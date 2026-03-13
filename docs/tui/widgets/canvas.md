# akashic/tui/widgets/canvas.f — Braille Canvas Widget

**Layer:** 7  
**Lines:** 443  
**Prefix:** `CVS-` (public), `_CVS-` (internal)  
**Provider:** `akashic-tui-canvas`  
**Dependencies:** `widget.f`, `draw.f`, `region.f`

## Overview

A free-form drawing surface using Unicode Braille characters
(U+2800..U+28FF) for sub-cell pixel resolution.  Each terminal cell
maps to a 2×4 dot block, giving 2× horizontal and 4× vertical
resolution compared to plain character placement.

Braille dot numbering per cell:

```
      Col 0   Col 1
Row 0   1       4      bit 0   bit 3
Row 1   2       5      bit 1   bit 4
Row 2   3       6      bit 2   bit 5
Row 3   7       8      bit 6   bit 7
```

Codepoint = `0x2800 + assembled-8-bit-value`

### Colour Model

Per-dot colour is impossible — a Braille glyph is one terminal cell
with a single fg/bg pair.  Instead, a **colour map** stores one
`(fg, bg)` pair per terminal cell.  Drawing operations stamp the
current *pen colour* into the colour map for every cell they touch.

### Buffers

| Buffer | Size | Purpose |
|--------|------|---------|
| `dot-buf` | `ceil(dot-w × dot-h / 8)` bytes | 1 bit per dot |
| `col-buf` | `cell-cols × cell-rows × 2` bytes | Per-cell `(fg, bg)` packed |

## Descriptor Layout (96 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+32 | header | widget header | Standard 5-cell header, type=WDG-T-CANVAS (14) |
| +40 | dot-buf | address | Allocated bit array (1 bit per dot) |
| +48 | dot-w | u | Dot width = region-w × 2 |
| +56 | dot-h | u | Dot height = region-h × 4 |
| +64 | col-buf | address | Allocated colour map (2 bytes per cell) |
| +72 | pen-fg | u | Current pen foreground (0–255) |
| +80 | pen-bg | u | Current pen background (0–255) |
| +88 | cell-w | u | Terminal cell columns (= region-w) |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `CVS-NEW` | `( rgn -- widget )` | Create canvas; allocates dot-buf and col-buf |
| `CVS-FREE` | `( widget -- )` | Free both buffers and descriptor |

### Dot Operations

| Word | Stack | Description |
|------|-------|-------------|
| `CVS-SET` | `( widget x y -- )` | Set dot at (x, y); stamps pen colour |
| `CVS-CLR` | `( widget x y -- )` | Clear dot at (x, y) |
| `CVS-GET` | `( widget x y -- flag )` | Test dot; returns -1 if set, 0 if clear |
| `CVS-CLEAR` | `( widget -- )` | Clear all dots and reset colour map |

### Pen / Colour

| Word | Stack | Description |
|------|-------|-------------|
| `CVS-PEN!` | `( widget fg bg -- )` | Set pen colour for subsequent draws |
| `CVS-COLOR!` | `( widget col row fg bg -- )` | Set colour of a specific cell directly |

### Drawing Primitives

| Word | Stack | Description |
|------|-------|-------------|
| `CVS-LINE` | `( widget x0 y0 x1 y1 -- )` | Draw line (Bresenham's algorithm) |
| `CVS-RECT` | `( widget x y w h -- )` | Draw rectangle outline |
| `CVS-FILL-RECT` | `( widget x y w h -- )` | Draw filled rectangle |
| `CVS-CIRCLE` | `( widget cx cy r -- )` | Draw circle (midpoint algorithm) |

### Text & Data

| Word | Stack | Description |
|------|-------|-------------|
| `CVS-TEXT` | `( widget x y addr len -- )` | Place text at dot coords (snapped to cell grid) |
| `CVS-PLOT` | `( widget data count x-scale y-scale -- )` | Connected line graph from integer array |

### Key Handling (via `WDG-HANDLE`)

The canvas does not consume any keys — `_CVS-HANDLE` always returns 0.

## Algorithm Notes

- **`_CVS-BRAILLE`** converts a 2×4 bit block into a Braille
  codepoint by OR-ing the 8 dot bits according to the Braille
  encoding's non-sequential bit layout (column-major, dots 7–8 at
  the bottom).

- **`CVS-LINE`** uses Bresenham's line algorithm with sign-aware
  stepping.  Variables `_LX0 _LY0 _LX1 _LY1 _LDX _LDY _LSX _LSY
  _LERR` avoid deep stack gymnastics.

- **`CVS-CIRCLE`** uses the midpoint circle algorithm.  Sets dots
  at all 8 symmetric octant points per step.

- **`CVS-PLOT`** draws a connected line graph from an array of
  integer y-values.  `x-scale` controls dots per data point
  horizontally; `y-scale` divides input values to map to canvas
  height.

- **Bounds checking.** `_CVS-OK?` validates (x, y) against
  `(dot-w, dot-h)` before every set/clear/get.  Out-of-range
  coordinates are silently ignored.

- **DO-loop guards.** All loops guard against zero iteration counts
  (KDOS `DO` always enters the body, even for 0 → 0).  Guarded
  with `DUP 0> IF 0 DO … LOOP ELSE DROP THEN` or converted to
  `BEGIN … WHILE … REPEAT`.

## Design Notes

- The canvas allocates both buffers at construction time and
  frees them in `CVS-FREE`.
- `CVS-CLEAR` zeroes the dot buffer and resets every colour-map
  entry to pen defaults (7, 0).
- When `GUARDED` is defined, every public word is wrapped with
  `WITH-GUARD` for concurrency safety.

## Test Coverage (22 tests)

| Group | Tests |
|-------|-------|
| create | type, dot-w, dot-h |
| set/get | set then get returns -1; clear then get returns 0 |
| clr | clear dot |
| oob | out-of-bounds set is no-op |
| pen | pen colour appears in col-buf |
| stamp | set stamps pen colour into col-buf |
| color | CVS-COLOR! writes fg/bg |
| clear | clears dots; resets colour |
| line | horizontal line; diagonal line |
| rect | rectangle outline dots |
| fill-rect | filled rectangle |
| circle | rightmost, top, centre-not-set |
| draw | no crash |
| handle | returns 0 (unconsumed) |
| free | no crash |
