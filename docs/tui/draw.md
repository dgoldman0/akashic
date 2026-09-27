# akashic-tui-draw — Cell-Level Drawing Primitives

Convenience words for common drawing operations on the current
screen's back buffer: horizontal / vertical lines, filled rectangles,
text strings placed at a position.  Operates on the screen set by
`SCR-USE`.

A "current style" (foreground, background, attributes) is maintained
so callers don't need to pass three extra values on every draw call.
All coordinates are 0-based (row, col).  Drawing is clipped to the
screen dimensions — writes outside the screen are silently discarded.

```forth
REQUIRE tui/draw.f
```

Optional neutral draw observers may wrap an independently replaceable paint
layer with `DRW-REPLACEMENT ( ... body-xt -- ... )`. The body paints the normal
screen completely while the screen preserves its ordinary underlying pixels
in a separate residue plane. Scope exit and exceptions restore the previous
depth. A nested foreground `DRW-OVERLAY` remains visible in both planes.
These scopes must not yield or change the selected screen; applications keep
using the ordinary drawing words.

`PROVIDED akashic-tui-draw` — safe to include multiple times.

**Dependencies:** `screen.f`, `../text/utf8.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Style State](#style-state)
- [Character Drawing](#character-drawing)
- [Line Drawing](#line-drawing)
- [Rectangle Drawing](#rectangle-drawing)
- [Text Drawing](#text-drawing)
- [Clipping](#clipping)
- [Convenience](#convenience)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Implicit style** | Current fg/bg/attrs stored in variables; every draw word uses them automatically. |
| **Clip-safe** | All output is bounds-checked against `SCR-W` / `SCR-H`; out-of-bounds writes are silently dropped. |
| **Back-buffer only** | Writes go to the selected back buffer; nothing appears on screen until `SCR-FLUSH`. |
| **Save/restore** | `DRW-CLEAR-RECT` saves and restores the current style so callers are not surprised. |
| **Prefix convention** | Public: `DRW-`. Internal: `_DRW-`. |
| **Not reentrant** | Internal scratch `VARIABLE`s are shared; call from one task only. |

---

## Style State

The drawing layer maintains three variables — foreground color index,
background color index, and attribute flags.  Every cell created by
the drawing words is packed using these values via `CELL-MAKE`.

### DRW-FG!

```
( fg -- )
```

Set the current drawing foreground color (0–255, xterm palette).

```forth
14 DRW-FG!   \ yellow
```

### DRW-BG!

```
( bg -- )
```

Set the current drawing background color (0–255, xterm palette).

```forth
4 DRW-BG!   \ blue
```

### DRW-ATTR!

```
( attrs -- )
```

Set the current drawing attributes.  Use the `CELL-A-*` constants
from `cell.f`, combined with `OR`.

```forth
CELL-A-BOLD CELL-A-UNDERLINE OR DRW-ATTR!   \ bold + underline
```

### DRW-STYLE!

```
( fg bg attrs -- )
```

Set foreground, background, and attributes in a single call.

```forth
14 4 CELL-A-BOLD DRW-STYLE!   \ yellow on blue, bold
```

### DRW-STYLE-SAVE

```
( -- )
```

Save the current foreground, background, and attributes to
internal scratch variables. The UIDL paint path calls this
automatically after applying the sidecar style, so widgets
can call `DRW-STYLE-RESTORE` to return to the inherited
theme colours after drawing a selection or cursor highlight.

```forth
14 4 CELL-A-BOLD DRW-STYLE!   \ set a theme style
DRW-STYLE-SAVE                 \ save it
CELL-A-REVERSE DRW-ATTR!       \ temporary highlight
\ ... draw highlighted content ...
DRW-STYLE-RESTORE              \ back to theme style
```

### DRW-STYLE-RESTORE

```
( -- )
```

Restore the foreground, background, and attributes previously
saved by `DRW-STYLE-SAVE`. Used by widgets to return to the
inherited sidecar style after drawing highlights.

```forth
DRW-STYLE-RESTORE   \ back to saved theme colours
```

### DRW-STYLE-RESET

```
( -- )
```

Reset the drawing style to defaults: foreground 7 (white),
background 0 (black), no attributes.

```forth
DRW-STYLE-RESET   \ back to plain white-on-black
```

---

## Character Drawing

### DRW-CHAR

```
( cp row col -- )
```

Place the one-scalar character `cp` at (row, col) using the current
style.  A wide character also takes the cell to its right; when the clip
cuts that cell, a space in the style takes its place.  Silently clipped if
outside the screen.  `DRW-HLINE` steps two cells per wide character.

```forth
65 0 0 DRW-CHAR        \ 'A' at top-left
9731 5 10 DRW-CHAR      \ '☣' at row 5, col 10
```

---

## Line Drawing

### DRW-HLINE

```
( cp row col len -- )
```

Draw a horizontal line of character `cp` starting at (row, col) and
extending `len` cells to the right.  Each cell is clipped
individually.

```forth
HEX 2500 DECIMAL  2 1 40 DRW-HLINE   \ '─' across 40 columns at row 2
```

### DRW-VLINE

```
( cp row col len -- )
```

Draw a vertical line of character `cp` starting at (row, col) and
extending `len` cells downward.  Each cell is clipped individually.

```forth
HEX 2502 DECIMAL  1 0 10 DRW-VLINE   \ '│' down 10 rows at col 0
```

---

## Rectangle Drawing

### DRW-FILL-RECT

```
( cp row col h w -- )
```

Fill an h×w rectangle with character `cp`, starting at (row, col).
Each row is drawn with `DRW-HLINE`, so the current style applies and
clipping is automatic.

```forth
HEX 2588 DECIMAL  5 10 8 20 DRW-FILL-RECT   \ solid block 8×20 at (5,10)
```

### DRW-CLEAR-RECT

```
( row col h w -- )
```

Clear an h×w rectangle to `CELL-BLANK` (space, fg=7, bg=0, no
attrs).  The current style is saved before clearing and restored
afterward, so the caller's style is not disturbed.

```forth
0 0 24 80 DRW-CLEAR-RECT   \ clear entire 80×24 area
```

---

## Text Drawing

### DRW-TEXT

```
( addr len row col -- )
```

Lay a UTF-8 string out as one row of text and place it from (row, col),
following the shared text rules (`docs/rich-terminal/APT-1-TEXT.md`, through
[text-row](../text/text-row.md)): each character (grapheme cluster) takes
its width in cells, a wide one a lead and a continuation cell; the string is
one bidi paragraph whose right-to-left runs appear in visual order, with
mirrored brackets and joined Arabic letters; and a character of several
scalars goes into the screen's cluster pool.  A character the clip cuts
shows a space in each of its cells the clip keeps.

Printable ASCII takes a byte path with no layout: it discards a clipped-left
prefix, then writes only the visible bytes.  Other text is laid out, and its
cells prepared, before one bounded mutable back-plane borrow, which neither
allocates nor calls the screen.  If the row cannot be laid out for lack of
memory, each scalar takes one cell and anything but printable ASCII shows as
U+FFFD.

```forth
S" Hello, world!" 0 0 DRW-TEXT   \ print at top-left
```

### DRW-TROW-MARK

```
( trow row col start end attrs -- )
```

Draw a row the caller already laid out with `TROW-LAYOUT`
([text-row](../text/text-row.md)), its visual column 0 at (row, col), as
`DRW-TEXT` draws. Characters whose logical start offset lies in
[start, end) also take `attrs`, as a selection or a caret does. A widget that
needs the layout anyway, for caret and pointer mapping, lays a line out once
and draws it with this word.

### DRW-TROW

```
( trow row col -- )
```

`DRW-TROW-MARK` with nothing marked.

### DRW-TEXT-STYLED and DRW-TROW-STYLED

```
( addr len row col xt -- )
( trow row col start end attrs xt -- )
```

As `DRW-TEXT` and `DRW-TROW-MARK`, but each character first takes the
foreground and attributes that `xt ( byte -- fg attrs )` gives for the byte
offset where the character starts, so one call draws a highlighted line.
Printable ASCII calls `xt` for each byte, other text for each character. The
style in force before the call is back in force after it. A text area uses
these with its style map ([textarea](widgets/textarea.md)).

### DRW-FG@ and DRW-ATTR@

```
( -- fg )  ( -- attrs )
```

The current foreground and attributes.

### DRW-TEXT-UNTRUSTED

```
( addr len row col -- )
```

Draw network, document, or Agent-supplied UTF-8 as `DRW-TEXT` does, except
that explicit bidi embeddings, overrides, and isolates are ignored, so such
text cannot reorder what surrounds it.  Controls show as U+FFFD, as they do
for all text.

This is a presentation transform only: it neither edits nor normalizes the
caller-owned bytes. Use `DRW-TEXT` for trusted interface labels and
`DRW-TEXT-UNTRUSTED` at an untrusted-content display boundary.

### DRW-TEXT-CENTER

```
( addr len row col w -- )
```

Center text, by its width in cells, within a field of width `w` starting at
(row, col).
The field is first filled with spaces (using the current style),
then the text is placed at the computed left-pad offset.  If the
text is longer than the field, it is truncated.

```forth
S" Title" 0 10 30 DRW-TEXT-CENTER   \ center in 30-col field at (0,10)
```

### DRW-TEXT-RIGHT

```
( addr len row col w -- )
```

Right-align text, by its width in cells, within a field of width `w`
starting at (row, col).
The field is first filled with spaces, then the text is placed
flush-right.  If the text is longer than the field, it is truncated.

```forth
S" Page 1" 23 50 30 DRW-TEXT-RIGHT   \ right-align in 30-col field
```

---

## Clipping

### DRW-WITH-CLIP

```
( xt row col h w -- )
```

Run `xt` with drawing clipped to the `h` by `w` rectangle at local
(row, col) as well as to the current clip. The clip returns when `xt` returns
or throws. A text area uses it to keep a scrolled or right-to-left line out of
its gutter. With no region in use the origin is zero, so the rectangle is in
screen coordinates.

```forth
['] draw-line-text  row gutter  1 width gutter -  DRW-WITH-CLIP
```

---

## Convenience

### DRW-REPEAT

```
( cp row col n -- )
```

Draw `n` copies of codepoint `cp` starting at (row, col),
advancing horizontally.  Synonym for `DRW-HLINE`.

```forth
42 12 0 80 DRW-REPEAT   \ row of '*' across 80 columns
```

---

## Quick Reference

| Word | Stack | Short |
|------|-------|-------|
| `DRW-FG!` | `( fg -- )` | Set foreground |
| `DRW-BG!` | `( bg -- )` | Set background |
| `DRW-ATTR!` | `( attrs -- )` | Set attributes |
| `DRW-STYLE!` | `( fg bg attrs -- )` | Set all style |
| `DRW-STYLE-SAVE` | `( -- )` | Save current fg/bg/attrs |
| `DRW-STYLE-RESTORE` | `( -- )` | Restore saved fg/bg/attrs |
| `DRW-STYLE-RESET` | `( -- )` | Reset to defaults |
| `DRW-CHAR` | `( cp row col -- )` | Draw one char |
| `DRW-HLINE` | `( cp row col len -- )` | Horizontal line |
| `DRW-VLINE` | `( cp row col len -- )` | Vertical line |
| `DRW-FILL-RECT` | `( cp row col h w -- )` | Fill rectangle |
| `DRW-CLEAR-RECT` | `( row col h w -- )` | Clear rectangle |
| `DRW-TEXT` | `( addr len row col -- )` | Draw UTF-8 text |
| `DRW-TROW-MARK` | `( trow row col start end attrs -- )` | Draw a laid-out row, marking a logical range |
| `DRW-TROW` | `( trow row col -- )` | Draw a laid-out row |
| `DRW-TEXT-STYLED` | `( addr len row col xt -- )` | Draw text, each character in the style `xt` gives |
| `DRW-TROW-STYLED` | `( trow row col start end attrs xt -- )` | Draw a laid-out row, each character in the style `xt` gives |
| `DRW-FG@` / `DRW-ATTR@` | `( -- fg )` / `( -- attrs )` | The current foreground and attributes |
| `DRW-TEXT-UNTRUSTED` | `( addr len row col -- )` | Draw untrusted UTF-8, ignoring bidi controls |
| `DRW-TEXT-CENTER` | `( addr len row col w -- )` | Center text |
| `DRW-TEXT-RIGHT` | `( addr len row col w -- )` | Right-align text |
| `DRW-WITH-CLIP` | `( xt row col h w -- )` | Run xt with a narrower clip |
| `DRW-REPEAT` | `( cp row col n -- )` | Repeat char (= HLINE) |
