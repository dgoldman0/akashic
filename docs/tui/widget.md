# akashic/tui/widget.f — Widget Common Header

**Layer:** 4A  
**Lines:** 234  
**Prefix:** `WDG-` (public), `_WDG-` (internal)  
**Provider:** `akashic-tui-widget`  
**Dependencies:** `region.f`

## Overview

Every TUI widget shares a uniform 5-cell header at offset +0.
This file defines the header layout, type constants, flag constants,
flag manipulation words, the revision that counts a widget's changes, and
polymorphic dispatch (`WDG-DRAW`, `WDG-HANDLE`).

Widget-specific data starts at offset +40 in each widget type.
The common header lets the event loop and focus manager iterate
widgets generically without knowing the concrete type.

## Widget Header (5 cells = 40 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | type | constant | `WDG-T-*` type tag |
| +8 | region | address | Region this widget occupies |
| +16 | draw-xt | xt | `( widget -- )` — draw into region |
| +24 | handle-xt | xt | `( event widget -- consumed? )` — handle input |
| +32 | flags | bitmask and count | Bits 0-15: visibility, focus, dirty, disabled. Bits 16-63: the revision |

## The revision

`WDG-REVISION` counts the changes to what a widget shows, so that anything
holding a copy of what it showed, such as UIDL's paint or a renderer's
snapshot, can tell whether the copy still holds. `WDG-DIRTY` moves it, and
so does each base word that changes a flag. Each widget's own words that
change what it shows move it too. A revision that has not moved means that
nothing the widget shows has changed. One that has moved may still show the
same, as when a canvas dot is set again; most setters compare first and
move nothing when given what the widget already has.

The dirty flag keeps its meaning for painting: a draw clears it, and
`WDG-FLAG!` can set it alone, to paint again without a change. Drawing,
querying and capturing move the revision only where they settle the
widget's view, and a view that moves is a change. The input field and the
text area scroll to keep the caret in view before they draw, the input
field also before it reports what it shows, and a dialog lays itself out in
its host's bounds before it paints. A paint never marks a widget dirty only
to make it draw, since `WDG-DRAW` draws a visible widget whether or not it
is dirty.

A widget word that may mark once per dot or glyph, while its module's guard
is held, uses `_WDG-CHANGED`, which is `WDG-DIRTY` without the guard a
`GUARDED` build wraps around it.

The revision shares the flags cell, so a flag and the revision change in one
store. It counts from 0 when the widget is made and wraps after 2^48
changes. Only `widget.f` writes the flags cell after a widget is made.

## Type Constants

| Constant | Value | Widget |
|----------|-------|--------|
| `WDG-T-LABEL` | 1 | Static text label |
| `WDG-T-INPUT` | 2 | Text input field |
| `WDG-T-LIST` | 3 | Scrollable list |
| `WDG-T-MENU` | 4 | Menu bar & dropdowns |
| `WDG-T-PROGRESS` | 5 | Progress bar / spinner |
| `WDG-T-TABLE` | 6 | Tabular data display |
| `WDG-T-DIALOG` | 7 | Modal dialog box |
| `WDG-T-TABS` | 8 | Tabbed panels |
| `WDG-T-SPLIT` | 9 | Split pane |
| `WDG-T-SCROLL` | 10 | Scroll container |
| `WDG-T-TREE` | 11 | Tree view |
| `WDG-T-STATUS` | 12 | Status bar |
| `WDG-T-TOAST` | 13 | Toast notification |
| `WDG-T-CANVAS` | 14 | Braille dot canvas |

## Flag Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `WDG-F-VISIBLE` | 1 | Widget is visible |
| `WDG-F-FOCUSED` | 2 | Widget has input focus |
| `WDG-F-DIRTY` | 4 | Widget needs redraw |
| `WDG-F-DISABLED` | 8 | Widget ignores input |

## API Reference

### Header Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `WDG-INIT` | `( addr type rgn draw-xt handle-xt -- )` | Fill a caller-owned header; sets flags to VISIBLE \| DIRTY |
| `WDG-TYPE` | `( widget -- type )` | Get type constant |
| `WDG-REGION` | `( widget -- rgn )` | Get region |
| `WDG-FLAGS` | `( widget -- flags )` | Get the raw flags cell, revision included |
| `WDG-REVISION` | `( widget -- n )` | How many times what the widget shows has changed |

### Flag Queries

| Word | Stack | Description |
|------|-------|-------------|
| `WDG-VISIBLE?` | `( widget -- flag )` | Is visible? |
| `WDG-FOCUSED?` | `( widget -- flag )` | Has focus? |
| `WDG-DIRTY?` | `( widget -- flag )` | Needs redraw? |
| `WDG-DISABLED?` | `( widget -- flag )` | Is disabled? |

### Flag Mutation

| Word | Stack | Description |
|------|-------|-------------|
| `WDG-SHOW` | `( widget -- )` | Set VISIBLE + DIRTY |
| `WDG-HIDE` | `( widget -- )` | Clear VISIBLE |
| `WDG-ENABLE` | `( widget -- )` | Clear DISABLED |
| `WDG-DISABLE` | `( widget -- )` | Set DISABLED + DIRTY |
| `WDG-FLAG!` | `( on? flag widget -- )` | Set or clear one flag, for owners that keep a widget's state in step with their own |
| `WDG-DIRTY` | `( widget -- )` | What the widget shows changed: move the revision and set DIRTY |
| `WDG-CLEAN` | `( widget -- )` | Clear DIRTY flag |
| `WDG-FOCUS-SET` | `( widget -- )` | Set FOCUSED + DIRTY without changing focus-chain membership |
| `WDG-FOCUS-CLR` | `( widget -- )` | Clear FOCUSED and set DIRTY without changing focus-chain membership |

Each of these words that changes a flag other than DIRTY moves the revision
and sets DIRTY. Setting a flag a widget already has moves nothing.

### Polymorphic Dispatch

| Word | Stack | Description |
|------|-------|-------------|
| `WDG-DRAW` | `( widget -- )` | If visible: activate region, call draw-xt, clear dirty |
| `WDG-HANDLE` | `( event widget -- consumed? )` | If not disabled: call handle-xt |

## Design Notes

- **No DEFER/IS.** Polymorphism uses execution tokens stored in
  descriptor fields. Each widget type's constructor sets draw-xt
  and handle-xt to its own internal words.
- **draw-xt signature:** `( widget -- )`. The region is already
  activated by `WDG-DRAW` before calling draw-xt.
- **handle-xt signature:** `( event widget -- consumed? )`. Returns
  TRUE (-1) if the event was consumed, FALSE (0) otherwise.
- **UI-owner dispatch:** in a `GUARDED` build, bounded header access and flag
  mutation retain `_wdg-guard`. `WDG-DRAW` and `WDG-HANDLE` deliberately run
  unwrapped on the UI owner core because they execute widget-provided code.
  Cross-core callers must post render/input work to that owner rather than
  invoking polymorphic callbacks concurrently.
- **Default flags:** New widgets are VISIBLE + DIRTY. Not FOCUSED
  (focus is managed by the focus chain in Layer 5).
