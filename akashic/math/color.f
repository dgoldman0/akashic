\ color.f — Color space conversions & pixel math
\ Part of Akashic math library for Megapad-64 / KDOS
\
\ Colors are 3 or 4 FP16 values on the stack (channels in [0, 1]
\ unless otherwise noted).  Packed formats use integer bit fields.
\
\ Prefix: COLOR-  (public API)
\         _CL-    (internal helpers)
\
\ Depends on: fp16.f, fp16-ext.f, exp.f  (for gamma curves)
\
\ Load with:   REQUIRE color.f
\
\ === Public API ===
\   COLOR-RGB>HSL      ( r g b -- h s l )         RGB to HSL
\   COLOR-HSL>RGB      ( h s l -- r g b )         HSL to RGB
\   COLOR-RGB>HSV      ( r g b -- h s v )         RGB to HSV
\   COLOR-HSV>RGB      ( h s v -- r g b )         HSV to RGB
\   COLOR-SRGB>LINEAR  ( srgb -- linear )         sRGB gamma decode
\   COLOR-LINEAR>SRGB  ( linear -- srgb )         sRGB gamma encode
\   COLOR-BLEND        ( r1 g1 b1 a1 r2 g2 b2 a2 -- r g b a )
\                        alpha-premultiplied over blend
\   COLOR-LERP-RGB     ( r1 g1 b1 r2 g2 b2 t -- r g b )
\                        per-channel linear interpolation
\   COLOR-PACK-RGBA    ( r g b a -- packed )       4×FP16 → 32-bit RGBA
\   COLOR-UNPACK-RGBA  ( packed -- r g b a )       32-bit RGBA → 4×FP16
\   COLOR-PACK-RGB565  ( r g b -- packed )         FP16 → 16-bit RGB565
\   COLOR-LUMINANCE    ( r g b -- Y )              relative luminance
\   COLOR-CONTRAST     ( r1 g1 b1 r2 g2 b2 -- ratio )  WCAG contrast ratio
\   COLOR-HEX-PARSE    ( addr len -- r g b flag )  parse #RGB / #RRGGBB
\   COLOR-MUL-ALPHA    ( r g b a -- r' g' b' a )   premultiply alpha
\   COLOR-GRAY         ( r g b -- gray )            grayscale (luminance)

REQUIRE fp16-ext.f
REQUIRE exp.f

PROVIDED akashic-color

\ =====================================================================
\  Constants
\ =====================================================================

0x0000 CONSTANT _CL-ZERO            \ 0.0
0x3C00 CONSTANT _CL-ONE             \ 1.0
0x3800 CONSTANT _CL-HALF            \ 0.5
0x4000 CONSTANT _CL-TWO             \ 2.0
0x4600 CONSTANT _CL-SIX             \ 6.0
0x3555 CONSTANT _CL-THIRD           \ 1/3 ≈ 0.3333
0x3955 CONSTANT _CL-TWOTHIRD        \ 2/3 ≈ 0.6667

\ sRGB gamma constants
\ Threshold: 0.04045  → 0x2930 (FP16)
\ Divider:   12.92    → 0x4A76 (FP16)
\ Offset:    0.055    → 0x2B0A (FP16)
\ Scale:     1.055    → 0x3C38 (FP16)
\ Exponent:  2.4      → 0x40CD (FP16)
\ Inv exp:   1/2.4 = 0.41667 → 0x36AB (FP16)
0x2930 CONSTANT _CL-SRGB-THRESH
0x4A76 CONSTANT _CL-SRGB-12P92
0x2B0A CONSTANT _CL-SRGB-OFFSET
0x3C38 CONSTANT _CL-SRGB-SCALE
0x40CD CONSTANT _CL-SRGB-GAMMA
0x36AB CONSTANT _CL-SRGB-INV-GAMMA

\ Luminance coefficients (Rec. 709 / sRGB)
\ 0.2126 → 0x32CE  (FP16)
\ 0.7152 → 0x39B9  (FP16)
\ 0.0722 → 0x2C9F  (FP16)
0x32CE CONSTANT _CL-LUM-R
0x39B9 CONSTANT _CL-LUM-G
0x2C9F CONSTANT _CL-LUM-B

\ =====================================================================
\  Internal scratch variables
\ =====================================================================

VARIABLE _CL-A
VARIABLE _CL-B
VARIABLE _CL-C
VARIABLE _CL-D
VARIABLE _CL-E
VARIABLE _CL-F
VARIABLE _CL-G
VARIABLE _CL-H

\ =====================================================================
\  Internal helpers
\ =====================================================================

: _CL-CLAMP01  ( x -- clamped )
    DUP FP16-SIGN IF DROP _CL-ZERO EXIT THEN
    DUP _CL-ONE FP16-GT IF DROP _CL-ONE THEN ;

: _CL-MIN3  ( a b c -- min )
    FP16-MIN FP16-MIN ;

: _CL-MAX3  ( a b c -- max )
    FP16-MAX FP16-MAX ;

\ =====================================================================
\  COLOR-SRGB>LINEAR — sRGB gamma decode (per channel)
\ =====================================================================
\  if c <= 0.04045:  linear = c / 12.92
\  else:             linear = ((c + 0.055) / 1.055) ^ 2.4

: COLOR-SRGB>LINEAR  ( srgb -- linear )
    DUP _CL-SRGB-THRESH FP16-LE IF
        _CL-SRGB-12P92 FP16-DIV
    ELSE
        _CL-SRGB-OFFSET FP16-ADD
        _CL-SRGB-SCALE FP16-DIV
        _CL-SRGB-GAMMA EXP-POW
    THEN ;

\ =====================================================================
\  COLOR-LINEAR>SRGB — sRGB gamma encode (per channel)
\ =====================================================================
\  if linear <= 0.0031308:  srgb = linear * 12.92
\  else:                    srgb = 1.055 * linear^(1/2.4) - 0.055
\
\  Threshold 0.0031308 ≈ 0.04045 / 12.92 → 0x1A64 (FP16)

0x1A64 CONSTANT _CL-LINEAR-THRESH

: COLOR-LINEAR>SRGB  ( linear -- srgb )
    DUP _CL-LINEAR-THRESH FP16-LE IF
        _CL-SRGB-12P92 FP16-MUL
    ELSE
        _CL-SRGB-INV-GAMMA EXP-POW
        _CL-SRGB-SCALE FP16-MUL
        _CL-SRGB-OFFSET FP16-SUB
    THEN ;

\ =====================================================================
\  COLOR-LUMINANCE — Relative luminance (Rec. 709)
\ =====================================================================
\  Y = 0.2126·R + 0.7152·G + 0.0722·B
\  Assumes linear RGB input.

: COLOR-LUMINANCE  ( r g b -- Y )
    _CL-LUM-B FP16-MUL               ( r g Yb )
    SWAP _CL-LUM-G FP16-MUL          ( r Yb Yg )
    FP16-ADD                          ( r Yg+Yb )
    SWAP _CL-LUM-R FP16-MUL          ( Yg+Yb Yr )
    FP16-ADD ;                        ( Y )

\ =====================================================================
\  COLOR-GRAY — Grayscale via luminance
\ =====================================================================

: COLOR-GRAY  ( r g b -- gray )
    COLOR-LUMINANCE ;

\ =====================================================================
\  COLOR-CONTRAST — WCAG 2.x contrast ratio
\ =====================================================================
\  ratio = (L1 + 0.05) / (L2 + 0.05)   where L1 >= L2
\  Assumes linear RGB input.  Returns FP16 ratio.

0x2A66 CONSTANT _CL-WCAG-OFFSET     \ 0.05 in FP16

: COLOR-CONTRAST  ( r1 g1 b1 r2 g2 b2 -- ratio )
    COLOR-LUMINANCE _CL-B !          ( r1 g1 b1 )  \ L2 → B
    COLOR-LUMINANCE _CL-A !          (  )           \ L1 → A
    \ Ensure L1 >= L2 (swap if needed)
    _CL-A @ _CL-B @ FP16-LT IF
        _CL-A @ _CL-C !  _CL-B @ _CL-A !  _CL-C @ _CL-B !
    THEN
    _CL-A @ _CL-WCAG-OFFSET FP16-ADD
    _CL-B @ _CL-WCAG-OFFSET FP16-ADD
    FP16-DIV ;

\ =====================================================================
\  COLOR-RGB>HSL — RGB to Hue-Saturation-Lightness
\ =====================================================================
\  H in [0, 1) (fractional turns, multiply by 360 for degrees)
\  S, L in [0, 1]
\
\  Algorithm:
\    max = max(r,g,b), min = min(r,g,b), delta = max - min
\    L = (max + min) / 2
\    S = delta==0 ? 0 : delta / (1 - |2L - 1|)
\    H = sector-dependent formula / 6

: COLOR-RGB>HSL  ( r g b -- h s l )
    _CL-C !  _CL-B !  _CL-A !        \ r→A, g→B, b→C

    \ max, min, delta
    _CL-A @ _CL-B @ FP16-MAX _CL-C @ FP16-MAX  _CL-D !   \ max→D
    _CL-A @ _CL-B @ FP16-MIN _CL-C @ FP16-MIN  _CL-E !   \ min→E
    _CL-D @ _CL-E @ FP16-SUB _CL-F !                      \ delta→F

    \ L = (max + min) / 2
    _CL-D @ _CL-E @ FP16-ADD _CL-HALF FP16-MUL  _CL-G !  \ L→G

    \ If delta == 0 → achromatic (H=0, S=0)
    _CL-F @ _CL-ZERO = IF
        _CL-ZERO _CL-ZERO _CL-G @
        EXIT
    THEN

    \ S = delta / (1 - |2L - 1|)
    _CL-G @ _CL-TWO FP16-MUL _CL-ONE FP16-SUB  FP16-ABS
    _CL-ONE SWAP FP16-SUB                        ( 1-|2L-1| )
    _CL-F @ SWAP FP16-DIV _CL-H !               \ S→H

    \ Hue sector
    _CL-D @ _CL-A @ = IF
        \ max == R: H = (G - B) / delta mod 6
        _CL-B @ _CL-C @ FP16-SUB _CL-F @ FP16-DIV
        \ Wrap negative: if result < 0, add 6
        DUP FP16-SIGN IF _CL-SIX FP16-ADD THEN
    ELSE _CL-D @ _CL-B @ = IF
        \ max == G: H = (B - R) / delta + 2
        _CL-C @ _CL-A @ FP16-SUB _CL-F @ FP16-DIV
        _CL-TWO FP16-ADD
    ELSE
        \ max == B: H = (R - G) / delta + 4
        _CL-A @ _CL-B @ FP16-SUB _CL-F @ FP16-DIV
        0x4400 ( 4.0 ) FP16-ADD
    THEN THEN

    \ Normalize H to [0, 1)
    _CL-SIX FP16-DIV                  ( h )
    _CL-H @                           ( h s )
    _CL-G @                           ( h s l )
    ;

\ =====================================================================
\  COLOR-HSL>RGB — HSL to RGB
\ =====================================================================
\  H in [0, 1) (fractional turns), S and L in [0, 1]
\
\  Algorithm:
\    C = (1 - |2L - 1|) * S
\    X = C * (1 - |H*6 mod 2 - 1|)
\    m = L - C/2
\    Then sector-select (r1, g1, b1) from {C, X, 0} combos,
\    add m to each channel.

VARIABLE _CL-HSL-C
VARIABLE _CL-HSL-X
VARIABLE _CL-HSL-M
VARIABLE _CL-HSL-SEC

: _CL-HSL-HUE2RGB  ( p q t -- channel )
    \ Helper: convert hue sector fraction to channel value
    \ Uses dedicated _CL-HSL-* vars to avoid clobbering caller's _CL-C
    \ t should be in [0, 1)
    DUP _CL-ZERO FP16-LT IF _CL-ONE FP16-ADD THEN
    DUP _CL-ONE FP16-GE IF _CL-ONE FP16-SUB THEN
    _CL-HSL-C !  _CL-HSL-X !  _CL-HSL-M !  \ t→HSL-C, q→HSL-X, p→HSL-M

    _CL-HSL-C @ 0x3155 ( 1/6 ) FP16-LT IF
        \ t < 1/6: p + (q-p) * 6 * t
        _CL-HSL-X @ _CL-HSL-M @ FP16-SUB _CL-SIX FP16-MUL _CL-HSL-C @ FP16-MUL
        _CL-HSL-M @ FP16-ADD EXIT
    THEN

    _CL-HSL-C @ _CL-HALF FP16-LT IF
        \ t < 1/2: q
        _CL-HSL-X @ EXIT
    THEN

    _CL-HSL-C @ _CL-TWOTHIRD FP16-LT IF
        \ t < 2/3: p + (q-p) * (2/3 - t) * 6
        _CL-TWOTHIRD _CL-HSL-C @ FP16-SUB
        _CL-SIX FP16-MUL
        _CL-HSL-X @ _CL-HSL-M @ FP16-SUB FP16-MUL
        _CL-HSL-M @ FP16-ADD EXIT
    THEN

    \ else: p
    _CL-HSL-M @ ;

: COLOR-HSL>RGB  ( h s l -- r g b )
    _CL-G !  _CL-F !  _CL-E !        \ h→E, s→F, l→G

    \ Achromatic
    _CL-F @ _CL-ZERO = IF
        _CL-G @ DUP DUP EXIT
    THEN

    \ q = l < 0.5 ? l*(1+s) : l + s - l*s
    _CL-G @ _CL-HALF FP16-LT IF
        _CL-G @ _CL-ONE _CL-F @ FP16-ADD FP16-MUL
    ELSE
        _CL-G @ _CL-F @ FP16-ADD
        _CL-G @ _CL-F @ FP16-MUL FP16-SUB
    THEN
    _CL-D !                            \ q→D

    \ p = 2*l - q
    _CL-G @ _CL-TWO FP16-MUL _CL-D @ FP16-SUB
    _CL-C !                            \ p→C

    \ R = hue2rgb(p, q, h + 1/3)
    _CL-C @ _CL-D @ _CL-E @ _CL-THIRD FP16-ADD
    _CL-HSL-HUE2RGB                   ( r )

    \ G = hue2rgb(p, q, h)
    _CL-C @ _CL-D @ _CL-E @
    _CL-HSL-HUE2RGB                   ( r g )

    \ B = hue2rgb(p, q, h - 1/3)
    _CL-C @ _CL-D @ _CL-E @ _CL-THIRD FP16-SUB
    _CL-HSL-HUE2RGB                   ( r g b )
    ;

\ =====================================================================
\  COLOR-RGB>HSV — RGB to Hue-Saturation-Value
\ =====================================================================
\  H in [0, 1), S and V in [0, 1]

: COLOR-RGB>HSV  ( r g b -- h s v )
    _CL-C !  _CL-B !  _CL-A !        \ r→A, g→B, b→C

    _CL-A @ _CL-B @ FP16-MAX _CL-C @ FP16-MAX  _CL-D !   \ max→D (V)
    _CL-A @ _CL-B @ FP16-MIN _CL-C @ FP16-MIN  _CL-E !   \ min→E
    _CL-D @ _CL-E @ FP16-SUB _CL-F !                      \ delta→F

    \ V = max
    \ If delta == 0 → achromatic
    _CL-F @ _CL-ZERO = IF
        _CL-ZERO _CL-ZERO _CL-D @
        EXIT
    THEN

    \ S = delta / max
    _CL-F @ _CL-D @ FP16-DIV _CL-G !  \ S→G

    \ Hue (same logic as HSL)
    _CL-D @ _CL-A @ = IF
        _CL-B @ _CL-C @ FP16-SUB _CL-F @ FP16-DIV
        DUP FP16-SIGN IF _CL-SIX FP16-ADD THEN
    ELSE _CL-D @ _CL-B @ = IF
        _CL-C @ _CL-A @ FP16-SUB _CL-F @ FP16-DIV
        _CL-TWO FP16-ADD
    ELSE
        _CL-A @ _CL-B @ FP16-SUB _CL-F @ FP16-DIV
        0x4400 FP16-ADD
    THEN THEN

    _CL-SIX FP16-DIV                  ( h )
    _CL-G @                           ( h s )
    _CL-D @                           ( h s v )
    ;

\ =====================================================================
\  COLOR-HSV>RGB — HSV to RGB
\ =====================================================================
\  H in [0, 1), S and V in [0, 1]
\
\  Algorithm:
\    C = V * S
\    H' = H * 6
\    X = C * (1 - |H' mod 2 - 1|)
\    m = V - C
\    Sector-select (r1, g1, b1), add m.

VARIABLE _CL-HSV-TMP

: COLOR-HSV>RGB  ( h s v -- r g b )
    _CL-C !  _CL-B !  _CL-A !        \ h→A, s→B, v→C

    \ C = V * S
    _CL-C @ _CL-B @ FP16-MUL _CL-D !  \ C→D

    \ m = V - C
    _CL-C @ _CL-D @ FP16-SUB _CL-E !  \ m→E

    \ H' = H * 6
    _CL-A @ _CL-SIX FP16-MUL          ( H' )

    \ sector = floor(H')
    DUP FP16-FLOOR                     ( H' floor )
    DUP FP16>INT _CL-F !              \ sector→F (integer)
    FP16-SUB                           ( frac = H' - floor )

    \ X = C * (1 - |frac*2 - 1|)
    \ We need |H' mod 2 - 1|.  frac is H' mod 1.
    \ H' mod 2: if sector is odd, frac_mod2 = 1 + frac, else frac
    \ Simplify: we compute f directly as the fractional part of H'
    \ and use sector to determine the channel assignment.
    _CL-HSV-TMP !                      \ frac → TMP

    \ For each sector, we need:
    \   f = frac of H' within the sector
    \   C, and X = C * (1 - |2f - 1|)... but easier to just compute
    \   p = m, q = V - C*f = V*(1 - S*f), t = V*(1 - S*(1-f))
    \ Use the classic p/q/t approach:

    \ p = m = V - C  (already in E)
    \ q = V * (1 - S * f)
    _CL-B @ _CL-HSV-TMP @ FP16-MUL    ( S*f )
    _CL-ONE SWAP FP16-SUB              ( 1-S*f )
    _CL-C @ FP16-MUL _CL-G !          \ q→G

    \ t = V * (1 - S * (1 - f))
    _CL-ONE _CL-HSV-TMP @ FP16-SUB    ( 1-f )
    _CL-B @ FP16-MUL                  ( S*(1-f) )
    _CL-ONE SWAP FP16-SUB             ( 1-S*(1-f) )
    _CL-C @ FP16-MUL _CL-H !         \ t→H

    \ Select channels based on sector (0-5)
    _CL-F @ CASE
        0 OF _CL-C @ _CL-H @ _CL-E @ ENDOF   \ V, t, p
        1 OF _CL-G @ _CL-C @ _CL-E @ ENDOF   \ q, V, p
        2 OF _CL-E @ _CL-C @ _CL-H @ ENDOF   \ p, V, t
        3 OF _CL-E @ _CL-G @ _CL-C @ ENDOF   \ p, q, V
        4 OF _CL-H @ _CL-E @ _CL-C @ ENDOF   \ t, p, V
        \ 5 or default
        _CL-C @ _CL-E @ _CL-G @               \ V, p, q
    ENDCASE
    ;

\ =====================================================================
\  COLOR-LERP-RGB — Per-channel linear interpolation
\ =====================================================================

VARIABLE _CL-LT

: COLOR-LERP-RGB  ( r1 g1 b1 r2 g2 b2 t -- r g b )
    _CL-LT !
    _CL-F !  _CL-E !  _CL-D !        \ r2→D, g2→E, b2→F
    _CL-C !  _CL-B !  _CL-A !        \ r1→A, g1→B, b1→C

    _CL-A @ _CL-D @ _CL-LT @ FP16-LERP   ( r )
    _CL-B @ _CL-E @ _CL-LT @ FP16-LERP   ( r g )
    _CL-C @ _CL-F @ _CL-LT @ FP16-LERP   ( r g b )
    ;

\ =====================================================================
\  COLOR-MUL-ALPHA — Premultiply alpha
\ =====================================================================

: COLOR-MUL-ALPHA  ( r g b a -- r' g' b' a )
    _CL-A !                            \ a→A
    _CL-A @ FP16-MUL                  ( r g b*a )
    SWAP _CL-A @ FP16-MUL SWAP        ( r g*a b*a )
    ROT _CL-A @ FP16-MUL -ROT         ( r*a g*a b*a )
    _CL-A @ ;                         ( r*a g*a b*a a )

\ =====================================================================
\  COLOR-BLEND — Alpha-premultiplied "over" compositing
\ =====================================================================
\  out = src + dst * (1 - src_alpha)
\  Inputs must be premultiplied.  src is the top layer.
\
\  Stack: ( r1 g1 b1 a1  r2 g2 b2 a2 -- r g b a )
\         src=color1 (top), dst=color2 (bottom)

VARIABLE _CL-BL-SA       \ src alpha
VARIABLE _CL-BL-INV      \ 1 - src_alpha
VARIABLE _CL-BL-SR
VARIABLE _CL-BL-SG
VARIABLE _CL-BL-SB

: COLOR-BLEND  ( r1 g1 b1 a1 r2 g2 b2 a2 -- r g b a )
    \ Store dst (color2)
    _CL-H !  _CL-G !  _CL-F !  _CL-E !   \ a2→H, b2→G, g2→F, r2→E

    \ Store src (color1)
    _CL-BL-SA !                         \ a1 → SA
    _CL-BL-SB !  _CL-BL-SG !  _CL-BL-SR !  \ b1→SB, g1→SG, r1→SR

    \ inv = 1 - src_alpha
    _CL-ONE _CL-BL-SA @ FP16-SUB _CL-BL-INV !

    \ out_r = sr + dr * inv
    _CL-BL-SR @ _CL-E @ _CL-BL-INV @ FP16-MUL FP16-ADD
    \ out_g = sg + dg * inv
    _CL-BL-SG @ _CL-F @ _CL-BL-INV @ FP16-MUL FP16-ADD
    \ out_b = sb + db * inv
    _CL-BL-SB @ _CL-G @ _CL-BL-INV @ FP16-MUL FP16-ADD
    \ out_a = sa + da * inv
    _CL-BL-SA @ _CL-H @ _CL-BL-INV @ FP16-MUL FP16-ADD
    ;

\ =====================================================================
\  COLOR-PACK-RGBA — Pack 4 FP16 channels to 32-bit RGBA8888
\ =====================================================================
\  Each channel is clamped to [0, 1], scaled to [0, 255], rounded,
\  packed as:  bits [31:24]=R  [23:16]=G  [15:8]=B  [7:0]=A

VARIABLE _CL-PK-T

0x5BF8 CONSTANT _CL-255              \ 255.0 in FP16

: _CL-FP16>BYTE  ( fp16 -- 0..255 )
    _CL-CLAMP01
    _CL-255 FP16-MUL
    FP16-ROUND FP16>INT
    0 MAX 255 MIN ;

: COLOR-PACK-RGBA  ( r g b a -- packed )
    _CL-FP16>BYTE                      ( r g b a8 )
    SWAP _CL-FP16>BYTE 8 LSHIFT OR    ( r g ba )
    SWAP _CL-FP16>BYTE 16 LSHIFT OR   ( r gba )
    SWAP _CL-FP16>BYTE 24 LSHIFT OR   ( rgba )
    ;

\ =====================================================================
\  COLOR-UNPACK-RGBA — Unpack 32-bit RGBA8888 to 4 FP16 channels
\ =====================================================================

: _CL-BYTE>FP16  ( 0..255 -- fp16 )
    INT>FP16 _CL-255 FP16-DIV ;

: COLOR-UNPACK-RGBA  ( packed -- r g b a )
    DUP 24 RSHIFT 0xFF AND _CL-BYTE>FP16 SWAP   ( r packed )
    DUP 16 RSHIFT 0xFF AND _CL-BYTE>FP16 SWAP   ( r g packed )
    DUP  8 RSHIFT 0xFF AND _CL-BYTE>FP16 SWAP   ( r g b packed )
              0xFF AND _CL-BYTE>FP16             ( r g b a )
    ;

\ =====================================================================
\  COLOR-PACK-RGB565 — Pack FP16 RGB to 16-bit RGB565
\ =====================================================================
\  R: 5 bits [15:11], G: 6 bits [10:5], B: 5 bits [4:0]

0x4FC0 CONSTANT _CL-31               \ 31.0 in FP16
0x53E0 CONSTANT _CL-63               \ 63.0 in FP16

: COLOR-PACK-RGB565  ( r g b -- packed )
    _CL-CLAMP01 _CL-31 FP16-MUL FP16-ROUND FP16>INT 0 MAX 31 MIN
    SWAP
    _CL-CLAMP01 _CL-63 FP16-MUL FP16-ROUND FP16>INT 0 MAX 63 MIN
    5 LSHIFT OR
    SWAP
    _CL-CLAMP01 _CL-31 FP16-MUL FP16-ROUND FP16>INT 0 MAX 31 MIN
    11 LSHIFT OR ;

\ =====================================================================
\  COLOR-HEX-PARSE — Parse CSS hex color string
\ =====================================================================
\  Accepts:  #RGB  #RRGGBB  (with or without leading #)
\  Returns:  r g b flag   (flag = TRUE if successful)
\  Channels are returned as FP16 in [0, 1].

VARIABLE _CL-HP-ADDR
VARIABLE _CL-HP-LEN

: _CL-HEXCHAR  ( char -- value flag )
    DUP [CHAR] 0 >= OVER [CHAR] 9 <= AND IF
        [CHAR] 0 - TRUE EXIT
    THEN
    DUP [CHAR] A >= OVER [CHAR] F <= AND IF
        [CHAR] A - 10 + TRUE EXIT
    THEN
    DUP [CHAR] a >= OVER [CHAR] f <= AND IF
        [CHAR] a - 10 + TRUE EXIT
    THEN
    DROP 0 FALSE ;

: _CL-PARSE-BYTE  ( addr -- value flag )
    DUP C@ _CL-HEXCHAR           ( addr hi flag )
    0= IF 2DROP 0 FALSE EXIT THEN
    SWAP 1+ C@ _CL-HEXCHAR       ( hi lo flag )
    0= IF 2DROP 0 FALSE EXIT THEN
    SWAP 4 LSHIFT OR TRUE ;

: COLOR-HEX-PARSE  ( addr len -- r g b flag )
    \ Skip leading # if present
    OVER C@ [CHAR] # = IF 1- SWAP 1+ SWAP THEN
    _CL-HP-LEN !  _CL-HP-ADDR !

    _CL-HP-LEN @ CASE
        3 OF
            \ #RGB → expand each nibble: R → RR, G → GG, B → BB
            _CL-HP-ADDR @ C@ _CL-HEXCHAR 0= IF
                _CL-ZERO _CL-ZERO _CL-ZERO FALSE EXIT THEN
            DUP 4 LSHIFT OR _CL-BYTE>FP16       ( r )
            _CL-HP-ADDR @ 1+ C@ _CL-HEXCHAR 0= IF
                DROP _CL-ZERO _CL-ZERO FALSE EXIT THEN
            DUP 4 LSHIFT OR _CL-BYTE>FP16       ( r g )
            _CL-HP-ADDR @ 2 + C@ _CL-HEXCHAR 0= IF
                2DROP _CL-ZERO FALSE EXIT THEN
            DUP 4 LSHIFT OR _CL-BYTE>FP16       ( r g b )
            TRUE
        ENDOF
        6 OF
            \ #RRGGBB
            _CL-HP-ADDR @ _CL-PARSE-BYTE 0= IF
                _CL-ZERO _CL-ZERO _CL-ZERO FALSE EXIT THEN
            _CL-BYTE>FP16                        ( r )
            _CL-HP-ADDR @ 2 + _CL-PARSE-BYTE 0= IF
                DROP _CL-ZERO _CL-ZERO FALSE EXIT THEN
            _CL-BYTE>FP16                        ( r g )
            _CL-HP-ADDR @ 4 + _CL-PARSE-BYTE 0= IF
                2DROP _CL-ZERO FALSE EXIT THEN
            _CL-BYTE>FP16                        ( r g b )
            TRUE
        ENDOF
        \ Unknown length
        _CL-ZERO _CL-ZERO _CL-ZERO FALSE
    ENDCASE
    ;

\ ── Concurrency ──────────────────────────────────────────
\ Color words are NOT reentrant.  They use shared VARIABLE
\ scratch for intermediate results.  Callers must ensure
\ single-task access via WITH-GUARD, WITH-CRITICAL, or by
\ running with preemption disabled.
