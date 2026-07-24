\ Focused L12 canonical metadata fact-stream contracts.

PROVIDED akashic-local-testing-lib-metadata-l12

VARIABLE _LM12-checks
VARIABLE _LM12-fails
VARIABLE _LM12-depth

LIB-METADATA-FACT-HEADER-SIZE 5 +
    CONSTANT _LM12-TAG-ALPHA-U
LIB-METADATA-FACT-HEADER-SIZE 4 +
    CONSTANT _LM12-TAG-BETA-U
LIB-METADATA-FACT-HEADER-SIZE LIB-ORIGIN-SIZE +
    CONSTANT _LM12-ORIGIN-FACT-U
LIB-METADATA-FACT-HEADER-SIZE LIB-LINEAGE-SIZE +
    CONSTANT _LM12-LINEAGE-FACT-U
_LM12-TAG-ALPHA-U _LM12-TAG-BETA-U +
    _LM12-ORIGIN-FACT-U + _LM12-LINEAGE-FACT-U +
    CONSTANT _LM12-FACTS-U
_LM12-ORIGIN-FACT-U 2 * CONSTANT _LM12-TWO-ORIGINS-U
_LM12-TAG-ALPHA-U 2 * CONSTANT _LM12-TWO-ALPHAS-U
_LM12-TAG-ALPHA-U _LM12-TAG-BETA-U +
    CONSTANT _LM12-TWO-TAGS-U

CREATE _LM12-facts _LM12-FACTS-U ALLOT
CREATE _LM12-invalid-facts _LM12-TWO-ORIGINS-U ALLOT
CREATE _LM12-summary LIB-METADATA-SUMMARY-SIZE ALLOT
CREATE _LM12-scratch-summary LIB-METADATA-SUMMARY-SIZE ALLOT
CREATE _LM12-invalid-summary LIB-METADATA-SUMMARY-SIZE ALLOT
CREATE _LM12-origin-a LIB-ORIGIN-SIZE ALLOT
CREATE _LM12-origin-b LIB-ORIGIN-SIZE ALLOT
CREATE _LM12-lineage LIB-LINEAGE-SIZE ALLOT
CREATE _LM12-invalid-lineage LIB-LINEAGE-SIZE ALLOT
CREATE _LM12-ref RREF-SIZE ALLOT
CREATE _LM12-origin-digest LIB-DIGEST-SIZE ALLOT
CREATE _LM12-lineage-digest LIB-DIGEST-SIZE ALLOT
CREATE _LM12-expected-digest LIB-DIGEST-SIZE ALLOT
CREATE _LM12-entry LIB-ENTRY-SIZE ALLOT
CREATE _LM12-entry-before LIB-ENTRY-SIZE ALLOT

: _LM12-assert  ( flag -- )
    1 _LM12-checks +!
    0= IF
        1 _LM12-fails +!
        ." LIBRARY METADATA L12 ASSERT " _LM12-checks @ . CR
    THEN ;

: _LM12-status  ( actual expected -- )
    2DUP <> IF
        ." METADATA STATUS actual/expected " 2DUP SWAP . . CR
    THEN
    = _LM12-assert ;

: _LM12-stack  ( -- )
    DEPTH _LM12-depth @ = _LM12-assert ;

: _LM12-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _LM12-text!  ( source-a source-u destination length-cell -- )
    >R OVER R@ ! SWAP MOVE R> DROP ;

: _LM12-fact!  ( fact payload-a payload-u kind -- next-fact )
    3 PICK LIBMF.KIND !
    DUP 3 PICK LIBMF.PAYLOAD-U !
    2 PICK LIBMF.PAYLOAD SWAP MOVE
    DUP LIBMF.PAYLOAD-U @
        LIB-METADATA-FACT-HEADER-SIZE + + ;

: _LM12-origin!  ( -- )
    S" canonical origin content"
        _LM12-origin-digest SHA3-256-HASH
    _LM12-origin-a LIB-ORIGIN-INIT
    LIB-ORIGIN-VFS-SNAPSHOT _LM12-origin-a LIBO.KIND !
    S" /metadata/source-a"
    DUP _LM12-origin-a LIBO.VFS LIBV.PATH-U !
    _LM12-origin-a LIBO.VFS LIBV.PATH SWAP MOVE
    24 _LM12-origin-a LIBO.VFS LIBV.CONTENT-U !
    QLOC-DK-PROJECTION-CONTENT
        _LM12-origin-a LIBO.VFS LIBV.DIGEST-KIND !
    _LM12-origin-digest
        _LM12-origin-a LIBO.VFS LIBV.CONTENT-DIGEST RID-COPY
    _LM12-origin-a LIB-ORIGIN-VALID? _LM12-assert

    _LM12-origin-a _LM12-origin-b LIB-ORIGIN-SIZE MOVE
    [CHAR] b _LM12-origin-b LIBO.VFS LIBV.PATH 17 + C!
    _LM12-origin-b LIB-ORIGIN-VALID? _LM12-assert ;

: _LM12-lineage!  ( -- )
    S" retained semantic lineage"
        _LM12-lineage-digest SHA3-256-HASH
    _LM12-ref RREF-INIT
    _LM12-ref RREF.ID RID-CLEAR
    0x71 _LM12-ref RREF.ID !
    _LM12-lineage LIB-LINEAGE-INIT
    LIB-LINEAGE-RELATION-DERIVED-FROM
        _LM12-lineage LIBLN.RELATION !
    S" org.akashic.library" _LM12-ref 3
        _LM12-lineage-digest QLOC-DK-SEMANTIC-STATE
        S" org.akashic.library.state.v1"
        _LM12-lineage LIBLN.LOCATOR QLOC-EXACT!
        QLOC-S-OK _LM12-status
    _LM12-lineage LIBLN.LOCATOR QLOC-VALID? _LM12-assert ;

: _LM12-facts!  ( -- )
    _LM12-facts _LM12-FACTS-U 0 FILL
    _LM12-facts
    S" alpha" LIB-METADATA-FACT-TAG _LM12-fact!
    S" beta" LIB-METADATA-FACT-TAG _LM12-fact!
    _LM12-origin-a LIB-ORIGIN-SIZE
        LIB-METADATA-FACT-ORIGIN _LM12-fact!
    _LM12-lineage LIB-LINEAGE-SIZE
        LIB-METADATA-FACT-LINEAGE _LM12-fact!
    _LM12-facts - _LM12-FACTS-U = _LM12-assert ;

: _LM12-entry-for-origin!  ( -- )
    _LM12-entry LIB-ENTRY-INIT
    _LM12-entry LIBE.ID RID-CLEAR
    0x91 _LM12-entry LIBE.ID !
    LIB-KIND-CAPTURE _LM12-entry LIBE.KIND !
    _LM12-entry LIBE.RECEIPT >R
    R@ LIB-RECEIPT-INIT
    LIB-IMPORT-VFS-SNAPSHOT R@ LIBR.METHOD !
    24 R@ LIBR.INITIAL-CONTENT-U !
    QLOC-DK-PROJECTION-CONTENT
        R@ LIBR.ORIGIN-DIGEST-KIND !
    _LM12-origin-digest
        R@ LIBR.ORIGIN-STATE-DIGEST RID-COPY
    _LM12-origin-a LIB-ORIGIN-SIZE
        R@ LIBR.LOCATOR-DIGEST SHA3-256-HASH
    LIB-VFS-SOURCE-OWNER$
        R@ LIBR.SOURCE-OWNER
        R@ LIBR.SOURCE-OWNER-U _LM12-text!
    R> DROP ;

: _LM12-empty  ( -- )
    _LM12-scratch-summary LIB-METADATA-SUMMARY-SIZE 165 FILL
    0 0 _LM12-scratch-summary
        LIB-METADATA-SUMMARIZE LIB-S-OK _LM12-status
    _LM12-scratch-summary LIBMS.FACTS-U @ 0= _LM12-assert
    _LM12-scratch-summary LIBMS.TAG-N @ 0= _LM12-assert
    _LM12-scratch-summary LIBMS.ORIGIN-N @ 0= _LM12-assert
    _LM12-scratch-summary LIBMS.LINEAGE-N @ 0= _LM12-assert
    0 0 _LM12-expected-digest SHA3-256-HASH
    _LM12-scratch-summary LIBMS.DIGEST
        _LM12-expected-digest SHA3-256-COMPARE _LM12-assert
    _LM12-scratch-summary LIBMS.DIGEST RID-PRESENT? _LM12-assert
    _LM12-stack ;

: _LM12-canonical  ( -- )
    _LM12-facts _LM12-FACTS-U _LM12-summary
        LIB-METADATA-SUMMARIZE LIB-S-OK _LM12-status
    _LM12-summary LIBMS.FACTS-U @
        _LM12-FACTS-U = _LM12-assert
    _LM12-summary LIBMS.TAG-N @ 2 = _LM12-assert
    _LM12-summary LIBMS.ORIGIN-N @ 1 = _LM12-assert
    _LM12-summary LIBMS.LINEAGE-N @ 1 = _LM12-assert
    _LM12-summary LIBMS.ORIGIN-A @
        _LM12-facts _LM12-TAG-ALPHA-U +
        _LM12-TAG-BETA-U + LIBMF.PAYLOAD = _LM12-assert
    _LM12-facts _LM12-FACTS-U
        _LM12-expected-digest SHA3-256-HASH
    _LM12-summary LIBMS.DIGEST
        _LM12-expected-digest SHA3-256-COMPARE _LM12-assert

    _LM12-entry-for-origin!
    _LM12-summary _LM12-entry
        LIB-METADATA-SUMMARY-APPLY LIB-S-OK _LM12-status
    _LM12-summary _LM12-entry
        LIB-METADATA-SUMMARY-MATCHES-ENTRY? _LM12-assert
    _LM12-entry LIBE.METADATA-U @
        _LM12-FACTS-U = _LM12-assert
    _LM12-entry LIBE.TAG-N @ 2 = _LM12-assert
    _LM12-entry LIBE.ORIGIN-N @ 1 = _LM12-assert
    _LM12-entry LIBE.LINEAGE-N @ 1 = _LM12-assert
    _LM12-entry LIBE.METADATA-DIGEST
        _LM12-summary LIBMS.DIGEST
        SHA3-256-COMPARE _LM12-assert
    _LM12-stack ;

: _LM12-truncation  ( -- )
    _LM12-scratch-summary LIB-METADATA-SUMMARY-SIZE 165 FILL
    _LM12-facts _LM12-FACTS-U 1-
        _LM12-scratch-summary
        LIB-METADATA-SUMMARIZE LIB-S-INVALID _LM12-status
    \ Completed facts remain summarized, but the truncated lineage does not.
    _LM12-scratch-summary LIBMS.FACTS-U @
        _LM12-FACTS-U 1- = _LM12-assert
    _LM12-scratch-summary LIBMS.TAG-N @ 2 = _LM12-assert
    _LM12-scratch-summary LIBMS.ORIGIN-N @ 1 = _LM12-assert
    _LM12-scratch-summary LIBMS.LINEAGE-N @ 0= _LM12-assert
    _LM12-scratch-summary LIBMS.ORIGIN-A @
        _LM12-facts _LM12-TAG-ALPHA-U +
        _LM12-TAG-BETA-U + LIBMF.PAYLOAD = _LM12-assert
    _LM12-stack ;

: _LM12-duplicate-origin  ( -- )
    _LM12-invalid-facts _LM12-TWO-ORIGINS-U 0 FILL
    _LM12-invalid-facts
    _LM12-origin-a LIB-ORIGIN-SIZE
        LIB-METADATA-FACT-ORIGIN _LM12-fact!
    _LM12-origin-b LIB-ORIGIN-SIZE
        LIB-METADATA-FACT-ORIGIN _LM12-fact!
    _LM12-invalid-facts - _LM12-TWO-ORIGINS-U = _LM12-assert
    _LM12-invalid-facts _LM12-TWO-ORIGINS-U
        _LM12-scratch-summary
        LIB-METADATA-SUMMARIZE LIB-S-INVALID _LM12-status
    _LM12-scratch-summary LIBMS.ORIGIN-N @ 1 = _LM12-assert
    _LM12-scratch-summary LIBMS.TAG-N @ 0= _LM12-assert
    _LM12-scratch-summary LIBMS.LINEAGE-N @ 0= _LM12-assert
    _LM12-stack ;

: _LM12-invalid-lineages  ( -- )
    _LM12-lineage _LM12-invalid-lineage LIB-LINEAGE-SIZE MOVE
    99 _LM12-invalid-lineage LIBLN.RELATION !
    _LM12-invalid-facts _LM12-LINEAGE-FACT-U 0 FILL
    _LM12-invalid-facts
    _LM12-invalid-lineage LIB-LINEAGE-SIZE
        LIB-METADATA-FACT-LINEAGE _LM12-fact! DROP
    _LM12-invalid-facts _LM12-LINEAGE-FACT-U
        _LM12-scratch-summary
        LIB-METADATA-SUMMARIZE LIB-S-INVALID _LM12-status
    _LM12-scratch-summary LIBMS.LINEAGE-N @ 0= _LM12-assert

    _LM12-lineage _LM12-invalid-lineage LIB-LINEAGE-SIZE MOVE
    0 _LM12-invalid-lineage LIBLN.LOCATOR QLOC.DOMAIN-REVISION !
    _LM12-invalid-lineage LIBLN.LOCATOR QLOC-VALID? 0= _LM12-assert
    _LM12-invalid-facts
    _LM12-invalid-lineage LIB-LINEAGE-SIZE
        LIB-METADATA-FACT-LINEAGE _LM12-fact! DROP
    _LM12-invalid-facts _LM12-LINEAGE-FACT-U
        _LM12-scratch-summary
        LIB-METADATA-SUMMARIZE LIB-S-INVALID _LM12-status
    _LM12-scratch-summary LIBMS.LINEAGE-N @ 0= _LM12-assert
    _LM12-stack ;

: _LM12-tag-ordering  ( -- )
    _LM12-invalid-facts _LM12-TWO-TAGS-U 0 FILL
    _LM12-invalid-facts
    S" beta" LIB-METADATA-FACT-TAG _LM12-fact!
    S" alpha" LIB-METADATA-FACT-TAG _LM12-fact! DROP
    _LM12-invalid-facts _LM12-TWO-TAGS-U
        _LM12-scratch-summary
        LIB-METADATA-SUMMARIZE LIB-S-INVALID _LM12-status
    _LM12-scratch-summary LIBMS.TAG-N @ 1 = _LM12-assert

    _LM12-invalid-facts _LM12-TWO-ALPHAS-U 0 FILL
    _LM12-invalid-facts
    S" alpha" LIB-METADATA-FACT-TAG _LM12-fact!
    S" alpha" LIB-METADATA-FACT-TAG _LM12-fact! DROP
    _LM12-invalid-facts _LM12-TWO-ALPHAS-U
        _LM12-scratch-summary
        LIB-METADATA-SUMMARIZE LIB-S-INVALID _LM12-status
    _LM12-scratch-summary LIBMS.TAG-N @ 1 = _LM12-assert
    _LM12-stack ;

: _LM12-rejected-apply  ( -- )
    \ A malformed summary may not disturb any unrelated destination bytes.
    \ Its projected metadata fields return to their canonical empty state.
    _LM12-entry LIB-ENTRY-INIT
    _LM12-entry LIBE.ID RID-CLEAR
    0xA1 _LM12-entry LIBE.ID !
    LIB-KIND-CAPTURE _LM12-entry LIBE.KIND !
    S" unchanged"
    DUP _LM12-entry LIBE.TITLE-U !
    _LM12-entry LIBE.TITLE SWAP MOVE
    0x5A _LM12-entry LIBE.FLAGS !
    _LM12-entry _LM12-entry-before LIB-ENTRY-SIZE MOVE

    _LM12-summary _LM12-invalid-summary
        LIB-METADATA-SUMMARY-SIZE MOVE
    2 _LM12-invalid-summary LIBMS.ORIGIN-N !
    _LM12-invalid-summary _LM12-entry
        LIB-METADATA-SUMMARY-APPLY LIB-S-INVALID _LM12-status
    _LM12-entry LIB-ENTRY-SIZE
        _LM12-entry-before LIB-ENTRY-SIZE
        COMPARE 0= _LM12-assert
    _LM12-entry LIBE.METADATA-U @ 0= _LM12-assert
    _LM12-entry LIBE.TAG-N @ 0= _LM12-assert
    _LM12-entry LIBE.ORIGIN-N @ 0= _LM12-assert
    _LM12-entry LIBE.LINEAGE-N @ 0= _LM12-assert
    _LM12-entry LIBE.METADATA-DIGEST
        LIB-DIGEST-SIZE _LM12-zero? _LM12-assert
    _LM12-stack ;

: _LM12-RUN  ( -- )
    0 _LM12-checks !
    0 _LM12-fails !
    DEPTH _LM12-depth !
    _LM12-origin!
    _LM12-lineage!
    _LM12-facts!
    _LM12-empty
    _LM12-canonical
    _LM12-truncation
    _LM12-duplicate-origin
    _LM12-invalid-lineages
    _LM12-tag-ordering
    _LM12-rejected-apply
    _LM12-stack
    _LM12-fails @ IF
        ." LIBRARY METADATA L12 FAIL " _LM12-fails @ .
        ." /" _LM12-checks @ . CR
    ELSE
        ." LIBRARY METADATA L12 PASS " _LM12-checks @ . CR
    THEN ;
