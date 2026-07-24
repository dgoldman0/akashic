\ Focused, bounded RAM-VFS contracts for the L13 successful-apply authority.

PROVIDED akashic-streams-l13-apply-contracts

VARIABLE _SL13P-checks
VARIABLE _SL13P-fails
VARIABLE _SL13P-depth
VARIABLE _SL13P-arena
VARIABLE _SL13P-vfs
VARIABLE _SL13P-ior
VARIABLE _SL13P-old-vfs
VARIABLE _SL13P-fault-point
VARIABLE _SL13P-fault-fired
VARIABLE _SL13P-fault-require-terminal
VARIABLE _SL13P-next-sequence
VARIABLE _SL13P-cleanup-calls
VARIABLE _SL13P-revalidate-calls
VARIABLE _SL13P-callback-order-bad
VARIABLE _SL13P-cleanup-error
VARIABLE _SL13P-revalidate-allow
VARIABLE _SL13P-visible-generation
VARIABLE _SL13P-visible-observations
VARIABLE _SL13P-visible-natives
VARIABLE _SL13P-visible-active
VARIABLE _SL13P-visible-directory-rows
VARIABLE _SL13P-visible-attempt-rows
VARIABLE _SL13P-visible-identity-rows
VARIABLE _SL13P-visible-ordering-rows
VARIABLE _SL13P-request-candidates
VARIABLE _SL13P-request-count
VARIABLE _SL13P-begin-rid
VARIABLE _SL13P-begin-revision
VARIABLE _SL13P-begin-namespace
VARIABLE _SL13P-inspect-source
VARIABLE _SL13P-inspect-namespace
VARIABLE _SL13P-inspect-candidate
VARIABLE _SL13P-inspect-revision
VARIABLE _SL13P-cold-revision
VARIABLE _SL13P-cold-content-a
VARIABLE _SL13P-cold-content-u
VARIABLE _SL13P-sink-offset
VARIABLE _SL13P-sink-source
VARIABLE _SL13P-sink-u
VARIABLE _SL13P-sink-bytes
VARIABLE _SL13P-sink-error

CREATE _SL13P-ops VFS-OPS-SIZE ALLOT
CREATE _SL13P-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _SL13P-cache0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _SL13P-cache1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13P-cache0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _SL13P-cache1-memory
GUARD _SL13P-guard

STREAMS-REPOSITORY-SIZE XBUF _SL13P-repository
STREAMS-REPOSITORY-WORK-SIZE XBUF _SL13P-repo-work
STREAMS-REPOSITORY-RECORD-BUFFER-MIN XBUF _SL13P-record-buffer
STREAMS-SOURCE-AUTHORITY-WORK-SIZE XBUF _SL13P-source-work
STREAMS-ACQUISITION-WORK-SIZE XBUF _SL13P-acquisition-work
STREAMS-APPLY-WORK-SIZE XBUF _SL13P-apply-work

CREATE _SL13P-authority RID-SIZE ALLOT
CREATE _SL13P-source-a-rid RID-SIZE ALLOT
CREATE _SL13P-source-b-rid RID-SIZE ALLOT
CREATE _SL13P-namespace-a SHA3-256-LEN ALLOT
CREATE _SL13P-namespace-b SHA3-256-LEN ALLOT
CREATE _SL13P-component 8 ALLOT
CREATE _SL13P-digest SHA3-256-LEN ALLOT
CREATE _SL13P-key0 STREAMS-PI-KEY-MAX ALLOT
CREATE _SL13P-key1 STREAMS-PI-KEY-MAX ALLOT
CREATE _SL13P-key2 STREAMS-PI-KEY-MAX ALLOT
CREATE _SL13P-key3 STREAMS-PI-KEY-MAX ALLOT

STREAMS-SOURCE-SIZE XBUF _SL13P-source
STREAMS-ACQUISITION-BEGIN-REQUEST-SIZE XBUF _SL13P-begin-request
STREAMS-APPLY-REQUEST-SIZE XBUF _SL13P-apply-request
OCHK-SOURCE-SIZE XBUF _SL13P-accepted
OCHK-SOURCE-SIZE XBUF _SL13P-output
OCHK-CANDIDATE-SIZE OCHK-BATCH-MAX * XBUF _SL13P-candidates
SPREC-SOURCE-SIZE XBUF _SL13P-source-record
SPREC-NATIVE-HEAD-SIZE XBUF _SL13P-native-record
SPREC-OBSERVATION-SIZE XBUF _SL13P-observation-record
SPREC-OBSERVATION-SIZE XBUF _SL13P-readback-record
128 XBUF _SL13P-blob-buffer

: _SL13P-assert  ( flag -- )
    1 _SL13P-checks +!
    0= IF
        1 _SL13P-fails +!
        ." STREAMS L13 APPLY ASSERT " _SL13P-checks @ . CR
    THEN ;

: _SL13P-stack  ( -- )
    DEPTH DUP _SL13P-depth @ <> IF
        ." STREAMS L13 APPLY STACK "
        _SL13P-depth @ . ." -> " DUP . CR .S CR
    THEN
    _SL13P-depth @ = _SL13P-assert ;

: _SL13P-status  ( actual expected -- )
    2DUP <> IF
        ." STREAMS L13 APPLY STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _SL13P-assert _SL13P-stack ;

: _SL13P-fault  ( point ordinal context -- status )
    2DROP
    DUP _SL13P-fault-point @ =
    _SL13P-fault-point @ 0<> AND IF
        _SL13P-fault-require-terminal @ IF
            _SL13P-repo-work STREAMS-REPOSITORY-ADAPTER-WORK@
                STREAMS-PA-AUTHORITY-ROOT@
            DUP 0= IF
                DROP DROP PERSIST-S-OK EXIT
            THEN
            SAR.ACTIVE-COUNT @ IF
                DROP PERSIST-S-OK EXIT
            THEN
        THEN
        DROP
        0 _SL13P-fault-point !
        0 _SL13P-fault-require-terminal !
        1 _SL13P-fault-fired +!
        PERSIST-S-FAULT EXIT
    THEN
    DROP PERSIST-S-OK ;

: _SL13P-arm-fault  ( point -- )
    _SL13P-fault-point !
    0 _SL13P-fault-require-terminal !
    0 _SL13P-fault-fired ! ;

: _SL13P-arm-terminal-fault  ( point -- )
    _SL13P-arm-fault
    -1 _SL13P-fault-require-terminal ! ;

: _SL13P-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _SL13P-status ;

: _SL13P-adapter  ( -- adapter )
    _SL13P-repository STREAMS-REPOSITORY-ADAPTER@ ;

: _SL13P-adapter-work  ( -- work )
    _SL13P-repo-work STREAMS-REPOSITORY-ADAPTER-WORK@ ;

: _SL13P-root  ( -- root )
    _SL13P-repo-work STREAMS-REPOSITORY-AUTHORITY-ROOT@ ;

: _SL13P-tree-cardinality  ( tree -- count )
    _SL13P-repo-work STREAMS-REPOSITORY-TREE-ROOT@
    PBTREE-ROOT-CARDINALITY@ ;

: _SL13P-sentinel!  ( address length -- )
    0xA5 FILL ;

: _SL13P-sentinel?  ( address length -- flag )
    0 ?DO
        DUP I + C@ 0xA5 <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _SL13P-output-sentinel!  ( -- )
    _SL13P-output OCHK-SOURCE-SIZE _SL13P-sentinel! ;

: _SL13P-runtime-init  ( -- )
    VFS-CUR _SL13P-old-vfs !
    VFS-RAM-OPS _SL13P-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _SL13P-binding VFS-BINDING-DESC-SIZE MOVE
    _SL13P-ops _SL13P-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW
    DUP 0= _SL13P-assert DROP _SL13P-arena !
    _SL13P-arena @ _SL13P-binding 0 VFS-NEW
    _SL13P-ior ! _SL13P-vfs !
    _SL13P-ior @ 0= _SL13P-assert
    _SL13P-vfs @ 0<> _SL13P-assert
    _SL13P-cache0-memory _SL13P-cache0 _SL13P-cache-init
    _SL13P-cache1-memory _SL13P-cache1 _SL13P-cache-init
    _SL13P-authority RID-SIZE 0x41 FILL
    _SL13P-source-a-rid RID-SIZE 0x51 FILL
    _SL13P-source-b-rid RID-SIZE 0x52 FILL
    _SL13P-namespace-a SHA3-256-LEN 0x61 FILL
    _SL13P-namespace-b SHA3-256-LEN 0x62 FILL
    _SL13P-component 8 0x71 FILL
    0 _SL13P-fault-point !
    0 _SL13P-fault-fired !
    0 _SL13P-fault-require-terminal !
    0 _SL13P-next-sequence !
    _SL13P-stack ;

: _SL13P-repository-init  ( -- )
    _SL13P-vfs @ _SL13P-cache0 _SL13P-cache1 _SL13P-guard
    ['] _SL13P-fault 0 _SL13P-repository
        STREAMS-REPOSITORY-INIT
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-record-buffer STREAMS-REPOSITORY-RECORD-BUFFER-MIN
    _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WORK-INIT
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-repository STREAMS-REPOSITORY-VALID? _SL13P-assert
    _SL13P-repo-work STREAMS-REPOSITORY-WORK-VALID? _SL13P-assert
    _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WORK-BOUND? _SL13P-assert
    _SL13P-stack ;

: _SL13P-first-stage-owner  ( context repository repo-work -- status )
    2DROP DROP
    _SL13P-authority _SL13P-adapter _SL13P-adapter-work
        STREAMS-PA-FIRST-STAGE-BEGIN
        STREAMS-PA-S-OK _SL13P-status
    _SL13P-adapter-work STREAMS-PA-AUTHORITY-ROOT@
    DUP 0<> _SL13P-assert
    STREAMS-AUTHORITY-PROVENANCE-COMPLETE-EMPTY
        SWAP SAR.PROVENANCE !
    _SL13P-adapter _SL13P-adapter-work
        STREAMS-PA-FIRST-STAGE-COMMIT
        STREAMS-PA-S-OK _SL13P-status
    STREAMS-REPOSITORY-S-OK ;

: _SL13P-provision  ( -- )
    _SL13P-repository _SL13P-repo-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-ABSENT _SL13P-status
    _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-STAGING-PREPARE
        STREAMS-REPOSITORY-S-OK _SL13P-status
    0 ['] _SL13P-first-stage-owner
        _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WITH-STAGING-OWNER
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-repository _SL13P-repo-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-authority _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-PROVISION
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-root SAR.AUTHORITY-ID _SL13P-authority RID=
        _SL13P-assert
    _SL13P-stack ;

: _SL13P-work-init  ( -- )
    _SL13P-source-work STREAMS-SOURCE-AUTHORITY-WORK-INIT
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13P-status
    _SL13P-acquisition-work STREAMS-ACQUISITION-WORK-INIT
        STREAMS-ACQUISITION-S-OK _SL13P-status
    _SL13P-apply-work STREAMS-APPLY-WORK-INIT
        STREAMS-APPLY-S-OK _SL13P-status
    _SL13P-source-work STREAMS-SOURCE-AUTHORITY-WORK-VALID?
        _SL13P-assert
    _SL13P-acquisition-work STREAMS-ACQUISITION-WORK-VALID?
        _SL13P-assert
    _SL13P-apply-work STREAMS-APPLY-WORK-VALID? _SL13P-assert
    _SL13P-stack ;

: _SL13P-source-base  ( rid observation-max revision-max -- )
    >R >R
    _SL13P-source STREAMS-SOURCE-INIT
    _SL13P-source STREAMS-SOURCE-ID!
        SSREG-S-OK _SL13P-status
    R> _SL13P-source SSOURCE.OBSERVATION-MAX !
    R> _SL13P-source SSOURCE.REVISION-MAX !
    SSOURCE-KIND-SYNDICATION _SL13P-source SSOURCE.KIND !
    SSOURCE-FORMAT-JSON-FEED _SL13P-source SSOURCE.FORMAT ! ;

: _SL13P-create-sources  ( -- )
    _SL13P-source-a-rid 8 2 _SL13P-source-base
    S" Apply source A" _SL13P-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13P-status
    S" https://example.test/apply-a.json"
        _SL13P-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13P-status
    _SL13P-source _SL13P-repository _SL13P-repo-work
        _SL13P-source-work STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13P-status

    _SL13P-source-b-rid 2 4 _SL13P-source-base
    S" Apply source B" _SL13P-source STREAMS-SOURCE-LABEL!
        SSREG-S-OK _SL13P-status
    S" https://example.test/apply-b.json"
        _SL13P-source STREAMS-SOURCE-ENDPOINT!
        SSREG-S-OK _SL13P-status
    _SL13P-source _SL13P-repository _SL13P-repo-work
        _SL13P-source-work STREAMS-SOURCE-AUTHORITY-CREATE
        STREAMS-SOURCE-AUTHORITY-S-OK _SL13P-status
    _SL13P-root
    DUP SAR.SOURCE-COUNT @ 2 = _SL13P-assert
    DUP SAR.OBSERVATION-COUNT @ 0= _SL13P-assert
    DUP SAR.NATIVE-COUNT @ 0= _SL13P-assert
    SAR.ACTIVE-COUNT @ 0= _SL13P-assert
    _SL13P-stack ;

: _SL13P-candidate  ( index -- candidate )
    OCHK-CANDIDATE-SIZE * _SL13P-candidates + ;

: _SL13P-candidate-base  ( index -- candidate )
    _SL13P-candidate
    DUP OCHK-CANDIDATE-INIT
    SSOURCE-FORMAT-JSON-FEED OVER OCC.FORMAT !
    OCHK-NATIVE-PROVIDER-ID OVER OCC.NATIVE-KIND ! ;

: _SL13P-candidate-valid  ( candidate -- )
    SPREC-CANDIDATE-VALID? _SL13P-assert ;

: _SL13P-candidate-a-v1  ( -- )
    0 _SL13P-candidate-base >R
    S" item-a" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Item A version one" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" https://example.test/items/a"
        R@ OCC.URL-U ! R@ OCC.URL-A !
    S" summary-a-v1" R@ OCC.SUMMARY-U ! R@ OCC.SUMMARY-A !
    S" body-a-v1" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    S" 2026-07-24T12:00:00Z"
        R@ OCC.PUBLISHED-U ! R@ OCC.PUBLISHED-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidate-a-v2  ( -- )
    0 _SL13P-candidate-base >R
    S" item-a" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Item A version two" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" https://example.test/items/a"
        R@ OCC.URL-U ! R@ OCC.URL-A !
    S" summary-a-v2" R@ OCC.SUMMARY-U ! R@ OCC.SUMMARY-A !
    S" body-a-v2" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    S" 2026-07-24T12:00:00Z"
        R@ OCC.PUBLISHED-U ! R@ OCC.PUBLISHED-A !
    S" 2026-07-24T12:05:00Z"
        R@ OCC.MODIFIED-U ! R@ OCC.MODIFIED-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidate-a-v3  ( -- )
    0 _SL13P-candidate-base >R
    S" item-a" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Item A version three" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" https://example.test/items/a"
        R@ OCC.URL-U ! R@ OCC.URL-A !
    S" summary-a-v3" R@ OCC.SUMMARY-U ! R@ OCC.SUMMARY-A !
    S" body-a-v3" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    S" 2026-07-24T12:00:00Z"
        R@ OCC.PUBLISHED-U ! R@ OCC.PUBLISHED-A !
    S" 2026-07-24T12:10:00Z"
        R@ OCC.MODIFIED-U ! R@ OCC.MODIFIED-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidate-stale  ( -- )
    0 _SL13P-candidate-base >R
    S" stale-item" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Stale candidate" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" stale-body" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidates-duplicate  ( -- )
    0 _SL13P-candidate-base >R
    S" duplicate-item" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Duplicate candidate" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" duplicate-body" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> 1 _SL13P-candidate OCHK-CANDIDATE-SIZE MOVE
    1 _SL13P-candidate _SL13P-candidate-valid ;

: _SL13P-candidate-b1  ( -- )
    0 _SL13P-candidate-base >R
    S" item-b-1" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Item B one" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" body-b-1" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidate-b2  ( -- )
    0 _SL13P-candidate-base >R
    S" item-b-2" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Item B two" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" body-b-2" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidate-b3  ( -- )
    0 _SL13P-candidate-base >R
    S" item-b-3" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Item B capacity" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" body-b-3" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidate-stage-fail  ( -- )
    0 _SL13P-candidate-base >R
    S" stage-fail" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Staging retry" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" stage-retry-body" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidate-commit-fail  ( -- )
    0 _SL13P-candidate-base >R
    S" commit-fail" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Commit retry" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" commit-retry-body" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-candidates-batch  ( -- )
    0 _SL13P-candidate-base >R
    S" batch-x" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Batch X" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" batch-x-body" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP
    1 _SL13P-candidate-base >R
    S" batch-y" R@ OCC.NATIVE-U ! R@ OCC.NATIVE-A !
    S" Batch Y" R@ OCC.TITLE-U ! R@ OCC.TITLE-A !
    S" batch-y-body" R@ OCC.CONTENT-U ! R@ OCC.CONTENT-A !
    R@ _SL13P-candidate-valid
    R> DROP ;

: _SL13P-begin  ( source-rid source-revision namespace -- )
    _SL13P-begin-namespace !
    _SL13P-begin-revision !
    _SL13P-begin-rid !
    _SL13P-begin-request
        STREAMS-ACQUISITION-BEGIN-REQUEST-INIT
        STREAMS-ACQUISITION-S-OK _SL13P-status
    _SL13P-begin-rid @
        _SL13P-begin-request SABR.SOURCE-ID RID-COPY
    _SL13P-begin-revision @
        _SL13P-begin-request SABR.SOURCE-REVISION !
    _SL13P-begin-namespace @
        _SL13P-begin-request SABR.NAMESPACE RID-COPY
    OCHK-NATIVE-PROVIDER-ID
        _SL13P-begin-request SABR.PROVIDER-KIND !
    S" https://example.test/apply.json"
        _SL13P-begin-request SABR.REQUESTED-U !
        _SL13P-begin-request SABR.REQUESTED-A !
    _SL13P-begin-request
        STREAMS-ACQUISITION-BEGIN-REQUEST-VALID?
        _SL13P-assert
    _SL13P-begin-request _SL13P-accepted
        _SL13P-repository _SL13P-repo-work _SL13P-acquisition-work
        STREAMS-ACQUISITION-BEGIN
        STREAMS-ACQUISITION-S-OK _SL13P-status
    1 _SL13P-next-sequence +!
    _SL13P-accepted OCS.ATTEMPT-SEQUENCE @
        _SL13P-next-sequence @ = _SL13P-assert
    _SL13P-accepted OCS.STATE @
        OCHK-ATTEMPT-ACCEPTED = _SL13P-assert
    _SL13P-accepted OCS.SOURCE-ID
        _SL13P-begin-rid @ RID= _SL13P-assert
    _SL13P-accepted OCS.SOURCE-REVISION @
        _SL13P-begin-revision @ = _SL13P-assert
    _SL13P-root SAR.ACTIVE-COUNT @ 1 = _SL13P-assert
    _SL13P-stack ;

: _SL13P-note-visibility  ( -- )
    _SL13P-root
    DUP SAR.LOGICAL-GENERATION @
        _SL13P-visible-generation @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    DUP SAR.OBSERVATION-COUNT @
        _SL13P-visible-observations @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    DUP SAR.NATIVE-COUNT @
        _SL13P-visible-natives @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    SAR.ACTIVE-COUNT @
        _SL13P-visible-active @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    STREAMS-PI-TREE-DIRECTORY _SL13P-tree-cardinality
        _SL13P-visible-directory-rows @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    STREAMS-PI-TREE-ATTEMPTS _SL13P-tree-cardinality
        _SL13P-visible-attempt-rows @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    STREAMS-PI-TREE-IDENTITIES _SL13P-tree-cardinality
        _SL13P-visible-identity-rows @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    STREAMS-PI-TREE-ORDERINGS _SL13P-tree-cardinality
        _SL13P-visible-ordering-rows @ <> IF
        -1 _SL13P-callback-order-bad !
    THEN ;

: _SL13P-cleanup  ( context -- cleanup-error )
    DROP
    1 _SL13P-cleanup-calls +!
    _SL13P-note-visibility
    _SL13P-cleanup-error @ ;

: _SL13P-revalidate  ( frozen-request context -- exact? )
    2DROP
    _SL13P-cleanup-calls @ 1 <> IF
        -1 _SL13P-callback-order-bad !
    THEN
    1 _SL13P-revalidate-calls +!
    _SL13P-note-visibility
    _SL13P-revalidate-allow @ ;

: _SL13P-prepare-callbacks  ( exact? -- )
    _SL13P-revalidate-allow !
    0 _SL13P-cleanup-error !
    0 _SL13P-cleanup-calls !
    0 _SL13P-revalidate-calls !
    0 _SL13P-callback-order-bad !
    _SL13P-root
    DUP SAR.LOGICAL-GENERATION @ _SL13P-visible-generation !
    DUP SAR.OBSERVATION-COUNT @ _SL13P-visible-observations !
    DUP SAR.NATIVE-COUNT @ _SL13P-visible-natives !
    SAR.ACTIVE-COUNT @ _SL13P-visible-active !
    STREAMS-PI-TREE-DIRECTORY _SL13P-tree-cardinality
        _SL13P-visible-directory-rows !
    STREAMS-PI-TREE-ATTEMPTS _SL13P-tree-cardinality
        _SL13P-visible-attempt-rows !
    STREAMS-PI-TREE-IDENTITIES _SL13P-tree-cardinality
        _SL13P-visible-identity-rows !
    STREAMS-PI-TREE-ORDERINGS _SL13P-tree-cardinality
        _SL13P-visible-ordering-rows ! ;

: _SL13P-check-callbacks  ( cleanup-calls revalidate-calls -- )
    _SL13P-revalidate-calls @ = _SL13P-assert
    _SL13P-cleanup-calls @ = _SL13P-assert
    _SL13P-callback-order-bad @ 0= _SL13P-assert
    _SL13P-stack ;

: _SL13P-apply-request!  ( candidates count -- )
    _SL13P-request-count !
    _SL13P-request-candidates !
    _SL13P-apply-request STREAMS-APPLY-REQUEST-INIT
        STREAMS-APPLY-S-OK _SL13P-status
    _SL13P-accepted OCS.SOURCE-ID
        _SL13P-apply-request SAPAR.SOURCE-ID RID-COPY
    _SL13P-accepted OCS.SOURCE-REVISION @
        _SL13P-apply-request SAPAR.SOURCE-REVISION !
    _SL13P-accepted OCS.ATTEMPT-ID
        _SL13P-apply-request SAPAR.ATTEMPT-ID RID-COPY
    _SL13P-accepted OCS.REQUEST-SEAL
        _SL13P-apply-request SAPAR.REQUEST-SEAL RID-COPY
    _SL13P-component
        _SL13P-apply-request SAPAR.COMPONENT-INSTANCE !
    1 _SL13P-apply-request SAPAR.COMPONENT-GENERATION !
    _SL13P-next-sequence @
        _SL13P-apply-request SAPAR.REQUEST-GENERATION !
    S" https://example.test/effective.json"
        _SL13P-apply-request SAPAR.EFFECTIVE-U !
        _SL13P-apply-request SAPAR.EFFECTIVE-A !
    _SL13P-request-candidates @
        _SL13P-apply-request SAPAR.CANDIDATES-A !
    _SL13P-request-count @
        _SL13P-apply-request SAPAR.CANDIDATE-COUNT !
    MS@ _SL13P-accepted OCS.STARTED-MS @ MAX
        _SL13P-apply-request SAPAR.FINISHED-MS !
    0 _SL13P-apply-request SAPAR.DETAIL !
    200 _SL13P-apply-request SAPAR.HTTP-STATUS !
    0 _SL13P-apply-request SAPAR.DECODE-STATUS !
    ['] _SL13P-cleanup
        _SL13P-apply-request SAPAR.CLEANUP-XT !
    0 _SL13P-apply-request SAPAR.CLEANUP-CONTEXT !
    ['] _SL13P-revalidate
        _SL13P-apply-request SAPAR.REVALIDATE-XT !
    0 _SL13P-apply-request SAPAR.REVALIDATE-CONTEXT !
    _SL13P-apply-request STREAMS-APPLY-REQUEST-VALID?
        _SL13P-assert
    _SL13P-stack ;

: _SL13P-apply  ( -- status )
    _SL13P-apply-request _SL13P-output
    _SL13P-repository _SL13P-repo-work _SL13P-apply-work
        STREAMS-APPLY ;

: _SL13P-apply-status  ( expected -- )
    >R _SL13P-apply R> _SL13P-status ;

: _SL13P-terminal-success  ( new revised unchanged -- )
    >R >R >R
    _SL13P-output OCS.STATE @
        OCHK-ATTEMPT-SUCCEEDED = _SL13P-assert
    _SL13P-output OCS.OUTCOME @ OCHK-O-OK = _SL13P-assert
    _SL13P-output OCS.NEW-COUNT @ R> = _SL13P-assert
    _SL13P-output OCS.REVISED-COUNT @ R> = _SL13P-assert
    _SL13P-output OCS.UNCHANGED-COUNT @ R> = _SL13P-assert
    _SL13P-output OCS.ATTEMPT-SEQUENCE @
        _SL13P-next-sequence @ = _SL13P-assert
    _SL13P-stack ;

: _SL13P-terminal-failure  ( outcome -- )
    >R
    _SL13P-output OCS.STATE @
        OCHK-ATTEMPT-FAILED = _SL13P-assert
    _SL13P-output OCS.OUTCOME @ R> = _SL13P-assert
    _SL13P-output OCS.NEW-COUNT @ 0= _SL13P-assert
    _SL13P-output OCS.REVISED-COUNT @ 0= _SL13P-assert
    _SL13P-output OCS.UNCHANGED-COUNT @ 0= _SL13P-assert
    _SL13P-stack ;

: _SL13P-root-counts  ( observations natives active -- )
    >R >R >R
    _SL13P-root
    DUP SAR.OBSERVATION-COUNT @ R> = _SL13P-assert
    DUP SAR.NATIVE-COUNT @ R> = _SL13P-assert
    SAR.ACTIVE-COUNT @ R> = _SL13P-assert
    _SL13P-stack ;

: _SL13P-native-key!  ( source-rid namespace candidate -- )
    _SL13P-inspect-candidate !
    _SL13P-inspect-namespace !
    _SL13P-inspect-source !
    _SL13P-inspect-candidate @
    DUP OCC.NATIVE-A @ SWAP OCC.NATIVE-U @
        _SL13P-digest SHA3-256-HASH
    _SL13P-inspect-source @
    _SL13P-inspect-namespace @
    _SL13P-inspect-candidate @ OCC.FORMAT @
    _SL13P-inspect-candidate @ OCC.NATIVE-KIND @
    _SL13P-digest 1 _SL13P-key0
        STREAMS-PI-NATIVE-HEAD-KEY
        STREAMS-PI-S-OK _SL13P-status ;

: _SL13P-head-owner  ( context repository repo-work -- status )
    2DROP DROP
    _SL13P-inspect-source @
    _SL13P-inspect-namespace @
    _SL13P-inspect-candidate @ _SL13P-native-key!
    _SL13P-key0 STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        _SL13P-native-record SPREC-NATIVE-HEAD-SIZE
        _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    _SL13P-inspect-revision @ IF
        DUP STREAMS-PA-S-OK = _SL13P-assert
        SWAP SPREC-NATIVE-HEAD-SIZE = _SL13P-assert
        DROP
        _SL13P-native-record SPREC-NATIVE-HEAD-SIZE
            SPREC-NATIVE-VALID? _SL13P-assert
        _SL13P-native-record SPRH.LATEST-REVISION @
            _SL13P-inspect-revision @ = _SL13P-assert
    ELSE
        DUP STREAMS-PA-S-NOT-FOUND = _SL13P-assert
        SWAP 0= _SL13P-assert
        DROP
    THEN
    STREAMS-REPOSITORY-S-OK ;

: _SL13P-check-head  ( source-rid namespace candidate revision|0 -- )
    _SL13P-inspect-revision !
    _SL13P-inspect-candidate !
    _SL13P-inspect-namespace !
    _SL13P-inspect-source !
    0 ['] _SL13P-head-owner
        _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-stack ;

: _SL13P-source-count-owner  ( context repository repo-work -- status )
    2DROP DROP
    _SL13P-inspect-source @ _SL13P-key0
        STREAMS-PI-SOURCE-RID-KEY
        STREAMS-PI-S-OK _SL13P-status
    _SL13P-key0 STREAMS-PI-SOURCE-RID-KEY-SIZE
        _SL13P-source-record SPREC-SOURCE-SIZE
        _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13P-assert
    SWAP SPREC-SOURCE-SIZE = _SL13P-assert
    DROP
    _SL13P-source-record SPREC-SOURCE-SIZE
        SPREC-SOURCE-VALID? _SL13P-assert
    _SL13P-source-record SPRS.OBSERVATION-COUNT @
        _SL13P-inspect-revision @ = _SL13P-assert
    STREAMS-REPOSITORY-S-OK ;

: _SL13P-check-source-count  ( source-rid count -- )
    _SL13P-inspect-revision !
    _SL13P-inspect-source !
    0 ['] _SL13P-source-count-owner
        _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-stack ;

: _SL13P-contract-new-revised-unchanged  ( -- )
    _SL13P-candidate-a-v1
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-OK _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    1 0 0 _SL13P-terminal-success
    1 1 0 _SL13P-root-counts
    _SL13P-source-a-rid 1 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 1 _SL13P-check-head

    _SL13P-candidate-a-v2
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-OK _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    0 1 0 _SL13P-terminal-success
    2 1 0 _SL13P-root-counts
    _SL13P-source-a-rid 2 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 2 _SL13P-check-head

    _SL13P-candidate-a-v2
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-OK _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    0 0 1 _SL13P-terminal-success
    2 1 0 _SL13P-root-counts
    _SL13P-source-a-rid 2 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 2 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-contract-revision-capacity  ( -- )
    _SL13P-candidate-a-v3
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-CAPACITY _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    OCHK-O-CAPACITY _SL13P-terminal-failure
    2 1 0 _SL13P-root-counts
    _SL13P-source-a-rid 2 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 2 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-contract-stale-revalidation  ( -- )
    _SL13P-candidate-stale
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    0 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-STALE _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    OCHK-O-STALE _SL13P-terminal-failure
    2 1 0 _SL13P-root-counts
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 0 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-contract-duplicate  ( -- )
    _SL13P-candidates-duplicate
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 2 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-DUPLICATE _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    OCHK-O-DECODE _SL13P-terminal-failure
    2 1 0 _SL13P-root-counts
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 0 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-contract-observation-capacity  ( -- )
    _SL13P-candidate-b1
    _SL13P-source-b-rid 1 _SL13P-namespace-b _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-OK _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    1 0 0 _SL13P-terminal-success
    3 2 0 _SL13P-root-counts

    _SL13P-candidate-b2
    _SL13P-source-b-rid 1 _SL13P-namespace-b _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-OK _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    1 0 0 _SL13P-terminal-success
    4 3 0 _SL13P-root-counts
    _SL13P-source-b-rid 2 _SL13P-check-source-count

    _SL13P-candidate-b3
    _SL13P-source-b-rid 1 _SL13P-namespace-b _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-CAPACITY _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    OCHK-O-CAPACITY _SL13P-terminal-failure
    4 3 0 _SL13P-root-counts
    _SL13P-source-b-rid 2 _SL13P-check-source-count
    _SL13P-source-b-rid _SL13P-namespace-b
        0 _SL13P-candidate 0 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-contract-staging-failure  ( -- )
    _SL13P-candidate-stage-fail
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    _SL13P-output-sentinel!
    PERSIST-FAULT-SEGMENT-WRITTEN _SL13P-arm-fault
    STREAMS-APPLY-S-FAULT _SL13P-apply-status
    _SL13P-apply-work STREAMS-APPLY-WORK-VALID? _SL13P-assert
    _SL13P-fault-fired @ 1 = _SL13P-assert
    _SL13P-output OCHK-SOURCE-SIZE
        _SL13P-sentinel? _SL13P-assert
    0 0 _SL13P-check-callbacks
    4 3 1 _SL13P-root-counts
    _SL13P-source-a-rid 2 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 0 _SL13P-check-head

    -1 _SL13P-prepare-callbacks
    _SL13P-output-sentinel!
    STREAMS-APPLY-S-OK _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    1 0 0 _SL13P-terminal-success
    5 4 0 _SL13P-root-counts
    _SL13P-source-a-rid 3 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 1 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-cold-reopen  ( -- )
    _SL13P-repository _SL13P-repo-work STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-cache0-memory _SL13P-cache0 _SL13P-cache-init
    _SL13P-cache1-memory _SL13P-cache1 _SL13P-cache-init
    _SL13P-repository-init
    _SL13P-repository _SL13P-repo-work STREAMS-REPOSITORY-LOAD
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-root SAR.AUTHORITY-ID _SL13P-authority RID=
        _SL13P-assert
    _SL13P-work-init
    _SL13P-stack ;

: _SL13P-contract-commit-failure  ( -- )
    _SL13P-candidate-commit-fail
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 1 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    _SL13P-output-sentinel!
    PERSIST-FAULT-ROOT-WRITTEN _SL13P-arm-terminal-fault
    STREAMS-APPLY-S-UNCERTAIN _SL13P-apply-status
    _SL13P-fault-fired @ 1 = _SL13P-assert
    _SL13P-output OCHK-SOURCE-SIZE
        _SL13P-sentinel? _SL13P-assert
    1 1 _SL13P-check-callbacks
    \ ROOT-WRITTEN is deliberately an uncertain publication boundary.
    \ PSTORE keeps that uncertainty sticky within the descriptor, so recreate
    \ the repository/work graph before selecting either the old complete root
    \ or the new complete root.  Retry only when the exact ACCEPTED attempt
    \ remains authoritative.
    _SL13P-cold-reopen
    _SL13P-root SAR.ACTIVE-COUNT @ IF
        5 4 1 _SL13P-root-counts
        _SL13P-source-a-rid 3 _SL13P-check-source-count
        _SL13P-source-a-rid _SL13P-namespace-a
            0 _SL13P-candidate 0 _SL13P-check-head
        \ Cleanup has already consumed the first decoded batch.  Model a
        \ fresh decode/request around the still-authoritative attempt.
        _SL13P-candidate-commit-fail
        0 _SL13P-candidate 1 _SL13P-apply-request!
        -1 _SL13P-prepare-callbacks
        _SL13P-output-sentinel!
        STREAMS-APPLY-S-OK _SL13P-apply-status
        1 1 _SL13P-check-callbacks
        1 0 0 _SL13P-terminal-success
    ELSE
        6 5 0 _SL13P-root-counts
        _SL13P-source-a-rid 4 _SL13P-check-source-count
        _SL13P-source-a-rid _SL13P-namespace-a
            0 _SL13P-candidate 1 _SL13P-check-head
    THEN
    6 5 0 _SL13P-root-counts
    _SL13P-source-a-rid 4 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 1 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-contract-whole-batch  ( -- )
    _SL13P-candidates-batch
    _SL13P-source-a-rid 1 _SL13P-namespace-a _SL13P-begin
    0 _SL13P-candidate 2 _SL13P-apply-request!
    -1 _SL13P-prepare-callbacks
    STREAMS-APPLY-S-OK _SL13P-apply-status
    1 1 _SL13P-check-callbacks
    2 0 0 _SL13P-terminal-success
    8 7 0 _SL13P-root-counts
    _SL13P-source-a-rid 6 _SL13P-check-source-count
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate 1 _SL13P-check-head
    _SL13P-source-a-rid _SL13P-namespace-a
        1 _SL13P-candidate 1 _SL13P-check-head
    _SL13P-stack ;

: _SL13P-blob-sink
  ( logical-offset source-a offered-u context -- status )
    DROP
    _SL13P-sink-u !
    _SL13P-sink-source !
    _SL13P-sink-offset !
    _SL13P-sink-offset @ _SL13P-sink-bytes @ <> IF
        -1 _SL13P-sink-error !
        PERSIST-S-CORRUPT EXIT
    THEN
    _SL13P-sink-offset @ _SL13P-sink-u @ +
        128 > IF
        -1 _SL13P-sink-error !
        PERSIST-S-CAPACITY EXIT
    THEN
    _SL13P-sink-source @
    _SL13P-blob-buffer _SL13P-sink-offset @ +
    _SL13P-sink-u @ MOVE
    _SL13P-sink-u @ _SL13P-sink-bytes +!
    PERSIST-S-OK ;

: _SL13P-cold-observation  ( revision content-a content-u -- )
    _SL13P-cold-content-u !
    _SL13P-cold-content-a !
    _SL13P-cold-revision !
    _SL13P-native-record SPRH.OBSERVATION-ID
    _SL13P-cold-revision @ _SL13P-key1
        STREAMS-PI-OBSERVATION-REVISION-KEY
        STREAMS-PI-S-OK _SL13P-status
    _SL13P-key1 STREAMS-PI-OBSERVATION-REVISION-KEY-SIZE
        _SL13P-observation-record SPREC-OBSERVATION-SIZE
        _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13P-assert
    SWAP SPREC-OBSERVATION-SIZE = _SL13P-assert
    DROP
    _SL13P-observation-record SPREC-OBSERVATION-SIZE
        SPREC-OBSERVATION-VALID? _SL13P-assert
    _SL13P-observation-record SPRO.REVISION @
        _SL13P-cold-revision @ = _SL13P-assert
    _SL13P-observation-record SPRO.SOURCE-ID
        _SL13P-source-a-rid RID= _SL13P-assert
    _SL13P-observation-record SPRO.CONTENT-U @
        _SL13P-cold-content-u @ = _SL13P-assert

    _SL13P-observation-record SPRO.ACQUISITION-SEQUENCE @
    _SL13P-observation-record SPRO.OBSERVATION-ID
    _SL13P-observation-record SPRO.REVISION @
    _SL13P-key2 STREAMS-PI-GLOBAL-TIME-KEY
        STREAMS-PI-S-OK _SL13P-status
    _SL13P-key2 STREAMS-PI-GLOBAL-TIME-KEY-SIZE
        _SL13P-readback-record SPREC-OBSERVATION-SIZE
        _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13P-assert
    SWAP SPREC-OBSERVATION-SIZE = _SL13P-assert
    DROP
    _SL13P-observation-record SPREC-OBSERVATION-SIZE
    _SL13P-readback-record SPREC-OBSERVATION-SIZE
        COMPARE 0= _SL13P-assert

    _SL13P-observation-record SPRO.SOURCE-ID
    _SL13P-observation-record SPRO.ACQUISITION-SEQUENCE @
    _SL13P-observation-record SPRO.OBSERVATION-ID
    _SL13P-observation-record SPRO.REVISION @
    _SL13P-key3 STREAMS-PI-SOURCE-TIME-KEY
        STREAMS-PI-S-OK _SL13P-status
    _SL13P-key3 STREAMS-PI-SOURCE-TIME-KEY-SIZE
        _SL13P-readback-record SPREC-OBSERVATION-SIZE
        _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13P-assert
    SWAP SPREC-OBSERVATION-SIZE = _SL13P-assert
    DROP
    _SL13P-observation-record SPREC-OBSERVATION-SIZE
    _SL13P-readback-record SPREC-OBSERVATION-SIZE
        COMPARE 0= _SL13P-assert

    _SL13P-blob-buffer 128 0 FILL
    0 _SL13P-sink-bytes !
    0 _SL13P-sink-error !
    _SL13P-observation-record SPRO.CONTENT
    0 _SL13P-cold-content-u @
    ['] _SL13P-blob-sink 0
    _SL13P-adapter _SL13P-adapter-work
        STREAMS-PA-BLOB-READ-RANGE
        STREAMS-PA-S-OK _SL13P-status
    _SL13P-sink-error @ 0= _SL13P-assert
    _SL13P-sink-bytes @ _SL13P-cold-content-u @ =
        _SL13P-assert
    _SL13P-blob-buffer _SL13P-cold-content-u @
    _SL13P-cold-content-a @ _SL13P-cold-content-u @
        COMPARE 0= _SL13P-assert ;

: _SL13P-cold-owner  ( context repository repo-work -- status )
    2DROP DROP
    _SL13P-candidate-a-v2
    _SL13P-source-a-rid _SL13P-namespace-a
        0 _SL13P-candidate _SL13P-native-key!
    _SL13P-key0 STREAMS-PI-NATIVE-HEAD-KEY-SIZE
        _SL13P-native-record SPREC-NATIVE-HEAD-SIZE
        _SL13P-adapter _SL13P-adapter-work STREAMS-PA-GET
    DUP STREAMS-PA-S-OK = _SL13P-assert
    SWAP SPREC-NATIVE-HEAD-SIZE = _SL13P-assert
    DROP
    _SL13P-native-record SPREC-NATIVE-HEAD-SIZE
        SPREC-NATIVE-VALID? _SL13P-assert
    _SL13P-native-record SPRH.LATEST-REVISION @ 2 =
        _SL13P-assert
    _SL13P-native-record SPRH.LAST-SEEN-SEQUENCE @ 3 =
        _SL13P-assert
    1 S" body-a-v1" _SL13P-cold-observation
    2 S" body-a-v2" _SL13P-cold-observation
    STREAMS-REPOSITORY-S-OK ;

: _SL13P-contract-cold-exact  ( -- )
    _SL13P-cold-reopen
    _SL13P-root
    DUP SAR.LOGICAL-GENERATION @ 26 = _SL13P-assert
    DUP SAR.ACQUISITION-SEQUENCE @ 12 = _SL13P-assert
    DUP SAR.SOURCE-COUNT @ 2 = _SL13P-assert
    DUP SAR.ATTEMPT-COUNT @ 12 = _SL13P-assert
    DUP SAR.OBSERVATION-COUNT @ 8 = _SL13P-assert
    DUP SAR.NATIVE-COUNT @ 7 = _SL13P-assert
    SAR.ACTIVE-COUNT @ 0= _SL13P-assert
    STREAMS-PI-TREE-DIRECTORY _SL13P-repo-work
        STREAMS-REPOSITORY-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 4 = _SL13P-assert
    STREAMS-PI-TREE-ATTEMPTS _SL13P-repo-work
        STREAMS-REPOSITORY-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 12 = _SL13P-assert
    STREAMS-PI-TREE-IDENTITIES _SL13P-repo-work
        STREAMS-REPOSITORY-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 15 = _SL13P-assert
    STREAMS-PI-TREE-ORDERINGS _SL13P-repo-work
        STREAMS-REPOSITORY-TREE-ROOT@
        PBTREE-ROOT-CARDINALITY@ 16 = _SL13P-assert
    _SL13P-source-a-rid 6 _SL13P-check-source-count
    _SL13P-source-b-rid 2 _SL13P-check-source-count
    0 ['] _SL13P-cold-owner
        _SL13P-repository _SL13P-repo-work
        STREAMS-REPOSITORY-WITH-OWNER
        STREAMS-REPOSITORY-S-OK _SL13P-status
    _SL13P-stack ;

: _SL13P-finish  ( -- )
    _SL13P-repository _SL13P-repo-work STREAMS-REPOSITORY-FINI
        STREAMS-REPOSITORY-S-OK _SL13P-status
    0 _SL13P-vfs @ VFS-UNMOUNT 0= _SL13P-assert
    _SL13P-vfs @ VFS-DESTROY
    _SL13P-old-vfs @ VFS-USE
    _SL13P-arena @ ARENA-DESTROY
    _SL13P-stack ;

: _SL13P-RUN  ( -- )
    0 _SL13P-checks ! 0 _SL13P-fails !
    DEPTH _SL13P-depth !
    _SL13P-runtime-init
    _SL13P-repository-init
    _SL13P-provision
    _SL13P-work-init
    _SL13P-create-sources
    _SL13P-contract-new-revised-unchanged
    _SL13P-contract-revision-capacity
    _SL13P-contract-stale-revalidation
    _SL13P-contract-duplicate
    _SL13P-contract-observation-capacity
    _SL13P-contract-staging-failure
    _SL13P-contract-commit-failure
    _SL13P-contract-whole-batch
    _SL13P-contract-cold-exact
    _SL13P-finish
    _SL13P-fails @ IF
        ." STREAMS L13 APPLY FAIL "
            _SL13P-fails @ . ." / " _SL13P-checks @ . CR
    ELSE
        ." STREAMS L13 APPLY PASS "
            _SL13P-checks @ . CR
    THEN ;
