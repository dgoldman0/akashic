\ =====================================================================
\  akashic/tui/game/widgets/inventory.f — Grid-Based Inventory Widget
\ =====================================================================
\
\  A focusable grid of item slots.  The player navigates with arrow
\  keys and can select, use, or drop items using callbacks.  Supports
\  scrolling when the item count exceeds the visible grid.
\
\  Slot entry (32 bytes, 4 cells):
\    +0   icon-cp     Codepoint (0 = empty slot)
\    +8   icon-fg     Foreground colour
\    +16  name-a      Item name string address
\    +24  name-u      Item name string length
\
\  Descriptor (header + 14 cells = 152 bytes):
\    +0..+39  widget header  (type = WDG-T-INVENTORY)
\    +40   cols         Grid columns
\    +48   rows         Grid rows (visible)
\    +56   slots        Slot array address
\    +64   slot-max     Maximum number of slots
\    +72   slot-count   Current number of slots used
\    +80   cursor       Current cursor index (0-based)
\    +88   scroll-top   First visible row * cols
\    +96   on-select-xt Callback ( index widget -- ) or 0
\    +104  on-use-xt    Callback ( index widget -- ) or 0
\    +112  on-drop-xt   Callback ( index widget -- ) or 0
\    +120  qty-array    Optional quantity array (1 cell each) or 0
\    +128  show-qty     Flag: show quantity numbers
\    +136  title-a      Title string address
\    +144  title-u      Title string length
\
\  Public API:
\    INV-NEW          ( rgn cols rows max-slots -- widget )
\    INV-FREE         ( widget -- )
\    INV-ADD          ( cp fg name-a name-u widget -- index )
\    INV-REMOVE       ( index widget -- )
\    INV-QTY!         ( qty index widget -- )
\    INV-QTY@         ( index widget -- qty )
\    INV-TITLE!       ( addr len widget -- )
\    INV-ON-SELECT    ( xt widget -- )
\    INV-ON-USE       ( xt widget -- )
\    INV-ON-DROP      ( xt widget -- )
\    INV-SELECTED     ( widget -- index )
\    INV-COUNT        ( widget -- n )
\    INV-CLEAR        ( widget -- )
\
\  Prefix: INV- (public), _INV- (internal)
\  Provider: akashic-tui-game-widgets-inventory
\  Dependencies: widget.f, draw.f, box.f, keys.f

PROVIDED ak-tui-gw-inventory

REQUIRE ../../widget.f
REQUIRE ../../draw.f
REQUIRE ../../box.f
REQUIRE ../../keys.f

\ =====================================================================
\  §1 — Constants & Layout
\ =====================================================================

22 CONSTANT WDG-T-INVENTORY

\ Slot entry (32 bytes)
 0 CONSTANT _INV-SL-CP
 8 CONSTANT _INV-SL-FG
16 CONSTANT _INV-SL-NA
24 CONSTANT _INV-SL-NU
32 CONSTANT _INV-SL-SZ

\ Descriptor offsets
40  CONSTANT _INV-O-COLS
48  CONSTANT _INV-O-ROWS
56  CONSTANT _INV-O-SLOTS
64  CONSTANT _INV-O-SMAX
72  CONSTANT _INV-O-SCNT
80  CONSTANT _INV-O-CURSOR
88  CONSTANT _INV-O-SCROLL
96  CONSTANT _INV-O-SEL-XT
104 CONSTANT _INV-O-USE-XT
112 CONSTANT _INV-O-DROP-XT
120 CONSTANT _INV-O-QTY
128 CONSTANT _INV-O-SHOWQ
136 CONSTANT _INV-O-TITLE-A
144 CONSTANT _INV-O-TITLE-U
152 CONSTANT _INV-DESC-SZ

\ =====================================================================
\  §2 — Slot Helpers
\ =====================================================================

: _INV-SLOT  ( widget index -- addr )
    _INV-SL-SZ * SWAP _INV-O-SLOTS + @ + ;

\ =====================================================================
\  §3 — Public Slot Management
\ =====================================================================

VARIABLE _INV-A-CP  VARIABLE _INV-A-FG  VARIABLE _INV-A-NA  VARIABLE _INV-A-NU

: INV-ADD  ( cp fg name-a name-u widget -- index )
    >R
    _INV-A-NU !  _INV-A-NA !  _INV-A-FG !  _INV-A-CP !
    R@ _INV-O-SCNT + @ R@ _INV-O-SMAX + @ >= IF
        R> DROP -1 EXIT
    THEN
    R@ _INV-O-SCNT + @          ( new-index  R: widget )
    R@ OVER _INV-SLOT >R        ( new-index  R: widget slot-addr )
    _INV-A-CP @ R@ _INV-SL-CP + !
    _INV-A-FG @ R@ _INV-SL-FG + !
    _INV-A-NA @ R@ _INV-SL-NA + !
    _INV-A-NU @ R@ _INV-SL-NU + !
    R> DROP                      ( new-index  R: widget )
    R@ _INV-O-SCNT + DUP @ 1+ SWAP !
    R> WDG-DIRTY ;               ( new-index )

: INV-REMOVE  ( index widget -- )
    >R
    \ Clear the slot
    R@ OVER _INV-SLOT _INV-SL-SZ 0 FILL
    \ Clear quantity
    R@ _INV-O-QTY + @ SWAP CELLS + 0 SWAP !
    R> WDG-DIRTY ;

: INV-QTY!  ( qty index widget -- )
    _INV-O-QTY + @ SWAP CELLS + ! ;

: INV-QTY@  ( index widget -- qty )
    _INV-O-QTY + @ SWAP CELLS + @ ;

: INV-COUNT  ( widget -- n )
    _INV-O-SCNT + @ ;

: INV-SELECTED  ( widget -- index )
    _INV-O-CURSOR + @ ;

: INV-TITLE!  ( addr len widget -- )
    >R
    R@ _INV-O-TITLE-U + !
    R@ _INV-O-TITLE-A + !
    R> WDG-DIRTY ;

: INV-ON-SELECT  ( xt widget -- )  _INV-O-SEL-XT  + ! ;
: INV-ON-USE     ( xt widget -- )  _INV-O-USE-XT  + ! ;
: INV-ON-DROP    ( xt widget -- )  _INV-O-DROP-XT + ! ;

: INV-CLEAR  ( widget -- )
    DUP _INV-O-SLOTS + @
    OVER _INV-O-SMAX + @ _INV-SL-SZ * 0 FILL
    DUP _INV-O-QTY + @
    OVER _INV-O-SMAX + @ CELLS 0 FILL
    DUP _INV-O-SCNT + 0 SWAP !
    DUP _INV-O-CURSOR + 0 SWAP !
    DUP _INV-O-SCROLL + 0 SWAP !
    WDG-DIRTY ;

\ =====================================================================
\  §4 — Scroll Management
\ =====================================================================

VARIABLE _INV-EV-W   VARIABLE _INV-EV-CR   VARIABLE _INV-EV-SR

: _INV-ENSURE-VISIBLE  ( widget -- )
    DUP _INV-EV-W !
    DUP _INV-O-CURSOR + @
    SWAP _INV-O-COLS + @ / _INV-EV-CR !       \ cursor row
    _INV-EV-W @ _INV-O-SCROLL + @ _INV-EV-SR ! \ scroll row
    _INV-EV-CR @ _INV-EV-SR @ < IF             \ above visible
        _INV-EV-CR @ _INV-EV-W @ _INV-O-SCROLL + ! EXIT
    THEN
    _INV-EV-CR @ _INV-EV-SR @ _INV-EV-W @ _INV-O-ROWS + @ + >= IF
        _INV-EV-CR @ _INV-EV-W @ _INV-O-ROWS + @ - 1+
        0 MAX _INV-EV-W @ _INV-O-SCROLL + !
    THEN ;

\ =====================================================================
\  §5 — Drawing
\ =====================================================================

VARIABLE _INV-DW   VARIABLE _INV-RW   VARIABLE _INV-RH
VARIABLE _INV-CW   \ cell width per grid slot
VARIABLE _INV-SL   \ current slot address (avoids >R inside ?DO)

: _INV-DRAW  ( widget -- )
    _INV-DW !
    _INV-DW @ WDG-REGION RGN-W _INV-RW !
    _INV-DW @ WDG-REGION RGN-H _INV-RH !

    \ Box frame
    _INV-DW @ _INV-O-TITLE-U + @ 0> IF
        BOX-SINGLE
        _INV-DW @ _INV-O-TITLE-A + @
        _INV-DW @ _INV-O-TITLE-U + @
        0 0 _INV-RH @ _INV-RW @ BOX-DRAW-TITLED
    ELSE
        BOX-SINGLE 0 0 _INV-RH @ _INV-RW @ BOX-DRAW
    THEN

    \ Clear interior
    32 1 1 _INV-RH @ 2 - _INV-RW @ 2 - DRW-FILL-RECT

    \ Compute slot cell width
    _INV-RW @ 2 -
    _INV-DW @ _INV-O-COLS + @ /
    DUP 3 < IF DROP 3 THEN
    _INV-CW !

    \ Draw grid
    _INV-DW @ _INV-O-SCROLL + @            ( scroll-row )
    _INV-DW @ _INV-O-ROWS + @ 0 ?DO        ( scroll-row )
        I OVER +                            ( scroll-row vis-row )
        DUP _INV-DW @ _INV-O-COLS + @ *    ( scroll-row vis-row first-idx )
        _INV-DW @ _INV-O-COLS + @ 0 ?DO
            DUP _INV-DW @ _INV-O-SCNT + @ < IF
                \ This slot exists
                DUP _INV-DW @ _INV-O-CURSOR + @ = IF
                    CELL-A-REVERSE DRW-ATTR!
                THEN
                DUP _INV-DW @ SWAP _INV-SLOT _INV-SL !
                \ Icon
                _INV-SL @ _INV-SL-CP + @ 0<> IF
                    _INV-SL @ _INV-SL-FG + @ DRW-FG!
                    _INV-SL @ _INV-SL-CP + @
                    J 1+   I _INV-CW @ * 1+
                    DRW-CHAR
                THEN
                \ Name (after icon)
                _INV-SL @ _INV-SL-NA + @ _INV-SL @ _INV-SL-NU + @
                _INV-CW @ 2 - MIN            ( truncate )
                J 1+   I _INV-CW @ * 2 +
                DRW-TEXT
                DRW-STYLE-RESTORE
            THEN
            1+
        LOOP
        DROP DROP
    LOOP
    DROP ;

\ =====================================================================
\  §6 — Event Handler
\ =====================================================================

VARIABLE _INV-HW

: _INV-FIRE-SELECT  ( widget -- )
    DUP _INV-O-SEL-XT + @ ?DUP IF
        OVER _INV-O-CURSOR + @
        2 PICK ROT EXECUTE
    THEN
    DROP ;

: _INV-MOVE-CURSOR  ( new-idx widget -- )
    >R
    DUP 0 < IF DROP R> DROP EXIT THEN
    DUP R@ _INV-O-SCNT + @ >= IF DROP R> DROP EXIT THEN
    R@ _INV-O-CURSOR + !
    R@ _INV-ENSURE-VISIBLE
    R@ _INV-FIRE-SELECT
    R> WDG-DIRTY ;

: _INV-HANDLE  ( event widget -- consumed? )
    _INV-HW !
    DUP @ KEY-T-SPECIAL = IF
        8 + @ CASE
            KEY-LEFT OF
                _INV-HW @ _INV-O-CURSOR + @ 1-
                _INV-HW @ _INV-MOVE-CURSOR
                -1 EXIT
            ENDOF
            KEY-RIGHT OF
                _INV-HW @ _INV-O-CURSOR + @ 1+
                _INV-HW @ _INV-MOVE-CURSOR
                -1 EXIT
            ENDOF
            KEY-UP OF
                _INV-HW @ _INV-O-CURSOR + @
                _INV-HW @ _INV-O-COLS + @ -
                _INV-HW @ _INV-MOVE-CURSOR
                -1 EXIT
            ENDOF
            KEY-DOWN OF
                _INV-HW @ _INV-O-CURSOR + @
                _INV-HW @ _INV-O-COLS + @ +
                _INV-HW @ _INV-MOVE-CURSOR
                -1 EXIT
            ENDOF
            KEY-ENTER OF
                _INV-HW @ _INV-O-USE-XT + @ ?DUP IF
                    _INV-HW @ _INV-O-CURSOR + @
                    _INV-HW @ ROT EXECUTE
                THEN
                -1 EXIT
            ENDOF
        ENDCASE
    THEN
    DUP @ KEY-T-CHAR = IF
        8 + @ CASE
            100 OF   \ 'd' = drop
                _INV-HW @ _INV-O-DROP-XT + @ ?DUP IF
                    _INV-HW @ _INV-O-CURSOR + @
                    _INV-HW @ ROT EXECUTE
                THEN
                -1 EXIT
            ENDOF
        ENDCASE
    THEN
    DROP 0 ;

\ =====================================================================
\  §7 — Constructor / Destructor
\ =====================================================================

VARIABLE _INV-N-RGN  VARIABLE _INV-N-COLS  VARIABLE _INV-N-ROWS
VARIABLE _INV-N-MAX

: INV-NEW  ( rgn cols rows max-slots -- widget )
    _INV-N-MAX !  _INV-N-ROWS !  _INV-N-COLS !  _INV-N-RGN !

    _INV-DESC-SZ ALLOCATE
    0<> ABORT" INV-NEW: alloc"

    WDG-T-INVENTORY    OVER _WDG-O-TYPE       + !
    _INV-N-RGN @       OVER _WDG-O-REGION     + !
    ['] _INV-DRAW      OVER _WDG-O-DRAW-XT    + !
    ['] _INV-HANDLE    OVER _WDG-O-HANDLE-XT  + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                       OVER _WDG-O-FLAGS      + !
    _INV-N-COLS @      OVER _INV-O-COLS       + !
    _INV-N-ROWS @      OVER _INV-O-ROWS       + !
    0                  OVER _INV-O-SCNT       + !
    0                  OVER _INV-O-CURSOR     + !
    0                  OVER _INV-O-SCROLL     + !
    0                  OVER _INV-O-SEL-XT     + !
    0                  OVER _INV-O-USE-XT     + !
    0                  OVER _INV-O-DROP-XT    + !
    0                  OVER _INV-O-SHOWQ      + !
    0                  OVER _INV-O-TITLE-A    + !
    0                  OVER _INV-O-TITLE-U    + !
    _INV-N-MAX @       OVER _INV-O-SMAX       + !

    \ Allocate slot array
    _INV-N-MAX @ _INV-SL-SZ * ALLOCATE
    0<> ABORT" INV-NEW: slots"
    DUP _INV-N-MAX @ _INV-SL-SZ * 0 FILL
    OVER _INV-O-SLOTS + !

    \ Allocate quantity array
    _INV-N-MAX @ CELLS ALLOCATE
    0<> ABORT" INV-NEW: qty"
    DUP _INV-N-MAX @ CELLS 0 FILL
    OVER _INV-O-QTY + ! ;

: INV-FREE  ( widget -- )
    DUP _INV-O-SLOTS + @ FREE
    DUP _INV-O-QTY   + @ FREE
    FREE ;

\ =====================================================================
\  §8 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../../concurrency/guard.f
GUARD _inv-guard

' INV-NEW         CONSTANT _inv-new-xt
' INV-FREE        CONSTANT _inv-free-xt
' INV-ADD         CONSTANT _inv-add-xt
' INV-REMOVE      CONSTANT _inv-remove-xt
' INV-QTY!        CONSTANT _inv-qty-set-xt
' INV-ON-SELECT   CONSTANT _inv-onsel-xt
' INV-ON-USE      CONSTANT _inv-onuse-xt
' INV-ON-DROP     CONSTANT _inv-ondrop-xt
' INV-CLEAR       CONSTANT _inv-clear-xt

: INV-NEW         _inv-new-xt       _inv-guard WITH-GUARD ;
: INV-FREE        _inv-free-xt      _inv-guard WITH-GUARD ;
: INV-ADD         _inv-add-xt       _inv-guard WITH-GUARD ;
: INV-REMOVE      _inv-remove-xt    _inv-guard WITH-GUARD ;
: INV-QTY!        _inv-qty-set-xt   _inv-guard WITH-GUARD ;
: INV-ON-SELECT   _inv-onsel-xt     _inv-guard WITH-GUARD ;
: INV-ON-USE      _inv-onuse-xt     _inv-guard WITH-GUARD ;
: INV-ON-DROP     _inv-ondrop-xt    _inv-guard WITH-GUARD ;
: INV-CLEAR       _inv-clear-xt     _inv-guard WITH-GUARD ;
[THEN] [THEN]
