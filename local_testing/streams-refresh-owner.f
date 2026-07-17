\ Deterministic contracts for the durable configured-source refresh owner.
\
\ The provider is deliberately fake, but the configured-provider seam, XIO
\ service, syndication decoder, observation checkpoint, replacement store,
\ and RAM VFS are production implementations.  In particular, the fake
\ START callback reloads the store and refuses to report its contract checks
\ as green unless the accepted attempt was durable before external work ran.

PROVIDED streams-refresh-tests

\ Load refresh-owner.f before this leaf test module.  Keeping this test free
\ of another nested REQUIRE leaves evaluator headroom for the JSON decoder.

." [srtc] compiling refresh-owner contracts" CR

VARIABLE _srtc-fails
VARIABLE _srtc-checks
VARIABLE _srtc-depth
VARIABLE _srtc-vfs
VARIABLE _srtc-old-vfs
VARIABLE _srtc-context
VARIABLE _srtc-durable-a
VARIABLE _srtc-snapshot-a
VARIABLE _srtc-document-a
VARIABLE _srtc-document-u
VARIABLE _srtc-fd
VARIABLE _srtc-release-count
VARIABLE _srtc-check-flag
VARIABLE _srtc-status

CREATE _srtc-service XIO-SERVICE-SIZE ALLOT
CREATE _srtc-owner STREAMS-REFRESH-OWNER-SIZE ALLOT
CREATE _srtc-source STREAMS-SOURCE-SIZE ALLOT
CREATE _srtc-stale-source STREAMS-SOURCE-SIZE ALLOT
CREATE _srtc-seed-store STREAMS-OBSERVATION-STORE-SIZE ALLOT
CREATE _srtc-seed-namespace RID-SIZE ALLOT

: _srtc-durable  ( -- checkpoint ) _srtc-durable-a @ ;
: _srtc-snapshot ( -- checkpoint ) _srtc-snapshot-a @ ;
: _srtc-live     ( -- checkpoint )
    _srtc-owner STREAMS-REFRESH-OWNER-CHECKPOINT ;
: _srtc-head     ( -- head|0 )
    _srtc-source SSOURCE.ID _srtc-live OCHK-SOURCE-FIND ;
: _srtc-durable-head  ( -- head|0 )
    _srtc-source SSOURCE.ID _srtc-durable OCHK-SOURCE-FIND ;

: _srtc-assert  ( flag -- )
    1 _srtc-checks +! 0= IF
        1 _srtc-fails +! ." SRTC ASSERT " _srtc-checks @ . CR
    THEN ;

: _srtc-stack  ( -- )
    DEPTH DUP _srtc-depth @ <> IF
        ." SRTC STACK " _srtc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _srtc-depth @ = _srtc-assert ;

: _srtc-allocate  ( size variable -- )
    >R ALLOCATE ABORT" STREAMS REFRESH CONTRACTS FAIL allocation" R> ! ;

: _srtc-free  ( variable -- )
    DUP @ ?DUP IF FREE 0 SWAP ! ELSE DROP THEN ;

\ ---------------------------------------------------------------------
\ Heap-owned fake SCONF context
\ ---------------------------------------------------------------------

  0 CONSTANT _SRTF-BODY-A
  8 CONSTANT _SRTF-BODY-U
 16 CONSTANT _SRTF-MEDIA
 24 CONSTANT _SRTF-OUTCOME
 32 CONSTANT _SRTF-DETAIL
 40 CONSTANT _SRTF-HTTP
 48 CONSTANT _SRTF-RESULT
 56 CONSTANT _SRTF-START-STEP
 64 CONSTANT _SRTF-POLL-STEP
 72 CONSTANT _SRTF-OP-ERROR
 80 CONSTANT _SRTF-CLEANUP-ERROR
 88 CONSTANT _SRTF-WIPE-THROWS
 96 CONSTANT _SRTF-CONFIG-STATUS
104 CONSTANT _SRTF-CONFIG-COUNT
112 CONSTANT _SRTF-START-COUNT
120 CONSTANT _SRTF-POLL-COUNT
128 CONSTANT _SRTF-CANCEL-COUNT
136 CONSTANT _SRTF-WIPE-COUNT
144 CONSTANT _SRTF-POISON-ERROR
152 CONSTANT _SRTF-EXPECTED-ID
160 CONSTANT _SRTF-EXPECTED-OWNER-GEN
168 CONSTANT _SRTF-EXPECTED-REQUEST-GEN
176 CONSTANT _SRTF-EXACT-OK
184 CONSTANT _SRTF-DURABLE-OK
192 CONSTANT _SRTF-SIZE

: _srtc-fake  ( -- context ) _srtc-context @ ;

: _srtc-fake-defaults  ( context -- )
    DUP _SRTF-SIZE 0 FILL
    SSOURCE-FORMAT-JSON-FEED OVER _SRTF-MEDIA + !
    SCONF-O-OK OVER _SRTF-OUTCOME + !
    200 OVER _SRTF-HTTP + !
    -1 OVER _SRTF-RESULT + !
    XIO-STEP-PENDING OVER _SRTF-START-STEP + !
    XIO-STEP-SUCCEEDED OVER _SRTF-POLL-STEP + !
    SCONF-S-OK OVER _SRTF-CONFIG-STATUS + !
    -1 OVER _SRTF-EXACT-OK + !
    -1 SWAP _SRTF-DURABLE-OK + ! ;

: _srtc-configure  ( source context -- status )
    DUP _SRTF-CONFIG-COUNT + 1 SWAP +!
    DUP _SRTF-CONFIG-STATUS + @ >R
    SWAP STREAMS-SOURCE-VALID? 0= IF
        DROP SCONF-S-INVALID R> DROP EXIT
    THEN
    DROP R> ;

: _srtc-requested$  ( context -- a u )
    DROP S" https://feed.example/configured.json" ;
: _srtc-effective$  ( context -- a u )
    DROP S" https://cdn.example/configured.json" ;
: _srtc-body$  ( context -- a u )
    DUP _SRTF-BODY-A + @ SWAP _SRTF-BODY-U + @ ;
: _srtc-media         ( context -- media ) _SRTF-MEDIA + @ ;
: _srtc-outcome       ( context -- outcome ) _SRTF-OUTCOME + @ ;
: _srtc-detail        ( context -- detail ) _SRTF-DETAIL + @ ;
: _srtc-http          ( context -- status ) _SRTF-HTTP + @ ;
: _srtc-result-valid? ( context -- flag ) _SRTF-RESULT + @ ;
: _srtc-cleanup-error ( context -- error ) _SRTF-CLEANUP-ERROR + @ ;
: _srtc-releasable?   ( context -- flag ) DROP -1 ;
: _srtc-poison        ( error context -- ) _SRTF-POISON-ERROR + ! ;

: _srtc-release  ( context -- status )
    DUP _srtc-context @ = IF 0 _srtc-context ! THEN
    DUP _SRTF-SIZE 0 FILL FREE
    1 _srtc-release-count +! SCONF-S-OK ;

VARIABLE _srtc-fake-operation

: _srtc-fake-exact?  ( operation context -- flag )
    >R _srtc-fake-operation !
    R@ _SRTF-EXPECTED-ID + @
    R@ _SRTF-EXPECTED-OWNER-GEN + @
    R@ _SRTF-EXPECTED-REQUEST-GEN + @
    _srtc-fake-operation @ XIO-OP-MATCH? R> DROP ;

: _srtc-fake-durable?  ( -- flag )
    _srtc-live DUP OCHK-VALID? 0= IF DROP 0 EXIT THEN
    _srtc-source SSOURCE.ID SWAP OCHK-SOURCE-FIND
    DUP 0= IF DROP 0 EXIT THEN
    OCS.STATE @ OCHK-ATTEMPT-ACCEPTED <> IF 0 EXIT THEN
    _srtc-durable STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _srtc-owner SREF.STORE STREAMS-OBSERVATION-STORE-LOAD
        OSTORE-S-OK <> IF 0 EXIT THEN
    _srtc-durable OCHK-VALID? 0= IF 0 EXIT THEN
    _srtc-source SSOURCE.ID _srtc-durable OCHK-SOURCE-FIND
    DUP 0= IF DROP 0 EXIT THEN
    OCS.STATE @ OCHK-ATTEMPT-ACCEPTED =
    _srtc-durable OCHK.GENERATION @ _srtc-live OCHK.GENERATION @ = AND ;

: _srtc-start  ( operation context -- step )
    DUP _SRTF-START-COUNT + 1 SWAP +!
    2DUP _srtc-fake-exact?
        OVER _SRTF-EXACT-OK + DUP @ ROT AND SWAP !
    _srtc-fake-durable?
        OVER _SRTF-DURABLE-OK + DUP @ ROT AND SWAP !
    DUP _SRTF-OP-ERROR + @ ?DUP IF 2 PICK XIOO.ERROR ! THEN
    NIP _SRTF-START-STEP + @ ;

: _srtc-poll  ( operation context -- step )
    DUP _SRTF-POLL-COUNT + 1 SWAP +!
    2DUP _srtc-fake-exact?
        OVER _SRTF-EXACT-OK + DUP @ ROT AND SWAP !
    DUP _SRTF-OP-ERROR + @ ?DUP IF 2 PICK XIOO.ERROR ! THEN
    NIP _SRTF-POLL-STEP + @ ;

: _srtc-cancel  ( operation context -- )
    NIP _SRTF-CANCEL-COUNT + 1 SWAP +! ;

: _srtc-wipe  ( operation context -- )
    NIP DUP _SRTF-WIPE-COUNT + 1 SWAP +!
    DUP _SRTF-WIPE-THROWS + @ ?DUP IF
        DUP 2 PICK _SRTF-CLEANUP-ERROR + !
        NIP THROW
    THEN
    0 OVER _SRTF-BODY-A + ! 0 SWAP _SRTF-BODY-U + ! ;

VARIABLE _srtc-factory-provider
VARIABLE _srtc-factory-context

: _srtc-factory  ( -- provider status )
    0 _srtc-factory-provider ! 0 _srtc-factory-context !
    _SRTF-SIZE ALLOCATE DUP IF 2DROP 0 SCONF-S-CAPACITY EXIT THEN
    DROP DUP _srtc-factory-context ! _srtc-fake-defaults
    STREAMS-CONFIGURED-PROVIDER-SIZE ALLOCATE DUP IF
        2DROP _srtc-factory-context @ FREE
        0 _srtc-factory-context ! 0 SCONF-S-CAPACITY EXIT
    THEN
    DROP DUP _srtc-factory-provider ! DUP SCONF-INIT
    _srtc-factory-context @ OVER SCONF.CONTEXT !
    ['] _srtc-configure OVER SCONF.CONFIGURE-XT !
    ['] _srtc-requested$ OVER SCONF.REQUESTED-XT !
    ['] _srtc-effective$ OVER SCONF.EFFECTIVE-XT !
    ['] _srtc-body$ OVER SCONF.BODY-XT !
    ['] _srtc-media OVER SCONF.MEDIA-KIND-XT !
    ['] _srtc-outcome OVER SCONF.OUTCOME-XT !
    ['] _srtc-detail OVER SCONF.DETAIL-XT !
    ['] _srtc-http OVER SCONF.HTTP-STATUS-XT !
    ['] _srtc-result-valid? OVER SCONF.RESULT-VALID-XT !
    ['] _srtc-cleanup-error OVER SCONF.CLEANUP-ERROR-XT !
    ['] _srtc-releasable? OVER SCONF.RELEASABLE-XT !
    ['] _srtc-poison OVER SCONF.POISON-XT !
    ['] _srtc-release OVER SCONF.RELEASE-XT !
    ['] _srtc-start OVER SCONF.START-XT !
    ['] _srtc-poll OVER SCONF.POLL-XT !
    ['] _srtc-cancel OVER SCONF.CANCEL-XT !
    ['] _srtc-wipe OVER SCONF.WIPE-XT !
    DUP SCONF-SEAL DUP SCONF-S-OK <> IF
        >R DROP _srtc-factory-context @ FREE
        _srtc-factory-provider @ FREE
        0 _srtc-factory-context ! 0 _srtc-factory-provider !
        0 R> EXIT
    THEN
    DROP
    _srtc-factory-context @ _srtc-context !
    SCONF-S-OK ;

: _srtc-factory-failure  ( -- provider status )
    _srtc-factory DROP SCONF-S-CAPACITY ;

\ ---------------------------------------------------------------------
\ Fixture, source, provider-plan, and durable-state helpers
\ ---------------------------------------------------------------------

: _srtc-load  ( name-a name-u -- document-a document-u )
    NAMEBUF 24 0 FILL NAMEBUF SWAP CMOVE
    FIND-BY-NAME DUP -1 = ABORT" SRTC fixture missing"
    OPEN-BY-SLOT DUP 0= ABORT" SRTC fixture open failed"
    DUP _srtc-fd ! FSIZE DUP _srtc-document-u !
    ALLOCATE ABORT" SRTC fixture allocation failed"
    DUP _srtc-document-a !
    _srtc-document-u @ _srtc-fd @ FREAD
        _srtc-document-u @ <> ABORT" SRTC fixture read failed"
    _srtc-fd @ FCLOSE
    _srtc-document-a @ _srtc-document-u @ ;

: _srtc-document-free  ( -- )
    _srtc-document-a @ ?DUP IF
        DUP _srtc-document-u @ 0 FILL FREE
    THEN
    0 _srtc-document-a ! 0 _srtc-document-u ! ;

: _srtc-source-init  ( -- )
    _srtc-source STREAMS-SOURCE-INIT
    _srtc-source SSOURCE.ID RID-CLEAR
    1701 _srtc-source SSOURCE.ID !
    S" Contract JSON feed" _srtc-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK = _srtc-assert
    S" https://feed.example/configured.json"
        _srtc-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK = _srtc-assert
    SSOURCE-KIND-SYNDICATION _srtc-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _srtc-source SSOURCE.FORMAT !
    1 _srtc-source SSOURCE.REVISION !
    _srtc-source STREAMS-SOURCE-VALID? _srtc-assert
    _srtc-seed-namespace RID-CLEAR 7701 _srtc-seed-namespace ! ;

: _srtc-plan-reset  ( -- )
    _srtc-fake DUP _SRTF-CONFIG-COUNT + 10 CELLS 0 FILL
    SSOURCE-FORMAT-JSON-FEED OVER _SRTF-MEDIA + !
    SCONF-O-OK OVER _SRTF-OUTCOME + !
    0 OVER _SRTF-DETAIL + !
    200 OVER _SRTF-HTTP + !
    -1 OVER _SRTF-RESULT + !
    XIO-STEP-PENDING OVER _SRTF-START-STEP + !
    XIO-STEP-SUCCEEDED OVER _SRTF-POLL-STEP + !
    0 OVER _SRTF-OP-ERROR + !
    0 OVER _SRTF-CLEANUP-ERROR + !
    0 OVER _SRTF-WIPE-THROWS + !
    SCONF-S-OK OVER _SRTF-CONFIG-STATUS + !
    -1 OVER _SRTF-EXACT-OK + !
    -1 SWAP _SRTF-DURABLE-OK + ! ;

: _srtc-plan-body!  ( a u -- )
    _srtc-fake DUP >R _SRTF-BODY-U + ! R> _SRTF-BODY-A + ! ;

: _srtc-expect  ( owner-id owner-generation request-generation -- )
    _srtc-fake >R
    R@ _SRTF-EXPECTED-REQUEST-GEN + !
    R@ _SRTF-EXPECTED-OWNER-GEN + !
    R> _SRTF-EXPECTED-ID + ! ;

: _srtc-start-refresh  ( owner-id owner-generation -- status )
    2DUP _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@ 1+
        _srtc-expect
    _srtc-source -ROT _srtc-owner STREAMS-REFRESH-OWNER-START ;

: _srtc-tick-owner  ( current-source owner-id owner-generation -- changed status )
    _srtc-owner STREAMS-REFRESH-OWNER-TICK ;

: _srtc-durable=live?  ( -- flag )
    _srtc-durable STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _srtc-owner SREF.STORE STREAMS-OBSERVATION-STORE-LOAD
        OSTORE-S-OK <> IF 0 EXIT THEN
    _srtc-durable STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _srtc-live STREAMS-OBSERVATION-CHECKPOINT-SIZE COMPARE 0= ;

: _srtc-good-state-snapshot!  ( -- )
    _srtc-live _srtc-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE ;

: _srtc-good-state-preserved?  ( -- flag )
    _srtc-live OCHK.OBSERVATION-COUNT @
        _srtc-snapshot OCHK.OBSERVATION-COUNT @ =
    _srtc-live OCHK.KEY-COUNT @ _srtc-snapshot OCHK.KEY-COUNT @ = AND
    _srtc-live OCHK.BLOB-USED @ _srtc-snapshot OCHK.BLOB-USED @ = AND
    _srtc-live OCHK-OBSERVATION-OFFSET +
        OCHK-OBSERVATION-MAX OCHK-OBSERVATION-SIZE *
    _srtc-snapshot OCHK-OBSERVATION-OFFSET +
        OCHK-OBSERVATION-MAX OCHK-OBSERVATION-SIZE * COMPARE 0= AND
    _srtc-live OCHK-KEY-OFFSET + OCHK-KEY-MAX OCHK-KEY-SIZE *
    _srtc-snapshot OCHK-KEY-OFFSET + OCHK-KEY-MAX OCHK-KEY-SIZE *
        COMPARE 0= AND
    _srtc-live OCHK.BLOB OCHK-BLOB-CAPACITY
    _srtc-snapshot OCHK.BLOB OCHK-BLOB-CAPACITY COMPARE 0= AND ;

: _srtc-attempt-state?  ( state outcome -- flag )
    >R _srtc-head DUP 0= IF DROP R> 2DROP 0 EXIT THEN
    OCS.STATE @ =
    _srtc-head OCS.OUTCOME @ R> = AND ;

: _srtc-plan-base  ( -- )
    _srtc-plan-reset S" jsonfeed-base.json" _srtc-load _srtc-plan-body! ;

: _srtc-plan-update  ( -- )
    _srtc-plan-reset S" jsonfeed-update.json" _srtc-load _srtc-plan-body! ;

: _srtc-plan-malformed  ( -- )
    _srtc-plan-reset S" malformed.json" _srtc-load _srtc-plan-body! ;

: _srtc-check-fake-start  ( -- )
    _srtc-fake DUP _SRTF-START-COUNT + @ 1 = _srtc-assert
    DUP _SRTF-EXACT-OK + @ _srtc-assert
    _SRTF-DURABLE-OK + @ _srtc-assert ;

\ ---------------------------------------------------------------------
\ Top-level cases.  The profile invokes these separately for decoder depth.
\ ---------------------------------------------------------------------

: _srtc-begin  ( -- )
    0 _srtc-fails ! 0 _srtc-checks ! 0 _srtc-release-count !
    0 _srtc-context ! 0 _srtc-document-a ! 0 _srtc-document-u !
    STREAMS-OBSERVATION-CHECKPOINT-SIZE _srtc-durable-a _srtc-allocate
    STREAMS-OBSERVATION-CHECKPOINT-SIZE _srtc-snapshot-a _srtc-allocate
    VFS-CUR _srtc-old-vfs !
    8388608 A-XMEM ARENA-NEW DUP 0= _srtc-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP _srtc-vfs ! 0<> _srtc-assert
    _srtc-vfs @ VFS-USE
    _srtc-service XIO-SERVICE-INIT XIO-S-OK = _srtc-assert
    _srtc-source-init
    DEPTH _srtc-depth ! _srtc-stack ;

: _srtc-test-absent-init  ( -- )
    ." SRTC CASE absent-init at " _srtc-checks @ . CR
    _srtc-vfs @ _srtc-service ['] _srtc-factory _srtc-owner
        STREAMS-REFRESH-OWNER-INIT SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-VALID? _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-AVAILABLE? _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-IDLE = _srtc-assert
    _srtc-live OCHK-VALID? _srtc-assert
    _srtc-live OCHK.GENERATION @ 0= _srtc-assert
    _srtc-live OCHK.SOURCE-COUNT @ 0= _srtc-assert
    _srtc-owner SREF.STORE STREAMS-OBSERVATION-STORE-PATH$
        _srtc-vfs @ VFS-RESOLVE 0= _srtc-assert
    _srtc-stack ;

: _srtc-test-policy-bounds  ( -- )
    ." SRTC CASE fixed observation policy bounds at " _srtc-checks @ . CR
    _srtc-source STREAMS-REFRESH-SOURCE-SUPPORTED? _srtc-assert
    _srtc-source _srtc-stale-source STREAMS-SOURCE-SIZE CMOVE
    2 _srtc-stale-source SSOURCE.PAGE-MAX !
    _srtc-stale-source STREAMS-SOURCE-VALID? _srtc-assert
    _srtc-stale-source STREAMS-REFRESH-SOURCE-SUPPORTED? 0= _srtc-assert
    _srtc-stale-source 4101 7 _srtc-owner STREAMS-REFRESH-OWNER-START
        SREF-S-INVALID = _srtc-assert

    _srtc-source _srtc-stale-source STREAMS-SOURCE-SIZE CMOVE
    15 _srtc-stale-source SSOURCE.OBSERVATION-MAX !
    _srtc-stale-source STREAMS-SOURCE-VALID? _srtc-assert
    _srtc-stale-source STREAMS-REFRESH-SOURCE-SUPPORTED? 0= _srtc-assert
    _srtc-stale-source 4101 7 _srtc-owner STREAMS-REFRESH-OWNER-START
        SREF-S-INVALID = _srtc-assert

    _srtc-source _srtc-stale-source STREAMS-SOURCE-SIZE CMOVE
    3 _srtc-stale-source SSOURCE.REVISION-MAX !
    _srtc-stale-source STREAMS-SOURCE-VALID? _srtc-assert
    _srtc-stale-source STREAMS-REFRESH-SOURCE-SUPPORTED? 0= _srtc-assert
    _srtc-stale-source 4101 7 _srtc-owner STREAMS-REFRESH-OWNER-START
        SREF-S-INVALID = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-SOURCE 0= _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@ 0= _srtc-assert
    _srtc-fake _SRTF-CONFIG-COUNT + @ 0= _srtc-assert
    _srtc-stack ;

: _srtc-test-first-success  ( -- )
    ." SRTC CASE accepted-before-start and success at "
        _srtc-checks @ . CR
    _srtc-plan-base
    4101 7 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-ACTIVE = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@ 1 = _srtc-assert
    _srtc-fake _SRTF-START-COUNT + @ 0= _srtc-assert
    OCHK-ATTEMPT-ACCEPTED OCHK-O-NONE _srtc-attempt-state? _srtc-assert
    _srtc-durable=live? _srtc-assert
    4101 7 1 _srtc-owner SREF.XIO-OP XIO-OP-MATCH? _srtc-assert
    4101 7 2 _srtc-owner SREF.XIO-OP XIO-OP-MATCH? 0= _srtc-assert
    _srtc-source 9999 7 _srtc-tick-owner
        SREF-S-INVALID = SWAP 0= AND _srtc-assert

    _srtc-service XIO-TICK
    _srtc-check-fake-start
    _srtc-source 4101 7 _srtc-tick-owner
        SREF-S-OK = SWAP 0= AND _srtc-assert
    _srtc-service XIO-TICK
    _srtc-source 4101 7 _srtc-tick-owner
        SREF-S-OK = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-SUCCEEDED = _srtc-assert
    _srtc-live OCHK.OBSERVATION-COUNT @ 2 = _srtc-assert
    _srtc-live OCHK.KEY-COUNT @ 2 = _srtc-assert
    _srtc-head DUP OCS.NEW-COUNT @ 2 = _srtc-assert
    DUP OCS.REVISED-COUNT @ 0= _srtc-assert
    OCS.UNCHANGED-COUNT @ 0= _srtc-assert
    OCHK-ATTEMPT-SUCCEEDED OCHK-O-OK _srtc-attempt-state? _srtc-assert
    0 _srtc-live OCHK-OBSERVATION-NTH
        _srtc-live OCHK-OBSERVATION-CONTENT$
        S" The stable item remains unchanged." STR-STR= _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-owner _SREF-RESET 0= _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-SOURCE
        _srtc-owner SREF.SOURCE = _srtc-assert
    _srtc-good-state-snapshot!
    _srtc-owner SREF.XIO-OP XIOO.STATE @ XIO-STATE-RESET = _srtc-assert
    _srtc-service XIO-ACTIVE? 0= _srtc-assert
    _srtc-service XIOS.RETAINED @ 0= _srtc-assert
    _srtc-stack ;

: _srtc-test-preaccept-failure  ( -- )
    ." SRTC CASE pre-accept failure hides staged source at "
        _srtc-checks @ . CR
    _srtc-plan-base
    SCONF-S-INVALID _srtc-fake _SRTF-CONFIG-STATUS + !
    4101 7 _srtc-start-refresh SREF-S-INVALID = _srtc-assert
    _srtc-document-free
    _srtc-fake _SRTF-CONFIG-COUNT + @ 1 = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-SOURCE 0= _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@ 1 = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-FAILED = _srtc-assert
    OCHK-ATTEMPT-SUCCEEDED OCHK-O-OK _srtc-attempt-state? _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-service XIO-ACTIVE? 0= _srtc-assert
    _srtc-stack ;

: _srtc-test-unchanged  ( -- )
    ." SRTC CASE unchanged at " _srtc-checks @ . CR
    _srtc-plan-base
    XIO-STEP-SUCCEEDED _srtc-fake _SRTF-START-STEP + !
    4101 7 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@ 2 = _srtc-assert
    4101 7 2 _srtc-owner SREF.XIO-OP XIO-OP-MATCH? _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-source 4101 7 _srtc-tick-owner
        SREF-S-OK = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    _srtc-live OCHK.OBSERVATION-COUNT @ 2 = _srtc-assert
    _srtc-live OCHK.KEY-COUNT @ 2 = _srtc-assert
    _srtc-head DUP OCS.NEW-COUNT @ 0= _srtc-assert
    DUP OCS.REVISED-COUNT @ 0= _srtc-assert
    OCS.UNCHANGED-COUNT @ 2 = _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-good-state-snapshot!
    _srtc-stack ;

: _srtc-test-cleanup-suppresses-success  ( -- )
    ." SRTC CASE cleanup suppresses success at " _srtc-checks @ . CR
    _srtc-plan-update
    XIO-STEP-SUCCEEDED _srtc-fake _SRTF-START-STEP + !
    -778 _srtc-fake _SRTF-WIPE-THROWS + !
    4101 7 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-source 4101 7 _srtc-tick-owner
        SREF-S-CLEANUP = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-CLEANUP = _srtc-assert
    OCHK-ATTEMPT-FAILED OCHK-O-CLEANUP _srtc-attempt-state? _srtc-assert
    _srtc-head OCS.CLEANUP-ERROR @ -778 = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ -778 = _srtc-assert
    _srtc-live OCHK.OBSERVATION-COUNT @ 2 = _srtc-assert
    _srtc-live OCHK.KEY-COUNT @ 2 = _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-fake _SRTF-POISON-ERROR + @ -778 = _srtc-assert
    _srtc-durable=live? _srtc-assert

    \ A cleanup failure quarantines this provider/owner lifecycle.  A manual
    \ retry must be rejected before source staging, configuration, BEGIN, or
    \ any durable generation change can overwrite the truthful CLEANUP head.
    _srtc-live _srtc-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _srtc-owner SREF.SOURCE _srtc-stale-source STREAMS-SOURCE-SIZE CMOVE
    _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@ _srtc-status !
    _srtc-owner STREAMS-REFRESH-OWNER-AVAILABLE? 0= _srtc-assert
    _srtc-source 4101 7 _srtc-owner STREAMS-REFRESH-OWNER-START
        SREF-S-UNAVAILABLE = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-CLEANUP = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-STATUS@
        SREF-S-CLEANUP = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ -778 = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@
        _srtc-status @ = _srtc-assert
    _srtc-live STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _srtc-snapshot STREAMS-OBSERVATION-CHECKPOINT-SIZE
        COMPARE 0= _srtc-assert
    _srtc-owner SREF.SOURCE STREAMS-SOURCE-SIZE
        _srtc-stale-source STREAMS-SOURCE-SIZE COMPARE 0= _srtc-assert
    _srtc-fake _SRTF-CONFIG-COUNT + @ 1 = _srtc-assert
    _srtc-fake _SRTF-CLEANUP-ERROR + @ -778 = _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-RELEASE SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-VALID? 0= _srtc-assert
    _srtc-context @ 0= _srtc-assert
    _srtc-release-count @ 1 = _srtc-assert
    _srtc-stack ;

: _srtc-test-restart-and-revision  ( -- )
    ." SRTC CASE restart and revised item at " _srtc-checks @ . CR
    _srtc-vfs @ _srtc-service ['] _srtc-factory _srtc-owner
        STREAMS-REFRESH-OWNER-INIT SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-IDLE = _srtc-assert
    _srtc-live OCHK.OBSERVATION-COUNT @ 2 = _srtc-assert
    _srtc-plan-update
    XIO-STEP-SUCCEEDED _srtc-fake _SRTF-START-STEP + !
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@ 1 = _srtc-assert
    4102 8 1 _srtc-owner SREF.XIO-OP XIO-OP-MATCH? _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-source 4102 8 _srtc-tick-owner
        SREF-S-OK = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    _srtc-live OCHK.OBSERVATION-COUNT @ 4 = _srtc-assert
    _srtc-live OCHK.KEY-COUNT @ 3 = _srtc-assert
    _srtc-head DUP OCS.NEW-COUNT @ 1 = _srtc-assert
    DUP OCS.REVISED-COUNT @ 1 = _srtc-assert
    OCS.UNCHANGED-COUNT @ 1 = _srtc-assert
    2 _srtc-live OCHK-OBSERVATION-NTH DUP OCO.REVISION @ 2 = _srtc-assert
    _srtc-live OCHK-OBSERVATION-TITLE$
        S" Change record, version two" STR-STR= _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-good-state-snapshot!
    _srtc-stack ;

: _srtc-test-transport-failure  ( -- )
    ." SRTC CASE transport failure at " _srtc-checks @ . CR
    _srtc-plan-base
    SCONF-O-TRANSPORT _srtc-fake _SRTF-OUTCOME + !
    711 _srtc-fake _SRTF-DETAIL + !
    0 _srtc-fake _SRTF-RESULT + !
    -771 _srtc-fake _SRTF-OP-ERROR + !
    XIO-STEP-FAILED _srtc-fake _SRTF-START-STEP + !
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-source 4102 8 _srtc-tick-owner
        SREF-S-EXTERNAL = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    OCHK-ATTEMPT-FAILED OCHK-O-TRANSPORT _srtc-attempt-state? _srtc-assert
    _srtc-head DUP OCS.DETAIL @ 711 = _srtc-assert
    OCS.XIO-ERROR @ -771 = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ -771 = _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-stack ;

: _srtc-test-semantic-failure  ( -- )
    ." SRTC CASE semantic failure at " _srtc-checks @ . CR
    _srtc-plan-base
    XIO-STEP-SUCCEEDED _srtc-fake _SRTF-START-STEP + !
    SCONF-O-HTTP _srtc-fake _SRTF-OUTCOME + !
    719 _srtc-fake _SRTF-DETAIL + !
    503 _srtc-fake _SRTF-HTTP + !
    0 _srtc-fake _SRTF-RESULT + !
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-source 4102 8 _srtc-tick-owner
        SREF-S-EXTERNAL = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    OCHK-ATTEMPT-FAILED OCHK-O-HTTP _srtc-attempt-state? _srtc-assert
    _srtc-head DUP OCS.DETAIL @ 719 = _srtc-assert
    OCS.HTTP-STATUS @ 503 = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ 719 = _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-stack ;

: _srtc-test-decode-failure  ( -- )
    ." SRTC CASE decode failure at " _srtc-checks @ . CR
    _srtc-plan-malformed
    XIO-STEP-SUCCEEDED _srtc-fake _SRTF-START-STEP + !
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-source 4102 8 _srtc-tick-owner
        SREF-S-DECODE = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    OCHK-ATTEMPT-FAILED OCHK-O-DECODE _srtc-attempt-state? _srtc-assert
    _srtc-head OCS.DECODE-STATUS @ DUP SYNDEC-S-OK <> _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ = _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-stack ;

: _srtc-test-source-stale  ( -- )
    ." SRTC CASE source revision stale at " _srtc-checks @ . CR
    _srtc-plan-base
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-source _srtc-stale-source STREAMS-SOURCE-SIZE CMOVE
    2 _srtc-stale-source SSOURCE.REVISION !
    _srtc-stale-source STREAMS-SOURCE-VALID? _srtc-assert
    _srtc-stale-source 4102 8 _srtc-tick-owner
        SREF-S-STALE = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-STALE = _srtc-assert
    OCHK-ATTEMPT-FAILED OCHK-O-STALE _srtc-attempt-state? _srtc-assert
    _srtc-head OCS.XIO-ERROR @ 0= _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ 0= _srtc-assert
    _srtc-fake DUP _SRTF-CANCEL-COUNT + @ 1 = _srtc-assert
    _SRTF-WIPE-COUNT + @ 1 = _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-stack ;

: _srtc-test-xio-generation-stale  ( -- )
    ." SRTC CASE exact XIO generation at " _srtc-checks @ . CR
    _srtc-plan-base
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    4102 8 _srtc-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@
        _srtc-owner SREF.XIO-OP XIO-OP-MATCH? _srtc-assert
    1 _srtc-owner SREF.XIO-OP XIOO.REQUEST-GENERATION +!
    _srtc-source 4102 8 _srtc-tick-owner
        SREF-S-STALE = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    OCHK-ATTEMPT-FAILED OCHK-O-STALE _srtc-attempt-state? _srtc-assert
    _srtc-head OCS.XIO-ERROR @ 0= _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ 0= _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-stack ;

: _srtc-test-explicit-cancel  ( -- )
    ." SRTC CASE explicit cancel at " _srtc-checks @ . CR
    _srtc-plan-base
    SCONF-O-CANCELLED _srtc-fake _SRTF-OUTCOME + !
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    4102 8 _srtc-owner STREAMS-REFRESH-OWNER-CANCEL
        SREF-S-CANCELLED = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-CANCELLED = _srtc-assert
    OCHK-ATTEMPT-CANCELLED OCHK-O-CANCELLED
        _srtc-attempt-state? _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-stack ;

: _srtc-test-cancel-after-success  ( -- )
    ." SRTC CASE cancel retained success at " _srtc-checks @ . CR
    _srtc-plan-base
    XIO-STEP-SUCCEEDED _srtc-fake _SRTF-START-STEP + !
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-owner SREF.XIO-OP XIOO.STATE @
        XIO-STATE-SUCCEEDED = _srtc-assert
    _srtc-service XIOS.RETAINED @
        _srtc-owner SREF.XIO-OP = _srtc-assert
    4102 8 _srtc-owner STREAMS-REFRESH-OWNER-CANCEL
        SREF-S-CANCELLED = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    OCHK-ATTEMPT-CANCELLED OCHK-O-CANCELLED
        _srtc-attempt-state? _srtc-assert
    _srtc-head OCS.XIO-ERROR @ 0= _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-CANCELLED = _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-service XIOS.RETAINED @ 0= _srtc-assert
    _srtc-owner SREF.XIO-OP XIOO.STATE @ XIO-STATE-RESET = _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-stack ;

: _srtc-test-release  ( -- )
    ." SRTC CASE release retained success at " _srtc-checks @ . CR
    _srtc-plan-base
    XIO-STEP-SUCCEEDED _srtc-fake _SRTF-START-STEP + !
    4102 8 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-service XIO-TICK _srtc-check-fake-start
    _srtc-owner SREF.XIO-OP XIOO.STATE @
        XIO-STATE-SUCCEEDED = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-SOURCE 0<> _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-RELEASE SREF-S-OK = _srtc-assert
    _srtc-document-free
    _srtc-owner STREAMS-REFRESH-OWNER-VALID? 0= _srtc-assert
    _srtc-context @ 0= _srtc-assert
    _srtc-release-count @ 2 = _srtc-assert
    _srtc-service XIO-ACTIVE? 0= _srtc-assert
    _srtc-service XIOS.RETAINED @ 0= _srtc-assert
    _srtc-vfs @ _srtc-seed-store STREAMS-OBSERVATION-STORE-INIT
        OSTORE-S-OK = _srtc-assert
    _srtc-durable STREAMS-OBSERVATION-CHECKPOINT-SIZE _srtc-seed-store
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK = _srtc-assert
    _srtc-durable-head DUP 0<> _srtc-assert
    DUP OCS.STATE @ OCHK-ATTEMPT-CANCELLED = _srtc-assert
    DUP OCS.OUTCOME @ OCHK-O-CANCELLED = _srtc-assert
    OCS.XIO-ERROR @ 0= _srtc-assert
    _srtc-stack ;

: _srtc-test-boot-recovery  ( -- )
    ." SRTC CASE boot recovery at " _srtc-checks @ . CR
    _srtc-vfs @ _srtc-seed-store STREAMS-OBSERVATION-STORE-INIT
        OSTORE-S-OK = _srtc-assert
    _srtc-durable STREAMS-OBSERVATION-CHECKPOINT-SIZE _srtc-seed-store
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK = _srtc-assert
    _srtc-durable OCHK.GENERATION @ _srtc-status !
    _srtc-source SSOURCE.ID _srtc-source SSOURCE.REVISION @
        _srtc-seed-namespace SREF-PROVIDER-SYNDICATION
        S" https://feed.example/configured.json" _srtc-durable OCHK-BEGIN
        OCHK-S-OK = _srtc-assert
    _srtc-durable _srtc-status @ _srtc-seed-store
        STREAMS-OBSERVATION-STORE-SAVE OSTORE-S-OK = _srtc-assert

    _srtc-vfs @ _srtc-service ['] _srtc-factory _srtc-owner
        STREAMS-REFRESH-OWNER-INIT SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-RECOVERED = _srtc-assert
    OCHK-ATTEMPT-INDETERMINATE OCHK-O-INDETERMINATE
        _srtc-attempt-state? _srtc-assert
    _srtc-live OCHK.GENERATION @ _srtc-status @ 2 + = _srtc-assert
    _srtc-durable=live? _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-RELEASE SREF-S-OK = _srtc-assert
    _srtc-release-count @ 3 = _srtc-assert
    _srtc-stack ;

: _srtc-check-offline-owned-release  ( expected-error -- )
    >R
    _srtc-owner STREAMS-REFRESH-OWNER-VALID? _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-AVAILABLE? 0= _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-OFFLINE = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-STATUS@
        SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@ R> = _srtc-assert
    _srtc-owner SREF.PROVIDER @ 0= _srtc-assert
    _srtc-owner SREF.LIVE @ DUP 0<> _srtc-assert
        OCHK-VALID? _srtc-assert
    _srtc-owner SREF.CANDIDATE @ DUP 0<> _srtc-assert
        OCHK-VALID? _srtc-assert
    _srtc-owner SREF.DECODER @ DUP 0<> _srtc-assert
        STREAMS-SYNDICATION-DECODER-VALID? _srtc-assert
    _srtc-owner SREF.STORE STREAMS-OBSERVATION-STORE-VALID? _srtc-assert

    _srtc-owner STREAMS-REFRESH-OWNER-RELEASE SREF-S-OK = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-VALID? 0= _srtc-assert
    _srtc-owner SREF.MAGIC @ 0= _srtc-assert
    _srtc-owner SREF.PROVIDER @ 0= _srtc-assert
    _srtc-owner SREF.DECODER @ 0= _srtc-assert
    _srtc-owner SREF.CANDIDATE @ 0= _srtc-assert
    _srtc-owner SREF.LIVE @ 0= _srtc-assert
    _srtc-stack ;

: _srtc-test-factory-absent-release  ( -- )
    ." SRTC CASE factory absent owner release at " _srtc-checks @ . CR
    _srtc-release-count @ _srtc-status !
    _srtc-vfs @ _srtc-service 0 _srtc-owner
        STREAMS-REFRESH-OWNER-INIT SREF-S-OK = _srtc-assert
    _srtc-context @ 0= _srtc-assert
    SREF-S-UNAVAILABLE _srtc-check-offline-owned-release
    _srtc-release-count @ _srtc-status @ = _srtc-assert
    _srtc-stack ;

: _srtc-test-service-absent-release  ( -- )
    ." SRTC CASE service absent owner release at " _srtc-checks @ . CR
    _srtc-release-count @ _srtc-status !
    _srtc-vfs @ 0 ['] _srtc-factory _srtc-owner
        STREAMS-REFRESH-OWNER-INIT SREF-S-OK = _srtc-assert
    _srtc-context @ 0= _srtc-assert
    SREF-S-UNAVAILABLE _srtc-check-offline-owned-release
    _srtc-release-count @ _srtc-status @ = _srtc-assert
    _srtc-stack ;

: _srtc-test-factory-failure-release  ( -- )
    ." SRTC CASE factory failure owner release at " _srtc-checks @ . CR
    _srtc-release-count @ _srtc-status !
    _srtc-vfs @ _srtc-service ['] _srtc-factory-failure _srtc-owner
        STREAMS-REFRESH-OWNER-INIT SREF-S-OK = _srtc-assert
    _srtc-context @ 0= _srtc-assert
    _srtc-release-count @ _srtc-status @ 1+ = _srtc-assert
    SCONF-S-CAPACITY _srtc-check-offline-owned-release
    _srtc-release-count @ _srtc-status @ 1+ = _srtc-assert
    _srtc-stack ;

: _srtc-test-persist-block-metadata  ( -- )
    ." SRTC CASE persist failure blocks with exact metadata at "
        _srtc-checks @ . CR
    _srtc-vfs @ _srtc-service ['] _srtc-factory _srtc-owner
        STREAMS-REFRESH-OWNER-INIT SREF-S-OK = _srtc-assert
    _srtc-good-state-snapshot!
    _srtc-plan-base
    5101 9 _srtc-start-refresh SREF-S-OK = _srtc-assert
    _srtc-service XIO-TICK
    _srtc-check-fake-start

    \ Fault injection happens only after BEGIN is durable and external work
    \ has started.  The final publication save must preserve the raw store
    \ status while publishing the owner's normalized blocked/storage tuple.
    VFSNAP-S-IO _srtc-owner SREF.STORE DUP >R
        STREAMS-OBSERVATION-STORE.CORE _VFSNAP-BLOCK!
        R> _OSTORE-SYNC DROP
    _srtc-service XIO-TICK
    _srtc-source 5101 9 _srtc-tick-owner
        SREF-S-STORAGE = SWAP 0<> AND _srtc-assert
    _srtc-document-free
    _srtc-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-BLOCKED = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-STATUS@
        SREF-S-STORAGE = _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-ERROR@
        OSTORE-S-IO = _srtc-assert
    _srtc-owner SREF.STORE-STATUS @ OSTORE-S-IO = _srtc-assert
    OCHK-ATTEMPT-ACCEPTED OCHK-O-NONE
        _srtc-attempt-state? _srtc-assert
    _srtc-good-state-preserved? _srtc-assert
    _srtc-owner STREAMS-REFRESH-OWNER-RELEASE SREF-S-OK = _srtc-assert
    _srtc-stack ;

: _srtc-finish  ( -- )
    _srtc-service XIO-SERVICE-FINI XIO-S-OK = _srtc-assert
    _srtc-old-vfs @ VFS-USE
    _srtc-vfs @ VFS-DESTROY
    0 _srtc-vfs !
    _srtc-snapshot-a _srtc-free _srtc-durable-a _srtc-free
    _srtc-stack
    _srtc-fails @ 0= IF
        ." STREAMS REFRESH OWNER CONTRACTS PASS " _srtc-checks @ .
    ELSE
        ." STREAMS REFRESH OWNER CONTRACTS FAIL " _srtc-fails @ .
        ." / " _srtc-checks @ .
    THEN CR ;
