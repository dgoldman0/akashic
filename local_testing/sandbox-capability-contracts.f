\ Contracts for the shared sandbox capability: its descriptors and
\ schemas, immediate replies for build, input and entry failures, runs
\ completed from the tick, cancellation, owner drain and unbind; then
\ installed modules on a RAM filesystem: installs and their refusals,
\ listing, invoking, a test applet that must ask the user first,
\ revocation and a restart; and that the capability returns every byte
\ it allocates.

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
\ The JSON text "" for an empty string.
CREATE _SCT-QQ 34 C, 34 C,

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
\ A scalar entry, whose name at offset 59 stands in for the signature the
\ pure profile requires.
: _SCT-ECHO  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 RETURN END ENTRY SIGNATURE 1 main main" ;
: _SCT-SCALAR  ( -- address length )
    S" FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 RETURN END ENTRY main main" ;
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

\ A helper returning seventeen cells, which the format allows.
: _SCT-WIDE  ( -- address length )
    0 _SCT-SRC-U !
    S" FUNCTION many PARAMS 0 RESULTS 17 LOCALS 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 RETURN END" _SCT-SRC+
    S"  FUNCTION main PARAMS 1 RESULTS 1 LOCALS 0 CALL many 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP 2DROP DROP" _SCT-SRC+
    S"  RETURN END ENTRY SIGNATURE 1 main main" _SCT-SRC+
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
\ Capability ID has EFFECTS, and its schemas suit a JSON caller.
: _SCT-CAP-OK  ( id-a id-u effects -- )
    >R SBOX-CAPABILITY-COMPONENT COMP-CAP-FIND
    DUP 0<> _SCT-ASSERT
    DUP CAP.EFFECTS @ R> = _SCT-ASSERT
    DUP CAP.IN-SCHEMA @ IVJSON-SCHEMA-COMPATIBLE? _SCT-ASSERT
    DUP CAP.IN-SCHEMA @ CSJSON-STRICT? _SCT-ASSERT
    CAP.OUT-SCHEMA @ IVJSON-SCHEMA-COMPATIBLE? _SCT-ASSERT ;

: _SCT-DESCRIPTORS  ( -- )
    SBOX-CAPABILITY-COMPONENT COMP-CAPS-VALID? _SCT-ASSERT
    SBOX-CAPABILITY-COMPONENT COMP.CAPS-N @ 5 = _SCT-ASSERT
    S" org.akashic.sandbox/test" CAP-E-OBSERVE _SCT-CAP-OK
    \ Installing keeps a module, so it needs approval.
    S" org.akashic.sandbox/install" CAP-E-PERSIST _SCT-CAP-OK
    S" org.akashic.sandbox/invoke" CAP-E-OBSERVE _SCT-CAP-OK
    S" org.akashic.sandbox/list" CAP-E-OBSERVE _SCT-CAP-OK
    \ Asking grants nothing itself; the user does.
    S" org.akashic.sandbox/authorize" CAP-E-OBSERVE _SCT-CAP-OK
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
    \ An empty string crosses JSON both ways.
    _SCT-QQ 2 _SCT-INPUT-U ! _SCT-INPUT-A !
    _SCT-ECHO _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE _SCT-QQ 2 2 PICK _SCT-RESULT= CBR-FREE
    S" 41" _SCT-INPUT-U ! _SCT-INPUT-A !
    \ A function may return more cells than a scalar entry could.
    _SCT-WIDE _SCT-ASK CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE S" 41" 2 PICK _SCT-RESULT= CBR-FREE
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
    \ A module for the shared capability can never carry a scalar entry.
    _SCT-SCALAR _SCT-ASK CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR
    S" compile" S" signature" 4 PICK _SCT-STEP=
    1 60 4 S" main" 5 PICK _SCT-AT=
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

\ =====================================================================
\  Modules
\ =====================================================================

VARIABLE _SCT-VFS
VARIABLE _SCT-OLD-VFS
VARIABLE _SCT-APPLET
VARIABLE _SCT-PRINCIPAL
VARIABLE _SCT-CALLER-GEN
VARIABLE _SCT-MODULE-A
VARIABLE _SCT-MODULE-U
VARIABLE _SCT-REVISION
VARIABLE _SCT-MAP
VARIABLE _SCT-SPEC-N
VARIABLE _SCT-JSON-U
VARIABLE _SCT-DECL-U
VARIABLE _SCT-FILE
VARIABLE _SCT-FILE-U

CREATE _SCT-SPECS 4 48 * ALLOT
CREATE _SCT-JSON-BUF 256 ALLOT
CREATE _SCT-J-INT 16 ALLOT
CREATE _SCT-J-STR 16 ALLOT
CREATE _SCT-J-BAD 16 ALLOT
CREATE _SCT-J-OPEN 16 ALLOT
CREATE _SCT-J-X 16 ALLOT
CREATE _SCT-J-INT-OUT 16 ALLOT
CREATE _SCT-APPLET-DESC COMP-DESC ALLOT
CREATE _SCT-RID 32 ALLOT
CREATE _SCT-KEY 32 ALLOT
CREATE _SCT-PAGE-NAME 2 ALLOT
CREATE _SCT-ART 32 ALLOT
CREATE _SCT-BYTE 8 ALLOT
CREATE _SCT-BUILD-RAW SBOX-BUILD-SIZE 7 + ALLOT
_SCT-BUILD-RAW _SCT-ALIGN8 CONSTANT _SCT-BUILD
CREATE _SCT-DECL-RAW 512 7 + ALLOT
_SCT-DECL-RAW _SCT-ALIGN8 CONSTANT _SCT-DECL
CREATE _SCT-WS-RAW SBOX-DECL-WORKSPACE-SIZE 7 + ALLOT
_SCT-WS-RAW _SCT-ALIGN8 CONSTANT _SCT-WS
\ Canonical schema bytes: any byte string, and any integer.
CREATE _SCT-BYTES-SCHEMA 12 ALLOT
CREATE _SCT-INT-SCHEMA 12 ALLOT

: _SCT-CAT$  ( -- address length ) S" /sbx-catalog.bin" ;
: _SCT-PACK$  ( -- address length ) S" /sbx-pack.bin" ;

: _SCT-PAIR!  ( address length pair -- ) TUCK 8 + ! ! ;
: _SCT-PAIR@  ( pair -- address length ) DUP @ SWAP 8 + @ ;

\ TEXT with each ' turned into ", copied into the JSON buffer.
: _SCT-JSON  ( address length -- address' length )
    _SCT-JSON-BUF _SCT-JSON-U @ +
    OVER 0 ?DO
        2 PICK I + C@ DUP [CHAR] ' = IF DROP 34 THEN
        OVER I + C!
    LOOP
    ROT DROP SWAP DUP _SCT-JSON-U +! ;

\ Schema bytes for a node that admits only TYPE.
: _SCT-SCHEMA-BYTES!  ( type address -- )
    DUP 12 0 FILL
    S" AKSCHEMA" 2 PICK SWAP MOVE
    SWAP CS-TYPE-BIT SWAP 8 + C! ;

: _SCT-NO-SPECS  ( -- ) 0 _SCT-SPEC-N ! ;

\ Adds the spec of entry NAME with the JSON Schemas IN and OUT.
: _SCT-SPEC+  ( name-a name-u in-pair out-pair -- )
    _SCT-SPEC-N @ 48 * _SCT-SPECS + >R
    _SCT-PAIR@ R@ 40 + ! R@ 32 + !
    _SCT-PAIR@ R@ 24 + ! R@ 16 + !
    R@ 8 + ! R> !
    1 _SCT-SPEC-N +! ;

: _SCT-SPEC@  ( index -- name-a name-u in-a in-u out-a out-u )
    48 * _SCT-SPECS + >R
    R@ @ R@ 8 + @ R@ 16 + @ R@ 24 + @ R@ 32 + @ R> 40 + @ ;

: _SCT-INCREMENT-SPECS  ( -- )
    _SCT-NO-SPECS S" main" _SCT-J-INT _SCT-J-INT _SCT-SPEC+ ;

: _SCT-PUT-TEXT  ( text-a text-u key-a key-u index map -- )
    CV-MAP-SLOT! THROW CV-STRING! THROW ;

\ A request for capability ID with COUNT arguments, from the current
\ principal and caller.
: _SCT-NEW  ( id-a id-u count -- request )
    CBR-NEW THROW >R
    _SCT-PRINCIPAL @ R@ CBR.PRINCIPAL !
    _SCT-INST @ R@ CBR-TARGET!
    -ROT SBOX-CAPABILITY-COMPONENT COMP-CAP-FIND R@ CBR.CAP !
    ['] _SCT-COMPLETE R@ CBR.COMPLETE-XT !
    _SCT-CALLER @ R@ CBR.CALLER-ID !
    _SCT-CALLER-GEN @ R@ CBR.CALLER-GEN !
    R@ CBR.ARGS CV-MAP! THROW
    R> ;

: _SCT-DISPATCH  ( request -- request status ) DUP _SCT-BUS @ CBUS-DISPATCH ;

\ The entry specs as argument INDEX.
: _SCT-ARG-SPECS  ( index request -- )
    >R S" entries" ROT R> CBR.ARGS CV-MAP-SLOT! THROW
    _SCT-SPEC-N @ OVER CV-LIST! THROW
    _SCT-SPEC-N @ 0 ?DO
        I OVER CV-LIST-NTH DUP _SCT-MAP ! 3 SWAP CV-MAP! THROW
        I _SCT-SPEC@
        S" output" 2 _SCT-MAP @ _SCT-PUT-TEXT
        S" input" 0 _SCT-MAP @ _SCT-PUT-TEXT
        S" name" 1 _SCT-MAP @ _SCT-PUT-TEXT
    LOOP
    DROP ;

\ Installs the current module revision from SOURCE with the current
\ specs and memory.  Installing persists, so the request carries the
\ approval a host's policy asks for.
: _SCT-INSTALL  ( source-a source-u -- request status )
    S" org.akashic.sandbox/install" 5 _SCT-NEW >R
    S" source" 4 R@ _SCT-ARG-TEXT
    0 R@ _SCT-ARG-SPECS
    _SCT-MEM @ S" memory" 1 R@ _SCT-ARG-INT
    _SCT-MODULE-A @ _SCT-MODULE-U @ S" module" 2 R@ _SCT-ARG-TEXT
    _SCT-REVISION @ S" revision" 3 R@ _SCT-ARG-INT
    R@ CBR.FLAGS @ CBR-F-APPROVED OR R@ CBR.FLAGS !
    R> _SCT-DISPATCH ;

: _SCT-INVOKE  ( -- request status )
    S" org.akashic.sandbox/invoke" 4 _SCT-NEW >R
    _SCT-ENTRY-A @ _SCT-ENTRY-U @ S" entry" 0 R@ _SCT-ARG-TEXT
    _SCT-INPUT-A @ _SCT-INPUT-U @ S" input" 1 R@ _SCT-ARG-TEXT
    _SCT-MODULE-A @ _SCT-MODULE-U @ S" module" 2 R@ _SCT-ARG-TEXT
    _SCT-REVISION @ S" revision" 3 R@ _SCT-ARG-INT
    R> _SCT-DISPATCH ;

: _SCT-LIST  ( first -- request status )
    S" org.akashic.sandbox/list" 1 _SCT-NEW >R
    S" first" 0 R@ _SCT-ARG-INT
    R> _SCT-DISPATCH ;

: _SCT-AUTHORIZE  ( -- request status )
    S" org.akashic.sandbox/authorize" 2 _SCT-NEW >R
    _SCT-MODULE-A @ _SCT-MODULE-U @ S" module" 0 R@ _SCT-ARG-TEXT
    _SCT-REVISION @ S" revision" 1 R@ _SCT-ARG-INT
    R> _SCT-DISPATCH ;

\ The Agent's requests name Desk as their caller.
: _SCT-AS-AGENT  ( -- )
    CPRINC-AGENT _SCT-PRINCIPAL ! 77 _SCT-CALLER ! 1 _SCT-CALLER-GEN ! ;

: _SCT-AS-APPLET  ( -- )
    CPRINC-COMPONENT _SCT-PRINCIPAL !
    _SCT-APPLET @ CINST.ID @ _SCT-CALLER !
    _SCT-APPLET @ CINST.GENERATION @ _SCT-CALLER-GEN ! ;

: _SCT-MODULE!  ( name-a name-u revision -- )
    _SCT-REVISION ! _SCT-MODULE-U ! _SCT-MODULE-A ! ;

: _SCT-INPUT!  ( address length -- ) _SCT-INPUT-U ! _SCT-INPUT-A ! ;

\ A completed OK request whose reply carries no result.
: _SCT-DONE-OK  ( request -- )
    DUP _SCT-OK? 0= IF DUP _SCT-EXPLAIN THEN
    DUP CBR.STATUS @ CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-OK? _SCT-ASSERT
    S" result" 2 PICK CBR.RESULT CV-MAP-FIND _SCT-NULL? _SCT-ASSERT
    S" error" ROT CBR.RESULT CV-MAP-FIND _SCT-NULL? _SCT-ASSERT ;

\ The failure names TEXT and has no source position.
: _SCT-DETAIL=  ( text-a text-u error -- )
    >R
    S" text" R@ CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT
    S" line" R> CV-MAP-FIND _SCT-NULL? _SCT-ASSERT ;

: _SCT-TEXT-IS  ( text-a text-u value -- )
    DUP >R _SCT-TEXT= DUP 0= IF
        ." SBOX CAPABILITY TEXT " R@ _SCT-SHOW CR
    THEN
    R> DROP _SCT-ASSERT ;

\ A list reply with COUNT modules, and NEXT, or null for -1.
: _SCT-PAGE=  ( request count next -- )
    ROT CBR.RESULT >R
    DUP 0< IF
        DROP S" next" R@ CV-MAP-FIND _SCT-NULL?
    ELSE
        S" next" R@ CV-MAP-FIND _SCT-INT=
    THEN
    _SCT-ASSERT
    S" modules" R> CV-MAP-FIND CV-LEN@ = _SCT-ASSERT ;

\ The item of the list reply REQUEST for module NAME's REVISION, or 0.
: _SCT-ITEM  ( name-a name-u revision request -- item|0 )
    S" modules" ROT CBR.RESULT CV-MAP-FIND
    DUP CV-LEN@ 0 ?DO
        I OVER CV-LIST-NTH
        S" revision" 2 PICK CV-MAP-FIND 3 PICK SWAP _SCT-INT= IF
            4 PICK 4 PICK S" module" 4 PICK CV-MAP-FIND _SCT-TEXT= IF
                NIP NIP NIP NIP UNLOOP EXIT
            THEN
        THEN
        DROP
    LOOP
    2DROP 2DROP 0 ;

\ The item for NAME's REVISION on the pages A and B hold.
: _SCT-FIND  ( name-a name-u revision -- item|0 )
    >R 2DUP R@ _SCT-A @ _SCT-ITEM ?DUP IF NIP NIP R> DROP EXIT THEN
    R> _SCT-B @ _SCT-ITEM ;

\ ITEM is in STATE, and its one entry, main, has the JSON Schemas IN and
\ OUT.
: _SCT-ITEM=  ( in-pair out-pair state-a state-u item -- )
    DUP 0= IF DROP 2DROP 2DROP 0 _SCT-ASSERT EXIT THEN
    >R
    S" state" R@ CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT
    S" entries" R> CV-MAP-FIND
    DUP CV-LEN@ 1 = _SCT-ASSERT
    0 SWAP CV-LIST-NTH >R
    S" main" S" name" R@ CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT
    _SCT-PAIR@ S" output" R@ CV-MAP-FIND _SCT-TEXT-IS
    _SCT-PAIR@ S" input" R> CV-MAP-FIND _SCT-TEXT-IS ;

\ The module the capability holds for NAME's REVISION.
: _SCT-HELD  ( name-a name-u revision -- module|0 )
    >R _SCT-RID _SCT-WS SBOX-DECL-MODULE-RID SBOX-DECL-S-OK = _SCT-ASSERT
    _SCT-RID R> _SCT-INST @ SBOX-CAPABILITY-MODULES@ SBOX-MODULE-FIND ;

: _SCT-STORAGE  ( -- status )
    _SCT-REG @ _SCT-VFS @ _SCT-CAT$ _SCT-PACK$ _SCT-INST @
    SBOX-CAPABILITY-MODULES ;

: _SCT-MODULES-SETUP  ( -- )
    VFS-CUR _SCT-OLD-VFS !
    1048576 A-XMEM ARENA-NEW THROW
    VFS-RAM-BINDING 0 VFS-NEW THROW _SCT-VFS !
    _SCT-VFS @ VFS-USE
    CV-T-BYTES _SCT-BYTES-SCHEMA _SCT-SCHEMA-BYTES!
    CV-T-INT _SCT-INT-SCHEMA _SCT-SCHEMA-BYTES!
    0 _SCT-JSON-U !
    S" {'type':'integer'}" _SCT-JSON _SCT-J-INT _SCT-PAIR!
    S" {'type':'string'}" _SCT-JSON _SCT-J-STR _SCT-PAIR!
    S" {'type':" _SCT-JSON _SCT-J-BAD _SCT-PAIR!
    S" {'type':'object'}" _SCT-JSON _SCT-J-OPEN _SCT-PAIR!
    S" 'x'" _SCT-JSON _SCT-J-X _SCT-PAIR!
    \ How the JSON form writes any integer: its bounds are the cell's.
    S" {'type':'integer','minimum':-9223372036854775808,'maximum':9223372036854775807}"
        _SCT-JSON _SCT-J-INT-OUT _SCT-PAIR!
    _SCT-APPLET-DESC DUP COMP-DESC-INIT
    S" org.test.applet" 2 PICK COMP.ID-U ! SWAP COMP.ID-A !
    _SCT-APPLET-DESC CINST-NEW THROW _SCT-APPLET !
    _SCT-APPLET @ _SCT-REG @ CREG-INST+ 0= _SCT-ASSERT
    CPRINC-USER _SCT-PRINCIPAL ! 1 _SCT-CALLER-GEN ! ;

: _SCT-MODULES-TEARDOWN  ( -- )
    _SCT-APPLET @ _SCT-REG @ CREG-INST- 0= _SCT-ASSERT
    _SCT-APPLET @ CINST-FREE
    _SCT-OLD-VFS @ VFS-USE
    _SCT-VFS @ VFS-DESTROY ;

\ Without module storage, module requests fail and the list is empty.
: _SCT-NO-STORAGE  ( -- )
    _SCT-DEFAULTS _SCT-AS-AGENT
    S" increment" 1 _SCT-MODULE!
    _SCT-INVOKE CBUS-S-FAILED = _SCT-ASSERT CBR-FREE
    _SCT-AUTHORIZE CBUS-S-FAILED = _SCT-ASSERT CBR-FREE
    _SCT-INCREMENT-SPECS
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-FAILED = _SCT-ASSERT CBR-FREE
    0 _SCT-LIST CBUS-S-OK = _SCT-ASSERT DUP 0 -1 _SCT-PAGE= CBR-FREE
    _SCT-INST @ SBOX-CAPABILITY-STORE@ 0= _SCT-ASSERT
    0 _SCT-VFS @ _SCT-CAT$ _SCT-PACK$ _SCT-INST @ SBOX-CAPABILITY-MODULES
        SBOX-CAPABILITY-S-INVALID = _SCT-ASSERT
    _SCT-STORAGE SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    _SCT-STORAGE SBOX-CAPABILITY-S-STATE = _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-STORE@ 0<> _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-MODULES@ SBOX-MODULE-COUNT@ 0= _SCT-ASSERT
    _SCT-STACK ;

\ Installs: refusals before and after the build, success, a repeat that
\ changes nothing, other content for an installed revision, and a second
\ revision.
: _SCT-INSTALLS  ( -- )
    _SCT-DEFAULTS _SCT-AS-AGENT
    \ A module name is spelled as an entry name is.
    S" Bad" 1 _SCT-MODULE! _SCT-INCREMENT-SPECS
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" module" S" name" 4 PICK _SCT-STEP=
    S" Bad" ROT _SCT-DETAIL= CBR-FREE
    S" increment" 1 _SCT-MODULE!
    \ Each entry has its schemas, and only the module's entries have any.
    _SCT-NO-SPECS
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" entries" S" missing" 4 PICK _SCT-STEP=
    S" main" ROT _SCT-DETAIL= CBR-FREE
    _SCT-INCREMENT-SPECS S" other" _SCT-J-INT _SCT-J-INT _SCT-SPEC+
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" entries" S" unknown" 4 PICK _SCT-STEP=
    S" other" ROT _SCT-DETAIL= CBR-FREE
    _SCT-INCREMENT-SPECS S" main" _SCT-J-INT _SCT-J-INT _SCT-SPEC+
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" entries" S" duplicate" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    \ Schemas are JSON Schema text, and must describe closed values.
    _SCT-NO-SPECS S" main" _SCT-J-BAD _SCT-J-INT _SCT-SPEC+
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input-schema" S" json-invalid" 4 PICK _SCT-STEP=
    S" main" ROT _SCT-DETAIL= CBR-FREE
    _SCT-NO-SPECS S" main" _SCT-J-INT _SCT-J-OPEN _SCT-SPEC+
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" output-schema" S" json-unsupported" 4 PICK _SCT-STEP=
    S" main" ROT _SCT-DETAIL= CBR-FREE
    \ A build fails as a test's does.
    _SCT-INCREMENT-SPECS
    _SCT-UNKNOWN _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" compile" S" unknown" 4 PICK _SCT-STEP=
    1 43 4 S" FROB" 5 PICK _SCT-AT= DROP CBR-FREE
    _SCT-MEMORY-MAX 8 + _SCT-MEM !
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input" S" limit" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    0 _SCT-MEM !
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT DUP _SCT-DONE-OK CBR-FREE
    \ The same install again changes nothing.
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT DUP _SCT-DONE-OK CBR-FREE
    _SCT-INST @ SBOX-CAPABILITY-MODULES@ SBOX-MODULE-COUNT@ 1 = _SCT-ASSERT
    \ Other content cannot take an installed revision.
    _SCT-NO-SPECS S" main" _SCT-J-STR _SCT-J-INT _SCT-SPEC+
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" store" S" duplicate" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    _SCT-INCREMENT-SPECS S" increment" 2 _SCT-MODULE!
    _SCT-INCREMENT _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT DUP _SCT-DONE-OK CBR-FREE
    \ An echo whose result can never match its declared output.
    S" echo" 1 _SCT-MODULE!
    _SCT-NO-SPECS S" main" _SCT-J-STR _SCT-J-INT _SCT-SPEC+
    _SCT-ECHO _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT DUP _SCT-DONE-OK CBR-FREE
    _SCT-INST @ SBOX-CAPABILITY-MODULES@ SBOX-MODULE-COUNT@ 3 = _SCT-ASSERT
    _SCT-DEFAULTS
    _SCT-STACK ;

\ A module whose entry takes bytes, which JSON cannot carry, installed
\ as another installer could.
: _SCT-BYTES-MODULE  ( -- )
    _SCT-BUILD SBOX-BUILD-INIT SBOX-BUILD-S-OK = _SCT-ASSERT
    _SCT-ECHO _SCT-INST @ CINST-STATE _SBXC.PROFILE 0 _SCT-BUILD SBOX-BUILD
        SBOX-BUILD-S-OK = _SCT-ASSERT
    1 0 24 SBOX-DECL-MEASURE SBOX-DECL-S-OK = _SCT-ASSERT _SCT-DECL-U !
    _SCT-BUILD SBOX-BUILD-PLAN@ DROP >R
    1 R@ SBOX-PLAN-ARTIFACT-DIGEST@ R@ SBOX-PLAN-PROFILE-DIGEST@
    1 0 24 _SCT-DECL _SCT-DECL-U @ SBOX-DECL-START SBOX-DECL-S-OK = _SCT-ASSERT
    S" bytes" _SCT-WS _SCT-DECL SBOX-DECL-MODULE! SBOX-DECL-S-OK = _SCT-ASSERT
    0 S" main" 0 R> SBOX-PLAN-ENTRY-SIGNATURE@ DROP
        _SCT-DECL SBOX-DECL-ENTRY! SBOX-DECL-S-OK = _SCT-ASSERT
    0 _SCT-BYTES-SCHEMA 12 _SCT-INT-SCHEMA 12 _SCT-WS _SCT-DECL
        SBOX-DECL-SCHEMAS! SBOX-DECL-S-OK = _SCT-ASSERT
    _SCT-KEY 32 66 FILL
    _SCT-KEY _SCT-DECL _SCT-DECL-U @ _SCT-BUILD
        _SCT-INST @ SBOX-CAPABILITY-STORE@ SBOX-STORE-INSTALL
        SBOX-STORE-S-OK = _SCT-ASSERT 0<> _SCT-ASSERT
    _SCT-BUILD SBOX-BUILD-RELEASE SBOX-BUILD-S-OK = _SCT-ASSERT
    _SCT-STACK ;

\ Five more modules, so the list takes two pages.
: _SCT-MORE-MODULES  ( -- )
    _SCT-DEFAULTS _SCT-AS-AGENT
    _SCT-NO-SPECS S" main" _SCT-J-STR _SCT-J-STR _SCT-SPEC+
    [CHAR] p _SCT-PAGE-NAME C!
    5 0 DO
        [CHAR] a I + _SCT-PAGE-NAME 1+ C!
        _SCT-PAGE-NAME 2 1 _SCT-MODULE!
        _SCT-ECHO _SCT-INSTALL CBUS-S-OK = _SCT-ASSERT
        DUP _SCT-DONE-OK CBR-FREE
    LOOP
    _SCT-INST @ SBOX-CAPABILITY-MODULES@ SBOX-MODULE-COUNT@ 9 = _SCT-ASSERT
    _SCT-DEFAULTS
    _SCT-STACK ;

: _SCT-LISTS  ( -- )
    _SCT-DEFAULTS _SCT-AS-AGENT
    0 _SCT-LIST CBUS-S-OK = _SCT-ASSERT _SCT-A !
    _SCT-A @ _SBXC-PAGE DUP _SCT-PAGE=
    _SBXC-PAGE _SCT-LIST CBUS-S-OK = _SCT-ASSERT _SCT-B !
    _SCT-B @ 1 -1 _SCT-PAGE=
    9 _SCT-LIST CBUS-S-OK = _SCT-ASSERT DUP 0 -1 _SCT-PAGE= CBR-FREE
    _SCT-J-INT-OUT _SCT-J-INT-OUT S" installed" S" increment" 1 _SCT-FIND
        _SCT-ITEM=
    _SCT-J-INT-OUT _SCT-J-INT-OUT S" installed" S" increment" 2 _SCT-FIND
        _SCT-ITEM=
    _SCT-J-STR _SCT-J-INT-OUT S" installed" S" echo" 1 _SCT-FIND _SCT-ITEM=
    \ JSON cannot describe the bytes module's entries.
    S" bytes" 1 _SCT-FIND DUP 0<> _SCT-ASSERT
    ?DUP IF S" entries" ROT CV-MAP-FIND _SCT-NULL? _SCT-ASSERT THEN
    _SCT-A @ CBR-FREE _SCT-B @ CBR-FREE
    _SCT-DEFAULTS
    _SCT-STACK ;

: _SCT-AGENT-INVOKES  ( -- )
    _SCT-DEFAULTS _SCT-AS-AGENT
    S" increment" 1 _SCT-MODULE!
    S" 41" _SCT-INPUT!
    _SCT-INVOKE CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE S" 42" 2 PICK _SCT-RESULT= CBR-FREE
    S" increment" 1 _SCT-HELD SBOX-MODULE-PINS@ 0= _SCT-ASSERT
    \ Unknown modules, revisions and entries.
    S" nope" 1 _SCT-MODULE!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" module" S" unknown" 4 PICK _SCT-STEP=
    S" nope" ROT _SCT-DETAIL= CBR-FREE
    S" increment" 9 _SCT-MODULE!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" module" S" unknown" 4 PICK _SCT-STEP=
    DROP CBR-FREE
    S" increment" 1 _SCT-MODULE!
    S" other" _SCT-ENTRY-U ! _SCT-ENTRY-A !
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" entry" S" unknown" 4 PICK _SCT-STEP=
    S" other" ROT _SCT-DETAIL= CBR-FREE
    S" main" _SCT-ENTRY-U ! _SCT-ENTRY-A !
    \ The input is JSON that matches the entry's input schema.
    _SCT-J-X _SCT-PAIR@ _SCT-INPUT!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input" S" schema" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    S" {" _SCT-INPUT!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" input" S" json-invalid" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    \ A result must match the entry's output schema.
    S" echo" 1 _SCT-MODULE!
    _SCT-J-X _SCT-PAIR@ _SCT-INPUT!
    _SCT-INVOKE CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE
    DUP _SCT-ERROR S" output" S" schema" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    \ An entry JSON cannot carry is refused before anything runs.
    S" bytes" 1 _SCT-MODULE!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" entry" S" unsupported" 4 PICK _SCT-STEP=
    S" main" ROT _SCT-DETAIL= CBR-FREE
    _SCT-DEFAULTS
    _SCT-STACK ;

\ The test applet may use a module revision only after the user allows
\ it; a refusal and a cancelled request leave it without a grant.
: _SCT-APPLET-ACCESS  ( -- )
    _SCT-DEFAULTS _SCT-AS-APPLET
    S" increment" 1 _SCT-MODULE!
    S" 41" _SCT-INPUT!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" access" S" not-granted" 4 PICK _SCT-STEP=
    _SCT-NOWHERE CBR-FREE
    \ Asking waits for the user.
    _SCT-INST @ SBOX-CAPABILITY-ASK 0= _SCT-ASSERT
    _SCT-AUTHORIZE CBUS-S-ACCEPTED = _SCT-ASSERT _SCT-A !
    _SCT-INST @ SBOX-CAPABILITY-BUSY? 0= _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-TICK DROP
    _SCT-A @ _SCT-COMPLETE? 0= _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-ASK DUP 0<> _SCT-ASSERT
    DUP SBOX-CAPABILITY-ASK@
    1 = _SCT-ASSERT
    S" increment" COMPARE 0= _SCT-ASSERT
    S" org.test.applet" COMPARE 0= _SCT-ASSERT
    \ The user refuses.
    0 SWAP _SCT-INST @ SBOX-CAPABILITY-ANSWER SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    _SCT-A @ _SCT-COMPLETE? _SCT-ASSERT
    _SCT-A @ _SCT-ERROR S" access" S" denied" 4 PICK _SCT-STEP= DROP
    _SCT-A @ CBR-FREE
    _SCT-INST @ SBOX-CAPABILITY-ASK 0= _SCT-ASSERT
    \ A request cancelled while it waits is no longer asked.
    _SCT-AUTHORIZE CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP CBR-CANCEL
    _SCT-INST @ SBOX-CAPABILITY-ASK 0= _SCT-ASSERT
    DUP _SCT-SETTLE
    DUP CBR.STATUS @ CBUS-S-CANCELLED = _SCT-ASSERT
    CBR-FREE
    \ The user allows it.
    _SCT-AUTHORIZE CBUS-S-ACCEPTED = _SCT-ASSERT _SCT-A !
    -1 _SCT-A @ _SCT-INST @ SBOX-CAPABILITY-ANSWER
        SBOX-CAPABILITY-S-INVALID = _SCT-ASSERT
    -1 _SCT-INST @ SBOX-CAPABILITY-ASK _SCT-INST @ SBOX-CAPABILITY-ANSWER
        SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    _SCT-A @ _SCT-COMPLETE? _SCT-ASSERT
    _SCT-A @ _SCT-DONE-OK _SCT-A @ CBR-FREE
    _SCT-INVOKE CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE S" 42" 2 PICK _SCT-RESULT= CBR-FREE
    \ A component that holds the grant is not asked again.
    _SCT-AUTHORIZE CBUS-S-OK = _SCT-ASSERT DUP _SCT-DONE-OK CBR-FREE
    \ The grant is for that exact revision.
    S" increment" 2 _SCT-MODULE!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" access" S" not-granted" 4 PICK _SCT-STEP=
    DROP CBR-FREE
    \ The Agent reaches modules through its own review, never a grant.
    _SCT-AS-AGENT
    _SCT-AUTHORIZE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" access" S" agent" 4 PICK _SCT-STEP=
    DROP CBR-FREE
    _SCT-DEFAULTS
    _SCT-STACK ;

\ A revoked revision is refused to everyone.
: _SCT-REVOKE  ( -- )
    S" increment" 2 _SCT-HELD DUP 0<> _SCT-ASSERT
    DUP SBOX-MODULE-PINS@ 0= _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-STORE@ SBOX-STORE-REVOKE
        SBOX-STORE-S-OK = _SCT-ASSERT
    _SCT-DEFAULTS _SCT-AS-AGENT
    S" increment" 2 _SCT-MODULE!
    S" 41" _SCT-INPUT!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" module" S" revoked" 4 PICK _SCT-STEP=
    S" increment" ROT _SCT-DETAIL= CBR-FREE
    _SCT-AS-APPLET
    _SCT-AUTHORIZE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" module" S" revoked" 4 PICK _SCT-STEP=
    DROP CBR-FREE
    _SCT-DEFAULTS
    _SCT-STACK ;

: _SCT-OPEN  ( path path-u flags -- fd )
    _SCT-VFS @ VFS-OPEN? 0= _SCT-ASSERT ;

\ Reads the pack into a fresh buffer.
: _SCT-READ-PACK  ( -- )
    _SCT-PACK$ VFS-FF-READ _SCT-OPEN >R
    R@ VFS-SIZE DUP _SCT-FILE-U !
    ALLOCATE 0= _SCT-ASSERT _SCT-FILE !
    _SCT-FILE @ _SCT-FILE-U @ R@ VFS-READ-EXACT 0= _SCT-ASSERT
    R> VFS-CLOSE? DROP ;

\ Where the pack read holds the artifact with DIGEST: the offset of its
\ bytes and their length, or 0 0.
: _SCT-ARTIFACT-AT  ( digest -- offset length )
    64 BEGIN DUP _SCT-FILE-U @ < WHILE
        _SCT-FILE @ OVER + DUP SBOX-BYTE-U32-LE@ 2 =
        OVER 16 + 32 5 PICK 32 COMPARE 0= AND IF
            8 + SBOX-BYTE-U64-LE@ >R 48 + NIP R> EXIT
        THEN
        8 + SBOX-BYTE-U64-LE@ 7 + -8 AND 48 + +
    REPEAT
    2DROP 0 0 ;

\ Flips the low bit of the pack's byte at OFFSET.
: _SCT-FLIP  ( offset -- )
    _SCT-PACK$ VFS-FF-READ VFS-FF-WRITE OR _SCT-OPEN >R
    DUP R@ VFS-SEEK? 0= _SCT-ASSERT
    _SCT-BYTE 1 R@ VFS-READ-EXACT 0= _SCT-ASSERT
    _SCT-BYTE C@ 1 XOR _SCT-BYTE C!
    R@ VFS-SEEK? 0= _SCT-ASSERT
    _SCT-BYTE 1 R@ VFS-WRITE-EXACT 0= _SCT-ASSERT
    R> VFS-CLOSE? DROP ;

\ After a restart the modules and the grant are kept: a module is
\ verified on its first use, a damaged one is quarantined then, and a
\ revoked revision stays refused.
: _SCT-SECOND-BOOT  ( -- )
    S" echo" 1 _SCT-HELD SBOX-MODULE-DECLARATION$ DROP
        SBOX-DECL-ARTIFACT-DIGEST@ _SCT-ART 32 MOVE
    _SCT-INST @ SBOX-CAPABILITY-UNBIND SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    \ The echo artifact is damaged while the host is down.
    _SCT-READ-PACK
    _SCT-ART _SCT-ARTIFACT-AT 70 > _SCT-ASSERT 70 + _SCT-FLIP
    _SCT-FILE @ FREE
    2 _SCT-BIND SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    _SCT-STORAGE SBOX-CAPABILITY-S-OK = _SCT-ASSERT
    _SCT-INST @ SBOX-CAPABILITY-MODULES@ SBOX-MODULE-COUNT@ 9 = _SCT-ASSERT
    S" increment" 1 _SCT-HELD SBOX-MODULE-STATE@
        SBOX-MODULE-DECLARED = _SCT-ASSERT
    _SCT-DEFAULTS _SCT-AS-APPLET
    S" increment" 1 _SCT-MODULE!
    S" 41" _SCT-INPUT!
    _SCT-INVOKE CBUS-S-ACCEPTED = _SCT-ASSERT
    DUP _SCT-SETTLE S" 42" 2 PICK _SCT-RESULT= CBR-FREE
    S" increment" 1 _SCT-HELD SBOX-MODULE-STATE@
        SBOX-MODULE-VERIFIED = _SCT-ASSERT
    _SCT-AS-AGENT
    S" increment" 2 _SCT-MODULE!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" module" S" revoked" 4 PICK _SCT-STEP=
    DROP CBR-FREE
    S" echo" 1 _SCT-MODULE!
    _SCT-J-X _SCT-PAIR@ _SCT-INPUT!
    _SCT-INVOKE CBUS-S-OK = _SCT-ASSERT
    DUP _SCT-ERROR S" module" S" quarantined" 4 PICK _SCT-STEP=
    S" echo" ROT _SCT-DETAIL= CBR-FREE
    0 _SCT-LIST CBUS-S-OK = _SCT-ASSERT _SCT-A !
    _SBXC-PAGE _SCT-LIST CBUS-S-OK = _SCT-ASSERT _SCT-B !
    S" increment" 2 _SCT-FIND DUP 0<> _SCT-ASSERT
    ?DUP IF >R S" revoked" S" state" R> CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT THEN
    S" echo" 1 _SCT-FIND DUP 0<> _SCT-ASSERT
    ?DUP IF
        >R S" quarantined" S" state" R> CV-MAP-FIND _SCT-TEXT= _SCT-ASSERT
    THEN
    _SCT-A @ CBR-FREE _SCT-B @ CBR-FREE
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
    _SCT-MODULES-SETUP
    _SCT-DESCRIPTORS
    _SCT-BIND-REFUSALS
    _SCT-SUCCESS
    _SCT-BUILD-FAILURES
    _SCT-INPUT-FAILURES
    _SCT-RUN-FAILURES
    _SCT-LIFECYCLE
    ." SBOX CAPABILITY MODULES " _SCT-CHECKS @ . CR
    _SCT-NO-STORAGE
    _SCT-INSTALLS
    ." SBOX CAPABILITY INSTALLED " _SCT-CHECKS @ . CR
    _SCT-BYTES-MODULE
    _SCT-MORE-MODULES
    _SCT-LISTS
    ." SBOX CAPABILITY LISTED " _SCT-CHECKS @ . CR
    _SCT-AGENT-INVOKES
    _SCT-APPLET-ACCESS
    ." SBOX CAPABILITY GRANTED " _SCT-CHECKS @ . CR
    _SCT-REVOKE
    _SCT-SECOND-BOOT
    ." SBOX CAPABILITY RESTARTED " _SCT-CHECKS @ . CR
    _SCT-UNBIND
    _SCT-MODULES-TEARDOWN
    _SCT-TEARDOWN
    _SCT-AVAILABLE _SCT-MEMORY @ = _SCT-ASSERT
    _SCT-STACK
    _SCT-FAILS @ 0= IF
        ." SBOX CAPABILITY CONTRACTS PASS " _SCT-CHECKS @ . CR
    ELSE
        ." SBOX CAPABILITY CONTRACTS FAIL " _SCT-FAILS @ . CR
    THEN ;

_SCT-RUN
