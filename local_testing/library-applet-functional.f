\ =====================================================================
\  Library applet functional controller contract
\ =====================================================================
\  Exercise the real ASHELL/UIDL lifecycle and the Library behavior retained
\  across the L12 service cutover: first-use create, exact preview, search,
\  rename, archive/unarchive, retained history, collection filtering,
\  semantic keyset paging, exact create retry, reload, pending discard,
\  cold reconstruction, and corrupt/future-root write refusal.
\  The _LAPP-* words are a white-box test seam, not public applet ABI.
\ =====================================================================

VARIABLE _laf-fails
VARIABLE _laf-checks
VARIABLE _laf-depth
VARIABLE _laf-outer-depth
VARIABLE _laf-init-entry-depth
VARIABLE _laf-ran

CREATE _laf-desc APP-DESC ALLOT
CREATE _laf-rid LIB-DIGEST-SIZE ALLOT
CREATE _laf-retry-rid LIB-DIGEST-SIZE ALLOT
CREATE _laf-retry-key LIB-DIGEST-SIZE ALLOT
CREATE _laf-create-before LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE ALLOT

CREATE _laf-collection LIBPA-COLLECTION-SIZE ALLOT
CREATE _laf-collection-out LIBPA-COLLECTION-SIZE ALLOT
CREATE _laf-collection-request
    LIBRARY-COLLECTION-WRITE-REQUEST-SIZE ALLOT
CREATE _laf-collection-rid LIB-DIGEST-SIZE ALLOT
CREATE _laf-member LIB-DIGEST-SIZE ALLOT
CREATE _laf-compaction-request
    LIBRARY-COMPACTION-BIND-REQUEST-SIZE ALLOT
VARIABLE _laf-compact-steps
VARIABLE _laf-logical-before

VARIABLE _laf-file-a
VARIABLE _laf-file-u
VARIABLE _laf-path-a
VARIABLE _laf-path-u
VARIABLE _laf-fd
VARIABLE _laf-ior
VARIABLE _laf-expected-health

CREATE _laf-root-0-original PROOT-RECORD-SIZE ALLOT
CREATE _laf-root-1-original PROOT-RECORD-SIZE ALLOT
CREATE _laf-root-0-corrupt PROOT-RECORD-SIZE ALLOT
CREATE _laf-root-1-corrupt PROOT-RECORD-SIZE ALLOT
CREATE _laf-root-0-future PROOT-RECORD-SIZE ALLOT
CREATE _laf-root-1-future PROOT-RECORD-SIZE ALLOT
CREATE _laf-inspection-before LIBRARY-REPOSITORY-INSPECTION-SIZE ALLOT
CREATE _laf-inspection-after LIBRARY-REPOSITORY-INSPECTION-SIZE ALLOT

: _laf-assert  ( flag -- )
    1 _laf-checks +!
    0= IF
        1 _laf-fails +!
        ." LIBRARY APPLET FUNCTIONAL ASSERT " _laf-checks @ . CR
    THEN ;

: _laf-stack  ( -- )
    DEPTH DUP _laf-depth @ <> IF
        ." LIBRARY APPLET FUNCTIONAL STACK "
            _laf-depth @ . ." -> " DUP . CR .S CR
    THEN
    _laf-depth @ = _laf-assert ;

: _laf-phase  ( address length -- )
    ." LIBRARY APPLET FUNCTIONAL PHASE " TYPE CR ;

: _laf-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _laf-preview-body?  ( -- flag )
    _LAPP-PREVIEW-BYTES _LAPP-PREVIEW-U @
        S" functional exact preview" STR-STR= ;

: _laf-read-file  ( destination expected-u path-a path-u -- flag )
    _laf-path-u ! _laf-path-a !
    _laf-file-u ! _laf-file-a !
    _laf-path-a @ _laf-path-u @ VFS-FF-READ VFS-CUR VFS-OPEN?
    _laf-ior ! _laf-fd !
    _laf-ior @ IF 0 EXIT THEN
    _laf-fd @ 0= IF 0 EXIT THEN
    _laf-fd @ VFS-SIZE _laf-file-u @ <> IF
        _laf-fd @ VFS-CLOSE? DROP 0 EXIT
    THEN
    _laf-file-a @ _laf-file-u @ _laf-fd @ VFS-READ-EXACT 0=
    _laf-fd @ VFS-CLOSE? 0= AND ;

: _laf-put-file  ( source-a source-u path-a path-u -- )
    _laf-path-u ! _laf-path-a !
    _laf-file-u ! _laf-file-a !
    _laf-path-a @ _laf-path-u @
        VFS-FF-READ VFS-FF-WRITE OR VFS-CUR VFS-OPEN?
    _laf-ior ! _laf-fd !
    _laf-ior @ 0= _laf-assert
    _laf-fd @ 0<> _laf-assert
    _laf-fd @ 0= IF EXIT THEN
    _laf-fd @ VFS-SIZE _laf-file-u @ = _laf-assert
    _laf-fd @ VFS-REWIND
    _laf-file-a @ _laf-file-u @ _laf-fd @ VFS-WRITE-EXACT
        0= _laf-assert
    _laf-fd @ VFS-CLOSE? 0= _laf-assert
    VFS-CUR VFS-SYNC 0= _laf-assert ;

: _laf-copy-corrupt  ( source destination -- )
    >R
    DUP R@ PROOT-RECORD-SIZE MOVE
    DROP
    R@ CREC-H-HEADER-CRC + DUP @ 1 XOR SWAP !
    R> DROP ;

: _laf-copy-future  ( source destination -- )
    >R
    DUP R@ PROOT-RECORD-SIZE MOVE
    DROP
    _PROOT-RECORD-FORMAT 1+ R@ CREC-H-FORMAT + !
    R@ _CREC-HEADER-CRC R@ CREC-H-HEADER-CRC + !
    R> DROP ;

: _laf-corrupt-roots  ( -- )
    _laf-root-0-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-0$ _laf-read-file _laf-assert
    _laf-root-1-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _laf-read-file _laf-assert
    _laf-root-0-original _laf-root-0-corrupt _laf-copy-corrupt
    _laf-root-1-original _laf-root-1-corrupt _laf-copy-corrupt
    _laf-root-0-corrupt PROOT-RECORD-SIZE
        _LIBREPO-ROOT-0$ _laf-put-file
    _laf-root-1-corrupt PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _laf-put-file ;

: _laf-future-roots  ( -- )
    _laf-root-0-original _laf-root-0-future _laf-copy-future
    _laf-root-1-original _laf-root-1-future _laf-copy-future
    _laf-root-0-future PROOT-RECORD-SIZE
        _LIBREPO-FUTURE-ROOT-RECORD? _laf-assert
    _laf-root-1-future PROOT-RECORD-SIZE
        _LIBREPO-FUTURE-ROOT-RECORD? _laf-assert
    _laf-root-0-future PROOT-RECORD-SIZE
        _LIBREPO-ROOT-0$ _laf-put-file
    _laf-root-1-future PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _laf-put-file ;

: _laf-restore-roots  ( -- )
    _laf-root-0-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-0$ _laf-put-file
    _laf-root-1-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _laf-put-file ;

: _laf-inspect-health  ( inspection expected-health -- )
    _laf-expected-health !
    DUP _LAPP-REPOSITORY _LAPP-REPOSITORY-WORK
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK = _laf-assert
    DUP LIBRARY-REPOSITORY-INSPECTION-SEALED? _laf-assert
    LRI.HEALTH @ _laf-expected-health @ = _laf-assert ;

: _laf-create  ( -- )
    _LAPP-OWNER-INITIALIZED @ _laf-assert
    _LAPP-READY @ 0= _laf-assert
    _LAPP-LAST-STATUS @ LIBRARY-SERVICE-S-ABSENT = _laf-assert
    _LAPP-RUNTIME@ 0<> _laf-assert

    \ A missing working set fails before touching repository authority.
    _LAPP-RUNTIME@ >R
    0 _LAPP-RUNTIME !
    _LAPP-ENSURE-PROVISIONED
        LIBRARY-SERVICE-S-CAPACITY = _laf-assert
    R> _LAPP-RUNTIME !
    _LAPP-BACK LIBRARY-SERVICE-S-OK = _laf-assert

    S" Functional needle" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" functional exact preview" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-PENDING-CREATE @ _LAPP-CREATE-PREPARED = _laf-assert
    _LAPP-ENSURE-PROVISIONED
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-DISPATCH-PENDING-CREATE
        LIBRARY-SERVICE-S-OK = _laf-assert

    _LAPP-READY? _laf-assert
    _LAPP-PENDING-CREATE @ 0= _laf-assert
    _LAPP-RESULT-ENTRY LIB-ENTRY-VALID? _laf-assert
    _LAPP-RESULT-ENTRY LIBE.ID DUP RID-PRESENT? _laf-assert
        _laf-rid RID-COPY
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 1 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _laf-assert
    _LAPP-REFRESH-AFTER-MUTATION
    _laf-stack ;

: _laf-query-and-preview  ( -- )
    S" needle" DUP _LAPP-TERM-U ! _LAPP-TERM SWAP CMOVE
    _LAPP-RESET-PAGE LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-CORPUS-ROW DUP LIBQS.REF RREF.ID
        _laf-rid RID= _laf-assert
    LIBQS-TITLE$ S" Functional needle" STR-STR= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-PREVIEW-U @ 24 = _laf-assert
    _LAPP-PREVIEW-TOTAL @ 24 = _laf-assert
    _LAPP-TARGET-ID _laf-rid RID= _laf-assert
    _LAPP-TARGET-REVISION @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-search-clear-and-cancel  ( -- )
    0 _LAPP-DO-SEARCH
    _LAPP-PROMPT-MODE @ _LAPP-PRM-SEARCH = _laf-assert
    _LAPP-PROMPT @ PRM-ACTIVE? _laf-assert
    _LAPP-PROMPT @ PRM-HIDE
    _LAPP-PROMPT @ _LAPP-PROMPT-CANCEL
    _LAPP-PROMPT-MODE @ _LAPP-PRM-NONE = _laf-assert
    _LAPP-PROMPT @ PRM-ACTIVE? 0= _laf-assert
    _LAPP-TERM _LAPP-TERM-U @ S" needle" STR-STR= _laf-assert

    0 _LAPP-DO-CLEAR-SEARCH
    _LAPP-TERM-U @ 0= _laf-assert
    _LAPP-TERM LIBRARY-CORPUS-TERM-MAX _laf-zero? _laf-assert
    _LAPP-LAST-STATUS @ LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _laf-stack ;

: _laf-rename  ( -- )
    S" Functional renamed" _LAPP-RENAME-NOW
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 2 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE-TITLE$
        S" Functional renamed" STR-STR= _laf-assert
    _LAPP-REFRESH-AFTER-MUTATION
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-CORPUS-ROW LIBQS-TITLE$
        S" Functional renamed" STR-STR= _laf-assert
    _LAPP-TARGET-REVISION @ 2 = _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-archive  ( -- )
    0 _LAPP-DO-ARCHIVE
    _LAPP-LAST-STATUS @ LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 3 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _laf-assert
    _LAPP-ROW-COUNT @ 0= _laf-assert
    _LAPP-PREVIEW-READY @ 0= _laf-assert

    0 _LAPP-DO-SHOW-ARCHIVED
    _LAPP-VIEW @ _LAPP-V-ARCHIVED = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-CORPUS-ROW LIBQS.REF RREF.ID
        _laf-rid RID= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-TARGET-REVISION @ 3 = _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-history-and-unarchive  ( -- )
    _LAPP-OPEN-HISTORY LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-HISTORY = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-HISTORY-ROW LIBRS.DOMAIN-REVISION @ 1 = _laf-assert
    0 _LAPP-HISTORY-ROW LIBRS.CONTENT-REVISION @ 1 = _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _laf-preview-body? _laf-assert

    _LAPP-BACK LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-ARCHIVED = _laf-assert
    0 _LAPP-DO-UNARCHIVE
    _LAPP-LAST-STATUS @ LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 4 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _laf-assert
    0 _LAPP-DO-SHOW-ACTIVE
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-TARGET-REVISION @ 4 = _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-create-collection  ( -- )
    _laf-rid _laf-member RID-COPY
    _laf-collection LIBPA-COLLECTION-INIT
    _laf-collection LIBPAC.ID RID-CLEAR
    0xC1 _laf-collection LIBPAC.ID !
    _laf-collection LIBPAC.OPERATION-KEY RID-CLEAR
    0xD1 _laf-collection LIBPAC.OPERATION-KEY !
    1 _laf-collection LIBPAC.REVISION !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-NEXT-MUTATION@ DUP
        _laf-collection LIBPAC.MUTATION-SEQUENCE !
        _laf-collection LIBPAC.CREATED-SEQUENCE !
    1 _laf-collection LIBPAC.MEMBER-N !
    S" Functional collection"
        DUP _laf-collection LIBPAC.TITLE-U !
        _laf-collection LIBPAC.TITLE SWAP CMOVE
    _laf-collection _laf-member 1 LIBPA-COLLECTION-REQUEST-SEAL!
        LIBPA-S-OK = _laf-assert

    _laf-collection-request LIBRARY-COLLECTION-WRITE-REQUEST-INIT
    _laf-collection _laf-collection-request LSCWR.COLLECTION !
    _laf-member _laf-collection-request LSCWR.MEMBERS !
    1 _laf-collection-request LSCWR.MEMBER-N !
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _laf-collection-request LSCWR.EXPECTED-LOGICAL !
    0 _laf-collection-request LSCWR.EXPECTED-REVISION !
    _laf-collection-out _laf-collection-request LSCWR.RESULT !
    _laf-collection-request _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-CREATE-COLLECTION
        LIBRARY-SERVICE-S-OK = _laf-assert
    _laf-collection-out LIBPAC.ID DUP RID-PRESENT? _laf-assert
        _laf-collection-rid RID-COPY ;

: _laf-collection-filter-and-back  ( -- )
    0 _LAPP-DO-SHOW-ALL
    _laf-create-collection
    0 _LAPP-DO-COLLECTIONS
    \ Collection preview must consume the selected summary revision after
    \ storing its exact read target; no view transition may leak it.
    _laf-stack
    _LAPP-VIEW @ _LAPP-V-COLLECTIONS = _laf-assert
    _LAPP-RETURN-VIEW @ _LAPP-V-ALL = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-COLLECTION-ROW LIBCS.REF RREF.ID
        _laf-collection-rid RID= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-COLLECTION LIBPAC.MEMBER-N @ 1 = _laf-assert

    _LAPP-FILTER-COLLECTION LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-ALL = _laf-assert
    _LAPP-FILTER-ACTIVE @ _laf-assert
    _LAPP-FILTER-ID _laf-collection-rid RID= _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-BACK LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-FILTER-ACTIVE @ 0= _laf-assert
    _LAPP-FILTER-ID RID-PRESENT? 0= _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _laf-stack ;

: _laf-exact-pending-retry  ( -- )
    S" Retried document" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" exact retry body" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-PREPARE-PENDING-CREATE
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-CREATE-ENTRY LIBE.RECEIPT LIBR.OPERATION-KEY
        _laf-retry-key RID-COPY
    _LAPP-CREATE-REQUEST _laf-create-before
        LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE MOVE

    \ Model an uncertain caller observation: authority committed the exact
    \ request, while the controller still owns the complete retry value.
    _LAPP-CREATE-REQUEST _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-CREATE-MANAGED
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-CREATE-REQUEST LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE
        _laf-create-before LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE
        COMPARE 0= _laf-assert
    _LAPP-CREATE-DISPATCHED _LAPP-PENDING-CREATE !
    _LAPP-CALL-PENDING-CREATE
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-PENDING-CREATE @ 0= _laf-assert
    _LAPP-RESULT-ENTRY LIBE.ID DUP RID-PRESENT? _laf-assert
        _laf-retry-rid RID-COPY
    _LAPP-RESULT-ENTRY LIBE.RECEIPT LIBR.OPERATION-KEY
        _laf-retry-key RID= _laf-assert
    _LAPP-REFRESH-AFTER-MUTATION
    _LAPP-ROW-COUNT @ 2 = _laf-assert
    _laf-stack ;

: _laf-nonzero-selection-restore  ( -- )
    \ Refresh must retain a semantic selection beyond row zero even though
    \ page initialization clears and repopulates the backing row buffer.
    1 _LAPP-SELECTED !
    _LAPP-LOAD-SELECTION
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-retry-rid RID= _laf-assert
    _LAPP-TARGET-ID _laf-retry-rid RID= _laf-assert

    _LAPP-RESET-PAGE
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 2 = _laf-assert
    _LAPP-SELECTED @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-retry-rid RID= _laf-assert
    _LAPP-TARGET-ID _laf-retry-rid RID= _laf-assert
    _laf-stack ;

: _laf-keyset-paging-and-reload  ( -- )
    0 _LAPP-TERM-U ! 0 _LAPP-FILTER-ACTIVE !
    _LAPP-V-ACTIVE _LAPP-VIEW !
    _LAPP-CLEAR-PAGES
    _LAPP-PAGE-INITIALIZE LIBRARY-SERVICE-S-OK = _laf-assert
    1 _LAPP-PAGE LIBQP.CAPACITY !
    _LAPP-PAGE-FIRST _LAPP-PAGE-MODE !
    _LAPP-RUN-PAGE LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-PAGE LIBQP.CONTINUATION
        LIBRARY-QUERY-CONTINUATION-HAS-AFTER? _laf-assert
    0 _LAPP-DO-NEXT-PAGE
    _LAPP-PAGE-INDEX @ 1 = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-retry-rid RID= _laf-assert
    0 _LAPP-DO-PREVIOUS-PAGE
    _LAPP-PAGE-INDEX @ 0= _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert

    _LAPP-PAGE LIBRARY-QUERY-PAGE-SIZE 0 FILL
    _LAPP-ENTRY LIB-ENTRY-SIZE 0 FILL
    0 _LAPP-ROW-COUNT ! 0 _LAPP-PREVIEW-READY !
    0 _LAPP-DO-RELOAD
    _LAPP-LAST-STATUS @ LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-READY? _laf-assert
    _LAPP-PAGE-INDEX @ 0= _laf-assert
    _LAPP-ROW-COUNT @ 2 = _laf-assert
    _LAPP-ENTRY LIB-ENTRY-VALID? _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-pending-close-and-discard  ( -- )
    S" Discard pending" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" never committed" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE
        LIBRARY-SERVICE-S-OK = _laf-assert
    0 _LAPP-CURRENT-INSTANCE @ LIBRARY-APPLET-REQUEST-CLOSE-CB
        APP-CLOSE-D-DEFER = _laf-assert
    _LAPP-PROMPT-MODE @ _LAPP-PRM-DISCARD-PENDING = _laf-assert
    S" DISCARD" _LAPP-PROMPT @ _PRM-O-INPUT + @ INP-SET-TEXT
    _LAPP-PROMPT @ PRM-HIDE
    _LAPP-PROMPT @ _LAPP-PROMPT-SUBMIT
    _LAPP-PENDING-CREATE @ 0= _laf-assert
    _LAPP-CREATE-REQUEST LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE
        _laf-zero? _laf-assert
    _LAPP-DISCARD-ARMED @ _laf-assert
    0 _LAPP-CURRENT-INSTANCE @ LIBRARY-APPLET-REQUEST-CLOSE-CB
        APP-CLOSE-D-ALLOW = _laf-assert
    _LAPP-DISCARD-ARMED @ 0= _laf-assert
    _laf-stack ;

: _laf-compact  ( -- )
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _laf-logical-before !
    _laf-compaction-request LIBRARY-COMPACTION-BIND-REQUEST-INIT
    16777216 _laf-compaction-request LSCBR.BYTE-BUDGET !
    4096 _laf-compaction-request LSCBR.WORK-BUDGET !
    1048576 _laf-compaction-request LSCBR.STEP-BYTE-BUDGET !
    _laf-compaction-request _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-COMPACTION-BIND
    DUP LIBRARY-SERVICE-S-OK = _laf-assert
    DUP IF DROP EXIT THEN DROP
    _LAPP-SERVICE _LAPP-SERVICE-WORK LIBRARY-SERVICE-COMPACTION-BEGIN
    DUP LIBRARY-SERVICE-S-OK = _laf-assert
    DUP IF DROP EXIT THEN DROP
    0 _laf-compact-steps !
    BEGIN
        _LAPP-SERVICE-WORK LIBRARY-SERVICE-COMPACTION-STATE@
            PCOMPACT-STATE-BUILDING =
    WHILE
        _laf-compact-steps @ 4096 >= IF
            0 _laf-assert EXIT
        THEN
        _LAPP-SERVICE _LAPP-SERVICE-WORK
            LIBRARY-SERVICE-COMPACTION-STEP
        DUP LIBRARY-SERVICE-S-OK = _laf-assert
        DUP IF DROP EXIT THEN DROP
        1 _laf-compact-steps +!
    REPEAT
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-READY = DUP _laf-assert 0= IF EXIT THEN
    _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-COMPACTION-FINALIZE
    DUP LIBRARY-SERVICE-S-OK = _laf-assert
    DUP IF DROP EXIT THEN DROP
    _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-COMPACTION-PUBLISH
    DUP LIBRARY-SERVICE-S-OK = _laf-assert
    DUP IF DROP EXIT THEN DROP
    _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-COMPACTION-MIRROR
    DUP LIBRARY-SERVICE-S-OK = _laf-assert
    DUP IF DROP EXIT THEN DROP
    _LAPP-SERVICE _LAPP-SERVICE-WORK
        LIBRARY-SERVICE-COMPACTION-CLEANUP
    DUP LIBRARY-SERVICE-S-OK = _laf-assert
    DUP IF DROP EXIT THEN DROP
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-COMPACTION-STATE@
        PCOMPACT-STATE-CLEANED = _laf-assert
    _LAPP-SERVICE-WORK LIBRARY-SERVICE-LOGICAL-GENERATION@
        _laf-logical-before @ = _laf-assert
    _laf-stack ;

: _laf-shell-init  ( instance -- )
    DEPTH _laf-init-entry-depth !
    LIBRARY-APPLET-INIT-CB
    DEPTH _laf-init-entry-depth @ 1- = _laf-assert
    DEPTH _laf-depth !
    1 _laf-ran +!
    S" primary-create-and-mutate" _laf-phase
    _laf-create
    _laf-query-and-preview
    _laf-search-clear-and-cancel
    _laf-rename
    S" primary-compaction-1" _laf-phase
    _laf-compact
    _laf-archive
    _laf-history-and-unarchive
    S" primary-compaction-2" _laf-phase
    _laf-compact
    _laf-collection-filter-and-back
    _laf-exact-pending-retry
    _laf-nonzero-selection-restore
    S" primary-compaction-3" _laf-phase
    _laf-compact
    _laf-keyset-paging-and-reload
    _laf-pending-close-and-discard
    _laf-stack
    ASHELL-QUIT ;

: _laf-cold-shell-init  ( instance -- )
    DEPTH _laf-init-entry-depth !
    LIBRARY-APPLET-INIT-CB
    DEPTH _laf-init-entry-depth @ 1- = _laf-assert
    DEPTH _laf-depth !
    1 _laf-ran +!

    _LAPP-OWNER-INITIALIZED @ _laf-assert
    _LAPP-READY? _laf-assert
    _LAPP-LAST-STATUS @ LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-ACTIVE = _laf-assert
    _LAPP-PAGE-INDEX @ 0= _laf-assert
    _LAPP-ROW-COUNT @ 2 = _laf-assert
    _LAPP-SELECTED @ 0= _laf-assert
    _LAPP-ENTRY LIB-ENTRY-VALID? _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-TARGET-ID _laf-rid RID= _laf-assert
    _LAPP-TARGET-REVISION @ 4 = _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-PREVIEW-U @ 24 = _laf-assert
    _LAPP-PREVIEW-TOTAL @ 24 = _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack
    ASHELL-QUIT ;

: _laf-assert-blocked-ui  ( -- )
    _LAPP-OWNER-INITIALIZED @ _laf-assert
    _LAPP-READY @ 0= _laf-assert
    _LAPP-READY? 0= _laf-assert
    _LAPP-LAST-STATUS @ DUP 0<> _laf-assert
        LIBRARY-SERVICE-S-CORRUPT = _laf-assert
    _LAPP-LAST-STATUS @ _LAPP-STATUS$
        S" Corrupt - writes blocked" STR-STR= _laf-assert
    _LAPP-E-SBAR-STATE @ 0<> _laf-assert
    _LAPP-STATUS-U @ 0> _laf-assert
    _LAPP-STATUS-BUF _LAPP-STATUS-U @
        S" Corrupt - writes blocked" STR-STR= _laf-assert
    _LAPP-VIEW @ _LAPP-V-ACTIVE = _laf-assert
    _LAPP-ROW-COUNT @ 0= _laf-assert
    _LAPP-PAGE LIBQP.COUNT @ 0= _laf-assert
    _LAPP-PREVIEW-READY @ 0= _laf-assert
    _LAPP-PREVIEW-U @ 0= _laf-assert
    _LAPP-ENTRY LIBE.ID RID-PRESENT? 0= _laf-assert ;

: _laf-refuse-blocked-writes  ( expected-health -- )
    _laf-expected-health !
    _laf-inspection-before _laf-expected-health @ _laf-inspect-health
    _LAPP-ENSURE-PROVISIONED
        LIBRARY-SERVICE-S-CORRUPT = _laf-assert
    _LAPP-READY? 0= _laf-assert

    S" Refused blocked write" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" must not commit" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE
        LIBRARY-SERVICE-S-OK = _laf-assert
    _LAPP-PENDING-CREATE @ _LAPP-CREATE-PREPARED = _laf-assert
    _LAPP-DISPATCH-PENDING-CREATE
        LIBRARY-SERVICE-S-CORRUPT = _laf-assert
    _LAPP-PENDING-CREATE @ _LAPP-CREATE-PREPARED = _laf-assert
    _LAPP-CREATE-REQUEST LIBRARY-DOCUMENT-CREATE-REQUEST-SIZE
        _laf-zero? _laf-assert
    _LAPP-ROW-COUNT @ 0= _laf-assert
    _LAPP-PREVIEW-READY @ 0= _laf-assert

    _laf-inspection-after _laf-expected-health @ _laf-inspect-health
    _laf-inspection-before LRI.SEAL
        _laf-inspection-after LRI.SEAL RID= _laf-assert
    _LAPP-CLEAR-PENDING
    _LAPP-PENDING-CREATE @ 0= _laf-assert ;

: _laf-blocked-shell-init  ( instance -- )
    DEPTH _laf-init-entry-depth !
    LIBRARY-APPLET-INIT-CB
    DEPTH _laf-init-entry-depth @ 1- = _laf-assert
    DEPTH _laf-depth !
    1 _laf-ran +!

    _laf-assert-blocked-ui
    LIBRARY-REPOSITORY-HEALTH-CORRUPT _laf-refuse-blocked-writes
    _laf-stack
    ASHELL-QUIT ;

: _laf-future-shell-init  ( instance -- )
    DEPTH _laf-init-entry-depth !
    LIBRARY-APPLET-INIT-CB
    DEPTH _laf-init-entry-depth @ 1- = _laf-assert
    DEPTH _laf-depth !
    1 _laf-ran +!

    \ Both checked roots carry a checksum-valid future record format.  The
    \ current reader must not adopt either as authority; the applet therefore
    \ presents its ordinary fail-closed corruption status while inspection
    \ retains the more exact FUTURE physical classification.
    _laf-assert-blocked-ui
    LIBRARY-REPOSITORY-HEALTH-FUTURE _laf-refuse-blocked-writes
    _laf-stack
    ASHELL-QUIT ;

: _laf-outer-stack  ( -- )
    DEPTH DUP _laf-outer-depth @ <> IF
        ." LIBRARY APPLET FUNCTIONAL OUTER STACK "
            _laf-outer-depth @ . ." -> " DUP . CR .S CR
    THEN
    _laf-outer-depth @ = _laf-assert ;

: _laf-run  ( -- )
    0 _laf-fails ! 0 _laf-checks ! 0 _laf-ran !
    DEPTH _laf-outer-depth !
    _laf-desc LIBRARY-APPLET-ENTRY
    ['] _laf-shell-init _laf-desc APP.INIT-XT !
    _laf-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _laf-assert
    _laf-outer-stack

    S" cold-reopen" _laf-phase
    ['] _laf-cold-shell-init _laf-desc APP.INIT-XT !
    _laf-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _laf-assert
    _laf-outer-stack

    S" corrupt-roots" _laf-phase
    _laf-corrupt-roots
    ['] _laf-blocked-shell-init _laf-desc APP.INIT-XT !
    _laf-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _laf-assert
    _laf-outer-stack
    _laf-restore-roots

    S" future-roots" _laf-phase
    _laf-future-roots
    ['] _laf-future-shell-init _laf-desc APP.INIT-XT !
    _laf-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _laf-assert
    _laf-outer-stack
    _laf-restore-roots

    \ Reopen once more after restoring the exact accepted root bytes.  This
    \ proves the damage branches did not leak blocked state beyond their own
    \ activation and that the populated authority is usable again.
    S" restored-reopen" _laf-phase
    ['] _laf-cold-shell-init _laf-desc APP.INIT-XT !
    _laf-desc ASHELL-RUN
    _LAPP-LIVE-INSTANCE @ 0= _laf-assert
    _laf-outer-stack

    \ There is deliberately no synthetic RECOVERY/UNCERTAIN lifecycle here.
    \ In the current owner, UNCERTAIN is an operation-local cleanup outcome,
    \ compaction recovery state is memory-only, and ordinary applet LOAD does
    \ not bind or recover the compactor.  No durable repository evidence can
    \ therefore reproduce that presentation across a fresh applet lifecycle.
    _laf-ran @ 5 = _laf-assert
    _laf-outer-stack
    _laf-fails @ ?DUP IF
        ." LIBRARY APPLET FUNCTIONAL FAIL " .
            ." / " _laf-checks @ . CR
    ELSE
        ." LIBRARY APPLET FUNCTIONAL PASS " _laf-checks @ . CR
    THEN ;

_laf-run
