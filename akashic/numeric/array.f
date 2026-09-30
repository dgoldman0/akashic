\ =====================================================================
\  numeric/array.f - Formats, arrays, and workspaces for numeric kernels
\ =====================================================================
\  The numeric package computes in IEEE binary32 (FP32) and binary64
\  (FP64) on the MegaPad tile engine.  A format is its TMODE element-width
\  code, so NUM-FP64 TMODE! selects it.
\
\  An array is caller storage described by a caller-owned descriptor:
\  base address, format, NX elements per row, and NY rows.  Each row is
\  padded to whole 64-byte tiles, so the row pitch is NX rounded up to
\  whole tiles.  The padding lanes belong to the array: element-wise
\  kernels compute them along with the real lanes, and reductions replace
\  them with the operation's identity.  A vector is an array with one row.
\  Storage is 64-byte aligned.
\
\  A workspace is caller scratch described the same way: an aligned
\  address and a byte count.  Kernels that need scratch say how much.
\
\  A scalar is a cell holding raw IEEE bits: all 64 bits for FP64, or the
\  low 32 bits for FP32.
\
\  Nothing here holds state.  Descriptors, storage, and workspaces all
\  belong to the caller, so every word may run on any core.
\
\  Prefix: NUM-   formats, status, tile helpers
\          NARR-  array descriptors
\          NWS-   workspace descriptors
\
\  Load with:   REQUIRE numeric/array.f
\ =====================================================================

PROVIDED akashic-numeric-array

REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Status codes
\ =====================================================================

0 CONSTANT NUM-OK
1 CONSTANT NUM-E-FORMAT      \ format is not FP32 or FP64
2 CONSTANT NUM-E-SHAPE       \ a dimension is invalid, or arrays differ
3 CONSTANT NUM-E-ALIGN       \ an address is not 64-byte aligned
4 CONSTANT NUM-E-SPACE       \ storage wraps, or a workspace is too small
5 CONSTANT NUM-E-RANGE       \ an argument is outside its allowed range
6 CONSTANT NUM-E-OVERLAP     \ an output or workspace overlaps an input
7 CONSTANT NUM-E-CONVERGE    \ a solver stopped before reaching its tolerance
8 CONSTANT NUM-E-SYNTAX      \ text is not a decimal number

\ =====================================================================
\  Formats
\ =====================================================================

6 CONSTANT NUM-FP32
7 CONSTANT NUM-FP64

64 CONSTANT NUM-TILE

0x8000000000000000 CONSTANT NUM-F64-NEG-ZERO
0x7FF8000000000000 CONSTANT NUM-F64-NAN          \ canonical quiet NaN
0x80000000         CONSTANT NUM-F32-NEG-ZERO
0x7FC00000         CONSTANT NUM-F32-NAN          \ canonical quiet NaN

: NUM-FORMAT?  ( fmt -- flag )
    DUP NUM-FP32 = SWAP NUM-FP64 = OR ;

: NUM-LANE-BYTES  ( fmt -- u )
    NUM-FP64 = IF 8 ELSE 4 THEN ;

: NUM-LANES  ( fmt -- u )
    NUM-FP64 = IF 8 ELSE 16 THEN ;

\ -0 is the exact identity of IEEE addition: x + -0 = x for every x.
: NUM-NEG-ZERO  ( fmt -- bits )
    NUM-FP64 = IF NUM-F64-NEG-ZERO ELSE NUM-F32-NEG-ZERO THEN ;

: NUM-NAN  ( fmt -- bits )
    NUM-FP64 = IF NUM-F64-NAN ELSE NUM-F32-NAN THEN ;

\ The cell whose eight copies put scalar bits in every lane of a tile.
: NUM-SPLAT-CELL  ( bits fmt -- cell )
    NUM-FP64 = IF EXIT THEN
    0xFFFFFFFF AND DUP 32 LSHIFT OR ;

\ Store cell into all eight cells of the aligned tile at addr.
: NUM-TILE-FILL  ( cell addr -- )
    OVER OVER !  OVER OVER 8 + !  OVER OVER 16 + !  OVER OVER 24 + !
    OVER OVER 32 + !  OVER OVER 40 + !  OVER OVER 48 + !  56 + ! ;

\ Tiles needed by one row of nx elements, or 0 when nx < 1.
: NUM-ROW-TILES  ( nx fmt -- tiles )
    OVER 1 < IF 2DROP 0 EXIT THEN
    NUM-LANES SWAP 1- SWAP / 1+ ;

\ =====================================================================
\  Array descriptors
\ =====================================================================

 0 CONSTANT _NARR-ADDR
 8 CONSTANT _NARR-FMT
16 CONSTANT _NARR-NX
24 CONSTANT _NARR-NY
32 CONSTANT NARR-SIZE

: NARR-ADDR  ( arr -- addr )  _NARR-ADDR + @ ;
: NARR-FMT   ( arr -- fmt )   _NARR-FMT + @ ;
: NARR-NX    ( arr -- nx )    _NARR-NX + @ ;
: NARR-NY    ( arr -- ny )    _NARR-NY + @ ;

-1 1 RSHIFT 64 / CONSTANT _NARR-MAX-TILES

\ Storage bytes for an nx-by-ny array, or 0 when the format or a
\ dimension is invalid, or the size cannot be a nonnegative cell.
: NARR-BYTES  ( nx ny fmt -- bytes|0 )
    DUP NUM-FORMAT? 0= IF DROP 2DROP 0 EXIT THEN
    ROT SWAP NUM-ROW-TILES                        ( ny row-tiles )
    OVER 1 < OVER 0= OR IF 2DROP 0 EXIT THEN
    _NARR-MAX-TILES 2 PICK / OVER < IF 2DROP 0 EXIT THEN
    * 64 * ;

\ Describe the caller storage at addr as an nx-by-ny array of fmt.  The
\ storage must be 64-byte aligned and NARR-BYTES long.
: NARR-INIT  ( addr nx ny fmt arr -- status )
    >R
    DUP NUM-FORMAT? 0= IF 2DROP 2DROP R> DROP NUM-E-FORMAT EXIT THEN
    3 PICK 63 AND IF 2DROP 2DROP R> DROP NUM-E-ALIGN EXIT THEN
    2 PICK 2 PICK 2 PICK NARR-BYTES               ( addr nx ny fmt bytes )
    ?DUP 0= IF 2DROP 2DROP R> DROP NUM-E-SHAPE EXIT THEN
    4 PICK SWAP MSPAN-NONWRAPPING? 0= IF
        2DROP 2DROP R> DROP NUM-E-SPACE EXIT
    THEN
    R@ _NARR-FMT + !  R@ _NARR-NY + !  R@ _NARR-NX + !  R> _NARR-ADDR + !
    NUM-OK ;

: NARR-ROW-TILES  ( arr -- tiles )
    DUP NARR-NX SWAP NARR-FMT NUM-ROW-TILES ;

: NARR-PITCH  ( arr -- bytes )
    NARR-ROW-TILES 64 * ;

: NARR-TILES  ( arr -- tiles )
    DUP NARR-ROW-TILES SWAP NARR-NY * ;

\ The whole storage span, padding included.
: NARR-STORAGE  ( arr -- addr bytes )
    DUP NARR-ADDR SWAP NARR-TILES 64 * ;

\ Same format and shape.
: NARR-SAME-SHAPE?  ( a b -- flag )
    OVER NARR-FMT OVER NARR-FMT =
    >R OVER NARR-NX OVER NARR-NX = R> AND
    >R NARR-NY SWAP NARR-NY = R> AND ;

\ =====================================================================
\  Workspace descriptors
\ =====================================================================

 0 CONSTANT _NWS-ADDR
 8 CONSTANT _NWS-BYTES
16 CONSTANT NWS-SIZE

: NWS-ADDR   ( ws -- addr )  _NWS-ADDR + @ ;
: NWS-BYTES  ( ws -- u )     _NWS-BYTES + @ ;

\ Describe bytes of caller scratch at the 64-byte aligned addr.
: NWS-INIT  ( addr bytes ws -- status )
    >R
    OVER 63 AND IF 2DROP R> DROP NUM-E-ALIGN EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP R> DROP NUM-E-SPACE EXIT THEN
    R@ _NWS-BYTES + !  R> _NWS-ADDR + !
    NUM-OK ;
