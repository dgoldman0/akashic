\ dom.f — DOM vocabulary for KDOS Forth
\
\ Arena-backed document object model.  Each document lives in
\ a single KDOS arena, enabling multiple simultaneous documents
\ and O(1) bulk teardown via ARENA-DESTROY.
\
\ Prefix: DOM-   (public API)
\         _DOM-  (internal helpers)
\
\ Load with:   REQUIRE dom.f

PROVIDED akashic-dom
REQUIRE ../css/bridge.f

\ =====================================================================
\  Constants
\ =====================================================================

1 CONSTANT DOM-T-ELEMENT
2 CONSTANT DOM-T-TEXT
3 CONSTANT DOM-T-COMMENT
4 CONSTANT DOM-T-DOCUMENT
5 CONSTANT DOM-T-FRAGMENT

80 CONSTANT DOM-NODE-SIZE     \ 10 cells per node
24 CONSTANT DOM-ATTR-SIZE     \ 3 cells per attribute

\ =====================================================================
\  Document Descriptor Layout (10 cells = 80 bytes)
\ =====================================================================
\
\  +0   arena       KDOS arena handle
\  +8   str-base    string region start
\ +16   str-ptr     string bump pointer
\ +24   str-end     string region end
\ +32   node-base   node pool start
\ +40   node-max    max nodes
\ +48   node-free   node free-list head (0 = empty)
\ +56   attr-base   attr pool start
\ +64   attr-max    max attrs
\ +72   attr-free   attr free-list head (0 = empty)

: D.ARENA     ;            \ +0
: D.STR-BASE  8 + ;        \ +8
: D.STR-PTR   16 + ;       \ +16
: D.STR-END   24 + ;       \ +24
: D.NODE-BASE 32 + ;       \ +32
: D.NODE-MAX  40 + ;       \ +40
: D.NODE-FREE 48 + ;       \ +48
: D.ATTR-BASE 56 + ;       \ +56
: D.ATTR-MAX  64 + ;       \ +64
: D.ATTR-FREE 72 + ;       \ +72

\ =====================================================================
\  Current Document
\ =====================================================================

VARIABLE _DOM-CUR    \ current document handle

: DOM-USE   ( doc -- )  _DOM-CUR ! ;
: DOM-DOC   ( -- doc )  _DOM-CUR @ ;

\ =====================================================================
\  Node Record Field Accessors
\ =====================================================================
\
\  Node record layout (10 cells = 80 bytes):
\    +0   type          element/text/comment/document/fragment
\    +8   flags         (reserved)
\   +16   parent        node address (0 = none)
\   +24   first-child   node address (0 = none)
\   +32   last-child    node address (0 = none)
\   +40   next-sibling  node address (0 = none)
\   +48   prev-sibling  node address (0 = none)
\   +56   name-or-text  string handle (tag name for elements, text for text/comment)
\   +64   first-attr    attr pool address (0 = none)
\   +72   aux           style cache handle or other per-type data

: N.TYPE       ;            \ +0
: N.FLAGS      8 + ;        \ +8
: N.PARENT     16 + ;       \ +16
: N.FIRST-CHILD 24 + ;      \ +24
: N.LAST-CHILD  32 + ;      \ +32
: N.NEXT-SIB   40 + ;       \ +40
: N.PREV-SIB   48 + ;       \ +48
: N.NAME       56 + ;       \ +56
: N.FIRST-ATTR 64 + ;       \ +64
: N.AUX        72 + ;       \ +72

\ _DOM-NODE-INIT-FREE ( -- )
\   Build free-list through node pool: chain slots via +0 field.
VARIABLE _DNIF-I
VARIABLE _DNIF-A

: _DOM-NODE-INIT-FREE  ( -- )
    DOM-DOC D.NODE-BASE @  _DNIF-A !
    DOM-DOC D.NODE-MAX @  1- 0 DO
        _DNIF-A @  DOM-NODE-SIZE +   \ next slot address
        _DNIF-A @ !                  \ current.+0 = next
        _DNIF-A @  DOM-NODE-SIZE +  _DNIF-A !
    LOOP
    0  _DNIF-A @ !   \ last slot.+0 = 0 (end of list)
    DOM-DOC D.NODE-BASE @  DOM-DOC D.NODE-FREE ! ;

\ _DOM-ATTR-INIT-FREE ( -- )
\   Build free-list through attr pool: chain slots via +0 field.
VARIABLE _DAIF-A

: _DOM-ATTR-INIT-FREE  ( -- )
    DOM-DOC D.ATTR-BASE @  _DAIF-A !
    DOM-DOC D.ATTR-MAX @  1- 0 DO
        _DAIF-A @  DOM-ATTR-SIZE +
        _DAIF-A @ !
        _DAIF-A @  DOM-ATTR-SIZE +  _DAIF-A !
    LOOP
    0  _DAIF-A @ !
    DOM-DOC D.ATTR-BASE @  DOM-DOC D.ATTR-FREE ! ;

\ =====================================================================
\  Layer 0 — Document Creation
\ =====================================================================

VARIABLE _DDN-AR     \ arena
VARIABLE _DDN-NN     \ max nodes
VARIABLE _DDN-NA     \ max attrs
VARIABLE _DDN-DOC    \ doc descriptor address

: DOM-DOC-NEW  ( arena max-nodes max-attrs -- doc )
    _DDN-NA !  _DDN-NN !  _DDN-AR !
    \ Allot descriptor (80 bytes) from arena
    _DDN-AR @  80 ARENA-ALLOT  _DDN-DOC !
    \ Store arena handle in descriptor
    _DDN-AR @  _DDN-DOC @ D.ARENA !
    \ Allot node pool slab
    _DDN-AR @  _DDN-NN @ DOM-NODE-SIZE * ARENA-ALLOT
    _DDN-DOC @ D.NODE-BASE !
    _DDN-NN @  _DDN-DOC @ D.NODE-MAX !
    0          _DDN-DOC @ D.NODE-FREE !
    \ Allot attr pool slab
    _DDN-AR @  _DDN-NA @ DOM-ATTR-SIZE * ARENA-ALLOT
    _DDN-DOC @ D.ATTR-BASE !
    _DDN-NA @  _DDN-DOC @ D.ATTR-MAX !
    0          _DDN-DOC @ D.ATTR-FREE !
    \ String region = remaining arena space
    _DDN-AR @ A.PTR @   _DDN-DOC @ D.STR-BASE !
    _DDN-AR @ A.PTR @   _DDN-DOC @ D.STR-PTR !
    \ str-end = arena base + arena size
    _DDN-AR @ DUP A.BASE @ SWAP A.SIZE @ +
    _DDN-DOC @ D.STR-END !
    \ Claim remaining arena space (advance ptr to end)
    _DDN-DOC @ D.STR-END @  _DDN-AR @ A.PTR !
    \ Build node and attr free-lists
    _DDN-DOC @  DOM-USE
    _DOM-NODE-INIT-FREE
    _DOM-ATTR-INIT-FREE
    \ Return doc handle
    DOM-DOC ;

\ =====================================================================
\  Layer 0 — String Pool
\ =====================================================================
\
\ String entries in the string region:
\   +0   len       (1 cell) — byte length of string
\   +8   refcount  (1 cell) — reference count
\  +16   bytes     (ALIGN8(len) bytes) — string data
\
\ Handle = address of entry.  Handle 0 = "no string" sentinel.
\ Bump-only allocation: released slots are NOT reused in v1.

VARIABLE _DSA-SRC    \ source address
VARIABLE _DSA-LEN    \ source length
VARIABLE _DSA-ESZ    \ entry size

: _DOM-STR-ALLOC  ( src-a src-u -- handle )
    _DSA-LEN !  _DSA-SRC !
    \ Entry size = 16 + ALIGN8(len)
    _DSA-LEN @ 7 + -8 AND 16 +  _DSA-ESZ !
    \ Check space
    DOM-DOC D.STR-PTR @  _DSA-ESZ @ +
    DOM-DOC D.STR-END @  > ABORT" DOM string pool full"
    \ Handle = current str-ptr
    DOM-DOC D.STR-PTR @
    \ Write header
    _DSA-LEN @ OVER !           \ len at +0
    1 OVER 8 + !                \ refcount=1 at +8
    \ Copy string bytes
    _DSA-LEN @ 0> IF
        _DSA-SRC @  OVER 16 +  _DSA-LEN @  CMOVE
    THEN
    \ Advance str-ptr
    DOM-DOC D.STR-PTR @  _DSA-ESZ @ +
    DOM-DOC D.STR-PTR ! ;

: _DOM-STR-GET  ( handle -- addr len )
    DUP 0= IF  0 EXIT  THEN    \ handle 0 → 0 0
    DUP 16 + SWAP @ ;

: _DOM-STR-REF  ( handle -- )
    DUP 0= IF  DROP EXIT  THEN
    DUP 8 + @ 1+  SWAP 8 + ! ;

: _DOM-STR-RELEASE  ( handle -- )
    DUP 0= IF  DROP EXIT  THEN
    DUP 8 + @ 1-  SWAP 8 + ! ;

: _DOM-STR-REFCOUNT  ( handle -- n )
    DUP 0= IF  EXIT  THEN
    8 + @ ;

: _DOM-STR-FREE?  ( -- n )
    DOM-DOC D.STR-END @
    DOM-DOC D.STR-PTR @  - ;

\ =====================================================================
\  Layer 1 — Node Allocation (alloc/free via free-list)
\ =====================================================================

\ _DOM-ZERO-NODE ( node -- )
\   Zero all 10 cells of a node record.
: _DOM-ZERO-NODE  ( node -- )
    80 0 FILL ;

\ _DOM-ALLOC ( type -- node )
\   Allocate a node from the current doc's free-list.
VARIABLE _DA-TY

: _DOM-ALLOC  ( type -- node )
    _DA-TY !
    DOM-DOC D.NODE-FREE @
    DUP 0= ABORT" DOM node pool exhausted"
    DUP @  DOM-DOC D.NODE-FREE !     \ pop free-list head
    DUP _DOM-ZERO-NODE
    _DA-TY @  OVER N.TYPE ! ;

\ _DOM-FREE ( node -- )
\   Release strings, zero node, push onto free-list.
: _DOM-FREE  ( node -- )
    DUP N.NAME @ _DOM-STR-RELEASE
    DUP N.AUX @ _DOM-STR-RELEASE
    DUP _DOM-ZERO-NODE
    DOM-DOC D.NODE-FREE @  OVER !    \ node.+0 = old head
    DOM-DOC D.NODE-FREE ! ;          \ head = node

\ -- Node field accessors --

: DOM-TYPE@   ( node -- type )   N.TYPE @ ;
: DOM-FLAGS@  ( node -- flags )  N.FLAGS @ ;
: DOM-FLAGS!  ( flags node -- )  N.FLAGS ! ;

\ =====================================================================
\  Layer 2 — Tree Structure
\ =====================================================================
\
\ Doubly-linked child lists for O(1) append, prepend, detach.

: DOM-PARENT       ( node -- parent|0 )    N.PARENT @ ;
: DOM-FIRST-CHILD  ( node -- child|0 )     N.FIRST-CHILD @ ;
: DOM-LAST-CHILD   ( node -- child|0 )     N.LAST-CHILD @ ;
: DOM-NEXT         ( node -- sib|0 )       N.NEXT-SIB @ ;
: DOM-PREV         ( node -- sib|0 )       N.PREV-SIB @ ;

\ DOM-APPEND ( child parent -- )
\   Append child to end of parent's child list.
VARIABLE _DAP-C    VARIABLE _DAP-P

: DOM-APPEND  ( child parent -- )
    _DAP-P !  _DAP-C !
    \ Detach child from any current parent first
    _DAP-C @ DOM-PARENT IF
        _DAP-C @ DOM-PARENT _DAP-P @ <> IF
            \ TODO: full detach — for now just link
        THEN
    THEN
    \ Set child's parent
    _DAP-P @  _DAP-C @ N.PARENT !
    \ Clear child's sibling links
    0 _DAP-C @ N.NEXT-SIB !
    \ If parent has no children, child becomes first and last
    _DAP-P @ N.FIRST-CHILD @ 0= IF
        _DAP-C @  _DAP-P @ N.FIRST-CHILD !
        _DAP-C @  _DAP-P @ N.LAST-CHILD !
        0 _DAP-C @ N.PREV-SIB !
        EXIT
    THEN
    \ Otherwise, link after current last child
    _DAP-P @ N.LAST-CHILD @   \ old-last
    _DAP-C @ OVER N.NEXT-SIB !   \ old-last.next = child
    _DAP-C @ N.PREV-SIB !        \ child.prev = old-last
    _DAP-C @  _DAP-P @ N.LAST-CHILD ! ;

\ DOM-PREPEND ( child parent -- )
\   Prepend child to beginning of parent's child list.
VARIABLE _DPP-C    VARIABLE _DPP-P

: DOM-PREPEND  ( child parent -- )
    _DPP-P !  _DPP-C !
    _DPP-P @  _DPP-C @ N.PARENT !
    0 _DPP-C @ N.PREV-SIB !
    _DPP-P @ N.FIRST-CHILD @ 0= IF
        _DPP-C @  _DPP-P @ N.FIRST-CHILD !
        _DPP-C @  _DPP-P @ N.LAST-CHILD !
        0 _DPP-C @ N.NEXT-SIB !
        EXIT
    THEN
    _DPP-P @ N.FIRST-CHILD @      \ old-first
    _DPP-C @ OVER N.PREV-SIB !    \ old-first.prev = child
    _DPP-C @ N.NEXT-SIB !         \ child.next = old-first
    _DPP-C @  _DPP-P @ N.FIRST-CHILD ! ;

\ DOM-DETACH ( node -- )
\   Remove node from its parent's child list, fix sibling links.
VARIABLE _DD-N   VARIABLE _DD-P

: DOM-DETACH  ( node -- )
    _DD-N !
    _DD-N @ N.PARENT @  DUP 0= IF  DROP EXIT  THEN
    _DD-P !
    \ Fix prev sibling's next pointer
    _DD-N @ N.PREV-SIB @ ?DUP IF
        _DD-N @ N.NEXT-SIB @  SWAP N.NEXT-SIB !
    ELSE
        \ Node is first child — update parent's first-child
        _DD-N @ N.NEXT-SIB @  _DD-P @ N.FIRST-CHILD !
    THEN
    \ Fix next sibling's prev pointer
    _DD-N @ N.NEXT-SIB @ ?DUP IF
        _DD-N @ N.PREV-SIB @  SWAP N.PREV-SIB !
    ELSE
        \ Node is last child — update parent's last-child
        _DD-N @ N.PREV-SIB @  _DD-P @ N.LAST-CHILD !
    THEN
    \ Clear node's links
    0 _DD-N @ N.PARENT !
    0 _DD-N @ N.PREV-SIB !
    0 _DD-N @ N.NEXT-SIB ! ;

\ DOM-INSERT-BEFORE ( new-node ref-node -- )
\   Insert new-node before ref-node in ref's parent's child list.
VARIABLE _DIB-N   VARIABLE _DIB-R   VARIABLE _DIB-P

: DOM-INSERT-BEFORE  ( new ref -- )
    _DIB-R !  _DIB-N !
    _DIB-R @ N.PARENT @  _DIB-P !
    _DIB-P @ 0= ABORT" DOM-INSERT-BEFORE: ref has no parent"
    \ Set new's parent
    _DIB-P @  _DIB-N @ N.PARENT !
    \ Link new <-> ref's prev
    _DIB-R @ N.PREV-SIB @  _DIB-N @ N.PREV-SIB !   \ new.prev = ref.prev
    _DIB-R @ N.PREV-SIB @ ?DUP IF
        _DIB-N @ SWAP N.NEXT-SIB !                  \ ref.prev.next = new
    ELSE
        _DIB-N @ _DIB-P @ N.FIRST-CHILD !           \ new is first child
    THEN
    \ Link new <-> ref
    _DIB-N @  _DIB-R @ N.PREV-SIB !                 \ ref.prev = new
    _DIB-R @  _DIB-N @ N.NEXT-SIB ! ;               \ new.next = ref

\ DOM-CHILD-COUNT ( node -- n )
\   Count number of children.
VARIABLE _DCC-N

: DOM-CHILD-COUNT  ( node -- n )
    N.FIRST-CHILD @  0    \ ( cursor count )
    BEGIN  OVER  WHILE
        1+  SWAP N.NEXT-SIB @ SWAP
    REPEAT  NIP ;

\ =====================================================================
\  Layer 3 — Attribute Storage
\ =====================================================================
\
\  Attr record layout (3 cells = 24 bytes):
\    +0   name    string handle
\    +8   value   string handle
\   +16   next    next attr address (0 = end of list)

: A.NAME   ;            \ +0
: A.VALUE  8 + ;        \ +8
: A.NEXT   16 + ;       \ +16

\ -- Helpers -------------------------------------------------------

\ _DOM-TOLOWER ( c -- c' )
\   Convert ASCII uppercase to lowercase; leave others unchanged.
: _DOM-TOLOWER  ( c -- c' )
    DUP 65 < IF EXIT THEN
    DUP 90 > IF EXIT THEN
    32 + ;

\ _DOM-CISTREQ ( a1 u1 a2 u2 -- flag )
\   Case-insensitive byte-string equality.
VARIABLE _DCS-1   VARIABLE _DCS-2
VARIABLE _DCS-L   VARIABLE _DCS-I

: _DOM-CISTREQ  ( a1 u1 a2 u2 -- flag )
    ROT OVER <> IF 2DROP DROP 0 EXIT THEN
    _DCS-L !  _DCS-2 !  _DCS-1 !
    _DCS-L @ 0= IF -1 EXIT THEN
    0 _DCS-I !
    BEGIN _DCS-I @ _DCS-L @ < WHILE
        _DCS-1 @ _DCS-I @ + C@  _DOM-TOLOWER
        _DCS-2 @ _DCS-I @ + C@  _DOM-TOLOWER
        <> IF 0 EXIT THEN
        _DCS-I @ 1+ _DCS-I !
    REPEAT
    -1 ;

\ -- Attr allocation -----------------------------------------------

\ _DOM-ATTR-ALLOC ( -- attr )
\   Pop attr slot from free-list, zero and return.
: _DOM-ATTR-ALLOC  ( -- attr )
    DOM-DOC D.ATTR-FREE @
    DUP 0= ABORT" DOM attr pool exhausted"
    DUP @  DOM-DOC D.ATTR-FREE !
    DUP 24 0 FILL ;

\ _DOM-ATTR-RELEASE ( attr -- )
\   Release name/value strings, zero slot, push onto free-list.
: _DOM-ATTR-RELEASE  ( attr -- )
    DUP A.NAME @ _DOM-STR-RELEASE
    DUP A.VALUE @ _DOM-STR-RELEASE
    DUP 24 0 FILL
    DOM-DOC D.ATTR-FREE @  OVER !
    DOM-DOC D.ATTR-FREE ! ;

\ -- Attribute access -----------------------------------------------

\ DOM-ATTR@ ( node name-a name-u -- val-a val-u flag )
\   Get attribute value by name (case-insensitive).
\   Returns value string and -1 if found, or 0 0 0 if not.
VARIABLE _DAG-NA   VARIABLE _DAG-NL   VARIABLE _DAG-A

: DOM-ATTR@  ( node name-a name-u -- val-a val-u flag )
    _DAG-NL !  _DAG-NA !
    N.FIRST-ATTR @  _DAG-A !
    BEGIN _DAG-A @ WHILE
        _DAG-A @ A.NAME @ _DOM-STR-GET
        _DAG-NA @ _DAG-NL @  _DOM-CISTREQ IF
            _DAG-A @ A.VALUE @ _DOM-STR-GET -1 EXIT
        THEN
        _DAG-A @ A.NEXT @  _DAG-A !
    REPEAT
    0 0 0 ;

\ DOM-ATTR! ( node name-a name-u val-a val-u -- )
\   Set attribute: update existing or create new.
VARIABLE _DAS-N   VARIABLE _DAS-NA   VARIABLE _DAS-NL
VARIABLE _DAS-VA  VARIABLE _DAS-VL   VARIABLE _DAS-A

: DOM-ATTR!  ( node name-a name-u val-a val-u -- )
    _DAS-VL !  _DAS-VA !  _DAS-NL !  _DAS-NA !  _DAS-N !
    _DAS-N @ N.FIRST-ATTR @  _DAS-A !
    BEGIN _DAS-A @ WHILE
        _DAS-A @ A.NAME @ _DOM-STR-GET
        _DAS-NA @ _DAS-NL @  _DOM-CISTREQ IF
            \ Update existing
            _DAS-A @ A.VALUE @ _DOM-STR-RELEASE
            _DAS-VA @ _DAS-VL @ _DOM-STR-ALLOC  _DAS-A @ A.VALUE !
            EXIT
        THEN
        _DAS-A @ A.NEXT @  _DAS-A !
    REPEAT
    \ Create new attr — link at head
    _DOM-ATTR-ALLOC  _DAS-A !
    _DAS-NA @ _DAS-NL @ _DOM-STR-ALLOC  _DAS-A @ A.NAME !
    _DAS-VA @ _DAS-VL @ _DOM-STR-ALLOC  _DAS-A @ A.VALUE !
    _DAS-N @ N.FIRST-ATTR @  _DAS-A @ A.NEXT !
    _DAS-A @  _DAS-N @ N.FIRST-ATTR ! ;

\ DOM-ATTR-DEL ( node name-a name-u -- )
\   Remove attribute by name (case-insensitive).
VARIABLE _DAD-N   VARIABLE _DAD-NA   VARIABLE _DAD-NL
VARIABLE _DAD-A   VARIABLE _DAD-P

: DOM-ATTR-DEL  ( node name-a name-u -- )
    _DAD-NL !  _DAD-NA !  _DAD-N !
    _DAD-N @ N.FIRST-ATTR @  _DAD-A !
    0 _DAD-P !
    BEGIN _DAD-A @ WHILE
        _DAD-A @ A.NAME @ _DOM-STR-GET
        _DAD-NA @ _DAD-NL @  _DOM-CISTREQ IF
            _DAD-P @ IF
                _DAD-A @ A.NEXT @  _DAD-P @ A.NEXT !
            ELSE
                _DAD-A @ A.NEXT @  _DAD-N @ N.FIRST-ATTR !
            THEN
            _DAD-A @ _DOM-ATTR-RELEASE
            EXIT
        THEN
        _DAD-A @ _DAD-P !
        _DAD-A @ A.NEXT @  _DAD-A !
    REPEAT ;

\ DOM-ATTR-HAS? ( node name-a name-u -- flag )
: DOM-ATTR-HAS?  ( node name-a name-u -- flag )
    DOM-ATTR@  NIP NIP ;

\ DOM-ATTR-COUNT ( node -- n )
: DOM-ATTR-COUNT  ( node -- n )
    N.FIRST-ATTR @  0
    BEGIN OVER WHILE
        1+  SWAP A.NEXT @ SWAP
    REPEAT NIP ;

\ -- Attr iteration -------------------------------------------------

: DOM-ATTR-FIRST    ( node -- attr|0 )    N.FIRST-ATTR @ ;
: DOM-ATTR-NEXTATTR ( attr -- attr|0 )    A.NEXT @ ;
: DOM-ATTR-NAME@    ( attr -- a u )       A.NAME @ _DOM-STR-GET ;
: DOM-ATTR-VAL@     ( attr -- a u )       A.VALUE @ _DOM-STR-GET ;

\ -- Shortcuts -------------------------------------------------------

: DOM-ID     ( node -- str-a str-u )   S" id" DOM-ATTR@ DROP ;
: DOM-CLASS  ( node -- str-a str-u )   S" class" DOM-ATTR@ DROP ;

\ =====================================================================
\  Layer 4 — Mutation
\ =====================================================================
\
\  High-level node creation, text manipulation, and subtree removal.

\ -- Node creation ---------------------------------------------------

: DOM-CREATE-ELEMENT  ( tag-a tag-u -- node )
    _DOM-STR-ALLOC
    DOM-T-ELEMENT _DOM-ALLOC
    SWAP OVER N.NAME ! ;

: DOM-CREATE-TEXT  ( txt-a txt-u -- node )
    _DOM-STR-ALLOC
    DOM-T-TEXT _DOM-ALLOC
    SWAP OVER N.NAME ! ;

: DOM-CREATE-COMMENT  ( txt-a txt-u -- node )
    _DOM-STR-ALLOC
    DOM-T-COMMENT _DOM-ALLOC
    SWAP OVER N.NAME ! ;

: DOM-CREATE-FRAGMENT  ( -- node )
    DOM-T-FRAGMENT _DOM-ALLOC ;

\ -- Name / text access ----------------------------------------------

: DOM-TAG-NAME  ( node -- name-a name-u )   N.NAME @ _DOM-STR-GET ;
: DOM-TEXT      ( node -- txt-a txt-u )     N.NAME @ _DOM-STR-GET ;

VARIABLE _DST-N

: DOM-SET-TEXT  ( node txt-a txt-u -- )
    ROT _DST-N !
    _DST-N @ N.NAME @ _DOM-STR-RELEASE
    _DOM-STR-ALLOC
    _DST-N @ N.NAME ! ;

\ -- Deep removal ----------------------------------------------------

\ _DOM-FREE-ATTRS ( node -- )
\   Release and free all attr records on a node.
VARIABLE _DFA-A   VARIABLE _DFA-NX

: _DOM-FREE-ATTRS  ( node -- )
    N.FIRST-ATTR @  _DFA-A !
    BEGIN _DFA-A @ WHILE
        _DFA-A @ A.NEXT @  _DFA-NX !
        _DFA-A @ _DOM-ATTR-RELEASE
        _DFA-NX @  _DFA-A !
    REPEAT ;

\ DOM-REMOVE ( node -- )
\   Detach node, iteratively depth-first free entire subtree.
VARIABLE _DRM-CUR   VARIABLE _DRM-PAR

: DOM-REMOVE  ( node -- )
    DUP DOM-DETACH
    _DRM-CUR !
    BEGIN
        \ Navigate to deepest first child (leaf)
        BEGIN _DRM-CUR @ DOM-FIRST-CHILD DUP WHILE
            _DRM-CUR !
        REPEAT DROP
        \ Free this leaf/childless node
        _DRM-CUR @ N.PARENT @  _DRM-PAR !
        _DRM-CUR @ DOM-DETACH
        _DRM-CUR @ _DOM-FREE-ATTRS
        _DRM-CUR @ _DOM-FREE
        _DRM-PAR @ 0= IF EXIT THEN
        _DRM-PAR @ _DRM-CUR !
    AGAIN ;

\ =====================================================================
\  Layer 5 — Style Resolution
\ =====================================================================
\
\  Computes applied CSS styles for DOM elements by:
\    1. Reconstructing an HTML opening tag from node tag + attrs
\    2. Feeding it to CSSB-APPLY-INLINE with the document stylesheet
\    3. Providing property lookup via CSS-DECL-FIND
\
\  v1: no caching — recomputes on each call.

\ -- Stylesheet storage -----------------------------------------------

VARIABLE _DOM-CSS-A    \ stylesheet text address
VARIABLE _DOM-CSS-L    \ stylesheet text length

: DOM-SET-STYLESHEET  ( css-a css-u -- )
    _DOM-CSS-L !  _DOM-CSS-A ! ;

\ -- Open-tag reconstruction -----------------------------------------
\
\  Rebuilds <tag attr="val" ...> from a DOM element node so the
\  CSS bridge can parse tag/id/class/style as if it were raw HTML.

CREATE _DOM-TAG-BUF 512 ALLOT    \ scratch buffer for open tag

VARIABLE _DBOT-BA   VARIABLE _DBOT-BL   VARIABLE _DBOT-MX
VARIABLE _DBOT-AT

\ _DBOT-C ( ch -- )  Append one byte, bounds-checked.
: _DBOT-C  ( ch -- )
    _DBOT-BL @ _DBOT-MX @ >= IF DROP EXIT THEN
    _DBOT-BA @ _DBOT-BL @ + C!  1 _DBOT-BL +! ;

\ _DBOT-S ( a u -- )  Append string, truncated to fit.
VARIABLE _DBOT-SA   VARIABLE _DBOT-SN

: _DBOT-S  ( a u -- )
    _DBOT-SN !  _DBOT-SA !
    _DBOT-BL @ _DBOT-MX @ >= IF EXIT THEN
    _DBOT-BL @ _DBOT-SN @ + _DBOT-MX @ > IF
        _DBOT-MX @ _DBOT-BL @ -  _DBOT-SN !
    THEN
    _DBOT-SN @ 0= IF EXIT THEN
    _DBOT-SA @  _DBOT-BA @ _DBOT-BL @ +  _DBOT-SN @  CMOVE
    _DBOT-SN @ _DBOT-BL +! ;

\ _DOM-BUILD-OPEN-TAG ( node buf max -- n )
\   Reconstruct <tagname attr="val" ...> from DOM element.
VARIABLE _DBOT-N

: _DOM-BUILD-OPEN-TAG  ( node buf max -- n )
    _DBOT-MX !  _DBOT-BA !  _DBOT-N !
    0 _DBOT-BL !
    60 _DBOT-C                          \ '<'
    _DBOT-N @ DOM-TAG-NAME _DBOT-S      \ tag name
    _DBOT-N @ DOM-ATTR-FIRST _DBOT-AT !
    BEGIN _DBOT-AT @ WHILE
        32 _DBOT-C                      \ space
        _DBOT-AT @ DOM-ATTR-NAME@ _DBOT-S
        61 _DBOT-C                      \ '='
        34 _DBOT-C                      \ '"'
        _DBOT-AT @ DOM-ATTR-VAL@  _DBOT-S
        34 _DBOT-C                      \ '"'
        _DBOT-AT @ DOM-ATTR-NEXTATTR _DBOT-AT !
    REPEAT
    62 _DBOT-C                          \ '>'
    _DBOT-BL @ ;

\ -- Style computation -----------------------------------------------

CREATE _DOM-STY-BUF 2048 ALLOT    \ scratch buffer for computed styles

VARIABLE _DCS-N   VARIABLE _DCS-BA   VARIABLE _DCS-MX
VARIABLE _DCS-TL

: DOM-COMPUTE-STYLE  ( node buf max -- n )
    _DCS-MX !  _DCS-BA !  _DCS-N !
    \ Only element nodes have styles
    _DCS-N @ DOM-TYPE@ DOM-T-ELEMENT <> IF 0 EXIT THEN
    \ Reconstruct open tag
    _DCS-N @ _DOM-TAG-BUF 512 _DOM-BUILD-OPEN-TAG _DCS-TL !
    \ Compute matched styles + inline via bridge
    _DOM-CSS-A @ _DOM-CSS-L @      \ css-a css-u
    _DOM-TAG-BUF _DCS-TL @        \ html-a html-u
    _DCS-BA @ _DCS-MX @           \ buf max
    CSSB-APPLY-INLINE ;

\ -- Property lookup --------------------------------------------------

VARIABLE _DSL-N   VARIABLE _DSL-PA   VARIABLE _DSL-PL

: DOM-STYLE@  ( node prop-a prop-u -- val-a val-u flag )
    _DSL-PL !  _DSL-PA !  _DSL-N !
    _DSL-N @ DOM-TYPE@ DOM-T-ELEMENT <> IF 0 0 0 EXIT THEN
    _DSL-N @ _DOM-STY-BUF 2048 DOM-COMPUTE-STYLE
    _DOM-STY-BUF SWAP
    _DSL-PA @ _DSL-PL @
    CSS-DECL-FIND ;

\ -- Cache stubs (v1: no caching) ------------------------------------

: DOM-STYLE-CACHED?     ( node -- flag )   DROP 0 ;
: DOM-INVALIDATE-STYLE  ( node -- )        DROP ;
