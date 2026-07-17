\ Deterministic applet-level contracts for Streams manual source refresh.
\
\ The fake provider crosses the production SCONF seam and the operation is
\ pumped through Desk's external-I/O service as exposed by Desk's component
\ endpoint.  Its START callback reloads the observation store, proving that
\ an ACCEPTED attempt was durable before any external callback ran.  The
\ concrete configured provider is never constructed, and neither provider
\ submits XIO during lifecycle setup, so the suite performs no network work
\ even though the online composition and Desk dependency closures are linked.

PROVIDED streams-manual-refresh-tests

." [smrc] compiling Streams manual-refresh integration contracts" CR

VARIABLE _smrc-fails
VARIABLE _smrc-checks
VARIABLE _smrc-depth
VARIABLE _smrc-old-vfs
VARIABLE _smrc-vfs
VARIABLE _smrc-desk
VARIABLE _smrc-inst
VARIABLE _smrc-offline
VARIABLE _smrc-relaunch
VARIABLE _smrc-recovery
VARIABLE _smrc-fixed-generation
VARIABLE _smrc-component-revision
VARIABLE _smrc-request
VARIABLE _smrc-registry
VARIABLE _smrc-bus
VARIABLE _smrc-document-a
VARIABLE _smrc-document-u
VARIABLE _smrc-document-fd
VARIABLE _smrc-durable-a
VARIABLE _smrc-source
VARIABLE _smrc-page
VARIABLE _smrc-status
VARIABLE _smrc-before
VARIABLE _smrc-old-generation
VARIABLE _smrc-offline-heap-before
VARIABLE _smrc-owner-phase-before
VARIABLE _smrc-owner-magic-before
VARIABLE _smrc-configured-init-before
VARIABLE _smrc-truth-heap-before
VARIABLE _smrc-selection-before
VARIABLE _smrc-view-before

CREATE _smrc-candidate STREAMS-SOURCE-SIZE ALLOT
CREATE _smrc-rid RID-SIZE ALLOT
CREATE _smrc-page-rid RID-SIZE ALLOT
CREATE _smrc-rref RREF-SIZE ALLOT
CREATE _smrc-result-rref RREF-SIZE ALLOT
CREATE _smrc-seed-namespace RID-SIZE ALLOT
CREATE _smrc-offline-desc APP-DESC ALLOT
CREATE _smrc-owner-before STREAMS-REFRESH-OWNER-SIZE ALLOT
CREATE _smrc-checkpoint-before STREAMS-OBSERVATION-CHECKPOINT-SIZE ALLOT

: _smrc-assert  ( flag -- )
    1 _smrc-checks +! 0= IF
        1 _smrc-fails +! ." SMRC ASSERT " _smrc-checks @ . CR
    THEN ;

: _smrc-stack  ( -- )
    DEPTH DUP _smrc-depth @ <> IF
        ." SMRC STACK " _smrc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _smrc-depth @ = _smrc-assert ;

: _smrc-zeroed?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP DROP -1 ;

: _smrc-ok  ( status -- ) 0= _smrc-assert ;

: _smrc-service  ( -- service )
    _smrc-desk @ _DESK-USE-STATE _DESK-EXTERNAL-IO ;

: _smrc-endpoint  ( -- endpoint )
    _smrc-desk @ _DESK-USE-STATE _DESK-ENDPOINT ;

: _smrc-desk-pump  ( -- )
    _smrc-desk @ DESK-TICK-CB ;

: _smrc-current-owner  ( -- owner )
    _STM-CONFIGURED-REFRESH ;

: _smrc-current-checkpoint  ( -- checkpoint )
    _smrc-current-owner STREAMS-REFRESH-OWNER-CHECKPOINT ;

: _smrc-feed-source  ( -- source|0 )
    _smrc-rid _STM-SOURCE-REGISTRY STREAMS-SOURCE-FIND ;

: _smrc-page-source  ( -- source|0 )
    _smrc-page-rid _STM-SOURCE-REGISTRY STREAMS-SOURCE-FIND ;

: _smrc-head  ( -- head|0 )
    _smrc-rid _smrc-current-checkpoint OCHK-SOURCE-FIND ;

: _smrc-generation-stable  ( -- )
    _smrc-inst @ CINST.GENERATION @ _smrc-fixed-generation @ =
        _smrc-assert ;

: _smrc-revision-capture  ( -- )
    _smrc-inst @ CINST.REVISION @ _smrc-component-revision ! ;

: _smrc-revision-stable  ( -- )
    _smrc-inst @ CINST.REVISION @ _smrc-component-revision @ =
        _smrc-assert ;

: _smrc-revision-advanced  ( -- )
    _smrc-inst @ CINST.REVISION @ _smrc-component-revision @ 1+ =
        _smrc-assert
    _smrc-revision-capture ;

\ ---------------------------------------------------------------------
\ Heap-owned fake configured provider
\ ---------------------------------------------------------------------

  0 CONSTANT _SMRF-BODY-A
  8 CONSTANT _SMRF-BODY-U
 16 CONSTANT _SMRF-FACTORY-COUNT
 24 CONSTANT _SMRF-CONFIGURE-COUNT
 32 CONSTANT _SMRF-START-COUNT
 40 CONSTANT _SMRF-POLL-COUNT
 48 CONSTANT _SMRF-CANCEL-COUNT
 56 CONSTANT _SMRF-WIPE-COUNT
 64 CONSTANT _SMRF-RELEASE-COUNT
 72 CONSTANT _SMRF-EXACT-OK
 80 CONSTANT _SMRF-DURABLE-OK
 88 CONSTANT _SMRF-SIZE

CREATE _smrc-plan _SMRF-SIZE ALLOT
CREATE _smrc-plan-before _SMRF-SIZE ALLOT
VARIABLE _smrc-provider-context
VARIABLE _smrc-provider
VARIABLE _smrc-provider-source
VARIABLE _smrc-provider-operation

: _smrc-plan-defaults  ( -- )
    _smrc-plan _SMRF-SIZE 0 FILL
    _smrc-document-a @ _smrc-plan _SMRF-BODY-A + !
    _smrc-document-u @ _smrc-plan _SMRF-BODY-U + !
    -1 _smrc-plan _SMRF-EXACT-OK + !
    -1 _smrc-plan _SMRF-DURABLE-OK + ! ;

: _smrc-configure  ( source context -- status )
    DROP _smrc-provider-source !
    1 _smrc-plan _SMRF-CONFIGURE-COUNT + +!
    _smrc-provider-source @ STREAMS-SOURCE-VALID? 0= IF
        SCONF-S-INVALID EXIT
    THEN
    _smrc-provider-source @ SSOURCE.ID _smrc-rid RID=
    _smrc-provider-source @ SSOURCE.REVISION @ 1 = AND
    _smrc-plan _SMRF-EXACT-OK + DUP @ ROT AND SWAP !
    SCONF-S-OK ;

: _smrc-requested$  ( context -- a u )
    DROP S" https://feed.example/manual.json" ;

: _smrc-effective$  ( context -- a u )
    DROP S" https://feed.example/manual.json" ;

: _smrc-body$  ( context -- a u )
    DROP _smrc-plan _SMRF-BODY-A + @
    _smrc-plan _SMRF-BODY-U + @ ;

: _smrc-media  ( context -- kind )
    DROP SSOURCE-FORMAT-JSON-FEED ;

: _smrc-outcome  ( context -- outcome ) DROP SCONF-O-OK ;
: _smrc-detail   ( context -- detail ) DROP 0 ;
: _smrc-http     ( context -- status ) DROP 200 ;
: _smrc-result?  ( context -- flag ) DROP -1 ;
: _smrc-cleanup  ( context -- error ) DROP 0 ;
: _smrc-releasable?  ( context -- flag ) DROP -1 ;
: _smrc-poison  ( error context -- ) 2DROP ;

: _smrc-attempt-durable?  ( -- flag )
    _smrc-inst @ DUP 0= IF DROP 0 EXIT THEN _STM-ACTIVATE
    _smrc-current-owner STREAMS-REFRESH-OWNER-VALID? 0= IF 0 EXIT THEN
    _smrc-head DUP 0= IF DROP 0 EXIT THEN
    OCS.STATE @ OCHK-ATTEMPT-ACCEPTED <> IF 0 EXIT THEN
    _smrc-durable-a @ STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _smrc-current-owner SREF.STORE
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK <> IF 0 EXIT THEN
    _smrc-durable-a @ OCHK-VALID? 0= IF 0 EXIT THEN
    _smrc-rid _smrc-durable-a @ OCHK-SOURCE-FIND
        DUP 0= IF DROP 0 EXIT THEN
    OCS.STATE @ OCHK-ATTEMPT-ACCEPTED =
    _smrc-durable-a @ OCHK.GENERATION @
        _smrc-current-checkpoint OCHK.GENERATION @ = AND ;

: _smrc-operation-exact?  ( operation -- flag )
    _smrc-provider-operation !
    _smrc-inst @ DUP 0= IF DROP 0 EXIT THEN
    DUP CINST.ID @ SWAP CINST.GENERATION @
    _smrc-current-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@
    _smrc-provider-operation @ XIO-OP-MATCH? ;

: _smrc-start  ( operation context -- step )
    DROP _smrc-provider-operation !
    1 _smrc-plan _SMRF-START-COUNT + +!
    _smrc-provider-operation @ _smrc-operation-exact?
    _smrc-plan _SMRF-EXACT-OK + DUP @ ROT AND SWAP !
    _smrc-attempt-durable?
    _smrc-plan _SMRF-DURABLE-OK + DUP @ ROT AND SWAP !
    XIO-STEP-PENDING ;

: _smrc-poll  ( operation context -- step )
    DROP _smrc-provider-operation !
    1 _smrc-plan _SMRF-POLL-COUNT + +!
    _smrc-provider-operation @ _smrc-operation-exact?
    _smrc-plan _SMRF-EXACT-OK + DUP @ ROT AND SWAP !
    XIO-STEP-SUCCEEDED ;

: _smrc-cancel  ( operation context -- )
    2DROP 1 _smrc-plan _SMRF-CANCEL-COUNT + +! ;

: _smrc-wipe  ( operation context -- )
    2DROP 1 _smrc-plan _SMRF-WIPE-COUNT + +! ;

: _smrc-release  ( context -- status )
    FREE 1 _smrc-plan _SMRF-RELEASE-COUNT + +! SCONF-S-OK ;

: _smrc-factory  ( -- provider status )
    0 _smrc-provider-context ! 0 _smrc-provider !
    1 _smrc-plan _SMRF-FACTORY-COUNT + +!
    8 ALLOCATE DUP IF 2DROP 0 SCONF-S-CAPACITY EXIT THEN
    DROP DUP _smrc-provider-context ! _smrc-plan SWAP !
    STREAMS-CONFIGURED-PROVIDER-SIZE ALLOCATE DUP IF
        2DROP _smrc-provider-context @ FREE
        0 _smrc-provider-context ! 0 SCONF-S-CAPACITY EXIT
    THEN
    DROP DUP _smrc-provider ! DUP SCONF-INIT
    _smrc-provider-context @ OVER SCONF.CONTEXT !
    ['] _smrc-configure OVER SCONF.CONFIGURE-XT !
    ['] _smrc-requested$ OVER SCONF.REQUESTED-XT !
    ['] _smrc-effective$ OVER SCONF.EFFECTIVE-XT !
    ['] _smrc-body$ OVER SCONF.BODY-XT !
    ['] _smrc-media OVER SCONF.MEDIA-KIND-XT !
    ['] _smrc-outcome OVER SCONF.OUTCOME-XT !
    ['] _smrc-detail OVER SCONF.DETAIL-XT !
    ['] _smrc-http OVER SCONF.HTTP-STATUS-XT !
    ['] _smrc-result? OVER SCONF.RESULT-VALID-XT !
    ['] _smrc-cleanup OVER SCONF.CLEANUP-ERROR-XT !
    ['] _smrc-releasable? OVER SCONF.RELEASABLE-XT !
    ['] _smrc-poison OVER SCONF.POISON-XT !
    ['] _smrc-release OVER SCONF.RELEASE-XT !
    ['] _smrc-start OVER SCONF.START-XT !
    ['] _smrc-poll OVER SCONF.POLL-XT !
    ['] _smrc-cancel OVER SCONF.CANCEL-XT !
    ['] _smrc-wipe OVER SCONF.WIPE-XT !
    DUP SCONF-SEAL DUP SCONF-S-OK <> IF
        >R DROP _smrc-provider-context @ FREE
        _smrc-provider @ FREE
        0 _smrc-provider-context ! 0 _smrc-provider !
        0 R> EXIT
    THEN ;

\ ---------------------------------------------------------------------
\ Component, source, request, and fixture helpers
\ ---------------------------------------------------------------------

: _smrc-desk-init  ( -- )
    _DESK-FILL-DESC
    DESK-COMP-DESC CINST-NEW DUP IF
        2DROP 0 _smrc-desk ! 0 _smrc-assert EXIT
    THEN
    DROP DUP _smrc-desk ! _DESK-USE-STATE
    _DESK-XIO-INIT XIO-S-OK = _smrc-assert
    _DESK-ENDPOINT IENDPOINT-INIT
    _smrc-desk @ _DESK-ENDPOINT IEND.CONTEXT !
    ['] _DESK-ENDPOINT-SERVICE _DESK-ENDPOINT IEND.SERVICE-XT !
    _DESK-ENDPOINT _smrc-desk @ CINST.ENDPOINT !
    S" org.akashic.net.external-io" _smrc-desk @ CINST-SERVICE
        _DESK-EXTERNAL-IO = _smrc-assert ;

: _smrc-load-fixture  ( -- )
    NAMEBUF 24 0 FILL
    S" manual-feed.json" DUP >R NAMEBUF SWAP CMOVE R> DROP
    FIND-BY-NAME DUP -1 = ABORT" SMRC fixture missing"
    OPEN-BY-SLOT DUP 0= ABORT" SMRC fixture open failed"
    DUP _smrc-document-fd ! FSIZE DUP _smrc-document-u !
    ALLOCATE ABORT" SMRC fixture allocation failed"
    DUP _smrc-document-a !
    _smrc-document-u @ _smrc-document-fd @ FREAD
        _smrc-document-u @ <> ABORT" SMRC fixture read failed"
    _smrc-document-fd @ FCLOSE ;

: _smrc-document-free  ( -- )
    _smrc-document-a @ ?DUP IF
        DUP _smrc-document-u @ 0 FILL FREE
    THEN
    0 _smrc-document-a ! 0 _smrc-document-u ! ;

: _smrc-instance-new  ( configured? -- instance|0 )
    IF STREAMS-ONLINE-COMP-DESC ELSE STREAMS-COMP-DESC THEN
    CINST-NEW DUP IF 2DROP 0 EXIT THEN DROP
    >R _smrc-endpoint R@ CINST.ENDPOINT !
    R@ STREAMS-INIT-CB R> ;

: _smrc-offline-entry-new  ( -- instance|0 )
    _smrc-offline-desc STREAMS-ENTRY
    _smrc-offline-desc APP.COMP-DESC @ CINST-NEW
    DUP IF 2DROP 0 EXIT THEN DROP
    >R _smrc-endpoint R@ CINST.ENDPOINT !
    R@ _smrc-offline-desc APP.INIT-XT @ EXECUTE R> ;

: _smrc-candidate-common  ( kind format label-a label-u endpoint-a endpoint-u -- )
    _smrc-candidate STREAMS-SOURCE-INIT
    _smrc-candidate STREAMS-SOURCE-ENDPOINT! SSREG-S-OK = _smrc-assert
    _smrc-candidate STREAMS-SOURCE-LABEL! SSREG-S-OK = _smrc-assert
    _smrc-candidate SSOURCE.FORMAT !
    _smrc-candidate SSOURCE.KIND ! ;

: _smrc-create-feed  ( -- )
    SSOURCE-KIND-SYNDICATION SSOURCE-FORMAT-JSON-FEED
    S" Manual feed" S" https://feed.example/manual.json"
        _smrc-candidate-common
    _smrc-candidate _smrc-rid _smrc-inst @ STREAMS-SOURCE-CREATE-OWNER
        STREAMS-SOURCE-S-OK = _smrc-assert
    _smrc-rid RID-PRESENT? _smrc-assert ;

: _smrc-create-page  ( -- )
    SSOURCE-KIND-PAGE SSOURCE-FORMAT-AUTO
    S" Unsupported page" S" https://page.example/manual"
        _smrc-candidate-common
    _smrc-candidate _smrc-page-rid _smrc-inst @
        STREAMS-SOURCE-CREATE-OWNER STREAMS-SOURCE-S-OK = _smrc-assert
    _smrc-page-rid RID-PRESENT? _smrc-assert ;

: _smrc-request-clear  ( -- )
    _smrc-request @ CBR.ARGS CV-FREE
    _smrc-request @ CBR.RESULT CV-FREE ;

: _smrc-slot  ( key-a key-u index map -- value )
    CV-MAP-SLOT! DUP 0= _smrc-assert DROP ;

VARIABLE _smrc-args-rid
VARIABLE _smrc-args-rref-revision
VARIABLE _smrc-args-expected

: _smrc-refresh-args  ( rid rref-revision expected-revision -- )
    _smrc-args-expected ! _smrc-args-rref-revision ! _smrc-args-rid !
    2 _smrc-request @ CBR.ARGS CV-MAP! _smrc-ok
    _smrc-rref RREF-INIT
    _smrc-args-rid @ _smrc-rref RREF.ID RID-COPY
    _smrc-args-rref-revision @ _smrc-rref RREF.REVISION !
    S" resource" 0 _smrc-request @ CBR.ARGS _smrc-slot
        _smrc-rref SWAP IRES-RREF! IRES-S-OK = _smrc-assert
    S" expected_revision" 1 _smrc-request @ CBR.ARGS _smrc-slot
        _smrc-args-expected @ SWAP CV-INT! ;

: _smrc-result-sentinel!  ( -- )
    S" caller-owned sentinel" _smrc-request @ CBR.RESULT CV-STRING!
        0= _smrc-assert ;

: _smrc-result-sentinel?  ( -- flag )
    _smrc-request @ CBR.RESULT DUP CV-TYPE@ CV-T-STRING <> IF
        DROP 0 EXIT
    THEN
    DUP CV-DATA@ SWAP CV-LEN@
        S" caller-owned sentinel" STR-STR= ;

: _smrc-result-field  ( key-a key-u -- value|0 )
    _smrc-request @ CBR.RESULT CV-MAP-FIND ;

: _smrc-string=  ( value expected-a expected-u -- flag )
    2>R DUP 0= IF DROP 2R> 2DROP 0 EXIT THEN
    DUP CV-TYPE@ CV-T-STRING <> IF DROP 2R> 2DROP 0 EXIT THEN
    DUP CV-DATA@ SWAP CV-LEN@ 2R> STR-STR= ;

: _smrc-refresh-scratch-clean?  ( -- flag )
    _STM-SOURCE-REFRESH-RESULT-CANDIDATE CV-SIZE _smrc-zeroed?
    _STM-SOURCE-REFRESH-RESULT-DEST @ 0= AND
    _STM-SOURCE-REFRESH-RESULT-SOURCE @ 0= AND
    _STM-SOURCE-REFRESH-RESULT-GENERATION @ 0= AND
    _STM-CAP-SOURCE @ 0= AND
    _STM-CAP-SOURCE-REFRESH-GENERATION @ 0= AND
    _STM-CAP-SOURCE-REFRESH-STATUS @ 0= AND
    _STM-CAP-SOURCE-REFRESH-CHANGED @ 0= AND ;

: _smrc-source-read-args  ( rid revision -- )
    _smrc-rref RREF-INIT
    SWAP _smrc-rref RREF.ID RID-COPY
    _smrc-rref RREF.REVISION !
    _smrc-rref _smrc-request @ CBR.ARGS IRES-RREF!
        IRES-S-OK = _smrc-assert ;

: _smrc-acquisition-state?  ( rid revision instance expected-a expected-u -- flag )
    2>R >R _smrc-source-read-args
    _smrc-request @ R> _STM-CAP-SOURCE-READ-H CBUS-S-OK <> IF
        2R> 2DROP 0 EXIT
    THEN
    S" acquisition_state" _smrc-result-field 2R> _smrc-string= ;

: _smrc-target!  ( instance -- )
    >R
    R@ CINST.ID @ _smrc-request @ CBR.TARGET-ID !
    R> CINST.GENERATION @ _smrc-request @ CBR.TARGET-GEN ! ;

: _smrc-dispatch-refresh  ( instance -- )
    DUP _smrc-target!
    STREAMS-CAP-SOURCE-REFRESH _smrc-request @ CBR.CAP !
    CPRINC-USER _smrc-request @ CBR.PRINCIPAL !
    DUP CINST.REVISION @ _smrc-request @ CBR.EXPECT-REV ! DROP
    _smrc-request @ _smrc-bus @ CBUS-POST CBUS-S-OK = _smrc-assert
    1 _smrc-bus @ CBUS-PUMP 1 = _smrc-assert ;

: _smrc-durable=live?  ( -- flag )
    _smrc-durable-a @ STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _smrc-current-owner SREF.STORE
        STREAMS-OBSERVATION-STORE-LOAD OSTORE-S-OK <> IF 0 EXIT THEN
    _smrc-durable-a @ STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _smrc-current-checkpoint STREAMS-OBSERVATION-CHECKPOINT-SIZE
        COMPARE 0= ;

\ ---------------------------------------------------------------------
\ Contracts
\ ---------------------------------------------------------------------

: _smrc-test-descriptor  ( -- )
    _STM-CAP-COUNT 15 = _smrc-assert
    STREAMS-COMP-DESC COMP.CAPS-N @ 15 = _smrc-assert
    STREAMS-CAP-SOURCE-REFRESH CAP-DESC-VALID? _smrc-assert
    STREAMS-CAP-SOURCE-REFRESH CAP.KIND @ CAP-K-COMMAND = _smrc-assert
    STREAMS-CAP-SOURCE-REFRESH CAP.FLAGS @ CAP-F-NEEDS-TARGET =
        _smrc-assert
    STREAMS-CAP-SOURCE-REFRESH CAP.EFFECTS @
        CAP-E-PERSIST CAP-E-EXTERNAL OR = _smrc-assert
    STREAMS-CAP-SOURCE-REFRESH CAP.ID-A @
        STREAMS-CAP-SOURCE-REFRESH CAP.ID-U @
        S" streams.source.refresh" STR-STR= _smrc-assert
    S" streams.source.refresh" STREAMS-COMP-DESC COMP-CAP-FIND
        STREAMS-CAP-SOURCE-REFRESH = _smrc-assert
    _STM-SOURCE-REFRESH-IN-SCHEMA CS.FIELD-N @ 2 = _smrc-assert
    _STM-SOURCE-REFRESH-IN-SCHEMA CS.MAX-LEN @ 2 = _smrc-assert
    _STM-SOURCE-REFRESH-ACK-SCHEMA CS.FIELD-N @ 5 = _smrc-assert
    _STM-SOURCE-REFRESH-ACK-SCHEMA CS.MAX-LEN @ 5 = _smrc-assert
    S" source-refresh" _UTUI-ACT-FIND
        ['] _STM-DO-SOURCE-REFRESH = _smrc-assert
    _smrc-stack ;

: _smrc-test-truthful-refusals  ( -- )
    ." SMRC CASE truthful blocked, unsupported, and unavailable states at "
        _smrc-checks @ . CR

    \ A structurally valid owner whose durable store is blocked must not
    \ make source.read claim that the source has merely never refreshed.
    _smrc-current-owner STREAMS-REFRESH-OWNER-VALID? _smrc-assert
    _smrc-current-owner SREF.PHASE @ _smrc-owner-phase-before !
    SREF-PHASE-BLOCKED _smrc-current-owner SREF.PHASE !
    _smrc-rid 1 _smrc-inst @ S" blocked"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear
    _smrc-owner-phase-before @ _smrc-current-owner SREF.PHASE !
    _smrc-current-owner STREAMS-REFRESH-OWNER-VALID? _smrc-assert

    \ R and the menu callback share this action.  A watched page is not a
    \ configured syndication input, so reject it before owner START can
    \ mutate the durable attempt, provider, or component revision.
    _STM-SOURCE-SELECTED @ _smrc-selection-before !
    _STM-VIEW @ _smrc-view-before !
    1 _STM-SOURCE-SELECTED ! _STM-V-SOURCES _STM-VIEW !
    _STM-SOURCE-SELECTED@ _smrc-page-source = _smrc-assert
    _smrc-current-owner _smrc-owner-before
        STREAMS-REFRESH-OWNER-SIZE CMOVE
    _smrc-current-checkpoint _smrc-checkpoint-before
        STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _smrc-plan _smrc-plan-before _SMRF-SIZE CMOVE
    _smrc-revision-capture
    _STM-SOURCE-REFRESH-ACTION
    _smrc-current-owner STREAMS-REFRESH-OWNER-SIZE
        _smrc-owner-before STREAMS-REFRESH-OWNER-SIZE COMPARE 0=
        _smrc-assert
    _smrc-current-checkpoint STREAMS-OBSERVATION-CHECKPOINT-SIZE
        _smrc-checkpoint-before STREAMS-OBSERVATION-CHECKPOINT-SIZE
        COMPARE 0= _smrc-assert
    _smrc-plan _SMRF-SIZE _smrc-plan-before _SMRF-SIZE COMPARE 0=
        _smrc-assert
    _smrc-revision-stable _smrc-generation-stable
    _smrc-service XIO-ACTIVE? 0= _smrc-assert
    _smrc-service XIOS.RETAINED @ 0= _smrc-assert
    _smrc-selection-before @ _STM-SOURCE-SELECTED !
    _smrc-view-before @ _STM-VIEW !

    \ Initialization failures can leave the embedded owner structurally
    \ invalid.  The preserved nonzero init status must project unavailable,
    \ and source.read must release all temporary typed values on cleanup.
    _smrc-current-owner SREF.MAGIC @ _smrc-owner-magic-before !
    _STM-CONFIGURED-INIT-STATUS @ _smrc-configured-init-before !
    HEAP-FREE-BYTES _smrc-truth-heap-before !
    0 _smrc-current-owner SREF.MAGIC !
    SREF-S-STORAGE _STM-CONFIGURED-INIT-STATUS !
    _smrc-rid 1 _smrc-inst @ S" unavailable"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear
    _smrc-configured-init-before @ _STM-CONFIGURED-INIT-STATUS !
    _smrc-owner-magic-before @ _smrc-current-owner SREF.MAGIC !
    _smrc-current-owner STREAMS-REFRESH-OWNER-VALID? _smrc-assert
    HEAP-FREE-BYTES _smrc-truth-heap-before @ = _smrc-assert
    _smrc-stack ;

: _smrc-test-closed-and-refusals  ( -- )
    ." SMRC CASE closed schema and refusal paths at "
        _smrc-checks @ . CR
    _smrc-rid 1 1 _smrc-refresh-args
    \ Replace the second declared key in-place.  Keeping the closed map at
    \ its exact maximum distinguishes UNKNOWN from the earlier LENGTH gate.
    1 _smrc-request @ CBR.ARGS CV-MAP-NTH CV-MAP-KEY
        S" extra" ROT CV-STRING! _smrc-ok
    _smrc-request @ CBR.ARGS _STM-SOURCE-REFRESH-IN-SCHEMA
        CS-VALIDATE-DEEP CS-E-UNKNOWN = _smrc-assert
    _smrc-request-clear

    \ Rebuild the ordinary exact input after the closed-schema probe.
    _smrc-rid 1 1 _smrc-refresh-args
    _smrc-request @ CBR.ARGS _STM-SOURCE-REFRESH-IN-SCHEMA
        CS-VALIDATE-DEEP 0= _smrc-assert
    _smrc-request-clear

    \ A three-field map is rejected by the independent closed length bound.
    3 _smrc-request @ CBR.ARGS CV-MAP! _smrc-ok
    _smrc-rref RREF-INIT
    _smrc-rid _smrc-rref RREF.ID RID-COPY
    1 _smrc-rref RREF.REVISION !
    S" resource" 0 _smrc-request @ CBR.ARGS _smrc-slot
        _smrc-rref SWAP IRES-RREF! IRES-S-OK = _smrc-assert
    S" expected_revision" 1 _smrc-request @ CBR.ARGS _smrc-slot
        1 SWAP CV-INT!
    S" extra" 2 _smrc-request @ CBR.ARGS _smrc-slot
        -1 SWAP CV-BOOL!
    _smrc-request @ CBR.ARGS _STM-SOURCE-REFRESH-IN-SCHEMA
        CS-VALIDATE-DEEP CS-E-LENGTH = _smrc-assert
    _smrc-request-clear

    _smrc-rid 1 2 _smrc-refresh-args _smrc-result-sentinel!
    _smrc-request @ _smrc-inst @ _STM-CAP-SOURCE-REFRESH-H
        CBUS-S-INVALID = _smrc-assert
    _smrc-result-sentinel? _smrc-assert
    _smrc-refresh-scratch-clean? _smrc-assert
    _smrc-request-clear

    _smrc-rid 2 2 _smrc-refresh-args _smrc-result-sentinel!
    _smrc-request @ _smrc-inst @ _STM-CAP-SOURCE-REFRESH-H
        CBUS-S-STALE-REVISION = _smrc-assert
    _smrc-result-sentinel? _smrc-assert
    _smrc-refresh-scratch-clean? _smrc-assert
    _smrc-request-clear

    _smrc-page-rid 1 1 _smrc-refresh-args _smrc-result-sentinel!
    _smrc-request @ _smrc-inst @ _STM-CAP-SOURCE-REFRESH-H
        CBUS-S-INVALID = _smrc-assert
    _smrc-result-sentinel? _smrc-assert
    _smrc-refresh-scratch-clean? _smrc-assert
    _smrc-request-clear

    HEAP-FREE-BYTES _smrc-offline-heap-before !
    _smrc-offline-entry-new DUP 0<> _smrc-assert DUP _smrc-offline ! DROP
    _smrc-offline @ _STM-ACTIVATE
    _STM-CONFIGURED-REFRESH STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-OFFLINE = _smrc-assert
    _smrc-rid 1 1 _smrc-refresh-args _smrc-result-sentinel!
    _smrc-request @ _smrc-offline @ _STM-CAP-SOURCE-REFRESH-H
        CBUS-S-NOT-FOUND = _smrc-assert
    _smrc-result-sentinel? _smrc-assert
    _smrc-refresh-scratch-clean? _smrc-assert
    _smrc-request-clear
    _smrc-offline @ CINST-FREE 0 _smrc-offline !
    HEAP-FREE-BYTES _smrc-offline-heap-before @ = _smrc-assert
    _smrc-inst @ _STM-ACTIVATE
    _smrc-generation-stable _smrc-revision-stable _smrc-stack ;

: _smrc-test-typed-accept-and-success  ( -- )
    ." SMRC CASE exact typed acceptance and cooperative success at "
        _smrc-checks @ . CR
    _smrc-rid 1 1 _smrc-refresh-args
    _smrc-request @ CBR.ARGS _STM-SOURCE-REFRESH-IN-SCHEMA
        CS-VALIDATE-DEEP 0= _smrc-assert
    _smrc-current-checkpoint OCHK.GENERATION @ _smrc-before !
    _smrc-revision-capture
    _smrc-inst @ _smrc-dispatch-refresh
    _smrc-request @ CBR.STATUS @ CBUS-S-OK = _smrc-assert
    _smrc-revision-advanced _smrc-generation-stable
    _smrc-request @ CBR.ACTUAL-REV @
        _smrc-inst @ CINST.REVISION @ = _smrc-assert
    _smrc-current-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-ACTIVE = _smrc-assert
    _smrc-current-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@
        1 = _smrc-assert
    _smrc-current-owner SREF.OWNER-GENERATION @
        _smrc-fixed-generation @ = _smrc-assert
    _smrc-inst @ CINST.ID @ _smrc-fixed-generation @ 1
        _smrc-current-owner SREF.XIO-OP XIO-OP-MATCH? _smrc-assert
    _smrc-plan _SMRF-START-COUNT + @ 0= _smrc-assert
    _smrc-current-checkpoint OCHK.GENERATION @
        _smrc-before @ 1+ = _smrc-assert
    _smrc-head DUP 0<> _smrc-assert DUP IF
        OCS.STATE @ OCHK-ATTEMPT-ACCEPTED = _smrc-assert
    ELSE DROP THEN
    _smrc-durable=live? _smrc-assert

    _smrc-request @ CBR.RESULT STREAMS-CAP-SOURCE-REFRESH CAP.OUT-SCHEMA @
        CS-VALIDATE-DEEP 0= _smrc-assert
    _smrc-request @ CBR.RESULT CV-LEN@ 5 = _smrc-assert
    S" resource" _smrc-result-field _smrc-result-rref IRES-RREF@
        IRES-S-OK = _smrc-assert
    _smrc-result-rref RREF.ID _smrc-rid RID= _smrc-assert
    _smrc-result-rref RREF.REVISION @ 1 = _smrc-assert
    S" source_revision" _smrc-result-field CV-DATA@ 1 = _smrc-assert
    S" accepted" _smrc-result-field DUP CV-TYPE@ CV-T-BOOL =
        _smrc-assert CV-DATA@ 0<> _smrc-assert
    S" request_generation" _smrc-result-field CV-DATA@ 1 = _smrc-assert
    S" state" _smrc-result-field S" accepted" _smrc-string= _smrc-assert
    S" endpoint" _smrc-result-field 0= _smrc-assert
    S" config" _smrc-result-field 0= _smrc-assert
    _smrc-request @ CBR.ARGS _STM-SOURCE-REFRESH-IN-SCHEMA
        CS-VALIDATE-DEEP 0= _smrc-assert
    _smrc-refresh-scratch-clean? _smrc-assert

    \ A second exact command is refused while the accepted XIO operation is
    \ active.  It neither advances the durable attempt nor replaces caller
    \ result storage.
    _smrc-request-clear
    _smrc-rid 1 1 _smrc-refresh-args _smrc-result-sentinel!
    _smrc-current-checkpoint OCHK.GENERATION @ _smrc-before !
    _smrc-request @ _smrc-inst @ _STM-CAP-SOURCE-REFRESH-H
        CBUS-S-BUSY = _smrc-assert
    _smrc-result-sentinel? _smrc-assert
    _smrc-current-checkpoint OCHK.GENERATION @ _smrc-before @ =
        _smrc-assert
    _smrc-current-owner STREAMS-REFRESH-OWNER-REQUEST-GENERATION@
        1 = _smrc-assert
    _smrc-refresh-scratch-clean? _smrc-assert
    _smrc-request-clear

    _smrc-rid 1 _smrc-inst @ S" accepted"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear
    _smrc-revision-capture

    _smrc-desk-pump
    _smrc-plan _SMRF-START-COUNT + @ 1 = _smrc-assert
    _smrc-plan _SMRF-EXACT-OK + @ _smrc-assert
    _smrc-plan _SMRF-DURABLE-OK + @ _smrc-assert
    _smrc-inst @ STREAMS-TICK-CB
    _smrc-revision-stable _smrc-generation-stable
    _smrc-current-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-ACTIVE = _smrc-assert

    _smrc-desk-pump
    _smrc-plan _SMRF-POLL-COUNT + @ 1 = _smrc-assert
    _smrc-inst @ STREAMS-TICK-CB
    _smrc-revision-advanced _smrc-generation-stable
    _smrc-current-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-SUCCEEDED = _smrc-assert
    _smrc-current-checkpoint OCHK.OBSERVATION-COUNT @ 2 = _smrc-assert
    _smrc-head DUP OCS.STATE @ OCHK-ATTEMPT-SUCCEEDED = _smrc-assert
    DUP OCS.NEW-COUNT @ 2 = _smrc-assert DROP
    _smrc-durable=live? _smrc-assert
    _smrc-service XIO-ACTIVE? 0= _smrc-assert
    _smrc-service XIOS.RETAINED @ 0= _smrc-assert

    _smrc-rid 1 _smrc-inst @ S" succeeded"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear _smrc-stack ;

: _smrc-test-relaunch-ui-and-recovery  ( -- )
    ." SMRC CASE relaunch, menu action, and boot recovery at "
        _smrc-checks @ . CR
    _smrc-inst @ _smrc-registry @ CREG-INST- 0= _smrc-assert
    _smrc-bus @ CBUS-FREE 0 _smrc-bus !
    _smrc-registry @ CREG-FREE 0 _smrc-registry !
    _smrc-inst @ CINST-FREE 0 _smrc-inst !

    -1 _smrc-instance-new DUP 0<> _smrc-assert DUP _smrc-relaunch !
    DUP _smrc-inst ! _STM-ACTIVATE
    _smrc-inst @ CINST.GENERATION @ DUP 0<> _smrc-assert
        _smrc-fixed-generation !
    _smrc-current-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-IDLE = _smrc-assert
    _smrc-current-checkpoint OCHK.OBSERVATION-COUNT @ 2 = _smrc-assert
    _smrc-rid 1 _smrc-inst @ S" succeeded"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear

    \ The menu callback and R-key action share the same start core.  The UI
    \ accepts the exact selected source, advances only component REVISION,
    \ and leaves XIO work cooperative for Desk's pump.
    0 _STM-SOURCE-SELECTED !
    _smrc-revision-capture
    _smrc-current-checkpoint OCHK.GENERATION @ _smrc-before !
    _STM-SOURCE-REFRESH-ACTION
    _smrc-revision-advanced _smrc-generation-stable
    _smrc-current-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-ACTIVE = _smrc-assert
    _smrc-current-owner SREF.OWNER-GENERATION @
        _smrc-fixed-generation @ = _smrc-assert
    _smrc-current-checkpoint OCHK.GENERATION @
        _smrc-before @ 1+ = _smrc-assert
    _smrc-plan _SMRF-START-COUNT + @ 1 = _smrc-assert
    _smrc-desk-pump _smrc-inst @ STREAMS-TICK-CB
    _smrc-revision-stable
    _smrc-desk-pump _smrc-inst @ STREAMS-TICK-CB
    _smrc-revision-advanced _smrc-generation-stable
    _smrc-plan _SMRF-START-COUNT + @ 2 = _smrc-assert
    _smrc-plan _SMRF-POLL-COUNT + @ 2 = _smrc-assert
    _smrc-current-checkpoint OCHK.OBSERVATION-COUNT @ 2 = _smrc-assert
    _smrc-head OCS.UNCHANGED-COUNT @ 2 = _smrc-assert
    _smrc-rid 1 _smrc-inst @ S" succeeded"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear

    \ Seed the exact durable state a process crash would leave: BEGIN was
    \ committed but no terminal observation was published.  Releasing this
    \ idle owner cannot alter that external record.  The next lifecycle must
    \ recover it as INDETERMINATE before exposing the checkpoint.
    _smrc-current-checkpoint OCHK.GENERATION @ _smrc-old-generation !
    _smrc-current-checkpoint _smrc-durable-a @
        STREAMS-OBSERVATION-CHECKPOINT-SIZE CMOVE
    _smrc-seed-namespace RID-CLEAR 8801 _smrc-seed-namespace !
    _smrc-rid 1 _smrc-seed-namespace SREF-PROVIDER-SYNDICATION
        S" https://feed.example/manual.json" _smrc-durable-a @ OCHK-BEGIN
        OCHK-S-OK = _smrc-assert
    _smrc-durable-a @ _smrc-old-generation @
        _smrc-current-owner SREF.STORE STREAMS-OBSERVATION-STORE-SAVE
        OSTORE-S-OK = _smrc-assert

    _smrc-inst @ CINST-FREE
    0 _smrc-inst ! 0 _smrc-relaunch !
    -1 _smrc-instance-new DUP 0<> _smrc-assert DUP _smrc-recovery !
    DUP _smrc-inst ! _STM-ACTIVATE
    _smrc-inst @ CINST.REVISION @ 1 = _smrc-assert
    _smrc-inst @ CINST.GENERATION @ DUP 0<> _smrc-assert
        _smrc-fixed-generation !
    _smrc-current-owner STREAMS-REFRESH-OWNER-PHASE@
        SREF-PHASE-RECOVERED = _smrc-assert
    _smrc-head DUP OCS.STATE @ OCHK-ATTEMPT-INDETERMINATE =
        _smrc-assert
    OCS.OUTCOME @ OCHK-O-INDETERMINATE = _smrc-assert
    _smrc-durable=live? _smrc-assert
    _smrc-rid 1 _smrc-inst @ S" indeterminate"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear

    \ Attempt projection is exact to the immutable source revision.  Source
    \ mutations retain the old audit head in the observation checkpoint but
    \ must present the new revision as never refreshed in source.read and UI.
    _smrc-rid 1 0 _smrc-inst @ STREAMS-SOURCE-ENABLE-OWNER
        STREAMS-SOURCE-S-OK = _smrc-assert
    _smrc-inst @ CINST.REVISION @ 2 = _smrc-assert
    _smrc-feed-source DUP SSOURCE.REVISION @ 2 = _smrc-assert
        _STM-SOURCE-ATTEMPT-HEAD 0= _smrc-assert
    _smrc-rid 2 _smrc-inst @ S" never refreshed"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear

    _smrc-rid 2 -1 _smrc-inst @ STREAMS-SOURCE-ENABLE-OWNER
        STREAMS-SOURCE-S-OK = _smrc-assert
    _smrc-inst @ CINST.REVISION @ 3 = _smrc-assert
    _smrc-rid 3 _smrc-inst @ S" never refreshed"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear

    _smrc-feed-source _smrc-candidate STREAMS-SOURCE-SIZE CMOVE
    S" Revised after refresh" _smrc-candidate STREAMS-SOURCE-LABEL!
        SSREG-S-OK = _smrc-assert
    _smrc-candidate 3 _smrc-inst @ STREAMS-SOURCE-REPLACE-OWNER
        STREAMS-SOURCE-S-OK = _smrc-assert
    _smrc-inst @ CINST.REVISION @ 4 = _smrc-assert
    _smrc-feed-source DUP SSOURCE.REVISION @ 4 = _smrc-assert
        _STM-SOURCE-ATTEMPT-HEAD 0= _smrc-assert
    _smrc-rid 4 _smrc-inst @ S" never refreshed"
        _smrc-acquisition-state? _smrc-assert
    _smrc-request-clear
    _smrc-head OCS.SOURCE-REVISION @ 1 = _smrc-assert
    _smrc-generation-stable _smrc-stack ;

: _smrc-begin  ( -- )
    0 _smrc-fails ! 0 _smrc-checks !
    0 _smrc-desk ! 0 _smrc-inst ! 0 _smrc-offline ! 0 _smrc-relaunch !
    0 _smrc-recovery ! 0 _smrc-request ! 0 _smrc-registry ! 0 _smrc-bus !
    0 _smrc-document-a ! 0 _smrc-document-u !
    _smrc-load-fixture _smrc-plan-defaults
    STREAMS-OBSERVATION-CHECKPOINT-SIZE ALLOCATE
        DUP 0= _smrc-assert DROP _smrc-durable-a !
    VFS-CUR _smrc-old-vfs !
    8388608 A-XMEM ARENA-NEW DUP 0= _smrc-assert DROP
    VFS-RAM-VTABLE VFS-NEW DUP 0<> _smrc-assert DUP _smrc-vfs ! VFS-USE
    _smrc-desk-init
    _STREAMS-COMP-SETUP
    ['] _smrc-factory STREAMS-ONLINE-COMP-SETUP-WITH-CONFIGURED
    STREAMS-ONLINE-COMP-DESC COMP.STATE-INIT-XT @
        ['] _STREAMS-ONLINE-STATE-INIT = _smrc-assert
    -1 _smrc-instance-new DUP 0<> _smrc-assert DUP _smrc-inst !
    DUP CINST.GENERATION @ DUP 0<> _smrc-assert _smrc-fixed-generation !
    CINST.REVISION @ 1 = _smrc-assert
    _smrc-inst @ _STM-ACTIVATE
    _STM-PUBLIC-FACTORY-XT @ ['] STREAMS-BLUESKY-PUBLIC-NEW = _smrc-assert
    _STM-CONFIGURED-FACTORY-XT @ ['] _smrc-factory = _smrc-assert
    _STM-PUBLIC-PROVIDER @ DUP 0<> _smrc-assert SPUB-VALID? _smrc-assert
    _STM-XIO-SERVICE @ _smrc-service = _smrc-assert
    _STM-XIO-OP XIOO.STATE @ XIO-STATE-RESET = _smrc-assert
    _STM-CONFIGURED-REFRESH STREAMS-REFRESH-OWNER-AVAILABLE? _smrc-assert
    _STM-CONFIGURED-REFRESH SREF.PROVIDER @ SCONF-VALID? _smrc-assert
    _smrc-service XIO-ACTIVE? 0= _smrc-assert
    _smrc-service XIOS.RETAINED @ 0= _smrc-assert
    _smrc-plan _SMRF-START-COUNT + @ 0= _smrc-assert
    _smrc-revision-capture
    _smrc-create-feed _smrc-revision-advanced _smrc-generation-stable
    _smrc-create-page _smrc-revision-advanced _smrc-generation-stable
    CBR-NEW DUP 0= _smrc-assert DROP _smrc-request !
    CREG-NEW DUP 0= _smrc-assert DROP _smrc-registry !
    STREAMS-COMP-DESC _smrc-registry @ CREG-TYPE+ 0= _smrc-assert
    _smrc-inst @ _smrc-registry @ CREG-INST+ 0= _smrc-assert
    _smrc-registry @ 0 CBUS-NEW DUP 0= _smrc-assert DROP _smrc-bus !
    DEPTH _smrc-depth ! _smrc-stack ;

: _smrc-finish  ( -- )
    _smrc-request @ ?DUP IF CBR-FREE 0 _smrc-request ! THEN
    _smrc-inst @ ?DUP IF CINST-FREE 0 _smrc-inst ! THEN
    _smrc-service XIO-ACTIVE? 0= _smrc-assert
    _smrc-service XIOS.RETAINED @ 0= _smrc-assert
    _smrc-desk @ _DESK-USE-STATE
    _DESK-XIO-FINI XIO-S-OK = _smrc-assert
    _smrc-desk @ CINST-FREE 0 _smrc-desk !
    _smrc-plan _SMRF-FACTORY-COUNT + @ 3 = _smrc-assert
    _smrc-plan _SMRF-RELEASE-COUNT + @ 3 = _smrc-assert
    _smrc-old-vfs @ VFS-USE
    _smrc-vfs @ VFS-DESTROY 0 _smrc-vfs !
    _smrc-durable-a @ ?DUP IF
        DUP STREAMS-OBSERVATION-CHECKPOINT-SIZE 0 FILL FREE
    THEN
    0 _smrc-durable-a ! _smrc-document-free
    _smrc-stack
    _smrc-fails @ 0= IF
        ." STREAMS MANUAL REFRESH CONTRACTS PASS " _smrc-checks @ .
    ELSE
        ." STREAMS MANUAL REFRESH CONTRACTS FAIL " _smrc-fails @ .
        ." / " _smrc-checks @ .
    THEN CR ;

: _smrc-run  ( -- )
    _smrc-begin
    _smrc-test-descriptor
    _smrc-test-truthful-refusals
    _smrc-test-closed-and-refusals
    _smrc-test-typed-accept-and-success
    _smrc-test-relaunch-ui-and-recovery
    _smrc-finish ;
