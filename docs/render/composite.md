# akashic-composite — Alpha Compositing & Blend Modes for KDOS / Megapad-64

Integer-only alpha compositing and blend modes operating on packed
RGBA8888 pixels.  This is the fast-path alternative to `COLOR-BLEND`
(which works in FP16 unpacked channels) — all per-pixel math here
uses integer 0–255 channels and avoids floating-point conversion.

```forth
REQUIRE render/composite.f
```

`PROVIDED akashic-composite` — safe to include multiple times.
Automatically requires `surface.f` (and transitively `color.f`,
`fp16.f`, etc.).

---

## Table of Contents

- [Design Principles](#design-principles)
- [composite.f vs color.f](#compositef-vs-colorf)
- [Porter-Duff Modes](#porter-duff-modes)
- [Blend Modes](#blend-modes)
- [Utilities](#utilities)
- [Bulk Operations](#bulk-operations)
- [Monochrome Blit](#monochrome-blit)
- [Internals](#internals)
- [Quick Reference](#quick-reference)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Integer-only** | All channel math uses 0–255 integers. No FP16 conversion per pixel. |
| **Packed RGBA8888** | Inputs and outputs are single 32-bit values: `R[31:24] G[23:16] B[15:8] A[7:0]`. Same format as `SURF-PIXEL!`. |
| **Premultiplied alpha** | Porter-Duff modes assume premultiplied input. Use `COMP-OPACITY` to premultiply if needed. |
| **Fast paths** | `COMP-OVER` short-circuits for fully opaque ($\alpha = 255$) and fully transparent ($\alpha = 0$) source pixels. `COMP-SCANLINE-OVER` applies the same per-pixel. |
| **Variable-based state** | Internal scratch uses `VARIABLE`s — not re-entrant. |
| **Prefix convention** | Public: `COMP-`. Internal: `_COMP-`. |

---

## composite.f vs color.f

| Aspect | `color.f` (`COLOR-BLEND`) | `composite.f` (`COMP-OVER`, ...) |
|---|---|---|
| **Channel format** | 4 separate FP16 values on the stack | Single packed 32-bit integer |
| **Precision** | IEEE 754 half-precision (10-bit mantissa) | 8-bit per channel (0–255) |
| **Speed** | Slower (FP16 multiply + convert per channel) | Faster (integer multiply + shift) |
| **Modes** | Source-over only | Source-over, in, out, atop, XOR, multiply, screen, overlay, darken, lighten |
| **Use case** | Color-space math, gradients, interpolation | Per-pixel compositing in render pipeline |

Use `color.f` when you need color-space conversions (HSL, sRGB
gamma, hex parsing).  Use `composite.f` when you're compositing
pixels in a rendering loop.

---

## Porter-Duff Modes

All Porter-Duff modes take two packed RGBA pixels and return a
composited result.  Inputs should be premultiplied.

### COMP-OVER

```forth
COMP-OVER  ( src dst -- result )
```

Source-over compositing:

$$\text{out} = \text{src} + \text{dst} \times (1 - \alpha_s)$$

The primary compositing operation.  Fast paths:
- $\alpha_s = 255$: returns `src` immediately (no math).
- $\alpha_s = 0$: returns `dst` immediately.

### COMP-IN

```forth
COMP-IN  ( src dst -- result )
```

Source-in: shows source only where destination is opaque.

$$\text{out} = \text{src} \times \alpha_d$$

### COMP-OUT

```forth
COMP-OUT  ( src dst -- result )
```

Source-out: shows source only where destination is transparent.

$$\text{out} = \text{src} \times (1 - \alpha_d)$$

### COMP-ATOP

```forth
COMP-ATOP  ( src dst -- result )
```

Source-atop: source is placed atop destination, using destination's
shape.

$$\text{out} = \text{src} \times \alpha_d + \text{dst} \times (1 - \alpha_s)$$

### COMP-XOR

```forth
COMP-XOR  ( src dst -- result )
```

XOR compositing: shows source and destination where they don't
overlap.

$$\text{out} = \text{src} \times (1 - \alpha_d) + \text{dst} \times (1 - \alpha_s)$$

Two opaque pixels XOR to transparent.

```forth
0xFF0000FF 0x00FF00FF COMP-OVER .   \ red over green → red
0xFF0000FF 0x00FF00FF COMP-XOR .    \ red XOR green  → transparent
```

---

## Blend Modes

Blend modes combine RGB channels using a per-channel formula, then
composite the alpha channel via source-over:

$$\alpha_\text{out} = \alpha_s + \alpha_d \times (1 - \alpha_s)$$

### COMP-MULTIPLY

```forth
COMP-MULTIPLY  ( src dst -- result )
```

Multiply blend — darkens:

$$c_\text{out} = \frac{c_s \times c_d}{255}$$

White is the identity (multiplying by 1 preserves the other).
Black absorbs everything.

### COMP-SCREEN

```forth
COMP-SCREEN  ( src dst -- result )
```

Screen blend — lightens (inverse of multiply):

$$c_\text{out} = c_s + c_d - \frac{c_s \times c_d}{255}$$

Complementary colors screen to white.

### COMP-OVERLAY

```forth
COMP-OVERLAY  ( src dst -- result )
```

Overlay blend — combines multiply and screen based on destination
luminance:

$$c_\text{out} = \begin{cases}
\frac{2 \times c_s \times c_d}{255} & c_d < 128 \\
255 - \frac{2 \times (255 - c_s)(255 - c_d)}{255} & \text{otherwise}
\end{cases}$$

Preserves highlights and shadows of the destination.

### COMP-DARKEN

```forth
COMP-DARKEN  ( src dst -- result )
```

Darken blend — per-channel minimum:

$$c_\text{out} = \min(c_s, c_d)$$

### COMP-LIGHTEN

```forth
COMP-LIGHTEN  ( src dst -- result )
```

Lighten blend — per-channel maximum:

$$c_\text{out} = \max(c_s, c_d)$$

```forth
0xFF0000FF 0x00FF00FF COMP-LIGHTEN .   \ red lighten green → yellow
```

---

## Utilities

### COMP-OPACITY

```forth
COMP-OPACITY  ( rgba alpha -- rgba' )
```

Scale all four channels (R, G, B, and A) by `alpha/255`.
Use this to fade a color or to premultiply:

$$c' = \frac{c \times \alpha + 128}{256}$$

- `alpha = 255` → unchanged.
- `alpha = 0` → transparent black.
- `alpha = 128` → approximately 50%.

```forth
0xFFFFFFFF 128 COMP-OPACITY .   \ → ~0x80808080
0xFF0000FF 0   COMP-OPACITY .   \ → 0x00000000
```

---

## Bulk Operations

### COMP-SCANLINE-COPY

```forth
COMP-SCANLINE-COPY  ( src-addr dst-addr len -- )
```

Copy `len` pixels (4 bytes each) from `src-addr` to `dst-addr`.
Pure memory copy via `CMOVE` — use when the source is known to be
fully opaque, or when overwriting is desired.

### COMP-SCANLINE-OVER

```forth
COMP-SCANLINE-OVER  ( src-addr dst-addr len -- )
```

Source-over composite `len` packed RGBA pixels from `src-addr` over
`dst-addr` in place.  Applies per-pixel fast paths:

- $\alpha = 0$: skip (leave destination unchanged).
- $\alpha = 255$: copy source directly (`L!`).
- Otherwise: call `COMP-OVER`.

This is the inner loop for surface-to-surface alpha blitting.

```forth
src-surf SURF-BUF  dst-surf SURF-BUF  320 COMP-SCANLINE-OVER
```

---

## Monochrome Blit

These words render monochrome (1-byte-per-pixel) bitmaps onto a
surface.  Designed for glyph rendering — the mono bitmap comes from
the font rasterizer or glyph cache.

### COMP-BLIT-MONO

```forth
COMP-BLIT-MONO  ( mono-buf w h surf x y fg-rgba -- )
```

Binary monochrome blit.  For each byte in the $w \times h$ mono
bitmap:
- Non-zero byte → write `fg-rgba` to the surface.
- Zero byte → skip (leave destination unchanged).

No blending — foreground pixels overwrite the destination.

### COMP-BLIT-MONO-ALPHA

```forth
COMP-BLIT-MONO-ALPHA  ( mono-buf w h surf x y fg-rgba -- )
```

Coverage-based monochrome blit.  Each byte (0–255) in the mono
bitmap represents coverage:
- `0xFF` = fully opaque → foreground color at full strength.
- `0x80` = ~50% coverage → foreground blended at half opacity.
- `0x00` = transparent → skip.

**Algorithm per pixel:**
1. Scale `fg-rgba` by the coverage byte via `COMP-OPACITY`.
2. Read the existing destination pixel.
3. Composite via `COMP-OVER`.
4. Write the result.

Use `COMP-BLIT-MONO` for binary (aliased) glyphs and
`COMP-BLIT-MONO-ALPHA` for anti-aliased glyphs with grayscale
coverage maps.

```forth
\ Blit a 12×16 anti-aliased glyph bitmap at (100, 50)
glyph-buf 12 16 my-fb 100 50 0xFFFFFFFF COMP-BLIT-MONO-ALPHA
```

---

## Internals

| Word | Purpose |
|---|---|
| `_COMP-UNPACK` `( rgba -- r g b a )` | Extract 0–255 channels from packed pixel. |
| `_COMP-PACK` `( r g b a -- rgba )` | Pack 0–255 channels (clamped) to RGBA8888. |
| `_COMP-MUL255` `( a b -- result )` | Integer $(a \times b + 128) \gg 8$, clamped 0–255. |
| `_COMP-SR`, `_COMP-SG`, `_COMP-SB`, `_COMP-SA` | Source channel scratch. |
| `_COMP-DR`, `_COMP-DG`, `_COMP-DB`, `_COMP-DA` | Destination channel scratch. |
| `_COMP-TMP`, `_COMP-PTR`, `_COMP-CNT`, `_COMP-SURF` | General-purpose scratch. |
| `_COMP-OV-CH` | Overlay blend per-channel scratch. |
| `_COMP-OVERLAY-CH` `( src-ch dst-ch -- result-ch )` | Per-channel overlay formula. |
| `_COMP-SL-SRC`, `_COMP-SL-DST`, `_COMP-SL-CNT` | Scanline loop state. |
| `_COMP-SL-S`, `_COMP-SL-D` | Scanline per-pixel scratch. |
| `_COMP-MONO-*` | Mono blit parameters. |
| `_COMP-MBA-*` | Mono-alpha blit parameters. |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `COMP-OVER` | `( src dst -- result )` | Source-over (Porter-Duff) |
| `COMP-IN` | `( src dst -- result )` | Source-in |
| `COMP-OUT` | `( src dst -- result )` | Source-out |
| `COMP-ATOP` | `( src dst -- result )` | Source-atop |
| `COMP-XOR` | `( src dst -- result )` | XOR compositing |
| `COMP-MULTIPLY` | `( src dst -- result )` | Multiply blend |
| `COMP-SCREEN` | `( src dst -- result )` | Screen blend |
| `COMP-OVERLAY` | `( src dst -- result )` | Overlay blend |
| `COMP-DARKEN` | `( src dst -- result )` | Darken (min) blend |
| `COMP-LIGHTEN` | `( src dst -- result )` | Lighten (max) blend |
| `COMP-OPACITY` | `( rgba alpha -- rgba' )` | Scale all channels |
| `COMP-SCANLINE-COPY` | `( src-addr dst-addr len -- )` | Bulk pixel copy |
| `COMP-SCANLINE-OVER` | `( src-addr dst-addr len -- )` | Bulk source-over |
| `COMP-BLIT-MONO` | `( mono-buf w h surf x y fg -- )` | Binary glyph blit |
| `COMP-BLIT-MONO-ALPHA` | `( mono-buf w h surf x y fg -- )` | Coverage glyph blit |

---

## Cookbook

### Fade a surface to 50% opacity

```forth
\ Scale every pixel's alpha by 128
src-surf SURF-W src-surf SURF-H * ( npixels )
src-surf SURF-BUF ( addr )
SWAP 0 DO
    DUP L@ 128 COMP-OPACITY   OVER L!
    4 +
LOOP DROP
```

### Layer compositing

```forth
\ Composite a UI overlay onto the framebuffer, row by row
fb SURF-H 0 DO
    overlay-surf SURF-BUF  I overlay-surf SURF-STRIDE * +
    fb       SURF-BUF  I fb       SURF-STRIDE * +
    fb SURF-W
    COMP-SCANLINE-OVER
LOOP
```

### Anti-aliased glyph rendering

```forth
\ Render glyph 65 at size 24, positioned at (100, 50)
65 24 GC-GET                          ( bmp w h )
ROT ROT                              ( bmp w h ) — already ordered
my-fb 100 50 0xFFFFFFFF
COMP-BLIT-MONO-ALPHA
```
