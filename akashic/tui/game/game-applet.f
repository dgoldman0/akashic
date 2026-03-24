\ =====================================================================
\  akashic/tui/game/game-applet.f — Game Applet Builder
\ =====================================================================
\
\  Convenience words for creating desk-compatible game applets.
\  Stamps out a complete APP-DESC whose init-xt creates a Game-View
\  (or Canvas Game-View) filling the applet's root region, wires
\  tick → fixed-step update, and wires paint → game draw.
\
\  Usage:
\    : my-init     ( -- )         ... ;
\    : my-update   ( dt -- )      ... ;
\    : my-draw     ( rgn -- )     ... ;
\    : my-input    ( ev -- )      ... ;
\    : my-shutdown ( -- )         ... ;
\
\    GAME-APP-DESC CONSTANT my-desc
\    S" My Game"       my-desc GAPP-TITLE!
\    30                 my-desc GAPP-FPS!
\    ' my-init         my-desc GAPP-ON-INIT!
\    ' my-update       my-desc GAPP-ON-UPDATE!
\    ' my-draw         my-desc GAPP-ON-DRAW!
\    ' my-input        my-desc GAPP-ON-INPUT!
\    ' my-shutdown     my-desc GAPP-ON-SHUTDOWN!
\
\    my-desc DESK-LAUNCH   \ launch as desk applet
\
\  The builder allocates an extended descriptor that holds both the
\  standard APP-DESC (112 bytes) and game-specific callback slots.
\  The internal init-xt creates a Game-View widget, wires everything
\  up, and calls the user's init callback.
\
\  Prefix: GAPP- (public), _GAPP- (internal)
\  Provider: akashic-tui-game-applet
\  Dependencies: app-desc.f, game-view.f, region.f

PROVIDED akashic-tui-game-applet

REQUIRE ../app-desc.f
REQUIRE game-view.f
REQUIRE ../region.f

\ =====================================================================
\  §1 — Extended Descriptor Layout
\ =====================================================================
\
\  Extends APP-DESC with game-specific fields after the standard
\  112 bytes.

112 CONSTANT _GAPP-O-USER-INIT      \ ( -- )
120 CONSTANT _GAPP-O-USER-UPDATE    \ ( dt -- )
128 CONSTANT _GAPP-O-USER-DRAW      \ ( rgn -- )
136 CONSTANT _GAPP-O-USER-INPUT     \ ( ev -- )
144 CONSTANT _GAPP-O-USER-SHUTDOWN  \ ( -- )
152 CONSTANT _GAPP-O-FPS            \ target FPS
160 CONSTANT _GAPP-O-GV             \ Game-View widget ptr
168 CONSTANT _GAPP-DESC-SZ

\ =====================================================================
\  §2 — Internal Callbacks
\ =====================================================================
\
\  These are wired into the APP-DESC standard slots and delegate
\  to the game-view and user callbacks.

\ Current game-applet descriptor (set during callbacks)
VARIABLE _GAPP-CUR

\ Region provider — uses ASHELL-REGION when available (app-shell loaded),
\ otherwise falls back to a variable set before init.
VARIABLE _GAPP-ROOT-RGN   0 _GAPP-ROOT-RGN !

: _GAPP-REGION  ( -- rgn )
    [DEFINED] ASHELL-REGION [IF]
        ASHELL-REGION
    [ELSE]
        _GAPP-ROOT-RGN @
    [THEN] ;

\ Internal INIT-XT: create Game-View, wire callbacks, call user init
: _GAPP-INIT  ( -- )
    _GAPP-CUR @                          ( desc )
    \ Create game-view over root region
    _GAPP-REGION GV-NEW                  ( desc gv )
    OVER _GAPP-O-GV + !                 ( desc )
    \ Set FPS
    DUP _GAPP-O-GV + @
    OVER _GAPP-O-FPS + @ GV-FPS!        ( desc )
    \ Wire user callbacks into game-view
    DUP _GAPP-O-USER-UPDATE + @ ?DUP IF
        OVER _GAPP-O-GV + @ SWAP GV-ON-UPDATE
    THEN
    DUP _GAPP-O-USER-DRAW + @ ?DUP IF
        OVER _GAPP-O-GV + @ SWAP GV-ON-DRAW
    THEN
    DUP _GAPP-O-USER-INPUT + @ ?DUP IF
        OVER _GAPP-O-GV + @ SWAP GV-ON-INPUT
    THEN
    \ Call user init
    _GAPP-O-USER-INIT + @ ?DUP IF EXECUTE THEN ;

\ Internal EVENT-XT: route events to game-view
: _GAPP-EVENT  ( ev -- consumed? )
    _GAPP-CUR @ _GAPP-O-GV + @ ?DUP IF
        WDG-HANDLE
    ELSE
        DROP 0
    THEN ;

\ Internal TICK-XT: tick the game-view
: _GAPP-TICK  ( -- )
    _GAPP-CUR @ _GAPP-O-GV + @ ?DUP IF GV-TICK THEN ;

\ Internal PAINT-XT: draw the game-view
: _GAPP-PAINT  ( -- )
    _GAPP-CUR @ _GAPP-O-GV + @ ?DUP IF WDG-DRAW THEN ;

\ Internal SHUTDOWN-XT: free game-view, call user shutdown
: _GAPP-SHUTDOWN  ( -- )
    _GAPP-CUR @                          ( desc )
    DUP _GAPP-O-GV + @ ?DUP IF
        GV-FREE
        0 OVER _GAPP-O-GV + !
    THEN
    _GAPP-O-USER-SHUTDOWN + @ ?DUP IF EXECUTE THEN ;

\ =====================================================================
\  §3 — Constructor
\ =====================================================================

: GAME-APP-DESC  ( -- desc )
    _GAPP-DESC-SZ ALLOCATE
    0<> ABORT" GAPP: alloc"
    DUP _GAPP-DESC-SZ 0 FILL            \ zero everything
    \ Wire internal callbacks into APP-DESC slots
    ['] _GAPP-INIT     OVER APP.INIT-XT     !
    ['] _GAPP-EVENT    OVER APP.EVENT-XT    !
    ['] _GAPP-TICK     OVER APP.TICK-XT     !
    ['] _GAPP-PAINT    OVER APP.PAINT-XT    !
    ['] _GAPP-SHUTDOWN OVER APP.SHUTDOWN-XT !
    \ Defaults
    30 OVER _GAPP-O-FPS + !             \ 30 FPS
    0  OVER _GAPP-O-GV  + !             \ no game-view yet
    \ Store self-reference for callback routing
    DUP _GAPP-CUR ! ;

\ =====================================================================
\  §4 — Configuration
\ =====================================================================

: GAPP-FPS!          ( fps desc -- )   _GAPP-O-FPS + ! ;
: GAPP-ON-INIT!      ( xt desc -- )    _GAPP-O-USER-INIT + ! ;
: GAPP-ON-UPDATE!    ( xt desc -- )    _GAPP-O-USER-UPDATE + ! ;
: GAPP-ON-DRAW!      ( xt desc -- )    _GAPP-O-USER-DRAW + ! ;
: GAPP-ON-INPUT!     ( xt desc -- )    _GAPP-O-USER-INPUT + ! ;
: GAPP-ON-SHUTDOWN!  ( xt desc -- )    _GAPP-O-USER-SHUTDOWN + ! ;

: GAPP-TITLE!  ( addr u desc -- )
    >R
    R@ APP.TITLE-U !
    R> APP.TITLE-A ! ;

\ =====================================================================
\  §5 — Runtime Access
\ =====================================================================

: GAPP-GV  ( desc -- gv | 0 )
    _GAPP-O-GV + @ ;

\ =====================================================================
\  §6 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _gapp-guard

' GAME-APP-DESC    CONSTANT _gapp-desc-xt
' GAPP-FPS!        CONSTANT _gapp-fps-xt
' GAPP-ON-INIT!    CONSTANT _gapp-init-xt
' GAPP-ON-UPDATE!  CONSTANT _gapp-update-xt
' GAPP-ON-DRAW!    CONSTANT _gapp-draw-xt
' GAPP-ON-INPUT!   CONSTANT _gapp-input-xt
' GAPP-ON-SHUTDOWN! CONSTANT _gapp-shutdown-xt
' GAPP-TITLE!      CONSTANT _gapp-title-xt

: GAME-APP-DESC    _gapp-desc-xt     _gapp-guard WITH-GUARD ;
: GAPP-FPS!        _gapp-fps-xt      _gapp-guard WITH-GUARD ;
: GAPP-ON-INIT!    _gapp-init-xt     _gapp-guard WITH-GUARD ;
: GAPP-ON-UPDATE!  _gapp-update-xt   _gapp-guard WITH-GUARD ;
: GAPP-ON-DRAW!    _gapp-draw-xt     _gapp-guard WITH-GUARD ;
: GAPP-ON-INPUT!   _gapp-input-xt    _gapp-guard WITH-GUARD ;
: GAPP-ON-SHUTDOWN! _gapp-shutdown-xt _gapp-guard WITH-GUARD ;
: GAPP-TITLE!      _gapp-title-xt    _gapp-guard WITH-GUARD ;
[THEN] [THEN]
