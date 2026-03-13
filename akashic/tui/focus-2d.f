\ focus-2d.f — Spatial (2D) Focus Navigation
\
\ Plug-in for focus.f.  Adds directional focus movement by scanning
\ the focus chain for the best spatial candidate in the requested
\ direction.  Uses Manhattan distance with a directional bias.
\
\ Also provides keyboard-driven mouse emulation:
\   Alt+Arrow  = move focus spatially (up/down/left/right)
\   Alt+Delete = left click on focused widget
\   Alt+End    = middle click on focused widget
\   Alt+PgDn   = right click on focused widget
\
\ Prefix: F2D- (public), _F2D- (internal)
\ Provider: akashic-tui-focus-2d
\ Dependencies: focus.f, keys.f, widget.f, region.f
\
\ Public API:
\   F2D-UP        ( -- )   Move focus to nearest widget above
\   F2D-DOWN      ( -- )   Move focus to nearest widget below
\   F2D-LEFT      ( -- )   Move focus to nearest widget left
\   F2D-RIGHT     ( -- )   Move focus to nearest widget right
\   F2D-CLICK-L   ( -- )   Simulate left click on focused widget
\   F2D-CLICK-M   ( -- )   Simulate middle click on focused widget
\   F2D-CLICK-R   ( -- )   Simulate right click on focused widget
\   F2D-DISPATCH  ( ev -- flag )  Handle Alt+Arrow/click keys; 0 if not ours

PROVIDED akashic-tui-focus-2d

REQUIRE focus.f
REQUIRE keys.f
REQUIRE widget.f
REQUIRE region.f

\ =====================================================================
\  §1 — Mouse-Button Constants
\ =====================================================================

1 CONSTANT F2D-BTN-LEFT
2 CONSTANT F2D-BTN-MID
3 CONSTANT F2D-BTN-RIGHT

\ =====================================================================
\  §2 — Internal State
\ =====================================================================

VARIABLE _F2D-BEST        \ Best candidate widget found so far
VARIABLE _F2D-SCORE       \ Best score (lower is better)
VARIABLE _F2D-CR          \ Current widget center-row
VARIABLE _F2D-CC          \ Current widget center-col

\ Synthetic mouse-event buffer (3 cells = 24 bytes)
CREATE _F2D-MEV  24 ALLOT

\ =====================================================================
\  §3 — Center-Point Calculation
\ =====================================================================

\ Compute center-point of a widget's region.
: _F2D-CENTER  ( widget -- row col )
    WDG-REGION
    DUP RGN-ROW OVER RGN-H 2 / +
    SWAP
    DUP RGN-COL SWAP RGN-W 2 / + ;

\ =====================================================================
\  §4 — Directional Scan Core
\ =====================================================================

\ Direction predicates — test whether candidate is in the right
\ direction relative to the current focus center.
\ Each returns ( cand-row cand-col -- cand-row cand-col flag )

: _F2D-IS-ABOVE?  ( cr cc -- cr cc flag )
    OVER _F2D-CR @ < ;

: _F2D-IS-BELOW?  ( cr cc -- cr cc flag )
    OVER _F2D-CR @ > ;

: _F2D-IS-LEFT?   ( cr cc -- cr cc flag )
    DUP _F2D-CC @ < ;

: _F2D-IS-RIGHT?  ( cr cc -- cr cc flag )
    DUP _F2D-CC @ > ;

\ Manhattan distance with directional bias.
\ Primary axis distance is weighted 1x, cross-axis 2x.
\ This prefers candidates that are strongly in the requested direction
\ over ones that are slightly in-direction but far off-axis.
\
\ Vertical score:   abs(dr) + 2*abs(dc)
\ Horizontal score: 2*abs(dr) + abs(dc)

: _F2D-SCORE-V  ( cand-row cand-col -- score )
    _F2D-CC @ - ABS 2 *          \ 2 * |delta-col|
    SWAP _F2D-CR @ - ABS +  ;    \ + |delta-row|

: _F2D-SCORE-H  ( cand-row cand-col -- score )
    _F2D-CC @ - ABS              \ |delta-col|
    SWAP _F2D-CR @ - ABS 2 * + ; \ + 2 * |delta-row|

\ The generic scan word.  Takes two xts:
\   dir-xt  ( cand-row cand-col -- cand-row cand-col flag )
\   score-xt ( cand-row cand-col -- score )
\ Called once per widget via FOC-EACH.

VARIABLE _F2D-DIR-XT
VARIABLE _F2D-SCORE-XT

VARIABLE _F2D-CAND          \ Widget currently being examined

: _F2D-SCAN-ONE  ( widget -- )
    DUP FOC-GET = IF DROP EXIT THEN
    DUP WDG-VISIBLE? 0= IF DROP EXIT THEN

    DUP _F2D-CAND !
    _F2D-CENTER                          ( cand-row cand-col )

    _F2D-DIR-XT @ EXECUTE               ( cand-row cand-col flag )
    0= IF 2DROP EXIT THEN

    _F2D-SCORE-XT @ EXECUTE             ( score )
    DUP _F2D-SCORE @ < IF
        _F2D-SCORE !
        _F2D-CAND @ _F2D-BEST !
    ELSE DROP THEN ;

: _F2D-SCAN  ( dir-xt score-xt -- )
    _F2D-SCORE-XT !
    _F2D-DIR-XT !
    FOC-GET DUP 0= IF DROP EXIT THEN
    _F2D-CENTER _F2D-CC ! _F2D-CR !
    0 _F2D-BEST !
    32767 _F2D-SCORE !
    ['] _F2D-SCAN-ONE FOC-EACH
    _F2D-BEST @ ?DUP IF FOC-SET THEN ;

\ =====================================================================
\  §5 — Public Directional Words
\ =====================================================================

: F2D-UP     ( -- )  ['] _F2D-IS-ABOVE? ['] _F2D-SCORE-V _F2D-SCAN ;
: F2D-DOWN   ( -- )  ['] _F2D-IS-BELOW? ['] _F2D-SCORE-V _F2D-SCAN ;
: F2D-LEFT   ( -- )  ['] _F2D-IS-LEFT?  ['] _F2D-SCORE-H _F2D-SCAN ;
: F2D-RIGHT  ( -- )  ['] _F2D-IS-RIGHT? ['] _F2D-SCORE-H _F2D-SCAN ;

\ =====================================================================
\  §6 — Keyboard-Driven Mouse Emulation
\ =====================================================================

\ Build a synthetic mouse event at the center of the focused widget.
\ _F2D-MEV: +0 = type (KEY-T-MOUSE), +8 = button, +16 = mods (0)
\ Also writes KEY-MOUSE-X / KEY-MOUSE-Y globals from keys.f.

: _F2D-SYNTH-CLICK  ( btn -- )
    FOC-GET DUP 0= IF 2DROP EXIT THEN
    _F2D-CENTER                    ( btn row col )
    KEY-MOUSE-X !                  ( btn row )
    KEY-MOUSE-Y !                  ( btn )
    KEY-T-MOUSE _F2D-MEV !        \ type = mouse
    _F2D-MEV 8 + !                \ code = button
    0 _F2D-MEV 16 + !             \ mods = 0
    _F2D-MEV FOC-GET WDG-HANDLE DROP ;

: F2D-CLICK-L  ( -- )  F2D-BTN-LEFT  _F2D-SYNTH-CLICK ;
: F2D-CLICK-M  ( -- )  F2D-BTN-MID   _F2D-SYNTH-CLICK ;
: F2D-CLICK-R  ( -- )  F2D-BTN-RIGHT _F2D-SYNTH-CLICK ;

\ =====================================================================
\  §7 — Key Dispatch
\ =====================================================================

\ F2D-DISPATCH ( ev -- flag )
\ Checks if the event is one of our Alt+Arrow / Alt+click combos.
\ Returns -1 (true) if handled, 0 if not ours.

: F2D-DISPATCH  ( ev -- flag )
    DUP KEY-IS-SPECIAL? 0= IF DROP 0 EXIT THEN
    DUP KEY-HAS-ALT?    0= IF DROP 0 EXIT THEN

    DUP KEY-CODE@
    DUP KEY-UP    = IF 2DROP F2D-UP     -1 EXIT THEN
    DUP KEY-DOWN  = IF 2DROP F2D-DOWN   -1 EXIT THEN
    DUP KEY-LEFT  = IF 2DROP F2D-LEFT   -1 EXIT THEN
    DUP KEY-RIGHT = IF 2DROP F2D-RIGHT  -1 EXIT THEN
    DUP KEY-DEL   = IF 2DROP F2D-CLICK-L -1 EXIT THEN
    DUP KEY-END   = IF 2DROP F2D-CLICK-M -1 EXIT THEN
    DUP KEY-PGDN  = IF 2DROP F2D-CLICK-R -1 EXIT THEN
    2DROP 0 ;

\ =====================================================================
\  §8 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _f2d-guard

' F2D-UP        CONSTANT _f2d-up-xt
' F2D-DOWN      CONSTANT _f2d-down-xt
' F2D-LEFT      CONSTANT _f2d-left-xt
' F2D-RIGHT     CONSTANT _f2d-right-xt
' F2D-CLICK-L   CONSTANT _f2d-clickl-xt
' F2D-CLICK-M   CONSTANT _f2d-clickm-xt
' F2D-CLICK-R   CONSTANT _f2d-clickr-xt
' F2D-DISPATCH  CONSTANT _f2d-dispatch-xt

: F2D-UP        _f2d-up-xt        _f2d-guard WITH-GUARD ;
: F2D-DOWN      _f2d-down-xt      _f2d-guard WITH-GUARD ;
: F2D-LEFT      _f2d-left-xt      _f2d-guard WITH-GUARD ;
: F2D-RIGHT     _f2d-right-xt     _f2d-guard WITH-GUARD ;
: F2D-CLICK-L   _f2d-clickl-xt    _f2d-guard WITH-GUARD ;
: F2D-CLICK-M   _f2d-clickm-xt    _f2d-guard WITH-GUARD ;
: F2D-CLICK-R   _f2d-clickr-xt    _f2d-guard WITH-GUARD ;
: F2D-DISPATCH  _f2d-dispatch-xt  _f2d-guard WITH-GUARD ;
[THEN] [THEN]
