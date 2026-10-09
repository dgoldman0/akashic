\ =====================================================================
\  sandbox-slot.f - One headless sandbox invocation slot
\ =====================================================================
\  This is the trusted lifecycle adapter for one headless invocation in
\  caller-owned storage.  It borrows one sealed exact module owner and one
\  active parent Context, copies already materialized value/execution
\  limits, and embeds one thin sandbox invocation host.  Each successful
\  ADMIT resolves an exact (RID, positive revision) and exact typed entry,
\  copies the typed input through SBOX-HOST, and publishes a new positive
\  invocation generation.
\
\  CLOSE permanently rejects new admission and synchronously cancels a
\  runnable invocation with HOST-SHUTDOWN detail.  A terminal result may
\  still be detached after CLOSE.  DRAIN is the explicit discard path: it
\  releases any remaining host before ending the module-owner, plan,
\  profile, and parent-Context borrows.  RELEASE is the idempotent safety
\  net which closes, drains, and zeros the caller-owned slot.
\
\  The detached result envelope owns an exact heap allocation containing
\  the self-contained SBOX-VM result.  It therefore survives slot,
\  module owner, plan/profile, and parent-Context teardown.
\
\  There is deliberately no APP-DESC, native callback, widget, Agent,
\  provider, Practice, declaration, schema, digest, cache, persistence,
\  VFS, capability, or import dispatch behavior here.
\ =====================================================================

PROVIDED akashic-sbox-slot

REQUIRE sandbox-module-owner.f
REQUIRE sandbox-host.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Public status and lifecycle states
\ =====================================================================

0  CONSTANT SBOX-JOB-S-OK
1  CONSTANT SBOX-JOB-S-INVALID
2  CONSTANT SBOX-JOB-S-STATE
3  CONSTANT SBOX-JOB-S-OWNER
4  CONSTANT SBOX-JOB-S-NOT-FOUND
5  CONSTANT SBOX-JOB-S-STALE-REVISION
6  CONSTANT SBOX-JOB-S-PROFILE
7  CONSTANT SBOX-JOB-S-ENTRY
8  CONSTANT SBOX-JOB-S-BUDGET
9  CONSTANT SBOX-JOB-S-HOST
10 CONSTANT SBOX-JOB-S-RESULT
11 CONSTANT SBOX-JOB-S-ALIAS
12 CONSTANT SBOX-JOB-S-NOMEM
13 CONSTANT SBOX-JOB-S-STALE-GENERATION

: SBOX-SLOT-STATUS-VALID?  ( status -- flag )
    DUP SBOX-JOB-S-OK >=
    SWAP SBOX-JOB-S-STALE-GENERATION <= AND ;

1 CONSTANT SBOX-SLOT-STATE-OPEN
2 CONSTANT SBOX-SLOT-STATE-CLOSING
3 CONSTANT SBOX-SLOT-STATE-DRAINED

0x44534258434F4D50 CONSTANT _SBXS-MAGIC  \ "DSBXCOMP"
0x4453425852455354 CONSTANT _SBXR-MAGIC  \ "DSBXREST"
0x7FFFFFFFFFFFFFFF CONSTANT _SBXS-GENERATION-MAX

\ =====================================================================
\  Fixed caller-owned slot
\ =====================================================================

  0 CONSTANT _SBXS-MAGIC-OFF
  8 CONSTANT _SBXS-SELF
 16 CONSTANT _SBXS-STATE
 24 CONSTANT _SBXS-OWNER
 32 CONSTANT _SBXS-PARENT
 40 CONSTANT _SBXS-SEQUENCE
 48 CONSTANT _SBXS-LIVE-GENERATION
 56 CONSTANT _SBXS-PLAN
 64 CONSTANT _SBXS-PROFILE
 72 CONSTANT _SBXS-ENTRY
 80 CONSTANT _SBXS-REVISION
 88 CONSTANT _SBXS-INSTRUCTION-BUDGET
 96 CONSTANT _SBXS-VALUE-OP-BUDGET
104 CONSTANT _SBXS-COPY-BUDGET
112 CONSTANT _SBXS-RESERVED
120 CONSTANT _SBXS-RID
152 CONSTANT _SBXS-LIMITS
256 CONSTANT _SBXS-HOST
768 CONSTANT SBOX-SLOT-SIZE

: _SBXS.MAGIC               ( slot -- address ) _SBXS-MAGIC-OFF + ;
: _SBXS.SELF                ( slot -- address ) _SBXS-SELF + ;
: _SBXS.STATE               ( slot -- address ) _SBXS-STATE + ;
: _SBXS.OWNER               ( slot -- address ) _SBXS-OWNER + ;
: _SBXS.PARENT              ( slot -- address ) _SBXS-PARENT + ;
: _SBXS.SEQUENCE            ( slot -- address ) _SBXS-SEQUENCE + ;
: _SBXS.LIVE-GENERATION     ( slot -- address )
    _SBXS-LIVE-GENERATION + ;
: _SBXS.PLAN                ( slot -- address ) _SBXS-PLAN + ;
: _SBXS.PROFILE             ( slot -- address ) _SBXS-PROFILE + ;
: _SBXS.ENTRY               ( slot -- address ) _SBXS-ENTRY + ;
: _SBXS.REVISION            ( slot -- address ) _SBXS-REVISION + ;
: _SBXS.INSTRUCTION-BUDGET  ( slot -- address )
    _SBXS-INSTRUCTION-BUDGET + ;
: _SBXS.VALUE-OP-BUDGET     ( slot -- address )
    _SBXS-VALUE-OP-BUDGET + ;
: _SBXS.COPY-BUDGET         ( slot -- address ) _SBXS-COPY-BUDGET + ;
: _SBXS.RESERVED            ( slot -- address ) _SBXS-RESERVED + ;
: _SBXS.RID                 ( slot -- rid ) _SBXS-RID + ;
: _SBXS.LIMITS              ( slot -- limits ) _SBXS-LIMITS + ;
: _SBXS.HOST                ( slot -- host ) _SBXS-HOST + ;

: _SBXS-SPAN?  ( address length -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _SBXS-ZERO?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _SBXS-FIXED?  ( slot -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    SBOX-SLOT-SIZE _SBXS-SPAN? ;

: _SBXS-HEADER?  ( slot -- flag )
    DUP _SBXS-FIXED? 0= IF DROP 0 EXIT THEN
    DUP _SBXS.MAGIC @ _SBXS-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBXS.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SBXS.STATE @ DUP SBOX-SLOT-STATE-OPEN =
    OVER SBOX-SLOT-STATE-CLOSING = OR
    SWAP SBOX-SLOT-STATE-DRAINED = OR 0= IF
        DROP 0 EXIT
    THEN
    _SBXS.RESERVED @ 0= ;

: _SBXS-PURE-PROFILE?  ( profile -- flag )
    DUP SBOX-PROFILE-VALID? 0= IF DROP 0 EXIT THEN
    SBOX-PROFILE-TAG@
    DUP IF 2DROP 0 EXIT THEN
    DROP SBOX-PROFILE-PURE-TAG = ;

: _SBXS-ENTRY-TYPED?  ( entry plan -- flag )
    >R
    DUP 0< IF DROP R> DROP 0 EXIT THEN
    DUP R@ SBOX-PLAN-ENTRY-N@ >= IF DROP R> DROP 0 EXIT THEN
    R@ SBOX-PLAN-ENTRY-SIGNATURE@
    0= IF DROP R> DROP 0 EXIT THEN
    SBOX-ABI-SIGNATURE-VALUE-TO-VALUE =
    R> DROP ;

: _SBXS-LIMITS-COPY  ( source destination -- status )
    OVER SBOX-VALUE-LIMITS-VALID? 0= IF
        2DROP SBOX-VALUE-S-STATE EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-BEGIN
    DUP IF -ROT 2DROP EXIT THEN
    DROP
    SBOX-VALUE-LIMIT-COUNT 0 ?DO
        I 2 PICK SBOX-VALUE-LIMIT@
        DUP IF
            2DROP 2DROP
            SBOX-VALUE-S-STATE UNLOOP EXIT
        THEN
        DROP
        I 2 PICK SBOX-VALUE-LIMIT!
        DUP IF -ROT 2DROP UNLOOP EXIT THEN
        DROP
    LOOP
    NIP SBOX-VALUE-LIMITS-SEAL ;

: _SBXS-BUDGET-WITHIN?  ( requested field plan -- flag )
    SBOX-PLAN-PROFILE@ SBOX-PROFILE-LIMIT@
    DUP IF
        2DROP DROP 0 EXIT
    THEN
    DROP U> 0= ;

: _SBXS-PLAN-BUDGETS?  ( plan slot -- flag )
    DUP _SBXS.INSTRUCTION-BUDGET @
    SBOX-PROFILE-LIMIT-MAX-BUDGET
    3 PICK _SBXS-BUDGET-WITHIN?
    1 PICK _SBXS.VALUE-OP-BUDGET @
    SBOX-PROFILE-LIMIT-VALUE-OPS
    4 PICK _SBXS-BUDGET-WITHIN? AND
    1 PICK _SBXS.COPY-BUDGET @
    SBOX-PROFILE-LIMIT-COPY-BYTES
    4 PICK _SBXS-BUDGET-WITHIN? AND
    NIP NIP ;

: _SBXS-PURE-PAIR?  ( plan profile -- flag )
    >R
    DUP SBOX-PLAN-VALID? 0= IF DROP R> DROP 0 EXIT THEN
    R@ _SBXS-PURE-PROFILE? 0= IF DROP R> DROP 0 EXIT THEN
    DUP SBOX-PLAN-PROFILE@ R@ <> IF DROP R> DROP 0 EXIT THEN
    SBOX-PLAN-IMPORT-N@ 0=
    R> DROP ;

\ The slot, its copied limits source, parent Context, and complete
\ installed-plan graph are independent lifetime domains before INIT writes.
: _SBXS-INIT-DISJOINT?
  ( owner parent limits slot -- flag )
    >R
    1 PICK CTX-SIZE
    R@ SBOX-SLOT-SIZE MSPAN-OVERLAP? IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    R@ SBOX-SLOT-SIZE
    4 PICK SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    1 PICK CTX-SIZE
    4 PICK SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-SIZE
    R@ SBOX-SLOT-SIZE MSPAN-OVERLAP? IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-SIZE
    3 PICK CTX-SIZE MSPAN-OVERLAP? IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DUP SBOX-VALUE-LIMITS-SIZE
    4 PICK SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    2DROP DROP R> DROP -1 ;

: _SBXS-LIFETIMES?  ( slot -- flag )
    >R
    R@ _SBXS.OWNER @ DUP SBOX-MODULE-OWNER-SEALED? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ _SBXS.PARENT @ DUP CTX-VALID? 0= IF
        DROP R> DROP 0 EXIT
    THEN
    CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        R> DROP 0 EXIT
    THEN
    R@ SBOX-SLOT-SIZE
    R@ _SBXS.OWNER @
    SBOX-MODULE-OWNER-SPAN-DISJOINT? 0= IF
        R> DROP 0 EXIT
    THEN
    R@ SBOX-SLOT-SIZE
    R@ _SBXS.PARENT @ CTX-SIZE MSPAN-OVERLAP? IF
        R> DROP 0 EXIT
    THEN
    R@ _SBXS.PARENT @ CTX-SIZE
    R@ _SBXS.OWNER @
    SBOX-MODULE-OWNER-SPAN-DISJOINT?
    R> DROP ;

: _SBXS-LIVE?  ( slot -- flag )
    _SBXS.LIVE-GENERATION @ 0> ;

: _SBXS-LIVE-MAPPING?  ( slot -- flag )
    >R
    R@ _SBXS.RID
    R@ _SBXS.REVISION @
    R@ _SBXS.OWNER @
    SBOX-MODULE-OWNER-RESOLVE-EXACT
    DUP IF
        2DROP DROP R> DROP 0 EXIT
    THEN
    DROP
    R@ _SBXS.PROFILE @ =
    SWAP R@ _SBXS.PLAN @ = AND
    R> DROP ;

: _SBXS-LIVE-SHAPE?  ( slot -- flag )
    DUP _SBXS-LIVE? 0= IF
        DUP _SBXS.LIVE-GENERATION @ 0=
        OVER _SBXS.PLAN @ 0= AND
        OVER _SBXS.PROFILE @ 0= AND
        OVER _SBXS.ENTRY @ 0= AND
        OVER _SBXS.REVISION @ 0= AND
        OVER _SBXS.RID RID-SIZE _SBXS-ZERO? AND
        SWAP _SBXS.HOST SBOX-HOST-INVOCATION-SIZE _SBXS-ZERO? AND
        EXIT
    THEN
    DUP _SBXS.LIVE-GENERATION @
    OVER _SBXS.SEQUENCE @ = 0= IF DROP 0 EXIT THEN
    DUP _SBXS-LIVE-MAPPING? 0= IF DROP 0 EXIT THEN
    DUP _SBXS.PLAN @ OVER _SBXS.PROFILE @
        _SBXS-PURE-PAIR? 0= IF DROP 0 EXIT THEN
    DUP _SBXS.PLAN @ OVER _SBXS-PLAN-BUDGETS? 0= IF DROP 0 EXIT THEN
    DUP _SBXS.ENTRY @ OVER _SBXS.PLAN @
        _SBXS-ENTRY-TYPED? 0= IF DROP 0 EXIT THEN
    _SBXS.HOST SBOX-HOST-VALID? ;

: SBOX-SLOT-VALID?  ( slot -- flag )
    DUP _SBXS-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _SBXS.STATE @ SBOX-SLOT-STATE-DRAINED = IF
        _SBXS.OWNER
        SBOX-SLOT-SIZE _SBXS-OWNER -
        _SBXS-ZERO? EXIT
    THEN
    DUP _SBXS.SEQUENCE @ DUP 0<
        SWAP _SBXS-GENERATION-MAX > OR IF DROP 0 EXIT THEN
    DUP _SBXS.INSTRUCTION-BUDGET @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXS.VALUE-OP-BUDGET @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXS.COPY-BUDGET @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXS.LIMITS SBOX-VALUE-LIMITS-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SBXS-LIFETIMES? 0= IF DROP 0 EXIT THEN
    _SBXS-LIVE-SHAPE? ;

: _SBXS-EXTERNAL-SPAN?  ( address length slot -- flag )
    >R
    2DUP _SBXS-SPAN? 0= IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ SBOX-SLOT-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    2DUP R@ _SBXS.PARENT @ CTX-SIZE
        MSPAN-OVERLAP? IF 2DROP R> DROP 0 EXIT THEN
    R@ _SBXS.OWNER @ SBOX-MODULE-OWNER-SPAN-DISJOINT?
    R> DROP ;

\ =====================================================================
\  Initialization
\ =====================================================================

: _SBXS-DROP7>STATUS  ( x1 x2 x3 x4 x5 x6 x7 status -- status )
    >R 2DROP 2DROP 2DROP DROP R> ;

: _SBXS-INIT-BOUNDARY
  ( owner parent limits instruction value-ops copy slot -- same status )
    DUP _SBXS-FIXED? 0= IF SBOX-JOB-S-INVALID EXIT THEN
    DUP SBOX-SLOT-SIZE _SBXS-ZERO? 0= IF
        SBOX-JOB-S-STATE EXIT
    THEN
    6 PICK SBOX-MODULE-OWNER-SEALED? 0= IF
        SBOX-JOB-S-OWNER EXIT
    THEN
    5 PICK DUP CTX-VALID? 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        SBOX-JOB-S-INVALID EXIT
    THEN
    4 PICK SBOX-VALUE-LIMITS-VALID? 0= IF
        SBOX-JOB-S-INVALID EXIT
    THEN
    3 PICK 0> 0= IF SBOX-JOB-S-BUDGET EXIT THEN
    2 PICK 0> 0= IF SBOX-JOB-S-BUDGET EXIT THEN
    1 PICK 0> 0= IF SBOX-JOB-S-BUDGET EXIT THEN
    6 PICK 6 PICK 6 PICK 3 PICK
        _SBXS-INIT-DISJOINT? 0= IF
        SBOX-JOB-S-ALIAS EXIT
    THEN
    SBOX-JOB-S-OK ;

: SBOX-SLOT-INIT
  ( owner parent limits instruction value-ops copy slot -- status )
    _SBXS-INIT-BOUNDARY
    DUP IF _SBXS-DROP7>STATUS EXIT THEN
    DROP

    DUP >R
    R@ SBOX-SLOT-SIZE 0 FILL
    R@ R@ _SBXS.SELF !
    6 PICK R@ _SBXS.OWNER !
    5 PICK R@ _SBXS.PARENT !
    3 PICK R@ _SBXS.INSTRUCTION-BUDGET !
    2 PICK R@ _SBXS.VALUE-OP-BUDGET !
    1 PICK R@ _SBXS.COPY-BUDGET !
    4 PICK R@ _SBXS.LIMITS _SBXS-LIMITS-COPY
    DUP IF
        DROP
        R@ SBOX-SLOT-SIZE 0 FILL
        SBOX-JOB-S-INVALID
        _SBXS-DROP7>STATUS R> DROP EXIT
    THEN
    DROP
    SBOX-SLOT-STATE-OPEN R@ _SBXS.STATE !
    _SBXS-MAGIC R@ _SBXS.MAGIC !
    R@ SBOX-SLOT-VALID? 0= IF
        R@ SBOX-SLOT-SIZE 0 FILL
        SBOX-JOB-S-INVALID
        _SBXS-DROP7>STATUS R> DROP EXIT
    THEN
    SBOX-JOB-S-OK _SBXS-DROP7>STATUS
    R> DROP ;

\ =====================================================================
\  Exact invocation admission
\ =====================================================================

: _SBXS-OWNER>STATUS  ( owner-status -- slot-status )
    DUP SBOX-MODULE-OWNER-S-NOT-FOUND = IF
        DROP SBOX-JOB-S-NOT-FOUND EXIT
    THEN
    SBOX-MODULE-OWNER-S-STALE-REVISION = IF
        SBOX-JOB-S-STALE-REVISION
    ELSE
        SBOX-JOB-S-OWNER
    THEN ;

: _SBXS-DROP4>RESOLUTION
  ( x1 x2 x3 x4 plan profile entry status -- plan profile entry status )
    >R >R >R >R
    2DROP 2DROP
    R> R> R> R> ;

: _SBXS-RESOLVE
  ( rid revision name name-u slot -- plan profile entry status )
    >R
    3 PICK 3 PICK R@ _SBXS.OWNER @
        SBOX-MODULE-OWNER-RESOLVE-EXACT
    DUP IF
        _SBXS-OWNER>STATUS >R
        2DROP 2DROP 2DROP
        R> R> DROP >R
        0 0 -1 R> EXIT
    THEN
    DROP
    2DUP _SBXS-PURE-PAIR? 0= IF
        2DROP 2DROP 2DROP
        R> DROP
        0 0 -1 SBOX-JOB-S-PROFILE EXIT
    THEN
    OVER R@ _SBXS-PLAN-BUDGETS? 0= IF
        2DROP 2DROP 2DROP
        R> DROP
        0 0 -1 SBOX-JOB-S-BUDGET EXIT
    THEN

    3 PICK 3 PICK 3 PICK SBOX-HOST-ENTRY-RESOLVE-EXACT
    DUP IF
        2DROP
        2DROP 2DROP 2DROP
        R> DROP
        0 0 -1 SBOX-JOB-S-ENTRY EXIT
    THEN
    DROP
    DUP 3 PICK _SBXS-ENTRY-TYPED? 0= IF
        2DROP 2DROP 2DROP DROP
        R> DROP
        0 0 -1 SBOX-JOB-S-ENTRY EXIT
    THEN
    R> DROP
    SBOX-JOB-S-OK _SBXS-DROP4>RESOLUTION ;

: _SBXS-ADMIT-BOUNDARY
  ( rid revision name name-u input input-u slot -- same status )
    DUP SBOX-SLOT-VALID? 0= IF
        SBOX-JOB-S-INVALID EXIT
    THEN
    DUP _SBXS.STATE @ SBOX-SLOT-STATE-OPEN <> IF
        SBOX-JOB-S-STATE EXIT
    THEN
    DUP _SBXS-LIVE? IF SBOX-JOB-S-STATE EXIT THEN
    DUP _SBXS.SEQUENCE @ _SBXS-GENERATION-MAX >= IF
        SBOX-JOB-S-STATE EXIT
    THEN
    5 PICK 0> 0= IF SBOX-JOB-S-INVALID EXIT THEN
    6 PICK RID-SIZE 2 PICK _SBXS-EXTERNAL-SPAN? 0= IF
        SBOX-JOB-S-ALIAS EXIT
    THEN
    6 PICK RID-PRESENT? 0= IF SBOX-JOB-S-INVALID EXIT THEN
    3 PICK 0> 0= IF SBOX-JOB-S-ENTRY EXIT THEN
    4 PICK 4 PICK 2 PICK _SBXS-EXTERNAL-SPAN? 0= IF
        SBOX-JOB-S-ALIAS EXIT
    THEN
    1 PICK 0> 0= IF SBOX-JOB-S-INVALID EXIT THEN
    2 PICK 2 PICK 2 PICK _SBXS-EXTERNAL-SPAN? 0= IF
        SBOX-JOB-S-ALIAS EXIT
    THEN
    SBOX-JOB-S-OK ;

: _SBXS-DROP10>GEN-STATUS
  ( x1 x2 x3 x4 x5 x6 x7 x8 x9 x10 generation status -- generation status )
    >R >R
    2DROP 2DROP 2DROP 2DROP 2DROP
    R> R> ;

: _SBXS-ADMIT-START
  ( rid revision name name-u input input-u slot plan profile entry -- generation status )
    3 PICK >R
    R@ _SBXS.PARENT @
    3 PICK
    2 PICK
    8 PICK
    8 PICK
    R@ _SBXS.LIMITS
    R@ _SBXS.INSTRUCTION-BUDGET @
    R@ _SBXS.VALUE-OP-BUDGET @
    R@ _SBXS.COPY-BUDGET @
    R@ _SBXS.HOST
    SBOX-HOST-INIT
    DUP IF
        DROP
        R> DROP
        0 SBOX-JOB-S-HOST
        _SBXS-DROP10>GEN-STATUS EXIT
    THEN
    DROP

    1 R@ _SBXS.SEQUENCE +!
    9 PICK R@ _SBXS.RID RID-COPY
    8 PICK R@ _SBXS.REVISION !
    2 PICK R@ _SBXS.PLAN !
    1 PICK R@ _SBXS.PROFILE !
    DUP R@ _SBXS.ENTRY !
    R@ _SBXS.SEQUENCE @ R@ _SBXS.LIVE-GENERATION !
    R@ _SBXS.SEQUENCE @ SBOX-JOB-S-OK
    R> DROP
    _SBXS-DROP10>GEN-STATUS ;

: SBOX-SLOT-ADMIT
  ( rid revision entry entry-u input input-u slot -- generation|0 status )
    _SBXS-ADMIT-BOUNDARY
    DUP IF
        >R 2DROP 2DROP 2DROP DROP 0 R> EXIT
    THEN
    DROP
    6 PICK 6 PICK 6 PICK 6 PICK 4 PICK _SBXS-RESOLVE
    DUP IF
        >R 2DROP 2DROP
        2DROP 2DROP 2DROP
        0 R> EXIT
    THEN
    DROP
    _SBXS-ADMIT-START ;

\ =====================================================================
\  Generation-bound execution
\ =====================================================================

: _SBXS-HANDLE-STATUS  ( generation slot -- status )
    DUP SBOX-SLOT-VALID? 0= IF
        2DROP SBOX-JOB-S-INVALID EXIT
    THEN
    DUP _SBXS-LIVE? 0= IF
        2DROP SBOX-JOB-S-STATE EXIT
    THEN
    _SBXS.LIVE-GENERATION @ =
    IF SBOX-JOB-S-OK ELSE SBOX-JOB-S-STALE-GENERATION THEN ;

: _SBXS-RUN-SLICE-VALIDATED
  ( max-steps slot -- run-state status )
    OVER 0> 0= IF
        2DROP SBOX-VM-RUN-INVALID SBOX-JOB-S-INVALID EXIT
    THEN
    >R
    R@ _SBXS.HOST _SHOST-RUN-SLICE-VALIDATED
    DUP SBOX-VM-RUN-INVALID =
    IF SBOX-JOB-S-HOST ELSE SBOX-JOB-S-OK THEN
    R> DROP ;

: _SBXS-DROP3>RUN-STATUS
  ( x1 x2 x3 run-state status -- run-state status )
    >R >R 2DROP DROP R> R> ;

: SBOX-SLOT-RUN-SLICE
  ( max-steps generation slot -- run-state status )
    1 PICK 1 PICK _SBXS-HANDLE-STATUS
    DUP IF
        >R 2DROP DROP SBOX-VM-RUN-INVALID R> EXIT
    THEN
    DROP
    2 PICK 0> 0= IF
        2DROP DROP
        SBOX-VM-RUN-INVALID SBOX-JOB-S-INVALID EXIT
    THEN
    2 PICK OVER _SBXS.HOST SBOX-HOST-RUN-SLICE
    DUP SBOX-VM-RUN-INVALID = IF
        SBOX-JOB-S-HOST
    ELSE
        SBOX-JOB-S-OK
    THEN
    _SBXS-DROP3>RUN-STATUS ;

: SBOX-SLOT-RUN-STATE@
  ( generation slot -- run-state status )
    2DUP _SBXS-HANDLE-STATUS
    DUP IF
        >R 2DROP SBOX-VM-RUN-INVALID R> EXIT
    THEN
    DROP
    DUP _SBXS.HOST SBOX-HOST-RUN-STATE@
    DUP SBOX-VM-RUN-INVALID = IF
        DROP 2DROP
        SBOX-VM-RUN-INVALID SBOX-JOB-S-HOST
    ELSE
        >R 2DROP R> SBOX-JOB-S-OK
    THEN ;

: SBOX-SLOT-CONTEXT-IDENTITY@
  ( generation slot -- id child-generation epoch status )
    2DUP _SBXS-HANDLE-STATUS
    DUP IF
        >R 2DROP 0 0 0 R> EXIT
    THEN
    DROP
    DUP _SBXS.HOST SBOX-HOST-CONTEXT-IDENTITY@
    DUP IF
        >R 2DROP 2DROP DROP 0 0 0
        R> DROP SBOX-JOB-S-HOST EXIT
    THEN
    DROP
    >R >R >R
    2DROP
    R> R> R> SBOX-JOB-S-OK ;

: SBOX-SLOT-CANCEL  ( generation slot -- status )
    2DUP _SBXS-HANDLE-STATUS
    DUP IF
        >R 2DROP R> EXIT
    THEN
    DROP
    SBOX-VM-CANCEL-CALLER 1 PICK _SBXS.HOST SBOX-HOST-CANCEL
    SBOX-HOST-S-OK =
    >R 2DROP R>
    IF SBOX-JOB-S-OK ELSE SBOX-JOB-S-HOST THEN ;

\ =====================================================================
\  Detached caller-owned result
\ =====================================================================

 0 CONSTANT _SBXR-MAGIC-OFF
 8 CONSTANT _SBXR-SELF
16 CONSTANT _SBXR-GENERATION
24 CONSTANT _SBXR-RUN-STATE
32 CONSTANT _SBXR-PAYLOAD
40 CONSTANT _SBXR-PAYLOAD-U
48 CONSTANT _SBXR-PAYLOAD-CAP
56 CONSTANT _SBXR-RESERVED
64 CONSTANT SBOX-SLOT-RESULT-SIZE

: _SBXR.MAGIC        ( result -- address ) _SBXR-MAGIC-OFF + ;
: _SBXR.SELF         ( result -- address ) _SBXR-SELF + ;
: _SBXR.GENERATION   ( result -- address ) _SBXR-GENERATION + ;
: _SBXR.RUN-STATE    ( result -- address ) _SBXR-RUN-STATE + ;
: _SBXR.PAYLOAD      ( result -- address ) _SBXR-PAYLOAD + ;
: _SBXR.PAYLOAD-U    ( result -- address ) _SBXR-PAYLOAD-U + ;
: _SBXR.PAYLOAD-CAP  ( result -- address ) _SBXR-PAYLOAD-CAP + ;
: _SBXR.RESERVED     ( result -- address ) _SBXR-RESERVED + ;

: _SBXR-FIXED?  ( result -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    SBOX-SLOT-RESULT-SIZE _SBXS-SPAN? ;

: _SBXS-TERMINAL?  ( run-state -- flag )
    DUP SBOX-VM-RUN-COMPLETE >=
    SWAP SBOX-VM-RUN-CANCELLED <= AND ;

\ These private accessors require a successful result proof, either directly
\ or nested in a just-completed receipt proof, with no intervening mutation,
\ callback, or yield.
: _SBXR-GENERATION-VALIDATED@  ( result -- generation )
    _SBXR.GENERATION @ ;

: _SBXR-RUN-STATE-VALIDATED@  ( result -- run-state )
    _SBXR.RUN-STATE @ ;

: _SBXR-PAYLOAD-VALIDATED@
  ( result -- payload payload-u flag )
    DUP _SBXR.PAYLOAD @
    SWAP _SBXR.PAYLOAD-U @
    -1 ;

: SBOX-SLOT-RESULT-VALID?  ( result -- flag )
    DUP _SBXR-FIXED? 0= IF DROP 0 EXIT THEN
    DUP _SBXR.MAGIC @ _SBXR-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBXR.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SBXR.GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXR.RUN-STATE @ _SBXS-TERMINAL? 0= IF DROP 0 EXIT THEN
    DUP _SBXR.PAYLOAD @ DUP 0= IF 2DROP 0 EXIT THEN
    DUP SBOX-VM-RESULT-VALID? 0= IF 2DROP 0 EXIT THEN
    _SVM-RESULT-TOTAL-VALIDATED@
    OVER _SBXR.PAYLOAD-U @ =
    OVER _SBXR.PAYLOAD-U @ 2 PICK _SBXR.PAYLOAD-CAP @ = AND
    SWAP _SBXR.RESERVED @ 0= AND ;

: SBOX-SLOT-RESULT-GENERATION@  ( result -- generation|0 )
    DUP SBOX-SLOT-RESULT-VALID?
    IF _SBXR-GENERATION-VALIDATED@ ELSE DROP 0 THEN ;

: SBOX-SLOT-RESULT-RUN-STATE@  ( result -- run-state )
    DUP SBOX-SLOT-RESULT-VALID?
    IF _SBXR-RUN-STATE-VALIDATED@
    ELSE DROP SBOX-VM-RUN-INVALID THEN ;

: SBOX-SLOT-RESULT-PAYLOAD@
  ( result -- payload payload-u flag )
    DUP SBOX-SLOT-RESULT-VALID? 0= IF
        DROP 0 0 0 EXIT
    THEN
    _SBXR-PAYLOAD-VALIDATED@ ;

: _SBXS-SCRUB-FREE  ( address length -- )
    OVER 0= IF 2DROP EXIT THEN
    DUP 0> IF 2DUP 0 FILL THEN
    DROP FREE ;

\ The enclosing Desk result or receipt has just validated this exact nested
\ VM result.  Scrub its proven writable span once, free the zeroed allocation,
\ then clear metadata.
: _SBXR-RELEASE-VALIDATED  ( result -- )
    >R
    R@ _SBXR.PAYLOAD @ R@ _SBXR.PAYLOAD-CAP @
    2DUP _SVM-RESULT-SCRUB-SPAN-VALIDATED
    DROP FREE
    R@ SBOX-SLOT-RESULT-SIZE 0 FILL
    R> DROP ;

: SBOX-SLOT-RESULT-RELEASE  ( result -- status )
    DUP _SBXR-FIXED? 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    DUP SBOX-SLOT-RESULT-SIZE _SBXS-ZERO? IF
        DROP SBOX-JOB-S-OK EXIT
    THEN
    DUP SBOX-SLOT-RESULT-VALID? 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    _SBXR-RELEASE-VALIDATED
    SBOX-JOB-S-OK ;

: _SBXS-TAKE-SPAN-VALIDATED
  ( address length slot -- status )
    >R
    2DUP R@ _SBXS-EXTERNAL-SPAN? 0= IF
        2DROP R> DROP SBOX-JOB-S-ALIAS EXIT
    THEN
    2DUP R@ _SBXS.HOST
        _SHOST-SPAN-DISJOINT-VALIDATED? 0= IF
        2DROP R> DROP SBOX-JOB-S-ALIAS EXIT
    THEN
    R@ _SBXS.HOST _SHOST-RUN-STATE-VALIDATED
        _SBXS-TERMINAL? 0= IF
        2DROP R> DROP SBOX-JOB-S-STATE EXIT
    THEN
    2DROP R> DROP SBOX-JOB-S-OK ;

: _SBXS-TAKE-SPAN-STATUS
  ( address length generation slot -- status )
    >R
    DUP R@ _SBXS-HANDLE-STATUS
    DUP IF
        >R 2DROP DROP R> R> DROP EXIT
    THEN
    DROP
    DROP R> _SBXS-TAKE-SPAN-VALIDATED ;

: _SBXS-TAKE-BOUNDARY
  ( result generation slot -- same status )
    2 PICK _SBXR-FIXED? 0= IF SBOX-JOB-S-INVALID EXIT THEN
    2 PICK SBOX-SLOT-RESULT-SIZE _SBXS-ZERO? 0= IF
        SBOX-JOB-S-STATE EXIT
    THEN
    2 PICK SBOX-SLOT-RESULT-SIZE 3 PICK 3 PICK
        _SBXS-TAKE-SPAN-STATUS ;

\ TAKE is serialized, and this allocator is the sole operation between the
\ measured host proof and the private FINISH below.  ALLOCATE must remain
\ non-reentrant: if it can callback, yield, or mutate the live host graph,
\ TAKE must use the fully validating public SBOX-HOST-FINISH instead.
: _SBXS-ALLOCATE  ( bytes -- address status )
    DUP 0> 0= IF DROP 0 SBOX-JOB-S-RESULT EXIT THEN
    ALLOCATE
    DUP IF
        2DROP 0 SBOX-JOB-S-NOMEM EXIT
    THEN
    DROP
    DUP 0= IF
        DROP 0 SBOX-JOB-S-NOMEM
    ELSE
        SBOX-JOB-S-OK
    THEN ;

: _SBXS-LIVE-CLEAR  ( slot -- )
    0 OVER _SBXS.LIVE-GENERATION !
    0 OVER _SBXS.PLAN !
    0 OVER _SBXS.PROFILE !
    0 OVER _SBXS.ENTRY !
    0 OVER _SBXS.REVISION !
    DUP _SBXS.RID RID-CLEAR
    _SBXS.HOST SBOX-HOST-INVOCATION-SIZE 0 FILL ;

: _SBXS-DROP6>STATUS  ( x1 x2 x3 x4 x5 x6 status -- status )
    >R 2DROP 2DROP 2DROP R> ;

: _SBXS-RESULT-TAKE-PRECHECKED
  ( result generation slot -- status )
    DUP _SBXS.HOST SBOX-HOST-RESULT-MEASURE
    DUP IF
        2DROP 2DROP DROP SBOX-JOB-S-HOST EXIT
    THEN
    DROP
    1 PICK _SBXS.HOST _SHOST-RUN-STATE-VALIDATED
    1 PICK _SBXS-ALLOCATE
    DUP IF
        >R 2DROP 2DROP 2DROP R> EXIT
    THEN
    DROP

    DUP
    3 PICK
    DUP
    6 PICK _SBXS.HOST
    _SHOST-FINISH-MEASURED-VALIDATED
    DUP IF
        DROP
        DUP 3 PICK _SBXS-SCRUB-FREE
        2DROP 2DROP 2DROP
        SBOX-JOB-S-HOST EXIT
    THEN
    DROP

    3 PICK _SBXS-LIVE-CLEAR
    5 PICK >R
    R@ SBOX-SLOT-RESULT-SIZE 0 FILL
    R@ R@ _SBXR.SELF !
    4 PICK R@ _SBXR.GENERATION !
    1 PICK R@ _SBXR.RUN-STATE !
    DUP R@ _SBXR.PAYLOAD !
    2 PICK R@ _SBXR.PAYLOAD-U !
    2 PICK R@ _SBXR.PAYLOAD-CAP !
    _SBXR-MAGIC R@ _SBXR.MAGIC !
    R@ SBOX-SLOT-RESULT-VALID? 0= IF
        DUP 3 PICK SBOX-VM-RESULT-RELEASE DROP
        DUP 3 PICK _SBXS-SCRUB-FREE
        R@ SBOX-SLOT-RESULT-SIZE 0 FILL
        R> DROP
        SBOX-JOB-S-RESULT _SBXS-DROP6>STATUS EXIT
    THEN
    R> DROP
    SBOX-JOB-S-OK _SBXS-DROP6>STATUS ;

: SBOX-SLOT-RESULT-TAKE
  ( result generation slot -- status )
    _SBXS-TAKE-BOUNDARY
    DUP IF
        >R 2DROP DROP R> EXIT
    THEN
    DROP
    _SBXS-RESULT-TAKE-PRECHECKED ;

\ =====================================================================
\  Close, drain, and deterministic release
\ =====================================================================

: SBOX-SLOT-CLOSE  ( slot -- status )
    DUP SBOX-SLOT-VALID? 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    DUP _SBXS.STATE @ SBOX-SLOT-STATE-DRAINED = IF
        DROP SBOX-JOB-S-OK EXIT
    THEN
    \ Publish the permanent admission barrier before touching the host.
    SBOX-SLOT-STATE-CLOSING
        OVER _SBXS.STATE !
    DUP _SBXS-LIVE? 0= IF
        DROP SBOX-JOB-S-OK EXIT
    THEN
    DUP _SBXS.HOST SBOX-HOST-RUN-STATE@
    DUP SBOX-VM-RUN-RUNNABLE = IF
        DROP
        SBOX-VM-CANCEL-HOST-SHUTDOWN
        SWAP _SBXS.HOST SBOX-HOST-CANCEL
        SBOX-HOST-S-OK =
        IF SBOX-JOB-S-OK ELSE SBOX-JOB-S-HOST THEN
        EXIT
    THEN
    SBOX-VM-RUN-INVALID = IF
        DROP SBOX-JOB-S-HOST
    ELSE
        DROP SBOX-JOB-S-OK
    THEN ;

: _SBXS-DRAIN-CLEAR  ( slot -- )
    DUP _SBXS.OWNER
    SBOX-SLOT-SIZE _SBXS-OWNER -
    0 FILL
    SBOX-SLOT-STATE-DRAINED SWAP _SBXS.STATE ! ;

: SBOX-SLOT-DRAIN  ( slot -- status )
    DUP SBOX-SLOT-VALID? 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    DUP _SBXS.STATE @ SBOX-SLOT-STATE-DRAINED = IF
        DROP SBOX-JOB-S-OK EXIT
    THEN
    DUP SBOX-SLOT-CLOSE >R
    DUP _SBXS-LIVE? IF
        DUP _SBXS.HOST SBOX-HOST-RELEASE
        DUP IF
            DROP R> DROP
            DROP SBOX-JOB-S-HOST EXIT
        THEN
        DROP
        DUP _SBXS-LIVE-CLEAR
    THEN
    _SBXS-DRAIN-CLEAR
    R> ;

: SBOX-SLOT-STATE@  ( slot -- state|0 )
    DUP SBOX-SLOT-VALID?
    IF _SBXS.STATE @ ELSE DROP 0 THEN ;

: SBOX-SLOT-GENERATION@  ( slot -- generation|0 )
    DUP SBOX-SLOT-VALID?
    IF _SBXS.LIVE-GENERATION @ ELSE DROP 0 THEN ;

: SBOX-SLOT-LIVE?  ( slot -- flag )
    DUP SBOX-SLOT-VALID?
    IF _SBXS-LIVE? ELSE DROP 0 THEN ;

: SBOX-SLOT-RELEASE  ( slot -- status )
    DUP _SBXS-FIXED? 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    DUP SBOX-SLOT-SIZE _SBXS-ZERO? IF
        DROP SBOX-JOB-S-OK EXIT
    THEN
    DUP SBOX-SLOT-VALID? 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    DUP SBOX-SLOT-DRAIN
    OVER _SBXS.STATE @ SBOX-SLOT-STATE-DRAINED = IF
        OVER SBOX-SLOT-SIZE 0 FILL
    THEN
    NIP ;
