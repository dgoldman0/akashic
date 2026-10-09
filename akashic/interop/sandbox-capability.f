\ =====================================================================
\  sandbox-capability.f - The shared sandbox capability
\ =====================================================================
\  Component org.akashic.sandbox gives every caller the request bus
\  admits one way to run restricted sandbox source.  Its capability
\  org.akashic.sandbox/test compiles and verifies a module, runs one of
\  its entries on an input value, and replies with the entry's result or
\  with where the module failed: the step, a stable code and, when source
\  bytes caused it, their line, column, length and text.  A module that
\  fails to build, or an input that cannot be run, is answered at once.
\  A run is accepted and completed later, from the host's tick.
\
\  The input and the result cross as JSON text, so a caller that speaks
\  JSON, the Agent first, can use the capability as it is.  Every field
\  is required; one that does not apply is null.
\
\  The host binds the instance to a parent Context and a complete limit
\  policy, ticks it, drains a closing caller's runs, and unbinds it
\  before freeing it.  Each run belongs to the calling instance the
\  request names, so no caller can see or cancel another's.  The
\  capability only observes: it publishes no owner state.  The host must
\  not unbind or free the instance from a completion callback.
\ =====================================================================

PROVIDED akashic-interop-sbxcap

REQUIRE request-bus.f
REQUIRE capability.f
REQUIRE codecs/sandbox-value.f
REQUIRE codecs/json-value.f
REQUIRE ../runtime/sandbox-build.f
REQUIRE ../runtime/sandbox-job-service.f

\ =====================================================================
\  Status
\ =====================================================================

0 CONSTANT SBOX-CAPABILITY-S-OK
1 CONSTANT SBOX-CAPABILITY-S-INVALID
2 CONSTANT SBOX-CAPABILITY-S-STATE
3 CONSTANT SBOX-CAPABILITY-S-SERVICE
4 CONSTANT SBOX-CAPABILITY-S-NOMEM

\ =====================================================================
\  Codes
\ =====================================================================
\ A reply's code is the lowercase suffix of the constant it names.

: _SBXC-COMPILE-CODE$  ( code -- address length )
    CASE
        SBOX-COMPILER-E-BYTE OF S" byte" ENDOF
        SBOX-COMPILER-E-BACKSLASH OF S" backslash" ENDOF
        SBOX-COMPILER-E-TOKEN-LENGTH OF S" token-length" ENDOF
        SBOX-COMPILER-E-END OF S" end" ENDOF
        SBOX-COMPILER-E-EXPECTED-FUNCTION OF S" expected-function" ENDOF
        SBOX-COMPILER-E-EXPECTED-ENTRY OF S" expected-entry" ENDOF
        SBOX-COMPILER-E-EXPECTED-PARAMS OF S" expected-params" ENDOF
        SBOX-COMPILER-E-EXPECTED-RESULTS OF S" expected-results" ENDOF
        SBOX-COMPILER-E-EXPECTED-LOCALS OF S" expected-locals" ENDOF
        SBOX-COMPILER-E-NAME OF S" name" ENDOF
        SBOX-COMPILER-E-DUPLICATE OF S" duplicate" ENDOF
        SBOX-COMPILER-E-NUMBER OF S" number" ENDOF
        SBOX-COMPILER-E-UNKNOWN OF S" unknown" ENDOF
        SBOX-COMPILER-E-UNMATCHED OF S" unmatched" ENDOF
        SBOX-COMPILER-E-UNREACHABLE OF S" unreachable" ENDOF
        SBOX-COMPILER-E-OPEN-CONTROL OF S" open-control" ENDOF
        SBOX-COMPILER-E-FALLTHROUGH OF S" fallthrough" ENDOF
        SBOX-COMPILER-E-RETURN-IN-LOOP OF S" return-in-loop" ENDOF
        SBOX-COMPILER-E-LOOP-INDEX OF S" loop-index" ENDOF
        SBOX-COMPILER-E-LOCAL-INDEX OF S" local-index" ENDOF
        SBOX-COMPILER-E-UNDEFINED-CALL OF S" undefined-call" ENDOF
        SBOX-COMPILER-E-ENTRY-ORDER OF S" entry-order" ENDOF
        SBOX-COMPILER-E-ENTRY-FUNCTION OF S" entry-function" ENDOF
        SBOX-COMPILER-E-SIGNATURE OF S" signature" ENDOF
        SBOX-COMPILER-E-SIGNATURE-MIX OF S" signature-mix" ENDOF
        SBOX-COMPILER-E-SCALAR-TYPED OF S" scalar-typed" ENDOF
        SBOX-COMPILER-E-LIMIT OF S" limit" ENDOF
        SBOX-COMPILER-E-DISABLED OF S" disabled" ENDOF
        SBOX-COMPILER-E-PROFILE OF S" profile" ENDOF
        >R S" internal" R>
    ENDCASE ;

: _SBXC-VERIFY-CODE$  ( detail -- address length )
    CASE
        SBOX-VERIFIER-D-CANDIDATE-SPAN OF S" candidate-span" ENDOF
        SBOX-VERIFIER-D-PROFILE-SPAN OF S" profile-span" ENDOF
        SBOX-VERIFIER-D-PLAN-SPAN OF S" plan-span" ENDOF
        SBOX-VERIFIER-D-WORKSPACE-SPAN OF S" workspace-span" ENDOF
        SBOX-VERIFIER-D-OVERLAP OF S" overlap" ENDOF
        SBOX-VERIFIER-D-CANDIDATE-GEOMETRY OF S" candidate-geometry" ENDOF
        SBOX-VERIFIER-D-PROFILE-SEALED OF S" profile-sealed" ENDOF
        SBOX-VERIFIER-D-PROFILE-TAG OF S" profile-tag" ENDOF
        SBOX-VERIFIER-D-MEMORY OF S" memory" ENDOF
        SBOX-VERIFIER-D-COUNTS OF S" counts" ENDOF
        SBOX-VERIFIER-D-PADDING OF S" padding" ENDOF
        SBOX-VERIFIER-D-FUNCTION-CODE OF S" function-code" ENDOF
        SBOX-VERIFIER-D-FUNCTION-SIGNATURE OF S" function-signature" ENDOF
        SBOX-VERIFIER-D-FUNCTION-LOCALS OF S" function-locals" ENDOF
        SBOX-VERIFIER-D-FUNCTION-FLAGS OF S" function-flags" ENDOF
        SBOX-VERIFIER-D-IMPORT-ID OF S" import-id" ENDOF
        SBOX-VERIFIER-D-IMPORT-ORDER OF S" import-order" ENDOF
        SBOX-VERIFIER-D-IMPORT-SIGNATURE OF S" import-signature" ENDOF
        SBOX-VERIFIER-D-IMPORT-COST OF S" import-cost" ENDOF
        SBOX-VERIFIER-D-IMPORT-FLAGS OF S" import-flags" ENDOF
        SBOX-VERIFIER-D-ENTRY-GEOMETRY OF S" entry-geometry" ENDOF
        SBOX-VERIFIER-D-ENTRY-NAME OF S" entry-name" ENDOF
        SBOX-VERIFIER-D-ENTRY-ORDER OF S" entry-order" ENDOF
        SBOX-VERIFIER-D-ENTRY-FUNCTION OF S" entry-function" ENDOF
        SBOX-VERIFIER-D-ENTRY-FLAGS OF S" entry-flags" ENDOF
        SBOX-VERIFIER-D-ENTRY-SIGNATURE OF S" entry-signature" ENDOF
        SBOX-VERIFIER-D-INSTRUCTION-FLAGS OF S" instruction-flags" ENDOF
        SBOX-VERIFIER-D-INSTRUCTION-OPCODE OF S" instruction-opcode" ENDOF
        SBOX-VERIFIER-D-INSTRUCTION-OPERANDS
            OF S" instruction-operands" ENDOF
        SBOX-VERIFIER-D-INSTRUCTION-TARGET OF S" instruction-target" ENDOF
        SBOX-VERIFIER-D-LOOP-NESTING OF S" loop-nesting" ENDOF
        SBOX-VERIFIER-D-LOOP-RECIPROCAL OF S" loop-reciprocal" ENDOF
        SBOX-VERIFIER-D-LOOP-SCOPE OF S" loop-scope" ENDOF
        SBOX-VERIFIER-D-LOOP-INDEX OF S" loop-index" ENDOF
        SBOX-VERIFIER-D-LOOP-RETURN OF S" loop-return" ENDOF
        SBOX-VERIFIER-D-STACK-UNDERFLOW OF S" stack-underflow" ENDOF
        SBOX-VERIFIER-D-STACK-OVERFLOW OF S" stack-overflow" ENDOF
        SBOX-VERIFIER-D-STACK-MERGE OF S" stack-merge" ENDOF
        SBOX-VERIFIER-D-STACK-RETURN OF S" stack-return" ENDOF
        SBOX-VERIFIER-D-UNREACHABLE OF S" unreachable" ENDOF
        SBOX-VERIFIER-D-PLAN-PUBLISH OF S" plan-publish" ENDOF
        >R S" internal" R>
    ENDCASE ;

: _SBXC-TRAP-CODE$  ( detail -- address length )
    CASE
        SBOX-VM-TRAP-BAD-OPCODE OF S" bad-opcode" ENDOF
        SBOX-VM-TRAP-BAD-INSTRUCTION-POINTER
            OF S" bad-instruction-pointer" ENDOF
        SBOX-VM-TRAP-BAD-BRANCH-TARGET OF S" bad-branch-target" ENDOF
        SBOX-VM-TRAP-BAD-CALL-TARGET OF S" bad-call-target" ENDOF
        SBOX-VM-TRAP-DATA-STACK-UNDERFLOW OF S" data-stack-underflow" ENDOF
        SBOX-VM-TRAP-CALL-STACK-UNDERFLOW OF S" call-stack-underflow" ENDOF
        SBOX-VM-TRAP-BAD-EXIT-SHAPE OF S" bad-exit-shape" ENDOF
        SBOX-VM-TRAP-DIVIDE-BY-ZERO OF S" divide-by-zero" ENDOF
        SBOX-VM-TRAP-DIVIDE-OVERFLOW OF S" divide-overflow" ENDOF
        SBOX-VM-TRAP-SHIFT-RANGE OF S" shift-range" ENDOF
        SBOX-VM-TRAP-MEMORY-OUT-OF-BOUNDS OF S" memory-out-of-bounds" ENDOF
        SBOX-VM-TRAP-MEMORY-MISALIGNED OF S" memory-misaligned" ENDOF
        SBOX-VM-TRAP-MEMORY-READ-ONLY OF S" memory-read-only" ENDOF
        SBOX-VM-TRAP-INVALID-VALUE-HANDLE OF S" invalid-value-handle" ENDOF
        SBOX-VM-TRAP-VALUE-TYPE-MISMATCH OF S" value-type-mismatch" ENDOF
        SBOX-VM-TRAP-VALUE-INDEX-RANGE OF S" value-index-range" ENDOF
        SBOX-VM-TRAP-INVALID-UTF8 OF S" invalid-utf8" ENDOF
        SBOX-VM-TRAP-DUPLICATE-MAP-KEY OF S" duplicate-map-key" ENDOF
        SBOX-VM-TRAP-INVALID-RESULT-GRAPH OF S" invalid-result-graph" ENDOF
        SBOX-VM-TRAP-EXPLICIT-ABORT OF S" explicit-abort" ENDOF
        SBOX-VM-TRAP-LOCAL-INDEX-RANGE OF S" local-index-range" ENDOF
        SBOX-VM-TRAP-INVALID-LENGTH OF S" invalid-length" ENDOF
        SBOX-VM-TRAP-LOOP-STACK-UNDERFLOW OF S" loop-stack-underflow" ENDOF
        SBOX-VM-TRAP-LOOP-ZERO-STEP OF S" loop-zero-step" ENDOF
        SBOX-VM-TRAP-LOOP-ARITHMETIC-OVERFLOW
            OF S" loop-arithmetic-overflow" ENDOF
        SBOX-VM-TRAP-LOOP-STATE-INVALID OF S" loop-state-invalid" ENDOF
        SBOX-VM-TRAP-MAP-KEY-ORDER OF S" map-key-order" ENDOF
        >R S" internal" R>
    ENDCASE ;

: _SBXC-EXHAUST-CODE$  ( detail -- address length )
    CASE
        SBOX-VM-EXHAUST-INSTRUCTION-UNITS OF S" instruction-units" ENDOF
        SBOX-VM-EXHAUST-VALUE-OPS OF S" value-ops" ENDOF
        SBOX-VM-EXHAUST-COPY-BYTES OF S" copy-bytes" ENDOF
        SBOX-VM-EXHAUST-DATA-STACK OF S" data-stack" ENDOF
        SBOX-VM-EXHAUST-CALL-FRAMES OF S" call-frames" ENDOF
        SBOX-VM-EXHAUST-LOOP-FRAMES OF S" loop-frames" ENDOF
        SBOX-VM-EXHAUST-OUTPUT-ARENA-NODES OF S" output-arena-nodes" ENDOF
        SBOX-VM-EXHAUST-OUTPUT-ARENA-BYTES OF S" output-arena-bytes" ENDOF
        SBOX-VM-EXHAUST-OUTPUT-RESULT-NODES
            OF S" output-result-nodes" ENDOF
        SBOX-VM-EXHAUST-OUTPUT-RESULT-BYTES
            OF S" output-result-bytes" ENDOF
        >R S" internal" R>
    ENDCASE ;

: _SBXC-CANCEL-CODE$  ( detail -- address length )
    CASE
        SBOX-VM-CANCEL-CALLER OF S" caller" ENDOF
        SBOX-VM-CANCEL-CONTEXT OF S" context" ENDOF
        SBOX-VM-CANCEL-DEADLINE OF S" deadline" ENDOF
        SBOX-VM-CANCEL-HOST-SHUTDOWN OF S" host-shutdown" ENDOF
        SBOX-VM-CANCEL-ADAPTER OF S" adapter" ENDOF
        >R S" internal" R>
    ENDCASE ;

: _SBXC-INPUT-CODE$  ( sbcv-status -- address length )
    CASE
        SBCV-S-TYPE OF S" type" ENDOF
        SBCV-S-UTF8 OF S" utf8" ENDOF
        SBCV-S-KEY OF S" key" ENDOF
        SBCV-S-LIMIT OF S" limit" ENDOF
        >R S" invalid" R>
    ENDCASE ;

: _SBXC-JSON-CODE$  ( ivjson-ior -- address length )
    CASE
        IVJSON-E-INVALID OF S" json-invalid" ENDOF
        IVJSON-E-TYPE OF S" json-type" ENDOF
        IVJSON-E-RANGE OF S" json-range" ENDOF
        IVJSON-E-DEPTH OF S" json-depth" ENDOF
        IVJSON-E-CAPACITY OF S" json-capacity" ENDOF
        IVJSON-E-NOMEM OF S" json-nomem" ENDOF
        IVJSON-E-UNSUPPORTED OF S" json-unsupported" ENDOF
        >R S" json-invalid" R>
    ENDCASE ;

\ =====================================================================
\  Descriptors and schemas
\ =====================================================================
\ One immutable table holds the component and capability descriptors,
\ the schema nodes and their map fields.

0 CONSTANT _SBXT-COMPONENT
_SBXT-COMPONENT COMP-DESC + CONSTANT _SBXT-TEST
_SBXT-TEST CAP-DESC + CONSTANT _SBXT-SCHEMAS

 0 CONSTANT _SBXS-IN
 1 CONSTANT _SBXS-SOURCE
 2 CONSTANT _SBXS-ENTRY
 3 CONSTANT _SBXS-JSON
 4 CONSTANT _SBXS-MEMORY
 5 CONSTANT _SBXS-OUT
 6 CONSTANT _SBXS-BOOL
 7 CONSTANT _SBXS-RESULT
 8 CONSTANT _SBXS-ERROR
 9 CONSTANT _SBXS-TEXT
10 CONSTANT _SBXS-MAYBE-TEXT
11 CONSTANT _SBXS-POSITION
12 CONSTANT _SBXS-COUNT
13 CONSTANT _SBXS-N

\ Four request fields, three reply fields and seven error fields.
_SBXT-SCHEMAS _SBXS-N CS-SIZE * + CONSTANT _SBXT-FIELDS
 0 CONSTANT _SBXF-IN
 4 CONSTANT _SBXF-OUT
 7 CONSTANT _SBXF-ERROR
14 CONSTANT _SBXF-N
_SBXT-FIELDS _SBXF-N CS-FIELD-SIZE * + CONSTANT _SBXT-SIZE

CREATE _SBXC-TABLES _SBXT-SIZE ALLOT

: SBOX-CAPABILITY-COMPONENT  ( -- desc ) _SBXC-TABLES _SBXT-COMPONENT + ;
: _SBXC-TEST-CAP  ( -- cap ) _SBXC-TABLES _SBXT-TEST + ;

: _SBXC-SCHEMA  ( index -- schema )
    CS-SIZE * _SBXT-SCHEMAS + _SBXC-TABLES + ;

: _SBXC-FIELD  ( index -- field )
    CS-FIELD-SIZE * _SBXT-FIELDS + _SBXC-TABLES + ;

\ =====================================================================
\  Component state and runs
\ =====================================================================

0x5342584341504142 CONSTANT _SBXC-MAGIC  \ "SBXCAPAB"

  0 CONSTANT _SBXC-MAGIC-OFF
  8 CONSTANT _SBXC-INSTANCE
 16 CONSTANT _SBXC-SERVICE
 24 CONSTANT _SBXC-SERVICE-U
 32 CONSTANT _SBXC-CAPACITY
 40 CONSTANT _SBXC-RUNS
 48 CONSTANT _SBXC-PARENT
 56 CONSTANT _SBXC-POLICY
 64 CONSTANT _SBXC-SLICE
 72 CONSTANT _SBXC-ALLOWANCE
 80 CONSTANT _SBXC-PROFILE
_SBXC-PROFILE SBOX-PROFILE-SIZE + CONSTANT _SBXC-LIMITS
_SBXC-LIMITS SBOX-VALUE-LIMITS-SIZE + CONSTANT _SBXC-STATE-SIZE

: _SBXC.MAGIC      ( state -- a ) _SBXC-MAGIC-OFF + ;
: _SBXC.INSTANCE   ( state -- a ) _SBXC-INSTANCE + ;
: _SBXC.SERVICE    ( state -- a ) _SBXC-SERVICE + ;
: _SBXC.SERVICE-U  ( state -- a ) _SBXC-SERVICE-U + ;
: _SBXC.CAPACITY   ( state -- a ) _SBXC-CAPACITY + ;
: _SBXC.RUNS       ( state -- a ) _SBXC-RUNS + ;
: _SBXC.PARENT     ( state -- a ) _SBXC-PARENT + ;
: _SBXC.POLICY     ( state -- a ) _SBXC-POLICY + ;
: _SBXC.SLICE      ( state -- a ) _SBXC-SLICE + ;
: _SBXC.ALLOWANCE  ( state -- a ) _SBXC-ALLOWANCE + ;
\ The pure-computation profile and the policy's value limits, inline.
: _SBXC.PROFILE    ( state -- profile ) _SBXC-PROFILE + ;
: _SBXC.LIMITS     ( state -- value-limits ) _SBXC-LIMITS + ;

0 CONSTANT _SBXC-FREE
1 CONSTANT _SBXC-RUNNING

\ One run: its request, its job and owner token, the failure a reply
\ names, the buffer and value it holds, and the build that owns its plan.
  0 CONSTANT _SBXR-PHASE
  8 CONSTANT _SBXR-STATE
 16 CONSTANT _SBXR-REQUEST
 24 CONSTANT _SBXR-ACTIVATION
 32 CONSTANT _SBXR-GENERATION
 40 CONSTANT _SBXR-OWNER-ID
 48 CONSTANT _SBXR-OWNER-GEN
 56 CONSTANT _SBXR-STEP-A
 64 CONSTANT _SBXR-STEP-U
 72 CONSTANT _SBXR-CODE-A
 80 CONSTANT _SBXR-CODE-U
 88 CONSTANT _SBXR-OFFSET
 96 CONSTANT _SBXR-LENGTH
104 CONSTANT _SBXR-ABORT
112 CONSTANT _SBXR-BUFFER
120 CONSTANT _SBXR-BUFFER-U
128 CONSTANT _SBXR-VALUE
_SBXR-VALUE CV-SIZE + CONSTANT _SBXR-BUILD
_SBXR-BUILD SBOX-BUILD-SIZE + CONSTANT _SBXR-SIZE

: _SBXR.PHASE       ( run -- a ) _SBXR-PHASE + ;
: _SBXR.STATE       ( run -- a ) _SBXR-STATE + ;
: _SBXR.REQUEST     ( run -- a ) _SBXR-REQUEST + ;
: _SBXR.ACTIVATION  ( run -- a ) _SBXR-ACTIVATION + ;
: _SBXR.GENERATION  ( run -- a ) _SBXR-GENERATION + ;
: _SBXR.OWNER-ID    ( run -- a ) _SBXR-OWNER-ID + ;
: _SBXR.OWNER-GEN   ( run -- a ) _SBXR-OWNER-GEN + ;
: _SBXR.STEP-A      ( run -- a ) _SBXR-STEP-A + ;
: _SBXR.STEP-U      ( run -- a ) _SBXR-STEP-U + ;
: _SBXR.CODE-A      ( run -- a ) _SBXR-CODE-A + ;
: _SBXR.CODE-U      ( run -- a ) _SBXR-CODE-U + ;
: _SBXR.OFFSET      ( run -- a ) _SBXR-OFFSET + ;
: _SBXR.LENGTH      ( run -- a ) _SBXR-LENGTH + ;
: _SBXR.ABORT       ( run -- a ) _SBXR-ABORT + ;
: _SBXR.BUFFER      ( run -- a ) _SBXR-BUFFER + ;
: _SBXR.BUFFER-U    ( run -- a ) _SBXR-BUFFER-U + ;
: _SBXR.VALUE       ( run -- value ) _SBXR-VALUE + ;
: _SBXR.BUILD       ( run -- build ) _SBXR-BUILD + ;

: _SBXC-BOUND?  ( state -- flag )
    DUP 0= IF EXIT THEN
    _SBXC.MAGIC @ _SBXC-MAGIC = ;

: _SBXC-RUN  ( index state -- run )
    _SBXC.RUNS @ SWAP _SBXR-SIZE * + ;

\ A free run, claimed for REQUEST.
: _SBXC-CLAIM  ( request state -- run|0 )
    DUP _SBXC.CAPACITY @ 0 ?DO
        I OVER _SBXC-RUN DUP _SBXR.PHASE @ _SBXC-FREE = IF
            NIP
            _SBXC-RUNNING OVER _SBXR.PHASE !
            TUCK _SBXR.REQUEST !
            UNLOOP EXIT
        THEN
        DROP
    LOOP
    2DROP 0 ;

: _SBXC-JOB  ( run -- activation generation owner-id owner-gen service )
    >R R@ _SBXR.ACTIVATION @ R@ _SBXR.GENERATION @
    R@ _SBXR.OWNER-ID @ R@ _SBXR.OWNER-GEN @
    R> _SBXR.STATE @ _SBXC.SERVICE @ ;

: _SBXC-DROP-BUFFER  ( run -- )
    DUP _SBXR.BUFFER @ ?DUP IF
        DUP 2 PICK _SBXR.BUFFER-U @ 0 FILL FREE
    THEN
    0 OVER _SBXR.BUFFER !
    0 SWAP _SBXR.BUFFER-U ! ;

\ Ends a run's own work, its job, buffer, value and plan, and frees the
\ run.  It keeps its home state and its empty build record.
: _SBXC-RUN-END  ( run -- )
    DUP _SBXR.ACTIVATION @ IF
        DUP _SBXC-JOB SBOX-JOB-DISCARD DROP
    THEN
    DUP _SBXC-DROP-BUFFER
    DUP _SBXR.VALUE CV-NULL!
    DUP _SBXR.BUILD SBOX-BUILD-RELEASE DROP
    _SBXC-FREE OVER _SBXR.PHASE !
    _SBXR.REQUEST _SBXR-BUILD _SBXR-REQUEST - 0 FILL ;

: _SBXC-FAIL!  ( step-a step-u code-a code-u run -- )
    >R
    R@ _SBXR.CODE-U ! R@ _SBXR.CODE-A !
    R@ _SBXR.STEP-U ! R@ _SBXR.STEP-A !
    -1 R@ _SBXR.OFFSET !
    0 R@ _SBXR.LENGTH !
    -1 R> _SBXR.ABORT ! ;

\ =====================================================================
\  Replies
\ =====================================================================

: _SBXC-ARG  ( key-a key-u request -- value|0 )
    CBR.ARGS CV-MAP-FIND ;

: _SBXC-STRING  ( value -- address length )
    DUP CV-DATA@ SWAP CV-LEN@ ;

: _SBXC-SOURCE  ( run -- address )
    S" source" ROT _SBXR.REQUEST @ _SBXC-ARG CV-DATA@ ;

: _SBXC-PUT-TEXT  ( text-a text-u key-a key-u index map -- ior )
    CV-MAP-SLOT! ?DUP IF NIP NIP NIP EXIT THEN
    CV-STRING! ;

: _SBXC-PUT-INT  ( n key-a key-u index map -- ior )
    CV-MAP-SLOT! ?DUP IF NIP NIP EXIT THEN
    CV-INT! 0 ;

: _SBXC-PUT-BOOL  ( flag key-a key-u index map -- ior )
    CV-MAP-SLOT! ?DUP IF NIP NIP EXIT THEN
    CV-BOOL! 0 ;

\ A fresh map entry is null until something is stored in it.
: _SBXC-PUT-NULL  ( key-a key-u index map -- ior )
    CV-MAP-SLOT! ?DUP IF NIP EXIT THEN
    DROP 0 ;

\ N, or null when N is negative.
: _SBXC-PUT-MAYBE  ( n key-a key-u index map -- ior )
    4 PICK 0< IF _SBXC-PUT-NULL NIP EXIT THEN
    _SBXC-PUT-INT ;

\ Line and column, both from 1, of byte OFFSET in SOURCE.  A column
\ counts bytes.
: _SBXC-LINE-COLUMN  ( source offset -- line column )
    1 1 ROT 0 ?DO
        2 PICK I + C@ 10 = IF DROP 1+ 1 ELSE 1+ THEN
    LOOP
    ROT DROP ;

\ Line, column, length and text, at indices 3 to 6.
: _SBXC-POSITION  ( map run -- ior )
    >R
    R@ _SBXC-SOURCE R@ _SBXR.OFFSET @ _SBXC-LINE-COLUMN
    SWAP S" line" 3 5 PICK _SBXC-PUT-INT
        ?DUP IF NIP NIP R> DROP EXIT THEN
    S" column" 4 4 PICK _SBXC-PUT-INT
        ?DUP IF NIP R> DROP EXIT THEN
    R@ _SBXR.LENGTH @ S" length" 5 4 PICK _SBXC-PUT-INT
        ?DUP IF NIP R> DROP EXIT THEN
    R@ _SBXC-SOURCE R@ _SBXR.OFFSET @ + R@ _SBXR.LENGTH @
        S" text" 6 5 PICK _SBXC-PUT-TEXT
    NIP R> DROP ;

\ Step and code, the abort code of an explicit abort, and the source
\ position when source bytes caused the failure; the rest is null.
: _SBXC-ERROR-MAP  ( map run -- ior )
    >R
    7 OVER CV-MAP! ?DUP IF NIP R> DROP EXIT THEN
    R@ _SBXR.STEP-A @ R@ _SBXR.STEP-U @ S" step" 0 5 PICK _SBXC-PUT-TEXT
        ?DUP IF NIP R> DROP EXIT THEN
    R@ _SBXR.CODE-A @ R@ _SBXR.CODE-U @ S" code" 1 5 PICK _SBXC-PUT-TEXT
        ?DUP IF NIP R> DROP EXIT THEN
    R@ _SBXR.ABORT @ S" abort" 2 4 PICK _SBXC-PUT-MAYBE
        ?DUP IF NIP R> DROP EXIT THEN
    R@ _SBXR.OFFSET @ 0< IF
        S" line" 3 3 PICK _SBXC-PUT-NULL ?DUP IF NIP R> DROP EXIT THEN
        S" column" 4 3 PICK _SBXC-PUT-NULL ?DUP IF NIP R> DROP EXIT THEN
        S" length" 5 3 PICK _SBXC-PUT-NULL ?DUP IF NIP R> DROP EXIT THEN
        S" text" 6 3 PICK _SBXC-PUT-NULL NIP R> DROP EXIT
    THEN
    R> _SBXC-POSITION ;

: _SBXC-TOP  ( run -- map ) _SBXR.REQUEST @ CBR.RESULT ;

\ Writes {ok: false, result: null, error: {...}} as the request's result.
: _SBXC-REPLY-FAILURE  ( run -- ior )
    >R
    3 R@ _SBXC-TOP CV-MAP! ?DUP IF R> DROP EXIT THEN
    0 S" ok" 0 R@ _SBXC-TOP _SBXC-PUT-BOOL ?DUP IF R> DROP EXIT THEN
    S" result" 1 R@ _SBXC-TOP _SBXC-PUT-NULL ?DUP IF R> DROP EXIT THEN
    S" error" 2 R@ _SBXC-TOP CV-MAP-SLOT! ?DUP IF NIP R> DROP EXIT THEN
    R> _SBXC-ERROR-MAP ;

\ Writes {ok: true, result: json, error: null}.
: _SBXC-REPLY-JSON  ( json-a json-u run -- ior )
    >R
    3 R@ _SBXC-TOP CV-MAP! ?DUP IF NIP NIP R> DROP EXIT THEN
    -1 S" ok" 0 R@ _SBXC-TOP _SBXC-PUT-BOOL
        ?DUP IF NIP NIP R> DROP EXIT THEN
    S" result" 1 R@ _SBXC-TOP _SBXC-PUT-TEXT ?DUP IF R> DROP EXIT THEN
    S" error" 2 R> _SBXC-TOP _SBXC-PUT-NULL ;

: _SBXC-REFUSE  ( text-a text-u status request -- status )
    OVER >R CBR-ERROR! R> ;

\ Ends a run and refuses its request.
: _SBXC-END-REFUSE  ( text-a text-u status run -- status )
    DUP _SBXR.REQUEST @ >R _SBXC-RUN-END R> _SBXC-REFUSE ;

\ Replies now with the run's failure and ends the run.
: _SBXC-ANSWER  ( run -- status )
    DUP _SBXR.REQUEST @ >R
    DUP _SBXC-REPLY-FAILURE SWAP _SBXC-RUN-END
    IF
        S" The sandbox could not write its reply" CBUS-S-FAILED
        R> _SBXC-REFUSE EXIT
    THEN
    R> DROP CBUS-S-OK ;

\ =====================================================================
\  Starting a run
\ =====================================================================

\ Guest memory the request asks for, rounded up to whole cells.
: _SBXC-MEMORY  ( run -- memory-u )
    S" memory" ROT _SBXR.REQUEST @ _SBXC-ARG
    ?DUP IF CV-DATA@ 7 + -8 AND ELSE 0 THEN ;

: _SBXC-BUILD  ( run -- build-status )
    >R
    S" source" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    R@ _SBXR.STATE @ _SBXC.PROFILE
    R@ _SBXC-MEMORY
    R> _SBXR.BUILD SBOX-BUILD ;

: _SBXC-BUILD-FAILED  ( run -- )
    >R
    R@ _SBXR.BUILD SBOX-BUILD-ERROR@ DROP
    R@ _SBXR.LENGTH ! R@ _SBXR.OFFSET !
    SWAP SBOX-BUILD-S-COMPILE = IF
        _SBXC-COMPILE-CODE$ S" compile"
    ELSE
        _SBXC-VERIFY-CODE$ S" verify"
    THEN
    R@ _SBXR.STEP-U ! R@ _SBXR.STEP-A !
    R@ _SBXR.CODE-U ! R@ _SBXR.CODE-A !
    -1 R> _SBXR.ABORT ! ;

\ The request's input, decoded from its JSON text.
: _SBXC-DECODE-INPUT  ( run -- ivjson-ior )
    >R S" input" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    R> _SBXR.VALUE IVJSON-DECODE ;

\ The decoded input in canonical form, in a fresh buffer.
: _SBXC-ENCODE  ( run -- sbcv-status )
    >R
    R@ _SBXR.VALUE R@ _SBXR.STATE @ _SBXC.LIMITS SBCV-MEASURE
        ?DUP IF NIP R> DROP EXIT THEN
    DUP ALLOCATE IF 2DROP R> DROP SBCV-S-NOMEM EXIT THEN
    R@ _SBXR.BUFFER ! R@ _SBXR.BUFFER-U !
    R@ _SBXR.VALUE R@ _SBXR.STATE @ _SBXC.LIMITS
    R@ _SBXR.BUFFER @ R@ _SBXR.BUFFER-U @ SBCV-ENCODE
    NIP R> DROP ;

: _SBXC-SUBMIT  ( run -- job-status )
    >R
    R@ _SBXR.BUILD SBOX-BUILD-PLAN@ DROP
    S" entry" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    R@ _SBXR.BUFFER @ R@ _SBXR.BUFFER-U @
    0
    R@ _SBXR.OWNER-ID @ R@ _SBXR.OWNER-GEN @
    R@ _SBXR.STATE @ _SBXC.SERVICE @
    SBOX-JOB-SUBMIT
    -ROT R@ _SBXR.GENERATION ! R@ _SBXR.ACTIVATION !
    R> DROP ;

: _SBXC-SUBMIT-FAILED  ( run job-status -- status )
    DUP SBOX-JOB-S-ENTRY = IF
        DROP >R S" entry" S" entry" R@ _SBXC-FAIL! R> _SBXC-ANSWER EXIT
    THEN
    DUP SBOX-JOB-S-INPUT = IF
        DROP >R S" input" S" limit" R@ _SBXC-FAIL! R> _SBXC-ANSWER EXIT
    THEN
    DUP SBOX-JOB-S-FULL = SWAP SBOX-JOB-S-CAPACITY = OR IF
        >R S" Every sandbox run is in use" CBUS-S-BUSY R> _SBXC-END-REFUSE
        EXIT
    THEN
    >R S" The sandbox could not start the run" CBUS-S-FAILED
    R> _SBXC-END-REFUSE ;

\ Builds the module, encodes the input and submits the run.
: _SBXC-START  ( run -- status )
    DUP _SBXC-BUILD
    DUP SBOX-BUILD-S-COMPILE = OVER SBOX-BUILD-S-VERIFY = OR IF
        DROP DUP _SBXC-BUILD-FAILED _SBXC-ANSWER EXIT
    THEN
    IF
        >R S" The sandbox could not build the module" CBUS-S-FAILED
        R> _SBXC-END-REFUSE EXIT
    THEN
    DUP _SBXC-DECODE-INPUT ?DUP IF
        DUP IVJSON-E-NOMEM = IF
            DROP >R S" The sandbox ran out of memory" CBUS-S-FAILED
            R> _SBXC-END-REFUSE EXIT
        THEN
        _SBXC-JSON-CODE$ >R >R S" input" R> R>
        4 PICK _SBXC-FAIL! _SBXC-ANSWER EXIT
    THEN
    DUP _SBXC-ENCODE ?DUP IF
        DUP SBCV-S-NOMEM = IF
            DROP >R S" The sandbox ran out of memory" CBUS-S-FAILED
            R> _SBXC-END-REFUSE EXIT
        THEN
        _SBXC-INPUT-CODE$ >R >R S" input" R> R>
        4 PICK _SBXC-FAIL! _SBXC-ANSWER EXIT
    THEN
    DUP _SBXC-SUBMIT
    OVER _SBXC-DROP-BUFFER
    ?DUP IF _SBXC-SUBMIT-FAILED EXIT THEN
    DROP CBUS-S-ACCEPTED ;

: _SBXC-CALLER?  ( request -- flag )
    DUP CBR.CALLER-ID @ 0> SWAP CBR.CALLER-GEN @ 0> AND ;

\ The org.akashic.sandbox/test handler.
: _SBXC-TEST  ( request instance -- status )
    CINST-STATE
    DUP _SBXC-BOUND? 0= IF
        DROP >R S" The sandbox is not running" CBUS-S-FAILED
        R> _SBXC-REFUSE EXIT
    THEN
    OVER _SBXC-CALLER? 0= IF
        DROP >R S" A sandbox run needs a calling instance" CBUS-S-DENIED
        R> _SBXC-REFUSE EXIT
    THEN
    OVER SWAP _SBXC-CLAIM
    ?DUP 0= IF
        >R S" Every sandbox run is in use" CBUS-S-BUSY R> _SBXC-REFUSE EXIT
    THEN
    NIP
    DUP _SBXR.REQUEST @ CBR.CALLER-ID @ OVER _SBXR.OWNER-ID !
    DUP _SBXR.REQUEST @ CBR.CALLER-GEN @ OVER _SBXR.OWNER-GEN !
    _SBXC-START ;

\ =====================================================================
\  Completing runs
\ =====================================================================

\ Ends a deferred run and completes its request with STATUS.  The run is
\ free before the requester's callback runs.
: _SBXC-COMPLETE  ( status run -- )
    DUP _SBXR.REQUEST @ >R
    DUP _SBXR.STATE @ _SBXC.INSTANCE @ >R
    _SBXC-RUN-END
    R> R> SWAP CBUS-COMPLETE-DEFERRED DROP ;

: _SBXC-COMPLETE-FAILED  ( text-a text-u run -- )
    >R CBUS-S-FAILED R@ _SBXR.REQUEST @ CBR-ERROR!
    CBUS-S-FAILED R> _SBXC-COMPLETE ;

: _SBXC-REPLY-STATUS  ( run -- status )
    _SBXC-REPLY-FAILURE IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

\ Replies with the run's decoded value as JSON text, or, when JSON
\ cannot carry it, with why.
: _SBXC-REPLY-RESULT  ( run -- status )
    CV-MAX-STRING-LEN ALLOCATE IF 2DROP CBUS-S-FAILED EXIT THEN
    2DUP SWAP _SBXR.VALUE SWAP CV-MAX-STRING-LEN IVJSON-ENCODE
    ?DUP IF
        NIP _SBXC-JSON-CODE$ S" result" 2SWAP 5 PICK _SBXC-FAIL!
        FREE _SBXC-REPLY-STATUS EXIT
    THEN
    OVER SWAP 3 PICK _SBXC-REPLY-JSON
    SWAP FREE NIP
    IF CBUS-S-FAILED ELSE CBUS-S-OK THEN ;

: _SBXC-RESULT-VALUE  ( run -- status )
    DUP _SBXR.BUFFER @ SBOX-VM-RESULT-CANDIDATE@
    0= IF 2DROP DROP CBUS-S-FAILED EXIT THEN
    2 PICK _SBXR.STATE @ _SBXC.LIMITS 3 PICK _SBXR.VALUE SBCV-DECODE
    IF DROP CBUS-S-FAILED EXIT THEN
    _SBXC-REPLY-RESULT ;

: _SBXC-RESULT-TRAP  ( run -- status )
    DUP _SBXR.BUFFER @ SBOX-VM-RESULT-DETAIL@
    DUP >R _SBXC-TRAP-CODE$ S" run" 2SWAP 4 PICK _SBXC-FAIL!
    R> SBOX-VM-TRAP-EXPLICIT-ABORT = IF
        DUP _SBXR.BUFFER @ SBOX-VM-RESULT-AUX@ OVER _SBXR.ABORT !
    THEN
    _SBXC-REPLY-STATUS ;

: _SBXC-RESULT-EXHAUSTED  ( run -- status )
    DUP _SBXR.BUFFER @ SBOX-VM-RESULT-DETAIL@ _SBXC-EXHAUST-CODE$
    S" run" 2SWAP 4 PICK _SBXC-FAIL!
    _SBXC-REPLY-STATUS ;

: _SBXC-RESULT-CANCELLED  ( run -- status )
    DUP _SBXR.BUFFER @ SBOX-VM-RESULT-DETAIL@ _SBXC-CANCEL-CODE$
    S" run" 2SWAP 4 PICK _SBXC-FAIL!
    _SBXC-REPLY-STATUS ;

\ The reply for the VM result the run's buffer holds.
: _SBXC-OUTCOME  ( run -- status )
    DUP _SBXR.BUFFER @ SBOX-VM-RESULT-CLASS@
    CASE
        SBOX-VM-CLASS-OK OF _SBXC-RESULT-VALUE ENDOF
        SBOX-VM-CLASS-GUEST-TRAP OF _SBXC-RESULT-TRAP ENDOF
        SBOX-VM-CLASS-RESOURCE-EXHAUSTED OF _SBXC-RESULT-EXHAUSTED ENDOF
        SBOX-VM-CLASS-CANCELLED OF _SBXC-RESULT-CANCELLED ENDOF
        >R DROP CBUS-S-FAILED R>
    ENDCASE ;

\ Takes a settled job's result, replies with it and completes the run.
: _SBXC-FINISH  ( run -- )
    DUP _SBXC-JOB SBOX-JOB-RESULT-MEASURE IF
        DROP S" The sandbox could not read the result" ROT
        _SBXC-COMPLETE-FAILED EXIT
    THEN
    DUP ALLOCATE IF
        2DROP S" The sandbox ran out of memory" ROT
        _SBXC-COMPLETE-FAILED EXIT
    THEN
    2 PICK _SBXR.BUFFER ! OVER _SBXR.BUFFER-U !
    DUP _SBXR.BUFFER @ OVER _SBXR.BUFFER-U @ 2 PICK _SBXC-JOB
        SBOX-JOB-RESULT-TAKE IF
        S" The sandbox could not take the result" ROT
        _SBXC-COMPLETE-FAILED EXIT
    THEN
    \ Taking the result freed the job.
    0 OVER _SBXR.ACTIVATION !
    DUP _SBXC-OUTCOME
    DUP CBUS-S-FAILED = IF
        DROP S" The sandbox could not write its reply" ROT
        _SBXC-COMPLETE-FAILED EXIT
    THEN
    SWAP _SBXC-COMPLETE ;

\ Completes a run that was cancelled or has settled; a runnable run
\ waits.
: _SBXC-SETTLE  ( run -- )
    DUP _SBXR.REQUEST @ CBR-CANCEL-REQUESTED? IF
        CBUS-S-CANCELLED SWAP _SBXC-COMPLETE EXIT
    THEN
    DUP _SBXC-JOB SBOX-JOB-QUERY IF
        2DROP DROP S" The sandbox lost the run" ROT
        _SBXC-COMPLETE-FAILED EXIT
    THEN
    2DROP
    DUP SBOX-JOB-STATE-RUNNABLE = IF 2DROP EXIT THEN
    SBOX-JOB-STATE-READY = IF _SBXC-FINISH EXIT THEN
    S" The sandbox run failed" ROT _SBXC-COMPLETE-FAILED ;

\ =====================================================================
\  Host interface
\ =====================================================================

: _SBXC-RUNS-INIT  ( state -- )
    DUP _SBXC.CAPACITY @ 0 ?DO
        I OVER _SBXC-RUN
        2DUP _SBXR.STATE !
        _SBXR.BUILD SBOX-BUILD-INIT DROP
    LOOP
    DROP ;

\ Frees what a binding allocated and clears the state.  Its runs have
\ already ended.
: _SBXC-RELEASE  ( state -- )
    >R
    R@ _SBXC.SERVICE @ ?DUP IF
        DUP R@ _SBXC.SERVICE-U @ SBOX-JOB-SERVICE-RELEASE DROP
        FREE
    THEN
    R@ _SBXC.RUNS @ ?DUP IF
        DUP R@ _SBXC.CAPACITY @ _SBXR-SIZE * 0 FILL FREE
    THEN
    R@ _SBXC-STATE-SIZE 0 FILL
    R> DROP ;

: _SBXC-OPEN  ( state -- status )
    >R
    R@ _SBXC.CAPACITY @ SBOX-JOB-SERVICE-MEASURE
    IF DROP R> DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    DUP R@ _SBXC.SERVICE-U !
    ALLOCATE IF DROP R> DROP SBOX-CAPABILITY-S-NOMEM EXIT THEN
    \ The service starts from zeroed storage.
    DUP R@ _SBXC.SERVICE-U @ 0 FILL
    R@ _SBXC.SERVICE !
    R@ _SBXC.CAPACITY @ _SBXR-SIZE * DUP ALLOCATE
    IF 2DROP R> DROP SBOX-CAPABILITY-S-NOMEM EXIT THEN
    DUP R@ _SBXC.RUNS ! SWAP 0 FILL
    R@ _SBXC.PROFILE SBOX-PROFILE-PURE-INIT
    IF R> DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    R@ _SBXC.POLICY @ R@ _SBXC.LIMITS SBOX-LIMITS-MATERIALIZE
    >R 2DROP DROP R>
    IF R> DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    R@ _SBXC.PARENT @ R@ _SBXC.POLICY @
    R@ _SBXC.SLICE @ R@ _SBXC.ALLOWANCE @
    R@ _SBXC.INSTANCE @ CINST.ID @ R@ _SBXC.CAPACITY @
    R@ _SBXC.SERVICE @ R@ _SBXC.SERVICE-U @
    SBOX-JOB-SERVICE-INIT
    IF R> DROP SBOX-CAPABILITY-S-SERVICE EXIT THEN
    R@ _SBXC-RUNS-INIT
    _SBXC-MAGIC R> _SBXC.MAGIC !
    SBOX-CAPABILITY-S-OK ;

\ Completes every run as cancelled, then frees the binding.  New
\ requests are refused from the start.
: _SBXC-UNBIND  ( state -- )
    0 OVER _SBXC.MAGIC !
    DUP _SBXC.CAPACITY @ 0 ?DO
        I OVER _SBXC-RUN DUP _SBXR.PHASE @ _SBXC-RUNNING = IF
            CBUS-S-CANCELLED SWAP _SBXC-COMPLETE
        ELSE
            DROP
        THEN
    LOOP
    _SBXC-RELEASE ;

: _SBXC-FINI  ( state -- )
    DUP _SBXC-BOUND? IF _SBXC-UNBIND ELSE DROP THEN ;

: _SBXC-OURS?  ( instance -- flag )
    DUP 0= IF EXIT THEN
    DUP CINST-STATE 0= IF DROP 0 EXIT THEN
    CINST-DESC _SBXC-TABLES = ;

\ Binds INSTANCE to a parent Context and a complete host limit policy,
\ with room for CAPACITY runs at once.  SLICE-STEPS and ALLOWANCE-MS pace
\ the runs as SBOX-JOB-SERVICE-INIT describes.  POLICY is copied here;
\ PARENT stays borrowed until unbind.
: SBOX-CAPABILITY-BIND
  ( parent policy slice-steps allowance-ms capacity instance -- status )
    DUP _SBXC-OURS? 0= IF
        2DROP 2DROP 2DROP SBOX-CAPABILITY-S-INVALID EXIT
    THEN
    DUP CINST-STATE _SBXC-BOUND? IF
        2DROP 2DROP 2DROP SBOX-CAPABILITY-S-STATE EXIT
    THEN
    DUP CINST-STATE >R
    R@ _SBXC-STATE-SIZE 0 FILL
    R@ _SBXC.INSTANCE !
    R@ _SBXC.CAPACITY ! R@ _SBXC.ALLOWANCE ! R@ _SBXC.SLICE !
    R@ _SBXC.POLICY ! R@ _SBXC.PARENT !
    R@ _SBXC-OPEN DUP IF R@ _SBXC-RELEASE THEN
    \ The service and the value limits hold their own copies.
    0 R> _SBXC.POLICY ! ;

\ Completes every run as cancelled and frees the binding.
: SBOX-CAPABILITY-UNBIND  ( instance -- status )
    DUP _SBXC-OURS? 0= IF DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    CINST-STATE _SBXC-FINI SBOX-CAPABILITY-S-OK ;

\ Runs jobs within the allowance, then completes every run that was
\ cancelled or has settled.
: SBOX-CAPABILITY-TICK  ( instance -- status )
    DUP _SBXC-OURS? 0= IF DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? 0= IF
        DROP SBOX-CAPABILITY-S-STATE EXIT
    THEN
    DUP _SBXC.SERVICE @ SBOX-JOB-SERVICE-TICK DROP
    0
    BEGIN
        \ A completion callback may have unbound the instance.
        OVER _SBXC-BOUND? IF DUP 2 PICK _SBXC.CAPACITY @ < ELSE 0 THEN
    WHILE
        DUP 2 PICK _SBXC-RUN
        DUP _SBXR.PHASE @ _SBXC-RUNNING = IF _SBXC-SETTLE ELSE DROP THEN
        1+
    REPEAT
    2DROP SBOX-CAPABILITY-S-OK ;

\ Completes a closing caller's runs as cancelled.  The host calls this
\ before the caller frees its requests.
: SBOX-CAPABILITY-OWNER-DRAIN
  ( owner-id owner-generation instance -- status )
    DUP _SBXC-OURS? 0= IF DROP 2DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? 0= IF
        DROP 2DROP SBOX-CAPABILITY-S-STATE EXIT
    THEN
    0
    BEGIN
        OVER _SBXC-BOUND? IF DUP 2 PICK _SBXC.CAPACITY @ < ELSE 0 THEN
    WHILE
        DUP 2 PICK _SBXC-RUN
        DUP _SBXR.PHASE @ _SBXC-RUNNING =
        OVER _SBXR.OWNER-ID @ 6 PICK = AND
        OVER _SBXR.OWNER-GEN @ 5 PICK = AND IF
            CBUS-S-CANCELLED SWAP _SBXC-COMPLETE
        ELSE
            DROP
        THEN
        1+
    REPEAT
    2DROP 2DROP SBOX-CAPABILITY-S-OK ;

\ Whether a run is under way, so the host keeps ticking.
: SBOX-CAPABILITY-BUSY?  ( instance -- flag )
    DUP _SBXC-OURS? 0= IF DROP 0 EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? 0= IF DROP 0 EXIT THEN
    DUP _SBXC.CAPACITY @ 0 ?DO
        I OVER _SBXC-RUN _SBXR.PHASE @ _SBXC-RUNNING = IF
            DROP -1 UNLOOP EXIT
        THEN
    LOOP
    DROP 0 ;

\ =====================================================================
\  Descriptor and schema initialization
\ =====================================================================

: _SBXC-OR-NULL  ( type -- mask ) CS-TYPE-BIT CV-T-NULL CS-TYPE-BIT OR ;

: _SBXC-FIELD!  ( key-a key-u schema-index flags field-index -- )
    _SBXC-FIELD >R
    R@ CSF.FLAGS !
    _SBXC-SCHEMA R@ CSF.SCHEMA !
    R@ CSF.KEY-U ! R> CSF.KEY-A ! ;

\ A closed map of COUNT fields from FIRST-FIELD.  TYPES also admits null
\ for a map that may be absent.
: _SBXC-MAP-SCHEMA!  ( first-field count types schema-index -- )
    _SBXC-SCHEMA >R
    R@ CS-ALLOW-MASK!
    DUP R@ CS.FIELD-N ! R@ CS-MAX-LEN!
    _SBXC-FIELD R> CS.FIELDS ! ;

: _SBXC-SCHEMAS-INIT  ( -- )
    _SBXS-SOURCE _SBXC-SCHEMA
        CV-T-STRING OVER CS-ALLOW!
        SBOX-COMPILER-SOURCE-MAX CV-MAX-STRING-LEN MIN SWAP CS-MAX-LEN!
    _SBXS-ENTRY _SBXC-SCHEMA
        CV-T-STRING OVER CS-ALLOW!
        SBOX-COMPILER-TOKEN-MAX SWAP CS-MAX-LEN!
    _SBXS-JSON _SBXC-SCHEMA
        CV-T-STRING OVER CS-ALLOW!
        CV-MAX-STRING-LEN SWAP CS-MAX-LEN!
    _SBXS-MEMORY _SBXC-SCHEMA
        CV-T-INT OVER CS-ALLOW!
        0 OVER CS-MIN!
        SBOX-PROFILE-MAX-MEMORY-BYTES SWAP CS-MAX!
    CV-T-BOOL _SBXS-BOOL _SBXC-SCHEMA CS-ALLOW!
    _SBXS-RESULT _SBXC-SCHEMA
        CV-T-STRING _SBXC-OR-NULL OVER CS-ALLOW-MASK!
        CV-MAX-STRING-LEN SWAP CS-MAX-LEN!
    CV-T-STRING _SBXS-TEXT _SBXC-SCHEMA CS-ALLOW!
    CV-T-STRING _SBXC-OR-NULL _SBXS-MAYBE-TEXT _SBXC-SCHEMA CS-ALLOW-MASK!
    _SBXS-POSITION _SBXC-SCHEMA
        CV-T-INT _SBXC-OR-NULL OVER CS-ALLOW-MASK! 1 SWAP CS-MIN!
    _SBXS-COUNT _SBXC-SCHEMA
        CV-T-INT _SBXC-OR-NULL OVER CS-ALLOW-MASK! 0 SWAP CS-MIN!

    S" source" _SBXS-SOURCE CSF-F-REQUIRED _SBXF-IN _SBXC-FIELD!
    S" entry" _SBXS-ENTRY CSF-F-REQUIRED _SBXF-IN 1+ _SBXC-FIELD!
    S" input" _SBXS-JSON CSF-F-REQUIRED _SBXF-IN 2 + _SBXC-FIELD!
    S" memory" _SBXS-MEMORY CSF-F-REQUIRED _SBXF-IN 3 + _SBXC-FIELD!
    _SBXF-IN 4 CV-T-MAP CS-TYPE-BIT _SBXS-IN _SBXC-MAP-SCHEMA!

    S" ok" _SBXS-BOOL CSF-F-REQUIRED _SBXF-OUT _SBXC-FIELD!
    S" result" _SBXS-RESULT CSF-F-REQUIRED _SBXF-OUT 1+ _SBXC-FIELD!
    S" error" _SBXS-ERROR CSF-F-REQUIRED _SBXF-OUT 2 + _SBXC-FIELD!
    _SBXF-OUT 3 CV-T-MAP CS-TYPE-BIT _SBXS-OUT _SBXC-MAP-SCHEMA!

    S" step" _SBXS-TEXT CSF-F-REQUIRED _SBXF-ERROR _SBXC-FIELD!
    S" code" _SBXS-TEXT CSF-F-REQUIRED _SBXF-ERROR 1+ _SBXC-FIELD!
    S" abort" _SBXS-COUNT CSF-F-REQUIRED _SBXF-ERROR 2 + _SBXC-FIELD!
    S" line" _SBXS-POSITION CSF-F-REQUIRED _SBXF-ERROR 3 + _SBXC-FIELD!
    S" column" _SBXS-POSITION CSF-F-REQUIRED _SBXF-ERROR 4 + _SBXC-FIELD!
    S" length" _SBXS-COUNT CSF-F-REQUIRED _SBXF-ERROR 5 + _SBXC-FIELD!
    S" text" _SBXS-MAYBE-TEXT CSF-F-REQUIRED _SBXF-ERROR 6 + _SBXC-FIELD!
    _SBXF-ERROR 7 CV-T-MAP _SBXC-OR-NULL _SBXS-ERROR _SBXC-MAP-SCHEMA! ;

: _SBXC-CAPABILITY-INIT  ( -- )
    _SBXC-TEST-CAP DUP CAP-DESC-INIT
    CAP-K-COMMAND OVER CAP.KIND !
    S" org.akashic.sandbox/test" 2 PICK CAP.ID-U ! OVER CAP.ID-A !
    S" Test sandbox source" 2 PICK CAP.TITLE-U ! OVER CAP.TITLE-A !
    S" Compile restricted sandbox source, run one entry on a JSON input, and return its JSON result or where the module failed."
        2 PICK CAP.DESC-U ! OVER CAP.DESC-A !
    _SBXS-IN _SBXC-SCHEMA OVER CAP.IN-SCHEMA !
    _SBXS-OUT _SBXC-SCHEMA OVER CAP.OUT-SCHEMA !
    CAP-E-OBSERVE OVER CAP.EFFECTS !
    CAP-F-IDEMPOTENT OVER CAP.FLAGS !
    ['] _SBXC-TEST SWAP CAP.HANDLER-XT ! ;

: _SBXC-COMPONENT-INIT  ( -- )
    SBOX-CAPABILITY-COMPONENT DUP COMP-DESC-INIT
    S" org.akashic.sandbox" 2 PICK COMP.ID-U ! OVER COMP.ID-A !
    S" 1.0.0" 2 PICK COMP.VERSION-U ! OVER COMP.VERSION-A !
    _SBXC-STATE-SIZE OVER COMP.STATE-SIZE !
    ['] _SBXC-FINI OVER COMP.STATE-FINI-XT !
    _SBXC-TEST-CAP OVER COMP.CAPS-A !
    1 SWAP COMP.CAPS-N ! ;

: _SBXC-TABLES-INIT  ( -- )
    _SBXC-TABLES _SBXT-SIZE 0 FILL
    _SBXC-SCHEMAS-INIT
    _SBXC-CAPABILITY-INIT
    _SBXC-COMPONENT-INIT ;

_SBXC-TABLES-INIT
