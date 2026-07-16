\ =====================================================================
\  media-type.f - bounded HTTP media-type syntax model
\ =====================================================================
\  This module parses one media-type field value into a caller-owned model.
\  It validates type/subtype tokens, optional whitespace around parameter
\  separators, token or quoted parameter values, quoted pairs, and complete
\  input consumption.  It does not decide which types, subtypes, parameters,
\  or parameter values a consumer should admit.
\
\  The model owns a bounded copy of the parsed value.  Returned views remain
\  valid until that model is initialized or parsed again.  Quoted parameter
\  values are unquoted and quoted pairs are decoded in the model copy.
\
\  Public API:
\    MTYPE-INIT          ( model -- )
\    MTYPE-PARSE         ( value-a value-u model -- status )
\    MTYPE-VALID?        ( model -- flag )
\    MTYPE-TYPE$         ( model -- type-a type-u )
\    MTYPE-SUBTYPE$      ( model -- subtype-a subtype-u )
\    MTYPE-PARAM-COUNT@  ( model -- count )
\    MTYPE-PARAM-NTH
\      ( index model -- name-a name-u value-a value-u found? )
\
\  Parsing is transactional with respect to MODEL.  Invalid syntax and input
\  shapes return MTYPE-S-INVALID.  Values or parameter counts beyond the
\  public bounds return MTYPE-S-CAPACITY.  This is a strict bounded parser,
\  not a MIME registry, browser-sniffing algorithm, or admission policy.
\ =====================================================================

PROVIDED akashic-media-type

REQUIRE ../concurrency/guard.f

1024 CONSTANT MTYPE-VALUE-MAX
   8 CONSTANT MTYPE-PARAM-MAX

0 CONSTANT MTYPE-S-OK
1 CONSTANT MTYPE-S-INVALID
2 CONSTANT MTYPE-S-CAPACITY

0x4D545950453031 CONSTANT _MTYPE-MAGIC  \ "MTYPE01"

 0 CONSTANT _MT-MAGIC
 8 CONSTANT _MT-SOURCE-U
16 CONSTANT _MT-TYPE-O
24 CONSTANT _MT-TYPE-U
32 CONSTANT _MT-SUBTYPE-O
40 CONSTANT _MT-SUBTYPE-U
48 CONSTANT _MT-PARAM-N
56 CONSTANT _MT-PARAMS

 0 CONSTANT _MTE-NAME-O
 8 CONSTANT _MTE-NAME-U
16 CONSTANT _MTE-VALUE-O
24 CONSTANT _MTE-VALUE-U
32 CONSTANT _MTE-SIZE

_MT-PARAMS MTYPE-PARAM-MAX _MTE-SIZE * +
    CONSTANT _MT-BYTES
_MT-BYTES MTYPE-VALUE-MAX +
    CONSTANT MTYPE-SIZE

: _MT-BYTES-A  ( model -- a )
    _MT-BYTES + ;

: _MT-ENTRY  ( index model -- entry )
    SWAP _MTE-SIZE * _MT-PARAMS + + ;

: MTYPE-INIT  ( model -- )
    DUP 0> IF MTYPE-SIZE 0 FILL ELSE DROP THEN ;

\ =====================================================================
\  Structural validation and accessors
\ =====================================================================

GUARD _media-type-guard

VARIABLE _MTV-M
VARIABLE _MTV-O
VARIABLE _MTV-U
VARIABLE _MTV-TOTAL

: _MTV-RANGE?  ( offset length total -- flag )
    _MTV-TOTAL ! _MTV-U ! _MTV-O !
    _MTV-O @ 0< _MTV-U @ 0< OR IF 0 EXIT THEN
    _MTV-O @ _MTV-TOTAL @ > IF 0 EXIT THEN
    _MTV-U @ _MTV-TOTAL @ _MTV-O @ - <= ;

: _MTYPE-VALID?  ( model -- flag )
    DUP 0> 0= IF DROP 0 EXIT THEN
    DUP _MTV-M !
    DUP _MT-MAGIC + @ _MTYPE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _MT-SOURCE-U + @ DUP 0< SWAP MTYPE-VALUE-MAX > OR IF
        DROP 0 EXIT
    THEN
    DUP _MT-TYPE-O + @
    OVER _MT-TYPE-U + @ DUP 0> 0= IF 2DROP DROP 0 EXIT THEN
    _MTV-M @ _MT-SOURCE-U + @ _MTV-RANGE? 0= IF DROP 0 EXIT THEN
    DUP _MT-SUBTYPE-O + @
    OVER _MT-SUBTYPE-U + @ DUP 0> 0= IF 2DROP DROP 0 EXIT THEN
    _MTV-M @ _MT-SOURCE-U + @ _MTV-RANGE? 0= IF DROP 0 EXIT THEN
    _MT-PARAM-N + @ DUP 0< SWAP MTYPE-PARAM-MAX > OR IF 0 EXIT THEN
    _MTV-M @ _MT-PARAM-N + @ 0 ?DO
        I _MTV-M @ _MT-ENTRY
        DUP _MTE-NAME-O + @
        OVER _MTE-NAME-U + @ DUP 0> 0= IF 2DROP DROP 0 UNLOOP EXIT THEN
        _MTV-M @ _MT-SOURCE-U + @ _MTV-RANGE? 0= IF
            DROP 0 UNLOOP EXIT
        THEN
        DUP _MTE-VALUE-O + @
        SWAP _MTE-VALUE-U + @
        _MTV-M @ _MT-SOURCE-U + @ _MTV-RANGE? 0= IF
            0 UNLOOP EXIT
        THEN
    LOOP
    -1 ;

' _MTYPE-VALID? CONSTANT _mtype-valid-q-xt
: MTYPE-VALID?  ( model -- flag )
    _mtype-valid-q-xt _media-type-guard WITH-GUARD ;

VARIABLE _MTA-M

: _MTYPE-TYPE$  ( model -- type-a type-u )
    DUP _MTA-M !
    _MTYPE-VALID? 0= IF 0 0 EXIT THEN
    _MTA-M @ _MT-BYTES-A
    _MTA-M @ _MT-TYPE-O + @ +
    _MTA-M @ _MT-TYPE-U + @ ;

: _MTYPE-SUBTYPE$  ( model -- subtype-a subtype-u )
    DUP _MTA-M !
    _MTYPE-VALID? 0= IF 0 0 EXIT THEN
    _MTA-M @ _MT-BYTES-A
    _MTA-M @ _MT-SUBTYPE-O + @ +
    _MTA-M @ _MT-SUBTYPE-U + @ ;

: _MTYPE-PARAM-COUNT@  ( model -- count )
    DUP _MTYPE-VALID? IF _MT-PARAM-N + @ ELSE DROP 0 THEN ;

VARIABLE _MTN-I
VARIABLE _MTN-M
VARIABLE _MTN-E

: _MTYPE-PARAM-NTH
    ( index model -- name-a name-u value-a value-u found? )
    _MTN-M ! _MTN-I !
    _MTN-M @ _MTYPE-VALID? 0= IF 0 0 0 0 0 EXIT THEN
    _MTN-I @ 0< IF 0 0 0 0 0 EXIT THEN
    _MTN-I @ _MTN-M @ _MT-PARAM-N + @ >= IF
        0 0 0 0 0 EXIT
    THEN
    _MTN-I @ _MTN-M @ _MT-ENTRY _MTN-E !
    _MTN-M @ _MT-BYTES-A _MTN-E @ _MTE-NAME-O + @ +
    _MTN-E @ _MTE-NAME-U + @
    _MTN-M @ _MT-BYTES-A _MTN-E @ _MTE-VALUE-O + @ +
    _MTN-E @ _MTE-VALUE-U + @
    -1 ;

' _MTYPE-TYPE$        CONSTANT _mtype-type-str-xt
' _MTYPE-SUBTYPE$     CONSTANT _mtype-subtype-str-xt
' _MTYPE-PARAM-COUNT@ CONSTANT _mtype-param-count-fetch-xt
' _MTYPE-PARAM-NTH    CONSTANT _mtype-param-nth-xt

: MTYPE-TYPE$  ( model -- type-a type-u )
    _mtype-type-str-xt _media-type-guard WITH-GUARD ;

: MTYPE-SUBTYPE$  ( model -- subtype-a subtype-u )
    _mtype-subtype-str-xt _media-type-guard WITH-GUARD ;

: MTYPE-PARAM-COUNT@  ( model -- count )
    _mtype-param-count-fetch-xt _media-type-guard WITH-GUARD ;

: MTYPE-PARAM-NTH
    ( index model -- name-a name-u value-a value-u found? )
    _mtype-param-nth-xt _media-type-guard WITH-GUARD ;

\ =====================================================================
\  Strict bounded parser
\ =====================================================================

CREATE _MTP-CANDIDATE MTYPE-SIZE ALLOT

VARIABLE _MTP-A
VARIABLE _MTP-U
VARIABLE _MTP-POS
VARIABLE _MTP-DEST
VARIABLE _MTP-TOKEN-O
VARIABLE _MTP-TOKEN-U
VARIABLE _MTP-NAME-O
VARIABLE _MTP-NAME-U
VARIABLE _MTP-VALUE-O
VARIABLE _MTP-VALUE-U
VARIABLE _MTP-READ
VARIABLE _MTP-WRITE

: _MTP-BYTES  ( -- a )
    _MTP-CANDIDATE _MT-BYTES-A ;

: _MTP-AT  ( position -- c )
    _MTP-BYTES + C@ ;

: _MTP-OWS?  ( c -- flag )
    DUP 32 = SWAP 9 = OR ;

: _MTP-SKIP-OWS  ( -- )
    BEGIN _MTP-POS @ _MTP-U @ < WHILE
        _MTP-POS @ _MTP-AT _MTP-OWS? 0= IF EXIT THEN
        1 _MTP-POS +!
    REPEAT ;

: _MTP-TCHAR?  ( c -- flag )
    DUP 48 58 WITHIN IF DROP -1 EXIT THEN
    DUP 65 91 WITHIN IF DROP -1 EXIT THEN
    DUP 97 123 WITHIN IF DROP -1 EXIT THEN
    DUP 33 = IF DROP -1 EXIT THEN
    DUP 35 40 WITHIN IF DROP -1 EXIT THEN
    DUP 42 = IF DROP -1 EXIT THEN
    DUP 43 = IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    DUP 94 = IF DROP -1 EXIT THEN
    DUP 95 = IF DROP -1 EXIT THEN
    DUP 96 = IF DROP -1 EXIT THEN
    DUP 124 = IF DROP -1 EXIT THEN
    126 = ;

: _MTP-TAKE-TOKEN?  ( -- flag )
    _MTP-POS @ _MTP-TOKEN-O !
    BEGIN
        _MTP-POS @ _MTP-U @ < IF
            _MTP-POS @ _MTP-AT _MTP-TCHAR?
        ELSE
            0
        THEN
    WHILE
        1 _MTP-POS +!
    REPEAT
    _MTP-POS @ _MTP-TOKEN-O @ - DUP _MTP-TOKEN-U !
    0> ;

: _MTP-QDTEXT?  ( c -- flag )
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 32 = IF DROP -1 EXIT THEN
    DUP 33 = IF DROP -1 EXIT THEN
    DUP 35 92 WITHIN IF DROP -1 EXIT THEN
    DUP 93 127 WITHIN IF DROP -1 EXIT THEN
    128 >= ;

: _MTP-QPAIR?  ( c -- flag )
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 32 127 WITHIN IF DROP -1 EXIT THEN
    128 >= ;

: _MTP-WRITE-BYTE  ( c -- )
    _MTP-BYTES _MTP-WRITE @ + C!
    1 _MTP-WRITE +! ;

: _MTP-TAKE-QUOTED?  ( -- flag )
    1 _MTP-POS +!
    _MTP-POS @ DUP _MTP-VALUE-O ! DUP _MTP-READ ! _MTP-WRITE !
    BEGIN _MTP-READ @ _MTP-U @ < WHILE
        _MTP-READ @ _MTP-AT
        DUP 34 = IF
            DROP
            _MTP-WRITE @ _MTP-VALUE-O @ - _MTP-VALUE-U !
            _MTP-READ @ 1+ _MTP-POS !
            -1 EXIT
        THEN
        DUP 92 = IF
            DROP
            1 _MTP-READ +!
            _MTP-READ @ _MTP-U @ >= IF 0 EXIT THEN
            _MTP-READ @ _MTP-AT DUP _MTP-QPAIR? 0= IF DROP 0 EXIT THEN
            _MTP-WRITE-BYTE
            1 _MTP-READ +!
        ELSE
            DUP _MTP-QDTEXT? 0= IF DROP 0 EXIT THEN
            _MTP-WRITE-BYTE
            1 _MTP-READ +!
        THEN
    REPEAT
    0 ;

: _MTP-TAKE-VALUE?  ( -- flag )
    _MTP-POS @ _MTP-U @ >= IF 0 EXIT THEN
    _MTP-POS @ _MTP-AT 34 = IF _MTP-TAKE-QUOTED? EXIT THEN
    _MTP-TAKE-TOKEN? DUP IF
        _MTP-TOKEN-O @ _MTP-VALUE-O !
        _MTP-TOKEN-U @ _MTP-VALUE-U !
    THEN ;

: _MTP-STORE-PARAM  ( -- )
    _MTP-CANDIDATE _MT-PARAM-N + @
    _MTP-CANDIDATE _MT-ENTRY
    DUP _MTP-NAME-O @ SWAP _MTE-NAME-O + !
    DUP _MTP-NAME-U @ SWAP _MTE-NAME-U + !
    DUP _MTP-VALUE-O @ SWAP _MTE-VALUE-O + !
    _MTP-VALUE-U @ SWAP _MTE-VALUE-U + !
    1 _MTP-CANDIDATE _MT-PARAM-N + +! ;

: _MTP-PARSE-BODY  ( -- status )
    0 _MTP-POS !
    _MTP-SKIP-OWS
    _MTP-TAKE-TOKEN? 0= IF MTYPE-S-INVALID EXIT THEN
    _MTP-TOKEN-O @ _MTP-CANDIDATE _MT-TYPE-O + !
    _MTP-TOKEN-U @ _MTP-CANDIDATE _MT-TYPE-U + !
    _MTP-POS @ _MTP-U @ >= IF MTYPE-S-INVALID EXIT THEN
    _MTP-POS @ _MTP-AT 47 <> IF MTYPE-S-INVALID EXIT THEN
    1 _MTP-POS +!
    _MTP-TAKE-TOKEN? 0= IF MTYPE-S-INVALID EXIT THEN
    _MTP-TOKEN-O @ _MTP-CANDIDATE _MT-SUBTYPE-O + !
    _MTP-TOKEN-U @ _MTP-CANDIDATE _MT-SUBTYPE-U + !

    BEGIN
        _MTP-SKIP-OWS
        _MTP-POS @ _MTP-U @ = IF MTYPE-S-OK EXIT THEN
        _MTP-POS @ _MTP-AT 59 <> IF MTYPE-S-INVALID EXIT THEN
        1 _MTP-POS +!
        _MTP-SKIP-OWS
        _MTP-TAKE-TOKEN? 0= IF MTYPE-S-INVALID EXIT THEN
        _MTP-TOKEN-O @ _MTP-NAME-O !
        _MTP-TOKEN-U @ _MTP-NAME-U !
        _MTP-POS @ _MTP-U @ >= IF MTYPE-S-INVALID EXIT THEN
        _MTP-POS @ _MTP-AT 61 <> IF MTYPE-S-INVALID EXIT THEN
        1 _MTP-POS +!
        _MTP-TAKE-VALUE? 0= IF MTYPE-S-INVALID EXIT THEN
        _MTP-CANDIDATE _MT-PARAM-N + @ MTYPE-PARAM-MAX >= IF
            MTYPE-S-CAPACITY EXIT
        THEN
        _MTP-STORE-PARAM
    AGAIN ;

: _MTYPE-PARSE  ( value-a value-u model -- status )
    _MTP-DEST ! _MTP-U ! _MTP-A !
    _MTP-DEST @ 0> 0= IF MTYPE-S-INVALID EXIT THEN
    _MTP-U @ 0< IF MTYPE-S-INVALID EXIT THEN
    _MTP-U @ MTYPE-VALUE-MAX > IF MTYPE-S-CAPACITY EXIT THEN
    _MTP-U @ 0= IF MTYPE-S-INVALID EXIT THEN
    _MTP-A @ 0> 0= IF MTYPE-S-INVALID EXIT THEN

    _MTP-CANDIDATE MTYPE-SIZE 0 FILL
    _MTP-U @ _MTP-CANDIDATE _MT-SOURCE-U + !
    _MTP-A @ _MTP-BYTES _MTP-U @ CMOVE
    _MTP-PARSE-BODY DUP IF EXIT THEN DROP
    _MTYPE-MAGIC _MTP-CANDIDATE _MT-MAGIC + !
    _MTP-CANDIDATE _MTP-DEST @ MTYPE-SIZE CMOVE
    MTYPE-S-OK ;

' _MTYPE-PARSE CONSTANT _mtype-parse-xt
: MTYPE-PARSE  ( value-a value-u model -- status )
    _mtype-parse-xt _media-type-guard WITH-GUARD ;
