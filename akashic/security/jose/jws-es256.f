\ =====================================================================
\  jws-es256.f - Strict caller-owned compact JWS with ES256
\ =====================================================================
\  This module implements the ordinary three-segment JWS Compact
\  Serialization for ECDSA over NIST P-256 and SHA-256.  It is a generic
\  JOSE boundary: it does not know about OAuth, DPoP, AT Protocol, Streams,
\  JWT claims, key discovery, or application-specific protected fields.
\
\  Signing preserves the exact caller-supplied protected-header JSON bytes
\  and accepts an arbitrary byte payload.  Verification publishes the exact
\  decoded protected-header and payload bytes.  The strict JSON dependency
\  requires a complete object, rejects duplicate decoded member names, and
\  this layer requires exactly one decoded `alg` member whose string value
\  is `ES256`.  Other protected members are left to the application except
\  that `crit` is rejected unconditionally: this library implements no JWS
\  extensions and therefore cannot claim to understand any critical one.
\  The transport-level `b64` extension is likewise rejected below.
\
\  Only RFC 7515's normal encoded-payload compact form is admitted:
\
\      BASE64URL(protected) || "." || BASE64URL(payload) || "." ||
\      BASE64URL(r || s)
\
\  Base64url is canonical and unpadded.  A zero-byte payload is represented
\  by an empty middle segment and is explicitly supported.  Empty protected
\  and signature segments, detached payloads, and RFC 7797 `b64:false`
\  processing are outside this API; a protected `b64` member is therefore
\  rejected rather than silently given ordinary encoded-payload semantics.
\  ES256 signatures are exactly 64 bytes in big-endian JOSE / IEEE P1363
\  form, never DER.
\
\  Every result is transactional.  Signing stages the complete compact JWS
\  before publishing it.  Verification stages both decoded outputs and
\  publishes neither until the signature is valid.  The module owns no key,
\  current operation, or mutable scratch.  Once a valid disjoint workspace
\  is admitted, that complete caller-owned workspace is cleared on success,
\  ordinary rejection, and THROW.
\
\  Production bounds:
\    protected header   <=  4,096 decoded bytes
\    payload            <= 65,536 decoded bytes
\    compact JWS        <= 92,932 encoded bytes
\    protected members <= 64
\
\  Public API:
\    JOSE-JWS-ES256-MAX-PROTECTED-BYTES  ( -- 4096 )
\    JOSE-JWS-ES256-MAX-PAYLOAD-BYTES    ( -- 65536 )
\    JOSE-JWS-ES256-MAX-COMPACT-BYTES    ( -- 92932 )
\    JOSE-JWS-ES256-SIGNATURE-SIZE       ( -- 64 )
\    JOSE-JWS-ES256-WORKSPACE-SIZE       ( -- bytes )
\    JOSE-JWS-ES256-STATUS-VALID?         ( status -- flag )
\    JOSE-JWS-ES256-COMPACT-SIZE
\      ( protected-u payload-u -- compact-u status )
\    JOSE-JWS-ES256-WORKSPACE-CLEAR       ( workspace -- status )
\    JOSE-JWS-ES256-SIGN
\      ( protected protected-u payload payload-u private
\        destination capacity workspace -- written status )
\    JOSE-JWS-ES256-VERIFY
\      ( compact compact-u public
\        protected-output protected-capacity
\        payload-output payload-capacity workspace
\        -- protected-u payload-u valid? status )
\ =====================================================================

PROVIDED akashic-jose-jws-es256

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE base64url.f
REQUIRE json-object.f
REQUIRE ../../math/sha256.f
REQUIRE ../../math/ecdsa-p256.f

\ =====================================================================
\  Public bounds and status vocabulary
\ =====================================================================

4096  CONSTANT JOSE-JWS-ES256-MAX-PROTECTED-BYTES
65536 CONSTANT JOSE-JWS-ES256-MAX-PAYLOAD-BYTES
ECDSA-P256-SIGNATURE-SIZE CONSTANT JOSE-JWS-ES256-SIGNATURE-SIZE

JOSE-JWS-ES256-MAX-PROTECTED-BYTES JOSE-B64URL-ENCODED-LENGTH
JOSE-B64URL-S-OK <> [IF]
    ." JOSE JWS ES256 protected geometry failed" CR ABORT
[THEN]
CONSTANT _JJWS-MAX-PROTECTED-TEXT

JOSE-JWS-ES256-MAX-PAYLOAD-BYTES JOSE-B64URL-ENCODED-LENGTH
JOSE-B64URL-S-OK <> [IF]
    ." JOSE JWS ES256 payload geometry failed" CR ABORT
[THEN]
CONSTANT _JJWS-MAX-PAYLOAD-TEXT

JOSE-JWS-ES256-SIGNATURE-SIZE JOSE-B64URL-ENCODED-LENGTH
JOSE-B64URL-S-OK <> [IF]
    ." JOSE JWS ES256 signature geometry failed" CR ABORT
[THEN]
CONSTANT _JJWS-SIGNATURE-TEXT-SIZE

_JJWS-MAX-PROTECTED-TEXT
_JJWS-MAX-PAYLOAD-TEXT + 2 +
_JJWS-SIGNATURE-TEXT-SIZE +
CONSTANT JOSE-JWS-ES256-MAX-COMPACT-BYTES

0  CONSTANT JOSE-JWS-ES256-S-OK
1  CONSTANT JOSE-JWS-ES256-S-INVALID
2  CONSTANT JOSE-JWS-ES256-S-CAPACITY
3  CONSTANT JOSE-JWS-ES256-S-ALIAS
4  CONSTANT JOSE-JWS-ES256-S-COMPACT
5  CONSTANT JOSE-JWS-ES256-S-ENCODING
6  CONSTANT JOSE-JWS-ES256-S-JSON
7  CONSTANT JOSE-JWS-ES256-S-ALGORITHM
8  CONSTANT JOSE-JWS-ES256-S-POLICY
9  CONSTANT JOSE-JWS-ES256-S-KEY
10 CONSTANT JOSE-JWS-ES256-S-SIGNATURE
11 CONSTANT JOSE-JWS-ES256-S-CRYPTO
12 CONSTANT JOSE-JWS-ES256-S-INTERNAL
13 CONSTANT JOSE-JWS-ES256-S-RANGE
14 CONSTANT JOSE-JWS-ES256-S-PROTECTED
15 CONSTANT JOSE-JWS-ES256-S-PLATFORM

: JOSE-JWS-ES256-STATUS-VALID?  ( status -- flag )
    DUP JOSE-JWS-ES256-S-OK >=
    SWAP JOSE-JWS-ES256-S-PLATFORM <= AND ;

64 CONSTANT _JJWS-MEMBER-CAPACITY

_JJWS-MEMBER-CAPACITY JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." JOSE JWS ES256 descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _JJWS-DESCRIPTOR-SIZE

JOSE-JSON-MAX-STRING-BYTES CONSTANT _JJWS-NAMES-SIZE

\ =====================================================================
\  Exact compact sizing
\ =====================================================================

: JOSE-JWS-ES256-COMPACT-SIZE
  ( protected-u payload-u -- compact-u status )
    DUP 0< IF
        2DROP 0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    DUP JOSE-JWS-ES256-MAX-PAYLOAD-BYTES U> IF
        2DROP 0 JOSE-JWS-ES256-S-CAPACITY EXIT
    THEN
    OVER 0> 0= IF
        2DROP 0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    OVER JOSE-JWS-ES256-MAX-PROTECTED-BYTES U> IF
        2DROP 0 JOSE-JWS-ES256-S-CAPACITY EXIT
    THEN

    JOSE-B64URL-ENCODED-LENGTH
    DUP JOSE-B64URL-S-OK <> IF
        2DROP DROP
        0 JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP >R
    JOSE-B64URL-ENCODED-LENGTH
    DUP JOSE-B64URL-S-OK <> IF
        2DROP R> DROP 0 JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    R> + 2 + _JJWS-SIGNATURE-TEXT-SIZE +
    JOSE-JWS-ES256-S-OK ;

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================
\  The first 256 bytes are pointer and scalar metadata.  A four-entry span
\  set follows so public operands can be checked pairwise before staging.
\  STAGE holds the maximum complete signing result; verification reuses its
\  prefix for decoded protected and payload bytes.  Secret digest, signature,
\  staged protected header and private key, ECDSA, JSON, and decoded-name
\  scratch are all inside the final wipe.

  0 CONSTANT _JJWSW-SOURCE0
  8 CONSTANT _JJWSW-SOURCE0-U
 16 CONSTANT _JJWSW-SOURCE1
 24 CONSTANT _JJWSW-SOURCE1-U
 32 CONSTANT _JJWSW-KEY
 40 CONSTANT _JJWSW-OUTPUT0
 48 CONSTANT _JJWSW-OUTPUT0-CAPACITY
 56 CONSTANT _JJWSW-OUTPUT1
 64 CONSTANT _JJWSW-OUTPUT1-CAPACITY

 72 CONSTANT _JJWSW-HEADER-A
 80 CONSTANT _JJWSW-HEADER-U
 88 CONSTANT _JJWSW-SEGMENT0-A
 96 CONSTANT _JJWSW-SEGMENT0-U
104 CONSTANT _JJWSW-SEGMENT1-A
112 CONSTANT _JJWSW-SEGMENT1-U
120 CONSTANT _JJWSW-SEGMENT2-A
128 CONSTANT _JJWSW-SEGMENT2-U

136 CONSTANT _JJWSW-DOT1
144 CONSTANT _JJWSW-DOT2
152 CONSTANT _JJWSW-RESULT-U
160 CONSTANT _JJWSW-FLAGS
168 CONSTANT _JJWSW-COUNT
176 CONSTANT _JJWSW-NAME-A
184 CONSTANT _JJWSW-NAME-U
192 CONSTANT _JJWSW-VALUE-A
200 CONSTANT _JJWSW-VALUE-U
208 CONSTANT _JJWSW-VALUE-TYPE
216 CONSTANT _JJWSW-DECODED0-U
224 CONSTANT _JJWSW-DECODED1-U
232 CONSTANT _JJWSW-INDEX
240 CONSTANT _JJWSW-RESERVED0
248 CONSTANT _JJWSW-RESERVED1

256 CONSTANT _JJWSW-SPANS-OFF
4 MSPAN-SET-BYTES
DUP 0= [IF]
    ." JOSE JWS ES256 span-set geometry failed" CR ABORT
[THEN]
CONSTANT _JJWS-SPANS-SIZE

_JJWSW-SPANS-OFF _JJWS-SPANS-SIZE +
CONSTANT _JJWSW-STAGE-OFF

_JJWSW-STAGE-OFF JOSE-JWS-ES256-MAX-COMPACT-BYTES +
7 + 8 / 8 *
CONSTANT _JJWSW-DIGEST-OFF

_JJWSW-DIGEST-OFF SHA256-LEN +
CONSTANT _JJWSW-SIGNATURE-OFF

_JJWSW-SIGNATURE-OFF JOSE-JWS-ES256-SIGNATURE-SIZE +
CONSTANT _JJWSW-ALG-OFF

_JJWSW-ALG-OFF 8 +
CONSTANT _JJWSW-ECDSA-OFF

_JJWSW-ECDSA-OFF ECDSA-P256-WORKSPACE-SIZE +
CONSTANT _JJWSW-DESCRIPTOR-OFF

_JJWSW-DESCRIPTOR-OFF _JJWS-DESCRIPTOR-SIZE +
CONSTANT _JJWSW-NAMES-OFF

_JJWSW-NAMES-OFF _JJWS-NAMES-SIZE +
CONSTANT _JJWSW-JSON-OFF

_JJWSW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
CONSTANT _JJWSW-PROTECTED-OFF

_JJWSW-PROTECTED-OFF JOSE-JWS-ES256-MAX-PROTECTED-BYTES +
CONSTANT _JJWSW-PRIVATE-OFF

_JJWSW-PRIVATE-OFF ECDSA-P256-PRIVATE-SIZE +
CONSTANT JOSE-JWS-ES256-WORKSPACE-SIZE

: _JJWSW.SOURCE0          ( w -- a ) _JJWSW-SOURCE0 + ;
: _JJWSW.SOURCE0-U        ( w -- a ) _JJWSW-SOURCE0-U + ;
: _JJWSW.SOURCE1          ( w -- a ) _JJWSW-SOURCE1 + ;
: _JJWSW.SOURCE1-U        ( w -- a ) _JJWSW-SOURCE1-U + ;
: _JJWSW.KEY              ( w -- a ) _JJWSW-KEY + ;
: _JJWSW.OUTPUT0          ( w -- a ) _JJWSW-OUTPUT0 + ;
: _JJWSW.OUTPUT0-CAPACITY ( w -- a ) _JJWSW-OUTPUT0-CAPACITY + ;
: _JJWSW.OUTPUT1          ( w -- a ) _JJWSW-OUTPUT1 + ;
: _JJWSW.OUTPUT1-CAPACITY ( w -- a ) _JJWSW-OUTPUT1-CAPACITY + ;

: _JJWSW.HEADER-A         ( w -- a ) _JJWSW-HEADER-A + ;
: _JJWSW.HEADER-U         ( w -- a ) _JJWSW-HEADER-U + ;
: _JJWSW.SEGMENT0-A       ( w -- a ) _JJWSW-SEGMENT0-A + ;
: _JJWSW.SEGMENT0-U       ( w -- a ) _JJWSW-SEGMENT0-U + ;
: _JJWSW.SEGMENT1-A       ( w -- a ) _JJWSW-SEGMENT1-A + ;
: _JJWSW.SEGMENT1-U       ( w -- a ) _JJWSW-SEGMENT1-U + ;
: _JJWSW.SEGMENT2-A       ( w -- a ) _JJWSW-SEGMENT2-A + ;
: _JJWSW.SEGMENT2-U       ( w -- a ) _JJWSW-SEGMENT2-U + ;

: _JJWSW.DOT1             ( w -- a ) _JJWSW-DOT1 + ;
: _JJWSW.DOT2             ( w -- a ) _JJWSW-DOT2 + ;
: _JJWSW.RESULT-U         ( w -- a ) _JJWSW-RESULT-U + ;
: _JJWSW.FLAGS            ( w -- a ) _JJWSW-FLAGS + ;
: _JJWSW.COUNT            ( w -- a ) _JJWSW-COUNT + ;
: _JJWSW.NAME-A           ( w -- a ) _JJWSW-NAME-A + ;
: _JJWSW.NAME-U           ( w -- a ) _JJWSW-NAME-U + ;
: _JJWSW.VALUE-A          ( w -- a ) _JJWSW-VALUE-A + ;
: _JJWSW.VALUE-U          ( w -- a ) _JJWSW-VALUE-U + ;
: _JJWSW.VALUE-TYPE       ( w -- a ) _JJWSW-VALUE-TYPE + ;
: _JJWSW.DECODED0-U       ( w -- a ) _JJWSW-DECODED0-U + ;
: _JJWSW.DECODED1-U       ( w -- a ) _JJWSW-DECODED1-U + ;
: _JJWSW.INDEX            ( w -- a ) _JJWSW-INDEX + ;

: _JJWSW.SPANS       ( w -- a ) _JJWSW-SPANS-OFF + ;
: _JJWSW.STAGE       ( w -- a ) _JJWSW-STAGE-OFF + ;
: _JJWSW.PAYLOAD     ( w -- a )
    _JJWSW-STAGE-OFF JOSE-JWS-ES256-MAX-PROTECTED-BYTES + + ;
: _JJWSW.DIGEST      ( w -- a ) _JJWSW-DIGEST-OFF + ;
: _JJWSW.SIGNATURE   ( w -- a ) _JJWSW-SIGNATURE-OFF + ;
: _JJWSW.ALG         ( w -- a ) _JJWSW-ALG-OFF + ;
: _JJWSW.ECDSA       ( w -- a ) _JJWSW-ECDSA-OFF + ;
: _JJWSW.DESCRIPTOR  ( w -- a ) _JJWSW-DESCRIPTOR-OFF + ;
: _JJWSW.NAMES       ( w -- a ) _JJWSW-NAMES-OFF + ;
: _JJWSW.JSON        ( w -- a ) _JJWSW-JSON-OFF + ;
: _JJWSW.PROTECTED   ( w -- a ) _JJWSW-PROTECTED-OFF + ;
: _JJWSW.PRIVATE     ( w -- a ) _JJWSW-PRIVATE-OFF + ;

: _JJWS-WIPE  ( workspace -- )
    JOSE-JWS-ES256-WORKSPACE-SIZE 0 FILL ;

: _JJWS-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP JOSE-JWS-ES256-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP JOSE-JWS-ES256-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP JOSE-JWS-ES256-S-PLATFORM EXIT
    THEN
    DROP JOSE-JWS-ES256-S-PLATFORM ;

: _JJWS-SHA-SPAN>STATUS  ( address length -- status )
    SHA256-CALLER-SPAN-STATUS
    DUP SHA256-S-OK = IF
        DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    DUP SHA256-S-INVALID = IF
        DROP JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    DUP SHA256-S-RANGE = IF
        DROP JOSE-JWS-ES256-S-RANGE EXIT
    THEN
    DUP SHA256-S-ALIAS = IF
        DROP JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    DROP JOSE-JWS-ES256-S-CRYPTO ;

: _JJWS-ADMIT-SPAN  ( address length -- status )
    2DUP CALLER-SPAN-STATUS _JJWS-CALLER>STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP ECDSA-P256-RESERVED-OVERLAP? IF
        2DROP JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    _JJWS-SHA-SPAN>STATUS ;

: JOSE-JWS-ES256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP JOSE-JWS-ES256-WORKSPACE-SIZE
        _JJWS-ADMIT-SPAN ?DUP IF
        NIP EXIT
    THEN
    _JJWS-WIPE JOSE-JWS-ES256-S-OK ;

\ =====================================================================
\  Geometry and operation admission
\ =====================================================================

: _JJWS-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _JJWS-NONEMPTY-SPAN?  ( address length -- flag )
    DUP 0> 0= IF 2DROP 0 EXIT THEN
    _JJWS-SPAN? ;

: _JJWS-FIXED-SPAN?  ( address length -- flag )
    _JJWS-NONEMPTY-SPAN? ;

: _JJWS-DROP7  ( seven values -- )
    2DROP 2DROP 2DROP DROP ;

: _JJWS-DROP8  ( eight values -- )
    2DROP 2DROP 2DROP 2DROP ;

: _JJWS-8DUP  ( eight values -- the same eight values twice )
    7 PICK 7 PICK 7 PICK 7 PICK
    7 PICK 7 PICK 7 PICK 7 PICK ;

: _JJWS-RETURN8-RESULT
  ( eight arguments result status -- result status )
    >R >R _JJWS-DROP8 R> R> ;

: _JJWS-OVER-WORKSPACE?
  ( address length workspace -- flag )
    JOSE-JWS-ES256-WORKSPACE-SIZE MSPAN-OVERLAP? ;

: _JJWS-SIGN-GEOMETRY
  \ ( protected protected-u payload payload-u private
  \   destination capacity workspace -- result-u status )
    DUP JOSE-JWS-ES256-WORKSPACE-SIZE
    _JJWS-FIXED-SPAN? 0= IF
        _JJWS-DROP8 0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    7 PICK 7 PICK _JJWS-NONEMPTY-SPAN? 0= IF
        _JJWS-DROP8 0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    5 PICK 5 PICK _JJWS-SPAN? 0= IF
        _JJWS-DROP8 0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    3 PICK ECDSA-P256-PRIVATE-SIZE
    _JJWS-FIXED-SPAN? 0= IF
        _JJWS-DROP8 0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    2 PICK 2 PICK _JJWS-SPAN? 0= IF
        _JJWS-DROP8 0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN

    DUP JOSE-JWS-ES256-WORKSPACE-SIZE
        _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> 0 SWAP EXIT
    THEN
    7 PICK 7 PICK _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> 0 SWAP EXIT
    THEN
    5 PICK 5 PICK _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> 0 SWAP EXIT
    THEN
    3 PICK ECDSA-P256-PRIVATE-SIZE
        _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> 0 SWAP EXIT
    THEN

    6 PICK 5 PICK JOSE-JWS-ES256-COMPACT-SIZE
    DUP IF
        _JJWS-RETURN8-RESULT EXIT
    THEN
    DROP >R

    1 PICK R@ U< IF
        R> DROP _JJWS-DROP8
        0 JOSE-JWS-ES256-S-CAPACITY EXIT
    THEN
    2 PICK R@ _JJWS-NONEMPTY-SPAN? 0= IF
        R> DROP _JJWS-DROP8
        0 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    2 PICK 2 PICK _JJWS-ADMIT-SPAN ?DUP IF
        >R
        _JJWS-DROP8
        R> R> DROP
        0 SWAP EXIT
    THEN

    7 PICK 7 PICK 2 PICK _JJWS-OVER-WORKSPACE? IF
        R> DROP _JJWS-DROP8
        0 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    5 PICK 5 PICK 2 PICK _JJWS-OVER-WORKSPACE? IF
        R> DROP _JJWS-DROP8
        0 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    3 PICK ECDSA-P256-PRIVATE-SIZE
    2 PICK _JJWS-OVER-WORKSPACE? IF
        R> DROP _JJWS-DROP8
        0 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    2 PICK R@ 2 PICK _JJWS-OVER-WORKSPACE? IF
        R> DROP _JJWS-DROP8
        0 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN

    R> JOSE-JWS-ES256-S-OK _JJWS-RETURN8-RESULT ;

: _JJWS-VERIFY-GEOMETRY
  \ ( compact compact-u public
  \   protected-output protected-capacity
  \   payload-output payload-capacity workspace -- status )
    DUP JOSE-JWS-ES256-WORKSPACE-SIZE
    _JJWS-FIXED-SPAN? 0= IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    7 PICK 7 PICK _JJWS-NONEMPTY-SPAN? 0= IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    6 PICK JOSE-JWS-ES256-MAX-COMPACT-BYTES U> IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-CAPACITY EXIT
    THEN
    5 PICK ECDSA-P256-PUBLIC-SIZE
    _JJWS-FIXED-SPAN? 0= IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    4 PICK 4 PICK _JJWS-SPAN? 0= IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-INVALID EXIT
    THEN
    2 PICK 2 PICK _JJWS-SPAN? 0= IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-INVALID EXIT
    THEN

    DUP JOSE-JWS-ES256-WORKSPACE-SIZE
        _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> EXIT
    THEN
    7 PICK 7 PICK _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> EXIT
    THEN
    5 PICK ECDSA-P256-PUBLIC-SIZE
        _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> EXIT
    THEN
    4 PICK 4 PICK _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> EXIT
    THEN
    2 PICK 2 PICK _JJWS-ADMIT-SPAN ?DUP IF
        >R _JJWS-DROP8 R> EXIT
    THEN

    7 PICK 7 PICK 2 PICK _JJWS-OVER-WORKSPACE? IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    5 PICK ECDSA-P256-PUBLIC-SIZE
    2 PICK _JJWS-OVER-WORKSPACE? IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    4 PICK 4 PICK 2 PICK _JJWS-OVER-WORKSPACE? IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    2 PICK 2 PICK 2 PICK _JJWS-OVER-WORKSPACE? IF
        _JJWS-DROP8 JOSE-JWS-ES256-S-ALIAS EXIT
    THEN

    _JJWS-DROP8 JOSE-JWS-ES256-S-OK ;

\ A valid workspace is admitted before public operands are collected into
\ this set.  Thus an overlap among public operands returns ALIAS with the
\ workspace scrubbed; an overlap with the workspace itself is rejected by
\ geometry before admission so wiping cannot damage a borrowed/output span.

: _JJWS-SPANS-BEGIN  ( workspace -- status )
    4 OVER _JJWSW.SPANS MSPAN-SET-INIT
    MSPAN-SET-S-OK <> IF
        DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-SPANS-ADD  ( address length workspace -- status )
    _JJWSW.SPANS MSPAN-SET-ADD
    DUP MSPAN-SET-S-OK = IF
        DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    MSPAN-SET-S-OVERLAP = IF
        JOSE-JWS-ES256-S-ALIAS EXIT
    THEN
    JOSE-JWS-ES256-S-INTERNAL ;

: _JJWS-SIGN-ALIASES  ( workspace -- status )
    DUP _JJWS-SPANS-BEGIN
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.SOURCE0 @
    OVER _JJWSW.SOURCE0-U @
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.SOURCE1 @
    OVER _JJWSW.SOURCE1-U @
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.KEY @ ECDSA-P256-PRIVATE-SIZE
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.OUTPUT0 @
    OVER _JJWSW.RESULT-U @
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-VERIFY-ALIASES  ( workspace -- status )
    DUP _JJWS-SPANS-BEGIN
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.SOURCE0 @
    OVER _JJWSW.SOURCE0-U @
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.KEY @ ECDSA-P256-PUBLIC-SIZE
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.OUTPUT0 @
    OVER _JJWSW.OUTPUT0-CAPACITY @
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DUP _JJWSW.OUTPUT1 @
    OVER _JJWSW.OUTPUT1-CAPACITY @
    2 PICK _JJWS-SPANS-ADD
    DUP IF NIP EXIT THEN DROP

    DROP JOSE-JWS-ES256-S-OK ;

\ =====================================================================
\  Strict protected-header policy
\ =====================================================================

: _JJWS-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _JJWSW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    R@ _JJWSW.VALUE-TYPE !
    R@ _JJWSW.VALUE-U !
    R@ _JJWSW.HEADER-A @ +
        R@ _JJWSW.VALUE-A !
    R@ _JJWSW.NAME-U !
    R@ _JJWSW.NAMES +
        R@ _JJWSW.NAME-A !
    R> DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-NAME=  ( expected expected-u workspace -- flag )
    >R
    R@ _JJWSW.NAME-A @ R@ _JJWSW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _JJWS-EXPECT-ES256  ( workspace -- status )
    >R
    R@ _JJWSW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        R> DROP JOSE-JWS-ES256-S-ALGORITHM EXIT
    THEN

    R@ _JJWSW.VALUE-A @ R@ _JJWSW.VALUE-U @
    R@ _JJWSW.JSON
    JOSE-JSON-STRING-MEASURE
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    5 <> IF
        R> DROP JOSE-JWS-ES256-S-ALGORITHM EXIT
    THEN

    R@ _JJWSW.VALUE-A @ R@ _JJWSW.VALUE-U @
    R@ _JJWSW.ALG 5 R@ _JJWSW.JSON
    JOSE-JSON-STRING-DECODE
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    5 <> IF
        R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN

    S" ES256" R@ _JJWSW.ALG 5 COMPARE 0= IF
        R> DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    R> DROP JOSE-JWS-ES256-S-ALGORITHM ;

: _JJWS-PROCESS-HEADER-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _JJWS-MEMBER-LOAD
    DUP IF
        NIP R> DROP EXIT
    THEN
    2DROP

    S" alg" R@ _JJWS-NAME= 0= IF
        \ RFC 7797 changes the exact signing input when `b64` is false.
        \ That extension is deliberately outside this ordinary encoded-
        \ payload API, so no `b64` member may be silently reinterpreted.
        S" b64" R@ _JJWS-NAME= IF
            R> DROP JOSE-JWS-ES256-S-POLICY EXIT
        THEN
        \ RFC 7515 requires every name listed by `crit` to be understood
        \ and processed.  This profile implements no extensions, so the
        \ presence of `crit` itself is unsupported regardless of its value.
        S" crit" R@ _JJWS-NAME= IF
            R> DROP JOSE-JWS-ES256-S-POLICY EXIT
        THEN
        R> DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    R@ _JJWSW.FLAGS @ IF
        R> DROP JOSE-JWS-ES256-S-ALGORITHM EXIT
    THEN
    R@ _JJWS-EXPECT-ES256
    DUP IF R> DROP EXIT THEN
    DROP
    1 R@ _JJWSW.FLAGS !
    R> DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-HEADER-VALIDATE  ( workspace -- status )
    DUP _JJWSW.HEADER-A @
    OVER _JJWSW.HEADER-U @
    2 PICK _JJWSW.DESCRIPTOR _JJWS-MEMBER-CAPACITY
    4 PICK _JJWSW.NAMES _JJWS-NAMES-SIZE
    6 PICK _JJWSW.JSON
    JOSE-JSON-OBJECT-PARSE
    DUP JOSE-JSON-S-OK <> IF
        2DROP JOSE-JWS-ES256-S-JSON EXIT
    THEN
    DROP

    DUP _JJWSW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    DUP 2 PICK _JJWSW.COUNT !
    0 2 PICK _JJWSW.FLAGS !

    0 ?DO
        I OVER _JJWS-PROCESS-HEADER-MEMBER
        DUP IF
            NIP UNLOOP EXIT
        THEN
        DROP
    LOOP

    DUP _JJWSW.FLAGS @ 1 <> IF
        DROP JOSE-JWS-ES256-S-ALGORITHM EXIT
    THEN
    DROP JOSE-JWS-ES256-S-OK ;

\ =====================================================================
\  Signing
\ =====================================================================

: _JJWS-MAP-SIGN-STATUS  ( ecdsa-status -- status )
    DUP ECDSA-P256-S-OK = IF
        DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    DUP ECDSA-P256-S-PRIVATE = IF
        DROP JOSE-JWS-ES256-S-KEY EXIT
    THEN
    DUP ECDSA-P256-S-NONCE = IF
        DROP JOSE-JWS-ES256-S-CRYPTO EXIT
    THEN
    DUP ECDSA-P256-S-CRYPTO = IF
        DROP JOSE-JWS-ES256-S-CRYPTO EXIT
    THEN
    DROP JOSE-JWS-ES256-S-INTERNAL ;

: _JJWS-SIGN-PREPARE  ( workspace -- status )
    DUP _JJWSW.SOURCE0-U @
    OVER _JJWSW.SOURCE1-U @
    JOSE-JWS-ES256-COMPACT-SIZE
    DUP IF
        2DROP DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    OVER _JJWSW.RESULT-U !
    DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-SIGN-STAGE-INPUTS  ( workspace -- )
    DUP _JJWSW.SOURCE0 @
    OVER _JJWSW.PROTECTED
    2 PICK _JJWSW.SOURCE0-U @ MOVE
    DUP _JJWSW.PROTECTED OVER _JJWSW.HEADER-A !
    DUP _JJWSW.SOURCE0-U @ OVER _JJWSW.HEADER-U !

    DUP _JJWSW.KEY @
    OVER _JJWSW.PRIVATE
    ECDSA-P256-PRIVATE-SIZE MOVE
    DUP _JJWSW.PRIVATE OVER _JJWSW.KEY !
    DROP ;

: _JJWS-SIGN-BUILD  ( workspace -- status )
    >R
    R@ _JJWSW.HEADER-A @ R@ _JJWSW.HEADER-U @
    R@ _JJWSW.STAGE _JJWS-MAX-PROTECTED-TEXT
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        2DROP R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    R@ _JJWSW.SEGMENT0-U !

    46 R@ _JJWSW.STAGE R@ _JJWSW.SEGMENT0-U @ + C!

    R@ _JJWSW.SOURCE1 @ R@ _JJWSW.SOURCE1-U @
    R@ _JJWSW.STAGE R@ _JJWSW.SEGMENT0-U @ + 1+
    _JJWS-MAX-PAYLOAD-TEXT
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        2DROP R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    R@ _JJWSW.SEGMENT1-U !

    R@ _JJWSW.SEGMENT0-U @ 1+
    R@ _JJWSW.SEGMENT1-U @ +
    DUP R@ _JJWSW.DOT2 !
    46 R@ _JJWSW.STAGE ROT + C!

    R@ _JJWSW.STAGE R@ _JJWSW.DOT2 @
    R@ _JJWSW.DIGEST SHA256-HASH
    DUP IF
        DROP R> DROP JOSE-JWS-ES256-S-CRYPTO EXIT
    THEN
    DROP

    R@ _JJWSW.DIGEST
    R@ _JJWSW.KEY @
    R@ _JJWSW.SIGNATURE
    R@ _JJWSW.ECDSA
    ECDSA-P256-SIGN-HASH
    _JJWS-MAP-SIGN-STATUS
    DUP IF
        R> DROP EXIT
    THEN
    DROP

    R@ _JJWSW.SIGNATURE JOSE-JWS-ES256-SIGNATURE-SIZE
    R@ _JJWSW.STAGE R@ _JJWSW.DOT2 @ + 1+
    _JJWS-SIGNATURE-TEXT-SIZE
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        2DROP R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    _JJWS-SIGNATURE-TEXT-SIZE <> IF
        R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN

    R@ _JJWSW.DOT2 @ 1+
    _JJWS-SIGNATURE-TEXT-SIZE +
    R@ _JJWSW.RESULT-U @ <> IF
        R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    R@ _JJWSW.STAGE
    R@ _JJWSW.OUTPUT0 @
    R@ _JJWSW.RESULT-U @ MOVE
    R> DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-SIGN-RUN  ( workspace -- written status )
    DUP _JJWS-SIGN-PREPARE
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    DUP _JJWS-SIGN-ALIASES
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    DUP _JJWS-SIGN-STAGE-INPUTS
    DUP _JJWS-HEADER-VALIDATE
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    DUP _JJWS-SIGN-BUILD
    DUP IF
        NIP 0 SWAP EXIT
    THEN
    DROP
    _JJWSW.RESULT-U @
    JOSE-JWS-ES256-S-OK ;

\ =====================================================================
\  Compact parsing and staged verification
\ =====================================================================

: _JJWS-RECORD-DOT  ( workspace -- status )
    DUP _JJWSW.COUNT @
    DUP 0= IF
        DROP
        DUP _JJWSW.INDEX @ OVER _JJWSW.DOT1 !
        1 OVER _JJWSW.COUNT +!
        DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    1 = IF
        DUP _JJWSW.INDEX @ OVER _JJWSW.DOT2 !
        1 OVER _JJWSW.COUNT +!
        DROP JOSE-JWS-ES256-S-OK EXIT
    THEN
    DROP JOSE-JWS-ES256-S-COMPACT ;

: _JJWS-SET-SEGMENTS  ( workspace -- status )
    >R
    R@ _JJWSW.SOURCE0 @ R@ _JJWSW.SEGMENT0-A !
    R@ _JJWSW.DOT1 @ R@ _JJWSW.SEGMENT0-U !

    R@ _JJWSW.SOURCE0 @ R@ _JJWSW.DOT1 @ + 1+
    R@ _JJWSW.SEGMENT1-A !
    R@ _JJWSW.DOT2 @ R@ _JJWSW.DOT1 @ - 1-
    R@ _JJWSW.SEGMENT1-U !

    R@ _JJWSW.SOURCE0 @ R@ _JJWSW.DOT2 @ + 1+
    R@ _JJWSW.SEGMENT2-A !
    R@ _JJWSW.SOURCE0-U @ R@ _JJWSW.DOT2 @ - 1-
    R@ _JJWSW.SEGMENT2-U !

    R@ _JJWSW.SEGMENT0-U @ 0= IF
        R> DROP JOSE-JWS-ES256-S-COMPACT EXIT
    THEN
    R@ _JJWSW.SEGMENT2-U @ 0= IF
        R> DROP JOSE-JWS-ES256-S-COMPACT EXIT
    THEN
    R> DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-SPLIT-COMPACT  ( workspace -- status )
    0 OVER _JJWSW.COUNT !
    0 OVER _JJWSW.INDEX !
    BEGIN
        DUP _JJWSW.INDEX @
        OVER _JJWSW.SOURCE0-U @ U<
    WHILE
        DUP _JJWSW.SOURCE0 @
        OVER _JJWSW.INDEX @ + C@
        46 = IF
            DUP _JJWS-RECORD-DOT
            DUP IF
                NIP EXIT
            THEN
            DROP
        THEN
        1 OVER _JJWSW.INDEX +!
    REPEAT
    DUP _JJWSW.COUNT @ 2 <> IF
        DROP JOSE-JWS-ES256-S-COMPACT EXIT
    THEN
    _JJWS-SET-SEGMENTS ;

: _JJWS-DECODED-LENGTH
  ( encoded encoded-u maximum -- decoded-u status )
    >R
    JOSE-B64URL-DECODED-LENGTH
    DUP JOSE-B64URL-S-OK <> IF
        2DROP R> DROP 0 JOSE-JWS-ES256-S-ENCODING EXIT
    THEN
    DROP
    DUP R@ U> IF
        DROP R> DROP 0 JOSE-JWS-ES256-S-CAPACITY EXIT
    THEN
    R> DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-VERIFY-LENGTHS  ( workspace -- status )
    >R
    R@ _JJWSW.SEGMENT0-A @ R@ _JJWSW.SEGMENT0-U @
    JOSE-JWS-ES256-MAX-PROTECTED-BYTES
    _JJWS-DECODED-LENGTH
    DUP IF
        2DROP R> DROP EXIT
    THEN
    DROP
    DUP 0= IF
        DROP R> DROP JOSE-JWS-ES256-S-COMPACT EXIT
    THEN
    R@ _JJWSW.DECODED0-U !

    R@ _JJWSW.SEGMENT1-A @ R@ _JJWSW.SEGMENT1-U @
    JOSE-JWS-ES256-MAX-PAYLOAD-BYTES
    _JJWS-DECODED-LENGTH
    DUP IF
        2DROP R> DROP EXIT
    THEN
    DROP
    R@ _JJWSW.DECODED1-U !

    R@ _JJWSW.SEGMENT2-A @ R@ _JJWSW.SEGMENT2-U @
    JOSE-JWS-ES256-MAX-COMPACT-BYTES
    _JJWS-DECODED-LENGTH
    DUP IF
        2DROP R> DROP EXIT
    THEN
    DROP
    JOSE-JWS-ES256-SIGNATURE-SIZE <> IF
        R> DROP JOSE-JWS-ES256-S-SIGNATURE EXIT
    THEN

    R@ _JJWSW.OUTPUT0-CAPACITY @
    R@ _JJWSW.DECODED0-U @ U< IF
        R> DROP JOSE-JWS-ES256-S-CAPACITY EXIT
    THEN
    R@ _JJWSW.OUTPUT1-CAPACITY @
    R@ _JJWSW.DECODED1-U @ U< IF
        R> DROP JOSE-JWS-ES256-S-CAPACITY EXIT
    THEN
    R> DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-DECODE-EXACT
  ( encoded encoded-u destination capacity expected-u -- status )
    >R
    JOSE-B64URL-DECODE
    DUP JOSE-B64URL-S-OK <> IF
        2DROP R> DROP JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    DROP
    R> <> IF
        JOSE-JWS-ES256-S-INTERNAL EXIT
    THEN
    JOSE-JWS-ES256-S-OK ;

: _JJWS-VERIFY-DECODE  ( workspace -- status )
    >R
    R@ _JJWSW.SEGMENT0-A @ R@ _JJWSW.SEGMENT0-U @
    R@ _JJWSW.STAGE JOSE-JWS-ES256-MAX-PROTECTED-BYTES
    R@ _JJWSW.DECODED0-U @
    _JJWS-DECODE-EXACT
    DUP IF R> DROP EXIT THEN
    DROP

    R@ _JJWSW.STAGE R@ _JJWSW.HEADER-A !
    R@ _JJWSW.DECODED0-U @ R@ _JJWSW.HEADER-U !
    R@ _JJWS-HEADER-VALIDATE
    DUP IF R> DROP EXIT THEN
    DROP

    R@ _JJWSW.SEGMENT1-A @ R@ _JJWSW.SEGMENT1-U @
    R@ _JJWSW.PAYLOAD JOSE-JWS-ES256-MAX-PAYLOAD-BYTES
    R@ _JJWSW.DECODED1-U @
    _JJWS-DECODE-EXACT
    DUP IF R> DROP EXIT THEN
    DROP

    R@ _JJWSW.SEGMENT2-A @ R@ _JJWSW.SEGMENT2-U @
    R@ _JJWSW.SIGNATURE JOSE-JWS-ES256-SIGNATURE-SIZE
    JOSE-JWS-ES256-SIGNATURE-SIZE
    _JJWS-DECODE-EXACT
    R> DROP ;

: _JJWS-MAP-VERIFY-FAILURE  ( ecdsa-status -- status )
    DUP ECDSA-P256-S-PUBLIC = IF
        DROP JOSE-JWS-ES256-S-KEY EXIT
    THEN
    DUP ECDSA-P256-S-SIGNATURE = IF
        DROP JOSE-JWS-ES256-S-SIGNATURE EXIT
    THEN
    DUP ECDSA-P256-S-CRYPTO = IF
        DROP JOSE-JWS-ES256-S-CRYPTO EXIT
    THEN
    DROP JOSE-JWS-ES256-S-INTERNAL ;

: _JJWS-VERIFY-SIGNATURE  ( workspace -- valid? status )
    >R
    R@ _JJWSW.SOURCE0 @ R@ _JJWSW.DOT2 @
    R@ _JJWSW.DIGEST SHA256-HASH
    DUP IF
        DROP R> DROP 0 JOSE-JWS-ES256-S-CRYPTO EXIT
    THEN
    DROP
    R@ _JJWSW.DIGEST
    R@ _JJWSW.KEY @
    R@ _JJWSW.SIGNATURE
    R@ _JJWSW.ECDSA
    ECDSA-P256-VERIFY-HASH
    DUP ECDSA-P256-S-OK <> IF
        _JJWS-MAP-VERIFY-FAILURE
        SWAP DROP
        0 SWAP
        R> DROP EXIT
    THEN
    DROP
    R> DROP JOSE-JWS-ES256-S-OK ;

: _JJWS-MOVE-WHEN  ( source destination length -- )
    DUP IF
        MOVE EXIT
    THEN
    2DROP DROP ;

: _JJWS-VERIFY-PUBLISH
  ( workspace -- protected-u payload-u valid? status )
    >R
    R@ _JJWSW.STAGE
    R@ _JJWSW.OUTPUT0 @
    R@ _JJWSW.DECODED0-U @ _JJWS-MOVE-WHEN
    R@ _JJWSW.PAYLOAD
    R@ _JJWSW.OUTPUT1 @
    R@ _JJWSW.DECODED1-U @ _JJWS-MOVE-WHEN
    R@ _JJWSW.DECODED0-U @
    R@ _JJWSW.DECODED1-U @
    -1 JOSE-JWS-ES256-S-OK
    R> DROP ;

: _JJWS-VERIFY-FAIL
  ( status -- protected-u payload-u valid? status )
    >R 0 0 0 R> ;

: _JJWS-VERIFY-RUN
  ( workspace -- protected-u payload-u valid? status )
    DUP _JJWS-VERIFY-ALIASES
    DUP IF
        NIP _JJWS-VERIFY-FAIL EXIT
    THEN
    DROP
    DUP _JJWS-SPLIT-COMPACT
    DUP IF
        NIP _JJWS-VERIFY-FAIL EXIT
    THEN
    DROP
    DUP _JJWS-VERIFY-LENGTHS
    DUP IF
        NIP _JJWS-VERIFY-FAIL EXIT
    THEN
    DROP
    DUP _JJWS-VERIFY-DECODE
    DUP IF
        NIP _JJWS-VERIFY-FAIL EXIT
    THEN
    DROP
    DUP _JJWS-VERIFY-SIGNATURE
    DUP IF
        >R 2DROP R> _JJWS-VERIFY-FAIL EXIT
    THEN
    DROP
    0= IF
        DROP 0 0 0 JOSE-JWS-ES256-S-OK EXIT
    THEN
    _JJWS-VERIFY-PUBLISH ;

\ =====================================================================
\  THROW-safe calls, argument binding, and public entry points
\ =====================================================================

: _JJWS-SIGN-CALL
  \ ( protected protected-u payload payload-u private
  \   destination capacity workspace xt -- written status )
    1 PICK >R
    CATCH
    DUP IF
        >R _JJWS-DROP8
        R> R> SWAP >R
        _JJWS-WIPE
        R> THROW
    THEN
    DROP
    R@ _JJWS-WIPE
    R> DROP ;

: _JJWS-VERIFY-CALL
  \ ( compact compact-u public
  \   protected-output protected-capacity
  \   payload-output payload-capacity workspace xt
  \   -- protected-u payload-u valid? status )
    1 PICK >R
    CATCH
    DUP IF
        >R _JJWS-DROP8
        R> R> SWAP >R
        _JJWS-WIPE
        R> THROW
    THEN
    DROP
    R@ _JJWS-WIPE
    R> DROP ;

: _JJWS-SIGN-BIND
  \ ( protected protected-u payload payload-u private
  \   destination capacity workspace -- workspace )
    DUP _JJWS-WIPE
    7 PICK OVER _JJWSW.SOURCE0 !
    6 PICK OVER _JJWSW.SOURCE0-U !
    5 PICK OVER _JJWSW.SOURCE1 !
    4 PICK OVER _JJWSW.SOURCE1-U !
    3 PICK OVER _JJWSW.KEY !
    2 PICK OVER _JJWSW.OUTPUT0 !
    1 PICK OVER _JJWSW.OUTPUT0-CAPACITY !
    >R _JJWS-DROP7 R> ;

: _JJWS-VERIFY-BIND
  \ ( compact compact-u public
  \   protected-output protected-capacity
  \   payload-output payload-capacity workspace -- workspace )
    DUP _JJWS-WIPE
    7 PICK OVER _JJWSW.SOURCE0 !
    6 PICK OVER _JJWSW.SOURCE0-U !
    5 PICK OVER _JJWSW.KEY !
    4 PICK OVER _JJWSW.OUTPUT0 !
    3 PICK OVER _JJWSW.OUTPUT0-CAPACITY !
    2 PICK OVER _JJWSW.OUTPUT1 !
    1 PICK OVER _JJWSW.OUTPUT1-CAPACITY !
    >R _JJWS-DROP7 R> ;

: _JJWS-SIGN-ADMITTED
  \ ( protected protected-u payload payload-u private
  \   destination capacity workspace -- written status )
    _JJWS-SIGN-BIND _JJWS-SIGN-RUN ;

: _JJWS-VERIFY-ADMITTED
  \ ( compact compact-u public
  \   protected-output protected-capacity
  \   payload-output payload-capacity workspace
  \   -- protected-u payload-u valid? status )
    _JJWS-VERIFY-BIND _JJWS-VERIFY-RUN ;

: JOSE-JWS-ES256-SIGN
  \ ( protected protected-u payload payload-u private
  \   destination capacity workspace -- written status )
    _JJWS-8DUP _JJWS-SIGN-GEOMETRY
    DUP IF
        >R DROP _JJWS-DROP8 R> 0 SWAP EXIT
    THEN
    2DROP
    ['] _JJWS-SIGN-ADMITTED _JJWS-SIGN-CALL ;

: JOSE-JWS-ES256-VERIFY
  \ ( compact compact-u public
  \   protected-output protected-capacity
  \   payload-output payload-capacity workspace
  \   -- protected-u payload-u valid? status )
    _JJWS-8DUP _JJWS-VERIFY-GEOMETRY
    DUP IF
        >R _JJWS-DROP8 R> _JJWS-VERIFY-FAIL EXIT
    THEN
    DROP
    ['] _JJWS-VERIFY-ADMITTED _JJWS-VERIFY-CALL ;

\ =====================================================================
\  Compile-time geometry assertions
\ =====================================================================

_JJWS-MAX-PROTECTED-TEXT 5462 <> [IF]
    ." JOSE JWS ES256 protected-text size mismatch" CR ABORT
[THEN]

_JJWS-MAX-PAYLOAD-TEXT 87382 <> [IF]
    ." JOSE JWS ES256 payload-text size mismatch" CR ABORT
[THEN]

_JJWS-SIGNATURE-TEXT-SIZE 86 <> [IF]
    ." JOSE JWS ES256 signature-text size mismatch" CR ABORT
[THEN]

JOSE-JWS-ES256-MAX-COMPACT-BYTES 92932 <> [IF]
    ." JOSE JWS ES256 compact size mismatch" CR ABORT
[THEN]

_JJWSW-ECDSA-OFF 8 MOD [IF]
    ." JOSE JWS ES256 ECDSA alignment mismatch" CR ABORT
[THEN]

_JJWSW-STAGE-OFF
JOSE-JWS-ES256-MAX-PROTECTED-BYTES +
JOSE-JWS-ES256-MAX-PAYLOAD-BYTES +
_JJWSW-DIGEST-OFF U> [IF]
    ." JOSE JWS ES256 verification stage overlap" CR ABORT
[THEN]
