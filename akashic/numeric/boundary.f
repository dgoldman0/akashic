\ =====================================================================
\  numeric/boundary.f - Boundary conditions for grid stencils
\ =====================================================================
\  A stencil reads values outside an NX-by-NY array: row -1 above it,
\  row NY below it, column -1 to its left, and column NX to its right.
\  These are its ghost values.  A boundary-condition descriptor says
\  where each side's ghost values come from.
\
\    Zero flux   A ghost value equals the edge element next to it, so no
\                heat crosses the side.
\    Dirichlet   Ghost values come from a caller vector: NX values for
\                the top and bottom sides, NY values for the left and
\                right sides, in the grid's format.
\
\  The descriptor and the ghost vectors belong to the caller.
\
\  Prefix: NBC-   public API
\          _NBC-  internal helpers
\
\  Load with:   REQUIRE numeric/boundary.f
\ =====================================================================

PROVIDED akashic-numeric-boundary

REQUIRE array.f

0 CONSTANT NBC-TOP        \ row -1
1 CONSTANT NBC-BOTTOM     \ row NY
2 CONSTANT NBC-LEFT       \ column -1
3 CONSTANT NBC-RIGHT      \ column NX

0 CONSTANT NBC-ZERO-FLUX
1 CONSTANT NBC-DIRICHLET

\ Four sides of two cells each: kind, then the ghost vector descriptor.
64 CONSTANT NBC-SIZE

: _NBC-SIDE   ( side bc -- addr )  SWAP 16 * + ;
: _NBC-SIDE?  ( side -- flag )  0 4 WITHIN ;

: NBC-KIND   ( side bc -- kind )  _NBC-SIDE @ ;
: NBC-GHOST  ( side bc -- arr )   _NBC-SIDE 8 + @ ;

\ Every side zero flux.
: NBC-INIT  ( bc -- )  NBC-SIZE 0 FILL ;

: NBC-ZERO-FLUX!  ( side bc -- status )
    OVER _NBC-SIDE? 0= IF 2DROP NUM-E-RANGE EXIT THEN
    _NBC-SIDE NBC-ZERO-FLUX OVER ! 0 SWAP 8 + !
    NUM-OK ;

\ Ghost values for side come from the vector descriptor ghost.
: NBC-DIRICHLET!  ( ghost side bc -- status )
    OVER _NBC-SIDE? 0= IF DROP 2DROP NUM-E-RANGE EXIT THEN
    _NBC-SIDE NBC-DIRICHLET OVER ! 8 + !
    NUM-OK ;

\ Ghost values a side of grid u needs: NX for top and bottom, NY for
\ left and right.
: _NBC-EXPECT  ( u side -- n )
    NBC-LEFT < IF NARR-NX ELSE NARR-NY THEN ;

: _NBC-GHOST-OK?  ( u g side -- flag )
    >R
    OVER NARR-FMT OVER NARR-FMT =
    OVER NARR-NY 1 = AND
    -ROT NARR-NX SWAP R> _NBC-EXPECT = AND ;

\ Can bc serve grid u?  A Dirichlet side needs a one-row ghost vector of
\ u's format and the right length (NUM-E-SHAPE), and each kind must be
\ one of the two defined (NUM-E-RANGE).
: NBC-CHECK  ( u bc -- status )
    4 0 DO
        I OVER NBC-KIND
        DUP NBC-ZERO-FLUX = IF DROP ELSE
            NBC-DIRICHLET <> IF UNLOOP 2DROP NUM-E-RANGE EXIT THEN
            I OVER NBC-GHOST ?DUP 0= IF UNLOOP 2DROP NUM-E-SHAPE EXIT THEN
            2 PICK SWAP I _NBC-GHOST-OK? 0= IF
                UNLOOP 2DROP NUM-E-SHAPE EXIT
            THEN
        THEN
    LOOP
    2DROP NUM-OK ;
