\ vec2.f — 2D vector operations (FP16)
\
\ Vectors are two FP16 values on the stack: ( x y ).
\ All operations use the tile engine via fp16.f for arithmetic.
\
\ Prefix: V2-   (public API)
\         _V2-  (internal helpers)
\
\ Load with:   REQUIRE vec2.f
\   (auto-loads fp16.f, fp16-ext.f, trig.f via REQUIRE)
\
\ === Public API ===
\   V2-ADD     ( ax ay bx by -- rx ry )   component-wise add
\   V2-SUB     ( ax ay bx by -- rx ry )   component-wise subtract
\   V2-SCALE   ( x y s -- rx ry )         scalar multiply
\   V2-DOT     ( ax ay bx by -- dot )     dot product
\   V2-CROSS   ( ax ay bx by -- cross )   2D cross product (scalar)
\   V2-LENSQ   ( x y -- len² )            squared length (no sqrt)
\   V2-LEN     ( x y -- len )             length √(x²+y²)
\   V2-NORM    ( x y -- nx ny )           normalize to unit length
\   V2-DIST    ( ax ay bx by -- d )       distance between two points
\   V2-LERP    ( ax ay bx by t -- rx ry ) linear interpolation
\   V2-PERP    ( x y -- -y x )            perpendicular (90° CCW)
\   V2-REFLECT ( vx vy nx ny -- rx ry )   reflect v across normal n
\   V2-ROTATE  ( x y angle -- rx ry )     rotate by angle (radians)
\   V2-NEG     ( x y -- -x -y )           negate
\   V2-MIN     ( ax ay bx by -- rx ry )   component-wise min
\   V2-MAX     ( ax ay bx by -- rx ry )   component-wise max
\   V2-EQ      ( ax ay bx by -- flag )    component-wise equality
\   V2-ZERO    ( -- x y )                 push (0, 0)
\   V2-ONE     ( -- x y )                 push (1, 1)

REQUIRE fp16-ext.f
REQUIRE trig.f

PROVIDED akashic-vec2

\ =====================================================================
\  Constants
\ =====================================================================

: V2-ZERO  ( -- x y )  FP16-POS-ZERO FP16-POS-ZERO ;
: V2-ONE   ( -- x y )  FP16-POS-ONE  FP16-POS-ONE ;

\ =====================================================================
\  Internal scratch variables
\ =====================================================================
\  Following the project convention: all intermediates use VARIABLEs,
\  no locals, no return-stack tricks beyond simple >R / R>.

VARIABLE _V2-A
VARIABLE _V2-B
VARIABLE _V2-C
VARIABLE _V2-D

\ =====================================================================
\  Basic arithmetic
\ =====================================================================

\ V2-ADD  ( ax ay bx by -- rx ry )
\   rx = ax + bx,  ry = ay + by
: V2-ADD  ( ax ay bx by -- rx ry )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-C @ FP16-ADD          ( rx )
    _V2-B @ _V2-D @ FP16-ADD          ( rx ry )
    ;

\ V2-SUB  ( ax ay bx by -- rx ry )
\   rx = ax - bx,  ry = ay - by
: V2-SUB  ( ax ay bx by -- rx ry )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-C @ FP16-SUB          ( rx )
    _V2-B @ _V2-D @ FP16-SUB          ( rx ry )
    ;

\ V2-SCALE  ( x y s -- rx ry )
\   Multiply both components by scalar s.
: V2-SCALE  ( x y s -- rx ry )
    _V2-C !                            \ s→C
    _V2-B !  _V2-A !                  \ y→B, x→A
    _V2-A @ _V2-C @ FP16-MUL          ( rx )
    _V2-B @ _V2-C @ FP16-MUL          ( rx ry )
    ;

\ V2-NEG  ( x y -- -x -y )
: V2-NEG  ( x y -- -x -y )
    FP16-NEG SWAP FP16-NEG SWAP ;

\ =====================================================================
\  Products
\ =====================================================================

\ V2-DOT  ( ax ay bx by -- dot )
\   dot = ax*bx + ay*by
: V2-DOT  ( ax ay bx by -- dot )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-C @ FP16-MUL          ( ax*bx )
    _V2-B @ _V2-D @ FP16-MUL          ( ax*bx ay*by )
    FP16-ADD ;                         ( dot )

\ V2-CROSS  ( ax ay bx by -- cross )
\   cross = ax*by - ay*bx  (z-component of 3D cross product)
: V2-CROSS  ( ax ay bx by -- cross )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-D @ FP16-MUL          ( ax*by )
    _V2-B @ _V2-C @ FP16-MUL          ( ax*by ay*bx )
    FP16-SUB ;                         ( cross )

\ =====================================================================
\  Length & distance
\ =====================================================================

\ V2-LENSQ  ( x y -- len² )
\   len² = x² + y²
: V2-LENSQ  ( x y -- len² )
    DUP FP16-MUL                       ( x y² )
    SWAP DUP FP16-MUL                  ( y² x² )
    FP16-ADD ;                         ( x²+y² )

\ V2-LEN  ( x y -- len )
\   len = √(x²+y²)
: V2-LEN  ( x y -- len )
    V2-LENSQ FP16-SQRT ;

\ V2-NORM  ( x y -- nx ny )
\   Normalize to unit length.  Zero vector → returns (0, 0).
: V2-NORM  ( x y -- nx ny )
    2DUP V2-LEN                        ( x y len )
    DUP FP16-POS-ZERO FP16-EQ IF
        DROP EXIT                      \ zero vector → unchanged
    THEN
    FP16-RECIP                         ( x y 1/len )
    V2-SCALE ;                         ( nx ny )

\ V2-DIST  ( ax ay bx by -- d )
\   Euclidean distance = |a - b|
: V2-DIST  ( ax ay bx by -- d )
    V2-SUB V2-LEN ;

\ =====================================================================
\  Interpolation
\ =====================================================================

\ V2-LERP  ( ax ay bx by t -- rx ry )
\   Per-component lerp: r = a + t*(b - a)
VARIABLE _V2L-T

: V2-LERP  ( ax ay bx by t -- rx ry )
    _V2L-T !                           ( ax ay bx by )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-C @ _V2L-T @ FP16-LERP  ( rx )
    _V2-B @ _V2-D @ _V2L-T @ FP16-LERP  ( rx ry )
    ;

\ =====================================================================
\  Geometric operations
\ =====================================================================

\ V2-PERP  ( x y -- -y x )
\   90° counter-clockwise perpendicular.
: V2-PERP  ( x y -- -y x )
    FP16-NEG                           ( x -y )
    SWAP ;                             ( -y x )

\ V2-REFLECT  ( vx vy nx ny -- rx ry )
\   r = v - 2*(v·n)*n
\   Assumes n is unit length.
VARIABLE _V2R-2D

: V2-REFLECT  ( vx vy nx ny -- rx ry )
    _V2-D !  _V2-C !                  \ ny→D, nx→C
    _V2-B !  _V2-A !                  \ vy→B, vx→A
    \ dot = vx*nx + vy*ny
    _V2-A @ _V2-B @ _V2-C @ _V2-D @
    V2-DOT                             ( dot )
    \ 2*dot
    0x4000 FP16-MUL _V2R-2D !         \ save 2*dot
    \ rx = vx - 2*dot*nx
    _V2-A @ _V2R-2D @ _V2-C @ FP16-MUL FP16-SUB  ( rx )
    \ ry = vy - 2*dot*ny
    _V2-B @ _V2R-2D @ _V2-D @ FP16-MUL FP16-SUB  ( rx ry )
    ;

\ V2-ROTATE  ( x y angle -- rx ry )
\   Rotate vector by angle (FP16 radians).
\   x' = x*cos(a) - y*sin(a)
\   y' = x*sin(a) + y*cos(a)

VARIABLE _VR-SIN
VARIABLE _VR-COS

: V2-ROTATE  ( x y angle -- rx ry )
    TRIG-SINCOS                        ( x y sin cos )
    _VR-COS !  _VR-SIN !              ( x y )
    _V2-B !  _V2-A !                  ( )
    \ rx = x*cos - y*sin
    _V2-A @ _VR-COS @ FP16-MUL        ( x*cos )
    _V2-B @ _VR-SIN @ FP16-MUL        ( x*cos y*sin )
    FP16-SUB                           ( rx )
    \ ry = x*sin + y*cos
    _V2-A @ _VR-SIN @ FP16-MUL        ( rx x*sin )
    _V2-B @ _VR-COS @ FP16-MUL        ( rx x*sin y*cos )
    FP16-ADD                           ( rx ry )
    ;

\ =====================================================================
\  Component-wise min / max
\ =====================================================================

\ V2-MIN  ( ax ay bx by -- rx ry )
: V2-MIN  ( ax ay bx by -- rx ry )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-C @ FP16-MIN          ( rx )
    _V2-B @ _V2-D @ FP16-MIN          ( rx ry )
    ;

\ V2-MAX  ( ax ay bx by -- rx ry )
: V2-MAX  ( ax ay bx by -- rx ry )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-C @ FP16-MAX          ( rx )
    _V2-B @ _V2-D @ FP16-MAX          ( rx ry )
    ;

\ =====================================================================
\  Equality
\ =====================================================================

\ V2-EQ  ( ax ay bx by -- flag )
\   True if both components are equal.
: V2-EQ  ( ax ay bx by -- flag )
    _V2-D !  _V2-C !                  \ by→D, bx→C
    _V2-B !  _V2-A !                  \ ay→B, ax→A
    _V2-A @ _V2-C @ FP16-EQ
    _V2-B @ _V2-D @ FP16-EQ
    AND ;                              ( flag )
