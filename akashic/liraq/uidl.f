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

\ Ensure NOOP exists (needed for registry default execution tokens)
[DEFINED] NOOP [IF] [ELSE] : NOOP ; [THEN]

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
7 CONSTANT UIDL-E-REG-FULL

VARIABLE _UDL-ERR
: UIDL-ERR  ( -- code )  _UDL-ERR @ ;

\ =====================================================================
\  Element Registry — Extensible Type System
\ =====================================================================
\
\ Replaces the old fixed type-enum with an open hash-table registry.
\ Any code can call DEFINE-ELEMENT to register a new element type
\ with its tag name, render/event/layout execution tokens, content
\ model, and category — making the UIDL markup language extensible
\ in the Forth tradition.

\ --- Element Definition Flag Constants ---
\ Bits 0-2: Content model
0 CONSTANT EL-LEAF           \ leaf, no children
1 CONSTANT EL-CONTAINER      \ arbitrary children
2 CONSTANT EL-COLLECTION     \ requires <template> + optional <empty>
3 CONSTANT EL-SELECTOR       \ contains <option> children
4 CONSTANT EL-FIXED-2        \ exactly 2 children (split)
5 CONSTANT EL-FIXED-1        \ exactly 1 child (scroll)
\ Bits 3-4: Category
0  CONSTANT EL-CAT-ENVELOPE  \ 0 << 3
8  CONSTANT EL-CAT-DATA      \ 1 << 3
16 CONSTANT EL-CAT-CHROME    \ 2 << 3
24 CONSTANT EL-CAT-BINDING   \ 3 << 3
\ Bit 5-7: Special flags
32  CONSTANT EL-F-FOCUS       \ inherently interactive / focusable
64  CONSTANT EL-F-SELF        \ self-closing allowed
128 CONSTANT EL-F-TWOWAY      \ two-way binding element

\ --- Flag Composition Helpers ---
: OR-DATA    ( fl -- fl' ) EL-CAT-DATA    OR ;
: OR-CHROME  ( fl -- fl' ) EL-CAT-CHROME  OR ;
: OR-BINDING ( fl -- fl' ) EL-CAT-BINDING OR ;
: OR-FOCUS   ( fl -- fl' ) EL-F-FOCUS     OR ;
: OR-SELF    ( fl -- fl' ) EL-F-SELF      OR ;
: OR-TWOWAY  ( fl -- fl' ) EL-F-TWOWAY    OR ;

\ --- Flag Query Words ---
: EL-CONTENT-MODEL ( fl -- model ) 7 AND ;
: EL-CATEGORY      ( fl -- cat )   3 RSHIFT 3 AND ;
: EL-FOCUSABLE?    ( fl -- flag )  EL-F-FOCUS  AND 0<> ;
: EL-SELF-CLOSE?   ( fl -- flag )  EL-F-SELF   AND 0<> ;
: EL-TWOWAY?       ( fl -- flag )  EL-F-TWOWAY AND 0<> ;

\ --- Element Definition Record (64 bytes, 8 cells) ---
: ED.TYPE      ( def -- a )         ;  \ +0  type-id
: ED.NAME-A    ( def -- a ) 8  + ;     \ +8  tag name string address
: ED.NAME-L    ( def -- a ) 16 + ;     \ +16 tag name string length
: ED.FLAGS     ( def -- a ) 24 + ;     \ +24 content model + category bits
: ED.RENDER-XT ( def -- a ) 32 + ;     \ +32 ( elem -- ) rendering hook
: ED.EVENT-XT  ( def -- a ) 40 + ;     \ +40 ( elem evt -- handled? )
: ED.LAYOUT-XT ( def -- a ) 48 + ;     \ +48 ( elem -- ) layout hook
: ED.NEXT      ( def -- a ) 56 + ;     \ +56 reserved / hash chain

\ --- Registry Storage ---
64 CONSTANT _EL-REG-SZ
CREATE _EL-REGISTRY  _EL-REG-SZ 64 * ALLOT   \ 64 slots × 64 bytes = 4096
VARIABLE _EL-REG-CNT
CREATE _EL-DEFS  _EL-REG-SZ CELLS ALLOT      \ type-id → def pointer index
\ --- Registry String Pool (persistent, not reset on UIDL-RESET) ---
CREATE _EL-REG-STRS  512 ALLOT
VARIABLE _EL-REG-SPOS

: _EL-STR-COPY  ( src len -- pool-a pool-l )
    DUP 0= IF EXIT THEN
    _EL-REG-SPOS @ OVER + 512 > IF 2DROP 0 0 EXIT THEN
    _EL-REG-STRS _EL-REG-SPOS @ + ( src len dest )
    SWAP DUP >R CMOVE
    _EL-REG-STRS _EL-REG-SPOS @ + R>
    DUP _EL-REG-SPOS +! ;

\ --- Registry Hash Function (FNV-1a, 64-slot) ---
: _EL-HASH-FN  ( addr len -- idx )
    2166136261
    SWAP 0 ?DO
        OVER I + C@ XOR
        16777619 *
    LOOP
    NIP 63 AND ;

\ --- Registry Lookup ---
VARIABLE _ER-SA  VARIABLE _ER-SL

: EL-LOOKUP  ( name-a name-l -- def | 0 )
    _ER-SL ! _ER-SA !
    _ER-SA @ _ER-SL @ _EL-HASH-FN        ( idx )
    _EL-REG-SZ 0 DO
        DUP 64 * _EL-REGISTRY +           ( idx def )
        DUP ED.NAME-L @ 0= IF
            2DROP 0 UNLOOP EXIT            \ empty slot — not found
        THEN
        DUP ED.NAME-A @ OVER ED.NAME-L @  ( idx def da dl )
        _ER-SA @ _ER-SL @ STR-STR= IF
            NIP UNLOOP EXIT                \ found — return def
        THEN
        DROP                               ( idx )
        1+ 63 AND
    LOOP
    DROP 0 ;

\ --- Lookup by Type ID ---
: EL-DEF-BY-TYPE  ( type-id -- def | 0 )
    DUP 1 < OVER _EL-REG-SZ > OR IF DROP 0 EXIT THEN
    CELLS _EL-DEFS + @ ;

\ --- Register Element (internal) ---
VARIABLE _ER-RXT  VARIABLE _ER-EXT  VARIABLE _ER-LXT  VARIABLE _ER-FL
VARIABLE _ER-NA   VARIABLE _ER-NL   VARIABLE _ER-TID

: _UDL-REG-ELEM  ( render-xt event-xt layout-xt flags name-a name-l -- type-id )
    _ER-NL ! _ER-NA !
    _ER-FL ! _ER-LXT ! _ER-EXT ! _ER-RXT !
    \ Check capacity
    _EL-REG-CNT @ _EL-REG-SZ >= IF
        UIDL-E-REG-FULL _UDL-ERR ! 0 EXIT
    THEN
    \ Check for duplicate name
    _ER-NA @ _ER-NL @ EL-LOOKUP IF
        DROP 0 EXIT
    THEN
    \ Copy name to persistent pool
    _ER-NA @ _ER-NL @ _EL-STR-COPY _ER-NL ! _ER-NA !
    \ Assign type-id
    _EL-REG-CNT @ 1+ _ER-TID !
    \ Find empty hash slot and fill it
    _ER-NA @ _ER-NL @ _EL-HASH-FN    ( idx )
    _EL-REG-SZ 0 DO
        DUP 64 * _EL-REGISTRY +       ( idx def )
        DUP ED.NAME-L @ 0= IF
            \ Found empty slot — fill definition record
            _ER-TID @   OVER ED.TYPE !
            _ER-NA @    OVER ED.NAME-A !
            _ER-NL @    OVER ED.NAME-L !
            _ER-FL @    OVER ED.FLAGS !
            _ER-RXT @   OVER ED.RENDER-XT !
            _ER-EXT @   OVER ED.EVENT-XT !
            _ER-LXT @   OVER ED.LAYOUT-XT !
            0           OVER ED.NEXT !
            \ Update by-type index
            DUP _ER-TID @ CELLS _EL-DEFS + !
            DROP DROP                  \ drop def, idx
            1 _EL-REG-CNT +!
            _ER-TID @
            UNLOOP EXIT
        THEN
        DROP                           ( idx )
        1+ 63 AND
    LOOP
    DROP 0 ;

\ --- Public Registration Word ---
: DEFINE-ELEMENT  ( render-xt event-xt layout-xt flags "name" -- type-id )
    PARSE-NAME NAMEBUF PN-LEN @ _UDL-REG-ELEM ;

\ =====================================================================
\  Built-in Element Registrations (20 core + option)
\ =====================================================================
\ Registration order preserves backward-compatible type-ids:
\   1=region, 2=group, ..., 17=uidl, 18=template, 19=empty, 20=rep, 21=option
\ All render/event/layout XTs are NOOP — backends patch them later.

' NOOP ' NOOP ' NOOP EL-CONTAINER OR-DATA                S" region"     _UDL-REG-ELEM CONSTANT UIDL-T-REGION
' NOOP ' NOOP ' NOOP EL-CONTAINER OR-DATA                S" group"      _UDL-REG-ELEM CONSTANT UIDL-T-GROUP
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-SELF             S" separator"  _UDL-REG-ELEM CONSTANT UIDL-T-SEPARATOR
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-SELF             S" meta"       _UDL-REG-ELEM CONSTANT UIDL-T-META
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA                     S" label"      _UDL-REG-ELEM CONSTANT UIDL-T-LABEL
' NOOP ' NOOP ' NOOP EL-CONTAINER OR-DATA                S" media"      _UDL-REG-ELEM CONSTANT UIDL-T-MEDIA
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-SELF             S" symbol"     _UDL-REG-ELEM CONSTANT UIDL-T-SYMBOL
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-FOCUS            S" canvas"     _UDL-REG-ELEM CONSTANT UIDL-T-CANVAS
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-FOCUS            S" action"     _UDL-REG-ELEM CONSTANT UIDL-T-ACTION
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-FOCUS OR-SELF OR-TWOWAY S" input" _UDL-REG-ELEM CONSTANT UIDL-T-INPUT
' NOOP ' NOOP ' NOOP EL-SELECTOR OR-DATA OR-FOCUS OR-TWOWAY S" selector" _UDL-REG-ELEM CONSTANT UIDL-T-SELECTOR
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-FOCUS OR-SELF OR-TWOWAY S" toggle" _UDL-REG-ELEM CONSTANT UIDL-T-TOGGLE
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-FOCUS OR-SELF OR-TWOWAY S" range" _UDL-REG-ELEM CONSTANT UIDL-T-RANGE
' NOOP ' NOOP ' NOOP EL-COLLECTION OR-DATA               S" collection" _UDL-REG-ELEM CONSTANT UIDL-T-COLLECTION
' NOOP ' NOOP ' NOOP EL-CONTAINER OR-DATA OR-FOCUS       S" table"      _UDL-REG-ELEM CONSTANT UIDL-T-TABLE
' NOOP ' NOOP ' NOOP EL-LEAF OR-DATA OR-SELF             S" indicator"  _UDL-REG-ELEM CONSTANT UIDL-T-INDICATOR
' NOOP ' NOOP ' NOOP EL-CONTAINER                        S" uidl"       _UDL-REG-ELEM CONSTANT UIDL-T-UIDL
' NOOP ' NOOP ' NOOP EL-CONTAINER OR-BINDING             S" template"   _UDL-REG-ELEM CONSTANT UIDL-T-TEMPLATE
' NOOP ' NOOP ' NOOP EL-CONTAINER OR-BINDING             S" empty"      _UDL-REG-ELEM CONSTANT UIDL-T-EMPTY
' NOOP ' NOOP ' NOOP EL-LEAF OR-BINDING OR-SELF          S" rep"        _UDL-REG-ELEM CONSTANT UIDL-T-REP
' NOOP ' NOOP ' NOOP EL-LEAF OR-BINDING OR-SELF          S" option"     _UDL-REG-ELEM CONSTANT UIDL-T-OPTION

0 CONSTANT UIDL-T-NONE   \ sentinel: "unknown tag"

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
4 CONSTANT UIDL-F-DIRTY

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

\ Subscription table storage (code in subscription section below)
128 CONSTANT _UDL-MAX-SUBS
CREATE _UDL-SUBS  _UDL-MAX-SUBS 24 * ALLOT  \ 128 × 24 = 3,072 bytes
VARIABLE _UDL-SUB-CNT

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
    _UDL-HIDS  _UDL-HASH-SZ 2 * CELLS 0 FILL
    0 _UDL-SUB-CNT !
    _UDL-SUBS _UDL-MAX-SUBS 24 * 0 FILL ;

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
    EL-LOOKUP DUP IF ED.TYPE @ ELSE DROP 0 THEN ;

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
    DUP 0= IF DROP S" none" EXIT THEN
    EL-DEF-BY-TYPE DUP IF
        DUP ED.NAME-A @ SWAP ED.NAME-L @
    ELSE DROP S" unknown" THEN ;

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

    \ two-way flag from registry
    DUP UE.TYPE @ EL-DEF-BY-TYPE ?DUP IF
        ED.FLAGS @ EL-F-TWOWAY AND IF
            UIDL-F-TWOWAY OVER UE.FLAGS !
        THEN
    THEN

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

\ =====================================================================
\  Phase 3 — Gap 3.1: Document Validation
\ =====================================================================
\
\ UIDL-VALIDATE scans all allocated elements and checks 8 rules.
\ Up to 16 errors stored in a buffer (rule# + elem-addr pairs).

CREATE _UDL-VERR  256 ALLOT   \ 16 entries × (8 rule + 8 elem) = 256
VARIABLE _UDL-VCNT             \ error count

: UIDL-ERROR-COUNT  ( -- n )  _UDL-VCNT @ ;

: UIDL-ERRORS-CLEAR ( -- )
    0 _UDL-VCNT !
    _UDL-VERR 256 0 FILL ;

: _UDL-VERR-ADD  ( rule elem -- )
    _UDL-VCNT @ 16 >= IF 2DROP EXIT THEN
    _UDL-VCNT @ 16 * _UDL-VERR +    \ slot addr
    >R
    R@ 8 + !                          \ store elem
    R> !                               \ store rule
    1 _UDL-VCNT +! ;

: UIDL-ERROR-NTH  ( n -- rule elem )
    DUP 0< OVER _UDL-VCNT @ >= OR IF
        DROP 0 0 EXIT
    THEN
    16 * _UDL-VERR +
    DUP @ SWAP 8 + @ ;

\ --- Helper: element by pool index ---
: _UDL-ELEM-I  ( i -- elem )
    _UDL-ELEMSZ * _UDL-ELEMS + ;

\ --- Rule 2: Valid ID format [a-z][a-z0-9-]*, max 64 ---
VARIABLE _UDL-VF   \ validation flag temp

: _UDL-ID-CH?  ( ch -- flag )
    DUP 97 >= OVER 122 <= AND IF DROP TRUE EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP TRUE EXIT THEN
    45 = ;

: _UDL-CHK-ID-FMT  ( elem -- )
    DUP UE.ID-L @ DUP 0= IF 2DROP EXIT THEN    \ no ID → skip
    DUP 64 > IF DROP 2 SWAP _UDL-VERR-ADD EXIT THEN
    SWAP DUP UE.ID-A @                           \ ( len elem id-a )
    SWAP >R                                       \ ( len id-a  R: elem )
    DUP C@ DUP 97 >= SWAP 122 <= AND 0= IF
        2DROP 2 R> _UDL-VERR-ADD EXIT
    THEN
    \ scan rest
    TRUE _UDL-VF !
    SWAP 1 ?DO
        DUP I + C@ _UDL-ID-CH? 0= IF FALSE _UDL-VF ! THEN
    LOOP
    DROP
    _UDL-VF @ 0= IF 2 R> _UDL-VERR-ADD ELSE R> DROP THEN ;

\ --- Rule 3: Valid bind path (dot-separated [a-z_][a-z0-9_]*) ---

: _UDL-BIND-CH?  ( ch -- flag )
    DUP 97 >= OVER 122 <= AND IF DROP TRUE EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP TRUE EXIT THEN
    DUP 95 = IF DROP TRUE EXIT THEN
    46 = ;

: _UDL-BIND-START?  ( ch -- flag )
    DUP 97 >= OVER 122 <= AND IF DROP TRUE EXIT THEN
    95 = ;

: _UDL-CHK-BIND  ( elem -- )
    DUP UE.BIND-L @ DUP 0= IF 2DROP EXIT THEN   \ no bind → skip
    SWAP DUP >R UE.BIND-A @                      \ ( len bind-a  R: elem )
    \ first char must be letter or _
    OVER C@ _UDL-BIND-START? 0= IF
        2DROP 3 R> _UDL-VERR-ADD EXIT
    THEN
    TRUE _UDL-VF !
    SWAP 1 ?DO
        DUP I + C@ _UDL-BIND-CH? 0= IF FALSE _UDL-VF ! THEN
    LOOP
    DROP
    _UDL-VF @ 0= IF 3 R> _UDL-VERR-ADD ELSE R> DROP THEN ;

\ --- Rule 4: Valid when expression (LEL-EVAL + _LEL-ERR check) ---

: _UDL-CHK-WHEN  ( elem -- )
    DUP UE.ATTR @
    BEGIN
        DUP 0<> WHILE
        DUP UA.NAME-A @ OVER UA.NAME-L @
        S" when" STR-STR= IF
            \ found when attr
            DUP UA.VAL-A @ OVER UA.VAL-L @     \ ( elem attr val-a val-l )
            DUP 0> IF OVER C@ 61 = IF 1 /STRING THEN THEN
            LEL-EVAL 2DROP DROP                 \ eval and discard result
            _LEL-ERR @ IF
                DROP                            \ drop attr
                4 SWAP _UDL-VERR-ADD EXIT       \ elem still on stack
            THEN
            2DROP EXIT                          \ drop attr + elem, ok
        THEN
        UA.NEXT @
    REPEAT
    2DROP ;                                     \ drop 0 + elem

\ --- Rule 5: Collection must have template child ---

: _UDL-CHK-COLL  ( elem -- )
    DUP UE.TYPE @ UIDL-T-COLLECTION <> IF DROP EXIT THEN
    DUP UIDL-TEMPLATE 0= IF
        5 SWAP _UDL-VERR-ADD
    ELSE DROP THEN ;

\ --- Rule 7: Arrange in valid range (0-5) ---

: _UDL-CHK-ARRANGE  ( elem -- )
    DUP UE.ARRANGE @ DUP 0 >= SWAP 5 <= AND IF
        DROP EXIT
    THEN
    7 SWAP _UDL-VERR-ADD ;

\ --- Rule 8: on-activate and emit mutually exclusive ---
VARIABLE _UDL-V8A   \ has on-activate
VARIABLE _UDL-V8E   \ has emit

: _UDL-CHK-EXCL  ( elem -- )
    0 _UDL-V8A !  0 _UDL-V8E !
    DUP UE.ATTR @
    BEGIN
        DUP 0<> WHILE
        DUP UA.NAME-A @ OVER UA.NAME-L @
        2DUP S" on-activate" STR-STR= IF 2DROP 1 _UDL-V8A ! ELSE
        S" emit" STR-STR= IF 1 _UDL-V8E ! THEN THEN
        UA.NEXT @
    REPEAT
    DROP
    _UDL-V8A @ _UDL-V8E @ AND IF
        8 SWAP _UDL-VERR-ADD
    ELSE DROP THEN ;

\ --- Main validation word ---

: UIDL-VALIDATE  ( -- n-errors )
    UIDL-ERRORS-CLEAR
    \ Rule 10: Root must be <uidl>
    UIDL-ROOT DUP 0= IF
        DROP 10 0 _UDL-VERR-ADD
        UIDL-ERROR-COUNT EXIT
    THEN
    DUP UE.TYPE @ UIDL-T-UIDL <> IF
        10 SWAP _UDL-VERR-ADD
    ELSE DROP THEN
    \ Scan all elements
    _UDL-ECNT @ 0 ?DO
        I _UDL-ELEM-I
        DUP _UDL-CHK-ID-FMT
        DUP _UDL-CHK-BIND
        DUP _UDL-CHK-WHEN
        DUP _UDL-CHK-COLL
        DUP _UDL-CHK-ARRANGE
        _UDL-CHK-EXCL
    LOOP
    UIDL-ERROR-COUNT ;

\ =====================================================================
\  Phase 3 — Gap 3.2: Document Mutation API
\ =====================================================================

VARIABLE _UDL-MUT-P   \ parent temp for mutations

: UIDL-ADD-ELEM  ( parent type -- new-elem | 0 )
    SWAP _UDL-MUT-P !
    _UDL-ALLOC-ELEM
    DUP 0= IF NIP EXIT THEN
    SWAP OVER UE.TYPE !
    _UDL-MUT-P @ OVER UE.PARENT !
    _UDL-MUT-P @ ?DUP IF
        OVER _UDL-LINK-CHILD
    THEN ;

\ Unlink elem from its parent's child chain
: _UDL-UNLINK  ( elem -- )
    DUP UE.PREV @ ?DUP IF
        OVER UE.NEXT @ SWAP UE.NEXT !    \ prev.next = elem.next
    ELSE
        \ elem is first child — update parent.fchild
        DUP UE.PARENT @ ?DUP IF
            OVER UE.NEXT @ SWAP UE.FCHILD !
        THEN
    THEN
    DUP UE.NEXT @ ?DUP IF
        OVER UE.PREV @ SWAP UE.PREV !    \ next.prev = elem.prev
    ELSE
        \ elem is last child — update parent.lchild
        DUP UE.PARENT @ ?DUP IF
            OVER UE.PREV @ SWAP UE.LCHILD !
        THEN
    THEN
    DUP UE.PARENT @ ?DUP IF
        -1 SWAP UE.NCHILD +!
    THEN
    0 OVER UE.NEXT !  0 OVER UE.PREV !
    0 SWAP UE.PARENT ! ;

: UIDL-REMOVE-ELEM  ( elem -- )
    \ Recursively remove children first
    DUP UE.FCHILD @
    BEGIN DUP 0<> WHILE
        DUP UE.NEXT @     \ save next before we destroy it
        SWAP RECURSE
    REPEAT DROP
    \ Unlink from parent
    DUP _UDL-UNLINK
    \ Zero out the element
    _UDL-ELEMSZ 0 FILL ;

: UIDL-SET-ATTR  ( elem name-a name-l val-a val-l -- )
    \ Check if attr already exists
    4 PICK UE.ATTR @
    BEGIN
        DUP 0<> WHILE
        DUP UA.NAME-A @ OVER UA.NAME-L @
        6 PICK 6 PICK STR-STR= IF
            \ Found — overwrite value
            >R                         \ ( elem na nl va vl  R: attr )
            2SWAP 2DROP ROT DROP       \ ( va vl  R: attr )
            _UDL-STR-COPY
            R@ UA.VAL-L ! R> UA.VAL-A !
            EXIT
        THEN
        UA.NEXT @
    REPEAT
    DROP      \ drop the 0 from loop exit
    \ Not found — store new attr (existing _UDL-STORE-ATTR)
    _UDL-STORE-ATTR ;

: UIDL-REMOVE-ATTR  ( elem name-a name-l -- )
    _UDL-SL ! _UDL-SA !
    DUP UE.ATTR @        \ prev-ptr = 0, cur = first attr
    0 SWAP                \ ( elem 0 cur )
    BEGIN
        DUP 0<> WHILE
        DUP UA.NAME-A @ OVER UA.NAME-L @
        _UDL-SA @ _UDL-SL @ STR-STR= IF
            \ Found it: unlink
            DUP UA.NEXT @              \ ( elem prev cur next )
            NIP                        \ ( elem prev next )
            OVER 0= IF
                \ cur was first attr — update elem.attr
                2 PICK UE.ATTR !       \ elem.attr = next
                DROP                   \ drop prev (0)
            ELSE
                SWAP UA.NEXT !         \ prev.next = next
            THEN
            DROP EXIT                  \ drop elem
        THEN
        NIP DUP UA.NEXT @             \ advance: prev=cur, cur=cur.next
    REPEAT
    2DROP DROP ;                       \ not found — clean up

: UIDL-MOVE-ELEM  ( elem new-parent -- )
    OVER _UDL-UNLINK
    2DUP SWAP UE.PARENT !
    _UDL-LINK-CHILD ;

\ =====================================================================
\  Phase 3 — Gap 3.3: Two-Way Binding Write-Back
\ =====================================================================

VARIABLE _UDL-BWE   \ bind-write element

: UIDL-BIND-WRITE  ( elem value-a value-l -- )
    ROT _UDL-BWE !                     \ save elem
    _UDL-BWE @ UIDL-BIND              \ ( val-a val-l bind-a bind-l flag )
    0= IF 2DROP 2DROP EXIT THEN        \ no bind → drop 4 remaining items
    \ stack: ( val-a val-l bind-a bind-l )
    _UDL-BWE @ UE.TYPE @
    DUP UIDL-T-TOGGLE = IF
        DROP
        2>R                            \ R: bind-l bind-a
        S" true" STR-STR=
        2R> ST-SET-PATH-BOOL EXIT
    THEN
    DUP UIDL-T-RANGE = IF
        DROP
        2>R                            \ R: bind-l bind-a
        STR>NUM 0= IF DROP 0 THEN
        2R> ST-SET-PATH-INT EXIT
    THEN
    DROP
    \ Default: string write-back  ( val-a val-l bind-a bind-l )
    ST-SET-PATH-STR ;

\ =====================================================================
\  Phase 3 — Gap 3.4: Action Dispatch Helpers
\ =====================================================================

0 CONSTANT UIDL-ACT-ACTIVATE
1 CONSTANT UIDL-ACT-EMIT
2 CONSTANT UIDL-ACT-SET-STATE

: UIDL-DISPATCH  ( elem -- action-type )
    DUP S" on-activate" UIDL-ATTR IF
        2DROP DROP UIDL-ACT-ACTIVATE EXIT
    THEN 2DROP
    DUP S" emit" UIDL-ATTR IF
        2DROP DROP UIDL-ACT-EMIT EXIT
    THEN 2DROP
    DUP S" set-state" UIDL-ATTR IF
        2DROP DROP UIDL-ACT-SET-STATE EXIT
    THEN 2DROP
    DROP -1 ;

: UIDL-HAS-ACTION?  ( elem -- flag )
    UIDL-DISPATCH -1 <> ;

: UIDL-ACTION-VALUE  ( elem -- a l flag )
    DUP S" on-activate" UIDL-ATTR IF
        >R >R DROP R> R> -1 EXIT
    THEN 2DROP
    DUP S" emit" UIDL-ATTR IF
        >R >R DROP R> R> -1 EXIT
    THEN 2DROP
    DUP S" set-state" UIDL-ATTR IF
        >R >R DROP R> R> -1 EXIT
    THEN 2DROP
    DROP 0 0 0 ;

\ =====================================================================
\  Subscription Table — Reactive Binding
\ =====================================================================
\
\ Maps state-tree paths (by hash) to subscribed elements.
\ When a path changes, UIDL-NOTIFY marks all subscribers dirty.
\ The paint cycle only redraws dirty elements.
\ Storage: _UDL-SUBS, _UDL-SUB-CNT, _UDL-MAX-SUBS declared in pools section.

\ Path hash (raw FNV-1a, no masking — for exact match)
: _UDL-PATH-HASH  ( addr len -- hash )
    2166136261
    SWAP 0 ?DO
        OVER I + C@ XOR
        16777619 *
    LOOP
    NIP ;

: UIDL-RESET-SUBS  ( -- )
    0 _UDL-SUB-CNT !
    _UDL-SUBS _UDL-MAX-SUBS 24 * 0 FILL ;

: UIDL-SUBSCRIBE  ( elem bind-a bind-l -- )
    _UDL-SUB-CNT @ _UDL-MAX-SUBS >= IF 2DROP DROP EXIT THEN
    _UDL-PATH-HASH                        ( elem hash )
    _UDL-SUB-CNT @ 24 * _UDL-SUBS +      ( elem hash entry )
    SWAP OVER !                            ( elem entry ) \ entry+0 = hash
    8 + !                                  ( )            \ entry+8 = elem
    1 _UDL-SUB-CNT +! ;

: UIDL-NOTIFY  ( path-a path-l -- )
    _UDL-PATH-HASH                         ( hash )
    _UDL-SUB-CNT @ 0 ?DO
        I 24 * _UDL-SUBS +                ( hash entry )
        DUP @ 2 PICK = IF
            8 + @                          ( hash elem )
            DUP UE.FLAGS @ UIDL-F-DIRTY OR SWAP UE.FLAGS !
        ELSE
            DROP
        THEN
    LOOP
    DROP ;

\ --- Dirty Flag Helpers ---
: UIDL-DIRTY?  ( elem -- flag )  UE.FLAGS @ UIDL-F-DIRTY AND 0<> ;

VARIABLE _UDL-DIRTY-HOOK   \ ( -- ) optional hook called after UIDL-DIRTY!
0 _UDL-DIRTY-HOOK !

: UIDL-DIRTY!  ( elem -- )
    DUP UE.FLAGS @ UIDL-F-DIRTY OR SWAP UE.FLAGS !
    _UDL-DIRTY-HOOK @ ?DUP IF EXECUTE THEN ;

: UIDL-CLEAN!  ( elem -- )  DUP UE.FLAGS @ UIDL-F-DIRTY INVERT AND SWAP UE.FLAGS ! ;

\ ── guard ────────────────────────────────────────────────
[DEFINED] GUARDED [IF] GUARDED [IF]
REQUIRE ../concurrency/guard.f
GUARD _uidl-guard

' UIDL-ERR        CONSTANT _uidl-err-xt
' UE.TYPE         CONSTANT _ue-dottype-xt
' UE.FLAGS        CONSTANT _ue-dotflags-xt
' UE.PARENT       CONSTANT _ue-dotparent-xt
' UE.NEXT         CONSTANT _ue-dotnext-xt
' UE.PREV         CONSTANT _ue-dotprev-xt
' UE.FCHILD       CONSTANT _ue-dotfchild-xt
' UE.LCHILD       CONSTANT _ue-dotlchild-xt
' UE.NCHILD       CONSTANT _ue-dotnchild-xt
' UE.ID-A         CONSTANT _ue-dotid-a-xt
' UE.ID-L         CONSTANT _ue-dotid-l-xt
' UE.ROLE-A       CONSTANT _ue-dotrole-a-xt
' UE.ROLE-L       CONSTANT _ue-dotrole-l-xt
' UE.ARRANGE      CONSTANT _ue-dotarrange-xt
' UE.ATTR         CONSTANT _ue-dotattr-xt
' UE.BIND-A       CONSTANT _ue-dotbind-a-xt
' UE.BIND-L       CONSTANT _ue-dotbind-l-xt
' UA.NEXT         CONSTANT _ua-dotnext-xt
' UA.NAME-A       CONSTANT _ua-dotname-a-xt
' UA.NAME-L       CONSTANT _ua-dotname-l-xt
' UA.VAL-A        CONSTANT _ua-dotval-a-xt
' UA.VAL-L        CONSTANT _ua-dotval-l-xt
' UIDL-RESET      CONSTANT _uidl-reset-xt
' UIDL-TYPE-NAME  CONSTANT _uidl-type-name-xt
' UIDL-PARSE      CONSTANT _uidl-parse-xt
' UIDL-ROOT       CONSTANT _uidl-root-xt
' UIDL-ELEM-COUNT CONSTANT _uidl-elem-count-xt
' UIDL-TYPE       CONSTANT _uidl-type-xt
' UIDL-ID         CONSTANT _uidl-id-xt
' UIDL-ROLE       CONSTANT _uidl-role-xt
' UIDL-ARRANGE    CONSTANT _uidl-arrange-xt
' UIDL-FLAGS      CONSTANT _uidl-flags-xt
' UIDL-PARENT     CONSTANT _uidl-parent-xt
' UIDL-FIRST-CHILD CONSTANT _uidl-first-child-xt
' UIDL-LAST-CHILD CONSTANT _uidl-last-child-xt
' UIDL-NEXT-SIB   CONSTANT _uidl-next-sib-xt
' UIDL-PREV-SIB   CONSTANT _uidl-prev-sib-xt
' UIDL-NCHILDREN  CONSTANT _uidl-nchildren-xt
' UIDL-BIND       CONSTANT _uidl-bind-xt
' UIDL-WHEN       CONSTANT _uidl-when-xt
' UIDL-ATTR       CONSTANT _uidl-attr-xt
' UIDL-ATTR-FIRST CONSTANT _uidl-attr-first-xt
' UIDL-ATTR-NEXT  CONSTANT _uidl-attr-next-xt
' UIDL-ATTR-NAME  CONSTANT _uidl-attr-name-xt
' UIDL-ATTR-VAL   CONSTANT _uidl-attr-val-xt
' UIDL-BY-ID      CONSTANT _uidl-by-id-xt
' UIDL-BIND-EVAL  CONSTANT _uidl-bind-eval-xt
' UIDL-EVAL-WHEN  CONSTANT _uidl-eval-when-xt
' UIDL-TEMPLATE   CONSTANT _uidl-template-xt
' UIDL-EMPTY-CHILD CONSTANT _uidl-empty-child-xt
' UIDL-REP-COUNT  CONSTANT _uidl-rep-count-xt
' UIDL-REP-BY-MOD CONSTANT _uidl-rep-by-mod-xt
' UIDL-ERROR-COUNT CONSTANT _uidl-error-count-xt
' UIDL-ERRORS-CLEAR CONSTANT _uidl-errors-clear-xt
' UIDL-ERROR-NTH  CONSTANT _uidl-error-nth-xt
' UIDL-VALIDATE   CONSTANT _uidl-validate-xt
' UIDL-ADD-ELEM   CONSTANT _uidl-add-elem-xt
' UIDL-REMOVE-ELEM CONSTANT _uidl-remove-elem-xt
' UIDL-SET-ATTR   CONSTANT _uidl-set-attr-xt
' UIDL-REMOVE-ATTR CONSTANT _uidl-remove-attr-xt
' UIDL-MOVE-ELEM  CONSTANT _uidl-move-elem-xt
' UIDL-BIND-WRITE CONSTANT _uidl-bind-write-xt
' UIDL-DISPATCH   CONSTANT _uidl-dispatch-xt
' UIDL-HAS-ACTION? CONSTANT _uidl-has-action-q-xt
' UIDL-ACTION-VALUE CONSTANT _uidl-action-value-xt
\ --- registry / subscription / dirty guards ---
' DEFINE-ELEMENT   CONSTANT _define-element-xt
' EL-LOOKUP        CONSTANT _el-lookup-xt
' EL-DEF-BY-TYPE   CONSTANT _el-def-by-type-xt
' ED.TYPE          CONSTANT _ed-dottype-xt
' ED.NAME-A        CONSTANT _ed-dotname-a-xt
' ED.NAME-L        CONSTANT _ed-dotname-l-xt
' ED.FLAGS         CONSTANT _ed-dotflags-xt
' ED.RENDER-XT     CONSTANT _ed-dotrender-xt-xt
' ED.EVENT-XT      CONSTANT _ed-dotevent-xt-xt
' ED.LAYOUT-XT     CONSTANT _ed-dotlayout-xt-xt
' EL-CONTENT-MODEL CONSTANT _el-content-model-xt
' EL-CATEGORY      CONSTANT _el-category-xt
' EL-FOCUSABLE?    CONSTANT _el-focusable-q-xt
' EL-SELF-CLOSE?   CONSTANT _el-self-close-q-xt
' EL-TWOWAY?       CONSTANT _el-twoway-q-xt
' UIDL-SUBSCRIBE   CONSTANT _uidl-subscribe-xt
' UIDL-NOTIFY      CONSTANT _uidl-notify-xt
' UIDL-RESET-SUBS  CONSTANT _uidl-reset-subs-xt
' UIDL-DIRTY?      CONSTANT _uidl-dirty-q-xt
' UIDL-DIRTY!      CONSTANT _uidl-dirty-s-xt
' UIDL-CLEAN!      CONSTANT _uidl-clean-s-xt

: UIDL-ERR        _uidl-err-xt _uidl-guard WITH-GUARD ;
: UE.TYPE         _ue-dottype-xt _uidl-guard WITH-GUARD ;
: UE.FLAGS        _ue-dotflags-xt _uidl-guard WITH-GUARD ;
: UE.PARENT       _ue-dotparent-xt _uidl-guard WITH-GUARD ;
: UE.NEXT         _ue-dotnext-xt _uidl-guard WITH-GUARD ;
: UE.PREV         _ue-dotprev-xt _uidl-guard WITH-GUARD ;
: UE.FCHILD       _ue-dotfchild-xt _uidl-guard WITH-GUARD ;
: UE.LCHILD       _ue-dotlchild-xt _uidl-guard WITH-GUARD ;
: UE.NCHILD       _ue-dotnchild-xt _uidl-guard WITH-GUARD ;
: UE.ID-A         _ue-dotid-a-xt _uidl-guard WITH-GUARD ;
: UE.ID-L         _ue-dotid-l-xt _uidl-guard WITH-GUARD ;
: UE.ROLE-A       _ue-dotrole-a-xt _uidl-guard WITH-GUARD ;
: UE.ROLE-L       _ue-dotrole-l-xt _uidl-guard WITH-GUARD ;
: UE.ARRANGE      _ue-dotarrange-xt _uidl-guard WITH-GUARD ;
: UE.ATTR         _ue-dotattr-xt _uidl-guard WITH-GUARD ;
: UE.BIND-A       _ue-dotbind-a-xt _uidl-guard WITH-GUARD ;
: UE.BIND-L       _ue-dotbind-l-xt _uidl-guard WITH-GUARD ;
: UA.NEXT         _ua-dotnext-xt _uidl-guard WITH-GUARD ;
: UA.NAME-A       _ua-dotname-a-xt _uidl-guard WITH-GUARD ;
: UA.NAME-L       _ua-dotname-l-xt _uidl-guard WITH-GUARD ;
: UA.VAL-A        _ua-dotval-a-xt _uidl-guard WITH-GUARD ;
: UA.VAL-L        _ua-dotval-l-xt _uidl-guard WITH-GUARD ;
: UIDL-RESET      _uidl-reset-xt _uidl-guard WITH-GUARD ;
: UIDL-TYPE-NAME  _uidl-type-name-xt _uidl-guard WITH-GUARD ;
: UIDL-PARSE      _uidl-parse-xt _uidl-guard WITH-GUARD ;
: UIDL-ROOT       _uidl-root-xt _uidl-guard WITH-GUARD ;
: UIDL-ELEM-COUNT _uidl-elem-count-xt _uidl-guard WITH-GUARD ;
: UIDL-TYPE       _uidl-type-xt _uidl-guard WITH-GUARD ;
: UIDL-ID         _uidl-id-xt _uidl-guard WITH-GUARD ;
: UIDL-ROLE       _uidl-role-xt _uidl-guard WITH-GUARD ;
: UIDL-ARRANGE    _uidl-arrange-xt _uidl-guard WITH-GUARD ;
: UIDL-FLAGS      _uidl-flags-xt _uidl-guard WITH-GUARD ;
: UIDL-PARENT     _uidl-parent-xt _uidl-guard WITH-GUARD ;
: UIDL-FIRST-CHILD _uidl-first-child-xt _uidl-guard WITH-GUARD ;
: UIDL-LAST-CHILD _uidl-last-child-xt _uidl-guard WITH-GUARD ;
: UIDL-NEXT-SIB   _uidl-next-sib-xt _uidl-guard WITH-GUARD ;
: UIDL-PREV-SIB   _uidl-prev-sib-xt _uidl-guard WITH-GUARD ;
: UIDL-NCHILDREN  _uidl-nchildren-xt _uidl-guard WITH-GUARD ;
: UIDL-BIND       _uidl-bind-xt _uidl-guard WITH-GUARD ;
: UIDL-WHEN       _uidl-when-xt _uidl-guard WITH-GUARD ;
: UIDL-ATTR       _uidl-attr-xt _uidl-guard WITH-GUARD ;
: UIDL-ATTR-FIRST _uidl-attr-first-xt _uidl-guard WITH-GUARD ;
: UIDL-ATTR-NEXT  _uidl-attr-next-xt _uidl-guard WITH-GUARD ;
: UIDL-ATTR-NAME  _uidl-attr-name-xt _uidl-guard WITH-GUARD ;
: UIDL-ATTR-VAL   _uidl-attr-val-xt _uidl-guard WITH-GUARD ;
: UIDL-BY-ID      _uidl-by-id-xt _uidl-guard WITH-GUARD ;
: UIDL-BIND-EVAL  _uidl-bind-eval-xt _uidl-guard WITH-GUARD ;
: UIDL-EVAL-WHEN  _uidl-eval-when-xt _uidl-guard WITH-GUARD ;
: UIDL-TEMPLATE   _uidl-template-xt _uidl-guard WITH-GUARD ;
: UIDL-EMPTY-CHILD _uidl-empty-child-xt _uidl-guard WITH-GUARD ;
: UIDL-REP-COUNT  _uidl-rep-count-xt _uidl-guard WITH-GUARD ;
: UIDL-REP-BY-MOD _uidl-rep-by-mod-xt _uidl-guard WITH-GUARD ;
: UIDL-ERROR-COUNT _uidl-error-count-xt _uidl-guard WITH-GUARD ;
: UIDL-ERRORS-CLEAR _uidl-errors-clear-xt _uidl-guard WITH-GUARD ;
: UIDL-ERROR-NTH  _uidl-error-nth-xt _uidl-guard WITH-GUARD ;
: UIDL-VALIDATE   _uidl-validate-xt _uidl-guard WITH-GUARD ;
: UIDL-ADD-ELEM   _uidl-add-elem-xt _uidl-guard WITH-GUARD ;
: UIDL-REMOVE-ELEM _uidl-remove-elem-xt _uidl-guard WITH-GUARD ;
: UIDL-SET-ATTR   _uidl-set-attr-xt _uidl-guard WITH-GUARD ;
: UIDL-REMOVE-ATTR _uidl-remove-attr-xt _uidl-guard WITH-GUARD ;
: UIDL-MOVE-ELEM  _uidl-move-elem-xt _uidl-guard WITH-GUARD ;
: UIDL-BIND-WRITE _uidl-bind-write-xt _uidl-guard WITH-GUARD ;
: UIDL-DISPATCH   _uidl-dispatch-xt _uidl-guard WITH-GUARD ;
: UIDL-HAS-ACTION? _uidl-has-action-q-xt _uidl-guard WITH-GUARD ;
: UIDL-ACTION-VALUE _uidl-action-value-xt _uidl-guard WITH-GUARD ;
\ --- registry / subscription / dirty guarded ---
: DEFINE-ELEMENT   _define-element-xt _uidl-guard WITH-GUARD ;
: EL-LOOKUP        _el-lookup-xt _uidl-guard WITH-GUARD ;
: EL-DEF-BY-TYPE   _el-def-by-type-xt _uidl-guard WITH-GUARD ;
: ED.TYPE          _ed-dottype-xt _uidl-guard WITH-GUARD ;
: ED.NAME-A        _ed-dotname-a-xt _uidl-guard WITH-GUARD ;
: ED.NAME-L        _ed-dotname-l-xt _uidl-guard WITH-GUARD ;
: ED.FLAGS         _ed-dotflags-xt _uidl-guard WITH-GUARD ;
: ED.RENDER-XT     _ed-dotrender-xt-xt _uidl-guard WITH-GUARD ;
: ED.EVENT-XT      _ed-dotevent-xt-xt _uidl-guard WITH-GUARD ;
: ED.LAYOUT-XT     _ed-dotlayout-xt-xt _uidl-guard WITH-GUARD ;
: EL-CONTENT-MODEL _el-content-model-xt _uidl-guard WITH-GUARD ;
: EL-CATEGORY      _el-category-xt _uidl-guard WITH-GUARD ;
: EL-FOCUSABLE?    _el-focusable-q-xt _uidl-guard WITH-GUARD ;
: EL-SELF-CLOSE?   _el-self-close-q-xt _uidl-guard WITH-GUARD ;
: EL-TWOWAY?       _el-twoway-q-xt _uidl-guard WITH-GUARD ;
: UIDL-SUBSCRIBE   _uidl-subscribe-xt _uidl-guard WITH-GUARD ;
: UIDL-NOTIFY      _uidl-notify-xt _uidl-guard WITH-GUARD ;
: UIDL-RESET-SUBS  _uidl-reset-subs-xt _uidl-guard WITH-GUARD ;
: UIDL-DIRTY?      _uidl-dirty-q-xt _uidl-guard WITH-GUARD ;
: UIDL-DIRTY!      _uidl-dirty-s-xt _uidl-guard WITH-GUARD ;
: UIDL-CLEAN!      _uidl-clean-s-xt _uidl-guard WITH-GUARD ;
[THEN] [THEN]
