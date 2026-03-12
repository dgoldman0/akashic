\ event.f — W3C-style DOM Event System for KDOS Forth
\
\ Three-phase event dispatch (capture → target → bubble) with
\ listener registration, type interning, and pool-based allocation.
\ Companion to dom.f — uses the same arena, string pool, and
\ coding conventions.  Does NOT modify dom.f.
\
\ BIOS words used:
\   MS@  ( -- ms )   millisecond uptime counter (for timestamps)
\
\ Prefix: DOME-   (public API)
\         _DOME-  (internal helpers)
\
\ Load with:   REQUIRE event.f

PROVIDED akashic-dom-event
REQUIRE dom.f

\ =====================================================================
\  Constants
\ =====================================================================

\ --- Dispatch phases ---
1 CONSTANT DOME-PHASE-CAPTURE
2 CONSTANT DOME-PHASE-TARGET
3 CONSTANT DOME-PHASE-BUBBLE

\ --- Event flag bits (in event +32 flags field) ---
1  CONSTANT DOME-F-BUBBLES         \ event bubbles up
2  CONSTANT DOME-F-CANCELABLE      \ preventDefault allowed
4  CONSTANT DOME-F-STOPPED         \ stopPropagation called
8  CONSTANT DOME-F-IMMEDIATE       \ stopImmediatePropagation called
16 CONSTANT DOME-F-PREVENTED       \ preventDefault called

\ --- Listener flag bits (in listener +16 flags field) ---
1 CONSTANT DOME-LF-CAPTURE         \ fires during capture phase
2 CONSTANT DOME-LF-ONCE            \ auto-remove after first fire

\ --- Pool sizes ---
80 CONSTANT DOME-EVT-SIZE          \ 10 cells per event object
40 CONSTANT DOME-LST-SIZE          \ 5 cells per listener entry
80 CONSTANT DOME-DESC-SIZE         \ 10 cells per DOME descriptor
8  CONSTANT DOME-EVT-POOL-COUNT    \ recycling pool of 8 events
32 CONSTANT DOME-MAX-TYPES         \ type registry capacity
64 CONSTANT DOME-MAX-DEPTH         \ max ancestor path depth

\ --- Standard type indices (slots 0..15 in type table) ---
0  CONSTANT DOME-TI-CLICK
1  CONSTANT DOME-TI-DBLCLICK
2  CONSTANT DOME-TI-MOUSEDOWN
3  CONSTANT DOME-TI-MOUSEUP
4  CONSTANT DOME-TI-MOUSEMOVE
5  CONSTANT DOME-TI-KEYDOWN
6  CONSTANT DOME-TI-KEYUP
7  CONSTANT DOME-TI-KEYPRESS
8  CONSTANT DOME-TI-FOCUS
9  CONSTANT DOME-TI-BLUR
10 CONSTANT DOME-TI-INPUT
11 CONSTANT DOME-TI-CHANGE
12 CONSTANT DOME-TI-SUBMIT
13 CONSTANT DOME-TI-SCROLL
14 CONSTANT DOME-TI-RESIZE
15 CONSTANT DOME-TI-CUSTOM

\ =====================================================================
\  DOME Descriptor Layout (10 cells = 80 bytes)
\ =====================================================================
\
\  +0   dom-doc       back-pointer to DOM document descriptor
\  +8   lst-base      listener pool start address
\ +16   lst-max       max listener slots
\ +24   lst-free      listener free-list head
\ +32   evt-base      event object pool start
\ +40   evt-free      event object free-list head
\ +48   shadow-base   shadow table (1 cell per DOM node slot)
\ +56   focus-node    currently focused DOM node (0 = none)
\ +64   type-tbl      type registry array (arena-allocated)
\ +72   type-cnt      number of registered types

: ED.DOC        ;           \ +0
: ED.LST-BASE   8 + ;      \ +8
: ED.LST-MAX    16 + ;     \ +16
: ED.LST-FREE   24 + ;     \ +24
: ED.EVT-BASE   32 + ;     \ +32
: ED.EVT-FREE   40 + ;     \ +40
: ED.SHADOW     48 + ;     \ +48
: ED.FOCUS      56 + ;     \ +56
: ED.TYPE-TBL   64 + ;     \ +64
: ED.TYPE-CNT   72 + ;     \ +72

\ =====================================================================
\  Current DOME Descriptor
\ =====================================================================

VARIABLE _DOME-CUR

: DOME-USE  ( dome -- )  _DOME-CUR ! ;
: DOME-CUR  ( -- dome )  _DOME-CUR @ ;

\ =====================================================================
\  Event Object Field Accessors
\ =====================================================================
\
\  Event layout (10 cells = 80 bytes):
\    +0   type          interned string handle
\    +8   target        node where event originated
\   +16   current       node whose listener is executing
\   +24   phase         DOME-PHASE-*
\   +32   flags         DOME-F-* bits
\   +40   timestamp     MS@ value at creation
\   +48   detail        generic payload cell 1
\   +56   detail2       generic payload cell 2
\   +64   detail3       generic payload cell 3
\   +72   related       related node (e.g. focus/blur relatedTarget)

: E.TYPE    ;               \ +0
: E.TARGET  8 + ;           \ +8
: E.CURRENT 16 + ;          \ +16
: E.PHASE   24 + ;          \ +24
: E.FLAGS   32 + ;          \ +32
: E.TSTAMP  40 + ;          \ +40
: E.DETAIL  48 + ;          \ +48
: E.DETAIL2 56 + ;          \ +56
: E.DETAIL3 64 + ;          \ +64
: E.RELATED 72 + ;          \ +72

\ =====================================================================
\  Listener Entry Field Accessors
\ =====================================================================
\
\  Listener layout (5 cells = 40 bytes):
\    +0   type     event type handle (interned)
\    +8   xt       execution token  ( event node -- )
\   +16   flags    DOME-LF-* bits
\   +24   next     next listener in node's list (0 = end)
\   +32   node     back-pointer to owning DOM node

: L.TYPE   ;                \ +0
: L.XT     8 + ;            \ +8
: L.FLAGS  16 + ;           \ +16
: L.NEXT   24 + ;           \ +24
: L.NODE   32 + ;           \ +32

\ =====================================================================
\  Public Event Getters / Setters
\ =====================================================================

: DOME-EVENT-TYPE     ( event -- type )    @ ;
: DOME-EVENT-TARGET   ( event -- node )    E.TARGET @ ;
: DOME-EVENT-CURRENT  ( event -- node )    E.CURRENT @ ;
: DOME-EVENT-PHASE    ( event -- phase )   E.PHASE @ ;
: DOME-EVENT-DETAIL   ( event -- d )       E.DETAIL @ ;
: DOME-EVENT-DETAIL!  ( d event -- )       E.DETAIL ! ;
: DOME-EVENT-DETAIL2  ( event -- d )       E.DETAIL2 @ ;
: DOME-EVENT-DETAIL2! ( d event -- )       E.DETAIL2 ! ;
: DOME-EVENT-DETAIL3  ( event -- d )       E.DETAIL3 @ ;
: DOME-EVENT-DETAIL3! ( d event -- )       E.DETAIL3 ! ;
: DOME-EVENT-RELATED  ( event -- node|0 )  E.RELATED @ ;
: DOME-EVENT-RELATED! ( node event -- )    E.RELATED ! ;
: DOME-EVENT-TSTAMP   ( event -- ms )      E.TSTAMP @ ;

\ =====================================================================
\  Propagation Control
\ =====================================================================

: DOME-STOP  ( event -- )
    DUP E.FLAGS @  DOME-F-STOPPED OR  SWAP E.FLAGS ! ;

: DOME-STOP-IMMEDIATE  ( event -- )
    DUP E.FLAGS @  DOME-F-STOPPED DOME-F-IMMEDIATE OR  OR
    SWAP E.FLAGS ! ;

: DOME-PREVENT  ( event -- )
    DUP E.FLAGS @  DOME-F-CANCELABLE AND IF
        DUP E.FLAGS @  DOME-F-PREVENTED OR  OVER E.FLAGS !
    THEN DROP ;

: DOME-STOPPED?   ( event -- flag )
    E.FLAGS @  DOME-F-STOPPED AND  0<> ;

: DOME-IMMEDIATE? ( event -- flag )
    E.FLAGS @  DOME-F-IMMEDIATE AND  0<> ;

: DOME-PREVENTED? ( event -- flag )
    E.FLAGS @  DOME-F-PREVENTED AND  0<> ;

\ =====================================================================
\  Type Accessor (by index)
\ =====================================================================

: DOME-TYPE@  ( index -- handle )
    8 *  DOME-CUR ED.TYPE-TBL @ +  @ ;

\ =====================================================================
\  Nested-Dispatch Path Buffers (3 levels)
\ =====================================================================

CREATE _DOME-PATH-BUFS  3 DOME-MAX-DEPTH * 8 * ALLOT
CREATE _DOME-PATH-CNTS  3 8 * ALLOT
VARIABLE _DOME-DISPATCH-DEPTH
0 _DOME-DISPATCH-DEPTH !

\ =====================================================================
\  Forward declarations — bodies follow in implementation section
\ =====================================================================
\
\  Internal:
\    _DOME-EVT-INIT-FREE   ( dome -- )
\    _DOME-LST-INIT-FREE   ( dome -- )
\    _DOME-LST-ALLOC       ( -- listener )
\    _DOME-LST-FREE        ( listener -- )
\    _DOME-SHADOW           ( node -- shadow-cell-addr )
\    _DOME-SHOULD-FIRE?     ( listener-flags phase -- flag )
\    _DOME-FIRE-ON          ( event node -- )
\    _DOME-BUILD-PATH       ( node -- )
\    _DOME-CLEANUP-ONCE     ( -- )
\    _DOME-INTERN-STD-TYPES ( doc dome -- )
\
\  Public:
\    DOME-EVENT-NEW    ( type bubbles? cancelable? -- event )
\    DOME-EVENT-FREE   ( event -- )
\    DOME-INTERN-TYPE  ( addr len -- type-handle )
\    DOME-TYPE-NAME    ( type-handle -- addr len )
\    DOME-LISTEN       ( node type xt -- )
\    DOME-LISTEN-CAPTURE ( node type xt -- )
\    DOME-LISTEN-ONCE  ( node type xt -- )
\    DOME-UNLISTEN     ( node type xt -- )
\    DOME-UNLISTEN-ALL ( node -- )
\    DOME-HAS-LISTENER? ( node type -- flag )
\    DOME-DISPATCH     ( node event -- prevented? )
\    DOME-FIRE         ( node type detail -- prevented? )
\    DOME-INIT         ( doc max-listeners -- dome )
\    DOME-INIT-DEFAULT ( doc -- dome )

\ =====================================================================
\  §1 — Event Pool: init / alloc / free
\ =====================================================================

VARIABLE _DEIF-A

: _DOME-EVT-INIT-FREE  ( dome -- )
    DUP ED.EVT-BASE @  _DEIF-A !
    DOME-EVT-POOL-COUNT 1- 0 DO
        _DEIF-A @  DOME-EVT-SIZE +
        _DEIF-A @ !
        _DEIF-A @  DOME-EVT-SIZE +  _DEIF-A !
    LOOP
    0  _DEIF-A @ !
    DUP ED.EVT-BASE @  SWAP ED.EVT-FREE ! ;

VARIABLE _DEN-TY   VARIABLE _DEN-FL

: DOME-EVENT-NEW  ( type bubbles? cancelable? -- event )
    SWAP IF DOME-F-BUBBLES   ELSE 0 THEN
    SWAP IF DOME-F-CANCELABLE ELSE 0 THEN
    OR  _DEN-FL !
    _DEN-TY !
    DOME-CUR ED.EVT-FREE @
    DUP 0= ABORT" DOME event pool exhausted"
    DUP @  DOME-CUR ED.EVT-FREE !
    DUP DOME-EVT-SIZE 0 FILL
    _DEN-TY @  OVER E.TYPE !
    _DEN-FL @  OVER E.FLAGS !
    MS@        OVER E.TSTAMP ! ;

: DOME-EVENT-FREE  ( event -- )
    DUP DOME-EVT-SIZE 0 FILL
    DOME-CUR ED.EVT-FREE @  OVER !
    DOME-CUR ED.EVT-FREE ! ;

\ =====================================================================
\  §2 — Listener Pool: init / alloc / free
\ =====================================================================

VARIABLE _DLIF-A

: _DOME-LST-INIT-FREE  ( dome -- )
    DUP ED.LST-BASE @  _DLIF-A !
    DUP ED.LST-MAX @ 1- 0 DO
        _DLIF-A @  DOME-LST-SIZE +
        _DLIF-A @ !
        _DLIF-A @  DOME-LST-SIZE +  _DLIF-A !
    LOOP
    0  _DLIF-A @ !
    DUP ED.LST-BASE @  SWAP ED.LST-FREE ! ;

: _DOME-LST-ALLOC  ( -- listener )
    DOME-CUR ED.LST-FREE @
    DUP 0= ABORT" DOME listener pool exhausted"
    DUP @  DOME-CUR ED.LST-FREE !
    DUP DOME-LST-SIZE 0 FILL ;

: _DOME-LST-FREE  ( listener -- )
    DUP DOME-LST-SIZE 0 FILL
    DOME-CUR ED.LST-FREE @  OVER !
    DOME-CUR ED.LST-FREE ! ;

\ =====================================================================
\  §3 — Shadow Table Lookup
\ =====================================================================

\ Shadow table: parallel array of cells, one per DOM node slot.
\ Index = (node-addr - doc.node-base) / DOM-NODE-SIZE
\ Returns address of the cell holding listener list head for node.

: _DOME-SHADOW  ( node -- shadow-cell-addr )
    DOME-CUR ED.DOC @ D.NODE-BASE @  -
    DOM-NODE-SIZE /
    8 *
    DOME-CUR ED.SHADOW @  + ;

\ =====================================================================
\  §4 — Type Interning
\ =====================================================================

\ Intern: linear scan of type registry, dedup by case-insensitive
\ string compare.  On miss, allocate from DOM string pool and register.

VARIABLE _DIT-A   VARIABLE _DIT-L   VARIABLE _DIT-H

: DOME-INTERN-TYPE  ( addr len -- type-handle )
    _DIT-L !  _DIT-A !
    \ Scan existing
    DOME-CUR ED.TYPE-CNT @ 0 ?DO
        DOME-CUR ED.TYPE-TBL @  I 8 * +  @
        DUP _DOM-STR-GET
        _DIT-A @ _DIT-L @  _DOM-CISTREQ IF
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    \ Not found — allocate new
    DOME-CUR ED.TYPE-CNT @  DOME-MAX-TYPES >= ABORT" DOME type registry full"
    _DIT-A @ _DIT-L @ _DOM-STR-ALLOC  _DIT-H !
    _DIT-H @
    DOME-CUR ED.TYPE-TBL @
    DOME-CUR ED.TYPE-CNT @ 8 * +  !
    DOME-CUR ED.TYPE-CNT @ 1+  DOME-CUR ED.TYPE-CNT !
    _DIT-H @ ;

: DOME-TYPE-NAME  ( type-handle -- addr len )
    _DOM-STR-GET ;

\ =====================================================================
\  §5 — Listener Registration
\ =====================================================================

VARIABLE _DL-N   VARIABLE _DL-TY   VARIABLE _DL-XT   VARIABLE _DL-FL

: _DOME-LISTEN-INNER  ( node type xt flags -- )
    _DL-FL !  _DL-XT !  _DL-TY !  _DL-N !
    _DOME-LST-ALLOC
    DUP >R
    _DL-TY @  R@ L.TYPE !
    _DL-XT @  R@ L.XT !
    _DL-FL @  R@ L.FLAGS !
    _DL-N  @  R@ L.NODE !
    _DL-N @ _DOME-SHADOW
    DUP @
    R@ L.NEXT !
    R>  SWAP ! ;

: DOME-LISTEN  ( node type xt -- )
    0 _DOME-LISTEN-INNER ;

: DOME-LISTEN-CAPTURE  ( node type xt -- )
    DOME-LF-CAPTURE _DOME-LISTEN-INNER ;

: DOME-LISTEN-ONCE  ( node type xt -- )
    DOME-LF-ONCE _DOME-LISTEN-INNER ;

\ DOME-UNLISTEN — remove first listener matching type + xt.
VARIABLE _DU-N   VARIABLE _DU-TY   VARIABLE _DU-XT
VARIABLE _DU-LST VARIABLE _DU-PRV

: DOME-UNLISTEN  ( node type xt -- )
    _DU-XT !  _DU-TY !  _DU-N !
    _DU-N @ _DOME-SHADOW @  _DU-LST !
    0 _DU-PRV !
    BEGIN _DU-LST @ WHILE
        _DU-LST @ L.TYPE @  _DU-TY @ = IF
        _DU-LST @ L.XT @    _DU-XT @ = IF
            _DU-PRV @ IF
                _DU-LST @ L.NEXT @  _DU-PRV @ L.NEXT !
            ELSE
                _DU-LST @ L.NEXT @
                _DU-N @ _DOME-SHADOW  !
            THEN
            _DU-LST @ _DOME-LST-FREE
            EXIT
        THEN THEN
        _DU-LST @  _DU-PRV !
        _DU-LST @ L.NEXT @  _DU-LST !
    REPEAT ;

\ DOME-UNLISTEN-ALL — remove every listener from a node.
VARIABLE _DUA-SH

: DOME-UNLISTEN-ALL  ( node -- )
    _DOME-SHADOW  _DUA-SH !
    _DUA-SH @ @
    BEGIN DUP WHILE
        DUP L.NEXT @
        SWAP _DOME-LST-FREE
    REPEAT
    DROP
    0  _DUA-SH @ ! ;

\ DOME-HAS-LISTENER? — check if node has any listener for type.
: DOME-HAS-LISTENER?  ( node type -- flag )
    SWAP _DOME-SHADOW @
    BEGIN DUP WHILE
        2DUP L.TYPE @ = IF
            2DROP -1 EXIT
        THEN
        L.NEXT @
    REPEAT
    2DROP 0 ;

\ =====================================================================
\  §6 — Ancestor Path Builder
\ =====================================================================

\ Current path buffer and count for the active dispatch depth.

: _DOME-PATH-BUF  ( -- addr )
    _DOME-PATH-BUFS
    _DOME-DISPATCH-DEPTH @ DOME-MAX-DEPTH 8 * * + ;

: _DOME-PATH-CNT  ( -- addr )
    _DOME-PATH-CNTS
    _DOME-DISPATCH-DEPTH @ 8 * + ;

\ Build ancestor path: path[0]=node, path[1]=parent, ... path[n-1]=root
VARIABLE _DBP-N

: _DOME-BUILD-PATH  ( node -- )
    _DBP-N !
    0  _DOME-PATH-CNT !
    BEGIN _DBP-N @ WHILE
        _DBP-N @
        _DOME-PATH-BUF  _DOME-PATH-CNT @ 8 * +  !
        _DOME-PATH-CNT @  1+  _DOME-PATH-CNT !
        _DOME-PATH-CNT @  DOME-MAX-DEPTH >= IF EXIT THEN
        _DBP-N @ N.PARENT @  _DBP-N !
    REPEAT ;

\ =====================================================================
\  §7 — Phase Matching + Fire-On-Node
\ =====================================================================

\ _DOME-SHOULD-FIRE? — does this listener fire in this phase?
\ Target phase: always.  Capture: only capture listeners.
\ Bubble: only non-capture listeners.

: _DOME-SHOULD-FIRE?  ( listener-flags phase -- flag )
    SWAP DOME-LF-CAPTURE AND  0<>
    SWAP
    DUP DOME-PHASE-TARGET = IF
        2DROP -1 EXIT
    THEN
    DOME-PHASE-CAPTURE = IF
        EXIT
    THEN
    INVERT ;

\ _DOME-FIRE-ON — fire all matching listeners on a node.
\ Reads event.type and event.phase.  Calls xt ( event node -- ).
\ Marks once-listeners dead (xt=0) for later cleanup.

VARIABLE _DFO-EVT   VARIABLE _DFO-LST   VARIABLE _DFO-NXT

: _DOME-FIRE-ON  ( event node -- )
    _DOME-SHADOW @  _DFO-LST !
    _DFO-EVT !
    BEGIN _DFO-LST @ WHILE
        \ Capture .next BEFORE calling listener (safe if list mutates)
        _DFO-LST @ L.NEXT @  _DFO-NXT !
        \ Type match?
        _DFO-LST @ L.TYPE @  _DFO-EVT @ E.TYPE @ = IF
            \ Phase match?
            _DFO-LST @ L.FLAGS @
            _DFO-EVT @ E.PHASE @
            _DOME-SHOULD-FIRE? IF
                \ Set event.currentTarget
                _DFO-LST @ L.NODE @  _DFO-EVT @ E.CURRENT !
                \ Call listener
                _DFO-EVT @
                _DFO-LST @ L.NODE @
                _DFO-LST @ L.XT @
                EXECUTE
                \ Once? Mark dead
                _DFO-LST @ L.FLAGS @  DOME-LF-ONCE AND IF
                    0  _DFO-LST @ L.XT !
                THEN
                \ Immediate stop?
                _DFO-EVT @ DOME-IMMEDIATE? IF EXIT THEN
                \ Normal stop? (still fire remaining on same node per W3C?
                \ No — stopPropagation stops NEXT node, not this one.
                \ stopImmediatePropagation stops this node.)
            THEN
        THEN
        _DFO-NXT @  _DFO-LST !
    REPEAT ;

\ _DOME-CLEANUP-ONCE — sweep path nodes, unlink dead listeners (xt=0).
VARIABLE _DCO-SH   VARIABLE _DCO-PRV   VARIABLE _DCO-CUR

: _DOME-CLEANUP-ONCE  ( -- )
    _DOME-PATH-CNT @ 0 ?DO
        _DOME-PATH-BUF I 8 * + @  _DOME-SHADOW  _DCO-SH !
        _DCO-SH @ @  _DCO-CUR !
        0 _DCO-PRV !
        BEGIN _DCO-CUR @ WHILE
            _DCO-CUR @ L.XT @ 0= IF
                \ Dead — unlink
                _DCO-PRV @ IF
                    _DCO-CUR @ L.NEXT @  _DCO-PRV @ L.NEXT !
                ELSE
                    _DCO-CUR @ L.NEXT @  _DCO-SH @ !
                THEN
                _DCO-CUR @ L.NEXT @
                _DCO-CUR @ _DOME-LST-FREE
                _DCO-CUR !
            ELSE
                _DCO-CUR @  _DCO-PRV !
                _DCO-CUR @ L.NEXT @  _DCO-CUR !
            THEN
        REPEAT
    LOOP ;

\ =====================================================================
\  §8 — Three-Phase Dispatch
\ =====================================================================

VARIABLE _DD-NODE   VARIABLE _DD-EVT

: DOME-DISPATCH  ( node event -- prevented? )
    _DD-EVT !  _DD-NODE !
    \ Bump dispatch depth (for nested path buffers)
    _DOME-DISPATCH-DEPTH @ 1+  _DOME-DISPATCH-DEPTH !
    _DOME-DISPATCH-DEPTH @ 3 > ABORT" DOME dispatch nested too deep"
    \ Set event.target
    _DD-NODE @  _DD-EVT @ E.TARGET !
    \ Build ancestor path
    _DD-NODE @  _DOME-BUILD-PATH
    \
    \ ── PHASE 1: CAPTURE (root → ... → target.parent) ──
    DOME-PHASE-CAPTURE  _DD-EVT @ E.PHASE !
    _DOME-PATH-CNT @ 1-  0 MAX
    BEGIN DUP 0> WHILE
        DUP 8 * _DOME-PATH-BUF + @
        _DD-EVT @ SWAP  _DOME-FIRE-ON
        _DD-EVT @ DOME-STOPPED? IF
            DROP  _DOME-CLEANUP-ONCE
            _DOME-DISPATCH-DEPTH @ 1-  _DOME-DISPATCH-DEPTH !
            _DD-EVT @ DOME-PREVENTED? EXIT
        THEN
        1-
    REPEAT DROP
    \
    \ ── PHASE 2: TARGET ──
    DOME-PHASE-TARGET  _DD-EVT @ E.PHASE !
    _DD-EVT @  _DD-NODE @  _DOME-FIRE-ON
    _DD-EVT @ DOME-STOPPED? IF
        _DOME-CLEANUP-ONCE
        _DOME-DISPATCH-DEPTH @ 1-  _DOME-DISPATCH-DEPTH !
        _DD-EVT @ DOME-PREVENTED? EXIT
    THEN
    \
    \ ── PHASE 3: BUBBLE (target.parent → ... → root) ──
    _DD-EVT @ E.FLAGS @  DOME-F-BUBBLES AND IF
        DOME-PHASE-BUBBLE  _DD-EVT @ E.PHASE !
        1
        BEGIN DUP _DOME-PATH-CNT @ < WHILE
            DUP 8 * _DOME-PATH-BUF + @
            _DD-EVT @ SWAP  _DOME-FIRE-ON
            _DD-EVT @ DOME-STOPPED? IF
                DROP  _DOME-CLEANUP-ONCE
                _DOME-DISPATCH-DEPTH @ 1-  _DOME-DISPATCH-DEPTH !
                _DD-EVT @ DOME-PREVENTED? EXIT
            THEN
            1+
        REPEAT DROP
    THEN
    \
    _DOME-CLEANUP-ONCE
    _DOME-DISPATCH-DEPTH @ 1-  _DOME-DISPATCH-DEPTH !
    _DD-EVT @ DOME-PREVENTED? ;

\ =====================================================================
\  §9 — Convenience Fire
\ =====================================================================

VARIABLE _DF-ND   VARIABLE _DF-TY   VARIABLE _DF-DT   VARIABLE _DF-EVT

: DOME-FIRE  ( node type detail -- prevented? )
    _DF-DT !  _DF-TY !  _DF-ND !
    _DF-TY @ -1 -1  DOME-EVENT-NEW  _DF-EVT !
    _DF-DT @  _DF-EVT @ E.DETAIL !
    _DF-ND @  _DF-EVT @  DOME-DISPATCH
    _DF-EVT @ DOME-EVENT-FREE ;

\ =====================================================================
\  §10 — Master Initialization
\ =====================================================================

VARIABLE _DI-DOC   VARIABLE _DI-ML   VARIABLE _DI-AR

\ _DOME-INTERN-STD-TYPES — register the 16 standard types (slots 0-15).
: _DOME-INTERN-STD-TYPES  ( -- )
    S" click"     DOME-INTERN-TYPE DROP
    S" dblclick"  DOME-INTERN-TYPE DROP
    S" mousedown" DOME-INTERN-TYPE DROP
    S" mouseup"   DOME-INTERN-TYPE DROP
    S" mousemove" DOME-INTERN-TYPE DROP
    S" keydown"   DOME-INTERN-TYPE DROP
    S" keyup"     DOME-INTERN-TYPE DROP
    S" keypress"  DOME-INTERN-TYPE DROP
    S" focus"     DOME-INTERN-TYPE DROP
    S" blur"      DOME-INTERN-TYPE DROP
    S" input"     DOME-INTERN-TYPE DROP
    S" change"    DOME-INTERN-TYPE DROP
    S" submit"    DOME-INTERN-TYPE DROP
    S" scroll"    DOME-INTERN-TYPE DROP
    S" resize"    DOME-INTERN-TYPE DROP
    S" custom"    DOME-INTERN-TYPE DROP ;

\ _DOME-CARVE ( nbytes -- addr )
\   Carve space from the *top* of the doc's string pool.
\   DOM-DOC-NEW claims all remaining arena for the string pool,
\   so we shrink D.STR-END downward instead of using ARENA-ALLOT.
VARIABLE _DC-N
: _DOME-CARVE  ( nbytes -- addr )
    _DC-N !
    _DI-DOC @ D.STR-END @  _DC-N @ -
    DUP _DI-DOC @ D.STR-PTR @  < ABORT" DOME: string pool full"
    DUP _DI-DOC @ D.STR-END ! ;

: DOME-INIT  ( doc max-listeners -- dome )
    _DI-ML !  _DI-DOC !
    _DI-DOC @ D.ARENA @  _DI-AR !
    \ Allot DOME descriptor (carved from string pool end)
    DOME-DESC-SIZE _DOME-CARVE
    DUP DOME-DESC-SIZE 0 FILL
    DUP >R
    _DI-DOC @  R@ ED.DOC !
    \ Listener pool
    _DI-ML @ DOME-LST-SIZE * _DOME-CARVE
    R@ ED.LST-BASE !
    _DI-ML @  R@ ED.LST-MAX !
    \ Event pool
    DOME-EVT-POOL-COUNT DOME-EVT-SIZE * _DOME-CARVE
    R@ ED.EVT-BASE !
    \ Shadow table (1 cell per node slot)
    _DI-DOC @ D.NODE-MAX @ 8 * _DOME-CARVE
    R@ ED.SHADOW !
    \ Type registry
    DOME-MAX-TYPES 8 * _DOME-CARVE
    R@ ED.TYPE-TBL !
    0  R@ ED.TYPE-CNT !
    0  R@ ED.FOCUS !
    \ Init free-lists
    R@ _DOME-LST-INIT-FREE
    R@ _DOME-EVT-INIT-FREE
    \ Zero shadow table
    R@ ED.SHADOW @  _DI-DOC @ D.NODE-MAX @ 8 *  0 FILL
    \ Zero type registry
    R@ ED.TYPE-TBL @  DOME-MAX-TYPES 8 *  0 FILL
    \ Activate and register standard types
    _DI-DOC @ DOM-USE
    R@ DOME-USE
    _DOME-INTERN-STD-TYPES
    R> ;

: DOME-INIT-DEFAULT  ( doc -- dome )
    256 DOME-INIT ;

\ =====================================================================
\  §11 — Guard Wrappers
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _dome-guard

\ -- Only guard functions that touch shared state.
\ -- Field accessors (ED.* E.* L.*) are pure offset arithmetic — no guard.

' DOME-USE        CONSTANT _dome-use-xt
' DOME-CUR        CONSTANT _dome-cur-xt
' DOME-EVENT-NEW  CONSTANT _dome-event-new-xt
' DOME-EVENT-FREE CONSTANT _dome-event-free-xt
' DOME-INTERN-TYPE CONSTANT _dome-intern-type-xt
' DOME-TYPE-NAME  CONSTANT _dome-type-name-xt
' DOME-TYPE@      CONSTANT _dome-type-at-xt
' DOME-LISTEN     CONSTANT _dome-listen-xt
' DOME-LISTEN-CAPTURE CONSTANT _dome-listen-capture-xt
' DOME-LISTEN-ONCE CONSTANT _dome-listen-once-xt
' DOME-UNLISTEN   CONSTANT _dome-unlisten-xt
' DOME-UNLISTEN-ALL CONSTANT _dome-unlisten-all-xt
' DOME-HAS-LISTENER? CONSTANT _dome-has-listener-xt
' DOME-DISPATCH   CONSTANT _dome-dispatch-xt
' DOME-FIRE       CONSTANT _dome-fire-xt
' DOME-INIT       CONSTANT _dome-init-xt
' DOME-INIT-DEFAULT CONSTANT _dome-init-default-xt
' DOME-STOP       CONSTANT _dome-stop-xt
' DOME-STOP-IMMEDIATE CONSTANT _dome-stop-imm-xt
' DOME-PREVENT    CONSTANT _dome-prevent-xt
' DOME-STOPPED?   CONSTANT _dome-stopped-xt
' DOME-PREVENTED? CONSTANT _dome-prevented-xt

: DOME-USE        _dome-use-xt _dome-guard WITH-GUARD ;
: DOME-CUR        _dome-cur-xt _dome-guard WITH-GUARD ;
: DOME-EVENT-NEW  _dome-event-new-xt _dome-guard WITH-GUARD ;
: DOME-EVENT-FREE _dome-event-free-xt _dome-guard WITH-GUARD ;
: DOME-INTERN-TYPE _dome-intern-type-xt _dome-guard WITH-GUARD ;
: DOME-TYPE-NAME  _dome-type-name-xt _dome-guard WITH-GUARD ;
: DOME-TYPE@      _dome-type-at-xt _dome-guard WITH-GUARD ;
: DOME-LISTEN     _dome-listen-xt _dome-guard WITH-GUARD ;
: DOME-LISTEN-CAPTURE _dome-listen-capture-xt _dome-guard WITH-GUARD ;
: DOME-LISTEN-ONCE _dome-listen-once-xt _dome-guard WITH-GUARD ;
: DOME-UNLISTEN   _dome-unlisten-xt _dome-guard WITH-GUARD ;
: DOME-UNLISTEN-ALL _dome-unlisten-all-xt _dome-guard WITH-GUARD ;
: DOME-HAS-LISTENER? _dome-has-listener-xt _dome-guard WITH-GUARD ;
: DOME-DISPATCH   _dome-dispatch-xt _dome-guard WITH-GUARD ;
: DOME-FIRE       _dome-fire-xt _dome-guard WITH-GUARD ;
: DOME-INIT       _dome-init-xt _dome-guard WITH-GUARD ;
: DOME-INIT-DEFAULT _dome-init-default-xt _dome-guard WITH-GUARD ;
: DOME-STOP       _dome-stop-xt _dome-guard WITH-GUARD ;
: DOME-STOP-IMMEDIATE _dome-stop-imm-xt _dome-guard WITH-GUARD ;
: DOME-PREVENT    _dome-prevent-xt _dome-guard WITH-GUARD ;
: DOME-STOPPED?   _dome-stopped-xt _dome-guard WITH-GUARD ;
: DOME-PREVENTED? _dome-prevented-xt _dome-guard WITH-GUARD ;
[THEN] [THEN]
