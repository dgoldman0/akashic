\ streams-sr3-admission.f - Focused SR3 Landing 1 admission contracts
\
\ This fixture uses a bounded RAM VFS and the public Streams spool surface.
\ It qualifies one current prerelease format only: there are no compatibility
\ readers, migrations, or alternate encodings in this gate.

PROVIDED akashic-sr3-admit-gate

VARIABLE _sr3a-fails
VARIABLE _sr3a-checks
VARIABLE _sr3a-depth
VARIABLE _sr3a-arena
VARIABLE _sr3a-vfs
VARIABLE _sr3a-ior
VARIABLE _sr3a-old-vfs
VARIABLE _sr3a-fault-at
VARIABLE _sr3a-source-calls
VARIABLE _sr3a-sink-bytes
VARIABLE _sr3a-page-id
VARIABLE _sr3a-old-generation
VARIABLE _sr3a-old-items
VARIABLE _sr3a-old-bytes
VARIABLE _sr3a-build-a
VARIABLE _sr3a-build-u
VARIABLE _sr3a-build-seed
VARIABLE _sr3a-build-xt
VARIABLE _sr3a-check-a
VARIABLE _sr3a-check-u
VARIABLE _sr3a-check-result
VARIABLE _sr3a-usage-items
VARIABLE _sr3a-usage-bytes
VARIABLE _sr3a-usage-active
VARIABLE _sr3a-usage-spool
VARIABLE _sr3a-usage-work

CREATE _sr3a-ops VFS-OPS-SIZE ALLOT
CREATE _sr3a-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _sr3a-identity PERSIST-IDENTITY-SIZE ALLOT

CREATE _sr3a-store-a PSTORE-SIZE ALLOT
CREATE _sr3a-store-b PSTORE-SIZE ALLOT
CREATE _sr3a-pwork-a PSTORE-WORK-SIZE ALLOT
CREATE _sr3a-pwork-b PSTORE-WORK-SIZE ALLOT
CREATE _sr3a-record-buffer-a STREAMS-SPOOL-RECORD-BUFFER-MIN ALLOT
CREATE _sr3a-record-buffer-b STREAMS-SPOOL-RECORD-BUFFER-MIN ALLOT
GUARD _sr3a-guard-a
GUARD _sr3a-guard-b

CREATE _sr3a-spool-a STREAMS-SPOOL-SIZE ALLOT
CREATE _sr3a-spool-b STREAMS-SPOOL-SIZE ALLOT
CREATE _sr3a-work-a STREAMS-SPOOL-WORK-SIZE ALLOT
CREATE _sr3a-work-b STREAMS-SPOOL-WORK-SIZE ALLOT

\ The RAM arena is a strict upper bound for either page bank.  Bind enough
\ caller-owned cold-audit space for that impossible-to-exceed page count plus
\ this fixture's one connector, one flow, and two retained attempts.
4194304 PERSIST-PAGE-FILE-SIZE /
    1 1 2 STREAMS-SPOOL-COLD-AUDIT-BYTES?
STREAMS-SPOOL-S-OK <> [IF]
    ." STREAMS SR3 ADMISSION AUDIT GEOMETRY" CR ABORT
[THEN]
CONSTANT _sr3a-cold-audit-u

CREATE _sr3a-cold-audit-a-storage _sr3a-cold-audit-u 7 + ALLOT
_sr3a-cold-audit-a-storage 7 + 7 INVERT AND
    CONSTANT _sr3a-cold-audit-a
CREATE _sr3a-cold-audit-b-storage _sr3a-cold-audit-u 7 + ALLOT
_sr3a-cold-audit-b-storage 7 + 7 INVERT AND
    CONSTANT _sr3a-cold-audit-b

CREATE _sr3a-authority-main RID-SIZE ALLOT
CREATE _sr3a-authority-bytes RID-SIZE ALLOT
CREATE _sr3a-authority-items RID-SIZE ALLOT
CREATE _sr3a-authority-fault RID-SIZE ALLOT
CREATE _sr3a-authority-unknown RID-SIZE ALLOT
CREATE _sr3a-authority-corrupt RID-SIZE ALLOT
CREATE _sr3a-connector-id RID-SIZE ALLOT
CREATE _sr3a-flow-id RID-SIZE ALLOT
CREATE _sr3a-endpoint-id RID-SIZE ALLOT
CREATE _sr3a-endpoint-seal RID-SIZE ALLOT
CREATE _sr3a-route-id RID-SIZE ALLOT
CREATE _sr3a-transform-id RID-SIZE ALLOT
CREATE _sr3a-origin-id RID-SIZE ALLOT
CREATE _sr3a-destination-id RID-SIZE ALLOT

CREATE _sr3a-connector STREAMS-OPCONN-SIZE ALLOT
CREATE _sr3a-flow STREAMS-OPFLOW-SIZE ALLOT
CREATE _sr3a-request-a STREAMS-SPOOL-REQUEST-SIZE ALLOT
CREATE _sr3a-request-b STREAMS-SPOOL-REQUEST-SIZE ALLOT
CREATE _sr3a-result-a STREAMS-SPOOL-RESULT-SIZE ALLOT
CREATE _sr3a-result-b STREAMS-SPOOL-RESULT-SIZE ALLOT
CREATE _sr3a-result-before STREAMS-SPOOL-RESULT-SIZE ALLOT
CREATE _sr3a-attempt STREAMS-OPATT-SIZE ALLOT
CREATE _sr3a-capacity STREAMS-SPOOL-CAPACITY-SIZE ALLOT
CREATE _sr3a-root-view STREAMS-OPROOT-SIZE ALLOT
CREATE _sr3a-connector-usage
    STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE ALLOT
CREATE _sr3a-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE ALLOT
CREATE _sr3a-cold-connector-entry
    _SSP-COLD-CONNECTOR-ENTRY-SIZE ALLOT
CREATE _sr3a-cold-flow-entry _SSP-COLD-FLOW-ENTRY-SIZE ALLOT
CREATE _sr3a-cold-accepted 2 CELLS ALLOT
CREATE _sr3a-cold-ready 2 CELLS ALLOT

CREATE _sr3a-payload-1 1 ALLOT
CREATE _sr3a-payload-4 4 ALLOT
CREATE _sr3a-payload-6 6 ALLOT
CREATE _sr3a-expected 64 ALLOT
CREATE _sr3a-readback 64 ALLOT
CREATE _sr3a-root-page PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _sr3a-root-value-before PERSIST-ROOT-VALUE-SIZE ALLOT

STREAMS-OPATT-SIZE PBLOB-CHUNK-SIZE MAX
    CONSTANT _sr3a-segment-payload-max

: _sr3a-assert  ( flag -- )
    1 _sr3a-checks +!
    0= IF
        1 _sr3a-fails +!
        ." STREAMS SR3 ADMISSION ASSERT " _sr3a-checks @ . CR
    THEN ;

: _sr3a-stack  ( -- )
    DEPTH DUP _sr3a-depth @ <> IF
        ." STREAMS SR3 ADMISSION STACK "
        _sr3a-depth @ . ." -> " DUP . CR .S CR
    THEN
    _sr3a-depth @ = _sr3a-assert ;

: _sr3a-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS SR3 ADMISSION STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _sr3a-assert _sr3a-stack ;

: _sr3a-status-either  ( actual expected-a expected-b -- )
    >R OVER = SWAP R> = OR _sr3a-assert _sr3a-stack ;

: _sr3a-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    DUP 0= IF DROP 2DROP -1 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _sr3a-rid-fill  ( byte rid -- )
    RID-SIZE ROT FILL ;

: _sr3a-result-sentinel  ( result -- )
    DUP STREAMS-SPOOL-RESULT-SIZE 0xA5 FILL
    _sr3a-result-before STREAMS-SPOOL-RESULT-SIZE MOVE ;

: _sr3a-result-unchanged?  ( result -- flag )
    _sr3a-result-before STREAMS-SPOOL-RESULT-SIZE _sr3a-bytes= ;

: _sr3a-fault  ( point ordinal context -- status )
    2DROP
    _sr3a-fault-at @ = IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN ;

\ PBLOB source: ( logical-offset destination requested-u context
\                 -- actual-u status )
: _sr3a-exact-source
  ( logical-offset destination requested-u context -- actual-u status )
    >R
    1 _sr3a-source-calls +!
    2 PICK R@ + 2 PICK 2 PICK MOVE
    NIP NIP PERSIST-S-OK
    R> DROP ;

: _sr3a-under-source
  ( logical-offset destination requested-u context -- actual-u status )
    >R
    1 _sr3a-source-calls +!
    2DROP DROP
    0 PERSIST-S-OK
    R> DROP ;

: _sr3a-over-source
  ( logical-offset destination requested-u context -- actual-u status )
    >R
    1 _sr3a-source-calls +!
    NIP NIP 1+ PERSIST-S-OK
    R> DROP ;

: _sr3a-failing-source
  ( logical-offset destination requested-u context -- actual-u status )
    >R
    1 _sr3a-source-calls +!
    2DROP DROP
    0 PERSIST-S-FAULT
    R> DROP ;

: _sr3a-throwing-source
  ( logical-offset destination requested-u context -- actual-u status )
    >R
    1 _sr3a-source-calls +!
    2DROP DROP
    R> DROP -739 THROW ;

\ Exercise outer cleanup if an unexpected exception interrupts cold setup
\ after PSTORE is borrowed but before reclaim audit takes ownership.
: _sr3a-cold-throw-body  ( work -- status )
    >R
    _SSPW-STATE-REOPEN R@ _SSPW.STATE !
    R@ _SSPW.SPOOL @ _SSP-D.STORE @
    R@ _SSPW.PSTORE-WORK @ PSTORE-BEGIN
    DUP IF _SSP-PERSIST>STATUS R> DROP EXIT THEN DROP
    _SSPW-TX-STORE R@ _SSPW.TX-PHASE !
    R> DROP -740 THROW ;

\ Public payload sink: ( logical-offset payload-a payload-u context -- status )
: _sr3a-sink
  ( logical-offset payload-a payload-u context -- status )
    >R
    2 PICK _sr3a-sink-bytes @ <> IF
        2DROP DROP R> DROP PERSIST-S-CORRUPT EXIT
    THEN
    OVER 3 PICK R@ + 2 PICK MOVE
    DUP _sr3a-sink-bytes +!
    2DROP DROP
    PERSIST-S-OK
    R> DROP ;

: _sr3a-setup-vfs  ( -- )
    VFS-CUR _sr3a-old-vfs !
    VFS-RAM-OPS _sr3a-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _sr3a-binding VFS-BINDING-DESC-SIZE MOVE
    _sr3a-ops _sr3a-binding VB.OPS !
    4194304 A-XMEM ARENA-NEW
    DUP 0= _sr3a-assert DROP _sr3a-arena !
    _sr3a-arena @ _sr3a-binding 0 VFS-NEW
    _sr3a-ior ! _sr3a-vfs !
    _sr3a-ior @ 0= _sr3a-assert
    _sr3a-vfs @ 0<> _sr3a-assert
    _sr3a-identity PERSIST-IDENTITY-SIZE 0x19 FILL
    0 _sr3a-fault-at ! ;

: _sr3a-setup-identities  ( -- )
    _sr3a-identity _sr3a-authority-main RID-COPY
    _sr3a-identity _sr3a-authority-bytes RID-COPY
    _sr3a-identity _sr3a-authority-items RID-COPY
    _sr3a-identity _sr3a-authority-fault RID-COPY
    _sr3a-identity _sr3a-authority-unknown RID-COPY
    _sr3a-identity _sr3a-authority-corrupt RID-COPY
    0x21 _sr3a-connector-id _sr3a-rid-fill
    0x22 _sr3a-flow-id _sr3a-rid-fill
    0x23 _sr3a-endpoint-id _sr3a-rid-fill
    0x24 _sr3a-endpoint-seal _sr3a-rid-fill
    0x25 _sr3a-route-id _sr3a-rid-fill
    0x26 _sr3a-transform-id _sr3a-rid-fill
    0x27 _sr3a-origin-id _sr3a-rid-fill
    _sr3a-endpoint-id _sr3a-destination-id RID-COPY
    _sr3a-payload-1 1 0x31 FILL
    _sr3a-payload-4 4 0x41 FILL
    _sr3a-payload-6 6 0x61 FILL ;

\ Each pair uses the same paths and identity to model a fresh descriptor
\ opening the authority written by its A-side predecessor.
: _sr3a-main-store-a-init  ( -- status )
    S" /s3am-p" S" /s3am-s" S" /s3am-ra" S" /s3am-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-a ['] _sr3a-fault 0 _sr3a-store-a PSTORE-INIT ;

: _sr3a-main-store-b-init  ( -- status )
    S" /s3am-p" S" /s3am-s" S" /s3am-ra" S" /s3am-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-b ['] _sr3a-fault 0 _sr3a-store-b PSTORE-INIT ;

: _sr3a-bytes-store-a-init  ( -- status )
    S" /s3ab-p" S" /s3ab-s" S" /s3ab-ra" S" /s3ab-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-a ['] _sr3a-fault 0 _sr3a-store-a PSTORE-INIT ;

: _sr3a-items-store-a-init  ( -- status )
    S" /s3ai-p" S" /s3ai-s" S" /s3ai-ra" S" /s3ai-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-a ['] _sr3a-fault 0 _sr3a-store-a PSTORE-INIT ;

: _sr3a-fault-store-a-init  ( -- status )
    S" /s3af-p" S" /s3af-s" S" /s3af-ra" S" /s3af-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-a ['] _sr3a-fault 0 _sr3a-store-a PSTORE-INIT ;

: _sr3a-fault-store-b-init  ( -- status )
    S" /s3af-p" S" /s3af-s" S" /s3af-ra" S" /s3af-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-b ['] _sr3a-fault 0 _sr3a-store-b PSTORE-INIT ;

: _sr3a-unknown-store-a-init  ( -- status )
    S" /s3au-p" S" /s3au-s" S" /s3au-ra" S" /s3au-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-a ['] _sr3a-fault 0 _sr3a-store-a PSTORE-INIT ;

: _sr3a-unknown-store-b-init  ( -- status )
    S" /s3au-p" S" /s3au-s" S" /s3au-ra" S" /s3au-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-b ['] _sr3a-fault 0 _sr3a-store-b PSTORE-INIT ;

: _sr3a-corrupt-store-a-init  ( -- status )
    S" /s3ac-p" S" /s3ac-s" S" /s3ac-ra" S" /s3ac-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-a ['] _sr3a-fault 0 _sr3a-store-a PSTORE-INIT ;

: _sr3a-corrupt-store-b-init  ( -- status )
    S" /s3ac-p" S" /s3ac-s" S" /s3ac-ra" S" /s3ac-rb"
    _sr3a-identity _sr3a-segment-payload-max _sr3a-vfs @ 0 0
    _sr3a-guard-b ['] _sr3a-fault 0 _sr3a-store-b PSTORE-INIT ;

: _sr3a-bind-a  ( store-init-xt -- status )
    EXECUTE DUP IF EXIT THEN DROP
    _sr3a-record-buffer-a STREAMS-SPOOL-RECORD-BUFFER-MIN
        _sr3a-pwork-a PSTORE-WORK-INIT DUP IF EXIT THEN DROP
    _sr3a-store-a _sr3a-pwork-a PSTORE-PROVISION DUP IF EXIT THEN DROP
    _sr3a-store-a _sr3a-spool-a STREAMS-SPOOL-INIT DUP IF EXIT THEN DROP
    _sr3a-cold-audit-a _sr3a-cold-audit-u
        _sr3a-pwork-a _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-WORK-INIT DUP IF EXIT THEN DROP
    _sr3a-spool-a _sr3a-work-a STREAMS-SPOOL-OPEN ;

: _sr3a-bind-b  ( store-init-xt -- status )
    EXECUTE DUP IF EXIT THEN DROP
    _sr3a-record-buffer-b STREAMS-SPOOL-RECORD-BUFFER-MIN
        _sr3a-pwork-b PSTORE-WORK-INIT DUP IF EXIT THEN DROP
    _sr3a-store-b _sr3a-pwork-b PSTORE-PROVISION DUP IF EXIT THEN DROP
    _sr3a-store-b _sr3a-spool-b STREAMS-SPOOL-INIT DUP IF EXIT THEN DROP
    _sr3a-cold-audit-b _sr3a-cold-audit-u
        _sr3a-pwork-b _sr3a-spool-b _sr3a-work-b
        STREAMS-SPOOL-WORK-INIT DUP IF EXIT THEN DROP
    _sr3a-spool-b _sr3a-work-b STREAMS-SPOOL-OPEN ;

: _sr3a-open-fresh-a  ( store-init-xt -- )
    _sr3a-bind-a STREAMS-SPOOL-S-ABSENT _sr3a-status
    _sr3a-root-view STREAMS-OPROOT-SIZE 0xA5 FILL
    _sr3a-root-view _sr3a-work-a STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-ABSENT _sr3a-status
    _sr3a-stack ;

: _sr3a-provision-a  ( authority-rid item-limit byte-limit -- )
    OVER 0 _sr3a-spool-a _sr3a-work-a STREAMS-SPOOL-PROVISION
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-root-view _sr3a-work-a STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-root-view
        DUP SOPROOT.ITEM-COUNT @ 0= _sr3a-assert
        DUP SOPROOT.PAYLOAD-BYTES @ 0= _sr3a-assert
        SOPROOT.READY-COUNT @ 0= _sr3a-assert
    _sr3a-stack ;

\ These four calls are the intentionally narrow Landing 1 public seams.
\ Their stack effects are part of this gate:
\   CONNECTOR-PUT ( connector spool work -- status )
\   FLOW-PUT      ( flow spool work -- status )
\   ATTEMPT@      ( attempt-id destination spool work -- status )
\   PAYLOAD-STREAM
\       ( attempt-id sink-xt sink-context spool work -- status )
: _sr3a-put-config-a  ( -- )
    _sr3a-connector _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-CONNECTOR-PUT
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-flow _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-FLOW-PUT
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-root-view _sr3a-work-a STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-root-view
        DUP SOPROOT.CONNECTOR-COUNT @ 1 = _sr3a-assert
        SOPROOT.FLOW-COUNT @ 1 = _sr3a-assert
    _sr3a-stack ;

: _sr3a-valid-config  ( -- )
    _sr3a-connector STREAMS-OPCONN-INIT
        STREAMS-OPREC-S-OK _sr3a-status
    _sr3a-connector-id _sr3a-connector SOPCONN.CONNECTOR-ID RID-COPY
    _sr3a-endpoint-id _sr3a-connector SOPCONN.ENDPOINT-ID RID-COPY
    _sr3a-endpoint-seal _sr3a-connector SOPCONN.ENDPOINT-SEAL RID-COPY
    1 _sr3a-connector SOPCONN.REVISION !
    STREAMS-OPCONN-DIRECTION-EGRESS
        _sr3a-connector SOPCONN.DIRECTION !
    101 _sr3a-connector SOPCONN.PROTOCOL !
    202 _sr3a-connector SOPCONN.PROFILE !
    STREAMS-OPCONN-ENDPOINT-PINNED
        _sr3a-connector SOPCONN.ENDPOINT-POLICY !
    64 _sr3a-connector SOPCONN.REQUEST-BYTE-LIMIT !
    64 _sr3a-connector SOPCONN.RESPONSE-BYTE-LIMIT !
    64 _sr3a-connector SOPCONN.PAYLOAD-BYTE-LIMIT !
    2 _sr3a-connector SOPCONN.QUEUE-ITEM-LIMIT !
    128 _sr3a-connector SOPCONN.QUEUE-BYTE-LIMIT !
    3 _sr3a-connector SOPCONN.RETRY-LIMIT !
    10 _sr3a-connector SOPCONN.RETRY-DELAY-MS !
    1 _sr3a-connector SOPCONN.REDIRECT-LIMIT !
    100 _sr3a-connector SOPCONN.CONNECT-TIMEOUT-MS !
    500 _sr3a-connector SOPCONN.OPERATION-TIMEOUT-MS !
    100 _sr3a-connector SOPCONN.IDLE-TIMEOUT-MS !
    STREAMS-OPCONN-RECEIPT-BOUNDED
        _sr3a-connector SOPCONN.RECEIPT-POLICY !
    32 _sr3a-connector SOPCONN.RECEIPT-BYTE-LIMIT !
    STREAMS-OPCONN-IDEMPOTENCY-EXACT
        _sr3a-connector SOPCONN.IDEMPOTENCY-POLICY !
    STREAMS-OPCONN-LIFECYCLE-ACTIVE
        _sr3a-connector SOPCONN.LIFECYCLE !
    1 _sr3a-connector SOPCONN.ENABLED !
    STREAMS-OPCONN-HEALTH-HEALTHY
        _sr3a-connector SOPCONN.HEALTH !
    1000 _sr3a-connector SOPCONN.CONFIGURED-MS !
    _sr3a-connector STREAMS-OPCONN-SEAL
        STREAMS-OPREC-S-OK _sr3a-status

    _sr3a-flow STREAMS-OPFLOW-INIT
        STREAMS-OPREC-S-OK _sr3a-status
    _sr3a-flow-id _sr3a-flow SOPFLOW.FLOW-ID RID-COPY
    _sr3a-connector-id
        _sr3a-flow SOPFLOW.INPUT-CONNECTOR-ID RID-COPY
    _sr3a-connector-id
        _sr3a-flow SOPFLOW.OUTPUT-CONNECTOR-ID RID-COPY
    _sr3a-route-id _sr3a-flow SOPFLOW.ROUTE-ID RID-COPY
    _sr3a-transform-id _sr3a-flow SOPFLOW.TRANSFORM-ID RID-COPY
    1 _sr3a-flow SOPFLOW.REVISION !
    1 _sr3a-flow SOPFLOW.INPUT-CONNECTOR-REVISION !
    1 _sr3a-flow SOPFLOW.OUTPUT-CONNECTOR-REVISION !
    1 _sr3a-flow SOPFLOW.ROUTE-REVISION !
    1 _sr3a-flow SOPFLOW.TRANSFORM-REVISION !
    64 _sr3a-flow SOPFLOW.PAYLOAD-BYTE-LIMIT !
    64 _sr3a-flow SOPFLOW.OUTPUT-BYTE-LIMIT !
    4 _sr3a-flow SOPFLOW.IN-FLIGHT-LIMIT !
    1000 _sr3a-flow SOPFLOW.TRANSFORM-STEP-LIMIT !
    500 _sr3a-flow SOPFLOW.TIMEOUT-MS !
    STREAMS-OPFLOW-BACKPRESSURE-REFUSE
        _sr3a-flow SOPFLOW.BACKPRESSURE-POLICY !
    STREAMS-OPFLOW-FAILURE-REVIEW
        _sr3a-flow SOPFLOW.FAILURE-POLICY !
    STREAMS-OPFLOW-RETRY-CONNECTOR-EXACT
        _sr3a-flow SOPFLOW.RETRY-POLICY !
    STREAMS-OPFLOW-LIFECYCLE-ACTIVE
        _sr3a-flow SOPFLOW.LIFECYCLE !
    1 _sr3a-flow SOPFLOW.ENABLED !
    1000 _sr3a-flow SOPFLOW.CONFIGURED-MS !
    _sr3a-flow STREAMS-OPFLOW-SEAL
        STREAMS-OPREC-S-OK _sr3a-status ;

: _sr3a-request!
  ( payload-a payload-u seed source-xt request -- )
    >R
    _sr3a-build-xt !
    _sr3a-build-seed !
    _sr3a-build-u !
    _sr3a-build-a !
    R@ STREAMS-SPOOL-REQUEST-INIT
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-build-xt @ R@ SPOOLREQ.SOURCE-XT !
    _sr3a-build-a @ R@ SPOOLREQ.SOURCE-CONTEXT !
    _sr3a-build-u @ R@ SPOOLREQ.PAYLOAD-U !
    1 R@ SPOOLREQ.CONNECTOR-REVISION !
    1 R@ SPOOLREQ.FLOW-REVISION !
    101 R@ SPOOLREQ.PROTOCOL !
    202 R@ SPOOLREQ.PROFILE !
    303 R@ SPOOLREQ.MEDIA !
    _sr3a-build-seed @ 10 * R@ SPOOLREQ.RECEIVED-MS !
    _sr3a-build-seed @ 10 * 1+ R@ SPOOLREQ.ACCEPTED-MS !
    STREAMS-OPATT-IDEMPOTENCY-EXACT
        R@ SPOOLREQ.IDEMPOTENCY-POLICY !
    _sr3a-build-seed @ R@ SPOOLREQ.EVENT-ID _sr3a-rid-fill
    _sr3a-connector-id R@ SPOOLREQ.CONNECTOR-ID RID-COPY
    _sr3a-flow-id R@ SPOOLREQ.FLOW-ID RID-COPY
    _sr3a-build-seed @ 1+
        R@ SPOOLREQ.CORRELATION-ID _sr3a-rid-fill
    _sr3a-build-seed @ 2 +
        R@ SPOOLREQ.IDEMPOTENCY-ID _sr3a-rid-fill
    _sr3a-origin-id R@ SPOOLREQ.ORIGIN-ID RID-COPY
    _sr3a-destination-id R@ SPOOLREQ.DESTINATION-ID RID-COPY
    _sr3a-endpoint-seal R@ SPOOLREQ.ENDPOINT-SEAL RID-COPY
    _sr3a-build-a @ _sr3a-build-u @
        R@ SPOOLREQ.PAYLOAD-DIGEST SHA3-256-HASH
    R@ STREAMS-SPOOL-REQUEST-VALID? _sr3a-assert
    R> DROP _sr3a-stack ;

: _sr3a-main-root  ( -- root )
    _sr3a-root-view _sr3a-work-a STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-root-view ;

: _sr3a-remember-main  ( -- )
    _sr3a-store-a PSTORE-GENERATION@ _sr3a-old-generation !
    _sr3a-main-root DUP SOPROOT.ITEM-COUNT @ _sr3a-old-items !
    SOPROOT.PAYLOAD-BYTES @ _sr3a-old-bytes ! ;

: _sr3a-main-unchanged  ( -- )
    _sr3a-store-a PSTORE-GENERATION@
        _sr3a-old-generation @ = _sr3a-assert
    _sr3a-main-root DUP SOPROOT.ITEM-COUNT @
        _sr3a-old-items @ = _sr3a-assert
    SOPROOT.PAYLOAD-BYTES @
        _sr3a-old-bytes @ = _sr3a-assert
    _sr3a-stack ;

: _sr3a-result-attempt-a  ( result -- status )
    SPOOLRESULT.ATTEMPT-ID _sr3a-attempt
    _sr3a-spool-a _sr3a-work-a STREAMS-SPOOL-ATTEMPT@ ;

: _sr3a-result-attempt-b  ( result -- status )
    SPOOLRESULT.ATTEMPT-ID _sr3a-attempt
    _sr3a-spool-b _sr3a-work-b STREAMS-SPOOL-ATTEMPT@ ;

: _sr3a-result-payload-a  ( result -- status )
    SPOOLRESULT.ATTEMPT-ID ['] _sr3a-sink _sr3a-readback
    _sr3a-spool-a _sr3a-work-a STREAMS-SPOOL-PAYLOAD-STREAM ;

: _sr3a-result-payload-b  ( result -- status )
    SPOOLRESULT.ATTEMPT-ID ['] _sr3a-sink _sr3a-readback
    _sr3a-spool-b _sr3a-work-b STREAMS-SPOOL-PAYLOAD-STREAM ;

: _sr3a-check-attempt  ( result expected-u -- )
    _sr3a-check-u !
    _sr3a-check-result !
    _sr3a-check-result @ _sr3a-result-attempt-a
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-attempt STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3a-assert
    _sr3a-attempt SOPATT.ATTEMPT-ID
        _sr3a-check-result @ SPOOLRESULT.ATTEMPT-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.EVENT-ID
        _sr3a-request-a SPOOLREQ.EVENT-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.CONNECTOR-ID
        _sr3a-connector-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.FLOW-ID
        _sr3a-flow-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.CORRELATION-ID
        _sr3a-request-a SPOOLREQ.CORRELATION-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.IDEMPOTENCY-ID
        _sr3a-request-a SPOOLREQ.IDEMPOTENCY-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.ORIGIN-ID
        _sr3a-origin-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.DESTINATION-ID
        _sr3a-destination-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.REQUEST-SEAL
        _sr3a-check-result @ SPOOLRESULT.REQUEST-SEAL RID= _sr3a-assert
    _sr3a-attempt SOPATT.ENDPOINT-SEAL
        _sr3a-endpoint-seal RID= _sr3a-assert
    _sr3a-attempt SOPATT.PAYLOAD-DIGEST
        _sr3a-request-a SPOOLREQ.PAYLOAD-DIGEST RID= _sr3a-assert
    _sr3a-attempt SOPATT.PAYLOAD-U @
        _sr3a-check-u @ = _sr3a-assert
    _sr3a-attempt SOPATT.CONNECTOR-REVISION @ 1 = _sr3a-assert
    _sr3a-attempt SOPATT.FLOW-REVISION @ 1 = _sr3a-assert
    _sr3a-attempt SOPATT.ACCEPTED-SEQUENCE @
        _sr3a-check-result @ SPOOLRESULT.ACCEPTED-SEQUENCE @ =
        _sr3a-assert
    _sr3a-attempt SOPATT.READY-SEQUENCE @
        _sr3a-check-result @ SPOOLRESULT.ACCEPTED-SEQUENCE @ =
        _sr3a-assert
    _sr3a-attempt SOPATT.DISPATCH-COUNT @ 0= _sr3a-assert
    _sr3a-attempt SOPATT.RETRY-COUNT @ 0= _sr3a-assert
    _sr3a-attempt SOPATT.PROTOCOL @ 101 = _sr3a-assert
    _sr3a-attempt SOPATT.PROFILE @ 202 = _sr3a-assert
    _sr3a-attempt SOPATT.MEDIA @ 303 = _sr3a-assert
    _sr3a-attempt SOPATT.RECEIPT-POLICY @
        STREAMS-OPATT-RECEIPT-BOUNDED = _sr3a-assert
    _sr3a-attempt SOPATT.RECEIPT-BYTE-LIMIT @ 32 = _sr3a-assert
    _sr3a-attempt SOPATT.RECEIPT-ID RID-ZERO? _sr3a-assert
    _sr3a-attempt SOPATT.STATE @
        STREAMS-OPATT-STATE-ACCEPTED = _sr3a-assert
    _sr3a-attempt SOPATT.EFFECT @
        STREAMS-OPATT-EFFECT-NOT-APPLIED = _sr3a-assert
    _sr3a-stack ;

: _sr3a-check-attempt-b  ( result expected-u -- )
    _sr3a-check-u !
    _sr3a-check-result !
    _sr3a-check-result @ _sr3a-result-attempt-b
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-attempt STREAMS-OPATT-SIZE
        STREAMS-OPATT-VALID? _sr3a-assert
    _sr3a-attempt SOPATT.ATTEMPT-ID
        _sr3a-check-result @ SPOOLRESULT.ATTEMPT-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.EVENT-ID
        _sr3a-request-b SPOOLREQ.EVENT-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.CONNECTOR-ID
        _sr3a-connector-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.FLOW-ID
        _sr3a-flow-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.CORRELATION-ID
        _sr3a-request-b SPOOLREQ.CORRELATION-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.IDEMPOTENCY-ID
        _sr3a-request-b SPOOLREQ.IDEMPOTENCY-ID RID= _sr3a-assert
    _sr3a-attempt SOPATT.ORIGIN-ID
        _sr3a-origin-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.DESTINATION-ID
        _sr3a-destination-id RID= _sr3a-assert
    _sr3a-attempt SOPATT.REQUEST-SEAL
        _sr3a-check-result @ SPOOLRESULT.REQUEST-SEAL RID= _sr3a-assert
    _sr3a-attempt SOPATT.ENDPOINT-SEAL
        _sr3a-endpoint-seal RID= _sr3a-assert
    _sr3a-attempt SOPATT.PAYLOAD-DIGEST
        _sr3a-request-b SPOOLREQ.PAYLOAD-DIGEST RID= _sr3a-assert
    _sr3a-attempt SOPATT.PAYLOAD-U @
        _sr3a-check-u @ = _sr3a-assert
    _sr3a-attempt SOPATT.CONNECTOR-REVISION @ 1 = _sr3a-assert
    _sr3a-attempt SOPATT.FLOW-REVISION @ 1 = _sr3a-assert
    _sr3a-attempt SOPATT.ACCEPTED-SEQUENCE @
        _sr3a-check-result @ SPOOLRESULT.ACCEPTED-SEQUENCE @ =
        _sr3a-assert
    _sr3a-attempt SOPATT.READY-SEQUENCE @
        _sr3a-check-result @ SPOOLRESULT.ACCEPTED-SEQUENCE @ =
        _sr3a-assert
    _sr3a-attempt SOPATT.DISPATCH-COUNT @ 0= _sr3a-assert
    _sr3a-attempt SOPATT.RETRY-COUNT @ 0= _sr3a-assert
    _sr3a-attempt SOPATT.PROTOCOL @ 101 = _sr3a-assert
    _sr3a-attempt SOPATT.PROFILE @ 202 = _sr3a-assert
    _sr3a-attempt SOPATT.MEDIA @ 303 = _sr3a-assert
    _sr3a-attempt SOPATT.RECEIPT-POLICY @
        STREAMS-OPATT-RECEIPT-BOUNDED = _sr3a-assert
    _sr3a-attempt SOPATT.RECEIPT-BYTE-LIMIT @ 32 = _sr3a-assert
    _sr3a-attempt SOPATT.RECEIPT-ID RID-ZERO? _sr3a-assert
    _sr3a-attempt SOPATT.STATE @
        STREAMS-OPATT-STATE-ACCEPTED = _sr3a-assert
    _sr3a-attempt SOPATT.EFFECT @
        STREAMS-OPATT-EFFECT-NOT-APPLIED = _sr3a-assert
    _sr3a-stack ;

: _sr3a-check-payload-a  ( result expected-a expected-u -- )
    _sr3a-check-u !
    _sr3a-check-a !
    _sr3a-check-result !
    _sr3a-readback 64 0xCC FILL
    0 _sr3a-sink-bytes !
    _sr3a-check-result @ _sr3a-result-payload-a
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-sink-bytes @ _sr3a-check-u @ = _sr3a-assert
    _sr3a-readback _sr3a-check-a @ _sr3a-check-u @
        _sr3a-bytes= _sr3a-assert
    _sr3a-stack ;

: _sr3a-check-payload-b  ( result expected-a expected-u -- )
    _sr3a-check-u !
    _sr3a-check-a !
    _sr3a-check-result !
    _sr3a-readback 64 0xCC FILL
    0 _sr3a-sink-bytes !
    _sr3a-check-result @ _sr3a-result-payload-b
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-sink-bytes @ _sr3a-check-u @ = _sr3a-assert
    _sr3a-readback _sr3a-check-a @ _sr3a-check-u @
        _sr3a-bytes= _sr3a-assert
    _sr3a-stack ;

: _sr3a-capacity-a  ( -- capacity )
    _sr3a-capacity _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-CAPACITY STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-capacity STREAMS-SPOOL-CAPACITY-VALID? _sr3a-assert
    _sr3a-capacity ;

: _sr3a-capacity-b  ( -- capacity )
    _sr3a-capacity _sr3a-spool-b _sr3a-work-b
        STREAMS-SPOOL-CAPACITY STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-capacity STREAMS-SPOOL-CAPACITY-VALID? _sr3a-assert
    _sr3a-capacity ;

: _sr3a-check-usage
  ( expected-items expected-bytes expected-active spool work -- )
    _sr3a-usage-work !
    _sr3a-usage-spool !
    _sr3a-usage-active !
    _sr3a-usage-bytes !
    _sr3a-usage-items !
    _sr3a-connector-id _sr3a-connector-usage
        _sr3a-usage-spool @ _sr3a-usage-work @
        STREAMS-SPOOL-CONNECTOR-USAGE@
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-VALID? _sr3a-assert
    _sr3a-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-ITEM-COUNT@
        _sr3a-assert _sr3a-usage-items @ = _sr3a-assert
    _sr3a-connector-usage STREAMS-OI-CONNECTOR-USAGE-VALUE-SIZE
        STREAMS-OI-CONNECTOR-USAGE-VALUE-PAYLOAD-BYTES@
        _sr3a-assert _sr3a-usage-bytes @ = _sr3a-assert
    _sr3a-flow-id _sr3a-flow-usage
        _sr3a-usage-spool @ _sr3a-usage-work @
        STREAMS-SPOOL-FLOW-USAGE@
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-FLOW-USAGE-VALUE-VALID? _sr3a-assert
    _sr3a-flow-usage STREAMS-OI-FLOW-USAGE-VALUE-SIZE
        STREAMS-OI-FLOW-USAGE-VALUE-ACTIVE-COUNT@
        _sr3a-assert _sr3a-usage-active @ = _sr3a-assert
    _sr3a-stack ;

\ Publish a deliberately supplied application-root page through the neutral
\ checked store.  This is a qualification seam, not a Streams mutation API.
: _sr3a-publish-root-page  ( -- )
    _sr3a-store-a _sr3a-pwork-a PSTORE-BEGIN
        PERSIST-S-OK _sr3a-status
    _sr3a-root-page PERSIST-PAGE-PAYLOAD-SIZE
        _sr3a-store-a _sr3a-pwork-a PSTORE-APPEND-PAGE
    SWAP _sr3a-page-id !
        PERSIST-S-OK _sr3a-status
    _sr3a-page-id @ _sr3a-store-a _sr3a-pwork-a
        PSTORE-APPLICATION-ROOT! PERSIST-S-OK _sr3a-status
    _sr3a-store-a _sr3a-pwork-a PSTORE-COMMIT
        PERSIST-S-OK _sr3a-status ;

: _sr3a-copy-current-root  ( -- )
    _sr3a-main-root _sr3a-root-page STREAMS-OPROOT-SIZE MOVE ;

\ Publish one deliberately false semantic counter through the normal Streams
\ transaction path.  Tree generations and reclaim state therefore remain
\ current, making the reachable attempt/blob scan—not stale metadata—the
\ required point of rejection.
: _sr3a-publish-corrupt-semantics  ( -- )
    _sr3a-work-a _SSPW-BEGIN STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-work-a _SSPW-PROVISION-ROOM? _sr3a-assert
    _sr3a-work-a _SSPW-MAINTAIN-RECLAIM
        STREAMS-SPOOL-S-OK _sr3a-status
    RECLAIM-FINALIZE-RETIREMENT-MAX
        _sr3a-work-a _SSPW-FUTURE-RETIREMENT!
        STREAMS-SPOOL-S-OK _sr3a-status
    2 _sr3a-work-a _SSPW.CURRENT-ROOT SOPROOT.PAYLOAD-BYTES !
    1 _sr3a-work-a _SSPW.CURRENT-ROOT
        SOPROOT.LOGICAL-GENERATION +!
    1 _sr3a-work-a _SSPW.CURRENT-ROOT SOPROOT.MUTATION-SEQUENCE +!
    _sr3a-work-a _SSPW-PUBLISH STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-work-a _SSPW-RECONCILE-CURRENT
        STREAMS-SPOOL-S-CORRUPT _sr3a-status ;

: _sr3a-test-main-cold-open  ( -- )
    _sr3a-main-store-b-init STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-record-buffer-b STREAMS-SPOOL-RECORD-BUFFER-MIN
        _sr3a-pwork-b PSTORE-WORK-INIT
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-store-b _sr3a-spool-b STREAMS-SPOOL-INIT
        STREAMS-SPOOL-S-OK _sr3a-status

    \ A zero audit span is a valid empty-store binding, but it must refuse a
    \ nonempty authority before exposing any durable state.
    0 0 _sr3a-pwork-b _sr3a-spool-b _sr3a-work-b
        STREAMS-SPOOL-WORK-INIT STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-spool-b _sr3a-work-b STREAMS-SPOOL-OPEN
        STREAMS-SPOOL-S-CAPACITY _sr3a-status
    _sr3a-work-b STREAMS-SPOOL-REOPEN-REQUIRED? _sr3a-assert
    _sr3a-root-view _sr3a-work-b STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-BUSY _sr3a-status

    \ Rebinding current work with adequate caller-owned audit memory performs
    \ the complete physical/tree/semantic audit and exposes the exact-full
    \ authority without a migration or alternate reader.
    _sr3a-cold-audit-b _sr3a-cold-audit-u
        _sr3a-pwork-b _sr3a-spool-b _sr3a-work-b
        STREAMS-SPOOL-WORK-INIT STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-spool-b _sr3a-work-b STREAMS-SPOOL-OPEN
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-capacity-b
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3a-assert
        DUP SPOOLCAP.BYTE-COUNT @ 10 = _sr3a-assert
        DUP SPOOLCAP.READY-COUNT @ 2 = _sr3a-assert
        SPOOLCAP.FLAGS @
            STREAMS-SPOOL-CAPACITY-F-ITEMS-FULL
            STREAMS-SPOOL-CAPACITY-F-BYTES-FULL OR
            = _sr3a-assert
    2 10 0 _sr3a-spool-b _sr3a-work-b _sr3a-check-usage
    _sr3a-result-b 6 _sr3a-check-attempt-b
    _sr3a-result-b _sr3a-payload-6 6 _sr3a-check-payload-b

    \ A pre-audit cold exception aborts its read-only proposal but cannot bless
    \ incomplete setup.  Only a complete explicit OPEN republishes.
    _sr3a-work-b ['] _sr3a-cold-throw-body _SSPW-WORK-CATCH
        STREAMS-SPOOL-S-FAULT _sr3a-status
    _sr3a-work-b STREAMS-SPOOL-REOPEN-REQUIRED? _sr3a-assert
    _sr3a-root-view _sr3a-work-b STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-BUSY _sr3a-status
    _sr3a-store-b _sr3a-pwork-b PSTORE-BEGIN
        PERSIST-S-OK _sr3a-status
    _sr3a-store-b _sr3a-pwork-b PSTORE-ABORT
        PERSIST-S-OK _sr3a-status
    _sr3a-spool-b _sr3a-work-b STREAMS-SPOOL-OPEN
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-work-b STREAMS-SPOOL-REOPEN-REQUIRED? 0= _sr3a-assert
    _sr3a-capacity-b
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3a-assert
        DUP SPOOLCAP.BYTE-COUNT @ 10 = _sr3a-assert
        SPOOLCAP.READY-COUNT @ 2 = _sr3a-assert
    2 10 0 _sr3a-spool-b _sr3a-work-b _sr3a-check-usage
    _sr3a-result-b 6 _sr3a-check-attempt-b
    _sr3a-result-b _sr3a-payload-6 6 _sr3a-check-payload-b ;

: _sr3a-test-main-admission  ( -- )
    ['] _sr3a-main-store-a-init _sr3a-open-fresh-a
    _sr3a-authority-main 2 10 _sr3a-provision-a
    _sr3a-put-config-a
    _sr3a-capacity-a
        DUP SPOOLCAP.ITEM-LIMIT @ 2 = _sr3a-assert
        DUP SPOOLCAP.BYTE-LIMIT @ 10 = _sr3a-assert
        DUP SPOOLCAP.ITEM-COUNT @ 0= _sr3a-assert
        DUP SPOOLCAP.BYTE-COUNT @ 0= _sr3a-assert
        DUP SPOOLCAP.CONNECTOR-COUNT @ 1 = _sr3a-assert
        SPOOLCAP.FLOW-COUNT @ 1 = _sr3a-assert
    0 0 0 _sr3a-spool-a _sr3a-work-a _sr3a-check-usage

    _sr3a-payload-4 _sr3a-expected 4 MOVE
    _sr3a-payload-4 4 0x40 ['] _sr3a-exact-source
        _sr3a-request-a _sr3a-request!
    _sr3a-result-a _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-a _sr3a-result-a _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-result-a STREAMS-SPOOL-RESULT-VALID? _sr3a-assert
    _sr3a-result-a SPOOLRESULT.DISPOSITION @
        STREAMS-SPOOL-ADMISSION-NEW = _sr3a-assert
    _sr3a-result-a SPOOLRESULT.ACCEPTED-SEQUENCE @ 1 = _sr3a-assert
    _sr3a-source-calls @ 0> _sr3a-assert
    _sr3a-main-root
        DUP SOPROOT.ITEM-COUNT @ 1 = _sr3a-assert
        DUP SOPROOT.PAYLOAD-BYTES @ 4 = _sr3a-assert
        SOPROOT.READY-COUNT @ 1 = _sr3a-assert
    1 4 0 _sr3a-spool-a _sr3a-work-a _sr3a-check-usage
    _sr3a-result-a 4 _sr3a-check-attempt

    \ The durable payload is the admitted snapshot, not later source memory.
    _sr3a-payload-4 4 0xEE FILL
    _sr3a-result-a _sr3a-expected 4 _sr3a-check-payload-a

    \ A direct connector+idempotency hit returns the original attempt without
    \ invoking a now-failing source or changing durable counters/generation.
    _sr3a-remember-main
    ['] _sr3a-failing-source _sr3a-request-a SPOOLREQ.SOURCE-XT !
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-a _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-REPLAY _sr3a-status
    _sr3a-source-calls @ 0= _sr3a-assert
    _sr3a-result-b STREAMS-SPOOL-RESULT-VALID? _sr3a-assert
    _sr3a-result-b SPOOLRESULT.DISPOSITION @
        STREAMS-SPOOL-ADMISSION-REPLAY = _sr3a-assert
    _sr3a-result-a SPOOLRESULT.ATTEMPT-ID
        _sr3a-result-b SPOOLRESULT.ATTEMPT-ID RID= _sr3a-assert
    _sr3a-result-a SPOOLRESULT.REQUEST-SEAL
        _sr3a-result-b SPOOLRESULT.REQUEST-SEAL RID= _sr3a-assert
    _sr3a-main-unchanged

    \ The same connector+key with a different canonical request is conflict,
    \ not a second item and not an accidental replay.
    _sr3a-expected 4 0x40 ['] _sr3a-exact-source
        _sr3a-request-b _sr3a-request!
    _sr3a-request-b SPOOLREQ.EVENT-ID
        DUP C@ 1 XOR SWAP C!
    _sr3a-request-b STREAMS-SPOOL-REQUEST-VALID? _sr3a-assert
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-CONFLICT _sr3a-status
    _sr3a-source-calls @ 0= _sr3a-assert
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged

    \ Exact-production failure, overproduction, and callback failure all abort
    \ before publication and expose neither a result nor a capacity charge.
    _sr3a-payload-6 6 0x50 ['] _sr3a-under-source
        _sr3a-request-b _sr3a-request!
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-CORRUPT _sr3a-status
    _sr3a-source-calls @ 0> _sr3a-assert
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged

    _sr3a-payload-6 6 0x50 ['] _sr3a-over-source
        _sr3a-request-b _sr3a-request!
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-CORRUPT _sr3a-status
    _sr3a-source-calls @ 0> _sr3a-assert
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged

    _sr3a-payload-6 6 0x50 ['] _sr3a-failing-source
        _sr3a-request-b _sr3a-request!
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-FAULT _sr3a-status
    _sr3a-source-calls @ 0> _sr3a-assert
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged
    _sr3a-work-a STREAMS-SPOOL-REOPEN-REQUIRED? 0= _sr3a-assert
    _sr3a-work-a _SSPW.RECLAIM RECLAIM-AUDITED-GENERATION@
        _sr3a-store-a PSTORE-GENERATION@ = _sr3a-assert
    _sr3a-store-a PSTORE-CURRENT-ROOT@
        _sr3a-work-a _SSPW.BASE-ROOT PERSIST-ROOT-VALUE-SIZE
        _sr3a-bytes= _sr3a-assert

    \ Unexpected source exceptions take the same exact rollback path.  The
    \ durable authority, caller result, and current-generation audit latch all
    \ survive, so the next valid admission can proceed without a cold reopen.
    _sr3a-payload-6 6 0x50 ['] _sr3a-throwing-source
        _sr3a-request-b _sr3a-request!
    _sr3a-remember-main
    _sr3a-store-a PSTORE-CURRENT-ROOT@
        _sr3a-root-value-before PERSIST-ROOT-VALUE-COPY
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-FAULT _sr3a-status
    _sr3a-source-calls @ 1 = _sr3a-assert
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged
    _sr3a-work-a STREAMS-SPOOL-REOPEN-REQUIRED? 0= _sr3a-assert
    _sr3a-work-a _SSPW.RECLAIM RECLAIM-AUDITED-GENERATION@
        _sr3a-store-a PSTORE-GENERATION@ = _sr3a-assert
    _sr3a-store-a PSTORE-CURRENT-ROOT@
        _sr3a-root-value-before PERSIST-ROOT-VALUE-SIZE
        _sr3a-bytes= _sr3a-assert
    1 4 0 _sr3a-spool-a _sr3a-work-a _sr3a-check-usage

    \ This item reaches both configured ceilings exactly.
    _sr3a-payload-6 6 0x50 ['] _sr3a-exact-source
        _sr3a-request-b _sr3a-request!
    _sr3a-result-b _sr3a-result-sentinel
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-result-b STREAMS-SPOOL-RESULT-VALID? _sr3a-assert
    _sr3a-capacity-a
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3a-assert
        DUP SPOOLCAP.BYTE-COUNT @ 10 = _sr3a-assert
        DUP SPOOLCAP.READY-COUNT @ 2 = _sr3a-assert
        SPOOLCAP.FLAGS @
            STREAMS-SPOOL-CAPACITY-F-ITEMS-FULL
            STREAMS-SPOOL-CAPACITY-F-BYTES-FULL OR
            = _sr3a-assert
    2 10 0 _sr3a-spool-a _sr3a-work-a _sr3a-check-usage

    \ With both dimensions full, item refusal wins deterministically and the
    \ payload callback is not entered.
    _sr3a-payload-1 1 0x60 ['] _sr3a-exact-source
        _sr3a-request-a _sr3a-request!
    _sr3a-remember-main
    _sr3a-result-a _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-a _sr3a-result-a _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-FULL-ITEMS _sr3a-status
    _sr3a-source-calls @ 0= _sr3a-assert
    _sr3a-result-a _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged
    _sr3a-test-main-cold-open ;

: _sr3a-test-byte-capacity  ( -- )
    ['] _sr3a-bytes-store-a-init _sr3a-open-fresh-a
    _sr3a-authority-bytes 3 4 _sr3a-provision-a
    _sr3a-put-config-a
    _sr3a-payload-4 4 0x70 ['] _sr3a-exact-source
        _sr3a-request-a _sr3a-request!
    _sr3a-result-a _sr3a-result-sentinel
    _sr3a-request-a _sr3a-result-a _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-capacity-a
        DUP SPOOLCAP.ITEM-COUNT @ 1 = _sr3a-assert
        DUP SPOOLCAP.BYTE-COUNT @ 4 = _sr3a-assert
        SPOOLCAP.FLAGS @
            STREAMS-SPOOL-CAPACITY-F-BYTES-FULL = _sr3a-assert

    _sr3a-payload-1 1 0x71 ['] _sr3a-exact-source
        _sr3a-request-b _sr3a-request!
    _sr3a-remember-main
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-FULL-BYTES _sr3a-status
    _sr3a-source-calls @ 0= _sr3a-assert
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged ;

: _sr3a-test-item-capacity  ( -- )
    ['] _sr3a-items-store-a-init _sr3a-open-fresh-a
    _sr3a-authority-items 1 10 _sr3a-provision-a
    _sr3a-put-config-a
    _sr3a-payload-1 1 0x72 ['] _sr3a-exact-source
        _sr3a-request-a _sr3a-request!
    _sr3a-result-a _sr3a-result-sentinel
    _sr3a-request-a _sr3a-result-a _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-capacity-a
        DUP SPOOLCAP.ITEM-COUNT @ 1 = _sr3a-assert
        DUP SPOOLCAP.BYTE-COUNT @ 1 = _sr3a-assert
        SPOOLCAP.FLAGS @
            STREAMS-SPOOL-CAPACITY-F-ITEMS-FULL = _sr3a-assert

    _sr3a-payload-1 1 0x73 ['] _sr3a-exact-source
        _sr3a-request-b _sr3a-request!
    _sr3a-remember-main
    _sr3a-result-b _sr3a-result-sentinel
    0 _sr3a-source-calls !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-FULL-ITEMS _sr3a-status
    _sr3a-source-calls @ 0= _sr3a-assert
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-main-unchanged ;

: _sr3a-test-interrupted-publication  ( -- )
    ['] _sr3a-fault-store-a-init _sr3a-open-fresh-a

    \ A definite prepublication failure restores the exact generation-zero
    \ empty authority without clearing its canonical reclaim continuity.
    PERSIST-FAULT-DATA-SYNCED _sr3a-fault-at !
    _sr3a-authority-fault 2 10 2 0
        _sr3a-spool-a _sr3a-work-a STREAMS-SPOOL-PROVISION
        STREAMS-SPOOL-S-FAULT _sr3a-status
    0 _sr3a-fault-at !
    _sr3a-store-a PSTORE-GENERATION@ 0= _sr3a-assert
    _sr3a-store-a PSTORE-CURRENT-ROOT@
        PROOTV.APPLICATION-ROOT @ -1 = _sr3a-assert
    _sr3a-work-a STREAMS-SPOOL-REOPEN-REQUIRED? 0= _sr3a-assert
    _sr3a-root-view _sr3a-work-a STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-ABSENT _sr3a-status

    \ The same work can immediately retry from that exact empty authority.
    _sr3a-authority-fault 2 10 _sr3a-provision-a
    _sr3a-put-config-a
    _sr3a-payload-4 4 0x80 ['] _sr3a-exact-source
        _sr3a-request-a _sr3a-request!
    _sr3a-result-a _sr3a-result-sentinel

    \ A fault reported only after the new root is durably published is
    \ normalized to success and adopts the matching reclaim generation.
    _sr3a-remember-main
    PERSIST-FAULT-ROOT-PUBLISHED _sr3a-fault-at !
    _sr3a-request-a _sr3a-result-a _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3a-status
    0 _sr3a-fault-at !
    _sr3a-store-a PSTORE-GENERATION@
        _sr3a-old-generation @ 1+ = _sr3a-assert
    _sr3a-result-a STREAMS-SPOOL-RESULT-VALID? _sr3a-assert
    _sr3a-work-a STREAMS-SPOOL-REOPEN-REQUIRED? 0= _sr3a-assert
    _sr3a-work-a _SSPW.RECLAIM RECLAIM-AUDITED-GENERATION@
        _sr3a-store-a PSTORE-GENERATION@ = _sr3a-assert
    1 4 0 _sr3a-spool-a _sr3a-work-a _sr3a-check-usage

    \ Fault after an alternate root has been written is a maybe-effect, not
    \ accepted/rejected volatile truth.  No result is exposed until cold open
    \ independently selects and traverses a complete authority.
    _sr3a-payload-6 6 0x81 ['] _sr3a-exact-source
        _sr3a-request-b _sr3a-request!
    _sr3a-result-b _sr3a-result-sentinel
    PERSIST-FAULT-ROOT-WRITTEN _sr3a-fault-at !
    _sr3a-request-b _sr3a-result-b _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-UNCERTAIN _sr3a-status
    0 _sr3a-fault-at !
    _sr3a-result-b _sr3a-result-unchanged? _sr3a-assert
    _sr3a-work-a STREAMS-SPOOL-REOPEN-REQUIRED? _sr3a-assert

    ['] _sr3a-fault-store-b-init _sr3a-bind-b
        STREAMS-SPOOL-S-OK _sr3a-status
    _sr3a-capacity-b
        DUP SPOOLCAP.ITEM-COUNT @ DUP 1 = SWAP 2 = OR _sr3a-assert
        DUP SPOOLCAP.ITEM-COUNT @ 1 = IF
            DUP SPOOLCAP.BYTE-COUNT @ 4 = _sr3a-assert
        ELSE
            DUP SPOOLCAP.BYTE-COUNT @ 10 = _sr3a-assert
        THEN
        DROP

    \ The same request converges the selected old/new root: it is either the
    \ missing new admission or a direct replay of the complete published one.
    _sr3a-result-b _sr3a-result-sentinel
    _sr3a-request-b _sr3a-result-b _sr3a-spool-b _sr3a-work-b
        STREAMS-SPOOL-ADMIT
        STREAMS-SPOOL-S-OK STREAMS-SPOOL-S-REPLAY _sr3a-status-either
    _sr3a-result-b STREAMS-SPOOL-RESULT-VALID? _sr3a-assert
    _sr3a-result-b SPOOLRESULT.DISPOSITION @
        DUP STREAMS-SPOOL-ADMISSION-NEW =
        SWAP STREAMS-SPOOL-ADMISSION-REPLAY = OR _sr3a-assert
    _sr3a-capacity-b
        DUP SPOOLCAP.ITEM-COUNT @ 2 = _sr3a-assert
        DUP SPOOLCAP.BYTE-COUNT @ 10 = _sr3a-assert
        SPOOLCAP.FLAGS @
            STREAMS-SPOOL-CAPACITY-F-ITEMS-FULL
            STREAMS-SPOOL-CAPACITY-F-BYTES-FULL OR
            = _sr3a-assert
    _sr3a-result-b 6 _sr3a-check-attempt-b
    _sr3a-result-b _sr3a-payload-6 6 _sr3a-check-payload-b ;

: _sr3a-test-unknown-root  ( -- )
    ['] _sr3a-unknown-store-a-init _sr3a-open-fresh-a
    _sr3a-authority-unknown 1 10 _sr3a-provision-a
    _sr3a-copy-current-root
    STREAMS-OPREC-SHAPE-CURRENT 1+
        _sr3a-root-page SOPROOT.SHAPE !
    _sr3a-publish-root-page

    ['] _sr3a-unknown-store-b-init _sr3a-bind-b
        STREAMS-SPOOL-S-UNKNOWN _sr3a-status
    _sr3a-work-b STREAMS-SPOOL-REOPEN-REQUIRED? _sr3a-assert
    _sr3a-root-view _sr3a-work-b STREAMS-SPOOL-AUTHORITY-ROOT
        STREAMS-SPOOL-S-BUSY _sr3a-status ;

: _sr3a-test-corrupt-reachable-authority  ( -- )
    ['] _sr3a-corrupt-store-a-init _sr3a-open-fresh-a
    _sr3a-authority-corrupt 2 10 _sr3a-provision-a
    _sr3a-put-config-a
    _sr3a-payload-1 1 0x90 ['] _sr3a-exact-source
        _sr3a-request-a _sr3a-request!
    _sr3a-result-a _sr3a-result-sentinel
    _sr3a-request-a _sr3a-result-a _sr3a-spool-a _sr3a-work-a
        STREAMS-SPOOL-ADMIT STREAMS-SPOOL-S-OK _sr3a-status

    \ Publish a generation-current, correctly sealed root that disagrees with
    \ the exact bytes reachable from its checked attempt/blob graph.  The
    \ direct reconciliation witness proves the mismatch is semantic; fresh
    \ cold open must then fail closed.
    _sr3a-publish-corrupt-semantics

    ['] _sr3a-corrupt-store-b-init _sr3a-bind-b
        STREAMS-SPOOL-S-CORRUPT _sr3a-status
    _sr3a-work-b STREAMS-SPOOL-REOPEN-REQUIRED? _sr3a-assert
    _sr3a-capacity _sr3a-spool-b _sr3a-work-b
        STREAMS-SPOOL-CAPACITY STREAMS-SPOOL-S-BUSY _sr3a-status
    _sr3a-result-a SPOOLRESULT.ATTEMPT-ID _sr3a-attempt
        _sr3a-spool-b _sr3a-work-b STREAMS-SPOOL-ATTEMPT@
        STREAMS-SPOOL-S-BUSY _sr3a-status ;

: _sr3a-test-cold-reconciliation-algorithms  ( -- )
    \ Exercise the bounded cold ledgers directly after the end-to-end cold
    \ gates: exact usage agrees, while either connector or flow disagreement
    \ is damage.
    _sr3a-cold-connector-entry _SSP-COLD-CONNECTOR-ENTRY-SIZE
        0 FILL
    _sr3a-cold-flow-entry _SSP-COLD-FLOW-ENTRY-SIZE 0 FILL
    _sr3a-cold-connector-entry _sr3a-work-b _SSPW.AUDIT-CONNECTORS !
    _sr3a-cold-flow-entry _sr3a-work-b _SSPW.AUDIT-FLOWS !
    1 _sr3a-work-b _SSPW.AUDIT-CONNECTOR-COUNT !
    1 _sr3a-work-b _SSPW.AUDIT-FLOW-COUNT !
    2 _sr3a-cold-connector-entry _SSPCCE.EXPECTED-ITEMS !
    10 _sr3a-cold-connector-entry _SSPCCE.EXPECTED-BYTES !
    2 _sr3a-cold-connector-entry _SSPCCE.ACTUAL-ITEMS !
    10 _sr3a-cold-connector-entry _SSPCCE.ACTUAL-BYTES !
    0 _sr3a-cold-flow-entry _SSPCFE.EXPECTED-ACTIVE !
    0 _sr3a-cold-flow-entry _SSPCFE.ACTUAL-ACTIVE !
    _sr3a-work-b _SSPW-COLD-USAGE-MATCH? _sr3a-assert
    1 _sr3a-cold-connector-entry _SSPCCE.ACTUAL-ITEMS !
    _sr3a-work-b _SSPW-COLD-USAGE-MATCH? 0= _sr3a-assert
    2 _sr3a-cold-connector-entry _SSPCCE.ACTUAL-ITEMS !
    1 _sr3a-cold-flow-entry _SSPCFE.ACTUAL-ACTIVE !
    _sr3a-work-b _SSPW-COLD-USAGE-MATCH? 0= _sr3a-assert

    \ Accepted and ready orderings permit gaps but never duplicates.  These
    \ witnesses also exercise the bounded in-place heap sort used at cold open.
    2 _sr3a-work-b _SSPW.CURRENT-ROOT SOPROOT.ITEM-COUNT !
    _sr3a-cold-accepted _sr3a-work-b _SSPW.AUDIT-ACCEPTED !
    _sr3a-cold-ready _sr3a-work-b _SSPW.AUDIT-READY !
    1 _sr3a-cold-accepted !
    3 _sr3a-cold-accepted CELL+ !
    2 _sr3a-cold-ready !
    4 _sr3a-cold-ready CELL+ !
    _sr3a-work-b _SSPW-COLD-SEQUENCES-UNIQUE? _sr3a-assert
    1 _sr3a-cold-accepted !
    1 _sr3a-cold-accepted CELL+ !
    2 _sr3a-cold-ready !
    4 _sr3a-cold-ready CELL+ !
    _sr3a-work-b _SSPW-COLD-SEQUENCES-UNIQUE? 0= _sr3a-assert
    1 _sr3a-cold-accepted !
    3 _sr3a-cold-accepted CELL+ !
    2 _sr3a-cold-ready !
    2 _sr3a-cold-ready CELL+ !
    _sr3a-work-b _SSPW-COLD-SEQUENCES-UNIQUE? 0= _sr3a-assert
    _sr3a-stack ;

: _SR3A-RUN  ( -- )
    0 _sr3a-fails !
    0 _sr3a-checks !
    DEPTH _sr3a-depth !
    0 _sr3a-fault-at !
    0 _sr3a-source-calls !
    0 _sr3a-sink-bytes !

    STREAMS-SPOOL-RECORD-BUFFER-MIN
        PERSIST-RECORD-HEADER-SIZE STREAMS-OPATT-SIZE + >=
        _sr3a-assert
    STREAMS-SPOOL-WORK-SIZE STREAMS-SPOOL-SIZE > _sr3a-assert

    _sr3a-setup-vfs
    _sr3a-setup-identities
    _sr3a-valid-config
    _sr3a-test-main-admission
    _sr3a-test-byte-capacity
    _sr3a-test-item-capacity
    _sr3a-test-interrupted-publication
    _sr3a-test-unknown-root
    _sr3a-test-corrupt-reachable-authority
    _sr3a-test-cold-reconciliation-algorithms

    _sr3a-old-vfs @ VFS-USE
    _sr3a-vfs @ VFS-DESTROY
    _sr3a-stack
    _sr3a-fails @ 0= IF
        ." STREAMS SR3 ADMISSION PASS " _sr3a-checks @ . CR
    ELSE
        ." STREAMS SR3 ADMISSION FAIL "
        _sr3a-fails @ . ." /" _sr3a-checks @ . CR
    THEN ;
