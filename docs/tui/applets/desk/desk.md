# akashic/tui/applets/desk/desk.f — TUI Multi-App Desktop

**Lines:** ~1007  
**Prefix:** `DESK-` (public), `_DESK-` / `_DTH-` / `_HB-` / `_DHBAR-` (internal)  
**Provider:** `akashic-tui-desk`  
**Location:** `akashic/tui/applets/desk/desk.f`  
**Dependencies:** [`app-shell.f`](../../app-shell.md), [`app-desc.f`](../../app-desc.md),
[`uidl-tui.f`](../../uidl-tui.md), [`screen.f`](../../screen.md),
[`region.f`](../../region.md), [`draw.f`](../../draw.md),
[`keys.f`](../../keys.md), [`color.f`](../../color.md),
[`toml.f`](../../../../utils/toml.md), [`binimg.f`](../../../../utils/binimg.md),
`liraq/uidl.f`

## Why `applets/`?

Most Akashic TUI modules are standalone composable components — each
one provides a self-contained service.  Modules in `applets/` are
*applets*: APP-DESC applications hosted by
[`app-shell.f`](../../app-shell.md) (or by the desk itself).  They
are not independently composable components but complete applications
that depend on the shell lifecycle.

## Overview

Multi-app desktop with dynamic tiling.  Runs as a **normal APP-DESC
applet** inside [`app-shell.f`](../../app-shell.md) — no private
event loop.

The desk delegates all terminal ownership, event dispatch, paint
cycling, and tick timing to the shell:

## Architecture

```
  app-shell.f           (terminal via term-init.f, event loop, paint cycle)
    └── DESK-DESC       (APP-DESC callbacks)
          ├── DESK-INIT-CB     → reset state
          ├── DESK-EVENT-CB    → shortcuts, route to focused sub-app
          ├── DESK-TICK-CB     → tick all alive sub-apps
          ├── DESK-PAINT-CB    → paint tiles, dividers, taskbar
          └── DESK-SHUTDOWN-CB → close all sub-apps
```

Sub-apps are isolated via per-app **UIDL context** buffers (~97 KiB each),
which save/restore the 15 UIDL scalar variables and 10 pool arrays.

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

Each sub-app occupies a heap-allocated 64-byte slot, linked in a singly
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
| +56 | `UIDL-BUF` | Shell-loaded UIDL file buffer (0 = none) |

## ASHELL-QUIT Interception

When a sub-app calls `ASHELL-QUIT`, `DESK-EVENT-CB` intercepts it
via the public API:

1. Checks `ASHELL-QUIT-PENDING?` (returns true when quit is pending)
2. Calls `ASHELL-CANCEL-QUIT` (re-arms the event loop)
3. Calls `DESK-CLOSE-ID` for that sub-app's slot
4. Returns −1 (consumed) to the shell

This means sub-app quit closes a tile, not the whole desktop.

## Theme System

The desk has 14 colour slot variables (`_DTH-*`) controlling the
taskbar, active/minimized/pinned entries, dividers, and clock.
`_DESK-THEME-DEFAULTS` sets a dark-blue palette.  All slots can be
overridden via a TOML config file under `[desk.theme]`.

| TOML Key | Slot | Default |
|----------|------|---------|
| `taskbar-fg` | Normal taskbar text | 15 (white) |
| `taskbar-bg` | Taskbar background | 17 (dark blue) |
| `active-fg` | Focused slot label | 0 (black) |
| `active-bg` | Focused slot background | 12 (bright blue) |
| `minimized-fg` | Minimized slot label | 8 (dark gray) |
| `minimized-bg` | Minimized slot background | 17 |
| `pinned-fg` | Hotbar pinned entry text | 244 (medium gray) |
| `pinned-bg` | Hotbar pinned background | 0 (black) |
| `divider-fg` | Tile divider lines | 240 (bright gray) |
| `divider-bg` | Divider background | 0 |
| `clock-fg` | Clock text | 14 (cyan) |
| `clock-bg` | Clock background | 17 |

Colour values are parsed by `TUI-PARSE-COLOR`: CSS named colours,
`#RRGGBB`, `#RGB`, or raw 0–255 xterm-256 indices.

## Hotbar (Pinned Apps)

The hotbar is a row of up to 12 pinned application shortcuts rendered
in the taskbar after the running-app entries.  Each entry is defined
by a `[[desk.hotbar]]` array-of-tables section in the TOML config:

```toml
[[desk.hotbar]]
label = "Pad"
file  = "pad.m64"
desc  = "PAD-DESC"
```

Entries start as **pinned** (not launched) and appear in a dimmed
`<Label>` style.  When launched (via `Alt+H`), the desk loads
the `.m64` binary via `IMG-LOAD-EXEC` (using an `EVALUATE` trick
to inject the filename), then `EVALUATE`s the `desc` word to obtain
an APP-DESC address, and calls `DESK-LAUNCH`.  The entry then shows
as `[Label]` in normal taskbar style.

> **Note:** KDOS does not have `INCLUDED`.  All applet code is loaded
> as pre-compiled `.m64` binary images.  See
> [app-loader.md](../../app-loader.md) for the full packaging pipeline.

Hotbar entry structure (7 cells = 56 bytes):

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | label-a | Label string address (zero-copy into TOML buffer) |
| +8 | label-u | Label string length |
| +16 | file-a | File path address |
| +24 | file-u | File path length |
| +32 | desc-a | Descriptor word name address |
| +40 | desc-u | Descriptor word name length |
| +48 | slot-id | Desk slot ID (0 = not launched) |

## Config Loading

`DESK-LOAD-CONFIG ( addr len -- )` takes a TOML buffer and loads
both the theme (`_DESK-LOAD-THEME`) and hotbar (`_DESK-LOAD-HOTBAR`).

To supply a config before `DESK-RUN`, store the buffer address/length
in `_DESK-CFG-A` / `_DESK-CFG-L`.  `DESK-INIT-CB` will call
`DESK-LOAD-CONFIG` automatically if these are non-zero.

A sample config template is provided in
[desk.toml](../../../../akashic/tui/applets/desk/desk.toml).

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

### Configuration

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-LOAD-CONFIG` | `( addr len -- )` | Load TOML buffer — applies theme and hotbar. |

### Startup

| Word | Stack | Description |
|------|-------|-------------|
| `DESK-QUEUE-LAUNCH` | `( desc -- )` | Set a startup applet to launch automatically when the desktop initialises.  Call before `DESK-RUN`. |
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
| Alt+H | Launch next unlaunched hotbar entry |

Alt+Arrow, Alt+Del, Alt+End, and Alt+PgDn are reserved by&nbsp;the shell
cursor and never reach desk’s event handler.

## Mouse Dispatch

When the shell cursor synthesises a click (or a real mouse event
arrives), `DESK-EVENT-CB` detects the `KEY-T-MOUSE` type via
`ASHELL-MOUSE?` and routes to `_DESK-DISPATCH-MOUSE` before any
keyboard handling.

**Tile hit-test** — `_DESK-TILE-AT ( row col -- slot | 0 )` walks the
linked-list of visible slots and checks whether `(row, col)` falls
within each tile’s `RGN-ROW`/`RGN-COL`/`RGN-H`/`RGN-W` bounds.
Returns the first matching slot, or 0 on miss.

**Dispatch** — `_DESK-DISPATCH-MOUSE` extracts row, col, and button
from the event, hits-tests tiles, context-switches to the winning
slot, then calls `UTUI-DISPATCH-MOUSE` with coordinates local to
that sub-app’s UIDL tree.  If no tile is hit, the event is dropped.

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

The UCTX system (`UCTX-ALLOC`, `UCTX-FREE`, `UCTX-SAVE`, `UCTX-RESTORE`,
`UCTX-CLEAR`, `UCTX-TOTAL`) is defined in `uidl-tui.f` §18b, which owns
the private variables being serialised.

Context switch (`_DESK-CTX-SWITCH`) saves the current sub-app's globals
via `CMOVE` and restores the target's.  Only one sub-app's context is
live at a time.  Desk delegates to `ASHELL-CTX-SWITCH` and
`ASHELL-CTX-SAVE` — it never calls `UCTX-SAVE`/`UCTX-RESTORE` directly.

## Internal Sections

| § | Title | Description |
|---|-------|-------------|
| 1 | Slot Struct | 64-byte linked-list node, state enum |
| 2 | DESK Global State | Head, focus, ID counter, layout prefs |
| 2b | Theme | 14 colour slot variables, defaults, TOML loader |
| 2c | Hotbar | Pinned-app entry array, TOML loader, painting |
| 2d | Config Loader | `DESK-LOAD-CONFIG` master loader |
| 3 | Linked-List Helpers | Find, unlink, append, count |
| 4 | Visible Collection Buffer | Up to 64 visible slots |
| 5 | Tiling Layout Engine | Grid, tile sizes, region assignment, dividers |
| 6 | Context Switching | Save/restore/switch helpers (delegates to shell) |
| 7 | Launch & Close | `DESK-LAUNCH`, `DESK-CLOSE-ID` |
| 8 | Focus/Minimize/Restore | State transitions, auto-focus |
| 9 | Taskbar Painter | Per-item styled painting + hotbar + divider |
| 10 | APP-DESC Callbacks | Init, event, tick, paint, shutdown |
| 10b | Mouse Dispatch | Tile hit-test + per-tile UTUI-DISPATCH-MOUSE routing |
| 11 | Descriptor & Entry | `DESK-DESC`, `_DESK-FILL-DESC`, `DESK-RUN` |
| 12 | Guard | `WITH-GUARD` wrappers for concurrency safety |

## Guard-Protected Words

Under `[DEFINED] GUARDED`:  `DESK-LAUNCH`, `DESK-CLOSE-ID`,
`DESK-FOCUS-ID`, `DESK-MINIMIZE-ID`, `DESK-RESTORE`, `DESK-FULLFRAME!`,
`DESK-TOGGLE-VH`, `DESK-RELAYOUT`, `DESK-SLOT-COUNT`, `DESK-VCOUNT`,
`DESK-RUN`.
