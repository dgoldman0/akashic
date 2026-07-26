\ streams-sr3-config.f - deterministic SR3 configuration contracts

PROVIDED akashic-streams-sr3-config-record-contracts

VARIABLE _sr3c-fails
VARIABLE _sr3c-checks
VARIABLE _sr3c-depth

: _sr3c-assert  ( flag -- )
    1 _sr3c-checks +!
    0= IF
        1 _sr3c-fails +!
        ." STREAMS SR3 CONFIG ASSERT " _sr3c-checks @ . CR
    THEN ;

: _sr3c-stack  ( -- )
    DEPTH DUP _sr3c-depth @ <> IF
        ." STREAMS SR3 CONFIG STACK "
        _sr3c-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr3c-depth @ = _sr3c-assert ;

CREATE _sr3c-rid-a RID-SIZE ALLOT
CREATE _sr3c-rid-b RID-SIZE ALLOT
CREATE _sr3c-rid-c RID-SIZE ALLOT
CREATE _sr3c-rid-d RID-SIZE ALLOT
CREATE _sr3c-rid-e RID-SIZE ALLOT
CREATE _sr3c-rid-f RID-SIZE ALLOT
CREATE _sr3c-rid-zero RID-SIZE ALLOT

CREATE _sr3c-connector-a STREAMS-OPCONN-SIZE 16 + ALLOT
CREATE _sr3c-connector-b STREAMS-OPCONN-SIZE 16 + ALLOT
CREATE _sr3c-connector-c STREAMS-OPCONN-SIZE 16 + ALLOT
CREATE _sr3c-connector-snapshot STREAMS-OPCONN-SIZE ALLOT

CREATE _sr3c-flow-a STREAMS-OPFLOW-SIZE 16 + ALLOT
CREATE _sr3c-flow-b STREAMS-OPFLOW-SIZE 16 + ALLOT
CREATE _sr3c-flow-c STREAMS-OPFLOW-SIZE 16 + ALLOT
CREATE _sr3c-flow-snapshot STREAMS-OPFLOW-SIZE ALLOT

CREATE _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-SIZE 16 + ALLOT
CREATE _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SIZE 16 + ALLOT
CREATE _sr3c-checkpoint-c STREAMS-OPCHECKPOINT-SIZE 16 + ALLOT
CREATE _sr3c-checkpoint-snapshot STREAMS-OPCHECKPOINT-SIZE ALLOT

: _sr3c-setup-identities  ( -- )
    _sr3c-rid-a RID-SIZE 0x11 FILL
    _sr3c-rid-b RID-SIZE 0x22 FILL
    _sr3c-rid-c RID-SIZE 0x33 FILL
    _sr3c-rid-d RID-SIZE 0x44 FILL
    _sr3c-rid-e RID-SIZE 0x55 FILL
    _sr3c-rid-f RID-SIZE 0x66 FILL
    _sr3c-rid-zero RID-CLEAR ;

: _sr3c-empty-blob!  ( blob -- )
    DUP PBLOB-SIZE 0 FILL
    _PBLOB-MAGIC OVER _PBL.MAGIC !
    -1 SWAP _PBL.LEVEL ! ;

: _sr3c-valid-connector!  ( connector -- )
    >R
    R@ STREAMS-OPCONN-INIT
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-rid-a R@ SOPCONN.CONNECTOR-ID RID-COPY
    _sr3c-rid-b R@ SOPCONN.ENDPOINT-ID RID-COPY
    _sr3c-rid-c R@ SOPCONN.ENDPOINT-SEAL RID-COPY
    1 R@ SOPCONN.REVISION !
    101 R@ SOPCONN.PROTOCOL !
    202 R@ SOPCONN.PROFILE !
    8192 R@ SOPCONN.REQUEST-BYTE-LIMIT !
    4096 R@ SOPCONN.RESPONSE-BYTE-LIMIT !
    4096 R@ SOPCONN.PAYLOAD-BYTE-LIMIT !
    8 R@ SOPCONN.QUEUE-ITEM-LIMIT !
    32768 R@ SOPCONN.QUEUE-BYTE-LIMIT !
    3 R@ SOPCONN.RETRY-LIMIT !
    100 R@ SOPCONN.RETRY-DELAY-MS !
    2 R@ SOPCONN.REDIRECT-LIMIT !
    1000 R@ SOPCONN.CONNECT-TIMEOUT-MS !
    5000 R@ SOPCONN.OPERATION-TIMEOUT-MS !
    1000 R@ SOPCONN.IDLE-TIMEOUT-MS !
    STREAMS-OPCONN-IDEMPOTENCY-EXACT
        R@ SOPCONN.IDEMPOTENCY-POLICY !
    STREAMS-OPCONN-HEALTH-HEALTHY R@ SOPCONN.HEALTH !
    500 R@ SOPCONN.CONFIGURED-MS !
    R@ STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert
    R> DROP ;

: _sr3c-valid-flow!  ( flow -- )
    >R
    R@ STREAMS-OPFLOW-INIT
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-rid-a R@ SOPFLOW.FLOW-ID RID-COPY
    _sr3c-rid-b R@ SOPFLOW.INPUT-CONNECTOR-ID RID-COPY
    _sr3c-rid-c R@ SOPFLOW.OUTPUT-CONNECTOR-ID RID-COPY
    _sr3c-rid-d R@ SOPFLOW.ROUTE-ID RID-COPY
    _sr3c-rid-e R@ SOPFLOW.TRANSFORM-ID RID-COPY
    1 R@ SOPFLOW.REVISION !
    2 R@ SOPFLOW.INPUT-CONNECTOR-REVISION !
    3 R@ SOPFLOW.OUTPUT-CONNECTOR-REVISION !
    4 R@ SOPFLOW.ROUTE-REVISION !
    5 R@ SOPFLOW.TRANSFORM-REVISION !
    4096 R@ SOPFLOW.PAYLOAD-BYTE-LIMIT !
    8192 R@ SOPFLOW.OUTPUT-BYTE-LIMIT !
    4 R@ SOPFLOW.IN-FLIGHT-LIMIT !
    100000 R@ SOPFLOW.TRANSFORM-STEP-LIMIT !
    5000 R@ SOPFLOW.TIMEOUT-MS !
    STREAMS-OPFLOW-BACKPRESSURE-PAUSE
        R@ SOPFLOW.BACKPRESSURE-POLICY !
    STREAMS-OPFLOW-FAILURE-REVIEW R@ SOPFLOW.FAILURE-POLICY !
    STREAMS-OPFLOW-RETRY-CONNECTOR-EXACT
        R@ SOPFLOW.RETRY-POLICY !
    500 R@ SOPFLOW.CONFIGURED-MS !
    R@ STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert
    R> DROP ;

: _sr3c-valid-checkpoint!  ( checkpoint -- )
    >R
    R@ STREAMS-OPCHECKPOINT-INIT
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-rid-a R@ SOPCHECKPOINT.CHECKPOINT-ID RID-COPY
    _sr3c-rid-b R@ SOPCHECKPOINT.CONNECTOR-ID RID-COPY
    _sr3c-rid-c R@ SOPCHECKPOINT.FLOW-ID RID-COPY
    _sr3c-rid-d R@ SOPCHECKPOINT.CURSOR-DIGEST RID-COPY
    2 R@ SOPCHECKPOINT.CONNECTOR-REVISION !
    3 R@ SOPCHECKPOINT.FLOW-REVISION !
    1 R@ SOPCHECKPOINT.RECORD-REVISION !
    1 R@ SOPCHECKPOINT.ORDER !
    500 R@ SOPCHECKPOINT.COMMITTED-MS !
    R@ SOPCHECKPOINT.CURSOR-BLOB _sr3c-empty-blob!
    R@ STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert
    R> DROP ;

: _sr3c-connector-field-valid  ( value accessor-xt -- )
    >R
    _sr3c-connector-b _sr3c-valid-connector!
    _sr3c-connector-b R> EXECUTE !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert ;

: _sr3c-connector-field-invalid  ( value accessor-xt -- )
    >R
    _sr3c-connector-b _sr3c-valid-connector!
    _sr3c-connector-b R> EXECUTE !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert ;

: _sr3c-flow-field-valid  ( value accessor-xt -- )
    >R
    _sr3c-flow-b _sr3c-valid-flow!
    _sr3c-flow-b R> EXECUTE !
    _sr3c-flow-b STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert ;

: _sr3c-flow-field-invalid  ( value accessor-xt -- )
    >R
    _sr3c-flow-b _sr3c-valid-flow!
    _sr3c-flow-b R> EXECUTE !
    _sr3c-flow-b STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert ;

: _sr3c-checkpoint-field-valid  ( value accessor-xt -- )
    >R
    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    _sr3c-checkpoint-b R> EXECUTE !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert ;

: _sr3c-checkpoint-field-invalid  ( value accessor-xt -- )
    >R
    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    _sr3c-checkpoint-b R> EXECUTE !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert ;

: _sr3c-connector-rid-invalid  ( accessor-xt -- )
    >R
    _sr3c-connector-b _sr3c-valid-connector!
    _sr3c-connector-b R> EXECUTE RID-CLEAR
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert ;

: _sr3c-flow-rid-invalid  ( accessor-xt -- )
    >R
    _sr3c-flow-b _sr3c-valid-flow!
    _sr3c-flow-b R> EXECUTE RID-CLEAR
    _sr3c-flow-b STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert ;

: _sr3c-checkpoint-rid-invalid  ( accessor-xt -- )
    >R
    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    _sr3c-checkpoint-b R> EXECUTE RID-CLEAR
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert ;

: _sr3c-connector-lifecycle  ( lifecycle enabled -- status )
    >R
    _sr3c-connector-b _sr3c-valid-connector!
    _sr3c-connector-b SOPCONN.LIFECYCLE !
    R> _sr3c-connector-b SOPCONN.ENABLED !
    _sr3c-connector-b STREAMS-OPCONN-SEAL ;

: _sr3c-flow-lifecycle  ( lifecycle enabled -- status )
    >R
    _sr3c-flow-b _sr3c-valid-flow!
    _sr3c-flow-b SOPFLOW.LIFECYCLE !
    R> _sr3c-flow-b SOPFLOW.ENABLED !
    _sr3c-flow-b STREAMS-OPFLOW-SEAL ;

: _sr3c-test-geometry-and-defaults  ( -- )
    STREAMS-OPCONN-SIZE 512 = _sr3c-assert
    STREAMS-OPFLOW-SIZE 512 = _sr3c-assert
    STREAMS-OPCHECKPOINT-SIZE 448 = _sr3c-assert
    STREAMS-OPCONN-SIZE PERSIST-PAGE-PAYLOAD-SIZE <= _sr3c-assert
    STREAMS-OPFLOW-SIZE PERSIST-PAGE-PAYLOAD-SIZE <= _sr3c-assert
    STREAMS-OPCHECKPOINT-SIZE PERSIST-PAGE-PAYLOAD-SIZE <= _sr3c-assert
    PBLOB-SIZE 72 = _sr3c-assert

    _sr3c-connector-a STREAMS-OPCONN-INIT
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-connector-a STREAMS-OPCONN-SIZE
        STREAMS-OPCONN-HEADER-CLASSIFY
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-connector-a SOPREC.KIND @
        STREAMS-OPREC-KIND-CONNECTOR = _sr3c-assert
    _sr3c-connector-a SOPCONN.DIRECTION @
        STREAMS-OPCONN-DIRECTION-EGRESS = _sr3c-assert
    _sr3c-connector-a SOPCONN.ENDPOINT-POLICY @
        STREAMS-OPCONN-ENDPOINT-PINNED = _sr3c-assert
    _sr3c-connector-a SOPCONN.CREDENTIAL-POLICY @
        STREAMS-OPCONN-CREDENTIAL-NONE = _sr3c-assert
    _sr3c-connector-a SOPCONN.CREDENTIAL-ID RID-ZERO? _sr3c-assert
    _sr3c-connector-a SOPCONN.RECEIPT-POLICY @
        STREAMS-OPCONN-RECEIPT-NONE = _sr3c-assert
    _sr3c-connector-a SOPCONN.RECEIPT-BYTE-LIMIT @ 0= _sr3c-assert
    _sr3c-connector-a SOPCONN.LIFECYCLE @
        STREAMS-OPCONN-LIFECYCLE-CONFIGURED = _sr3c-assert
    _sr3c-connector-a SOPCONN.ENABLED @ 0= _sr3c-assert
    _sr3c-connector-a SOPCONN.RESERVED
        STREAMS-OPCONN-SIZE _SOPC-RESERVED -
        _SOPREC-ZERO? _sr3c-assert

    _sr3c-flow-a STREAMS-OPFLOW-INIT
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-flow-a STREAMS-OPFLOW-SIZE STREAMS-OPFLOW-HEADER-CLASSIFY
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-flow-a SOPREC.KIND @
        STREAMS-OPREC-KIND-FLOW = _sr3c-assert
    _sr3c-flow-a SOPFLOW.BACKPRESSURE-POLICY @
        STREAMS-OPFLOW-BACKPRESSURE-REFUSE = _sr3c-assert
    _sr3c-flow-a SOPFLOW.FAILURE-POLICY @
        STREAMS-OPFLOW-FAILURE-TERMINAL = _sr3c-assert
    _sr3c-flow-a SOPFLOW.RETRY-POLICY @
        STREAMS-OPFLOW-RETRY-NONE = _sr3c-assert
    _sr3c-flow-a SOPFLOW.LIFECYCLE @
        STREAMS-OPFLOW-LIFECYCLE-CONFIGURED = _sr3c-assert
    _sr3c-flow-a SOPFLOW.ENABLED @ 0= _sr3c-assert
    _sr3c-flow-a SOPFLOW.RESERVED
        STREAMS-OPFLOW-SIZE _SOPF-RESERVED -
        _SOPREC-ZERO? _sr3c-assert

    _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-INIT
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-HEADER-CLASSIFY
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-checkpoint-a SOPREC.KIND @
        STREAMS-OPREC-KIND-CHECKPOINT = _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.RESERVED
        STREAMS-OPCHECKPOINT-SIZE _SOPK-RESERVED -
        _SOPREC-ZERO? _sr3c-assert

    0 STREAMS-OPCONN-INIT
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    0 STREAMS-OPFLOW-INIT
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    0 STREAMS-OPCHECKPOINT-INIT
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-valid-construction  ( -- )
    _sr3c-connector-a _sr3c-valid-connector!
    _sr3c-connector-a STREAMS-OPCONN-SIZE
        STREAMS-OPCONN-VALID? _sr3c-assert
    _sr3c-connector-a SOPCONN.CONNECTOR-ID
        _sr3c-rid-a RID= _sr3c-assert
    _sr3c-connector-a SOPCONN.ENDPOINT-ID
        _sr3c-rid-b RID= _sr3c-assert
    _sr3c-connector-a SOPCONN.ENDPOINT-SEAL
        _sr3c-rid-c RID= _sr3c-assert

    _sr3c-flow-a _sr3c-valid-flow!
    _sr3c-flow-a STREAMS-OPFLOW-SIZE
        STREAMS-OPFLOW-VALID? _sr3c-assert
    _sr3c-flow-a SOPFLOW.FLOW-ID _sr3c-rid-a RID= _sr3c-assert
    _sr3c-flow-a SOPFLOW.OUTPUT-CONNECTOR-ID
        _sr3c-rid-c RID= _sr3c-assert
    _sr3c-flow-a SOPFLOW.OUTPUT-CONNECTOR-REVISION @
        3 = _sr3c-assert

    _sr3c-checkpoint-a _sr3c-valid-checkpoint!
    _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-VALID? _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CHECKPOINT-ID
        _sr3c-rid-a RID= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CONNECTOR-ID
        _sr3c-rid-b RID= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.FLOW-ID
        _sr3c-rid-c RID= _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-connector-policies  ( -- )
    STREAMS-OPCONN-DIRECTION-EGRESS ['] SOPCONN.DIRECTION
        _sr3c-connector-field-valid
    1 ['] SOPCONN.DIRECTION _sr3c-connector-field-invalid
    3 ['] SOPCONN.DIRECTION _sr3c-connector-field-invalid

    STREAMS-OPCONN-ENDPOINT-PINNED ['] SOPCONN.ENDPOINT-POLICY
        _sr3c-connector-field-valid
    STREAMS-OPCONN-ENDPOINT-ALLOWLISTED ['] SOPCONN.ENDPOINT-POLICY
        _sr3c-connector-field-valid
    0 ['] SOPCONN.ENDPOINT-POLICY _sr3c-connector-field-invalid
    3 ['] SOPCONN.ENDPOINT-POLICY _sr3c-connector-field-invalid

    STREAMS-OPCONN-IDEMPOTENCY-NONE
        ['] SOPCONN.IDEMPOTENCY-POLICY _sr3c-connector-field-valid
    STREAMS-OPCONN-IDEMPOTENCY-EXACT
        ['] SOPCONN.IDEMPOTENCY-POLICY _sr3c-connector-field-valid
    -1 ['] SOPCONN.IDEMPOTENCY-POLICY _sr3c-connector-field-invalid
    2 ['] SOPCONN.IDEMPOTENCY-POLICY _sr3c-connector-field-invalid

    STREAMS-OPCONN-HEALTH-UNKNOWN ['] SOPCONN.HEALTH
        _sr3c-connector-field-valid
    STREAMS-OPCONN-HEALTH-HEALTHY ['] SOPCONN.HEALTH
        _sr3c-connector-field-valid
    STREAMS-OPCONN-HEALTH-DEGRADED ['] SOPCONN.HEALTH
        _sr3c-connector-field-valid
    STREAMS-OPCONN-HEALTH-UNAVAILABLE ['] SOPCONN.HEALTH
        _sr3c-connector-field-valid
    -1 ['] SOPCONN.HEALTH _sr3c-connector-field-invalid
    4 ['] SOPCONN.HEALTH _sr3c-connector-field-invalid

    _sr3c-connector-b _sr3c-valid-connector!
    _sr3c-rid-d _sr3c-connector-b SOPCONN.CREDENTIAL-ID RID-COPY
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-connector-b _sr3c-valid-connector!
    STREAMS-OPCONN-CREDENTIAL-OPAQUE
        _sr3c-connector-b SOPCONN.CREDENTIAL-POLICY !
    _sr3c-rid-d _sr3c-connector-b SOPCONN.CREDENTIAL-ID RID-COPY
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-connector-b _sr3c-valid-connector!
    STREAMS-OPCONN-CREDENTIAL-OPAQUE
        _sr3c-connector-b SOPCONN.CREDENTIAL-POLICY !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    2 ['] SOPCONN.CREDENTIAL-POLICY
        _sr3c-connector-field-invalid

    _sr3c-connector-b _sr3c-valid-connector!
    1 _sr3c-connector-b SOPCONN.RECEIPT-BYTE-LIMIT !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-connector-b _sr3c-valid-connector!
    STREAMS-OPCONN-RECEIPT-BOUNDED
        _sr3c-connector-b SOPCONN.RECEIPT-POLICY !
    1 _sr3c-connector-b SOPCONN.RECEIPT-BYTE-LIMIT !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-connector-b _sr3c-valid-connector!
    STREAMS-OPCONN-RECEIPT-BOUNDED
        _sr3c-connector-b SOPCONN.RECEIPT-POLICY !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    2 ['] SOPCONN.RECEIPT-POLICY _sr3c-connector-field-invalid
    _sr3c-connector-b _sr3c-valid-connector!
    STREAMS-OPCONN-RECEIPT-BOUNDED
        _sr3c-connector-b SOPCONN.RECEIPT-POLICY !
    _SOPREC-MAX-SIGNED
        _sr3c-connector-b SOPCONN.RECEIPT-BYTE-LIMIT !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-connector-lifecycle  ( -- )
    STREAMS-OPCONN-LIFECYCLE-CONFIGURED 0
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert
    STREAMS-OPCONN-LIFECYCLE-ACTIVE 1
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert
    STREAMS-OPCONN-LIFECYCLE-DRAINING 0
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert
    STREAMS-OPCONN-LIFECYCLE-RETIRED 0
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert

    STREAMS-OPCONN-LIFECYCLE-CONFIGURED 1
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPCONN-LIFECYCLE-ACTIVE 0
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPCONN-LIFECYCLE-DRAINING 1
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPCONN-LIFECYCLE-RETIRED 1
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    0 0 _sr3c-connector-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    5 0 _sr3c-connector-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPCONN-LIFECYCLE-ACTIVE 2
        _sr3c-connector-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-connector-bounds  ( -- )
    ['] SOPCONN.CONNECTOR-ID _sr3c-connector-rid-invalid
    ['] SOPCONN.ENDPOINT-ID _sr3c-connector-rid-invalid
    ['] SOPCONN.ENDPOINT-SEAL _sr3c-connector-rid-invalid

    0 ['] SOPCONN.REVISION _sr3c-connector-field-invalid
    0 ['] SOPCONN.PROTOCOL _sr3c-connector-field-invalid
    0 ['] SOPCONN.PROFILE _sr3c-connector-field-invalid
    0 ['] SOPCONN.REQUEST-BYTE-LIMIT _sr3c-connector-field-invalid
    0 ['] SOPCONN.RESPONSE-BYTE-LIMIT _sr3c-connector-field-invalid
    0 ['] SOPCONN.PAYLOAD-BYTE-LIMIT _sr3c-connector-field-invalid
    0 ['] SOPCONN.QUEUE-ITEM-LIMIT _sr3c-connector-field-invalid
    0 ['] SOPCONN.QUEUE-BYTE-LIMIT _sr3c-connector-field-invalid
    0 ['] SOPCONN.CONNECT-TIMEOUT-MS _sr3c-connector-field-invalid
    0 ['] SOPCONN.OPERATION-TIMEOUT-MS
        _sr3c-connector-field-invalid
    0 ['] SOPCONN.IDLE-TIMEOUT-MS _sr3c-connector-field-invalid
    -1 ['] SOPCONN.RETRY-LIMIT _sr3c-connector-field-invalid
    -1 ['] SOPCONN.RETRY-DELAY-MS _sr3c-connector-field-invalid
    -1 ['] SOPCONN.REDIRECT-LIMIT _sr3c-connector-field-invalid
    -1 ['] SOPCONN.CONFIGURED-MS _sr3c-connector-field-invalid
    1 ['] SOPCONN.FLAGS _sr3c-connector-field-invalid

    _SOPREC-MAX-SIGNED ['] SOPCONN.REVISION
        _sr3c-connector-field-valid
    _SOPREC-MAX-SIGNED ['] SOPCONN.RETRY-LIMIT
        _sr3c-connector-field-valid

    _sr3c-connector-b _sr3c-valid-connector!
    4095 _sr3c-connector-b SOPCONN.QUEUE-BYTE-LIMIT !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-connector-b _sr3c-valid-connector!
    4096 _sr3c-connector-b SOPCONN.QUEUE-BYTE-LIMIT !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert

    _sr3c-connector-b _sr3c-valid-connector!
    999 _sr3c-connector-b SOPCONN.OPERATION-TIMEOUT-MS !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-connector-b _sr3c-valid-connector!
    1000 _sr3c-connector-b SOPCONN.OPERATION-TIMEOUT-MS !
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert

    _sr3c-connector-b _sr3c-valid-connector!
    1 _sr3c-connector-b SOPCONN.RESERVED C!
    _sr3c-connector-b STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-flow-policies  ( -- )
    STREAMS-OPFLOW-BACKPRESSURE-REFUSE
        ['] SOPFLOW.BACKPRESSURE-POLICY _sr3c-flow-field-valid
    STREAMS-OPFLOW-BACKPRESSURE-PAUSE
        ['] SOPFLOW.BACKPRESSURE-POLICY _sr3c-flow-field-valid
    0 ['] SOPFLOW.BACKPRESSURE-POLICY _sr3c-flow-field-invalid
    3 ['] SOPFLOW.BACKPRESSURE-POLICY _sr3c-flow-field-invalid

    STREAMS-OPFLOW-FAILURE-TERMINAL
        ['] SOPFLOW.FAILURE-POLICY _sr3c-flow-field-valid
    STREAMS-OPFLOW-FAILURE-REVIEW
        ['] SOPFLOW.FAILURE-POLICY _sr3c-flow-field-valid
    0 ['] SOPFLOW.FAILURE-POLICY _sr3c-flow-field-invalid
    3 ['] SOPFLOW.FAILURE-POLICY _sr3c-flow-field-invalid

    STREAMS-OPFLOW-RETRY-NONE
        ['] SOPFLOW.RETRY-POLICY _sr3c-flow-field-valid
    STREAMS-OPFLOW-RETRY-CONNECTOR-EXACT
        ['] SOPFLOW.RETRY-POLICY _sr3c-flow-field-valid
    -1 ['] SOPFLOW.RETRY-POLICY _sr3c-flow-field-invalid
    2 ['] SOPFLOW.RETRY-POLICY _sr3c-flow-field-invalid
    _sr3c-stack ;

: _sr3c-test-flow-lifecycle  ( -- )
    STREAMS-OPFLOW-LIFECYCLE-CONFIGURED 0 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert
    STREAMS-OPFLOW-LIFECYCLE-ACTIVE 1 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert
    STREAMS-OPFLOW-LIFECYCLE-DRAINING 0 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert
    STREAMS-OPFLOW-LIFECYCLE-RETIRED 0 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-OK = _sr3c-assert

    STREAMS-OPFLOW-LIFECYCLE-CONFIGURED 1 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPFLOW-LIFECYCLE-ACTIVE 0 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPFLOW-LIFECYCLE-DRAINING 1 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPFLOW-LIFECYCLE-RETIRED 1 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    0 0 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    5 0 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    STREAMS-OPFLOW-LIFECYCLE-ACTIVE 2 _sr3c-flow-lifecycle
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-flow-bounds  ( -- )
    ['] SOPFLOW.FLOW-ID _sr3c-flow-rid-invalid
    ['] SOPFLOW.INPUT-CONNECTOR-ID _sr3c-flow-rid-invalid
    ['] SOPFLOW.OUTPUT-CONNECTOR-ID _sr3c-flow-rid-invalid
    ['] SOPFLOW.ROUTE-ID _sr3c-flow-rid-invalid
    ['] SOPFLOW.TRANSFORM-ID _sr3c-flow-rid-invalid

    0 ['] SOPFLOW.REVISION _sr3c-flow-field-invalid
    0 ['] SOPFLOW.INPUT-CONNECTOR-REVISION _sr3c-flow-field-invalid
    0 ['] SOPFLOW.OUTPUT-CONNECTOR-REVISION _sr3c-flow-field-invalid
    0 ['] SOPFLOW.ROUTE-REVISION _sr3c-flow-field-invalid
    0 ['] SOPFLOW.TRANSFORM-REVISION _sr3c-flow-field-invalid
    0 ['] SOPFLOW.PAYLOAD-BYTE-LIMIT _sr3c-flow-field-invalid
    0 ['] SOPFLOW.OUTPUT-BYTE-LIMIT _sr3c-flow-field-invalid
    0 ['] SOPFLOW.IN-FLIGHT-LIMIT _sr3c-flow-field-invalid
    0 ['] SOPFLOW.TRANSFORM-STEP-LIMIT _sr3c-flow-field-invalid
    0 ['] SOPFLOW.TIMEOUT-MS _sr3c-flow-field-invalid
    -1 ['] SOPFLOW.CONFIGURED-MS _sr3c-flow-field-invalid
    1 ['] SOPFLOW.FLAGS _sr3c-flow-field-invalid
    _SOPREC-MAX-SIGNED ['] SOPFLOW.REVISION _sr3c-flow-field-valid
    _SOPREC-MAX-SIGNED ['] SOPFLOW.TRANSFORM-STEP-LIMIT
        _sr3c-flow-field-valid

    _sr3c-flow-b _sr3c-valid-flow!
    1 _sr3c-flow-b SOPFLOW.RESERVED C!
    _sr3c-flow-b STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-canonical-checkpoint  ( -- )
    _sr3c-checkpoint-a _sr3c-valid-checkpoint!
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-U @ 0= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-BLOB
        PBLOB-VALID? _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-BLOB
        PBLOB-TOTAL@ 0= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-BLOB
        PBLOB-CHUNK-COUNT@ 0= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-BLOB
        PBLOB-LEVEL@ -1 = _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-BLOB
        PBLOB-ROOT@ 0= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-BLOB _PBL.FLAGS @
        0= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.CURSOR-BLOB _PBL.RESERVED @
        0= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.PRIOR-CHECKPOINT-ID
        RID-ZERO? _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.FLAGS @ 0= _sr3c-assert
    _sr3c-checkpoint-a SOPCHECKPOINT.ORDER @ 1 = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-checkpoint-prior-chain  ( -- )
    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    _sr3c-rid-e
        _sr3c-checkpoint-b SOPCHECKPOINT.PRIOR-CHECKPOINT-ID RID-COPY
    STREAMS-OPCHECKPOINT-F-HAS-PRIOR
        _sr3c-checkpoint-b SOPCHECKPOINT.FLAGS !
    2 _sr3c-checkpoint-b SOPCHECKPOINT.ORDER !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-OK = _sr3c-assert

    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    2 _sr3c-checkpoint-b SOPCHECKPOINT.ORDER !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert

    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    _sr3c-rid-e
        _sr3c-checkpoint-b SOPCHECKPOINT.PRIOR-CHECKPOINT-ID RID-COPY
    STREAMS-OPCHECKPOINT-F-HAS-PRIOR
        _sr3c-checkpoint-b SOPCHECKPOINT.FLAGS !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert

    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    STREAMS-OPCHECKPOINT-F-HAS-PRIOR
        _sr3c-checkpoint-b SOPCHECKPOINT.FLAGS !
    2 _sr3c-checkpoint-b SOPCHECKPOINT.ORDER !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert

    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    _sr3c-rid-a
        _sr3c-checkpoint-b SOPCHECKPOINT.PRIOR-CHECKPOINT-ID RID-COPY
    STREAMS-OPCHECKPOINT-F-HAS-PRIOR
        _sr3c-checkpoint-b SOPCHECKPOINT.FLAGS !
    2 _sr3c-checkpoint-b SOPCHECKPOINT.ORDER !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert

    2 ['] SOPCHECKPOINT.FLAGS _sr3c-checkpoint-field-invalid
    3 ['] SOPCHECKPOINT.FLAGS _sr3c-checkpoint-field-invalid
    _sr3c-stack ;

: _sr3c-test-checkpoint-bounds  ( -- )
    ['] SOPCHECKPOINT.CHECKPOINT-ID _sr3c-checkpoint-rid-invalid
    ['] SOPCHECKPOINT.CONNECTOR-ID _sr3c-checkpoint-rid-invalid
    ['] SOPCHECKPOINT.FLOW-ID _sr3c-checkpoint-rid-invalid
    ['] SOPCHECKPOINT.CURSOR-DIGEST _sr3c-checkpoint-rid-invalid

    0 ['] SOPCHECKPOINT.CONNECTOR-REVISION
        _sr3c-checkpoint-field-invalid
    0 ['] SOPCHECKPOINT.FLOW-REVISION
        _sr3c-checkpoint-field-invalid
    0 ['] SOPCHECKPOINT.RECORD-REVISION
        _sr3c-checkpoint-field-invalid
    0 ['] SOPCHECKPOINT.ORDER _sr3c-checkpoint-field-invalid
    -1 ['] SOPCHECKPOINT.COMMITTED-MS
        _sr3c-checkpoint-field-invalid
    -1 ['] SOPCHECKPOINT.CURSOR-U _sr3c-checkpoint-field-invalid
    _SOPREC-MAX-SIGNED ['] SOPCHECKPOINT.RECORD-REVISION
        _sr3c-checkpoint-field-valid
    _SOPREC-MAX-SIGNED ['] SOPCHECKPOINT.COMMITTED-MS
        _sr3c-checkpoint-field-valid

    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    1 _sr3c-checkpoint-b SOPCHECKPOINT.CURSOR-U !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    0 _sr3c-checkpoint-b SOPCHECKPOINT.CURSOR-BLOB _PBL.MAGIC !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-checkpoint-b _sr3c-valid-checkpoint!
    1 _sr3c-checkpoint-b SOPCHECKPOINT.RESERVED C!
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SEAL
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-connector-seal-copy-header  ( -- )
    0 STREAMS-OPCONN-SIZE STREAMS-OPCONN-VALID? 0= _sr3c-assert
    -1 STREAMS-OPCONN-SIZE STREAMS-OPCONN-VALID? 0= _sr3c-assert
    _sr3c-connector-a _sr3c-valid-connector!
    _sr3c-connector-a _sr3c-connector-b STREAMS-OPCONN-COPY
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-connector-a STREAMS-OPCONN-SIZE
    _sr3c-connector-b STREAMS-OPCONN-SIZE
        COMPARE 0= _sr3c-assert

    _sr3c-connector-b SOPCONN.REVISION
        DUP C@ 1 XOR SWAP C!
    _sr3c-connector-b STREAMS-OPCONN-SIZE
        STREAMS-OPCONN-VALID? 0= _sr3c-assert
    _sr3c-connector-c STREAMS-OPCONN-SIZE 0xA5 FILL
    _sr3c-connector-c _sr3c-connector-snapshot
        STREAMS-OPCONN-SIZE MOVE
    _sr3c-connector-b _sr3c-connector-c STREAMS-OPCONN-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-connector-c STREAMS-OPCONN-SIZE
    _sr3c-connector-snapshot STREAMS-OPCONN-SIZE
        COMPARE 0= _sr3c-assert

    _sr3c-connector-a _sr3c-connector-snapshot
        STREAMS-OPCONN-SIZE MOVE
    _sr3c-connector-a _sr3c-connector-a STREAMS-OPCONN-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-connector-a STREAMS-OPCONN-SIZE
    _sr3c-connector-snapshot STREAMS-OPCONN-SIZE
        COMPARE 0= _sr3c-assert
    _sr3c-connector-a _sr3c-connector-a 8 + STREAMS-OPCONN-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-connector-a STREAMS-OPCONN-SIZE
    _sr3c-connector-snapshot STREAMS-OPCONN-SIZE
        COMPARE 0= _sr3c-assert
    _sr3c-connector-a 0 STREAMS-OPCONN-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert

    _sr3c-connector-a _sr3c-connector-b STREAMS-OPCONN-SIZE MOVE
    STREAMS-OPREC-SHAPE-CURRENT 1+
        _sr3c-connector-b SOPREC.SHAPE !
    _sr3c-connector-b STREAMS-OPCONN-SIZE
        STREAMS-OPCONN-HEADER-CLASSIFY
        STREAMS-OPREC-S-UNKNOWN = _sr3c-assert
    0 _sr3c-connector-b SOPREC.SHAPE !
    _sr3c-connector-b STREAMS-OPCONN-SIZE
        STREAMS-OPCONN-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3c-assert
    _sr3c-connector-a STREAMS-OPCONN-SIZE 1-
        STREAMS-OPCONN-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3c-assert
    0 STREAMS-OPCONN-SIZE STREAMS-OPCONN-HEADER-CLASSIFY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-flow-seal-copy-header  ( -- )
    0 STREAMS-OPFLOW-SIZE STREAMS-OPFLOW-VALID? 0= _sr3c-assert
    -1 STREAMS-OPFLOW-SIZE STREAMS-OPFLOW-VALID? 0= _sr3c-assert
    _sr3c-flow-a _sr3c-valid-flow!
    _sr3c-flow-a _sr3c-flow-b STREAMS-OPFLOW-COPY
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-flow-a STREAMS-OPFLOW-SIZE
    _sr3c-flow-b STREAMS-OPFLOW-SIZE
        COMPARE 0= _sr3c-assert

    _sr3c-flow-b SOPFLOW.REVISION DUP C@ 1 XOR SWAP C!
    _sr3c-flow-b STREAMS-OPFLOW-SIZE
        STREAMS-OPFLOW-VALID? 0= _sr3c-assert
    _sr3c-flow-c STREAMS-OPFLOW-SIZE 0xA5 FILL
    _sr3c-flow-c _sr3c-flow-snapshot STREAMS-OPFLOW-SIZE MOVE
    _sr3c-flow-b _sr3c-flow-c STREAMS-OPFLOW-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-flow-c STREAMS-OPFLOW-SIZE
    _sr3c-flow-snapshot STREAMS-OPFLOW-SIZE
        COMPARE 0= _sr3c-assert

    _sr3c-flow-a _sr3c-flow-snapshot STREAMS-OPFLOW-SIZE MOVE
    _sr3c-flow-a _sr3c-flow-a STREAMS-OPFLOW-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-flow-a _sr3c-flow-a 8 + STREAMS-OPFLOW-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-flow-a STREAMS-OPFLOW-SIZE
    _sr3c-flow-snapshot STREAMS-OPFLOW-SIZE
        COMPARE 0= _sr3c-assert
    _sr3c-flow-a 0 STREAMS-OPFLOW-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert

    _sr3c-flow-a _sr3c-flow-b STREAMS-OPFLOW-SIZE MOVE
    STREAMS-OPREC-SHAPE-CURRENT 1+ _sr3c-flow-b SOPREC.SHAPE !
    _sr3c-flow-b STREAMS-OPFLOW-SIZE STREAMS-OPFLOW-HEADER-CLASSIFY
        STREAMS-OPREC-S-UNKNOWN = _sr3c-assert
    0 _sr3c-flow-b SOPREC.SHAPE !
    _sr3c-flow-b STREAMS-OPFLOW-SIZE STREAMS-OPFLOW-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3c-assert
    _sr3c-flow-a STREAMS-OPFLOW-SIZE 1-
        STREAMS-OPFLOW-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3c-assert
    0 STREAMS-OPFLOW-SIZE STREAMS-OPFLOW-HEADER-CLASSIFY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _sr3c-test-checkpoint-seal-copy-header  ( -- )
    0 STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-VALID? 0= _sr3c-assert
    -1 STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-VALID? 0= _sr3c-assert
    _sr3c-checkpoint-a _sr3c-valid-checkpoint!
    _sr3c-checkpoint-a _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-COPY
        STREAMS-OPREC-S-OK = _sr3c-assert
    _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-SIZE
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SIZE
        COMPARE 0= _sr3c-assert

    _sr3c-checkpoint-b SOPCHECKPOINT.RECORD-REVISION
        DUP C@ 1 XOR SWAP C!
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-VALID? 0= _sr3c-assert
    _sr3c-checkpoint-c STREAMS-OPCHECKPOINT-SIZE 0xA5 FILL
    _sr3c-checkpoint-c _sr3c-checkpoint-snapshot
        STREAMS-OPCHECKPOINT-SIZE MOVE
    _sr3c-checkpoint-b _sr3c-checkpoint-c STREAMS-OPCHECKPOINT-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-checkpoint-c STREAMS-OPCHECKPOINT-SIZE
    _sr3c-checkpoint-snapshot STREAMS-OPCHECKPOINT-SIZE
        COMPARE 0= _sr3c-assert

    _sr3c-checkpoint-a _sr3c-checkpoint-snapshot
        STREAMS-OPCHECKPOINT-SIZE MOVE
    _sr3c-checkpoint-a _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-checkpoint-a _sr3c-checkpoint-a 8 +
        STREAMS-OPCHECKPOINT-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-SIZE
    _sr3c-checkpoint-snapshot STREAMS-OPCHECKPOINT-SIZE
        COMPARE 0= _sr3c-assert
    _sr3c-checkpoint-a 0 STREAMS-OPCHECKPOINT-COPY
        STREAMS-OPREC-S-INVALID = _sr3c-assert

    _sr3c-checkpoint-a _sr3c-checkpoint-b
        STREAMS-OPCHECKPOINT-SIZE MOVE
    STREAMS-OPREC-SHAPE-CURRENT 1+
        _sr3c-checkpoint-b SOPREC.SHAPE !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-HEADER-CLASSIFY
        STREAMS-OPREC-S-UNKNOWN = _sr3c-assert
    0 _sr3c-checkpoint-b SOPREC.SHAPE !
    _sr3c-checkpoint-b STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3c-assert
    _sr3c-checkpoint-a STREAMS-OPCHECKPOINT-SIZE 1-
        STREAMS-OPCHECKPOINT-HEADER-CLASSIFY
        STREAMS-OPREC-S-CORRUPT = _sr3c-assert
    0 STREAMS-OPCHECKPOINT-SIZE
        STREAMS-OPCHECKPOINT-HEADER-CLASSIFY
        STREAMS-OPREC-S-INVALID = _sr3c-assert
    _sr3c-stack ;

: _SR3C-RUN  ( -- )
    0 _sr3c-fails !
    0 _sr3c-checks !
    DEPTH _sr3c-depth !
    _sr3c-setup-identities
    _sr3c-stack
    _sr3c-test-geometry-and-defaults
    _sr3c-test-valid-construction
    _sr3c-test-connector-policies
    _sr3c-test-connector-lifecycle
    _sr3c-test-connector-bounds
    _sr3c-test-flow-policies
    _sr3c-test-flow-lifecycle
    _sr3c-test-flow-bounds
    _sr3c-test-canonical-checkpoint
    _sr3c-test-checkpoint-prior-chain
    _sr3c-test-checkpoint-bounds
    _sr3c-test-connector-seal-copy-header
    _sr3c-test-flow-seal-copy-header
    _sr3c-test-checkpoint-seal-copy-header
    _sr3c-stack
    _sr3c-fails @ 0= IF
        ." STREAMS SR3 CONFIG PASS" CR
    ELSE
        ." STREAMS SR3 CONFIG FAIL " _sr3c-fails @ . CR
    THEN ;
