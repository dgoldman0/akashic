\ dom-render.f — DOM-to-TUI Layout & Paint
\
\ Walks the DOM tree with attached DTUI sidecars, computes
\ simplified block/inline character-cell layout within a target
\ region, and paints the results into the TUI screen back buffer
\ using draw.f / box.f primitives.
\
\ Prefix: DREN-  (public)
\         _DREN- (internal)
\
\ Load with:   REQUIRE dom-render.f

PROVIDED akashic-tui-dom-render

REQUIRE dom-tui.f
REQUIRE draw.f
REQUIRE box.f
REQUIRE region.f
REQUIRE screen.f

\ =====================================================================
\  §1 — Layout State
\ =====================================================================

\ Viewport / available region
VARIABLE _DREN-RGN     \ region address (from DREN-LAYOUT)
VARIABLE _DREN-VW      \ available width for current layout level
VARIABLE _DREN-VH      \ viewport height (from region)

\ Cursor: current flow position during layout
VARIABLE _DREN-ROW     \ current row  (region-relative)
VARIABLE _DREN-COL     \ current col  (region-relative)
VARIABLE _DREN-LINE-H  \ tallest element on the current inline line
VARIABLE _DREN-LMAR    \ left margin for current content area

\ Per-node temporaries (set at start of each node, protected by R stack)
VARIABLE _DREN-ND      \ current node
VARIABLE _DREN-SC      \ current sidecar
VARIABLE _DREN-FL      \ sidecar flags cache

\ =====================================================================
\  §2 — Border Index → BOX-STYLE Mapping
\ =====================================================================

\ Map DTUI-BORDER-* constants to BOX-* style addresses.
\ 0=none, 1=single, 2=double, 3=rounded, 4=heavy
\ Table of 5 entries (0 = no border, stored as 0).
CREATE _DREN-BSTYLES  5 8 * ALLOT

: _DREN-INIT-BSTYLES  ( -- )
    0               _DREN-BSTYLES  0 8 * + !
    BOX-SINGLE      _DREN-BSTYLES  1 8 * + !
    BOX-DOUBLE      _DREN-BSTYLES  2 8 * + !
    BOX-ROUND       _DREN-BSTYLES  3 8 * + !
    BOX-HEAVY       _DREN-BSTYLES  4 8 * + ! ;

_DREN-INIT-BSTYLES

\ _DREN-BOX-STYLE ( border-idx -- style-addr|0 )
: _DREN-BOX-STYLE  ( idx -- style|0 )
    DUP 0< OVER 4 > OR IF DROP 0 EXIT THEN
    8 * _DREN-BSTYLES + @ ;

\ =====================================================================
\  §3 — Text Helpers
\ =====================================================================

CREATE _DREN-TXTBUF 1024 ALLOT
VARIABLE _DREN-TXTLEN

\ _DREN-COLLECT-TEXT ( node -- addr len )
\   Concatenate text content of immediate text-node children.
\   Consumes node (DOM-FIRST-CHILD uses it).
: _DREN-COLLECT-TEXT  ( node -- addr len )
    0 _DREN-TXTLEN !
    DOM-FIRST-CHILD
    BEGIN DUP WHILE
        DUP DOM-TYPE@ DOM-T-TEXT = IF
            DUP DOM-TEXT            \ child txt-a txt-u
            DUP _DREN-TXTLEN @ + 1024 > IF
                2DROP               \ overflow — skip
            ELSE
                DUP >R              \ save length
                _DREN-TXTBUF _DREN-TXTLEN @ +
                SWAP CMOVE          \ ( txt-a txt-u dest -- )
                R> _DREN-TXTLEN +!
            THEN
        THEN
        DOM-NEXT
    REPEAT
    DROP
    _DREN-TXTBUF _DREN-TXTLEN @ ;

\ _DREN-TEXT-WIDTH ( addr len -- n )
\   Count codepoints (character cells) in a UTF-8 string.
: _DREN-TEXT-WIDTH  ( addr len -- n )
    UTF8-LEN ;

\ =====================================================================
\  §4 — Layout Engine (Block / Inline Flow)
\ =====================================================================

\ _DREN-NEWLINE ( -- )
\   Move cursor to next row.  Advance by _DREN-LINE-H (minimum 1).
: _DREN-NEWLINE  ( -- )
    _DREN-LINE-H @ DUP 1 < IF DROP 1 THEN  _DREN-ROW +!
    _DREN-LMAR @ _DREN-COL !
    1 _DREN-LINE-H ! ;

\ Forward declaration of layout-children
VARIABLE _DREN-LAYOUT-CHILDREN-XT

\ _DREN-LAYOUT-NODE ( node -- )
\   Compute layout position for one element node and recurse.
\   All 8 global variables are saved/restored on the return stack
\   so recursive calls (via _DREN-LAYOUT-CHILDREN) are safe.
: _DREN-LAYOUT-NODE  ( node -- )
    \ --- Validate ---
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    DUP N.AUX @  DUP 0= IF 2DROP EXIT THEN
    _DREN-SC !  _DREN-ND !

    _DREN-SC @ DTUI-SC-FLAGS  _DREN-FL !

    \ --- Skip invisible (display:none) ---
    _DREN-FL @ DTUI-F-VISIBLE AND 0= IF EXIT THEN

    \ --- Block: force new line if mid-line ---
    _DREN-FL @ DTUI-F-BLOCK AND IF
        _DREN-COL @ _DREN-LMAR @ > IF _DREN-NEWLINE THEN
    THEN

    \ --- Compute border inset (0 or 1) ---
    _DREN-SC @ DTUI-SC-STYLE DTUI-UNPACK-BORDER 0<> IF 1 ELSE 0 THEN
    \ Stack: bi

    \ --- Compute width ---
    _DREN-SC @ DTUI-SC-W DUP 0> IF
        \ Explicit CSS width + 2*border
        OVER 2* +               \ Stack: bi width
    ELSE
        DROP
        _DREN-FL @ DTUI-F-BLOCK AND IF
            \ Block: fill available width (min 2*bi)
            _DREN-LMAR @ _DREN-VW @ + _DREN-COL @ -
            OVER 2* MAX         \ Stack: bi width
        ELSE
            \ Inline: text width + 2*border
            DUP 2*
            _DREN-ND @ _DREN-COLLECT-TEXT
            _DREN-TEXT-WIDTH +  \ Stack: bi width
        THEN
    THEN

    \ Clamp width to available space
    _DREN-LMAR @ _DREN-VW @ + _DREN-COL @ -  MIN
    DUP 1 < IF 2DROP EXIT THEN
    \ Stack: bi width

    NIP
    \ Stack: width

    \ --- Compute height ---
    _DREN-SC @ DTUI-SC-H DUP 0> IF
        \ Explicit CSS height; add 2 for top/bottom border
        _DREN-SC @ DTUI-SC-STYLE DTUI-UNPACK-BORDER IF 2 + THEN
    ELSE
        DROP
        _DREN-SC @ DTUI-SC-STYLE DTUI-UNPACK-BORDER IF 3 ELSE 1 THEN
    THEN
    \ Stack: width height

    \ --- Store position & dimensions into sidecar ---
    _DREN-ROW @  _DREN-SC @ DTUI-SC-ROW!
    _DREN-COL @  _DREN-SC @ DTUI-SC-COL!
    OVER         _DREN-SC @ DTUI-SC-W!
    DUP          _DREN-SC @ DTUI-SC-H!
    \ Stack: width height  (values now also stored in sidecar)

    2DROP
    \ Stack: empty

    \ --- Save ALL global state to return stack for recursion ---
    _DREN-SC @  >R
    _DREN-ND @  >R
    _DREN-FL @  >R
    _DREN-ROW @ >R
    _DREN-COL @ >R
    _DREN-LINE-H @ >R
    _DREN-VW @  >R
    _DREN-LMAR @ >R
    \ R: sc nd fl row col lh vw lm  (8 cells)

    \ --- Set content area for children ---
    _DREN-SC @ DTUI-SC-STYLE DTUI-UNPACK-BORDER IF
        _DREN-ROW @ 1+  _DREN-ROW !
        _DREN-COL @ 1+  _DREN-COL !
        _DREN-SC @ DTUI-SC-W 2 -  DUP 0< IF DROP 0 THEN  _DREN-VW !
    ELSE
        _DREN-SC @ DTUI-SC-W  _DREN-VW !
    THEN
    _DREN-COL @ _DREN-LMAR !
    1 _DREN-LINE-H !

    \ --- Recurse into children ---
    _DREN-ND @ _DREN-LAYOUT-CHILDREN-XT @ EXECUTE

    \ --- Restore global state ---
    R> _DREN-LMAR !
    R> _DREN-VW !
    R> _DREN-LINE-H !
    R> _DREN-COL !
    R> _DREN-ROW !
    R> _DREN-FL !
    R> _DREN-ND !
    R> _DREN-SC !

    \ --- Advance cursor past this node ---
    _DREN-FL @ DTUI-F-BLOCK AND IF
        _DREN-SC @ DTUI-SC-H  _DREN-ROW +!
    ELSE
        _DREN-SC @ DTUI-SC-W  _DREN-COL +!
        _DREN-SC @ DTUI-SC-H
        _DREN-LINE-H @ MAX  _DREN-LINE-H !
    THEN ;

\ _DREN-LAYOUT-CHILDREN ( parent -- )
\   Layout all element children of parent.
: _DREN-LAYOUT-CHILDREN  ( parent -- )
    DOM-FIRST-CHILD
    BEGIN DUP WHILE
        DUP DOM-TYPE@ DOM-T-ELEMENT = IF
            DUP _DREN-LAYOUT-NODE
        THEN
        DOM-NEXT
    REPEAT
    DROP ;

' _DREN-LAYOUT-CHILDREN _DREN-LAYOUT-CHILDREN-XT !

\ =====================================================================
\  §5 — Paint Engine
\ =====================================================================

VARIABLE _DREN-DOC

\ _DREN-APPLY-STYLE ( sc -- )
\   Set DRW-* style from sidecar's packed style word.
: _DREN-APPLY-STYLE  ( sc -- )
    DUP DTUI-SC-STYLE DTUI-UNPACK-ATTRS
    SWAP DUP DTUI-SC-STYLE DTUI-UNPACK-BG
    SWAP DTUI-SC-STYLE DTUI-UNPACK-FG
    \ Stack: attrs bg fg
    SWAP ROT  DRW-STYLE! ;

\ _DREN-PAINT-BG ( sc -- )
\   Fill the element's bounding box with background using space char.
: _DREN-PAINT-BG  ( sc -- )
    DUP _DREN-APPLY-STYLE
    >R
    32
    R@ DTUI-SC-ROW
    R@ DTUI-SC-COL
    R@ DTUI-SC-H
    R> DTUI-SC-W
    DRW-FILL-RECT ;

\ _DREN-PAINT-BORDER ( sc -- )
\   Draw a box border if the sidecar has one.
: _DREN-PAINT-BORDER  ( sc -- )
    DUP DTUI-SC-STYLE DTUI-UNPACK-BORDER
    DUP 0= IF 2DROP EXIT THEN
    _DREN-BOX-STYLE  DUP 0= IF 2DROP EXIT THEN
    \ Stack: sc box-style
    SWAP
    DUP _DREN-APPLY-STYLE
    DUP DTUI-SC-ROW  OVER DTUI-SC-COL
    ROT DUP DTUI-SC-H  SWAP DTUI-SC-W
    \ Stack: box-style row col h w
    BOX-DRAW ;

\ _DREN-PAINT-TEXT ( node sc -- )
\   Render text content of the element's text-node children.
: _DREN-PAINT-TEXT  ( node sc -- )
    DUP _DREN-APPLY-STYLE
    \ Compute text origin (inside border if present)
    DUP DTUI-SC-STYLE DTUI-UNPACK-BORDER 0<> IF 1 ELSE 0 THEN
    >R
    DUP DTUI-SC-ROW R@ +
    SWAP DTUI-SC-COL R> +
    \ Stack: node row col
    ROT _DREN-COLLECT-TEXT
    \ Stack: row col addr len
    2SWAP                   \ addr len row col
    DRW-TEXT ;

\ _DREN-PAINT-NODE ( node -- )
\   Paint one element node.  If the sidecar has a custom draw-xt,
\   call it as ( node sidecar region -- ) and skip default paint.
\   Otherwise: bg → border → text → recurse children.
\   Clears DTUI-F-DIRTY after painting.

VARIABLE _DREN-TMP-RGN    \ per-node scratch region

: _DREN-PAINT-NODE  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    DUP N.AUX @ DUP 0= IF 2DROP EXIT THEN
    \ Stack: node sc
    DUP DTUI-SC-FLAGS DTUI-F-VISIBLE AND 0= IF 2DROP EXIT THEN

    \ visibility:hidden — reserve space but don't paint
    DUP DTUI-SC-FLAGS DTUI-F-HIDDEN AND IF 2DROP EXIT THEN

    \ Clear dirty flag
    DUP DTUI-CLEAR-DIRTY

    \ Custom draw callback?
    DUP DTUI-SC-DRAW DUP IF
        \ Build a sub-region for this node
        >R  \ save draw-xt
        DUP DTUI-SC-ROW OVER DTUI-SC-COL
        2 PICK DTUI-SC-H  3 PICK DTUI-SC-W
        RGN-NEW _DREN-TMP-RGN !
        R>      \ restore draw-xt
        \ Stack: node sc draw-xt
        >R 2DUP R>
        _DREN-TMP-RGN @    \ ( node sc draw-xt rgn )
        SWAP EXECUTE        \ ( node sc rgn draw-xt -- ) calls draw-xt
        _DREN-TMP-RGN @ RGN-FREE
        2DROP               \ drop node sc
        EXIT
    THEN
    DROP    \ drop 0 from DTUI-SC-DRAW

    \ Paint background
    DUP _DREN-PAINT-BG

    \ Paint border
    DUP _DREN-PAINT-BORDER

    \ Paint text content
    2DUP _DREN-PAINT-TEXT

    \ Paint children
    DROP    \ drop sc, keep node
    DOM-FIRST-CHILD
    BEGIN DUP WHILE
        DUP _DREN-PAINT-NODE
        DOM-NEXT
    REPEAT
    DROP ;

\ =====================================================================
\  §6 — Public API
\ =====================================================================

\ DREN-LAYOUT ( doc rgn -- )
\   Compute character-cell layout for the entire DOM tree
\   within the given region.
: DREN-LAYOUT  ( doc rgn -- )
    _DREN-RGN !
    DUP DOM-USE
    DUP _DREN-DOC !

    \ Extract region dimensions
    _DREN-RGN @ RGN-W  _DREN-VW !
    _DREN-RGN @ RGN-H  _DREN-VH !

    \ Reset flow cursor
    0 _DREN-ROW !
    0 _DREN-COL !
    0 _DREN-LMAR !
    1 _DREN-LINE-H !

    \ Walk from BODY (skipping html/head)
    D.BODY @  DUP 0= IF DROP EXIT THEN

    \ Layout BODY itself if it has a sidecar, else just its children
    DUP N.AUX @ IF
        _DREN-LAYOUT-NODE
    ELSE
        _DREN-LAYOUT-CHILDREN
    THEN ;

\ DREN-PAINT ( doc -- )
\   Paint all laid-out nodes into the screen back buffer.
\   DREN-LAYOUT must have been called first (to set _DREN-RGN).
: DREN-PAINT  ( doc -- )
    DUP DOM-USE
    _DREN-DOC !

    \ Activate the region for clipping
    _DREN-RGN @ RGN-USE

    \ Reset drawing style
    DRW-STYLE-RESET

    \ Walk from BODY
    _DREN-DOC @ D.BODY @  DUP 0= IF DROP RGN-ROOT EXIT THEN
    _DREN-PAINT-NODE

    \ Unclip
    RGN-ROOT ;

\ DREN-PAINT-DIRTY ( doc -- )
\   Repaint only nodes with DTUI-F-DIRTY set.  Much cheaper than
\   a full DREN-PAINT when only a few nodes changed.
\   DREN-LAYOUT must have been called first (to set _DREN-RGN).

: _DREN-PAINT-DIRTY-WALK  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    DUP N.AUX @ DUP 0= IF 2DROP EXIT THEN
    \ Stack: node sc
    DTUI-SC-FLAGS DTUI-F-DIRTY AND IF
        \ Dirty — paint this node (which clears the flag)
        _DREN-PAINT-NODE
    ELSE
        \ Not dirty — still recurse children (a child may be dirty)
        DOM-FIRST-CHILD
        BEGIN DUP WHILE
            DUP _DREN-PAINT-DIRTY-WALK
            DOM-NEXT
        REPEAT
        DROP
    THEN ;

: DREN-PAINT-DIRTY  ( doc -- )
    DUP DOM-USE
    _DREN-DOC !

    _DREN-RGN @ RGN-USE
    DRW-STYLE-RESET

    _DREN-DOC @ D.BODY @  DUP 0= IF DROP RGN-ROOT EXIT THEN
    _DREN-PAINT-DIRTY-WALK

    RGN-ROOT ;

\ DREN-RENDER ( doc rgn -- )
\   Layout + paint in one call.
: DREN-RENDER  ( doc rgn -- )
    2DUP  DREN-LAYOUT
    DROP  DREN-PAINT ;

\ DREN-RELAYOUT ( doc rgn -- )
\   Re-layout only if any sidecar has DTUI-F-GEOM-DIRTY set.
\   If no geometry changed, returns immediately.  Otherwise does a
\   full DREN-LAYOUT and clears all GEOM-DIRTY flags.
VARIABLE _DRL-GEO

: _DREN-CHECK-GEOM-DIRTY  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    N.AUX @  DUP 0= IF DROP EXIT THEN
    DTUI-SC-FLAGS  DTUI-F-GEOM-DIRTY AND IF
        -1 _DRL-GEO !
    THEN ;

: _DREN-CLEAR-GEOM-DIRTY  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    N.AUX @  DUP 0= IF DROP EXIT THEN
    DTUI-CLEAR-GEOM-DIRTY ;

: DREN-RELAYOUT  ( doc rgn -- )
    OVER DOM-USE
    0 _DRL-GEO !
    OVER D.BODY @  DUP 0= IF DROP 2DROP EXIT THEN
    ['] _DREN-CHECK-GEOM-DIRTY DOM-WALK-DEPTH
    _DRL-GEO @ 0= IF 2DROP EXIT THEN  \ nothing changed — skip
    \ Geometry changed — full relayout
    2DUP DREN-LAYOUT
    \ Clear all geom-dirty flags
    DROP DUP DOM-USE
    D.BODY @  DUP 0= IF DROP EXIT THEN
    ['] _DREN-CLEAR-GEOM-DIRTY DOM-WALK-DEPTH ;

\ DREN-DIRTY? ( doc -- flag )
\   True if any sidecar has DTUI-F-DIRTY set.
VARIABLE _DRD-FLG

: _DREN-CHECK-DIRTY  ( node -- )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP EXIT THEN
    N.AUX @  DUP 0= IF DROP EXIT THEN
    DTUI-SC-FLAGS  DTUI-F-DIRTY AND IF
        -1 _DRD-FLG !
    THEN ;

: DREN-DIRTY?  ( doc -- flag )
    DUP DOM-USE
    0 _DRD-FLG !
    D.BODY @  DUP 0= IF DROP 0 EXIT THEN
    ['] _DREN-CHECK-DIRTY DOM-WALK-DEPTH
    _DRD-FLG @ ;

\ DREN-PAINT-NODE ( node -- )
\   Paint a single node (for partial updates).
\   Caller must have activated the region (RGN-USE) first.
: DREN-PAINT-NODE  ( node -- )
    _DREN-PAINT-NODE ;

\ =====================================================================
\  §7 — Guard Wrappers
\ =====================================================================

[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _dren-guard

' DREN-LAYOUT       CONSTANT _dren-layout-xt
' DREN-PAINT        CONSTANT _dren-paint-xt
' DREN-PAINT-DIRTY  CONSTANT _dren-paintdirty-xt
' DREN-RENDER       CONSTANT _dren-render-xt
' DREN-RELAYOUT     CONSTANT _dren-relayout-xt
' DREN-DIRTY?       CONSTANT _dren-dirty-xt
' DREN-PAINT-NODE   CONSTANT _dren-paintnode-xt

: DREN-LAYOUT       _dren-layout-xt     _dren-guard WITH-GUARD ;
: DREN-PAINT        _dren-paint-xt      _dren-guard WITH-GUARD ;
: DREN-PAINT-DIRTY  _dren-paintdirty-xt _dren-guard WITH-GUARD ;
: DREN-RENDER       _dren-render-xt     _dren-guard WITH-GUARD ;
: DREN-RELAYOUT     _dren-relayout-xt   _dren-guard WITH-GUARD ;
: DREN-DIRTY?       _dren-dirty-xt      _dren-guard WITH-GUARD ;
: DREN-PAINT-NODE   _dren-paintnode-xt  _dren-guard WITH-GUARD ;
[THEN] [THEN]
