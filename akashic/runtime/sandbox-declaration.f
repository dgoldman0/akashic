\ =====================================================================
\  sandbox-declaration.f - Canonical sandbox module declarations
\ =====================================================================
\  A declaration (docs/sandbox/declaration-format.md) binds one module
\  revision to its artifact and profile digests, its entries with their
\  input and output schemas, the limits it asks for, and where it came
\  from.  It is metadata, not authority: it runs nothing, grants nothing,
\  and can only narrow a limit.  Its identity is the SHA3-256 digest of
\  its bytes in the declaration domain, which is kept outside it.
\
\  Schemas are canonical schema bytes (docs/interop/schema-bytes.md).
\  This layer treats them as opaque spans bound by their digests; the
\  interop layer checks their structure before it installs or invokes.
\
\  Every word works on caller memory and keeps no module state.  The
\  readers take a declaration SBOX-DECL-VALIDATE has accepted.
\ =====================================================================

PROVIDED akashic-sbx-declaration

REQUIRE identity.f
REQUIRE sandbox-limits.f
REQUIRE ../sandbox/abi.f
REQUIRE ../sandbox/artifact.f
REQUIRE ../sandbox/digest.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

0 CONSTANT SBOX-DECL-S-OK
1 CONSTANT SBOX-DECL-S-INVALID
2 CONSTANT SBOX-DECL-S-CAPACITY
3 CONSTANT SBOX-DECL-S-ALIAS
4 CONSTANT SBOX-DECL-S-STATE
5 CONSTANT SBOX-DECL-S-DIGEST
6 CONSTANT SBOX-DECL-S-FAULT

\ =====================================================================
\  Geometry
\ =====================================================================

  1 CONSTANT SBOX-DECL-FORMAT
184 CONSTANT SBOX-DECL-HEADER-SIZE
 16 CONSTANT SBOX-DECL-LIMIT-SIZE
168 CONSTANT SBOX-DECL-ENTRY-SIZE
\ The same ceiling as an artifact's.
16777216 CONSTANT SBOX-DECL-BYTES-MAX
4294967295 CONSTANT _SDC-U32-MAX

0 CONSTANT SBOX-DECL-PROVENANCE-NONE
1 CONSTANT SBOX-DECL-PROVENANCE-PACKAGE

\ Header:
\   +0   "AKSBXDCL"          +8   u16 format 1       +10 u16 header 184
\   +12  u32 flags 0         +16  u64 total bytes
\   +24  u32 entry count     +28  u16 limit count    +30 u16 provenance
\   +32  u64 schema bytes    +40  u64 module revision
\   +48  module RID          +80  artifact digest    +112 profile digest
\   +144 provenance RID      +176 u64 provenance revision
  8 CONSTANT _SDC-H-FORMAT
 10 CONSTANT _SDC-H-EXTENT
 12 CONSTANT _SDC-H-FLAGS
 16 CONSTANT _SDC-H-TOTAL
 24 CONSTANT _SDC-H-ENTRY-N
 28 CONSTANT _SDC-H-LIMIT-N
 30 CONSTANT _SDC-H-PROVENANCE
 32 CONSTANT _SDC-H-SCHEMA-U
 40 CONSTANT _SDC-H-REVISION
 48 CONSTANT _SDC-H-MODULE
 80 CONSTANT _SDC-H-ARTIFACT
112 CONSTANT _SDC-H-PROFILE
144 CONSTANT _SDC-H-PROV-RID
176 CONSTANT _SDC-H-PROV-REVISION

\ Limit record: [u16 field, 6 zero bytes, u64 value]
\ Entry record:
\   +0   u16 name length   +2 u16 0   +4 u32 signature   +8 64-byte name
\   +72  input schema slot           +120 output schema slot
\ Schema slot: [u64 offset, u64 length, 32-byte digest]
  0 CONSTANT _SDC-E-NAME-U
  2 CONSTANT _SDC-E-RESERVED
  4 CONSTANT _SDC-E-SIGNATURE
  8 CONSTANT _SDC-E-NAME
 64 CONSTANT _SDC-E-NAME-AREA
 72 CONSTANT _SDC-E-INPUT
120 CONSTANT _SDC-E-OUTPUT
  0 CONSTANT _SDC-S-OFFSET
  8 CONSTANT _SDC-S-LENGTH
 16 CONSTANT _SDC-S-DIGEST

\ The caller's workspace: the declaration in hand, the schema cursor, the
\ digest just computed, and the digest work area.
 0 CONSTANT _SDW-DECL
 8 CONSTANT _SDW-CURSOR
16 CONSTANT _SDW-DIGEST
48 CONSTANT _SDW-WORK
_SDW-WORK SBOX-DIGEST-WORKSPACE-SIZE + CONSTANT SBOX-DECL-WORKSPACE-SIZE

: _SDW.DECL    ( w -- a ) _SDW-DECL + ;
: _SDW.CURSOR  ( w -- a ) _SDW-CURSOR + ;
: _SDW.DIGEST  ( w -- a ) _SDW-DIGEST + ;
: _SDW.WORK    ( w -- a ) _SDW-WORK + ;

: _SDC-SPAN?  ( address length -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _SDW-ADMIT?  ( workspace -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    SBOX-DECL-WORKSPACE-SIZE _SDC-SPAN? ;

: _SDC-ZERO?  ( address length -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

\ A present digest or RID: readable and not all zero.
: _SDC-PRESENT?  ( address length -- flag )
    2DUP _SDC-SPAN? 0= IF 2DROP 0 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    _SDC-ZERO? 0= ;

: _SDC-MAGIC  ( -- address length ) S" AKSBXDCL" ;

: _SDC-ENTRY-N@  ( declaration -- n ) _SDC-H-ENTRY-N + SBOX-BYTE-U32-LE@ ;
: _SDC-LIMIT-N@  ( declaration -- n ) _SDC-H-LIMIT-N + SBOX-BYTE-U16-LE@ ;
: _SDC-SCHEMA-U@  ( declaration -- n ) _SDC-H-SCHEMA-U + SBOX-BYTE-U64-LE@ ;

: _SDC-DECL-SPAN  ( declaration -- declaration declaration-u )
    DUP _SDC-H-TOTAL + SBOX-BYTE-U64-LE@ ;

: _SDC-LIMITS  ( declaration -- address ) SBOX-DECL-HEADER-SIZE + ;

: _SDC-ENTRIES  ( declaration -- address )
    DUP _SDC-LIMITS SWAP _SDC-LIMIT-N@ SBOX-DECL-LIMIT-SIZE * + ;

: _SDC-SCHEMAS  ( declaration -- address )
    DUP _SDC-ENTRIES SWAP _SDC-ENTRY-N@ SBOX-DECL-ENTRY-SIZE * + ;

: _SDC-ENTRY  ( index declaration -- record )
    _SDC-ENTRIES SWAP SBOX-DECL-ENTRY-SIZE * + ;

: _SDC-LIMIT  ( index declaration -- record )
    _SDC-LIMITS SWAP SBOX-DECL-LIMIT-SIZE * + ;

: _SDC-DIGEST-STATUS  ( digest-status -- status )
    CASE
        SBOX-DIGEST-S-OK OF SBOX-DECL-S-OK ENDOF
        SBOX-DIGEST-S-INVALID OF SBOX-DECL-S-INVALID ENDOF
        SBOX-DIGEST-S-CAPACITY OF SBOX-DECL-S-CAPACITY ENDOF
        SBOX-DIGEST-S-ALIAS OF SBOX-DECL-S-ALIAS ENDOF
        SBOX-DECL-S-FAULT SWAP
    ENDCASE ;

: _SDC-DROP3>STATUS  ( x1 x2 x3 status -- status ) >R 2DROP DROP R> ;
: _SDC-DROP5  ( x1 x2 x3 x4 x5 -- ) 2DROP 2DROP DROP ;
: _SDC-DROP9  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 -- ) 2DROP 2DROP 2DROP 2DROP DROP ;

\ =====================================================================
\  Measuring
\ =====================================================================

: _SDC-COUNTS-STATUS  ( entry-n limit-n schema-u -- status )
    DUP 0< IF DROP 2DROP SBOX-DECL-S-INVALID EXIT THEN
    SBOX-DECL-BYTES-MAX > IF 2DROP SBOX-DECL-S-CAPACITY EXIT THEN
    DUP 0< SWAP SBOX-LIMIT-COUNT > OR IF DROP SBOX-DECL-S-INVALID EXIT THEN
    DUP 1 < SWAP SBOX-ARTIFACT-ENTRY-MAX > OR IF
        SBOX-DECL-S-INVALID
    ELSE
        SBOX-DECL-S-OK
    THEN ;

\ The bytes a declaration with these counts occupies.  Each count is held
\ to its ceiling first, so the sum cannot overflow.
: SBOX-DECL-MEASURE  ( entry-n limit-n schema-u -- declaration-u status )
    2 PICK 2 PICK 2 PICK _SDC-COUNTS-STATUS ?DUP IF
        >R 2DROP DROP 0 R> EXIT
    THEN
    SWAP SBOX-DECL-LIMIT-SIZE * +
    SWAP SBOX-DECL-ENTRY-SIZE * + SBOX-DECL-HEADER-SIZE +
    DUP SBOX-DECL-BYTES-MAX > IF DROP 0 SBOX-DECL-S-CAPACITY EXIT THEN
    SBOX-DECL-S-OK ;

\ =====================================================================
\  Writing
\ =====================================================================

\ ( module-rid revision artifact-digest profile-digest
\   entry-n limit-n schema-u declaration declaration-u -- status )
\ Clears DECLARATION, which must be exactly the measured size, and writes
\ its header: the module revision, the artifact and profile it binds, the
\ counts, and no provenance.  The limits, entries and schemas follow.
: SBOX-DECL-START
    4 PICK 4 PICK 4 PICK SBOX-DECL-MEASURE ?DUP IF
        >R DROP _SDC-DROP9 R> EXIT
    THEN
    2DUP < IF DROP _SDC-DROP9 SBOX-DECL-S-CAPACITY EXIT THEN
    OVER <> IF _SDC-DROP9 SBOX-DECL-S-INVALID EXIT THEN
    2DUP _SDC-SPAN? 0= 2 PICK 0= OR IF
        _SDC-DROP9 SBOX-DECL-S-INVALID EXIT
    THEN
    8 PICK RID-SIZE _SDC-PRESENT? 0= IF _SDC-DROP9 SBOX-DECL-S-INVALID EXIT THEN
    7 PICK 1 < IF _SDC-DROP9 SBOX-DECL-S-INVALID EXIT THEN
    6 PICK 32 _SDC-PRESENT? 0= IF _SDC-DROP9 SBOX-DECL-S-INVALID EXIT THEN
    5 PICK 32 _SDC-PRESENT? 0= IF _SDC-DROP9 SBOX-DECL-S-INVALID EXIT THEN
    8 PICK RID-SIZE 3 PICK 3 PICK MSPAN-OVERLAP?
    7 PICK 32 4 PICK 4 PICK MSPAN-OVERLAP? OR
    6 PICK 32 4 PICK 4 PICK MSPAN-OVERLAP? OR IF
        _SDC-DROP9 SBOX-DECL-S-ALIAS EXIT
    THEN
    2DUP 0 FILL
    >R >R
    _SDC-MAGIC R@ SWAP MOVE
    SBOX-DECL-FORMAT R@ _SDC-H-FORMAT + SBOX-BYTE-U16-LE!
    SBOX-DECL-HEADER-SIZE R@ _SDC-H-EXTENT + SBOX-BYTE-U16-LE!
    R> R> OVER _SDC-H-TOTAL + SBOX-BYTE-U64-LE! >R
    R@ _SDC-H-SCHEMA-U + SBOX-BYTE-U64-LE!
    R@ _SDC-H-LIMIT-N + SBOX-BYTE-U16-LE!
    R@ _SDC-H-ENTRY-N + SBOX-BYTE-U32-LE!
    R@ _SDC-H-PROFILE + 32 MOVE
    R@ _SDC-H-ARTIFACT + 32 MOVE
    R@ _SDC-H-REVISION + SBOX-BYTE-U64-LE!
    R> _SDC-H-MODULE + RID-SIZE MOVE
    SBOX-DECL-S-OK ;

\ KIND is SBOX-DECL-PROVENANCE-NONE with RID 0 and revision 0, or
\ -PACKAGE with a present package RID and a positive revision.  It records
\ what the installer says the module came from; it is not a trust claim.
: SBOX-DECL-PROVENANCE!  ( kind rid revision declaration -- status )
    >R
    2 PICK SBOX-DECL-PROVENANCE-NONE = IF
        0= SWAP 0= AND NIP 0= IF R> DROP SBOX-DECL-S-INVALID EXIT THEN
        R@ _SDC-H-PROV-RID + RID-SIZE 0 FILL
        0 R@ _SDC-H-PROV-REVISION + SBOX-BYTE-U64-LE!
        SBOX-DECL-PROVENANCE-NONE R> _SDC-H-PROVENANCE + SBOX-BYTE-U16-LE!
        SBOX-DECL-S-OK EXIT
    THEN
    2 PICK SBOX-DECL-PROVENANCE-PACKAGE <> IF
        2DROP DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    DUP 1 < IF 2DROP DROP R> DROP SBOX-DECL-S-INVALID EXIT THEN
    OVER RID-SIZE _SDC-PRESENT? 0= IF
        2DROP DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    R@ _SDC-H-PROV-REVISION + SBOX-BYTE-U64-LE!
    R@ _SDC-H-PROV-RID + RID-SIZE MOVE
    R> _SDC-H-PROVENANCE + SBOX-BYTE-U16-LE!
    SBOX-DECL-S-OK ;

\ The limit at INDEX: one SBOX-LIMIT- field and a positive, bounded value.
\ Limits are written in increasing field order.
: SBOX-DECL-LIMIT!  ( index field value declaration -- status )
    >R
    2 PICK DUP 0< SWAP R@ _SDC-LIMIT-N@ < 0= OR IF
        2DROP DROP R> DROP SBOX-DECL-S-STATE EXIT
    THEN
    DUP 1 < OVER SBOX-LIMIT-UNBOUNDED = OR IF
        2DROP DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    OVER DUP 0< SWAP SBOX-LIMIT-COUNT < 0= OR IF
        2DROP DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    ROT R> _SDC-LIMIT >R
    R@ 8 + SBOX-BYTE-U64-LE!
    R> SBOX-BYTE-U16-LE!
    SBOX-DECL-S-OK ;

\ The entry at INDEX: its name and machine signature.  Entries are written
\ in increasing name order.
: SBOX-DECL-ENTRY!  ( index name name-u signature declaration -- status )
    >R
    3 PICK DUP 0< SWAP R@ _SDC-ENTRY-N@ < 0= OR IF
        2DROP 2DROP R> DROP SBOX-DECL-S-STATE EXIT
    THEN
    DUP 1 < OVER _SDC-U32-MAX > OR IF
        2DROP 2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    2 PICK 2 PICK _SDC-SPAN? 0= IF
        2DROP 2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    2 PICK 2 PICK SBOX-ABI-ENTRY-NAME? 0= IF
        2DROP 2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    3 PICK R> _SDC-ENTRY >R
    R@ _SDC-E-SIGNATURE + SBOX-BYTE-U32-LE!
    DUP R@ _SDC-E-NAME-U + SBOX-BYTE-U16-LE!
    R@ _SDC-E-NAME + _SDC-E-NAME-AREA 0 FILL
    R@ _SDC-E-NAME + SWAP MOVE
    DROP R> DROP SBOX-DECL-S-OK ;

\ Where entry INDEX's schemas start: right after the previous entry's
\ output schema.
: _SDC-SCHEMA-START  ( index declaration -- offset )
    OVER 0= IF 2DROP 0 EXIT THEN
    SWAP 1- SWAP _SDC-ENTRY _SDC-E-OUTPUT +
    DUP _SDC-S-OFFSET + SBOX-BYTE-U64-LE@
    SWAP _SDC-S-LENGTH + SBOX-BYTE-U64-LE@ + ;

\ True once entry INDEX's schemas are written.
: _SDC-SCHEMAS-WRITTEN?  ( index declaration -- flag )
    _SDC-ENTRY _SDC-E-OUTPUT + _SDC-S-LENGTH + SBOX-BYTE-U64-LE@ 0<> ;

\ True when SPAN overlaps the declaration or the workspace.
: _SDW-ALIAS?  ( address length workspace -- flag )
    >R
    2DUP R@ _SDW.DECL @ _SDC-DECL-SPAN MSPAN-OVERLAP?
    -ROT R> SBOX-DECL-WORKSPACE-SIZE MSPAN-OVERLAP? OR ;

\ Copies SCHEMA to the cursor, fills SLOT with its place and digest, and
\ advances the cursor.
: _SDC-PUT-SCHEMA  ( schema schema-u slot workspace -- status )
    >R
    R@ _SDW.CURSOR @ OVER _SDC-S-OFFSET + SBOX-BYTE-U64-LE!
    OVER OVER _SDC-S-LENGTH + SBOX-BYTE-U64-LE!
    -ROT
    R@ _SDW.DECL @ _SDC-SCHEMAS R@ _SDW.CURSOR @ +
    2 PICK OVER 3 PICK MOVE
    SWAP DUP R@ _SDW.CURSOR +!
    ROT DROP
    ROT _SDC-S-DIGEST +
    R> _SDW.WORK SBOX-DIGEST-SCHEMA _SDC-DIGEST-STATUS ;

\ Entry INDEX's input and output schemas, written right after the
\ previous entry's.  Their digests are computed here.
: SBOX-DECL-SCHEMAS!
  ( index input input-u output output-u workspace declaration -- status )
    OVER _SDW-ADMIT? 0= IF 2DROP _SDC-DROP5 SBOX-DECL-S-INVALID EXIT THEN
    DUP _SDC-DECL-SPAN 3 PICK SBOX-DECL-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        2DROP _SDC-DROP5 SBOX-DECL-S-ALIAS EXIT
    THEN
    OVER _SDW.DECL ! >R
    4 PICK DUP 0< SWAP R@ _SDW.DECL @ _SDC-ENTRY-N@ < 0= OR IF
        _SDC-DROP5 R> DROP SBOX-DECL-S-STATE EXIT
    THEN
    4 PICK IF
        4 PICK 1- R@ _SDW.DECL @ _SDC-SCHEMAS-WRITTEN? 0= IF
            _SDC-DROP5 R> DROP SBOX-DECL-S-STATE EXIT
        THEN
    THEN
    DUP 1 < 3 PICK 1 < OR IF _SDC-DROP5 R> DROP SBOX-DECL-S-INVALID EXIT THEN
    3 PICK 3 PICK _SDC-SPAN? 0= 2 PICK 2 PICK _SDC-SPAN? 0= OR IF
        _SDC-DROP5 R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    3 PICK 3 PICK R@ _SDW-ALIAS? 2 PICK 2 PICK R@ _SDW-ALIAS? OR IF
        _SDC-DROP5 R> DROP SBOX-DECL-S-ALIAS EXIT
    THEN
    4 PICK R@ _SDW.DECL @ _SDC-SCHEMA-START R@ _SDW.CURSOR !
    R@ _SDW.DECL @ _SDC-SCHEMA-U@ R@ _SDW.CURSOR @ - 3 PICK -
    DUP 0< IF DROP _SDC-DROP5 R> DROP SBOX-DECL-S-CAPACITY EXIT THEN
    OVER < IF _SDC-DROP5 R> DROP SBOX-DECL-S-CAPACITY EXIT THEN
    3 PICK 3 PICK 6 PICK R@ _SDW.DECL @ _SDC-ENTRY _SDC-E-INPUT +
        R@ _SDC-PUT-SCHEMA ?DUP IF >R _SDC-DROP5 R> R> DROP EXIT THEN
    OVER OVER 6 PICK R@ _SDW.DECL @ _SDC-ENTRY _SDC-E-OUTPUT +
        R@ _SDC-PUT-SCHEMA
    >R _SDC-DROP5 R> R> DROP ;

\ =====================================================================
\  Validation
\ =====================================================================

: _SDC-PROVENANCE-VALID?  ( declaration -- flag )
    DUP _SDC-H-PROVENANCE + SBOX-BYTE-U16-LE@ CASE
        SBOX-DECL-PROVENANCE-NONE OF
            DUP _SDC-H-PROV-RID + RID-SIZE _SDC-ZERO?
            SWAP _SDC-H-PROV-REVISION + SBOX-BYTE-U64-LE@ 0= AND
        ENDOF
        SBOX-DECL-PROVENANCE-PACKAGE OF
            DUP _SDC-H-PROV-RID + RID-SIZE _SDC-ZERO? 0=
            SWAP _SDC-H-PROV-REVISION + SBOX-BYTE-U64-LE@ 0> AND
        ENDOF
        NIP 0 SWAP
    ENDCASE ;

: _SDC-HEADER-VALID?  ( declaration declaration-u -- flag )
    DUP SBOX-DECL-HEADER-SIZE < IF 2DROP 0 EXIT THEN
    OVER 8 _SDC-MAGIC COMPARE IF 2DROP 0 EXIT THEN
    OVER _SDC-H-FORMAT + SBOX-BYTE-U16-LE@ SBOX-DECL-FORMAT <> IF
        2DROP 0 EXIT
    THEN
    OVER _SDC-H-EXTENT + SBOX-BYTE-U16-LE@ SBOX-DECL-HEADER-SIZE <> IF
        2DROP 0 EXIT
    THEN
    OVER _SDC-H-FLAGS + SBOX-BYTE-U32-LE@ IF 2DROP 0 EXIT THEN
    OVER _SDC-H-TOTAL + SBOX-BYTE-U64-LE@ OVER <> IF 2DROP 0 EXIT THEN
    DROP
    DUP _SDC-ENTRY-N@ OVER _SDC-LIMIT-N@ 2 PICK _SDC-SCHEMA-U@
    SBOX-DECL-MEASURE IF 2DROP 0 EXIT THEN
    OVER _SDC-H-TOTAL + SBOX-BYTE-U64-LE@ <> IF DROP 0 EXIT THEN
    DUP _SDC-H-REVISION + SBOX-BYTE-U64-LE@ 1 < IF DROP 0 EXIT THEN
    DUP _SDC-H-MODULE + RID-SIZE _SDC-ZERO? IF DROP 0 EXIT THEN
    DUP _SDC-H-ARTIFACT + 32 _SDC-ZERO? IF DROP 0 EXIT THEN
    DUP _SDC-H-PROFILE + 32 _SDC-ZERO? IF DROP 0 EXIT THEN
    _SDC-PROVENANCE-VALID? ;

\ Limit records name distinct fields in increasing order, each with a
\ positive, bounded value.
: _SDC-LIMITS-VALID?  ( declaration -- flag )
    -1 OVER _SDC-LIMIT-N@ 0 ?DO
        I 2 PICK _SDC-LIMIT
        DUP 2 + 6 _SDC-ZERO? 0= IF DROP 2DROP 0 UNLOOP EXIT THEN
        DUP 8 + SBOX-BYTE-U64-LE@
        DUP 1 < SWAP SBOX-LIMIT-UNBOUNDED = OR IF
            DROP 2DROP 0 UNLOOP EXIT
        THEN
        SBOX-BYTE-U16-LE@
        DUP SBOX-LIMIT-COUNT < 0= IF DROP 2DROP 0 UNLOOP EXIT THEN
        TUCK < 0= IF 2DROP 0 UNLOOP EXIT THEN
    LOOP
    2DROP -1 ;

\ A slot starts at the cursor, fits in the section, and its digest
\ matches its bytes.
: _SDC-SLOT-STATUS  ( slot workspace -- status )
    >R
    DUP _SDC-S-OFFSET + SBOX-BYTE-U64-LE@ R@ _SDW.CURSOR @ <> IF
        DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    DUP _SDC-S-LENGTH + SBOX-BYTE-U64-LE@
    DUP 1 < IF 2DROP R> DROP SBOX-DECL-S-INVALID EXIT THEN
    DUP R@ _SDW.DECL @ _SDC-SCHEMA-U@ R@ _SDW.CURSOR @ - > IF
        2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    R@ _SDW.DECL @ _SDC-SCHEMAS R@ _SDW.CURSOR @ + OVER
    R@ _SDW.DIGEST R@ _SDW.WORK SBOX-DIGEST-SCHEMA ?DUP IF
        _SDC-DIGEST-STATUS NIP NIP R> DROP EXIT
    THEN
    R@ _SDW.CURSOR +!
    _SDC-S-DIGEST + 32 R@ _SDW.DIGEST 32 COMPARE
    R> DROP IF SBOX-DECL-S-DIGEST ELSE SBOX-DECL-S-OK THEN ;

\ One entry: reserved bytes zero, a positive signature, a name after the
\ previous one with a zero tail, and both schema slots.
: _SDC-ENTRY-STATUS  ( index workspace -- status )
    >R
    DUP R@ _SDW.DECL @ _SDC-ENTRY
    DUP _SDC-E-RESERVED + SBOX-BYTE-U16-LE@ IF
        2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    DUP _SDC-E-SIGNATURE + SBOX-BYTE-U32-LE@ 1 < IF
        2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    DUP _SDC-E-NAME-U + SBOX-BYTE-U16-LE@
    OVER _SDC-E-NAME + OVER SBOX-ABI-ENTRY-NAME? 0= IF
        DROP 2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    OVER _SDC-E-NAME + OVER + _SDC-E-NAME-AREA 2 PICK - _SDC-ZERO? 0= IF
        DROP 2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    2 PICK IF
        OVER _SDC-E-NAME + OVER
        4 PICK 1- R@ _SDW.DECL @ _SDC-ENTRY
        DUP _SDC-E-NAME + SWAP _SDC-E-NAME-U + SBOX-BYTE-U16-LE@
        COMPARE 0> 0= IF DROP 2DROP R> DROP SBOX-DECL-S-INVALID EXIT THEN
    THEN
    DROP NIP
    DUP _SDC-E-INPUT + R@ _SDC-SLOT-STATUS ?DUP IF
        NIP R> DROP EXIT
    THEN
    _SDC-E-OUTPUT + R@ _SDC-SLOT-STATUS
    R> DROP ;

\ Accepts only a complete canonical declaration, every embedded schema
\ digest included.
: SBOX-DECL-VALIDATE  ( declaration declaration-u workspace -- status )
    DUP _SDW-ADMIT? 0= IF SBOX-DECL-S-INVALID _SDC-DROP3>STATUS EXIT THEN
    2 PICK 2 PICK _SDC-SPAN? 0= 3 PICK 0= OR IF
        SBOX-DECL-S-INVALID _SDC-DROP3>STATUS EXIT
    THEN
    2 PICK 2 PICK 2 PICK SBOX-DECL-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        SBOX-DECL-S-ALIAS _SDC-DROP3>STATUS EXIT
    THEN
    >R
    2DUP _SDC-HEADER-VALID? 0= IF
        2DROP R> DROP SBOX-DECL-S-INVALID EXIT
    THEN
    DROP DUP R@ _SDW.DECL !
    _SDC-LIMITS-VALID? 0= IF R> DROP SBOX-DECL-S-INVALID EXIT THEN
    0 R@ _SDW.CURSOR !
    R>
    DUP _SDW.DECL @ _SDC-ENTRY-N@ 0 ?DO
        I OVER _SDC-ENTRY-STATUS ?DUP IF NIP UNLOOP EXIT THEN
    LOOP
    \ The entries' schemas cover the whole section.
    DUP _SDW.CURSOR @ SWAP _SDW.DECL @ _SDC-SCHEMA-U@ <> IF
        SBOX-DECL-S-INVALID EXIT
    THEN
    SBOX-DECL-S-OK ;

\ The declaration's identity: SHA3-256 of its bytes in the declaration
\ domain, once SBOX-DECL-VALIDATE accepts it.
: SBOX-DECL-DIGEST  ( declaration declaration-u digest workspace -- status )
    OVER 32 2 PICK SBOX-DECL-WORKSPACE-SIZE MSPAN-OVERLAP? IF
        2DROP 2DROP SBOX-DECL-S-ALIAS EXIT
    THEN
    3 PICK 3 PICK 2 PICK SBOX-DECL-VALIDATE ?DUP IF
        >R 2DROP 2DROP R> EXIT
    THEN
    _SDW.WORK SBOX-DIGEST-DECLARATION _SDC-DIGEST-STATUS ;

\ =====================================================================
\  Reading an accepted declaration
\ =====================================================================

: SBOX-DECL-MODULE@  ( declaration -- rid revision )
    DUP _SDC-H-MODULE + SWAP _SDC-H-REVISION + SBOX-BYTE-U64-LE@ ;

: SBOX-DECL-ARTIFACT-DIGEST@  ( declaration -- digest ) _SDC-H-ARTIFACT + ;
: SBOX-DECL-PROFILE-DIGEST@  ( declaration -- digest ) _SDC-H-PROFILE + ;

: SBOX-DECL-PROVENANCE@  ( declaration -- kind rid revision )
    DUP _SDC-H-PROVENANCE + SBOX-BYTE-U16-LE@
    OVER _SDC-H-PROV-RID +
    ROT _SDC-H-PROV-REVISION + SBOX-BYTE-U64-LE@ ;

: SBOX-DECL-ENTRY-N@  ( declaration -- n ) _SDC-ENTRY-N@ ;

: SBOX-DECL-ENTRY-NAME$  ( index declaration -- name name-u )
    _SDC-ENTRY DUP _SDC-E-NAME + SWAP _SDC-E-NAME-U + SBOX-BYTE-U16-LE@ ;

: SBOX-DECL-ENTRY-SIGNATURE@  ( index declaration -- signature )
    _SDC-ENTRY _SDC-E-SIGNATURE + SBOX-BYTE-U32-LE@ ;

: _SDC-SLOT$  ( slot declaration -- schema schema-u digest )
    _SDC-SCHEMAS OVER _SDC-S-OFFSET + SBOX-BYTE-U64-LE@ +
    OVER _SDC-S-LENGTH + SBOX-BYTE-U64-LE@
    ROT _SDC-S-DIGEST + ;

: SBOX-DECL-ENTRY-INPUT$  ( index declaration -- schema schema-u digest )
    TUCK _SDC-ENTRY _SDC-E-INPUT + SWAP _SDC-SLOT$ ;

: SBOX-DECL-ENTRY-OUTPUT$  ( index declaration -- schema schema-u digest )
    TUCK _SDC-ENTRY _SDC-E-OUTPUT + SWAP _SDC-SLOT$ ;

\ The entry named NAME, by binary search over the ordered names.
: SBOX-DECL-ENTRY-FIND  ( name name-u declaration -- index|-1 )
    OVER 1 < 2 PICK SBOX-ABI-ENTRY-NAME-MAX > OR IF DROP 2DROP -1 EXIT THEN
    >R 0 R@ _SDC-ENTRY-N@
    BEGIN 2DUP < WHILE
        2DUP + 1 RSHIFT
        4 PICK 4 PICK 2 PICK R@ SBOX-DECL-ENTRY-NAME$ COMPARE
        DUP 0= IF DROP NIP NIP NIP NIP R> DROP EXIT THEN
        0< IF NIP ELSE 1+ ROT DROP SWAP THEN
    REPEAT
    2DROP 2DROP R> DROP -1 ;

: SBOX-DECL-LIMIT-N@  ( declaration -- n ) _SDC-LIMIT-N@ ;

: SBOX-DECL-LIMIT@  ( index declaration -- field value )
    _SDC-LIMIT DUP SBOX-BYTE-U16-LE@ SWAP 8 + SBOX-BYTE-U64-LE@ ;

\ Fills LIMITS with the limits the declaration asks for.  Every other
\ field stays unbounded, so the record only narrows what it meets.
\ Returns an SBOX-LIMITS- status.
: SBOX-DECL-LIMITS  ( declaration limits -- status )
    DUP SBOX-LIMITS-BEGIN ?DUP IF NIP NIP EXIT THEN
    OVER _SDC-LIMIT-N@ 0 ?DO
        I 2 PICK SBOX-DECL-LIMIT@ SWAP 2 PICK SBOX-LIMIT-CAP
        ?DUP IF NIP NIP UNLOOP EXIT THEN
    LOOP
    NIP SBOX-LIMITS-SEAL ;
