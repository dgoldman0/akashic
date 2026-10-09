\ =====================================================================
\  sandbox-job-service.f - Bounded sandbox job service
\ =====================================================================
\  The service runs verified sandbox plans as jobs for any host.  The
\  caller selects a positive capacity; MEASURE gives the exact storage
\  span for it, and INIT accepts only that span.  The service borrows one
\  active parent Context and copies the host's limit policy, the length
\  of one run slice, and the time each TICK may spend running jobs.
\
\  SUBMIT binds a job to an opaque owner token (id, generation), checks
\  the plan and its typed entry, narrows the policy by the request's
\  limits and the plan's profile, and copies the input into a fresh
\  capability-empty host.  The public handle is the service activation
\  ID and a positive job generation.  Only the job's owner may query,
\  cancel, take or discard it, and OWNER-DRAIN discards all of an
\  owner's jobs when that owner closes.
\
\  TICK runs runnable jobs in turn, one slice at a time, until no job is
\  runnable or the allowance is spent, and always runs at least one
\  slice.  It cancels a job past its deadline.  A finished job keeps its
\  result until TAKE writes the self-contained VM result into a caller
\  buffer or DISCARD drops it.
\
\  The caller keeps a submitted plan, its profile and the parent Context
\  alive until the job is taken or discarded.  CLOSE cancels runnable
\  jobs and refuses new ones; DRAIN also discards every job and ends the
\  service's borrows.  The service is caller-serialized and stays on the
\  core that initialized it.  Operations check the service header and
\  the job they touch; AUDIT checks every job against its host.
\
\  No module table, schema, digest, persistence, capability or effect
\  behavior lives here.  The owner token scopes access and cleanup only;
\  it grants the guest nothing.
\ =====================================================================

PROVIDED akashic-sbox-job-service

REQUIRE sandbox-host.f
REQUIRE sandbox-limits.f
REQUIRE ../utils/caller-span.f
REQUIRE ../utils/memory-span.f

\ =====================================================================
\  Status, job state, and service state
\ =====================================================================

0  CONSTANT SBOX-JOB-S-OK
1  CONSTANT SBOX-JOB-S-INVALID
2  CONSTANT SBOX-JOB-S-STATE
3  CONSTANT SBOX-JOB-S-NOT-FOUND
4  CONSTANT SBOX-JOB-S-STALE
5  CONSTANT SBOX-JOB-S-NOT-OWNER
6  CONSTANT SBOX-JOB-S-WRONG-CORE
7  CONSTANT SBOX-JOB-S-FULL
8  CONSTANT SBOX-JOB-S-CAPACITY
9  CONSTANT SBOX-JOB-S-PROFILE
10 CONSTANT SBOX-JOB-S-ENTRY
11 CONSTANT SBOX-JOB-S-INPUT
12 CONSTANT SBOX-JOB-S-LIMITS
13 CONSTANT SBOX-JOB-S-HOST
14 CONSTANT SBOX-JOB-S-RESULT
15 CONSTANT SBOX-JOB-S-ALIAS
16 CONSTANT SBOX-JOB-S-NOMEM

: SBOX-JOB-STATUS-VALID?  ( status -- flag )
    DUP SBOX-JOB-S-OK >= SWAP SBOX-JOB-S-NOMEM <= AND ;

0 CONSTANT SBOX-JOB-STATE-FREE
1 CONSTANT SBOX-JOB-STATE-RUNNABLE
2 CONSTANT SBOX-JOB-STATE-READY
3 CONSTANT SBOX-JOB-STATE-FAILED

1 CONSTANT SBOX-JOB-SERVICE-STATE-OPEN
2 CONSTANT SBOX-JOB-SERVICE-STATE-CLOSING
3 CONSTANT SBOX-JOB-SERVICE-STATE-DRAINED

0x7FFFFFFFFFFFFFFF CONSTANT _SBXJ-SIGNED-MAX
0x5342584A4F425356 CONSTANT _SBXJ-MAGIC  \ "SBXJOBSV"

\ =====================================================================
\  Measured service and inline jobs
\ =====================================================================

  0 CONSTANT _SBXJ-MAGIC-OFF
  8 CONSTANT _SBXJ-SELF
 16 CONSTANT _SBXJ-SIZE
 24 CONSTANT _SBXJ-STATE
 32 CONSTANT _SBXJ-CAPACITY
 40 CONSTANT _SBXJ-OWNER-CORE
 48 CONSTANT _SBXJ-PARENT
 56 CONSTANT _SBXJ-ACTIVATION-ID
 64 CONSTANT _SBXJ-NEXT-GENERATION
 72 CONSTANT _SBXJ-CURSOR
 80 CONSTANT _SBXJ-LIVE-N
 88 CONSTANT _SBXJ-RUNNABLE-N
 96 CONSTANT _SBXJ-SLICE-STEPS
104 CONSTANT _SBXJ-ALLOWANCE-MS
112 CONSTANT _SBXJ-POLICY
\ SUBMIT's scratch: the effective limits and the value limits they
\ materialize.  Both are zero outside SUBMIT.
_SBXJ-POLICY SBOX-LIMITS-SIZE + CONSTANT _SBXJ-EFFECTIVE
_SBXJ-EFFECTIVE SBOX-LIMITS-SIZE + CONSTANT _SBXJ-VALUE-LIMITS
_SBXJ-VALUE-LIMITS SBOX-VALUE-LIMITS-SIZE +
    CONSTANT SBOX-JOB-SERVICE-HEADER-SIZE

 0 CONSTANT _SBXJS-STATE
 8 CONSTANT _SBXJS-GENERATION
16 CONSTANT _SBXJS-OWNER-ID
24 CONSTANT _SBXJS-OWNER-GENERATION
32 CONSTANT _SBXJS-RUN-STATE
40 CONSTANT _SBXJS-STATUS
48 CONSTANT _SBXJS-DEADLINE
56 CONSTANT _SBXJS-HOST
_SBXJS-HOST SBOX-HOST-INVOCATION-SIZE + CONSTANT _SBXJS-SIZE

: _SBXJ.MAGIC            ( service -- address ) _SBXJ-MAGIC-OFF + ;
: _SBXJ.SELF             ( service -- address ) _SBXJ-SELF + ;
: _SBXJ.SIZE             ( service -- address ) _SBXJ-SIZE + ;
: _SBXJ.STATE            ( service -- address ) _SBXJ-STATE + ;
: _SBXJ.CAPACITY         ( service -- address ) _SBXJ-CAPACITY + ;
: _SBXJ.OWNER-CORE       ( service -- address ) _SBXJ-OWNER-CORE + ;
: _SBXJ.PARENT           ( service -- address ) _SBXJ-PARENT + ;
: _SBXJ.ACTIVATION-ID    ( service -- address ) _SBXJ-ACTIVATION-ID + ;
: _SBXJ.NEXT-GENERATION  ( service -- address )
    _SBXJ-NEXT-GENERATION + ;
: _SBXJ.CURSOR           ( service -- address ) _SBXJ-CURSOR + ;
: _SBXJ.LIVE-N           ( service -- address ) _SBXJ-LIVE-N + ;
: _SBXJ.RUNNABLE-N       ( service -- address ) _SBXJ-RUNNABLE-N + ;
: _SBXJ.SLICE-STEPS      ( service -- address ) _SBXJ-SLICE-STEPS + ;
: _SBXJ.ALLOWANCE-MS     ( service -- address ) _SBXJ-ALLOWANCE-MS + ;
: _SBXJ.POLICY           ( service -- limits ) _SBXJ-POLICY + ;
: _SBXJ.EFFECTIVE        ( service -- limits ) _SBXJ-EFFECTIVE + ;
: _SBXJ.VALUE-LIMITS     ( service -- limits ) _SBXJ-VALUE-LIMITS + ;

: _SBXJS.STATE             ( job -- address ) _SBXJS-STATE + ;
: _SBXJS.GENERATION        ( job -- address ) _SBXJS-GENERATION + ;
: _SBXJS.OWNER-ID          ( job -- address ) _SBXJS-OWNER-ID + ;
: _SBXJS.OWNER-GENERATION  ( job -- address )
    _SBXJS-OWNER-GENERATION + ;
: _SBXJS.RUN-STATE         ( job -- address ) _SBXJS-RUN-STATE + ;
: _SBXJS.STATUS            ( job -- address ) _SBXJS-STATUS + ;
: _SBXJS.DEADLINE          ( job -- address ) _SBXJS-DEADLINE + ;
: _SBXJS.HOST              ( job -- host ) _SBXJS-HOST + ;

: _SBXJ-JOB  ( index service -- job )
    SBOX-JOB-SERVICE-HEADER-SIZE + SWAP _SBXJS-SIZE * + ;

\ Capacity has no policy ceiling here.  It is limited only by the
\ positive signed byte span that can hold the header and inline jobs.
: SBOX-JOB-SERVICE-MEASURE  ( capacity -- service-u|0 status )
    DUP 1 < IF DROP 0 SBOX-JOB-S-INVALID EXIT THEN
    DUP _SBXJ-SIGNED-MAX SBOX-JOB-SERVICE-HEADER-SIZE -
        _SBXJS-SIZE / > IF
        DROP 0 SBOX-JOB-S-CAPACITY EXIT
    THEN
    _SBXJS-SIZE * SBOX-JOB-SERVICE-HEADER-SIZE +
    SBOX-JOB-S-OK ;

: _SBXJ-SPAN?  ( address length -- flag )
    2DUP MSPAN-NONWRAPPING? 0= IF 2DROP 0 EXIT THEN
    CALLER-SPAN-STATUS CALLER-SPAN-S-OK = ;

: _SBXJ-ZERO?  ( address length -- flag )
    2DUP OR 7 AND IF 2DROP 0 EXIT THEN
    8 / 0 ?DO
        DUP I 8 * + @ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

\ Records the first failure of a sweep in CELL.
: _SBXJ-FIRST!  ( status cell -- )
    OVER 0= IF 2DROP EXIT THEN
    DUP @ IF 2DROP EXIT THEN
    ! ;

: _SBXJ-TERMINAL?  ( run-state -- flag )
    DUP SBOX-VM-RUN-COMPLETE >= SWAP SBOX-VM-RUN-CANCELLED <= AND ;

\ =====================================================================
\  Service and job shape
\ =====================================================================

: _SBXJ-HEADER?  ( service -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP 7 AND IF DROP 0 EXIT THEN
    DUP SBOX-JOB-SERVICE-HEADER-SIZE _SBXJ-SPAN? 0= IF DROP 0 EXIT THEN
    DUP _SBXJ.MAGIC @ _SBXJ-MAGIC <> IF DROP 0 EXIT THEN
    DUP _SBXJ.SELF @ OVER <> IF DROP 0 EXIT THEN
    DUP _SBXJ.CAPACITY @ SBOX-JOB-SERVICE-MEASURE IF 2DROP 0 EXIT THEN
    OVER _SBXJ.SIZE @ <> IF DROP 0 EXIT THEN
    DUP DUP _SBXJ.SIZE @ _SBXJ-SPAN? 0= IF DROP 0 EXIT THEN
    _SBXJ.STATE @ DUP SBOX-JOB-SERVICE-STATE-OPEN >=
    SWAP SBOX-JOB-SERVICE-STATE-DRAINED <= AND ;

: _SBXJ-DRAINED?  ( service -- flag )
    _SBXJ.STATE @ SBOX-JOB-SERVICE-STATE-DRAINED = ;

\ An open or closing service whose counters and policy are consistent.
: _SBXJ-LIVE?  ( service -- flag )
    DUP _SBXJ-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _SBXJ-DRAINED? IF DROP 0 EXIT THEN
    DUP _SBXJ.ACTIVATION-ID @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXJ.NEXT-GENERATION @ 0< IF DROP 0 EXIT THEN
    DUP _SBXJ.CURSOR @ OVER _SBXJ.CAPACITY @ U< 0= IF DROP 0 EXIT THEN
    DUP _SBXJ.LIVE-N @ OVER _SBXJ.CAPACITY @ U> IF DROP 0 EXIT THEN
    DUP _SBXJ.RUNNABLE-N @ OVER _SBXJ.LIVE-N @ U> IF DROP 0 EXIT THEN
    DUP _SBXJ.SLICE-STEPS @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXJ.ALLOWANCE-MS @ 0> 0= IF DROP 0 EXIT THEN
    _SBXJ.POLICY SBOX-LIMITS-BOUNDED? ;

: SBOX-JOB-SERVICE-VALID?  ( service -- flag )
    DUP _SBXJ-HEADER? 0= IF DROP 0 EXIT THEN
    DUP _SBXJ-DRAINED? IF
        DUP _SBXJ.OWNER-CORE
        SWAP _SBXJ.SIZE @ _SBXJ-OWNER-CORE - _SBXJ-ZERO? EXIT
    THEN
    _SBXJ-LIVE? ;

\ The common prologue of every operation on a live service.
: _SBXJ-ENTER  ( service -- status )
    DUP _SBXJ-HEADER? 0= IF DROP SBOX-JOB-S-INVALID EXIT THEN
    DUP _SBXJ-DRAINED? IF DROP SBOX-JOB-S-STATE EXIT THEN
    DUP _SBXJ-LIVE? 0= IF DROP SBOX-JOB-S-INVALID EXIT THEN
    _SBXJ.OWNER-CORE @ COREID =
    IF SBOX-JOB-S-OK ELSE SBOX-JOB-S-WRONG-CORE THEN ;

: SBOX-JOB-SERVICE-OWNER?  ( service -- flag )
    DUP _SBXJ-LIVE? IF _SBXJ.OWNER-CORE @ COREID = ELSE DROP 0 THEN ;

: _SBXJ-JOB-SHAPE?  ( job -- flag )
    DUP _SBXJS.STATE @ DUP SBOX-JOB-STATE-RUNNABLE >=
        SWAP SBOX-JOB-STATE-FAILED <= AND 0= IF DROP 0 EXIT THEN
    DUP _SBXJS.GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXJS.OWNER-ID @ 0> 0= IF DROP 0 EXIT THEN
    DUP _SBXJS.OWNER-GENERATION @ 0> 0= IF DROP 0 EXIT THEN
    _SBXJS.STATUS @ SBOX-JOB-STATUS-VALID? ;

: _SBXJ-HOST>STATUS  ( host-status -- status )
    DUP SBOX-HOST-S-INPUT = IF DROP SBOX-JOB-S-INPUT EXIT THEN
    DUP SBOX-HOST-S-NOMEM = IF DROP SBOX-JOB-S-NOMEM EXIT THEN
    DUP SBOX-HOST-S-ENTRY = IF DROP SBOX-JOB-S-ENTRY EXIT THEN
    DUP SBOX-HOST-S-BUDGET = IF DROP SBOX-JOB-S-LIMITS EXIT THEN
    DUP SBOX-HOST-S-ALIAS = IF DROP SBOX-JOB-S-ALIAS EXIT THEN
    DUP SBOX-HOST-S-RESULT = IF DROP SBOX-JOB-S-RESULT EXIT THEN
    DUP SBOX-HOST-S-STATE = IF DROP SBOX-JOB-S-STATE EXIT THEN
    DUP SBOX-HOST-S-CONTEXT = IF DROP SBOX-JOB-S-STATE EXIT THEN
    DROP SBOX-JOB-S-HOST ;

\ =====================================================================
\  Job transitions
\ =====================================================================

\ Records the host's run state for a job that was runnable.
: _SBXJ-SETTLE  ( run-state job service -- status )
    >R
    OVER SBOX-VM-RUN-RUNNABLE = IF
        _SBXJS.RUN-STATE ! R> DROP SBOX-JOB-S-OK EXIT
    THEN
    -1 R> _SBXJ.RUNNABLE-N +!
    OVER _SBXJ-TERMINAL? IF
        TUCK _SBXJS.RUN-STATE !
        SBOX-JOB-STATE-READY SWAP _SBXJS.STATE !
        SBOX-JOB-S-OK EXIT
    THEN
    TUCK _SBXJS.RUN-STATE !
    SBOX-JOB-S-HOST OVER _SBXJS.STATUS !
    SBOX-JOB-STATE-FAILED SWAP _SBXJS.STATE !
    SBOX-JOB-S-HOST ;

\ Cancels a runnable job; it becomes ready with a cancelled result.
: _SBXJ-CANCEL-JOB  ( detail job service -- status )
    >R
    TUCK _SBXJS.HOST SBOX-HOST-CANCEL IF
        SBOX-VM-RUN-INVALID SWAP R> _SBXJ-SETTLE EXIT
    THEN
    DUP _SBXJS.HOST SBOX-HOST-RUN-STATE@ SWAP R> _SBXJ-SETTLE ;

\ A finished job whose host no longer proves its own graph.
: _SBXJ-HOST-LOST  ( job -- )
    SBOX-JOB-S-HOST OVER _SBXJS.STATUS !
    SBOX-JOB-STATE-FAILED SWAP _SBXJS.STATE ! ;

\ Releases a job's host and frees the job.  A host that cannot prove it
\ owns its graph is an invariant failure, so the job is kept and nothing
\ it points at is freed.
: _SBXJ-DISCARD  ( job service -- status )
    >R
    DUP _SBXJS.STATE @ SBOX-JOB-STATE-FREE = IF
        DROP R> DROP SBOX-JOB-S-OK EXIT
    THEN
    DUP _SBXJS.STATE @ SBOX-JOB-STATE-RUNNABLE =
    OVER _SBXJS.HOST SBOX-HOST-RELEASE IF
        IF -1 R@ _SBXJ.RUNNABLE-N +! THEN
        _SBXJ-HOST-LOST R> DROP SBOX-JOB-S-HOST EXIT
    THEN
    IF -1 R@ _SBXJ.RUNNABLE-N +! THEN
    _SBXJS-SIZE 0 FILL
    -1 R> _SBXJ.LIVE-N +!
    SBOX-JOB-S-OK ;

\ =====================================================================
\  Initialization
\ =====================================================================

\ INIT is caller-serialized.  These cells stage its arguments while they
\ are validated, before the service is written.
VARIABLE _SBXJI-PARENT
VARIABLE _SBXJI-POLICY
VARIABLE _SBXJI-SLICE
VARIABLE _SBXJI-ALLOWANCE
VARIABLE _SBXJI-ACTIVATION
VARIABLE _SBXJI-CAPACITY
VARIABLE _SBXJI-SERVICE
VARIABLE _SBXJI-SERVICE-U

: _SBXJI-OVERLAP?  ( address length -- flag )
    _SBXJI-SERVICE @ _SBXJI-SERVICE-U @ MSPAN-OVERLAP? ;

: _SBXJI-BOUNDARY  ( -- status )
    _SBXJI-CAPACITY @ SBOX-JOB-SERVICE-MEASURE ?DUP IF NIP EXIT THEN
    _SBXJI-SERVICE-U @ <> IF SBOX-JOB-S-CAPACITY EXIT THEN
    _SBXJI-SERVICE @ DUP 0= SWAP 7 AND OR IF
        SBOX-JOB-S-INVALID EXIT
    THEN
    _SBXJI-SERVICE @ _SBXJI-SERVICE-U @ _SBXJ-SPAN? 0= IF
        SBOX-JOB-S-INVALID EXIT
    THEN
    _SBXJI-SERVICE @ _SBXJI-SERVICE-U @ _SBXJ-ZERO? 0= IF
        SBOX-JOB-S-STATE EXIT
    THEN
    _SBXJI-PARENT @ DUP CTX-VALID? 0= IF DROP SBOX-JOB-S-INVALID EXIT THEN
    DUP CTX.FLAGS @ CTX-F-ACTIVE AND 0= IF
        DROP SBOX-JOB-S-INVALID EXIT
    THEN
    CTX.FLAGS @ CTX-F-RECOVERY AND IF SBOX-JOB-S-INVALID EXIT THEN
    _SBXJI-PARENT @ CTX-SIZE _SBXJI-OVERLAP? IF SBOX-JOB-S-ALIAS EXIT THEN
    _SBXJI-POLICY @ SBOX-LIMITS-BOUNDED? 0= IF SBOX-JOB-S-LIMITS EXIT THEN
    _SBXJI-POLICY @ SBOX-LIMITS-SIZE _SBXJI-OVERLAP? IF
        SBOX-JOB-S-ALIAS EXIT
    THEN
    _SBXJI-SLICE @ 0> 0= IF SBOX-JOB-S-INVALID EXIT THEN
    _SBXJI-ALLOWANCE @ 0> 0= IF SBOX-JOB-S-INVALID EXIT THEN
    _SBXJI-ACTIVATION @ 0> 0= IF SBOX-JOB-S-INVALID EXIT THEN
    SBOX-JOB-S-OK ;

: SBOX-JOB-SERVICE-INIT
  ( parent policy slice-steps allowance-ms activation-id capacity service service-u -- status )
    _SBXJI-SERVICE-U ! _SBXJI-SERVICE ! _SBXJI-CAPACITY !
    _SBXJI-ACTIVATION ! _SBXJI-ALLOWANCE ! _SBXJI-SLICE !
    _SBXJI-POLICY ! _SBXJI-PARENT !
    _SBXJI-BOUNDARY ?DUP IF EXIT THEN

    _SBXJI-SERVICE @ >R
    R@ R@ _SBXJ.SELF !
    _SBXJI-SERVICE-U @ R@ _SBXJ.SIZE !
    SBOX-JOB-SERVICE-STATE-OPEN R@ _SBXJ.STATE !
    _SBXJI-CAPACITY @ R@ _SBXJ.CAPACITY !
    COREID R@ _SBXJ.OWNER-CORE !
    _SBXJI-PARENT @ R@ _SBXJ.PARENT !
    _SBXJI-ACTIVATION @ R@ _SBXJ.ACTIVATION-ID !
    _SBXJI-SLICE @ R@ _SBXJ.SLICE-STEPS !
    _SBXJI-ALLOWANCE @ R@ _SBXJ.ALLOWANCE-MS !
    _SBXJI-POLICY @ R@ _SBXJ.POLICY SBOX-LIMITS-COPY IF
        R@ _SBXJI-SERVICE-U @ 0 FILL
        R> DROP SBOX-JOB-S-LIMITS EXIT
    THEN
    _SBXJ-MAGIC R@ _SBXJ.MAGIC !
    R> DROP SBOX-JOB-S-OK ;

\ =====================================================================
\  Owner-scoped job lookup
\ =====================================================================

VARIABLE _SBXJL-SERVICE
VARIABLE _SBXJL-GENERATION
VARIABLE _SBXJL-OWNER-ID
VARIABLE _SBXJL-OWNER-GENERATION

\ On success _SBXJL-SERVICE holds the service for the caller's next step.
: _SBXJ-FIND
  ( activation-id job-generation owner-id owner-generation service -- job|0 status )
    DUP _SBXJ-ENTER ?DUP IF
        >R 2DROP 2DROP DROP 0 R> EXIT
    THEN
    _SBXJL-SERVICE !
    _SBXJL-OWNER-GENERATION ! _SBXJL-OWNER-ID ! _SBXJL-GENERATION !
    _SBXJL-SERVICE @ _SBXJ.ACTIVATION-ID @ <> IF
        0 SBOX-JOB-S-STALE EXIT
    THEN
    _SBXJL-GENERATION @ 0> 0= IF 0 SBOX-JOB-S-STALE EXIT THEN
    _SBXJL-OWNER-ID @ 0> _SBXJL-OWNER-GENERATION @ 0> AND 0= IF
        0 SBOX-JOB-S-NOT-OWNER EXIT
    THEN
    _SBXJL-SERVICE @ _SBXJ.CAPACITY @ 0 ?DO
        I _SBXJL-SERVICE @ _SBXJ-JOB
        DUP _SBXJS.STATE @ SBOX-JOB-STATE-FREE <>
        OVER _SBXJS.GENERATION @ _SBXJL-GENERATION @ = AND IF
            DUP _SBXJ-JOB-SHAPE? 0= IF
                DROP 0 SBOX-JOB-S-INVALID UNLOOP EXIT
            THEN
            DUP _SBXJS.OWNER-ID @ _SBXJL-OWNER-ID @ =
            OVER _SBXJS.OWNER-GENERATION @
                _SBXJL-OWNER-GENERATION @ = AND IF
                SBOX-JOB-S-OK UNLOOP EXIT
            THEN
            DROP 0 SBOX-JOB-S-NOT-OWNER UNLOOP EXIT
        THEN
        DROP
    LOOP
    0 SBOX-JOB-S-NOT-FOUND ;

\ =====================================================================
\  Transactional submission
\ =====================================================================

VARIABLE _SBXJSUB-PLAN
VARIABLE _SBXJSUB-ENTRY
VARIABLE _SBXJSUB-ENTRY-U
VARIABLE _SBXJSUB-INPUT
VARIABLE _SBXJSUB-INPUT-U
VARIABLE _SBXJSUB-REQUEST
VARIABLE _SBXJSUB-OWNER-ID
VARIABLE _SBXJSUB-OWNER-GENERATION
VARIABLE _SBXJSUB-SERVICE
VARIABLE _SBXJSUB-JOB
VARIABLE _SBXJSUB-INDEX

: _SBXJSUB-OVERLAP?  ( address length -- flag )
    _SBXJSUB-SERVICE @ DUP _SBXJ.SIZE @ MSPAN-OVERLAP? ;

\ A plan the service can run: verified, pure and without imports.
: _SBXJ-PURE-PLAN?  ( plan -- flag )
    DUP SBOX-PLAN-VALID? 0= IF DROP 0 EXIT THEN
    DUP SBOX-PLAN-IMPORT-N@ IF DROP 0 EXIT THEN
    SBOX-PLAN-PROFILE@ DUP SBOX-PROFILE-VALID? 0= IF DROP 0 EXIT THEN
    SBOX-PROFILE-TAG@ IF DROP 0 EXIT THEN
    SBOX-PROFILE-PURE-TAG = ;

: _SBXJSUB-FREE  ( -- job|0 )
    _SBXJSUB-SERVICE @ _SBXJ.CAPACITY @ 0 ?DO
        I _SBXJSUB-SERVICE @ _SBXJ-JOB
        DUP _SBXJS.STATE @ SBOX-JOB-STATE-FREE = IF UNLOOP EXIT THEN
        DROP
    LOOP
    0 ;

: _SBXJSUB-ENTRY-STATUS  ( -- status )
    _SBXJSUB-ENTRY @ _SBXJSUB-ENTRY-U @ _SBXJSUB-PLAN @
        SBOX-HOST-ENTRY-RESOLVE-EXACT IF
        DROP SBOX-JOB-S-ENTRY EXIT
    THEN
    DUP _SBXJSUB-INDEX !
    _SBXJSUB-PLAN @ SBOX-PLAN-ENTRY-SIGNATURE@ 0= IF
        DROP SBOX-JOB-S-ENTRY EXIT
    THEN
    SBOX-ABI-SIGNATURE-VALUE-TO-VALUE =
    IF SBOX-JOB-S-OK ELSE SBOX-JOB-S-ENTRY THEN ;

: _SBXJSUB-BOUNDARY  ( -- status )
    _SBXJSUB-SERVICE @ _SBXJ-ENTER ?DUP IF EXIT THEN
    _SBXJSUB-SERVICE @ _SBXJ.STATE @
        SBOX-JOB-SERVICE-STATE-OPEN <> IF SBOX-JOB-S-STATE EXIT THEN
    _SBXJSUB-OWNER-ID @ 0> _SBXJSUB-OWNER-GENERATION @ 0> AND 0= IF
        SBOX-JOB-S-NOT-OWNER EXIT
    THEN
    _SBXJSUB-SERVICE @ _SBXJ.NEXT-GENERATION @
        _SBXJ-SIGNED-MAX >= IF SBOX-JOB-S-STATE EXIT THEN
    _SBXJSUB-PLAN @ _SBXJ-PURE-PLAN? 0= IF SBOX-JOB-S-PROFILE EXIT THEN
    _SBXJSUB-PLAN @ DUP SBOX-PLAN-TOTAL@ _SBXJSUB-OVERLAP? IF
        SBOX-JOB-S-ALIAS EXIT
    THEN
    _SBXJSUB-ENTRY-STATUS ?DUP IF EXIT THEN
    _SBXJSUB-INPUT-U @ 0> 0= IF SBOX-JOB-S-INPUT EXIT THEN
    _SBXJSUB-INPUT @ _SBXJSUB-INPUT-U @ _SBXJ-SPAN? 0= IF
        SBOX-JOB-S-INPUT EXIT
    THEN
    _SBXJSUB-INPUT @ _SBXJSUB-INPUT-U @ _SBXJSUB-OVERLAP? IF
        SBOX-JOB-S-ALIAS EXIT
    THEN
    _SBXJSUB-REQUEST @ ?DUP IF
        DUP SBOX-LIMITS-VALID? 0= IF DROP SBOX-JOB-S-LIMITS EXIT THEN
        SBOX-LIMITS-SIZE _SBXJSUB-OVERLAP? IF SBOX-JOB-S-ALIAS EXIT THEN
    THEN
    _SBXJSUB-FREE ?DUP 0= IF SBOX-JOB-S-FULL EXIT THEN
    _SBXJSUB-JOB !
    SBOX-JOB-S-OK ;

: _SBXJSUB-SCRUB  ( -- )
    _SBXJSUB-SERVICE @ _SBXJ.EFFECTIVE
    SBOX-LIMITS-SIZE SBOX-VALUE-LIMITS-SIZE + 0 FILL ;

\ The effective limits: the policy, narrowed by the request and by the
\ plan's profile.
: _SBXJSUB-LIMITS  ( -- instruction value-ops copy wall-ms status )
    _SBXJSUB-SERVICE @ >R
    R@ _SBXJ.POLICY R@ _SBXJ.EFFECTIVE SBOX-LIMITS-COPY IF
        R> DROP 0 0 0 0 SBOX-JOB-S-LIMITS EXIT
    THEN
    _SBXJSUB-REQUEST @ ?DUP IF
        R@ _SBXJ.EFFECTIVE SBOX-LIMITS-MEET IF
            R> DROP 0 0 0 0 SBOX-JOB-S-LIMITS EXIT
        THEN
    THEN
    _SBXJSUB-PLAN @ SBOX-PLAN-PROFILE@
        R@ _SBXJ.EFFECTIVE SBOX-LIMITS-PROFILE-MEET IF
        R> DROP 0 0 0 0 SBOX-JOB-S-LIMITS EXIT
    THEN
    R@ _SBXJ.EFFECTIVE R@ _SBXJ.VALUE-LIMITS
        SBOX-LIMITS-MATERIALIZE IF
        2DROP DROP R> DROP 0 0 0 0 SBOX-JOB-S-LIMITS EXIT
    THEN
    SBOX-LIMIT-WALL-MS R@ _SBXJ.EFFECTIVE SBOX-LIMIT@ DROP
    R> DROP SBOX-JOB-S-OK ;

: _SBXJ-DEADLINE  ( wall-ms -- deadline )
    MS@ 2DUP _SBXJ-SIGNED-MAX SWAP - > IF
        2DROP _SBXJ-SIGNED-MAX EXIT
    THEN
    + ;

: _SBXJSUB-HOST  ( instruction value-ops copy -- status )
    >R >R >R
    _SBXJSUB-SERVICE @ _SBXJ.PARENT @
    _SBXJSUB-PLAN @
    _SBXJSUB-INDEX @
    _SBXJSUB-INPUT @ _SBXJSUB-INPUT-U @
    _SBXJSUB-SERVICE @ _SBXJ.VALUE-LIMITS
    R> R> R>
    _SBXJSUB-JOB @ _SBXJS.HOST
    SBOX-HOST-INIT ;

: _SBXJSUB-PUBLISH  ( deadline -- activation-id job-generation )
    _SBXJSUB-JOB @ >R
    R@ _SBXJS.DEADLINE !
    _SBXJSUB-SERVICE @ _SBXJ.NEXT-GENERATION DUP 1 SWAP +! @
        R@ _SBXJS.GENERATION !
    _SBXJSUB-OWNER-ID @ R@ _SBXJS.OWNER-ID !
    _SBXJSUB-OWNER-GENERATION @ R@ _SBXJS.OWNER-GENERATION !
    SBOX-VM-RUN-RUNNABLE R@ _SBXJS.RUN-STATE !
    SBOX-JOB-S-OK R@ _SBXJS.STATUS !
    SBOX-JOB-STATE-RUNNABLE R@ _SBXJS.STATE !
    1 _SBXJSUB-SERVICE @ _SBXJ.LIVE-N +!
    1 _SBXJSUB-SERVICE @ _SBXJ.RUNNABLE-N +!
    _SBXJSUB-SERVICE @ _SBXJ.ACTIVATION-ID @
    R> _SBXJS.GENERATION @ ;

: SBOX-JOB-SUBMIT
  ( plan entry entry-u input input-u request|0 owner-id owner-generation service -- activation-id|0 job-generation|0 status )
    _SBXJSUB-SERVICE !
    _SBXJSUB-OWNER-GENERATION ! _SBXJSUB-OWNER-ID !
    _SBXJSUB-REQUEST !
    _SBXJSUB-INPUT-U ! _SBXJSUB-INPUT !
    _SBXJSUB-ENTRY-U ! _SBXJSUB-ENTRY !
    _SBXJSUB-PLAN !
    _SBXJSUB-BOUNDARY ?DUP IF 0 0 ROT EXIT THEN
    _SBXJSUB-LIMITS ?DUP IF
        >R 2DROP 2DROP _SBXJSUB-SCRUB 0 0 R> EXIT
    THEN
    _SBXJ-DEADLINE >R
    _SBXJSUB-HOST ?DUP IF
        R> DROP
        _SBXJSUB-JOB @ _SBXJS-SIZE 0 FILL
        _SBXJSUB-SCRUB
        _SBXJ-HOST>STATUS 0 0 ROT EXIT
    THEN
    _SBXJSUB-SCRUB
    R> _SBXJSUB-PUBLISH SBOX-JOB-S-OK ;

\ =====================================================================
\  Running jobs within an allowance
\ =====================================================================

VARIABLE _SBXJT-SERVICE
VARIABLE _SBXJT-START
VARIABLE _SBXJT-FIRST

\ The next runnable job from the cursor; the cursor moves past it.
: _SBXJT-NEXT  ( -- job|0 )
    _SBXJT-SERVICE @ _SBXJ.CAPACITY @ 0 ?DO
        _SBXJT-SERVICE @ _SBXJ.CURSOR @ I +
        _SBXJT-SERVICE @ _SBXJ.CAPACITY @ MOD
        DUP _SBXJT-SERVICE @ _SBXJ-JOB
        DUP _SBXJS.STATE @ SBOX-JOB-STATE-RUNNABLE = IF
            SWAP 1+ _SBXJT-SERVICE @ _SBXJ.CAPACITY @ MOD
            _SBXJT-SERVICE @ _SBXJ.CURSOR !
            UNLOOP EXIT
        THEN
        2DROP
    LOOP
    0 ;

\ One slice of a runnable job, or its cancellation once its deadline
\ has passed.
: _SBXJT-STEP  ( job -- status )
    MS@ OVER _SBXJS.DEADLINE @ >= IF
        SBOX-VM-CANCEL-DEADLINE SWAP _SBXJT-SERVICE @ _SBXJ-CANCEL-JOB EXIT
    THEN
    _SBXJT-SERVICE @ _SBXJ.SLICE-STEPS @
    OVER _SBXJS.HOST SBOX-HOST-RUN-SLICE
    SWAP _SBXJT-SERVICE @ _SBXJ-SETTLE ;

: _SBXJT-SPENT?  ( -- flag )
    MS@ _SBXJT-START @ -
    _SBXJT-SERVICE @ _SBXJ.ALLOWANCE-MS @ >= ;

\ Returns the first job failure of the tick, after running the rest.
: SBOX-JOB-SERVICE-TICK  ( service -- status )
    DUP _SBXJ-ENTER ?DUP IF NIP EXIT THEN
    DUP _SBXJ.STATE @ SBOX-JOB-SERVICE-STATE-OPEN <> IF
        DROP SBOX-JOB-S-STATE EXIT
    THEN
    _SBXJT-SERVICE !
    0 _SBXJT-FIRST !
    MS@ _SBXJT-START !
    BEGIN
        _SBXJT-SERVICE @ _SBXJ.RUNNABLE-N @ 0>
    WHILE
        _SBXJT-NEXT ?DUP 0= IF SBOX-JOB-S-INVALID EXIT THEN
        _SBXJT-STEP _SBXJT-FIRST _SBXJ-FIRST!
        _SBXJT-SPENT? IF _SBXJT-FIRST @ EXIT THEN
    REPEAT
    _SBXJT-FIRST @ ;

\ =====================================================================
\  Owner-scoped query, cancellation, result, and discard
\ =====================================================================

: SBOX-JOB-QUERY
  ( activation-id job-generation owner-id owner-generation service -- job-state run-state last-status status )
    _SBXJ-FIND ?DUP IF
        NIP >R SBOX-JOB-STATE-FREE SBOX-VM-RUN-INVALID SBOX-JOB-S-OK R> EXIT
    THEN
    DUP _SBXJS.STATE @
    OVER _SBXJS.RUN-STATE @
    ROT _SBXJS.STATUS @
    SBOX-JOB-S-OK ;

\ A ready job is already settled, and a failed job reports its failure.
: SBOX-JOB-CANCEL
  ( activation-id job-generation owner-id owner-generation service -- status )
    _SBXJ-FIND ?DUP IF NIP EXIT THEN
    DUP _SBXJS.STATE @
    DUP SBOX-JOB-STATE-READY = IF 2DROP SBOX-JOB-S-OK EXIT THEN
    SBOX-JOB-STATE-FAILED = IF _SBXJS.STATUS @ EXIT THEN
    SBOX-VM-CANCEL-CALLER SWAP _SBXJL-SERVICE @ _SBXJ-CANCEL-JOB ;

\ Measuring settles the result: the VM may still turn a malformed
\ returned value into a terminal guest failure.
: SBOX-JOB-RESULT-MEASURE
  ( activation-id job-generation owner-id owner-generation service -- result-u|0 status )
    _SBXJ-FIND ?DUP IF EXIT THEN
    DUP _SBXJS.STATE @
    DUP SBOX-JOB-STATE-RUNNABLE = IF 2DROP 0 SBOX-JOB-S-STATE EXIT THEN
    SBOX-JOB-STATE-FAILED = IF _SBXJS.STATUS @ 0 SWAP EXIT THEN
    DUP _SBXJS.HOST SBOX-HOST-RESULT-MEASURE IF
        DROP _SBXJ-HOST-LOST 0 SBOX-JOB-S-HOST EXIT
    THEN
    SWAP DUP _SBXJS.HOST SBOX-HOST-RUN-STATE@ SWAP _SBXJS.RUN-STATE !
    SBOX-JOB-S-OK ;

\ Writes the self-contained VM result into the caller's buffer and frees
\ the job.  A buffer that is too small leaves the job ready.
: SBOX-JOB-RESULT-TAKE
  ( result result-capacity activation-id job-generation owner-id owner-generation service -- status )
    _SBXJ-FIND ?DUP IF NIP NIP NIP EXIT THEN
    DUP _SBXJS.STATE @
    DUP SBOX-JOB-STATE-RUNNABLE = IF
        2DROP 2DROP SBOX-JOB-S-STATE EXIT
    THEN
    SBOX-JOB-STATE-FAILED = IF _SBXJS.STATUS @ NIP NIP EXIT THEN
    2 PICK 2 PICK _SBXJ-SPAN? 0= IF DROP 2DROP SBOX-JOB-S-RESULT EXIT THEN
    2 PICK 2 PICK _SBXJL-SERVICE @ DUP _SBXJ.SIZE @
        MSPAN-OVERLAP? IF DROP 2DROP SBOX-JOB-S-ALIAS EXIT THEN
    >R R@ _SBXJS.HOST SBOX-HOST-FINISH ?DUP IF
        DUP SBOX-HOST-S-INVALID = IF R@ _SBXJ-HOST-LOST THEN
        R> DROP _SBXJ-HOST>STATUS EXIT
    THEN
    R> _SBXJL-SERVICE @ _SBXJ-DISCARD ;

: SBOX-JOB-DISCARD
  ( activation-id job-generation owner-id owner-generation service -- status )
    _SBXJ-FIND ?DUP IF NIP EXIT THEN
    _SBXJL-SERVICE @ _SBXJ-DISCARD ;

VARIABLE _SBXJOD-SERVICE
VARIABLE _SBXJOD-ID
VARIABLE _SBXJOD-GENERATION
VARIABLE _SBXJOD-FIRST

: _SBXJOD-OWNED?  ( job -- flag )
    DUP _SBXJS.STATE @ SBOX-JOB-STATE-FREE <>
    OVER _SBXJS.OWNER-ID @ _SBXJOD-ID @ = AND
    SWAP _SBXJS.OWNER-GENERATION @ _SBXJOD-GENERATION @ = AND ;

\ The host calls this while it can still name a closing owner, before
\ that owner's identity may be reused.
: SBOX-JOB-OWNER-DRAIN  ( owner-id owner-generation service -- status )
    DUP _SBXJ-ENTER ?DUP IF NIP NIP NIP EXIT THEN
    _SBXJOD-SERVICE ! _SBXJOD-GENERATION ! _SBXJOD-ID !
    _SBXJOD-ID @ 0> _SBXJOD-GENERATION @ 0> AND 0= IF
        SBOX-JOB-S-NOT-OWNER EXIT
    THEN
    0 _SBXJOD-FIRST !
    _SBXJOD-SERVICE @ _SBXJ.CAPACITY @ 0 ?DO
        I _SBXJOD-SERVICE @ _SBXJ-JOB
        DUP _SBXJOD-OWNED? IF
            _SBXJOD-SERVICE @ _SBXJ-DISCARD _SBXJOD-FIRST _SBXJ-FIRST!
        ELSE
            DROP
        THEN
    LOOP
    _SBXJOD-FIRST @ ;

\ =====================================================================
\  Whole-service close, drain, and release
\ =====================================================================

VARIABLE _SBXJCL-SERVICE
VARIABLE _SBXJCL-FIRST

\ Refuses new jobs and cancels runnable ones; finished results stay.
: SBOX-JOB-SERVICE-CLOSE  ( service -- status )
    DUP _SBXJ-HEADER? 0= IF DROP SBOX-JOB-S-INVALID EXIT THEN
    DUP _SBXJ-DRAINED? IF DROP SBOX-JOB-S-OK EXIT THEN
    DUP _SBXJ-ENTER ?DUP IF NIP EXIT THEN
    _SBXJCL-SERVICE !
    SBOX-JOB-SERVICE-STATE-CLOSING _SBXJCL-SERVICE @ _SBXJ.STATE !
    0 _SBXJCL-FIRST !
    _SBXJCL-SERVICE @ _SBXJ.CAPACITY @ 0 ?DO
        I _SBXJCL-SERVICE @ _SBXJ-JOB
        DUP _SBXJS.STATE @ SBOX-JOB-STATE-RUNNABLE = IF
            SBOX-VM-CANCEL-HOST-SHUTDOWN SWAP
            _SBXJCL-SERVICE @ _SBXJ-CANCEL-JOB _SBXJCL-FIRST _SBXJ-FIRST!
        ELSE
            DROP
        THEN
    LOOP
    _SBXJCL-FIRST @ ;

VARIABLE _SBXJDR-SERVICE
VARIABLE _SBXJDR-FIRST

: _SBXJ-DRAIN-CLEAR  ( service -- )
    DUP _SBXJ.OWNER-CORE
    OVER _SBXJ.SIZE @ _SBXJ-OWNER-CORE - 0 FILL
    SBOX-JOB-SERVICE-STATE-DRAINED SWAP _SBXJ.STATE ! ;

\ Discards every job.  The service ends its borrows only once no job
\ is left.
: SBOX-JOB-SERVICE-DRAIN  ( service -- status )
    DUP _SBXJ-HEADER? 0= IF DROP SBOX-JOB-S-INVALID EXIT THEN
    DUP _SBXJ-DRAINED? IF DROP SBOX-JOB-S-OK EXIT THEN
    DUP _SBXJ-ENTER ?DUP IF NIP EXIT THEN
    DUP _SBXJDR-SERVICE !
    SBOX-JOB-SERVICE-CLOSE _SBXJDR-FIRST !
    _SBXJDR-SERVICE @ _SBXJ.CAPACITY @ 0 ?DO
        I _SBXJDR-SERVICE @ _SBXJ-JOB
        DUP _SBXJS.STATE @ SBOX-JOB-STATE-FREE <> IF
            _SBXJDR-SERVICE @ _SBXJ-DISCARD _SBXJDR-FIRST _SBXJ-FIRST!
        ELSE
            DROP
        THEN
    LOOP
    _SBXJDR-SERVICE @ _SBXJ.LIVE-N @ 0= IF
        _SBXJDR-SERVICE @ _SBXJ-DRAIN-CLEAR
    THEN
    _SBXJDR-FIRST @ ;

VARIABLE _SBXJR-SERVICE
VARIABLE _SBXJR-SERVICE-U

: _SBXJR-GEOMETRY  ( -- status )
    _SBXJR-SERVICE-U @ SBOX-JOB-SERVICE-HEADER-SIZE <= IF
        SBOX-JOB-S-CAPACITY EXIT
    THEN
    _SBXJR-SERVICE-U @ SBOX-JOB-SERVICE-HEADER-SIZE -
    DUP _SBXJS-SIZE MOD IF DROP SBOX-JOB-S-CAPACITY EXIT THEN
    _SBXJS-SIZE / SBOX-JOB-SERVICE-MEASURE ?DUP IF NIP EXIT THEN
    _SBXJR-SERVICE-U @ <> IF SBOX-JOB-S-CAPACITY EXIT THEN
    _SBXJR-SERVICE @ DUP 0= SWAP 7 AND OR IF
        SBOX-JOB-S-INVALID EXIT
    THEN
    _SBXJR-SERVICE @ _SBXJR-SERVICE-U @ _SBXJ-SPAN? 0= IF
        SBOX-JOB-S-INVALID EXIT
    THEN
    SBOX-JOB-S-OK ;

\ Drains if needed and zeros the storage once nothing is left.
: SBOX-JOB-SERVICE-RELEASE  ( service service-u -- status )
    _SBXJR-SERVICE-U ! _SBXJR-SERVICE !
    _SBXJR-GEOMETRY ?DUP IF EXIT THEN
    _SBXJR-SERVICE @ _SBXJR-SERVICE-U @ _SBXJ-ZERO? IF
        SBOX-JOB-S-OK EXIT
    THEN
    _SBXJR-SERVICE @ _SBXJ-HEADER? 0= IF SBOX-JOB-S-INVALID EXIT THEN
    _SBXJR-SERVICE @ _SBXJ.SIZE @ _SBXJR-SERVICE-U @ <> IF
        SBOX-JOB-S-CAPACITY EXIT
    THEN
    _SBXJR-SERVICE @ SBOX-JOB-SERVICE-DRAIN
    _SBXJR-SERVICE @ _SBXJ-DRAINED? IF
        _SBXJR-SERVICE @ _SBXJR-SERVICE-U @ 0 FILL
    THEN ;

\ =====================================================================
\  Queries and audit
\ =====================================================================

: SBOX-JOB-SERVICE-STATE@  ( service -- state|0 )
    DUP SBOX-JOB-SERVICE-VALID? IF _SBXJ.STATE @ ELSE DROP 0 THEN ;

: SBOX-JOB-SERVICE-ACTIVATION@  ( service -- activation-id|0 )
    DUP _SBXJ-LIVE? IF _SBXJ.ACTIVATION-ID @ ELSE DROP 0 THEN ;

: SBOX-JOB-SERVICE-COUNT  ( service -- count )
    DUP _SBXJ-LIVE? IF _SBXJ.LIVE-N @ ELSE DROP 0 THEN ;

: SBOX-JOB-SERVICE-RUNNABLE  ( service -- count )
    DUP _SBXJ-LIVE? IF _SBXJ.RUNNABLE-N @ ELSE DROP 0 THEN ;

: SBOX-JOB-SERVICE-CAPACITY@  ( service -- capacity|0 )
    DUP _SBXJ-HEADER? IF _SBXJ.CAPACITY @ ELSE DROP 0 THEN ;

VARIABLE _SBXJA-SERVICE
VARIABLE _SBXJA-LIVE
VARIABLE _SBXJA-RUNNABLE

\ A free job is zero.  A runnable job's host runs, a ready job's host
\ is terminal, and a failed job records why it failed.
: _SBXJA-JOB?  ( job -- flag )
    DUP _SBXJS.STATE @ SBOX-JOB-STATE-FREE = IF
        _SBXJS-SIZE _SBXJ-ZERO? EXIT
    THEN
    DUP _SBXJ-JOB-SHAPE? 0= IF DROP 0 EXIT THEN
    DUP _SBXJS.GENERATION @
        _SBXJA-SERVICE @ _SBXJ.NEXT-GENERATION @ > IF DROP 0 EXIT THEN
    1 _SBXJA-LIVE +!
    DUP _SBXJS.STATE @ SBOX-JOB-STATE-FAILED = IF
        _SBXJS.STATUS @ 0<> EXIT
    THEN
    DUP _SBXJS.STATUS @ IF DROP 0 EXIT THEN
    DUP _SBXJS.HOST SBOX-HOST-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SBXJS.HOST SBOX-HOST-RUN-STATE@
        OVER _SBXJS.RUN-STATE @ <> IF DROP 0 EXIT THEN
    DUP _SBXJS.STATE @ SBOX-JOB-STATE-RUNNABLE = IF
        1 _SBXJA-RUNNABLE +!
        _SBXJS.RUN-STATE @ SBOX-VM-RUN-RUNNABLE = EXIT
    THEN
    _SBXJS.RUN-STATE @ _SBXJ-TERMINAL? ;

\ A complete walk for tests and diagnostics; operations never need it.
: SBOX-JOB-SERVICE-AUDIT  ( service -- flag )
    DUP SBOX-JOB-SERVICE-VALID? 0= IF DROP 0 EXIT THEN
    DUP _SBXJ-DRAINED? IF DROP -1 EXIT THEN
    _SBXJA-SERVICE !
    0 _SBXJA-LIVE ! 0 _SBXJA-RUNNABLE !
    _SBXJA-SERVICE @ _SBXJ.EFFECTIVE
        SBOX-LIMITS-SIZE SBOX-VALUE-LIMITS-SIZE + _SBXJ-ZERO? 0= IF
        0 EXIT
    THEN
    _SBXJA-SERVICE @ _SBXJ.CAPACITY @ 0 ?DO
        I _SBXJA-SERVICE @ _SBXJ-JOB _SBXJA-JOB? 0= IF 0 UNLOOP EXIT THEN
    LOOP
    _SBXJA-LIVE @ _SBXJA-SERVICE @ _SBXJ.LIVE-N @ =
    _SBXJA-RUNNABLE @ _SBXJA-SERVICE @ _SBXJ.RUNNABLE-N @ = AND ;
