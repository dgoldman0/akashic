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
\  The per-tile loops keep only the frame and a byte offset on the stack
\  and reach frame fields as literals, which the BIOS JIT folds into
\  single instructions.  Everything that is fixed for a row or a call is
\  worked out once, outside them.
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
\  The tile loops read the first seven fields; offsets below 128 fold
\  into one add.

  0 CONSTANT _NSF-UPROW      \ current row's upper neighbour
  8 CONSTANT _NSF-DOWNROW    \ current row's lower neighbour
 16 CONSTANT _NSF-UROW       \ current row, where the stencil reads it
 24 CONSTANT _NSF-OUTROW     \ where the current output row is computed
 32 CONSTANT _NSF-LROW       \ left-neighbour row
 40 CONSTANT _NSF-RROW       \ right-neighbour row
 48 CONSTANT _NSF-TPR        \ tiles per row
 56 CONSTANT _NSF-PREV       \ rows i-1, i, and i+1: ring rows when the
 64 CONSTANT _NSF-CUR        \ grid is staged, else the grid's own rows
 72 CONSTANT _NSF-NEXT
 80 CONSTANT _NSF-OUT        \ output row i
 88 CONSTANT _NSF-OBUF       \ staged output row; 0: output in place
 96 CONSTANT _NSF-GL         \ left ghost of row i; 0: zero flux
104 CONSTANT _NSF-GR         \ right ghost of row i; 0: zero flux
112 CONSTANT _NSF-GTOP       \ top ghost row; 0: zero flux
120 CONSTANT _NSF-GBOT       \ bottom ghost row; 0: zero flux
128 CONSTANT _NSF-U          \ grid base
136 CONSTANT _NSF-PITCH      \ bytes per row
144 CONSTANT _NSF-NY
152 CONSTANT _NSF-LB         \ bytes per lane
160 CONSTANT _NSF-SHIFT      \ bytes moved into a neighbour row: NX-1 lanes
168 CONSTANT _NSF-STAGED     \ nonzero: grid rows stream through the ring
176 CONSTANT _NSF-PRELOAD    \ nonzero: each output row starts as the grid row
184 CONSTANT _NSF-FMT
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
\  Tiles
\ =====================================================================

\ The Laplacian of tile k of the current row, into the tile at dst.
: _NST-L  ( frame k dst -- frame k )
    DUP TDST! >R
    OVER [ _NSF-UPROW ] LITERAL + @ OVER + TSRC0!
    OVER [ _NSF-DOWNROW ] LITERAL + @ OVER + TSRC1!  TADD
    R> TSRC0!
    OVER [ _NSF-LROW ] LITERAL + @ OVER + TSRC1!  TADD
    OVER [ _NSF-RROW ] LITERAL + @ OVER + TSRC1!  TADD
    OVER [ _NSF-UROW ] LITERAL + @ OVER + TSRC0!
    OVER [ _NSF-M4 ] LITERAL + TSRC1!  TFMA ;

\ The current output row = L(u).
: _NST-LAPLACE-TILES  ( frame -- )
    0 OVER [ _NSF-TPR ] LITERAL + @ 0 ?DO
        OVER [ _NSF-OUTROW ] LITERAL + @ OVER + _NST-L
        64 +
    LOOP
    2DROP ;

\ The current output row = RN(L * c + u); it already holds the grid row.
: _NST-UPDATE-TILES  ( frame -- )
    0 OVER [ _NSF-TPR ] LITERAL + @ 0 ?DO
        OVER [ _NSF-T ] LITERAL + _NST-L
        OVER [ _NSF-T ] LITERAL + TSRC0!
        OVER [ _NSF-C ] LITERAL + TSRC1!
        OVER [ _NSF-OUTROW ] LITERAL + @ OVER + TDST!  TFMA
        64 +
    LOOP
    2DROP ;

\ =====================================================================
\  Rows
\ =====================================================================
\  The row words keep the frame on the return stack, where R@ reaches it
\  in one instruction.

\ A lane's bits at addr; LB is 8 for FP64 and 4 for FP32.
: _NST-LANE@  ( addr frame -- bits )
    [ _NSF-LB ] LITERAL + @ 8 XOR IF L@ ELSE @ THEN ;

: _NST-LANE!  ( bits addr frame -- )
    [ _NSF-LB ] LITERAL + @ 8 XOR IF L! ELSE ! THEN ;

\ Workspace row n: 0 left, 1 right, 2 to 4 the ring, 5 the output.
: _NST-WS-ROW  ( n frame -- addr )
    DUP [ _NSF-PITCH ] LITERAL + @ ROT * + [ _NSF-ROWS ] LITERAL + ;

\ Copy grid row j into the ring row held in frame field f.
: _NST-STAGE  ( j f frame -- )
    >R R@ + @
    SWAP R@ [ _NSF-PITCH ] LITERAL + @ * R@ [ _NSF-U ] LITERAL + @ +
    SWAP R> [ _NSF-PITCH ] LITERAL + @ CMOVE ;

\ Row i's upper neighbour: row i-1, or at the top edge the Dirichlet
\ ghost row or, for zero flux, row i itself.
: _NST-UP  ( i frame -- addr )
    SWAP IF [ _NSF-PREV ] LITERAL + @ EXIT THEN
    DUP [ _NSF-GTOP ] LITERAL + @ ?DUP IF NIP EXIT THEN
    [ _NSF-UROW ] LITERAL + @ ;

\ Row i's lower neighbour, likewise.
: _NST-DOWN  ( i frame -- addr )
    >R R@ [ _NSF-NY ] LITERAL + @ 1 - XOR IF R> [ _NSF-NEXT ] LITERAL + @ EXIT THEN
    R@ [ _NSF-GBOT ] LITERAL + @ ?DUP IF R> DROP EXIT THEN
    R> [ _NSF-UROW ] LITERAL + @ ;

\ The ghost value beside the current row from the ghost pointer in frame
\ field g, which then moves on one lane; for a zero-flux side (pointer
\ 0), the current row's lane at byte offset.
: _NST-GHOST  ( frame g offset -- bits )
    ROT >R
    SWAP R@ + DUP @ ?DUP IF
        ROT DROP
        DUP R@ [ _NSF-LB ] LITERAL + @ + ROT !
    ELSE
        DROP R@ [ _NSF-UROW ] LITERAL + @ +
    THEN
    R> _NST-LANE@ ;

\ Build the current row's left and right neighbour rows.
: _NST-NEIGHBOURS  ( frame -- )
    >R
    \ left: ghost, then elements 0 .. NX-2
    R@ [ _NSF-GL ] LITERAL 0 _NST-GHOST
    R@ [ _NSF-LROW ] LITERAL + @ R@ _NST-LANE!
    R@ [ _NSF-UROW ] LITERAL + @
    R@ [ _NSF-LROW ] LITERAL + @ R@ [ _NSF-LB ] LITERAL + @ +
    R@ [ _NSF-SHIFT ] LITERAL + @ CMOVE
    \ right: elements 1 .. NX-1, then ghost
    R@ [ _NSF-UROW ] LITERAL + @ R@ [ _NSF-LB ] LITERAL + @ +
    R@ [ _NSF-RROW ] LITERAL + @
    R@ [ _NSF-SHIFT ] LITERAL + @ CMOVE
    R@ [ _NSF-GR ] LITERAL R@ [ _NSF-SHIFT ] LITERAL + @ _NST-GHOST
    R@ [ _NSF-RROW ] LITERAL + @ R@ [ _NSF-SHIFT ] LITERAL + @ +
    R> _NST-LANE! ;

\ Copy a staged output row out to the output, when there is one.
: _NST-PUT  ( frame -- )
    >R R@ [ _NSF-OBUF ] LITERAL + @ ?DUP IF
        R@ [ _NSF-OUT ] LITERAL + @ R@ [ _NSF-PITCH ] LITERAL + @ CMOVE
    THEN
    R> DROP ;

\ Move the frame on one row: the output row and the three row pointers.
\ A staged grid reuses the ring row of row i-1 for row i+2; a grid read
\ in place moves on to its next row.
: _NST-ADVANCE  ( frame -- )
    >R
    R@ [ _NSF-OUT ] LITERAL + DUP @ R@ [ _NSF-PITCH ] LITERAL + @ + SWAP !
    R@ [ _NSF-PREV ] LITERAL + @
    R@ [ _NSF-CUR ] LITERAL + @ R@ [ _NSF-PREV ] LITERAL + !
    R@ [ _NSF-NEXT ] LITERAL + @ R@ [ _NSF-CUR ] LITERAL + !
    R@ [ _NSF-STAGED ] LITERAL + @ IF ELSE
        DROP R@ [ _NSF-CUR ] LITERAL + @ R@ [ _NSF-PITCH ] LITERAL + @ +
    THEN
    R> [ _NSF-NEXT ] LITERAL + ! ;

\ Row i: stage the row below it, set the row pointers, build the
\ neighbour rows, run the tile loop xt, and put the output row.
: _NST-ROW  ( i frame xt -- )
    >R >R
    R@ [ _NSF-STAGED ] LITERAL + @ IF
        DUP 1 + DUP R@ [ _NSF-NY ] LITERAL + @ XOR IF
            [ _NSF-NEXT ] LITERAL R@ _NST-STAGE
        ELSE
            DROP
        THEN
    THEN
    R@ [ _NSF-CUR ] LITERAL + @ R@ [ _NSF-UROW ] LITERAL + !
    DUP R@ _NST-UP R@ [ _NSF-UPROW ] LITERAL + !
    R@ _NST-DOWN R@ [ _NSF-DOWNROW ] LITERAL + !
    R@ [ _NSF-OBUF ] LITERAL + @ ?DUP IF ELSE R@ [ _NSF-OUT ] LITERAL + @ THEN
    R@ [ _NSF-OUTROW ] LITERAL + !
    R@ _NST-NEIGHBOURS
    R@ [ _NSF-PRELOAD ] LITERAL + @ IF
        R@ [ _NSF-UROW ] LITERAL + @ R@ [ _NSF-OUTROW ] LITERAL + @
        R@ [ _NSF-PITCH ] LITERAL + @ CMOVE
    THEN
    R> R> OVER SWAP EXECUTE
    DUP _NST-PUT
    _NST-ADVANCE ;

\ Point the frame at row i0: its output row, ghost pointers, and row
\ pointers, staging rows i0-1 and i0 when the grid is staged.
: _NST-START  ( i0 frame -- )
    2DUP [ _NSF-PITCH ] LITERAL + @ * OVER [ _NSF-OUT ] LITERAL + +!
    2DUP [ _NSF-LB ] LITERAL + @ *
    OVER [ _NSF-GL ] LITERAL + DUP @ IF OVER SWAP +! ELSE DROP THEN
    OVER [ _NSF-GR ] LITERAL + DUP @ IF +! ELSE 2DROP THEN
    DUP [ _NSF-STAGED ] LITERAL + @ IF
        2 OVER _NST-WS-ROW OVER [ _NSF-PREV ] LITERAL + !
        3 OVER _NST-WS-ROW OVER [ _NSF-CUR ] LITERAL + !
        4 OVER _NST-WS-ROW OVER [ _NSF-NEXT ] LITERAL + !
        OVER IF OVER 1 - [ _NSF-PREV ] LITERAL 2 PICK _NST-STAGE THEN
        [ _NSF-CUR ] LITERAL SWAP _NST-STAGE
    ELSE
        TUCK [ _NSF-PITCH ] LITERAL + @ * OVER [ _NSF-U ] LITERAL + @ +
        2DUP SWAP [ _NSF-CUR ] LITERAL + !
        OVER [ _NSF-PITCH ] LITERAL + @ 2DUP - 3 PICK [ _NSF-PREV ] LITERAL + !
        + SWAP [ _NSF-NEXT ] LITERAL + !
    THEN ;

: _NST-SWEEP  ( frame xt i1 i0 -- )
    2DUP = IF 2DROP 2DROP EXIT THEN
    DUP 4 PICK _NST-START
    ?DO I 2 PICK 2 PICK _NST-ROW LOOP
    2DROP ;

\ =====================================================================
\  Frame
\ =====================================================================

\ Is the span wholly inside HBW?
: _NST-IN-HBW?  ( addr bytes -- flag )
    OVER + HBW-BASE HBW-SIZE + U> 0= SWAP HBW-BASE U< 0= AND ;

\ A side's Dirichlet ghost vector, or 0 for a zero-flux side.
: _NST-GHOST-BASE  ( side bc -- addr|0 )
    2DUP NBC-KIND NBC-DIRICHLET = IF NBC-GHOST NARR-ADDR ELSE 2DROP 0 THEN ;

\ Fill the frame for u, bc, and out in the workspace.  Lanes past NX
\ all lie in a row's last tile, so zeroing the last tiles of the
\ neighbour rows keeps those lanes +0 for the whole call.
: _NST-FRAME  ( u bc out ws -- frame )
    NWS-ADDR >R
    ROT
    DUP NARR-ADDR R@ [ _NSF-U ] LITERAL + !
    DUP NARR-PITCH R@ [ _NSF-PITCH ] LITERAL + !
    DUP NARR-ROW-TILES R@ [ _NSF-TPR ] LITERAL + !
    DUP NARR-NY R@ [ _NSF-NY ] LITERAL + !
    DUP NARR-FMT R@ [ _NSF-FMT ] LITERAL + !
    DUP NARR-FMT NUM-LANE-BYTES R@ [ _NSF-LB ] LITERAL + !
    DUP NARR-NX 1 - R@ [ _NSF-LB ] LITERAL + @ * R@ [ _NSF-SHIFT ] LITERAL + !
    NARR-STORAGE _NST-IN-HBW? 0= R@ [ _NSF-STAGED ] LITERAL + !
    DUP NARR-ADDR R@ [ _NSF-OUT ] LITERAL + !
    NARR-STORAGE _NST-IN-HBW? IF 0 ELSE 5 R@ _NST-WS-ROW THEN
    R@ [ _NSF-OBUF ] LITERAL + !
    NBC-TOP OVER _NST-GHOST-BASE R@ [ _NSF-GTOP ] LITERAL + !
    NBC-BOTTOM OVER _NST-GHOST-BASE R@ [ _NSF-GBOT ] LITERAL + !
    NBC-LEFT OVER _NST-GHOST-BASE R@ [ _NSF-GL ] LITERAL + !
    NBC-RIGHT SWAP _NST-GHOST-BASE R@ [ _NSF-GR ] LITERAL + !
    0 R@ _NST-WS-ROW R@ [ _NSF-LROW ] LITERAL + !
    1 R@ _NST-WS-ROW R@ [ _NSF-RROW ] LITERAL + !
    0 1 R@ _NST-WS-ROW 64 - NUM-TILE-FILL
    0 2 R@ _NST-WS-ROW 64 - NUM-TILE-FILL
    0 R@ [ _NSF-PRELOAD ] LITERAL + !
    R@ [ _NSF-FMT ] LITERAL + @ DUP NUM-FP64 = IF _NST-F64-M4 ELSE _NST-F32-M4 THEN
    SWAP NUM-SPLAT-CELL R@ [ _NSF-M4 ] LITERAL + NUM-TILE-FILL
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
    _NST-FRAME ['] _NST-LAPLACE-TILES R> R> SWAP _NST-SWEEP
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
    SWAP OVER [ _NSF-FMT ] LITERAL + @ NUM-SPLAT-CELL
    OVER [ _NSF-C ] LITERAL + NUM-TILE-FILL
    -1 OVER [ _NSF-PRELOAD ] LITERAL + !
    ['] _NST-UPDATE-TILES R> R> SWAP _NST-SWEEP
    NUM-OK ;

\ out = L(u).
: NST-LAPLACE  ( u bc out ws -- status )
    0 4 PICK NARR-NY NST-LAPLACE-ROWS ;

\ out = RN(L(u) * c + u).
: NST-UPDATE  ( c u bc out ws -- status )
    0 4 PICK NARR-NY NST-UPDATE-ROWS ;
