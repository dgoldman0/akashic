\ Executable gate for the sandbox job service: submission through a taken
\ result, every job lifecycle path, and cleanup.

PROVIDED sbox-job-gate

VARIABLE _4W
VARIABLE _4H
VARIABLE _4X
VARIABLE _4D
VARIABLE _4K
VARIABLE _4J
VARIABLE _4Y
VARIABLE _4G
VARIABLE _4F
VARIABLE _4U0
VARIABLE _4U1
VARIABLE _4K2
VARIABLE _4GA
VARIABLE _4GB
VARIABLE _4RB
VARIABLE _4RU
VARIABLE _4TG
VARIABLE _4TC
VARIABLE _4TB
VARIABLE _4TU

\ The module is 336 bytes holding two instructions.
336 CONSTANT _4CU
_4CU 2 SBOX-PLAN-EXTENT DROP CONSTANT _4VU
4 CONSTANT _4SC
_4SC SBOX-JOB-SERVICE-MEASURE DROP CONSTANT _4SU

: _4A  ( address -- aligned-address ) 7 + -8 AND ;

\ Bytes ALLOCATE can still hand out: the bank-0 heap, the unused tail of
\ external memory and every reclaimed external block.  ALLOCATE uses
\ external memory when there is any, which HEAP-FREE-BYTES does not see.
: _4AV  ( -- u )
    HEAP-FREE-BYTES XMEM-FREE +
    XMEM-FL @ BEGIN ?DUP WHILE DUP @ ROT + SWAP 8 + @ REPEAT ;

CREATE _4PR SBOX-PROFILE-SIZE 7 + ALLOT
_4PR _4A CONSTANT _4P
CREATE _4PWR SBOX-PROFILE-LOAD-WORKSPACE-SIZE 7 + ALLOT
_4PWR _4A CONSTANT _4PW
CREATE _4CR _4CU 7 + ALLOT
_4CR _4A CONSTANT _4C
CREATE _4LR SBOX-ARTIFACT-LAYOUT-SIZE 7 + ALLOT
_4LR _4A CONSTANT _4L
CREATE _4VR _4VU 7 + ALLOT
_4VR _4A CONSTANT _4V
CREATE _4Q PHEAD-SIZE ALLOT
CREATE _4MR SBOX-LIMITS-SIZE 7 + ALLOT
_4MR _4A CONSTANT _4M
CREATE _4RR SBOX-LIMITS-SIZE 7 + ALLOT
_4RR _4A CONSTANT _4RQ
CREATE _4IR 31 ALLOT
_4IR _4A CONSTANT _4I
CREATE _4ER 31 ALLOT
_4ER _4A CONSTANT _4E
CREATE _4SR _4SU 7 + ALLOT
_4SR _4A CONSTANT _4S
CREATE _4Z COMP-DESC ALLOT

: _4?  ( flag -- ) 0= THROW ;

: _4PH  ( phase -- )
    0 _4U0 ! 0 _4U1 ! _4F ! ;

: _4D?  ( phase -- )
    _4PH
    DEPTH _4W @ -
    DUP 1 >= IF
        OVER _4U0 !
    THEN
    DUP 2 >= IF
        2 PICK _4U1 !
    THEN
    ?DUP IF THROW THEN ;

: _4EC  ( -- )
    1 0 1 4 0 2 _4L SBOX-ARTIFACT-MEASURE
        THROW
    _4P SBOX-PROFILE-DIGEST@
    64 _4L _4C SBOX-ARTIFACT-HEADER!
        THROW
    0x0001000100000002 _4C 256 +
        SBOX-BYTE-U64-LE!
    0x0000000400000000 _4C 272 +
        SBOX-BYTE-U64-LE!
    0x0000000100000000 _4C 280 +
        SBOX-BYTE-U64-LE!
    0x000000006E69616D _4C 288 +
        SBOX-BYTE-U64-LE!
    SBOX-MACHINE-OP-RETURN _4C 320 +
        SBOX-BYTE-U16-LE! ;

: _4II  ( -- )
    _4P _4PW SBOX-PROFILE-PURE-INIT THROW
    _4EC
    \ Only the verifier makes a plan.  Its workspace is measured from the
    \ module and freed once the plan is sealed.
    _4C _4CU SBOX-PLAN-MEASURE THROW _4VU = _4?
    _4C _4CU SBOX-VERIFIER-WORKSPACE-MEASURE THROW
    ALLOCATE THROW >R
    _4C _4CU _4P _4V _4VU R@ SBOX-VERIFY
    R> FREE
    THROW ;

: _4L!  ( value field -- )
    _4M SBOX-LIMIT-CAP THROW ;

\ The host's complete policy.  Every value limit admits only the one
\ boolean this module echoes.
: _4MI  ( -- )
    _4M SBOX-LIMITS-BEGIN THROW
    100000 SBOX-LIMIT-INSTRUCTION-BUDGET _4L!
      8192 SBOX-LIMIT-VALUE-OP-BUDGET _4L!
    262144 SBOX-LIMIT-COPY-BUDGET _4L!
    600000 SBOX-LIMIT-WALL-MS _4L!
         1 SBOX-LIMIT-DEPTH _4L!
         1 SBOX-LIMIT-BLOB-BYTES _4L!
         1 SBOX-LIMIT-LIST-COUNT _4L!
         1 SBOX-LIMIT-MAP-COUNT _4L!
         1 SBOX-LIMIT-INPUT-NODES _4L!
        24 SBOX-LIMIT-INPUT-BYTES _4L!
         1 SBOX-LIMIT-OUTPUT-ARENA-NODES _4L!
         1 SBOX-LIMIT-OUTPUT-ARENA-BYTES _4L!
         1 SBOX-LIMIT-OUTPUT-RESULT-NODES _4L!
        24 SBOX-LIMIT-OUTPUT-RESULT-BYTES _4L!
       256 SBOX-LIMIT-DATA-STACK _4L!
        64 SBOX-LIMIT-CALL-FRAMES _4L!
        64 SBOX-LIMIT-LOOP-FRAMES _4L!
     65536 SBOX-LIMIT-MEMORY-BYTES _4L!
    _4M SBOX-LIMITS-SEAL THROW ;

\ A request that narrows one field of the policy.
: _4RQ!  ( value field -- )
    _4RQ SBOX-LIMITS-BEGIN THROW
    _4RQ SBOX-LIMIT-CAP THROW
    _4RQ SBOX-LIMITS-SEAL THROW ;

: _4B!  ( flag address -- )
    >R R@ 24 0 FILL SBOX-VALUE-T-BOOL R@ C!
    8 R@ 8 + SBOX-BYTE-U64-LE!
    R> 16 + SBOX-BYTE-U64-LE! ;

\ A component instance's owner token, as Desk forms it.
: _4OT  ( instance -- owner-id owner-generation )
    DUP CINST.ID @ SWAP CINST.GENERATION @ ;

: _4SB  ( request instance -- activation-id job-generation status )
    >R >R _4V S" main" _4I 24 R> R> _4OT _4S SBOX-JOB-SUBMIT ;

\ Submit main for OWNER in the open service and keep its generation.
: _4SJ  ( instance -- generation )
    >R 0 _4I _4B!
    0 R> _4SB THROW SWAP _4Y @ = _4? ;

: _4QJ  ( generation instance -- job-state run-state last-status )
    >R _4Y @ SWAP R> _4OT _4S SBOX-JOB-QUERY THROW ;

: _4QS  ( generation instance -- status )
    >R _4Y @ SWAP R> _4OT _4S SBOX-JOB-QUERY
    >R 2DROP DROP R> ;

: _4JOB  ( generation instance -- activation-id generation owner-id owner-generation service )
    >R _4Y @ SWAP R> _4OT _4S ;

\ Measure a ready job's result, take it into a fresh buffer, and return
\ the buffer.
: _4TK  ( generation instance -- result result-u )
    _4TC ! _4TG !
    _4TG @ _4TC @ _4JOB SBOX-JOB-RESULT-MEASURE THROW
    DUP ALLOCATE THROW SWAP
    2DUP _4TG @ _4TC @ _4JOB SBOX-JOB-RESULT-TAKE THROW ;

: _4RF  ( result result-u -- )
    OVER SWAP SBOX-VM-RESULT-RELEASE THROW
    FREE ;

: _4R=?  ( expected expected-u result -- flag )
    SBOX-VM-RESULT-CANDIDATE@
    0= IF 2DROP 2DROP 0 EXIT THEN
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    COMPARE 0= ;

: _4AUDIT  ( -- )
    _4S SBOX-JOB-SERVICE-AUDIT _4? ;

: _S4-RUNTIME-INIT  ( -- )
    _4Q PHEAD-INIT
    0x44 _4Q PHEAD.ID C!
    0x45 _4Q PHEAD.CURRENT-ROOT C!
    4 CTX-NEW DUP IF THROW THEN DROP _4X !
    _4Q _4X @ CTX.PRACTICE !
    _4X @ DUP CTX.FLAGS @ CTX-F-ACTIVE OR OVER CTX.FLAGS !
    CTX-TOUCH
    _4Z COMP-DESC-INIT
    _4Z CINST-NEW DUP IF THROW THEN DROP _4D !
    _4Z CINST-NEW DUP IF THROW THEN DROP _4K !
    _4D @ CINST.ID @ _4J !
    _4S _4SU 0 FILL
    300 _4PH
    \ INIT refuses a policy that leaves a field unbounded, a zero slice,
    \ and storage of another size, and writes nothing when it refuses.
    8 SBOX-LIMIT-INPUT-BYTES _4RQ!
    _4X @ _4RQ 256 1000 0 _4J @ _4SC _4S _4SU SBOX-JOB-SERVICE-INIT
        SBOX-JOB-S-LIMITS = _4?
    _4X @ _4M 0 1000 0 _4J @ _4SC _4S _4SU SBOX-JOB-SERVICE-INIT
        SBOX-JOB-S-INVALID = _4?
    _4X @ _4M 256 1000 0 _4J @ _4SC _4S _4SU 8 - SBOX-JOB-SERVICE-INIT
        SBOX-JOB-S-CAPACITY = _4?
    \ Its own core and a core the machine lacks are never workers.
    _4X @ _4M 256 1000 1 COREID LSHIFT _4J @ _4SC _4S _4SU
        SBOX-JOB-SERVICE-INIT SBOX-JOB-S-INVALID = _4?
    _4X @ _4M 256 1000 1 N-FULL-CORES LSHIFT _4J @ _4SC _4S _4SU
        SBOX-JOB-SERVICE-INIT SBOX-JOB-S-INVALID = _4?
    _4S SBOX-JOB-SERVICE-STATE@ 0= _4?
    301 _4PH
    _4X @ _4M 256 1000 0 _4J @
    _4SC _4S _4SU SBOX-JOB-SERVICE-INIT THROW
    _4S SBOX-JOB-SERVICE-CAPACITY@ _4SC = _4?
    _4X @ _4M 256 1000 0 _4J @ _4SC _4S _4SU SBOX-JOB-SERVICE-INIT
        SBOX-JOB-S-STATE = _4?
    _4AUDIT ;

: _S4-INVOKE-TAKE  ( -- )
    400 _4D?
    _4S SBOX-JOB-SERVICE-STATE@ SBOX-JOB-SERVICE-STATE-OPEN = _4?
    401 _4D?
    0 _4I _4B! 0 _4E _4B!
    \ Submission refuses a plan it cannot run, an unknown entry and a
    \ missing owner before any job exists.
    0 S" main" _4I 24 0 _4K @ _4OT _4S SBOX-JOB-SUBMIT
        SBOX-JOB-S-PROFILE = _4? 2DROP
    _4V S" none" _4I 24 0 _4K @ _4OT _4S SBOX-JOB-SUBMIT
        SBOX-JOB-S-ENTRY = _4? 2DROP
    _4V S" main" _4I 24 0 0 0 _4S SBOX-JOB-SUBMIT
        SBOX-JOB-S-NOT-OWNER = _4? 2DROP
    _4S SBOX-JOB-SERVICE-COUNT 0= _4?
    402 _4D?
    0 _4K @ _4SB
    >R _4G ! _4Y ! R> THROW
    403 _4D?
    \ The input was copied at submission.
    _4I 24 0xA5 FILL
    _4S SBOX-JOB-SERVICE-TICK THROW
    _4AUDIT
    404 _4D?
    _4G @ _4K @ _4TK _4RU ! _4RB !
    _4S SBOX-JOB-SERVICE-COUNT 0= _4?
    _4AUDIT
    405 _4D? ;

\ Every job path beyond submit, tick and take: owners, query, cancel,
\ discard, owner drain, the tick allowance, a short result buffer, a
\ request's limits, deadlines, close and whole-service drain.
: _S4-LIFECYCLE  ( -- )
    _4Z CINST-NEW DUP IF THROW THEN DROP _4K2 !
    500 _4D?
    \ Two owners' jobs wait in two of the four slots.
    _4K @ _4SJ _4GA !
    _4K2 @ _4SJ _4GB !
    _4S SBOX-JOB-SERVICE-COUNT 2 = _4?
    _4S SBOX-JOB-SERVICE-RUNNABLE 2 = _4?
    _4GA @ _4K @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-RUNNABLE = _4?
        SBOX-JOB-STATE-RUNNABLE = _4?
    501 _4D?
    \ A job is visible only to its owner, and a handle names one
    \ activation.
    _4GB @ _4K @ _4QS SBOX-JOB-S-NOT-OWNER = _4?
    _4Y @ 1+ _4GA @ _4K @ _4OT _4S SBOX-JOB-QUERY
        >R 2DROP DROP R> SBOX-JOB-S-STALE = _4?
    502 _4D?
    \ Cancelling a job before it runs leaves a cancelled ready result.
    _4GA @ _4K @ _4JOB SBOX-JOB-CANCEL THROW
    _4GA @ _4K @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-CANCELLED = _4?
        SBOX-JOB-STATE-READY = _4?
    _4S SBOX-JOB-SERVICE-RUNNABLE 1 = _4?
    _4AUDIT
    503 _4D?
    \ One tick runs the only runnable job to completion.
    _4S SBOX-JOB-SERVICE-TICK THROW
    _4GB @ _4K2 @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-COMPLETE = _4?
        SBOX-JOB-STATE-READY = _4?
    _4S SBOX-JOB-SERVICE-RUNNABLE 0= _4?
    504 _4D?
    \ Discard releases the cancelled job, whose handle is then unknown.
    _4GA @ _4K @ _4JOB SBOX-JOB-DISCARD THROW
    _4GA @ _4K @ _4QS SBOX-JOB-S-NOT-FOUND = _4?
    _4S SBOX-JOB-SERVICE-COUNT 1 = _4?
    505 _4D?
    \ Draining one owner releases only that owner's retained result.
    _4K @ _4SJ _4GA !
    _4K2 @ _4OT _4S SBOX-JOB-OWNER-DRAIN THROW
    _4GB @ _4K2 @ _4QS SBOX-JOB-S-NOT-FOUND = _4?
    _4S SBOX-JOB-SERVICE-COUNT 1 = _4?
    _4AUDIT
    506 _4D?
    \ One tick runs every runnable job while its allowance lasts.
    _4K2 @ _4SJ _4GB !
    _4S SBOX-JOB-SERVICE-RUNNABLE 2 = _4?
    _4S SBOX-JOB-SERVICE-TICK THROW
    _4S SBOX-JOB-SERVICE-RUNNABLE 0= _4?
    _4GA @ _4K @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-COMPLETE = _4?
        SBOX-JOB-STATE-READY = _4?
    _4GB @ _4K2 @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-COMPLETE = _4?
        SBOX-JOB-STATE-READY = _4?
    _4AUDIT
    507 _4D?
    \ A buffer one byte short leaves the result in place.
    _4GB @ _4K2 @ _4JOB SBOX-JOB-RESULT-MEASURE THROW _4TU !
    _4TU @ ALLOCATE THROW _4TB !
    _4TB @ _4TU @ 1- _4GB @ _4K2 @ _4JOB SBOX-JOB-RESULT-TAKE
        SBOX-JOB-S-RESULT = _4?
    _4GB @ _4K2 @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-COMPLETE = _4?
        SBOX-JOB-STATE-READY = _4?
    _4TB @ _4TU @ _4GB @ _4K2 @ _4JOB SBOX-JOB-RESULT-TAKE THROW
    _4E 24 _4TB @ _4R=? _4?
    _4TB @ _4TU @ _4RF
    _4S SBOX-JOB-SERVICE-COUNT 1 = _4?
    _4AUDIT
    508 _4D?
    \ A request narrows the policy: this input is larger than it allows.
    8 SBOX-LIMIT-INPUT-BYTES _4RQ!
    0 _4I _4B!
    _4RQ _4K @ _4SB SBOX-JOB-S-INPUT = _4? 2DROP
    _4S SBOX-JOB-SERVICE-COUNT 1 = _4?
    _4AUDIT
    509 _4D?
    \ A job past its deadline is cancelled at the next tick.
    1 SBOX-LIMIT-WALL-MS _4RQ!
    0 _4I _4B!
    _4RQ _4K @ _4SB THROW _4GB ! DROP
    MS@ 2 + BEGIN MS@ OVER >= UNTIL DROP
    _4S SBOX-JOB-SERVICE-TICK THROW
    _4GB @ _4K @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-CANCELLED = _4?
        SBOX-JOB-STATE-READY = _4?
    _4GB @ _4K @ _4TK
    OVER SBOX-VM-RESULT-CLASS@ SBOX-VM-CLASS-CANCELLED = _4?
    OVER SBOX-VM-RESULT-DETAIL@ SBOX-VM-CANCEL-DEADLINE = _4?
    _4RF
    _4AUDIT
    510 _4D?
    \ Close bars new work and settles the runnable job synchronously.
    _4K @ _4SJ _4GB !
    _4S SBOX-JOB-SERVICE-CLOSE THROW
    _4S SBOX-JOB-SERVICE-STATE@
        SBOX-JOB-SERVICE-STATE-CLOSING = _4?
    0 _4K @ _4SB SBOX-JOB-S-STATE = _4? 2DROP
    _4GB @ _4K @ _4QJ
        SBOX-JOB-S-OK = _4? SBOX-VM-RUN-CANCELLED = _4?
        SBOX-JOB-STATE-READY = _4?
    _4S SBOX-JOB-SERVICE-TICK SBOX-JOB-S-STATE = _4?
    _4AUDIT
    511 _4D?
    \ Drain discards every retained result and ends the service's borrows.
    _4S SBOX-JOB-SERVICE-DRAIN THROW
    _4S SBOX-JOB-SERVICE-STATE@
        SBOX-JOB-SERVICE-STATE-DRAINED = _4?
    _4AUDIT
    512 _4D?
    _4K2 @ CINST-FREE 0 _4K2 !
    513 _4D? ;

: _S4-TEARDOWN  ( -- )
    _4S _4SU SBOX-JOB-SERVICE-RELEASE THROW
    _4V SBOX-PLAN-RELEASE THROW
    0 _4X @ CTX.FLAGS ! _4X @ CTX-FREE
    0 _4X !
    _4Q PHEAD-SIZE 0 FILL
    _4K @ CINST-FREE _4D @ CINST-FREE
    0 _4K ! 0 _4D ! ;

\ The first result outlives the service, plan, Context and owners.
: _S4-DETACHED-RESULT  ( -- )
    6 _4PH
    _4RB @ SBOX-VM-RESULT-CLASS@ SBOX-VM-CLASS-OK = _4?
    106 _4D?
    8 _4PH
    _4E 24 _4RB @ _4R=? _4?
    108 _4D?
    9 _4PH
    _4RB @ _4RU @ _4RF
    0 _4RB ! 0 _4RU !
    109 _4D?
    10 _4PH
    _4AV _4H @ = _4?
    110 _4D? ;

: _S4-BODY  ( -- )
    100 _4D?
    1 _4PH _4II
    101 _4D?
    2 _4PH _4MI
    102 _4D?
    3 _4PH _S4-RUNTIME-INIT
    103 _4D?
    4 _4PH _S4-INVOKE-TAKE
    104 _4D?
    11 _4PH _S4-LIFECYCLE
    112 _4D?
    5 _4PH _S4-TEARDOWN
    105 _4D?
    _S4-DETACHED-RESULT
    111 _4D? ;

: _S4-FAIL  ( status -- )
    ." SBOX JOB GATE FAIL PHASE "
    _4F @ .
    ." STATUS " .
    ." TOP " _4U0 @ .
    ." NEXT " _4U1 @ .
    CR TX-FLUSH ;

: _S4-RUN  ( -- )
    DEPTH _4W !
    _4AV _4H !
    ." SBOX JOB GATE START" CR TX-FLUSH
    ['] _S4-BODY CATCH ?DUP IF
        _S4-FAIL EXIT
    THEN
    ." SBOX JOB GATE PASS" CR TX-FLUSH ;

_S4-RUN
