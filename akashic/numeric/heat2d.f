\ =====================================================================
\  numeric/heat2d.f - Time steps for 2-D heat diffusion
\ =====================================================================
\  The heat equation du/dt = alpha * (d2u/dx2 + d2u/dy2) on a grid with
\  equal spacing h and time step dt, where r = alpha * dt / h^2.
\
\  NHEAT-EXPLICIT is one forward-Euler (FTCS) step:
\
\    u' = RN(L(u) * r + u)
\
\  with the 5-point Laplacian of numeric/stencil2d.f.  It is stable only
\  for 0 <= r <= 1/4, and it refuses any other r (NUM-E-RANGE).  The
\  check compares IEEE bit patterns as unsigned integers, which orders
\  nonnegative values correctly and puts negatives, infinity, and NaN
\  above 1/4.
\
\  The step writes a separate output grid.  Callers alternate two grids
\  from step to step.  It runs on a team (numeric/team.f); a team of one
\  core runs it on the caller's core alone, with the same bits.
\
\  NHEAT-IMPLICIT is one backward-Euler step, stable for every r >= 0.
\  It solves
\
\    (I - r L0) u' = u + r g
\
\  where L0 is the Laplacian with zero Dirichlet ghost values (zero-flux
\  sides stay as they are) and g = L(0), which carries the Dirichlet ghost
\  values.  The right-hand side is R = RN(L(0) * r + u), and the solve is
\  conjugate gradient (numeric/cg.f) from u, with the operator NT-UPDATE
\  at c = -r.  So the step also gives the same bits on any number of cores.
\  A stepper holds r, the solver's tolerance and iteration limit, and its
\  scratch; the output may be the grid itself.
\
\  Prefix: NHEAT-   public API
\          _NHEAT-  internal helpers
\
\  Load with:   REQUIRE numeric/heat2d.f
\ =====================================================================

PROVIDED akashic-numeric-heat2d

REQUIRE team-stencil2d.f
REQUIRE cg.f

0x3FD0000000000000 CONSTANT _NHEAT-F64-QUARTER
0x3E800000         CONSTANT _NHEAT-F32-QUARTER

\ Workspace bytes each team member needs for a step on a grid of this
\ shape: the stencil's rows and the reductions' block values.
: NHEAT-WS-BYTES  ( u -- bytes )  DUP NST-WS-BYTES SWAP NV-WS-BYTES MAX ;

: _NHEAT-R-OK?  ( r fmt -- flag )
    NUM-FP64 = IF _NHEAT-F64-QUARTER ELSE _NHEAT-F32-QUARTER THEN
    U> 0= ;

\ out = RN(L(u) * r + u) on the team, for 0 <= r <= 1/4 in u's format.
: NHEAT-EXPLICIT  ( r u bc out team -- status )
    3 PICK NARR-FMT DUP NUM-FORMAT? 0= IF DROP 2DROP 2DROP DROP NUM-E-FORMAT EXIT THEN
    5 PICK SWAP _NHEAT-R-OK? 0= IF 2DROP 2DROP DROP NUM-E-RANGE EXIT THEN
    NT-UPDATE ;

\ =====================================================================
\  Implicit steps
\ =====================================================================

  0 CONSTANT _NHI-R           \ r, in the grid's format
  8 CONSTANT _NHI-NEG-R       \ -r
 16 CONSTANT _NHI-TEAM        \ the team of the step under way
 24 CONSTANT _NHI-SCRATCH-A
 32 CONSTANT _NHI-SCRATCH-U
 64 CONSTANT _NHI-BC0         \ bc with zero Dirichlet ghost values
128 CONSTANT _NHI-ZROW        \ zero ghost vector for the top and bottom
160 CONSTANT _NHI-ZCOL        \ zero ghost vector for the left and right
192 CONSTANT _NHI-CG          \ the solver
_NHI-CG NCG-SIZE + CONSTANT NHEAT-IMPLICIT-SIZE

: _NHI-CG@    ( stepper -- ncg )   _NHI-CG + ;

\ The stepper's solver, for NCG-ITERATIONS and NCG-RESIDUAL.
: NHEAT-SOLVER  ( stepper -- ncg )  _NHI-CG + ;
: _NHI-TEAM@  ( stepper -- team )  _NHI-TEAM + @ ;

: _NHI-ROW-BYTES  ( u -- bytes )  DUP NARR-NX 1 ROT NARR-FMT NARR-BYTES ;
: _NHI-COL-BYTES  ( u -- bytes )  DUP NARR-NY 1 ROT NARR-FMT NARR-BYTES ;

\ a + b, or 0 when either is 0 or the sum cannot be a cell.
: _NHI-ADD  ( a b -- sum|0 )
    2DUP 0= SWAP 0= OR IF 2DROP 0 EXIT THEN
    2DUP -1 1 RSHIFT SWAP - > IF 2DROP 0 EXIT THEN
    + ;

\ Stepper scratch bytes for grids shaped like u: the solver's three arrays
\ and two zero ghost vectors.
: NHEAT-IMPLICIT-BYTES  ( u -- bytes|0 )
    DUP NCG-SCRATCH-BYTES OVER _NHI-ROW-BYTES _NHI-ADD SWAP _NHI-COL-BYTES _NHI-ADD ;

\ Is r nonnegative and finite in format fmt?
: _NHI-R-OK?  ( r fmt -- flag )
    NUM-FP64 = IF 0x7FF0000000000000 ELSE 0x7F800000 THEN U< ;

\ The solver's operator: out = RN(L0(v) * -r + v).
: _NHEAT-OP  ( v out team stepper -- status )
    >R ROT R@ _NHI-NEG-R + @ SWAP R> _NHI-BC0 + 4 ROLL 4 ROLL NT-UPDATE ;

\ Set up a stepper for grids shaped like u: r in u's format, the solver's
\ tolerance (binary64 bits) and iteration limit, and aligned scratch of
\ NHEAT-IMPLICIT-BYTES.
: NHEAT-IMPLICIT-INIT  ( r tol limit addr bytes u stepper -- status )
    >R
    DUP NARR-FMT NUM-FORMAT? 0= IF 2DROP 2DROP 2DROP R> DROP NUM-E-FORMAT EXIT THEN
    5 PICK OVER NARR-FMT _NHI-R-OK? 0= IF 2DROP 2DROP 2DROP R> DROP NUM-E-RANGE EXIT THEN
    4 PICK 0x7FF0000000000000 U< 0= 4 PICK 0< OR IF
        2DROP 2DROP 2DROP R> DROP NUM-E-RANGE EXIT
    THEN
    DUP NHEAT-IMPLICIT-BYTES ?DUP 0= IF 2DROP 2DROP 2DROP R> DROP NUM-E-SPACE EXIT THEN
    2 PICK > IF 2DROP 2DROP 2DROP R> DROP NUM-E-SPACE EXIT THEN
    2 PICK 63 AND IF 2DROP 2DROP 2DROP R> DROP NUM-E-ALIGN EXIT THEN
    2 PICK 2 PICK MSPAN-NONWRAPPING? 0= IF 2DROP 2DROP 2DROP R> DROP NUM-E-SPACE EXIT THEN
    R@ NHEAT-IMPLICIT-SIZE 0 FILL
    NIP
    OVER R@ _NHI-SCRATCH-A + !  DUP NHEAT-IMPLICIT-BYTES R@ _NHI-SCRATCH-U + !
    2DUP DUP NCG-SCRATCH-BYTES SWAP R@ _NHI-CG@ NCG-INIT DROP
    2DUP NCG-SCRATCH-BYTES +
    OVER NARR-NX 1 3 PICK NARR-FMT R@ _NHI-ZROW + NARR-INIT DROP
    2DUP NCG-SCRATCH-BYTES + OVER _NHI-ROW-BYTES +
    OVER NARR-NY 1 3 PICK NARR-FMT R@ _NHI-ZCOL + NARR-INIT DROP
    0 R@ _NHI-ZROW + NV-FILL DROP  0 R@ _NHI-ZCOL + NV-FILL DROP
    ['] _NHEAT-OP R@ R@ _NHI-CG@ NCG-OPERATOR!
    NARR-FMT >R DROP R>                              ( r tol limit fmt )
    SWAP >R SWAP >R                                  \ ( r fmt ) R: stepper limit tol
    OVER SWAP NUM-NEG-ZERO XOR                       ( r -r )
    R> R> R@ _NHI-CG@ NCG-LIMITS! DROP
    R@ _NHI-NEG-R + !  R> _NHI-R + !
    NUM-OK ;

\ The stepper's copy of bc, with each Dirichlet side reading zeros.
: _NHI-BC0!  ( bc stepper -- )
    DUP _NHI-BC0 + NBC-INIT
    4 0 DO
        I 2 PICK NBC-KIND NBC-DIRICHLET = IF
            I NBC-LEFT < IF DUP _NHI-ZROW + ELSE DUP _NHI-ZCOL + THEN
            I 2 PICK _NHI-BC0 + NBC-DIRICHLET! DROP
        THEN
    LOOP
    2DROP ;

\ Does the span a u stay clear of the stepper's scratch?
: _NHI-APART?  ( a u stepper -- flag )
    DUP _NHI-SCRATCH-A + @ SWAP _NHI-SCRATCH-U + @ MSPAN-OVERLAP? 0= ;

\ Do bc's Dirichlet vectors stay clear of the stepper's scratch?
: _NHI-BC-APART?  ( bc stepper -- flag )
    -1 ROT ROT
    4 0 DO
        I 2 PICK NBC-KIND NBC-DIRICHLET = IF
            I 2 PICK NBC-GHOST ?DUP IF
                NARR-STORAGE 2 PICK _NHI-APART? 3 ROLL AND -ROT
            THEN
        THEN
    LOOP
    2DROP ;

\ The right-hand side into the solver's R: P = +0, Q = L(P) with bc, and
\ R = RN(Q * r + u).
: _NHI-RHS  ( u bc stepper -- status )
    >R
    0 R@ _NHI-CG@ NCG-P R@ _NHI-TEAM@ NT-FILL ?DUP IF NIP NIP R> DROP EXIT THEN
    R@ _NHI-CG@ NCG-P SWAP R@ _NHI-CG@ NCG-Q R@ _NHI-TEAM@ NT-LAPLACE ?DUP IF
        NIP R> DROP EXIT
    THEN
    R@ _NHI-CG@ NCG-R R@ _NHI-TEAM@ NT-COPY ?DUP IF R> DROP EXIT THEN
    R@ _NHI-R + @ R@ _NHI-CG@ NCG-Q R@ _NHI-CG@ NCG-R R> _NHI-TEAM@ NT-AXPY ;

\ One backward-Euler step on the team: out = u', the solution of
\ (I - r L0) u' = u + r g.  out may be u itself, but may not otherwise
\ overlap it.  Returns the solver's iteration count.
: NHEAT-IMPLICIT  ( u bc out stepper team -- iterations status )
    OVER _NHI-TEAM + !
    >R
    2 PICK R@ _NHI-CG@ NCG-R NARR-SAME-SHAPE? 0= IF 2DROP DROP R> DROP 0 NUM-E-SHAPE EXIT THEN
    DUP R@ _NHI-CG@ NCG-R NARR-SAME-SHAPE? 0= IF 2DROP DROP R> DROP 0 NUM-E-SHAPE EXIT THEN
    2 PICK NARR-ADDR OVER NARR-ADDR <> IF
        2 PICK NARR-STORAGE 2 PICK NARR-STORAGE MSPAN-OVERLAP? IF
            2DROP DROP R> DROP 0 NUM-E-OVERLAP EXIT
        THEN
    THEN
    2 PICK NARR-STORAGE R@ _NHI-APART? 0= IF 2DROP DROP R> DROP 0 NUM-E-OVERLAP EXIT THEN
    DUP NARR-STORAGE R@ _NHI-APART? 0= IF 2DROP DROP R> DROP 0 NUM-E-OVERLAP EXIT THEN
    OVER R@ _NHI-BC-APART? 0= IF 2DROP DROP R> DROP 0 NUM-E-OVERLAP EXIT THEN
    OVER R@ _NHI-BC0!
    ROT ROT OVER SWAP R@ _NHI-RHS ?DUP IF NIP NIP R> DROP 0 SWAP EXIT THEN
    OVER R@ _NHI-TEAM@ NT-COPY ?DUP IF NIP R> DROP 0 SWAP EXIT THEN
    R@ _NHI-TEAM@ R@ _NHI-CG@ NCG-SOLVE
    R> _NHI-CG@ NCG-ITERATIONS SWAP ;
