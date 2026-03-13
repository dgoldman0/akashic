\ =================================================================
\  event.f  —  TUI Event Loop & Dispatch
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TUI-EVT- / _TUI-EVT-
\  Depends on: akashic-tui-keys, akashic-tui-screen, akashic-tui-focus
\
\  The main event loop that ties input, rendering, and timers
\  together.  Polls for input via KEY-POLL, dispatches events
\  through the focused widget chain, triggers timer callbacks,
\  redraws dirty widgets via FOC-EACH, and calls SCR-FLUSH to
\  update the display.
\
\  Public API:
\   TUI-EVT-LOOP       ( -- )        Enter event loop (blocks until quit)
\   TUI-EVT-QUIT       ( -- )        Signal loop to exit
\   TUI-EVT-TICK-MS!   ( ms -- )     Set tick interval (default: 100)
\   TUI-EVT-ON-TICK    ( xt -- )     Register tick callback: ( -- )
\   TUI-EVT-ON-RESIZE  ( xt -- )     Register resize callback: ( w h -- )
\   TUI-EVT-ON-KEY     ( xt -- )     Register global key handler: ( ev -- f )
\   TUI-EVT-POST       ( xt -- )     Post deferred action for next iter
\   TUI-EVT-REDRAW     ( -- )        Request full redraw next iteration
\
\  Not reentrant.  Uses BIOS MS@ for timer ticks.
\ =================================================================

PROVIDED akashic-tui-event

REQUIRE keys.f
REQUIRE screen.f
REQUIRE focus.f

\ =====================================================================
\  §1 — State Variables
\ =====================================================================

VARIABLE _TUI-EVT-RUNNING       \ Loop running flag (TRUE = active)
0 _TUI-EVT-RUNNING !

VARIABLE _TUI-EVT-TICK-MS       \ Tick interval in milliseconds
100 _TUI-EVT-TICK-MS !

VARIABLE _TUI-EVT-LAST-TICK     \ MS@ snapshot of last tick
0 _TUI-EVT-LAST-TICK !

VARIABLE _TUI-EVT-ON-TICK-XT    \ Tick callback xt (0=none)
0 _TUI-EVT-ON-TICK-XT !

VARIABLE _TUI-EVT-ON-RESIZE-XT  \ Resize callback xt (0=none)
0 _TUI-EVT-ON-RESIZE-XT !

VARIABLE _TUI-EVT-ON-KEY-XT     \ Global key handler xt (0=none)
0 _TUI-EVT-ON-KEY-XT !

VARIABLE _TUI-EVT-REDRAW-FLAG   \ Non-zero = full redraw requested
0 _TUI-EVT-REDRAW-FLAG !

\ =====================================================================
\  §2 — Key Event Buffer
\ =====================================================================

\ Key event is 3 cells (24 bytes): type, code/char, modifiers
CREATE _TUI-EVT-KEY-BUF 24 ALLOT

\ =====================================================================
\  §3 — Deferred Action Queue (FIFO, max 8 entries)
\ =====================================================================

8 CONSTANT _TUI-EVT-POST-MAX

CREATE _TUI-EVT-POST-Q  _TUI-EVT-POST-MAX CELLS ALLOT

VARIABLE _TUI-EVT-POST-HEAD     \ Next slot to write
0 _TUI-EVT-POST-HEAD !

VARIABLE _TUI-EVT-POST-TAIL     \ Next slot to read
0 _TUI-EVT-POST-TAIL !

\ TUI-EVT-POST ( xt -- )
\   Enqueue a deferred action.  Silently drops if queue is full.
: TUI-EVT-POST  ( xt -- )
    _TUI-EVT-POST-HEAD @
    _TUI-EVT-POST-TAIL @ -
    _TUI-EVT-POST-MAX >= IF DROP EXIT THEN
    _TUI-EVT-POST-HEAD @
    _TUI-EVT-POST-MAX MOD CELLS _TUI-EVT-POST-Q + !
    _TUI-EVT-POST-HEAD @ 1+ _TUI-EVT-POST-HEAD ! ;

\ _TUI-EVT-DRAIN-POSTED ( -- )
\   Execute all queued deferred actions, oldest first.
: _TUI-EVT-DRAIN-POSTED  ( -- )
    BEGIN
        _TUI-EVT-POST-TAIL @ _TUI-EVT-POST-HEAD @ < 
    WHILE
        _TUI-EVT-POST-TAIL @
        _TUI-EVT-POST-MAX MOD CELLS _TUI-EVT-POST-Q + @
        _TUI-EVT-POST-TAIL @ 1+ _TUI-EVT-POST-TAIL !
        EXECUTE
    REPEAT ;

\ =====================================================================
\  §4 — Public Configuration Words
\ =====================================================================

\ TUI-EVT-TICK-MS! ( ms -- )
: TUI-EVT-TICK-MS!  ( ms -- )
    _TUI-EVT-TICK-MS ! ;

\ TUI-EVT-ON-TICK ( xt -- )
: TUI-EVT-ON-TICK  ( xt -- )
    _TUI-EVT-ON-TICK-XT ! ;

\ TUI-EVT-ON-RESIZE ( xt -- )
: TUI-EVT-ON-RESIZE  ( xt -- )
    _TUI-EVT-ON-RESIZE-XT ! ;

\ TUI-EVT-ON-KEY ( xt -- )
: TUI-EVT-ON-KEY  ( xt -- )
    _TUI-EVT-ON-KEY-XT ! ;

\ TUI-EVT-QUIT ( -- )
: TUI-EVT-QUIT  ( -- )
    0 _TUI-EVT-RUNNING ! ;

\ TUI-EVT-REDRAW ( -- )
: TUI-EVT-REDRAW  ( -- )
    -1 _TUI-EVT-REDRAW-FLAG ! ;

\ =====================================================================
\  §5 — Timer Tick Check
\ =====================================================================

VARIABLE _TUI-EVT-TMP

\ _TUI-EVT-CHECK-TICK ( -- )
\   If enough time has elapsed since last tick, call tick callback.
: _TUI-EVT-CHECK-TICK  ( -- )
    _TUI-EVT-ON-TICK-XT @ 0= IF EXIT THEN
    MS@ _TUI-EVT-TMP !
    _TUI-EVT-TMP @  _TUI-EVT-LAST-TICK @  -
    _TUI-EVT-TICK-MS @ >= IF
        _TUI-EVT-TMP @ _TUI-EVT-LAST-TICK !
        _TUI-EVT-ON-TICK-XT @ EXECUTE
    THEN ;

\ =====================================================================
\  §6 — Dirty Widget Redraw
\ =====================================================================

\ _TUI-EVT-DRAW-ONE ( widget -- )
\   Draw a single widget if it is dirty.
: _TUI-EVT-DRAW-ONE  ( widget -- )
    DUP WDG-DIRTY? IF WDG-DRAW ELSE DROP THEN ;

\ _TUI-EVT-DRAW-DIRTY ( -- )
\   Walk the focus chain and redraw any dirty widgets.
\   If the global redraw flag is set, mark all widgets dirty first.
: _TUI-EVT-DRAW-DIRTY  ( -- )
    _TUI-EVT-REDRAW-FLAG @ IF
        ['] WDG-DIRTY FOC-EACH
        0 _TUI-EVT-REDRAW-FLAG !
    THEN
    ['] _TUI-EVT-DRAW-ONE FOC-EACH ;

\ =====================================================================
\  §7 — Resize Check
\ =====================================================================

\ _TUI-EVT-CHECK-RESIZE ( ev -- )
\   If the event is a resize event, call the resize callback.
: _TUI-EVT-CHECK-RESIZE  ( ev -- )
    DUP @ KEY-T-RESIZE = IF
        _TUI-EVT-ON-RESIZE-XT @ ?DUP IF
            SWAP DUP 8 + @      \ ( xt ev w )  — code field = width
            SWAP 16 + @         \ ( xt w h )   — mods field = height
            ROT EXECUTE
        ELSE DROP THEN
    ELSE DROP THEN ;

\ =====================================================================
\  §8 — Main Event Loop
\ =====================================================================

: TUI-EVT-LOOP  ( -- )
    -1 _TUI-EVT-RUNNING !
    MS@ _TUI-EVT-LAST-TICK !
    BEGIN
        _TUI-EVT-RUNNING @
    WHILE
        \ 1. Poll for input
        _TUI-EVT-KEY-BUF KEY-POLL IF
            \ 1a. Check for resize
            _TUI-EVT-KEY-BUF _TUI-EVT-CHECK-RESIZE
            \ 2. Global handler first
            _TUI-EVT-ON-KEY-XT @ ?DUP IF
                _TUI-EVT-KEY-BUF SWAP EXECUTE  ( -- consumed? )
            ELSE 0 THEN
            \ 3. If not consumed, dispatch to focused widget
            0= IF
                _TUI-EVT-KEY-BUF FOC-DISPATCH
            THEN
        THEN
        \ 4. Run deferred actions
        _TUI-EVT-DRAIN-POSTED
        \ 5. Timer tick
        _TUI-EVT-CHECK-TICK
        \ 6. Draw dirty widgets
        _TUI-EVT-DRAW-DIRTY
        \ 7. Flush screen
        SCR-FLUSH
        \ 8. Cooperative yield
        YIELD?
    REPEAT ;

\ =====================================================================
\  §9 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _tui-evt-guard

' TUI-EVT-LOOP      CONSTANT _tui-evt-loop-xt
' TUI-EVT-QUIT      CONSTANT _tui-evt-quit-xt
' TUI-EVT-TICK-MS!  CONSTANT _tui-evt-tick-ms-xt
' TUI-EVT-ON-TICK   CONSTANT _tui-evt-on-tick-xt
' TUI-EVT-ON-RESIZE CONSTANT _tui-evt-on-resize-xt
' TUI-EVT-ON-KEY    CONSTANT _tui-evt-on-key-xt
' TUI-EVT-POST      CONSTANT _tui-evt-post-xt
' TUI-EVT-REDRAW    CONSTANT _tui-evt-redraw-xt

: TUI-EVT-LOOP      _tui-evt-loop-xt      _tui-evt-guard WITH-GUARD ;
: TUI-EVT-QUIT      _tui-evt-quit-xt      _tui-evt-guard WITH-GUARD ;
: TUI-EVT-TICK-MS!  _tui-evt-tick-ms-xt   _tui-evt-guard WITH-GUARD ;
: TUI-EVT-ON-TICK   _tui-evt-on-tick-xt   _tui-evt-guard WITH-GUARD ;
: TUI-EVT-ON-RESIZE _tui-evt-on-resize-xt _tui-evt-guard WITH-GUARD ;
: TUI-EVT-ON-KEY    _tui-evt-on-key-xt    _tui-evt-guard WITH-GUARD ;
: TUI-EVT-POST      _tui-evt-post-xt      _tui-evt-guard WITH-GUARD ;
: TUI-EVT-REDRAW    _tui-evt-redraw-xt    _tui-evt-guard WITH-GUARD ;
[THEN] [THEN]
