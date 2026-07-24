\ Caller-owned L12 Library query-domain and keyset-page contracts.

PROVIDED akashic-library-query-l12-contracts

VARIABLE _LQ12-checks
VARIABLE _LQ12-fails
VARIABLE _LQ12-depth

CREATE _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12-request-other LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12-collection-request
    LIBRARY-COLLECTION-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12-history-request
    LIBRARY-HISTORY-QUERY-REQUEST-SIZE ALLOT
CREATE _LQ12-fingerprint-a LIB-DIGEST-SIZE ALLOT
CREATE _LQ12-fingerprint-b LIB-DIGEST-SIZE ALLOT
CREATE _LQ12-rid-a RID-SIZE ALLOT
CREATE _LQ12-rid-b RID-SIZE ALLOT
CREATE _LQ12-bad-utf8 2 ALLOT

CREATE _LQ12-summary LIBRARY-QUERY-SUMMARY-SIZE ALLOT
CREATE _LQ12-collection-summary LIBRARY-COLLECTION-SUMMARY-SIZE ALLOT
CREATE _LQ12-revision-summary LIBRARY-REVISION-SUMMARY-SIZE ALLOT

CREATE _LQ12-continuation LIBRARY-QUERY-CONTINUATION-SIZE ALLOT
CREATE _LQ12-continuation-copy LIBRARY-QUERY-CONTINUATION-SIZE ALLOT
CREATE _LQ12-page LIBRARY-QUERY-PAGE-SIZE ALLOT
CREATE _LQ12-page-copy LIBRARY-QUERY-PAGE-SIZE ALLOT
CREATE _LQ12-corpus-rows LIBRARY-QUERY-SUMMARY-SIZE 2 * ALLOT
CREATE _LQ12-collection-rows
    LIBRARY-COLLECTION-SUMMARY-SIZE 2 * ALLOT
CREATE _LQ12-history-rows LIBRARY-REVISION-SUMMARY-SIZE 2 * ALLOT
LIBRARY-QUERY-WORK-SIZE XBUF _LQ12-work

: _LQ12-assert  ( flag -- )
    1 _LQ12-checks +!
    0= IF
        1 _LQ12-fails +!
        ." LIBRARY QUERY L12 ASSERT " _LQ12-checks @ . CR
    THEN ;

: _LQ12-stack  ( -- )
    DEPTH DUP _LQ12-depth @ <> IF
        ." LIBRARY QUERY L12 STACK "
        _LQ12-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LQ12-depth @ = _LQ12-assert ;

: _LQ12-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY QUERY L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LQ12-assert _LQ12-stack ;

: _LQ12-text!  ( source-a source-u destination length-cell -- )
    >R
    OVER R@ !
    SWAP MOVE
    R> DROP ;

: _LQ12-setup  ( -- )
    _LQ12-rid-a RID-SIZE 0x11 FILL
    _LQ12-rid-b RID-SIZE 0x22 FILL
    0xC0 _LQ12-bad-utf8 C!
    0xAF _LQ12-bad-utf8 1+ C! ;

: _LQ12-request-contracts  ( -- )
    LIBRARY-CORPUS-QUERY-REQUEST-SIZE 208 = _LQ12-assert
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _LQ12-assert
    _LQ12-request LIBCQR.LIFECYCLE-MASK @
        LIBRARY-CORPUS-LIFECYCLE-ACTIVE = _LQ12-assert
    _LQ12-request LIBCQR.KIND-MASK @
        LIBRARY-CORPUS-KIND-ALL = _LQ12-assert
    _LQ12-request LIBCQR.MEDIA-MASK @
        LIBRARY-CORPUS-MEDIA-ALL = _LQ12-assert
    _LQ12-request LIBCQR.FIELD-MASK @
        LIBRARY-CORPUS-FIELD-ALL = _LQ12-assert
    _LQ12-request _LQ12-fingerprint-a
        LIBRARY-CORPUS-QUERY-FINGERPRINT LIBPA-S-OK _LQ12-status

    S" needle" _LQ12-request LIBRARY-CORPUS-QUERY-TERM!
        LIBPA-S-OK _LQ12-status
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _LQ12-assert
    _LQ12-request LIBCQR-TERM$ S" needle" COMPARE 0= _LQ12-assert
    _LQ12-request _LQ12-fingerprint-b
        LIBRARY-CORPUS-QUERY-FINGERPRINT LIBPA-S-OK _LQ12-status
    _LQ12-fingerprint-a _LQ12-fingerprint-b
        SHA3-256-COMPARE 0= _LQ12-assert

    _LQ12-request _LQ12-request-other
        LIBRARY-CORPUS-QUERY-REQUEST-SIZE MOVE
    _LQ12-bad-utf8 2 _LQ12-request LIBRARY-CORPUS-QUERY-TERM!
        LIBPA-S-INVALID _LQ12-status
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE
    _LQ12-request-other LIBRARY-CORPUS-QUERY-REQUEST-SIZE
        COMPARE 0= _LQ12-assert

    _LQ12-rid-a _LQ12-request LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBPA-S-OK _LQ12-status
    _LQ12-request LIBCQR.COLLECTION _LQ12-rid-a RID= _LQ12-assert
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _LQ12-assert

    0 _LQ12-request LIBCQR.LIFECYCLE-MASK !
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _LQ12-assert
    LIBRARY-CORPUS-LIFECYCLE-ALL
        _LQ12-request LIBCQR.LIFECYCLE-MASK !
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _LQ12-assert

    0 _LQ12-request LIBCQR.FIELD-MASK !
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _LQ12-assert
    LIBRARY-CORPUS-FIELD-TITLE
        _LQ12-request LIBCQR.FIELD-MASK !
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _LQ12-assert

    1 _LQ12-request LIBCQR.TERM
        _LQ12-request LIBCQR.TERM-U @ + C!
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? 0= _LQ12-assert
    S" x" _LQ12-request LIBRARY-CORPUS-QUERY-TERM!
        LIBPA-S-OK _LQ12-status
    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-VALID? _LQ12-assert

    _LQ12-request _LQ12-request LIBCQR.TERM
        LIBRARY-CORPUS-QUERY-FINGERPRINT
        LIBPA-S-INVALID _LQ12-status
    _LQ12-stack ;

: _LQ12-summary-contracts  ( -- )
    _LQ12-summary LIBRARY-QUERY-SUMMARY-INIT
    _LQ12-summary LIBRARY-QUERY-SUMMARY-VALID? 0= _LQ12-assert
    _LQ12-rid-a _LQ12-summary LIBQS.REF RREF.ID RID-COPY
    3 _LQ12-summary LIBQS.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _LQ12-summary LIBQS.KIND !
    LIB-LIFECYCLE-ACTIVE _LQ12-summary LIBQS.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _LQ12-summary LIBQS.MEDIA !
    12 _LQ12-summary LIBQS.CONTENT-U !
    7 _LQ12-summary LIBQS.MUTATION-SEQUENCE !
    _LQ12-summary LIBQS.CONTENT-DIGEST RID-SIZE 0x33 FILL
    S" Summary" _LQ12-summary LIBQS.TITLE
        _LQ12-summary LIBQS.TITLE-U _LQ12-text!
    _LQ12-summary LIBRARY-QUERY-SUMMARY-VALID? _LQ12-assert
    LIB-MEDIA-TEXT-CSV _LQ12-summary LIBQS.MEDIA !
    _LQ12-summary LIBRARY-QUERY-SUMMARY-VALID? 0= _LQ12-assert
    LIB-KIND-CAPTURE _LQ12-summary LIBQS.KIND !
    _LQ12-summary LIBRARY-QUERY-SUMMARY-VALID? _LQ12-assert
    LIB-KIND-MANAGED-DOCUMENT _LQ12-summary LIBQS.KIND !
    LIB-MEDIA-TEXT-PLAIN _LQ12-summary LIBQS.MEDIA !
    LIB-LIFECYCLE-TOMBSTONED _LQ12-summary LIBQS.LIFECYCLE !
    _LQ12-summary LIBRARY-QUERY-SUMMARY-VALID? 0= _LQ12-assert
    LIB-LIFECYCLE-ARCHIVED _LQ12-summary LIBQS.LIFECYCLE !
    _LQ12-summary LIBRARY-QUERY-SUMMARY-VALID? _LQ12-assert
    _LQ12-summary LIBQS.TITLE LIB-TITLE-MAX 0 FILL
    0 _LQ12-summary LIBQS.TITLE-U !
    _LQ12-summary LIBRARY-QUERY-SUMMARY-VALID? 0= _LQ12-assert

    _LQ12-collection-summary LIBRARY-COLLECTION-SUMMARY-INIT
    _LQ12-rid-b
        _LQ12-collection-summary LIBCS.REF RREF.ID RID-COPY
    2 _LQ12-collection-summary LIBCS.REVISION !
    9 _LQ12-collection-summary LIBCS.MUTATION-SEQUENCE !
    1000000 _LQ12-collection-summary LIBCS.MEMBER-N !
    S" Collection" _LQ12-collection-summary LIBCS.TITLE
        _LQ12-collection-summary LIBCS.TITLE-U _LQ12-text!
    _LQ12-collection-summary
        LIBRARY-COLLECTION-SUMMARY-VALID? _LQ12-assert
    _LQ12-collection-summary LIBCS.TITLE
        LIB-COLLECTION-TITLE-MAX 0 FILL
    0 _LQ12-collection-summary LIBCS.TITLE-U !
    _LQ12-collection-summary
        LIBRARY-COLLECTION-SUMMARY-VALID? 0= _LQ12-assert

    _LQ12-revision-summary LIBRARY-REVISION-SUMMARY-INIT
    7 _LQ12-revision-summary LIBRS.DOMAIN-REVISION !
    4 _LQ12-revision-summary LIBRS.CONTENT-REVISION !
    LIB-MEDIA-TEXT-MARKDOWN _LQ12-revision-summary LIBRS.MEDIA !
    900000 _LQ12-revision-summary LIBRS.CONTENT-U !
    _LQ12-revision-summary LIBRS.DIGEST RID-SIZE 0x44 FILL
    _LQ12-revision-summary
        LIBRARY-REVISION-SUMMARY-VALID? _LQ12-assert
    3 _LQ12-revision-summary LIBRS.DOMAIN-REVISION !
    _LQ12-revision-summary
        LIBRARY-REVISION-SUMMARY-VALID? 0= _LQ12-assert
    _LQ12-stack ;

: _LQ12-fill-continuation  ( -- )
    _LQ12-continuation LIBRARY-QUERY-CONTINUATION-INIT
    _LQ12-fingerprint-b
        _LQ12-continuation LIBQC.FINGERPRINT RID-COPY
    11 _LQ12-continuation LIBQC.OBSERVED-LOGICAL-GENERATION !
    3 _LQ12-continuation LIBQC.FIRST-ORDER-SEQUENCE !
    _LQ12-rid-a _LQ12-continuation LIBQC.FIRST-RID RID-COPY
    8 _LQ12-continuation LIBQC.LAST-ORDER-SEQUENCE !
    _LQ12-rid-b _LQ12-continuation LIBQC.LAST-RID RID-COPY
    LIBRARY-QUERY-CONTINUATION-F-READY
    LIBRARY-QUERY-CONTINUATION-F-ROWS OR
    LIBRARY-QUERY-CONTINUATION-F-BEFORE OR
    LIBRARY-QUERY-CONTINUATION-F-AFTER OR
        _LQ12-continuation LIBQC.FLAGS ! ;

: _LQ12-continuation-contracts  ( -- )
    LIBRARY-QUERY-CONTINUATION-SIZE 136 = _LQ12-assert
    _LQ12-continuation LIBRARY-QUERY-CONTINUATION-INIT
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? _LQ12-assert
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-READY? 0= _LQ12-assert

    _LQ12-fill-continuation
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? _LQ12-assert
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-READY? _LQ12-assert
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-HAS-ROWS? _LQ12-assert
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-HAS-BEFORE? _LQ12-assert
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-HAS-AFTER? _LQ12-assert
    _LQ12-continuation _LQ12-continuation-copy
        LIBRARY-QUERY-CONTINUATION-COPY
        LIBPA-S-OK _LQ12-status
    _LQ12-continuation-copy
        LIBRARY-QUERY-CONTINUATION-VALID? _LQ12-assert

    9 _LQ12-continuation LIBQC.FIRST-ORDER-SEQUENCE !
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? 0= _LQ12-assert
    3 _LQ12-continuation LIBQC.FIRST-ORDER-SEQUENCE !
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? _LQ12-assert
    8 _LQ12-continuation LIBQC.FIRST-ORDER-SEQUENCE !
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? _LQ12-assert
    _LQ12-rid-b _LQ12-continuation LIBQC.FIRST-RID RID-COPY
    _LQ12-rid-a _LQ12-continuation LIBQC.LAST-RID RID-COPY
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? 0= _LQ12-assert
    _LQ12-rid-a _LQ12-continuation LIBQC.FIRST-RID RID-COPY
    _LQ12-rid-b _LQ12-continuation LIBQC.LAST-RID RID-COPY
    3 _LQ12-continuation LIBQC.FIRST-ORDER-SEQUENCE !

    _LQ12-continuation LIBRARY-QUERY-CONTINUATION-INIT
    _LQ12-fingerprint-a
        _LQ12-continuation LIBQC.FINGERPRINT RID-COPY
    12 _LQ12-continuation LIBQC.OBSERVED-LOGICAL-GENERATION !
    LIBRARY-QUERY-CONTINUATION-F-READY
        _LQ12-continuation LIBQC.FLAGS !
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? _LQ12-assert
    LIBRARY-QUERY-CONTINUATION-F-BEFORE
        _LQ12-continuation LIBQC.FLAGS +!
    _LQ12-continuation
        LIBRARY-QUERY-CONTINUATION-VALID? 0= _LQ12-assert
    _LQ12-stack ;

: _LQ12-page-contracts  ( -- )
    LIBRARY-QUERY-PAGE-SIZE 192 = _LQ12-assert
    _LQ12-page LIBRARY-QUERY-PAGE-SIZE 0x5A FILL
    _LQ12-page 2 _LQ12-page LIBRARY-CORPUS-PAGE-INIT
        LIBPA-S-INVALID _LQ12-status
    _LQ12-page C@ 0x5A = _LQ12-assert
    _LQ12-corpus-rows 0 _LQ12-page LIBRARY-CORPUS-PAGE-INIT
        LIBPA-S-INVALID _LQ12-status
    _LQ12-corpus-rows 33 _LQ12-page LIBRARY-CORPUS-PAGE-INIT
        LIBPA-S-INVALID _LQ12-status

    _LQ12-corpus-rows 2 _LQ12-page LIBRARY-CORPUS-PAGE-INIT
        LIBPA-S-OK _LQ12-status
    _LQ12-page LIBRARY-CORPUS-PAGE-VALID? _LQ12-assert
    _LQ12-page LIBQP.COUNT @ 0= _LQ12-assert
    _LQ12-fill-continuation
    _LQ12-continuation _LQ12-page LIBQP.CONTINUATION
        LIBRARY-QUERY-CONTINUATION-COPY
        LIBPA-S-OK _LQ12-status
    2 _LQ12-page LIBQP.COUNT !
    _LQ12-page LIBRARY-CORPUS-PAGE-VALID? _LQ12-assert
    LIBRARY-QUERY-SUMMARY-SIZE 8 +
        _LQ12-page LIBQP.ROW-SIZE !
    _LQ12-page LIBRARY-QUERY-PAGE-VALID? 0= _LQ12-assert
    LIBRARY-QUERY-SUMMARY-SIZE _LQ12-page LIBQP.ROW-SIZE !
    _LQ12-page LIBRARY-CORPUS-PAGE-VALID? _LQ12-assert
    0 _LQ12-page LIBRARY-CORPUS-PAGE-ROW
        _LQ12-corpus-rows = _LQ12-assert
    1 _LQ12-page LIBRARY-CORPUS-PAGE-ROW
        _LQ12-corpus-rows LIBRARY-QUERY-SUMMARY-SIZE + =
        _LQ12-assert
    2 _LQ12-page LIBRARY-CORPUS-PAGE-ROW 0= _LQ12-assert
    -1 _LQ12-page LIBRARY-CORPUS-PAGE-ROW 0= _LQ12-assert
    0 _LQ12-page LIBRARY-COLLECTION-PAGE-ROW 0= _LQ12-assert

    _LQ12-page _LQ12-page-copy LIBRARY-QUERY-PAGE-SIZE MOVE
    _LQ12-page-copy LIBRARY-QUERY-PAGE-VALID? 0= _LQ12-assert
    0 _LQ12-page LIBQP.COUNT !
    _LQ12-page LIBRARY-QUERY-PAGE-VALID? 0= _LQ12-assert

    _LQ12-collection-rows 2 _LQ12-page
        LIBRARY-COLLECTION-PAGE-INIT LIBPA-S-OK _LQ12-status
    _LQ12-page LIBRARY-COLLECTION-PAGE-VALID? _LQ12-assert
    _LQ12-page LIBRARY-CORPUS-PAGE-VALID? 0= _LQ12-assert

    _LQ12-history-rows 2 _LQ12-page
        LIBRARY-HISTORY-PAGE-INIT LIBPA-S-OK _LQ12-status
    _LQ12-page LIBRARY-HISTORY-PAGE-VALID? _LQ12-assert
    _LQ12-stack ;

: _LQ12-other-request-contracts  ( -- )
    _LQ12-collection-request
        LIBRARY-COLLECTION-QUERY-REQUEST-INIT
    _LQ12-collection-request
        LIBRARY-COLLECTION-QUERY-REQUEST-VALID? _LQ12-assert
    _LQ12-collection-request _LQ12-fingerprint-a
        LIBRARY-COLLECTION-QUERY-FINGERPRINT
        LIBPA-S-OK _LQ12-status

    _LQ12-history-request LIBRARY-HISTORY-QUERY-REQUEST-INIT
    _LQ12-history-request
        LIBRARY-HISTORY-QUERY-REQUEST-VALID? 0= _LQ12-assert
    _LQ12-rid-a _LQ12-history-request
        LIBRARY-HISTORY-QUERY-RID! LIBPA-S-OK _LQ12-status
    _LQ12-history-request
        LIBRARY-HISTORY-QUERY-REQUEST-VALID? _LQ12-assert
    _LQ12-history-request _LQ12-fingerprint-a
        LIBRARY-HISTORY-QUERY-FINGERPRINT
        LIBPA-S-OK _LQ12-status
    _LQ12-rid-b _LQ12-history-request
        LIBRARY-HISTORY-QUERY-RID! LIBPA-S-OK _LQ12-status
    _LQ12-history-request _LQ12-fingerprint-b
        LIBRARY-HISTORY-QUERY-FINGERPRINT
        LIBPA-S-OK _LQ12-status
    _LQ12-fingerprint-a _LQ12-fingerprint-b
        SHA3-256-COMPARE 0= _LQ12-assert
    _LQ12-stack ;

: _LQ12-execution-work-contracts  ( -- )
    LIBRARY-QUERY-WORK-SIZE 32768 = _LQ12-assert
    0 LIBRARY-QUERY-WORK-INIT LIBPA-S-INVALID _LQ12-status
    _LQ12-work LIBRARY-QUERY-WORK-INIT LIBPA-S-OK _LQ12-status
    _LQ12-work LIBRARY-QUERY-WORK-VALID? _LQ12-assert
    _LQ12-work LIBRARY-QUERY-WORK-STATUS@
        LIBPA-S-OK _LQ12-status

    S" abcdef" S" cde" _LIBQ-CONTAINS? _LQ12-assert
    S" abcdef" S" cef" _LIBQ-CONTAINS? 0= _LQ12-assert
    S" abcdef" 0 0 _LIBQ-CONTAINS? _LQ12-assert
    S" abc" S" abcdef" _LIBQ-CONTAINS? 0= _LQ12-assert

    _LQ12-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    S" aba" _LQ12-request LIBRARY-CORPUS-QUERY-TERM!
        LIBPA-S-OK _LQ12-status
    _LQ12-request _LQ12-work _LIBQW.REQUEST !
    _LQ12-work _LIBQ-KMP-BUILD
    0 S" xxab" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    _LQ12-work _LIBQW.MATCH-HIT @ 0= _LQ12-assert
    4 S" ayz" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    _LQ12-work _LIBQW.MATCH-HIT @ _LQ12-assert

    _LQ12-work _LIBQ-KMP-BUILD
    0 S" aab" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    _LQ12-work _LIBQW.MATCH-HIT @ 0= _LQ12-assert
    3 S" a" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    _LQ12-work _LIBQW.MATCH-HIT @ _LQ12-assert

    S" ababaca" _LQ12-request LIBRARY-CORPUS-QUERY-TERM!
        LIBPA-S-OK _LQ12-status
    _LQ12-work _LIBQ-KMP-BUILD
    0 _LQ12-work _LIBQW-KMP-CELL @ 0= _LQ12-assert
    1 _LQ12-work _LIBQW-KMP-CELL @ 0= _LQ12-assert
    2 _LQ12-work _LIBQW-KMP-CELL @ 1 = _LQ12-assert
    3 _LQ12-work _LIBQW-KMP-CELL @ 2 = _LQ12-assert
    4 _LQ12-work _LIBQW-KMP-CELL @ 3 = _LQ12-assert
    5 _LQ12-work _LIBQW-KMP-CELL @ 0= _LQ12-assert
    6 _LQ12-work _LIBQW-KMP-CELL @ 1 = _LQ12-assert
    0 S" zzabab" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    6 S" ac" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    _LQ12-work _LIBQW.MATCH-HIT @ 0= _LQ12-assert
    8 S" axx" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    _LQ12-work _LIBQW.MATCH-HIT @ _LQ12-assert

    S" aaaaab" _LQ12-request LIBRARY-CORPUS-QUERY-TERM!
        LIBPA-S-OK _LQ12-status
    _LQ12-work _LIBQ-KMP-BUILD
    0 _LQ12-work _LIBQW-KMP-CELL @ 0= _LQ12-assert
    1 _LQ12-work _LIBQW-KMP-CELL @ 1 = _LQ12-assert
    2 _LQ12-work _LIBQW-KMP-CELL @ 2 = _LQ12-assert
    3 _LQ12-work _LIBQW-KMP-CELL @ 3 = _LQ12-assert
    4 _LQ12-work _LIBQW-KMP-CELL @ 4 = _LQ12-assert
    5 _LQ12-work _LIBQW-KMP-CELL @ 0= _LQ12-assert
    0 S" xxaaaa" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    6 S" ab" _LQ12-work _LIBQ-KMP-SINK
        PERSIST-S-OK _LQ12-status
    _LQ12-work _LIBQW.MATCH-HIT @ _LQ12-assert
    _LQ12-stack ;

: _LQ12-RUN  ( -- )
    DEPTH _LQ12-depth !
    0 _LQ12-checks !
    0 _LQ12-fails !
    LIBRARY-QUERY-WORK-SIZE 32768 = _LQ12-assert
    _LQ12-setup
    _LQ12-request-contracts
    _LQ12-summary-contracts
    _LQ12-continuation-contracts
    _LQ12-page-contracts
    _LQ12-other-request-contracts
    _LQ12-execution-work-contracts
    _LQ12-stack
    _LQ12-fails @ IF
        ." LIBRARY QUERY L12 FAIL " _LQ12-fails @ .
        ." / " _LQ12-checks @ . CR
    ELSE
        ." LIBRARY QUERY L12 PASS " _LQ12-checks @ . CR
    THEN ;
