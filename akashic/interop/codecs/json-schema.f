\ =====================================================================
\  json-schema.f - JSON Schema projection for interoperability schemas
\ =====================================================================
\  CS descriptors remain the source of truth. This module projects their
\  bounded type, range, length, item, and map-field contracts to JSON Schema
\  for protocol adapters and provider tool definitions, and reads that same
\  JSON form back into canonical schema bytes (docs/interop/schema-bytes.md).
\ =====================================================================

PROVIDED akashic-ischema-json-codec

REQUIRE json-value.f
REQUIRE schema-bytes.f

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

\ =====================================================================
\  Reading the JSON form
\ =====================================================================
\  CSJSON-READ accepts the JSON Schema form this module writes and writes
\  its canonical schema bytes.  Each schema is an object whose "type" is a
\  name, or an array of distinct names, from null, boolean, integer,
\  string, array and object.  "minimum" and "maximum" bound an integer; a
\  bound at the cell's extreme is no bound and is dropped.  "maxLength",
\  "maxItems" and "maxProperties" give the one maximum length: each the
\  type allows must be present when any is, and all must agree.  "items"
\  describes a list's items.  "properties", with "required" and
\  "additionalProperties": false, closes a map; without them a map is
\  open.  A "description" string is ignored, and any other key is refused.
\  Like the writer, the reader takes only what JSON can carry: a list of at
\  most IVJSON-MAX-CHILDREN items, empty when its items are unconstrained,
\  and an open map only when it is empty.  The bytes are never longer than
\  the JSON text plus CSB-MAGIC-SIZE.

VARIABLE _CSJR-ERR
VARIABLE _CSJR-MAP
VARIABLE _CSJR-MASKV
VARIABLE _CSJR-FLAGS
VARIABLE _CSJR-MIN-V
VARIABLE _CSJR-MAX-V
VARIABLE _CSJR-LEN
VARIABLE _CSJR-MISSING
VARIABLE _CSJR-KA
VARIABLE _CSJR-KU
CREATE _CSJR-ROOT CV-SIZE ALLOT
_CSJR-ROOT CV-INIT

: _CSJR-FAIL  ( ior -- ) _CSJR-ERR @ IF DROP ELSE _CSJR-ERR ! THEN ;
: _CSJR-FLAG+  ( flag -- ) _CSJR-FLAGS @ OR _CSJR-FLAGS ! ;
: _CSJR-STRING$  ( value -- address length ) DUP CV-DATA@ SWAP CV-LEN@ ;
: _CSJR-FIELD  ( key-a key-u -- value|0 ) _CSJR-MAP @ CV-MAP-FIND ;

: _CSJR-INT  ( value -- n flag )
    DUP CV-TYPE@ CV-T-INT = IF CV-DATA@ -1 ELSE DROP 0 0 THEN ;

: _CSJR-TYPE-BIT  ( name-a name-u -- bit|0 )
    2DUP S" null" COMPARE 0= IF 2DROP CV-T-NULL CS-TYPE-BIT EXIT THEN
    2DUP S" boolean" COMPARE 0= IF 2DROP CV-T-BOOL CS-TYPE-BIT EXIT THEN
    2DUP S" integer" COMPARE 0= IF 2DROP CV-T-INT CS-TYPE-BIT EXIT THEN
    2DUP S" string" COMPARE 0= IF 2DROP CV-T-STRING CS-TYPE-BIT EXIT THEN
    2DUP S" array" COMPARE 0= IF 2DROP CV-T-LIST CS-TYPE-BIT EXIT THEN
    S" object" COMPARE 0= IF CV-T-MAP CS-TYPE-BIT ELSE 0 THEN ;

\ The type mask a "type" value names, or 0.
: _CSJR-MASK  ( type-value|0 -- mask|0 )
    DUP 0= IF EXIT THEN
    DUP CV-TYPE@ CV-T-STRING = IF _CSJR-STRING$ _CSJR-TYPE-BIT EXIT THEN
    DUP CV-TYPE@ CV-T-LIST <> IF DROP 0 EXIT THEN
    DUP CV-LEN@ 0= IF DROP 0 EXIT THEN
    0 OVER CV-LEN@ 0 ?DO
        I 2 PICK CV-LIST-NTH
        DUP CV-TYPE@ CV-T-STRING <> IF 2DROP DROP 0 UNLOOP EXIT THEN
        _CSJR-STRING$ _CSJR-TYPE-BIT
        DUP 0= OVER 3 PICK AND OR IF 2DROP DROP 0 UNLOOP EXIT THEN
        OR
    LOOP
    NIP ;

: _CSJR-KEY-KNOWN?  ( key-a key-u -- flag )
    2DUP S" type" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" minimum" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" maximum" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" maxLength" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" maxItems" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" maxProperties" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" items" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" properties" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" required" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" additionalProperties" COMPARE 0= IF 2DROP -1 EXIT THEN
    S" description" COMPARE 0= ;

: _CSJR-KEYS-KNOWN?  ( map -- flag )
    DUP CV-LEN@ 0 ?DO
        I OVER CV-MAP-NTH CV-MAP-KEY _CSJR-STRING$
        _CSJR-KEY-KNOWN? 0= IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ One integer bound, allowed only when the type has integers.
: _CSJR-BOUND  ( key-a key-u -- n present ior )
    _CSJR-FIELD ?DUP 0= IF 0 0 0 EXIT THEN
    _CSJR-MASKV @ CV-T-INT CS-TYPE-BIT AND 0= IF
        DROP 0 0 IVJSON-E-TYPE EXIT
    THEN
    _CSJR-INT 0= IF DROP 0 0 IVJSON-E-TYPE EXIT THEN
    -1 0 ;

: _CSJR-BOUNDS  ( -- ior )
    S" minimum" _CSJR-BOUND ?DUP IF NIP NIP EXIT THEN
    IF
        DUP CV-CELL-MIN <> IF
            _CSJR-MIN-V ! CSB-F-MIN _CSJR-FLAG+
        ELSE DROP THEN
    ELSE DROP THEN
    S" maximum" _CSJR-BOUND ?DUP IF NIP NIP EXIT THEN
    IF
        DUP CV-CELL-MAX <> IF
            _CSJR-MAX-V ! CSB-F-MAX _CSJR-FLAG+
        ELSE DROP THEN
    ELSE DROP THEN
    _CSJR-FLAGS @ CSB-F-MIN CSB-F-MAX OR AND
        CSB-F-MIN CSB-F-MAX OR = IF
        _CSJR-MIN-V @ _CSJR-MAX-V @ > IF IVJSON-E-TYPE EXIT THEN
    THEN
    0 ;

\ One length key: allowed only where TYPE is in the mask, a nonnegative
\ integer, and equal to every other length key present.
: _CSJR-LEN-KEY  ( key-a key-u type -- ior )
    CS-TYPE-BIT _CSJR-MASKV @ AND >R
    _CSJR-FIELD ?DUP 0= IF
        R> IF 1 _CSJR-MISSING +! THEN 0 EXIT
    THEN
    R> 0= IF DROP IVJSON-E-TYPE EXIT THEN
    _CSJR-INT 0= IF DROP IVJSON-E-TYPE EXIT THEN
    DUP 0< IF DROP IVJSON-E-TYPE EXIT THEN
    _CSJR-LEN @ DUP 0< IF DROP _CSJR-LEN ! 0 EXIT THEN
    <> IF IVJSON-E-TYPE EXIT THEN
    0 ;

: _CSJR-LENGTHS  ( -- ior )
    -1 _CSJR-LEN ! 0 _CSJR-MISSING !
    S" maxLength" CV-T-STRING _CSJR-LEN-KEY ?DUP IF EXIT THEN
    S" maxItems" CV-T-LIST _CSJR-LEN-KEY ?DUP IF EXIT THEN
    S" maxProperties" CV-T-MAP _CSJR-LEN-KEY ?DUP IF EXIT THEN
    _CSJR-LEN @ 0< 0= _CSJR-MISSING @ 0> AND IF IVJSON-E-TYPE EXIT THEN
    0 ;

\ Checks the schema's own keys and fills the node's mask, flags and
\ bounds.
: _CSJR-HEAD  ( -- ior )
    _CSJR-MAP @ _CSJR-KEYS-KNOWN? 0= IF IVJSON-E-UNSUPPORTED EXIT THEN
    S" description" _CSJR-FIELD ?DUP IF
        CV-TYPE@ CV-T-STRING <> IF IVJSON-E-TYPE EXIT THEN
    THEN
    S" type" _CSJR-FIELD _CSJR-MASK ?DUP 0= IF
        IVJSON-E-UNSUPPORTED EXIT
    THEN
    _CSJR-MASKV !
    0 _CSJR-FLAGS !
    _CSJR-BOUNDS ?DUP IF EXIT THEN
    _CSJR-LENGTHS ?DUP IF EXIT THEN
    _CSJR-LEN @ 0< 0= IF CSB-F-MAX-LEN _CSJR-FLAG+ THEN
    0 ;

: _CSJR-REQUIRED-SEEN?  ( index list -- flag )
    2DUP CV-LIST-NTH _CSJR-STRING$ _CSJR-KU ! _CSJR-KA !
    SWAP 0 ?DO
        I OVER CV-LIST-NTH _CSJR-STRING$
        _CSJR-KA @ _CSJR-KU @ COMPARE 0= IF DROP -1 UNLOOP EXIT THEN
    LOOP
    DROP 0 ;

\ "required" lists distinct property names.
: _CSJR-REQUIRED-VALID?  ( properties required -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-LIST <> IF 2DROP 0 EXIT THEN
    DUP CV-LEN@ 0 ?DO
        I OVER CV-LIST-NTH
        DUP CV-TYPE@ CV-T-STRING <> IF DROP 2DROP 0 UNLOOP EXIT THEN
        _CSJR-STRING$ 3 PICK CV-MAP-FIND 0= IF 2DROP 0 UNLOOP EXIT THEN
        I OVER _CSJR-REQUIRED-SEEN? IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ The properties of a closed map, or 0 for an open one.
: _CSJR-PROPERTIES  ( -- properties|0 ior )
    S" properties" _CSJR-FIELD
    S" required" _CSJR-FIELD
    S" additionalProperties" _CSJR-FIELD
    2 PICK 0= IF
        OR NIP IF 0 IVJSON-E-TYPE ELSE 0 0 THEN EXIT
    THEN
    _CSJR-MASKV @ CV-T-MAP CS-TYPE-BIT AND 0= IF
        2DROP DROP 0 IVJSON-E-TYPE EXIT
    THEN
    DUP 0= IF 2DROP DROP 0 IVJSON-E-TYPE EXIT THEN
    DUP CV-TYPE@ CV-T-BOOL <> IF 2DROP DROP 0 IVJSON-E-TYPE EXIT THEN
    CV-DATA@ IF 2DROP 0 IVJSON-E-UNSUPPORTED EXIT THEN
    OVER CV-TYPE@ CV-T-MAP <> IF 2DROP 0 IVJSON-E-TYPE EXIT THEN
    OVER CV-LEN@ 0= IF 2DROP 0 IVJSON-E-UNSUPPORTED EXIT THEN
    OVER CV-LEN@ CS-MAX-FIELDS > IF 2DROP 0 IVJSON-E-CAPACITY EXIT THEN
    2DUP _CSJR-REQUIRED-VALID? 0= IF 2DROP 0 IVJSON-E-TYPE EXIT THEN
    DROP 0 ;

: _CSJR-REQUIRED?  ( key-a key-u required -- flag )
    DUP CV-LEN@ 0 ?DO
        I OVER CV-LIST-NTH _CSJR-STRING$ 4 PICK 4 PICK COMPARE 0= IF
            DROP 2DROP -1 UNLOOP EXIT
        THEN
    LOOP
    DROP 2DROP 0 ;

\ Is KEY after LAST?  LAST-U is -1 before the first key.
: _CSJR-AFTER?  ( key-a key-u last-a last-u -- flag )
    DUP 0< IF 2DROP 2DROP -1 EXIT THEN
    COMPARE 0> ;

\ The entry of PROPERTIES whose key most closely follows LAST, so fields
\ are written in key order.
: _CSJR-NEXT-ENTRY  ( properties last-a last-u -- entry|0 )
    0 3 PICK CV-LEN@ 0 ?DO
        I 4 PICK CV-MAP-NTH
        DUP CV-MAP-KEY _CSJR-STRING$ 5 PICK 5 PICK _CSJR-AFTER? IF
            OVER 0= IF
                NIP
            ELSE
                DUP CV-MAP-KEY _CSJR-STRING$
                3 PICK CV-MAP-KEY _CSJR-STRING$ COMPARE 0< IF
                    NIP
                ELSE
                    DROP
                THEN
            THEN
        ELSE
            DROP
        THEN
    LOOP
    NIP NIP NIP ;

DEFER _CSJR-SCHEMA  ( value depth -- )

\ The last key written stays on the stack, because a field's own schema
\ may be a map whose fields are walked in between.
: _CSJR-FIELDS  ( properties required depth -- )
    2 PICK CV-LEN@ DUP CSBW-U16
    >R 0 -1 R>
    0 ?DO
        _CSJR-ERR @ IF LEAVE THEN
        4 PICK 2 PICK 2 PICK _CSJR-NEXT-ENTRY
        NIP NIP
        DUP CV-MAP-KEY _CSJR-STRING$
        DUP CSBW-U32 2DUP CSBW-BYTES
        2DUP 6 PICK _CSJR-REQUIRED? 1 AND CSBW-U8
        ROT CV-MAP-VALUE 3 PICK 1+ _CSJR-SCHEMA
    LOOP
    2DROP 2DROP DROP ;

\ JSON carries a container only within a known bound
\ (IVJSON-SCHEMA-COMPATIBLE?).
: _CSJR-CARRIED?  ( items properties -- flag )
    _CSJR-MASKV @ CV-T-LIST CS-TYPE-BIT AND IF
        _CSJR-LEN @ DUP 0< SWAP IVJSON-MAX-CHILDREN > OR IF
            2DROP 0 EXIT
        THEN
        OVER 0= _CSJR-LEN @ 0<> AND IF 2DROP 0 EXIT THEN
    THEN
    _CSJR-MASKV @ CV-T-MAP CS-TYPE-BIT AND IF
        DUP 0= _CSJR-LEN @ 0<> AND IF 2DROP 0 EXIT THEN
    THEN
    2DROP -1 ;

: _CSJR-WRITE-HEAD  ( -- )
    _CSJR-MASKV @ CSBW-U16
    _CSJR-FLAGS @ CSBW-U8 0 CSBW-U8
    _CSJR-FLAGS @ CSB-F-MIN AND IF _CSJR-MIN-V @ CSBW-U64 THEN
    _CSJR-FLAGS @ CSB-F-MAX AND IF _CSJR-MAX-V @ CSBW-U64 THEN
    _CSJR-FLAGS @ CSB-F-MAX-LEN AND IF _CSJR-LEN @ CSBW-U64 THEN ;

: _CSJR-SCHEMA-R  ( value depth -- )
    _CSJR-ERR @ IF 2DROP EXIT THEN
    DUP CS-MAX-DEPTH >= IF 2DROP IVJSON-E-DEPTH _CSJR-FAIL EXIT THEN
    OVER CV-TYPE@ CV-T-MAP <> IF 2DROP IVJSON-E-TYPE _CSJR-FAIL EXIT THEN
    OVER _CSJR-MAP !
    _CSJR-HEAD ?DUP IF NIP NIP _CSJR-FAIL EXIT THEN
    S" items" _CSJR-FIELD
    DUP IF
        _CSJR-MASKV @ CV-T-LIST CS-TYPE-BIT AND 0= IF
            DROP 2DROP IVJSON-E-TYPE _CSJR-FAIL EXIT
        THEN
        CSB-F-ITEM _CSJR-FLAG+
    THEN
    _CSJR-PROPERTIES ?DUP IF NIP NIP NIP NIP _CSJR-FAIL EXIT THEN
    2DUP _CSJR-CARRIED? 0= IF
        2DROP 2DROP IVJSON-E-UNSUPPORTED _CSJR-FAIL EXIT
    THEN
    DUP IF CSB-F-FIELDS _CSJR-FLAG+ THEN
    S" required" _CSJR-FIELD
    _CSJR-WRITE-HEAD
    \ ( value depth items properties required )
    2 PICK ?DUP IF 4 PICK 1+ _CSJR-SCHEMA THEN
    OVER IF OVER OVER 5 PICK _CSJR-FIELDS THEN
    2DROP 2DROP DROP ;

' _CSJR-SCHEMA-R IS _CSJR-SCHEMA

: _CSJSON-READ  ( json json-u buffer capacity -- length ior )
    CSBW-BEGIN
    _CSJR-ROOT IVJSON-DECODE ?DUP IF 0 SWAP EXIT THEN
    0 _CSJR-ERR !
    _CSJR-ROOT 0 _CSJR-SCHEMA
    _CSJR-ROOT CV-FREE
    _CSJR-ERR @ ?DUP IF 0 SWAP EXIT THEN
    CSBW-END IF DROP 0 IVJSON-E-CAPACITY ELSE 0 THEN ;

GUARD _csjson-read-guard
' _CSJSON-READ CONSTANT _csjson-read-xt
: CSJSON-READ  ( json json-u buffer capacity -- length ior )
    _csjson-read-xt _csjson-read-guard WITH-GUARD ;

