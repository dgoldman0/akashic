\ bezier.f — Bézier curve primitives in FP16
\
\ Quadratic and cubic Bézier evaluation, subdivision, flatness
\ testing, and adaptive flattening.  All coordinates are FP16
\ (x, y) pairs on the Forth stack.
\
\ Uses fp16.f and fp16-ext.f for hardware-accelerated FP16 math.
\
\ Prefix: BZ-  (public API)
\         _BZ- (internal helpers)
\
\ Load with:   REQUIRE bezier.f
\
\ === Public API ===
\  Evaluation:
\   BZ-QUAD-EVAL   ( x0 y0 x1 y1 x2 y2 t -- rx ry )
\   BZ-CUBIC-EVAL  ( x0 y0 x1 y1 x2 y2 x3 y3 t -- rx ry )
\
\  Flatness:
\   BZ-QUAD-FLAT?  ( x0 y0 x1 y1 x2 y2 tol -- flag )
\   BZ-CUBIC-FLAT? ( x0 y0 x1 y1 x2 y2 x3 y3 tol -- flag )
\
\  Flattening (recursive subdivision -> line segment callback):
\   BZ-QUAD-FLATTEN  ( x0 y0 x1 y1 x2 y2 tol xt -- )
\   BZ-CUBIC-FLATTEN ( x0 y0 x1 y1 x2 y2 x3 y3 tol xt -- )
\     Callback xt: ( x0 y0 x1 y1 -- ) called for each line segment.
\
\ Stack depth is managed via an explicit work stack in memory
\ to avoid Forth return stack overflow during deep subdivision.
\ NOTE: The callback must NOT call BZ-*-FLATTEN recursively.

REQUIRE fp16-ext.f

PROVIDED akashic-bezier

\ =====================================================================
\  Constants
\ =====================================================================
0x3800 CONSTANT _BZ-HALF            \ FP16  0.5
0x3555 CONSTANT _BZ-THIRD           \ FP16 ~1/3
0x3955 CONSTANT _BZ-TWO-THIRDS      \ FP16 ~2/3

\ =====================================================================
\  Shared point variables P0-P3
\ =====================================================================
VARIABLE _BZ-AX   VARIABLE _BZ-AY
VARIABLE _BZ-BX   VARIABLE _BZ-BY
VARIABLE _BZ-CX   VARIABLE _BZ-CY
VARIABLE _BZ-DX   VARIABLE _BZ-DY
VARIABLE _BZ-T                      \ parameter t for EVAL words

: _BZ!0 ( x y -- ) _BZ-AY ! _BZ-AX ! ;
: _BZ!1 ( x y -- ) _BZ-BY ! _BZ-BX ! ;
: _BZ!2 ( x y -- ) _BZ-CY ! _BZ-CX ! ;
: _BZ!3 ( x y -- ) _BZ-DY ! _BZ-DX ! ;
: _BZ@0 ( -- x y ) _BZ-AX @ _BZ-AY @ ;
: _BZ@1 ( -- x y ) _BZ-BX @ _BZ-BY @ ;
: _BZ@2 ( -- x y ) _BZ-CX @ _BZ-CY @ ;
: _BZ@3 ( -- x y ) _BZ-DX @ _BZ-DY @ ;

\ =====================================================================
\  LERP2D — 2D linear interpolation in FP16
\ =====================================================================
VARIABLE _L2-X0   VARIABLE _L2-Y0
VARIABLE _L2-X1   VARIABLE _L2-Y1
VARIABLE _L2-T

: LERP2D  ( x0 y0 x1 y1 t -- rx ry )
    _L2-T !
    _L2-Y1 !  _L2-X1 !  _L2-Y0 !  _L2-X0 !
    _L2-X0 @  _L2-X1 @  _L2-T @  FP16-LERP
    _L2-Y0 @  _L2-Y1 @  _L2-T @  FP16-LERP ;

: MID2D   ( x0 y0 x1 y1 -- mx my )  _BZ-HALF LERP2D ;

\ =====================================================================
\  BZ-QUAD-EVAL — De Casteljau evaluation of quadratic Bezier
\ =====================================================================
VARIABLE _QE-QX0   VARIABLE _QE-QY0
VARIABLE _QE-QX1   VARIABLE _QE-QY1

: BZ-QUAD-EVAL  ( x0 y0 x1 y1 x2 y2 t -- rx ry )
    _BZ-T !  _BZ!2  _BZ!1  _BZ!0
    _BZ@0 _BZ@1 _BZ-T @ LERP2D  _QE-QY0 !  _QE-QX0 !
    _BZ@1 _BZ@2 _BZ-T @ LERP2D  _QE-QY1 !  _QE-QX1 !
    _QE-QX0 @ _QE-QY0 @  _QE-QX1 @ _QE-QY1 @  _BZ-T @ LERP2D ;

\ =====================================================================
\  BZ-CUBIC-EVAL — De Casteljau evaluation of cubic Bezier
\ =====================================================================
VARIABLE _CE-QX0   VARIABLE _CE-QY0
VARIABLE _CE-QX1   VARIABLE _CE-QY1
VARIABLE _CE-QX2   VARIABLE _CE-QY2
VARIABLE _CE-RX0   VARIABLE _CE-RY0
VARIABLE _CE-RX1   VARIABLE _CE-RY1

: BZ-CUBIC-EVAL  ( x0 y0 x1 y1 x2 y2 x3 y3 t -- rx ry )
    _BZ-T !  _BZ!3  _BZ!2  _BZ!1  _BZ!0
    _BZ@0 _BZ@1 _BZ-T @ LERP2D  _CE-QY0 !  _CE-QX0 !
    _BZ@1 _BZ@2 _BZ-T @ LERP2D  _CE-QY1 !  _CE-QX1 !
    _BZ@2 _BZ@3 _BZ-T @ LERP2D  _CE-QY2 !  _CE-QX2 !
    _CE-QX0 @ _CE-QY0 @  _CE-QX1 @ _CE-QY1 @  _BZ-T @ LERP2D
    _CE-RY0 !  _CE-RX0 !
    _CE-QX1 @ _CE-QY1 @  _CE-QX2 @ _CE-QY2 @  _BZ-T @ LERP2D
    _CE-RY1 !  _CE-RX1 !
    _CE-RX0 @ _CE-RY0 @  _CE-RX1 @ _CE-RY1 @  _BZ-T @ LERP2D ;

\ =====================================================================
\  BZ-QUAD-FLAT? — quadratic flatness test (L-inf norm)
\ =====================================================================
\  Flat if max deviation of P1 from chord midpoint <= tolerance.
VARIABLE _QF-MX   VARIABLE _QF-MY

: BZ-QUAD-FLAT?  ( x0 y0 x1 y1 x2 y2 tol -- flag )
    >R  _BZ!2  _BZ!1  _BZ!0
    _BZ@0 _BZ@2 MID2D  _QF-MY !  _QF-MX !
    _BZ-BX @ _QF-MX @ FP16-SUB FP16-ABS
    _BZ-BY @ _QF-MY @ FP16-SUB FP16-ABS
    FP16-MAX   R> FP16-LE ;

\ =====================================================================
\  BZ-CUBIC-FLAT? — cubic flatness test (L-inf norm)
\ =====================================================================
\  Flat if both P1 and P2 are within tolerance of the chord
\  at t=1/3 and t=2/3 respectively.
VARIABLE _CF-CX   VARIABLE _CF-CY
VARIABLE _CF-D

: BZ-CUBIC-FLAT?  ( x0 y0 x1 y1 x2 y2 x3 y3 tol -- flag )
    >R  _BZ!3  _BZ!2  _BZ!1  _BZ!0
    \ chord1 = lerp(P0, P3, 1/3) — compare to P1
    _BZ@0 _BZ@3 _BZ-THIRD LERP2D  _CF-CY !  _CF-CX !
    _BZ-BX @ _CF-CX @ FP16-SUB FP16-ABS
    _BZ-BY @ _CF-CY @ FP16-SUB FP16-ABS
    FP16-MAX  _CF-D !
    \ chord2 = lerp(P0, P3, 2/3) — compare to P2
    _BZ@0 _BZ@3 _BZ-TWO-THIRDS LERP2D  _CF-CY !  _CF-CX !
    _BZ-CX @ _CF-CX @ FP16-SUB FP16-ABS
    _BZ-CY @ _CF-CY @ FP16-SUB FP16-ABS
    FP16-MAX  _CF-D @ FP16-MAX
    R> FP16-LE ;

\ =====================================================================
\  Work stack for iterative subdivision
\ =====================================================================
\ Max depth ~16 x 8 values = 128 cells.  Allocate 256 for safety.
HERE  256 CELLS ALLOT  CONSTANT _BZ-WSTACK
VARIABLE _BZ-WSP

: _BZ-WS-RESET   ( -- )       _BZ-WSTACK _BZ-WSP ! ;
: _BZ-WS-PUSH    ( val -- )   _BZ-WSP @  !  _BZ-WSP @  CELL+  _BZ-WSP ! ;
: _BZ-WS-POP     ( -- val )   _BZ-WSP @  1 CELLS -  DUP _BZ-WSP !  @ ;
: _BZ-WS-EMPTY?  ( -- flag )  _BZ-WSP @  _BZ-WSTACK  = ;

\ =====================================================================
\  Flatten helpers
\ =====================================================================
VARIABLE _BZ-TOL
VARIABLE _BZ-CB

\ --- Quad split at t=0.5 ---
VARIABLE _QS-MX   VARIABLE _QS-MY     \ mid(P0,P1)
VARIABLE _QS-NX   VARIABLE _QS-NY     \ mid(P1,P2)
VARIABLE _QS-SX   VARIABLE _QS-SY     \ mid(M,N) = on-curve

: _BZ-QUAD-SPLIT-PUSH  ( -- )
    \ Split quad in _BZ P0-P2 at t=0.5, push two halves.
    _BZ@0 _BZ@1 MID2D  _QS-MY !  _QS-MX !
    _BZ@1 _BZ@2 MID2D  _QS-NY !  _QS-NX !
    _QS-MX @ _QS-MY @  _QS-NX @ _QS-NY @  MID2D
    _QS-SY !  _QS-SX !
    \ Push right half (S->N->P2) — deeper, processed second
    _QS-SX @ _BZ-WS-PUSH   _QS-SY @ _BZ-WS-PUSH
    _QS-NX @ _BZ-WS-PUSH   _QS-NY @ _BZ-WS-PUSH
    _BZ-CX @ _BZ-WS-PUSH   _BZ-CY @ _BZ-WS-PUSH
    \ Push left half (P0->M->S) — top, processed first
    _BZ-AX @ _BZ-WS-PUSH   _BZ-AY @ _BZ-WS-PUSH
    _QS-MX @ _BZ-WS-PUSH   _QS-MY @ _BZ-WS-PUSH
    _QS-SX @ _BZ-WS-PUSH   _QS-SY @ _BZ-WS-PUSH ;

\ --- Cubic split at t=0.5 ---
VARIABLE _CS-ABX   VARIABLE _CS-ABY    \ mid(P0,P1)
VARIABLE _CS-BCX   VARIABLE _CS-BCY    \ mid(P1,P2)
VARIABLE _CS-CDX   VARIABLE _CS-CDY    \ mid(P2,P3)
VARIABLE _CS-EX    VARIABLE _CS-EY     \ mid(AB,BC)
VARIABLE _CS-FX    VARIABLE _CS-FY     \ mid(BC,CD)
VARIABLE _CS-GX    VARIABLE _CS-GY     \ mid(E,F) = on-curve

: _BZ-CUBIC-SPLIT-PUSH  ( -- )
    \ Split cubic in _BZ P0-P3 at t=0.5, push two halves.
    _BZ@0 _BZ@1 MID2D  _CS-ABY !  _CS-ABX !
    _BZ@1 _BZ@2 MID2D  _CS-BCY !  _CS-BCX !
    _BZ@2 _BZ@3 MID2D  _CS-CDY !  _CS-CDX !
    _CS-ABX @ _CS-ABY @  _CS-BCX @ _CS-BCY @  MID2D
    _CS-EY !  _CS-EX !
    _CS-BCX @ _CS-BCY @  _CS-CDX @ _CS-CDY @  MID2D
    _CS-FY !  _CS-FX !
    _CS-EX @ _CS-EY @  _CS-FX @ _CS-FY @  MID2D
    _CS-GY !  _CS-GX !
    \ Push right half (G->F->CD->P3)
    _CS-GX  @ _BZ-WS-PUSH   _CS-GY  @ _BZ-WS-PUSH
    _CS-FX  @ _BZ-WS-PUSH   _CS-FY  @ _BZ-WS-PUSH
    _CS-CDX @ _BZ-WS-PUSH   _CS-CDY @ _BZ-WS-PUSH
    _BZ-DX  @ _BZ-WS-PUSH   _BZ-DY  @ _BZ-WS-PUSH
    \ Push left half (P0->AB->E->G)
    _BZ-AX  @ _BZ-WS-PUSH   _BZ-AY  @ _BZ-WS-PUSH
    _CS-ABX @ _BZ-WS-PUSH   _CS-ABY @ _BZ-WS-PUSH
    _CS-EX  @ _BZ-WS-PUSH   _CS-EY  @ _BZ-WS-PUSH
    _CS-GX  @ _BZ-WS-PUSH   _CS-GY  @ _BZ-WS-PUSH ;

\ =====================================================================
\  BZ-QUAD-FLATTEN
\ =====================================================================
: BZ-QUAD-FLATTEN  ( x0 y0 x1 y1 x2 y2 tol xt -- )
    _BZ-CB !  _BZ-TOL !
    _BZ!2  _BZ!1  _BZ!0
    _BZ-WS-RESET
    \ Push initial quad (6 values)
    _BZ-AX @ _BZ-WS-PUSH  _BZ-AY @ _BZ-WS-PUSH
    _BZ-BX @ _BZ-WS-PUSH  _BZ-BY @ _BZ-WS-PUSH
    _BZ-CX @ _BZ-WS-PUSH  _BZ-CY @ _BZ-WS-PUSH
    BEGIN  _BZ-WS-EMPTY? 0=  WHILE
        \ Pop 6 values (reverse push order)
        _BZ-WS-POP _BZ-CY !   _BZ-WS-POP _BZ-CX !
        _BZ-WS-POP _BZ-BY !   _BZ-WS-POP _BZ-BX !
        _BZ-WS-POP _BZ-AY !   _BZ-WS-POP _BZ-AX !
        _BZ@0 _BZ@1 _BZ@2 _BZ-TOL @ BZ-QUAD-FLAT? IF
            _BZ@0 _BZ@2  _BZ-CB @ EXECUTE
        ELSE
            _BZ-QUAD-SPLIT-PUSH
        THEN
    REPEAT ;

\ =====================================================================
\  BZ-CUBIC-FLATTEN
\ =====================================================================
: BZ-CUBIC-FLATTEN  ( x0 y0 x1 y1 x2 y2 x3 y3 tol xt -- )
    _BZ-CB !  _BZ-TOL !
    _BZ!3  _BZ!2  _BZ!1  _BZ!0
    _BZ-WS-RESET
    \ Push initial cubic (8 values)
    _BZ-AX @ _BZ-WS-PUSH  _BZ-AY @ _BZ-WS-PUSH
    _BZ-BX @ _BZ-WS-PUSH  _BZ-BY @ _BZ-WS-PUSH
    _BZ-CX @ _BZ-WS-PUSH  _BZ-CY @ _BZ-WS-PUSH
    _BZ-DX @ _BZ-WS-PUSH  _BZ-DY @ _BZ-WS-PUSH
    BEGIN  _BZ-WS-EMPTY? 0=  WHILE
        _BZ-WS-POP _BZ-DY !   _BZ-WS-POP _BZ-DX !
        _BZ-WS-POP _BZ-CY !   _BZ-WS-POP _BZ-CX !
        _BZ-WS-POP _BZ-BY !   _BZ-WS-POP _BZ-BX !
        _BZ-WS-POP _BZ-AY !   _BZ-WS-POP _BZ-AX !
        _BZ@0 _BZ@1 _BZ@2 _BZ@3 _BZ-TOL @ BZ-CUBIC-FLAT? IF
            _BZ@0 _BZ@3  _BZ-CB @ EXECUTE
        ELSE
            _BZ-CUBIC-SPLIT-PUSH
        THEN
    REPEAT ;
