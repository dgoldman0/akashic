\ =====================================================================
\  token-response.f - Ephemeral generic OAuth 2 token-response decoding
\ =====================================================================
\  One strict JSON token response is decoded into a view inside a
\  caller-owned workspace.  The view and every decoded field are valid
\  only while the caller callback runs.  The complete workspace is wiped
\  after every admitted parse result, callback return, or caught THROW.
\
\  Recognized members:
\
\    access_token  required, nonempty RFC 6749 VSCHAR string
\    token_type    required, nonempty RFC 6749 type-name or URI-reference
\    refresh_token optional, nonempty RFC 6749 VSCHAR string
\    scope         optional, nonempty RFC 6749 scope string
\    expires_in    optional, bounded nonnegative integral number
\
\  Unknown members pass complete strict JSON validation and are ignored.
\  This module owns no HTTP, discovery, clock, token installation, OIDC,
\  AT Protocol, session, persistence, or application policy.
\
\  Public API:
\
\    OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE
\    OAUTH2-TOKEN-RESPONSE-WITH
\    OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
\    OAUTH2-TOKEN-VIEW-TOKEN-TYPE@
\    OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@
\    OAUTH2-TOKEN-VIEW-SCOPE@
\    OAUTH2-TOKEN-VIEW-EXPIRES-IN@
\ =====================================================================

PROVIDED akashic-oauth2-tokenrsp

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../jose/json-object.f

\ =====================================================================
\  Public status and capacity vocabulary
\ =====================================================================

0  CONSTANT OAUTH2-TOKEN-RESPONSE-S-OK
1  CONSTANT OAUTH2-TOKEN-RESPONSE-S-INVALID
2  CONSTANT OAUTH2-TOKEN-RESPONSE-S-CAPACITY
3  CONSTANT OAUTH2-TOKEN-RESPONSE-S-ALIAS
4  CONSTANT OAUTH2-TOKEN-RESPONSE-S-JSON
5  CONSTANT OAUTH2-TOKEN-RESPONSE-S-MISSING
6  CONSTANT OAUTH2-TOKEN-RESPONSE-S-TYPE
7  CONSTANT OAUTH2-TOKEN-RESPONSE-S-VALUE
8  CONSTANT OAUTH2-TOKEN-RESPONSE-S-DUPLICATE
9  CONSTANT OAUTH2-TOKEN-RESPONSE-S-CALLBACK
10 CONSTANT OAUTH2-TOKEN-RESPONSE-S-INTERNAL
11 CONSTANT OAUTH2-TOKEN-RESPONSE-S-RANGE
12 CONSTANT OAUTH2-TOKEN-RESPONSE-S-PROTECTED
13 CONSTANT OAUTH2-TOKEN-RESPONSE-S-PLATFORM

: OAUTH2-TOKEN-RESPONSE-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-TOKEN-RESPONSE-S-OK >=
    SWAP OAUTH2-TOKEN-RESPONSE-S-PLATFORM <= AND ;

8192 CONSTANT OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY
4096 CONSTANT OAUTH2-TOKEN-VIEW-TOKEN-TYPE-CAPACITY
4096 CONSTANT OAUTH2-TOKEN-VIEW-REFRESH-CAPACITY
4096 CONSTANT OAUTH2-TOKEN-VIEW-SCOPE-CAPACITY

2147483647 CONSTANT OAUTH2-TOKEN-VIEW-MAX-EXPIRES-IN
OAUTH2-TOKEN-VIEW-MAX-EXPIRES-IN 10 /
    CONSTANT _O2TR-EXPIRES-QUOTIENT
OAUTH2-TOKEN-VIEW-MAX-EXPIRES-IN 10 MOD
    CONSTANT _O2TR-EXPIRES-REMAINDER

1  CONSTANT _O2TR-P-ACCESS-TOKEN
2  CONSTANT _O2TR-P-TOKEN-TYPE
4  CONSTANT _O2TR-P-REFRESH-TOKEN
8  CONSTANT _O2TR-P-SCOPE
16 CONSTANT _O2TR-P-EXPIRES-IN

_O2TR-P-ACCESS-TOKEN _O2TR-P-TOKEN-TYPE OR
    CONSTANT _O2TR-REQUIRED-PRESENCE

\ =====================================================================
\  Ephemeral callback view
\ =====================================================================

0x4F32545256494557 CONSTANT _O2TR-VIEW-MAGIC-VALUE

 0 CONSTANT _O2TRV-MAGIC
 8 CONSTANT _O2TRV-ACCESS-U
16 CONSTANT _O2TRV-TYPE-U
24 CONSTANT _O2TRV-REFRESH-U
32 CONSTANT _O2TRV-SCOPE-U
40 CONSTANT _O2TRV-EXPIRES-IN
48 CONSTANT _O2TRV-HEADER-SIZE

_O2TRV-HEADER-SIZE CONSTANT _O2TRV-ACCESS-OFF
_O2TRV-ACCESS-OFF OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY +
    CONSTANT _O2TRV-TYPE-OFF
_O2TRV-TYPE-OFF OAUTH2-TOKEN-VIEW-TOKEN-TYPE-CAPACITY +
    CONSTANT _O2TRV-REFRESH-OFF
_O2TRV-REFRESH-OFF OAUTH2-TOKEN-VIEW-REFRESH-CAPACITY +
    CONSTANT _O2TRV-SCOPE-OFF
_O2TRV-SCOPE-OFF OAUTH2-TOKEN-VIEW-SCOPE-CAPACITY +
    CONSTANT _O2TR-VIEW-SIZE

: _O2TRV.MAGIC       ( view -- address ) _O2TRV-MAGIC + ;
: _O2TRV.ACCESS-U    ( view -- address ) _O2TRV-ACCESS-U + ;
: _O2TRV.TYPE-U      ( view -- address ) _O2TRV-TYPE-U + ;
: _O2TRV.REFRESH-U   ( view -- address ) _O2TRV-REFRESH-U + ;
: _O2TRV.SCOPE-U     ( view -- address ) _O2TRV-SCOPE-U + ;
: _O2TRV.EXPIRES-IN  ( view -- address ) _O2TRV-EXPIRES-IN + ;

: _O2TRV.ACCESS   ( view -- address ) _O2TRV-ACCESS-OFF + ;
: _O2TRV.TYPE     ( view -- address ) _O2TRV-TYPE-OFF + ;
: _O2TRV.REFRESH  ( view -- address ) _O2TRV-REFRESH-OFF + ;
: _O2TRV.SCOPE    ( view -- address ) _O2TRV-SCOPE-OFF + ;

\ =====================================================================
\  Caller admission and view access
\ =====================================================================

: _O2TR-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-PLATFORM EXIT
    THEN
    DROP OAUTH2-TOKEN-RESPONSE-S-PLATFORM ;

: _O2TR-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _O2TR-CALLER>STATUS ;

: _O2TR-REQUIRED-LENGTH?  ( length capacity -- flag )
    OVER 0> IF
        U> 0=
    ELSE
        2DROP 0
    THEN ;

: _O2TR-OPTIONAL-LENGTH?  ( length capacity -- flag )
    OVER 0< IF
        2DROP 0 EXIT
    THEN
    U> 0= ;

: _O2TR-VIEW-VALID?  ( view -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP _O2TR-VIEW-SIZE _O2TR-ADMIT-SPAN
        OAUTH2-TOKEN-RESPONSE-S-OK <> IF
        DROP 0 EXIT
    THEN
    DUP _O2TRV.MAGIC @ _O2TR-VIEW-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP _O2TRV.ACCESS-U @
        OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY
        _O2TR-REQUIRED-LENGTH? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2TRV.TYPE-U @
        OAUTH2-TOKEN-VIEW-TOKEN-TYPE-CAPACITY
        _O2TR-REQUIRED-LENGTH? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2TRV.REFRESH-U @
        OAUTH2-TOKEN-VIEW-REFRESH-CAPACITY
        _O2TR-OPTIONAL-LENGTH? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2TRV.SCOPE-U @
        OAUTH2-TOKEN-VIEW-SCOPE-CAPACITY
        _O2TR-OPTIONAL-LENGTH? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2TRV.EXPIRES-IN @
    DUP -1 = IF
        2DROP -1 EXIT
    THEN
    DUP 0< IF
        2DROP 0 EXIT
    THEN
    OAUTH2-TOKEN-VIEW-MAX-EXPIRES-IN U> 0=
    SWAP DROP ;

: _O2TR-VIEW-TEXT@  ( view length-offset data-offset -- address length )
    >R
    OVER SWAP + @
    SWAP R> + SWAP ;

: OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
  ( view -- address length status )
    DUP _O2TR-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-TOKEN-RESPONSE-S-INVALID EXIT
    THEN
    _O2TRV-ACCESS-U _O2TRV-ACCESS-OFF _O2TR-VIEW-TEXT@
    OAUTH2-TOKEN-RESPONSE-S-OK ;

: OAUTH2-TOKEN-VIEW-TOKEN-TYPE@
  ( view -- address length status )
    DUP _O2TR-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-TOKEN-RESPONSE-S-INVALID EXIT
    THEN
    _O2TRV-TYPE-U _O2TRV-TYPE-OFF _O2TR-VIEW-TEXT@
    OAUTH2-TOKEN-RESPONSE-S-OK ;

: OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@
  ( view -- address length status )
    DUP _O2TR-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-TOKEN-RESPONSE-S-INVALID EXIT
    THEN
    DUP _O2TRV.REFRESH-U @ 0= IF
        DROP 0 0 OAUTH2-TOKEN-RESPONSE-S-MISSING EXIT
    THEN
    _O2TRV-REFRESH-U _O2TRV-REFRESH-OFF _O2TR-VIEW-TEXT@
    OAUTH2-TOKEN-RESPONSE-S-OK ;

: OAUTH2-TOKEN-VIEW-SCOPE@
  ( view -- address length status )
    DUP _O2TR-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-TOKEN-RESPONSE-S-INVALID EXIT
    THEN
    DUP _O2TRV.SCOPE-U @ 0= IF
        DROP 0 0 OAUTH2-TOKEN-RESPONSE-S-MISSING EXIT
    THEN
    _O2TRV-SCOPE-U _O2TRV-SCOPE-OFF _O2TR-VIEW-TEXT@
    OAUTH2-TOKEN-RESPONSE-S-OK ;

: OAUTH2-TOKEN-VIEW-EXPIRES-IN@
  ( view -- seconds status )
    DUP _O2TR-VIEW-VALID? 0= IF
        DROP 0 OAUTH2-TOKEN-RESPONSE-S-INVALID EXIT
    THEN
    DUP _O2TRV.EXPIRES-IN @ -1 = IF
        DROP 0 OAUTH2-TOKEN-RESPONSE-S-MISSING EXIT
    THEN
    _O2TRV.EXPIRES-IN @ OAUTH2-TOKEN-RESPONSE-S-OK ;

\ =====================================================================
\  Caller-owned operation workspace
\ =====================================================================

16 CONSTANT _O2TR-MAX-MEMBERS
1024 CONSTANT _O2TR-NAMES-SIZE

_O2TR-MAX-MEMBERS JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." OAuth 2 token response descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _O2TR-DESCRIPTOR-SIZE

 0 CONSTANT _O2TRW-SOURCE
 8 CONSTANT _O2TRW-SOURCE-U
16 CONSTANT _O2TRW-CALLBACK
24 CONSTANT _O2TRW-CONTEXT
32 CONSTANT _O2TRW-NAME-A
40 CONSTANT _O2TRW-NAME-U
48 CONSTANT _O2TRW-VALUE-A
56 CONSTANT _O2TRW-VALUE-U
64 CONSTANT _O2TRW-VALUE-TYPE
72 CONSTANT _O2TRW-PRESENT
80 CONSTANT _O2TRW-SCAN
88 CONSTANT _O2TRW-ACCUMULATOR
96 CONSTANT _O2TRW-HEADER-SIZE

_O2TRW-HEADER-SIZE CONSTANT _O2TRW-DESCRIPTOR-OFF
_O2TRW-DESCRIPTOR-OFF _O2TR-DESCRIPTOR-SIZE +
    CONSTANT _O2TRW-NAMES-OFF
_O2TRW-NAMES-OFF _O2TR-NAMES-SIZE +
    CONSTANT _O2TRW-JSON-OFF
_O2TRW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
    CONSTANT _O2TRW-VIEW-OFF
_O2TRW-VIEW-OFF _O2TR-VIEW-SIZE +
    CONSTANT OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE

: _O2TRW.SOURCE       ( workspace -- address ) _O2TRW-SOURCE + ;
: _O2TRW.SOURCE-U     ( workspace -- address ) _O2TRW-SOURCE-U + ;
: _O2TRW.CALLBACK     ( workspace -- address ) _O2TRW-CALLBACK + ;
: _O2TRW.CONTEXT      ( workspace -- address ) _O2TRW-CONTEXT + ;
: _O2TRW.NAME-A       ( workspace -- address ) _O2TRW-NAME-A + ;
: _O2TRW.NAME-U       ( workspace -- address ) _O2TRW-NAME-U + ;
: _O2TRW.VALUE-A      ( workspace -- address ) _O2TRW-VALUE-A + ;
: _O2TRW.VALUE-U      ( workspace -- address ) _O2TRW-VALUE-U + ;
: _O2TRW.VALUE-TYPE   ( workspace -- address ) _O2TRW-VALUE-TYPE + ;
: _O2TRW.PRESENT      ( workspace -- address ) _O2TRW-PRESENT + ;
: _O2TRW.SCAN         ( workspace -- address ) _O2TRW-SCAN + ;
: _O2TRW.ACCUMULATOR  ( workspace -- address ) _O2TRW-ACCUMULATOR + ;

: _O2TRW.DESCRIPTOR  ( workspace -- address ) _O2TRW-DESCRIPTOR-OFF + ;
: _O2TRW.NAMES       ( workspace -- address ) _O2TRW-NAMES-OFF + ;
: _O2TRW.JSON        ( workspace -- address ) _O2TRW-JSON-OFF + ;
: _O2TRW.VIEW        ( workspace -- address ) _O2TRW-VIEW-OFF + ;

: _O2TR-WIPE  ( workspace -- )
    OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Geometry and stack helpers
\ =====================================================================

: _O2TR-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _O2TR-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;
: _O2TR-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;

: _O2TR-RETURN5  ( x1 x2 x3 x4 x5 status -- status )
    >R _O2TR-DROP5 R> ;

: _O2TR-WITH-GEOMETRY
  ( source source-u callback context workspace -- status )
    DUP OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE _O2TR-ADMIT-SPAN
        ?DUP IF
        _O2TR-RETURN5 EXIT
    THEN
    4 PICK 4 PICK _O2TR-ADMIT-SPAN ?DUP IF
        _O2TR-RETURN5 EXIT
    THEN
    2 PICK 0= IF
        OAUTH2-TOKEN-RESPONSE-S-INVALID _O2TR-RETURN5 EXIT
    THEN
    3 PICK 0= IF
        OAUTH2-TOKEN-RESPONSE-S-INVALID _O2TR-RETURN5 EXIT
    THEN
    3 PICK JOSE-JSON-MAX-DOCUMENT-BYTES U> IF
        OAUTH2-TOKEN-RESPONSE-S-CAPACITY _O2TR-RETURN5 EXIT
    THEN
    4 PICK 4 PICK 2 PICK OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-TOKEN-RESPONSE-S-ALIAS _O2TR-RETURN5 EXIT
    THEN
    OAUTH2-TOKEN-RESPONSE-S-OK _O2TR-RETURN5 ;

\ =====================================================================
\  Strict field decoding and policy
\ =====================================================================

: _O2TR-JSON>STATUS  ( json-status -- status )
    DUP JOSE-JSON-S-OK = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-OK EXIT
    THEN
    DUP JOSE-JSON-S-DUPLICATE = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-DUPLICATE EXIT
    THEN
    DUP JOSE-JSON-S-CAPACITY = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-MEMBERS = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-STRING = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-DOCUMENT = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-SYNTAX = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-JSON EXIT
    THEN
    DUP JOSE-JSON-S-UTF8 = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-JSON EXIT
    THEN
    DUP JOSE-JSON-S-DEPTH = IF
        DROP OAUTH2-TOKEN-RESPONSE-S-JSON EXIT
    THEN
    DROP OAUTH2-TOKEN-RESPONSE-S-INTERNAL ;

: _O2TR-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _O2TRW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP OAUTH2-TOKEN-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2TRW.VALUE-TYPE !
    R@ _O2TRW.VALUE-U !
    R@ _O2TRW.SOURCE @ + R@ _O2TRW.VALUE-A !
    R@ _O2TRW.NAME-U !
    R@ _O2TRW.NAMES + R@ _O2TRW.NAME-A !
    R> DROP OAUTH2-TOKEN-RESPONSE-S-OK ;

: _O2TR-NAME=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _O2TRW.NAME-A @ R@ _O2TRW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _O2TR-COPY-MEMBER-STRING
  ( destination length-cell capacity workspace -- status )
    >R
    R@ _O2TRW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        _O2TR-DROP3 R> DROP OAUTH2-TOKEN-RESPONSE-S-TYPE EXIT
    THEN
    R@ _O2TRW.SCAN !
    R@ _O2TRW.NAME-U !
    R@ _O2TRW.NAME-A !

    R@ _O2TRW.VALUE-A @ R@ _O2TRW.VALUE-U @
    R@ _O2TRW.NAME-A @ R@ _O2TRW.SCAN @
    R@ _O2TRW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        DUP JOSE-JSON-S-CAPACITY =
        OVER JOSE-JSON-S-STRING = OR IF
            2DROP R> DROP
            OAUTH2-TOKEN-RESPONSE-S-CAPACITY EXIT
        THEN
        2DROP R> DROP OAUTH2-TOKEN-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    DUP 0= IF
        DROP R> DROP OAUTH2-TOKEN-RESPONSE-S-VALUE EXIT
    THEN
    R@ _O2TRW.NAME-U @ !
    R> DROP OAUTH2-TOKEN-RESPONSE-S-OK ;

: _O2TR-MARK-PRESENT  ( mask workspace -- status )
    >R
    DUP R@ _O2TRW.PRESENT @ AND IF
        DROP R> DROP OAUTH2-TOKEN-RESPONSE-S-DUPLICATE EXIT
    THEN
    R@ _O2TRW.PRESENT @ OR R@ _O2TRW.PRESENT !
    R> DROP OAUTH2-TOKEN-RESPONSE-S-OK ;

: _O2TR-VSCHAR?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ 32 127 WITHIN 0= IF
            2DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _O2TR-DIGIT?  ( byte -- flag )
    48 58 WITHIN ;

: _O2TR-ALPHA?  ( byte -- flag )
    DUP 65 91 WITHIN
    SWAP 97 123 WITHIN OR ;

: _O2TR-HEXDIGIT?  ( byte -- flag )
    DUP _O2TR-DIGIT? IF DROP -1 EXIT THEN
    DUP 65 71 WITHIN
    SWAP 97 103 WITHIN OR ;

: _O2TR-NAME-CHAR?  ( byte -- flag )
    DUP _O2TR-ALPHA? IF DROP -1 EXIT THEN
    DUP _O2TR-DIGIT? IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    95 = ;

: _O2TR-UNRESERVED?  ( byte -- flag )
    DUP _O2TR-ALPHA? IF DROP -1 EXIT THEN
    DUP _O2TR-DIGIT? IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    DUP 95 = IF DROP -1 EXIT THEN
    126 = ;

: _O2TR-SUBDELIM?  ( byte -- flag )
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

: _O2TR-SCHEME-CHAR?  ( byte -- flag )
    DUP _O2TR-ALPHA? IF DROP -1 EXIT THEN
    DUP _O2TR-DIGIT? IF DROP -1 EXIT THEN
    DUP 43 = IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    46 = ;

: _O2TR-REGNAME-CHAR?  ( byte -- flag )
    DUP _O2TR-UNRESERVED? IF DROP -1 EXIT THEN
    _O2TR-SUBDELIM? ;

: _O2TR-USERINFO-CHAR?  ( byte -- flag )
    DUP _O2TR-REGNAME-CHAR? IF DROP -1 EXIT THEN
    58 = ;

: _O2TR-PCHAR?  ( byte -- flag )
    DUP _O2TR-REGNAME-CHAR? IF DROP -1 EXIT THEN
    DUP 58 = IF DROP -1 EXIT THEN
    64 = ;

: _O2TR-PCHAR-NC?  ( byte -- flag )
    DUP _O2TR-REGNAME-CHAR? IF DROP -1 EXIT THEN
    64 = ;

: _O2TR-PATH-CHAR?  ( byte -- flag )
    DUP _O2TR-PCHAR? IF DROP -1 EXIT THEN
    47 = ;

: _O2TR-QUERY-FRAGMENT-CHAR?  ( byte -- flag )
    DUP _O2TR-PCHAR? IF DROP -1 EXIT THEN
    DUP 47 = IF DROP -1 EXIT THEN
    63 = ;

: _O2TR-IPVFUTURE-CHAR?  ( byte -- flag )
    _O2TR-USERINFO-CHAR? ;

: _O2TR-RAW-SEQUENCE?  ( address length predicate -- flag )
    >R
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ R@ EXECUTE 0= IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _O2TR-PCT-TRIPLET?  ( address length -- flag )
    DUP 3 U< IF 2DROP 0 EXIT THEN
    OVER C@ 37 <> IF 2DROP 0 EXIT THEN
    OVER 1+ C@ _O2TR-HEXDIGIT? 0= IF 2DROP 0 EXIT THEN
    OVER 2 + C@ _O2TR-HEXDIGIT?
    >R 2DROP R> ;

\ Validate one RFC 3986 component without decoding pct-encoded octets.
\ The supplied predicate covers every admitted raw byte except "%".
: _O2TR-URI-SEQUENCE?  ( address length predicate -- flag )
    >R
    DUP 0< IF 2DROP R> DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ 37 = IF
            2DUP _O2TR-PCT-TRIPLET? 0= IF
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

: _O2TR-TYPE-NAME?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    ['] _O2TR-NAME-CHAR? _O2TR-RAW-SEQUENCE? ;

: _O2TR-SCHEME?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ _O2TR-ALPHA? 0= IF 2DROP 0 EXIT THEN
    1- SWAP 1+ SWAP
    ['] _O2TR-SCHEME-CHAR? _O2TR-RAW-SEQUENCE? ;

: _O2TR-REGNAME?  ( address length -- flag )
    ['] _O2TR-REGNAME-CHAR? _O2TR-URI-SEQUENCE? ;

: _O2TR-USERINFO?  ( address length -- flag )
    ['] _O2TR-USERINFO-CHAR? _O2TR-URI-SEQUENCE? ;

: _O2TR-PCHAR-SEQUENCE?  ( address length -- flag )
    ['] _O2TR-PCHAR? _O2TR-URI-SEQUENCE? ;

: _O2TR-PCHAR-NC-SEQUENCE?  ( address length -- flag )
    ['] _O2TR-PCHAR-NC? _O2TR-URI-SEQUENCE? ;

: _O2TR-PATH-SEQUENCE?  ( address length -- flag )
    ['] _O2TR-PATH-CHAR? _O2TR-URI-SEQUENCE? ;

: _O2TR-QUERY-FRAGMENT?  ( address length -- flag )
    ['] _O2TR-QUERY-FRAGMENT-CHAR? _O2TR-URI-SEQUENCE? ;

: _O2TR-FIND-BYTE  ( address length byte -- index|-1 )
    >R
    DUP 0< IF 2DROP R> DROP -1 EXIT THEN
    0
    BEGIN DUP 2 PICK U< WHILE
        2 PICK OVER + C@ R@ = IF
            >R 2DROP R> R> DROP EXIT
        THEN
        1+
    REPEAT
    _O2TR-DROP3 R> DROP -1 ;

: _O2TR-FIND-DOUBLE-COLON  ( address length -- index|-1 )
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
    _O2TR-DROP3 -1 ;

: _O2TR-DIGITS?  ( address length -- flag )
    ['] _O2TR-DIGIT? _O2TR-RAW-SEQUENCE? ;

: _O2TR-H16?  ( address length -- flag )
    DUP 1 U< OVER 4 U> OR IF 2DROP 0 EXIT THEN
    ['] _O2TR-HEXDIGIT? _O2TR-RAW-SEQUENCE? ;

: _O2TR-DEC-OCTET?  ( address length -- flag )
    DUP 1 U< OVER 3 U> OR IF 2DROP 0 EXIT THEN
    DUP 1 > IF
        OVER C@ 48 = IF 2DROP 0 EXIT THEN
    THEN
    0 >R
    BEGIN DUP WHILE
        OVER C@ DUP _O2TR-DIGIT? 0= IF
            DROP 2DROP R> DROP 0 EXIT
        THEN
        48 -
        R> 10 * + >R
        1- SWAP 1+ SWAP
    REPEAT
    2DROP
    R> 255 U> 0= ;

: _O2TR-IPV4-CUT  ( address length -- next-address next-length flag )
    2DUP 46 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP 2DROP 0 0 0 EXIT
    THEN
    >R
    OVER R@ _O2TR-DEC-OCTET? 0= IF
        2DROP R> DROP 0 0 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP -1 ;

: _O2TR-IPV4?  ( address length -- flag )
    _O2TR-IPV4-CUT 0= IF 2DROP 0 EXIT THEN
    _O2TR-IPV4-CUT 0= IF 2DROP 0 EXIT THEN
    _O2TR-IPV4-CUT 0= IF 2DROP 0 EXIT THEN
    _O2TR-DEC-OCTET? ;

\ Return the number of 16-bit units in one colon-separated IPv6 side.
\ Embedded IPv4 is admitted only as the final token when allow-ipv4 is true.
: _O2TR-IPV6-SIDE  ( address length allow-ipv4 -- units|-1 )
    >R
    DUP 0= IF 2DROP R> DROP 0 EXIT THEN
    0 >R
    BEGIN
        2DUP 58 _O2TR-FIND-BYTE
        DUP -1 = IF
            DROP
            2DUP 46 _O2TR-FIND-BYTE -1 <> IF
                R> R> 0= IF
                    _O2TR-DROP3 -1 EXIT
                THEN
                >R
                _O2TR-IPV4? 0= IF
                    R> DROP -1 EXIT
                THEN
                R> 2 + EXIT
            THEN
            _O2TR-H16? 0= IF
                R> DROP R> DROP -1 EXIT
            THEN
            R> 1+ R> DROP EXIT
        THEN
        >R
        OVER R@ _O2TR-H16? 0= IF
            2DROP
            R> DROP R> DROP R> DROP
            -1 EXIT
        THEN
        SWAP R@ + 1+ SWAP R@ - 1-
        R> DROP
        R> 1+ >R
    AGAIN ;

: _O2TR-IPV6?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    2DUP _O2TR-FIND-DOUBLE-COLON
    DUP -1 = IF
        DROP -1 _O2TR-IPV6-SIDE 8 = EXIT
    THEN
    >R
    OVER R@ 0 _O2TR-IPV6-SIDE
    DUP 0< IF
        _O2TR-DROP3 R> DROP 0 EXIT
    THEN
    2 PICK R@ + 2 +
    2 PICK R@ - 2 -
    -1 _O2TR-IPV6-SIDE
    DUP 0< IF
        _O2TR-DROP4 R> DROP 0 EXIT
    THEN
    + 8 U<
    >R 2DROP R> R> DROP ;

: _O2TR-IPVFUTURE?  ( address length -- flag )
    DUP 4 U< IF 2DROP 0 EXIT THEN
    OVER C@ DUP 118 = SWAP 86 = OR 0= IF
        2DROP 0 EXIT
    THEN
    1- SWAP 1+ SWAP
    2DUP 46 _O2TR-FIND-BYTE
    DUP 1 < IF
        DROP 2DROP 0 EXIT
    THEN
    >R
    OVER R@ ['] _O2TR-HEXDIGIT?
        _O2TR-RAW-SEQUENCE? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    DUP 0= IF 2DROP 0 EXIT THEN
    ['] _O2TR-IPVFUTURE-CHAR? _O2TR-RAW-SEQUENCE? ;

: _O2TR-IP-LITERAL?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ DUP 118 = SWAP 86 = OR IF
        _O2TR-IPVFUTURE? EXIT
    THEN
    _O2TR-IPV6? ;

: _O2TR-BRACKETED-HOSTPORT?  ( address length -- flag )
    DUP 2 U< IF 2DROP 0 EXIT THEN
    2DUP 93 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP 2DROP 0 EXIT
    THEN
    >R
    OVER 1+ R@ 1- _O2TR-IP-LITERAL? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 58 <> IF 2DROP 0 EXIT THEN
    1- SWAP 1+ SWAP
    _O2TR-DIGITS? ;

: _O2TR-HOSTPORT?  ( address length -- flag )
    DUP IF
        OVER C@ 91 = IF
            _O2TR-BRACKETED-HOSTPORT? EXIT
        THEN
    THEN
    2DUP 58 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP _O2TR-REGNAME? EXIT
    THEN
    >R
    OVER R@ _O2TR-REGNAME? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    _O2TR-DIGITS? ;

: _O2TR-AUTHORITY?  ( address length -- flag )
    2DUP 64 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP _O2TR-HOSTPORT? EXIT
    THEN
    >R
    OVER R@ _O2TR-USERINFO? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    _O2TR-HOSTPORT? ;

: _O2TR-PATH-ABEMPTY?  ( address length -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 47 <> IF 2DROP 0 EXIT THEN
    _O2TR-PATH-SEQUENCE? ;

: _O2TR-PATH-ABSOLUTE?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 47 <> IF 2DROP 0 EXIT THEN
    DUP 1 = IF 2DROP -1 EXIT THEN
    OVER 1+ C@ 47 = IF 2DROP 0 EXIT THEN
    _O2TR-PATH-SEQUENCE? ;

: _O2TR-PATH-ROOTLESS?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 47 = IF 2DROP 0 EXIT THEN
    _O2TR-PATH-SEQUENCE? ;

: _O2TR-PATH-NOSCHEME?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    OVER C@ 47 = IF 2DROP 0 EXIT THEN
    2DUP 47 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP _O2TR-PCHAR-NC-SEQUENCE? EXIT
    THEN
    >R
    OVER R@ _O2TR-PCHAR-NC-SEQUENCE? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + SWAP R@ -
    R> DROP
    _O2TR-PATH-SEQUENCE? ;

: _O2TR-DOUBLE-SLASH?  ( address length -- flag )
    DUP 2 U< IF 2DROP 0 EXIT THEN
    OVER C@ 47 =
    2 PICK 1+ C@ 47 = AND
    >R 2DROP R> ;

: _O2TR-NETWORK-PART?  ( address length -- flag )
    2 - SWAP 2 + SWAP
    2DUP 47 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP _O2TR-AUTHORITY? EXIT
    THEN
    >R
    OVER R@ _O2TR-AUTHORITY? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + SWAP R@ -
    R> DROP
    _O2TR-PATH-ABEMPTY? ;

: _O2TR-HIER-PART?  ( address length -- flag )
    2DUP _O2TR-DOUBLE-SLASH? IF
        _O2TR-NETWORK-PART? EXIT
    THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 47 = IF
        _O2TR-PATH-ABSOLUTE? EXIT
    THEN
    _O2TR-PATH-ROOTLESS? ;

: _O2TR-RELATIVE-PART?  ( address length -- flag )
    2DUP _O2TR-DOUBLE-SLASH? IF
        _O2TR-NETWORK-PART? EXIT
    THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ 47 = IF
        _O2TR-PATH-ABSOLUTE? EXIT
    THEN
    _O2TR-PATH-NOSCHEME? ;

: _O2TR-URI-WITH-SCHEME?  ( address length colon-index -- flag )
    >R
    OVER R@ _O2TR-SCHEME? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    SWAP R@ + 1+ SWAP R@ - 1-
    R> DROP
    _O2TR-HIER-PART? ;

: _O2TR-URI-CORE?  ( address length -- flag )
    2DUP 58 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP _O2TR-RELATIVE-PART? EXIT
    THEN
    >R
    2DUP 47 _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP R> _O2TR-URI-WITH-SCHEME? EXIT
    THEN
    R@ SWAP U< IF
        R> _O2TR-URI-WITH-SCHEME? EXIT
    THEN
    R> DROP
    _O2TR-RELATIVE-PART? ;

\ Cut the first query/fragment delimiter and validate the suffix.  On
\ success the original address and the prefix length remain for the caller.
: _O2TR-CUT-QUERY-FRAGMENT
  ( address length delimiter -- address prefix-length flag )
    >R
    2DUP R@ _O2TR-FIND-BYTE
    DUP -1 = IF
        DROP R> DROP -1 EXIT
    THEN
    >R
    OVER R@ + 1+
    1 PICK R@ - 1-
    _O2TR-QUERY-FRAGMENT? 0= IF
        2DROP R> DROP R> DROP 0 0 0 EXIT
    THEN
    DROP R> R> DROP -1 ;

: _O2TR-URI-REFERENCE?  ( address length -- flag )
    35 _O2TR-CUT-QUERY-FRAGMENT 0= IF
        2DROP 0 EXIT
    THEN
    63 _O2TR-CUT-QUERY-FRAGMENT 0= IF
        2DROP 0 EXIT
    THEN
    _O2TR-URI-CORE? ;

: _O2TR-TOKEN-TYPE?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    2DUP _O2TR-TYPE-NAME? IF 2DROP -1 EXIT THEN
    _O2TR-URI-REFERENCE? ;

: _O2TR-SCOPE-CHAR?  ( byte -- flag )
    DUP 0x21 = IF DROP -1 EXIT THEN
    DUP 0x23 0x5C WITHIN IF DROP -1 EXIT THEN
    0x5D 0x7F WITHIN ;

: _O2TR-SCOPE?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    -1 >R
    BEGIN DUP WHILE
        OVER C@
        DUP 32 = IF
            DROP
            R@ IF
                2DROP R> DROP 0 EXIT
            THEN
            -1 R> DROP >R
        ELSE
            _O2TR-SCOPE-CHAR? 0= IF
                2DROP R> DROP 0 EXIT
            THEN
            0 R> DROP >R
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP
    R> 0= ;

: _O2TR-EXPIRES-ACCUMULATE
  ( accumulator digit -- accumulator-next valid? )
    >R
    DUP _O2TR-EXPIRES-QUOTIENT U> IF
        DROP R> DROP 0 0 EXIT
    THEN
    DUP _O2TR-EXPIRES-QUOTIENT = IF
        R@ _O2TR-EXPIRES-REMAINDER U> IF
            DROP R> DROP 0 0 EXIT
        THEN
    THEN
    10 * R> + -1 ;

: _O2TR-PARSE-EXPIRES  ( workspace -- status )
    DUP _O2TRW.VALUE-TYPE @ JOSE-JSON-T-NUMBER <> IF
        DROP OAUTH2-TOKEN-RESPONSE-S-TYPE EXIT
    THEN
    DUP _O2TRW.VALUE-U @ 0= IF
        DROP OAUTH2-TOKEN-RESPONSE-S-INTERNAL EXIT
    THEN
    0 OVER _O2TRW.SCAN !
    0 OVER _O2TRW.ACCUMULATOR !
    BEGIN
        DUP _O2TRW.SCAN @
        OVER _O2TRW.VALUE-U @ U<
    WHILE
        DUP _O2TRW.VALUE-A @
        OVER _O2TRW.SCAN @ + C@
        DUP _O2TR-DIGIT? 0= IF
            2DROP OAUTH2-TOKEN-RESPONSE-S-VALUE EXIT
        THEN
        48 -
        OVER _O2TRW.ACCUMULATOR @ SWAP
        _O2TR-EXPIRES-ACCUMULATE 0= IF
            2DROP OAUTH2-TOKEN-RESPONSE-S-VALUE EXIT
        THEN
        OVER _O2TRW.ACCUMULATOR !
        1 OVER _O2TRW.SCAN +!
    REPEAT
    DUP _O2TRW.ACCUMULATOR @
    OVER _O2TRW.VIEW _O2TRV.EXPIRES-IN !
    DROP OAUTH2-TOKEN-RESPONSE-S-OK ;

: _O2TR-PROCESS-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _O2TR-MEMBER-LOAD
    DUP IF NIP R> DROP EXIT THEN
    2DROP

    S" access_token" R@ _O2TR-NAME= IF
        R@ _O2TRW.VIEW _O2TRV.ACCESS
        R@ _O2TRW.VIEW _O2TRV.ACCESS-U
        OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY
        R@ _O2TR-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2TRW.VIEW _O2TRV.ACCESS
        R@ _O2TRW.VIEW _O2TRV.ACCESS-U @
        _O2TR-VSCHAR? 0= IF
            R> DROP OAUTH2-TOKEN-RESPONSE-S-VALUE EXIT
        THEN
        _O2TR-P-ACCESS-TOKEN
        R@ _O2TR-MARK-PRESENT R> DROP EXIT
    THEN

    S" token_type" R@ _O2TR-NAME= IF
        R@ _O2TRW.VIEW _O2TRV.TYPE
        R@ _O2TRW.VIEW _O2TRV.TYPE-U
        OAUTH2-TOKEN-VIEW-TOKEN-TYPE-CAPACITY
        R@ _O2TR-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2TRW.VIEW _O2TRV.TYPE
        R@ _O2TRW.VIEW _O2TRV.TYPE-U @
        _O2TR-TOKEN-TYPE? 0= IF
            R> DROP OAUTH2-TOKEN-RESPONSE-S-VALUE EXIT
        THEN
        _O2TR-P-TOKEN-TYPE
        R@ _O2TR-MARK-PRESENT R> DROP EXIT
    THEN

    S" refresh_token" R@ _O2TR-NAME= IF
        R@ _O2TRW.VIEW _O2TRV.REFRESH
        R@ _O2TRW.VIEW _O2TRV.REFRESH-U
        OAUTH2-TOKEN-VIEW-REFRESH-CAPACITY
        R@ _O2TR-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2TRW.VIEW _O2TRV.REFRESH
        R@ _O2TRW.VIEW _O2TRV.REFRESH-U @
        _O2TR-VSCHAR? 0= IF
            R> DROP OAUTH2-TOKEN-RESPONSE-S-VALUE EXIT
        THEN
        _O2TR-P-REFRESH-TOKEN
        R@ _O2TR-MARK-PRESENT R> DROP EXIT
    THEN

    S" scope" R@ _O2TR-NAME= IF
        R@ _O2TRW.VIEW _O2TRV.SCOPE
        R@ _O2TRW.VIEW _O2TRV.SCOPE-U
        OAUTH2-TOKEN-VIEW-SCOPE-CAPACITY
        R@ _O2TR-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2TRW.VIEW _O2TRV.SCOPE
        R@ _O2TRW.VIEW _O2TRV.SCOPE-U @
        _O2TR-SCOPE? 0= IF
            R> DROP OAUTH2-TOKEN-RESPONSE-S-VALUE EXIT
        THEN
        _O2TR-P-SCOPE
        R@ _O2TR-MARK-PRESENT R> DROP EXIT
    THEN

    S" expires_in" R@ _O2TR-NAME= IF
        R@ _O2TR-PARSE-EXPIRES
        DUP IF R> DROP EXIT THEN DROP
        _O2TR-P-EXPIRES-IN
        R@ _O2TR-MARK-PRESENT R> DROP EXIT
    THEN

    R> DROP OAUTH2-TOKEN-RESPONSE-S-OK ;

: _O2TR-PROCESS-ALL  ( count workspace -- status )
    SWAP 0 SWAP
    BEGIN 2DUP U< WHILE
        2 PICK 2 PICK SWAP _O2TR-PROCESS-MEMBER
        DUP IF
            >R _O2TR-DROP3 R> EXIT
        THEN
        DROP
        SWAP 1+ SWAP
    REPEAT
    _O2TR-DROP3 OAUTH2-TOKEN-RESPONSE-S-OK ;

: _O2TR-PARSE-STAGE  ( workspace -- status )
    >R
    R@ _O2TRW.SOURCE @ R@ _O2TRW.SOURCE-U @
    R@ _O2TRW.DESCRIPTOR _O2TR-MAX-MEMBERS
    R@ _O2TRW.NAMES _O2TR-NAMES-SIZE
    R@ _O2TRW.JSON
    JOSE-JSON-OBJECT-PARSE
    _O2TR-JSON>STATUS
    DUP IF R> DROP EXIT THEN DROP

    R@ _O2TRW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP OAUTH2-TOKEN-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    0 R@ _O2TRW.PRESENT !
    R@ _O2TR-PROCESS-ALL
    DUP IF R> DROP EXIT THEN DROP

    R@ _O2TRW.PRESENT @ _O2TR-REQUIRED-PRESENCE AND
    _O2TR-REQUIRED-PRESENCE <> IF
        R> DROP OAUTH2-TOKEN-RESPONSE-S-MISSING EXIT
    THEN
    _O2TR-VIEW-MAGIC-VALUE
    R@ _O2TRW.VIEW _O2TRV.MAGIC !
    R> DROP OAUTH2-TOKEN-RESPONSE-S-OK ;

\ =====================================================================
\  Admitted callback operation and mandatory cleanup
\ =====================================================================

-17301 CONSTANT _O2TR-E-CALLBACK-STACK

: _O2TR-CALLBACK-RUN  ( workspace -- callback-status )
    DEPTH >R
    DUP _O2TRW.CALLBACK @ >R
    DUP _O2TRW.VIEW
    SWAP _O2TRW.CONTEXT @
    R> EXECUTE
    DEPTH R> <> IF
        _O2TR-E-CALLBACK-STACK THROW
    THEN ;

: _O2TR-CALLBACK-SAFE  ( workspace -- callback-status parse-status )
    ['] _O2TR-CALLBACK-RUN CATCH
    DUP IF
        2DROP
        0 OAUTH2-TOKEN-RESPONSE-S-CALLBACK EXIT
    THEN
    DROP
    OAUTH2-TOKEN-RESPONSE-S-OK ;

: _O2TR-WITH-OP
  ( source source-u callback context workspace -- callback-status parse-status )
    DUP _O2TR-WIPE
    4 PICK OVER _O2TRW.SOURCE !
    3 PICK OVER _O2TRW.SOURCE-U !
    2 PICK OVER _O2TRW.CALLBACK !
    1 PICK OVER _O2TRW.CONTEXT !
    NIP NIP NIP NIP

    -1 OVER _O2TRW.VIEW _O2TRV.EXPIRES-IN !
    DUP _O2TR-PARSE-STAGE
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    _O2TR-CALLBACK-SAFE ;

: _O2TR-WITH-CALL
  ( source source-u callback context workspace operation-xt -- callback-status parse-status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _O2TR-WIPE
        _O2TR-DROP5
        R> DROP
        0 OAUTH2-TOKEN-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2TR-WIPE
    R> DROP ;

: OAUTH2-TOKEN-RESPONSE-WITH
  ( source source-u callback context workspace -- callback-status parse-status )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK
        _O2TR-WITH-GEOMETRY
    DUP IF
        >R _O2TR-DROP5 0 R> EXIT
    THEN
    DROP
    ['] _O2TR-WITH-OP _O2TR-WITH-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _O2TR-GEOMETRY-ABORT  ( -- )
    ." OAuth 2 token response geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TR-NAMES-SIZE JOSE-JSON-MAX-NAME-BYTES U> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TR-DESCRIPTOR-SIZE 688 <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRV-ACCESS-OFF OAUTH2-TOKEN-VIEW-ACCESS-CAPACITY +
_O2TRV-TYPE-OFF <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRV-TYPE-OFF OAUTH2-TOKEN-VIEW-TOKEN-TYPE-CAPACITY +
_O2TRV-REFRESH-OFF <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRV-REFRESH-OFF OAUTH2-TOKEN-VIEW-REFRESH-CAPACITY +
_O2TRV-SCOPE-OFF <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRV-SCOPE-OFF OAUTH2-TOKEN-VIEW-SCOPE-CAPACITY +
_O2TR-VIEW-SIZE <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TR-VIEW-SIZE 20528 <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRW-DESCRIPTOR-OFF _O2TR-DESCRIPTOR-SIZE +
_O2TRW-NAMES-OFF <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRW-NAMES-OFF _O2TR-NAMES-SIZE +
_O2TRW-JSON-OFF <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
_O2TRW-VIEW-OFF <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

_O2TRW-VIEW-OFF _O2TR-VIEW-SIZE +
OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]

OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE 30976 <> [IF]
    _O2TR-GEOMETRY-ABORT
[THEN]
