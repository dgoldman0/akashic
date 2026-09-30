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
\  from step to step.
\
\  Prefix: NHEAT-   public API
\          _NHEAT-  internal helpers
\
\  Load with:   REQUIRE numeric/heat2d.f
\ =====================================================================

PROVIDED akashic-numeric-heat2d

REQUIRE stencil2d.f

0x3FD0000000000000 CONSTANT _NHEAT-F64-QUARTER
0x3E800000         CONSTANT _NHEAT-F32-QUARTER

\ Workspace bytes for a step on a grid of this shape.
: NHEAT-WS-BYTES  ( u -- bytes )  NST-WS-BYTES ;

: _NHEAT-R-OK?  ( r fmt -- flag )
    NUM-FP64 = IF _NHEAT-F64-QUARTER ELSE _NHEAT-F32-QUARTER THEN
    U> 0= ;

\ out = RN(L(u) * r + u), for 0 <= r <= 1/4 in u's format.
: NHEAT-EXPLICIT  ( r u bc out ws -- status )
    3 PICK NARR-FMT DUP NUM-FORMAT? 0= IF DROP 2DROP 2DROP DROP NUM-E-FORMAT EXIT THEN
    5 PICK SWAP _NHEAT-R-OK? 0= IF 2DROP 2DROP DROP NUM-E-RANGE EXIT THEN
    NST-UPDATE ;
