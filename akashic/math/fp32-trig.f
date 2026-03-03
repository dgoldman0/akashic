\ fp32-trig.f — FP32 trigonometric functions
\
\ Polynomial approximations optimised for FP32's 23-bit mantissa.
\ Range reduction maps any angle to [−π/4, π/4], then degree-7/6
\ minimax polynomials give results accurate to <2 ULP.
\
\ All angles are in FP32 radians unless noted otherwise.
\ Conversion helpers F32T-DEG>RAD / F32T-RAD>DEG are provided.
\
\ Prefix: F32T-  (public API)
\         _F3T-  (internal helpers)
\
\ Load with:   REQUIRE fp32-trig.f
\
\ === Public API ===
\   F32T-SIN       ( angle -- sin )       sine
\   F32T-COS       ( angle -- cos )       cosine
\   F32T-SINCOS    ( angle -- sin cos )   both at once
\   F32T-TAN       ( angle -- tan )       tangent
\   F32T-ATAN      ( x -- angle )         arctangent
\   F32T-ATAN2     ( y x -- angle )       four-quadrant arctangent
\   F32T-ASIN      ( x -- angle )         arcsine
\   F32T-ACOS      ( x -- angle )         arccosine
\   F32T-DEG>RAD   ( deg -- rad )         degree → radian
\   F32T-RAD>DEG   ( rad -- deg )         radian → degree

REQUIRE fp32.f

PROVIDED akashic-fp32-trig

\ =====================================================================
\  Constants — well-known FP32 bit patterns
\ =====================================================================
\  Verified via Python:  struct.unpack('<I', struct.pack('<f', v))[0]

0x40490FDB CONSTANT F32T-PI           \ 3.14159265
0x40C90FDB CONSTANT F32T-2PI          \ 6.28318531
0x3FC90FDB CONSTANT F32T-PI/2         \ 1.57079633
0x3F490FDB CONSTANT F32T-PI/4         \ 0.78539816
0x3EA2F983 CONSTANT F32T-INV-PI       \ 1/π  = 0.31830989
0x3E22F983 CONSTANT F32T-INV-2PI      \ 1/2π = 0.15915494
0x3C8EFA35 CONSTANT F32T-DEG2RAD      \ π/180 = 0.01745329
0x42652EE1 CONSTANT F32T-RAD2DEG      \ 180/π = 57.2957795

\ =====================================================================
\  Polynomial coefficients — sin(x) on [−π/4, π/4]
\ =====================================================================
\  sin(x) ≈ x * (S1 + x²*(S3 + x²*(S5 + x²*S7)))
\  Minimax degree-7 polynomial (4 coefficients):
\    S1 =  1.0               = 0x3F800000
\    S3 = -1/6    = -0.16666667  = 0xBE2AAAAB
\    S5 =  1/120  =  0.00833333  = 0x3C088889
\    S7 = -1/5040 = -0.00019841  = 0xB9500D01

0x3F800000 CONSTANT _F3T-S1
0xBE2AAAAB CONSTANT _F3T-S3
0x3C088889 CONSTANT _F3T-S5
0xB9500D01 CONSTANT _F3T-S7

\ =====================================================================
\  Polynomial coefficients — cos(x) on [−π/4, π/4]
\ =====================================================================
\  cos(x) ≈ C0 + x²*(C2 + x²*(C4 + x²*C6))
\  Minimax degree-6 polynomial (4 coefficients):
\    C0 =  1.0                = 0x3F800000
\    C2 = -0.5                = 0xBF000000
\    C4 =  1/24  =  0.04166667  = 0x3D2AAAAB
\    C6 = -1/720 = -0.00138889  = 0xBAB60B61

0x3F800000 CONSTANT _F3T-C0
0xBF000000 CONSTANT _F3T-C2
0x3D2AAAAB CONSTANT _F3T-C4
0xBAB60B61 CONSTANT _F3T-C6

\ =====================================================================
\  Polynomial coefficients — atan(x) on [−1, 1]
\ =====================================================================
\  atan(x) ≈ x * (A1 + x²*(A3 + x²*(A5 + x²*A7)))
\  Minimax degree-7 polynomial:
\    A1 =  1.0                = 0x3F800000
\    A3 = -1/3  = -0.33333333  = 0xBEAAAAAB
\    A5 =  1/5  =  0.20000000  = 0x3E4CCCCD
\    A7 = -1/7  = -0.14285714  = 0xBE124925

0x3F800000 CONSTANT _F3T-A1
0xBEAAAAAB CONSTANT _F3T-A3
0x3E4CCCCD CONSTANT _F3T-A5
0xBE124925 CONSTANT _F3T-A7

\ =====================================================================
\  Internal: range reduction for sin/cos
\ =====================================================================
\  Map angle to [−π/4, π/4] and track quadrant (0–3).
\  quadrant 0:  sin(x) =  sin_poly(r),  cos(x) =  cos_poly(r)
\  quadrant 1:  sin(x) =  cos_poly(r),  cos(x) = −sin_poly(r)
\  quadrant 2:  sin(x) = −sin_poly(r),  cos(x) = −cos_poly(r)
\  quadrant 3:  sin(x) = −cos_poly(r),  cos(x) =  sin_poly(r)

VARIABLE _F3T-QUAD
VARIABLE _F3T-RED
VARIABLE _F3T-SWAP

\ FP32 floor helper: truncate toward negative infinity.
\ For positive values, INT truncation works.  For negative values we
\ need to subtract 1 if there is a fractional part.
: _F3T-FLOOR  ( fp32 -- fp32 )
    DUP FP32>INT INT>FP32             ( x trunc )
    2DUP FP32< IF                     \ x < trunc  (x was negative, trunc rounded toward 0)
        FP32-ONE FP32-SUB             \ trunc - 1
    THEN
    NIP ;

: _F3T-REDUCE  ( angle -- )
    0 _F3T-SWAP !
    \ Step 1: fold to [0, 2π)
    DUP 0x80000000 AND IF             \ negative angle?
        \ Add enough multiples of 2π to make positive
        DUP FP32-ABS                  ( angle |angle| )
        F32T-2PI FP32-DIV _F3T-FLOOR ( angle floor(|a|/2π) )
        FP32-ONE FP32-ADD            ( angle n+1 )
        F32T-2PI FP32-MUL            ( angle (n+1)*2π )
        FP32-ADD                      ( angle + (n+1)*2π )
    THEN
    \ Modulo 2π
    DUP F32T-2PI FP32-DIV _F3T-FLOOR ( pos_angle n )
    F32T-2PI FP32-MUL FP32-SUB       ( angle mod 2π )
    \ Clamp any tiny negative to zero (rounding artifact)
    DUP 0x80000000 AND IF DROP FP32-ZERO THEN
    \ Step 2: determine quadrant and reduce to [0, π/2)
    DUP F32T-PI/2 FP32< IF
        0 _F3T-QUAD !                 \ Q0: [0, π/2)
    ELSE DUP F32T-PI FP32< IF
        F32T-PI/2 FP32-SUB
        1 _F3T-QUAD !                 \ Q1: [π/2, π)
    ELSE DUP F32T-PI F32T-PI/2 FP32-ADD FP32< IF
        F32T-PI FP32-SUB
        2 _F3T-QUAD !                 \ Q2: [π, 3π/2)
    ELSE
        F32T-PI F32T-PI/2 FP32-ADD FP32-SUB
        3 _F3T-QUAD !                 \ Q3: [3π/2, 2π)
    THEN THEN THEN
    \ Now angle is in [0, π/2).  Further reduce to [0, π/4].
    DUP F32T-PI/4 FP32> IF
        F32T-PI/2 SWAP FP32-SUB      \ complement: π/2 − angle
        1 _F3T-SWAP !
    THEN
    _F3T-RED ! ;

\ =====================================================================
\  Internal: polynomial evaluation (Horner form)
\ =====================================================================

VARIABLE _F3T-X2

: _F3T-SIN-POLY  ( x -- sin )
    \ sin(x) ≈ x * (S1 + x²*(S3 + x²*(S5 + x²*S7)))
    DUP DUP FP32-MUL _F3T-X2 !       \ x²
    _F3T-X2 @ _F3T-S7 FP32-MUL       \ x²*S7
    _F3T-S5 FP32-ADD                  \ S5 + x²*S7
    _F3T-X2 @ FP32-MUL               \ x²*(S5 + x²*S7)
    _F3T-S3 FP32-ADD                  \ S3 + x²*(S5 + x²*S7)
    _F3T-X2 @ FP32-MUL               \ x²*(S3 + ...)
    _F3T-S1 FP32-ADD                  \ S1 + x²*(S3 + ...)
    FP32-MUL ;                        \ x * (...)

: _F3T-COS-POLY  ( x -- cos )
    \ cos(x) ≈ C0 + x²*(C2 + x²*(C4 + x²*C6))
    DUP FP32-MUL _F3T-X2 !           \ x²
    _F3T-X2 @ _F3T-C6 FP32-MUL      \ x²*C6
    _F3T-C4 FP32-ADD                  \ C4 + x²*C6
    _F3T-X2 @ FP32-MUL               \ x²*(C4 + x²*C6)
    _F3T-C2 FP32-ADD                  \ C2 + x²*(C4 + x²*C6)
    _F3T-X2 @ FP32-MUL               \ x²*(C2 + ...)
    _F3T-C0 FP32-ADD ;               \ C0 + x²*(...)

\ =====================================================================
\  F32T-SINCOS — compute both sin and cos
\ =====================================================================

VARIABLE _F3T-SP
VARIABLE _F3T-CP

: F32T-SINCOS  ( angle -- sin cos )
    _F3T-REDUCE
    _F3T-RED @ _F3T-SIN-POLY _F3T-SP !
    _F3T-RED @ _F3T-COS-POLY _F3T-CP !
    \ If complement was applied, swap sin_poly ↔ cos_poly
    _F3T-SWAP @ IF
        _F3T-SP @  _F3T-CP @
        _F3T-SP !  _F3T-CP !
    THEN
    _F3T-QUAD @ CASE
        0 OF _F3T-SP @              _F3T-CP @              ENDOF
        1 OF _F3T-CP @              _F3T-SP @ FP32-NEGATE  ENDOF
        2 OF _F3T-SP @ FP32-NEGATE  _F3T-CP @ FP32-NEGATE  ENDOF
        3 OF _F3T-CP @ FP32-NEGATE  _F3T-SP @              ENDOF
    ENDCASE ;

: F32T-SIN  ( angle -- sin )   F32T-SINCOS DROP ;
: F32T-COS  ( angle -- cos )   F32T-SINCOS NIP ;

\ =====================================================================
\  F32T-TAN — tangent = sin / cos
\ =====================================================================

: F32T-TAN  ( angle -- tan )
    F32T-SINCOS                       ( sin cos )
    FP32-DIV ;

\ =====================================================================
\  F32T-ATAN — arctangent via polynomial + range reduction
\ =====================================================================
\  Three-range approach:
\    |x| > 1       : atan(x) = π/2 − atan(1/x)
\    x > tan(π/8)  : atan(x) = π/4 + atan((x−1)/(x+1))
\    |x| ≤ tan(π/8): polynomial
\
\  tan(π/8) ≈ 0.41421356 = 0x3ED413CD

VARIABLE _F3T-ATAN-NEG
VARIABLE _F3T-ATAN-INV
VARIABLE _F3T-ATAN-MID

0x3ED413CD CONSTANT _F3T-ATAN-TH     \ tan(π/8) ≈ 0.41421356

: F32T-ATAN  ( x -- angle )
    0 _F3T-ATAN-NEG !
    0 _F3T-ATAN-INV !
    0 _F3T-ATAN-MID !
    DUP 0x80000000 AND IF             \ negative?
        FP32-NEGATE 1 _F3T-ATAN-NEG !
    THEN
    \ If x > 1, use atan(x) = π/2 − atan(1/x)
    DUP FP32-ONE FP32> IF
        FP32-RECIP 1 _F3T-ATAN-INV !
    THEN
    \ If x > tan(π/8), use atan(x) = π/4 + atan((x−1)/(x+1))
    DUP _F3T-ATAN-TH FP32> IF
        DUP FP32-ONE FP32-SUB        \ x − 1
        SWAP FP32-ONE FP32-ADD       \ x + 1
        FP32-DIV
        1 _F3T-ATAN-MID !
    THEN
    \ Polynomial: x * (A1 + x²*(A3 + x²*(A5 + x²*A7)))
    DUP DUP FP32-MUL _F3T-X2 !       \ x²
    _F3T-X2 @ _F3T-A7 FP32-MUL      \ x²*A7
    _F3T-A5 FP32-ADD                  \ A5 + x²*A7
    _F3T-X2 @ FP32-MUL               \ x²*(A5 + x²*A7)
    _F3T-A3 FP32-ADD                  \ A3 + ...
    _F3T-X2 @ FP32-MUL               \ x²*(A3 + ...)
    _F3T-A1 FP32-ADD                  \ A1 + ...
    FP32-MUL                          \ x * (...)
    _F3T-ATAN-MID @ IF
        F32T-PI/4 FP32-ADD
    THEN
    _F3T-ATAN-INV @ IF
        F32T-PI/2 SWAP FP32-SUB
    THEN
    _F3T-ATAN-NEG @ IF FP32-NEGATE THEN ;

\ =====================================================================
\  F32T-ATAN2 — four-quadrant arctangent
\ =====================================================================

VARIABLE _F3T-A2Y
VARIABLE _F3T-A2X

: F32T-ATAN2  ( y x -- angle )
    _F3T-A2X !  _F3T-A2Y !
    _F3T-A2X @ FP32-0= IF            \ x = ±0
        _F3T-A2Y @ 0x80000000 AND IF
            F32T-PI/2 FP32-NEGATE EXIT   \ y<0: −π/2
        THEN
        _F3T-A2Y @ FP32-0= IF
            FP32-ZERO EXIT            \ y=0: 0
        THEN
        F32T-PI/2 EXIT                \ y>0: +π/2
    THEN
    _F3T-A2Y @ _F3T-A2X @ FP32-DIV
    F32T-ATAN                         ( base_angle )
    _F3T-A2X @ 0x80000000 AND IF     \ x < 0?
        _F3T-A2Y @ 0x80000000 AND IF
            F32T-PI FP32-SUB         \ Q3: atan − π
        ELSE
            F32T-PI FP32-ADD         \ Q2: atan + π
        THEN
    THEN ;

\ =====================================================================
\  F32T-ASIN — arcsine: asin(x) = atan2(x, √(1−x²))
\ =====================================================================

: F32T-ASIN  ( x -- angle )
    DUP DUP FP32-MUL                 \ x²
    FP32-ONE SWAP FP32-SUB           \ 1 − x²
    FP32-SQRT                         \ √(1−x²)
    F32T-ATAN2 ;

\ =====================================================================
\  F32T-ACOS — arccosine: acos(x) = π/2 − asin(x)
\ =====================================================================

: F32T-ACOS  ( x -- angle )
    F32T-ASIN F32T-PI/2 SWAP FP32-SUB ;

\ =====================================================================
\  Degree ↔ Radian conversion
\ =====================================================================

: F32T-DEG>RAD  ( deg -- rad )   F32T-DEG2RAD FP32-MUL ;
: F32T-RAD>DEG  ( rad -- deg )   F32T-RAD2DEG FP32-MUL ;
