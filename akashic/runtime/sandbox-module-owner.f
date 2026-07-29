\ =====================================================================
\  sandbox-module-owner.f - bounded in-memory Stage 2 module ownership
\ =====================================================================
\  This activation-local owner is the exact, non-invoking composition seam
\  above the neutral sandbox.  It owns registered profile identities,
\  structurally validated canonical schemas, independently verified plans,
\  installed declarations/artifacts, and caller-owned leases which pin those
\  immutable objects.
\
\  The owner is deliberately not a catalog or authority.  It has no VFS,
\  persistence, Practice, Context, Desk, Agent, capability, import, or host
\  invocation path.  Durable loading and revocation belong in future owner
\  adapters which feed this same exact in-memory boundary.
\ =====================================================================

REQUIRE identity.f
REQUIRE sandbox-declaration.f
REQUIRE sandbox-schema.f
REQUIRE ../sandbox/verifier.f
REQUIRE ../sandbox/digest.f
REQUIRE ../text/utf8.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f
REQUIRE ../concurrency/guard.f

\ Keep the linked-loader identity unique and within KDOS's 23-byte key.
S" akashic-rt-sbx-owner" NIP 20 <> [IF]
    ." sandbox module-owner loader identity mismatch" CR ABORT
[THEN]
PROVIDED akashic-rt-sbx-owner

\ =====================================================================
\  Public status and configured hard bounds
\ =====================================================================

 0 CONSTANT SBOX-MOWNER-S-OK
 1 CONSTANT SBOX-MOWNER-S-INVALID
 2 CONSTANT SBOX-MOWNER-S-STATE
 3 CONSTANT SBOX-MOWNER-S-CAPACITY
 4 CONSTANT SBOX-MOWNER-S-NOMEM
 5 CONSTANT SBOX-MOWNER-S-BUSY
 6 CONSTANT SBOX-MOWNER-S-CONFLICT
 7 CONSTANT SBOX-MOWNER-S-NOT-FOUND
 8 CONSTANT SBOX-MOWNER-S-DIGEST
 9 CONSTANT SBOX-MOWNER-S-PROFILE
10 CONSTANT SBOX-MOWNER-S-SCHEMA
11 CONSTANT SBOX-MOWNER-S-DECLARATION
12 CONSTANT SBOX-MOWNER-S-ARTIFACT
13 CONSTANT SBOX-MOWNER-S-VERIFY
14 CONSTANT SBOX-MOWNER-S-ENTRY
15 CONSTANT SBOX-MOWNER-S-ALIAS
16 CONSTANT SBOX-MOWNER-S-CLEANUP
17 CONSTANT SBOX-MOWNER-S-PLATFORM

: SBOX-MOWNER-STATUS-VALID?  ( status -- flag )
    DUP SBOX-MOWNER-S-OK >=
    SWAP SBOX-MOWNER-S-PLATFORM <= AND ;

\ Count bounds prevent corrupted configuration from turning validation loops
\ into unbounded walks.  Exact caller-selected capacities remain available
\ within these production activation ceilings.
64  CONSTANT SBOX-MOWNER-MODULE-CAP-MAX
16  CONSTANT SBOX-MOWNER-PROFILE-CAP-MAX
256 CONSTANT SBOX-MOWNER-SCHEMA-CAP-MAX
64  CONSTANT SBOX-MOWNER-PLAN-CAP-MAX
256 CONSTANT SBOX-MOWNER-SCHEMA-DEPTH-MAX

262144 CONSTANT SBOX-MOWNER-PROFILE-BYTES-MAX

1 CONSTANT _SMO-STATE-READY
2 CONSTANT _SMO-STATE-RELEASING

0x3152574F5842534D CONSTANT _SMO-MAGIC  \ "MSBXOWR1"

\ =====================================================================
\  Owner descriptor
\ =====================================================================

  0 CONSTANT _SMO-MAGIC-OFF
  8 CONSTANT _SMO-SELF-OFF
 16 CONSTANT _SMO-STATE-OFF
 24 CONSTANT _SMO-BACKING-OFF
 32 CONSTANT _SMO-BACKING-U-OFF
 40 CONSTANT _SMO-MODULE-CAP-OFF
 48 CONSTANT _SMO-MODULE-N-OFF
 56 CONSTANT _SMO-PROFILE-CAP-OFF
 64 CONSTANT _SMO-PROFILE-N-OFF
 72 CONSTANT _SMO-SCHEMA-CAP-OFF
 80 CONSTANT _SMO-SCHEMA-N-OFF
 88 CONSTANT _SMO-PLAN-CAP-OFF
 96 CONSTANT _SMO-PLAN-N-OFF
104 CONSTANT _SMO-LEASE-N-OFF
112 CONSTANT _SMO-SCHEMA-DEPTH-OFF
120 CONSTANT _SMO-GENERATION-OFF
128 CONSTANT _SMO-GUARD-OFF
160 CONSTANT _SMO-MODULES-OFF
168 CONSTANT _SMO-PROFILES-OFF
176 CONSTANT _SMO-SCHEMAS-OFF
184 CONSTANT _SMO-PLANS-OFF
192 CONSTANT _SMO-DECL-VIEW-OFF
200 CONSTANT _SMO-DIGEST-WORK-OFF
208 CONSTANT _SMO-SCHEMA-WORK-OFF
216 CONSTANT _SMO-SCHEMA-WORK-U-OFF
224 CONSTANT _SMO-VERIFIER-WORK-OFF
232 CONSTANT _SMO-LAST-VERIFY-STATUS-OFF
240 CONSTANT _SMO-LAST-VERIFY-DETAIL-OFF
248 CONSTANT _SMO-LAST-VERIFY-INDEX-OFF

\ Operation scratch is part of the owner and is used only while its guard is
\ held.  There is no module-global mutable operation state.
256 CONSTANT _SMO-S-A-OFF
264 CONSTANT _SMO-S-U-OFF
272 CONSTANT _SMO-S-B-OFF
280 CONSTANT _SMO-S-V-OFF
288 CONSTANT _SMO-S-C-OFF
296 CONSTANT _SMO-S-W-OFF
304 CONSTANT _SMO-S-D-OFF
312 CONSTANT _SMO-S-X-OFF
320 CONSTANT _SMO-S-E-OFF
328 CONSTANT _SMO-S-F-OFF
336 CONSTANT _SMO-S-I-OFF
344 CONSTANT _SMO-S-J-OFF
352 CONSTANT _SMO-S-ROW-OFF
360 CONSTANT _SMO-S-OTHER-OFF
368 CONSTANT _SMO-S-ENTRY-OFF
376 CONSTANT _SMO-S-PLAN-OFF
384 CONSTANT _SMO-S-PTR-OFF
392 CONSTANT _SMO-S-SIZE-OFF
400 CONSTANT _SMO-S-STATUS-OFF
408 CONSTANT _SMO-S-P-OFF
416 CONSTANT _SMO-S-Q-OFF
424 CONSTANT _SMO-S-R-OFF
432 CONSTANT _SMO-S-T-OFF

448 CONSTANT _SMO-TEMP-A-OFF
480 CONSTANT _SMO-TEMP-B-OFF
512 CONSTANT _SMO-TEMP-C-OFF
544 CONSTANT _SMO-RESERVED-OFF
640 CONSTANT SBOX-MOWNER-SIZE

: _SMO.MAGIC              ( owner -- a ) _SMO-MAGIC-OFF + ;
: _SMO.SELF               ( owner -- a ) _SMO-SELF-OFF + ;
: _SMO.STATE              ( owner -- a ) _SMO-STATE-OFF + ;
: _SMO.BACKING            ( owner -- a ) _SMO-BACKING-OFF + ;
: _SMO.BACKING-U          ( owner -- a ) _SMO-BACKING-U-OFF + ;
: _SMO.MODULE-CAP         ( owner -- a ) _SMO-MODULE-CAP-OFF + ;
: _SMO.MODULE-N           ( owner -- a ) _SMO-MODULE-N-OFF + ;
: _SMO.PROFILE-CAP        ( owner -- a ) _SMO-PROFILE-CAP-OFF + ;
: _SMO.PROFILE-N          ( owner -- a ) _SMO-PROFILE-N-OFF + ;
: _SMO.SCHEMA-CAP         ( owner -- a ) _SMO-SCHEMA-CAP-OFF + ;
: _SMO.SCHEMA-N           ( owner -- a ) _SMO-SCHEMA-N-OFF + ;
: _SMO.PLAN-CAP           ( owner -- a ) _SMO-PLAN-CAP-OFF + ;
: _SMO.PLAN-N             ( owner -- a ) _SMO-PLAN-N-OFF + ;
: _SMO.LEASE-N            ( owner -- a ) _SMO-LEASE-N-OFF + ;
: _SMO.SCHEMA-DEPTH       ( owner -- a ) _SMO-SCHEMA-DEPTH-OFF + ;
: _SMO.GENERATION         ( owner -- a ) _SMO-GENERATION-OFF + ;
: _SMO.GUARD              ( owner -- guard ) _SMO-GUARD-OFF + ;
: _SMO.MODULES            ( owner -- a ) _SMO-MODULES-OFF + ;
: _SMO.PROFILES           ( owner -- a ) _SMO-PROFILES-OFF + ;
: _SMO.SCHEMAS            ( owner -- a ) _SMO-SCHEMAS-OFF + ;
: _SMO.PLANS              ( owner -- a ) _SMO-PLANS-OFF + ;
: _SMO.DECL-VIEW          ( owner -- a ) _SMO-DECL-VIEW-OFF + ;
: _SMO.DIGEST-WORK        ( owner -- a ) _SMO-DIGEST-WORK-OFF + ;
: _SMO.SCHEMA-WORK        ( owner -- a ) _SMO-SCHEMA-WORK-OFF + ;
: _SMO.SCHEMA-WORK-U      ( owner -- a ) _SMO-SCHEMA-WORK-U-OFF + ;
: _SMO.VERIFIER-WORK      ( owner -- a ) _SMO-VERIFIER-WORK-OFF + ;
: _SMO.LAST-VERIFY-STATUS ( owner -- a )
    _SMO-LAST-VERIFY-STATUS-OFF + ;
: _SMO.LAST-VERIFY-DETAIL ( owner -- a )
    _SMO-LAST-VERIFY-DETAIL-OFF + ;
: _SMO.LAST-VERIFY-INDEX  ( owner -- a )
    _SMO-LAST-VERIFY-INDEX-OFF + ;

: _SMO.S-A      ( owner -- a ) _SMO-S-A-OFF + ;
: _SMO.S-U      ( owner -- a ) _SMO-S-U-OFF + ;
: _SMO.S-B      ( owner -- a ) _SMO-S-B-OFF + ;
: _SMO.S-V      ( owner -- a ) _SMO-S-V-OFF + ;
: _SMO.S-C      ( owner -- a ) _SMO-S-C-OFF + ;
: _SMO.S-W      ( owner -- a ) _SMO-S-W-OFF + ;
: _SMO.S-D      ( owner -- a ) _SMO-S-D-OFF + ;
: _SMO.S-X      ( owner -- a ) _SMO-S-X-OFF + ;
: _SMO.S-E      ( owner -- a ) _SMO-S-E-OFF + ;
: _SMO.S-F      ( owner -- a ) _SMO-S-F-OFF + ;
: _SMO.S-I      ( owner -- a ) _SMO-S-I-OFF + ;
: _SMO.S-J      ( owner -- a ) _SMO-S-J-OFF + ;
: _SMO.S-ROW    ( owner -- a ) _SMO-S-ROW-OFF + ;
: _SMO.S-OTHER  ( owner -- a ) _SMO-S-OTHER-OFF + ;
: _SMO.S-ENTRY  ( owner -- a ) _SMO-S-ENTRY-OFF + ;
: _SMO.S-PLAN   ( owner -- a ) _SMO-S-PLAN-OFF + ;
: _SMO.S-PTR    ( owner -- a ) _SMO-S-PTR-OFF + ;
: _SMO.S-SIZE   ( owner -- a ) _SMO-S-SIZE-OFF + ;
: _SMO.S-STATUS ( owner -- a ) _SMO-S-STATUS-OFF + ;
: _SMO.S-P      ( owner -- a ) _SMO-S-P-OFF + ;
: _SMO.S-Q      ( owner -- a ) _SMO-S-Q-OFF + ;
: _SMO.S-R      ( owner -- a ) _SMO-S-R-OFF + ;
: _SMO.S-T      ( owner -- a ) _SMO-S-T-OFF + ;
: _SMO.TEMP-A   ( owner -- digest ) _SMO-TEMP-A-OFF + ;
: _SMO.TEMP-B   ( owner -- digest ) _SMO-TEMP-B-OFF + ;
: _SMO.TEMP-C   ( owner -- digest ) _SMO-TEMP-C-OFF + ;

: _SMO-SCRATCH-CLEAR  ( owner -- )
    _SMO-S-A-OFF +
    _SMO-RESERVED-OFF _SMO-S-A-OFF - 0 FILL ;

\ =====================================================================
\  Registry row layouts
\ =====================================================================

0x31464F5250584253 CONSTANT _SMO-PROFILE-ROW-MAGIC \ "SBXPROF1"
0x3141484353584253 CONSTANT _SMO-SCHEMA-ROW-MAGIC  \ "SBXSCHA1"
0x314E414C50584253 CONSTANT _SMO-PLAN-ROW-MAGIC    \ "SBXPLAN1"
0x31444F4D53584253 CONSTANT _SMO-MODULE-ROW-MAGIC  \ "SBXSMOD1"

  0 CONSTANT _SMP-MAGIC
  8 CONSTANT _SMP-BLOB
 16 CONSTANT _SMP-ID
 24 CONSTANT _SMP-ID-U
 32 CONSTANT _SMP-DESCRIPTOR
 40 CONSTANT _SMP-DESCRIPTOR-U
 48 CONSTANT _SMP-DIGEST
 80 CONSTANT _SMP-PROFILE
 88 CONSTANT _SMP-MODULE-REFS
 96 CONSTANT _SMP-RESERVED
128 CONSTANT _SMO-PROFILE-ROW-SIZE

: _SMP.MAGIC         ( row -- a ) _SMP-MAGIC + ;
: _SMP.BLOB          ( row -- a ) _SMP-BLOB + ;
: _SMP.ID            ( row -- a ) _SMP-ID + ;
: _SMP.ID-U          ( row -- a ) _SMP-ID-U + ;
: _SMP.DESCRIPTOR    ( row -- a ) _SMP-DESCRIPTOR + ;
: _SMP.DESCRIPTOR-U  ( row -- a ) _SMP-DESCRIPTOR-U + ;
: _SMP.DIGEST        ( row -- digest ) _SMP-DIGEST + ;
: _SMP.PROFILE       ( row -- a ) _SMP-PROFILE + ;
: _SMP.MODULE-REFS   ( row -- a ) _SMP-MODULE-REFS + ;

 0 CONSTANT _SMS-MAGIC
 8 CONSTANT _SMS-BYTES
16 CONSTANT _SMS-BYTES-U
24 CONSTANT _SMS-DIGEST
56 CONSTANT _SMS-RESERVED
96 CONSTANT _SMO-SCHEMA-ROW-SIZE

: _SMS.MAGIC    ( row -- a ) _SMS-MAGIC + ;
: _SMS.BYTES    ( row -- a ) _SMS-BYTES + ;
: _SMS.BYTES-U  ( row -- a ) _SMS-BYTES-U + ;
: _SMS.DIGEST   ( row -- digest ) _SMS-DIGEST + ;

  0 CONSTANT _SML-MAGIC
  8 CONSTANT _SML-ARTIFACT-DIGEST
 40 CONSTANT _SML-PROFILE-DIGEST
 72 CONSTANT _SML-PLAN
 80 CONSTANT _SML-PLAN-U
 88 CONSTANT _SML-PROFILE-ROW
 96 CONSTANT _SML-MODULE-REFS
104 CONSTANT _SML-RESERVED
112 CONSTANT _SMO-PLAN-ROW-SIZE

: _SML.MAGIC            ( row -- a ) _SML-MAGIC + ;
: _SML.ARTIFACT-DIGEST  ( row -- digest ) _SML-ARTIFACT-DIGEST + ;
: _SML.PROFILE-DIGEST   ( row -- digest ) _SML-PROFILE-DIGEST + ;
: _SML.PLAN             ( row -- a ) _SML-PLAN + ;
: _SML.PLAN-U           ( row -- a ) _SML-PLAN-U + ;
: _SML.PROFILE-ROW      ( row -- a ) _SML-PROFILE-ROW + ;
: _SML.MODULE-REFS      ( row -- a ) _SML-MODULE-REFS + ;

  0 CONSTANT _SMM-MAGIC
  8 CONSTANT _SMM-DECLARATION
 16 CONSTANT _SMM-DECLARATION-U
 24 CONSTANT _SMM-ARTIFACT
 32 CONSTANT _SMM-ARTIFACT-U
 40 CONSTANT _SMM-OWNER-RID
 72 CONSTANT _SMM-MODULE-RID
104 CONSTANT _SMM-REVISION
112 CONSTANT _SMM-DECLARATION-DIGEST
144 CONSTANT _SMM-ARTIFACT-DIGEST
176 CONSTANT _SMM-PROFILE-ROW
184 CONSTANT _SMM-PLAN-ROW
192 CONSTANT _SMM-LEASES
200 CONSTANT _SMM-ENTRY-N
208 CONSTANT _SMM-RESERVED
224 CONSTANT _SMO-MODULE-ROW-SIZE

: _SMM.MAGIC               ( row -- a ) _SMM-MAGIC + ;
: _SMM.DECLARATION         ( row -- a ) _SMM-DECLARATION + ;
: _SMM.DECLARATION-U       ( row -- a ) _SMM-DECLARATION-U + ;
: _SMM.ARTIFACT            ( row -- a ) _SMM-ARTIFACT + ;
: _SMM.ARTIFACT-U          ( row -- a ) _SMM-ARTIFACT-U + ;
: _SMM.OWNER-RID           ( row -- rid ) _SMM-OWNER-RID + ;
: _SMM.MODULE-RID          ( row -- rid ) _SMM-MODULE-RID + ;
: _SMM.REVISION            ( row -- a ) _SMM-REVISION + ;
: _SMM.DECLARATION-DIGEST  ( row -- digest )
    _SMM-DECLARATION-DIGEST + ;
: _SMM.ARTIFACT-DIGEST     ( row -- digest ) _SMM-ARTIFACT-DIGEST + ;
: _SMM.PROFILE-ROW         ( row -- a ) _SMM-PROFILE-ROW + ;
: _SMM.PLAN-ROW            ( row -- a ) _SMM-PLAN-ROW + ;
: _SMM.LEASES              ( row -- a ) _SMM-LEASES + ;
: _SMM.ENTRY-N             ( row -- a ) _SMM-ENTRY-N + ;

: _SMO-PROFILE-ROW  ( index owner -- row )
    _SMO.PROFILES @ SWAP _SMO-PROFILE-ROW-SIZE * + ;

: _SMO-SCHEMA-ROW  ( index owner -- row )
    _SMO.SCHEMAS @ SWAP _SMO-SCHEMA-ROW-SIZE * + ;

: _SMO-PLAN-ROW  ( index owner -- row )
    _SMO.PLANS @ SWAP _SMO-PLAN-ROW-SIZE * + ;

: _SMO-MODULE-ROW  ( index owner -- row )
    _SMO.MODULES @ SWAP _SMO-MODULE-ROW-SIZE * + ;

\ =====================================================================
\  Admission helpers and exact byte identities
\ =====================================================================

: _SMO-CALLER>STATUS  ( caller-status -- status )
    DUP CALLER-SPAN-S-OK = IF DROP SBOX-MOWNER-S-OK EXIT THEN
    DUP CALLER-SPAN-S-RANGE = IF
        DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP CALLER-SPAN-S-PROTECTED = IF
        DROP SBOX-MOWNER-S-PLATFORM EXIT
    THEN
    DROP SBOX-MOWNER-S-PLATFORM ;

: _SMO-READ-SPAN-STATUS  ( address length -- status )
    DUP 0< IF 2DROP SBOX-MOWNER-S-INVALID EXIT THEN
    DUP 0= IF 2DROP SBOX-MOWNER-S-OK EXIT THEN
    OVER 0= IF 2DROP SBOX-MOWNER-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS _SMO-CALLER>STATUS ;

: _SMO-FIXED-SPAN-STATUS  ( address length -- status )
    DUP 0> 0= IF 2DROP SBOX-MOWNER-S-INVALID EXIT THEN
    OVER 0= IF 2DROP SBOX-MOWNER-S-INVALID EXIT THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    CALLER-SPAN-STATUS _SMO-CALLER>STATUS ;

: _SMO-32=  ( a b -- flag )
    SBOX-DIGEST-SIZE COMPARE 0= ;

: _SMO-32-ZERO?  ( digest -- flag )
    SBOX-DIGEST-SIZE 0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SMO-DIGEST-PRESENT?  ( digest -- flag )
    DUP SBOX-DIGEST-SIZE _SMO-FIXED-SPAN-STATUS
        SBOX-MOWNER-S-OK <> IF DROP 0 EXIT THEN
    _SMO-32-ZERO? 0= ;

: _SMO-NUL-FREE?  ( address length -- flag )
    BEGIN DUP 0> WHILE
        OVER C@ 0= IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _SMO-ZERO?  ( address length -- flag )
    BEGIN DUP 0> WHILE
        OVER C@ IF 2DROP 0 EXIT THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP -1 ;

: _SMO-PROFILE-ID?  ( address length -- flag )
    DUP 1 < OVER SBOX-DECL-PROFILE-ID-MAX > OR IF
        2DROP 0 EXIT
    THEN
    2DUP _SMO-READ-SPAN-STATUS SBOX-MOWNER-S-OK <> IF
        2DROP 0 EXIT
    THEN
    2DUP UTF8-VALID? 0= IF 2DROP 0 EXIT THEN
    _SMO-NUL-FREE? ;

: _SMO-MODULE-CAP?  ( count -- flag )
    DUP 0> SWAP SBOX-MOWNER-MODULE-CAP-MAX <= AND ;

: _SMO-PROFILE-CAP?  ( count -- flag )
    DUP 0> SWAP SBOX-MOWNER-PROFILE-CAP-MAX <= AND ;

: _SMO-SCHEMA-CAP?  ( count -- flag )
    DUP 0> SWAP SBOX-MOWNER-SCHEMA-CAP-MAX <= AND ;

: _SMO-PLAN-CAP?  ( count -- flag )
    DUP 0> SWAP SBOX-MOWNER-PLAN-CAP-MAX <= AND ;

: _SMO-SCHEMA-DEPTH?  ( depth -- flag )
    DUP 0> SWAP SBOX-MOWNER-SCHEMA-DEPTH-MAX <= AND ;

: SBOX-MOWNER-BACKING-MEASURE
  ( module-cap profile-cap schema-cap plan-cap schema-depth
    -- bytes|0 status )
    4 PICK _SMO-MODULE-CAP?
    4 PICK _SMO-PROFILE-CAP? AND
    3 PICK _SMO-SCHEMA-CAP? AND
    2 PICK _SMO-PLAN-CAP? AND
    1 PICK _SMO-SCHEMA-DEPTH? AND 0= IF
        2DROP 2DROP DROP 0 SBOX-MOWNER-S-INVALID EXIT
    THEN

    4 PICK _SMO-MODULE-ROW-SIZE *
    4 PICK _SMO-PROFILE-ROW-SIZE * +
    3 PICK _SMO-SCHEMA-ROW-SIZE * +
    2 PICK _SMO-PLAN-ROW-SIZE * +
    SBOX-DECL-VIEW-SIZE +
    SBOX-DIGEST-WORKSPACE-SIZE +
    SBOX-VERIFIER-WORKSPACE-SIZE +
    1 PICK SBOX-SCHEMA-WORKSPACE-MEASURE
    DUP IF
        >R DROP DROP
        2DROP 2DROP DROP
        0
        R> SBOX-SCHEMA-S-CAPACITY =
        IF SBOX-MOWNER-S-CAPACITY ELSE SBOX-MOWNER-S-INVALID THEN
        EXIT
    THEN
    DROP +
    >R 2DROP 2DROP DROP R> SBOX-MOWNER-S-OK ;

\ =====================================================================
\  Owner initialization and shallow validity
\ =====================================================================

: _SMO-POINTERS-BIND  ( owner -- )
    >R
    R@ _SMO.BACKING @
    DUP R@ _SMO.MODULES !
    R@ _SMO.MODULE-CAP @ _SMO-MODULE-ROW-SIZE * +
    DUP R@ _SMO.PROFILES !
    R@ _SMO.PROFILE-CAP @ _SMO-PROFILE-ROW-SIZE * +
    DUP R@ _SMO.SCHEMAS !
    R@ _SMO.SCHEMA-CAP @ _SMO-SCHEMA-ROW-SIZE * +
    DUP R@ _SMO.PLANS !
    R@ _SMO.PLAN-CAP @ _SMO-PLAN-ROW-SIZE * +
    DUP R@ _SMO.DECL-VIEW !
    SBOX-DECL-VIEW-SIZE +
    DUP R@ _SMO.DIGEST-WORK !
    SBOX-DIGEST-WORKSPACE-SIZE +
    DUP R@ _SMO.SCHEMA-WORK !
    R@ _SMO.SCHEMA-WORK-U @ +
    R@ _SMO.VERIFIER-WORK !
    R> DROP ;

: _SMO-EXPECTED-END  ( owner -- address )
    DUP _SMO.VERIFIER-WORK @
    SBOX-VERIFIER-WORKSPACE-SIZE +
    SWAP DROP ;

: _SMO-HEADER-ADMITTED?  ( owner -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBOX-MOWNER-SIZE MSPAN-NONWRAPPING? 0= IF
        DROP 0 EXIT
    THEN
    SBOX-MOWNER-SIZE CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = ;

: SBOX-MOWNER-VALID?  ( owner -- flag )
    DUP _SMO-HEADER-ADMITTED? 0= IF DROP 0 EXIT THEN
    DUP _SMO.MAGIC @ _SMO-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SMO.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SMO.STATE @ _SMO-STATE-READY <> IF DROP 0 EXIT THEN
    DUP _SMO.GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SMO.GUARD GUARD-SPIN? 0= IF DROP 0 EXIT THEN

    DUP _SMO.MODULE-CAP @ _SMO-MODULE-CAP? 0= IF DROP 0 EXIT THEN
    DUP _SMO.PROFILE-CAP @ _SMO-PROFILE-CAP? 0= IF DROP 0 EXIT THEN
    DUP _SMO.SCHEMA-CAP @ _SMO-SCHEMA-CAP? 0= IF DROP 0 EXIT THEN
    DUP _SMO.PLAN-CAP @ _SMO-PLAN-CAP? 0= IF DROP 0 EXIT THEN
    DUP _SMO.SCHEMA-DEPTH @ _SMO-SCHEMA-DEPTH? 0= IF
        DROP 0 EXIT
    THEN

    DUP _SMO.MODULE-N @ DUP 0<
    SWAP 2 PICK _SMO.MODULE-CAP @ > OR IF DROP 0 EXIT THEN
    DUP _SMO.PROFILE-N @ DUP 0<
    SWAP 2 PICK _SMO.PROFILE-CAP @ > OR IF DROP 0 EXIT THEN
    DUP _SMO.SCHEMA-N @ DUP 0<
    SWAP 2 PICK _SMO.SCHEMA-CAP @ > OR IF DROP 0 EXIT THEN
    DUP _SMO.PLAN-N @ DUP 0<
    SWAP 2 PICK _SMO.PLAN-CAP @ > OR IF DROP 0 EXIT THEN
    DUP _SMO.LEASE-N @ 0< IF DROP 0 EXIT THEN

    DUP _SMO.BACKING @ DUP 0= IF 2DROP 0 EXIT THEN
    OVER _SMO.BACKING-U @ DUP 0> 0= IF
        2DROP DROP 0 EXIT
    THEN
    2DUP MSPAN-NONWRAPPING? 0= IF
        2DROP DROP 0 EXIT
    THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK <> IF DROP 0 EXIT THEN

    DUP _SMO.MODULES @ OVER _SMO.BACKING @ <> IF DROP 0 EXIT THEN
    DUP _SMO-EXPECTED-END
    OVER _SMO.BACKING @
    2 PICK _SMO.BACKING-U @ + <> IF
        DROP 0 EXIT
    THEN
    DUP _SMO.SCHEMA-WORK-U @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SMO.SCHEMA-WORK @ SBOX-SCHEMA-WORKSPACE-VALID? 0= IF
        DROP 0 EXIT
    THEN
    DUP _SMO.SCHEMA-WORK @
        SBOX-SCHEMA-WORKSPACE-MAX-DEPTH@
    OVER _SMO.SCHEMA-DEPTH @ <> IF DROP 0 EXIT THEN
    _SMO-RESERVED-OFF + 96 _SMO-ZERO? ;

: SBOX-MOWNER-INIT
  ( module-cap profile-cap schema-cap plan-cap schema-depth owner -- status )
    DUP _SMO-HEADER-ADMITTED? 0= IF
        2DROP 2DROP 2DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.MAGIC @ _SMO-MAGIC = IF
        2DROP 2DROP 2DROP SBOX-MOWNER-S-STATE EXIT
    THEN
    >R
    4 PICK 4 PICK 4 PICK 4 PICK 4 PICK
        SBOX-MOWNER-BACKING-MEASURE
    DUP IF
        >R DROP 2DROP 2DROP DROP R> R> DROP EXIT
    THEN
    DROP
    R@ SBOX-MOWNER-SIZE 0 FILL
    R@ _SMO.BACKING-U !
    R@ _SMO.SCHEMA-DEPTH !
    R@ _SMO.PLAN-CAP !
    R@ _SMO.SCHEMA-CAP !
    R@ _SMO.PROFILE-CAP !
    R@ _SMO.MODULE-CAP !

    R@ _SMO.BACKING-U @ ALLOCATE
    DUP IF
        2DROP
        R@ SBOX-MOWNER-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-NOMEM EXIT
    THEN
    DROP
    DUP R@ _SMO.BACKING !
    R@ _SMO.BACKING-U @ 0 FILL

    R@ _SMO.SCHEMA-DEPTH @ SBOX-SCHEMA-WORKSPACE-MEASURE
    DUP IF
        2DROP
        R@ _SMO.BACKING @ FREE
        R@ SBOX-MOWNER-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN
    DROP R@ _SMO.SCHEMA-WORK-U !
    R@ _SMO-POINTERS-BIND

    R@ _SMO.SCHEMA-DEPTH @
    R@ _SMO.SCHEMA-WORK @
    R@ _SMO.SCHEMA-WORK-U @
    SBOX-SCHEMA-WORKSPACE-INIT
    SBOX-SCHEMA-S-OK <> IF
        R@ _SMO.BACKING @ FREE
        R@ SBOX-MOWNER-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-PLATFORM EXIT
    THEN

    SBOX-VERIFIER-S-OK R@ _SMO.LAST-VERIFY-STATUS !
    SBOX-VERIFIER-D-NONE R@ _SMO.LAST-VERIFY-DETAIL !
    -1 R@ _SMO.LAST-VERIFY-INDEX !
    1 R@ _SMO.GENERATION !
    _SMO-STATE-READY R@ _SMO.STATE !
    R@ R@ _SMO.SELF !
    _SMO-MAGIC R@ _SMO.MAGIC !
    R@ SBOX-MOWNER-VALID? 0= IF
        R@ _SMO.BACKING @ FREE
        R@ SBOX-MOWNER-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-PLATFORM EXIT
    THEN
    R> DROP SBOX-MOWNER-S-OK ;

\ =====================================================================
\  Exact row searches
\ =====================================================================

: _SMO-PROFILE-FIND-DIGEST  ( digest owner -- row|0 )
    >R 0
    BEGIN DUP R@ _SMO.PROFILE-N @ < WHILE
        DUP R@ _SMO-PROFILE-ROW
        DUP _SMP.MAGIC @ _SMO-PROFILE-ROW-MAGIC = IF
            DUP _SMP.DIGEST 3 PICK _SMO-32= IF
                NIP NIP R> DROP EXIT
            THEN
        THEN
        DROP 1+
    REPEAT
    2DROP R> DROP 0 ;

: _SMO-PROFILE-FIND-EXACT  ( id id-u digest owner -- row|0 )
    >R
    DUP R@ _SMO-PROFILE-FIND-DIGEST
    DUP 0= IF
        DROP 2DROP DROP R> DROP 0 EXIT
    THEN
    >R DROP
    R@ _SMP.ID @ R@ _SMP.ID-U @
    3 PICK 3 PICK COMPARE 0= IF
        2DROP R> R> DROP EXIT
    THEN
    2DROP R> DROP R> DROP 0 ;

: _SMO-SCHEMA-FIND  ( digest owner -- row|0 )
    >R 0
    BEGIN DUP R@ _SMO.SCHEMA-N @ < WHILE
        DUP R@ _SMO-SCHEMA-ROW
        DUP _SMS.MAGIC @ _SMO-SCHEMA-ROW-MAGIC = IF
            DUP _SMS.DIGEST 3 PICK _SMO-32= IF
                NIP NIP R> DROP EXIT
            THEN
        THEN
        DROP 1+
    REPEAT
    2DROP R> DROP 0 ;

: _SMO-PLAN-FIND  ( artifact-digest profile-digest owner -- row|0 )
    >R 0
    BEGIN DUP R@ _SMO.PLAN-N @ < WHILE
        DUP R@ _SMO-PLAN-ROW
        DUP _SML.MAGIC @ _SMO-PLAN-ROW-MAGIC = IF
            DUP _SML.ARTIFACT-DIGEST 4 PICK _SMO-32=
            OVER _SML.PROFILE-DIGEST 4 PICK _SMO-32= AND IF
                2SWAP 2DROP NIP R> DROP EXIT
            THEN
        THEN
        DROP 1+
    REPEAT
    DROP 2DROP R> DROP 0 ;

: _SMO-MODULE-FIND-KEY
  ( owner-rid module-rid revision owner -- row|0 )
    >R 0
    BEGIN DUP R@ _SMO.MODULE-N @ < WHILE
        DUP R@ _SMO-MODULE-ROW
        DUP _SMM.MAGIC @ _SMO-MODULE-ROW-MAGIC = IF
            DUP _SMM.OWNER-RID 5 PICK RID=
            OVER _SMM.MODULE-RID 5 PICK RID= AND
            OVER _SMM.REVISION @ 4 PICK = AND IF
                >R DROP 2DROP DROP
                R> R> DROP EXIT
            THEN
        THEN
        DROP 1+
    REPEAT
    DROP 2DROP DROP R> DROP 0 ;

\ =====================================================================
\  Owned sealed-profile reconstruction
\ =====================================================================

: _SMO-PROFILE-CLONE  ( source destination owner -- status )
    >R
    R@ _SMO.S-Q !
    R@ _SMO.S-P !
    R@ _SMO.S-Q @ SBOX-PROFILE-INIT
    SBOX-PROFILE-S-OK <> IF
        R> DROP SBOX-MOWNER-S-PROFILE EXIT
    THEN
    R@ _SMO.S-P @ SBOX-PROFILE-TAG@
    DUP SBOX-PROFILE-S-OK <> IF
        2DROP R> DROP SBOX-MOWNER-S-PROFILE EXIT
    THEN
    DROP R@ _SMO.S-Q @ SBOX-PROFILE-TAG!
    SBOX-PROFILE-S-OK <> IF
        R> DROP SBOX-MOWNER-S-PROFILE EXIT
    THEN

    0 R@ _SMO.S-I !
    BEGIN
        R@ _SMO.S-I @ SBOX-PROFILE-LIMIT-FIELD-COUNT <
    WHILE
        R@ _SMO.S-I @ R@ _SMO.S-P @ SBOX-PROFILE-LIMIT@
        DUP SBOX-PROFILE-S-OK <> IF
            2DROP R> DROP SBOX-MOWNER-S-PROFILE EXIT
        THEN
        DROP
        R@ _SMO.S-I @ R@ _SMO.S-Q @ SBOX-PROFILE-LIMIT!
        SBOX-PROFILE-S-OK <> IF
            R> DROP SBOX-MOWNER-S-PROFILE EXIT
        THEN
        1 R@ _SMO.S-I +!
    REPEAT

    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ SBOX-PROFILE-OPCODE-CAPACITY < WHILE
        R@ _SMO.S-I @ R@ _SMO.S-P @
            SBOX-PROFILE-OPCODE-ENABLED?
        DUP SBOX-PROFILE-S-OK = IF
            DROP IF
                R@ _SMO.S-I @ R@ _SMO.S-Q @
                    SBOX-PROFILE-OPCODE-ENABLE
                SBOX-PROFILE-S-OK <> IF
                    R> DROP SBOX-MOWNER-S-PROFILE EXIT
                THEN
            THEN
        ELSE
            SBOX-PROFILE-S-OPCODE <> IF
                DROP R> DROP SBOX-MOWNER-S-PROFILE EXIT
            THEN
            DROP
        THEN
        1 R@ _SMO.S-I +!
    REPEAT

    R@ _SMO.S-Q @ SBOX-PROFILE-SEAL
    SBOX-PROFILE-S-OK =
    IF SBOX-MOWNER-S-OK ELSE SBOX-MOWNER-S-PROFILE THEN
    R> DROP ;

: _SMO-PROFILES-EQUAL?  ( a b owner -- flag )
    >R
    R@ _SMO.S-Q !
    R@ _SMO.S-P !
    R@ _SMO.S-P @ SBOX-PROFILE-TAG@
    DUP SBOX-PROFILE-S-OK <> IF
        2DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ _SMO.S-Q @ SBOX-PROFILE-TAG@
    DUP SBOX-PROFILE-S-OK <> IF
        2DROP R> DROP 0 EXIT
    THEN
    DROP <> IF R> DROP 0 EXIT THEN

    0 R@ _SMO.S-I !
    BEGIN
        R@ _SMO.S-I @ SBOX-PROFILE-LIMIT-FIELD-COUNT <
    WHILE
        R@ _SMO.S-I @ R@ _SMO.S-P @ SBOX-PROFILE-LIMIT@
        DUP SBOX-PROFILE-S-OK <> IF
            2DROP R> DROP 0 EXIT
        THEN
        DROP
        R@ _SMO.S-I @ R@ _SMO.S-Q @ SBOX-PROFILE-LIMIT@
        DUP SBOX-PROFILE-S-OK <> IF
            2DROP DROP R> DROP 0 EXIT
        THEN
        DROP <> IF R> DROP 0 EXIT THEN
        1 R@ _SMO.S-I +!
    REPEAT

    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ SBOX-PROFILE-OPCODE-CAPACITY < WHILE
        R@ _SMO.S-I @ R@ _SMO.S-P @
            SBOX-PROFILE-OPCODE-ENABLED?
        R@ _SMO.S-STATUS !
        R@ _SMO.S-X !
        R@ _SMO.S-I @ R@ _SMO.S-Q @
            SBOX-PROFILE-OPCODE-ENABLED?
        R@ _SMO.S-T !
        R@ _SMO.S-R !
        R@ _SMO.S-STATUS @ R@ _SMO.S-T @ <> IF
            R> DROP 0 EXIT
        THEN
        R@ _SMO.S-STATUS @ SBOX-PROFILE-S-OK = IF
            R@ _SMO.S-X @ R@ _SMO.S-R @ <> IF
                R> DROP 0 EXIT
            THEN
        ELSE
            R@ _SMO.S-STATUS @ SBOX-PROFILE-S-OPCODE <> IF
                R> DROP 0 EXIT
            THEN
        THEN
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP -1 ;

: _SMO-PROFILE-EXISTING-STATUS  ( row owner -- status )
    >R
    DUP _SMP.ID @ OVER _SMP.ID-U @
    R@ _SMO.S-A @ R@ _SMO.S-U @ COMPARE 0= 0= IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMP.DESCRIPTOR @ OVER _SMP.DESCRIPTOR-U @
    R@ _SMO.S-B @ R@ _SMO.S-V @ COMPARE 0= 0= IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    _SMP.PROFILE @ R@ _SMO.S-F @ R@
    _SMO-PROFILES-EQUAL? 0= IF
        R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-PROFILE-REGISTER-INTERNAL
  ( id id-u descriptor descriptor-u expected-digest sealed-profile owner
    -- status )
    >R
    R@ SBOX-MOWNER-VALID? 0= IF
        2DROP 2DROP 2DROP R> DROP SBOX-MOWNER-S-STATE EXIT
    THEN
    R@ _SMO.S-F !
    R@ _SMO.S-E !
    R@ _SMO.S-V !
    R@ _SMO.S-B !
    R@ _SMO.S-U !
    R@ _SMO.S-A !

    R@ _SMO.S-A @ R@ _SMO.S-U @ _SMO-PROFILE-ID? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-V @ DUP 0> 0=
    SWAP SBOX-MOWNER-PROFILE-BYTES-MAX > OR IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN
    R@ _SMO.S-B @ R@ _SMO.S-V @ _SMO-READ-SPAN-STATUS
    ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-E @ _SMO-DIGEST-PRESENT? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-F @ SBOX-PROFILE-VALID? 0= IF
        R> DROP SBOX-MOWNER-S-PROFILE EXIT
    THEN

    R@ _SMO.S-B @ R@ _SMO.S-V @
    R@ _SMO.TEMP-A R@ _SMO.DIGEST-WORK @
    SBOX-DIGEST-PROFILE
    SBOX-DIGEST-S-OK <> IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.TEMP-A R@ _SMO.S-E @ _SMO-32= 0= IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN

    R@ _SMO.TEMP-A R@ _SMO-PROFILE-FIND-DIGEST
    ?DUP IF
        R@ _SMO-PROFILE-EXISTING-STATUS
        R> DROP EXIT
    THEN
    R@ _SMO.PROFILE-N @ R@ _SMO.PROFILE-CAP @ >= IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN

    R@ _SMO.S-U @ R@ _SMO.S-V @ +
    DUP R@ _SMO.S-SIZE !
    ALLOCATE
    DUP IF
        2DROP R> DROP SBOX-MOWNER-S-NOMEM EXIT
    THEN
    DROP R@ _SMO.S-PTR !
    R@ _SMO.S-A @ R@ _SMO.S-PTR @ R@ _SMO.S-U @ MOVE
    R@ _SMO.S-B @
    R@ _SMO.S-PTR @ R@ _SMO.S-U @ +
    R@ _SMO.S-V @ MOVE
    R@ _SMO.S-PTR @ R@ _SMO.S-U @ +
    R@ _SMO.S-V @
    R@ _SMO.TEMP-B R@ _SMO.DIGEST-WORK @
    SBOX-DIGEST-PROFILE
    SBOX-DIGEST-S-OK <> IF
        R@ _SMO.S-PTR @ FREE
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.TEMP-B R@ _SMO.TEMP-A _SMO-32= 0= IF
        R@ _SMO.S-PTR @ FREE
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN

    SBOX-PROFILE-SIZE ALLOCATE
    DUP IF
        2DROP R@ _SMO.S-PTR @ FREE
        R> DROP SBOX-MOWNER-S-NOMEM EXIT
    THEN
    DROP R@ _SMO.S-Q !
    R@ _SMO.S-F @ R@ _SMO.S-Q @ R@
    _SMO-PROFILE-CLONE DUP IF
        R@ _SMO.S-STATUS !
        R@ _SMO.S-Q @ FREE
        R@ _SMO.S-PTR @ FREE
        R@ _SMO.S-STATUS @ R> DROP EXIT
    THEN
    DROP

    R@ _SMO.PROFILE-N @ R@ _SMO-PROFILE-ROW
    DUP R@ _SMO.S-ROW !
    _SMO-PROFILE-ROW-SIZE 0 FILL
    R@ _SMO.S-PTR @ R@ _SMO.S-ROW @ _SMP.BLOB !
    R@ _SMO.S-PTR @ R@ _SMO.S-ROW @ _SMP.ID !
    R@ _SMO.S-U @ R@ _SMO.S-ROW @ _SMP.ID-U !
    R@ _SMO.S-PTR @ R@ _SMO.S-U @ +
        R@ _SMO.S-ROW @ _SMP.DESCRIPTOR !
    R@ _SMO.S-V @ R@ _SMO.S-ROW @ _SMP.DESCRIPTOR-U !
    R@ _SMO.TEMP-A R@ _SMO.S-ROW @ _SMP.DIGEST
        SBOX-DIGEST-SIZE MOVE
    R@ _SMO.S-Q @ R@ _SMO.S-ROW @ _SMP.PROFILE !
    _SMO-PROFILE-ROW-MAGIC R@ _SMO.S-ROW @ _SMP.MAGIC !
    1 R@ _SMO.PROFILE-N +!
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-PROFILE-REGISTER-LOCKED
  ( id id-u descriptor descriptor-u expected-digest sealed-profile owner
    -- status )
    DUP >R _SMO-PROFILE-REGISTER-INTERNAL
    R@ _SMO-SCRATCH-CLEAR R> DROP ;

: SBOX-MOWNER-PROFILE-REGISTER
  ( id id-u descriptor descriptor-u expected-digest sealed-profile owner
    -- status )
    DUP SBOX-MOWNER-VALID? 0= IF
        2DROP 2DROP 2DROP DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.GUARD >R
    ['] _SMO-PROFILE-REGISTER-LOCKED R> WITH-GUARD ;

\ =====================================================================
\  Canonical schema registry
\ =====================================================================

: _SMO-SCHEMA-EXISTING-STATUS  ( row owner -- status )
    >R
    DUP _SMS.BYTES-U @ R@ _SMO.S-U @ <> IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    _SMS.BYTES @ R@ _SMO.S-A @ R@ _SMO.S-U @
    COMPARE 0=
    IF SBOX-MOWNER-S-OK ELSE SBOX-MOWNER-S-CONFLICT THEN
    R> DROP ;

: _SMO-SCHEMA-REGISTER-INTERNAL
  ( schema schema-u expected-digest owner -- status )
    >R
    R@ SBOX-MOWNER-VALID? 0= IF
        2DROP DROP R> DROP SBOX-MOWNER-S-STATE EXIT
    THEN
    R@ _SMO.S-E !
    R@ _SMO.S-U !
    R@ _SMO.S-A !
    R@ _SMO.S-U @ DUP 0> 0=
    SWAP SBOX-DECL-ONE-SCHEMA-MAX > OR IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN
    R@ _SMO.S-A @ R@ _SMO.S-U @ _SMO-READ-SPAN-STATUS
    ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-E @ _SMO-DIGEST-PRESENT? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN

    R@ _SMO.S-A @ R@ _SMO.S-U @
    R@ _SMO.TEMP-A R@ _SMO.DIGEST-WORK @
    SBOX-DIGEST-SCHEMA
    SBOX-DIGEST-S-OK <> IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.TEMP-A R@ _SMO.S-E @ _SMO-32= 0= IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.S-A @ R@ _SMO.S-U @ R@ _SMO.SCHEMA-WORK @
    SBOX-SCHEMA-VALIDATE
    SBOX-SCHEMA-S-OK <> IF
        R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN

    R@ _SMO.TEMP-A R@ _SMO-SCHEMA-FIND
    ?DUP IF
        R@ _SMO-SCHEMA-EXISTING-STATUS
        R> DROP EXIT
    THEN
    R@ _SMO.SCHEMA-N @ R@ _SMO.SCHEMA-CAP @ >= IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN

    R@ _SMO.S-U @ ALLOCATE
    DUP IF
        2DROP R> DROP SBOX-MOWNER-S-NOMEM EXIT
    THEN
    DROP R@ _SMO.S-PTR !
    R@ _SMO.S-A @ R@ _SMO.S-PTR @ R@ _SMO.S-U @ MOVE
    R@ _SMO.S-PTR @ R@ _SMO.S-U @ R@ _SMO.SCHEMA-WORK @
    SBOX-SCHEMA-VALIDATE
    SBOX-SCHEMA-S-OK <> IF
        R@ _SMO.S-PTR @ FREE
        R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN
    R@ _SMO.S-PTR @ R@ _SMO.S-U @
    R@ _SMO.TEMP-B R@ _SMO.DIGEST-WORK @
    SBOX-DIGEST-SCHEMA
    SBOX-DIGEST-S-OK <> IF
        R@ _SMO.S-PTR @ FREE
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.TEMP-B R@ _SMO.TEMP-A _SMO-32= 0= IF
        R@ _SMO.S-PTR @ FREE
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN

    R@ _SMO.SCHEMA-N @ R@ _SMO-SCHEMA-ROW
    DUP R@ _SMO.S-ROW !
    _SMO-SCHEMA-ROW-SIZE 0 FILL
    R@ _SMO.S-PTR @ R@ _SMO.S-ROW @ _SMS.BYTES !
    R@ _SMO.S-U @ R@ _SMO.S-ROW @ _SMS.BYTES-U !
    R@ _SMO.TEMP-A R@ _SMO.S-ROW @ _SMS.DIGEST
        SBOX-DIGEST-SIZE MOVE
    _SMO-SCHEMA-ROW-MAGIC R@ _SMO.S-ROW @ _SMS.MAGIC !
    1 R@ _SMO.SCHEMA-N +!
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-SCHEMA-REGISTER-LOCKED
  ( schema schema-u expected-digest owner -- status )
    DUP >R _SMO-SCHEMA-REGISTER-INTERNAL
    R@ _SMO-SCRATCH-CLEAR R> DROP ;

: SBOX-MOWNER-SCHEMA-REGISTER
  ( schema schema-u expected-digest owner -- status )
    DUP SBOX-MOWNER-VALID? 0= IF
        2DROP 2DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.GUARD >R
    ['] _SMO-SCHEMA-REGISTER-LOCKED R> WITH-GUARD ;

\ =====================================================================
\  Module-install validation and independently verified plan caching
\ =====================================================================

: _SMO-RESOLVE-DECL-PROFILE  ( owner -- status )
    >R
    R@ _SMO.DECL-VIEW @ SBOX-DECL-PROFILE-ID@
    DUP SBOX-DECL-S-OK <> IF
        2DROP DROP R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP
    R@ _SMO.S-W !
    R@ _SMO.S-C !
    R@ _SMO.DECL-VIEW @ SBOX-DECL-PROFILE-DIGEST@
    DUP SBOX-DECL-S-OK <> IF
        2DROP R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO.S-D !
    R@ _SMO.S-C @ R@ _SMO.S-W @ R@ _SMO.S-D @ R@
    _SMO-PROFILE-FIND-EXACT
    DUP 0= IF
        DROP R> DROP SBOX-MOWNER-S-NOT-FOUND EXIT
    THEN
    DUP _SMP.MAGIC @ _SMO-PROFILE-ROW-MAGIC <> IF
        DROP R> DROP SBOX-MOWNER-S-PROFILE EXIT
    THEN
    R@ _SMO.S-OTHER !
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-CHECK-ONE-SCHEMA
  ( bytes schema-u digest storage owner -- status )
    >R
    R@ _SMO.S-X !
    R@ _SMO.S-D !
    R@ _SMO.S-W !
    R@ _SMO.S-C !

    R@ _SMO.S-W @ DUP 0> 0=
    SWAP SBOX-DECL-ONE-SCHEMA-MAX > OR IF
        R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN
    R@ _SMO.S-D @ _SMO-DIGEST-PRESENT? 0= IF
        R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN

    R@ _SMO.S-X @ SBOX-DECL-SCHEMA-EMBEDDED = IF
        R@ _SMO.S-C @ 0= IF
            R> DROP SBOX-MOWNER-S-SCHEMA EXIT
        THEN
        R@ _SMO.S-C @ R@ _SMO.S-W @
        R@ _SMO.SCHEMA-WORK @ SBOX-SCHEMA-VALIDATE
        SBOX-SCHEMA-S-OK <> IF
            R> DROP SBOX-MOWNER-S-SCHEMA EXIT
        THEN
        R@ _SMO.S-C @ R@ _SMO.S-W @
        R@ _SMO.TEMP-C R@ _SMO.DIGEST-WORK @
        SBOX-DIGEST-SCHEMA
        SBOX-DIGEST-S-OK <> IF
            R> DROP SBOX-MOWNER-S-DIGEST EXIT
        THEN
        R@ _SMO.TEMP-C R@ _SMO.S-D @ _SMO-32=
        IF SBOX-MOWNER-S-OK ELSE SBOX-MOWNER-S-DIGEST THEN
        R> DROP EXIT
    THEN

    R@ _SMO.S-X @ SBOX-DECL-SCHEMA-REFERENCED <> IF
        R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN
    R@ _SMO.S-C @ IF
        R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN
    R@ _SMO.S-D @ R@ _SMO-SCHEMA-FIND
    DUP 0= IF
        DROP R> DROP SBOX-MOWNER-S-NOT-FOUND EXIT
    THEN
    DUP _SMS.MAGIC @ _SMO-SCHEMA-ROW-MAGIC <> IF
        DROP R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN
    DUP _SMS.BYTES-U @ R@ _SMO.S-W @ <> IF
        DROP R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN
    DUP _SMS.BYTES @ OVER _SMS.BYTES-U @
    R@ _SMO.SCHEMA-WORK @ SBOX-SCHEMA-VALIDATE
    SBOX-SCHEMA-S-OK <> IF
        DROP R> DROP SBOX-MOWNER-S-SCHEMA EXIT
    THEN
    DROP R> DROP SBOX-MOWNER-S-OK ;

: _SMO-CHECK-ENTRY-SCHEMAS  ( entry owner -- status )
    >R
    DUP R@ _SMO.DECL-VIEW @
        SBOX-DECL-ENTRY-INPUT-SCHEMA@
    DUP SBOX-DECL-S-OK <> IF
        DROP 2DROP 2DROP DROP
        R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO-CHECK-ONE-SCHEMA
    ?DUP IF
        >R DROP R> R> DROP EXIT
    THEN

    R@ _SMO.DECL-VIEW @
        SBOX-DECL-ENTRY-OUTPUT-SCHEMA@
    DUP SBOX-DECL-S-OK <> IF
        DROP 2DROP 2DROP
        R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO-CHECK-ONE-SCHEMA
    R> DROP ;

: _SMO-CHECK-ENTRIES  ( plan owner -- status )
    >R
    R@ _SMO.S-PLAN !
    R@ _SMO.S-PLAN @ SBOX-PLAN-VALID? 0= IF
        R> DROP SBOX-MOWNER-S-VERIFY EXIT
    THEN
    R@ _SMO.DECL-VIEW @ SBOX-DECL-ENTRY-COUNT@
    DUP SBOX-DECL-S-OK <> IF
        2DROP R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO.S-SIZE !
    R@ _SMO.S-PLAN @ SBOX-PLAN-ENTRY-N@
    R@ _SMO.S-SIZE @ <> IF
        R> DROP SBOX-MOWNER-S-ENTRY EXIT
    THEN

    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.S-SIZE @ < WHILE
        R@ _SMO.S-I @ R@ _SMO.DECL-VIEW @ SBOX-DECL-ENTRY@
        DUP SBOX-DECL-S-OK <> IF
            2DROP R> DROP SBOX-MOWNER-S-DECLARATION EXIT
        THEN
        DROP R@ _SMO.S-ENTRY !

        R@ _SMO.S-ENTRY @ R@ _SMO.DECL-VIEW @
            SBOX-DECL-ENTRY-NAME@
        DUP SBOX-DECL-S-OK <> IF
            2DROP DROP R> DROP SBOX-MOWNER-S-DECLARATION EXIT
        THEN
        DROP R@ _SMO.S-W ! R@ _SMO.S-C !
        R@ _SMO.S-I @ R@ _SMO.S-PLAN @ SBOX-PLAN-ENTRY-NAME$
        DUP 0= 2 PICK 0= OR IF
            2DROP R> DROP SBOX-MOWNER-S-ENTRY EXIT
        THEN
        R@ _SMO.S-C @ R@ _SMO.S-W @ COMPARE IF
            R> DROP SBOX-MOWNER-S-ENTRY EXIT
        THEN

        R@ _SMO.S-ENTRY @ R@ _SMO.DECL-VIEW @
            SBOX-DECL-ENTRY-SIGNATURE@
        DUP SBOX-DECL-S-OK <> IF
            2DROP R> DROP SBOX-MOWNER-S-DECLARATION EXIT
        THEN
        DROP R@ _SMO.S-X !
        R@ _SMO.S-I @ R@ _SMO.S-PLAN @
            SBOX-PLAN-ENTRY-SIGNATURE@
        0= IF
            DROP R> DROP SBOX-MOWNER-S-ENTRY EXIT
        THEN
        R@ _SMO.S-X @ <> IF
            R> DROP SBOX-MOWNER-S-ENTRY EXIT
        THEN

        R@ _SMO.S-ENTRY @ R@ _SMO-CHECK-ENTRY-SCHEMAS
        ?DUP IF R> DROP EXIT THEN
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-CAPTURE-VERIFY  ( verifier-status owner -- )
    >R
    DUP R@ _SMO.LAST-VERIFY-STATUS !
    DROP
    R@ _SMO.VERIFIER-WORK @ SBOX-VERIFIER-ERROR-DETAIL@
    DUP SBOX-VERIFIER-S-OK = IF
        DROP R@ _SMO.LAST-VERIFY-DETAIL !
    ELSE
        2DROP SBOX-VERIFIER-D-INTERNAL
            R@ _SMO.LAST-VERIFY-DETAIL !
    THEN
    R@ _SMO.VERIFIER-WORK @ SBOX-VERIFIER-ERROR-INDEX@
    DUP SBOX-VERIFIER-S-OK = IF
        DROP R@ _SMO.LAST-VERIFY-INDEX !
    ELSE
        2DROP -1 R@ _SMO.LAST-VERIFY-INDEX !
    THEN
    R> DROP ;

: _SMO-PLAN-PREPARE  ( profile-row owner -- status )
    >R
    R@ _SMO.S-OTHER !
    0 R@ _SMO.S-T !
    0 R@ _SMO.S-PLAN !
    0 R@ _SMO.S-ROW !
    0 R@ _SMO.S-R !

    R@ _SMO.TEMP-B
    R@ _SMO.S-OTHER @ _SMP.DIGEST
    R@ _SMO-PLAN-FIND
    ?DUP IF
        DUP _SML.MAGIC @ _SMO-PLAN-ROW-MAGIC <> IF
            DROP R> DROP SBOX-MOWNER-S-VERIFY EXIT
        THEN
        DUP _SML.PROFILE-ROW @ R@ _SMO.S-OTHER @ <> IF
            DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
        THEN
        DUP _SML.PLAN @ DUP SBOX-PLAN-VALID? 0= IF
            2DROP R> DROP SBOX-MOWNER-S-VERIFY EXIT
        THEN
        DUP SBOX-PLAN-CANDIDATE$
        R@ _SMO.S-B @ R@ _SMO.S-V @ COMPARE 0= 0= IF
            2DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
        THEN
        R@ _SMO.S-PLAN !
        R@ _SMO.S-ROW !
        R> DROP SBOX-MOWNER-S-OK EXIT
    THEN

    R@ _SMO.PLAN-N @ R@ _SMO.PLAN-CAP @ >= IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN
    R@ _SMO.S-V @ SBOX-PLAN-MEASURE
    DUP IF
        2DROP R> DROP SBOX-MOWNER-S-ARTIFACT EXIT
    THEN
    DROP DUP R@ _SMO.S-R !
    ALLOCATE
    DUP IF
        2DROP R> DROP SBOX-MOWNER-S-NOMEM EXIT
    THEN
    DROP R@ _SMO.S-PLAN !

    R@ _SMO.S-B @ R@ _SMO.S-V @
    R@ _SMO.S-OTHER @ _SMP.PROFILE @
    R@ _SMO.S-PLAN @ R@ _SMO.S-R @
    R@ _SMO.VERIFIER-WORK @
    SBOX-VERIFY
    DUP R@ _SMO-CAPTURE-VERIFY
    SBOX-VERIFIER-S-OK <> IF
        R@ _SMO.S-PLAN @ FREE
        0 R@ _SMO.S-PLAN !
        R> DROP SBOX-MOWNER-S-VERIFY EXIT
    THEN
    R@ _SMO.S-PLAN @ SBOX-PLAN-VALID? 0= IF
        R@ _SMO.S-PLAN @ FREE
        0 R@ _SMO.S-PLAN !
        R> DROP SBOX-MOWNER-S-VERIFY EXIT
    THEN
    R@ _SMO.PLAN-N @ R@ _SMO-PLAN-ROW R@ _SMO.S-ROW !
    -1 R@ _SMO.S-T !
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-PLAN-ROLLBACK  ( owner -- )
    DUP _SMO.S-T @ IF
        DUP _SMO.S-PLAN @ ?DUP IF FREE THEN
    THEN
    0 OVER _SMO.S-PLAN !
    0 OVER _SMO.S-ROW !
    0 OVER _SMO.S-T !
    DROP ;

: _SMO-PLAN-PUBLISH  ( owner -- )
    DUP _SMO.S-T @ 0= IF DROP EXIT THEN
    >R
    R@ _SMO.S-ROW @ DUP _SMO-PLAN-ROW-SIZE 0 FILL
    R@ _SMO.TEMP-B OVER _SML.ARTIFACT-DIGEST
        SBOX-DIGEST-SIZE MOVE
    R@ _SMO.S-OTHER @ _SMP.DIGEST
        OVER _SML.PROFILE-DIGEST SBOX-DIGEST-SIZE MOVE
    R@ _SMO.S-PLAN @ OVER _SML.PLAN !
    R@ _SMO.S-R @ OVER _SML.PLAN-U !
    R@ _SMO.S-OTHER @ OVER _SML.PROFILE-ROW !
    _SMO-PLAN-ROW-MAGIC SWAP _SML.MAGIC !
    1 R@ _SMO.PLAN-N +!
    0 R@ _SMO.S-T !
    R> DROP ;

: _SMO-MODULE-KEY-FIND  ( owner -- row|0 status )
    >R
    R@ _SMO.DECL-VIEW @ SBOX-DECL-OWNER-RID@
    DUP SBOX-DECL-S-OK <> IF
        2DROP R> DROP 0 SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO.S-C !
    R@ _SMO.DECL-VIEW @ SBOX-DECL-MODULE-RID@
    DUP SBOX-DECL-S-OK <> IF
        2DROP R> DROP 0 SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO.S-D !
    R@ _SMO.DECL-VIEW @ SBOX-DECL-MODULE-REVISION@
    DUP SBOX-DECL-S-OK <> IF
        2DROP R> DROP 0 SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO.S-X !
    R@ _SMO.S-C @ R@ _SMO.S-D @ R@ _SMO.S-X @ R@
    _SMO-MODULE-FIND-KEY SBOX-MOWNER-S-OK
    R> DROP ;

: _SMO-EXISTING-MODULE-STATUS  ( row owner -- status )
    >R
    DUP _SMM.DECLARATION-DIGEST R@ _SMO.TEMP-A _SMO-32= 0= IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMM.ARTIFACT-DIGEST R@ _SMO.TEMP-B _SMO-32= 0= IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMM.PROFILE-ROW @ R@ _SMO.S-OTHER @ <> IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMM.DECLARATION-U @ R@ _SMO.S-U @ <> IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMM.DECLARATION @ R@ _SMO.S-A @ R@ _SMO.S-U @
        COMPARE IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMM.ARTIFACT-U @ R@ _SMO.S-V @ <> IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMM.ARTIFACT @ R@ _SMO.S-B @ R@ _SMO.S-V @
        COMPARE IF
        DROP R> DROP SBOX-MOWNER-S-CONFLICT EXIT
    THEN
    DUP _SMM.PLAN-ROW @ DUP _SML.MAGIC @
        _SMO-PLAN-ROW-MAGIC <> IF
        2DROP R> DROP SBOX-MOWNER-S-VERIFY EXIT
    THEN
    _SML.PLAN @ R@ _SMO-CHECK-ENTRIES
    NIP R> DROP ;

: _SMO-MODULE-PUBLISH  ( owner -- )
    >R
    R@ _SMO.MODULE-N @ R@ _SMO-MODULE-ROW
    DUP R@ _SMO.S-ROW !
    _SMO-MODULE-ROW-SIZE 0 FILL
    R@ _SMO.S-P @ R@ _SMO.S-ROW @ _SMM.DECLARATION !
    R@ _SMO.S-U @ R@ _SMO.S-ROW @ _SMM.DECLARATION-U !
    R@ _SMO.S-Q @ R@ _SMO.S-ROW @ _SMM.ARTIFACT !
    R@ _SMO.S-V @ R@ _SMO.S-ROW @ _SMM.ARTIFACT-U !

    R@ _SMO.DECL-VIEW @ SBOX-DECL-OWNER-RID@ DROP
    R@ _SMO.S-ROW @ _SMM.OWNER-RID RID-COPY
    R@ _SMO.DECL-VIEW @ SBOX-DECL-MODULE-RID@ DROP
    R@ _SMO.S-ROW @ _SMM.MODULE-RID RID-COPY
    R@ _SMO.DECL-VIEW @ SBOX-DECL-MODULE-REVISION@ DROP
    R@ _SMO.S-ROW @ _SMM.REVISION !
    R@ _SMO.TEMP-A
    R@ _SMO.S-ROW @ _SMM.DECLARATION-DIGEST
        SBOX-DIGEST-SIZE MOVE
    R@ _SMO.TEMP-B
    R@ _SMO.S-ROW @ _SMM.ARTIFACT-DIGEST
        SBOX-DIGEST-SIZE MOVE
    R@ _SMO.S-OTHER @ R@ _SMO.S-ROW @ _SMM.PROFILE-ROW !
    R@ _SMO.S-PLAN @ R@ _SMO.S-ROW @ _SMM.PLAN-ROW !
    R@ _SMO.DECL-VIEW @ SBOX-DECL-ENTRY-COUNT@ DROP
    R@ _SMO.S-ROW @ _SMM.ENTRY-N !
    _SMO-MODULE-ROW-MAGIC R@ _SMO.S-ROW @ _SMM.MAGIC !

    1 R@ _SMO.S-OTHER @ _SMP.MODULE-REFS +!
    1 R@ _SMO.S-PLAN @ _SML.MODULE-REFS +!
    1 R@ _SMO.MODULE-N +!
    R> DROP ;

: _SMO-MODULE-INSTALL-INTERNAL
  ( declaration declaration-u declaration-digest artifact artifact-u owner
    -- status )
    >R
    R@ SBOX-MOWNER-VALID? 0= IF
        2DROP 2DROP DROP R> DROP SBOX-MOWNER-S-STATE EXIT
    THEN
    R@ _SMO.S-V !
    R@ _SMO.S-B !
    R@ _SMO.S-E !
    R@ _SMO.S-U !
    R@ _SMO.S-A !

    R@ _SMO.S-U @ DUP SBOX-DECL-HEADER-SIZE <
    SWAP SBOX-DECL-BYTES-MAX > OR IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN
    R@ _SMO.S-A @ R@ _SMO.S-U @ _SMO-READ-SPAN-STATUS
    ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-E @ _SMO-DIGEST-PRESENT? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-V @ DUP SBOX-CANDIDATE-HEADER-SIZE <
    SWAP SBOX-VERIFIER-CANDIDATE-MAX-SIZE > OR IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN
    R@ _SMO.S-B @ R@ _SMO.S-V @ _SMO-READ-SPAN-STATUS
    ?DUP IF R> DROP EXIT THEN

    R@ _SMO.S-A @ R@ _SMO.S-U @
    R@ _SMO.DECL-VIEW @ R@ _SMO.DIGEST-WORK @
    SBOX-DECL-VALIDATE
    SBOX-DECL-S-OK <> IF
        R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    R@ _SMO.S-A @ R@ _SMO.S-U @
    R@ _SMO.TEMP-A R@ _SMO.DIGEST-WORK @
    SBOX-DECL-DIGEST
    SBOX-DECL-S-OK <> IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.TEMP-A R@ _SMO.S-E @ _SMO-32= 0= IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN

    R@ _SMO.S-B @ R@ _SMO.S-V @
    R@ _SMO.TEMP-B R@ _SMO.DIGEST-WORK @
    SBOX-DIGEST-ARTIFACT
    SBOX-DIGEST-S-OK <> IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.DECL-VIEW @ SBOX-DECL-ARTIFACT-DIGEST@
    DUP SBOX-DECL-S-OK <> IF
        2DROP R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP R@ _SMO.TEMP-B SWAP _SMO-32= 0= IF
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN

    R@ _SMO-RESOLVE-DECL-PROFILE ?DUP IF
        R> DROP EXIT
    THEN
    R@ _SMO-MODULE-KEY-FIND
    DUP IF
        >R DROP R> R> DROP EXIT
    THEN
    DROP
    ?DUP IF
        R@ _SMO-EXISTING-MODULE-STATUS
        R> DROP EXIT
    THEN
    R@ _SMO.MODULE-N @ R@ _SMO.MODULE-CAP @ >= IF
        R> DROP SBOX-MOWNER-S-CAPACITY EXIT
    THEN

    R@ _SMO.S-OTHER @ R@ _SMO-PLAN-PREPARE
    ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-PLAN @ R@ _SMO-CHECK-ENTRIES
    ?DUP IF
        R@ _SMO-PLAN-ROLLBACK R> DROP EXIT
    THEN

    R@ _SMO.S-U @ ALLOCATE
    DUP IF
        2DROP R@ _SMO-PLAN-ROLLBACK
        R> DROP SBOX-MOWNER-S-NOMEM EXIT
    THEN
    DROP R@ _SMO.S-P !
    R@ _SMO.S-A @ R@ _SMO.S-P @ R@ _SMO.S-U @ MOVE

    R@ _SMO.S-V @ ALLOCATE
    DUP IF
        2DROP R@ _SMO.S-P @ FREE
        R@ _SMO-PLAN-ROLLBACK
        R> DROP SBOX-MOWNER-S-NOMEM EXIT
    THEN
    DROP R@ _SMO.S-Q !
    R@ _SMO.S-B @ R@ _SMO.S-Q @ R@ _SMO.S-V @ MOVE

    \ Recompute both owned copies before publishing either row.
    R@ _SMO.S-P @ R@ _SMO.S-U @
    R@ _SMO.TEMP-C R@ _SMO.DIGEST-WORK @
    SBOX-DECL-DIGEST
    SBOX-DECL-S-OK <> IF
        R@ _SMO.S-Q @ FREE R@ _SMO.S-P @ FREE
        R@ _SMO-PLAN-ROLLBACK
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.TEMP-C R@ _SMO.TEMP-A _SMO-32= 0= IF
        R@ _SMO.S-Q @ FREE R@ _SMO.S-P @ FREE
        R@ _SMO-PLAN-ROLLBACK
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.S-Q @ R@ _SMO.S-V @
    R@ _SMO.TEMP-C R@ _SMO.DIGEST-WORK @
    SBOX-DIGEST-ARTIFACT
    SBOX-DIGEST-S-OK <> IF
        R@ _SMO.S-Q @ FREE R@ _SMO.S-P @ FREE
        R@ _SMO-PLAN-ROLLBACK
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN
    R@ _SMO.TEMP-C R@ _SMO.TEMP-B _SMO-32= 0= IF
        R@ _SMO.S-Q @ FREE R@ _SMO.S-P @ FREE
        R@ _SMO-PLAN-ROLLBACK
        R> DROP SBOX-MOWNER-S-DIGEST EXIT
    THEN

    \ Revalidate the owned declaration before publishing either row.
    R@ _SMO.S-P @ R@ _SMO.S-U @
    R@ _SMO.DECL-VIEW @ R@ _SMO.DIGEST-WORK @
    SBOX-DECL-VALIDATE
    SBOX-DECL-S-OK <> IF
        R@ _SMO.S-Q @ FREE R@ _SMO.S-P @ FREE
        R@ _SMO-PLAN-ROLLBACK
        R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    R@ _SMO.S-PLAN @ R@ _SMO-CHECK-ENTRIES
    ?DUP IF
        R@ _SMO.S-Q @ FREE R@ _SMO.S-P @ FREE
        R@ _SMO-PLAN-ROLLBACK
        R> DROP EXIT
    THEN

    R@ _SMO-PLAN-PUBLISH
    \ _SMO-MODULE-PUBLISH expects the plan row, not the plan object.
    R@ _SMO.S-ROW @ R@ _SMO.S-PLAN !
    R@ _SMO-MODULE-PUBLISH
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-MODULE-INSTALL-LOCKED
  ( declaration declaration-u declaration-digest artifact artifact-u owner
    -- status )
    DUP >R _SMO-MODULE-INSTALL-INTERNAL
    R@ _SMO-SCRATCH-CLEAR R> DROP ;

: SBOX-MOWNER-MODULE-INSTALL
  ( declaration declaration-u declaration-digest artifact artifact-u owner
    -- status )
    DUP SBOX-MOWNER-VALID? 0= IF
        2DROP 2DROP 2DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.GUARD >R
    ['] _SMO-MODULE-INSTALL-LOCKED R> WITH-GUARD ;

\ =====================================================================
\  Caller-owned exact entry leases
\ =====================================================================

0x314553414C584253 CONSTANT _SMO-LEASE-MAGIC  \ "SBXLEASE1"

  0 CONSTANT _SLE-MAGIC
  8 CONSTANT _SLE-SELF
 16 CONSTANT _SLE-OWNER
 24 CONSTANT _SLE-MODULE-ROW
 32 CONSTANT _SLE-PLAN-ROW
 40 CONSTANT _SLE-PROFILE-ROW
 48 CONSTANT _SLE-ENTRY-INDEX
 56 CONSTANT _SLE-ENTRY
 64 CONSTANT _SLE-INPUT
 72 CONSTANT _SLE-INPUT-U
 80 CONSTANT _SLE-OUTPUT
 88 CONSTANT _SLE-OUTPUT-U
 96 CONSTANT _SLE-INPUT-DIGEST
128 CONSTANT _SLE-OUTPUT-DIGEST
160 CONSTANT _SLE-DECL-VIEW
336 CONSTANT _SLE-RESERVED
352 CONSTANT SBOX-MLEASE-SIZE

: _SLE.MAGIC          ( lease -- a ) _SLE-MAGIC + ;
: _SLE.SELF           ( lease -- a ) _SLE-SELF + ;
: _SLE.OWNER          ( lease -- a ) _SLE-OWNER + ;
: _SLE.MODULE-ROW     ( lease -- a ) _SLE-MODULE-ROW + ;
: _SLE.PLAN-ROW       ( lease -- a ) _SLE-PLAN-ROW + ;
: _SLE.PROFILE-ROW    ( lease -- a ) _SLE-PROFILE-ROW + ;
: _SLE.ENTRY-INDEX    ( lease -- a ) _SLE-ENTRY-INDEX + ;
: _SLE.ENTRY          ( lease -- a ) _SLE-ENTRY + ;
: _SLE.INPUT          ( lease -- a ) _SLE-INPUT + ;
: _SLE.INPUT-U        ( lease -- a ) _SLE-INPUT-U + ;
: _SLE.OUTPUT         ( lease -- a ) _SLE-OUTPUT + ;
: _SLE.OUTPUT-U       ( lease -- a ) _SLE-OUTPUT-U + ;
: _SLE.INPUT-DIGEST   ( lease -- digest ) _SLE-INPUT-DIGEST + ;
: _SLE.OUTPUT-DIGEST  ( lease -- digest ) _SLE-OUTPUT-DIGEST + ;
: _SLE.DECL-VIEW      ( lease -- view ) _SLE-DECL-VIEW + ;

: _SMO-PROFILE-ROW-BELONGS?  ( row owner -- flag )
    >R
    DUP R@ _SMO.PROFILES @ U< IF
        DROP R> DROP 0 EXIT
    THEN
    DUP R@ _SMO.PROFILES @ -
    R@ _SMO.PROFILE-N @ _SMO-PROFILE-ROW-SIZE * U>= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ _SMO.PROFILES @ -
    _SMO-PROFILE-ROW-SIZE MOD 0=
    R> DROP ;

: _SMO-PLAN-ROW-BELONGS?  ( row owner -- flag )
    >R
    DUP R@ _SMO.PLANS @ U< IF
        DROP R> DROP 0 EXIT
    THEN
    DUP R@ _SMO.PLANS @ -
    R@ _SMO.PLAN-N @ _SMO-PLAN-ROW-SIZE * U>= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ _SMO.PLANS @ -
    _SMO-PLAN-ROW-SIZE MOD 0=
    R> DROP ;

: _SMO-MODULE-ROW-BELONGS?  ( row owner -- flag )
    >R
    DUP R@ _SMO.MODULES @ U< IF
        DROP R> DROP 0 EXIT
    THEN
    DUP R@ _SMO.MODULES @ -
    R@ _SMO.MODULE-N @ _SMO-MODULE-ROW-SIZE * U>= IF
        DROP R> DROP 0 EXIT
    THEN
    R@ _SMO.MODULES @ -
    _SMO-MODULE-ROW-SIZE MOD 0=
    R> DROP ;

: _SMO-LEASE-HEADER?  ( lease -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBOX-MLEASE-SIZE MSPAN-NONWRAPPING? 0= IF DROP 0 EXIT THEN
    SBOX-MLEASE-SIZE CALLER-SPAN-STATUS
        CALLER-SPAN-S-OK = ;

: SBOX-MLEASE-VALID?  ( lease -- flag )
    DUP _SMO-LEASE-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _SLE.MAGIC @ _SMO-LEASE-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SLE.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SLE.OWNER @ DUP SBOX-MOWNER-VALID? 0= IF
        2DROP 0 EXIT
    THEN
    >R
    R@ _SMO.LEASE-N @ 0> 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.MODULE-ROW @ DUP R@ _SMO-MODULE-ROW-BELONGS? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP _SMM.MAGIC @ _SMO-MODULE-ROW-MAGIC <> IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP _SMM.LEASES @ 0> 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DROP

    DUP _SLE.PLAN-ROW @ DUP R@ _SMO-PLAN-ROW-BELONGS? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP _SML.MAGIC @ _SMO-PLAN-ROW-MAGIC <> IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP _SML.PLAN @ 0= IF 2DROP R> DROP 0 EXIT THEN
    DROP
    DUP _SLE.PLAN-ROW @
    OVER _SLE.MODULE-ROW @ _SMM.PLAN-ROW @ <> IF
        DROP R> DROP 0 EXIT
    THEN

    DUP _SLE.PROFILE-ROW @ DUP R@ _SMO-PROFILE-ROW-BELONGS? 0= IF
        2DROP R> DROP 0 EXIT
    THEN
    DUP _SMP.MAGIC @ _SMO-PROFILE-ROW-MAGIC <> IF
        2DROP R> DROP 0 EXIT
    THEN
    _SMP.PROFILE @ 0= IF DROP R> DROP 0 EXIT THEN
    DUP _SLE.PROFILE-ROW @
    OVER _SLE.MODULE-ROW @ _SMM.PROFILE-ROW @ <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.PROFILE-ROW @
    OVER _SLE.PLAN-ROW @ _SML.PROFILE-ROW @ <> IF
        DROP R> DROP 0 EXIT
    THEN

    DUP _SLE.ENTRY-INDEX @ DUP 0<
    SWAP 2 PICK _SLE.MODULE-ROW @ _SMM.ENTRY-N @ >= OR IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.DECL-VIEW SBOX-DECL-VIEW-VALID? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.DECL-VIEW SBOX-DECL-SOURCE@
    DUP SBOX-DECL-S-OK <> IF
        2DROP 2DROP R> DROP 0 EXIT
    THEN
    DROP
    2 PICK _SLE.MODULE-ROW @ _SMM.DECLARATION-U @
    OVER <> IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    2 PICK _SLE.MODULE-ROW @ _SMM.DECLARATION @
    2 PICK <> IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    2DROP
    DUP _SLE.ENTRY-INDEX @
    OVER _SLE.DECL-VIEW SBOX-DECL-ENTRY@
    DUP SBOX-DECL-S-OK <> IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DROP OVER _SLE.ENTRY @ <> IF
        DROP R> DROP 0 EXIT
    THEN

    DUP _SLE.INPUT @ OVER _SLE.INPUT-U @
        _SMO-READ-SPAN-STATUS SBOX-MOWNER-S-OK <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.INPUT-U @ DUP 0> 0=
    SWAP SBOX-DECL-ONE-SCHEMA-MAX > OR IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.INPUT-DIGEST _SMO-DIGEST-PRESENT? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.OUTPUT @ OVER _SLE.OUTPUT-U @
        _SMO-READ-SPAN-STATUS SBOX-MOWNER-S-OK <> IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.OUTPUT-U @ DUP 0> 0=
    SWAP SBOX-DECL-ONE-SCHEMA-MAX > OR IF
        DROP R> DROP 0 EXIT
    THEN
    DUP _SLE.OUTPUT-DIGEST _SMO-DIGEST-PRESENT? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    _SLE-RESERVED + SBOX-MLEASE-SIZE _SLE-RESERVED -
        _SMO-ZERO?
    R> DROP ;

: _SMO-RESOLVE-SCHEMA-SPAN
  ( bytes schema-u digest storage owner -- resolved resolved-u status )
    >R
    R@ _SMO.S-X !
    R@ _SMO.S-D !
    R@ _SMO.S-W !
    R@ _SMO.S-C !
    R@ _SMO.S-C @ R@ _SMO.S-W @ R@ _SMO.S-D @
    R@ _SMO.S-X @ R@ _SMO-CHECK-ONE-SCHEMA
    ?DUP IF
        0 0 ROT R> DROP EXIT
    THEN
    R@ _SMO.S-X @ SBOX-DECL-SCHEMA-EMBEDDED = IF
        R@ _SMO.S-C @ R@ _SMO.S-W @ SBOX-MOWNER-S-OK
        R> DROP EXIT
    THEN
    R@ _SMO.S-D @ R@ _SMO-SCHEMA-FIND
    DUP 0= IF
        DROP R> DROP 0 0 SBOX-MOWNER-S-NOT-FOUND EXIT
    THEN
    DUP _SMS.BYTES @ SWAP _SMS.BYTES-U @
    SBOX-MOWNER-S-OK R> DROP ;

: _SMO-LEASE-ADMIT  ( owner -- status )
    >R
    R@ _SMO.S-A @ RID-SIZE _SMO-FIXED-SPAN-STATUS
    ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-A @ RID-PRESENT? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-B @ RID-SIZE _SMO-FIXED-SPAN-STATUS
    ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-B @ RID-PRESENT? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-X @ 0> 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-E @ _SMO-DIGEST-PRESENT? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-W @ DUP 1 <
    SWAP SBOX-DECL-ENTRY-NAME-MAX > OR IF
        R> DROP SBOX-MOWNER-S-ENTRY EXIT
    THEN
    R@ _SMO.S-C @ R@ _SMO.S-W @ _SMO-READ-SPAN-STATUS
    ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-F @ _SMO-LEASE-HEADER? 0= IF
        R> DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    R@ _SMO.S-F @ SBOX-MLEASE-VALID? IF
        R> DROP SBOX-MOWNER-S-STATE EXIT
    THEN

    R@ _SMO.S-F @ SBOX-MLEASE-SIZE
    R@ SBOX-MOWNER-SIZE MSPAN-OVERLAP? IF
        R> DROP SBOX-MOWNER-S-ALIAS EXIT
    THEN
    R@ _SMO.S-F @ SBOX-MLEASE-SIZE
    R@ _SMO.BACKING @ R@ _SMO.BACKING-U @
        MSPAN-OVERLAP? IF
        R> DROP SBOX-MOWNER-S-ALIAS EXIT
    THEN
    R@ _SMO.S-F @ SBOX-MLEASE-SIZE
    R@ _SMO.S-A @ RID-SIZE MSPAN-OVERLAP? IF
        R> DROP SBOX-MOWNER-S-ALIAS EXIT
    THEN
    R@ _SMO.S-F @ SBOX-MLEASE-SIZE
    R@ _SMO.S-B @ RID-SIZE MSPAN-OVERLAP? IF
        R> DROP SBOX-MOWNER-S-ALIAS EXIT
    THEN
    R@ _SMO.S-F @ SBOX-MLEASE-SIZE
    R@ _SMO.S-E @ SBOX-DIGEST-SIZE MSPAN-OVERLAP? IF
        R> DROP SBOX-MOWNER-S-ALIAS EXIT
    THEN
    R@ _SMO.S-F @ SBOX-MLEASE-SIZE
    R@ _SMO.S-C @ R@ _SMO.S-W @ MSPAN-OVERLAP? IF
        R> DROP SBOX-MOWNER-S-ALIAS EXIT
    THEN
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-LEASE-ENTRY-INDEX  ( entry owner -- index|-1 )
    >R
    R@ _SMO.S-ENTRY !
    0 R@ _SMO.S-I !
    BEGIN
        R@ _SMO.S-I @
        R@ _SMO.DECL-VIEW @ SBOX-DECL-ENTRY-COUNT@
        DROP <
    WHILE
        R@ _SMO.S-I @ R@ _SMO.DECL-VIEW @ SBOX-DECL-ENTRY@
        DUP SBOX-DECL-S-OK <> IF
            2DROP R> DROP -1 EXIT
        THEN
        DROP R@ _SMO.S-ENTRY @ = IF
            R@ _SMO.S-I @ R> DROP EXIT
        THEN
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP -1 ;

: _SMO-LEASE-SCHEMAS  ( entry lease owner -- status )
    >R
    R@ _SMO.S-F !
    R@ _SMO.S-ENTRY !

    R@ _SMO.S-ENTRY @ R@ _SMO.S-F @ _SLE.DECL-VIEW
        SBOX-DECL-ENTRY-INPUT-SCHEMA@
    DUP SBOX-DECL-S-OK <> IF
        DROP 2DROP 2DROP R> DROP
        SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP
    OVER R@ _SMO.S-F @ _SLE.INPUT-DIGEST
        SBOX-DIGEST-SIZE MOVE
    R@ _SMO-RESOLVE-SCHEMA-SPAN
    DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    R@ _SMO.S-F @ _SLE.INPUT-U !
    R@ _SMO.S-F @ _SLE.INPUT !

    R@ _SMO.S-ENTRY @ R@ _SMO.S-F @ _SLE.DECL-VIEW
        SBOX-DECL-ENTRY-OUTPUT-SCHEMA@
    DUP SBOX-DECL-S-OK <> IF
        DROP 2DROP 2DROP R> DROP
        SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    DROP
    OVER R@ _SMO.S-F @ _SLE.OUTPUT-DIGEST
        SBOX-DIGEST-SIZE MOVE
    R@ _SMO-RESOLVE-SCHEMA-SPAN
    DUP IF
        >R 2DROP R> R> DROP EXIT
    THEN
    DROP
    R@ _SMO.S-F @ _SLE.OUTPUT-U !
    R@ _SMO.S-F @ _SLE.OUTPUT !
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-LEASE-ACQUIRE-INTERNAL
  ( owner-rid module-rid revision declaration-digest
    entry entry-u lease owner -- status )
    >R
    R@ SBOX-MOWNER-VALID? 0= IF
        2DROP 2DROP 2DROP DROP R> DROP
        SBOX-MOWNER-S-STATE EXIT
    THEN
    R@ _SMO.S-F !
    R@ _SMO.S-W !
    R@ _SMO.S-C !
    R@ _SMO.S-E !
    R@ _SMO.S-X !
    R@ _SMO.S-B !
    R@ _SMO.S-A !

    R@ _SMO-LEASE-ADMIT ?DUP IF R> DROP EXIT THEN
    R@ _SMO.S-A @ R@ _SMO.S-B @ R@ _SMO.S-X @ R@
    _SMO-MODULE-FIND-KEY
    DUP 0= IF
        DROP R> DROP SBOX-MOWNER-S-NOT-FOUND EXIT
    THEN
    DUP _SMM.DECLARATION-DIGEST R@ _SMO.S-E @
        _SMO-32= 0= IF
        DROP R> DROP SBOX-MOWNER-S-NOT-FOUND EXIT
    THEN
    R@ _SMO.S-ROW !

    R@ _SMO.S-F @ SBOX-MLEASE-SIZE 0 FILL
    R@ _SMO.S-ROW @ _SMM.DECLARATION @
    R@ _SMO.S-ROW @ _SMM.DECLARATION-U @
    R@ _SMO.S-F @ _SLE.DECL-VIEW
    R@ _SMO.DIGEST-WORK @
    SBOX-DECL-VALIDATE
    SBOX-DECL-S-OK <> IF
        R@ _SMO.S-F @ SBOX-MLEASE-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-DECLARATION EXIT
    THEN
    R@ _SMO.S-C @ R@ _SMO.S-W @
    R@ _SMO.S-F @ _SLE.DECL-VIEW
    SBOX-DECL-ENTRY-FIND-EXACT
    DUP IF
        DROP DROP
        R@ _SMO.S-F @ SBOX-MLEASE-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-NOT-FOUND EXIT
    THEN
    DROP
    DUP R@ _SMO.S-ENTRY !
    DUP R@ _SMO-LEASE-ENTRY-INDEX
    DUP 0< IF
        2DROP
        R@ _SMO.S-F @ SBOX-MLEASE-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-ENTRY EXIT
    THEN
    R@ _SMO.S-I !
    DROP

    R@ _SMO.S-ENTRY @ R@ _SMO.S-F @ R@
        _SMO-LEASE-SCHEMAS
    ?DUP IF
        R@ _SMO.S-F @ SBOX-MLEASE-SIZE 0 FILL
        R> DROP EXIT
    THEN

    R@ R@ _SMO.S-F @ _SLE.OWNER !
    R@ _SMO.S-ROW @ R@ _SMO.S-F @ _SLE.MODULE-ROW !
    R@ _SMO.S-ROW @ _SMM.PLAN-ROW @
        R@ _SMO.S-F @ _SLE.PLAN-ROW !
    R@ _SMO.S-ROW @ _SMM.PROFILE-ROW @
        R@ _SMO.S-F @ _SLE.PROFILE-ROW !
    R@ _SMO.S-I @ R@ _SMO.S-F @ _SLE.ENTRY-INDEX !
    R@ _SMO.S-ENTRY @ R@ _SMO.S-F @ _SLE.ENTRY !
    R@ _SMO.S-F @ DUP _SLE.SELF !
    1 R@ _SMO.S-ROW @ _SMM.LEASES +!
    1 R@ _SMO.LEASE-N +!
    _SMO-LEASE-MAGIC R@ _SMO.S-F @ _SLE.MAGIC !

    R@ _SMO.S-F @ SBOX-MLEASE-VALID? 0= IF
        -1 R@ _SMO.S-ROW @ _SMM.LEASES +!
        -1 R@ _SMO.LEASE-N +!
        R@ _SMO.S-F @ SBOX-MLEASE-SIZE 0 FILL
        R> DROP SBOX-MOWNER-S-PLATFORM EXIT
    THEN
    R> DROP SBOX-MOWNER-S-OK ;

: _SMO-LEASE-ACQUIRE-LOCKED
  ( owner-rid module-rid revision declaration-digest
    entry entry-u lease owner -- status )
    DUP >R _SMO-LEASE-ACQUIRE-INTERNAL
    R@ _SMO-SCRATCH-CLEAR R> DROP ;

: SBOX-MOWNER-ACQUIRE-EXACT
  ( owner-rid module-rid revision declaration-digest
    entry entry-u lease owner -- status )
    DUP SBOX-MOWNER-VALID? 0= IF
        2DROP 2DROP 2DROP 2DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.GUARD >R
    ['] _SMO-LEASE-ACQUIRE-LOCKED R> WITH-GUARD ;

: _SMO-LEASE-RELEASE-LOCKED  ( lease -- status )
    DUP SBOX-MLEASE-VALID? 0= IF
        DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SLE.OWNER @ >R
    DUP _SLE.MODULE-ROW @ R@ _SMO.S-ROW !
    R@ _SMO.S-ROW @ _SMM.LEASES @ 0> 0=
    R@ _SMO.LEASE-N @ 0> 0= OR IF
        DROP R> DROP SBOX-MOWNER-S-STATE EXIT
    THEN
    0 OVER _SLE.MAGIC !
    -1 R@ _SMO.S-ROW @ _SMM.LEASES +!
    -1 R@ _SMO.LEASE-N +!
    SBOX-MLEASE-SIZE 0 FILL
    R@ _SMO-SCRATCH-CLEAR
    R> DROP SBOX-MOWNER-S-OK ;

: SBOX-MLEASE-RELEASE  ( lease -- status )
    DUP SBOX-MLEASE-VALID? 0= IF
        DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SLE.OWNER @ DUP SBOX-MOWNER-VALID? 0= IF
        2DROP SBOX-MOWNER-S-STATE EXIT
    THEN
    _SMO.GUARD >R
    ['] _SMO-LEASE-RELEASE-LOCKED R> WITH-GUARD ;

\ Read-only lease accessors.  They expose immutable objects pinned by the
\ lease and never perform lookup, hashing, verification, or invocation.
: SBOX-MLEASE-DECLARATION@  ( lease -- declaration-view|0 )
    DUP SBOX-MLEASE-VALID?
    IF _SLE.DECL-VIEW ELSE DROP 0 THEN ;

: SBOX-MLEASE-DECLARATION$  ( lease -- declaration declaration-u | 0 0 )
    SBOX-MLEASE-DECLARATION@
    DUP 0= IF DROP 0 0 EXIT THEN
    SBOX-DECL-SOURCE@ DROP ;

: SBOX-MLEASE-PLAN@  ( lease -- plan|0 )
    DUP SBOX-MLEASE-VALID? IF
        _SLE.PLAN-ROW @ _SML.PLAN @
    ELSE DROP 0 THEN ;

: SBOX-MLEASE-PROFILE@  ( lease -- profile|0 )
    DUP SBOX-MLEASE-VALID? IF
        _SLE.PROFILE-ROW @ _SMP.PROFILE @
    ELSE DROP 0 THEN ;

: SBOX-MLEASE-ENTRY-INDEX@  ( lease -- index|-1 )
    DUP SBOX-MLEASE-VALID?
    IF _SLE.ENTRY-INDEX @ ELSE DROP -1 THEN ;

: SBOX-MLEASE-ENTRY-NAME$  ( lease -- address length | 0 0 )
    DUP SBOX-MLEASE-VALID? 0= IF DROP 0 0 EXIT THEN
    DUP _SLE.ENTRY @
    SWAP _SLE.DECL-VIEW
    SBOX-DECL-ENTRY-NAME@ DROP ;

: SBOX-MLEASE-INPUT-SCHEMA@
  ( lease -- schema schema-u digest | 0 0 0 )
    DUP SBOX-MLEASE-VALID? 0= IF DROP 0 0 0 EXIT THEN
    DUP _SLE.INPUT @
    OVER _SLE.INPUT-U @
    ROT _SLE.INPUT-DIGEST ;

: SBOX-MLEASE-OUTPUT-SCHEMA@
  ( lease -- schema schema-u digest | 0 0 0 )
    DUP SBOX-MLEASE-VALID? 0= IF DROP 0 0 0 EXIT THEN
    DUP _SLE.OUTPUT @
    OVER _SLE.OUTPUT-U @
    ROT _SLE.OUTPUT-DIGEST ;

\ =====================================================================
\  Owner diagnostics and deterministic release
\ =====================================================================

: SBOX-MOWNER-MODULE-COUNT@  ( owner -- count|-1 )
    DUP SBOX-MOWNER-VALID?
    IF _SMO.MODULE-N @ ELSE DROP -1 THEN ;

: SBOX-MOWNER-PROFILE-COUNT@  ( owner -- count|-1 )
    DUP SBOX-MOWNER-VALID?
    IF _SMO.PROFILE-N @ ELSE DROP -1 THEN ;

: SBOX-MOWNER-SCHEMA-COUNT@  ( owner -- count|-1 )
    DUP SBOX-MOWNER-VALID?
    IF _SMO.SCHEMA-N @ ELSE DROP -1 THEN ;

: SBOX-MOWNER-PLAN-COUNT@  ( owner -- count|-1 )
    DUP SBOX-MOWNER-VALID?
    IF _SMO.PLAN-N @ ELSE DROP -1 THEN ;

: SBOX-MOWNER-ACTIVE-LEASES@  ( owner -- count|-1 )
    DUP SBOX-MOWNER-VALID?
    IF _SMO.LEASE-N @ ELSE DROP -1 THEN ;

: SBOX-MOWNER-CAPACITIES@
  ( owner -- module-cap profile-cap schema-cap plan-cap schema-depth status )
    DUP SBOX-MOWNER-VALID? 0= IF
        DROP 0 0 0 0 0 SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.MODULE-CAP @
    OVER _SMO.PROFILE-CAP @
    2 PICK _SMO.SCHEMA-CAP @
    3 PICK _SMO.PLAN-CAP @
    4 PICK _SMO.SCHEMA-DEPTH @
    >R >R >R >R >R DROP
    R> R> R> R> R> SBOX-MOWNER-S-OK ;

: SBOX-MOWNER-LAST-VERIFIER@
  ( owner -- verifier-status detail index status )
    DUP SBOX-MOWNER-VALID? 0= IF
        DROP 0 0 -1 SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.LAST-VERIFY-STATUS @
    OVER _SMO.LAST-VERIFY-DETAIL @
    ROT _SMO.LAST-VERIFY-INDEX @
    SBOX-MOWNER-S-OK ;

: _SMO-RELEASE-PREFLIGHT  ( owner -- flag )
    >R
    R@ _SMO.LEASE-N @ IF R> DROP 0 EXIT THEN

    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.MODULE-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-MODULE-ROW
        DUP _SMM.MAGIC @ _SMO-MODULE-ROW-MAGIC <> IF
            DROP R> DROP 0 EXIT
        THEN
        DUP _SMM.LEASES @ IF DROP R> DROP 0 EXIT THEN
        DUP _SMM.DECLARATION @
        OVER _SMM.DECLARATION-U @ _SMO-READ-SPAN-STATUS
        SBOX-MOWNER-S-OK <> IF DROP R> DROP 0 EXIT THEN
        DUP _SMM.ARTIFACT @
        OVER _SMM.ARTIFACT-U @ _SMO-READ-SPAN-STATUS
        SBOX-MOWNER-S-OK <> IF DROP R> DROP 0 EXIT THEN
        DUP _SMM.PROFILE-ROW @ R@ _SMO-PROFILE-ROW-BELONGS? 0= IF
            DROP R> DROP 0 EXIT
        THEN
        _SMM.PLAN-ROW @ R@ _SMO-PLAN-ROW-BELONGS? 0= IF
            R> DROP 0 EXIT
        THEN
        1 R@ _SMO.S-I +!
    REPEAT

    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.PLAN-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-PLAN-ROW
        DUP _SML.MAGIC @ _SMO-PLAN-ROW-MAGIC <> IF
            DROP R> DROP 0 EXIT
        THEN
        DUP _SML.PLAN @ DUP SBOX-PLAN-VALID? 0= IF
            2DROP R> DROP 0 EXIT
        THEN
        SWAP _SML.PLAN-U @ OVER SBOX-PLAN-TOTAL@ <> IF
            DROP R> DROP 0 EXIT
        THEN
        DROP
        1 R@ _SMO.S-I +!
    REPEAT

    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.SCHEMA-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-SCHEMA-ROW
        DUP _SMS.MAGIC @ _SMO-SCHEMA-ROW-MAGIC <> IF
            DROP R> DROP 0 EXIT
        THEN
        DUP _SMS.BYTES @
        SWAP _SMS.BYTES-U @ _SMO-READ-SPAN-STATUS
        SBOX-MOWNER-S-OK <> IF R> DROP 0 EXIT THEN
        1 R@ _SMO.S-I +!
    REPEAT

    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.PROFILE-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-PROFILE-ROW
        DUP _SMP.MAGIC @ _SMO-PROFILE-ROW-MAGIC <> IF
            DROP R> DROP 0 EXIT
        THEN
        DUP _SMP.BLOB @
        OVER _SMP.ID-U @ 2 PICK _SMP.DESCRIPTOR-U @ +
            _SMO-READ-SPAN-STATUS
        SBOX-MOWNER-S-OK <> IF DROP R> DROP 0 EXIT THEN
        _SMP.PROFILE @ SBOX-PROFILE-VALID? 0= IF
            R> DROP 0 EXIT
        THEN
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP -1 ;

: _SMO-RELEASE-MODULES  ( owner -- )
    >R
    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.MODULE-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-MODULE-ROW
        DUP _SMM.DECLARATION @ FREE
        DUP _SMM.ARTIFACT @ FREE
        _SMO-MODULE-ROW-SIZE 0 FILL
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP ;

: _SMO-RELEASE-PLANS  ( owner -- )
    >R
    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.PLAN-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-PLAN-ROW
        DUP _SML.PLAN @ DUP SBOX-PLAN-RELEASE DROP
        FREE
        _SMO-PLAN-ROW-SIZE 0 FILL
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP ;

: _SMO-RELEASE-SCHEMAS  ( owner -- )
    >R
    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.SCHEMA-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-SCHEMA-ROW
        DUP _SMS.BYTES @ FREE
        _SMO-SCHEMA-ROW-SIZE 0 FILL
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP ;

: _SMO-RELEASE-PROFILES  ( owner -- )
    >R
    0 R@ _SMO.S-I !
    BEGIN R@ _SMO.S-I @ R@ _SMO.PROFILE-N @ < WHILE
        R@ _SMO.S-I @ R@ _SMO-PROFILE-ROW
        DUP _SMP.PROFILE @ DUP SBOX-PROFILE-SIZE 0 FILL FREE
        DUP _SMP.BLOB @ FREE
        _SMO-PROFILE-ROW-SIZE 0 FILL
        1 R@ _SMO.S-I +!
    REPEAT
    R> DROP ;

: _SMO-RELEASE-LOCKED  ( owner -- status )
    DUP SBOX-MOWNER-VALID? 0= IF
        DROP SBOX-MOWNER-S-STATE EXIT
    THEN
    DUP _SMO.LEASE-N @ IF
        DROP SBOX-MOWNER-S-BUSY EXIT
    THEN
    DUP _SMO-RELEASE-PREFLIGHT 0= IF
        DUP _SMO-SCRATCH-CLEAR
        DROP SBOX-MOWNER-S-CLEANUP EXIT
    THEN
    _SMO-STATE-RELEASING OVER _SMO.STATE !
    DUP _SMO-RELEASE-MODULES
    DUP _SMO-RELEASE-PLANS
    DUP _SMO-RELEASE-SCHEMAS
    DUP _SMO-RELEASE-PROFILES
    DUP _SMO.BACKING @ FREE
    DROP SBOX-MOWNER-S-OK ;

\ The caller owns the 640-byte descriptor.  A successful RELEASE destroys
\ all owner allocations and clears that descriptor.  As with any explicit
\ destroy operation, the caller must first unpublish the owner pointer so no
\ new operation can race descriptor reclamation.
: SBOX-MOWNER-RELEASE  ( owner -- status )
    DUP SBOX-MOWNER-VALID? 0= IF
        DROP SBOX-MOWNER-S-INVALID EXIT
    THEN
    DUP _SMO.GUARD GUARD-TRY-ACQUIRE 0= IF
        DROP SBOX-MOWNER-S-BUSY EXIT
    THEN
    DUP _SMO-RELEASE-LOCKED
    OVER _SMO.GUARD GUARD-RELEASE
    DUP SBOX-MOWNER-S-OK = IF
        >R SBOX-MOWNER-SIZE 0 FILL R>
    ELSE
        NIP
    THEN ;
