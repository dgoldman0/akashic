\ =====================================================================
\  did-document.f - Strict caller-owned AT Protocol DID documents
\ =====================================================================
\  This module applies the AT Protocol identity profile to one already
\  obtained JSON DID document.  It performs no DID resolution, DNS, HTTP,
\  OAuth, repository, firehose, or application work.
\
\  The complete JSON document is validated before profile selection.  The
\  parser then requires:
\
\    * an `id` string exactly equal to the caller's expected DID;
\    * the first modern `#atproto` Multikey verification method whose
\      controller is that DID and whose publicKeyMultibase is syntactically
\      Base58btc;
\    * the first `#atproto_pds` AtprotoPersonalDataServer service whose
\      serviceEndpoint is an absolute HTTPS origin; and
\    * optionally, the first syntactically valid `at://` handle in
\      `alsoKnownAs`.
\
\  Fragment identifiers may be relative (`#atproto`) or fully qualified
\  (`did:...#atproto`).  Legacy publicKeyJwk verification methods are not
\  selected.  Unknown members and nested values remain accepted only after
\  the strict JSON dependency has validated their syntax, UTF-8, depth, and
\  duplicate decoded names.
\
\  A successful parse publishes one fixed-size, self-contained result.  No
\  result view borrows the receive buffer.  The optional-handle evidence is
\  explicit: a conforming document without a usable handle succeeds with
\  AT-DIDDOC-E-MISSING.  Missing or unusable key/PDS candidates instead
\  return AT-DIDDOC-S-KEY or AT-DIDDOC-S-PDS and publish nothing.
\
\  Public API:
\    AT-DIDDOC-SIZE
\    AT-DIDDOC-WORKSPACE-SIZE
\    AT-DIDDOC-STATUS-VALID?          ( status -- flag )
\    AT-DIDDOC-VALID?                 ( document -- flag )
\    AT-DIDDOC-WORKSPACE-CLEAR        ( workspace -- status )
\    AT-DIDDOC-PARSE
\      ( source source-u expected-did expected-did-u
\        document workspace -- status )
\    AT-DIDDOC-EVIDENCE@
\      ( document -- id-e handle-e key-e pds-e status )
\    AT-DIDDOC-DID@                   ( document -- a u status )
\    AT-DIDDOC-HANDLE@                ( document -- a u status )
\    AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
\      ( document -- a u status )
\    AT-DIDDOC-PDS-TARGET@            ( document -- target status )
\    AT-DIDDOC-PDS-ORIGIN@            ( document -- a u status )
\ =====================================================================

PROVIDED akashic-atproto-diddoc

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../security/jose/json-object.f
REQUIRE ../net/http-target.f
REQUIRE did.f
REQUIRE handle.f

\ =====================================================================
\  Public status, evidence, and bounds
\ =====================================================================

0  CONSTANT AT-DIDDOC-S-OK
1  CONSTANT AT-DIDDOC-S-INVALID
2  CONSTANT AT-DIDDOC-S-CAPACITY
3  CONSTANT AT-DIDDOC-S-ALIAS
4  CONSTANT AT-DIDDOC-S-JSON
5  CONSTANT AT-DIDDOC-S-ID
6  CONSTANT AT-DIDDOC-S-HANDLE
7  CONSTANT AT-DIDDOC-S-KEY
8  CONSTANT AT-DIDDOC-S-PDS
9  CONSTANT AT-DIDDOC-S-MISSING
10 CONSTANT AT-DIDDOC-S-INTERNAL
11 CONSTANT AT-DIDDOC-S-RANGE
12 CONSTANT AT-DIDDOC-S-PROTECTED
13 CONSTANT AT-DIDDOC-S-PLATFORM

: AT-DIDDOC-STATUS-VALID?  ( status -- flag )
    DUP AT-DIDDOC-S-OK >=
    SWAP AT-DIDDOC-S-PLATFORM <= AND ;

0 CONSTANT AT-DIDDOC-E-MISSING
1 CONSTANT AT-DIDDOC-E-VALID

64   CONSTANT AT-DIDDOC-MAX-MEMBERS
2048 CONSTANT AT-DIDDOC-DID-CAPACITY
253  CONSTANT AT-DIDDOC-HANDLE-CAPACITY
512  CONSTANT AT-DIDDOC-KEY-CAPACITY
AT-DIDDOC-DID-CAPACITY 12 + CONSTANT _ATDD-SCRATCH-CAPACITY
2064 CONSTANT _ATDD-SCRATCH-STORAGE

1 CONSTANT _ATDD-F-ID
2 CONSTANT _ATDD-F-HANDLE
4 CONSTANT _ATDD-F-KEY
8 CONSTANT _ATDD-F-PDS
_ATDD-F-ID _ATDD-F-KEY OR _ATDD-F-PDS OR
    CONSTANT _ATDD-F-REQUIRED
_ATDD-F-REQUIRED _ATDD-F-HANDLE OR CONSTANT _ATDD-F-ALL

1 CONSTANT _ATDD-P-ID
2 CONSTANT _ATDD-P-ALSO-KNOWN-AS
4 CONSTANT _ATDD-P-VERIFICATION
8 CONSTANT _ATDD-P-SERVICE

1 CONSTANT _ATDD-C-ID
2 CONSTANT _ATDD-C-TYPE
4 CONSTANT _ATDD-C-CONTROLLER
8 CONSTANT _ATDD-C-VALUE
15 CONSTANT _ATDD-C-ALL

4 CONSTANT _ATDD-PDS-ENDPOINT
_ATDD-C-ID _ATDD-C-TYPE OR _ATDD-PDS-ENDPOINT OR
    CONSTANT _ATDD-PDS-ALL

\ =====================================================================
\  Fixed caller-owned result
\ =====================================================================

0x4154444944444F43 CONSTANT _ATDD-MAGIC-VALUE  \ "ATDIDDOC"

 0 CONSTANT _ATDD-MAGIC
 8 CONSTANT _ATDD-FLAGS
16 CONSTANT _ATDD-DID-U
24 CONSTANT _ATDD-HANDLE-U
32 CONSTANT _ATDD-KEY-U
40 CONSTANT _ATDD-RESERVED
48 CONSTANT _ATDD-HEADER-SIZE

_ATDD-HEADER-SIZE CONSTANT _ATDD-DID-OFF
_ATDD-DID-OFF AT-DIDDOC-DID-CAPACITY +
    CONSTANT _ATDD-HANDLE-OFF
_ATDD-HANDLE-OFF 256 +
    CONSTANT _ATDD-KEY-OFF
_ATDD-KEY-OFF AT-DIDDOC-KEY-CAPACITY +
    CONSTANT _ATDD-TARGET-OFF
_ATDD-TARGET-OFF HTARGET-SIZE + CONSTANT AT-DIDDOC-SIZE

: _ATDD.MAGIC       ( d -- a ) _ATDD-MAGIC + ;
: _ATDD.FLAGS       ( d -- a ) _ATDD-FLAGS + ;
: _ATDD.DID-U       ( d -- a ) _ATDD-DID-U + ;
: _ATDD.HANDLE-U    ( d -- a ) _ATDD-HANDLE-U + ;
: _ATDD.KEY-U       ( d -- a ) _ATDD-KEY-U + ;
: _ATDD.RESERVED    ( d -- a ) _ATDD-RESERVED + ;
: _ATDD.DID         ( d -- a ) _ATDD-DID-OFF + ;
: _ATDD.HANDLE      ( d -- a ) _ATDD-HANDLE-OFF + ;
: _ATDD.KEY         ( d -- a ) _ATDD-KEY-OFF + ;
: _ATDD.TARGET      ( d -- a ) _ATDD-TARGET-OFF + ;

\ =====================================================================
\  Caller admission shared by parser and result accessors
\ =====================================================================

: _ATDD-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP AT-DIDDOC-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP AT-DIDDOC-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP AT-DIDDOC-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP AT-DIDDOC-S-PLATFORM EXIT
    THEN
    DROP AT-DIDDOC-S-PLATFORM ;

: _ATDD-ADMIT-SPAN  ( address length -- status )
    CALLER-SPAN-STATUS _ATDD-CALLER>STATUS ;

: _ATDD-BASE58-BYTE?  ( byte -- flag )
    DUP [CHAR] 1 >= OVER [CHAR] 9 <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] A >= OVER [CHAR] H <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] J >= OVER [CHAR] N <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] P >= OVER [CHAR] Z <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] a >= OVER [CHAR] k <= AND IF DROP -1 EXIT THEN
    DUP [CHAR] m >= SWAP [CHAR] z <= AND ;

: _ATDD-MULTIBASE?  ( address length -- flag )
    DUP 2 < OVER AT-DIDDOC-KEY-CAPACITY > OR IF
        2DROP 0 EXIT
    THEN
    OVER C@ [CHAR] z <> IF 2DROP 0 EXIT THEN
    1 /STRING
    BEGIN DUP WHILE
        OVER C@ _ATDD-BASE58-BYTE? 0= IF
            2DROP 0 EXIT
        THEN
        1 /STRING
    REPEAT
    2DROP -1 ;

: _ATDD-ORIGIN-TARGET?  ( target -- flag )
    DUP HTARGET-VALID? 0= IF DROP 0 EXIT THEN
    HTARGET-REQUEST-TARGET$ S" /" COMPARE 0= ;

: _ATDD-RESULT-SHAPE?  ( document -- flag )
    >R
    R@ _ATDD.MAGIC @ _ATDD-MAGIC-VALUE <> IF
        R> DROP 0 EXIT
    THEN
    R@ _ATDD.RESERVED @ IF R> DROP 0 EXIT THEN
    R@ _ATDD.FLAGS @ DUP _ATDD-F-REQUIRED AND
        _ATDD-F-REQUIRED <> IF
        DROP R> DROP 0 EXIT
    THEN
    _ATDD-F-ALL INVERT AND IF R> DROP 0 EXIT THEN
    R@ _ATDD.DID-U @ DUP DID-LENGTH-MIN <
        SWAP AT-DIDDOC-DID-CAPACITY > OR IF
        R> DROP 0 EXIT
    THEN
    R@ _ATDD.HANDLE-U @ DUP 0<
        SWAP AT-DIDDOC-HANDLE-CAPACITY > OR IF
        R> DROP 0 EXIT
    THEN
    R@ _ATDD.KEY-U @ DUP 2 <
        SWAP AT-DIDDOC-KEY-CAPACITY > OR IF
        R> DROP 0 EXIT
    THEN
    R> DROP -1 ;

: AT-DIDDOC-VALID?  ( document -- flag )
    DUP AT-DIDDOC-SIZE _ATDD-ADMIT-SPAN IF DROP 0 EXIT THEN
    DUP _ATDD-RESULT-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _ATDD.DID OVER _ATDD.DID-U @ DID-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP _ATDD.FLAGS @ _ATDD-F-HANDLE AND IF
        DUP _ATDD.HANDLE OVER _ATDD.HANDLE-U @
        AT-HANDLE-NORMALIZED?
        DUP AT-HANDLE-S-OK <> IF
            2DROP DROP 0 EXIT
        THEN
        DROP 0= IF DROP 0 EXIT THEN
    ELSE
        DUP _ATDD.HANDLE-U @ IF DROP 0 EXIT THEN
    THEN
    DUP _ATDD.KEY OVER _ATDD.KEY-U @ _ATDD-MULTIBASE? 0= IF
        DROP 0 EXIT
    THEN
    _ATDD.TARGET _ATDD-ORIGIN-TARGET? ;

\ =====================================================================
\  Result accessors
\ =====================================================================

: AT-DIDDOC-EVIDENCE@
  ( document -- id-e handle-e key-e pds-e status )
    DUP AT-DIDDOC-VALID? 0= IF
        DROP 0 0 0 0 AT-DIDDOC-S-INVALID EXIT
    THEN
    _ATDD.FLAGS @
    AT-DIDDOC-E-VALID
    SWAP _ATDD-F-HANDLE AND IF
        AT-DIDDOC-E-VALID
    ELSE
        AT-DIDDOC-E-MISSING
    THEN
    AT-DIDDOC-E-VALID AT-DIDDOC-E-VALID
    AT-DIDDOC-S-OK ;

: AT-DIDDOC-DID@  ( document -- address length status )
    DUP AT-DIDDOC-VALID? 0= IF
        DROP 0 0 AT-DIDDOC-S-INVALID EXIT
    THEN
    DUP _ATDD.DID SWAP _ATDD.DID-U @
    AT-DIDDOC-S-OK ;

: AT-DIDDOC-HANDLE@  ( document -- address length status )
    DUP AT-DIDDOC-VALID? 0= IF
        DROP 0 0 AT-DIDDOC-S-INVALID EXIT
    THEN
    DUP _ATDD.FLAGS @ _ATDD-F-HANDLE AND 0= IF
        DROP 0 0 AT-DIDDOC-S-MISSING EXIT
    THEN
    DUP _ATDD.HANDLE SWAP _ATDD.HANDLE-U @
    AT-DIDDOC-S-OK ;

: AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
  ( document -- address length status )
    DUP AT-DIDDOC-VALID? 0= IF
        DROP 0 0 AT-DIDDOC-S-INVALID EXIT
    THEN
    DUP _ATDD.KEY SWAP _ATDD.KEY-U @
    AT-DIDDOC-S-OK ;

: AT-DIDDOC-PDS-TARGET@  ( document -- target status )
    DUP AT-DIDDOC-VALID? 0= IF
        DROP 0 AT-DIDDOC-S-INVALID EXIT
    THEN
    _ATDD.TARGET AT-DIDDOC-S-OK ;

: AT-DIDDOC-PDS-ORIGIN@  ( document -- address length status )
    DUP AT-DIDDOC-VALID? 0= IF
        DROP 0 0 AT-DIDDOC-S-INVALID EXIT
    THEN
    _ATDD.TARGET HTARGET-URI$
    AT-DIDDOC-S-OK ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================

AT-DIDDOC-MAX-MEMBERS JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." AT Protocol DID document descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _ATDD-DESCRIPTOR-SIZE

  0 CONSTANT _ATDDW-SOURCE
  8 CONSTANT _ATDDW-SOURCE-U
 16 CONSTANT _ATDDW-EXPECTED
 24 CONSTANT _ATDDW-EXPECTED-U
 32 CONSTANT _ATDDW-OUTPUT
 40 CONSTANT _ATDDW-NAME-A
 48 CONSTANT _ATDDW-NAME-U
 56 CONSTANT _ATDDW-VALUE-A
 64 CONSTANT _ATDDW-VALUE-U
 72 CONSTANT _ATDDW-VALUE-TYPE
 80 CONSTANT _ATDDW-PRESENT
 88 CONSTANT _ATDDW-ARRAY-A
 96 CONSTANT _ATDDW-ARRAY-U
104 CONSTANT _ATDDW-ARRAY-POS
112 CONSTANT _ATDDW-TOKEN-START
120 CONSTANT _ATDDW-TOKEN-U
128 CONSTANT _ATDDW-TOKEN-TYPE
136 CONSTANT _ATDDW-DECODED-U
144 CONSTANT _ATDDW-CANDIDATE-FLAGS
152 CONSTANT _ATDDW-CANDIDATE-U
160 CONSTANT _ATDDW-SCAN-DEPTH
168 CONSTANT _ATDDW-SCAN-STRING
176 CONSTANT _ATDDW-SCAN-ESCAPE
184 CONSTANT _ATDDW-DECODE-A
192 CONSTANT _ATDDW-DECODE-CAP
200 CONSTANT _ATDDW-AKA-A
208 CONSTANT _ATDDW-AKA-U
216 CONSTANT _ATDDW-AKA-TYPE
224 CONSTANT _ATDDW-VM-A
232 CONSTANT _ATDDW-VM-U
240 CONSTANT _ATDDW-VM-TYPE
248 CONSTANT _ATDDW-SVC-A
256 CONSTANT _ATDDW-SVC-U
264 CONSTANT _ATDDW-SVC-TYPE
272 CONSTANT _ATDDW-OBJECT-A
280 CONSTANT _ATDDW-RESERVED0
288 CONSTANT _ATDDW-HEADER-SIZE

_ATDDW-HEADER-SIZE CONSTANT _ATDDW-DESCRIPTOR-OFF
_ATDDW-DESCRIPTOR-OFF _ATDD-DESCRIPTOR-SIZE +
    CONSTANT _ATDDW-NAMES-OFF
_ATDDW-NAMES-OFF JOSE-JSON-MAX-NAME-BYTES +
    CONSTANT _ATDDW-JSON-OFF
_ATDDW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
    CONSTANT _ATDDW-STAGE-OFF
_ATDDW-STAGE-OFF AT-DIDDOC-SIZE +
    CONSTANT _ATDDW-SCRATCH-OFF
_ATDDW-SCRATCH-OFF _ATDD-SCRATCH-STORAGE +
    CONSTANT AT-DIDDOC-WORKSPACE-SIZE

: _ATDDW.SOURCE          ( w -- a ) _ATDDW-SOURCE + ;
: _ATDDW.SOURCE-U        ( w -- a ) _ATDDW-SOURCE-U + ;
: _ATDDW.EXPECTED        ( w -- a ) _ATDDW-EXPECTED + ;
: _ATDDW.EXPECTED-U      ( w -- a ) _ATDDW-EXPECTED-U + ;
: _ATDDW.OUTPUT          ( w -- a ) _ATDDW-OUTPUT + ;
: _ATDDW.NAME-A          ( w -- a ) _ATDDW-NAME-A + ;
: _ATDDW.NAME-U          ( w -- a ) _ATDDW-NAME-U + ;
: _ATDDW.VALUE-A         ( w -- a ) _ATDDW-VALUE-A + ;
: _ATDDW.VALUE-U         ( w -- a ) _ATDDW-VALUE-U + ;
: _ATDDW.VALUE-TYPE      ( w -- a ) _ATDDW-VALUE-TYPE + ;
: _ATDDW.PRESENT         ( w -- a ) _ATDDW-PRESENT + ;
: _ATDDW.ARRAY-A         ( w -- a ) _ATDDW-ARRAY-A + ;
: _ATDDW.ARRAY-U         ( w -- a ) _ATDDW-ARRAY-U + ;
: _ATDDW.ARRAY-POS       ( w -- a ) _ATDDW-ARRAY-POS + ;
: _ATDDW.TOKEN-START     ( w -- a ) _ATDDW-TOKEN-START + ;
: _ATDDW.TOKEN-U         ( w -- a ) _ATDDW-TOKEN-U + ;
: _ATDDW.TOKEN-TYPE      ( w -- a ) _ATDDW-TOKEN-TYPE + ;
: _ATDDW.DECODED-U       ( w -- a ) _ATDDW-DECODED-U + ;
: _ATDDW.CANDIDATE-FLAGS ( w -- a ) _ATDDW-CANDIDATE-FLAGS + ;
: _ATDDW.CANDIDATE-U     ( w -- a ) _ATDDW-CANDIDATE-U + ;
: _ATDDW.SCAN-DEPTH      ( w -- a ) _ATDDW-SCAN-DEPTH + ;
: _ATDDW.SCAN-STRING     ( w -- a ) _ATDDW-SCAN-STRING + ;
: _ATDDW.SCAN-ESCAPE     ( w -- a ) _ATDDW-SCAN-ESCAPE + ;
: _ATDDW.DECODE-A        ( w -- a ) _ATDDW-DECODE-A + ;
: _ATDDW.DECODE-CAP      ( w -- a ) _ATDDW-DECODE-CAP + ;
: _ATDDW.AKA-A           ( w -- a ) _ATDDW-AKA-A + ;
: _ATDDW.AKA-U           ( w -- a ) _ATDDW-AKA-U + ;
: _ATDDW.AKA-TYPE        ( w -- a ) _ATDDW-AKA-TYPE + ;
: _ATDDW.VM-A            ( w -- a ) _ATDDW-VM-A + ;
: _ATDDW.VM-U            ( w -- a ) _ATDDW-VM-U + ;
: _ATDDW.VM-TYPE         ( w -- a ) _ATDDW-VM-TYPE + ;
: _ATDDW.SVC-A           ( w -- a ) _ATDDW-SVC-A + ;
: _ATDDW.SVC-U           ( w -- a ) _ATDDW-SVC-U + ;
: _ATDDW.SVC-TYPE        ( w -- a ) _ATDDW-SVC-TYPE + ;
: _ATDDW.OBJECT-A        ( w -- a ) _ATDDW-OBJECT-A + ;

: _ATDDW.DESCRIPTOR  ( w -- a ) _ATDDW-DESCRIPTOR-OFF + ;
: _ATDDW.NAMES       ( w -- a ) _ATDDW-NAMES-OFF + ;
: _ATDDW.JSON        ( w -- a ) _ATDDW-JSON-OFF + ;
: _ATDDW.STAGE       ( w -- a ) _ATDDW-STAGE-OFF + ;
: _ATDDW.SCRATCH     ( w -- a ) _ATDDW-SCRATCH-OFF + ;

: _ATDD-WIPE  ( workspace -- )
    AT-DIDDOC-WORKSPACE-SIZE 0 FILL ;

: AT-DIDDOC-WORKSPACE-CLEAR  ( workspace -- status )
    DUP AT-DIDDOC-WORKSPACE-SIZE _ATDD-ADMIT-SPAN
    ?DUP IF NIP EXIT THEN
    _ATDD-WIPE
    AT-DIDDOC-S-OK ;

\ =====================================================================
\  Parse geometry and mandatory cleanup
\ =====================================================================

: _ATDD-DROP6  ( x1 x2 x3 x4 x5 x6 -- )
    2DROP 2DROP 2DROP ;

: _ATDD-RETURN6  ( x1 x2 x3 x4 x5 x6 status -- status )
    >R _ATDD-DROP6 R> ;

: _ATDD-PARSE-GEOMETRY
  ( source source-u expected expected-u document workspace -- status )
    DUP AT-DIDDOC-WORKSPACE-SIZE _ATDD-ADMIT-SPAN
        ?DUP IF
        >R _ATDD-DROP6 R> EXIT
    THEN
    5 PICK 5 PICK _ATDD-ADMIT-SPAN ?DUP IF
        >R _ATDD-DROP6 R> EXIT
    THEN
    3 PICK 3 PICK _ATDD-ADMIT-SPAN ?DUP IF
        >R _ATDD-DROP6 R> EXIT
    THEN
    OVER AT-DIDDOC-SIZE _ATDD-ADMIT-SPAN ?DUP IF
        >R _ATDD-DROP6 R> EXIT
    THEN

    4 PICK 0= IF
        AT-DIDDOC-S-INVALID _ATDD-RETURN6 EXIT
    THEN
    4 PICK JOSE-JSON-MAX-DOCUMENT-BYTES U> IF
        AT-DIDDOC-S-CAPACITY _ATDD-RETURN6 EXIT
    THEN
    2 PICK 0= IF
        AT-DIDDOC-S-ID _ATDD-RETURN6 EXIT
    THEN
    2 PICK AT-DIDDOC-DID-CAPACITY U> IF
        AT-DIDDOC-S-CAPACITY _ATDD-RETURN6 EXIT
    THEN

    5 PICK 5 PICK 3 PICK AT-DIDDOC-SIZE
        MSPAN-OVERLAP? IF
        AT-DIDDOC-S-ALIAS _ATDD-RETURN6 EXIT
    THEN
    5 PICK 5 PICK 2 PICK AT-DIDDOC-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        AT-DIDDOC-S-ALIAS _ATDD-RETURN6 EXIT
    THEN
    3 PICK 3 PICK 3 PICK AT-DIDDOC-SIZE
        MSPAN-OVERLAP? IF
        AT-DIDDOC-S-ALIAS _ATDD-RETURN6 EXIT
    THEN
    3 PICK 3 PICK 2 PICK AT-DIDDOC-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        AT-DIDDOC-S-ALIAS _ATDD-RETURN6 EXIT
    THEN
    OVER AT-DIDDOC-SIZE
        2 PICK AT-DIDDOC-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        AT-DIDDOC-S-ALIAS _ATDD-RETURN6 EXIT
    THEN

    3 PICK 3 PICK DID-VALIDATE DID-S-OK <> IF
        AT-DIDDOC-S-ID _ATDD-RETURN6 EXIT
    THEN
    AT-DIDDOC-S-OK _ATDD-RETURN6 ;

\ An operation/publication THROW is rethrown after successful cleanup.
\ Cleanup THROW propagates directly and therefore has precedence.
: _ATDD-CALL-FINALLY
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
\  Strict JSON helpers
\ =====================================================================

: _ATDD-JSON>STATUS  ( json-status -- status )
    DUP JOSE-JSON-S-OK = IF DROP AT-DIDDOC-S-OK EXIT THEN
    DUP JOSE-JSON-S-CAPACITY = IF
        DROP AT-DIDDOC-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-MEMBERS = IF
        DROP AT-DIDDOC-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-STRING = IF
        DROP AT-DIDDOC-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-DOCUMENT = IF
        DROP AT-DIDDOC-S-CAPACITY EXIT
    THEN
    DUP JOSE-JSON-S-SYNTAX = IF DROP AT-DIDDOC-S-JSON EXIT THEN
    DUP JOSE-JSON-S-UTF8 = IF DROP AT-DIDDOC-S-JSON EXIT THEN
    DUP JOSE-JSON-S-DEPTH = IF DROP AT-DIDDOC-S-JSON EXIT THEN
    DUP JOSE-JSON-S-DUPLICATE = IF DROP AT-DIDDOC-S-JSON EXIT THEN
    DROP AT-DIDDOC-S-INTERNAL ;

: _ATDD-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _ATDDW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATDDW.VALUE-TYPE !
    R@ _ATDDW.VALUE-U !
    R@ _ATDDW.OBJECT-A @ +
        R@ _ATDDW.VALUE-A !
    R@ _ATDDW.NAME-U !
    R@ _ATDDW.NAMES +
        R@ _ATDDW.NAME-A !
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-NAME=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _ATDDW.NAME-A @ R@ _ATDDW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _ATDD-DECODE-CURRENT
  ( destination capacity workspace -- status )
    >R
    R@ _ATDDW.DECODE-CAP !
    R@ _ATDDW.DECODE-A !
    R@ _ATDDW.VALUE-A @ R@ _ATDDW.VALUE-U @
    R@ _ATDDW.DECODE-A @ R@ _ATDDW.DECODE-CAP @
    R@ _ATDDW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        DUP JOSE-JSON-S-CAPACITY = IF
            2DROP R> DROP AT-DIDDOC-S-CAPACITY EXIT
        THEN
        2DROP R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATDDW.DECODED-U !
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-DECODE-TOKEN
  ( destination capacity workspace -- status )
    >R
    R@ _ATDDW.DECODE-CAP !
    R@ _ATDDW.DECODE-A !
    R@ _ATDDW.ARRAY-A @ R@ _ATDDW.TOKEN-START @ +
    R@ _ATDDW.TOKEN-U @
    R@ _ATDDW.DECODE-A @ R@ _ATDDW.DECODE-CAP @
    R@ _ATDDW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        DUP JOSE-JSON-S-CAPACITY = IF
            2DROP R> DROP AT-DIDDOC-S-CAPACITY EXIT
        THEN
        2DROP R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    DROP
    R@ _ATDDW.DECODED-U !
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-SET-CANDIDATE  ( mask workspace -- )
    >R
    R@ _ATDDW.CANDIDATE-FLAGS @ OR
    R@ _ATDDW.CANDIDATE-FLAGS !
    R> DROP ;

: _ATDD-SCRATCH=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _ATDDW.SCRATCH R@ _ATDDW.DECODED-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _ATDD-FRAGMENT-ID?  ( suffix-a suffix-u workspace -- flag )
    >R
    2DUP R@ _ATDD-SCRATCH= IF
        2DROP R> DROP -1 EXIT
    THEN
    R@ _ATDDW.DECODED-U @
    R@ _ATDDW.EXPECTED-U @ 2 PICK + <> IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _ATDDW.SCRATCH R@ _ATDDW.EXPECTED-U @
    R@ _ATDDW.EXPECTED @ R@ _ATDDW.EXPECTED-U @
    COMPARE IF
        2DROP R> DROP 0 EXIT
    THEN
    R@ _ATDDW.SCRATCH R@ _ATDDW.EXPECTED-U @ +
    R@ _ATDDW.DECODED-U @ R@ _ATDDW.EXPECTED-U @ -
    2SWAP COMPARE 0=
    R> DROP ;

\ =====================================================================
\  Array token iterator
\ =====================================================================
\  The root JSON pass has already validated every array value.  This
\  iterator only recovers exact token boundaries while respecting strings
\  and nested containers; impossible geometry is therefore INTERNAL.

: _ATDD-JSON-WS?  ( byte -- flag )
    DUP 32 = IF DROP -1 EXIT THEN
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 10 = IF DROP -1 EXIT THEN
    13 = ;

: _ATDD-ARRAY-C@  ( position workspace -- byte )
    DUP _ATDDW.ARRAY-A @ ROT + C@ SWAP DROP ;

: _ATDD-ARRAY-SKIP-WS  ( workspace -- )
    BEGIN
        DUP _ATDDW.ARRAY-POS @
        OVER _ATDDW.ARRAY-U @ U<
    WHILE
        DUP _ATDDW.ARRAY-POS @ OVER _ATDD-ARRAY-C@
        _ATDD-JSON-WS? 0= IF DROP EXIT THEN
        1 OVER _ATDDW.ARRAY-POS +!
    REPEAT
    DROP ;

: _ATDD-ARRAY-BIND  ( address length workspace -- status )
    >R
    DUP 2 U< IF 2DROP R> DROP AT-DIDDOC-S-INTERNAL EXIT THEN
    OVER C@ [CHAR] [ <> IF
        2DROP R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    2DUP + 1- C@ [CHAR] ] <> IF
        2DROP R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    R@ _ATDDW.ARRAY-U !
    R@ _ATDDW.ARRAY-A !
    1 R@ _ATDDW.ARRAY-POS !
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-SCAN-STRING  ( workspace -- status )
    >R
    1 R@ _ATDDW.ARRAY-POS +!
    BEGIN
        R@ _ATDDW.ARRAY-POS @ R@ _ATDDW.ARRAY-U @ U<
    WHILE
        R@ _ATDDW.ARRAY-POS @ R@ _ATDD-ARRAY-C@
        DUP 34 = IF
            DROP
            1 R@ _ATDDW.ARRAY-POS +!
            R> DROP AT-DIDDOC-S-OK EXIT
        THEN
        92 = IF
            1 R@ _ATDDW.ARRAY-POS +!
            R@ _ATDDW.ARRAY-POS @
            R@ _ATDDW.ARRAY-U @ U< 0= IF
                R> DROP AT-DIDDOC-S-INTERNAL EXIT
            THEN
        THEN
        1 R@ _ATDDW.ARRAY-POS +!
    REPEAT
    R> DROP AT-DIDDOC-S-INTERNAL ;

: _ATDD-SCAN-CONTAINER  ( workspace -- status )
    >R
    0 R@ _ATDDW.SCAN-DEPTH !
    0 R@ _ATDDW.SCAN-STRING !
    0 R@ _ATDDW.SCAN-ESCAPE !
    BEGIN
        R@ _ATDDW.ARRAY-POS @ R@ _ATDDW.ARRAY-U @ U<
    WHILE
        R@ _ATDDW.ARRAY-POS @ R@ _ATDD-ARRAY-C@
        R@ _ATDDW.SCAN-STRING @ IF
            R@ _ATDDW.SCAN-ESCAPE @ IF
                DROP 0 R@ _ATDDW.SCAN-ESCAPE !
            ELSE
                DUP 92 = IF
                    DROP -1 R@ _ATDDW.SCAN-ESCAPE !
                ELSE
                    34 = IF
                        0 R@ _ATDDW.SCAN-STRING !
                    THEN
                THEN
            THEN
        ELSE
            DUP 34 = IF
                DROP -1 R@ _ATDDW.SCAN-STRING !
            ELSE
                DUP [CHAR] { = OVER [CHAR] [ = OR IF
                    DROP 1 R@ _ATDDW.SCAN-DEPTH +!
                ELSE
                    DUP [CHAR] } = SWAP [CHAR] ] = OR IF
                        -1 R@ _ATDDW.SCAN-DEPTH +!
                    THEN
                THEN
            THEN
        THEN
        1 R@ _ATDDW.ARRAY-POS +!
        R@ _ATDDW.SCAN-DEPTH @ 0= IF
            R> DROP AT-DIDDOC-S-OK EXIT
        THEN
    REPEAT
    R> DROP AT-DIDDOC-S-INTERNAL ;

: _ATDD-SCAN-SCALAR  ( workspace -- status )
    >R
    BEGIN
        R@ _ATDDW.ARRAY-POS @ R@ _ATDDW.ARRAY-U @ U<
    WHILE
        R@ _ATDDW.ARRAY-POS @ R@ _ATDD-ARRAY-C@
        DUP [CHAR] , = OVER [CHAR] ] = OR
        OVER _ATDD-JSON-WS? OR IF
            DROP R> DROP AT-DIDDOC-S-OK EXIT
        THEN
        DROP
        1 R@ _ATDDW.ARRAY-POS +!
    REPEAT
    R> DROP AT-DIDDOC-S-INTERNAL ;

: _ATDD-TOKEN-TYPE!  ( first-byte workspace -- )
    >R
    DUP 34 = IF
        DROP JOSE-JSON-T-STRING R@ _ATDDW.TOKEN-TYPE !
        R> DROP EXIT
    THEN
    DUP [CHAR] { = IF
        DROP JOSE-JSON-T-OBJECT R@ _ATDDW.TOKEN-TYPE !
        R> DROP EXIT
    THEN
    DUP [CHAR] [ = IF
        DROP JOSE-JSON-T-ARRAY R@ _ATDDW.TOKEN-TYPE !
        R> DROP EXIT
    THEN
    DROP 0 R@ _ATDDW.TOKEN-TYPE !
    R> DROP ;

: _ATDD-ARRAY-NEXT  ( workspace -- has-token status )
    >R
    R@ _ATDD-ARRAY-SKIP-WS
    R@ _ATDDW.ARRAY-POS @ R@ _ATDDW.ARRAY-U @ U< 0= IF
        R> DROP 0 AT-DIDDOC-S-INTERNAL EXIT
    THEN
    R@ _ATDDW.ARRAY-POS @
    R@ _ATDDW.ARRAY-U @ 1- = IF
        R@ _ATDDW.ARRAY-POS @ R@ _ATDD-ARRAY-C@
        [CHAR] ] <> IF
            R> DROP 0 AT-DIDDOC-S-INTERNAL EXIT
        THEN
        R@ _ATDDW.ARRAY-U @ R@ _ATDDW.ARRAY-POS !
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN

    R@ _ATDDW.ARRAY-POS @ DUP R@ _ATDDW.TOKEN-START !
    R@ _ATDD-ARRAY-C@ DUP R@ _ATDD-TOKEN-TYPE!
    DUP 34 = IF
        DROP R@ _ATDD-SCAN-STRING
    ELSE
        DUP [CHAR] { = OVER [CHAR] [ = OR IF
            DROP R@ _ATDD-SCAN-CONTAINER
        ELSE
            DROP R@ _ATDD-SCAN-SCALAR
        THEN
    THEN
    DUP IF R> DROP 0 SWAP EXIT THEN DROP

    R@ _ATDDW.ARRAY-POS @ R@ _ATDDW.TOKEN-START @ -
        R@ _ATDDW.TOKEN-U !
    R@ _ATDD-ARRAY-SKIP-WS
    R@ _ATDDW.ARRAY-POS @ R@ _ATDDW.ARRAY-U @ U< 0= IF
        R> DROP 0 AT-DIDDOC-S-INTERNAL EXIT
    THEN
    R@ _ATDDW.ARRAY-POS @ R@ _ATDD-ARRAY-C@
    DUP [CHAR] , = IF
        DROP 1 R@ _ATDDW.ARRAY-POS +!
    ELSE
        [CHAR] ] <> IF
            R> DROP 0 AT-DIDDOC-S-INTERNAL EXIT
        THEN
    THEN
    R> DROP -1 AT-DIDDOC-S-OK ;

\ =====================================================================
\  Root DID-document member capture
\ =====================================================================

: _ATDD-CAPTURE-SPAN
  ( address-cell length-cell type-cell workspace -- )
    >R
    R@ _ATDDW.VALUE-TYPE @ SWAP !
    R@ _ATDDW.VALUE-U @ SWAP !
    R@ _ATDDW.VALUE-A @ SWAP !
    R> DROP ;

: _ATDD-PROCESS-ID  ( workspace -- status )
    >R
    R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        R> DROP AT-DIDDOC-S-ID EXIT
    THEN
    R@ _ATDDW.STAGE _ATDD.DID
    AT-DIDDOC-DID-CAPACITY R@ _ATDD-DECODE-CURRENT
    DUP IF R> DROP EXIT THEN DROP
    R@ _ATDDW.DECODED-U @ 0= IF
        R> DROP AT-DIDDOC-S-ID EXIT
    THEN
    R@ _ATDDW.STAGE _ATDD.DID
    R@ _ATDDW.DECODED-U @ DID-VALID? 0= IF
        R> DROP AT-DIDDOC-S-ID EXIT
    THEN
    R@ _ATDDW.STAGE _ATDD.DID R@ _ATDDW.DECODED-U @
    R@ _ATDDW.EXPECTED @ R@ _ATDDW.EXPECTED-U @
    COMPARE IF
        R> DROP AT-DIDDOC-S-ID EXIT
    THEN
    R@ _ATDDW.DECODED-U @ R@ _ATDDW.STAGE _ATDD.DID-U !
    R@ _ATDDW.STAGE _ATDD.FLAGS @ _ATDD-F-ID OR
        R@ _ATDDW.STAGE _ATDD.FLAGS !
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-CAPTURE-TOP-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _ATDD-MEMBER-LOAD
    DUP IF NIP R> DROP EXIT THEN
    2DROP

    S" id" R@ _ATDD-NAME= IF
        R@ _ATDD-PROCESS-ID
        DUP IF R> DROP EXIT THEN DROP
        R@ _ATDDW.PRESENT @ _ATDD-P-ID OR
            R@ _ATDDW.PRESENT !
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" alsoKnownAs" R@ _ATDD-NAME= IF
        R@ _ATDDW.AKA-A R@ _ATDDW.AKA-U
        R@ _ATDDW.AKA-TYPE R@ _ATDD-CAPTURE-SPAN
        R@ _ATDDW.PRESENT @ _ATDD-P-ALSO-KNOWN-AS OR
            R@ _ATDDW.PRESENT !
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" verificationMethod" R@ _ATDD-NAME= IF
        R@ _ATDDW.VM-A R@ _ATDDW.VM-U
        R@ _ATDDW.VM-TYPE R@ _ATDD-CAPTURE-SPAN
        R@ _ATDDW.PRESENT @ _ATDD-P-VERIFICATION OR
            R@ _ATDDW.PRESENT !
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" service" R@ _ATDD-NAME= IF
        R@ _ATDDW.SVC-A R@ _ATDDW.SVC-U
        R@ _ATDDW.SVC-TYPE R@ _ATDD-CAPTURE-SPAN
        R@ _ATDDW.PRESENT @ _ATDD-P-SERVICE OR
            R@ _ATDDW.PRESENT !
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    \ Unknown members were already validated recursively by the root pass.
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-CAPTURE-TOP-ALL  ( count workspace -- status )
    SWAP 0 ?DO
        I OVER _ATDD-CAPTURE-TOP-MEMBER
        DUP IF NIP UNLOOP EXIT THEN
        DROP
    LOOP
    DROP AT-DIDDOC-S-OK ;

\ =====================================================================
\  Optional handle selection
\ =====================================================================

: _ATDD-TRY-HANDLE  ( workspace -- selected? status )
    >R
    R@ _ATDDW.TOKEN-TYPE @ JOSE-JSON-T-STRING <> IF
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    R@ _ATDDW.SCRATCH AT-DIDDOC-DID-CAPACITY
    R@ _ATDD-DECODE-TOKEN
    DUP AT-DIDDOC-S-INTERNAL = IF
        R> DROP 0 SWAP EXIT
    THEN
    DUP IF
        DROP R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    DROP
    R@ _ATDDW.DECODED-U @ 5 <= IF
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    R@ _ATDDW.SCRATCH 5 S" at://" COMPARE IF
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    R@ _ATDDW.SCRATCH 5 +
    R@ _ATDDW.DECODED-U @ 5 -
    R@ _ATDDW.STAGE _ATDD.HANDLE AT-DIDDOC-HANDLE-CAPACITY
    AT-HANDLE-NORMALIZE
    DUP AT-HANDLE-S-OK = IF
        DROP
        DUP R@ _ATDDW.STAGE _ATDD.HANDLE-U !
        DROP
        R@ _ATDDW.STAGE _ATDD.FLAGS @ _ATDD-F-HANDLE OR
            R@ _ATDDW.STAGE _ATDD.FLAGS !
        R> DROP -1 AT-DIDDOC-S-OK EXIT
    THEN
    DUP AT-HANDLE-S-SYNTAX =
    OVER AT-HANDLE-S-CAPACITY = OR IF
        2DROP R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    2DROP R> DROP 0 AT-DIDDOC-S-INTERNAL ;

: _ATDD-SELECT-HANDLE  ( workspace -- status )
    >R
    R@ _ATDDW.PRESENT @ _ATDD-P-ALSO-KNOWN-AS AND 0= IF
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN
    R@ _ATDDW.AKA-TYPE @ JOSE-JSON-T-ARRAY <> IF
        R> DROP AT-DIDDOC-S-HANDLE EXIT
    THEN
    R@ _ATDDW.AKA-A @ R@ _ATDDW.AKA-U @ R@ _ATDD-ARRAY-BIND
    DUP IF R> DROP EXIT THEN DROP
    BEGIN
        R@ _ATDD-ARRAY-NEXT
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        0= IF R> DROP AT-DIDDOC-S-OK EXIT THEN
        R@ _ATDD-TRY-HANDLE
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        IF R> DROP AT-DIDDOC-S-OK EXIT THEN
    AGAIN ;

\ =====================================================================
\  Candidate-object parsing
\ =====================================================================

: _ATDD-PARSE-TOKEN-OBJECT  ( workspace -- count status )
    >R
    R@ _ATDDW.ARRAY-A @ R@ _ATDDW.TOKEN-START @ +
        R@ _ATDDW.OBJECT-A !
    R@ _ATDDW.OBJECT-A @ R@ _ATDDW.TOKEN-U @
    R@ _ATDDW.DESCRIPTOR AT-DIDDOC-MAX-MEMBERS
    R@ _ATDDW.NAMES JOSE-JSON-MAX-NAME-BYTES
    R@ _ATDDW.JSON
    JOSE-JSON-OBJECT-PARSE
    _ATDD-JSON>STATUS
    DUP IF
        R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ _ATDDW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP 0 AT-DIDDOC-S-INTERNAL EXIT
    THEN
    DROP R> DROP AT-DIDDOC-S-OK ;

: _ATDD-DECODE-SCRATCH  ( workspace -- status )
    DUP _ATDDW.SCRATCH _ATDD-SCRATCH-CAPACITY
    ROT _ATDD-DECODE-CURRENT ;

: _ATDD-VM-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _ATDD-MEMBER-LOAD
    DUP IF NIP R> DROP EXIT THEN
    2DROP

    S" id" R@ _ATDD-NAME= IF
        R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING = IF
            R@ _ATDD-DECODE-SCRATCH
            DUP AT-DIDDOC-S-INTERNAL = IF R> DROP EXIT THEN
            0= IF
                S" #atproto" R@ _ATDD-FRAGMENT-ID? IF
                    _ATDD-C-ID R@ _ATDD-SET-CANDIDATE
                THEN
            THEN
        THEN
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" type" R@ _ATDD-NAME= IF
        R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING = IF
            R@ _ATDD-DECODE-SCRATCH
            DUP AT-DIDDOC-S-INTERNAL = IF R> DROP EXIT THEN
            0= IF
                S" Multikey" R@ _ATDD-SCRATCH= IF
                    _ATDD-C-TYPE R@ _ATDD-SET-CANDIDATE
                THEN
            THEN
        THEN
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" controller" R@ _ATDD-NAME= IF
        R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING = IF
            R@ _ATDD-DECODE-SCRATCH
            DUP AT-DIDDOC-S-INTERNAL = IF R> DROP EXIT THEN
            0= IF
                R@ _ATDDW.EXPECTED @ R@ _ATDDW.EXPECTED-U @
                R@ _ATDD-SCRATCH= IF
                    _ATDD-C-CONTROLLER R@ _ATDD-SET-CANDIDATE
                THEN
            THEN
        THEN
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" publicKeyMultibase" R@ _ATDD-NAME= IF
        R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING = IF
            R@ _ATDDW.STAGE _ATDD.KEY AT-DIDDOC-KEY-CAPACITY
            R@ _ATDD-DECODE-CURRENT
            DUP AT-DIDDOC-S-INTERNAL = IF R> DROP EXIT THEN
            0= IF
                R@ _ATDDW.STAGE _ATDD.KEY
                R@ _ATDDW.DECODED-U @ _ATDD-MULTIBASE? IF
                    R@ _ATDDW.DECODED-U @
                        R@ _ATDDW.CANDIDATE-U !
                    _ATDD-C-VALUE R@ _ATDD-SET-CANDIDATE
                THEN
            THEN
        THEN
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    \ In particular, publicKeyJwk is not a modern Multikey value.
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-VM-MEMBERS  ( count workspace -- status )
    SWAP 0 ?DO
        I OVER _ATDD-VM-MEMBER
        DUP IF NIP UNLOOP EXIT THEN
        DROP
    LOOP
    DROP AT-DIDDOC-S-OK ;

: _ATDD-TRY-VM  ( workspace -- selected? status )
    >R
    R@ _ATDDW.TOKEN-TYPE @ JOSE-JSON-T-OBJECT <> IF
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    0 R@ _ATDDW.CANDIDATE-FLAGS !
    0 R@ _ATDDW.CANDIDATE-U !
    R@ _ATDD-PARSE-TOKEN-OBJECT
    DUP IF
        >R DROP R> R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ _ATDD-VM-MEMBERS
    DUP IF R> DROP 0 SWAP EXIT THEN DROP
    R@ _ATDDW.CANDIDATE-FLAGS @ _ATDD-C-ALL <> IF
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    R@ _ATDDW.CANDIDATE-U @ R@ _ATDDW.STAGE _ATDD.KEY-U !
    R@ _ATDDW.STAGE _ATDD.FLAGS @ _ATDD-F-KEY OR
        R@ _ATDDW.STAGE _ATDD.FLAGS !
    R> DROP -1 AT-DIDDOC-S-OK ;

: _ATDD-SELECT-VM  ( workspace -- status )
    >R
    R@ _ATDDW.PRESENT @ _ATDD-P-VERIFICATION AND 0= IF
        R> DROP AT-DIDDOC-S-KEY EXIT
    THEN
    R@ _ATDDW.VM-TYPE @ JOSE-JSON-T-ARRAY <> IF
        R> DROP AT-DIDDOC-S-KEY EXIT
    THEN
    R@ _ATDDW.VM-A @ R@ _ATDDW.VM-U @ R@ _ATDD-ARRAY-BIND
    DUP IF R> DROP EXIT THEN DROP
    BEGIN
        R@ _ATDD-ARRAY-NEXT
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        0= IF R> DROP AT-DIDDOC-S-KEY EXIT THEN
        R@ _ATDD-TRY-VM
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        IF R> DROP AT-DIDDOC-S-OK EXIT THEN
    AGAIN ;

\ =====================================================================
\  PDS service selection
\ =====================================================================

: _ATDD-PDS-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _ATDD-MEMBER-LOAD
    DUP IF NIP R> DROP EXIT THEN
    2DROP

    S" id" R@ _ATDD-NAME= IF
        R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING = IF
            R@ _ATDD-DECODE-SCRATCH
            DUP AT-DIDDOC-S-INTERNAL = IF R> DROP EXIT THEN
            0= IF
                S" #atproto_pds" R@ _ATDD-FRAGMENT-ID? IF
                    _ATDD-C-ID R@ _ATDD-SET-CANDIDATE
                THEN
            THEN
        THEN
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" type" R@ _ATDD-NAME= IF
        R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING = IF
            R@ _ATDD-DECODE-SCRATCH
            DUP AT-DIDDOC-S-INTERNAL = IF R> DROP EXIT THEN
            0= IF
                S" AtprotoPersonalDataServer"
                R@ _ATDD-SCRATCH= IF
                    _ATDD-C-TYPE R@ _ATDD-SET-CANDIDATE
                THEN
            THEN
        THEN
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    S" serviceEndpoint" R@ _ATDD-NAME= IF
        R@ _ATDDW.VALUE-TYPE @ JOSE-JSON-T-STRING = IF
            R@ _ATDD-DECODE-SCRATCH
            DUP AT-DIDDOC-S-INTERNAL = IF R> DROP EXIT THEN
            0= IF
                R@ _ATDDW.SCRATCH R@ _ATDDW.DECODED-U @
                R@ _ATDDW.STAGE _ATDD.TARGET HTARGET-PARSE
                HTARGET-S-OK = IF
                    R@ _ATDDW.STAGE _ATDD.TARGET
                    _ATDD-ORIGIN-TARGET? IF
                        _ATDD-PDS-ENDPOINT R@ _ATDD-SET-CANDIDATE
                    THEN
                THEN
            THEN
        THEN
        R> DROP AT-DIDDOC-S-OK EXIT
    THEN

    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-PDS-MEMBERS  ( count workspace -- status )
    SWAP 0 ?DO
        I OVER _ATDD-PDS-MEMBER
        DUP IF NIP UNLOOP EXIT THEN
        DROP
    LOOP
    DROP AT-DIDDOC-S-OK ;

: _ATDD-TRY-PDS  ( workspace -- selected? status )
    >R
    R@ _ATDDW.TOKEN-TYPE @ JOSE-JSON-T-OBJECT <> IF
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    0 R@ _ATDDW.CANDIDATE-FLAGS !
    R@ _ATDD-PARSE-TOKEN-OBJECT
    DUP IF
        >R DROP R> R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ _ATDD-PDS-MEMBERS
    DUP IF R> DROP 0 SWAP EXIT THEN DROP
    R@ _ATDDW.CANDIDATE-FLAGS @ _ATDD-PDS-ALL <> IF
        R> DROP 0 AT-DIDDOC-S-OK EXIT
    THEN
    R@ _ATDDW.STAGE _ATDD.FLAGS @ _ATDD-F-PDS OR
        R@ _ATDDW.STAGE _ATDD.FLAGS !
    R> DROP -1 AT-DIDDOC-S-OK ;

: _ATDD-SELECT-PDS  ( workspace -- status )
    >R
    R@ _ATDDW.PRESENT @ _ATDD-P-SERVICE AND 0= IF
        R> DROP AT-DIDDOC-S-PDS EXIT
    THEN
    R@ _ATDDW.SVC-TYPE @ JOSE-JSON-T-ARRAY <> IF
        R> DROP AT-DIDDOC-S-PDS EXIT
    THEN
    R@ _ATDDW.SVC-A @ R@ _ATDDW.SVC-U @ R@ _ATDD-ARRAY-BIND
    DUP IF R> DROP EXIT THEN DROP
    BEGIN
        R@ _ATDD-ARRAY-NEXT
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        0= IF R> DROP AT-DIDDOC-S-PDS EXIT THEN
        R@ _ATDD-TRY-PDS
        DUP IF
            >R DROP R> R> DROP EXIT
        THEN
        DROP
        IF R> DROP AT-DIDDOC-S-OK EXIT THEN
    AGAIN ;

\ =====================================================================
\  Staging, publication, and public parse
\ =====================================================================

: _ATDD-PARSE-STAGE  ( workspace -- status )
    >R
    R@ _ATDDW.SOURCE @ R@ _ATDDW.OBJECT-A !
    R@ _ATDDW.SOURCE @ R@ _ATDDW.SOURCE-U @
    R@ _ATDDW.DESCRIPTOR AT-DIDDOC-MAX-MEMBERS
    R@ _ATDDW.NAMES JOSE-JSON-MAX-NAME-BYTES
    R@ _ATDDW.JSON
    JOSE-JSON-OBJECT-PARSE
    _ATDD-JSON>STATUS
    DUP IF R> DROP EXIT THEN DROP

    R@ _ATDDW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    DROP
    0 R@ _ATDDW.PRESENT !
    R@ _ATDD-CAPTURE-TOP-ALL
    DUP IF R> DROP EXIT THEN DROP

    R@ _ATDDW.PRESENT @ _ATDD-P-ID AND 0= IF
        R> DROP AT-DIDDOC-S-ID EXIT
    THEN
    R@ _ATDD-SELECT-HANDLE
    DUP IF R> DROP EXIT THEN DROP
    R@ _ATDD-SELECT-VM
    DUP IF R> DROP EXIT THEN DROP
    R@ _ATDD-SELECT-PDS
    DUP IF R> DROP EXIT THEN DROP

    R@ _ATDDW.STAGE _ATDD.FLAGS @
        _ATDD-F-REQUIRED AND _ATDD-F-REQUIRED <> IF
        R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    0 R@ _ATDDW.STAGE _ATDD.RESERVED !
    _ATDD-MAGIC-VALUE R@ _ATDDW.STAGE _ATDD.MAGIC !
    R> DROP AT-DIDDOC-S-OK ;

: _ATDD-PARSE-ADMITTED
  ( source source-u expected expected-u document workspace -- status )
    DUP _ATDD-WIPE
    5 PICK OVER _ATDDW.SOURCE !
    4 PICK OVER _ATDDW.SOURCE-U !
    3 PICK OVER _ATDDW.EXPECTED !
    2 PICK OVER _ATDDW.EXPECTED-U !
    OVER OVER _ATDDW.OUTPUT !
    NIP NIP NIP NIP NIP
    _ATDD-PARSE-STAGE ;

: _ATDD-PUBLISH  ( workspace -- )
    0 OVER _ATDDW.OUTPUT @ _ATDD.MAGIC !
    DUP _ATDDW.STAGE 8 +
    OVER _ATDDW.OUTPUT @ 8 +
    AT-DIDDOC-SIZE 8 - MOVE
    _ATDD-MAGIC-VALUE OVER _ATDDW.OUTPUT @ _ATDD.MAGIC !
    DROP ;

: _ATDD-PARSE-CALL
  ( source source-u expected expected-u document workspace xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _ATDD-WIPE
        _ATDD-DROP6
        R> DROP AT-DIDDOC-S-INTERNAL EXIT
    THEN
    DROP
    DUP IF
        R@ _ATDD-WIPE
        R> DROP EXIT
    THEN
    DROP
    R@ ['] _ATDD-PUBLISH ['] _ATDD-WIPE
        _ATDD-CALL-FINALLY
    R> DROP
    AT-DIDDOC-S-OK ;

: AT-DIDDOC-PARSE
  ( source source-u expected expected-u document workspace -- status )
    5 PICK 5 PICK 5 PICK 5 PICK 5 PICK 5 PICK
    _ATDD-PARSE-GEOMETRY
    DUP IF
        >R _ATDD-DROP6 R> EXIT
    THEN
    DROP
    ['] _ATDD-PARSE-ADMITTED _ATDD-PARSE-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _ATDD-GEOMETRY-ABORT  ( -- )
    ." AT Protocol DID document geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _ATDD-GEOMETRY-ABORT
[THEN]

_ATDD-HANDLE-OFF 256 + _ATDD-KEY-OFF <> [IF]
    _ATDD-GEOMETRY-ABORT
[THEN]

_ATDD-TARGET-OFF HTARGET-SIZE + AT-DIDDOC-SIZE <> [IF]
    _ATDD-GEOMETRY-ABORT
[THEN]

_ATDD-SCRATCH-CAPACITY _ATDD-SCRATCH-STORAGE > [IF]
    _ATDD-GEOMETRY-ABORT
[THEN]

_ATDDW-SCRATCH-OFF _ATDD-SCRATCH-STORAGE +
AT-DIDDOC-WORKSPACE-SIZE <> [IF]
    _ATDD-GEOMETRY-ABORT
[THEN]
