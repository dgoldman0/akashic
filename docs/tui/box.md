# akashic-tui-box — Box Drawing & Borders

Draw rectangular borders and frames using Unicode box-drawing
characters.  Multiple border styles are provided (single, double,
rounded, heavy, ASCII).  Composable with `draw.f` — boxes are drawn
into the same back buffer via the current screen.

**File:** `akashic/tui/box.f`
**Lines:** 275
**Prefix:** `BOX-` (public), `_BOX-` (internal)
**Provider:** `akashic-tui-box`
**Dependencies:** `draw.f`
**Layer:** 2 — Drawing Primitives

Each style is a descriptor containing 8 codepoints stored in a flat
cell array.

```forth
REQUIRE tui/box.f
```

`PROVIDED akashic-tui-box` — safe to include multiple times.

**Dependencies:** `draw.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Style Descriptors](#style-descriptors)
- [Pre-defined Styles](#pre-defined-styles)
- [Drawing Words](#drawing-words)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Style = data** | Each border style is an 8-cell descriptor — no code branching per style. |
| **Composable** | Uses `DRW-CHAR`, `DRW-HLINE`, `DRW-VLINE` from draw.f; inherits current fg/bg/attrs. |
| **Clip-safe** | All drawing is delegated to draw.f which clips to screen bounds. |
| **Unicode first** | Native Unicode box-drawing characters; ASCII fallback provided. |
| **Prefix convention** | Public: `BOX-`. Internal: `_BOX-`. |
| **Not reentrant** | Internal scratch `VARIABLE`s are shared; call from one task only. |

---

## Style Descriptors

Each box style is a flat array of 8 codepoints (8 bytes each,
64 bytes total) allocated in the dictionary via `_BOX-STYLE`.  The
layout is:

| Offset | Field | Single | Double | Round | Heavy | ASCII |
|--------|-------|--------|--------|-------|-------|-------|
| +0 | top-left | ┌ | ╔ | ╭ | ┏ | + |
| +8 | top-right | ┐ | ╗ | ╮ | ┓ | + |
| +16 | bot-left | └ | ╚ | ╰ | ┗ | + |
| +24 | bot-right | ┘ | ╝ | ╯ | ┛ | + |
| +32 | horizontal | ─ | ═ | ─ | ━ | - |
| +40 | vertical | │ | ║ | │ | ┃ | \| |
| +48 | t-left | ├ | ╠ | ├ | ┣ | + |
| +56 | t-right | ┤ | ╣ | ┤ | ┫ | + |

A style word (e.g. `BOX-SINGLE`) pushes the address of its
descriptor onto the stack.

---

## Pre-defined Styles

Five built-in styles are provided:

### BOX-SINGLE

```
( -- style )
```

Single-line box: `┌─┐│└─┘` with T-pieces `├┤`.

```forth
BOX-SINGLE 0 0 10 40 BOX-DRAW   \ single-line border
```

### BOX-DOUBLE

```
( -- style )
```

Double-line box: `╔═╗║╚═╝` with T-pieces `╠╣`.

```forth
BOX-DOUBLE 0 0 10 40 BOX-DRAW   \ double-line border
```

### BOX-ROUND

```
( -- style )
```

Rounded-corner box: `╭─╮│╰─╯` with T-pieces `├┤`.  Uses the
same horizontal and vertical characters as single, but with
rounded corners.

```forth
BOX-ROUND 0 0 10 40 BOX-DRAW   \ rounded border
```

### BOX-HEAVY

```
( -- style )
```

Heavy (thick) box: `┏━┓┃┗━┛` with T-pieces `┣┫`.

```forth
BOX-HEAVY 0 0 10 40 BOX-DRAW   \ heavy border
```

### BOX-ASCII

```
( -- style )
```

ASCII fallback: `+-+|+-+` with `+` for T-pieces.  Safe for
terminals that lack Unicode box-drawing support.

```forth
BOX-ASCII 0 0 10 40 BOX-DRAW   \ ASCII border
```

---

## Drawing Words

### BOX-DRAW

```
( style row col h w -- )
```

Draw a border rectangle of height `h` and width `w` with its
top-left corner at (row, col).  Draws the four corners, top and
bottom horizontal edges, and left and right vertical edges.
Minimum useful size is h=2, w=2 (just corners, no interior).

The current drawing style (fg/bg/attrs) from draw.f is used for
all characters.

```forth
14 4 CELL-A-BOLD DRW-STYLE!
BOX-DOUBLE 2 5 12 50 BOX-DRAW   \ bold yellow-on-blue double border
```

### BOX-DRAW-TITLED

```
( style addr len row col h w -- )
```

Draw a border rectangle with a title string on the top edge.  The
box is drawn first via `BOX-DRAW`, then the title text is placed
starting 2 columns in from the left corner.  The title is truncated
to `w-4` characters if it would overflow (corners + 1 space each
side).

```forth
BOX-SINGLE S" Settings" 1 2 15 60 BOX-DRAW-TITLED
```

### BOX-HLINE

```
( style row col w -- )
```

Draw a horizontal rule at (row, col) of width `w` using the style's
horizontal character (offset +32).  Useful for internal dividers
within a box.

```forth
BOX-SINGLE 5 1 58 BOX-HLINE   \ single-line divider inside a 60-col box
```

### BOX-VLINE

```
( style row col h -- )
```

Draw a vertical rule at (row, col) of height `h` using the style's
vertical character (offset +40).  Useful for column separators
within a box.

```forth
BOX-SINGLE 1 30 13 BOX-VLINE   \ vertical divider inside a 15-row box
```

### BOX-SHADOW

```
( row col h w -- )
```

Draw a drop shadow along the right edge and bottom edge of a
rectangle.  The shadow uses the dim block character `░` (U+2591)
with fg=0, bg=0, `CELL-A-DIM`.  The shadow is 1 cell wide on the
right and 1 cell tall on the bottom, offset by +1 from the box
bounds.

The current drawing style is saved and restored around the shadow
drawing.

```forth
BOX-ROUND 2 5 12 40 BOX-DRAW
2 5 12 40 BOX-SHADOW               \ add shadow to the box
```

---

## Quick Reference

| Word | Stack | Short |
|------|-------|-------|
| `BOX-SINGLE` | `( -- style )` | Single-line style |
| `BOX-DOUBLE` | `( -- style )` | Double-line style |
| `BOX-ROUND` | `( -- style )` | Rounded-corner style |
| `BOX-HEAVY` | `( -- style )` | Heavy-line style |
| `BOX-ASCII` | `( -- style )` | ASCII fallback style |
| `BOX-DRAW` | `( style row col h w -- )` | Draw border |
| `BOX-DRAW-TITLED` | `( style addr len row col h w -- )` | Border + title |
| `BOX-HLINE` | `( style row col w -- )` | Horizontal rule |
| `BOX-VLINE` | `( style row col h -- )` | Vertical rule |
| `BOX-SHADOW` | `( row col h w -- )` | Drop shadow |
