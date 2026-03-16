\ =================================================================
\  term-init.f — Shared Terminal Initialisation Primitives
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: APP- / _APP-
\  Depends on: akashic-tui-ansi, akashic-tui-screen,
\              akashic-tui-focus
\
\  Low-level terminal ownership: alternate screen, screen buffer,
\  cursor visibility, focus chain.  Used by both standalone apps
\  (app.f → APP-RUN / APP-RUN-FULL) and the applet shell
\  (app-shell.f → ASHELL-RUN).
\
\  Extracted from the former monolithic app.f so that app-shell.f
\  no longer depends on app.f and its event-loop machinery.
\
\  Public API:
\   APP-INIT       ( w h -- )       Set up terminal + screen buffer
\   APP-SHUTDOWN   ( -- )           Teardown + restore terminal
\   APP-SCREEN     ( -- scr )       Application screen descriptor
\   APP-SIZE       ( -- w h )       Current screen dimensions
\   APP-TITLE!     ( addr len -- )  Set terminal title
\
\  Not reentrant.  A single terminal session is assumed.
\ =================================================================

PROVIDED akashic-tui-term-init

REQUIRE ../ansi.f
REQUIRE ../screen.f
REQUIRE ../focus.f
REQUIRE ../../utils/term.f

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
    \ Auto-size: if both dimensions are 0, use hardware terminal size.
    OVER 0= OVER 0= AND IF
        2DROP TERM-SIZE
    THEN
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
\  §4 — Accessors
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
\  §5 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _tinit-guard

' APP-INIT      CONSTANT _tinit-init-xt
' APP-SHUTDOWN  CONSTANT _tinit-shutdown-xt
' APP-SCREEN    CONSTANT _tinit-screen-xt
' APP-SIZE      CONSTANT _tinit-size-xt
' APP-TITLE!    CONSTANT _tinit-title-xt

: APP-INIT      _tinit-init-xt      _tinit-guard WITH-GUARD ;
: APP-SHUTDOWN  _tinit-shutdown-xt  _tinit-guard WITH-GUARD ;
: APP-SCREEN    _tinit-screen-xt    _tinit-guard WITH-GUARD ;
: APP-SIZE      _tinit-size-xt      _tinit-guard WITH-GUARD ;
: APP-TITLE!    _tinit-title-xt     _tinit-guard WITH-GUARD ;
[THEN] [THEN]
