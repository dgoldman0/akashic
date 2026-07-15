\ =====================================================================
\  json-schema.f - JSON Schema projection for interoperability schemas
\ =====================================================================
\  CS descriptors remain the source of truth. This module projects their
\  bounded type, range, length, item, and map-field contracts to JSON Schema
\  for protocol adapters and provider tool definitions.
\ =====================================================================

PROVIDED akashic-ischema-json-codec

REQUIRE json-value.f

VARIABLE _CSJ-MASK
VARIABLE _CSJ-COUNT

: _CSJ-TYPE-NAME  ( cv-type -- addr len )
    CASE
        CV-T-NULL OF S" null" ENDOF
        CV-T-BOOL OF S" boolean" ENDOF
        CV-T-INT OF S" integer" ENDOF
        CV-T-STRING OF S" string" ENDOF
        CV-T-LIST OF S" array" ENDOF
        CV-T-MAP OF S" object" ENDOF
        CV-T-RESOURCE OF S" string" ENDOF
        DROP S" object"
    ENDCASE ;

: _CSJ-TYPE-COUNT  ( mask -- count )
    _CSJ-MASK ! 0 _CSJ-COUNT !
    9 0 DO
        _CSJ-MASK @ I CS-TYPE-BIT AND IF
            \ STRING and RESOURCE share JSON's string primitive.  If both
            \ are allowed, emit that primitive once rather than a duplicate
            \ entry in the type array.
            I CV-T-RESOURCE =
            _CSJ-MASK @ CV-T-STRING CS-TYPE-BIT AND 0<> AND 0= IF
                1 _CSJ-COUNT +!
            THEN
        THEN
    LOOP
    _CSJ-COUNT @ ;

: _CSJ-FIRST-TYPE  ( mask -- type )
    9 0 DO
        DUP I CS-TYPE-BIT AND IF DROP I UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

CREATE _CSJEF-S IVJSON-MAX-DEPTH 8 * ALLOT
VARIABLE _CSJE-DEPTH
VARIABLE _CSJE-ERROR
VARIABLE _CSJE-STRUCTURAL

: _CSJSON-SCHEMA-IOR>IVJSON  ( cs-ior -- ivjson-ior )
    DUP CS-E-DEPTH = IF DROP IVJSON-E-DEPTH EXIT THEN
    CS-E-CAPACITY = IF IVJSON-E-CAPACITY ELSE IVJSON-E-TYPE THEN ;

\ Validate before the first builder write.  Besides preventing projection
\ from walking malformed child pointers, compatibility rejects native CV
\ alternatives for which IVJSON has no canonical wire form.  A null schema
\ remains the explicit unconstrained/no-arguments projection handled by the
\ public entry points below.
: _CSJSON-PREFLIGHT  ( schema -- ior )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CS-SCHEMA-VALIDATE ?DUP IF
        NIP _CSJSON-SCHEMA-IOR>IVJSON EXIT
    THEN
    IVJSON-SCHEMA-COMPATIBLE? 0= IF
        IVJSON-E-UNSUPPORTED
    ELSE
        0
    THEN ;

: _CSJE-SLOT  ( -- address )
    _CSJEF-S _CSJE-DEPTH @ 8 * + ;

: _CSJE-S@  ( -- schema ) _CSJE-SLOT @ ;
: _CSJE-S!  ( schema -- ) _CSJE-SLOT ! ;

DEFER _CSJE-SCHEMA

: _CSJE-TYPES  ( -- )
    _CSJE-S@ CS.TYPE-MASK @ DUP _CSJ-TYPE-COUNT DUP 0= IF
        2DROP IVJSON-E-TYPE _CSJE-ERROR ! EXIT
    THEN
    1 = IF
        S" type" JSON-KEY: _CSJ-FIRST-TYPE _CSJ-TYPE-NAME JSON-ESTR
    ELSE
        S" type" JSON-KEY: JSON-[
        9 0 DO
            DUP I CS-TYPE-BIT AND IF
                I CV-T-RESOURCE =
                OVER CV-T-STRING CS-TYPE-BIT AND 0<> AND 0= IF
                    I _CSJ-TYPE-NAME JSON-ESTR
                THEN
            THEN
        LOOP
        JSON-] DROP
    THEN ;

: _CSJE-CONSTRAINTS  ( -- )
    _CSJE-S@ CS.TYPE-MASK @ CV-T-INT CS-TYPE-BIT AND IF
        S" minimum"
        _CSJE-S@ CS.FLAGS @ CS-F-MIN AND IF
            _CSJE-S@ CS.MIN @
        ELSE
            CV-CELL-MIN
        THEN
        JSON-KV-NUM
        S" maximum"
        _CSJE-S@ CS.FLAGS @ CS-F-MAX AND IF
            _CSJE-S@ CS.MAX @
        ELSE
            CV-CELL-MAX
        THEN
        JSON-KV-NUM
    THEN
    _CSJE-S@ CS.FLAGS @ CS-F-MAX-LEN AND IF
        _CSJE-S@ CS.TYPE-MASK @ CV-T-LIST CS-TYPE-BIT AND IF
            S" maxItems" _CSJE-S@ CS.MAX-LEN @ JSON-KV-NUM
        THEN
        _CSJE-S@ CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
            S" maxProperties" _CSJE-S@ CS.MAX-LEN @ JSON-KV-NUM
        THEN
        _CSJE-S@ CS.TYPE-MASK @
            CV-T-STRING CS-TYPE-BIT CV-T-RESOURCE CS-TYPE-BIT OR AND IF
            S" maxLength" _CSJE-S@ CS.MAX-LEN @ JSON-KV-NUM
        THEN
    THEN ;

: _CSJE-ITEMS  ( -- )
    _CSJE-S@ CS.TYPE-MASK @ CV-T-LIST CS-TYPE-BIT AND 0= IF EXIT THEN
    _CSJE-S@ CS.ITEM @ ?DUP IF
        S" items" JSON-KEY: _CSJE-SCHEMA
    THEN ;

: _CSJE-PROPERTIES  ( -- )
    _CSJE-S@ CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND 0= IF EXIT THEN
    _CSJE-S@ CS.FIELD-N @ 0= IF EXIT THEN
    S" properties" JSON-KEY: JSON-{
    _CSJE-S@ CS.FIELD-N @ 0 ?DO
        _CSJE-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP
        DUP CSF.KEY-A @ SWAP CSF.KEY-U @ JSON-EKEY:
        CSF.SCHEMA @ _CSJE-SCHEMA
        _CSJE-ERROR @ IF LEAVE THEN
    LOOP
    JSON-}
    _CSJE-ERROR @ IF EXIT THEN
    S" required" JSON-KEY: JSON-[
    _CSJE-S@ CS.FIELD-N @ 0 ?DO
        _CSJE-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP CSF.FLAGS @
        CSF-F-REQUIRED AND IF
            DUP CSF.KEY-A @ SWAP CSF.KEY-U @ JSON-ESTR
        ELSE
            DROP
        THEN
    LOOP
    JSON-]
    S" additionalProperties" 0 JSON-KV-BOOL ;

: _CSJE-SCHEMA-R  ( schema -- )
    _CSJE-ERROR @ IF DROP EXIT THEN
    1 _CSJE-DEPTH +!
    _CSJE-DEPTH @ IVJSON-MAX-DEPTH >= IF
        DROP IVJSON-E-DEPTH _CSJE-ERROR ! -1 _CSJE-DEPTH +! EXIT
    THEN
    _CSJE-S!
    JSON-{
    _CSJE-TYPES
    _CSJE-ERROR @ 0= IF _CSJE-CONSTRAINTS THEN
    _CSJE-ERROR @ 0= IF _CSJE-ITEMS THEN
    _CSJE-ERROR @ 0= IF _CSJE-PROPERTIES THEN
    JSON-}
    -1 _CSJE-DEPTH +! ;

' _CSJE-SCHEMA-R IS _CSJE-SCHEMA

: _CSJSON-WRITE  ( schema -- ior )
    DUP _CSJSON-PREFLIGHT ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP JSON-{ JSON-} 0 EXIT THEN
    -1 _CSJE-DEPTH ! 0 _CSJE-ERROR !
    _CSJE-SCHEMA
    _CSJE-ERROR @ ;

: CSJSON-WRITE  ( schema -- ior )
    0 _CSJE-STRUCTURAL ! _CSJSON-WRITE ;

: CSJSON-STRUCTURAL-WRITE  ( schema -- ior )
    -1 _CSJE-STRUCTURAL ! _CSJSON-WRITE 0 _CSJE-STRUCTURAL ! ;

: CSJSON-NO-ARGS-WRITE  ( -- )
    JSON-{
    S" type" S" object" JSON-KV-ESTR
    S" properties" JSON-KEY: JSON-{ JSON-}
    S" required" JSON-KEY: JSON-[ JSON-]
    S" additionalProperties" 0 JSON-KV-BOOL
    JSON-} ;

\ OpenAI strict function schemas require every declared object property to be
\ required. The ordinary projection preserves optional Akashic fields, so
\ protocol adapters can use this predicate to enable strict mode only when the
\ source schema actually satisfies that stronger contract.
\ ( schema depth -- flag )
: _CSJSON-STRICT-R?
    DUP IVJSON-MAX-DEPTH >= IF 2DROP 0 EXIT THEN
    >R
    DUP 0= IF DROP R> DROP -1 EXIT THEN
    DUP CS.TYPE-MASK @ CV-T-LIST CS-TYPE-BIT AND IF
        DUP CS.ITEM @ ?DUP IF
            R@ 1+ RECURSE 0= IF DROP R> DROP 0 EXIT THEN
        THEN
    THEN
    DUP CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
        DUP CS.FIELD-N @ 0 ?DO
            DUP CS.FIELDS @ I CS-FIELD-SIZE * + DUP CSF.FLAGS @
            CSF-F-REQUIRED AND 0= IF
                2DROP R> DROP 0 UNLOOP EXIT
            THEN
            CSF.SCHEMA @ R@ 1+ RECURSE 0= IF
                DROP R> DROP 0 UNLOOP EXIT
            THEN
        LOOP
    THEN
    DROP R> DROP -1 ;

\ ( schema -- flag )
: CSJSON-STRICT?
    DUP 0= IF DROP -1 EXIT THEN
    DUP _CSJSON-PREFLIGHT IF DROP 0 EXIT THEN
    0 _CSJSON-STRICT-R? ;

: _CSJSON-INPUT-WRITE  ( schema -- ior )
    DUP _CSJSON-PREFLIGHT ?DUP IF NIP EXIT THEN
    DUP 0= IF DROP CSJSON-NO-ARGS-WRITE 0 EXIT THEN
    DUP CS.TYPE-MASK @ CV-T-NULL CS-TYPE-BIT = IF
        DROP CSJSON-NO-ARGS-WRITE 0 EXIT
    THEN
    DUP CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
        _CSJSON-WRITE EXIT
    THEN
    JSON-{
    S" type" S" object" JSON-KV-ESTR
    S" properties" JSON-KEY: JSON-{
        S" value" JSON-EKEY: DUP _CSJSON-WRITE
        DUP IF NIP JSON-} JSON-} EXIT THEN DROP
    JSON-}
    S" required" JSON-KEY: JSON-[ S" value" JSON-ESTR JSON-]
    S" additionalProperties" 0 JSON-KV-BOOL
    DROP JSON-} 0 ;

: CSJSON-INPUT-WRITE  ( schema -- ior )
    0 _CSJE-STRUCTURAL ! _CSJSON-INPUT-WRITE ;

: CSJSON-STRUCTURAL-INPUT-WRITE  ( schema -- ior )
    -1 _CSJE-STRUCTURAL ! _CSJSON-INPUT-WRITE 0 _CSJE-STRUCTURAL ! ;

GUARD _csjson-guard
' CSJSON-WRITE CONSTANT _csjson-write-xt
' CSJSON-STRUCTURAL-WRITE CONSTANT _csjson-structural-write-xt
' CSJSON-INPUT-WRITE CONSTANT _csjson-input-write-xt
' CSJSON-STRUCTURAL-INPUT-WRITE CONSTANT _csjson-structural-input-write-xt

: _CSJSON-WRITE-GUARDED
    _csjson-write-xt _csjson-guard WITH-GUARD ;
: _CSJSON-STRUCTURAL-WRITE-GUARDED
    _csjson-structural-write-xt _csjson-guard WITH-GUARD ;
: _CSJSON-INPUT-WRITE-GUARDED
    _csjson-input-write-xt _csjson-guard WITH-GUARD ;
: _CSJSON-STRUCTURAL-INPUT-WRITE-GUARDED
    _csjson-structural-input-write-xt _csjson-guard WITH-GUARD ;

\ Keep one lock order for embedded and standalone encoders: the JSON
\ builder is always outermost, followed by the schema encoder's frames.
: CSJSON-WRITE
    ['] _CSJSON-WRITE-GUARDED JSON-WITH-BUILDER ;
: CSJSON-STRUCTURAL-WRITE
    ['] _CSJSON-STRUCTURAL-WRITE-GUARDED JSON-WITH-BUILDER ;
: CSJSON-INPUT-WRITE
    ['] _CSJSON-INPUT-WRITE-GUARDED JSON-WITH-BUILDER ;
: CSJSON-STRUCTURAL-INPUT-WRITE
    ['] _CSJSON-STRUCTURAL-INPUT-WRITE-GUARDED JSON-WITH-BUILDER ;

VARIABLE _CSJE-BUF
VARIABLE _CSJE-CAP

: _CSJSON-ENCODE  ( schema buffer capacity -- length ior )
    _CSJE-CAP ! _CSJE-BUF !
    JSON-BUILD-RESET
    _CSJE-BUF @ _CSJE-CAP @ JSON-SET-OUTPUT
    CSJSON-WRITE ?DUP IF 0 SWAP EXIT THEN
    JSON-OUTPUT-OK? 0= IF 0 IVJSON-E-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP 0 ;

: _CSJSON-INPUT-ENCODE  ( schema buffer capacity -- length ior )
    _CSJE-CAP ! _CSJE-BUF !
    JSON-BUILD-RESET
    _CSJE-BUF @ _CSJE-CAP @ JSON-SET-OUTPUT
    CSJSON-INPUT-WRITE ?DUP IF 0 SWAP EXIT THEN
    JSON-OUTPUT-OK? 0= IF 0 IVJSON-E-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP 0 ;

: _CSJSON-STRUCTURAL-INPUT-ENCODE  ( schema buffer capacity -- length ior )
    _CSJE-CAP ! _CSJE-BUF !
    JSON-BUILD-RESET
    _CSJE-BUF @ _CSJE-CAP @ JSON-SET-OUTPUT
    CSJSON-STRUCTURAL-INPUT-WRITE ?DUP IF 0 SWAP EXIT THEN
    JSON-OUTPUT-OK? 0= IF 0 IVJSON-E-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP 0 ;

: _CSJSON-ENCODE-CSJSON-GUARDED
    ['] _CSJSON-ENCODE _csjson-guard WITH-GUARD ;
: _CSJSON-INPUT-ENCODE-CSJSON-GUARDED
    ['] _CSJSON-INPUT-ENCODE _csjson-guard WITH-GUARD ;
: _CSJSON-STRUCTURAL-INPUT-ENCODE-CSJSON-GUARDED
    ['] _CSJSON-STRUCTURAL-INPUT-ENCODE _csjson-guard WITH-GUARD ;

: CSJSON-ENCODE
    ['] _CSJSON-ENCODE-CSJSON-GUARDED JSON-WITH-BUILDER ;
: CSJSON-INPUT-ENCODE
    ['] _CSJSON-INPUT-ENCODE-CSJSON-GUARDED JSON-WITH-BUILDER ;
: CSJSON-STRUCTURAL-INPUT-ENCODE
    ['] _CSJSON-STRUCTURAL-INPUT-ENCODE-CSJSON-GUARDED
        JSON-WITH-BUILDER ;
