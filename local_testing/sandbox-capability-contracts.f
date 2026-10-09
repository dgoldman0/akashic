\ Contracts for the shared sandbox capability: its descriptors and
\ schemas, immediate replies for build, input and entry failures, runs
\ completed from the tick, cancellation, owner drain and unbind, and that
\ the capability returns every byte it allocates.

PROVIDED sbox-capability-tests

VARIABLE _SCT-FAILS
VARIABLE _SCT-CHECKS
VARIABLE _SCT-DEPTH
VARIABLE _SCT-MEMORY
VARIABLE _SCT-INST
VARIABLE _SCT-REG
VARIABLE _SCT-BUS
VARIABLE _SCT-CTX
VARIABLE _SCT-DONE
VARIABLE _SCT-CALLER
VARIABLE _SCT-ENTRY-A
VARIABLE _SCT-ENTRY-U
VARIABLE _SCT-INPUT-A
VARIABLE _SCT-INPUT-U
VARIABLE _SCT-MEM
VARIABLE _SCT-A
VARIABLE _SCT-B
VARIABLE _SCT-SRC-U

: _SCT-ALIGN8  ( address -- aligned-address ) 7 + -8 AND ;

\ The most guest memory the test policy grants a run.
65536 CONSTANT _SCT-MEMORY-MAX

CREATE _SCT-POLICY-RAW SBOX-LIMITS-SIZE 7 + ALLOT
_SCT-POLICY-RAW _SCT-ALIGN8 CONSTANT _SCT-POLICY
CREATE _SCT-HEAD PHEAD-SIZE ALLOT
CREATE _SCT-SRC 512 ALLOT

: _SCT-ASSERT  ( flag -- )
    1 _SCT-CHECKS +!
    0= IF
        1 _SCT-FAILS +!
        ." SBOX CAPABILITY ASSERT " _SCT-CHECKS @ . CR
    THEN ;

: _SCT-STACK  ( -- )
    DEPTH DUP _SCT-DEPTH @ <> IF
        ." SBOX CAPABILITY STACK "
        _SCT-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _SCT-DEPTH @ = _SCT-ASSERT ;

\ Bytes ALLOCATE can still hand out: the bank-0 heap, the unused tail of
\ external memory and every reclaimed external block.
: _SCT-AVAILABLE  ( -- u )
    HEAP-FREE-BYTES XMEM-FREE +
    XMEM-FL @ BEGIN ?DUP WHILE DUP @ ROT + SWAP 8 + @ REPEAT ;

\ =====================================================================
\  Sources
\ =====================================================================

: _SCT-INCREMENT  ( -- address length )
    S" FUNCTION increment PARAMS 1 RESULTS 1 LOCALS 0 V.I64.GET 1 I64.ADD V.NEW.I64 RETURN END ENTRY SIGNATURE 1 main increment" ;
\ FROB at offset 42.
: _SCT-UNKNOWN  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 FROB RETURN END ENTRY SIGNATURE 1 main main" ;
\ RETURN, at offset 47, leaves no result.
: _SCT-NO-RESULT  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 DROP RETURN END ENTRY SIGNATURE 1 main main" ;
: _SCT-DIVIDE  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 V.I64.GET 0 I64.DIV.S V.NEW.I64 RETURN END ENTRY SIGNATURE 1 main main" ;
: _SCT-ABORT  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 ABORT 7 END ENTRY SIGNATURE 1 main main" ;
: _SCT-FOREVER  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 BEGIN AGAIN END ENTRY SIGNATURE 1 main main" ;
: _SCT-MEMORY-SIZE  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 DROP MEM.SIZE V.NEW.I64 RETURN END ENTRY SIGNATURE 1 main main" ;

: _SCT-SRC+  ( address length -- )
    DUP _SCT-SRC-U @ + 512 > IF 2DROP EXIT THEN
    _SCT-SRC _SCT-SRC-U @ + SWAP DUP _SCT-SRC-U +! MOVE ;
: _SCT-NL  ( -- ) 10 _SCT-SRC _SCT-SRC-U @ + C! 1 _SCT-SRC-U +! ;

\ The unknown word is on line 3, after a comment line.
: _SCT-TWO-LINES  ( -- address length )
    0 _SCT-SRC-U !
    S" \ a comment" _SCT-SRC+ _SCT-NL
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0" _SCT-SRC+ _SCT-NL
    S"   FROB RETURN END ENTRY SIGNATURE 1 main main" _SCT-SRC+
    _SCT-SRC _SCT-SRC-U @ ;

\ =====================================================================
\  Requests
\ =====================================================================

: _SCT-COMPLETE  ( request -- ) DROP 1 _SCT-DONE +! ;

: _SCT-DEFAULTS  ( -- )
    S" main" _SCT-ENTRY-U ! _SCT-ENTRY-A !
    S" null" _SCT-INPUT-U ! _SCT-INPUT-A !
    0 _SCT-MEM !
    77 _SCT-CALLER ! ;

: _SCT-ARG-TEXT  ( text-a text-u key-a key-u index request -- )
    CBR.ARGS CV-MAP-SLOT! THROW CV-STRING! THROW ;

: _SCT-ARG-INT  ( n key-a key-u index request -- )
    CBR.ARGS CV-MAP-SLOT! THROW CV-INT! ;

: _SCT-CAP  ( -- cap )
    S" org.akashic.sandbox/test" SBOX-CAPABILITY-COMPONENT COMP-CAP-FIND ;

\ A request for SOURCE with the current entry, input, memory and caller.
: _SCT-REQUEST  ( source-a source-u -- request )
    CBR-NEW THROW >R
    CPRINC-USER R@ CBR.PRINCIPAL !
    _SCT-INST @ R@ CBR-TARGET!
    _SCT-CAP R@ CBR.CAP !
    ['] _SCT-COMPLETE R@ CBR.COMPLETE-XT !
    _SCT-CALLER @ R@ CBR.CALLER-ID !
    1 R@ CBR.CALLER-GEN !
    4 R@ CBR.ARGS CV-MAP! THROW
    S" source" 0 R@ _SCT-ARG-TEXT
    _SCT-ENTRY-A @ _SCT-ENTRY-U @ S" entry" 1 R@ _SCT-ARG-TEXT
    _SCT-INPUT-A @ _SCT-INPUT-U @ S" input" 2 R@ _SCT-ARG-TEXT
    _SCT-MEM @ S" memory" 3 R@ _SCT-ARG-INT
    R> ;

: _SCT-ASK  ( source-a source-u -- request status )
    _SCT-REQUEST DUP _SCT-BUS @ CBUS-DISPATCH ;

: _SCT-COMPLETE?  ( request -- flag )
    CBR.FLAGS @ CBR-F-COMPLETE AND 0<> ;

\ Ticks until REQUEST completes, within a bound.
: _SCT-SETTLE  ( request -- )
    10000 BEGIN
        OVER _SCT-COMPLETE? 0= OVER 0> AND
    WHILE
        _SCT-INST @ SBOX-CAPABILITY-TICK DROP 1-
    REPEAT
    DROP _SCT-COMPLETE? _SCT-ASSERT ;

\ =====================================================================
\  Replies
\ =====================================================================

: _SCT-TEXT=  ( text-a text-u value -- flag )
    DUP 0= IF DROP 2DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-STRING <> IF DROP 2DROP 0 EXIT THEN
    DUP CV-DATA@ SWAP CV-LEN@ COMPARE 0= ;

: _SCT-INT=  ( n value -- flag )
    DUP 0= IF 2DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-INT <> IF 2DROP 0 EXIT THEN
    CV-DATA@ = ;

: _SCT-NULL?  ( value -- flag )
    DUP 0= IF EXIT THEN CV-TYPE@ CV-T-NULL = ;

: _SCT-OK?  ( request -- flag )
    S" ok" ROT CBR.RESULT CV-MAP-FIND
    DUP 0= IF EXIT THEN
    DUP CV-TYPE@ CV-T-BOOL = SWAP CV-DATA@ 0<> AND ;

: _SCT-SHOW  ( value -- )
    DUP 0= IF DROP ." (none)" EXIT THEN
    DUP CV-TYPE@ CV-T-STRING = IF
        DUP CV-DATA@ SWAP CV-LEN@ TYPE EXIT
    THEN
    DUP CV-TYPE@ CV-T-INT = IF CV-DATA@ . EXIT THEN
    ." type " CV-TYPE@ . ;

\ Prints a failure reply, so a failing check names what went wrong.
: _SCT-EXPLAIN  ( request -- )
    ." SBOX CAPABILITY REPLY status " DUP CBR.STATUS @ .
    S" error" ROT CBR.RESULT CV-MAP-FIND
    DUP _SCT-NULL? IF DROP CR EXIT THEN
    ." step " S" step" 2 PICK CV-MAP-FIND _SCT-SHOW
    ."  code " S" code" 2 PICK CV-MAP-FIND _SCT-SHOW
    ."  text " S" text" ROT CV-MAP-FIND _SCT-SHOW CR ;

\ A completed OK request whose reply is the JSON text RESULT.
: _SCT-RESULT=  ( result-a result-u request -- )
    DUP _SCT-OK? 0= IF DUP _SCT-EXPLAIN THEN
    DUP CBR.STATUS @ CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-OK? _SCT-ASSERT
    S" error" 2 PICK CBR.RESULT CV-MAP-FIND _SCT-NULL? _SCT-ASSERT
    S" result" ROT CBR.RESULT CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT ;

\ The error map of a completed failure reply.
: _SCT-ERROR  ( request -- error )
    DUP CBR.STATUS @ CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-OK? 0= _SCT-ASSERT
    S" result" 2 PICK CBR.RESULT CV-MAP-FIND _SCT-NULL? _SCT-ASSERT
    S" error" ROT CBR.RESULT CV-MAP-FIND ;

: _SCT-STEP=  ( step-a step-u code-a code-u error -- )
    >R
    S" code" R@ CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT
    S" step" R> CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT ;

\ The failure has a source position.
: _SCT-AT=  ( line column length text-a text-u error -- )
    >R
    S" text" R@ CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT
    S" length" R@ CV-MAP-FIND _SCT-INT= _SCT-ASSERT
    S" column" R@ CV-MAP-FIND _SCT-INT= _SCT-ASSERT
    S" line" R@ CV-MAP-FIND _SCT-INT= _SCT-ASSERT
    S" abort" R> CV-MAP-FIND _SCT-NULL? _SCT-ASSERT ;

\ The failure has no source position.
: _SCT-NOWHERE  ( error -- )
    >R
    S" line" R@ CV-MAP-FIND _SCT-NULL? _SCT-ASSERT
    S" column" R@ CV-MAP-FIND _SCT-NULL? _SCT-ASSERT
    S" length" R@ CV-MAP-FIND _SCT-NULL? _SCT-ASSERT
    S" text" R> CV-MAP-FIND _SCT-NULL? _SCT-ASSERT ;

\ =====================================================================
\  Setup
\ =====================================================================

: _SCT-L!  ( value field -- )
    _SCT-POLICY SBOX-LIMIT-CAP SBOX-LIMITS-S-OK = _SCT-ASSERT ;

\ A complete host policy.  The instruction budget ends a loop quickly.
: _SCT-POLICY-INIT  ( -- )
    _SCT-POLICY SBOX-LIMITS-BEGIN SBOX-LIMITS-S-OK = _SCT-ASSERT
      5000 SBOX-LIMIT-INSTRUCTION-BUDGET _SCT-L!
      8192 SBOX-LIMIT-VALUE-OP-BUDGET _SCT-L!
    262144 SBOX-LIMIT-COPY-BUDGET _SCT-L!
    600000 SBOX-LIMIT-WALL-MS _SCT-L!
         8 SBOX-LIMIT-DEPTH _SCT-L!
      1024 SBOX-LIMIT-BLOB-BYTES _SCT-L!
        64 SBOX-LIMIT-LIST-COUNT _SCT-L!
        64 SBOX-LIMIT-MAP-COUNT _SCT-L!
       512 SBOX-LIMIT-INPUT-NODES _SCT-L!
     65536 SBOX-LIMIT-INPUT-BYTES _SCT-L!
       512 SBOX-LIMIT-OUTPUT-ARENA-NODES _SCT-L!
     65536 SBOX-LIMIT-OUTPUT-ARENA-BYTES _SCT-L!
       512 SBOX-LIMIT-OUTPUT-RESULT-NODES _SCT-L!
     65536 SBOX-LIMIT-OUTPUT-RESULT-BYTES _SCT-L!
       256 SBOX-LIMIT-DATA-STACK _SCT-L!
        64 SBOX-LIMIT-CALL-FRAMES _SCT-L!
        64 SBOX-LIMIT-LOOP-FRAMES _SCT-L!
    _SCT-MEMORY-MAX SBOX-LIMIT-MEMORY-BYTES _SCT-L!
    _SCT-POLICY SBOX-LIMITS-SEAL SBOX-LIMITS-S-OK = _SCT-ASSERT ;

: _SCT-BIND  ( capacity -- status )
    >R _SCT-CTX @ _SCT-POLICY 256 1000 R> _SCT-INST @ SBOX-CAPABILITY-BIND ;

: _SCT-SETUP  ( -- )
    _SCT-HEAD PHEAD-INIT
    0x44 _SCT-HEAD PHEAD.ID C!
    0x45 _SCT-HEAD PHEAD.CURRENT-ROOT C!
    4 CTX-NEW THROW _SCT-CTX !
    _SCT-HEAD _SCT-CTX @ CTX.PRACTICE !
    _SCT-CTX @ DUP CTX.FLAGS @ CTX-F-ACTIVE OR SWAP CTX.FLAGS !
    _SCT-CTX @ CTX-TOUCH
    _SCT-POLICY-INIT
    SBOX-CAPABILITY-COMPONENT CINST-NEW THROW _SCT-INST !
    CREG-NEW THROW _SCT-REG !
    _SCT-INST @ _SCT-REG @ CREG-INST+ 0= _SCT-ASSERT
    _SCT-REG @ 0 CBUS-NEW THROW _SCT-BUS !
    _SCT-DEFAULTS
    0 _SCT-DONE ! ;

: _SCT-TEARDOWN  ( -- )
    _SCT-BUS @ CBUS-FREE
    _SCT-INST @ _SCT-REG @ CREG-INST- 0= _SCT-ASSERT
    _SCT-REG @ CREG-FREE
    _SCT-INST @ CINST-FREE
    0 _SCT-CTX @ CTX.FLAGS ! _SCT-CTX @ CTX-FREE ;

\ =====================================================================
\  Cases
\ =====================================================================

: _SCT-NOT-INTERNAL  ( address length -- flag )
    S" internal" COMPARE 0<> ;

\ Every code a reply can name has its own name, and the schemas suit a
\ caller that speaks JSON, strictly.
: _SCT-DESCRIPTORS  ( -- )
    SBOX-CAPABILITY-COMPONENT COMP-CAPS-VALID? _SCT-ASSERT
    _SCT-CAP DUP 0<> _SCT-ASSERT
    DUP CAP.EFFECTS @ CAP-E-OBSERVE = _SCT-ASSERT
    DUP CAP.IN-SCHEMA @ IVJSON-SCHEMA-COMPATIBLE? _SCT-ASSERT
    DUP CAP.IN-SCHEMA @ CSJSON-STRICT? _SCT-ASSERT
    CAP.OUT-SCHEMA @ IVJSON-SCHEMA-COMPATIBLE? _SCT-ASSERT
    -1 SBOX-COMPILER-E-INTERNAL 1 DO
        I _SBXC-COMPILE-CODE$ _SCT-NOT-INTERNAL AND
    LOOP _SCT-ASSERT
    -1 SBOX-VERIFIER-D-INTERNAL 1 DO
        I _SBXC-VERIFY-CODE$ _SCT-NOT-INTERNAL AND
    LOOP _SCT-ASSERT
    -1 SBOX-VM-TRAP-MAP-KEY-ORDER 1+ 1 DO
        I _SBXC-TRAP-CODE$ _SCT-NOT-INTERNAL AND
    LOOP _SCT-ASSERT
    -1 SBOX-VM-EXHAUST-OUTPUT-RESULT-BYTES 1+ 1 DO
        I _SBXC-EXHAUST-CODE$ _SCT-NOT-INTERNAL AND
    LOOP _SCT-ASSERT
    -1 SBOX-VM-CANCEL-ADAPTER 1+ 1 DO
        I _SBXC-CANCEL-CODE$ _SCT-NOT-INTERNAL AND
    LOOP _SCT-ASSERT
    _SCT-STACK ;

: _SCT-BIND-REFUSALS  ( -- )
    \ An unbound capability refuses a run.
    _SCT-INCREMENT _SCT-ASK CBUS-S-FAILED = _SCT-ASSERT CBR-FREE
    _SCT-INST @ SBOX-CAPABILITY-BUSY? 0= _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-TICK SBOX-CAPABILITY-S-STATE = _SCT-ASSERT
    _SCT-CTX @ _SCT-POLICY 256 1000 2 0 SBOX-CAPABILITY-BIND
        SBOX-CAPABILITY-S-INVALID = _SCT-ASSERT
    0 _SCT-BIND SBOX-CAPABILITY-S-INVALID = _SCT-ASSERT
    _SCT-INST @ CINST-STATE _SBXC-BOUND? 0= _SCT-ASSERT
    2 _SCT-BIND DUP IF ." SBOX CAPABILITY BIND STATUS " DUP . CR THEN
        SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    2 _SCT-BIND SBOX-CAPABILITY-S-STATE = _SCT-ASSERT
    _SCT-STACK ;

: _SCT-SUCCESS  ( -- )
    0 _SCT-DONE !
    S" 41" _SCT-INPUT-U ! _SCT-INPUT-A !
    _SCT-INCREMENT _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP CBR-DEFERRED? _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-BUSY? _SCT-ASSERT
    DUP _SCT-SETTLE
    S" 42" 2 PICK _SCT-RESULT=
    _SCT-DONE @ 1 = _SCT-ASSERT
    CBR-FREE
    _SCT-INST @ SBOX-CAPABILITY-BUSY? 0= _SCT-ASSERT
    \ Memory rounds up to whole cells.
    7 _SCT-MEM !
    _SCT-MEMORY-SIZE _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE S" 8" 2 PICK _SCT-RESULT= CBR-FREE
    \ A run may have all the memory the policy grants.
    _SCT-MEMORY-MAX _SCT-MEM !
    _SCT-MEMORY-SIZE _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE S" 65536" 2 PICK _SCT-RESULT= CBR-FREE
    _SCT-DEFAULTS
    _SCT-STACK ;

: _SCT-BUILD-FAILURES  ( -- )
    _SCT-UNKNOWN _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-COMPLETE? _SCT-ASSERT
    DUP _SCT-ERROR
    S" compile" S" unknown" 4 PICK _SCT-STEP=
    1 43 4 S" FROB" 5 PICK _SCT-AT=
    DROP CBR-FREE
    _SCT-TWO-LINES _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR
    S" compile" S" unknown" 4 PICK _SCT-STEP=
    3 3 4 S" FROB" 5 PICK _SCT-AT=
    DROP CBR-FREE
    _SCT-NO-RESULT _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR
    S" verify" S" stack-return" 4 PICK _SCT-STEP=
    1 48 6 S" RETURN" 5 PICK _SCT-AT=
    DROP CBR-FREE
    _SCT-STACK ;

: _SCT-INPUT-FAILURES  ( -- )
    S" {" _SCT-INPUT-U ! _SCT-INPUT-A !
    _SCT-INCREMENT _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input" S" json-invalid" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    S" 1.5" _SCT-INPUT-U ! _SCT-INPUT-A !
    _SCT-INCREMENT _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input" S" json-unsupported" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    \ Nine levels exceed the policy's depth of eight.
    S" [[[[[[[[[1]]]]]]]]]" _SCT-INPUT-U ! _SCT-INPUT-A !
    _SCT-INCREMENT _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input" S" limit" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    _SCT-DEFAULTS
    S" nope" _SCT-ENTRY-U ! _SCT-ENTRY-A !
    _SCT-INCREMENT _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" entry" S" entry" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    _SCT-DEFAULTS
    \ A run needs a calling instance.
    0 _SCT-CALLER !
    _SCT-INCREMENT _SCT-ASK CBUS-S-DENIED = _SCT-ASSERT CBR-FREE
    _SCT-DEFAULTS
    \ More memory than the policy grants is refused before any build.
    _SCT-MEMORY-MAX 8 + _SCT-MEM !
    _SCT-INCREMENT _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input" S" limit" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    _SCT-DEFAULTS
    _SCT-STACK ;

: _SCT-RUN-FAILURES  ( -- )
    S" 5" _SCT-INPUT-U ! _SCT-INPUT-A !
    _SCT-DIVIDE _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE
    DUP _SCT-ERROR S" run" S" divide-by-zero" 4 PICK _SCT-STEP=
    DUP _SCT-NOWHERE S" abort" ROT CV-MAP-FIND _SCT-NULL? _SCT-ASSERT
    CBR-FREE
    _SCT-ABORT _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE
    DUP _SCT-ERROR S" run" S" explicit-abort" 4 PICK _SCT-STEP=
    DUP _SCT-NOWHERE 7 SWAP S" abort" ROT CV-MAP-FIND _SCT-INT= _SCT-ASSERT
    CBR-FREE
    _SCT-FOREVER _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE
    DUP _SCT-ERROR S" run" S" instruction-units" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    _SCT-DEFAULTS
    _SCT-STACK ;

\ A cancelled run completes as cancelled; a full capability is busy; a
\ closing caller's runs end and others go on.
: _SCT-LIFECYCLE  ( -- )
    0 _SCT-DONE !
    _SCT-FOREVER _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP CBR-CANCEL
    DUP _SCT-SETTLE
    DUP CBR.STATUS @ CBUS-S-CANCELLED = _SCT-ASSERT
    CBR-FREE
    _SCT-FOREVER _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT _SCT-A !
    88 _SCT-CALLER !
    _SCT-FOREVER _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT _SCT-B !
    _SCT-FOREVER _SCT-ASK CBUS-S-BUSY = _SCT-ASSERT CBR-FREE
    77 1 _SCT-INST @ SBOX-CAPABILITY-OWNER-DRAIN
        SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    _SCT-A @ _SCT-COMPLETE? _SCT-ASSERT
    _SCT-A @ CBR.STATUS @ CBUS-S-CANCELLED = _SCT-ASSERT
    _SCT-B @ _SCT-COMPLETE? 0= _SCT-ASSERT
    _SCT-B @ _SCT-SETTLE
    _SCT-B @ _SCT-ERROR S" run" S" instruction-units" 4 PICK _SCT-STEP=
    DROP
    _SCT-A @ CBR-FREE _SCT-B @ CBR-FREE
    \ The cancelled run, the busy refusal, the drained run and B.
    _SCT-DONE @ 4 = _SCT-ASSERT
    _SCT-DEFAULTS
    _SCT-STACK ;

\ Unbinding completes what is still running, and the capability then
\ refuses new runs until it is bound again.
: _SCT-UNBIND  ( -- )
    _SCT-FOREVER _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-UNBIND SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    DUP _SCT-COMPLETE? _SCT-ASSERT
    DUP CBR.STATUS @ CBUS-S-CANCELLED = _SCT-ASSERT
    CBR-FREE
    _SCT-INST @ SBOX-CAPABILITY-UNBIND SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    _SCT-INCREMENT _SCT-ASK CBUS-S-FAILED = _SCT-ASSERT CBR-FREE
    _SCT-STACK ;

: _SCT-RUN  ( -- )
    0 _SCT-FAILS !
    0 _SCT-CHECKS !
    DEPTH _SCT-DEPTH !
    _SCT-AVAILABLE _SCT-MEMORY !
    _SCT-SETUP
    _SCT-DESCRIPTORS
    _SCT-BIND-REFUSALS
    _SCT-SUCCESS
    _SCT-BUILD-FAILURES
    _SCT-INPUT-FAILURES
    _SCT-RUN-FAILURES
    _SCT-LIFECYCLE
    _SCT-UNBIND
    _SCT-TEARDOWN
    _SCT-AVAILABLE _SCT-MEMORY @ = _SCT-ASSERT
    _SCT-STACK
    _SCT-FAILS @ 0= IF
        ." SBOX CAPABILITY CONTRACTS PASS " _SCT-CHECKS @ . CR
    ELSE
        ." SBOX CAPABILITY CONTRACTS FAIL " _SCT-FAILS @ . CR
    THEN ;

_SCT-RUN
