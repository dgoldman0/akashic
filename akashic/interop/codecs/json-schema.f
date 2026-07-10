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
        CV-T-F32 OF S" number" ENDOF
        CV-T-STRING OF S" string" ENDOF
        CV-T-BYTES OF S" string" ENDOF
        CV-T-LIST OF S" array" ENDOF
        CV-T-MAP OF S" object" ENDOF
        CV-T-RESOURCE OF S" string" ENDOF
        DROP S" object"
    ENDCASE ;

: _CSJ-TYPE-COUNT  ( mask -- count )
    _CSJ-MASK ! 0 _CSJ-COUNT !
    9 0 DO
        _CSJ-MASK @ I CS-TYPE-BIT AND IF 1 _CSJ-COUNT +! THEN
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
            DUP I CS-TYPE-BIT AND IF I _CSJ-TYPE-NAME JSON-ESTR THEN
        LOOP
        JSON-] DROP
    THEN ;

: _CSJE-CONSTRAINTS  ( -- )
    _CSJE-S@ CS.FLAGS @ CS-F-MIN AND IF
        S" minimum" _CSJE-S@ CS.MIN @ JSON-KV-NUM
    THEN
    _CSJE-S@ CS.FLAGS @ CS-F-MAX AND IF
        S" maximum" _CSJE-S@ CS.MAX @ JSON-KV-NUM
    THEN
    _CSJE-S@ CS.FLAGS @ CS-F-MAX-LEN AND IF
        _CSJE-S@ CS.TYPE-MASK @ CV-T-LIST CS-TYPE-BIT AND IF
            S" maxItems" _CSJE-S@ CS.MAX-LEN @ JSON-KV-NUM
        ELSE
            _CSJE-S@ CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
                S" maxProperties" _CSJE-S@ CS.MAX-LEN @ JSON-KV-NUM
            ELSE
                S" maxLength" _CSJE-S@ CS.MAX-LEN @ JSON-KV-NUM
            THEN
        THEN
    THEN
    _CSJE-S@ CS.TYPE-MASK @ CV-T-RESOURCE CS-TYPE-BIT AND IF
        S" format" S" uri" JSON-KV-ESTR
    THEN
    _CSJE-S@ CS.TYPE-MASK @ CV-T-BYTES CS-TYPE-BIT AND IF
        S" contentEncoding" S" base64" JSON-KV-ESTR
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

: CSJSON-WRITE  ( schema -- ior )
    DUP 0= IF DROP JSON-{ JSON-} 0 EXIT THEN
    -1 _CSJE-DEPTH ! 0 _CSJE-ERROR !
    _CSJE-SCHEMA
    _CSJE-ERROR @ ;

: CSJSON-NO-ARGS-WRITE  ( -- )
    JSON-{
    S" type" S" object" JSON-KV-ESTR
    S" additionalProperties" 0 JSON-KV-BOOL
    JSON-} ;

: CSJSON-INPUT-WRITE  ( schema -- ior )
    DUP 0= IF DROP CSJSON-NO-ARGS-WRITE 0 EXIT THEN
    DUP CS.TYPE-MASK @ CV-T-NULL CS-TYPE-BIT = IF
        DROP CSJSON-NO-ARGS-WRITE 0 EXIT
    THEN
    DUP CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
        CSJSON-WRITE EXIT
    THEN
    JSON-{
    S" type" S" object" JSON-KV-ESTR
    S" properties" JSON-KEY: JSON-{
        S" value" JSON-EKEY: DUP CSJSON-WRITE
        DUP IF NIP JSON-} JSON-} EXIT THEN DROP
    JSON-}
    S" required" JSON-KEY: JSON-[ S" value" JSON-ESTR JSON-]
    S" additionalProperties" 0 JSON-KV-BOOL
    DROP JSON-} 0 ;

VARIABLE _CSJE-BUF
VARIABLE _CSJE-CAP

: CSJSON-ENCODE  ( schema buffer capacity -- length ior )
    _CSJE-CAP ! _CSJE-BUF !
    JSON-BUILD-RESET
    _CSJE-BUF @ _CSJE-CAP @ JSON-SET-OUTPUT
    CSJSON-WRITE ?DUP IF 0 SWAP EXIT THEN
    JSON-OUTPUT-OK? 0= IF 0 IVJSON-E-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP 0 ;

: CSJSON-INPUT-ENCODE  ( schema buffer capacity -- length ior )
    _CSJE-CAP ! _CSJE-BUF !
    JSON-BUILD-RESET
    _CSJE-BUF @ _CSJE-CAP @ JSON-SET-OUTPUT
    CSJSON-INPUT-WRITE ?DUP IF 0 SWAP EXIT THEN
    JSON-OUTPUT-OK? 0= IF 0 IVJSON-E-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP 0 ;
