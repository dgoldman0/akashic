\ =====================================================================
\  akashic/tui/game/scene.f — Scene Manager
\ =====================================================================
\
\  Manages game scenes (title screen, gameplay, inventory, pause,
\  game-over, etc.) as a stack with enter/leave/update/draw callbacks.
\
\  The active scene is the top of an 8-deep stack.  SCENE-PUSH saves
\  the current scene and activates a new one (e.g., pause overlay).
\  SCENE-POP restores the previous scene.  SCENE-SWITCH replaces the
\  top scene entirely (e.g., title → gameplay).
\
\  Each scene is described by a 32-byte (4-cell) callback table:
\    +0   on-enter   ( -- )        Called when scene becomes active
\    +8   on-leave   ( -- )        Called when scene ceases to be active
\   +16   on-update  ( -- )        Called every fixed-timestep tick
\   +24   on-draw    ( -- )        Called every frame
\
\  A callback of 0 means "no-op" — will be silently skipped.
\
\  Integration with loop.f:
\    SCENE-BIND-LOOP connects the scene manager to GAME-ON-UPDATE
\    and GAME-ON-DRAW so the active scene's callbacks are driven by
\    the game loop automatically.
\
\  Public API:
\    SCN-DEFINE      ( xt-enter xt-leave xt-update xt-draw -- scn )
\    SCN-FREE        ( scn -- )
\    SCN-PUSH        ( scn -- )       Push scene onto stack
\    SCN-POP         ( -- )           Pop and restore previous scene
\    SCN-SWITCH      ( scn -- )       Replace top scene
\    SCN-UPDATE      ( -- )           Call active scene's on-update
\    SCN-DRAW        ( -- )           Call active scene's on-draw
\    SCN-ACTIVE      ( -- scn | 0 )   Get current active scene
\    SCN-DEPTH       ( -- n )         Stack depth
\    SCN-BIND-LOOP   ( -- )           Wire into game loop callbacks
\    SCN-BIND-APPLET ( desc -- )      Wire into app descriptor
\
\  Prefix: SCN- (public), _SCN- (internal)
\  Provider: akashic-tui-game-scene
\  Dependencies: (none; optionally loop.f for SCN-BIND-LOOP,
\                app-desc.f for SCN-BIND-APPLET)

PROVIDED akashic-tui-game-scene

\ =====================================================================
\  §1 — Scene Descriptor
\ =====================================================================

 0 CONSTANT _SCN-O-ENTER
 8 CONSTANT _SCN-O-LEAVE
16 CONSTANT _SCN-O-UPDATE
24 CONSTANT _SCN-O-DRAW
32 CONSTANT _SCN-DESC-SIZE

\ =====================================================================
\  §2 — Scene Stack
\ =====================================================================

8 CONSTANT _SCN-MAX-DEPTH

CREATE _SCN-STACK  _SCN-MAX-DEPTH CELLS ALLOT
VARIABLE _SCN-SP   \ stack pointer (0 = empty)

: _SCN-INIT  0 _SCN-SP ! ;
_SCN-INIT

\ =====================================================================
\  §3 — Constructor / Destructor
\ =====================================================================

: SCN-DEFINE  ( xt-enter xt-leave xt-update xt-draw -- scn )
    _SCN-DESC-SIZE ALLOCATE 0<> ABORT" SCN-DEFINE: alloc"
    >R
    R@ _SCN-O-DRAW   + !
    R@ _SCN-O-UPDATE + !
    R@ _SCN-O-LEAVE  + !
    R@ _SCN-O-ENTER  + !
    R> ;

: SCN-FREE  ( scn -- )
    FREE ;

\ =====================================================================
\  §4 — Stack Operations
\ =====================================================================

\ _SCN-CALL ( scn offset -- )
\   Execute callback at offset if non-zero.
: _SCN-CALL  ( scn offset -- )
    + @ DUP 0<> IF EXECUTE ELSE DROP THEN ;

: SCN-ACTIVE  ( -- scn | 0 )
    _SCN-SP @ 0= IF 0 EXIT THEN
    _SCN-STACK _SCN-SP @ 1- CELLS + @ ;

: SCN-DEPTH  ( -- n )
    _SCN-SP @ ;

: SCN-PUSH  ( scn -- )
    _SCN-SP @ _SCN-MAX-DEPTH >= ABORT" SCN-PUSH: stack full"
    \ Leave current scene if one exists
    SCN-ACTIVE DUP 0<> IF _SCN-O-LEAVE _SCN-CALL ELSE DROP THEN
    \ Push new scene
    _SCN-STACK _SCN-SP @ CELLS + !
    _SCN-SP @ 1+ _SCN-SP !
    \ Enter new scene
    SCN-ACTIVE _SCN-O-ENTER _SCN-CALL ;

: SCN-POP  ( -- )
    _SCN-SP @ 0= IF EXIT THEN
    \ Leave current scene
    SCN-ACTIVE _SCN-O-LEAVE _SCN-CALL
    \ Pop
    _SCN-SP @ 1- _SCN-SP !
    \ Re-enter previous scene if one exists
    SCN-ACTIVE DUP 0<> IF _SCN-O-ENTER _SCN-CALL ELSE DROP THEN ;

: SCN-SWITCH  ( scn -- )
    _SCN-SP @ 0= IF
        \ No current scene — just push
        SCN-PUSH EXIT
    THEN
    \ Leave current
    SCN-ACTIVE _SCN-O-LEAVE _SCN-CALL
    \ Replace top
    _SCN-STACK _SCN-SP @ 1- CELLS + !
    \ Enter new
    SCN-ACTIVE _SCN-O-ENTER _SCN-CALL ;

\ =====================================================================
\  §5 — Per-Frame Dispatch
\ =====================================================================

: SCN-UPDATE  ( -- )
    SCN-ACTIVE DUP 0<> IF _SCN-O-UPDATE _SCN-CALL ELSE DROP THEN ;

: SCN-DRAW  ( -- )
    SCN-ACTIVE DUP 0<> IF _SCN-O-DRAW _SCN-CALL ELSE DROP THEN ;

\ =====================================================================
\  §6 — Game-Loop Integration
\ =====================================================================

REQUIRE loop.f

: SCN-BIND-LOOP  ( -- )
    ['] SCN-UPDATE GAME-ON-UPDATE
    ['] SCN-DRAW   GAME-ON-DRAW ;

\ =====================================================================
\  §7 — App-Shell Integration
\ =====================================================================

REQUIRE ../app-desc.f

\ SCN-BIND-APPLET ( desc -- )
\   Wire the scene manager into an app descriptor for desk hosting.
\   Sets GAME-ON-UPDATE to drive scenes via the accumulator, then
\   installs GAME-TICK as the tick callback and SCN-DRAW as paint.
: SCN-BIND-APPLET  ( desc -- )
    ['] SCN-UPDATE GAME-ON-UPDATE
    ['] GAME-TICK  OVER APP.TICK-XT  !
    ['] SCN-DRAW   SWAP APP.PAINT-XT ! ;

\ =====================================================================
\  §8 — Concurrency Guards
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _scn-guard

' SCN-DEFINE      CONSTANT _scn-define-xt
' SCN-FREE        CONSTANT _scn-free-xt
' SCN-PUSH        CONSTANT _scn-push-xt
' SCN-POP         CONSTANT _scn-pop-xt
' SCN-SWITCH      CONSTANT _scn-switch-xt
' SCN-BIND-LOOP   CONSTANT _scn-bloop-xt
' SCN-BIND-APPLET CONSTANT _scn-bapplet-xt

: SCN-DEFINE      _scn-define-xt   _scn-guard WITH-GUARD ;
: SCN-FREE        _scn-free-xt     _scn-guard WITH-GUARD ;
: SCN-PUSH        _scn-push-xt     _scn-guard WITH-GUARD ;
: SCN-POP         _scn-pop-xt      _scn-guard WITH-GUARD ;
: SCN-SWITCH      _scn-switch-xt   _scn-guard WITH-GUARD ;
: SCN-BIND-LOOP   _scn-bloop-xt    _scn-guard WITH-GUARD ;
: SCN-BIND-APPLET _scn-bapplet-xt  _scn-guard WITH-GUARD ;
[THEN] [THEN]
