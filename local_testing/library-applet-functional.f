\ =====================================================================
\  Library applet functional controller contract
\ =====================================================================
\  Exercise the real ASHELL/UIDL lifecycle and every Library behavior edge
\  named by the L1 controller prerequisite: create/retry/discard,
\  query/search/paging/reload, rename/lifecycle/history, and collection
\  enumeration/filter/back. Some exact setup paths call controller-private
\  words directly; this fixture does not claim every UI callback wrapper.
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
CREATE _laf-create-before LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _laf-collection-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _laf-collection-rid LIB-DIGEST-SIZE ALLOT
CREATE _laf-member LIB-DIGEST-SIZE ALLOT
CREATE _laf-collection-request
    LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _laf-collection-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
VARIABLE _laf-retry-generation

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

: _laf-preview-body?  ( -- flag )
    _LAPP-PREVIEW-BYTES _LAPP-PREVIEW-U @
        S" functional exact preview" STR-STR= ;

: _laf-zero?  ( a u -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _laf-after-head-fault  ( stage -- status )
    _LIBMU-STAGE-AFTER-HEAD = IF
        LIBSTORE-S-IO
    ELSE
        LIBSTORE-S-OK
    THEN ;

: _laf-create  ( -- )
    _LAPP-STORE-INITIALIZED @ _laf-assert
    _LAPP-READY @ 0= _laf-assert
    _LAPP-LAST-STATUS @ LIBSTORE-S-ABSENT = _laf-assert
    _LAPP-PREVIEW-BUFFER @ 0<> _laf-assert
    _LAPP-PREVIEW-BUFFER @ >R
    0 _LAPP-PREVIEW-BUFFER !
    LIBSTORE-S-OK _LAPP-LAST-STATUS !
    _LAPP-ENSURE-PROVISIONED LIBSTORE-S-ALLOCATION = _laf-assert
    R> _LAPP-PREVIEW-BUFFER !
    \ Presentation-only actions may replace the visible ABSENT status.  The
    \ create path must reclassify storage instead of trusting that cache.
    _LAPP-BACK LIBSTORE-S-OK = _laf-assert
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert

    S" Functional needle" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" functional exact preview" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE LIBSTORE-S-OK = _laf-assert
    _LAPP-PENDING-CREATE @ _LAPP-CREATE-PREPARED = _laf-assert
    _LAPP-DISPATCH-PENDING-CREATE LIBSTORE-S-OK = _laf-assert

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
    _LAPP-RESET-PAGE LIBSTORE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-CORPUS-ROW DUP LIBQS.REF RREF.ID
        _laf-rid RID= _laf-assert
    LIBQS-TITLE$ S" Functional needle" STR-STR= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-TARGET-ID _laf-rid RID= _laf-assert
    _LAPP-TARGET-REVISION @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-ENTRY LIBE.DOMAIN-REVISION @ 1 = _laf-assert
    _LAPP-CONTENT LIBCT-DATA$
        S" functional exact preview" STR-STR= _laf-assert
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
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _laf-stack ;

: _laf-rename  ( -- )
    S" Functional renamed" _LAPP-RENAME-NOW
        LIBSTORE-S-OK = _laf-assert
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
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 3 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _laf-assert
    _LAPP-ROW-COUNT @ 0= _laf-assert
    _LAPP-PREVIEW-READY @ 0= _laf-assert

    0 _LAPP-DO-SHOW-ARCHIVED
    _LAPP-VIEW @ _LAPP-V-ARCHIVED = _laf-assert
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-CORPUS-ROW LIBQS.REF RREF.ID
        _laf-rid RID= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-TARGET-REVISION @ 3 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _laf-assert
    _laf-preview-body? _laf-assert

    0 _LAPP-DO-SHOW-ALL
    _LAPP-VIEW @ _LAPP-V-ALL = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _laf-assert
    _LAPP-ENTRY LIBE-TITLE$ S" Functional renamed" STR-STR= _laf-assert
    0 _LAPP-DO-SHOW-ARCHIVED
    _laf-stack ;

: _laf-history-and-unarchive  ( -- )
    _LAPP-OPEN-HISTORY LIBSTORE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-HISTORY = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    \ Lifecycle changes advance the entry domain revision without rewriting
    \ immutable content history; its retained frame remains revision 1.
    0 _LAPP-HISTORY-ROW LIBRS.DOMAIN-REVISION @ 1 = _laf-assert
    0 _LAPP-HISTORY-ROW LIBRS.CONTENT-REVISION @ 1 = _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _laf-preview-body? _laf-assert

    _LAPP-BACK LIBSTORE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-ARCHIVED = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-DO-UNARCHIVE
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.DOMAIN-REVISION @ 4 = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _laf-assert
    _LAPP-ROW-COUNT @ 0= _laf-assert
    _LAPP-PREVIEW-READY @ 0= _laf-assert

    0 _LAPP-DO-SHOW-ACTIVE
    _LAPP-VIEW @ _LAPP-V-ACTIVE = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-TARGET-REVISION @ 4 = _laf-assert
    _LAPP-ENTRY LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ACTIVE = _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-collection-filter-and-back  ( -- )
    0 _LAPP-DO-SHOW-ALL
    _LAPP-VIEW @ _LAPP-V-ALL = _laf-assert
    _laf-rid _laf-member RID-COPY
    _laf-collection-key LIB-OPERATION-KEY-SIZE 0x63 FILL
    _laf-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    _LAPP-STORE LIBRARY-VFS-STORE.GENERATION @
        _laf-collection-request LIBCCR.EXPECTED-CATALOG-GENERATION !
    _laf-collection-key _laf-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _laf-assert
    S" Functional collection" _laf-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE!
        LIBSTORE-S-OK = _laf-assert
    _laf-member 1 _laf-collection-request
        LIBRARY-COLLECTION-CREATE-MEMBERS!
        LIBSTORE-S-OK = _laf-assert
    _laf-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-VALID?
        _laf-assert
    _laf-collection-request _laf-collection-view _LAPP-STORE
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-OK = _laf-assert
    _laf-collection-view LIBCV.ID DUP RID-PRESENT? _laf-assert
        _laf-collection-rid RID-COPY

    0 _LAPP-DO-COLLECTIONS
    _LAPP-VIEW @ _LAPP-V-COLLECTIONS = _laf-assert
    _LAPP-RETURN-VIEW @ _LAPP-V-ALL = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    0 _LAPP-COLLECTION-ROW LIBCS.REF RREF.ID
        _laf-collection-rid RID= _laf-assert
    _LAPP-PREVIEW-READY @ _laf-assert
    _LAPP-COLLECTION-VIEW LIBCV.MEMBER-N @ 1 = _laf-assert
    0 _LAPP-COLLECTION-VIEW LIBCV-MEMBER _laf-rid RID= _laf-assert

    _LAPP-FILTER-COLLECTION LIBSTORE-S-OK = _laf-assert
    _LAPP-VIEW @ _LAPP-V-ALL = _laf-assert
    _LAPP-FILTER-ACTIVE @ _laf-assert
    _LAPP-FILTER-ID _laf-collection-rid RID= _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-BACK LIBSTORE-S-OK = _laf-assert
    _LAPP-FILTER-ACTIVE @ 0= _laf-assert
    _LAPP-FILTER-ID RID-PRESENT? 0= _laf-assert
    _LAPP-VIEW @ _LAPP-V-ALL = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _laf-stack ;

: _laf-exact-pending-retry  ( -- )
    S" Retried document" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" exact retry body" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE LIBSTORE-S-OK = _laf-assert
    _LAPP-CREATE-REQUEST _laf-create-before
        LIBRARY-MANAGED-CREATE-REQUEST-SIZE CMOVE
    ['] _laf-after-head-fault _LIBMU-CHECKPOINT-XT !
    _LAPP-DISPATCH-PENDING-CREATE LIBSTORE-S-IO = _laf-assert
    _LAPP-PENDING-CREATE @ _LAPP-CREATE-DISPATCHED = _laf-assert
    _LAPP-CREATE-REQUEST LIBRARY-MANAGED-CREATE-REQUEST-SIZE
        _laf-create-before LIBRARY-MANAGED-CREATE-REQUEST-SIZE
        COMPARE 0= _laf-assert
    _LAPP-STORE LIBRARY-VFS-STORE.GENERATION @ DUP
        _laf-retry-generation ! 0> _laf-assert
    _LIBVFS-RESET-MUTATION-HOOKS
    0 _LAPP-DO-RETRY-CREATE
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-PENDING-CREATE @ 0= _laf-assert
    _LAPP-STORE LIBRARY-VFS-STORE.GENERATION @
        _laf-retry-generation @ = _laf-assert
    _LAPP-RESULT-ENTRY LIBE.ID DUP RID-PRESENT? _laf-assert
        _laf-retry-rid RID-COPY
    _LAPP-RESULT-ENTRY LIBE.RECEIPT LIBR.OPERATION-KEY
        _laf-create-before LIBMCR.OPERATION-KEY RID= _laf-assert
    _LAPP-ROW-COUNT @ 2 = _laf-assert
    _laf-stack ;

: _laf-paging-conflict-and-reload  ( -- )
    1 _LAPP-NEXT-SLOT !
    _LAPP-GENERATION @ 1- _LAPP-GENERATION !
    0 _LAPP-DO-NEXT-PAGE
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-PAGE-INDEX @ 0= _laf-assert
    _LAPP-GENERATION @
        _LAPP-STORE LIBRARY-VFS-STORE.GENERATION @ = _laf-assert
    _LAPP-ROW-COUNT @ 2 = _laf-assert

    1 _LAPP-NEXT-SLOT !
    0 _LAPP-DO-NEXT-PAGE
    _LAPP-PAGE-INDEX @ 1 = _laf-assert
    1 _LAPP-PAGE-START @ 1 = _laf-assert
    _LAPP-ROW-COUNT @ 1 = _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-retry-rid RID= _laf-assert
    0 _LAPP-DO-PREVIOUS-PAGE
    _LAPP-PAGE-INDEX @ 0= _laf-assert
    _LAPP-ROW-COUNT @ 2 = _laf-assert

    _LAPP-CORPUS-PAGE
        LIBRARY-QUERY-PAGE-MAX LIBRARY-QUERY-SUMMARY-SIZE * 0 FILL
    _LAPP-ENTRY LIB-ENTRY-SIZE 0 FILL
    0 _LAPP-ROW-COUNT ! 0 _LAPP-PREVIEW-READY !
    0 _LAPP-DO-RELOAD
    _LAPP-LAST-STATUS @ LIBSTORE-S-OK = _laf-assert
    _LAPP-READY? _laf-assert
    _LAPP-PAGE-INDEX @ 0= _laf-assert
    _LAPP-ROW-COUNT @ 2 = _laf-assert
    _LAPP-ENTRY LIB-ENTRY-VALID? _laf-assert
    _LAPP-ENTRY LIBE.ID _laf-rid RID= _laf-assert
    _LAPP-ENTRY LIBE-TITLE$ S" Functional renamed" STR-STR= _laf-assert
    _laf-preview-body? _laf-assert
    _laf-stack ;

: _laf-pending-close-and-discard  ( -- )
    S" Discard pending" DUP _LAPP-PENDING-TITLE-U !
        _LAPP-PENDING-TITLE SWAP CMOVE
    S" never committed" DUP _LAPP-PENDING-BODY-U !
        _LAPP-PENDING-BODY SWAP CMOVE
    _LAPP-CONFIGURE-CREATE LIBSTORE-S-OK = _laf-assert
    _LAPP-PENDING-CREATE @ _LAPP-CREATE-PREPARED = _laf-assert
    0 _LAPP-CURRENT-INSTANCE @ LIBRARY-APPLET-REQUEST-CLOSE-CB
        APP-CLOSE-D-DEFER = _laf-assert
    _LAPP-PROMPT-MODE @ _LAPP-PRM-DISCARD-PENDING = _laf-assert
    _LAPP-PROMPT @ PRM-ACTIVE? _laf-assert
    S" DISCARD" _LAPP-PROMPT @ _PRM-O-INPUT + @ INP-SET-TEXT
    _LAPP-PROMPT @ PRM-HIDE
    _LAPP-PROMPT @ _LAPP-PROMPT-SUBMIT
    _LAPP-PENDING-CREATE @ 0= _laf-assert
    _LAPP-CREATE-REQUEST LIBRARY-MANAGED-CREATE-REQUEST-SIZE
        _laf-zero? _laf-assert
    _LAPP-DISCARD-ARMED @ _laf-assert
    0 _LAPP-CURRENT-INSTANCE @ LIBRARY-APPLET-REQUEST-CLOSE-CB
        APP-CLOSE-D-ALLOW = _laf-assert
    _LAPP-DISCARD-ARMED @ 0= _laf-assert
    _laf-stack ;

: _laf-shell-init  ( instance -- )
    DEPTH _laf-init-entry-depth !
    LIBRARY-APPLET-INIT-CB
    DEPTH _laf-init-entry-depth @ 1- = _laf-assert
    DEPTH _laf-depth !
    -1 _laf-ran !
    _laf-create
    _laf-query-and-preview
    _laf-search-clear-and-cancel
    _laf-rename
    _laf-archive
    _laf-history-and-unarchive
    _laf-collection-filter-and-back
    _laf-exact-pending-retry
    _laf-paging-conflict-and-reload
    _laf-pending-close-and-discard
    _laf-stack
    ASHELL-QUIT ;

: _laf-run  ( -- )
    0 _laf-fails ! 0 _laf-checks ! 0 _laf-ran !
    DEPTH _laf-outer-depth !
    _laf-desc LIBRARY-APPLET-ENTRY
    ['] _laf-shell-init _laf-desc APP.INIT-XT !
    _laf-desc ASHELL-RUN
    _laf-ran @ _laf-assert
    DEPTH DUP _laf-outer-depth @ <> IF
        ." LIBRARY APPLET FUNCTIONAL OUTER STACK "
            _laf-outer-depth @ . ." -> " DUP . CR .S CR
    THEN
    _laf-outer-depth @ = _laf-assert
    _laf-fails @ ?DUP IF
        ." LIBRARY APPLET FUNCTIONAL FAIL " .
            ." / " _laf-checks @ . CR
    ELSE
        ." LIBRARY APPLET FUNCTIONAL PASS " _laf-checks @ . CR
    THEN ;

_laf-run
