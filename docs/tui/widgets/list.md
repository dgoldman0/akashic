# akashic/tui/widgets/list.f — Scrollable List Widget

**Layer:** 4B  
**Lines:** 1370  
**Prefix:** `LST-` (public), `_LST-` (internal)  
**Provider:** `akashic-tui-list`  
**Dependencies:** `widget.f`, `draw.f`, `keys.f`, `semantic-collections.f`,
`style-palette.f`, `text-style.f`, `text-lines.f`, `memory-span.f`

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
the rows start below it, except in card mode.

An optional row callback, `( index widget -- flags )`, marks rows with
`LST-ROW-SECTION`, `LST-ROW-CHECKABLE` and `LST-ROW-CHECKED`.  When the first
row is a section heading, the list is in sections: each heading starts a
section, shows its first field in bold across the row, and is never
selected, and the rows under it are indented two cells.  A section flag on
a later row of a list whose first row is not a heading is ignored.  A
checkable row shows `[ ]` or `[x]` before its first column.  The list
reports a check to its check callback and leaves the row's state to the
caller, which changes its data and returns the new flags.

In `LST-CARDS` mode each row is a card: its first field one cell in, and
each other field on lines of its own, three cells in.  Each field is at
most the region's width less two cells, and less four, and at least one:
the widths SEMANTIC-CONTENT-1 gives a card's fields.  A field of a column
marked `LST-COLUMN-WRAP` breaks into lines at that width by the shared
line rule ([text-lines](../../text/text-lines.md)), and its line feeds
separate paragraphs; a line of a right-to-left paragraph starts at the
field's right edge.  Any other field is one line, cut at its width.  So a
card takes one screen row for each field, but one for each line of a
wrapping field, exactly as a rich terminal lays the same card out.  A card
is never a heading and has no check box, whatever the row callback says.
In `LST-UNTRUSTED` mode the text comes from outside the application, such
as posts from a network feed: the list draws it as `DRW-TEXT-UNTRUSTED`
does, so explicit direction controls cannot reorder the screen, and
publishes it without them.

The view is a place in the rows: a row and one of its screen rows.  It
scrolls by screen rows, so a card taller than the view shows part of
itself, and it never shows empty rows below the last row while rows above
are hidden.  An item takes one screen row, so in item mode the place is
always a row's first screen row.

An optional style source, `( text-a text-u map index column widget -- )`,
fills a style map (`text-style.f`) that says what each byte of a field
means, as a highlighter does.  CELL draws each meaning in the style
palette's look over the list's own colours, and the item view carries the
meanings as style runs, so a renderer can show a link as a link.  The list
keeps one map, grown to the longest field it has been asked to style.

The list publishes its shown rows, and the selected row wherever it is,
as a renderer-neutral item view (see `semantic-collections.md`).  A rich
renderer draws that view itself and sends item events back by key; CELL
output draws the same rows through `WDG-DRAW`.

## Descriptor Layout (168 bytes)

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
| +128 | row-xt | `( index widget -- flags )`, or 0 |
| +136 | check-xt | `( index widget -- )` when a checkable row is checked, or 0 |
| +144 | mode | `LST-CARDS` and `LST-UNTRUSTED`, or 0 |
| +152 | style-xt | `( text-a text-u map index column widget -- )`, or 0 |
| +160 | scroll-row | Screen rows of the first shown row above the view |

## Column Records (40 bytes each)

| Offset | Constant | Description |
|--------|----------|-------------|
| +0 | `LST-COLUMN-KIND` | `LST-TEXT-COLUMN` (left-aligned) or `LST-NUMBER-COLUMN` (right-aligned) |
| +8 | `LST-COLUMN-LABEL-A` | Label address |
| +16 | `LST-COLUMN-LABEL-U` | Label length, 0 for none |
| +24 | `LST-COLUMN-WIDTH` | Width in cells, or 0 for a share of the rest |
| +32 | `LST-COLUMN-FLAGS` | `LST-COLUMN-WRAP`: in card mode its fields break into lines |

`LST-COLUMN-SIZE` is the record size.  The list maps the two kinds onto
its item view's text and number columns, so a caller never names the
collection model.  Fixed columns take their width.
Flexible columns share what is left after the fixed columns and the
one-cell gaps between columns; the last flexible column takes whatever the
division leaves over.  Each cell is clipped to its column.  Cards ignore
the widths and take the card field widths above.

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `LST-NEW` | `( rgn key-xt field-xt -- widget )` | An empty list with one text column |
| `LST-FREE` | `( widget -- )` | Free the descriptor |

### Rows and Columns

| Word | Stack | Description |
|------|-------|-------------|
| `LST-ROWS!` | `( count widget -- )` | The rows changed: there are now `count`, the first row that is not a heading is selected, and the view is at the top |
| `LST-COUNT` | `( widget -- count )` | Number of rows |
| `LST-COLUMNS!` | `( columns-a count widget -- )` | Use `count` caller-owned column records; `0 0` for one text column |
| `LST-ROW-FLAGS!` | `( xt widget -- )` | Row callback `( index widget -- flags )`, or 0 for plain rows |
| `LST-MODE!` | `( mode widget -- )` | `LST-CARDS` and `LST-UNTRUSTED`, or 0 |
| `LST-STYLE!` | `( xt widget -- )` | Style source `( text-a text-u map index column widget -- )`, or 0 for plain text |

### Selection and Callbacks

| Word | Stack | Description |
|------|-------|-------------|
| `LST-SELECT` | `( index widget -- )` | Select a row, or the next row that is not a heading, and show it; the selection callback runs if it moved |
| `LST-SELECTED` | `( widget -- index )` | The selected row, or -1 |
| `LST-ON-SELECT` | `( xt widget -- )` | Callback `( index widget -- )` when the selection moves |
| `LST-ON-OPEN` | `( xt widget -- )` | Callback `( index widget -- )` when the selected row is opened |
| `LST-ON-CHECK` | `( xt widget -- )` | Callback `( index widget -- )` when a checkable row is checked or unchecked |
| `LST-CONTEXT!` | `( context widget -- )` | Store the caller's context cell |
| `LST-CONTEXT@` | `( widget -- context )` | Read the caller's context cell |

### Scrolling

| Word | Stack | Description |
|------|-------|-------------|
| `LST-SCROLL-TO` | `( index widget -- )` | Scroll so a row is shown, without selecting it: the view starts at a row above it or cut at its top, or one with at least the body's screen rows; otherwise it moves down until the row's last screen row is the body's last |
| `LST-SCROLL-INFO` | `( widget -- content-h offset visible-h )` | Scroll parameters in screen rows: all of them, those above the view, and the body's |
| `LST-SCROLL-SET` | `( offset widget -- )` | Start the view `offset` screen rows down, within the rows; the selection does not move |

A card list with wrapping columns counts a card's screen rows from its
fields' lines, so `LST-SCROLL-INFO` lays out every card, and the other
words lay out the cards they pass.

### Item View

| Word | Stack | Description |
|------|-------|-------------|
| `LST-ITEM-VIEW-CAPTURE` | `( root-key dst cap builder widget -- bytes status )` | Build the list's item view with the caller's builder; `dst cap` of `0 0` measures |
| `LST-ITEM-VIEW-MEASURE` | `( root-key builder widget -- bytes status )` | Exact bytes the capture needs |
| `LST-INSTANCE@` | `( widget -- token )` | The instance token, or 0 for anything that is not a live list |
| `LST-STORAGE-DISJOINT?` | `( address bytes -- flag )` | A caller span misses the module's own storage |
| `LST-ITEM-VIEW-STORAGE-DISJOINT?` | `( address bytes widget -- flag )` | A caller span also misses the list's descriptor, region and column records |

The capture's role is `CARDS` in card mode, `SECTIONS` when the list is in
sections, `TABLE` when there is more than one column or any label, and
`LIST` otherwise.  It carries the columns, each wrapping column with its
`WRAP` flag, and the screen rows of the first shown card above the view
as the view's viewport row.  Then the rows in index order: the selected
row when it is above the view, the shown rows (every row with a screen
row in the body), and the selected row when it is below the view.  Each
row carries its key, one field per column, the `SELECTED` state when it is
the selection, and `CHECKABLE` and `CHECKED` from its flags.  In sections a heading is a `SECTION` item with its first field and
no state, and every other row has depth one and names the heading above it,
found once for each run of carried rows.  A field is carried as CELL
shows it (`UTF8-SAFE-COPY`): each control character and each byte
that is not UTF-8 as U+FFFD, but a wrapping field's line feeds as they
are, and in `LST-UNTRUSTED` mode each explicit
embedding, override or isolate as U+200B, which is invisible and reorders
nothing.  Both keep one scalar for each scalar of the source, so the style
runs taken from its map still fit.  A card list whose wrapping field
cannot be laid out, because its row buffer cannot grow, captures
`UNAVAILABLE`: its screen rows are unknown.

## Input (via `WDG-HANDLE`)

| Input | Action |
|-------|--------|
| Up / Down | Move the selection one row, past headings |
| Page Up / Page Down | Move the selection by the rows shown (in card mode, the cards with a screen row in the view) |
| Home / End | Select the first / last row that is not a heading |
| Enter | Open the selected row |
| Space | Check the selected row, when it is checkable |
| Primary press | Select the row under the pointer, or open it if it is already selected; on a row's check box, check it; a press on the header, on a heading, or below the rows is consumed and does nothing |
| Wheel | Scroll three screen rows without moving the selection |
| Item SELECT | Select the row with that key |
| Item OPEN | Select the row with that key, then open it |
| Item CHECK | Check the row with that key |

Pointer events carry absolute screen cells (see `keys.f`).  Item events
arrive as `KEY-MOUSE-ITEM` with the key in `KEY-MOUSE-ITEM-KEY` and the
action in `KEY-MOUSE-ITEM-ACTION`.  A key only names a row the renderer
was sent: a shown row or the selected row.  An item event whose key names
no such row, or a heading, is consumed and changes nothing.

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
