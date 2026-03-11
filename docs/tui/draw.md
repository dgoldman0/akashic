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
- [Convenience](#convenience)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Implicit style** | Current fg/bg/attrs stored in variables; every draw word uses them automatically. |
| **Clip-safe** | All output is bounds-checked against `SCR-W` / `SCR-H`; out-of-bounds writes are silently dropped. |
| **Back-buffer only** | Writes go to the back buffer via `SCR-SET`; nothing appears on screen until `SCR-FLUSH`. |
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

Place one character (codepoint) at (row, col) using the current
style.  Silently clipped if outside the screen.

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

Place a UTF-8 string at (row, col), advancing one column per
codepoint.  Uses `UTF8-DECODE` to iterate the string.  Clipped to
the screen width.

```forth
S" Hello, world!" 0 0 DRW-TEXT   \ print at top-left
```

### DRW-TEXT-CENTER

```
( addr len row col w -- )
```

Center text within a field of width `w` starting at (row, col).
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

Right-align text within a field of width `w` starting at (row, col).
The field is first filled with spaces, then the text is placed
flush-right.  If the text is longer than the field, it is truncated.

```forth
S" Page 1" 23 50 30 DRW-TEXT-RIGHT   \ right-align in 30-col field
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
| `DRW-STYLE-RESET` | `( -- )` | Reset to defaults |
| `DRW-CHAR` | `( cp row col -- )` | Draw one char |
| `DRW-HLINE` | `( cp row col len -- )` | Horizontal line |
| `DRW-VLINE` | `( cp row col len -- )` | Vertical line |
| `DRW-FILL-RECT` | `( cp row col h w -- )` | Fill rectangle |
| `DRW-CLEAR-RECT` | `( row col h w -- )` | Clear rectangle |
| `DRW-TEXT` | `( addr len row col -- )` | Draw UTF-8 text |
| `DRW-TEXT-CENTER` | `( addr len row col w -- )` | Center text |
| `DRW-TEXT-RIGHT` | `( addr len row col w -- )` | Right-align text |
| `DRW-REPEAT` | `( cp row col n -- )` | Repeat char (= HLINE) |
