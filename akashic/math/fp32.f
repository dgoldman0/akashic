\ fp32.f — IEEE 754 single-precision (binary32) arithmetic
\
\ A float is packed in the low 32 bits of a 64-bit Forth cell.  The
\ words run on MegaPad's scalar FP32 instructions, so every result is
\ the correctly rounded IEEE 754 result in the rounding mode in FPCSR:
\ round to nearest even unless a caller changes it.  Every NaN result
\ is the canonical quiet NaN, FP32-NAN.  The words hold no state, so
\ any task or core may use them.
\
\ Layout of an IEEE 754 binary32 value (32 bits):
\   [31]    sign       1 bit
\   [30:23] exponent   8 bits (biased by 127)
\   [22:0]  mantissa   23 bits (implicit leading 1 for normals)
\
\ A fixed-point value (fixed.f) is a signed cell whose low 16 bits are
\ the fraction.
\
\ Prefix: FP32-   (public API)
\         _FP32-  (internal constants)
\
\ Load with:   REQUIRE fp32.f
\
\ === Public API ===
\   FP32-ADD     ( a b -- a+b )      addition
\   FP32-SUB     ( a b -- a-b )      subtraction
\   FP32-MUL     ( a b -- a*b )      multiplication
\   FP32-DIV     ( a b -- a/b )      division
\   FP32-FMA     ( a b c -- a*b+c )  fused multiply-add, one rounding
\   FP32-SQRT    ( a -- sqrt )       square root
\   FP32-RECIP   ( a -- 1/a )        reciprocal
\   FP32-NEGATE  ( a -- -a )         flip the sign bit
\   FP32-ABS     ( a -- |a| )        clear the sign bit
\   FP32<        ( a b -- flag )     less-than
\   FP32>        ( a b -- flag )     greater-than
\   FP32=        ( a b -- flag )     equality, -0 = +0
\   FP32<=       ( a b -- flag )     less-or-equal
\   FP32>=       ( a b -- flag )     greater-or-equal
\   FP32-0=      ( a -- flag )       is it -0 or +0?
\   FP32-MIN     ( a b -- min )      minimum, -0 below +0
\   FP32-MAX     ( a b -- max )      maximum, -0 below +0
\   FP16>FP32    ( fp16 -- fp32 )    widen, exact
\   FP32>FP16    ( fp32 -- fp16 )    narrow, rounded
\   FP32>FX      ( fp32 -- fx )      to fixed point, toward zero
\   FX>FP32      ( fx -- fp32 )      from fixed point, rounded
\   FP32>INT     ( fp32 -- n )       to an integer, toward zero
\   INT>FP32     ( n -- fp32 )       from an integer, rounded
\   ACC>FP32     ( -- fp32 )         low 32 bits of the tile accumulator
\
\ The comparisons are false when either value is NaN, and MIN and MAX
\ return NaN when either value is NaN.  The conversions to fixed point
\ and to an integer give 0 for NaN and saturate at the cell's range.

PROVIDED akashic-fp32

\ =====================================================================
\  Constants: well-known FP32 bit patterns
\ =====================================================================

0x00000000 CONSTANT FP32-ZERO
0x3F800000 CONSTANT FP32-ONE
0x3F000000 CONSTANT FP32-HALF
0x40000000 CONSTANT FP32-TWO
0x40490FDB CONSTANT FP32-PI
0x402DF854 CONSTANT FP32-E
0x7F800000 CONSTANT FP32-INF
0x7FC00000 CONSTANT FP32-NAN

0x47800000 CONSTANT _FP32-65536       \ 2^16
0x37800000 CONSTANT _FP32-1/65536     \ 2^-16

\ =====================================================================
\  Arithmetic
\ =====================================================================

: FP32-ADD  ( a b -- a+b )  F32+ ;
: FP32-SUB  ( a b -- a-b )  F32- ;
: FP32-MUL  ( a b -- a*b )  F32* ;
: FP32-DIV  ( a b -- a/b )  F32/ ;
: FP32-FMA  ( a b c -- a*b+c )  F32FMA ;
: FP32-SQRT  ( a -- sqrt[a] )  F32SQRT ;
: FP32-RECIP  ( a -- 1/a )  FP32-ONE SWAP F32/ ;

\ =====================================================================
\  Sign
\ =====================================================================

: FP32-NEGATE  ( a -- -a )  0x80000000 XOR 0xFFFFFFFF AND ;
: FP32-ABS  ( a -- |a| )  0x7FFFFFFF AND ;
: FP32-0=  ( a -- flag )  0x7FFFFFFF AND 0= ;

\ =====================================================================
\  Comparison
\ =====================================================================

: FP32<   ( a b -- flag )  F32< ;
: FP32>   ( a b -- flag )  SWAP F32< ;
: FP32=   ( a b -- flag )  F32= ;
: FP32<=  ( a b -- flag )  F32<= ;
: FP32>=  ( a b -- flag )  SWAP F32<= ;
: FP32-MIN  ( a b -- min )  F32MIN ;
: FP32-MAX  ( a b -- max )  F32MAX ;

\ =====================================================================
\  Conversions
\ =====================================================================
\  Scaling by 2^16 is exact, so the fixed-point conversions round at
\  most once, like the integer ones.

: FP16>FP32  ( fp16 -- fp32 )  F16>F32 ;
: FP32>FP16  ( fp32 -- fp16 )  F32>F16 ;
: FP32>FX  ( fp32 -- fx )  _FP32-65536 F32* F32>S ;
: FX>FP32  ( fx -- fp32 )  S>F32 _FP32-1/65536 F32* ;
: FP32>INT  ( fp32 -- n )  F32>S ;
: INT>FP32  ( n -- fp32 )  S>F32 ;

\ After an FP16 or BF16 reduction, the tile engine's accumulator
\ (ACC@, CSR 0x19) holds its binary32 result in the low 32 bits.  FP32
\ and FP64 reductions leave binary64 there instead.
: ACC>FP32  ( -- fp32 )  ACC@ 0xFFFFFFFF AND ;
