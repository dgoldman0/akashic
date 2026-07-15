\ =====================================================================
\  json-value.f - JSON codec for owned interoperability values
\ =====================================================================
\  This module has no protocol, transport, provider, Desk, or TUI
\  dependency. JSON objects and arrays become owned CV maps and lists.
\  F32 and byte-string wire forms remain explicit unsupported cases until
\  a canonical textual representation is selected.
\ =====================================================================

PROVIDED akashic-ivalue-json-codec

REQUIRE ../schema.f
REQUIRE ../../utils/json.f
REQUIRE ../../concurrency/guard.f

1 CONSTANT IVJSON-E-INVALID
2 CONSTANT IVJSON-E-TYPE
3 CONSTANT IVJSON-E-RANGE
4 CONSTANT IVJSON-E-DEPTH
5 CONSTANT IVJSON-E-CAPACITY
6 CONSTANT IVJSON-E-NOMEM
7 CONSTANT IVJSON-E-UNSUPPORTED

16 CONSTANT IVJSON-MAX-DEPTH
64 CONSTANT IVJSON-MAX-CHILDREN

\ CV has native float and opaque-byte variants, but this codec deliberately
\ has no canonical JSON representation for either one yet.  Keep the exact
\ representable mask public so protocol boundaries do not infer support from
\ JSON Schema's broader primitive vocabulary.
CS-VALID-TYPE-MASK
    CV-T-F32 CS-TYPE-BIT INVERT AND
    CV-T-BYTES CS-TYPE-BIT INVERT AND
CONSTANT IVJSON-SUPPORTED-TYPE-MASK

\ The graph must already be structurally valid before the recursive walk can
\ dereference children.  An unconstrained list item or open map is not a
\ compatibility guarantee: either can contain F32 or bytes.  Container
\ bounds must also keep every schema-valid value within this codec's child
\ limit.  The predicate does not estimate an encoded byte length or promise
\ that a particular destination buffer is large enough.
: _IVJSON-SCHEMA-COMPATIBLE-R?  ( schema depth -- flag )
    DUP IVJSON-MAX-DEPTH >= IF 2DROP 0 EXIT THEN
    >R
    DUP CS.TYPE-MASK @ IVJSON-SUPPORTED-TYPE-MASK INVERT AND IF
        DROP R> DROP 0 EXIT
    THEN
    DUP CS.TYPE-MASK @ CV-T-LIST CS-TYPE-BIT AND IF
        DUP CS.FLAGS @ CS-F-MAX-LEN AND 0= IF
            DROP R> DROP 0 EXIT
        THEN
        DUP CS.MAX-LEN @ IVJSON-MAX-CHILDREN > IF
            DROP R> DROP 0 EXIT
        THEN
        DUP CS.ITEM @ ?DUP IF
            R@ 1+ RECURSE 0= IF DROP R> DROP 0 EXIT THEN
        ELSE
            DUP CS.MAX-LEN @ IF DROP R> DROP 0 EXIT THEN
        THEN
    THEN
    DUP CS.TYPE-MASK @ CV-T-MAP CS-TYPE-BIT AND IF
        DUP CS.FIELD-N @ 0= IF
            DUP CS.FLAGS @ CS-F-MAX-LEN AND 0= IF
                DROP R> DROP 0 EXIT
            THEN
            DUP CS.MAX-LEN @ IF DROP R> DROP 0 EXIT THEN
        THEN
        DUP CS.FIELD-N @ IVJSON-MAX-CHILDREN > IF
            DUP CS.FLAGS @ CS-F-MAX-LEN AND 0= IF
                DROP R> DROP 0 EXIT
            THEN
            DUP CS.MAX-LEN @ IVJSON-MAX-CHILDREN > IF
                DROP R> DROP 0 EXIT
            THEN
        THEN
        DUP CS.FIELD-N @ 0 ?DO
            DUP CS.FIELDS @ I CS-FIELD-SIZE * + CSF.SCHEMA @
            R@ 1+ RECURSE 0= IF
                DROP R> DROP 0 UNLOOP EXIT
            THEN
        LOOP
    THEN
    DROP R> DROP -1 ;

: IVJSON-SCHEMA-COMPATIBLE?  ( schema -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CS-SCHEMA-VALIDATE IF DROP 0 EXIT THEN
    0 _IVJSON-SCHEMA-COMPATIBLE-R? ;

\ Per-depth decode frames keep recursive calls from overwriting parent
\ cursors. Each array stores one cell for every supported nesting level.
CREATE _IVJDF-A      IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJDF-U      IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJDF-V      IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJDF-CUR-A  IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJDF-CUR-U  IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJDF-KEY-A  IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJDF-KEY-U  IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJDF-COUNT  IVJSON-MAX-DEPTH 8 * ALLOT
VARIABLE _IVJD-DEPTH

: _IVJD-SLOT  ( base -- address )
    _IVJD-DEPTH @ 8 * + ;

: _IVJD-A@      ( -- x ) _IVJDF-A _IVJD-SLOT @ ;
: _IVJD-U@      ( -- x ) _IVJDF-U _IVJD-SLOT @ ;
: _IVJD-V@      ( -- x ) _IVJDF-V _IVJD-SLOT @ ;
: _IVJD-CUR-A@  ( -- x ) _IVJDF-CUR-A _IVJD-SLOT @ ;
: _IVJD-CUR-U@  ( -- x ) _IVJDF-CUR-U _IVJD-SLOT @ ;
: _IVJD-KEY-A@  ( -- x ) _IVJDF-KEY-A _IVJD-SLOT @ ;
: _IVJD-KEY-U@  ( -- x ) _IVJDF-KEY-U _IVJD-SLOT @ ;
: _IVJD-COUNT@  ( -- x ) _IVJDF-COUNT _IVJD-SLOT @ ;

: _IVJD-A!      ( x -- ) _IVJDF-A _IVJD-SLOT ! ;
: _IVJD-U!      ( x -- ) _IVJDF-U _IVJD-SLOT ! ;
: _IVJD-V!      ( x -- ) _IVJDF-V _IVJD-SLOT ! ;
: _IVJD-CUR-A!  ( x -- ) _IVJDF-CUR-A _IVJD-SLOT ! ;
: _IVJD-CUR-U!  ( x -- ) _IVJDF-CUR-U _IVJD-SLOT ! ;
: _IVJD-KEY-A!  ( x -- ) _IVJDF-KEY-A _IVJD-SLOT ! ;
: _IVJD-KEY-U!  ( x -- ) _IVJDF-KEY-U _IVJD-SLOT ! ;
: _IVJD-COUNT!  ( x -- ) _IVJDF-COUNT _IVJD-SLOT ! ;

: _IVJD-COUNT+  ( -- )
    _IVJDF-COUNT _IVJD-SLOT 1 SWAP +! ;

VARIABLE _IVJN-A
VARIABLE _IVJN-U
VARIABLE _IVJN-NEG
VARIABLE _IVJN-LIMIT
VARIABLE _IVJN-ACC
VARIABLE _IVJN-DIGIT

: _IVJSON-INTEGER?  ( value-a value-u -- flag )
    _IVJN-U ! _IVJN-A !
    _IVJN-A @ _IVJN-U @ JSON-SKIP-VALUE DROP
    _IVJN-A @ - _IVJN-U !
    _IVJN-U @ 0= IF 0 EXIT THEN
    _IVJN-A @ C@ 45 = IF
        _IVJN-U @ 1- DUP 0= SWAP 19 > OR IF 0 EXIT THEN
        1 _IVJN-A +! -1 _IVJN-U +!
    ELSE
        _IVJN-U @ 19 > IF 0 EXIT THEN
    THEN
    _IVJN-U @ 0 DO
        _IVJN-A @ I + C@ DUP 48 < SWAP 57 > OR IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

\ Accumulate negatively so the signed-cell minimum is representable.  The
\ caller has already established digit-only integer syntax.
: _IVJSON-PARSE-INTEGER  ( addr len -- n flag )
    _IVJN-U ! _IVJN-A ! 0 _IVJN-NEG ! 0 _IVJN-ACC !
    _IVJN-U @ 0= IF 0 0 EXIT THEN
    _IVJN-A @ C@ 45 = IF
        -1 _IVJN-NEG ! 1 _IVJN-A +! -1 _IVJN-U +!
    THEN
    _IVJN-NEG @ IF
        0x8000000000000000
    ELSE
        0x8000000000000001
    THEN _IVJN-LIMIT !
    _IVJN-U @ 0 ?DO
        _IVJN-A @ I + C@ 48 - _IVJN-DIGIT !
        _IVJN-ACC @ _IVJN-LIMIT @ 10 / < IF
            0 0 UNLOOP EXIT
        THEN
        _IVJN-ACC @ 10 *
        DUP _IVJN-LIMIT @ _IVJN-DIGIT @ + < IF
            DROP 0 0 UNLOOP EXIT
        THEN
        _IVJN-DIGIT @ - _IVJN-ACC !
    LOOP
    _IVJN-ACC @ _IVJN-NEG @ 0= IF NEGATE THEN -1 ;

VARIABLE _IVJS-A
VARIABLE _IVJS-U
VARIABLE _IVJS-V
VARIABLE _IVJS-TMP
VARIABLE _IVJS-N

: _IVJD-STRING-BODY  ( raw-a raw-u value -- ior )
    _IVJS-V ! _IVJS-U ! _IVJS-A ! 0 _IVJS-TMP !
    _IVJS-U @ 0= IF
        0 0 _IVJS-V @ CV-STRING! IF IVJSON-E-NOMEM ELSE 0 THEN EXIT
    THEN
    _IVJS-U @ ALLOCATE DUP IF
        2DROP IVJSON-E-NOMEM EXIT
    THEN
    DROP _IVJS-TMP !
    _IVJS-A @ _IVJS-U @ _IVJS-TMP @ _IVJS-U @ JSON-UNESCAPE-CHECKED
    DUP IF
        2DROP _IVJS-TMP @ FREE IVJSON-E-INVALID EXIT
    THEN
    DROP DUP _IVJS-N !
    _IVJS-TMP @ SWAP _IVJS-V @ CV-STRING!
    _IVJS-TMP @ FREE
    IF IVJSON-E-NOMEM ELSE 0 THEN ;

: _IVJD-STRING  ( -- ior )
    _IVJD-A@ _IVJD-U@ JSON-GET-STRING
    _IVJD-V@ _IVJD-STRING-BODY ;

: _IVJD-OBJECT-COUNT  ( -- count ior )
    _IVJD-A@ _IVJD-U@ JSON-ENTER
    _IVJD-CUR-U! _IVJD-CUR-A! 0 _IVJD-COUNT!
    BEGIN
        _IVJD-CUR-A@ _IVJD-CUR-U@ JSON-EACH-KEY
        IF
            2DROP
            JSON-NEXT DROP _IVJD-CUR-U! _IVJD-CUR-A!
            _IVJD-COUNT+
            _IVJD-COUNT@ IVJSON-MAX-CHILDREN > IF
                0 IVJSON-E-CAPACITY EXIT
            THEN
            -1
        ELSE
            2DROP 2DROP 0
        THEN
    0= UNTIL
    _IVJD-COUNT@ 0 ;

VARIABLE _IVJK-I
VARIABLE _IVJK-MAP
VARIABLE _IVJK-KEY

: _IVJD-DUPLICATE-KEY?  ( index map -- flag )
    _IVJK-MAP ! _IVJK-I !
    _IVJK-I @ _IVJK-MAP @ CV-MAP-NTH CV-MAP-KEY _IVJK-KEY !
    _IVJK-I @ 0 ?DO
        I _IVJK-MAP @ CV-MAP-NTH CV-MAP-KEY
        DUP CV-TYPE@ CV-T-STRING = IF
            DUP CV-DATA@ SWAP CV-LEN@
            _IVJK-KEY @ DUP CV-DATA@ SWAP CV-LEN@ STR-STR= IF
                -1 UNLOOP EXIT
            THEN
        ELSE
            DROP
        THEN
    LOOP
    0 ;

DEFER _IVJD-VALUE

: _IVJD-ARRAY  ( -- ior )
    _IVJD-A@ _IVJD-U@ JSON-ENTER
    2DUP JSON-COUNT DUP IVJSON-MAX-CHILDREN > IF
        DROP 2DROP IVJSON-E-CAPACITY EXIT
    THEN
    DUP _IVJD-COUNT!
    _IVJD-V@ CV-LIST! IF 2DROP IVJSON-E-NOMEM EXIT THEN
    _IVJD-CUR-U! _IVJD-CUR-A!
    _IVJD-COUNT@ 0 ?DO
        _IVJD-CUR-A@ _IVJD-CUR-U@
        I _IVJD-V@ CV-LIST-NTH _IVJD-VALUE ?DUP IF
            UNLOOP EXIT
        THEN
        _IVJD-CUR-A@ _IVJD-CUR-U@ JSON-NEXT DROP
        _IVJD-CUR-U! _IVJD-CUR-A!
    LOOP
    0 ;

: _IVJD-OBJECT  ( -- ior )
    _IVJD-OBJECT-COUNT DUP IF NIP EXIT THEN DROP
    DUP _IVJD-COUNT!
    _IVJD-V@ CV-MAP! IF IVJSON-E-NOMEM EXIT THEN
    _IVJD-A@ _IVJD-U@ JSON-ENTER
    _IVJD-CUR-U! _IVJD-CUR-A!
    _IVJD-COUNT@ 0 ?DO
        _IVJD-CUR-A@ _IVJD-CUR-U@ JSON-EACH-KEY 0= IF
            2DROP 2DROP IVJSON-E-INVALID UNLOOP EXIT
        THEN
        _IVJD-KEY-U! _IVJD-KEY-A! _IVJD-CUR-U! _IVJD-CUR-A!
        _IVJD-KEY-A@ _IVJD-KEY-U@
        I _IVJD-V@ CV-MAP-NTH CV-MAP-KEY
        _IVJD-STRING-BODY ?DUP IF UNLOOP EXIT THEN
        I _IVJD-V@ _IVJD-DUPLICATE-KEY? IF
            IVJSON-E-INVALID UNLOOP EXIT
        THEN
        _IVJD-CUR-A@ _IVJD-CUR-U@
        I _IVJD-V@ CV-MAP-NTH CV-MAP-VALUE
        _IVJD-VALUE ?DUP IF UNLOOP EXIT THEN
        _IVJD-CUR-A@ _IVJD-CUR-U@ JSON-NEXT DROP
        _IVJD-CUR-U! _IVJD-CUR-A!
    LOOP
    0 ;

: _IVJD-VALUE-IMPL  ( -- ior )
    _IVJD-A@ _IVJD-U@ JSON-TYPE? CASE
        JSON-T-NULL OF _IVJD-V@ CV-NULL! 0 ENDOF
        JSON-T-BOOL OF
            _IVJD-A@ _IVJD-U@ JSON-GET-BOOL _IVJD-V@ CV-BOOL! 0
        ENDOF
        JSON-T-NUMBER OF
            _IVJD-A@ _IVJD-U@ JSON-VALUE-SPAN
            2DUP _IVJSON-INTEGER? 0= IF
                2DROP
                IVJSON-E-UNSUPPORTED
            ELSE
                _IVJSON-PARSE-INTEGER IF
                    _IVJD-V@ CV-INT! 0
                ELSE
                    DROP IVJSON-E-RANGE
                THEN
            THEN
        ENDOF
        JSON-T-STRING OF _IVJD-STRING ENDOF
        JSON-T-ARRAY OF _IVJD-ARRAY ENDOF
        JSON-T-OBJECT OF _IVJD-OBJECT ENDOF
        IVJSON-E-INVALID SWAP DROP
    ENDCASE ;

: _IVJD-VALUE-R  ( json-a json-u value -- ior )
    1 _IVJD-DEPTH +!
    _IVJD-DEPTH @ IVJSON-MAX-DEPTH >= IF
        DROP 2DROP -1 _IVJD-DEPTH +! IVJSON-E-DEPTH EXIT
    THEN
    _IVJD-V! _IVJD-U! _IVJD-A!
    _IVJD-VALUE-IMPL
    -1 _IVJD-DEPTH +! ;

' _IVJD-VALUE-R IS _IVJD-VALUE

VARIABLE _IVJD-TOP-V
CREATE _IVJD-TEMP CV-SIZE ALLOT
_IVJD-TEMP CV-INIT

: _IVJSON-REPLACE  ( source destination -- )
    DUP >R CV-FREE
    R> CV-SIZE CMOVE ;

: IVJSON-DECODE  ( json-a json-u value -- ior )
    _IVJD-TOP-V !
    _IVJD-TOP-V @ 0= IF 2DROP IVJSON-E-TYPE EXIT THEN
    _IVJD-TEMP CV-FREE
    2DUP JSON-VALID? 0= IF 2DROP IVJSON-E-INVALID EXIT THEN
    -1 _IVJD-DEPTH !
    _IVJD-TEMP _IVJD-VALUE DUP IF
        _IVJD-TEMP CV-FREE EXIT
    THEN
    DROP
    _IVJD-TEMP _IVJD-TOP-V @ _IVJSON-REPLACE
    _IVJD-TEMP CV-INIT 0 ;

\ Schema coercion is deliberately narrow. A JSON string can become a
\ resource URI when the schema requires that native type; no other type is
\ silently reinterpreted.
CREATE _IVJCF-V IVJSON-MAX-DEPTH 8 * ALLOT
CREATE _IVJCF-S IVJSON-MAX-DEPTH 8 * ALLOT
VARIABLE _IVJC-DEPTH

: _IVJC-SLOT  ( base -- address ) _IVJC-DEPTH @ 8 * + ;
: _IVJC-V@    ( -- value ) _IVJCF-V _IVJC-SLOT @ ;
: _IVJC-S@    ( -- schema ) _IVJCF-S _IVJC-SLOT @ ;
: _IVJC-V!    ( value -- ) _IVJCF-V _IVJC-SLOT ! ;
: _IVJC-S!    ( schema -- ) _IVJCF-S _IVJC-SLOT ! ;

DEFER _IVJC-VALUE

: _IVJC-CONTAINER  ( -- ior )
    _IVJC-V@ CV-TYPE@ CV-T-LIST = IF
        _IVJC-S@ CS.ITEM @ ?DUP IF
            _IVJC-V@ CV-LEN@ 0 ?DO
                I _IVJC-V@ CV-LIST-NTH OVER _IVJC-VALUE ?DUP IF
                    NIP UNLOOP EXIT
                THEN
            LOOP
            DROP
        THEN
        0 EXIT
    THEN
    _IVJC-V@ CV-TYPE@ CV-T-MAP = IF
        _IVJC-S@ CS.FIELD-N @ 0 ?DO
            _IVJC-S@ CS.FIELDS @ I CS-FIELD-SIZE * + DUP
            DUP CSF.KEY-A @ SWAP CSF.KEY-U @ _IVJC-V@ CV-MAP-FIND
            ?DUP IF
                SWAP CSF.SCHEMA @ _IVJC-VALUE ?DUP IF UNLOOP EXIT THEN
            ELSE
                DROP
            THEN
        LOOP
        _IVJC-V@ _IVJC-S@ CS-VALIDATE-FIELDS EXIT
    THEN
    0 ;

: _IVJC-VALUE-R  ( value schema -- ior )
    1 _IVJC-DEPTH +!
    _IVJC-DEPTH @ IVJSON-MAX-DEPTH >= IF
        2DROP -1 _IVJC-DEPTH +! IVJSON-E-DEPTH EXIT
    THEN
    _IVJC-S! _IVJC-V!
    _IVJC-V@ CV-TYPE@ CV-T-STRING =
    _IVJC-S@ CS.TYPE-MASK @ CV-T-RESOURCE CS-TYPE-BIT AND 0<> AND
    _IVJC-S@ CS.TYPE-MASK @ CV-T-STRING CS-TYPE-BIT AND 0= AND IF
        CV-T-RESOURCE _IVJC-V@ CV.TYPE !
    THEN
    _IVJC-V@ _IVJC-S@ CS-VALIDATE ?DUP IF
        DROP -1 _IVJC-DEPTH +! IVJSON-E-TYPE EXIT
    THEN
    _IVJC-CONTAINER
    -1 _IVJC-DEPTH +! ;

' _IVJC-VALUE-R IS _IVJC-VALUE

VARIABLE _IVJC-TOP-S
VARIABLE _IVJC-TOP-V
CREATE _IVJC-TEMP CV-SIZE ALLOT
_IVJC-TEMP CV-INIT

: _IVJSON-SCHEMA-IOR>DECODE-IOR  ( cs-ior -- ivjson-ior )
    DUP CS-E-DEPTH = IF DROP IVJSON-E-DEPTH EXIT THEN
    CS-E-CAPACITY = IF IVJSON-E-CAPACITY ELSE IVJSON-E-TYPE THEN ;

\ Validate the complete schema graph before decoding any input.  Runtime
\ traversal alone cannot see a malformed or unsupported item schema beneath
\ an empty list (or fields omitted from an empty map).  A null schema remains
\ the explicit unconstrained decode mode.
: _IVJSON-DECODE-PREFLIGHT  ( schema -- ior )
    DUP 0= IF DROP 0 EXIT THEN
    DUP CS-SCHEMA-VALIDATE ?DUP IF
        NIP _IVJSON-SCHEMA-IOR>DECODE-IOR EXIT
    THEN
    IVJSON-SCHEMA-COMPATIBLE? 0= IF
        IVJSON-E-UNSUPPORTED
    ELSE
        0
    THEN ;

: IVJSON-DECODE-AS  ( json-a json-u schema value -- ior )
    _IVJC-TOP-V ! _IVJC-TOP-S !
    _IVJC-TOP-V @ 0= IF 2DROP IVJSON-E-TYPE EXIT THEN
    _IVJC-TOP-S @ _IVJSON-DECODE-PREFLIGHT ?DUP IF
        >R 2DROP R> EXIT
    THEN
    _IVJC-TEMP CV-FREE
    _IVJC-TEMP IVJSON-DECODE ?DUP IF EXIT THEN
    _IVJC-TOP-S @ 0= IF
        _IVJC-TEMP _IVJC-TOP-V @ _IVJSON-REPLACE
        _IVJC-TEMP CV-INIT 0 EXIT
    THEN
    -1 _IVJC-DEPTH !
    _IVJC-TEMP _IVJC-TOP-S @ _IVJC-VALUE DUP IF
        _IVJC-TEMP CV-FREE EXIT
    THEN
    DROP
    _IVJC-TEMP _IVJC-TOP-V @ _IVJSON-REPLACE
    _IVJC-TEMP CV-INIT 0 ;

\ Decode frames and coercion state are module-owned scratch.  Hold one guard
\ for the complete transaction; the raw DECODE-AS body is already bound to
\ the raw DECODE word, so it does not release the guard between phases.
GUARD _ivjson-decode-guard
' IVJSON-DECODE CONSTANT _ivjson-decode-xt
' IVJSON-DECODE-AS CONSTANT _ivjson-decode-as-xt
: IVJSON-DECODE
    _ivjson-decode-xt _ivjson-decode-guard WITH-GUARD ;
: IVJSON-DECODE-AS
    _ivjson-decode-as-xt _ivjson-decode-guard WITH-GUARD ;

\ =====================================================================
\  Encoding
\ =====================================================================

CREATE _IVJEF-V IVJSON-MAX-DEPTH 8 * ALLOT
VARIABLE _IVJE-DEPTH
VARIABLE _IVJE-ERROR
VARIABLE _IVJE-TYPED

\ All encoders share recursive frame state and JSON's streaming builder.
\ Public entry holds the builder guard outermost, then this frame guard, for
\ the complete transaction.  Keeping that lock order matches other compound
\ encoders and permits safe use from an existing builder transaction.  The
\ caller's output buffer remains owned by the caller after return.
GUARD _ivjson-encode-guard

: _IVJE-SLOT  ( -- address )
    _IVJEF-V _IVJE-DEPTH @ 8 * + ;

: _IVJE-V@  ( -- value ) _IVJE-SLOT @ ;
: _IVJE-V!  ( value -- ) _IVJE-SLOT ! ;

DEFER _IVJE-VALUE

VARIABLE _IVJE-DUP-KEY

: _IVJE-DUPLICATE-KEY?  ( index -- flag )
    DUP _IVJE-V@ CV-MAP-NTH CV-MAP-KEY _IVJE-DUP-KEY !
    0 ?DO
        I _IVJE-V@ CV-MAP-NTH CV-MAP-KEY
        DUP CV-TYPE@ CV-T-STRING = IF
            DUP CV-DATA@ SWAP CV-LEN@
            _IVJE-DUP-KEY @ DUP CV-DATA@ SWAP CV-LEN@
            STR-STR= IF -1 UNLOOP EXIT THEN
        ELSE
            DROP
        THEN
    LOOP
    0 ;

: _IVJE-CONTAINER-VALID?  ( expected-aux -- flag )
    _IVJE-V@ CV.AUX @ <> IF 0 EXIT THEN
    _IVJE-V@ CV-LEN@ DUP 0< OVER IVJSON-MAX-CHILDREN > OR IF
        DROP 0 EXIT
    THEN
    DUP 0> IF _IVJE-V@ CV-DATA@ 0= IF DROP 0 EXIT THEN THEN
    DROP -1 ;

: _IVJE-TEXT-VALID?  ( -- flag )
    _IVJE-V@ CV-LEN@ DUP 0< IF DROP 0 EXIT THEN
    DUP CV-MAX-STRING-LEN > IF DROP 0 EXIT THEN
    DUP 0> IF _IVJE-V@ CV-DATA@ 0= IF DROP 0 EXIT THEN THEN
    _IVJE-V@ CV-DATA@ SWAP UTF8-VALID? ;

: _IVJE-LIST  ( -- )
    CV-SIZE _IVJE-CONTAINER-VALID? 0= IF
        IVJSON-E-RANGE _IVJE-ERROR ! EXIT
    THEN
    JSON-[
    _IVJE-V@ CV-LEN@ 0 ?DO
        I _IVJE-V@ CV-LIST-NTH _IVJE-VALUE
        _IVJE-ERROR @ JSON-OUTPUT-OK? 0= OR IF
            _IVJE-ERROR @ 0= IF IVJSON-E-CAPACITY _IVJE-ERROR ! THEN
            LEAVE
        THEN
    LOOP
    JSON-] ;

: _IVJE-MAP  ( -- )
    CV-MAP-ENTRY-SIZE _IVJE-CONTAINER-VALID? 0= IF
        IVJSON-E-RANGE _IVJE-ERROR ! EXIT
    THEN
    JSON-{
    _IVJE-V@ CV-LEN@ 0 ?DO
        I _IVJE-V@ CV-MAP-NTH DUP CV-MAP-KEY
        DUP CV-TYPE@ CV-T-STRING <> IF
            2DROP IVJSON-E-TYPE _IVJE-ERROR ! LEAVE
        THEN
        DUP CV-LEN@ DUP 0< IF
            2DROP DROP IVJSON-E-RANGE _IVJE-ERROR ! LEAVE
        THEN
        DUP CV-MAX-STRING-LEN > IF
            2DROP DROP IVJSON-E-RANGE _IVJE-ERROR ! LEAVE
        THEN
        DUP 0> IF OVER CV-DATA@ 0= IF
            2DROP DROP IVJSON-E-RANGE _IVJE-ERROR ! LEAVE
        THEN THEN
        DROP
        DUP CV-DATA@ OVER CV-LEN@ 2DUP UTF8-VALID? 0= IF
            2DROP 2DROP IVJSON-E-TYPE _IVJE-ERROR ! LEAVE
        THEN
        2DROP
        I _IVJE-DUPLICATE-KEY? IF
            2DROP IVJSON-E-INVALID _IVJE-ERROR ! LEAVE
        THEN
        DUP CV-DATA@ SWAP CV-LEN@ JSON-EKEY:
        CV-MAP-VALUE _IVJE-VALUE
        _IVJE-ERROR @ JSON-OUTPUT-OK? 0= OR IF
            _IVJE-ERROR @ 0= IF IVJSON-E-CAPACITY _IVJE-ERROR ! THEN
            LEAVE
        THEN
    LOOP
    JSON-} ;

: _IVJE-TYPE-TAG  ( type -- )
    CASE
        CV-T-NULL OF S" null" JSON-ESTR ENDOF
        CV-T-BOOL OF S" bool" JSON-ESTR ENDOF
        CV-T-INT OF S" int" JSON-ESTR ENDOF
        CV-T-STRING OF S" string" JSON-ESTR ENDOF
        CV-T-LIST OF S" list" JSON-ESTR ENDOF
        CV-T-MAP OF S" map" JSON-ESTR ENDOF
        CV-T-RESOURCE OF S" resource" JSON-ESTR ENDOF
        IVJSON-E-UNSUPPORTED _IVJE-ERROR !
    ENDCASE ;

: _IVJE-PAYLOAD  ( -- )
    _IVJE-V@ CV-TYPE@ CASE
        CV-T-NULL OF JSON-NULL ENDOF
        CV-T-BOOL OF _IVJE-V@ CV-DATA@ JSON-BOOL ENDOF
        CV-T-INT OF _IVJE-V@ CV-DATA@ JSON-NUM ENDOF
        CV-T-STRING OF
            _IVJE-TEXT-VALID? IF
                _IVJE-V@ DUP CV-DATA@ SWAP CV-LEN@ JSON-ESTR
            ELSE
                IVJSON-E-TYPE _IVJE-ERROR !
            THEN
        ENDOF
        CV-T-RESOURCE OF
            _IVJE-TEXT-VALID? IF
                _IVJE-V@ DUP CV-DATA@ SWAP CV-LEN@ JSON-ESTR
            ELSE
                IVJSON-E-TYPE _IVJE-ERROR !
            THEN
        ENDOF
        CV-T-LIST OF _IVJE-LIST ENDOF
        CV-T-MAP OF _IVJE-MAP ENDOF
        IVJSON-E-UNSUPPORTED _IVJE-ERROR !
    ENDCASE ;

: _IVJE-VALUE-R  ( value -- )
    _IVJE-ERROR @ IF DROP EXIT THEN
    1 _IVJE-DEPTH +!
    _IVJE-DEPTH @ IVJSON-MAX-DEPTH >= IF
        DROP IVJSON-E-DEPTH _IVJE-ERROR ! -1 _IVJE-DEPTH +! EXIT
    THEN
    _IVJE-V!
    _IVJE-TYPED @ IF
        JSON-[
        _IVJE-V@ CV-TYPE@ _IVJE-TYPE-TAG
        _IVJE-ERROR @ 0= IF _IVJE-PAYLOAD THEN
        JSON-]
    ELSE
        _IVJE-PAYLOAD
    THEN
    -1 _IVJE-DEPTH +! ;

' _IVJE-VALUE-R IS _IVJE-VALUE

VARIABLE _IVJE-BUF
VARIABLE _IVJE-CAP

: _IVJSON-ENCODE  ( value buffer capacity -- length ior )
    _IVJE-CAP ! _IVJE-BUF !
    DUP 0= IF DROP 0 IVJSON-E-TYPE EXIT THEN
    JSON-BUILD-RESET
    _IVJE-BUF @ _IVJE-CAP @ JSON-SET-OUTPUT
    -1 _IVJE-DEPTH ! 0 _IVJE-ERROR !
    _IVJE-VALUE
    _IVJE-ERROR @ ?DUP IF 0 SWAP EXIT THEN
    JSON-OUTPUT-OK? 0= IF 0 IVJSON-E-CAPACITY EXIT THEN
    JSON-OUTPUT-RESULT NIP 0 ;

: _IVJSON-ENCODE-PLAIN  ( value buffer capacity -- length ior )
    0 _IVJE-TYPED ! _IVJSON-ENCODE ;

: _IVJSON-ENCODE-TYPED  ( value buffer capacity -- length ior )
    -1 _IVJE-TYPED ! _IVJSON-ENCODE ;

: _IVJSON-ENCODE-PLAIN-IVJSON-GUARDED  ( value buffer capacity -- length ior )
    ['] _IVJSON-ENCODE-PLAIN _ivjson-encode-guard WITH-GUARD ;

: _IVJSON-ENCODE-TYPED-IVJSON-GUARDED  ( value buffer capacity -- length ior )
    ['] _IVJSON-ENCODE-TYPED _ivjson-encode-guard WITH-GUARD ;

: IVJSON-ENCODE  ( value buffer capacity -- length ior )
    ['] _IVJSON-ENCODE-PLAIN-IVJSON-GUARDED JSON-WITH-BUILDER ;

\ Exact review/seal representation.  Every recursive node carries a type
\ label, so values such as STRING and RESOURCE can never share canonical
\ bytes merely because their payload text is equal.
: IVJSON-TYPED-ENCODE  ( value buffer capacity -- length ior )
    ['] _IVJSON-ENCODE-TYPED-IVJSON-GUARDED JSON-WITH-BUILDER ;
