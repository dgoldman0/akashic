# akashic/tui/app-shell.f — TUI Application Shell Runtime

**Layer:** 7 (above term-init.f)  
**Lines:** ~449  
**Prefix:** `ASHELL-` (public), `_ASHELL-` (internal)  
**Provider:** `akashic-tui-app-shell`  
**Dependencies:** `app-desc.f`, [`cogs/term-init.f`](cogs/term-init.md), `keys.f`, `screen.f`, `region.f`, `draw.f`,
`focus.f`, `uidl-tui.f`, `utils/term.f`

## Overview

Headless runtime that owns the terminal, event loop, paint cycle, and
UIDL integration.  Apps provide callbacks via an **APP-DESC** descriptor;
the shell has no UI of its own.

Terminal management (alternate screen, screen buffer, cursor) comes
from [`cogs/term-init.f`](cogs/term-init.md) — the same cog that
`app.f` uses for standalone apps.  This means app-shell.f does **not**
depend on `app.f`; the standalone and applet paths are fully
independent.

`ASHELL-RUN` blocks until the app calls `ASHELL-QUIT` or a callback
throws.  Terminal state is always restored via `CATCH`-guarded teardown.

Not reentrant.  One app at a time.

> **Standalone vs Applet.**  Standalone TUI apps use [`app.f`](app.md)
> directly (they own the event loop via `APP-RUN`).  Applets are hosted
> here — one at a time via `ASHELL-RUN`, or composited by
> [`desk.f`](applets/desk/desk.md).  Both paths share terminal init from
> [`cogs/term-init.f`](cogs/term-init.md).

## APP-DESC — Application Descriptor

The 96-byte APP-DESC struct is defined in
[app-desc.f](app-desc.md) and pulled in via `REQUIRE app-desc.f`.

96 bytes (12 cells).  Allocate with `CREATE my-desc APP-DESC ALLOT`,
zero-fill with `APP-DESC-INIT`.  Unused callback fields must be 0
(the shell skips them).

| Offset | Field | Stack | Description |
|--------|-------|-------|-------------|
| +0 | `APP.INIT-XT` | `( -- )` | Called once during setup |
| +8 | `APP.EVENT-XT` | `( ev -- flag )` | Key/mouse handler; return true if consumed |
| +16 | `APP.TICK-XT` | `( -- )` | Periodic tick (timers, animation) |
| +24 | `APP.PAINT-XT` | `( -- )` | Custom widget painting (after UIDL) |
| +32 | `APP.SHUTDOWN-XT` | `( -- )` | Cleanup on exit |
| +40 | `APP.UIDL-A` | addr | UIDL XML source address (0 = no UIDL) |
| +48 | `APP.UIDL-U` | u | UIDL XML source length |
| +56 | `APP.WIDTH` | u | Preferred terminal width (0 = auto) |
| +64 | `APP.HEIGHT` | u | Preferred terminal height (0 = auto) |
| +72 | `APP.TITLE-A` | addr | Terminal title address (0 = none) |
| +80 | `APP.TITLE-U` | u | Terminal title length |
| +88 | `APP.FLAGS` | u | Reserved (0) |

Each field accessor takes `( desc -- addr )` and returns the address of
that field within the descriptor, suitable for `@` or `!`.

## API Reference

### Lifecycle

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-RUN` | `( desc -- )` | Run app.  Blocks until quit or throw.  Always restores terminal. |
| `ASHELL-QUIT` | `( -- )` | Signal the event loop to exit after the current iteration. Safe to call from any callback, including init. |

### State Queries

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-DESC` | `( -- desc )` | Current app descriptor (0 if not running). |
| `ASHELL-REGION` | `( -- rgn )` | Root region (full screen). |
| `ASHELL-UIDL?` | `( -- flag )` | True if a UIDL document is loaded. |

### Paint & Tick

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-DIRTY!` | `( -- )` | Request repaint next frame. |
| `ASHELL-TICK-MS!` | `( ms -- )` | Set tick interval (default 50 ms). |

### Toast

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-TOAST` | `( addr u ms -- )` | Show a toast message for *ms* milliseconds. Auto-dismisses. |
| `ASHELL-TOAST-VISIBLE?` | `( -- flag )` | True if a toast is currently showing. |

### Deferred Actions

| Word | Stack | Description |
|------|-------|-------------|
| `ASHELL-POST` | `( xt -- )` | Enqueue xt for execution before next paint. FIFO, max 16 entries. Drops silently if full. |

### Descriptor Helpers

| Word | Stack | Description |
|------|-------|-------------|
| `APP-DESC` | `( -- 96 )` | Descriptor size constant. |
| `APP-DESC-INIT` | `( desc -- )` | Zero-fill a descriptor. |

## Lifecycle Sequence

### ASHELL-RUN

```
ASHELL-RUN
  ├── _ASHELL-SETUP (via CATCH)
  │     1. Store descriptor
  │     2. APP-INIT (terminal + screen buffer, from term-init.f)
  │     3. Set terminal title (if provided)
  │     4. Create root region (full screen)
  │     5. UTUI-LOAD UIDL document (if provided)
  │     6. Set RUNNING flag, init tick timer
  │     7. Call APP.INIT-XT (app may ASHELL-QUIT here)
  │     8. KEY-TIMEOUT! for ESC sequences
  │     9. Mark dirty, initial paint + flush
  │
  ├── _ASHELL-LOOP (via CATCH)
  │     BEGIN RUNNING WHILE
  │       1. KEY-POLL → resize / dispatch
  │       2. Hardware resize poll
  │       3. Drain deferred actions
  │       4. Timer tick check
  │       5. Paint if dirty
  │       6. YIELD?
  │     REPEAT
  │
  └── _ASHELL-TEARDOWN (always runs)
        1. APP.SHUTDOWN-XT callback
        2. UTUI-DETACH (if UIDL loaded)
        3. RGN-FREE root region
        4. APP-SHUTDOWN (terminal restore, from term-init.f)
        5. Reset all shell state
```

If `_ASHELL-SETUP` throws, teardown still runs and the throw is
re-raised.  If `_ASHELL-LOOP` throws, teardown runs and the throw
is re-raised.  The terminal is always left clean.

### Event Dispatch Order

For each key event:

1. **App handler** — `APP.EVENT-XT` gets first crack.  If it returns
   true, the event is consumed and the screen is marked dirty.
2. **UIDL dispatch** — `UTUI-DISPATCH-KEY` routes to shortcuts and
   focused elements.  If it returns true, the screen is marked dirty.
3. **Drop** — unhandled events are discarded.

### Paint Order

1. `RGN-ROOT` — reset region to full screen
2. `UTUI-PAINT` — UIDL elements (if loaded)
3. `APP.PAINT-XT` — app's custom widget drawing (on top of UIDL)
4. Toast overlay — `_ASHELL-DRAW-TOAST` (if visible)
5. `RGN-ROOT` — reset region
6. `SCR-FLUSH` — diff and emit to terminal

### Resize Handling

Two resize detection paths:

- **Structured resize events** from `KEY-POLL` — the event carries
  the new width and height.
- **Hardware poll** via `TERM-RESIZED?` — catches SIGWINCH-style
  resizes that don't arrive as key events.

Both call `_ASHELL-ON-RESIZE`, which: resizes the screen buffer,
recreates the root region, relayouts UIDL (if loaded), marks dirty.

### Automatic Dirty Propagation

Apps following the browser model never call `ASHELL-DIRTY!` directly.
Instead, the framework detects changes automatically:

- **`_UTUI-NEEDS-PAINT` flag** — set by the `UIDL-DIRTY!` hook
  (in `uidl.f`) whenever any element is dirtied.  Also set by
  `UTUI-ADD-ELEM`, `UTUI-REMOVE-ELEM`, `UTUI-SET-ATTR`, and
  `UTUI-WIDGET-SET`.
- **After TICK-XT** — `_ASHELL-CHECK-TICK` checks
  `_UTUI-NEEDS-PAINT` and converts it to `ASHELL-DIRTY!`.
- **At paint start** — `_ASHELL-PAINT` also checks the flag, so
  changes made outside the tick cycle are still caught.

This means: modify the DOM or widget state, and the framework repaints.
No manual dirty signalling needed.

## Toast Facility

`ASHELL-TOAST` provides a shell-level toast overlay.  The app passes
a message string and a duration in milliseconds.  The shell handles
all rendering and timing.

```forth
S" Saved!" 2000 ASHELL-TOAST    \ toast appears for 2 seconds
```

The toast is drawn last in the paint cycle (on top of everything).
Expiry is checked in `_ASHELL-CHECK-TICK` — when the toast expires,
the shell auto-dirties to clear it.  No timer or paint code in the
app.

## Cooperative Multitasking

One `YIELD?` per loop iteration.  `YIELD?` checks the per-core KDOS
preemption flag (set by the timer ISR at the `TIME-SLICE` interval).
If set, context-switches to the scheduler.  Otherwise no-op.

The loop is non-blocking — `KEY-POLL` returns immediately, paint
only runs when dirty, tick only fires at interval.  Other KDOS tasks
get regular time slices.

### Deferred Action Queue

`ASHELL-POST` enqueues an xt into a 16-slot FIFO.  All queued
actions drain every loop iteration, after event dispatch and before
tick/paint.  Use for work that shouldn't run inside a callback
(e.g., modifying the UIDL tree, opening dialogs).

## Concurrency Guards

When `GUARDED` is defined at compile time, all public words are
wrapped with `WITH-GUARD` for thread safety:

`ASHELL-RUN`, `ASHELL-QUIT`, `ASHELL-DIRTY!`, `ASHELL-REGION`,
`ASHELL-TICK-MS!`, `ASHELL-POST`, `ASHELL-UIDL?`, `ASHELL-DESC`,
`ASHELL-TOAST`, `ASHELL-TOAST-VISIBLE?`.

Currently `GUARDED` is not defined, so guards are inactive.

## Usage Examples

### Minimal App (No UIDL)

```forth
REQUIRE tui/app-shell.f

: my-event  ( ev -- flag )
    @ 113 = IF          \ 'q' pressed
        ASHELL-QUIT -1
    ELSE 0 THEN ;

CREATE my-desc APP-DESC ALLOT  my-desc APP-DESC-INIT
' my-event  my-desc APP.EVENT-XT !

my-desc ASHELL-RUN
```

### UIDL App

```forth
REQUIRE tui/app-shell.f

CREATE my-uidl 256 ALLOT
S" <uidl><region><label text=Hello/></region></uidl>"
my-uidl SWAP MOVE

: my-init  ( -- )
    S" lbl" UTUI-BY-ID  ( elem )
    \ ... wire up widgets ...
    ;

: my-event  ( ev -- flag )
    @ 27 = IF ASHELL-QUIT -1 ELSE 0 THEN ;

CREATE my-desc APP-DESC ALLOT  my-desc APP-DESC-INIT
' my-init   my-desc APP.INIT-XT !
' my-event  my-desc APP.EVENT-XT !
my-uidl     my-desc APP.UIDL-A !
49          my-desc APP.UIDL-U !

my-desc ASHELL-RUN
```

### Quit From Init

```forth
: my-init  ( -- )
    \ do setup, decide to bail
    ASHELL-QUIT ;
```

This works because the RUNNING flag is set *before* the init callback.

## Internal State

| Variable | Default | Purpose |
|----------|---------|---------|
| `_ASHELL-DESC` | 0 | Current descriptor |
| `_ASHELL-RGN` | 0 | Root region address |
| `_ASHELL-RUNNING` | 0 | Loop active flag |
| `_ASHELL-DIRTY` | 0 | Repaint needed flag |
| `_ASHELL-HAS-UIDL` | 0 | UIDL document loaded flag |
| `_ASHELL-TICK-MS` | 50 | Tick interval (ms) |
| `_ASHELL-LAST-TICK` | 0 | `MS@` of last tick |
| `_ASHELL-EV` | — | 24-byte key event buffer |
| `_ASHELL-POST-Q` | — | 16-slot deferred action FIFO |

| `_ASHELL-TOAST-MSG` | 0 0 | Toast message addr + len (2 cells) |
| `_ASHELL-TOAST-EXPIRY` | 0 | Toast `MS@` deadline |
| `_ASHELL-TOAST-WAS-VIS` | 0 | Was-visible flag for expiry detection |

All state is reset to defaults by `_ASHELL-TEARDOWN`.
