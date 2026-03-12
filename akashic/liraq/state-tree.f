\ state-tree.f — LIRAQ State Tree (Layer 1)
\
\ Arena-backed hierarchical key-value store, path-addressed with
\ dot-separated paths.  Each state tree lives in a single KDOS
\ arena, enabling multiple simultaneous trees and O(1) bulk
\ teardown via ARENA-DESTROY.
\
\ Value types: String, Integer, Boolean, Null, Float, Array, Object.
\ Float values stored as packed IEEE-754 FP32 (software, via akashic-fp32).
\
\ Prefix: ST-   (public API)
\         _ST-  (internal helpers)
\
\ Load with:   REQUIRE state-tree.f

REQUIRE ../utils/string.f
REQUIRE ../math/fp32.f

PROVIDED akashic-state-tree

\ =====================================================================
\  Type tags
\ =====================================================================

0 CONSTANT ST-T-FREE
1 CONSTANT ST-T-STRING
2 CONSTANT ST-T-INTEGER
3 CONSTANT ST-T-BOOLEAN
4 CONSTANT ST-T-NULL
5 CONSTANT ST-T-FLOAT
6 CONSTANT ST-T-ARRAY
7 CONSTANT ST-T-OBJECT

\ =====================================================================
\  Flag bits
\ =====================================================================

1 CONSTANT ST-F-PROTECTED    \ path starts with _
2 CONSTANT ST-F-READONLY     \ DCS may not mutate

\ =====================================================================
\  Error codes
\ =====================================================================

1 CONSTANT ST-E-NOT-FOUND
2 CONSTANT ST-E-TYPE
3 CONSTANT ST-E-FULL
4 CONSTANT ST-E-PROTECTED
5 CONSTANT ST-E-POOL-FULL
6 CONSTANT ST-E-BAD-PATH
7 CONSTANT ST-E-BAD-INDEX

\ =====================================================================
\  Node layout — 96 bytes (12 cells)
\ =====================================================================

: SN.TYPE    ( node -- addr )  ;            \ offset  0
: SN.FLAGS   ( node -- addr )  8 + ;        \ offset  8
: SN.PARENT  ( node -- addr )  16 + ;       \ offset 16
: SN.NEXT    ( node -- addr )  24 + ;       \ offset 24
: SN.PREV    ( node -- addr )  32 + ;       \ offset 32
: SN.FCHILD  ( node -- addr )  40 + ;       \ offset 40
: SN.LCHILD  ( node -- addr )  48 + ;       \ offset 48
: SN.NCHILD  ( node -- addr )  56 + ;       \ offset 56
: SN.NAMEA   ( node -- addr )  64 + ;       \ offset 64
: SN.NAMEL   ( node -- addr )  72 + ;       \ offset 72
: SN.VAL1    ( node -- addr )  80 + ;       \ offset 80
: SN.VAL2    ( node -- addr )  88 + ;       \ offset 88

96 CONSTANT _ST-NODESZ

\ =====================================================================
\  Defaults
\ =====================================================================

128 CONSTANT _ST-JRNL-MAX
72 CONSTANT _ST-JRNL-ENTRY

\ =====================================================================
\  Descriptor layout — 128 bytes (16 cells)
\ =====================================================================
\
\  +0    arena        KDOS arena handle
\  +8    node-base    node pool start
\  +16   node-max     max node count
\  +24   node-free    free-list head (0 = empty)
\  +32   node-used    count of allocated nodes
\  +40   str-base     string pool region start
\  +48   str-ptr      string pool bump pointer
\  +56   str-end      string pool region end
\  +64   root         root node address
\  +72   jrnl-base    journal entry array
\  +80   jrnl-max     max journal entries
\  +88   jrnl-pos     circular write position
\  +96   jrnl-seq     sequence counter
\  +104  jrnl-cnt     entry count
\  +112  jrnl-src     current source tag
\  +120  err          error code

128 CONSTANT _ST-DESCSZ

: SD.ARENA      ( st -- addr )  ;              \ +0
: SD.NODE-BASE  ( st -- addr )  8 + ;          \ +8
: SD.NODE-MAX   ( st -- addr )  16 + ;         \ +16
: SD.NODE-FREE  ( st -- addr )  24 + ;         \ +24
: SD.NODE-USED  ( st -- addr )  32 + ;         \ +32
: SD.STR-BASE   ( st -- addr )  40 + ;         \ +40
: SD.STR-PTR    ( st -- addr )  48 + ;         \ +48
: SD.STR-END    ( st -- addr )  56 + ;         \ +56
: SD.ROOT       ( st -- addr )  64 + ;         \ +64
: SD.JRNL-BASE  ( st -- addr )  72 + ;         \ +72
: SD.JRNL-MAX   ( st -- addr )  80 + ;         \ +80
: SD.JRNL-POS   ( st -- addr )  88 + ;         \ +88
: SD.JRNL-SEQ   ( st -- addr )  96 + ;         \ +96
: SD.JRNL-CNT   ( st -- addr )  104 + ;        \ +104
: SD.JRNL-SRC   ( st -- addr )  112 + ;        \ +112
: SD.ERR        ( st -- addr )  120 + ;        \ +120

\ =====================================================================
\  Current document
\ =====================================================================

VARIABLE _ST-CUR    \ current state tree handle

: ST-USE  ( st -- )  _ST-CUR ! ;
: ST-DOC  ( -- st )  _ST-CUR @ ;

\ =====================================================================
\  Error handling
\ =====================================================================

: ST-ERR       ( -- addr )  ST-DOC SD.ERR ;
: ST-FAIL      ( code -- )  ST-ERR ! ;
: ST-OK?       ( -- flag )  ST-ERR @ 0= ;
: ST-CLEAR-ERR ( -- )       0 ST-ERR ! ;

\ =====================================================================
\  Journal source constants
\ =====================================================================

0 CONSTANT ST-SRC-DCS
1 CONSTANT ST-SRC-BINDING
2 CONSTANT ST-SRC-BEHAVIOR
3 CONSTANT ST-SRC-RUNTIME

\ =====================================================================
\  Node pool — free-list allocation from arena slab
\ =====================================================================

VARIABLE _SNIF-A

: _ST-NODE-INIT-FREE  ( -- )
    ST-DOC SD.NODE-BASE @  _SNIF-A !
    ST-DOC SD.NODE-MAX @  1- 0 DO
        _SNIF-A @  _ST-NODESZ +
        _SNIF-A @ !
        _SNIF-A @  _ST-NODESZ +  _SNIF-A !
    LOOP
    0  _SNIF-A @ !
    ST-DOC SD.NODE-BASE @  ST-DOC SD.NODE-FREE ! ;

: _ST-ALLOC  ( -- node | 0 )
    ST-DOC SD.NODE-FREE @
    DUP 0= IF  ST-E-FULL ST-FAIL EXIT  THEN
    DUP @  ST-DOC SD.NODE-FREE !
    DUP _ST-NODESZ 0 FILL
    1 ST-DOC SD.NODE-USED +! ;

: _ST-FREE-NODE  ( node -- )
    DUP _ST-NODESZ 0 FILL
    ST-DOC SD.NODE-FREE @  OVER !
    ST-DOC SD.NODE-FREE !
    -1 ST-DOC SD.NODE-USED +! ;

\ =====================================================================
\  Document creation
\ =====================================================================

VARIABLE _SDN-AR
VARIABLE _SDN-NN
VARIABLE _SDN-DOC

: ST-DOC-NEW  ( arena max-nodes -- st )
    _SDN-NN !  _SDN-AR !
    \ Allot descriptor (128 bytes) from arena
    _SDN-AR @  _ST-DESCSZ ARENA-ALLOT  _SDN-DOC !
    _SDN-DOC @ _ST-DESCSZ 0 FILL
    _SDN-AR @  _SDN-DOC @ SD.ARENA !
    \ Allot node pool slab
    _SDN-AR @  _SDN-NN @ _ST-NODESZ * ARENA-ALLOT
    _SDN-DOC @ SD.NODE-BASE !
    _SDN-NN @  _SDN-DOC @ SD.NODE-MAX !
    0          _SDN-DOC @ SD.NODE-FREE !
    0          _SDN-DOC @ SD.NODE-USED !
    \ Allot journal slab
    _SDN-AR @  _ST-JRNL-MAX _ST-JRNL-ENTRY * ARENA-ALLOT
    _SDN-DOC @ SD.JRNL-BASE !
    _ST-JRNL-MAX  _SDN-DOC @ SD.JRNL-MAX !
    0  _SDN-DOC @ SD.JRNL-POS !
    0  _SDN-DOC @ SD.JRNL-SEQ !
    0  _SDN-DOC @ SD.JRNL-CNT !
    ST-SRC-DCS  _SDN-DOC @ SD.JRNL-SRC !
    0  _SDN-DOC @ SD.ERR !
    \ String region = remaining arena space
    _SDN-AR @ A.PTR @   _SDN-DOC @ SD.STR-BASE !
    _SDN-AR @ A.PTR @   _SDN-DOC @ SD.STR-PTR  !
    \ str-end = arena base + arena size
    _SDN-AR @ DUP A.BASE @ SWAP A.SIZE @ +
    _SDN-DOC @ SD.STR-END !
    \ Claim remaining arena space (advance ptr to end)
    _SDN-DOC @ SD.STR-END @  _SDN-AR @ A.PTR !
    \ Set as current document and build free list
    _SDN-DOC @  ST-USE
    _ST-NODE-INIT-FREE
    \ Create root node (object)
    _ST-ALLOC  DUP 0= ABORT" ST-DOC-NEW: pool empty"
    ST-T-OBJECT OVER SN.TYPE !
    ST-DOC SD.ROOT !
    \ Return handle
    ST-DOC ;

\ =====================================================================
\  Public handle accessors
\ =====================================================================

: ST-ROOT       ( -- node )  ST-DOC SD.ROOT @ ;
: ST-NODE-COUNT ( -- n )     ST-DOC SD.NODE-USED @ ;

\ =====================================================================
\  String pool — bump allocator from arena string region
\ =====================================================================

VARIABLE _STC-L
VARIABLE _STC-D
: _ST-STR-COPY  ( src len -- addr len )
    DUP _STC-L !
    ST-DOC SD.STR-PTR @  OVER +
    ST-DOC SD.STR-END @  > IF
        2DROP ST-E-POOL-FULL ST-FAIL 0 0 EXIT
    THEN
    ST-DOC SD.STR-PTR @  _STC-D !
    DROP
    _STC-L @ 0 ?DO
        DUP I + C@  _STC-D @ I + C!
    LOOP
    DROP
    _STC-L @ ST-DOC SD.STR-PTR +!
    _STC-D @ _STC-L @ ;

\ =====================================================================
\  Tree structure operations
\ =====================================================================

VARIABLE _STAC-C
VARIABLE _STAC-P
: _ST-APPEND-CHILD  ( child parent -- )
    _STAC-P !  _STAC-C !
    _STAC-P @ _STAC-C @ SN.PARENT !
    0 _STAC-C @ SN.NEXT !
    0 _STAC-C @ SN.PREV !
    _STAC-P @ SN.FCHILD @ 0= IF
        _STAC-C @ _STAC-P @ SN.FCHILD !
        _STAC-C @ _STAC-P @ SN.LCHILD !
    ELSE
        _STAC-P @ SN.LCHILD @
        DUP _STAC-C @ SN.PREV !
        SN.NEXT _STAC-C @ SWAP !
        _STAC-C @ _STAC-P @ SN.LCHILD !
    THEN
    1 _STAC-P @ SN.NCHILD +! ;

VARIABLE _STD-N
VARIABLE _STD-P
: _ST-DETACH  ( node -- )
    _STD-N !
    _STD-N @ SN.PARENT @ DUP 0= IF DROP EXIT THEN
    _STD-P !
    _STD-N @ SN.PREV @ ?DUP IF
        _STD-N @ SN.NEXT @ SWAP SN.NEXT !
    ELSE
        _STD-N @ SN.NEXT @ _STD-P @ SN.FCHILD !
    THEN
    _STD-N @ SN.NEXT @ ?DUP IF
        _STD-N @ SN.PREV @ SWAP SN.PREV !
    ELSE
        _STD-N @ SN.PREV @ _STD-P @ SN.LCHILD !
    THEN
    -1 _STD-P @ SN.NCHILD +!
    0 _STD-N @ SN.PARENT !
    0 _STD-N @ SN.NEXT !
    0 _STD-N @ SN.PREV ! ;

\ _ST-FIND-CHILD ( parent name-a name-l -- child | 0 )
\   Linear scan of children, compare names via STR-STR=.
VARIABLE _STFC-A
VARIABLE _STFC-L
: _ST-FIND-CHILD  ( parent name-a name-l -- child | 0 )
    _STFC-L ! _STFC-A !
    SN.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP SN.NAMEA @  OVER SN.NAMEL @
        _STFC-A @ _STFC-L @
        STR-STR=
        IF EXIT THEN
        SN.NEXT @
    REPEAT ;

: _ST-INDEX-CHILD  ( parent idx -- child | 0 )
    SWAP SN.FCHILD @
    SWAP
    0 ?DO
        DUP 0= IF UNLOOP EXIT THEN
        SN.NEXT @
    LOOP ;

: _ST-DESTROY  ( node -- )
    DUP SN.FCHILD @
    BEGIN
        DUP 0<> WHILE
        DUP SN.NEXT @
        SWAP RECURSE
    REPEAT
    DROP
    _ST-FREE-NODE ;

\ =====================================================================
\  Path navigation
\ =====================================================================

: _ST-SPLIT-DOT  ( path-a path-l -- first-a first-l rest-a rest-l flag )
    46 STR-SPLIT ;

: _ST-IS-INDEX?  ( str-a str-l -- n flag )
    STR>NUM ;

\ _ST-DESCEND ( node seg-a seg-l -- child | 0 )
\   Descend one level into an object (by name) or array (by index).
VARIABLE _STDES-N
: _ST-DESCEND  ( node seg-a seg-l -- child | 0 )
    ROT _STDES-N !
    _STDES-N @ SN.TYPE @
    DUP ST-T-OBJECT = IF
        DROP
        _STDES-N @ -ROT _ST-FIND-CHILD
        EXIT
    THEN
    DUP ST-T-ARRAY = IF
        DROP
        _ST-IS-INDEX? IF
            _STDES-N @ SWAP _ST-INDEX-CHILD
        ELSE
            DROP ST-E-BAD-INDEX ST-FAIL 0
        THEN
        EXIT
    THEN
    DROP 2DROP 0 ;

VARIABLE _STN-CUR
: ST-NAVIGATE  ( path-a path-l -- node | 0 )
    ST-DOC SD.ROOT @ _STN-CUR !
    BEGIN
        DUP 0> WHILE
        _ST-SPLIT-DOT IF
            2>R
            _STN-CUR @ -ROT _ST-DESCEND
            DUP 0= IF 2R> 2DROP EXIT THEN
            _STN-CUR !
            2R>
        ELSE
            2DROP
            _STN-CUR @ -ROT _ST-DESCEND
            EXIT
        THEN
    REPEAT
    2DROP _STN-CUR @ ;

\ _ST-ENSURE-CHILD ( parent name-a name-l type -- child )
VARIABLE _STEC-P
VARIABLE _STEC-A
VARIABLE _STEC-L
VARIABLE _STEC-T
: _ST-ENSURE-CHILD  ( parent name-a name-l type -- child )
    _STEC-T !  _STEC-L !  _STEC-A !  _STEC-P !
    _STEC-P @ _STEC-A @ _STEC-L @ _ST-FIND-CHILD
    DUP 0<> IF EXIT THEN
    DROP
    _ST-ALLOC DUP 0= IF EXIT THEN
    DUP _STEC-T @ SWAP SN.TYPE !
    _STEC-A @ _STEC-L @ _ST-STR-COPY
    ST-OK? 0= IF 2DROP _ST-FREE-NODE 0 EXIT THEN
    2 PICK SN.NAMEL !
    OVER  SN.NAMEA !
    _STEC-A @ C@ 95 = IF
        DUP SN.FLAGS @ ST-F-PROTECTED OR OVER SN.FLAGS !
    THEN
    DUP _STEC-P @ _ST-APPEND-CHILD ;

VARIABLE _STEP-CUR
: ST-ENSURE-PATH  ( path-a path-l -- parent last-a last-l )
    ST-DOC SD.ROOT @ _STEP-CUR !
    BEGIN
        _ST-SPLIT-DOT IF
            2>R
            _STEP-CUR @ -ROT ST-T-OBJECT _ST-ENSURE-CHILD
            DUP 0= IF 2R> 2DROP 0 0 EXIT THEN
            _STEP-CUR !
            2R>
        ELSE
            2DROP
            _STEP-CUR @  -ROT
            EXIT
        THEN
    AGAIN ;

\ =====================================================================
\  Value API
\ =====================================================================

: ST-GET-TYPE  ( node -- type )  SN.TYPE @ ;
: ST-GET-INT   ( node -- n )    SN.VAL1 @ ;
: ST-GET-BOOL  ( node -- f )    SN.VAL1 @ ;
: ST-GET-STR   ( node -- a l )  DUP SN.VAL1 @ SWAP SN.VAL2 @ ;
: ST-GET-FLOAT ( node -- fp32 ) SN.VAL1 @ ;
: ST-NULL?     ( node -- f )    SN.TYPE @ ST-T-NULL = ;

: _ST-CLEAR-CHILDREN  ( node -- )
    DUP SN.FCHILD @
    BEGIN DUP 0<> WHILE
        DUP SN.NEXT @
        SWAP _ST-DESTROY
    REPEAT
    DROP
    0 OVER SN.FCHILD !
    0 OVER SN.LCHILD !
    0 SWAP SN.NCHILD ! ;

: ST-SET-INT  ( n node -- )
    DUP SN.TYPE @ ST-T-ARRAY >= IF DUP _ST-CLEAR-CHILDREN THEN
    ST-T-INTEGER OVER SN.TYPE !
    SN.VAL1 ! ;

: ST-SET-BOOL  ( flag node -- )
    DUP SN.TYPE @ ST-T-ARRAY >= IF DUP _ST-CLEAR-CHILDREN THEN
    ST-T-BOOLEAN OVER SN.TYPE !
    SN.VAL1 ! ;

: ST-SET-STR  ( addr len node -- )
    DUP SN.TYPE @ ST-T-ARRAY >= IF DUP _ST-CLEAR-CHILDREN THEN
    >R _ST-STR-COPY
    ST-OK? 0= IF 2DROP R> DROP EXIT THEN
    ST-T-STRING R@ SN.TYPE !
    R@ SN.VAL2 !
    R> SN.VAL1 ! ;

: ST-SET-FLOAT  ( fp32 node -- )
    DUP SN.TYPE @ ST-T-ARRAY >= IF DUP _ST-CLEAR-CHILDREN THEN
    ST-T-FLOAT OVER SN.TYPE !
    SN.VAL1 ! ;

: ST-SET-NULL  ( node -- )
    DUP SN.TYPE @ ST-T-ARRAY >= IF DUP _ST-CLEAR-CHILDREN THEN
    ST-T-NULL OVER SN.TYPE !
    0 OVER SN.VAL1 !
    0 SWAP SN.VAL2 ! ;

: ST-MAKE-OBJECT  ( node -- )
    DUP SN.TYPE @ ST-T-ARRAY >= IF DUP _ST-CLEAR-CHILDREN THEN
    ST-T-OBJECT SWAP SN.TYPE ! ;

: ST-MAKE-ARRAY  ( node -- )
    DUP SN.TYPE @ ST-T-ARRAY >= IF DUP _ST-CLEAR-CHILDREN THEN
    ST-T-ARRAY SWAP SN.TYPE ! ;

\ =====================================================================
\  Path-based mutations
\ =====================================================================

: ST-SET-PATH-INT  ( n path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-PATH
    ST-OK? 0= IF 2DROP 2DROP EXIT THEN
    ST-T-INTEGER _ST-ENSURE-CHILD
    DUP 0= IF 2DROP EXIT THEN
    ST-SET-INT ;

: ST-SET-PATH-BOOL  ( flag path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-PATH
    ST-OK? 0= IF 2DROP 2DROP EXIT THEN
    ST-T-BOOLEAN _ST-ENSURE-CHILD
    DUP 0= IF 2DROP EXIT THEN
    ST-SET-BOOL ;

: ST-SET-PATH-STR  ( str-a str-l path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-PATH
    ST-OK? 0= IF 2DROP DROP 2DROP EXIT THEN
    ST-T-STRING _ST-ENSURE-CHILD
    DUP 0= IF DROP 2DROP EXIT THEN
    ST-SET-STR ;

: ST-SET-PATH-FLOAT  ( fp32 path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-PATH
    ST-OK? 0= IF 2DROP 2DROP EXIT THEN
    ST-T-FLOAT _ST-ENSURE-CHILD
    DUP 0= IF 2DROP EXIT THEN
    ST-SET-FLOAT ;

: ST-SET-PATH-NULL  ( path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-PATH
    ST-OK? 0= IF 2DROP DROP EXIT THEN
    ST-T-NULL _ST-ENSURE-CHILD
    DUP 0= IF DROP EXIT THEN
    ST-SET-NULL ;

: ST-GET-PATH  ( path-a path-l -- node | 0 )
    ST-CLEAR-ERR
    ST-NAVIGATE
    DUP 0= IF ST-E-NOT-FOUND ST-FAIL THEN ;

: ST-DELETE-PATH  ( path-a path-l -- )
    ST-CLEAR-ERR
    ST-NAVIGATE
    DUP 0= IF DROP ST-E-NOT-FOUND ST-FAIL EXIT THEN
    DUP _ST-DETACH
    _ST-DESTROY ;

\ =====================================================================
\  Array mutations
\ =====================================================================

: ST-ENSURE-ARRAY  ( path-a path-l -- node )
    ST-CLEAR-ERR
    ST-ENSURE-PATH
    ST-OK? 0= IF 2DROP DROP 0 EXIT THEN
    ST-T-ARRAY _ST-ENSURE-CHILD
    DUP 0= IF EXIT THEN
    DUP SN.TYPE @ ST-T-ARRAY <> IF
        DUP ST-MAKE-ARRAY
    THEN ;

: ST-ARRAY-APPEND-INT  ( n path-a path-l -- )
    ST-ENSURE-ARRAY
    DUP 0= IF 2DROP EXIT THEN
    SWAP >R
    _ST-ALLOC DUP 0= IF R> DROP DROP EXIT THEN
    R> OVER ST-SET-INT
    SWAP _ST-APPEND-CHILD ;

: ST-ARRAY-APPEND-STR  ( str-a str-l path-a path-l -- )
    ST-ENSURE-ARRAY
    DUP 0= IF DROP 2DROP EXIT THEN
    >R
    _ST-ALLOC DUP 0= IF R> DROP 2DROP EXIT THEN
    DUP >R -ROT R> ST-SET-STR
    R> _ST-APPEND-CHILD ;

: ST-ARRAY-COUNT  ( path-a path-l -- n )
    ST-NAVIGATE
    DUP 0= IF EXIT THEN
    SN.NCHILD @ ;

: ST-ARRAY-NTH  ( path-a path-l n -- node | 0 )
    >R ST-NAVIGATE
    DUP 0= IF R> DROP EXIT THEN
    R> _ST-INDEX-CHILD ;

: ST-ARRAY-REMOVE  ( path-a path-l n -- )
    ST-CLEAR-ERR
    >R ST-NAVIGATE
    DUP 0= IF R> 2DROP ST-E-NOT-FOUND ST-FAIL EXIT THEN
    R> _ST-INDEX-CHILD
    DUP 0= IF DROP ST-E-BAD-INDEX ST-FAIL EXIT THEN
    DUP _ST-DETACH _ST-DESTROY ;

\ =====================================================================
\  Protected path checking
\ =====================================================================

: ST-PROTECTED?  ( path-a path-l -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DROP C@ 95 = ;

\ =====================================================================
\  Journal
\ =====================================================================

: _ST-JRNL-ENTRY-ADDR  ( idx -- addr )
    _ST-JRNL-ENTRY * ST-DOC SD.JRNL-BASE @ + ;

VARIABLE _STJ-OP
VARIABLE _STJ-PA
VARIABLE _STJ-PL
VARIABLE _STJ-OT
VARIABLE _STJ-OV
VARIABLE _STJ-NT
VARIABLE _STJ-NV
: ST-JOURNAL-ADD  ( op path-a path-l old-type old-val new-type new-val -- )
    _STJ-NV ! _STJ-NT ! _STJ-OV ! _STJ-OT !
    _STJ-PL ! _STJ-PA ! _STJ-OP !
    ST-DOC SD.JRNL-POS @ _ST-JRNL-ENTRY-ADDR
    ST-DOC SD.JRNL-SEQ @     OVER !
    ST-DOC SD.JRNL-SRC @     OVER 8 + !
    _STJ-OP @                OVER 16 + !
    _STJ-PA @                OVER 24 + !
    _STJ-PL @                OVER 32 + !
    _STJ-OT @                OVER 40 + !
    _STJ-OV @                OVER 48 + !
    _STJ-NT @                OVER 56 + !
    _STJ-NV @                SWAP 64 + !
    1 ST-DOC SD.JRNL-SEQ +!
    ST-DOC SD.JRNL-POS @ 1+  ST-DOC SD.JRNL-MAX @ MOD
    ST-DOC SD.JRNL-POS !
    ST-DOC SD.JRNL-CNT @  ST-DOC SD.JRNL-MAX @  < IF
        1 ST-DOC SD.JRNL-CNT +!
    THEN ;

: ST-JOURNAL-SEQ    ( -- n )  ST-DOC SD.JRNL-SEQ @ ;
: ST-JOURNAL-COUNT  ( -- n )  ST-DOC SD.JRNL-CNT @ ;

: ST-JOURNAL-NTH  ( n -- addr | 0 )
    DUP ST-DOC SD.JRNL-CNT @ >= IF DROP 0 EXIT THEN
    ST-DOC SD.JRNL-POS @ 1- SWAP -
    DUP 0< IF ST-DOC SD.JRNL-MAX @ + THEN
    _ST-JRNL-ENTRY-ADDR ;

\ =====================================================================
\  Gap 1.1 — ST-MERGE  (shallow object merge)
\ =====================================================================

VARIABLE _STM-SRC
VARIABLE _STM-DST
VARIABLE _STM-CH
VARIABLE _STM-NA
VARIABLE _STM-NL
VARIABLE _STM-TY

: _ST-COPY-VALUE  ( src-node dst-node -- )
    SWAP DUP SN.TYPE @ _STM-TY !
    _STM-TY @ ST-T-INTEGER = IF
        SN.VAL1 @ SWAP ST-SET-INT EXIT
    THEN
    _STM-TY @ ST-T-BOOLEAN = IF
        SN.VAL1 @ SWAP ST-SET-BOOL EXIT
    THEN
    _STM-TY @ ST-T-STRING = IF
        DUP SN.VAL1 @ SWAP SN.VAL2 @
        ROT ST-SET-STR EXIT
    THEN
    _STM-TY @ ST-T-FLOAT = IF
        SN.VAL1 @ SWAP ST-SET-FLOAT EXIT
    THEN
    _STM-TY @ ST-T-NULL = IF
        DROP ST-SET-NULL EXIT
    THEN
    \ array/object: skip (shallow merge)
    2DROP ;

: ST-MERGE  ( src-path-a src-path-l dst-path-a dst-path-l -- )
    ST-CLEAR-ERR
    2>R
    ST-NAVIGATE DUP 0= IF
        2R> 2DROP ST-E-NOT-FOUND ST-FAIL EXIT
    THEN
    DUP SN.TYPE @ ST-T-OBJECT <> IF
        DROP 2R> 2DROP ST-E-TYPE ST-FAIL EXIT
    THEN
    _STM-SRC !
    2R> ST-NAVIGATE DUP 0= IF
        DROP ST-E-NOT-FOUND ST-FAIL EXIT
    THEN
    DUP SN.TYPE @ ST-T-OBJECT <> IF
        DROP ST-E-TYPE ST-FAIL EXIT
    THEN
    _STM-DST !
    \ iterate source children
    _STM-SRC @ SN.FCHILD @
    BEGIN DUP 0<> WHILE
        _STM-CH !
        _STM-CH @ SN.NAMEA @ _STM-NA !
        _STM-CH @ SN.NAMEL @ _STM-NL !
        _STM-CH @ SN.TYPE @  _STM-TY !
        \ ensure child in dst with matching type
        _STM-DST @  _STM-NA @ _STM-NL @  _STM-TY @  _ST-ENSURE-CHILD
        DUP 0= IF DROP EXIT THEN
        \ copy value
        _STM-CH @ SWAP _ST-COPY-VALUE
        _STM-CH @ SN.NEXT @
    REPEAT DROP ;

\ =====================================================================
\  Gap 1.2 — Array insertion
\ =====================================================================

VARIABLE _STI-ARR
VARIABLE _STI-ND
VARIABLE _STI-REF

VARIABLE _STLB-N   \ new node
VARIABLE _STLB-R   \ ref node
VARIABLE _STLB-P   \ parent

: _ST-INSERT-AT  ( new-node ref-node parent -- )
    _STLB-P !  _STLB-R !  _STLB-N !
    \ set new.parent
    _STLB-P @ _STLB-N @ SN.PARENT !
    \ set new.next = ref
    _STLB-R @ _STLB-N @ SN.NEXT !
    \ set new.prev = ref.prev
    _STLB-R @ SN.PREV @ _STLB-N @ SN.PREV !
    \ if ref had a prev, prev.next = new
    _STLB-R @ SN.PREV @ ?DUP IF
        _STLB-N @ SWAP SN.NEXT !
    ELSE
        \ ref was first child: parent.fchild = new
        _STLB-N @ _STLB-P @ SN.FCHILD !
    THEN
    \ ref.prev = new
    _STLB-N @ _STLB-R @ SN.PREV !
    \ bump child count
    1 _STLB-P @ SN.NCHILD +! ;

: ST-ARRAY-INSERT-INT  ( n index path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-ARRAY
    DUP 0= IF DROP 2DROP EXIT THEN
    _STI-ARR !
    \ validate index: 0 <= idx <= count
    DUP _STI-ARR @ SN.NCHILD @ > IF
        DROP DROP ST-E-BAD-INDEX ST-FAIL EXIT
    THEN
    DUP _STI-ARR @ SN.NCHILD @ = IF
        \ index == count: append
        DROP
        _STI-ARR @ SWAP >R
        _ST-ALLOC DUP 0= IF R> DROP DROP EXIT THEN
        R> OVER ST-SET-INT
        SWAP _ST-APPEND-CHILD
        EXIT
    THEN
    \ find ref node at index
    _STI-ARR @ SWAP _ST-INDEX-CHILD
    DUP 0= IF DROP DROP ST-E-BAD-INDEX ST-FAIL EXIT THEN
    _STI-REF !
    \ alloc new node, set value
    _ST-ALLOC DUP 0= IF DROP EXIT THEN
    _STI-ND !
    _STI-ND @ ST-SET-INT
    \ insert before ref
    _STI-ND @ _STI-REF @ _STI-ARR @ _ST-INSERT-AT ;

: ST-ARRAY-INSERT-STR  ( str-a str-l index path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-ARRAY
    DUP 0= IF DROP DROP 2DROP EXIT THEN
    _STI-ARR !
    DUP _STI-ARR @ SN.NCHILD @ > IF
        DROP DROP 2DROP ST-E-BAD-INDEX ST-FAIL EXIT
    THEN
    DUP _STI-ARR @ SN.NCHILD @ = IF
        \ append
        DROP
        _STI-ARR @ >R
        _ST-ALLOC DUP 0= IF R> DROP 2DROP EXIT THEN
        DUP >R -ROT R> ST-SET-STR
        R> _ST-APPEND-CHILD
        EXIT
    THEN
    _STI-ARR @ SWAP _ST-INDEX-CHILD
    DUP 0= IF DROP 2DROP ST-E-BAD-INDEX ST-FAIL EXIT THEN
    _STI-REF !
    _ST-ALLOC DUP 0= IF 2DROP EXIT THEN
    _STI-ND !
    _STI-ND @ ST-SET-STR
    _STI-ND @ _STI-REF @ _STI-ARR @ _ST-INSERT-AT ;

\ =====================================================================
\  Gap 1.3 — Journal resize
\ =====================================================================

VARIABLE _STJR-OLD
VARIABLE _STJR-NEW
VARIABLE _STJR-I
VARIABLE _STJR-SRC
VARIABLE _STJR-DST

: ST-JRNL-SIZE!  ( new-max -- )
    DUP 1 < IF DROP EXIT THEN
    _STJR-NEW !
    ST-DOC SD.JRNL-MAX @ _STJR-OLD !
    \ allot new slab from arena
    ST-DOC SD.ARENA @
    _STJR-NEW @ _ST-JRNL-ENTRY * ARENA-ALLOT
    _STJR-DST !
    \ copy existing entries (up to min of old-cnt, new-max)
    ST-DOC SD.JRNL-CNT @  _STJR-NEW @ MIN
    _STJR-I !
    _STJR-I @ 0 ?DO
        I ST-JOURNAL-NTH DUP 0<> IF
            _STJR-DST @ I _ST-JRNL-ENTRY * +
            _ST-JRNL-ENTRY CMOVE
        ELSE
            DROP
        THEN
    LOOP
    \ update descriptor
    _STJR-DST @  ST-DOC SD.JRNL-BASE !
    _STJR-NEW @  ST-DOC SD.JRNL-MAX !
    _STJR-I @    ST-DOC SD.JRNL-CNT !
    _STJR-I @    ST-DOC SD.JRNL-POS !  ;

\ =====================================================================
\  Gap 1.4 — Schema validation
\ =====================================================================
\
\  Schemas are stored under the _schema path prefix using the normal
\  state-tree path setters.  For example, to constrain user.age:
\
\    S" integer" S" _schema.user.age.type" ST-SET-PATH-STR
\    0           S" _schema.user.age.min"  ST-SET-PATH-INT
\    150         S" _schema.user.age.max"  ST-SET-PATH-INT
\
\  ST-VALIDATE checks these constraints.

8 CONSTANT ST-E-SCHEMA     \ schema validation error

CREATE _STV-BUF 256 ALLOT    \ path construction buffer
VARIABLE _STV-LEN

: _STV-RESET  0 _STV-LEN ! ;

: _STV-APPEND  ( addr len -- )
    DUP _STV-LEN @ + 255 > IF 2DROP EXIT THEN
    _STV-BUF _STV-LEN @ + SWAP CMOVE
    _STV-LEN +! ;

: _STV-PATH  ( -- addr len )  _STV-BUF _STV-LEN @ ;

: _ST-SCHEMA-PATH  ( path-a path-l suffix-a suffix-l -- addr len )
    2>R 2>R
    _STV-RESET
    S" _schema." _STV-APPEND
    2R> _STV-APPEND
    S" ." _STV-APPEND
    2R> _STV-APPEND
    _STV-PATH ;

VARIABLE _STV-NODE
VARIABLE _STV-ERR

: ST-VALIDATE  ( path-a path-l -- flag )
    ST-CLEAR-ERR
    0 _STV-ERR !
    2DUP ST-NAVIGATE DUP 0= IF
        DROP 2DROP ST-E-NOT-FOUND ST-FAIL 0 EXIT
    THEN
    _STV-NODE !
    \ Check type constraint
    2DUP S" type" _ST-SCHEMA-PATH
    ST-NAVIGATE DUP 0<> IF
        \ schema node has type string, compare with actual
        DUP SN.TYPE @ ST-T-STRING = IF
            ST-GET-STR                   ( path-a path-l schema-str-a schema-str-l )
            _STV-NODE @ SN.TYPE @
            DUP ST-T-INTEGER = IF DROP S" integer" ELSE
            DUP ST-T-STRING  = IF DROP S" string"  ELSE
            DUP ST-T-BOOLEAN = IF DROP S" boolean" ELSE
            DUP ST-T-FLOAT   = IF DROP S" float"   ELSE
            DUP ST-T-NULL    = IF DROP S" null"    ELSE
            DUP ST-T-ARRAY   = IF DROP S" array"   ELSE
            DUP ST-T-OBJECT  = IF DROP S" object"  ELSE
                DROP S" unknown"
            THEN THEN THEN THEN THEN THEN THEN
            STR-STR= 0= IF 1 _STV-ERR ! THEN
        ELSE DROP THEN
    ELSE DROP THEN
    \ Check min constraint (integer/float)
    2DUP S" min" _ST-SCHEMA-PATH
    ST-NAVIGATE DUP 0<> IF
        _STV-NODE @ SN.TYPE @ ST-T-INTEGER = IF
            ST-GET-INT _STV-NODE @ ST-GET-INT
            < IF 1 _STV-ERR ! THEN
        ELSE DROP THEN
    ELSE DROP THEN
    \ Check max constraint
    2DUP S" max" _ST-SCHEMA-PATH
    ST-NAVIGATE DUP 0<> IF
        _STV-NODE @ SN.TYPE @ ST-T-INTEGER = IF
            ST-GET-INT _STV-NODE @ ST-GET-INT
            > IF 1 _STV-ERR ! THEN
        ELSE DROP THEN
    ELSE DROP THEN
    \ Check min-length (string)
    2DUP S" min-length" _ST-SCHEMA-PATH
    ST-NAVIGATE DUP 0<> IF
        _STV-NODE @ SN.TYPE @ ST-T-STRING = IF
            ST-GET-INT _STV-NODE @ SN.VAL2 @
            > IF 1 _STV-ERR ! THEN
        ELSE DROP THEN
    ELSE DROP THEN
    \ Check max-length (string)
    2DUP S" max-length" _ST-SCHEMA-PATH
    ST-NAVIGATE DUP 0<> IF
        _STV-NODE @ SN.TYPE @ ST-T-STRING = IF
            ST-GET-INT _STV-NODE @ SN.VAL2 @
            < IF 1 _STV-ERR ! THEN
        ELSE DROP THEN
    ELSE DROP THEN
    \ Check read-only flag
    2DUP S" read-only" _ST-SCHEMA-PATH
    ST-NAVIGATE DUP 0<> IF
        ST-GET-INT 0<> IF
            _STV-NODE @ SN.FLAGS @ ST-F-READONLY OR
            _STV-NODE @ SN.FLAGS !
        THEN
    ELSE DROP THEN
    2DROP
    _STV-ERR @ 0= IF 1 ELSE ST-E-SCHEMA ST-FAIL 0 THEN ;

\ =====================================================================
\  Gap 1.5 — Snapshot / Restore
\ =====================================================================
\
\  Snapshots copy the full arena region into XMEM.
\  Uses ARENA-ALLOT on a separate temp arena.

CREATE _ST-SNAP-BUF 65536 ALLOT
VARIABLE _ST-SNAP-LEN

: ST-SNAPSHOT  ( -- snap-addr snap-len )
    \ Calculate used region: from arena base to str-ptr
    ST-DOC SD.ARENA @ A.BASE @    ( base )
    ST-DOC SD.STR-PTR @           ( base str-ptr )
    OVER -                        ( base len )
    DUP _ST-SNAP-LEN !
    DUP 65536 > ABORT" snapshot too large"
    \ Copy arena region into static buffer
    >R  _ST-SNAP-BUF R@ CMOVE    ( ; src=base dst=buf len=R )
    R>
    _ST-SNAP-BUF SWAP ;

: ST-RESTORE  ( snap-addr snap-len -- )
    >R                             ( snap-a ; R: len )
    ST-DOC SD.ARENA @ A.BASE @    ( snap-a base )
    R@ CMOVE                      ( )
    \ Adjust str-ptr
    ST-DOC SD.ARENA @ A.BASE @  R> +
    ST-DOC SD.STR-PTR ! ;

\ =====================================================================
\  Gap 1.6 — Computed value stubs
\ =====================================================================

4 CONSTANT ST-F-COMPUTED    \ node has a computed expression

VARIABLE _ST-COMPUTE-XT
' NOOP _ST-COMPUTE-XT !

: ST-COMPUTED?  ( node -- flag )
    SN.FLAGS @ ST-F-COMPUTED AND 0<> ;

: ST-COMPUTED!  ( expr-a expr-l path-a path-l -- )
    ST-CLEAR-ERR
    ST-ENSURE-PATH
    ST-OK? 0= IF 2DROP 2DROP EXIT THEN
    ST-T-STRING _ST-ENSURE-CHILD
    DUP 0= IF 2DROP EXIT THEN
    DUP >R ST-SET-STR
    R@ SN.FLAGS @ ST-F-COMPUTED OR R> SN.FLAGS ! ;

\ =====================================================================
\  Gap 1.7 — Subscriptions
\ =====================================================================

64 CONSTANT _ST-SUB-MAX
CREATE _ST-SUB-TABLE  _ST-SUB-MAX 24 * ALLOT
VARIABLE _ST-SUB-CNT
0 _ST-SUB-CNT !

\ Each entry: 24 bytes = 3 cells
\   +0  path-hash (FNV-1a)
\   +8  xt (execution token)
\   +16 active flag (0 or 1)

: _ST-SUB-ENTRY  ( idx -- addr )  24 * _ST-SUB-TABLE + ;

: _ST-FNV1A  ( addr len -- hash )
    2166136261 -ROT     ( hash addr len )
    0 ?DO               ( hash addr )
        OVER I + C@     ( hash addr byte )
        ROT XOR         ( addr hash' )
        16777619 *      ( addr hash'' )
        SWAP            ( hash addr )
    LOOP
    DROP ;

: ST-SUBSCRIBE  ( path-a path-l xt -- sub-id )
    >R
    _ST-FNV1A          ( hash ; R: xt )
    _ST-SUB-CNT @ _ST-SUB-MAX >= IF
        DROP R> DROP -1 EXIT
    THEN
    _ST-SUB-CNT @ _ST-SUB-ENTRY
    OVER SWAP !                 ( hash ; entry.hash = hash )
    _ST-SUB-CNT @ _ST-SUB-ENTRY 8 +
    R> SWAP !                   ( ; entry.xt = xt )
    _ST-SUB-CNT @ _ST-SUB-ENTRY 16 +
    1 SWAP !                    ( ; entry.active = 1 )
    _ST-SUB-CNT @
    1 _ST-SUB-CNT +!  ;

: ST-UNSUBSCRIBE  ( sub-id -- )
    DUP 0< IF DROP EXIT THEN
    DUP _ST-SUB-CNT @ >= IF DROP EXIT THEN
    _ST-SUB-ENTRY 16 + 0 SWAP ! ;

: _ST-NOTIFY  ( path-a path-l -- )
    2DUP _ST-FNV1A          ( path-a path-l hash )
    _ST-SUB-CNT @ 0 ?DO
        I _ST-SUB-ENTRY     ( path-a path-l hash entry )
        DUP 16 + @ 0<> IF   ( active? )
            DUP @ 3 PICK = IF  ( hash matches? )
                8 + @ EXECUTE
            ELSE DROP THEN
        ELSE DROP THEN
    LOOP
    DROP 2DROP ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _ltree-guard

' SN.TYPE         CONSTANT _sn-dottype-xt
' SN.FLAGS        CONSTANT _sn-dotflags-xt
' SN.PARENT       CONSTANT _sn-dotparent-xt
' SN.NEXT         CONSTANT _sn-dotnext-xt
' SN.PREV         CONSTANT _sn-dotprev-xt
' SN.FCHILD       CONSTANT _sn-dotfchild-xt
' SN.LCHILD       CONSTANT _sn-dotlchild-xt
' SN.NCHILD       CONSTANT _sn-dotnchild-xt
' SN.NAMEA        CONSTANT _sn-dotnamea-xt
' SN.NAMEL        CONSTANT _sn-dotnamel-xt
' SN.VAL1         CONSTANT _sn-dotval1-xt
' SN.VAL2         CONSTANT _sn-dotval2-xt
' SD.ARENA        CONSTANT _sd-dotarena-xt
' SD.NODE-BASE    CONSTANT _sd-dotnode-base-xt
' SD.NODE-MAX     CONSTANT _sd-dotnode-max-xt
' SD.NODE-FREE    CONSTANT _sd-dotnode-free-xt
' SD.NODE-USED    CONSTANT _sd-dotnode-used-xt
' SD.STR-BASE     CONSTANT _sd-dotstr-base-xt
' SD.STR-PTR      CONSTANT _sd-dotstr-ptr-xt
' SD.STR-END      CONSTANT _sd-dotstr-end-xt
' SD.ROOT         CONSTANT _sd-dotroot-xt
' SD.JRNL-BASE    CONSTANT _sd-dotjrnl-base-xt
' SD.JRNL-MAX     CONSTANT _sd-dotjrnl-max-xt
' SD.JRNL-POS     CONSTANT _sd-dotjrnl-pos-xt
' SD.JRNL-SEQ     CONSTANT _sd-dotjrnl-seq-xt
' SD.JRNL-CNT     CONSTANT _sd-dotjrnl-cnt-xt
' SD.JRNL-SRC     CONSTANT _sd-dotjrnl-src-xt
' SD.ERR          CONSTANT _sd-doterr-xt
' ST-USE          CONSTANT _st-use-xt
' ST-DOC          CONSTANT _st-doc-xt
' ST-ERR          CONSTANT _st-err-xt
' ST-FAIL         CONSTANT _st-fail-xt
' ST-OK?          CONSTANT _st-ok-q-xt
' ST-CLEAR-ERR    CONSTANT _st-clear-err-xt
' ST-DOC-NEW      CONSTANT _st-doc-new-xt
' ST-ROOT         CONSTANT _st-root-xt
' ST-NODE-COUNT   CONSTANT _st-node-count-xt
' ST-NAVIGATE     CONSTANT _st-navigate-xt
' ST-ENSURE-PATH  CONSTANT _st-ensure-path-xt
' ST-GET-TYPE     CONSTANT _st-get-type-xt
' ST-GET-INT      CONSTANT _st-get-int-xt
' ST-GET-BOOL     CONSTANT _st-get-bool-xt
' ST-GET-STR      CONSTANT _st-get-str-xt
' ST-GET-FLOAT    CONSTANT _st-get-float-xt
' ST-NULL?        CONSTANT _st-null-q-xt
' ST-SET-INT      CONSTANT _st-set-int-xt
' ST-SET-BOOL     CONSTANT _st-set-bool-xt
' ST-SET-STR      CONSTANT _st-set-str-xt
' ST-SET-FLOAT    CONSTANT _st-set-float-xt
' ST-SET-NULL     CONSTANT _st-set-null-xt
' ST-MAKE-OBJECT  CONSTANT _st-make-object-xt
' ST-MAKE-ARRAY   CONSTANT _st-make-array-xt
' ST-SET-PATH-INT CONSTANT _st-set-path-int-xt
' ST-SET-PATH-BOOL CONSTANT _st-set-path-bool-xt
' ST-SET-PATH-STR CONSTANT _st-set-path-str-xt
' ST-SET-PATH-FLOAT CONSTANT _st-set-path-float-xt
' ST-SET-PATH-NULL CONSTANT _st-set-path-null-xt
' ST-GET-PATH     CONSTANT _st-get-path-xt
' ST-DELETE-PATH  CONSTANT _st-delete-path-xt
' ST-ENSURE-ARRAY CONSTANT _st-ensure-array-xt
' ST-ARRAY-APPEND-INT CONSTANT _st-array-append-int-xt
' ST-ARRAY-APPEND-STR CONSTANT _st-array-append-str-xt
' ST-ARRAY-COUNT  CONSTANT _st-array-count-xt
' ST-ARRAY-NTH    CONSTANT _st-array-nth-xt
' ST-ARRAY-REMOVE CONSTANT _st-array-remove-xt
' ST-PROTECTED?   CONSTANT _st-protected-q-xt
' ST-JOURNAL-ADD  CONSTANT _st-journal-add-xt
' ST-JOURNAL-SEQ  CONSTANT _st-journal-seq-xt
' ST-JOURNAL-COUNT CONSTANT _st-journal-count-xt
' ST-JOURNAL-NTH  CONSTANT _st-journal-nth-xt
' ST-MERGE        CONSTANT _st-merge-xt
' ST-ARRAY-INSERT-INT CONSTANT _st-array-insert-int-xt
' ST-ARRAY-INSERT-STR CONSTANT _st-array-insert-str-xt
' ST-JRNL-SIZE!   CONSTANT _st-jrnl-size-s-xt
' ST-VALIDATE     CONSTANT _st-validate-xt
' ST-SNAPSHOT     CONSTANT _st-snapshot-xt
' ST-RESTORE      CONSTANT _st-restore-xt
' ST-COMPUTED?    CONSTANT _st-computed-q-xt
' ST-COMPUTED!    CONSTANT _st-computed-s-xt
' ST-SUBSCRIBE    CONSTANT _st-subscribe-xt
' ST-UNSUBSCRIBE  CONSTANT _st-unsubscribe-xt

: SN.TYPE         _sn-dottype-xt _ltree-guard WITH-GUARD ;
: SN.FLAGS        _sn-dotflags-xt _ltree-guard WITH-GUARD ;
: SN.PARENT       _sn-dotparent-xt _ltree-guard WITH-GUARD ;
: SN.NEXT         _sn-dotnext-xt _ltree-guard WITH-GUARD ;
: SN.PREV         _sn-dotprev-xt _ltree-guard WITH-GUARD ;
: SN.FCHILD       _sn-dotfchild-xt _ltree-guard WITH-GUARD ;
: SN.LCHILD       _sn-dotlchild-xt _ltree-guard WITH-GUARD ;
: SN.NCHILD       _sn-dotnchild-xt _ltree-guard WITH-GUARD ;
: SN.NAMEA        _sn-dotnamea-xt _ltree-guard WITH-GUARD ;
: SN.NAMEL        _sn-dotnamel-xt _ltree-guard WITH-GUARD ;
: SN.VAL1         _sn-dotval1-xt _ltree-guard WITH-GUARD ;
: SN.VAL2         _sn-dotval2-xt _ltree-guard WITH-GUARD ;
: SD.ARENA        _sd-dotarena-xt _ltree-guard WITH-GUARD ;
: SD.NODE-BASE    _sd-dotnode-base-xt _ltree-guard WITH-GUARD ;
: SD.NODE-MAX     _sd-dotnode-max-xt _ltree-guard WITH-GUARD ;
: SD.NODE-FREE    _sd-dotnode-free-xt _ltree-guard WITH-GUARD ;
: SD.NODE-USED    _sd-dotnode-used-xt _ltree-guard WITH-GUARD ;
: SD.STR-BASE     _sd-dotstr-base-xt _ltree-guard WITH-GUARD ;
: SD.STR-PTR      _sd-dotstr-ptr-xt _ltree-guard WITH-GUARD ;
: SD.STR-END      _sd-dotstr-end-xt _ltree-guard WITH-GUARD ;
: SD.ROOT         _sd-dotroot-xt _ltree-guard WITH-GUARD ;
: SD.JRNL-BASE    _sd-dotjrnl-base-xt _ltree-guard WITH-GUARD ;
: SD.JRNL-MAX     _sd-dotjrnl-max-xt _ltree-guard WITH-GUARD ;
: SD.JRNL-POS     _sd-dotjrnl-pos-xt _ltree-guard WITH-GUARD ;
: SD.JRNL-SEQ     _sd-dotjrnl-seq-xt _ltree-guard WITH-GUARD ;
: SD.JRNL-CNT     _sd-dotjrnl-cnt-xt _ltree-guard WITH-GUARD ;
: SD.JRNL-SRC     _sd-dotjrnl-src-xt _ltree-guard WITH-GUARD ;
: SD.ERR          _sd-doterr-xt _ltree-guard WITH-GUARD ;
: ST-USE          _st-use-xt _ltree-guard WITH-GUARD ;
: ST-DOC          _st-doc-xt _ltree-guard WITH-GUARD ;
: ST-ERR          _st-err-xt _ltree-guard WITH-GUARD ;
: ST-FAIL         _st-fail-xt _ltree-guard WITH-GUARD ;
: ST-OK?          _st-ok-q-xt _ltree-guard WITH-GUARD ;
: ST-CLEAR-ERR    _st-clear-err-xt _ltree-guard WITH-GUARD ;
: ST-DOC-NEW      _st-doc-new-xt _ltree-guard WITH-GUARD ;
: ST-ROOT         _st-root-xt _ltree-guard WITH-GUARD ;
: ST-NODE-COUNT   _st-node-count-xt _ltree-guard WITH-GUARD ;
: ST-NAVIGATE     _st-navigate-xt _ltree-guard WITH-GUARD ;
: ST-ENSURE-PATH  _st-ensure-path-xt _ltree-guard WITH-GUARD ;
: ST-GET-TYPE     _st-get-type-xt _ltree-guard WITH-GUARD ;
: ST-GET-INT      _st-get-int-xt _ltree-guard WITH-GUARD ;
: ST-GET-BOOL     _st-get-bool-xt _ltree-guard WITH-GUARD ;
: ST-GET-STR      _st-get-str-xt _ltree-guard WITH-GUARD ;
: ST-GET-FLOAT    _st-get-float-xt _ltree-guard WITH-GUARD ;
: ST-NULL?        _st-null-q-xt _ltree-guard WITH-GUARD ;
: ST-SET-INT      _st-set-int-xt _ltree-guard WITH-GUARD ;
: ST-SET-BOOL     _st-set-bool-xt _ltree-guard WITH-GUARD ;
: ST-SET-STR      _st-set-str-xt _ltree-guard WITH-GUARD ;
: ST-SET-FLOAT    _st-set-float-xt _ltree-guard WITH-GUARD ;
: ST-SET-NULL     _st-set-null-xt _ltree-guard WITH-GUARD ;
: ST-MAKE-OBJECT  _st-make-object-xt _ltree-guard WITH-GUARD ;
: ST-MAKE-ARRAY   _st-make-array-xt _ltree-guard WITH-GUARD ;
: ST-SET-PATH-INT _st-set-path-int-xt _ltree-guard WITH-GUARD ;
: ST-SET-PATH-BOOL _st-set-path-bool-xt _ltree-guard WITH-GUARD ;
: ST-SET-PATH-STR _st-set-path-str-xt _ltree-guard WITH-GUARD ;
: ST-SET-PATH-FLOAT _st-set-path-float-xt _ltree-guard WITH-GUARD ;
: ST-SET-PATH-NULL _st-set-path-null-xt _ltree-guard WITH-GUARD ;
: ST-GET-PATH     _st-get-path-xt _ltree-guard WITH-GUARD ;
: ST-DELETE-PATH  _st-delete-path-xt _ltree-guard WITH-GUARD ;
: ST-ENSURE-ARRAY _st-ensure-array-xt _ltree-guard WITH-GUARD ;
: ST-ARRAY-APPEND-INT _st-array-append-int-xt _ltree-guard WITH-GUARD ;
: ST-ARRAY-APPEND-STR _st-array-append-str-xt _ltree-guard WITH-GUARD ;
: ST-ARRAY-COUNT  _st-array-count-xt _ltree-guard WITH-GUARD ;
: ST-ARRAY-NTH    _st-array-nth-xt _ltree-guard WITH-GUARD ;
: ST-ARRAY-REMOVE _st-array-remove-xt _ltree-guard WITH-GUARD ;
: ST-PROTECTED?   _st-protected-q-xt _ltree-guard WITH-GUARD ;
: ST-JOURNAL-ADD  _st-journal-add-xt _ltree-guard WITH-GUARD ;
: ST-JOURNAL-SEQ  _st-journal-seq-xt _ltree-guard WITH-GUARD ;
: ST-JOURNAL-COUNT _st-journal-count-xt _ltree-guard WITH-GUARD ;
: ST-JOURNAL-NTH  _st-journal-nth-xt _ltree-guard WITH-GUARD ;
: ST-MERGE        _st-merge-xt _ltree-guard WITH-GUARD ;
: ST-ARRAY-INSERT-INT _st-array-insert-int-xt _ltree-guard WITH-GUARD ;
: ST-ARRAY-INSERT-STR _st-array-insert-str-xt _ltree-guard WITH-GUARD ;
: ST-JRNL-SIZE!   _st-jrnl-size-s-xt _ltree-guard WITH-GUARD ;
: ST-VALIDATE     _st-validate-xt _ltree-guard WITH-GUARD ;
: ST-SNAPSHOT     _st-snapshot-xt _ltree-guard WITH-GUARD ;
: ST-RESTORE      _st-restore-xt _ltree-guard WITH-GUARD ;
: ST-COMPUTED?    _st-computed-q-xt _ltree-guard WITH-GUARD ;
: ST-COMPUTED!    _st-computed-s-xt _ltree-guard WITH-GUARD ;
: ST-SUBSCRIBE    _st-subscribe-xt _ltree-guard WITH-GUARD ;
: ST-UNSUBSCRIBE  _st-unsubscribe-xt _ltree-guard WITH-GUARD ;
[THEN] [THEN]
