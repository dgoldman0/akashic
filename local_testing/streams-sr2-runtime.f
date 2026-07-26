\ streams-sr2-runtime.f - deterministic contracts for the bounded SR2 runtime

PROVIDED akashic-streams-sr2-runtime-contracts

VARIABLE _sr2r-fails
VARIABLE _sr2r-checks
VARIABLE _sr2r-depth

: _sr2r-assert  ( flag -- )
    1 _sr2r-checks +!
    0= IF
        1 _sr2r-fails +!
        ." STREAMS SR2 RUNTIME ASSERT " _sr2r-checks @ . CR
    THEN ;

: _sr2r-stack  ( -- )
    DEPTH DUP _sr2r-depth @ <> IF
        ." STREAMS SR2 RUNTIME STACK "
        _sr2r-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr2r-depth @ = _sr2r-assert ;

CREATE _sr2r-input       STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr2r-output      STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr2r-bidi        STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr2r-bad         STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr2r-flow-a      STREAMS-FLOW-SIZE ALLOT
CREATE _sr2r-flow-b      STREAMS-FLOW-SIZE ALLOT
CREATE _sr2r-event-a     STREAMS-EVENT-SIZE ALLOT
CREATE _sr2r-event-b     STREAMS-EVENT-SIZE ALLOT
CREATE _sr2r-event-c     STREAMS-EVENT-SIZE ALLOT

CREATE _sr2r-ingress-a   STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2r-egress-a    STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2r-in-segments-a STREAMS-PAYLOAD-SEGMENT-SIZE ALLOT
CREATE _sr2r-out-segments-a STREAMS-PAYLOAD-SEGMENT-SIZE ALLOT
CREATE _sr2r-in-bytes-a  STREAMS-RUNTIME-SEGMENT-BYTES ALLOT
CREATE _sr2r-out-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES ALLOT
CREATE _sr2r-operation-a
    STREAMS-RUNTIME-PROFILE-COMPACT
    STREAMS-RUNTIME-OPERATION-CAPACITY ALLOT

CREATE _sr2r-ingress-b   STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2r-egress-b    STREAMS-PAYLOAD-SIZE ALLOT
CREATE _sr2r-in-segments-b
    STREAMS-PAYLOAD-SEGMENT-SIZE 4 * ALLOT
CREATE _sr2r-out-segments-b
    STREAMS-PAYLOAD-SEGMENT-SIZE 4 * ALLOT
CREATE _sr2r-in-bytes-b
    STREAMS-RUNTIME-SEGMENT-BYTES 4 * ALLOT
CREATE _sr2r-out-bytes-b
    STREAMS-RUNTIME-SEGMENT-BYTES 4 * ALLOT
CREATE _sr2r-operation-b
    STREAMS-RUNTIME-PROFILE-STANDARD
    STREAMS-RUNTIME-OPERATION-CAPACITY ALLOT

CREATE _sr2r-large-payload
    STREAMS-RUNTIME-PROFILE-STANDARD
    STREAMS-RUNTIME-INGRESS-CAPACITY 1+ ALLOT
CREATE _sr2r-copy-buffer
    STREAMS-RUNTIME-PROFILE-STANDARD
    STREAMS-RUNTIME-EGRESS-CAPACITY ALLOT
CREATE _sr2r-pool-entries STREAMS-EXECUTION-ENTRY-SIZE 2 * ALLOT
CREATE _sr2r-pool STREAMS-EXECUTION-POOL-SIZE ALLOT
CREATE _sr2r-metadata-entries
    STREAMS-EXECUTION-ENTRY-SIZE STREAMS-CONNECTOR-SIZE + ALLOT
CREATE _sr2r-metadata-pool STREAMS-EXECUTION-POOL-SIZE ALLOT
CREATE _sr2r-peer-entries STREAMS-EXECUTION-ENTRY-SIZE 2 * ALLOT
CREATE _sr2r-peer-pool STREAMS-EXECUTION-POOL-SIZE ALLOT

VARIABLE _sr2r-mode
VARIABLE _sr2r-release-mode
VARIABLE _sr2r-releases
VARIABLE _sr2r-starts
VARIABLE _sr2r-polls
VARIABLE _sr2r-cancels
VARIABLE _sr2r-cleanups
VARIABLE _sr2r-reentry-status
VARIABLE _sr2r-pool-flow-a
VARIABLE _sr2r-pool-flow-b
VARIABLE _sr2r-pool-lease-a
VARIABLE _sr2r-pool-lease-b
VARIABLE _sr2r-binding-epoch
VARIABLE _sr2r-carrier-generation
VARIABLE _sr2r-reservation-generation
VARIABLE _sr2r-old-generation

VARIABLE _sr2r-cb-event
VARIABLE _sr2r-cb-op
VARIABLE _sr2r-cb-result
VARIABLE _sr2r-t-event
VARIABLE _sr2r-t-output
VARIABLE _sr2r-t-result
VARIABLE _sr2r-build-event
VARIABLE _sr2r-build-flow
VARIABLE _sr2r-build-tag
VARIABLE _sr2r-build-timeout
VARIABLE _sr2r-build-a
VARIABLE _sr2r-build-u
VARIABLE _sr2r-expected-status
VARIABLE _sr2r-expected-state
VARIABLE _sr2r-expected-effect

0  CONSTANT _SR2R-MODE-DELIVER
1  CONSTANT _SR2R-MODE-PENDING
2  CONSTANT _SR2R-MODE-TRANSFORM-FAIL
3  CONSTANT _SR2R-MODE-FAILED-BEFORE
4  CONSTANT _SR2R-MODE-FAILED-AFTER
5  CONSTANT _SR2R-MODE-INDETERMINATE
6  CONSTANT _SR2R-MODE-CANCEL
7  CONSTANT _SR2R-MODE-CLEANUP-ERROR
8  CONSTANT _SR2R-MODE-CLEANUP-THROW
9  CONSTANT _SR2R-MODE-START-THROW
10 CONSTANT _SR2R-MODE-TRANSFORM-CANCEL
11 CONSTANT _SR2R-MODE-CANCEL-PENDING
12 CONSTANT _SR2R-MODE-MUTATE-PAYLOAD
13 CONSTANT _SR2R-MODE-POLL-THROW
14 CONSTANT _SR2R-MODE-TRANSFORM-THROW
15 CONSTANT _SR2R-MODE-PENDING-APPLIED
16 CONSTANT _SR2R-MODE-CANCEL-THROW
17 CONSTANT _SR2R-MODE-REENTER

0x535231434F504D31 CONSTANT _SR2R-OP-MARK

: _sr2r-reset-counters  ( -- )
    0 _sr2r-releases !
    0 _sr2r-starts !
    0 _sr2r-polls !
    0 _sr2r-cancels !
    0 _sr2r-cleanups !
    0 _sr2r-release-mode ! ;

: _sr2r-result!
  ( completion effect detail error result -- )
    >R
    R@ SCRR.ERROR !
    R@ SCRR.DETAIL !
    R@ SCRR.EFFECT !
    R> SCRR.COMPLETION ! ;

: _sr2r-transform-result!
  ( completion output-u detail error result -- )
    >R
    R@ STRR.ERROR !
    R@ STRR.DETAIL !
    R@ STRR.OUTPUT-U !
    R> STRR.COMPLETION ! ;

: _sr2r-release  ( payload-a payload-u context -- error )
    DROP 2DROP
    1 _sr2r-releases +!
    _sr2r-release-mode @ 1 = IF -780 EXIT THEN
    _sr2r-release-mode @ 2 = IF -781 THROW THEN
    0 ;

: _sr2r-transform  ( ingress-event output-carrier context result -- )
    _sr2r-t-result !
    DROP
    _sr2r-t-output !
    _sr2r-t-event !
    _sr2r-mode @ _SR2R-MODE-TRANSFORM-THROW = IF -760 THROW THEN
    _sr2r-mode @ _SR2R-MODE-TRANSFORM-FAIL = IF
        STREAMS-TRANSFORM-COMPLETION-FAILED 0 201 -761
        _sr2r-t-result @ _sr2r-transform-result!
        EXIT
    THEN
    _sr2r-mode @ _SR2R-MODE-TRANSFORM-CANCEL = IF
        STREAMS-TRANSFORM-COMPLETION-CANCELLED 0 202 0
        _sr2r-t-result @ _sr2r-transform-result!
        EXIT
    THEN
    _sr2r-t-event @ SEVT.PAYLOAD-U @ 3 +
        _sr2r-t-output @ SPAY.BYTE-CAP @ <= _sr2r-assert
    S" tx:"
    _sr2r-t-output @ SPAY.GENERATION @
    _sr2r-t-output @ STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-t-output @ SPAY.GENERATION @
    _sr2r-t-output @ _sr2r-t-event @
        STREAMS-EVENT-APPEND-TO-CARRIER
        STREAMS-FLOW-S-OK = _sr2r-assert
    STREAMS-TRANSFORM-COMPLETION-OK
    _sr2r-t-output @ SPAY.BYTE-U @
    0 0 _sr2r-t-result @ _sr2r-transform-result! ;

: _sr2r-check-output-event  ( event -- )
    DUP STREAMS-EVENT-VALID? _sr2r-assert
    DUP SEVT.DIRECTION @ STREAMS-EVENT-DIRECTION-EGRESS =
        _sr2r-assert
    DUP SEVT.PAYLOAD-U @ 3 >= _sr2r-assert
    _sr2r-copy-buffer
    STREAMS-RUNTIME-PROFILE-STANDARD STREAMS-RUNTIME-EGRESS-CAPACITY
    2 PICK STREAMS-EVENT-PAYLOAD-COPY
        STREAMS-FLOW-S-OK = _sr2r-assert
    DUP 3 >= _sr2r-assert
    DROP
    _sr2r-copy-buffer 3 S" tx:" COMPARE 0= _sr2r-assert
    DROP ;

: _sr2r-start  ( egress-event operation context result -- )
    _sr2r-cb-result !
    DROP
    _sr2r-cb-op !
    _sr2r-cb-event !
    1 _sr2r-starts +!
    _sr2r-cb-event @ _sr2r-check-output-event
    _SR2R-OP-MARK _sr2r-cb-op @ !
    _sr2r-mode @ _SR2R-MODE-START-THROW = IF -762 THROW THEN
    _sr2r-mode @ _SR2R-MODE-MUTATE-PAYLOAD = IF
        0 _sr2r-cb-event @ SEVT.PAYLOAD-A @
            SPAY.SEGMENTS @ SPSEG.DATA @ C!
        STREAMS-CONNECTOR-COMPLETION-DELIVERED
        STREAMS-EFFECT-APPLIED 0 0
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    _sr2r-mode @ _SR2R-MODE-PENDING =
    _sr2r-mode @ _SR2R-MODE-POLL-THROW = OR
    _sr2r-mode @ _SR2R-MODE-CANCEL-THROW = OR IF
        STREAMS-CONNECTOR-COMPLETION-PENDING
        STREAMS-EFFECT-UNCERTAIN 0 0
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    _sr2r-mode @ _SR2R-MODE-PENDING-APPLIED = IF
        STREAMS-CONNECTOR-COMPLETION-PENDING
        STREAMS-EFFECT-APPLIED 0 0
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    _sr2r-mode @ _SR2R-MODE-FAILED-BEFORE = IF
        STREAMS-CONNECTOR-COMPLETION-FAILED
        STREAMS-EFFECT-NOT-APPLIED 301 -763
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    _sr2r-mode @ _SR2R-MODE-FAILED-AFTER = IF
        STREAMS-CONNECTOR-COMPLETION-FAILED
        STREAMS-EFFECT-APPLIED 302 -764
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    _sr2r-mode @ _SR2R-MODE-INDETERMINATE = IF
        STREAMS-CONNECTOR-COMPLETION-INDETERMINATE
        STREAMS-EFFECT-UNCERTAIN 303 -765
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    _sr2r-mode @ _SR2R-MODE-REENTER = IF
        22 _sr2r-flow-b STREAMS-FLOW-STEP _sr2r-reentry-status !
    THEN
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr2r-cb-result @ _sr2r-result! ;

: _sr2r-poll  ( egress-event operation context result -- )
    _sr2r-cb-result !
    DROP
    _sr2r-cb-op !
    _sr2r-cb-event !
    1 _sr2r-polls +!
    _sr2r-cb-event @ _sr2r-check-output-event
    _sr2r-cb-op @ @ _SR2R-OP-MARK = _sr2r-assert
    _sr2r-mode @ _SR2R-MODE-POLL-THROW = IF -766 THROW THEN
    _sr2r-mode @ _SR2R-MODE-PENDING-APPLIED = IF
        STREAMS-CONNECTOR-COMPLETION-FAILED
        STREAMS-EFFECT-NOT-APPLIED 304 -767
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr2r-cb-result @ _sr2r-result! ;

: _sr2r-cancel  ( egress-event operation context result -- )
    _sr2r-cb-result !
    DROP
    _sr2r-cb-op !
    _sr2r-cb-event !
    1 _sr2r-cancels +!
    _sr2r-cb-event @ _sr2r-check-output-event
    _sr2r-cb-op @ @ _SR2R-OP-MARK = _sr2r-assert
    _sr2r-mode @ _SR2R-MODE-CANCEL-THROW = IF -768 THROW THEN
    _sr2r-mode @ _SR2R-MODE-CANCEL-PENDING = IF
        STREAMS-CONNECTOR-COMPLETION-PENDING
        STREAMS-EFFECT-UNCERTAIN 401 0
        _sr2r-cb-result @ _sr2r-result!
        EXIT
    THEN
    STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED 0 0
    _sr2r-cb-result @ _sr2r-result! ;

: _sr2r-cleanup  ( egress-event operation context -- error )
    DROP
    _sr2r-cb-op !
    _sr2r-cb-event !
    1 _sr2r-cleanups +!
    _sr2r-mode @ _SR2R-MODE-MUTATE-PAYLOAD <> IF
        _sr2r-cb-event @ _sr2r-check-output-event
    THEN
    _sr2r-cb-op @ @ _SR2R-OP-MARK = _sr2r-assert
    _sr2r-mode @ _SR2R-MODE-CLEANUP-ERROR = IF -770 EXIT THEN
    _sr2r-mode @ _SR2R-MODE-CLEANUP-THROW = IF -771 THROW THEN
    0 ;

: _sr2r-connector-identity  ( id-byte endpoint-byte connector -- )
    >R
    DUP R@ SCON.ENDPOINT-ID RID-SIZE ROT FILL
    DROP
    R> SCON.ID RID-SIZE ROT FILL ;

: _sr2r-setup-connectors  ( -- )
    _sr2r-input STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    0x11 0x21 _sr2r-input _sr2r-connector-identity
    1 _sr2r-input SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT
        _sr2r-input SCON.DIRECTION !
    101 _sr2r-input SCON.PROTOCOL !
    _sr2r-input STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-input STREAMS-CONNECTOR-VALID? _sr2r-assert

    _sr2r-output STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    0x12 0x22 _sr2r-output _sr2r-connector-identity
    1 _sr2r-output SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT
        _sr2r-output SCON.DIRECTION !
    102 _sr2r-output SCON.PROTOCOL !
    0 _sr2r-output SCON.CONTEXT !
    16 _sr2r-output SCON.OP-SIZE !
    ['] _sr2r-start _sr2r-output SCON.START-XT !
    ['] _sr2r-poll _sr2r-output SCON.POLL-XT !
    ['] _sr2r-cancel _sr2r-output SCON.CANCEL-XT !
    ['] _sr2r-cleanup _sr2r-output SCON.CLEANUP-XT !
    _sr2r-output STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-output STREAMS-CONNECTOR-VALID? _sr2r-assert ;

: _sr2r-setup-bidi  ( -- )
    _sr2r-bidi STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    0x13 0x23 _sr2r-bidi _sr2r-connector-identity
    1 _sr2r-bidi SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-BIDIRECTIONAL
        _sr2r-bidi SCON.DIRECTION !
    103 _sr2r-bidi SCON.PROTOCOL !
    16 _sr2r-bidi SCON.OP-SIZE !
    ['] _sr2r-start _sr2r-bidi SCON.START-XT !
    ['] _sr2r-poll _sr2r-bidi SCON.POLL-XT !
    ['] _sr2r-cancel _sr2r-bidi SCON.CANCEL-XT !
    ['] _sr2r-cleanup _sr2r-bidi SCON.CLEANUP-XT !
    _sr2r-bidi STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-bidi STREAMS-CONNECTOR-VALID? _sr2r-assert ;

: _sr2r-close-carrier  ( carrier -- )
    DUP _SPAY-HEADER? 0= IF DROP EXIT THEN
    DUP SPAY.STATE @ STREAMS-PAYLOAD-STATE-CLOSED = IF DROP EXIT THEN
    DUP SPAY.GENERATION @ SWAP STREAMS-PAYLOAD-CLOSE
    STREAMS-PAYLOAD-S-OK = _sr2r-assert ;

: _sr2r-payload-scratch-zero?  ( payload -- flag )
    DUP _SPAY.ARG-A @ 0=
    OVER _SPAY.ARG-U @ 0= AND
    OVER _SPAY.ARG-OFFSET @ 0= AND
    OVER _SPAY.ARG-ORIGINAL-U @ 0= AND
    SWAP _SPAY.ARG-GENERATION @ 0= AND ;

: _sr2r-init-compact-workspace  ( -- )
    _sr2r-ingress-a _sr2r-close-carrier
    _sr2r-egress-a _sr2r-close-carrier
    _sr2r-in-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2r-in-segments-a STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-out-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2r-out-segments-a STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-in-segments-a 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2r-ingress-a
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-out-segments-a 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2r-egress-a
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-ingress-a STREAMS-PAYLOAD-VALID? _sr2r-assert
    _sr2r-egress-a STREAMS-PAYLOAD-VALID? _sr2r-assert
    1 STREAMS-RUNTIME-SEGMENT-BYTES _sr2r-ingress-a
        STREAMS-PAYLOAD-UNIFORM-GEOMETRY? _sr2r-assert
    1 STREAMS-RUNTIME-SEGMENT-BYTES _sr2r-egress-a
        STREAMS-PAYLOAD-UNIFORM-GEOMETRY? _sr2r-assert ;

: _sr2r-init-standard-segments  ( bytes table -- )
    >R
    DUP STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    DUP STREAMS-RUNTIME-SEGMENT-BYTES +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-SIZE +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    DUP STREAMS-RUNTIME-SEGMENT-BYTES 2 * +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-SIZE 2 * +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    STREAMS-RUNTIME-SEGMENT-BYTES 3 * +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R> STREAMS-PAYLOAD-SEGMENT-SIZE 3 * +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2r-assert ;

: _sr2r-init-standard-workspace  ( -- )
    _sr2r-ingress-b _sr2r-close-carrier
    _sr2r-egress-b _sr2r-close-carrier
    _sr2r-in-bytes-b _sr2r-in-segments-b _sr2r-init-standard-segments
    _sr2r-out-bytes-b _sr2r-out-segments-b _sr2r-init-standard-segments
    _sr2r-in-segments-b 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2r-ingress-b
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-out-segments-b 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2r-egress-b
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-ingress-b STREAMS-PAYLOAD-VALID? _sr2r-assert
    _sr2r-egress-b STREAMS-PAYLOAD-VALID? _sr2r-assert
    4 STREAMS-RUNTIME-SEGMENT-BYTES _sr2r-ingress-b
        STREAMS-PAYLOAD-UNIFORM-GEOMETRY? _sr2r-assert
    4 STREAMS-RUNTIME-SEGMENT-BYTES _sr2r-egress-b
        STREAMS-PAYLOAD-UNIFORM-GEOMETRY? _sr2r-assert ;

: _sr2r-bind-workspace  ( flow -- status )
    DUP _sr2r-flow-a = IF
        DROP
        _sr2r-init-compact-workspace
        STREAMS-RUNTIME-PROFILE-COMPACT
        _sr2r-ingress-a _sr2r-egress-a
        _sr2r-operation-a
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2r-flow-a STREAMS-FLOW-WORKSPACE! EXIT
    THEN
    DROP
    _sr2r-init-standard-workspace
    STREAMS-RUNTIME-PROFILE-STANDARD
    _sr2r-ingress-b _sr2r-egress-b
    _sr2r-operation-b
    STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-OPERATION-CAPACITY
    _sr2r-flow-b STREAMS-FLOW-WORKSPACE! ;

: _sr2r-configure-flow  ( id-byte timeout-ms flow -- status )
    _sr2r-build-flow !
    _sr2r-build-timeout !
    _sr2r-build-tag !
    _sr2r-build-flow @ STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-build-flow @ _sr2r-bind-workspace
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-build-flow @ SFLOW.ID RID-SIZE
        _sr2r-build-tag @ FILL
    7 _sr2r-build-flow @ SFLOW.REVISION !
    _sr2r-build-timeout @ _sr2r-build-flow @ SFLOW.TIMEOUT-MS !
    _sr2r-input _sr2r-build-flow @ SFLOW.INPUT-CONNECTOR !
    _sr2r-output _sr2r-build-flow @ SFLOW.OUTPUT-CONNECTOR !
    ['] _sr2r-transform _sr2r-build-flow @ SFLOW.TRANSFORM-XT !
    0 _sr2r-build-flow @ SFLOW.TRANSFORM-CONTEXT !
    201 _sr2r-build-flow @ SFLOW.OUTPUT-MEDIA !
    _sr2r-build-flow @ STREAMS-FLOW-SEAL ;

: _sr2r-setup-flow  ( id-byte flow -- )
    >R 100 R> _sr2r-configure-flow
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-build-flow @ STREAMS-FLOW-VALID? _sr2r-assert ;

: _sr2r-event-header  ( tag event -- )
    _sr2r-build-event !
    _sr2r-build-tag !
    _sr2r-build-event @ STREAMS-EVENT-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-build-event @ SEVT.EVENT-ID RID-SIZE
        _sr2r-build-tag @ FILL
    _sr2r-build-event @ SEVT.CORRELATION-ID RID-SIZE
        _sr2r-build-tag @ 1+ FILL
    _sr2r-build-event @ SEVT.IDEMPOTENCY-ID RID-SIZE
        _sr2r-build-tag @ 2 + FILL
    _sr2r-build-event @ SEVT.ORIGIN-ID RID-SIZE
        _sr2r-build-tag @ 3 + FILL
    _sr2r-build-event @ SEVT.DESTINATION-ID RID-SIZE
        _sr2r-build-tag @ 4 + FILL
    301 _sr2r-build-event @ SEVT.MEDIA !
    _sr2r-build-tag @ _sr2r-build-event @ SEVT.SEQUENCE !
    0 _sr2r-build-event @ SEVT.RECEIVED-MS ! ;

: _sr2r-event-routing  ( event -- )
    >R
    _sr2r-input SCON.ID R@ SEVT.CONNECTOR-ID RID-COPY
    _sr2r-flow-a SFLOW.ID R@ SEVT.FLOW-ID RID-COPY
    _sr2r-input SCON.ENDPOINT-ID R@ SEVT.ORIGIN-ID RID-COPY
    _sr2r-flow-a SFLOW.ID R@ SEVT.DESTINATION-ID RID-COPY
    _sr2r-input SCON.REVISION @ R@ SEVT.CONNECTOR-REVISION !
    STREAMS-EVENT-DIRECTION-INGRESS R@ SEVT.DIRECTION !
    _sr2r-input SCON.PROTOCOL @ R> SEVT.PROTOCOL ! ;

: _sr2r-egress-routing  ( event -- )
    >R
    _sr2r-output SCON.ID R@ SEVT.CONNECTOR-ID RID-COPY
    _sr2r-flow-a SFLOW.ID R@ SEVT.FLOW-ID RID-COPY
    _sr2r-output SCON.ENDPOINT-ID R@ SEVT.DESTINATION-ID RID-COPY
    _sr2r-output SCON.REVISION @ R@ SEVT.CONNECTOR-REVISION !
    STREAMS-EVENT-DIRECTION-EGRESS R@ SEVT.DIRECTION !
    _sr2r-output SCON.PROTOCOL @ R@ SEVT.PROTOCOL !
    _sr2r-flow-a SFLOW.OUTPUT-MEDIA @ R> SEVT.MEDIA ! ;

: _sr2r-build-egress-metadata  ( payload-a payload-u tag event -- )
    >R
    R@ _sr2r-event-header
    R@ _sr2r-egress-routing
    R> SEVT.PAYLOAD-DIGEST SHA3-256-HASH ;

: _sr2r-build-borrowed
  ( payload-a payload-u tag event flow -- status )
    _sr2r-build-flow !
    _sr2r-build-event !
    _sr2r-build-tag !
    _sr2r-build-u !
    _sr2r-build-a !
    _sr2r-build-tag @ _sr2r-build-event @ _sr2r-event-header
    _sr2r-build-a @ _sr2r-build-u @ _sr2r-build-event @
        STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-input _sr2r-build-event @ _sr2r-build-flow @
        STREAMS-FLOW-SEAL-INGRESS ;

: _sr2r-build-owned
  ( payload-a payload-u tag event flow -- status )
    _sr2r-build-flow !
    _sr2r-build-event !
    _sr2r-build-tag !
    _sr2r-build-u !
    _sr2r-build-a !
    _sr2r-build-tag @ _sr2r-build-event @ _sr2r-event-header
    _sr2r-build-a @ _sr2r-build-u @
    ['] _sr2r-release _sr2r-build-tag @ _sr2r-build-event @
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-input _sr2r-build-event @ _sr2r-build-flow @
        STREAMS-FLOW-SEAL-INGRESS ;

: _sr2r-to-output-ready  ( -- )
    11 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @
        STREAMS-FLOW-STATE-OUTPUT-READY = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACCEPTED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-EVENT SEVT.CORRELATION-ID
    _sr2r-flow-a SFLOW.EGRESS-EVENT SEVT.CORRELATION-ID
        RID= _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-EVENT SEVT.IDEMPOTENCY-ID
    _sr2r-flow-a SFLOW.EGRESS-EVENT SEVT.IDEMPOTENCY-ID
        RID= _sr2r-assert ;

: _sr2r-new-a  ( mode -- )
    _sr2r-mode !
    _sr2r-reset-counters
    0x31 _sr2r-flow-a _sr2r-setup-flow
    S" ping" 0x41 _sr2r-event-a _sr2r-flow-a
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a 7 10 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert ;

: _sr2r-retire-a  ( -- )
    _sr2r-flow-a SFLOW.GENERATION @ _sr2r-flow-a
        STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr2r-assert ;

: _sr2r-test-connector-directions  ( -- )
    _sr2r-setup-bidi

    _sr2r-bad STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    0x14 0x24 _sr2r-bad _sr2r-connector-identity
    1 _sr2r-bad SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT _sr2r-bad SCON.DIRECTION !
    104 _sr2r-bad SCON.PROTOCOL !
    16 _sr2r-bad SCON.OP-SIZE !
    ['] _sr2r-start _sr2r-bad SCON.START-XT !
    ['] _sr2r-poll _sr2r-bad SCON.POLL-XT !
    ['] _sr2r-cancel _sr2r-bad SCON.CANCEL-XT !
    ['] _sr2r-cleanup _sr2r-bad SCON.CLEANUP-XT !
    _sr2r-bad STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-bad STREAMS-CONNECTOR-VALID? 0= _sr2r-assert

    _sr2r-bad STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    0x15 0x25 _sr2r-bad _sr2r-connector-identity
    1 _sr2r-bad SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT _sr2r-bad SCON.DIRECTION !
    105 _sr2r-bad SCON.PROTOCOL !
    _sr2r-bad STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-bad STREAMS-CONNECTOR-VALID? 0= _sr2r-assert
    _sr2r-stack ;

: _sr2r-output-with-op-size  ( operation-bytes -- status )
    >R
    _sr2r-bad STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    0x16 0x26 _sr2r-bad _sr2r-connector-identity
    1 _sr2r-bad SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT _sr2r-bad SCON.DIRECTION !
    106 _sr2r-bad SCON.PROTOCOL !
    R> _sr2r-bad SCON.OP-SIZE !
    ['] _sr2r-start _sr2r-bad SCON.START-XT !
    ['] _sr2r-poll _sr2r-bad SCON.POLL-XT !
    ['] _sr2r-cancel _sr2r-bad SCON.CANCEL-XT !
    ['] _sr2r-cleanup _sr2r-bad SCON.CLEANUP-XT !
    _sr2r-bad STREAMS-CONNECTOR-SEAL ;

: _sr2r-test-exact-bounds  ( -- )
    STREAMS-CONNECTOR-SIZE 168 = _sr2r-assert
    STREAMS-EVENT-SIZE 376 = _sr2r-assert
    STREAMS-ATTEMPT-SIZE 304 = _sr2r-assert
    STREAMS-PAYLOAD-SIZE 224 = _sr2r-assert
    STREAMS-FLOW-SIZE 1904 = _sr2r-assert
    STREAMS-EXECUTION-ENTRY-SIZE 96 = _sr2r-assert
    STREAMS-EXECUTION-POOL-SIZE 136 = _sr2r-assert
    STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES
        10848 = _sr2r-assert
    STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES
        35824 = _sr2r-assert
    136 96 2 * +
    10848 +
    35824 + 47000 = _sr2r-assert
    STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr2r-output-with-op-size
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-bad STREAMS-CONNECTOR-VALID? _sr2r-assert
    4097 _sr2r-output-with-op-size
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-bad STREAMS-CONNECTOR-VALID? _sr2r-assert
    0 _sr2r-output-with-op-size
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-bad STREAMS-CONNECTOR-VALID? 0= _sr2r-assert

    0x33 0 _sr2r-flow-b _sr2r-configure-flow
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    0x33 STREAMS-FLOW-TIMEOUT-MAX-MS 1+
        _sr2r-flow-b _sr2r-configure-flow
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    0x33 STREAMS-FLOW-TIMEOUT-MAX-MS
        _sr2r-flow-b _sr2r-configure-flow
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-b STREAMS-FLOW-VALID? _sr2r-assert

    S" edge" 0x3F _sr2r-event-c _sr2r-flow-b
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-c 7
        _SFLOW-CELL-MAX STREAMS-FLOW-TIMEOUT-MAX-MS - 1+
        _sr2r-flow-b STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-CAPACITY = _sr2r-assert
    _sr2r-event-c STREAMS-EVENT-VALID? _sr2r-assert
    _sr2r-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert

    0x40 _sr2r-event-a _sr2r-event-header
    _sr2r-large-payload
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-INGRESS-CAPACITY 1+
        _sr2r-event-a STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-profile-bounds-and-large-body  ( -- )
    _SR2R-MODE-DELIVER _sr2r-mode !
    _sr2r-reset-counters
    _sr2r-large-payload
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-INGRESS-CAPACITY 0x78 FILL
    0x33 _sr2r-flow-b _sr2r-setup-flow
    _sr2r-large-payload
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-INGRESS-CAPACITY
        0x40 _sr2r-event-a _sr2r-flow-b _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a 7 10 _sr2r-flow-b STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    1 11 _sr2r-flow-b STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    1 _sr2r-flow-b STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr2r-assert

    0x33 _sr2r-flow-b _sr2r-setup-flow
    0x41 _sr2r-event-b _sr2r-event-header
    _sr2r-large-payload
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-RUNTIME-INGRESS-CAPACITY 1+
        _sr2r-event-b STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-input _sr2r-event-b _sr2r-flow-b STREAMS-FLOW-SEAL-INGRESS
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b 7 10 _sr2r-flow-b STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-CAPACITY = _sr2r-assert
    _sr2r-event-b STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert

    0x33 _sr2r-flow-b _sr2r-setup-flow
    _sr2r-large-payload 8192
        0x42 _sr2r-event-c _sr2r-flow-b _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-c 7 20 _sr2r-flow-b STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    21 _sr2r-flow-b STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr2r-assert
    _sr2r-flow-b SFLOW.EGRESS-EVENT SEVT.PAYLOAD-U @ 8195 =
        _sr2r-assert
    22 _sr2r-flow-b STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    1 _sr2r-flow-b STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-event-binding-rollback  ( -- )
    _sr2r-reset-counters

    0x49 _sr2r-event-c _sr2r-event-header
    S" ping" ['] _sr2r-release 0x49 _sr2r-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-OK = _sr2r-assert
    S" pong" ['] _sr2r-release 0x4A _sr2r-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    S" pong" _sr2r-event-c STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-event-c SEVT.RELEASE-CONTEXT @ 0x49 =
        _sr2r-assert
    _sr2r-event-c STREAMS-EVENT-SEAL
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-releases @ 1 = _sr2r-assert
    _sr2r-event-c SEVT.STATE @ _SEVT-STATE-CLOSED =
        _sr2r-assert
    _sr2r-event-c SEVT.PAYLOAD-A @ 0= _sr2r-assert
    _sr2r-event-c SEVT.RELEASE-XT @ 0= _sr2r-assert
    _sr2r-event-c SEVT.RELEASE-CONTEXT @ 0= _sr2r-assert
    _sr2r-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-releases @ 1 = _sr2r-assert

    0x4B _sr2r-event-c _sr2r-event-header
    S" ping" _sr2r-event-c STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-OK = _sr2r-assert
    S" pong" ['] _sr2r-release 0x4B _sr2r-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-releases @ 1 = _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-event-lifecycle-and-full  ( -- )
    _sr2r-reset-counters
    0x31 _sr2r-flow-a _sr2r-setup-flow

    S" ping" 0x42 _sr2r-event-a _sr2r-flow-a
        _sr2r-build-owned
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-VALID? _sr2r-assert
    _sr2r-event-a 7 10 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-releases @ 1 = _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-releases @ 1 = _sr2r-assert

    S" pong" 0x43 _sr2r-event-b _sr2r-flow-a
        _sr2r-build-owned
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b 7 11 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-FULL = _sr2r-assert
    _sr2r-releases @ 1 = _sr2r-assert
    _sr2r-event-b STREAMS-EVENT-VALID? _sr2r-assert
    _sr2r-event-b STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-releases @ 2 = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACCEPTED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert
    _sr2r-flow-a SFLOW.GENERATION @ 12 _sr2r-flow-a
        STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-retire-a

    0x49 _sr2r-event-c _sr2r-event-header
    0 0 0 0 _sr2r-event-c STREAMS-EVENT-OWN
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    0 0 ['] _sr2r-release 0x49 _sr2r-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-input _sr2r-event-c _sr2r-flow-a
        STREAMS-FLOW-SEAL-INGRESS
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-c 7 13 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-releases @ 3 = _sr2r-assert
    2 14 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-owned-cleanup-failures  ( -- )
    _sr2r-reset-counters
    0x31 _sr2r-flow-a _sr2r-setup-flow
    1 _sr2r-release-mode !
    S" ping" 0x44 _sr2r-event-a _sr2r-flow-a
        _sr2r-build-owned
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a 7 10 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-CLEANUP = _sr2r-assert
    _sr2r-releases @ 1 = _sr2r-assert
    _sr2r-event-a SEVT.STATE @ _SEVT-STATE-CLEANUP-FAILED =
        _sr2r-assert
    _sr2r-event-a SEVT.CLEANUP-ERROR @ -780 = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert

    2 _sr2r-release-mode !
    S" pong" 0x45 _sr2r-event-b _sr2r-flow-a
        _sr2r-build-owned
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b 7 11 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-CLEANUP = _sr2r-assert
    _sr2r-releases @ 2 = _sr2r-assert
    _sr2r-event-b SEVT.CLEANUP-ERROR @ -781 = _sr2r-assert
    0 _sr2r-release-mode !
    _sr2r-stack ;

: _sr2r-test-happy-retire-reuse  ( -- )
    _SR2R-MODE-DELIVER _sr2r-new-a
    _sr2r-to-output-ready
    _sr2r-copy-buffer
    STREAMS-RUNTIME-PROFILE-COMPACT STREAMS-RUNTIME-EGRESS-CAPACITY
    _sr2r-flow-a SFLOW.EGRESS-EVENT STREAMS-EVENT-PAYLOAD-COPY
        STREAMS-FLOW-S-OK = _sr2r-assert
    DUP 7 = _sr2r-assert
    _sr2r-copy-buffer SWAP S" tx:ping" COMPARE 0= _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr2r-assert
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    _sr2r-starts @ 1 = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-DELIVERED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT STREAMS-ATTEMPT-VALID?
        _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT STREAMS-ATTEMPT-VALID?
        _sr2r-assert
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    _sr2r-flow-a SFLOW.GENERATION @ 14 _sr2r-flow-a
        STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    _sr2r-starts @ 1 = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-CARRIER SPAY.STATE @
        STREAMS-PAYLOAD-STATE-SEALED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-CARRIER SPAY.STATE @
        STREAMS-PAYLOAD-STATE-SEALED = _sr2r-assert
    0 _sr2r-copy-buffer 7
        _sr2r-flow-a SFLOW.EGRESS-CARRIER SPAY.GENERATION @
        _sr2r-flow-a SFLOW.EGRESS-CARRIER STREAMS-PAYLOAD-READ
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-copy-buffer 7 S" tx:ping" COMPARE 0= _sr2r-assert
    _sr2r-flow-a SFLOW.GENERATION @ 1+
        _sr2r-flow-a STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-STALE = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-TERMINAL =
        _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-CARRIER SPAY.GENERATION @
        _sr2r-flow-a SFLOW.EGRESS-CARRIER
        STREAMS-PAYLOAD-EXACT? _sr2r-assert
    _sr2r-retire-a
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-CARRIER SPAY.STATE @
        STREAMS-PAYLOAD-STATE-BUILDING = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-CARRIER SPAY.STATE @
        STREAMS-PAYLOAD-STATE-BUILDING = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-CARRIER SPAY.BYTE-U @ 0=
        _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-CARRIER SPAY.BYTE-U @ 0=
        _sr2r-assert
    _sr2r-in-segments-a SPSEG.USED @ 0= _sr2r-assert
    _sr2r-out-segments-a SPSEG.USED @ 0= _sr2r-assert
    _sr2r-in-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _SPAY-ZERO? _sr2r-assert
    _sr2r-out-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _SPAY-ZERO? _sr2r-assert
    _sr2r-operation-a
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-OPERATION-CAPACITY
        _SPAY-ZERO? _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert

    S" pong" 0x46 _sr2r-event-b _sr2r-flow-a
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b 7 20 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-a SFLOW.GENERATION @ 2 = _sr2r-assert
    2 21 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-pending-delivery  ( -- )
    _SR2R-MODE-PENDING _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-DELIVERING =
        _sr2r-assert
    _sr2r-cleanups @ 0= _sr2r-assert
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    _sr2r-starts @ 1 = _sr2r-assert
    _sr2r-polls @ 1 = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-transform-failures  ( -- )
    _SR2R-MODE-TRANSFORM-FAIL _sr2r-new-a
    11 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-BEFORE = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-NOT-APPLIED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert
    _sr2r-starts @ 0= _sr2r-assert
    _sr2r-cleanups @ 0= _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-TRANSFORM-CANCEL _sr2r-new-a
    11 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-CANCELLED = _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-TRANSFORM-THROW _sr2r-new-a
    11 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-CALLBACK = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.ERROR @ -760 =
        _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-run-output-outcome
  ( mode expected-status expected-state expected-effect -- )
    _sr2r-expected-effect !
    _sr2r-expected-state !
    _sr2r-expected-status !
    _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        _sr2r-expected-status @ = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        _sr2r-expected-state @ =
        _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        _sr2r-expected-effect @ =
        _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-mode @ _SR2R-MODE-MUTATE-PAYLOAD = IF
        _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.CLEANUP-ERROR @
            STREAMS-FLOW-E-PAYLOAD-CHANGED = _sr2r-assert
    THEN
    _sr2r-retire-a ;

: _sr2r-test-output-effect-truth  ( -- )
    _SR2R-MODE-FAILED-BEFORE
    STREAMS-FLOW-S-FAILED
    STREAMS-ATTEMPT-STATE-FAILED-BEFORE
    STREAMS-EFFECT-NOT-APPLIED _sr2r-run-output-outcome

    _SR2R-MODE-FAILED-AFTER
    STREAMS-FLOW-S-FAILED
    STREAMS-ATTEMPT-STATE-FAILED-AFTER
    STREAMS-EFFECT-APPLIED _sr2r-run-output-outcome

    _SR2R-MODE-INDETERMINATE
    STREAMS-FLOW-S-INDETERMINATE
    STREAMS-ATTEMPT-STATE-INDETERMINATE
    STREAMS-EFFECT-UNCERTAIN _sr2r-run-output-outcome

    _SR2R-MODE-MUTATE-PAYLOAD
    STREAMS-FLOW-S-INDETERMINATE
    STREAMS-ATTEMPT-STATE-INDETERMINATE
    STREAMS-EFFECT-UNCERTAIN _sr2r-run-output-outcome

    _SR2R-MODE-PENDING-APPLIED _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr2r-assert
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-AFTER = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -767 =
        _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-cancellation  ( -- )
    _SR2R-MODE-CANCEL _sr2r-new-a
    1 11 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-CANCELLED = _sr2r-assert
    _sr2r-cancels @ 0= _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-CANCEL _sr2r-new-a
    _sr2r-to-output-ready
    1 12 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-CANCELLED = _sr2r-assert
    _sr2r-cancels @ 0= _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-PENDING _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    1 13 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-cancels @ 1 = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-CANCEL-THROW _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    1 13 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-UNCERTAIN = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-CALLBACK = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -768 =
        _sr2r-assert
    _sr2r-cancels @ 1 = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-PENDING _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    _SR2R-MODE-CANCEL-PENDING _sr2r-mode !
    1 13 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-UNCERTAIN = _sr2r-assert
    _sr2r-cancels @ 1 = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-timeout  ( -- )
    _SR2R-MODE-CANCEL _sr2r-new-a
    110 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-TIMEOUT = _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-PENDING _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    110 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-cancels @ 1 = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-stale  ( -- )
    _sr2r-reset-counters
    0x31 _sr2r-flow-a _sr2r-setup-flow
    S" ping" 0x47 _sr2r-event-a _sr2r-flow-a
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    2 _sr2r-event-a SEVT.CONNECTOR-REVISION !
    _sr2r-event-a 7 10 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-STALE = _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-VALID? _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert

    S" pong" 0x48 _sr2r-event-b _sr2r-flow-a
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b 7 11 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    2 _sr2r-input SCON.REVISION !
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-STALE = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-STALE = _sr2r-assert
    1 _sr2r-input SCON.REVISION !
    _sr2r-retire-a

    _SR2R-MODE-PENDING _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    2 _sr2r-output SCON.REVISION !
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-UNCERTAIN = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-STALE = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    1 _sr2r-output SCON.REVISION !
    _sr2r-retire-a

    _SR2R-MODE-PENDING-APPLIED _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    2 _sr2r-output SCON.REVISION !
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-AFTER = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-STALE = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    1 _sr2r-output SCON.REVISION !
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-cleanup-and-throws  ( -- )
    _SR2R-MODE-CLEANUP-ERROR _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CLEANUP = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-DELIVERED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.CLEANUP-ERROR @ -770 =
        _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CLEANUP = _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-CLEANUP-THROW _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CLEANUP = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.CLEANUP-ERROR @ -771 =
        _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-START-THROW _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -762 =
        _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-POLL-THROW _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-INDETERMINATE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -766 =
        _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-segmented-carriers  ( -- )
    _sr2r-init-compact-workspace
    _sr2r-large-payload
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY 0x61 FILL
    _sr2r-ingress-a SPAY.GENERATION @
        _sr2r-ingress-a STREAMS-PAYLOAD-RESET
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation !
    _sr2r-large-payload
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY
        _sr2r-carrier-generation @
        _sr2r-ingress-a STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-large-payload 1 _sr2r-carrier-generation @
        _sr2r-ingress-a STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-CAPACITY = _sr2r-assert
    _sr2r-ingress-a SPAY.BYTE-U @
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY = _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-a STREAMS-PAYLOAD-SEAL
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-a
        STREAMS-PAYLOAD-EXACT? _sr2r-assert
    _sr2r-copy-buffer
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY
        _sr2r-carrier-generation @
        _sr2r-ingress-a STREAMS-PAYLOAD-COPY
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-RUNTIME-INGRESS-CAPACITY = _sr2r-assert
    0 _sr2r-ingress-a SPAY.SEGMENTS @ SPSEG.DATA @ C!
    _sr2r-carrier-generation @ _sr2r-ingress-a
        STREAMS-PAYLOAD-EXACT? 0= _sr2r-assert
    _sr2r-ingress-a STREAMS-PAYLOAD-BOUND? _sr2r-assert
    _sr2r-ingress-a STREAMS-PAYLOAD-VALID? 0= _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-a STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-INTEGRITY = _sr2r-assert
    _sr2r-ingress-a SPAY.STATE @ STREAMS-PAYLOAD-STATE-CLOSED =
        _sr2r-assert
    _sr2r-ingress-a SPAY.SEGMENTS @ SPSEG.DATA @ C@ 0= _sr2r-assert

    _sr2r-init-standard-workspace
    _sr2r-ingress-b SPAY.GENERATION @
        _sr2r-ingress-b STREAMS-PAYLOAD-RESET
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation !
    _sr2r-large-payload 8192
        _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-ingress-b SPAY.SEGMENTS @ SPSEG.USED @
        STREAMS-RUNTIME-SEGMENT-BYTES = _sr2r-assert
    _sr2r-ingress-b SPAY.SEGMENTS @ STREAMS-PAYLOAD-SEGMENT-SIZE +
        SPSEG.USED @ STREAMS-RUNTIME-SEGMENT-BYTES = _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b STREAMS-PAYLOAD-SEAL
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-EXACT? _sr2r-assert

    _sr2r-copy-buffer 8191
        _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-COPY
        STREAMS-PAYLOAD-S-CAPACITY = _sr2r-assert
    0= _sr2r-assert
    _sr2r-ingress-b _sr2r-payload-scratch-zero? _sr2r-assert
    _sr2r-ingress-b SPAY.BUSY @ 0= _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-EXACT? _sr2r-assert

    _sr2r-copy-buffer -1
        _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-COPY
        STREAMS-PAYLOAD-S-INVALID = _sr2r-assert
    0= _sr2r-assert
    _sr2r-ingress-b _sr2r-payload-scratch-zero? _sr2r-assert
    _sr2r-ingress-b SPAY.BUSY @ 0= _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-EXACT? _sr2r-assert

    0 _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-DIGEST
        STREAMS-PAYLOAD-S-INVALID = _sr2r-assert
    _sr2r-ingress-b _sr2r-payload-scratch-zero? _sr2r-assert
    _sr2r-ingress-b SPAY.BUSY @ 0= _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-EXACT? _sr2r-assert
    -16 _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-DIGEST
        STREAMS-PAYLOAD-S-INVALID = _sr2r-assert
    _sr2r-ingress-b _sr2r-payload-scratch-zero? _sr2r-assert
    _sr2r-ingress-b SPAY.BUSY @ 0= _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-EXACT? _sr2r-assert

    _sr2r-carrier-generation @ _sr2r-ingress-b STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2r-assert

    _sr2r-ingress-b SPAY.GENERATION @
        _sr2r-ingress-b STREAMS-PAYLOAD-RESET
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation !
    _sr2r-large-payload 5000
        _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-large-payload 5000
        _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    5000 _sr2r-ingress-b _SPAY.ARG-OFFSET !
    23 _sr2r-ingress-b _SPAY.ARG-U !
    29 _sr2r-ingress-b _SPAY.ARG-ORIGINAL-U !
    _sr2r-large-payload _sr2r-ingress-b _SPAY.ARG-A !
    _sr2r-carrier-generation @
        _sr2r-ingress-b _SPAY.ARG-GENERATION !
    -1 _sr2r-ingress-b SPAY.BUSY !
    _sr2r-ingress-a _sr2r-ingress-b STREAMS-PAYLOAD-S-INVALID
        _SPAY-ROLLBACK-APPEND-PAYLOAD
        STREAMS-PAYLOAD-S-INVALID = _sr2r-assert
    _sr2r-ingress-b SPAY.BYTE-U @ 5000 = _sr2r-assert
    _sr2r-ingress-b SPAY.SEGMENTS @ SPSEG.USED @ 4096 =
        _sr2r-assert
    _sr2r-ingress-b SPAY.SEGMENTS @ STREAMS-PAYLOAD-SEGMENT-SIZE +
        SPSEG.USED @ 904 = _sr2r-assert
    _sr2r-ingress-b SPAY.SEGMENTS @ STREAMS-PAYLOAD-SEGMENT-SIZE 2 * +
        SPSEG.USED @ 0= _sr2r-assert
    _sr2r-ingress-b SPAY.SEGMENTS @ STREAMS-PAYLOAD-SEGMENT-SIZE 3 * +
        SPSEG.USED @ 0= _sr2r-assert
    _sr2r-in-bytes-b 5000 + 5000 _SPAY-ZERO? _sr2r-assert
    _sr2r-ingress-b _sr2r-payload-scratch-zero? _sr2r-assert
    _sr2r-ingress-b SPAY.BUSY @ 0= _sr2r-assert
    _sr2r-ingress-b STREAMS-PAYLOAD-VALID? _sr2r-assert
    S" tail" _sr2r-carrier-generation @
        _sr2r-ingress-b STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-ingress-b SPAY.BYTE-U @ 5004 = _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-carrier-binding  ( -- )
    0x31 _sr2r-flow-a _sr2r-setup-flow
    _sr2r-ingress-a SPAY.BINDING-EPOCH @ _sr2r-binding-epoch !
    _sr2r-ingress-a SPAY.GENERATION @ _sr2r-carrier-generation !
    _sr2r-ingress-a SPAY.GENERATION @ _sr2r-ingress-a
        STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-in-segments-a 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2r-ingress-a
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-ingress-a SPAY.GENERATION @
        _sr2r-carrier-generation @ = _sr2r-assert
    _sr2r-ingress-a SPAY.BINDING-EPOCH @
        _sr2r-binding-epoch @ 1+ = _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? 0= _sr2r-assert

    _sr2r-large-payload
        _sr2r-in-segments-a SPSEG.DATA !
    _sr2r-ingress-a STREAMS-PAYLOAD-BOUND? 0= _sr2r-assert
    _sr2r-in-bytes-a
        _sr2r-in-segments-a SPSEG.DATA !
    _sr2r-ingress-a STREAMS-PAYLOAD-BOUND? _sr2r-assert

    _sr2r-ingress-a SPAY.GENERATION @ _sr2r-ingress-a
        STREAMS-PAYLOAD-RESET
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation !
    S" ping" _sr2r-carrier-generation @
        _sr2r-ingress-a STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-a STREAMS-PAYLOAD-SEAL
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    0x64 _sr2r-event-a _sr2r-event-header
    _sr2r-event-a _sr2r-event-routing
    _sr2r-ingress-a _sr2r-event-a STREAMS-EVENT-CARRIER
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-SEAL
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-VALID? _sr2r-assert
    _sr2r-event-a SEVT.RELEASE-CONTEXT @
        _sr2r-ingress-a SPAY.BINDING-EPOCH @ = _sr2r-assert
    _sr2r-ingress-a SPAY.BINDING-EPOCH @ _sr2r-binding-epoch !
    _sr2r-ingress-a SPAY.GENERATION @ _sr2r-carrier-generation !
    _sr2r-ingress-a SPAY.GENERATION @ _sr2r-ingress-a
        STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-in-segments-a 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2r-ingress-a
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-ingress-a SPAY.GENERATION @
        _sr2r-carrier-generation @ = _sr2r-assert
    _sr2r-ingress-a SPAY.BINDING-EPOCH @
        _sr2r-binding-epoch @ 1+ = _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-VALID? 0= _sr2r-assert
    _sr2r-event-a STREAMS-EVENT-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-ingress-a SPAY.GENERATION @ _sr2r-ingress-a
        STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-alias-preflights  ( -- )
    _sr2r-init-standard-workspace
    _sr2r-ingress-b SPAY.GENERATION @
        _sr2r-ingress-b STREAMS-PAYLOAD-RESET
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation !
    S" payload" _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-APPEND
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b STREAMS-PAYLOAD-SEAL
        STREAMS-PAYLOAD-S-OK = _sr2r-assert

    0 _sr2r-ingress-b 1 _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-READ
        STREAMS-PAYLOAD-S-INVALID = _sr2r-assert
    _sr2r-ingress-b STREAMS-RUNTIME-SEGMENT-BYTES
        _sr2r-carrier-generation @ _sr2r-ingress-b STREAMS-PAYLOAD-COPY
        STREAMS-PAYLOAD-S-INVALID = _sr2r-assert
    0= _sr2r-assert
    _sr2r-ingress-b _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-DIGEST
        STREAMS-PAYLOAD-S-INVALID = _sr2r-assert
    _sr2r-ingress-b _sr2r-payload-scratch-zero? _sr2r-assert
    _sr2r-ingress-b SPAY.BUSY @ 0= _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b
        STREAMS-PAYLOAD-EXACT? _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-b STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2r-assert

    0x31 _sr2r-flow-a _sr2r-setup-flow
    S" ping" 0x65 _sr2r-event-b _sr2r-flow-a
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b 4 _sr2r-event-b STREAMS-EVENT-PAYLOAD-COPY
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    0= _sr2r-assert
    _sr2r-event-b STREAMS-EVENT-VALID? _sr2r-assert
    _sr2r-event-b STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr2r-assert

    _sr2r-ingress-a _sr2r-close-carrier
    _sr2r-event-c STREAMS-EVENT-SIZE
        _sr2r-in-segments-a STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-in-segments-a 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr2r-ingress-a
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-ingress-a SPAY.GENERATION @ _sr2r-ingress-a
        STREAMS-PAYLOAD-RESET
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-carrier-generation !
    _sr2r-carrier-generation @ _sr2r-ingress-a STREAMS-PAYLOAD-SEAL
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    0x66 _sr2r-event-c _sr2r-event-header
    _sr2r-event-c _sr2r-event-routing
    _sr2r-ingress-a _sr2r-event-c STREAMS-EVENT-CARRIER
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-event-c SEVT.OWNERSHIP @ 0= _sr2r-assert
    _sr2r-carrier-generation @ _sr2r-ingress-a STREAMS-PAYLOAD-CLOSE
        STREAMS-PAYLOAD-S-OK = _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-between-call-tamper  ( -- )
    _SR2R-MODE-DELIVER _sr2r-new-a
    0 _sr2r-flow-a SFLOW.INGRESS-CARRIER
        SPAY.SEGMENTS @ SPSEG.DATA @ C!
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    11 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-BEFORE = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.ERROR @
        STREAMS-FLOW-E-PAYLOAD-CHANGED = _sr2r-assert
    _sr2r-starts @ 0= _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-PENDING _sr2r-new-a
    _sr2r-to-output-ready
    0 _sr2r-flow-a SFLOW.EGRESS-CARRIER
        SPAY.SEGMENTS @ SPSEG.DATA @ C!
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-BEFORE = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @
        STREAMS-FLOW-E-PAYLOAD-CHANGED = _sr2r-assert
    _sr2r-starts @ 0= _sr2r-assert
    _sr2r-retire-a

    _SR2R-MODE-PENDING _sr2r-new-a
    _sr2r-to-output-ready
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr2r-assert
    0 _sr2r-flow-a SFLOW.EGRESS-CARRIER
        SPAY.SEGMENTS @ SPSEG.DATA @ C!
    _SR2R-MODE-MUTATE-PAYLOAD _sr2r-mode !
    13 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-INDETERMINATE = _sr2r-assert
    _sr2r-polls @ 0= _sr2r-assert
    _sr2r-cleanups @ 1 = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @
        STREAMS-FLOW-E-PAYLOAD-CHANGED = _sr2r-assert
    _sr2r-retire-a
    _sr2r-stack ;

: _sr2r-test-direct-ingress  ( -- )
    _sr2r-reset-counters
    _SR2R-MODE-DELIVER _sr2r-mode !
    0x31 _sr2r-flow-a _sr2r-setup-flow

    0x61 _sr2r-event-a _sr2r-event-header
    _sr2r-input _sr2r-event-a 8 7 10 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    DUP 1 = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-event-a _SEVT-UNBOUND-METADATA? _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-RECEIVING =
        _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert

    S" ping" _sr2r-reservation-generation @ 11 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-APPEND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation @ 12 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-COMMIT
        STREAMS-FLOW-S-CAPACITY = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-RECEIVING =
        _sr2r-assert
    S" pong" _sr2r-reservation-generation @ 13 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-APPEND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation @ 14 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-COMMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-ACCEPTED =
        _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.PAYLOAD-U @ 8 =
        _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-EVENT STREAMS-EVENT-VALID?
        _sr2r-assert
    15 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr2r-assert
    _sr2r-reservation-generation @ 16 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-reservation-generation @ _sr2r-flow-a STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr2r-assert

    0x62 _sr2r-event-b _sr2r-event-header
    _sr2r-input _sr2r-event-b 4 7 20 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    DUP _sr2r-old-generation !
    _sr2r-reservation-generation !
    S" pi" _sr2r-reservation-generation @ 21 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-APPEND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-old-generation @ 1- 22 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-ABORT
        STREAMS-FLOW-S-STALE = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-RECEIVING =
        _sr2r-assert
    _sr2r-reservation-generation @ 23 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-ABORT
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert
    _sr2r-in-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _SPAY-ZERO? _sr2r-assert

    0x63 _sr2r-event-c _sr2r-event-header
    _sr2r-input _sr2r-event-c 4 7 24 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    S" ping" _sr2r-old-generation @ 25 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-APPEND
        STREAMS-FLOW-S-STALE = _sr2r-assert
    _sr2r-reservation-generation @ 26 _sr2r-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert

    0x67 _sr2r-event-a _sr2r-event-header
    _sr2r-input _sr2r-event-a 0 7 30 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    130 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a SFLOW.GENERATION @
        _sr2r-reservation-generation @ = _sr2r-assert

    0x68 _sr2r-event-b _sr2r-event-header
    _sr2r-input _sr2r-event-b 4 7 200 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    S" ping" _sr2r-reservation-generation @ 301 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-APPEND
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-in-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _SPAY-ZERO? _sr2r-assert

    0x69 _sr2r-event-c _sr2r-event-header
    _sr2r-input _sr2r-event-c 0 7 400 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-reservation-generation @ 501 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-COMMIT
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert

    0x6A _sr2r-event-a _sr2r-event-header
    _sr2r-input _sr2r-event-a 4 7 600 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    S" ping" _sr2r-reservation-generation @ 1- 701 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-APPEND
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert

    0x6B _sr2r-event-b _sr2r-event-header
    _sr2r-input _sr2r-event-b 4 7 800 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-reservation-generation @ 1- 901 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-ABORT
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert

    0x6C _sr2r-event-c _sr2r-event-header
    _sr2r-input _sr2r-event-c 4 7 1000 _sr2r-flow-a
        STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-reservation-generation @ 1- 1101 _sr2r-flow-a
        STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-direct-egress  ( -- )
    _sr2r-reset-counters
    _SR2R-MODE-DELIVER _sr2r-mode !
    0x31 _sr2r-flow-a _sr2r-setup-flow

    S" tx:ping" 0x71 _sr2r-event-a _sr2r-build-egress-metadata
    _sr2r-event-a _SEVT-DIGESTED-EGRESS-METADATA? _sr2r-assert
    _sr2r-output _sr2r-event-a 7 7 10 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    DUP 1 = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @
        STREAMS-FLOW-STATE-EGRESS-STAGING = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-CARRIER SPAY.BYTE-U @ 0=
        _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert
    _sr2r-event-a SEVT.PAYLOAD-DIGEST
        _sr2r-flow-a SFLOW.TRANSFORM-RESULT
        SHA3-256-COMPARE _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-EVENT SEVT.ORIGIN-ID
        _sr2r-event-a SEVT.ORIGIN-ID RID= _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-EVENT SEVT.PAYLOAD-DIGEST
        SHA3-256-LEN _SFLOW-ZERO? _sr2r-assert

    S" tx:" _sr2r-reservation-generation @ 11 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-APPEND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation @ 12 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-COMMIT
        STREAMS-FLOW-S-CAPACITY = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @
        STREAMS-FLOW-STATE-EGRESS-STAGING = _sr2r-assert
    S" ping" _sr2r-reservation-generation @ 13 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-APPEND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation @ 14 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-COMMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @
        STREAMS-FLOW-STATE-OUTPUT-READY = _sr2r-assert
    _sr2r-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACCEPTED = _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-EVENT STREAMS-EVENT-VALID?
        _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-EVENT SEVT.PAYLOAD-DIGEST
        _sr2r-event-a SEVT.PAYLOAD-DIGEST
        SHA3-256-COMPARE _sr2r-assert
    15 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    _sr2r-starts @ 1 = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-TERMINAL =
        _sr2r-assert
    _sr2r-reservation-generation @ _sr2r-flow-a STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr2r-assert

    S" tx:ping" 0x72 _sr2r-event-b _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-b 7 7 20 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    DUP _sr2r-old-generation !
    _sr2r-reservation-generation !
    1 _sr2r-flow-a SFLOW.EGRESS-EVENT SEVT.SEQUENCE +!
    _sr2r-flow-a STREAMS-FLOW-VALID? 0= _sr2r-assert
    -1 _sr2r-flow-a SFLOW.EGRESS-EVENT SEVT.SEQUENCE +!
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-flow-a SFLOW.TRANSFORM-RESULT
        DUP C@ 1 XOR SWAP C!
    _sr2r-flow-a STREAMS-FLOW-VALID? 0= _sr2r-assert
    _sr2r-flow-a SFLOW.TRANSFORM-RESULT
        DUP C@ 1 XOR SWAP C!
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-old-generation @ 1- 21 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-ABORT
        STREAMS-FLOW-S-STALE = _sr2r-assert
    _sr2r-reservation-generation @ 22 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-ABORT
        STREAMS-FLOW-S-CANCELLED = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-out-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _SPAY-ZERO? _sr2r-assert

    S" tx:ping" 0x73 _sr2r-event-c _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-c 7 7 30 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    S" tx:pong" _sr2r-reservation-generation @ 31 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-APPEND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation @ 32 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-COMMIT
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr2r-assert
    _sr2r-starts @ 1 = _sr2r-assert
    _sr2r-out-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _SPAY-ZERO? _sr2r-assert

    0 0 0x74 _sr2r-event-a _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-a 0 7 40 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    140 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a SFLOW.GENERATION @
        _sr2r-reservation-generation @ = _sr2r-assert

    S" tx:ping" 0x75 _sr2r-event-b _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-b 7 7 200 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    S" tx:ping" _sr2r-reservation-generation @ 301 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-APPEND
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-out-bytes-a STREAMS-RUNTIME-SEGMENT-BYTES
        _SPAY-ZERO? _sr2r-assert

    0 0 0x76 _sr2r-event-c _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-c 0 7 400 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-reservation-generation @ 501 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-COMMIT
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert

    S" tx:ping" 0x77 _sr2r-event-a _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-a 7 7 600 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    S" tx:ping" _sr2r-reservation-generation @ 1- 701 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-APPEND
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert

    S" tx:ping" 0x78 _sr2r-event-b _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-b 7 7 800 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-reservation-generation @ 1- 901 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-ABORT
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert

    S" tx:ping" 0x79 _sr2r-event-c _sr2r-build-egress-metadata
    _sr2r-output _sr2r-event-c 7 7 1000 _sr2r-flow-a
        STREAMS-FLOW-EGRESS-BEGIN
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-reservation-generation !
    _sr2r-reservation-generation @ 1- 1101 _sr2r-flow-a
        STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-TIMED-OUT = _sr2r-assert
    _sr2r-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr2r-assert
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-execution-pool  ( -- )
    _sr2r-output _sr2r-output _SPOOL-CONNECTORS-SAME-OR-DISJOINT?
        _sr2r-assert
    _sr2r-output _sr2r-output 1+ _SPOOL-CONNECTORS-SAME-OR-DISJOINT?
        0= _sr2r-assert

    0x31 _sr2r-flow-a _sr2r-setup-flow
    _sr2r-metadata-entries 1 _sr2r-metadata-pool
        STREAMS-EXECUTION-POOL-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-output
        _sr2r-metadata-entries
        STREAMS-CONNECTOR-SIZE MOVE
    _sr2r-metadata-entries
        _sr2r-flow-a SFLOW.OUTPUT-CONNECTOR !
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-flow-a _sr2r-metadata-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-metadata-pool _SPOOL.BOUND @ 0= _sr2r-assert
    _sr2r-metadata-pool _SPOOL.BUSY @ 0= _sr2r-assert
    _sr2r-metadata-pool _SPOOL.RUNTIME-BYTES @
        STREAMS-EXECUTION-POOL-SIZE STREAMS-EXECUTION-ENTRY-SIZE + =
        _sr2r-assert

    0x31 _sr2r-flow-a _sr2r-setup-flow
    0x32 _sr2r-flow-b _sr2r-setup-flow
    _sr2r-output _sr2r-in-bytes-b STREAMS-CONNECTOR-SIZE MOVE
    _sr2r-in-bytes-b _sr2r-flow-a SFLOW.OUTPUT-CONNECTOR !
    _sr2r-flow-a STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-flow-b STREAMS-FLOW-VALID? _sr2r-assert
    _sr2r-peer-entries 2 _sr2r-peer-pool
        STREAMS-EXECUTION-POOL-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-a _sr2r-peer-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-b _sr2r-peer-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    _sr2r-peer-pool _SPOOL.BOUND @ 1 = _sr2r-assert
    _sr2r-peer-pool _SPOOL.BUSY @ 0= _sr2r-assert
    _sr2r-peer-pool STREAMS-EXECUTION-POOL-VALID? _sr2r-assert

    0x31 _sr2r-flow-a _sr2r-setup-flow
    0x32 _sr2r-flow-b _sr2r-setup-flow
    _sr2r-pool-entries 2 _sr2r-pool STREAMS-EXECUTION-POOL-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-a _sr2r-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-b _sr2r-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-SEAL
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-VALID? _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-CAPACITY@ 2 = _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0= _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-RUNTIME-BYTES@
        STREAMS-EXECUTION-POOL-SIZE
        STREAMS-EXECUTION-ENTRY-SIZE 2 * +
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES +
        STREAMS-RUNTIME-PROFILE-STANDARD
            STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES + =
        _sr2r-assert

    4096 4096 _sr2r-pool STREAMS-EXECUTION-POOL-ACQUIRE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-pool-lease-a !
    _sr2r-pool-flow-a !
    _sr2r-pool-flow-a @ _sr2r-flow-a = _sr2r-assert
    5000 5000 _sr2r-pool STREAMS-EXECUTION-POOL-ACQUIRE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-pool-lease-b !
    _sr2r-pool-flow-b !
    _sr2r-pool-flow-b @ _sr2r-flow-b = _sr2r-assert
    1 1 _sr2r-pool STREAMS-EXECUTION-POOL-ACQUIRE
        STREAMS-FLOW-S-FULL = _sr2r-assert
    2DROP
    _sr2r-pool STREAMS-EXECUTION-POOL-ACTIVE@ 2 = _sr2r-assert

    _sr2r-pool-flow-a @ _sr2r-pool-lease-a @ _sr2r-pool
        STREAMS-EXECUTION-POOL-RELEASE
        STREAMS-FLOW-S-OK = _sr2r-assert
    5000 5000 _sr2r-pool STREAMS-EXECUTION-POOL-ACQUIRE
        STREAMS-FLOW-S-CAPACITY = _sr2r-assert
    2DROP
    _sr2r-pool-flow-a @ _sr2r-pool-lease-a @ _sr2r-pool
        STREAMS-EXECUTION-POOL-RELEASE
        STREAMS-FLOW-S-STALE = _sr2r-assert
    _sr2r-pool-flow-b @ _sr2r-pool-lease-b @ _sr2r-pool
        STREAMS-EXECUTION-POOL-RELEASE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0= _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-VALID? _sr2r-assert
    _sr2r-flow-a SFLOW.BINDING-EPOCH @ _sr2r-binding-epoch !
    _sr2r-flow-a STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-flow-a SFLOW.BINDING-EPOCH @
        _sr2r-binding-epoch @ 1+ = _sr2r-assert
    _sr2r-pool STREAMS-EXECUTION-POOL-VALID? 0= _sr2r-assert
    1 1 _sr2r-pool STREAMS-EXECUTION-POOL-ACQUIRE
        STREAMS-FLOW-S-INVALID = _sr2r-assert
    2DROP
    _sr2r-pool _SPOOL.BUSY @ 0= _sr2r-assert
    _sr2r-stack ;

: _sr2r-test-isolation  ( -- )
    _sr2r-reset-counters
    _SR2R-MODE-DELIVER _sr2r-mode !
    0x31 _sr2r-flow-a _sr2r-setup-flow
    0x32 _sr2r-flow-b _sr2r-setup-flow
    S" ping" 0x51 _sr2r-event-a _sr2r-flow-a
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    S" pong" 0x52 _sr2r-event-b _sr2r-flow-b
        _sr2r-build-borrowed
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-a 7 10 _sr2r-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-event-b 7 20 _sr2r-flow-b STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr2r-assert
    11 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr2r-assert
    _sr2r-flow-b SFLOW.STATE @ STREAMS-FLOW-STATE-ACCEPTED =
        _sr2r-assert
    21 _sr2r-flow-b STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr2r-assert
    _sr2r-flow-a SFLOW.ID _sr2r-flow-b SFLOW.ID RID= 0=
        _sr2r-assert
    _sr2r-flow-a SFLOW.GENERATION @ 1 = _sr2r-assert
    _sr2r-flow-b SFLOW.GENERATION @ 1 = _sr2r-assert
    -1 _sr2r-reentry-status !
    _SR2R-MODE-REENTER _sr2r-mode !
    12 _sr2r-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    _sr2r-reentry-status @ STREAMS-FLOW-S-BUSY = _sr2r-assert
    _sr2r-flow-b SFLOW.STATE @ STREAMS-FLOW-STATE-OUTPUT-READY =
        _sr2r-assert
    _SR2R-MODE-DELIVER _sr2r-mode !
    23 _sr2r-flow-b STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr2r-assert
    _sr2r-starts @ 2 = _sr2r-assert
    _sr2r-cleanups @ 2 = _sr2r-assert
    1 _sr2r-flow-a STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr2r-assert
    1 _sr2r-flow-b STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr2r-assert
    _sr2r-stack ;

: _SR2R-RUN  ( -- )
    0 _sr2r-fails !
    0 _sr2r-checks !
    DEPTH _sr2r-depth !
    _sr2r-setup-connectors
    _sr2r-stack
    _sr2r-test-connector-directions
    _sr2r-test-exact-bounds
    _sr2r-test-profile-bounds-and-large-body
    _sr2r-test-event-binding-rollback
    _sr2r-test-event-lifecycle-and-full
    _sr2r-test-owned-cleanup-failures
    _sr2r-test-happy-retire-reuse
    _sr2r-test-pending-delivery
    _sr2r-test-transform-failures
    _sr2r-test-output-effect-truth
    _sr2r-test-cancellation
    _sr2r-test-timeout
    _sr2r-test-stale
    _sr2r-test-cleanup-and-throws
    _sr2r-test-segmented-carriers
    _sr2r-test-carrier-binding
    _sr2r-test-alias-preflights
    _sr2r-test-between-call-tamper
    _sr2r-test-direct-ingress
    _sr2r-test-direct-egress
    _sr2r-test-isolation
    _sr2r-test-execution-pool
    _sr2r-fails @ 0= IF
        ." STREAMS SR2 RUNTIME PASS" CR
    ELSE
        ." STREAMS SR2 RUNTIME FAIL " _sr2r-fails @ . CR
    THEN ;
