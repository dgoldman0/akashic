\ fp16-ext.f — Extended FP16 operations
\
\ Built on fp16.f.  Adds comparisons, lerp, reciprocal,
\ division, square root, clamp, floor/frac, and fixed-point
\ conversions.
\
\ Prefix: FP16-   (public API)
\         _FX-    (internal helpers)
\
\ Load with:   REQUIRE fp16-ext.f
\   (auto-loads fp16.f via REQUIRE)
\
\ === Public API ===
\   FP16-LT     ( a b -- flag )    a < b
\   FP16-GT     ( a b -- flag )    a > b
\   FP16-LE     ( a b -- flag )    a <= b
\   FP16-GE     ( a b -- flag )    a >= b
\   FP16-EQ     ( a b -- flag )    a = b (±0 equal)
\   FP16-LERP   ( a b t -- r )    linear interpolation
\   FP16-CLAMP  ( x lo hi -- r )  clamp to [lo,hi]
\   FP16-RECIP  ( a -- 1/a )      reciprocal (Newton-Raphson)
\   FP16-DIV    ( a b -- a/b )    division
\   FP16-SQRT   ( a -- sqrt )     square root (Newton-Raphson)
\   FP16-FLOOR  ( a -- floor )    floor to integral FP16
\   FP16-FRAC   ( a -- frac )     fractional part
\   FP16-ROUND  ( a -- rounded )  round to nearest integer (half-up)
\   FP16>FX     ( fp16 -- fx )    FP16 → 16.16 fixed-point
\   FX>FP16     ( fx -- fp16 )    16.16 fixed-point → FP16

REQUIRE fp16.f

PROVIDED akashic-fp16-ext

\ =====================================================================
\  Comparisons
\ =====================================================================
\  IEEE 754 FP16 has a nice property: for non-NaN values, if we
\  treat the bit pattern as sign-magnitude integer, the ordering
\  is preserved.  We convert to two's complement for easy compare.
\
\  sign-mag → two's complement:
\    if negative (bit 15 set): val = 0x8000 - (raw & 0x7FFF)
\                                  = 0x8000 - raw + 0x8000
\                                  BUT simpler: invert low 15 + 1?
\    Actually: if bit15=1, twos = -(raw & 0x7FFF) = 0 - (raw & 0x7FFF)
\              if bit15=0, twos = raw
\  But we need unsigned compare after.  Easier approach:
\    Map to sortable integer: if negative, flip = 0xFFFF - raw
\                             if positive, flip = raw + 0x8000
\  Then unsigned compare on flip values gives correct FP16 ordering.
\  Both ±0 map to 0x8000, so they compare equal.

: _FP16-SORTKEY  ( fp16 -- key )
    0xFFFF AND
    \ Canonicalize ±0 → +0 so both map to same key
    DUP 0x7FFF AND 0= IF DROP 0 THEN
    DUP 0x8000 AND IF
        \ negative: flip all bits → 0xFFFF XOR raw
        \   -smallest → near 0x7FFF, -inf (0xFC00) → 0x03FF
        0xFFFF XOR
    ELSE
        \ positive: add 0x8000 so positive > all negatives
        0x8000 +
    THEN
    0xFFFF AND ;

: FP16-LT  ( a b -- flag )
    _FP16-SORTKEY SWAP _FP16-SORTKEY SWAP
    ( key-a key-b )  U< ;

: FP16-GT  ( a b -- flag )
    SWAP FP16-LT ;

: FP16-LE  ( a b -- flag )
    FP16-GT 0= ;

: FP16-GE  ( a b -- flag )
    FP16-LT 0= ;

: FP16-EQ  ( a b -- flag )
    \ Handle ±0: both map to same sort key
    _FP16-SORTKEY SWAP _FP16-SORTKEY = ;

\ =====================================================================
\  FP16-LERP — linear interpolation: a + t*(b - a)
\ =====================================================================
\  Uses FMA: result = t * (b-a) + a
\  So we put (b-a) in src0, t in src1, a in dst, then TFMA.

: FP16-LERP  ( a b t -- result )
    >R                                 \ save t
    OVER FP16-SUB                      ( a b-a )   ( R: t )
    R>                                 ( a b-a t )
    \ FMA: src0 * src1 + dst = (b-a) * t + a
    ROT                               ( b-a t a )
    FP16-FMA ;                         \ (b-a) t a → (b-a)*t + a

\ =====================================================================
\  FP16-CLAMP — clamp x to [lo, hi]
\ =====================================================================

: FP16-CLAMP  ( x lo hi -- clamped )
    ROT                                ( lo hi x )
    OVER FP16-MIN                      ( lo hi min[x,hi] )
    ROT FP16-MAX ;                     ( max[min[x,hi], lo] )

\ =====================================================================
\  FP16-RECIP — reciprocal via Newton-Raphson
\ =====================================================================
\  Initial estimate: manipulate exponent.
\    For x = 1.m × 2^e, 1/x ≈ 1.0 × 2^(-e)
\    Magic: recip0 = 0x7BFC - x  (for positive x)
\    This gives a rough estimate good to ~3 bits.
\    Then refine: r' = r * (2 - x*r)   [Newton step]
\    Two iterations → ~10 bit accuracy (full FP16 mantissa).
\
\  Handle sign: compute recip of |x|, restore sign.

VARIABLE _FR-SIGN

: FP16-RECIP  ( a -- 1/a )
    0xFFFF AND
    DUP 0x8000 AND _FR-SIGN !         \ save sign
    0x7FFF AND                         \ work with |a|
    DUP 0= IF DROP FP16-POS-INF _FR-SIGN @ OR EXIT THEN
    DUP FP16-POS-INF = IF DROP FP16-POS-ZERO _FR-SIGN @ OR EXIT THEN
    \ Initial estimate: 0x7800 - x  (log-linear: 30*1024 - x)
    \ Exact for powers of 2, ~3 bits for others.
    DUP >R                            ( |a| ) ( R: |a| )
    0x7800 SWAP - 0xFFFF AND          ( r0 )
    \ Newton iteration 1: r = r * (2 - a*r)
    DUP R@ FP16-MUL                   ( r0 a*r0 )
    0x4000 SWAP FP16-SUB              ( r0 2-a*r0 )
    FP16-MUL                          ( r1 )
    \ Newton iteration 2: r = r * (2 - a*r)
    DUP R> FP16-MUL                   ( r1 a*r1 )
    0x4000 SWAP FP16-SUB              ( r1 2-a*r1 )
    FP16-MUL                          ( r2 )
    \ Restore sign
    _FR-SIGN @ OR
    0xFFFF AND ;

\ =====================================================================
\  FP16-DIV — division: a / b = a * recip(b)
\ =====================================================================

: FP16-DIV  ( a b -- a/b )
    FP16-RECIP FP16-MUL ;

\ =====================================================================
\  FP16-SQRT — square root via Newton-Raphson
\ =====================================================================
\  For x: initial estimate from halved exponent.
\    exp_bits = (x >> 10) & 0x1F
\    rough: ((exp_bits - 15) / 2 + 15) << 10 | (mantissa >> 1)
\    Simpler magic: sqrt0 = (x >> 1) + 0x1C00
\    Then refine: s' = 0.5 * (s + x/s)   [Newton step]
\    Two iterations.
\
\  Negative input → return qNaN.
\  Zero → zero.

: FP16-SQRT  ( a -- sqrt[a] )
    0xFFFF AND
    DUP 0x8000 AND IF DROP FP16-QNAN EXIT THEN   \ negative → NaN
    DUP 0= IF EXIT THEN                           \ sqrt(0) = 0
    DUP FP16-POS-INF = IF EXIT THEN               \ sqrt(inf) = inf
    DUP >R                             ( x ) ( R: x )
    \ Initial estimate: (x >> 1) + 0x1C00
    1 RSHIFT 0x1C00 + 0xFFFF AND       ( s0 )
    \ Newton iteration 1: s = 0.5 * (s + x/s)
    DUP R@ SWAP FP16-DIV              ( s0 x/s0 )
    FP16-ADD                           ( s0+x/s0 )
    FP16-POS-HALF FP16-MUL            ( s1 )
    \ Newton iteration 2: s = 0.5 * (s + x/s)
    DUP R@ SWAP FP16-DIV              ( s1 x/s1 )
    FP16-ADD                           ( s1+x/s1 )
    FP16-POS-HALF FP16-MUL            ( s2 )
    \ Final correction: if s2*s2 > x, subtract 1 ULP
    DUP DUP FP16-MUL R> FP16-GT IF 1 - 0xFFFF AND THEN ;

\ =====================================================================
\  FP16-FLOOR — floor to integral FP16 value
\ =====================================================================
\  Convert to integer (truncating toward zero), then back.
\  For negative non-integers, subtract 1 before converting.

: FP16-FLOOR  ( a -- floor )
    DUP FP16>INT INT>FP16              ( a floor_toward_zero )
    \ If a was negative and had a fractional part, floor is one less
    OVER FP16-SIGN IF                  \ negative?
        2DUP FP16-EQ 0= IF            \ a ≠ trunc(a)?
            FP16-POS-ONE FP16-SUB     \ floor = trunc - 1
        THEN
    THEN
    NIP ;

\ =====================================================================
\  FP16-FRAC — fractional part: a - floor(a)
\ =====================================================================

: FP16-FRAC  ( a -- frac )
    DUP FP16-FLOOR FP16-SUB ;

\ =====================================================================
\  FP16-ROUND — round to nearest integer (half-up)
\ =====================================================================
\  round(x) = floor(x + 0.5)

: FP16-ROUND  ( a -- rounded )
    FP16-POS-HALF FP16-ADD FP16-FLOOR ;

\ =====================================================================
\  FP16 ↔ 16.16 fixed-point conversion
\ =====================================================================
\  16.16 fixed: 16 integer bits + 16 fractional bits.
\  Value = raw / 65536.
\
\  FP16>FX: Extract sign, exponent, mantissa from FP16.
\    mantissa with implicit 1 = 11 bits (1.10 format).
\    Shift to align with 16.16: shift left by (exp - 15 + 16 - 10) = (exp - 9)
\    If exp < 9, shift right by (9 - exp).

VARIABLE _FX-SIGN
VARIABLE _FX-EXP
VARIABLE _FX-MANT

: FP16>FX  ( fp16 -- fx )
    0xFFFF AND
    DUP 0x8000 AND IF 1 ELSE 0 THEN _FX-SIGN !
    0x7FFF AND
    DUP 0= IF _FX-SIGN @ IF NEGATE THEN EXIT THEN    \ ±0 → 0
    DUP FP16-POS-INF >= IF DROP 0x7FFFFFFF _FX-SIGN @ IF NEGATE THEN EXIT THEN
    DUP 10 RSHIFT 0x1F AND _FX-EXP !
    0x3FF AND 0x400 OR _FX-MANT !     \ mantissa with implicit 1 (11 bits)
    _FX-EXP @ 0= IF 0 EXIT THEN       \ denormals → 0
    \ Shift amount: exp - 15 + 16 - 10 = exp - 9
    _FX-EXP @ 9 - DUP 0 >= IF
        _FX-MANT @ SWAP LSHIFT
    ELSE
        NEGATE _FX-MANT @ SWAP RSHIFT
    THEN
    _FX-SIGN @ IF NEGATE THEN ;

\ FX>FP16: Convert 16.16 fixed-point to FP16.
\   In 16.16, value = raw / 65536.  So actual exponent = msb_pos - 16,
\   and FP16 biased exponent = msb_pos - 16 + 15 = msb_pos - 1.

VARIABLE _XF-SIGN
VARIABLE _XF-MAG
VARIABLE _XF-MSB
VARIABLE _XF-EXP

: FX>FP16  ( fx -- fp16 )
    DUP 0= IF DROP FP16-POS-ZERO EXIT THEN
    DUP 0 < IF
        NEGATE 1 _XF-SIGN !
    ELSE
        0 _XF-SIGN !
    THEN
    _XF-MAG !
    \ Find highest set bit position (0-based)
    0 _XF-MSB !
    _XF-MAG @
    BEGIN DUP 1 > WHILE
        1 RSHIFT
        _XF-MSB @ 1+ _XF-MSB !
    REPEAT
    DROP
    \ Biased exponent: msb_pos - 1  (accounting for 16.16 offset)
    _XF-MSB @ 1 - _XF-EXP !
    _XF-EXP @ 0 <= IF
        _XF-SIGN @ IF 0x8000 ELSE 0 THEN EXIT
    THEN
    _XF-EXP @ 30 > IF
        _XF-SIGN @ IF 0xFBFF ELSE 0x7BFF THEN EXIT
    THEN
    \ Extract 10-bit mantissa: shift |fx| to drop implicit 1
    _XF-MSB @ 10 > IF
        _XF-MAG @ _XF-MSB @ 10 - RSHIFT
    ELSE
        _XF-MAG @ 10 _XF-MSB @ - LSHIFT
    THEN
    0x3FF AND                          ( frac10 )
    _XF-EXP @ 10 LSHIFT OR            ( fp16_unsigned )
    _XF-SIGN @ IF 0x8000 OR THEN
    0xFFFF AND ;
