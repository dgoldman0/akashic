\ =====================================================================
\  pkce.f - Generic OAuth 2 Proof Key for Code Exchange (S256)
\ =====================================================================
\  This is a policy-neutral RFC 7636 utility.  It validates caller-supplied
\  code verifiers, derives an S256 challenge deterministically, or creates
\  a verifier from 32 bytes of checked hardware entropy and derives its
\  matching challenge.  The weaker `plain` transformation is intentionally
\  absent.
\
\  Every operation uses a caller-owned bounded workspace.  The module owns
\  no mutable operation state.  Hashes and encoded results remain staged in
\  that workspace until every fallible step succeeds.  Once geometry is
\  admitted, the complete workspace is wiped after success, status failure,
\  or THROW.  Lower-layer and publication THROW propagate after cleanup;
\  mandatory-cleanup THROW propagates with precedence.
\
\  Rejected geometry, capacity, alias, and verifier calls do not modify the
\  workspace or destinations.  For admitted calls, destinations are changed
\  only at final publication.  Only the exact 43-byte published result spans
\  participate in input/output and output/output alias checks; each complete
\  advertised output-capacity span must remain disjoint from the workspace,
\  because the workspace is independently wiped.
\
\  Public API:
\    OAUTH2-PKCE-VERIFIER-MIN             ( -- 43 )
\    OAUTH2-PKCE-VERIFIER-MAX             ( -- 128 )
\    OAUTH2-PKCE-GENERATED-VERIFIER-SIZE  ( -- 43 )
\    OAUTH2-PKCE-CHALLENGE-SIZE           ( -- 43 )
\    OAUTH2-PKCE-WORKSPACE-SIZE           ( -- 219 )
\    OAUTH2-PKCE-STATUS-VALID?            ( status -- flag )
\    OAUTH2-PKCE-VERIFIER-VALID?          ( verifier verifier-u -- flag )
\    OAUTH2-PKCE-WORKSPACE-CLEAR          ( workspace -- status )
\    OAUTH2-PKCE-S256
\      ( verifier verifier-u challenge challenge-capacity workspace
\        -- written status )
\    OAUTH2-PKCE-GENERATE
\      ( verifier verifier-capacity challenge challenge-capacity workspace
\        -- verifier-written challenge-written status )
\ =====================================================================

PROVIDED akashic-oauth2-pkce

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../jose/base64url.f
REQUIRE ../../math/sha256.f
REQUIRE ../../math/entropy.f

\ =====================================================================
\  Public geometry and status vocabulary
\ =====================================================================

43  CONSTANT OAUTH2-PKCE-VERIFIER-MIN
128 CONSTANT OAUTH2-PKCE-VERIFIER-MAX
43  CONSTANT OAUTH2-PKCE-GENERATED-VERIFIER-SIZE
43  CONSTANT OAUTH2-PKCE-CHALLENGE-SIZE

0 CONSTANT OAUTH2-PKCE-S-OK
1 CONSTANT OAUTH2-PKCE-S-INVALID
2 CONSTANT OAUTH2-PKCE-S-VERIFIER
3 CONSTANT OAUTH2-PKCE-S-CAPACITY
4 CONSTANT OAUTH2-PKCE-S-ALIAS
5 CONSTANT OAUTH2-PKCE-S-ENTROPY
6 CONSTANT OAUTH2-PKCE-S-CRYPTO
7 CONSTANT OAUTH2-PKCE-S-INTERNAL
8 CONSTANT OAUTH2-PKCE-S-RANGE
9 CONSTANT OAUTH2-PKCE-S-PROTECTED
10 CONSTANT OAUTH2-PKCE-S-PLATFORM

: OAUTH2-PKCE-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-PKCE-S-OK >=
    SWAP OAUTH2-PKCE-S-PLATFORM <= AND ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================
\  The first 64 bytes hold transient borrowed pointers and capacities.
\  The remaining regions stage raw entropy, the generated verifier, the
\  SHA-256 digest, and the challenge.  The five-byte gap following the
\  generated verifier keeps the digest naturally aligned.

  0 CONSTANT _OPKW-VERIFIER
  8 CONSTANT _OPKW-VERIFIER-U
 16 CONSTANT _OPKW-CHALLENGE
 24 CONSTANT _OPKW-CHALLENGE-CAPACITY
 32 CONSTANT _OPKW-RESERVED0
 40 CONSTANT _OPKW-RESERVED1
 48 CONSTANT _OPKW-RESERVED2
 56 CONSTANT _OPKW-RESERVED3

 64 CONSTANT _OPKW-RAW-OFF
 96 CONSTANT _OPKW-STAGED-VERIFIER-OFF
144 CONSTANT _OPKW-DIGEST-OFF
176 CONSTANT _OPKW-STAGED-CHALLENGE-OFF
219 CONSTANT OAUTH2-PKCE-WORKSPACE-SIZE

32 CONSTANT _OPK-RANDOM-SIZE
48 CONSTANT _OPK-STAGED-VERIFIER-REGION-SIZE

: _OPKW.VERIFIER           ( workspace -- address ) _OPKW-VERIFIER + ;
: _OPKW.VERIFIER-U         ( workspace -- address ) _OPKW-VERIFIER-U + ;
: _OPKW.CHALLENGE          ( workspace -- address ) _OPKW-CHALLENGE + ;
: _OPKW.CHALLENGE-CAPACITY ( workspace -- address )
    _OPKW-CHALLENGE-CAPACITY + ;
: _OPKW.RAW                ( workspace -- address ) _OPKW-RAW-OFF + ;
: _OPKW.STAGED-VERIFIER    ( workspace -- address )
    _OPKW-STAGED-VERIFIER-OFF + ;
: _OPKW.DIGEST             ( workspace -- address ) _OPKW-DIGEST-OFF + ;
: _OPKW.STAGED-CHALLENGE   ( workspace -- address )
    _OPKW-STAGED-CHALLENGE-OFF + ;

: _OPK-WIPE  ( workspace -- )
    OAUTH2-PKCE-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Caller admission and verifier predicates
\ =====================================================================

: _OPK-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP OAUTH2-PKCE-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP OAUTH2-PKCE-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP OAUTH2-PKCE-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP OAUTH2-PKCE-S-PLATFORM EXIT
    THEN
    DROP OAUTH2-PKCE-S-PLATFORM ;

: _OPK-SHA>STATUS  ( sha-status -- status )
    DUP SHA256-S-OK = IF
        DROP OAUTH2-PKCE-S-OK EXIT
    THEN
    DUP SHA256-S-RANGE = IF
        DROP OAUTH2-PKCE-S-RANGE EXIT
    THEN
    DUP SHA256-S-INVALID = IF
        DROP OAUTH2-PKCE-S-INVALID EXIT
    THEN
    DUP SHA256-S-ALIAS = IF
        DROP OAUTH2-PKCE-S-ALIAS EXIT
    THEN
    DROP OAUTH2-PKCE-S-CRYPTO ;

: _OPK-ADMIT-SPAN  ( address length -- status )
    2DUP CALLER-SPAN-STATUS _OPK-CALLER>STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    SHA256-CALLER-SPAN-STATUS _OPK-SHA>STATUS ;

: _OPK-B64>STATUS  ( base64url-status -- status )
    DUP JOSE-B64URL-S-RANGE = IF
        DROP OAUTH2-PKCE-S-RANGE EXIT
    THEN
    DUP JOSE-B64URL-S-PROTECTED = IF
        DROP OAUTH2-PKCE-S-PROTECTED EXIT
    THEN
    DUP JOSE-B64URL-S-PLATFORM = IF
        DROP OAUTH2-PKCE-S-PLATFORM EXIT
    THEN
    DUP JOSE-B64URL-S-ALIAS = IF
        DROP OAUTH2-PKCE-S-ALIAS EXIT
    THEN
    DROP OAUTH2-PKCE-S-INTERNAL ;

: _OPK-ENTROPY>STATUS  ( entropy-status -- status )
    DUP ENTROPY-S-UNAVAILABLE = IF
        DROP OAUTH2-PKCE-S-ENTROPY EXIT
    THEN
    DUP ENTROPY-S-RANGE = IF
        DROP OAUTH2-PKCE-S-RANGE EXIT
    THEN
    DUP ENTROPY-S-PROTECTED = IF
        DROP OAUTH2-PKCE-S-PROTECTED EXIT
    THEN
    DROP OAUTH2-PKCE-S-INTERNAL ;

: _OPK-UNRESERVED?  ( char -- flag )
    DUP 65 >= OVER 90 <= AND IF DROP -1 EXIT THEN
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    DUP 95 = IF DROP -1 EXIT THEN
    126 = ;

: OAUTH2-PKCE-VERIFIER-VALID?  ( verifier verifier-u -- flag )
    DUP OAUTH2-PKCE-VERIFIER-MIN < IF 2DROP 0 EXIT THEN
    DUP OAUTH2-PKCE-VERIFIER-MAX > IF 2DROP 0 EXIT THEN
    2DUP _OPK-ADMIT-SPAN IF 2DROP 0 EXIT THEN
    DUP 0 ?DO
        OVER I + C@ _OPK-UNRESERVED? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: OAUTH2-PKCE-WORKSPACE-CLEAR  ( workspace -- status )
    DUP OAUTH2-PKCE-WORKSPACE-SIZE
        _OPK-ADMIT-SPAN ?DUP IF
        NIP EXIT
    THEN
    _OPK-WIPE OAUTH2-PKCE-S-OK ;

\ =====================================================================
\  Exact operation geometry
\ =====================================================================

: _OPK-DROP5  ( x1 x2 x3 x4 x5 -- )
    2DROP 2DROP DROP ;

: _OPK-RETURN5  ( x1 x2 x3 x4 x5 status -- status )
    >R _OPK-DROP5 R> ;

: _OPK-S256-GEOMETRY
  ( verifier verifier-u challenge challenge-capacity workspace -- status )
    DUP OAUTH2-PKCE-WORKSPACE-SIZE _OPK-ADMIT-SPAN
        ?DUP IF
        >R _OPK-DROP5 R> EXIT
    THEN
    4 PICK 4 PICK _OPK-ADMIT-SPAN ?DUP IF
        >R _OPK-DROP5 R> EXIT
    THEN
    2 PICK 2 PICK _OPK-ADMIT-SPAN ?DUP IF
        >R _OPK-DROP5 R> EXIT
    THEN
    1 PICK OAUTH2-PKCE-CHALLENGE-SIZE U< IF
        OAUTH2-PKCE-S-CAPACITY _OPK-RETURN5 EXIT
    THEN
    4 PICK 4 PICK OAUTH2-PKCE-VERIFIER-VALID? 0= IF
        OAUTH2-PKCE-S-VERIFIER _OPK-RETURN5 EXIT
    THEN

    \ The borrowed verifier is compared with the exact published challenge,
    \ not unused destination capacity.
    4 PICK 4 PICK
    4 PICK OAUTH2-PKCE-CHALLENGE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-PKCE-S-ALIAS _OPK-RETURN5 EXIT
    THEN
    4 PICK 4 PICK
    2 PICK OAUTH2-PKCE-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-PKCE-S-ALIAS _OPK-RETURN5 EXIT
    THEN
    2 PICK 2 PICK
    2 PICK OAUTH2-PKCE-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-PKCE-S-ALIAS _OPK-RETURN5 EXIT
    THEN
    OAUTH2-PKCE-S-OK _OPK-RETURN5 ;

: _OPK-GENERATE-GEOMETRY
  \ ( verifier verifier-capacity challenge challenge-capacity workspace
  \   -- status )
    DUP OAUTH2-PKCE-WORKSPACE-SIZE _OPK-ADMIT-SPAN
        ?DUP IF
        >R _OPK-DROP5 R> EXIT
    THEN
    4 PICK 4 PICK _OPK-ADMIT-SPAN ?DUP IF
        >R _OPK-DROP5 R> EXIT
    THEN
    2 PICK 2 PICK _OPK-ADMIT-SPAN ?DUP IF
        >R _OPK-DROP5 R> EXIT
    THEN
    3 PICK OAUTH2-PKCE-GENERATED-VERIFIER-SIZE U< IF
        OAUTH2-PKCE-S-CAPACITY _OPK-RETURN5 EXIT
    THEN
    1 PICK OAUTH2-PKCE-CHALLENGE-SIZE U< IF
        OAUTH2-PKCE-S-CAPACITY _OPK-RETURN5 EXIT
    THEN

    \ The two exact result spans must be disjoint.  Their unused advertised
    \ capacities may overlap because neither operation writes those bytes.
    4 PICK OAUTH2-PKCE-GENERATED-VERIFIER-SIZE
    4 PICK OAUTH2-PKCE-CHALLENGE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-PKCE-S-ALIAS _OPK-RETURN5 EXIT
    THEN
    4 PICK 4 PICK
    2 PICK OAUTH2-PKCE-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-PKCE-S-ALIAS _OPK-RETURN5 EXIT
    THEN
    2 PICK 2 PICK
    2 PICK OAUTH2-PKCE-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-PKCE-S-ALIAS _OPK-RETURN5 EXIT
    THEN
    OAUTH2-PKCE-S-OK _OPK-RETURN5 ;

\ =====================================================================
\  S256 construction and staged publication
\ =====================================================================

\ SHA256-HASH owns the shared crypto-ACC transaction transitively.  PKCE
\ deliberately does not acquire that resource itself.
: _OPK-BUILD-S256  ( verifier verifier-u workspace -- status )
    >R
    R@ _OPKW.DIGEST SHA256-HASH
    DUP IF
        _OPK-SHA>STATUS R> DROP EXIT
    THEN
    DROP
    R@ _OPKW.DIGEST SHA256-LEN
    R@ _OPKW.STAGED-CHALLENGE OAUTH2-PKCE-CHALLENGE-SIZE
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        NIP _OPK-B64>STATUS R> DROP EXIT
    THEN
    DROP
    OAUTH2-PKCE-CHALLENGE-SIZE <> IF
        R> DROP OAUTH2-PKCE-S-INTERNAL EXIT
    THEN
    R> DROP OAUTH2-PKCE-S-OK ;

: _OPK-BIND
  ( verifier verifier-u challenge challenge-capacity workspace -- workspace )
    DUP _OPK-WIPE
    4 PICK OVER _OPKW.VERIFIER !
    3 PICK OVER _OPKW.VERIFIER-U !
    2 PICK OVER _OPKW.CHALLENGE !
    1 PICK OVER _OPKW.CHALLENGE-CAPACITY !
    >R 2DROP 2DROP R> ;

: _OPK-S256-STAGE  ( workspace -- status )
    DUP _OPKW.VERIFIER @
    OVER _OPKW.VERIFIER-U @
    2 PICK _OPK-BUILD-S256
    DUP IF
        NIP EXIT
    THEN
    DROP
    DROP OAUTH2-PKCE-S-OK ;

: _OPK-GENERATE-STAGE  ( workspace -- status )
    >R
    R@ _OPKW.RAW _OPK-RANDOM-SIZE ENTROPY-FILL
    DUP ENTROPY-S-OK <> IF
        _OPK-ENTROPY>STATUS R> DROP EXIT
    THEN
    DROP

    R@ _OPKW.RAW _OPK-RANDOM-SIZE
    R@ _OPKW.STAGED-VERIFIER OAUTH2-PKCE-GENERATED-VERIFIER-SIZE
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        NIP _OPK-B64>STATUS R> DROP EXIT
    THEN
    DROP
    OAUTH2-PKCE-GENERATED-VERIFIER-SIZE <> IF
        R> DROP OAUTH2-PKCE-S-INTERNAL EXIT
    THEN

    R@ _OPKW.STAGED-VERIFIER
    OAUTH2-PKCE-GENERATED-VERIFIER-SIZE
    R@ _OPK-BUILD-S256
    DUP IF
        R> DROP EXIT
    THEN
    DROP

    R> DROP
    OAUTH2-PKCE-S-OK ;

: _OPK-S256-ADMITTED
  \ ( verifier verifier-u challenge challenge-capacity workspace
  \   -- written status )
    _OPK-BIND _OPK-S256-STAGE ;

: _OPK-GENERATE-ADMITTED
  \ ( verifier verifier-capacity challenge challenge-capacity workspace
  \   -- verifier-written challenge-written status )
    _OPK-BIND _OPK-GENERATE-STAGE ;

\ =====================================================================
\  Publication and mandatory cleanup
\ =====================================================================

: _OPK-S256-PUBLISH  ( workspace -- written )
    DUP _OPKW.STAGED-CHALLENGE
    OVER _OPKW.CHALLENGE @
    OAUTH2-PKCE-CHALLENGE-SIZE MOVE
    DROP OAUTH2-PKCE-CHALLENGE-SIZE ;

: _OPK-GENERATE-PUBLISH
  ( workspace -- verifier-written challenge-written )
    DUP _OPKW.STAGED-VERIFIER
    OVER _OPKW.VERIFIER @
    OAUTH2-PKCE-GENERATED-VERIFIER-SIZE MOVE
    DUP _OPKW.STAGED-CHALLENGE
    OVER _OPKW.CHALLENGE @
    OAUTH2-PKCE-CHALLENGE-SIZE MOVE
    DROP
    OAUTH2-PKCE-GENERATED-VERIFIER-SIZE
    OAUTH2-PKCE-CHALLENGE-SIZE ;

\ Operation and publication THROW are rethrown after successful cleanup.
\ Cleanup THROW propagates directly and therefore has precedence.
: _OPK-CALL-FINALLY
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

: _OPK-CALL-RESULT
  ( x1 x2 x3 x4 workspace xt -- written status )
    1 PICK >R
    CATCH
    DUP IF
        >R _OPK-DROP5
        R> R> SWAP >R
        _OPK-WIPE
        R> THROW
    THEN
    DROP
    DUP IF
        R@ _OPK-WIPE
        R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ ['] _OPK-S256-PUBLISH ['] _OPK-WIPE
        _OPK-CALL-FINALLY
    R> DROP
    OAUTH2-PKCE-S-OK ;

: _OPK-CALL-GENERATE
  \ ( x1 x2 x3 x4 workspace xt
  \   -- verifier-written challenge-written status )
    1 PICK >R
    CATCH
    DUP IF
        >R _OPK-DROP5
        R> R> SWAP >R
        _OPK-WIPE
        R> THROW
    THEN
    DROP
    DUP IF
        R@ _OPK-WIPE
        R> DROP 0 0 ROT EXIT
    THEN
    DROP
    R@ ['] _OPK-GENERATE-PUBLISH ['] _OPK-WIPE
        _OPK-CALL-FINALLY
    R> DROP
    OAUTH2-PKCE-S-OK ;

\ =====================================================================
\  Public entry points
\ =====================================================================

: OAUTH2-PKCE-S256
  \ ( verifier verifier-u challenge challenge-capacity workspace
  \   -- written status )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK _OPK-S256-GEOMETRY
    DUP IF
        >R _OPK-DROP5 R> 0 SWAP EXIT
    THEN
    DROP
    ['] _OPK-S256-ADMITTED _OPK-CALL-RESULT ;

: OAUTH2-PKCE-GENERATE
  \ ( verifier verifier-capacity challenge challenge-capacity workspace
  \   -- verifier-written challenge-written status )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK _OPK-GENERATE-GEOMETRY
    DUP IF
        >R _OPK-DROP5 R> 0 0 ROT EXIT
    THEN
    DROP
    ['] _OPK-GENERATE-ADMITTED _OPK-CALL-GENERATE ;

\ Compile-time layout checks prevent a later edit from silently overlapping
\ secret staging regions or changing the published workspace contract.
: _OPK-GEOMETRY-ABORT  ( -- )
    ." OAuth2 PKCE workspace geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _OPK-GEOMETRY-ABORT
[THEN]

_OPKW-RAW-OFF _OPK-RANDOM-SIZE +
_OPKW-STAGED-VERIFIER-OFF <> [IF]
    _OPK-GEOMETRY-ABORT
[THEN]

_OPKW-STAGED-VERIFIER-OFF _OPK-STAGED-VERIFIER-REGION-SIZE +
_OPKW-DIGEST-OFF <> [IF]
    _OPK-GEOMETRY-ABORT
[THEN]

_OPKW-DIGEST-OFF SHA256-LEN +
_OPKW-STAGED-CHALLENGE-OFF <> [IF]
    _OPK-GEOMETRY-ABORT
[THEN]

_OPKW-STAGED-CHALLENGE-OFF OAUTH2-PKCE-CHALLENGE-SIZE +
OAUTH2-PKCE-WORKSPACE-SIZE <> [IF]
    _OPK-GEOMETRY-ABORT
[THEN]
