\ =====================================================================
\  akashic/tui/menu.f — Menu Bar & Dropdown Menus
\ =====================================================================
\
\  Horizontal menu bar with dropdown menus.  Each menu contains a
\  list of items with labels, action callbacks, and flags for
\  separators, disabled, and checked states.
\
\  Menu Item Descriptor (4 cells = 32 bytes):
\    +0   label-a    Label string address
\    +8   label-u    Label string length
\   +16   action-xt  Callback: ( -- ) invoked on selection
\   +24   flags      MNU-F-SEPARATOR | MNU-F-DISABLED | MNU-F-CHECKED
\
\  Each top-level menu entry (4 cells = 32 bytes):
\    +0   label-a    Menu title string address
\    +8   label-u    Menu title string length
\   +16   items-addr Address of item descriptor array
\   +24   item-count Number of items
\
\  Menu Descriptor (header + 5 cells = 80 bytes):
\    +0..+32  widget header  (type=WDG-T-MENU)
\   +40   menus       Address of top-level menu array
\   +48   menu-count  Number of top-level menus
\   +56   active-menu Currently open menu index (-1 = none)
\   +64   active-item Currently highlighted item in open menu
\   +72   bar-region  Region for the menu bar row
\
\  Prefix: MNU- (public), _MNU- (internal)
\  Provider: akashic-tui-menu
\  Dependencies: widget.f, draw.f, box.f, region.f

PROVIDED akashic-tui-menu

REQUIRE ../widget.f
REQUIRE ../draw.f
REQUIRE ../box.f
REQUIRE ../region.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _MNU-O-MENUS
48 CONSTANT _MNU-O-COUNT
56 CONSTANT _MNU-O-ACTIVE
64 CONSTANT _MNU-O-ITEM
72 CONSTANT _MNU-O-BAR-RGN

80 CONSTANT _MNU-DESC-SIZE

\ =====================================================================
\ 2. Item size / entry size / flag constants
\ =====================================================================

32 CONSTANT _MNU-ITEM-SIZE    \ per menu item: 4 cells
32 CONSTANT _MNU-ENTRY-SIZE   \ per top-level menu: 4 cells

1 CONSTANT MNU-F-SEPARATOR
2 CONSTANT MNU-F-DISABLED
4 CONSTANT MNU-F-CHECKED

\ =====================================================================
\ 3. Helpers — accessing top-level menus and items
\ =====================================================================

\ _MNU-ENTRY ( widget index -- entry-addr )
\   Address of top-level menu entry at index.
: _MNU-ENTRY  ( widget index -- entry-addr )
    _MNU-ENTRY-SIZE *
    SWAP _MNU-O-MENUS + @ + ;

\ _MNU-ENTRY-LABEL-A ( entry -- addr )
: _MNU-ENTRY-LABEL-A  ( entry -- addr )  @ ;

\ _MNU-ENTRY-LABEL-U ( entry -- u )
: _MNU-ENTRY-LABEL-U  ( entry -- u )  8 + @ ;

\ _MNU-ENTRY-ITEMS ( entry -- items-addr )
: _MNU-ENTRY-ITEMS  ( entry -- items-addr )  16 + @ ;

\ _MNU-ENTRY-ICOUNT ( entry -- count )
: _MNU-ENTRY-ICOUNT  ( entry -- count )  24 + @ ;

\ _MNU-ITEM-ADDR ( items-addr index -- item-addr )
: _MNU-ITEM-ADDR  ( items-addr index -- item-addr )
    _MNU-ITEM-SIZE * + ;

\ =====================================================================
\ 4. Internal — Draw
\ =====================================================================

VARIABLE _MNU-DRW-W       \ widget
VARIABLE _MNU-DRW-COL     \ current column during bar draw
VARIABLE _MNU-DRW-I       \ loop counter
VARIABLE _MNU-DRW-N       \ menu count
VARIABLE _MNU-DRW-ACT     \ active-menu index
VARIABLE _MNU-DRW-ENTRY   \ current entry addr
VARIABLE _MNU-DRW-RW      \ region width
VARIABLE _MNU-DRW-LBL-A   \ label addr
VARIABLE _MNU-DRW-LBL-U   \ label len

\ --- _MNU-BAR-COL ( widget index -- col )
\   Compute the starting column for top-level menu at index.
\   Each label is padded by 2 spaces on each side.

VARIABLE _MNU-BC-I
VARIABLE _MNU-BC-W
VARIABLE _MNU-BC-COL

: _MNU-BAR-COL  ( widget index -- col )
    _MNU-BC-I !
    _MNU-BC-W !
    0 _MNU-BC-COL !
    0 BEGIN
        DUP _MNU-BC-I @ <
    WHILE
        _MNU-BC-W @ OVER _MNU-ENTRY  \ ( i entry )
        _MNU-ENTRY-LABEL-U
        2 + 2 +                       \ " label " + 2 padding each side
        _MNU-BC-COL +!
        1+
    REPEAT
    DROP
    _MNU-BC-COL @ ;

\ --- Draw the menu bar at row 0 of the widget region ---

: _MNU-DRAW-BAR  ( -- )
    \ Clear bar row
    32 0 0 _MNU-DRW-RW @ DRW-HLINE
    0 _MNU-DRW-COL !
    0 _MNU-DRW-I !
    BEGIN
        _MNU-DRW-I @ _MNU-DRW-N @ <
    WHILE
        _MNU-DRW-W @ _MNU-DRW-I @ _MNU-ENTRY _MNU-DRW-ENTRY !
        _MNU-DRW-ENTRY @ _MNU-ENTRY-LABEL-A _MNU-DRW-LBL-A !
        _MNU-DRW-ENTRY @ _MNU-ENTRY-LABEL-U _MNU-DRW-LBL-U !
        \ If this is the active menu, reverse video
        _MNU-DRW-I @ _MNU-DRW-ACT @ = IF
            CELL-A-REVERSE DRW-ATTR!
        THEN
        \ Draw " label " with 1-space padding
        32 0 _MNU-DRW-COL @ DRW-CHAR
        _MNU-DRW-COL @ 1+ _MNU-DRW-COL !
        _MNU-DRW-LBL-A @ _MNU-DRW-LBL-U @
            0 _MNU-DRW-COL @ DRW-TEXT
        _MNU-DRW-LBL-U @ _MNU-DRW-COL +!
        32 0 _MNU-DRW-COL @ DRW-CHAR
        _MNU-DRW-COL @ 1+ _MNU-DRW-COL !
        \ Reset attrs after active
        _MNU-DRW-I @ _MNU-DRW-ACT @ = IF
            0 DRW-ATTR!
        THEN
        1 _MNU-DRW-I +!
    REPEAT ;

\ --- Draw a dropdown for the active menu ---

VARIABLE _MNU-DD-ENTRY    \ active menu entry addr
VARIABLE _MNU-DD-ITEMS    \ items array addr
VARIABLE _MNU-DD-ICNT     \ item count
VARIABLE _MNU-DD-COL      \ dropdown left column
VARIABLE _MNU-DD-MAXW     \ max item label width
VARIABLE _MNU-DD-I        \ item loop counter
VARIABLE _MNU-DD-ITEM     \ current item addr
VARIABLE _MNU-DD-FLAGS    \ current item flags
VARIABLE _MNU-DD-BW       \ box width
VARIABLE _MNU-DD-BH       \ box height

: _MNU-DROPDOWN-MAXW  ( -- )
    \ Find widest label among items
    0 _MNU-DD-MAXW !
    0 _MNU-DD-I !
    BEGIN
        _MNU-DD-I @ _MNU-DD-ICNT @ <
    WHILE
        _MNU-DD-ITEMS @ _MNU-DD-I @ _MNU-ITEM-ADDR _MNU-DD-ITEM !
        _MNU-DD-ITEM @ 24 + @    \ flags
        MNU-F-SEPARATOR AND 0= IF
            _MNU-DD-ITEM @ 8 + @ \ label-u
            _MNU-DD-MAXW @ MAX _MNU-DD-MAXW !
        THEN
        1 _MNU-DD-I +!
    REPEAT ;

: _MNU-DRAW-DROPDOWN  ( -- )
    _MNU-DRW-ACT @ 0< IF EXIT THEN   \ no open menu

    \ Resolve the active entry
    _MNU-DRW-W @ _MNU-DRW-ACT @ _MNU-ENTRY _MNU-DD-ENTRY !
    _MNU-DD-ENTRY @ _MNU-ENTRY-ITEMS _MNU-DD-ITEMS !
    _MNU-DD-ENTRY @ _MNU-ENTRY-ICOUNT _MNU-DD-ICNT !
    _MNU-DD-ICNT @ 0= IF EXIT THEN

    \ Column = bar column of active menu
    _MNU-DRW-W @ _MNU-DRW-ACT @ _MNU-BAR-COL _MNU-DD-COL !

    \ Find widest item
    _MNU-DROPDOWN-MAXW

    \ Box dimensions: width = maxw + 4 (borders + padding), height = count + 2
    _MNU-DD-MAXW @ 4 + _MNU-DD-BW !
    _MNU-DD-ICNT @ 2 + _MNU-DD-BH !

    \ Draw box at row 1 (below bar)
    BOX-SINGLE 1 _MNU-DD-COL @ _MNU-DD-BH @ _MNU-DD-BW @ BOX-DRAW

    \ Draw each item
    0 _MNU-DD-I !
    BEGIN
        _MNU-DD-I @ _MNU-DD-ICNT @ <
    WHILE
        _MNU-DD-ITEMS @ _MNU-DD-I @ _MNU-ITEM-ADDR _MNU-DD-ITEM !
        _MNU-DD-ITEM @ 24 + @ _MNU-DD-FLAGS !

        _MNU-DD-FLAGS @ MNU-F-SEPARATOR AND IF
            \ Separator: draw horizontal line inside box
            0x2500                       \ ─
            _MNU-DD-I @ 2 +              \ row (offset 2: 1 for bar + 1 for box top)
            _MNU-DD-COL @ 1+             \ col (inside box)
            _MNU-DD-BW @ 2 -             \ width (inside box)
            DRW-HLINE
        ELSE
            \ Set style: dimmed if disabled, reverse if active item
            _MNU-DD-FLAGS @ MNU-F-DISABLED AND IF
                CELL-A-DIM DRW-ATTR!
            ELSE
                _MNU-DD-I @ _MNU-DRW-W @ _MNU-O-ITEM + @ = IF
                    CELL-A-REVERSE DRW-ATTR!
                THEN
            THEN
            \ Clear the line inside box
            32
            _MNU-DD-I @ 2 +
            _MNU-DD-COL @ 1+
            _MNU-DD-BW @ 2 -
            DRW-HLINE
            \ Draw check mark if checked
            _MNU-DD-FLAGS @ MNU-F-CHECKED AND IF
                0x2713                   \ ✓
                _MNU-DD-I @ 2 +
                _MNU-DD-COL @ 1+
                DRW-CHAR
            THEN
            \ Draw label (offset by 2 inside box for padding/check)
            _MNU-DD-ITEM @ @ \ label-a
            _MNU-DD-ITEM @ 8 + @ \ label-u
            _MNU-DD-I @ 2 +
            _MNU-DD-COL @ 2 +
            DRW-TEXT
            \ Reset attrs
            0 DRW-ATTR!
        THEN
        1 _MNU-DD-I +!
    REPEAT ;

\ --- Main draw callback ---

: _MNU-DRAW  ( widget -- )
    _MNU-DRW-W !
    _MNU-DRW-W @ WDG-REGION RGN-W _MNU-DRW-RW !
    _MNU-DRW-W @ _MNU-O-COUNT + @ _MNU-DRW-N !
    _MNU-DRW-W @ _MNU-O-ACTIVE + @ _MNU-DRW-ACT !
    _MNU-DRAW-BAR
    _MNU-DRAW-DROPDOWN ;

\ =====================================================================
\ 5. Internal — Handle
\ =====================================================================

VARIABLE _MNU-HND-W       \ widget
VARIABLE _MNU-HND-EV      \ event address
VARIABLE _MNU-HND-TYPE    \ event type
VARIABLE _MNU-HND-CODE    \ event key code
VARIABLE _MNU-HND-AMENU   \ active menu
VARIABLE _MNU-HND-AITEM   \ active item
VARIABLE _MNU-HND-ICNT    \ item count in active menu
VARIABLE _MNU-HND-ENTRY   \ active entry addr

\ _MNU-ITEM-COUNT ( widget -- n )
\   Item count for the currently active menu.
: _MNU-ITEM-COUNT  ( widget -- n )
    DUP _MNU-O-ACTIVE + @ _MNU-ENTRY
    _MNU-ENTRY-ICOUNT ;

\ _MNU-SKIP-DISABLED-DOWN ( widget -- )
\   Advance active-item forward, skipping separators and disabled items.

VARIABLE _MNU-SD-W
VARIABLE _MNU-SD-ICNT
VARIABLE _MNU-SD-ITEMS

: _MNU-SKIP-DISABLED-DOWN  ( widget -- )
    _MNU-SD-W !
    _MNU-SD-W @ _MNU-SD-W @ _MNU-O-ACTIVE + @ _MNU-ENTRY
    DUP _MNU-ENTRY-ICOUNT _MNU-SD-ICNT !
    _MNU-ENTRY-ITEMS _MNU-SD-ITEMS !
    BEGIN
        _MNU-SD-W @ _MNU-O-ITEM + @ _MNU-SD-ICNT @ <
    WHILE
        _MNU-SD-ITEMS @ _MNU-SD-W @ _MNU-O-ITEM + @ _MNU-ITEM-ADDR
        24 + @   \ flags
        DUP MNU-F-SEPARATOR AND
        SWAP MNU-F-DISABLED AND OR IF
            1 _MNU-SD-W @ _MNU-O-ITEM + +!
        ELSE
            EXIT
        THEN
    REPEAT ;

\ _MNU-SKIP-DISABLED-UP ( widget -- )
\   Move active-item backward, skipping separators and disabled items.

VARIABLE _MNU-SU-W
VARIABLE _MNU-SU-ITEMS

: _MNU-SKIP-DISABLED-UP  ( widget -- )
    _MNU-SU-W !
    _MNU-SU-W @ _MNU-SU-W @ _MNU-O-ACTIVE + @ _MNU-ENTRY
    _MNU-ENTRY-ITEMS _MNU-SU-ITEMS !
    BEGIN
        _MNU-SU-W @ _MNU-O-ITEM + @ 0>
    WHILE
        _MNU-SU-ITEMS @ _MNU-SU-W @ _MNU-O-ITEM + @ _MNU-ITEM-ADDR
        24 + @   \ flags
        DUP MNU-F-SEPARATOR AND
        SWAP MNU-F-DISABLED AND OR IF
            -1 _MNU-SU-W @ _MNU-O-ITEM + +!
        ELSE
            EXIT
        THEN
    REPEAT ;

\ --- Handle key events ---

: _MNU-HANDLE  ( event widget -- consumed? )
    _MNU-HND-W !
    _MNU-HND-EV !
    _MNU-HND-EV @ @ _MNU-HND-TYPE !       \ event type field
    _MNU-HND-EV @ 8 + @ _MNU-HND-CODE !   \ event key-code field
    _MNU-HND-W @ _MNU-O-ACTIVE + @ _MNU-HND-AMENU !
    _MNU-HND-W @ _MNU-O-ITEM + @ _MNU-HND-AITEM !

    _MNU-HND-TYPE @ KEY-T-SPECIAL = IF
        _MNU-HND-CODE @ CASE
            KEY-LEFT OF
                _MNU-HND-AMENU @ 0< IF
                    \ No menu open — don't consume
                    0 EXIT
                THEN
                \ Move to previous menu
                _MNU-HND-AMENU @ 1- 0 MAX
                _MNU-HND-W @ _MNU-O-ACTIVE + !
                0 _MNU-HND-W @ _MNU-O-ITEM + !
                _MNU-HND-W @ _MNU-SKIP-DISABLED-DOWN
                _MNU-HND-W @ WDG-DIRTY
                -1 EXIT
            ENDOF
            KEY-RIGHT OF
                _MNU-HND-AMENU @ 0< IF
                    0 EXIT
                THEN
                \ Move to next menu
                _MNU-HND-AMENU @ 1+
                _MNU-HND-W @ _MNU-O-COUNT + @ 1- MIN
                _MNU-HND-W @ _MNU-O-ACTIVE + !
                0 _MNU-HND-W @ _MNU-O-ITEM + !
                _MNU-HND-W @ _MNU-SKIP-DISABLED-DOWN
                _MNU-HND-W @ WDG-DIRTY
                -1 EXIT
            ENDOF
            KEY-DOWN OF
                _MNU-HND-AMENU @ 0< IF
                    \ Open first menu
                    0 _MNU-HND-W @ _MNU-O-ACTIVE + !
                    0 _MNU-HND-W @ _MNU-O-ITEM + !
                    _MNU-HND-W @ _MNU-SKIP-DISABLED-DOWN
                    _MNU-HND-W @ WDG-DIRTY
                    -1 EXIT
                THEN
                \ Move to next item
                _MNU-HND-W @ _MNU-ITEM-COUNT _MNU-HND-ICNT !
                _MNU-HND-AITEM @ 1+
                _MNU-HND-ICNT @ 1- MIN
                _MNU-HND-W @ _MNU-O-ITEM + !
                _MNU-HND-W @ _MNU-SKIP-DISABLED-DOWN
                _MNU-HND-W @ WDG-DIRTY
                -1 EXIT
            ENDOF
            KEY-UP OF
                _MNU-HND-AMENU @ 0< IF
                    0 EXIT
                THEN
                _MNU-HND-AITEM @ 1-
                DUP 0< IF DROP 0 THEN
                _MNU-HND-W @ _MNU-O-ITEM + !
                _MNU-HND-W @ _MNU-SKIP-DISABLED-UP
                _MNU-HND-W @ WDG-DIRTY
                -1 EXIT
            ENDOF
            KEY-ENTER OF
                _MNU-HND-AMENU @ 0< IF
                    0 EXIT
                THEN
                \ Fire action of active item (if not separator/disabled)
                _MNU-HND-W @ _MNU-HND-W @ _MNU-O-ACTIVE + @ _MNU-ENTRY
                DUP _MNU-ENTRY-ITEMS
                SWAP _MNU-ENTRY-ICOUNT
                _MNU-HND-AITEM @ OVER < IF     \ index in range?
                    DROP
                    _MNU-HND-AITEM @ _MNU-ITEM-ADDR  \ ( item-addr )
                    DUP 24 + @                  \ flags
                    DUP MNU-F-SEPARATOR AND
                    SWAP MNU-F-DISABLED AND OR 0= IF
                        16 + @ EXECUTE          \ call action-xt
                    ELSE
                        DROP
                    THEN
                ELSE
                    2DROP
                THEN
                \ Close menu after action
                -1 _MNU-HND-W @ _MNU-O-ACTIVE + !
                _MNU-HND-W @ WDG-DIRTY
                -1 EXIT
            ENDOF
            KEY-ESC OF
                _MNU-HND-AMENU @ 0< IF
                    0 EXIT
                THEN
                -1 _MNU-HND-W @ _MNU-O-ACTIVE + !
                _MNU-HND-W @ WDG-DIRTY
                -1 EXIT
            ENDOF
        ENDCASE
    THEN
    0 ;

\ =====================================================================
\ 6. Constructor
\ =====================================================================

\ MNU-NEW ( rgn menus count -- widget )
\   Create a menu bar widget.
\   rgn should be tall enough for bar (row 0) + largest dropdown.
: MNU-NEW  ( rgn menus count -- widget )
    >R >R                              \ R: count menus ; ( rgn )
    _MNU-DESC-SIZE ALLOCATE
    0<> ABORT" MNU-NEW: alloc failed"  \ ( rgn addr )
    \ Fill header
    WDG-T-MENU    OVER _WDG-O-TYPE      + !
    SWAP          OVER _WDG-O-REGION    + !   \ rgn stored; ( addr )
    ['] _MNU-DRAW  OVER _WDG-O-DRAW-XT  + !
    ['] _MNU-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                  OVER _WDG-O-FLAGS     + !
    \ Fill menu fields
    R> OVER _MNU-O-MENUS  + !          \ menus addr
    R> OVER _MNU-O-COUNT  + !          \ menu count
    -1 OVER _MNU-O-ACTIVE + !          \ no menu open
    0  OVER _MNU-O-ITEM   + !          \ no active item
    DUP WDG-REGION
       OVER _MNU-O-BAR-RGN + ! ;      \ bar-region = widget region

\ =====================================================================
\ 7. Public API
\ =====================================================================

\ MNU-OPEN ( index widget -- )
\   Open dropdown for menu at index.
: MNU-OPEN  ( index widget -- )
    DUP >R
    _MNU-O-ACTIVE + !             \ store index at widget+56
    0 R@ _MNU-O-ITEM + !           \ reset active item
    R@ _MNU-SKIP-DISABLED-DOWN
    R> WDG-DIRTY ;

\ MNU-CLOSE ( widget -- )
\   Close any open dropdown.
: MNU-CLOSE  ( widget -- )
    -1 OVER _MNU-O-ACTIVE + !
    WDG-DIRTY ;

\ MNU-ACTIVE ( widget -- index )
\   Return currently active (open) menu index, or -1.
: MNU-ACTIVE  ( widget -- index )
    _MNU-O-ACTIVE + @ ;

\ MNU-ACTIVE-ITEM ( widget -- index )
\   Return currently highlighted item index.
: MNU-ACTIVE-ITEM  ( widget -- index )
    _MNU-O-ITEM + @ ;

\ MNU-ITEM-ENABLE ( widget menu# item# -- )
\   Enable a menu item (clear MNU-F-DISABLED).
: MNU-ITEM-ENABLE  ( widget menu# item# -- )
    >R                                  \ R: item# ; ( widget menu# )
    _MNU-ENTRY _MNU-ENTRY-ITEMS        \ ( items-addr )
    R> _MNU-ITEM-ADDR                  \ ( item-addr )
    DUP 24 + @                         \ ( item-addr flags )
    MNU-F-DISABLED INVERT AND
    SWAP 24 + ! ;

\ MNU-ITEM-DISABLE ( widget menu# item# -- )
\   Disable a menu item (set MNU-F-DISABLED).
: MNU-ITEM-DISABLE  ( widget menu# item# -- )
    >R                                  \ R: item# ; ( widget menu# )
    _MNU-ENTRY _MNU-ENTRY-ITEMS        \ ( items-addr )
    R> _MNU-ITEM-ADDR                  \ ( item-addr )
    DUP 24 + @
    MNU-F-DISABLED OR
    SWAP 24 + ! ;

\ MNU-ITEM-CHECK ( widget menu# item# flag -- )
\   Set or clear MNU-F-CHECKED on a menu item.

VARIABLE _MNU-IC-W
VARIABLE _MNU-IC-FLAG
VARIABLE _MNU-IC-ITEM2
VARIABLE _MNU-IC-MENU

: MNU-ITEM-CHECK  ( widget menu# item# flag -- )
    _MNU-IC-FLAG !
    _MNU-IC-ITEM2 !
    _MNU-IC-MENU !
    _MNU-IC-W !
    _MNU-IC-W @ _MNU-IC-MENU @ _MNU-ENTRY _MNU-ENTRY-ITEMS
    _MNU-IC-ITEM2 @ _MNU-ITEM-ADDR
    DUP 24 + @
    MNU-F-CHECKED INVERT AND
    _MNU-IC-FLAG @ IF MNU-F-CHECKED OR THEN
    SWAP 24 + ! ;

\ MNU-FREE ( widget -- )
\   Free the menu descriptor (does not free menus/items arrays).
: MNU-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\ 8. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _mnu-guard

' MNU-NEW          CONSTANT _mnu-new-xt
' MNU-OPEN         CONSTANT _mnu-open-xt
' MNU-CLOSE        CONSTANT _mnu-close-xt
' MNU-ACTIVE       CONSTANT _mnu-active-xt
' MNU-ACTIVE-ITEM  CONSTANT _mnu-activeitem-xt
' MNU-ITEM-ENABLE  CONSTANT _mnu-itemenable-xt
' MNU-ITEM-DISABLE CONSTANT _mnu-itemdisable-xt
' MNU-ITEM-CHECK   CONSTANT _mnu-itemcheck-xt
' MNU-FREE         CONSTANT _mnu-free-xt

: MNU-NEW          _mnu-new-xt        _mnu-guard WITH-GUARD ;
: MNU-OPEN         _mnu-open-xt       _mnu-guard WITH-GUARD ;
: MNU-CLOSE        _mnu-close-xt      _mnu-guard WITH-GUARD ;
: MNU-ACTIVE       _mnu-active-xt     _mnu-guard WITH-GUARD ;
: MNU-ACTIVE-ITEM  _mnu-activeitem-xt _mnu-guard WITH-GUARD ;
: MNU-ITEM-ENABLE  _mnu-itemenable-xt _mnu-guard WITH-GUARD ;
: MNU-ITEM-DISABLE _mnu-itemdisable-xt _mnu-guard WITH-GUARD ;
: MNU-ITEM-CHECK   _mnu-itemcheck-xt  _mnu-guard WITH-GUARD ;
: MNU-FREE         _mnu-free-xt       _mnu-guard WITH-GUARD ;
[THEN] [THEN]
