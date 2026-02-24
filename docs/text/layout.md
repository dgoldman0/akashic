# akashic-layout — Text Layout Engine for KDOS / Megapad-64

Measures text widths, advances a cursor, and performs simple
word-wrap line breaking over UTF-8 strings.  Relies on the TTF
cmap for codepoint → glyph mapping and the hmtx table for advance
widths.

```forth
REQUIRE layout.f
```

`PROVIDED akashic-layout` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Scale State](#scale-state)
- [Character & Text Width](#character--text-width)
- [Vertical Metrics](#vertical-metrics)
- [Cursor Positioning](#cursor-positioning)
- [Word-Wrap Iterator](#word-wrap-iterator)
- [Quick Reference](#quick-reference)
- [Known Limitations](#known-limitations)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Scaled pixel units** | All returned values are in pixels: `font_units × pixel_size / UPEM`. |
| **Integer arithmetic** | No floating-point — uses integer divide for the scale. |
| **UTF-8 native** | Iterates strings via `UTF8-DECODE`, supporting full Unicode. |
| **Iterator pattern** | Word-wrap uses an init/next-line iterator — no dynamic allocation. |
| **Prefix convention** | Public words use `LAY-`, internals use `_LAY-`. |

---

## Dependencies

```
layout.f ──→ utf8.f
         ──→ ttf.f (TTF-CMAP-LOOKUP, TTF-ADVANCE, TTF-UPEM, TTF-ASCENDER, …)
```

A TTF font must be parsed (`TTF-PARSE`) before any layout call.

---

## Scale State

Before using any layout word, set the pixel size:

```forth
16 LAY-SCALE!   \ render at 16 px
```

This caches `TTF-UPEM` into `_LAY-UPEM` so the scale factor
(`pixel_size / UPEM`) is available to every subsequent call.

| Word | Stack | Description |
|---|---|---|
| `LAY-SCALE!` | `( pixel-size -- )` | Set rendering scale and cache UPEM. |

---

## Character & Text Width

```forth
65 LAY-CHAR-WIDTH .    \ width of 'A' in pixels
addr len LAY-TEXT-WIDTH .   \ total width of a UTF-8 string
```

| Word | Stack | Description |
|---|---|---|
| `LAY-CHAR-WIDTH` | `( codepoint -- pixels )` | Width of one character (cmap → advance → scale). |
| `LAY-TEXT-WIDTH` | `( addr len -- pixels )` | Sum of advance widths for every codepoint in the string. |

`LAY-TEXT-WIDTH` iterates with `UTF8-DECODE`, accumulating widths
in the internal variable `_LAY-TW-ACC`.

---

## Vertical Metrics

```forth
LAY-ASCENDER .     \ e.g. 12
LAY-DESCENDER .    \ e.g. -4  (negative = below baseline)
LAY-LINE-HEIGHT .  \ ascender - descender + lineGap
```

| Word | Stack | Description |
|---|---|---|
| `LAY-ASCENDER` | `( -- pixels )` | Scaled ascender from the TTF `hhea` table. |
| `LAY-DESCENDER` | `( -- pixels )` | Scaled descender (usually negative). |
| `LAY-LINE-HEIGHT` | `( -- pixels )` | `ascender − descender + lineGap`, scaled. |

---

## Cursor Positioning

A simple 2-D cursor for single-line or multi-line text output.

```forth
10 20 LAY-CURSOR-INIT      \ start at (10, 20)
65 LAY-CURSOR-ADV           \ advance by width of 'A'
LAY-CURSOR@  SWAP . .      \ print x y
LAY-CURSOR-NL               \ carriage return + line feed
```

| Word | Stack | Description |
|---|---|---|
| `LAY-CURSOR-INIT` | `( x y -- )` | Set cursor position; remembers start-x for newlines. |
| `LAY-CURSOR@` | `( -- x y )` | Read current cursor position. |
| `LAY-CURSOR-ADV` | `( codepoint -- )` | Advance cursor x by the character's width. |
| `LAY-CURSOR-NL` | `( -- )` | Reset x to start-x, advance y by `LAY-LINE-HEIGHT`. |

---

## Word-Wrap Iterator

Breaks a UTF-8 string into successive lines, each fitting within
a configurable pixel width.  The iterator consumes no heap — all
state lives in variables.

### Usage pattern

```forth
100 LAY-WRAP-WIDTH!            \ max line width = 100 px
addr len LAY-WRAP-INIT         \ begin iteration
BEGIN LAY-WRAP-LINE WHILE      \ ( addr len ) of one line
    \ … render or measure the line …
REPEAT
```

### Line-breaking rules

1. **Soft break at spaces** — when the accumulated width exceeds the
   wrap width, the line is broken after the last space.
2. **Hard newline** — `0x0A` forces an immediate line break; the
   newline character is consumed and not included in any line.
3. **Forced mid-word break** — if no space has been seen, the line
   breaks before the current character (with a guarantee of at least
   one character per line to avoid infinite loops).

### API

| Word | Stack | Description |
|---|---|---|
| `LAY-WRAP-WIDTH!` | `( pixels -- )` | Set maximum line width. |
| `LAY-WRAP-INIT` | `( addr len -- )` | Initialise the iterator. |
| `LAY-WRAP-LINE` | `( -- addr len flag )` | Next line; `flag=0` ⇒ done. |

### Internal variables

| Variable | Purpose |
|---|---|
| `_LAY-WR-A`, `_LAY-WR-L` | Remaining string pointer and length. |
| `_LAY-LS` | Line-start address. |
| `_LAY-ACC` | Accumulated pixel width of current line. |
| `_LAY-SA`, `_LAY-SL` | Scan position (before decode). |
| `_LAY-NA`, `_LAY-NL` | Next position (after decode). |
| `_LAY-BA`, `_LAY-BL` | Last break opportunity (after space). |
| `_LAY-BSEEN` | Flag: has a space been seen on this line? |
| `_LAY-CP` | Current codepoint. |

---

## Quick Reference

| Word | Stack | Category |
|---|---|---|
| `LAY-SCALE!` | `( px -- )` | Scale |
| `LAY-CHAR-WIDTH` | `( cp -- px )` | Width |
| `LAY-TEXT-WIDTH` | `( a u -- px )` | Width |
| `LAY-ASCENDER` | `( -- px )` | Metrics |
| `LAY-DESCENDER` | `( -- px )` | Metrics |
| `LAY-LINE-HEIGHT` | `( -- px )` | Metrics |
| `LAY-CURSOR-INIT` | `( x y -- )` | Cursor |
| `LAY-CURSOR@` | `( -- x y )` | Cursor |
| `LAY-CURSOR-ADV` | `( cp -- )` | Cursor |
| `LAY-CURSOR-NL` | `( -- )` | Cursor |
| `LAY-WRAP-WIDTH!` | `( px -- )` | Wrap |
| `LAY-WRAP-INIT` | `( a u -- )` | Wrap |
| `LAY-WRAP-LINE` | `( -- a u f )` | Wrap |

---

## Known Limitations

- **No kerning** — advance widths are used as-is; pair kerning from
  the `kern` or `GPOS` table is not consulted.
- **No bidirectional text** — layout is always left-to-right.
- **No ligatures or glyph substitution** — no OpenType GSUB support.
- **Integer rounding** — the scale division rounds toward zero, which
  can cause ±1 px drift on long lines.
- **Space-only breaking** — only U+0020 (space) is treated as a break
  opportunity; other whitespace or Unicode line-break classes are not
  considered.
