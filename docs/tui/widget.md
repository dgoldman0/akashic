# akashic/tui/widget.f — Widget Common Header

**Layer:** 4A  
**Lines:** 234  
**Prefix:** `WDG-` (public), `_WDG-` (internal)  
**Provider:** `akashic-tui-widget`  
**Dependencies:** `region.f`

## Overview

Every TUI widget shares a uniform 5-cell header at offset +0.
This file defines the header layout, type constants, flag constants,
flag manipulation words, and polymorphic dispatch (`WDG-DRAW`,
`WDG-HANDLE`).

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
| +32 | flags | bitmask | Visibility, focus, dirty, disabled |

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
| `WDG-TYPE` | `( widget -- type )` | Get type constant |
| `WDG-REGION` | `( widget -- rgn )` | Get region |
| `WDG-FLAGS` | `( widget -- flags )` | Get raw flags bitmask |

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
| `WDG-DIRTY` | `( widget -- )` | Set DIRTY flag |
| `WDG-CLEAN` | `( widget -- )` | Clear DIRTY flag |

### Polymorphic Dispatch

| Word | Stack | Description |
|------|-------|-------------|
| `WDG-DRAW` | `( widget -- )` | If visible: activate region, call draw-xt, clear dirty |
| `WDG-HANDLE` | `( event widget -- consumed? )` | If not disabled: call handle-xt |

### Internal

| Word | Stack | Description |
|------|-------|-------------|
| `_WDG-INIT` | `( addr type rgn draw-xt handle-xt -- )` | Fill header at addr; sets flags = VISIBLE \| DIRTY |

## Design Notes

- **No DEFER/IS.** Polymorphism uses execution tokens stored in
  descriptor fields. Each widget type's constructor sets draw-xt
  and handle-xt to its own internal words.
- **draw-xt signature:** `( widget -- )`. The region is already
  activated by `WDG-DRAW` before calling draw-xt.
- **handle-xt signature:** `( event widget -- consumed? )`. Returns
  TRUE (-1) if the event was consumed, FALSE (0) otherwise.
- **Default flags:** New widgets are VISIBLE + DIRTY. Not FOCUSED
  (focus is managed by the focus chain in Layer 5).
