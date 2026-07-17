\ =====================================================================
\  worker-job.f - One-shot supervised full-core worker jobs
\ =====================================================================
\  This is deliberately not a scheduler or a worker pool.  The owner core
\  prepares caller-owned buffers, submits one descriptor to an idle full
\  core, polls it, validates its own revision/generation, and only then
\  applies the result.  Worker code may use only its input, output, scratch,
\  and audited worker-safe words.  It may not allocate, draw, switch VFS or
\  UI globals, touch component state, or publish a semantic commit.  Its XT
\  returns a result code; zero succeeds and nonzero fails.  Worker XTs are
\  total and MUST NOT THROW for expected failures.  The supervisor uses the
\  per-core KDOS CATCH chain only as last-resort fault containment.
\
\  Metadata publication is serialized by EVT-LOCK.  Payload/output writes
\  happen before the terminal state is published under that lock; WJOB-POLL
\  takes the same lock before returning the state and result.
\ =====================================================================

PROVIDED akashic-concurrency-worker-job

REQUIRE event.f
REQUIRE ../runtime/concurrency-class.f
REQUIRE ../utils/memory-span.f

0x424F4A57 CONSTANT WJOB-MAGIC       \ "WJOB" in memory
1          CONSTANT WJOB-ABI-VERSION

0 CONSTANT WJOB-S-IDLE
1 CONSTANT WJOB-S-PREPARED
2 CONSTANT WJOB-S-RUNNING
3 CONSTANT WJOB-S-SUCCEEDED
4 CONSTANT WJOB-S-FAILED
5 CONSTANT WJOB-S-CANCELLED
6 CONSTANT WJOB-S-REAPED

0 CONSTANT WJOB-OK
1 CONSTANT WJOB-E-INVALID
2 CONSTANT WJOB-E-STATE
3 CONSTANT WJOB-E-BUSY
4 CONSTANT WJOB-E-CORE
5 CONSTANT WJOB-E-CLASS
6 CONSTANT WJOB-E-UNAVAILABLE
7 CONSTANT WJOB-E-NOT-DONE
8 CONSTANT WJOB-E-CAPACITY

-4096 CONSTANT WJOB-R-DEADLINE

  0 CONSTANT _WJ-MAGIC
  8 CONSTANT _WJ-ABI
 16 CONSTANT _WJ-SIZE
 24 CONSTANT _WJ-STATE
 32 CONSTANT _WJ-GENERATION
 40 CONSTANT _WJ-CORE
 48 CONSTANT _WJ-CLASS
 56 CONSTANT _WJ-WORKER-XT          \ ( job -- result-code )
 64 CONSTANT _WJ-IN-A
 72 CONSTANT _WJ-IN-U
 80 CONSTANT _WJ-OUT-A
 88 CONSTANT _WJ-OUT-CAP
 96 CONSTANT _WJ-OUT-U
104 CONSTANT _WJ-SCRATCH-A
112 CONSTANT _WJ-SCRATCH-U
120 CONSTANT _WJ-CANCELLED
128 CONSTANT _WJ-RESULT
136 CONSTANT _WJ-TAG
144 CONSTANT _WJ-DEADLINE
152 CONSTANT _WJ-STARTED-MS
160 CONSTANT _WJ-ENDED-MS
168 CONSTANT _WJ-RESERVED
176 CONSTANT WJOB-SIZE

: WJOB.MAGIC       ( job -- a ) _WJ-MAGIC + ;
: WJOB.ABI         ( job -- a ) _WJ-ABI + ;
: WJOB.SIZE        ( job -- a ) _WJ-SIZE + ;
: WJOB.STATE       ( job -- a ) _WJ-STATE + ;
: WJOB.GENERATION  ( job -- a ) _WJ-GENERATION + ;
: WJOB.CORE        ( job -- a ) _WJ-CORE + ;
: WJOB.CLASS       ( job -- a ) _WJ-CLASS + ;
: WJOB.WORKER-XT   ( job -- a ) _WJ-WORKER-XT + ;
: WJOB.IN-A        ( job -- a ) _WJ-IN-A + ;
: WJOB.IN-U        ( job -- a ) _WJ-IN-U + ;
: WJOB.OUT-A       ( job -- a ) _WJ-OUT-A + ;
: WJOB.OUT-CAP     ( job -- a ) _WJ-OUT-CAP + ;
: WJOB.OUT-U       ( job -- a ) _WJ-OUT-U + ;
: WJOB.SCRATCH-A   ( job -- a ) _WJ-SCRATCH-A + ;
: WJOB.SCRATCH-U   ( job -- a ) _WJ-SCRATCH-U + ;
: WJOB.CANCELLED   ( job -- a ) _WJ-CANCELLED + ;
: WJOB.RESULT      ( job -- a ) _WJ-RESULT + ;
: WJOB.TAG         ( job -- a ) _WJ-TAG + ;
: WJOB.DEADLINE    ( job -- a ) _WJ-DEADLINE + ;
: WJOB.STARTED-MS  ( job -- a ) _WJ-STARTED-MS + ;
: WJOB.ENDED-MS    ( job -- a ) _WJ-ENDED-MS + ;

: WJOB-INIT  ( job -- )
    DUP WJOB-SIZE 0 FILL
    WJOB-MAGIC OVER WJOB.MAGIC !
    WJOB-ABI-VERSION OVER WJOB.ABI !
    WJOB-SIZE OVER WJOB.SIZE !
    -1 SWAP WJOB.CORE ! ;

: WJOB-VALID?  ( job -- flag )
    DUP 0= IF DROP 0 EXIT THEN
    DUP WJOB.MAGIC @ WJOB-MAGIC =
    OVER WJOB.ABI @ WJOB-ABI-VERSION = AND
    OVER WJOB.SIZE @ WJOB-SIZE >= AND
    SWAP WJOB.STATE @ DUP WJOB-S-IDLE >=
    SWAP WJOB-S-REAPED <= AND AND ;

: WJOB-TERMINAL?  ( state -- flag )
    DUP WJOB-S-SUCCEEDED >= SWAP WJOB-S-CANCELLED <= AND ;

: _WJOB-SPAN-VALID?  ( addr len -- flag )
    DUP 0= IF 2DROP -1 EXIT THEN
    OVER 0= IF 2DROP 0 EXIT THEN
    MSPAN-NONWRAPPING? ;

: _WJOB-SPANS-OVERLAP?  ( a1 u1 a2 u2 -- flag )
    MSPAN-OVERLAP? ;

: _WJOB-FIELDS-VALID?  ( job -- flag )
    >R
    R@ WJOB.WORKER-XT @ 0<>
    R@ WJOB.GENERATION @ 0> AND
    R@ WJOB.CLASS @ DUP CCLASS-VALID? SWAP CCLASS-WORKER? AND AND
    R@ WJOB.IN-A @ R@ WJOB.IN-U @ _WJOB-SPAN-VALID? AND
    R@ WJOB.OUT-A @ R@ WJOB.OUT-CAP @ _WJOB-SPAN-VALID? AND
    R@ WJOB.SCRATCH-A @ R@ WJOB.SCRATCH-U @ _WJOB-SPAN-VALID? AND
    R@ WJOB.IN-A @ R@ WJOB.IN-U @
        R@ WJOB.OUT-A @ R@ WJOB.OUT-CAP @
        _WJOB-SPANS-OVERLAP? 0= AND
    R@ WJOB.IN-A @ R@ WJOB.IN-U @
        R@ WJOB.SCRATCH-A @ R@ WJOB.SCRATCH-U @
        _WJOB-SPANS-OVERLAP? 0= AND
    R@ WJOB.OUT-A @ R@ WJOB.OUT-CAP @
        R@ WJOB.SCRATCH-A @ R@ WJOB.SCRATCH-U @
        _WJOB-SPANS-OVERLAP? 0= AND
    R> DROP ;

\ The many arguments are stored only while the descriptor is owner-private.
\ PREPARED is published last under EVT-LOCK.
: WJOB-PREPARE
  ( worker-xt in-a in-u out-a out-cap scratch-a scratch-u
    class generation tag job -- status )
    DUP WJOB-VALID? 0= IF DROP 10 0 DO DROP LOOP WJOB-E-INVALID EXIT THEN
    DUP WJOB.STATE @ DUP WJOB-S-IDLE <> SWAP WJOB-S-REAPED <> AND IF
        DROP 10 0 DO DROP LOOP WJOB-E-STATE EXIT
    THEN
    >R
    R@ WJOB.TAG !
    R@ WJOB.GENERATION !
    R@ WJOB.CLASS !
    R@ WJOB.SCRATCH-U !
    R@ WJOB.SCRATCH-A !
    R@ WJOB.OUT-CAP !
    R@ WJOB.OUT-A !
    R@ WJOB.IN-U !
    R@ WJOB.IN-A !
    R@ WJOB.WORKER-XT !
    0 R@ WJOB.OUT-U !
    0 R@ WJOB.CANCELLED !
    0 R@ WJOB.RESULT !
    0 R@ WJOB.DEADLINE !
    0 R@ WJOB.STARTED-MS !
    0 R@ WJOB.ENDED-MS !
    R@ _WJOB-FIELDS-VALID? 0= IF
        R@ WJOB-INIT R> DROP WJOB-E-INVALID EXIT
    THEN
    EVT-LOCK LOCK
    WJOB-S-PREPARED R@ WJOB.STATE !
    EVT-LOCK UNLOCK
    R> DROP WJOB-OK ;

: WJOB-DEADLINE!  ( absolute-ms job -- status )
    DUP WJOB-VALID? 0= IF 2DROP WJOB-E-INVALID EXIT THEN
    DUP WJOB.STATE @ WJOB-S-PREPARED <> IF 2DROP WJOB-E-STATE EXIT THEN
    WJOB.DEADLINE ! WJOB-OK ;

: WJOB-OUTPUT-LEN!  ( len job -- status )
    DUP WJOB-VALID? 0= IF 2DROP WJOB-E-INVALID EXIT THEN
    DUP WJOB.STATE @ WJOB-S-RUNNING <> IF 2DROP WJOB-E-STATE EXIT THEN
    OVER 0< IF 2DROP WJOB-E-CAPACITY EXIT THEN
    2DUP WJOB.OUT-CAP @ > IF 2DROP WJOB-E-CAPACITY EXIT THEN
    WJOB.OUT-U ! WJOB-OK ;

: WJOB-CANCELLED?  ( job -- flag )
    WJOB.CANCELLED @ 0<> ;

: WJOB-MATCH?  ( generation tag job -- flag )
    >R
    SWAP R@ WJOB.GENERATION @ =
    SWAP R> WJOB.TAG @ = AND ;

16 CONSTANT _WJOB-MAX-CORES
CREATE _WJOB-SLOTS _WJOB-MAX-CORES CELLS ALLOT
_WJOB-SLOTS _WJOB-MAX-CORES CELLS 0 FILL

: _WJOB-SLOT  ( core -- slot-a )
    CELLS _WJOB-SLOTS + ;

: _WJOB-CORE-VALID?  ( core -- flag )
    DUP 1 >=
    OVER N-FULL-CORES < AND
    SWAP _WJOB-MAX-CORES < AND ;

: _WJOB-CALL  ( -- )
    COREID _WJOB-SLOT @ DUP WJOB.WORKER-XT @ EXECUTE
    COREID _WJOB-SLOT @ WJOB.RESULT ! ;

: _WJOB-EXECUTE  ( job -- job result-code )
    ['] _WJOB-CALL CATCH
    DUP IF EXIT THEN
    DROP DUP WJOB.RESULT @ ;

: _WJOB-PUBLISH-TERMINAL  ( state result job -- )
    >R
    R@ WJOB.RESULT !
    MS@ R@ WJOB.ENDED-MS !
    EVT-LOCK LOCK
    R> WJOB.STATE !
    EVT-LOCK UNLOCK ;

: _WJOB-DEADLINE-EXPIRED?  ( job -- flag )
    WJOB.DEADLINE @ ?DUP IF
        MS@ SWAP U< 0=
    ELSE
        0
    THEN ;

: _WJOB-FINISH  ( job result-code -- )
    OVER WJOB-CANCELLED? IF
        DROP WJOB-S-CANCELLED 0 ROT _WJOB-PUBLISH-TERMINAL EXIT
    THEN
    OVER _WJOB-DEADLINE-EXPIRED? IF
        DROP WJOB-S-CANCELLED WJOB-R-DEADLINE ROT
        _WJOB-PUBLISH-TERMINAL EXIT
    THEN
    DUP IF
        WJOB-S-FAILED SWAP ROT _WJOB-PUBLISH-TERMINAL
    ELSE
        DROP WJOB-S-SUCCEEDED 0 ROT _WJOB-PUBLISH-TERMINAL
    THEN ;

: _WJOB-TRAMPOLINE  ( -- )
    COREID _WJOB-SLOT @ ?DUP 0= IF EXIT THEN
    DUP WJOB-CANCELLED? IF
        WJOB-S-CANCELLED 0 ROT _WJOB-PUBLISH-TERMINAL EXIT
    THEN
    _WJOB-EXECUTE _WJOB-FINISH ;

: WJOB-SUBMIT  ( worker-core job -- status )
    DUP WJOB-VALID? 0= IF 2DROP WJOB-E-INVALID EXIT THEN
    OVER _WJOB-CORE-VALID? 0= IF 2DROP WJOB-E-CORE EXIT THEN
    N-FULL-CORES 2 < IF 2DROP WJOB-E-UNAVAILABLE EXIT THEN
    >R                              \ core ; R: job
    EVT-LOCK LOCK
    R@ WJOB.STATE @ WJOB-S-PREPARED <> IF
        EVT-LOCK UNLOCK DROP R> DROP WJOB-E-STATE EXIT
    THEN
    DUP CORE-STATUS IF
        EVT-LOCK UNLOCK DROP R> DROP WJOB-E-BUSY EXIT
    THEN
    DUP _WJOB-SLOT @ IF
        EVT-LOCK UNLOCK DROP R> DROP WJOB-E-BUSY EXIT
    THEN
    R@ OVER _WJOB-SLOT !
    DUP R@ WJOB.CORE !
    MS@ R@ WJOB.STARTED-MS !
    WJOB-S-RUNNING R@ WJOB.STATE !
    EVT-LOCK UNLOCK
    ['] _WJOB-TRAMPOLINE SWAP CORE-RUN
    R> DROP WJOB-OK ;

: WJOB-POLL  ( job -- state result-code )
    DUP WJOB-VALID? 0= IF DROP WJOB-S-IDLE WJOB-E-INVALID EXIT THEN
    >R EVT-LOCK LOCK
    R@ WJOB.STATE @ R@ WJOB.RESULT @
    EVT-LOCK UNLOCK R> DROP ;

: WJOB-CANCEL  ( job -- status )
    DUP WJOB-VALID? 0= IF DROP WJOB-E-INVALID EXIT THEN
    EVT-LOCK LOCK
    DUP WJOB.STATE @
    DUP WJOB-S-PREPARED = IF
        DROP -1 OVER WJOB.CANCELLED !
        WJOB-S-CANCELLED OVER WJOB.STATE !
        MS@ OVER WJOB.ENDED-MS !
        EVT-LOCK UNLOCK DROP WJOB-OK EXIT
    THEN
    WJOB-S-RUNNING = IF
        -1 SWAP WJOB.CANCELLED !
        EVT-LOCK UNLOCK WJOB-OK EXIT
    THEN
    EVT-LOCK UNLOCK DROP WJOB-E-STATE ;

: WJOB-PHYSICALLY-DONE?  ( job -- flag )
    DUP WJOB-VALID? 0= IF DROP 0 EXIT THEN
    DUP WJOB.STATE @ WJOB-TERMINAL? 0= IF DROP 0 EXIT THEN
    WJOB.CORE @ DUP 0< IF DROP -1 EXIT THEN
    CORE-STATUS 0= ;

: WJOB-REAP  ( job -- status )
    DUP WJOB-VALID? 0= IF DROP WJOB-E-INVALID EXIT THEN
    DUP WJOB.STATE @ WJOB-TERMINAL? 0= IF DROP WJOB-E-NOT-DONE EXIT THEN
    DUP WJOB.CORE @ DUP 0>= IF
        DUP CORE-STATUS IF 2DROP WJOB-E-BUSY EXIT THEN
        2DUP _WJOB-SLOT @ <> IF 2DROP WJOB-E-STATE EXIT THEN
    THEN
    DROP
    EVT-LOCK LOCK
    DUP WJOB.CORE @ DUP 0>= IF
        _WJOB-SLOT 0 SWAP !
    ELSE
        DROP
    THEN
    -1 OVER WJOB.CORE !
    WJOB-S-REAPED SWAP WJOB.STATE !
    EVT-LOCK UNLOCK
    WJOB-OK ;
