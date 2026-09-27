# akashic/tui/widgets/list.f — Scrollable List Widget

**Layer:** 4B  
**Lines:** 680  
**Prefix:** `LST-` (public), `_LST-` (internal)  
**Provider:** `akashic-tui-list`  
**Dependencies:** `widget.f`, `draw.f`, `keys.f`, `semantic-collections.f`,
`memory-span.f`

## Overview

A vertically scrollable list of rows, one or more columns wide, with one
selected row.  The widget does not own its rows.  The caller gives a row
count and two callbacks:

| Callback | Stack | Meaning |
|----------|-------|---------|
| key-xt | `( index widget -- key )` | A nonzero key, unique among the rows, that names the row from draw to draw |
| field-xt | `( index column widget -- addr len )` | The text of one cell |

Rows show in index order.  Columns are an optional caller-owned array of
column records.  With no columns the list has one unlabelled text column.
When any column has a label, the region's first row shows the labels and
the rows start below it.

The list publishes its shown rows, and the selected row wherever it is,
as a renderer-neutral item view (see `semantic-collections.md`).  A rich
renderer draws that view itself and sends item events back by key; CELL
output draws the same rows through `WDG-DRAW`.

## Descriptor Layout (128 bytes)

| Offset | Field | Description |
|--------|-------|-------------|
| +0..+39 | header | Standard widget header, type=`WDG-T-LIST` |
| +40 | count | Number of rows |
| +48 | selected | Selected row, or -1 when there are no rows |
| +56 | scroll-top | First shown row |
| +64 | select-xt | `( index widget -- )` when the selection moves, or 0 |
| +72 | open-xt | `( index widget -- )` when a row is opened, or 0 |
| +80 | key-xt | `( index widget -- key )` |
| +88 | field-xt | `( index column widget -- addr len )` |
| +96 | columns-a | Column records, or 0 |
| +104 | columns-n | Column count, or 0 for one text column |
| +112 | instance | Nonzero allocation-lifetime instance token |
| +120 | context | The caller's context cell |

## Column Records (32 bytes each)

| Offset | Constant | Description |
|--------|----------|-------------|
| +0 | `LST-COLUMN-KIND` | `USCOL-IV-TEXT` (left-aligned) or `USCOL-IV-NUMBER` (right-aligned) |
| +8 | `LST-COLUMN-LABEL-A` | Label address |
| +16 | `LST-COLUMN-LABEL-U` | Label length, 0 for none |
| +24 | `LST-COLUMN-WIDTH` | Width in cells, or 0 for a share of the rest |

`LST-COLUMN-SIZE` is the record size.  Fixed columns take their width.
Flexible columns share what is left after the fixed columns and the
one-cell gaps between columns; the last flexible column takes whatever the
division leaves over.  Each cell is clipped to its column.

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `LST-NEW` | `( rgn key-xt field-xt -- widget )` | An empty list with one text column |
| `LST-FREE` | `( widget -- )` | Free the descriptor |

### Rows and Columns

| Word | Stack | Description |
|------|-------|-------------|
| `LST-ROWS!` | `( count widget -- )` | The rows changed: there are now `count`, the first is selected, and the view is at the top |
| `LST-COUNT` | `( widget -- count )` | Number of rows |
| `LST-COLUMNS!` | `( columns-a count widget -- )` | Use `count` caller-owned column records; `0 0` for one text column |

### Selection and Callbacks

| Word | Stack | Description |
|------|-------|-------------|
| `LST-SELECT` | `( index widget -- )` | Select a row and show it; the selection callback runs if it moved |
| `LST-SELECTED` | `( widget -- index )` | The selected row, or -1 |
| `LST-ON-SELECT` | `( xt widget -- )` | Callback `( index widget -- )` when the selection moves |
| `LST-ON-OPEN` | `( xt widget -- )` | Callback `( index widget -- )` when the selected row is opened |
| `LST-CONTEXT!` | `( context widget -- )` | Store the caller's context cell |
| `LST-CONTEXT@` | `( widget -- context )` | Read the caller's context cell |

### Scrolling

| Word | Stack | Description |
|------|-------|-------------|
| `LST-SCROLL-TO` | `( index widget -- )` | Scroll so a row is shown, without selecting it |
| `LST-SCROLL-INFO` | `( widget -- content-h offset visible-h )` | Scroll parameters for a scroll container |
| `LST-SCROLL-SET` | `( offset widget -- )` | Set the first shown row (clamped); the selection does not move |

### Item View

| Word | Stack | Description |
|------|-------|-------------|
| `LST-ITEM-VIEW-CAPTURE` | `( root-key dst cap builder widget -- bytes status )` | Build the list's item view with the caller's builder; `dst cap` of `0 0` measures |
| `LST-ITEM-VIEW-MEASURE` | `( root-key builder widget -- bytes status )` | Exact bytes the capture needs |
| `LST-INSTANCE@` | `( widget -- token )` | The instance token, or 0 for anything that is not a live list |
| `LST-STORAGE-DISJOINT?` | `( address bytes -- flag )` | A caller span misses the module's own storage |
| `LST-ITEM-VIEW-STORAGE-DISJOINT?` | `( address bytes widget -- flag )` | A caller span also misses the list's descriptor, region and column records |

The capture's role is `TABLE` when there is more than one column or any
label, and `LIST` otherwise.  It carries the columns, then the rows in
index order: the selected row when it is above the view, the shown rows,
and the selected row when it is below the view.  Each row carries its key,
one field per column, and the `SELECTED` state when it is the selection.

## Input (via `WDG-HANDLE`)

| Input | Action |
|-------|--------|
| Up / Down | Move the selection one row |
| Page Up / Page Down | Move the selection by the shown height |
| Home / End | Select the first / last row |
| Enter | Open the selected row |
| Primary press | Select the row under the pointer; a press on the header or below the rows is consumed and does nothing |
| Wheel | Scroll three rows without moving the selection |
| Item SELECT | Select the row with that key |
| Item OPEN | Select the row with that key, then open it |

Pointer events carry absolute screen cells (see `keys.f`).  Item events
arrive as `KEY-MOUSE-ITEM` with the key in `KEY-MOUSE-ITEM-KEY` and the
action in `KEY-MOUSE-ITEM-ACTION`.  A key only names a row the renderer
was sent: a shown row or the selected row.  An item event whose key names
no such row is consumed and changes nothing.

## Design Notes

- **Rows by callback.** The list keeps no row data, so a caller with
  thousands of rows, or rows that change under it, pays nothing to keep a
  copy in step.  `LST-ROWS!` is the one signal that the rows changed.
- **Keys, not positions.** A renderer names rows by key because a row's
  index can change between the frame it drew and the event it sends back.
- **Context cell.** Callbacks that serve several lists read the list's
  context cell to find their own state.  This keeps a snapshot capture
  correct when it visits a list whose owner is not the active one.
- **Auto-scroll.** A selection that is already shown never moves the
  view, so the row under a pointer press stays under it.
