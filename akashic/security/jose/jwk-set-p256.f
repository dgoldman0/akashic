\ =====================================================================
\  jwk-set-p256.f - Checked homogeneous public P-256 JWK Sets
\ =====================================================================
\  This module is a deliberately strict JOSE selection profile, not a
\  general RFC 7517 key-set implementation.  It accepts one bounded JSON
\  object with a nonempty `keys` array, validates every array member as a
\  public EC/P-256 JWK, and selects exactly one key by decoded `kid`.
\
\  Every key must have a nonempty decoded `kid`, and decoded identifiers
\  must be globally unique.  Optional `use`, `alg`, and `key_ops` metadata
\  is exact when present:
\
\      use     = "sig"
\      alg     = "ES256"
\      key_ops = ["verify"]
\
\  Registered private or symmetric parameters are rejected regardless of
\  value type.  Certificate-reference and time/revocation members are
\  rejected until a layer exists that can acquire or evaluate their policy
\  and prove consistency with the JWK.  Unknown public metadata remains
\  accepted only after complete strict JSON validation.
\
\  The root document is validated before exact candidate spans are
\  recovered.  All spans are collected before per-key parsing so an inner
\  `key_ops` array can never corrupt the outer `keys` cursor.  A selected
\  key never short-circuits validation of later candidates.
\
\  Source and selector bytes are borrowed read-only for the complete call.
\  The selected 65-byte SEC 1 public key and 32-byte RFC 7638 thumbprint are
\  staged in caller-owned workspace and published only after the complete
\  set succeeds.  Returned failures leave both outputs unchanged.  The
\  complete workspace is wiped after every admitted normal or caught exit.
\
\  Public API:
\    JOSE-JWK-SET-P256-PUBLIC-SIZE
\    JOSE-JWK-SET-P256-THUMBPRINT-SIZE
\    JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES
\    JOSE-JWK-SET-P256-MAX-KEYS
\    JOSE-JWK-SET-P256-MAX-MEMBERS
\    JOSE-JWK-SET-P256-KID-CAPACITY
\    JOSE-JWK-SET-P256-WORKSPACE-SIZE
\    JOSE-JWK-SET-P256-STATUS-VALID?  ( status -- flag )
\    JOSE-JWK-SET-P256-WORKSPACE-CLEAR
\      ( workspace -- status )
\    JOSE-JWK-SET-P256-SELECT
\      ( source source-u kid kid-u
\        public-output thumbprint-output workspace -- status )
\ =====================================================================

PROVIDED akashic-jose-jwk-set-p256

REQUIRE ../../utils/memory-span.f
REQUIRE json-object.f
REQUIRE jwk-p256.f

\ =====================================================================
\  Public bounds and status vocabulary
\ =====================================================================

JOSE-JWK-P256-PUBLIC-SIZE
    CONSTANT JOSE-JWK-SET-P256-PUBLIC-SIZE
JOSE-JWK-P256-THUMBPRINT-SIZE
    CONSTANT JOSE-JWK-SET-P256-THUMBPRINT-SIZE
JOSE-JSON-MAX-DOCUMENT-BYTES
    CONSTANT JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES

32  CONSTANT JOSE-JWK-SET-P256-MAX-KEYS
32  CONSTANT JOSE-JWK-SET-P256-MAX-MEMBERS
256 CONSTANT JOSE-JWK-SET-P256-KID-CAPACITY

0  CONSTANT JOSE-JWK-SET-P256-S-OK
1  CONSTANT JOSE-JWK-SET-P256-S-INVALID
2  CONSTANT JOSE-JWK-SET-P256-S-CAPACITY
3  CONSTANT JOSE-JWK-SET-P256-S-ALIAS
4  CONSTANT JOSE-JWK-SET-P256-S-JSON
5  CONSTANT JOSE-JWK-SET-P256-S-MISSING
6  CONSTANT JOSE-JWK-SET-P256-S-TYPE
7  CONSTANT JOSE-JWK-SET-P256-S-EMPTY
8  CONSTANT JOSE-JWK-SET-P256-S-SENSITIVE
9  CONSTANT JOSE-JWK-SET-P256-S-UNSUPPORTED
10 CONSTANT JOSE-JWK-SET-P256-S-KEY
11 CONSTANT JOSE-JWK-SET-P256-S-DUPLICATE
12 CONSTANT JOSE-JWK-SET-P256-S-USE
13 CONSTANT JOSE-JWK-SET-P256-S-ALGORITHM
14 CONSTANT JOSE-JWK-SET-P256-S-KEY-OPS
15 CONSTANT JOSE-JWK-SET-P256-S-NOT-FOUND
16 CONSTANT JOSE-JWK-SET-P256-S-CRYPTO
17 CONSTANT JOSE-JWK-SET-P256-S-INTERNAL
18 CONSTANT JOSE-JWK-SET-P256-S-RANGE
19 CONSTANT JOSE-JWK-SET-P256-S-PROTECTED
20 CONSTANT JOSE-JWK-SET-P256-S-PLATFORM

: JOSE-JWK-SET-P256-STATUS-VALID?  ( status -- flag )
    DUP JOSE-JWK-SET-P256-S-OK >=
    SWAP JOSE-JWK-SET-P256-S-PLATFORM <= AND ;

JOSE-JWK-SET-P256-MAX-MEMBERS JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." JOSE P-256 JWK Set descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _JJKS-DESCRIPTOR-SIZE

32 CONSTANT _JJKS-CANDIDATE-ENTRY-SIZE
 0 CONSTANT _JJKSE-TOKEN-OFFSET
 8 CONSTANT _JJKSE-TOKEN-U
16 CONSTANT _JJKSE-KID-OFFSET
24 CONSTANT _JJKSE-KID-U

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================
\  The 39,528-byte layout is fixed and contains no module-owned operation
\  state.  Candidate entries first retain source-relative object spans and
\  later receive offsets into the decoded-kid arena.

  0 CONSTANT _JJKSW-SOURCE
  8 CONSTANT _JJKSW-SOURCE-U
 16 CONSTANT _JJKSW-SELECTOR
 24 CONSTANT _JJKSW-SELECTOR-U
 32 CONSTANT _JJKSW-PUBLIC-OUTPUT
 40 CONSTANT _JJKSW-THUMBPRINT-OUTPUT
 48 CONSTANT _JJKSW-ARRAY-A
 56 CONSTANT _JJKSW-ARRAY-U
 64 CONSTANT _JJKSW-ARRAY-POS
 72 CONSTANT _JJKSW-TOKEN-START
 80 CONSTANT _JJKSW-TOKEN-U
 88 CONSTANT _JJKSW-TOKEN-TYPE
 96 CONSTANT _JJKSW-SCAN-DEPTH
104 CONSTANT _JJKSW-SCAN-STRING
112 CONSTANT _JJKSW-SCAN-ESCAPE
120 CONSTANT _JJKSW-KEY-COUNT
128 CONSTANT _JJKSW-CURRENT-INDEX
136 CONSTANT _JJKSW-NAME-A
144 CONSTANT _JJKSW-NAME-U
152 CONSTANT _JJKSW-VALUE-A
160 CONSTANT _JJKSW-VALUE-U
168 CONSTANT _JJKSW-VALUE-TYPE
176 CONSTANT _JJKSW-DECODED-U
184 CONSTANT _JJKSW-MATCH-COUNT
192 CONSTANT _JJKSW-OBJECT-A
200 CONSTANT _JJKSW-OBJECT-U
208 CONSTANT _JJKSW-RESERVED0
216 CONSTANT _JJKSW-RESERVED1
224 CONSTANT _JJKSW-RESERVED2
232 CONSTANT _JJKSW-RESERVED3
240 CONSTANT _JJKSW-RESERVED4
248 CONSTANT _JJKSW-RESERVED5

256 CONSTANT _JJKSW-DESCRIPTOR-OFF
_JJKSW-DESCRIPTOR-OFF _JJKS-DESCRIPTOR-SIZE +
    CONSTANT _JJKSW-NAMES-OFF
_JJKSW-NAMES-OFF JOSE-JSON-MAX-NAME-BYTES +
    CONSTANT _JJKSW-JSON-OFF
_JJKSW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
    CONSTANT _JJKSW-CANDIDATES-OFF
_JJKSW-CANDIDATES-OFF
    JOSE-JWK-SET-P256-MAX-KEYS _JJKS-CANDIDATE-ENTRY-SIZE * +
    CONSTANT _JJKSW-KID-BYTES-OFF
_JJKSW-KID-BYTES-OFF
    JOSE-JWK-SET-P256-MAX-KEYS
    JOSE-JWK-SET-P256-KID-CAPACITY * +
    CONSTANT _JJKSW-SCRATCH-OFF
_JJKSW-SCRATCH-OFF JOSE-JWK-SET-P256-KID-CAPACITY +
    CONSTANT _JJKSW-JWK-OFF
_JJKSW-JWK-OFF JOSE-JWK-P256-WORKSPACE-SIZE +
    CONSTANT _JJKSW-CURRENT-PUBLIC-OFF
_JJKSW-CURRENT-PUBLIC-OFF JOSE-JWK-SET-P256-PUBLIC-SIZE +
    CONSTANT _JJKSW-SELECTED-PUBLIC-OFF
_JJKSW-SELECTED-PUBLIC-OFF JOSE-JWK-SET-P256-PUBLIC-SIZE +
    7 + -8 AND
    CONSTANT _JJKSW-SELECTED-THUMBPRINT-OFF
_JJKSW-SELECTED-THUMBPRINT-OFF
    JOSE-JWK-SET-P256-THUMBPRINT-SIZE +
    CONSTANT JOSE-JWK-SET-P256-WORKSPACE-SIZE

JOSE-JWK-SET-P256-WORKSPACE-SIZE 39528 <> [IF]
    ." JOSE P-256 JWK Set workspace geometry changed" CR ABORT
[THEN]

_JJKSW-DESCRIPTOR-OFF 7 AND [IF]
    ." JOSE P-256 JWK Set descriptor is not cell aligned" CR ABORT
[THEN]
_JJKSW-CANDIDATES-OFF 7 AND [IF]
    ." JOSE P-256 JWK Set candidates are not cell aligned" CR ABORT
[THEN]
_JJKSW-JWK-OFF 7 AND [IF]
    ." JOSE P-256 JWK Set child workspace is not cell aligned" CR ABORT
[THEN]

: _JJKSW.SOURCE             ( w -- a ) _JJKSW-SOURCE + ;
: _JJKSW.SOURCE-U           ( w -- a ) _JJKSW-SOURCE-U + ;
: _JJKSW.SELECTOR           ( w -- a ) _JJKSW-SELECTOR + ;
: _JJKSW.SELECTOR-U         ( w -- a ) _JJKSW-SELECTOR-U + ;
: _JJKSW.PUBLIC-OUTPUT      ( w -- a ) _JJKSW-PUBLIC-OUTPUT + ;
: _JJKSW.THUMBPRINT-OUTPUT  ( w -- a ) _JJKSW-THUMBPRINT-OUTPUT + ;
: _JJKSW.ARRAY-A            ( w -- a ) _JJKSW-ARRAY-A + ;
: _JJKSW.ARRAY-U            ( w -- a ) _JJKSW-ARRAY-U + ;
: _JJKSW.ARRAY-POS          ( w -- a ) _JJKSW-ARRAY-POS + ;
: _JJKSW.TOKEN-START        ( w -- a ) _JJKSW-TOKEN-START + ;
: _JJKSW.TOKEN-U            ( w -- a ) _JJKSW-TOKEN-U + ;
: _JJKSW.TOKEN-TYPE         ( w -- a ) _JJKSW-TOKEN-TYPE + ;
: _JJKSW.SCAN-DEPTH         ( w -- a ) _JJKSW-SCAN-DEPTH + ;
: _JJKSW.SCAN-STRING        ( w -- a ) _JJKSW-SCAN-STRING + ;
: _JJKSW.SCAN-ESCAPE        ( w -- a ) _JJKSW-SCAN-ESCAPE + ;
: _JJKSW.KEY-COUNT          ( w -- a ) _JJKSW-KEY-COUNT + ;
: _JJKSW.CURRENT-INDEX      ( w -- a ) _JJKSW-CURRENT-INDEX + ;
: _JJKSW.NAME-A             ( w -- a ) _JJKSW-NAME-A + ;
: _JJKSW.NAME-U             ( w -- a ) _JJKSW-NAME-U + ;
: _JJKSW.VALUE-A            ( w -- a ) _JJKSW-VALUE-A + ;
: _JJKSW.VALUE-U            ( w -- a ) _JJKSW-VALUE-U + ;
: _JJKSW.VALUE-TYPE         ( w -- a ) _JJKSW-VALUE-TYPE + ;
: _JJKSW.DECODED-U          ( w -- a ) _JJKSW-DECODED-U + ;
: _JJKSW.MATCH-COUNT        ( w -- a ) _JJKSW-MATCH-COUNT + ;
: _JJKSW.OBJECT-A           ( w -- a ) _JJKSW-OBJECT-A + ;
: _JJKSW.OBJECT-U           ( w -- a ) _JJKSW-OBJECT-U + ;

: _JJKSW.DESCRIPTOR  ( w -- a ) _JJKSW-DESCRIPTOR-OFF + ;
: _JJKSW.NAMES       ( w -- a ) _JJKSW-NAMES-OFF + ;
: _JJKSW.JSON        ( w -- a ) _JJKSW-JSON-OFF + ;
: _JJKSW.CANDIDATES  ( w -- a ) _JJKSW-CANDIDATES-OFF + ;
: _JJKSW.KID-BYTES   ( w -- a ) _JJKSW-KID-BYTES-OFF + ;
: _JJKSW.SCRATCH     ( w -- a ) _JJKSW-SCRATCH-OFF + ;
: _JJKSW.JWK         ( w -- a ) _JJKSW-JWK-OFF + ;
: _JJKSW.CURRENT-PUBLIC
  ( w -- a ) _JJKSW-CURRENT-PUBLIC-OFF + ;
: _JJKSW.SELECTED-PUBLIC
  ( w -- a ) _JJKSW-SELECTED-PUBLIC-OFF + ;
: _JJKSW.SELECTED-THUMBPRINT
  ( w -- a ) _JJKSW-SELECTED-THUMBPRINT-OFF + ;

: _JJKS-CANDIDATE  ( index workspace -- entry )
    _JJKSW.CANDIDATES
    SWAP _JJKS-CANDIDATE-ENTRY-SIZE * + ;

: _JJKS-WIPE  ( workspace -- )
    JOSE-JWK-SET-P256-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Caller geometry and mandatory cleanup
\ =====================================================================

: _JJKS-JWK-SPAN>STATUS  ( jwk-status -- status )
    DUP JOSE-JWK-P256-S-OK = IF
        DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    DUP JOSE-JWK-P256-S-INVALID = IF
        DROP JOSE-JWK-SET-P256-S-INVALID EXIT
    THEN
    DUP JOSE-JWK-P256-S-ALIAS = IF
        DROP JOSE-JWK-SET-P256-S-ALIAS EXIT
    THEN
    DUP JOSE-JWK-P256-S-CRYPTO = IF
        DROP JOSE-JWK-SET-P256-S-CRYPTO EXIT
    THEN
    DUP JOSE-JWK-P256-S-RANGE = IF
        DROP JOSE-JWK-SET-P256-S-RANGE EXIT
    THEN
    DUP JOSE-JWK-P256-S-PROTECTED = IF
        DROP JOSE-JWK-SET-P256-S-PROTECTED EXIT
    THEN
    DUP JOSE-JWK-P256-S-PLATFORM = IF
        DROP JOSE-JWK-SET-P256-S-PLATFORM EXIT
    THEN
    DROP JOSE-JWK-SET-P256-S-PLATFORM ;

: _JJKS-ADMIT-SPAN  ( address length -- status )
    JOSE-JWK-P256-CALLER-SPAN-STATUS
    _JJKS-JWK-SPAN>STATUS ;

: _JJKS-SPAN-STATUS  ( address length -- status )
    DUP 0< IF
        2DROP JOSE-JWK-SET-P256-S-INVALID EXIT
    THEN
    DUP 0= IF
        2DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    OVER 0= IF
        2DROP JOSE-JWK-SET-P256-S-INVALID EXIT
    THEN
    _JJKS-ADMIT-SPAN ;

: _JJKS-FIXED-STATUS  ( address length -- status )
    OVER 0= IF
        2DROP JOSE-JWK-SET-P256-S-INVALID EXIT
    THEN
    OVER 7 AND IF
        2DROP JOSE-JWK-SET-P256-S-INVALID EXIT
    THEN
    _JJKS-SPAN-STATUS ;

: _JJKS-DROP6  ( six-values -- )
    2DROP 2DROP 2DROP ;

: _JJKS-DROP7  ( seven-values -- )
    2DROP 2DROP 2DROP DROP ;

: _JJKS-7DUP  ( seven-values -- the-same-seven-values twice )
    6 PICK 6 PICK 6 PICK 6 PICK
    6 PICK 6 PICK 6 PICK ;

: _JJKS-RETURN7  ( seven-values status -- status )
    >R _JJKS-DROP7 R> ;

: _JJKS-SELECT-GEOMETRY
  ( source source-u selector selector-u public-output thumbprint-output workspace -- status )
    DUP JOSE-JWK-SET-P256-WORKSPACE-SIZE _JJKS-FIXED-STATUS
    ?DUP IF _JJKS-RETURN7 EXIT THEN

    6 PICK 6 PICK _JJKS-SPAN-STATUS
    ?DUP IF _JJKS-RETURN7 EXIT THEN
    5 PICK 0> 0= IF
        JOSE-JWK-SET-P256-S-INVALID _JJKS-RETURN7 EXIT
    THEN
    5 PICK JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES U> IF
        JOSE-JWK-SET-P256-S-CAPACITY _JJKS-RETURN7 EXIT
    THEN

    4 PICK 4 PICK _JJKS-SPAN-STATUS
    ?DUP IF _JJKS-RETURN7 EXIT THEN
    3 PICK 0> 0= IF
        JOSE-JWK-SET-P256-S-INVALID _JJKS-RETURN7 EXIT
    THEN
    3 PICK JOSE-JWK-SET-P256-KID-CAPACITY U> IF
        JOSE-JWK-SET-P256-S-CAPACITY _JJKS-RETURN7 EXIT
    THEN

    2 PICK JOSE-JWK-SET-P256-PUBLIC-SIZE _JJKS-SPAN-STATUS
    ?DUP IF _JJKS-RETURN7 EXIT THEN
    1 PICK JOSE-JWK-SET-P256-THUMBPRINT-SIZE _JJKS-SPAN-STATUS
    ?DUP IF _JJKS-RETURN7 EXIT THEN

    \ Borrowed inputs may overlap each other, but no input may overlap
    \ either output or mutable workspace.
    6 PICK 6 PICK
    4 PICK JOSE-JWK-SET-P256-PUBLIC-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN
    6 PICK 6 PICK
    3 PICK JOSE-JWK-SET-P256-THUMBPRINT-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN
    6 PICK 6 PICK
    2 PICK JOSE-JWK-SET-P256-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN

    4 PICK 4 PICK
    4 PICK JOSE-JWK-SET-P256-PUBLIC-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN
    4 PICK 4 PICK
    3 PICK JOSE-JWK-SET-P256-THUMBPRINT-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN
    4 PICK 4 PICK
    2 PICK JOSE-JWK-SET-P256-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN

    2 PICK JOSE-JWK-SET-P256-PUBLIC-SIZE
    3 PICK JOSE-JWK-SET-P256-THUMBPRINT-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN
    2 PICK JOSE-JWK-SET-P256-PUBLIC-SIZE
    2 PICK JOSE-JWK-SET-P256-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN
    1 PICK JOSE-JWK-SET-P256-THUMBPRINT-SIZE
    2 PICK JOSE-JWK-SET-P256-WORKSPACE-SIZE
    MSPAN-OVERLAP? IF
        JOSE-JWK-SET-P256-S-ALIAS _JJKS-RETURN7 EXIT
    THEN

    JOSE-JWK-SET-P256-S-OK _JJKS-RETURN7 ;

: JOSE-JWK-SET-P256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP JOSE-JWK-SET-P256-WORKSPACE-SIZE _JJKS-FIXED-STATUS
    ?DUP IF NIP EXIT THEN
    _JJKS-WIPE
    JOSE-JWK-SET-P256-S-OK ;

\ An operation/publication THROW is rethrown after successful cleanup.
\ Cleanup THROW propagates directly and therefore has precedence.
: _JJKS-CALL-FINALLY
  ( workspace operation-xt cleanup-xt -- results... )
    >R
    OVER >R
    CATCH
    DUP IF
        >R DROP
        R> R> R> EXECUTE
        THROW
    THEN
    DROP
    R> R> EXECUTE ;

\ =====================================================================
\  Strict JSON object helpers
\ =====================================================================

: _JJKS-JSON>STATUS  ( json-status -- status )
    DUP JOSE-JSON-S-OK = IF
        DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    DUP JOSE-JSON-S-CAPACITY =
    OVER JOSE-JSON-S-DEPTH = OR
    OVER JOSE-JSON-S-MEMBERS = OR
    OVER JOSE-JSON-S-STRING = OR
    OVER JOSE-JSON-S-DOCUMENT = OR IF
        DROP JOSE-JWK-SET-P256-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-INVALID =
    OVER JOSE-JSON-S-ALIAS = OR
    OVER JOSE-JSON-S-INTERNAL = OR IF
        DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    DROP JOSE-JWK-SET-P256-S-JSON ;

: _JJKS-OBJECT-PARSE  ( source source-u workspace -- status )
    >R
    OVER R@ _JJKSW.OBJECT-A !
    DUP R@ _JJKSW.OBJECT-U !
    R@ _JJKSW.DESCRIPTOR
    JOSE-JWK-SET-P256-MAX-MEMBERS
    R@ _JJKSW.NAMES
    JOSE-JSON-MAX-NAME-BYTES
    R@ _JJKSW.JSON
    JOSE-JSON-OBJECT-PARSE
    _JJKS-JSON>STATUS
    R> DROP ;

: _JJKS-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _JJKSW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    DROP
    R@ _JJKSW.VALUE-TYPE !
    R@ _JJKSW.VALUE-U !
    R@ _JJKSW.OBJECT-A @ +
        R@ _JJKSW.VALUE-A !
    R@ _JJKSW.NAME-U !
    R@ _JJKSW.NAMES +
        R@ _JJKSW.NAME-A !
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-NAME=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _JJKSW.NAME-A @ R@ _JJKSW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _JJKS-FIND-MEMBER
  ( expected-a expected-u workspace -- found status )
    >R
    R@ _JJKSW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP R> DROP
        0 JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    DROP
    0 SWAP
    BEGIN
        2DUP <
    WHILE
        OVER R@ _JJKS-MEMBER-LOAD
        DUP IF
            >R 2DROP 2DROP R> R> DROP
            0 SWAP EXIT
        THEN
        DROP
        3 PICK 3 PICK R@ _JJKS-NAME= IF
            2DROP 2DROP R> DROP
            -1 JOSE-JWK-SET-P256-S-OK EXIT
        THEN
        SWAP 1+ SWAP
    REPEAT
    2DROP 2DROP R> DROP
    0 JOSE-JWK-SET-P256-S-OK ;

: _JJKS-DECODE-SPAN  ( source source-u workspace -- status )
    >R
    R@ _JJKSW.SCRATCH
    JOSE-JWK-SET-P256-KID-CAPACITY
    R@ _JJKSW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        >R DROP R> _JJKS-JSON>STATUS
        R> DROP EXIT
    THEN
    DROP
    R@ _JJKSW.DECODED-U !
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-DECODE-CURRENT  ( workspace -- status )
    >R
    R@ _JJKSW.VALUE-A @ R@ _JJKSW.VALUE-U @
    R@ _JJKS-DECODE-SPAN
    R> DROP ;

: _JJKS-SCRATCH=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _JJKSW.SCRATCH R@ _JJKSW.DECODED-U @
    2SWAP COMPARE 0=
    R> DROP ;

\ =====================================================================
\  Exact already-validated array token recovery
\ =====================================================================

: _JJKS-JSON-WS?  ( byte -- flag )
    DUP 32 = IF DROP -1 EXIT THEN
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 10 = IF DROP -1 EXIT THEN
    13 = ;

: _JJKS-ARRAY-C@  ( position workspace -- byte )
    DUP _JJKSW.ARRAY-A @ ROT + C@ SWAP DROP ;

: _JJKS-ARRAY-SKIP-WS  ( workspace -- )
    BEGIN
        DUP _JJKSW.ARRAY-POS @
        OVER _JJKSW.ARRAY-U @ U<
    WHILE
        DUP _JJKSW.ARRAY-POS @ OVER _JJKS-ARRAY-C@
        _JJKS-JSON-WS? 0= IF DROP EXIT THEN
        1 OVER _JJKSW.ARRAY-POS +!
    REPEAT
    DROP ;

: _JJKS-ARRAY-BIND  ( address length workspace -- status )
    >R
    DUP 2 U< IF
        2DROP R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    OVER C@ [CHAR] [ <> IF
        2DROP R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    2DUP + 1- C@ [CHAR] ] <> IF
        2DROP R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    R@ _JJKSW.ARRAY-U !
    R@ _JJKSW.ARRAY-A !
    1 R@ _JJKSW.ARRAY-POS !
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-SCAN-STRING  ( workspace -- status )
    >R
    1 R@ _JJKSW.ARRAY-POS +!
    BEGIN
        R@ _JJKSW.ARRAY-POS @ R@ _JJKSW.ARRAY-U @ U<
    WHILE
        R@ _JJKSW.ARRAY-POS @ R@ _JJKS-ARRAY-C@
        DUP 34 = IF
            DROP
            1 R@ _JJKSW.ARRAY-POS +!
            R> DROP JOSE-JWK-SET-P256-S-OK EXIT
        THEN
        92 = IF
            1 R@ _JJKSW.ARRAY-POS +!
            R@ _JJKSW.ARRAY-POS @
            R@ _JJKSW.ARRAY-U @ U< 0= IF
                R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
            THEN
        THEN
        1 R@ _JJKSW.ARRAY-POS +!
    REPEAT
    R> DROP JOSE-JWK-SET-P256-S-INTERNAL ;

: _JJKS-SCAN-CONTAINER  ( workspace -- status )
    >R
    0 R@ _JJKSW.SCAN-DEPTH !
    0 R@ _JJKSW.SCAN-STRING !
    0 R@ _JJKSW.SCAN-ESCAPE !
    BEGIN
        R@ _JJKSW.ARRAY-POS @ R@ _JJKSW.ARRAY-U @ U<
    WHILE
        R@ _JJKSW.ARRAY-POS @ R@ _JJKS-ARRAY-C@
        R@ _JJKSW.SCAN-STRING @ IF
            R@ _JJKSW.SCAN-ESCAPE @ IF
                DROP 0 R@ _JJKSW.SCAN-ESCAPE !
            ELSE
                DUP 92 = IF
                    DROP -1 R@ _JJKSW.SCAN-ESCAPE !
                ELSE
                    34 = IF
                        0 R@ _JJKSW.SCAN-STRING !
                    THEN
                THEN
            THEN
        ELSE
            DUP 34 = IF
                DROP -1 R@ _JJKSW.SCAN-STRING !
            ELSE
                DUP [CHAR] { = OVER [CHAR] [ = OR IF
                    DROP 1 R@ _JJKSW.SCAN-DEPTH +!
                ELSE
                    DUP [CHAR] } = SWAP [CHAR] ] = OR IF
                        -1 R@ _JJKSW.SCAN-DEPTH +!
                    THEN
                THEN
            THEN
        THEN
        1 R@ _JJKSW.ARRAY-POS +!
        R@ _JJKSW.SCAN-DEPTH @ 0= IF
            R> DROP JOSE-JWK-SET-P256-S-OK EXIT
        THEN
    REPEAT
    R> DROP JOSE-JWK-SET-P256-S-INTERNAL ;

: _JJKS-SCAN-SCALAR  ( workspace -- status )
    >R
    BEGIN
        R@ _JJKSW.ARRAY-POS @ R@ _JJKSW.ARRAY-U @ U<
    WHILE
        R@ _JJKSW.ARRAY-POS @ R@ _JJKS-ARRAY-C@
        DUP [CHAR] , = OVER [CHAR] ] = OR
        OVER _JJKS-JSON-WS? OR IF
            DROP R> DROP JOSE-JWK-SET-P256-S-OK EXIT
        THEN
        DROP
        1 R@ _JJKSW.ARRAY-POS +!
    REPEAT
    R> DROP JOSE-JWK-SET-P256-S-INTERNAL ;

: _JJKS-TOKEN-TYPE!  ( first-byte workspace -- )
    >R
    DUP 34 = IF
        DROP JOSE-JSON-T-STRING R@ _JJKSW.TOKEN-TYPE !
        R> DROP EXIT
    THEN
    DUP [CHAR] { = IF
        DROP JOSE-JSON-T-OBJECT R@ _JJKSW.TOKEN-TYPE !
        R> DROP EXIT
    THEN
    DUP [CHAR] [ = IF
        DROP JOSE-JSON-T-ARRAY R@ _JJKSW.TOKEN-TYPE !
        R> DROP EXIT
    THEN
    DROP 0 R@ _JJKSW.TOKEN-TYPE !
    R> DROP ;

: _JJKS-ARRAY-NEXT  ( workspace -- has-token status )
    >R
    R@ _JJKS-ARRAY-SKIP-WS
    R@ _JJKSW.ARRAY-POS @ R@ _JJKSW.ARRAY-U @ U< 0= IF
        R> DROP 0 JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    R@ _JJKSW.ARRAY-POS @ R@ _JJKSW.ARRAY-U @ 1- = IF
        R@ _JJKSW.ARRAY-POS @ R@ _JJKS-ARRAY-C@
        [CHAR] ] <> IF
            R> DROP 0 JOSE-JWK-SET-P256-S-INTERNAL EXIT
        THEN
        R@ _JJKSW.ARRAY-U @ R@ _JJKSW.ARRAY-POS !
        R> DROP 0 JOSE-JWK-SET-P256-S-OK EXIT
    THEN

    R@ _JJKSW.ARRAY-POS @ DUP R@ _JJKSW.TOKEN-START !
    R@ _JJKS-ARRAY-C@ DUP R@ _JJKS-TOKEN-TYPE!
    DUP 34 = IF
        DROP R@ _JJKS-SCAN-STRING
    ELSE
        DUP [CHAR] { = OVER [CHAR] [ = OR IF
            DROP R@ _JJKS-SCAN-CONTAINER
        ELSE
            DROP R@ _JJKS-SCAN-SCALAR
        THEN
    THEN
    DUP IF R> DROP 0 SWAP EXIT THEN
    DROP

    R@ _JJKSW.ARRAY-POS @ R@ _JJKSW.TOKEN-START @ -
        R@ _JJKSW.TOKEN-U !
    R@ _JJKS-ARRAY-SKIP-WS
    R@ _JJKSW.ARRAY-POS @ R@ _JJKSW.ARRAY-U @ U< 0= IF
        R> DROP 0 JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    R@ _JJKSW.ARRAY-POS @ R@ _JJKS-ARRAY-C@
    DUP [CHAR] , = IF
        DROP 1 R@ _JJKSW.ARRAY-POS +!
    ELSE
        [CHAR] ] <> IF
            R> DROP 0 JOSE-JWK-SET-P256-S-INTERNAL EXIT
        THEN
    THEN
    R> DROP -1 JOSE-JWK-SET-P256-S-OK ;

\ =====================================================================
\  Root envelope and candidate-span collection
\ =====================================================================

: _JJKS-COLLECT-CANDIDATES  ( workspace -- status )
    >R
    R@ _JJKSW.VALUE-A @ R@ _JJKSW.VALUE-U @ R@
    _JJKS-ARRAY-BIND
    DUP IF R> DROP EXIT THEN
    DROP
    0 R@ _JJKSW.KEY-COUNT !

    BEGIN
        R@ _JJKS-ARRAY-NEXT
        DUP IF
            NIP R> DROP EXIT
        THEN
        DROP
        DUP 0= IF
            DROP
            R@ _JJKSW.KEY-COUNT @ 0= IF
                R> DROP JOSE-JWK-SET-P256-S-EMPTY EXIT
            THEN
            R> DROP JOSE-JWK-SET-P256-S-OK EXIT
        THEN
        DROP

        R@ _JJKSW.TOKEN-TYPE @ JOSE-JSON-T-OBJECT <> IF
            R> DROP JOSE-JWK-SET-P256-S-TYPE EXIT
        THEN
        R@ _JJKSW.KEY-COUNT @
        JOSE-JWK-SET-P256-MAX-KEYS >= IF
            R> DROP JOSE-JWK-SET-P256-S-CAPACITY EXIT
        THEN

        R@ _JJKSW.KEY-COUNT @ R@ _JJKS-CANDIDATE
        R@ _JJKSW.ARRAY-A @ R@ _JJKSW.TOKEN-START @ +
        R@ _JJKSW.SOURCE @ -
        OVER _JJKSE-TOKEN-OFFSET + !
        R@ _JJKSW.TOKEN-U @
        SWAP _JJKSE-TOKEN-U + !
        1 R@ _JJKSW.KEY-COUNT +!
    AGAIN ;

: _JJKS-ROOT-STAGE  ( workspace -- status )
    >R
    R@ _JJKSW.SOURCE @ R@ _JJKSW.SOURCE-U @ R@
    _JJKS-OBJECT-PARSE
    DUP IF R> DROP EXIT THEN
    DROP

    S" keys" R@ _JJKS-FIND-MEMBER
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    0= IF
        R> DROP JOSE-JWK-SET-P256-S-MISSING EXIT
    THEN
    R@ _JJKSW.VALUE-TYPE @ JOSE-JSON-T-ARRAY <> IF
        R> DROP JOSE-JWK-SET-P256-S-TYPE EXIT
    THEN
    R@ _JJKS-COLLECT-CANDIDATES
    R> DROP ;

\ =====================================================================
\  Per-key policy
\ =====================================================================

: _JJKS-SENSITIVE-NAME?  ( workspace -- flag )
    >R
    S" d" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" k" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" p" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" q" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" dp" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" dq" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" qi" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" oth" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" priv" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    R> DROP 0 ;

: _JJKS-UNSUPPORTED-NAME?  ( workspace -- flag )
    >R
    S" x5u" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" x5c" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" x5t" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" x5t#S256" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" nbf" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" exp" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    S" revoked" R@ _JJKS-NAME= IF R> DROP -1 EXIT THEN
    R> DROP 0 ;

: _JJKS-CHECK-SENSITIVE  ( workspace -- status )
    >R
    R@ _JJKSW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    DROP
    0 SWAP
    BEGIN
        2DUP <
    WHILE
        OVER R@ _JJKS-MEMBER-LOAD
        DUP IF
            >R 2DROP R> R> DROP EXIT
        THEN
        DROP
        R@ _JJKS-SENSITIVE-NAME? IF
            2DROP R> DROP
            JOSE-JWK-SET-P256-S-SENSITIVE EXIT
        THEN
        SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-CHECK-UNSUPPORTED  ( workspace -- status )
    >R
    R@ _JJKSW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    DROP
    0 SWAP
    BEGIN
        2DUP <
    WHILE
        OVER R@ _JJKS-MEMBER-LOAD
        DUP IF
            >R 2DROP R> R> DROP EXIT
        THEN
        DROP
        R@ _JJKS-UNSUPPORTED-NAME? IF
            2DROP R> DROP
            JOSE-JWK-SET-P256-S-UNSUPPORTED EXIT
        THEN
        SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-CURRENT-CANDIDATE  ( workspace -- source source-u )
    >R
    R@ _JJKSW.CURRENT-INDEX @ R@ _JJKS-CANDIDATE
    DUP _JJKSE-TOKEN-OFFSET + @ R@ _JJKSW.SOURCE @ +
    SWAP _JJKSE-TOKEN-U + @
    R> DROP ;

: _JJKS-JWK-PARSE>STATUS  ( jwk-status -- status )
    DUP JOSE-JWK-P256-S-OK = IF
        DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    DUP JOSE-JWK-P256-S-RANGE = IF
        DROP JOSE-JWK-SET-P256-S-RANGE EXIT
    THEN
    DUP JOSE-JWK-P256-S-PROTECTED = IF
        DROP JOSE-JWK-SET-P256-S-PROTECTED EXIT
    THEN
    DUP JOSE-JWK-P256-S-PLATFORM = IF
        DROP JOSE-JWK-SET-P256-S-PLATFORM EXIT
    THEN
    DUP JOSE-JWK-P256-S-ALIAS =
    OVER JOSE-JWK-P256-S-INTERNAL = OR
    OVER JOSE-JWK-P256-S-CRYPTO = OR IF
        DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    DROP JOSE-JWK-SET-P256-S-KEY ;

: _JJKS-VALIDATE-PUBLIC  ( workspace -- status )
    >R
    R@ _JJKS-CURRENT-CANDIDATE
    R@ _JJKSW.CURRENT-PUBLIC
    R@ _JJKSW.JWK
    JOSE-JWK-P256-PUBLIC-PARSE
    _JJKS-JWK-PARSE>STATUS
    R> DROP ;

: _JJKS-ENTRY-KID@  ( index workspace -- address length )
    >R
    R@ _JJKS-CANDIDATE
    DUP _JJKSE-KID-OFFSET + @ R@ _JJKSW.KID-BYTES +
    SWAP _JJKSE-KID-U + @
    R> DROP ;

: _JJKS-KID-DUPLICATE?  ( workspace -- flag )
    >R
    0 R@ _JJKSW.CURRENT-INDEX @
    BEGIN
        2DUP <
    WHILE
        OVER R@ _JJKS-ENTRY-KID@
        R@ _JJKSW.SCRATCH R@ _JJKSW.DECODED-U @
        2SWAP COMPARE 0= IF
            2DROP R> DROP -1 EXIT
        THEN
        SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP 0 ;

: _JJKS-STORE-KID  ( workspace -- )
    >R
    R@ _JJKSW.CURRENT-INDEX @
    JOSE-JWK-SET-P256-KID-CAPACITY *
    DUP
    R@ _JJKSW.CURRENT-INDEX @ R@ _JJKS-CANDIDATE
    _JJKSE-KID-OFFSET + !
    R@ _JJKSW.DECODED-U @
    R@ _JJKSW.CURRENT-INDEX @ R@ _JJKS-CANDIDATE
    _JJKSE-KID-U + !
    R@ _JJKSW.SCRATCH
    SWAP R@ _JJKSW.KID-BYTES +
    R@ _JJKSW.DECODED-U @ MOVE
    R> DROP ;

: _JJKS-CURRENT-KID-MATCHES?  ( workspace -- flag )
    >R
    R@ _JJKSW.SCRATCH R@ _JJKSW.DECODED-U @
    R@ _JJKSW.SELECTOR @ R@ _JJKSW.SELECTOR-U @
    COMPARE 0=
    R> DROP ;

: _JJKS-STAGE-MATCH  ( workspace -- )
    DUP _JJKSW.CURRENT-PUBLIC
    OVER _JJKSW.SELECTED-PUBLIC
    JOSE-JWK-SET-P256-PUBLIC-SIZE MOVE
    1 SWAP _JJKSW.MATCH-COUNT ! ;

: _JJKS-PROCESS-KID  ( workspace -- status )
    >R
    S" kid" R@ _JJKS-FIND-MEMBER
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    0= IF
        R> DROP JOSE-JWK-SET-P256-S-MISSING EXIT
    THEN
    R@ _JJKSW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        R> DROP JOSE-JWK-SET-P256-S-TYPE EXIT
    THEN
    R@ _JJKS-DECODE-CURRENT
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _JJKSW.DECODED-U @ 0= IF
        R> DROP JOSE-JWK-SET-P256-S-EMPTY EXIT
    THEN
    R@ _JJKS-KID-DUPLICATE? IF
        R> DROP JOSE-JWK-SET-P256-S-DUPLICATE EXIT
    THEN
    R@ _JJKS-STORE-KID
    R@ _JJKS-CURRENT-KID-MATCHES? IF
        R@ _JJKS-STAGE-MATCH
    THEN
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-PROCESS-USE  ( workspace -- status )
    >R
    S" use" R@ _JJKS-FIND-MEMBER
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    0= IF
        R> DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    R@ _JJKSW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        R> DROP JOSE-JWK-SET-P256-S-USE EXIT
    THEN
    R@ _JJKS-DECODE-CURRENT
    DUP IF R> DROP EXIT THEN
    DROP
    S" sig" R@ _JJKS-SCRATCH= 0= IF
        R> DROP JOSE-JWK-SET-P256-S-USE EXIT
    THEN
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-PROCESS-ALGORITHM  ( workspace -- status )
    >R
    S" alg" R@ _JJKS-FIND-MEMBER
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    0= IF
        R> DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    R@ _JJKSW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        R> DROP JOSE-JWK-SET-P256-S-ALGORITHM EXIT
    THEN
    R@ _JJKS-DECODE-CURRENT
    DUP IF R> DROP EXIT THEN
    DROP
    S" ES256" R@ _JJKS-SCRATCH= 0= IF
        R> DROP JOSE-JWK-SET-P256-S-ALGORITHM EXIT
    THEN
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-PROCESS-KEY-OPS  ( workspace -- status )
    >R
    S" key_ops" R@ _JJKS-FIND-MEMBER
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    0= IF
        R> DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    R@ _JJKSW.VALUE-TYPE @ JOSE-JSON-T-ARRAY <> IF
        R> DROP JOSE-JWK-SET-P256-S-KEY-OPS EXIT
    THEN
    R@ _JJKSW.VALUE-A @ R@ _JJKSW.VALUE-U @ R@
    _JJKS-ARRAY-BIND
    DUP IF R> DROP EXIT THEN
    DROP

    R@ _JJKS-ARRAY-NEXT
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    0= IF
        R> DROP JOSE-JWK-SET-P256-S-KEY-OPS EXIT
    THEN
    R@ _JJKSW.TOKEN-TYPE @ JOSE-JSON-T-STRING <> IF
        R> DROP JOSE-JWK-SET-P256-S-KEY-OPS EXIT
    THEN
    R@ _JJKSW.ARRAY-A @ R@ _JJKSW.TOKEN-START @ +
    R@ _JJKSW.TOKEN-U @ R@ _JJKS-DECODE-SPAN
    DUP IF R> DROP EXIT THEN
    DROP
    S" verify" R@ _JJKS-SCRATCH= 0= IF
        R> DROP JOSE-JWK-SET-P256-S-KEY-OPS EXIT
    THEN

    R@ _JJKS-ARRAY-NEXT
    DUP IF
        NIP R> DROP EXIT
    THEN
    DROP
    IF
        R> DROP JOSE-JWK-SET-P256-S-KEY-OPS EXIT
    THEN
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-PROCESS-CANDIDATE  ( workspace -- status )
    >R
    R@ _JJKS-CURRENT-CANDIDATE R@ _JJKS-OBJECT-PARSE
    DUP IF R> DROP EXIT THEN
    DROP

    R@ _JJKS-CHECK-SENSITIVE
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _JJKS-CHECK-UNSUPPORTED
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _JJKS-VALIDATE-PUBLIC
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _JJKS-PROCESS-KID
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _JJKS-PROCESS-USE
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _JJKS-PROCESS-ALGORITHM
    DUP IF R> DROP EXIT THEN
    DROP
    R@ _JJKS-PROCESS-KEY-OPS
    R> DROP ;

: _JJKS-PROCESS-ALL  ( workspace -- status )
    >R
    0 R@ _JJKSW.CURRENT-INDEX !
    0 R@ _JJKSW.MATCH-COUNT !
    BEGIN
        R@ _JJKSW.CURRENT-INDEX @
        R@ _JJKSW.KEY-COUNT @ <
    WHILE
        R@ _JJKS-PROCESS-CANDIDATE
        DUP IF R> DROP EXIT THEN
        DROP
        1 R@ _JJKSW.CURRENT-INDEX +!
    REPEAT
    R@ _JJKSW.MATCH-COUNT @ 1 <> IF
        R> DROP JOSE-JWK-SET-P256-S-NOT-FOUND EXIT
    THEN
    R> DROP JOSE-JWK-SET-P256-S-OK ;

: _JJKS-THUMBPRINT>STATUS  ( jwk-status -- status )
    DUP JOSE-JWK-P256-S-OK = IF
        DROP JOSE-JWK-SET-P256-S-OK EXIT
    THEN
    DUP JOSE-JWK-P256-S-CRYPTO = IF
        DROP JOSE-JWK-SET-P256-S-CRYPTO EXIT
    THEN
    DUP JOSE-JWK-P256-S-RANGE = IF
        DROP JOSE-JWK-SET-P256-S-RANGE EXIT
    THEN
    DUP JOSE-JWK-P256-S-PROTECTED = IF
        DROP JOSE-JWK-SET-P256-S-PROTECTED EXIT
    THEN
    DUP JOSE-JWK-P256-S-PLATFORM = IF
        DROP JOSE-JWK-SET-P256-S-PLATFORM EXIT
    THEN
    DROP JOSE-JWK-SET-P256-S-INTERNAL ;

: _JJKS-THUMBPRINT-STAGE  ( workspace -- status )
    >R
    R@ _JJKSW.SELECTED-PUBLIC
    R@ _JJKSW.SELECTED-THUMBPRINT
    R@ _JJKSW.JWK
    JOSE-JWK-P256-THUMBPRINT
    _JJKS-THUMBPRINT>STATUS
    R> DROP ;

: _JJKS-SELECT-STAGE  ( workspace -- status )
    DUP _JJKS-ROOT-STAGE
    DUP IF NIP EXIT THEN
    DROP
    DUP _JJKS-PROCESS-ALL
    DUP IF NIP EXIT THEN
    DROP
    _JJKS-THUMBPRINT-STAGE ;

\ =====================================================================
\  Admitted operation and publication
\ =====================================================================

: _JJKS-SELECT-ADMITTED
  ( source source-u selector selector-u public-output thumbprint-output workspace -- status )
    DUP _JJKS-WIPE
    6 PICK OVER _JJKSW.SOURCE !
    5 PICK OVER _JJKSW.SOURCE-U !
    4 PICK OVER _JJKSW.SELECTOR !
    3 PICK OVER _JJKSW.SELECTOR-U !
    2 PICK OVER _JJKSW.PUBLIC-OUTPUT !
    1 PICK OVER _JJKSW.THUMBPRINT-OUTPUT !
    >R _JJKS-DROP6 R>
    _JJKS-SELECT-STAGE ;

: _JJKS-SELECT-PUBLISH  ( workspace -- )
    DUP _JJKSW.SELECTED-PUBLIC
    OVER _JJKSW.PUBLIC-OUTPUT @
    JOSE-JWK-SET-P256-PUBLIC-SIZE MOVE
    DUP _JJKSW.SELECTED-THUMBPRINT
    OVER _JJKSW.THUMBPRINT-OUTPUT @
    JOSE-JWK-SET-P256-THUMBPRINT-SIZE MOVE
    DROP ;

: _JJKS-SELECT-CALL
  ( source source-u selector selector-u public-output thumbprint-output workspace xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _JJKS-WIPE
        _JJKS-DROP7
        R> DROP JOSE-JWK-SET-P256-S-INTERNAL EXIT
    THEN
    DROP
    DUP IF
        R@ _JJKS-WIPE
        R> DROP EXIT
    THEN
    DROP
    R@ ['] _JJKS-SELECT-PUBLISH ['] _JJKS-WIPE
        _JJKS-CALL-FINALLY
    R> DROP
    JOSE-JWK-SET-P256-S-OK ;

: JOSE-JWK-SET-P256-SELECT
  ( source source-u selector selector-u public-output thumbprint-output workspace -- status )
    _JJKS-7DUP _JJKS-SELECT-GEOMETRY
    DUP IF
        >R _JJKS-DROP7 R> EXIT
    THEN
    DROP
    ['] _JJKS-SELECT-ADMITTED _JJKS-SELECT-CALL ;
