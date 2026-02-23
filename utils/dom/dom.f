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
