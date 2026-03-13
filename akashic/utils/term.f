\ =================================================================
\  term.f  —  Terminal Geometry Utilities
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TERM- / _TERM-
\  No dependencies (uses BIOS UART Geometry words directly).
\
\  Wraps the BIOS UART Geometry register words (COLS, ROWS,
\  TERMSIZE, RESIZED?, RESIZE-DENIED?, RESIZE-REQUEST) behind a
\  consistent TERM- prefix and adds derived convenience words for
\  centering, clamping, and resize-with-timeout.
\
\  BIOS words used (from UART Geometry MMIO at 0xFFFF_FF00_0000_0010):
\    COLS             ( -- n )          Read column count (16-bit)
\    ROWS             ( -- n )          Read row count (16-bit)
\    TERMSIZE         ( -- cols rows )  Read both dimensions
\    RESIZED?         ( -- flag )       Check & clear RESIZED flag (W1C)
\    RESIZE-DENIED?   ( -- flag )       Check & clear REQ_DENIED flag
\    RESIZE-REQUEST   ( cols rows -- )  Write REQ_COLS/REQ_ROWS + trigger
\
\  Public API:
\   TERM-W           ( -- n )               Current width (columns)
\   TERM-H           ( -- n )               Current height (rows)
\   TERM-SIZE        ( -- w h )             Current dimensions
\   TERM-AREA        ( -- n )               w * h
\   TERM-RESIZED?    ( -- flag )            Resize occurred? (clears flag)
\   TERM-RESIZE      ( w h -- ior )         Request resize with timeout
\   TERM-FIT?        ( w h -- flag )        Both fit within terminal?
\   TERM-CLAMP       ( w h -- w' h' )       Clamp to terminal bounds
\   TERM-CENTER      ( w h -- col row )     Center coords for a rect
\   TERM-SAVE        ( -- w h )             Snapshot current dimensions
\   TERM-CHANGED?    ( old-w old-h -- flag ) Size changed since snapshot?
\ =================================================================

PROVIDED akashic-term

\ =====================================================================
\  §1 — Direct BIOS Wrappers
\ =====================================================================

\ TERM-W ( -- n )  Current terminal width in columns.
: TERM-W  ( -- n )
    COLS ;

\ TERM-H ( -- n )  Current terminal height in rows.
: TERM-H  ( -- n )
    ROWS ;

\ TERM-SIZE ( -- w h )  Current terminal dimensions.
: TERM-SIZE  ( -- w h )
    TERMSIZE ;

\ TERM-RESIZED? ( -- flag )
\   Check if a resize has occurred since the last check.
\   Clears the hardware RESIZED flag (write-1-to-clear).
: TERM-RESIZED?  ( -- flag )
    RESIZED? ;

\ =====================================================================
\  §2 — Derived Geometry Words
\ =====================================================================

\ TERM-AREA ( -- n )  Total cells (width × height).
: TERM-AREA  ( -- n )
    TERM-SIZE * ;

\ TERM-FIT? ( w h -- flag )
\   TRUE if a w×h rectangle fits within the current terminal.
: TERM-FIT?  ( w h -- flag )
    TERM-H <= >R
    TERM-W <= R> AND ;

\ TERM-CLAMP ( w h -- w' h' )
\   Clamp dimensions to current terminal bounds.
: TERM-CLAMP  ( w h -- w' h' )
    TERM-H MIN SWAP
    TERM-W MIN SWAP ;

\ TERM-CENTER ( w h -- col row )
\   Compute top-left coordinates to center a w×h rectangle.
\   Uses integer division; result is 0-based.
: TERM-CENTER  ( w h -- col row )
    TERM-H OVER - 2 / >R          ( w h   R: row )
    DROP                            ( w )
    TERM-W OVER - 2 /              ( w col )
    NIP R> ;                        ( col row )

\ =====================================================================
\  §3 — Snapshot & Change Detection
\ =====================================================================

\ TERM-SAVE ( -- w h )
\   Return current dimensions for later comparison.
: TERM-SAVE  ( -- w h )
    TERM-SIZE ;

\ TERM-CHANGED? ( old-w old-h -- flag )
\   Compare saved dimensions against current; TRUE if different.
: TERM-CHANGED?  ( old-w old-h -- flag )
    TERM-H <> >R
    TERM-W <> R> OR ;

\ =====================================================================
\  §4 — Resize Request with Timeout
\ =====================================================================
\
\  TERM-RESIZE requests a terminal resize from the host and polls
\  for acceptance or denial.  Returns:
\    0  — accepted (COLS/ROWS updated)
\   -1  — denied by host
\   -2  — timeout (no response within deadline)
\
\  The timeout is in milliseconds.  Default: 2000 ms.

VARIABLE _TERM-RESIZE-TIMEOUT
2000 _TERM-RESIZE-TIMEOUT !

\ TERM-RESIZE-TIMEOUT! ( ms -- )  Set resize poll timeout.
: TERM-RESIZE-TIMEOUT!  ( ms -- )
    _TERM-RESIZE-TIMEOUT ! ;

\ TERM-RESIZE ( w h -- ior )
\   Request the host to resize the terminal to w columns × h rows.
\   Blocks (polling) until RESIZED?, RESIZE-DENIED?, or timeout.
\   ior: 0 = accepted, -1 = denied, -2 = timeout.
: TERM-RESIZE  ( w h -- ior )
    2DUP RESIZE-REQUEST              ( w h -- )  \ sends req to host
    MS@ _TERM-RESIZE-TIMEOUT @ +    ( deadline )
    BEGIN
        RESIZED? IF
            DROP 0 EXIT              \ accepted
        THEN
        RESIZE-DENIED? IF
            DROP -1 EXIT             \ denied
        THEN
        MS@ OVER >=                  ( deadline past? )
    UNTIL
    DROP -2 ;                        \ timeout

\ =====================================================================
\  §5 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _term-guard

' TERM-W         CONSTANT _term-w-xt
' TERM-H         CONSTANT _term-h-xt
' TERM-SIZE      CONSTANT _term-size-xt
' TERM-AREA      CONSTANT _term-area-xt
' TERM-RESIZED?  CONSTANT _term-resized-xt
' TERM-RESIZE    CONSTANT _term-resize-xt
' TERM-FIT?      CONSTANT _term-fit-xt
' TERM-CLAMP     CONSTANT _term-clamp-xt
' TERM-CENTER    CONSTANT _term-center-xt
' TERM-SAVE      CONSTANT _term-save-xt
' TERM-CHANGED?  CONSTANT _term-changed-xt

: TERM-W         _term-w-xt         _term-guard WITH-GUARD ;
: TERM-H         _term-h-xt         _term-guard WITH-GUARD ;
: TERM-SIZE      _term-size-xt      _term-guard WITH-GUARD ;
: TERM-AREA      _term-area-xt      _term-guard WITH-GUARD ;
: TERM-RESIZED?  _term-resized-xt   _term-guard WITH-GUARD ;
: TERM-RESIZE    _term-resize-xt    _term-guard WITH-GUARD ;
: TERM-FIT?      _term-fit-xt       _term-guard WITH-GUARD ;
: TERM-CLAMP     _term-clamp-xt     _term-guard WITH-GUARD ;
: TERM-CENTER    _term-center-xt    _term-guard WITH-GUARD ;
: TERM-SAVE      _term-save-xt      _term-guard WITH-GUARD ;
: TERM-CHANGED?  _term-changed-xt   _term-guard WITH-GUARD ;
[THEN] [THEN]
