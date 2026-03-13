\ =================================================================
\  toast.f  —  Transient Notification Widget
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TST- / _TST-
\  Depends on: akashic-tui-draw, akashic-tui-box, akashic-tui-region
\
\  Brief popup messages that auto-dismiss after a timeout.
\  Rendered as a bordered box at a configurable anchor position.
\
\  Only one toast is visible at a time.  Showing a new toast
\  replaces the current one.  The caller must call TST-TICK from
\  the event-loop tick callback to drive the auto-dismiss timer.
\
\  The toast is a singleton — it uses module-level state rather than
\  a widget descriptor, because it doesn't participate in the focus
\  chain or receive key events.
\
\  Public API:
\   TST-SHOW        ( msg-a msg-u timeout-ms -- )
\   TST-DISMISS     ( -- )
\   TST-TICK        ( -- )
\   TST-DRAW        ( -- )
\   TST-POSITION!   ( row col -- )
\   TST-STYLE!      ( fg bg box-style -- )
\   TST-VISIBLE?    ( -- flag )
\ =================================================================

PROVIDED akashic-tui-toast

REQUIRE ../draw.f
REQUIRE ../box.f
REQUIRE ../region.f

\ =====================================================================
\  §1 — State variables
\ =====================================================================

VARIABLE _TST-MSG-A         0 _TST-MSG-A !
VARIABLE _TST-MSG-L         0 _TST-MSG-L !
VARIABLE _TST-DEADLINE      0 _TST-DEADLINE !    \ MS@ value at which to dismiss
VARIABLE _TST-ACTIVE        0 _TST-ACTIVE !      \ TRUE while visible
VARIABLE _TST-ANCHOR-ROW    0 _TST-ANCHOR-ROW !  \ anchor row (0 = auto bottom-2)
VARIABLE _TST-ANCHOR-COL    0 _TST-ANCHOR-COL !  \ anchor col (0 = auto right-align)
VARIABLE _TST-FG            7 _TST-FG !          \ default: white
VARIABLE _TST-BG            0 _TST-BG !          \ default: black
VARIABLE _TST-BOX           0 _TST-BOX !         \ default: BOX-SINGLE (set at first use)
VARIABLE _TST-BOX-INIT      0 _TST-BOX-INIT !    \ lazy init flag for box style

\ =====================================================================
\  §2 — TST-SHOW  ( msg-a msg-u timeout-ms -- )
\ =====================================================================
\   Display a toast message.  Replaces any current toast.
\   timeout-ms is the display duration in milliseconds.

: TST-SHOW  ( msg-a msg-u timeout-ms -- )
    MS@ + _TST-DEADLINE !
    _TST-MSG-L !
    _TST-MSG-A !
    -1 _TST-ACTIVE ! ;

\ =====================================================================
\  §3 — TST-DISMISS  ( -- )
\ =====================================================================

: TST-DISMISS  ( -- )
    0 _TST-ACTIVE !
    0 _TST-MSG-L ! ;

\ =====================================================================
\  §4 — TST-TICK  ( -- )
\ =====================================================================
\   Called from the event loop tick handler.  If a toast is active
\   and its deadline has passed, dismiss it.

: TST-TICK  ( -- )
    _TST-ACTIVE @ 0= IF EXIT THEN
    MS@ _TST-DEADLINE @ >= IF
        TST-DISMISS
    THEN ;

\ =====================================================================
\  §5 — TST-DRAW  ( -- )
\ =====================================================================
\   Render the current toast to the screen.  Should be called after
\   all widgets have drawn (overlay phase).  Does nothing if no
\   toast is active.
\
\   The toast is a bordered box containing the message text.
\   Box dimensions: width = msg-len + 4 (border + 1 padding each side),
\   height = 3 (top border, text row, bottom border).
\
\   Position: if anchor is (0,0), auto-positions at bottom-right
\   of the current screen.

: _TST-ENSURE-BOX  ( -- )
    _TST-BOX-INIT @ IF EXIT THEN
    BOX-ROUND _TST-BOX !
    -1 _TST-BOX-INIT ! ;

: TST-DRAW  ( -- )
    _TST-ACTIVE @ 0= IF EXIT THEN
    _TST-MSG-L @ 0= IF EXIT THEN

    _TST-ENSURE-BOX

    \ Compute box dimensions
    _TST-MSG-L @ 4 +                     ( box-w )
    3                                     ( box-w box-h )

    \ Compute position
    _TST-ANCHOR-ROW @ ?DUP IF            ( box-w box-h row )
    ELSE
        SCR-H OVER -                      ( box-w box-h row )  \ bottom-aligned
    THEN
    >R                                    ( box-w box-h   R: row )
    _TST-ANCHOR-COL @ ?DUP IF            ( box-w box-h col )
    ELSE
        OVER SCR-W SWAP -                 ( box-w box-h col )  \ right-aligned
    THEN
    >R                                    ( box-w box-h   R: row col )

    \ Save clip state, go root
    RGN-ROOT

    \ Draw background fill (clear area under box)
    _TST-BG @ DRW-BG!
    _TST-FG @ DRW-FG!
    0 DRW-ATTR!
    32 R> R>                              ( box-w box-h space col row )
    ROT                                   ( box-w space col row box-h )
    >R >R >R                              ( box-w space  R: box-h row col )
    \ Stack: box-w space ; R: box-h row col
    \ DRW-FILL-RECT ( cp row col h w -- )
    R> R> R>                              ( box-w space box-h row col )
    \ rearrange: cp=space row col h=box-h w=box-w
    >R >R                                 ( box-w space box-h   R: row col )
    ROT                                   ( space box-h box-w   R: row col )
    >R >R                                 ( space   R: row col box-h box-w )
    R> R> R> R>                           ( space box-w box-h col row )
    SWAP >R SWAP >R                       ( space row col  R: box-w box-h )
    R> R>                                 ( space row col box-h box-w )
    DRW-FILL-RECT                         ( )

    \ Re-derive row, col, box-h, box-w
    \ We need them again for the box border and text.
    \ Recompute from state:
    _TST-MSG-L @ 4 +                     ( box-w )
    3                                     ( box-w box-h=3 )
    _TST-ANCHOR-ROW @ ?DUP 0= IF SCR-H 3 - THEN  ( box-w box-h row )
    _TST-ANCHOR-COL @ ?DUP 0= IF
        SCR-W 3 PICK -                    ( box-w box-h row col )
    THEN

    \ Draw box border: BOX-DRAW ( style row col h w -- )
    >R >R                                 ( box-w box-h   R: row col )
    _TST-BOX @                            ( box-w box-h style )
    R> R>                                 ( box-w box-h style col row )
    SWAP >R SWAP R>                       ( box-w style row col box-h )
    \ Stack: box-w style row col box-h
    \ Need: style row col box-h box-w
    4 ROLL                                ( style row col box-h box-w )
    BOX-DRAW                              ( )

    \ Draw message text inside box
    _TST-ANCHOR-ROW @ ?DUP 0= IF SCR-H 3 - THEN 1+  ( text-row )
    _TST-ANCHOR-COL @ ?DUP 0= IF
        SCR-W _TST-MSG-L @ 4 + -         ( text-row base-col )
    THEN 2 +                              ( text-row text-col )
    _TST-MSG-A @ _TST-MSG-L @            ( text-row text-col msg-a msg-u )
    2SWAP SWAP                            ( msg-a msg-u row col )
    \ DRW-TEXT ( addr len row col -- )
    DRW-TEXT ;

\ =====================================================================
\  §6 — Configuration
\ =====================================================================

: TST-POSITION!  ( row col -- )
    _TST-ANCHOR-COL !
    _TST-ANCHOR-ROW ! ;

: TST-STYLE!  ( fg bg box-style -- )
    _TST-BOX !
    _TST-BG !
    _TST-FG !
    -1 _TST-BOX-INIT ! ;  \ mark box as explicitly set

: TST-VISIBLE?  ( -- flag )
    _TST-ACTIVE @ ;

\ =====================================================================
\  §7 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _tst-guard

' TST-SHOW      CONSTANT _tst-show-xt
' TST-DISMISS   CONSTANT _tst-dismiss-xt
' TST-TICK      CONSTANT _tst-tick-xt
' TST-DRAW      CONSTANT _tst-draw-xt
' TST-POSITION! CONSTANT _tst-position-xt
' TST-STYLE!    CONSTANT _tst-style-xt
' TST-VISIBLE?  CONSTANT _tst-visible-xt

: TST-SHOW      _tst-show-xt      _tst-guard WITH-GUARD ;
: TST-DISMISS   _tst-dismiss-xt   _tst-guard WITH-GUARD ;
: TST-TICK      _tst-tick-xt      _tst-guard WITH-GUARD ;
: TST-DRAW      _tst-draw-xt      _tst-guard WITH-GUARD ;
: TST-POSITION! _tst-position-xt  _tst-guard WITH-GUARD ;
: TST-STYLE!    _tst-style-xt     _tst-guard WITH-GUARD ;
: TST-VISIBLE?  _tst-visible-xt   _tst-guard WITH-GUARD ;
[THEN] [THEN]
