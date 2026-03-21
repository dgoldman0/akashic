\ =================================================================
\  tree.f  —  Tree View Widget
\ =================================================================
\  Megapad-64 / KDOS Forth      Prefix: TREE- / _TREE-
\  Depends on: akashic-tui-widget, akashic-tui-draw, akashic-tui-region,
\              akashic-tui-keys
\
\  Collapsible tree display for hierarchical data.  The widget does
\  NOT own the tree data — it discovers the structure through four
\  user-supplied callbacks:
\
\   children-xt  ( node -- first-child | 0 )
\   next-xt      ( node -- sibling | 0 )
\   label-xt     ( node -- addr len )
\   leaf?-xt     ( node -- flag )
\
\  Nodes are opaque cell-sized tokens (pointers, handles, indices).
\  0 means "no node" / NIL.
\
\  Navigation: Up/Down move cursor.  Right expands, Left collapses,
\  Enter toggles.  Selection callback fires on Enter.
\
\  Expand/collapse state is stored in a flat bitmap indexed by DFS
\  order position.  The tree is re-walked on each draw / query.
\  For moderate trees (< 512 visible nodes) this is fast enough.
\
\  Descriptor layout (header + 9 cells = 112 bytes):
\   +40  root          Root node token
\   +48  children-xt   Callback: first child
\   +56  next-xt       Callback: next sibling
\   +64  label-xt      Callback: node label
\   +72  leaf-xt       Callback: is-leaf?
\   +80  cursor        Selected visible-row index
\   +88  scroll-top    First visible row (scroll offset)
\   +96  on-sel-xt     Selection callback xt (0 = none)
\   +104 exp-buf       Expand bitmap buffer
\ =================================================================

PROVIDED akashic-tui-tree

REQUIRE ../widget.f
REQUIRE ../region.f
REQUIRE ../draw.f
REQUIRE ../keys.f

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
80  CONSTANT _TREE-O-CURSOR
88  CONSTANT _TREE-O-SCROLL
96  CONSTANT _TREE-O-ON-SEL
104 CONSTANT _TREE-O-EXP-BUF
112 CONSTANT _TREE-DESC-SZ

512 CONSTANT _TREE-MAX-NODES
2   CONSTANT _TREE-INDENT

\ Tree-guide codepoints
9500 CONSTANT _TREE-TEE      \ U+251C ├
9492 CONSTANT _TREE-ELL      \ U+2514 └
9474 CONSTANT _TREE-PIPE     \ U+2502 │
9472 CONSTANT _TREE-DASH     \ U+2500 ─

\ Expand indicators
9654 CONSTANT _TREE-ARROW-R  \ U+25B6 ▶  collapsed
9660 CONSTANT _TREE-ARROW-D  \ U+25BC ▼  expanded

\ =====================================================================
\  §2 — Expand bitmap helpers
\ =====================================================================

: _TREE-EXP!  ( w idx -- )
    DUP 3 RSHIFT
    2 PICK _TREE-O-EXP-BUF + @ +
    SWAP 7 AND 1 SWAP LSHIFT
    OVER C@ OR SWAP C! DROP ;

: _TREE-COL!  ( w idx -- )
    DUP 3 RSHIFT
    2 PICK _TREE-O-EXP-BUF + @ +
    SWAP 7 AND 1 SWAP LSHIFT INVERT
    OVER C@ AND SWAP C! DROP ;

: _TREE-EXP?  ( w idx -- flag )
    DUP 3 RSHIFT
    2 PICK _TREE-O-EXP-BUF + @ +
    SWAP 7 AND 1 SWAP LSHIFT
    SWAP C@ AND 0<> NIP ;

\ =====================================================================
\  §3 — Callback wrappers
\ =====================================================================

: _TREE-CHILDREN  ( w node -- first-child|0 )
    SWAP _TREE-O-CHILD-XT + @ EXECUTE ;
: _TREE-NEXT  ( w node -- sibling|0 )
    SWAP _TREE-O-NEXT-XT + @ EXECUTE ;
: _TREE-LABEL  ( w node -- addr len )
    SWAP _TREE-O-LABEL-XT + @ EXECUTE ;
: _TREE-LEAF?  ( w node -- flag )
    SWAP _TREE-O-LEAF-XT + @ EXECUTE ;

\ =====================================================================
\  §4 — Recursive DFS walk engine
\ =====================================================================
\  Walks the tree in DFS order following sibling chains.  For every
\  visible node, calls  xt ( node depth dfs-idx -- ).
\  The walk checks _TREE-FOUND after each callback; a non-zero value
\  short-circuits the walk (used by find-node).
\
\  All state lives in variables to avoid R-stack pressure.

VARIABLE _TW-W        \ widget pointer
VARIABLE _TW-XT       \ visitor callback xt
VARIABLE _TW-IDX      \ DFS index counter
VARIABLE _TREE-FOUND  \ short-circuit flag / result

: _TREE-DO-WALK  ( node depth -- )
    BEGIN
        OVER 0<>
    WHILE
        \ Visit this node
        OVER OVER _TW-IDX @              ( node depth node depth idx )
        _TW-XT @ EXECUTE
        1 _TW-IDX +!
        _TREE-FOUND @ IF 2DROP EXIT THEN

        \ If non-leaf and expanded, recurse into children
        _TW-W @ 2 PICK _TREE-LEAF? 0= IF
            _TW-W @ _TW-IDX @ 1- _TREE-EXP? IF
                _TW-W @ 2 PICK _TREE-CHILDREN  ( node depth child )
                ?DUP IF
                    OVER 1+ RECURSE      ( node depth )
                    _TREE-FOUND @ IF 2DROP EXIT THEN
                THEN
            THEN
        THEN

        \ Advance to next sibling
        SWAP _TW-W @ SWAP _TREE-NEXT     ( depth sibling )
        SWAP
    REPEAT
    2DROP ;

: _TREE-WALK  ( w xt -- )
    _TW-XT !  _TW-W !
    0 _TW-IDX !  0 _TREE-FOUND !
    _TW-W @ _TREE-O-ROOT + @
    0 _TREE-DO-WALK ;

\ =====================================================================
\  §5 — Count visible rows
\ =====================================================================

VARIABLE _TREE-TOTAL

: _TREE-CNT-CB  ( node depth idx -- )
    3DROP 1 _TREE-TOTAL +! ;

: _TREE-VIS-COUNT  ( w -- n )
    0 _TREE-TOTAL !
    ['] _TREE-CNT-CB _TREE-WALK
    _TREE-TOTAL @ ;

\ =====================================================================
\  §6 — Find node at visible row N
\ =====================================================================

VARIABLE _TREE-TARGET
VARIABLE _TREE-ROW-CTR
VARIABLE _TREE-FDEPTH

: _TREE-FIND-CB  ( node depth idx -- )
    DROP
    _TREE-ROW-CTR @ _TREE-TARGET @ = IF
        _TREE-FDEPTH !
        _TREE-FOUND !                    \ non-zero → short-circuits walk
    ELSE
        2DROP
    THEN
    1 _TREE-ROW-CTR +! ;

: _TREE-NODE-AT  ( w row -- node depth | 0 0 )
    _TREE-TARGET !
    0 _TREE-ROW-CTR !
    ['] _TREE-FIND-CB _TREE-WALK
    _TREE-FOUND @ ?DUP IF
        _TREE-FDEPTH @
    ELSE 0 0 THEN ;

\ =====================================================================
\  §7 — Find DFS index of a node (by identity)
\ =====================================================================
\  Used by TREE-EXPAND / TREE-COLLAPSE / TREE-TOGGLE to map a
\  node token to its expand-bitmap index.

VARIABLE _TREE-SEEK       \ node token we're looking for
VARIABLE _TREE-SEEK-IDX   \ result DFS index (-1 = not found)

: _TREE-IDX-CB  ( node depth idx -- )
    SWAP DROP                            ( node idx )
    OVER _TREE-SEEK @ = IF
        _TREE-SEEK-IDX !
        _TREE-FOUND !                    \ short-circuit (node is non-zero)
    ELSE
        2DROP
    THEN ;

: _TREE-NODE>IDX  ( w node -- idx | -1 )
    _TREE-SEEK !  -1 _TREE-SEEK-IDX !
    ['] _TREE-IDX-CB _TREE-WALK
    _TREE-SEEK-IDX @ ;

\ =====================================================================
\  §8 — Draw handler
\ =====================================================================

VARIABLE _TREE-SCRL
VARIABLE _TREE-VH

: _TREE-DRAW-LINE  ( node depth idx -- )
    >R                                    ( node depth   R: idx )

    \ Screen row = visible-row-counter − scroll-top
    _TREE-ROW-CTR @ _TREE-SCRL @ -       ( node depth scr-row )

    \ Skip rows outside viewport
    DUP 0< OVER _TREE-VH @ >= OR IF
        2DROP DROP R> DROP
        1 _TREE-ROW-CTR +! EXIT
    THEN

    \ Highlight selected row (reverse video)
    _TREE-ROW-CTR @ _TW-W @ _TREE-O-CURSOR + @ = IF
        0 DRW-FG! 7 DRW-BG! 0 DRW-ATTR!
    ELSE
        DRW-STYLE-RESTORE
    THEN

    \ Fill row with spaces (background)
    32 OVER 0 _TW-W @ WDG-REGION RGN-W DRW-HLINE  ( node depth scr-row )

    \ Compute indent column
    SWAP _TREE-INDENT *                   ( node scr-row col )

    \ Draw expand/collapse indicator
    2 PICK _TW-W @ SWAP _TREE-LEAF? IF
        \ Leaf — plain space
        32 2 PICK 2 PICK DRW-CHAR        ( node scr-row col )
    ELSE
        _TW-W @ R@ _TREE-EXP? IF
            _TREE-ARROW-D
        ELSE
            _TREE-ARROW-R
        THEN
        2 PICK 2 PICK DRW-CHAR           ( node scr-row col )
    THEN
    R> DROP                               ( node scr-row col )

    \ Column past indicator + gap
    2 +                                   ( node scr-row col )

    \ Draw label text
    ROT _TW-W @ SWAP _TREE-LABEL         ( scr-row col addr len )
    2SWAP DRW-TEXT

    1 _TREE-ROW-CTR +! ;

: _TREE-DRAW  ( widget -- )
    DUP _TREE-O-SCROLL + @ _TREE-SCRL !
    DUP WDG-REGION RGN-H _TREE-VH !
    0 _TREE-ROW-CTR !
    ['] _TREE-DRAW-LINE _TREE-WALK ;

\ =====================================================================
\  §9 — Scroll / cursor helpers
\ =====================================================================

: _TREE-CLAMP  ( widget -- )
    DUP _TREE-VIS-COUNT                  ( w total )
    DUP 0= IF 2DROP EXIT THEN
    1-
    OVER _TREE-O-CURSOR + @
    OVER MIN DUP 0< IF DROP 0 THEN
    NIP SWAP _TREE-O-CURSOR + ! ;

VARIABLE _TSC-CUR  VARIABLE _TSC-SCR  VARIABLE _TSC-VH

: _TREE-SCROLL  ( widget -- )
    DUP _TREE-O-CURSOR + @ _TSC-CUR !
    DUP _TREE-O-SCROLL + @ _TSC-SCR !
    DUP WDG-REGION RGN-H _TSC-VH !
    _TSC-CUR @ _TSC-SCR @ < IF           \ cursor above viewport
        _TSC-CUR @ SWAP _TREE-O-SCROLL + ! EXIT
    THEN
    _TSC-CUR @ _TSC-SCR @ _TSC-VH @ + >= IF  \ cursor below viewport
        _TSC-CUR @ _TSC-VH @ - 1+ DUP 0< IF DROP 0 THEN
        SWAP _TREE-O-SCROLL + ! EXIT
    THEN
    DROP ;

\ =====================================================================
\  §10 — Event handler
\ =====================================================================

: _TREE-HANDLE  ( event widget -- consumed? )
    OVER KEY-IS-SPECIAL? 0= IF 2DROP 0 EXIT THEN
    OVER KEY-CODE@                        ( ev w code )

    DUP KEY-UP = IF
        DROP NIP                          ( w )
        DUP _TREE-O-CURSOR + @            ( w cur )
        DUP 0> IF 1- THEN                 ( w new-cur )
        OVER _TREE-O-CURSOR + !           ( w )
        DUP _TREE-SCROLL  WDG-DIRTY -1 EXIT
    THEN

    DUP KEY-DOWN = IF
        DROP NIP
        DUP _TREE-O-CURSOR + @ 1+
        OVER _TREE-O-CURSOR + !
        DUP _TREE-CLAMP
        DUP _TREE-SCROLL  WDG-DIRTY -1 EXIT
    THEN

    DUP KEY-RIGHT = IF                    \ expand
        DROP NIP
        DUP _TREE-O-CURSOR + @
        OVER SWAP _TREE-NODE-AT DROP      ( w node )
        ?DUP IF
            OVER SWAP
            2DUP _TREE-LEAF? 0= IF
                OVER SWAP _TREE-NODE>IDX  ( w idx )
                DUP 0>= IF  OVER SWAP _TREE-EXP!  ELSE DROP  THEN
            ELSE DROP THEN
        THEN
        WDG-DIRTY -1 EXIT
    THEN

    DUP KEY-LEFT = IF                     \ collapse
        DROP NIP
        DUP _TREE-O-CURSOR + @
        OVER SWAP _TREE-NODE-AT DROP
        ?DUP IF
            OVER SWAP
            2DUP _TREE-LEAF? 0= IF
                OVER SWAP _TREE-NODE>IDX
                DUP 0>= IF  OVER SWAP _TREE-COL!  ELSE DROP  THEN
            ELSE DROP THEN
        THEN
        WDG-DIRTY -1 EXIT
    THEN

    DUP KEY-ENTER = IF                    \ toggle + select callback
        DROP NIP
        DUP _TREE-O-CURSOR + @
        OVER SWAP _TREE-NODE-AT DROP      ( w node )
        ?DUP IF
            OVER SWAP
            2DUP _TREE-LEAF? 0= IF
                OVER SWAP _TREE-NODE>IDX  ( w idx )
                DUP 0>= IF
                    2DUP _TREE-EXP? IF
                        OVER SWAP _TREE-COL!
                    ELSE
                        OVER SWAP _TREE-EXP!
                    THEN
                ELSE DROP THEN
            ELSE DROP THEN
        THEN
        \ Fire selection callback
        DUP _TREE-O-ON-SEL + @ ?DUP IF
            OVER SWAP EXECUTE             ( w )  \ xt ( widget -- )
        THEN
        WDG-DIRTY -1 EXIT
    THEN

    3DROP 0 ;

\ =====================================================================
\  §11 — Constructor
\ =====================================================================

: TREE-NEW  ( rgn root children-xt next-xt label-xt leaf?-xt -- widget )
    >R >R >R >R >R                       ( rgn   R: leaf? label next child root )
    _TREE-DESC-SZ ALLOCATE
    0<> ABORT" TREE-NEW: alloc"
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
    0                 OVER _TREE-O-CURSOR    + !
    0                 OVER _TREE-O-SCROLL    + !
    0                 OVER _TREE-O-ON-SEL    + !
    _TREE-MAX-NODES 8 / DUP >R ALLOCATE
    0<> ABORT" TREE-NEW: exp-buf"
    DUP R> 0 FILL
    OVER _TREE-O-EXP-BUF + ! ;

\ =====================================================================
\  §12 — Public API
\ =====================================================================

: TREE-SELECTED  ( w -- node )
    DUP _TREE-O-CURSOR + @
    OVER SWAP _TREE-NODE-AT DROP ;

: TREE-ON-SELECT  ( w xt -- )
    SWAP _TREE-O-ON-SEL + ! ;

: TREE-EXPAND  ( w node -- )
    2DUP _TREE-LEAF? IF 2DROP EXIT THEN
    OVER SWAP _TREE-NODE>IDX              ( w idx )
    DUP 0>= IF OVER SWAP _TREE-EXP! ELSE DROP THEN
    WDG-DIRTY ;

: TREE-COLLAPSE  ( w node -- )
    2DUP _TREE-LEAF? IF 2DROP EXIT THEN
    OVER SWAP _TREE-NODE>IDX
    DUP 0>= IF OVER SWAP _TREE-COL! ELSE DROP THEN
    WDG-DIRTY ;

: TREE-TOGGLE  ( w node -- )
    2DUP _TREE-LEAF? IF 2DROP EXIT THEN
    OVER SWAP _TREE-NODE>IDX              ( w idx )
    DUP 0< IF DROP WDG-DIRTY EXIT THEN
    2DUP _TREE-EXP? IF
        OVER SWAP _TREE-COL!
    ELSE
        OVER SWAP _TREE-EXP!
    THEN
    WDG-DIRTY ;

: TREE-EXPAND-ALL  ( w -- )
    DUP _TREE-O-EXP-BUF + @
    _TREE-MAX-NODES 8 / 255 FILL
    WDG-DIRTY ;

: TREE-REFRESH  ( w -- )  WDG-DIRTY ;

\ TREE-SCROLL-INFO ( widget -- content-h offset visible-h )
\   Return scroll parameters for the scroll container.
: TREE-SCROLL-INFO  ( widget -- content-h offset visible-h )
    DUP _TREE-VIS-COUNT
    OVER _TREE-O-SCROLL + @
    ROT WDG-REGION RGN-H ;

\ TREE-SCROLL-SET ( offset widget -- )
\   Set scroll-top directly (clamped).  Does NOT change cursor.
: TREE-SCROLL-SET  ( offset widget -- )
    >R
    R@ _TREE-VIS-COUNT R@ WDG-REGION RGN-H -
    DUP 0< IF DROP 0 THEN              \ max scroll
    MIN  0 MAX                          \ clamp 0..max
    R@ _TREE-O-SCROLL + !
    R> WDG-DIRTY ;

: TREE-FREE  ( w -- )
    DUP _TREE-O-EXP-BUF + @ FREE
    FREE ;

\ =====================================================================
\  §13 — Guard
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../../concurrency/guard.f
GUARD _tree-guard

' TREE-NEW         CONSTANT _tree-new-xt
' TREE-SELECTED    CONSTANT _tree-sel-xt
' TREE-ON-SELECT   CONSTANT _tree-onsel-xt
' TREE-EXPAND      CONSTANT _tree-exp-xt
' TREE-COLLAPSE    CONSTANT _tree-col-xt
' TREE-TOGGLE      CONSTANT _tree-tog-xt
' TREE-EXPAND-ALL  CONSTANT _tree-exall-xt
' TREE-REFRESH     CONSTANT _tree-ref-xt
' TREE-FREE        CONSTANT _tree-free-xt

: TREE-NEW         _tree-new-xt    _tree-guard WITH-GUARD ;
: TREE-SELECTED    _tree-sel-xt    _tree-guard WITH-GUARD ;
: TREE-ON-SELECT   _tree-onsel-xt  _tree-guard WITH-GUARD ;
: TREE-EXPAND      _tree-exp-xt    _tree-guard WITH-GUARD ;
: TREE-COLLAPSE    _tree-col-xt    _tree-guard WITH-GUARD ;
: TREE-TOGGLE      _tree-tog-xt    _tree-guard WITH-GUARD ;
: TREE-EXPAND-ALL  _tree-exall-xt  _tree-guard WITH-GUARD ;
: TREE-REFRESH     _tree-ref-xt    _tree-guard WITH-GUARD ;
: TREE-FREE        _tree-free-xt   _tree-guard WITH-GUARD ;
[THEN] [THEN]
