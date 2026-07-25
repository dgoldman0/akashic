\ Focused, bounded contracts for the L13 Streams runtime owner.
\
\ The qualified migration fixture supplies one RAM VFS and exact both-valid
\ legacy evidence.  This fixture closes those setup owners, activates the
\ production runtime twice over the same VFS, and never starts XIO.  The first
\ activation imports legacy authority and leaves one repository-native
\ ACCEPTED attempt.  Before the second activation the legacy source evidence
\ is deliberately corrupted.  Reopen must prefer the existing repository and
\ recover only the native ACCEPTED attempt as indeterminate.

PROVIDED streams-l13-rt-tests

VARIABLE _SL13T-checks
VARIABLE _SL13T-fails
VARIABLE _SL13T-depth
VARIABLE _SL13T-record-u
VARIABLE _SL13T-generation
VARIABLE _SL13T-evidence-status

STREAMS-RUNTIME-OWNER-SIZE XBUF _SL13T-owner-a
STREAMS-RUNTIME-OWNER-SIZE XBUF _SL13T-owner-b
STREAMS-SOURCE-SIZE XBUF _SL13T-source-read
STREAMS-ACQUISITION-WORK-SIZE XBUF _SL13T-acquisition-work
STREAMS-ACQUISITION-BEGIN-REQUEST-SIZE XBUF _SL13T-begin-request
OCHK-SOURCE-SIZE XBUF _SL13T-accepted
CREATE _SL13T-corrupt-digest SHA3-256-LEN ALLOT

: _SL13T-assert  ( flag -- )
    1 _SL13T-checks +!
    0= IF
        1 _SL13T-fails +!
        ." STREAMS L13 RUNTIME ASSERT " _SL13T-checks @ . CR
    THEN ;

: _SL13T-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 RUNTIME STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13T-assert ;

: _SL13T-stack  ( -- )
    DEPTH DUP _SL13T-depth @ <> IF
        ." STREAMS L13 RUNTIME STACK "
        _SL13T-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13T-depth @ = _SL13T-assert ;

: _SL13T-init  ( owner -- status )
    >R
    _SL13M-vfs @ 0 0 _SL13M-authority R>
        STREAMS-RUNTIME-OWNER-INIT ;

: _SL13T-repository  ( owner -- repository )
    STREAMS-RUNTIME-OWNER-REPOSITORY ;

: _SL13T-repo-work  ( owner -- work )
    STREAMS-RUNTIME-OWNER-REPOSITORY-WORK ;

: _SL13T-source-work  ( owner -- work )
    STREAMS-RUNTIME-OWNER-SOURCE-WORK ;

: _SL13T-query-work  ( owner -- work )
    STREAMS-RUNTIME-OWNER-QUERY-WORK ;

: _SL13T-query-page  ( owner -- page )
    STREAMS-RUNTIME-OWNER-QUERY-PAGE ;

: _SL13T-adapter  ( owner -- adapter )
    _SL13T-repository STREAMS-REPOSITORY-ADAPTER@ ;

: _SL13T-adapter-work  ( owner -- work )
    _SL13T-repo-work STREAMS-REPOSITORY-ADAPTER-WORK@ ;

: _SL13T-root  ( owner -- root )
    _SL13T-repo-work STREAMS-REPOSITORY-AUTHORITY-ROOT@ ;

\ Close only the setup descriptors.  The VFS and its arena remain live for
\ both runtime activations.
: _SL13T-close-setup-owners  ( -- )
    _SL13M-repository _SL13M-repository-work
        STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13T-status
    _SL13M-observation-store STREAMS-OBSERVATION-STORE-FINI
        OSTORE-S-OK _SL13T-status
    _SL13M-source-store STREAMS-SOURCE-STORE-FINI
        SSSTORE-S-OK _SL13T-status
    _SL13T-stack ;

: _SL13T-ready-common  ( owner -- )
    DUP STREAMS-RUNTIME-OWNER-VALID? _SL13T-assert
    DUP STREAMS-RUNTIME-OWNER-READY? _SL13T-assert
    DUP STREAMS-RUNTIME-OWNER-PHASE@
        SRT-PHASE-READY = _SL13T-assert
    DUP STREAMS-RUNTIME-OWNER-STATUS@
        SRT-S-OK = _SL13T-assert
    DUP STREAMS-RUNTIME-OWNER-REPOSITORY-STATUS@
        STREAMS-REPOSITORY-S-OK = _SL13T-assert
    DUP STREAMS-RUNTIME-OWNER-RECOVERY-STATUS@
        STREAMS-ACQUISITION-S-OK = _SL13T-assert
    DUP STREAMS-RUNTIME-OWNER-REFRESH-STATUS@
        SRRO-S-UNAVAILABLE = _SL13T-assert
    DUP STREAMS-RUNTIME-OWNER-REFRESH 0= _SL13T-assert
    DUP SRT.BOOT @ 0= _SL13T-assert
    DUP SRT.BOOT-SIZE @ 0= _SL13T-assert
    DUP SRT.SOURCE-OPEN @ 0= _SL13T-assert
    SRT.OBSERVATION-OPEN @ 0= _SL13T-assert ;

: _SL13T-root-common  ( owner -- root )
    _SL13T-root
    DUP 0<> _SL13T-assert
    DUP STREAMS-AUTHORITY-ROOT-HEADER-VALID? _SL13T-assert
    DUP SAR.AUTHORITY-ID _SL13M-authority RID= _SL13T-assert
    DUP SAR.PROVENANCE @
        STREAMS-AUTHORITY-PROVENANCE-LEGACY-BOTH =
        _SL13T-assert
    DUP SAR.SOURCE-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13T-assert
    DUP SAR.OBSERVATION-COMPLETENESS @
        STREAMS-AUTHORITY-COMPLETE = _SL13T-assert
    DUP SAR.SOURCE-COUNT @ 1 = _SL13T-assert
    DUP SAR.REMOVED-SOURCE-COUNT @ 0= _SL13T-assert
    DUP SAR.OBSERVATION-COUNT @ 1 = _SL13T-assert
    DUP SAR.NATIVE-COUNT @ 1 = _SL13T-assert
    DUP SAR.LEGACY-SOURCE-DIGEST SHA3-256-LEN
        _SL13M-source-digest SHA3-256-LEN
        COMPARE 0= _SL13T-assert
    DUP SAR.LEGACY-OBSERVATION-DIGEST SHA3-256-LEN
        _SL13M-observation-digest SHA3-256-LEN
        COMPARE 0= _SL13T-assert ;

: _SL13T-read-source  ( owner -- )
    >R
    _SL13M-source-rid _SL13T-source-read
    R@ _SL13T-repository
    R@ _SL13T-repo-work
    R@ _SL13T-source-work
        STREAMS-SOURCE-AUTHORITY-READ
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13T-status
    _SL13T-source-read STREAMS-SOURCE-VALID? _SL13T-assert
    _SL13T-source-read SSOURCE.ID
        _SL13M-source-rid RID= _SL13T-assert
    _SL13T-source-read SSOURCE.REVISION @ 1 = _SL13T-assert
    _SL13T-source-read STREAMS-SOURCE-LABEL$
        S" Migrated configured feed" STR-STR= _SL13T-assert
    _SL13T-source-read STREAMS-SOURCE-ENDPOINT$
        S" https://example.test/migrated.json"
        STR-STR= _SL13T-assert
    R> DROP ;

: _SL13T-query-source  ( owner -- )
    >R
    R@ _SL13T-query-page
    R@ _SL13T-adapter
    R@ _SL13T-adapter-work
    R@ _SL13T-query-work
        STREAMS-QUERY-SOURCES-FIRST
        STREAMS-QUERY-S-OK _SL13T-status
    R@ _SL13T-query-page
        STREAMS-QUERY-PAGE-PUBLISHED? _SL13T-assert
    R@ _SL13T-query-page
        STREAMS-QUERY-PAGE-COUNT@ 1 = _SL13T-assert
    R@ _SL13T-query-page
        STREAMS-QUERY-PAGE-PROVENANCE@
        STREAMS-AUTHORITY-PROVENANCE-LEGACY-BOTH =
        _SL13T-assert
    0 R@ _SL13T-query-page STREAMS-QUERY-SOURCE-PAGE-ROW@
    DUP 0<> _SL13T-assert
    DUP SPRS.ID _SL13M-source-rid RID= _SL13T-assert
    SPRS.REVISION @ 1 = _SL13T-assert
    R> DROP ;

: _SL13T-latest-attempt  ( owner -- attempt-record )
    >R
    _SL13M-source-rid
    R@ _SL13T-query-page
    R@ _SL13T-adapter
    R@ _SL13T-adapter-work
    R@ _SL13T-query-work
        STREAMS-QUERY-ATTEMPT-LATEST@
        STREAMS-QUERY-S-OK _SL13T-status
    DUP 0<> _SL13T-assert
    R> DROP ;

: _SL13T-assert-imported-attempt  ( -- )
    _SL13T-owner-a _SL13T-latest-attempt
    DUP SPRA.ATTEMPT-SEQUENCE @ 2 = _SL13T-assert
    DUP SPRA.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13T-assert
    SPRA.OUTCOME @
        OCHK-O-INDETERMINATE = _SL13T-assert ;

: _SL13T-assert-root-a  ( -- )
    _SL13T-owner-a _SL13T-root-common
    DUP SAR.LOGICAL-GENERATION @ 0= _SL13T-assert
    DUP SAR.MUTATION-SEQUENCE @ 1 = _SL13T-assert
    DUP SAR.ACQUISITION-SEQUENCE @ 2 = _SL13T-assert
    DUP SAR.ATTEMPT-COUNT @ 1 = _SL13T-assert
    SAR.ACTIVE-COUNT @ 0= _SL13T-assert ;

: _SL13T-activation-a  ( -- )
    ." SL13T CASE legacy import and steady runtime" CR
    _SL13T-owner-a _SL13T-init SRT-S-OK _SL13T-status
    _SL13T-owner-a _SL13T-ready-common
    _SL13T-owner-a STREAMS-RUNTIME-OWNER-MIGRATION-STATUS@
        STREAMS-MIGRATION-S-OK _SL13T-status
    _SL13T-owner-a
        STREAMS-RUNTIME-OWNER-MIGRATED-RECOVERED-COUNT@
        1 = _SL13T-assert
    _SL13T-owner-a
        STREAMS-RUNTIME-OWNER-NATIVE-RECOVERED-COUNT@
        0= _SL13T-assert
    _SL13T-assert-root-a
    _SL13T-owner-a _SL13T-read-source
    _SL13T-owner-a _SL13T-query-source
    _SL13T-assert-imported-attempt

    _SL13T-owner-b _SL13T-init SRT-S-BUSY _SL13T-status
    _SL13T-owner-b STREAMS-RUNTIME-OWNER-VALID? 0=
        _SL13T-assert
    _SL13T-owner-b STREAMS-RUNTIME-OWNER-PHASE@
        SRT-PHASE-UNINITIALIZED = _SL13T-assert
    _SL13T-owner-b STREAMS-RUNTIME-OWNER-STATUS@
        SRT-S-INVALID = _SL13T-assert
    _SL13T-stack ;

: _SL13T-begin-native  ( -- )
    _SL13T-acquisition-work STREAMS-ACQUISITION-WORK-INIT
        STREAMS-ACQUISITION-S-OK _SL13T-status
    _SL13T-begin-request STREAMS-ACQUISITION-BEGIN-REQUEST-INIT
        STREAMS-ACQUISITION-S-OK _SL13T-status
    _SL13M-source-rid
        _SL13T-begin-request SABR.SOURCE-ID RID-COPY
    1 _SL13T-begin-request SABR.SOURCE-REVISION !
    _SL13M-namespace
        _SL13T-begin-request SABR.NAMESPACE RID-COPY
    OCHK-NATIVE-PROVIDER-ID
        _SL13T-begin-request SABR.PROVIDER-KIND !
    S" https://example.test/migrated.json"
        _SL13T-begin-request SABR.REQUESTED-U !
        _SL13T-begin-request SABR.REQUESTED-A !
    _SL13T-begin-request
        STREAMS-ACQUISITION-BEGIN-REQUEST-VALID?
        _SL13T-assert

    _SL13T-begin-request _SL13T-accepted
    _SL13T-owner-a _SL13T-repository
    _SL13T-owner-a _SL13T-repo-work
    _SL13T-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13T-status
    _SL13T-accepted OCS.STATE @
        OCHK-ATTEMPT-ACCEPTED = _SL13T-assert
    _SL13T-accepted OCS.OUTCOME @
        OCHK-O-NONE = _SL13T-assert
    _SL13T-accepted OCS.ATTEMPT-SEQUENCE @ 3 =
        _SL13T-assert
    _SL13T-accepted OCS.SOURCE-REVISION @ 1 =
        _SL13T-assert

    _SL13T-owner-a _SL13T-root
    DUP SAR.LOGICAL-GENERATION @ 1 = _SL13T-assert
    DUP SAR.MUTATION-SEQUENCE @ 2 = _SL13T-assert
    DUP SAR.ACQUISITION-SEQUENCE @ 3 = _SL13T-assert
    DUP SAR.ATTEMPT-COUNT @ 2 = _SL13T-assert
    SAR.ACTIVE-COUNT @ 1 = _SL13T-assert
    _SL13T-owner-a _SL13T-latest-attempt
    SPRA.ATTEMPT OCHK-SOURCE-SIZE
        _SL13T-accepted OCHK-SOURCE-SIZE
        COMPARE 0= _SL13T-assert
    _SL13T-stack ;

: _SL13T-release-a  ( -- )
    _SL13T-owner-a STREAMS-RUNTIME-OWNER-RELEASE
        SRT-S-OK _SL13T-status
    _SL13T-owner-a STREAMS-RUNTIME-OWNER-VALID? 0=
        _SL13T-assert
    _SL13T-owner-a STREAMS-RUNTIME-OWNER-PHASE@
        SRT-PHASE-UNINITIALIZED = _SL13T-assert
    _SL13T-acquisition-work
        STREAMS-ACQUISITION-WORK-SIZE 0 FILL
    _SL13T-stack ;

: _SL13T-corrupt-legacy-source  ( -- )
    ." SL13T CASE corrupt legacy behind repository root" CR
    _SL13M-read-source-record
    _SL13M-source-raw STREAMS-SOURCE-STORE-HEADER-SIZE +
        DUP C@ 1 XOR SWAP C!
    _SL13M-write-source-record

    _SL13M-vfs @ _SL13M-source-store STREAMS-SOURCE-STORE-INIT
        SSSTORE-S-OK _SL13T-status
    _SL13M-registry STREAMS-SOURCE-REGISTRY-SIZE
    _SL13T-corrupt-digest _SL13M-source-store
        STREAMS-SOURCE-STORE-LOAD-EVIDENCE
    _SL13T-evidence-status !
    _SL13T-generation !
    _SL13T-record-u !
    _SL13T-evidence-status @
        SSSTORE-S-CORRUPT _SL13T-status
    _SL13T-record-u @ 0= _SL13T-assert
    _SL13T-generation @ 0= _SL13T-assert
    _SL13T-corrupt-digest SHA3-256-LEN
        _SL13M-zero? _SL13T-assert
    _SL13M-source-store STREAMS-SOURCE-STORE-FINI
        SSSTORE-S-OK _SL13T-status
    _SL13T-stack ;

: _SL13T-assert-root-b  ( -- )
    _SL13T-owner-b _SL13T-root-common
    \ BEGIN and boot recovery each publish one semantic adapter commit.
    DUP SAR.LOGICAL-GENERATION @ 2 = _SL13T-assert
    DUP SAR.MUTATION-SEQUENCE @ 3 = _SL13T-assert
    DUP SAR.ACQUISITION-SEQUENCE @ 3 = _SL13T-assert
    DUP SAR.ATTEMPT-COUNT @ 2 = _SL13T-assert
    SAR.ACTIVE-COUNT @ 0= _SL13T-assert ;

: _SL13T-assert-native-recovery  ( -- )
    _SL13T-owner-b _SL13T-latest-attempt
    DUP SPRA.ATTEMPT-SEQUENCE @ 3 = _SL13T-assert
    DUP SPRA.STATE @
        OCHK-ATTEMPT-INDETERMINATE = _SL13T-assert
    DUP SPRA.OUTCOME @
        OCHK-O-INDETERMINATE = _SL13T-assert
    DUP SPRA.ATTEMPT-ID
        _SL13T-accepted OCS.ATTEMPT-ID RID=
        _SL13T-assert
    DUP SPRA.SOURCE-ID
        _SL13T-accepted OCS.SOURCE-ID RID=
        _SL13T-assert
    DUP SPRA.SOURCE-REVISION @
        _SL13T-accepted OCS.SOURCE-REVISION @ =
        _SL13T-assert
    DUP SPRA.NAMESPACE
        _SL13T-accepted OCS.NAMESPACE RID=
        _SL13T-assert
    SPRA-REQUESTED$
        _SL13T-accepted OCS.REQUESTED$
        STR-STR= _SL13T-assert ;

: _SL13T-activation-b  ( -- )
    ." SL13T CASE repository precedence and native recovery" CR
    _SL13T-owner-b _SL13T-init SRT-S-OK _SL13T-status
    _SL13T-owner-b _SL13T-ready-common
    _SL13T-owner-b STREAMS-RUNTIME-OWNER-MIGRATION-STATUS@
        STREAMS-MIGRATION-S-ALREADY _SL13T-status
    _SL13T-owner-b
        STREAMS-RUNTIME-OWNER-MIGRATED-RECOVERED-COUNT@
        0= _SL13T-assert
    _SL13T-owner-b
        STREAMS-RUNTIME-OWNER-NATIVE-RECOVERED-COUNT@
        1 = _SL13T-assert
    _SL13T-assert-root-b
    _SL13T-owner-b _SL13T-read-source
    _SL13T-owner-b _SL13T-query-source
    _SL13T-assert-native-recovery
    _SL13T-owner-b STREAMS-RUNTIME-OWNER-RELEASE
        SRT-S-OK _SL13T-status
    _SL13T-owner-b STREAMS-RUNTIME-OWNER-VALID? 0=
        _SL13T-assert
    _SL13T-stack ;

: _SL13T-RUN  ( -- )
    0 _SL13T-checks !
    0 _SL13T-fails !
    0 _SL13M-checks !
    0 _SL13M-fails !
    DEPTH _SL13T-depth !
    DEPTH _SL13M-depth !
    _SL13T-owner-a STREAMS-RUNTIME-OWNER-SIZE 0 FILL
    _SL13T-owner-b STREAMS-RUNTIME-OWNER-SIZE 0 FILL
    _SL13T-accepted OCHK-SOURCE-SIZE 0 FILL

    _SL13M-case-setup
    _SL13M-source-legacy
    _SL13M-observation-legacy
    _SL13M-capture-evidence
    _SL13T-close-setup-owners

    _SL13T-activation-a
    _SL13T-begin-native
    _SL13T-release-a
    _SL13T-corrupt-legacy-source
    _SL13T-activation-b

    _SL13M-case-finish
    _SL13T-stack
    _SL13T-fails @ _SL13M-fails @ OR IF
        ." STREAMS L13 RUNTIME FAIL "
        _SL13T-fails @ _SL13M-fails @ + .
        ." / "
        _SL13T-checks @ _SL13M-checks @ + . CR
    ELSE
        ." STREAMS L13 RUNTIME PASS "
        _SL13T-checks @ _SL13M-checks @ + . CR
    THEN ;
