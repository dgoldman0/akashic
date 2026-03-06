\ interp.f — Interpolation, easing, and spline functions
\
\ Easing curves for CSS transitions / animations,
\ plus general-purpose spline interpolation.
\
\ All inputs/outputs are FP16.  Parameter `t` is expected
\ in [0, 1] unless otherwise noted.
\
\ Prefix: INTERP-  (public API)
\         _IP-     (internal helpers)
\
\ Load with:   REQUIRE interp.f
\
\ === Public API ===
\   INTERP-SMOOTHSTEP       ( edge0 edge1 x -- r )
\   INTERP-SMOOTHERSTEP     ( edge0 edge1 x -- r )
\   INTERP-EASE-IN-QUAD     ( t -- r )
\   INTERP-EASE-OUT-QUAD    ( t -- r )
\   INTERP-EASE-IN-OUT-QUAD ( t -- r )
\   INTERP-EASE-IN-CUBIC    ( t -- r )
\   INTERP-EASE-OUT-CUBIC   ( t -- r )
\   INTERP-EASE-IN-OUT-CUBIC ( t -- r )
\   INTERP-EASE-IN-SINE     ( t -- r )
\   INTERP-EASE-OUT-SINE    ( t -- r )
\   INTERP-EASE-ELASTIC     ( t -- r )
\   INTERP-EASE-BOUNCE      ( t -- r )
\   INTERP-CUBIC-BEZIER     ( t x1 y1 x2 y2 -- r )
\   INTERP-CATMULL-ROM      ( p0 p1 p2 p3 t -- r )
\   INTERP-HERMITE          ( p0 m0 p1 m1 t -- r )

REQUIRE fp16-ext.f
REQUIRE trig.f
REQUIRE exp.f

PROVIDED akashic-interp

\ =====================================================================
\  Constants
\ =====================================================================

0x3C00 CONSTANT _IP-ONE              \ 1.0
0x3800 CONSTANT _IP-HALF             \ 0.5
0x4000 CONSTANT _IP-TWO              \ 2.0
0x4200 CONSTANT _IP-THREE            \ 3.0
0x4400 CONSTANT _IP-FOUR             \ 4.0
0x4500 CONSTANT _IP-FIVE             \ 5.0
0x4600 CONSTANT _IP-SIX              \ 6.0
0x4900 CONSTANT _IP-TEN              \ 10.0
0x4BC0 CONSTANT _IP-FIFTEEN          \ 15.0
0x0000 CONSTANT _IP-ZERO             \ 0.0

\ =====================================================================
\  Helpers
\ =====================================================================

: _IP-CLAMP01  ( x -- clamped )
    \ Clamp to [0, 1]
    DUP FP16-SIGN IF DROP _IP-ZERO EXIT THEN
    DUP _IP-ONE FP16-GT IF DROP _IP-ONE THEN ;

: _IP-SQR  ( x -- x² )
    DUP FP16-MUL ;

: _IP-CUBE  ( x -- x³ )
    DUP DUP FP16-MUL FP16-MUL ;

\ =====================================================================
\  INTERP-SMOOTHSTEP — Hermite smoothstep: 3t² − 2t³
\ =====================================================================

: INTERP-SMOOTHSTEP  ( edge0 edge1 x -- r )
    ROT                               ( edge1 x edge0 )
    TUCK FP16-SUB                     ( edge1 edge0 x-edge0 )
    -ROT FP16-SUB                     ( x-edge0 edge1-edge0 )
    FP16-DIV                          ( t_raw )
    _IP-CLAMP01                       ( t )
    DUP _IP-SQR                       ( t t² )
    OVER _IP-TWO FP16-MUL             ( t t² 2t )
    _IP-THREE SWAP FP16-SUB           ( t t² 3-2t )
    FP16-MUL                          ( t t²·[3-2t] )
    NIP ;

\ =====================================================================
\  INTERP-SMOOTHERSTEP — Perlin's: 6t⁵ − 15t⁴ + 10t³
\ =====================================================================

: INTERP-SMOOTHERSTEP  ( edge0 edge1 x -- r )
    ROT TUCK FP16-SUB
    -ROT FP16-SUB FP16-DIV
    _IP-CLAMP01                       ( t )
    DUP                               ( t t )
    \ t*(t*6 - 15) + 10
    DUP _IP-SIX FP16-MUL _IP-FIFTEEN FP16-SUB
    OVER FP16-MUL _IP-TEN FP16-ADD   ( t t poly )
    \ result = t³ * poly
    SWAP _IP-CUBE                     ( t poly t³ )
    FP16-MUL NIP ;

\ =====================================================================
\  Quadratic easing
\ =====================================================================

: INTERP-EASE-IN-QUAD  ( t -- r )
    _IP-SQR ;

: INTERP-EASE-OUT-QUAD  ( t -- r )
    _IP-ONE SWAP FP16-SUB _IP-SQR
    _IP-ONE SWAP FP16-SUB ;

: INTERP-EASE-IN-OUT-QUAD  ( t -- r )
    DUP _IP-HALF FP16-LT IF
        \ t < 0.5:  2t²
        _IP-SQR _IP-TWO FP16-MUL
    ELSE
        \ t ≥ 0.5:  1 − (−2t + 2)²/2
        _IP-TWO FP16-MUL _IP-TWO FP16-SUB FP16-NEG
        _IP-SQR _IP-HALF FP16-MUL
        _IP-ONE SWAP FP16-SUB
    THEN ;

\ =====================================================================
\  Cubic easing
\ =====================================================================

: INTERP-EASE-IN-CUBIC  ( t -- r )
    _IP-CUBE ;

: INTERP-EASE-OUT-CUBIC  ( t -- r )
    _IP-ONE SWAP FP16-SUB _IP-CUBE
    _IP-ONE SWAP FP16-SUB ;

: INTERP-EASE-IN-OUT-CUBIC  ( t -- r )
    DUP _IP-HALF FP16-LT IF
        \ t < 0.5:  4t³
        _IP-CUBE _IP-FOUR FP16-MUL
    ELSE
        \ t ≥ 0.5:  1 − (−2t + 2)³/2
        _IP-TWO FP16-MUL _IP-TWO FP16-SUB FP16-NEG
        _IP-CUBE _IP-HALF FP16-MUL
        _IP-ONE SWAP FP16-SUB
    THEN ;

\ =====================================================================
\  Sinusoidal easing  (requires trig.f)
\ =====================================================================

: INTERP-EASE-IN-SINE  ( t -- r )
    \ 1 − cos(t·π/2)
    TRIG-PI/2 FP16-MUL TRIG-COS
    _IP-ONE SWAP FP16-SUB ;

: INTERP-EASE-OUT-SINE  ( t -- r )
    \ sin(t·π/2)
    TRIG-PI/2 FP16-MUL TRIG-SIN ;

\ =====================================================================
\  Elastic easing: −2^(10(t−1)) · sin((t−1−0.075)·2π / 0.3)
\ =====================================================================

0x2CCD CONSTANT _IP-PT3             \ 0.3
0x28CD CONSTANT _IP-PT075           \ 0.075

VARIABLE _IP-E-T1

: INTERP-EASE-ELASTIC  ( t -- r )
    DUP _IP-ZERO = IF EXIT THEN
    DUP _IP-ONE  = IF EXIT THEN
    _IP-ONE FP16-SUB _IP-E-T1 !      ( -- )
    \ power = −2^(10·t1)
    _IP-E-T1 @ _IP-TEN FP16-MUL EXP-EXP2  ( 2^[10·t1] )
    FP16-NEG                          ( −2^[10·t1] )
    \ angle = (t1 − 0.075) · 2π / 0.3
    _IP-E-T1 @ _IP-PT075 FP16-SUB
    TRIG-2PI FP16-MUL
    _IP-PT3 FP16-DIV                  ( power angle )
    TRIG-SIN FP16-MUL ;

\ =====================================================================
\  Bounce easing (piecewise quadratic)
\ =====================================================================

0x4DF8 CONSTANT _IP-B-N1            \ 7.5625
0x4124 CONSTANT _IP-B-D1            \ 2.75
0x3C00 CONSTANT _IP-B-1D2P75        \ 1.0/2.75 ≈ 0.3636 → 0x35D1
\ Precomputed thresholds:
0x35D1 CONSTANT _IP-B-T1            \ 1/2.75
0x3951 CONSTANT _IP-B-T2            \ 2/2.75
0x3B8E CONSTANT _IP-B-T3            \ 2.5/2.75

VARIABLE _IP-B-T

: _IP-BOUNCE-OUT  ( t -- r )
    DUP _IP-B-T1 FP16-LT IF
        \ n1·t·t
        _IP-B-N1 OVER FP16-MUL FP16-MUL EXIT
    THEN
    DUP _IP-B-T2 FP16-LT IF
        \ t -= 1.5/2.75
        0x3800 FP16-SUB               ( adjusted_t )  \ 1.5/2.75 ≈ 0.5455
        DUP _IP-B-N1 SWAP FP16-MUL FP16-MUL
        0x3B00 FP16-ADD EXIT           ( n1·t'·t' + 0.75 )
    THEN
    DUP _IP-B-T3 FP16-LT IF
        \ t -= 2.25/2.75
        0x3A49 FP16-SUB
        DUP _IP-B-N1 SWAP FP16-MUL FP16-MUL
        0x3F00 FP16-ADD EXIT           ( n1·t'·t' + 0.9375 )
    THEN
    \ t -= 2.625/2.75
    0x3B4D FP16-SUB
    DUP _IP-B-N1 SWAP FP16-MUL FP16-MUL
    0x3F80 FP16-ADD ;                  ( n1·t'·t' + 0.984375 )

: INTERP-EASE-BOUNCE  ( t -- r )
    _IP-ONE SWAP FP16-SUB
    _IP-BOUNCE-OUT
    _IP-ONE SWAP FP16-SUB ;

\ =====================================================================
\  CSS cubic-bezier(x1, y1, x2, y2)
\ =====================================================================
\  Given time t ∈ [0,1], the CSS cubic-bezier defines control points
\  P0=(0,0), P1=(x1,y1), P2=(x2,y2), P3=(1,1).
\
\  We need to solve for the parameter u such that
\    Bx(u) = 3(1−u)²u·x1 + 3(1−u)u²·x2 + u³ = t
\  Then return:
\    By(u) = 3(1−u)²u·y1 + 3(1−u)u²·y2 + u³
\
\  We use 5 Newton-Raphson iterations for u.

VARIABLE _IP-CB-X1
VARIABLE _IP-CB-Y1
VARIABLE _IP-CB-X2
VARIABLE _IP-CB-Y2
VARIABLE _IP-CB-T

: _IP-CB-EVAL  ( u coeffX1 coeffX2 -- Bx )
    \ B(u) = 3(1-u)²u·c1 + 3(1-u)u²·c2 + u³
    \ Store coefficients to work with stack
    SWAP                               ( u c2 c1 )
    2 PICK _IP-ONE 2 PICK FP16-SUB     ( u c2 c1 u 1-u )
    DUP FP16-MUL                       ( u c2 c1 u [1-u]² )
    3 PICK FP16-MUL                    ( u c2 c1 u·[1-u]² )
    _IP-THREE FP16-MUL                 ( u c2 c1 3u[1-u]² )
    FP16-MUL                           ( u c2 term1 )
    -ROT                               ( term1 u c2 )
    OVER DUP FP16-MUL                  ( term1 u c2 u² )
    _IP-ONE 3 PICK FP16-SUB FP16-MUL  ( term1 u c2 u²·[1-u] )
    _IP-THREE FP16-MUL FP16-MUL       ( term1 u term2 )
    ROT FP16-ADD                       ( u term1+term2 )
    SWAP DUP DUP FP16-MUL FP16-MUL    ( sum u³ )
    FP16-ADD ;

: _IP-CB-DERIV  ( u c1 -- dB/du )
    \ dB/du = 3c1(1-u)² + (6c2-6c1)(1-u)u + 3(1-c2)u²
    \ Simplified: compute numerically with a small step
    \ For FP16, a simple forward-difference is sufficient:
    \ dB/du ≈ (B(u+h) - B(u-h)) / (2h)  where h = 1/64
    DROP                               ( u )
    DUP 0x1400 FP16-ADD               ( u u+h )   \ h ≈ 1/64
    _IP-CB-X1 @ _IP-CB-X2 @ _IP-CB-EVAL  ( u B[u+h] )
    SWAP 0x1400 FP16-SUB              ( B[u+h] u-h )
    _IP-CB-X1 @ _IP-CB-X2 @ _IP-CB-EVAL  ( B[u+h] B[u-h] )
    FP16-SUB                           ( B[u+h]-B[u-h] )
    0x5400 FP16-MUL ;                 ( ·32 → /[2h] )

VARIABLE _IP-CB-U

: INTERP-CUBIC-BEZIER  ( t x1 y1 x2 y2 -- r )
    _IP-CB-Y2 ! _IP-CB-X2 ! _IP-CB-Y1 ! _IP-CB-X1 !
    _IP-CB-T !
    \ Initial guess: u = t
    _IP-CB-T @ _IP-CB-U !
    \ 5 Newton iterations
    5 0 DO
        _IP-CB-U @
        DUP _IP-CB-X1 @ _IP-CB-X2 @ _IP-CB-EVAL  ( u Bx[u] )
        _IP-CB-T @ FP16-SUB                       ( u err )
        SWAP DUP _IP-CB-X1 @ _IP-CB-DERIV         ( err u deriv )
        DUP _IP-ZERO = IF 2DROP DROP LEAVE THEN
        -ROT SWAP FP16-DIV                         ( deriv err/deriv )
        SWAP DROP                                  ( correction )
        _IP-CB-U @ SWAP FP16-SUB _IP-CB-U !
    LOOP
    \ Evaluate y at converged u
    _IP-CB-U @ _IP-CB-Y1 @ _IP-CB-Y2 @ _IP-CB-EVAL ;

\ =====================================================================
\  INTERP-CATMULL-ROM — Catmull-Rom spline
\ =====================================================================
\  q(t) = 0.5 * ( 2p1 + (-p0+p2)t + (2p0-5p1+4p2-p3)t²
\                + (-p0+3p1-3p2+p3)t³ )

VARIABLE _IP-CR-P0
VARIABLE _IP-CR-P1
VARIABLE _IP-CR-P2
VARIABLE _IP-CR-P3

: INTERP-CATMULL-ROM  ( p0 p1 p2 p3 t -- r )
    >R
    _IP-CR-P3 ! _IP-CR-P2 ! _IP-CR-P1 ! _IP-CR-P0 !
    R>                                 ( t )
    \ a0 = 2·p1
    _IP-CR-P1 @ _IP-TWO FP16-MUL      ( t a0 )
    \ a1 = −p0 + p2
    _IP-CR-P2 @ _IP-CR-P0 @ FP16-SUB  ( t a0 a1 )
    \ a2 = 2·p0 − 5·p1 + 4·p2 − p3
    _IP-CR-P0 @ _IP-TWO FP16-MUL
    _IP-CR-P1 @ _IP-FIVE FP16-MUL FP16-SUB
    _IP-CR-P2 @ _IP-FOUR FP16-MUL FP16-ADD
    _IP-CR-P3 @ FP16-SUB              ( t a0 a1 a2 )
    \ a3 = −p0 + 3·p1 − 3·p2 + p3
    _IP-CR-P0 @ FP16-NEG
    _IP-CR-P1 @ _IP-THREE FP16-MUL FP16-ADD
    _IP-CR-P2 @ _IP-THREE FP16-MUL FP16-SUB
    _IP-CR-P3 @ FP16-ADD              ( t a0 a1 a2 a3 )
    \ Horner: ((a3·t + a2)·t + a1)·t + a0
    4 PICK FP16-MUL FP16-ADD          ( t a0 a1 a3t+a2 )
    3 PICK FP16-MUL FP16-ADD          ( t a0 [a3t+a2]t+a1 )
    ROT FP16-MUL FP16-ADD             ( [[a3t+a2]t+a1]t+a0 )
    _IP-HALF FP16-MUL ;

\ =====================================================================
\  INTERP-HERMITE — Cubic Hermite interpolation
\ =====================================================================
\  H(t) = (2t³ − 3t² + 1)·p0 + (t³ − 2t² + t)·m0
\        + (−2t³ + 3t²)·p1  + (t³ − t²)·m1

VARIABLE _IP-H-P0
VARIABLE _IP-H-M0
VARIABLE _IP-H-P1
VARIABLE _IP-H-M1
VARIABLE _IP-H-T
VARIABLE _IP-H-T2
VARIABLE _IP-H-T3

: INTERP-HERMITE  ( p0 m0 p1 m1 t -- r )
    DUP _IP-H-T !
    DUP DUP FP16-MUL DUP _IP-H-T2 !  ( p0 m0 p1 m1 t t² )
    SWAP FP16-MUL _IP-H-T3 !          ( p0 m0 p1 m1 )
    _IP-H-M1 ! _IP-H-P1 ! _IP-H-M0 ! _IP-H-P0 !
    \ h00 = 2t³ − 3t² + 1
    _IP-H-T3 @ _IP-TWO FP16-MUL
    _IP-H-T2 @ _IP-THREE FP16-MUL FP16-SUB
    _IP-ONE FP16-ADD
    _IP-H-P0 @ FP16-MUL               ( h00·p0 )
    \ h10 = t³ − 2t² + t
    _IP-H-T3 @
    _IP-H-T2 @ _IP-TWO FP16-MUL FP16-SUB
    _IP-H-T @ FP16-ADD
    _IP-H-M0 @ FP16-MUL               ( h00·p0 h10·m0 )
    FP16-ADD                           ( sum )
    \ h01 = −2t³ + 3t²
    _IP-H-T3 @ _IP-TWO FP16-MUL FP16-NEG
    _IP-H-T2 @ _IP-THREE FP16-MUL FP16-ADD
    _IP-H-P1 @ FP16-MUL               ( sum h01·p1 )
    FP16-ADD                           ( sum )
    \ h11 = t³ − t²
    _IP-H-T3 @ _IP-H-T2 @ FP16-SUB
    _IP-H-M1 @ FP16-MUL               ( sum h11·m1 )
    FP16-ADD ;

\ ── Concurrency ──────────────────────────────────────────
\ Interpolation words are NOT reentrant.  They use shared
\ VARIABLE scratch for intermediate results.  Callers must
\ ensure single-task access via WITH-GUARD, WITH-CRITICAL,
\ or by running with preemption disabled.
