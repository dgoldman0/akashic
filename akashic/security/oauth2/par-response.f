\ =====================================================================
\  par-response.f - Ephemeral generic OAuth 2 PAR response decoding
\ =====================================================================
\  One strict JSON pushed authorization request (PAR) success response is
\  decoded into a view inside a caller-owned workspace.  The view and the
\  decoded request URI are valid only while the caller callback runs.  The
\  complete workspace is wiped after every admitted parse result, callback
\  return, or caught THROW.
\
\  Recognized members:
\
\    request_uri required, nonempty RFC 6749 VSCHAR string
\    expires_in  required, bounded positive integral number
\
\  Unknown members pass complete strict JSON validation and are ignored.
\  This module owns no HTTP, endpoint selection, error-response decoding,
\  request-URI binding or single-use policy, authorization transaction,
\  AT Protocol, persistence, or application policy.
\
\  Public API:
\
\    OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE
\    OAUTH2-PAR-RESPONSE-WITH
\    OAUTH2-PAR-VIEW-REQUEST-URI@
\    OAUTH2-PAR-VIEW-EXPIRES-IN@
\ =====================================================================

PROVIDED akashic-oauth2-parrsp

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../jose/json-object.f

\ =====================================================================
\  Public status and capacity vocabulary
\ =====================================================================

0  CONSTANT OAUTH2-PAR-RESPONSE-S-OK
1  CONSTANT OAUTH2-PAR-RESPONSE-S-INVALID
2  CONSTANT OAUTH2-PAR-RESPONSE-S-CAPACITY
3  CONSTANT OAUTH2-PAR-RESPONSE-S-ALIAS
4  CONSTANT OAUTH2-PAR-RESPONSE-S-JSON
5  CONSTANT OAUTH2-PAR-RESPONSE-S-MISSING
6  CONSTANT OAUTH2-PAR-RESPONSE-S-TYPE
7  CONSTANT OAUTH2-PAR-RESPONSE-S-VALUE
8  CONSTANT OAUTH2-PAR-RESPONSE-S-DUPLICATE
9  CONSTANT OAUTH2-PAR-RESPONSE-S-CALLBACK
10 CONSTANT OAUTH2-PAR-RESPONSE-S-INTERNAL
11 CONSTANT OAUTH2-PAR-RESPONSE-S-RANGE
12 CONSTANT OAUTH2-PAR-RESPONSE-S-PROTECTED
13 CONSTANT OAUTH2-PAR-RESPONSE-S-PLATFORM

: OAUTH2-PAR-RESPONSE-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-PAR-RESPONSE-S-OK >=
    SWAP OAUTH2-PAR-RESPONSE-S-PLATFORM <= AND ;

4096 CONSTANT OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY
2147483647 CONSTANT OAUTH2-PAR-VIEW-MAX-EXPIRES-IN

OAUTH2-PAR-VIEW-MAX-EXPIRES-IN 10 /
    CONSTANT _O2PR-EXPIRES-QUOTIENT
OAUTH2-PAR-VIEW-MAX-EXPIRES-IN 10 MOD
    CONSTANT _O2PR-EXPIRES-REMAINDER

1 CONSTANT _O2PR-P-REQUEST-URI
2 CONSTANT _O2PR-P-EXPIRES-IN

_O2PR-P-REQUEST-URI _O2PR-P-EXPIRES-IN OR
    CONSTANT _O2PR-REQUIRED-PRESENCE

\ =====================================================================
\  Ephemeral callback view
\ =====================================================================

0x4F32505256494557 CONSTANT _O2PR-VIEW-MAGIC-VALUE

 0 CONSTANT _O2PRV-MAGIC
 8 CONSTANT _O2PRV-REQUEST-URI-U
16 CONSTANT _O2PRV-EXPIRES-IN
24 CONSTANT _O2PRV-HEADER-SIZE

_O2PRV-HEADER-SIZE CONSTANT _O2PRV-REQUEST-URI-OFF
_O2PRV-REQUEST-URI-OFF OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY +
    CONSTANT _O2PR-VIEW-SIZE

: _O2PRV.MAGIC        ( view -- address ) _O2PRV-MAGIC + ;
: _O2PRV.REQUEST-URI-U ( view -- address ) _O2PRV-REQUEST-URI-U + ;
: _O2PRV.EXPIRES-IN   ( view -- address ) _O2PRV-EXPIRES-IN + ;

: _O2PRV.REQUEST-URI  ( view -- address ) _O2PRV-REQUEST-URI-OFF + ;

\ =====================================================================
\  Caller admission and view access
\ =====================================================================

: _O2PR-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP OAUTH2-PAR-RESPONSE-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP OAUTH2-PAR-RESPONSE-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP OAUTH2-PAR-RESPONSE-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP OAUTH2-PAR-RESPONSE-S-PLATFORM EXIT
    THEN
    DROP OAUTH2-PAR-RESPONSE-S-PLATFORM ;

: _O2PR-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _O2PR-CALLER>STATUS ;

: _O2PR-REQUIRED-LENGTH?  ( length capacity -- flag )
    OVER 0> IF
        U> 0=
    ELSE
        2DROP 0
    THEN ;

: _O2PR-VIEW-VALID?  ( view -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP _O2PR-VIEW-SIZE _O2PR-ADMIT-SPAN
        OAUTH2-PAR-RESPONSE-S-OK <> IF
        DROP 0 EXIT
    THEN
    DUP _O2PRV.MAGIC @ _O2PR-VIEW-MAGIC-VALUE <> IF
        DROP 0 EXIT
    THEN
    DUP _O2PRV.REQUEST-URI-U @
        OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY
        _O2PR-REQUIRED-LENGTH? 0= IF
        DROP 0 EXIT
    THEN
    DUP _O2PRV.EXPIRES-IN @
    DUP 1 < IF
        2DROP 0 EXIT
    THEN
    OAUTH2-PAR-VIEW-MAX-EXPIRES-IN U> 0=
    SWAP DROP ;

: _O2PR-VIEW-TEXT@  ( view length-offset data-offset -- address length )
    >R
    OVER SWAP + @
    SWAP R> + SWAP ;

: OAUTH2-PAR-VIEW-REQUEST-URI@
  ( view -- address length status )
    DUP _O2PR-VIEW-VALID? 0= IF
        DROP 0 0 OAUTH2-PAR-RESPONSE-S-INVALID EXIT
    THEN
    _O2PRV-REQUEST-URI-U _O2PRV-REQUEST-URI-OFF
    _O2PR-VIEW-TEXT@
    OAUTH2-PAR-RESPONSE-S-OK ;

: OAUTH2-PAR-VIEW-EXPIRES-IN@
  ( view -- seconds status )
    DUP _O2PR-VIEW-VALID? 0= IF
        DROP 0 OAUTH2-PAR-RESPONSE-S-INVALID EXIT
    THEN
    _O2PRV.EXPIRES-IN @ OAUTH2-PAR-RESPONSE-S-OK ;

\ =====================================================================
\  Caller-owned operation workspace
\ =====================================================================

16 CONSTANT _O2PR-MAX-MEMBERS
1024 CONSTANT _O2PR-NAMES-SIZE

_O2PR-MAX-MEMBERS JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." OAuth 2 PAR response descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _O2PR-DESCRIPTOR-SIZE

 0 CONSTANT _O2PRW-SOURCE
 8 CONSTANT _O2PRW-SOURCE-U
16 CONSTANT _O2PRW-CALLBACK
24 CONSTANT _O2PRW-CONTEXT
32 CONSTANT _O2PRW-NAME-A
40 CONSTANT _O2PRW-NAME-U
48 CONSTANT _O2PRW-VALUE-A
56 CONSTANT _O2PRW-VALUE-U
64 CONSTANT _O2PRW-VALUE-TYPE
72 CONSTANT _O2PRW-PRESENT
80 CONSTANT _O2PRW-SCAN
88 CONSTANT _O2PRW-ACCUMULATOR
96 CONSTANT _O2PRW-HEADER-SIZE

_O2PRW-HEADER-SIZE CONSTANT _O2PRW-DESCRIPTOR-OFF
_O2PRW-DESCRIPTOR-OFF _O2PR-DESCRIPTOR-SIZE +
    CONSTANT _O2PRW-NAMES-OFF
_O2PRW-NAMES-OFF _O2PR-NAMES-SIZE +
    CONSTANT _O2PRW-JSON-OFF
_O2PRW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
    CONSTANT _O2PRW-VIEW-OFF
_O2PRW-VIEW-OFF _O2PR-VIEW-SIZE +
    CONSTANT OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE

: _O2PRW.SOURCE       ( workspace -- address ) _O2PRW-SOURCE + ;
: _O2PRW.SOURCE-U     ( workspace -- address ) _O2PRW-SOURCE-U + ;
: _O2PRW.CALLBACK     ( workspace -- address ) _O2PRW-CALLBACK + ;
: _O2PRW.CONTEXT      ( workspace -- address ) _O2PRW-CONTEXT + ;
: _O2PRW.NAME-A       ( workspace -- address ) _O2PRW-NAME-A + ;
: _O2PRW.NAME-U       ( workspace -- address ) _O2PRW-NAME-U + ;
: _O2PRW.VALUE-A      ( workspace -- address ) _O2PRW-VALUE-A + ;
: _O2PRW.VALUE-U      ( workspace -- address ) _O2PRW-VALUE-U + ;
: _O2PRW.VALUE-TYPE   ( workspace -- address ) _O2PRW-VALUE-TYPE + ;
: _O2PRW.PRESENT      ( workspace -- address ) _O2PRW-PRESENT + ;
: _O2PRW.SCAN         ( workspace -- address ) _O2PRW-SCAN + ;
: _O2PRW.ACCUMULATOR  ( workspace -- address ) _O2PRW-ACCUMULATOR + ;

: _O2PRW.DESCRIPTOR  ( workspace -- address )
    _O2PRW-DESCRIPTOR-OFF + ;
: _O2PRW.NAMES       ( workspace -- address ) _O2PRW-NAMES-OFF + ;
: _O2PRW.JSON        ( workspace -- address ) _O2PRW-JSON-OFF + ;
: _O2PRW.VIEW        ( workspace -- address ) _O2PRW-VIEW-OFF + ;

: _O2PR-WIPE  ( workspace -- )
    OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Geometry and stack helpers
\ =====================================================================

: _O2PR-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _O2PR-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;

: _O2PR-RETURN5  ( x1 x2 x3 x4 x5 status -- status )
    >R _O2PR-DROP5 R> ;

: _O2PR-WITH-GEOMETRY
  ( source source-u callback context workspace -- status )
    DUP OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE _O2PR-ADMIT-SPAN
        ?DUP IF
        _O2PR-RETURN5 EXIT
    THEN
    DUP 7 AND IF
        OAUTH2-PAR-RESPONSE-S-INVALID _O2PR-RETURN5 EXIT
    THEN
    4 PICK 4 PICK _O2PR-ADMIT-SPAN ?DUP IF
        _O2PR-RETURN5 EXIT
    THEN
    2 PICK 0= IF
        OAUTH2-PAR-RESPONSE-S-INVALID _O2PR-RETURN5 EXIT
    THEN
    3 PICK 0= IF
        OAUTH2-PAR-RESPONSE-S-INVALID _O2PR-RETURN5 EXIT
    THEN
    3 PICK JOSE-JSON-MAX-DOCUMENT-BYTES U> IF
        OAUTH2-PAR-RESPONSE-S-CAPACITY _O2PR-RETURN5 EXIT
    THEN
    4 PICK 4 PICK 2 PICK OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-PAR-RESPONSE-S-ALIAS _O2PR-RETURN5 EXIT
    THEN
    OAUTH2-PAR-RESPONSE-S-OK _O2PR-RETURN5 ;

\ =====================================================================
\  Strict field decoding and policy
\ =====================================================================

: _O2PR-JSON>STATUS  ( json-status -- status )
    DUP JOSE-JSON-S-OK = IF
        DROP OAUTH2-PAR-RESPONSE-S-OK EXIT
    THEN
    DUP JOSE-JSON-S-DUPLICATE = IF
        DROP OAUTH2-PAR-RESPONSE-S-DUPLICATE EXIT
    THEN
    DUP JOSE-JSON-S-CAPACITY = IF
        DROP OAUTH2-PAR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-MEMBERS = IF
        DROP OAUTH2-PAR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-STRING = IF
        DROP OAUTH2-PAR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-DOCUMENT = IF
        DROP OAUTH2-PAR-RESPONSE-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-SYNTAX = IF
        DROP OAUTH2-PAR-RESPONSE-S-JSON EXIT
    THEN
    DUP JOSE-JSON-S-UTF8 = IF
        DROP OAUTH2-PAR-RESPONSE-S-JSON EXIT
    THEN
    DUP JOSE-JSON-S-DEPTH = IF
        DROP OAUTH2-PAR-RESPONSE-S-JSON EXIT
    THEN
    DROP OAUTH2-PAR-RESPONSE-S-INTERNAL ;

: _O2PR-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _O2PRW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP OAUTH2-PAR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2PRW.VALUE-TYPE !
    R@ _O2PRW.VALUE-U !
    R@ _O2PRW.SOURCE @ + R@ _O2PRW.VALUE-A !
    R@ _O2PRW.NAME-U !
    R@ _O2PRW.NAMES + R@ _O2PRW.NAME-A !
    R> DROP OAUTH2-PAR-RESPONSE-S-OK ;

: _O2PR-NAME=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _O2PRW.NAME-A @ R@ _O2PRW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _O2PR-COPY-MEMBER-STRING
  ( destination length-cell capacity workspace -- status )
    >R
    R@ _O2PRW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        _O2PR-DROP3 R> DROP OAUTH2-PAR-RESPONSE-S-TYPE EXIT
    THEN
    R@ _O2PRW.SCAN !
    R@ _O2PRW.NAME-U !
    R@ _O2PRW.NAME-A !

    R@ _O2PRW.VALUE-A @ R@ _O2PRW.VALUE-U @
    R@ _O2PRW.NAME-A @ R@ _O2PRW.SCAN @
    R@ _O2PRW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        DUP JOSE-JSON-S-CAPACITY =
        OVER JOSE-JSON-S-STRING = OR IF
            2DROP R> DROP
            OAUTH2-PAR-RESPONSE-S-CAPACITY EXIT
        THEN
        2DROP R> DROP OAUTH2-PAR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    DUP 0= IF
        DROP R> DROP OAUTH2-PAR-RESPONSE-S-VALUE EXIT
    THEN
    R@ _O2PRW.NAME-U @ !
    R> DROP OAUTH2-PAR-RESPONSE-S-OK ;

: _O2PR-MARK-PRESENT  ( mask workspace -- status )
    >R
    DUP R@ _O2PRW.PRESENT @ AND IF
        DROP R> DROP OAUTH2-PAR-RESPONSE-S-DUPLICATE EXIT
    THEN
    R@ _O2PRW.PRESENT @ OR R@ _O2PRW.PRESENT !
    R> DROP OAUTH2-PAR-RESPONSE-S-OK ;

: _O2PR-VSCHAR?  ( address length -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    BEGIN DUP WHILE
        OVER C@ 32 127 WITHIN 0= IF
            2DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _O2PR-DIGIT?  ( byte -- flag )
    48 58 WITHIN ;

: _O2PR-EXPIRES-ACCUMULATE
  ( accumulator digit -- accumulator-next valid? )
    >R
    DUP _O2PR-EXPIRES-QUOTIENT U> IF
        DROP R> DROP 0 0 EXIT
    THEN
    DUP _O2PR-EXPIRES-QUOTIENT = IF
        R@ _O2PR-EXPIRES-REMAINDER U> IF
            DROP R> DROP 0 0 EXIT
        THEN
    THEN
    10 * R> + -1 ;

: _O2PR-PARSE-EXPIRES  ( workspace -- status )
    DUP _O2PRW.VALUE-TYPE @ JOSE-JSON-T-NUMBER <> IF
        DROP OAUTH2-PAR-RESPONSE-S-TYPE EXIT
    THEN
    DUP _O2PRW.VALUE-U @ 0= IF
        DROP OAUTH2-PAR-RESPONSE-S-INTERNAL EXIT
    THEN
    0 OVER _O2PRW.SCAN !
    0 OVER _O2PRW.ACCUMULATOR !
    BEGIN
        DUP _O2PRW.SCAN @
        OVER _O2PRW.VALUE-U @ U<
    WHILE
        DUP _O2PRW.VALUE-A @
        OVER _O2PRW.SCAN @ + C@
        DUP _O2PR-DIGIT? 0= IF
            2DROP OAUTH2-PAR-RESPONSE-S-VALUE EXIT
        THEN
        48 -
        OVER _O2PRW.ACCUMULATOR @ SWAP
        _O2PR-EXPIRES-ACCUMULATE 0= IF
            2DROP OAUTH2-PAR-RESPONSE-S-VALUE EXIT
        THEN
        OVER _O2PRW.ACCUMULATOR !
        1 OVER _O2PRW.SCAN +!
    REPEAT
    DUP _O2PRW.ACCUMULATOR @
    DUP 0= IF
        2DROP OAUTH2-PAR-RESPONSE-S-VALUE EXIT
    THEN
    OVER _O2PRW.VIEW _O2PRV.EXPIRES-IN !
    DROP OAUTH2-PAR-RESPONSE-S-OK ;

: _O2PR-PROCESS-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _O2PR-MEMBER-LOAD
    DUP IF NIP R> DROP EXIT THEN
    2DROP

    S" request_uri" R@ _O2PR-NAME= IF
        R@ _O2PRW.VIEW _O2PRV.REQUEST-URI
        R@ _O2PRW.VIEW _O2PRV.REQUEST-URI-U
        OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY
        R@ _O2PR-COPY-MEMBER-STRING
        DUP IF R> DROP EXIT THEN DROP
        R@ _O2PRW.VIEW _O2PRV.REQUEST-URI
        R@ _O2PRW.VIEW _O2PRV.REQUEST-URI-U @
        _O2PR-VSCHAR? 0= IF
            R> DROP OAUTH2-PAR-RESPONSE-S-VALUE EXIT
        THEN
        _O2PR-P-REQUEST-URI
        R@ _O2PR-MARK-PRESENT R> DROP EXIT
    THEN

    S" expires_in" R@ _O2PR-NAME= IF
        R@ _O2PR-PARSE-EXPIRES
        DUP IF R> DROP EXIT THEN DROP
        _O2PR-P-EXPIRES-IN
        R@ _O2PR-MARK-PRESENT R> DROP EXIT
    THEN

    R> DROP OAUTH2-PAR-RESPONSE-S-OK ;

: _O2PR-PROCESS-ALL  ( count workspace -- status )
    SWAP 0 SWAP
    BEGIN 2DUP U< WHILE
        2 PICK 2 PICK SWAP _O2PR-PROCESS-MEMBER
        DUP IF
            >R _O2PR-DROP3 R> EXIT
        THEN
        DROP
        SWAP 1+ SWAP
    REPEAT
    _O2PR-DROP3 OAUTH2-PAR-RESPONSE-S-OK ;

: _O2PR-PARSE-STAGE  ( workspace -- status )
    >R
    R@ _O2PRW.SOURCE @ R@ _O2PRW.SOURCE-U @
    R@ _O2PRW.DESCRIPTOR _O2PR-MAX-MEMBERS
    R@ _O2PRW.NAMES _O2PR-NAMES-SIZE
    R@ _O2PRW.JSON
    JOSE-JSON-OBJECT-PARSE
    _O2PR-JSON>STATUS
    DUP IF R> DROP EXIT THEN DROP

    R@ _O2PRW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP OAUTH2-PAR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    0 R@ _O2PRW.PRESENT !
    R@ _O2PR-PROCESS-ALL
    DUP IF R> DROP EXIT THEN DROP

    R@ _O2PRW.PRESENT @ _O2PR-REQUIRED-PRESENCE AND
    _O2PR-REQUIRED-PRESENCE <> IF
        R> DROP OAUTH2-PAR-RESPONSE-S-MISSING EXIT
    THEN
    _O2PR-VIEW-MAGIC-VALUE
    R@ _O2PRW.VIEW _O2PRV.MAGIC !
    R> DROP OAUTH2-PAR-RESPONSE-S-OK ;

\ =====================================================================
\  Admitted callback operation and mandatory cleanup
\ =====================================================================

-17311 CONSTANT _O2PR-E-CALLBACK-STACK

: _O2PR-CALLBACK-RUN  ( workspace -- callback-status )
    DEPTH >R
    DUP _O2PRW.CALLBACK @ >R
    DUP _O2PRW.VIEW
    SWAP _O2PRW.CONTEXT @
    R> EXECUTE
    DEPTH R> <> IF
        _O2PR-E-CALLBACK-STACK THROW
    THEN ;

: _O2PR-CALLBACK-SAFE  ( workspace -- callback-status response-status )
    ['] _O2PR-CALLBACK-RUN CATCH
    DUP IF
        2DROP
        0 OAUTH2-PAR-RESPONSE-S-CALLBACK EXIT
    THEN
    DROP
    OAUTH2-PAR-RESPONSE-S-OK ;

: _O2PR-WITH-OP
  \ ( source source-u callback context workspace
  \   -- callback-status response-status )
    DUP _O2PR-WIPE
    4 PICK OVER _O2PRW.SOURCE !
    3 PICK OVER _O2PRW.SOURCE-U !
    2 PICK OVER _O2PRW.CALLBACK !
    1 PICK OVER _O2PRW.CONTEXT !
    NIP NIP NIP NIP

    DUP _O2PR-PARSE-STAGE
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    _O2PR-CALLBACK-SAFE ;

: _O2PR-WITH-CALL
  \ ( source source-u callback context workspace operation-xt
  \   -- callback-status response-status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _O2PR-WIPE
        _O2PR-DROP5
        R> DROP
        0 OAUTH2-PAR-RESPONSE-S-INTERNAL EXIT
    THEN
    DROP
    R@ _O2PR-WIPE
    R> DROP ;

: OAUTH2-PAR-RESPONSE-WITH
  \ ( source source-u callback context workspace
  \   -- callback-status response-status )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK
        _O2PR-WITH-GEOMETRY
    DUP IF
        >R _O2PR-DROP5 0 R> EXIT
    THEN
    DROP
    ['] _O2PR-WITH-OP _O2PR-WITH-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _O2PR-GEOMETRY-ABORT  ( -- )
    ." OAuth 2 PAR response geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PR-NAMES-SIZE JOSE-JSON-MAX-NAME-BYTES U> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PR-DESCRIPTOR-SIZE 688 <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PRV-REQUEST-URI-OFF OAUTH2-PAR-VIEW-REQUEST-URI-CAPACITY +
_O2PR-VIEW-SIZE <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PR-VIEW-SIZE 4120 <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PRW-DESCRIPTOR-OFF _O2PR-DESCRIPTOR-SIZE +
_O2PRW-NAMES-OFF <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PRW-NAMES-OFF _O2PR-NAMES-SIZE +
_O2PRW-JSON-OFF <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PRW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
_O2PRW-VIEW-OFF <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

_O2PRW-VIEW-OFF _O2PR-VIEW-SIZE +
OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]

OAUTH2-PAR-RESPONSE-WORKSPACE-SIZE 14568 <> [IF]
    _O2PR-GEOMETRY-ABORT
[THEN]
