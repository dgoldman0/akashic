# akashic-tui-color — xterm-256 Color Conversion

Shared TUI color utilities: maps 24-bit RGB values to the nearest
xterm-256 palette index using Euclidean distance across the 6×6×6
colour cube (indices 16–231) and the 24-step grayscale ramp
(indices 232–255). It also expands palette indices to fully opaque
RGBA8888 and parses CSS colour strings (hex and named) directly to
palette indices.

```forth
REQUIRE tui/color.f
```

`PROVIDED akashic-tui-color` — safe to include multiple times.

**Dependencies:** `css/css.f`, `utils/string.f`

---

## Table of Contents

- [Design Principles](#design-principles)
- [Algorithm](#algorithm)
- [Public API](#public-api)
- [Quick Reference](#quick-reference)
- [Usage Examples](#usage-examples)
- [See Also](#see-also)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Shared module** | Used by both `dom-tui.f` and `uidl-tui.f` — extracted to avoid duplication. |
| **Pure computation** | No allocation, no I/O, no global state beyond scratch variables. |
| **Terminal-compatible** | Palette expansion exactly matches MegaPad's `VirtualTerminal`: its base 16 colours, the xterm cube, and the xterm grayscale ramp. |
| **CSS-aware** | Accepts `#RRGGBB` / `#RGB` hex colours, all 148 CSS named colours, and raw integer palette indices (0-255). |
| **Prefix convention** | Public: `TUI-`. Internal: `_TC-`. |

---

## Algorithm

`TUI-RESOLVE-COLOR` maps an RGB triplet to the nearest xterm-256
palette entry in two steps:

1. **Colour cube** (indices 16–231) — snap each component to the
   nearest of the 6 cube levels (0, 95, 135, 175, 215, 255) and
   compute Euclidean distance² to that quantised colour.

2. **Grayscale ramp** (indices 232–255) — average the three
   components, find the nearest of 24 gray levels
   (8, 18, 28, … 238), and compute distance² from the original RGB.

The index with the smaller distance² wins.  Ties favour grayscale.

`TUI-PALETTE>RGBA` performs the exact reverse palette expansion:

1. **Base colours** (indices 0–15) use MegaPad's terminal palette:

   | Index | RGB | Index | RGB |
   |------:|:----|------:|:----|
   | 0 | `000000` | 8 | `555555` |
   | 1 | `AA0000` | 9 | `FF5555` |
   | 2 | `00AA00` | 10 | `55FF55` |
   | 3 | `AA5500` | 11 | `FFFF55` |
   | 4 | `0000AA` | 12 | `5555FF` |
   | 5 | `AA00AA` | 13 | `FF55FF` |
   | 6 | `00AAAA` | 14 | `55FFFF` |
   | 7 | `AAAAAA` | 15 | `FFFFFF` |

2. **Colour cube** (indices 16–231) uses component levels
   0, 95, 135, 175, 215, and 255, with blue varying fastest.

3. **Grayscale ramp** (indices 232–255) uses
   `gray = 8 + 10 × (index - 232)`.

The result is the numeric packed value `0xRRGGBBAA`; alpha is always
`0xFF`. This is a value layout, independent of byte order in memory.

---

## Public API

### `TUI-RESOLVE-COLOR` — `( r g b -- index )`

Map a 24-bit RGB triplet (each component 0–255) to the nearest
xterm-256 palette index.

```forth
255 255 255 TUI-RESOLVE-COLOR  .  \ 231 (bright white)
0   0   0   TUI-RESOLVE-COLOR  .  \ 16  (black in cube)
95  135 175 TUI-RESOLVE-COLOR  .  \ 67  (steel blue area)
128 128 128 TUI-RESOLVE-COLOR  .  \ 244 (mid-gray in ramp)
```

### `TUI-PALETTE>RGBA` — `( index -- rgba )`

Expand an already-validated xterm-256 palette index to packed
`0xRRGGBBAA`, matching the foreground and background fields in a TUI
`CELL`. The conversion does not clamp, mask, or wrap its input; callers
own the existing `0..255` palette-index invariant. It has no provider
dependency and performs no allocation.

```forth
1   TUI-PALETTE>RGBA  .  \ 0xAA0000FF (base red)
67  TUI-PALETTE>RGBA  .  \ 0x5F87AFFF (cube colour)
244 TUI-PALETTE>RGBA  .  \ 0x808080FF (grayscale)
```

### `TUI-PARSE-COLOR` — `( val-a val-u -- index found? )`

Parse a CSS colour value string and return the palette index.
Supports:

- **Hex colours**: `#RRGGBB` and `#RGB` (resolved via
  `CSS-PARSE-HEX-COLOR`)
- **Named colours**: all 148 CSS named colours (`white`, `red`,
  `darkgreen`, `cornflowerblue`, etc.) via `CSS-COLOR-FIND`
- **Raw integer indices**: `0`–`255` (direct xterm-256 palette index,
  parsed via `CSS-PARSE-INT`)

Returns `( index -1 )` on success, `( 0 0 )` on failure.

```forth
S" #5f0087" TUI-PARSE-COLOR  .  .  \ -1 54  (deep purple)
S" white"   TUI-PARSE-COLOR  .  .  \ -1 231 (bright white)
S" 7"       TUI-PARSE-COLOR  .  .  \ -1 7   (white, palette 7)
S" 236"     TUI-PARSE-COLOR  .  .  \ -1 236 (dark gray)
S" bogus"   TUI-PARSE-COLOR  . .   \ 0 0    (not found)
```

> **Note:** The failure return is `( 0 0 )` — two values, not one.
> This was a stack-balance bug in earlier versions (fixed).

---

## Quick Reference

```
TUI-RESOLVE-COLOR   ( r g b -- index )              RGB → xterm-256 palette index
TUI-PALETTE>RGBA    ( index -- rgba )                Palette index → opaque 0xRRGGBBAA
TUI-PARSE-COLOR     ( val-a val-u -- idx flag )      CSS color string → palette index
                                                     Hex (#RGB, #RRGGBB), named, or integer 0-255
```

---

## Usage Examples

### Resolve a hex colour for the draw engine

```forth
S" #87d7d7" TUI-PARSE-COLOR IF
    \ index is on stack — use as fg
    236 0 DRW-STYLE!
ELSE
    \ fallback
    7 0 0 DRW-STYLE!
THEN
```

### Convert named colours to palette indices

```forth
S" cornflowerblue" TUI-PARSE-COLOR IF
    .  \ prints the palette index
THEN
```

### Expand a cell colour for a rich label

```forth
cell CELL-FG@ TUI-PALETTE>RGBA  \ opaque RGBA for the neutral label record
```

---

## See Also

- [css.md](../css/css.md) — CSS parser (`CSS-PARSE-HEX-COLOR`, `CSS-COLOR-FIND`)
- [dom-tui.md](dom-tui.md) — DOM-to-TUI backend (historically defined the resolver)
- [uidl-tui.md](uidl-tui.md) — UIDL TUI backend (uses color.f for `style=` resolution)
- [cell.md](cell.md) — Character cell encoding (FG/BG are 8-bit palette indices)
- [draw.md](draw.md) — Draw engine (`DRW-STYLE!` consumes palette indices)
