\ dom-event.f — DOM Event Routing for TUI
\
\ TUI-specific adapter that feeds keyboard and mouse events from
\ the TUI input system (keys.f) into the general-purpose DOM event
\ system (dom/event.f).  Translates KEY-READ events into
\ DOME-T-KEYDOWN / DOME-T-KEYPRESS DOM events, mouse reports into
\ DOME-T-CLICK / DOME-T-MOUSEDOWN / DOME-T-MOUSEUP, and manages
\ DOM-level focus (Tab cycling through DTUI-F-FOCUSABLE elements).
\
\ Prefix: DEVT-  (public)
\         _DEVT- (internal)
\
\ Load with:   REQUIRE dom-event.f

PROVIDED akashic-tui-dom-event

REQUIRE dom-tui.f
REQUIRE dom-render.f
REQUIRE keys.f
REQUIRE ../dom/event.f

\ =====================================================================
\  §1 — State
\ =====================================================================

VARIABLE _DEVT-DOC      \ DOM document
VARIABLE _DEVT-DOME     \ DOME event descriptor
VARIABLE _DEVT-FOCUS    \ currently focused DOM node (0 = none)

\ =====================================================================
\  §2 — Initialization
\ =====================================================================

\ DEVT-INIT ( doc dome -- )
\   Bind DOM event routing to a document + DOME descriptor.
: DEVT-INIT  ( doc dome -- )
    _DEVT-DOME !
    _DEVT-DOC  !
    0 _DEVT-FOCUS ! ;

\ =====================================================================
\  §3 — Focus Management
\ =====================================================================

\ DEVT-FOCUS ( -- node|0 )
\   Get currently focused DOM element.
: DEVT-FOCUS  ( -- node|0 )
    _DEVT-FOCUS @ ;

VARIABLE _DFS-OLD   VARIABLE _DFS-NEW   VARIABLE _DFS-EVT

\ DEVT-FOCUS! ( node -- )
\   Set focus to specific element.  Fires blur on old, focus on new.
\   blur.relatedTarget = new node; focus.relatedTarget = old node.
: DEVT-FOCUS!  ( node -- )
    DUP _DEVT-FOCUS @ = IF DROP EXIT THEN
    _DEVT-FOCUS @ _DFS-OLD !
    DUP            _DFS-NEW !
    _DEVT-DOME @ DOME-USE
    _DEVT-DOC  @ DOM-USE
    \ Fire blur on old focus (bubbles=false, cancelable=false)
    _DFS-OLD @ IF
        DOME-TI-BLUR DOME-TYPE@  0 0  DOME-EVENT-NEW  _DFS-EVT !
        _DFS-NEW @  _DFS-EVT @ E.RELATED !
        _DFS-OLD @  _DFS-EVT @  DOME-DISPATCH DROP
        _DFS-EVT @ DOME-EVENT-FREE
    THEN
    \ Update focus state
    _DFS-NEW @ _DEVT-FOCUS !
    \ Fire focus on new element (bubbles=false, cancelable=false)
    _DFS-NEW @ IF
        DOME-TI-FOCUS DOME-TYPE@  0 0  DOME-EVENT-NEW  _DFS-EVT !
        _DFS-OLD @  _DFS-EVT @ E.RELATED !
        _DFS-NEW @  _DFS-EVT @  DOME-DISPATCH DROP
        _DFS-EVT @ DOME-EVENT-FREE
    THEN ;

\ _DEVT-FOCUSABLE? ( node -- flag )
\   Check if a node is focusable via sidecar flags.
: _DEVT-FOCUSABLE?  ( node -- flag )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP 0 EXIT THEN
    N.AUX @  DUP 0= IF EXIT THEN
    DUP DTUI-SC-FLAGS DTUI-F-VISIBLE AND 0= IF DROP 0 EXIT THEN
    DTUI-SC-FLAGS DTUI-F-FOCUSABLE AND 0<> ;

\ =====================================================================
\  §3a — Focus Traversal (DFS order)
\ =====================================================================

\ We walk the DOM tree depth-first from BODY, collecting
\ focusable nodes into a small ring.  Then find the current
\ focus index and step forward or backward.

CREATE _DEVT-FRING  64 8 * ALLOT   \ up to 64 focusable nodes
VARIABLE _DEVT-FCOUNT

\ _DEVT-BUILD-RING ( -- )
\   Populate _DEVT-FRING with all focusable elements.

: _DEVT-COLLECT-FOCUSABLE  ( node -- )
    DUP _DEVT-FOCUSABLE? IF
        _DEVT-FCOUNT @ 64 < IF
            DUP  _DEVT-FRING  _DEVT-FCOUNT @ 8 * +  !
            _DEVT-FCOUNT @ 1+  _DEVT-FCOUNT !
        THEN
    THEN DROP ;

: _DEVT-BUILD-RING  ( -- )
    0 _DEVT-FCOUNT !
    _DEVT-DOC @ DOM-USE
    _DEVT-DOC @ D.BODY @  DUP 0= IF DROP EXIT THEN
    ['] _DEVT-COLLECT-FOCUSABLE DOM-WALK-DEPTH ;

\ _DEVT-FIND-IN-RING ( node -- index|-1 )
\   Find node in the focus ring.
: _DEVT-FIND-IN-RING  ( node -- index|-1 )
    _DEVT-FCOUNT @ 0 ?DO
        DUP  _DEVT-FRING I 8 * + @  = IF
            DROP I UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

\ DEVT-FOCUS-NEXT ( -- )
\   Move focus to next focusable element (Tab order).
: DEVT-FOCUS-NEXT  ( -- )
    _DEVT-BUILD-RING
    _DEVT-FCOUNT @ 0= IF EXIT THEN
    _DEVT-FOCUS @  _DEVT-FIND-IN-RING
    DUP 0< IF
        DROP 0
    ELSE
        1+  _DEVT-FCOUNT @ MOD
    THEN
    _DEVT-FRING SWAP 8 * +  @
    DEVT-FOCUS! ;

\ DEVT-FOCUS-PREV ( -- )
\   Move focus to previous focusable element (Shift-Tab).
: DEVT-FOCUS-PREV  ( -- )
    _DEVT-BUILD-RING
    _DEVT-FCOUNT @ 0= IF EXIT THEN
    _DEVT-FOCUS @  _DEVT-FIND-IN-RING
    DUP 0< IF
        DROP _DEVT-FCOUNT @ 1-
    ELSE
        1-  DUP 0< IF DROP _DEVT-FCOUNT @ 1- THEN
    THEN
    _DEVT-FRING SWAP 8 * +  @
    DEVT-FOCUS! ;

\ =====================================================================
\  §4 — Hit Testing
\ =====================================================================

\ DEVT-HIT-TEST ( row col -- node|0 )
\   Find deepest visible element at (row, col) by DFS walking
\   from BODY.  Later DFS nodes overwrite earlier — giving us
\   correct paint-order (last painted = on top).

VARIABLE _DHT-ROW   VARIABLE _DHT-COL
VARIABLE _DHT-BEST  VARIABLE _DHT-SC

: _DEVT-HIT-CHECK  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    DUP N.AUX @  DUP 0= IF 2DROP EXIT THEN
    _DHT-SC !   \ node on stack, sc in variable
    \ Check visibility
    _DHT-SC @ DTUI-SC-FLAGS DTUI-F-VISIBLE AND 0= IF DROP EXIT THEN
    _DHT-SC @ DTUI-SC-FLAGS DTUI-F-HIDDEN  AND    IF DROP EXIT THEN
    \ Bounds: row in [sc.ROW, sc.ROW + sc.H)
    _DHT-ROW @  _DHT-SC @ DTUI-SC-ROW  < IF DROP EXIT THEN
    _DHT-ROW @  _DHT-SC @ DTUI-SC-ROW  _DHT-SC @ DTUI-SC-H +
    < INVERT IF DROP EXIT THEN
    \ Bounds: col in [sc.COL, sc.COL + sc.W)
    _DHT-COL @  _DHT-SC @ DTUI-SC-COL  < IF DROP EXIT THEN
    _DHT-COL @  _DHT-SC @ DTUI-SC-COL  _DHT-SC @ DTUI-SC-W +
    < INVERT IF DROP EXIT THEN
    \ Inside — deeper DFS wins (overwrite)
    _DHT-BEST ! ;

: DEVT-HIT-TEST  ( row col -- node|0 )
    _DHT-COL !  _DHT-ROW !
    0 _DHT-BEST !
    _DEVT-DOC @ DOM-USE
    _DEVT-DOC @ D.BODY @  DUP 0= IF EXIT THEN
    ['] _DEVT-HIT-CHECK DOM-WALK-DEPTH
    _DHT-BEST @ ;

\ =====================================================================
\  §5 — Key Event Translation & Dispatch
\ =====================================================================

\ DEVT-DISPATCH ( key-ev-addr -- prevented? )
\   Translate a TUI key event into DOM keydown event and dispatch
\   to the focused element (or BODY if no focus).
\   For printable characters, also fires keypress.
\   Returns true if preventDefault was called.

VARIABLE _DKD-EVT   VARIABLE _DKD-TGT   VARIABLE _DKD-KE

: DEVT-DISPATCH  ( key-ev-addr -- prevented? )
    _DKD-KE !
    _DEVT-DOME @ DOME-USE
    _DEVT-DOC @ DOM-USE
    \ Determine target
    _DEVT-FOCUS @  DUP 0= IF
        DROP _DEVT-DOC @ D.BODY @
    THEN
    _DKD-TGT !
    _DKD-TGT @ 0= IF 0 EXIT THEN
    \ Tab handling — intercept before dispatch
    _DKD-KE @ KEY-IS-SPECIAL? IF
        _DKD-KE @ KEY-CODE@ KEY-TAB = IF
            _DKD-KE @ KEY-HAS-SHIFT? IF
                DEVT-FOCUS-PREV
            ELSE
                DEVT-FOCUS-NEXT
            THEN
            0 EXIT
        THEN
        _DKD-KE @ KEY-CODE@ KEY-BACKTAB = IF
            DEVT-FOCUS-PREV
            0 EXIT
        THEN
    THEN
    \ Create keydown event (bubbles, cancelable)
    DOME-TI-KEYDOWN DOME-TYPE@  -1 -1  DOME-EVENT-NEW  _DKD-EVT !
    \ Pack key info into detail fields:
    \   detail  = key code (character codepoint or special key constant)
    \   detail2 = modifier flags
    \   detail3 = key event type (KEY-T-CHAR, KEY-T-SPECIAL, etc.)
    _DKD-KE @ KEY-CODE@  _DKD-EVT @ E.DETAIL  !
    _DKD-KE @ KEY-MODS@  _DKD-EVT @ E.DETAIL2 !
    _DKD-KE @ @  _DKD-EVT @ E.DETAIL3 !   \ type field at +0
    \ Dispatch keydown
    _DKD-TGT @  _DKD-EVT @  DOME-DISPATCH
    _DKD-EVT @ DOME-EVENT-FREE
    \ If char event and not prevented, also fire keypress
    DUP INVERT IF
        _DKD-KE @ KEY-IS-CHAR? IF
            DROP
            DOME-TI-KEYPRESS DOME-TYPE@  -1 -1  DOME-EVENT-NEW  _DKD-EVT !
            _DKD-KE @ KEY-CODE@  _DKD-EVT @ E.DETAIL !
            _DKD-KE @ KEY-MODS@  _DKD-EVT @ E.DETAIL2 !
            _DKD-KE @ @  _DKD-EVT @ E.DETAIL3 !   \ type at +0
            _DKD-TGT @  _DKD-EVT @  DOME-DISPATCH
            _DKD-EVT @ DOME-EVENT-FREE
        THEN
    THEN ;

\ =====================================================================
\  §6 — Mouse Event Translation & Dispatch
\ =====================================================================

\ DEVT-DISPATCH-MOUSE ( row col button -- prevented? )
\   Hit-test to find target element, then dispatch a DOM click event.
\   button: 0=left, 1=middle, 2=right (from KEY-MOUSE-* constants)

VARIABLE _DMD-EVT   VARIABLE _DMD-TGT
VARIABLE _DMD-ROW   VARIABLE _DMD-COL   VARIABLE _DMD-BTN

: DEVT-DISPATCH-MOUSE  ( row col button -- prevented? )
    _DMD-BTN !  _DMD-COL !  _DMD-ROW !
    _DEVT-DOME @ DOME-USE
    _DEVT-DOC @ DOM-USE
    \ Hit-test
    _DMD-ROW @  _DMD-COL @  DEVT-HIT-TEST
    DUP 0= IF EXIT THEN
    _DMD-TGT !
    \ Focus the clicked element if it's focusable
    _DMD-TGT @ _DEVT-FOCUSABLE? IF
        _DMD-TGT @ DEVT-FOCUS!
    THEN
    \ Fire mousedown (bubbles, cancelable)
    DOME-TI-MOUSEDOWN DOME-TYPE@  -1 -1  DOME-EVENT-NEW  _DMD-EVT !
    _DMD-ROW @  _DMD-EVT @ E.DETAIL  !
    _DMD-COL @  _DMD-EVT @ E.DETAIL2 !
    _DMD-BTN @  _DMD-EVT @ E.DETAIL3 !
    _DMD-TGT @  _DMD-EVT @  DOME-DISPATCH DROP
    _DMD-EVT @ DOME-EVENT-FREE
    \ Fire click (bubbles, cancelable)
    DOME-TI-CLICK DOME-TYPE@  -1 -1  DOME-EVENT-NEW  _DMD-EVT !
    _DMD-ROW @  _DMD-EVT @ E.DETAIL  !
    _DMD-COL @  _DMD-EVT @ E.DETAIL2 !
    _DMD-BTN @  _DMD-EVT @ E.DETAIL3 !
    _DMD-TGT @  _DMD-EVT @  DOME-DISPATCH
    _DMD-EVT @ DOME-EVENT-FREE ;

\ =====================================================================
\  §7 — Guard Wrappers
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _devt-guard

' DEVT-INIT          CONSTANT _devt-init-xt
' DEVT-FOCUS         CONSTANT _devt-focus-xt
' DEVT-FOCUS!        CONSTANT _devt-focus-set-xt
' DEVT-FOCUS-NEXT    CONSTANT _devt-focus-next-xt
' DEVT-FOCUS-PREV    CONSTANT _devt-focus-prev-xt
' DEVT-HIT-TEST      CONSTANT _devt-hit-test-xt
' DEVT-DISPATCH      CONSTANT _devt-dispatch-xt
' DEVT-DISPATCH-MOUSE CONSTANT _devt-dispatch-mouse-xt

: DEVT-INIT          _devt-init-xt          _devt-guard WITH-GUARD ;
: DEVT-FOCUS         _devt-focus-xt         _devt-guard WITH-GUARD ;
: DEVT-FOCUS!        _devt-focus-set-xt     _devt-guard WITH-GUARD ;
: DEVT-FOCUS-NEXT    _devt-focus-next-xt    _devt-guard WITH-GUARD ;
: DEVT-FOCUS-PREV    _devt-focus-prev-xt    _devt-guard WITH-GUARD ;
: DEVT-HIT-TEST      _devt-hit-test-xt      _devt-guard WITH-GUARD ;
: DEVT-DISPATCH      _devt-dispatch-xt      _devt-guard WITH-GUARD ;
: DEVT-DISPATCH-MOUSE _devt-dispatch-mouse-xt _devt-guard WITH-GUARD ;
[THEN] [THEN]
