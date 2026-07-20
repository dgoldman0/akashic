\ =====================================================================
\  Gate 4 milestone 2: immutable captures and RID-based collections
\ =====================================================================
\  This fixture uses only the public Library owner surface.  It proves
\  copied-snapshot import identity and receipts, then proves that
\  collection membership is an independent RID relationship: removing
\  a member does not delete it, and lifecycle changes do not rewrite the
\  collection that names it.

VARIABLE _lcc-fails
VARIABLE _lcc-checks
VARIABLE _lcc-depth
VARIABLE _lcc-store-slot
VARIABLE _lcc-vfs
VARIABLE _lcc-old-vfs
VARIABLE _lcc-arena
VARIABLE _lcc-status
VARIABLE _lcc-required

CREATE _lcc-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lcc-key-a LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lcc-key-b LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lcc-collection-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lcc-rid-a LIB-DIGEST-SIZE ALLOT
CREATE _lcc-rid-b LIB-DIGEST-SIZE ALLOT
CREATE _lcc-unknown-rid LIB-DIGEST-SIZE ALLOT
CREATE _lcc-collection-rid LIB-DIGEST-SIZE ALLOT
CREATE _lcc-rid-out LIB-DIGEST-SIZE ALLOT
CREATE _lcc-origin LIB-ORIGIN-SIZE ALLOT
CREATE _lcc-request-a LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE ALLOT
CREATE _lcc-request-b LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE ALLOT
CREATE _lcc-managed-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lcc-entry LIB-ENTRY-SIZE ALLOT
CREATE _lcc-entry2 LIB-ENTRY-SIZE ALLOT
CREATE _lcc-identity-entry LIB-ENTRY-SIZE ALLOT
CREATE _lcc-store-before LIBRARY-VFS-STORE-SIZE ALLOT
CREATE _lcc-read-entry LIB-ENTRY-SIZE ALLOT
CREATE _lcc-read-content LIB-CONTENT-SIZE ALLOT
CREATE _lcc-receipt LIB-RECEIPT-SIZE ALLOT
CREATE _lcc-members LIB-DIGEST-SIZE 2 * ALLOT
CREATE _lcc-create-request
    LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _lcc-replace-request
    LIBRARY-COLLECTION-REPLACE-REQUEST-SIZE ALLOT
CREATE _lcc-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
CREATE _lcc-view2 LIBRARY-COLLECTION-VIEW-SIZE ALLOT
LIB-CONTENT-MAX XBUF _lcc-bytes

: _lcc-store  ( -- store ) _lcc-store-slot @ ;

: _lcc-assert  ( flag -- )
    1 _lcc-checks +!
    0= IF
        1 _lcc-fails +!
        ." LIBRARY CAPTURE COLLECTION ASSERT " _lcc-checks @ . CR
    THEN ;

: _lcc-stack  ( -- )
    DEPTH DUP _lcc-depth @ <> IF
        ." LIBRARY CAPTURE COLLECTION STACK "
        _lcc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _lcc-depth @ = _lcc-assert ;

: _lcc-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _lcc-build-origin  ( -- )
    _lcc-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _lcc-origin LIBO.KIND !
    S" /imports/shared-capture.md"
        DUP _lcc-origin LIBO.VFS LIBV.PATH-U !
        _lcc-origin LIBO.VFS LIBV.PATH SWAP CMOVE
    S" immutable copied bytes"
        DUP _lcc-origin LIBO.VFS LIBV.CONTENT-U !
        _lcc-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    QLOC-DK-PROJECTION-CONTENT
        _lcc-origin LIBO.VFS LIBV.DIGEST-KIND !
    _lcc-origin LIB-ORIGIN-VALID? _lcc-assert ;

: _lcc-build-capture  ( key expected-generation request -- )
    >R
    R@ LIBRARY-CAPTURE-IMPORT-REQUEST-INIT
    R@ LIBCIR.EXPECTED-CATALOG-GENERATION !
    R@ LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!
        LIBSTORE-S-OK = _lcc-assert
    S" Shared imported snapshot" R@
        LIBRARY-CAPTURE-IMPORT-TITLE!
        LIBSTORE-S-OK = _lcc-assert
    S" immutable copied bytes" R@
        LIBRARY-CAPTURE-IMPORT-CONTENT!
        LIBSTORE-S-OK = _lcc-assert
    LIB-MEDIA-TEXT-MARKDOWN R@ LIBCIR.MEDIA !
    _lcc-origin R@ LIBRARY-CAPTURE-IMPORT-ORIGIN!
        LIBSTORE-S-OK = _lcc-assert
    R@ LIBRARY-CAPTURE-IMPORT-REQUEST-VALID? _lcc-assert
    R> DROP ;

: _lcc-read  ( rid domain-revision -- )
    _lcc-bytes LIB-CONTENT-MAX _lcc-read-entry _lcc-read-content
        _lcc-store LIBRARY-VFS-STORE-READ-EXACT
    _lcc-status ! _lcc-required ! ;

: _lcc-read-identity  ( rid -- )
    _lcc-identity-entry _lcc-store
        LIBRARY-VFS-STORE-READ-IDENTITY _lcc-status ! ;

: _lcc-fail-catalog-read  ( destination length fd -- ior )
    OVER LIB-CATALOG-RECORD-SIZE = IF
        DROP 2DROP -1 EXIT
    THEN
    VFS-READ-EXACT ;

: _lcc-assert-view-member  ( rid index view -- )
    LIBCV-MEMBER RID= _lcc-assert ;

: _lcc-imports  ( -- )
    _lcc-key-a 1 _lcc-request-a _lcc-build-capture
    _lcc-request-a _lcc-entry _lcc-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _lcc-assert
    _lcc-entry LIB-ENTRY-VALID? _lcc-assert
    _lcc-entry LIBE.ID _lcc-rid-a RID-COPY
    _lcc-entry LIBE.KIND @ LIB-KIND-CAPTURE = _lcc-assert
    _lcc-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _lcc-assert
    _lcc-entry LIBE.DOMAIN-REVISION @ 1 = _lcc-assert
    _lcc-entry LIBE.CURRENT-CONTENT-REVISION @ 1 = _lcc-assert
    _lcc-entry LIBE.RECEIPT LIBR.METHOD @
        LIB-IMPORT-VFS-SNAPSHOT = _lcc-assert
    _lcc-entry LIBE.ORIGIN LIB-ORIGIN-SIZE
        _lcc-origin LIB-ORIGIN-SIZE COMPARE 0= _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lcc-assert

    \ Same-key/same-request is a readback, not another publication.
    _lcc-entry2 LIB-ENTRY-SIZE 165 FILL
    _lcc-request-a _lcc-entry2 _lcc-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _lcc-assert
    _lcc-entry2 LIBE.ID _lcc-rid-a RID= _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lcc-assert

    \ The same copied snapshot under a distinct key is a distinct capture.
    _lcc-key-b 2 _lcc-request-b _lcc-build-capture
    _lcc-request-b _lcc-entry2 _lcc-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _lcc-assert
    _lcc-entry2 LIBE.ID _lcc-rid-b RID-COPY
    _lcc-rid-a _lcc-rid-b RID= 0= _lcc-assert
    _lcc-entry LIBE.CONTENT-DIGEST _lcc-entry2 LIBE.CONTENT-DIGEST
        SHA3-256-COMPARE _lcc-assert
    _lcc-entry LIBE.ORIGIN LIB-ORIGIN-SIZE
        _lcc-entry2 LIBE.ORIGIN LIB-ORIGIN-SIZE COMPARE 0= _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lcc-assert

    \ Same key with changed request facts is never accepted as a retry.
    S" Changed imported snapshot" _lcc-request-a
        LIBRARY-CAPTURE-IMPORT-TITLE!
        LIBSTORE-S-OK = _lcc-assert
    _lcc-request-a _lcc-entry2 _lcc-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-IDEMPOTENCY-MISMATCH = _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lcc-assert

    \ Operation keys and resource identities share one namespace.  Both
    \ capture and managed admission reject an existing RID as a new key.
    _lcc-rid-a 3 _lcc-request-a _lcc-build-capture
    _lcc-entry2 LIB-ENTRY-SIZE 165 FILL
    _lcc-request-a _lcc-entry2 _lcc-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-CONFLICT = _lcc-assert
    _lcc-entry2 LIB-ENTRY-SIZE _lcc-zero? _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lcc-assert

    _lcc-managed-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    3 _lcc-managed-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lcc-rid-b _lcc-managed-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lcc-assert
    S" RID collision refusal" _lcc-managed-request
        LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lcc-assert
    S" no publication" _lcc-managed-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lcc-assert
    LIB-MEDIA-TEXT-PLAIN _lcc-managed-request LIBMCR.MEDIA !
    _lcc-managed-request LIBRARY-MANAGED-CREATE-REQUEST-VALID?
        _lcc-assert
    _lcc-entry2 LIB-ENTRY-SIZE 165 FILL
    _lcc-managed-request _lcc-entry2 _lcc-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-CONFLICT = _lcc-assert
    _lcc-entry2 LIB-ENTRY-SIZE _lcc-zero? _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lcc-assert

    _lcc-rid-a 1 _lcc-read
    _lcc-status @ LIBSTORE-S-OK = _lcc-assert
    _lcc-required @ 22 = _lcc-assert
    _lcc-read-entry LIBE.ID _lcc-rid-a RID= _lcc-assert
    _lcc-read-content LIBCT-DATA$
        S" immutable copied bytes" COMPARE 0= _lcc-assert

    \ Capture bytes are immutable: the managed replacement surface refuses
    \ the kind before publication and leaves its caller output empty.
    _lcc-entry2 LIB-ENTRY-SIZE 165 FILL
    _lcc-rid-a 1 S" forbidden capture replacement" _lcc-entry2 _lcc-store
        LIBRARY-VFS-STORE-REPLACE-MANAGED
        LIBSTORE-S-INVALID = _lcc-assert
    _lcc-entry2 LIB-ENTRY-SIZE _lcc-zero? _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lcc-assert
    _lcc-stack ;

: _lcc-identity-read-contract  ( -- )
    \ A targeted capture lookup uses only warm authority assurance and the
    \ exact catalog record; it neither enumerates query pages nor consults
    \ or rebuilds the disposable corpus index.
    _LIBPQ-RESET
    _lcc-identity-entry LIB-ENTRY-SIZE 165 FILL
    _lcc-rid-a _lcc-read-identity
    _lcc-status @ LIBSTORE-S-OK = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-VALID? _lcc-assert
    _lcc-identity-entry LIBE.ID _lcc-rid-a RID= _lcc-assert
    _lcc-identity-entry LIBE.KIND @ LIB-KIND-CAPTURE = _lcc-assert
    _lcc-identity-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE
        _lcc-entry LIB-ENTRY-SIZE COMPARE 0= _lcc-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lcc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lcc-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lcc-assert
    _LIBPQ-ENTRY-READ@ 1 = _lcc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lcc-assert
    _LIBPQ-ARENA-SCAN@ 0= _lcc-assert

    \ Unknown and semantically invalid identities leave no stale entry.
    _lcc-identity-entry LIB-ENTRY-SIZE 165 FILL
    _lcc-unknown-rid _lcc-read-identity
    _lcc-status @ LIBSTORE-S-NOT-FOUND = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE _lcc-zero? _lcc-assert
    _lcc-rid-out RID-CLEAR
    _lcc-identity-entry LIB-ENTRY-SIZE 165 FILL
    _lcc-rid-out _lcc-read-identity
    _lcc-status @ LIBSTORE-S-INVALID = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE _lcc-zero? _lcc-assert

    \ Input/output overlap and owner-store aliases are rejected before any
    \ unsafe output write.  A self-aliased entry therefore remains intact.
    _lcc-entry _lcc-identity-entry LIB-ENTRY-SIZE CMOVE
    _lcc-identity-entry _lcc-identity-entry _lcc-store
        LIBRARY-VFS-STORE-READ-IDENTITY
        LIBSTORE-S-INVALID = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE
        _lcc-entry LIB-ENTRY-SIZE COMPARE 0= _lcc-assert
    _lcc-store _lcc-store-before LIBRARY-VFS-STORE-SIZE CMOVE
    _lcc-rid-a _lcc-store _lcc-store
        LIBRARY-VFS-STORE-READ-IDENTITY
        LIBSTORE-S-INVALID = _lcc-assert
    _lcc-store LIBRARY-VFS-STORE-SIZE
        _lcc-store-before LIBRARY-VFS-STORE-SIZE COMPARE 0= _lcc-assert

    \ A touched-record I/O failure is explicit and cannot expose the stale
    \ successful entry that occupied the caller buffer before the call.
    _lcc-identity-entry LIB-ENTRY-SIZE 165 FILL
    ['] _lcc-fail-catalog-read _LIBVFS-READ-EXACT-XT !
    _lcc-rid-a _lcc-read-identity
    _lcc-status @ LIBSTORE-S-IO = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE _lcc-zero? _lcc-assert
    ['] VFS-READ-EXACT _LIBVFS-READ-EXACT-XT !
    _lcc-stack ;

: _lcc-receipt-a  ( -- )
    _lcc-rid-out LIB-DIGEST-SIZE 165 FILL
    _lcc-receipt LIB-RECEIPT-SIZE 165 FILL
    _lcc-key-a _lcc-rid-out _lcc-receipt _lcc-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        LIBSTORE-S-OK = _lcc-assert
    _lcc-rid-out _lcc-rid-a RID= _lcc-assert
    _lcc-receipt LIB-RECEIPT-VALID? _lcc-assert
    _lcc-receipt LIBR.OPERATION-KEY _lcc-key-a RID= _lcc-assert
    _lcc-receipt LIBR.METHOD @
        LIB-IMPORT-VFS-SNAPSHOT = _lcc-assert
    _lcc-receipt LIBR-SOURCE-OWNER$
        LIB-VFS-SOURCE-OWNER$ COMPARE 0= _lcc-assert
    _lcc-stack ;

: _lcc-create-collection  ( -- )
    _lcc-rid-a _lcc-members RID-COPY
    _lcc-rid-b _lcc-members LIB-DIGEST-SIZE + RID-COPY
    _lcc-create-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    3 _lcc-create-request LIBCCR.EXPECTED-CATALOG-GENERATION !
    _lcc-collection-key _lcc-create-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lcc-assert
    S" Imported snapshots" _lcc-create-request
        LIBRARY-COLLECTION-CREATE-TITLE!
        LIBSTORE-S-OK = _lcc-assert
    _lcc-members 2 _lcc-create-request
        LIBRARY-COLLECTION-CREATE-MEMBERS!
        LIBSTORE-S-OK = _lcc-assert
    _lcc-create-request LIBRARY-COLLECTION-CREATE-REQUEST-VALID?
        _lcc-assert
    _lcc-create-request _lcc-view _lcc-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-OK = _lcc-assert
    _lcc-view LIBCV.ID _lcc-collection-rid RID-COPY
    _lcc-view LIBCV.REVISION @ 1 = _lcc-assert
    _lcc-view LIBCV.MEMBER-N @ 2 = _lcc-assert
    _lcc-rid-a 0 _lcc-view _lcc-assert-view-member
    _lcc-rid-b 1 _lcc-view _lcc-assert-view-member
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 4 = _lcc-assert

    \ A create retry succeeds after generation advances and preserves RID.
    _lcc-create-request _lcc-view2 _lcc-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-OK = _lcc-assert
    _lcc-view2 LIBCV.ID _lcc-collection-rid RID= _lcc-assert
    _lcc-view2 LIBCV.REVISION @ 1 = _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 4 = _lcc-assert

    _lcc-collection-rid 1 _lcc-view2 _lcc-store
        LIBRARY-VFS-STORE-READ-COLLECTION-EXACT
        LIBSTORE-S-OK = _lcc-assert
    _lcc-view LIBRARY-COLLECTION-VIEW-SIZE
        _lcc-view2 LIBRARY-COLLECTION-VIEW-SIZE COMPARE 0= _lcc-assert
    _lcc-stack ;

: _lcc-replace-collection  ( -- )
    _lcc-replace-request LIBRARY-COLLECTION-REPLACE-REQUEST-INIT
    _lcc-collection-rid _lcc-replace-request LIBCRR.ID RID-COPY
    1 _lcc-replace-request LIBCRR.EXPECTED-REVISION !
    S" Kept snapshot" _lcc-replace-request
        LIBRARY-COLLECTION-REPLACE-TITLE!
        LIBSTORE-S-OK = _lcc-assert
    _lcc-members LIB-DIGEST-SIZE + 1 _lcc-replace-request
        LIBRARY-COLLECTION-REPLACE-MEMBERS!
        LIBSTORE-S-OK = _lcc-assert
    _lcc-replace-request LIBRARY-COLLECTION-REPLACE-REQUEST-VALID?
        _lcc-assert
    _lcc-replace-request _lcc-view _lcc-store
        LIBRARY-VFS-STORE-REPLACE-COLLECTION
        LIBSTORE-S-OK = _lcc-assert
    _lcc-view LIBCV.REVISION @ 2 = _lcc-assert
    _lcc-view LIBCV.MEMBER-N @ 1 = _lcc-assert
    _lcc-rid-b 0 _lcc-view _lcc-assert-view-member
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 5 = _lcc-assert

    \ Stale replacement is refused and leaves the current view intact.
    _lcc-replace-request _lcc-view2 _lcc-store
        LIBRARY-VFS-STORE-REPLACE-COLLECTION
        LIBSTORE-S-CONFLICT = _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 5 = _lcc-assert
    _lcc-collection-rid 2 _lcc-view2 _lcc-store
        LIBRARY-VFS-STORE-READ-COLLECTION-EXACT
        LIBSTORE-S-OK = _lcc-assert
    _lcc-rid-b 0 _lcc-view2 _lcc-assert-view-member

    \ Membership removal is not resource deletion.
    _lcc-rid-a 1 _lcc-read
    _lcc-status @ LIBSTORE-S-OK = _lcc-assert
    _lcc-read-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _lcc-assert
    _lcc-stack ;

: _lcc-lifecycle-independent  ( -- )
    \ Archiving preserves exact capture reads and collection membership.
    _lcc-rid-b 1 _lcc-entry _lcc-store LIBRARY-VFS-STORE-ARCHIVE
        LIBSTORE-S-OK = _lcc-assert
    _lcc-entry LIBE.DOMAIN-REVISION @ 2 = _lcc-assert
    _lcc-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE 165 FILL
    _lcc-rid-b _lcc-read-identity
    _lcc-status @ LIBSTORE-S-OK = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE
        _lcc-entry LIB-ENTRY-SIZE COMPARE 0= _lcc-assert
    _lcc-identity-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _lcc-assert
    _lcc-rid-b 2 _lcc-read
    _lcc-status @ LIBSTORE-S-OK = _lcc-assert
    _lcc-read-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _lcc-assert
    _lcc-read-content LIBCT-DATA$
        S" immutable copied bytes" COMPARE 0= _lcc-assert
    _lcc-collection-rid 2 _lcc-view _lcc-store
        LIBRARY-VFS-STORE-READ-COLLECTION-EXACT
        LIBSTORE-S-OK = _lcc-assert
    _lcc-rid-b 0 _lcc-view _lcc-assert-view-member

    \ Only explicit tombstone destroys the capture; it still does not
    \ silently rewrite the independent collection relationship.
    _lcc-rid-b 2 _lcc-entry _lcc-store
        LIBRARY-VFS-STORE-TOMBSTONE-DESTRUCTIVE
        LIBSTORE-S-OK = _lcc-assert
    _lcc-entry LIBE.DOMAIN-REVISION @ 3 = _lcc-assert
    _lcc-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE 165 FILL
    _lcc-rid-b _lcc-read-identity
    _lcc-status @ LIBSTORE-S-TOMBSTONED = _lcc-assert
    _lcc-identity-entry LIB-ENTRY-SIZE
        _lcc-entry LIB-ENTRY-SIZE COMPARE 0= _lcc-assert
    _lcc-identity-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lcc-assert
    _lcc-rid-b 3 _lcc-read
    _lcc-status @ LIBSTORE-S-TOMBSTONED = _lcc-assert
    _lcc-required @ 0= _lcc-assert
    _lcc-read-content LIB-CONTENT-SIZE _lcc-zero? _lcc-assert
    _lcc-collection-rid 2 _lcc-view _lcc-store
        LIBRARY-VFS-STORE-READ-COLLECTION-EXACT
        LIBSTORE-S-OK = _lcc-assert
    _lcc-view LIBCV.MEMBER-N @ 1 = _lcc-assert
    _lcc-rid-b 0 _lcc-view _lcc-assert-view-member

    \ Original key resolves to the non-reusable tombstoned identity.
    _lcc-rid-out LIB-DIGEST-SIZE 165 FILL
    _lcc-receipt LIB-RECEIPT-SIZE 165 FILL
    _lcc-key-b _lcc-rid-out _lcc-receipt _lcc-store
        LIBRARY-VFS-STORE-LOOKUP-RECEIPT
        LIBSTORE-S-TOMBSTONED = _lcc-assert
    _lcc-rid-out _lcc-rid-b RID= _lcc-assert
    _lcc-receipt LIB-RECEIPT-VALID? _lcc-assert
    _lcc-request-b _lcc-entry2 _lcc-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-TOMBSTONED = _lcc-assert
    _lcc-entry2 LIBE.ID _lcc-rid-b RID= _lcc-assert
    _lcc-entry2 LIBE.LIFECYCLE @
        LIB-LIFECYCLE-TOMBSTONED = _lcc-assert
    _lcc-store LIBRARY-VFS-STORE.GENERATION @ 7 = _lcc-assert
    _lcc-stack ;

: _lcc-run  ( -- )
    0 _lcc-fails ! 0 _lcc-checks ! DEPTH _lcc-depth !
    VFS-CUR _lcc-old-vfs !
    _lcc-arena-id LIB-DIGEST-SIZE 0xA6 FILL
    _lcc-key-a LIB-OPERATION-KEY-SIZE 0x61 FILL
    _lcc-key-b LIB-OPERATION-KEY-SIZE 0x62 FILL
    _lcc-unknown-rid LIB-DIGEST-SIZE 0x71 FILL
    _lcc-collection-key LIB-OPERATION-KEY-SIZE 0x63 FILL
    _lcc-build-origin
    4194304 A-XMEM ARENA-NEW DUP 0= _lcc-assert DROP
    DUP _lcc-arena !
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lcc-vfs ! 0<> _lcc-assert
    _lcc-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE ALLOCATE
        ABORT" LIBRARY CAPTURE COLLECTION allocation" _lcc-store-slot !
    _lcc-vfs @ _lcc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lcc-assert
    _lcc-arena-id _lcc-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lcc-assert
    _lcc-imports
    _lcc-identity-read-contract
    _lcc-receipt-a
    _lcc-create-collection
    _lcc-replace-collection
    _lcc-lifecycle-independent
    _lcc-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lcc-assert
    _lcc-store-slot @ FREE 0 _lcc-store-slot !
    _lcc-old-vfs @ VFS-USE
    _lcc-vfs @ VFS-DESTROY
    _lcc-stack
    _lcc-fails @ ?DUP IF
        ." LIBRARY CAPTURE COLLECTION FAIL " .
        ." / " _lcc-checks @ . CR
    ELSE
        ." LIBRARY CAPTURE COLLECTION PASS " _lcc-checks @ . CR
    THEN ;

_lcc-run
