\ =====================================================================
\  get-session-response.f - Exact getSession identity admission
\ =====================================================================
\  This state-free endpoint adapter strictly validates one bounded
\  com.atproto.server.getSession JSON object.  It requires the Lexicon's
\  handle and did strings, decodes and validates both, and accepts only a
\  DID exactly equal to the trusted DID already retained by the ready OAuth
\  profile.  No response pointer or mutable handle survives the call.
\
\  Optional getSession members are completely JSON-validated but are not
\  retained by this narrow identity-binding projection.  Account-status,
\  email, and DID-document presentation policy belongs to a later endpoint
\  projection rather than the authenticated transport.
\ =====================================================================

PROVIDED akashic-at-getsession

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../security/jose/json-object.f
REQUIRE handle.f
REQUIRE did.f
REQUIRE oauth-profile.f

\ =====================================================================
\  Public status vocabulary
\ =====================================================================

0  CONSTANT AT-GETSESSION-S-OK
1  CONSTANT AT-GETSESSION-S-INVALID
2  CONSTANT AT-GETSESSION-S-CAPACITY
3  CONSTANT AT-GETSESSION-S-ALIAS
4  CONSTANT AT-GETSESSION-S-PROFILE
5  CONSTANT AT-GETSESSION-S-JSON
6  CONSTANT AT-GETSESSION-S-MISSING
7  CONSTANT AT-GETSESSION-S-TYPE
8  CONSTANT AT-GETSESSION-S-HANDLE
9  CONSTANT AT-GETSESSION-S-DID
10 CONSTANT AT-GETSESSION-S-BINDING
11 CONSTANT AT-GETSESSION-S-RANGE
12 CONSTANT AT-GETSESSION-S-PROTECTED
13 CONSTANT AT-GETSESSION-S-PLATFORM
14 CONSTANT AT-GETSESSION-S-INTERNAL

: AT-GETSESSION-STATUS-VALID?  ( status -- flag )
    DUP AT-GETSESSION-S-OK >=
    SWAP AT-GETSESSION-S-INTERNAL <= AND ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================

1 CONSTANT _ATGS-P-HANDLE
2 CONSTANT _ATGS-P-DID
3 CONSTANT _ATGS-P-REQUIRED

JOSE-JSON-MAX-MEMBERS CONSTANT _ATGS-MEMBER-CAPACITY
JOSE-JSON-MAX-NAME-BYTES CONSTANT _ATGS-NAMES-CAPACITY

_ATGS-MEMBER-CAPACITY JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." AT getSession descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _ATGS-DESCRIPTOR-SIZE

 0 CONSTANT _ATGSW-SOURCE
 8 CONSTANT _ATGSW-SOURCE-U
16 CONSTANT _ATGSW-PROFILE
24 CONSTANT _ATGSW-NAME-A
32 CONSTANT _ATGSW-NAME-U
40 CONSTANT _ATGSW-VALUE-A
48 CONSTANT _ATGSW-VALUE-U
56 CONSTANT _ATGSW-VALUE-TYPE
64 CONSTANT _ATGSW-PRESENT
72 CONSTANT _ATGSW-SCAN
80 CONSTANT _ATGSW-COUNT
88 CONSTANT _ATGSW-HANDLE-U
96 CONSTANT _ATGSW-DID-U
104 CONSTANT _ATGSW-LENGTH-FIELD
112 CONSTANT _ATGSW-HEADER-SIZE

_ATGSW-HEADER-SIZE CONSTANT _ATGSW-DESCRIPTOR-OFF
_ATGSW-DESCRIPTOR-OFF _ATGS-DESCRIPTOR-SIZE +
    CONSTANT _ATGSW-NAMES-OFF
_ATGSW-NAMES-OFF _ATGS-NAMES-CAPACITY +
    CONSTANT _ATGSW-JSON-OFF
_ATGSW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
    CONSTANT _ATGSW-HANDLE-OFF
_ATGSW-HANDLE-OFF AT-HANDLE-LENGTH-MAX +
    CONSTANT _ATGSW-DID-OFF
_ATGSW-DID-OFF DID-LENGTH-MAX +
7 + -8 AND CONSTANT AT-GETSESSION-WORKSPACE-SIZE

: _ATGSW.SOURCE       ( workspace -- field ) _ATGSW-SOURCE + ;
: _ATGSW.SOURCE-U     ( workspace -- field ) _ATGSW-SOURCE-U + ;
: _ATGSW.PROFILE      ( workspace -- field ) _ATGSW-PROFILE + ;
: _ATGSW.NAME-A       ( workspace -- field ) _ATGSW-NAME-A + ;
: _ATGSW.NAME-U       ( workspace -- field ) _ATGSW-NAME-U + ;
: _ATGSW.VALUE-A      ( workspace -- field ) _ATGSW-VALUE-A + ;
: _ATGSW.VALUE-U      ( workspace -- field ) _ATGSW-VALUE-U + ;
: _ATGSW.VALUE-TYPE   ( workspace -- field ) _ATGSW-VALUE-TYPE + ;
: _ATGSW.PRESENT      ( workspace -- field ) _ATGSW-PRESENT + ;
: _ATGSW.SCAN         ( workspace -- field ) _ATGSW-SCAN + ;
: _ATGSW.COUNT        ( workspace -- field ) _ATGSW-COUNT + ;
: _ATGSW.HANDLE-U     ( workspace -- field ) _ATGSW-HANDLE-U + ;
: _ATGSW.DID-U        ( workspace -- field ) _ATGSW-DID-U + ;
: _ATGSW.LENGTH-FIELD ( workspace -- field ) _ATGSW-LENGTH-FIELD + ;

: _ATGSW.DESCRIPTOR  ( workspace -- address )
    _ATGSW-DESCRIPTOR-OFF + ;
: _ATGSW.NAMES  ( workspace -- address )
    _ATGSW-NAMES-OFF + ;
: _ATGSW.JSON  ( workspace -- address )
    _ATGSW-JSON-OFF + ;
: _ATGSW.HANDLE  ( workspace -- address )
    _ATGSW-HANDLE-OFF + ;
: _ATGSW.DID  ( workspace -- address )
    _ATGSW-DID-OFF + ;

: _ATGS-WIPE  ( workspace -- )
    AT-GETSESSION-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Caller admission and status mapping
\ =====================================================================

: _ATGS-CALLER>STATUS  ( caller-status -- status )
    CASE
        CALLER-SPAN-S-OK OF AT-GETSESSION-S-OK ENDOF
        CALLER-SPAN-S-RANGE OF AT-GETSESSION-S-RANGE ENDOF
        CALLER-SPAN-S-PROTECTED OF
            AT-GETSESSION-S-PROTECTED
        ENDOF
        CALLER-SPAN-S-PLATFORM OF
            AT-GETSESSION-S-PLATFORM
        ENDOF
        AT-GETSESSION-S-PLATFORM SWAP
    ENDCASE ;

: _ATGS-SPAN-STATUS  ( address length -- status )
    DUP 0> 0= IF 2DROP AT-GETSESSION-S-INVALID EXIT THEN
    OVER 0= IF 2DROP AT-GETSESSION-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATGS-CALLER>STATUS ;

: _ATGS-FIXED-STATUS  ( address length -- status )
    OVER 0= IF 2DROP AT-GETSESSION-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP AT-GETSESSION-S-INVALID EXIT THEN
    _ATGS-SPAN-STATUS ;

: _ATGS-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _ATGS-RETURN4  ( x1 x2 x3 x4 status -- status )
    >R _ATGS-DROP4 R> ;

: _ATGS-JSON>STATUS  ( json-status -- status )
    CASE
        JOSE-JSON-S-OK OF AT-GETSESSION-S-OK ENDOF
        JOSE-JSON-S-CAPACITY OF AT-GETSESSION-S-CAPACITY ENDOF
        JOSE-JSON-S-MEMBERS OF AT-GETSESSION-S-CAPACITY ENDOF
        JOSE-JSON-S-STRING OF AT-GETSESSION-S-CAPACITY ENDOF
        JOSE-JSON-S-DOCUMENT OF AT-GETSESSION-S-CAPACITY ENDOF
        JOSE-JSON-S-ALIAS OF AT-GETSESSION-S-ALIAS ENDOF
        JOSE-JSON-S-SYNTAX OF AT-GETSESSION-S-JSON ENDOF
        JOSE-JSON-S-UTF8 OF AT-GETSESSION-S-JSON ENDOF
        JOSE-JSON-S-DEPTH OF AT-GETSESSION-S-JSON ENDOF
        JOSE-JSON-S-DUPLICATE OF AT-GETSESSION-S-JSON ENDOF
        AT-GETSESSION-S-INTERNAL SWAP
    ENDCASE ;

: AT-GETSESSION-WORKSPACE-CLEAR  ( workspace -- status )
    DUP AT-GETSESSION-WORKSPACE-SIZE _ATGS-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _ATGS-WIPE
    AT-GETSESSION-S-OK ;

: _ATGS-GEOMETRY
  ( source source-u profile workspace -- status )
    DUP AT-GETSESSION-WORKSPACE-SIZE _ATGS-FIXED-STATUS
    ?DUP IF _ATGS-RETURN4 EXIT THEN
    3 PICK 3 PICK _ATGS-SPAN-STATUS
    ?DUP IF _ATGS-RETURN4 EXIT THEN
    1 PICK AT-OAUTH-PROFILE-SIZE _ATGS-FIXED-STATUS
    ?DUP IF _ATGS-RETURN4 EXIT THEN
    2 PICK JOSE-JSON-MAX-DOCUMENT-BYTES U> IF
        _ATGS-DROP4 AT-GETSESSION-S-CAPACITY EXIT
    THEN
    3 PICK 3 PICK 2 PICK AT-GETSESSION-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATGS-DROP4 AT-GETSESSION-S-ALIAS EXIT
    THEN
    1 PICK AT-OAUTH-PROFILE-SIZE
    2 PICK AT-GETSESSION-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        _ATGS-DROP4 AT-GETSESSION-S-ALIAS EXIT
    THEN
    _ATGS-DROP4 AT-GETSESSION-S-OK ;

\ =====================================================================
\  Strict member decoding
\ =====================================================================

: _ATGS-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _ATGSW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP AT-GETSESSION-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATGSW.VALUE-TYPE !
    R@ _ATGSW.VALUE-U !
    R@ _ATGSW.SOURCE @ + R@ _ATGSW.VALUE-A !
    R@ _ATGSW.NAME-U !
    R@ _ATGSW.NAMES + R@ _ATGSW.NAME-A !
    R> DROP AT-GETSESSION-S-OK ;

: _ATGS-NAME=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _ATGSW.NAME-A @ R@ _ATGSW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _ATGS-COPY-STRING
  ( destination capacity length-field workspace -- status )
    >R
    R@ _ATGSW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        2DROP DROP R> DROP AT-GETSESSION-S-TYPE EXIT
    THEN
    R@ _ATGSW.LENGTH-FIELD !
    R@ _ATGSW.NAME-U !
    R@ _ATGSW.NAME-A !
    R@ _ATGSW.VALUE-A @ R@ _ATGSW.VALUE-U @
    R@ _ATGSW.NAME-A @ R@ _ATGSW.NAME-U @
    R@ _ATGSW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        _ATGS-JSON>STATUS >R
        DROP R> R> DROP EXIT
    THEN
    DROP
    R@ _ATGSW.LENGTH-FIELD @ !
    R> DROP AT-GETSESSION-S-OK ;

: _ATGS-MARK  ( presence-bit workspace -- status )
    >R
    DUP R@ _ATGSW.PRESENT @ AND IF
        DROP R> DROP AT-GETSESSION-S-JSON EXIT
    THEN
    R@ _ATGSW.PRESENT @ OR R@ _ATGSW.PRESENT !
    R> DROP AT-GETSESSION-S-OK ;

: _ATGS-HANDLE  ( workspace -- status )
    >R
    _ATGS-P-HANDLE R@ _ATGS-MARK ?DUP IF R> DROP EXIT THEN
    R@ _ATGSW.HANDLE AT-HANDLE-LENGTH-MAX
    R@ _ATGSW.HANDLE-U R@ _ATGS-COPY-STRING
    ?DUP IF R> DROP EXIT THEN
    R@ _ATGSW.HANDLE R@ _ATGSW.HANDLE-U @
    AT-HANDLE-VALIDATE
    AT-HANDLE-S-OK =
    IF AT-GETSESSION-S-OK ELSE AT-GETSESSION-S-HANDLE THEN
    R> DROP ;

: _ATGS-DID  ( workspace -- status )
    >R
    _ATGS-P-DID R@ _ATGS-MARK ?DUP IF R> DROP EXIT THEN
    R@ _ATGSW.DID DID-LENGTH-MAX
    R@ _ATGSW.DID-U R@ _ATGS-COPY-STRING
    ?DUP IF R> DROP EXIT THEN
    R@ _ATGSW.DID R@ _ATGSW.DID-U @ DID-VALIDATE
    DID-S-OK =
    IF AT-GETSESSION-S-OK ELSE AT-GETSESSION-S-DID THEN
    R> DROP ;

: _ATGS-PROCESS-MEMBER  ( workspace -- status )
    >R
    S" handle" R@ _ATGS-NAME= IF R> _ATGS-HANDLE EXIT THEN
    S" did" R@ _ATGS-NAME= IF R> _ATGS-DID EXIT THEN
    R> DROP AT-GETSESSION-S-OK ;

: _ATGS-PROCESS-ALL  ( count workspace -- status )
    >R
    R@ _ATGSW.COUNT !
    0 R@ _ATGSW.SCAN !
    BEGIN
        R@ _ATGSW.SCAN @ R@ _ATGSW.COUNT @ U<
    WHILE
        R@ _ATGSW.SCAN @ R@ _ATGS-MEMBER-LOAD
        ?DUP IF R> DROP EXIT THEN
        R@ _ATGS-PROCESS-MEMBER ?DUP IF R> DROP EXIT THEN
        1 R@ _ATGSW.SCAN +!
    REPEAT
    R> DROP AT-GETSESSION-S-OK ;

: _ATGS-BIND-DID  ( workspace -- status )
    >R
    R@ _ATGSW.PROFILE @ AT-OAUTH-PROFILE-DID@
    DUP AT-OAUTH-PROFILE-S-OK <> IF
        >R 2DROP R> DROP R> DROP
        AT-GETSESSION-S-PROFILE EXIT
    THEN
    DROP
    R@ _ATGSW.DID R@ _ATGSW.DID-U @
    COMPARE 0=
    IF AT-GETSESSION-S-OK ELSE AT-GETSESSION-S-BINDING THEN
    R> DROP ;

: _ATGS-PARSE  ( workspace -- status )
    >R
    R@ _ATGSW.SOURCE @ R@ _ATGSW.SOURCE-U @
    R@ _ATGSW.DESCRIPTOR _ATGS-MEMBER-CAPACITY
    R@ _ATGSW.NAMES _ATGS-NAMES-CAPACITY
    R@ _ATGSW.JSON
    JOSE-JSON-OBJECT-PARSE _ATGS-JSON>STATUS
    ?DUP IF R> DROP EXIT THEN
    R@ _ATGSW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP AT-GETSESSION-S-INTERNAL EXIT
    THEN
    DROP
    0 R@ _ATGSW.PRESENT !
    R@ _ATGS-PROCESS-ALL ?DUP IF R> DROP EXIT THEN
    R@ _ATGSW.PRESENT @ _ATGS-P-REQUIRED AND
    _ATGS-P-REQUIRED <> IF
        R> DROP AT-GETSESSION-S-MISSING EXIT
    THEN
    R@ _ATGS-BIND-DID
    R> DROP ;

\ =====================================================================
\  Admitted operation and public entry point
\ =====================================================================

: _ATGS-OP  ( source source-u profile workspace -- status )
    >R
    R@ _ATGS-WIPE
    2 PICK R@ _ATGSW.SOURCE !
    1 PICK R@ _ATGSW.SOURCE-U !
    DUP R@ _ATGSW.PROFILE !
    2DROP DROP
    R@ _ATGSW.PROFILE @ AT-OAUTH-PROFILE-READY? 0= IF
        R> DROP AT-GETSESSION-S-PROFILE EXIT
    THEN
    R@ _ATGS-PARSE
    R> DROP ;

: _ATGS-CALL
  ( source source-u profile workspace operation-xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _ATGS-WIPE
        2DROP 2DROP
        R> DROP AT-GETSESSION-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATGS-WIPE
    R> DROP ;

: AT-GETSESSION-ADMIT
  ( source source-u profile workspace -- status )
    3 PICK 3 PICK 3 PICK 3 PICK _ATGS-GEOMETRY
    ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    ['] _ATGS-OP _ATGS-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

1 CELLS 8 <> [IF]
    ." AT getSession cell geometry mismatch" CR ABORT
[THEN]

_ATGSW-DESCRIPTOR-OFF _ATGS-DESCRIPTOR-SIZE +
_ATGSW-NAMES-OFF <> [IF]
    ." AT getSession descriptor geometry mismatch" CR ABORT
[THEN]

_ATGSW-DID-OFF DID-LENGTH-MAX +
7 + -8 AND AT-GETSESSION-WORKSPACE-SIZE <> [IF]
    ." AT getSession workspace geometry mismatch" CR ABORT
[THEN]
