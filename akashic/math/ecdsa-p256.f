\ =====================================================================
\  ecdsa-p256.f - Caller-owned deterministic ECDSA over NIST P-256
\ =====================================================================
\  This module supplies the generic raw-signature primitive required by
\  JOSE without owning a key, nonce state, current operation, or mutable
\  scratch.  Hashes, private scalars, public keys, and signatures use
\  big-endian protocol order at the public boundary.  A signature is the
\  fixed 64-byte IEEE P1363 / JOSE form r || s; DER is deliberately outside
\  this API.
\
\  Signing uses RFC 6979 HMAC-SHA-256 exactly.  It does not normalize s to
\  the lower half-order, so published RFC 6979 vectors are reproduced byte
\  for byte.  Candidate generation is bounded; the astronomically unlikely
\  r=0, s=0, or out-of-range candidate path performs RFC 6979's prescribed
\  K/V update before trying again.
\
\  The caller supplies one workspace and owns it exclusively from call through
\  return.  Borrowed inputs must remain immutable for that interval.  The
\  workspace contains all operation metadata, RFC 6979 state, subgroup-order
\  temporaries, the HMAC workspace, and the P-256 workspace.  Every admitted
\  operation attempts to clear that entire workspace after success, ordinary
\  rejection, lower-layer failure, and THROW.  An admitted THROW is reissued
\  after the outer wipe attempt because it may report a subordinate mandatory
\  cleanup failure.  Publication and outer-cleanup THROWs also propagate.
\  Pointer/alias rejection occurs before admission and therefore leaves all
\  caller memory unchanged.
\
\  ECDSA must switch the shared Field ALU between the P-256 field prime and
\  the subgroup order.  Each complete public operation holds field.f's
\  recursive transaction.  Curve work is performed only through p256.f's
\  public operations; verification uses P256-PUBLIC-SCALAR-LINCOMB.
\
\  Public API:
\    ECDSA-P256-HASH-SIZE        ( -- 32 )
\    ECDSA-P256-PRIVATE-SIZE     ( -- 32 )
\    ECDSA-P256-PUBLIC-SIZE      ( -- 65 )
\    ECDSA-P256-SIGNATURE-SIZE   ( -- 64 )
\    ECDSA-P256-WORKSPACE-SIZE   ( -- 2064 )
\    ECDSA-P256-STATUS-VALID?    ( status -- flag )
\    ECDSA-P256-WORKSPACE-CLEAR  ( workspace -- status )
\    ECDSA-P256-SIGN-HASH        ( hash private signature workspace
\                                  -- status )
\    ECDSA-P256-VERIFY-HASH      ( hash public signature workspace
\                                  -- valid? status )
\ =====================================================================

PROVIDED akashic-ecdsa-p256

REQUIRE hmac-sha256.f
REQUIRE p256.f
REQUIRE field.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Public constants and status vocabulary
\ =====================================================================

32 CONSTANT ECDSA-P256-HASH-SIZE
32 CONSTANT ECDSA-P256-PRIVATE-SIZE
65 CONSTANT ECDSA-P256-PUBLIC-SIZE
64 CONSTANT ECDSA-P256-SIGNATURE-SIZE

0 CONSTANT ECDSA-P256-S-OK
1 CONSTANT ECDSA-P256-S-RANGE
2 CONSTANT ECDSA-P256-S-PROTECTED
3 CONSTANT ECDSA-P256-S-PLATFORM
4 CONSTANT ECDSA-P256-S-ALIAS
5 CONSTANT ECDSA-P256-S-PRIVATE
6 CONSTANT ECDSA-P256-S-PUBLIC
7 CONSTANT ECDSA-P256-S-SIGNATURE
8 CONSTANT ECDSA-P256-S-NONCE
9 CONSTANT ECDSA-P256-S-CRYPTO
10 CONSTANT ECDSA-P256-S-INTERNAL

: ECDSA-P256-STATUS-VALID?  ( status -- flag )
    DUP ECDSA-P256-S-OK >=
    SWAP ECDSA-P256-S-INTERNAL <= AND ;

\ =====================================================================
\  Immutable subgroup-order constants
\ =====================================================================
\  Field values are little-endian internally.  A zero custom-prime pinv
\  selects the Field ALU's ordinary modular reduction, which accepts normal
\  (not Montgomery-domain) operands.  These CREATE bodies are immutable
\  tables, not operation storage.

CREATE _ECP-N
    0x51 C, 0x25 C, 0x63 C, 0xFC C, 0xC2 C, 0xCA C, 0xB9 C, 0xF3 C,
    0x84 C, 0x9E C, 0x17 C, 0xA7 C, 0xAD C, 0xFA C, 0xE6 C, 0xBC C,
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,
    0x00 C, 0x00 C, 0x00 C, 0x00 C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,

CREATE _ECP-PINV0
    0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C,
    0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C,
    0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C,
    0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C, 0 C,

64 CONSTANT _ECP-RFC6979-ATTEMPTS

\ =====================================================================
\  Caller-owned workspace layout
\ =====================================================================
\  +0..31 is pointer metadata.  Every cryptographic region begins on an
\  eight-byte boundary.  HMAC output, message, and sub-workspace are
\  pairwise disjoint, including from K, as required by HMAC-SHA256.

   0 CONSTANT _ECPW-HASH
   8 CONSTANT _ECPW-ARG1
  16 CONSTANT _ECPW-SIGNATURE
  24 CONSTANT _ECPW-RESERVED

  32 CONSTANT _ECPW-K
  64 CONSTANT _ECPW-V
  96 CONSTANT _ECPW-H1O
 128 CONSTANT _ECPW-NONCE
 160 CONSTANT _ECPW-R-BE
 192 CONSTANT _ECPW-S-BE

 224 CONSTANT _ECPW-D-LE
 256 CONSTANT _ECPW-E-LE
 288 CONSTANT _ECPW-K-LE
 320 CONSTANT _ECPW-R-LE
 352 CONSTANT _ECPW-S-LE
 384 CONSTANT _ECPW-T0
 416 CONSTANT _ECPW-T1

 448 CONSTANT _ECPW-U1-BE
 480 CONSTANT _ECPW-U2-BE
 512 CONSTANT _ECPW-POINT

 584 CONSTANT _ECPW-HMAC-OUTPUT
 616 CONSTANT _ECPW-HMAC-MESSAGE
 720 CONSTANT _ECPW-HMAC-WORKSPACE
 912 CONSTANT _ECPW-P256-WORKSPACE

_ECPW-P256-WORKSPACE P256-WORKSPACE-SIZE +
    CONSTANT ECDSA-P256-WORKSPACE-SIZE

: _ECPW.HASH            ( workspace -- address ) _ECPW-HASH + ;
: _ECPW.ARG1            ( workspace -- address ) _ECPW-ARG1 + ;
: _ECPW.SIGNATURE       ( workspace -- address ) _ECPW-SIGNATURE + ;

: _ECPW.K               ( workspace -- address ) _ECPW-K + ;
: _ECPW.V               ( workspace -- address ) _ECPW-V + ;
: _ECPW.H1O             ( workspace -- address ) _ECPW-H1O + ;
: _ECPW.NONCE           ( workspace -- address ) _ECPW-NONCE + ;
: _ECPW.R-BE            ( workspace -- address ) _ECPW-R-BE + ;
: _ECPW.S-BE            ( workspace -- address ) _ECPW-S-BE + ;

: _ECPW.D-LE            ( workspace -- address ) _ECPW-D-LE + ;
: _ECPW.E-LE            ( workspace -- address ) _ECPW-E-LE + ;
: _ECPW.K-LE            ( workspace -- address ) _ECPW-K-LE + ;
: _ECPW.R-LE            ( workspace -- address ) _ECPW-R-LE + ;
: _ECPW.S-LE            ( workspace -- address ) _ECPW-S-LE + ;
: _ECPW.T0              ( workspace -- address ) _ECPW-T0 + ;
: _ECPW.T1              ( workspace -- address ) _ECPW-T1 + ;

: _ECPW.U1-BE           ( workspace -- address ) _ECPW-U1-BE + ;
: _ECPW.U2-BE           ( workspace -- address ) _ECPW-U2-BE + ;
: _ECPW.POINT           ( workspace -- address ) _ECPW-POINT + ;
: _ECPW.HMAC-OUTPUT     ( workspace -- address ) _ECPW-HMAC-OUTPUT + ;
: _ECPW.HMAC-MESSAGE    ( workspace -- address ) _ECPW-HMAC-MESSAGE + ;
: _ECPW.HMAC-WORKSPACE  ( workspace -- address ) _ECPW-HMAC-WORKSPACE + ;
: _ECPW.P256-WORKSPACE  ( workspace -- address ) _ECPW-P256-WORKSPACE + ;

\ =====================================================================
\  Geometry, wiping, and fixed-width helpers
\ =====================================================================

: _ECP-DROP4  ( x1 x2 x3 x4 -- )
    2DROP 2DROP ;

: _ECP-4DUP  ( four values -- the same four values twice )
    3 PICK 3 PICK 3 PICK 3 PICK ;

\ Preserve physical-range, protected-memory, and platform failures instead
\ of collapsing memory that was unsafe to inspect into a key/signature error.
: _ECP-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP ECDSA-P256-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP ECDSA-P256-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP ECDSA-P256-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP ECDSA-P256-S-PLATFORM EXIT
    THEN
    DROP ECDSA-P256-S-PLATFORM ;

\ ECDSA calls HMAC-SHA256 internally, but its public signature output is not
\ an HMAC operand.  Qualify every public span against SHA-256's exposed
\ reserved boundary so a final signature MOVE cannot overwrite its guard.
: _ECP-SHA-SPAN>STATUS  ( address length -- status )
    SHA256-CALLER-SPAN-STATUS
    DUP SHA256-S-OK = IF
        DROP ECDSA-P256-S-OK EXIT
    THEN
    DUP SHA256-S-RANGE = IF
        DROP ECDSA-P256-S-RANGE EXIT
    THEN
    DUP SHA256-S-ALIAS = IF
        DROP ECDSA-P256-S-ALIAS EXIT
    THEN
    DROP ECDSA-P256-S-PLATFORM ;

\ The subgroup order and its custom-prime reduction parameter are immutable
\ implementation tables, never caller-owned storage.
: _ECP-TABLE-OVERLAP?  ( address length -- flag )
    2DUP _ECP-N ECDSA-P256-PRIVATE-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    _ECP-PINV0 ECDSA-P256-PRIVATE-SIZE MSPAN-OVERLAP? ;

: _ECP-FIXED-SPAN-STATUS  ( address fixed-size -- status )
    2DUP CALLER-SPAN-STATUS _ECP-CALLER>STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP _ECP-SHA-SPAN>STATUS ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP FIELD-RESERVED-OVERLAP? IF
        2DROP ECDSA-P256-S-ALIAS EXIT
    THEN
    2DUP P256-RESERVED-OVERLAP? IF
        2DROP ECDSA-P256-S-ALIAS EXIT
    THEN
    _ECP-TABLE-OVERLAP? IF
        ECDSA-P256-S-ALIAS
    ELSE
        ECDSA-P256-S-OK
    THEN ;

: _ECP-WIPE  ( workspace -- )
    ECDSA-P256-WORKSPACE-SIZE 0 FILL ;

\ Cleanup is mandatory after admission.  There is deliberately no exception
\ boundary here: a wipe THROW makes secret containment ambiguous and must
\ propagate instead of being mislabeled as a returned status.
: _ECP-CLEANUP-STATUS  ( status workspace wipe-xt -- status )
    EXECUTE ;

: _ECP-CLEANUP-RESULT
  ( valid? status workspace wipe-xt -- valid? status )
    EXECUTE ;

: ECDSA-P256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP ECDSA-P256-WORKSPACE-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        NIP EXIT
    THEN
    _ECP-WIPE
    ECDSA-P256-S-OK ;

: _ECP-REVERSE32  ( source destination -- )
    32 0 DO
        OVER I + C@
        OVER 31 I - + C!
    LOOP
    2DROP ;

: _ECP-BORROW  ( a b borrow -- borrow' )
    + U< 1 AND ;

\ Fixed-width little-endian comparison.  Every call performs all 32 byte
\ steps, including for private scalars and deterministic nonces.
: _ECP-LE-LT?  ( first second -- flag )
    0
    32 0 DO
        2 PICK I + C@
        2 PICK I + C@
        2 PICK _ECP-BORROW
        NIP
    LOOP
    0<> NIP NIP ;

: _ECP-NONZERO32?  ( address -- flag )
    0
    32 0 DO
        OVER I + C@ OR
    LOOP
    NIP 0<> ;

: _ECP-SCALAR-VALID?  ( scalar-le -- flag )
    DUP _ECP-NONZERO32?
    SWAP _ECP-N _ECP-LE-LT?
    AND ;

: _ECP-USE-N  ( -- )
    _ECP-N _ECP-PINV0 FIELD-LOAD-PRIME ;

\ Reject every pair of public spans.  This gives staged publication one
\ unambiguous ownership rule and prevents a workspace wipe from erasing a
\ borrowed input or caller destination.
: _ECP-SIGN-ALIASED?  ( hash private signature workspace -- flag )
    3 PICK ECDSA-P256-HASH-SIZE
    4 PICK ECDSA-P256-PRIVATE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    3 PICK ECDSA-P256-HASH-SIZE
    3 PICK ECDSA-P256-SIGNATURE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    3 PICK ECDSA-P256-HASH-SIZE
    2 PICK ECDSA-P256-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    2 PICK ECDSA-P256-PRIVATE-SIZE
    3 PICK ECDSA-P256-SIGNATURE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    2 PICK ECDSA-P256-PRIVATE-SIZE
    2 PICK ECDSA-P256-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    OVER ECDSA-P256-SIGNATURE-SIZE
    2 PICK ECDSA-P256-WORKSPACE-SIZE MSPAN-OVERLAP?
    >R _ECP-DROP4 R> ;

: _ECP-VERIFY-ALIASED?  ( hash public signature workspace -- flag )
    3 PICK ECDSA-P256-HASH-SIZE
    4 PICK ECDSA-P256-PUBLIC-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    3 PICK ECDSA-P256-HASH-SIZE
    3 PICK ECDSA-P256-SIGNATURE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    3 PICK ECDSA-P256-HASH-SIZE
    2 PICK ECDSA-P256-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    2 PICK ECDSA-P256-PUBLIC-SIZE
    3 PICK ECDSA-P256-SIGNATURE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    2 PICK ECDSA-P256-PUBLIC-SIZE
    2 PICK ECDSA-P256-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        _ECP-DROP4 -1 EXIT
    THEN
    OVER ECDSA-P256-SIGNATURE-SIZE
    2 PICK ECDSA-P256-WORKSPACE-SIZE MSPAN-OVERLAP?
    >R _ECP-DROP4 R> ;

: _ECP-SIGN-GEOMETRY  ( hash private signature workspace -- status )
    DUP ECDSA-P256-WORKSPACE-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    OVER ECDSA-P256-SIGNATURE-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    2 PICK ECDSA-P256-PRIVATE-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    3 PICK ECDSA-P256-HASH-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    3 PICK 3 PICK 3 PICK 3 PICK _ECP-SIGN-ALIASED? IF
        _ECP-DROP4 ECDSA-P256-S-ALIAS EXIT
    THEN
    _ECP-DROP4 ECDSA-P256-S-OK ;

: _ECP-VERIFY-GEOMETRY  ( hash public signature workspace -- status )
    DUP ECDSA-P256-WORKSPACE-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    OVER ECDSA-P256-SIGNATURE-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    2 PICK ECDSA-P256-PUBLIC-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    3 PICK ECDSA-P256-HASH-SIZE _ECP-FIXED-SPAN-STATUS
    ?DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    3 PICK 3 PICK 3 PICK 3 PICK _ECP-VERIFY-ALIASED? IF
        _ECP-DROP4 ECDSA-P256-S-ALIAS EXIT
    THEN
    _ECP-DROP4 ECDSA-P256-S-OK ;

: _ECP-BIND
  ( hash private-or-public signature workspace -- workspace )
    DUP _ECP-WIPE
    3 PICK OVER _ECPW.HASH !
    2 PICK OVER _ECPW.ARG1 !
    OVER OVER _ECPW.SIGNATURE !
    >R 2DROP DROP R> ;

\ =====================================================================
\  RFC 6979 HMAC-SHA-256 state machine
\ =====================================================================

\ HMAC-SHA256 receives six pairwise-safe operands:
\   key=K, message=HMAC-MESSAGE, digest=HMAC-OUTPUT,
\   workspace=HMAC-WORKSPACE.
\ The retained outer workspace is not one of HMAC-SHA256's arguments.
: _ECP-HMAC>STATUS  ( hmac-status -- status )
    DUP HMAC-SHA256-S-OK = IF
        DROP ECDSA-P256-S-OK EXIT
    THEN
    DUP HMAC-SHA256-S-CRYPTO = IF
        DROP ECDSA-P256-S-CRYPTO EXIT
    THEN
    DROP ECDSA-P256-S-INTERNAL ;

: _ECP-HMAC-AT  ( workspace message-u -- workspace hmac-status )
    >R
    DUP _ECPW.K ECDSA-P256-HASH-SIZE
    2 PICK _ECPW.HMAC-MESSAGE R@
    4 PICK _ECPW.HMAC-OUTPUT
    5 PICK _ECPW.HMAC-WORKSPACE
    HMAC-SHA256
    R> DROP ;

: _ECP-HMAC-INTO-K  ( workspace message-u -- workspace status )
    _ECP-HMAC-AT
    _ECP-HMAC>STATUS
    DUP ECDSA-P256-S-OK <> IF
        EXIT
    THEN
    DROP
    DUP _ECPW.HMAC-OUTPUT
    OVER _ECPW.K ECDSA-P256-HASH-SIZE MOVE
    ECDSA-P256-S-OK ;

: _ECP-HMAC-INTO-V  ( workspace message-u -- workspace status )
    _ECP-HMAC-AT
    _ECP-HMAC>STATUS
    DUP ECDSA-P256-S-OK <> IF
        EXIT
    THEN
    DROP
    DUP _ECPW.HMAC-OUTPUT
    OVER _ECPW.V ECDSA-P256-HASH-SIZE MOVE
    ECDSA-P256-S-OK ;

: _ECP-V-MESSAGE  ( workspace -- )
    DUP _ECPW.V
    OVER _ECPW.HMAC-MESSAGE
    ECDSA-P256-HASH-SIZE MOVE
    DROP ;

: _ECP-V0-MESSAGE  ( workspace -- )
    DUP _ECP-V-MESSAGE
    0 OVER _ECPW.HMAC-MESSAGE ECDSA-P256-HASH-SIZE + C!
    DROP ;

\ Build V || marker || int2octets(x) || bits2octets(h1).
: _ECP-RFC6979-SEED-MESSAGE  ( workspace marker -- )
    >R
    DUP _ECPW.V
    OVER _ECPW.HMAC-MESSAGE
    ECDSA-P256-HASH-SIZE MOVE
    R> OVER _ECPW.HMAC-MESSAGE ECDSA-P256-HASH-SIZE + C!
    \ RFC 6979 consumes the admitted private scalar, not borrowed caller
    \ memory that another execution could mutate after validation.
    DUP _ECPW.D-LE
    OVER _ECPW.HMAC-MESSAGE 33 +
    _ECP-REVERSE32
    DUP _ECPW.H1O
    OVER _ECPW.HMAC-MESSAGE 65 +
    ECDSA-P256-HASH-SIZE MOVE
    DROP ;

\ qlen=256 equals the SHA-256 width.  Since h1 < 2^256 < 2*n,
\ bits2octets is one reduction modulo n.
: _ECP-REDUCE-HASH  ( workspace -- )
    DUP _ECPW.HASH @
    OVER _ECPW.E-LE
    _ECP-REVERSE32
    _ECP-USE-N
    DUP _ECPW.T0 FIELD-ZERO
    DUP _ECPW.E-LE
    OVER _ECPW.T0
    2 PICK _ECPW.T1
    FIELD-ADD
    DUP _ECPW.T1
    OVER _ECPW.E-LE
    ECDSA-P256-HASH-SIZE MOVE
    DUP _ECPW.E-LE
    OVER _ECPW.H1O
    _ECP-REVERSE32
    DROP ;

: _ECP-RFC6979-INIT  ( workspace -- status )
    DUP _ECPW.K ECDSA-P256-HASH-SIZE 0 FILL
    DUP _ECPW.V ECDSA-P256-HASH-SIZE 1 FILL

    DUP 0 _ECP-RFC6979-SEED-MESSAGE
    97 _ECP-HMAC-INTO-K
    DUP IF NIP EXIT THEN DROP

    DUP _ECP-V-MESSAGE
    32 _ECP-HMAC-INTO-V
    DUP IF NIP EXIT THEN DROP

    DUP 1 _ECP-RFC6979-SEED-MESSAGE
    97 _ECP-HMAC-INTO-K
    DUP IF NIP EXIT THEN DROP

    DUP _ECP-V-MESSAGE
    32 _ECP-HMAC-INTO-V
    DUP IF NIP EXIT THEN DROP

    DROP ECDSA-P256-S-OK ;

\ Generate the next 256-bit candidate.  One V block supplies all of T.
: _ECP-RFC6979-NEXT  ( workspace -- candidate-valid? status )
    DUP _ECP-V-MESSAGE
    32 _ECP-HMAC-INTO-V
    DUP IF
        >R DROP 0 R> EXIT
    THEN
    DROP
    DUP _ECPW.V
    OVER _ECPW.NONCE
    ECDSA-P256-PRIVATE-SIZE MOVE
    DUP _ECPW.NONCE
    OVER _ECPW.K-LE
    _ECP-REVERSE32
    DUP _ECPW.K-LE _ECP-SCALAR-VALID?
    SWAP DROP
    ECDSA-P256-S-OK ;

\ RFC 6979 step H, used after an inadmissible k or the ECDSA r/s zero case.
: _ECP-RFC6979-REJECT  ( workspace -- status )
    DUP _ECP-V0-MESSAGE
    33 _ECP-HMAC-INTO-K
    DUP IF NIP EXIT THEN DROP

    DUP _ECP-V-MESSAGE
    32 _ECP-HMAC-INTO-V
    DUP IF NIP EXIT THEN DROP

    DROP ECDSA-P256-S-OK ;

\ =====================================================================
\  Deterministic signing under the Field transaction
\ =====================================================================

: _ECP-P256>STATUS  ( p256-status -- status )
    DUP P256-S-OK = IF
        DROP ECDSA-P256-S-OK EXIT
    THEN
    DUP P256-S-ALIAS = IF
        DROP ECDSA-P256-S-ALIAS EXIT
    THEN
    DUP P256-S-PRIVATE = IF
        \ ECDSA prevalidates every scalar sent to P-256.  A private-scalar
        \ rejection here is therefore an invariant failure; the generated
        \ nonce case is intercepted explicitly by _ECP-SIGN-CANDIDATE.
        DROP ECDSA-P256-S-INTERNAL EXIT
    THEN
    DUP P256-S-PUBLIC = IF
        DROP ECDSA-P256-S-PUBLIC EXIT
    THEN
    DUP P256-S-SCALAR = IF
        \ Verification also prevalidates both linear-combination scalars.
        DROP ECDSA-P256-S-INTERNAL EXIT
    THEN
    DUP P256-S-INTERNAL = IF
        DROP ECDSA-P256-S-INTERNAL EXIT
    THEN
    DUP P256-S-RANGE = IF
        DROP ECDSA-P256-S-RANGE EXIT
    THEN
    DUP P256-S-PROTECTED = IF
        DROP ECDSA-P256-S-PROTECTED EXIT
    THEN
    DUP P256-S-PLATFORM = IF
        DROP ECDSA-P256-S-PLATFORM EXIT
    THEN
    DUP P256-S-ENTROPY = IF
        DROP ECDSA-P256-S-INTERNAL EXIT
    THEN
    DUP P256-S-IDENTITY = IF
        DROP ECDSA-P256-S-INTERNAL EXIT
    THEN
    DROP ECDSA-P256-S-INTERNAL ;

: _ECP-SIGN-CANDIDATE  ( workspace -- produced? status )
    \ R = kG through the public, fixed-round P-256 operation.
    DUP _ECPW.NONCE
    OVER _ECPW.POINT
    2 PICK _ECPW.P256-WORKSPACE
    P256-PUBLIC-FROM-PRIVATE
    DUP P256-S-OK <> IF
        DUP P256-S-PRIVATE = IF
            2DROP 0 ECDSA-P256-S-NONCE EXIT
        THEN
        _ECP-P256>STATUS
        >R DROP 0 R> EXIT
    THEN
    DROP

    \ r = affine-x mod n.  P-256's field prime is less than 2*n, so the
    \ ordinary FIELD-ADD reduction performs at most one subtraction.
    DUP _ECPW.POINT 1+
    OVER _ECPW.T0
    _ECP-REVERSE32
    _ECP-USE-N
    DUP _ECPW.T1 FIELD-ZERO
    DUP _ECPW.T0
    OVER _ECPW.T1
    2 PICK _ECPW.R-LE
    FIELD-ADD
    DUP _ECPW.R-LE _ECP-NONZERO32? 0= IF
        DROP 0 ECDSA-P256-S-OK EXIT
    THEN
    DUP _ECPW.R-LE
    OVER _ECPW.R-BE
    _ECP-REVERSE32

    \ s = k^-1 * (e + r*d) mod n.
    DUP _ECPW.R-LE
    OVER _ECPW.D-LE
    2 PICK _ECPW.T0
    FIELD-MUL
    DUP _ECPW.E-LE
    OVER _ECPW.T0
    2 PICK _ECPW.T1
    FIELD-ADD
    DUP _ECPW.K-LE
    OVER _ECPW.S-LE
    FIELD-INV
    DUP _ECPW.S-LE
    OVER _ECPW.T1
    2 PICK _ECPW.T0
    FIELD-MUL
    DUP _ECPW.T0
    OVER _ECPW.S-LE
    ECDSA-P256-HASH-SIZE MOVE
    DUP _ECPW.S-LE _ECP-NONZERO32? 0= IF
        DROP 0 ECDSA-P256-S-OK EXIT
    THEN
    DUP _ECPW.S-LE
    OVER _ECPW.S-BE
    _ECP-REVERSE32
    DROP -1 ECDSA-P256-S-OK ;

: _ECP-SIGN-LOCKED  ( workspace -- status )
    DUP _ECPW.ARG1 @
    OVER _ECPW.D-LE
    _ECP-REVERSE32
    DUP _ECPW.D-LE _ECP-SCALAR-VALID? 0= IF
        DROP ECDSA-P256-S-PRIVATE EXIT
    THEN

    DUP _ECP-REDUCE-HASH
    DUP _ECP-RFC6979-INIT
    DUP IF NIP EXIT THEN DROP

    _ECP-RFC6979-ATTEMPTS 0 DO
        DUP _ECP-RFC6979-NEXT
        DUP IF
            >R 2DROP R> UNLOOP EXIT
        THEN
        DROP
        IF
            DUP _ECP-SIGN-CANDIDATE
            DUP IF
                >R 2DROP R> UNLOOP EXIT
            THEN
            DROP
            IF
                DROP ECDSA-P256-S-OK UNLOOP EXIT
            THEN
        THEN

        DUP _ECP-RFC6979-REJECT
        DUP IF
            NIP UNLOOP EXIT
        THEN
        DROP
    LOOP

    DROP ECDSA-P256-S-NONCE ;

: _ECP-SIGN-TRANSACTION  ( workspace -- status )
    ['] _ECP-SIGN-LOCKED FIELD-WITH-TRANSACTION ;

\ =====================================================================
\  Raw-signature verification under the Field transaction
\ =====================================================================

: _ECP-VERIFY-LOCKED  ( workspace -- valid? status )
    \ Decode and strictly validate raw r and s.
    DUP _ECPW.SIGNATURE @
    OVER _ECPW.R-LE
    _ECP-REVERSE32
    DUP _ECPW.SIGNATURE @ 32 +
    OVER _ECPW.S-LE
    _ECP-REVERSE32
    DUP _ECPW.R-LE _ECP-SCALAR-VALID? 0= IF
        DROP 0 ECDSA-P256-S-SIGNATURE EXIT
    THEN
    DUP _ECPW.S-LE _ECP-SCALAR-VALID? 0= IF
        DROP 0 ECDSA-P256-S-SIGNATURE EXIT
    THEN

    \ Distinguish malformed public geometry from an ordinary signature
    \ mismatch before performing the linear combination.
    DUP _ECPW.ARG1 @
    OVER _ECPW.P256-WORKSPACE
    P256-PUBLIC-VALID?
    DUP IF
        _ECP-P256>STATUS
        >R 2DROP 0 R> EXIT
    THEN
    DROP
    0= IF
        DROP 0 ECDSA-P256-S-PUBLIC EXIT
    THEN

    \ w=s^-1; u1=e*w; u2=r*w over the subgroup order.
    DUP _ECP-REDUCE-HASH
    _ECP-USE-N
    DUP _ECPW.S-LE
    OVER _ECPW.T0
    FIELD-INV
    DUP _ECPW.E-LE
    OVER _ECPW.T0
    2 PICK _ECPW.T1
    FIELD-MUL
    DUP _ECPW.R-LE
    OVER _ECPW.T0
    2 PICK _ECPW.K-LE
    FIELD-MUL
    DUP _ECPW.T1
    OVER _ECPW.U1-BE
    _ECP-REVERSE32
    DUP _ECPW.K-LE
    OVER _ECPW.U2-BE
    _ECP-REVERSE32

    \ R = u1*G + u2*Q through p256.f's public verification primitive.
    DUP _ECPW.U1-BE
    OVER _ECPW.U2-BE
    2 PICK _ECPW.ARG1 @
    3 PICK _ECPW.POINT
    4 PICK _ECPW.P256-WORKSPACE
    P256-PUBLIC-SCALAR-LINCOMB
    DUP IF
        DUP P256-S-IDENTITY = IF
            2DROP 0 ECDSA-P256-S-OK EXIT
        THEN
        DUP P256-S-PUBLIC = IF
            2DROP 0 ECDSA-P256-S-PUBLIC EXIT
        THEN
        _ECP-P256>STATUS
        >R DROP 0 R> EXIT
    THEN
    DROP

    \ v = affine-x mod n, then compare canonical little-endian scalars.
    DUP _ECPW.POINT 1+
    OVER _ECPW.T0
    _ECP-REVERSE32
    _ECP-USE-N
    DUP _ECPW.T1 FIELD-ZERO
    DUP _ECPW.T0
    OVER _ECPW.T1
    2 PICK _ECPW.K-LE
    FIELD-ADD
    DUP _ECPW.R-LE
    OVER _ECPW.K-LE
    FIELD-EQ?
    SWAP DROP
    ECDSA-P256-S-OK ;

: _ECP-VERIFY-TRANSACTION  ( workspace -- valid? status )
    ['] _ECP-VERIFY-LOCKED FIELD-WITH-TRANSACTION ;

\ =====================================================================
\  Exception-safe admission, publication, and public operations
\ =====================================================================
\  Geometry is checked before admission and leaves all caller memory
\  untouched.  The admitted computation boundary ends before signature
\  publication.  It catches only so the outer workspace can be wiped, then
\  rethrows: an untyped subordinate THROW may itself represent mandatory
\  lower-layer cleanup ambiguity and cannot safely become INTERNAL.
\
\  Signature publication has its own boundary solely to guarantee the same
\  wipe attempt before rethrowing a publication fault.  Mandatory cleanup is
\  never caught.  Verification publishes no output, but follows the same
\  rethrow-and-wipe rule and lets a cleanup fault escape.

: _ECP-STATUS>NORMAL  ( status -- status )
    DUP ECDSA-P256-STATUS-VALID? IF EXIT THEN
    DROP ECDSA-P256-S-INTERNAL ;

: _ECP-VERIFY-RESULT>NORMAL
  ( valid? status -- valid? status )
    DUP ECDSA-P256-STATUS-VALID? 0= IF
        2DROP 0 ECDSA-P256-S-INTERNAL EXIT
    THEN
    DUP ECDSA-P256-S-OK = IF
        SWAP 0<> SWAP EXIT
    THEN
    SWAP DROP 0 SWAP ;

: _ECP-SIGN-ADMITTED
  ( hash private signature workspace -- workspace status )
    _ECP-BIND
    DUP _ECP-SIGN-TRANSACTION
    _ECP-STATUS>NORMAL ;

: _ECP-VERIFY-ADMITTED
  ( hash public signature workspace -- workspace valid? status )
    _ECP-BIND
    DUP _ECP-VERIFY-TRANSACTION
    _ECP-VERIFY-RESULT>NORMAL ;

: _ECP-SIGN-CALL
  ( hash private signature workspace xt -- workspace status )
    1 PICK >R
    CATCH
    ?DUP IF
        R@ _ECP-WIPE
        >R _ECP-DROP4 R>
        R> DROP
        THROW
    THEN
    R> DROP ;

: _ECP-VERIFY-CALL
  ( hash public signature workspace xt -- workspace valid? status )
    1 PICK >R
    CATCH
    ?DUP IF
        R@ _ECP-WIPE
        >R _ECP-DROP4 R>
        R> DROP
        THROW
    THEN
    R> DROP ;

: _ECP-SIGN-CLEAR-RETURN  ( workspace status -- status )
    SWAP ['] _ECP-WIPE _ECP-CLEANUP-STATUS ;

: _ECP-VERIFY-CLEAR-RETURN
  ( workspace valid? status -- valid? status )
    ROT ['] _ECP-WIPE _ECP-CLEANUP-RESULT ;

\ R-BE and S-BE are compile-time checked adjacent, so one final MOVE starts
\ publication of the complete staged r || s value.  Retain workspace for the
\ mandatory wipe after successful publication.
: _ECP-SIGN-PUBLISH  ( workspace -- workspace )
    DUP _ECPW.R-BE
    OVER _ECPW.SIGNATURE @
    ECDSA-P256-SIGNATURE-SIZE MOVE ;

: _ECP-SIGN-PUBLISH-CLEAR
  ( workspace publish-xt -- status | throws )
    CATCH
    ?DUP IF
        >R
        _ECP-WIPE
        R> THROW
    THEN
    _ECP-WIPE
    ECDSA-P256-S-OK ;

: ECDSA-P256-SIGN-HASH
  ( hash private signature workspace -- status )
    _ECP-4DUP _ECP-SIGN-GEOMETRY
    DUP IF
        >R _ECP-DROP4 R> EXIT
    THEN
    DROP
    ['] _ECP-SIGN-ADMITTED
    _ECP-SIGN-CALL
    DUP IF
        _ECP-SIGN-CLEAR-RETURN EXIT
    THEN
    DROP
    ['] _ECP-SIGN-PUBLISH
    _ECP-SIGN-PUBLISH-CLEAR ;

: ECDSA-P256-VERIFY-HASH
  ( hash public signature workspace -- valid? status )
    _ECP-4DUP _ECP-VERIFY-GEOMETRY
    DUP IF
        >R _ECP-DROP4 0 R> EXIT
    THEN
    DROP
    ['] _ECP-VERIFY-ADMITTED
    _ECP-VERIFY-CALL
    _ECP-VERIFY-CLEAR-RETURN ;

\ =====================================================================
\  Compile-time workspace geometry checks
\ =====================================================================

: _ECP-GEOMETRY-ABORT  ( -- )
    ." ECDSA-P256 workspace geometry mismatch" CR ABORT ;

1 CELLS 8 <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-RESERVED 8 + _ECPW-K <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-K 32 + _ECPW-V <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-V 32 + _ECPW-H1O <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-H1O 32 + _ECPW-NONCE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-NONCE 32 + _ECPW-R-BE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-R-BE 32 + _ECPW-S-BE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-S-BE 32 + _ECPW-D-LE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-D-LE 32 + _ECPW-E-LE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-E-LE 32 + _ECPW-K-LE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-K-LE 32 + _ECPW-R-LE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-R-LE 32 + _ECPW-S-LE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-S-LE 32 + _ECPW-T0 <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-T0 32 + _ECPW-T1 <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-T1 32 + _ECPW-U1-BE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-U1-BE 32 + _ECPW-U2-BE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-U2-BE 32 + _ECPW-POINT <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-POINT ECDSA-P256-PUBLIC-SIZE +
    _ECPW-HMAC-OUTPUT > [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-HMAC-OUTPUT HMAC-SHA256-DIGEST-SIZE +
    _ECPW-HMAC-MESSAGE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-HMAC-MESSAGE 97 +
    _ECPW-HMAC-WORKSPACE > [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-HMAC-WORKSPACE HMAC-SHA256-WORKSPACE-SIZE +
    _ECPW-P256-WORKSPACE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]

_ECPW-P256-WORKSPACE P256-WORKSPACE-SIZE +
    ECDSA-P256-WORKSPACE-SIZE <> [IF]
    _ECP-GEOMETRY-ABORT
[THEN]
