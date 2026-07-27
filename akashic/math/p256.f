\ =====================================================================
\  p256.f - Caller-owned NIST P-256 point and key primitives
\ =====================================================================
\  This module supplies the curve operation needed below generic JOSE and
\  TLS-style consumers without owning a key, a current operation, or any
\  mutable scratch.  Private scalars and SEC 1 public keys use big-endian
\  wire order at the public boundary; the hardware Field ALU's little-
\  endian representation is confined to a caller-owned workspace.
\
\  Secret scalar multiplication executes exactly 256 rounds.  Every round
\  evaluates both R+R and (R+R)+G with the complete Renes-Costello-Batina
\  Algorithm 4 formula for a=-3, then selects the result bytewise with an
\  arithmetic mask.  There is no secret-dependent branch or table lookup.
\
\  The Field ALU prime selector is shared operation state.  This module
\  holds field.f's always-present recursive transaction across prime
\  selection, all point operations, and affine conversion.
\
\  Public API:
\    P256-PRIVATE-SIZE             ( -- 32 )
\    P256-SCALAR-SIZE              ( -- 32 )
\    P256-PUBLIC-SIZE              ( -- 65 )
\    P256-WORKSPACE-SIZE           ( -- 1152 )
\    P256-STATUS-VALID?            ( status -- flag )
\    P256-RESERVED-OVERLAP?        ( address length -- flag )
\    P256-WORKSPACE-CLEAR          ( workspace -- status )
\    P256-KEYGEN                   ( private-output public-output
\                                     workspace -- status )
\    P256-PUBLIC-FROM-PRIVATE      ( private public workspace -- status )
\    P256-PUBLIC-VALID?            ( public workspace -- valid? status )
\    P256-PUBLIC-SCALAR-LINCOMB    ( scalar-g scalar-q public-q
\                                     result workspace -- status )
\
\  A public key is the uncompressed SEC 1 encoding 04 || X || Y.  The caller
\  owns a workspace exclusively from call through return and keeps borrowed
\  inputs immutable for that interval.  Failed geometry checks do not touch
\  caller memory.  Once a workspace has been admitted, cleanup is attempted
\  after success, ordinary rejection, and THROW.  Unexpected operation,
\  publication, and cleanup faults propagate; no returned status conceals
\  ambiguous output publication or workspace wipe completion.  KEYGEN
\  obtains unbiased candidates only from checked
\  ENTROPY-FILL and stages both outputs before one final publication phase.
\  Publication is an in-process commit point, not power-failure atomicity
\  across the two caller buffers.  Its rejection loop is bounded and fails
\  closed.  PUBLIC-FROM-PRIVATE similarly starts copying its result only
\  after the complete computation succeeds.
\  PUBLIC-SCALAR-LINCOMB computes
\  scalar-g*G + scalar-q*Q.  Its two scalars are public protocol values,
\  accept zero, and must be less than the subgroup order.  Nevertheless,
\  its point computation uses a fixed 256-round branchless schedule.
\ =====================================================================

PROVIDED akashic-p256

REQUIRE ../utils/memory-span.f
REQUIRE ../utils/caller-span.f
REQUIRE field.f
REQUIRE entropy.f

\ =====================================================================
\  Public constants and status vocabulary
\ =====================================================================

32   CONSTANT P256-SCALAR-SIZE
P256-SCALAR-SIZE CONSTANT P256-PRIVATE-SIZE
65   CONSTANT P256-PUBLIC-SIZE
1152 CONSTANT P256-WORKSPACE-SIZE

0 CONSTANT P256-S-OK
1 CONSTANT P256-S-RANGE
2 CONSTANT P256-S-PROTECTED
3 CONSTANT P256-S-PLATFORM
4 CONSTANT P256-S-ALIAS
5 CONSTANT P256-S-PRIVATE
6 CONSTANT P256-S-PUBLIC
7 CONSTANT P256-S-SCALAR
8 CONSTANT P256-S-IDENTITY
9 CONSTANT P256-S-ENTROPY
10 CONSTANT P256-S-INTERNAL

16 CONSTANT _P256-KEYGEN-ATTEMPTS

\ RANGE, PROTECTED, and PLATFORM preserve the generic caller-memory boundary;
\ ALIAS is a forbidden overlap;
\ PRIVATE is d=0 or d>=n; PUBLIC is a malformed/noncanonical/off-curve Q;
\ SCALAR is a public linear-combination scalar >=n; IDENTITY means that a
\ valid linear combination has no SEC 1 encoding; ENTROPY means checked
\ entropy is unavailable; INTERNAL covers bounded keygen rejection
\ exhaustion or an impossible subordinate status; PLATFORM is an unexpected
\ caller-memory qualification result.  A returned failure selected before
\ final publication leaves outputs untouched.  A fault during publication
\ may expose a partial copy and therefore propagates.
: P256-STATUS-VALID?  ( status -- flag )
    DUP P256-S-OK >=
    SWAP P256-S-INTERNAL <= AND ;

\ =====================================================================
\  Immutable curve constants
\ =====================================================================
\  Field constants are little-endian to match the hardware Field ALU.
\  These CREATE bodies are immutable tables, not operation storage.

CREATE _P256-GX
    0x96 C, 0xC2 C, 0x98 C, 0xD8 C, 0x45 C, 0x39 C, 0xA1 C, 0xF4 C,
    0xA0 C, 0x33 C, 0xEB C, 0x2D C, 0x81 C, 0x7D C, 0x03 C, 0x77 C,
    0xF2 C, 0x40 C, 0xA4 C, 0x63 C, 0xE5 C, 0xE6 C, 0xBC C, 0xF8 C,
    0x47 C, 0x42 C, 0x2C C, 0xE1 C, 0xF2 C, 0xD1 C, 0x17 C, 0x6B C,

CREATE _P256-GY
    0xF5 C, 0x51 C, 0xBF C, 0x37 C, 0x68 C, 0x40 C, 0xB6 C, 0xCB C,
    0xCE C, 0x5E C, 0x31 C, 0x6B C, 0x57 C, 0x33 C, 0xCE C, 0x2B C,
    0x16 C, 0x9E C, 0x0F C, 0x7C C, 0x4A C, 0xEB C, 0xE7 C, 0x8E C,
    0x9B C, 0x7F C, 0x1A C, 0xFE C, 0xE2 C, 0x42 C, 0xE3 C, 0x4F C,

CREATE _P256-B
    0x4B C, 0x60 C, 0xD2 C, 0x27 C, 0x3E C, 0x3C C, 0xCE C, 0x3B C,
    0xF6 C, 0xB0 C, 0x53 C, 0xCC C, 0xB0 C, 0x06 C, 0x1D C, 0x65 C,
    0xBC C, 0x86 C, 0x98 C, 0x76 C, 0x55 C, 0xBD C, 0xEB C, 0xB3 C,
    0xE7 C, 0x93 C, 0x3A C, 0xAA C, 0xD8 C, 0x35 C, 0xC6 C, 0x5A C,

CREATE _P256-P
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,
    0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C, 0x00 C,
    0x01 C, 0x00 C, 0x00 C, 0x00 C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,

CREATE _P256-N
    0x51 C, 0x25 C, 0x63 C, 0xFC C, 0xC2 C, 0xCA C, 0xB9 C, 0xF3 C,
    0x84 C, 0x9E C, 0x17 C, 0xA7 C, 0xAD C, 0xFA C, 0xE6 C, 0xBC C,
    0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,
    0x00 C, 0x00 C, 0x00 C, 0x00 C, 0xFF C, 0xFF C, 0xFF C, 0xFF C,

\ =====================================================================
\  Caller-owned workspace layout
\ =====================================================================

   0 CONSTANT _P256W-SCALAR
  32 CONSTANT _P256W-BASE
 128 CONSTANT _P256W-R
 224 CONSTANT _P256W-DOUBLE
 320 CONSTANT _P256W-ADD

 416 CONSTANT _P256W-T0
 448 CONSTANT _P256W-T1
 480 CONSTANT _P256W-T2
 512 CONSTANT _P256W-T3
 544 CONSTANT _P256W-T4
 576 CONSTANT _P256W-T5
 608 CONSTANT _P256W-T6
 640 CONSTANT _P256W-T7
 672 CONSTANT _P256W-T8
 704 CONSTANT _P256W-T9
 736 CONSTANT _P256W-T10
 768 CONSTANT _P256W-T11
 800 CONSTANT _P256W-T12
 832 CONSTANT _P256W-T13
 864 CONSTANT _P256W-T14

 896 CONSTANT _P256W-AFFINE-X
 928 CONSTANT _P256W-AFFINE-Y
 960 CONSTANT _P256W-ENCODED

1032 CONSTANT _P256W-INPUT
1040 CONSTANT _P256W-OUTPUT
1048 CONSTANT _P256W-POINT-P
1056 CONSTANT _P256W-POINT-Q
1064 CONSTANT _P256W-POINT-R
1072 CONSTANT _P256W-MASK
1080 CONSTANT _P256W-INPUT2
1088 CONSTANT _P256W-INPUT3
1096 CONSTANT _P256W-PRIVATE-STAGED

: _P256W.SCALAR    ( workspace -- address ) _P256W-SCALAR + ;
: _P256W.BASE      ( workspace -- address ) _P256W-BASE + ;
: _P256W.R         ( workspace -- address ) _P256W-R + ;
: _P256W.DOUBLE    ( workspace -- address ) _P256W-DOUBLE + ;
: _P256W.ADD       ( workspace -- address ) _P256W-ADD + ;

: _P256W.T0        ( workspace -- address ) _P256W-T0 + ;
: _P256W.T1        ( workspace -- address ) _P256W-T1 + ;
: _P256W.T2        ( workspace -- address ) _P256W-T2 + ;
: _P256W.T3        ( workspace -- address ) _P256W-T3 + ;
: _P256W.T4        ( workspace -- address ) _P256W-T4 + ;
: _P256W.T5        ( workspace -- address ) _P256W-T5 + ;
: _P256W.T6        ( workspace -- address ) _P256W-T6 + ;
: _P256W.T7        ( workspace -- address ) _P256W-T7 + ;
: _P256W.T8        ( workspace -- address ) _P256W-T8 + ;
: _P256W.T9        ( workspace -- address ) _P256W-T9 + ;
: _P256W.T10       ( workspace -- address ) _P256W-T10 + ;
: _P256W.T11       ( workspace -- address ) _P256W-T11 + ;
: _P256W.T12       ( workspace -- address ) _P256W-T12 + ;
: _P256W.T13       ( workspace -- address ) _P256W-T13 + ;
: _P256W.T14       ( workspace -- address ) _P256W-T14 + ;

: _P256W.AFFINE-X  ( workspace -- address ) _P256W-AFFINE-X + ;
: _P256W.AFFINE-Y  ( workspace -- address ) _P256W-AFFINE-Y + ;
: _P256W.ENCODED   ( workspace -- address ) _P256W-ENCODED + ;
: _P256W.INPUT     ( workspace -- address ) _P256W-INPUT + ;
: _P256W.OUTPUT    ( workspace -- address ) _P256W-OUTPUT + ;
: _P256W.POINT-P   ( workspace -- address ) _P256W-POINT-P + ;
: _P256W.POINT-Q   ( workspace -- address ) _P256W-POINT-Q + ;
: _P256W.POINT-R   ( workspace -- address ) _P256W-POINT-R + ;
: _P256W.MASK      ( workspace -- address ) _P256W-MASK + ;
: _P256W.INPUT2    ( workspace -- address ) _P256W-INPUT2 + ;
: _P256W.INPUT3    ( workspace -- address ) _P256W-INPUT3 + ;
: _P256W.PRIVATE-STAGED
    ( workspace -- address ) _P256W-PRIVATE-STAGED + ;

: _P256.X          ( point -- address ) ;
: _P256.Y          ( point -- address ) 32 + ;
: _P256.Z          ( point -- address ) 64 + ;

: _P256W.PX  ( workspace -- address ) _P256W.POINT-P @ _P256.X ;
: _P256W.PY  ( workspace -- address ) _P256W.POINT-P @ _P256.Y ;
: _P256W.PZ  ( workspace -- address ) _P256W.POINT-P @ _P256.Z ;
: _P256W.QX  ( workspace -- address ) _P256W.POINT-Q @ _P256.X ;
: _P256W.QY  ( workspace -- address ) _P256W.POINT-Q @ _P256.Y ;
: _P256W.QZ  ( workspace -- address ) _P256W.POINT-Q @ _P256.Z ;
: _P256W.RX  ( workspace -- address ) _P256W.POINT-R @ _P256.X ;
: _P256W.RY  ( workspace -- address ) _P256W.POINT-R @ _P256.Y ;
: _P256W.RZ  ( workspace -- address ) _P256W.POINT-R @ _P256.Z ;

\ =====================================================================
\  Geometry, wiping, and fixed-width byte helpers
\ =====================================================================

: _P256-DROP3  ( x1 x2 x3 -- ) 2DROP DROP ;
: _P256-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;

\ Preserve physical-range, protected-memory, and platform failures instead
\ of treating memory that was unsafe to inspect as an invalid curve value.
\ CALLER-SPAN-STATUS contains the pre-admission BIOS exception boundary.
: _P256-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP P256-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP P256-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP P256-S-PROTECTED EXIT
    THEN
    DUP CALLER-SPAN-S-PLATFORM = IF
        DROP P256-S-PLATFORM EXIT
    THEN
    DROP P256-S-PLATFORM ;

\ All five tables are private implementation data.  Even an apparently
\ read-only caller alias is rejected because another operation may publish
\ or wipe through that same caller span.
: _P256-TABLE-OVERLAP?  ( address length -- flag )
    2DUP _P256-GX P256-SCALAR-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _P256-GY P256-SCALAR-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _P256-B P256-SCALAR-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    2DUP _P256-P P256-SCALAR-SIZE MSPAN-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    _P256-N P256-SCALAR-SIZE MSPAN-OVERLAP? ;

\ Report the complete lower-layer storage footprint that a checked caller
\ must not alias.  This is a pure geometry predicate, not an allocator,
\ lifetime tracker, ownership proof, or retained borrow.
: P256-RESERVED-OVERLAP?  ( address length -- flag )
    2DUP FIELD-RESERVED-OVERLAP? IF
        2DROP -1 EXIT
    THEN
    _P256-TABLE-OVERLAP? ;

: _P256-FIXED-SPAN-STATUS  ( address fixed-size -- status )
    2DUP CALLER-SPAN-STATUS _P256-CALLER>STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    P256-RESERVED-OVERLAP? IF
        P256-S-ALIAS
    ELSE
        P256-S-OK
    THEN ;

: _P256-WIPE  ( workspace -- )
    P256-WORKSPACE-SIZE 0 FILL ;

\ Cleanup is mandatory after admission.  These helpers deliberately contain
\ no exception boundary: a wipe fault makes completion ambiguous and must
\ propagate rather than being mislabeled as a returned operation status.
: _P256-CLEANUP-STATUS  ( status workspace wipe-xt -- status )
    EXECUTE ;

: _P256-CLEANUP-RESULT
  ( valid? status workspace wipe-xt -- valid? status )
    EXECUTE ;

: P256-WORKSPACE-CLEAR  ( workspace -- status )
    DUP P256-WORKSPACE-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        NIP EXIT
    THEN
    _P256-WIPE
    P256-S-OK ;

: _P256-REVERSE32  ( source destination -- )
    32 0 DO
        OVER I + C@
        OVER 31 I - + C!
    LOOP
    2DROP ;

\ Return the borrow bit from a-b-borrow.  Byte operands are in 0..255,
\ so b+borrow cannot overflow a cell.
: _P256-BORROW  ( a b borrow -- borrow' )
    + U< 1 AND ;

\ Fixed-width little-endian comparison.  It performs all 32 byte steps.
: _P256-LE-LT?  ( first second -- flag )
    0
    32 0 DO
        2 PICK I + C@
        2 PICK I + C@
        2 PICK _P256-BORROW
        NIP
    LOOP
    0<> NIP NIP ;

: _P256-NONZERO32?  ( address -- flag )
    0
    32 0 DO
        OVER I + C@ OR
    LOOP
    NIP 0<> ;

: _P256-SCALAR-VALID?  ( scalar-le -- flag )
    DUP _P256-NONZERO32?
    SWAP _P256-N _P256-LE-LT?
    AND ;

: _P256-FIELD-ELEMENT?  ( element-le -- flag )
    _P256-P _P256-LE-LT? ;

: _P256-DERIVE-ALIASED?  ( private public workspace -- flag )
    >R
    OVER P256-PRIVATE-SIZE 2 PICK P256-PUBLIC-SIZE
        MSPAN-OVERLAP? IF
        2DROP R> DROP -1 EXIT
    THEN
    OVER P256-PRIVATE-SIZE R@ P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        2DROP R> DROP -1 EXIT
    THEN
    DUP P256-PUBLIC-SIZE R@ P256-WORKSPACE-SIZE
        MSPAN-OVERLAP?
    ROT DROP SWAP DROP
    R> DROP ;

: _P256-DERIVE-GEOMETRY  ( private public workspace -- status )
    DUP P256-WORKSPACE-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP3 R> EXIT
    THEN
    OVER P256-PUBLIC-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP3 R> EXIT
    THEN
    2 PICK P256-PRIVATE-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP3 R> EXIT
    THEN
    2 PICK 2 PICK 2 PICK _P256-DERIVE-ALIASED? IF
        _P256-DROP3 P256-S-ALIAS EXIT
    THEN
    _P256-DROP3 P256-S-OK ;

: _P256-VALIDATE-GEOMETRY  ( public workspace -- status )
    DUP P256-WORKSPACE-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    OVER P256-PUBLIC-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R 2DROP R> EXIT
    THEN
    OVER P256-PUBLIC-SIZE 2 PICK P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF
        2DROP P256-S-ALIAS EXIT
    THEN
    2DROP P256-S-OK ;

: _P256-LINCOMB-ALIASED?
    ( scalar-g scalar-q public-q result workspace -- flag )
    \ Reject every pair.  This keeps the public contract simple and makes
    \ staged publication independent of caller-chosen input aliases.
    4 PICK P256-SCALAR-SIZE 2 PICK P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    3 PICK P256-SCALAR-SIZE 2 PICK P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    2 PICK P256-PUBLIC-SIZE 2 PICK P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    OVER P256-PUBLIC-SIZE 2 PICK P256-WORKSPACE-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN

    4 PICK P256-SCALAR-SIZE 3 PICK P256-PUBLIC-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    3 PICK P256-SCALAR-SIZE 3 PICK P256-PUBLIC-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    2 PICK P256-PUBLIC-SIZE 3 PICK P256-PUBLIC-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN

    4 PICK P256-SCALAR-SIZE 5 PICK P256-SCALAR-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    4 PICK P256-SCALAR-SIZE 4 PICK P256-PUBLIC-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    3 PICK P256-SCALAR-SIZE 4 PICK P256-PUBLIC-SIZE
        MSPAN-OVERLAP? IF _P256-DROP5 -1 EXIT THEN
    _P256-DROP5 0 ;

: _P256-LINCOMB-GEOMETRY
    ( scalar-g scalar-q public-q result workspace -- status )
    DUP P256-WORKSPACE-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP5 R> EXIT
    THEN
    OVER P256-PUBLIC-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP5 R> EXIT
    THEN
    2 PICK P256-PUBLIC-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP5 R> EXIT
    THEN
    3 PICK P256-SCALAR-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP5 R> EXIT
    THEN
    4 PICK P256-SCALAR-SIZE _P256-FIXED-SPAN-STATUS
    ?DUP IF
        >R _P256-DROP5 R> EXIT
    THEN
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK
        _P256-LINCOMB-ALIASED? IF
        _P256-DROP5 P256-S-ALIAS EXIT
    THEN
    _P256-DROP5 P256-S-OK ;

\ Finalize a complete admitted operation.  CATCH exists only to guarantee a
\ workspace-wipe attempt on an exceptional path.  The original THROW is then
\ reissued; it is never normalized because the operation may have reached a
\ publication MOVE.  The wipe itself is outside an exception boundary, so a
\ cleanup fault also propagates.  Geometry rejection happens before these
\ helpers and therefore leaves caller memory untouched.
: _P256-CALL3-STATUS  ( first second workspace xt -- status )
    1 PICK >R
    CATCH
    ?DUP IF
        R@ _P256-WIPE
        >R _P256-DROP3 R>
        R> DROP
        THROW
    THEN
    R@ ['] _P256-WIPE _P256-CLEANUP-STATUS
    R> DROP ;

: _P256-CALL2-RESULT  ( first workspace xt -- valid? status )
    1 PICK >R
    CATCH
    ?DUP IF
        R@ _P256-WIPE
        >R 2DROP R>
        R> DROP
        THROW
    THEN
    R@ ['] _P256-WIPE _P256-CLEANUP-RESULT
    R> DROP ;

: _P256-CALL5-STATUS
  ( first second third fourth workspace xt -- status )
    1 PICK >R
    CATCH
    ?DUP IF
        R@ _P256-WIPE
        >R _P256-DROP5 R>
        R> DROP
        THROW
    THEN
    R@ ['] _P256-WIPE _P256-CLEANUP-STATUS
    R> DROP ;

\ =====================================================================
\  Complete projective addition
\ =====================================================================
\  Homogeneous projective coordinates represent affine (X/Z, Y/Z).
\  The identity is (0:1:0).  The formula below is RCB Algorithm 4 for
\  y^2 = x^3 - 3*x + b and is complete for P-256, including equal,
\  inverse, and identity operands.

: _P256-COMPLETE-ADD  ( first second result workspace -- )
    \ Keep all operand pointers in caller-owned metadata so nested field
    \ calls and point formulae never depend on module variables.
    3 PICK OVER _P256W.POINT-P !
    2 PICK OVER _P256W.POINT-Q !
    OVER OVER _P256W.POINT-R !
    NIP NIP NIP

    \ x1x2, y1y2, z1z2
    DUP _P256W.PX OVER _P256W.QX 2 PICK _P256W.T0 FIELD-MUL
    DUP _P256W.PY OVER _P256W.QY 2 PICK _P256W.T1 FIELD-MUL
    DUP _P256W.PZ OVER _P256W.QZ 2 PICK _P256W.T2 FIELD-MUL

    \ C = X1*Y2 + X2*Y1
    DUP _P256W.PX OVER _P256W.PY 2 PICK _P256W.T3 FIELD-ADD
    DUP _P256W.QX OVER _P256W.QY 2 PICK _P256W.T4 FIELD-ADD
    DUP _P256W.T3 OVER _P256W.T4 2 PICK _P256W.T3 FIELD-MUL
    DUP _P256W.T3 OVER _P256W.T0 2 PICK _P256W.T3 FIELD-SUB
    DUP _P256W.T3 OVER _P256W.T1 2 PICK _P256W.T3 FIELD-SUB

    \ D = Y1*Z2 + Y2*Z1
    DUP _P256W.PY OVER _P256W.PZ 2 PICK _P256W.T4 FIELD-ADD
    DUP _P256W.QY OVER _P256W.QZ 2 PICK _P256W.T5 FIELD-ADD
    DUP _P256W.T4 OVER _P256W.T5 2 PICK _P256W.T4 FIELD-MUL
    DUP _P256W.T4 OVER _P256W.T1 2 PICK _P256W.T4 FIELD-SUB
    DUP _P256W.T4 OVER _P256W.T2 2 PICK _P256W.T4 FIELD-SUB

    \ E = X1*Z2 + X2*Z1
    DUP _P256W.PX OVER _P256W.PZ 2 PICK _P256W.T5 FIELD-ADD
    DUP _P256W.QX OVER _P256W.QZ 2 PICK _P256W.T6 FIELD-ADD
    DUP _P256W.T5 OVER _P256W.T6 2 PICK _P256W.T5 FIELD-MUL
    DUP _P256W.T5 OVER _P256W.T0 2 PICK _P256W.T5 FIELD-SUB
    DUP _P256W.T5 OVER _P256W.T2 2 PICK _P256W.T5 FIELD-SUB

    \ F = 3*(E - b*z1z2)
    _P256-B OVER _P256W.T2 2 PICK _P256W.T6 FIELD-MUL
    DUP _P256W.T5 OVER _P256W.T6 2 PICK _P256W.T6 FIELD-SUB
    DUP _P256W.T6 OVER _P256W.T6 2 PICK _P256W.T7 FIELD-ADD
    DUP _P256W.T7 OVER _P256W.T6 2 PICK _P256W.T6 FIELD-ADD

    \ G = y1y2-F; H = y1y2+F; I = 3*z1z2
    DUP _P256W.T1 OVER _P256W.T6 2 PICK _P256W.T7 FIELD-SUB
    DUP _P256W.T1 OVER _P256W.T6 2 PICK _P256W.T8 FIELD-ADD
    DUP _P256W.T2 OVER _P256W.T2 2 PICK _P256W.T9 FIELD-ADD
    DUP _P256W.T9 OVER _P256W.T2 2 PICK _P256W.T9 FIELD-ADD

    \ J = 3*(b*E - x1x2 - I)
    _P256-B OVER _P256W.T5 2 PICK _P256W.T10 FIELD-MUL
    DUP _P256W.T10 OVER _P256W.T0 2 PICK _P256W.T10 FIELD-SUB
    DUP _P256W.T10 OVER _P256W.T9 2 PICK _P256W.T10 FIELD-SUB
    DUP _P256W.T10 OVER _P256W.T10 2 PICK _P256W.T11 FIELD-ADD
    DUP _P256W.T11 OVER _P256W.T10 2 PICK _P256W.T10 FIELD-ADD

    \ K = 3*x1x2-I; L=D*J; M=K*J; N=K*C
    DUP _P256W.T0 OVER _P256W.T0 2 PICK _P256W.T11 FIELD-ADD
    DUP _P256W.T11 OVER _P256W.T0 2 PICK _P256W.T11 FIELD-ADD
    DUP _P256W.T11 OVER _P256W.T9 2 PICK _P256W.T11 FIELD-SUB
    DUP _P256W.T4 OVER _P256W.T10 2 PICK _P256W.T12 FIELD-MUL
    DUP _P256W.T11 OVER _P256W.T10 2 PICK _P256W.T13 FIELD-MUL
    DUP _P256W.T11 OVER _P256W.T3 2 PICK _P256W.T14 FIELD-MUL

    \ Y3 = H*G+M; X3 = H*C-L; Z3 = G*D+N
    DUP _P256W.T8 OVER _P256W.T7 2 PICK _P256W.RY FIELD-MUL
    DUP _P256W.RY OVER _P256W.T13 2 PICK _P256W.RY FIELD-ADD
    DUP _P256W.T8 OVER _P256W.T3 2 PICK _P256W.RX FIELD-MUL
    DUP _P256W.RX OVER _P256W.T12 2 PICK _P256W.RX FIELD-SUB
    DUP _P256W.T7 OVER _P256W.T4 2 PICK _P256W.RZ FIELD-MUL
    DUP _P256W.RZ OVER _P256W.T14 2 PICK _P256W.RZ FIELD-ADD
    DROP ;

\ =====================================================================
\  Fixed-round secret scalar multiplication
\ =====================================================================

: _P256-POINT-IDENTITY  ( point -- )
    DUP _P256.X FIELD-ZERO
    DUP _P256.Y FIELD-ONE
    _P256.Z FIELD-ZERO ;

: _P256-POINT-GENERATOR  ( point -- )
    DUP _P256-GX SWAP _P256.X 32 MOVE
    DUP _P256-GY SWAP _P256.Y 32 MOVE
    _P256.Z FIELD-ONE ;

: _P256-SCALAR-BIT  ( round workspace -- bit )
    SWAP
    DUP 3 RSHIFT 31 SWAP -
    2 PICK _P256W.SCALAR SWAP + C@
    SWAP 7 AND 7 SWAP - RSHIFT
    1 AND NIP ;

\ PUBLIC-SCALAR-LINCOMB temporarily stages its second public scalar in the
\ encoding area.  The area is overwritten only after the point result is
\ complete and no scalar bit remains to be consumed.
: _P256-SCALAR2-BIT  ( round workspace -- bit )
    SWAP
    DUP 3 RSHIFT 31 SWAP -
    2 PICK _P256W.ENCODED SWAP + C@
    SWAP 7 AND 7 SWAP - RSHIFT
    1 AND NIP ;

\ Select second when MASK is all ones, first when it is zero.
: _P256-SELECT-POINT  ( workspace -- )
    96 0 DO
        DUP _P256W.DOUBLE I + C@
        DUP
        2 PICK _P256W.ADD I + C@
        XOR
        2 PICK _P256W.MASK @ AND
        XOR
        OVER _P256W.R I + C!
    LOOP
    DROP ;

: _P256-SCALAR-ROUND  ( round workspace -- )
    2DUP _P256-SCALAR-BIT NEGATE
    OVER _P256W.MASK !

    \ D = R+R, A = D+G.  The same complete formula handles both.
    DUP _P256W.R
    OVER _P256W.R
    2 PICK _P256W.DOUBLE
    3 PICK _P256-COMPLETE-ADD

    DUP _P256W.DOUBLE
    OVER _P256W.BASE
    2 PICK _P256W.ADD
    3 PICK _P256-COMPLETE-ADD

    DUP _P256-SELECT-POINT
    2DROP ;

: _P256-SCALAR-MUL-G  ( workspace -- )
    DUP _P256W.BASE _P256-POINT-GENERATOR
    DUP _P256W.R _P256-POINT-IDENTITY
    256 0 DO
        I OVER _P256-SCALAR-ROUND
    LOOP
    DROP ;

\ Load the validated affine Q staged by public-point decoding.
: _P256-POINT-STAGED-Q  ( workspace -- )
    DUP _P256W.AFFINE-X
    OVER _P256W.BASE _P256.X
    32 MOVE
    DUP _P256W.AFFINE-Y
    OVER _P256W.BASE _P256.Y
    32 MOVE
    _P256W.BASE _P256.Z FIELD-ONE ;

\ One fixed public-scalar linear-combination round:
\   R = 2R; masked R += bit-g*G; masked R += bit-q*Q.
\ DOUBLE snapshots the first choice before each bytewise selection.
: _P256-PUBLIC-SCALAR-LINCOMB-ROUND  ( round workspace -- )
    2DUP _P256-SCALAR-BIT NEGATE
    OVER _P256W.MASK !

    DUP _P256W.R
    OVER _P256W.R
    2 PICK _P256W.DOUBLE
    3 PICK _P256-COMPLETE-ADD

    DUP _P256W.DOUBLE
    OVER _P256W.BASE
    2 PICK _P256W.ADD
    3 PICK _P256-COMPLETE-ADD
    DUP _P256-SELECT-POINT

    \ Preserve the selected 2R or 2R+G as the first Q-selection operand.
    DUP _P256W.R
    OVER _P256W.DOUBLE
    96 MOVE
    DUP _P256-POINT-STAGED-Q

    2DUP _P256-SCALAR2-BIT NEGATE
    OVER _P256W.MASK !
    DUP _P256W.DOUBLE
    OVER _P256W.BASE
    2 PICK _P256W.ADD
    3 PICK _P256-COMPLETE-ADD
    DUP _P256-SELECT-POINT

    \ The next round's first addition always uses G.
    DUP _P256W.BASE _P256-POINT-GENERATOR
    2DROP ;

: _P256-PUBLIC-SCALAR-LINCOMB-MUL  ( workspace -- )
    DUP _P256W.BASE _P256-POINT-GENERATOR
    DUP _P256W.R _P256-POINT-IDENTITY
    256 0 DO
        I OVER _P256-PUBLIC-SCALAR-LINCOMB-ROUND
    LOOP
    DROP ;

\ =====================================================================
\  Encoding and public-point validation
\ =====================================================================

: _P256-R-TO-AFFINE  ( workspace -- )
    \ Homogeneous coordinates require one inverse: x=X/Z, y=Y/Z.
    DUP _P256W.R _P256.Z
    OVER _P256W.T0 FIELD-INV
    DUP _P256W.R _P256.X
    OVER _P256W.T0
    2 PICK _P256W.AFFINE-X FIELD-MUL
    DUP _P256W.R _P256.Y
    OVER _P256W.T0
    2 PICK _P256W.AFFINE-Y FIELD-MUL
    DROP ;

: _P256-ENCODE-STAGED  ( workspace -- )
    0x04 OVER _P256W.ENCODED C!
    DUP _P256W.AFFINE-X
    OVER _P256W.ENCODED 1+
    _P256-REVERSE32
    DUP _P256W.AFFINE-Y
    OVER _P256W.ENCODED 33 +
    _P256-REVERSE32
    DROP ;

: _P256-DECODE-STAGED  ( workspace -- )
    DUP _P256W.INPUT @ 1+
    OVER _P256W.AFFINE-X
    _P256-REVERSE32
    DUP _P256W.INPUT @ 33 +
    OVER _P256W.AFFINE-Y
    _P256-REVERSE32
    DROP ;

: _P256-AFFINE-ON-CURVE?  ( workspace -- flag )
    \ T0=x^2; T1=x^3; T2=3*x, then compare y^2 with x^3-3*x+b.
    DUP _P256W.AFFINE-X
    OVER _P256W.AFFINE-X
    2 PICK _P256W.T0 FIELD-MUL
    DUP _P256W.T0
    OVER _P256W.AFFINE-X
    2 PICK _P256W.T1 FIELD-MUL
    DUP _P256W.AFFINE-X
    OVER _P256W.AFFINE-X
    2 PICK _P256W.T2 FIELD-ADD
    DUP _P256W.T2
    OVER _P256W.AFFINE-X
    2 PICK _P256W.T2 FIELD-ADD
    DUP _P256W.T1
    OVER _P256W.T2
    2 PICK _P256W.T1 FIELD-SUB
    DUP _P256W.T1
    _P256-B
    2 PICK _P256W.T1 FIELD-ADD
    DUP _P256W.AFFINE-Y
    OVER _P256W.AFFINE-Y
    2 PICK _P256W.T2 FIELD-MUL
    DUP _P256W.T2
    SWAP _P256W.T1
    FIELD-EQ? ;

\ =====================================================================
\  Guarded operation bodies
\ =====================================================================

: _P256-KEYGEN-CANDIDATE  ( workspace -- status )
    \ Rejection sampling preserves the uniform distribution on [1,n).
    \ ENTROPY-FILL is the sole writer of every fresh BE candidate.
    _P256-KEYGEN-ATTEMPTS 0 DO
        DUP _P256W.PRIVATE-STAGED
        P256-PRIVATE-SIZE ENTROPY-FILL
        DUP ENTROPY-S-UNAVAILABLE = IF
            DROP DROP P256-S-ENTROPY UNLOOP EXIT
        THEN
        ENTROPY-S-OK <> IF
            DROP P256-S-INTERNAL UNLOOP EXIT
        THEN

        DUP _P256W.PRIVATE-STAGED
        OVER _P256W.SCALAR
        _P256-REVERSE32
        DUP _P256W.SCALAR _P256-SCALAR-VALID? IF
            DROP P256-S-OK UNLOOP EXIT
        THEN
    LOOP
    DROP P256-S-INTERNAL ;

: _P256-KEYGEN-LOCKED  ( workspace -- status )
    DUP _P256-KEYGEN-CANDIDATE
    DUP IF NIP EXIT THEN
    DROP

    FIELD-USE-P256
    DUP _P256-SCALAR-MUL-G
    DUP _P256-R-TO-AFFINE
    DUP _P256-ENCODE-STAGED

    \ Copy both staged outputs only in this final publication phase.  The two
    \ caller buffers are separate commits, not a crash-atomic grouped write.
    DUP _P256W.PRIVATE-STAGED
    OVER _P256W.INPUT @
    P256-PRIVATE-SIZE MOVE
    DUP _P256W.ENCODED
    OVER _P256W.OUTPUT @
    P256-PUBLIC-SIZE MOVE
    DROP P256-S-OK ;

: _P256-DERIVE-LOCKED  ( workspace -- status )
    FIELD-USE-P256
    DUP _P256W.INPUT @
    OVER _P256W.SCALAR
    _P256-REVERSE32
    DUP _P256W.SCALAR _P256-SCALAR-VALID? 0= IF
        DROP P256-S-PRIVATE EXIT
    THEN
    DUP _P256-SCALAR-MUL-G
    DUP _P256-R-TO-AFFINE
    DUP _P256-ENCODE-STAGED
    DUP _P256W.ENCODED
    OVER _P256W.OUTPUT @
    P256-PUBLIC-SIZE MOVE
    DROP P256-S-OK ;

: _P256-VALIDATE-LOCKED  ( workspace -- valid? status )
    DUP _P256W.INPUT @ C@ 0x04 <> IF
        DROP 0 P256-S-OK EXIT
    THEN
    DUP _P256-DECODE-STAGED
    DUP _P256W.AFFINE-X _P256-FIELD-ELEMENT? 0= IF
        DROP 0 P256-S-OK EXIT
    THEN
    DUP _P256W.AFFINE-Y _P256-FIELD-ELEMENT? 0= IF
        DROP 0 P256-S-OK EXIT
    THEN
    FIELD-USE-P256
    _P256-AFFINE-ON-CURVE?
    P256-S-OK ;

: _P256-PUBLIC-SCALAR-LINCOMB-LOCKED  ( workspace -- status )
    FIELD-USE-P256

    DUP _P256W.INPUT @
    OVER _P256W.SCALAR
    _P256-REVERSE32
    DUP _P256W.INPUT2 @
    OVER _P256W.ENCODED
    _P256-REVERSE32

    \ Public linear-combination scalars admit zero but not n or larger.
    DUP _P256W.SCALAR _P256-N _P256-LE-LT? 0= IF
        DROP P256-S-SCALAR EXIT
    THEN
    DUP _P256W.ENCODED _P256-N _P256-LE-LT? 0= IF
        DROP P256-S-SCALAR EXIT
    THEN

    \ Reuse the canonical public-point decoder with Q as its staged input.
    DUP _P256W.INPUT3 @
    OVER _P256W.INPUT !
    DUP _P256-VALIDATE-LOCKED
    DROP 0= IF
        DROP P256-S-PUBLIC EXIT
    THEN

    DUP _P256-PUBLIC-SCALAR-LINCOMB-MUL
    DUP _P256W.R _P256.Z FIELD-ZERO? IF
        DROP P256-S-IDENTITY EXIT
    THEN
    DUP _P256-R-TO-AFFINE
    DUP _P256-ENCODE-STAGED
    DUP _P256W.ENCODED
    OVER _P256W.OUTPUT @
    P256-PUBLIC-SIZE MOVE
    DROP P256-S-OK ;

\ The transaction spans the complete multi-operation computation.  FIELD-*
\ calls recurse through the same public boundary.
: _P256-KEYGEN-TRANSACTION  ( workspace -- status )
    ['] _P256-KEYGEN-LOCKED FIELD-WITH-TRANSACTION ;

: _P256-DERIVE-TRANSACTION  ( workspace -- status )
    ['] _P256-DERIVE-LOCKED FIELD-WITH-TRANSACTION ;

: _P256-VALIDATE-TRANSACTION  ( workspace -- valid? status )
    ['] _P256-VALIDATE-LOCKED FIELD-WITH-TRANSACTION ;

: _P256-PUBLIC-SCALAR-LINCOMB-TRANSACTION  ( workspace -- status )
    ['] _P256-PUBLIC-SCALAR-LINCOMB-LOCKED
    FIELD-WITH-TRANSACTION ;

\ =====================================================================
\  Public operations
\ =====================================================================

: _P256-KEYGEN-ADMITTED
  ( private-output public-output workspace -- status )
    DUP _P256-WIPE
    2 PICK OVER _P256W.INPUT !
    OVER OVER _P256W.OUTPUT !
    NIP NIP
    _P256-KEYGEN-TRANSACTION ;

: _P256-DERIVE-ADMITTED
  ( private public workspace -- status )
    DUP _P256-WIPE
    2 PICK OVER _P256W.INPUT !
    OVER OVER _P256W.OUTPUT !
    NIP NIP
    _P256-DERIVE-TRANSACTION ;

: _P256-VALIDATE-ADMITTED  ( public workspace -- valid? status )
    DUP _P256-WIPE
    OVER OVER _P256W.INPUT !
    NIP
    _P256-VALIDATE-TRANSACTION ;

: _P256-LINCOMB-ADMITTED
  ( scalar-g scalar-q public-q result workspace -- status )
    DUP _P256-WIPE
    4 PICK OVER _P256W.INPUT !
    3 PICK OVER _P256W.INPUT2 !
    2 PICK OVER _P256W.INPUT3 !
    OVER OVER _P256W.OUTPUT !
    NIP NIP NIP NIP
    _P256-PUBLIC-SCALAR-LINCOMB-TRANSACTION ;

: P256-KEYGEN  ( private-output public-output workspace -- status )
    2 PICK 2 PICK 2 PICK _P256-DERIVE-GEOMETRY
    DUP IF
        >R _P256-DROP3 R> EXIT
    THEN
    DROP
    ['] _P256-KEYGEN-ADMITTED _P256-CALL3-STATUS ;

: P256-PUBLIC-FROM-PRIVATE  ( private public workspace -- status )
    2 PICK 2 PICK 2 PICK _P256-DERIVE-GEOMETRY
    DUP IF
        >R _P256-DROP3 R> EXIT
    THEN
    DROP
    ['] _P256-DERIVE-ADMITTED _P256-CALL3-STATUS ;

: P256-PUBLIC-VALID?  ( public workspace -- valid? status )
    2DUP _P256-VALIDATE-GEOMETRY
    DUP IF
        >R 2DROP 0 R> EXIT
    THEN
    DROP
    ['] _P256-VALIDATE-ADMITTED _P256-CALL2-RESULT ;

: P256-PUBLIC-SCALAR-LINCOMB
    ( scalar-g scalar-q public-q result workspace -- status )
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK _P256-LINCOMB-GEOMETRY
    DUP IF
        >R _P256-DROP5 R> EXIT
    THEN
    DROP
    ['] _P256-LINCOMB-ADMITTED _P256-CALL5-STATUS ;
