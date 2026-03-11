\ =====================================================================
\  akashic/tui/widget.f — Widget Common Header & Polymorphic Dispatch
\ =====================================================================
\
\  Every widget shares a uniform 5-cell header at offset +0.
\  This file defines:
\    - Header layout constants and accessors
\    - Widget type constants (WDG-T-*)
\    - Flag constants and flag manipulation words
\    - Polymorphic dispatch words (WDG-DRAW, WDG-HANDLE)
\
\  Widget-specific data lives at +40 onwards in each widget type.
\  The common header lets the event loop and focus manager iterate
\  widgets generically: call draw-xt to paint, call handle-xt to
\  dispatch input, check flags for visibility and focus state.
\
\  Widget Header (5 cells = 40 bytes):
\    +0   type       Widget type constant (WDG-T-*)
\    +8   region     Region this widget occupies
\   +16   draw-xt    Execution token: ( widget -- )
\   +24   handle-xt  Execution token: ( event widget -- consumed? )
\   +32   flags      WDG-F-VISIBLE | WDG-F-FOCUSED | WDG-F-DIRTY | ...
\
\  Prefix: WDG- (public), _WDG- (internal)
\  Provider: akashic-tui-widget
\  Dependencies: region.f

PROVIDED akashic-tui-widget

REQUIRE region.f

\ =====================================================================
\ 1. Header offsets
\ =====================================================================

 0 CONSTANT _WDG-O-TYPE
 8 CONSTANT _WDG-O-REGION
16 CONSTANT _WDG-O-DRAW-XT
24 CONSTANT _WDG-O-HANDLE-XT
32 CONSTANT _WDG-O-FLAGS

40 CONSTANT _WDG-HDR-SIZE   \ size of header; widget data starts here

\ =====================================================================
\ 2. Widget type constants
\ =====================================================================

 1 CONSTANT WDG-T-LABEL
 2 CONSTANT WDG-T-INPUT
 3 CONSTANT WDG-T-LIST
 4 CONSTANT WDG-T-MENU
 5 CONSTANT WDG-T-PROGRESS
 6 CONSTANT WDG-T-TABLE
 7 CONSTANT WDG-T-DIALOG
 8 CONSTANT WDG-T-TABS
 9 CONSTANT WDG-T-SPLIT
10 CONSTANT WDG-T-SCROLL
11 CONSTANT WDG-T-TREE
12 CONSTANT WDG-T-STATUS
13 CONSTANT WDG-T-TOAST
14 CONSTANT WDG-T-CANVAS

\ =====================================================================
\ 3. Flag constants
\ =====================================================================

1 CONSTANT WDG-F-VISIBLE
2 CONSTANT WDG-F-FOCUSED
4 CONSTANT WDG-F-DIRTY
8 CONSTANT WDG-F-DISABLED

\ =====================================================================
\ 4. Header accessors
\ =====================================================================

\ WDG-TYPE ( widget -- type )
: WDG-TYPE  ( widget -- type )
    _WDG-O-TYPE + @ ;

\ WDG-REGION ( widget -- rgn )
: WDG-REGION  ( widget -- rgn )
    _WDG-O-REGION + @ ;

\ WDG-FLAGS ( widget -- flags )
: WDG-FLAGS  ( widget -- flags )
    _WDG-O-FLAGS + @ ;

\ _WDG-FLAGS! ( flags widget -- )
: _WDG-FLAGS!  ( flags widget -- )
    _WDG-O-FLAGS + ! ;

\ =====================================================================
\ 5. Flag manipulation
\ =====================================================================

\ WDG-VISIBLE? ( widget -- flag )
: WDG-VISIBLE?  ( widget -- flag )
    WDG-FLAGS WDG-F-VISIBLE AND 0<> ;

\ WDG-FOCUSED? ( widget -- flag )
: WDG-FOCUSED?  ( widget -- flag )
    WDG-FLAGS WDG-F-FOCUSED AND 0<> ;

\ WDG-DIRTY? ( widget -- flag )
: WDG-DIRTY?  ( widget -- flag )
    WDG-FLAGS WDG-F-DIRTY AND 0<> ;

\ WDG-DISABLED? ( widget -- flag )
: WDG-DISABLED?  ( widget -- flag )
    WDG-FLAGS WDG-F-DISABLED AND 0<> ;

\ WDG-SHOW ( widget -- )  Set VISIBLE flag, mark dirty.
: WDG-SHOW  ( widget -- )
    DUP WDG-FLAGS
    WDG-F-VISIBLE OR  WDG-F-DIRTY OR
    SWAP _WDG-FLAGS! ;

\ WDG-HIDE ( widget -- )  Clear VISIBLE flag.
: WDG-HIDE  ( widget -- )
    DUP WDG-FLAGS
    WDG-F-VISIBLE INVERT AND
    SWAP _WDG-FLAGS! ;

\ WDG-ENABLE ( widget -- )  Clear DISABLED flag.
: WDG-ENABLE  ( widget -- )
    DUP WDG-FLAGS
    WDG-F-DISABLED INVERT AND
    SWAP _WDG-FLAGS! ;

\ WDG-DISABLE ( widget -- )  Set DISABLED flag, mark dirty.
: WDG-DISABLE  ( widget -- )
    DUP WDG-FLAGS
    WDG-F-DISABLED OR  WDG-F-DIRTY OR
    SWAP _WDG-FLAGS! ;

\ WDG-DIRTY ( widget -- )  Mark widget as needing redraw.
: WDG-DIRTY  ( widget -- )
    DUP WDG-FLAGS WDG-F-DIRTY OR SWAP _WDG-FLAGS! ;

\ WDG-CLEAN ( widget -- )  Clear dirty flag (after redraw).
: WDG-CLEAN  ( widget -- )
    DUP WDG-FLAGS WDG-F-DIRTY INVERT AND SWAP _WDG-FLAGS! ;

\ _WDG-FOCUS-SET ( widget -- )  Set FOCUSED flag, mark dirty.
: _WDG-FOCUS-SET  ( widget -- )
    DUP WDG-FLAGS WDG-F-FOCUSED OR WDG-F-DIRTY OR SWAP _WDG-FLAGS! ;

\ _WDG-FOCUS-CLR ( widget -- )  Clear FOCUSED flag, mark dirty.
: _WDG-FOCUS-CLR  ( widget -- )
    DUP WDG-FLAGS WDG-F-FOCUSED INVERT AND WDG-F-DIRTY OR
    SWAP _WDG-FLAGS! ;

\ =====================================================================
\ 6. Polymorphic dispatch
\ =====================================================================

\ WDG-DRAW ( widget -- )
\   Call the widget's draw-xt if visible.
\   Activates the widget's region, calls draw-xt, clears dirty flag.
: WDG-DRAW  ( widget -- )
    DUP WDG-VISIBLE? IF
        DUP WDG-REGION RGN-USE
        DUP DUP _WDG-O-DRAW-XT + @ EXECUTE
        WDG-CLEAN
    ELSE
        DROP
    THEN ;

\ WDG-HANDLE ( event widget -- consumed? )
\   Call the widget's handle-xt if not disabled.
\   Returns TRUE if the event was consumed, FALSE otherwise.
: WDG-HANDLE  ( event widget -- consumed? )
    DUP WDG-DISABLED? IF
        2DROP 0
    ELSE
        DUP _WDG-O-HANDLE-XT + @ EXECUTE
    THEN ;

\ =====================================================================
\ 7. Header initialization helper (used by widget constructors)
\ =====================================================================

\ _WDG-INIT ( addr type rgn draw-xt handle-xt -- )
\   Fill the 5-cell header at addr.
\   Sets flags to VISIBLE | DIRTY by default.
: _WDG-INIT  ( addr type rgn draw-xt handle-xt -- )
    4 PICK _WDG-O-HANDLE-XT + !       \ handle-xt
    3 PICK _WDG-O-DRAW-XT   + !       \ draw-xt
    2 PICK _WDG-O-REGION    + !       \ region
    OVER   _WDG-O-TYPE      + !       \ type
    WDG-F-VISIBLE WDG-F-DIRTY OR
    SWAP   _WDG-O-FLAGS     + ! ;      \ flags

\ =====================================================================
\ 8. Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
GUARD _wdg-guard

' WDG-TYPE        CONSTANT _wdg-type-xt
' WDG-REGION      CONSTANT _wdg-region-xt
' WDG-FLAGS       CONSTANT _wdg-flags-xt
' WDG-VISIBLE?    CONSTANT _wdg-visible-xt
' WDG-FOCUSED?    CONSTANT _wdg-focused-xt
' WDG-DIRTY?      CONSTANT _wdg-dirty-xt
' WDG-DISABLED?   CONSTANT _wdg-disabled-xt
' WDG-SHOW        CONSTANT _wdg-show-xt
' WDG-HIDE        CONSTANT _wdg-hide-xt
' WDG-ENABLE      CONSTANT _wdg-enable-xt
' WDG-DISABLE     CONSTANT _wdg-disable-xt
' WDG-DIRTY       CONSTANT _wdg-dirty2-xt
' WDG-CLEAN       CONSTANT _wdg-clean-xt
' WDG-DRAW        CONSTANT _wdg-draw-xt
' WDG-HANDLE      CONSTANT _wdg-handle-xt
' _WDG-INIT       CONSTANT _wdg-init-xt

: WDG-TYPE        _wdg-type-xt      _wdg-guard WITH-GUARD ;
: WDG-REGION      _wdg-region-xt    _wdg-guard WITH-GUARD ;
: WDG-FLAGS       _wdg-flags-xt     _wdg-guard WITH-GUARD ;
: WDG-VISIBLE?    _wdg-visible-xt   _wdg-guard WITH-GUARD ;
: WDG-FOCUSED?    _wdg-focused-xt   _wdg-guard WITH-GUARD ;
: WDG-DIRTY?      _wdg-dirty-xt     _wdg-guard WITH-GUARD ;
: WDG-DISABLED?   _wdg-disabled-xt  _wdg-guard WITH-GUARD ;
: WDG-SHOW        _wdg-show-xt      _wdg-guard WITH-GUARD ;
: WDG-HIDE        _wdg-hide-xt      _wdg-guard WITH-GUARD ;
: WDG-ENABLE      _wdg-enable-xt    _wdg-guard WITH-GUARD ;
: WDG-DISABLE     _wdg-disable-xt   _wdg-guard WITH-GUARD ;
: WDG-DIRTY       _wdg-dirty2-xt    _wdg-guard WITH-GUARD ;
: WDG-CLEAN       _wdg-clean-xt     _wdg-guard WITH-GUARD ;
: WDG-DRAW        _wdg-draw-xt      _wdg-guard WITH-GUARD ;
: WDG-HANDLE      _wdg-handle-xt    _wdg-guard WITH-GUARD ;
: _WDG-INIT       _wdg-init-xt      _wdg-guard WITH-GUARD ;
[THEN] [THEN]
