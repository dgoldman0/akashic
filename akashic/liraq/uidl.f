\ uidl.f — LIRAQ UIDL Document Model (Layer 3, Spec §02)
\
\ Parses UIDL XML documents into a static-pool semantic element tree.
\ 16 element types + 4 pseudo-types, 6 arrangement modes, ID hash
\ table for O(1) lookup, per-element attribute linked lists.
\
\ Public API:
\   UIDL-PARSE         ( xml-a xml-l -- flag )
\   UIDL-RESET         ( -- )
\   UIDL-ROOT          ( -- elem | 0 )
\   UIDL-BY-ID         ( id-a id-l -- elem | 0 )
\   UIDL-ELEM-COUNT    ( -- n )
\   UIDL-ERR           ( -- code )
\
\   UIDL-TYPE          ( elem -- type )
\   UIDL-ID            ( elem -- a l )
\   UIDL-ROLE          ( elem -- a l )
\   UIDL-ARRANGE       ( elem -- mode )
\   UIDL-BIND          ( elem -- a l flag )
\   UIDL-WHEN          ( elem -- a l flag )
\   UIDL-FLAGS         ( elem -- flags )
\
\   UIDL-PARENT        ( elem -- p | 0 )
\   UIDL-FIRST-CHILD   ( elem -- c | 0 )
\   UIDL-LAST-CHILD    ( elem -- c | 0 )
\   UIDL-NEXT-SIB      ( elem -- s | 0 )
\   UIDL-PREV-SIB      ( elem -- s | 0 )
\   UIDL-NCHILDREN     ( elem -- n )
\
\   UIDL-ATTR          ( elem na nl -- va vl flag )
\   UIDL-ATTR-FIRST    ( elem -- attr | 0 )
\   UIDL-ATTR-NEXT     ( attr -- next | 0 )
\   UIDL-ATTR-NAME     ( attr -- a l )
\   UIDL-ATTR-VAL      ( attr -- a l )
\
\   UIDL-EVAL-WHEN     ( elem -- flag )
\   UIDL-BIND-EVAL     ( elem -- type v1 v2 )
\   UIDL-TYPE-NAME     ( type -- a l )
\
\   UIDL-TEMPLATE      ( coll-elem -- template | 0 )
\   UIDL-EMPTY-CHILD   ( coll-elem -- empty | 0 )
\   UIDL-REP-BY-MOD    ( media mod-a mod-l -- rep | 0 )
\   UIDL-REP-COUNT     ( media -- n )
\
\ Prefix: UIDL-  (public)   _UDL-  (internal)
\
\ Load with:   REQUIRE uidl.f

REQUIRE ../markup/core.f
REQUIRE ../markup/xml.f
REQUIRE ../utils/string.f
REQUIRE lel.f
REQUIRE state-tree.f

PROVIDED akashic-uidl

\ =====================================================================
\  Element Type Constants (1-16 semantic, 17-20 pseudo)
\ =====================================================================

0  CONSTANT UIDL-T-NONE
1  CONSTANT UIDL-T-REGION
2  CONSTANT UIDL-T-GROUP
3  CONSTANT UIDL-T-SEPARATOR
4  CONSTANT UIDL-T-META
5  CONSTANT UIDL-T-LABEL
6  CONSTANT UIDL-T-MEDIA
7  CONSTANT UIDL-T-SYMBOL
8  CONSTANT UIDL-T-CANVAS
9  CONSTANT UIDL-T-ACTION
10 CONSTANT UIDL-T-INPUT
11 CONSTANT UIDL-T-SELECTOR
12 CONSTANT UIDL-T-TOGGLE
13 CONSTANT UIDL-T-RANGE
14 CONSTANT UIDL-T-COLLECTION
15 CONSTANT UIDL-T-TABLE
16 CONSTANT UIDL-T-INDICATOR

17 CONSTANT UIDL-T-UIDL
18 CONSTANT UIDL-T-TEMPLATE
19 CONSTANT UIDL-T-EMPTY
20 CONSTANT UIDL-T-REP

\ =====================================================================
\  Arrangement Modes
\ =====================================================================

0 CONSTANT UIDL-A-NONE
1 CONSTANT UIDL-A-DOCK
2 CONSTANT UIDL-A-FLEX
3 CONSTANT UIDL-A-STACK
4 CONSTANT UIDL-A-FLOW
5 CONSTANT UIDL-A-GRID

\ =====================================================================
\  Element Flags
\ =====================================================================

1 CONSTANT UIDL-F-SELFCLOSE
2 CONSTANT UIDL-F-TWOWAY

\ =====================================================================
\  Error Codes
\ =====================================================================

0 CONSTANT UIDL-E-OK
1 CONSTANT UIDL-E-NO-ROOT
2 CONSTANT UIDL-E-DUP-ID
3 CONSTANT UIDL-E-BAD-TAG
4 CONSTANT UIDL-E-FULL
5 CONSTANT UIDL-E-STR-FULL
6 CONSTANT UIDL-E-ATTR-FULL

VARIABLE _UDL-ERR
: UIDL-ERR  ( -- code )  _UDL-ERR @ ;

\ =====================================================================
\  Pool Sizes & Layout
\ =====================================================================

256   CONSTANT _UDL-MAX-ELEMS
512   CONSTANT _UDL-MAX-ATTRS
12288 CONSTANT _UDL-STR-SZ
256   CONSTANT _UDL-HASH-SZ

\ Element node — 128 bytes (16 cells)
128 CONSTANT _UDL-ELEMSZ
: UE.TYPE    ( e -- a )  ;
: UE.FLAGS   ( e -- a )  8 + ;
: UE.PARENT  ( e -- a )  16 + ;
: UE.NEXT    ( e -- a )  24 + ;
: UE.PREV    ( e -- a )  32 + ;
: UE.FCHILD  ( e -- a )  40 + ;
: UE.LCHILD  ( e -- a )  48 + ;
: UE.NCHILD  ( e -- a )  56 + ;
: UE.ID-A    ( e -- a )  64 + ;
: UE.ID-L    ( e -- a )  72 + ;
: UE.ROLE-A  ( e -- a )  80 + ;
: UE.ROLE-L  ( e -- a )  88 + ;
: UE.ARRANGE ( e -- a )  96 + ;
: UE.ATTR    ( e -- a )  104 + ;
: UE.BIND-A  ( e -- a )  112 + ;
: UE.BIND-L  ( e -- a )  120 + ;

\ Attribute node — 40 bytes (5 cells)
40 CONSTANT _UDL-ATTRSZ
: UA.NEXT    ( a -- a )  ;
: UA.NAME-A  ( a -- a )  8 + ;
: UA.NAME-L  ( a -- a )  16 + ;
: UA.VAL-A   ( a -- a )  24 + ;
: UA.VAL-L   ( a -- a )  32 + ;

\ =====================================================================
\  Static Pools
\ =====================================================================

CREATE _UDL-ELEMS  _UDL-MAX-ELEMS _UDL-ELEMSZ * ALLOT
CREATE _UDL-ATTRS  _UDL-MAX-ATTRS _UDL-ATTRSZ * ALLOT
CREATE _UDL-STRS   _UDL-STR-SZ ALLOT
CREATE _UDL-HASH   _UDL-HASH-SZ CELLS ALLOT
CREATE _UDL-HIDS   _UDL-HASH-SZ 2 * CELLS ALLOT

VARIABLE _UDL-ECNT
VARIABLE _UDL-ACNT
VARIABLE _UDL-SPOS
VARIABLE _UDL-ROOT

\ Temp vars for search-by-name (avoids broken 2R@)
VARIABLE _UDL-SA   VARIABLE _UDL-SL
VARIABLE _UDL-RMA  VARIABLE _UDL-RML

\ =====================================================================
\  UIDL-RESET
\ =====================================================================

: UIDL-RESET  ( -- )
    UIDL-E-OK _UDL-ERR !
    0 _UDL-ECNT !  0 _UDL-ACNT !  0 _UDL-SPOS !  0 _UDL-ROOT !
    _UDL-ELEMS _UDL-MAX-ELEMS _UDL-ELEMSZ * 0 FILL
    _UDL-ATTRS _UDL-MAX-ATTRS _UDL-ATTRSZ * 0 FILL
    _UDL-HASH  _UDL-HASH-SZ CELLS 0 FILL
    _UDL-HIDS  _UDL-HASH-SZ 2 * CELLS 0 FILL ;

\ =====================================================================
\  String Pool
\ =====================================================================

: _UDL-STR-COPY  ( src len -- pool-a pool-l )
    DUP 0= IF EXIT THEN
    _UDL-SPOS @ OVER + _UDL-STR-SZ > IF
        2DROP UIDL-E-STR-FULL _UDL-ERR ! 0 0 EXIT
    THEN
    _UDL-STRS _UDL-SPOS @ +    ( src len dest )
    SWAP DUP >R                 ( src dest len  R: len )
    CMOVE                       ( )
    _UDL-STRS _UDL-SPOS @ +    ( pool-a )
    R>                          ( pool-a len )
    DUP _UDL-SPOS +! ;

\ =====================================================================
\  Element Allocation
\ =====================================================================

: _UDL-ALLOC-ELEM  ( -- elem | 0 )
    _UDL-ECNT @ _UDL-MAX-ELEMS >= IF
        UIDL-E-FULL _UDL-ERR ! 0 EXIT
    THEN
    _UDL-ECNT @ _UDL-ELEMSZ * _UDL-ELEMS +
    DUP _UDL-ELEMSZ 0 FILL
    1 _UDL-ECNT +! ;

\ =====================================================================
\  Attribute Allocation
\ =====================================================================

: _UDL-ALLOC-ATTR  ( -- attr | 0 )
    _UDL-ACNT @ _UDL-MAX-ATTRS >= IF
        UIDL-E-ATTR-FULL _UDL-ERR ! 0 EXIT
    THEN
    _UDL-ACNT @ _UDL-ATTRSZ * _UDL-ATTRS +
    DUP _UDL-ATTRSZ 0 FILL
    1 _UDL-ACNT +! ;

\ =====================================================================
\  ID Hash Table (FNV-1a, linear probing)
\ =====================================================================

: _UDL-HASH-FN  ( addr len -- idx )
    2166136261
    SWAP 0 ?DO
        OVER I + C@ XOR
        16777619 *
    LOOP
    NIP _UDL-HASH-SZ 1- AND ;

\ Register element in ID table.  -1 = ok, 0 = duplicate.
: _UDL-ID-REG  ( elem id-a id-l -- flag )
    2DUP _UDL-HASH-FN              ( elem id-a id-l idx )
    _UDL-HASH-SZ 0 DO
        DUP CELLS _UDL-HASH + @
        0= IF
            \ empty slot — insert
            3 PICK  OVER CELLS _UDL-HASH + !
            2 PICK  OVER 2 * CELLS _UDL-HIDS + !
            OVER    OVER 2 * 1+ CELLS _UDL-HIDS + !
            DROP 2DROP DROP -1
            UNLOOP EXIT
        THEN
        \ occupied — check duplicate
        DUP 2 * CELLS _UDL-HIDS + @
        OVER 2 * 1+ CELLS _UDL-HIDS + @
        4 PICK 4 PICK STR-STR= IF
            DROP 2DROP DROP
            UIDL-E-DUP-ID _UDL-ERR !
            0 UNLOOP EXIT
        THEN
        1+ _UDL-HASH-SZ 1- AND
    LOOP
    DROP 2DROP DROP 0 ;

\ Lookup element by ID.
: _UDL-ID-FIND  ( id-a id-l -- elem | 0 )
    2DUP _UDL-HASH-FN              ( id-a id-l idx )
    _UDL-HASH-SZ 0 DO
        DUP CELLS _UDL-HASH + @
        DUP 0= IF
            DROP DROP 2DROP 0
            UNLOOP EXIT
        THEN
        DROP
        DUP 2 * CELLS _UDL-HIDS + @
        OVER 2 * 1+ CELLS _UDL-HIDS + @
        4 PICK 4 PICK STR-STR= IF
            CELLS _UDL-HASH + @
            >R 2DROP R>
            UNLOOP EXIT
        THEN
        1+ _UDL-HASH-SZ 1- AND
    LOOP
    DROP 2DROP 0 ;

\ =====================================================================
\  Tag Name → Type Mapping
\ =====================================================================

: _UDL-MAP-TAG  ( name-a name-l -- type )
    2DUP S" uidl"       STR-STR= IF 2DROP UIDL-T-UIDL       EXIT THEN
    2DUP S" region"     STR-STR= IF 2DROP UIDL-T-REGION     EXIT THEN
    2DUP S" group"      STR-STR= IF 2DROP UIDL-T-GROUP      EXIT THEN
    2DUP S" separator"  STR-STR= IF 2DROP UIDL-T-SEPARATOR  EXIT THEN
    2DUP S" meta"       STR-STR= IF 2DROP UIDL-T-META       EXIT THEN
    2DUP S" label"      STR-STR= IF 2DROP UIDL-T-LABEL      EXIT THEN
    2DUP S" media"      STR-STR= IF 2DROP UIDL-T-MEDIA      EXIT THEN
    2DUP S" symbol"     STR-STR= IF 2DROP UIDL-T-SYMBOL     EXIT THEN
    2DUP S" canvas"     STR-STR= IF 2DROP UIDL-T-CANVAS     EXIT THEN
    2DUP S" action"     STR-STR= IF 2DROP UIDL-T-ACTION     EXIT THEN
    2DUP S" input"      STR-STR= IF 2DROP UIDL-T-INPUT      EXIT THEN
    2DUP S" selector"   STR-STR= IF 2DROP UIDL-T-SELECTOR   EXIT THEN
    2DUP S" toggle"     STR-STR= IF 2DROP UIDL-T-TOGGLE     EXIT THEN
    2DUP S" range"      STR-STR= IF 2DROP UIDL-T-RANGE      EXIT THEN
    2DUP S" collection" STR-STR= IF 2DROP UIDL-T-COLLECTION EXIT THEN
    2DUP S" table"      STR-STR= IF 2DROP UIDL-T-TABLE      EXIT THEN
    2DUP S" indicator"  STR-STR= IF 2DROP UIDL-T-INDICATOR  EXIT THEN
    2DUP S" template"   STR-STR= IF 2DROP UIDL-T-TEMPLATE   EXIT THEN
    2DUP S" empty"      STR-STR= IF 2DROP UIDL-T-EMPTY      EXIT THEN
    2DUP S" rep"        STR-STR= IF 2DROP UIDL-T-REP        EXIT THEN
    2DROP UIDL-T-NONE ;

\ =====================================================================
\  Arrange String → Mode
\ =====================================================================

: _UDL-MAP-ARRANGE  ( val-a val-l -- mode )
    2DUP S" dock"  STR-STR= IF 2DROP UIDL-A-DOCK  EXIT THEN
    2DUP S" flex"  STR-STR= IF 2DROP UIDL-A-FLEX  EXIT THEN
    2DUP S" stack" STR-STR= IF 2DROP UIDL-A-STACK EXIT THEN
    2DUP S" flow"  STR-STR= IF 2DROP UIDL-A-FLOW  EXIT THEN
    2DUP S" grid"  STR-STR= IF 2DROP UIDL-A-GRID  EXIT THEN
    2DUP S" none"  STR-STR= IF 2DROP UIDL-A-NONE  EXIT THEN
    2DROP UIDL-A-NONE ;

\ =====================================================================
\  Type → Name String
\ =====================================================================

: UIDL-TYPE-NAME  ( type -- a l )
    DUP  0 = IF DROP S" none"       EXIT THEN
    DUP  1 = IF DROP S" region"     EXIT THEN
    DUP  2 = IF DROP S" group"      EXIT THEN
    DUP  3 = IF DROP S" separator"  EXIT THEN
    DUP  4 = IF DROP S" meta"       EXIT THEN
    DUP  5 = IF DROP S" label"      EXIT THEN
    DUP  6 = IF DROP S" media"      EXIT THEN
    DUP  7 = IF DROP S" symbol"     EXIT THEN
    DUP  8 = IF DROP S" canvas"     EXIT THEN
    DUP  9 = IF DROP S" action"     EXIT THEN
    DUP 10 = IF DROP S" input"      EXIT THEN
    DUP 11 = IF DROP S" selector"   EXIT THEN
    DUP 12 = IF DROP S" toggle"     EXIT THEN
    DUP 13 = IF DROP S" range"      EXIT THEN
    DUP 14 = IF DROP S" collection" EXIT THEN
    DUP 15 = IF DROP S" table"      EXIT THEN
    DUP 16 = IF DROP S" indicator"  EXIT THEN
    DUP 17 = IF DROP S" uidl"       EXIT THEN
    DUP 18 = IF DROP S" template"   EXIT THEN
    DUP 19 = IF DROP S" empty"      EXIT THEN
    DUP 20 = IF DROP S" rep"        EXIT THEN
    DROP S" unknown" ;

\ =====================================================================
\  Tree Linking
\ =====================================================================

: _UDL-LINK-CHILD  ( parent child -- )
    OVER UE.LCHILD @ ?DUP IF
        \ has existing children — append after last
        2DUP SWAP UE.PREV !          \ child.prev = old-last
        OVER SWAP UE.NEXT !          \ old-last.next = child
    ELSE
        DUP 2 PICK UE.FCHILD !       \ parent.first = child
    THEN
    OVER UE.LCHILD !                  \ parent.last = child
    1 SWAP UE.NCHILD +! ;

\ =====================================================================
\  Attribute Storage
\ =====================================================================

: _UDL-STORE-ATTR  ( elem na nl va vl -- )
    _UDL-ERR @ IF 2DROP 2DROP DROP EXIT THEN
    _UDL-ALLOC-ATTR
    DUP 0= IF DROP 2DROP 2DROP DROP EXIT THEN
    >R
    _UDL-STR-COPY
    R@ UA.VAL-L !  R@ UA.VAL-A !
    _UDL-STR-COPY
    R@ UA.NAME-L !  R@ UA.NAME-A !
    DUP UE.ATTR @  R@ UA.NEXT !
    R> SWAP UE.ATTR ! ;

\ =====================================================================
\  Attribute Parser
\ =====================================================================

VARIABLE _UPA-NA  VARIABLE _UPA-NL
VARIABLE _UPA-VA  VARIABLE _UPA-VL

: _UDL-PARSE-ATTRS  ( elem xml-a xml-l -- )
    MU-GET-TAG-BODY MU-SKIP-NAME      ( elem body-a body-l )
    BEGIN
        MU-ATTR-NEXT                   ( elem ba' bl' na nl va vl flag )
    WHILE
        _UPA-VL !  _UPA-VA !
        _UPA-NL !  _UPA-NA !          ( elem ba' bl' )
        2>R                            ( elem  R: bl ba )

        _UPA-NA @ _UPA-NL @ S" id" STR-STR= IF
            _UPA-VA @ _UPA-VL @ _UDL-STR-COPY
            >R OVER UE.ID-A ! R> OVER UE.ID-L !
        ELSE
        _UPA-NA @ _UPA-NL @ S" role" STR-STR= IF
            _UPA-VA @ _UPA-VL @ _UDL-STR-COPY
            >R OVER UE.ROLE-A ! R> OVER UE.ROLE-L !
        ELSE
        _UPA-NA @ _UPA-NL @ S" arrange" STR-STR= IF
            _UPA-VA @ _UPA-VL @ _UDL-MAP-ARRANGE
            OVER UE.ARRANGE !
        ELSE
        _UPA-NA @ _UPA-NL @ S" bind" STR-STR= IF
            _UPA-VA @ _UPA-VL @
            DUP 0> IF OVER C@ 61 = IF 1 /STRING THEN THEN
            _UDL-STR-COPY
            >R OVER UE.BIND-A ! R> OVER UE.BIND-L !
        ELSE
        _UPA-NA @ _UPA-NL @ S" xmlns" STR-STR= IF
            \ skip
        ELSE
            DUP _UPA-NA @ _UPA-NL @
            _UPA-VA @ _UPA-VL @ _UDL-STORE-ATTR
        THEN THEN THEN THEN THEN

        2R>                            ( elem ba' bl' )
    REPEAT
    \ WHILE exit: flag=0, stack has extra items from MU-ATTR-NEXT
    \ MU-ATTR-NEXT with flag=0 returns: ( a u 0 0 0 0 0 )
    \ ... but WHILE already consumed the 0.
    \ Remaining: ( elem ba bl na nl va vl ) — 6 items from the zero-flag call
    2DROP 2DROP 2DROP
    DROP ;

\ =====================================================================
\  Recursive Element Parser
\ =====================================================================

: _UDL-PARSE-ELEM  ( xml-a xml-l parent -- elem | 0 )
    >R                                 ( xa xl  R: parent )

    \ tag name → type
    2DUP MU-GET-TAG-NAME               ( xa xl xa' xl' na nl )
    2SWAP 2DROP                        ( xa xl na nl )
    _UDL-MAP-TAG                       ( xa xl type )
    DUP UIDL-T-NONE = IF
        DROP 2DROP R> DROP 0 EXIT
    THEN
    >R                                 ( xa xl  R: parent type )

    \ allocate element
    _UDL-ALLOC-ELEM                    ( xa xl elem )
    DUP 0= IF 2DROP R> R> 2DROP 0 EXIT THEN

    \ set type, parent
    R> OVER UE.TYPE !                  ( xa xl elem  R: parent )
    R> OVER UE.PARENT !               ( xa xl elem )

    \ two-way flag
    DUP UE.TYPE @
    DUP UIDL-T-INPUT    =
    OVER UIDL-T-SELECTOR = OR
    OVER UIDL-T-TOGGLE   = OR
    SWAP UIDL-T-RANGE    = OR
    IF UIDL-F-TWOWAY OVER UE.FLAGS ! THEN

    \ detect self-closing
    >R 2DUP MU-TAG-TYPE               ( xa xl tt  R: elem )
    MU-T-SELF-CLOSE = IF
        R@ UE.FLAGS @ UIDL-F-SELFCLOSE OR R@ UE.FLAGS !
    THEN

    \ parse attributes
    R@ -ROT 2DUP 2>R                  ( elem xa xl  R: elem xl xa )
    _UDL-PARSE-ATTRS                   ( R: elem xl xa )
    2R>                                ( xa xl  R: elem )

    \ register ID
    R@ UE.ID-L @ 0> IF
        R@ R@ UE.ID-A @ R@ UE.ID-L @
        _UDL-ID-REG 0= IF
            R> DROP 2DROP 0 EXIT
        THEN
    THEN

    \ link to parent
    R@ UE.PARENT @ ?DUP IF
        R@ _UDL-LINK-CHILD
    THEN

    \ parse children if not self-closing
    R@ UE.FLAGS @ UIDL-F-SELFCLOSE AND 0= IF
        MU-ENTER                       ( ia il  R: elem )
        BEGIN
            MU-SKIP-WS
            MU-SKIP-TO-TAG
            DUP 0> WHILE
            2DUP MU-TAG-TYPE
            DUP MU-T-CLOSE = IF
                DROP 2DROP R> EXIT
            THEN
            DUP MU-T-OPEN = OVER MU-T-SELF-CLOSE = OR IF
                DROP
                2DUP R@ _UDL-PARSE-ELEM DROP
                MU-SKIP-ELEMENT
            ELSE DUP MU-T-COMMENT = IF
                DROP MU-SKIP-COMMENT
            ELSE DUP MU-T-PI = IF
                DROP MU-SKIP-PI
            ELSE
                DROP 1 /STRING
            THEN THEN THEN
        REPEAT
        2DROP
    ELSE
        2DROP
    THEN
    R> ;

\ =====================================================================
\  UIDL-PARSE
\ =====================================================================

: UIDL-PARSE  ( xml-a xml-l -- flag )
    UIDL-RESET
    MU-SKIP-WS  MU-SKIP-TO-TAG
    DUP 0= IF 2DROP UIDL-E-NO-ROOT _UDL-ERR ! 0 EXIT THEN

    2DUP MU-GET-TAG-NAME           ( xa xl xa' xl' na nl )
    2SWAP 2DROP                     ( xa xl na nl )
    S" uidl" STR-STR= 0= IF
        2DROP UIDL-E-NO-ROOT _UDL-ERR ! 0 EXIT
    THEN

    0 _UDL-PARSE-ELEM
    DUP 0= IF UIDL-E-NO-ROOT _UDL-ERR ! 0 EXIT THEN
    _UDL-ROOT !

    _UDL-ERR @ 0= ;

\ =====================================================================
\  Public Accessors
\ =====================================================================

: UIDL-ROOT        ( -- elem | 0 )  _UDL-ROOT @ ;
: UIDL-ELEM-COUNT  ( -- n )         _UDL-ECNT @ ;

: UIDL-TYPE        ( elem -- type )    UE.TYPE @ ;
: UIDL-ID          ( elem -- a l )     DUP UE.ID-A @ SWAP UE.ID-L @ ;
: UIDL-ROLE        ( elem -- a l )     DUP UE.ROLE-A @ SWAP UE.ROLE-L @ ;
: UIDL-ARRANGE     ( elem -- mode )    UE.ARRANGE @ ;
: UIDL-FLAGS       ( elem -- flags )   UE.FLAGS @ ;
: UIDL-PARENT      ( elem -- p | 0 )   UE.PARENT @ ;
: UIDL-FIRST-CHILD ( elem -- c | 0 )   UE.FCHILD @ ;
: UIDL-LAST-CHILD  ( elem -- c | 0 )   UE.LCHILD @ ;
: UIDL-NEXT-SIB    ( elem -- s | 0 )   UE.NEXT @ ;
: UIDL-PREV-SIB    ( elem -- s | 0 )   UE.PREV @ ;
: UIDL-NCHILDREN   ( elem -- n )       UE.NCHILD @ ;

: UIDL-BIND  ( elem -- a l flag )
    DUP UE.BIND-L @ 0> IF
        DUP UE.BIND-A @ SWAP UE.BIND-L @ -1
    ELSE DROP 0 0 0 THEN ;

: UIDL-WHEN  ( elem -- a l flag )
    UE.ATTR @
    BEGIN
        DUP 0<> WHILE
        DUP UA.NAME-A @ OVER UA.NAME-L @
        S" when" STR-STR= IF
            DUP UA.VAL-A @ SWAP UA.VAL-L @
            DUP 0> IF OVER C@ 61 = IF 1 /STRING THEN THEN
            -1 EXIT
        THEN
        UA.NEXT @
    REPEAT
    DROP 0 0 0 ;

: UIDL-ATTR  ( elem na nl -- va vl flag )
    _UDL-SL ! _UDL-SA ! UE.ATTR @
    BEGIN
        DUP 0<> WHILE
        DUP UA.NAME-A @ OVER UA.NAME-L @
        _UDL-SA @ _UDL-SL @ STR-STR= IF
            DUP UA.VAL-A @ SWAP UA.VAL-L @
            -1 EXIT
        THEN
        UA.NEXT @
    REPEAT
    DROP 0 0 0 ;

: UIDL-ATTR-FIRST  ( elem -- attr | 0 )  UE.ATTR @ ;
: UIDL-ATTR-NEXT   ( attr -- next | 0 )  UA.NEXT @ ;
: UIDL-ATTR-NAME   ( attr -- a l )  DUP UA.NAME-A @ SWAP UA.NAME-L @ ;
: UIDL-ATTR-VAL    ( attr -- a l )  DUP UA.VAL-A @ SWAP UA.VAL-L @ ;

: UIDL-BY-ID  ( id-a id-l -- elem | 0 )  _UDL-ID-FIND ;

\ =====================================================================
\  Binding & When Evaluation (needs ST-USE + LEL)
\ =====================================================================

: UIDL-BIND-EVAL  ( elem -- type v1 v2 )
    UIDL-BIND IF LEL-EVAL
    ELSE 2DROP ST-T-NULL 0 0 THEN ;

: UIDL-EVAL-WHEN  ( elem -- flag )
    UIDL-WHEN IF
        LEL-EVAL
        ROT
        DUP ST-T-BOOLEAN = IF DROP NIP EXIT THEN
        DUP ST-T-INTEGER = IF DROP NIP 0<> EXIT THEN
        DUP ST-T-NULL    = IF DROP NIP NIP 0 EXIT THEN
        DUP ST-T-STRING  = IF DROP NIP 0<> EXIT THEN
        DROP NIP NIP 0
    ELSE 2DROP -1 THEN ;

\ =====================================================================
\  Collection Helpers
\ =====================================================================

: UIDL-TEMPLATE  ( coll -- template | 0 )
    UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UIDL-TYPE UIDL-T-TEMPLATE = IF EXIT THEN
        UIDL-NEXT-SIB
    REPEAT ;

: UIDL-EMPTY-CHILD  ( coll -- empty | 0 )
    UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UIDL-TYPE UIDL-T-EMPTY = IF EXIT THEN
        UIDL-NEXT-SIB
    REPEAT ;

\ =====================================================================
\  Representation Set Helpers
\ =====================================================================

: UIDL-REP-COUNT  ( media -- n )
    0 SWAP UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UIDL-TYPE UIDL-T-REP = IF SWAP 1+ SWAP THEN
        UIDL-NEXT-SIB
    REPEAT DROP ;

: UIDL-REP-BY-MOD  ( media mod-a mod-l -- rep | 0 )
    _UDL-RML ! _UDL-RMA ! UIDL-FIRST-CHILD
    BEGIN DUP 0<> WHILE
        DUP UIDL-TYPE UIDL-T-REP = IF
            DUP S" modality" UIDL-ATTR IF
                _UDL-RMA @ _UDL-RML @ STR-STR= IF EXIT THEN
            ELSE 2DROP THEN
        THEN
        UIDL-NEXT-SIB
    REPEAT ;