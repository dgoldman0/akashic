\ =====================================================================
\  jwk-p256.f - Strict public P-256 JSON Web Keys and thumbprints
\ =====================================================================
\  This module is the generic JOSE boundary for an NIST P-256 public key.
\  It owns no key, current document, policy, or mutable scratch.  AT
\  Protocol, OAuth, Streams, and application-specific `kid`, `use`, and
\  `alg` policy deliberately live above this library.
\
\  Every admitted public JWK contains exactly one of each required member:
\
\      kty = "EC"
\      crv = "P-256"
\      x   = canonical unpadded Base64url of exactly 32 bytes
\      y   = canonical unpadded Base64url of exactly 32 bytes
\
\  Additional non-secret members are accepted and ignored by PUBLIC-PARSE
\  so a higher layer can apply `kid`, `use`, `alg`, certificate, or
\  application policy directly to the caller-owned source.  The decoded
\  member name `d` is always rejected rather than silently turning a
\  public-key parser into a private-key boundary.  The strict JSON
\  dependency rejects duplicate decoded names and trailing non-whitespace
\  input before this policy is applied.
\
\  The public-key boundary is the 65-byte uncompressed SEC 1 form
\  04 || X || Y.  Parsed coordinates are validated on P-256 before they
\  are published.  Emission always uses the RFC 7638 lexicographic member
\  order:
\
\      {"crv":"P-256","kty":"EC","x":"...","y":"..."}
\
\  All mutating APIs stage their result in a caller-owned bounded
\  workspace and publish only after the complete operation succeeds.
\  Validation/staging THROW is mapped to INTERNAL only after mandatory
\  cleanup succeeds.  Final caller-output publication is a separate phase:
\  publication THROW propagates after cleanup, and cleanup THROW propagates
\  with precedence.  Returned failures never publish caller output.
\
\  Public API:
\    JOSE-JWK-P256-PUBLIC-SIZE       ( -- 65 )
\    JOSE-JWK-P256-CANONICAL-SIZE    ( -- 126 )
\    JOSE-JWK-P256-THUMBPRINT-SIZE   ( -- 32 )
\    JOSE-JWK-P256-MAX-MEMBERS       ( -- 32 )
\    JOSE-JWK-P256-WORKSPACE-SIZE    ( -- bytes )
\    JOSE-JWK-P256-STATUS-VALID?     ( status -- flag )
\    JOSE-JWK-P256-CALLER-SPAN-STATUS
\      ( address length -- status )
\    JOSE-JWK-P256-WORKSPACE-CLEAR  ( workspace -- status )
\    JOSE-JWK-P256-PUBLIC-PARSE
\      ( source source-u public-output workspace -- status )
\    JOSE-JWK-P256-PUBLIC-EMIT
\      ( public destination capacity workspace -- written status )
\    JOSE-JWK-P256-THUMBPRINT
\      ( public digest-output workspace -- status )
\ =====================================================================

PROVIDED akashic-jose-jwk-p256

REQUIRE ../../utils/memory-span.f
REQUIRE ../../utils/caller-span.f
REQUIRE base64url.f
REQUIRE json-object.f
REQUIRE ../../math/sha256.f
REQUIRE ../../math/p256.f

\ =====================================================================
\  Public geometry and status vocabulary
\ =====================================================================

P256-PUBLIC-SIZE CONSTANT JOSE-JWK-P256-PUBLIC-SIZE
126              CONSTANT JOSE-JWK-P256-CANONICAL-SIZE
SHA256-LEN       CONSTANT JOSE-JWK-P256-THUMBPRINT-SIZE
32               CONSTANT JOSE-JWK-P256-MAX-MEMBERS

0 CONSTANT JOSE-JWK-P256-S-OK
1 CONSTANT JOSE-JWK-P256-S-INVALID
2 CONSTANT JOSE-JWK-P256-S-CAPACITY
3 CONSTANT JOSE-JWK-P256-S-ALIAS
4 CONSTANT JOSE-JWK-P256-S-JSON
5 CONSTANT JOSE-JWK-P256-S-POLICY
6 CONSTANT JOSE-JWK-P256-S-ENCODING
7 CONSTANT JOSE-JWK-P256-S-PUBLIC
8 CONSTANT JOSE-JWK-P256-S-CRYPTO
9 CONSTANT JOSE-JWK-P256-S-INTERNAL
10 CONSTANT JOSE-JWK-P256-S-RANGE
11 CONSTANT JOSE-JWK-P256-S-PROTECTED
12 CONSTANT JOSE-JWK-P256-S-PLATFORM

: JOSE-JWK-P256-STATUS-VALID?  ( status -- flag )
    DUP JOSE-JWK-P256-S-OK >=
    SWAP JOSE-JWK-P256-S-PLATFORM <= AND ;

JOSE-JWK-P256-MAX-MEMBERS JOSE-JSON-OBJECT-BYTES
JOSE-JSON-S-OK <> [IF]
    ." JOSE P-256 JWK descriptor geometry failed" CR ABORT
[THEN]
CONSTANT _JJPK-DESCRIPTOR-SIZE

JOSE-JWK-P256-MAX-MEMBERS CONSTANT _JJPK-MEMBER-CAPACITY
JOSE-JSON-MAX-NAME-BYTES CONSTANT _JJPK-NAMES-SIZE
43 CONSTANT _JJPK-COORDINATE-TEXT-SIZE

\ =====================================================================
\  Caller-owned workspace
\ =====================================================================
\  The first 128 bytes contain only operation-local borrowed pointers and
\  small scalar metadata.  The JSON parser's full bounded workspace is
\  retained so admitted metadata is validated with the same strict syntax,
\  Unicode, duplicate-name, and nesting rules as the required members.

  0 CONSTANT _JJPKW-SOURCE
  8 CONSTANT _JJPKW-SOURCE-U
 16 CONSTANT _JJPKW-OUTPUT
 24 CONSTANT _JJPKW-OUTPUT-CAPACITY
 32 CONSTANT _JJPKW-FLAGS
 40 CONSTANT _JJPKW-NAME-A
 48 CONSTANT _JJPKW-NAME-U
 56 CONSTANT _JJPKW-VALUE-A
 64 CONSTANT _JJPKW-VALUE-U
 72 CONSTANT _JJPKW-VALUE-TYPE
 80 CONSTANT _JJPKW-RESERVED0
 88 CONSTANT _JJPKW-RESERVED1
 96 CONSTANT _JJPKW-RESERVED2
104 CONSTANT _JJPKW-RESERVED3
112 CONSTANT _JJPKW-RESERVED4
120 CONSTANT _JJPKW-RESERVED5

128 CONSTANT _JJPKW-DESCRIPTOR-OFF
_JJPKW-DESCRIPTOR-OFF _JJPK-DESCRIPTOR-SIZE +
CONSTANT _JJPKW-NAMES-OFF
_JJPKW-NAMES-OFF _JJPK-NAMES-SIZE +
CONSTANT _JJPKW-JSON-OFF
_JJPKW-JSON-OFF JOSE-JSON-OBJECT-WORKSPACE-SIZE +
CONSTANT _JJPKW-P256-OFF
_JJPKW-P256-OFF P256-WORKSPACE-SIZE +
CONSTANT _JJPKW-PUBLIC-OFF
_JJPKW-PUBLIC-OFF JOSE-JWK-P256-PUBLIC-SIZE +
CONSTANT _JJPKW-CANONICAL-OFF
_JJPKW-CANONICAL-OFF JOSE-JWK-P256-CANONICAL-SIZE +
CONSTANT _JJPKW-DIGEST-OFF
_JJPKW-DIGEST-OFF JOSE-JWK-P256-THUMBPRINT-SIZE +
CONSTANT JOSE-JWK-P256-WORKSPACE-SIZE

: _JJPKW.SOURCE           ( w -- a ) _JJPKW-SOURCE + ;
: _JJPKW.SOURCE-U         ( w -- a ) _JJPKW-SOURCE-U + ;
: _JJPKW.OUTPUT           ( w -- a ) _JJPKW-OUTPUT + ;
: _JJPKW.OUTPUT-CAPACITY  ( w -- a ) _JJPKW-OUTPUT-CAPACITY + ;
: _JJPKW.FLAGS            ( w -- a ) _JJPKW-FLAGS + ;
: _JJPKW.NAME-A           ( w -- a ) _JJPKW-NAME-A + ;
: _JJPKW.NAME-U           ( w -- a ) _JJPKW-NAME-U + ;
: _JJPKW.VALUE-A          ( w -- a ) _JJPKW-VALUE-A + ;
: _JJPKW.VALUE-U          ( w -- a ) _JJPKW-VALUE-U + ;
: _JJPKW.VALUE-TYPE       ( w -- a ) _JJPKW-VALUE-TYPE + ;

: _JJPKW.DESCRIPTOR  ( w -- a ) _JJPKW-DESCRIPTOR-OFF + ;
: _JJPKW.NAMES       ( w -- a ) _JJPKW-NAMES-OFF + ;
: _JJPKW.JSON        ( w -- a ) _JJPKW-JSON-OFF + ;
: _JJPKW.P256        ( w -- a ) _JJPKW-P256-OFF + ;
: _JJPKW.PUBLIC      ( w -- a ) _JJPKW-PUBLIC-OFF + ;
: _JJPKW.CANONICAL   ( w -- a ) _JJPKW-CANONICAL-OFF + ;
: _JJPKW.DIGEST      ( w -- a ) _JJPKW-DIGEST-OFF + ;

: _JJPK-WIPE  ( workspace -- )
    JOSE-JWK-P256-WORKSPACE-SIZE 0 FILL ;

\ =====================================================================
\  Immutable canonical-serialization fragments
\ =====================================================================
\  CREATE bodies in this section are constant byte tables.  There is no
\  writable module-owned operation state.

31 CONSTANT _JJPK-CANONICAL-PREFIX-SIZE
 7 CONSTANT _JJPK-CANONICAL-MIDDLE-SIZE
 2 CONSTANT _JJPK-CANONICAL-SUFFIX-SIZE

31 CONSTANT _JJPK-CANONICAL-X-OFF
74 CONSTANT _JJPK-CANONICAL-MIDDLE-OFF
81 CONSTANT _JJPK-CANONICAL-Y-OFF
124 CONSTANT _JJPK-CANONICAL-SUFFIX-OFF

CREATE _JJPK-CANONICAL-PREFIX
    0x7B C, 0x22 C, 0x63 C, 0x72 C, 0x76 C, 0x22 C, 0x3A C, 0x22 C,
    0x50 C, 0x2D C, 0x32 C, 0x35 C, 0x36 C, 0x22 C, 0x2C C, 0x22 C,
    0x6B C, 0x74 C, 0x79 C, 0x22 C, 0x3A C, 0x22 C, 0x45 C, 0x43 C,
    0x22 C, 0x2C C, 0x22 C, 0x78 C, 0x22 C, 0x3A C, 0x22 C,

CREATE _JJPK-CANONICAL-MIDDLE
    0x22 C, 0x2C C, 0x22 C, 0x79 C, 0x22 C, 0x3A C, 0x22 C,

CREATE _JJPK-CANONICAL-SUFFIX
    0x22 C, 0x7D C,

\ =====================================================================
\  Caller admission and geometry
\ =====================================================================

: _JJPK-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _JJPK-DROP4  ( x1 x2 x3 x4 -- ) 2DROP 2DROP ;

: _JJPK-RETURN3  ( x1 x2 x3 status -- status )
    >R _JJPK-DROP3 R> ;

: _JJPK-RETURN4  ( x1 x2 x3 x4 status -- status )
    >R _JJPK-DROP4 R> ;

\ Preserve the generic caller-memory distinctions at this public boundary.
\ CALLER-SPAN-STATUS already catches BIOS faults and normalizes undocumented
\ results to PLATFORM.
: _JJPK-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP JOSE-JWK-P256-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP JOSE-JWK-P256-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP JOSE-JWK-P256-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP JOSE-JWK-P256-S-PLATFORM EXIT
    THEN
    DROP JOSE-JWK-P256-S-PLATFORM ;

\ SHA256-CALLER-SPAN-STATUS is the SHA layer's exported admission and
\ reserved-storage boundary.  Generic range/protected/platform distinctions
\ have already been preserved before this mapper is reached.
: _JJPK-SHA>STATUS  ( sha-status -- status )
    DUP SHA256-S-OK = IF
        DROP JOSE-JWK-P256-S-OK EXIT
    THEN
    DUP SHA256-S-RANGE = IF
        DROP JOSE-JWK-P256-S-RANGE EXIT
    THEN
    DUP SHA256-S-INVALID = IF
        DROP JOSE-JWK-P256-S-INVALID EXIT
    THEN
    DUP SHA256-S-ALIAS = IF
        DROP JOSE-JWK-P256-S-ALIAS EXIT
    THEN
    DUP SHA256-S-CRYPTO = IF
        DROP JOSE-JWK-P256-S-CRYPTO EXIT
    THEN
    DROP JOSE-JWK-P256-S-CRYPTO ;

\ The canonical fragments are immutable module data, not caller storage.
: _JJPK-LOCAL-RESERVED-OVERLAP?  ( address length -- flag )
    2DUP _JJPK-CANONICAL-PREFIX
        _JJPK-CANONICAL-PREFIX-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _JJPK-CANONICAL-MIDDLE
        _JJPK-CANONICAL-MIDDLE-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    _JJPK-CANONICAL-SUFFIX
        _JJPK-CANONICAL-SUFFIX-SIZE MSPAN-OVERLAP? ;

\ Qualify a complete advertised caller span before any mutation.  P-256
\ exposes its full lower-layer reserved footprint directly; SHA-256 exposes
\ the corresponding check through its caller-span status word.
: _JJPK-ADMIT-SPAN  ( address length -- status )
    2DUP CALLER-SPAN-STATUS _JJPK-CALLER>STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    2DUP P256-RESERVED-OVERLAP? IF
        2DROP JOSE-JWK-P256-S-ALIAS EXIT
    THEN
    2DUP _JJPK-LOCAL-RESERVED-OVERLAP? IF
        2DROP JOSE-JWK-P256-S-ALIAS EXIT
    THEN
    SHA256-CALLER-SPAN-STATUS _JJPK-SHA>STATUS ;

\ Export the complete nonmutating caller boundary so checked JOSE layers can
\ qualify their outer workspaces before any write.  This preserves the P-256,
\ immutable JWK serialization, and SHA-256 reserved footprints in one place.
: JOSE-JWK-P256-CALLER-SPAN-STATUS
  ( address length -- status )
    _JJPK-ADMIT-SPAN ;

: JOSE-JWK-P256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP JOSE-JWK-P256-WORKSPACE-SIZE _JJPK-ADMIT-SPAN
    ?DUP IF
        NIP EXIT
    THEN
    _JJPK-WIPE
    JOSE-JWK-P256-S-OK ;

: _JJPK-PARSE-GEOMETRY
  ( source source-u public-output workspace -- status )
    DUP JOSE-JWK-P256-WORKSPACE-SIZE _JJPK-ADMIT-SPAN
        ?DUP IF
        >R _JJPK-DROP4 R> EXIT
    THEN
    3 PICK 3 PICK _JJPK-ADMIT-SPAN ?DUP IF
        >R _JJPK-DROP4 R> EXIT
    THEN
    OVER JOSE-JWK-P256-PUBLIC-SIZE
        _JJPK-ADMIT-SPAN ?DUP IF
        >R _JJPK-DROP4 R> EXIT
    THEN
    2 PICK 0= IF
        JOSE-JWK-P256-S-INVALID _JJPK-RETURN4 EXIT
    THEN
    2 PICK JOSE-JSON-MAX-DOCUMENT-BYTES U> IF
        JOSE-JWK-P256-S-INVALID _JJPK-RETURN4 EXIT
    THEN

    3 PICK 3 PICK 3 PICK JOSE-JWK-P256-PUBLIC-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN4 EXIT
    THEN
    3 PICK 3 PICK 2 PICK JOSE-JWK-P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN4 EXIT
    THEN
    OVER JOSE-JWK-P256-PUBLIC-SIZE
        2 PICK JOSE-JWK-P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN4 EXIT
    THEN
    JOSE-JWK-P256-S-OK _JJPK-RETURN4 ;

: _JJPK-EMIT-GEOMETRY
  ( public destination capacity workspace -- status )
    DUP JOSE-JWK-P256-WORKSPACE-SIZE _JJPK-ADMIT-SPAN
        ?DUP IF
        >R _JJPK-DROP4 R> EXIT
    THEN
    3 PICK JOSE-JWK-P256-PUBLIC-SIZE
        _JJPK-ADMIT-SPAN ?DUP IF
        >R _JJPK-DROP4 R> EXIT
    THEN
    2 PICK 2 PICK _JJPK-ADMIT-SPAN ?DUP IF
        >R _JJPK-DROP4 R> EXIT
    THEN

    3 PICK JOSE-JWK-P256-PUBLIC-SIZE
        4 PICK 4 PICK MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN4 EXIT
    THEN
    3 PICK JOSE-JWK-P256-PUBLIC-SIZE
        2 PICK JOSE-JWK-P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN4 EXIT
    THEN
    2 PICK 2 PICK 2 PICK JOSE-JWK-P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN4 EXIT
    THEN
    1 PICK JOSE-JWK-P256-CANONICAL-SIZE U< IF
        JOSE-JWK-P256-S-CAPACITY _JJPK-RETURN4 EXIT
    THEN
    JOSE-JWK-P256-S-OK _JJPK-RETURN4 ;

: _JJPK-THUMBPRINT-GEOMETRY
  ( public digest-output workspace -- status )
    DUP JOSE-JWK-P256-WORKSPACE-SIZE _JJPK-ADMIT-SPAN
        ?DUP IF
        >R _JJPK-DROP3 R> EXIT
    THEN
    2 PICK JOSE-JWK-P256-PUBLIC-SIZE
        _JJPK-ADMIT-SPAN ?DUP IF
        >R _JJPK-DROP3 R> EXIT
    THEN
    OVER JOSE-JWK-P256-THUMBPRINT-SIZE
        _JJPK-ADMIT-SPAN ?DUP IF
        >R _JJPK-DROP3 R> EXIT
    THEN

    2 PICK JOSE-JWK-P256-PUBLIC-SIZE
        3 PICK JOSE-JWK-P256-THUMBPRINT-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN3 EXIT
    THEN
    2 PICK JOSE-JWK-P256-PUBLIC-SIZE
        2 PICK JOSE-JWK-P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN3 EXIT
    THEN
    OVER JOSE-JWK-P256-THUMBPRINT-SIZE
        2 PICK JOSE-JWK-P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        JOSE-JWK-P256-S-ALIAS _JJPK-RETURN3 EXIT
    THEN
    JOSE-JWK-P256-S-OK _JJPK-RETURN3 ;

\ =====================================================================
\  Mandatory cleanup
\ =====================================================================

\ An operation or publication THROW is rethrown after successful cleanup.
\ A cleanup THROW propagates directly and therefore takes precedence.
: _JJPK-CALL-FINALLY
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
\  Strict public-JWK parse
\ =====================================================================

: _JJPK-MEMBER-LOAD  ( index workspace -- status )
    >R
    R@ _JJPKW.DESCRIPTOR JOSE-JSON-OBJECT-MEMBER@
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP 2DROP
        R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP
    R@ _JJPKW.VALUE-TYPE !
    R@ _JJPKW.VALUE-U !
    R@ _JJPKW.SOURCE @ +
        R@ _JJPKW.VALUE-A !
    R@ _JJPKW.NAME-U !
    R@ _JJPKW.NAMES +
        R@ _JJPKW.NAME-A !
    R> DROP JOSE-JWK-P256-S-OK ;

: _JJPK-NAME=  ( expected-a expected-u workspace -- flag )
    >R
    R@ _JJPKW.NAME-A @ R@ _JJPKW.NAME-U @
    2SWAP COMPARE 0=
    R> DROP ;

: _JJPK-DECODE-MEMBER-STRING  ( workspace -- written status )
    DUP _JJPKW.VALUE-A @
    OVER _JJPKW.VALUE-U @
    2 PICK _JJPKW.CANONICAL
    JOSE-JWK-P256-CANONICAL-SIZE
    4 PICK _JJPKW.JSON
    JOSE-JSON-STRING-DECODE
    >R >R DROP R> R> ;

: _JJPK-STAGED=  ( expected-a expected-u decoded-u workspace -- flag )
    >R
    R@ _JJPKW.CANONICAL SWAP
    2SWAP COMPARE 0=
    R> DROP ;

: _JJPK-EXPECT-LITERAL  ( expected-a expected-u workspace -- status )
    >R
    R@ _JJPKW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        2DROP R> DROP JOSE-JWK-P256-S-POLICY EXIT
    THEN
    R@ _JJPK-DECODE-MEMBER-STRING
    DUP JOSE-JSON-S-OK <> IF
        2DROP 2DROP R> DROP JOSE-JWK-P256-S-JSON EXIT
    THEN
    DROP
    R@ _JJPK-STAGED= 0= IF
        R> DROP JOSE-JWK-P256-S-POLICY EXIT
    THEN
    R> DROP JOSE-JWK-P256-S-OK ;

: _JJPK-DECODE-COORDINATE  ( destination workspace -- status )
    >R
    R@ _JJPKW.VALUE-TYPE @ JOSE-JSON-T-STRING <> IF
        DROP R> DROP JOSE-JWK-P256-S-POLICY EXIT
    THEN
    R@ _JJPK-DECODE-MEMBER-STRING
    DUP JOSE-JSON-S-OK <> IF
        2DROP DROP R> DROP JOSE-JWK-P256-S-JSON EXIT
    THEN
    DROP
    _JJPK-COORDINATE-TEXT-SIZE <> IF
        DROP R> DROP JOSE-JWK-P256-S-ENCODING EXIT
    THEN

    R@ _JJPKW.CANONICAL _JJPK-COORDINATE-TEXT-SIZE
    ROT P256-SCALAR-SIZE
    JOSE-B64URL-DECODE
    DUP JOSE-B64URL-S-OK <> IF
        DUP JOSE-B64URL-S-INVALID = IF
            2DROP R> DROP JOSE-JWK-P256-S-ENCODING EXIT
        THEN
        2DROP R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP
    P256-SCALAR-SIZE <> IF
        R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    R> DROP JOSE-JWK-P256-S-OK ;

: _JJPK-SET-FLAG  ( mask workspace -- status )
    >R
    DUP R@ _JJPKW.FLAGS @ AND IF
        DROP R> DROP JOSE-JWK-P256-S-POLICY EXIT
    THEN
    R@ _JJPKW.FLAGS @ OR
    R@ _JJPKW.FLAGS !
    R> DROP JOSE-JWK-P256-S-OK ;

: _JJPK-PROCESS-MEMBER  ( index workspace -- status )
    >R
    DUP R@ _JJPK-MEMBER-LOAD
    DUP IF
        NIP R> DROP EXIT
    THEN
    2DROP

    \ An escaped spelling such as "\u0064" has already been decoded to `d`
    \ in the names buffer and therefore reaches this unconditional check.
    S" d" R@ _JJPK-NAME= IF
        R> DROP JOSE-JWK-P256-S-POLICY EXIT
    THEN

    S" kty" R@ _JJPK-NAME= IF
        S" EC" R@ _JJPK-EXPECT-LITERAL
        DUP IF R> DROP EXIT THEN DROP
        1 R@ _JJPK-SET-FLAG R> DROP EXIT
    THEN

    S" crv" R@ _JJPK-NAME= IF
        S" P-256" R@ _JJPK-EXPECT-LITERAL
        DUP IF R> DROP EXIT THEN DROP
        2 R@ _JJPK-SET-FLAG R> DROP EXIT
    THEN

    S" x" R@ _JJPK-NAME= IF
        R@ _JJPKW.PUBLIC 1+ R@ _JJPK-DECODE-COORDINATE
        DUP IF R> DROP EXIT THEN DROP
        4 R@ _JJPK-SET-FLAG R> DROP EXIT
    THEN

    S" y" R@ _JJPK-NAME= IF
        R@ _JJPKW.PUBLIC 33 + R@ _JJPK-DECODE-COORDINATE
        DUP IF R> DROP EXIT THEN DROP
        8 R@ _JJPK-SET-FLAG R> DROP EXIT
    THEN

    \ Unknown public metadata remains in the caller-owned source for a
    \ policy layer to enumerate independently.  This binary-key parser
    \ publishes only the validated SEC 1 point.
    R> DROP JOSE-JWK-P256-S-OK ;

: _JJPK-PROCESS-ALL  ( count workspace -- status )
    SWAP 0 ?DO
        I OVER _JJPK-PROCESS-MEMBER
        DUP IF
            NIP UNLOOP EXIT
        THEN
        DROP
    LOOP
    DROP JOSE-JWK-P256-S-OK ;

: _JJPK-VALIDATE-PUBLIC  ( public workspace -- status )
    >R
    R@ _JJPKW.P256 P256-PUBLIC-VALID?
    DUP P256-S-OK <> IF
        2DROP R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP 0= IF
        R> DROP JOSE-JWK-P256-S-PUBLIC EXIT
    THEN
    R> DROP JOSE-JWK-P256-S-OK ;

: _JJPK-PARSE-STAGE  ( workspace -- status )
    >R
    R@ _JJPKW.SOURCE @ R@ _JJPKW.SOURCE-U @
    R@ _JJPKW.DESCRIPTOR _JJPK-MEMBER-CAPACITY
    R@ _JJPKW.NAMES _JJPK-NAMES-SIZE
    R@ _JJPKW.JSON
    JOSE-JSON-OBJECT-PARSE
    JOSE-JSON-S-OK <> IF
        R> DROP JOSE-JWK-P256-S-JSON EXIT
    THEN

    R@ _JJPKW.DESCRIPTOR JOSE-JSON-OBJECT-COUNT@
    DUP JOSE-JSON-S-OK <> IF
        2DROP R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP
    DUP 4 < IF
        DROP R> DROP JOSE-JWK-P256-S-POLICY EXIT
    THEN

    0x04 R@ _JJPKW.PUBLIC C!
    0 R@ _JJPKW.FLAGS !
    R@ _JJPK-PROCESS-ALL
    DUP IF
        R> DROP EXIT
    THEN
    DROP

    R@ _JJPKW.FLAGS @ 15 <> IF
        R> DROP JOSE-JWK-P256-S-POLICY EXIT
    THEN
    R@ _JJPKW.PUBLIC R@ _JJPK-VALIDATE-PUBLIC
    DUP IF R> DROP EXIT THEN DROP

    R> DROP JOSE-JWK-P256-S-OK ;

\ =====================================================================
\  Canonical emission and RFC 7638 thumbprint
\ =====================================================================

: _JJPK-BUILD-CANONICAL  ( public workspace -- status )
    >R
    _JJPK-CANONICAL-PREFIX
    R@ _JJPKW.CANONICAL
    _JJPK-CANONICAL-PREFIX-SIZE MOVE
    _JJPK-CANONICAL-MIDDLE
    R@ _JJPKW.CANONICAL _JJPK-CANONICAL-MIDDLE-OFF +
    _JJPK-CANONICAL-MIDDLE-SIZE MOVE
    _JJPK-CANONICAL-SUFFIX
    R@ _JJPKW.CANONICAL _JJPK-CANONICAL-SUFFIX-OFF +
    _JJPK-CANONICAL-SUFFIX-SIZE MOVE

    DUP 1+ P256-SCALAR-SIZE
    R@ _JJPKW.CANONICAL _JJPK-CANONICAL-X-OFF +
    _JJPK-COORDINATE-TEXT-SIZE
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        2DROP DROP R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP _JJPK-COORDINATE-TEXT-SIZE <> IF
        DROP R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN

    33 + P256-SCALAR-SIZE
    R@ _JJPKW.CANONICAL _JJPK-CANONICAL-Y-OFF +
    _JJPK-COORDINATE-TEXT-SIZE
    JOSE-B64URL-ENCODE
    DUP JOSE-B64URL-S-OK <> IF
        2DROP R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP _JJPK-COORDINATE-TEXT-SIZE <> IF
        R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    R> DROP JOSE-JWK-P256-S-OK ;

: _JJPK-STAGE-PUBLIC  ( workspace -- workspace )
    DUP _JJPKW.SOURCE @
    OVER _JJPKW.PUBLIC
    JOSE-JWK-P256-PUBLIC-SIZE MOVE ;

: _JJPK-EMIT-STAGE  ( workspace -- status )
    _JJPK-STAGE-PUBLIC
    DUP _JJPKW.PUBLIC OVER _JJPK-VALIDATE-PUBLIC
    DUP IF NIP EXIT THEN
    DROP
    DUP _JJPKW.PUBLIC OVER _JJPK-BUILD-CANONICAL
    DUP IF NIP EXIT THEN
    DROP
    DROP JOSE-JWK-P256-S-OK ;

: _JJPK-THUMBPRINT-STAGE  ( workspace -- status )
    _JJPK-STAGE-PUBLIC
    DUP _JJPKW.PUBLIC OVER _JJPK-VALIDATE-PUBLIC
    DUP IF NIP EXIT THEN
    DROP
    DUP _JJPKW.PUBLIC OVER _JJPK-BUILD-CANONICAL
    DUP IF NIP EXIT THEN
    DROP
    DUP _JJPKW.CANONICAL JOSE-JWK-P256-CANONICAL-SIZE
    2 PICK _JJPKW.DIGEST SHA256-HASH
    DUP IF
        2DROP JOSE-JWK-P256-S-CRYPTO EXIT
    THEN
    DROP
    DROP JOSE-JWK-P256-S-OK ;

\ =====================================================================
\  Admitted staging and caller-output publication
\ =====================================================================

: _JJPK-PARSE-ADMITTED
  ( source source-u public-output workspace -- status )
    DUP _JJPK-WIPE
    3 PICK OVER _JJPKW.SOURCE !
    2 PICK OVER _JJPKW.SOURCE-U !
    OVER OVER _JJPKW.OUTPUT !
    NIP NIP NIP
    _JJPK-PARSE-STAGE ;

: _JJPK-EMIT-ADMITTED
  ( public destination capacity workspace -- status )
    DUP _JJPK-WIPE
    3 PICK OVER _JJPKW.SOURCE !
    2 PICK OVER _JJPKW.OUTPUT !
    1 PICK OVER _JJPKW.OUTPUT-CAPACITY !
    NIP NIP NIP
    _JJPK-EMIT-STAGE ;

: _JJPK-THUMBPRINT-ADMITTED
  ( public digest-output workspace -- status )
    DUP _JJPK-WIPE
    2 PICK OVER _JJPKW.SOURCE !
    OVER OVER _JJPKW.OUTPUT !
    NIP NIP
    _JJPK-THUMBPRINT-STAGE ;

: _JJPK-PARSE-PUBLISH  ( workspace -- )
    DUP _JJPKW.PUBLIC
    OVER _JJPKW.OUTPUT @
    JOSE-JWK-P256-PUBLIC-SIZE MOVE
    DROP ;

: _JJPK-EMIT-PUBLISH  ( workspace -- written )
    DUP _JJPKW.CANONICAL
    OVER _JJPKW.OUTPUT @
    JOSE-JWK-P256-CANONICAL-SIZE MOVE
    DROP JOSE-JWK-P256-CANONICAL-SIZE ;

: _JJPK-THUMBPRINT-PUBLISH  ( workspace -- )
    DUP _JJPKW.DIGEST
    OVER _JJPKW.OUTPUT @
    JOSE-JWK-P256-THUMBPRINT-SIZE MOVE
    DROP ;

: _JJPK-PARSE-CALL
  ( source source-u public-output workspace xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _JJPK-WIPE
        _JJPK-DROP4
        R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP
    DUP IF
        R@ _JJPK-WIPE
        R> DROP EXIT
    THEN
    DROP
    R@ ['] _JJPK-PARSE-PUBLISH ['] _JJPK-WIPE
        _JJPK-CALL-FINALLY
    R> DROP
    JOSE-JWK-P256-S-OK ;

: _JJPK-EMIT-CALL
  ( public destination capacity workspace xt -- written status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _JJPK-WIPE
        _JJPK-DROP4
        R> DROP 0 JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP
    DUP IF
        R@ _JJPK-WIPE
        R> DROP 0 SWAP EXIT
    THEN
    DROP
    R@ ['] _JJPK-EMIT-PUBLISH ['] _JJPK-WIPE
        _JJPK-CALL-FINALLY
    R> DROP
    JOSE-JWK-P256-S-OK ;

: _JJPK-THUMBPRINT-CALL
  ( public digest-output workspace xt -- status )
    1 PICK >R
    CATCH
    DUP IF
        DROP
        R@ _JJPK-WIPE
        _JJPK-DROP3
        R> DROP JOSE-JWK-P256-S-INTERNAL EXIT
    THEN
    DROP
    DUP IF
        R@ _JJPK-WIPE
        R> DROP EXIT
    THEN
    DROP
    R@ ['] _JJPK-THUMBPRINT-PUBLISH ['] _JJPK-WIPE
        _JJPK-CALL-FINALLY
    R> DROP
    JOSE-JWK-P256-S-OK ;

\ =====================================================================
\  Public entry points
\ =====================================================================

: JOSE-JWK-P256-PUBLIC-PARSE
  ( source source-u public-output workspace -- status )
    3 PICK 3 PICK 3 PICK 3 PICK _JJPK-PARSE-GEOMETRY
    DUP IF
        >R _JJPK-DROP4 R> EXIT
    THEN
    DROP
    ['] _JJPK-PARSE-ADMITTED _JJPK-PARSE-CALL ;

: JOSE-JWK-P256-PUBLIC-EMIT
  ( public destination capacity workspace -- written status )
    3 PICK 3 PICK 3 PICK 3 PICK _JJPK-EMIT-GEOMETRY
    DUP IF
        >R _JJPK-DROP4 R> 0 SWAP EXIT
    THEN
    DROP
    ['] _JJPK-EMIT-ADMITTED _JJPK-EMIT-CALL ;

: JOSE-JWK-P256-THUMBPRINT
  ( public digest-output workspace -- status )
    2 PICK 2 PICK 2 PICK _JJPK-THUMBPRINT-GEOMETRY
    DUP IF
        >R _JJPK-DROP3 R> EXIT
    THEN
    DROP
    ['] _JJPK-THUMBPRINT-ADMITTED _JJPK-THUMBPRINT-CALL ;
