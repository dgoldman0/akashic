\ =====================================================================
\  schema-bytes.f - Canonical bytes for interoperability schemas
\ =====================================================================
\  One schema has exactly one byte form (docs/interop/schema-bytes.md),
\  so a digest of those bytes identifies it.  MEASURE validates a
\  document against an allowed-type mask and sizes the storage DECODE
\  needs; DECODE builds the CS graph in that storage.  Both refuse a
\  noncanonical document rather than normalizing it.  Their -CLOSED forms
\  also require every map and list a schema admits to be described.  The
\  CSBW words write a document for a producer such as the JSON reader.
\
\  The walks keep module scratch, so one guard serializes each family.
\ =====================================================================

PROVIDED akashic-ischema-bytes

REQUIRE ../schema.f
REQUIRE ../../text/utf8.f
REQUIRE ../../utils/memory-span.f
REQUIRE ../../concurrency/guard.f

1 CONSTANT CSB-E-INVALID
2 CONSTANT CSB-E-TYPE
3 CONSTANT CSB-E-DEPTH
4 CONSTANT CSB-E-CAPACITY
5 CONSTANT CSB-E-OPEN

\ Node flags: which optional parts follow the node header.
1  CONSTANT CSB-F-MIN
2  CONSTANT CSB-F-MAX
4  CONSTANT CSB-F-MAX-LEN
8  CONSTANT CSB-F-ITEM
16 CONSTANT CSB-F-FIELDS
31 CONSTANT _CSB-F-ALL

8 CONSTANT CSB-MAGIC-SIZE
: CSB-MAGIC  ( -- address length ) S" AKSCHEMA" ;

\ The types whose values have a length.
CV-T-STRING CS-TYPE-BIT CV-T-BYTES CS-TYPE-BIT OR
CV-T-RESOURCE CS-TYPE-BIT OR CV-T-LIST CS-TYPE-BIT OR
CV-T-MAP CS-TYPE-BIT OR CONSTANT _CSB-LENGTH-TYPES

: _CSB-U16@  ( address -- value ) DUP C@ SWAP 1+ C@ 8 LSHIFT OR ;
: _CSB-U32@  ( address -- value )
    DUP _CSB-U16@ SWAP 2 + _CSB-U16@ 16 LSHIFT OR ;
: _CSB-U64@  ( address -- value )
    DUP _CSB-U32@ SWAP 4 + _CSB-U32@ 32 LSHIFT OR ;

\ =====================================================================
\  Measuring
\ =====================================================================

VARIABLE _CSB-P
VARIABLE _CSB-END
VARIABLE _CSB-ALLOWED
VARIABLE _CSB-NODES
VARIABLE _CSB-FIELDS
VARIABLE _CSB-KEYS
VARIABLE _CSB-MIN
\ The node's maximum length, or -1 without one.
VARIABLE _CSB-LEN
\ True when every map and list must be described.
VARIABLE _CSB-CLOSED

\ The next N bytes, if the document holds them.
: _CSB-TAKE  ( n -- address flag )
    DUP _CSB-END @ _CSB-P @ - > IF DROP 0 0 EXIT THEN
    _CSB-P @ SWAP _CSB-P +! -1 ;

\ Each flag names a part the type mask can use.
: _CSB-FLAGS-FIT?  ( mask flags -- flag )
    DUP CSB-F-MIN CSB-F-MAX OR AND IF
        OVER CV-T-INT CS-TYPE-BIT AND 0= IF 2DROP 0 EXIT THEN
    THEN
    DUP CSB-F-MAX-LEN AND IF
        OVER _CSB-LENGTH-TYPES AND 0= IF 2DROP 0 EXIT THEN
    THEN
    DUP CSB-F-ITEM AND IF
        OVER CV-T-LIST CS-TYPE-BIT AND 0= IF 2DROP 0 EXIT THEN
    THEN
    DUP CSB-F-FIELDS AND IF
        OVER CV-T-MAP CS-TYPE-BIT AND 0= IF 2DROP 0 EXIT THEN
    THEN
    2DROP -1 ;

\ The bounds the flags name.  A bound at the cell's extreme is no bound,
\ so the canonical form never holds one.
: _CSB-MEASURE-BOUNDS  ( flags -- ior )
    -1 _CSB-LEN !
    DUP CSB-F-MIN AND IF
        8 _CSB-TAKE 0= IF 2DROP CSB-E-INVALID EXIT THEN
        _CSB-U64@ DUP CV-CELL-MIN = IF 2DROP CSB-E-INVALID EXIT THEN
        _CSB-MIN !
    THEN
    DUP CSB-F-MAX AND IF
        8 _CSB-TAKE 0= IF 2DROP CSB-E-INVALID EXIT THEN
        _CSB-U64@ DUP CV-CELL-MAX = IF 2DROP CSB-E-INVALID EXIT THEN
        OVER CSB-F-MIN AND IF
            DUP _CSB-MIN @ < IF 2DROP CSB-E-INVALID EXIT THEN
        THEN
        DROP
    THEN
    DUP CSB-F-MAX-LEN AND IF
        8 _CSB-TAKE 0= IF 2DROP CSB-E-INVALID EXIT THEN
        _CSB-U64@ DUP 0< IF 2DROP CSB-E-INVALID EXIT THEN
        _CSB-LEN !
    THEN
    DROP 0 ;

\ A closed node describes every value it admits: a map has its fields
\ and a list its item schema, unless the maximum length is zero.
: _CSB-CLOSED-NODE?  ( mask flags -- flag )
    _CSB-LEN @ 0= IF 2DROP -1 EXIT THEN
    OVER CV-T-MAP CS-TYPE-BIT AND IF
        DUP CSB-F-FIELDS AND 0= IF 2DROP 0 EXIT THEN
    THEN
    SWAP CV-T-LIST CS-TYPE-BIT AND IF CSB-F-ITEM AND 0<> ELSE DROP -1 THEN ;

DEFER _CSB-MEASURE-NODE  ( depth -- ior )

: _CSB-FIELD-FAIL  ( depth prev-a prev-u ior -- depth 0 0 ior )
    >R 2DROP 0 0 R> ;

\ One field: its key, strictly after the previous key, its required byte
\ and its schema.  PREV-U is -1 before the first field.
: _CSB-MEASURE-FIELD
  ( depth prev-a prev-u -- depth key-a key-u 0 | depth 0 0 ior )
    4 _CSB-TAKE 0= IF DROP CSB-E-INVALID _CSB-FIELD-FAIL EXIT THEN
    _CSB-U32@ DUP CV-MAX-STRING-LEN > IF
        DROP CSB-E-INVALID _CSB-FIELD-FAIL EXIT
    THEN
    DUP _CSB-TAKE 0= IF 2DROP CSB-E-INVALID _CSB-FIELD-FAIL EXIT THEN
    SWAP
    2DUP UTF8-VALID? 0= IF 2DROP CSB-E-INVALID _CSB-FIELD-FAIL EXIT THEN
    2 PICK 0< 0= IF
        2DUP 5 PICK 5 PICK COMPARE 0> 0= IF
            2DROP CSB-E-INVALID _CSB-FIELD-FAIL EXIT
        THEN
    THEN
    DUP _CSB-KEYS +!
    2SWAP 2DROP
    1 _CSB-TAKE 0= IF DROP CSB-E-INVALID _CSB-FIELD-FAIL EXIT THEN
    C@ 1 U> IF CSB-E-INVALID _CSB-FIELD-FAIL EXIT THEN
    2 PICK 1+ _CSB-MEASURE-NODE ?DUP IF _CSB-FIELD-FAIL EXIT THEN
    0 ;

: _CSB-MEASURE-FIELDS  ( depth -- ior )
    2 _CSB-TAKE 0= IF 2DROP CSB-E-INVALID EXIT THEN
    _CSB-U16@ DUP 1 < OVER CS-MAX-FIELDS > OR IF
        2DROP CSB-E-INVALID EXIT
    THEN
    DUP _CSB-FIELDS +!
    >R 0 -1 R>
    0 ?DO
        _CSB-MEASURE-FIELD ?DUP IF >R 2DROP DROP R> UNLOOP EXIT THEN
    LOOP
    2DROP DROP 0 ;

\ The node header is a u16 type mask, the flags byte and a zero byte.
: _CSB-MEASURE-NODE-R  ( depth -- ior )
    DUP CS-MAX-DEPTH >= IF DROP CSB-E-DEPTH EXIT THEN
    1 _CSB-NODES +!
    _CSB-NODES @ CS-MAX-NODES > IF DROP CSB-E-INVALID EXIT THEN
    4 _CSB-TAKE 0= IF 2DROP CSB-E-INVALID EXIT THEN
    DUP 3 + C@ IF 2DROP CSB-E-INVALID EXIT THEN
    DUP _CSB-U16@ SWAP 2 + C@
    OVER 0= 2 PICK CS-VALID-TYPE-MASK INVERT AND OR IF
        2DROP DROP CSB-E-INVALID EXIT
    THEN
    OVER _CSB-ALLOWED @ INVERT AND IF 2DROP DROP CSB-E-TYPE EXIT THEN
    DUP _CSB-F-ALL INVERT AND IF 2DROP DROP CSB-E-INVALID EXIT THEN
    2DUP _CSB-FLAGS-FIT? 0= IF 2DROP DROP CSB-E-INVALID EXIT THEN
    DUP _CSB-MEASURE-BOUNDS ?DUP IF NIP NIP NIP EXIT THEN
    _CSB-CLOSED @ IF
        2DUP _CSB-CLOSED-NODE? 0= IF 2DROP DROP CSB-E-OPEN EXIT THEN
    THEN
    NIP
    DUP CSB-F-ITEM AND IF
        OVER 1+ _CSB-MEASURE-NODE ?DUP IF NIP NIP EXIT THEN
    THEN
    CSB-F-FIELDS AND IF _CSB-MEASURE-FIELDS EXIT THEN
    DROP 0 ;

' _CSB-MEASURE-NODE-R IS _CSB-MEASURE-NODE

: _CSB-STORAGE-U  ( -- bytes )
    _CSB-NODES @ CS-SIZE *
    _CSB-FIELDS @ CS-FIELD-SIZE * +
    _CSB-KEYS @ 7 + -8 AND + ;

\ Validates DOCUMENT as one canonical schema whose every type is in
\ TYPE-MASK, and returns the storage DECODE needs for its graph.
: _CSB-MEASURE  ( document document-u type-mask -- storage-u ior )
    _CSB-ALLOWED !
    DUP CSB-MAGIC-SIZE < IF 2DROP 0 CSB-E-INVALID EXIT THEN
    OVER 0= IF 2DROP 0 CSB-E-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 CSB-E-INVALID EXIT THEN
    OVER CSB-MAGIC-SIZE CSB-MAGIC COMPARE IF
        2DROP 0 CSB-E-INVALID EXIT
    THEN
    OVER + _CSB-END !
    CSB-MAGIC-SIZE + _CSB-P !
    0 _CSB-NODES ! 0 _CSB-FIELDS ! 0 _CSB-KEYS !
    0 _CSB-MEASURE-NODE ?DUP IF 0 SWAP EXIT THEN
    _CSB-P @ _CSB-END @ <> IF 0 CSB-E-INVALID EXIT THEN
    _CSB-STORAGE-U 0 ;

\ =====================================================================
\  Decoding
\ =====================================================================

VARIABLE _CSB-DOC
VARIABLE _CSB-NODE-NEXT
VARIABLE _CSB-FIELD-NEXT
VARIABLE _CSB-KEY-NEXT

DEFER _CSB-DECODE-NODE  ( -- schema )

\ A map's whole field array is reserved before any child is decoded, so
\ each map's fields stay contiguous.
: _CSB-DECODE-FIELDS  ( schema -- )
    _CSB-P @ _CSB-U16@ 2 _CSB-P +!
    2DUP SWAP CS.FIELD-N !
    _CSB-FIELD-NEXT @ ROT CS.FIELDS !
    _CSB-FIELD-NEXT @ SWAP
    DUP CS-FIELD-SIZE * _CSB-FIELD-NEXT +!
    0 ?DO
        DUP I CS-FIELD-SIZE * +
        _CSB-P @ _CSB-U32@ 4 _CSB-P +!
        2DUP SWAP CSF.KEY-U !
        _CSB-KEY-NEXT @ 2 PICK CSF.KEY-A !
        _CSB-P @ _CSB-KEY-NEXT @ 2 PICK MOVE
        DUP _CSB-P +! _CSB-KEY-NEXT +!
        _CSB-P @ C@ IF CSF-F-REQUIRED ELSE 0 THEN OVER CSF.FLAGS !
        1 _CSB-P +!
        _CSB-DECODE-NODE SWAP CSF.SCHEMA !
    LOOP
    DROP ;

\ Trusts a document MEASURE has admitted.
: _CSB-DECODE-NODE-R  ( -- schema )
    _CSB-NODE-NEXT @ CS-SIZE _CSB-NODE-NEXT +!
    DUP CS-INIT
    _CSB-P @ _CSB-U16@ OVER CS-ALLOW-MASK!
    _CSB-P @ 2 + C@ 4 _CSB-P +!
    DUP CSB-F-MIN AND IF
        _CSB-P @ _CSB-U64@ 8 _CSB-P +! 2 PICK CS-MIN!
    THEN
    DUP CSB-F-MAX AND IF
        _CSB-P @ _CSB-U64@ 8 _CSB-P +! 2 PICK CS-MAX!
    THEN
    DUP CSB-F-MAX-LEN AND IF
        _CSB-P @ _CSB-U64@ 8 _CSB-P +! 2 PICK CS-MAX-LEN!
    THEN
    DUP CSB-F-ITEM AND IF _CSB-DECODE-NODE 2 PICK CS.ITEM ! THEN
    CSB-F-FIELDS AND IF DUP _CSB-DECODE-FIELDS THEN ;

' _CSB-DECODE-NODE-R IS _CSB-DECODE-NODE

\ Decodes DOCUMENT into STORAGE, at least the measured size, cell-aligned
\ and disjoint from DOCUMENT, and returns the root schema.  The graph
\ copies every key and borrows nothing from DOCUMENT.
: _CSB-DECODE
  ( document document-u type-mask storage storage-u -- schema|0 ior )
    4 PICK 4 PICK 3 PICK 3 PICK MSPAN-OVERLAP? IF
        2DROP 2DROP DROP 0 CSB-E-INVALID EXIT
    THEN
    2>R
    2 PICK _CSB-DOC !
    _CSB-MEASURE ?DUP IF NIP 2R> 2DROP 0 SWAP EXIT THEN
    2R>
    ROT U< IF DROP 0 CSB-E-CAPACITY EXIT THEN
    DUP 0= OVER 7 AND OR IF DROP 0 CSB-E-INVALID EXIT THEN
    DUP _CSB-NODE-NEXT !
    _CSB-NODES @ CS-SIZE * + DUP _CSB-FIELD-NEXT !
    _CSB-FIELDS @ CS-FIELD-SIZE * + _CSB-KEY-NEXT !
    _CSB-DOC @ CSB-MAGIC-SIZE + _CSB-P !
    _CSB-DECODE-NODE 0 ;

\ =====================================================================
\  Writing
\ =====================================================================
\  A producer begins a document in its buffer, writes it in order, and
\  ends it.  The first capacity failure is kept and later writes do
\  nothing.

VARIABLE _CSBW-A
VARIABLE _CSBW-CAP
VARIABLE _CSBW-U
VARIABLE _CSBW-ERR

: _CSBW-ROOM  ( n -- address flag )
    _CSBW-ERR @ IF DROP 0 0 EXIT THEN
    DUP _CSBW-CAP @ _CSBW-U @ - > IF
        DROP CSB-E-CAPACITY _CSBW-ERR ! 0 0 EXIT
    THEN
    _CSBW-A @ _CSBW-U @ + SWAP _CSBW-U +! -1 ;

: CSBW-BYTES  ( address length -- )
    DUP _CSBW-ROOM IF SWAP MOVE ELSE 2DROP DROP THEN ;

: CSBW-U8  ( value -- ) 1 _CSBW-ROOM IF C! ELSE 2DROP THEN ;

: CSBW-U16  ( value -- )
    2 _CSBW-ROOM IF 2DUP C! SWAP 8 RSHIFT SWAP 1+ C! ELSE 2DROP THEN ;

: CSBW-U32  ( value -- ) DUP CSBW-U16 16 RSHIFT CSBW-U16 ;
: CSBW-U64  ( value -- ) DUP CSBW-U32 32 RSHIFT CSBW-U32 ;

: CSBW-BEGIN  ( buffer capacity -- )
    _CSBW-CAP ! _CSBW-A ! 0 _CSBW-U ! 0 _CSBW-ERR !
    CSB-MAGIC CSBW-BYTES ;

\ Records the producer's own failure; the first one is kept.
: CSBW-FAIL  ( ior -- )
    _CSBW-ERR @ IF DROP ELSE _CSBW-ERR ! THEN ;

: CSBW-FAILED?  ( -- flag ) _CSBW-ERR @ 0<> ;

: CSBW-END  ( -- length ior )
    _CSBW-ERR @ ?DUP IF 0 SWAP ELSE _CSBW-U @ 0 THEN ;

: _CSB-MEASURE-ANY  ( document document-u type-mask -- storage-u ior )
    0 _CSB-CLOSED ! _CSB-MEASURE ;
: _CSB-MEASURE-CLOSED  ( document document-u type-mask -- storage-u ior )
    -1 _CSB-CLOSED ! _CSB-MEASURE ;
: _CSB-DECODE-ANY
  ( document document-u type-mask storage storage-u -- schema|0 ior )
    0 _CSB-CLOSED ! _CSB-DECODE ;
: _CSB-DECODE-CLOSED
  ( document document-u type-mask storage storage-u -- schema|0 ior )
    -1 _CSB-CLOSED ! _CSB-DECODE ;

GUARD _csb-guard
' _CSB-MEASURE-ANY CONSTANT _csb-measure-xt
' _CSB-MEASURE-CLOSED CONSTANT _csb-measure-closed-xt
' _CSB-DECODE-ANY CONSTANT _csb-decode-xt
' _CSB-DECODE-CLOSED CONSTANT _csb-decode-closed-xt
: CSB-MEASURE  ( document document-u type-mask -- storage-u ior )
    _csb-measure-xt _csb-guard WITH-GUARD ;
: CSB-MEASURE-CLOSED  ( document document-u type-mask -- storage-u ior )
    _csb-measure-closed-xt _csb-guard WITH-GUARD ;
: CSB-DECODE
  ( document document-u type-mask storage storage-u -- schema|0 ior )
    _csb-decode-xt _csb-guard WITH-GUARD ;
: CSB-DECODE-CLOSED
  ( document document-u type-mask storage storage-u -- schema|0 ior )
    _csb-decode-closed-xt _csb-guard WITH-GUARD ;
