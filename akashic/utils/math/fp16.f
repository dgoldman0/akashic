\ fp16.f — IEEE 754 half-precision math via tile engine
\
\ The tile engine on Megapad-64 provides 32-lane FP16 SIMD.
\ This library wraps it for scalar FP16 operations by using
\ lane 0 of aligned 64-byte tile buffers in HBW math RAM.
\
\ FP16 values are stored as 16-bit raw on the Forth data stack.
\ Conversion to/from integer uses fixed-point scaling.
\
\ Prefix: FP16-   (public API)
\         _FP16-  (internal helpers)
\
\ Load with:   REQUIRE fp16.f
\
\ === Public API ===
\   FP16-ADD    ( a b -- a+b )       half-precision add
\   FP16-SUB    ( a b -- a-b )       half-precision subtract
\   FP16-MUL    ( a b -- a*b )       half-precision multiply
\   FP16-NEG    ( a -- -a )          negate (flip sign bit)
\   FP16-ABS    ( a -- |a| )         absolute value (clear sign bit)
\   FP16-SIGN   ( a -- flag )        sign bit: 0 = positive, -1 = negative
\   FP16>INT    ( fp16 -- n )        truncate FP16 to signed integer
\   INT>FP16    ( n -- fp16 )        convert signed integer to FP16
\   FP16-FMA    ( a b c -- a*b+c )   fused multiply-add
\   FP16-MIN    ( a b -- min )       elementwise minimum
\   FP16-MAX    ( a b -- max )       elementwise maximum
\   FP16-ZERO   ( -- fp16 )         +0.0 literal
\   FP16-ONE    ( -- fp16 )         +1.0 literal
\   FP16-HALF   ( -- fp16 )         +0.5 literal
\   FP16-DOT    ( addr n -- acc )    dot product of n FP16 pairs
\
\ Internal tile buffers are allocated in HBW at module load time.
\ All operations set FP16-MODE before use and are not re-entrant.

PROVIDED akashic-fp16

\ =====================================================================
\  Constants: well-known FP16 bit patterns
\ =====================================================================

0x0000 CONSTANT FP16-POS-ZERO      \ +0.0
0x8000 CONSTANT FP16-NEG-ZERO      \ -0.0
0x3C00 CONSTANT FP16-POS-ONE       \ +1.0
0xBC00 CONSTANT FP16-NEG-ONE       \ -1.0
0x3800 CONSTANT FP16-POS-HALF      \ +0.5
0x7C00 CONSTANT FP16-POS-INF       \ +inf
0xFC00 CONSTANT FP16-NEG-INF       \ -inf
0x7E00 CONSTANT FP16-QNAN          \ quiet NaN

: FP16-ZERO FP16-POS-ZERO ;
: FP16-ONE  FP16-POS-ONE ;
: FP16-HALF FP16-POS-HALF ;

\ =====================================================================
\  Internal: tile buffers in HBW for scalar ops
\ =====================================================================
\  We need three 64-byte aligned tiles: SRC0, SRC1, DST.
\  HBW-ALLOT returns 64-byte-aligned addresses.

VARIABLE _FP16-TA                      \ tile A (src0)
VARIABLE _FP16-TB                      \ tile B (src1)
VARIABLE _FP16-TD                      \ tile D (dst)

\ Initialize tile buffers.  Call once at load time.
: _FP16-INIT-TILES  ( -- )
    64 HBW-ALLOT _FP16-TA !
    64 HBW-ALLOT _FP16-TB !
    64 HBW-ALLOT _FP16-TD !
    \ Zero all three tiles
    _FP16-TA @ 64 0 FILL
    _FP16-TB @ 64 0 FILL
    _FP16-TD @ 64 0 FILL ;

_FP16-INIT-TILES

\ =====================================================================
\  Internal: set up tile engine for scalar FP16 binary op
\ =====================================================================

: _FP16-SETUP2  ( a b -- )
    \ Store b in lane 0 of tile B, a in lane 0 of tile A
    _FP16-TB @ W!                      ( a )
    _FP16-TA @ W!                      ( )
    FP16-MODE
    _FP16-TA @ TSRC0!
    _FP16-TB @ TSRC1!
    _FP16-TD @ TDST! ;

: _FP16-RESULT  ( -- fp16 )
    _FP16-TD @ W@ 0xFFFF AND ;

\ =====================================================================
\  Arithmetic operations
\ =====================================================================

: FP16-ADD  ( a b -- a+b )
    _FP16-SETUP2 TADD _FP16-RESULT ;

: FP16-SUB  ( a b -- a-b )
    _FP16-SETUP2 TSUB _FP16-RESULT ;

: FP16-MUL  ( a b -- a*b )
    _FP16-SETUP2 TMUL _FP16-RESULT ;

: FP16-MIN  ( a b -- min )
    _FP16-SETUP2 TEMIN _FP16-RESULT ;

: FP16-MAX  ( a b -- max )
    _FP16-SETUP2 TEMAX _FP16-RESULT ;

\ =====================================================================
\  Unary operations (bit manipulation — no tile engine needed)
\ =====================================================================

: FP16-NEG  ( a -- -a )
    0x8000 XOR 0xFFFF AND ;

: FP16-ABS  ( a -- |a| )
    0x7FFF AND ;

: FP16-SIGN  ( a -- flag )
    0x8000 AND IF -1 ELSE 0 THEN ;

\ =====================================================================
\  FP16-FMA — fused multiply-add: a*b + c
\ =====================================================================
\  Tile engine FMA: dst[i] = src0[i] * src1[i] + dst[i]
\  So we put c in dst, a in src0, b in src1, then TFMA.

: FP16-FMA  ( a b c -- a*b+c )
    _FP16-TD @ W!                      \ c → dst lane 0
    _FP16-TB @ W!                      \ b → src1 lane 0
    _FP16-TA @ W!                      \ a → src0 lane 0
    FP16-MODE
    _FP16-TA @ TSRC0!
    _FP16-TB @ TSRC1!
    _FP16-TD @ TDST!
    TFMA
    _FP16-RESULT ;

\ =====================================================================
\  INT>FP16 — convert signed integer to FP16
\ =====================================================================
\  Algorithm: decompose into sign + magnitude, find exponent via CLZ,
\  shift mantissa into position, assemble FP16 bits.
\  Range: -65504 to +65504 (FP16 max).

VARIABLE _IF-SIGN
VARIABLE _IF-MAG
VARIABLE _IF-EXP
VARIABLE _IF-FRAC

: INT>FP16  ( n -- fp16 )
    DUP 0= IF DROP FP16-POS-ZERO EXIT THEN
    DUP 0 < IF
        NEGATE 1 _IF-SIGN !
    ELSE
        0 _IF-SIGN !
    THEN
    DUP 65504 > IF DROP 65504 THEN    \ clamp to FP16 max
    _IF-MAG !
    \ Find highest set bit position (0-based)
    0 _IF-EXP !
    _IF-MAG @
    BEGIN DUP 1 > WHILE
        1 RSHIFT
        _IF-EXP @ 1+ _IF-EXP !
    REPEAT
    DROP
    \ exponent bias = 15
    _IF-EXP @ 15 +                     ( biased_exp )
    \ fraction: shift magnitude to drop the implicit 1, keep 10 bits
    _IF-EXP @ 10 > IF
        _IF-MAG @ _IF-EXP @ 10 - RSHIFT
    ELSE
        _IF-MAG @ 10 _IF-EXP @ - LSHIFT
    THEN
    0x3FF AND                          ( biased_exp frac10 )
    SWAP 10 LSHIFT OR                  ( fp16_unsigned )
    _IF-SIGN @ IF 0x8000 OR THEN
    0xFFFF AND ;

\ =====================================================================
\  FP16>INT — truncate FP16 to signed integer
\ =====================================================================
\  Drops the fractional part (truncates toward zero).

VARIABLE _FI-SIGN
VARIABLE _FI-EXP
VARIABLE _FI-FRAC
VARIABLE _FI-MANT

: FP16>INT  ( fp16 -- n )
    0xFFFF AND
    DUP 0x8000 AND IF 1 ELSE 0 THEN _FI-SIGN !
    0x7FFF AND                         ( abs )
    DUP FP16-POS-INF >= IF DROP 0 EXIT THEN
    DUP 10 RSHIFT 0x1F AND _FI-EXP !
    0x3FF AND 0x400 OR _FI-MANT !     ( )  \ mantissa with implicit 1
    _FI-EXP @ 0= IF 0 EXIT THEN
    _FI-EXP @ 15 - _FI-EXP !          \ unbias
    _FI-EXP @ 0 < IF 0 EXIT THEN      \ |val| < 1
    \ Shift mantissa: mantissa has 10 fraction bits + 1 implicit bit
    \ If exp >= 10: shift left by (exp - 10)
    \ If exp < 10:  shift right by (10 - exp) — truncates fraction
    _FI-EXP @ 10 >= IF
        _FI-MANT @ _FI-EXP @ 10 - LSHIFT
    ELSE
        _FI-MANT @ 10 _FI-EXP @ - RSHIFT
    THEN
    _FI-SIGN @ IF NEGATE THEN ;
