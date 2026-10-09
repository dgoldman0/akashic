\ =====================================================================
\  sandbox-capability.f - The shared sandbox capability
\ =====================================================================
\  Component org.akashic.sandbox gives every caller the request bus
\  admits one way to run restricted sandbox source and installed modules.
\
\    test       compiles and verifies source and runs one of its entries.
\    install    builds source into a named module revision and keeps it.
\    invoke     runs an entry of an installed module revision.
\    list       lists the installed modules, a page at a time.
\    authorize  asks the user to let the calling component use a module
\               revision.
\
\  A reply carries the entry's result or where things failed: the step, a
\  stable code and, when source bytes caused it, their line, column,
\  length and text.  What fails before running is answered at once; a run
\  is accepted and completed later, from the host's tick, and a request
\  to use a module waits for the host's answer.
\
\  Installed modules live in a module table the binding fills from a
\  module store when the host gives it storage.  A module is named, its
\  entries carry the schemas their inputs and results must match, and
\  every revision is exact.  Other components reach a module revision only
\  through a grant the user approves, kept per Practice; the Agent reaches
\  modules through its own review and Mandate.
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
REQUIRE intent.f
REQUIRE codecs/sandbox-value.f
REQUIRE codecs/json-value.f
REQUIRE ../sandbox/profile-codec.f
REQUIRE codecs/json-schema.f
REQUIRE codecs/sandbox-schema.f
REQUIRE policy.f
REQUIRE ../runtime/registry.f
REQUIRE ../runtime/practice-head.f
REQUIRE ../runtime/context.f
REQUIRE ../runtime/sandbox-build.f
REQUIRE ../runtime/sandbox-job-service.f
REQUIRE ../runtime/sandbox-module-store.f

\ =====================================================================
\  Status
\ =====================================================================

0 CONSTANT SBOX-CAPABILITY-S-OK
1 CONSTANT SBOX-CAPABILITY-S-INVALID
2 CONSTANT SBOX-CAPABILITY-S-STATE
3 CONSTANT SBOX-CAPABILITY-S-SERVICE
4 CONSTANT SBOX-CAPABILITY-S-NOMEM
5 CONSTANT SBOX-CAPABILITY-S-STORE

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
        SBOX-VERIFIER-D-ARTIFACT-SPAN OF S" artifact-span" ENDOF
        SBOX-VERIFIER-D-PROFILE-SPAN OF S" profile-span" ENDOF
        SBOX-VERIFIER-D-PLAN-SPAN OF S" plan-span" ENDOF
        SBOX-VERIFIER-D-WORKSPACE-SPAN OF S" workspace-span" ENDOF
        SBOX-VERIFIER-D-OVERLAP OF S" overlap" ENDOF
        SBOX-VERIFIER-D-ARTIFACT-GEOMETRY OF S" artifact-geometry" ENDOF
        SBOX-VERIFIER-D-PROFILE-DIGEST OF S" profile-digest" ENDOF
        SBOX-VERIFIER-D-MEMORY OF S" memory" ENDOF
        SBOX-VERIFIER-D-COUNTS OF S" counts" ENDOF
        SBOX-VERIFIER-D-PADDING OF S" padding" ENDOF
        SBOX-VERIFIER-D-FUNCTION-CODE OF S" function-code" ENDOF
        SBOX-VERIFIER-D-FUNCTION-SIGNATURE OF S" function-signature" ENDOF
        SBOX-VERIFIER-D-FUNCTION-FLAGS OF S" function-flags" ENDOF
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

: _SBXC-SCHEMA-CODE$  ( csb-ior -- address length )
    CASE
        CSB-E-TYPE OF S" type" ENDOF
        CSB-E-DEPTH OF S" depth" ENDOF
        CSB-E-OPEN OF S" open" ENDOF
        >R S" invalid" R>
    ENDCASE ;

: _SBXC-STORE-CODE$  ( store-status -- address length )
    CASE
        SBOX-STORE-S-DUPLICATE OF S" duplicate" ENDOF
        SBOX-STORE-S-REVOKED OF S" revoked" ENDOF
        SBOX-STORE-S-REMOVED OF S" removed" ENDOF
        SBOX-STORE-S-CONFLICT OF S" conflict" ENDOF
        SBOX-STORE-S-RECOVERY OF S" recovery" ENDOF
        SBOX-STORE-S-IO OF S" io" ENDOF
        SBOX-STORE-S-BUSY OF S" busy" ENDOF
        SBOX-STORE-S-NOMEM OF S" nomem" ENDOF
        >R S" state" R>
    ENDCASE ;

: _SBXC-MODULE-CODE$  ( module-status -- address length )
    CASE
        SBOX-MODULE-S-PROFILE OF S" profile" ENDOF
        SBOX-MODULE-S-MISMATCH OF S" mismatch" ENDOF
        SBOX-MODULE-S-VERIFY OF S" verify" ENDOF
        SBOX-MODULE-S-DUPLICATE OF S" duplicate" ENDOF
        >R S" invalid" R>
    ENDCASE ;

\ A module's state as callers see it.
: _SBXC-STATE$  ( module-state -- address length )
    CASE
        SBOX-MODULE-DECLARED OF S" installed" ENDOF
        SBOX-MODULE-VERIFIED OF S" installed" ENDOF
        SBOX-MODULE-QUARANTINED OF S" quarantined" ENDOF
        SBOX-MODULE-RETIRED OF S" revoked" ENDOF
        >R S" unknown" R>
    ENDCASE ;

\ =====================================================================
\  Descriptors and schemas
\ =====================================================================
\ One immutable table holds the component and capability descriptors,
\ the schema nodes and their map fields.

0 CONSTANT _SBXT-COMPONENT
_SBXT-COMPONENT COMP-DESC + CONSTANT _SBXT-CAPS

\ A page of the module list holds at most this many modules.
8 CONSTANT _SBXC-PAGE

\ The capabilities, contiguous in this order.
0 CONSTANT _SBXK-TEST
1 CONSTANT _SBXK-INSTALL
2 CONSTANT _SBXK-INVOKE
3 CONSTANT _SBXK-LIST
4 CONSTANT _SBXK-AUTHORIZE
5 CONSTANT _SBXK-N
\ One intent for each capability, through which applets reach it.
_SBXT-CAPS _SBXK-N CAP-DESC * + CONSTANT _SBXT-INTENTS
_SBXT-INTENTS _SBXK-N CINT-DESC-SIZE * + CONSTANT _SBXT-SCHEMAS

 0 CONSTANT _SBXS-IN
 1 CONSTANT _SBXS-SOURCE
 2 CONSTANT _SBXS-NAME
 3 CONSTANT _SBXS-JSON
 4 CONSTANT _SBXS-NATURAL
 5 CONSTANT _SBXS-OUT
 6 CONSTANT _SBXS-BOOL
 7 CONSTANT _SBXS-RESULT
 8 CONSTANT _SBXS-ERROR
 9 CONSTANT _SBXS-TEXT
10 CONSTANT _SBXS-MAYBE-TEXT
11 CONSTANT _SBXS-POSITION
12 CONSTANT _SBXS-COUNT
13 CONSTANT _SBXS-REVISION
14 CONSTANT _SBXS-INSTALL-IN
15 CONSTANT _SBXS-SPECS
16 CONSTANT _SBXS-SPEC
17 CONSTANT _SBXS-INVOKE-IN
18 CONSTANT _SBXS-LIST-IN
19 CONSTANT _SBXS-LIST-OUT
20 CONSTANT _SBXS-MODULES
21 CONSTANT _SBXS-ITEM
22 CONSTANT _SBXS-MAYBE-SPECS
23 CONSTANT _SBXS-AUTHORIZE-IN
24 CONSTANT _SBXS-N

\ The map fields of every request, reply and error.
_SBXT-SCHEMAS _SBXS-N CS-SIZE * + CONSTANT _SBXT-FIELDS
 0 CONSTANT _SBXF-IN
 4 CONSTANT _SBXF-OUT
 7 CONSTANT _SBXF-ERROR
14 CONSTANT _SBXF-INSTALL
19 CONSTANT _SBXF-SPEC
22 CONSTANT _SBXF-INVOKE
26 CONSTANT _SBXF-LIST
27 CONSTANT _SBXF-LIST-OUT
29 CONSTANT _SBXF-ITEM
33 CONSTANT _SBXF-AUTHORIZE
35 CONSTANT _SBXF-N
_SBXT-FIELDS _SBXF-N CS-FIELD-SIZE * + CONSTANT _SBXT-SIZE

CREATE _SBXC-TABLES _SBXT-SIZE ALLOT

: SBOX-CAPABILITY-COMPONENT  ( -- desc ) _SBXC-TABLES _SBXT-COMPONENT + ;
: _SBXC-CAP  ( index -- cap ) CAP-DESC * _SBXT-CAPS + _SBXC-TABLES + ;
: _SBXC-INTENT  ( index -- intent )
    CINT-DESC-SIZE * _SBXT-INTENTS + _SBXC-TABLES + ;

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
 80 CONSTANT _SBXC-LIMITS
_SBXC-LIMITS SBOX-VALUE-LIMITS-SIZE + CONSTANT _SBXC-VM-LIMITS
_SBXC-VM-LIMITS SBOX-VM-LIMITS-SIZE + CONSTANT _SBXC-PROFILE
\ With storage: the registry that names callers, the module table and
\ store the binding owns, and scratch for module identities.
_SBXC-PROFILE SBOX-PROFILE-SIZE + 7 + -8 AND CONSTANT _SBXC-REGISTRY
_SBXC-REGISTRY 8 + CONSTANT _SBXC-MODULES
_SBXC-MODULES 8 + CONSTANT _SBXC-STORE
_SBXC-STORE 8 + CONSTANT _SBXC-ASK-SEQ
_SBXC-ASK-SEQ 8 + CONSTANT _SBXC-RID
_SBXC-RID 32 + CONSTANT _SBXC-KEY
_SBXC-KEY 32 + CONSTANT _SBXC-DECL-WS
_SBXC-DECL-WS SBOX-DECL-WORKSPACE-SIZE + CONSTANT _SBXC-DECL-LIMITS
_SBXC-DECL-LIMITS SBOX-LIMITS-SIZE + CONSTANT _SBXC-STATE-SIZE

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
\ The value limits and activation limits the policy gives.
: _SBXC.LIMITS     ( state -- value-limits ) _SBXC-LIMITS + ;
: _SBXC.VM-LIMITS  ( state -- vm-limits ) _SBXC-VM-LIMITS + ;
\ Every module runs under the production pure-computation profile, which
\ the binding loads and keeps while any plan it built may borrow it.
: _SBXC.PROFILE    ( state -- profile ) _SBXC-PROFILE + ;
: _SBXC.REGISTRY   ( state -- a ) _SBXC-REGISTRY + ;
: _SBXC.MODULES    ( state -- a ) _SBXC-MODULES + ;
: _SBXC.STORE      ( state -- a ) _SBXC-STORE + ;
\ The last identity given to a request that waits for the user.
: _SBXC.ASK-SEQ    ( state -- a ) _SBXC-ASK-SEQ + ;
: _SBXC.RID        ( state -- rid ) _SBXC-RID + ;
: _SBXC.KEY        ( state -- key ) _SBXC-KEY + ;
: _SBXC.DECL-WS    ( state -- workspace ) _SBXC-DECL-WS + ;
\ The limits the declaration of the module being invoked asks for.
: _SBXC.DECL-LIMITS  ( state -- limits ) _SBXC-DECL-LIMITS + ;

0 CONSTANT _SBXC-FREE
1 CONSTANT _SBXC-RUNNING

\ One run: its request, its job and owner token, the failure a reply
\ names, the buffer and value it holds and the build that owns its plan.
\ For a module, also: the pinned module and entry, the declaration an
\ install writes, or the component and Practice a request to use one
\ asks for.
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
_SBXR-BUILD SBOX-BUILD-SIZE + CONSTANT _SBXR-KIND
_SBXR-KIND 8 + CONSTANT _SBXR-MODULE
_SBXR-MODULE 8 + CONSTANT _SBXR-ENTRY
_SBXR-ENTRY 8 + CONSTANT _SBXR-DETAIL-A
_SBXR-DETAIL-A 8 + CONSTANT _SBXR-DETAIL-U
_SBXR-DETAIL-U 8 + CONSTANT _SBXR-DECL
_SBXR-DECL 8 + CONSTANT _SBXR-DECL-U
_SBXR-DECL-U 8 + CONSTANT _SBXR-ASK-ID
_SBXR-ASK-ID 8 + CONSTANT _SBXR-GRANTEE-U
_SBXR-GRANTEE-U 8 + CONSTANT _SBXR-GRANTEE
_SBXR-GRANTEE SBOX-STORE-GRANTEE-MAX + 7 + -8 AND CONSTANT _SBXR-PRACTICE
_SBXR-PRACTICE RID-SIZE + CONSTANT _SBXR-SIZE

0 CONSTANT _SBXC-TEST-RUN
1 CONSTANT _SBXC-INVOKE-RUN
2 CONSTANT _SBXC-ASK-RUN

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
: _SBXR.KIND        ( run -- a ) _SBXR-KIND + ;
: _SBXR.MODULE      ( run -- a ) _SBXR-MODULE + ;
: _SBXR.ENTRY       ( run -- a ) _SBXR-ENTRY + ;
: _SBXR.DETAIL-A    ( run -- a ) _SBXR-DETAIL-A + ;
: _SBXR.DETAIL-U    ( run -- a ) _SBXR-DETAIL-U + ;
: _SBXR.DECL        ( run -- a ) _SBXR-DECL + ;
: _SBXR.DECL-U      ( run -- a ) _SBXR-DECL-U + ;
: _SBXR.ASK-ID      ( run -- a ) _SBXR-ASK-ID + ;
: _SBXR.GRANTEE-U   ( run -- a ) _SBXR-GRANTEE-U + ;
: _SBXR.GRANTEE     ( run -- grantee ) _SBXR-GRANTEE + ;
: _SBXR.PRACTICE    ( run -- rid ) _SBXR-PRACTICE + ;

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

\ Ends a run's own work, its job, buffer, value, plan, declaration and
\ module pin, and frees the run.  It keeps its home state and its empty
\ build record.
: _SBXC-RUN-END  ( run -- )
    DUP _SBXR.ACTIVATION @ IF
        DUP _SBXC-JOB SBOX-JOB-DISCARD DROP
    THEN
    DUP _SBXC-DROP-BUFFER
    DUP _SBXR.VALUE CV-NULL!
    DUP _SBXR.BUILD SBOX-BUILD-RELEASE DROP
    DUP _SBXR.DECL @ ?DUP IF FREE THEN
    DUP _SBXR.MODULE @ ?DUP IF SBOX-MODULE-UNPIN DROP THEN
    _SBXC-FREE OVER _SBXR.PHASE !
    DUP _SBXR.REQUEST _SBXR-BUILD _SBXR-REQUEST - 0 FILL
    _SBXR.KIND _SBXR-SIZE _SBXR-KIND - 0 FILL ;

: _SBXC-FAIL!  ( step-a step-u code-a code-u run -- )
    >R
    R@ _SBXR.CODE-U ! R@ _SBXR.CODE-A !
    R@ _SBXR.STEP-U ! R@ _SBXR.STEP-A !
    -1 R@ _SBXR.OFFSET !
    0 R@ _SBXR.LENGTH !
    0 R@ _SBXR.DETAIL-U !
    -1 R> _SBXR.ABORT ! ;

\ The text a failure without a source position names, such as an entry.
: _SBXC-DETAIL!  ( text-a text-u run -- )
    TUCK _SBXR.DETAIL-U ! _SBXR.DETAIL-A ! ;

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
        R@ _SBXR.DETAIL-U @ IF
            R@ _SBXR.DETAIL-A @ R@ _SBXR.DETAIL-U @
                S" text" 6 5 PICK _SBXC-PUT-TEXT
        ELSE
            S" text" 6 3 PICK _SBXC-PUT-NULL
        THEN
        NIP R> DROP EXIT
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

\ Writes {ok: true, result: null, error: null}.
: _SBXC-REPLY-OK  ( run -- ior )
    >R
    3 R@ _SBXC-TOP CV-MAP! ?DUP IF R> DROP EXIT THEN
    -1 S" ok" 0 R@ _SBXC-TOP _SBXC-PUT-BOOL ?DUP IF R> DROP EXIT THEN
    S" result" 1 R@ _SBXC-TOP _SBXC-PUT-NULL ?DUP IF R> DROP EXIT THEN
    S" error" 2 R> _SBXC-TOP _SBXC-PUT-NULL ;

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

\ Ends a run whose reply IOR says was written or not, and answers its
\ request now.
: _SBXC-ANSWERED  ( ior run -- status )
    DUP _SBXR.REQUEST @ >R _SBXC-RUN-END
    IF
        S" The sandbox could not write its reply" CBUS-S-FAILED
        R> _SBXC-REFUSE EXIT
    THEN
    R> DROP CBUS-S-OK ;

\ Replies now with the run's failure and ends the run.
: _SBXC-ANSWER  ( run -- status )
    DUP _SBXC-REPLY-FAILURE SWAP _SBXC-ANSWERED ;

\ Replies now that the request succeeded and ends the run.
: _SBXC-ANSWER-OK  ( run -- status )
    DUP _SBXC-REPLY-OK SWAP _SBXC-ANSWERED ;

: _SBXC-NOMEM-END  ( run -- status )
    >R S" The sandbox ran out of memory" CBUS-S-FAILED R> _SBXC-END-REFUSE ;

\ Answers a run whose check failed.  CODE 1: the run records the
\ failure; 2: memory ran out; 3: the sandbox failed itself.
: _SBXC-CHECK-FAILED  ( run code -- status )
    DUP 1 = IF DROP _SBXC-ANSWER EXIT THEN
    2 = IF _SBXC-NOMEM-END EXIT THEN
    >R S" The sandbox could not declare the module" CBUS-S-FAILED
    R> _SBXC-END-REFUSE ;

\ =====================================================================
\  Starting a run
\ =====================================================================

\ Guest memory the request asks for, rounded up to whole cells.
: _SBXC-MEMORY  ( run -- memory-u )
    S" memory" ROT _SBXR.REQUEST @ _SBXC-ARG
    ?DUP IF CV-DATA@ 7 + -8 AND ELSE 0 THEN ;

\ Whether the policy grants the guest memory the request asks for.
: _SBXC-MEMORY?  ( run -- flag )
    DUP _SBXC-MEMORY
    SBOX-VM-LIMIT-MEMORY-BYTES ROT _SBXR.STATE @ _SBXC.VM-LIMITS
    SBOX-VM-LIMIT@ > 0= ;

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

\ Builds the request's source within the guest memory the policy grants,
\ or answers why it could not.
: _SBXC-PREPARE  ( run -- run -1 | status 0 )
    DUP _SBXC-MEMORY? 0= IF
        >R S" input" S" limit" R@ _SBXC-FAIL! R> _SBXC-ANSWER 0 EXIT
    THEN
    DUP _SBXC-BUILD
    DUP SBOX-BUILD-S-COMPILE = OVER SBOX-BUILD-S-VERIFY = OR IF
        DROP DUP _SBXC-BUILD-FAILED _SBXC-ANSWER 0 EXIT
    THEN
    IF
        >R S" The sandbox could not build the module" CBUS-S-FAILED
        R> _SBXC-END-REFUSE 0 EXIT
    THEN
    -1 ;

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

\ Submits PLAN's entry the request names on the encoded input, narrowed
\ by LIMITS when there are any.
: _SBXC-SUBMIT  ( plan limits|0 run -- job-status )
    >R SWAP
    S" entry" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    R@ _SBXR.BUFFER @ R@ _SBXR.BUFFER-U @
    5 PICK
    R@ _SBXR.OWNER-ID @ R@ _SBXR.OWNER-GEN @
    R@ _SBXR.STATE @ _SBXC.SERVICE @
    SBOX-JOB-SUBMIT
    -ROT R@ _SBXR.GENERATION ! R@ _SBXR.ACTIVATION !
    NIP R> DROP ;

: _SBXC-INPUT-JSON-FAILED  ( run ivjson-ior -- status )
    DUP IVJSON-E-NOMEM = IF DROP _SBXC-NOMEM-END EXIT THEN
    _SBXC-JSON-CODE$ S" input" 2SWAP 4 PICK _SBXC-FAIL! _SBXC-ANSWER ;

: _SBXC-INPUT-ENCODE-FAILED  ( run sbcv-status -- status )
    DUP SBCV-S-NOMEM = IF DROP _SBXC-NOMEM-END EXIT THEN
    _SBXC-INPUT-CODE$ S" input" 2SWAP 4 PICK _SBXC-FAIL! _SBXC-ANSWER ;

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
    _SBXC-PREPARE 0= IF EXIT THEN
    DUP _SBXC-DECODE-INPUT ?DUP IF _SBXC-INPUT-JSON-FAILED EXIT THEN
    DUP _SBXC-ENCODE ?DUP IF _SBXC-INPUT-ENCODE-FAILED EXIT THEN
    DUP _SBXR.BUILD SBOX-BUILD-PLAN@ DROP 0 2 PICK _SBXC-SUBMIT
    OVER _SBXC-DROP-BUFFER
    ?DUP IF _SBXC-SUBMIT-FAILED EXIT THEN
    DROP CBUS-S-ACCEPTED ;

: _SBXC-CALLER?  ( request -- flag )
    DUP CBR.CALLER-ID @ 0> SWAP CBR.CALLER-GEN @ 0> AND ;

\ Claims a run, owned by the calling instance, or refuses the request.
: _SBXC-ACCEPT  ( request instance -- run -1 | status 0 )
    CINST-STATE
    DUP _SBXC-BOUND? 0= IF
        DROP >R S" The sandbox is not running" CBUS-S-FAILED
        R> _SBXC-REFUSE 0 EXIT
    THEN
    OVER _SBXC-CALLER? 0= IF
        DROP >R S" A sandbox run needs a calling instance" CBUS-S-DENIED
        R> _SBXC-REFUSE 0 EXIT
    THEN
    OVER SWAP _SBXC-CLAIM
    ?DUP 0= IF
        >R S" Every sandbox run is in use" CBUS-S-BUSY R> _SBXC-REFUSE
        0 EXIT
    THEN
    NIP
    DUP _SBXR.REQUEST @ CBR.CALLER-ID @ OVER _SBXR.OWNER-ID !
    DUP _SBXR.REQUEST @ CBR.CALLER-GEN @ OVER _SBXR.OWNER-GEN !
    -1 ;

\ The org.akashic.sandbox/test handler.
: _SBXC-TEST  ( request instance -- status )
    _SBXC-ACCEPT IF _SBXC-START THEN ;

\ =====================================================================
\  Modules
\ =====================================================================
\ Installed modules are named and every revision is exact.  Each entry's
\ input and result must match the schemas its declaration gives, and
\ both cross as JSON, so an entry JSON cannot carry is refused before
\ anything runs.

\ Decodes sandbox schema bytes into a graph in fresh storage, which the
\ caller frees.  IOR is a CSB- error, or -1 when memory runs out.
: _SBXC-GRAPH  ( schema schema-u -- graph storage ior )
    2DUP SBCS-MEASURE ?DUP IF >R DROP 2DROP 0 0 R> EXIT THEN
    DUP ALLOCATE IF 2DROP 2DROP 0 0 -1 EXIT THEN
    DUP >R SWAP SBCS-DECODE
    ?DUP IF NIP R> FREE 0 0 ROT EXIT THEN
    R> 0 ;

\ Whether JSON can carry every value the schema admits.  IOR is as
\ _SBXC-GRAPH gives it.
: _SBXC-JSON-SCHEMA?  ( schema schema-u -- flag ior )
    _SBXC-GRAPH ?DUP IF NIP NIP 0 SWAP EXIT THEN
    SWAP IVJSON-SCHEMA-COMPATIBLE? SWAP FREE 0 ;

\ The installed revision of the module NAME, or 0.
: _SBXC-MODULE  ( name name-u revision state -- module|0 )
    >R
    R@ _SBXC.MODULES @ 0= IF DROP 2DROP R> DROP 0 EXIT THEN
    -ROT R@ _SBXC.RID R@ _SBXC.DECL-WS SBOX-DECL-MODULE-RID IF
        DROP R> DROP 0 EXIT
    THEN
    R@ _SBXC.RID SWAP R> _SBXC.MODULES @ SBOX-MODULE-FIND ;

\ The module revision the request names, or 0.
: _SBXC-ARG-MODULE  ( run -- module|0 )
    >R
    S" module" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    S" revision" R@ _SBXR.REQUEST @ _SBXC-ARG CV-DATA@
    R> _SBXR.STATE @ _SBXC-MODULE ;

\ Records why the module the request names cannot be used.
: _SBXC-MODULE-FAIL!  ( code-a code-u run -- )
    >R S" module" 2SWAP R@ _SBXC-FAIL!
    S" module" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING R> _SBXC-DETAIL! ;

\ The calling component's id, or 0 0 when the registry cannot name it.
: _SBXC-CALLER$  ( request state -- id id-u | 0 0 )
    _SBXC.REGISTRY @ ?DUP 0= IF DROP 0 0 EXIT THEN
    >R DUP CBR.CALLER-ID @ SWAP CBR.CALLER-GEN @ R> CREG-INST-FIND
    ?DUP 0= IF 0 0 EXIT THEN
    CINST-DESC DUP COMP.ID-A @ SWAP COMP.ID-U @ ;

\ The Practice the parent Context works in, or 0.
: _SBXC-PRACTICE  ( state -- rid|0 )
    _SBXC.PARENT @ ?DUP 0= IF 0 EXIT THEN
    CTX.PRACTICE @ DUP PHEAD-VALID? 0= IF DROP 0 EXIT THEN
    PHEAD.ID ;

\ Records the calling component and the Practice it works in, or why
\ there are none.
: _SBXC-WHO  ( run -- flag )
    DUP _SBXR.REQUEST @ OVER _SBXR.STATE @ _SBXC-CALLER$
    DUP 0= OVER SBOX-STORE-GRANTEE-MAX > OR IF
        2DROP >R S" access" S" caller" R@ _SBXC-FAIL! R> DROP 0 EXIT
    THEN
    DUP 3 PICK _SBXR.GRANTEE-U !
    2 PICK _SBXR.GRANTEE SWAP MOVE
    DUP _SBXR.STATE @ _SBXC-PRACTICE ?DUP 0= IF
        >R S" access" S" practice" R@ _SBXC-FAIL! R> DROP 0 EXIT
    THEN
    SWAP _SBXR.PRACTICE RID-SIZE MOVE -1 ;

\ Whether the run's component holds a grant for MODULE in its Practice.
: _SBXC-GRANTED?  ( module run -- flag )
    >R SBOX-MODULE-KEY@
    R@ _SBXR.PRACTICE -ROT
    R@ _SBXR.GRANTEE R@ _SBXR.GRANTEE-U @ 2SWAP
    R> _SBXR.STATE @ _SBXC.STORE @ SBOX-STORE-GRANTED? ;

\ Whether the caller may use MODULE: the Agent under its own review and
\ Mandate, any other component through a grant in its Practice.  The
\ Agent's requests name Desk as their caller, so a grant cannot stand
\ for them.
: _SBXC-ACCESS?  ( module run -- flag )
    DUP _SBXR.REQUEST @ CBR.PRINCIPAL @ CPRINC-AGENT = IF 2DROP -1 EXIT THEN
    DUP _SBXC-WHO 0= IF 2DROP 0 EXIT THEN
    TUCK _SBXC-GRANTED? IF DROP -1 EXIT THEN
    >R S" access" S" not-granted" R@ _SBXC-FAIL! R> DROP 0 ;

\ 0 when MODULE can run, after verifying a module loaded from storage on
\ its first use; 1 when the run records why not; 2 when memory ran out.
: _SBXC-READY  ( module run -- code )
    OVER 0= IF NIP S" unknown" ROT _SBXC-MODULE-FAIL! 1 EXIT THEN
    OVER SBOX-MODULE-STATE@ SBOX-MODULE-DECLARED = IF
        OVER OVER _SBXR.STATE @ _SBXC.STORE @ SBOX-STORE-VERIFY
        DUP SBOX-STORE-S-NOMEM = IF DROP 2DROP 2 EXIT THEN
        DUP SBOX-STORE-S-OK <> OVER SBOX-STORE-S-MODULE <> AND IF
            \ The artifact could not be read; the module stays declared.
            _SBXC-STORE-CODE$ S" store" 2SWAP 4 PICK _SBXC-FAIL!
            2DROP 1 EXIT
        THEN
        DROP
    THEN
    OVER SBOX-MODULE-STATE@
    DUP SBOX-MODULE-VERIFIED = IF DROP 2DROP 0 EXIT THEN
    SBOX-MODULE-RETIRED = IF S" revoked" ELSE S" quarantined" THEN
    ROT _SBXC-MODULE-FAIL! DROP 1 ;

\ Claims a run for a request about installed modules, or refuses it.
: _SBXC-ACCEPT-MODULES  ( request instance -- run -1 | status 0 )
    DUP CINST-STATE DUP _SBXC-BOUND? IF
        _SBXC.MODULES @ 0= IF
            DROP >R S" The sandbox has no module storage" CBUS-S-FAILED
            R> _SBXC-REFUSE 0 EXIT
        THEN
    ELSE
        DROP
    THEN
    _SBXC-ACCEPT ;

\ ---------------------------------------------------------------------
\  Invoking
\ ---------------------------------------------------------------------

\ The index of the entry the request names, or -1 when the run records
\ that MODULE has none.
: _SBXC-ENTRY  ( module run -- index )
    >R
    S" entry" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    ROT SBOX-MODULE-DECLARATION$ DROP SBOX-DECL-ENTRY-FIND
    DUP 0< IF
        S" entry" S" unknown" R@ _SBXC-FAIL!
        S" entry" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING R@ _SBXC-DETAIL!
    THEN
    R> DROP ;

\ 0 when JSON can carry entry INDEX's input and result, 1 when the run
\ records that it cannot, 2 when memory ran out.
: _SBXC-ENTRY-JSON  ( index declaration run -- code )
    >R
    2DUP SBOX-DECL-ENTRY-INPUT$ DROP _SBXC-JSON-SCHEMA?
    IF 2DROP DROP R> DROP 2 EXIT THEN
    IF
        SBOX-DECL-ENTRY-OUTPUT$ DROP _SBXC-JSON-SCHEMA?
        IF DROP R> DROP 2 EXIT THEN
        IF R> DROP 0 EXIT THEN
    ELSE
        2DROP
    THEN
    S" entry" S" unsupported" R@ _SBXC-FAIL!
    S" entry" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING R> _SBXC-DETAIL!
    1 ;

\ 0 when the decoded input matches entry INDEX's input schema, 1 when
\ the run records that it does not, 2 when memory ran out.
: _SBXC-INPUT-MATCH  ( index declaration run -- code )
    >R SBOX-DECL-ENTRY-INPUT$ DROP _SBXC-GRAPH
    IF 2DROP R> DROP 2 EXIT THEN
    SWAP R@ _SBXR.VALUE SWAP CS-VALIDATE-DEEP
    SWAP FREE
    IF S" input" S" schema" R> _SBXC-FAIL! 1 EXIT THEN
    R> DROP 0 ;

\ 0 when an invoked entry's result matches its output schema, 1 when it
\ does not, 2 when memory ran out.
: _SBXC-OUTPUT-MATCH  ( run -- code )
    >R
    R@ _SBXR.ENTRY @ R@ _SBXR.MODULE @ SBOX-MODULE-DECLARATION$ DROP
    SBOX-DECL-ENTRY-OUTPUT$ DROP _SBXC-GRAPH
    IF 2DROP R> DROP 2 EXIT THEN
    SWAP R@ _SBXR.VALUE SWAP CS-VALIDATE-DEEP
    SWAP FREE
    R> DROP 0<> 1 AND ;

\ Checks the module, the caller's access, the entry and the input, then
\ pins the module for the run and submits it within the limits its
\ declaration asks for.
: _SBXC-INVOKE-START  ( run -- status )
    DUP _SBXC-ARG-MODULE
    DUP 2 PICK _SBXC-READY ?DUP IF NIP _SBXC-CHECK-FAILED EXIT THEN
    DUP 2 PICK _SBXC-ACCESS? 0= IF DROP _SBXC-ANSWER EXIT THEN
    DUP 2 PICK _SBXC-ENTRY
    DUP 0< IF 2DROP _SBXC-ANSWER EXIT THEN
    OVER SBOX-MODULE-DECLARATION$ DROP
    \ ( run module index declaration )
    2DUP 5 PICK _SBXC-ENTRY-JSON ?DUP IF
        >R 2DROP DROP R> _SBXC-CHECK-FAILED EXIT
    THEN
    3 PICK _SBXC-DECODE-INPUT ?DUP IF
        >R 2DROP DROP R> _SBXC-INPUT-JSON-FAILED EXIT
    THEN
    2DUP 5 PICK _SBXC-INPUT-MATCH ?DUP IF
        >R 2DROP DROP R> _SBXC-CHECK-FAILED EXIT
    THEN
    3 PICK _SBXC-ENCODE ?DUP IF
        >R 2DROP DROP R> _SBXC-INPUT-ENCODE-FAILED EXIT
    THEN
    \ The run holds the pin until it ends.
    2 PICK SBOX-MODULE-PIN IF
        DROP 2DROP DROP >R S" The sandbox could not start the run"
        CBUS-S-FAILED R> _SBXC-END-REFUSE EXIT
    THEN
    \ ( run module index declaration plan )
    3 PICK 5 PICK _SBXR.MODULE !
    2 PICK 5 PICK _SBXR.ENTRY !
    SWAP 4 PICK _SBXR.STATE @ _SBXC.DECL-LIMITS TUCK SBOX-DECL-LIMITS IF
        2DROP 2DROP >R S" The sandbox could not start the run"
        CBUS-S-FAILED R> _SBXC-END-REFUSE EXIT
    THEN
    \ ( run module index plan limits )
    ROT DROP ROT DROP 2 PICK _SBXC-SUBMIT
    OVER _SBXC-DROP-BUFFER
    ?DUP IF _SBXC-SUBMIT-FAILED EXIT THEN
    DROP CBUS-S-ACCEPTED ;

\ The org.akashic.sandbox/invoke handler.
: _SBXC-INVOKE  ( request instance -- status )
    _SBXC-ACCEPT-MODULES 0= IF EXIT THEN
    _SBXC-INVOKE-RUN OVER _SBXR.KIND !
    _SBXC-INVOKE-START ;

\ ---------------------------------------------------------------------
\  Installing
\ ---------------------------------------------------------------------
\ An install declares the build: the request's module and revision, the
\ plan's entries in their order, and for each the schemas the request
\ gives as JSON Schema text.  The declaration's digest is the install's
\ operation key, so the same install again changes nothing.

: _SBXC-SPECS  ( run -- list ) S" entries" ROT _SBXR.REQUEST @ _SBXC-ARG ;

\ The text of SPEC's field KEY.
: _SBXC-SPEC$  ( key-a key-u spec -- address length )
    CV-MAP-FIND _SBXC-STRING ;

\ The spec the request gives for the entry NAME, or 0.
: _SBXC-SPEC  ( name name-u run -- spec|0 )
    _SBXC-SPECS
    DUP CV-LEN@ 0 ?DO
        I OVER CV-LIST-NTH
        S" name" 2 PICK _SBXC-SPEC$ 5 PICK 5 PICK STR-STR= IF
            NIP NIP NIP UNLOOP EXIT
        THEN
        DROP
    LOOP
    DROP 2DROP 0 ;

\ Whether PLAN has an entry named NAME.
: _SBXC-PLAN-HAS?  ( name name-u plan -- flag )
    DUP SBOX-PLAN-ENTRY-N@ 0 ?DO
        I OVER SBOX-PLAN-ENTRY-NAME$ 4 PICK 4 PICK STR-STR= IF
            DROP 2DROP -1 UNLOOP EXIT
        THEN
    LOOP
    DROP 2DROP 0 ;

\ Whether the request gives one spec for each of the plan's entries and
\ no other; otherwise the run records which entry is wrong.
: _SBXC-ENTRIES?  ( plan run -- flag )
    OVER SBOX-PLAN-ENTRY-N@ 0 ?DO
        I 2 PICK SBOX-PLAN-ENTRY-NAME$ 2 PICK _SBXC-SPEC 0= IF
            S" entries" S" missing" 4 PICK _SBXC-FAIL!
            I 2 PICK SBOX-PLAN-ENTRY-NAME$ 2 PICK _SBXC-DETAIL!
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DUP _SBXC-SPECS CV-LEN@ 2 PICK SBOX-PLAN-ENTRY-N@ = IF 2DROP -1 EXIT THEN
    DUP _SBXC-SPECS
    DUP CV-LEN@ 0 ?DO
        I OVER CV-LIST-NTH S" name" ROT _SBXC-SPEC$
        2DUP 6 PICK _SBXC-PLAN-HAS? 0= IF
            S" entries" S" unknown" 7 PICK _SBXC-FAIL!
            3 PICK _SBXC-DETAIL! 2DROP DROP 0 UNLOOP EXIT
        THEN
        2DROP
    LOOP
    DROP
    S" entries" S" duplicate" 4 PICK _SBXC-FAIL!
    2DROP 0 ;

\ Room for every spec's two schemas as bytes, each after its length cell
\ and padded to a cell.  Bytes never outgrow the JSON text by more than
\ the magic.
: _SBXC-SCHEMA-ROOM  ( run -- capacity )
    _SBXC-SPECS 0 SWAP
    DUP CV-LEN@ 0 ?DO
        I OVER CV-LIST-NTH
        S" input" 2 PICK _SBXC-SPEC$ NIP
        SWAP S" output" ROT _SBXC-SPEC$ NIP +
        CSB-MAGIC-SIZE 15 + 2* +
        ROT + SWAP
    LOOP
    DROP ;

: _SBXC-SCHEMA-KEY$  ( output? -- key-a key-u )
    IF S" output" ELSE S" input" THEN ;

: _SBXC-SCHEMA-STEP$  ( output? -- step-a step-u )
    IF S" output-schema" ELSE S" input-schema" THEN ;

\ Records why SPEC's input or output schema was refused.
: _SBXC-SCHEMA-FAIL!  ( code-a code-u spec output? run -- )
    >R
    _SBXC-SCHEMA-STEP$ 2>R
    S" name" ROT _SBXC-SPEC$
    2SWAP 2R> 2SWAP R@ _SBXC-FAIL!
    R> _SBXC-DETAIL! ;

\ Reads SPEC's input or output JSON schema as sandbox schema bytes at
\ CURSOR, after their length cell, and moves the cursor past them,
\ padded to a cell.  0, or 1 when the run records why the schema was
\ refused, or 2 when memory ran out.
: _SBXC-READ-SCHEMA  ( spec output? cursor run -- cursor' code )
    >R
    OVER _SBXC-SCHEMA-KEY$ 4 PICK _SBXC-SPEC$
    DUP CSB-MAGIC-SIZE + 3 PICK 8 + SWAP CSJSON-READ
    DUP IVJSON-E-NOMEM = IF 2DROP 2DROP DROP R> DROP 0 2 EXIT THEN
    ?DUP IF
        NIP NIP _SBXC-JSON-CODE$ 2SWAP R> _SBXC-SCHEMA-FAIL! 0 1 EXIT
    THEN
    OVER 8 + OVER SBCS-MEASURE NIP ?DUP IF
        NIP NIP _SBXC-SCHEMA-CODE$ 2SWAP R> _SBXC-SCHEMA-FAIL! 0 1 EXIT
    THEN
    2DUP SWAP !
    7 + -8 AND 8 + +
    NIP NIP 0 R> DROP ;

\ Reads both schemas of entry INDEX of the plan at CURSOR.
: _SBXC-READ-ENTRY  ( cursor index plan run -- cursor' code )
    >R
    SBOX-PLAN-ENTRY-NAME$ R@ _SBXC-SPEC
    DUP 0 3 PICK R@ _SBXC-READ-SCHEMA
    ?DUP IF >R 2DROP DROP 0 R> R> DROP EXIT THEN
    ROT DROP -1 SWAP R> _SBXC-READ-SCHEMA ;

\ Reads every entry's schemas into the run's buffer, in plan order.
: _SBXC-READ-SCHEMAS  ( plan run -- code )
    DUP _SBXR.BUFFER @
    2 PICK SBOX-PLAN-ENTRY-N@ 0 ?DO
        I 3 PICK 3 PICK _SBXC-READ-ENTRY
        ?DUP IF NIP NIP NIP UNLOOP EXIT THEN
    LOOP
    DROP 2DROP 0 ;

\ The schema at CURSOR and the cursor past it.
: _SBXC-NEXT-SCHEMA  ( cursor -- schema schema-u cursor' )
    DUP 8 + SWAP @ 2DUP 7 + -8 AND + ;

\ Schema K of those read into BUFFER.
: _SBXC-NTH-SCHEMA  ( k buffer -- schema schema-u )
    SWAP 0 ?DO _SBXC-NEXT-SCHEMA NIP NIP LOOP
    DUP 8 + SWAP @ ;

\ The total length of the schemas read for the plan's entries.
: _SBXC-SCHEMA-U  ( plan run -- schema-u )
    _SBXR.BUFFER @ SWAP SBOX-PLAN-ENTRY-N@ 2*
    0 -ROT 0 ?DO
        _SBXC-NEXT-SCHEMA ROT DROP -ROT + SWAP
    LOOP
    DROP ;

\ Sizes the declaration and starts it in a fresh buffer the run holds.
: _SBXC-DECL-START  ( plan run -- code )
    >R
    DUP SBOX-PLAN-ENTRY-N@ 0 2 PICK R@ _SBXC-SCHEMA-U SBOX-DECL-MEASURE
    IF 2DROP R> DROP 3 EXIT THEN
    DUP ALLOCATE IF 2DROP DROP R> DROP 2 EXIT THEN
    R@ _SBXR.DECL ! R@ _SBXR.DECL-U !
    S" revision" R@ _SBXR.REQUEST @ _SBXC-ARG CV-DATA@
    OVER SBOX-PLAN-ARTIFACT-DIGEST@
    2 PICK SBOX-PLAN-PROFILE-DIGEST@
    3 PICK SBOX-PLAN-ENTRY-N@ 0
    5 PICK R@ _SBXC-SCHEMA-U
    R@ _SBXR.DECL @ R@ _SBXR.DECL-U @
    SBOX-DECL-START NIP
    R> DROP IF 3 ELSE 0 THEN ;

\ Writes entry INDEX: its name and signature from the plan, and its
\ schemas from the run's buffer.
: _SBXC-WRITE-ENTRY  ( index plan run -- status )
    >R
    OVER SWAP 2DUP SBOX-PLAN-ENTRY-SIGNATURE@ DROP
    -ROT SBOX-PLAN-ENTRY-NAME$ ROT
    >R 2>R DUP 2R> R>
    R@ _SBXR.DECL @ SBOX-DECL-ENTRY! ?DUP IF NIP R> DROP EXIT THEN
    DUP 2* R@ _SBXR.BUFFER @ _SBXC-NTH-SCHEMA
    2 PICK 2* 1+ R@ _SBXR.BUFFER @ _SBXC-NTH-SCHEMA
    R@ _SBXR.STATE @ _SBXC.DECL-WS R> _SBXR.DECL @ SBOX-DECL-SCHEMAS! ;

: _SBXC-WRITE-ENTRIES  ( plan run -- status )
    OVER SBOX-PLAN-ENTRY-N@ 0 ?DO
        I 2 PICK 2 PICK _SBXC-WRITE-ENTRY
        ?DUP IF NIP NIP UNLOOP EXIT THEN
    LOOP
    2DROP 0 ;

\ Declares the run's build in a buffer the run holds.  0, or 1 when the
\ run records why it cannot, 2 when memory ran out, 3 when the sandbox
\ failed itself.
: _SBXC-DECLARE  ( run -- code )
    >R
    R@ _SBXR.BUILD SBOX-BUILD-PLAN@ DROP
    DUP R@ _SBXC-ENTRIES? 0= IF DROP R> DROP 1 EXIT THEN
    R@ _SBXC-SCHEMA-ROOM DUP ALLOCATE IF 2DROP DROP R> DROP 2 EXIT THEN
    R@ _SBXR.BUFFER ! R@ _SBXR.BUFFER-U !
    DUP R@ _SBXC-READ-SCHEMAS ?DUP IF NIP R> DROP EXIT THEN
    DUP R@ _SBXC-DECL-START ?DUP IF NIP R> DROP EXIT THEN
    S" module" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    R@ _SBXR.STATE @ _SBXC.DECL-WS R@ _SBXR.DECL @ SBOX-DECL-MODULE!
    IF DROP R> DROP 3 EXIT THEN
    R> _SBXC-WRITE-ENTRIES IF 3 ELSE 0 THEN ;

\ Installs the declared build, keyed by the declaration's digest.
: _SBXC-STORE-INSTALL  ( run -- status )
    >R
    R@ _SBXR.DECL @ R@ _SBXR.DECL-U @
    R@ _SBXR.STATE @ _SBXC.KEY R@ _SBXR.STATE @ _SBXC.DECL-WS
    SBOX-DECL-DIGEST IF
        S" The sandbox could not declare the module" CBUS-S-FAILED
        R> _SBXC-END-REFUSE EXIT
    THEN
    R@ _SBXR.STATE @ _SBXC.KEY
    R@ _SBXR.DECL @ R@ _SBXR.DECL-U @
    R@ _SBXR.BUILD
    R@ _SBXR.STATE @ _SBXC.STORE @
    SBOX-STORE-INSTALL NIP
    DUP SBOX-STORE-S-OK = IF DROP R> _SBXC-ANSWER-OK EXIT THEN
    DUP SBOX-STORE-S-NOMEM = IF DROP R> _SBXC-NOMEM-END EXIT THEN
    DUP SBOX-STORE-S-MODULE = IF
        DROP R@ _SBXR.STATE @ _SBXC.STORE @ SBOX-STORE-MODULE-STATUS@
        _SBXC-MODULE-CODE$ S" module" 2SWAP
    ELSE
        _SBXC-STORE-CODE$ S" store" 2SWAP
    THEN
    R@ _SBXC-FAIL! R> _SBXC-ANSWER ;

\ Checks the module's name, builds the source, declares it and installs
\ it.
: _SBXC-INSTALL-RUN  ( run -- status )
    S" module" 2 PICK _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    2 PICK _SBXR.STATE @ DUP _SBXC.RID SWAP _SBXC.DECL-WS
    SBOX-DECL-MODULE-RID IF
        S" name" 2 PICK _SBXC-MODULE-FAIL! _SBXC-ANSWER EXIT
    THEN
    _SBXC-PREPARE 0= IF EXIT THEN
    DUP _SBXC-DECLARE ?DUP IF _SBXC-CHECK-FAILED EXIT THEN
    _SBXC-STORE-INSTALL ;

\ The org.akashic.sandbox/install handler.
: _SBXC-INSTALL  ( request instance -- status )
    _SBXC-ACCEPT-MODULES IF _SBXC-INSTALL-RUN THEN ;

\ ---------------------------------------------------------------------
\  Listing
\ ---------------------------------------------------------------------

\ Sandbox schema bytes as JSON Schema text, written into BUFFER, which
\ holds CV-MAX-STRING-LEN bytes.
: _SBXC-SCHEMA-TEXT  ( schema schema-u buffer -- text text-u ior )
    >R _SBXC-GRAPH ?DUP IF NIP NIP R> 0 ROT EXIT THEN
    SWAP R@ CV-MAX-STRING-LEN CSJSON-ENCODE
    ROT FREE R> -ROT ;

\ Writes {input, name, output} for entry INDEX of DECLARATION into SPEC.
: _SBXC-LIST-SPEC  ( index declaration buffer spec -- ior )
    3 OVER CV-MAP! ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    >R
    2 PICK 2 PICK SBOX-DECL-ENTRY-INPUT$ DROP 2 PICK _SBXC-SCHEMA-TEXT
    ?DUP IF >R 2DROP 2DROP DROP R> R> DROP EXIT THEN
    S" input" 0 R@ _SBXC-PUT-TEXT ?DUP IF >R 2DROP DROP R> R> DROP EXIT THEN
    2 PICK 2 PICK SBOX-DECL-ENTRY-NAME$ S" name" 1 R@ _SBXC-PUT-TEXT
    ?DUP IF >R 2DROP DROP R> R> DROP EXIT THEN
    ROT ROT SBOX-DECL-ENTRY-OUTPUT$ DROP ROT _SBXC-SCHEMA-TEXT
    ?DUP IF >R 2DROP R> R> DROP EXIT THEN
    S" output" 2 R> _SBXC-PUT-TEXT ;

\ Writes the specs of DECLARATION's entries into LIST.
: _SBXC-LIST-SPECS  ( declaration buffer list -- ior )
    2 PICK SBOX-DECL-ENTRY-N@ OVER CV-LIST! ?DUP IF NIP NIP NIP EXIT THEN
    2 PICK SBOX-DECL-ENTRY-N@ 0 ?DO
        I 3 PICK 3 PICK I 4 PICK CV-LIST-NTH _SBXC-LIST-SPEC
        ?DUP IF NIP NIP NIP UNLOOP EXIT THEN
    LOOP
    DROP 2DROP 0 ;

\ Whether JSON can describe DECLARATION's entries: no more than a list
\ carries, and every schema one JSON can carry.  IOR as _SBXC-GRAPH.
: _SBXC-DESCRIBABLE?  ( declaration -- flag ior )
    DUP SBOX-DECL-ENTRY-N@ IVJSON-MAX-CHILDREN > IF DROP 0 0 EXIT THEN
    DUP SBOX-DECL-ENTRY-N@ 0 ?DO
        I OVER SBOX-DECL-ENTRY-INPUT$ DROP _SBXC-JSON-SCHEMA?
        ?DUP IF NIP NIP 0 SWAP UNLOOP EXIT THEN
        0= IF DROP 0 0 UNLOOP EXIT THEN
        I OVER SBOX-DECL-ENTRY-OUTPUT$ DROP _SBXC-JSON-SCHEMA?
        ?DUP IF NIP NIP 0 SWAP UNLOOP EXIT THEN
        0= IF DROP 0 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 0 ;

\ Writes ITEM's entries: DECLARATION's specs, or null when JSON cannot
\ describe them.
: _SBXC-LIST-ENTRIES  ( declaration buffer item -- ior )
    2 PICK _SBXC-DESCRIBABLE? ?DUP IF NIP NIP NIP NIP EXIT THEN
    0= IF NIP NIP >R S" entries" 0 R> _SBXC-PUT-NULL EXIT THEN
    >R S" entries" 0 R> CV-MAP-SLOT! ?DUP IF NIP NIP NIP EXIT THEN
    _SBXC-LIST-SPECS ;

\ Writes {entries, module, revision, state} for MODULE into ITEM.  The
\ name and entries are null for a module whose declaration is lost.
: _SBXC-LIST-ITEM  ( module buffer item -- ior )
    4 OVER CV-MAP! ?DUP IF NIP NIP NIP EXIT THEN
    2 PICK SBOX-MODULE-DECLARATION$ DROP ?DUP IF
        DUP 3 PICK 3 PICK _SBXC-LIST-ENTRIES
        ?DUP IF NIP NIP NIP NIP EXIT THEN
        SBOX-DECL-MODULE-NAME$ S" module" 1 5 PICK _SBXC-PUT-TEXT
    ELSE
        S" entries" 0 3 PICK _SBXC-PUT-NULL ?DUP IF NIP NIP NIP EXIT THEN
        S" module" 1 3 PICK _SBXC-PUT-NULL
    THEN
    ?DUP IF NIP NIP NIP EXIT THEN
    2 PICK SBOX-MODULE-KEY@ NIP S" revision" 2 4 PICK _SBXC-PUT-INT
    ?DUP IF NIP NIP NIP EXIT THEN
    ROT SBOX-MODULE-STATE@ _SBXC-STATE$ S" state" 3 5 PICK _SBXC-PUT-TEXT
    NIP NIP ;

: _SBXC-MODULE-N  ( owner|0 -- n ) DUP IF SBOX-MODULE-COUNT@ THEN ;

\ Writes into LIST the page of OWNER's modules from index FIRST.
: _SBXC-LIST-MODULES  ( first owner buffer list -- ior )
    2 PICK _SBXC-MODULE-N 4 PICK - 0 MAX _SBXC-PAGE MIN
    DUP 2 PICK CV-LIST! ?DUP IF NIP >R 2DROP 2DROP R> EXIT THEN
    0 ?DO
        I 4 PICK + 3 PICK SBOX-MODULE-NTH
        2 PICK I 3 PICK CV-LIST-NTH _SBXC-LIST-ITEM
        ?DUP IF >R 2DROP 2DROP R> UNLOOP EXIT THEN
    LOOP
    2DROP 2DROP 0 ;

\ Writes {modules, next}: the page from FIRST, and where the next page
\ starts, or null after the last.
: _SBXC-LIST-REPLY  ( first owner buffer map -- ior )
    2 OVER CV-MAP! ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    3 PICK _SBXC-PAGE + DUP 4 PICK _SBXC-MODULE-N < 0= IF DROP -1 THEN
    S" next" 1 4 PICK _SBXC-PUT-MAYBE ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    >R S" modules" 0 R> CV-MAP-SLOT! ?DUP IF >R 2DROP 2DROP R> EXIT THEN
    _SBXC-LIST-MODULES ;

\ The org.akashic.sandbox/list handler.
: _SBXC-LIST  ( request instance -- status )
    CINST-STATE
    DUP _SBXC-BOUND? 0= IF
        DROP >R S" The sandbox is not running" CBUS-S-FAILED
        R> _SBXC-REFUSE EXIT
    THEN
    CV-MAX-STRING-LEN ALLOCATE IF
        2DROP >R S" The sandbox ran out of memory" CBUS-S-FAILED
        R> _SBXC-REFUSE EXIT
    THEN
    S" first" 4 PICK _SBXC-ARG CV-DATA@
    ROT _SBXC.MODULES @
    2 PICK 4 PICK CBR.RESULT _SBXC-LIST-REPLY
    SWAP FREE
    IF
        >R S" The sandbox could not write its reply" CBUS-S-FAILED
        R> _SBXC-REFUSE EXIT
    THEN
    DROP CBUS-S-OK ;

\ ---------------------------------------------------------------------
\  Asking to use a module
\ ---------------------------------------------------------------------
\ A component that holds no grant for a module revision asks for one.
\ The request waits until the host has asked the user, and the user's
\ answer completes it; an allowed request records the grant first.  The
\ request itself observes only: the grant is the user's act.

: _SBXC-ASK  ( run -- status )
    DUP _SBXR.REQUEST @ CBR.PRINCIPAL @ CPRINC-AGENT = IF
        >R S" access" S" agent" R@ _SBXC-FAIL! R> _SBXC-ANSWER EXIT
    THEN
    DUP _SBXC-WHO 0= IF _SBXC-ANSWER EXIT THEN
    DUP _SBXC-ARG-MODULE
    ?DUP 0= IF S" unknown" 2 PICK _SBXC-MODULE-FAIL! _SBXC-ANSWER EXIT THEN
    DUP SBOX-MODULE-STATE@
    DUP SBOX-MODULE-RETIRED = IF
        2DROP S" revoked" 2 PICK _SBXC-MODULE-FAIL! _SBXC-ANSWER EXIT
    THEN
    SBOX-MODULE-QUARANTINED = IF
        DROP S" quarantined" 2 PICK _SBXC-MODULE-FAIL! _SBXC-ANSWER EXIT
    THEN
    OVER _SBXC-GRANTED? IF _SBXC-ANSWER-OK EXIT THEN
    _SBXC-ASK-RUN OVER _SBXR.KIND !
    \ The host answers only the request it showed, never one that later
    \ took the same run.
    1 OVER _SBXR.STATE @ _SBXC.ASK-SEQ +!
    DUP _SBXR.STATE @ _SBXC.ASK-SEQ @ SWAP _SBXR.ASK-ID !
    CBUS-S-ACCEPTED ;

\ The org.akashic.sandbox/authorize handler.
: _SBXC-AUTHORIZE  ( request instance -- status )
    _SBXC-ACCEPT-MODULES IF _SBXC-ASK THEN ;

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

\ An invoked entry's result must match its output schema.
: _SBXC-RESULT-VALUE  ( run -- status )
    DUP _SBXR.BUFFER @ SBOX-VM-RESULT-CANDIDATE@
    0= IF 2DROP DROP CBUS-S-FAILED EXIT THEN
    2 PICK _SBXR.STATE @ _SBXC.LIMITS 3 PICK _SBXR.VALUE SBCV-DECODE
    IF DROP CBUS-S-FAILED EXIT THEN
    DUP _SBXR.KIND @ _SBXC-INVOKE-RUN = IF
        DUP _SBXC-OUTPUT-MATCH
        DUP 2 = IF 2DROP CBUS-S-FAILED EXIT THEN
        IF
            S" output" S" schema" 4 PICK _SBXC-FAIL! _SBXC-REPLY-STATUS EXIT
        THEN
    THEN
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
\ waits, and so does a request to use a module.
: _SBXC-SETTLE  ( run -- )
    DUP _SBXR.REQUEST @ CBR-CANCEL-REQUESTED? IF
        CBUS-S-CANCELLED SWAP _SBXC-COMPLETE EXIT
    THEN
    \ A request to use a module waits for the host's answer.
    DUP _SBXR.KIND @ _SBXC-ASK-RUN = IF DROP EXIT THEN
    DUP _SBXC-JOB SBOX-JOB-QUERY IF
        2DROP DROP S" The sandbox lost the run" ROT
        _SBXC-COMPLETE-FAILED EXIT
    THEN
    2DROP
    DUP SBOX-JOB-STATE-RUNNABLE = IF 2DROP EXIT THEN
    SBOX-JOB-STATE-READY = IF _SBXC-FINISH EXIT THEN
    S" The sandbox run failed" ROT _SBXC-COMPLETE-FAILED ;

\ Completes a deferred run whose reply IOR says was written or not.
: _SBXC-COMPLETE-REPLY  ( ior run -- )
    SWAP IF
        S" The sandbox could not write its reply" ROT _SBXC-COMPLETE-FAILED
        EXIT
    THEN
    CBUS-S-OK SWAP _SBXC-COMPLETE ;

\ Records the grant an asking run wants.
: _SBXC-GRANT  ( run -- store-status )
    >R
    S" module" R@ _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    R@ _SBXR.STATE @ DUP _SBXC.RID SWAP _SBXC.DECL-WS SBOX-DECL-MODULE-RID
    IF R> DROP SBOX-STORE-S-INVALID EXIT THEN
    R@ _SBXR.PRACTICE R@ _SBXR.GRANTEE R@ _SBXR.GRANTEE-U @
    R@ _SBXR.STATE @ _SBXC.RID
    S" revision" R@ _SBXR.REQUEST @ _SBXC-ARG CV-DATA@
    R> _SBXR.STATE @ _SBXC.STORE @ SBOX-STORE-GRANT ;

: _SBXC-ALLOW  ( run -- status )
    DUP _SBXC-GRANT
    DUP SBOX-STORE-S-OK = IF
        DROP DUP _SBXC-REPLY-OK SWAP _SBXC-COMPLETE-REPLY
        SBOX-CAPABILITY-S-OK EXIT
    THEN
    _SBXC-STORE-CODE$ S" store" 2SWAP 4 PICK _SBXC-FAIL!
    DUP _SBXC-REPLY-FAILURE SWAP _SBXC-COMPLETE-REPLY
    SBOX-CAPABILITY-S-STORE ;

: _SBXC-DENY  ( run -- status )
    >R S" access" S" denied" R@ _SBXC-FAIL!
    R@ _SBXC-REPLY-FAILURE R> _SBXC-COMPLETE-REPLY
    SBOX-CAPABILITY-S-OK ;

\ Whether RUN waits for the user to allow it.
: _SBXC-ASKING?  ( run -- flag )
    DUP _SBXR.PHASE @ _SBXC-RUNNING = 0= IF DROP 0 EXIT THEN
    DUP _SBXR.KIND @ _SBXC-ASK-RUN = 0= IF DROP 0 EXIT THEN
    _SBXR.REQUEST @ CBR-CANCEL-REQUESTED? 0= ;

\ Whether ASK is one of STATE's runs and still waits for the user as the
\ request ID.
: _SBXC-OUR-ASK?  ( ask id state -- flag )
    2 PICK 0= IF 2DROP DROP 0 EXIT THEN
    2 PICK OVER _SBXC.RUNS @ -
    DUP 0< IF DROP 2DROP DROP 0 EXIT THEN
    DUP _SBXR-SIZE MOD IF DROP 2DROP DROP 0 EXIT THEN
    _SBXR-SIZE / SWAP _SBXC.CAPACITY @ < 0= IF 2DROP 0 EXIT THEN
    OVER _SBXC-ASKING? 0= IF 2DROP 0 EXIT THEN
    SWAP _SBXR.ASK-ID @ = ;

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

\ Closes the module store and frees the module table, whose modules no
\ run pins any more.
: _SBXC-MODULES-RELEASE  ( state -- )
    DUP _SBXC.STORE @ ?DUP IF
        DUP SBOX-STORE-CLOSE DROP FREE
        0 OVER _SBXC.STORE !
    THEN
    DUP _SBXC.MODULES @ ?DUP IF
        DUP SBOX-MODULE-OWNER-RELEASE DROP FREE
        0 OVER _SBXC.MODULES !
    THEN
    0 SWAP _SBXC.REGISTRY ! ;

\ Frees what a binding allocated and clears the state.  Its runs have
\ already ended.
: _SBXC-RELEASE  ( state -- )
    DUP _SBXC-MODULES-RELEASE
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
    SBOX-PROFILE-LOAD-WORKSPACE-SIZE ALLOCATE
    IF DROP R> DROP SBOX-CAPABILITY-S-NOMEM EXIT THEN
    R@ _SBXC.PROFILE OVER SBOX-PROFILE-PURE-INIT
    SWAP DUP SBOX-PROFILE-LOAD-WORKSPACE-SIZE 0 FILL FREE
    IF R> DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    R@ _SBXC.POLICY @ R@ _SBXC.LIMITS R@ _SBXC.VM-LIMITS
        SBOX-LIMITS-MATERIALIZE
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

\ Whether a run is under way, so the host keeps ticking.  A request to
\ use a module waits for the host's answer instead.
: SBOX-CAPABILITY-BUSY?  ( instance -- flag )
    DUP _SBXC-OURS? 0= IF DROP 0 EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? 0= IF DROP 0 EXIT THEN
    DUP _SBXC.CAPACITY @ 0 ?DO
        I OVER _SBXC-RUN
        DUP _SBXR.PHASE @ _SBXC-RUNNING =
        SWAP _SBXR.KIND @ _SBXC-ASK-RUN <> AND IF
            DROP -1 UNLOOP EXIT
        THEN
    LOOP
    DROP 0 ;

: _SBXC-DROP6  ( a b c d e f -- ) 2DROP 2DROP 2DROP ;

\ Gives a bound instance installed modules: REGISTRY names the callers
\ that ask for them, and the module store keeps them in the catalog and
\ pack files at those absolute paths of VFS, in one directory.  The
\ binding opens the store now and owns it and its module table until
\ unbind.  A store in recovery opens and serves what it could read.
: SBOX-CAPABILITY-MODULES
  ( registry vfs catalog catalog-u pack pack-u instance -- status )
    DUP _SBXC-OURS? 0= IF DROP _SBXC-DROP6 SBOX-CAPABILITY-S-INVALID EXIT THEN
    CINST-STATE
    DUP _SBXC-BOUND? 0= IF DROP _SBXC-DROP6 SBOX-CAPABILITY-S-STATE EXIT THEN
    DUP _SBXC.MODULES @ IF
        DROP _SBXC-DROP6 SBOX-CAPABILITY-S-STATE EXIT
    THEN
    >R
    5 PICK 0= IF _SBXC-DROP6 R> DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    SBOX-MODULE-OWNER-SIZE ALLOCATE IF
        DROP _SBXC-DROP6 R> DROP SBOX-CAPABILITY-S-NOMEM EXIT
    THEN
    DUP SBOX-MODULE-OWNER-SIZE 0 FILL R@ _SBXC.MODULES !
    R@ _SBXC.PROFILE R@ _SBXC.MODULES @ SBOX-MODULE-OWNER-INIT IF
        _SBXC-DROP6 R> _SBXC-MODULES-RELEASE SBOX-CAPABILITY-S-INVALID EXIT
    THEN
    SBOX-STORE-SIZE ALLOCATE IF
        DROP _SBXC-DROP6 R> _SBXC-MODULES-RELEASE SBOX-CAPABILITY-S-NOMEM EXIT
    THEN
    DUP SBOX-STORE-SIZE 0 FILL R@ _SBXC.STORE !
    R@ _SBXC.MODULES @ R@ _SBXC.STORE @ SBOX-STORE-INIT IF
        DROP R> _SBXC-MODULES-RELEASE SBOX-CAPABILITY-S-INVALID EXIT
    THEN
    R@ _SBXC.REGISTRY !
    R@ _SBXC.STORE @ SBOX-STORE-OPEN
    ?DUP 0= IF R> DROP SBOX-CAPABILITY-S-OK EXIT THEN
    R> _SBXC-MODULES-RELEASE
    SBOX-STORE-S-NOMEM = IF
        SBOX-CAPABILITY-S-NOMEM
    ELSE
        SBOX-CAPABILITY-S-STORE
    THEN ;

\ The module store and the module table of a binding with installed
\ modules, or 0.  Through them the host shows modules and grants and
\ revokes or removes them.
: SBOX-CAPABILITY-STORE@  ( instance -- store|0 )
    DUP _SBXC-OURS? 0= IF DROP 0 EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? IF _SBXC.STORE @ ELSE DROP 0 THEN ;

: SBOX-CAPABILITY-MODULES@  ( instance -- owner|0 )
    DUP _SBXC-OURS? 0= IF DROP 0 EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? IF _SBXC.MODULES @ ELSE DROP 0 THEN ;

\ The first request waiting for the user to let its component use a
\ module revision, or 0.  The host asks the user and gives the answer
\ with SBOX-CAPABILITY-ANSWER.
: SBOX-CAPABILITY-ASK  ( instance -- ask|0 )
    DUP _SBXC-OURS? 0= IF DROP 0 EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? 0= IF DROP 0 EXIT THEN
    DUP _SBXC.CAPACITY @ 0 ?DO
        I OVER _SBXC-RUN DUP _SBXC-ASKING? IF NIP UNLOOP EXIT THEN
        DROP
    LOOP
    DROP 0 ;

\ The identity of ASK, which no other request of the binding shares.
: SBOX-CAPABILITY-ASK-ID@  ( ask -- id ) _SBXR.ASK-ID @ ;

\ Whether ASK still waits for the user as the request ID.
: SBOX-CAPABILITY-ASKING?  ( ask id instance -- flag )
    DUP _SBXC-OURS? 0= IF DROP 2DROP 0 EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? 0= IF DROP 2DROP 0 EXIT THEN
    _SBXC-OUR-ASK? ;

\ What ASK wants: the component that asks, and the module revision.
: SBOX-CAPABILITY-ASK@  ( ask -- grantee grantee-u module module-u revision )
    DUP _SBXR.GRANTEE OVER _SBXR.GRANTEE-U @
    S" module" 4 PICK _SBXR.REQUEST @ _SBXC-ARG _SBXC-STRING
    S" revision" 6 PICK _SBXR.REQUEST @ _SBXC-ARG CV-DATA@
    >R >R >R ROT DROP R> R> R> ;

\ Answers ASK, the request ID, with the user's decision and completes
\ it.  A request that no longer waits as ID is refused.  When ALLOW is
\ true, the grant is recorded first; SBOX-CAPABILITY-S-STORE says the
\ store refused it, and the request then fails with why.
: SBOX-CAPABILITY-ANSWER  ( allow ask id instance -- status )
    DUP _SBXC-OURS? 0= IF 2DROP 2DROP SBOX-CAPABILITY-S-INVALID EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? 0= IF
        2DROP 2DROP SBOX-CAPABILITY-S-STATE EXIT
    THEN
    >R OVER SWAP R> _SBXC-OUR-ASK? 0= IF
        2DROP SBOX-CAPABILITY-S-INVALID EXIT
    THEN
    SWAP IF _SBXC-ALLOW ELSE _SBXC-DENY THEN ;

\ The Practice the binding's grants are for, or 0 outside a Practice.
: SBOX-CAPABILITY-PRACTICE  ( instance -- rid|0 )
    DUP _SBXC-OURS? 0= IF DROP 0 EXIT THEN
    CINST-STATE DUP _SBXC-BOUND? IF _SBXC-PRACTICE ELSE DROP 0 THEN ;

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

\ A list of at most N items of the schema ITEM-INDEX.
: _SBXC-LIST-SCHEMA!  ( types n item-index schema-index -- )
    _SBXC-SCHEMA >R
    _SBXC-SCHEMA R@ CS.ITEM !
    R@ CS-MAX-LEN!
    R> CS-ALLOW-MASK! ;

: _SBXC-SCHEMAS-INIT  ( -- )
    _SBXS-SOURCE _SBXC-SCHEMA
        CV-T-STRING OVER CS-ALLOW!
        CV-MAX-STRING-LEN SWAP CS-MAX-LEN!
    \ An entry or a module name.
    _SBXS-NAME _SBXC-SCHEMA
        CV-T-STRING OVER CS-ALLOW!
        SBOX-ABI-ENTRY-NAME-MAX SWAP CS-MAX-LEN!
    _SBXS-JSON _SBXC-SCHEMA
        CV-T-STRING OVER CS-ALLOW!
        CV-MAX-STRING-LEN SWAP CS-MAX-LEN!
    _SBXS-NATURAL _SBXC-SCHEMA
        CV-T-INT OVER CS-ALLOW!
        0 SWAP CS-MIN!
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
    _SBXS-REVISION _SBXC-SCHEMA
        CV-T-INT OVER CS-ALLOW! 1 SWAP CS-MIN!
    CV-T-LIST CS-TYPE-BIT IVJSON-MAX-CHILDREN _SBXS-SPEC _SBXS-SPECS
        _SBXC-LIST-SCHEMA!
    CV-T-LIST _SBXC-OR-NULL IVJSON-MAX-CHILDREN _SBXS-SPEC _SBXS-MAYBE-SPECS
        _SBXC-LIST-SCHEMA!
    CV-T-LIST CS-TYPE-BIT _SBXC-PAGE _SBXS-ITEM _SBXS-MODULES
        _SBXC-LIST-SCHEMA!

    S" source" _SBXS-SOURCE CSF-F-REQUIRED _SBXF-IN _SBXC-FIELD!
    S" entry" _SBXS-NAME CSF-F-REQUIRED _SBXF-IN 1+ _SBXC-FIELD!
    S" input" _SBXS-JSON CSF-F-REQUIRED _SBXF-IN 2 + _SBXC-FIELD!
    S" memory" _SBXS-NATURAL CSF-F-REQUIRED _SBXF-IN 3 + _SBXC-FIELD!
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

: _SBXC-MODULE-SCHEMAS-INIT  ( -- )
    S" entries" _SBXS-SPECS CSF-F-REQUIRED _SBXF-INSTALL _SBXC-FIELD!
    S" memory" _SBXS-NATURAL CSF-F-REQUIRED _SBXF-INSTALL 1+ _SBXC-FIELD!
    S" module" _SBXS-NAME CSF-F-REQUIRED _SBXF-INSTALL 2 + _SBXC-FIELD!
    S" revision" _SBXS-REVISION CSF-F-REQUIRED _SBXF-INSTALL 3 + _SBXC-FIELD!
    S" source" _SBXS-SOURCE CSF-F-REQUIRED _SBXF-INSTALL 4 + _SBXC-FIELD!
    _SBXF-INSTALL 5 CV-T-MAP CS-TYPE-BIT _SBXS-INSTALL-IN _SBXC-MAP-SCHEMA!

    S" input" _SBXS-JSON CSF-F-REQUIRED _SBXF-SPEC _SBXC-FIELD!
    S" name" _SBXS-NAME CSF-F-REQUIRED _SBXF-SPEC 1+ _SBXC-FIELD!
    S" output" _SBXS-JSON CSF-F-REQUIRED _SBXF-SPEC 2 + _SBXC-FIELD!
    _SBXF-SPEC 3 CV-T-MAP CS-TYPE-BIT _SBXS-SPEC _SBXC-MAP-SCHEMA!

    S" entry" _SBXS-NAME CSF-F-REQUIRED _SBXF-INVOKE _SBXC-FIELD!
    S" input" _SBXS-JSON CSF-F-REQUIRED _SBXF-INVOKE 1+ _SBXC-FIELD!
    S" module" _SBXS-NAME CSF-F-REQUIRED _SBXF-INVOKE 2 + _SBXC-FIELD!
    S" revision" _SBXS-REVISION CSF-F-REQUIRED _SBXF-INVOKE 3 + _SBXC-FIELD!
    _SBXF-INVOKE 4 CV-T-MAP CS-TYPE-BIT _SBXS-INVOKE-IN _SBXC-MAP-SCHEMA!

    S" first" _SBXS-NATURAL CSF-F-REQUIRED _SBXF-LIST _SBXC-FIELD!
    _SBXF-LIST 1 CV-T-MAP CS-TYPE-BIT _SBXS-LIST-IN _SBXC-MAP-SCHEMA!

    S" modules" _SBXS-MODULES CSF-F-REQUIRED _SBXF-LIST-OUT _SBXC-FIELD!
    S" next" _SBXS-COUNT CSF-F-REQUIRED _SBXF-LIST-OUT 1+ _SBXC-FIELD!
    _SBXF-LIST-OUT 2 CV-T-MAP CS-TYPE-BIT _SBXS-LIST-OUT _SBXC-MAP-SCHEMA!

    S" entries" _SBXS-MAYBE-SPECS CSF-F-REQUIRED _SBXF-ITEM _SBXC-FIELD!
    S" module" _SBXS-MAYBE-TEXT CSF-F-REQUIRED _SBXF-ITEM 1+ _SBXC-FIELD!
    S" revision" _SBXS-REVISION CSF-F-REQUIRED _SBXF-ITEM 2 + _SBXC-FIELD!
    S" state" _SBXS-TEXT CSF-F-REQUIRED _SBXF-ITEM 3 + _SBXC-FIELD!
    _SBXF-ITEM 4 CV-T-MAP CS-TYPE-BIT _SBXS-ITEM _SBXC-MAP-SCHEMA!

    S" module" _SBXS-NAME CSF-F-REQUIRED _SBXF-AUTHORIZE _SBXC-FIELD!
    S" revision" _SBXS-REVISION CSF-F-REQUIRED _SBXF-AUTHORIZE 1+
        _SBXC-FIELD!
    _SBXF-AUTHORIZE 2 CV-T-MAP CS-TYPE-BIT _SBXS-AUTHORIZE-IN
        _SBXC-MAP-SCHEMA! ;

\ Starts capability INDEX with its id and title.
: _SBXC-CAP!  ( id-a id-u title-a title-u index -- cap )
    _SBXC-CAP DUP CAP-DESC-INIT
    CAP-K-COMMAND OVER CAP.KIND !
    >R R@ CAP.TITLE-U ! R@ CAP.TITLE-A ! R@ CAP.ID-U ! R@ CAP.ID-A ! R> ;

: _SBXC-CAP-DESC!  ( desc-a desc-u cap -- )
    TUCK CAP.DESC-U ! CAP.DESC-A ! ;

\ Gives CAP its schemas, handler, effects and flags.
: _SBXC-CAP-RUN!  ( in-index out-index xt effects flags cap -- )
    >R R@ CAP.FLAGS ! R@ CAP.EFFECTS ! R@ CAP.HANDLER-XT !
    _SBXC-SCHEMA R@ CAP.OUT-SCHEMA ! _SBXC-SCHEMA R> CAP.IN-SCHEMA ! ;

: _SBXC-CAPABILITIES-INIT  ( -- )
    S" org.akashic.sandbox/test" S" Test sandbox source" _SBXK-TEST _SBXC-CAP!
    S" Compile restricted sandbox source, run one entry on a JSON input, and return its JSON result or where the module failed."
        2 PICK _SBXC-CAP-DESC!
    >R _SBXS-IN _SBXS-OUT ['] _SBXC-TEST CAP-E-OBSERVE CAP-F-IDEMPOTENT
        R> _SBXC-CAP-RUN!

    S" org.akashic.sandbox/install" S" Install a sandbox module"
        _SBXK-INSTALL _SBXC-CAP!
    S" Compile and verify restricted sandbox source and keep it as an exact revision of a named module, giving every entry JSON Schemas, as JSON text, for its input and its result. The same install again changes nothing."
        2 PICK _SBXC-CAP-DESC!
    >R _SBXS-INSTALL-IN _SBXS-OUT ['] _SBXC-INSTALL CAP-E-PERSIST
        CAP-F-IDEMPOTENT R> _SBXC-CAP-RUN!

    S" org.akashic.sandbox/invoke" S" Invoke a sandbox module"
        _SBXK-INVOKE _SBXC-CAP!
    S" Run one entry of an installed module revision on a JSON input that matches the entry's input schema, and return its JSON result or why it failed."
        2 PICK _SBXC-CAP-DESC!
    >R _SBXS-INVOKE-IN _SBXS-OUT ['] _SBXC-INVOKE CAP-E-OBSERVE
        CAP-F-IDEMPOTENT R> _SBXC-CAP-RUN!

    S" org.akashic.sandbox/list" S" List sandbox modules" _SBXK-LIST _SBXC-CAP!
    S" List the installed modules a page at a time from the index first, with each revision's state and its entries' JSON Schemas. next is where the following page starts, or null after the last."
        2 PICK _SBXC-CAP-DESC!
    >R _SBXS-LIST-IN _SBXS-LIST-OUT ['] _SBXC-LIST CAP-E-OBSERVE
        CAP-F-IDEMPOTENT R> _SBXC-CAP-RUN!

    S" org.akashic.sandbox/authorize" S" Ask to use a sandbox module"
        _SBXK-AUTHORIZE _SBXC-CAP!
    S" Ask the user to let the calling component invoke an installed module revision in the current Practice. The request completes when the user answers."
        2 PICK _SBXC-CAP-DESC!
    >R _SBXS-AUTHORIZE-IN _SBXS-OUT ['] _SBXC-AUTHORIZE CAP-E-OBSERVE 0
        R> _SBXC-CAP-RUN! ;

: _SBXC-INTENT!  ( id-a id-u index -- )
    DUP _SBXC-CAP SWAP _SBXC-INTENT >R
    R@ CINT-DESC-INIT
    R@ CINTD.CAP !
    R@ CINTD.ID-U ! R@ CINTD.ID-A !
    100 R> CINTD.PRIORITY ! ;

: _SBXC-INTENTS-INIT  ( -- )
    S" sandbox.test" _SBXK-TEST _SBXC-INTENT!
    S" sandbox.install" _SBXK-INSTALL _SBXC-INTENT!
    S" sandbox.invoke" _SBXK-INVOKE _SBXC-INTENT!
    S" sandbox.list" _SBXK-LIST _SBXC-INTENT!
    S" sandbox.authorize" _SBXK-AUTHORIZE _SBXC-INTENT! ;

: _SBXC-COMPONENT-INIT  ( -- )
    SBOX-CAPABILITY-COMPONENT DUP COMP-DESC-INIT
    S" org.akashic.sandbox" 2 PICK COMP.ID-U ! OVER COMP.ID-A !
    S" 1.0.0" 2 PICK COMP.VERSION-U ! OVER COMP.VERSION-A !
    _SBXC-STATE-SIZE OVER COMP.STATE-SIZE !
    ['] _SBXC-FINI OVER COMP.STATE-FINI-XT !
    _SBXK-TEST _SBXC-CAP OVER COMP.CAPS-A !
    _SBXK-N OVER COMP.CAPS-N !
    _SBXK-TEST _SBXC-INTENT OVER COMP.INTENTS-A !
    _SBXK-N SWAP COMP.INTENTS-N ! ;

: _SBXC-TABLES-INIT  ( -- )
    _SBXC-TABLES _SBXT-SIZE 0 FILL
    _SBXC-SCHEMAS-INIT
    _SBXC-MODULE-SCHEMAS-INIT
    _SBXC-CAPABILITIES-INIT
    _SBXC-INTENTS-INIT
    _SBXC-COMPONENT-INIT ;

_SBXC-TABLES-INIT
