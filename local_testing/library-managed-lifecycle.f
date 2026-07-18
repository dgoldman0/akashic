\ =====================================================================
\  Gate 4 milestone 2: managed-document lifecycle and retained history
\ =====================================================================
\  This fixture stays entirely on the public Library owner surface.  It
\  proves the four-revision logical window across five replacements, then
\  carries the same resource through metadata, archive, restore-as-new,
\  and destructive tombstone transitions without losing its receipt.

VARIABLE _lml-fails
VARIABLE _lml-checks
VARIABLE _lml-depth
VARIABLE _lml-store-slot
VARIABLE _lml-vfs
VARIABLE _lml-old-vfs
VARIABLE _lml-arena
VARIABLE _lml-status
VARIABLE _lml-required
VARIABLE _lml-equal
VARIABLE _lml-expected
VARIABLE _lml-input-a
VARIABLE _lml-input-u
VARIABLE _lml-query-count
VARIABLE _lml-query-next
VARIABLE _lml-query-generation

CREATE _lml-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lml-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lml-rid LIB-DIGEST-SIZE ALLOT
CREATE _lml-unknown-rid LIB-DIGEST-SIZE ALLOT
CREATE _lml-rid-out LIB-DIGEST-SIZE ALLOT
CREATE _lml-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lml-result LIB-ENTRY-SIZE ALLOT
CREATE _lml-read-entry LIB-ENTRY-SIZE ALLOT
CREATE _lml-read-content LIB-CONTENT-SIZE ALLOT
CREATE _lml-retained-content LIB-CONTENT-SIZE ALLOT
CREATE _lml-metadata LIBRARY-METADATA-SIZE ALLOT
CREATE _lml-lineage LIB-LINEAGE-SIZE ALLOT
CREATE _lml-lineage-ref RREF-SIZE ALLOT
CREATE _lml-lineage-digest LIB-DIGEST-SIZE ALLOT
CREATE _lml-receipt-out LIB-RECEIPT-SIZE ALLOT
CREATE _lml-saved-receipt LIB-RECEIPT-SIZE ALLOT
CREATE _lml-query-summary LIBRARY-QUERY-SUMMARY-SIZE ALLOT
CREATE _lml-history
    LIBRARY-REVISION-SUMMARY-SIZE LIB-RETAINED-REVISION-MAX * ALLOT
LIB-CONTENT-MAX XBUF _lml-bytes

: _lml-store  ( -- store ) _lml-store-slot @ ;

: _lml-assert  ( flag -- )
    1 _lml-checks +!
    0= IF
        1 _lml-fails +!
        ." LIBRARY MANAGED LIFECYCLE ASSERT " _lml-checks @ . CR
    THEN ;

: _lml-stack  ( -- )
    DEPTH DUP _lml-depth @ <> IF
        ." LIBRARY MANAGED LIFECYCLE STACK "
        _lml-depth @ . ." -> " DUP . CR .S CR
    THEN
    _lml-depth @ = _lml-assert ;

: _lml-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _lml-summary  ( index -- summary )
    LIBRARY-REVISION-SUMMARY-SIZE * _lml-history + ;

: _lml-read-current  ( domain-revision -- )
    _lml-rid SWAP _lml-bytes LIB-CONTENT-MAX
        _lml-read-entry _lml-read-content _lml-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lml-status ! _lml-required ! ;

: _lml-read-retained  ( retained-domain-revision -- )
    _lml-rid SWAP _lml-bytes LIB-CONTENT-MAX
        _lml-retained-content _lml-store
        LIBRARY-VFS-STORE-READ-RETAINED-EXACT
    _lml-status ! _lml-required ! ;

: _lml-query-active  ( -- )
    0 0 _lml-query-summary 1 _lml-store
        LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lml-status ! _lml-query-generation !
    _lml-query-next ! _lml-query-count ! ;

: _lml-replace  ( expected-domain-revision a u -- )
    _lml-input-u ! _lml-input-a ! _lml-expected !
    _lml-rid _lml-expected @ _lml-input-a @ _lml-input-u @
        _lml-result _lml-store LIBRARY-VFS-STORE-REPLACE-MANAGED
        LIBSTORE-S-OK = _lml-assert
    _lml-result LIB-ENTRY-VALID? _lml-assert
    _lml-result LIBE.DOMAIN-REVISION @
        _lml-expected @ 1+ = _lml-assert
    _lml-result LIBE.CURRENT-CONTENT-REVISION @
        _lml-expected @ 1+ = _lml-assert ;

: _lml-check-receipt  ( expected-status -- )
    _lml-expected !
    _lml-rid-out LIB-DIGEST-SIZE 165 FILL
    _lml-receipt-out LIB-RECEIPT-SIZE 165 FILL
    _lml-key _lml-rid-out _lml-receipt-out _lml-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        _lml-expected @ = _lml-assert
    _lml-rid-out _lml-rid RID= _lml-assert
    _lml-receipt-out LIB-RECEIPT-VALID? _lml-assert
    _lml-receipt-out LIBR.OPERATION-KEY _lml-key RID= _lml-assert
    _lml-receipt-out LIB-RECEIPT-SIZE
        _lml-saved-receipt LIB-RECEIPT-SIZE COMPARE 0= _lml-assert ;

: _lml-create  ( -- )
    _lml-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    1 _lml-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lml-key _lml-request LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lml-assert
    S" Lifecycle document" _lml-request LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lml-assert
    S" revision one" _lml-request LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lml-assert
    LIB-MEDIA-TEXT-MARKDOWN _lml-request LIBMCR.MEDIA !
    _lml-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lml-assert
    _lml-request _lml-result _lml-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lml-assert
    _lml-result LIB-ENTRY-VALID? _lml-assert
    _lml-result LIBE.ID _lml-rid RID-COPY
    _lml-result LIBE.RECEIPT _lml-saved-receipt
        LIB-RECEIPT-SIZE CMOVE
    _lml-result LIBE.DOMAIN-REVISION @ 1 = _lml-assert
    _lml-result LIBE.CURRENT-CONTENT-REVISION @ 1 = _lml-assert
    _lml-result LIBE.OLDEST-CONTENT-REVISION @ 1 = _lml-assert
    _lml-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lml-assert
    _lml-stack ;

: _lml-five-replacements  ( -- )
    1 S" revision two" _lml-replace
    2 S" revision three" _lml-replace
    3 S" revision four" _lml-replace
    4 S" revision five" _lml-replace
    5 S" revision six" _lml-replace
    _lml-result LIBE.DOMAIN-REVISION @ 6 = _lml-assert
    _lml-result LIBE.CURRENT-CONTENT-REVISION @ 6 = _lml-assert
    _lml-result LIBE.OLDEST-CONTENT-REVISION @ 3 = _lml-assert
    _lml-store LIBRARY-VFS-STORE.GENERATION @ 7 = _lml-assert

    \ A stale writer cannot append content or advance publication.
    _lml-result LIB-ENTRY-SIZE 165 FILL
    _lml-rid 5 S" stale replacement" _lml-result _lml-store
        LIBRARY-VFS-STORE-REPLACE-MANAGED
        LIBSTORE-S-CONFLICT = _lml-assert
    _lml-result LIB-ENTRY-SIZE _lml-zero? _lml-assert
    _lml-store LIBRARY-VFS-STORE.GENERATION @ 7 = _lml-assert
    LIBSTORE-S-OK _lml-check-receipt
    _lml-stack ;

: _lml-retained-window  ( -- )
    _lml-rid 6 _lml-history LIB-RETAINED-REVISION-MAX _lml-store
        LIBRARY-VFS-STORE-LIST-RETAINED-REVISIONS
    _lml-status ! _lml-required !
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-required @ LIB-RETAINED-REVISION-MAX = _lml-assert
    0 _lml-summary LIBRS.DOMAIN-REVISION @ 6 = _lml-assert
    0 _lml-summary LIBRS.CONTENT-REVISION @ 6 = _lml-assert
    1 _lml-summary LIBRS.DOMAIN-REVISION @ 5 = _lml-assert
    1 _lml-summary LIBRS.CONTENT-REVISION @ 5 = _lml-assert
    2 _lml-summary LIBRS.DOMAIN-REVISION @ 4 = _lml-assert
    2 _lml-summary LIBRS.CONTENT-REVISION @ 4 = _lml-assert
    3 _lml-summary LIBRS.DOMAIN-REVISION @ 3 = _lml-assert
    3 _lml-summary LIBRS.CONTENT-REVISION @ 3 = _lml-assert

    6 _lml-read-retained
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-retained-content LIBCT-DATA$
        S" revision six" COMPARE 0= _lml-assert
    3 _lml-read-retained
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-retained-content LIBCT-DATA$
        S" revision three" COMPARE 0= _lml-assert
    2 _lml-read-retained
    _lml-status @ LIBSTORE-S-GONE = _lml-assert
    _lml-required @ 0= _lml-assert
    _lml-retained-content LIB-CONTENT-SIZE _lml-zero? _lml-assert

    _lml-rid 6 3 _lml-store LIBRARY-VFS-STORE-COMPARE-RETAINED
        _lml-status ! _lml-equal !
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-equal @ 0= _lml-assert
    _lml-rid 3 3 _lml-store LIBRARY-VFS-STORE-COMPARE-RETAINED
        _lml-status ! _lml-equal !
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-equal @ _lml-assert
    _lml-store LIBRARY-VFS-STORE-LAST-STATUS@
        LIBSTORE-S-OK = _lml-assert

    _lml-rid 2 3 _lml-store LIBRARY-VFS-STORE-COMPARE-RETAINED
        _lml-status ! _lml-equal !
    _lml-status @ LIBSTORE-S-GONE = _lml-assert
    _lml-equal @ 0= _lml-assert
    _lml-store LIBRARY-VFS-STORE-LAST-STATUS@
        LIBSTORE-S-GONE = _lml-assert

    _lml-unknown-rid 1 1 _lml-store
        LIBRARY-VFS-STORE-COMPARE-RETAINED
        _lml-status ! _lml-equal !
    _lml-status @ LIBSTORE-S-NOT-FOUND = _lml-assert
    _lml-equal @ 0= _lml-assert
    _lml-store LIBRARY-VFS-STORE-LAST-STATUS@
        LIBSTORE-S-NOT-FOUND = _lml-assert
    _lml-stack ;

: _lml-metadata-and-archive  ( -- )
    _lml-metadata LIBRARY-METADATA-INIT
    S" Curated lifecycle document" _lml-metadata
        LIBRARY-METADATA-TITLE! LIBSTORE-S-OK = _lml-assert
    S" lifecycle" 0 _lml-metadata
        LIBRARY-METADATA-TAG! LIBSTORE-S-OK = _lml-assert
    _lml-lineage LIB-LINEAGE-INIT
    LIB-LINEAGE-RELATION-DERIVED-FROM
        _lml-lineage LIBLN.RELATION !
    _lml-lineage-ref RREF-INIT
    _lml-lineage-ref RREF.ID LIB-DIGEST-SIZE 0x71 FILL
    S" retained lineage state" _lml-lineage-digest SHA3-256-HASH
    S" org.akashic.library" _lml-lineage-ref 3
        _lml-lineage-digest QLOC-DK-SEMANTIC-STATE
        S" org.akashic.library.state.v1"
        _lml-lineage LIBLN.LOCATOR QLOC-EXACT!
        QLOC-S-OK = _lml-assert
    _lml-lineage 0 _lml-metadata
        LIBRARY-METADATA-LINEAGE! LIBSTORE-S-OK = _lml-assert
    _lml-metadata LIBRARY-METADATA-VALID? _lml-assert
    _lml-rid 6 _lml-metadata _lml-result _lml-store
        LIBRARY-VFS-STORE-REPLACE-METADATA
        LIBSTORE-S-OK = _lml-assert
    _lml-result LIBE.DOMAIN-REVISION @ 7 = _lml-assert
    _lml-result LIBE.CURRENT-CONTENT-REVISION @ 6 = _lml-assert
    _lml-result LIBE-TITLE$
        S" Curated lifecycle document" COMPARE 0= _lml-assert
    _lml-result LIBE.TAG-N @ 1 = _lml-assert
    0 _lml-result LIBE-TAG LIB-TAG$
        S" lifecycle" COMPARE 0= _lml-assert
    _lml-result LIBE.LINEAGE-N @ 1 = _lml-assert
    0 _lml-result LIBE-LINEAGE LIB-LINEAGE-SIZE
        _lml-lineage LIB-LINEAGE-SIZE COMPARE 0= _lml-assert
    _lml-result LIBE.RECEIPT LIB-RECEIPT-SIZE
        _lml-saved-receipt LIB-RECEIPT-SIZE COMPARE 0= _lml-assert

    _lml-rid 7 _lml-result _lml-store LIBRARY-VFS-STORE-ARCHIVE
        LIBSTORE-S-OK = _lml-assert
    _lml-result LIBE.DOMAIN-REVISION @ 8 = _lml-assert
    _lml-result LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _lml-assert
    8 _lml-read-current
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-read-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _lml-assert
    _lml-read-content LIBCT-DATA$
        S" revision six" COMPARE 0= _lml-assert
    _lml-query-active
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-query-count @ 0= _lml-assert
    _lml-query-next @ -1 = _lml-assert
    _lml-query-generation @ 9 = _lml-assert
    _lml-query-summary LIBQS.REF RREF.ID RID-PRESENT? 0= _lml-assert
    3 _lml-read-retained
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-retained-content LIBCT-DATA$
        S" revision three" COMPARE 0= _lml-assert
    LIBSTORE-S-OK _lml-check-receipt
    _lml-stack ;

: _lml-unarchive-and-restore  ( -- )
    _lml-rid 8 _lml-result _lml-store LIBRARY-VFS-STORE-UNARCHIVE
        LIBSTORE-S-OK = _lml-assert
    _lml-result LIBE.DOMAIN-REVISION @ 9 = _lml-assert
    _lml-result LIBE.LIFECYCLE @ LIB-LIFECYCLE-ACTIVE = _lml-assert
    _lml-query-active
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-query-count @ 1 = _lml-assert
    _lml-query-next @ -1 = _lml-assert
    _lml-query-generation @ 10 = _lml-assert
    _lml-query-summary LIBQS.REF RREF.ID _lml-rid RID= _lml-assert
    _lml-query-summary LIBQS.DOMAIN-REVISION @ 9 = _lml-assert
    _lml-query-summary LIBQS.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _lml-assert

    _lml-rid 9 3 _lml-result _lml-store
        LIBRARY-VFS-STORE-RESTORE-RETAINED-EXACT
        LIBSTORE-S-OK = _lml-assert
    _lml-result LIB-ENTRY-VALID? _lml-assert
    _lml-result LIBE.DOMAIN-REVISION @ 10 = _lml-assert
    _lml-result LIBE.CURRENT-CONTENT-REVISION @ 7 = _lml-assert
    _lml-result LIBE.OLDEST-CONTENT-REVISION @ 4 = _lml-assert
    _lml-result LIBE.RECEIPT LIB-RECEIPT-SIZE
        _lml-saved-receipt LIB-RECEIPT-SIZE COMPARE 0= _lml-assert
    10 _lml-read-current
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-read-content LIBCT.CONTENT-REVISION @ 7 = _lml-assert
    _lml-read-content LIBCT.DOMAIN-REVISION @ 10 = _lml-assert
    _lml-read-content LIBCT-DATA$
        S" revision three" COMPARE 0= _lml-assert
    3 _lml-read-retained
    _lml-status @ LIBSTORE-S-GONE = _lml-assert

    _lml-rid 10 _lml-history LIB-RETAINED-REVISION-MAX _lml-store
        LIBRARY-VFS-STORE-LIST-RETAINED-REVISIONS
    _lml-status ! _lml-required !
    _lml-status @ LIBSTORE-S-OK = _lml-assert
    _lml-required @ 4 = _lml-assert
    0 _lml-summary LIBRS.DOMAIN-REVISION @ 10 = _lml-assert
    0 _lml-summary LIBRS.CONTENT-REVISION @ 7 = _lml-assert
    1 _lml-summary LIBRS.DOMAIN-REVISION @ 6 = _lml-assert
    2 _lml-summary LIBRS.DOMAIN-REVISION @ 5 = _lml-assert
    3 _lml-summary LIBRS.DOMAIN-REVISION @ 4 = _lml-assert
    LIBSTORE-S-OK _lml-check-receipt
    _lml-stack ;

: _lml-tombstone  ( -- )
    _lml-rid 10 _lml-result _lml-store
        LIBRARY-VFS-STORE-TOMBSTONE-DESTRUCTIVE
        LIBSTORE-S-OK = _lml-assert
    _lml-result LIB-ENTRY-VALID? _lml-assert
    _lml-result LIBE.DOMAIN-REVISION @ 11 = _lml-assert
    _lml-result LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lml-assert
    _lml-result LIBE.CONTENT-U @ 0= _lml-assert
    _lml-result LIBE.CURRENT-CONTENT-REVISION @ 0= _lml-assert
    _lml-result LIBE.RECEIPT LIB-RECEIPT-SIZE
        _lml-saved-receipt LIB-RECEIPT-SIZE COMPARE 0= _lml-assert

    11 _lml-read-current
    _lml-status @ LIBSTORE-S-TOMBSTONED = _lml-assert
    _lml-required @ 0= _lml-assert
    _lml-read-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lml-assert
    _lml-read-content LIB-CONTENT-SIZE _lml-zero? _lml-assert
    10 _lml-read-retained
    _lml-status @ LIBSTORE-S-TOMBSTONED = _lml-assert
    _lml-rid 10 10 _lml-store LIBRARY-VFS-STORE-COMPARE-RETAINED
        _lml-status ! _lml-equal !
    _lml-status @ LIBSTORE-S-TOMBSTONED = _lml-assert
    _lml-equal @ 0= _lml-assert
    _lml-store LIBRARY-VFS-STORE-LAST-STATUS@
        LIBSTORE-S-TOMBSTONED = _lml-assert
    LIBSTORE-S-TOMBSTONED _lml-check-receipt

    \ A retry of the original create key resolves to the retired RID.  It
    \ cannot allocate a replacement even though the request's generation is old.
    _lml-request _lml-result _lml-store LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-TOMBSTONED = _lml-assert
    _lml-result LIBE.ID _lml-rid RID= _lml-assert
    _lml-result LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lml-assert
    _lml-store LIBRARY-VFS-STORE.GENERATION @ 12 = _lml-assert
    _lml-stack ;

: _lml-run  ( -- )
    0 _lml-fails ! 0 _lml-checks ! DEPTH _lml-depth !
    VFS-CUR _lml-old-vfs !
    _lml-arena-id LIB-DIGEST-SIZE 0xA5 FILL
    _lml-key LIB-OPERATION-KEY-SIZE 0x51 FILL
    _lml-unknown-rid LIB-DIGEST-SIZE 0x72 FILL
    4194304 A-XMEM ARENA-NEW DUP 0= _lml-assert DROP
    DUP _lml-arena !
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lml-vfs ! 0<> _lml-assert
    _lml-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE ALLOCATE
        ABORT" LIBRARY MANAGED LIFECYCLE allocation" _lml-store-slot !
    _lml-vfs @ _lml-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lml-assert
    _lml-arena-id _lml-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lml-assert
    _lml-create
    _lml-five-replacements
    _lml-retained-window
    _lml-metadata-and-archive
    _lml-unarchive-and-restore
    _lml-tombstone
    _lml-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lml-assert
    _lml-store-slot @ FREE 0 _lml-store-slot !
    _lml-old-vfs @ VFS-USE
    _lml-vfs @ VFS-DESTROY
    _lml-stack
    _lml-fails @ ?DUP IF
        ." LIBRARY MANAGED LIFECYCLE FAIL " .
        ." / " _lml-checks @ . CR
    ELSE
        ." LIBRARY MANAGED LIFECYCLE PASS " _lml-checks @ . CR
    THEN ;

_lml-run
