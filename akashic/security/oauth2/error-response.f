\ =====================================================================
\  error-response.f - Ephemeral generic OAuth 2 error decoding
\ =====================================================================
\  One strict RFC 6749 OAuth error response is decoded into a view inside
\  a caller-owned workspace.  The view and every decoded field are valid
\  only while the caller callback runs.  The complete workspace is wiped
\  after every admitted parse result, callback return, or caught THROW.
\
\  Recognized members:
\
\    error              required, nonempty RFC 6749 NQSCHAR string
\    error_description  optional, nonempty RFC 6749 NQSCHAR string
\    error_uri          optional RFC 3986 URI-reference, including empty
\
\  Unknown members pass complete strict JSON validation and are ignored.
\  This module owns no HTTP, endpoint selection, retry, nonce, DPoP,
\  AT Protocol, persistence, or application policy.
\
\  Public API:
\
\    OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE
\    OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR
\    OAUTH2-ERROR-RESPONSE-WITH
\    OAUTH2-ERROR-VIEW-ERROR@
\    OAUTH2-ERROR-VIEW-DESCRIPTION@
\    OAUTH2-ERROR-VIEW-URI@
\ =====================================================================

PROVIDED akashic-oauth2-errorrsp

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../jose/json-object.f

\ =====================================================================
\  Public status and capacity vocabulary
\ =====================================================================

0  CONSTANT OAUTH2-ERROR-RESPONSE-S-OK
1  CONSTANT OAUTH2-ERROR-RESPONSE-S-INVALID
2  CONSTANT OAUTH2-ERROR-RESPONSE-S-CAPACITY
3  CONSTANT OAUTH2-ERROR-RESPONSE-S-ALIAS
4  CONSTANT OAUTH2-ERROR-RESPONSE-S-JSON
5  CONSTANT OAUTH2-ERROR-RESPONSE-S-MISSING
6  CONSTANT OAUTH2-ERROR-RESPONSE-S-TYPE
7  CONSTANT OAUTH2-ERROR-RESPONSE-S-VALUE
8  CONSTANT OAUTH2-ERROR-RESPONSE-S-DUPLICATE
9  CONSTANT OAUTH2-ERROR-RESPONSE-S-CALLBACK
10 CONSTANT OAUTH2-ERROR-RESPONSE-S-INTERNAL
11 CONSTANT OAUTH2-ERROR-RESPONSE-S-RANGE
12 CONSTANT OAUTH2-ERROR-RESPONSE-S-PROTECTED
13 CONSTANT OAUTH2-ERROR-RESPONSE-S-PLATFORM

: OAUTH2-ERROR-RESPONSE-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-ERROR-RESPONSE-S-OK >=
    SWAP OAUTH2-ERROR-RESPONSE-S-PLATFORM <= AND ;

256  CONSTANT OAUTH2-ERROR-VIEW-ERROR-CAPACITY
1024 CONSTANT OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY
4096 CONSTANT OAUTH2-ERROR-VIEW-URI-CAPACITY

1 CONSTANT _O2ER-P-ERROR
2 CONSTANT _O2ER-P-DESCRIPTION
4 CONSTANT _O2ER-P-URI

_O2ER-P-ERROR CONSTANT _O2ER-REQUIRED-PRESENCE

\ =====================================================================
\  Ephemeral callback view
\ =====================================================================

0x4F32455256494557 CONSTANT _O2ER-VIEW-MAGIC-VALUE

 0 CONSTANT _O2ERV-MAGIC
 8 CONSTANT _O2ERV-ERROR-U
16 CONSTANT _O2ERV-DESCRIPTION-U
24 CONSTANT _O2ERV-URI-U
32 CONSTANT _O2ERV-PRESENT
40 CONSTANT _O2ERV-HEADER-SIZE

_O2ERV-HEADER-SIZE CONSTANT _O2ERV-ERROR-OFF
_O2ERV-ERROR-OFF OAUTH2-ERROR-VIEW-ERROR-CAPACITY +
    CONSTANT _O2ERV-DESCRIPTION-OFF
_O2ERV-DESCRIPTION-OFF OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY +
    CONSTANT _O2ERV-URI-OFF
_O2ERV-URI-OFF OAUTH2-ERROR-VIEW-URI-CAPACITY +
    CONSTANT _O2ER-VIEW-SIZE

: _O2ERV.MAGIC        ( view -- address ) _O2ERV-MAGIC + ;
: _O2ERV.ERROR-U      ( view -- address ) _O2ERV-ERROR-U + ;
: _O2ERV.DESCRIPTION-U ( view -- address ) _O2ERV-DESCRIPTION-U + ;
: _O2ERV.URI-U        ( view -- address ) _O2ERV-URI-U + ;
: _O2ERV.PRESENT      ( view -- address ) _O2ERV-PRESENT + ;

: _O2ERV.ERROR        ( view -- address ) _O2ERV-ERROR-OFF + ;
: _O2ERV.DESCRIPTION  ( view -- address ) _O2ERV-DESCRIPTION-OFF + ;
: _O2ERV.URI          ( view -- address ) _O2ERV-URI-OFF + ;

\ =====================================================================
\  Caller admission and view access
\ =====================================================================

: _O2ER-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP OAUTH2-ERROR-RESPONSE-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP OAUTH2-ERROR-RESPONSE-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP OAUTH2-ERROR-RESPONSE-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP OAUTH2-ERROR-RESPONSE-S-PLATFORM EXIT
    THEN
    DROP OAUTH2-ERROR-RESPONSE-S-PLATFORM ;

: _O2ER-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _O2ER-CALLER>STATUS ;

: _O2ER-REQUIRED-LENGTH?  ( length capacity -- flag )
    OVER 0> IF
        U> 0=
    ELSE
        2DROP 0
    THEN ;

: _O2ER-OPTIONAL-LENGTH?  ( length capacity -- flag )
    OVER 0< IF
        2DROP 0 EXIT
    THEN
    U> 0= ;

: _O2ER-VIEW-VALID?  ( view -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _O2ER-VIEW-SIZE _O2ER-ADMIT-SPAN
        OAUTH2-ERROR-RESPONSE-S-OK <> IF
        DROP 0 EXIT
    THEN
    DUP _O2ERV.MAGIC @ _O2ER-VIEW-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP _O2ERV.PRESENT @ DUP 0< IF
        2DROP 0 EXIT
    THEN
    DUP _O2ER-P-ERROR _O2ER-P-DESCRIPTION OR
        _O2ER-P-URI OR AND OVER <> IF
        2DROP 0 EXIT
    THEN
    _O2ER-P-ERROR AND 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2ERV.ERROR-U @
        OAUTH2-ERROR-VIEW-ERROR-CAPACITY
        _O2ER-REQUIRED-LENGTH? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2ERV.PRESENT @ _O2ER-P-DESCRIPTION AND IF
        DUP _O2ERV.DESCRIPTION-U @
            OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY
            _O2ER-REQUIRED-LENGTH? 0= IF
            DROP 0 EXIT
        THEN
    ELSE
        DUP _O2ERV.DESCRIPTION-U @ 0<> IF
            DROP 0 EXIT
        THEN
    THEN
    DUP _O2ERV.PRESENT @ _O2ER-P-URI AND IF
        _O2ERV.URI-U @
            OAUTH2-ERROR-VIEW-URI-CAPACITY
            _O2ER-OPTIONAL-LENGTH?
    ELSE
        _O2ERV.URI-U @ 0=
    THEN ;

: _O2ER-VIEW-TEXT@  ( view length-offset data-offset -- address length )
    >R
    OVER SWAP + @
    SWAP R> + SWAP ;

: OAUTH2-ERROR-VIEW-ERROR@
  ( view -- address length status )
    DUP _O2ER-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-ERROR-RESPONSE-S-INVALID EXIT
    THEN
    _O2ERV-ERROR-U _O2ERV-ERROR-OFF _O2ER-VIEW-TEXT@
    OAUTH2-ERROR-RESPONSE-S-OK ;

: OAUTH2-ERROR-VIEW-DESCRIPTION@
  ( view -- address length status )
    DUP _O2ER-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-ERROR-RESPONSE-S-INVALID EXIT
    THEN
    DUP _O2ERV.PRESENT @ _O2ER-P-DESCRIPTION AND 0= IF
        DROP 0 0 OAUTH2-ERROR-RESPONSE-S-MISSING EXIT
    THEN
    _O2ERV-DESCRIPTION-U _O2ERV-DESCRIPTION-OFF
    _O2ER-VIEW-TEXT@
    OAUTH2-ERROR-RESPONSE-S-OK ;

: OAUTH2-ERROR-VIEW-URI@
  ( view -- address length status )
    DUP _O2ER-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-ERROR-RESPONSE-S-INVALID EXIT
    THEN
    DUP _O2ERV.PRESENT @ _O2ER-P-URI AND 0= IF
        DROP 0 0 OAUTH2-ERROR-RESPONSE-S-MISSING EXIT
    THEN
    _O2ERV-URI-U _O2ERV-URI-OFF _O2ER-VIEW-TEXT@
    OAUTH2-ERROR-RESPONSE-S-OK ;

\ =====================================================================
\  Caller-owned operation workspace
\ =====================================================================

16 CONSTANT _O2ER-MAX-MEMBERS
1024 CONSTANT _O2ER-NAMES-SIZE

_O2ER-MAX-MEMBERS JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." OAuth 2 error response descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _O2ER-DESCRIPTOR-SIZE

 0 CONSTANT _O2ERW-SOURCE
 8 CONSTANT _O2ERW-SOURCE-U
16 CONSTANT _O2ERW-CALLBACK
24 CONSTANT _O2ERW-CONTEXT
32 CONSTANT _O2ERW-NAME-A
40 CONSTANT _O2ERW-NAME-U
48 CONSTANT _O2ERW-VALUE-A
56 CONSTANT _O2ERW-VALUE-U
64 CONSTANT _O2ERW-VALUE-TYPE
72 CONSTANT _O2ERW-PRESENT
80 CONSTANT _O2ERW-SCAN
88 CONSTANT _O2ERW-ACCUMULATOR
96 CONSTANT _O2ERW-HEADER-SIZE

_O2ERW-HEADER-SIZE CONSTANT _O2ERW-DESCRIPTOR-OFF
_O2ERW-DESCRIPTOR-OFF _O2ER-DESCRIPTOR-SIZE +
    CONSTANT _O2ERW-NAMES-OFF
_O2ERW-NAMES-OFF _O2ER-NAMES-SIZE +
    CONSTANT _O2ERW-JSON-OFF
_O2ERW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
    CONSTANT _O2ERW-VIEW-OFF
_O2ERW-VIEW-OFF _O2ER-VIEW-SIZE +
    CONSTANT OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE

: _O2ERW.SOURCE       ( workspace -- address ) _O2ERW-SOURCE + ;
: _O2ERW.SOURCE-U     ( workspace -- address ) _O2ERW-SOURCE-U + ;
: _O2ERW.CALLBACK     ( workspace -- address ) _O2ERW-CALLBACK + ;
: _O2ERW.CONTEXT      ( workspace -- address ) _O2ERW-CONTEXT + ;
: _O2ERW.NAME-A       ( workspace -- address ) _O2ERW-NAME-A + ;
: _O2ERW.NAME-U       ( workspace -- address ) _O2ERW-NAME-U + ;
: _O2ERW.VALUE-A      ( workspace -- address ) _O2ERW-VALUE-A + ;
: _O2ERW.VALUE-U      ( workspace -- address ) _O2ERW-VALUE-U + ;
: _O2ERW.VALUE-TYPE   ( workspace -- address ) _O2ERW-VALUE-TYPE + ;
: _O2ERW.PRESENT      ( workspace -- address ) _O2ERW-PRESENT + ;
: _O2ERW.SCAN         ( workspace -- address ) _O2ERW-SCAN + ;
: _O2ERW.ACCUMULATOR  ( workspace -- address ) _O2ERW-ACCUMULATOR + ;

: _O2ERW.DESCRIPTOR  ( workspace -- address )
    _O2ERW-DESCRIPTOR-OFF + ;
: _O2ERW.NAMES       ( workspace -- address ) _O2ERW-NAMES-OFF + ;
: _O2ERW.JSON        ( workspace -- address ) _O2ERW-JSON-OFF + ;
: _O2ERW.VIEW        ( workspace -- address ) _O2ERW-VIEW-OFF + ;

: _O2ER-WIPE  ( workspace -- )
    OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE 0 FILL ;

: OAUTH2-ERROR-RESPONSE-WORKSPACE-CLEAR  ( workspace -- status )
    DUP OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE
        _O2ER-ADMIT-SPAN ?DUP IF
        NIP EXIT
    THEN
    DUP 7 AND IF
        DROP OAUTH2-ERROR-RESPONSE-S-INVALID EXIT
    THEN
    _O2ER-WIPE
    OAUTH2-ERROR-RESPONSE-S-OK ;

\ =====================================================================
\  Geometry and stack helpers
\ =====================================================================

: _O2ER-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _O2ER-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;
: _O2ER-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;

: _O2ER-RETURN5  ( x1 x2 x3 x4 x5 status -- status )
    >R _O2ER-DROP5 R> ;

: _O2ER-WITH-GEOMETRY
  ( source source-u callback context workspace -- status )
    DUP OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE _O2ER-ADMIT-SPAN
        ?DUP IF
        _O2ER-RETURN5 EXIT
    THEN
    DUP 7 AND IF
        OAUTH2-ERROR-RESPONSE-S-INVALID _O2ER-RETURN5 EXIT
    THEN
    4 PICK 4 PICK _O2ER-ADMIT-SPAN ?DUP IF
        _O2ER-RETURN5 EXIT
    THEN
    2 PICK 0= IF
        OAUTH2-ERROR-RESPONSE-S-INVALID _O2ER-RETURN5 EXIT
    THEN
    3 PICK 0= IF
        OAUTH2-ERROR-RESPONSE-S-INVALID _O2ER-RETURN5 EXIT
    THEN
    3 PICK JOSE-JSON-MAX-DOCUMENT-BYTES U> IF
        OAUTH2-ERROR-RESPONSE-S-CAPACITY _O2ER-RETURN5 EXIT
    THEN
    4 PICK 4 PICK 2 PICK OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-ERROR-RESPONSE-S-ALIAS _O2ER-RETURN5 EXIT
    THEN
    OAUTH2-ERROR-RESPONSE-S-OK _O2ER-RETURN5 ;

\ =====================================================================
\  Strict JSON field decoding
\ =====================================================================

: _O2ER-JSON>STATUS  ( json-status -- status )
    DUP JOSE-JSON-S-OK = IF
        DROP OAUTH2-ERROR-RESPONSE-S-OK EXIT
    THEN
    DUP JOSE-JSON-S-DUPLICATE = IF
        DROP OAUTH2-ERROR-RESPONSE-S-DUPLICATE EXIT
    THEN
    DUP JOSE-JSON-S-CAPACITY = IF
        DROP OAUTH2-ERROR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-MEMBERS = IF
        DROP OAUTH2-ERROR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-STRING = IF
        DROP OAUTH2-ERROR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-DOCUMENT = IF
        DROP OAUTH2-ERROR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-SYNTAX = IF
        DROP OAUTH2-ERROR-RESPONSE-S-JSON EXIT
    THEN
    DUP JOSE-JSON-S-UTF8 = IF
        DROP OAUTH2-ERROR-RESPONSE-S-JSON EXIT
    THEN
    DUP JOSE-JSON-S-DEPTH = IF
        DROP OAUTH2-ERROR-RESPONSE-S-JSON EXIT
    THEN
    DROP OAUTH2-ERROR-RESPONSE-S-INTERNAL ;

: _O2ER-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _O2ERW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP OAUTH2-ERROR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2ERW.VALUE-TYPE !
    R@ _O2ERW.VALUE-U !
    R@ _O2ERW.SOURCE @ + R@ _O2ERW.VALUE-A !
    R@ _O2ERW.NAME-U !
    R@ _O2ERW.NAMES + R@ _O2ERW.NAME-A !
    R> DROP OAUTH2-ERROR-RESPONSE-S-OK ;

: _O2ER-NAME=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _O2ERW.NAME-A @ R@ _O2ERW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _O2ER-COPY-MEMBER-STRING
  ( destination length-cell capacity workspace -- status )
    >R
    R@ _O2ERW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        _O2ER-DROP3 R> DROP OAUTH2-ERROR-RESPONSE-S-TYPE EXIT
    THEN
    R@ _O2ERW.SCAN !
    R@ _O2ERW.NAME-U !
    R@ _O2ERW.NAME-A !

    R@ _O2ERW.VALUE-A @ R@ _O2ERW.VALUE-U @
    R@ _O2ERW.NAME-A @ R@ _O2ERW.SCAN @
    R@ _O2ERW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        DUP JOSE-JSON-S-CAPACITY =
        OVER JOSE-JSON-S-STRING = OR IF
            2DROP R> DROP
            OAUTH2-ERROR-RESPONSE-S-CAPACITY EXIT
        THEN
        2DROP R> DROP OAUTH2-ERROR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2ERW.NAME-U @ !
    R> DROP OAUTH2-ERROR-RESPONSE-S-OK ;

: _O2ER-MARK-PRESENT  ( mask workspace -- status )
    >R
    DUP R@ _O2ERW.PRESENT @ AND IF
        DROP R> DROP OAUTH2-ERROR-RESPONSE-S-DUPLICATE EXIT
    THEN
    R@ _O2ERW.PRESENT @ OR R@ _O2ERW.PRESENT !
    R> DROP OAUTH2-ERROR-RESPONSE-S-OK ;

\ RFC 6749 NQSCHAR: %x20-21 / %x23-5B / %x5D-7E.
: _O2ER-NQSCHAR-BYTE?  ( byte -- flag )
    DUP 0x20 0x22 WITHIN IF DROP -1 EXIT THEN
    DUP 0x23 0x5C WITHIN IF DROP -1 EXIT THEN
    0x5D 0x7F WITHIN ;

: _O2ER-NQSCHAR?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ _O2ER-NQSCHAR-BYTE? 0= IF
            2DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

\ =====================================================================
\  RFC 3986 URI-reference validation for error_uri
\ =====================================================================

: _O2ER-DIGIT?  ( byte -- flag )
    48 58 WITHIN ;

: _O2ER-ALPHA?  ( byte -- flag )
    DUP 65 91 WITHIN
    SWAP 97 123 WITHIN OR ;

: _O2ER-HEXDIGIT?  ( byte -- flag )
    DUP _O2ER-DIGIT? IF DROP -1 EXIT THEN
    DUP 65 71 WITHIN
    SWAP 97 103 WITHIN OR ;

: _O2ER-UNRESERVED?  ( byte -- flag )
    DUP _O2ER-ALPHA? IF DROP -1 EXIT THEN
    DUP _O2ER-DIGIT? IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    DUP 95 = IF DROP -1 EXIT THEN
    126 = ;

: _O2ER-SUBDELIM?  ( byte -- flag )
    DUP 33 = IF DROP -1 EXIT THEN
    DUP 36 = IF DROP -1 EXIT THEN
    DUP 38 = IF DROP -1 EXIT THEN
    DUP 39 = IF DROP -1 EXIT THEN
    DUP 40 = IF DROP -1 EXIT THEN
    DUP 41 = IF DROP -1 EXIT THEN
    DUP 42 = IF DROP -1 EXIT THEN
    DUP 43 = IF DROP -1 EXIT THEN
    DUP 44 = IF DROP -1 EXIT THEN
    DUP 59 = IF DROP -1 EXIT THEN
    61 = ;

: _O2ER-SCHEME-CHAR?  ( byte -- flag )
    DUP _O2ER-ALPHA? IF DROP -1 EXIT THEN
    DUP _O2ER-DIGIT? IF DROP -1 EXIT THEN
    DUP 43 = IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    46 = ;

: _O2ER-REGNAME-CHAR?  ( byte -- flag )
    DUP _O2ER-UNRESERVED? IF DROP -1 EXIT THEN
    _O2ER-SUBDELIM? ;

: _O2ER-USERINFO-CHAR?  ( byte -- flag )
    DUP _O2ER-REGNAME-CHAR? IF DROP -1 EXIT THEN
    58 = ;

: _O2ER-PCHAR?  ( byte -- flag )
    DUP _O2ER-REGNAME-CHAR? IF DROP -1 EXIT THEN
    DUP 58 = IF DROP -1 EXIT THEN
    64 = ;

: _O2ER-PCHAR-NC?  ( byte -- flag )
    DUP _O2ER-REGNAME-CHAR? IF DROP -1 EXIT THEN
    64 = ;

: _O2ER-PATH-CHAR?  ( byte -- flag )
    DUP _O2ER-PCHAR? IF DROP -1 EXIT THEN
    47 = ;

: _O2ER-QUERY-FRAGMENT-CHAR?  ( byte -- flag )
    DUP _O2ER-PCHAR? IF DROP -1 EXIT THEN
    DUP 47 = IF DROP -1 EXIT THEN
    63 = ;

: _O2ER-IPVFUTURE-CHAR?  ( byte -- flag )
    _O2ER-USERINFO-CHAR? ;

: _O2ER-RAW-SEQUENCE?  ( address length predicate -- flag )
    >R
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ R@ EXECUTE 0= IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _O2ER-PCT-TRIPLET?  ( address length -- flag )
    DUP 3 U< IF 2DROP 0 EXIT THEN
    OVER C@ 37 <> IF 2DROP 0 EXIT THEN
    OVER 1+ C@ _O2ER-HEXDIGIT? 0= IF 2DROP 0 EXIT THEN
    OVER 2 + C@ _O2ER-HEXDIGIT?
    >R 2DROP R> ;

\ Validate one RFC 3986 component without decoding pct-encoded octets.
\ The supplied predicate covers every admitted raw byte except "%".
: _O2ER-URI-SEQUENCE?  ( address length predicate -- flag )
    >R
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ 37 = IF
            2DUP _O2ER-PCT-TRIPLET? 0= IF
                2DROP R> DROP 0 EXIT
            THEN
            3 - SWAP 3 + SWAP
        ELSE
            OVER C@ R@ EXECUTE 0= IF
                2DROP R> DROP 0 EXIT
            THEN
            1- SWAP 1+ SWAP
        THEN
    REPEAT
    2DROP R> DROP -1 ;

: _O2ER-SCHEME?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ _O2ER-ALPHA? 0= IF 2DROP 0 EXIT THEN
    1- SWAP 1+ SWAP
    ['] _O2ER-SCHEME-CHAR? _O2ER-RAW-SEQUENCE? ;

: _O2ER-REGNAME?  ( address length -- flag )
    ['] _O2ER-REGNAME-CHAR? _O2ER-URI-SEQUENCE? ;

: _O2ER-USERINFO?  ( address length -- flag )
    ['] _O2ER-USERINFO-CHAR? _O2ER-URI-SEQUENCE? ;

: _O2ER-PCHAR-NC-SEQUENCE?  ( address length -- flag )
    ['] _O2ER-PCHAR-NC? _O2ER-URI-SEQUENCE? ;

: _O2ER-PATH-SEQUENCE?  ( address length -- flag )
    ['] _O2ER-PATH-CHAR? _O2ER-URI-SEQUENCE? ;

: _O2ER-QUERY-FRAGMENT?  ( address length -- flag )
    ['] _O2ER-QUERY-FRAGMENT-CHAR? _O2ER-URI-SEQUENCE? ;

: _O2ER-FIND-BYTE  ( address length byte -- index|-1 )
    >R
    DUP 0< IF 2DROP R> DROP -1 EXIT THEN
    0
    BEGIN DUP 2 PICK U< WHILE
        2 PICK OVER + C@ R@ = IF
            >R 2DROP R> R> DROP EXIT
        THEN
        1+
    REPEAT
    _O2ER-DROP3 R> DROP -1 ;

: _O2ER-FIND-DOUBLE-COLON  ( address length -- index|-1 )
    DUP 0< IF 2DROP -1 EXIT THEN
    DUP 2 U< IF 2DROP -1 EXIT THEN
    0
    BEGIN DUP 1+ 2 PICK U< WHILE
        2 PICK OVER + C@ 58 =
        3 PICK 2 PICK + 1+ C@ 58 = AND IF
            >R 2DROP R> EXIT
        THEN
        1+
    REPEAT
    _O2ER-DROP3 -1 ;

: _O2ER-DIGITS?  ( address length -- flag )
    ['] _O2ER-DIGIT? _O2ER-RAW-SEQUENCE? ;

: _O2ER-H16?  ( address length -- flag )
    DUP 1 U< OVER 4 U> OR IF 2DROP 0 EXIT THEN
    ['] _O2ER-HEXDIGIT? _O2ER-RAW-SEQUENCE? ;

: _O2ER-DEC-OCTET?  ( address length -- flag )
    DUP 1 U< OVER 3 U> OR IF 2DROP 0 EXIT THEN
    DUP 1 > IF
        OVER C@ 48 = IF 2DROP 0 EXIT THEN
    THEN
    0 >R
    BEGIN DUP WHILE
        OVER C@ DUP _O2ER-DIGIT? 0= IF
            DROP 2DROP R> DROP 0 EXIT
        THEN
        48 -
        R> 10 * + >R
        1- SWAP 1+ SWAP
    REPEAT
    2DROP
    R> 255 U> 0= ;

: _O2ER-IPV4-CUT  ( address length -- next-address next-length flag )
    2DUP 46 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP 2DROP 0 0 0 EXIT
    THEN
    >R
    OVER R@ _O2ER-DEC-OCTET? 0= IF
        2DROP R> DROP 0 0 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP -1 ;

: _O2ER-IPV4?  ( address length -- flag )
    _O2ER-IPV4-CUT 0= IF 2DROP 0 EXIT THEN
    _O2ER-IPV4-CUT 0= IF 2DROP 0 EXIT THEN
    _O2ER-IPV4-CUT 0= IF 2DROP 0 EXIT THEN
    _O2ER-DEC-OCTET? ;

\ Return the number of 16-bit units in one colon-separated IPv6 side.
\ Embedded IPv4 is admitted only as the final token when allow-ipv4 is true.
: _O2ER-IPV6-SIDE  ( address length allow-ipv4 -- units|-1 )
    >R
    DUP 0= IF 2DROP R> DROP 0 EXIT THEN
    0 >R
    BEGIN
        2DUP 58 _O2ER-FIND-BYTE
        DUP -1 = IF
            DROP
            2DUP 46 _O2ER-FIND-BYTE -1 <> IF
                R> R> 0= IF
                    _O2ER-DROP3 -1 EXIT
                THEN
                >R
                _O2ER-IPV4? 0= IF
                    R> DROP -1 EXIT
                THEN
                R> 2 + EXIT
            THEN
            _O2ER-H16? 0= IF
                R> DROP R> DROP -1 EXIT
            THEN
            R> 1+ R> DROP EXIT
        THEN
        >R
        OVER R@ _O2ER-H16? 0= IF
            2DROP
            R> DROP R> DROP R> DROP
            -1 EXIT
        THEN
        SWAP R@ + 1+ SWAP R@ - 1-
        R> DROP
        R> 1+ >R
    AGAIN ;

: _O2ER-IPV6?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    2DUP _O2ER-FIND-DOUBLE-COLON
    DUP -1 = IF
        DROP -1 _O2ER-IPV6-SIDE 8 = EXIT
    THEN
    >R
    OVER R@ 0 _O2ER-IPV6-SIDE
    DUP 0< IF
        _O2ER-DROP3 R> DROP 0 EXIT
    THEN
    2 PICK R@ + 2 +
    2 PICK R@ - 2 -
    -1 _O2ER-IPV6-SIDE
    DUP 0< IF
        _O2ER-DROP4 R> DROP 0 EXIT
    THEN
    + 8 U<
    >R 2DROP R> R> DROP ;

: _O2ER-IPVFUTURE?  ( address length -- flag )
    DUP 4 U< IF 2DROP 0 EXIT THEN
    OVER C@ DUP 118 = SWAP 86 = OR 0= IF
        2DROP 0 EXIT
    THEN
    1- SWAP 1+ SWAP
    2DUP 46 _O2ER-FIND-BYTE
    DUP 1 < IF
        DROP 2DROP 0 EXIT
    THEN
    >R
    OVER R@ ['] _O2ER-HEXDIGIT?
        _O2ER-RAW-SEQUENCE? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    DUP 0= IF 2DROP 0 EXIT THEN
    ['] _O2ER-IPVFUTURE-CHAR? _O2ER-RAW-SEQUENCE? ;

: _O2ER-IP-LITERAL?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 118 = SWAP 86 = OR IF
        _O2ER-IPVFUTURE? EXIT
    THEN
    _O2ER-IPV6? ;

: _O2ER-BRACKETED-HOSTPORT?  ( address length -- flag )
    DUP 2 U< IF 2DROP 0 EXIT THEN
    2DUP 93 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP 2DROP 0 EXIT
    THEN
    >R
    OVER 1+ R@ 1- _O2ER-IP-LITERAL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 58 <> IF 2DROP 0 EXIT THEN
    1- SWAP 1+ SWAP
    _O2ER-DIGITS? ;

: _O2ER-HOSTPORT?  ( address length -- flag )
    DUP IF
        OVER C@ 91 = IF
            _O2ER-BRACKETED-HOSTPORT? EXIT
        THEN
    THEN
    2DUP 58 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP _O2ER-REGNAME? EXIT
    THEN
    >R
    OVER R@ _O2ER-REGNAME? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    _O2ER-DIGITS? ;

: _O2ER-AUTHORITY?  ( address length -- flag )
    2DUP 64 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP _O2ER-HOSTPORT? EXIT
    THEN
    >R
    OVER R@ _O2ER-USERINFO? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    _O2ER-HOSTPORT? ;

: _O2ER-PATH-ABEMPTY?  ( address length -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 47 <> IF 2DROP 0 EXIT THEN
    _O2ER-PATH-SEQUENCE? ;

: _O2ER-PATH-ABSOLUTE?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 47 <> IF 2DROP 0 EXIT THEN
    DUP 1 = IF 2DROP -1 EXIT THEN
    OVER 1+ C@ 47 = IF 2DROP 0 EXIT THEN
    _O2ER-PATH-SEQUENCE? ;

: _O2ER-PATH-ROOTLESS?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 47 = IF 2DROP 0 EXIT THEN
    _O2ER-PATH-SEQUENCE? ;

: _O2ER-PATH-NOSCHEME?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 47 = IF 2DROP 0 EXIT THEN
    2DUP 47 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP _O2ER-PCHAR-NC-SEQUENCE? EXIT
    THEN
    >R
    OVER R@ _O2ER-PCHAR-NC-SEQUENCE? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + SWAP R@ -
    R> DROP
    _O2ER-PATH-SEQUENCE? ;

: _O2ER-DOUBLE-SLASH?  ( address length -- flag )
    DUP 2 U< IF 2DROP 0 EXIT THEN
    OVER C@ 47 =
    2 PICK 1+ C@ 47 = AND
    >R 2DROP R> ;

: _O2ER-NETWORK-PART?  ( address length -- flag )
    2 - SWAP 2 + SWAP
    2DUP 47 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP _O2ER-AUTHORITY? EXIT
    THEN
    >R
    OVER R@ _O2ER-AUTHORITY? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + SWAP R@ -
    R> DROP
    _O2ER-PATH-ABEMPTY? ;

: _O2ER-HIER-PART?  ( address length -- flag )
    2DUP _O2ER-DOUBLE-SLASH? IF
        _O2ER-NETWORK-PART? EXIT
    THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 47 = IF
        _O2ER-PATH-ABSOLUTE? EXIT
    THEN
    _O2ER-PATH-ROOTLESS? ;

: _O2ER-RELATIVE-PART?  ( address length -- flag )
    2DUP _O2ER-DOUBLE-SLASH? IF
        _O2ER-NETWORK-PART? EXIT
    THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 47 = IF
        _O2ER-PATH-ABSOLUTE? EXIT
    THEN
    _O2ER-PATH-NOSCHEME? ;

: _O2ER-URI-WITH-SCHEME?  ( address length colon-index -- flag )
    >R
    OVER R@ _O2ER-SCHEME? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    _O2ER-HIER-PART? ;

: _O2ER-URI-CORE?  ( address length -- flag )
    2DUP 58 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP _O2ER-RELATIVE-PART? EXIT
    THEN
    >R
    2DUP 47 _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP R> _O2ER-URI-WITH-SCHEME? EXIT
    THEN
    R@ SWAP U< IF
        R> _O2ER-URI-WITH-SCHEME? EXIT
    THEN
    R> DROP
    _O2ER-RELATIVE-PART? ;

\ Cut the first query/fragment delimiter and validate the suffix.  On
\ success the original address and the prefix length remain for the caller.
: _O2ER-CUT-QUERY-FRAGMENT
  ( address length delimiter -- address prefix-length flag )
    >R
    2DUP R@ _O2ER-FIND-BYTE
    DUP -1 = IF
        DROP R> DROP -1 EXIT
    THEN
    >R
    OVER R@ + 1+
    1 PICK R@ - 1-
    _O2ER-QUERY-FRAGMENT? 0= IF
        2DROP R> DROP R> DROP 0 0 0 EXIT
    THEN
    DROP R> R> DROP -1 ;

: _O2ER-URI-REFERENCE?  ( address length -- flag )
    35 _O2ER-CUT-QUERY-FRAGMENT 0= IF
        2DROP 0 EXIT
    THEN
    63 _O2ER-CUT-QUERY-FRAGMENT 0= IF
        2DROP 0 EXIT
    THEN
    _O2ER-URI-CORE? ;

\ =====================================================================
\  Recognized member policy and strict root processing
\ =====================================================================

: _O2ER-PROCESS-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _O2ER-MEMBER-LOAD
    DUP IF NIP R> DROP EXIT THEN
    2DROP

    S" error" R@ _O2ER-NAME= IF
        R@ _O2ERW.VIEW _O2ERV.ERROR
        R@ _O2ERW.VIEW _O2ERV.ERROR-U
        OAUTH2-ERROR-VIEW-ERROR-CAPACITY
        R@ _O2ER-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2ERW.VIEW _O2ERV.ERROR
        R@ _O2ERW.VIEW _O2ERV.ERROR-U @
        _O2ER-NQSCHAR? 0= IF
            R> DROP OAUTH2-ERROR-RESPONSE-S-VALUE EXIT
        THEN
        _O2ER-P-ERROR
        R@ _O2ER-MARK-PRESENT R> DROP EXIT
    THEN

    S" error_description" R@ _O2ER-NAME= IF
        R@ _O2ERW.VIEW _O2ERV.DESCRIPTION
        R@ _O2ERW.VIEW _O2ERV.DESCRIPTION-U
        OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY
        R@ _O2ER-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2ERW.VIEW _O2ERV.DESCRIPTION
        R@ _O2ERW.VIEW _O2ERV.DESCRIPTION-U @
        _O2ER-NQSCHAR? 0= IF
            R> DROP OAUTH2-ERROR-RESPONSE-S-VALUE EXIT
        THEN
        _O2ER-P-DESCRIPTION
        R@ _O2ER-MARK-PRESENT R> DROP EXIT
    THEN

    S" error_uri" R@ _O2ER-NAME= IF
        R@ _O2ERW.VIEW _O2ERV.URI
        R@ _O2ERW.VIEW _O2ERV.URI-U
        OAUTH2-ERROR-VIEW-URI-CAPACITY
        R@ _O2ER-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2ERW.VIEW _O2ERV.URI
        R@ _O2ERW.VIEW _O2ERV.URI-U @
        _O2ER-URI-REFERENCE? 0= IF
            R> DROP OAUTH2-ERROR-RESPONSE-S-VALUE EXIT
        THEN
        _O2ER-P-URI
        R@ _O2ER-MARK-PRESENT R> DROP EXIT
    THEN

    R> DROP OAUTH2-ERROR-RESPONSE-S-OK ;

: _O2ER-PROCESS-ALL  ( count workspace -- status )
    SWAP 0 SWAP
    BEGIN 2DUP U< WHILE
        2 PICK 2 PICK SWAP _O2ER-PROCESS-MEMBER
        DUP IF
            >R _O2ER-DROP3 R> EXIT
        THEN
        DROP
        SWAP 1+ SWAP
    REPEAT
    _O2ER-DROP3 OAUTH2-ERROR-RESPONSE-S-OK ;

: _O2ER-PARSE-STAGE  ( workspace -- status )
    >R
    R@ _O2ERW.SOURCE @ R@ _O2ERW.SOURCE-U @
    R@ _O2ERW.DESCRIPTOR _O2ER-MAX-MEMBERS
    R@ _O2ERW.NAMES _O2ER-NAMES-SIZE
    R@ _O2ERW.JSON
    JOSE-JSON-OBJECT-PARSE
    _O2ER-JSON>STATUS
    DUP IF R> DROP EXIT THEN DROP

    R@ _O2ERW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP OAUTH2-ERROR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    0 R@ _O2ERW.PRESENT !
    R@ _O2ER-PROCESS-ALL
    DUP IF R> DROP EXIT THEN DROP

    R@ _O2ERW.PRESENT @ _O2ER-REQUIRED-PRESENCE AND
    _O2ER-REQUIRED-PRESENCE <> IF
        R> DROP OAUTH2-ERROR-RESPONSE-S-MISSING EXIT
    THEN
    R@ _O2ERW.PRESENT @
    R@ _O2ERW.VIEW _O2ERV.PRESENT !
    _O2ER-VIEW-MAGIC-VALUE
    R@ _O2ERW.VIEW _O2ERV.MAGIC !
    R> DROP OAUTH2-ERROR-RESPONSE-S-OK ;

\ =====================================================================
\  Admitted callback operation and mandatory cleanup
\ =====================================================================

-17321 CONSTANT _O2ER-E-CALLBACK-STACK
0x4F32455247554152 CONSTANT _O2ER-CALLBACK-GUARD

: _O2ER-CALLBACK-RUN  ( workspace -- callback-status )
    DEPTH >R
    _O2ER-CALLBACK-GUARD SWAP
    DUP _O2ERW.CALLBACK @ >R
    DUP _O2ERW.VIEW
    SWAP _O2ERW.CONTEXT @
    R> EXECUTE
    DEPTH R@ 1+ <> IF
        _O2ER-E-CALLBACK-STACK THROW
    THEN
    OVER _O2ER-CALLBACK-GUARD <> IF
        _O2ER-E-CALLBACK-STACK THROW
    THEN
    NIP
    R> DROP ;

: _O2ER-CALLBACK-SAFE
  ( workspace -- callback-status response-status )
    ['] _O2ER-CALLBACK-RUN CATCH
    DUP IF
        2DROP
        0 OAUTH2-ERROR-RESPONSE-S-CALLBACK EXIT
    THEN
    DROP
    OAUTH2-ERROR-RESPONSE-S-OK ;

: _O2ER-WITH-OP
  \ ( source source-u callback context workspace
  \   -- callback-status response-status )
    DUP _O2ER-WIPE
    4 PICK OVER _O2ERW.SOURCE !
    3 PICK OVER _O2ERW.SOURCE-U !
    2 PICK OVER _O2ERW.CALLBACK !
    1 PICK OVER _O2ERW.CONTEXT !
    NIP NIP NIP NIP

    DUP _O2ER-PARSE-STAGE
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    _O2ER-CALLBACK-SAFE ;

: _O2ER-WITH-CALL
  \ ( source source-u callback context workspace operation-xt
  \   -- callback-status response-status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _O2ER-WIPE
        _O2ER-DROP5
        R> DROP
        0 OAUTH2-ERROR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2ER-WIPE
    R> DROP ;

: OAUTH2-ERROR-RESPONSE-WITH
  \ ( source source-u callback context workspace
  \   -- callback-status response-status )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK
        _O2ER-WITH-GEOMETRY
    DUP IF
        >R _O2ER-DROP5 0 R> EXIT
    THEN
    DROP
    ['] _O2ER-WITH-OP _O2ER-WITH-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _O2ER-GEOMETRY-ABORT  ( -- )
    ." OAuth 2 error response geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ER-NAMES-SIZE JOSE-JSON-MAX-NAME-BYTES U> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ER-DESCRIPTOR-SIZE 688 <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ERV-ERROR-OFF OAUTH2-ERROR-VIEW-ERROR-CAPACITY +
_O2ERV-DESCRIPTION-OFF <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ERV-DESCRIPTION-OFF OAUTH2-ERROR-VIEW-DESCRIPTION-CAPACITY +
_O2ERV-URI-OFF <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ERV-URI-OFF OAUTH2-ERROR-VIEW-URI-CAPACITY +
_O2ER-VIEW-SIZE <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ER-VIEW-SIZE 5416 <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ERW-DESCRIPTOR-OFF _O2ER-DESCRIPTOR-SIZE +
_O2ERW-NAMES-OFF <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ERW-NAMES-OFF _O2ER-NAMES-SIZE +
_O2ERW-JSON-OFF <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ERW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
_O2ERW-VIEW-OFF <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

_O2ERW-VIEW-OFF _O2ER-VIEW-SIZE +
OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]

OAUTH2-ERROR-RESPONSE-WORKSPACE-SIZE 15864 <> [IF]
    _O2ER-GEOMETRY-ABORT
[THEN]
