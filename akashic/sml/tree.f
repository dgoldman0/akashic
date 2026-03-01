\ tree.f — SOM Tree: DOM + 1D extensions for KDOS / Megapad-64
\
\ Layers the Sequential Object Model on top of the arena-backed DOM.
\ Reuses DOM node descriptors (80 bytes each) and adds document-level
\ SOM state:  Cursor, FocusStack, InputContext.
\
\ SML element type is stored in the DOM flags field (bits 8–12).
\ CueMap and LaneTable are deferred to sml/style.f.
\
\ Prefix: SML-   (tree API)
\         SOM-   (cursor / focus / input context API)
\         _SML-  (internal helpers)
\         _SOM-  (internal helpers)
\
\ Load with:   REQUIRE tree.f

REQUIRE core.f
REQUIRE ../dom/dom.f

PROVIDED akashic-sml-tree

\ =====================================================================
\  Constants
\ =====================================================================

\ SML type stored in N.FLAGS bits 8–12  (5 bits → 0..31)
8  CONSTANT _SML-TYPE-SHIFT
31 CONSTANT _SML-TYPE-MASK          \ 5-bit mask (0x1F)

\ Input context states (SOM §5)
0 CONSTANT SOM-CTX-NAV
1 CONSTANT SOM-CTX-TEXT
2 CONSTANT SOM-CTX-SLIDER
3 CONSTANT SOM-CTX-CYCLING
4 CONSTANT SOM-CTX-MENU
5 CONSTANT SOM-CTX-TRAPPED

\ Focus stack capacity
16 CONSTANT _SOM-FS-MAX             \ max scope depth

\ =====================================================================
\  SOM Extension Block Layout
\ =====================================================================
\
\ Allocated alongside the DOM document.  Stored in a global variable
\ (one active SOM tree at a time, like DOM-DOC).
\
\ Cursor (4 cells = 32 bytes):
\   +0   current    node address (0 = none)
\   +8   scope      scope node address
\  +16   position   zero-based index in scope
\  +24   at-bound   0=none, 1=first, 2=last
\
\ FocusStack (3 cells per frame × 16 frames + 1 depth cell):
\   +32   fs-depth      current depth
\   +40   fs-frames     16 × (scope, savedPos, resumePolicy) = 16×24 = 384 bytes
\   Frame layout (24 bytes per frame):
\     +0  scope          scope node address
\     +8  saved-pos      last cursor position before exit (-1 = none)
\    +16  resume-policy  0=first, 1=last, 2=none
\
\ InputContext (3 cells = 24 bytes):
\   +424  ctx-state   SOM-CTX-* constant
\   +432  ctx-target  element node address (0 = none)
\   +440  ctx-value   edit value (cell)
\
\ Total: 448 bytes

448 CONSTANT _SOM-EXT-SIZE

\ Field offsets within the SOM extension block
: SX.CURRENT     ;              \ +0
: SX.SCOPE       8 + ;         \ +8
: SX.POSITION    16 + ;        \ +16
: SX.AT-BOUND    24 + ;        \ +24
: SX.FS-DEPTH    32 + ;        \ +32
: SX.FS-FRAMES   40 + ;        \ +40  (384 bytes)
: SX.CTX-STATE   424 + ;       \ +424
: SX.CTX-TARGET  432 + ;       \ +432
: SX.CTX-VALUE   440 + ;       \ +440

\ Frame size and accessors (relative to frame base)
24 CONSTANT _SOM-FRAME-SIZE
: SF.SCOPE       ;              \ +0 in frame
: SF.SAVED-POS   8 + ;         \ +8
: SF.RESUME      16 + ;        \ +16

\ Resume policy constants
0 CONSTANT SOM-RESUME-FIRST
1 CONSTANT SOM-RESUME-LAST
2 CONSTANT SOM-RESUME-NONE

\ Boundary constants
0 CONSTANT SOM-BOUND-NONE
1 CONSTANT SOM-BOUND-FIRST
2 CONSTANT SOM-BOUND-LAST

\ =====================================================================
\  SOM Tree Handle
\ =====================================================================
\
\ A "tree" is a pair: ( DOM-doc-addr , SOM-ext-addr ).
\ We store both in a 2-cell structure (16 bytes) allocated from
\ the same arena.
\
\ Tree layout (16 bytes):
\   +0   doc    DOM document descriptor address
\   +8   ext    SOM extension block address

: T.DOC    ;            \ +0
: T.EXT    8 + ;        \ +8

VARIABLE _SML-CUR-TREE              \ current SOM tree handle

: SML-TREE-USE   ( tree -- )   _SML-CUR-TREE ! ;
: SML-TREE       ( -- tree )   _SML-CUR-TREE @ ;
: _SOM-EXT       ( -- ext )    SML-TREE T.EXT @ ;

\ =====================================================================
\  SML Type Encoding in DOM Flags
\ =====================================================================

\ _SML-SET-TYPE ( sml-type node -- )
\   Store SML element type in bits 8–12 of node's flags field.
: _SML-SET-TYPE  ( sml-type node -- )
    DUP N.FLAGS @                        \ ( type node flags )
    _SML-TYPE-MASK _SML-TYPE-SHIFT LSHIFT INVERT AND  \ clear bits 8-12
    ROT _SML-TYPE-SHIFT LSHIFT OR        \ OR in new type
    SWAP N.FLAGS ! ;

\ SML-NODE-TYPE@ ( node -- sml-type )
\   Read the SML element type from flags bits 8–12.
: SML-NODE-TYPE@  ( node -- sml-type )
    N.FLAGS @  _SML-TYPE-SHIFT RSHIFT  _SML-TYPE-MASK AND ;

\ =====================================================================
\  Tree Creation / Destruction
\ =====================================================================

VARIABLE _STC-AR     \ arena handle
VARIABLE _STC-TR     \ tree handle

: SML-TREE-CREATE  ( -- tree )
    \ Create arena: 256KB in extended memory
    262144 A-XMEM ARENA-NEW DROP  _STC-AR !
    \ Allocate tree handle (16 bytes) from arena
    _STC-AR @  16 ARENA-ALLOT  _STC-TR !
    \ Allocate SOM extension block BEFORE DOM-DOC-NEW
    \ (DOM-DOC-NEW claims all remaining space for string pool)
    _STC-AR @  _SOM-EXT-SIZE ARENA-ALLOT
    DUP _SOM-EXT-SIZE 0 FILL           \ zero the block
    _STC-TR @ T.EXT !
    \ Create DOM document: 256 nodes, 512 attrs
    _STC-AR @  256  512  DOM-DOC-NEW
    _STC-TR @ T.DOC !
    \ Initialize focus stack depth = 0, context = NAV
    _STC-TR @ T.EXT @  SX.FS-DEPTH  0 SWAP !
    _STC-TR @ T.EXT @  SX.CTX-STATE  SOM-CTX-NAV SWAP !
    \ Set as current tree
    _STC-TR @  SML-TREE-USE
    \ Also set DOM-USE so DOM words work
    _STC-TR @ T.DOC @  DOM-USE
    _STC-TR @ ;

: SML-TREE-DESTROY  ( tree -- )
    T.DOC @ D.ARENA @  ARENA-DESTROY ;

\ =====================================================================
\  Helpers: Navigate to DOM doc from tree
\ =====================================================================

\ _SML-USE-DOC ( -- )
\   Ensure DOM-DOC is set to the current tree's DOM doc.
: _SML-USE-DOC  ( -- )
    SML-TREE T.DOC @  DOM-USE ;

\ =====================================================================
\  SML-LOAD — Parse SML markup string into tree
\ =====================================================================
\
\ Parses an SML string using the DOM HTML parser, then walks the
\ resulting tree tagging each element node with its SML type.

VARIABLE _SLO-CUR
VARIABLE _SLO-ROOT

\ =====================================================================
\  DFS Upward-Walk Helper
\ =====================================================================
\
\ Factored out so that EXIT returns to the caller of _DFS-UP,
\ not the outermost DFS word.  Shared by all DFS traversals.

VARIABLE _DFS-UCUR
VARIABLE _DFS-UROOT

\ _DFS-UP ( cur root -- next|0 )
\   Walk parent chain from cur until a sibling is found.
\   Return the sibling node, or 0 if we reach root.
: _DFS-UP  ( cur root -- next|0 )
    _DFS-UROOT !  _DFS-UCUR !
    BEGIN
        _DFS-UCUR @ _DFS-UROOT @ = IF 0 EXIT THEN
        _DFS-UCUR @ DOM-NEXT ?DUP IF EXIT THEN
        _DFS-UCUR @ DOM-PARENT _DFS-UCUR !
    AGAIN ;

\ _SML-TAG-WALK ( root -- )
\   DFS walk: for each element node, classify tag name → SML type,
\   store in flags.
: _SML-TAG-WALK  ( root -- )
    DUP _SLO-ROOT !  _SLO-CUR !
    BEGIN
        _SLO-CUR @ DOM-TYPE@ DOM-T-ELEMENT = IF
            _SLO-CUR @ DOM-TAG-NAME SML-TYPE?
            _SLO-CUR @ _SML-SET-TYPE
        THEN
        _SLO-CUR @ DOM-FIRST-CHILD ?DUP IF
            _SLO-CUR !
        ELSE
            _SLO-CUR @ _SLO-ROOT @ _DFS-UP  DUP _SLO-CUR !
        THEN
        _SLO-CUR @ 0=
    UNTIL ;

: SML-LOAD  ( a u tree -- )
    SML-TREE-USE
    _SML-USE-DOC
    \ Parse SML markup using DOM HTML parser
    DOM-PARSE-HTML
    \ Tag all element nodes with SML types
    _SML-TAG-WALK ;

\ =====================================================================
\  Node Query Helpers
\ =====================================================================

\ SML-NODE@ ( node tree -- addr )
\   Get node descriptor address.  Node IS the address in this impl.
: SML-NODE@  ( node tree -- addr )
    DROP ;

\ =====================================================================
\  Navigability Predicates (operating on DOM nodes)
\ =====================================================================

\ _SML-NODE-HIDDEN? ( node -- flag )
\   True if node has hidden="true" attribute.
VARIABLE _SNH-A  VARIABLE _SNH-L

: _SML-NODE-HIDDEN?  ( node -- flag )
    S" hidden" DOM-ATTR@
    IF
        \ Check if value is "true"
        _SNH-L ! _SNH-A !
        _SNH-A @ _SNH-L @  S" true" STR-STR=
    ELSE
        2DROP 0
    THEN ;

\ _SML-NODE-NAVIGABLE? ( node -- flag )
\   True if node is a navigable position element and not hidden.
: _SML-NODE-NAVIGABLE?  ( node -- flag )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP 0 EXIT THEN
    DUP _SML-NODE-HIDDEN? IF DROP 0 EXIT THEN
    SML-NODE-TYPE@ SML-POSITION? ;

\ _SML-NODE-SCOPE? ( node -- flag )
\   True if node is a scope element (seq, ring, gate, trap).
: _SML-NODE-SCOPE?  ( node -- flag )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP 0 EXIT THEN
    SML-NODE-TYPE@ SML-SCOPE? ;

\ _SML-NODE-ENTERABLE? ( node -- flag )
\   True if node is a scope element and not hidden.
: _SML-NODE-ENTERABLE?  ( node -- flag )
    DUP DOM-TYPE@ DOM-T-ELEMENT <> IF DROP 0 EXIT THEN
    DUP _SML-NODE-HIDDEN? IF DROP 0 EXIT THEN
    SML-NODE-TYPE@ SML-SCOPE? ;

\ =====================================================================
\  Tree Navigation — DFS Navigable Traversal
\ =====================================================================
\
\ These scan the DOM tree in depth-first order but only land on
\ position-type elements (items that the cursor can rest on).

VARIABLE _SNF-CUR
VARIABLE _SNF-ROOT

\ SML-FIRST ( tree -- node|0 )
\   First navigable (position) node in the tree, DFS order.
: SML-FIRST  ( tree -- node|0 )
    SML-TREE-USE  _SML-USE-DOC
    DOM-DOC  D.NODE-BASE @   \ root = first node (fragment root)
    DUP _SNF-ROOT !  _SNF-CUR !
    BEGIN
        _SNF-CUR @ _SML-NODE-NAVIGABLE? IF
            _SNF-CUR @ EXIT
        THEN
        _SNF-CUR @ DOM-FIRST-CHILD ?DUP IF
            _SNF-CUR !
        ELSE
            _SNF-CUR @ _SNF-ROOT @ _DFS-UP  DUP _SNF-CUR !
        THEN
        _SNF-CUR @ 0=
    UNTIL
    0 ;

\ SML-LAST ( tree -- node|0 )
\   Last navigable node in DFS order.
VARIABLE _SNL-CUR
VARIABLE _SNL-ROOT
VARIABLE _SNL-LAST

: SML-LAST  ( tree -- node|0 )
    SML-TREE-USE  _SML-USE-DOC
    DOM-DOC  D.NODE-BASE @
    DUP _SNL-ROOT !  _SNL-CUR !  0 _SNL-LAST !
    BEGIN
        _SNL-CUR @ _SML-NODE-NAVIGABLE? IF
            _SNL-CUR @  _SNL-LAST !
        THEN
        _SNL-CUR @ DOM-FIRST-CHILD ?DUP IF
            _SNL-CUR !
        ELSE
            _SNL-CUR @ _SNL-ROOT @ _DFS-UP  DUP _SNL-CUR !
        THEN
        _SNL-CUR @ 0=
    UNTIL
    _SNL-LAST @ ;

\ SML-NEXT ( node tree -- node'|0 )
\   Next navigable node in DFS order after given node.
VARIABLE _SNN-CUR
VARIABLE _SNN-ROOT

: SML-NEXT  ( node tree -- node'|0 )
    SML-TREE-USE  _SML-USE-DOC
    DOM-DOC  D.NODE-BASE @  _SNN-ROOT !
    _SNN-CUR !
    \ Advance past the given node: try first-child, then up-walk
    _SNN-CUR @ DOM-FIRST-CHILD ?DUP IF
        _SNN-CUR !
    ELSE
        _SNN-CUR @ _SNN-ROOT @ _DFS-UP  DUP _SNN-CUR !
        0= IF 0 EXIT THEN
    THEN
    \ DFS from _SNN-CUR to find next navigable
    BEGIN
        _SNN-CUR @ _SML-NODE-NAVIGABLE? IF
            _SNN-CUR @ EXIT
        THEN
        _SNN-CUR @ DOM-FIRST-CHILD ?DUP IF
            _SNN-CUR !
        ELSE
            _SNN-CUR @ _SNN-ROOT @ _DFS-UP  DUP _SNN-CUR !
        THEN
        _SNN-CUR @ 0=
    UNTIL
    0 ;

\ SML-PREV ( node tree -- node'|0 )
\   Previous navigable node in DFS order before given node.
\   Strategy: DFS from root, remember last navigable before target.
VARIABLE _SNP-CUR
VARIABLE _SNP-ROOT
VARIABLE _SNP-TARGET
VARIABLE _SNP-LAST

: SML-PREV  ( node tree -- node'|0 )
    SML-TREE-USE  _SML-USE-DOC
    _SNP-TARGET !
    DOM-DOC  D.NODE-BASE @
    DUP _SNP-ROOT !  _SNP-CUR !  0 _SNP-LAST !
    BEGIN
        _SNP-CUR @ _SNP-TARGET @ = IF
            _SNP-LAST @ EXIT
        THEN
        _SNP-CUR @ _SML-NODE-NAVIGABLE? IF
            _SNP-CUR @ _SNP-LAST !
        THEN
        _SNP-CUR @ DOM-FIRST-CHILD ?DUP IF
            _SNP-CUR !
        ELSE
            _SNP-CUR @ _SNP-ROOT @ _DFS-UP  DUP _SNP-CUR !
        THEN
        _SNP-CUR @ 0=
    UNTIL
    0 ;

\ SML-JUMP? ( node tree -- flag )
\   True if node is a scope with jump="true" attribute.
: SML-JUMP?  ( node tree -- flag )
    DROP
    DUP _SML-NODE-SCOPE? 0= IF DROP 0 EXIT THEN
    S" jump" DOM-ATTR@
    IF S" true" STR-STR=
    ELSE 2DROP 0
    THEN ;

\ SML-CHILDREN ( scope tree -- n )
\   Count navigable children of a scope element.
VARIABLE _SCH-N
VARIABLE _SCH-CUR

: SML-CHILDREN  ( scope tree -- n )
    DROP
    0 _SCH-N !
    DOM-FIRST-CHILD _SCH-CUR !
    BEGIN _SCH-CUR @ WHILE
        _SCH-CUR @ _SML-NODE-NAVIGABLE? IF
            1 _SCH-N +!
        THEN
        _SCH-CUR @ _SML-NODE-ENTERABLE? IF
            \ Scopes count as one navigable entry point
            1 _SCH-N +!
        THEN
        _SCH-CUR @ DOM-NEXT  _SCH-CUR !
    REPEAT
    _SCH-N @ ;

\ =====================================================================
\  SML-NODE-ADD — Add a node to the tree
\ =====================================================================

VARIABLE _SNA-PAR
VARIABLE _SNA-KIND
VARIABLE _SNA-LA
VARIABLE _SNA-LL

\ SML-NODE-ADD ( parent kind label-a label-u -- node )
\   Create an element node with the given SML element name and
\   optional label, append to parent.
: SML-NODE-ADD  ( parent kind-a kind-u label-a label-u -- node )
    _SNA-LL !  _SNA-LA !
    _SML-USE-DOC
    \ Create DOM element with kind as tag name
    DOM-CREATE-ELEMENT
    \ Tag with SML type
    2DUP DOM-TAG-NAME SML-TYPE? SWAP _SML-SET-TYPE DROP
    \ Set label attribute if non-empty
    _SNA-LL @ 0> IF
        DUP S" label" _SNA-LA @ _SNA-LL @ DOM-ATTR!
    THEN
    \ Append to parent
    DUP ROT DOM-APPEND ;

\ SML-NODE-REMOVE ( node tree -- )
\   Remove node and its subtree from the tree.
: SML-NODE-REMOVE  ( node tree -- )
    SML-TREE-USE  _SML-USE-DOC
    DOM-REMOVE ;

\ =====================================================================
\  Scope-local Navigation Helpers
\ =====================================================================
\
\ These find navigable children within a given scope element,
\ staying within the direct children only (not deep DFS).

\ _SOM-SCOPE-FIRST ( scope -- node|0 )
\   First navigable or enterable direct child of scope.
VARIABLE _SSF-CUR

: _SOM-SCOPE-FIRST  ( scope -- node|0 )
    DOM-FIRST-CHILD  _SSF-CUR !
    BEGIN _SSF-CUR @ WHILE
        _SSF-CUR @ _SML-NODE-NAVIGABLE? IF _SSF-CUR @ EXIT THEN
        _SSF-CUR @ _SML-NODE-ENTERABLE? IF _SSF-CUR @ EXIT THEN
        _SSF-CUR @ DOM-NEXT  _SSF-CUR !
    REPEAT
    0 ;

\ _SOM-SCOPE-LAST ( scope -- node|0 )
\   Last navigable or enterable direct child of scope.
VARIABLE _SSL-CUR
VARIABLE _SSL-LAST

: _SOM-SCOPE-LAST  ( scope -- node|0 )
    DOM-LAST-CHILD  _SSL-CUR !
    0 _SSL-LAST !
    \ Walk backward from last child
    BEGIN _SSL-CUR @ WHILE
        _SSL-CUR @ _SML-NODE-NAVIGABLE?
        _SSL-CUR @ _SML-NODE-ENTERABLE? OR IF
            _SSL-CUR @ EXIT
        THEN
        _SSL-CUR @ DOM-PREV  _SSL-CUR !
    REPEAT
    0 ;

\ _SOM-SCOPE-NEXT ( node scope -- node'|0 )
\   Next navigable/enterable sibling after node within scope's children.
VARIABLE _SSNN-CUR

: _SOM-SCOPE-NEXT  ( node scope -- node'|0 )
    DROP
    DOM-NEXT  _SSNN-CUR !
    BEGIN _SSNN-CUR @ WHILE
        _SSNN-CUR @ _SML-NODE-NAVIGABLE? IF _SSNN-CUR @ EXIT THEN
        _SSNN-CUR @ _SML-NODE-ENTERABLE? IF _SSNN-CUR @ EXIT THEN
        _SSNN-CUR @ DOM-NEXT  _SSNN-CUR !
    REPEAT
    0 ;

\ _SOM-SCOPE-PREV ( node scope -- node'|0 )
\   Previous navigable/enterable sibling before node.
VARIABLE _SSPN-CUR

: _SOM-SCOPE-PREV  ( node scope -- node'|0 )
    DROP
    DOM-PREV  _SSPN-CUR !
    BEGIN _SSPN-CUR @ WHILE
        _SSPN-CUR @ _SML-NODE-NAVIGABLE? IF _SSPN-CUR @ EXIT THEN
        _SSPN-CUR @ _SML-NODE-ENTERABLE? IF _SSPN-CUR @ EXIT THEN
        _SSPN-CUR @ DOM-PREV  _SSPN-CUR !
    REPEAT
    0 ;

\ _SOM-SCOPE-INDEX ( node scope -- n )
\   Zero-based index of node among navigable/enterable children.
VARIABLE _SSI-CUR
VARIABLE _SSI-N
VARIABLE _SSI-TARGET

: _SOM-SCOPE-INDEX  ( node scope -- n )
    DOM-FIRST-CHILD  _SSI-CUR !
    SWAP _SSI-TARGET !
    0 _SSI-N !
    BEGIN _SSI-CUR @ WHILE
        _SSI-CUR @ _SSI-TARGET @ = IF _SSI-N @ EXIT THEN
        _SSI-CUR @ _SML-NODE-NAVIGABLE?
        _SSI-CUR @ _SML-NODE-ENTERABLE? OR IF
            1 _SSI-N +!
        THEN
        _SSI-CUR @ DOM-NEXT  _SSI-CUR !
    REPEAT
    _SSI-N @ ;

\ _SOM-SCOPE-NTH ( n scope -- node|0 )
\   Return the nth navigable/enterable child (0-based).
VARIABLE _SSNT-CUR
VARIABLE _SSNT-I

: _SOM-SCOPE-NTH  ( n scope -- node|0 )
    DOM-FIRST-CHILD  _SSNT-CUR !
    _SSNT-I !
    BEGIN _SSNT-CUR @ WHILE
        _SSNT-CUR @ _SML-NODE-NAVIGABLE?
        _SSNT-CUR @ _SML-NODE-ENTERABLE? OR IF
            _SSNT-I @ 0= IF _SSNT-CUR @ EXIT THEN
            _SSNT-I @ 1-  _SSNT-I !
        THEN
        _SSNT-CUR @ DOM-NEXT  _SSNT-CUR !
    REPEAT
    0 ;

\ _SOM-SCOPE-COUNT ( scope -- n )
\   Count navigable/enterable direct children.
VARIABLE _SSC-CUR
VARIABLE _SSC-N

: _SOM-SCOPE-COUNT  ( scope -- n )
    DOM-FIRST-CHILD  _SSC-CUR !
    0 _SSC-N !
    BEGIN _SSC-CUR @ WHILE
        _SSC-CUR @ _SML-NODE-NAVIGABLE?
        _SSC-CUR @ _SML-NODE-ENTERABLE? OR IF
            1 _SSC-N +!
        THEN
        _SSC-CUR @ DOM-NEXT  _SSC-CUR !
    REPEAT
    _SSC-N @ ;

\ =====================================================================
\  Containing Scope Lookup
\ =====================================================================

\ _SOM-CONTAINING-SCOPE ( node -- scope|0 )
\   Walk up parent chain to find nearest scope ancestor.
VARIABLE _SCS-CUR

: _SOM-CONTAINING-SCOPE  ( node -- scope|0 )
    DOM-PARENT  _SCS-CUR !
    BEGIN _SCS-CUR @ WHILE
        _SCS-CUR @ _SML-NODE-SCOPE? IF _SCS-CUR @ EXIT THEN
        _SCS-CUR @ DOM-PARENT  _SCS-CUR !
    REPEAT
    0 ;

\ =====================================================================
\  Scope Kind Queries (on node directly)
\ =====================================================================

\ _SOM-SCOPE-RING? ( scope -- flag )
\   True if scope is a <ring> element.
: _SOM-SCOPE-RING?  ( scope -- flag )
    DOM-TAG-NAME S" ring" STR-STR= ;

\ _SOM-SCOPE-TRAP? ( scope -- flag )
\   True if scope is a <trap> element.
: _SOM-SCOPE-TRAP?  ( scope -- flag )
    DOM-TAG-NAME S" trap" STR-STR= ;

\ _SOM-SCOPE-SEQ? ( scope -- flag )
\   True if scope is a <seq> element.
: _SOM-SCOPE-SEQ?  ( scope -- flag )
    DOM-TAG-NAME S" seq" STR-STR= ;

\ _SOM-SCOPE-GATE? ( scope -- flag )
\   True if scope is a <gate> element.
: _SOM-SCOPE-GATE?  ( scope -- flag )
    DOM-TAG-NAME S" gate" STR-STR= ;

\ =====================================================================
\  Focus Stack Operations (SOM §4)
\ =====================================================================

\ _SOM-FS-FRAME ( index -- addr )
\   Return address of focus stack frame at given index.
: _SOM-FS-FRAME  ( index -- addr )
    _SOM-FRAME-SIZE *  _SOM-EXT SX.FS-FRAMES + ;

\ SOM-FS-DEPTH ( tree -- n )
: SOM-FS-DEPTH  ( tree -- n )
    DROP  _SOM-EXT SX.FS-DEPTH @ ;

\ _SOM-FS-PUSH ( scope saved-pos resume -- )
\   Push a new frame onto the focus stack.
VARIABLE _SFP-S
VARIABLE _SFP-P
VARIABLE _SFP-R

: _SOM-FS-PUSH  ( scope saved-pos resume -- )
    _SFP-R !  _SFP-P !  _SFP-S !
    _SOM-EXT SX.FS-DEPTH @  _SOM-FS-MAX >= IF EXIT THEN  \ stack full
    _SOM-EXT SX.FS-DEPTH @  _SOM-FS-FRAME
    _SFP-S @ OVER SF.SCOPE !
    _SFP-P @ OVER SF.SAVED-POS !
    _SFP-R @ SWAP SF.RESUME !
    _SOM-EXT SX.FS-DEPTH  DUP @ 1+ SWAP ! ;

\ _SOM-FS-POP ( -- scope saved-pos resume )
\   Pop the top frame.  Returns 0 0 0 if empty.
: _SOM-FS-POP  ( -- scope saved-pos resume )
    _SOM-EXT SX.FS-DEPTH @ 0= IF 0 0 0 EXIT THEN
    _SOM-EXT SX.FS-DEPTH  DUP @ 1- SWAP !
    _SOM-EXT SX.FS-DEPTH @  _SOM-FS-FRAME
    DUP SF.SCOPE @  OVER SF.SAVED-POS @  ROT SF.RESUME @ ;

\ _SOM-FS-PEEK ( -- scope saved-pos resume )
\   Read top frame without popping.
: _SOM-FS-PEEK  ( -- scope saved-pos resume )
    _SOM-EXT SX.FS-DEPTH @ 0= IF 0 0 0 EXIT THEN
    _SOM-EXT SX.FS-DEPTH @ 1-  _SOM-FS-FRAME
    DUP SF.SCOPE @  OVER SF.SAVED-POS @  ROT SF.RESUME @ ;

\ _SOM-FS-UPDATE-POS ( new-pos -- )
\   Update the saved position in the top frame.
: _SOM-FS-UPDATE-POS  ( new-pos -- )
    _SOM-EXT SX.FS-DEPTH @ 0= IF DROP EXIT THEN
    _SOM-EXT SX.FS-DEPTH @ 1-  _SOM-FS-FRAME
    SF.SAVED-POS ! ;

\ =====================================================================
\  Cursor Read API (SOM §3)
\ =====================================================================

\ SOM-CURRENT ( tree -- node|0 )
: SOM-CURRENT  ( tree -- node|0 )
    DROP  _SOM-EXT SX.CURRENT @ ;

\ SOM-SCOPE ( tree -- scope|0 )
: SOM-SCOPE  ( tree -- scope|0 )
    DROP  _SOM-EXT SX.SCOPE @ ;

\ SOM-POSITION ( tree -- n )
: SOM-POSITION  ( tree -- n )
    DROP  _SOM-EXT SX.POSITION @ ;

\ SOM-AT-BOUNDARY ( tree -- bound )
\   0=none, 1=first, 2=last
: SOM-AT-BOUNDARY  ( tree -- bound )
    DROP  _SOM-EXT SX.AT-BOUND @ ;

\ =====================================================================
\  Cursor Internal Helpers
\ =====================================================================

\ _SOM-SET-CURSOR ( node scope -- )
\   Set cursor to node within scope, update position and boundary.
VARIABLE _SSC-NODE
VARIABLE _SSC-SSCOPE

: _SOM-SET-CURSOR  ( node scope -- )
    _SSC-SSCOPE !  _SSC-NODE !
    _SSC-NODE @  _SOM-EXT SX.CURRENT !
    _SSC-SSCOPE @  _SOM-EXT SX.SCOPE !
    \ Compute position index
    _SSC-NODE @ _SSC-SSCOPE @  _SOM-SCOPE-INDEX
    _SOM-EXT SX.POSITION !
    \ Compute boundary
    _SSC-SSCOPE @ _SOM-SCOPE-FIRST _SSC-NODE @ = IF
        _SSC-SSCOPE @ _SOM-SCOPE-LAST _SSC-NODE @ = IF
            \ Only one element: both first and last
            SOM-BOUND-FIRST _SOM-EXT SX.AT-BOUND !
        ELSE
            SOM-BOUND-FIRST _SOM-EXT SX.AT-BOUND !
        THEN
    ELSE
        _SSC-SSCOPE @ _SOM-SCOPE-LAST _SSC-NODE @ = IF
            SOM-BOUND-LAST _SOM-EXT SX.AT-BOUND !
        ELSE
            SOM-BOUND-NONE _SOM-EXT SX.AT-BOUND !
        THEN
    THEN ;

\ _SOM-INIT-CURSOR ( tree -- )
\   Initialize cursor to first navigable node in root scope.
\   Finds the root scope (first <seq>/<ring> under document root).
VARIABLE _SIC-ROOT

: _SOM-INIT-CURSOR  ( tree -- )
    SML-TREE-USE  _SML-USE-DOC
    \ Find root scope: walk children of the DOM document root
    DOM-DOC  D.NODE-BASE @
    DOM-FIRST-CHILD  _SIC-ROOT !
    \ The parse root is a fragment; find <sml> under it
    BEGIN _SIC-ROOT @ WHILE
        _SIC-ROOT @ DOM-TYPE@ DOM-T-ELEMENT = IF
            _SIC-ROOT @ DOM-TAG-NAME S" sml" STR-STR= IF
                \ Found <sml> — look for first scope child
                _SIC-ROOT @ DOM-FIRST-CHILD  _SIC-ROOT !
                BEGIN _SIC-ROOT @ WHILE
                    _SIC-ROOT @ _SML-NODE-SCOPE? IF
                        \ Found root scope — push onto focus stack
                        _SIC-ROOT @ -1 SOM-RESUME-LAST _SOM-FS-PUSH
                        \ Set cursor to first navigable child
                        _SIC-ROOT @ _SOM-SCOPE-FIRST
                        DUP IF
                            _SIC-ROOT @ _SOM-SET-CURSOR
                        ELSE
                            DROP
                            0 _SOM-EXT SX.CURRENT !
                            _SIC-ROOT @ _SOM-EXT SX.SCOPE !
                        THEN
                        EXIT
                    THEN
                    _SIC-ROOT @ DOM-NEXT  _SIC-ROOT !
                REPEAT
                EXIT
            THEN
        THEN
        _SIC-ROOT @ DOM-NEXT  _SIC-ROOT !
    REPEAT ;

\ =====================================================================
\  Cursor Movement — SOM-NEXT (SOM §3.2)
\ =====================================================================

\ SOM-NEXT ( tree -- moved? )
\   Move cursor to next navigable sibling in current scope.
\   At last child: wrap (ring), bump boundary (seq), block (trap).
VARIABLE _SMN-SC
VARIABLE _SMN-NXT

: SOM-NEXT  ( tree -- moved? )
    SML-TREE-USE
    _SOM-EXT SX.SCOPE @  _SMN-SC !
    _SOM-EXT SX.CURRENT @ 0= IF 0 EXIT THEN
    \ Try to find next navigable sibling
    _SOM-EXT SX.CURRENT @  _SMN-SC @ _SOM-SCOPE-NEXT
    _SMN-NXT !
    _SMN-NXT @ IF
        \ Found next — move there
        _SMN-NXT @ _SMN-SC @ _SOM-SET-CURSOR  -1 EXIT
    THEN
    \ At boundary — behaviour depends on scope kind
    _SMN-SC @ _SOM-SCOPE-RING? IF
        \ Ring: wrap to first
        _SMN-SC @ _SOM-SCOPE-FIRST
        DUP IF
            _SMN-SC @ _SOM-SET-CURSOR -1 EXIT
        THEN
        DROP 0 EXIT
    THEN
    \ Seq / gate / trap: stay at boundary
    SOM-BOUND-LAST _SOM-EXT SX.AT-BOUND !
    0 ;

\ =====================================================================
\  Cursor Movement — SOM-PREV (SOM §3.2)
\ =====================================================================

VARIABLE _SMP-SC
VARIABLE _SMP-PRV

: SOM-PREV  ( tree -- moved? )
    SML-TREE-USE
    _SOM-EXT SX.SCOPE @  _SMP-SC !
    _SOM-EXT SX.CURRENT @ 0= IF 0 EXIT THEN
    _SOM-EXT SX.CURRENT @  _SMP-SC @ _SOM-SCOPE-PREV
    _SMP-PRV !
    _SMP-PRV @ IF
        _SMP-PRV @ _SMP-SC @ _SOM-SET-CURSOR  -1 EXIT
    THEN
    \ At first boundary
    _SMP-SC @ _SOM-SCOPE-RING? IF
        _SMP-SC @ _SOM-SCOPE-LAST
        DUP IF
            _SMP-SC @ _SOM-SET-CURSOR -1 EXIT
        THEN
        DROP 0 EXIT
    THEN
    SOM-BOUND-FIRST _SOM-EXT SX.AT-BOUND !
    0 ;

\ =====================================================================
\  Cursor Movement — SOM-ENTER (SOM §3.2)
\ =====================================================================

\ SOM-ENTER ( tree -- moved? )
\   If current node is a scope element, enter it.
\   Cursor moves to first navigable child (or resume position).
VARIABLE _SME-SC
VARIABLE _SME-CHILD

: SOM-ENTER  ( tree -- moved? )
    SML-TREE-USE
    _SOM-EXT SX.CURRENT @ 0= IF 0 EXIT THEN
    _SOM-EXT SX.CURRENT @  _SML-NODE-ENTERABLE? 0= IF 0 EXIT THEN
    _SOM-EXT SX.CURRENT @  _SME-SC !
    \ Save current position in parent frame before entering
    _SOM-EXT SX.POSITION @  _SOM-FS-UPDATE-POS
    \ Determine resume policy from element's resume attribute
    _SME-SC @ S" resume" DOM-ATTR@
    IF
        2DUP S" first" STR-STR= IF
            2DROP SOM-RESUME-FIRST
        ELSE 2DUP S" none" STR-STR= IF
            2DROP SOM-RESUME-NONE
        ELSE
            2DROP SOM-RESUME-LAST
        THEN THEN
    ELSE
        2DROP SOM-RESUME-LAST          \ default: resume last
    THEN
    \ Push new scope frame
    _SME-SC @ -1 ROT _SOM-FS-PUSH
    \ Find first navigable child
    _SME-SC @ _SOM-SCOPE-FIRST  _SME-CHILD !
    _SME-CHILD @ IF
        _SME-CHILD @ _SME-SC @ _SOM-SET-CURSOR
        \ Input context: ring → MENU, trap → TRAPPED
        _SME-SC @ _SOM-SCOPE-RING? IF
            SOM-CTX-MENU _SOM-EXT SX.CTX-STATE !
            _SME-SC @  _SOM-EXT SX.CTX-TARGET !
        THEN
        _SME-SC @ _SOM-SCOPE-TRAP? IF
            SOM-CTX-TRAPPED _SOM-EXT SX.CTX-STATE !
            _SME-SC @  _SOM-EXT SX.CTX-TARGET !
        THEN
        -1 EXIT
    THEN
    \ Empty scope — cursor stays as scope with no current
    0 _SOM-EXT SX.CURRENT !
    _SME-SC @ _SOM-EXT SX.SCOPE !
    -1 ;

\ =====================================================================
\  Cursor Movement — SOM-BACK (SOM §3.2)
\ =====================================================================

\ SOM-BACK ( tree -- moved? )
\   Exit current scope.  Denied if in a trap.
VARIABLE _SMB-OLD-SC
VARIABLE _SMB-POS
VARIABLE _SMB-RES

: SOM-BACK  ( tree -- moved? )
    SML-TREE-USE
    _SOM-EXT SX.SCOPE @ 0= IF 0 EXIT THEN
    \ Denied in a trap
    _SOM-EXT SX.SCOPE @  _SOM-SCOPE-TRAP? IF 0 EXIT THEN
    \ Pop focus stack
    _SOM-FS-POP  _SMB-RES !  _SMB-POS !  _SMB-OLD-SC !
    _SMB-OLD-SC @ 0= IF 0 EXIT THEN     \ empty stack
    \ Pop again to get parent scope frame
    _SOM-FS-PEEK  DROP DROP              \ parent scope
    DUP 0= IF
        DROP
        \ No parent scope — we're at root, re-push and deny
        _SMB-OLD-SC @ _SMB-POS @ _SMB-RES @ _SOM-FS-PUSH
        0 EXIT
    THEN
    \ Land cursor on the scope element in parent scope
    _SMB-OLD-SC @  SWAP _SOM-SET-CURSOR
    \ Reset input context to NAV
    SOM-CTX-NAV _SOM-EXT SX.CTX-STATE !
    0 _SOM-EXT SX.CTX-TARGET !
    -1 ;

\ =====================================================================
\  Cursor Movement — SOM-JUMP (SOM §3.2)
\ =====================================================================

\ SOM-JUMP ( id-a id-u tree -- moved? )
\   Jump cursor to the element with given id.
VARIABLE _SMJ-NODE
VARIABLE _SMJ-SC

: SOM-JUMP  ( id-a id-u tree -- moved? )
    SML-TREE-USE  _SML-USE-DOC
    \ Find element by id
    DOM-DOC  D.NODE-BASE @
    -ROT DOM-GET-BY-ID
    _SMJ-NODE !
    _SMJ-NODE @ 0= IF 0 EXIT THEN
    \ Find containing scope
    _SMJ-NODE @ _SOM-CONTAINING-SCOPE  _SMJ-SC !
    _SMJ-SC @ 0= IF 0 EXIT THEN
    \ If the target is a scope itself, land on it in its parent scope
    _SMJ-NODE @ _SML-NODE-SCOPE? IF
        _SMJ-NODE @ _SOM-CONTAINING-SCOPE _SMJ-SC !
        _SMJ-SC @ 0= IF 0 EXIT THEN
    THEN
    \ Set cursor
    _SMJ-NODE @  _SMJ-SC @ _SOM-SET-CURSOR
    -1 ;

\ =====================================================================
\  Input Context API (SOM §5)
\ =====================================================================

\ SOM-CTX@ ( tree -- state )
: SOM-CTX@  ( tree -- state )
    DROP  _SOM-EXT SX.CTX-STATE @ ;

\ SOM-CTX-ENTER ( target state tree -- )
\   Transition to new input context.
: SOM-CTX-ENTER  ( target state tree -- )
    DROP
    _SOM-EXT SX.CTX-STATE !
    _SOM-EXT SX.CTX-TARGET !
    0 _SOM-EXT SX.CTX-VALUE ! ;

\ SOM-CTX-EXIT ( tree -- )
\   Return to navigation context.
: SOM-CTX-EXIT  ( tree -- )
    DROP
    SOM-CTX-NAV _SOM-EXT SX.CTX-STATE !
    0 _SOM-EXT SX.CTX-TARGET !
    0 _SOM-EXT SX.CTX-VALUE ! ;

\ SOM-CTX-TARGET ( tree -- node|0 )
: SOM-CTX-TARGET  ( tree -- node|0 )
    DROP  _SOM-EXT SX.CTX-TARGET @ ;

\ SOM-CTX-VALUE ( tree -- val )
: SOM-CTX-VALUE  ( tree -- val )
    DROP  _SOM-EXT SX.CTX-VALUE @ ;

\ SOM-CTX-SET-VALUE ( val tree -- )
: SOM-CTX-SET-VALUE  ( val tree -- )
    DROP  _SOM-EXT SX.CTX-VALUE ! ;

\ =====================================================================
\  SML-PATCH — Mutation stub (deferred to Layer 3)
\ =====================================================================

\ SML-PATCH ( op-a op-u tree -- )
\   Placeholder.  Mutation operations will be defined in the
\   inceptor layer.
: SML-PATCH  ( op-a op-u tree -- )
    DROP 2DROP ;

\ =====================================================================
\  Convenience: SML-INIT
\ =====================================================================

\ SML-INIT ( sml-a sml-u -- tree )
\   Create a tree, load SML markup, initialize cursor.
\   Returns the tree handle.
: SML-INIT  ( sml-a sml-u -- tree )
    SML-TREE-CREATE  -ROT
    SML-TREE  SML-LOAD
    SML-TREE  _SOM-INIT-CURSOR ;
