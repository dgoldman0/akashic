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
15 CONSTANT WDG-T-FSEL
16 CONSTANT WDG-T-EXPLORER
17 CONSTANT WDG-T-PROMPT
18 CONSTANT WDG-T-AGENT-AUTH
19 CONSTANT WDG-T-AGENT-SETTINGS

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

\ WDG-FOCUS-SET ( widget -- )  Set FOCUSED flag, mark dirty.
\ Public for focus managers and composed widgets that forward focus to a
\ mounted child; it does not alter any focus-chain membership.
: WDG-FOCUS-SET  ( widget -- )
    DUP WDG-FLAGS WDG-F-FOCUSED OR WDG-F-DIRTY OR SWAP _WDG-FLAGS! ;

\ WDG-FOCUS-CLR ( widget -- )  Clear FOCUSED flag, mark dirty.
: WDG-FOCUS-CLR  ( widget -- )
    DUP WDG-FLAGS WDG-F-FOCUSED INVERT AND WDG-F-DIRTY OR
    SWAP _WDG-FLAGS! ;

\ =====================================================================
\ 6. Polymorphic dispatch and draw observation
\ =====================================================================

\ Ordinary composed widgets may contain other canonical widgets which are
\ not direct members of a retained document.  A UI owner can observe that
\ existing draw lifecycle without teaching either widget about a renderer.
\ The observer is scoped around a caller body and is diagnostic-only:
\ observer failure is retained as the scope status but never interrupts CELL
\ painting.  A throwing widget draw still throws its original exception.
\
\ observer-xt: ( widget phase context -- status )
\ body-xt:     ( i*x -- j*x )
\
\ FULL-BEGIN / FULL-END bracket one visible WDG-DRAW.  FULL-ABORT closes a
\ begun draw whose widget callback threw.  PARTIAL is emitted only after a
\ canonical partial draw has completed successfully.

0 CONSTANT WDG-DRAW-PHASE-FULL-BEGIN
1 CONSTANT WDG-DRAW-PHASE-FULL-END
2 CONSTANT WDG-DRAW-PHASE-FULL-ABORT
3 CONSTANT WDG-DRAW-PHASE-PARTIAL

0 CONSTANT WDG-DRAW-OBS-S-OK
1 CONSTANT WDG-DRAW-OBS-S-INVALID
2 CONSTANT WDG-DRAW-OBS-S-NESTED
3 CONSTANT WDG-DRAW-OBS-S-CALLBACK
4 CONSTANT WDG-DRAW-OBS-S-REENTRANT

VARIABLE _WDG-OBS-XT
VARIABLE _WDG-OBS-CONTEXT
VARIABLE _WDG-OBS-BODY-XT
VARIABLE _WDG-OBS-ACTIVE
VARIABLE _WDG-OBS-CALLING
VARIABLE _WDG-OBS-FAULT
VARIABLE _WDG-OBS-IOR
VARIABLE _WDG-OBS-WIDGET
VARIABLE _WDG-OBS-PHASE

0 _WDG-OBS-XT !
0 _WDG-OBS-CONTEXT !
0 _WDG-OBS-BODY-XT !
0 _WDG-OBS-ACTIVE !
0 _WDG-OBS-CALLING !
0 _WDG-OBS-FAULT !
0 _WDG-OBS-IOR !
0 _WDG-OBS-WIDGET !
0 _WDG-OBS-PHASE !

: _WDG-OBS-SET-FAULT  ( status -- )
    ?DUP IF
        _WDG-OBS-FAULT @ 0= IF _WDG-OBS-FAULT ! ELSE DROP THEN
    THEN ;

: _WDG-OBS-DO-NOTE  ( -- status )
    _WDG-OBS-WIDGET @ _WDG-OBS-PHASE @ _WDG-OBS-CONTEXT @
    _WDG-OBS-XT @ EXECUTE ;

: _WDG-OBS-NOTE  ( widget phase -- )
    _WDG-OBS-ACTIVE @ 0= IF 2DROP EXIT THEN
    _WDG-OBS-FAULT @ IF 2DROP EXIT THEN
    _WDG-OBS-CALLING @ IF
        2DROP WDG-DRAW-OBS-S-REENTRANT _WDG-OBS-SET-FAULT EXIT
    THEN
    _WDG-OBS-PHASE ! _WDG-OBS-WIDGET !
    -1 _WDG-OBS-CALLING !
    ['] _WDG-OBS-DO-NOTE CATCH ?DUP IF
        DROP WDG-DRAW-OBS-S-CALLBACK
    THEN
    0 _WDG-OBS-CALLING !
    0 _WDG-OBS-WIDGET ! 0 _WDG-OBS-PHASE !
    _WDG-OBS-SET-FAULT ;

: _WDG-OBS-DO-BODY  ( i*x -- j*x )
    _WDG-OBS-BODY-XT @ EXECUTE ;

: _WDG-OBS-CLEAR  ( -- )
    0 _WDG-OBS-XT ! 0 _WDG-OBS-CONTEXT ! 0 _WDG-OBS-BODY-XT !
    0 _WDG-OBS-ACTIVE ! 0 _WDG-OBS-CALLING !
    0 _WDG-OBS-WIDGET ! 0 _WDG-OBS-PHASE ! ;

\ WDG-DRAW-OBSERVE ( i*x context observer-xt body-xt -- j*x status )
\   Execute body-xt with one call-scoped observer.  Nested scopes leave the
\   outer observer installed and execute their body under it, returning
\   NESTED.  The active observer's first failure is returned after an
\   otherwise successful body.  Body exceptions are rethrown unchanged after
\   all observation state has been scrubbed.
: WDG-DRAW-OBSERVE
    ( i*x context observer-xt body-xt -- j*x status )
    _WDG-OBS-ACTIVE @ IF
        NIP NIP EXECUTE WDG-DRAW-OBS-S-NESTED EXIT
    THEN
    DUP 0= IF DROP 2DROP WDG-DRAW-OBS-S-INVALID EXIT THEN
    OVER 0= IF
        NIP NIP EXECUTE WDG-DRAW-OBS-S-INVALID EXIT
    THEN
    _WDG-OBS-BODY-XT ! _WDG-OBS-XT ! _WDG-OBS-CONTEXT !
    0 _WDG-OBS-FAULT ! 0 _WDG-OBS-IOR !
    -1 _WDG-OBS-ACTIVE !
    ['] _WDG-OBS-DO-BODY CATCH _WDG-OBS-IOR !
    _WDG-OBS-FAULT @
    _WDG-OBS-CLEAR
    _WDG-OBS-IOR @ DUP 0= IF DROP EXIT THEN
    NIP THROW ;

\ WDG-DRAW-PARTIAL-COMPLETE ( widget -- )
\   Canonical widgets with a truthful partial-paint entry call this only
\   after their draw and dirty-state transition have completed.
: WDG-DRAW-PARTIAL-COMPLETE  ( widget -- )
    WDG-DRAW-PHASE-PARTIAL _WDG-OBS-NOTE ;

\ WDG-DRAW ( widget -- )
\   Call the widget's draw-xt if visible.
\   Activates the widget's region, calls draw-xt, clears dirty flag.
: WDG-DRAW  ( widget -- )
    DUP WDG-VISIBLE? IF
        DUP WDG-REGION RGN-USE
        DUP WDG-DRAW-PHASE-FULL-BEGIN _WDG-OBS-NOTE
        DUP DUP _WDG-O-DRAW-XT + @ CATCH ?DUP IF
            >R DROP
            DUP WDG-DRAW-PHASE-FULL-ABORT _WDG-OBS-NOTE
            DROP R> THROW
        THEN
        DUP WDG-DRAW-PHASE-FULL-END _WDG-OBS-NOTE
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

\ WDG-INIT ( addr type rgn draw-xt handle-xt -- )
\   Fill the 5-cell header at addr.
\   Sets flags to VISIBLE | DIRTY by default.
: WDG-INIT  ( addr type rgn draw-xt handle-xt -- )
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
REQUIRE ../concurrency/guard.f
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
' WDG-DRAW-OBSERVE CONSTANT _wdg-draw-observe-xt
' WDG-DRAW-PARTIAL-COMPLETE
                  CONSTANT _wdg-draw-partial-complete-xt
' WDG-DRAW        CONSTANT _wdg-draw-xt
' WDG-HANDLE      CONSTANT _wdg-handle-xt
' WDG-FOCUS-SET   CONSTANT _wdg-focus-set-xt
' WDG-FOCUS-CLR   CONSTANT _wdg-focus-clr-xt
' WDG-INIT        CONSTANT _wdg-init-xt

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
: WDG-FOCUS-SET   _wdg-focus-set-xt _wdg-guard WITH-GUARD ;
: WDG-FOCUS-CLR   _wdg-focus-clr-xt _wdg-guard WITH-GUARD ;
\ Polymorphic dispatch executes widget-provided code.  Drawing and input
\ handling are UI-owner lifecycle work, so never retain _wdg-guard across a
\ draw/handle callback; cross-core callers must post work to the UI owner.
: WDG-DRAW-OBSERVE _wdg-draw-observe-xt EXECUTE ;
: WDG-DRAW-PARTIAL-COMPLETE
                  _wdg-draw-partial-complete-xt EXECUTE ;
: WDG-DRAW        _wdg-draw-xt EXECUTE ;
: WDG-HANDLE      _wdg-handle-xt EXECUTE ;
: WDG-INIT        _wdg-init-xt      _wdg-guard WITH-GUARD ;
[THEN] [THEN]
