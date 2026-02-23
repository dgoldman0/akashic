\ fixed.f — 16.16 fixed-point arithmetic
\
\ Value representation: signed 64-bit cell where the low 16 bits
\ are the fractional part.  Value = raw / 65536.
\
\ On Megapad-64 (64-bit cells), intermediate products of two 32-bit
\ fixed-point values fit in a single cell, so no double-width math
\ is needed.
\
\ Prefix: FX-  (public API)
\
\ Load with:   REQUIRE fixed.f
\
\ === Public API ===
\   FX*       ( a b -- a*b )       fixed multiply
\   FX/       ( a b -- a/b )       fixed divide
\   FX-ABS    ( a -- |a| )         absolute value
\   FX-NEG    ( a -- -a )          negate
\   FX-SIGN   ( a -- -1|0|1 )     sign
\   INT>FX    ( n -- fx )          integer to 16.16
\   FX>INT    ( fx -- n )          truncate to integer
\   FX-FRAC   ( fx -- fx )         fractional part only
\   FX-FLOOR  ( fx -- fx )         floor (round toward -inf)
\   FX-CEIL   ( fx -- fx )         ceiling (round toward +inf)
\   FX-ROUND  ( fx -- fx )         round to nearest integer
\   FX-LERP   ( a b t -- r )      linear interpolation, t in FX
\   FX-MIN    ( a b -- min )       minimum
\   FX-MAX    ( a b -- max )       maximum
\   FX-CLAMP  ( x lo hi -- r )    clamp to [lo, hi]
\
\ Constants:
\   FX-ONE    ( -- 65536 )         1.0 in 16.16
\   FX-HALF   ( -- 32768 )         0.5 in 16.16
\   FX-ZERO   ( -- 0 )             0.0 in 16.16

PROVIDED akashic-fixed

\ =====================================================================
\  Constants
\ =====================================================================

65536 CONSTANT FX-ONE
32768 CONSTANT FX-HALF
    0 CONSTANT FX-ZERO

\ =====================================================================
\  Conversion
\ =====================================================================

: INT>FX  ( n -- fx )   16 LSHIFT ;
: FX>INT  ( fx -- n )   65536 / ;

\ =====================================================================
\  Basic arithmetic
\ =====================================================================

: FX*  ( a b -- a*b )
    \ (a * b) / 65536.  64-bit intermediate never overflows for
    \ reasonable 16.16 values (±32767.9999).
    \ Use signed division (not RSHIFT which is unsigned).
    * 65536 / ;

: FX/  ( a b -- a/b )
    \ (a << 16) / b.
    SWAP 16 LSHIFT SWAP / ;

: FX-ABS  ( a -- |a| )  DUP 0 < IF NEGATE THEN ;
: FX-NEG  ( a -- -a )   NEGATE ;

: FX-SIGN  ( a -- -1|0|1 )
    DUP 0 < IF DROP -1 EXIT THEN
    0 > IF 1 ELSE 0 THEN ;

\ =====================================================================
\  Rounding / fractional
\ =====================================================================

: FX-FRAC  ( fx -- fx )
    \ Fractional part: x - floor(x).  Always non-negative.
    DUP 0 < IF
        0xFFFF AND DUP IF FX-ONE SWAP - ELSE THEN
    ELSE
        0xFFFF AND
    THEN ;

: FX-FLOOR  ( fx -- fx )
    \ Clear fractional bits.  In two's complement, this rounds
    \ toward -inf for both positive and negative values.
    0xFFFF INVERT AND ;

: FX-CEIL  ( fx -- fx )
    \ Round toward +inf.
    DUP 0xFFFF AND IF                  \ has fractional part?
        0xFFFF INVERT AND FX-ONE +
    THEN ;

: FX-ROUND  ( fx -- fx )
    \ Round to nearest (half rounds up).
    FX-HALF + FX-FLOOR ;

\ =====================================================================
\  Min / Max / Clamp
\ =====================================================================

: FX-MIN  ( a b -- min )  2DUP > IF SWAP THEN DROP ;
: FX-MAX  ( a b -- max )  2DUP < IF SWAP THEN DROP ;

: FX-CLAMP  ( x lo hi -- clamped )
    ROT OVER MIN ROT MAX ;

\ =====================================================================
\  FX-LERP — linear interpolation: a + t*(b - a)
\ =====================================================================
\  t is in 16.16 scaled [0, FX-ONE].

: FX-LERP  ( a b t -- result )
    >R OVER - R> FX* + ;
