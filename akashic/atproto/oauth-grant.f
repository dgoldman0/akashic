\ =====================================================================
\  oauth-grant.f - AT Protocol OAuth token-grant admission
\ =====================================================================
\  This state-free adapter applies the AT Protocol OAuth token-response
\  policy to the generic ephemeral OAuth token decoder.  A successful
\  operation lends one populated generic O2SESSION grant descriptor to a
\  synchronous caller callback.  The descriptor and all of its borrowed
\  token spans are valid only during that callback.
\
\  This module owns no HTTP, authorization transaction, DPoP key or nonce,
\  clock, credential RID, durable session, XRPC, or Streams state.  It
\  never mutates an OAuth session.
\
\  Public API:
\
\    AT-OAUTH-GRANT-WORKSPACE-SIZE
\    AT-OAUTH-GRANT-WORKSPACE-CLEAR
\    AT-OAUTH-GRANT-STATUS-VALID?
\    AT-OAUTH-GRANT-MODE-VALID?
\    AT-OAUTH-GRANT-WITH
\ =====================================================================

PROVIDED akashic-at-oauth-grant

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../security/oauth2/token-response.f
REQUIRE ../security/oauth2/session.f
REQUIRE did.f
REQUIRE oauth-profile.f

\ =====================================================================
\  Public status and mode vocabulary
\ =====================================================================

0  CONSTANT AT-OAUTH-GRANT-S-OK
1  CONSTANT AT-OAUTH-GRANT-S-INVALID
2  CONSTANT AT-OAUTH-GRANT-S-CAPACITY
3  CONSTANT AT-OAUTH-GRANT-S-ALIAS
4  CONSTANT AT-OAUTH-GRANT-S-PROFILE
5  CONSTANT AT-OAUTH-GRANT-S-RESPONSE
6  CONSTANT AT-OAUTH-GRANT-S-TOKEN-TYPE
7  CONSTANT AT-OAUTH-GRANT-S-SCOPE
8  CONSTANT AT-OAUTH-GRANT-S-SUBJECT
9  CONSTANT AT-OAUTH-GRANT-S-SUBJECT-BINDING
10 CONSTANT AT-OAUTH-GRANT-S-REFRESH
11 CONSTANT AT-OAUTH-GRANT-S-TIME
12 CONSTANT AT-OAUTH-GRANT-S-OVERFLOW
13 CONSTANT AT-OAUTH-GRANT-S-CALLBACK
14 CONSTANT AT-OAUTH-GRANT-S-INTERNAL
15 CONSTANT AT-OAUTH-GRANT-S-RANGE
16 CONSTANT AT-OAUTH-GRANT-S-PROTECTED
17 CONSTANT AT-OAUTH-GRANT-S-PLATFORM

: AT-OAUTH-GRANT-STATUS-VALID?  ( status -- flag )
    DUP AT-OAUTH-GRANT-S-OK >=
    SWAP AT-OAUTH-GRANT-S-PLATFORM <= AND ;

0 CONSTANT AT-OAUTH-GRANT-MODE-INITIAL
1 CONSTANT AT-OAUTH-GRANT-MODE-REFRESH

: AT-OAUTH-GRANT-MODE-VALID?  ( mode -- flag )
    DUP AT-OAUTH-GRANT-MODE-INITIAL =
    SWAP AT-OAUTH-GRANT-MODE-REFRESH = OR ;

-1 1 RSHIFT CONSTANT _ATOG-CELL-MAX

\ =====================================================================
\  Caller-owned operation workspace
\ =====================================================================

 0 CONSTANT _ATOGW-CALLBACK
 8 CONSTANT _ATOGW-CONTEXT
16 CONSTANT _ATOGW-PROFILE
24 CONSTANT _ATOGW-MODE
32 CONSTANT _ATOGW-BASE-MS
40 CONSTANT _ATOGW-CALLBACK-RESULT
48 CONSTANT _ATOGW-POLICY-STATUS
56 CONSTANT _ATOGW-PARSER-STATUS
64 CONSTANT _ATOGW-HEADER-SIZE

_ATOGW-HEADER-SIZE CONSTANT _ATOGW-GRANT-OFF
_ATOGW-GRANT-OFF O2SESSION-GRANT-SIZE +
    CONSTANT _ATOGW-TOKEN-WORK-OFF
_ATOGW-TOKEN-WORK-OFF OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE +
    CONSTANT AT-OAUTH-GRANT-WORKSPACE-SIZE

: _ATOGW.CALLBACK  ( workspace -- field ) _ATOGW-CALLBACK + ;
: _ATOGW.CONTEXT   ( workspace -- field ) _ATOGW-CONTEXT + ;
: _ATOGW.PROFILE   ( workspace -- field ) _ATOGW-PROFILE + ;
: _ATOGW.MODE      ( workspace -- field ) _ATOGW-MODE + ;
: _ATOGW.BASE-MS   ( workspace -- field ) _ATOGW-BASE-MS + ;
: _ATOGW.CALLBACK-RESULT
  ( workspace -- field ) _ATOGW-CALLBACK-RESULT + ;
: _ATOGW.POLICY-STATUS
  ( workspace -- field ) _ATOGW-POLICY-STATUS + ;
: _ATOGW.PARSER-STATUS
  ( workspace -- field ) _ATOGW-PARSER-STATUS + ;

: _ATOGW.GRANT       ( workspace -- grant ) _ATOGW-GRANT-OFF + ;
: _ATOGW.TOKEN-WORK  ( workspace -- token-workspace )
    _ATOGW-TOKEN-WORK-OFF + ;

: _ATOG-WIPE  ( workspace -- )
    AT-OAUTH-GRANT-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Admission and geometry
\ =====================================================================

: _ATOG-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP AT-OAUTH-GRANT-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP AT-OAUTH-GRANT-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-OAUTH-GRANT-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-OAUTH-GRANT-S-PLATFORM EXIT
    THEN
    DROP AT-OAUTH-GRANT-S-PLATFORM ;

: _ATOG-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP AT-OAUTH-GRANT-S-INVALID EXIT THEN
    DUP 0= IF 2DROP AT-OAUTH-GRANT-S-OK EXIT THEN
    OVER 0= IF 2DROP AT-OAUTH-GRANT-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATOG-CALLER>STATUS ;

: _ATOG-FIXED-STATUS  ( address size -- status )
    OVER 0= IF 2DROP AT-OAUTH-GRANT-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP AT-OAUTH-GRANT-S-INVALID EXIT THEN
    _ATOG-SPAN-STATUS ;

: _ATOG-DROP3  ( x1 x2 x3 -- )
    2DROP DROP ;

: _ATOG-DROP8  ( eight-values -- )
    2DROP 2DROP 2DROP 2DROP ;

: _ATOG-8DUP  ( eight-values -- the-same-eight-values twice )
    7 PICK 7 PICK 7 PICK 7 PICK
    7 PICK 7 PICK 7 PICK 7 PICK ;

: _ATOG-RETURN8  ( eight-values status -- status )
    >R _ATOG-DROP8 R> ;

: _ATOG-WITH-GEOMETRY
  ( source source-u mode base-ms profile callback context workspace -- status )
    DUP AT-OAUTH-GRANT-WORKSPACE-SIZE _ATOG-FIXED-STATUS
    ?DUP IF _ATOG-RETURN8 EXIT THEN

    7 PICK 7 PICK _ATOG-SPAN-STATUS
    ?DUP IF _ATOG-RETURN8 EXIT THEN
    6 PICK 0> 0= IF
        AT-OAUTH-GRANT-S-INVALID _ATOG-RETURN8 EXIT
    THEN
    5 PICK AT-OAUTH-GRANT-MODE-VALID? 0= IF
        AT-OAUTH-GRANT-S-INVALID _ATOG-RETURN8 EXIT
    THEN
    4 PICK DUP 0< IF
        DROP AT-OAUTH-GRANT-S-TIME _ATOG-RETURN8 EXIT
    THEN
    _ATOG-CELL-MAX U> IF
        AT-OAUTH-GRANT-S-TIME _ATOG-RETURN8 EXIT
    THEN
    3 PICK AT-OAUTH-PROFILE-SIZE _ATOG-FIXED-STATUS
    ?DUP IF _ATOG-RETURN8 EXIT THEN
    2 PICK 0= IF
        AT-OAUTH-GRANT-S-INVALID _ATOG-RETURN8 EXIT
    THEN

    7 PICK 7 PICK 2 PICK AT-OAUTH-GRANT-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-GRANT-S-ALIAS _ATOG-RETURN8 EXIT
    THEN
    7 PICK 7 PICK 5 PICK AT-OAUTH-PROFILE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-GRANT-S-ALIAS _ATOG-RETURN8 EXIT
    THEN
    3 PICK AT-OAUTH-PROFILE-SIZE
    2 PICK AT-OAUTH-GRANT-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        AT-OAUTH-GRANT-S-ALIAS _ATOG-RETURN8 EXIT
    THEN
    3 PICK AT-OAUTH-PROFILE-READY? 0= IF
        AT-OAUTH-GRANT-S-PROFILE _ATOG-RETURN8 EXIT
    THEN
    AT-OAUTH-GRANT-S-OK _ATOG-RETURN8 ;

: AT-OAUTH-GRANT-WORKSPACE-CLEAR  ( workspace -- status )
    DUP AT-OAUTH-GRANT-WORKSPACE-SIZE _ATOG-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _ATOG-WIPE
    AT-OAUTH-GRANT-S-OK ;

\ =====================================================================
\  Generic response-status mapping
\ =====================================================================

: _ATOG-PARSER>STATUS  ( parser-status -- grant-status )
    DUP OAUTH2-TOKEN-RESPONSE-S-OK = IF
        DROP AT-OAUTH-GRANT-S-OK EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-CAPACITY = IF
        DROP AT-OAUTH-GRANT-S-CAPACITY EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-ALIAS = IF
        DROP AT-OAUTH-GRANT-S-ALIAS EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-RANGE = IF
        DROP AT-OAUTH-GRANT-S-RANGE EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-PROTECTED = IF
        DROP AT-OAUTH-GRANT-S-PROTECTED EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-PLATFORM = IF
        DROP AT-OAUTH-GRANT-S-PLATFORM EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-CALLBACK = IF
        DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-INVALID = IF
        DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-INTERNAL = IF
        DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-STATUS-VALID? IF
        DROP AT-OAUTH-GRANT-S-RESPONSE EXIT
    THEN
    DROP AT-OAUTH-GRANT-S-INTERNAL ;

\ =====================================================================
\  AT Protocol policy helpers
\ =====================================================================

: _ATOG-ASCII-LOWER  ( byte -- folded-byte )
    DUP [CHAR] A [CHAR] Z 1+ WITHIN IF 32 + THEN ;

: _ATOG-DPOP?  ( address length -- flag )
    DUP 4 <> IF 2DROP 0 EXIT THEN
    OVER C@ _ATOG-ASCII-LOWER [CHAR] d =
    2 PICK 1+ C@ _ATOG-ASCII-LOWER [CHAR] p = AND
    2 PICK 2 + C@ _ATOG-ASCII-LOWER [CHAR] o = AND
    2 PICK 3 + C@ _ATOG-ASCII-LOWER [CHAR] p = AND
    >R 2DROP R> ;

: _ATOG-TOKEN-LENGTH  ( address length -- token-length )
    0
    BEGIN
        DUP 2 PICK U<
    WHILE
        2 PICK OVER + C@ 32 = IF
            >R 2DROP R> EXIT
        THEN
        1+
    REPEAT
    >R 2DROP R> ;

: _ATOG-ATPROTO-SCOPE?  ( address length -- flag )
    BEGIN
        DUP
    WHILE
        2DUP _ATOG-TOKEN-LENGTH >R
        OVER R@ S" atproto" COMPARE 0= IF
            2DROP R> DROP -1 EXIT
        THEN
        DUP R@ = IF
            2DROP R> DROP 0 EXIT
        THEN
        R> 1+ /STRING
    REPEAT
    2DROP 0 ;

: _ATOG-GRANT-FLAG!  ( flag workspace -- )
    _ATOGW.GRANT O2SESSION-G.FLAGS
    DUP @ ROT OR SWAP ! ;

: _ATOG-STAGE-SPAN
  ( address length address-field length-field -- )
    >R
    2 PICK OVER !
    DROP
    DUP R> !
    2DROP ;

: _ATOG-STAGE-ACCESS  ( view workspace -- status )
    >R
    OAUTH2-TOKEN-VIEW-ACCESS-TOKEN@
    DUP OAUTH2-TOKEN-RESPONSE-S-OK <> IF
        _ATOG-DROP3 R> DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATOGW.GRANT O2SESSION-G.ACCESS-A
    R@ _ATOGW.GRANT O2SESSION-G.ACCESS-U
    _ATOG-STAGE-SPAN
    R> DROP AT-OAUTH-GRANT-S-OK ;

: _ATOG-STAGE-TYPE  ( view workspace -- status )
    >R
    OAUTH2-TOKEN-VIEW-TOKEN-TYPE@
    DUP OAUTH2-TOKEN-RESPONSE-S-OK <> IF
        _ATOG-DROP3 R> DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    2DUP _ATOG-DPOP? 0= IF
        2DROP R> DROP AT-OAUTH-GRANT-S-TOKEN-TYPE EXIT
    THEN
    R@ _ATOGW.GRANT O2SESSION-G.TOKEN-TYPE-A
    R@ _ATOGW.GRANT O2SESSION-G.TOKEN-TYPE-U
    _ATOG-STAGE-SPAN
    R> DROP AT-OAUTH-GRANT-S-OK ;

: _ATOG-STAGE-SCOPE  ( view workspace -- status )
    >R
    OAUTH2-TOKEN-VIEW-SCOPE@
    DUP OAUTH2-TOKEN-RESPONSE-S-MISSING = IF
        _ATOG-DROP3 R> DROP AT-OAUTH-GRANT-S-SCOPE EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-OK <> IF
        _ATOG-DROP3 R> DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    2DUP _ATOG-ATPROTO-SCOPE? 0= IF
        2DROP R> DROP AT-OAUTH-GRANT-S-SCOPE EXIT
    THEN
    R@ _ATOGW.GRANT O2SESSION-G.SCOPE-A
    R@ _ATOGW.GRANT O2SESSION-G.SCOPE-U
    _ATOG-STAGE-SPAN
    O2SESSION-GRANT-F-SCOPE R@ _ATOG-GRANT-FLAG!
    R> DROP AT-OAUTH-GRANT-S-OK ;

: _ATOG-CHECK-SUBJECT  ( view workspace -- status )
    >R
    OAUTH2-TOKEN-VIEW-SUBJECT@
    DUP OAUTH2-TOKEN-RESPONSE-S-MISSING = IF
        _ATOG-DROP3 R> DROP AT-OAUTH-GRANT-S-SUBJECT EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-OK <> IF
        _ATOG-DROP3 R> DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    2DUP DID-VALIDATE DID-S-OK <> IF
        2DROP R> DROP AT-OAUTH-GRANT-S-SUBJECT EXIT
    THEN
    R@ _ATOGW.PROFILE @ AT-OAUTH-PROFILE-DID@
    DUP AT-OAUTH-PROFILE-S-OK <> IF
        _ATOG-DROP3 2DROP R> DROP
        AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    COMPARE 0= IF
        R> DROP AT-OAUTH-GRANT-S-OK
    ELSE
        R> DROP AT-OAUTH-GRANT-S-SUBJECT-BINDING
    THEN ;

: _ATOG-STAGE-REFRESH  ( view workspace -- status )
    >R
    OAUTH2-TOKEN-VIEW-REFRESH-TOKEN@
    DUP OAUTH2-TOKEN-RESPONSE-S-MISSING = IF
        _ATOG-DROP3
        R@ _ATOGW.MODE @ AT-OAUTH-GRANT-MODE-INITIAL = IF
            R> DROP AT-OAUTH-GRANT-S-OK
        ELSE
            R> DROP AT-OAUTH-GRANT-S-REFRESH
        THEN
        EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-OK <> IF
        _ATOG-DROP3 R> DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATOGW.GRANT O2SESSION-G.REFRESH-A
    R@ _ATOGW.GRANT O2SESSION-G.REFRESH-U
    _ATOG-STAGE-SPAN
    O2SESSION-GRANT-F-REFRESH R@ _ATOG-GRANT-FLAG!
    R> DROP AT-OAUTH-GRANT-S-OK ;

: _ATOG-DEADLINE  ( seconds base-ms -- deadline status )
    DUP 0< IF
        2DROP 0 AT-OAUTH-GRANT-S-TIME EXIT
    THEN
    >R
    DUP _ATOG-CELL-MAX 1000 / U> IF
        DROP R> DROP 0 AT-OAUTH-GRANT-S-OVERFLOW EXIT
    THEN
    1000 *
    DUP _ATOG-CELL-MAX R@ - U> IF
        DROP R> DROP 0 AT-OAUTH-GRANT-S-OVERFLOW EXIT
    THEN
    R> + AT-OAUTH-GRANT-S-OK ;

: _ATOG-STAGE-EXPIRY  ( view workspace -- status )
    >R
    OAUTH2-TOKEN-VIEW-EXPIRES-IN@
    DUP OAUTH2-TOKEN-RESPONSE-S-MISSING = IF
        2DROP R> DROP AT-OAUTH-GRANT-S-OK EXIT
    THEN
    DUP OAUTH2-TOKEN-RESPONSE-S-OK <> IF
        2DROP R> DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATOGW.BASE-MS @ _ATOG-DEADLINE
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    R@ _ATOGW.GRANT O2SESSION-G.EXPIRES-AT-MS !
    O2SESSION-GRANT-F-EXPIRY R@ _ATOG-GRANT-FLAG!
    R> DROP AT-OAUTH-GRANT-S-OK ;

\ =====================================================================
\  External callback and admitted policy operation
\ =====================================================================

-17501 CONSTANT _ATOG-E-CALLBACK-STACK

: _ATOG-CLIENT-CALLBACK-RUN  ( workspace -- callback-result )
    DEPTH >R
    DUP _ATOGW.CALLBACK @ >R
    DUP _ATOGW.GRANT
    SWAP _ATOGW.CONTEXT @
    R> EXECUTE
    DEPTH R> <> IF
        _ATOG-E-CALLBACK-STACK THROW
    THEN ;

: _ATOG-CLIENT-CALLBACK-SAFE
  ( workspace -- callback-result grant-status )
    ['] _ATOG-CLIENT-CALLBACK-RUN CATCH
    DUP IF
        2DROP
        0 AT-OAUTH-GRANT-S-CALLBACK EXIT
    THEN
    DROP
    AT-OAUTH-GRANT-S-OK ;

: _ATOG-POLICY-RETURN  ( view workspace status -- status )
    >R 2DROP R> ;

: _ATOG-POLICY  ( view workspace -- grant-status )
    DUP _ATOGW.GRANT O2SESSION-GRANT-CLEAR
    O2SESSION-S-OK <> IF
        2DROP AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN

    2DUP _ATOG-STAGE-ACCESS
    DUP IF _ATOG-POLICY-RETURN EXIT THEN DROP
    2DUP _ATOG-STAGE-TYPE
    DUP IF _ATOG-POLICY-RETURN EXIT THEN DROP
    2DUP _ATOG-STAGE-SCOPE
    DUP IF _ATOG-POLICY-RETURN EXIT THEN DROP
    2DUP _ATOG-CHECK-SUBJECT
    DUP IF _ATOG-POLICY-RETURN EXIT THEN DROP
    2DUP _ATOG-STAGE-REFRESH
    DUP IF _ATOG-POLICY-RETURN EXIT THEN DROP
    2DUP _ATOG-STAGE-EXPIRY
    DUP IF _ATOG-POLICY-RETURN EXIT THEN DROP

    NIP
    DUP _ATOG-CLIENT-CALLBACK-SAFE
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    OVER _ATOGW.CALLBACK-RESULT !
    DROP
    AT-OAUTH-GRANT-S-OK ;

: _ATOG-TOKEN-CALLBACK  ( view workspace -- grant-status )
    _ATOG-POLICY ;

: _ATOG-WIPE-RETURN
  ( callback-result grant-status workspace -- callback-result grant-status )
    >R
    R@ _ATOG-WIPE
    R> DROP ;

: _ATOG-WIPE-FAIL  ( workspace grant-status -- 0 grant-status )
    SWAP >R
    0 SWAP R>
    _ATOG-WIPE-RETURN ;

: _ATOG-WITH-OP
  ( source source-u mode base-ms profile callback context workspace -- callback-result grant-status )
    DUP >R
    R@ _ATOG-WIPE
    5 PICK R@ _ATOGW.MODE !
    4 PICK R@ _ATOGW.BASE-MS !
    3 PICK R@ _ATOGW.PROFILE !
    2 PICK R@ _ATOGW.CALLBACK !
    1 PICK R@ _ATOGW.CONTEXT !

    7 PICK 7 PICK
    ['] _ATOG-TOKEN-CALLBACK R@ R@ _ATOGW.TOKEN-WORK
    OAUTH2-TOKEN-RESPONSE-WITH
    DUP R@ _ATOGW.PARSER-STATUS !
    1 PICK R@ _ATOGW.POLICY-STATUS !
    2DROP
    _ATOG-DROP8
    R>

    DUP _ATOGW.PARSER-STATUS @ _ATOG-PARSER>STATUS
    DUP IF _ATOG-WIPE-FAIL EXIT THEN
    DROP
    DUP _ATOGW.POLICY-STATUS @
    DUP IF _ATOG-WIPE-FAIL EXIT THEN
    DROP
    DUP _ATOGW.CALLBACK-RESULT @
    AT-OAUTH-GRANT-S-OK ROT
    _ATOG-WIPE-RETURN ;

: _ATOG-WITH-CALL
  ( source source-u mode base-ms profile callback context workspace operation-xt -- callback-result grant-status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _ATOG-WIPE
        _ATOG-DROP8
        R> DROP
        0 AT-OAUTH-GRANT-S-INTERNAL EXIT
    THEN
    DROP
    R> DROP ;

: AT-OAUTH-GRANT-WITH
  ( source source-u mode base-ms profile callback context workspace -- callback-result grant-status )
    _ATOG-8DUP _ATOG-WITH-GEOMETRY
    DUP IF
        >R _ATOG-DROP8 0 R> EXIT
    THEN
    DROP
    ['] _ATOG-WITH-OP _ATOG-WITH-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _ATOG-GEOMETRY-ABORT  ( -- )
    ." AT OAuth grant geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _ATOG-GEOMETRY-ABORT
[THEN]

_ATOGW-HEADER-SIZE 7 AND [IF]
    _ATOG-GEOMETRY-ABORT
[THEN]

_ATOGW-GRANT-OFF O2SESSION-GRANT-SIZE +
_ATOGW-TOKEN-WORK-OFF <> [IF]
    _ATOG-GEOMETRY-ABORT
[THEN]

_ATOGW-TOKEN-WORK-OFF OAUTH2-TOKEN-RESPONSE-WORKSPACE-SIZE +
AT-OAUTH-GRANT-WORKSPACE-SIZE <> [IF]
    _ATOG-GEOMETRY-ABORT
[THEN]

AT-OAUTH-GRANT-WORKSPACE-SIZE 35240 <> [IF]
    _ATOG-GEOMETRY-ABORT
[THEN]
