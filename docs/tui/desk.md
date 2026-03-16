# akashic/tui/desk.f — TUI Multi-App Desktop

**Lines:** ~640  
**Prefix:** `DESK-` (public), `_DESK-` (internal)  
**Provider:** `akashic-tui-desk`  
**Dependencies:** `app-shell.f`, `app-desc.f`, `uidl-tui.f`, `screen.f`,
`region.f`, `draw.f`, `keys.f`, `liraq/uidl.f`

## Overview

Multi-app desktop with dynamic tiling.  Runs as a **normal APP-DESC app**
inside `app-shell.f` — no private event loop.  Replaces `app-compositor.f`.

The compositor had its own event loop, tick system, paint system, and resize
handler — all duplicating `app-shell.f`.  The DESK delegates to the shell:

| Concern | Compositor (old) | DESK (new) |
|---------|------------------|------------|
| Event loop | `_COMP-LOOP` (private) | Shell's `_ASHELL-LOOP` |
| Paint cycle | `COMP-PAINT-ALL` | Shell calls `DESK-PAINT-CB` |
| Tick dispatch | `COMP-TICK-ALL` (private timer) | Shell calls `DESK-TICK-CB` |
| Terminal init | `APP-INIT` / `APP-SHUTDOWN` | Shell owns terminal |
| Quit | `COMP-QUIT` | `ASHELL-QUIT` shuts down shell |

Sub-apps are isolated via per-app **UIDL context** buffers (~97 KiB each),
which save/restore the 15 UIDL scalar variables and 10 pool arrays.

## Architecture

```
  app-shell.f         (event loop, terminal, paint cycle)
    └── DESK-DESC     (APP-DESC callbacks)
          ├── DESK-EVENT-CB    → shortcuts, route to focused sub-app
          ├── DESK-TICK-CB     → tick all alive sub-apps
          ├── DESK-PAINT-CB    → paint tiles, dividers, taskbar
          ├── DESK-INIT-CB     → reset state
          └── DESK-SHUTDOWN-CB → close all sub-apps
```

## Tiling Algorithm

Given **N** visible apps and usable area **W × H** (H = SCR-H − 1 for taskbar):

- **V-pref** (default): `cols = ceil(√N)`, `rows = ceil(N / cols)`
- **H-pref**: `rows = ceil(√N)`, `cols = ceil(N / rows)`
- Tile size: `tw = (W − (cols−1)) / cols`, `th = (H − (rows−1)) / rows`
- Last column/row absorbs remainder pixels
- 1-cell dividers drawn between adjacent tiles

Toggle with `DESK-TOGGLE-VH`.  Full-frame mode (`DESK-FULLFRAME!`) shows
only the focused app and hides dividers.

## Slot Structure

Each sub-app occupies a heap-allocated 56-byte slot, linked in a singly
linked list.  Slot IDs are monotonic (1, 2, 3, …).

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | `DESC` | APP-DESC pointer |
| +8 | `RGN` | Region handle (0 if no region) |
| +16 | `STATE` | 0=empty, 1=running, 2=minimized, 3=focused |
| +24 | `UCTX` | UIDL context pointer (0 = no UIDL) |
| +32 | `HAS-UIDL` | Flag: app has UIDL? |
| +40 | `NEXT` | → next slot in list (0 = tail) |
| +48 | `ID` | Unique slot ID |

## ASHELL-QUIT Interception

When a sub-app calls `ASHELL-QUIT` (sets `_ASHELL-RUNNING` to 0),
`DESK-EVENT-CB` intercepts it:

1. Re-sets `_ASHELL-RUNNING` to −1 (keeps shell alive)
2. Calls `DESK-CLOSE-ID` for that sub-app's slot
3. Returns −1 (consumed) to the shell

This means sub-app quit closes a tile, not the whole desktop.

## API Reference

### Sub-App Management

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-LAUNCH` | `( desc -- id )` | Launch sub-app from APP-DESC.  Returns slot ID (−1 on failure). |
| `DESK-CLOSE-ID` | `( id -- )` | Close sub-app by slot ID.  Calls SHUTDOWN-XT, frees UIDL context. |
| `DESK-FOCUS-ID` | `( id -- )` | Focus sub-app by slot ID.  No-op if minimized or not found. |
| `DESK-MINIMIZE-ID` | `( id -- )` | Minimize sub-app (alive but hidden). |
| `DESK-RESTORE` | `( -- )` | Restore last minimized app. |

### Layout

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-RELAYOUT` | `( -- )` | Recompute tile grid.  Called automatically on launch/close/minimize. |
| `DESK-FULLFRAME!` | `( flag -- )` | Toggle full-frame mode (show only focused app). |
| `DESK-TOGGLE-VH` | `( -- )` | Toggle V-pref / H-pref tiling. |

### Queries

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-SLOT-COUNT` | `( -- n )` | Number of live slots (all states). |
| `DESK-VCOUNT` | `( -- n )` | Number of visible (non-minimized) slots. |

### Entry Point

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-RUN` | `( -- )` | Fill `DESK-DESC`, call `ASHELL-RUN`.  Blocks until shell exits. |

## Keyboard Shortcuts

All shortcuts require **Alt** modifier:

| Key | Action |
|-----|--------|
| Alt+1 … Alt+9 | Focus slot by ID |
| Alt+Tab | Cycle focus to next visible slot |
| Alt+M | Minimize focused slot |
| Alt+R | Restore last minimized |
| Alt+F | Toggle full-frame mode |
| Alt+L | Toggle V/H tiling preference |
| Alt+W | Close focused slot |

## UIDL Context System

Each sub-app with a UIDL document gets a ~97 KiB context buffer that
captures:

- **15 scalar variables**: element count, attribute count, string position,
  root pointer, subscription count, elem base, doc-loaded flag, state,
  focus pointer, action count, shortcut count, overlay count, saved focus,
  skip-children flag, region handle.
- **10 pool arrays**: elements (32 KiB), attributes (20 KiB), strings
  (12 KiB), hash (2 KiB), hash-IDs (4 KiB), subscriptions (3 KiB),
  sidecars (20 KiB), actions (1.5 KiB), shortcuts (2 KiB), overlay
  buffer (0.5 KiB).

Context switch (`_DESK-CTX-SWITCH`) saves the current sub-app's globals
via `CMOVE` and restores the target's.  Only one sub-app's context is
live at a time.

## Internal Sections

| § | Title | Description |
|---|-------|-------------|
| 1 | UIDL Context Save/Restore | `UCTX-*` words, variable/pool tables |
| 2 | Slot Struct | 56-byte linked-list node, state enum |
| 3 | DESK Global State | Head, focus, ID counter, layout prefs |
| 4 | Linked-List Helpers | Find, unlink, append, count |
| 5 | Visible Collection Buffer | Up to 64 visible slots |
| 6 | Tiling Layout Engine | Grid, tile sizes, region assignment, dividers |
| 7 | Context Switching | Save/restore/switch helpers |
| 8 | Launch & Close | `DESK-LAUNCH`, `DESK-CLOSE-ID` |
| 9 | Focus/Minimize/Restore | State transitions, auto-focus |
| 10 | Taskbar Painter | Bottom-row status bar |
| 11 | APP-DESC Callbacks | Init, event, tick, paint, shutdown |
| 12 | Descriptor & Entry | `DESK-DESC`, `_DESK-FILL-DESC`, `DESK-RUN` |
| 13 | Guard | `WITH-GUARD` wrappers for concurrency safety |

## Guard-Protected Words

Under `[DEFINED] GUARDED`:  `DESK-LAUNCH`, `DESK-CLOSE-ID`,
`DESK-FOCUS-ID`, `DESK-MINIMIZE-ID`, `DESK-RESTORE`, `DESK-FULLFRAME!`,
`DESK-TOGGLE-VH`, `DESK-RELAYOUT`, `DESK-SLOT-COUNT`, `DESK-VCOUNT`,
`DESK-RUN`.
