\ =================================================================
\  app.f  —  TUI Application Lifecycle
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: APP- / _APP-
\  Depends on: akashic-tui-ansi, akashic-tui-screen,
\              akashic-tui-event, akashic-tui-focus
\
\  One-call application setup and teardown.  Enters alternate
\  screen, hides cursor, creates a screen buffer, runs the event
\  loop, then restores everything on exit.
\
\  Public API:
\   APP-INIT       ( w h -- )           Set up terminal + screen
\   APP-RUN        ( -- )               Enter event loop (blocks)
\   APP-SHUTDOWN   ( -- )               Teardown + restore terminal
\   APP-SIZE       ( -- w h )           Current screen dimensions
\   APP-SCREEN     ( -- scr )           Application screen descriptor
\   APP-TITLE!     ( addr len -- )      Set terminal title
\   APP-RUN-FULL   ( init-xt w h -- )   Convenience lifecycle wrapper
\
\  Not reentrant.  APP-RUN-FULL uses CATCH to guarantee cleanup.
\ =================================================================

PROVIDED akashic-tui-app

REQUIRE ansi.f
REQUIRE screen.f
REQUIRE event.f
REQUIRE focus.f

\ =====================================================================
\  §1 — State
\ =====================================================================

VARIABLE _APP-SCR          \ Screen descriptor (0 = not initialised)
0 _APP-SCR !

VARIABLE _APP-INITED       \ TRUE after APP-INIT, FALSE after SHUTDOWN
0 _APP-INITED !

\ =====================================================================
\  §2 — APP-INIT  ( w h -- )
\ =====================================================================
\   1. Enter alternate screen buffer
\   2. Hide cursor
\   3. Clear screen
\   4. Create screen buffer (w × h)
\   5. Set as current screen
\   6. Clear focus chain
\   7. Mark as initialised

: APP-INIT  ( w h -- )
    _APP-INITED @ IF 2DROP EXIT THEN   \ idempotent
    ANSI-ALT-ON
    ANSI-CURSOR-OFF
    ANSI-RESET
    ANSI-CLEAR
    ANSI-HOME
    2DUP SCR-NEW              ( w h scr )
    DUP _APP-SCR !
    SCR-USE
    2DROP                     \ consume w h
    FOC-CLEAR
    -1 _APP-INITED ! ;

\ =====================================================================
\  §3 — APP-SHUTDOWN  ( -- )
\ =====================================================================
\   1. Free the screen buffer
\   2. Show cursor
\   3. Reset attributes
\   4. Leave alternate screen
\   5. Move cursor to bottom-left
\   6. Mark as not initialised
\
\   Safe to call even if APP-INIT was never called (no-op).

: APP-SHUTDOWN  ( -- )
    _APP-INITED @ 0= IF EXIT THEN
    _APP-SCR @ ?DUP IF
        SCR-FREE
        0 _APP-SCR !
    THEN
    FOC-CLEAR
    ANSI-RESET
    ANSI-CURSOR-ON
    ANSI-ALT-OFF
    0 _APP-INITED ! ;

\ =====================================================================
\  §4 — APP-RUN  ( -- )
\ =====================================================================

: APP-RUN  ( -- )
    TUI-EVT-LOOP ;

\ =====================================================================
\  §5 — Accessors
\ =====================================================================

\ APP-SCREEN ( -- scr )
: APP-SCREEN  ( -- scr )
    _APP-SCR @ ;

\ APP-SIZE ( -- w h )
\   Returns 0 0 if not initialised.
: APP-SIZE  ( -- w h )
    _APP-SCR @ IF SCR-W SCR-H ELSE 0 0 THEN ;

\ APP-TITLE! ( addr len -- )
: APP-TITLE!  ( addr len -- )
    ANSI-TITLE ;

\ =====================================================================
\  §6 — APP-RUN-FULL  ( init-xt w h -- )
\ =====================================================================
\   Convenience word: init, call user setup, run loop, shutdown.
\   Uses CATCH so that APP-SHUTDOWN always runs even on THROW.

: APP-RUN-FULL  ( init-xt w h -- )
    2DUP APP-INIT              ( init-xt w h )
    2DROP                      ( init-xt )
    ['] EXECUTE CATCH          ( 0 | exn )
    APP-SHUTDOWN
    ?DUP IF THROW THEN ;

\ =====================================================================
\  §7 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _app-guard

' APP-INIT      CONSTANT _app-init-xt
' APP-SHUTDOWN  CONSTANT _app-shutdown-xt
' APP-RUN       CONSTANT _app-run-xt
' APP-SCREEN    CONSTANT _app-screen-xt
' APP-SIZE      CONSTANT _app-size-xt
' APP-TITLE!    CONSTANT _app-title-xt
' APP-RUN-FULL  CONSTANT _app-run-full-xt

: APP-INIT      _app-init-xt      _app-guard WITH-GUARD ;
: APP-SHUTDOWN  _app-shutdown-xt  _app-guard WITH-GUARD ;
: APP-RUN       _app-run-xt       _app-guard WITH-GUARD ;
: APP-SCREEN    _app-screen-xt    _app-guard WITH-GUARD ;
: APP-SIZE      _app-size-xt      _app-guard WITH-GUARD ;
: APP-TITLE!    _app-title-xt     _app-guard WITH-GUARD ;
: APP-RUN-FULL  _app-run-full-xt  _app-guard WITH-GUARD ;
[THEN] [THEN]
