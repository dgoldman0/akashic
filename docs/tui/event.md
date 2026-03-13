# akashic/tui/event.f — TUI Event Loop & Dispatch

**Layer:** 6  
**Lines:** 254  
**Prefix:** `TUI-EVT-` (public), `_TUI-EVT-` (internal)  
**Provider:** `akashic-tui-event`  
**Dependencies:** `keys.f`, `screen.f`, `focus.f`, `utils/term.f`

## Overview

Central coordination point that ties input polling, event dispatch,
timer callbacks, dirty-widget redraw, and screen flushing into a
single blocking loop.  One call to `TUI-EVT-LOOP` runs the entire
TUI application until `TUI-EVT-QUIT` is invoked (directly or via a
posted deferred action).

Not reentrant.  Uses BIOS `MS@` for timer ticks and KDOS `YIELD?`
for cooperative multitasking.

## Architecture

Each iteration of the loop performs the following steps in order:

1. **Poll input** — `KEY-POLL` into a 24-byte event buffer.
2. **Resize check** — if the event type is `KEY-T-RESIZE`, call the
   registered resize callback with `( w h )`.
3. **Global key handler** — if registered, call `( ev -- consumed? )`.
   A true return consumes the event.
4. **Focus dispatch** — if the event was not consumed, forward it to
   the focused widget via `FOC-DISPATCH`.
5. **Hardware resize poll** — `TERM-RESIZED?` checks the UART
   geometry RESIZED flag.  If set, reads `TERM-SIZE` and invokes
   the resize callback.  Complements the ANSI-based path.
6. **Drain posted actions** — execute all queued deferred actions (FIFO).
7. **Timer tick** — if enough time has elapsed since the last tick,
   invoke the tick callback.
8. **Draw dirty widgets** — walk the focus chain via `FOC-EACH` and
   redraw any widget with its dirty flag set.
9. **Flush screen** — `SCR-FLUSH` pushes the back-buffer to the terminal.
10. **Cooperative yield** — `YIELD?` returns the CPU slice to KDOS.

## API Reference

### Loop Control

| Word | Stack | Description |
|------|-------|-------------|
| `TUI-EVT-LOOP` | `( -- )` | Enter the event loop. Blocks until `TUI-EVT-QUIT` is called. Sets `_TUI-EVT-RUNNING` to TRUE, snapshots `MS@` for tick timing. |
| `TUI-EVT-QUIT` | `( -- )` | Signal the loop to exit after the current iteration. |

### Callback Registration

| Word | Stack | Description |
|------|-------|-------------|
| `TUI-EVT-ON-TICK` | `( xt -- )` | Register tick callback `( -- )`. Called once per tick interval. |
| `TUI-EVT-ON-RESIZE` | `( xt -- )` | Register resize callback `( w h -- )`. Called when a `KEY-T-RESIZE` event is received. |
| `TUI-EVT-ON-KEY` | `( xt -- )` | Register global key handler `( event-addr -- consumed? )`. Runs before focus dispatch; returning TRUE consumes the event. |

### Configuration

| Word | Stack | Description |
|------|-------|-------------|
| `TUI-EVT-TICK-MS!` | `( ms -- )` | Set the tick interval in milliseconds. Default: 100. |

### Deferred Action Queue

| Word | Stack | Description |
|------|-------|-------------|
| `TUI-EVT-POST` | `( xt -- )` | Enqueue a deferred action for execution during the drain phase. FIFO order. Silently drops if the queue is full (max 8). |

### Display

| Word | Stack | Description |
|------|-------|-------------|
| `TUI-EVT-REDRAW` | `( -- )` | Request a full redraw on the next iteration. Sets the global redraw flag; during draw-dirty, all widgets in the focus chain are marked dirty before drawing. |

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_TUI-EVT-DRAIN-POSTED` | `( -- )` | Execute all queued deferred actions, oldest first, until the queue is empty. |
| `_TUI-EVT-CHECK-TICK` | `( -- )` | Compare `MS@` against `_TUI-EVT-LAST-TICK`; if elapsed >= tick interval, invoke the tick callback and update the snapshot. |
| `_TUI-EVT-CHECK-RESIZE` | `( ev -- )` | If event type is `KEY-T-RESIZE`, extract width/height from code/mods fields and call the resize callback. |
| `_TUI-EVT-DRAW-ONE` | `( widget -- )` | Draw a single widget if its dirty flag is set. |
| `_TUI-EVT-DRAW-DIRTY` | `( -- )` | If the redraw flag is set, mark all chain widgets dirty first. Then draw every dirty widget via `FOC-EACH`. |

## State Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `_TUI-EVT-RUNNING` | 0 | Loop active flag (TRUE inside loop). |
| `_TUI-EVT-TICK-MS` | 100 | Tick interval in milliseconds. |
| `_TUI-EVT-LAST-TICK` | 0 | `MS@` snapshot of last tick fire. |
| `_TUI-EVT-ON-TICK-XT` | 0 | Tick callback xt (0 = none). |
| `_TUI-EVT-ON-RESIZE-XT` | 0 | Resize callback xt (0 = none). |
| `_TUI-EVT-ON-KEY-XT` | 0 | Global key handler xt (0 = none). |
| `_TUI-EVT-REDRAW-FLAG` | 0 | Non-zero requests full redraw. |
| `_TUI-EVT-KEY-BUF` | — | 24-byte key event buffer (3 cells). |
| `_TUI-EVT-POST-Q` | — | 8-entry circular FIFO for deferred actions. |
| `_TUI-EVT-POST-HEAD` | 0 | Next write slot (monotonic). |
| `_TUI-EVT-POST-TAIL` | 0 | Next read slot (monotonic). |

## Guard Support

When `GUARDED` is defined, all public words are wrapped with
`_tui-evt-guard WITH-GUARD` for thread-safety.

## Design Notes

- **Single event buffer.** Only one key event is buffered per
  iteration.  `KEY-POLL` returns FALSE when no input is available,
  so the loop simply skips dispatch.
- **Deferred actions** decouple callbacks from state mutation.  A
  widget handler that wants to quit posts `' TUI-EVT-QUIT
  TUI-EVT-POST` instead of calling `TUI-EVT-QUIT` mid-dispatch.
- **Monotonic head/tail.** The FIFO uses unbounded head/tail
  counters with `MOD _TUI-EVT-POST-MAX` to wrap.  Overflow is
  detected by checking `head - tail >= max`.
- **Tick timing.** Uses `MS@` (BIOS 64-bit monotonic ms uptime) for
  elapsed-time comparison.  The last-tick snapshot is updated after
  each callback invocation to prevent drift accumulation.
- **Dirty redraw.** `TUI-EVT-REDRAW` sets a flag; the draw phase
  then calls `WDG-DIRTY` on every chain entry before the normal
  per-widget `WDG-DIRTY?` / `WDG-DRAW` pass.
