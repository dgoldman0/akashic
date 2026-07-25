\ streams-sr1-core.f - deterministic contracts for the storage-free SR1 core

PROVIDED akashic-streams-sr1-core-contracts

VARIABLE _sr1c-fails
VARIABLE _sr1c-checks
VARIABLE _sr1c-depth

: _sr1c-assert  ( flag -- )
    1 _sr1c-checks +!
    0= IF
        1 _sr1c-fails +!
        ." STREAMS SR1 CORE ASSERT " _sr1c-checks @ . CR
    THEN ;

: _sr1c-stack  ( -- )
    DEPTH DUP _sr1c-depth @ <> IF
        ." STREAMS SR1 CORE STACK "
        _sr1c-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr1c-depth @ = _sr1c-assert ;

CREATE _sr1c-input       STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr1c-output      STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr1c-bidi        STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr1c-bad         STREAMS-CONNECTOR-SIZE ALLOT
CREATE _sr1c-flow-a      STREAMS-FLOW-SIZE ALLOT
CREATE _sr1c-flow-b      STREAMS-FLOW-SIZE ALLOT
CREATE _sr1c-event-a     STREAMS-EVENT-SIZE ALLOT
CREATE _sr1c-event-b     STREAMS-EVENT-SIZE ALLOT
CREATE _sr1c-event-c     STREAMS-EVENT-SIZE ALLOT
CREATE _sr1c-large-payload STREAMS-FLOW-PAYLOAD-MAX ALLOT

VARIABLE _sr1c-mode
VARIABLE _sr1c-release-mode
VARIABLE _sr1c-releases
VARIABLE _sr1c-starts
VARIABLE _sr1c-polls
VARIABLE _sr1c-cancels
VARIABLE _sr1c-cleanups

VARIABLE _sr1c-cb-event
VARIABLE _sr1c-cb-op
VARIABLE _sr1c-cb-result
VARIABLE _sr1c-t-event
VARIABLE _sr1c-t-output
VARIABLE _sr1c-t-cap
VARIABLE _sr1c-t-result
VARIABLE _sr1c-build-event
VARIABLE _sr1c-build-flow
VARIABLE _sr1c-build-tag
VARIABLE _sr1c-build-timeout
VARIABLE _sr1c-build-a
VARIABLE _sr1c-build-u
VARIABLE _sr1c-expected-status
VARIABLE _sr1c-expected-state
VARIABLE _sr1c-expected-effect

0  CONSTANT _SR1C-MODE-DELIVER
1  CONSTANT _SR1C-MODE-PENDING
2  CONSTANT _SR1C-MODE-TRANSFORM-FAIL
3  CONSTANT _SR1C-MODE-FAILED-BEFORE
4  CONSTANT _SR1C-MODE-FAILED-AFTER
5  CONSTANT _SR1C-MODE-INDETERMINATE
6  CONSTANT _SR1C-MODE-CANCEL
7  CONSTANT _SR1C-MODE-CLEANUP-ERROR
8  CONSTANT _SR1C-MODE-CLEANUP-THROW
9  CONSTANT _SR1C-MODE-START-THROW
10 CONSTANT _SR1C-MODE-TRANSFORM-CANCEL
11 CONSTANT _SR1C-MODE-CANCEL-PENDING
12 CONSTANT _SR1C-MODE-MUTATE-PAYLOAD
13 CONSTANT _SR1C-MODE-POLL-THROW
14 CONSTANT _SR1C-MODE-TRANSFORM-THROW
15 CONSTANT _SR1C-MODE-PENDING-APPLIED
16 CONSTANT _SR1C-MODE-CANCEL-THROW

0x535231434F504D31 CONSTANT _SR1C-OP-MARK

: _sr1c-reset-counters  ( -- )
    0 _sr1c-releases !
    0 _sr1c-starts !
    0 _sr1c-polls !
    0 _sr1c-cancels !
    0 _sr1c-cleanups !
    0 _sr1c-release-mode ! ;

: _sr1c-result!
  ( completion effect detail error result -- )
    >R
    R@ SCRR.ERROR !
    R@ SCRR.DETAIL !
    R@ SCRR.EFFECT !
    R> SCRR.COMPLETION ! ;

: _sr1c-transform-result!
  ( completion output-u detail error result -- )
    >R
    R@ STRR.ERROR !
    R@ STRR.DETAIL !
    R@ STRR.OUTPUT-U !
    R> STRR.COMPLETION ! ;

: _sr1c-release  ( payload-a payload-u context -- error )
    DROP 2DROP
    1 _sr1c-releases +!
    _sr1c-release-mode @ 1 = IF -780 EXIT THEN
    _sr1c-release-mode @ 2 = IF -781 THROW THEN
    0 ;

: _sr1c-transform  ( ingress-event output-a output-cap context result -- )
    _sr1c-t-result !
    DROP
    _sr1c-t-cap !
    _sr1c-t-output !
    _sr1c-t-event !
    _sr1c-mode @ _SR1C-MODE-TRANSFORM-THROW = IF -760 THROW THEN
    _sr1c-mode @ _SR1C-MODE-TRANSFORM-FAIL = IF
        STREAMS-TRANSFORM-COMPLETION-FAILED 0 201 -761
        _sr1c-t-result @ _sr1c-transform-result!
        EXIT
    THEN
    _sr1c-mode @ _SR1C-MODE-TRANSFORM-CANCEL = IF
        STREAMS-TRANSFORM-COMPLETION-CANCELLED 0 202 0
        _sr1c-t-result @ _sr1c-transform-result!
        EXIT
    THEN
    _sr1c-t-event @ SEVT.PAYLOAD-U @ 3 +
        _sr1c-t-cap @ <= _sr1c-assert
    S" tx:" _sr1c-t-output @ SWAP MOVE
    _sr1c-t-event @ SEVT.PAYLOAD-A @
    _sr1c-t-output @ 3 +
    _sr1c-t-event @ SEVT.PAYLOAD-U @ MOVE
    STREAMS-TRANSFORM-COMPLETION-OK
    _sr1c-t-event @ SEVT.PAYLOAD-U @ 3 +
    0 0 _sr1c-t-result @ _sr1c-transform-result! ;

: _sr1c-check-output-event  ( event -- )
    DUP STREAMS-EVENT-VALID? _sr1c-assert
    DUP SEVT.DIRECTION @ STREAMS-EVENT-DIRECTION-EGRESS =
        _sr1c-assert
    DUP SEVT.PAYLOAD-U @ 3 >= _sr1c-assert
    DUP SEVT.PAYLOAD-A @ 3 S" tx:" COMPARE 0= _sr1c-assert
    DROP ;

: _sr1c-start  ( egress-event operation context result -- )
    _sr1c-cb-result !
    DROP
    _sr1c-cb-op !
    _sr1c-cb-event !
    1 _sr1c-starts +!
    _sr1c-cb-event @ _sr1c-check-output-event
    _SR1C-OP-MARK _sr1c-cb-op @ !
    _sr1c-mode @ _SR1C-MODE-START-THROW = IF -762 THROW THEN
    _sr1c-mode @ _SR1C-MODE-MUTATE-PAYLOAD = IF
        0 _sr1c-cb-event @ SEVT.PAYLOAD-A @ C!
        STREAMS-CONNECTOR-COMPLETION-DELIVERED
        STREAMS-EFFECT-APPLIED 0 0
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    _sr1c-mode @ _SR1C-MODE-PENDING =
    _sr1c-mode @ _SR1C-MODE-POLL-THROW = OR
    _sr1c-mode @ _SR1C-MODE-CANCEL-THROW = OR IF
        STREAMS-CONNECTOR-COMPLETION-PENDING
        STREAMS-EFFECT-UNCERTAIN 0 0
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    _sr1c-mode @ _SR1C-MODE-PENDING-APPLIED = IF
        STREAMS-CONNECTOR-COMPLETION-PENDING
        STREAMS-EFFECT-APPLIED 0 0
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    _sr1c-mode @ _SR1C-MODE-FAILED-BEFORE = IF
        STREAMS-CONNECTOR-COMPLETION-FAILED
        STREAMS-EFFECT-NOT-APPLIED 301 -763
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    _sr1c-mode @ _SR1C-MODE-FAILED-AFTER = IF
        STREAMS-CONNECTOR-COMPLETION-FAILED
        STREAMS-EFFECT-APPLIED 302 -764
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    _sr1c-mode @ _SR1C-MODE-INDETERMINATE = IF
        STREAMS-CONNECTOR-COMPLETION-INDETERMINATE
        STREAMS-EFFECT-UNCERTAIN 303 -765
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr1c-cb-result @ _sr1c-result! ;

: _sr1c-poll  ( egress-event operation context result -- )
    _sr1c-cb-result !
    DROP
    _sr1c-cb-op !
    _sr1c-cb-event !
    1 _sr1c-polls +!
    _sr1c-cb-event @ _sr1c-check-output-event
    _sr1c-cb-op @ @ _SR1C-OP-MARK = _sr1c-assert
    _sr1c-mode @ _SR1C-MODE-POLL-THROW = IF -766 THROW THEN
    _sr1c-mode @ _SR1C-MODE-PENDING-APPLIED = IF
        STREAMS-CONNECTOR-COMPLETION-FAILED
        STREAMS-EFFECT-NOT-APPLIED 304 -767
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    STREAMS-CONNECTOR-COMPLETION-DELIVERED
    STREAMS-EFFECT-APPLIED 0 0
    _sr1c-cb-result @ _sr1c-result! ;

: _sr1c-cancel  ( egress-event operation context result -- )
    _sr1c-cb-result !
    DROP
    _sr1c-cb-op !
    _sr1c-cb-event !
    1 _sr1c-cancels +!
    _sr1c-cb-event @ _sr1c-check-output-event
    _sr1c-cb-op @ @ _SR1C-OP-MARK = _sr1c-assert
    _sr1c-mode @ _SR1C-MODE-CANCEL-THROW = IF -768 THROW THEN
    _sr1c-mode @ _SR1C-MODE-CANCEL-PENDING = IF
        STREAMS-CONNECTOR-COMPLETION-PENDING
        STREAMS-EFFECT-UNCERTAIN 401 0
        _sr1c-cb-result @ _sr1c-result!
        EXIT
    THEN
    STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED 0 0
    _sr1c-cb-result @ _sr1c-result! ;

: _sr1c-cleanup  ( egress-event operation context -- error )
    DROP
    _sr1c-cb-op !
    _sr1c-cb-event !
    1 _sr1c-cleanups +!
    _sr1c-mode @ _SR1C-MODE-MUTATE-PAYLOAD <> IF
        _sr1c-cb-event @ _sr1c-check-output-event
    THEN
    _sr1c-cb-op @ @ _SR1C-OP-MARK = _sr1c-assert
    _sr1c-mode @ _SR1C-MODE-CLEANUP-ERROR = IF -770 EXIT THEN
    _sr1c-mode @ _SR1C-MODE-CLEANUP-THROW = IF -771 THROW THEN
    0 ;

: _sr1c-connector-identity  ( id-byte endpoint-byte connector -- )
    >R
    DUP R@ SCON.ENDPOINT-ID RID-SIZE ROT FILL
    DROP
    R> SCON.ID RID-SIZE ROT FILL ;

: _sr1c-setup-connectors  ( -- )
    _sr1c-input STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    0x11 0x21 _sr1c-input _sr1c-connector-identity
    1 _sr1c-input SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT
        _sr1c-input SCON.DIRECTION !
    101 _sr1c-input SCON.PROTOCOL !
    _sr1c-input STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-input STREAMS-CONNECTOR-VALID? _sr1c-assert

    _sr1c-output STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    0x12 0x22 _sr1c-output _sr1c-connector-identity
    1 _sr1c-output SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT
        _sr1c-output SCON.DIRECTION !
    102 _sr1c-output SCON.PROTOCOL !
    0 _sr1c-output SCON.CONTEXT !
    16 _sr1c-output SCON.OP-SIZE !
    ['] _sr1c-start _sr1c-output SCON.START-XT !
    ['] _sr1c-poll _sr1c-output SCON.POLL-XT !
    ['] _sr1c-cancel _sr1c-output SCON.CANCEL-XT !
    ['] _sr1c-cleanup _sr1c-output SCON.CLEANUP-XT !
    _sr1c-output STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-output STREAMS-CONNECTOR-VALID? _sr1c-assert ;

: _sr1c-setup-bidi  ( -- )
    _sr1c-bidi STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    0x13 0x23 _sr1c-bidi _sr1c-connector-identity
    1 _sr1c-bidi SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-BIDIRECTIONAL
        _sr1c-bidi SCON.DIRECTION !
    103 _sr1c-bidi SCON.PROTOCOL !
    16 _sr1c-bidi SCON.OP-SIZE !
    ['] _sr1c-start _sr1c-bidi SCON.START-XT !
    ['] _sr1c-poll _sr1c-bidi SCON.POLL-XT !
    ['] _sr1c-cancel _sr1c-bidi SCON.CANCEL-XT !
    ['] _sr1c-cleanup _sr1c-bidi SCON.CLEANUP-XT !
    _sr1c-bidi STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-bidi STREAMS-CONNECTOR-VALID? _sr1c-assert ;

: _sr1c-configure-flow  ( id-byte timeout-ms flow -- status )
    _sr1c-build-flow !
    _sr1c-build-timeout !
    _sr1c-build-tag !
    _sr1c-build-flow @ STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-build-flow @ SFLOW.ID RID-SIZE
        _sr1c-build-tag @ FILL
    7 _sr1c-build-flow @ SFLOW.REVISION !
    _sr1c-build-timeout @ _sr1c-build-flow @ SFLOW.TIMEOUT-MS !
    _sr1c-input _sr1c-build-flow @ SFLOW.INPUT-CONNECTOR !
    _sr1c-output _sr1c-build-flow @ SFLOW.OUTPUT-CONNECTOR !
    ['] _sr1c-transform _sr1c-build-flow @ SFLOW.TRANSFORM-XT !
    0 _sr1c-build-flow @ SFLOW.TRANSFORM-CONTEXT !
    201 _sr1c-build-flow @ SFLOW.OUTPUT-MEDIA !
    _sr1c-build-flow @ STREAMS-FLOW-SEAL ;

: _sr1c-setup-flow  ( id-byte flow -- )
    >R 100 R> _sr1c-configure-flow
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-build-flow @ STREAMS-FLOW-VALID? _sr1c-assert ;

: _sr1c-event-header  ( tag event -- )
    _sr1c-build-event !
    _sr1c-build-tag !
    _sr1c-build-event @ STREAMS-EVENT-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-build-event @ SEVT.EVENT-ID RID-SIZE
        _sr1c-build-tag @ FILL
    _sr1c-build-event @ SEVT.CORRELATION-ID RID-SIZE
        _sr1c-build-tag @ 1+ FILL
    _sr1c-build-event @ SEVT.IDEMPOTENCY-ID RID-SIZE
        _sr1c-build-tag @ 2 + FILL
    _sr1c-build-event @ SEVT.ORIGIN-ID RID-SIZE
        _sr1c-build-tag @ 3 + FILL
    _sr1c-build-event @ SEVT.DESTINATION-ID RID-SIZE
        _sr1c-build-tag @ 4 + FILL
    301 _sr1c-build-event @ SEVT.MEDIA !
    _sr1c-build-tag @ _sr1c-build-event @ SEVT.SEQUENCE !
    0 _sr1c-build-event @ SEVT.RECEIVED-MS ! ;

: _sr1c-build-borrowed
  ( payload-a payload-u tag event flow -- status )
    _sr1c-build-flow !
    _sr1c-build-event !
    _sr1c-build-tag !
    _sr1c-build-u !
    _sr1c-build-a !
    _sr1c-build-tag @ _sr1c-build-event @ _sr1c-event-header
    _sr1c-build-a @ _sr1c-build-u @ _sr1c-build-event @
        STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-input _sr1c-build-event @ _sr1c-build-flow @
        STREAMS-FLOW-SEAL-INGRESS ;

: _sr1c-build-owned
  ( payload-a payload-u tag event flow -- status )
    _sr1c-build-flow !
    _sr1c-build-event !
    _sr1c-build-tag !
    _sr1c-build-u !
    _sr1c-build-a !
    _sr1c-build-tag @ _sr1c-build-event @ _sr1c-event-header
    _sr1c-build-a @ _sr1c-build-u @
    ['] _sr1c-release _sr1c-build-tag @ _sr1c-build-event @
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-input _sr1c-build-event @ _sr1c-build-flow @
        STREAMS-FLOW-SEAL-INGRESS ;

: _sr1c-to-output-ready  ( -- )
    11 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr1c-assert
    _sr1c-flow-a SFLOW.STATE @
        STREAMS-FLOW-STATE-OUTPUT-READY = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACCEPTED = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-EVENT SEVT.CORRELATION-ID
    _sr1c-flow-a SFLOW.EGRESS-EVENT SEVT.CORRELATION-ID
        RID= _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-EVENT SEVT.IDEMPOTENCY-ID
    _sr1c-flow-a SFLOW.EGRESS-EVENT SEVT.IDEMPOTENCY-ID
        RID= _sr1c-assert ;

: _sr1c-new-a  ( mode -- )
    _sr1c-mode !
    _sr1c-reset-counters
    0x31 _sr1c-flow-a _sr1c-setup-flow
    S" ping" 0x41 _sr1c-event-a _sr1c-flow-a
        _sr1c-build-borrowed
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-a 7 10 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr1c-assert ;

: _sr1c-retire-a  ( -- )
    _sr1c-flow-a SFLOW.GENERATION @ _sr1c-flow-a
        STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr1c-assert ;

: _sr1c-test-connector-directions  ( -- )
    _sr1c-setup-bidi

    _sr1c-bad STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    0x14 0x24 _sr1c-bad _sr1c-connector-identity
    1 _sr1c-bad SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT _sr1c-bad SCON.DIRECTION !
    104 _sr1c-bad SCON.PROTOCOL !
    16 _sr1c-bad SCON.OP-SIZE !
    ['] _sr1c-start _sr1c-bad SCON.START-XT !
    ['] _sr1c-poll _sr1c-bad SCON.POLL-XT !
    ['] _sr1c-cancel _sr1c-bad SCON.CANCEL-XT !
    ['] _sr1c-cleanup _sr1c-bad SCON.CLEANUP-XT !
    _sr1c-bad STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    _sr1c-bad STREAMS-CONNECTOR-VALID? 0= _sr1c-assert

    _sr1c-bad STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    0x15 0x25 _sr1c-bad _sr1c-connector-identity
    1 _sr1c-bad SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT _sr1c-bad SCON.DIRECTION !
    105 _sr1c-bad SCON.PROTOCOL !
    _sr1c-bad STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    _sr1c-bad STREAMS-CONNECTOR-VALID? 0= _sr1c-assert
    _sr1c-stack ;

: _sr1c-output-with-op-size  ( operation-bytes -- status )
    >R
    _sr1c-bad STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    0x16 0x26 _sr1c-bad _sr1c-connector-identity
    1 _sr1c-bad SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT _sr1c-bad SCON.DIRECTION !
    106 _sr1c-bad SCON.PROTOCOL !
    R> _sr1c-bad SCON.OP-SIZE !
    ['] _sr1c-start _sr1c-bad SCON.START-XT !
    ['] _sr1c-poll _sr1c-bad SCON.POLL-XT !
    ['] _sr1c-cancel _sr1c-bad SCON.CANCEL-XT !
    ['] _sr1c-cleanup _sr1c-bad SCON.CLEANUP-XT !
    _sr1c-bad STREAMS-CONNECTOR-SEAL ;

: _sr1c-test-exact-bounds  ( -- )
    STREAMS-FLOW-OP-MAX _sr1c-output-with-op-size
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-bad STREAMS-CONNECTOR-VALID? _sr1c-assert
    STREAMS-FLOW-OP-MAX 1+ _sr1c-output-with-op-size
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    _sr1c-bad STREAMS-CONNECTOR-VALID? 0= _sr1c-assert

    0x33 0 _sr1c-flow-b _sr1c-configure-flow
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    0x33 STREAMS-FLOW-TIMEOUT-MAX-MS 1+
        _sr1c-flow-b _sr1c-configure-flow
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    0x33 STREAMS-FLOW-TIMEOUT-MAX-MS
        _sr1c-flow-b _sr1c-configure-flow
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-flow-b STREAMS-FLOW-VALID? _sr1c-assert

    S" edge" 0x3F _sr1c-event-c _sr1c-flow-b
        _sr1c-build-borrowed
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-c 7
        _SFLOW-CELL-MAX STREAMS-FLOW-TIMEOUT-MAX-MS - 1+
        _sr1c-flow-b STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-CAPACITY = _sr1c-assert
    _sr1c-event-c STREAMS-EVENT-VALID? _sr1c-assert
    _sr1c-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert

    0x40 _sr1c-event-a _sr1c-event-header
    _sr1c-large-payload STREAMS-FLOW-PAYLOAD-MAX
        _sr1c-event-a STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-a STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert

    0x41 _sr1c-event-b _sr1c-event-header
    _sr1c-large-payload STREAMS-FLOW-PAYLOAD-MAX 1+
        _sr1c-event-b STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-CAPACITY = _sr1c-assert
    _sr1c-stack ;

: _sr1c-test-event-binding-rollback  ( -- )
    _sr1c-reset-counters

    0x49 _sr1c-event-c _sr1c-event-header
    S" ping" ['] _sr1c-release 0x49 _sr1c-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-OK = _sr1c-assert
    S" pong" ['] _sr1c-release 0x4A _sr1c-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    S" pong" _sr1c-event-c STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    _sr1c-event-c SEVT.RELEASE-CONTEXT @ 0x49 =
        _sr1c-assert
    _sr1c-event-c STREAMS-EVENT-SEAL
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    _sr1c-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-releases @ 1 = _sr1c-assert
    _sr1c-event-c SEVT.STATE @ _SEVT-STATE-CLOSED =
        _sr1c-assert
    _sr1c-event-c SEVT.PAYLOAD-A @ 0= _sr1c-assert
    _sr1c-event-c SEVT.RELEASE-XT @ 0= _sr1c-assert
    _sr1c-event-c SEVT.RELEASE-CONTEXT @ 0= _sr1c-assert
    _sr1c-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-releases @ 1 = _sr1c-assert

    0x4B _sr1c-event-c _sr1c-event-header
    S" ping" _sr1c-event-c STREAMS-EVENT-BORROW
        STREAMS-FLOW-S-OK = _sr1c-assert
    S" pong" ['] _sr1c-release 0x4B _sr1c-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    _sr1c-event-c STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-releases @ 1 = _sr1c-assert
    _sr1c-stack ;

: _sr1c-test-event-lifecycle-and-full  ( -- )
    _sr1c-reset-counters
    0x31 _sr1c-flow-a _sr1c-setup-flow

    S" ping" 0x42 _sr1c-event-a _sr1c-flow-a
        _sr1c-build-owned
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-a STREAMS-EVENT-VALID? _sr1c-assert
    _sr1c-event-a 7 10 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-releases @ 1 = _sr1c-assert
    _sr1c-event-a STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-releases @ 1 = _sr1c-assert

    S" pong" 0x43 _sr1c-event-b _sr1c-flow-a
        _sr1c-build-owned
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-b 7 11 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-FULL = _sr1c-assert
    _sr1c-releases @ 1 = _sr1c-assert
    _sr1c-event-b STREAMS-EVENT-VALID? _sr1c-assert
    _sr1c-event-b STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-b STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-releases @ 2 = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACCEPTED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr1c-assert
    _sr1c-flow-a SFLOW.GENERATION @ 12 _sr1c-flow-a
        STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr1c-assert
    _sr1c-retire-a

    0x49 _sr1c-event-c _sr1c-event-header
    0 0 0 0 _sr1c-event-c STREAMS-EVENT-OWN
        STREAMS-FLOW-S-INVALID = _sr1c-assert
    0 0 ['] _sr1c-release 0x49 _sr1c-event-c
        STREAMS-EVENT-OWN
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-input _sr1c-event-c _sr1c-flow-a
        STREAMS-FLOW-SEAL-INGRESS
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-c 7 13 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-releases @ 3 = _sr1c-assert
    2 14 _sr1c-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-owned-cleanup-failures  ( -- )
    _sr1c-reset-counters
    0x31 _sr1c-flow-a _sr1c-setup-flow
    1 _sr1c-release-mode !
    S" ping" 0x44 _sr1c-event-a _sr1c-flow-a
        _sr1c-build-owned
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-a 7 10 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-CLEANUP = _sr1c-assert
    _sr1c-releases @ 1 = _sr1c-assert
    _sr1c-event-a SEVT.STATE @ _SEVT-STATE-CLEANUP-FAILED =
        _sr1c-assert
    _sr1c-event-a SEVT.CLEANUP-ERROR @ -780 = _sr1c-assert
    _sr1c-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr1c-assert

    2 _sr1c-release-mode !
    S" pong" 0x45 _sr1c-event-b _sr1c-flow-a
        _sr1c-build-owned
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-b 7 11 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-CLEANUP = _sr1c-assert
    _sr1c-releases @ 2 = _sr1c-assert
    _sr1c-event-b SEVT.CLEANUP-ERROR @ -781 = _sr1c-assert
    0 _sr1c-release-mode !
    _sr1c-stack ;

: _sr1c-test-happy-retire-reuse  ( -- )
    _SR1C-MODE-DELIVER _sr1c-new-a
    _sr1c-to-output-ready
    _sr1c-flow-a SFLOW.EGRESS-EVENT SEVT.PAYLOAD-A @
    _sr1c-flow-a SFLOW.EGRESS-EVENT SEVT.PAYLOAD-U @
    S" tx:ping" COMPARE 0= _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr1c-assert
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr1c-assert
    _sr1c-starts @ 1 = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-DELIVERED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT STREAMS-ATTEMPT-VALID?
        _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT STREAMS-ATTEMPT-VALID?
        _sr1c-assert
    13 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr1c-assert
    _sr1c-flow-a SFLOW.GENERATION @ 14 _sr1c-flow-a
        STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-DELIVERED = _sr1c-assert
    _sr1c-starts @ 1 = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a
    _sr1c-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-IDLE =
        _sr1c-assert

    S" pong" 0x46 _sr1c-event-b _sr1c-flow-a
        _sr1c-build-borrowed
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-b 7 20 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-flow-a SFLOW.GENERATION @ 2 = _sr1c-assert
    2 21 _sr1c-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-pending-delivery  ( -- )
    _SR1C-MODE-PENDING _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    _sr1c-flow-a SFLOW.STATE @ STREAMS-FLOW-STATE-DELIVERING =
        _sr1c-assert
    _sr1c-cleanups @ 0= _sr1c-assert
    13 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr1c-assert
    _sr1c-starts @ 1 = _sr1c-assert
    _sr1c-polls @ 1 = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-transform-failures  ( -- )
    _SR1C-MODE-TRANSFORM-FAIL _sr1c-new-a
    11 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-BEFORE = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-NOT-APPLIED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-EMPTY = _sr1c-assert
    _sr1c-starts @ 0= _sr1c-assert
    _sr1c-cleanups @ 0= _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-TRANSFORM-CANCEL _sr1c-new-a
    11 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CANCELLED = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-CANCELLED = _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-TRANSFORM-THROW _sr1c-new-a
    11 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-CALLBACK = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.ERROR @ -760 =
        _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-run-output-outcome
  ( mode expected-status expected-state expected-effect -- )
    _sr1c-expected-effect !
    _sr1c-expected-state !
    _sr1c-expected-status !
    _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        _sr1c-expected-status @ = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        _sr1c-expected-state @ =
        _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        _sr1c-expected-effect @ =
        _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a ;

: _sr1c-test-output-effect-truth  ( -- )
    _SR1C-MODE-FAILED-BEFORE
    STREAMS-FLOW-S-FAILED
    STREAMS-ATTEMPT-STATE-FAILED-BEFORE
    STREAMS-EFFECT-NOT-APPLIED _sr1c-run-output-outcome

    _SR1C-MODE-FAILED-AFTER
    STREAMS-FLOW-S-FAILED
    STREAMS-ATTEMPT-STATE-FAILED-AFTER
    STREAMS-EFFECT-APPLIED _sr1c-run-output-outcome

    _SR1C-MODE-INDETERMINATE
    STREAMS-FLOW-S-INDETERMINATE
    STREAMS-ATTEMPT-STATE-INDETERMINATE
    STREAMS-EFFECT-UNCERTAIN _sr1c-run-output-outcome

    _SR1C-MODE-MUTATE-PAYLOAD
    STREAMS-FLOW-S-INDETERMINATE
    STREAMS-ATTEMPT-STATE-INDETERMINATE
    STREAMS-EFFECT-UNCERTAIN _sr1c-run-output-outcome

    _SR1C-MODE-PENDING-APPLIED _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr1c-assert
    13 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-AFTER = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -767 =
        _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-cancellation  ( -- )
    _SR1C-MODE-CANCEL _sr1c-new-a
    1 11 _sr1c-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-CANCELLED = _sr1c-assert
    _sr1c-cancels @ 0= _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-CANCEL _sr1c-new-a
    _sr1c-to-output-ready
    1 12 _sr1c-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-ACKNOWLEDGED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-CANCELLED = _sr1c-assert
    _sr1c-cancels @ 0= _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-PENDING _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    1 13 _sr1c-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED = _sr1c-assert
    _sr1c-cancels @ 1 = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-CANCEL-THROW _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    1 13 _sr1c-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-UNCERTAIN = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-CALLBACK = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -768 =
        _sr1c-assert
    _sr1c-cancels @ 1 = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-PENDING _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    _SR1C-MODE-CANCEL-PENDING _sr1c-mode !
    1 13 _sr1c-flow-a STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-UNCERTAIN = _sr1c-assert
    _sr1c-cancels @ 1 = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-timeout  ( -- )
    _SR1C-MODE-CANCEL _sr1c-new-a
    110 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-TIMED-OUT = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-TIMEOUT = _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-PENDING _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    110 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-TIMED-OUT = _sr1c-assert
    _sr1c-cancels @ 1 = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-stale  ( -- )
    _sr1c-reset-counters
    0x31 _sr1c-flow-a _sr1c-setup-flow
    S" ping" 0x47 _sr1c-event-a _sr1c-flow-a
        _sr1c-build-borrowed
        STREAMS-FLOW-S-OK = _sr1c-assert
    2 _sr1c-event-a SEVT.CONNECTOR-REVISION !
    _sr1c-event-a 7 10 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-STALE = _sr1c-assert
    _sr1c-event-a STREAMS-EVENT-VALID? _sr1c-assert
    _sr1c-event-a STREAMS-EVENT-CLOSE
        STREAMS-FLOW-S-OK = _sr1c-assert

    S" pong" 0x48 _sr1c-event-b _sr1c-flow-a
        _sr1c-build-borrowed
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-b 7 11 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    2 _sr1c-input SCON.REVISION !
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-STALE = _sr1c-assert
    _sr1c-flow-a SFLOW.INGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-STALE = _sr1c-assert
    1 _sr1c-input SCON.REVISION !
    _sr1c-retire-a

    _SR1C-MODE-PENDING _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    2 _sr1c-output SCON.REVISION !
    13 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-UNCERTAIN = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-STALE = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    1 _sr1c-output SCON.REVISION !
    _sr1c-retire-a

    _SR1C-MODE-PENDING-APPLIED _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    2 _sr1c-output SCON.REVISION !
    13 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-FAILED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-FAILED-AFTER = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.EFFECT @
        STREAMS-EFFECT-APPLIED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.REASON @
        STREAMS-ATTEMPT-REASON-STALE = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    1 _sr1c-output SCON.REVISION !
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-cleanup-and-throws  ( -- )
    _SR1C-MODE-CLEANUP-ERROR _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CLEANUP = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-DELIVERED = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.CLEANUP-ERROR @ -770 =
        _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    13 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CLEANUP = _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-CLEANUP-THROW _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-CLEANUP = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.CLEANUP-ERROR @ -771 =
        _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-START-THROW _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.STATE @
        STREAMS-ATTEMPT-STATE-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -762 =
        _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a

    _SR1C-MODE-POLL-THROW _sr1c-new-a
    _sr1c-to-output-ready
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-PENDING = _sr1c-assert
    13 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-INDETERMINATE = _sr1c-assert
    _sr1c-flow-a SFLOW.EGRESS-ATTEMPT SATT.ERROR @ -766 =
        _sr1c-assert
    _sr1c-cleanups @ 1 = _sr1c-assert
    _sr1c-retire-a
    _sr1c-stack ;

: _sr1c-test-isolation  ( -- )
    _sr1c-reset-counters
    _SR1C-MODE-DELIVER _sr1c-mode !
    0x31 _sr1c-flow-a _sr1c-setup-flow
    0x32 _sr1c-flow-b _sr1c-setup-flow
    S" ping" 0x51 _sr1c-event-a _sr1c-flow-a
        _sr1c-build-borrowed
        STREAMS-FLOW-S-OK = _sr1c-assert
    S" pong" 0x52 _sr1c-event-b _sr1c-flow-b
        _sr1c-build-borrowed
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-a 7 10 _sr1c-flow-a STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-event-b 7 20 _sr1c-flow-b STREAMS-FLOW-ADMIT
        STREAMS-FLOW-S-OK = _sr1c-assert
    11 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr1c-assert
    _sr1c-flow-b SFLOW.STATE @ STREAMS-FLOW-STATE-ACCEPTED =
        _sr1c-assert
    21 _sr1c-flow-b STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED = _sr1c-assert
    _sr1c-flow-a SFLOW.ID _sr1c-flow-b SFLOW.ID RID= 0=
        _sr1c-assert
    _sr1c-flow-a SFLOW.GENERATION @ 1 = _sr1c-assert
    _sr1c-flow-b SFLOW.GENERATION @ 1 = _sr1c-assert
    12 _sr1c-flow-a STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr1c-assert
    _sr1c-flow-b SFLOW.STATE @ STREAMS-FLOW-STATE-OUTPUT-READY =
        _sr1c-assert
    22 _sr1c-flow-b STREAMS-FLOW-STEP
        STREAMS-FLOW-S-DELIVERED = _sr1c-assert
    _sr1c-starts @ 2 = _sr1c-assert
    _sr1c-cleanups @ 2 = _sr1c-assert
    1 _sr1c-flow-a STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr1c-assert
    1 _sr1c-flow-b STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK = _sr1c-assert
    _sr1c-stack ;

: _SR1C-RUN  ( -- )
    0 _sr1c-fails !
    0 _sr1c-checks !
    DEPTH _sr1c-depth !
    _sr1c-setup-connectors
    _sr1c-stack
    _sr1c-test-connector-directions
    _sr1c-test-exact-bounds
    _sr1c-test-event-binding-rollback
    _sr1c-test-event-lifecycle-and-full
    _sr1c-test-owned-cleanup-failures
    _sr1c-test-happy-retire-reuse
    _sr1c-test-pending-delivery
    _sr1c-test-transform-failures
    _sr1c-test-output-effect-truth
    _sr1c-test-cancellation
    _sr1c-test-timeout
    _sr1c-test-stale
    _sr1c-test-cleanup-and-throws
    _sr1c-test-isolation
    _sr1c-fails @ 0= IF
        ." STREAMS SR1 CORE PASS" CR
    ELSE
        ." STREAMS SR1 CORE FAIL " _sr1c-fails @ . CR
    THEN ;
