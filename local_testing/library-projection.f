\ =====================================================================
\  Gate 4 milestone 4: bounded Library projection-owner contract fixture
\ =====================================================================

VARIABLE _lpo-fails
VARIABLE _lpo-checks
VARIABLE _lpo-depth
VARIABLE _lpo-vfs
VARIABLE _lpo-other-vfs
VARIABLE _lpo-old-vfs
VARIABLE _lpo-arena
VARIABLE _lpo-other-arena
VARIABLE _lpo-ior
VARIABLE _lpo-context
VARIABLE _lpo-cold-context
VARIABLE _lpo-creg
VARIABLE _lpo-rreg
VARIABLE _lpo-bus
VARIABLE _lpo-request
VARIABLE _lpo-expected-status
VARIABLE _lpo-required
VARIABLE _lpo-before
VARIABLE _lpo-instance
VARIABLE _lpo-text-a
VARIABLE _lpo-text-u
VARIABLE _lpo-index
VARIABLE _lpo-target
VARIABLE _lpo-data-a
VARIABLE _lpo-data-u
VARIABLE _lpo-compact-steps

PHEAD-SIZE XBUF _lpo-head
LIB-DIGEST-SIZE XBUF _lpo-arena-id
LIB-OPERATION-KEY-SIZE XBUF _lpo-key
LIB-DIGEST-SIZE 11 * XBUF _lpo-rids
LIB-DIGEST-SIZE XBUF _lpo-unknown-rid

CREATE _lpo-vfs-ops VFS-OPS-SIZE ALLOT
CREATE _lpo-vfs-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _lpo-cache-0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _lpo-cache-1 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _lpo-builder-cache-0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _lpo-builder-cache-1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _lpo-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _lpo-cache-1-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _lpo-builder-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _lpo-builder-cache-1-memory
GUARD _lpo-repository-guard
GUARD _lpo-builder-guard

LIBRARY-REPOSITORY-SIZE XBUF _lpo-repository
LIBRARY-REPOSITORY-WORK-SIZE XBUF _lpo-repository-work
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _lpo-record-buffer
LIBRARY-REPOSITORY-STAGE-BUFFER-MIN XBUF _lpo-stage-buffer
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _lpo-builder-record-buffer
512 XBUF _lpo-compact-buffer
LIBRARY-SERVICE-SIZE XBUF _lpo-service
LIBRARY-SERVICE-WORK-SIZE XBUF _lpo-service-work

LIBRARY-DOCUMENT-INITIAL-DRAFT-SIZE XBUF _lpo-draft
LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE XBUF _lpo-create-request
LIBRARY-DOCUMENT-READ-REQUEST-SIZE XBUF _lpo-read-request
LIBRARY-DOCUMENT-REPLACE-REQUEST-SIZE XBUF _lpo-replace-request
LIBRARY-COMPACTION-BIND-REQUEST-SIZE XBUF _lpo-compaction-request
LIBRARY-SERVICE-CONTENT-DESCRIPTOR-SIZE XBUF _lpo-descriptor
LIB-ORIGIN-SIZE XBUF _lpo-origin
LIB-METADATA-FACT-HEADER-SIZE LIB-ORIGIN-SIZE +
    CONSTANT _LPO-CAPTURE-FACTS-U
_LPO-CAPTURE-FACTS-U XBUF _lpo-capture-facts
LIB-ENTRY-SIZE XBUF _lpo-entry
LIB-ENTRY-SIZE XBUF _lpo-capture-entry
LIB-ENTRY-SIZE XBUF _lpo-next-entry
LIB-ENTRY-SIZE XBUF _lpo-result-entry
LIB-CONTENT-SIZE XBUF _lpo-create-content
LIB-CONTENT-SIZE XBUF _lpo-next-content
16 XBUF _lpo-content
8 XBUF _lpo-prune-content
70000 CONSTANT _LPO-LARGE-CONTENT-U
VARIABLE _lpo-large-content
RREF-SIZE XBUF _lpo-ref
QLOC-SIZE XBUF _lpo-loc-a
QLOC-SIZE XBUF _lpo-loc-b
QLOC-SIZE XBUF _lpo-loc-c
LIB-DIGEST-SIZE XBUF _lpo-digest-a
LIB-DIGEST-SIZE XBUF _lpo-digest-b
LIBRARY-PROJECTION-ROOT-SIZE XBUF _lpo-root
LBIND-SIZE XBUF _lpo-bind-a
LBIND-SIZE XBUF _lpo-bind-b
LBIND-SIZE XBUF _lpo-bind-fail
RACQ-RESULT-SIZE XBUF _lpo-result-a
RACQ-RESULT-SIZE XBUF _lpo-result-b
RACQ-RESULT-SIZE XBUF _lpo-result-fail
RACQ-TOKEN-SIZE XBUF _lpo-token-copy
RCLI-SIZE XBUF _lpo-client
LBIND-SIZE LIBRARY-PROJECTION-LEASE-MAX 1+ *
    CONSTANT _LPO-CAP-BINDS-SIZE
RACQ-RESULT-SIZE LIBRARY-PROJECTION-LEASE-MAX 1+ *
    CONSTANT _LPO-CAP-RESULTS-SIZE
VARIABLE _lpo-cap-binds
VARIABLE _lpo-cap-results
LIB-PROJECTION-MAX 8 * XBUF _lpo-cap-instances
CREATE _lpo-cap-rid-map
    0 , 3 , 4 , 5 , 6 , 7 , 8 , 9 ,

: _lpo-rid  ( index -- rid ) LIB-DIGEST-SIZE * _lpo-rids + ;
: _lpo-cap-bind  ( index -- bind ) LBIND-SIZE * _lpo-cap-binds @ + ;
: _lpo-cap-result  ( index -- result )
    RACQ-RESULT-SIZE * _lpo-cap-results @ + ;
: _lpo-cap-rid  ( index -- rid )
    8 * _lpo-cap-rid-map + @ _lpo-rid ;

: _lpo-assert  ( flag -- )
    1 _lpo-checks +!
    0= IF
        1 _lpo-fails +!
        ." LIBRARY PROJECTION OWNER ASSERT " _lpo-checks @ . CR
    THEN ;

: _lpo-stack  ( -- )
    DEPTH DUP _lpo-depth @ <> IF
        ." LIBRARY PROJECTION OWNER STACK "
        _lpo-depth @ . ."  -> " DUP . CR .S CR
    THEN
    _lpo-depth @ = _lpo-assert ;

: _lpo-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY PROJECTION OWNER STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _lpo-assert ;

: _lpo-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _lpo-id!  ( value id -- ) DUP RID-CLEAR ! ;

: _lpo-identity-loc!  ( rid locator -- status )
    >R
    _lpo-ref RREF-INIT
    _lpo-ref RREF.ID RID-COPY
    LIBRARY-PROJECTION-OWNER$ _lpo-ref R> QLOC-IDENTITY! ;

VARIABLE _lpo-exact-rid
VARIABLE _lpo-exact-revision
VARIABLE _lpo-exact-digest
VARIABLE _lpo-exact-locator

: _lpo-exact-loc!  ( rid revision digest locator -- status )
    _lpo-exact-locator ! _lpo-exact-digest !
    _lpo-exact-revision ! _lpo-exact-rid !
    _lpo-ref RREF-INIT
    _lpo-exact-rid @ _lpo-ref RREF.ID RID-COPY
    LIBRARY-PROJECTION-OWNER$ _lpo-ref
        _lpo-exact-revision @ _lpo-exact-digest @
        QLOC-DK-PROJECTION-CONTENT LIBRARY-PROJECTION-CONTRACT$
        _lpo-exact-locator @ QLOC-EXACT! ;

: _lpo-attach  ( locator binding result -- status )
    >R >R
    _lpo-root _lpo-context @ _lpo-rreg @
    R> R> LIBRARY-PROJECTION-ATTACH ;

: _lpo-cold-attach  ( locator binding result -- status )
    >R >R
    _lpo-root _lpo-cold-context @ _lpo-rreg @
    R> R> LIBRARY-PROJECTION-ATTACH ;

: _lpo-result-content?  ( expected-a expected-u -- flag )
    _lpo-text-u ! _lpo-text-a !
    S" content" _lpo-request @ CBR.RESULT CV-MAP-FIND DUP 0= IF
        DROP 0 EXIT
    THEN
    DUP CV-DATA@ SWAP CV-LEN@
    _lpo-text-a @ _lpo-text-u @ STR-STR= ;

: _lpo-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        LIBRARY-REPOSITORY-S-OK _lpo-status ;

: _lpo-create-request!  ( -- )
    _lpo-create-request LIBRARY-DOCUMENT-CREATE-REQUEST-INIT
    _lpo-entry _lpo-create-request LSDCR.ENTRY !
    _lpo-create-content _lpo-create-request LSDCR.CONTENT !
    _lpo-draft LSDID.FACTS-A @ _lpo-create-request LSDCR.FACTS-A !
    _lpo-draft LSDID.FACTS-U @ _lpo-create-request LSDCR.FACTS-U !
    _lpo-service-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _lpo-create-request LSDCR.EXPECTED-LOGICAL !
    _lpo-result-entry _lpo-create-request LSDCR.RESULT !
    _lpo-create-request
        LIBRARY-DOCUMENT-CREATE-REQUEST-VALID? _lpo-assert ;

: _lpo-create-document  ( index -- )
    _lpo-index !
    S" managed-0" _lpo-content SWAP CMOVE
    [CHAR] 0 _lpo-index @ + _lpo-content 8 + C!
    _lpo-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _lpo-draft LSDID.ID RID-CLEAR
    _lpo-index @ 1+ _lpo-draft LSDID.ID !
    _lpo-draft LSDID.OPERATION-KEY RID-CLEAR
    _lpo-index @ 101 + _lpo-draft LSDID.OPERATION-KEY !
    LIB-KIND-MANAGED-DOCUMENT _lpo-draft LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN _lpo-draft LSDID.MEDIA !
    _lpo-service-work LIBRARY-SERVICE-NEXT-MUTATION@
        _lpo-draft LSDID.MUTATION-SEQUENCE !
    _lpo-content _lpo-draft LSDID.CONTENT-A !
    9 _lpo-draft LSDID.CONTENT-U !
    S" Projection fixture"
        DUP _lpo-draft LSDID.TITLE-U !
        _lpo-draft LSDID.TITLE SWAP CMOVE
    _lpo-draft _lpo-entry _lpo-create-content
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-create-request!
    _lpo-create-request _lpo-service _lpo-service-work
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-result-entry LIB-ENTRY-VALID? _lpo-assert
    _lpo-result-entry LIBE.ID _lpo-index @ _lpo-rid RID-COPY
    _lpo-index @ _lpo-rid RID-PRESENT? _lpo-assert
    _lpo-result-entry LIBE.KIND @
        LIB-KIND-MANAGED-DOCUMENT = _lpo-assert
    _lpo-stack ;

: _lpo-create-documents-first  ( -- )
    3 0 ?DO
        I _lpo-create-document
    LOOP
    _lpo-stack ;

: _lpo-create-documents-rest  ( -- )
    9 4 ?DO
        I _lpo-create-document
    LOOP
    9 0 ?DO
        I 0 ?DO
            I _lpo-rid J _lpo-rid RID= 0= _lpo-assert
        LOOP
    LOOP
    _lpo-stack ;

: _lpo-build-origin  ( -- )
    _lpo-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _lpo-origin LIBO.KIND !
    S" /imports/projection-capture.txt"
        DUP _lpo-origin LIBO.VFS LIBV.PATH-U !
        _lpo-origin LIBO.VFS LIBV.PATH SWAP CMOVE
    S" capture bytes"
        DUP _lpo-origin LIBO.VFS LIBV.CONTENT-U !
        _lpo-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    QLOC-DK-PROJECTION-CONTENT
        _lpo-origin LIBO.VFS LIBV.DIGEST-KIND !
    _lpo-origin LIB-ORIGIN-VALID? _lpo-assert ;

: _lpo-create-capture  ( -- )
    _lpo-build-origin
    _lpo-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _lpo-draft LSDID.ID RID-CLEAR
    10 _lpo-draft LSDID.ID !
    _lpo-draft LSDID.OPERATION-KEY RID-CLEAR
    110 _lpo-draft LSDID.OPERATION-KEY !
    LIB-KIND-CAPTURE _lpo-draft LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN _lpo-draft LSDID.MEDIA !
    _lpo-service-work LIBRARY-SERVICE-NEXT-MUTATION@
        _lpo-draft LSDID.MUTATION-SEQUENCE !
    S" capture bytes"
        DUP _lpo-draft LSDID.CONTENT-U !
        OVER _lpo-draft LSDID.CONTENT-A !
        2DROP
    S" Projection capture"
        DUP _lpo-draft LSDID.TITLE-U !
        _lpo-draft LSDID.TITLE SWAP CMOVE
    _lpo-capture-facts _LPO-CAPTURE-FACTS-U 0 FILL
    LIB-METADATA-FACT-ORIGIN _lpo-capture-facts LIBMF.KIND !
    LIB-ORIGIN-SIZE _lpo-capture-facts LIBMF.PAYLOAD-U !
    _lpo-origin _lpo-capture-facts LIBMF.PAYLOAD
        LIB-ORIGIN-SIZE MOVE
    _lpo-capture-facts _LPO-CAPTURE-FACTS-U _lpo-draft
        LIBRARY-DOCUMENT-INITIAL-DRAFT-FACTS!
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-draft _lpo-entry _lpo-create-content
        LIBRARY-SERVICE-PREPARE-CAPTURE-IMPORT
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-create-request!
    _lpo-create-request _lpo-service _lpo-service-work
        LIBRARY-SERVICE-IMPORT-CAPTURE
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-result-entry _lpo-capture-entry LIB-ENTRY-SIZE MOVE
    _lpo-result-entry LIBE.ID 9 _lpo-rid RID-COPY
    _lpo-capture-entry LIBE.KIND @ LIB-KIND-CAPTURE = _lpo-assert
    9 _lpo-rid RID-PRESENT? _lpo-assert
    _lpo-stack ;

: _lpo-create-large  ( -- )
    _lpo-large-content @ _LPO-LARGE-CONTENT-U [CHAR] L FILL
    _lpo-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _lpo-draft LSDID.ID RID-CLEAR
    11 _lpo-draft LSDID.ID !
    _lpo-draft LSDID.OPERATION-KEY RID-CLEAR
    111 _lpo-draft LSDID.OPERATION-KEY !
    LIB-KIND-MANAGED-DOCUMENT _lpo-draft LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN _lpo-draft LSDID.MEDIA !
    _lpo-service-work LIBRARY-SERVICE-NEXT-MUTATION@
        _lpo-draft LSDID.MUTATION-SEQUENCE !
    _lpo-large-content @ _lpo-draft LSDID.CONTENT-A !
    _LPO-LARGE-CONTENT-U _lpo-draft LSDID.CONTENT-U !
    S" Large projection"
        DUP _lpo-draft LSDID.TITLE-U !
        _lpo-draft LSDID.TITLE SWAP CMOVE
    _lpo-draft _lpo-entry _lpo-create-content
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-create-request!
    _lpo-create-request _lpo-service _lpo-service-work
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-result-entry LIBE.ID 10 _lpo-rid RID-COPY
    _lpo-result-entry LIBE.CONTENT-U @
        _LPO-LARGE-CONTENT-U = _lpo-assert
    _lpo-stack ;

: _lpo-read-identity  ( index -- status )
    _lpo-read-request LIBRARY-DOCUMENT-READ-REQUEST-INIT
    _lpo-rid _lpo-read-request LSDQR.RID RID-COPY
    _lpo-entry _lpo-read-request LSDQR.ENTRY !
    _lpo-descriptor _lpo-read-request LSDQR.DESCRIPTOR !
    _lpo-read-request _lpo-service _lpo-service-work
        LIBRARY-SERVICE-READ-CURRENT ;

: _lpo-replace-finish  ( content|0 service-xt -- status )
    >R
    _lpo-replace-request LIBRARY-DOCUMENT-REPLACE-REQUEST-INIT
    _lpo-next-entry _lpo-replace-request LSDRR.NEXT !
    _lpo-replace-request LSDRR.CONTENT !
    _lpo-service-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _lpo-replace-request LSDRR.EXPECTED-LOGICAL !
    _lpo-entry LIBE.DOMAIN-REVISION @
        _lpo-replace-request LSDRR.EXPECTED-DOMAIN !
    _lpo-result-entry _lpo-replace-request LSDRR.RESULT !
    _lpo-replace-request _lpo-service _lpo-service-work R> EXECUTE
    DUP IF EXIT THEN DROP
    _lpo-result-entry _lpo-entry LIB-ENTRY-SIZE MOVE
    LIBRARY-SERVICE-S-OK ;

: _lpo-lifecycle!  ( index lifecycle -- status )
    _lpo-target ! _lpo-index !
    _lpo-index @ _lpo-read-identity DUP IF EXIT THEN DROP
    _lpo-entry _lpo-target @
    _lpo-service-work LIBRARY-SERVICE-NEXT-MUTATION@
    _lpo-next-entry LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
    DUP IF EXIT THEN DROP
    0 ['] LIBRARY-SERVICE-REPLACE-LIFECYCLE _lpo-replace-finish ;

: _lpo-content!  ( index data-a data-u -- status )
    _lpo-data-u ! _lpo-data-a ! _lpo-index !
    _lpo-index @ _lpo-read-identity DUP IF EXIT THEN DROP
    _lpo-entry _lpo-data-a @ _lpo-data-u @
    _lpo-service-work LIBRARY-SERVICE-NEXT-MUTATION@
    _lpo-next-entry _lpo-next-content
        LIBRARY-SERVICE-PREPARE-CONTENT-NEXT
    DUP IF EXIT THEN DROP
    _lpo-next-content ['] LIBRARY-SERVICE-REPLACE-CONTENT
        _lpo-replace-finish ;

: _lpo-tombstone!  ( index -- status )
    DUP _lpo-index !
    _lpo-read-identity DUP IF EXIT THEN DROP
    _lpo-entry
    _lpo-service-work LIBRARY-SERVICE-NEXT-MUTATION@
    _lpo-next-entry LIBRARY-SERVICE-PREPARE-TOMBSTONE-NEXT
    DUP IF EXIT THEN DROP
    0 ['] LIBRARY-SERVICE-TOMBSTONE _lpo-replace-finish ;

: _lpo-seed-pruning  ( -- )
    \ Build the retained-history fixture while its document is the only
    \ indexed value.  The RAM VFS is deliberately bounded, so this keeps
    \ projection coverage from depending on unrelated copy-on-write pressure.
    S" prune-2" _lpo-prune-content SWAP CMOVE
    5 0 ?DO
        [CHAR] 2 I + _lpo-prune-content 6 + C!
        3 _lpo-prune-content 7 _lpo-content!
            LIBRARY-SERVICE-S-OK _lpo-status
    LOOP
    _lpo-entry LIBE.DOMAIN-REVISION @ 6 = _lpo-assert
    _lpo-entry LIBE.OLDEST-CONTENT-REVISION @ 3 = _lpo-assert
    _lpo-stack ;

: _lpo-seed-lifecycle  ( -- )
    \ Keep document zero active but advance its domain revision independently
    \ of its content revision before a projection instance exists.
    0 LIB-LIFECYCLE-ARCHIVED _lpo-lifecycle!
        LIBRARY-SERVICE-S-OK = _lpo-assert
    0 LIB-LIFECYCLE-ACTIVE _lpo-lifecycle!
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 3 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _lpo-assert

    1 LIB-LIFECYCLE-ARCHIVED _lpo-lifecycle!
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lpo-assert
    _lpo-stack ;

: _lpo-compact-seed-storage  ( -- )
    _lpo-service-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _lpo-before !
    _lpo-compaction-request LIBRARY-COMPACTION-BIND-REQUEST-INIT
    16777216 _lpo-compaction-request LSCBR.BYTE-BUDGET !
    4096 _lpo-compaction-request LSCBR.WORK-BUDGET !
    1048576 _lpo-compaction-request LSCBR.STEP-BYTE-BUDGET !
    _lpo-compaction-request
        LIBRARY-COMPACTION-BIND-REQUEST-VALID? _lpo-assert
    _lpo-compaction-request _lpo-service _lpo-service-work
        LIBRARY-SERVICE-COMPACTION-BIND
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-service-work LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-IDLE = _lpo-assert
    _lpo-service _lpo-service-work LIBRARY-SERVICE-COMPACTION-BEGIN
        LIBRARY-SERVICE-S-OK _lpo-status

    0 _lpo-compact-steps !
    BEGIN
        _lpo-service-work LIBRARY-SERVICE-COMPACTION-STATE@
            PCOMPACT-STATE-BUILDING =
    WHILE
        _lpo-compact-steps @ 4096 >= IF
            0 _lpo-assert EXIT
        THEN
        _lpo-service _lpo-service-work
            LIBRARY-SERVICE-COMPACTION-STEP
            LIBRARY-SERVICE-S-OK _lpo-status
        1 _lpo-compact-steps +!
    REPEAT
    _lpo-service-work LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-READY = DUP _lpo-assert 0= IF EXIT THEN
    _lpo-service _lpo-service-work LIBRARY-SERVICE-COMPACTION-FINALIZE
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-service _lpo-service-work LIBRARY-SERVICE-COMPACTION-PUBLISH
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-service _lpo-service-work LIBRARY-SERVICE-COMPACTION-MIRROR
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-service _lpo-service-work LIBRARY-SERVICE-COMPACTION-CLEANUP
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-service-work LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-CLEANED = _lpo-assert
    _lpo-service-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _lpo-before @ = _lpo-assert
    _lpo-stack ;

: _lpo-capacity-buffers-setup  ( -- )
    0 _lpo-cap-binds ! 0 _lpo-cap-results ! 0 _lpo-large-content !
    _LPO-CAP-BINDS-SIZE ALLOCATE DUP IF NIP THROW THEN
        DROP _lpo-cap-binds !
    _LPO-CAP-RESULTS-SIZE ALLOCATE DUP IF
        NIP >R
        _lpo-cap-binds @ FREE 0 _lpo-cap-binds !
        R> THROW
    THEN
    DROP _lpo-cap-results !
    _LPO-LARGE-CONTENT-U ALLOCATE DUP IF
        NIP >R
        _lpo-cap-results @ FREE 0 _lpo-cap-results !
        _lpo-cap-binds @ FREE 0 _lpo-cap-binds !
        R> THROW
    THEN
    DROP _lpo-large-content !
    _lpo-cap-binds @ _LPO-CAP-BINDS-SIZE 0 FILL
    _lpo-cap-results @ _LPO-CAP-RESULTS-SIZE 0 FILL
    _lpo-large-content @ _LPO-LARGE-CONTENT-U 0 FILL
    _lpo-stack ;

: _lpo-capacity-buffers-free  ( -- )
    _lpo-large-content @ ?DUP IF
        DUP _LPO-LARGE-CONTENT-U 0 FILL FREE
        0 _lpo-large-content !
    THEN
    _lpo-cap-results @ ?DUP IF
        DUP _LPO-CAP-RESULTS-SIZE 0 FILL FREE
        0 _lpo-cap-results !
    THEN
    _lpo-cap-binds @ ?DUP IF
        DUP _LPO-CAP-BINDS-SIZE 0 FILL FREE
        0 _lpo-cap-binds !
    THEN ;

: _lpo-repository-init  ( -- )
    _lpo-cache-0-memory _lpo-cache-0 _lpo-cache-init
    _lpo-cache-1-memory _lpo-cache-1 _lpo-cache-init
    _lpo-builder-cache-0-memory
        _lpo-builder-cache-0 _lpo-cache-init
    _lpo-builder-cache-1-memory
        _lpo-builder-cache-1 _lpo-cache-init
    _lpo-vfs @
    _lpo-cache-0 _lpo-cache-1
    _lpo-builder-cache-0 _lpo-builder-cache-1
    _lpo-repository-guard _lpo-builder-guard
    0 0 _lpo-repository LIBRARY-REPOSITORY-INIT
        LIBRARY-REPOSITORY-S-OK _lpo-status
    _lpo-record-buffer LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _lpo-stage-buffer LIBRARY-REPOSITORY-STAGE-BUFFER-MIN
    _lpo-builder-record-buffer LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _lpo-compact-buffer 512
    _lpo-repository _lpo-repository-work
        LIBRARY-REPOSITORY-WORK-INIT
        LIBRARY-REPOSITORY-S-OK _lpo-status ;

: _lpo-service-init  ( -- )
    _lpo-repository _lpo-repository-work _lpo-service
        LIBRARY-SERVICE-INIT
        LIBRARY-SERVICE-S-OK _lpo-status
    _lpo-service _lpo-service-work LIBRARY-SERVICE-WORK-INIT
        LIBRARY-SERVICE-S-OK _lpo-status ;

: _lpo-repository-setup  ( -- )
    VFS-CUR _lpo-old-vfs !
    _lpo-arena-id LIB-DIGEST-SIZE 0xB4 FILL
    _lpo-unknown-rid LIB-DIGEST-SIZE 0xEE FILL
    VFS-RAM-OPS _lpo-vfs-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _lpo-vfs-binding VFS-BINDING-DESC-SIZE MOVE
    _lpo-vfs-ops _lpo-vfs-binding VB.OPS !
    67108864 A-XMEM ARENA-NEW DUP 0= _lpo-assert
        DROP _lpo-arena !
    _lpo-arena @ _lpo-vfs-binding 0 VFS-NEW
        _lpo-ior ! _lpo-vfs !
    _lpo-ior @ 0= _lpo-assert
    _lpo-vfs @ 0<> _lpo-assert
    _lpo-vfs @ VFS-USE
    _lpo-repository-init
    _lpo-repository _lpo-repository-work
        LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-OK _lpo-status
    _lpo-arena-id _lpo-repository _lpo-repository-work
        LIBRARY-REPOSITORY-BOOTSTRAP
        LIBRARY-REPOSITORY-S-OK _lpo-status
    _lpo-service-init
    _lpo-stack
    3 _lpo-create-document
    _lpo-seed-pruning
    _lpo-compact-seed-storage
    _lpo-create-documents-first
    _lpo-seed-lifecycle
    _lpo-create-documents-rest
    _lpo-create-capture

    \ The unrelated empty VFS is selected only by the ambient-fallback test.
    4194304 A-XMEM ARENA-NEW DUP 0= _lpo-assert DROP
        _lpo-other-arena !
    _lpo-other-arena @ _lpo-vfs-binding 0 VFS-NEW
        _lpo-ior ! _lpo-other-vfs !
    _lpo-ior @ 0= _lpo-assert
    _lpo-other-vfs @ 0<> _lpo-assert
    _lpo-vfs @ VFS-USE
    _lpo-stack ;

: _lpo-runtime-setup  ( -- )
    _lpo-head PHEAD-INIT
    0x51 _lpo-head PHEAD.ID _lpo-id!
    0x52 _lpo-head PHEAD.CURRENT-ROOT _lpo-id!
    91 CTX-NEW DUP 0= _lpo-assert DROP _lpo-context !
    _lpo-head _lpo-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _lpo-context @ CTX.FLAGS !
    92 CTX-NEW DUP 0= _lpo-assert DROP _lpo-cold-context !
    _lpo-head _lpo-cold-context @ CTX.PRACTICE !
    CTX-F-ACTIVE _lpo-cold-context @ CTX.FLAGS !
    CREG-NEW DUP 0= _lpo-assert DROP _lpo-creg !
    _lpo-creg @ _lpo-context @ RREG-NEW
        DUP 0= _lpo-assert DROP _lpo-rreg !
    _lpo-creg @ 0 CBUS-NEW DUP 0= _lpo-assert DROP _lpo-bus !
    _lpo-bus @ _lpo-context @ CTX.QUEUE !
    _lpo-service _lpo-context @ _lpo-creg @ _lpo-rreg @ _lpo-bus @
        _lpo-root LIBRARY-PROJECTION-ROOT-INIT
        RACQ-S-OK = _lpo-assert
    CBR-NEW DUP 0= _lpo-assert DROP _lpo-request !
    _lpo-stack ;

: _lpo-root-contract  ( -- )
    LIB-PROJECTION-MAX 8 = _lpo-assert
    LIBRARY-PROJECTION-OWNER-MAX 8 = _lpo-assert
    LIBRARY-PROJECTION-LEASE-MAX 64 = _lpo-assert
    LIBRARY-PROJECTION-ROOT-SIZE RACQ-ROOT-SIZE > _lpo-assert
    LIBRARY-PROJECTION-OWNER$
        S" org.akashic.library" STR-STR= _lpo-assert
    LIBRARY-PROJECTION-CONTRACT$
        S" org.akashic.library.utf8-content.v1" STR-STR= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RACQ
        RACQ-ROOT-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RACQ
        _lpo-root = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RACQ RACQ-ROOT-OWNER$
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-CALLS@ 0= _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        0= _lpo-assert
    _lpo-unknown-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    -1 _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        0= _lpo-assert
    LIBRARY-PROJECTION-OWNER-MAX _lpo-root
        LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@ 0= _lpo-assert

    \ Root initialization rejects a caller output placed over the Context's
    \ borrowed Practice head before any zero-fill or descriptor mutation.
    _lpo-creg @ CREG.TYPE-N @ _lpo-before !
    _lpo-service _lpo-context @ _lpo-creg @ _lpo-rreg @ _lpo-bus @
        _lpo-head LIBRARY-PROJECTION-ROOT-INIT
        RACQ-S-INVALID = _lpo-assert
    _lpo-head PHEAD-VALID? _lpo-assert
    _lpo-creg @ CREG.TYPE-N @ _lpo-before @ = _lpo-assert
    _lpo-stack ;

: _lpo-attach-alias-contract  ( -- )
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ _lpo-before !

    \ The typed wrapper rejects shared/partially shared outputs before the
    \ portable helper can initialize either object or retain the RID.
    _lpo-result-fail RACQ-RESULT-SIZE 0xA5 FILL
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @
        _lpo-result-fail _lpo-result-fail LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-result-fail C@ 0xA5 = _lpo-assert
    _lpo-result-fail RACQ-RESULT-SIZE 1- + C@ 0xA5 = _lpo-assert

    \ Generic RACQ knows only the 88-byte prefix; the Library wrapper closes
    \ the larger root tail and every bounded borrowed owner span.
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-root RACQ-ROOT-SIZE + LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-VALID? _lpo-assert
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-repository LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-repository LIBRARY-REPOSITORY-VALID? _lpo-assert
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-head LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-head PHEAD-VALID? _lpo-assert
    _lpo-loc-a _lpo-root _lpo-context @ _lpo-rreg @ _lpo-bind-fail
        _lpo-arena @ A.BASE @ LIBRARY-PROJECTION-ATTACH
        RACQ-S-INVALID = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@
        _lpo-before @ = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-sharing-release  ( -- )
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK _lpo-status
    _lpo-result-a RACQ-RESULT-VALID? _lpo-assert
    _lpo-result-a RACQ.RESULT-REF RREF.ID
        0 _lpo-rid RID= _lpo-assert
    _lpo-result-a RACQ.RESULT-REF RREF.REVISION @ 0= _lpo-assert
    _lpo-bind-a LBIND-VALID? _lpo-assert
    _lpo-bind-a LBIND.REVISION @ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        DUP 0>= _lpo-assert
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        DUP _lpo-instance ! 0<> _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert

    \ Registry publication never bypasses the root retain.  The second
    \ acquisition shares the fixed-RID instance but owns a distinct token.
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ _lpo-before !
    _lpo-loc-a _lpo-bind-b _lpo-result-b _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@
        _lpo-before @ 1+ = _lpo-assert
    _lpo-bind-b LBIND.TARGET-ID @
        _lpo-bind-a LBIND.TARGET-ID @ = _lpo-assert
    _lpo-bind-b LBIND.TARGET-GEN @
        _lpo-bind-a LBIND.TARGET-GEN @ = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-instance @ = _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN RACQ.TOKEN-COOKIE @
        _lpo-result-b RACQ.RESULT-TOKEN RACQ.TOKEN-COOKIE @
        <> _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _lpo-assert
    _lpo-result-b RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN
        _lpo-result-b RACQ.RESULT-TOKEN <> _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 2 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert

    \ A context-mismatched LBIND fails after owner retention, so RACQ must
    \ roll the new lease back without disturbing the two existing clients.
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@ _lpo-before !
    _lpo-loc-a _lpo-bind-fail _lpo-result-fail _lpo-cold-attach
        RACQ-S-ATTACH-FAILED = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@
        _lpo-before @ 1+ = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 2 = _lpo-assert

    \ A byte-copy is not a token.  A simulated release failure leaves the
    \ original lease active and retryable; the successful retry waits through
    \ one BUSY quiescence report and performs exactly one decrement.
    _lpo-result-a RACQ.RESULT-TOKEN _lpo-token-copy
        RACQ-TOKEN-SIZE MOVE
    _lpo-token-copy RACQ-RELEASE RACQ-S-STALE-TOKEN = _lpo-assert
    1 _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-FAILURES!
        RACQ-S-OK = _lpo-assert
    _lpo-bind-a _lpo-result-a RACQ-DETACH
        RACQ-S-RELEASE-FAILED = _lpo-assert
    _lpo-result-a RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    1 _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-BUSY!
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-CALLS@ _lpo-before !
    _lpo-bind-a _lpo-result-a RACQ-DETACH RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-QUIESCENT-CALLS@
        _lpo-before @ 2 + = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-instance @ CINST-DESC COMP-DESC-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@ _lpo-before !
    _lpo-result-a RACQ.RESULT-TOKEN RACQ-RELEASE
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-RELEASE-CALLS@
        _lpo-before @ = _lpo-assert

    _lpo-bind-b _lpo-result-b RACQ-DETACH RACQ-S-OK = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-managed-client?  ( client -- flag )
    DUP RCLI-VALID? 0= IF DROP 0 EXIT THEN
    DUP RCLI-REPLACE? 0= IF DROP 0 EXIT THEN
    RCLI.OWNER @ CINST-DESC
    DUP COMP.CAPS-N @ 3 =
    OVER S" resource.describe" ROT COMP-CAP-FIND 0<> AND
    OVER S" resource.snapshot" ROT COMP-CAP-FIND 0<> AND
    SWAP S" resource.replace" ROT COMP-CAP-FIND 0<> AND ;

: _lpo-capture-client?  ( client -- flag )
    DUP RCLI-VALID? 0= IF DROP 0 EXIT THEN
    DUP RCLI-REPLACE? IF DROP 0 EXIT THEN
    RCLI.OWNER @ CINST-DESC
    DUP COMP.CAPS-N @ 2 =
    OVER S" resource.describe" ROT COMP-CAP-FIND 0<> AND
    OVER S" resource.snapshot" ROT COMP-CAP-FIND 0<> AND
    SWAP S" resource.replace" ROT COMP-CAP-FIND 0= AND ;

: _lpo-client-init  ( result binding -- status )
    _lpo-context @ _lpo-bus @ _lpo-client RCLI-INIT ;

: _lpo-describe-managed  ( -- )
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpo-assert
    S" resource" _lpo-request @ CBR.RESULT CV-MAP-FIND
        _lpo-ref IRES-RREF@ IRES-S-OK = _lpo-assert
    _lpo-ref RREF.ID 0 _lpo-rid RID= _lpo-assert
    _lpo-ref RREF.REVISION @ 0= _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 3 = _lpo-assert
    S" kind" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" managed-document" STR-STR= _lpo-assert
    S" title" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" Projection fixture" STR-STR= _lpo-assert
    S" media_type" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" text/plain" STR-STR= _lpo-assert
    S" mutable" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ _lpo-assert
    S" size" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 9 = _lpo-assert
    S" owner" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert ;

: _lpo-snapshot  ( locator expected-a expected-u -- )
    _lpo-text-u ! _lpo-text-a !
    DUP CPRINC-USER _lpo-request @ _lpo-client RCLI-SNAPSHOT-CALL
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-SNAPSHOT-RESULT? _lpo-assert
    _lpo-text-a @ _lpo-text-u @ _lpo-result-content? _lpo-assert ;

: _lpo-current-retained-replace  ( -- )
    0 _lpo-read-identity LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 3 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    0 _lpo-rid 3 _lpo-digest-a _lpo-loc-a _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-managed-client? _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 1 = _lpo-assert
    _lpo-describe-managed
    _lpo-loc-a S" managed-0" _lpo-snapshot

    S" managed-updated" _lpo-digest-b SHA3-256-HASH
    _lpo-loc-a S" managed-updated" _lpo-digest-b CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-CALL
        CBUS-S-OK = _lpo-assert
    _lpo-loc-a _lpo-digest-b _lpo-request @ CBR.RESULT
        RCON-REPLACE-RESULT? _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND CV-DATA@
        4 = _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 2 = _lpo-assert
    _lpo-bind-a LBIND.REVISION @ 1 = _lpo-assert

    \ The retained frame is addressed by its content-frame domain revision,
    \ not by either intervening metadata-only domain revision.
    S" managed-0" _lpo-digest-a SHA3-256-HASH
    0 _lpo-rid 1 _lpo-digest-a _lpo-loc-b _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-b S" managed-0" _lpo-snapshot

    \ A retained historical frame remains readable through this RID owner,
    \ but its exact locator cannot be used as a writable-current alias.
    S" historical-denied" _lpo-digest-a SHA3-256-HASH
    _lpo-loc-b S" historical-denied" _lpo-digest-a CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-CALL
        CBUS-S-STALE-REVISION = _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 2 = _lpo-assert

    0 _lpo-read-identity LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 4 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 2 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-b
        SHA3-256-COMPARE _lpo-assert
    0 _lpo-rid 4 _lpo-digest-b _lpo-loc-c _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-c S" managed-updated" _lpo-snapshot
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-client RCLI-VALID? 0= _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-stack ;

: _lpo-archived-ambient  ( -- )
    1 _lpo-read-identity LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 2 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    1 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    1 _lpo-rid 2 _lpo-digest-a _lpo-loc-b _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert

    \ The root remains bound to its configured service when an unrelated empty
    \ VFS becomes ambient.  Archived identity is unavailable because identity
    \ means active-current; the exact archived state remains readable.
    _lpo-other-vfs @ VFS-USE
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-bind-fail LBIND-INIT
    _lpo-result-fail RACQ-RESULT-INIT
    _lpo-loc-a _lpo-bind-fail _lpo-result-fail _lpo-attach
        RACQ-S-UNAVAILABLE = _lpo-assert
    _lpo-result-fail RACQ.RESULT-STATUS @
        RACQ-S-UNAVAILABLE = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-loc-b _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-managed-client? _lpo-assert
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpo-assert
    S" resource" _lpo-request @ CBR.RESULT CV-MAP-FIND
        _lpo-ref IRES-RREF@ IRES-S-OK = _lpo-assert
    _lpo-ref RREF.ID 1 _lpo-rid RID= _lpo-assert
    _lpo-ref RREF.REVISION @ 0= _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 2 = _lpo-assert
    S" kind" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" managed-document" STR-STR= _lpo-assert
    S" title" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" Projection fixture" STR-STR= _lpo-assert
    S" media_type" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" text/plain" STR-STR= _lpo-assert
    S" mutable" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 0= _lpo-assert
    S" size" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 9 = _lpo-assert
    S" owner" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert
    _lpo-loc-b S" managed-1" _lpo-snapshot

    \ An archived exact state is readable but never mutable.  Refusal must
    \ leave its domain revision, lifecycle, and content digest unchanged.
    S" archived-denied" _lpo-digest-b SHA3-256-HASH
    _lpo-loc-b S" archived-denied" _lpo-digest-b CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-CALL
        CBUS-S-DENIED = _lpo-assert
    _lpo-client RCLI.BIND LBIND.REVISION @ 1 = _lpo-assert
    1 _lpo-read-identity LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 2 = _lpo-assert
    _lpo-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a
        SHA3-256-COMPARE _lpo-assert
    _lpo-loc-b S" managed-1" _lpo-snapshot
    VFS-CUR _lpo-other-vfs @ = _lpo-assert
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-vfs @ VFS-USE
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-stack ;

: _lpo-published-tombstone  ( -- )
    \ Publication is never durable authority.  Once the configured service
    \ tombstones this RID, new acquisition and calls through the already
    \ published instance both fail closed.  Its existing lease remains an
    \ ordinary releasable lifetime token so final teardown cannot leak.
    2 _lpo-read-identity
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    2 _lpo-rid _lpo-entry LIBE.DOMAIN-REVISION @
        _lpo-digest-a _lpo-loc-b _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    2 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-managed-client? _lpo-assert
    2 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert

    2 _lpo-tombstone!
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lpo-assert
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK <> _lpo-assert
    _lpo-loc-b CPRINC-USER _lpo-request @ _lpo-client
        RCLI-SNAPSHOT-CALL CBUS-S-OK <> _lpo-assert

    _lpo-bind-fail LBIND-INIT
    _lpo-loc-a _lpo-bind-fail _lpo-result-fail _lpo-attach
        RACQ-S-TOMBSTONED = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    2 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-capture-snapshot  ( -- )
    9 _lpo-read-identity LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.KIND @ LIB-KIND-CAPTURE = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    9 _lpo-rid _lpo-entry LIBE.DOMAIN-REVISION @ _lpo-digest-a
        _lpo-loc-a _lpo-exact-loc! QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-capture-client? _lpo-assert
    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpo-assert
    S" resource" _lpo-request @ CBR.RESULT CV-MAP-FIND
        _lpo-ref IRES-RREF@ IRES-S-OK = _lpo-assert
    _lpo-ref RREF.ID 9 _lpo-rid RID= _lpo-assert
    _lpo-ref RREF.REVISION @ 0= _lpo-assert
    S" domain_revision" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 1 = _lpo-assert
    S" kind" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" capture" STR-STR= _lpo-assert
    S" title" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" Projection capture" STR-STR= _lpo-assert
    S" media_type" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        S" text/plain" STR-STR= _lpo-assert
    S" mutable" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 0= _lpo-assert
    S" size" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ 13 = _lpo-assert
    S" owner" _lpo-request @ CBR.RESULT CV-MAP-FIND
        DUP CV-DATA@ SWAP CV-LEN@
        LIBRARY-PROJECTION-OWNER$ STR-STR= _lpo-assert
    _lpo-loc-a S" capture bytes" _lpo-snapshot
    S" ignored" _lpo-digest-b SHA3-256-HASH
    _lpo-loc-a S" ignored" _lpo-digest-b CPRINC-USER
        _lpo-request @ _lpo-client RCLI-REPLACE-PREPARE
        RCLI-S-READONLY = _lpo-assert
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-stack ;

: _lpo-large-bounded-snapshot  ( -- )
    10 _lpo-read-identity
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.CONTENT-U @
        _LPO-LARGE-CONTENT-U = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    10 _lpo-rid _lpo-entry LIBE.DOMAIN-REVISION @
        _lpo-digest-a _lpo-loc-a _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-client _lpo-managed-client? _lpo-assert

    CPRINC-USER _lpo-request @ _lpo-client RCLI-DESCRIBE
        CBUS-S-OK = _lpo-assert
    _lpo-request @ CBR.RESULT RCON-DESCRIBE-RESULT? _lpo-assert
    S" size" _lpo-request @ CBR.RESULT CV-MAP-FIND
        CV-DATA@ _LPO-LARGE-CONTENT-U = _lpo-assert

    \ Projection interop is intentionally bounded to 64 KiB.  Describe
    \ reports the complete durable size, while snapshot refuses atomically
    \ instead of returning a misleading prefix.
    _lpo-loc-a CPRINC-USER _lpo-request @ _lpo-client
        RCLI-SNAPSHOT-CALL CBUS-S-FAILED = _lpo-assert
    _lpo-loc-a _lpo-request @ CBR.RESULT
        RCON-SNAPSHOT-RESULT? 0= _lpo-assert
    S" content" _lpo-request @ CBR.RESULT CV-MAP-FIND
        0= _lpo-assert

    10 _lpo-read-identity
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.CONTENT-U @
        _LPO-LARGE-CONTENT-U = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a
        SHA3-256-COMPARE _lpo-assert
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-stack ;

: _lpo-rejected  ( locator expected-status -- )
    _lpo-expected-status !
    _lpo-bind-fail LBIND-INIT
    _lpo-result-fail RACQ-RESULT-INIT
    _lpo-bind-fail _lpo-result-fail _lpo-attach
        _lpo-expected-status @ = _lpo-assert
    _lpo-result-fail RACQ.RESULT-STATUS @
        _lpo-expected-status @ = _lpo-assert
    _lpo-result-fail RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert ;

: _lpo-acquire-failures  ( -- )
    0 _lpo-read-identity LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 4 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY

    \ Owner mismatch is rejected by the portable acquisition boundary before
    \ the Library callback is entered.
    _lpo-ref RREF-INIT
    0 _lpo-rid _lpo-ref RREF.ID RID-COPY
    S" org.akashic.wrong-owner" _lpo-ref _lpo-loc-a QLOC-IDENTITY!
        QLOC-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@ _lpo-before !
    _lpo-loc-a RACQ-S-OWNER-MISMATCH _lpo-rejected
    _lpo-root LIBRARY-PROJECTION-ROOT-ACQUIRE-CALLS@
        _lpo-before @ = _lpo-assert

    \ The projection contract, exact domain revision, and projection digest
    \ are independent closed qualifiers.
    0 _lpo-rid 4 _lpo-digest-a _lpo-loc-a _lpo-exact-loc! DROP
    _lpo-loc-a _lpo-loc-b QLOC-COPY DROP
    [CHAR] x _lpo-loc-b QLOC.PROJECTION C!
    _lpo-loc-b QLOC-VALID? _lpo-assert
    _lpo-loc-b RACQ-S-UNQUALIFIED _lpo-rejected

    0 _lpo-rid 999 _lpo-digest-a _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-REVISION-MISMATCH _lpo-rejected

    _lpo-digest-a _lpo-digest-b RID-COPY
    _lpo-digest-b DUP C@ 1 XOR SWAP C!
    0 _lpo-rid 4 _lpo-digest-b _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-DIGEST-MISMATCH _lpo-rejected

    _lpo-unknown-rid _lpo-loc-b _lpo-identity-loc! DROP
    _lpo-loc-b RACQ-S-NOT-FOUND _lpo-rejected

    \ Domain revision two on document zero was metadata-only and never a
    \ content-frame alias.  Document three's original frame is truly pruned.
    S" managed-0" _lpo-digest-a SHA3-256-HASH
    0 _lpo-rid 2 _lpo-digest-a _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-GONE _lpo-rejected
    S" managed-3" _lpo-digest-a SHA3-256-HASH
    3 _lpo-rid 1 _lpo-digest-a _lpo-loc-b _lpo-exact-loc! DROP
    _lpo-loc-b RACQ-S-PRUNED _lpo-rejected

    2 _lpo-rid _lpo-loc-b _lpo-identity-loc! DROP
    _lpo-loc-b RACQ-S-TOMBSTONED _lpo-rejected
    _lpo-stack ;

: _lpo-capacity-contract  ( -- )
    LIB-PROJECTION-MAX 0 ?DO
        I _lpo-cap-rid _lpo-loc-a _lpo-identity-loc! DROP
        _lpo-loc-a I _lpo-cap-bind I _lpo-cap-result _lpo-attach
            RACQ-S-OK = _lpo-assert
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
            DUP 0>= _lpo-assert
            _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
            DUP 0<> _lpo-assert
            I 8 * _lpo-cap-instances + !
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
            1 = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ LIB-PROJECTION-MAX = _lpo-assert

    \ A ninth distinct RID cannot evict or retarget any fixed-RID owner.
    \ The ninth request is an exact archived state because archived identity
    \ is deliberately unavailable.
    1 _lpo-read-identity LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    1 _lpo-rid 2 _lpo-digest-a _lpo-loc-b _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-b 8 _lpo-cap-bind 8 _lpo-cap-result _lpo-attach
        RACQ-S-CAPACITY = _lpo-assert
    8 _lpo-cap-result RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
        0= _lpo-assert
    1 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    LIB-PROJECTION-MAX 0 ?DO
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
            _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
            I 8 * _lpo-cap-instances + @ = _lpo-assert
    LOOP

    \ Pool fullness is per distinct owner, not per lease.  Sharing remains
    \ available and must retain the original instance.
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc! DROP
    _lpo-loc-a 9 _lpo-cap-bind 9 _lpo-cap-result _lpo-attach
        RACQ-S-OK = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        2 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-cap-instances @ = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIB-PROJECTION-MAX 1+ = _lpo-assert

    \ Releasing one final reference frees exactly that owner slot.  The
    \ refused archived state can then acquire it without disturbing owners.
    7 _lpo-cap-bind 7 _lpo-cap-result RACQ-DETACH
        RACQ-S-OK = _lpo-assert
    9 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        -1 = _lpo-assert
    _lpo-loc-b 7 _lpo-cap-bind 7 _lpo-cap-result _lpo-attach
        RACQ-S-OK = _lpo-assert
    1 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        DUP 0>= _lpo-assert
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        0<> _lpo-assert
    7 0 ?DO
        I _lpo-cap-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
            _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
            I 8 * _lpo-cap-instances + @ = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@
        LIB-PROJECTION-MAX = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIB-PROJECTION-MAX 1+ = _lpo-assert

    LIB-PROJECTION-MAX 0 ?DO
        I _lpo-cap-bind I _lpo-cap-result RACQ-DETACH
            RACQ-S-OK = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 1 = _lpo-assert
    9 _lpo-cap-bind 9 _lpo-cap-result RACQ-DETACH
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-lease-capacity-contract  ( -- )
    \ Lease capacity is independent of the eight-owner pool.  One fixed-RID
    \ owner may be shared through exactly 64 distinct activation-local tokens.
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc!
        QLOC-S-OK = _lpo-assert
    LIBRARY-PROJECTION-LEASE-MAX 0 ?DO
        _lpo-loc-a I _lpo-cap-bind I _lpo-cap-result _lpo-attach
            RACQ-S-OK = _lpo-assert
        I _lpo-cap-result RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE?
            _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 1 = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        DUP 0>= _lpo-assert
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        DUP _lpo-instance ! 0<> _lpo-assert

    \ The 65th token refuses without changing the shared instance or counts.
    _lpo-loc-a LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-bind
        LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-result _lpo-attach
        RACQ-S-CAPACITY = _lpo-assert
    LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-result
        RACQ.RESULT-TOKEN RACQ-TOKEN-ACTIVE? 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-instance @ = _lpo-assert

    \ Releasing any one token makes one ledger slot reusable without
    \ retargeting the owner or changing its other 63 references.
    0 _lpo-cap-bind 0 _lpo-cap-result RACQ-DETACH
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX 1- = _lpo-assert
    _lpo-loc-a LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-bind
        LIBRARY-PROJECTION-LEASE-MAX _lpo-cap-result _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        LIBRARY-PROJECTION-LEASE-MAX = _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-FIND
        _lpo-root LIBRARY-PROJECTION-ROOT-SLOT-INSTANCE@
        _lpo-instance @ = _lpo-assert

    LIBRARY-PROJECTION-LEASE-MAX 1+ 1 ?DO
        I _lpo-cap-bind I _lpo-cap-result RACQ-DETACH
            RACQ-S-OK = _lpo-assert
    LOOP
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 0= _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LEASES@ 0= _lpo-assert
    0 _lpo-rid _lpo-root LIBRARY-PROJECTION-ROOT-REFS@
        0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-root-fini-contract  ( -- )
    0 _lpo-rid _lpo-loc-a _lpo-identity-loc! DROP
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-FINI
        RACQ-S-BUSY = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-VALID? _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-LIVE@ 1 = _lpo-assert
    _lpo-bind-a _lpo-result-a RACQ-DETACH RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-FINI
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-SIZE _lpo-zero? _lpo-assert
    _lpo-creg @ CREG.INST-N @ 0= _lpo-assert
    _lpo-rreg @ RREG.COUNT @ 0= _lpo-assert
    _lpo-stack ;

: _lpo-cold-reopen-contract  ( -- )
    \ Close every storage/service descriptor, reconstruct them over the same
    \ RAM-VFS, and prove an exact retained locator is still projectable.
    _lpo-service _lpo-service-work LIBRARY-SERVICE-FINI
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-repository _lpo-repository-work LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK = _lpo-assert
    _lpo-repository-init
    _lpo-repository _lpo-repository-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-OK = _lpo-assert
    _lpo-service-init
    _lpo-service _lpo-context @ _lpo-creg @ _lpo-rreg @ _lpo-bus @
        _lpo-root LIBRARY-PROJECTION-ROOT-INIT
        RACQ-S-OK = _lpo-assert

    0 _lpo-read-identity
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-entry LIBE.DOMAIN-REVISION @ 4 = _lpo-assert
    _lpo-entry LIBE.CONTENT-DIGEST _lpo-digest-a RID-COPY
    0 _lpo-rid 4 _lpo-digest-a _lpo-loc-a _lpo-exact-loc!
        QLOC-S-OK = _lpo-assert
    _lpo-loc-a _lpo-bind-a _lpo-result-a _lpo-attach
        RACQ-S-OK = _lpo-assert
    _lpo-result-a _lpo-bind-a _lpo-client-init
        CBUS-S-OK = _lpo-assert
    _lpo-loc-a S" managed-updated" _lpo-snapshot
    _lpo-client RCLI-FINI CBUS-S-OK = _lpo-assert
    _lpo-bind-a LBIND-CLEAR
    _lpo-root LIBRARY-PROJECTION-ROOT-FINI
        RACQ-S-OK = _lpo-assert
    _lpo-root LIBRARY-PROJECTION-ROOT-SIZE _lpo-zero? _lpo-assert
    _lpo-stack ;

: _lpo-teardown  ( -- )
    _lpo-request @ CBR-FREE
    0 _lpo-request !
    _lpo-bus @ CBUS-FREE
    _lpo-rreg @ RREG-FREE
    _lpo-creg @ CREG-FREE
    _lpo-cold-context @ CTX-FREE
    _lpo-context @ CTX-FREE
    _lpo-vfs @ VFS-USE
    _lpo-service _lpo-service-work LIBRARY-SERVICE-FINI
        LIBRARY-SERVICE-S-OK = _lpo-assert
    _lpo-repository _lpo-repository-work LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK = _lpo-assert
    _lpo-old-vfs @ VFS-USE
    _lpo-other-vfs @ VFS-DESTROY
    _lpo-vfs @ VFS-DESTROY
    _lpo-capacity-buffers-free
    _lpo-stack ;

: _lpo-run  ( -- )
    0 _lpo-fails ! 0 _lpo-checks ! DEPTH _lpo-depth !
    _lpo-capacity-buffers-setup
    _lpo-repository-setup
    _lpo-runtime-setup
    _lpo-root-contract
    _lpo-attach-alias-contract
    _lpo-sharing-release
    _lpo-current-retained-replace
    _lpo-archived-ambient
    _lpo-capture-snapshot
    _lpo-published-tombstone
    _lpo-acquire-failures
    _lpo-capacity-contract
    _lpo-lease-capacity-contract
    _lpo-create-large
    _lpo-large-bounded-snapshot
    _lpo-root-fini-contract
    _lpo-cold-reopen-contract
    _lpo-teardown
    _lpo-stack
    _lpo-fails @ ?DUP IF
        ." LIBRARY PROJECTION OWNER FAIL " .
        ."  / " _lpo-checks @ . CR
    ELSE
        ." LIBRARY PROJECTION OWNER PASS " _lpo-checks @ . CR
    THEN ;

_lpo-run
