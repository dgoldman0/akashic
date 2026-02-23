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
    \ Set as current and return doc handle
    _DDN-DOC @  DUP DOM-USE ;

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
