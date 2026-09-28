\ =================================================================
\  tree.f  —  Tree View Widget
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TREE- / _TREE-
\  Depends on: akashic-tui-widget, akashic-tui-draw, akashic-tui-region,
\              akashic-tui-keys, akashic-tui-semantic-collections
\
\  Collapsible tree display for hierarchical data.  The widget does
\  NOT own the tree data — it discovers the structure through five
\  caller-supplied callbacks:
\
\   children-xt  ( node -- first-child | 0 )
\   next-xt      ( node -- sibling | 0 )
\   label-xt     ( node -- addr len )
\   leaf?-xt     ( node -- flag )
\   key-xt       ( parent-key node -- key )
\
\  Nodes are opaque cell-sized tokens (pointers, handles, indices).
\  0 means "no node" / NIL.  A key names a node from draw to draw: it is
\  nonzero, unique among the nodes the tree shows, and the same for the
\  same node whenever its parent's key is.  Top-level nodes get parent key
\  0.  Callbacks must not call back into this widget; while one runs,
\  TREE-WALK-CONTEXT returns the context cell of the tree that called it.
\
\  Expansion is the set of expanded keys, so it follows each node however
\  the rows above it change, and the selection is the selected node's key.
\  The set is a sorted array that grows as needed; there is no node limit.
\
\  Up/Down move the selection, Right expands, Left collapses or moves to
\  the parent, and Enter opens the selection: the open callback runs if
\  there is one, and a branch otherwise expands or collapses.  A press
\  selects the row under it, and a press on a branch's mark expands or
\  collapses it.  A renderer's item events do the same by key.
\
\  The tree publishes its visible rows as a renderer-neutral TREE item
\  view (semantic-collections.f) for a selected rich renderer.
\
\  Descriptor layout (header + 15 cells = 160 bytes):
\   +40  root          Root node token
\   +48  children-xt   Callback: first child
\   +56  next-xt       Callback: next sibling
\   +64  label-xt      Callback: node label
\   +72  leaf-xt       Callback: is-leaf?
\   +80  key-xt        Callback: node key
\   +88  cursor-key    Selected node's key, or 0 for the first row
\   +96  scroll-top    First visible row (scroll offset)
\   +104 on-select-xt  ( widget -- ) the selection moved, or 0
\   +112 on-open-xt    ( widget -- ) the selection was opened, or 0
\   +120 expanded-a    Sorted expanded keys, or 0
\   +128 expanded-n    Number of expanded keys
\   +136 expanded-cap  Capacity of expanded-a, in keys
\   +144 instance      Nonzero allocation-lifetime instance token
\   +152 context       Caller's context cell
\ =================================================================

PROVIDED akashic-tui-tree

REQUIRE ../widget.f
REQUIRE ../region.f
REQUIRE ../draw.f
REQUIRE ../keys.f
REQUIRE ../semantic-collections.f
REQUIRE ../../utils/memory-span.f

CREATE _TREE-OWNED-START
VARIABLE _TREE-OWNED-LIMIT
0 _TREE-OWNED-LIMIT !

\ 3DROP is used below but not part of ANS Forth — define if absent.
[UNDEFINED] 3DROP [IF]
: 3DROP  ( a b c -- )  DROP 2DROP ;
[THEN]

\ =====================================================================
\  §1 — Layout constants
\ =====================================================================

40  CONSTANT _TREE-O-ROOT
48  CONSTANT _TREE-O-CHILD-XT
56  CONSTANT _TREE-O-NEXT-XT
64  CONSTANT _TREE-O-LABEL-XT
72  CONSTANT _TREE-O-LEAF-XT
80  CONSTANT _TREE-O-KEY-XT
88  CONSTANT _TREE-O-CURSOR
96  CONSTANT _TREE-O-SCROLL
104 CONSTANT _TREE-O-ON-SEL
112 CONSTANT _TREE-O-ON-OPEN
120 CONSTANT _TREE-O-XA
128 CONSTANT _TREE-O-XN
136 CONSTANT _TREE-O-XCAP
144 CONSTANT _TREE-O-INSTANCE
152 CONSTANT _TREE-O-CONTEXT
160 CONSTANT _TREE-DESC-SZ

2   CONSTANT _TREE-INDENT
16  CONSTANT _TREE-X-FIRST-CAP

\ Expand indicators
9654 CONSTANT _TREE-ARROW-R  \ U+25B6 ▶  collapsed
9660 CONSTANT _TREE-ARROW-D  \ U+25BC ▼  expanded

VARIABLE _TREE-NEXT-INSTANCE
0 _TREE-NEXT-INSTANCE !

: _TREE-CLAIM-INSTANCE  ( -- token )
    _TREE-NEXT-INSTANCE @ DUP -1 =
        IF DROP 1 ELSE 1+ DUP 0= IF DROP 1 THEN THEN
    DUP _TREE-NEXT-INSTANCE ! ;

\ =====================================================================
\  §2 — Expanded-key set
\ =====================================================================
\  A sorted array of unsigned keys.  Lookup is a binary search; an insert
\  or removal shifts the tail.

VARIABLE _TREE-X-W
VARIABLE _TREE-X-KEY
VARIABLE _TREE-X-LO
VARIABLE _TREE-X-HI

: _TREE-X@  ( index w -- key )  _TREE-O-XA + @ SWAP CELLS + @ ;

\ _TREE-XFIND ( key w -- index found? )
\   The first index whose key is not below KEY, and whether it is KEY.
: _TREE-XFIND  ( key w -- index found? )
    _TREE-X-W ! _TREE-X-KEY !
    0 _TREE-X-LO ! _TREE-X-W @ _TREE-O-XN + @ _TREE-X-HI !
    BEGIN _TREE-X-LO @ _TREE-X-HI @ < WHILE
        _TREE-X-LO @ _TREE-X-HI @ + 1 RSHIFT
        DUP _TREE-X-W @ _TREE-X@ _TREE-X-KEY @ U< IF
            1+ _TREE-X-LO !
        ELSE
            _TREE-X-HI !
        THEN
    REPEAT
    _TREE-X-LO @
    DUP _TREE-X-W @ _TREE-O-XN + @ < IF
        DUP _TREE-X-W @ _TREE-X@ _TREE-X-KEY @ =
    ELSE
        0
    THEN ;

: _TREE-XHAS?  ( key w -- flag )  _TREE-XFIND NIP ;

\ _TREE-XGROW ( w -- ok? )   Make room for one more key.
: _TREE-XGROW  ( w -- ok? )
    >R
    R@ _TREE-O-XN + @ R@ _TREE-O-XCAP + @ U< IF R> DROP -1 EXIT THEN
    R@ _TREE-O-XCAP + @ ?DUP IF 2* ELSE _TREE-X-FIRST-CAP THEN
    DUP CELLS ALLOCATE IF 2DROP R> DROP 0 EXIT THEN
    R@ _TREE-O-XA + @ ?DUP IF
        DUP 2 PICK R@ _TREE-O-XN + @ CELLS MOVE
        FREE
    THEN
    R@ _TREE-O-XA + !
    R> _TREE-O-XCAP + !
    -1 ;

VARIABLE _TREE-XA-W
VARIABLE _TREE-XA-KEY
VARIABLE _TREE-XA-I

: _TREE-XADD  ( key w -- ok? )
    _TREE-XA-W ! _TREE-XA-KEY !
    _TREE-XA-KEY @ _TREE-XA-W @ _TREE-XFIND IF DROP -1 EXIT THEN
        _TREE-XA-I !
    _TREE-XA-W @ _TREE-XGROW 0= IF 0 EXIT THEN
    _TREE-XA-W @ _TREE-O-XA + @ _TREE-XA-I @ CELLS +
    DUP DUP CELL+
        _TREE-XA-W @ _TREE-O-XN + @ _TREE-XA-I @ - CELLS MOVE
    _TREE-XA-KEY @ SWAP !
    1 _TREE-XA-W @ _TREE-O-XN + +!
    -1 ;

: _TREE-XREMOVE  ( key w -- )
    _TREE-XA-W ! _TREE-XA-KEY !
    _TREE-XA-KEY @ _TREE-XA-W @ _TREE-XFIND 0= IF DROP EXIT THEN
        _TREE-XA-I !
    _TREE-XA-W @ _TREE-O-XA + @ _TREE-XA-I @ CELLS +
    DUP CELL+ SWAP
        _TREE-XA-W @ _TREE-O-XN + @ _TREE-XA-I @ - 1- CELLS MOVE
    -1 _TREE-XA-W @ _TREE-O-XN + +! ;

\ =====================================================================
\  §3 — Walk engine
\ =====================================================================
\  Walks the visible rows in order, following sibling chains and
\  descending into expanded branches.  For every row it calls
\  xt ( node depth key parent-key row -- ).  A nonzero _TREE-FOUND stops
\  the walk.  All walk state lives in variables, so a visitor must not
\  start another walk.

VARIABLE _TW-W        \ widget pointer
VARIABLE _TW-XT       \ visitor callback xt
VARIABLE _TW-ROW      \ visible row counter
VARIABLE _TREE-FOUND  \ short-circuit flag

: _TREE-CHILDREN  ( node -- first-child|0 )
    _TW-W @ _TREE-O-CHILD-XT + @ EXECUTE ;
: _TREE-NEXT  ( node -- sibling|0 )  _TW-W @ _TREE-O-NEXT-XT + @ EXECUTE ;
: _TREE-LABEL  ( node -- addr len )  _TW-W @ _TREE-O-LABEL-XT + @ EXECUTE ;
: _TREE-LEAF?  ( node -- flag )  _TW-W @ _TREE-O-LEAF-XT + @ EXECUTE ;
: _TREE-KEY  ( parent-key node -- key )  _TW-W @ _TREE-O-KEY-XT + @ EXECUTE ;

\ TREE-WALK-CONTEXT ( -- context )
\   While a callback runs, the calling tree's context cell.
: TREE-WALK-CONTEXT  ( -- context )  _TW-W @ _TREE-O-CONTEXT + @ ;

\ _TREE-OPEN-BRANCH? ( node key -- flag )   An expanded branch.
: _TREE-OPEN-BRANCH?  ( node key -- flag )
    SWAP _TREE-LEAF? IF DROP 0 EXIT THEN
    _TW-W @ _TREE-XHAS? ;

: _TREE-DO-WALK  ( node depth parent-key -- )
    BEGIN
        2 PICK
    WHILE
        DUP 3 PICK _TREE-KEY                    ( node depth pkey key )
        3 PICK 3 PICK 2 PICK 4 PICK _TW-ROW @
            _TW-XT @ EXECUTE
        1 _TW-ROW +!
        _TREE-FOUND @ IF 2DROP 2DROP EXIT THEN
        3 PICK OVER _TREE-OPEN-BRANCH? IF
            3 PICK _TREE-CHILDREN ?DUP IF       ( node depth pkey key child )
                3 PICK 1+ 2 PICK RECURSE
                _TREE-FOUND @ IF 2DROP 2DROP EXIT THEN
            THEN
        THEN
        DROP                                    ( node depth pkey )
        ROT _TREE-NEXT -ROT                     ( sibling depth pkey )
    REPEAT
    DROP 2DROP ;

: _TREE-WALK  ( w xt -- )
    _TW-XT ! _TW-W !
    0 _TW-ROW ! 0 _TREE-FOUND !
    _TW-W @ _TREE-O-ROOT + @ 0 0 _TREE-DO-WALK ;

\ =====================================================================
\  §4 — Row queries
\ =====================================================================

VARIABLE _TREE-TARGET
VARIABLE _TREE-F-NODE
VARIABLE _TREE-F-DEPTH
VARIABLE _TREE-F-KEY
VARIABLE _TREE-F-PKEY
VARIABLE _TREE-F-ROW

: _TREE-HIT  ( node depth key parent-key row -- )
    _TREE-F-ROW ! _TREE-F-PKEY ! _TREE-F-KEY !
    _TREE-F-DEPTH ! _TREE-F-NODE !
    -1 _TREE-FOUND ! ;

: _TREE-SKIP  ( node depth key parent-key row -- )  2DROP 3DROP ;

: _TREE-ROW-CB  ( node depth key parent-key row -- )
    DUP _TREE-TARGET @ = IF _TREE-HIT ELSE _TREE-SKIP THEN ;

: _TREE-KEY-CB  ( node depth key parent-key row -- )
    2 PICK _TREE-TARGET @ = IF _TREE-HIT ELSE _TREE-SKIP THEN ;

: _TREE-NODE-CB  ( node depth key parent-key row -- )
    4 PICK _TREE-TARGET @ = IF _TREE-HIT ELSE _TREE-SKIP THEN ;

\ Each query leaves the row it found in _TREE-F-*.
: _TREE-AT-ROW  ( w row -- found? )
    _TREE-TARGET ! ['] _TREE-ROW-CB _TREE-WALK _TREE-FOUND @ ;
: _TREE-AT-KEY  ( w key -- found? )
    _TREE-TARGET ! ['] _TREE-KEY-CB _TREE-WALK _TREE-FOUND @ ;
: _TREE-AT-NODE  ( w node -- found? )
    _TREE-TARGET ! ['] _TREE-NODE-CB _TREE-WALK _TREE-FOUND @ ;

\ One full walk: the row count, the selected row (-1 when its key is not
\ shown), and the first row's key.
VARIABLE _TREE-TOTAL
VARIABLE _TREE-CUR-ROW
VARIABLE _TREE-ROW0-KEY

: _TREE-SCAN-CB  ( node depth key parent-key row -- )
    DUP 0= IF 2 PICK _TREE-ROW0-KEY ! THEN
    2 PICK _TW-W @ _TREE-O-CURSOR + @ = IF DUP _TREE-CUR-ROW ! THEN
    _TREE-SKIP ;

\ _TREE-SETTLE ( w -- )
\   Scan the rows, keep the selection on a shown row (the first row when
\   its node is gone or hidden), and clamp the scroll to the rows.
: _TREE-SETTLE  ( w -- )
    -1 _TREE-CUR-ROW ! 0 _TREE-ROW0-KEY !
    DUP ['] _TREE-SCAN-CB _TREE-WALK
    _TW-ROW @ _TREE-TOTAL !
    _TREE-CUR-ROW @ 0< _TREE-TOTAL @ 0> AND IF
        _TREE-ROW0-KEY @ OVER _TREE-O-CURSOR + !
        0 _TREE-CUR-ROW !
    THEN
    _TREE-TOTAL @ OVER WDG-REGION RGN-H - 0 MAX
    OVER _TREE-O-SCROLL + @ MIN 0 MAX
    SWAP _TREE-O-SCROLL + ! ;

: _TREE-VIS-COUNT  ( w -- n )  _TREE-SETTLE _TREE-TOTAL @ ;

\ =====================================================================
\  §5 — Draw handler
\ =====================================================================

VARIABLE _TREE-SCRL
VARIABLE _TREE-VH

: _TREE-DRAW-LINE  ( node depth key parent-key row -- )
    DUP _TREE-SCRL @ - DUP _TREE-VH @ < 0= IF
        DROP _TREE-SKIP -1 _TREE-FOUND ! EXIT
    THEN
    DUP 0< IF DROP _TREE-SKIP EXIT THEN          ( n d k p row srow )
    SWAP _TREE-CUR-ROW @ = IF
        0 DRW-FG! 7 DRW-BG! 0 DRW-ATTR!
    ELSE
        DRW-STYLE-RESTORE
    THEN                                          ( n d k p srow )
    32 OVER 0 _TW-W @ WDG-REGION RGN-W DRW-HLINE
    NIP                                           ( n d k srow )
    ROT _TREE-INDENT * SWAP                       ( n k col srow )
    3 PICK _TREE-LEAF? IF
        32
    ELSE
        3 PICK 3 PICK _TREE-OPEN-BRANCH? IF _TREE-ARROW-D ELSE _TREE-ARROW-R THEN
    THEN                                          ( n k col srow cp )
    OVER 3 PICK DRW-CHAR                          ( n k col srow )
    SWAP 2 + ROT DROP                             ( n srow col+2 )
    ROT _TREE-LABEL 2SWAP DRW-TEXT ;

: _TREE-DRAW  ( widget -- )
    DUP _TREE-SETTLE
    DUP _TREE-O-SCROLL + @ _TREE-SCRL !
    DUP WDG-REGION RGN-H _TREE-VH !
    DRW-STYLE-RESTORE
    32 0 0 _TREE-VH @ 4 PICK WDG-REGION RGN-W DRW-FILL-RECT
    ['] _TREE-DRAW-LINE _TREE-WALK
    DRW-STYLE-RESTORE ;

\ =====================================================================
\  §6 — Selection, expansion, and opening
\ =====================================================================

\ _TREE-SHOW-ROW ( row w -- )   Scroll so ROW is shown.
: _TREE-SHOW-ROW  ( row w -- )
    >R
    DUP R@ _TREE-O-SCROLL + @ < IF R> _TREE-O-SCROLL + ! EXIT THEN
    R@ WDG-REGION RGN-H
    2DUP R@ _TREE-O-SCROLL + @ + < IF 2DROP R> DROP EXIT THEN
    - 1+ 0 MAX R> _TREE-O-SCROLL + ! ;

\ _TREE-SELECT-FOUND ( w -- )
\   Select the row the last query found, show it, and report a change.
: _TREE-SELECT-FOUND  ( w -- )
    _TREE-F-ROW @ OVER _TREE-SHOW-ROW
    _TREE-F-KEY @ OVER _TREE-O-CURSOR + @ <> IF
        _TREE-F-KEY @ OVER _TREE-O-CURSOR + !
        DUP _TREE-O-ON-SEL + @ ?DUP IF OVER SWAP EXECUTE THEN
    THEN
    WDG-DIRTY ;

: _TREE-SELECT-ROW  ( row w -- )
    TUCK SWAP _TREE-AT-ROW IF _TREE-SELECT-FOUND ELSE DROP THEN ;

\ _TREE-FIX-CURSOR ( fallback-key w -- )
\   After a collapse, a selection that is no longer shown moves to
\   FALLBACK-KEY, the collapsed node.
: _TREE-FIX-CURSOR  ( fallback-key w -- )
    DUP DUP _TREE-O-CURSOR + @ _TREE-AT-KEY IF 2DROP EXIT THEN
    TUCK SWAP _TREE-AT-KEY IF _TREE-SELECT-FOUND ELSE DROP THEN ;

\ Expand or collapse the row the last query found.
: _TREE-EXPAND-FOUND  ( w -- )
    _TREE-F-NODE @ _TREE-LEAF? IF DROP EXIT THEN
    _TREE-F-KEY @ OVER _TREE-XADD DROP WDG-DIRTY ;

: _TREE-COLLAPSE-FOUND  ( w -- )
    _TREE-F-NODE @ _TREE-LEAF? IF DROP EXIT THEN
    _TREE-F-KEY @ >R
    R@ OVER _TREE-XREMOVE
    R> OVER _TREE-FIX-CURSOR
    WDG-DIRTY ;

: _TREE-TOGGLE-FOUND  ( w -- )
    _TREE-F-KEY @ OVER _TREE-XHAS? IF
        _TREE-COLLAPSE-FOUND
    ELSE
        _TREE-EXPAND-FOUND
    THEN ;

\ _TREE-OPEN ( w -- )
\   Open the selection: the open callback, or a branch expands or
\   collapses.
: _TREE-OPEN  ( w -- )
    DUP _TREE-O-ON-OPEN + @ ?DUP IF OVER SWAP EXECUTE WDG-DIRTY EXIT THEN
    DUP _TREE-SETTLE
    DUP _TREE-CUR-ROW @ _TREE-AT-ROW IF _TREE-TOGGLE-FOUND ELSE DROP THEN ;

\ =====================================================================
\  §7 — Event handler
\ =====================================================================

3 CONSTANT _TREE-WHEEL-ROWS

\ _TREE-WHEEL ( rows widget -- )
\   Scroll the view by signed rows without moving the selection.
: _TREE-WHEEL  ( rows widget -- )
    >R R@ _TREE-O-SCROLL + @ +
    DUP 0< IF DROP 0 THEN
    R@ _TREE-VIS-COUNT R@ WDG-REGION RGN-H -
    DUP 0< IF DROP 0 THEN
    2DUP > IF NIP ELSE DROP THEN
    R@ _TREE-O-SCROLL + ! R> WDG-DIRTY ;

VARIABLE _TPT-W
VARIABLE _TPT-ROW
VARIABLE _TPT-COL

\ A renderer's item event names a node by key.  A key no longer shown
\ (the view changed since that frame) is consumed and ignored.
: _TREE-ITEM-EVENT  ( widget -- consumed? )
    _TPT-W !
    _TPT-W @ KEY-MOUSE-ITEM-KEY @ _TREE-AT-KEY 0= IF -1 EXIT THEN
    KEY-MOUSE-ITEM-ACTION @ CASE
        KEY-ITEM-SELECT OF _TPT-W @ _TREE-SELECT-FOUND ENDOF
        KEY-ITEM-OPEN OF
            _TPT-W @ _TREE-SELECT-FOUND _TPT-W @ _TREE-OPEN
        ENDOF
        KEY-ITEM-EXPAND OF _TPT-W @ _TREE-EXPAND-FOUND ENDOF
        KEY-ITEM-COLLAPSE OF _TPT-W @ _TREE-COLLAPSE-FOUND ENDOF
    ENDCASE
    -1 ;

\ A primary press selects the row under it; a press on a branch's mark also
\ expands or collapses that branch.  The wheel scrolls.
: _TREE-POINTER  ( event widget -- consumed? )
    _TPT-W !
    DUP 8 + @ KEY-MOUSE-BUTTON CASE
        KEY-MOUSE-SCROLL-UP OF
            DROP _TREE-WHEEL-ROWS NEGATE _TPT-W @ _TREE-WHEEL -1 EXIT
        ENDOF
        KEY-MOUSE-SCROLL-DN OF
            DROP _TREE-WHEEL-ROWS _TPT-W @ _TREE-WHEEL -1 EXIT
        ENDOF
        KEY-MOUSE-ITEM OF DROP _TPT-W @ _TREE-ITEM-EVENT EXIT ENDOF
        KEY-MOUSE-LEFT OF
            16 + @ DUP 16 RSHIFT _TPT-W @ WDG-REGION RGN-ROW - _TPT-ROW !
            0xFFFF AND _TPT-W @ WDG-REGION RGN-COL - _TPT-COL !
            _TPT-ROW @ 0< IF 0 EXIT THEN
            _TPT-W @ _TREE-SETTLE
            _TPT-ROW @ _TPT-W @ _TREE-O-SCROLL + @ +
            DUP _TREE-TOTAL @ < 0= IF DROP -1 EXIT THEN
            _TPT-W @ SWAP _TREE-AT-ROW 0= IF -1 EXIT THEN
            _TREE-F-DEPTH @ _TREE-INDENT * _TPT-COL @ = >R
            _TPT-W @ _TREE-SELECT-FOUND
            \ A press on the mark also toggles; the selection callback may
            \ have walked, so find the row again.
            R> IF
                _TPT-W @ DUP _TREE-O-CURSOR + @ _TREE-AT-KEY IF
                    _TPT-W @ _TREE-TOGGLE-FOUND
                THEN
            THEN
            -1 EXIT
        ENDOF
    ENDCASE
    DROP 0 ;

: _TREE-KEYS  ( code widget -- consumed? )
    DUP _TREE-SETTLE
    _TREE-TOTAL @ 0= IF 2DROP 0 EXIT THEN
    SWAP CASE
        KEY-UP OF
            _TREE-CUR-ROW @ 1- 0 MAX SWAP _TREE-SELECT-ROW -1
        ENDOF
        KEY-DOWN OF
            _TREE-CUR-ROW @ 1+ _TREE-TOTAL @ 1- MIN SWAP _TREE-SELECT-ROW -1
        ENDOF
        KEY-HOME OF 0 SWAP _TREE-SELECT-ROW -1 ENDOF
        KEY-END OF _TREE-TOTAL @ 1- SWAP _TREE-SELECT-ROW -1 ENDOF
        KEY-PGUP OF
            _TREE-CUR-ROW @ OVER WDG-REGION RGN-H - 0 MAX
            SWAP _TREE-SELECT-ROW -1
        ENDOF
        KEY-PGDN OF
            _TREE-CUR-ROW @ OVER WDG-REGION RGN-H + _TREE-TOTAL @ 1- MIN
            SWAP _TREE-SELECT-ROW -1
        ENDOF
        KEY-RIGHT OF
            DUP _TREE-CUR-ROW @ _TREE-AT-ROW IF
                _TREE-EXPAND-FOUND
            ELSE DROP THEN
            -1
        ENDOF
        KEY-LEFT OF
            DUP _TREE-CUR-ROW @ _TREE-AT-ROW IF
                _TREE-F-KEY @ OVER _TREE-XHAS? IF
                    _TREE-COLLAPSE-FOUND
                ELSE
                    _TREE-F-PKEY @ ?DUP IF
                        OVER SWAP _TREE-AT-KEY IF
                            _TREE-SELECT-FOUND
                        ELSE DROP THEN
                    ELSE DROP THEN
                THEN
            ELSE DROP THEN
            -1
        ENDOF
        KEY-ENTER OF _TREE-OPEN -1 ENDOF
        NIP 0 SWAP
    ENDCASE ;

: _TREE-HANDLE  ( event widget -- consumed? )
    OVER @ KEY-T-MOUSE = IF _TREE-POINTER EXIT THEN
    OVER KEY-IS-SPECIAL? 0= IF 2DROP 0 EXIT THEN
    SWAP KEY-CODE@ SWAP _TREE-KEYS ;

\ =====================================================================
\  §8 — Storage authority
\ =====================================================================

: _TREE-GENUINE?  ( widget -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _TREE-DESC-SZ MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    DUP _WDG-O-TYPE + @ WDG-T-TREE <> IF DROP 0 EXIT THEN
    DUP _WDG-O-DRAW-XT + @ ['] _TREE-DRAW <> IF DROP 0 EXIT THEN
    DUP _WDG-O-HANDLE-XT + @ ['] _TREE-HANDLE <> IF DROP 0 EXIT THEN
    DUP _TREE-O-INSTANCE + @ 0= IF DROP 0 EXIT THEN
    WDG-REGION DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    RGN-SIZE MSPAN-NONWRAPPING? ;

\ Pure and deliberately unguarded: a caller span against the module's
\ mutable scratch.
: TREE-STORAGE-DISJOINT?  ( address bytes -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF DROP 0= EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    _TREE-OWNED-LIMIT @ DUP _TREE-OWNED-START U< IF
        DROP 2DROP 0 EXIT
    THEN
    _TREE-OWNED-START - >R
    _TREE-OWNED-START R> MSPAN-OVERLAP? 0= ;

VARIABLE _TREE-SD-A
VARIABLE _TREE-SD-U
VARIABLE _TREE-SD-W

\ TREE-ITEM-VIEW-STORAGE-DISJOINT? ( address bytes widget -- flag )
\   A caller span against the module and one live tree's descriptor,
\   region, and expanded keys.
: TREE-ITEM-VIEW-STORAGE-DISJOINT?  ( address bytes widget -- flag )
    >R
    2DUP TREE-STORAGE-DISJOINT? 0= IF 2DROP R> DROP 0 EXIT THEN
    _TREE-SD-U ! _TREE-SD-A ! R> _TREE-SD-W !
    _TREE-SD-W @ _TREE-GENUINE? 0= IF 0 EXIT THEN
    _TREE-SD-U @ 0= IF -1 EXIT THEN
    _TREE-SD-A @ _TREE-SD-U @
        _TREE-SD-W @ _TREE-DESC-SZ MSPAN-OVERLAP? IF 0 EXIT THEN
    _TREE-SD-A @ _TREE-SD-U @
        _TREE-SD-W @ WDG-REGION RGN-SIZE MSPAN-OVERLAP? IF 0 EXIT THEN
    _TREE-SD-W @ _TREE-O-XA + @ ?DUP IF
        _TREE-SD-A @ _TREE-SD-U @ ROT
        _TREE-SD-W @ _TREE-O-XCAP + @ CELLS MSPAN-OVERLAP? IF 0 EXIT THEN
    THEN
    -1 ;

\ =====================================================================
\  §9 — Item view capture
\ =====================================================================
\  The shown rows, and the selected row wherever it is, as a TREE item
\  view with one unlabelled text column.  Row keys come from key-xt,
\  parents are the parent keys the walk passes down, and ordinals are
\  the visible rows.

VARIABLE _TREE-C-ROOT
VARIABLE _TREE-C-DST
VARIABLE _TREE-C-CAP
VARIABLE _TREE-C-BUILDER
VARIABLE _TREE-C-W
VARIABLE _TREE-C-H
VARIABLE _TREE-C-WIDTH
VARIABLE _TREE-C-STATE
VARIABLE _TREE-C-FIRST
VARIABLE _TREE-C-COUNT
VARIABLE _TREE-C-END
VARIABLE _TREE-CV-NODE
VARIABLE _TREE-CV-DEPTH
VARIABLE _TREE-CV-KEY
VARIABLE _TREE-CV-PKEY
VARIABLE _TREE-CV-ROW
VARIABLE _TREE-CV-STATE

\ The builder latches its first failure, which USCOL-BUILDER-FINISH
\ reports, so the visitor does not stop on one.
: _TREE-CAPTURE-CB  ( node depth key parent-key row -- )
    _TREE-CV-ROW ! _TREE-CV-PKEY ! _TREE-CV-KEY !
    _TREE-CV-DEPTH ! _TREE-CV-NODE !
    _TREE-CV-ROW @ _TREE-C-END @ < 0= IF -1 _TREE-FOUND ! EXIT THEN
    _TREE-CV-ROW @ _TREE-C-FIRST @ - _TREE-C-COUNT @ U<
    _TREE-CV-ROW @ _TREE-CUR-ROW @ = OR 0= IF EXIT THEN
    0 _TREE-CV-STATE !
    _TREE-CV-ROW @ _TREE-CUR-ROW @ = IF
        USCOL-IV-SELECTED _TREE-CV-STATE !
    THEN
    _TREE-CV-NODE @ _TREE-LEAF? 0= IF
        _TREE-CV-STATE @ USCOL-IV-EXPANDABLE OR _TREE-CV-STATE !
        _TREE-CV-NODE @ _TREE-CV-KEY @ _TREE-OPEN-BRANCH? IF
            _TREE-CV-STATE @ USCOL-IV-EXPANDED OR _TREE-CV-STATE !
        THEN
    THEN
    _TREE-CV-KEY @ _TREE-CV-PKEY @ _TREE-CV-ROW @ _TREE-CV-DEPTH @
    _TREE-CV-STATE @ USCOL-IV-ITEM
        _TREE-C-BUILDER @ USCOL-ITEMS-ITEM-BEGIN DROP
    _TREE-CV-NODE @ _TREE-LABEL
        _TREE-C-BUILDER @ USCOL-ITEMS-FIELD DROP
    _TREE-C-BUILDER @ USCOL-ITEMS-ITEM-END DROP ;

: _TREE-CAPTURE-PREFLIGHT?  ( root destination capacity builder widget -- flag )
    DUP _TREE-GENUINE? 0= IF 0 EXIT THEN
    4 PICK 0= IF 0 EXIT THEN
    3 PICK 3 PICK 2 PICK TREE-ITEM-VIEW-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    1 PICK USCOL-BUILDER-SIZE 2 PICK
        TREE-ITEM-VIEW-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    1 PICK USCOL-BUILDER-SIZE USCOL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    3 PICK 3 PICK USCOL-STORAGE-DISJOINT? 0= IF 0 EXIT THEN
    -1 ;

: _TREE-C-ROOT-STATE  ( -- state )
    0
    _TREE-C-W @ WDG-VISIBLE? IF USCOL-STATE-VISIBLE OR THEN
    _TREE-C-W @ WDG-DISABLED? 0= IF USCOL-STATE-ENABLED OR THEN
    _TREE-C-W @ WDG-FOCUSED?
    _TREE-C-W @ WDG-VISIBLE? AND
    _TREE-C-W @ WDG-DISABLED? 0= AND IF USCOL-STATE-SELECTED OR THEN ;

\ TREE-ITEM-VIEW-CAPTURE
\   ( root-key destination capacity builder widget -- bytes status )
\   Build the tree's item view with the caller's builder: copy mode with a
\   destination, exact measure mode with (0, 0).
: TREE-ITEM-VIEW-CAPTURE
    ( root-key destination capacity builder widget -- bytes status )
    _TREE-CAPTURE-PREFLIGHT? 0= IF
        2DROP 2DROP DROP 0 USCOL-S-INVALID EXIT
    THEN
    _TREE-C-W ! _TREE-C-BUILDER ! _TREE-C-CAP !
    _TREE-C-DST ! _TREE-C-ROOT !
    _TREE-C-DST @ _TREE-C-CAP @ _TREE-C-BUILDER @ USCOL-BUILDER-INIT
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TREE-C-W @ WDG-REGION RGN-H DUP 0> 0= IF
        DROP 0 USCOL-S-UNAVAILABLE EXIT
    THEN _TREE-C-H !
    _TREE-C-W @ WDG-REGION RGN-W DUP 0> 0= IF
        DROP 0 USCOL-S-UNAVAILABLE EXIT
    THEN _TREE-C-WIDTH !
    _TREE-C-W @ _TREE-SETTLE
    _TREE-C-W @ _TREE-O-SCROLL + @ _TREE-C-FIRST !
    _TREE-TOTAL @ _TREE-C-FIRST @ - _TREE-C-H @ MIN 0 MAX _TREE-C-COUNT !
    _TREE-C-FIRST @ _TREE-C-COUNT @ + _TREE-CUR-ROW @ 1+ MAX _TREE-C-END !
    _TREE-C-ROOT-STATE _TREE-C-STATE !
    _TREE-C-ROOT @ 0 0 _TREE-C-H @ _TREE-C-WIDTH @ _TREE-C-STATE @
        _TREE-C-BUILDER @ USCOL-ITEMS-BEGIN
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    USCOL-IV-TREE 0 _TREE-TOTAL @ _TREE-C-FIRST @ _TREE-C-COUNT @
        _TREE-C-BUILDER @ USCOL-ITEMS-SHAPE
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    USCOL-IV-TEXT 0 0 _TREE-C-BUILDER @ USCOL-ITEMS-COLUMN
    DUP USCOL-S-OK <> IF 0 SWAP EXIT THEN DROP
    _TREE-C-W @ ['] _TREE-CAPTURE-CB _TREE-WALK
    _TREE-C-BUILDER @ USCOL-ITEMS-END DROP
    _TREE-C-BUILDER @ USCOL-BUILDER-FINISH ;

\ TREE-ITEM-VIEW-MEASURE ( root-key builder widget -- bytes status )
: TREE-ITEM-VIEW-MEASURE  ( root-key builder widget -- bytes status )
    >R >R 0 0 R> R> TREE-ITEM-VIEW-CAPTURE ;

\ =====================================================================
\  §10 — Constructor
\ =====================================================================

: TREE-NEW  ( rgn root children-xt next-xt label-xt leaf?-xt key-xt -- widget )
    >R >R >R >R >R >R          ( rgn   R: key leaf label next child root )
    _TREE-DESC-SZ ALLOCATE
    0<> ABORT" TREE-NEW: alloc"
    DUP _TREE-DESC-SZ 0 FILL
    WDG-T-TREE       OVER _WDG-O-TYPE       + !
    SWAP              OVER _WDG-O-REGION     + !
    ['] _TREE-DRAW    OVER _WDG-O-DRAW-XT    + !
    ['] _TREE-HANDLE  OVER _WDG-O-HANDLE-XT  + !
    WDG-F-VISIBLE WDG-F-DIRTY OR
                      OVER _WDG-O-FLAGS      + !
    R>                OVER _TREE-O-ROOT      + !
    R>                OVER _TREE-O-CHILD-XT  + !
    R>                OVER _TREE-O-NEXT-XT   + !
    R>                OVER _TREE-O-LABEL-XT  + !
    R>                OVER _TREE-O-LEAF-XT   + !
    R>                OVER _TREE-O-KEY-XT    + !
    _TREE-CLAIM-INSTANCE OVER _TREE-O-INSTANCE + ! ;

\ =====================================================================
\  §11 — Public API
\ =====================================================================

\ TREE-SELECTED ( w -- node|0 )   The selected node.
: TREE-SELECTED  ( w -- node|0 )
    DUP _TREE-SETTLE
    _TREE-TOTAL @ 0= IF DROP 0 EXIT THEN
    _TREE-CUR-ROW @ _TREE-AT-ROW IF _TREE-F-NODE @ ELSE 0 THEN ;

\ TREE-SELECTED-KEY ( w -- key|0 )   The selected node's key.
: TREE-SELECTED-KEY  ( w -- key|0 )
    DUP _TREE-SETTLE
    _TREE-TOTAL @ IF _TREE-O-CURSOR + @ ELSE DROP 0 THEN ;

\ TREE-SELECT ( w node -- )   Select a shown node.
: TREE-SELECT  ( w node -- )
    OVER SWAP _TREE-AT-NODE IF _TREE-SELECT-FOUND ELSE DROP THEN ;

\ TREE-ON-SELECT ( xt w -- )   Callback ( widget -- ) when the selection
\   moves to another node.
: TREE-ON-SELECT  ( xt w -- )  _TREE-O-ON-SEL + ! ;

\ TREE-ON-OPEN ( xt w -- )   Callback ( widget -- ) when the selection is
\   opened by Enter or a renderer's OPEN.  Without one, opening a branch
\   expands or collapses it.
: TREE-ON-OPEN  ( xt w -- )  _TREE-O-ON-OPEN + ! ;

\ TREE-CONTEXT! ( context w -- ) and TREE-CONTEXT@ ( w -- context )
\   The caller's context cell, which callbacks read with TREE-WALK-CONTEXT.
: TREE-CONTEXT!  ( context w -- )  _TREE-O-CONTEXT + ! ;
: TREE-CONTEXT@  ( w -- context )  _TREE-O-CONTEXT + @ ;

: TREE-EXPAND  ( w node -- )
    OVER SWAP _TREE-AT-NODE IF _TREE-EXPAND-FOUND ELSE DROP THEN ;

: TREE-COLLAPSE  ( w node -- )
    OVER SWAP _TREE-AT-NODE IF _TREE-COLLAPSE-FOUND ELSE DROP THEN ;

: TREE-TOGGLE  ( w node -- )
    OVER SWAP _TREE-AT-NODE IF _TREE-TOGGLE-FOUND ELSE DROP THEN ;

\ TREE-EXPANDED? ( w node -- flag )   Is a shown node expanded?
: TREE-EXPANDED?  ( w node -- flag )
    OVER SWAP _TREE-AT-NODE 0= IF DROP 0 EXIT THEN
    _TREE-F-KEY @ SWAP _TREE-XHAS? ;

\ Expanding a node lets the walk descend into it, so one walk expands
\ every branch it can reach.
: _TREE-EXPAND-ALL-CB  ( node depth key parent-key row -- )
    2DROP ROT _TREE-LEAF? IF 2DROP EXIT THEN
    NIP _TW-W @ _TREE-XADD DROP ;

: TREE-EXPAND-ALL  ( w -- )
    DUP ['] _TREE-EXPAND-ALL-CB _TREE-WALK
    WDG-DIRTY ;

\ TREE-COLLAPSE-ALL ( w -- )   Collapse every branch.
: TREE-COLLAPSE-ALL  ( w -- )
    DUP _TREE-O-CURSOR + @ >R
    0 OVER _TREE-O-XN + !
    DUP _TREE-SETTLE
    DUP _TREE-O-CURSOR + @ R> <> IF
        DUP _TREE-O-ON-SEL + @ ?DUP IF OVER SWAP EXECUTE THEN
    THEN
    WDG-DIRTY ;

: TREE-REFRESH  ( w -- )  WDG-DIRTY ;

\ TREE-SCROLL-INFO ( widget -- content-h offset visible-h )
\   Return scroll parameters for the scroll container.
: TREE-SCROLL-INFO  ( widget -- content-h offset visible-h )
    DUP _TREE-SETTLE
    _TREE-TOTAL @
    OVER _TREE-O-SCROLL + @
    ROT WDG-REGION RGN-H ;

\ TREE-SCROLL-SET ( offset widget -- )
\   Set scroll-top directly (clamped).  Does NOT change the selection.
: TREE-SCROLL-SET  ( offset widget -- )
    >R
    R@ _TREE-VIS-COUNT R@ WDG-REGION RGN-H -
    DUP 0< IF DROP 0 THEN              \ max scroll
    MIN  0 MAX                          \ clamp 0..max
    R@ _TREE-O-SCROLL + !
    R> WDG-DIRTY ;

: TREE-INSTANCE@  ( widget -- token )
    DUP _TREE-GENUINE? 0= IF DROP 0 EXIT THEN
    _TREE-O-INSTANCE + @ ;

: TREE-FREE  ( w -- )
    DUP _TREE-O-XA + @ ?DUP IF FREE THEN
    FREE ;

\ =====================================================================
\  §12 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _tree-guard

' TREE-NEW         CONSTANT _tree-new-xt
' TREE-SELECTED    CONSTANT _tree-sel-xt
' TREE-SELECTED-KEY CONSTANT _tree-sel-key-xt
' TREE-SELECT      CONSTANT _tree-select-xt
' TREE-ON-SELECT   CONSTANT _tree-onsel-xt
' TREE-ON-OPEN     CONSTANT _tree-onopen-xt
' TREE-CONTEXT!    CONSTANT _tree-context-s-xt
' TREE-CONTEXT@    CONSTANT _tree-context-g-xt
' TREE-EXPAND      CONSTANT _tree-exp-xt
' TREE-COLLAPSE    CONSTANT _tree-col-xt
' TREE-TOGGLE      CONSTANT _tree-tog-xt
' TREE-EXPANDED?   CONSTANT _tree-expq-xt
' TREE-EXPAND-ALL  CONSTANT _tree-exall-xt
' TREE-COLLAPSE-ALL CONSTANT _tree-colall-xt
' TREE-REFRESH     CONSTANT _tree-ref-xt
' TREE-INSTANCE@   CONSTANT _tree-instance-xt
' TREE-ITEM-VIEW-CAPTURE CONSTANT _tree-capture-xt
' TREE-ITEM-VIEW-MEASURE CONSTANT _tree-measure-xt
' TREE-ITEM-VIEW-STORAGE-DISJOINT? CONSTANT _tree-disjoint-q-xt
' TREE-FREE        CONSTANT _tree-free-xt

: TREE-NEW         _tree-new-xt    _tree-guard WITH-GUARD ;
: TREE-SELECTED    _tree-sel-xt    _tree-guard WITH-GUARD ;
: TREE-SELECTED-KEY _tree-sel-key-xt _tree-guard WITH-GUARD ;
: TREE-SELECT      _tree-select-xt _tree-guard WITH-GUARD ;
: TREE-ON-SELECT   _tree-onsel-xt  _tree-guard WITH-GUARD ;
: TREE-ON-OPEN     _tree-onopen-xt _tree-guard WITH-GUARD ;
: TREE-CONTEXT!    _tree-context-s-xt _tree-guard WITH-GUARD ;
: TREE-CONTEXT@    _tree-context-g-xt _tree-guard WITH-GUARD ;
: TREE-EXPAND      _tree-exp-xt    _tree-guard WITH-GUARD ;
: TREE-COLLAPSE    _tree-col-xt    _tree-guard WITH-GUARD ;
: TREE-TOGGLE      _tree-tog-xt    _tree-guard WITH-GUARD ;
: TREE-EXPANDED?   _tree-expq-xt   _tree-guard WITH-GUARD ;
: TREE-EXPAND-ALL  _tree-exall-xt  _tree-guard WITH-GUARD ;
: TREE-COLLAPSE-ALL _tree-colall-xt _tree-guard WITH-GUARD ;
: TREE-REFRESH     _tree-ref-xt    _tree-guard WITH-GUARD ;
: TREE-INSTANCE@   _tree-instance-xt _tree-guard WITH-GUARD ;
: TREE-ITEM-VIEW-CAPTURE _tree-capture-xt _tree-guard WITH-GUARD ;
: TREE-ITEM-VIEW-MEASURE _tree-measure-xt _tree-guard WITH-GUARD ;
: TREE-ITEM-VIEW-STORAGE-DISJOINT?
    _tree-disjoint-q-xt _tree-guard WITH-GUARD ;
: TREE-FREE        _tree-free-xt   _tree-guard WITH-GUARD ;
[THEN] [THEN]

CREATE _TREE-OWNED-END
_TREE-OWNED-END _TREE-OWNED-LIMIT !
