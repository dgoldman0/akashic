\ =================================================================
\  app.f  —  Standalone TUI Application Lifecycle
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: APP-
\  Depends on: akashic-tui-term-init, akashic-tui-event
\
\  STANDALONE APPLICATION model.  Adds the event-loop layer on top
\  of the shared terminal primitives in term-init.f.  Standalone
\  apps use this module directly: one app, one screen, one event
\  loop.
\
\  This is NOT for applets.  Applets use app-desc.f + app-shell.f,
\  which depend on term-init.f directly (not on this file).
\
\  Public API  (re-exported from term-init.f):
\   APP-INIT       ( w h -- )           Set up terminal + screen
\   APP-SHUTDOWN   ( -- )               Teardown + restore terminal
\   APP-SIZE       ( -- w h )           Current screen dimensions
\   APP-SCREEN     ( -- scr )           Application screen descriptor
\   APP-TITLE!     ( addr len -- )      Set terminal title
\
\  Standalone-only API  (defined here):
\   APP-RUN        ( -- )               Enter event loop (blocks)
\   APP-RUN-FULL   ( init-xt w h -- )   Convenience lifecycle wrapper
\
\  Not reentrant.  APP-RUN-FULL uses CATCH to guarantee cleanup.
\ =================================================================

PROVIDED akashic-tui-app

REQUIRE cogs/term-init.f
REQUIRE event.f

\ =====================================================================
\  §1 — APP-RUN  ( -- )
\ =====================================================================

: APP-RUN  ( -- )
    TUI-EVT-LOOP ;

\ =====================================================================
\  §2 — APP-RUN-FULL  ( init-xt w h -- )
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
\  §3 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _app-guard

' APP-RUN       CONSTANT _app-run-xt
' APP-RUN-FULL  CONSTANT _app-run-full-xt

: APP-RUN       _app-run-xt       _app-guard WITH-GUARD ;
: APP-RUN-FULL  _app-run-full-xt  _app-guard WITH-GUARD ;
[THEN] [THEN]
