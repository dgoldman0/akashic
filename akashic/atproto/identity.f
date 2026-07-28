\ =====================================================================
\  identity.f - Caller-owned AT Protocol identity and PDS discovery
\ =====================================================================
\  This module is the transport-neutral policy core for resolving one AT
\  Protocol handle or DID.  It owns no mutable module state and performs no
\  DNS, HTTP, TLS, clock, cache, OAuth, repository, or application work.
\  Instead, a caller drives an explicit action state machine and supplies
\  complete DNS or final HTTP responses.
\
\  Handle input uses DNS TXT first when `_atproto.<handle>` fits the DNS
\  presentation-name bound.  A validated direct DNS mapping is authoritative
\  and proceeds directly to DID-document resolution; HTTPS well-known is the
\  fallback.  Per-RR TXT values remain provisional until the iterator reaches
\  its validated terminal state.  Repeated identical `did=` values are
\  accepted, while distinct valid DID values are a conflict.
\
\  DID input resolves its document first.  A claimed handle is then checked
\  in the reverse direction, but a missing, disallowed, unresolved, or
\  mismatching handle does not discard the DID document.  Identity evidence
\  and participation readiness are deliberately separate: exact document ID
\  is sufficient to publish a resolved DID, while a usable signing key and
\  PDS endpoint are both required for participation readiness.
\
\  Production policy supports canonical `did:plc` identifiers and
\  hostname-level `did:web` identifiers.  Reserved handle TLDs, including
\  `.test`, fail resolution policy.  Development exceptions belong in an
\  explicit adapter, not in this production core.
\
\  Public API:
\    ATID-RESULT-SIZE
\    ATID-RESOLVER-SIZE
\    ATID-RESULT-INIT                 ( result -- status )
\    ATID-RESULT-VALID?               ( result -- flag )
\    ATID-RESULT-READY?               ( result -- flag )
\    ATID-RESOLVER-CLEAR              ( resolver -- status )
\    ATID-RESOLVER-VALID?             ( resolver -- flag )
\    ATID-BEGIN-HANDLE
\      ( handle-a handle-u result resolver -- status )
\    ATID-BEGIN-DID
\      ( did-a did-u result resolver -- status )
\    ATID-ACTION@                     ( resolver -- action status )
\    ATID-RESOLVER-STATUS@            ( resolver -- status )
\    ATID-DNS-NAME@                   ( resolver -- a u status )
\    ATID-DNS-QUERY-BUILD             ( unpredictable-id resolver -- status )
\    ATID-DNS-QUERY$                  ( resolver -- a u status )
\    ATID-HTTP-TARGET@                ( resolver -- target status )
\    ATID-DNS-RESPONSE!
\      ( response-a response-u resolver -- status )
\    ATID-HTTP-RESPONSE!
\      ( body-a body-u http-status redirect-count
\        final-target resolver -- status )
\    ATID-ACTION-FAIL                 ( resolver -- status )
\    ATID-DID@                        ( result -- a u status )
\    ATID-HANDLE@                     ( result -- a u status )
\    ATID-DOCUMENT@                   ( result -- document status )
\    ATID-PUBLIC-KEY-MULTIBASE@       ( result -- a u status )
\    ATID-PDS-TARGET@                 ( result -- target status )
\    ATID-PDS-ORIGIN@                 ( result -- a u status )
\    ATID-EVIDENCE@                   ( result -- evidence status )
\    ATID-PARTICIPATION-STATUS        ( result -- status )
\    ATID-PARTICIPATION-READY?        ( result -- flag )
\    ATID-RESOLVER-WIPE               ( resolver -- status )
\ =====================================================================

PROVIDED akashic-atproto-identity

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE ../net/http-target.f
REQUIRE ../net/dns-txt.f
REQUIRE did.f
REQUIRE handle.f
REQUIRE did-document.f

\ =====================================================================
\  Public bounds, actions, statuses, and evidence
\ =====================================================================

244 CONSTANT ATID-DNS-HANDLE-MAX
8   CONSTANT ATID-DNS-CNAME-MAX
3   CONSTANT ATID-HTTP-REDIRECT-MAX
64  CONSTANT ATID-WELL-KNOWN-TRIM-MAX

0 CONSTANT ATID-A-NONE
1 CONSTANT ATID-A-DNS-QUERY
2 CONSTANT ATID-A-DNS-EXCHANGE
3 CONSTANT ATID-A-HANDLE-HTTPS
4 CONSTANT ATID-A-DID-DOCUMENT
5 CONSTANT ATID-A-DONE
6 CONSTANT ATID-A-FAILED

: ATID-ACTION-VALID?  ( action -- flag )
    DUP ATID-A-NONE >= SWAP ATID-A-FAILED <= AND ;

0  CONSTANT ATID-S-OK
1  CONSTANT ATID-S-INVALID
2  CONSTANT ATID-S-CAPACITY
3  CONSTANT ATID-S-ALIAS
4  CONSTANT ATID-S-SYNTAX
5  CONSTANT ATID-S-POLICY
6  CONSTANT ATID-S-METHOD
7  CONSTANT ATID-S-STATE
8  CONSTANT ATID-S-DNS
9  CONSTANT ATID-S-HTTP
10 CONSTANT ATID-S-DOCUMENT
11 CONSTANT ATID-S-MISMATCH
12 CONSTANT ATID-S-UNRESOLVED
13 CONSTANT ATID-S-CONFLICT
14 CONSTANT ATID-S-LOOP
15 CONSTANT ATID-S-KEY
16 CONSTANT ATID-S-PDS
17 CONSTANT ATID-S-MISSING
18 CONSTANT ATID-S-INTERNAL
19 CONSTANT ATID-S-RANGE
20 CONSTANT ATID-S-PROTECTED
21 CONSTANT ATID-S-PLATFORM

: ATID-STATUS-VALID?  ( status -- flag )
    DUP ATID-S-OK >= SWAP ATID-S-PLATFORM <= AND ;

1    CONSTANT ATID-E-INPUT-HANDLE
2    CONSTANT ATID-E-INPUT-DID
4    CONSTANT ATID-E-HANDLE-DNS
8    CONSTANT ATID-E-HANDLE-HTTPS
16   CONSTANT ATID-E-DOCUMENT-ID
32   CONSTANT ATID-E-HANDLE-VERIFIED
64   CONSTANT ATID-E-HANDLE-MISSING
128  CONSTANT ATID-E-HANDLE-INVALID
256  CONSTANT ATID-E-KEY
512  CONSTANT ATID-E-PDS
1024 CONSTANT ATID-E-PARTICIPATION

2047 CONSTANT _ATID-E-ALL
ATID-E-INPUT-HANDLE ATID-E-INPUT-DID OR
    CONSTANT _ATID-E-INPUT
ATID-E-HANDLE-DNS ATID-E-HANDLE-HTTPS OR
    CONSTANT _ATID-E-MAPPING
ATID-E-HANDLE-VERIFIED ATID-E-HANDLE-MISSING OR
ATID-E-HANDLE-INVALID OR CONSTANT _ATID-E-HANDLE-STATE

0 CONSTANT _ATID-MODE-NONE
1 CONSTANT _ATID-MODE-HANDLE
2 CONSTANT _ATID-MODE-DID

0 CONSTANT _ATID-PHASE-IDLE
1 CONSTANT _ATID-PHASE-DNS
2 CONSTANT _ATID-PHASE-HANDLE-HTTPS
3 CONSTANT _ATID-PHASE-DID-DOCUMENT
4 CONSTANT _ATID-PHASE-DONE
5 CONSTANT _ATID-PHASE-FAILED

\ =====================================================================
\  Caller-owned resolved result
\ =====================================================================

0x4154494452455331 CONSTANT _ATIDR-MAGIC-VALUE  \ "ATIDRES1"

 0 CONSTANT _ATIDR-MAGIC
 8 CONSTANT _ATIDR-PHASE
16 CONSTANT _ATIDR-EVIDENCE
24 CONSTANT _ATIDR-RESERVED
32 CONSTANT _ATIDR-DOCUMENT

_ATIDR-DOCUMENT AT-DIDDOC-SIZE + CONSTANT ATID-RESULT-SIZE

: _ATIDR.MAGIC     ( result -- a ) _ATIDR-MAGIC + ;
: _ATIDR.PHASE     ( result -- a ) _ATIDR-PHASE + ;
: _ATIDR.EVIDENCE  ( result -- a ) _ATIDR-EVIDENCE + ;
: _ATIDR.RESERVED  ( result -- a ) _ATIDR-RESERVED + ;
: _ATIDR.DOCUMENT  ( result -- a ) _ATIDR-DOCUMENT + ;

\ =====================================================================
\  Caller-owned resolver geometry
\ =====================================================================

0x41544944574F5231 CONSTANT _ATIDW-MAGIC-VALUE  \ "ATIDWOR1"

  0 CONSTANT _ATIDW-MAGIC
  8 CONSTANT _ATIDW-PHASE
 16 CONSTANT _ATIDW-MODE
 24 CONSTANT _ATIDW-ACTION
 32 CONSTANT _ATIDW-STATUS
 40 CONSTANT _ATIDW-RESULT
 48 CONSTANT _ATIDW-EVIDENCE
 56 CONSTANT _ATIDW-DNS-ID
 64 CONSTANT _ATIDW-DNS-STATUS
 72 CONSTANT _ATIDW-HTTP-STATUS
 80 CONSTANT _ATIDW-DID-U
 88 CONSTANT _ATIDW-HANDLE-U
 96 CONSTANT _ATIDW-DNS-DID-U
104 CONSTANT _ATIDW-DNS-CANDIDATES
112 CONSTANT _ATIDW-DNS-CONFLICT
120 CONSTANT _ATIDW-CNAME-COUNT
128 CONSTANT _ATIDW-NAME-U
136 CONSTANT _ATIDW-URI-U
144 CONSTANT _ATIDW-PREV-DNS-ID
152 CONSTANT _ATIDW-RESERVED1
160 CONSTANT _ATIDW-HEADER-SIZE

_ATIDW-HEADER-SIZE CONSTANT _ATIDW-DID-OFF
_ATIDW-DID-OFF DID-LENGTH-MAX + CONSTANT _ATIDW-HANDLE-OFF
_ATIDW-HANDLE-OFF 256 + CONSTANT _ATIDW-DNS-DID-OFF
_ATIDW-DNS-DID-OFF DID-LENGTH-MAX + CONSTANT _ATIDW-NAME-OFF
_ATIDW-NAME-OFF 256 + CONSTANT _ATIDW-URI-OFF
_ATIDW-URI-OFF HTARGET-URI-CAPACITY + CONSTANT _ATIDW-CNAME-OFF
_ATIDW-CNAME-OFF ATID-DNS-CNAME-MAX 1+ 256 * +
    CONSTANT _ATIDW-TARGET-OFF
_ATIDW-TARGET-OFF HTARGET-SIZE + CONSTANT _ATIDW-QUERY-OFF
_ATIDW-QUERY-OFF DNS-TXT-QUERY-SIZE + CONSTANT _ATIDW-RR-VALUE-OFF
_ATIDW-RR-VALUE-OFF DNS-TXT-VALUE-MAX + CONSTANT _ATIDW-RR-OFF
_ATIDW-RR-OFF DNS-TXT-RR-RESULT-SIZE + CONSTANT _ATIDW-ITER-OFF
_ATIDW-ITER-OFF DNS-TXT-ITER-SIZE + CONSTANT _ATIDW-CNAME-RESULT-OFF
_ATIDW-CNAME-RESULT-OFF DNS-TXT-CNAME-RESULT-SIZE +
    CONSTANT _ATIDW-DOCUMENT-OFF
_ATIDW-DOCUMENT-OFF AT-DIDDOC-SIZE + CONSTANT _ATIDW-DIDDOC-WORK-OFF
_ATIDW-DIDDOC-WORK-OFF AT-DIDDOC-WORKSPACE-SIZE +
    CONSTANT ATID-RESOLVER-SIZE

: _ATIDW.MAGIC          ( w -- a ) _ATIDW-MAGIC + ;
: _ATIDW.PHASE          ( w -- a ) _ATIDW-PHASE + ;
: _ATIDW.MODE           ( w -- a ) _ATIDW-MODE + ;
: _ATIDW.ACTION         ( w -- a ) _ATIDW-ACTION + ;
: _ATIDW.STATUS         ( w -- a ) _ATIDW-STATUS + ;
: _ATIDW.RESULT         ( w -- a ) _ATIDW-RESULT + ;
: _ATIDW.EVIDENCE       ( w -- a ) _ATIDW-EVIDENCE + ;
: _ATIDW.DNS-ID         ( w -- a ) _ATIDW-DNS-ID + ;
: _ATIDW.DNS-STATUS     ( w -- a ) _ATIDW-DNS-STATUS + ;
: _ATIDW.HTTP-STATUS    ( w -- a ) _ATIDW-HTTP-STATUS + ;
: _ATIDW.DID-U          ( w -- a ) _ATIDW-DID-U + ;
: _ATIDW.HANDLE-U       ( w -- a ) _ATIDW-HANDLE-U + ;
: _ATIDW.DNS-DID-U      ( w -- a ) _ATIDW-DNS-DID-U + ;
: _ATIDW.DNS-CANDIDATES ( w -- a ) _ATIDW-DNS-CANDIDATES + ;
: _ATIDW.DNS-CONFLICT   ( w -- a ) _ATIDW-DNS-CONFLICT + ;
: _ATIDW.CNAME-COUNT    ( w -- a ) _ATIDW-CNAME-COUNT + ;
: _ATIDW.NAME-U         ( w -- a ) _ATIDW-NAME-U + ;
: _ATIDW.URI-U          ( w -- a ) _ATIDW-URI-U + ;
: _ATIDW.PREV-DNS-ID    ( w -- a ) _ATIDW-PREV-DNS-ID + ;
: _ATIDW.RESERVED1      ( w -- a ) _ATIDW-RESERVED1 + ;
: _ATIDW.DID            ( w -- a ) _ATIDW-DID-OFF + ;
: _ATIDW.HANDLE         ( w -- a ) _ATIDW-HANDLE-OFF + ;
: _ATIDW.DNS-DID        ( w -- a ) _ATIDW-DNS-DID-OFF + ;
: _ATIDW.NAME           ( w -- a ) _ATIDW-NAME-OFF + ;
: _ATIDW.URI            ( w -- a ) _ATIDW-URI-OFF + ;
: _ATIDW.CNAME          ( index w -- a )
    _ATIDW-CNAME-OFF + SWAP 256 * + ;
: _ATIDW.TARGET         ( w -- a ) _ATIDW-TARGET-OFF + ;
: _ATIDW.QUERY          ( w -- a ) _ATIDW-QUERY-OFF + ;
: _ATIDW.RR-VALUE       ( w -- a ) _ATIDW-RR-VALUE-OFF + ;
: _ATIDW.RR             ( w -- a ) _ATIDW-RR-OFF + ;
: _ATIDW.ITER           ( w -- a ) _ATIDW-ITER-OFF + ;
: _ATIDW.CNAME-RESULT   ( w -- a ) _ATIDW-CNAME-RESULT-OFF + ;
: _ATIDW.DOCUMENT       ( w -- a ) _ATIDW-DOCUMENT-OFF + ;
: _ATIDW.DIDDOC-WORK    ( w -- a ) _ATIDW-DIDDOC-WORK-OFF + ;

\ =====================================================================
\  Generic admission and stack helpers
\ =====================================================================

: _ATID-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _ATID-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;
: _ATID-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;
: _ATID-DROP6  ( x1 x2 x3 x4 x5 x6 -- ) 2DROP 2DROP 2DROP ;

: _ATID-RETURN3  ( x1 x2 x3 status -- status )
    >R _ATID-DROP3 R> ;

: _ATID-RETURN4  ( x1 x2 x3 x4 status -- status )
    >R _ATID-DROP4 R> ;

: _ATID-RETURN5  ( x1 x2 x3 x4 x5 status -- status )
    >R _ATID-DROP5 R> ;

: _ATID-RETURN6  ( x1 x2 x3 x4 x5 x6 status -- status )
    >R _ATID-DROP6 R> ;

: _ATID-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP ATID-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF DROP ATID-S-RANGE EXIT THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP ATID-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP ATID-S-PLATFORM EXIT
    THEN
    DROP ATID-S-PLATFORM ;

: _ATID-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP ATID-S-INVALID EXIT THEN
    DUP 0= IF 2DROP ATID-S-OK EXIT THEN
    OVER 0= IF 2DROP ATID-S-INVALID EXIT THEN
    CALLER-SPAN-STATUS _ATID-CALLER>STATUS ;

: _ATID-FIXED-STATUS  ( address size -- status )
    OVER 0= IF 2DROP ATID-S-INVALID EXIT THEN
    OVER 7 AND IF 2DROP ATID-S-INVALID EXIT THEN
    _ATID-SPAN-STATUS ;

: _ATID-RESULT-STATUS  ( result -- status )
    ATID-RESULT-SIZE _ATID-FIXED-STATUS ;

: _ATID-RESOLVER-STATUS  ( resolver -- status )
    ATID-RESOLVER-SIZE _ATID-FIXED-STATUS ;

: _ATID-HTTP-STATUS?  ( status -- flag )
    DUP 100 >= SWAP 599 <= AND ;

: _ATID-HTTP-SUCCESS?  ( status -- flag )
    DUP 200 >= SWAP 299 <= AND ;

: _ATID-BIT?  ( value bit -- flag )
    AND 0<> ;

: _ATID-EVIDENCE+  ( bit resolver -- )
    _ATIDW.EVIDENCE DUP @ ROT OR SWAP ! ;

: _ATID-EVIDENCE-COUNT  ( evidence mask -- count )
    AND DUP 0= IF DROP 0 EXIT THEN
    DUP DUP 1- AND 0= IF DROP 1 EXIT THEN
    DROP 2 ;

\ =====================================================================
\  Production handle and DID resolution policy
\ =====================================================================

: _ATID-LOWER?  ( byte -- flag )
    [CHAR] a [CHAR] z 1+ WITHIN ;

: _ATID-PLC-BYTE?  ( byte -- flag )
    DUP _ATID-LOWER? IF DROP -1 EXIT THEN
    [CHAR] 2 [CHAR] 7 1+ WITHIN ;

: _ATID-LAST-DOT  ( address length -- index|-1 )
    -1 >R
    0
    BEGIN
        DUP 2 PICK U<
    WHILE
        2 PICK OVER + C@ [CHAR] . = IF
            DUP R> DROP >R
        THEN
        1+
    REPEAT
    DROP 2DROP R> ;

: _ATID-TLD$  ( address length -- tld-a tld-u )
    2DUP _ATID-LAST-DOT
    DUP 0< IF DROP EXIT THEN
    1+ /STRING ;

: _ATID-RESERVED-TLD?  ( handle-a handle-u -- flag )
    _ATID-TLD$
    2DUP S" alt" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" arpa" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" example" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" internal" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" invalid" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" local" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" localhost" COMPARE 0= IF 2DROP -1 EXIT THEN
    2DUP S" onion" COMPARE 0= IF 2DROP -1 EXIT THEN
    S" test" COMPARE 0= ;

: _ATID-HANDLE-POLICY  ( handle-a handle-u -- status )
    2DUP AT-HANDLE-NORMALIZED?
    DUP AT-HANDLE-S-OK <> IF
        >R DROP 2DROP R> DROP ATID-S-SYNTAX EXIT
    THEN
    DROP 0= IF 2DROP ATID-S-SYNTAX EXIT THEN
    _ATID-RESERVED-TLD? IF ATID-S-POLICY ELSE ATID-S-OK THEN ;

: _ATID-PLC-PREFIX?  ( did-a did-u -- flag )
    DUP 8 < IF 2DROP 0 EXIT THEN
    OVER 8 S" did:plc:" COMPARE 0=
    >R 2DROP R> ;

: _ATID-WEB-PREFIX?  ( did-a did-u -- flag )
    DUP 8 < IF 2DROP 0 EXIT THEN
    OVER 8 S" did:web:" COMPARE 0=
    >R 2DROP R> ;

: _ATID-PLC-PROFILE  ( did-a did-u -- status )
    DUP 32 <> IF 2DROP ATID-S-SYNTAX EXIT THEN
    8 /STRING
    BEGIN DUP WHILE
        OVER C@ _ATID-PLC-BYTE? 0= IF
            2DROP ATID-S-SYNTAX EXIT
        THEN
        1 /STRING
    REPEAT
    2DROP ATID-S-OK ;

: _ATID-WEB-PROFILE  ( did-a did-u -- status )
    8 /STRING
    2DUP _ATID-HANDLE-POLICY
    >R 2DROP R> ;

: _ATID-DID-PROFILE  ( did-a did-u -- status )
    2DUP DID-VALIDATE DID-S-OK <> IF
        2DROP ATID-S-SYNTAX EXIT
    THEN
    2DUP _ATID-PLC-PREFIX? IF
        _ATID-PLC-PROFILE EXIT
    THEN
    2DUP _ATID-WEB-PREFIX? IF
        _ATID-WEB-PROFILE EXIT
    THEN
    2DROP ATID-S-METHOD ;

\ =====================================================================
\  Resolved result lifecycle and evidence invariants
\ =====================================================================

: _ATID-RESULT-EMPTY?  ( result -- flag )
    DUP _ATIDR.PHASE @ 0=
    OVER _ATIDR.EVIDENCE @ 0= AND
    SWAP _ATIDR.RESERVED @ 0= AND ;

: _ATID-DIDDOC-EVIDENCE  ( document -- h-e k-e p-e valid? )
    AT-DIDDOC-EVIDENCE@
    DUP AT-DIDDOC-S-OK <> IF
        _ATID-DROP5 0 0 0 0 EXIT
    THEN
    DROP
    >R >R
    NIP
    R> R> -1 ;

: _ATID-RESULT-EVIDENCE?  ( result -- flag )
    >R
    R@ _ATIDR.EVIDENCE @ DUP _ATID-E-ALL INVERT AND IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _ATID-E-INPUT _ATID-EVIDENCE-COUNT 1 <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _ATID-E-HANDLE-STATE _ATID-EVIDENCE-COUNT 1 <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP ATID-E-DOCUMENT-ID _ATID-BIT? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP ATID-E-INPUT-HANDLE _ATID-BIT? IF
        DUP ATID-E-HANDLE-VERIFIED _ATID-BIT? 0= IF
            DROP R> DROP 0 EXIT
        THEN
    THEN
    DUP ATID-E-HANDLE-VERIFIED _ATID-BIT? IF
        DUP _ATID-E-MAPPING _ATID-EVIDENCE-COUNT 1 <> IF
            DROP R> DROP 0 EXIT
        THEN
    ELSE
        DUP _ATID-E-MAPPING AND IF DROP R> DROP 0 EXIT THEN
    THEN
    DUP ATID-E-KEY _ATID-BIT?
    OVER ATID-E-PDS _ATID-BIT? AND
    OVER ATID-E-PARTICIPATION _ATID-BIT? <> IF
        DROP R> DROP 0 EXIT
    THEN
    R> _ATIDR.DOCUMENT _ATID-DIDDOC-EVIDENCE
    0= IF _ATID-DROP4 0 EXIT THEN
    >R >R >R
    DUP ATID-E-HANDLE-VERIFIED _ATID-BIT? IF
        R> AT-DIDDOC-E-VALID <> IF
            R> DROP R> DROP DROP 0 EXIT
        THEN
    ELSE
        DUP ATID-E-HANDLE-MISSING _ATID-BIT? IF
            R> AT-DIDDOC-E-MISSING <> IF
                R> DROP R> DROP DROP 0 EXIT
            THEN
        ELSE
            R> AT-DIDDOC-E-VALID <> IF
                R> DROP R> DROP DROP 0 EXIT
            THEN
        THEN
    THEN
    DUP ATID-E-KEY _ATID-BIT?
    R> AT-DIDDOC-E-VALID = <> IF
        R> DROP DROP 0 EXIT
    THEN
    ATID-E-PDS _ATID-BIT?
    R> AT-DIDDOC-E-VALID = <>
    0= ;

: _ATID-RESULT-READY-VALID?  ( result -- flag )
    DUP _ATIDR.PHASE @ 1 <> IF DROP 0 EXIT THEN
    DUP _ATIDR.RESERVED @ IF DROP 0 EXIT THEN
    DUP _ATIDR.DOCUMENT AT-DIDDOC-VALID? 0= IF DROP 0 EXIT THEN
    DUP _ATIDR.DOCUMENT AT-DIDDOC-DID@
    DUP AT-DIDDOC-S-OK <> IF
        _ATID-DROP4 0 EXIT
    THEN
    DROP _ATID-DID-PROFILE ATID-S-OK <> IF DROP 0 EXIT THEN
    _ATID-RESULT-EVIDENCE? ;

: ATID-RESULT-VALID?  ( result -- flag )
    DUP _ATID-RESULT-STATUS ?DUP IF 2DROP 0 EXIT THEN
    DUP _ATIDR.MAGIC @ _ATIDR-MAGIC-VALUE <> IF DROP 0 EXIT THEN
    DUP _ATIDR.PHASE @ 0= IF _ATID-RESULT-EMPTY? EXIT THEN
    _ATID-RESULT-READY-VALID? ;

: ATID-RESULT-READY?  ( result -- flag )
    DUP ATID-RESULT-VALID? IF
        _ATIDR.PHASE @ 1 =
    ELSE
        DROP 0
    THEN ;

: ATID-RESULT-INIT  ( result -- status )
    DUP _ATID-RESULT-STATUS ?DUP IF NIP EXIT THEN
    DUP ATID-RESULT-SIZE 0 FILL
    _ATIDR-MAGIC-VALUE OVER _ATIDR.MAGIC !
    DROP ATID-S-OK ;

\ =====================================================================
\  Resolver lifecycle and corruption invariants
\ =====================================================================

: _ATIDW-IDLE?  ( resolver -- flag )
    DUP _ATIDW.PHASE @ _ATID-PHASE-IDLE =
    OVER _ATIDW.MODE @ _ATID-MODE-NONE = AND
    OVER _ATIDW.ACTION @ ATID-A-NONE = AND
    OVER _ATIDW.STATUS @ ATID-S-OK = AND
    OVER _ATIDW.RESULT @ 0= AND
    OVER _ATIDW.EVIDENCE @ 0= AND
    OVER _ATIDW.DID-U @ 0= AND
    OVER _ATIDW.HANDLE-U @ 0= AND
    OVER _ATIDW.DNS-DID-U @ 0= AND
    OVER _ATIDW.CNAME-COUNT @ 0= AND
    OVER _ATIDW.NAME-U @ 0= AND
    OVER _ATIDW.URI-U @ 0= AND
    OVER _ATIDW.PREV-DNS-ID @ -1 = AND
    SWAP _ATIDW.RESERVED1 @ 0= AND ;

: _ATIDW-RESULT-DISJOINT?  ( resolver -- flag )
    DUP _ATIDW.RESULT @ DUP 0= IF 2DROP 0 EXIT THEN
    ATID-RESULT-SIZE
    2 PICK ATID-RESOLVER-SIZE MSPAN-OVERLAP? 0=
    NIP ;

: _ATIDW-CONTENT?  ( resolver -- flag )
    DUP _ATIDW.EVIDENCE @ DUP 0<
    SWAP _ATID-E-ALL INVERT AND 0<> OR IF DROP 0 EXIT THEN
    DUP _ATIDW.DNS-ID @ DUP -1 <
    SWAP 65535 > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.DNS-STATUS @ DNS-TXT-STATUS-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP _ATIDW.HTTP-STATUS @ DUP 0<>
    SWAP _ATID-HTTP-STATUS? 0= AND IF DROP 0 EXIT THEN
    DUP _ATIDW.DID-U @ DUP 0<
    SWAP DID-LENGTH-MAX > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.DID-U @ IF
        DUP _ATIDW.DID OVER _ATIDW.DID-U @
        _ATID-DID-PROFILE ATID-S-OK <> IF DROP 0 EXIT THEN
    THEN
    DUP _ATIDW.HANDLE-U @ DUP 0<
    SWAP AT-HANDLE-LENGTH-MAX > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.HANDLE-U @ IF
        DUP _ATIDW.HANDLE OVER _ATIDW.HANDLE-U @
        _ATID-HANDLE-POLICY ATID-S-OK <> IF DROP 0 EXIT THEN
    THEN
    DUP _ATIDW.DNS-DID-U @ DUP 0<
    SWAP DID-LENGTH-MAX > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.DNS-DID-U @ IF
        DUP _ATIDW.DNS-DID OVER _ATIDW.DNS-DID-U @
        DID-VALID? 0= IF DROP 0 EXIT THEN
    THEN
    DUP _ATIDW.DNS-CANDIDATES @ DUP 0<
    SWAP 65535 > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.DNS-CONFLICT @ DUP 0<>
    SWAP -1 <> AND IF DROP 0 EXIT THEN
    DUP _ATIDW.CNAME-COUNT @ DUP 0<
    SWAP ATID-DNS-CNAME-MAX > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.NAME-U @ DUP 0<
    SWAP DNS-TXT-NAME-MAX > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.URI-U @ DUP 0<
    SWAP HTARGET-URI-CAPACITY > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.PREV-DNS-ID @ DUP -1 <
    SWAP 65535 > OR IF DROP 0 EXIT THEN
    _ATIDW.RESERVED1 @ 0= ;

: _ATIDW-ACTIVE-RESULT?  ( resolver -- flag )
    DUP _ATIDW-RESULT-DISJOINT? 0= IF DROP 0 EXIT THEN
    _ATIDW.RESULT @
    DUP ATID-RESULT-VALID?
    SWAP ATID-RESULT-READY? 0= AND ;

: _ATIDW-DNS-PHASE?  ( resolver -- flag )
    DUP _ATIDW.PHASE @ _ATID-PHASE-DNS <> IF DROP 0 EXIT THEN
    DUP _ATIDW.ACTION @ DUP ATID-A-DNS-QUERY =
    SWAP ATID-A-DNS-EXCHANGE = OR 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.STATUS @ ATID-S-OK <> IF DROP 0 EXIT THEN
    DUP _ATIDW.HANDLE-U @ 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.NAME-U @ 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.NAME OVER _ATIDW.NAME-U @
    DNS-TXT-NAME-VALIDATE DNS-TXT-S-OK <> IF DROP 0 EXIT THEN
    DUP _ATIDW.ACTION @ ATID-A-DNS-EXCHANGE = IF
        DUP _ATIDW.DNS-ID @ 0< IF DROP 0 EXIT THEN
        DUP _ATIDW.QUERY DNS-TXT-QUERY-VALID? 0= IF DROP 0 EXIT THEN
    ELSE
        DUP _ATIDW.DNS-ID @ -1 <> IF DROP 0 EXIT THEN
    THEN
    _ATIDW-ACTIVE-RESULT? ;

: _ATIDW-HANDLE-HTTP-PHASE?  ( resolver -- flag )
    DUP _ATIDW.PHASE @ _ATID-PHASE-HANDLE-HTTPS <>
        IF DROP 0 EXIT THEN
    DUP _ATIDW.ACTION @ ATID-A-HANDLE-HTTPS <>
        IF DROP 0 EXIT THEN
    DUP _ATIDW.STATUS @ ATID-S-OK <> IF DROP 0 EXIT THEN
    DUP _ATIDW.HANDLE-U @ 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.TARGET HTARGET-VALID? 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.TARGET HTARGET-REQUEST-TARGET$
    S" /.well-known/atproto-did" COMPARE IF DROP 0 EXIT THEN
    _ATIDW-ACTIVE-RESULT? ;

: _ATIDW-DIDDOC-PHASE?  ( resolver -- flag )
    DUP _ATIDW.PHASE @ _ATID-PHASE-DID-DOCUMENT <>
        IF DROP 0 EXIT THEN
    DUP _ATIDW.ACTION @ ATID-A-DID-DOCUMENT <>
        IF DROP 0 EXIT THEN
    DUP _ATIDW.STATUS @ ATID-S-OK <> IF DROP 0 EXIT THEN
    DUP _ATIDW.DID-U @ 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.TARGET HTARGET-VALID? 0= IF DROP 0 EXIT THEN
    _ATIDW-ACTIVE-RESULT? ;

: _ATIDW-DONE-PHASE?  ( resolver -- flag )
    DUP _ATIDW.PHASE @ _ATID-PHASE-DONE <> IF DROP 0 EXIT THEN
    DUP _ATIDW.ACTION @ ATID-A-DONE <> IF DROP 0 EXIT THEN
    DUP _ATIDW.STATUS @ ATID-S-OK <> IF DROP 0 EXIT THEN
    DUP _ATIDW-RESULT-DISJOINT? 0= IF DROP 0 EXIT THEN
    _ATIDW.RESULT @ ATID-RESULT-READY? ;

: _ATIDW-FAILED-PHASE?  ( resolver -- flag )
    DUP _ATIDW.PHASE @ _ATID-PHASE-FAILED <>
        IF DROP 0 EXIT THEN
    DUP _ATIDW.ACTION @ ATID-A-FAILED <> IF DROP 0 EXIT THEN
    DUP _ATIDW.STATUS @ DUP ATID-S-OK =
    SWAP ATID-STATUS-VALID? 0= OR IF DROP 0 EXIT THEN
    _ATIDW-ACTIVE-RESULT? ;

: ATID-RESOLVER-VALID?  ( resolver -- flag )
    DUP _ATID-RESOLVER-STATUS ?DUP IF 2DROP 0 EXIT THEN
    DUP _ATIDW.MAGIC @ _ATIDW-MAGIC-VALUE <> IF DROP 0 EXIT THEN
    DUP _ATIDW.PHASE @ DUP _ATID-PHASE-IDLE <
    SWAP _ATID-PHASE-FAILED > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.MODE @ DUP _ATID-MODE-NONE <
    SWAP _ATID-MODE-DID > OR IF DROP 0 EXIT THEN
    DUP _ATIDW.ACTION @ ATID-ACTION-VALID? 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.STATUS @ ATID-STATUS-VALID? 0= IF DROP 0 EXIT THEN
    DUP _ATIDW-CONTENT? 0= IF DROP 0 EXIT THEN
    DUP _ATIDW.PHASE @ _ATID-PHASE-IDLE = IF
        _ATIDW-IDLE? EXIT
    THEN
    DUP _ATIDW.MODE @ _ATID-MODE-NONE = IF DROP 0 EXIT THEN
    DUP _ATIDW.PHASE @ _ATID-PHASE-DNS = IF
        _ATIDW-DNS-PHASE? EXIT
    THEN
    DUP _ATIDW.PHASE @ _ATID-PHASE-HANDLE-HTTPS = IF
        _ATIDW-HANDLE-HTTP-PHASE? EXIT
    THEN
    DUP _ATIDW.PHASE @ _ATID-PHASE-DID-DOCUMENT = IF
        _ATIDW-DIDDOC-PHASE? EXIT
    THEN
    DUP _ATIDW.PHASE @ _ATID-PHASE-DONE = IF
        _ATIDW-DONE-PHASE? EXIT
    THEN
    _ATIDW-FAILED-PHASE? ;

: ATID-RESOLVER-CLEAR  ( resolver -- status )
    DUP _ATID-RESOLVER-STATUS ?DUP IF NIP EXIT THEN
    DUP ATID-RESOLVER-SIZE 0 FILL
    -1 OVER _ATIDW.DNS-ID !
    -1 OVER _ATIDW.PREV-DNS-ID !
    _ATIDW-MAGIC-VALUE OVER _ATIDW.MAGIC !
    DROP ATID-S-OK ;

\ =====================================================================
\  URI, target, and transition construction
\ =====================================================================

: _ATID-URI-RESET  ( resolver -- )
    DUP _ATIDW.URI HTARGET-URI-CAPACITY 0 FILL
    0 SWAP _ATIDW.URI-U ! ;

: _ATID-URI+  ( source-a source-u resolver -- status )
    >R
    DUP R@ _ATIDW.URI-U @ +
    HTARGET-URI-CAPACITY U> IF
        2DROP R> DROP ATID-S-CAPACITY EXIT
    THEN
    OVER
    R@ _ATIDW.URI R@ _ATIDW.URI-U @ +
    2 PICK CMOVE
    DUP R@ _ATIDW.URI-U +!
    2DROP R> DROP ATID-S-OK ;

: _ATID-TARGET-SEAL  ( resolver -- status )
    DUP _ATIDW.URI OVER _ATIDW.URI-U @
    2 PICK _ATIDW.TARGET HTARGET-PARSE
    HTARGET-S-OK <> IF DROP ATID-S-INTERNAL EXIT THEN
    DROP ATID-S-OK ;

: _ATID-BUILD-HANDLE-TARGET  ( resolver -- status )
    >R
    R@ _ATID-URI-RESET
    S" https://" R@ _ATID-URI+ ?DUP IF R> DROP EXIT THEN
    R@ _ATIDW.HANDLE R@ _ATIDW.HANDLE-U @
    R@ _ATID-URI+ ?DUP IF R> DROP EXIT THEN
    S" /.well-known/atproto-did"
    R@ _ATID-URI+ ?DUP IF R> DROP EXIT THEN
    R> _ATID-TARGET-SEAL ;

: _ATID-BUILD-PLC-TARGET  ( resolver -- status )
    >R
    R@ _ATID-URI-RESET
    S" https://plc.directory/" R@ _ATID-URI+
    ?DUP IF R> DROP EXIT THEN
    R@ _ATIDW.DID R@ _ATIDW.DID-U @
    R@ _ATID-URI+ ?DUP IF R> DROP EXIT THEN
    R> _ATID-TARGET-SEAL ;

: _ATID-BUILD-WEB-TARGET  ( resolver -- status )
    >R
    R@ _ATID-URI-RESET
    S" https://" R@ _ATID-URI+ ?DUP IF R> DROP EXIT THEN
    R@ _ATIDW.DID R@ _ATIDW.DID-U @ 8 /STRING
    R@ _ATID-URI+ ?DUP IF R> DROP EXIT THEN
    S" /.well-known/did.json"
    R@ _ATID-URI+ ?DUP IF R> DROP EXIT THEN
    R> _ATID-TARGET-SEAL ;

: _ATID-BUILD-DID-TARGET  ( resolver -- status )
    DUP _ATIDW.DID OVER _ATIDW.DID-U @
    2DUP _ATID-PLC-PREFIX? IF
        2DROP _ATID-BUILD-PLC-TARGET EXIT
    THEN
    _ATID-WEB-PREFIX? IF
        _ATID-BUILD-WEB-TARGET
    ELSE
        DROP ATID-S-METHOD
    THEN ;

: _ATID-FAIL  ( status resolver -- status )
    >R
    DUP R@ _ATIDW.STATUS !
    _ATID-PHASE-FAILED R@ _ATIDW.PHASE !
    ATID-A-FAILED R@ _ATIDW.ACTION !
    R> DROP ;

: _ATID-START-HANDLE-HTTPS  ( resolver -- status )
    DUP _ATID-BUILD-HANDLE-TARGET ?DUP IF
        SWAP _ATID-FAIL EXIT
    THEN
    _ATID-PHASE-HANDLE-HTTPS OVER _ATIDW.PHASE !
    ATID-A-HANDLE-HTTPS SWAP _ATIDW.ACTION !
    ATID-S-OK ;

: _ATID-START-DID-DOCUMENT  ( resolver -- status )
    DUP _ATID-BUILD-DID-TARGET ?DUP IF
        SWAP _ATID-FAIL EXIT
    THEN
    _ATID-PHASE-DID-DOCUMENT OVER _ATIDW.PHASE !
    ATID-A-DID-DOCUMENT SWAP _ATIDW.ACTION !
    ATID-S-OK ;

\ Each chain slot is zero-filled, so the byte immediately following a stored
\ name is an unambiguous terminator even at the 253-byte maximum.
: _ATID-CNAME-SLOT!  ( name-a name-u index resolver -- )
    >R
    R@ _ATIDW.CNAME DUP 256 0 FILL
    >R
    R@ SWAP CMOVE
    R> DROP R> DROP ;

: _ATID-CNAME-SLOT=  ( name-a name-u index resolver -- flag )
    >R
    DUP R@ _ATIDW.CNAME >R
    DROP
    R@ OVER + C@ 0<> IF
        2DROP R> DROP R> DROP 0 EXIT
    THEN
    R@ OVER COMPARE 0=
    R> DROP R> DROP ;

: _ATID-CNAME-SEEN?  ( name-a name-u resolver -- flag )
    >R
    0
    BEGIN
        DUP R@ _ATIDW.CNAME-COUNT @ <=
    WHILE
        2 PICK 2 PICK 2 PICK R@
        _ATID-CNAME-SLOT= IF
            _ATID-DROP3 R> DROP -1 EXIT
        THEN
        1+
    REPEAT
    _ATID-DROP3 R> DROP 0 ;

: _ATID-DNS-NAME-RESET  ( resolver -- )
    DUP _ATIDW.NAME 256 0 FILL
    0 OVER _ATIDW.NAME-U !
    -1 OVER _ATIDW.DNS-ID !
    0 OVER _ATIDW.DNS-DID-U !
    0 OVER _ATIDW.DNS-CANDIDATES !
    0 OVER _ATIDW.DNS-CONFLICT !
    0 OVER _ATIDW.CNAME-COUNT !
    DUP _ATIDW.QUERY DNS-TXT-QUERY-SIZE 0 FILL
    DUP _ATIDW.RR DNS-TXT-RR-RESULT-SIZE 0 FILL
    DUP _ATIDW.ITER DNS-TXT-ITER-SIZE 0 FILL
    DUP _ATIDW.CNAME-RESULT DNS-TXT-CNAME-RESULT-SIZE 0 FILL
    DUP _ATIDW.RR-VALUE DNS-TXT-VALUE-MAX 0 FILL
    DROP ;

: _ATID-PREPARE-DNS  ( resolver -- status )
    >R
    R@ _ATID-DNS-NAME-RESET
    S" _atproto." DUP
    R@ _ATIDW.NAME-U !
    R@ _ATIDW.NAME SWAP CMOVE
    R@ _ATIDW.HANDLE
    R@ _ATIDW.HANDLE-U @
    R@ _ATIDW.NAME R@ _ATIDW.NAME-U @ +
    SWAP CMOVE
    R@ _ATIDW.HANDLE-U @ R@ _ATIDW.NAME-U +!
    R@ _ATIDW.NAME R@ _ATIDW.NAME-U @
    DNS-TXT-NAME-VALIDATE DNS-TXT-S-OK <> IF
        R> DROP ATID-S-DNS EXIT
    THEN
    R@ _ATIDW.NAME R@ _ATIDW.NAME-U @
    0 R@ _ATID-CNAME-SLOT!
    _ATID-PHASE-DNS R@ _ATIDW.PHASE !
    ATID-A-DNS-QUERY R@ _ATIDW.ACTION !
    R> DROP ATID-S-OK ;

: _ATID-START-HANDLE-DISCOVERY  ( resolver -- status )
    DUP _ATIDW.HANDLE-U @ ATID-DNS-HANDLE-MAX U> IF
        _ATID-START-HANDLE-HTTPS
    ELSE
        DUP _ATID-PREPARE-DNS ?DUP IF
            SWAP _ATID-FAIL
        ELSE
            DROP ATID-S-OK
        THEN
    THEN ;

\ =====================================================================
\  Transactional begin operations
\ =====================================================================

: _ATID-BEGIN-GEOMETRY  ( source-a source-u result resolver -- status )
    3 PICK 3 PICK _ATID-SPAN-STATUS ?DUP IF
        _ATID-RETURN4 EXIT
    THEN
    1 PICK ATID-RESULT-VALID? 0= IF
        ATID-S-INVALID _ATID-RETURN4 EXIT
    THEN
    1 PICK ATID-RESULT-READY? IF
        ATID-S-STATE _ATID-RETURN4 EXIT
    THEN
    DUP ATID-RESOLVER-VALID? 0= IF
        ATID-S-INVALID _ATID-RETURN4 EXIT
    THEN
    DUP _ATIDW.PHASE @ _ATID-PHASE-IDLE <> IF
        ATID-S-STATE _ATID-RETURN4 EXIT
    THEN
    3 PICK 3 PICK
    3 PICK ATID-RESULT-SIZE MSPAN-OVERLAP? IF
        ATID-S-ALIAS _ATID-RETURN4 EXIT
    THEN
    3 PICK 3 PICK
    2 PICK ATID-RESOLVER-SIZE MSPAN-OVERLAP? IF
        ATID-S-ALIAS _ATID-RETURN4 EXIT
    THEN
    1 PICK ATID-RESULT-SIZE
    2 PICK ATID-RESOLVER-SIZE MSPAN-OVERLAP? IF
        ATID-S-ALIAS _ATID-RETURN4 EXIT
    THEN
    _ATID-DROP4 ATID-S-OK ;

: _ATID-BEGIN-RESET  ( mode result resolver -- )
    >R
    R@ ATID-RESOLVER-CLEAR DROP
    OVER R@ _ATIDW.MODE !
    DUP R@ _ATIDW.RESULT !
    SWAP _ATID-MODE-HANDLE = IF
        ATID-E-INPUT-HANDLE
    ELSE
        ATID-E-INPUT-DID
    THEN
    R@ _ATIDW.EVIDENCE !
    DROP R> DROP ;

: ATID-BEGIN-HANDLE
  ( handle-a handle-u result resolver -- status )
    3 PICK 3 PICK 3 PICK 3 PICK
    _ATID-BEGIN-GEOMETRY ?DUP IF _ATID-RETURN4 EXIT THEN
    3 PICK 3 PICK AT-HANDLE-VALIDATE
    DUP AT-HANDLE-S-OK <> IF
        >R _ATID-DROP4 R> DROP ATID-S-SYNTAX EXIT
    THEN
    DROP
    _ATID-MODE-HANDLE 2 PICK 2 PICK
    _ATID-BEGIN-RESET
    >R
    2 PICK 2 PICK
    R@ _ATIDW.HANDLE AT-HANDLE-LENGTH-MAX
    AT-HANDLE-NORMALIZE
    DUP AT-HANDLE-S-OK <> IF
        DROP _ATID-DROP4
        R@ ATID-RESOLVER-CLEAR DROP
        R> DROP ATID-S-INTERNAL EXIT
    THEN
    DROP
    DUP R@ _ATIDW.HANDLE-U !
    DROP
    R@ _ATIDW.HANDLE R@ _ATIDW.HANDLE-U @
    _ATID-HANDLE-POLICY ?DUP IF
        R@ ATID-RESOLVER-CLEAR DROP
        >R _ATID-DROP3 R> R> DROP EXIT
    THEN
    R@ _ATID-START-HANDLE-DISCOVERY
    >R _ATID-DROP3 R> R> DROP ;

: ATID-BEGIN-DID  ( did-a did-u result resolver -- status )
    3 PICK 3 PICK 3 PICK 3 PICK
    _ATID-BEGIN-GEOMETRY ?DUP IF _ATID-RETURN4 EXIT THEN
    3 PICK 3 PICK _ATID-DID-PROFILE ?DUP IF
        _ATID-RETURN4 EXIT
    THEN
    _ATID-MODE-DID 2 PICK 2 PICK _ATID-BEGIN-RESET
    >R
    2 PICK 2 PICK R@ _ATIDW.DID SWAP MOVE
    OVER R@ _ATIDW.DID-U !
    R@ _ATID-START-DID-DOCUMENT
    >R _ATID-DROP3 R> R> DROP ;

\ =====================================================================
\  Action inspection and DNS query construction
\ =====================================================================

: ATID-ACTION@  ( resolver -- action status )
    DUP ATID-RESOLVER-VALID? 0= IF
        DROP ATID-A-NONE ATID-S-INVALID EXIT
    THEN
    _ATIDW.ACTION @ ATID-S-OK ;

: ATID-RESOLVER-STATUS@  ( resolver -- status )
    DUP ATID-RESOLVER-VALID? IF
        _ATIDW.STATUS @
    ELSE
        DROP ATID-S-INVALID
    THEN ;

: ATID-DNS-NAME@  ( resolver -- address length status )
    DUP ATID-RESOLVER-VALID? 0= IF
        DROP 0 0 ATID-S-INVALID EXIT
    THEN
    DUP _ATIDW.PHASE @ _ATID-PHASE-DNS <> IF
        DROP 0 0 ATID-S-STATE EXIT
    THEN
    DUP _ATIDW.NAME SWAP _ATIDW.NAME-U @ ATID-S-OK ;

: ATID-DNS-QUERY-BUILD  ( unpredictable-id resolver -- status )
    DUP ATID-RESOLVER-VALID? 0= IF
        2DROP ATID-S-INVALID EXIT
    THEN
    DUP _ATIDW.ACTION @ ATID-A-DNS-QUERY <> IF
        2DROP ATID-S-STATE EXIT
    THEN
    OVER DUP 0< SWAP 65535 > OR IF
        2DROP ATID-S-INVALID EXIT
    THEN
    DUP _ATIDW.PREV-DNS-ID @ -1 <> IF
        OVER OVER _ATIDW.PREV-DNS-ID @ = IF
            2DROP ATID-S-STATE EXIT
        THEN
    THEN
    DUP _ATIDW.NAME
    OVER _ATIDW.NAME-U @
    3 PICK
    3 PICK _ATIDW.QUERY
    DNS-TXT-QUERY-BUILD
    DUP DNS-TXT-S-OK <> IF
        DROP ATID-S-INTERNAL OVER _ATID-FAIL
        >R 2DROP R> EXIT
    THEN
    DROP
    OVER OVER _ATIDW.DNS-ID !
    OVER OVER _ATIDW.PREV-DNS-ID !
    ATID-A-DNS-EXCHANGE OVER _ATIDW.ACTION !
    2DROP ATID-S-OK ;

: ATID-DNS-QUERY$  ( resolver -- address length status )
    DUP ATID-RESOLVER-VALID? 0= IF
        DROP 0 0 ATID-S-INVALID EXIT
    THEN
    DUP _ATIDW.ACTION @ ATID-A-DNS-EXCHANGE <> IF
        DROP 0 0 ATID-S-STATE EXIT
    THEN
    _ATIDW.QUERY DNS-TXT-QUERY$
    DUP DNS-TXT-S-OK = IF
        DROP ATID-S-OK
    ELSE
        >R 2DROP 0 0 R> DROP ATID-S-INTERNAL
    THEN ;

: ATID-HTTP-TARGET@  ( resolver -- target status )
    DUP ATID-RESOLVER-VALID? 0= IF
        DROP 0 ATID-S-INVALID EXIT
    THEN
    DUP _ATIDW.ACTION @ DUP ATID-A-HANDLE-HTTPS =
    SWAP ATID-A-DID-DOCUMENT = OR 0= IF
        DROP 0 ATID-S-STATE EXIT
    THEN
    _ATIDW.TARGET ATID-S-OK ;

\ =====================================================================
\  DID-document evidence, publication, and mapping reduction
\ =====================================================================

: _ATID-CAPTURE-DOCUMENT-EVIDENCE  ( resolver -- status )
    >R
    ATID-E-DOCUMENT-ID R@ _ATID-EVIDENCE+
    R@ _ATIDW.DOCUMENT AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
    DUP AT-DIDDOC-S-OK = IF
        DROP 2DROP ATID-E-KEY R@ _ATID-EVIDENCE+
    ELSE
        AT-DIDDOC-S-MISSING <> IF
            2DROP R> DROP ATID-S-INTERNAL EXIT
        THEN
        2DROP
    THEN
    R@ _ATIDW.DOCUMENT AT-DIDDOC-PDS-TARGET@
    DUP AT-DIDDOC-S-OK = IF
        DROP DROP ATID-E-PDS R@ _ATID-EVIDENCE+
    ELSE
        AT-DIDDOC-S-MISSING <> IF
            DROP R> DROP ATID-S-INTERNAL EXIT
        THEN
        DROP
    THEN
    R@ _ATIDW.DOCUMENT AT-DIDDOC-PARTICIPATION-STATUS
    DUP AT-DIDDOC-S-OK = IF
        DROP ATID-E-PARTICIPATION R@ _ATID-EVIDENCE+
        R> DROP ATID-S-OK EXIT
    THEN
    DUP AT-DIDDOC-S-KEY = SWAP AT-DIDDOC-S-PDS = OR IF
        R> DROP ATID-S-OK EXIT
    THEN
    R> DROP ATID-S-INTERNAL ;

: _ATID-PUBLISH  ( handle-state-evidence resolver -- status )
    >R
    DUP R@ _ATID-EVIDENCE+
    DROP
    0 R@ _ATIDW.RESULT @ _ATIDR.MAGIC !
    R@ _ATIDW.DOCUMENT
    R@ _ATIDW.RESULT @ _ATIDR.DOCUMENT
    AT-DIDDOC-SIZE MOVE
    1 R@ _ATIDW.RESULT @ _ATIDR.PHASE !
    R@ _ATIDW.EVIDENCE @
    R@ _ATIDW.RESULT @ _ATIDR.EVIDENCE !
    0 R@ _ATIDW.RESULT @ _ATIDR.RESERVED !
    _ATIDR-MAGIC-VALUE R@ _ATIDW.RESULT @ _ATIDR.MAGIC !
    R@ _ATIDW.RESULT @ ATID-RESULT-READY? 0= IF
        R@ _ATIDW.RESULT @ ATID-RESULT-INIT DROP
        ATID-S-INTERNAL R> _ATID-FAIL EXIT
    THEN
    _ATID-PHASE-DONE R@ _ATIDW.PHASE !
    ATID-A-DONE R@ _ATIDW.ACTION !
    ATID-S-OK R@ _ATIDW.STATUS !
    R> DROP ATID-S-OK ;

: _ATID-DISCOVERY-FAIL  ( failure-status resolver -- status )
    DUP _ATIDW.MODE @ _ATID-MODE-DID = IF
        NIP ATID-E-HANDLE-INVALID SWAP _ATID-PUBLISH
    ELSE
        _ATID-FAIL
    THEN ;

: _ATID-USE-MAPPING
  ( did-a did-u mapping-evidence resolver -- status )
    >R
    2 PICK 2 PICK _ATID-DID-PROFILE
    DUP ATID-S-OK <> IF
        R@ _ATIDW.MODE @ _ATID-MODE-DID = IF
            DROP _ATID-DROP3
            ATID-E-HANDLE-INVALID R> _ATID-PUBLISH EXIT
        THEN
        >R _ATID-DROP3 R> R> _ATID-FAIL EXIT
    THEN
    DROP
    R@ _ATIDW.MODE @ _ATID-MODE-HANDLE = IF
        DUP R@ _ATID-EVIDENCE+
        2 PICK 2 PICK R@ _ATIDW.DID SWAP MOVE
        1 PICK R@ _ATIDW.DID-U !
        _ATID-DROP3
        R> _ATID-START-DID-DOCUMENT EXIT
    THEN
    2 PICK 2 PICK
    R@ _ATIDW.DID R@ _ATIDW.DID-U @ COMPARE 0= IF
        DUP R@ _ATID-EVIDENCE+
        _ATID-DROP3
        ATID-E-HANDLE-VERIFIED R> _ATID-PUBLISH
    ELSE
        _ATID-DROP3
        ATID-E-HANDLE-INVALID R> _ATID-PUBLISH
    THEN ;

: _ATID-DOCUMENT-HANDLE  ( resolver -- status )
    >R
    R@ _ATIDW.DOCUMENT AT-DIDDOC-HANDLE@
    DUP AT-DIDDOC-S-MISSING = IF
        DROP 2DROP
        R@ _ATIDW.MODE @ _ATID-MODE-HANDLE = IF
            ATID-S-MISMATCH R> _ATID-FAIL
        ELSE
            ATID-E-HANDLE-MISSING R> _ATID-PUBLISH
        THEN EXIT
    THEN
    DUP AT-DIDDOC-S-OK <> IF
        DROP 2DROP ATID-S-INTERNAL R> _ATID-FAIL EXIT
    THEN
    DROP
    R@ _ATIDW.MODE @ _ATID-MODE-HANDLE = IF
        2DUP
        R@ _ATIDW.HANDLE R@ _ATIDW.HANDLE-U @
        COMPARE 0= IF
            2DROP ATID-E-HANDLE-VERIFIED R> _ATID-PUBLISH
        ELSE
            2DROP ATID-S-MISMATCH R> _ATID-FAIL
        THEN EXIT
    THEN
    2DUP _ATID-HANDLE-POLICY ATID-S-OK <> IF
        2DROP ATID-E-HANDLE-INVALID R> _ATID-PUBLISH EXIT
    THEN
    2DUP R@ _ATIDW.HANDLE SWAP MOVE
    DUP R@ _ATIDW.HANDLE-U !
    2DROP
    R> _ATID-START-HANDLE-DISCOVERY ;

\ =====================================================================
\  DNS TXT reduction and bounded CNAME progression
\ =====================================================================

: _ATID-RR-DID$  ( rr-result -- did-a did-u valid? )
    DUP DNS-TXT-RR-RESULT-VALID? 0= IF
        DROP 0 0 0 EXIT
    THEN
    DUP DNS-TXT-RR-PRESENT? 0= IF DROP 0 0 0 EXIT THEN
    DUP DNS-TXT-RR-PROVISIONAL? 0= IF DROP 0 0 0 EXIT THEN
    DUP DNS-TXT-RR-COMPLETE? 0= IF DROP 0 0 0 EXIT THEN
    DUP DNS-TXT-RR-TOTAL-LENGTH@
    DID-LENGTH-MAX 4 + U> IF DROP 0 0 0 EXIT THEN
    DUP DNS-TXT-RR-PREFIX$
    2 PICK DNS-TXT-RR-TOTAL-LENGTH@
    1 PICK <> IF _ATID-DROP3 0 0 0 EXIT THEN
    DUP 4 < IF _ATID-DROP3 0 0 0 EXIT THEN
    OVER 4 S" did=" COMPARE IF
        _ATID-DROP3 0 0 0 EXIT
    THEN
    4 /STRING
    2DUP DID-VALID? 0= IF
        _ATID-DROP3 0 0 0 EXIT
    THEN
    ROT DROP -1 ;

: _ATID-ACCEPT-RR  ( resolver -- status )
    >R
    R@ _ATIDW.RR _ATID-RR-DID$ 0= IF
        2DROP R> DROP ATID-S-OK EXIT
    THEN
    R@ _ATIDW.DNS-DID-U @ 0= IF
        2DUP R@ _ATIDW.DNS-DID SWAP MOVE
        DUP R@ _ATIDW.DNS-DID-U !
    ELSE
        2DUP
        R@ _ATIDW.DNS-DID R@ _ATIDW.DNS-DID-U @
        COMPARE IF -1 R@ _ATIDW.DNS-CONFLICT ! THEN
    THEN
    1 R@ _ATIDW.DNS-CANDIDATES +!
    2DROP R> DROP ATID-S-OK ;

: _ATID-TXT-REDUCE
  ( response-a response-u resolver -- dns-status )
    >R
    0 R@ _ATIDW.DNS-DID-U !
    0 R@ _ATIDW.DNS-CANDIDATES !
    0 R@ _ATIDW.DNS-CONFLICT !
    R@ _ATIDW.RR-VALUE DNS-TXT-VALUE-MAX
    R@ _ATIDW.RR DNS-TXT-RR-RESULT-INIT
    DUP DNS-TXT-S-OK <> IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    2DUP R@ _ATIDW.QUERY R@ _ATIDW.RR R@ _ATIDW.ITER
    DNS-TXT-ITER-BEGIN
    DUP DNS-TXT-S-OK <> IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    BEGIN
        R@ _ATIDW.ITER DNS-TXT-ITER-NEXT
        DUP DNS-TXT-S-OK <> IF
            >R _ATID-DROP3 R> R> DROP EXIT
        THEN
        DROP
        IF
            R@ _ATID-ACCEPT-RR
            DUP ATID-S-OK <> IF
                DROP 2DROP R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            DROP
        ELSE
            R@ _ATIDW.ITER DNS-TXT-ITER-VALIDATED? 0= IF
                2DROP R> DROP DNS-TXT-S-MALFORMED EXIT
            THEN
            R@ _ATIDW.ITER DNS-TXT-ITER-STATUS@
            >R 2DROP R> R> DROP EXIT
        THEN
    AGAIN ;

: _ATID-CNAME-REDUCE
  ( response-a response-u resolver -- dns-status )
    >R
    R@ _ATIDW.NAME DNS-TXT-NAME-MAX
    R@ _ATIDW.CNAME-RESULT DNS-TXT-CNAME-RESULT-INIT
    DUP DNS-TXT-S-OK <> IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    R@ _ATIDW.QUERY R@ _ATIDW.CNAME-RESULT
    DNS-TXT-CNAME-PARSE
    R> DROP ;

: _ATID-DNS-NAME-LOWER  ( address length -- )
    BEGIN DUP WHILE
        OVER C@ DUP [CHAR] A [CHAR] Z 1+ WITHIN IF
            32 +
        THEN
        2 PICK C!
        1 /STRING
    REPEAT
    2DROP ;

: _ATID-FOLLOW-CNAME  ( resolver -- status )
    >R
    R@ _ATIDW.CNAME-COUNT @ ATID-DNS-CNAME-MAX >= IF
        ATID-S-LOOP R> _ATID-DISCOVERY-FAIL EXIT
    THEN
    R@ _ATIDW.CNAME-RESULT DNS-TXT-CNAME-TARGET$
    2DUP _ATID-DNS-NAME-LOWER
    2DUP R@ _ATID-CNAME-SEEN? IF
        2DROP ATID-S-LOOP R> _ATID-DISCOVERY-FAIL EXIT
    THEN
    DUP R@ _ATIDW.NAME-U !
    1 R@ _ATIDW.CNAME-COUNT +!
    2DUP R@ _ATIDW.CNAME-COUNT @ R@ _ATID-CNAME-SLOT!
    2DROP
    -1 R@ _ATIDW.DNS-ID !
    R@ _ATIDW.QUERY DNS-TXT-QUERY-SIZE 0 FILL
    ATID-A-DNS-QUERY R@ _ATIDW.ACTION !
    R> DROP ATID-S-OK ;

: _ATID-DNS-FALLBACK  ( resolver -- status )
    0 OVER _ATIDW.DNS-DID-U !
    _ATID-START-HANDLE-HTTPS ;

: _ATID-DNS-DECIDE  ( txt-status cname-status resolver -- status )
    >R
    OVER R@ _ATIDW.DNS-STATUS !
    OVER DNS-TXT-S-OK = IF
        R@ _ATIDW.DNS-CONFLICT @ IF
            2DROP ATID-S-CONFLICT R> _ATID-DISCOVERY-FAIL EXIT
        THEN
        R@ _ATIDW.DNS-DID-U @ IF
            DUP DNS-TXT-S-NODATA <> IF
                2DROP ATID-S-CONFLICT R>
                _ATID-DISCOVERY-FAIL EXIT
            THEN
            2DROP
            R@ _ATIDW.DNS-DID R@ _ATIDW.DNS-DID-U @
            ATID-E-HANDLE-DNS R> _ATID-USE-MAPPING EXIT
        THEN
    THEN
    DUP DNS-TXT-S-OK = IF
        2DROP R> _ATID-FOLLOW-CNAME EXIT
    THEN
    DUP DNS-TXT-S-DUPLICATE = IF
        2DROP ATID-S-CONFLICT R> _ATID-DISCOVERY-FAIL EXIT
    THEN
    2DROP R> _ATID-DNS-FALLBACK ;

: _ATID-RESPONSE-GEOMETRY
  ( response-a response-u resolver -- status )
    2 PICK 2 PICK _ATID-SPAN-STATUS ?DUP IF
        _ATID-RETURN3 EXIT
    THEN
    2 PICK 2 PICK
    2 PICK ATID-RESOLVER-SIZE MSPAN-OVERLAP? IF
        ATID-S-ALIAS _ATID-RETURN3 EXIT
    THEN
    2 PICK 2 PICK
    2 PICK _ATIDW.RESULT @ ATID-RESULT-SIZE
    MSPAN-OVERLAP? IF
        ATID-S-ALIAS _ATID-RETURN3 EXIT
    THEN
    _ATID-DROP3 ATID-S-OK ;

: ATID-DNS-RESPONSE!
  ( response-a response-u resolver -- status )
    DUP ATID-RESOLVER-VALID? 0= IF
        _ATID-DROP3 ATID-S-INVALID EXIT
    THEN
    DUP _ATIDW.ACTION @ ATID-A-DNS-EXCHANGE <> IF
        _ATID-DROP3 ATID-S-STATE EXIT
    THEN
    2 PICK 2 PICK 2 PICK _ATID-RESPONSE-GEOMETRY
    ?DUP IF _ATID-RETURN3 EXIT THEN
    >R
    2DUP R@ _ATID-TXT-REDUCE
    2 PICK 2 PICK R@ _ATID-CNAME-REDUCE
    R@ _ATID-DNS-DECIDE
    >R 2DROP R> R> DROP ;

\ =====================================================================
\  Explicit final HTTP response policy
\ =====================================================================

: _ATID-WELL-KNOWN-WS?  ( byte -- flag )
    DUP 32 = IF DROP -1 EXIT THEN
    DUP 9 = IF DROP -1 EXIT THEN
    DUP 10 = IF DROP -1 EXIT THEN
    13 = ;

: _ATID-WELL-KNOWN-TRIM-RIGHT
  ( body-a body-u prior-trim -- a' u' status )
    BEGIN
        OVER 0= IF DROP ATID-S-OK EXIT THEN
        2 PICK 2 PICK + 1- C@
        _ATID-WELL-KNOWN-WS? 0= IF
            DROP ATID-S-OK EXIT
        THEN
        1+
        DUP ATID-WELL-KNOWN-TRIM-MAX U> IF
            _ATID-DROP3 0 0 ATID-S-SYNTAX EXIT
        THEN
        SWAP 1- SWAP
    AGAIN ;

: _ATID-TRIM-HANDLE-BODY  ( body-a body-u -- did-a did-u status )
    DUP DID-LENGTH-MAX ATID-WELL-KNOWN-TRIM-MAX 2 * + U> IF
        2DROP 0 0 ATID-S-CAPACITY EXIT
    THEN
    0
    BEGIN
        OVER 0= IF
            _ATID-DROP3 0 0 ATID-S-SYNTAX EXIT
        THEN
        2 PICK C@ _ATID-WELL-KNOWN-WS? 0= IF
            _ATID-WELL-KNOWN-TRIM-RIGHT
            DUP ATID-S-OK <> IF EXIT THEN
            DROP
            DUP 0= IF
                2DROP 0 0 ATID-S-SYNTAX
            ELSE
                ATID-S-OK
            THEN
            EXIT
        THEN
        1+
        DUP ATID-WELL-KNOWN-TRIM-MAX U> IF
            _ATID-DROP3 0 0 ATID-S-SYNTAX EXIT
        THEN
        >R 1 /STRING R>
    AGAIN ;

: _ATID-HANDLE-HTTP-RESPONSE
  ( body-a body-u http-status resolver -- status )
    >R
    DUP R@ _ATIDW.HTTP-STATUS !
    DUP _ATID-HTTP-SUCCESS? 0= IF
        DROP 2DROP ATID-S-UNRESOLVED R> _ATID-DISCOVERY-FAIL EXIT
    THEN
    DROP
    _ATID-TRIM-HANDLE-BODY
    DUP ATID-S-OK <> IF
        >R 2DROP R> R> _ATID-DISCOVERY-FAIL EXIT
    THEN
    DROP
    2DUP _ATID-DID-PROFILE
    DUP ATID-S-OK <> IF
        >R 2DROP R> R> _ATID-DISCOVERY-FAIL EXIT
    THEN
    DROP
    ATID-E-HANDLE-HTTPS R> _ATID-USE-MAPPING ;

: _ATID-DIDDOC-HTTP-RESPONSE
  ( body-a body-u http-status resolver -- status )
    >R
    DUP R@ _ATIDW.HTTP-STATUS !
    DUP _ATID-HTTP-SUCCESS? 0= IF
        DROP 2DROP ATID-S-HTTP R> _ATID-FAIL EXIT
    THEN
    DROP
    R@ _ATIDW.DID R@ _ATIDW.DID-U @
    R@ _ATIDW.DOCUMENT R@ _ATIDW.DIDDOC-WORK
    AT-DIDDOC-PARSE
    DUP AT-DIDDOC-S-OK <> IF
        DROP ATID-S-DOCUMENT R> _ATID-FAIL EXIT
    THEN
    DROP
    R@ _ATID-CAPTURE-DOCUMENT-EVIDENCE
    DUP ATID-S-OK <> IF
        R> _ATID-FAIL EXIT
    THEN
    DROP
    R> _ATID-DOCUMENT-HANDLE ;

: ATID-HTTP-RESPONSE!
  ( body-a body-u http-status redirect-count final-target resolver -- status )
    DUP ATID-RESOLVER-VALID? 0= IF
        _ATID-DROP6 ATID-S-INVALID EXIT
    THEN
    3 PICK _ATID-HTTP-STATUS? 0= IF
        _ATID-DROP6 ATID-S-INVALID EXIT
    THEN
    2 PICK DUP 0< SWAP ATID-HTTP-REDIRECT-MAX > OR IF
        _ATID-DROP6 ATID-S-HTTP EXIT
    THEN
    OVER HTARGET-VALID? 0= IF
        _ATID-DROP6 ATID-S-HTTP EXIT
    THEN
    2 PICK 0= IF
        OVER 1 PICK _ATIDW.TARGET HTARGET-EQUAL? 0= IF
            _ATID-DROP6 ATID-S-HTTP EXIT
        THEN
    THEN
    DUP _ATIDW.ACTION @ DUP ATID-A-HANDLE-HTTPS =
    SWAP ATID-A-DID-DOCUMENT = OR 0= IF
        _ATID-DROP6 ATID-S-STATE EXIT
    THEN
    5 PICK 5 PICK 2 PICK _ATID-RESPONSE-GEOMETRY
    ?DUP IF _ATID-RETURN6 EXIT THEN
    >R 2DROP R>
    DUP _ATIDW.ACTION @ ATID-A-HANDLE-HTTPS = IF
        _ATID-HANDLE-HTTP-RESPONSE
    ELSE
        _ATID-DIDDOC-HTTP-RESPONSE
    THEN ;

\ A transport calls this only after its bounded retry/redirect policy is
\ exhausted.  The identity core then applies protocol fallback semantics.
: ATID-ACTION-FAIL  ( resolver -- status )
    DUP ATID-RESOLVER-VALID? 0= IF
        DROP ATID-S-INVALID EXIT
    THEN
    DUP _ATIDW.ACTION @ DUP ATID-A-DNS-QUERY =
    SWAP ATID-A-DNS-EXCHANGE = OR IF
        _ATID-DNS-FALLBACK EXIT
    THEN
    DUP _ATIDW.ACTION @ ATID-A-HANDLE-HTTPS = IF
        ATID-S-UNRESOLVED SWAP _ATID-DISCOVERY-FAIL EXIT
    THEN
    DUP _ATIDW.ACTION @ ATID-A-DID-DOCUMENT = IF
        ATID-S-HTTP SWAP _ATID-FAIL EXIT
    THEN
    DROP ATID-S-STATE ;

\ =====================================================================
\  Published result accessors and cleanup
\ =====================================================================

: ATID-DOCUMENT@  ( result -- document status )
    DUP ATID-RESULT-READY? 0= IF
        DROP 0 ATID-S-INVALID EXIT
    THEN
    _ATIDR.DOCUMENT ATID-S-OK ;

: ATID-DID@  ( result -- address length status )
    DUP ATID-RESULT-READY? 0= IF
        DROP 0 0 ATID-S-INVALID EXIT
    THEN
    _ATIDR.DOCUMENT AT-DIDDOC-DID@
    DUP AT-DIDDOC-S-OK = IF
        DROP ATID-S-OK
    ELSE
        >R 2DROP 0 0 R> DROP ATID-S-INTERNAL
    THEN ;

: ATID-HANDLE@  ( result -- address length status )
    DUP ATID-RESULT-READY? 0= IF
        DROP 0 0 ATID-S-INVALID EXIT
    THEN
    DUP _ATIDR.EVIDENCE @
    ATID-E-HANDLE-VERIFIED _ATID-BIT? 0= IF
        DROP 0 0 ATID-S-MISSING EXIT
    THEN
    _ATIDR.DOCUMENT AT-DIDDOC-HANDLE@
    DUP AT-DIDDOC-S-OK = IF
        DROP ATID-S-OK
    ELSE
        >R 2DROP 0 0 R> DROP ATID-S-INTERNAL
    THEN ;

: ATID-PUBLIC-KEY-MULTIBASE@
  ( result -- address length status )
    DUP ATID-RESULT-READY? 0= IF
        DROP 0 0 ATID-S-INVALID EXIT
    THEN
    _ATIDR.DOCUMENT AT-DIDDOC-PUBLIC-KEY-MULTIBASE@
    DUP AT-DIDDOC-S-OK = IF
        DROP ATID-S-OK EXIT
    THEN
    DUP AT-DIDDOC-S-MISSING = IF
        DROP 2DROP 0 0 ATID-S-MISSING EXIT
    THEN
    >R 2DROP 0 0 R> DROP ATID-S-INTERNAL ;

: ATID-PDS-TARGET@  ( result -- target status )
    DUP ATID-RESULT-READY? 0= IF
        DROP 0 ATID-S-INVALID EXIT
    THEN
    _ATIDR.DOCUMENT AT-DIDDOC-PDS-TARGET@
    DUP AT-DIDDOC-S-OK = IF
        DROP ATID-S-OK EXIT
    THEN
    DUP AT-DIDDOC-S-MISSING = IF
        2DROP 0 ATID-S-MISSING EXIT
    THEN
    2DROP 0 ATID-S-INTERNAL ;

: ATID-PDS-ORIGIN@  ( result -- address length status )
    DUP ATID-RESULT-READY? 0= IF
        DROP 0 0 ATID-S-INVALID EXIT
    THEN
    _ATIDR.DOCUMENT AT-DIDDOC-PDS-ORIGIN@
    DUP AT-DIDDOC-S-OK = IF
        DROP ATID-S-OK EXIT
    THEN
    DUP AT-DIDDOC-S-MISSING = IF
        DROP 2DROP 0 0 ATID-S-MISSING EXIT
    THEN
    >R 2DROP 0 0 R> DROP ATID-S-INTERNAL ;

: ATID-EVIDENCE@  ( result -- evidence status )
    DUP ATID-RESULT-READY? IF
        _ATIDR.EVIDENCE @ ATID-S-OK
    ELSE
        DROP 0 ATID-S-INVALID
    THEN ;

: ATID-PARTICIPATION-STATUS  ( result -- status )
    DUP ATID-RESULT-READY? 0= IF
        DROP ATID-S-INVALID EXIT
    THEN
    _ATIDR.DOCUMENT AT-DIDDOC-PARTICIPATION-STATUS
    DUP AT-DIDDOC-S-OK = IF DROP ATID-S-OK EXIT THEN
    DUP AT-DIDDOC-S-KEY = IF DROP ATID-S-KEY EXIT THEN
    DUP AT-DIDDOC-S-PDS = IF DROP ATID-S-PDS EXIT THEN
    DROP ATID-S-INTERNAL ;

: ATID-PARTICIPATION-READY?  ( result -- flag )
    ATID-PARTICIPATION-STATUS ATID-S-OK = ;

: ATID-RESOLVER-WIPE  ( resolver -- status )
    DUP ATID-RESOLVER-VALID? 0= IF
        DROP ATID-S-INVALID EXIT
    THEN
    ATID-RESOLVER-SIZE 0 FILL
    ATID-S-OK ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _ATID-GEOMETRY-ABORT  ( -- )
    ." AT Protocol identity geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _ATID-GEOMETRY-ABORT
[THEN]

_ATIDR-DOCUMENT AT-DIDDOC-SIZE +
ATID-RESULT-SIZE <> [IF]
    _ATID-GEOMETRY-ABORT
[THEN]

_ATIDW-DIDDOC-WORK-OFF AT-DIDDOC-WORKSPACE-SIZE +
ATID-RESOLVER-SIZE <> [IF]
    _ATID-GEOMETRY-ABORT
[THEN]

_ATIDW-RR-VALUE-OFF DNS-TXT-VALUE-MAX +
_ATIDW-RR-OFF <> [IF]
    _ATID-GEOMETRY-ABORT
[THEN]

_ATIDW-CNAME-OFF ATID-DNS-CNAME-MAX 1+ 256 * +
_ATIDW-TARGET-OFF <> [IF]
    _ATID-GEOMETRY-ABORT
[THEN]
