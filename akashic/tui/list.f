\ =====================================================================
\  akashic/tui/list.f — Scrollable List Widget
\ =====================================================================
\
\  A vertically scrollable list of selectable items.  Supports:
\    - Keyboard navigation (up/down, page-up/page-down)
\    - Selection highlight (reverse video on selected item)
\    - Selection-changed callback
\    - Programmatic selection and item replacement
\    - Scroll auto-adjustment to keep selection visible
\
\  Items are an external array of ( addr len ) pairs — 2 cells per
\  item.  The widget does not copy strings; the caller owns the data.
\
\  List Descriptor (header + 6 cells = 88 bytes):
\    +0..+32  widget header   type=WDG-T-LIST
\    +40      items           Address of item array (each: addr+len)
\    +48      count           Number of items
\    +56      selected        Currently selected index (0-based, -1 = none)
\    +64      scroll-top      Index of first visible item
\    +72      select-xt       Selection callback ( index widget -- ) or 0
\    +80      item-xt         Custom render callback ( index widget -- ) or 0
\
\  Prefix: LST- (public), _LST- (internal)
\  Provider: akashic-tui-list
\  Dependencies: widget.f, draw.f, keys.f

PROVIDED akashic-tui-list

REQUIRE widget.f
REQUIRE draw.f
REQUIRE keys.f

\ =====================================================================
\ 1. Descriptor layout
\ =====================================================================

40 CONSTANT _LST-O-ITEMS
48 CONSTANT _LST-O-COUNT
56 CONSTANT _LST-O-SEL
64 CONSTANT _LST-O-SCROLL
72 CONSTANT _LST-O-SEL-XT
80 CONSTANT _LST-O-ITEM-XT

88 CONSTANT _LST-DESC-SIZE

\ =====================================================================
\ 2. Internal helpers
\ =====================================================================

\ _LST-ITEM-ADDR ( items index -- addr len )
\   Fetch address+length of item at given index.
\   Items array is 2 cells per entry (addr, len).
: _LST-ITEM-ADDR  ( items index -- addr len )
    8 * 2 * +                              \ items + index * 16
    DUP @ SWAP 8 + @ ;

\ _LST-ENSURE-VISIBLE ( widget -- )
\   Adjust scroll-top so selected item is visible.
: _LST-ENSURE-VISIBLE  ( widget -- )
    DUP _LST-O-SEL + @ DUP 0 < IF 2DROP EXIT THEN  \ no selection
    SWAP DUP >R
    _LST-O-SCROLL + @                      \ ( sel scroll  R: widget )
    \ If sel < scroll → scroll = sel
    2DUP > IF
        DROP R> _LST-O-SCROLL + ! EXIT
    THEN
    \ If sel >= scroll + height → scroll = sel - height + 1
    R@ WDG-REGION RGN-H                   \ ( sel scroll height )
    OVER +                                  \ ( sel scroll scroll+height )
    2 PICK SWAP >= IF                       \ sel < scroll+height → visible
        2DROP R> DROP EXIT
    THEN
    \ sel >= scroll+height
    DROP                                    \ drop scroll
    R@ WDG-REGION RGN-H - 1+              \ new scroll = sel - height + 1
    DUP 0 < IF DROP 0 THEN                 \ clamp to 0
    R> _LST-O-SCROLL + ! ;

\ =====================================================================
\ 3. Internal draw
\ =====================================================================

\ _LST-DRAW ( widget -- )
\   Draw visible items in the region.
: _LST-DRAW  ( widget -- )
    DUP WDG-REGION RGN-W                  \ ( widget rgnw )
    OVER WDG-REGION RGN-H                 \ ( widget rgnw rgnh )
    \ Clear entire region
    32 0 0 2 PICK 3 PICK DRW-FILL-RECT
    \ Loop visible rows
    OVER _LST-O-SCROLL + @                \ ( widget rgnw rgnh scroll )
    OVER 0 ?DO
        \ row i: item index = scroll + i
        DUP I +                             \ ( widget rgnw rgnh scroll itemidx )
        DUP 4 PICK _LST-O-COUNT + @ >= IF
            DROP LEAVE                      \ past end of items
        THEN
        \ Check if this item is selected
        DUP 4 PICK _LST-O-SEL + @ = IF
            CELL-A-REVERSE DRW-ATTR!
        THEN
        \ Check for custom renderer
        4 PICK _LST-O-ITEM-XT + @ DUP 0<> IF
            \ Custom: ( index widget -- )
            OVER 5 PICK SWAP EXECUTE
        ELSE
            DROP
            \ Default: draw item text at row I
            4 PICK _LST-O-ITEMS + @        \ items array
            OVER _LST-ITEM-ADDR            \ ( ... itemidx addr len )
            I 0 DRW-TEXT
        THEN
        \ Reset attr if was selected
        DUP 4 PICK _LST-O-SEL + @ = IF
            0 DRW-ATTR!
        THEN
        DROP                                \ drop itemidx
    LOOP
    DROP 2DROP ;

\ =====================================================================
\ 4. Internal handle
\ =====================================================================

\ _LST-SELECT! ( index widget -- )
\   Set selection, ensure visible, fire callback, mark dirty.
: _LST-SELECT!  ( index widget -- )
    2DUP _LST-O-SEL + !                   \ store selection
    DUP _LST-ENSURE-VISIBLE
    DUP _LST-O-SEL-XT + @ DUP 0<> IF
        >R 2DUP R> EXECUTE                 \ callback ( index widget -- )
    ELSE
        DROP
    THEN
    NIP WDG-DIRTY ;

VARIABLE _LST-HND-W   \ widget saved during handle

\ _LST-HANDLE ( event widget -- consumed? )
: _LST-HANDLE  ( event widget -- consumed? )
    _LST-HND-W !
    DUP @ KEY-T-SPECIAL = IF
        8 + @                               \ key code
        CASE
            KEY-UP OF
                _LST-HND-W @ _LST-O-SEL + @ DUP 0 > IF
                    1- _LST-HND-W @ _LST-SELECT!
                ELSE
                    DROP
                THEN
                -1
            ENDOF
            KEY-DOWN OF
                _LST-HND-W @ _LST-O-SEL + @
                _LST-HND-W @ _LST-O-COUNT + @ 1- < IF
                    _LST-HND-W @ _LST-O-SEL + @ 1+
                    _LST-HND-W @ _LST-SELECT!
                THEN
                -1
            ENDOF
            KEY-PGUP OF
                _LST-HND-W @ _LST-O-SEL + @
                _LST-HND-W @ WDG-REGION RGN-H -
                0 MAX
                _LST-HND-W @ _LST-SELECT!
                -1
            ENDOF
            KEY-PGDN OF
                _LST-HND-W @ _LST-O-SEL + @
                _LST-HND-W @ WDG-REGION RGN-H +
                _LST-HND-W @ _LST-O-COUNT + @ 1- MIN
                _LST-HND-W @ _LST-SELECT!
                -1
            ENDOF
            KEY-HOME OF
                0 _LST-HND-W @ _LST-SELECT!
                -1
            ENDOF
            KEY-END OF
                _LST-HND-W @ _LST-O-COUNT + @ 1-
                _LST-HND-W @ _LST-SELECT!
                -1
            ENDOF
            \ default: not consumed
            0 SWAP
        ENDCASE
        EXIT
    THEN
    DROP 0 ;

\ =====================================================================
\ 5. Constructor
\ =====================================================================

\ LST-NEW ( rgn items count -- widget )
: LST-NEW  ( rgn items count -- widget )
    >R >R                                  \ R: count items ; ( rgn )
    _LST-DESC-SIZE ALLOCATE
    0<> ABORT" LST-NEW: alloc failed"      \ ( rgn addr )
    WDG-T-LIST     OVER _WDG-O-TYPE      + !
    SWAP           OVER _WDG-O-REGION    + !
    ['] _LST-DRAW  OVER _WDG-O-DRAW-XT   + !
    ['] _LST-HANDLE OVER _WDG-O-HANDLE-XT + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                   OVER _WDG-O-FLAGS     + !
    R>             OVER _LST-O-ITEMS     + !   \ items
    R>             OVER _LST-O-COUNT     + !   \ count
    0              OVER _LST-O-SEL       + !   \ selected = 0
    0              OVER _LST-O-SCROLL    + !   \ scroll = 0
    0              OVER _LST-O-SEL-XT    + !   \ no callback
    0              OVER _LST-O-ITEM-XT   + ! ; \ no custom renderer

\ =====================================================================
\ 6. Public API
\ =====================================================================

\ LST-SELECT ( index widget -- )
\   Programmatically select item.
: LST-SELECT  ( index widget -- )
    _LST-SELECT! ;

\ LST-SELECTED ( widget -- index )
: LST-SELECTED  ( widget -- index )
    _LST-O-SEL + @ ;

\ LST-ON-SELECT ( xt widget -- )
: LST-ON-SELECT  ( xt widget -- )
    _LST-O-SEL-XT + ! ;

\ LST-SET-ITEMS ( items count widget -- )
\   Replace the item array.  Resets selection to 0.
: LST-SET-ITEMS  ( items count widget -- )
    >R
    R@ _LST-O-COUNT + !
    R@ _LST-O-ITEMS + !
    0 R@ _LST-O-SEL + !
    0 R@ _LST-O-SCROLL + !
    R> WDG-DIRTY ;

\ LST-SCROLL-TO ( index widget -- )
\   Ensure item at index is visible (adjusts scroll).
: LST-SCROLL-TO  ( index widget -- )
    OVER OVER _LST-O-SEL + !
    _LST-ENSURE-VISIBLE ;

\ LST-SET-RENDER ( xt widget -- )
\   Set custom item renderer: ( index widget -- ).
: LST-SET-RENDER  ( xt widget -- )
    _LST-O-ITEM-XT + ! ;

\ LST-FREE ( widget -- )
: LST-FREE  ( widget -- )
    FREE ;

\ =====================================================================
\ 7. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
GUARD _lst-guard

' LST-NEW         CONSTANT _lst-new-xt
' LST-SELECT      CONSTANT _lst-select-xt
' LST-SELECTED    CONSTANT _lst-selected-xt
' LST-ON-SELECT   CONSTANT _lst-onsel-xt
' LST-SET-ITEMS   CONSTANT _lst-setitems-xt
' LST-SCROLL-TO   CONSTANT _lst-scrollto-xt
' LST-SET-RENDER  CONSTANT _lst-setrender-xt
' LST-FREE        CONSTANT _lst-free-xt

: LST-NEW         _lst-new-xt       _lst-guard WITH-GUARD ;
: LST-SELECT      _lst-select-xt    _lst-guard WITH-GUARD ;
: LST-SELECTED    _lst-selected-xt  _lst-guard WITH-GUARD ;
: LST-ON-SELECT   _lst-onsel-xt     _lst-guard WITH-GUARD ;
: LST-SET-ITEMS   _lst-setitems-xt  _lst-guard WITH-GUARD ;
: LST-SCROLL-TO   _lst-scrollto-xt  _lst-guard WITH-GUARD ;
: LST-SET-RENDER  _lst-setrender-xt _lst-guard WITH-GUARD ;
: LST-FREE        _lst-free-xt      _lst-guard WITH-GUARD ;
[THEN] [THEN]
