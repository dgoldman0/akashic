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
128 CONSTANT _NSF-M4         \ tile of -4
192 CONSTANT _NSF-C          \ tile of the update coefficient
256 CONSTANT _NSF-T          \ tile for one Laplacian result
320 CONSTANT _NSF-ROWS       \ left-neighbour row, then right-neighbour row

\ Workspace bytes for a grid of this shape.
: NST-WS-BYTES  ( u -- bytes )  NARR-PITCH 2 * _NSF-ROWS + ;

0xC010000000000000 CONSTANT _NST-F64-M4
0xC0800000         CONSTANT _NST-F32-M4

\ =====================================================================
\  Checks
\ =====================================================================

\ Does the span a u overlap neither out nor the workspace?
: _NST-APART?  ( a u out ws -- flag )
    >R NARR-STORAGE 2OVER MSPAN-OVERLAP? IF R> DROP 2DROP 0 EXIT THEN
    R> DUP NWS-ADDR SWAP NWS-BYTES MSPAN-OVERLAP? 0= ;

: _NST-CHECK  ( u bc out ws -- status )
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

\ Bytes moved into a neighbour row: all but one element.
: _NST-SHIFT-BYTES  ( frame -- u )
    DUP _NSF-NX + @ 1- SWAP _NSF-LB + @ * ;

\ The ghost row beyond an edge: the Dirichlet vector, or edge row i.
: _NST-EDGE-ROW  ( i side frame -- addr )
    >R R@ _NSF-BC + @ 2DUP NBC-KIND NBC-DIRICHLET = IF
        NBC-GHOST NARR-ADDR NIP
    ELSE
        2DROP R@ _NST-ROW-ADDR
    THEN
    R> DROP ;

: _NST-UP-ROW  ( i frame -- addr )
    OVER 0= IF NBC-TOP SWAP _NST-EDGE-ROW EXIT THEN
    SWAP 1- SWAP _NST-ROW-ADDR ;

: _NST-DOWN-ROW  ( i frame -- addr )
    2DUP _NSF-NY + @ 1- = IF NBC-BOTTOM SWAP _NST-EDGE-ROW EXIT THEN
    SWAP 1+ SWAP _NST-ROW-ADDR ;

\ The ghost value in row i at column -1 (NBC-LEFT) or NX (NBC-RIGHT).
: _NST-GHOST-COL  ( i side frame -- bits )
    >R
    DUP R@ _NSF-BC + @ NBC-KIND NBC-DIRICHLET = IF
        R@ _NSF-BC + @ NBC-GHOST NARR-ADDR
        SWAP R@ _NSF-LB + @ * +
    ELSE
        NBC-LEFT = IF 0 ELSE R@ _NSF-NX + @ 1- THEN
        R@ _NSF-LB + @ *
        SWAP R@ _NSF-PITCH + @ * + R@ _NSF-U + @ +
    THEN
    R> _NST-LANE@ ;

\ Point the frame at row i, and build its neighbour rows.
: _NST-SET-ROWS  ( i frame -- )
    2DUP _NST-ROW-ADDR OVER _NSF-UROW + !
    2DUP SWAP OVER _NSF-PITCH + @ * SWAP _NSF-OUT + @ + OVER _NSF-OUTROW + !
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

: _NST-ROW  ( i frame xt -- )
    ROT 2 PICK _NST-SET-ROWS
    OVER _NSF-TPR + @ 64 * 0 ?DO
        I 2 PICK 2 PICK EXECUTE
    64 +LOOP
    2DROP ;

: _NST-SWEEP  ( frame xt -- )
    OVER _NSF-NY + @ 0 ?DO I 2 PICK 2 PICK _NST-ROW LOOP
    2DROP ;

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
    R@ _NSF-ROWS + DUP R@ _NSF-LROW + !
    R@ _NSF-PITCH + @ + R@ _NSF-RROW + !
    R@ _NSF-ROWS + DUP R@ _NSF-PITCH + @ 2 * + SWAP ?DO 0 I ! 8 +LOOP
    R> ;

\ =====================================================================
\  Public words
\ =====================================================================

\ out = L(u).
: NST-LAPLACE  ( u bc out ws -- status )
    3 PICK 3 PICK 3 PICK 3 PICK _NST-CHECK ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    3 PICK NARR-FMT TMODE!
    _NST-FRAME ['] _NST-TILE-LAPLACE _NST-SWEEP
    NUM-OK ;

\ out = RN(L(u) * c + u), where c is scalar bits in u's format.
: NST-UPDATE  ( c u bc out ws -- status )
    3 PICK 3 PICK 3 PICK 3 PICK _NST-CHECK ?DUP IF
        >R 2DROP 2DROP DROP R> EXIT
    THEN
    3 PICK NARR-FMT TMODE!
    _NST-FRAME
    SWAP OVER _NSF-FMT + @ NUM-SPLAT-CELL OVER _NSF-C + NUM-TILE-FILL
    -1 OVER _NSF-PRELOAD + !
    ['] _NST-TILE-UPDATE _NST-SWEEP
    NUM-OK ;
