\ =====================================================================
\  numeric/stencil2d.f - The 5-point Laplacian on 2-D grids
\ =====================================================================
\  A grid is an NX-by-NY numeric array (numeric/array.f) with unit
\  spacing.  Its Laplacian at row i, column j is
\
\    L(u) = up + down + left + right - 4u
\
\  where the neighbours outside the grid are ghost values supplied by a
\  boundary-condition descriptor (numeric/boundary.f).  The order of
\  operations is fixed, one rounding each:
\
\    t = up + down,  t = t + left,  t = t + right,  L = RN(u * -4 + t)
\
\  NST-UPDATE applies u + c*L(u) in one sweep, rounding once more:
\  RN(L * c + u).  With c = r it is an explicit diffusion step; with
\  c = -r it is the operator of an implicit one.
\
\  Rows are processed whole.  A row's left and right neighbours are the
\  row copied one element over into two workspace rows with CMOVE; the
\  boundary condition supplies the element shifted in.  Lanes of those
\  rows past NX hold +0, so each output row's padding lanes are also
\  defined: computed from the input's padding lanes and zeros.
\
\  Arrays in HBW are read and written in place.  A grid anywhere else
\  streams through the workspace: each row is copied once into a ring of
\  three workspace rows, which the stencil reads.  An output anywhere
\  else is computed into a workspace row and copied out once.  Each row
\  then crosses the external memory link once each way, where reading
\  in place would cross it several times.
\
\  The output must not overlap the grid, a Dirichlet ghost vector, or the
\  workspace.  Kernels set TMODE and the tile address registers and leave
\  them set.  They hold no module state; the workspace (NST-WS-BYTES)
\  carries the loop state.
\
\  Prefix: NST-   public API
\          _NST-  internal helpers
\          _NSF-  workspace frame fields
\
\  Load with:   REQUIRE numeric/stencil2d.f
\ =====================================================================

PROVIDED akashic-numeric-stencil2d

REQUIRE array.f
REQUIRE boundary.f

\ =====================================================================
\  Workspace frame
\ =====================================================================

  0 CONSTANT _NSF-U          \ grid base
  8 CONSTANT _NSF-OUT        \ output base
 16 CONSTANT _NSF-PITCH      \ bytes per row
 24 CONSTANT _NSF-TPR        \ tiles per row
 32 CONSTANT _NSF-NX
 40 CONSTANT _NSF-NY
 48 CONSTANT _NSF-LB         \ bytes per lane
 56 CONSTANT _NSF-BC         \ boundary-condition descriptor
 64 CONSTANT _NSF-UPROW      \ current row's upper neighbour
 72 CONSTANT _NSF-DOWNROW    \ current row's lower neighbour
 80 CONSTANT _NSF-UROW       \ current row
 88 CONSTANT _NSF-OUTROW     \ current output row
 96 CONSTANT _NSF-LROW       \ left-neighbour row
104 CONSTANT _NSF-RROW       \ right-neighbour row
112 CONSTANT _NSF-PRELOAD    \ nonzero: copy each grid row to the output
120 CONSTANT _NSF-FMT
128 CONSTANT _NSF-RING       \ ring of staged grid rows; 0: grid in place
136 CONSTANT _NSF-OBUF       \ staged output row; 0: output in place
192 CONSTANT _NSF-M4         \ tile of -4
256 CONSTANT _NSF-C          \ tile of the update coefficient
320 CONSTANT _NSF-T          \ tile for one Laplacian result
384 CONSTANT _NSF-ROWS       \ left, right, three ring rows, output row

\ Workspace bytes for a grid of this shape.
: NST-WS-BYTES  ( u -- bytes )  NARR-PITCH 6 * _NSF-ROWS + ;

0xC010000000000000 CONSTANT _NST-F64-M4
0xC0800000         CONSTANT _NST-F32-M4

\ =====================================================================
\  Checks
\ =====================================================================

\ Does the span a u overlap neither out nor the workspace?
: _NST-APART?  ( a u out ws -- flag )
    >R NARR-STORAGE 2OVER MSPAN-OVERLAP? IF R> DROP 2DROP 0 EXIT THEN
    R> DUP NWS-ADDR SWAP NWS-BYTES MSPAN-OVERLAP? 0= ;

\ Can the stencil run on u with bc into out, using ws?
: NST-CHECK  ( u bc out ws -- status )
    3 PICK NARR-FMT NUM-FORMAT? 0= IF 2DROP 2DROP NUM-E-FORMAT EXIT THEN
    3 PICK 2 PICK NARR-SAME-SHAPE? 0= IF 2DROP 2DROP NUM-E-SHAPE EXIT THEN
    3 PICK 3 PICK NBC-CHECK ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    DUP NWS-BYTES 4 PICK NST-WS-BYTES < IF 2DROP 2DROP NUM-E-SPACE EXIT THEN
    OVER NARR-STORAGE 2 PICK NWS-ADDR 3 PICK NWS-BYTES MSPAN-OVERLAP? IF
        2DROP 2DROP NUM-E-OVERLAP EXIT
    THEN
    3 PICK NARR-STORAGE 3 PICK 3 PICK _NST-APART? 0= IF
        2DROP 2DROP NUM-E-OVERLAP EXIT
    THEN
    4 0 DO
        I 3 PICK NBC-KIND NBC-DIRICHLET = IF
            I 3 PICK NBC-GHOST NARR-STORAGE 3 PICK 3 PICK _NST-APART? 0= IF
                UNLOOP 2DROP 2DROP NUM-E-OVERLAP EXIT
            THEN
        THEN
    LOOP
    2DROP 2DROP NUM-OK ;

\ =====================================================================
\  Rows
\ =====================================================================

: _NST-LANE@  ( addr frame -- bits )
    _NSF-LB + @ 8 = IF @ ELSE L@ THEN ;

: _NST-LANE!  ( bits addr frame -- )
    _NSF-LB + @ 8 = IF ! ELSE L! THEN ;

: _NST-ROW-ADDR  ( i frame -- addr )
    SWAP OVER _NSF-PITCH + @ * SWAP _NSF-U + @ + ;

\ Grid row j where the stencil reads it: its ring row when the grid is
\ staged, else the row itself.
: _NST-SOURCE  ( j frame -- addr )
    DUP _NSF-RING + @ ?DUP IF
        >R SWAP 3 MOD SWAP _NSF-PITCH + @ * R> + EXIT
    THEN
    _NST-ROW-ADDR ;

\ Copy grid row j into its ring row, when the grid is staged.
: _NST-STAGE  ( j frame -- )
    DUP _NSF-RING + @ 0= IF 2DROP EXIT THEN
    2DUP _NST-ROW-ADDR -ROT
    DUP _NSF-PITCH + @ >R _NST-SOURCE R> CMOVE ;

\ Output row i where the stencil writes it: the staged output row, or
\ the row itself.
: _NST-TARGET  ( i frame -- addr )
    DUP _NSF-OBUF + @ ?DUP IF NIP NIP EXIT THEN
    SWAP OVER _NSF-PITCH + @ * SWAP _NSF-OUT + @ + ;

\ Copy the staged output row out to output row i, when there is one.
: _NST-PUT  ( i frame -- )
    DUP _NSF-OBUF + @ 0= IF 2DROP EXIT THEN
    DUP _NSF-OBUF + @ -ROT
    SWAP OVER _NSF-PITCH + @ * OVER _NSF-OUT + @ +
    SWAP _NSF-PITCH + @ CMOVE ;

\ Bytes moved into a neighbour row: all but one element.
: _NST-SHIFT-BYTES  ( frame -- u )
    DUP _NSF-NX + @ 1- SWAP _NSF-LB + @ * ;

\ The ghost row beyond an edge: the Dirichlet vector, or edge row i.
: _NST-EDGE-ROW  ( i side frame -- addr )
    >R R@ _NSF-BC + @ 2DUP NBC-KIND NBC-DIRICHLET = IF
        NBC-GHOST NARR-ADDR NIP
    ELSE
        2DROP R@ _NST-SOURCE
    THEN
    R> DROP ;

: _NST-UP-ROW  ( i frame -- addr )
    OVER 0= IF NBC-TOP SWAP _NST-EDGE-ROW EXIT THEN
    SWAP 1- SWAP _NST-SOURCE ;

: _NST-DOWN-ROW  ( i frame -- addr )
    2DUP _NSF-NY + @ 1- = IF NBC-BOTTOM SWAP _NST-EDGE-ROW EXIT THEN
    SWAP 1+ SWAP _NST-SOURCE ;

\ The ghost value in row i at column -1 (NBC-LEFT) or NX (NBC-RIGHT).
: _NST-GHOST-COL  ( i side frame -- bits )
    >R
    DUP R@ _NSF-BC + @ NBC-KIND NBC-DIRICHLET = IF
        R@ _NSF-BC + @ NBC-GHOST NARR-ADDR
        SWAP R@ _NSF-LB + @ * +
    ELSE
        NBC-LEFT = IF 0 ELSE R@ _NSF-NX + @ 1- THEN
        R@ _NSF-LB + @ *
        SWAP R@ _NST-SOURCE +
    THEN
    R> _NST-LANE@ ;

\ Point the frame at row i, and build its neighbour rows.
: _NST-SET-ROWS  ( i frame -- )
    2DUP _NST-SOURCE OVER _NSF-UROW + !
    2DUP _NST-TARGET OVER _NSF-OUTROW + !
    2DUP _NST-UP-ROW OVER _NSF-UPROW + !
    2DUP _NST-DOWN-ROW OVER _NSF-DOWNROW + !
    \ left: ghost, then elements 0 .. NX-2
    2DUP NBC-LEFT SWAP _NST-GHOST-COL OVER _NSF-LROW + @ 2 PICK _NST-LANE!
    DUP _NSF-UROW + @
    OVER _NSF-LROW + @ 2 PICK _NSF-LB + @ +
    2 PICK _NST-SHIFT-BYTES CMOVE
    \ right: elements 1 .. NX-1, then ghost
    DUP _NSF-UROW + @ OVER _NSF-LB + @ +
    OVER _NSF-RROW + @
    2 PICK _NST-SHIFT-BYTES CMOVE
    2DUP NBC-RIGHT SWAP _NST-GHOST-COL
    OVER _NSF-RROW + @ 2 PICK _NST-SHIFT-BYTES + 2 PICK _NST-LANE!
    \ an update starts from the grid row
    DUP _NSF-PRELOAD + @ IF
        DUP _NSF-UROW + @ OVER _NSF-OUTROW + @ 2 PICK _NSF-PITCH + @ CMOVE
    THEN
    2DROP ;

\ =====================================================================
\  Tiles
\ =====================================================================

\ The Laplacian of tile k of the current row, into the tile at dst.
: _NST-T  ( k frame dst -- )
    DUP TDST! >R
    2DUP _NSF-UPROW + @ + TSRC0!
    2DUP _NSF-DOWNROW + @ + TSRC1!  TADD
    R> TSRC0!
    2DUP _NSF-LROW + @ + TSRC1!  TADD
    2DUP _NSF-RROW + @ + TSRC1!  TADD
    2DUP _NSF-UROW + @ + TSRC0!
    NIP _NSF-M4 + TSRC1!  TFMA ;

: _NST-TILE-LAPLACE  ( k frame -- )
    2DUP _NSF-OUTROW + @ + _NST-T ;

\ out = RN(L * c + u); the output row already holds the grid row.
: _NST-TILE-UPDATE  ( k frame -- )
    2DUP DUP _NSF-T + _NST-T
    DUP _NSF-T + TSRC0!
    DUP _NSF-C + TSRC1!
    _NSF-OUTROW + @ + TDST!  TFMA ;

\ Row i: stage the row below it, compute every tile, and put the result.
: _NST-ROW  ( i frame xt -- )
    >R
    OVER 1+ OVER _NSF-NY + @ < IF OVER 1+ OVER _NST-STAGE THEN
    2DUP _NST-SET-ROWS
    R> OVER _NSF-TPR + @ 64 * 0 ?DO
        I 2 PICK 2 PICK EXECUTE
    64 +LOOP
    DROP _NST-PUT ;

\ Rows i0 up to i1.  A staged grid first needs rows i0-1 and i0 in its
\ ring; each row then stages the one below it.
: _NST-SWEEP  ( frame xt i1 i0 -- )
    2DUP > IF
        DUP 0> IF DUP 1- 4 PICK _NST-STAGE THEN
        DUP 4 PICK _NST-STAGE
    THEN
    ?DO I 2 PICK 2 PICK _NST-ROW LOOP
    2DROP ;

\ Is the span wholly inside HBW?
: _NST-IN-HBW?  ( addr bytes -- flag )
    OVER + HBW-BASE HBW-SIZE + U> 0= SWAP HBW-BASE U< 0= AND ;

\ Workspace row n: 0 left, 1 right, 2 to 4 the ring, 5 the output.
: _NST-WS-ROW  ( n frame -- addr )
    DUP _NSF-PITCH + @ ROT * + _NSF-ROWS + ;

\ Workspace row n for the grid-shaped array at addr, or 0 when the array
\ is in HBW.
: _NST-STAGING  ( addr n frame -- addr|0 )
    >R SWAP R@ _NSF-PITCH + @ R@ _NSF-NY + @ * _NST-IN-HBW? IF
        DROP 0
    ELSE
        R@ _NST-WS-ROW
    THEN
    R> DROP ;

\ Fill the frame for u, bc, and out in the workspace.
: _NST-FRAME  ( u bc out ws -- frame )
    NWS-ADDR >R
    NARR-ADDR R@ _NSF-OUT + !
    R@ _NSF-BC + !
    DUP NARR-ADDR R@ _NSF-U + !
    DUP NARR-PITCH R@ _NSF-PITCH + !
    DUP NARR-ROW-TILES R@ _NSF-TPR + !
    DUP NARR-NX R@ _NSF-NX + !
    DUP NARR-NY R@ _NSF-NY + !
    NARR-FMT DUP R@ _NSF-FMT + !
    DUP NUM-LANE-BYTES R@ _NSF-LB + !
    DUP NUM-FP64 = IF _NST-F64-M4 ELSE _NST-F32-M4 THEN
    SWAP NUM-SPLAT-CELL R@ _NSF-M4 + NUM-TILE-FILL
    0 R@ _NSF-PRELOAD + !
    0 R@ _NST-WS-ROW R@ _NSF-LROW + !
    1 R@ _NST-WS-ROW R@ _NSF-RROW + !
    R@ _NSF-U + @ 2 R@ _NST-STAGING R@ _NSF-RING + !
    R@ _NSF-OUT + @ 5 R@ _NST-STAGING R@ _NSF-OBUF + !
    2 R@ _NST-WS-ROW R@ _NSF-ROWS + ?DO 0 I ! 8 +LOOP
    R> ;

\ =====================================================================
\  Public words
\ =====================================================================

: _NST-DROP6  ( x1 x2 x3 x4 x5 x6 -- )  2DROP 2DROP 2DROP ;

\ Is 0 <= i0 <= i1 <= ny?
: _NST-ROWS?  ( u i0 i1 -- flag )
    ROT NARR-NY OVER >= >R
    2DUP <= >R
    DROP 0>= R> AND R> AND ;

\ Rows i0 up to i1 of out = L(u).
: NST-LAPLACE-ROWS  ( u bc out ws i0 i1 -- status )
    5 PICK 5 PICK 5 PICK 5 PICK NST-CHECK ?DUP IF >R _NST-DROP6 R> EXIT THEN
    5 PICK 2 PICK 2 PICK _NST-ROWS? 0= IF _NST-DROP6 NUM-E-RANGE EXIT THEN
    >R >R
    3 PICK NARR-FMT TMODE!
    _NST-FRAME ['] _NST-TILE-LAPLACE R> R> SWAP _NST-SWEEP
    NUM-OK ;

\ Rows i0 up to i1 of out = RN(L(u) * c + u), where c is scalar bits in
\ u's format.
: NST-UPDATE-ROWS  ( c u bc out ws i0 i1 -- status )
    5 PICK 5 PICK 5 PICK 5 PICK NST-CHECK ?DUP IF
        >R _NST-DROP6 DROP R> EXIT
    THEN
    5 PICK 2 PICK 2 PICK _NST-ROWS? 0= IF _NST-DROP6 DROP NUM-E-RANGE EXIT THEN
    >R >R
    3 PICK NARR-FMT TMODE!
    _NST-FRAME
    SWAP OVER _NSF-FMT + @ NUM-SPLAT-CELL OVER _NSF-C + NUM-TILE-FILL
    -1 OVER _NSF-PRELOAD + !
    ['] _NST-TILE-UPDATE R> R> SWAP _NST-SWEEP
    NUM-OK ;

\ out = L(u).
: NST-LAPLACE  ( u bc out ws -- status )
    0 4 PICK NARR-NY NST-LAPLACE-ROWS ;

\ out = RN(L(u) * c + u).
: NST-UPDATE  ( c u bc out ws -- status )
    0 4 PICK NARR-NY NST-UPDATE-ROWS ;
