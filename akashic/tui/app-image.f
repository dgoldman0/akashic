\ =================================================================
\  app-image.f  —  Binary Image Convenience Wrapper
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: APPI- / _APPI-
\  Depends on: akashic-tui-app, akashic-binimg
\
\  Thin wrapper that integrates binimg.f with the TUI application
\  lifecycle (app.f).  Allows a compiled TUI application to be
\  frozen to a .m64 image and reloaded + launched later.
\
\  All filename arguments are parsed from the input stream
\  (matching binimg convention).
\
\  Public API:
\   APPI-MARK     ( -- )              Snapshot dictionary for image
\   APPI-ENTRY    ( xt -- )           Register app entry point
\   APPI-SAVE     ( "filename" -- ior ) Save image (.m64)
\   APPI-LOAD     ( "filename" -- xt ior ) Load image, return entry
\   APPI-RUN      ( "filename" w h -- ) Load + APP-RUN-FULL
\ =================================================================

PROVIDED akashic-tui-app-image

REQUIRE app.f
REQUIRE ../utils/binimg.f

\ =====================================================================
\  §1 — APPI-MARK  ( -- )
\ =====================================================================
\   Snapshot the dictionary pointer.  Everything compiled after this
\   call becomes part of the saved image segment.

: APPI-MARK  ( -- )
    IMG-MARK ;

\ =====================================================================
\  §2 — APPI-ENTRY  ( xt -- )
\ =====================================================================
\   Register an execution token as the application entry point.
\   The xt must point to a word compiled after APPI-MARK.

: APPI-ENTRY  ( xt -- )
    IMG-ENTRY ;

\ =====================================================================
\  §3 — APPI-SAVE  ( "filename" -- ior )
\ =====================================================================
\   Save everything compiled since APPI-MARK as a .m64 image file.
\   The filename is parsed from the input stream.
\   Returns 0 on success, negative ior on error.
\
\   Typical usage:
\     APPI-MARK
\     : my-app  ( -- )  ... ;
\     ' my-app APPI-ENTRY
\     APPI-SAVE my-app.m64

: APPI-SAVE  ( "filename" -- ior )
    IMG-SAVE ;

\ =====================================================================
\  §4 — APPI-LOAD  ( "filename" -- xt ior )
\ =====================================================================
\   Load a .m64 image that was saved with APPI-SAVE (must have the
\   EXEC flag set via APPI-ENTRY).  Returns the entry-point xt and
\   0 on success, or 0 and a negative ior on error.
\
\   The filename is parsed from the input stream.

: APPI-LOAD  ( "filename" -- xt ior )
    IMG-LOAD-EXEC ;

\ =====================================================================
\  §5 — APPI-RUN  ( w h "filename" -- )
\ =====================================================================
\   One-shot: load a .m64 TUI app image and run it through the full
\   application lifecycle.  The entry xt is passed to APP-RUN-FULL
\   which handles init → execute → event-loop → shutdown.
\
\   Usage:   80 24 APPI-RUN my-app.m64
\
\   On load error, prints a message and aborts (THROW).

-100 CONSTANT _APPI-ERR-LOAD

: APPI-RUN  ( w h "filename" -- )
    IMG-LOAD-EXEC                    ( w h xt ior )
    ?DUP IF
        ." APPI-RUN: load failed (" . ." )" CR
        _APPI-ERR-LOAD THROW
    THEN                             ( w h xt )
    -ROT                             ( xt w h )
    APP-RUN-FULL ;

\ =====================================================================
\  §6 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _appi-guard

' APPI-MARK   CONSTANT _appi-mark-xt
' APPI-ENTRY  CONSTANT _appi-entry-xt
' APPI-SAVE   CONSTANT _appi-save-xt
' APPI-LOAD   CONSTANT _appi-load-xt
' APPI-RUN    CONSTANT _appi-run-xt

: APPI-MARK   _appi-mark-xt   _appi-guard WITH-GUARD ;
: APPI-ENTRY  _appi-entry-xt  _appi-guard WITH-GUARD ;
: APPI-SAVE   _appi-save-xt   _appi-guard WITH-GUARD ;
: APPI-LOAD   _appi-load-xt   _appi-guard WITH-GUARD ;
: APPI-RUN    _appi-run-xt    _appi-guard WITH-GUARD ;
[THEN] [THEN]
