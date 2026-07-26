\ streams-sr3-delivery.f - Focused SR3 Landing 2 delivery evidence
\
\ This deterministic one-core fixture qualifies the current prerelease
\ delivery lifecycle only.  It uses public spool operations for selection,
\ activation, exact payload readback, terminal evidence, safe requeue, and
\ cold recovery; it carries no compatibility or alternate-format path.

PROVIDED akashic-sr3-delivery-gate

VARIABLE _sr3d-fails
VARIABLE _sr3d-checks
VARIABLE _sr3d-depth
VARIABLE _sr3d-arena
VARIABLE _sr3d-vfs
VARIABLE _sr3d-ior
VARIABLE _sr3d-old-vfs
VARIABLE _sr3d-source-calls
VARIABLE _sr3d-sink-bytes
VARIABLE _sr3d-current-spool
VARIABLE _sr3d-current-work
VARIABLE _sr3d-mode
VARIABLE _sr3d-revision
VARIABLE _sr3d-target
VARIABLE _sr3d-payload-a
VARIABLE _sr3d-seed
VARIABLE _sr3d-old-generation

CREATE _sr3d-ops VFS-OPS-SIZE ALLOT
CREATE _sr3d-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _sr3d-identity PERSIST-IDENTITY-SIZE ALLOT

CREATE _sr3d-store-a PSTORE-SIZE ALLOT
CREATE _sr3d-store-b PSTORE-SIZE ALLOT
CREATE _sr3d-pwork-a PSTORE-WORK-SIZE ALLOT
CREATE _sr3d-pwork-b PSTORE-WORK-SIZE ALLOT
CREATE _sr3d-record-buffer-a STREAMS-SPOOL-RECORD-BUFFER-MIN ALLOT
CREATE _sr3d-record-buffer-b STREAMS-SPOOL-RECORD-BUFFER-MIN ALLOT
GUARD _sr3d-guard-a
GUARD _sr3d-guard-b

CREATE _sr3d-spool-a STREAMS-SPOOL-SIZE ALLOT
CREATE _sr3d-spool-b STREAMS-SPOOL-SIZE ALLOT
CREATE _sr3d-work-a STREAMS-SPOOL-WORK-SIZE ALLOT
CREATE _sr3d-work-b STREAMS-SPOOL-WORK-SIZE ALLOT

\ The 4 MiB RAM VFS bounds both page banks.  Cold audit memory covers the
\ fixture's maximum of two connectors, two flows, and three attempts.
4194304 PERSIST-PAGE-FILE-SIZE /
    2 2 3 STREAMS-SPOOL-COLD-AUDIT-BYTES?
STREAMS-SPOOL-S-OK <> [IF]
    ." STREAMS SR3 DELIVERY AUDIT GEOMETRY" CR ABORT
[THEN]
CONSTANT _sr3d-cold-audit-u

CREATE _sr3d-cold-audit-a-storage _sr3d-cold-audit-u 7 + ALLOT
_sr3d-cold-audit-a-storage 7 + 7 INVERT AND
    CONSTANT _sr3d-cold-audit-a
CREATE _sr3d-cold-audit-b-storage _sr3d-cold-audit-u 7 + ALLOT
_sr3d-cold-audit-b-storage 7 + 7 INVERT AND
    CONSTANT _sr3d-cold-audit-b

CREATE _sr3d-authority RID-SIZE ALLOT
CREATE _sr3d-exact-connector-id RID-SIZE ALLOT
CREATE _sr3d-exact-flow-id RID-SIZE ALLOT
CREATE _sr3d-exact-endpoint-id RID-SIZE ALLOT
CREATE _sr3d-exact-endpoint-seal RID-SIZE ALLOT
CREATE _sr3d-exact-route-id RID-SIZE ALLOT
CREATE _sr3d-exact-transform-id RID-SIZE ALLOT
CREATE _sr3d-unsafe-connector-id RID-SIZE ALLOT
CREATE _sr3d-unsafe-flow-id RID-SIZE ALLOT
CREATE _sr3d-unsafe-endpoint-id RID-SIZE ALLOT
CREATE _sr3d-unsafe-endpoint-seal RID-SIZE ALLOT
CREATE _sr3d-unsafe-route-id RID-SIZE ALLOT
CREATE _sr3d-unsafe-transform-id RID-SIZE ALLOT
CREATE _sr3d-origin-id RID-SIZE ALLOT
CREATE _sr3d-ack-id RID-SIZE ALLOT
CREATE _sr3d-delivery-id RID-SIZE ALLOT

CREATE _sr3d-exact-connector STREAMS-OPCONN-SIZE ALLOT
CREATE _sr3d-exact-flow STREAMS-OPFLOW-SIZE ALLOT
CREATE _sr3d-unsafe-connector STREAMS-OPCONN-SIZE ALLOT
CREATE _sr3d-unsafe-flow STREAMS-OPFLOW-SIZE ALLOT
CREATE _sr3d-request STREAMS-SPOOL-REQUEST-SIZE ALLOT
CREATE _sr3d-result-exact STREAMS-SPOOL-RESULT-SIZE ALLOT
CREATE _sr3d-result-unsafe STREAMS-SPOOL-RESULT-SIZE ALLOT
CREATE _sr3d-result-stale STREAMS-SPOOL-RESULT-SIZE ALLOT
CREATE _sr3d-result-cleanup STREAMS-SPOOL-RESULT-SIZE ALLOT
CREATE _sr3d-ready STREAMS-OPATT-SIZE ALLOT
CREATE _sr3d-attempt STREAMS-OPATT-SIZE ALLOT
CREATE _sr3d-completion STREAMS-SPOOL-COMPLETION-SIZE ALLOT
CREATE _sr3d-receipt STREAMS-OPRECEIPT-SIZE ALLOT
CREATE _sr3d-capacity STREAMS-SPOOL-CAPACITY-SIZE ALLOT
CREATE _sr3d-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE ALLOT

CREATE _sr3d-payload-exact 4 ALLOT
CREATE _sr3d-payload-unsafe 4 ALLOT
CREATE _sr3d-payload-stale 4 ALLOT
CREATE _sr3d-remote 6 ALLOT
CREATE _sr3d-readback 64 ALLOT

STREAMS-OPATT-SIZE PBLOB-CHUNK-SIZE MAX
    CONSTANT _sr3d-segment-payload-max

: _sr3d-assert  ( flag -- )
    1 _sr3d-checks +!
    0= IF
        1 _sr3d-fails +!
        ." STREAMS SR3 DELIVERY ASSERT " _sr3d-checks @ . CR
    THEN ;

: _sr3d-stack  ( -- )
    DEPTH DUP _sr3d-depth @ <> IF
        ." STREAMS SR3 DELIVERY STACK "
        _sr3d-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr3d-depth @ = _sr3d-assert ;

: _sr3d-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS SR3 DELIVERY STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _sr3d-assert _sr3d-stack ;

: _sr3d-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _sr3d-rid-fill  ( byte rid -- )
    RID-SIZE ROT FILL ;

\ Exact bounded source contract shared by admission and remote evidence.
: _sr3d-source
  ( logical-offset destination requested-u context -- actual-u status )
    >R
    1 _sr3d-source-calls +!
    2 PICK R@ + 2 PICK 2 PICK MOVE
    NIP NIP PERSIST-S-OK
    R> DROP ;

\ Public stream sink used for payload and receipt evidence readback.
: _sr3d-sink
  ( logical-offset payload-a payload-u context -- status )
    >R
    2 PICK _sr3d-sink-bytes @ <> IF
        2DROP DROP R> DROP PERSIST-S-CORRUPT EXIT
    THEN
    OVER 3 PICK R@ + 2 PICK MOVE
    DUP _sr3d-sink-bytes +!
    2DROP DROP
    PERSIST-S-OK
    R> DROP ;

: _sr3d-setup-vfs  ( -- )
    VFS-CUR _sr3d-old-vfs !
    VFS-RAM-OPS _sr3d-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _sr3d-binding VFS-BINDING-DESC-SIZE MOVE
    _sr3d-ops _sr3d-binding VB.OPS !
    4194304 A-XMEM ARENA-NEW
    DUP 0= _sr3d-assert DROP _sr3d-arena !
    _sr3d-arena @ _sr3d-binding 0 VFS-NEW
    _sr3d-ior ! _sr3d-vfs !
    _sr3d-ior @ 0= _sr3d-assert
    _sr3d-vfs @ 0<> _sr3d-assert
    _sr3d-identity PERSIST-IDENTITY-SIZE 0x19 FILL ;

: _sr3d-setup-bytes  ( -- )
    _sr3d-identity _sr3d-authority RID-COPY
    0x21 _sr3d-exact-connector-id _sr3d-rid-fill
    0x22 _sr3d-exact-flow-id _sr3d-rid-fill
    0x23 _sr3d-exact-endpoint-id _sr3d-rid-fill
    0x24 _sr3d-exact-endpoint-seal _sr3d-rid-fill
    0x25 _sr3d-exact-route-id _sr3d-rid-fill
    0x26 _sr3d-exact-transform-id _sr3d-rid-fill
    0x31 _sr3d-unsafe-connector-id _sr3d-rid-fill
    0x32 _sr3d-unsafe-flow-id _sr3d-rid-fill
    0x33 _sr3d-unsafe-endpoint-id _sr3d-rid-fill
    0x34 _sr3d-unsafe-endpoint-seal _sr3d-rid-fill
    0x35 _sr3d-unsafe-route-id _sr3d-rid-fill
    0x36 _sr3d-unsafe-transform-id _sr3d-rid-fill
    0x41 _sr3d-origin-id _sr3d-rid-fill
    0xA1 _sr3d-ack-id _sr3d-rid-fill
    0xA2 _sr3d-delivery-id _sr3d-rid-fill
    _sr3d-payload-exact 4 0x51 FILL
    _sr3d-payload-unsafe 4 0x61 FILL
    _sr3d-payload-stale 4 0x71 FILL
    _sr3d-remote 4 0x81 FILL
    _sr3d-remote 4 + 2 0x91 FILL ;

: _sr3d-store-a-init  ( -- status )
    S" /s3d-p" S" /s3d-s" S" /s3d-ra" S" /s3d-rb"
    _sr3d-identity _sr3d-segment-payload-max _sr3d-vfs @ 0 0
    _sr3d-guard-a 0 0 _sr3d-store-a PSTORE-INIT ;

: _sr3d-store-b-init  ( -- status )
    S" /s3d-p" S" /s3d-s" S" /s3d-ra" S" /s3d-rb"
    _sr3d-identity _sr3d-segment-payload-max _sr3d-vfs @ 0 0
    _sr3d-guard-b 0 0 _sr3d-store-b PSTORE-INIT ;

: _sr3d-use-a  ( -- )
    _sr3d-spool-a _sr3d-current-spool !
    _sr3d-work-a _sr3d-current-work ! ;

: _sr3d-use-b  ( -- )
    _sr3d-spool-b _sr3d-current-spool !
    _sr3d-work-b _sr3d-current-work ! ;

: _sr3d-bind-a  ( -- status )
    _sr3d-use-a
    _sr3d-store-a-init DUP IF EXIT THEN DROP
    _sr3d-record-buffer-a STREAMS-SPOOL-RECORD-BUFFER-MIN
        _sr3d-pwork-a PSTORE-WORK-INIT DUP IF EXIT THEN DROP
    _sr3d-store-a _sr3d-pwork-a PSTORE-PROVISION DUP IF EXIT THEN DROP
    _sr3d-store-a _sr3d-spool-a STREAMS-SPOOL-INIT DUP IF EXIT THEN DROP
    _sr3d-cold-audit-a _sr3d-cold-audit-u
        _sr3d-pwork-a _sr3d-spool-a _sr3d-work-a
        STREAMS-SPOOL-WORK-INIT DUP IF EXIT THEN DROP
    _sr3d-spool-a _sr3d-work-a STREAMS-SPOOL-OPEN ;

: _sr3d-bind-b  ( -- status )
    _sr3d-use-b
    _sr3d-store-b-init DUP IF EXIT THEN DROP
    _sr3d-record-buffer-b STREAMS-SPOOL-RECORD-BUFFER-MIN
        _sr3d-pwork-b PSTORE-WORK-INIT DUP IF EXIT THEN DROP
    _sr3d-store-b _sr3d-pwork-b PSTORE-PROVISION DUP IF EXIT THEN DROP
    _sr3d-store-b _sr3d-spool-b STREAMS-SPOOL-INIT DUP IF EXIT THEN DROP
    _sr3d-cold-audit-b _sr3d-cold-audit-u
        _sr3d-pwork-b _sr3d-spool-b _sr3d-work-b
        STREAMS-SPOOL-WORK-INIT DUP IF EXIT THEN DROP
    _sr3d-spool-b _sr3d-work-b STREAMS-SPOOL-OPEN ;

: _sr3d-mode-connector-id  ( -- rid )
    _sr3d-mode @ IF
        _sr3d-exact-connector-id
    ELSE
        _sr3d-unsafe-connector-id
    THEN ;

: _sr3d-mode-flow-id  ( -- rid )
    _sr3d-mode @ IF _sr3d-exact-flow-id ELSE _sr3d-unsafe-flow-id THEN ;

: _sr3d-mode-endpoint-id  ( -- rid )
    _sr3d-mode @ IF
        _sr3d-exact-endpoint-id
    ELSE
        _sr3d-unsafe-endpoint-id
    THEN ;

: _sr3d-mode-endpoint-seal  ( -- rid )
    _sr3d-mode @ IF
        _sr3d-exact-endpoint-seal
    ELSE
        _sr3d-unsafe-endpoint-seal
    THEN ;

: _sr3d-mode-route-id  ( -- rid )
    _sr3d-mode @ IF _sr3d-exact-route-id ELSE _sr3d-unsafe-route-id THEN ;

: _sr3d-mode-transform-id  ( -- rid )
    _sr3d-mode @ IF
        _sr3d-exact-transform-id
    ELSE
        _sr3d-unsafe-transform-id
    THEN ;

: _sr3d-config!  ( revision exact? -- )
    _sr3d-mode !
    _sr3d-revision !
    _sr3d-mode @ IF
        _sr3d-exact-connector
    ELSE
        _sr3d-unsafe-connector
    THEN _sr3d-target !
    _sr3d-target @ STREAMS-OPCONN-INIT
        STREAMS-OPREC-S-OK _sr3d-status
    _sr3d-mode-connector-id
        _sr3d-target @ SOPCONN.CONNECTOR-ID RID-COPY
    _sr3d-mode-endpoint-id
        _sr3d-target @ SOPCONN.ENDPOINT-ID RID-COPY
    _sr3d-mode-endpoint-seal
        _sr3d-target @ SOPCONN.ENDPOINT-SEAL RID-COPY
    _sr3d-revision @ _sr3d-target @ SOPCONN.REVISION !
    STREAMS-OPCONN-DIRECTION-EGRESS
        _sr3d-target @ SOPCONN.DIRECTION !
    _sr3d-mode @ IF 101 ELSE 102 THEN
        _sr3d-target @ SOPCONN.PROTOCOL !
    _sr3d-mode @ IF 201 ELSE 202 THEN
        _sr3d-target @ SOPCONN.PROFILE !
    STREAMS-OPCONN-ENDPOINT-PINNED
        _sr3d-target @ SOPCONN.ENDPOINT-POLICY !
    16 _sr3d-target @ SOPCONN.REQUEST-BYTE-LIMIT !
    16 _sr3d-target @ SOPCONN.RESPONSE-BYTE-LIMIT !
    4 _sr3d-target @ SOPCONN.PAYLOAD-BYTE-LIMIT !
    3 _sr3d-target @ SOPCONN.QUEUE-ITEM-LIMIT !
    12 _sr3d-target @ SOPCONN.QUEUE-BYTE-LIMIT !
    _sr3d-mode @ IF 2 ELSE 0 THEN
        _sr3d-target @ SOPCONN.RETRY-LIMIT !
    _sr3d-mode @ IF 5 ELSE 0 THEN
        _sr3d-target @ SOPCONN.RETRY-DELAY-MS !
    0 _sr3d-target @ SOPCONN.REDIRECT-LIMIT !
    100 _sr3d-target @ SOPCONN.CONNECT-TIMEOUT-MS !
    500 _sr3d-target @ SOPCONN.OPERATION-TIMEOUT-MS !
    100 _sr3d-target @ SOPCONN.IDLE-TIMEOUT-MS !
    _sr3d-mode @ IF
        STREAMS-OPCONN-RECEIPT-BOUNDED
        16
    ELSE
        STREAMS-OPCONN-RECEIPT-NONE
        0
    THEN
    _sr3d-target @ SOPCONN.RECEIPT-BYTE-LIMIT !
    _sr3d-target @ SOPCONN.RECEIPT-POLICY !
    _sr3d-mode @ IF
        STREAMS-OPCONN-IDEMPOTENCY-EXACT
    ELSE
        STREAMS-OPCONN-IDEMPOTENCY-NONE
    THEN _sr3d-target @ SOPCONN.IDEMPOTENCY-POLICY !
    STREAMS-OPCONN-LIFECYCLE-ACTIVE
        _sr3d-target @ SOPCONN.LIFECYCLE !
    1 _sr3d-target @ SOPCONN.ENABLED !
    STREAMS-OPCONN-HEALTH-HEALTHY
        _sr3d-target @ SOPCONN.HEALTH !
    _sr3d-revision @ 1000 *
        _sr3d-target @ SOPCONN.CONFIGURED-MS !
    _sr3d-target @ STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK _sr3d-status

    _sr3d-mode @ IF _sr3d-exact-flow ELSE _sr3d-unsafe-flow THEN
        _sr3d-target !
    _sr3d-target @ STREAMS-OPFLOW-INIT
        STREAMS-OPREC-S-OK _sr3d-status
    _sr3d-mode-flow-id _sr3d-target @ SOPFLOW.FLOW-ID RID-COPY
    _sr3d-mode-connector-id
        _sr3d-target @ SOPFLOW.INPUT-CONNECTOR-ID RID-COPY
    _sr3d-mode-connector-id
        _sr3d-target @ SOPFLOW.OUTPUT-CONNECTOR-ID RID-COPY
    _sr3d-mode-route-id _sr3d-target @ SOPFLOW.ROUTE-ID RID-COPY
    _sr3d-mode-transform-id
        _sr3d-target @ SOPFLOW.TRANSFORM-ID RID-COPY
    _sr3d-revision @ _sr3d-target @ SOPFLOW.REVISION !
    _sr3d-revision @
        _sr3d-target @ SOPFLOW.INPUT-CONNECTOR-REVISION !
    _sr3d-revision @
        _sr3d-target @ SOPFLOW.OUTPUT-CONNECTOR-REVISION !
    1 _sr3d-target @ SOPFLOW.ROUTE-REVISION !
    1 _sr3d-target @ SOPFLOW.TRANSFORM-REVISION !
    4 _sr3d-target @ SOPFLOW.PAYLOAD-BYTE-LIMIT !
    4 _sr3d-target @ SOPFLOW.OUTPUT-BYTE-LIMIT !
    1 _sr3d-target @ SOPFLOW.IN-FLIGHT-LIMIT !
    1000 _sr3d-target @ SOPFLOW.TRANSFORM-STEP-LIMIT !
    500 _sr3d-target @ SOPFLOW.TIMEOUT-MS !
    STREAMS-OPFLOW-BACKPRESSURE-REFUSE
        _sr3d-target @ SOPFLOW.BACKPRESSURE-POLICY !
    STREAMS-OPFLOW-FAILURE-REVIEW
        _sr3d-target @ SOPFLOW.FAILURE-POLICY !
    _sr3d-mode @ IF
        STREAMS-OPFLOW-RETRY-CONNECTOR-EXACT
    ELSE
        STREAMS-OPFLOW-RETRY-NONE
    THEN _sr3d-target @ SOPFLOW.RETRY-POLICY !
    STREAMS-OPFLOW-LIFECYCLE-ACTIVE
        _sr3d-target @ SOPFLOW.LIFECYCLE !
    1 _sr3d-target @ SOPFLOW.ENABLED !
    _sr3d-revision @ 1000 * _sr3d-target @ SOPFLOW.CONFIGURED-MS !
    _sr3d-target @ STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-OK _sr3d-status ;

: _sr3d-put-config  ( exact? -- )
    IF
        _sr3d-exact-connector
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CONNECTOR-PUT
            STREAMS-SPOOL-S-OK _sr3d-status
        _sr3d-exact-flow
    ELSE
        _sr3d-unsafe-connector
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CONNECTOR-PUT
            STREAMS-SPOOL-S-OK _sr3d-status
        _sr3d-unsafe-flow
    THEN
    _sr3d-current-spool @ _sr3d-current-work @
    STREAMS-SPOOL-FLOW-PUT STREAMS-SPOOL-S-OK _sr3d-status ;

: _sr3d-request!
  ( payload-a seed exact? request -- )
    _sr3d-target !
    _sr3d-mode !
    _sr3d-seed !
    _sr3d-payload-a !
    _sr3d-target @ STREAMS-SPOOL-REQUEST-INIT
        STREAMS-SPOOL-S-OK _sr3d-status
    ['] _sr3d-source _sr3d-target @ SPOOLREQ.SOURCE-XT !
    _sr3d-payload-a @ _sr3d-target @ SPOOLREQ.SOURCE-CONTEXT !
    4 _sr3d-target @ SPOOLREQ.PAYLOAD-U !
    1 _sr3d-target @ SPOOLREQ.CONNECTOR-REVISION !
    1 _sr3d-target @ SPOOLREQ.FLOW-REVISION !
    _sr3d-mode @ IF 101 ELSE 102 THEN
        _sr3d-target @ SPOOLREQ.PROTOCOL !
    _sr3d-mode @ IF 201 ELSE 202 THEN
        _sr3d-target @ SPOOLREQ.PROFILE !
    303 _sr3d-target @ SPOOLREQ.MEDIA !
    _sr3d-seed @ 10 *
        _sr3d-target @ SPOOLREQ.RECEIVED-MS !
    _sr3d-seed @ 10 * 1+
        _sr3d-target @ SPOOLREQ.ACCEPTED-MS !
    _sr3d-mode @ IF
        STREAMS-OPATT-IDEMPOTENCY-EXACT
    ELSE
        STREAMS-OPATT-IDEMPOTENCY-NONE
    THEN _sr3d-target @ SPOOLREQ.IDEMPOTENCY-POLICY !
    _sr3d-seed @ _sr3d-target @ SPOOLREQ.EVENT-ID _sr3d-rid-fill
    _sr3d-mode-connector-id
        _sr3d-target @ SPOOLREQ.CONNECTOR-ID RID-COPY
    _sr3d-mode-flow-id _sr3d-target @ SPOOLREQ.FLOW-ID RID-COPY
    _sr3d-seed @ 0x10 +
        _sr3d-target @ SPOOLREQ.CORRELATION-ID _sr3d-rid-fill
    _sr3d-seed @ 0x20 +
        _sr3d-target @ SPOOLREQ.IDEMPOTENCY-ID _sr3d-rid-fill
    _sr3d-origin-id _sr3d-target @ SPOOLREQ.ORIGIN-ID RID-COPY
    _sr3d-mode-endpoint-id
        _sr3d-target @ SPOOLREQ.DESTINATION-ID RID-COPY
    _sr3d-mode-endpoint-seal
        _sr3d-target @ SPOOLREQ.ENDPOINT-SEAL RID-COPY
    _sr3d-payload-a @ 4
        _sr3d-target @ SPOOLREQ.PAYLOAD-DIGEST SHA3-256-HASH
    _sr3d-target @ STREAMS-SPOOL-REQUEST-VALID? _sr3d-assert
    _sr3d-stack ;

: _sr3d-attempt@  ( attempt-id -- status )
    _sr3d-attempt _sr3d-current-spool @ _sr3d-current-work @
    STREAMS-SPOOL-ATTEMPT@ ;

: _sr3d-capacity@  ( -- capacity )
    _sr3d-capacity _sr3d-current-spool @ _sr3d-current-work @
    STREAMS-SPOOL-CAPACITY STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-capacity STREAMS-SPOOL-CAPACITY-VALID? _sr3d-assert
    _sr3d-capacity ;

: _sr3d-payload=  ( attempt-id expected-a -- )
    _sr3d-payload-a !
    _sr3d-readback 64 0xCC FILL
    0 _sr3d-sink-bytes !
    ['] _sr3d-sink _sr3d-readback
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-PAYLOAD-STREAM
        STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-sink-bytes @ 4 = _sr3d-assert
    _sr3d-readback _sr3d-payload-a @ 4 _sr3d-bytes= _sr3d-assert
    _sr3d-stack ;

: _sr3d-receipt-stream=  ( attempt-id -- )
    _sr3d-readback 64 0xCC FILL
    0 _sr3d-sink-bytes !
    ['] _sr3d-sink _sr3d-readback
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-RECEIPT-STREAM
        STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-sink-bytes @ 6 = _sr3d-assert
    _sr3d-readback _sr3d-remote 6 _sr3d-bytes= _sr3d-assert
    _sr3d-stack ;

: _sr3d-check-recovered
  ( attempt-id expected-start exact? -- )
    _sr3d-mode !
    _sr3d-seed !
    _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 3 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-INDETERMINATE =
            _sr3d-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-UNCERTAIN =
            _sr3d-assert
        DUP SOPATT.REASON @ STREAMS-OPATT-REASON-RECOVERED-ACTIVE =
            _sr3d-assert
        DUP SOPATT.STARTED-MS @ _sr3d-seed @ = _sr3d-assert
        DUP SOPATT.FINISHED-MS @ _sr3d-seed @ = _sr3d-assert
        DUP SOPATT.DISPATCH-COUNT @ 1 = _sr3d-assert
        DUP SOPATT.RETRY-COUNT @ 0= _sr3d-assert
        SOPATT.IDEMPOTENCY-POLICY @
            _sr3d-mode @ IF
                STREAMS-OPATT-IDEMPOTENCY-EXACT =
            ELSE
                STREAMS-OPATT-IDEMPOTENCY-NONE =
            THEN _sr3d-assert
    _sr3d-stack ;

: _sr3d-build-completion  ( -- )
    _sr3d-completion STREAMS-SPOOL-COMPLETION-INIT
        STREAMS-SPOOL-S-OK _sr3d-status
    STREAMS-OPATT-STATE-DELIVERED
        _sr3d-completion SPOOLCOMP.STATE !
    STREAMS-OPATT-EFFECT-APPLIED
        _sr3d-completion SPOOLCOMP.EFFECT !
    STREAMS-OPATT-REASON-NONE
        _sr3d-completion SPOOLCOMP.REASON !
    330 _sr3d-completion SPOOLCOMP.FINISHED-MS !
    204 _sr3d-completion SPOOLCOMP.RESULT !
    310 _sr3d-completion SPOOLCOMP.ACKNOWLEDGED-MS !
    320 _sr3d-completion SPOOLCOMP.DELIVERED-MS !
    4 _sr3d-completion SPOOLCOMP.REMOTE-RECEIPT-U !
    2 _sr3d-completion SPOOLCOMP.REMOTE-CORRELATION-U !
    ['] _sr3d-source _sr3d-completion SPOOLCOMP.SOURCE-XT !
    _sr3d-remote _sr3d-completion SPOOLCOMP.SOURCE-CONTEXT !
    _sr3d-ack-id
        _sr3d-completion SPOOLCOMP.ACKNOWLEDGEMENT-ID RID-COPY
    _sr3d-delivery-id
        _sr3d-completion SPOOLCOMP.DELIVERY-ID RID-COPY
    _sr3d-remote 6
        _sr3d-completion SPOOLCOMP.REMOTE-DIGEST SHA3-256-HASH
    _sr3d-completion STREAMS-SPOOL-COMPLETION-VALID? _sr3d-assert
    _sr3d-stack ;

: _sr3d-build-cleanup-failure  ( -- )
    _sr3d-completion STREAMS-SPOOL-COMPLETION-INIT
        STREAMS-SPOOL-S-OK _sr3d-status
    STREAMS-OPATT-STATE-FAILED-BEFORE
        _sr3d-completion SPOOLCOMP.STATE !
    STREAMS-OPATT-EFFECT-NOT-APPLIED
        _sr3d-completion SPOOLCOMP.EFFECT !
    STREAMS-OPATT-REASON-NONE
        _sr3d-completion SPOOLCOMP.REASON !
    77 _sr3d-completion SPOOLCOMP.CLEANUP-ERROR !
    510 _sr3d-completion SPOOLCOMP.FINISHED-MS !
    _sr3d-completion STREAMS-SPOOL-COMPLETION-VALID? _sr3d-assert
    _sr3d-stack ;

: _sr3d-check-completion-contract  ( -- )
    _sr3d-completion STREAMS-SPOOL-COMPLETION-INIT
        STREAMS-SPOOL-S-OK _sr3d-status
    STREAMS-OPATT-STATE-FAILED-BEFORE
        _sr3d-completion SPOOLCOMP.STATE !
    STREAMS-OPATT-EFFECT-NOT-APPLIED
        _sr3d-completion SPOOLCOMP.EFFECT !
    1 _sr3d-completion SPOOLCOMP.FINISHED-MS !
    1 _sr3d-completion SPOOLCOMP.RESULT !
    _sr3d-completion STREAMS-SPOOL-COMPLETION-VALID? 0=
        _sr3d-assert
    0 _sr3d-completion SPOOLCOMP.RESULT !
    _sr3d-completion STREAMS-SPOOL-COMPLETION-VALID?
        _sr3d-assert
    STREAMS-OPATT-REASON-CALLBACK
        _sr3d-completion SPOOLCOMP.REASON !
    -491 _sr3d-completion SPOOLCOMP.DETAIL !
    -4901 _sr3d-completion SPOOLCOMP.ERROR !
    -770 _sr3d-completion SPOOLCOMP.CLEANUP-ERROR !
    _sr3d-completion STREAMS-SPOOL-COMPLETION-VALID?
        _sr3d-assert
    STREAMS-OPATT-STATE-STALE
        _sr3d-completion SPOOLCOMP.STATE !
    STREAMS-OPATT-REASON-STALE
        _sr3d-completion SPOOLCOMP.REASON !
    _sr3d-completion STREAMS-SPOOL-COMPLETION-VALID?
        _sr3d-assert
    STREAMS-OPATT-REASON-RECOVERED-ACTIVE 1+
        _sr3d-completion SPOOLCOMP.REASON !
    _sr3d-completion STREAMS-SPOOL-COMPLETION-VALID? 0=
        _sr3d-assert
    _sr3d-stack ;

: _sr3d-check-receipt  ( -- )
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-receipt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-RECEIPT@
        STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-receipt STREAMS-OPRECEIPT-SIZE
        STREAMS-OPRECEIPT-VALID? _sr3d-assert
    _sr3d-receipt
        DUP SOPRECEIPT.ATTEMPT-ID
            _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID RID=
            _sr3d-assert
        DUP SOPRECEIPT.ACKNOWLEDGEMENT-ID
            _sr3d-ack-id RID= _sr3d-assert
        DUP SOPRECEIPT.DELIVERY-ID
            _sr3d-delivery-id RID= _sr3d-assert
        DUP SOPRECEIPT.ACKNOWLEDGED-MS @ 310 = _sr3d-assert
        DUP SOPRECEIPT.DELIVERED-MS @ 320 = _sr3d-assert
        DUP SOPRECEIPT.RESULT @ 204 = _sr3d-assert
        DUP SOPRECEIPT.REMOTE-RECEIPT-U @ 4 = _sr3d-assert
        DUP SOPRECEIPT.REMOTE-CORRELATION-U @ 2 = _sr3d-assert
        DUP SOPRECEIPT.REMOTE-DIGEST
            _sr3d-completion SPOOLCOMP.REMOTE-DIGEST
            SHA3-256-LEN _sr3d-bytes= _sr3d-assert
        DUP SOPRECEIPT.CONNECTOR-REVISION @ 1 = _sr3d-assert
        DUP SOPRECEIPT.FLOW-REVISION @ 1 = _sr3d-assert
        SOPRECEIPT.PAYLOAD-U @ 4 = _sr3d-assert
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-receipt-stream=
    _sr3d-stack ;

: _sr3d-first-land  ( -- )
    _sr3d-bind-a STREAMS-SPOOL-S-ABSENT _sr3d-status
    _sr3d-authority 3 12 3 50
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-PROVISION STREAMS-SPOOL-S-OK _sr3d-status

    1 -1 _sr3d-config!
    -1 _sr3d-put-config
    1 0 _sr3d-config!
    0 _sr3d-put-config

    _sr3d-payload-exact 1 -1 _sr3d-request _sr3d-request!
    _sr3d-request _sr3d-result-exact
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-result-exact STREAMS-SPOOL-RESULT-VALID? _sr3d-assert

    _sr3d-payload-unsafe 2 0 _sr3d-request _sr3d-request!
    _sr3d-request _sr3d-result-unsafe
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-result-unsafe STREAMS-SPOOL-RESULT-VALID? _sr3d-assert

    _sr3d-ready _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-READY@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-ready SOPATT.ATTEMPT-ID
        _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID RID= _sr3d-assert

    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        1 100 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ACTIVATE STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 2 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-ACTIVE = _sr3d-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-UNCERTAIN =
            _sr3d-assert
        DUP SOPATT.DISPATCH-COUNT @ 1 = _sr3d-assert
        SOPATT.STARTED-MS @ 100 = _sr3d-assert
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-payload-exact _sr3d-payload=

    _sr3d-result-unsafe SPOOLRESULT.ATTEMPT-ID
        1 200 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ACTIVATE STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt SOPATT.STATE @
        STREAMS-OPATT-STATE-ACTIVE = _sr3d-assert
    _sr3d-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 2 = _sr3d-assert
        SPOOLCAP.TERMINAL-COUNT @ 0= _sr3d-assert
    _sr3d-stack ;

: _sr3d-cold-recovery-and-finish  ( -- )
    \ OPEN completes cold proof and durably moves every active row to visible
    \ indeterminate state before returning a usable descriptor.
    _sr3d-bind-b STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID 100 -1
        _sr3d-check-recovered
    _sr3d-result-unsafe SPOOLRESULT.ATTEMPT-ID 200 0
        _sr3d-check-recovered
    _sr3d-capacity@
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3d-assert
        SPOOLCAP.INDETERMINATE-COUNT @ 2 = _sr3d-assert

    \ Exact connector policy permits only the same durable attempt and
    \ idempotency key to return to READY.
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        3 105 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-REQUEUE-SAFE STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.ATTEMPT-ID
            _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID RID=
            _sr3d-assert
        DUP SOPATT.RECORD-REVISION @ 4 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-ACCEPTED = _sr3d-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-UNCERTAIN =
            _sr3d-assert
        DUP SOPATT.DISPATCH-COUNT @ 1 = _sr3d-assert
        SOPATT.RETRY-COUNT @ 1 = _sr3d-assert

    \ The non-exact attempt cannot be retried.  Refusal happens before a
    \ transaction: the store generation and durable attempt are unchanged.
    _sr3d-store-b PSTORE-GENERATION@ _sr3d-old-generation !
    _sr3d-attempt STREAMS-OPATT-SIZE 0xA5 FILL
    _sr3d-result-unsafe SPOOLRESULT.ATTEMPT-ID
        3 205 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-REQUEUE-SAFE
        STREAMS-SPOOL-S-CONFLICT _sr3d-status
    _sr3d-store-b PSTORE-GENERATION@
        _sr3d-old-generation @ = _sr3d-assert
    _sr3d-result-unsafe SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 3 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-INDETERMINATE =
            _sr3d-assert
        SOPATT.RETRY-COUNT @ 0= _sr3d-assert

    _sr3d-ready _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-READY@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-ready SOPATT.ATTEMPT-ID
        _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID RID= _sr3d-assert
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        4 300 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ACTIVATE STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 5 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-ACTIVE = _sr3d-assert
        DUP SOPATT.DISPATCH-COUNT @ 2 = _sr3d-assert
        DUP SOPATT.RETRY-COUNT @ 1 = _sr3d-assert
        SOPATT.STARTED-MS @ 300 = _sr3d-assert
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-payload-exact _sr3d-payload=

    \ A second exact-flow item reaches the per-flow in-flight limit.  This
    \ refusal happens after transaction begin inside activation, so it also
    \ proves that the failed mutation is aborted and the work remains usable.
    _sr3d-payload-stale 3 -1 _sr3d-request _sr3d-request!
    _sr3d-request _sr3d-result-stale
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-store-b PSTORE-GENERATION@ _sr3d-old-generation !
    _sr3d-attempt STREAMS-OPATT-SIZE 0xA5 FILL
    _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID
        1 305 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ACTIVATE
        STREAMS-SPOOL-S-FULL-ITEMS _sr3d-status
    _sr3d-store-b PSTORE-GENERATION@
        _sr3d-old-generation @ = _sr3d-assert
    _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 1 = _sr3d-assert
        SOPATT.STATE @ STREAMS-OPATT-STATE-ACCEPTED = _sr3d-assert
    _sr3d-capacity@
        DUP SPOOLCAP.READY-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 1 = _sr3d-assert
        SPOOLCAP.TERMINAL-COUNT @ 1 = _sr3d-assert

    _sr3d-build-completion
    \ Standalone evidence is well-formed, but acknowledgement before the
    \ durable activation time is cross-record invalid and must not call the
    \ source or mutate the authority.
    299 _sr3d-completion SPOOLCOMP.ACKNOWLEDGED-MS !
    0 _sr3d-source-calls !
    _sr3d-store-b PSTORE-GENERATION@ _sr3d-old-generation !
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        5 _sr3d-completion _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-TERMINALIZE
        STREAMS-SPOOL-S-INVALID _sr3d-status
    _sr3d-source-calls @ 0= _sr3d-assert
    _sr3d-store-b PSTORE-GENERATION@
        _sr3d-old-generation @ = _sr3d-assert
    310 _sr3d-completion SPOOLCOMP.ACKNOWLEDGED-MS !
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        5 _sr3d-completion _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-TERMINALIZE STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-source-calls @ 0> _sr3d-assert
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 6 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-DELIVERED = _sr3d-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-APPLIED = _sr3d-assert
        DUP SOPATT.FLAGS @ STREAMS-OPATT-F-RECEIPT-PRESENT =
            _sr3d-assert
        DUP SOPATT.RECEIPT-ID RID-PRESENT? _sr3d-assert
        SOPATT.FINISHED-MS @ 330 = _sr3d-assert
    \ Exact convergence replay must neither invoke the evidence source nor
    \ allocate a second receipt.
    _sr3d-source-calls @ _sr3d-seed !
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        5 _sr3d-completion _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-TERMINALIZE
        STREAMS-SPOOL-S-REPLAY _sr3d-status
    _sr3d-source-calls @ _sr3d-seed @ = _sr3d-assert
    _sr3d-attempt SOPATT.RECORD-REVISION @ 6 = _sr3d-assert
    _sr3d-check-receipt
    _sr3d-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 3 = _sr3d-assert
        DUP SPOOLCAP.BYTE-COUNT @ 12 = _sr3d-assert
        DUP SPOOLCAP.READY-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 1 = _sr3d-assert
        SPOOLCAP.RECEIPT-BYTES @ 6 = _sr3d-assert
    _sr3d-stack ;

: _sr3d-stale-and-final-cold  ( -- )
    \ The ready item was admitted against revision 1.  Installing revision 2
    \ makes activation consume it into durable STALE truth without dispatch.
    2 -1 _sr3d-config!
    -1 _sr3d-put-config
    _sr3d-ready _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-READY@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-ready SOPATT.ATTEMPT-ID
        _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID RID= _sr3d-assert
    _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID
        1 400 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ACTIVATE STREAMS-SPOOL-S-STALE _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 2 = _sr3d-assert
        DUP SOPATT.CONNECTOR-REVISION @ 1 = _sr3d-assert
        DUP SOPATT.FLOW-REVISION @ 1 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-STALE = _sr3d-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-NOT-APPLIED =
            _sr3d-assert
        DUP SOPATT.REASON @ STREAMS-OPATT-REASON-STALE-CONFIGURATION =
            _sr3d-assert
        DUP SOPATT.DISPATCH-COUNT @ 0= _sr3d-assert
        SOPATT.FINISHED-MS @ 400 = _sr3d-assert
    _sr3d-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 3 = _sr3d-assert
        DUP SPOOLCAP.BYTE-COUNT @ 12 = _sr3d-assert
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 3 = _sr3d-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 1 = _sr3d-assert
        SPOOLCAP.RECEIPT-BYTES @ 6 = _sr3d-assert

    \ A third descriptor is unnecessary: rebinding the inactive A-side
    \ descriptor performs a complete cold audit of the same durable bytes.
    _sr3d-bind-a STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 3 = _sr3d-assert
        DUP SPOOLCAP.BYTE-COUNT @ 12 = _sr3d-assert
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 3 = _sr3d-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 1 = _sr3d-assert
        SPOOLCAP.RECEIPT-BYTES @ 6 = _sr3d-assert
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 6 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-DELIVERED = _sr3d-assert
        SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-APPLIED = _sr3d-assert
    _sr3d-result-unsafe SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt SOPATT.STATE @
        STREAMS-OPATT-STATE-INDETERMINATE = _sr3d-assert
    _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-STALE = _sr3d-assert
        SOPATT.REASON @ STREAMS-OPATT-REASON-STALE-CONFIGURATION =
            _sr3d-assert
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-payload-exact _sr3d-payload=
    _sr3d-check-receipt
    _sr3d-ready _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-READY@ STREAMS-SPOOL-S-NOT-FOUND _sr3d-status
    _sr3d-stack ;

: _sr3d-cleanup-and-final-cold  ( -- )
    \ Terminal-count pressure skips the older pinned indeterminate attempt
    \ and identifies the oldest safe terminal attempt.  A different target
    \ cannot bypass that order while pressure is active.
    330 _sr3d-ready
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP-CANDIDATE@
        STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-ready
        DUP SOPATT.ATTEMPT-ID
            _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID RID=
            _sr3d-assert
        DUP SOPATT.RECORD-REVISION @ 6 = _sr3d-assert
        SOPATT.STATE @ STREAMS-OPATT-STATE-DELIVERED = _sr3d-assert

    _sr3d-store-a PSTORE-GENERATION@ _sr3d-old-generation !
    _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID
        2 330 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP
        STREAMS-SPOOL-S-CONFLICT _sr3d-status
    _sr3d-store-a PSTORE-GENERATION@
        _sr3d-old-generation @ = _sr3d-assert

    \ The selected delivered attempt retires in one publication.  Its
    \ attempt, payload, receipt, idempotency row, and exact retained usage
    \ all leave logical authority together.
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        6 330 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.ATTEMPT-ID
            _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID RID=
            _sr3d-assert
        SOPATT.RECORD-REVISION @ 6 = _sr3d-assert
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-NOT-FOUND _sr3d-status
    0 _sr3d-sink-bytes !
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        ['] _sr3d-sink _sr3d-readback
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-PAYLOAD-STREAM
        STREAMS-SPOOL-S-NOT-FOUND _sr3d-status
    _sr3d-result-exact SPOOLRESULT.ATTEMPT-ID
        _sr3d-receipt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-RECEIPT@
        STREAMS-SPOOL-S-NOT-FOUND _sr3d-status
    _sr3d-exact-connector-id _sr3d-usage
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CONNECTOR-USAGE@
        STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-ITEM-COUNT@
        SWAP 1 = AND _sr3d-assert
    _sr3d-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-PAYLOAD-BYTES@
        SWAP 4 = AND _sr3d-assert
    _sr3d-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.BYTE-COUNT @ 8 = _sr3d-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.RECEIPT-BYTES @ 0= _sr3d-assert
        DUP SPOOLCAP.CLEANUP-FAILED-COUNT @ 0= _sr3d-assert
        SPOOLCAP.UNCOMPACTED-CLEANUP-COUNT @ 1 = _sr3d-assert

    \ With pressure relieved, the stale attempt remains retained until its
    \ configured age expires.  The indeterminate attempt remains pinned.
    400 _sr3d-ready
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP-CANDIDATE@
        STREAMS-SPOOL-S-NOT-FOUND _sr3d-status
    450 _sr3d-ready
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP-CANDIDATE@
        STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-ready SOPATT.ATTEMPT-ID
        _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID RID= _sr3d-assert
    _sr3d-result-unsafe SPOOLRESULT.ATTEMPT-ID
        3 450 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP
        STREAMS-SPOOL-S-CONFLICT _sr3d-status
    _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID
        2 450 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-result-stale SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-NOT-FOUND _sr3d-status

    \ Reusing the newly freed capacity, create a terminal cleanup failure.
    \ ACCEPTED work is rejected before a cleanup transaction, and the later
    \ cleanup error remains an exact pinned terminal count.
    _sr3d-payload-exact 4 -1 _sr3d-request _sr3d-request!
    2 _sr3d-request SPOOLREQ.CONNECTOR-REVISION !
    2 _sr3d-request SPOOLREQ.FLOW-REVISION !
    _sr3d-request STREAMS-SPOOL-REQUEST-VALID? _sr3d-assert
    _sr3d-request _sr3d-result-cleanup
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-store-a PSTORE-GENERATION@ _sr3d-old-generation !
    _sr3d-result-cleanup SPOOLRESULT.ATTEMPT-ID
        1 600 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP
        STREAMS-SPOOL-S-CONFLICT _sr3d-status
    _sr3d-store-a PSTORE-GENERATION@
        _sr3d-old-generation @ = _sr3d-assert
    _sr3d-result-cleanup SPOOLRESULT.ATTEMPT-ID
        1 500 _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-ACTIVATE STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-result-cleanup SPOOLRESULT.ATTEMPT-ID
        2 600 _sr3d-ready
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP
        STREAMS-SPOOL-S-CONFLICT _sr3d-status
    _sr3d-build-cleanup-failure
    _sr3d-result-cleanup SPOOLRESULT.ATTEMPT-ID
        2 _sr3d-completion _sr3d-attempt
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-TERMINALIZE STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.RECORD-REVISION @ 3 = _sr3d-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-FAILED-BEFORE =
            _sr3d-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-NOT-APPLIED =
            _sr3d-assert
        SOPATT.CLEANUP-ERROR @ 77 = _sr3d-assert
    _sr3d-store-a PSTORE-GENERATION@ _sr3d-old-generation !
    _sr3d-result-cleanup SPOOLRESULT.ATTEMPT-ID
        3 600 _sr3d-ready
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP
        STREAMS-SPOOL-S-CONFLICT _sr3d-status
    _sr3d-store-a PSTORE-GENERATION@
        _sr3d-old-generation @ = _sr3d-assert
    600 _sr3d-ready
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CLEANUP-CANDIDATE@
        STREAMS-SPOOL-S-NOT-FOUND _sr3d-status
    _sr3d-exact-connector-id _sr3d-usage
        _sr3d-current-spool @ _sr3d-current-work @
        STREAMS-SPOOL-CONNECTOR-USAGE@
        STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-ITEM-COUNT@
        SWAP 1 = AND _sr3d-assert
    _sr3d-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-PAYLOAD-BYTES@
        SWAP 4 = AND _sr3d-assert
    _sr3d-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.BYTE-COUNT @ 8 = _sr3d-assert
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 0= _sr3d-assert
        DUP SPOOLCAP.CLEANUP-FAILED-COUNT @ 1 = _sr3d-assert
        SPOOLCAP.UNCOMPACTED-CLEANUP-COUNT @ 2 = _sr3d-assert

    \ A fresh descriptor must recompute the reduced live set and preserve the
    \ two pinned attempts; append-only garbage remains truthfully uncompacted.
    _sr3d-bind-b STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-result-unsafe SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-INDETERMINATE =
            _sr3d-assert
        SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-UNCERTAIN =
            _sr3d-assert
    _sr3d-result-cleanup SPOOLRESULT.ATTEMPT-ID
        _sr3d-attempt@ STREAMS-SPOOL-S-OK _sr3d-status
    _sr3d-attempt
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-FAILED-BEFORE =
            _sr3d-assert
        SOPATT.CLEANUP-ERROR @ 77 = _sr3d-assert
    _sr3d-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.BYTE-COUNT @ 8 = _sr3d-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3d-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 1 = _sr3d-assert
        DUP SPOOLCAP.CLEANUP-FAILED-COUNT @ 1 = _sr3d-assert
        SPOOLCAP.UNCOMPACTED-CLEANUP-COUNT @ 2 = _sr3d-assert
    _sr3d-stack ;

: _SR3D-RUN  ( -- )
    0 _sr3d-fails !
    0 _sr3d-checks !
    DEPTH _sr3d-depth !
    0 _sr3d-source-calls !
    0 _sr3d-sink-bytes !

    STREAMS-SPOOL-COMPLETION-SIZE STREAMS-SPOOL-REQUEST-SIZE <=
        _sr3d-assert
    STREAMS-OPRECEIPT-SIZE STREAMS-SPOOL-RECORD-BUFFER-MIN <=
        _sr3d-assert
    _sr3d-check-completion-contract

    _sr3d-setup-vfs
    _sr3d-setup-bytes
    _sr3d-first-land
    _sr3d-cold-recovery-and-finish
    _sr3d-stale-and-final-cold
    _sr3d-cleanup-and-final-cold

    _sr3d-old-vfs @ VFS-USE
    _sr3d-vfs @ VFS-DESTROY
    _sr3d-stack
    _sr3d-fails @ 0= IF
        ." STREAMS SR3 DELIVERY PASS " _sr3d-checks @ . CR
    ELSE
        ." STREAMS SR3 DELIVERY FAIL "
        _sr3d-fails @ . ." /" _sr3d-checks @ . CR
    THEN ;
