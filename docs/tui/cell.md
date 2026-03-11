# akashic-tui-cell — Character Cell Type

Defines the character cell as a packed 64-bit value — one codepoint,
one foreground color index, one background color index, and attribute
flags.  This is the "pixel" of the terminal UI, analogous to
RGBA8888 in the render pipeline.

```forth
REQUIRE tui/cell.f
```

`PROVIDED akashic-tui-cell` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Cell Encoding](#cell-encoding)
- [Attribute Flags](#attribute-flags)
- [Constructor](#constructor)
- [Field Extractors](#field-extractors)
- [Field Setters](#field-setters)
- [Constants](#constants)
- [Predicates](#predicates)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **One cell = one `@`/`!`** | Entire cell packs into a single Megapad-64 cell (8 bytes). |
| **Pure computation** | No I/O, no allocation, no state. |
| **Non-destructive setters** | `CELL-FG!` etc. return a new cell value, leaving the original unchanged. |
| **Prefix convention** | Public: `CELL-`. Internal: `_CELL-`. |
| **Building block** | Used by screen.f, draw.f, and widget layers. |

---

## Cell Encoding

Each cell packs four fields into 64 bits:

```
Bits 63       48 47      40 39      32 31          0
     ┌─────────┬──────────┬──────────┬──────────────┐
     │  attrs  │   bg     │   fg     │  codepoint   │
     │ 16 bits │  8 bits  │  8 bits  │   32 bits    │
     └─────────┴──────────┴──────────┴──────────────┘
```

- **codepoint** (bits 0–31): Unicode codepoint. 0 = empty cell.
- **fg** (bits 32–39): Foreground color index (0–255, xterm 256-color palette).
- **bg** (bits 40–47): Background color index (0–255, xterm 256-color palette).
- **attrs** (bits 48–63): Attribute flags (see below).

A screen buffer is a flat array of cells, each addressed with plain
`@` and `!`.

---

## Attribute Flags

Attribute constants are low-bit values (bits 0–8).  `CELL-MAKE`
shifts them into position 48–63 during packing.  `CELL-ATTRS@`
returns them in their low-bit form for direct `AND` testing.

| Constant | Value | Cell Bit | Description |
|----------|-------|----------|-------------|
| `CELL-A-BOLD` | 1 | 48 | Bold / bright |
| `CELL-A-DIM` | 2 | 49 | Dim / faint |
| `CELL-A-ITALIC` | 4 | 50 | Italic |
| `CELL-A-UNDERLINE` | 8 | 51 | Underline |
| `CELL-A-BLINK` | 16 | 52 | Blink |
| `CELL-A-REVERSE` | 32 | 53 | Reverse video |
| `CELL-A-STRIKE` | 64 | 54 | Strikethrough |
| `CELL-A-WIDE` | 128 | 55 | Wide character (left half) |
| `CELL-A-CONT` | 256 | 56 | Continuation (right half of wide char) |

Combine with `OR`:

```forth
CELL-A-BOLD CELL-A-UNDERLINE OR   \ bold + underline
```

---

## Constructor

### CELL-MAKE

```
( cp fg bg attrs -- cell )
```

Pack a codepoint, foreground color index, background color index,
and attribute flags into a single 64-bit cell value.

```forth
65 7 0 0 CELL-MAKE          \ 'A', white on black, no attrs
9731 14 4 CELL-A-BOLD CELL-MAKE  \ '☣', yellow on blue, bold
```

---

## Field Extractors

All extractors consume the cell and return the extracted value.

| Word | Stack | Description |
|------|-------|-------------|
| `CELL-CP@` | `( cell -- cp )` | Codepoint (0–4294967295) |
| `CELL-FG@` | `( cell -- fg )` | Foreground index (0–255) |
| `CELL-BG@` | `( cell -- bg )` | Background index (0–255) |
| `CELL-ATTRS@` | `( cell -- attrs )` | Attribute flags (low-bit form, 0–65535) |

```forth
CELL-BLANK CELL-CP@     \ → 32 (space)
CELL-BLANK CELL-FG@     \ → 7  (white)
```

---

## Field Setters

Setters replace one field, preserving all others.  They return a
new cell value (non-destructive).

| Word | Stack | Description |
|------|-------|-------------|
| `CELL-FG!` | `( fg cell -- cell' )` | Replace foreground color |
| `CELL-BG!` | `( bg cell -- cell' )` | Replace background color |
| `CELL-ATTRS!` | `( attrs cell -- cell' )` | Replace attributes |
| `CELL-CP!` | `( cp cell -- cell' )` | Replace codepoint |

```forth
200 CELL-BLANK CELL-FG!     \ blank cell with fg=200
CELL-A-BOLD CELL-BLANK CELL-ATTRS!  \ blank cell, bold
```

---

## Constants

### CELL-BLANK

```
( -- cell )
```

A blank cell: space (codepoint 32), default foreground (7 = white),
default background (0 = black), no attributes.  This is the
"erased" state of a terminal cell.

```forth
CELL-BLANK CELL-CP@     \ → 32
CELL-BLANK CELL-FG@     \ → 7
CELL-BLANK CELL-BG@     \ → 0
CELL-BLANK CELL-ATTRS@  \ → 0
```

---

## Predicates

| Word | Stack | Description |
|------|-------|-------------|
| `CELL-EQUAL?` | `( a b -- flag )` | Exact 64-bit equality |
| `CELL-EMPTY?` | `( cell -- flag )` | True if cp is 0 or space, default colors, no attrs |
| `CELL-HAS-ATTR?` | `( attr-mask cell -- flag )` | True if the given attribute bit(s) are set |

```forth
CELL-BLANK CELL-BLANK CELL-EQUAL?     \ → -1 (true)
CELL-BLANK CELL-EMPTY?                \ → -1 (true)
CELL-A-BOLD  65 7 0 CELL-A-BOLD CELL-MAKE  CELL-HAS-ATTR?  \ → -1
```

---

## Quick Reference

| Word | Stack | Short |
|------|-------|-------|
| `CELL-MAKE` | `( cp fg bg attrs -- cell )` | Pack cell |
| `CELL-CP@` | `( cell -- cp )` | Get codepoint |
| `CELL-FG@` | `( cell -- fg )` | Get foreground |
| `CELL-BG@` | `( cell -- bg )` | Get background |
| `CELL-ATTRS@` | `( cell -- attrs )` | Get attributes |
| `CELL-FG!` | `( fg cell -- cell' )` | Set foreground |
| `CELL-BG!` | `( bg cell -- cell' )` | Set background |
| `CELL-ATTRS!` | `( attrs cell -- cell' )` | Set attributes |
| `CELL-CP!` | `( cp cell -- cell' )` | Set codepoint |
| `CELL-BLANK` | `( -- cell )` | Default blank |
| `CELL-EQUAL?` | `( a b -- flag )` | Exact compare |
| `CELL-EMPTY?` | `( cell -- flag )` | Is blank/empty? |
| `CELL-HAS-ATTR?` | `( mask cell -- flag )` | Test attr bit |
