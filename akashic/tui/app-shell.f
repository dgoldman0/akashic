\ =================================================================
\  app-shell.f — TUI Application Shell Runtime
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: ASHELL- / _ASHELL-
\  Depends on: akashic-tui-app, akashic-tui-keys, akashic-tui-screen,
\              akashic-tui-region, akashic-tui-draw,
\              akashic-tui-uidl-tui, akashic-tui-focus
\
\  Headless runtime that owns the terminal, event loop, paint
\  cycle, and UIDL integration.  Apps provide callbacks via an
\  APP-DESC descriptor.  The shell has no UI of its own.
\
\  Lifecycle:
\    1. Terminal init (APP-INIT)
\    2. Root region created
\    3. UIDL document loaded (if provided)
\    4. App init callback
\    5. Initial paint + flush
\    6. Non-blocking event loop:
\       a. KEY-POLL → app event → UIDL dispatch
\       b. Drain deferred actions
\       c. Timer tick → app tick
\       d. Paint: UTUI-PAINT + app paint → SCR-FLUSH
\       e. YIELD?
\    7. App shutdown callback
\    8. UIDL detach + APP-SHUTDOWN
\
\  Public API:
\    ASHELL-RUN       ( desc -- )      Main entry (blocks until quit)
\    ASHELL-QUIT      ( -- )           Signal event loop to exit
\    ASHELL-DIRTY!    ( -- )           Request repaint next frame
\    ASHELL-REGION    ( -- rgn )       Root region
\    ASHELL-TICK-MS!  ( ms -- )        Set tick interval (default 50)
\    ASHELL-POST      ( xt -- )        Enqueue deferred action
\    ASHELL-UIDL?     ( -- flag )      Is a UIDL document loaded?
\    ASHELL-DESC      ( -- desc )      Current app descriptor
\
\  The shell guarantees APP-SHUTDOWN runs even on THROW.
\ =================================================================

PROVIDED akashic-tui-app-shell

REQUIRE app.f
REQUIRE keys.f
REQUIRE screen.f
REQUIRE region.f
REQUIRE draw.f
REQUIRE focus.f
REQUIRE uidl-tui.f
REQUIRE ../utils/term.f
REQUIRE app-desc.f

\ =====================================================================
\  §2 — Shell State
\ =====================================================================

VARIABLE _ASHELL-RGN          \ Root region (0 = not created)
0 _ASHELL-RGN !

VARIABLE _ASHELL-DESC         \ Current app descriptor (0 = not running)
0 _ASHELL-DESC !

VARIABLE _ASHELL-RUNNING      \ Event loop active flag
0 _ASHELL-RUNNING !

VARIABLE _ASHELL-DIRTY        \ Repaint requested flag
0 _ASHELL-DIRTY !

VARIABLE _ASHELL-HAS-UIDL     \ UIDL document loaded flag
0 _ASHELL-HAS-UIDL !

VARIABLE _ASHELL-TICK-MS      \ Tick interval in milliseconds
50 _ASHELL-TICK-MS !

VARIABLE _ASHELL-LAST-TICK    \ MS@ snapshot of last tick
0 _ASHELL-LAST-TICK !

\ --- Toast state ---
CREATE _ASHELL-TOAST-MSG  2 CELLS ALLOT   \ addr + len
0 _ASHELL-TOAST-MSG !
0 _ASHELL-TOAST-MSG CELL+ !

VARIABLE _ASHELL-TOAST-EXPIRY             \ MS@ deadline
0 _ASHELL-TOAST-EXPIRY !

VARIABLE _ASHELL-TOAST-WAS-VIS            \ was-visible flag
0 _ASHELL-TOAST-WAS-VIS !

\ =====================================================================
\  §3 — Deferred Action Queue (FIFO, max 16 entries)
\ =====================================================================

16 CONSTANT _ASHELL-POST-MAX

CREATE _ASHELL-POST-Q  _ASHELL-POST-MAX CELLS ALLOT

VARIABLE _ASHELL-POST-HEAD
0 _ASHELL-POST-HEAD !

VARIABLE _ASHELL-POST-TAIL
0 _ASHELL-POST-TAIL !

: ASHELL-POST  ( xt -- )
    _ASHELL-POST-HEAD @ _ASHELL-POST-TAIL @ -
    _ASHELL-POST-MAX >= IF DROP EXIT THEN
    _ASHELL-POST-HEAD @
    _ASHELL-POST-MAX MOD CELLS _ASHELL-POST-Q + !
    1 _ASHELL-POST-HEAD +! ;

: _ASHELL-DRAIN-POSTED  ( -- )
    BEGIN
        _ASHELL-POST-TAIL @ _ASHELL-POST-HEAD @ <
    WHILE
        _ASHELL-POST-TAIL @
        _ASHELL-POST-MAX MOD CELLS _ASHELL-POST-Q + @
        1 _ASHELL-POST-TAIL +!
        EXECUTE
    REPEAT ;

\ =====================================================================
\  §4 — Public Accessors
\ =====================================================================

\ ASHELL-QUIT ( -- )
\   Signal the event loop to exit after the current iteration.
: ASHELL-QUIT  ( -- )
    0 _ASHELL-RUNNING ! ;

\ ASHELL-DIRTY! ( -- )
\   Mark the screen as needing repaint.
: ASHELL-DIRTY!  ( -- )
    -1 _ASHELL-DIRTY ! ;

\ ASHELL-REGION ( -- rgn )
\   The root region that covers the full screen.
: ASHELL-REGION  ( -- rgn )
    _ASHELL-RGN @ ;

\ ASHELL-TICK-MS! ( ms -- )
\   Set the tick callback interval.
: ASHELL-TICK-MS!  ( ms -- )
    _ASHELL-TICK-MS ! ;

\ ASHELL-UIDL? ( -- flag )
\   True if a UIDL document is currently loaded.
: ASHELL-UIDL?  ( -- flag )
    _ASHELL-HAS-UIDL @ ;

\ ASHELL-DESC ( -- desc )
\   The currently running app descriptor (0 if not running).
: ASHELL-DESC  ( -- desc )
    _ASHELL-DESC @ ;

\ ASHELL-TOAST-VISIBLE? ( -- flag )
\   True if toast message is currently showing.
: ASHELL-TOAST-VISIBLE?  ( -- flag )
    _ASHELL-TOAST-EXPIRY @ MS@ > ;

\ ASHELL-TOAST ( addr u ms -- )
\   Show a toast message for ms milliseconds.
: ASHELL-TOAST  ( addr u ms -- )
    MS@ + _ASHELL-TOAST-EXPIRY !
    _ASHELL-TOAST-MSG 2!
    -1 _ASHELL-TOAST-WAS-VIS !
    ASHELL-DIRTY! ;

\ _ASHELL-DRAW-TOAST ( -- )
\   Render toast overlay centred on bottom row.
: _ASHELL-DRAW-TOAST  ( -- )
    RGN-ROOT
    253 DRW-FG!  236 DRW-BG!  0 DRW-ATTR!
    _ASHELL-TOAST-MSG 2@               ( a u )
    DUP 4 +                            ( a u tw )
    \ Fill background bar:  ( cp row col h w -- )
    32
    SCR-H 1-
    SCR-W 3 PICK - 2/                 ( a u tw 32 row col )
    1  4 PICK
    DRW-FILL-RECT                      ( a u tw )
    \ Centre text:  ( addr len row col w -- )
    SCR-H 1-
    SCR-W 2 PICK - 2/                 ( a u tw row col )
    ROT                                ( a u row col tw )
    DRW-TEXT-CENTER
    DRW-STYLE-RESET ;

\ =====================================================================
\  §5 — Key Event Buffer
\ =====================================================================

CREATE _ASHELL-EV  24 ALLOT     \ 3-cell key event descriptor

\ =====================================================================
\  §6 — Resize Handling
\ =====================================================================

: _ASHELL-ON-RESIZE  ( w h -- )
    SCR-RESIZE
    \ Rebuild root region from new screen dimensions
    _ASHELL-RGN @ ?DUP IF RGN-FREE THEN
    0 0 SCR-H SCR-W RGN-NEW _ASHELL-RGN !
    \ Re-layout UIDL tree if loaded
    _ASHELL-HAS-UIDL @ IF
        UTUI-RELAYOUT
    THEN
    ASHELL-DIRTY! ;

\ =====================================================================
\  §7 — Event Dispatch
\ =====================================================================

\ _ASHELL-DISPATCH-KEY ( ev -- )
\   Route a key event through the app's handler, then UIDL dispatch.
: _ASHELL-DISPATCH-KEY  ( ev -- )
    \ 1. App's event handler gets first crack
    _ASHELL-DESC @ APP.EVENT-XT @ ?DUP IF
        OVER SWAP EXECUTE            ( ev consumed? )
        IF DROP ASHELL-DIRTY! EXIT THEN
    THEN
    \ 2. UIDL dispatch (shortcuts, focused element)
    _ASHELL-HAS-UIDL @ IF
        DUP UTUI-DISPATCH-KEY        ( ev consumed? )
        IF ASHELL-DIRTY! THEN
    THEN
    DROP ;

\ _ASHELL-CHECK-RESIZE ( ev -- )
\   If the event is a resize, handle it.
: _ASHELL-CHECK-RESIZE  ( ev -- )
    DUP @ KEY-T-RESIZE = IF
        DUP 8 + @                    \ width  (code field)
        OVER 16 + @                   \ height (mods field)
        _ASHELL-ON-RESIZE
    THEN
    DROP ;

\ _ASHELL-CHECK-HW-RESIZE ( -- )
\   Poll hardware RESIZED? flag.
: _ASHELL-CHECK-HW-RESIZE  ( -- )
    TERM-RESIZED? IF
        TERM-SIZE _ASHELL-ON-RESIZE
    THEN ;

\ =====================================================================
\  §8 — Timer Tick
\ =====================================================================

VARIABLE _ASHELL-TICK-TMP

: _ASHELL-CHECK-TICK  ( -- )
    _ASHELL-DESC @ APP.TICK-XT @ 0= IF EXIT THEN
    MS@ _ASHELL-TICK-TMP !
    _ASHELL-TICK-TMP @ _ASHELL-LAST-TICK @ -
    _ASHELL-TICK-MS @ >= IF
        _ASHELL-TICK-TMP @ _ASHELL-LAST-TICK !
        _ASHELL-DESC @ APP.TICK-XT @ EXECUTE
        \ If tick caused any UIDL/widget changes, auto-dirty
        _UTUI-NEEDS-PAINT @ IF
            0 _UTUI-NEEDS-PAINT !
            ASHELL-DIRTY!
        THEN
    THEN
    \ Toast expiry: if toast just expired, trigger repaint to clear it
    ASHELL-TOAST-VISIBLE? 0= IF
        _ASHELL-TOAST-WAS-VIS @ IF
            0 _ASHELL-TOAST-WAS-VIS !
            ASHELL-DIRTY!
        THEN
    THEN ;

\ =====================================================================
\  §9 — Paint
\ =====================================================================

: _ASHELL-PAINT  ( -- )
    \ Check UIDL needs-paint flag (set by UIDL-DIRTY! hook)
    _UTUI-NEEDS-PAINT @ IF
        0 _UTUI-NEEDS-PAINT !
        ASHELL-DIRTY!
    THEN
    _ASHELL-DIRTY @ 0= IF EXIT THEN
    0 _ASHELL-DIRTY !
    RGN-ROOT
    \ UIDL elements first (they own the background/structure)
    _ASHELL-HAS-UIDL @ IF
        UTUI-PAINT
    THEN
    \ App's custom widget painting (on top of UIDL)
    _ASHELL-DESC @ APP.PAINT-XT @ ?DUP IF
        EXECUTE
    THEN
    \ Toast overlay (drawn last, on top of everything)
    ASHELL-TOAST-VISIBLE? IF
        _ASHELL-DRAW-TOAST
    THEN
    RGN-ROOT
    SCR-FLUSH ;

\ =====================================================================
\  §10 — Lifecycle: Init
\ =====================================================================

: _ASHELL-SETUP  ( desc -- )
    DUP _ASHELL-DESC !
    \ 1. Terminal init
    DUP APP.WIDTH @ OVER APP.HEIGHT @  APP-INIT
    \ 2. Terminal title
    DUP APP.TITLE-A @ ?DUP IF
        OVER APP.TITLE-U @  APP-TITLE!
    THEN
    \ 3. Root region (full screen)
    0 0 SCR-H SCR-W RGN-NEW _ASHELL-RGN !
    \ 4. UIDL document
    DUP APP.UIDL-A @ ?DUP IF
        OVER APP.UIDL-U @           ( desc uidl-a uidl-u )
        _ASHELL-RGN @               ( desc uidl-a uidl-u rgn )
        UTUI-LOAD                   ( desc flag )
        IF -1 ELSE 0 THEN
        _ASHELL-HAS-UIDL !
    ELSE 0 _ASHELL-HAS-UIDL ! THEN
    \ 5. Prepare runtime state (BEFORE init callback so quit-from-init works)
    -1 _ASHELL-RUNNING !
    MS@ _ASHELL-LAST-TICK !
    \ 6. App init callback
    DUP APP.INIT-XT @ ?DUP IF EXECUTE THEN
    \ 7. Escape sequence timeout
    1 KEY-TIMEOUT!
    \ 8. Initial paint
    ASHELL-DIRTY!
    _ASHELL-PAINT
    DROP ;

\ =====================================================================
\  §11 — Lifecycle: Shutdown
\ =====================================================================

: _ASHELL-TEARDOWN  ( -- )
    \ App shutdown callback
    _ASHELL-DESC @ ?DUP IF
        APP.SHUTDOWN-XT @ ?DUP IF EXECUTE THEN
    THEN
    \ UIDL detach
    _ASHELL-HAS-UIDL @ IF
        UTUI-DETACH
        0 _ASHELL-HAS-UIDL !
    THEN
    \ Free region
    _ASHELL-RGN @ ?DUP IF
        RGN-FREE
        0 _ASHELL-RGN !
    THEN
    \ Terminal teardown
    APP-SHUTDOWN
    \ Reset shell state
    0 _ASHELL-DESC !
    0 _ASHELL-RUNNING !
    0 _ASHELL-DIRTY !
    0 _ASHELL-POST-HEAD !
    0 _ASHELL-POST-TAIL ! ;

\ =====================================================================
\  §12 — Event Loop
\ =====================================================================

: _ASHELL-LOOP  ( -- )
    \ _ASHELL-RUNNING and _ASHELL-LAST-TICK already set by _ASHELL-SETUP
    BEGIN
        _ASHELL-RUNNING @
    WHILE
        \ 1. Non-blocking input poll
        _ASHELL-EV KEY-POLL IF
            \ 1a. Resize events
            _ASHELL-EV _ASHELL-CHECK-RESIZE
            \ 1b. Dispatch key/mouse
            _ASHELL-EV @ KEY-T-RESIZE <> IF
                _ASHELL-EV _ASHELL-DISPATCH-KEY
            THEN
        THEN
        \ 2. Hardware resize poll
        _ASHELL-CHECK-HW-RESIZE
        \ 3. Deferred actions
        _ASHELL-DRAIN-POSTED
        \ 4. Timer tick
        _ASHELL-CHECK-TICK
        \ 5. Paint (only if dirty)
        _ASHELL-PAINT
        \ 6. Cooperative yield
        YIELD?
    REPEAT ;

\ =====================================================================
\  §13 — Main Entry Point
\ =====================================================================

\ ASHELL-RUN ( desc -- )
\   Run an application.  Blocks until ASHELL-QUIT is called or the
\   app's init/event/tick/paint callback THROWs.  Terminal is always
\   restored on exit.
: ASHELL-RUN  ( desc -- )
    ['] _ASHELL-SETUP CATCH ?DUP IF
        \ Setup failed — still try to clean up
        _ASHELL-TEARDOWN
        THROW
    THEN
    ['] _ASHELL-LOOP CATCH
    _ASHELL-TEARDOWN
    ?DUP IF THROW THEN ;

\ =====================================================================
\  §14 — Guard (Concurrency Safety)
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ashell-guard

' ASHELL-RUN     CONSTANT _ashell-run-xt
' ASHELL-QUIT    CONSTANT _ashell-quit-xt
' ASHELL-DIRTY!  CONSTANT _ashell-dirty-xt
' ASHELL-REGION  CONSTANT _ashell-region-xt
' ASHELL-TICK-MS! CONSTANT _ashell-tick-ms-xt
' ASHELL-POST    CONSTANT _ashell-post-xt
' ASHELL-UIDL?   CONSTANT _ashell-uidl-xt
' ASHELL-DESC    CONSTANT _ashell-desc-xt
' ASHELL-TOAST   CONSTANT _ashell-toast-xt
' ASHELL-TOAST-VISIBLE? CONSTANT _ashell-toast-vis-xt

: ASHELL-RUN      _ashell-run-xt      _ashell-guard WITH-GUARD ;
: ASHELL-QUIT     _ashell-quit-xt     _ashell-guard WITH-GUARD ;
: ASHELL-DIRTY!   _ashell-dirty-xt    _ashell-guard WITH-GUARD ;
: ASHELL-REGION   _ashell-region-xt   _ashell-guard WITH-GUARD ;
: ASHELL-TICK-MS! _ashell-tick-ms-xt  _ashell-guard WITH-GUARD ;
: ASHELL-POST     _ashell-post-xt     _ashell-guard WITH-GUARD ;
: ASHELL-UIDL?    _ashell-uidl-xt     _ashell-guard WITH-GUARD ;
: ASHELL-DESC     _ashell-desc-xt     _ashell-guard WITH-GUARD ;
: ASHELL-TOAST    _ashell-toast-xt    _ashell-guard WITH-GUARD ;
: ASHELL-TOAST-VISIBLE? _ashell-toast-vis-xt _ashell-guard WITH-GUARD ;
[THEN] [THEN]
