\ =====================================================================
\  numeric/blas1.f - Element-wise kernels and reductions on arrays
\ =====================================================================
\  Level-1 kernels over numeric arrays (numeric/array.f) in FP32 or FP64,
\  run on the calling core's tile engine.
\
\  Element-wise kernels work on whole tiles, so they also compute the
\  padding lanes of each row.  Arrays in one call must have the same
\  format and shape.  An output may be the same array as an input.
\
\  Reductions return binary64 bits in both formats, because the tile
\  engine accumulates FP32 and FP64 in binary64.  SUM, DOT, SUMSQ, and
\  ASUM have one defined order, so a result is the same bits however the
\  work is split:
\
\    1. The array's tiles are taken in row-major order.  In each row's
\       last tile, lanes past NX are replaced by the identity: -0 for SUM,
\       SUMSQ, and ASUM; for DOT, -0 in x and +0 in y, whose product is -0.
\    2. Each tile gives the tile engine's canonical tree result.
\    3. Runs of NUM-BLOCK-TILES consecutive tiles form blocks.  A block's
\       value chains its tile results in order, one rounding per add.
\    4. The result is the canonical pairwise tree over the block values,
\       padded with -0 to a power of two.
\
\  MAX and MIN are exact, so their order does not matter.  They skip NaN
\  lanes; padding lanes hold the canonical NaN, so they never win.
\
\  Each reduction is also available in two steps, so its blocks can be
\  split among cores: NV-BLOCK-VALUES computes a range of block values and
\  NV-COMBINE combines them all.
\
\  Kernels set TMODE and TCTRL and leave them set.  They hold no module
\  state: scratch comes from a caller workspace of NV-WS-BYTES bytes.
\
\  Prefix: NV-    public kernels
\          _NB1-  internal helpers
\          _NRF-  reduction frame, kept in the workspace
\
\  Load with:   REQUIRE numeric/blas1.f
\ =====================================================================

PROVIDED akashic-numeric-blas1

REQUIRE array.f

\ Tiles per reduction block.  It is part of the definition of every
\ SUM, DOT, SUMSQ, and ASUM result, so changing it changes the rounding.
32 CONSTANT NUM-BLOCK-TILES

\ =====================================================================
\  Checks
\ =====================================================================

: _NB1-FMT-OK?  ( arr -- flag )  NARR-FMT NUM-FORMAT? ;

\ x and y are in a valid format and have the same format and shape.
: NV-CHECK2  ( x y -- status )
    OVER _NB1-FMT-OK? 0= IF 2DROP NUM-E-FORMAT EXIT THEN
    NARR-SAME-SHAPE? IF NUM-OK ELSE NUM-E-SHAPE THEN ;

\ x, y, and z are in a valid format and have the same format and shape.
: NV-CHECK3  ( x y z -- status )
    2 PICK _NB1-FMT-OK? 0= IF 2DROP DROP NUM-E-FORMAT EXIT THEN
    >R OVER NARR-SAME-SHAPE? SWAP R> NARR-SAME-SHAPE? AND
    IF NUM-OK ELSE NUM-E-SHAPE THEN ;

\ =====================================================================
\  Element-wise kernels
\ =====================================================================

\ For each tile: TSRC0 = a+k, TSRC1 = b+k, TDST = c+k, then xt.
: _NB1-EACH3  ( a b c bytes xt -- )
    SWAP 0 ?DO
        3 PICK I + TSRC0!
        2 PICK I + TSRC1!
        OVER I + TDST!
        DUP EXECUTE
    64 +LOOP
    2DROP 2DROP ;

: _NB1-BINARY  ( x y z xt -- status )
    >R 2 PICK 2 PICK 2 PICK NV-CHECK3 ?DUP IF
        R> DROP >R 2DROP DROP R> EXIT
    THEN
    DUP NARR-FMT TMODE!
    DUP NARR-TILES 64 *
    >R >R >R NARR-ADDR R> NARR-ADDR R> NARR-ADDR R> R>
    _NB1-EACH3 NUM-OK ;

\ z = x + y, x - y, or x * y, one rounding per lane.
: NV-ADD  ( x y z -- status )  ['] TADD _NB1-BINARY ;
: NV-SUB  ( x y z -- status )  ['] TSUB _NB1-BINARY ;
: NV-MUL  ( x y z -- status )  ['] TMUL _NB1-BINARY ;

\ y = x, padding included.
: NV-COPY  ( x y -- status )
    2DUP NV-CHECK2 ?DUP IF >R 2DROP R> EXIT THEN
    SWAP NARR-STORAGE ROT NARR-ADDR SWAP CMOVE NUM-OK ;

\ Every lane of x, padding included, becomes the scalar bits.
: NV-FILL  ( bits x -- status )
    DUP _NB1-FMT-OK? 0= IF 2DROP NUM-E-FORMAT EXIT THEN
    DUP NARR-FMT ROT SWAP NUM-SPLAT-CELL
    SWAP NARR-STORAGE OVER + SWAP ?DO DUP I ! 8 +LOOP
    DROP NUM-OK ;

\ x = RN(x * a).
: NV-SCALE  ( bits x ws -- status )
    OVER _NB1-FMT-OK? 0= IF DROP 2DROP NUM-E-FORMAT EXIT THEN
    DUP NWS-BYTES 64 < IF DROP 2DROP NUM-E-SPACE EXIT THEN
    NWS-ADDR >R
    DUP NARR-FMT ROT OVER NUM-SPLAT-CELL R@ NUM-TILE-FILL TMODE!
    R> TSRC1!
    NARR-STORAGE OVER + SWAP ?DO I DUP TSRC0! TDST! TMUL 64 +LOOP
    NUM-OK ;

\ y = RN(x * a + y), fused: one rounding per lane.
: NV-AXPY  ( bits x y ws -- status )
    >R 2DUP NV-CHECK2 ?DUP IF R> DROP >R 2DROP DROP R> EXIT THEN
    R@ NWS-BYTES 64 < IF R> DROP 2DROP DROP NUM-E-SPACE EXIT THEN
    R> NWS-ADDR >R
    ROT 2 PICK NARR-FMT DUP TMODE! NUM-SPLAT-CELL R@ NUM-TILE-FILL
    R> TSRC1!
    SWAP NARR-ADDR SWAP NARR-STORAGE
    0 ?DO OVER I + TSRC0! DUP I + TDST! TFMA 64 +LOOP
    2DROP NUM-OK ;

\ =====================================================================
\  Reduction frame
\ =====================================================================
\  The first workspace tile holds the loop state, tiles 1 and 2 stage a
\  row's last partial tile, and the rest hold one value per block.

 0 CONSTANT _NRF-X          \ x base
 8 CONSTANT _NRF-Y          \ y base, when _NRF-PAIR is set
16 CONSTANT _NRF-TPR        \ tiles per row
24 CONSTANT _NRF-TAIL       \ real bytes in a row's last tile; 0 if full
32 CONSTANT _NRF-OP         \ tile reduction xt
40 CONSTANT _NRF-XPAD       \ cell pattern for x padding lanes
48 CONSTANT _NRF-YPAD       \ cell pattern for y padding lanes
56 CONSTANT _NRF-PAIR       \ nonzero when the reduction reads y

: _NRF-STAGE-X   ( frame -- addr )   64 + ;
: _NRF-STAGE-Y   ( frame -- addr )  128 + ;

\ Real bytes in each row's last tile, or 0 when rows fill their tiles.
: _NB1-TAIL-BYTES  ( arr -- bytes )
    DUP NARR-NX OVER NARR-FMT NUM-LANES MOD
    SWAP NARR-FMT NUM-LANE-BYTES * ;

\ Start a frame in the workspace for a one-array reduction of x.
: _NB1-FRAME  ( x ws -- frame )
    NWS-ADDR >R
    DUP NARR-ADDR R@ _NRF-X + !
    DUP NARR-ROW-TILES R@ _NRF-TPR + !
    _NB1-TAIL-BYTES R@ _NRF-TAIL + !
    0 R@ _NRF-PAIR + !
    R> ;

\ Is tile t the partial last tile of its row?
: _NRF-TAIL?  ( t frame -- flag )
    DUP _NRF-TAIL + @ 0= IF 2DROP 0 EXIT THEN
    _NRF-TPR + @ TUCK MOD SWAP 1- = ;

\ Copy count bytes from src into the aligned tile dst, whose other
\ lanes get the cell pattern.
: _NRF-STAGE  ( src dst cell count -- )
    >R OVER NUM-TILE-FILL R> CMOVE ;

\ Point the tile sources at tile t, staged when it is a partial row
\ tail, and run the frame's reduction on it.
: _NRF-TILE  ( t frame -- )
    2DUP _NRF-TAIL? IF
        OVER 64 * OVER _NRF-X + @ +
        OVER _NRF-STAGE-X 2 PICK _NRF-XPAD + @ 3 PICK _NRF-TAIL + @
        _NRF-STAGE
        DUP _NRF-STAGE-X TSRC0!
        DUP _NRF-PAIR + @ IF
            OVER 64 * OVER _NRF-Y + @ +
            OVER _NRF-STAGE-Y 2 PICK _NRF-YPAD + @ 3 PICK _NRF-TAIL + @
            _NRF-STAGE
            DUP _NRF-STAGE-Y TSRC1!
        THEN
    ELSE
        OVER 64 * OVER _NRF-X + @ + TSRC0!
        DUP _NRF-PAIR + @ IF OVER 64 * OVER _NRF-Y + @ + TSRC1! THEN
    THEN
    NIP _NRF-OP + @ EXECUTE ;

\ Chain the results of tiles t0 up to t1 in ACC0 and return it.
: _NRF-BLOCK  ( t1 t0 frame -- bits )
    3 TCTRL!
    -ROT ?DO I OVER _NRF-TILE LOOP
    DROP ACC@ ;

\ =====================================================================
\  Combining block values
\ =====================================================================

\ Fill values n and up with cell until n is a multiple of 8.
: _NUM-PAD  ( addr n cell -- )
    >R
    BEGIN DUP 7 AND WHILE
        2DUP 8 * + R@ SWAP !  1+
    REPEAT
    2DROP R> DROP ;

\ Replace n values with the trees of their groups of 8.  Value k is
\ written after group k has been read, so the update is in place.
: _NUM-TREE-LEVEL  ( addr n -- addr m )
    2DUP NUM-F64-NEG-ZERO _NUM-PAD
    7 + 3 RSHIFT
    DUP 0 ?DO
        2 TCTRL!
        OVER I 64 * + TSRC0! TSUM
        ACC@ 2 PICK I 8 * + !
    LOOP ;

\ The canonical pairwise tree over n binary64 values at the aligned
\ addr, which has room for n rounded up to a multiple of 8.  Padding
\ with -0 changes no value, so a tree of 8-value trees is the tree over
\ all n values padded to a power of two.  The values are overwritten.
: _NUM-TREE  ( addr n -- bits )
    NUM-FP64 TMODE!
    BEGIN DUP 1 > WHILE _NUM-TREE-LEVEL REPEAT
    DROP @ ;

\ The NaN-skipping extreme of n binary64 values at the aligned addr,
\ chained with the tile reduction xt (TMAX or TMIN).  Padding lanes hold
\ NaN, which the reduction skips.
: _NUM-EXTREME  ( addr n xt -- bits )
    NUM-FP64 TMODE!
    -ROT 2DUP NUM-F64-NAN _NUM-PAD
    7 + 3 RSHIFT
    3 TCTRL!
    0 ?DO DUP I 64 * + TSRC0! OVER EXECUTE LOOP
    2DROP ACC@ ;

\ =====================================================================
\  Reductions
\ =====================================================================
\  A reduction runs in two steps, so its blocks can be split among cores:
\  NV-BLOCK-VALUES computes the values of a range of blocks, and
\  NV-COMBINE combines all of them in the fixed order.

0 CONSTANT NV-OP-SUM
1 CONSTANT NV-OP-SUMSQ
2 CONSTANT NV-OP-ASUM
3 CONSTANT NV-OP-DOT
4 CONSTANT NV-OP-MAX
5 CONSTANT NV-OP-MIN

\ Workspace bytes NV-BLOCK-VALUES needs: the frame and two staging tiles.
192 CONSTANT NV-BLOCK-WS-BYTES

: _NB1-OP?  ( op -- flag )  0 6 WITHIN ;
: _NB1-EXTREME?  ( op -- flag )  NV-OP-MAX >= ;

: _NB1-OP-XT  ( op -- xt )
    DUP NV-OP-SUM = IF DROP ['] TSUM EXIT THEN
    DUP NV-OP-SUMSQ = IF DROP ['] TSUMSQ EXIT THEN
    DUP NV-OP-ASUM = IF DROP ['] TL1 EXIT THEN
    DUP NV-OP-DOT = IF DROP ['] TDOT EXIT THEN
    NV-OP-MAX = IF ['] TMAX ELSE ['] TMIN THEN ;

: _NB1-NEG-ZERO-PAD  ( x -- cell )
    NARR-FMT DUP NUM-NEG-ZERO SWAP NUM-SPLAT-CELL ;

: _NB1-NAN-PAD  ( x -- cell )
    NARR-FMT DUP NUM-NAN SWAP NUM-SPLAT-CELL ;

\ Blocks in a reduction of arr.
: NV-BLOCKS  ( arr -- n )
    NARR-TILES NUM-BLOCK-TILES 1- + NUM-BLOCK-TILES / ;

\ Where a workspace keeps block values for NV-COMBINE.
: NV-PARTIALS  ( ws -- addr )  NWS-ADDR NV-BLOCK-WS-BYTES + ;

\ Workspace bytes for a whole reduction of arr on one core: the frame,
\ the staging tiles, and one binary64 value per block, rounded up to
\ whole tiles.
: NV-WS-BYTES  ( arr -- bytes )
    NV-BLOCKS 7 + 3 RSHIFT 64 * NV-BLOCK-WS-BYTES + ;

\ Fill the frame in ws for op over x (and y for NV-OP-DOT) and set TMODE.
: _NB1-SETUP  ( x y op ws -- frame )
    3 PICK SWAP _NB1-FRAME
    3 PICK NARR-FMT TMODE!
    OVER _NB1-OP-XT OVER _NRF-OP + !
    OVER _NB1-EXTREME? IF 3 PICK _NB1-NAN-PAD ELSE 3 PICK _NB1-NEG-ZERO-PAD THEN
    OVER _NRF-XPAD + !
    SWAP NV-OP-DOT = IF
        SWAP NARR-ADDR OVER _NRF-Y + !
        -1 OVER _NRF-PAIR + !
        0 OVER _NRF-YPAD + !
    ELSE
        NIP
    THEN
    NIP ;

\ dst[b] = the value of block b, for b0 <= b < b1.
: _NRF-VALUES  ( dst tiles frame b1 b0 -- )
    ?DO
        OVER I 1+ NUM-BLOCK-TILES * MIN
        I NUM-BLOCK-TILES *
        2 PICK _NRF-BLOCK
        3 PICK I 8 * + !
    LOOP
    DROP 2DROP ;

: _NB1-DROP7  ( x1 x2 x3 x4 x5 x6 x7 -- )  2DROP 2DROP 2DROP DROP ;

\ The values of blocks b0 up to b1 of op over x (and y for NV-OP-DOT):
\ block b's binary64 bits go to dst + 8b.  The workspace needs
\ NV-BLOCK-WS-BYTES, and those bytes must not overlap the values written.
: NV-BLOCK-VALUES  ( x y op ws dst b0 b1 -- status )
    4 PICK _NB1-OP? 0= IF _NB1-DROP7 NUM-E-RANGE EXIT THEN
    6 PICK _NB1-FMT-OK? 0= IF _NB1-DROP7 NUM-E-FORMAT EXIT THEN
    4 PICK NV-OP-DOT = IF
        6 PICK 6 PICK NARR-SAME-SHAPE? 0= IF _NB1-DROP7 NUM-E-SHAPE EXIT THEN
    THEN
    3 PICK NWS-BYTES NV-BLOCK-WS-BYTES < IF _NB1-DROP7 NUM-E-SPACE EXIT THEN
    OVER 0< IF _NB1-DROP7 NUM-E-RANGE EXIT THEN
    2DUP > IF _NB1-DROP7 NUM-E-RANGE EXIT THEN
    DUP 7 PICK NV-BLOCKS > IF _NB1-DROP7 NUM-E-RANGE EXIT THEN
    2 PICK 2 PICK 8 * + OVER 3 PICK - 8 *
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP _NB1-DROP7 NUM-E-SPACE EXIT THEN
    5 PICK NWS-ADDR NV-BLOCK-WS-BYTES MSPAN-OVERLAP? IF
        _NB1-DROP7 NUM-E-OVERLAP EXIT
    THEN
    >R >R >R
    3 PICK NARR-TILES >R
    _NB1-SETUP
    R> R> -ROT SWAP R> R> SWAP
    _NRF-VALUES
    NUM-OK ;

\ Combine n block values of op kept at the workspace's NV-PARTIALS, in the
\ fixed order: the canonical pairwise tree for the sums, and the exact
\ NaN-skipping extreme for MAX and MIN.  The values are overwritten.
: NV-COMBINE  ( n op ws -- bits status )
    OVER _NB1-OP? 0= IF DROP 2DROP 0 NUM-E-RANGE EXIT THEN
    2 PICK 1 < IF DROP 2DROP 0 NUM-E-RANGE EXIT THEN
    DUP NWS-BYTES 3 PICK 7 + 3 RSHIFT 64 * NV-BLOCK-WS-BYTES + < IF
        DROP 2DROP 0 NUM-E-SPACE EXIT
    THEN
    NV-PARTIALS -ROT
    DUP _NB1-EXTREME? IF _NB1-OP-XT _NUM-EXTREME ELSE DROP _NUM-TREE THEN
    NUM-OK ;

\ A whole reduction on one core.
: _NB1-REDUCE  ( x y op ws -- bits status )
    3 PICK _NB1-FMT-OK? 0= IF 2DROP 2DROP 0 NUM-E-FORMAT EXIT THEN
    OVER NV-OP-DOT = IF
        3 PICK 3 PICK NARR-SAME-SHAPE? 0= IF 2DROP 2DROP 0 NUM-E-SHAPE EXIT THEN
    THEN
    DUP NWS-BYTES 4 PICK NV-WS-BYTES < IF 2DROP 2DROP 0 NUM-E-SPACE EXIT THEN
    OVER >R DUP >R
    DUP NV-PARTIALS 0 5 PICK NV-BLOCKS DUP >R
    NV-BLOCK-VALUES ?DUP IF R> R> R> 2DROP DROP 0 SWAP EXIT THEN
    R> R> R> SWAP NV-COMBINE ;

: NV-SUM    ( x ws -- bits status )  0 NV-OP-SUM ROT _NB1-REDUCE ;
: NV-SUMSQ  ( x ws -- bits status )  0 NV-OP-SUMSQ ROT _NB1-REDUCE ;

\ Sum of absolute values.
: NV-ASUM   ( x ws -- bits status )  0 NV-OP-ASUM ROT _NB1-REDUCE ;

\ Largest and smallest lanes, skipping NaN (-0 orders below +0).  An
\ array of NaNs gives the canonical binary64 NaN.
: NV-MAX    ( x ws -- bits status )  0 NV-OP-MAX ROT _NB1-REDUCE ;
: NV-MIN    ( x ws -- bits status )  0 NV-OP-MIN ROT _NB1-REDUCE ;

: NV-DOT    ( x y ws -- bits status )  NV-OP-DOT SWAP _NB1-REDUCE ;
