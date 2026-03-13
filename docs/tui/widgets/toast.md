# akashic/tui/widgets/toast.f — Transient Notification Widget

**Layer:** 7  
**Lines:** 215  
**Prefix:** `TST-` (public), `_TST-` (internal)  
**Provider:** `akashic-tui-toast`  
**Dependencies:** `draw.f`, `box.f`, `region.f`

## Overview

Brief popup messages that auto-dismiss after a timeout.  Rendered as
a bordered box at a configurable anchor position (defaults to
bottom-right of the screen).

Only one toast is visible at a time.  Showing a new toast replaces
the current one.  The caller must call `TST-TICK` from the event-loop
tick callback to drive the auto-dismiss timer.

### Singleton Design

The toast uses **module-level state** (VARIABLEs) rather than a widget
descriptor, because it does not participate in the focus chain or
receive key events.  It is drawn as an overlay after all widgets.

### Toast Box

- Width = message length + 4 (border + 1 padding each side)
- Height = 3 (top border, text row, bottom border)
- Box style defaults to `BOX-ROUND` (lazy-initialized on first draw)

## State Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `_TST-MSG-A` | 0 | Message string address |
| `_TST-MSG-L` | 0 | Message string length |
| `_TST-DEADLINE` | 0 | `MS@` value at which to auto-dismiss |
| `_TST-ACTIVE` | 0 | TRUE while a toast is visible |
| `_TST-ANCHOR-ROW` | 0 | Anchor row (0 = auto bottom-aligned) |
| `_TST-ANCHOR-COL` | 0 | Anchor column (0 = auto right-aligned) |
| `_TST-FG` | 7 | Foreground colour |
| `_TST-BG` | 0 | Background colour |
| `_TST-BOX` | 0 | Box style (set on first use or via `TST-STYLE!`) |

## API Reference

### Display

| Word | Stack | Description |
|------|-------|-------------|
| `TST-SHOW` | `( msg-a msg-u timeout-ms -- )` | Show a toast; replaces any current toast |
| `TST-DISMISS` | `( -- )` | Manually dismiss current toast |
| `TST-DRAW` | `( -- )` | Render toast overlay (call after all widgets draw) |
| `TST-VISIBLE?` | `( -- flag )` | TRUE if a toast is currently displayed |

### Timer

| Word | Stack | Description |
|------|-------|-------------|
| `TST-TICK` | `( -- )` | Call from event loop tick; auto-dismisses expired toasts |

### Configuration

| Word | Stack | Description |
|------|-------|-------------|
| `TST-POSITION!` | `( row col -- )` | Set toast anchor position (0 0 = auto) |
| `TST-STYLE!` | `( fg bg box-style -- )` | Set colours and box style |

## Design Notes

- **Auto-positioning.** When anchor is `(0, 0)`, the toast is placed
  at `(SCR-H - 3, SCR-W - box-w)` — bottom-right corner.
- **Timer model.** `TST-SHOW` computes `MS@ + timeout-ms` as the
  deadline.  `TST-TICK` compares `MS@` against the deadline and
  calls `TST-DISMISS` when expired.
- **Overlay rendering.** `TST-DRAW` switches to the root region
  (`RGN-ROOT`), fills the background, draws the box border, and
  renders the message text.  It should be called in the app's draw
  phase after all widgets.
- **Lazy box init.** The box style defaults to `BOX-ROUND`, set on
  first `TST-DRAW` if not explicitly configured via `TST-STYLE!`.
- When `GUARDED` is defined, every public word is wrapped with
  `WITH-GUARD` for concurrency safety.
