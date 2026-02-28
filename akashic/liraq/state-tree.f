\ state-tree.f — LIRAQ State Tree (Layer 1)
\
\ Hierarchical key-value store, path-addressed with dot-separated
\ paths.  Implements LIRAQ v1.0 spec §03.
\
\ Value types: String, Integer, Boolean, Null, Array, Object.
\ (Float deferred — no FPU on Megapad-64.)
\
\ Prefix: ST-   (public API)
\         _ST-  (internal helpers)

REQUIRE ../utils/string.f

PROVIDED akashic-state-tree

\ =====================================================================
\  Type tags
\ =====================================================================

0 CONSTANT ST-T-FREE
1 CONSTANT ST-T-STRING
2 CONSTANT ST-T-INTEGER
3 CONSTANT ST-T-BOOLEAN
4 CONSTANT ST-T-NULL
5 CONSTANT ST-T-ARRAY
6 CONSTANT ST-T-OBJECT

\ =====================================================================
\  Flag bits
\ =====================================================================

1 CONSTANT ST-F-PROTECTED    \ path starts with _
2 CONSTANT ST-F-READONLY     \ DCS may not mutate

\ =====================================================================
\  Error codes
\ =====================================================================

VARIABLE ST-ERR
0 ST-ERR !

: ST-FAIL  ( code -- )  ST-ERR ! ;
: ST-OK?   ( -- flag )  ST-ERR @ 0= ;
: ST-CLEAR-ERR  ( -- )  0 ST-ERR ! ;

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
\  Pool sizes
\ =====================================================================

256 CONSTANT _ST-MAXNODES
8192 CONSTANT _ST-SPOOL-SZ
128 CONSTANT _ST-JRNL-MAX
72 CONSTANT _ST-JRNL-ENTRY

\ =====================================================================
\  Node pool — flag byte + 96 bytes per slot
\ =====================================================================

_ST-NODESZ 1+ CONSTANT _ST-STRIDE     \ 97

CREATE _ST-POOL  _ST-MAXNODES _ST-STRIDE * ALLOT
VARIABLE _ST-NUSED

: _ST-POOL-ZERO  ( -- )
    _ST-POOL _ST-MAXNODES _ST-STRIDE * 0 DO
        0 OVER I + C!
    LOOP DROP
    0 _ST-NUSED ! ;

: _ST-FLAG  ( idx -- addr )
    _ST-STRIDE * _ST-POOL + ;

: _ST-DATA  ( idx -- addr )
    _ST-FLAG 1+ ;

: _ST-ALLOC  ( -- node | 0 )
    _ST-MAXNODES 0 DO
        I _ST-FLAG C@ 0= IF
            1 I _ST-FLAG C!
            I _ST-DATA
            DUP _ST-NODESZ 0 DO
                0 OVER I + C!
            LOOP DROP
            1 _ST-NUSED +!
            UNLOOP EXIT
        THEN
    LOOP
    ST-E-FULL ST-FAIL 0 ;

: _ST-FREE-NODE  ( node -- )
    1-  0 OVER C!  DROP
    -1 _ST-NUSED +! ;

\ =====================================================================
\  String pool — bump allocator
\ =====================================================================

CREATE _ST-SPOOL  _ST-SPOOL-SZ ALLOT
VARIABLE _ST-SPOS

: _ST-SPOOL-ZERO  ( -- )  0 _ST-SPOS ! ;

\ _ST-STR-COPY ( src len -- addr len )
\   Copy string into pool.  Returns pool address and length.
VARIABLE _STC-L
VARIABLE _STC-D
: _ST-STR-COPY  ( src len -- addr len )
    DUP _STC-L !
    _ST-SPOS @ OVER + _ST-SPOOL-SZ > IF
        2DROP ST-E-POOL-FULL ST-FAIL 0 0 EXIT
    THEN
    _ST-SPOOL _ST-SPOS @ +  _STC-D !
    DROP                               \ drop len, keep src
    _STC-L @ 0 ?DO
        DUP I + C@  _STC-D @ I + C!
    LOOP
    DROP                               \ drop src
    _STC-L @ _ST-SPOS +!
    _STC-D @ _STC-L @ ;

\ =====================================================================
\  Root node
\ =====================================================================

VARIABLE _ST-ROOT

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
\   Descend one level.  Rewritten without CASE for stack clarity.
VARIABLE _STDES-N
: _ST-DESCEND  ( node seg-a seg-l -- child | 0 )
    ROT _STDES-N !                      \ save node; stack: ( seg-a seg-l )
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
    _ST-ROOT @ _STN-CUR !
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
    _ST-ROOT @ _STEP-CUR !
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

CREATE _ST-JRNL  _ST-JRNL-MAX _ST-JRNL-ENTRY * ALLOT
VARIABLE _ST-JPOS
VARIABLE _ST-JSEQ
VARIABLE _ST-JCNT
VARIABLE _ST-JSRC

0 CONSTANT ST-SRC-DCS
1 CONSTANT ST-SRC-BINDING
2 CONSTANT ST-SRC-BEHAVIOR
3 CONSTANT ST-SRC-RUNTIME

: _ST-JRNL-ENTRY-ADDR  ( idx -- addr )
    _ST-JRNL-ENTRY * _ST-JRNL + ;

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
    _ST-JPOS @ _ST-JRNL-ENTRY-ADDR
    _ST-JSEQ @     OVER !
    _ST-JSRC @     OVER 8 + !
    _STJ-OP @      OVER 16 + !
    _STJ-PA @      OVER 24 + !
    _STJ-PL @      OVER 32 + !
    _STJ-OT @      OVER 40 + !
    _STJ-OV @      OVER 48 + !
    _STJ-NT @      OVER 56 + !
    _STJ-NV @      SWAP 64 + !
    1 _ST-JSEQ +!
    _ST-JPOS @ 1+ _ST-JRNL-MAX MOD _ST-JPOS !
    _ST-JCNT @ _ST-JRNL-MAX < IF 1 _ST-JCNT +! THEN ;

: ST-JOURNAL-SEQ  ( -- n )  _ST-JSEQ @ ;
: ST-JOURNAL-COUNT  ( -- n )  _ST-JCNT @ ;

: ST-JOURNAL-NTH  ( n -- addr | 0 )
    DUP _ST-JCNT @ >= IF DROP 0 EXIT THEN
    _ST-JPOS @ 1- SWAP -
    DUP 0< IF _ST-JRNL-MAX + THEN
    _ST-JRNL-ENTRY-ADDR ;

\ =====================================================================
\  Initialization
\ =====================================================================

: ST-INIT  ( -- )
    _ST-POOL-ZERO
    _ST-SPOOL-ZERO
    0 _ST-JPOS !
    0 _ST-JSEQ !
    0 _ST-JCNT !
    ST-SRC-DCS _ST-JSRC !
    ST-CLEAR-ERR
    _ST-ALLOC  DUP 0= IF DROP EXIT THEN
    ST-T-OBJECT OVER SN.TYPE !
    _ST-ROOT ! ;

: ST-ROOT  ( -- node )  _ST-ROOT @ ;
: ST-NODE-COUNT  ( -- n )  _ST-NUSED @ ;
