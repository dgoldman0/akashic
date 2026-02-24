\ trig.f — FP16 trigonometric functions
\
\ Polynomial approximations optimised for FP16's 10-bit mantissa.
\ Range reduction maps any angle to [−π/4, π/4], then a short
\ Taylor/minimax polynomial gives full-precision results.
\
\ All angles are in FP16 radians unless noted otherwise.
\ Conversion helpers DEG>RAD / RAD>DEG are provided.
\
\ Prefix: TRIG-  (public API)
\         _TR-   (internal helpers)
\
\ Load with:   REQUIRE trig.f
\
\ === Public API ===
\   TRIG-SIN       ( angle -- sin )       sine
\   TRIG-COS       ( angle -- cos )       cosine
\   TRIG-SINCOS    ( angle -- sin cos )   both at once
\   TRIG-TAN       ( angle -- tan )       tangent
\   TRIG-ATAN      ( x -- angle )         arctangent
\   TRIG-ATAN2     ( y x -- angle )       four-quadrant arctangent
\   TRIG-ASIN      ( x -- angle )         arcsine
\   TRIG-ACOS      ( x -- angle )         arccosine
\   TRIG-DEG>RAD   ( deg -- rad )         degree → radian
\   TRIG-RAD>DEG   ( rad -- deg )         radian → degree

REQUIRE fp16-ext.f

PROVIDED akashic-trig

\ =====================================================================
\  Constants — well-known FP16 bit patterns
\ =====================================================================
\  Verified via Python: struct-based float→FP16 conversion.

0x4248 CONSTANT TRIG-PI              \ 3.14159
0x4648 CONSTANT TRIG-2PI             \ 6.28318
0x3E48 CONSTANT TRIG-PI/2            \ 1.57080
0x3A48 CONSTANT TRIG-PI/4            \ 0.78540
0x3518 CONSTANT TRIG-INV-PI          \ 1/π  = 0.31831
0x3118 CONSTANT TRIG-INV-2PI         \ 1/2π = 0.15915
0x2478 CONSTANT TRIG-DEG2RAD         \ π/180 = 0.01745
0x5329 CONSTANT TRIG-RAD2DEG         \ 180/π = 57.2958

\ Polynomial coefficients (stored as FP16 bit patterns)
\ sin(x) ≈ x − x³/6 + x⁵/120   on [−π/4, π/4]
0x3C00 CONSTANT _TR-SIN-C1           \ +1.0
0xB155 CONSTANT _TR-SIN-C3           \ −1/6  = −0.16667
0x2044 CONSTANT _TR-SIN-C5           \ +1/120 = 0.00833

\ cos(x) ≈ 1 − x²/2 + x⁴/24   on [−π/4, π/4]
0x3C00 CONSTANT _TR-COS-D0           \ +1.0
0xB800 CONSTANT _TR-COS-D2           \ −0.5
0x2955 CONSTANT _TR-COS-D4           \ +1/24 = 0.04167

\ atan(x) ≈ x − x³/3 + x⁵/5   on [−1, 1]
0x3C00 CONSTANT _TR-AT-A1            \ +1.0
0xB555 CONSTANT _TR-AT-A3            \ −1/3  = −0.33333
0x3266 CONSTANT _TR-AT-A5            \ +1/5  = 0.20000

\ =====================================================================
\  Internal: range reduction for sin/cos
\ =====================================================================
\  Map angle to [−π/4, π/4] and track quadrant (0–3).
\  quadrant 0:  sin(x) =  sin_poly(r),  cos(x) =  cos_poly(r)
\  quadrant 1:  sin(x) =  cos_poly(r),  cos(x) = −sin_poly(r)
\  quadrant 2:  sin(x) = −sin_poly(r),  cos(x) = −cos_poly(r)
\  quadrant 3:  sin(x) = −cos_poly(r),  cos(x) =  sin_poly(r)

VARIABLE _TR-QUAD
VARIABLE _TR-RED                     \ reduced angle

: _TR-REDUCE  ( angle -- )
    \ Step 1: fold to [0, 2π)
    DUP FP16-SIGN IF                  \ negative angle?
        FP16-NEG                      \ work with |angle|
        TRIG-2PI FP16-DIV FP16-FLOOR ( n_periods )
        TRIG-2PI FP16-MUL            ( n*2π )
        SWAP FP16-ADD TRIG-2PI FP16-ADD  \ angle + ceil*2π
        SWAP DROP
    ELSE
        DUP TRIG-2PI FP16-GE IF      \ >= 2π?
            DUP TRIG-2PI FP16-DIV FP16-FLOOR
            TRIG-2PI FP16-MUL FP16-SUB
        THEN
    THEN
    \ Now angle is in [0, 2π) approximately.
    \ Step 2: determine quadrant and reduce to [0, π/2)
    DUP TRIG-PI/2 FP16-LT IF
        0 _TR-QUAD !                  \ Q0: [0, π/2)
    ELSE DUP TRIG-PI FP16-LT IF
        TRIG-PI/2 FP16-SUB
        1 _TR-QUAD !                  \ Q1: [π/2, π)
    ELSE DUP TRIG-PI TRIG-PI/2 FP16-ADD FP16-LT IF
        TRIG-PI FP16-SUB
        2 _TR-QUAD !                  \ Q2: [π, 3π/2)
    ELSE
        TRIG-PI TRIG-PI/2 FP16-ADD FP16-SUB
        3 _TR-QUAD !                  \ Q3: [3π/2, 2π)
    THEN THEN THEN
    \ Now angle is in [0, π/2). Further reduce to [0, π/4].
    DUP TRIG-PI/4 FP16-GT IF
        TRIG-PI/2 SWAP FP16-SUB      \ complement: π/2 − angle
        _TR-QUAD @ 1+ 3 AND _TR-QUAD !  \ shift quadrant
    THEN
    _TR-RED ! ;

\ =====================================================================
\  Internal: polynomial evaluation (Horner form)
\ =====================================================================

VARIABLE _TR-X2

: _TR-SIN-POLY  ( x -- sin )
    \ sin(x) ≈ x * (1 + x²*(−1/6 + x²/120))
    DUP DUP FP16-MUL _TR-X2 !        \ x² stored
    _TR-X2 @ _TR-SIN-C5 FP16-MUL     \ x²/120
    _TR-SIN-C3 FP16-ADD              \ −1/6 + x²/120
    _TR-X2 @ FP16-MUL                \ x²*(−1/6 + x²/120)
    _TR-SIN-C1 FP16-ADD              \ 1 + ...
    FP16-MUL ;                        \ x * (...)

: _TR-COS-POLY  ( x -- cos )
    \ cos(x) ≈ 1 + x²*(−0.5 + x²/24)
    DUP FP16-MUL _TR-X2 !            \ x²
    _TR-X2 @ _TR-COS-D4 FP16-MUL    \ x²/24
    _TR-COS-D2 FP16-ADD              \ −0.5 + x²/24
    _TR-X2 @ FP16-MUL                \ x²*(−0.5 + x²/24)
    _TR-COS-D0 FP16-ADD ;            \ 1 + ...

\ =====================================================================
\  TRIG-SIN — sine
\ =====================================================================
VARIABLE _TR-SP
VARIABLE _TR-CP

: TRIG-SINCOS  ( angle -- sin cos )
    _TR-REDUCE
    _TR-RED @ _TR-SIN-POLY _TR-SP !
    _TR-RED @ _TR-COS-POLY _TR-CP !
    _TR-QUAD @ CASE
        0 OF _TR-SP @          _TR-CP @          ENDOF
        1 OF _TR-CP @          _TR-SP @ FP16-NEG ENDOF
        2 OF _TR-SP @ FP16-NEG _TR-CP @ FP16-NEG ENDOF
        3 OF _TR-CP @ FP16-NEG _TR-SP @          ENDOF
    ENDCASE ;

: TRIG-SIN  ( angle -- sin )   TRIG-SINCOS DROP ;
: TRIG-COS  ( angle -- cos )   TRIG-SINCOS NIP ;

\ =====================================================================
\  TRIG-TAN — tangent = sin/cos
\ =====================================================================

: TRIG-TAN  ( angle -- tan )
    TRIG-SINCOS                       ( sin cos )
    FP16-DIV ;

\ =====================================================================
\  TRIG-ATAN — arctangent via polynomial on [−1, 1]
\ =====================================================================
\  For |x| > 1: atan(x) = π/2 − atan(1/x)
\  Polynomial: atan(x) ≈ x*(1 − x²/3 + x⁴/5), Horner form

VARIABLE _TR-ATAN-NEG                \ sign flag
VARIABLE _TR-ATAN-INV                \ reciprocal flag

: TRIG-ATAN  ( x -- angle )
    0 _TR-ATAN-NEG !
    0 _TR-ATAN-INV !
    DUP FP16-SIGN IF
        FP16-NEG 1 _TR-ATAN-NEG !
    THEN
    \ Now x >= 0.  If x > 1, use atan(x) = π/2 − atan(1/x)
    DUP FP16-POS-ONE FP16-GT IF
        FP16-RECIP 1 _TR-ATAN-INV !
    THEN
    \ Polynomial: x*(a1 + x²*(a3 + x²*a5))  Horner
    DUP DUP FP16-MUL _TR-X2 !        \ x²
    _TR-X2 @ _TR-AT-A5 FP16-MUL      \ x²*a5
    _TR-AT-A3 FP16-ADD               \ a3 + x²*a5
    _TR-X2 @ FP16-MUL                \ x²*(a3 + x²*a5)
    _TR-AT-A1 FP16-ADD               \ a1 + x²*(...)
    FP16-MUL                          \ x * (...)
    _TR-ATAN-INV @ IF
        TRIG-PI/2 SWAP FP16-SUB
    THEN
    _TR-ATAN-NEG @ IF FP16-NEG THEN ;

\ =====================================================================
\  TRIG-ATAN2 — four-quadrant arctangent
\ =====================================================================
\  atan2(y, x) handles all four quadrants and special cases.

VARIABLE _TR-A2Y
VARIABLE _TR-A2X

: TRIG-ATAN2  ( y x -- angle )
    _TR-A2X !  _TR-A2Y !
    _TR-A2X @ 0x7FFF AND 0= IF       \ x = ±0
        _TR-A2Y @ FP16-SIGN IF
            TRIG-PI/2 FP16-NEG EXIT  \ y<0: −π/2
        THEN
        _TR-A2Y @ 0x7FFF AND 0= IF
            FP16-POS-ZERO EXIT       \ y=0: 0
        THEN
        TRIG-PI/2 EXIT               \ y>0: +π/2
    THEN
    _TR-A2Y @ _TR-A2X @ FP16-DIV
    TRIG-ATAN                         ( base_angle )
    _TR-A2X @ FP16-SIGN IF           \ x < 0?
        _TR-A2Y @ FP16-SIGN IF
            TRIG-PI FP16-SUB         \ Q3: atan − π
        ELSE
            TRIG-PI FP16-ADD         \ Q2: atan + π
        THEN
    THEN ;

\ =====================================================================
\  TRIG-ASIN — arcsine: asin(x) = atan2(x, √(1−x²))
\ =====================================================================

: TRIG-ASIN  ( x -- angle )
    DUP DUP FP16-MUL                 \ x²
    FP16-POS-ONE SWAP FP16-SUB       \ 1 − x²
    FP16-SQRT                         \ √(1−x²)
    TRIG-ATAN2 ;

\ =====================================================================
\  TRIG-ACOS — arccosine: acos(x) = π/2 − asin(x)
\ =====================================================================

: TRIG-ACOS  ( x -- angle )
    TRIG-ASIN TRIG-PI/2 SWAP FP16-SUB ;

\ =====================================================================
\  Degree ↔ Radian conversion
\ =====================================================================

: TRIG-DEG>RAD  ( deg -- rad )   TRIG-DEG2RAD FP16-MUL ;
: TRIG-RAD>DEG  ( rad -- deg )   TRIG-RAD2DEG FP16-MUL ;
