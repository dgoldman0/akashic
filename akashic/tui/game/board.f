\ =====================================================================
\  akashic/tui/game/board.f — A game map shown as a canonical text grid
\ =====================================================================
\
\  A board shows the part of a map that fits its region as one canonical
\  text grid (widgets/text-grid.f), each tile one item two cells wide.
\  The game supplies each tile's text and state through a token:
\
\      ( x y ctx -- text-a text-u state )
\
\  where state is 0, BOARD-CURRENT for the tile the player stands on, or
\  BOARD-UNAVAILABLE for a tile out of sight, which draws dim and
\  refuses selection.  A game names only BOARD- words; the collection
\  model stays the board's.  The board marks the cursor's tile as the
\  grid's primary item when that tile is available.  A pointer press, or
\  a rich terminal's PLACE on an item, selects the tile through the text
\  grid's ordinary selection, and the board calls the game's selection
\  token with the tile's map position:
\
\      ( x y ctx -- )
\
\  The board follows Grid's pattern of two banks: it builds the model in
\  the bank the widget does not hold and binds it with TGRID-BIND, which
\  validates it whole before the widget lets go of the other.  The banks
\  grow when a build runs out of room: the board measures the model,
\  grows both banks to a power of two that holds it, and builds again.
\
\  The model's root is the region, so the grid draws one cell for one
\  cell.  The window, the map's tiles the region holds, is as wide as
\  half the region's columns and as tall as its rows, and no larger than
\  the map; a window smaller than the region sits in its middle.  The
\  game chooses the window's origin, as a camera follows the player
\  (game/2d/camera.f), and the board keeps it on the map.  Item keys are
\  map positions, y * width + x + 1, so a tile keeps its key as the
\  window moves.
\
\  UIDL gives the widget its element's geometry each paint.  A game asks
\  BOARD-FITS? before a turn or on a tick, and rebuilds the board when
\  the region has changed size since the model was built.
\
\  Board Descriptor:
\    +0   next       The next live board
\    +8   widget     The text grid
\    +16  map-w      The map's size in tiles
\    +24  map-h
\    +32  x0         The window's origin, in tiles
\    +40  y0
\    +48  vw         The window's size, in tiles
\    +56  vh
\    +64  token      ( x y ctx -- text-a text-u state )
\    +72  select     ( x y ctx -- ), or 0
\    +80  ctx        The game's context for both tokens
\    +88  bank-a     The two banks
\    +96  bank-b
\    +104 bank-cap   Each bank's capacity
\    +112 active     The bound bank, or 0
\    +120 work       TGRID-BIND's work storage
\    +128 work-cap
\    +136 bound-h    The region's size when the model was built
\    +144 bound-w
\    +152 cursor     The cursor's tile as y * width + x, or -1
\    +160 builder    USCOL-BUILDER-SIZE bytes
\    +248 summary    USCOL-SUMMARY-SIZE bytes
\
\  Public API:
\    BOARD-NEW        ( row col h w map-w map-h -- board )
\    BOARD-FREE       ( board -- )
\    BOARD-TOKEN!     ( xt ctx board -- )
\    BOARD-ON-SELECT  ( xt board -- )
\    BOARD-WINDOW!    ( x0 y0 board -- )
\    BOARD-CURSOR!    ( x y board -- )
\    BOARD-REBUILD    ( board -- status )
\    BOARD-FITS?      ( board -- flag )
\    BOARD-VIEW       ( board -- vw vh )
\    BOARD-ORIGIN     ( board -- x0 y0 )
\    BOARD-WIDGET     ( board -- widget )
\    BOARD-CURRENT BOARD-UNAVAILABLE   ( -- state )
\
\  Statuses are the collection statuses (USCOL-S-*), and BOARD-S-NOMEM
\  when the banks cannot grow.
\
\  Prefix: BOARD- (public), _BOARD- / _BRD- (internal)
\  Provider: akashic-tui-game-board
\  Dependencies: text-grid.f, region.f, widget.f

PROVIDED akashic-tui-game-board

REQUIRE ../widgets/text-grid.f
REQUIRE ../region.f
REQUIRE ../widget.f

\ =====================================================================
\  §1 — Constants & Offsets
\ =====================================================================

100 CONSTANT BOARD-S-NOMEM

\ A tile's state, as the game's token answers it
USCOL-ITEM-CURRENT     CONSTANT BOARD-CURRENT      \ the player's tile
USCOL-ITEM-UNAVAILABLE CONSTANT BOARD-UNAVAILABLE  \ a tile out of sight

( kind: board-token xt( x y ctx -- text-a text-u state ) )
( kind: board-select xt( x y ctx -- ) )

2 CONSTANT _BOARD-CELL-W           \ cells a tile takes

0   CONSTANT _BOARD-O-NEXT
8   CONSTANT _BOARD-O-WIDGET
16  CONSTANT _BOARD-O-MAP-W
24  CONSTANT _BOARD-O-MAP-H
32  CONSTANT _BOARD-O-X0
40  CONSTANT _BOARD-O-Y0
48  CONSTANT _BOARD-O-VW
56  CONSTANT _BOARD-O-VH
64  CONSTANT _BOARD-O-TOKEN   ( holds: board-token )
72  CONSTANT _BOARD-O-SELECT  ( holds: board-select )
80  CONSTANT _BOARD-O-CTX
88  CONSTANT _BOARD-O-BANK-A
96  CONSTANT _BOARD-O-BANK-B
104 CONSTANT _BOARD-O-BANK-CAP
112 CONSTANT _BOARD-O-ACTIVE
120 CONSTANT _BOARD-O-WORK
128 CONSTANT _BOARD-O-WORK-CAP
136 CONSTANT _BOARD-O-BOUND-H
144 CONSTANT _BOARD-O-BOUND-W
152 CONSTANT _BOARD-O-CURSOR
160 CONSTANT _BOARD-O-BUILDER
_BOARD-O-BUILDER USCOL-BUILDER-SIZE + CONSTANT _BOARD-O-SUMMARY
_BOARD-O-SUMMARY USCOL-SUMMARY-SIZE + CONSTANT _BOARD-DESC-SZ

: _BOARD-WIDGET  ( board -- widget )  _BOARD-O-WIDGET + @ ;
: _BOARD-REGION  ( board -- rgn )  _BOARD-WIDGET WDG-REGION ;

\ =====================================================================
\  §2 — Live Boards
\ =====================================================================
\
\  The text grid's selection token receives the widget; the board finds
\  itself among the live boards by it.

VARIABLE _BOARD-LIST
0 _BOARD-LIST !

: _BOARD-OF  ( widget -- board|0 )
    _BOARD-LIST @
    BEGIN DUP WHILE
        2DUP _BOARD-WIDGET = IF NIP EXIT THEN
        _BOARD-O-NEXT + @
    REPEAT
    NIP ;

: _BOARD-UNLINK  ( board -- )
    _BOARD-LIST
    BEGIN DUP @ WHILE
        DUP @ 2 PICK = IF
            SWAP _BOARD-O-NEXT + @ SWAP ! EXIT
        THEN
        @ _BOARD-O-NEXT +
    REPEAT
    2DROP ;

\ The game's tile from a selected item
: _BOARD-SELECTED  ( item-key widget -- )
    _BOARD-OF ?DUP 0= IF DROP EXIT THEN          ( key board )
    DUP _BOARD-O-SELECT + @ 0= IF 2DROP EXIT THEN
    SWAP 1- OVER _BOARD-O-MAP-W + @ /MOD          ( board x y )
    ROT DUP _BOARD-O-CTX + @ SWAP _BOARD-O-SELECT + @ EXECUTE ;

\ =====================================================================
\  §3 — Constructor / Destructor & Settings
\ =====================================================================

: BOARD-NEW  ( row col h w map-w map-h -- board )
    _BOARD-DESC-SZ ALLOCATE 0<> ABORT" BOARD-NEW: alloc"   ( r c h w mw mh b )
    DUP _BOARD-DESC-SZ 0 FILL
    TUCK _BOARD-O-MAP-H + !  TUCK _BOARD-O-MAP-W + !       ( r c h w b )
    >R RGN-NEW TGRID-NEW R@ _BOARD-O-WIDGET + !
    ['] _BOARD-SELECTED R@ _BOARD-WIDGET TGRID-ON-SELECT
    -1 R@ _BOARD-O-CURSOR + !
    _BOARD-LIST @ R@ _BOARD-O-NEXT + !  R@ _BOARD-LIST !
    R> ;

: BOARD-FREE  ( board -- )
    DUP _BOARD-UNLINK
    DUP _BOARD-REGION SWAP DUP _BOARD-WIDGET TGRID-FREE SWAP RGN-FREE
    DUP _BOARD-O-WORK + @ FREE
    DUP _BOARD-O-BANK-B + @ FREE
    DUP _BOARD-O-BANK-A + @ FREE
    FREE ;

: BOARD-TOKEN!  ( xt ctx board -- )
    TUCK _BOARD-O-CTX + !  _BOARD-O-TOKEN + ! ;

: BOARD-ON-SELECT  ( xt board -- )  _BOARD-O-SELECT + ! ;

\ The window's origin; BOARD-REBUILD keeps the window on the map.
: BOARD-WINDOW!  ( x0 y0 board -- )
    TUCK _BOARD-O-Y0 + !  _BOARD-O-X0 + ! ;

\ The cursor's tile, or -1 -1 for none.  It is the grid's primary item
\ while it is in the window and available.
: BOARD-CURSOR!  ( x y board -- )
    >R DUP 0< IF 2DROP -1 R> _BOARD-O-CURSOR + ! EXIT THEN
    R@ _BOARD-O-MAP-W + @ * + R> _BOARD-O-CURSOR + ! ;

: BOARD-WIDGET  ( board -- widget )  _BOARD-WIDGET ;

: BOARD-VIEW  ( board -- vw vh )
    DUP _BOARD-O-VW + @ SWAP _BOARD-O-VH + @ ;

: BOARD-ORIGIN  ( board -- x0 y0 )
    DUP _BOARD-O-X0 + @ SWAP _BOARD-O-Y0 + @ ;

\ Does the bound model still have the region's size?
: BOARD-FITS?  ( board -- flag )
    DUP _BOARD-O-ACTIVE + @ 0= IF DROP FALSE EXIT THEN
    DUP _BOARD-REGION RGN-H OVER _BOARD-O-BOUND-H + @ =
    OVER _BOARD-REGION RGN-W ROT _BOARD-O-BOUND-W + @ = AND ;

\ =====================================================================
\  §4 — Building the Model
\ =====================================================================

VARIABLE _BRD-B          \ the board being built
VARIABLE _BRD-H          \ the region's size
VARIABLE _BRD-W
VARIABLE _BRD-TOP        \ where the window's first tile sits
VARIABLE _BRD-LEFT
VARIABLE _BRD-X
VARIABLE _BRD-Y

: _BRD@  ( offset -- n )  _BRD-B @ + @ ;
: _BRD!  ( n offset -- )  _BRD-B @ + ! ;
: _BRD-BUILDER  ( -- builder )  _BRD-B @ _BOARD-O-BUILDER + ;

\ The window that fits the region, kept on the map, and where it sits
: _BRD-LAYOUT  ( -- )
    _BRD-B @ _BOARD-REGION DUP RGN-H _BRD-H !  RGN-W _BRD-W !
    _BRD-W @ _BOARD-CELL-W / _BOARD-O-MAP-W _BRD@ MIN _BOARD-O-VW _BRD!
    _BRD-H @ _BOARD-O-MAP-H _BRD@ MIN _BOARD-O-VH _BRD!
    _BOARD-O-X0 _BRD@  _BOARD-O-MAP-W _BRD@ _BOARD-O-VW _BRD@ - MIN  0 MAX
        _BOARD-O-X0 _BRD!
    _BOARD-O-Y0 _BRD@  _BOARD-O-MAP-H _BRD@ _BOARD-O-VH _BRD@ - MIN  0 MAX
        _BOARD-O-Y0 _BRD!
    _BRD-H @ _BOARD-O-VH _BRD@ - 2/ _BRD-TOP !
    _BRD-W @ _BOARD-O-VW _BRD@ _BOARD-CELL-W * - 2/ _BRD-LEFT ! ;

\ The game's text and state for a tile
: _BRD-TILE  ( x y -- text-a text-u state )
    _BRD-B @ DUP _BOARD-O-CTX + @ SWAP _BOARD-O-TOKEN + @ EXECUTE ;

\ The primary item: the cursor's tile while it lies in the window and
\ the game shows it available, or 0
: _BRD-PRIMARY  ( -- key )
    _BOARD-O-CURSOR _BRD@ DUP 0< IF DROP 0 EXIT THEN
    _BOARD-O-MAP-W _BRD@ /MOD                       ( x y )
    OVER _BOARD-O-X0 _BRD@ - _BOARD-O-VW _BRD@ U< 0= IF 2DROP 0 EXIT THEN
    DUP _BOARD-O-Y0 _BRD@ - _BOARD-O-VH _BRD@ U< 0= IF 2DROP 0 EXIT THEN
    2DUP _BRD-TILE NIP NIP BOARD-UNAVAILABLE AND IF 2DROP 0 EXIT THEN
    _BOARD-O-MAP-W _BRD@ * + 1+ ;

\ One tile's item
: _BRD-ITEM  ( -- status )
    _BRD-Y @ _BOARD-O-MAP-W _BRD@ * _BRD-X @ + 1+   ( key )
    _BRD-Y @ _BOARD-O-Y0 _BRD@ - _BRD-TOP @ +       ( key row )
    _BRD-X @ _BOARD-O-X0 _BRD@ - _BOARD-CELL-W * _BRD-LEFT @ +
    1 _BOARD-CELL-W USCOL-ROLE-CONTENT              ( key row col rs cs role )
    _BRD-X @ _BRD-Y @ _BRD-TILE                     ( ... text-a text-u state )
    -ROT _BRD-BUILDER USCOL-TEXT-ITEM ;

\ The whole model, into the builder as it stands
: _BRD-BUILD  ( -- status )
    USCOL-F-TEXT-GRID 1 0 0 _BRD-H @ _BRD-W @
        USCOL-STATE-VISIBLE USCOL-STATE-ENABLED OR
        _BRD-BUILDER USCOL-TEXT-BEGIN
    ?DUP IF EXIT THEN
    USCOL-CONTENT-READ-ONLY _BRD-H @ _BRD-W @ 0 0 _BRD-H @ _BRD-W @
        _BRD-BUILDER USCOL-TEXT-SHAPE
    ?DUP IF EXIT THEN
    _BRD-PRIMARY 0 0 0 _BRD-BUILDER USCOL-TEXT-POSITIONS
    ?DUP IF EXIT THEN
    _BOARD-O-VH _BRD@ 0 ?DO
        _BOARD-O-Y0 _BRD@ I + _BRD-Y !
        _BOARD-O-VW _BRD@ 0 ?DO
            _BOARD-O-X0 _BRD@ I + _BRD-X !
            _BRD-ITEM ?DUP IF UNLOOP UNLOOP EXIT THEN
        LOOP
    LOOP
    _BRD-BUILDER USCOL-TEXT-END ;

\ Build into storage of a capacity: the model's bytes and a status
: _BRD-BUILD-INTO  ( dst cap -- bytes status )
    _BRD-BUILDER USCOL-BUILDER-INIT ?DUP IF 0 SWAP EXIT THEN
    _BRD-BUILD ?DUP IF 0 SWAP EXIT THEN
    _BRD-BUILDER USCOL-BUILDER-FINISH ;

\ The bank the widget does not hold
: _BRD-INACTIVE  ( -- bank )
    _BOARD-O-ACTIVE _BRD@ _BOARD-O-BANK-A _BRD@ = IF
        _BOARD-O-BANK-B _BRD@
    ELSE
        _BOARD-O-BANK-A _BRD@
    THEN ;

\ Bind a model built in a bank; the widget takes it whole or keeps its
\ last one.
: _BRD-BIND  ( bank bytes -- status )
    OVER SWAP
        _BOARD-O-WORK _BRD@ _BOARD-O-WORK-CAP _BRD@
        _BRD-B @ _BOARD-O-SUMMARY +
        _BOARD-O-WIDGET _BRD@ TGRID-BIND
    ?DUP IF NIP EXIT THEN
    _BOARD-O-ACTIVE _BRD!
    _BRD-H @ _BOARD-O-BOUND-H _BRD!
    _BRD-W @ _BOARD-O-BOUND-W _BRD!
    USCOL-S-OK ;

VARIABLE _BRD-NA         \ new banks and work while the board grows
VARIABLE _BRD-NB
VARIABLE _BRD-NW
VARIABLE _BRD-NCAP

: _BRD-FREE-NEW  ( -- )
    _BRD-NW @ FREE  _BRD-NB @ FREE  _BRD-NA @ FREE ;

\ Grow to banks that hold a model of n bytes, a power of two from 256,
\ build in one and bind it.  The bound bank stays bound until the new
\ model binds, and a failure leaves the board as it was.  TGRID-BIND's
\ work takes a cell an item, and an item takes 72 bytes at least, so a
\ cell for each eight bytes of a bank is room.
: _BRD-GROW-BIND  ( n -- status )
    256 BEGIN 2DUP > WHILE 2* REPEAT NIP _BRD-NCAP !
    0 _BRD-NA ! 0 _BRD-NB ! 0 _BRD-NW !
    _BRD-NCAP @ ALLOCATE IF DROP BOARD-S-NOMEM EXIT THEN _BRD-NA !
    _BRD-NCAP @ ALLOCATE IF DROP _BRD-FREE-NEW BOARD-S-NOMEM EXIT THEN
        _BRD-NB !
    _BRD-NCAP @ 8 / ALLOCATE IF DROP _BRD-FREE-NEW BOARD-S-NOMEM EXIT THEN
        _BRD-NW !
    _BRD-NA @ _BRD-NCAP @ _BRD-BUILD-INTO ?DUP IF
        NIP _BRD-FREE-NEW EXIT
    THEN                                            ( bytes )
    _BRD-NA @ SWAP OVER SWAP
        _BRD-NW @ _BRD-NCAP @ 8 /
        _BRD-B @ _BOARD-O-SUMMARY +
        _BOARD-O-WIDGET _BRD@ TGRID-BIND
    ?DUP IF NIP _BRD-FREE-NEW EXIT THEN             ( bank )
    _BOARD-O-WORK _BRD@ FREE
    _BOARD-O-BANK-B _BRD@ FREE
    _BOARD-O-BANK-A _BRD@ FREE
    _BRD-NA @ _BOARD-O-BANK-A _BRD!
    _BRD-NB @ _BOARD-O-BANK-B _BRD!
    _BRD-NW @ _BOARD-O-WORK _BRD!
    _BRD-NCAP @ DUP _BOARD-O-BANK-CAP _BRD!  8 / _BOARD-O-WORK-CAP _BRD!
    _BOARD-O-ACTIVE _BRD!
    _BRD-H @ _BOARD-O-BOUND-H _BRD!
    _BRD-W @ _BOARD-O-BOUND-W _BRD!
    USCOL-S-OK ;

\ BOARD-REBUILD ( board -- status )
\   Build the model for the region's size and the game's state, and bind
\   it.  The widget keeps its last model when a build fails.
: BOARD-REBUILD  ( board -- status )
    _BRD-B !
    _BOARD-O-TOKEN _BRD@ 0= IF USCOL-S-UNAVAILABLE EXIT THEN
    _BRD-LAYOUT
    _BRD-H @ 0= _BRD-W @ 0= OR IF USCOL-S-UNAVAILABLE EXIT THEN
    _BOARD-O-BANK-CAP _BRD@ IF
        _BRD-INACTIVE _BOARD-O-BANK-CAP _BRD@ _BRD-BUILD-INTO
    ELSE
        0 USCOL-S-CAPACITY
    THEN                                            ( bytes status )
    DUP USCOL-S-CAPACITY = IF
        2DROP 0 0 _BRD-BUILD-INTO ?DUP IF NIP EXIT THEN
        _BRD-GROW-BIND EXIT
    THEN
    ?DUP IF NIP EXIT THEN
    _BRD-INACTIVE SWAP _BRD-BIND ;

\ =====================================================================
\  §5 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _board-guard

' BOARD-NEW      CONSTANT _board-new-xt
' BOARD-FREE     CONSTANT _board-free-xt
' BOARD-REBUILD  CONSTANT _board-rebuild-xt

: BOARD-NEW      _board-new-xt      _board-guard WITH-GUARD ;
: BOARD-FREE     _board-free-xt     _board-guard WITH-GUARD ;
: BOARD-REBUILD  _board-rebuild-xt  _board-guard WITH-GUARD ;
[THEN] [THEN]
