\ Current-format two-process MP64FS acceptance for the L12 Library owner.
\
\ This is deliberately the smallest durable process-isolation gate: one
\ managed create, current query/read/content/receipt readback, and exact-key
\ replay.  Broader lifecycle, retained-history, capture, collection, query,
\ and projection parity belongs to the focused same-VFS and applet gates.
\ The parent process carries only serialized MP64FS bytes and the printed RID
\ into the second guest.

PROVIDED akashic-library-cold-l12-contracts

VARIABLE _LC12-fails
VARIABLE _LC12-checks
VARIABLE _LC12-cold?
VARIABLE _LC12-old-vfs
VARIABLE _LC12-vfs
VARIABLE _LC12-arena
VARIABLE _LC12-range-u
VARIABLE _LC12-sink-offset
VARIABLE _LC12-sink-a
VARIABLE _LC12-sink-u
VARIABLE _LC12-operation-kind
VARIABLE _LC12-generation-before
VARIABLE _LC12-logical-before
VARIABLE _LC12-mutation-before

/BLOCK-DEVICE XBUF _LC12-bd
/VOLUME XBUF _LC12-volume

PERSIST-PAGE-CACHE-SIZE XBUF _LC12-cache-0
PERSIST-PAGE-CACHE-SIZE XBUF _LC12-cache-1
PERSIST-PAGE-CACHE-SIZE XBUF _LC12-builder-cache-0
PERSIST-PAGE-CACHE-SIZE XBUF _LC12-builder-cache-1
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LC12-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LC12-cache-1-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LC12-builder-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LC12-builder-cache-1-memory
GUARD _LC12-source-guard
GUARD _LC12-builder-guard

LIBRARY-REPOSITORY-SIZE XBUF _LC12-repository
LIBRARY-REPOSITORY-WORK-SIZE XBUF _LC12-repository-work
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LC12-record
LIBRARY-REPOSITORY-STAGE-BUFFER-MIN XBUF _LC12-stage
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LC12-builder-record
512 XBUF _LC12-compact-buffer
8192 CONSTANT _LC12-audit-map-capacity
_LC12-audit-map-capacity XBUF _LC12-audit-map
_LC12-audit-map-capacity XBUF _LC12-builder-audit-map

LIBRARY-SERVICE-SIZE XBUF _LC12-service
LIBRARY-SERVICE-WORK-SIZE XBUF _LC12-service-work
LIBRARY-DOCUMENT-INITIAL-DRAFT-SIZE XBUF _LC12-draft
LIB-ENTRY-SIZE XBUF _LC12-entry
LIB-CONTENT-SIZE XBUF _LC12-content
LIB-ENTRY-SIZE XBUF _LC12-result
LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE XBUF _LC12-create-request

LIBRARY-CORPUS-QUERY-REQUEST-SIZE XBUF _LC12-query-request
LIBRARY-QUERY-PAGE-SIZE XBUF _LC12-query-page
LIBRARY-QUERY-SUMMARY-SIZE XBUF _LC12-query-row

LIBRARY-DOCUMENT-READ-REQUEST-SIZE XBUF _LC12-read-request
LIB-ENTRY-SIZE XBUF _LC12-read-entry
LIBRARY-SERVICE-CONTENT-DESCRIPTOR-SIZE XBUF _LC12-descriptor
LIBRARY-CONTENT-DELIVERY-REQUEST-SIZE XBUF _LC12-delivery-request
LIBRARY-OPERATION-LOOKUP-REQUEST-SIZE XBUF _LC12-operation-request

CREATE _LC12-bootstrap RID-SIZE ALLOT
CREATE _LC12-expected-rid RID-SIZE ALLOT
CREATE _LC12-operation-rid RID-SIZE ALLOT
\ This buffer is immutable from request preparation through the cold replay.
\ A LIB-CONTENT value borrows its DATA-A span; reusing that span for a later
\ candidate would silently change the supposedly exact retry.
CREATE _LC12-content-bytes 64 ALLOT
CREATE _LC12-read-bytes 64 ALLOT

: _LC12-assert  ( flag -- )
    1 _LC12-checks +!
    0= IF
        1 _LC12-fails +!
        _LC12-cold? @ IF
            ." LIBRARY MANAGED COLD ASSERT "
        ELSE
            ." LIBRARY MANAGED FIRST ASSERT "
        THEN
        _LC12-checks @ . CR
    THEN ;

: _LC12-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY MANAGED STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LC12-assert ;

: _LC12-progress  ( phase -- )
    ." LIBRARY MANAGED PHASE " . CR
    0 0xFFFFFF0000000006 C! ;

: _LC12-text!  ( source-a source-u destination length-cell -- )
    >R
    OVER R@ !
    SWAP MOVE
    R> DROP ;

: _LC12-entry=  ( entry-a entry-b -- flag )
    LIB-ENTRY-SIZE SWAP LIB-ENTRY-SIZE COMPARE 0= ;

: _LC12-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _LC12-status ;

: _LC12-runtime-init  ( -- )
    VFS-CUR _LC12-old-vfs !
    _LC12-bd BD-OPEN THROW
    _LC12-bd _LC12-volume VOL-RAW THROW
    2097152 A-XMEM ARENA-NEW
    DUP 0= _LC12-assert DROP _LC12-arena !
    _LC12-arena @ _LC12-volume VMP-NEW ?DUP IF THROW THEN
    DUP _LC12-vfs ! DUP 0<> _LC12-assert VFS-USE

    _LC12-cache-0-memory _LC12-cache-0 _LC12-cache-init
    _LC12-cache-1-memory _LC12-cache-1 _LC12-cache-init
    _LC12-builder-cache-0-memory
        _LC12-builder-cache-0 _LC12-cache-init
    _LC12-builder-cache-1-memory
        _LC12-builder-cache-1 _LC12-cache-init

    _LC12-vfs @
    _LC12-cache-0 _LC12-cache-1
    _LC12-builder-cache-0 _LC12-builder-cache-1
    _LC12-source-guard _LC12-builder-guard
    0 0 _LC12-repository LIBRARY-REPOSITORY-INIT
        LIBRARY-REPOSITORY-S-OK _LC12-status

    _LC12-record LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LC12-stage LIBRARY-REPOSITORY-STAGE-BUFFER-MIN
    _LC12-builder-record LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LC12-compact-buffer 512
    _LC12-audit-map _LC12-audit-map-capacity
    _LC12-builder-audit-map _LC12-audit-map-capacity
    _LC12-repository _LC12-repository-work
        LIBRARY-REPOSITORY-WORK-INIT
        LIBRARY-REPOSITORY-S-OK _LC12-status ;

: _LC12-service-init  ( -- )
    _LC12-repository _LC12-repository-work _LC12-service
        LIBRARY-SERVICE-INIT
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-service _LC12-service-work LIBRARY-SERVICE-WORK-INIT
        LIBRARY-SERVICE-S-OK _LC12-status ;

: _LC12-repository-first  ( -- )
    _LC12-repository _LC12-repository-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-ABSENT _LC12-status
    3 _LC12-progress
    _LC12-repository _LC12-repository-work LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-OK _LC12-status
    4 _LC12-progress
    _LC12-bootstrap RID-SIZE 0xA4 FILL
    _LC12-bootstrap _LC12-repository _LC12-repository-work
        LIBRARY-REPOSITORY-BOOTSTRAP
        LIBRARY-REPOSITORY-S-OK _LC12-status
    5 _LC12-progress
    _LC12-repository-work LIBRARY-REPOSITORY-LOGICAL-GENERATION@
        0= _LC12-assert ;

: _LC12-repository-cold  ( -- )
    _LC12-repository _LC12-repository-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-OK _LC12-status
    22 _LC12-progress
    _LC12-repository-work LIBRARY-REPOSITORY-LOGICAL-GENERATION@
        1 = _LC12-assert
    _LC12-repository-work LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LC12-assert
    _LC12-repository-work LIBRARY-REPOSITORY-COLLECTION-COUNT@
        0= _LC12-assert
    _LC12-repository-work LIBRARY-REPOSITORY-MEMBERSHIP-COUNT@
        0= _LC12-assert ;

: _LC12-create-value!  ( -- )
    _LC12-content-bytes 64 0 FILL
    S" durable managed content" _LC12-content-bytes SWAP MOVE
    _LC12-draft LIBRARY-DOCUMENT-INITIAL-DRAFT-INIT
    _LC12-draft LSDID.ID RID-CLEAR
    1 _LC12-draft LSDID.ID !
    _LC12-draft LSDID.OPERATION-KEY RID-CLEAR
    0x51 _LC12-draft LSDID.OPERATION-KEY !
    LIB-KIND-MANAGED-DOCUMENT _LC12-draft LSDID.KIND !
    LIB-MEDIA-TEXT-MARKDOWN _LC12-draft LSDID.MEDIA !
    1 _LC12-draft LSDID.MUTATION-SEQUENCE !
    _LC12-content-bytes _LC12-draft LSDID.CONTENT-A !
    23 _LC12-draft LSDID.CONTENT-U !
    S" Cold-process note"
        _LC12-draft LSDID.TITLE
        _LC12-draft LSDID.TITLE-U _LC12-text!
    _LC12-draft _LC12-entry _LC12-content
        LIBRARY-SERVICE-PREPARE-MANAGED-CREATE
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-create-request LIBRARY-DOCUMENT-CREATE-REQUEST-INIT
    _LC12-entry _LC12-create-request LSDCR.ENTRY !
    _LC12-content _LC12-create-request LSDCR.CONTENT !
    0 _LC12-create-request LSDCR.EXPECTED-LOGICAL !
    _LC12-result _LC12-create-request LSDCR.RESULT !
    _LC12-create-request LIBRARY-DOCUMENT-CREATE-REQUEST-VALID?
        _LC12-assert ;

: _LC12-query  ( -- )
    _LC12-query-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _LC12-query-row 1 _LC12-query-page
        LIBRARY-CORPUS-PAGE-INIT LIBPA-S-OK _LC12-status
    _LC12-query-request _LC12-query-page
        _LC12-service _LC12-service-work
        LIBRARY-SERVICE-CORPUS-FIRST
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-query-page LIBQP.COUNT @ 1 = _LC12-assert
    0 _LC12-query-page LIBRARY-CORPUS-PAGE-ROW
    DUP 0<> _LC12-assert
    DUP LIBRARY-QUERY-SUMMARY-VALID? _LC12-assert
    DUP LIBQS.REF RREF.ID _LC12-expected-rid RID= _LC12-assert
    DUP LIBQS.DOMAIN-REVISION @ 1 = _LC12-assert
    DUP LIBQS.KIND @ LIB-KIND-MANAGED-DOCUMENT = _LC12-assert
    DUP LIBQS.LIFECYCLE @ LIB-LIFECYCLE-ACTIVE = _LC12-assert
    DUP LIBQS.MEDIA @ LIB-MEDIA-TEXT-MARKDOWN = _LC12-assert
    DUP LIBQS.CONTENT-U @ 23 = _LC12-assert
    DUP LIBQS.CONTENT-DIGEST _LC12-entry LIBE.CONTENT-DIGEST
        RID= _LC12-assert
    LIBQS-TITLE$ S" Cold-process note" COMPARE 0= _LC12-assert ;

: _LC12-range-sink
  ( logical-offset source-a source-u context -- persist-status )
    >R
    _LC12-sink-u !
    _LC12-sink-a !
    _LC12-sink-offset !
    _LC12-sink-offset @ 0<
    _LC12-sink-u @ 0< OR
    _LC12-sink-offset @ _LC12-sink-u @ + 64 > OR IF
        R> DROP PERSIST-S-CORRUPT EXIT
    THEN
    _LC12-sink-a @
    R@ _LC12-sink-offset @ +
    _LC12-sink-u @ MOVE
    _LC12-sink-offset @ _LC12-sink-u @ +
        _LC12-range-u @ MAX _LC12-range-u !
    R> DROP PERSIST-S-OK ;

: _LC12-read  ( -- )
    _LC12-read-request LIBRARY-DOCUMENT-READ-REQUEST-INIT
    _LC12-expected-rid _LC12-read-request LSDQR.RID RID-COPY
    1 _LC12-read-request LSDQR.EXPECTED-DOMAIN !
    _LC12-read-entry _LC12-read-request LSDQR.ENTRY !
    _LC12-descriptor _LC12-read-request LSDQR.DESCRIPTOR !
    _LC12-read-request _LC12-service _LC12-service-work
        LIBRARY-SERVICE-READ-EXACT
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-read-entry LIB-ENTRY-VALID? _LC12-assert
    _LC12-read-entry _LC12-entry _LC12-entry= _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.METHOD @
        LIB-IMPORT-CREATED = _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.OPERATION-KEY
        _LC12-draft LSDID.OPERATION-KEY RID= _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-REVISION @
        1 = _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-U @
        23 = _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.INITIAL-MEDIA @
        LIB-MEDIA-TEXT-MARKDOWN = _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-DIGEST
        _LC12-entry LIBE.CONTENT-DIGEST RID= _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.REQUEST-SEAL
        RID-PRESENT? _LC12-assert
    _LC12-read-entry LIBE.RECEIPT LIBR.SOURCE-OWNER-U @
        0= _LC12-assert
    _LC12-descriptor
        LIBRARY-SERVICE-CONTENT-DESCRIPTOR-VALID? _LC12-assert
    _LC12-descriptor LIBRARY-SERVICE-CONTENT-SIZE@
        23 = _LC12-assert

    _LC12-read-bytes 64 0 FILL
    0 _LC12-range-u !
    _LC12-delivery-request LIBRARY-CONTENT-DELIVERY-REQUEST-INIT
    _LC12-descriptor _LC12-delivery-request LSCDR.DESCRIPTOR !
    0 _LC12-delivery-request LSCDR.OFFSET !
    23 _LC12-delivery-request LSCDR.REQUESTED !
    ['] _LC12-range-sink _LC12-delivery-request LSCDR.SINK-XT !
    _LC12-read-bytes _LC12-delivery-request LSCDR.SINK-CONTEXT !
    _LC12-delivery-request _LC12-service _LC12-service-work
        LIBRARY-SERVICE-CONTENT-RANGE
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-range-u @ 23 = _LC12-assert
    _LC12-read-bytes 23 S" durable managed content"
        COMPARE 0= _LC12-assert ;

: _LC12-operation-lookup  ( -- )
    _LC12-operation-request LIBRARY-OPERATION-LOOKUP-REQUEST-INIT
    _LC12-draft LSDID.OPERATION-KEY
        _LC12-operation-request LSOLR.OPERATION-KEY RID-COPY
    _LC12-operation-kind
        _LC12-operation-request LSOLR.KIND-OUT !
    _LC12-operation-rid
        _LC12-operation-request LSOLR.RID-OUT !
    _LC12-operation-request _LC12-service _LC12-service-work
        LIBRARY-SERVICE-LOOKUP-OPERATION
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-operation-kind @
        LIBPA-OPERATION-DOCUMENT = _LC12-assert
    _LC12-operation-rid _LC12-expected-rid RID= _LC12-assert ;

: _LC12-semantic-readback  ( -- )
    _LC12-query
    _LC12-read
    _LC12-operation-lookup ;

: _LC12-replay-without-mutation  ( -- )
    _LC12-repository LIBRARY-REPOSITORY-GENERATION@
        _LC12-generation-before !
    _LC12-service-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LC12-logical-before !
    _LC12-service-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LC12-mutation-before !

    _LC12-result LIB-ENTRY-SIZE 0xA5 FILL
    _LC12-create-request _LC12-service _LC12-service-work
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-result _LC12-entry _LC12-entry= _LC12-assert

    _LC12-repository LIBRARY-REPOSITORY-GENERATION@
        _LC12-generation-before @ = _LC12-assert
    _LC12-service-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        _LC12-logical-before @ = _LC12-assert
    _LC12-service-work LIBRARY-SERVICE-NEXT-MUTATION@
        _LC12-mutation-before @ = _LC12-assert
    _LC12-repository-work LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LC12-assert ;

: _LC12-hex-digit  ( nibble -- )
    DUP 10 < IF [CHAR] 0 + ELSE 10 - [CHAR] A + THEN EMIT ;

: _LC12-hex-byte  ( byte -- )
    DUP 16 / _LC12-hex-digit 15 AND _LC12-hex-digit ;

: _LC12-rid.  ( rid -- )
    RID-SIZE 0 DO DUP I + C@ _LC12-hex-byte LOOP DROP ;

: _LC12-finish  ( -- )
    _LC12-vfs @ VFS-SYNC 0= _LC12-assert
    _LC12-service _LC12-service-work LIBRARY-SERVICE-FINI
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-repository _LC12-repository-work LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK _LC12-status
    _LC12-vfs @ VFS-SYNC 0= _LC12-assert
    _LC12-old-vfs @ VFS-USE
    _LC12-vfs @ VFS-DESTROY
    _LC12-volume VOL-CLOSE 0= _LC12-assert
    _LC12-bd BD-CLOSE 0= _LC12-assert ;

: _LC12-FIRST-RUN  ( -- )
    0 _LC12-cold? !
    0 _LC12-fails !
    0 _LC12-checks !
    1 _LC12-progress
    _LC12-runtime-init
    2 _LC12-progress
    _LC12-repository-first
    _LC12-service-init
    6 _LC12-progress
    _LC12-create-value!
    _LC12-create-request _LC12-service _LC12-service-work
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK _LC12-status
    _LC12-result LIB-ENTRY-VALID? _LC12-assert
    _LC12-result _LC12-entry _LC12-entry= _LC12-assert
    _LC12-result LIBE.ID _LC12-expected-rid RID-COPY
    _LC12-service-work LIBRARY-SERVICE-LOGICAL-GENERATION@
        1 = _LC12-assert
    _LC12-service-work LIBRARY-SERVICE-NEXT-MUTATION@
        2 = _LC12-assert
    _LC12-repository-work LIBRARY-REPOSITORY-DOCUMENT-COUNT@
        1 = _LC12-assert
    7 _LC12-progress
    _LC12-semantic-readback
    8 _LC12-progress
    _LC12-finish
    _LC12-fails @ IF
        ." LIBRARY MANAGED FIRST BOOT FAIL "
            _LC12-fails @ . ." / " _LC12-checks @ . CR
    ELSE
        ." LIBRARY MANAGED FIRST RID "
            _LC12-expected-rid _LC12-rid. CR
        ." LIBRARY MANAGED FIRST BOOT PASS "
            _LC12-checks @ . CR
    THEN ;

: _LC12-COLD-RUN  ( expected-rid -- )
    -1 _LC12-cold? !
    0 _LC12-fails !
    0 _LC12-checks !
    _LC12-expected-rid RID-COPY
    20 _LC12-progress
    _LC12-runtime-init
    21 _LC12-progress
    _LC12-repository-cold
    _LC12-service-init
    23 _LC12-progress
    _LC12-service-work LIBRARY-SERVICE-NEXT-MUTATION@
        2 = _LC12-assert
    \ Reconstruct the exact public value and retain its immutable content span
    \ through both readback and the retry.
    _LC12-create-value!
    _LC12-entry LIBE.ID _LC12-expected-rid RID= _LC12-assert
    _LC12-semantic-readback
    24 _LC12-progress
    _LC12-replay-without-mutation
    25 _LC12-progress
    _LC12-semantic-readback
    26 _LC12-progress
    _LC12-finish
    _LC12-fails @ IF
        ." LIBRARY MANAGED COLD BOOT FAIL "
            _LC12-fails @ . ." / " _LC12-checks @ . CR
    ELSE
        ." LIBRARY MANAGED COLD BOOT PASS "
            _LC12-checks @ . CR
    THEN ;
