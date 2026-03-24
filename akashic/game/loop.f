\ =====================================================================
\  akashic/tui/game/loop.f — Fixed-Timestep Game Loop Adapter
\ =====================================================================
\
\  Wraps the TUI event infrastructure to provide a frame-driven game
\  loop with a fixed update rate.  Instead of event-driven dispatch,
\  the loop runs: input → update → draw → flush every frame at the
\  target FPS.
\
\  The loop reuses KEY-POLL, SCR-FLUSH, MS@, and YIELD? from the
\  existing TUI stack.  It does NOT use TUI-EVT-LOOP — it is a
\  parallel entry point for game-oriented programs.
\
\  Callbacks:
\    input-xt   ( ev -- )           Called for each key event polled
\    update-xt  ( dt -- )           Fixed timestep update (dt = ms)
\    draw-xt    ( -- )              Render the current frame
\    quit-xt    ( -- flag )         Optional: returns TRUE to exit
\
\  Public API:
\    GAME-FPS!       ( n -- )       Set target frame rate (default: 30)
\    GAME-ON-INPUT   ( xt -- )      Register input callback
\    GAME-ON-UPDATE  ( xt -- )      Register update callback
\    GAME-ON-DRAW    ( xt -- )      Register draw callback
\    GAME-ON-QUIT    ( xt -- )      Register quit-check callback
\    GAME-RUN        ( -- )         Enter game loop (blocks)
\    GAME-QUIT       ( -- )         Signal loop exit
\    GAME-INIT       ( -- )         Reset timing state (applet mode)
\    GAME-TICK       ( -- )         Run one tick cycle (applet mode)
\    GAME-FRAME#     ( -- n )       Current frame number
\    GAME-DT         ( -- ms )      Current frame interval in ms
\
\  Prefix: GAME- (public), _GAME- (internal)
\  Provider: akashic-tui-game-loop
\  Dependencies: keys.f, screen.f

PROVIDED akashic-tui-game-loop

REQUIRE ../tui/keys.f
REQUIRE ../tui/screen.f

\ =====================================================================
\  §1 — State
\ =====================================================================

VARIABLE _GAME-RUNNING          \ Loop active flag
0 _GAME-RUNNING !

VARIABLE _GAME-FRAME-MS         \ Milliseconds per frame
33 _GAME-FRAME-MS !             \ Default: ~30 fps

VARIABLE _GAME-INPUT-XT         \ Input callback  ( ev -- )
0 _GAME-INPUT-XT !

VARIABLE _GAME-UPDATE-XT        \ Update callback ( dt -- )
0 _GAME-UPDATE-XT !

VARIABLE _GAME-DRAW-XT          \ Draw callback   ( -- )
0 _GAME-DRAW-XT !

VARIABLE _GAME-QUIT-XT          \ Quit check      ( -- flag )
0 _GAME-QUIT-XT !

VARIABLE _GAME-FRAME            \ Frame counter
0 _GAME-FRAME !

VARIABLE _GAME-LAST-MS          \ MS@ at start of previous frame
0 _GAME-LAST-MS !

VARIABLE _GAME-ACCUM            \ Accumulator for fixed timestep
0 _GAME-ACCUM !

\ Key event buffer (3 cells = 24 bytes)
CREATE _GAME-EV 24 ALLOT

\ Deferred action queue (8 slots)
8 CONSTANT _GAME-POST-MAX
CREATE _GAME-POST-Q  _GAME-POST-MAX CELLS ALLOT
VARIABLE _GAME-POST-HEAD   0 _GAME-POST-HEAD !
VARIABLE _GAME-POST-TAIL   0 _GAME-POST-TAIL !

\ =====================================================================
\  §2 — Public Configuration
\ =====================================================================

\ GAME-FPS! ( n -- )
\   Set target frame rate.  Clamps to 1..120.
: GAME-FPS!  ( n -- )
    DUP 1 < IF DROP 1 THEN
    DUP 120 > IF DROP 120 THEN
    1000 SWAP / _GAME-FRAME-MS ! ;

\ GAME-DT ( -- ms )
\   Return the frame interval in milliseconds.
: GAME-DT  ( -- ms )
    _GAME-FRAME-MS @ ;

\ GAME-FRAME# ( -- n )
\   Return the current frame counter.
: GAME-FRAME#  ( -- n )
    _GAME-FRAME @ ;

\ GAME-ON-INPUT ( xt -- )
: GAME-ON-INPUT  ( xt -- )
    _GAME-INPUT-XT ! ;

\ GAME-ON-UPDATE ( xt -- )
: GAME-ON-UPDATE  ( xt -- )
    _GAME-UPDATE-XT ! ;

\ GAME-ON-DRAW ( xt -- )
: GAME-ON-DRAW  ( xt -- )
    _GAME-DRAW-XT ! ;

\ GAME-ON-QUIT ( xt -- )
: GAME-ON-QUIT  ( xt -- )
    _GAME-QUIT-XT ! ;

\ GAME-QUIT ( -- )
: GAME-QUIT  ( -- )
    0 _GAME-RUNNING ! ;

\ =====================================================================
\  §3 — Deferred Actions
\ =====================================================================

\ GAME-POST ( xt -- )
\   Enqueue a deferred action for end-of-frame execution.
: GAME-POST  ( xt -- )
    _GAME-POST-HEAD @
    _GAME-POST-TAIL @ -
    _GAME-POST-MAX >= IF DROP EXIT THEN
    _GAME-POST-HEAD @
    _GAME-POST-MAX MOD CELLS _GAME-POST-Q + !
    _GAME-POST-HEAD @ 1+ _GAME-POST-HEAD ! ;

\ _GAME-DRAIN-POSTED ( -- )
: _GAME-DRAIN-POSTED  ( -- )
    BEGIN
        _GAME-POST-TAIL @ _GAME-POST-HEAD @ <
    WHILE
        _GAME-POST-TAIL @
        _GAME-POST-MAX MOD CELLS _GAME-POST-Q + @
        _GAME-POST-TAIL @ 1+ _GAME-POST-TAIL !
        EXECUTE
    REPEAT ;

\ =====================================================================
\  §4 — Input Phase
\ =====================================================================

\ _GAME-POLL-INPUT ( -- )
\   Drain all pending key events, calling the input callback for each.
: _GAME-POLL-INPUT  ( -- )
    _GAME-INPUT-XT @ 0= IF EXIT THEN
    BEGIN
        _GAME-EV KEY-POLL
    WHILE
        _GAME-EV _GAME-INPUT-XT @ EXECUTE
    REPEAT ;

\ =====================================================================
\  §5 — Update Phase (fixed timestep with accumulator)
\ =====================================================================

\ _GAME-DO-UPDATE ( elapsed-ms -- )
\   Add elapsed time to accumulator, run update in fixed dt steps.
\   This ensures the update callback always receives the same dt,
\   regardless of frame timing jitter.
: _GAME-DO-UPDATE  ( elapsed-ms -- )
    _GAME-ACCUM @ + _GAME-ACCUM !
    _GAME-UPDATE-XT @ 0= IF 0 _GAME-ACCUM ! EXIT THEN
    BEGIN
        _GAME-ACCUM @ _GAME-FRAME-MS @ >=
    WHILE
        _GAME-FRAME-MS @ _GAME-UPDATE-XT @ EXECUTE
        _GAME-ACCUM @ _GAME-FRAME-MS @ - _GAME-ACCUM !
    REPEAT ;

\ =====================================================================
\  §6 — Draw Phase
\ =====================================================================

\ _GAME-DO-DRAW ( -- )
\   Call the draw callback then flush the screen.
: _GAME-DO-DRAW  ( -- )
    _GAME-DRAW-XT @ ?DUP IF EXECUTE THEN
    SCR-FLUSH ;

\ =====================================================================
\  §7 — Frame Pacing
\ =====================================================================

\ _GAME-WAIT-FRAME ( frame-start-ms -- )
\   Busy-wait (with YIELD?) until enough time has passed for one frame.
: _GAME-WAIT-FRAME  ( frame-start-ms -- )
    BEGIN
        MS@ OVER - _GAME-FRAME-MS @ < 
    WHILE
        YIELD?
    REPEAT
    DROP ;

\ =====================================================================
\  §7b — Applet-Mode API
\ =====================================================================
\
\  For games hosted inside the app shell / desk, the host drives
\  timing and painting.  Instead of GAME-RUN the applet calls
\  GAME-INIT once (e.g. from APP.INIT-XT) and GAME-TICK from its
\  APP.TICK-XT callback.

\ GAME-INIT ( -- )
\   Reset accumulator, frame counter, and timing state.
\   Call once before the first GAME-TICK.
: GAME-INIT  ( -- )
    0 _GAME-FRAME !
    0 _GAME-ACCUM !
    0 _GAME-POST-HEAD !
    0 _GAME-POST-TAIL !
    MS@ _GAME-LAST-MS ! ;

\ GAME-TICK ( -- )
\   Compute elapsed time, run fixed-timestep updates, drain deferred.
\   Suitable as an APP.TICK-XT callback (or called from one).
: GAME-TICK  ( -- )
    MS@ DUP _GAME-LAST-MS @ -
    SWAP _GAME-LAST-MS !
    DUP 200 > IF DROP 200 THEN
    _GAME-DO-UPDATE
    _GAME-DRAIN-POSTED
    _GAME-FRAME @ 1+ _GAME-FRAME ! ;

\ =====================================================================
\  §8 — Main Game Loop
\ =====================================================================

\ GAME-RUN ( -- )
\   Enter the game loop.  Blocks until GAME-QUIT is called or the
\   quit callback returns TRUE.
\
\   Sequence per frame:
\     1. Poll all pending input
\     2. Run fixed-timestep updates
\     3. Draw + flush
\     4. Drain deferred actions
\     5. Check quit callback
\     6. Wait for frame boundary
\     7. Increment frame counter
: GAME-RUN  ( -- )
    -1 _GAME-RUNNING !
    GAME-INIT
    BEGIN
        _GAME-RUNNING @
    WHILE
        \ Compute elapsed time since last frame
        MS@ DUP _GAME-LAST-MS @ -       ( now elapsed )
        SWAP _GAME-LAST-MS !             ( elapsed )
        \ Cap elapsed to avoid spiral of death (max 200ms)
        DUP 200 > IF DROP 200 THEN
        \ 1. Input
        _GAME-POLL-INPUT
        \ 2. Update (fixed timestep)
        _GAME-DO-UPDATE
        \ 3. Draw + flush
        _GAME-DO-DRAW
        \ 4. Deferred actions
        _GAME-DRAIN-POSTED
        \ 5. Quit check
        _GAME-QUIT-XT @ ?DUP IF
            EXECUTE IF GAME-QUIT THEN
        THEN
        \ 6. Frame pacing — wait until frame time elapses
        _GAME-LAST-MS @ _GAME-WAIT-FRAME
        \ 7. Advance frame counter
        _GAME-FRAME @ 1+ _GAME-FRAME !
    REPEAT ;

\ =====================================================================
\  §9 — Guard (optional concurrency safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _game-loop-guard

' GAME-FPS!      CONSTANT _game-fps-xt
' GAME-ON-INPUT  CONSTANT _game-on-input-xt
' GAME-ON-UPDATE CONSTANT _game-on-update-xt
' GAME-ON-DRAW   CONSTANT _game-on-draw-xt
' GAME-ON-QUIT   CONSTANT _game-on-quit-xt
' GAME-RUN       CONSTANT _game-run-xt
' GAME-QUIT      CONSTANT _game-quit-xt
' GAME-POST      CONSTANT _game-post-xt
' GAME-INIT      CONSTANT _game-init-xt
' GAME-TICK      CONSTANT _game-tick-xt

: GAME-FPS!      _game-fps-xt      _game-loop-guard WITH-GUARD ;
: GAME-ON-INPUT  _game-on-input-xt _game-loop-guard WITH-GUARD ;
: GAME-ON-UPDATE _game-on-update-xt _game-loop-guard WITH-GUARD ;
: GAME-ON-DRAW   _game-on-draw-xt _game-loop-guard WITH-GUARD ;
: GAME-ON-QUIT   _game-on-quit-xt _game-loop-guard WITH-GUARD ;
: GAME-RUN       _game-run-xt     _game-loop-guard WITH-GUARD ;
: GAME-QUIT      _game-quit-xt    _game-loop-guard WITH-GUARD ;
: GAME-POST      _game-post-xt    _game-loop-guard WITH-GUARD ;
: GAME-INIT      _game-init-xt    _game-loop-guard WITH-GUARD ;
: GAME-TICK      _game-tick-xt    _game-loop-guard WITH-GUARD ;
[THEN] [THEN]
