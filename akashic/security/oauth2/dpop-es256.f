\ =====================================================================
\  dpop-es256.f - Standalone OAuth DPoP proof construction with ES256
\ =====================================================================
\  This module constructs one RFC 9449 DPoP proof JWT.  It does not own an
\  HTTP client, clock, URI normalizer, nonce cache, token set, OAuth flow,
\  discovery policy, or proof verifier.
\
\  The transport supplies the exact HTTP method, an already normalized
\  absolute HTTP target URI with query and fragment removed, and the
\  NumericDate creation time.  A nonce and access token are independently
\  optional: `(0,0)` means absent.  Nonces remain opaque NQCHAR strings.
\  Access tokens remain opaque token68 strings and, when present, contribute
\  only `ath = BASE64URL(SHA-256(ASCII(access-token)))`.
\
\  Every admitted construction obtains fresh hardware entropy for a
\  128-bit `jti`, derives the public P-256 key from the supplied private
\  key, emits that public key as a JWK, constructs the protected header and
\  payload in caller-owned staging, and delegates compact signing to the
\  generic JWS ES256 layer.  The complete compact proof is staged before
\  final caller-output publication.
\
\  The module owns no mutable operation state.  Once valid geometry is
\  admitted, its complete caller-owned workspace is cleared on success,
\  returned failure, and THROW.  Operation and publication THROWs are
\  reissued after cleanup; a cleanup THROW has precedence.
\
\  Public API:
\    OAUTH2-DPOP-ES256-MAX-METHOD-BYTES   ( -- 32 )
\    OAUTH2-DPOP-ES256-MAX-HTU-BYTES      ( -- 4096 )
\    OAUTH2-DPOP-ES256-MAX-NONCE-BYTES    ( -- 4096 )
\    OAUTH2-DPOP-ES256-JTI-SIZE           ( -- 22 )
\    OAUTH2-DPOP-ES256-MAX-PROOF-BYTES    ( -- 11459 )
\    OAUTH2-DPOP-ES256-WORKSPACE-SIZE     ( -- bytes )
\    OAUTH2-DPOP-ES256-STATUS-VALID?       ( status -- flag )
\    OAUTH2-DPOP-ES256-WORKSPACE-CLEAR     ( workspace -- status )
\    OAUTH2-DPOP-ES256-PROOF
\      ( htm htm-u htu htu-u iat
\        nonce nonce-u access-token access-token-u private
\        destination capacity workspace -- written status )
\ =====================================================================

PROVIDED akashic-oauth2-dpop256

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE ../jose/base64url.f
REQUIRE ../jose/jwk-p256.f
REQUIRE ../jose/jws-es256.f
REQUIRE ../../math/sha256.f
REQUIRE ../../math/entropy.f
REQUIRE ../../math/p256.f

\ =====================================================================
\  Public bounds and status vocabulary
\ =====================================================================

32   CONSTANT OAUTH2-DPOP-ES256-MAX-METHOD-BYTES
4096 CONSTANT OAUTH2-DPOP-ES256-MAX-HTU-BYTES
4096 CONSTANT OAUTH2-DPOP-ES256-MAX-NONCE-BYTES

16 CONSTANT _ODP-JTI-ENTROPY-SIZE

_ODP-JTI-ENTROPY-SIZE JOSE-B64URL-ENCODED-LENGTH
JOSE-B64URL-S-OK <> [IF]
    ." OAuth2 DPoP ES256 jti geometry failed" CR ABORT
[THEN]
CONSTANT OAUTH2-DPOP-ES256-JTI-SIZE

165  CONSTANT _ODP-HEADER-SIZE
8363 CONSTANT _ODP-MAX-PAYLOAD-SIZE

_ODP-HEADER-SIZE _ODP-MAX-PAYLOAD-SIZE
JOSE-JWS-ES256-COMPACT-SIZE
JOSE-JWS-ES256-S-OK <> [IF]
    ." OAuth2 DPoP ES256 proof geometry failed" CR ABORT
[THEN]
CONSTANT OAUTH2-DPOP-ES256-MAX-PROOF-BYTES

0  CONSTANT OAUTH2-DPOP-ES256-S-OK
1  CONSTANT OAUTH2-DPOP-ES256-S-INVALID
2  CONSTANT OAUTH2-DPOP-ES256-S-METHOD
3  CONSTANT OAUTH2-DPOP-ES256-S-HTU
4  CONSTANT OAUTH2-DPOP-ES256-S-NONCE
5  CONSTANT OAUTH2-DPOP-ES256-S-TOKEN
6  CONSTANT OAUTH2-DPOP-ES256-S-TIME
7  CONSTANT OAUTH2-DPOP-ES256-S-CAPACITY
8  CONSTANT OAUTH2-DPOP-ES256-S-ALIAS
9  CONSTANT OAUTH2-DPOP-ES256-S-ENTROPY
10 CONSTANT OAUTH2-DPOP-ES256-S-KEY
11 CONSTANT OAUTH2-DPOP-ES256-S-CRYPTO
12 CONSTANT OAUTH2-DPOP-ES256-S-INTERNAL
13 CONSTANT OAUTH2-DPOP-ES256-S-RANGE
14 CONSTANT OAUTH2-DPOP-ES256-S-PROTECTED
15 CONSTANT OAUTH2-DPOP-ES256-S-PLATFORM

: OAUTH2-DPOP-ES256-STATUS-VALID?  ( status -- flag )
    DUP OAUTH2-DPOP-ES256-S-OK >=
    SWAP OAUTH2-DPOP-ES256-S-PLATFORM <= AND ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================

  0 CONSTANT _ODPW-HTM
  8 CONSTANT _ODPW-HTM-U
 16 CONSTANT _ODPW-HTU
 24 CONSTANT _ODPW-HTU-U
 32 CONSTANT _ODPW-IAT
 40 CONSTANT _ODPW-NONCE
 48 CONSTANT _ODPW-NONCE-U
 56 CONSTANT _ODPW-TOKEN
 64 CONSTANT _ODPW-TOKEN-U
 72 CONSTANT _ODPW-PRIVATE-IN
 80 CONSTANT _ODPW-DESTINATION
 88 CONSTANT _ODPW-CAPACITY
 96 CONSTANT _ODPW-RESULT-U
104 CONSTANT _ODPW-CURSOR
112 CONSTANT _ODPW-REMAINING
120 CONSTANT _ODPW-DIVISOR
128 CONSTANT _ODPW-STARTED
136 CONSTANT _ODPW-IAT-U
144 CONSTANT _ODPW-RESERVED0
152 CONSTANT _ODPW-RESERVED1

160 CONSTANT _ODPW-PRIVATE-OFF
_ODPW-PRIVATE-OFF P256-PRIVATE-SIZE +
CONSTANT _ODPW-PUBLIC-OFF
_ODPW-PUBLIC-OFF P256-PUBLIC-SIZE +
7 + 8 / 8 *
CONSTANT _ODPW-JTI-RAW-OFF
_ODPW-JTI-RAW-OFF _ODP-JTI-ENTROPY-SIZE +
CONSTANT _ODPW-JTI-TEXT-OFF
_ODPW-JTI-TEXT-OFF OAUTH2-DPOP-ES256-JTI-SIZE +
7 + 8 / 8 *
CONSTANT _ODPW-ATH-DIGEST-OFF
_ODPW-ATH-DIGEST-OFF SHA256-LEN +
CONSTANT _ODPW-ATH-TEXT-OFF
_ODPW-ATH-TEXT-OFF 43 +
7 + 8 / 8 *
CONSTANT _ODPW-IAT-TEXT-OFF
_ODPW-IAT-TEXT-OFF 19 +
7 + 8 / 8 *
CONSTANT _ODPW-HEADER-OFF
_ODPW-HEADER-OFF _ODP-HEADER-SIZE +
7 + 8 / 8 *
CONSTANT _ODPW-PAYLOAD-OFF
_ODPW-PAYLOAD-OFF _ODP-MAX-PAYLOAD-SIZE +
7 + 8 / 8 *
CONSTANT _ODPW-PROOF-OFF
_ODPW-PROOF-OFF OAUTH2-DPOP-ES256-MAX-PROOF-BYTES +
7 + 8 / 8 *
CONSTANT _ODPW-JWK-WORK-OFF
_ODPW-JWK-WORK-OFF JOSE-JWK-P256-WORKSPACE-SIZE +
7 + 8 / 8 *
CONSTANT _ODPW-JWS-WORK-OFF
_ODPW-JWS-WORK-OFF JOSE-JWS-ES256-WORKSPACE-SIZE +
CONSTANT OAUTH2-DPOP-ES256-WORKSPACE-SIZE

: _ODPW.HTM          ( w -- a ) _ODPW-HTM + ;
: _ODPW.HTM-U        ( w -- a ) _ODPW-HTM-U + ;
: _ODPW.HTU          ( w -- a ) _ODPW-HTU + ;
: _ODPW.HTU-U        ( w -- a ) _ODPW-HTU-U + ;
: _ODPW.IAT          ( w -- a ) _ODPW-IAT + ;
: _ODPW.NONCE        ( w -- a ) _ODPW-NONCE + ;
: _ODPW.NONCE-U      ( w -- a ) _ODPW-NONCE-U + ;
: _ODPW.TOKEN        ( w -- a ) _ODPW-TOKEN + ;
: _ODPW.TOKEN-U      ( w -- a ) _ODPW-TOKEN-U + ;
: _ODPW.PRIVATE-IN   ( w -- a ) _ODPW-PRIVATE-IN + ;
: _ODPW.DESTINATION  ( w -- a ) _ODPW-DESTINATION + ;
: _ODPW.CAPACITY     ( w -- a ) _ODPW-CAPACITY + ;
: _ODPW.RESULT-U     ( w -- a ) _ODPW-RESULT-U + ;
: _ODPW.CURSOR       ( w -- a ) _ODPW-CURSOR + ;
: _ODPW.REMAINING    ( w -- a ) _ODPW-REMAINING + ;
: _ODPW.DIVISOR      ( w -- a ) _ODPW-DIVISOR + ;
: _ODPW.STARTED      ( w -- a ) _ODPW-STARTED + ;
: _ODPW.IAT-U        ( w -- a ) _ODPW-IAT-U + ;

: _ODPW.PRIVATE      ( w -- a ) _ODPW-PRIVATE-OFF + ;
: _ODPW.PUBLIC       ( w -- a ) _ODPW-PUBLIC-OFF + ;
: _ODPW.JTI-RAW      ( w -- a ) _ODPW-JTI-RAW-OFF + ;
: _ODPW.JTI-TEXT     ( w -- a ) _ODPW-JTI-TEXT-OFF + ;
: _ODPW.ATH-DIGEST   ( w -- a ) _ODPW-ATH-DIGEST-OFF + ;
: _ODPW.ATH-TEXT     ( w -- a ) _ODPW-ATH-TEXT-OFF + ;
: _ODPW.IAT-TEXT     ( w -- a ) _ODPW-IAT-TEXT-OFF + ;
: _ODPW.HEADER       ( w -- a ) _ODPW-HEADER-OFF + ;
: _ODPW.PAYLOAD      ( w -- a ) _ODPW-PAYLOAD-OFF + ;
: _ODPW.PROOF        ( w -- a ) _ODPW-PROOF-OFF + ;
: _ODPW.JWK-WORK     ( w -- a ) _ODPW-JWK-WORK-OFF + ;
: _ODPW.JWS-WORK     ( w -- a ) _ODPW-JWS-WORK-OFF + ;

: _ODP-WIPE  ( workspace -- )
    OAUTH2-DPOP-ES256-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Status mapping and caller-memory admission
\ =====================================================================

: _ODP-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP OAUTH2-DPOP-ES256-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP OAUTH2-DPOP-ES256-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP OAUTH2-DPOP-ES256-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP OAUTH2-DPOP-ES256-S-PLATFORM EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-PLATFORM ;

: _ODP-SHA>STATUS  ( sha-status -- status )
    DUP SHA256-S-OK = IF
        DROP OAUTH2-DPOP-ES256-S-OK EXIT
    THEN
    DUP SHA256-S-RANGE = IF
        DROP OAUTH2-DPOP-ES256-S-RANGE EXIT
    THEN
    DUP SHA256-S-INVALID = IF
        DROP OAUTH2-DPOP-ES256-S-INVALID EXIT
    THEN
    DUP SHA256-S-ALIAS = IF
        DROP OAUTH2-DPOP-ES256-S-ALIAS EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-CRYPTO ;

: _ODP-ADMIT-SPAN  ( address length -- status )
    2DUP CALLER-SPAN-STATUS _ODP-CALLER>STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP ECDSA-P256-RESERVED-OVERLAP? IF
        2DROP OAUTH2-DPOP-ES256-S-ALIAS EXIT
    THEN
    SHA256-CALLER-SPAN-STATUS _ODP-SHA>STATUS ;

: _ODP-B64>STATUS  ( base64url-status -- status )
    DUP JOSE-B64URL-S-RANGE = IF
        DROP OAUTH2-DPOP-ES256-S-RANGE EXIT
    THEN
    DUP JOSE-B64URL-S-PROTECTED = IF
        DROP OAUTH2-DPOP-ES256-S-PROTECTED EXIT
    THEN
    DUP JOSE-B64URL-S-PLATFORM = IF
        DROP OAUTH2-DPOP-ES256-S-PLATFORM EXIT
    THEN
    DUP JOSE-B64URL-S-ALIAS = IF
        DROP OAUTH2-DPOP-ES256-S-ALIAS EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-INTERNAL ;

: _ODP-ENTROPY>STATUS  ( entropy-status -- status )
    DUP ENTROPY-S-UNAVAILABLE = IF
        DROP OAUTH2-DPOP-ES256-S-ENTROPY EXIT
    THEN
    DUP ENTROPY-S-RANGE = IF
        DROP OAUTH2-DPOP-ES256-S-RANGE EXIT
    THEN
    DUP ENTROPY-S-PROTECTED = IF
        DROP OAUTH2-DPOP-ES256-S-PROTECTED EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-INTERNAL ;

: _ODP-P256>STATUS  ( p256-status -- status )
    DUP P256-S-RANGE = IF
        DROP OAUTH2-DPOP-ES256-S-RANGE EXIT
    THEN
    DUP P256-S-PROTECTED = IF
        DROP OAUTH2-DPOP-ES256-S-PROTECTED EXIT
    THEN
    DUP P256-S-PLATFORM = IF
        DROP OAUTH2-DPOP-ES256-S-PLATFORM EXIT
    THEN
    DUP P256-S-ALIAS = IF
        DROP OAUTH2-DPOP-ES256-S-ALIAS EXIT
    THEN
    DUP P256-S-PRIVATE = IF
        DROP OAUTH2-DPOP-ES256-S-KEY EXIT
    THEN
    DUP P256-S-PUBLIC = IF
        DROP OAUTH2-DPOP-ES256-S-KEY EXIT
    THEN
    DUP P256-S-INTERNAL = IF
        DROP OAUTH2-DPOP-ES256-S-CRYPTO EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-INTERNAL ;

: _ODP-JWK>STATUS  ( jwk-status -- status )
    DUP JOSE-JWK-P256-S-PUBLIC = IF
        DROP OAUTH2-DPOP-ES256-S-KEY EXIT
    THEN
    DUP JOSE-JWK-P256-S-CRYPTO = IF
        DROP OAUTH2-DPOP-ES256-S-CRYPTO EXIT
    THEN
    DUP JOSE-JWK-P256-S-RANGE = IF
        DROP OAUTH2-DPOP-ES256-S-RANGE EXIT
    THEN
    DUP JOSE-JWK-P256-S-PROTECTED = IF
        DROP OAUTH2-DPOP-ES256-S-PROTECTED EXIT
    THEN
    DUP JOSE-JWK-P256-S-PLATFORM = IF
        DROP OAUTH2-DPOP-ES256-S-PLATFORM EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-INTERNAL ;

: _ODP-JWS>STATUS  ( jws-status -- status )
    DUP JOSE-JWS-ES256-S-KEY = IF
        DROP OAUTH2-DPOP-ES256-S-KEY EXIT
    THEN
    DUP JOSE-JWS-ES256-S-CRYPTO = IF
        DROP OAUTH2-DPOP-ES256-S-CRYPTO EXIT
    THEN
    DUP JOSE-JWS-ES256-S-RANGE = IF
        DROP OAUTH2-DPOP-ES256-S-RANGE EXIT
    THEN
    DUP JOSE-JWS-ES256-S-PROTECTED = IF
        DROP OAUTH2-DPOP-ES256-S-PROTECTED EXIT
    THEN
    DUP JOSE-JWS-ES256-S-PLATFORM = IF
        DROP OAUTH2-DPOP-ES256-S-PLATFORM EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-INTERNAL ;

\ =====================================================================
\  Pure syntax and size boundaries
\ =====================================================================

: _ODP-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _ODP-NONEMPTY-SPAN?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    _ODP-SPAN? ;

: _ODP-OPTIONAL-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF
        DROP 0= EXIT
    THEN
    _ODP-NONEMPTY-SPAN? ;

: _ODP-TCHAR?  ( char -- flag )
    DUP 65 >= OVER 90 <= AND IF DROP -1 EXIT THEN
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP -1 EXIT THEN
    DUP 33 = IF DROP -1 EXIT THEN
    DUP 35 = IF DROP -1 EXIT THEN
    DUP 36 = IF DROP -1 EXIT THEN
    DUP 37 = IF DROP -1 EXIT THEN
    DUP 38 = IF DROP -1 EXIT THEN
    DUP 39 = IF DROP -1 EXIT THEN
    DUP 42 = IF DROP -1 EXIT THEN
    DUP 43 = IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    DUP 94 = IF DROP -1 EXIT THEN
    DUP 95 = IF DROP -1 EXIT THEN
    DUP 96 = IF DROP -1 EXIT THEN
    DUP 124 = IF DROP -1 EXIT THEN
    126 = ;

: _ODP-METHOD-VALID?  ( method method-u -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    DUP OAUTH2-DPOP-ES256-MAX-METHOD-BYTES U> IF
        2DROP 0 EXIT
    THEN
    DUP 0 ?DO
        OVER I + C@ _ODP-TCHAR? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ODP-HTTPS-PREFIX?  ( htu htu-u -- flag )
    DUP 8 <= IF 2DROP 0 EXIT THEN
    DROP
    DUP C@       104 =
    OVER 1+ C@   116 = AND
    OVER 2 + C@  116 = AND
    OVER 3 + C@  112 = AND
    OVER 4 + C@  115 = AND
    OVER 5 + C@   58 = AND
    OVER 6 + C@   47 = AND
    OVER 7 + C@   47 = AND
    OVER 8 + C@   47 <> AND
    NIP ;

: _ODP-HTTP-PREFIX?  ( htu htu-u -- flag )
    DUP 7 <= IF 2DROP 0 EXIT THEN
    DROP
    DUP C@       104 =
    OVER 1+ C@   116 = AND
    OVER 2 + C@  116 = AND
    OVER 3 + C@  112 = AND
    OVER 4 + C@   58 = AND
    OVER 5 + C@   47 = AND
    OVER 6 + C@   47 = AND
    OVER 7 + C@   47 <> AND
    NIP ;

: _ODP-ABSOLUTE-HTTP?  ( htu htu-u -- flag )
    2DUP _ODP-HTTPS-PREFIX? >R
    _ODP-HTTP-PREFIX?
    R> OR ;

: _ODP-HTU-CHAR?  ( char -- flag )
    DUP 33 < IF DROP 0 EXIT THEN
    DUP 126 > IF DROP 0 EXIT THEN
    DUP 34 = IF DROP 0 EXIT THEN
    DUP 35 = IF DROP 0 EXIT THEN
    DUP 63 = IF DROP 0 EXIT THEN
    92 <> ;

: _ODP-HTU-VALID?  ( htu htu-u -- flag )
    DUP OAUTH2-DPOP-ES256-MAX-HTU-BYTES U> IF
        2DROP 0 EXIT
    THEN
    2DUP _ODP-ABSOLUTE-HTTP? 0= IF
        2DROP 0 EXIT
    THEN
    DUP 0 ?DO
        OVER I + C@ _ODP-HTU-CHAR? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ODP-NQCHAR?  ( char -- flag )
    DUP 33 < IF DROP 0 EXIT THEN
    DUP 126 > IF DROP 0 EXIT THEN
    DUP 34 = SWAP 92 = OR 0= ;

: _ODP-NONCE-VALID?  ( nonce nonce-u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    DUP OAUTH2-DPOP-ES256-MAX-NONCE-BYTES U> IF
        2DROP 0 EXIT
    THEN
    DUP 0 ?DO
        OVER I + C@ _ODP-NQCHAR? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ODP-TOKEN68-BASE?  ( char -- flag )
    DUP 65 >= OVER 90 <= AND IF DROP -1 EXIT THEN
    DUP 97 >= OVER 122 <= AND IF DROP -1 EXIT THEN
    DUP 48 >= OVER 57 <= AND IF DROP -1 EXIT THEN
    DUP 45 = IF DROP -1 EXIT THEN
    DUP 46 = IF DROP -1 EXIT THEN
    DUP 95 = IF DROP -1 EXIT THEN
    DUP 126 = IF DROP -1 EXIT THEN
    DUP 43 = IF DROP -1 EXIT THEN
    47 = ;

: _ODP-ALL-EQUALS?  ( address length -- flag )
    DUP 0 ?DO
        OVER I + C@ 61 <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ODP-TOKEN-VALID?  ( token token-u -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER C@ _ODP-TOKEN68-BASE? 0= IF
        2DROP 0 EXIT
    THEN
    DUP 1 ?DO
        OVER I + C@ DUP 61 = IF
            DROP
            OVER I + OVER I - _ODP-ALL-EQUALS? 0= IF
                2DROP 0 UNLOOP EXIT
            THEN
            2DROP -1 UNLOOP EXIT
        THEN
        _ODP-TOKEN68-BASE? 0= IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _ODP-IAT-DIGITS  ( nonnegative-iat -- digits )
    DUP 0= IF DROP 1 EXIT THEN
    0 SWAP
    BEGIN
        DUP
    WHILE
        10 / SWAP 1+ SWAP
    REPEAT
    DROP ;

: _ODP-PAYLOAD-SIZE
  ( htm-u htu-u iat nonce-u token-u -- payload-u )
    >R >R
    _ODP-IAT-DIGITS + + 57 +
    R@ ?DUP IF
        + 11 +
    THEN
    R> DROP
    R> 0> IF 52 + THEN ;

: _ODP-COMPACT-SIZE
  ( htm-u htu-u iat nonce-u token-u -- compact-u status )
    _ODP-PAYLOAD-SIZE
    DUP _ODP-MAX-PAYLOAD-SIZE U> IF
        DROP 0 OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    _ODP-HEADER-SIZE SWAP JOSE-JWS-ES256-COMPACT-SIZE
    DUP JOSE-JWS-ES256-S-OK <> IF
        2DROP 0 OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-OK ;

\ =====================================================================
\  Complete operation geometry
\ =====================================================================

: _ODP-DROP12  ( twelve values -- )
    2DROP 2DROP 2DROP 2DROP 2DROP 2DROP ;

: _ODP-DROP13  ( thirteen values -- )
    2DROP 2DROP 2DROP 2DROP 2DROP 2DROP DROP ;

: _ODP-13DUP  ( thirteen values -- the same values twice )
    12 PICK 12 PICK 12 PICK 12 PICK 12 PICK 12 PICK 12 PICK
    12 PICK 12 PICK 12 PICK 12 PICK 12 PICK 12 PICK ;

: _ODP-RETURN13
  ( thirteen arguments status -- status )
    >R _ODP-DROP13 R> ;

: _ODP-GEOMETRY
  \ ( htm htm-u htu htu-u iat
  \   nonce nonce-u token token-u private destination capacity workspace
  \   -- status )
    DUP OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        _ODP-NONEMPTY-SPAN? 0= IF
        OAUTH2-DPOP-ES256-S-INVALID _ODP-RETURN13 EXIT
    THEN
    12 PICK 12 PICK _ODP-NONEMPTY-SPAN? 0= IF
        OAUTH2-DPOP-ES256-S-INVALID _ODP-RETURN13 EXIT
    THEN
    10 PICK 10 PICK _ODP-NONEMPTY-SPAN? 0= IF
        OAUTH2-DPOP-ES256-S-INVALID _ODP-RETURN13 EXIT
    THEN
    7 PICK 7 PICK _ODP-OPTIONAL-SPAN? 0= IF
        OAUTH2-DPOP-ES256-S-INVALID _ODP-RETURN13 EXIT
    THEN
    5 PICK 5 PICK _ODP-OPTIONAL-SPAN? 0= IF
        OAUTH2-DPOP-ES256-S-INVALID _ODP-RETURN13 EXIT
    THEN
    3 PICK P256-PRIVATE-SIZE _ODP-NONEMPTY-SPAN? 0= IF
        OAUTH2-DPOP-ES256-S-INVALID _ODP-RETURN13 EXIT
    THEN
    2 PICK 2 PICK _ODP-SPAN? 0= IF
        OAUTH2-DPOP-ES256-S-INVALID _ODP-RETURN13 EXIT
    THEN

    DUP OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        _ODP-ADMIT-SPAN ?DUP IF
        _ODP-RETURN13 EXIT
    THEN
    12 PICK 12 PICK _ODP-ADMIT-SPAN ?DUP IF
        _ODP-RETURN13 EXIT
    THEN
    10 PICK 10 PICK _ODP-ADMIT-SPAN ?DUP IF
        _ODP-RETURN13 EXIT
    THEN
    7 PICK 7 PICK _ODP-ADMIT-SPAN ?DUP IF
        _ODP-RETURN13 EXIT
    THEN
    5 PICK 5 PICK _ODP-ADMIT-SPAN ?DUP IF
        _ODP-RETURN13 EXIT
    THEN
    3 PICK P256-PRIVATE-SIZE _ODP-ADMIT-SPAN ?DUP IF
        _ODP-RETURN13 EXIT
    THEN
    2 PICK 2 PICK _ODP-ADMIT-SPAN ?DUP IF
        _ODP-RETURN13 EXIT
    THEN

    12 PICK 12 PICK _ODP-METHOD-VALID? 0= IF
        OAUTH2-DPOP-ES256-S-METHOD _ODP-RETURN13 EXIT
    THEN
    10 PICK 10 PICK _ODP-HTU-VALID? 0= IF
        OAUTH2-DPOP-ES256-S-HTU _ODP-RETURN13 EXIT
    THEN
    8 PICK 0< IF
        OAUTH2-DPOP-ES256-S-TIME _ODP-RETURN13 EXIT
    THEN
    7 PICK 7 PICK _ODP-NONCE-VALID? 0= IF
        OAUTH2-DPOP-ES256-S-NONCE _ODP-RETURN13 EXIT
    THEN
    5 PICK 5 PICK _ODP-TOKEN-VALID? 0= IF
        OAUTH2-DPOP-ES256-S-TOKEN _ODP-RETURN13 EXIT
    THEN

    \ The complete workspace must not intersect any borrowed or advertised
    \ public span because it is wiped independently on every admitted exit.
    12 PICK 12 PICK
    2 PICK OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-DPOP-ES256-S-ALIAS _ODP-RETURN13 EXIT
    THEN
    10 PICK 10 PICK
    2 PICK OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-DPOP-ES256-S-ALIAS _ODP-RETURN13 EXIT
    THEN
    7 PICK 7 PICK
    2 PICK OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-DPOP-ES256-S-ALIAS _ODP-RETURN13 EXIT
    THEN
    5 PICK 5 PICK
    2 PICK OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-DPOP-ES256-S-ALIAS _ODP-RETURN13 EXIT
    THEN
    3 PICK P256-PRIVATE-SIZE
    2 PICK OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-DPOP-ES256-S-ALIAS _ODP-RETURN13 EXIT
    THEN
    2 PICK 2 PICK
    2 PICK OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        OAUTH2-DPOP-ES256-S-ALIAS _ODP-RETURN13 EXIT
    THEN

    \ Publishing over the caller's private key is never admitted.  Other
    \ borrowed request values may overlap destination capacity because the
    \ complete proof is staged only after all of them have been consumed.
    3 PICK P256-PRIVATE-SIZE
    4 PICK 4 PICK MSPAN-OVERLAP? IF
        OAUTH2-DPOP-ES256-S-ALIAS _ODP-RETURN13 EXIT
    THEN

    11 PICK 10 PICK 10 PICK 9 PICK 8 PICK
        _ODP-COMPACT-SIZE
    DUP IF
        >R DROP R> _ODP-RETURN13 EXIT
    THEN
    DROP
    2 PICK OVER U< IF
        DROP
        OAUTH2-DPOP-ES256-S-CAPACITY _ODP-RETURN13 EXIT
    THEN
    DROP
    OAUTH2-DPOP-ES256-S-OK _ODP-RETURN13 ;

: OAUTH2-DPOP-ES256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP OAUTH2-DPOP-ES256-WORKSPACE-SIZE
        _ODP-ADMIT-SPAN ?DUP IF
        NIP EXIT
    THEN
    _ODP-WIPE OAUTH2-DPOP-ES256-S-OK ;

\ =====================================================================
\  Staged claim construction
\ =====================================================================

: _ODP-PAYLOAD-APPEND  ( source source-u workspace -- )
    >R
    2DUP
    R@ _ODPW.PAYLOAD R@ _ODPW.CURSOR @ +
    SWAP MOVE
    NIP R@ _ODPW.CURSOR +!
    R> DROP ;

: _ODP-PAYLOAD-CHAR  ( char workspace -- )
    >R
    R@ _ODPW.PAYLOAD R@ _ODPW.CURSOR @ + C!
    1 R@ _ODPW.CURSOR +!
    R> DROP ;

: _ODP-HEADER-APPEND  ( source source-u workspace -- )
    >R
    2DUP
    R@ _ODPW.HEADER R@ _ODPW.CURSOR @ +
    SWAP MOVE
    NIP R@ _ODPW.CURSOR +!
    R> DROP ;

: _ODP-HEADER-CHAR  ( char workspace -- )
    >R
    R@ _ODPW.HEADER R@ _ODPW.CURSOR @ + C!
    1 R@ _ODPW.CURSOR +!
    R> DROP ;

: _ODP-FORMAT-IAT  ( workspace -- )
    0 OVER _ODPW.IAT-U !
    DUP _ODPW.IAT @ OVER _ODPW.REMAINING !
    1000000000000000000 OVER _ODPW.DIVISOR !
    0 OVER _ODPW.STARTED !
    BEGIN
        DUP _ODPW.DIVISOR @ 0>
    WHILE
        DUP _ODPW.REMAINING @
        OVER _ODPW.DIVISOR @ /MOD
        >R OVER _ODPW.REMAINING ! R>

        DUP IF -1 2 PICK _ODPW.STARTED ! THEN
        OVER _ODPW.DIVISOR @ 1 = IF
            -1 2 PICK _ODPW.STARTED !
        THEN
        OVER _ODPW.STARTED @ IF
            48 +
            OVER _ODPW.IAT-TEXT
            2 PICK _ODPW.IAT-U @ + C!
            1 OVER _ODPW.IAT-U +!
        ELSE
            DROP
        THEN

        DUP _ODPW.DIVISOR @ 10 /
        OVER _ODPW.DIVISOR !
    REPEAT
    DROP ;

: _ODP-STAGE-PRIVATE  ( workspace -- )
    DUP _ODPW.PRIVATE-IN @
    OVER _ODPW.PRIVATE
    P256-PRIVATE-SIZE MOVE
    DROP ;

: _ODP-BUILD-JTI  ( workspace -- status )
    >R
    R@ _ODPW.JTI-RAW _ODP-JTI-ENTROPY-SIZE ENTROPY-FILL
    DUP ENTROPY-S-OK <> IF
        _ODP-ENTROPY>STATUS R> DROP EXIT
    THEN
    DROP
    R@ _ODPW.JTI-RAW _ODP-JTI-ENTROPY-SIZE
    R@ _ODPW.JTI-TEXT OAUTH2-DPOP-ES256-JTI-SIZE
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        NIP _ODP-B64>STATUS R> DROP EXIT
    THEN
    DROP
    OAUTH2-DPOP-ES256-JTI-SIZE <> IF
        R> DROP OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    R> DROP OAUTH2-DPOP-ES256-S-OK ;

: _ODP-DERIVE-PUBLIC  ( workspace -- status )
    >R
    R@ _ODPW.PRIVATE
    R@ _ODPW.PUBLIC
    R@ _ODPW.JWK-WORK
    P256-PUBLIC-FROM-PRIVATE
    DUP P256-S-OK <> IF
        _ODP-P256>STATUS R> DROP EXIT
    THEN
    DROP R> DROP OAUTH2-DPOP-ES256-S-OK ;

: _ODP-BUILD-HEADER  ( workspace -- status )
    >R
    0 R@ _ODPW.CURSOR !
    123 R@ _ODP-HEADER-CHAR
    34 R@ _ODP-HEADER-CHAR
    S" typ" R@ _ODP-HEADER-APPEND
    34 R@ _ODP-HEADER-CHAR
    58 R@ _ODP-HEADER-CHAR
    34 R@ _ODP-HEADER-CHAR
    S" dpop+jwt" R@ _ODP-HEADER-APPEND
    34 R@ _ODP-HEADER-CHAR
    44 R@ _ODP-HEADER-CHAR
    34 R@ _ODP-HEADER-CHAR
    S" alg" R@ _ODP-HEADER-APPEND
    34 R@ _ODP-HEADER-CHAR
    58 R@ _ODP-HEADER-CHAR
    34 R@ _ODP-HEADER-CHAR
    S" ES256" R@ _ODP-HEADER-APPEND
    34 R@ _ODP-HEADER-CHAR
    44 R@ _ODP-HEADER-CHAR
    34 R@ _ODP-HEADER-CHAR
    S" jwk" R@ _ODP-HEADER-APPEND
    34 R@ _ODP-HEADER-CHAR
    58 R@ _ODP-HEADER-CHAR

    R@ _ODPW.CURSOR @ 38 <> IF
        R> DROP OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    R@ _ODPW.PUBLIC
    R@ _ODPW.HEADER R@ _ODPW.CURSOR @ +
    JOSE-JWK-P256-CANONICAL-SIZE
    R@ _ODPW.JWK-WORK
    JOSE-JWK-P256-PUBLIC-EMIT
    DUP JOSE-JWK-P256-S-OK <> IF
        NIP _ODP-JWK>STATUS R> DROP EXIT
    THEN
    DROP
    JOSE-JWK-P256-CANONICAL-SIZE <> IF
        R> DROP OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    JOSE-JWK-P256-CANONICAL-SIZE R@ _ODPW.CURSOR +!
    125 R@ _ODP-HEADER-CHAR
    R@ _ODPW.CURSOR @ _ODP-HEADER-SIZE <> IF
        R> DROP OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    R> DROP OAUTH2-DPOP-ES256-S-OK ;

: _ODP-BUILD-ATH  ( workspace -- status )
    DUP _ODPW.TOKEN-U @ 0= IF
        DROP OAUTH2-DPOP-ES256-S-OK EXIT
    THEN
    >R
    R@ _ODPW.TOKEN @ R@ _ODPW.TOKEN-U @
    R@ _ODPW.ATH-DIGEST SHA256-HASH
    DUP SHA256-S-OK <> IF
        _ODP-SHA>STATUS R> DROP EXIT
    THEN
    DROP
    R@ _ODPW.ATH-DIGEST SHA256-LEN
    R@ _ODPW.ATH-TEXT 43 JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        NIP _ODP-B64>STATUS R> DROP EXIT
    THEN
    DROP
    43 <> IF
        R> DROP OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    R> DROP OAUTH2-DPOP-ES256-S-OK ;

: _ODP-BUILD-PAYLOAD  ( workspace -- status )
    DUP _ODP-FORMAT-IAT
    0 OVER _ODPW.CURSOR !

    123 OVER _ODP-PAYLOAD-CHAR
    34 OVER _ODP-PAYLOAD-CHAR
    S" jti" 2 PICK _ODP-PAYLOAD-APPEND
    34 OVER _ODP-PAYLOAD-CHAR
    58 OVER _ODP-PAYLOAD-CHAR
    34 OVER _ODP-PAYLOAD-CHAR
    DUP _ODPW.JTI-TEXT OAUTH2-DPOP-ES256-JTI-SIZE
        2 PICK _ODP-PAYLOAD-APPEND
    34 OVER _ODP-PAYLOAD-CHAR
    44 OVER _ODP-PAYLOAD-CHAR
    34 OVER _ODP-PAYLOAD-CHAR
    S" htm" 2 PICK _ODP-PAYLOAD-APPEND
    34 OVER _ODP-PAYLOAD-CHAR
    58 OVER _ODP-PAYLOAD-CHAR
    34 OVER _ODP-PAYLOAD-CHAR
    DUP _ODPW.HTM @ OVER _ODPW.HTM-U @
        2 PICK _ODP-PAYLOAD-APPEND
    34 OVER _ODP-PAYLOAD-CHAR
    44 OVER _ODP-PAYLOAD-CHAR
    34 OVER _ODP-PAYLOAD-CHAR
    S" htu" 2 PICK _ODP-PAYLOAD-APPEND
    34 OVER _ODP-PAYLOAD-CHAR
    58 OVER _ODP-PAYLOAD-CHAR
    34 OVER _ODP-PAYLOAD-CHAR
    DUP _ODPW.HTU @ OVER _ODPW.HTU-U @
        2 PICK _ODP-PAYLOAD-APPEND
    34 OVER _ODP-PAYLOAD-CHAR
    44 OVER _ODP-PAYLOAD-CHAR
    34 OVER _ODP-PAYLOAD-CHAR
    S" iat" 2 PICK _ODP-PAYLOAD-APPEND
    34 OVER _ODP-PAYLOAD-CHAR
    58 OVER _ODP-PAYLOAD-CHAR
    DUP _ODPW.IAT-TEXT OVER _ODPW.IAT-U @
        2 PICK _ODP-PAYLOAD-APPEND

    DUP _ODPW.NONCE-U @ IF
        44 OVER _ODP-PAYLOAD-CHAR
        34 OVER _ODP-PAYLOAD-CHAR
        S" nonce" 2 PICK _ODP-PAYLOAD-APPEND
        34 OVER _ODP-PAYLOAD-CHAR
        58 OVER _ODP-PAYLOAD-CHAR
        34 OVER _ODP-PAYLOAD-CHAR
        DUP _ODPW.NONCE @ OVER _ODPW.NONCE-U @
            2 PICK _ODP-PAYLOAD-APPEND
        34 OVER _ODP-PAYLOAD-CHAR
    THEN

    DUP _ODPW.TOKEN-U @ IF
        44 OVER _ODP-PAYLOAD-CHAR
        34 OVER _ODP-PAYLOAD-CHAR
        S" ath" 2 PICK _ODP-PAYLOAD-APPEND
        34 OVER _ODP-PAYLOAD-CHAR
        58 OVER _ODP-PAYLOAD-CHAR
        34 OVER _ODP-PAYLOAD-CHAR
        DUP _ODPW.ATH-TEXT 43
            2 PICK _ODP-PAYLOAD-APPEND
        34 OVER _ODP-PAYLOAD-CHAR
    THEN

    125 OVER _ODP-PAYLOAD-CHAR

    DUP _ODPW.HTM-U @
    OVER _ODPW.HTU-U @
    2 PICK _ODPW.IAT @
    3 PICK _ODPW.NONCE-U @
    4 PICK _ODPW.TOKEN-U @
    _ODP-PAYLOAD-SIZE
    OVER _ODPW.CURSOR @ <> IF
        DROP OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    DUP _ODPW.CURSOR @ _ODP-MAX-PAYLOAD-SIZE U> IF
        DROP OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    DROP OAUTH2-DPOP-ES256-S-OK ;

: _ODP-SIGN-STAGED  ( workspace -- written status )
    >R
    R@ _ODPW.HEADER _ODP-HEADER-SIZE
    R@ _ODPW.PAYLOAD R@ _ODPW.CURSOR @
    R@ _ODPW.PRIVATE
    R@ _ODPW.PROOF OAUTH2-DPOP-ES256-MAX-PROOF-BYTES
    R@ _ODPW.JWS-WORK
    JOSE-JWS-ES256-SIGN
    DUP JOSE-JWS-ES256-S-OK <> IF
        >R DROP R> _ODP-JWS>STATUS
        R> DROP 0 SWAP EXIT
    THEN
    DROP

    _ODP-HEADER-SIZE R@ _ODPW.CURSOR @
    JOSE-JWS-ES256-COMPACT-SIZE
    DUP JOSE-JWS-ES256-S-OK <> IF
        DROP 2DROP R> DROP
        0 OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    DROP
    2DUP <> IF
        2DROP R> DROP 0 OAUTH2-DPOP-ES256-S-INTERNAL EXIT
    THEN
    DROP
    DUP R@ _ODPW.RESULT-U !
    R> DROP OAUTH2-DPOP-ES256-S-OK ;

: _ODP-RUN  ( workspace -- written status )
    DUP _ODP-STAGE-PRIVATE
    DUP _ODP-BUILD-JTI
    DUP IF NIP 0 SWAP EXIT THEN
    DROP
    DUP _ODP-DERIVE-PUBLIC
    DUP IF NIP 0 SWAP EXIT THEN
    DROP
    DUP _ODP-BUILD-HEADER
    DUP IF NIP 0 SWAP EXIT THEN
    DROP
    DUP _ODP-BUILD-ATH
    DUP IF NIP 0 SWAP EXIT THEN
    DROP
    DUP _ODP-BUILD-PAYLOAD
    DUP IF NIP 0 SWAP EXIT THEN
    DROP
    _ODP-SIGN-STAGED ;

\ =====================================================================
\  Binding, terminal publication, and mandatory cleanup
\ =====================================================================

: _ODP-BIND
  \ ( htm htm-u htu htu-u iat
  \   nonce nonce-u token token-u private destination capacity workspace
  \   -- workspace )
    DUP _ODP-WIPE
    12 PICK OVER _ODPW.HTM !
    11 PICK OVER _ODPW.HTM-U !
    10 PICK OVER _ODPW.HTU !
    9 PICK OVER _ODPW.HTU-U !
    8 PICK OVER _ODPW.IAT !
    7 PICK OVER _ODPW.NONCE !
    6 PICK OVER _ODPW.NONCE-U !
    5 PICK OVER _ODPW.TOKEN !
    4 PICK OVER _ODPW.TOKEN-U !
    3 PICK OVER _ODPW.PRIVATE-IN !
    2 PICK OVER _ODPW.DESTINATION !
    1 PICK OVER _ODPW.CAPACITY !
    >R _ODP-DROP12 R> ;

: _ODP-ADMITTED
  \ ( htm htm-u htu htu-u iat
  \   nonce nonce-u token token-u private destination capacity workspace
  \   -- written status )
    _ODP-BIND _ODP-RUN ;

: _ODP-PUBLISH  ( workspace -- written )
    DUP _ODPW.PROOF
    OVER _ODPW.DESTINATION @
    2 PICK _ODPW.RESULT-U @ MOVE
    _ODPW.RESULT-U @ ;

: _ODP-CALL-FINALLY
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

: _ODP-CALL
  \ ( thirteen arguments xt -- written status )
    1 PICK >R
    CATCH
    DUP IF
        >R _ODP-DROP13
        R> R> SWAP >R
        _ODP-WIPE
        R> THROW
    THEN
    DROP
    DUP IF
        R@ _ODP-WIPE
        R> DROP
        NIP 0 SWAP EXIT
    THEN
    DROP DROP
    R@ ['] _ODP-PUBLISH ['] _ODP-WIPE
        _ODP-CALL-FINALLY
    R> DROP
    OAUTH2-DPOP-ES256-S-OK ;

\ =====================================================================
\  Public constructor
\ =====================================================================

: OAUTH2-DPOP-ES256-PROOF
  \ ( htm htm-u htu htu-u iat
  \   nonce nonce-u access-token access-token-u private
  \   destination capacity workspace -- written status )
    _ODP-13DUP _ODP-GEOMETRY
    DUP IF
        >R _ODP-DROP13 R> 0 SWAP EXIT
    THEN
    DROP
    ['] _ODP-ADMITTED _ODP-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

: _ODP-GEOMETRY-ABORT  ( -- )
    ." OAuth2 DPoP ES256 workspace geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _ODP-GEOMETRY-ABORT
[THEN]

OAUTH2-DPOP-ES256-JTI-SIZE 22 <> [IF]
    _ODP-GEOMETRY-ABORT
[THEN]

OAUTH2-DPOP-ES256-MAX-PROOF-BYTES 11459 <> [IF]
    _ODP-GEOMETRY-ABORT
[THEN]

JOSE-JWK-P256-WORKSPACE-SIZE P256-WORKSPACE-SIZE U< [IF]
    _ODP-GEOMETRY-ABORT
[THEN]

_ODPW-JWS-WORK-OFF 8 MOD [IF]
    _ODP-GEOMETRY-ABORT
[THEN]

_ODPW-JWS-WORK-OFF JOSE-JWS-ES256-WORKSPACE-SIZE +
OAUTH2-DPOP-ES256-WORKSPACE-SIZE <> [IF]
    _ODP-GEOMETRY-ABORT
[THEN]
