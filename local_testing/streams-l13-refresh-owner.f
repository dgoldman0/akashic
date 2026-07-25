\ Focused repository-backed configured-refresh owner contracts.
\
\ The already-qualified L13 apply fixture supplies only its RAM-VFS,
\ repository, source-authority, and bounded work-area setup helpers.  This
\ leaf owns a fake configured provider and exercises the production
\ repository-refresh owner end to end.  In particular, the fake START
\ callback refuses to call the ordering proof green unless durable ACCEPTED
\ authority is visible before any external work begins.

PROVIDED streams-l13-rfo-tests

VARIABLE _SL13R-checks
VARIABLE _SL13R-fails
VARIABLE _SL13R-depth
VARIABLE _SL13R-context
VARIABLE _SL13R-factory-calls
VARIABLE _SL13R-release-calls
VARIABLE _SL13R-document-a
VARIABLE _SL13R-document-u
VARIABLE _SL13R-fd

CREATE _SL13R-service XIO-SERVICE-SIZE ALLOT
STREAMS-REPOSITORY-REFRESH-OWNER-SIZE XBUF _SL13R-owner
STREAMS-SOURCE-SIZE XBUF _SL13R-stale-source
STREAMS-PI-KEY-MAX XBUF _SL13R-key
SPREC-ATTEMPT-SIZE XBUF _SL13R-history-record
SPREC-ATTEMPT-SIZE XBUF _SL13R-active-record

: _SL13R-assert  ( flag -- )
    1 _SL13R-checks +!
    0= IF
        1 _SL13R-fails +!
        ." STREAMS L13 REFRESH ASSERT " _SL13R-checks @ . CR
    THEN ;

: _SL13R-stack  ( -- )
    DEPTH DUP _SL13R-depth @ <> IF
        ." STREAMS L13 REFRESH STACK "
        _SL13R-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13R-depth @ = _SL13R-assert ;

: _SL13R-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 REFRESH STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13R-assert _SL13R-stack ;

\ ---------------------------------------------------------------------
\ Heap-owned configured-provider fake
\ ---------------------------------------------------------------------

  0 CONSTANT _SL13RF-BODY-A
  8 CONSTANT _SL13RF-BODY-U
 16 CONSTANT _SL13RF-MEDIA
 24 CONSTANT _SL13RF-OUTCOME
 32 CONSTANT _SL13RF-DETAIL
 40 CONSTANT _SL13RF-HTTP
 48 CONSTANT _SL13RF-RESULT
 56 CONSTANT _SL13RF-START-STEP
 64 CONSTANT _SL13RF-POLL-STEP
 72 CONSTANT _SL13RF-OP-ERROR
 80 CONSTANT _SL13RF-CLEANUP-ERROR
 88 CONSTANT _SL13RF-WIPE-THROWS
 96 CONSTANT _SL13RF-CONFIG-STATUS
104 CONSTANT _SL13RF-CONFIG-COUNT
112 CONSTANT _SL13RF-START-COUNT
120 CONSTANT _SL13RF-POLL-COUNT
128 CONSTANT _SL13RF-CANCEL-COUNT
136 CONSTANT _SL13RF-WIPE-COUNT
144 CONSTANT _SL13RF-POISON-ERROR
152 CONSTANT _SL13RF-DURABLE-OK
160 CONSTANT _SL13RF-SIZE

: _SL13R-fake  ( -- context ) _SL13R-context @ ;

: _SL13R-fake-defaults  ( context -- )
    DUP _SL13RF-SIZE 0 FILL
    SSOURCE-FORMAT-JSON-FEED OVER _SL13RF-MEDIA + !
    SCONF-O-OK OVER _SL13RF-OUTCOME + !
    200 OVER _SL13RF-HTTP + !
    -1 OVER _SL13RF-RESULT + !
    XIO-STEP-PENDING OVER _SL13RF-START-STEP + !
    XIO-STEP-SUCCEEDED OVER _SL13RF-POLL-STEP + !
    SCONF-S-OK OVER _SL13RF-CONFIG-STATUS + !
    -1 SWAP _SL13RF-DURABLE-OK + ! ;

: _SL13R-configure  ( source context -- status )
    DUP _SL13RF-CONFIG-COUNT + 1 SWAP +!
    DUP _SL13RF-CONFIG-STATUS + @ >R
    SWAP STREAMS-SOURCE-VALID? 0= IF
        DROP SCONF-S-INVALID R> DROP EXIT
    THEN
    DROP R> ;

: _SL13R-requested$  ( context -- a u )
    DROP S" https://example.test/repository-refresh.json" ;

: _SL13R-effective$  ( context -- a u )
    DROP S" https://cdn.example.test/repository-refresh.json" ;

: _SL13R-body$  ( context -- a u )
    DUP _SL13RF-BODY-A + @ SWAP _SL13RF-BODY-U + @ ;

: _SL13R-media  ( context -- media )
    _SL13RF-MEDIA + @ ;

: _SL13R-outcome  ( context -- outcome )
    _SL13RF-OUTCOME + @ ;

: _SL13R-detail  ( context -- detail )
    _SL13RF-DETAIL + @ ;

: _SL13R-http  ( context -- status )
    _SL13RF-HTTP + @ ;

: _SL13R-result-valid?  ( context -- flag )
    _SL13RF-RESULT + @ ;

: _SL13R-cleanup-error  ( context -- error )
    _SL13RF-CLEANUP-ERROR + @ ;

: _SL13R-releasable?  ( context -- flag )
    DROP -1 ;

: _SL13R-poison  ( error context -- )
    _SL13RF-POISON-ERROR + ! ;

: _SL13R-release  ( context -- status )
    DUP _SL13R-context @ = IF 0 _SL13R-context ! THEN
    DUP _SL13RF-SIZE 0 FILL FREE
    1 _SL13R-release-calls +!
    SCONF-S-OK ;

VARIABLE _SL13R-persisted-exact

: _SL13R-history-key!  ( attempt -- status )
    DUP OCS.SOURCE-ID
    OVER OCS.ATTEMPT-SEQUENCE @
    ROT OCS.ATTEMPT-ID
    _SL13R-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY ;

: _SL13R-inspect-accepted-owner
  ( context repository repo-work -- status )
    2DROP DROP
    -1 _SL13R-persisted-exact !
    _SL13R-owner SRRO.ATTEMPT _SL13R-history-key!
    STREAMS-PI-S-OK <> IF
        0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    _SL13R-key STREAMS-PI-ATTEMPT-BY-SOURCE-KEY-SIZE
    _SL13R-history-record SPREC-ATTEMPT-SIZE
    _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK <> IF
        2DROP 0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    DROP
    SPREC-ATTEMPT-SIZE <> IF
        0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    _SL13R-history-record SPREC-ATTEMPT-SIZE
        SPREC-ATTEMPT-VALID? 0= IF
        0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    _SL13R-history-record SPRA.ATTEMPT OCHK-SOURCE-SIZE
    _SL13R-owner SRRO.ATTEMPT OCHK-SOURCE-SIZE
        COMPARE IF
        0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN

    _SL13R-owner SRRO.ATTEMPT OCS.SOURCE-ID
    _SL13R-key STREAMS-PI-ACTIVE-ATTEMPT-KEY
    STREAMS-PI-S-OK <> IF
        0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    _SL13R-key STREAMS-PI-ACTIVE-ATTEMPT-KEY-SIZE
    _SL13R-active-record SPREC-ATTEMPT-SIZE
    _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK <> IF
        2DROP 0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    DROP
    SPREC-ATTEMPT-SIZE <> IF
        0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    _SL13R-active-record SPREC-ATTEMPT-SIZE
        SPREC-ATTEMPT-VALID? 0= IF
        0 _SL13R-persisted-exact !
        STREAMS-REPOSITORY-S-OK EXIT
    THEN
    _SL13R-active-record SPRA.ATTEMPT OCHK-SOURCE-SIZE
    _SL13R-owner SRRO.ATTEMPT OCHK-SOURCE-SIZE
        COMPARE 0=
        _SL13R-persisted-exact !
    STREAMS-REPOSITORY-S-OK ;

: _SL13R-durable-accepted?  ( -- flag )
    _SL13P-root SAR.ACTIVE-COUNT @ 1 =
    _SL13R-owner SRRO.ACCEPTED @ 0<> AND
    _SL13R-owner SRRO.ATTEMPT OCS.STATE @
        OCHK-ATTEMPT-ACCEPTED = AND
    _SL13R-owner SRRO.ATTEMPT OCS.SOURCE-ID
        _SL13P-source SSOURCE.ID RID= AND
    DUP 0= IF EXIT THEN
    DROP
    0 _SL13R-persisted-exact !
    0 ['] _SL13R-inspect-accepted-owner
    _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK =
    _SL13R-persisted-exact @ AND ;

: _SL13R-start  ( operation context -- step )
    DUP _SL13RF-START-COUNT + 1 SWAP +!
    _SL13R-durable-accepted?
        OVER _SL13RF-DURABLE-OK + DUP @ ROT AND SWAP !
    DUP _SL13RF-OP-ERROR + @ ?DUP IF
        2 PICK XIOO.ERROR !
    THEN
    NIP _SL13RF-START-STEP + @ ;

: _SL13R-poll  ( operation context -- step )
    DUP _SL13RF-POLL-COUNT + 1 SWAP +!
    DUP _SL13RF-OP-ERROR + @ ?DUP IF
        2 PICK XIOO.ERROR !
    THEN
    NIP _SL13RF-POLL-STEP + @ ;

: _SL13R-cancel  ( operation context -- )
    NIP _SL13RF-CANCEL-COUNT + 1 SWAP +! ;

: _SL13R-wipe  ( operation context -- )
    NIP
    DUP _SL13RF-WIPE-COUNT + 1 SWAP +!
    DUP _SL13RF-WIPE-THROWS + @ ?DUP IF
        DUP 2 PICK _SL13RF-CLEANUP-ERROR + !
        NIP THROW
    THEN
    0 OVER _SL13RF-BODY-A + !
    0 SWAP _SL13RF-BODY-U + ! ;

VARIABLE _SL13R-factory-provider
VARIABLE _SL13R-factory-context

: _SL13R-factory  ( -- provider status )
    1 _SL13R-factory-calls +!
    0 _SL13R-factory-provider !
    0 _SL13R-factory-context !
    _SL13RF-SIZE ALLOCATE DUP IF
        2DROP 0 SCONF-S-CAPACITY EXIT
    THEN
    DROP DUP _SL13R-factory-context ! _SL13R-fake-defaults
    STREAMS-CONFIGURED-PROVIDER-SIZE ALLOCATE DUP IF
        2DROP
        _SL13R-factory-context @ FREE
        0 _SL13R-factory-context !
        0 SCONF-S-CAPACITY EXIT
    THEN
    DROP
    DUP _SL13R-factory-provider !
    DUP SCONF-INIT
    _SL13R-factory-context @ OVER SCONF.CONTEXT !
    ['] _SL13R-configure OVER SCONF.CONFIGURE-XT !
    ['] _SL13R-requested$ OVER SCONF.REQUESTED-XT !
    ['] _SL13R-effective$ OVER SCONF.EFFECTIVE-XT !
    ['] _SL13R-body$ OVER SCONF.BODY-XT !
    ['] _SL13R-media OVER SCONF.MEDIA-KIND-XT !
    ['] _SL13R-outcome OVER SCONF.OUTCOME-XT !
    ['] _SL13R-detail OVER SCONF.DETAIL-XT !
    ['] _SL13R-http OVER SCONF.HTTP-STATUS-XT !
    ['] _SL13R-result-valid? OVER SCONF.RESULT-VALID-XT !
    ['] _SL13R-cleanup-error OVER SCONF.CLEANUP-ERROR-XT !
    ['] _SL13R-releasable? OVER SCONF.RELEASABLE-XT !
    ['] _SL13R-poison OVER SCONF.POISON-XT !
    ['] _SL13R-release OVER SCONF.RELEASE-XT !
    ['] _SL13R-start OVER SCONF.START-XT !
    ['] _SL13R-poll OVER SCONF.POLL-XT !
    ['] _SL13R-cancel OVER SCONF.CANCEL-XT !
    ['] _SL13R-wipe OVER SCONF.WIPE-XT !
    DUP SCONF-SEAL DUP SCONF-S-OK <> IF
        >R DROP
        _SL13R-factory-context @ FREE
        _SL13R-factory-provider @ FREE
        0 _SL13R-factory-context !
        0 _SL13R-factory-provider !
        0 R> EXIT
    THEN
    DROP
    _SL13R-factory-context @ _SL13R-context !
    SCONF-S-OK ;

: _SL13R-factory-capacity  ( -- provider status )
    1 _SL13R-factory-calls +!
    0 SCONF-S-CAPACITY ;

\ ---------------------------------------------------------------------
\ Fixture and owner helpers
\ ---------------------------------------------------------------------

: _SL13R-load  ( name-a name-u -- document-a document-u )
    NAMEBUF 24 0 FILL
    NAMEBUF SWAP CMOVE
    FIND-BY-NAME DUP -1 = ABORT" SL13R fixture missing"
    OPEN-BY-SLOT DUP 0= ABORT" SL13R fixture open failed"
    DUP _SL13R-fd ! FSIZE DUP _SL13R-document-u !
    ALLOCATE ABORT" SL13R fixture allocation failed"
    DUP _SL13R-document-a !
    _SL13R-document-u @ _SL13R-fd @ FREAD
        _SL13R-document-u @ <> ABORT" SL13R fixture read failed"
    _SL13R-fd @ FCLOSE
    _SL13R-document-a @ _SL13R-document-u @ ;

: _SL13R-document-free  ( -- )
    _SL13R-document-a @ ?DUP IF
        DUP _SL13R-document-u @ 0 FILL FREE
    THEN
    0 _SL13R-document-a !
    0 _SL13R-document-u ! ;

: _SL13R-plan-base  ( -- )
    _SL13R-document-free
    _SL13R-fake _SL13R-fake-defaults
    S" srro-base.json" _SL13R-load
    _SL13R-fake _SL13RF-BODY-U + !
    _SL13R-fake _SL13RF-BODY-A + ! ;

: _SL13R-owner-init  ( -- )
    _SL13R-service ['] _SL13R-factory
    _SL13P-repository _SL13P-repo-work _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-INIT
        SRRO-S-OK _SL13R-status
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-VALID?
        _SL13R-assert
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-AVAILABLE?
        _SL13R-assert ;

: _SL13R-start-owner  ( component generation -- status )
    >R >R
    _SL13P-source R> R> _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-START ;

: _SL13R-tick-owner  ( source component generation -- changed? status )
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-TICK ;

: _SL13R-attempt-state?  ( state outcome -- flag )
    >R >R
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-ATTEMPT
    DUP 0<> IF
        DUP OCS.STATE @ R> =
        SWAP OCS.OUTCOME @ R> = AND
    ELSE
        DROP R> DROP R> DROP 0
    THEN ;

: _SL13R-release-owner  ( -- )
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-RELEASE
        SRRO-S-OK _SL13R-status
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-VALID? 0=
        _SL13R-assert
    _SL13R-context @ 0= _SL13R-assert ;

\ ---------------------------------------------------------------------
\ Contracts
\ ---------------------------------------------------------------------

: _SL13R-contract-recovery-gate  ( -- )
    ." SL13R CASE boot recovery gate at " _SL13R-checks @ . CR
    _SL13P-source-b-rid 1 _SL13P-namespace-b _SL13P-begin
    _SL13P-root SAR.ACTIVE-COUNT @ 1 = _SL13R-assert
    _SL13R-factory-calls @ 0= _SL13R-assert
    _SL13R-service ['] _SL13R-factory
    _SL13P-repository _SL13P-repo-work _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-INIT
        SRRO-S-BLOCKED _SL13R-status
    _SL13R-factory-calls @ 0= _SL13R-assert
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-VALID? 0=
        _SL13R-assert

    _SL13P-output 1
    _SL13P-repository _SL13P-repo-work _SL13P-acquisition-work
        STREAMS-ACQUISITION-RECOVER-ALL
    STREAMS-ACQUISITION-S-OK =
    SWAP 1 = AND _SL13R-assert
    _SL13P-output OCS.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13R-assert
    _SL13P-output OCS.OUTCOME @
        OCHK-O-INDETERMINATE = _SL13R-assert
    _SL13P-root SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    _SL13R-stack ;

: _SL13R-contract-admission-statuses  ( -- )
    ." SL13R CASE factory/configure/admission status domains at "
        _SL13R-checks @ . CR
    _SL13R-service ['] _SL13R-factory-capacity
    _SL13P-repository _SL13P-repo-work _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-INIT
        SRRO-S-CAPACITY _SL13R-status
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-VALID? 0=
        _SL13R-assert

    _SL13R-owner-init
    _SL13R-plan-base
    SCONF-S-BUSY _SL13R-fake _SL13RF-CONFIG-STATUS + !
    8098 1 _SL13R-start-owner SRRO-S-BUSY _SL13R-status
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-PHASE@
        SRRO-PHASE-FAILED = _SL13R-assert
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-ERROR@
        SCONF-S-BUSY = _SL13R-assert
    _SL13P-root SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    _SL13R-release-owner
    _SL13R-document-free

    _SL13R-owner-init
    _SL13R-plan-base
    SCONF-S-TRANSPORT _SL13R-fake _SL13RF-CONFIG-STATUS + !
    8099 1 _SL13R-start-owner SRRO-S-EXTERNAL _SL13R-status
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-ERROR@
        SCONF-S-TRANSPORT = _SL13R-assert
    _SL13P-root SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    _SL13R-release-owner
    _SL13R-document-free

    _SL13R-owner-init
    _SL13P-repo-work 8100 1 _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-START
        SRRO-S-INVALID _SL13R-status
    _SL13R-fake _SL13RF-CONFIG-COUNT + @ 0= _SL13R-assert
    _SL13P-root SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    _SL13R-release-owner
    _SL13R-stack ;

: _SL13R-contract-success  ( -- )
    ." SL13R CASE durable begin and atomic success at "
        _SL13R-checks @ . CR
    _SL13R-owner-init
    _SL13R-plan-base
    XIO-STEP-SUCCEEDED _SL13R-fake _SL13RF-START-STEP + !
    8101 1 _SL13R-start-owner SRRO-S-OK _SL13R-status
    _SL13P-root SAR.ACTIVE-COUNT @ 1 = _SL13R-assert
    _SL13R-fake _SL13RF-START-COUNT + @ 0= _SL13R-assert
    _SL13R-service XIO-TICK
    _SL13R-fake _SL13RF-DURABLE-OK + @ _SL13R-assert
    _SL13P-source 8101 1 _SL13R-tick-owner
    SRRO-S-OK = SWAP 0<> AND _SL13R-assert
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-PHASE@
        SRRO-PHASE-SUCCEEDED = _SL13R-assert
    OCHK-ATTEMPT-SUCCEEDED OCHK-O-OK
        _SL13R-attempt-state? _SL13R-assert
    _SL13P-root
    DUP SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    DUP SAR.OBSERVATION-COUNT @ 2 = _SL13R-assert
    SAR.NATIVE-COUNT @ 2 = _SL13R-assert
    _SL13R-service XIO-ACTIVE? 0= _SL13R-assert
    _SL13R-service XIOS.RETAINED @ 0= _SL13R-assert
    _SL13R-document-free
    _SL13R-release-owner
    _SL13R-stack ;

: _SL13R-contract-stale  ( -- )
    ." SL13R CASE source revision stale at " _SL13R-checks @ . CR
    _SL13R-owner-init
    _SL13R-plan-base
    8102 2 _SL13R-start-owner SRRO-S-OK _SL13R-status
    _SL13P-source _SL13R-stale-source
        STREAMS-SOURCE-SIZE MOVE
    2 _SL13R-stale-source SSOURCE.REVISION !
    _SL13R-stale-source STREAMS-SOURCE-VALID? _SL13R-assert
    _SL13R-stale-source 8102 2 _SL13R-tick-owner
    SRRO-S-STALE = SWAP 0<> AND _SL13R-assert
    OCHK-ATTEMPT-FAILED OCHK-O-STALE
        _SL13R-attempt-state? _SL13R-assert
    _SL13P-root
    DUP SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    SAR.OBSERVATION-COUNT @ 2 = _SL13R-assert
    _SL13R-fake DUP _SL13RF-CANCEL-COUNT + @ 1 =
        _SL13R-assert
    _SL13RF-WIPE-COUNT + @ 1 = _SL13R-assert
    _SL13R-document-free
    _SL13R-release-owner
    _SL13R-stack ;

: _SL13R-contract-cancel  ( -- )
    ." SL13R CASE explicit cancellation at " _SL13R-checks @ . CR
    _SL13R-owner-init
    _SL13R-plan-base
    81025 2 _SL13R-start-owner SRRO-S-OK _SL13R-status
    _SL13R-service XIO-TICK
    _SL13R-fake _SL13RF-DURABLE-OK + @ _SL13R-assert
    81025 2 _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-CANCEL
    SRRO-S-CANCELLED = SWAP 0<> AND _SL13R-assert
    OCHK-ATTEMPT-CANCELLED OCHK-O-CANCELLED
        _SL13R-attempt-state? _SL13R-assert
    _SL13P-root
    DUP SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    SAR.OBSERVATION-COUNT @ 2 = _SL13R-assert
    _SL13R-document-free
    _SL13R-release-owner
    _SL13R-stack ;

: _SL13R-contract-provider-failure  ( -- )
    ." SL13R CASE provider failure terminal at "
        _SL13R-checks @ . CR
    _SL13R-owner-init
    _SL13R-plan-base
    SCONF-O-HTTP _SL13R-fake _SL13RF-OUTCOME + !
    719 _SL13R-fake _SL13RF-DETAIL + !
    503 _SL13R-fake _SL13RF-HTTP + !
    0 _SL13R-fake _SL13RF-RESULT + !
    -771 _SL13R-fake _SL13RF-OP-ERROR + !
    XIO-STEP-FAILED _SL13R-fake _SL13RF-START-STEP + !
    8103 3 _SL13R-start-owner SRRO-S-OK _SL13R-status
    _SL13R-service XIO-TICK
    _SL13P-source 8103 3 _SL13R-tick-owner
    SRRO-S-EXTERNAL = SWAP 0<> AND _SL13R-assert
    OCHK-ATTEMPT-FAILED OCHK-O-HTTP
        _SL13R-attempt-state? _SL13R-assert
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-ERROR@
        -771 = _SL13R-assert
    _SL13P-root
    DUP SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    SAR.OBSERVATION-COUNT @ 2 = _SL13R-assert
    _SL13R-document-free
    _SL13R-release-owner
    _SL13R-stack ;

: _SL13R-contract-cleanup-suppresses-success  ( -- )
    ." SL13R CASE cleanup suppresses atomic success at "
        _SL13R-checks @ . CR
    _SL13R-owner-init
    _SL13R-plan-base
    XIO-STEP-SUCCEEDED _SL13R-fake _SL13RF-START-STEP + !
    -778 _SL13R-fake _SL13RF-WIPE-THROWS + !
    8104 4 _SL13R-start-owner SRRO-S-OK _SL13R-status
    _SL13R-service XIO-TICK
    _SL13P-source 8104 4 _SL13R-tick-owner
    SRRO-S-CLEANUP = SWAP 0<> AND _SL13R-assert
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-PHASE@
        SRRO-PHASE-CLEANUP = _SL13R-assert
    OCHK-ATTEMPT-FAILED OCHK-O-CLEANUP
        _SL13R-attempt-state? _SL13R-assert
    _SL13R-owner STREAMS-REPOSITORY-REFRESH-OWNER-ERROR@
        -778 = _SL13R-assert
    _SL13R-fake _SL13RF-POISON-ERROR + @
        -778 = _SL13R-assert
    _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-REQUEST-GENERATION@
        1 = _SL13R-assert
    8104 4 _SL13R-start-owner SRRO-S-CLEANUP _SL13R-status
    _SL13R-owner
        STREAMS-REPOSITORY-REFRESH-OWNER-REQUEST-GENERATION@
        1 = _SL13R-assert
    _SL13P-root
    DUP SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    SAR.OBSERVATION-COUNT @ 2 = _SL13R-assert
    _SL13R-document-free
    _SL13R-release-owner
    _SL13R-stack ;

: _SL13R-contract-active-release  ( -- )
    ." SL13R CASE active release terminalizes at "
        _SL13R-checks @ . CR
    _SL13R-owner-init
    _SL13R-plan-base
    8105 5 _SL13R-start-owner SRRO-S-OK _SL13R-status
    _SL13P-root SAR.ACTIVE-COUNT @ 1 = _SL13R-assert
    _SL13R-release-owner
    _SL13P-root
    DUP SAR.ACTIVE-COUNT @ 0= _SL13R-assert
    SAR.OBSERVATION-COUNT @ 2 = _SL13R-assert
    _SL13P-repository STREAMS-REPOSITORY-VALID? _SL13R-assert
    _SL13P-repository STREAMS-REPOSITORY-LOADED? _SL13R-assert
    _SL13P-repository STREAMS-REPOSITORY-PROVISIONED?
        _SL13R-assert
    _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WORK-BOUND? _SL13R-assert
    _SL13R-service XIO-SERVICE-BOUND? _SL13R-assert
    _SL13R-service XIO-SERVICE-OWNER? _SL13R-assert
    _SL13R-service XIO-ACTIVE? 0= _SL13R-assert
    _SL13R-service XIOS.RETAINED @ 0= _SL13R-assert
    _SL13R-factory-calls @ 10 = _SL13R-assert
    _SL13R-release-calls @ 9 = _SL13R-assert
    _SL13R-document-free
    _SL13R-stack ;

: _SL13R-finish  ( -- )
    _SL13R-service XIO-SERVICE-FINI XIO-S-OK _SL13R-status
    _SL13P-finish
    _SL13R-stack ;

: _SL13R-RUN  ( -- )
    0 _SL13R-checks !
    0 _SL13R-fails !
    0 _SL13R-context !
    0 _SL13R-factory-calls !
    0 _SL13R-release-calls !
    0 _SL13R-document-a !
    0 _SL13R-document-u !
    0 _SL13P-checks !
    0 _SL13P-fails !
    DEPTH _SL13P-depth !
    DEPTH _SL13R-depth !
    _SL13P-runtime-init
    _SL13P-repository-init
    _SL13P-provision
    _SL13P-work-init
    _SL13P-create-sources
    \ CREATE accepts a revision-zero candidate and deliberately leaves that
    \ caller-owned candidate unchanged.  Hydrate the exact current source
    \ revision that the refresh owner is required to borrow.
    _SL13P-source-b-rid _SL13P-source
        _SL13P-repository _SL13P-repo-work _SL13P-source-work
        STREAMS-SOURCE-AUTHORITY-READ
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13P-status
    _SL13P-source STREAMS-SOURCE-VALID? _SL13R-assert
    _SL13R-service XIO-SERVICE-INIT XIO-S-OK _SL13R-status
    _SL13R-contract-recovery-gate
    _SL13R-contract-admission-statuses
    _SL13R-contract-success
    _SL13R-contract-stale
    _SL13R-contract-cancel
    _SL13R-contract-provider-failure
    _SL13R-contract-cleanup-suppresses-success
    _SL13R-contract-active-release
    _SL13R-finish
    _SL13R-fails @ _SL13P-fails @ OR IF
        ." STREAMS L13 REFRESH FAIL "
        _SL13R-fails @ _SL13P-fails @ + .
        ." / "
        _SL13R-checks @ _SL13P-checks @ + . CR
    ELSE
        ." STREAMS L13 REFRESH PASS "
        _SL13R-checks @ _SL13P-checks @ + . CR
    THEN ;
