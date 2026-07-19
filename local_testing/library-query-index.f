\ =====================================================================
\  Gate 4 milestone 3: disposable index and bounded corpus queries
\ =====================================================================
\  Corpus construction and every observed domain fact use the public
\  Library owner surface.  The only private operations are narrow
\  deterministic loss/damage seams for activation-local acceleration state.

VARIABLE _lqi-fails
VARIABLE _lqi-checks
VARIABLE _lqi-depth
VARIABLE _lqi-store-slot
VARIABLE _lqi-vfs
VARIABLE _lqi-old-vfs
VARIABLE _lqi-arena
VARIABLE _lqi-status
VARIABLE _lqi-required
VARIABLE _lqi-count
VARIABLE _lqi-next
VARIABLE _lqi-generation
VARIABLE _lqi-saved-next
VARIABLE _lqi-saved-generation
VARIABLE _lqi-term-a
VARIABLE _lqi-term-u
VARIABLE _lqi-mask
VARIABLE _lqi-perf-cycles
VARIABLE _lqi-perf-stalls
VARIABLE _lqi-perf-extmem

CREATE _lqi-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lqi-key-a LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lqi-key-b LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lqi-key-c LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lqi-collection-key-a LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lqi-collection-key-b LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lqi-rid-a LIB-DIGEST-SIZE ALLOT
CREATE _lqi-rid-b LIB-DIGEST-SIZE ALLOT
CREATE _lqi-rid-c LIB-DIGEST-SIZE ALLOT
CREATE _lqi-collection-rid-a LIB-DIGEST-SIZE ALLOT
CREATE _lqi-collection-rid-b LIB-DIGEST-SIZE ALLOT
CREATE _lqi-zero-rid LIB-DIGEST-SIZE ALLOT
CREATE _lqi-origin LIB-ORIGIN-SIZE ALLOT
CREATE _lqi-managed-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lqi-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-SIZE ALLOT
CREATE _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _lqi-metadata LIBRARY-METADATA-SIZE ALLOT
CREATE _lqi-entry LIB-ENTRY-SIZE ALLOT
CREATE _lqi-read-entry LIB-ENTRY-SIZE ALLOT
CREATE _lqi-read-content LIB-CONTENT-SIZE ALLOT
CREATE _lqi-members LIB-DIGEST-SIZE 2 * ALLOT
CREATE _lqi-collection-request
    LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _lqi-collection-view LIBRARY-COLLECTION-VIEW-SIZE ALLOT
CREATE _lqi-head-before LIB-HEAD-FACT-SIZE ALLOT
CREATE _lqi-bank-before LIB-BANK-FACT-SIZE ALLOT
CREATE _lqi-arena-before LIB-ARENA-FACT-SIZE ALLOT
CREATE _lqi-bad-utf8 2 ALLOT
LIBRARY-CORPUS-TERM-MAX 1+ XBUF _lqi-long-term
LIBRARY-QUERY-SUMMARY-SIZE 4 * XBUF _lqi-page
LIBRARY-QUERY-SUMMARY-SIZE 4 * XBUF _lqi-baseline
LIBRARY-COLLECTION-SUMMARY-SIZE 2 * XBUF _lqi-collection-page
LIB-CONTENT-MAX XBUF _lqi-bytes

: _lqi-store  ( -- store ) _lqi-store-slot @ ;

: _lqi-assert  ( flag -- )
    1 _lqi-checks +!
    0= IF
        1 _lqi-fails +!
        ." LIBRARY QUERY INDEX ASSERT " _lqi-checks @ . CR
    THEN ;

: _lqi-stack  ( -- )
    DEPTH DUP _lqi-depth @ <> IF
        ." LIBRARY QUERY INDEX STACK "
        _lqi-depth @ . ." -> " DUP . CR .S CR
    THEN
    _lqi-depth @ = _lqi-assert ;

: _lqi-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _lqi-summary  ( index -- summary )
    LIBRARY-QUERY-SUMMARY-SIZE * _lqi-page + ;

: _lqi-collection-summary  ( index -- summary )
    LIBRARY-COLLECTION-SUMMARY-SIZE * _lqi-collection-page + ;

: _lqi-id-at?  ( rid index -- flag )
    _lqi-summary LIBQS.REF RREF.ID RID= ;

: _lqi-collection-id-at?  ( rid index -- flag )
    _lqi-collection-summary LIBCS.REF RREF.ID RID= ;

: _lqi-query  ( summaries capacity -- )
    >R _lqi-query-request SWAP R> _lqi-store
        LIBRARY-VFS-STORE-QUERY-CORPUS
    _lqi-status ! _lqi-generation ! _lqi-next ! _lqi-count ! ;

: _lqi-query-active  ( expected start -- )
    _lqi-page 4 _lqi-store LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lqi-status ! _lqi-generation ! _lqi-next ! _lqi-count ! ;

: _lqi-query-collections  ( expected start summaries capacity -- )
    _lqi-store LIBRARY-VFS-STORE-QUERY-COLLECTIONS
    _lqi-status ! _lqi-generation ! _lqi-next ! _lqi-count ! ;

: _lqi-query-request!  ( term-a term-u -- )
    _lqi-term-u ! _lqi-term-a !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _lqi-term-a @ _lqi-term-u @ _lqi-query-request
        LIBRARY-CORPUS-QUERY-TERM!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID?
        _lqi-assert ;

: _lqi-field-query  ( term-a term-u field-mask -- )
    _lqi-mask ! _lqi-query-request!
    _lqi-mask @ _lqi-query-request LIBCQR.FIELD-MASK !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID?
        _lqi-assert
    _lqi-page 4 _lqi-query ;

: _lqi-kind-query  ( kind-mask -- )
    S" needle" _lqi-query-request!
    _lqi-query-request LIBCQR.KIND-MASK !
    _lqi-page 4 _lqi-query ;

: _lqi-media-query  ( media-mask -- )
    S" needle" _lqi-query-request!
    _lqi-query-request LIBCQR.MEDIA-MASK !
    _lqi-page 4 _lqi-query ;

: _lqi-lifecycle-query  ( lifecycle-mask -- )
    S" needle" _lqi-query-request!
    _lqi-query-request LIBCQR.LIFECYCLE-MASK !
    _lqi-page 4 _lqi-query ;

: _lqi-read  ( rid domain-revision -- )
    _lqi-bytes LIB-CONTENT-MAX _lqi-read-entry _lqi-read-content
        _lqi-store LIBRARY-VFS-STORE-READ-EXACT
    _lqi-status ! _lqi-required ! ;

: _lqi-profile-start  ( -- )
    _LIBPQ-RESET
    PERF-RESET ;

: _lqi-profile-stop  ( -- )
    PERF-CYCLES _lqi-perf-cycles !
    PERF-STALLS _lqi-perf-stalls !
    PERF-EXTMEM _lqi-perf-extmem ! ;

: _lqi-profile-line  ( label-a label-u -- )
    ." LIBRARY EFFICIENCY BASELINE " TYPE
    ."  cycles=" _lqi-perf-cycles @ .
    ."  stalls=" _lqi-perf-stalls @ .
    ."  extmem=" _lqi-perf-extmem @ .
    ."  full=" _LIBPQ-FULL-VALIDATION@ .
    ."  warm=" _LIBPQ-WARM-ASSURANCE@ .
    ."  index=" _LIBPQ-INDEX-REBUILD@ .
    ."  entry=" _LIBPQ-ENTRY-READ@ .
    ."  collection=" _LIBPQ-COLLECTION-READ@ .
    ."  direct=" _LIBPQ-DIRECT-FRAME-READ@ .
    ."  direct-bytes=" _LIBPQ-DIRECT-FRAME-BYTES@ .
    ."  scans=" _LIBPQ-ARENA-SCAN@ .
    ."  frames=" _LIBPQ-ARENA-SCAN-FRAME@ .
    ."  scan-bytes=" _LIBPQ-ARENA-SCAN-BYTES@ . CR ;

: _lqi-empty-provisioned-baseline  ( -- )
    \ Reopen the just-provisioned four-file corpus so the fixed cold cost and
    \ both first/repeated empty warm calls are independently visible.
    _lqi-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lqi-assert
    _lqi-vfs @ _lqi-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lqi-assert
    _lqi-profile-start
    _lqi-store LIBRARY-VFS-STORE-LOAD _lqi-status !
    _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 1 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqi-assert
    S" empty-cold-load" _lqi-profile-line

    0 0 _lqi-query-request!
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 0= _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 1 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ENTRY-READ@ 0= _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lqi-assert
    S" empty-first" _lqi-profile-line

    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 0= _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 1 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ENTRY-READ@ 0= _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lqi-assert
    S" empty-repeat" _lqi-profile-line
    _lqi-stack ;

\ Deterministic warm-path cost witness.  Every unchanged operation must retain
\ exact public results without another full validation or index publication.
: _lqi-efficiency-baseline  ( -- )
    S" titleonly" _lqi-query-request!
    LIBRARY-CORPUS-FIELD-TITLE _lqi-query-request LIBCQR.FIELD-MASK !
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    S" title-first" _lqi-profile-line

    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    S" title-repeat" _lqi-profile-line

    _lqi-profile-start
    0 0 _lqi-collection-page 2 _lqi-query-collections
    _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 2 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    S" collections" _lqi-profile-line

    0 0 _lqi-query-request!
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ENTRY-READ@ 3 = _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    S" empty-browse" _lqi-profile-line

    S" newbody" _lqi-query-request!
    LIBRARY-CORPUS-FIELD-BODY _lqi-query-request LIBCQR.FIELD-MASK !
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 1 = _lqi-assert
    _LIBPQ-DIRECT-FRAME-BYTES@ 512 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    S" body-hit" _lqi-profile-line

    S" unfindable" _lqi-query-request!
    LIBRARY-CORPUS-FIELD-BODY _lqi-query-request LIBCQR.FIELD-MASK !
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    S" body-bloom-miss" _lqi-profile-line

    S" z" _lqi-query-request!
    LIBRARY-CORPUS-FIELD-BODY _lqi-query-request LIBCQR.FIELD-MASK !
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 3 = _lqi-assert
    _LIBPQ-DIRECT-FRAME-BYTES@ 1536 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    S" body-short-miss" _lqi-profile-line

    _lqi-profile-start 0 0 _lqi-query-active _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ENTRY-READ@ 3 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    S" active-warm" _lqi-profile-line

    _lqi-profile-start _lqi-rid-a 3 _lqi-read _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-required @ 23 = _lqi-assert
    _lqi-read-content LIBCT-DATA$
        S" newbody bodyonly needle" COMPARE 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ENTRY-READ@ 1 = _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 1 = _lqi-assert
    _LIBPQ-DIRECT-FRAME-BYTES@ 512 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    S" exact-current" _lqi-profile-line
    _lqi-stack ;

: _lqi-authority-snapshot  ( -- )
    _lqi-store LIBRARY-VFS-STORE.HEAD _lqi-head-before
        LIB-HEAD-FACT-SIZE CMOVE
    _lqi-store LIBRARY-VFS-STORE.BANK _lqi-bank-before
        LIB-BANK-FACT-SIZE CMOVE
    _lqi-store LIBRARY-VFS-STORE.ARENA _lqi-arena-before
        LIB-ARENA-FACT-SIZE CMOVE ;

: _lqi-authority-unchanged  ( -- )
    _lqi-store LIBRARY-VFS-STORE.HEAD LIB-HEAD-FACT-SIZE
        _lqi-head-before LIB-HEAD-FACT-SIZE COMPARE 0= _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.BANK LIB-BANK-FACT-SIZE
        _lqi-bank-before LIB-BANK-FACT-SIZE COMPARE 0= _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.ARENA LIB-ARENA-FACT-SIZE
        _lqi-arena-before LIB-ARENA-FACT-SIZE COMPARE 0= _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 8 = _lqi-assert ;

: _lqi-authority-recovery-contracts  ( -- )
    _lqi-authority-snapshot
    _LIBAUTH-TEST-DAMAGE LIBSTORE-S-OK = _lqi-assert
    _lqi-profile-start 0 0 _lqi-query-active _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqi-assert
    _LIBPQ-ENTRY-READ@ 3 = _lqi-assert
    _lqi-authority-unchanged
    S" authority-recover" _lqi-profile-line

    _lqi-profile-start 0 0 _lqi-query-active _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ENTRY-READ@ 3 = _lqi-assert
    _lqi-authority-unchanged
    S" authority-repeat" _lqi-profile-line
    _lqi-stack ;

: _lqi-locator-recovery-contracts  ( -- )
    _lqi-authority-snapshot
    _LIBLOC-TEST-DAMAGE LIBSTORE-S-OK = _lqi-assert
    _lqi-profile-start _lqi-rid-a 3 _lqi-read _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-required @ 23 = _lqi-assert
    _lqi-read-content LIBCT-DATA$
        S" newbody bodyonly needle" COMPARE 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 1 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    _lqi-authority-unchanged
    S" locator-recover" _lqi-profile-line

    _lqi-profile-start _lqi-rid-a 3 _lqi-read _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-required @ 23 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-DIRECT-FRAME-READ@ 1 = _lqi-assert
    _LIBPQ-DIRECT-FRAME-BYTES@ 512 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    _lqi-authority-unchanged
    S" locator-repeat" _lqi-profile-line
    _lqi-stack ;

: _lqi-fact-recovery-contracts  ( -- )
    _lqi-authority-snapshot
    _LIBAUTH-TEST-CATALOG-FACT-DAMAGE
        LIBSTORE-S-OK = _lqi-assert
    _lqi-profile-start 0 0 _lqi-query-active _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqi-assert
    _LIBPQ-ENTRY-READ@ 3 = _lqi-assert
    _lqi-authority-unchanged
    S" catalog-fact-recover" _lqi-profile-line

    _LIBAUTH-TEST-COLLECTION-FACT-DAMAGE
        LIBSTORE-S-OK = _lqi-assert
    _lqi-profile-start
    0 0 _lqi-collection-page 2 _lqi-query-collections
    _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 2 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqi-assert
    _LIBPQ-COLLECTION-READ@ 2 = _lqi-assert
    _lqi-authority-unchanged
    S" collection-fact-recover" _lqi-profile-line

    _lqi-profile-start
    0 0 _lqi-collection-page 2 _lqi-query-collections
    _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 2 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-COLLECTION-READ@ 2 = _lqi-assert
    _lqi-authority-unchanged
    S" collection-fact-repeat" _lqi-profile-line
    _lqi-stack ;

\ ---------------------------------------------------------------------
\ Deterministic authoritative corpus
\ ---------------------------------------------------------------------

: _lqi-create-a  ( -- )
    _lqi-managed-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    1 _lqi-managed-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lqi-key-a _lqi-managed-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lqi-assert
    S" Needle titleonly Café" _lqi-managed-request
        LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lqi-assert
    S" oldbody needle" _lqi-managed-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lqi-assert
    LIB-MEDIA-TEXT-MARKDOWN _lqi-managed-request LIBMCR.MEDIA !
    _lqi-managed-request LIBRARY-MANAGED-CREATE-REQUEST-VALID?
        _lqi-assert
    _lqi-managed-request _lqi-entry _lqi-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lqi-assert
    _lqi-entry LIBE.ID _lqi-rid-a RID-COPY
    _lqi-entry LIBE.DOMAIN-REVISION @ 1 = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lqi-assert ;

: _lqi-old-body-before-replace  ( -- )
    S" oldbody" LIBRARY-CORPUS-FIELD-BODY _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-generation @ 2 = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert ;

: _lqi-replace-a  ( -- )
    _lqi-rid-a 1 S" newbody bodyonly needle" _lqi-entry _lqi-store
        LIBRARY-VFS-STORE-REPLACE-MANAGED
        LIBSTORE-S-OK = _lqi-assert
    _lqi-entry LIBE.DOMAIN-REVISION @ 2 = _lqi-assert
    _lqi-entry LIBE.CURRENT-CONTENT-REVISION @ 2 = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lqi-assert

    S" oldbody" LIBRARY-CORPUS-FIELD-BODY _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-generation @ 3 = _lqi-assert
    _lqi-count @ 0= _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    S" newbody" LIBRARY-CORPUS-FIELD-BODY _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert ;

: _lqi-metadata-a  ( -- )
    _lqi-metadata LIBRARY-METADATA-INIT
    S" Needle titleonly Café" _lqi-metadata
        LIBRARY-METADATA-TITLE! LIBSTORE-S-OK = _lqi-assert
    S" needle" 0 _lqi-metadata
        LIBRARY-METADATA-TAG! LIBSTORE-S-OK = _lqi-assert
    S" tagonly" 1 _lqi-metadata
        LIBRARY-METADATA-TAG! LIBSTORE-S-OK = _lqi-assert
    _lqi-metadata LIBRARY-METADATA-VALID? _lqi-assert
    _lqi-rid-a 2 _lqi-metadata _lqi-entry _lqi-store
        LIBRARY-VFS-STORE-REPLACE-METADATA
        LIBSTORE-S-OK = _lqi-assert
    _lqi-entry LIBE.DOMAIN-REVISION @ 3 = _lqi-assert
    _lqi-entry LIBE.TAG-N @ 2 = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 4 = _lqi-assert ;

: _lqi-create-b  ( -- )
    _lqi-managed-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    4 _lqi-managed-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lqi-key-b _lqi-managed-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lqi-assert
    S" Plain managed resource" _lqi-managed-request
        LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lqi-assert
    S" needle plain body" _lqi-managed-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lqi-assert
    LIB-MEDIA-TEXT-PLAIN _lqi-managed-request LIBMCR.MEDIA !
    _lqi-managed-request LIBRARY-MANAGED-CREATE-REQUEST-VALID?
        _lqi-assert
    _lqi-managed-request _lqi-entry _lqi-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lqi-assert
    _lqi-entry LIBE.ID _lqi-rid-b RID-COPY
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 5 = _lqi-assert ;

: _lqi-build-origin  ( -- )
    _lqi-origin LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _lqi-origin LIBO.KIND !
    S" /query/needle.csv"
        DUP _lqi-origin LIBO.VFS LIBV.PATH-U !
        _lqi-origin LIBO.VFS LIBV.PATH SWAP CMOVE
    S" csv needle payload"
        DUP _lqi-origin LIBO.VFS LIBV.CONTENT-U !
        _lqi-origin LIBO.VFS LIBV.CONTENT-DIGEST SHA3-256-HASH
    QLOC-DK-PROJECTION-CONTENT
        _lqi-origin LIBO.VFS LIBV.DIGEST-KIND !
    _lqi-origin LIB-ORIGIN-VALID? _lqi-assert ;

: _lqi-create-c  ( -- )
    _lqi-build-origin
    _lqi-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-INIT
    5 _lqi-capture-request LIBCIR.EXPECTED-CATALOG-GENERATION !
    _lqi-key-c _lqi-capture-request
        LIBRARY-CAPTURE-IMPORT-OPERATION-KEY!
        LIBSTORE-S-OK = _lqi-assert
    S" Needle CSV capture" _lqi-capture-request
        LIBRARY-CAPTURE-IMPORT-TITLE!
        LIBSTORE-S-OK = _lqi-assert
    S" csv needle payload" _lqi-capture-request
        LIBRARY-CAPTURE-IMPORT-CONTENT!
        LIBSTORE-S-OK = _lqi-assert
    LIB-MEDIA-TEXT-CSV _lqi-capture-request LIBCIR.MEDIA !
    _lqi-origin _lqi-capture-request
        LIBRARY-CAPTURE-IMPORT-ORIGIN!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-capture-request LIBRARY-CAPTURE-IMPORT-REQUEST-VALID?
        _lqi-assert
    _lqi-capture-request _lqi-entry _lqi-store
        LIBRARY-VFS-STORE-IMPORT-CAPTURE
        LIBSTORE-S-OK = _lqi-assert
    _lqi-entry LIBE.ID _lqi-rid-c RID-COPY
    _lqi-entry LIBE.KIND @ LIB-KIND-CAPTURE = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 6 = _lqi-assert ;

: _lqi-create-collections  ( -- )
    _lqi-rid-a _lqi-members RID-COPY
    _lqi-rid-c _lqi-members LIB-DIGEST-SIZE + RID-COPY
    _lqi-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    6 _lqi-collection-request LIBCCR.EXPECTED-CATALOG-GENERATION !
    _lqi-collection-key-a _lqi-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lqi-assert
    S" Alpha query set" _lqi-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-members 2 _lqi-collection-request
        LIBRARY-COLLECTION-CREATE-MEMBERS!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-collection-request _lqi-collection-view _lqi-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-OK = _lqi-assert
    _lqi-collection-view LIBCV.ID _lqi-collection-rid-a RID-COPY
    _lqi-collection-view LIBCV.MEMBER-N @ 2 = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 7 = _lqi-assert

    _lqi-rid-b _lqi-members RID-COPY
    _lqi-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    7 _lqi-collection-request LIBCCR.EXPECTED-CATALOG-GENERATION !
    _lqi-collection-key-b _lqi-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lqi-assert
    S" Beta query set" _lqi-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-members 1 _lqi-collection-request
        LIBRARY-COLLECTION-CREATE-MEMBERS!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-collection-request _lqi-collection-view _lqi-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-OK = _lqi-assert
    _lqi-collection-view LIBCV.ID _lqi-collection-rid-b RID-COPY
    _lqi-collection-view LIBCV.MEMBER-N @ 1 = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 8 = _lqi-assert ;

\ ---------------------------------------------------------------------
\ Request, filter, paging, and collection-query contracts
\ ---------------------------------------------------------------------

: _lqi-request-contracts  ( -- )
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lqi-assert
    0 0 _lqi-query-request LIBRARY-CORPUS-QUERY-TERM!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lqi-assert

    S" needle" _lqi-query-request!
    _lqi-query-request LIBCQR-TERM$ _lqi-query-request
        LIBRARY-CORPUS-QUERY-TERM! LIBSTORE-S-OK = _lqi-assert
    _lqi-query-request LIBCQR-TERM$ S" needle" COMPARE 0= _lqi-assert
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lqi-assert

    _lqi-long-term LIBRARY-CORPUS-TERM-MAX 1+ [CHAR] x FILL
    _lqi-long-term LIBRARY-CORPUS-TERM-MAX 1+ _lqi-query-request
        LIBRARY-CORPUS-QUERY-TERM!
        LIBSTORE-S-OUTPUT-CAPACITY = _lqi-assert
    0xC0 _lqi-bad-utf8 C! 0xAF _lqi-bad-utf8 1+ C!
    _lqi-bad-utf8 2 _lqi-query-request LIBRARY-CORPUS-QUERY-TERM!
        LIBSTORE-S-INVALID = _lqi-assert

    S" needle" _lqi-query-request!
    0 _lqi-query-request LIBCQR.LIFECYCLE-MASK !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    S" needle" _lqi-query-request!
    4 _lqi-query-request LIBCQR.KIND-MASK !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    S" needle" _lqi-query-request!
    8 _lqi-query-request LIBCQR.MEDIA-MASK !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    S" needle" _lqi-query-request!
    0 _lqi-query-request LIBCQR.FIELD-MASK !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    S" needle" _lqi-query-request!
    1 _lqi-query-request LIBCQR.FLAGS !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    S" needle" _lqi-query-request!
    -1 _lqi-query-request LIBCQR.EXPECTED-CATALOG-GENERATION !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    S" needle" _lqi-query-request!
    -1 _lqi-query-request LIBCQR.START-SLOT !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    S" needle" _lqi-query-request!
    1 _lqi-query-request LIBCQR.START-SLOT !
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _lqi-assert
    _lqi-zero-rid _lqi-query-request
        LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBSTORE-S-INVALID = _lqi-assert
    \ The setter must preserve a RID shifted right from an overlapping source.
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _lqi-collection-rid-a _lqi-query-request LIBCQR.COLLECTION 1-
        LIB-DIGEST-SIZE MOVE
    _lqi-query-request LIBCQR.COLLECTION 1- _lqi-query-request
        LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-query-request LIBCQR.COLLECTION _lqi-collection-rid-a RID=
        _lqi-assert
    S" needle" _lqi-query-request!
    _lqi-collection-rid-a _lqi-query-request
        LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _lqi-assert
    _lqi-stack ;

: _lqi-field-contracts  ( -- )
    S" titleonly" LIBRARY-CORPUS-FIELD-TITLE _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    S" bodyonly" LIBRARY-CORPUS-FIELD-BODY _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    S" tagonly" LIBRARY-CORPUS-FIELD-TAGS _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    S" tag" LIBRARY-CORPUS-FIELD-TAGS _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 0= _lqi-assert

    \ One/two-byte terms bypass trigrams but retain exact byte semantics.
    S" N" LIBRARY-CORPUS-FIELD-TITLE _lqi-field-query
    _lqi-count @ 2 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-c 1 _lqi-id-at? _lqi-assert
    S" Ne" LIBRARY-CORPUS-FIELD-TITLE _lqi-field-query
    _lqi-count @ 2 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-c 1 _lqi-id-at? _lqi-assert

    S" needle" LIBRARY-CORPUS-FIELD-ALL _lqi-field-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-b 1 _lqi-id-at? _lqi-assert
    _lqi-rid-c 2 _lqi-id-at? _lqi-assert

    S" Needle" LIBRARY-CORPUS-FIELD-TITLE _lqi-field-query
    _lqi-count @ 2 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-c 1 _lqi-id-at? _lqi-assert
    S" needle" LIBRARY-CORPUS-FIELD-TITLE _lqi-field-query
    _lqi-count @ 0= _lqi-assert
    S" Café" LIBRARY-CORPUS-FIELD-TITLE _lqi-field-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    S" café" LIBRARY-CORPUS-FIELD-TITLE _lqi-field-query
    _lqi-count @ 0= _lqi-assert

    0 0 _lqi-query-request!
    _lqi-page 4 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-stack ;

: _lqi-filter-contracts  ( -- )
    LIBRARY-CORPUS-KIND-MANAGED _lqi-kind-query
    _lqi-count @ 2 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-b 1 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-KIND-CAPTURE _lqi-kind-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-c 0 _lqi-id-at? _lqi-assert

    LIBRARY-CORPUS-MEDIA-MARKDOWN _lqi-media-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-MEDIA-PLAIN _lqi-media-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-b 0 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-MEDIA-CSV _lqi-media-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-c 0 _lqi-id-at? _lqi-assert

    S" needle" _lqi-query-request!
    _lqi-collection-rid-a _lqi-query-request
        LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-page 4 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 2 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-c 1 _lqi-id-at? _lqi-assert
    _lqi-stack ;

: _lqi-paging-contracts  ( -- )
    S" needle" _lqi-query-request!
    _lqi-page 1 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-next @ DUP 0> _lqi-assert _lqi-saved-next !
    _lqi-generation @ DUP 8 = _lqi-assert _lqi-saved-generation !

    _lqi-saved-generation @ _lqi-query-request
        LIBCQR.EXPECTED-CATALOG-GENERATION !
    _lqi-saved-next @ _lqi-query-request LIBCQR.START-SLOT !
    _lqi-page 1 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-b 0 _lqi-id-at? _lqi-assert
    _lqi-next @ DUP 0> _lqi-assert _lqi-saved-next !

    _lqi-saved-next @ _lqi-query-request LIBCQR.START-SLOT !
    _lqi-page 1 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-c 0 _lqi-id-at? _lqi-assert
    _lqi-next @ -1 = _lqi-assert

    \ Raw cursors cross a nonmatching catalog slot without skipping the
    \ later title match.
    S" Needle" _lqi-query-request!
    LIBRARY-CORPUS-FIELD-TITLE
        _lqi-query-request LIBCQR.FIELD-MASK !
    _lqi-page 1 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-next @ DUP 1 = _lqi-assert _lqi-saved-next !
    _lqi-generation @ _lqi-query-request
        LIBCQR.EXPECTED-CATALOG-GENERATION !
    _lqi-saved-next @ _lqi-query-request LIBCQR.START-SLOT !
    _lqi-page 1 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert _lqi-rid-c 0 _lqi-id-at? _lqi-assert
    _lqi-next @ -1 = _lqi-assert

    S" needle" _lqi-query-request!
    _lqi-page LIBRARY-QUERY-SUMMARY-SIZE 165 FILL
    _lqi-page LIBRARY-QUERY-PAGE-MAX 1+ _lqi-query
    _lqi-status @ LIBSTORE-S-OUTPUT-CAPACITY = _lqi-assert
    _lqi-page C@ 165 = _lqi-assert
    _lqi-page LIBRARY-QUERY-SUMMARY-SIZE 1- + C@ 165 = _lqi-assert
    _lqi-stack ;

: _lqi-collection-query-contracts  ( -- )
    0 0 _lqi-collection-page 1 _lqi-query-collections
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _lqi-next @ DUP 0> _lqi-assert _lqi-saved-next !
    _lqi-collection-rid-a 0 _lqi-collection-id-at? _lqi-assert
    0 _lqi-collection-summary LIBCS.REF RREF-VALID? _lqi-assert
    0 _lqi-collection-summary LIBCS.REVISION @ 1 = _lqi-assert
    0 _lqi-collection-summary LIBCS.MEMBER-N @ 2 = _lqi-assert
    0 _lqi-collection-summary LIBCS.FLAGS @ 0= _lqi-assert
    0 _lqi-collection-summary LIBCS-TITLE$
        S" Alpha query set" COMPARE 0= _lqi-assert

    8 _lqi-saved-next @ _lqi-collection-page 1 _lqi-query-collections
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-collection-rid-b 0 _lqi-collection-id-at? _lqi-assert
    0 _lqi-collection-summary LIBCS.REVISION @ 1 = _lqi-assert
    0 _lqi-collection-summary LIBCS.MEMBER-N @ 1 = _lqi-assert
    0 _lqi-collection-summary LIBCS-TITLE$
        S" Beta query set" COMPARE 0= _lqi-assert

    _lqi-collection-page LIBRARY-COLLECTION-SUMMARY-SIZE 165 FILL
    0 0 _lqi-collection-page LIBRARY-QUERY-PAGE-MAX 1+
        _lqi-query-collections
    _lqi-status @ LIBSTORE-S-OUTPUT-CAPACITY = _lqi-assert
    _lqi-collection-page C@ 165 = _lqi-assert
    _lqi-collection-page LIBRARY-COLLECTION-SUMMARY-SIZE 1- + C@
        165 = _lqi-assert
    _lqi-stack ;

\ ---------------------------------------------------------------------
\ Disposable rebuild and lifecycle visibility
\ ---------------------------------------------------------------------

: _lqi-index-rebuild-contracts  ( -- )
    S" needle" _lqi-query-request!
    _lqi-page 4 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _lqi-page _lqi-baseline LIBRARY-QUERY-SUMMARY-SIZE 4 * CMOVE
    _lqi-authority-snapshot

    _LIBIX-TEST-LOSE LIBSTORE-S-OK = _lqi-assert
    _lqi-authority-unchanged
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _lqi-page LIBRARY-QUERY-SUMMARY-SIZE 4 *
        _lqi-baseline LIBRARY-QUERY-SUMMARY-SIZE 4 *
        COMPARE 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    _lqi-authority-unchanged
    S" index-loss-rebuild" _lqi-profile-line

    _LIBIX-TEST-DAMAGE LIBSTORE-S-OK = _lqi-assert
    _lqi-authority-unchanged
    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _lqi-page LIBRARY-QUERY-SUMMARY-SIZE 4 *
        _lqi-baseline LIBRARY-QUERY-SUMMARY-SIZE 4 *
        COMPARE 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    _lqi-authority-unchanged
    S" index-damage-rebuild" _lqi-profile-line

    _lqi-profile-start _lqi-page 4 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 3 = _lqi-assert
    _lqi-next @ -1 = _lqi-assert
    _lqi-generation @ 8 = _lqi-assert
    _lqi-page LIBRARY-QUERY-SUMMARY-SIZE 4 *
        _lqi-baseline LIBRARY-QUERY-SUMMARY-SIZE 4 *
        COMPARE 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ARENA-SCAN@ 0= _lqi-assert
    _lqi-authority-unchanged
    S" index-repeat" _lqi-profile-line

    _lqi-rid-a 3 _lqi-read
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-read-content LIBCT-DATA$
        S" newbody bodyonly needle" COMPARE 0= _lqi-assert
    _lqi-stack ;

: _lqi-stale-and-lifecycle-contracts  ( -- )
    S" needle" _lqi-query-request!
    _lqi-page 1 _lqi-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 1 = _lqi-assert
    _lqi-next @ _lqi-saved-next !
    _lqi-generation @ DUP 8 = _lqi-assert _lqi-saved-generation !

    _lqi-rid-b 1 _lqi-entry _lqi-store LIBRARY-VFS-STORE-ARCHIVE
        LIBSTORE-S-OK = _lqi-assert
    _lqi-entry LIBE.DOMAIN-REVISION @ 2 = _lqi-assert
    _lqi-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-ARCHIVED = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 9 = _lqi-assert

    _lqi-saved-generation @ _lqi-query-request
        LIBCQR.EXPECTED-CATALOG-GENERATION !
    _lqi-saved-next @ _lqi-query-request LIBCQR.START-SLOT !
    _lqi-baseline LIBRARY-QUERY-SUMMARY-INIT
    _lqi-page LIBRARY-QUERY-SUMMARY-SIZE 165 FILL
    _lqi-profile-start _lqi-page 1 _lqi-query _lqi-profile-stop
    _lqi-status @ LIBSTORE-S-CONFLICT = _lqi-assert
    _lqi-count @ 0= _lqi-assert
    _lqi-generation @ 9 = _lqi-assert
    _lqi-page LIBQS.REF RREF.ID RID-PRESENT? 0= _lqi-assert
    _lqi-page LIBRARY-QUERY-SUMMARY-SIZE
        _lqi-baseline LIBRARY-QUERY-SUMMARY-SIZE
        COMPARE 0= _lqi-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lqi-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lqi-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lqi-assert
    _LIBPQ-ENTRY-READ@ 0= _lqi-assert
    S" post-mutation-stale-conflict" _lqi-profile-line

    LIBRARY-CORPUS-LIFECYCLE-ACTIVE _lqi-lifecycle-query
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-count @ 2 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-c 1 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-LIFECYCLE-ARCHIVED _lqi-lifecycle-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-b 0 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-LIFECYCLE-ALL _lqi-lifecycle-query
    _lqi-count @ 3 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-b 1 _lqi-id-at? _lqi-assert
    _lqi-rid-c 2 _lqi-id-at? _lqi-assert
    _lqi-rid-b 2 _lqi-read
    _lqi-status @ LIBSTORE-S-OK = _lqi-assert
    _lqi-read-entry LIBE.LIFECYCLE @
        LIB-LIFECYCLE-ARCHIVED = _lqi-assert

    _lqi-rid-c 1 _lqi-entry _lqi-store
        LIBRARY-VFS-STORE-TOMBSTONE-DESTRUCTIVE
        LIBSTORE-S-OK = _lqi-assert
    _lqi-entry LIBE.DOMAIN-REVISION @ 2 = _lqi-assert
    _lqi-entry LIBE.LIFECYCLE @ LIB-LIFECYCLE-TOMBSTONED = _lqi-assert
    _lqi-store LIBRARY-VFS-STORE.GENERATION @ 10 = _lqi-assert

    LIBRARY-CORPUS-LIFECYCLE-ACTIVE _lqi-lifecycle-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-LIFECYCLE-ARCHIVED _lqi-lifecycle-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-b 0 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-LIFECYCLE-ALL _lqi-lifecycle-query
    _lqi-count @ 2 = _lqi-assert
    _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-rid-b 1 _lqi-id-at? _lqi-assert
    LIBRARY-CORPUS-KIND-CAPTURE _lqi-kind-query
    _lqi-count @ 0= _lqi-assert
    _lqi-rid-c 2 _lqi-read
    _lqi-status @ LIBSTORE-S-TOMBSTONED = _lqi-assert
    _lqi-required @ 0= _lqi-assert
    _lqi-read-content LIB-CONTENT-SIZE _lqi-zero? _lqi-assert

    S" needle" _lqi-query-request!
    LIBRARY-CORPUS-LIFECYCLE-ALL
        _lqi-query-request LIBCQR.LIFECYCLE-MASK !
    _lqi-collection-rid-a _lqi-query-request
        LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBSTORE-S-OK = _lqi-assert
    _lqi-page 4 _lqi-query
    _lqi-count @ 1 = _lqi-assert _lqi-rid-a 0 _lqi-id-at? _lqi-assert
    _lqi-stack ;

: _lqi-run  ( -- )
    0 _lqi-fails ! 0 _lqi-checks ! DEPTH _lqi-depth !
    VFS-CUR _lqi-old-vfs !
    _lqi-arena-id LIB-DIGEST-SIZE 0xA6 FILL
    _lqi-key-a LIB-OPERATION-KEY-SIZE 0x51 FILL
    _lqi-key-b LIB-OPERATION-KEY-SIZE 0x52 FILL
    _lqi-key-c LIB-OPERATION-KEY-SIZE 0x53 FILL
    _lqi-collection-key-a LIB-OPERATION-KEY-SIZE 0x61 FILL
    _lqi-collection-key-b LIB-OPERATION-KEY-SIZE 0x62 FILL
    _lqi-zero-rid LIB-DIGEST-SIZE 0 FILL
    4194304 A-XMEM ARENA-NEW DUP 0= _lqi-assert DROP
    DUP _lqi-arena !
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lqi-vfs ! 0<> _lqi-assert
    _lqi-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE ALLOCATE
        ABORT" LIBRARY QUERY INDEX allocation" _lqi-store-slot !
    _lqi-vfs @ _lqi-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lqi-assert
    _lqi-arena-id _lqi-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lqi-assert

    _lqi-empty-provisioned-baseline

    _lqi-create-a
    _lqi-old-body-before-replace
    _lqi-replace-a
    _lqi-metadata-a
    _lqi-create-b
    _lqi-create-c
    _lqi-create-collections
    _lqi-efficiency-baseline
    _lqi-authority-recovery-contracts
    _lqi-locator-recovery-contracts
    _lqi-fact-recovery-contracts
    _lqi-request-contracts
    _lqi-field-contracts
    _lqi-filter-contracts
    _lqi-paging-contracts
    _lqi-collection-query-contracts
    _lqi-index-rebuild-contracts
    _lqi-stale-and-lifecycle-contracts

    _LIBAUTH-READY @ 0<> _lqi-assert
    _LIBIX-READY @ 0<> _lqi-assert
    _lqi-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lqi-assert
    _LIBAUTH-READY @ 0= _lqi-assert
    _LIBIX-READY @ 0= _lqi-assert

    _lqi-store-slot @ FREE 0 _lqi-store-slot !
    _lqi-old-vfs @ VFS-USE
    _lqi-vfs @ VFS-DESTROY
    _lqi-stack
    _lqi-fails @ ?DUP IF
        ." LIBRARY QUERY INDEX FAIL " .
        ." / " _lqi-checks @ . CR
    ELSE
        ." LIBRARY QUERY INDEX PASS " _lqi-checks @ . CR
    THEN ;

_lqi-run
