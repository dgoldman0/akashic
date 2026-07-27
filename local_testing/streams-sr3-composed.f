\ streams-sr3-composed.f - canonical composed SR2/SR3 cold gate
\
\ This fixture is intentionally split into first-boot and cold-boot entry
\ points.  The host runner carries only serialized MP64FS bytes and three
\ semantic attempt RIDs into a fresh process and dictionary.
\
\ Assumed production bridge surface:
\   STREAMS-OPDISPATCH-INIT
\     ( dispatch -- status )
\   STREAMS-OPDISPATCH-BIND
\     ( spool spool-work pool opflow opconn media dispatch -- status )
\   STREAMS-OPDISPATCH-ENQUEUE
\     ( output-ready-flow accepted-ms spool-result dispatch -- status )
\   STREAMS-OPDISPATCH-DISPATCH
\     ( now-ms dispatch -- status )
\   STREAMS-OPDISPATCH-POLL
\     ( now-ms dispatch -- status )
\   STREAMS-OPDISPATCH-CANCEL
\     ( now-ms dispatch -- status )
\   STREAMS-OPDISPATCH-RELEASE
\     ( dispatch -- status )
\   STREAMS-OPDISPATCH-STATUS@
\   STREAMS-OPDISPATCH-SPOOL-STATUS@
\   STREAMS-OPDISPATCH-FLOW-STATUS@
\     ( dispatch -- status )
\   STREAMS-OPDISPATCH-FLOW@
\     ( dispatch -- flow|0 )
\   STREAMS-OPDISPATCH-ATTEMPT@
\     ( dispatch -- attempt|0 )
\   STREAMS-OPDISPATCH-PAYLOAD-U@
\     ( dispatch -- payload-u|-1 )
\   STREAMS-OPDISPATCH-CLEANUP-ERROR@
\     ( dispatch -- error )
\
\ ENQUEUE consumes an exact SR2 flow while it is OUTPUT-READY and before
\ output START.  A successful DISPATCH acquires a fitting cell, restores the
\ exact durable egress bytes, commits durable ACTIVE truth, and returns before
\ START.  POLL drives START/connector progress and terminal publication.
\ RELEASE is the only successful terminal-cell retirement/pool-release path.

PROVIDED akashic-streams-sr3-composed-contracts

VARIABLE _sr3c-fails
VARIABLE _sr3c-checks
VARIABLE _sr3c-depth
VARIABLE _sr3c-cold?
VARIABLE _sr3c-old-vfs
VARIABLE _sr3c-vfs
VARIABLE _sr3c-arena

: _sr3c-drop3  ( x1 x2 x3 -- ) 2DROP DROP ;

VARIABLE _sr3c-current-spool
VARIABLE _sr3c-current-work
VARIABLE _sr3c-dispatch-ms
VARIABLE _sr3c-remote-mode
VARIABLE _sr3c-remote-starts
VARIABLE _sr3c-remote-polls
VARIABLE _sr3c-remote-cancels
VARIABLE _sr3c-remote-cleanups
VARIABLE _sr3c-local-starts
VARIABLE _sr3c-local-polls
VARIABLE _sr3c-local-cancels
VARIABLE _sr3c-local-cleanups
VARIABLE _sr3c-start-profile
VARIABLE _sr3c-stream-u
VARIABLE _sr3c-stream-target
VARIABLE _sr3c-stream-limit
VARIABLE _sr3c-build-event
VARIABLE _sr3c-build-tag
VARIABLE _sr3c-build-now
VARIABLE _sr3c-build-a
VARIABLE _sr3c-build-u
VARIABLE _sr3c-generation
VARIABLE _sr3c-old-generation
VARIABLE _sr3c-held-flow-a
VARIABLE _sr3c-held-flow-b
VARIABLE _sr3c-held-lease-a
VARIABLE _sr3c-held-lease-b
VARIABLE _sr3c-cb-event
VARIABLE _sr3c-cb-op
VARIABLE _sr3c-cb-result
VARIABLE _sr3c-enqueue-result
VARIABLE _sr3c-enqueue-id
VARIABLE _sr3c-expected-state
VARIABLE _sr3c-expected-effect
VARIABLE _sr3c-expected-profile
VARIABLE _sr3c-expected-poll-status
VARIABLE _sr3c-starts-before
VARIABLE _sr3c-generation-before

0 CONSTANT _SR3C-REMOTE-DELIVER
1 CONSTANT _SR3C-REMOTE-FAIL-SIGNED

/BLOCK-DEVICE XBUF _sr3c-bd
/VOLUME XBUF _sr3c-volume

PSTORE-SIZE XBUF _sr3c-store
PSTORE-WORK-SIZE XBUF _sr3c-pstore-work
STREAMS-SPOOL-RECORD-BUFFER-MIN XBUF _sr3c-record-buffer
GUARD _sr3c-guard
PERSIST-PAGE-FILE-SIZE XBUF _sr3c-bank1-page
PSEG-FILE-SIZE XBUF _sr3c-bank1-segment
STREAMS-SPOOL-SIZE XBUF _sr3c-spool
STREAMS-SPOOL-WORK-SIZE XBUF _sr3c-spool-work

PSTORE-SIZE XBUF _sr3c-builder-store
PSTORE-WORK-SIZE XBUF _sr3c-builder-pstore-work
STREAMS-SPOOL-RECORD-BUFFER-MIN XBUF _sr3c-builder-record-buffer
GUARD _sr3c-builder-guard
STREAMS-SPOOL-SIZE XBUF _sr3c-builder-spool
STREAMS-SPOOL-WORK-SIZE XBUF _sr3c-builder-spool-work

STREAMS-SPOOL-COMPACTION-CONTEXT-SIZE
    XBUF _sr3c-compaction-context
PCOMPACT-SIZE XBUF _sr3c-compaction
PCOMPACT-WORK-SIZE XBUF _sr3c-compaction-work
512 XBUF _sr3c-compaction-buffer
PERSIST-PAGE-WORK-SIZE XBUF _sr3c-page-size-work
PSEG-WORK-SIZE XBUF _sr3c-segment-size-work
512 XBUF _sr3c-segment-size-buffer
VARIABLE _sr3c-compaction-steps

4194304 PERSIST-PAGE-FILE-SIZE /
    2 1 3 STREAMS-SPOOL-COLD-AUDIT-BYTES?
STREAMS-SPOOL-S-OK <> [IF]
    ." STREAMS SR3 COMPOSED AUDIT GEOMETRY" CR ABORT
[THEN]
CONSTANT _sr3c-cold-audit-u
_sr3c-cold-audit-u XBUF _sr3c-cold-audit

STREAMS-OPDISPATCH-SIZE XBUF _sr3c-dispatch

STREAMS-OPCONN-SIZE XBUF _sr3c-local-opconn
STREAMS-OPCONN-SIZE XBUF _sr3c-remote-opconn
STREAMS-OPFLOW-SIZE XBUF _sr3c-opflow

STREAMS-SPOOL-RESULT-SIZE XBUF _sr3c-result-delivered
STREAMS-SPOOL-RESULT-SIZE XBUF _sr3c-result-failure
STREAMS-SPOOL-RESULT-SIZE XBUF _sr3c-result-large
STREAMS-SPOOL-RESULT-SIZE XBUF _sr3c-result-refused
STREAMS-OPATT-SIZE XBUF _sr3c-ready
STREAMS-OPATT-SIZE XBUF _sr3c-attempt
STREAMS-OPATT-SIZE XBUF _sr3c-attempt-before
STREAMS-OPRECEIPT-SIZE XBUF _sr3c-receipt
STREAMS-SPOOL-CAPACITY-SIZE XBUF _sr3c-capacity
STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE XBUF _sr3c-connector-usage
STREAMS-OI-FLOW-USAGE-VALUE-SIZE XBUF _sr3c-flow-usage

CREATE _sr3c-identity RID-SIZE ALLOT
CREATE _sr3c-authority RID-SIZE ALLOT
CREATE _sr3c-local-id RID-SIZE ALLOT
CREATE _sr3c-local-endpoint RID-SIZE ALLOT
CREATE _sr3c-local-seal RID-SIZE ALLOT
CREATE _sr3c-remote-id RID-SIZE ALLOT
CREATE _sr3c-remote-endpoint RID-SIZE ALLOT
CREATE _sr3c-remote-seal RID-SIZE ALLOT
CREATE _sr3c-flow-id RID-SIZE ALLOT
CREATE _sr3c-route-id RID-SIZE ALLOT
CREATE _sr3c-transform-id RID-SIZE ALLOT
CREATE _sr3c-producer-input-id RID-SIZE ALLOT
CREATE _sr3c-producer-input-endpoint RID-SIZE ALLOT
CREATE _sr3c-producer-flow-id RID-SIZE ALLOT
CREATE _sr3c-current-id RID-SIZE ALLOT
CREATE _sr3c-delivered-id RID-SIZE ALLOT
CREATE _sr3c-failure-id RID-SIZE ALLOT
CREATE _sr3c-large-id RID-SIZE ALLOT

CREATE _sr3c-small-delivered 9 ALLOT
CREATE _sr3c-small-failure 7 ALLOT
CREATE _sr3c-small-refused 7 ALLOT
4097 XBUF _sr3c-large
5000 XBUF _sr3c-readback

STREAMS-CONNECTOR-SIZE XBUF _sr3c-producer-input
STREAMS-CONNECTOR-SIZE XBUF _sr3c-local-output
STREAMS-CONNECTOR-SIZE XBUF _sr3c-dispatch-input
STREAMS-CONNECTOR-SIZE XBUF _sr3c-remote-output

STREAMS-FLOW-SIZE XBUF _sr3c-producer-flow
STREAMS-PAYLOAD-SIZE XBUF _sr3c-producer-ingress
STREAMS-PAYLOAD-SIZE XBUF _sr3c-producer-egress
STREAMS-PAYLOAD-SEGMENT-SIZE 4 * XBUF _sr3c-producer-in-segments
STREAMS-PAYLOAD-SEGMENT-SIZE 4 * XBUF _sr3c-producer-out-segments
STREAMS-RUNTIME-SEGMENT-BYTES 4 * XBUF _sr3c-producer-in-bytes
STREAMS-RUNTIME-SEGMENT-BYTES 4 * XBUF _sr3c-producer-out-bytes
STREAMS-RUNTIME-STANDARD-OPERATION-BYTES XBUF _sr3c-producer-operation
STREAMS-EVENT-SIZE XBUF _sr3c-producer-metadata

STREAMS-FLOW-SIZE XBUF _sr3c-compact-flow
STREAMS-PAYLOAD-SIZE XBUF _sr3c-compact-ingress
STREAMS-PAYLOAD-SIZE XBUF _sr3c-compact-egress
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _sr3c-compact-in-segments
STREAMS-PAYLOAD-SEGMENT-SIZE XBUF _sr3c-compact-out-segments
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _sr3c-compact-in-bytes
STREAMS-RUNTIME-SEGMENT-BYTES XBUF _sr3c-compact-out-bytes
STREAMS-RUNTIME-COMPACT-OPERATION-BYTES XBUF _sr3c-compact-operation

STREAMS-FLOW-SIZE XBUF _sr3c-standard-flow
STREAMS-PAYLOAD-SIZE XBUF _sr3c-standard-ingress
STREAMS-PAYLOAD-SIZE XBUF _sr3c-standard-egress
STREAMS-PAYLOAD-SEGMENT-SIZE 4 * XBUF _sr3c-standard-in-segments
STREAMS-PAYLOAD-SEGMENT-SIZE 4 * XBUF _sr3c-standard-out-segments
STREAMS-RUNTIME-SEGMENT-BYTES 4 * XBUF _sr3c-standard-in-bytes
STREAMS-RUNTIME-SEGMENT-BYTES 4 * XBUF _sr3c-standard-out-bytes
STREAMS-RUNTIME-STANDARD-OPERATION-BYTES XBUF _sr3c-standard-operation

STREAMS-EXECUTION-ENTRY-SIZE 2 * XBUF _sr3c-pool-entries
STREAMS-EXECUTION-POOL-SIZE XBUF _sr3c-pool

: _sr3c-assert  ( flag -- )
    1 _sr3c-checks +!
    0= IF
        1 _sr3c-fails +!
        _sr3c-cold? @ IF
            ." STREAMS SR3 COMPOSED COLD ASSERT "
        ELSE
            ." STREAMS SR3 COMPOSED FIRST ASSERT "
        THEN
        _sr3c-checks @ . CR
    THEN ;

: _sr3c-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS SR3 COMPOSED STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _sr3c-assert ;

: _sr3c-stack  ( -- )
    DEPTH DUP _sr3c-depth @ <> IF
        ." STREAMS SR3 COMPOSED STACK "
        _sr3c-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr3c-depth @ = _sr3c-assert ;

: _sr3c-progress  ( phase -- )
    ." STREAMS SR3 COMPOSED PHASE " . CR
    0 0xFFFFFF0000000006 C! ;

: _sr3c-rid-fill  ( byte rid -- )
    RID-SIZE ROT FILL ;

: _sr3c-zero?  ( a u -- flag )
    DUP 0< IF 2DROP 0 EXIT THEN
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _sr3c-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _sr3c-result!  ( completion effect detail error result -- )
    >R
    R@ SCRR.ERROR !
    R@ SCRR.DETAIL !
    R@ SCRR.EFFECT !
    R> SCRR.COMPLETION ! ;

: _sr3c-transform-result!
  ( completion output-u detail error result -- )
    >R
    R@ STRR.ERROR !
    R@ STRR.DETAIL !
    R@ STRR.OUTPUT-U !
    R> STRR.COMPLETION ! ;

: _sr3c-stream-sink
  ( logical-offset payload-a payload-u context -- status )
    >R
    2 PICK _sr3c-stream-u @ <> IF
        2DROP DROP R> DROP PERSIST-S-CORRUPT EXIT
    THEN
    OVER 3 PICK R@ + 2 PICK MOVE
    DUP _sr3c-stream-u +!
    2DROP DROP
    PERSIST-S-OK
    R> DROP ;

: _sr3c-stream-attempt  ( attempt-id expected-a expected-u -- )
    _sr3c-stream-limit !
    _sr3c-stream-target !
    _sr3c-readback 5000 0xCC FILL
    0 _sr3c-stream-u !
    ['] _sr3c-stream-sink _sr3c-readback
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-PAYLOAD-STREAM
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-stream-u @ _sr3c-stream-limit @ = _sr3c-assert
    _sr3c-readback _sr3c-stream-target @
        _sr3c-stream-limit @ _sr3c-bytes= _sr3c-assert ;

: _sr3c-attempt@  ( attempt-id -- status )
    _sr3c-attempt _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-ATTEMPT@ ;

: _sr3c-ready@  ( -- status )
    _sr3c-ready _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-READY@ ;

: _sr3c-capacity@  ( -- capacity )
    _sr3c-capacity
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-CAPACITY
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-capacity STREAMS-SPOOL-CAPACITY-VALID? _sr3c-assert
    _sr3c-capacity ;

: _sr3c-copy-current-id  ( attempt -- )
    SOPATT.ATTEMPT-ID _sr3c-current-id RID-COPY ;

: _sr3c-runtime-open  ( -- )
    VFS-CUR _sr3c-old-vfs !
    _sr3c-bd BD-OPEN THROW
    _sr3c-bd _sr3c-volume VOL-RAW THROW
    2097152 A-XMEM ARENA-NEW
    DUP IF NIP THROW THEN DROP
    DUP 0= IF DROP -1 THROW THEN _sr3c-arena !
    _sr3c-arena @ _sr3c-volume VMP-NEW ?DUP IF THROW THEN
    DUP 0= IF DROP -1 THROW THEN
    DUP _sr3c-vfs ! VFS-USE ;

: _sr3c-runtime-close  ( -- )
    _sr3c-vfs @ VFS-SYNC 0= _sr3c-assert
    _sr3c-old-vfs @ VFS-USE
    _sr3c-vfs @ VFS-DESTROY
    _sr3c-volume VOL-CLOSE 0= _sr3c-assert
    _sr3c-bd BD-CLOSE 0= _sr3c-assert ;

: _sr3c-store-init  ( -- status )
    S" /s3cp" S" /s3cs" S" /s3cra" S" /s3crb"
    _sr3c-identity
    STREAMS-OPATT-SIZE PBLOB-CHUNK-SIZE MAX
    _sr3c-vfs @ 0 0 _sr3c-guard 0 0 _sr3c-store
        PSTORE-INIT ;

: _sr3c-bank1-init  ( -- status )
    S" /s3cp1" _sr3c-vfs @ 0 0 _sr3c-bank1-page
        PPAGE-FILE-INIT DUP IF EXIT THEN DROP
    S" /s3cs1" STREAMS-OPATT-SIZE PBLOB-CHUNK-SIZE MAX
        _sr3c-vfs @ 0 _sr3c-bank1-segment PSEG-FILE-INIT ;

: _sr3c-builder-store-init  ( -- status )
    S" /s3cp" S" /s3cs" S" /s3cba" S" /s3cbb"
    _sr3c-identity
    STREAMS-OPATT-SIZE PBLOB-CHUNK-SIZE MAX
    _sr3c-vfs @ 0 0 _sr3c-builder-guard 0 0
        _sr3c-builder-store PSTORE-INIT ;

: _sr3c-configure-two-bank-stores  ( -- status )
    _sr3c-bank1-init DUP IF EXIT THEN DROP
    _sr3c-bank1-page _sr3c-bank1-segment _sr3c-store
        PSTORE-BANK1-CONFIGURE DUP IF EXIT THEN DROP
    _sr3c-builder-store-init DUP IF EXIT THEN DROP
    _sr3c-bank1-page _sr3c-bank1-segment _sr3c-builder-store
        PSTORE-BANK1-CONFIGURE ;

: _sr3c-spool-bind  ( -- status )
    _sr3c-spool _sr3c-current-spool !
    _sr3c-spool-work _sr3c-current-work !
    _sr3c-store-init DUP IF EXIT THEN DROP
    _sr3c-configure-two-bank-stores DUP IF EXIT THEN DROP
    _sr3c-record-buffer STREAMS-SPOOL-RECORD-BUFFER-MIN
        _sr3c-pstore-work PSTORE-WORK-INIT DUP IF EXIT THEN DROP
    _sr3c-builder-record-buffer STREAMS-SPOOL-RECORD-BUFFER-MIN
        _sr3c-builder-pstore-work PSTORE-WORK-INIT
        DUP IF EXIT THEN DROP
    _sr3c-store _sr3c-pstore-work PSTORE-PROVISION DUP IF EXIT THEN DROP
    _sr3c-store _sr3c-spool STREAMS-SPOOL-INIT DUP IF EXIT THEN DROP
    _sr3c-builder-store _sr3c-builder-spool STREAMS-SPOOL-INIT
        DUP IF EXIT THEN DROP
    _sr3c-cold-audit _sr3c-cold-audit-u
        _sr3c-pstore-work _sr3c-spool _sr3c-spool-work
        STREAMS-SPOOL-WORK-INIT DUP IF EXIT THEN DROP
    0 0 _sr3c-builder-pstore-work
        _sr3c-builder-spool _sr3c-builder-spool-work
        STREAMS-SPOOL-WORK-INIT DUP IF EXIT THEN DROP
    _sr3c-spool _sr3c-spool-work STREAMS-SPOOL-OPEN ;

: _sr3c-setup-bytes  ( -- )
    _sr3c-identity RID-SIZE 0x19 FILL
    _sr3c-identity _sr3c-authority RID-COPY
    0x21 _sr3c-local-id _sr3c-rid-fill
    0x22 _sr3c-local-endpoint _sr3c-rid-fill
    0x23 _sr3c-local-seal _sr3c-rid-fill
    0x31 _sr3c-remote-id _sr3c-rid-fill
    0x32 _sr3c-remote-endpoint _sr3c-rid-fill
    0x33 _sr3c-remote-seal _sr3c-rid-fill
    0x41 _sr3c-flow-id _sr3c-rid-fill
    0x42 _sr3c-route-id _sr3c-rid-fill
    0x43 _sr3c-transform-id _sr3c-rid-fill
    0x51 _sr3c-producer-input-id _sr3c-rid-fill
    0x52 _sr3c-producer-input-endpoint _sr3c-rid-fill
    0x53 _sr3c-producer-flow-id _sr3c-rid-fill
    _sr3c-delivered-id RID-CLEAR
    _sr3c-failure-id RID-CLEAR
    _sr3c-large-id RID-CLEAR
    S" delivered" _sr3c-small-delivered SWAP MOVE
    S" failure" _sr3c-small-failure SWAP MOVE
    S" refused" _sr3c-small-refused SWAP MOVE
    _sr3c-large 4097 0xA7 FILL
    0x5A _sr3c-large C!
    0xC3 _sr3c-large 4096 + C! ;

: _sr3c-opconn-common
  ( connector-id endpoint-id endpoint-seal protocol profile connector -- )
    >R
    R@ STREAMS-OPCONN-INIT STREAMS-OPREC-S-OK _sr3c-status
    R@ SOPCONN.PROFILE !
    R@ SOPCONN.PROTOCOL !
    R@ SOPCONN.ENDPOINT-SEAL RID-COPY
    R@ SOPCONN.ENDPOINT-ID RID-COPY
    R@ SOPCONN.CONNECTOR-ID RID-COPY
    1 R@ SOPCONN.REVISION !
    STREAMS-OPCONN-DIRECTION-EGRESS R@ SOPCONN.DIRECTION !
    STREAMS-OPCONN-ENDPOINT-PINNED R@ SOPCONN.ENDPOINT-POLICY !
    STREAMS-OPCONN-CREDENTIAL-NONE R@ SOPCONN.CREDENTIAL-POLICY !
    5000 R@ SOPCONN.REQUEST-BYTE-LIMIT !
    5000 R@ SOPCONN.RESPONSE-BYTE-LIMIT !
    4113 R@ SOPCONN.PAYLOAD-BYTE-LIMIT !
    3 R@ SOPCONN.QUEUE-ITEM-LIMIT !
    4113 R@ SOPCONN.QUEUE-BYTE-LIMIT !
    0 R@ SOPCONN.RETRY-LIMIT !
    0 R@ SOPCONN.RETRY-DELAY-MS !
    0 R@ SOPCONN.REDIRECT-LIMIT !
    100 R@ SOPCONN.CONNECT-TIMEOUT-MS !
    1000 R@ SOPCONN.OPERATION-TIMEOUT-MS !
    100 R@ SOPCONN.IDLE-TIMEOUT-MS !
    STREAMS-OPCONN-RECEIPT-NONE R@ SOPCONN.RECEIPT-POLICY !
    0 R@ SOPCONN.RECEIPT-BYTE-LIMIT !
    STREAMS-OPCONN-IDEMPOTENCY-EXACT
        R@ SOPCONN.IDEMPOTENCY-POLICY !
    STREAMS-OPCONN-LIFECYCLE-ACTIVE R@ SOPCONN.LIFECYCLE !
    1 R@ SOPCONN.ENABLED !
    STREAMS-OPCONN-HEALTH-HEALTHY R@ SOPCONN.HEALTH !
    1 R@ SOPCONN.CONFIGURED-MS !
    R@ STREAMS-OPCONN-SEAL STREAMS-OPREC-S-OK _sr3c-status
    R> DROP ;

: _sr3c-setup-operational-config  ( -- )
    _sr3c-local-id _sr3c-local-endpoint _sr3c-local-seal
        101 201 _sr3c-local-opconn _sr3c-opconn-common
    _sr3c-remote-id _sr3c-remote-endpoint _sr3c-remote-seal
        102 202 _sr3c-remote-opconn _sr3c-opconn-common

    _sr3c-opflow STREAMS-OPFLOW-INIT
        STREAMS-OPREC-S-OK _sr3c-status
    _sr3c-flow-id _sr3c-opflow SOPFLOW.FLOW-ID RID-COPY
    _sr3c-local-id
        _sr3c-opflow SOPFLOW.INPUT-CONNECTOR-ID RID-COPY
    _sr3c-remote-id
        _sr3c-opflow SOPFLOW.OUTPUT-CONNECTOR-ID RID-COPY
    _sr3c-route-id _sr3c-opflow SOPFLOW.ROUTE-ID RID-COPY
    _sr3c-transform-id _sr3c-opflow SOPFLOW.TRANSFORM-ID RID-COPY
    1 _sr3c-opflow SOPFLOW.REVISION !
    1 _sr3c-opflow SOPFLOW.INPUT-CONNECTOR-REVISION !
    1 _sr3c-opflow SOPFLOW.OUTPUT-CONNECTOR-REVISION !
    1 _sr3c-opflow SOPFLOW.ROUTE-REVISION !
    1 _sr3c-opflow SOPFLOW.TRANSFORM-REVISION !
    4113 _sr3c-opflow SOPFLOW.PAYLOAD-BYTE-LIMIT !
    4113 _sr3c-opflow SOPFLOW.OUTPUT-BYTE-LIMIT !
    1 _sr3c-opflow SOPFLOW.IN-FLIGHT-LIMIT !
    1000 _sr3c-opflow SOPFLOW.TRANSFORM-STEP-LIMIT !
    1000 _sr3c-opflow SOPFLOW.TIMEOUT-MS !
    STREAMS-OPFLOW-BACKPRESSURE-REFUSE
        _sr3c-opflow SOPFLOW.BACKPRESSURE-POLICY !
    STREAMS-OPFLOW-FAILURE-REVIEW
        _sr3c-opflow SOPFLOW.FAILURE-POLICY !
    STREAMS-OPFLOW-RETRY-NONE
        _sr3c-opflow SOPFLOW.RETRY-POLICY !
    STREAMS-OPFLOW-LIFECYCLE-ACTIVE
        _sr3c-opflow SOPFLOW.LIFECYCLE !
    1 _sr3c-opflow SOPFLOW.ENABLED !
    1 _sr3c-opflow SOPFLOW.CONFIGURED-MS !
    _sr3c-opflow STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-OK _sr3c-status ;

: _sr3c-install-operational-config  ( -- )
    _sr3c-local-opconn
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-CONNECTOR-PUT
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-remote-opconn
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-CONNECTOR-PUT
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-opflow
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-FLOW-PUT
        STREAMS-SPOOL-S-OK _sr3c-status ;

: _sr3c-connector-identity  ( id endpoint connector -- )
    >R
    R@ SCON.ENDPOINT-ID RID-COPY
    R> SCON.ID RID-COPY ;

: _sr3c-local-start  ( event operation context result -- )
    _sr3c-cb-result !
    DROP
    _sr3c-cb-op !
    _sr3c-cb-event !
    1 _sr3c-local-starts +!
    0 _sr3c-assert
    STREAMS-CONNECTOR-COMPLETION-FAILED
    STREAMS-EFFECT-NOT-APPLIED 0 -5101
        _sr3c-cb-result @ _sr3c-result! ;

: _sr3c-local-poll  ( event operation context result -- )
    _sr3c-cb-result !
    _sr3c-drop3
    1 _sr3c-local-polls +!
    0 _sr3c-assert
    STREAMS-CONNECTOR-COMPLETION-FAILED
    STREAMS-EFFECT-NOT-APPLIED 0 -5102
        _sr3c-cb-result @ _sr3c-result! ;

: _sr3c-local-cancel  ( event operation context result -- )
    _sr3c-cb-result !
    _sr3c-drop3
    1 _sr3c-local-cancels +!
    0 _sr3c-assert
    STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED 0 0
        _sr3c-cb-result @ _sr3c-result! ;

: _sr3c-local-cleanup  ( event operation context -- error )
    _sr3c-drop3
    1 _sr3c-local-cleanups +!
    0 _sr3c-assert
    0 ;

: _sr3c-check-remote-event  ( event -- )
    DUP STREAMS-EVENT-VALID? _sr3c-assert
    DUP SEVT.EVENT-ID
        _sr3c-attempt SOPATT.EVENT-ID RID= _sr3c-assert
    DUP SEVT.CONNECTOR-ID
        _sr3c-attempt SOPATT.CONNECTOR-ID RID= _sr3c-assert
    DUP SEVT.FLOW-ID
        _sr3c-attempt SOPATT.FLOW-ID RID= _sr3c-assert
    DUP SEVT.CORRELATION-ID
        _sr3c-attempt SOPATT.CORRELATION-ID RID= _sr3c-assert
    DUP SEVT.IDEMPOTENCY-ID
        _sr3c-attempt SOPATT.IDEMPOTENCY-ID RID= _sr3c-assert
    DUP SEVT.ORIGIN-ID
        _sr3c-attempt SOPATT.ORIGIN-ID RID= _sr3c-assert
    DUP SEVT.DESTINATION-ID
        _sr3c-attempt SOPATT.DESTINATION-ID RID= _sr3c-assert
    DUP SEVT.PAYLOAD-U @
        _sr3c-attempt SOPATT.PAYLOAD-U @ = _sr3c-assert
    DUP SEVT.PAYLOAD-DIGEST
        _sr3c-attempt SOPATT.PAYLOAD-DIGEST
        SHA3-256-COMPARE _sr3c-assert
    DUP SEVT.PAYLOAD-A @ SPAY.PROFILE @
        _sr3c-start-profile !
    _sr3c-readback 5000 2 PICK STREAMS-EVENT-PAYLOAD-COPY
        STREAMS-FLOW-S-OK _sr3c-status
    DUP _sr3c-attempt SOPATT.PAYLOAD-U @ = _sr3c-assert
    DROP
    DUP SEVT.PAYLOAD-U @ 4097 = IF
        _sr3c-readback _sr3c-large 4097 _sr3c-bytes= _sr3c-assert
    ELSE
        _sr3c-remote-mode @ _SR3C-REMOTE-DELIVER = IF
            _sr3c-readback _sr3c-small-delivered 9
                _sr3c-bytes= _sr3c-assert
        ELSE
            _sr3c-readback _sr3c-small-failure 7
                _sr3c-bytes= _sr3c-assert
        THEN
    THEN
    DROP ;

: _sr3c-remote-start  ( event operation context result -- )
    _sr3c-cb-result !
    DROP
    _sr3c-cb-op !
    _sr3c-cb-event !
    1 _sr3c-remote-starts +!
    _sr3c-current-id
        _sr3c-attempt@ STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-attempt
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-ACTIVE =
            _sr3c-assert
        DUP SOPATT.RECORD-REVISION @ 2 = _sr3c-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-UNCERTAIN =
            _sr3c-assert
        DUP SOPATT.DISPATCH-COUNT @ 1 = _sr3c-assert
        SOPATT.STARTED-MS @ _sr3c-dispatch-ms @ = _sr3c-assert
    _sr3c-cb-event @ _sr3c-check-remote-event
    _sr3c-remote-mode @ _SR3C-REMOTE-FAIL-SIGNED = IF
        STREAMS-CONNECTOR-COMPLETION-FAILED
        STREAMS-EFFECT-NOT-APPLIED -491 -4901
            _sr3c-cb-result @ _sr3c-result!
    ELSE
        STREAMS-CONNECTOR-COMPLETION-DELIVERED
        STREAMS-EFFECT-APPLIED 0 0
            _sr3c-cb-result @ _sr3c-result!
    THEN ;

: _sr3c-remote-poll  ( event operation context result -- )
    _sr3c-cb-result !
    _sr3c-drop3
    1 _sr3c-remote-polls +!
    0 _sr3c-assert
    STREAMS-CONNECTOR-COMPLETION-INDETERMINATE
    STREAMS-EFFECT-UNCERTAIN 0 -5201
        _sr3c-cb-result @ _sr3c-result! ;

: _sr3c-remote-cancel  ( event operation context result -- )
    _sr3c-cb-result !
    _sr3c-drop3
    1 _sr3c-remote-cancels +!
    STREAMS-CONNECTOR-COMPLETION-CANCELLED
    STREAMS-EFFECT-NOT-APPLIED 0 0
        _sr3c-cb-result @ _sr3c-result! ;

: _sr3c-remote-cleanup  ( event operation context -- error )
    _sr3c-drop3
    1 _sr3c-remote-cleanups +!
    _sr3c-remote-mode @ _SR3C-REMOTE-FAIL-SIGNED =
        IF -770 ELSE 0 THEN ;

: _sr3c-transform  ( ingress-event output-carrier context result -- )
    _sr3c-cb-result !
    DROP
    _sr3c-cb-op !
    _sr3c-cb-event !
    _sr3c-cb-op @ SPAY.GENERATION @
        _sr3c-cb-op @ _sr3c-cb-event @
        STREAMS-EVENT-APPEND-TO-CARRIER
        STREAMS-FLOW-S-OK _sr3c-status
    STREAMS-TRANSFORM-COMPLETION-OK
    _sr3c-cb-op @ SPAY.BYTE-U @ 0 0
        _sr3c-cb-result @ _sr3c-transform-result! ;

: _sr3c-setup-runtime-connectors  ( -- )
    _sr3c-producer-input STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-local-id _sr3c-local-endpoint
        _sr3c-producer-input _sr3c-connector-identity
    1 _sr3c-producer-input SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT
        _sr3c-producer-input SCON.DIRECTION !
    101 _sr3c-producer-input SCON.PROTOCOL !
    _sr3c-producer-input STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK _sr3c-status

    _sr3c-dispatch-input STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-local-id _sr3c-local-endpoint
        _sr3c-dispatch-input _sr3c-connector-identity
    1 _sr3c-dispatch-input SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-INPUT
        _sr3c-dispatch-input SCON.DIRECTION !
    101 _sr3c-dispatch-input SCON.PROTOCOL !
    _sr3c-dispatch-input STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK _sr3c-status

    \ This descriptor is a sentinel for accidental local output dispatch.
    \ The composed path must always use the remote connector below.
    _sr3c-local-output STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-local-id _sr3c-local-endpoint
        _sr3c-local-output _sr3c-connector-identity
    1 _sr3c-local-output SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT
        _sr3c-local-output SCON.DIRECTION !
    101 _sr3c-local-output SCON.PROTOCOL !
    0 _sr3c-local-output SCON.CONTEXT !
    16 _sr3c-local-output SCON.OP-SIZE !
    ['] _sr3c-local-start _sr3c-local-output SCON.START-XT !
    ['] _sr3c-local-poll _sr3c-local-output SCON.POLL-XT !
    ['] _sr3c-local-cancel _sr3c-local-output SCON.CANCEL-XT !
    ['] _sr3c-local-cleanup _sr3c-local-output SCON.CLEANUP-XT !
    _sr3c-local-output STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK _sr3c-status

    _sr3c-remote-output STREAMS-CONNECTOR-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-remote-id _sr3c-remote-endpoint
        _sr3c-remote-output _sr3c-connector-identity
    1 _sr3c-remote-output SCON.REVISION !
    STREAMS-CONNECTOR-DIRECTION-OUTPUT
        _sr3c-remote-output SCON.DIRECTION !
    102 _sr3c-remote-output SCON.PROTOCOL !
    0 _sr3c-remote-output SCON.CONTEXT !
    16 _sr3c-remote-output SCON.OP-SIZE !
    ['] _sr3c-remote-start _sr3c-remote-output SCON.START-XT !
    ['] _sr3c-remote-poll _sr3c-remote-output SCON.POLL-XT !
    ['] _sr3c-remote-cancel _sr3c-remote-output SCON.CANCEL-XT !
    ['] _sr3c-remote-cleanup _sr3c-remote-output SCON.CLEANUP-XT !
    _sr3c-remote-output STREAMS-CONNECTOR-SEAL
        STREAMS-FLOW-S-OK _sr3c-status

    _sr3c-producer-input STREAMS-CONNECTOR-VALID? _sr3c-assert
    _sr3c-dispatch-input STREAMS-CONNECTOR-VALID? _sr3c-assert
    _sr3c-local-output STREAMS-CONNECTOR-VALID? _sr3c-assert
    _sr3c-remote-output STREAMS-CONNECTOR-VALID? _sr3c-assert ;

: _sr3c-init-standard-segments  ( bytes table -- )
    >R
    DUP STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK _sr3c-status
    DUP STREAMS-RUNTIME-SEGMENT-BYTES +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-SIZE +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK _sr3c-status
    DUP STREAMS-RUNTIME-SEGMENT-BYTES 2 * +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R@ STREAMS-PAYLOAD-SEGMENT-SIZE 2 * +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK _sr3c-status
    STREAMS-RUNTIME-SEGMENT-BYTES 3 * +
        STREAMS-RUNTIME-SEGMENT-BYTES
        R> STREAMS-PAYLOAD-SEGMENT-SIZE 3 * +
        STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK _sr3c-status ;

: _sr3c-init-producer-workspace  ( -- )
    _sr3c-producer-in-bytes _sr3c-producer-in-segments
        _sr3c-init-standard-segments
    _sr3c-producer-out-bytes _sr3c-producer-out-segments
        _sr3c-init-standard-segments
    _sr3c-producer-in-segments 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr3c-producer-ingress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _sr3c-status
    _sr3c-producer-out-segments 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr3c-producer-egress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _sr3c-status ;

: _sr3c-init-compact-workspace  ( -- )
    _sr3c-compact-in-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr3c-compact-in-segments STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK _sr3c-status
    _sr3c-compact-out-bytes STREAMS-RUNTIME-SEGMENT-BYTES
        _sr3c-compact-out-segments STREAMS-PAYLOAD-SEGMENT-INIT
        STREAMS-PAYLOAD-S-OK _sr3c-status
    _sr3c-compact-in-segments 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr3c-compact-ingress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _sr3c-status
    _sr3c-compact-out-segments 1
        STREAMS-RUNTIME-PROFILE-COMPACT
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr3c-compact-egress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _sr3c-status ;

: _sr3c-init-standard-workspace  ( -- )
    _sr3c-standard-in-bytes _sr3c-standard-in-segments
        _sr3c-init-standard-segments
    _sr3c-standard-out-bytes _sr3c-standard-out-segments
        _sr3c-init-standard-segments
    _sr3c-standard-in-segments 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr3c-standard-ingress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _sr3c-status
    _sr3c-standard-out-segments 4
        STREAMS-RUNTIME-PROFILE-STANDARD
        STREAMS-PAYLOAD-F-WIPE 0 0 _sr3c-standard-egress
        STREAMS-PAYLOAD-INIT STREAMS-PAYLOAD-S-OK _sr3c-status ;

: _sr3c-setup-producer-flow  ( -- )
    _sr3c-producer-flow STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-init-producer-workspace
    STREAMS-RUNTIME-PROFILE-STANDARD
        _sr3c-producer-ingress _sr3c-producer-egress
        _sr3c-producer-operation
        STREAMS-RUNTIME-PROFILE-STANDARD
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr3c-producer-flow STREAMS-FLOW-WORKSPACE!
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-flow-id _sr3c-producer-flow SFLOW.ID RID-COPY
    1 _sr3c-producer-flow SFLOW.REVISION !
    1000 _sr3c-producer-flow SFLOW.TIMEOUT-MS !
    _sr3c-producer-input
        _sr3c-producer-flow SFLOW.INPUT-CONNECTOR !
    _sr3c-remote-output
        _sr3c-producer-flow SFLOW.OUTPUT-CONNECTOR !
    ['] _sr3c-transform _sr3c-producer-flow SFLOW.TRANSFORM-XT !
    0 _sr3c-producer-flow SFLOW.TRANSFORM-CONTEXT !
    303 _sr3c-producer-flow SFLOW.OUTPUT-MEDIA !
    _sr3c-producer-flow STREAMS-FLOW-SEAL
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-producer-flow STREAMS-FLOW-VALID? _sr3c-assert ;

: _sr3c-setup-compact-flow  ( -- )
    _sr3c-compact-flow STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-init-compact-workspace
    STREAMS-RUNTIME-PROFILE-COMPACT
        _sr3c-compact-ingress _sr3c-compact-egress
        _sr3c-compact-operation
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr3c-compact-flow STREAMS-FLOW-WORKSPACE!
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-flow-id _sr3c-compact-flow SFLOW.ID RID-COPY
    1 _sr3c-compact-flow SFLOW.REVISION !
    1000 _sr3c-compact-flow SFLOW.TIMEOUT-MS !
    _sr3c-dispatch-input _sr3c-compact-flow SFLOW.INPUT-CONNECTOR !
    _sr3c-remote-output _sr3c-compact-flow SFLOW.OUTPUT-CONNECTOR !
    ['] _sr3c-transform _sr3c-compact-flow SFLOW.TRANSFORM-XT !
    0 _sr3c-compact-flow SFLOW.TRANSFORM-CONTEXT !
    303 _sr3c-compact-flow SFLOW.OUTPUT-MEDIA !
    _sr3c-compact-flow STREAMS-FLOW-SEAL
        STREAMS-FLOW-S-OK _sr3c-status ;

: _sr3c-setup-standard-flow  ( -- )
    _sr3c-standard-flow STREAMS-FLOW-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-init-standard-workspace
    STREAMS-RUNTIME-PROFILE-STANDARD
        _sr3c-standard-ingress _sr3c-standard-egress
        _sr3c-standard-operation
        STREAMS-RUNTIME-PROFILE-STANDARD
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr3c-standard-flow STREAMS-FLOW-WORKSPACE!
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-flow-id _sr3c-standard-flow SFLOW.ID RID-COPY
    1 _sr3c-standard-flow SFLOW.REVISION !
    1000 _sr3c-standard-flow SFLOW.TIMEOUT-MS !
    _sr3c-dispatch-input _sr3c-standard-flow SFLOW.INPUT-CONNECTOR !
    _sr3c-remote-output _sr3c-standard-flow SFLOW.OUTPUT-CONNECTOR !
    ['] _sr3c-transform _sr3c-standard-flow SFLOW.TRANSFORM-XT !
    0 _sr3c-standard-flow SFLOW.TRANSFORM-CONTEXT !
    303 _sr3c-standard-flow SFLOW.OUTPUT-MEDIA !
    _sr3c-standard-flow STREAMS-FLOW-SEAL
        STREAMS-FLOW-S-OK _sr3c-status ;

: _sr3c-setup-runtime  ( -- )
    _sr3c-setup-runtime-connectors
    _sr3c-setup-producer-flow
    _sr3c-setup-compact-flow
    _sr3c-setup-standard-flow
    _sr3c-pool-entries 2 _sr3c-pool
        STREAMS-EXECUTION-POOL-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-compact-flow _sr3c-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-standard-flow _sr3c-pool STREAMS-EXECUTION-POOL-BIND
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-pool STREAMS-EXECUTION-POOL-SEAL
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-pool STREAMS-EXECUTION-POOL-VALID? _sr3c-assert
    _sr3c-pool STREAMS-EXECUTION-POOL-CAPACITY@ 2 =
        _sr3c-assert
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
        _sr3c-assert

    _sr3c-dispatch STREAMS-OPDISPATCH-INIT
        STREAMS-OPDISPATCH-S-OK _sr3c-status
    _sr3c-current-spool @ _sr3c-current-work @
        _sr3c-pool _sr3c-opflow _sr3c-remote-opconn
        303 _sr3c-dispatch STREAMS-OPDISPATCH-BIND
        STREAMS-OPDISPATCH-S-OK _sr3c-status
    _sr3c-dispatch STREAMS-OPDISPATCH-VALID? _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-STATE@
        STREAMS-OPDISPATCH-STATE-READY = _sr3c-assert ;

: _sr3c-event-header  ( tag now-ms event -- )
    _sr3c-build-event !
    _sr3c-build-now !
    _sr3c-build-tag !
    _sr3c-build-event @ STREAMS-EVENT-INIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-build-tag @
        _sr3c-build-event @ SEVT.EVENT-ID _sr3c-rid-fill
    _sr3c-build-tag @ 1+
        _sr3c-build-event @ SEVT.CORRELATION-ID _sr3c-rid-fill
    _sr3c-build-tag @ 2 +
        _sr3c-build-event @ SEVT.IDEMPOTENCY-ID _sr3c-rid-fill
    _sr3c-build-tag @ 3 +
        _sr3c-build-event @ SEVT.ORIGIN-ID _sr3c-rid-fill
    _sr3c-build-tag @ 4 +
        _sr3c-build-event @ SEVT.DESTINATION-ID _sr3c-rid-fill
    303 _sr3c-build-event @ SEVT.MEDIA !
    _sr3c-build-tag @ _sr3c-build-event @ SEVT.SEQUENCE !
    _sr3c-build-now @ _sr3c-build-event @ SEVT.RECEIVED-MS ! ;

: _sr3c-producer-ready  ( payload-a payload-u tag now-ms -- )
    _sr3c-build-now !
    _sr3c-build-tag !
    _sr3c-build-u !
    _sr3c-build-a !
    _sr3c-build-tag @ _sr3c-build-now @
        _sr3c-producer-metadata _sr3c-event-header
    _sr3c-producer-input _sr3c-producer-metadata
        _sr3c-build-u @ 1 _sr3c-build-now @
        _sr3c-producer-flow STREAMS-FLOW-INGRESS-BEGIN
        STREAMS-FLOW-S-OK _sr3c-status
    DUP 0> _sr3c-assert
    _sr3c-generation !
    _sr3c-build-a @ _sr3c-build-u @
        _sr3c-generation @ _sr3c-build-now @ 1+
        _sr3c-producer-flow STREAMS-FLOW-INGRESS-APPEND
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-generation @ _sr3c-build-now @ 2 +
        _sr3c-producer-flow STREAMS-FLOW-INGRESS-COMMIT
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-build-now @ 3 + _sr3c-producer-flow
        STREAMS-FLOW-STEP
        STREAMS-FLOW-S-ACKNOWLEDGED _sr3c-status
    _sr3c-producer-flow SFLOW.STATE @
        STREAMS-FLOW-STATE-OUTPUT-READY = _sr3c-assert
    _sr3c-producer-flow SFLOW.EGRESS-EVENT
        STREAMS-EVENT-VALID? _sr3c-assert
    _sr3c-producer-flow SFLOW.EGRESS-EVENT SEVT.PAYLOAD-U @
        _sr3c-build-u @ = _sr3c-assert
    _sr3c-producer-flow SFLOW.EGRESS-CARRIER
        DUP SPAY.GENERATION @ SWAP STREAMS-PAYLOAD-EXACT?
        _sr3c-assert
    _sr3c-remote-starts @ 0= _sr3c-assert
    _sr3c-local-starts @ 0= _sr3c-assert ;

: _sr3c-producer-retire  ( now-ms -- )
    _sr3c-generation @ SWAP _sr3c-producer-flow
        STREAMS-FLOW-CANCEL
        STREAMS-FLOW-S-CANCELLED _sr3c-status
    _sr3c-generation @ _sr3c-producer-flow STREAMS-FLOW-RETIRE
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-producer-flow SFLOW.STATE @
        STREAMS-FLOW-STATE-IDLE = _sr3c-assert
    _sr3c-producer-flow SFLOW.INGRESS-CARRIER SPAY.BYTE-U @ 0=
        _sr3c-assert
    _sr3c-producer-flow SFLOW.EGRESS-CARRIER SPAY.BYTE-U @ 0=
        _sr3c-assert ;

: _sr3c-check-enqueued-exact  ( -- )
    _sr3c-current-id _sr3c-attempt@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-attempt STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3c-assert
    _sr3c-attempt
        DUP SOPATT.ATTEMPT-ID _sr3c-current-id RID=
            _sr3c-assert
        DUP SOPATT.EVENT-ID
            _sr3c-producer-flow SFLOW.EGRESS-EVENT
                SEVT.EVENT-ID RID= _sr3c-assert
        DUP SOPATT.CONNECTOR-ID _sr3c-remote-id RID=
            _sr3c-assert
        DUP SOPATT.FLOW-ID _sr3c-flow-id RID= _sr3c-assert
        DUP SOPATT.CORRELATION-ID
            _sr3c-producer-flow SFLOW.EGRESS-EVENT
                SEVT.CORRELATION-ID RID= _sr3c-assert
        DUP SOPATT.IDEMPOTENCY-ID
            _sr3c-producer-flow SFLOW.EGRESS-EVENT
                SEVT.IDEMPOTENCY-ID RID= _sr3c-assert
        DUP SOPATT.ORIGIN-ID
            _sr3c-producer-flow SFLOW.EGRESS-EVENT
                SEVT.ORIGIN-ID RID= _sr3c-assert
        DUP SOPATT.DESTINATION-ID _sr3c-remote-endpoint RID=
            _sr3c-assert
        DUP SOPATT.PAYLOAD-DIGEST
            _sr3c-producer-flow SFLOW.EGRESS-EVENT
                SEVT.PAYLOAD-DIGEST
            SHA3-256-COMPARE _sr3c-assert
        DUP SOPATT.PAYLOAD-U @ _sr3c-build-u @ =
            _sr3c-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-ACCEPTED =
            _sr3c-assert
        SOPATT.RECORD-REVISION @ 1 = _sr3c-assert
    _sr3c-current-id _sr3c-build-a @ _sr3c-build-u @
        _sr3c-stream-attempt ;

: _sr3c-enqueue-success
  ( payload-a payload-u tag now-ms result attempt-id-out -- )
    _sr3c-enqueue-id !
    _sr3c-enqueue-result !
    _sr3c-build-now !
    _sr3c-build-tag !
    _sr3c-build-u !
    _sr3c-build-a !
    _sr3c-build-a @ _sr3c-build-u @
        _sr3c-build-tag @ _sr3c-build-now @ _sr3c-producer-ready
    _sr3c-producer-flow _sr3c-build-now @ 4 +
        _sr3c-enqueue-result @ _sr3c-dispatch
        STREAMS-OPDISPATCH-ENQUEUE
        STREAMS-OPDISPATCH-S-OK _sr3c-status
    _sr3c-enqueue-result @ STREAMS-SPOOL-RESULT-VALID?
        _sr3c-assert
    _sr3c-enqueue-result @ SPOOLRESULT.ATTEMPT-ID
        DUP _sr3c-current-id RID-COPY
        _sr3c-enqueue-id @ RID-COPY
    _sr3c-check-enqueued-exact
    _sr3c-build-now @ 5 + _sr3c-producer-retire ;

: _sr3c-enqueue-refused  ( payload-a payload-u tag now-ms -- )
    _sr3c-build-now !
    _sr3c-build-tag !
    _sr3c-build-u !
    _sr3c-build-a !
    _sr3c-build-a @ _sr3c-build-u @
        _sr3c-build-tag @ _sr3c-build-now @ _sr3c-producer-ready
    _sr3c-store PSTORE-GENERATION@
        _sr3c-generation-before !
    _sr3c-ready@ STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-ready _sr3c-attempt-before
        STREAMS-OPATT-SIZE MOVE
    _sr3c-result-refused STREAMS-SPOOL-RESULT-SIZE 0xA5 FILL
    _sr3c-producer-flow _sr3c-build-now @ 4 +
        _sr3c-result-refused _sr3c-dispatch
        STREAMS-OPDISPATCH-ENQUEUE
        STREAMS-OPDISPATCH-S-OUTBOX-FULL-ITEMS _sr3c-status
    _sr3c-dispatch STREAMS-OPDISPATCH-SPOOL-STATUS@
        STREAMS-SPOOL-S-FULL-ITEMS = _sr3c-assert
    _sr3c-store PSTORE-GENERATION@
        _sr3c-generation-before @ = _sr3c-assert
    _sr3c-ready@ STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-ready _sr3c-attempt-before STREAMS-OPATT-SIZE
        _sr3c-bytes= _sr3c-assert
    _sr3c-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 3 = _sr3c-assert
        DUP SPOOLCAP.BYTE-COUNT @ 4113 = _sr3c-assert
        DUP SPOOLCAP.READY-COUNT @ 3 = _sr3c-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3c-assert
        SPOOLCAP.TERMINAL-COUNT @ 0= _sr3c-assert
    _sr3c-build-now @ 5 + _sr3c-producer-retire ;

: _sr3c-hold-compact  ( -- )
    0 1 _sr3c-pool STREAMS-EXECUTION-POOL-ACQUIRE
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-held-lease-a !
    _sr3c-held-flow-a !
    _sr3c-held-flow-a @ _sr3c-compact-flow = _sr3c-assert ;

: _sr3c-hold-standard  ( -- )
    0 4097 _sr3c-pool STREAMS-EXECUTION-POOL-ACQUIRE
        STREAMS-FLOW-S-OK _sr3c-status
    _sr3c-held-lease-b !
    _sr3c-held-flow-b !
    _sr3c-held-flow-b @ _sr3c-standard-flow = _sr3c-assert ;

: _sr3c-release-held-compact  ( -- )
    _sr3c-held-flow-a @ _sr3c-held-lease-a @ _sr3c-pool
        STREAMS-EXECUTION-POOL-RELEASE
        STREAMS-FLOW-S-OK _sr3c-status
    0 _sr3c-held-flow-a !
    0 _sr3c-held-lease-a ! ;

: _sr3c-release-held-standard  ( -- )
    _sr3c-held-flow-b @ _sr3c-held-lease-b @ _sr3c-pool
        STREAMS-EXECUTION-POOL-RELEASE
        STREAMS-FLOW-S-OK _sr3c-status
    0 _sr3c-held-flow-b !
    0 _sr3c-held-lease-b ! ;

: _sr3c-snapshot-ready  ( -- )
    _sr3c-store PSTORE-GENERATION@
        _sr3c-generation-before !
    _sr3c-ready@ STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-ready _sr3c-attempt-before
        STREAMS-OPATT-SIZE MOVE ;

: _sr3c-check-ready-snapshot  ( -- )
    _sr3c-store PSTORE-GENERATION@
        _sr3c-generation-before @ = _sr3c-assert
    _sr3c-ready@ STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-ready _sr3c-attempt-before STREAMS-OPATT-SIZE
        _sr3c-bytes= _sr3c-assert ;

: _sr3c-runtime-full-pressure  ( now-ms -- )
    _sr3c-build-now !
    _sr3c-hold-compact
    _sr3c-hold-standard
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 2 =
        _sr3c-assert
    _sr3c-snapshot-ready
    _sr3c-remote-starts @ _sr3c-starts-before !
    _sr3c-build-now @ _sr3c-dispatch
        STREAMS-OPDISPATCH-DISPATCH
        STREAMS-OPDISPATCH-S-RUNTIME-FULL _sr3c-status
    _sr3c-dispatch STREAMS-OPDISPATCH-STATUS@
        STREAMS-OPDISPATCH-S-RUNTIME-FULL = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-FLOW-STATUS@
        STREAMS-FLOW-S-FULL = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-STATE@
        STREAMS-OPDISPATCH-STATE-READY = _sr3c-assert
    _sr3c-remote-starts @ _sr3c-starts-before @ =
        _sr3c-assert
    _sr3c-check-ready-snapshot
    _sr3c-release-held-compact
    _sr3c-release-held-standard
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
        _sr3c-assert ;

: _sr3c-runtime-capacity-pressure  ( now-ms -- )
    _sr3c-build-now !
    _sr3c-hold-standard
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 1 =
        _sr3c-assert
    _sr3c-snapshot-ready
    _sr3c-ready SOPATT.ATTEMPT-ID
        _sr3c-large-id RID= _sr3c-assert
    _sr3c-remote-starts @ _sr3c-starts-before !
    _sr3c-build-now @ _sr3c-dispatch
        STREAMS-OPDISPATCH-DISPATCH
        STREAMS-OPDISPATCH-S-RUNTIME-CAPACITY _sr3c-status
    _sr3c-dispatch STREAMS-OPDISPATCH-STATUS@
        STREAMS-OPDISPATCH-S-RUNTIME-CAPACITY = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-FLOW-STATUS@
        STREAMS-FLOW-S-CAPACITY = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-STATE@
        STREAMS-OPDISPATCH-STATE-READY = _sr3c-assert
    _sr3c-remote-starts @ _sr3c-starts-before @ =
        _sr3c-assert
    _sr3c-check-ready-snapshot
    _sr3c-release-held-standard
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
        _sr3c-assert ;

: _sr3c-runtime-clean?  ( -- flag )
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0=
    _sr3c-compact-flow SFLOW.STATE @
        STREAMS-FLOW-STATE-IDLE = AND
    _sr3c-standard-flow SFLOW.STATE @
        STREAMS-FLOW-STATE-IDLE = AND
    _sr3c-compact-flow SFLOW.INGRESS-CARRIER SPAY.BYTE-U @ 0= AND
    _sr3c-compact-flow SFLOW.EGRESS-CARRIER SPAY.BYTE-U @ 0= AND
    _sr3c-standard-flow SFLOW.INGRESS-CARRIER SPAY.BYTE-U @ 0= AND
    _sr3c-standard-flow SFLOW.EGRESS-CARRIER SPAY.BYTE-U @ 0= AND
    _sr3c-compact-operation
        STREAMS-RUNTIME-PROFILE-COMPACT
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr3c-zero? AND
    _sr3c-standard-operation
        STREAMS-RUNTIME-PROFILE-STANDARD
            STREAMS-RUNTIME-OPERATION-CAPACITY
        _sr3c-zero? AND
    _sr3c-remote-output SCON.CALLBACK-BUSY @ 0= AND
    _sr3c-dispatch-input SCON.CALLBACK-BUSY @ 0= AND ;

: _sr3c-check-zero-receipt  ( attempt-id -- )
    DUP _sr3c-current-id RID-COPY
    _sr3c-receipt
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-RECEIPT@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-receipt STREAMS-OPRECEIPT-SIZE
        STREAMS-OPRECEIPT-VALID? _sr3c-assert
    _sr3c-receipt
        DUP SOPRECEIPT.ATTEMPT-ID
            _sr3c-current-id RID= _sr3c-assert
        DUP SOPRECEIPT.DELIVERY-ID RID-PRESENT? _sr3c-assert
        DUP SOPRECEIPT.REMOTE-RECEIPT-U @ 0= _sr3c-assert
        DUP SOPRECEIPT.REMOTE-CORRELATION-U @ 0= _sr3c-assert
        DUP SOPRECEIPT.REMOTE-DIGEST SHA3-256-LEN
            _sr3c-zero? _sr3c-assert
        SOPRECEIPT.REMOTE-BLOB PBLOB-SIZE
            _sr3c-zero? _sr3c-assert ;

: _sr3c-check-delivered-terminal  ( -- )
    _sr3c-current-id _sr3c-attempt@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-attempt
        DUP SOPATT.RECORD-REVISION @ 3 = _sr3c-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-DELIVERED =
            _sr3c-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-APPLIED =
            _sr3c-assert
        DUP SOPATT.REASON @ STREAMS-OPATT-REASON-OUTPUT =
            _sr3c-assert
        DUP SOPATT.DETAIL @ 0= _sr3c-assert
        DUP SOPATT.ERROR @ 0= _sr3c-assert
        DUP SOPATT.CLEANUP-ERROR @ 0= _sr3c-assert
        DUP SOPATT.FINISHED-MS @
            _sr3c-dispatch-ms @ 1+ = _sr3c-assert
        DUP SOPATT.FLAGS @ STREAMS-OPATT-F-RECEIPT-PRESENT =
            _sr3c-assert
        SOPATT.RECEIPT-ID RID-PRESENT? _sr3c-assert
    _sr3c-current-id _sr3c-check-zero-receipt ;

: _sr3c-check-failure-terminal  ( -- )
    _sr3c-current-id _sr3c-attempt@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-attempt
        DUP SOPATT.RECORD-REVISION @ 3 = _sr3c-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-FAILED-BEFORE =
            _sr3c-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-NOT-APPLIED =
            _sr3c-assert
        DUP SOPATT.REASON @ STREAMS-OPATT-REASON-OUTPUT =
            _sr3c-assert
        DUP SOPATT.DETAIL @ -491 = _sr3c-assert
        DUP SOPATT.ERROR @ -4901 = _sr3c-assert
        DUP SOPATT.CLEANUP-ERROR @ -770 = _sr3c-assert
        DUP SOPATT.FINISHED-MS @
            _sr3c-dispatch-ms @ 1+ = _sr3c-assert
        DUP SOPATT.FLAGS @ 0= _sr3c-assert
        SOPATT.RECEIPT-ID RID-ZERO? _sr3c-assert
    _sr3c-current-id _sr3c-receipt
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-RECEIPT@
        STREAMS-SPOOL-S-NOT-FOUND _sr3c-status ;

: _sr3c-dispatch-success
  ( attempt-id mode expected-profile now-ms -- )
    _sr3c-dispatch-ms !
    _sr3c-expected-profile !
    _sr3c-remote-mode !
    _sr3c-current-id RID-COPY
    _sr3c-ready@ STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-ready SOPATT.ATTEMPT-ID
        _sr3c-current-id RID= _sr3c-assert
    _sr3c-remote-starts @ _sr3c-starts-before !
    _sr3c-dispatch-ms @ _sr3c-dispatch
        STREAMS-OPDISPATCH-DISPATCH
        STREAMS-OPDISPATCH-S-PENDING _sr3c-status
    _sr3c-dispatch STREAMS-OPDISPATCH-STATE@
        STREAMS-OPDISPATCH-STATE-ACTIVE = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-SPOOL-STATUS@
        STREAMS-SPOOL-S-OK = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-FLOW-STATUS@
        STREAMS-FLOW-S-OK = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-PAYLOAD-U@
        _sr3c-ready SOPATT.PAYLOAD-U @ = _sr3c-assert
    _sr3c-dispatch STREAMS-OPDISPATCH-FLOW@
        DUP 0<> _sr3c-assert
        DUP SFLOW.STATE @ STREAMS-FLOW-STATE-OUTPUT-READY =
            _sr3c-assert
        SFLOW.PROFILE @ _sr3c-expected-profile @ =
            _sr3c-assert
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 1 =
        _sr3c-assert
    _sr3c-remote-starts @ _sr3c-starts-before @ =
        _sr3c-assert
    _sr3c-current-id _sr3c-attempt@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-attempt
        DUP SOPATT.RECORD-REVISION @ 2 = _sr3c-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-ACTIVE =
            _sr3c-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-UNCERTAIN =
            _sr3c-assert
        SOPATT.STARTED-MS @
            _sr3c-dispatch-ms @ = _sr3c-assert

    _sr3c-remote-mode @ _SR3C-REMOTE-FAIL-SIGNED = IF
        STREAMS-OPDISPATCH-S-CLEANUP
    ELSE
        STREAMS-OPDISPATCH-S-TERMINAL
    THEN _sr3c-expected-poll-status !
    _sr3c-dispatch-ms @ 1+ _sr3c-dispatch
        STREAMS-OPDISPATCH-POLL
        _sr3c-expected-poll-status @ _sr3c-status
    _sr3c-dispatch STREAMS-OPDISPATCH-STATE@
        STREAMS-OPDISPATCH-STATE-TERMINAL = _sr3c-assert
    _sr3c-remote-starts @ _sr3c-starts-before @ 1+ =
        _sr3c-assert
    _sr3c-start-profile @ _sr3c-expected-profile @ =
        _sr3c-assert
    _sr3c-remote-polls @ 0= _sr3c-assert
    _sr3c-local-starts @ 0= _sr3c-assert
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 1 =
        _sr3c-assert
    _sr3c-remote-mode @ _SR3C-REMOTE-FAIL-SIGNED = IF
        _sr3c-dispatch STREAMS-OPDISPATCH-FLOW-STATUS@
            STREAMS-FLOW-S-CLEANUP = _sr3c-assert
        _sr3c-dispatch STREAMS-OPDISPATCH-CLEANUP-ERROR@
            -770 = _sr3c-assert
        _sr3c-check-failure-terminal
    ELSE
        _sr3c-dispatch STREAMS-OPDISPATCH-FLOW-STATUS@
            STREAMS-FLOW-S-DELIVERED = _sr3c-assert
        _sr3c-dispatch STREAMS-OPDISPATCH-CLEANUP-ERROR@
            0= _sr3c-assert
        _sr3c-check-delivered-terminal
    THEN
    \ POLL already returned and durably recorded any connector cleanup
    \ failure.  RELEASE reports whether runtime retirement itself succeeded.
    _sr3c-dispatch STREAMS-OPDISPATCH-RELEASE
        STREAMS-OPDISPATCH-S-OK _sr3c-status
    _sr3c-dispatch STREAMS-OPDISPATCH-STATE@
        STREAMS-OPDISPATCH-STATE-READY = _sr3c-assert
    _sr3c-runtime-clean? _sr3c-assert ;

: _sr3c-check-first-final-capacity  ( -- )
    _sr3c-capacity@
        DUP SPOOLCAP.ITEM-LIMIT @ 3 = _sr3c-assert
        DUP SPOOLCAP.BYTE-LIMIT @ 4113 = _sr3c-assert
        DUP SPOOLCAP.ITEM-COUNT @ 3 = _sr3c-assert
        DUP SPOOLCAP.BYTE-COUNT @ 4113 = _sr3c-assert
        DUP SPOOLCAP.READY-COUNT @ 1 = _sr3c-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3c-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 1 = _sr3c-assert
        DUP SPOOLCAP.RECEIPT-BYTES @ 0= _sr3c-assert
        DUP SPOOLCAP.CLEANUP-FAILED-COUNT @ 1 = _sr3c-assert
        SPOOLCAP.UNCOMPACTED-CLEANUP-COUNT @ 0= _sr3c-assert ;

: _sr3c-check-cold-existing  ( -- )
    6000 _sr3c-dispatch-ms !
    _sr3c-delivered-id _sr3c-current-id RID-COPY
    _sr3c-check-delivered-terminal
    _sr3c-delivered-id _sr3c-small-delivered 9
        _sr3c-stream-attempt

    7000 _sr3c-dispatch-ms !
    _sr3c-failure-id _sr3c-current-id RID-COPY
    _sr3c-check-failure-terminal
    _sr3c-failure-id _sr3c-small-failure 7
        _sr3c-stream-attempt

    _sr3c-large-id _sr3c-attempt@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-attempt
        DUP SOPATT.RECORD-REVISION @ 1 = _sr3c-assert
        DUP SOPATT.STATE @ STREAMS-OPATT-STATE-ACCEPTED =
            _sr3c-assert
        DUP SOPATT.EFFECT @ STREAMS-OPATT-EFFECT-NOT-APPLIED =
            _sr3c-assert
        DUP SOPATT.PAYLOAD-U @ 4097 = _sr3c-assert
        SOPATT.STARTED-MS @ -1 = _sr3c-assert
    _sr3c-large-id _sr3c-large 4097 _sr3c-stream-attempt
    _sr3c-ready@ STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-ready SOPATT.ATTEMPT-ID
        _sr3c-large-id RID= _sr3c-assert
    _sr3c-check-first-final-capacity ;

: _sr3c-check-cold-final-capacity  ( -- )
    _sr3c-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 3 = _sr3c-assert
        DUP SPOOLCAP.BYTE-COUNT @ 4113 = _sr3c-assert
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 3 = _sr3c-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 2 = _sr3c-assert
        DUP SPOOLCAP.RECEIPT-BYTES @ 0= _sr3c-assert
        DUP SPOOLCAP.CLEANUP-FAILED-COUNT @ 1 = _sr3c-assert
        SPOOLCAP.UNCOMPACTED-CLEANUP-COUNT @ 0= _sr3c-assert ;

: _sr3c-logical-cleanup  ( -- )
    10000 _sr3c-attempt
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-CLEANUP-CANDIDATE@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-attempt SOPATT.ATTEMPT-ID
        _sr3c-delivered-id RID= _sr3c-assert
    _sr3c-attempt SOPATT.ATTEMPT-ID
        _sr3c-current-id RID-COPY
    _sr3c-current-id
    _sr3c-attempt SOPATT.RECORD-REVISION @
    10000 _sr3c-ready
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-CLEANUP
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-ready SOPATT.ATTEMPT-ID
        _sr3c-delivered-id RID= _sr3c-assert
    _sr3c-delivered-id _sr3c-attempt@
        STREAMS-SPOOL-S-NOT-FOUND _sr3c-status
    _sr3c-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3c-assert
        DUP SPOOLCAP.BYTE-COUNT @ 4104 = _sr3c-assert
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3c-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 1 = _sr3c-assert
        DUP SPOOLCAP.RECEIPT-BYTES @ 0= _sr3c-assert
        DUP SPOOLCAP.CLEANUP-FAILED-COUNT @ 1 = _sr3c-assert
        SPOOLCAP.UNCOMPACTED-CLEANUP-COUNT @ 1 = _sr3c-assert ;

: _sr3c-size-result  ( bytes status -- bytes )
    DUP PERSIST-S-OK =
    OVER PERSIST-S-ABSENT = OR _sr3c-assert
    DUP PERSIST-S-ABSENT = IF 2DROP 0 EXIT THEN
    DROP ;

: _sr3c-page-size  ( bank -- bytes )
    _sr3c-store PSTORE-PAGE-FILE-FOR-BANK@
        _sr3c-page-size-work PPAGE-FILE-SIZE?
    _sr3c-size-result ;

: _sr3c-segment-size  ( bank -- bytes )
    _sr3c-store PSTORE-SEGMENT-FILE-FOR-BANK@
        _sr3c-segment-size-work PSEG-FILE-SIZE?
    _sr3c-size-result ;

: _sr3c-compaction-init  ( -- )
    _sr3c-page-size-work PPAGE-WORK-INIT
        PERSIST-S-OK _sr3c-status
    _sr3c-segment-size-buffer 512
        _sr3c-segment-size-work PSEG-WORK-INIT
        PERSIST-S-OK _sr3c-status
    _sr3c-compaction-buffer 512
        _sr3c-compaction-work PCOMPACT-WORK-INIT
        PERSIST-S-OK _sr3c-status
    _sr3c-spool _sr3c-spool-work
        _sr3c-builder-spool _sr3c-builder-spool-work
        _sr3c-compaction-context
        STREAMS-SPOOL-COMPACTION-CONTEXT-INIT
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-store PSTORE-ROOT-FILE@
        _sr3c-builder-store _sr3c-builder-pstore-work
        STREAMS-SPOOL-COMPACTION-STEP-XT
        STREAMS-SPOOL-COMPACTION-FINALIZE-XT
        _sr3c-compaction-context
        65536 64 8192 _sr3c-compaction PCOMPACT-INIT
        PERSIST-S-OK _sr3c-status
    _sr3c-compaction PCOMPACT-VALID? _sr3c-assert
    _sr3c-compaction-context
        STREAMS-SPOOL-COMPACTION-CONTEXT-VALID? _sr3c-assert ;

: _sr3c-compaction-build  ( -- status )
    0 _sr3c-compaction-steps !
    BEGIN
        _sr3c-compaction-work PCOMPACT-STATE@
            PCOMPACT-STATE-BUILDING =
        _sr3c-compaction-steps @ 64 < AND
    WHILE
        _sr3c-compaction-work PCOMPACT-STEP
        DUP PERSIST-S-OK <> IF EXIT THEN
        DROP
        1 _sr3c-compaction-steps +!
    REPEAT
    _sr3c-compaction-work PCOMPACT-STATE@
        PCOMPACT-STATE-READY =
    IF PERSIST-S-OK ELSE PERSIST-S-CAPACITY THEN ;

: _sr3c-compact-live-set  ( -- )
    _sr3c-store PSTORE-GENERATION@ _sr3c-old-generation !
    _sr3c-runtime-clean? _sr3c-assert
    _sr3c-compaction-init
    PERSIST-DATA-BANK-0 _sr3c-page-size 0> _sr3c-assert
    PERSIST-DATA-BANK-0 _sr3c-segment-size 0> _sr3c-assert
    PERSIST-DATA-BANK-1 _sr3c-page-size 0= _sr3c-assert
    PERSIST-DATA-BANK-1 _sr3c-segment-size 0= _sr3c-assert

    _sr3c-compaction _sr3c-compaction-work PCOMPACT-BEGIN
        PERSIST-S-OK _sr3c-status
    _sr3c-compaction-work PCOMPACT-STATE@
        PCOMPACT-STATE-BUILDING = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-SOURCE-BANK@
        PERSIST-DATA-BANK-0 = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-TARGET-BANK@
        PERSIST-DATA-BANK-1 = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-NEXT-GENERATION@
        _sr3c-old-generation @ 1+ = _sr3c-assert

    _sr3c-compaction-build
    DUP PERSIST-S-OK <> IF
        >R
        _sr3c-compaction-context STREAMS-SPOOL-COMPACTION-CANCEL
            STREAMS-SPOOL-S-OK _sr3c-status
        _sr3c-compaction-work PCOMPACT-ABORT
            PERSIST-S-OK _sr3c-status
        R> PERSIST-S-OK _sr3c-status
        EXIT
    THEN
    DROP
    _sr3c-compaction-work PCOMPACT-STATE@
        PCOMPACT-STATE-READY = _sr3c-assert
    _sr3c-compaction-steps @ 1 > _sr3c-assert
    _sr3c-compaction-work PCOMPACT-WORK-USED@
        _sr3c-compaction-steps @ = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-BYTES-USED@
        4097 > _sr3c-assert

    _sr3c-compaction-work PCOMPACT-FINALIZE
        PERSIST-S-OK _sr3c-status
    _sr3c-compaction-work PCOMPACT-STATE@
        PCOMPACT-STATE-FINALIZED = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-TARGET-ROOT@
        DUP 0<> _sr3c-assert
        PROOTV.DATA-BANK @
            PERSIST-DATA-BANK-1 = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-PUBLISH
        PERSIST-S-OK _sr3c-status
    _sr3c-compaction-work PCOMPACT-STATE@
        PCOMPACT-STATE-PUBLISHED = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-MIRROR
        PERSIST-S-OK _sr3c-status
    _sr3c-compaction-work PCOMPACT-STATE@
        PCOMPACT-STATE-MIRRORED = _sr3c-assert
    _sr3c-compaction-work PCOMPACT-CLEANUP-ELIGIBLE?
        _sr3c-assert
    _sr3c-compaction-work PCOMPACT-CLEANUP
        PERSIST-S-OK _sr3c-status
    _sr3c-compaction-work PCOMPACT-STATE@
        PCOMPACT-STATE-CLEANED = _sr3c-assert
    _sr3c-compaction-context STREAMS-SPOOL-COMPACTION-STATUS@
        STREAMS-SPOOL-S-OK = _sr3c-assert

    PERSIST-DATA-BANK-0 _sr3c-page-size 0= _sr3c-assert
    PERSIST-DATA-BANK-0 _sr3c-segment-size 0= _sr3c-assert
    PERSIST-DATA-BANK-1 _sr3c-page-size 0> _sr3c-assert
    PERSIST-DATA-BANK-1 _sr3c-segment-size 0> _sr3c-assert

    \ Rebuild current descriptors from serialized authority and force the
    \ normal cold physical audit against the selected compacted bank.
    _sr3c-spool-bind STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-store PSTORE-GENERATION@
        _sr3c-old-generation @ 1+ = _sr3c-assert
    _sr3c-store PSTORE-CURRENT-ROOT@ PROOTV.DATA-BANK @
        PERSIST-DATA-BANK-1 = _sr3c-assert ;

: _sr3c-check-compacted-usage  ( -- )
    _sr3c-local-id _sr3c-connector-usage
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-CONNECTOR-USAGE@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-connector-usage
        STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-VALID? _sr3c-assert
    _sr3c-connector-usage
        STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-ITEM-COUNT@
        _sr3c-assert 0= _sr3c-assert
    _sr3c-connector-usage
        STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-PAYLOAD-BYTES@
        _sr3c-assert 0= _sr3c-assert

    _sr3c-remote-id _sr3c-connector-usage
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-CONNECTOR-USAGE@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-connector-usage
        STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-ITEM-COUNT@
        _sr3c-assert 2 = _sr3c-assert
    _sr3c-connector-usage
        STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-PAYLOAD-BYTES@
        _sr3c-assert 4104 = _sr3c-assert

    _sr3c-flow-id _sr3c-flow-usage
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-FLOW-USAGE@
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-FLOW-USAGE-VALUE-VALID? _sr3c-assert
    _sr3c-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-FLOW-USAGE-VALUE-ACTIVE-COUNT@
        _sr3c-assert 0= _sr3c-assert ;

: _sr3c-check-compacted-live-set  ( -- )
    _sr3c-delivered-id _sr3c-attempt@
        STREAMS-SPOOL-S-NOT-FOUND _sr3c-status

    7000 _sr3c-dispatch-ms !
    _sr3c-failure-id _sr3c-current-id RID-COPY
    _sr3c-check-failure-terminal
    _sr3c-failure-id _sr3c-small-failure 7
        _sr3c-stream-attempt

    9000 _sr3c-dispatch-ms !
    _sr3c-large-id _sr3c-current-id RID-COPY
    _sr3c-check-delivered-terminal
    _sr3c-large-id _sr3c-large 4097
        _sr3c-stream-attempt

    _sr3c-ready@ STREAMS-SPOOL-S-NOT-FOUND _sr3c-status
    _sr3c-capacity@
        DUP SPOOLCAP.ITEM-LIMIT @ 3 = _sr3c-assert
        DUP SPOOLCAP.BYTE-LIMIT @ 4113 = _sr3c-assert
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3c-assert
        DUP SPOOLCAP.BYTE-COUNT @ 4104 = _sr3c-assert
        DUP SPOOLCAP.READY-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.TERMINAL-COUNT @ 2 = _sr3c-assert
        DUP SPOOLCAP.INDETERMINATE-COUNT @ 0= _sr3c-assert
        DUP SPOOLCAP.RECEIPT-COUNT @ 1 = _sr3c-assert
        DUP SPOOLCAP.RECEIPT-BYTES @ 0= _sr3c-assert
        DUP SPOOLCAP.CLEANUP-FAILED-COUNT @ 1 = _sr3c-assert
        SPOOLCAP.UNCOMPACTED-CLEANUP-COUNT @ 0= _sr3c-assert
    _sr3c-check-compacted-usage ;

: _sr3c-reset  ( -- )
    0 _sr3c-fails !
    0 _sr3c-checks !
    0 _sr3c-remote-mode !
    0 _sr3c-remote-starts !
    0 _sr3c-remote-polls !
    0 _sr3c-remote-cancels !
    0 _sr3c-remote-cleanups !
    0 _sr3c-local-starts !
    0 _sr3c-local-polls !
    0 _sr3c-local-cancels !
    0 _sr3c-local-cleanups !
    0 _sr3c-start-profile !
    0 _sr3c-stream-u !
    0 _sr3c-held-flow-a !
    0 _sr3c-held-flow-b !
    0 _sr3c-held-lease-a !
    0 _sr3c-held-lease-b !
    _sr3c-current-id RID-CLEAR ;

: _sr3c-first-journey  ( -- )
    _sr3c-spool-bind STREAMS-SPOOL-S-ABSENT _sr3c-status
    _sr3c-authority 3 4113 3 10000
        _sr3c-current-spool @ _sr3c-current-work @
        STREAMS-SPOOL-PROVISION
        STREAMS-SPOOL-S-OK _sr3c-status
    _sr3c-setup-operational-config
    _sr3c-install-operational-config
    _sr3c-setup-runtime

    _sr3c-small-delivered 9 0x61 1000
        _sr3c-result-delivered _sr3c-delivered-id
        _sr3c-enqueue-success
    _sr3c-small-failure 7 0x71 2000
        _sr3c-result-failure _sr3c-failure-id
        _sr3c-enqueue-success
    _sr3c-large 4097 0x81 3000
        _sr3c-result-large _sr3c-large-id
        _sr3c-enqueue-success
    _sr3c-capacity@
        DUP SPOOLCAP.ITEM-COUNT @ 3 = _sr3c-assert
        DUP SPOOLCAP.BYTE-COUNT @ 4113 = _sr3c-assert
        DUP SPOOLCAP.READY-COUNT @ 3 = _sr3c-assert
        DUP SPOOLCAP.ACTIVE-COUNT @ 0= _sr3c-assert
        SPOOLCAP.TERMINAL-COUNT @ 0= _sr3c-assert

    \ Durable pressure is independent of the entirely free runtime pool.
    _sr3c-pool STREAMS-EXECUTION-POOL-ACTIVE@ 0= _sr3c-assert
    _sr3c-small-refused 7 0x91 4000 _sr3c-enqueue-refused

    \ Runtime pressure cannot consume or mutate the durable oldest READY row.
    5000 _sr3c-runtime-full-pressure

    _sr3c-delivered-id _SR3C-REMOTE-DELIVER
        STREAMS-RUNTIME-PROFILE-COMPACT 6000
        _sr3c-dispatch-success
    _sr3c-failure-id _SR3C-REMOTE-FAIL-SIGNED
        STREAMS-RUNTIME-PROFILE-STANDARD 7000
        _sr3c-dispatch-success

    \ A free compact cell does not make a 4,097-byte attempt dispatchable.
    8000 _sr3c-runtime-capacity-pressure
    _sr3c-check-first-final-capacity
    _sr3c-remote-starts @ 2 = _sr3c-assert
    _sr3c-remote-polls @ 0= _sr3c-assert
    _sr3c-remote-cancels @ 0= _sr3c-assert
    _sr3c-remote-cleanups @ 2 = _sr3c-assert
    _sr3c-local-starts @ 0= _sr3c-assert
    _sr3c-runtime-clean? _sr3c-assert ;

: _sr3c-cold-journey  ( -- )
    _sr3c-spool-bind STREAMS-SPOOL-S-OK _sr3c-status
    \ The bridge receives fresh runtime descriptors and current semantic
    \ config; no runtime address was recovered from disk.
    _sr3c-setup-operational-config
    _sr3c-setup-runtime
    _sr3c-check-cold-existing
    _sr3c-large-id _SR3C-REMOTE-DELIVER
        STREAMS-RUNTIME-PROFILE-STANDARD 9000
    _sr3c-dispatch-success
    _sr3c-check-cold-final-capacity
    _sr3c-logical-cleanup
    _sr3c-compact-live-set
    _sr3c-check-compacted-live-set
    _sr3c-remote-starts @ 1 = _sr3c-assert
    _sr3c-remote-polls @ 0= _sr3c-assert
    _sr3c-remote-cancels @ 0= _sr3c-assert
    _sr3c-remote-cleanups @ 1 = _sr3c-assert
    _sr3c-local-starts @ 0= _sr3c-assert
    _sr3c-runtime-clean? _sr3c-assert ;

: _sr3c-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _sr3c-hex-byte  ( byte -- )
    DUP 16 / _sr3c-hex-digit
    15 AND _sr3c-hex-digit ;

: _sr3c-rid.  ( rid -- )
    RID-SIZE 0 DO
        DUP I + C@ _sr3c-hex-byte
    LOOP
    DROP ;

: _SR3C-FIRST-RUN  ( -- )
    0 _sr3c-cold? !
    _sr3c-reset
    _sr3c-setup-bytes
    DEPTH _sr3c-depth !
    1 _sr3c-progress
    _sr3c-runtime-open
    2 _sr3c-progress
    _sr3c-first-journey
    3 _sr3c-progress
    _sr3c-runtime-close
    _sr3c-stack
    _sr3c-fails @ IF
        ." STREAMS SR3 COMPOSED FIRST BOOT FAIL "
        _sr3c-fails @ . ." / " _sr3c-checks @ . CR
    ELSE
        ." STREAMS SR3 COMPOSED DELIVERED RID "
            _sr3c-delivered-id _sr3c-rid. CR
        ." STREAMS SR3 COMPOSED FAILURE RID "
            _sr3c-failure-id _sr3c-rid. CR
        ." STREAMS SR3 COMPOSED LARGE RID "
            _sr3c-large-id _sr3c-rid. CR
        ." STREAMS SR3 COMPOSED FIRST BOOT PASS "
            _sr3c-checks @ . CR
    THEN ;

: _SR3C-COLD-RUN  ( delivered-id failure-id large-id -- )
    -1 _sr3c-cold? !
    _sr3c-reset
    _sr3c-setup-bytes
    _sr3c-large-id RID-COPY
    _sr3c-failure-id RID-COPY
    _sr3c-delivered-id RID-COPY
    DEPTH _sr3c-depth !
    20 _sr3c-progress
    _sr3c-runtime-open
    21 _sr3c-progress
    _sr3c-cold-journey
    22 _sr3c-progress
    _sr3c-runtime-close
    _sr3c-stack
    _sr3c-fails @ IF
        ." STREAMS SR3 COMPOSED COLD BOOT FAIL "
        _sr3c-fails @ . ." / " _sr3c-checks @ . CR
    ELSE
        ." STREAMS SR3 COMPOSED COLD BOOT PASS "
            _sr3c-checks @ . CR
    THEN ;
