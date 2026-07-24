\ Focused RAM-VFS contracts for the L12 Desk/Library semantic service.

PROVIDED akashic-library-service-l12-contracts

VARIABLE _LS12-fails
VARIABLE _LS12-checks
VARIABLE _LS12-depth

LIBRARY-SERVICE-SIZE XBUF _LS12-service
LIBRARY-SERVICE-WORK-SIZE XBUF _LS12-work

LIBRARY-DOCUMENT-INITIAL-DRAFT-SIZE XBUF _LS12-draft
LIB-ENTRY-SIZE XBUF _LS12-entry
LIB-CONTENT-SIZE XBUF _LS12-content
LIB-ENTRY-SIZE XBUF _LS12-result-entry
LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE XBUF _LS12-create-request
64 XBUF _LS12-content-bytes

LIB-ENTRY-SIZE XBUF _LS12-replace-next
LIB-CONTENT-SIZE XBUF _LS12-replace-content-value
LIB-ENTRY-SIZE XBUF _LS12-replace-result
LIBRARY-DOCUMENT-REPLACE-REQUEST-SIZE XBUF _LS12-replace-request
LIBRARY-RETAINED-READ-REQUEST-SIZE XBUF _LS12-retained-request
LIBRARY-SERVICE-CONTENT-DESCRIPTOR-SIZE XBUF _LS12-retained-descriptor
LIBRARY-RETAINED-CONTENT-FACTS-SIZE XBUF _LS12-retained-facts
LIB-ENTRY-SIZE XBUF _LS12-restore-next
LIB-ENTRY-SIZE XBUF _LS12-restore-missing-next
LIB-ENTRY-SIZE XBUF _LS12-restore-result
LIB-ENTRY-SIZE XBUF _LS12-pristine-entry
LIBRARY-DOCUMENT-RESTORE-REQUEST-SIZE XBUF _LS12-restore-request
LIBRARY-RETAINED-COMPARE-REQUEST-SIZE XBUF _LS12-compare-request
VARIABLE _LS12-compare-equal
LIBRARY-HISTORY-QUERY-REQUEST-SIZE XBUF _LS12-history-request
LIBRARY-QUERY-PAGE-SIZE XBUF _LS12-history-page
LIBRARY-REVISION-SUMMARY-SIZE 3 * XBUF _LS12-history-rows

LIB-METADATA-FACT-HEADER-SIZE LIB-ORIGIN-SIZE +
    CONSTANT _LS12-capture-facts-u
LIB-ORIGIN-SIZE XBUF _LS12-capture-origin
_LS12-capture-facts-u XBUF _LS12-capture-facts
32 XBUF _LS12-capture-bytes
LIB-ENTRY-SIZE XBUF _LS12-capture-entry
LIB-CONTENT-SIZE XBUF _LS12-capture-content
LIB-ENTRY-SIZE XBUF _LS12-capture-result
LIB-ENTRY-SIZE XBUF _LS12-capture-mismatch-entry
LIB-CONTENT-SIZE XBUF _LS12-capture-mismatch-content
LIB-ENTRY-SIZE XBUF _LS12-capture-mismatch-result
LIB-ENTRY-SIZE XBUF _LS12-capture-distinct-result
LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE XBUF _LS12-capture-request
VARIABLE _LS12-value-entry
VARIABLE _LS12-value-content
VARIABLE _LS12-value-rid
VARIABLE _LS12-value-operation
VARIABLE _LS12-generation
VARIABLE _LS12-mutation-before
VARIABLE _LS12-document-before

LIBRARY-OPERATION-LOOKUP-REQUEST-SIZE XBUF _LS12-operation-request
VARIABLE _LS12-operation-kind
VARIABLE _LS12-expected-operation-kind
RID-SIZE XBUF _LS12-operation-rid
RID-SIZE XBUF _LS12-expected-operation-rid

LIB-ENTRY-SIZE XBUF _LS12-lifecycle-next
LIB-ENTRY-SIZE XBUF _LS12-lifecycle-result
LIBRARY-DOCUMENT-REPLACE-REQUEST-SIZE XBUF _LS12-lifecycle-request

LIBRARY-CORPUS-QUERY-REQUEST-SIZE XBUF _LS12-corpus-request
LIBRARY-QUERY-PAGE-SIZE XBUF _LS12-corpus-page
LIBRARY-QUERY-SUMMARY-SIZE XBUF _LS12-corpus-row

LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LS12-inspection-a
LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LS12-inspection-b
LIBRARY-MIRROR-REPAIR-REQUEST-SIZE XBUF _LS12-repair-request
SHA3-256-LEN XBUF _LS12-repaired-seal
SHA3-256-LEN XBUF _LS12-pristine-seal
LIBRARY-RAW-EXPORT-REQUEST-SIZE XBUF _LS12-raw-request
VARIABLE _LS12-raw-required
VARIABLE _LS12-raw

RID-SIZE 129 * XBUF _LS12-many-rids
LIBPA-COLLECTION-SIZE XBUF _LS12-many-collection
LIBPA-COLLECTION-SIZE XBUF _LS12-collection-result
LIBPA-COLLECTION-SIZE XBUF _LS12-collection-next
LIBPA-COLLECTION-SIZE XBUF _LS12-collection-read
LIBPA-COLLECTION-SIZE XBUF _LS12-collection-conflict
LIBPA-COLLECTION-SIZE XBUF _LS12-pristine-collection
LIBRARY-COLLECTION-WRITE-REQUEST-SIZE XBUF _LS12-collection-request
LIBRARY-COLLECTION-READ-REQUEST-SIZE XBUF _LS12-collection-read-request

VARIABLE _LS12-logical-before

LIBRARY-COMPACTION-BIND-REQUEST-SIZE XBUF _LS12-compaction-request

: _LS12-assert  ( flag -- )
    1 _LS12-checks +!
    0= IF
        1 _LS12-fails +!
        ." LIBRARY SERVICE L12 ASSERT " _LS12-checks @ . CR
    THEN ;

: _LS12-stack  ( -- )
    DEPTH DUP _LS12-depth @ <> IF
        ." LIBRARY SERVICE L12 STACK "
        _LS12-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LS12-depth @ = _LS12-assert ;

: _LS12-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY SERVICE L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LS12-assert
    _LS12-stack ;

: _LS12-progress  ( phase -- )
    ." LIBRARY SERVICE L12 PHASE " . CR
    0 0xFFFFFF0000000006 C! ;

: _LS12-text!  ( source-a source-u destination length-cell -- )
    >R
    OVER R@ !
    SWAP MOVE
    R> DROP ;

: _LS12-repository-ready  ( -- )
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-ABSENT _LS12-status
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-OK _LS12-status
    _LR12-bootstrap _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-BOOTSTRAP
        LIBRARY-REPOSITORY-S-OK _LS12-status
    _LR12-work-a LIBRARY-REPOSITORY-LOGICAL-GENERATION@
        0= _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        0= _LS12-assert
    _LS12-stack ;

: _LS12-service-init  ( -- )
    _LR12-repository-a _LR12-work-a _LS12-service
        LIBRARY-SERVICE-INIT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-service LIBRARY-SERVICE-VALID? _LS12-assert
    _LS12-service _LS12-work LIBRARY-SERVICE-WORK-INIT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-work LIBRARY-SERVICE-WORK-VALID? _LS12-assert
    _LS12-work LIBRARY-SERVICE-WORK-SERVICE@
        _LS12-service = _LS12-assert
    _LS12-service LIBRARY-SERVICE-REPOSITORY@
        _LR12-repository-a = _LS12-assert
    _LS12-service LIBRARY-SERVICE-REPOSITORY-WORK@
        _LR12-work-a = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        0= _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        1 = _LS12-assert
    _LS12-stack ;

: _LS12-managed-value!  ( -- )
    _LS12-content-bytes 64 0 FILL
    S" service" _LS12-content-bytes SWAP MOVE

    _LS12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _LS12-draft LSDID.ID RID-CLEAR
    1 _LS12-draft LSDID.ID !
    _LS12-draft LSDID.OPERATION-KEY RID-CLEAR
    0x100051 _LS12-draft LSDID.OPERATION-KEY !
    LIB-KIND-MANAGED-DOCUMENT _LS12-draft LSDID.KIND !
    LIB-MEDIA-TEXT-PLAIN _LS12-draft LSDID.MEDIA !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-draft LSDID.MUTATION-SEQUENCE !
    _LS12-content-bytes _LS12-draft LSDID.CONTENT-A !
    7 _LS12-draft LSDID.CONTENT-U !
    S" Service contract"
        _LS12-draft LSDID.TITLE
        _LS12-draft LSDID.TITLE-U _LS12-text!

    _LS12-draft _LS12-entry _LS12-content
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-entry LIB-ENTRY-VALID? _LS12-assert
    _LS12-content LIB-CONTENT-VALID? _LS12-assert

    _LS12-create-request LIBRARY-DOCUMENT-CREATE-REQUEST-INIT
    _LS12-entry _LS12-create-request LSDCR.ENTRY !
    _LS12-content _LS12-create-request LSDCR.CONTENT !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-create-request LSDCR.EXPECTED-LOGICAL !
    _LS12-result-entry _LS12-create-request LSDCR.RESULT !
    _LS12-create-request
        LIBRARY-DOCUMENT-CREATE-REQUEST-VALID? _LS12-assert
    _LS12-stack ;

: _LS12-managed-create  ( -- )
    _LS12-managed-value!
    _LS12-create-request _LS12-service _LS12-work
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-result-entry LIB-ENTRY-VALID? _LS12-assert
    _LS12-result-entry LIBE.ID _LS12-entry LIBE.ID
        RID= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        1 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        2 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LS12-assert

    \ Same operation value is a no-write retry even though its expected
    \ generation is now stale.
    _LS12-result-entry LIB-ENTRY-SIZE 0xA5 FILL
    _LS12-create-request _LS12-service _LS12-work
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-result-entry LIB-ENTRY-VALID? _LS12-assert
    _LS12-result-entry LIBE.ID _LS12-entry LIBE.ID
        RID= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        1 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LS12-assert
    _LS12-stack ;

: _LS12-entry=  ( entry-a entry-b -- flag )
    LIB-ENTRY-SIZE SWAP LIB-ENTRY-SIZE COMPARE 0= ;

: _LS12-collection=  ( collection-a collection-b -- flag )
    LIBPA-COLLECTION-SIZE SWAP
    LIBPA-COLLECTION-SIZE COMPARE 0= ;

: _LS12-operation=  ( operation-key expected-kind expected-rid -- )
    _LS12-expected-operation-rid RID-COPY
    _LS12-expected-operation-kind !
    _LS12-operation-request LIBRARY-OPERATION-LOOKUP-REQUEST-INIT
    _LS12-operation-request LSOLR.OPERATION-KEY RID-COPY
    _LS12-operation-kind
        _LS12-operation-request LSOLR.KIND-OUT !
    _LS12-operation-rid
        _LS12-operation-request LSOLR.RID-OUT !
    _LS12-operation-request
        LIBRARY-OPERATION-LOOKUP-REQUEST-VALID? _LS12-assert
    -1 _LS12-operation-kind !
    _LS12-operation-rid RID-SIZE 0xA5 FILL
    _LS12-operation-request _LS12-service _LS12-work
        LIBRARY-SERVICE-LOOKUP-OPERATION
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-operation-kind @
        _LS12-expected-operation-kind @ = _LS12-assert
    _LS12-operation-rid _LS12-expected-operation-rid
        RID= _LS12-assert
    _LS12-stack ;

: _LS12-capture-origin!  ( -- )
    _LS12-capture-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT
        _LS12-capture-origin LIBO.KIND !
    S" /imports/service-capture.md"
        DUP _LS12-capture-origin LIBO.VFS LIBV.PATH-U !
        _LS12-capture-origin LIBO.VFS LIBV.PATH SWAP MOVE
    8 _LS12-capture-origin LIBO.VFS LIBV.CONTENT-U !
    QLOC-DK-PROJECTION-CONTENT
        _LS12-capture-origin LIBO.VFS LIBV.DIGEST-KIND !
    S" captured"
        _LS12-capture-origin LIBO.VFS LIBV.CONTENT-DIGEST
        SHA3-256-HASH
    _LS12-capture-origin LIB-ORIGIN-VALID? _LS12-assert

    _LS12-capture-facts _LS12-capture-facts-u 0 FILL
    LIB-METADATA-FACT-ORIGIN
        _LS12-capture-facts LIBMF.KIND !
    LIB-ORIGIN-SIZE
        _LS12-capture-facts LIBMF.PAYLOAD-U !
    _LS12-capture-origin
        _LS12-capture-facts LIBMF.PAYLOAD
        LIB-ORIGIN-SIZE MOVE ;

: _LS12-capture-value!
  ( changed? rid-cell operation-cell entry content -- )
    _LS12-value-content !
    _LS12-value-entry !
    _LS12-value-operation !
    _LS12-value-rid !
    _LS12-capture-bytes 32 0 FILL
    S" captured" _LS12-capture-bytes SWAP MOVE

    _LS12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _LS12-draft LSDID.ID RID-CLEAR
    _LS12-value-rid @ _LS12-draft LSDID.ID !
    _LS12-draft LSDID.OPERATION-KEY RID-CLEAR
    _LS12-value-operation @ _LS12-draft LSDID.OPERATION-KEY !
    LIB-KIND-CAPTURE _LS12-draft LSDID.KIND !
    LIB-MEDIA-TEXT-MARKDOWN _LS12-draft LSDID.MEDIA !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-draft LSDID.MUTATION-SEQUENCE !
    _LS12-capture-bytes _LS12-draft LSDID.CONTENT-A !
    8 _LS12-draft LSDID.CONTENT-U !
    IF
        S" Changed service capture"
    ELSE
        S" Service capture"
    THEN
    _LS12-draft LSDID.TITLE
        _LS12-draft LSDID.TITLE-U _LS12-text!
    _LS12-capture-facts _LS12-capture-facts-u _LS12-draft
        LIBRARY-DOCUMENT-INITIAL-DRAFT-FACTS!
        LIBRARY-SERVICE-S-OK _LS12-status

    _LS12-draft
    _LS12-value-entry @ _LS12-value-content @
        LIBRARY-SERVICE-PREPARE-CAPTURE-IMPORT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-value-entry @ LIB-ENTRY-VALID? _LS12-assert
    _LS12-value-content @ LIB-CONTENT-VALID? _LS12-assert
    _LS12-stack ;

: _LS12-capture-conflict  ( entry content -- )
    >R
    _LS12-capture-request LSDCR.ENTRY !
    R@ _LS12-capture-request LSDCR.CONTENT !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-capture-request LSDCR.EXPECTED-LOGICAL !
    _LS12-capture-mismatch-result
        _LS12-capture-request LSDCR.RESULT !
    _LS12-capture-request
        LIBRARY-DOCUMENT-CREATE-REQUEST-VALID? _LS12-assert

    _LS12-capture-mismatch-result LIB-ENTRY-SIZE 0xA5 FILL
    _LS12-pristine-entry LIB-ENTRY-SIZE 0xA5 FILL
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-mutation-before !
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        _LS12-document-before !
    _LS12-capture-request _LS12-service _LS12-work
        LIBRARY-SERVICE-IMPORT-CAPTURE
        LIBRARY-SERVICE-S-CONFLICT _LS12-status
    _LS12-capture-mismatch-result _LS12-pristine-entry
        _LS12-entry= _LS12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-mutation-before @ = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        _LS12-document-before @ = _LS12-assert
    R> DROP
    _LS12-stack ;

: _LS12-capture-import  ( -- )
    _LS12-capture-origin!
    0 2 0x100052 _LS12-capture-entry _LS12-capture-content
        _LS12-capture-value!

    _LS12-capture-request LIBRARY-DOCUMENT-CREATE-REQUEST-INIT
    _LS12-capture-entry
        _LS12-capture-request LSDCR.ENTRY !
    _LS12-capture-content
        _LS12-capture-request LSDCR.CONTENT !
    _LS12-capture-facts
        _LS12-capture-request LSDCR.FACTS-A !
    _LS12-capture-facts-u
        _LS12-capture-request LSDCR.FACTS-U !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-capture-request LSDCR.EXPECTED-LOGICAL !
    _LS12-capture-result
        _LS12-capture-request LSDCR.RESULT !
    _LS12-capture-request
        LIBRARY-DOCUMENT-CREATE-REQUEST-VALID? _LS12-assert
    _LS12-capture-request _LS12-service _LS12-work
        LIBRARY-SERVICE-IMPORT-CAPTURE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-capture-result LIB-ENTRY-VALID? _LS12-assert
    _LS12-capture-result LIBE.ID
        _LS12-capture-entry LIBE.ID RID= _LS12-assert
    _LS12-capture-result LIBE.KIND @
        LIB-KIND-CAPTURE = _LS12-assert
    _LS12-capture-result LIBE.RECEIPT LIBR.METHOD @
        LIB-IMPORT-VFS-SNAPSHOT = _LS12-assert
    _LS12-capture-result LIBE.RECEIPT LIBR.OPERATION-KEY
        _LS12-capture-entry LIBE.RECEIPT LIBR.OPERATION-KEY
        RID= _LS12-assert
    _LS12-capture-result LIBE.RECEIPT
        LIBR.INITIAL-CONTENT-DIGEST
    _LS12-capture-content LIBCT.DIGEST
        RID= _LS12-assert
    _LS12-capture-result LIBE.RECEIPT LIBR-SOURCE-OWNER$
        LIB-VFS-SOURCE-OWNER$ COMPARE 0= _LS12-assert
    _LS12-capture-origin LIB-ORIGIN-SIZE
        _LS12-operation-rid SHA3-256-HASH
    _LS12-capture-result LIBE.RECEIPT LIBR.LOCATOR-DIGEST
        _LS12-operation-rid RID= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        4 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        5 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        2 = _LS12-assert

    \ A same-value replay is a readback even though its expected generation
    \ is stale; neither physical nor semantic generation advances.
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation !
    _LS12-capture-result LIB-ENTRY-SIZE 0xA5 FILL
    _LS12-capture-request _LS12-service _LS12-work
        LIBRARY-SERVICE-IMPORT-CAPTURE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-capture-result _LS12-capture-entry
        _LS12-entry= _LS12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        4 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        5 = _LS12-assert

    \ Identical capture bytes and origin under a genuinely new operation key
    \ remain a separate resource identity, not content-addressed deduplication.
    0 3 0x100053
        _LS12-capture-mismatch-entry _LS12-capture-mismatch-content
        _LS12-capture-value!
    _LS12-capture-mismatch-entry
        _LS12-capture-request LSDCR.ENTRY !
    _LS12-capture-mismatch-content
        _LS12-capture-request LSDCR.CONTENT !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-capture-request LSDCR.EXPECTED-LOGICAL !
    _LS12-capture-distinct-result
        _LS12-capture-request LSDCR.RESULT !
    _LS12-capture-request _LS12-service _LS12-work
        LIBRARY-SERVICE-IMPORT-CAPTURE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-capture-distinct-result LIB-ENTRY-VALID? _LS12-assert
    _LS12-capture-distinct-result LIBE.ID
        _LS12-capture-result LIBE.ID RID= 0= _LS12-assert
    _LS12-capture-distinct-result LIBE.CONTENT-DIGEST
        _LS12-capture-result LIBE.CONTENT-DIGEST
        RID= _LS12-assert
    _LS12-capture-distinct-result LIBE.RECEIPT LIBR.LOCATOR-DIGEST
        _LS12-capture-result LIBE.RECEIPT LIBR.LOCATOR-DIGEST
        RID= _LS12-assert
    _LS12-capture-distinct-result LIBE.RECEIPT LIBR.REQUEST-SEAL
        _LS12-capture-result LIBE.RECEIPT LIBR.REQUEST-SEAL
        RID= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        5 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        6 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        3 = _LS12-assert
    _LS12-capture-mismatch-entry LIBE.RECEIPT LIBR.OPERATION-KEY
    LIBPA-OPERATION-DOCUMENT _LS12-capture-distinct-result LIBE.ID
        _LS12-operation=

    \ The operation key cannot disguise changed request facts.
    -1 2 0x100052 _LS12-capture-mismatch-entry
        _LS12-capture-mismatch-content _LS12-capture-value!
    _LS12-capture-mismatch-entry
        _LS12-capture-request LSDCR.ENTRY !
    _LS12-capture-mismatch-content
        _LS12-capture-request LSDCR.CONTENT !
    _LS12-capture-mismatch-result LIB-ENTRY-SIZE 0xA5 FILL
    _LS12-pristine-entry LIB-ENTRY-SIZE 0xA5 FILL
    _LS12-capture-mismatch-result
        _LS12-capture-request LSDCR.RESULT !
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation !
    _LS12-capture-request _LS12-service _LS12-work
        LIBRARY-SERVICE-IMPORT-CAPTURE
        LIBRARY-SERVICE-S-IDEMPOTENCY-MISMATCH _LS12-status
    _LS12-capture-mismatch-result _LS12-pristine-entry
        _LS12-entry= _LS12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        5 = _LS12-assert

    \ Resource IDs and operation keys share one global namespace.  Exercise
    \ both crossed directions and require a nonpublishing conflict.
    0 0x100052 0x100054
        _LS12-capture-mismatch-entry _LS12-capture-mismatch-content
        _LS12-capture-value!
    _LS12-capture-mismatch-entry _LS12-capture-mismatch-content
        _LS12-capture-conflict

    0 4 2
        _LS12-capture-mismatch-entry _LS12-capture-mismatch-content
        _LS12-capture-value!
    _LS12-capture-mismatch-entry _LS12-capture-mismatch-content
        _LS12-capture-conflict

    _LS12-capture-entry LIBE.RECEIPT LIBR.OPERATION-KEY
    LIBPA-OPERATION-DOCUMENT _LS12-capture-entry LIBE.ID
        _LS12-operation=
    _LS12-stack ;

: _LS12-retained-facts!  ( descriptor facts -- )
    >R
    R@ LIBRARY-RETAINED-CONTENT-FACTS-INIT
    DUP LIBRARY-SERVICE-CONTENT-RID@
        R@ LIBRCF.ID RID-COPY
    DUP LIBRARY-SERVICE-CONTENT-DOMAIN-REVISION@
        R@ LIBRCF.DOMAIN-REVISION !
    DUP LIBRARY-SERVICE-CONTENT-REVISION@
        R@ LIBRCF.CONTENT-REVISION !
    DUP LIBRARY-SERVICE-CONTENT-KIND@
        R@ LIBRCF.KIND !
    DUP LIBRARY-SERVICE-CONTENT-MEDIA@
        R@ LIBRCF.MEDIA !
    DUP LIBRARY-SERVICE-CONTENT-SIZE@
        R@ LIBRCF.DATA-U !
    LIBRARY-SERVICE-CONTENT-DIGEST@
        R@ LIBRCF.DIGEST RID-COPY
    R@ LIBRARY-RETAINED-CONTENT-FACTS-VALID? _LS12-assert
    R> DROP ;

: _LS12-replace-content  ( -- )
    _LS12-content-bytes 64 0 FILL
    S" service v2" _LS12-content-bytes SWAP MOVE
    _LS12-result-entry
    _LS12-content-bytes 10
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
    _LS12-replace-next _LS12-replace-content-value
        LIBRARY-SERVICE-PREPARE-CONTENT-NEXT
        LIBRARY-SERVICE-S-OK _LS12-status
    501 _LS12-progress
    _LS12-replace-next LIB-ENTRY-VALID? _LS12-assert
    _LS12-replace-content-value LIB-CONTENT-VALID? _LS12-assert

    _LS12-replace-request LIBRARY-DOCUMENT-REPLACE-REQUEST-INIT
    _LS12-replace-next _LS12-replace-request LSDRR.NEXT !
    _LS12-replace-content-value _LS12-replace-request LSDRR.CONTENT !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-replace-request LSDRR.EXPECTED-LOGICAL !
    _LS12-result-entry LIBE.DOMAIN-REVISION @
        _LS12-replace-request LSDRR.EXPECTED-DOMAIN !
    _LS12-replace-result _LS12-replace-request LSDRR.RESULT !
    _LS12-replace-request
        LIBRARY-DOCUMENT-REPLACE-REQUEST-VALID? _LS12-assert
    502 _LS12-progress
    _LS12-replace-request _LS12-service _LS12-work
        LIBRARY-SERVICE-REPLACE-CONTENT
        LIBRARY-SERVICE-S-OK _LS12-status
    503 _LS12-progress
    _LS12-replace-result _LS12-replace-next
        _LS12-entry= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        2 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        3 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LS12-assert
    _LS12-stack ;

: _LS12-read-retained  ( -- )
    _LS12-retained-request LIBRARY-RETAINED-READ-REQUEST-INIT
    _LS12-replace-result LIBE.ID
        _LS12-retained-request LSHRR.RID RID-COPY
    1 _LS12-retained-request LSHRR.DOMAIN !
    _LS12-retained-descriptor
        _LS12-retained-request LSHRR.DESCRIPTOR !
    _LS12-retained-request
        LIBRARY-RETAINED-READ-REQUEST-VALID? _LS12-assert
    _LS12-retained-request _LS12-service _LS12-work
        LIBRARY-SERVICE-READ-RETAINED-EXACT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-retained-descriptor
        LIBRARY-SERVICE-CONTENT-DESCRIPTOR-VALID? _LS12-assert
    _LS12-retained-descriptor
        LIBRARY-SERVICE-CONTENT-DOMAIN-REVISION@
        1 = _LS12-assert
    _LS12-retained-descriptor
        LIBRARY-SERVICE-CONTENT-REVISION@
        1 = _LS12-assert
    _LS12-retained-descriptor
        LIBRARY-SERVICE-CONTENT-KIND@
        LIB-KIND-MANAGED-DOCUMENT = _LS12-assert
    _LS12-retained-descriptor
        LIBRARY-SERVICE-CONTENT-SIZE@
        7 = _LS12-assert
    _LS12-retained-descriptor
        LIBRARY-SERVICE-CONTENT-DIGEST@
        _LS12-entry LIBE.CONTENT-DIGEST RID= _LS12-assert
    _LS12-retained-descriptor _LS12-retained-facts
        _LS12-retained-facts!
    _LS12-stack ;

: _LS12-restore-request!
  ( next retained-domain expected-logical expected-domain -- )
    >R >R >R
    _LS12-restore-request LIBRARY-DOCUMENT-RESTORE-REQUEST-INIT
    _LS12-restore-request LSDTR.NEXT !
    R> _LS12-restore-request LSDTR.RETAINED-DOMAIN !
    R> _LS12-restore-request LSDTR.EXPECTED-LOGICAL !
    R> _LS12-restore-request LSDTR.EXPECTED-DOMAIN !
    _LS12-restore-result _LS12-restore-request LSDTR.RESULT ! ;

: _LS12-restore-output-sentinel!  ( -- )
    _LS12-restore-result LIB-ENTRY-SIZE 0xA5 FILL
    _LS12-restore-result _LS12-pristine-entry
        LIB-ENTRY-SIZE MOVE ;

: _LS12-retained-restore  ( -- )
    _LS12-replace-content
    51 _LS12-progress
    _LS12-read-retained
    52 _LS12-progress

    \ The retained descriptor is projected into applet-domain semantic facts
    \ before the service prepares the next catalog value.
    _LS12-replace-result _LS12-retained-facts
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
    _LS12-restore-next
        LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-restore-next LIB-ENTRY-VALID? _LS12-assert
    53 _LS12-progress
    _LS12-restore-next 1 2
    _LS12-replace-result LIBE.DOMAIN-REVISION @
        _LS12-restore-request!
    _LS12-restore-request
        LIBRARY-DOCUMENT-RESTORE-REQUEST-VALID? _LS12-assert
    _LS12-restore-request _LS12-service _LS12-work
        LIBRARY-SERVICE-RESTORE-RETAINED
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-restore-result _LS12-restore-next
        _LS12-entry= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        3 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        4 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LS12-assert
    54 _LS12-progress

    \ Exact-value retries succeed before stale predicates or a missing
    \ retained-history lookup, and perform no semantic mutation.
    _LS12-restore-next 999 0 1 _LS12-restore-request!
    _LS12-restore-output-sentinel!
    _LS12-restore-request _LS12-service _LS12-work
        LIBRARY-SERVICE-RESTORE-RETAINED
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-restore-result _LS12-restore-next
        _LS12-entry= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        3 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        4 = _LS12-assert
    55 _LS12-progress

    \ A different valid next value lets the rejection contracts prove that
    \ conflict and missing-target results leave caller output untouched.
    _LS12-restore-result _LS12-retained-facts
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
    _LS12-restore-missing-next
        LIBRARY-SERVICE-PREPARE-RETAINED-RESTORE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-restore-missing-next LIB-ENTRY-VALID? _LS12-assert
    56 _LS12-progress

    _LS12-restore-missing-next 1 2 3 _LS12-restore-request!
    _LS12-restore-output-sentinel!
    _LS12-restore-request _LS12-service _LS12-work
        LIBRARY-SERVICE-RESTORE-RETAINED
        LIBRARY-SERVICE-S-CONFLICT _LS12-status
    _LS12-restore-result _LS12-pristine-entry
        _LS12-entry= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        3 = _LS12-assert
    57 _LS12-progress

    _LS12-restore-missing-next 999 3 3 _LS12-restore-request!
    _LS12-restore-output-sentinel!
    _LS12-restore-request
        LIBRARY-DOCUMENT-RESTORE-REQUEST-VALID? _LS12-assert
    _LS12-restore-request _LS12-service _LS12-work
        LIBRARY-SERVICE-RESTORE-RETAINED
        LIBRARY-SERVICE-S-NOT-FOUND _LS12-status
    _LS12-restore-result _LS12-pristine-entry
        _LS12-entry= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        3 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        4 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LS12-assert
    58 _LS12-progress

    \ A nested output may not alias live service machinery even when the DTO
    \ is otherwise structurally valid.
    _LS12-restore-missing-next 1 3 3 _LS12-restore-request!
    _LS12-work _LS12-restore-request LSDTR.RESULT !
    _LS12-restore-request
        LIBRARY-DOCUMENT-RESTORE-REQUEST-VALID? _LS12-assert
    _LS12-restore-request _LS12-service _LS12-work
        LIBRARY-SERVICE-RESTORE-RETAINED
        LIBRARY-SERVICE-S-INVALID _LS12-status
    _LS12-work LIBRARY-SERVICE-WORK-VALID? _LS12-assert
    59 _LS12-progress
    _LS12-stack ;

: _LS12-retained-compare  ( domain-a domain-b expected-equal -- )
    >R
    _LS12-compare-request
        LIBRARY-RETAINED-COMPARE-REQUEST-INIT
    _LS12-restore-next LIBE.ID
        _LS12-compare-request LSHCR.RID RID-COPY
    SWAP _LS12-compare-request LSHCR.DOMAIN-A !
    _LS12-compare-request LSHCR.DOMAIN-B !
    _LS12-compare-equal
        _LS12-compare-request LSHCR.EQUAL-OUT !
    _LS12-compare-request
        LIBRARY-RETAINED-COMPARE-REQUEST-VALID? _LS12-assert
    -1 _LS12-compare-equal !
    _LS12-compare-request _LS12-service _LS12-work
        LIBRARY-SERVICE-COMPARE-RETAINED
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-compare-equal @ R> = _LS12-assert
    _LS12-stack ;

: _LS12-retained-observations  ( -- )
    \ Domain 3 is a new revision which deliberately reuses domain 1's
    \ immutable content.  Exact retained comparisons distinguish it from
    \ domain 2 without materializing either body.
    1 3 -1 _LS12-retained-compare
    1 2 0 _LS12-retained-compare

    _LS12-history-request LIBRARY-HISTORY-QUERY-REQUEST-INIT
    _LS12-restore-next LIBE.ID _LS12-history-request
        LIBRARY-HISTORY-QUERY-RID!
        LIBPA-S-OK _LS12-status
    _LS12-history-rows 3 _LS12-history-page
        LIBRARY-HISTORY-PAGE-INIT
        LIBPA-S-OK _LS12-status
    _LS12-history-request _LS12-history-page
        _LS12-service _LS12-work LIBRARY-SERVICE-HISTORY-FIRST
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-history-page LIBQP.COUNT @ 3 = _LS12-assert
    0 _LS12-history-page LIBRARY-HISTORY-PAGE-ROW
    DUP LIBRARY-REVISION-SUMMARY-VALID? _LS12-assert
    DUP LIBRS.DOMAIN-REVISION @ 1 = _LS12-assert
    DUP LIBRS.CONTENT-REVISION @ 1 = _LS12-assert
    LIBRS.DIGEST _LS12-entry LIBE.CONTENT-DIGEST
        RID= _LS12-assert
    1 _LS12-history-page LIBRARY-HISTORY-PAGE-ROW
    DUP LIBRARY-REVISION-SUMMARY-VALID? _LS12-assert
    DUP LIBRS.DOMAIN-REVISION @ 2 = _LS12-assert
    LIBRS.CONTENT-REVISION @ 2 = _LS12-assert
    2 _LS12-history-page LIBRARY-HISTORY-PAGE-ROW
    DUP LIBRARY-REVISION-SUMMARY-VALID? _LS12-assert
    DUP LIBRS.DOMAIN-REVISION @ 3 = _LS12-assert
    DUP LIBRS.CONTENT-REVISION @ 3 = _LS12-assert
    LIBRS.DIGEST _LS12-entry LIBE.CONTENT-DIGEST
        RID= _LS12-assert

    _LS12-entry LIBE.RECEIPT LIBR.OPERATION-KEY
    LIBPA-OPERATION-DOCUMENT _LS12-restore-next LIBE.ID
        _LS12-operation=
    _LS12-stack ;

: _LS12-corpus-first  ( -- )
    _LS12-corpus-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _LS12-corpus-request
        LIBRARY-CORPUS-QUERY-REQUEST-VALID? _LS12-assert
    _LS12-corpus-row 1 _LS12-corpus-page
        LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LS12-status
    _LS12-corpus-request _LS12-corpus-page
        _LS12-service _LS12-work LIBRARY-SERVICE-CORPUS-FIRST
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-corpus-page LIBQP.COUNT @ 1 = _LS12-assert
    0 _LS12-corpus-page LIBRARY-CORPUS-PAGE-ROW
    DUP 0<> _LS12-assert
    DUP LIBRARY-QUERY-SUMMARY-VALID? _LS12-assert
    LIBQS.REF RREF.ID _LS12-entry LIBE.ID RID= _LS12-assert
    _LS12-stack ;

: _LS12-maintenance  ( -- )
    _LS12-inspection-a _LS12-service _LS12-work
        LIBRARY-SERVICE-INSPECT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-inspection-a
        LIBRARY-REPOSITORY-INSPECTION-SEALED? _LS12-assert
    _LS12-inspection-a LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-FALLBACK = _LS12-assert
    _LS12-inspection-a LRI.REPAIR-MASK @
        LIBRARY-REPOSITORY-REPAIR-MIRROR = _LS12-assert

    _LS12-repair-request LIBRARY-MIRROR-REPAIR-REQUEST-INIT
    _LS12-inspection-a
        _LS12-repair-request LSMRR.INSPECTION !
    _LS12-repaired-seal
        _LS12-repair-request LSMRR.REPAIRED-SEAL !
    _LS12-repair-request
        LIBRARY-MIRROR-REPAIR-REQUEST-VALID? _LS12-assert
    _LS12-repair-request _LS12-service _LS12-work
        LIBRARY-SERVICE-REPAIR-MIRROR
        LIBRARY-SERVICE-S-OK _LS12-status

    _LS12-inspection-b _LS12-service _LS12-work
        LIBRARY-SERVICE-INSPECT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-inspection-b
        LIBRARY-REPOSITORY-INSPECTION-SEALED? _LS12-assert
    _LS12-inspection-b LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-OK = _LS12-assert
    _LS12-inspection-b LRI.REPAIR-MASK @ 0= _LS12-assert
    _LS12-repaired-seal _LS12-inspection-b LRI.SEAL
        SHA3-256-COMPARE _LS12-assert

    \ A stale sealed observation cannot authorize another repair, and failure
    \ leaves the caller's proposed result span untouched.
    _LS12-repaired-seal SHA3-256-LEN 0xA5 FILL
    _LS12-pristine-seal SHA3-256-LEN 0xA5 FILL
    _LS12-repair-request _LS12-service _LS12-work
        LIBRARY-SERVICE-REPAIR-MIRROR
        LIBRARY-SERVICE-S-CONFLICT _LS12-status
    _LS12-repaired-seal _LS12-pristine-seal
        SHA3-256-COMPARE _LS12-assert

    \ Capacity negotiation publishes the exact whole-export requirement
    \ without touching a destination.
    _LS12-raw-request LIBRARY-RAW-EXPORT-REQUEST-INIT
    0 _LS12-raw-request LSRXR.DESTINATION !
    0 _LS12-raw-request LSRXR.CAPACITY !
    _LS12-inspection-b _LS12-raw-request LSRXR.INSPECTION !
    _LS12-raw-required _LS12-raw-request LSRXR.REQUIRED-OUT !
    -1 _LS12-raw-required !
    _LS12-raw-request
        LIBRARY-RAW-EXPORT-REQUEST-VALID? _LS12-assert
    _LS12-raw-request _LS12-service _LS12-work
        LIBRARY-SERVICE-RAW-EXPORT
        LIBRARY-SERVICE-S-CAPACITY _LS12-status
    _LS12-raw-required @
        _LS12-inspection-b LRI.RAW-REQUIRED @ = _LS12-assert
    _LS12-raw-required @ 0> _LS12-assert
    _LS12-stack ;

: _LS12-full-raw-export  ( -- )
    \ The successful retry exports the complete sealed observation in one
    \ call; no role, offset, or partial-service result is involved.
    _LR12-arena @ _LS12-raw-required @ ARENA-ALLOT
    DUP 0<> _LS12-assert
    DUP _LS12-raw !
    _LS12-raw-request LSRXR.DESTINATION !
    _LS12-raw-required @ _LS12-raw-request LSRXR.CAPACITY !
    -1 _LS12-raw-required !
    _LS12-raw-request
        LIBRARY-RAW-EXPORT-REQUEST-VALID? _LS12-assert
    _LS12-raw-request _LS12-service _LS12-work
        LIBRARY-SERVICE-RAW-EXPORT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-raw-required @
        _LS12-inspection-b LRI.RAW-REQUIRED @ = _LS12-assert
    _LS12-stack ;

: _LS12-collection-read-exact  ( expected-revision expected-status -- )
    >R
    _LS12-collection-read-request
        LIBRARY-COLLECTION-READ-REQUEST-INIT
    _LS12-collection-result LIBC.ID
        _LS12-collection-read-request LSCRR.RID RID-COPY
    _LS12-collection-read-request LSCRR.EXPECTED-REVISION !
    _LS12-collection-read
        _LS12-collection-read-request LSCRR.RESULT !
    _LS12-collection-read-request
        LIBRARY-COLLECTION-READ-REQUEST-VALID? _LS12-assert
    _LS12-collection-read LIBPA-COLLECTION-SIZE 0xA5 FILL
    _LS12-collection-read-request _LS12-service _LS12-work
        LIBRARY-SERVICE-READ-COLLECTION-EXACT
    R> _LS12-status ;

: _LS12-collection-initial!  ( -- )
    _LS12-many-rids RID-SIZE 129 * 0 FILL
    1 _LS12-many-rids !
    2 _LS12-many-rids RID-SIZE + !

    _LS12-many-collection LIBPA-COLLECTION-INIT
    _LS12-many-collection LIBC.ID RID-CLEAR
    0x100000 _LS12-many-collection LIBC.ID !
    _LS12-many-collection LIBC.OPERATION-KEY RID-CLEAR
    0x100001 _LS12-many-collection LIBC.OPERATION-KEY !
    1 _LS12-many-collection LIBC.REVISION !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        DUP _LS12-many-collection LIBC.MUTATION-SEQUENCE !
        _LS12-many-collection LIBC.CREATED-SEQUENCE !
    2 _LS12-many-collection LIBC.MEMBER-N !
    S" Service collection"
        _LS12-many-collection LIBC.TITLE
        _LS12-many-collection LIBC.TITLE-U _LS12-text!
    _LS12-many-collection _LS12-many-rids 2
        LIBPA-COLLECTION-REQUEST-SEAL!
        LIBPA-S-OK _LS12-status
    _LS12-many-collection LIBPA-COLLECTION-VALID? _LS12-assert

    _LS12-collection-request LIBRARY-COLLECTION-WRITE-REQUEST-INIT
    _LS12-many-collection
        _LS12-collection-request LSCWR.COLLECTION !
    _LS12-many-rids _LS12-collection-request LSCWR.MEMBERS !
    2 _LS12-collection-request LSCWR.MEMBER-N !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-collection-request LSCWR.EXPECTED-LOGICAL !
    0 _LS12-collection-request LSCWR.EXPECTED-REVISION !
    _LS12-collection-result
        _LS12-collection-request LSCWR.RESULT !
    _LS12-collection-request
        LIBRARY-COLLECTION-WRITE-REQUEST-VALID? _LS12-assert ;

: _LS12-collection-create-read-retry  ( -- )
    _LS12-collection-initial!
    _LS12-collection-request _LS12-service _LS12-work
        LIBRARY-SERVICE-CREATE-COLLECTION
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-collection-result _LS12-many-collection
        _LS12-collection= _LS12-assert
    _LS12-collection-result LIBC.REVISION @ 1 = _LS12-assert
    _LS12-collection-result LIBC.MEMBER-N @ 2 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        6 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        7 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-COLLECTION-COUNT@
        1 = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-MEMBERSHIP-COUNT@
        2 = _LS12-assert

    \ Create retries resolve the collection operation before considering the
    \ now-stale expected logical generation.
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation !
    _LS12-collection-result LIBPA-COLLECTION-SIZE 0xA5 FILL
    _LS12-collection-request _LS12-service _LS12-work
        LIBRARY-SERVICE-CREATE-COLLECTION
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-collection-result _LS12-many-collection
        _LS12-collection= _LS12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        6 = _LS12-assert
    1 LIBRARY-SERVICE-S-OK _LS12-collection-read-exact
    _LS12-collection-read _LS12-collection-result
        _LS12-collection= _LS12-assert

    _LS12-many-collection LIBC.OPERATION-KEY
    LIBPA-OPERATION-COLLECTION _LS12-many-collection LIBC.ID
        _LS12-operation=
    _LS12-stack ;

: _LS12-collection-replace-conflict
  ( expected-logical expected-revision -- )
    _LS12-collection-request LSCWR.EXPECTED-REVISION !
    _LS12-collection-request LSCWR.EXPECTED-LOGICAL !
    _LS12-collection-conflict
        _LS12-collection-request LSCWR.RESULT !
    _LS12-collection-conflict LIBPA-COLLECTION-SIZE 0xA5 FILL
    _LS12-pristine-collection LIBPA-COLLECTION-SIZE 0xA5 FILL
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before !
    _LS12-collection-request _LS12-service _LS12-work
        LIBRARY-SERVICE-REPLACE-COLLECTION
        LIBRARY-SERVICE-S-CONFLICT _LS12-status
    _LS12-collection-conflict _LS12-pristine-collection
        _LS12-collection= _LS12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before @ = _LS12-assert
    _LS12-stack ;

: _LS12-collection-replace  ( -- )
    _LS12-collection-result _LS12-collection-next
        LIBPA-COLLECTION-SIZE MOVE
    2 _LS12-collection-next LIBC.REVISION !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-collection-next LIBC.MUTATION-SEQUENCE !
    S" Revised service collection"
        _LS12-collection-next LIBC.TITLE
        _LS12-collection-next LIBC.TITLE-U _LS12-text!
    _LS12-collection-next LIBPA-COLLECTION-VALID? _LS12-assert

    _LS12-collection-request LIBRARY-COLLECTION-WRITE-REQUEST-INIT
    _LS12-collection-next
        _LS12-collection-request LSCWR.COLLECTION !
    _LS12-many-rids _LS12-collection-request LSCWR.MEMBERS !
    2 _LS12-collection-request LSCWR.MEMBER-N !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-collection-request LSCWR.EXPECTED-LOGICAL !
    1 _LS12-collection-request LSCWR.EXPECTED-REVISION !
    _LS12-collection-result
        _LS12-collection-request LSCWR.RESULT !
    _LS12-collection-request _LS12-service _LS12-work
        LIBRARY-SERVICE-REPLACE-COLLECTION
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-collection-result _LS12-collection-next
        _LS12-collection= _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        7 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        8 = _LS12-assert
    2 LIBRARY-SERVICE-S-OK _LS12-collection-read-exact
    _LS12-collection-read _LS12-collection-result
        _LS12-collection= _LS12-assert

    \ Collection replacement is optimistic rather than operation-key
    \ idempotent.  Isolate stale logical and stale collection predicates, and
    \ prove that each rejection preserves both caller output and physical and
    \ semantic generations.
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        1-
    2
    _LS12-collection-replace-conflict
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
    1
    _LS12-collection-replace-conflict
    1 LIBRARY-SERVICE-S-CONFLICT _LS12-collection-read-exact
    2 LIBRARY-SERVICE-S-OK _LS12-collection-read-exact
    _LS12-stack ;

: _LS12-collection-lifecycle-independent  ( -- )
    _LS12-capture-result LIB-LIFECYCLE-ARCHIVED
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
    _LS12-lifecycle-next
        LIBRARY-SERVICE-PREPARE-LIFECYCLE-NEXT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-lifecycle-request
        LIBRARY-DOCUMENT-REPLACE-REQUEST-INIT
    _LS12-lifecycle-next _LS12-lifecycle-request LSDRR.NEXT !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-lifecycle-request LSDRR.EXPECTED-LOGICAL !
    _LS12-capture-result LIBE.DOMAIN-REVISION @
        _LS12-lifecycle-request LSDRR.EXPECTED-DOMAIN !
    _LS12-lifecycle-result _LS12-lifecycle-request LSDRR.RESULT !
    _LS12-lifecycle-request _LS12-service _LS12-work
        LIBRARY-SERVICE-REPLACE-LIFECYCLE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-lifecycle-result LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        8 = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        9 = _LS12-assert

    \ Lifecycle belongs to the document identity.  The collection record and
    \ its independent membership edge remain byte-for-byte unchanged.
    2 LIBRARY-SERVICE-S-OK _LS12-collection-read-exact
    _LS12-collection-read _LS12-collection-result
        _LS12-collection= _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-MEMBERSHIP-COUNT@
        2 = _LS12-assert
    _LS12-stack ;

: _LS12-collection-tombstone-independent  ( -- )
    \ Destructive lifecycle publication erases the capture value without
    \ rewriting the collection record or its independent membership edge.
    _LS12-lifecycle-result
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
    _LS12-lifecycle-next
        LIBRARY-SERVICE-PREPARE-TOMBSTONE-NEXT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-lifecycle-next LIB-ENTRY-VALID? _LS12-assert
    _LS12-lifecycle-next LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _LS12-assert

    _LS12-lifecycle-request
        LIBRARY-DOCUMENT-REPLACE-REQUEST-INIT
    _LS12-lifecycle-next _LS12-lifecycle-request LSDRR.NEXT !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-lifecycle-request LSDRR.EXPECTED-LOGICAL !
    _LS12-lifecycle-result LIBE.DOMAIN-REVISION @
        _LS12-lifecycle-request LSDRR.EXPECTED-DOMAIN !
    _LS12-lifecycle-result _LS12-lifecycle-request LSDRR.RESULT !
    _LS12-lifecycle-request
        LIBRARY-DOCUMENT-REPLACE-REQUEST-VALID? _LS12-assert

    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-mutation-before !
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        _LS12-document-before !
    _LS12-lifecycle-request _LS12-service _LS12-work
        LIBRARY-SERVICE-TOMBSTONE
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-lifecycle-result _LS12-lifecycle-next
        _LS12-entry= _LS12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation @ > _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before @ 1+ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-mutation-before @ 1+ = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        _LS12-document-before @ = _LS12-assert

    2 LIBRARY-SERVICE-S-OK _LS12-collection-read-exact
    _LS12-collection-read _LS12-collection-result
        _LS12-collection= _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-MEMBERSHIP-COUNT@
        2 = _LS12-assert

    \ Reusing the original operation key with an otherwise identical capture
    \ and a fresh candidate RID resolves the terminal identity.  It cannot
    \ allocate a replacement or advance either generation.
    0 4 0x100052
        _LS12-capture-mismatch-entry _LS12-capture-mismatch-content
        _LS12-capture-value!
    _LS12-capture-request LIBRARY-DOCUMENT-CREATE-REQUEST-INIT
    _LS12-capture-mismatch-entry
        _LS12-capture-request LSDCR.ENTRY !
    _LS12-capture-mismatch-content
        _LS12-capture-request LSDCR.CONTENT !
    _LS12-capture-facts
        _LS12-capture-request LSDCR.FACTS-A !
    _LS12-capture-facts-u
        _LS12-capture-request LSDCR.FACTS-U !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-capture-request LSDCR.EXPECTED-LOGICAL !
    _LS12-capture-mismatch-result
        _LS12-capture-request LSDCR.RESULT !
    _LS12-capture-request
        LIBRARY-DOCUMENT-CREATE-REQUEST-VALID? _LS12-assert

    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation !
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before !
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-mutation-before !
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        _LS12-document-before !
    _LS12-capture-mismatch-result LIB-ENTRY-SIZE 0xA5 FILL
    _LS12-capture-request _LS12-service _LS12-work
        LIBRARY-SERVICE-IMPORT-CAPTURE
        LIBRARY-SERVICE-S-TOMBSTONED _LS12-status
    _LS12-capture-mismatch-result _LS12-lifecycle-result
        _LS12-entry= _LS12-assert
    _LS12-capture-mismatch-result LIBE.ID
        _LS12-capture-mismatch-entry LIBE.ID RID= 0= _LS12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@
        _LS12-generation @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before @ = _LS12-assert
    _LS12-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LS12-mutation-before @ = _LS12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        _LS12-document-before @ = _LS12-assert

    _LS12-capture-entry LIBE.RECEIPT LIBR.OPERATION-KEY
    LIBPA-OPERATION-DOCUMENT _LS12-lifecycle-result LIBE.ID
        _LS12-operation=
    _LS12-stack ;

: _LS12-compaction-lifecycle  ( -- )
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before !
    _LS12-compaction-request LIBRARY-COMPACTION-BIND-REQUEST-INIT
    1048576 _LS12-compaction-request LSCBR.BYTE-BUDGET !
    256 _LS12-compaction-request LSCBR.WORK-BUDGET !
    65536 _LS12-compaction-request LSCBR.STEP-BYTE-BUDGET !
    _LS12-compaction-request
        LIBRARY-COMPACTION-BIND-REQUEST-VALID? _LS12-assert
    _LS12-compaction-request _LS12-service _LS12-work
        LIBRARY-SERVICE-COMPACTION-BIND
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-work LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-IDLE = _LS12-assert
    _LS12-service _LS12-work LIBRARY-SERVICE-COMPACTION-BEGIN
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-work LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-BUILDING = _LS12-assert
    _LS12-service _LS12-work LIBRARY-SERVICE-COMPACTION-ABORT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-work LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-IDLE = _LS12-assert
    _LS12-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LS12-logical-before @ = _LS12-assert
    _LS12-stack ;

: _LS12-finalizers  ( -- )
    -1 _LS12-work _LSW.BUSY !
    _LS12-service _LS12-work LIBRARY-SERVICE-FINI
        LIBRARY-SERVICE-S-BUSY _LS12-status
    0 _LS12-work _LSW.BUSY !
    _LS12-service LIBRARY-SERVICE-VALID? _LS12-assert
    _LS12-work LIBRARY-SERVICE-WORK-VALID? _LS12-assert

    _LS12-work LIBRARY-SERVICE-WORK-FINI
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-work LIBRARY-SERVICE-WORK-VALID? 0= _LS12-assert
    _LS12-service _LS12-work LIBRARY-SERVICE-WORK-INIT
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-service _LS12-work LIBRARY-SERVICE-FINI
        LIBRARY-SERVICE-S-OK _LS12-status
    _LS12-service LIBRARY-SERVICE-VALID? 0= _LS12-assert
    _LS12-work LIBRARY-SERVICE-WORK-VALID? 0= _LS12-assert
    _LS12-stack ;

: _LS12-RUN  ( -- )
    0 _LS12-fails !
    0 _LS12-checks !
    0 _LR12-fails !
    0 _LR12-checks !
    DEPTH _LS12-depth !
    DEPTH _LR12-depth !

    _LR12-runtime-init
    _LR12-repository-a-init
    _LS12-repository-ready
    1 _LS12-progress
    _LS12-service-init
    2 _LS12-progress
    _LS12-maintenance
    3 _LS12-progress
    _LS12-full-raw-export
    4 _LS12-progress
    _LS12-managed-create
    5 _LS12-progress
    _LS12-retained-restore
    6 _LS12-progress
    _LS12-retained-observations
    7 _LS12-progress

    _LS12-capture-import
    8 _LS12-progress
    _LS12-corpus-first
    9 _LS12-progress
    _LS12-collection-create-read-retry
    10 _LS12-progress
    _LS12-collection-replace
    11 _LS12-progress

    _LS12-collection-lifecycle-independent
    12 _LS12-progress
    _LS12-collection-tombstone-independent
    13 _LS12-progress
    _LS12-compaction-lifecycle
    14 _LS12-progress
    _LS12-finalizers
    _LR12-finish

    _LR12-fails @ IF 1 _LS12-fails +! THEN
    _LS12-fails @ IF
        ." LIBRARY SERVICE L12 FAIL "
        _LS12-fails @ . ." /" _LS12-checks @ . CR
    ELSE
        ." LIBRARY SERVICE L12 PASS "
        _LS12-checks @ . CR
    THEN ;
