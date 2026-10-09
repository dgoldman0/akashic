\ Executable endpoint-to-receipt gate for transient Desk sandbox compute.

PROVIDED sbox-s4-desk-service

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

136 CONSTANT _4CU
SBOX-PLAN-DESCRIPTOR-SIZE _4CU + CONSTANT _4VU
4 CONSTANT _4SC
_4SC DESK-SBOX-JOB-SERVICE-MEASURE DROP CONSTANT _4SU

: _4A  ( address -- aligned-address ) 7 + -8 AND ;

CREATE _4PR SBOX-PROFILE-SIZE 7 + ALLOT
_4PR _4A CONSTANT _4P
CREATE _4CR _4CU 7 + ALLOT
_4CR _4A CONSTANT _4C
CREATE _4LR SBOX-CANDIDATE-LAYOUT-SIZE 7 + ALLOT
_4LR _4A CONSTANT _4L
CREATE _4VR _4VU 7 + ALLOT
_4VR _4A CONSTANT _4V
1 SBOX-MODULE-OWNER-MEASURE DROP CONSTANT _4OU
CREATE _4OR _4OU 7 + ALLOT
_4OR _4A CONSTANT _4O
CREATE _4R RID-SIZE ALLOT
CREATE _4Q PHEAD-SIZE ALLOT
CREATE _4MR SBOX-VALUE-LIMITS-SIZE 7 + ALLOT
_4MR _4A CONSTANT _4M
CREATE _4IR 31 ALLOT
_4IR _4A CONSTANT _4I
CREATE _4ER 31 ALLOT
_4ER _4A CONSTANT _4E
CREATE _4SR _4SU 7 + ALLOT
_4SR _4A CONSTANT _4S
CREATE _4NR IENDPOINT-SIZE 7 + ALLOT
_4NR _4A CONSTANT _4N
CREATE _4Z COMP-DESC ALLOT
CREATE _4TR DESK-SBOX-RECEIPT-SIZE 7 + ALLOT
_4TR _4A CONSTANT _4T

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
    1 0 1 4 0 2 _4L SBOX-CANDIDATE-MEASURE
        THROW
    SBOX-PROFILE-PURE-TAG
    64 _4L _4C SBOX-CANDIDATE-HEADER!
        THROW
    0x0001000100000002 _4C 64 +
        SBOX-CANDIDATE-U64-LE!
    0x0000000400000000 _4C 80 +
        SBOX-CANDIDATE-U64-LE!
    0x0000000100000000 _4C 88 +
        SBOX-CANDIDATE-U64-LE!
    0x000000006E69616D _4C 96 +
        SBOX-CANDIDATE-U64-LE!
    SBOX-MACHINE-OP-RETURN _4C 120 +
        SBOX-CANDIDATE-U16-LE! ;

: _4II  ( -- )
    _4P SBOX-PROFILE-PURE-INIT THROW
    _4EC
    \ Stage 2/3 independently verified these exact known-good bytes.
    _4C _4CU _4L _4P
        _4V _4VU SBOX-PLAN-PUBLISH-VERIFIED
        THROW
    _4R RID-CLEAR 0xA4 _4R C!
    1 _4O _4OU SBOX-MODULE-OWNER-INIT THROW
    _4R 11 _4V _4O SBOX-MODULE-OWNER-ADD THROW
    _4O SBOX-MODULE-OWNER-SEAL THROW ;

: _4L!  ( value field -- )
    _4M SBOX-VALUE-LIMIT! THROW ;

: _4MI  ( -- )
    _4M SBOX-VALUE-LIMITS-BEGIN THROW
       1 SBOX-VALUE-LIMIT-DEPTH _4L!
       1 SBOX-VALUE-LIMIT-BLOB-BYTES _4L!
       1 SBOX-VALUE-LIMIT-LIST-COUNT _4L!
       1 SBOX-VALUE-LIMIT-MAP-COUNT _4L!
       1 SBOX-VALUE-LIMIT-INPUT-NODES _4L!
      24 SBOX-VALUE-LIMIT-INPUT-BYTES _4L!
       1 SBOX-VALUE-LIMIT-OUTPUT-ARENA-NODES _4L!
       1 SBOX-VALUE-LIMIT-OUTPUT-ARENA-BYTES _4L!
       1 SBOX-VALUE-LIMIT-OUTPUT-RESULT-NODES _4L!
      24 SBOX-VALUE-LIMIT-OUTPUT-RESULT-BYTES _4L!
    _4M SBOX-VALUE-LIMITS-SEAL THROW ;

: _4B!  ( flag address -- )
    >R R@ 24 0 FILL SBOX-VALUE-T-BOOL R@ C!
    8 R@ 8 + SBOX-CANDIDATE-U64-LE!
    R> 16 + SBOX-CANDIDATE-U64-LE! ;

: _4PS  ( -- service | 0 )
    _4S DESK-SBOX-JOB-SERVICE-STATE@
    DESK-SBOX-JOB-SERVICE-STATE-OPEN =
    IF _4S ELSE 0 THEN ;

: _4ES  ( id-a id-u context -- service | 0 )
    _4D @ <> IF 2DROP 0 EXIT THEN
    S" org.akashic.sandbox.pure-compute" COMPARE 0=
    IF _4PS ELSE 0 THEN ;

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
    _4N IENDPOINT-INIT
    _4D @ _4N IEND.CONTEXT !
    ['] _4ES _4N IEND.SERVICE-XT !
    _4N _4K @ CINST.ENDPOINT !
    _4S _4SU 0 FILL
    _4O _4Q _4X @ _4M
    100000 8192 262144 256 _4J @
    _4SC _4S _4SU DESK-SBOX-JOB-SERVICE-INIT THROW
    _4S DESK-SBOX-JOB-SERVICE-CAPACITY@ _4SC = _4? ;

: _S4-INVOKE-TAKE  ( -- )
    400 _4D?
    S" org.akashic.sandbox.pure-compute" _4K @ CINST-SERVICE
        _4S = _4?
    401 _4D?
    0 _4I _4B! 0 _4E _4B!
    _4T DESK-SBOX-RECEIPT-SIZE 0 FILL
    402 _4D?
    _4R 11 S" main" _4I 24 _4K @ _4S
        DESK-SBOX-JOB-SUBMIT
    >R _4G ! _4Y ! R> THROW
    403 _4D?
    _4I 24 0xA5 FILL
    _4S DESK-SBOX-JOB-SERVICE-TICK THROW
    404 _4D?
    _4T _4Y @ _4G @
        _4K @ _4S DESK-SBOX-JOB-RESULT-TAKE
        THROW
    405 _4D? ;

\ Submit main for CALLER in the open service and keep its generation.
: _4SJ  ( caller -- generation )
    >R 0 _4I _4B!
    _4R 11 S" main" _4I 24 R> _4S DESK-SBOX-JOB-SUBMIT
    THROW SWAP _4Y @ = _4? ;

: _4QJ  ( generation caller -- job-state run-state last-status )
    >R _4Y @ SWAP R> _4S DESK-SBOX-JOB-QUERY THROW ;

: _4QS  ( generation caller -- status )
    >R _4Y @ SWAP R> _4S DESK-SBOX-JOB-QUERY
    >R 2DROP DROP R> ;

\ Every job path beyond submit, tick and take: callers, query, cancel,
\ discard, caller drain, close and whole-service drain.
: _S4-LIFECYCLE  ( -- )
    _4Z CINST-NEW DUP IF THROW THEN DROP _4K2 !
    500 _4D?
    \ Two callers' jobs wait in two of the four slots.
    _4K @ _4SJ _4GA !
    _4K2 @ _4SJ _4GB !
    _4S DESK-SBOX-JOB-SERVICE-COUNT 2 = _4?
    _4GA @ _4K @ _4QJ
        DESK-SBOX-S-OK = _4? SBOX-VM-RUN-RUNNABLE = _4?
        DESK-SBOX-JOB-STATE-RUNNABLE = _4?
    501 _4D?
    \ A job is visible only to the caller that submitted it.
    _4GB @ _4K @ _4QS DESK-SBOX-JOB-S-NOT-CALLER = _4?
    502 _4D?
    \ Cancelling a job before it runs leaves a cancelled ready result.
    _4Y @ _4GA @ _4K @ _4S DESK-SBOX-JOB-CANCEL THROW
    _4GA @ _4K @ _4QJ
        DESK-SBOX-S-OK = _4? SBOX-VM-RUN-CANCELLED = _4?
        DESK-SBOX-JOB-STATE-READY = _4?
    503 _4D?
    \ One tick runs the only runnable job to completion.
    _4S DESK-SBOX-JOB-SERVICE-TICK THROW
    _4GB @ _4K2 @ _4QJ
        DESK-SBOX-S-OK = _4? SBOX-VM-RUN-COMPLETE = _4?
        DESK-SBOX-JOB-STATE-READY = _4?
    504 _4D?
    \ Discard releases the cancelled job, whose handle is then unknown.
    _4Y @ _4GA @ _4K @ _4S DESK-SBOX-JOB-DISCARD THROW
    _4GA @ _4K @ _4QS DESK-SBOX-S-NOT-FOUND = _4?
    _4S DESK-SBOX-JOB-SERVICE-COUNT 1 = _4?
    505 _4D?
    \ Draining one caller releases only that caller's retained result.
    _4K @ _4SJ _4GA !
    _4K2 @ _4S DESK-SBOX-JOB-OWNER-DRAIN THROW
    _4GB @ _4K2 @ _4QS DESK-SBOX-S-NOT-FOUND = _4?
    _4S DESK-SBOX-JOB-SERVICE-COUNT 1 = _4?
    506 _4D?
    \ Close bars new work and settles the runnable job synchronously.
    _4S DESK-SBOX-JOB-SERVICE-CLOSE THROW
    _4S DESK-SBOX-JOB-SERVICE-STATE@
        DESK-SBOX-JOB-SERVICE-STATE-CLOSING = _4?
    _4R 11 S" main" _4I 24 _4K @ _4S DESK-SBOX-JOB-SUBMIT
        DESK-SBOX-S-STATE = _4? 2DROP
    _4GA @ _4K @ _4QJ
        DESK-SBOX-S-OK = _4? SBOX-VM-RUN-CANCELLED = _4?
        DESK-SBOX-JOB-STATE-READY = _4?
    507 _4D?
    \ Drain discards every retained result and ends the service's borrows.
    _4S DESK-SBOX-JOB-SERVICE-DRAIN THROW
    _4S DESK-SBOX-JOB-SERVICE-STATE@
        DESK-SBOX-JOB-SERVICE-STATE-DRAINED = _4?
    508 _4D?
    _4K2 @ CINST-FREE 0 _4K2 !
    509 _4D? ;

: _S4-TEARDOWN  ( -- )
    _4S _4SU DESK-SBOX-JOB-SERVICE-RELEASE THROW
    _4O SBOX-MODULE-OWNER-RELEASE THROW
    _4V SBOX-PLAN-RELEASE THROW
    0 _4X @ CTX.FLAGS ! _4X @ CTX-FREE
    0 _4X !
    _4Q PHEAD-SIZE 0 FILL
    _4K @ CINST-FREE _4D @ CINST-FREE
    0 _4K ! 0 _4D ! ;

: _S4-RESULT=?  ( expected expected-u receipt -- flag )
    DESK-SBOX-RECEIPT-PAYLOAD@
    0= IF 2DROP 2DROP 0 EXIT THEN DROP
    SBOX-VM-RESULT-CANDIDATE@
    0= IF 2DROP 2DROP 0 EXIT THEN
    2 PICK OVER <> IF 2DROP 2DROP 0 EXIT THEN
    COMPARE 0= ;

: _S4-DETACHED-RESULT  ( -- )
    6 _4PH
    _4T DESK-SBOX-RECEIPT-ACTIVATION@ _4?
    _4G @ = _4? _4J @ = _4?
    106 _4D?
    7 _4PH
    _4T DESK-SBOX-RECEIPT-MODULE@ _4?
    S" main" COMPARE 0= _4?
    11 = _4? _4R RID= _4?
    107 _4D?
    8 _4PH
    _4E 24 _4T _S4-RESULT=? _4?
    108 _4D?
    9 _4PH
    _4T DESK-SBOX-RECEIPT-RELEASE THROW
    109 _4D?
    10 _4PH
    HEAP-FREE-BYTES _4H @ = _4?
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
    ." SBOX STAGE4 DESK SERVICE FAIL PHASE "
    _4F @ .
    ." STATUS " .
    ." TOP " _4U0 @ .
    ." NEXT " _4U1 @ .
    CR TX-FLUSH ;

: _S4-RUN  ( -- )
    DEPTH _4W !
    HEAP-FREE-BYTES _4H !
    ." SBOX STAGE4 DESK SERVICE START" CR TX-FLUSH
    ['] _S4-BODY CATCH ?DUP IF
        _S4-FAIL EXIT
    THEN
    ." SBOX STAGE4 DESK SERVICE PASS" CR TX-FLUSH ;

_S4-RUN
