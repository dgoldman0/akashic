# akashic-color — Color Space Math for KDOS / Megapad-64

Color space conversions, gamma correction, alpha compositing, and
pixel packing — all in FP16.  Color channels are FP16 values in
$[0, 1]$ unless otherwise noted.

```forth
REQUIRE color.f
```

`PROVIDED akashic-color` — safe to include multiple times.
Auto-loads `fp16-ext.f` and `exp.f` (and transitively `fp16.f`)
via REQUIRE.

---

## Table of Contents

- [Design Principles](#design-principles)
- [sRGB Gamma](#srgb-gamma)
- [Luminance & Contrast](#luminance--contrast)
- [RGB ↔ HSL](#rgb--hsl)
- [RGB ↔ HSV](#rgb--hsv)
- [Interpolation](#interpolation)
- [Alpha & Blending](#alpha--blending)
- [Packing & Unpacking](#packing--unpacking)
- [Hex Parsing](#hex-parsing)
- [Internals](#internals)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Channels on the stack** | Colors live as 3 or 4 FP16 values on the stack `( r g b )` or `( r g b a )`, not in memory. |
| **Normalized range** | All channels are in $[0, 1]$. Hue is in $[0, 1)$ (fractional turns — multiply by 360 for degrees). |
| **FP16 throughout** | All components are raw 16-bit IEEE 754 half-precision bit patterns. |
| **PREFIX convention** | All public words use the `COLOR-` prefix. Internal helpers use `_CL-`. |
| **VARIABLEs for scratch** | Eight shared scratch variables `_CL-A` through `_CL-H` hold intermediates. No locals, no return-stack tricks. |
| **Not re-entrant** | Shared VARIABLEs mean concurrent callers would collide. |

---

## sRGB Gamma

### COLOR-SRGB>LINEAR

```forth
COLOR-SRGB>LINEAR  ( srgb -- linear )
```

Decode a single sRGB channel to linear light:

$$
\text{linear} = \begin{cases}
c / 12.92 & c \le 0.04045 \\
\left(\frac{c + 0.055}{1.055}\right)^{2.4} & \text{otherwise}
\end{cases}
$$

Uses `EXP-POW` from `exp.f` for the gamma exponent.

### COLOR-LINEAR>SRGB

```forth
COLOR-LINEAR>SRGB  ( linear -- srgb )
```

Encode a linear-light channel to sRGB:

$$
\text{srgb} = \begin{cases}
12.92 \cdot c & c \le 0.0031308 \\
1.055 \cdot c^{1/2.4} - 0.055 & \text{otherwise}
\end{cases}
$$

---

## Luminance & Contrast

### COLOR-LUMINANCE

```forth
COLOR-LUMINANCE  ( r g b -- Y )
```

Relative luminance per Rec. 709 / sRGB:

$$Y = 0.2126 R + 0.7152 G + 0.0722 B$$

Assumes **linear** RGB input. Apply `COLOR-SRGB>LINEAR` per
channel first if working with sRGB values.

### COLOR-GRAY

```forth
COLOR-GRAY  ( r g b -- gray )
```

Grayscale conversion via luminance.  Equivalent to `COLOR-LUMINANCE`.

### COLOR-CONTRAST

```forth
COLOR-CONTRAST  ( r1 g1 b1 r2 g2 b2 -- ratio )
```

WCAG 2.x contrast ratio between two colors:

$$\text{ratio} = \frac{L_1 + 0.05}{L_2 + 0.05}, \quad L_1 \ge L_2$$

Automatically swaps luminances if needed.  Assumes linear RGB.
Returns an FP16 value $\ge 1.0$ (maximum 21:1 for black/white).

```forth
\ White vs black contrast  →  21.0
0x3C00 0x3C00 0x3C00  0x0000 0x0000 0x0000
COLOR-CONTRAST .  \ → ~21.0
```

---

## RGB ↔ HSL

### COLOR-RGB>HSL

```forth
COLOR-RGB>HSL  ( r g b -- h s l )
```

Convert RGB to Hue-Saturation-Lightness.

- $H$ in $[0, 1)$ — fractional turns (multiply by 360 for degrees)
- $S$ in $[0, 1]$
- $L$ in $[0, 1]$

Achromatic colors (R = G = B) return $H = 0$, $S = 0$.

**Algorithm:**
1. Compute $\max$, $\min$, $\delta = \max - \min$
2. $L = (\max + \min) / 2$
3. $S = \delta\, /\, (1 - |2L - 1|)$
4. $H$ from sector-dependent formula, normalized to $[0, 1)$

### COLOR-HSL>RGB

```forth
COLOR-HSL>RGB  ( h s l -- r g b )
```

Convert HSL back to RGB.  Inverse of `COLOR-RGB>HSL`.

Uses the standard $p$/$q$ intermediate approach with the
`_CL-HSL-HUE2RGB` helper for each channel.

```forth
\ Pure red  →  hsl(0, 1, 0.5)  →  rgb(1, 0, 0)
0x0000 0x3C00 0x3800  COLOR-HSL>RGB
\ Stack: 0x3C00 0x0000 0x0000  (R=1, G=0, B=0)
```

---

## RGB ↔ HSV

### COLOR-RGB>HSV

```forth
COLOR-RGB>HSV  ( r g b -- h s v )
```

Convert RGB to Hue-Saturation-Value.

- $H$ in $[0, 1)$
- $S = \delta / \max$
- $V = \max$

Achromatic colors return $H = 0$, $S = 0$.

### COLOR-HSV>RGB

```forth
COLOR-HSV>RGB  ( h s v -- r g b )
```

Convert HSV back to RGB.  Uses the classic $p$/$q$/$t$ approach
with sector selection via `CASE`.

```forth
\ Pure green  →  hsv(1/3, 1, 1)  →  rgb(0, 1, 0)
0x3555 0x3C00 0x3C00  COLOR-HSV>RGB
```

---

## Interpolation

### COLOR-LERP-RGB

```forth
COLOR-LERP-RGB  ( r1 g1 b1 r2 g2 b2 t -- r g b )
```

Per-channel linear interpolation between two RGB colors:

$$r = r_1 + t \cdot (r_2 - r_1)$$

Uses `FP16-LERP` for each channel.  Works in whatever color space
the inputs are in — for perceptually smooth gradients, convert to
linear light first.

---

## Alpha & Blending

### COLOR-MUL-ALPHA

```forth
COLOR-MUL-ALPHA  ( r g b a -- r' g' b' a )
```

Premultiply RGB channels by alpha:
$r' = r \cdot a$, $g' = g \cdot a$, $b' = b \cdot a$.
Alpha is passed through unchanged.

### COLOR-BLEND

```forth
COLOR-BLEND  ( r1 g1 b1 a1 r2 g2 b2 a2 -- r g b a )
```

Alpha-premultiplied "over" compositing (Porter-Duff):

$$\text{out} = \text{src} + \text{dst} \cdot (1 - \alpha_{\text{src}})$$

- **src** = color1 (top layer), **dst** = color2 (bottom layer)
- Both inputs must be premultiplied — use `COLOR-MUL-ALPHA` first

```forth
\ 50% red over solid blue
0x3800 0x0000 0x0000 0x3800  \ src: (0.5, 0, 0, 0.5) premultiplied
0x0000 0x0000 0x3C00 0x3C00  \ dst: (0, 0, 1, 1) premultiplied
COLOR-BLEND
```

---

## Packing & Unpacking

### COLOR-PACK-RGBA

```forth
COLOR-PACK-RGBA  ( r g b a -- packed )
```

Pack four FP16 channels to a single 32-bit RGBA8888 integer.
Each channel is clamped to $[0, 1]$, scaled to $[0, 255]$, and
rounded.

Bit layout: `[31:24]=R  [23:16]=G  [15:8]=B  [7:0]=A`

### COLOR-UNPACK-RGBA

```forth
COLOR-UNPACK-RGBA  ( packed -- r g b a )
```

Unpack a 32-bit RGBA8888 integer to four FP16 channels in $[0, 1]$.

```forth
0xFF804020 COLOR-UNPACK-RGBA
\ → R≈1.0  G≈0.502  B≈0.251  A≈0.125
```

### COLOR-PACK-RGB565

```forth
COLOR-PACK-RGB565  ( r g b -- packed )
```

Pack FP16 RGB to 16-bit RGB565 format (common for embedded displays):

- R: 5 bits `[15:11]`
- G: 6 bits `[10:5]`
- B: 5 bits `[4:0]`

---

## Hex Parsing

### COLOR-HEX-PARSE

```forth
COLOR-HEX-PARSE  ( addr len -- r g b flag )
```

Parse a CSS-style hex color string. Accepts `#RGB`, `#RRGGBB`,
`RGB`, or `RRGGBB` (leading `#` is optional). Case-insensitive.

Returns three FP16 channels in $[0, 1]$ and a success flag.
On failure, returns $(0, 0, 0, \text{FALSE})$.

```forth
S" #FF8040" COLOR-HEX-PARSE  \ → R=1.0  G≈0.502  B≈0.251  TRUE
S" #F80"    COLOR-HEX-PARSE  \ → R=1.0  G≈0.533  B=0.0    TRUE
S" xyz"     COLOR-HEX-PARSE  \ → 0 0 0 FALSE
```

**Short form expansion:** `#RGB` expands each nibble — `#F80` becomes
`#FF8800`.

---

## Internals

| Word | Purpose |
|---|---|
| `_CL-A` through `_CL-H` | VARIABLEs holding intermediate FP16 values |
| `_CL-CLAMP01` | Clamp FP16 to $[0, 1]$ |
| `_CL-MIN3`, `_CL-MAX3` | Three-way FP16 min/max |
| `_CL-FP16>BYTE` | Clamp, scale to 255, round, convert to integer |
| `_CL-BYTE>FP16` | Integer 0–255 to FP16 $[0, 1]$ |
| `_CL-HEXCHAR` | Single hex character to value |
| `_CL-PARSE-BYTE` | Two hex characters to byte value |
| `_CL-HSL-HUE2RGB` | HSL helper for per-channel hue conversion |
| `_CL-HSL-C`, `_CL-HSL-X`, `_CL-HSL-M`, `_CL-HSL-SEC` | HSL conversion scratch |
| `_CL-HSV-TMP` | HSV conversion scratch |
| `_CL-BL-SA`, `_CL-BL-INV`, `_CL-BL-SR`, `_CL-BL-SG`, `_CL-BL-SB` | Blend operation scratch |
| `_CL-HP-ADDR`, `_CL-HP-LEN` | Hex parse address/length |
| `_CL-LT` | LERP `t` parameter |

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `COLOR-SRGB>LINEAR` | `( srgb -- linear )` | sRGB gamma decode |
| `COLOR-LINEAR>SRGB` | `( linear -- srgb )` | sRGB gamma encode |
| `COLOR-LUMINANCE` | `( r g b -- Y )` | Relative luminance (Rec. 709) |
| `COLOR-GRAY` | `( r g b -- gray )` | Grayscale via luminance |
| `COLOR-CONTRAST` | `( r1 g1 b1 r2 g2 b2 -- ratio )` | WCAG contrast ratio |
| `COLOR-RGB>HSL` | `( r g b -- h s l )` | RGB → HSL |
| `COLOR-HSL>RGB` | `( h s l -- r g b )` | HSL → RGB |
| `COLOR-RGB>HSV` | `( r g b -- h s v )` | RGB → HSV |
| `COLOR-HSV>RGB` | `( h s v -- r g b )` | HSV → RGB |
| `COLOR-LERP-RGB` | `( r1 g1 b1 r2 g2 b2 t -- r g b )` | Per-channel color lerp |
| `COLOR-MUL-ALPHA` | `( r g b a -- r' g' b' a )` | Premultiply alpha |
| `COLOR-BLEND` | `( r1 g1 b1 a1 r2 g2 b2 a2 -- r g b a )` | Porter-Duff over blend |
| `COLOR-PACK-RGBA` | `( r g b a -- packed )` | Pack to RGBA8888 |
| `COLOR-UNPACK-RGBA` | `( packed -- r g b a )` | Unpack RGBA8888 |
| `COLOR-PACK-RGB565` | `( r g b -- packed )` | Pack to RGB565 |
| `COLOR-HEX-PARSE` | `( addr len -- r g b flag )` | Parse CSS hex color |
