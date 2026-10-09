\ =====================================================================
\  profile.f - Sealed sandbox execution profile
\ =====================================================================
\  A profile is the runtime table that one canonical descriptor decodes
\  to (docs/sandbox/profile-format.md).  It holds what a module means: the
\  profile digest and identifier, the semantics it names, the enabled
\  opcodes and the enabled entry signatures.  It holds no resource limit:
\  how much one compilation, verification or run may use is the host's
\  dynamic policy, so the same profile serves every host and device.  It
\  holds no handler, host pointer, Context or authority either.
\
\  Only the descriptor loader in profile-codec.f builds a profile.  The
\  loader writes the seal last, so a failed load publishes nothing usable.
\  A byte copy is invalid, because its stored self address no longer names
\  the copy.
\
\  Callers supply one writable, cell-aligned SBOX-PROFILE-SIZE-byte object
\  and keep it mapped and quiescent during each synchronous call.  Every
\  public operation qualifies that span before reading it, and every query
\  returns an explicit status.
\ =====================================================================

PROVIDED akashic-sbx-profile

REQUIRE abi.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Status and semantics
\ =====================================================================

0 CONSTANT SBOX-PROFILE-S-OK
1 CONSTANT SBOX-PROFILE-S-INVALID
2 CONSTANT SBOX-PROFILE-S-OPCODE
3 CONSTANT SBOX-PROFILE-S-ALIAS
4 CONSTANT SBOX-PROFILE-S-DESCRIPTOR
5 CONSTANT SBOX-PROFILE-S-UNSUPPORTED
6 CONSTANT SBOX-PROFILE-S-FAULT
7 CONSTANT SBOX-PROFILE-S-RANGE
8 CONSTANT SBOX-PROFILE-S-PROTECTED
9 CONSTANT SBOX-PROFILE-S-PLATFORM

: SBOX-PROFILE-STATUS-VALID?  ( status -- flag )
    DUP SBOX-PROFILE-S-OK >=
    SWAP SBOX-PROFILE-S-PLATFORM <= AND ;

\ The semantic contracts this runtime implements.  Scalar qualification is
\ pure computation plus signature-zero entries, which take and return their
\ function's own I64 cells.  It exists only to qualify the executor, and no
\ product host accepts it.
1 CONSTANT SBOX-PROFILE-SEMANTICS-PURE
2 CONSTANT SBOX-PROFILE-SEMANTICS-SCALAR-QUALIFICATION

: _SBP-SEMANTICS?  ( semantics -- flag )
    DUP SBOX-PROFILE-SEMANTICS-PURE =
    SWAP SBOX-PROFILE-SEMANTICS-SCALAR-QUALIFICATION = OR ;

\ =====================================================================
\  Fixed object layout
\ =====================================================================

0x53425850524F464C CONSTANT _SBOX-PROFILE-MAGIC  \ "SBXPROFL"

127 CONSTANT SBOX-PROFILE-IDENTIFIER-MAX
32  CONSTANT SBOX-PROFILE-DIGEST-SIZE

  0 CONSTANT _SBP-MAGIC
  8 CONSTANT _SBP-SELF
 16 CONSTANT _SBP-SEMANTICS
 24 CONSTANT _SBP-SIGNATURES
 32 CONSTANT _SBP-DIGEST
 64 CONSTANT _SBP-ID-U
 72 CONSTANT _SBP-ID
200 CONSTANT _SBP-OPCODES
232 CONSTANT SBOX-PROFILE-SIZE

\ Signature IDs index one cell of enable bits.
64 CONSTANT SBOX-PROFILE-SIGNATURE-CAPACITY

: _SBP.MAGIC       ( profile -- address ) _SBP-MAGIC + ;
: _SBP.SELF        ( profile -- address ) _SBP-SELF + ;
: _SBP.SEMANTICS   ( profile -- address ) _SBP-SEMANTICS + ;
: _SBP.SIGNATURES  ( profile -- address ) _SBP-SIGNATURES + ;
: _SBP.DIGEST      ( profile -- address ) _SBP-DIGEST + ;
: _SBP.ID-U        ( profile -- address ) _SBP-ID-U + ;
: _SBP.ID          ( profile -- address ) _SBP-ID + ;
: _SBP.OPCODES     ( profile -- address ) _SBP-OPCODES + ;

: _SBP-OPCODE-CELL  ( opcode profile -- cell-address mask )
    _SBP.OPCODES OVER 6 RSHIFT 8 * +
    SWAP 63 AND 1 SWAP LSHIFT ;

: _SBOX-PROFILE-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF
        DROP SBOX-PROFILE-S-OK EXIT
    THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP SBOX-PROFILE-S-RANGE EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP SBOX-PROFILE-S-PROTECTED EXIT
    THEN
    DROP SBOX-PROFILE-S-PLATFORM ;

: _SBOX-PROFILE-SPAN-STATUS  ( profile -- status )
    DUP 0= IF DROP SBOX-PROFILE-S-INVALID EXIT THEN
    DUP 7 AND IF DROP SBOX-PROFILE-S-INVALID EXIT THEN
    DUP SBOX-PROFILE-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP SBOX-PROFILE-S-INVALID EXIT
    THEN
    SBOX-PROFILE-SIZE CALLER-SPAN-STATUS
    _SBOX-PROFILE-CALLER>STATUS ;

\ The loader's last write.  Everything else is already in place.
: _SBP-SEAL  ( profile -- )
    DUP DUP _SBP.SELF !
    _SBOX-PROFILE-MAGIC SWAP _SBP.MAGIC ! ;

\ =====================================================================
\  Validation and queries
\ =====================================================================

: _SBOX-PROFILE-STATUS  ( profile -- status )
    DUP _SBOX-PROFILE-SPAN-STATUS ?DUP IF NIP EXIT THEN
    DUP _SBP.MAGIC @ _SBOX-PROFILE-MAGIC <> IF
        DROP SBOX-PROFILE-S-INVALID EXIT
    THEN
    DUP _SBP.SELF @ OVER <> IF DROP SBOX-PROFILE-S-INVALID EXIT THEN
    DUP _SBP.SEMANTICS @ _SBP-SEMANTICS? 0= IF
        DROP SBOX-PROFILE-S-INVALID EXIT
    THEN
    _SBP.ID-U @ DUP 0> SWAP SBOX-PROFILE-IDENTIFIER-MAX <= AND
    IF SBOX-PROFILE-S-OK ELSE SBOX-PROFILE-S-INVALID THEN ;

: SBOX-PROFILE-VALID?  ( profile -- flag )
    _SBOX-PROFILE-STATUS SBOX-PROFILE-S-OK = ;

: SBOX-PROFILE-SEMANTICS@  ( profile -- semantics status )
    DUP _SBOX-PROFILE-STATUS ?DUP IF NIP 0 SWAP EXIT THEN
    _SBP.SEMANTICS @ SBOX-PROFILE-S-OK ;

: SBOX-PROFILE-OPCODE-ENABLED?  ( opcode profile -- flag status )
    DUP _SBOX-PROFILE-STATUS ?DUP IF >R 2DROP 0 R> EXIT THEN
    OVER SBOX-ABI-OPCODE-STATUS SBOX-MACHINE-S-OK <> IF
        2DROP 0 SBOX-PROFILE-S-OPCODE EXIT
    THEN
    _SBP-OPCODE-CELL SWAP @ AND 0<> SBOX-PROFILE-S-OK ;

: SBOX-PROFILE-SIGNATURE-ENABLED?  ( signature profile -- flag status )
    DUP _SBOX-PROFILE-STATUS ?DUP IF >R 2DROP 0 R> EXIT THEN
    OVER 0 SBOX-PROFILE-SIGNATURE-CAPACITY WITHIN 0= IF
        2DROP 0 SBOX-PROFILE-S-OK EXIT
    THEN
    _SBP.SIGNATURES @ SWAP RSHIFT 1 AND 0<> SBOX-PROFILE-S-OK ;

\ The 32 sealed digest bytes.  Callers read them and never write them.
: SBOX-PROFILE-DIGEST@  ( profile -- digest|0 )
    DUP SBOX-PROFILE-VALID? IF _SBP.DIGEST ELSE DROP 0 THEN ;

: SBOX-PROFILE-DIGEST=  ( digest profile -- flag )
    SBOX-PROFILE-DIGEST@ ?DUP 0= IF DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    SBOX-PROFILE-DIGEST-SIZE TUCK COMPARE 0= ;

: SBOX-PROFILE-IDENTIFIER$  ( profile -- address length | 0 0 )
    DUP SBOX-PROFILE-VALID? IF
        DUP _SBP.ID SWAP _SBP.ID-U @
    ELSE
        DROP 0 0
    THEN ;
