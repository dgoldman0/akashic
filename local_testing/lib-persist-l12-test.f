\ Successor contracts for the one-current-layout L12 Library owner adapter.

PROVIDED akashic-library-persistence-l12-contracts

VARIABLE _L12P-checks
VARIABLE _L12P-fails
VARIABLE _L12P-depth
VARIABLE _L12P-arena
VARIABLE _L12P-vfs
VARIABLE _L12P-ior
VARIABLE _L12P-si-store
VARIABLE _L12P-si-pwork
VARIABLE _L12P-si-buffer
VARIABLE _L12P-si-guard

CREATE _L12P-ops VFS-OPS-SIZE ALLOT
CREATE _L12P-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _L12P-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _L12P-bootstrap RID-SIZE ALLOT
CREATE _L12P-bootstrap-other RID-SIZE ALLOT
CREATE _L12P-bootstrap-out RID-SIZE ALLOT
CREATE _L12P-store PSTORE-SIZE ALLOT
CREATE _L12P-store-cold PSTORE-SIZE ALLOT
CREATE _L12P-pwork PSTORE-WORK-SIZE ALLOT
CREATE _L12P-pwork-cold PSTORE-WORK-SIZE ALLOT
LIBPA-RECORD-MAX PERSIST-RECORD-HEADER-SIZE + CONSTANT _L12P-buffer-u
_L12P-buffer-u XBUF _L12P-buffer
_L12P-buffer-u XBUF _L12P-buffer-cold
CREATE _L12P-adapter LIBPA-SIZE ALLOT
CREATE _L12P-adapter-cold LIBPA-SIZE ALLOT
LIBPA-INDEX-WORK-SIZE XBUF _L12P-work
LIBPA-INDEX-WORK-SIZE XBUF _L12P-work-cold
GUARD _L12P-guard
GUARD _L12P-guard-cold

CREATE _L12P-collection LIB-COLLECTION-SIZE ALLOT
CREATE _L12P-collection-out LIB-COLLECTION-SIZE ALLOT
CREATE _L12P-collection-record LIBPA-COLLECTION-RECORD-SIZE ALLOT
CREATE _L12P-entry LIB-ENTRY-SIZE ALLOT
CREATE _L12P-entry-out LIB-ENTRY-SIZE ALLOT
CREATE _L12P-entry-cold LIB-ENTRY-SIZE ALLOT
CREATE _L12P-entry-next LIB-ENTRY-SIZE ALLOT
CREATE _L12P-content LIB-CONTENT-SIZE ALLOT
CREATE _L12P-content-next LIB-CONTENT-SIZE ALLOT
CREATE _L12P-source 96 ALLOT
CREATE _L12P-history LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _L12P-current LIBPA-CONTENT-DESCRIPTOR-SIZE ALLOT
CREATE _L12P-range-rows LIBPA-RANGE-ROW-SIZE 2 * ALLOT
CREATE _L12P-range-snapshot LIBPA-RANGE-ROW-SIZE ALLOT
CREATE _L12P-continuation LIBPA-CONTINUATION-SIZE ALLOT
CREATE _L12P-continuation-seeded LIBPA-CONTINUATION-SIZE ALLOT
CREATE _L12P-continuation-snapshot LIBPA-CONTINUATION-SIZE ALLOT
CREATE _L12P-continuation-empty LIBPA-CONTINUATION-SIZE ALLOT
CREATE _L12P-state-prefix 3 ALLOT
LIB-METADATA-FACT-HEADER-SIZE 3 + CONSTANT _L12P-facts-u
CREATE _L12P-facts _L12P-facts-u ALLOT
CREATE _L12P-metadata-summary LIB-METADATA-SUMMARY-SIZE ALLOT

: _L12P-assert  ( flag -- )
    1 _L12P-checks +!
    0= IF
        1 _L12P-fails +!
        ." LIBRARY PERSISTENCE L12 ASSERT " _L12P-checks @ . CR
    THEN ;

: _L12P-stack  ( -- )
    DEPTH _L12P-depth @ = _L12P-assert ;

: _L12P-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY PERSISTENCE L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _L12P-assert _L12P-stack ;

: _L12P-bytes=  ( a b u -- flag )
    DUP 0< IF DROP 2DROP 0 EXIT THEN
    0 ?DO
        2DUP I + C@ SWAP I + C@ <> IF
            2DROP 0 UNLOOP EXIT
        THEN
    LOOP
    2DROP -1 ;

: _L12P-text!  ( source-a source-u destination length-cell -- )
    >R
    OVER R@ !
    SWAP MOVE
    R> DROP ;

: _L12P-document!  ( -- )
    _L12P-source 96 0 FILL
    S" abcdefghijklmnopqrstuvwxyz0123456789ABCD"
        _L12P-source SWAP MOVE
    _L12P-content LIB-CONTENT-INIT
    _L12P-content LIBCT.ID RID-CLEAR
    0x41 _L12P-content LIBCT.ID !
    1 _L12P-content LIBCT.DOMAIN-REVISION !
    1 _L12P-content LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12P-content LIBCT.KIND !
    LIB-MEDIA-TEXT-PLAIN _L12P-content LIBCT.MEDIA !
    _L12P-source _L12P-content LIBCT.DATA-A !
    40 _L12P-content LIBCT.DATA-U !
    _L12P-content LIB-CONTENT-DIGEST! LIB-S-OK _L12P-status

    _L12P-entry LIB-ENTRY-INIT
    _L12P-entry LIBE.ID RID-CLEAR
    0x41 _L12P-entry LIBE.ID !
    1 _L12P-entry LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _L12P-entry LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _L12P-entry LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _L12P-entry LIBE.MEDIA !
    1 _L12P-entry LIBE.CURRENT-CONTENT-REVISION !
    1 _L12P-entry LIBE.OLDEST-CONTENT-REVISION !
    40 _L12P-entry LIBE.CONTENT-U !
    _L12P-content LIBCT.DIGEST _L12P-entry LIBE.CONTENT-DIGEST RID-COPY
    1 _L12P-entry LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12P-entry LIBE.CREATED-CLOCK !
    1 _L12P-entry LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _L12P-entry LIBE.MODIFIED-CLOCK !
    1 _L12P-entry LIBE.MODIFIED-VALUE !
    S" First note"
        _L12P-entry LIBE.TITLE _L12P-entry LIBE.TITLE-U _L12P-text!
    _L12P-facts _L12P-facts-u 0 FILL
    LIB-METADATA-FACT-TAG _L12P-facts LIBMF.KIND !
    3 _L12P-facts LIBMF.PAYLOAD-U !
    S" tag" _L12P-facts LIBMF.PAYLOAD SWAP MOVE
    _L12P-facts _L12P-facts-u _L12P-metadata-summary
        LIB-METADATA-SUMMARIZE LIB-S-OK _L12P-status
    _L12P-entry LIBE.RECEIPT DUP LIB-RECEIPT-INIT
    DUP LIBR.OPERATION-KEY RID-CLEAR
    0x51 OVER LIBR.OPERATION-KEY !
    LIB-IMPORT-CREATED OVER LIBR.METHOD !
    1 OVER LIBR.INITIAL-CONTENT-REVISION !
    40 OVER LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN OVER LIBR.INITIAL-MEDIA !
    _L12P-entry LIBE.CONTENT-DIGEST
        OVER LIBR.INITIAL-CONTENT-DIGEST RID-COPY
    DROP
    _L12P-metadata-summary _L12P-entry
        LIB-METADATA-SUMMARY-APPLY LIB-S-OK _L12P-status
    _L12P-entry LIB-ENTRY-REQUEST-SEAL! LIB-S-OK _L12P-status
    _L12P-entry LIB-ENTRY-VALID? _L12P-assert
    _L12P-content LIB-CONTENT-VALID? _L12P-assert ;

: _L12P-metadata-next!  ( -- )
    _L12P-entry-out _L12P-entry-next LIB-ENTRY-SIZE MOVE
    2 _L12P-entry-next LIBE.DOMAIN-REVISION !
    2 _L12P-entry-next LIBE.MUTATION-SEQUENCE !
    2 _L12P-entry-next LIBE.MODIFIED-VALUE !
    _L12P-entry-next LIBE.TITLE LIB-TITLE-MAX 0 FILL
    S" Beta" DUP _L12P-entry-next LIBE.TITLE-U !
    _L12P-entry-next LIBE.TITLE SWAP MOVE
    _L12P-entry-next LIB-ENTRY-VALID? _L12P-assert ;

: _L12P-content-next!  ( -- )
    _L12P-source 96 0 FILL
    S" xyzzy" _L12P-source SWAP MOVE
    _L12P-content-next LIB-CONTENT-INIT
    _L12P-entry-out LIBE.ID _L12P-content-next LIBCT.ID RID-COPY
    3 _L12P-content-next LIBCT.DOMAIN-REVISION !
    2 _L12P-content-next LIBCT.CONTENT-REVISION !
    _L12P-entry-out LIBE.KIND @ _L12P-content-next LIBCT.KIND !
    _L12P-entry-out LIBE.MEDIA @ _L12P-content-next LIBCT.MEDIA !
    _L12P-source _L12P-content-next LIBCT.DATA-A !
    5 _L12P-content-next LIBCT.DATA-U !
    _L12P-content-next LIB-CONTENT-DIGEST!
        LIB-S-OK _L12P-status
    _L12P-entry-out _L12P-entry-next LIB-ENTRY-SIZE MOVE
    3 _L12P-entry-next LIBE.DOMAIN-REVISION !
    2 _L12P-entry-next LIBE.CURRENT-CONTENT-REVISION !
    1 _L12P-entry-next LIBE.OLDEST-CONTENT-REVISION !
    5 _L12P-entry-next LIBE.CONTENT-U !
    _L12P-content-next LIBCT.DIGEST
        _L12P-entry-next LIBE.CONTENT-DIGEST RID-COPY
    3 _L12P-entry-next LIBE.MUTATION-SEQUENCE !
    3 _L12P-entry-next LIBE.MODIFIED-VALUE !
    _L12P-content-next LIB-CONTENT-VALID? _L12P-assert
    _L12P-entry-next LIB-ENTRY-VALID? _L12P-assert ;

: _L12P-store-init  ( store pwork buffer guard -- )
    _L12P-si-guard !
    _L12P-si-buffer !
    _L12P-si-pwork !
    _L12P-si-store !
    S" /l12-pages" S" /l12-segment" S" /l12-root-a" S" /l12-root-b"
    _L12P-identity LIBPA-RECORD-MAX _L12P-vfs @ 0 0
    _L12P-si-guard @ 0 0 _L12P-si-store @
        PSTORE-INIT PERSIST-S-OK _L12P-status
    _L12P-si-buffer @ _L12P-buffer-u _L12P-si-pwork @
        PSTORE-WORK-INIT PERSIST-S-OK _L12P-status ;

: _L12P-setup  ( -- )
    VFS-RAM-OPS _L12P-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _L12P-binding VFS-BINDING-DESC-SIZE MOVE
    _L12P-ops _L12P-binding VB.OPS !
    16777216 A-XMEM ARENA-NEW DUP 0= _L12P-assert DROP _L12P-arena !
    _L12P-arena @ _L12P-binding 0 VFS-NEW _L12P-ior ! _L12P-vfs !
    _L12P-ior @ 0= _L12P-assert
    _L12P-vfs @ 0<> _L12P-assert
    _L12P-identity PERSIST-IDENTITY-SIZE 0x71 FILL
    _L12P-bootstrap RID-SIZE 0xA1 FILL
    _L12P-bootstrap-other RID-SIZE 0xA2 FILL

    _L12P-store _L12P-pwork _L12P-buffer _L12P-guard _L12P-store-init
    _L12P-store _L12P-adapter LIBPA-INIT LIBPA-S-OK _L12P-status
    _L12P-pwork _L12P-adapter _L12P-work
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12P-status
    _L12P-store _L12P-pwork PSTORE-PROVISION
        PERSIST-S-OK _L12P-status
    _L12P-adapter _L12P-work LIBPA-INDEX-OPEN
        LIBPA-S-ABSENT _L12P-status ;

: _L12P-bootstrap-contracts  ( -- )
    _L12P-bootstrap-out RID-SIZE 0xCC FILL
    _L12P-bootstrap-out _L12P-work LIBPA-INDEX-BOOTSTRAP-ID@
        LIBPA-S-ABSENT _L12P-status
    _L12P-bootstrap _L12P-adapter _L12P-work LIBPA-INDEX-PROVISION
        LIBPA-S-OK _L12P-status
    _L12P-store PSTORE-GENERATION@ 1 = _L12P-assert
    _L12P-work LIBPA-INDEX-LOGICAL-GENERATION@ 0 = _L12P-assert
    _L12P-bootstrap-out _L12P-work LIBPA-INDEX-BOOTSTRAP-ID@
        LIBPA-S-OK _L12P-status
    _L12P-bootstrap _L12P-bootstrap-out RID= _L12P-assert
    _L12P-bootstrap _L12P-adapter _L12P-work LIBPA-INDEX-PROVISION
        LIBPA-S-OK _L12P-status
    _L12P-store PSTORE-GENERATION@ 1 = _L12P-assert
    _L12P-bootstrap-other _L12P-adapter _L12P-work LIBPA-INDEX-PROVISION
        LIBPA-S-CONFLICT _L12P-status
    _L12P-store PSTORE-GENERATION@ 1 = _L12P-assert ;

: _L12P-document-create-contracts  ( -- )
    _L12P-document!
    _L12P-entry-out LIB-ENTRY-SIZE 0xA5 FILL
    _L12P-entry _L12P-content _L12P-facts _L12P-facts-u
        0 _L12P-entry-out
        _L12P-adapter _L12P-work LIBPA-DOCUMENT-CREATE-EXACT
        LIBPA-S-OK _L12P-status
    _L12P-entry _L12P-entry-out LIB-ENTRY-SIZE _L12P-bytes= _L12P-assert
    _L12P-work LIBPA-INDEX-LOGICAL-GENERATION@ 1 = _L12P-assert
    _L12P-work LIBPA-INDEX-DOCUMENT-COUNT@ 1 = _L12P-assert
    _L12P-work LIBPA-INDEX-MUTATION-SEQUENCE@ 1 = _L12P-assert
    _L12P-store PSTORE-GENERATION@ 2 > _L12P-assert
    _L12P-store PSTORE-GENERATION@ >R
    _L12P-entry-out LIB-ENTRY-SIZE 0xA5 FILL
    \ Idempotency resolves before the now-stale expected generation.
    _L12P-entry _L12P-content _L12P-facts _L12P-facts-u
        0 _L12P-entry-out
        _L12P-adapter _L12P-work LIBPA-DOCUMENT-CREATE-EXACT
        LIBPA-S-OK _L12P-status
    _L12P-store PSTORE-GENERATION@ R> = _L12P-assert
    _L12P-entry _L12P-entry-out LIB-ENTRY-SIZE _L12P-bytes= _L12P-assert
    _L12P-entry LIBE.ID _L12P-entry-cold
        _L12P-adapter _L12P-work LIBPA-INDEX-RID-LOOKUP
        LIBPA-S-OK _L12P-status
    _L12P-entry _L12P-entry-cold LIB-ENTRY-SIZE _L12P-bytes= _L12P-assert
    _L12P-entry LIBE.ID 1 _L12P-history
        _L12P-adapter _L12P-work LIBPA-INDEX-HISTORY
        LIBPA-S-OK _L12P-status
    _L12P-history LIBPA-CONTENT-DOMAIN-REVISION@ 1 = _L12P-assert
    _L12P-history LIBPA-CONTENT-SIZE@ 40 = _L12P-assert ;

: _L12P-document-read-and-metadata-contracts  ( -- )
    _L12P-entry LIBE.ID _L12P-entry-cold _L12P-current
        _L12P-adapter _L12P-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _L12P-status
    _L12P-entry-out _L12P-entry-cold LIB-ENTRY-SIZE
        _L12P-bytes= _L12P-assert
    _L12P-current LIBPA-CONTENT-DOMAIN-REVISION@ 1 = _L12P-assert
    _L12P-metadata-next!
    _L12P-entry-out _L12P-entry-next
        _LIBPIX-DOCUMENT-TRANSITION? _L12P-assert
    _L12P-entry-next _L12P-current
        _LIBPIX-DESCRIPTOR-AGREES? _L12P-assert
    _L12P-entry-next 0 -1 1 1 _L12P-entry-out
        _L12P-adapter _L12P-work
        LIBPA-DOCUMENT-METADATA-REPLACE-EXACT
        LIBPA-S-OK _L12P-status
    _L12P-entry-next _L12P-entry-out LIB-ENTRY-SIZE
        _L12P-bytes= _L12P-assert
    _L12P-work LIBPA-INDEX-LOGICAL-GENERATION@ 2 = _L12P-assert
    _L12P-entry LIBE.ID _L12P-entry-cold _L12P-current
        _L12P-adapter _L12P-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _L12P-status
    _L12P-entry-next _L12P-entry-cold LIB-ENTRY-SIZE
        _L12P-bytes= _L12P-assert
    _L12P-current LIBPA-CONTENT-DOMAIN-REVISION@ 1 = _L12P-assert
    _L12P-entry LIBE.ID 2 _L12P-history
        _L12P-adapter _L12P-work LIBPA-HISTORY-READ
        LIBPA-S-NOT-FOUND _L12P-status ;

: _L12P-document-content-replace-contracts  ( -- )
    _L12P-content-next!
    _L12P-entry-next _L12P-content-next 2 2 _L12P-entry-out
        _L12P-adapter _L12P-work
        LIBPA-DOCUMENT-CONTENT-REPLACE-EXACT
        LIBPA-S-OK _L12P-status
    _L12P-entry-next _L12P-entry-out LIB-ENTRY-SIZE
        _L12P-bytes= _L12P-assert
    _L12P-work LIBPA-INDEX-LOGICAL-GENERATION@ 3 = _L12P-assert
    _L12P-entry LIBE.ID _L12P-entry-cold _L12P-current
        _L12P-adapter _L12P-work LIBPA-DOCUMENT-READ
        LIBPA-S-OK _L12P-status
    _L12P-entry-next _L12P-entry-cold LIB-ENTRY-SIZE
        _L12P-bytes= _L12P-assert
    _L12P-current LIBPA-CONTENT-DOMAIN-REVISION@ 3 = _L12P-assert
    _L12P-current LIBPA-CONTENT-REVISION@ 2 = _L12P-assert
    _L12P-current LIBPA-CONTENT-SIZE@ 5 = _L12P-assert
    _L12P-entry LIBE.ID 1 _L12P-history
        _L12P-adapter _L12P-work LIBPA-HISTORY-READ
        LIBPA-S-OK _L12P-status
    _L12P-entry LIBE.ID 2 _L12P-history
        _L12P-adapter _L12P-work LIBPA-HISTORY-READ
        LIBPA-S-NOT-FOUND _L12P-status
    _L12P-entry LIBE.ID 3 _L12P-history
        _L12P-adapter _L12P-work LIBPA-HISTORY-READ
        LIBPA-S-OK _L12P-status
    _L12P-store PSTORE-GENERATION@ >R
    _L12P-entry-next _L12P-content-next 2 2 _L12P-entry-out
        _L12P-adapter _L12P-work
        LIBPA-DOCUMENT-CONTENT-REPLACE-EXACT
        LIBPA-S-OK _L12P-status
    _L12P-store PSTORE-GENERATION@ R> = _L12P-assert ;

: _L12P-seed-contracts  ( -- )
    LIBPA-RANGE-DOCUMENT-CREATION 0 0
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert

    LIBPA-RANGE-DOCUMENT-RECENCY 0 0
    3 _L12P-entry LIBE.ID 3 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert

    LIB-LIFECYCLE-ACTIVE _L12P-state-prefix C!
    LIB-KIND-MANAGED-DOCUMENT _L12P-state-prefix 1+ C!
    LIB-MEDIA-TEXT-PLAIN _L12P-state-prefix 2 + C!
    LIBPA-RANGE-DOCUMENT-STATE-CREATION _L12P-state-prefix 3
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert
    LIBPA-RANGE-DOCUMENT-STATE-RECENCY _L12P-state-prefix 3
    3 _L12P-entry LIBE.ID 3 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert

    LIBPA-RANGE-EXACT-TAG S" tag"
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert
    LIBPA-RANGE-CANDIDATE S" abc"
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert

    LIBPA-RANGE-COLLECTION-ORDER 0 0
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert
    LIBPA-RANGE-MEMBERSHIP _L12P-entry LIBE.ID RID-SIZE
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert
    LIBPA-RANGE-HISTORY _L12P-entry LIBE.ID RID-SIZE
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    _L12P-continuation-seeded LIBPA-CONTINUATION-VALID? _L12P-assert

    _L12P-continuation-seeded LIBPA-CONTINUATION-SIZE 0x5A FILL
    _L12P-continuation-seeded _L12P-continuation-snapshot
        LIBPA-CONTINUATION-SIZE MOVE
    LIBPA-RANGE-DOCUMENT-TITLE S" F"
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-INVALID _L12P-status
    _L12P-continuation-seeded _L12P-continuation-snapshot
        LIBPA-CONTINUATION-SIZE _L12P-bytes= _L12P-assert
    LIBPA-RANGE-COLLECTION-TITLE S" A"
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-INVALID _L12P-status
    _L12P-continuation-seeded _L12P-continuation-snapshot
        LIBPA-CONTINUATION-SIZE _L12P-bytes= _L12P-assert ;

: _L12P-range-contracts  ( -- )
    LIBPA-RANGE-DOCUMENT-CREATION 0 0
    _L12P-range-rows 1 _L12P-continuation
    _L12P-adapter _L12P-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12P-assert
    1 = _L12P-assert
    _L12P-continuation LIBPA-CONTINUATION-VALID? _L12P-assert
    _L12P-continuation _LIBPACONT.PREFIX-SEAL SHA3-256-LEN
        _LIBPA-ZERO? _L12P-assert
    1 _L12P-continuation _LIBPACONT.PREFIX-SEAL C!
    _L12P-continuation LIBPA-CONTINUATION-VALID? 0= _L12P-assert
    0 _L12P-continuation _LIBPACONT.PREFIX-SEAL C!
    _L12P-continuation LIBPA-CONTINUATION-VALID? _L12P-assert
    _L12P-range-rows LIBPA-RANGE-ROW-RID@
    _L12P-entry LIBE.ID RID= _L12P-assert
    _L12P-range-rows LIBPA-RANGE-ROW-ORDER@ 1 = _L12P-assert
    _L12P-continuation LIBPA-CONTINUATION-LOGICAL-GENERATION@
        3 = _L12P-assert
    LIBPA-RANGE-DOCUMENT-CREATION 0 0
    _L12P-range-rows 1 _L12P-continuation
    _L12P-adapter _L12P-work LIBPA-RANGE-AFTER
    LIBPA-S-OK = _L12P-assert
    0= _L12P-assert

    \ A mismatched resume fails without touching either caller output.
    _L12P-range-rows LIBPA-RANGE-ROW-SIZE 0xD3 FILL
    _L12P-range-rows _L12P-range-snapshot
        LIBPA-RANGE-ROW-SIZE MOVE
    _L12P-continuation _L12P-continuation-snapshot
        LIBPA-CONTINUATION-SIZE MOVE
    LIBPA-RANGE-DOCUMENT-RECENCY 0 0
    _L12P-range-rows 1 _L12P-continuation
    _L12P-adapter _L12P-work LIBPA-RANGE-AFTER
    LIBPA-S-INVALID = _L12P-assert
    0= _L12P-assert
    _L12P-range-rows _L12P-range-snapshot
        LIBPA-RANGE-ROW-SIZE _L12P-bytes= _L12P-assert
    _L12P-continuation _L12P-continuation-snapshot
        LIBPA-CONTINUATION-SIZE _L12P-bytes= _L12P-assert

    \ An empty FIRST page is success, leaves row storage untouched, and
    \ returns the one canonical empty continuation representation.
    _L12P-range-rows LIBPA-RANGE-ROW-SIZE 0xA5 FILL
    _L12P-range-rows _L12P-range-snapshot
        LIBPA-RANGE-ROW-SIZE MOVE
    _L12P-continuation-empty LIBPA-CONTINUATION-SIZE 0xCC FILL
    LIBPA-RANGE-COLLECTION-ORDER 0 0
    _L12P-range-rows 1 _L12P-continuation-empty
    _L12P-adapter _L12P-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12P-assert
    0= _L12P-assert
    _L12P-range-rows _L12P-range-snapshot
        LIBPA-RANGE-ROW-SIZE _L12P-bytes= _L12P-assert
    _L12P-continuation-empty LIBPA-CONTINUATION-VALID? _L12P-assert
    _L12P-continuation-empty LIBPA-CONTINUATION-FAMILY@
        LIBPA-RANGE-COLLECTION-ORDER = _L12P-assert
    _L12P-continuation-empty LIBPA-CONTINUATION-DIRECTION@
        LIBPA-CONTINUATION-SEEDED = _L12P-assert
    _L12P-continuation-empty _LIBPACONT.FIRST-U @ 0= _L12P-assert
    _L12P-continuation-empty _LIBPACONT.LAST-U @ 0= _L12P-assert
    _L12P-continuation-empty _LIBPACONT.PREFIX-SEAL SHA3-256-LEN
        _LIBPA-ZERO? _L12P-assert

    _L12P-seed-contracts
    LIBPA-RANGE-DOCUMENT-CREATION 0 0
    1 _L12P-entry LIBE.ID 1 _L12P-entry LIBE.ID
    _L12P-continuation-seeded LIBPA-CONTINUATION-SEED
    LIBPA-S-OK _L12P-status
    LIBPA-RANGE-DOCUMENT-CREATION 0 0
    _L12P-range-rows 1 _L12P-continuation-seeded
    _L12P-adapter _L12P-work LIBPA-RANGE-BEFORE
    LIBPA-S-OK = _L12P-assert
    0= _L12P-assert

    LIB-LIFECYCLE-ACTIVE _L12P-state-prefix C!
    LIB-KIND-MANAGED-DOCUMENT _L12P-state-prefix 1+ C!
    LIB-MEDIA-TEXT-PLAIN _L12P-state-prefix 2 + C!
    LIBPA-RANGE-DOCUMENT-STATE-RECENCY _L12P-state-prefix 3
    _L12P-range-rows 1 _L12P-continuation
    _L12P-adapter _L12P-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12P-assert
    1 = _L12P-assert
    _L12P-range-rows LIBPA-RANGE-ROW-ORDER@ 3 = _L12P-assert

    LIBPA-RANGE-HISTORY _L12P-entry LIBE.ID RID-SIZE
    _L12P-range-rows 1 _L12P-continuation
    _L12P-adapter _L12P-work LIBPA-RANGE-FIRST
    LIBPA-S-OK = _L12P-assert
    1 = _L12P-assert
    _L12P-range-rows LIBPA-RANGE-ROW-DOMAIN@ 1 = _L12P-assert
    LIBPA-RANGE-HISTORY _L12P-entry LIBE.ID RID-SIZE
    _L12P-range-rows 1 _L12P-continuation
    _L12P-adapter _L12P-work LIBPA-RANGE-AFTER
    LIBPA-S-OK = _L12P-assert
    1 = _L12P-assert
    _L12P-range-rows LIBPA-RANGE-ROW-DOMAIN@ 3 = _L12P-assert
    LIBPA-RANGE-HISTORY _L12P-entry LIBE.ID RID-SIZE
    _L12P-range-rows 1 _L12P-continuation
    _L12P-adapter _L12P-work LIBPA-RANGE-BEFORE
    LIBPA-S-OK = _L12P-assert
    1 = _L12P-assert
    _L12P-range-rows LIBPA-RANGE-ROW-DOMAIN@ 1 = _L12P-assert ;

: _L12P-cold-contracts  ( -- )
    _L12P-store-cold _L12P-pwork-cold _L12P-buffer-cold _L12P-guard-cold
        _L12P-store-init
    _L12P-store-cold _L12P-adapter-cold LIBPA-INIT
        LIBPA-S-OK _L12P-status
    _L12P-pwork-cold _L12P-adapter-cold _L12P-work-cold
        LIBPA-INDEX-WORK-INIT LIBPA-S-OK _L12P-status
    _L12P-store-cold _L12P-pwork-cold PSTORE-PROVISION
        PERSIST-S-OK _L12P-status
    _L12P-adapter-cold _L12P-work-cold LIBPA-INDEX-OPEN
        LIBPA-S-OK _L12P-status
    _L12P-work-cold LIBPA-INDEX-LOGICAL-GENERATION@ 3 = _L12P-assert
    _L12P-bootstrap-out _L12P-work-cold LIBPA-INDEX-BOOTSTRAP-ID@
        LIBPA-S-OK _L12P-status
    _L12P-bootstrap _L12P-bootstrap-out RID= _L12P-assert
    _L12P-entry LIBE.ID _L12P-entry-cold
        _L12P-adapter-cold _L12P-work-cold LIBPA-INDEX-RID-LOOKUP
        LIBPA-S-OK _L12P-status
    _L12P-entry-next _L12P-entry-cold LIB-ENTRY-SIZE
        _L12P-bytes= _L12P-assert ;

: _L12P-collection-record-contracts  ( -- )
    _L12P-collection LIB-COLLECTION-INIT
    _L12P-collection LIBC.ID RID-CLEAR
    0x11 _L12P-collection LIBC.ID !
    _L12P-collection LIBC.OPERATION-KEY RID-CLEAR
    0x22 _L12P-collection LIBC.OPERATION-KEY !
    1 _L12P-collection LIBC.REVISION !
    7 _L12P-collection LIBC.MUTATION-SEQUENCE !
    3 _L12P-collection LIBC.CREATED-SEQUENCE !
    0 _L12P-collection LIBC.MEMBER-N !
    S" Alpha" DUP _L12P-collection LIBC.TITLE-U !
    _L12P-collection LIBC.TITLE SWAP MOVE
    _L12P-collection LIBC.REQUEST-SEAL RID-CLEAR
    0x33 _L12P-collection LIBC.REQUEST-SEAL !
    _L12P-collection LIB-COLLECTION-VALID? _L12P-assert
    _L12P-collection _L12P-collection-record
        LIBPA-COLLECTION-RECORD-ENCODE LIBPA-S-OK _L12P-status
    _L12P-collection-record LIBPA-COLLECTION-RECORD-SIZE
        LIBPA-COLLECTION-RECORD-VALID? _L12P-assert
    _L12P-collection-record LIBPA-COLLECTION-RECORD-SIZE
        _L12P-collection-out LIBPA-COLLECTION-RECORD-DECODE
        LIBPA-S-OK _L12P-status
    _L12P-collection _L12P-collection-out LIB-COLLECTION-SIZE
        _L12P-bytes= _L12P-assert ;

: _L12P-RUN  ( -- )
    0 _L12P-checks !
    0 _L12P-fails !
    DEPTH _L12P-depth !
    PBLOB-WORK-SIZE 46960 = _L12P-assert
    LIBPA-INDEX-WORK-SIZE 119840 = _L12P-assert
    _L12P-setup
    _L12P-bootstrap-contracts
    _L12P-document-create-contracts
    _L12P-document-read-and-metadata-contracts
    _L12P-document-content-replace-contracts
    _L12P-range-contracts
    _L12P-cold-contracts
    _L12P-collection-record-contracts
    _L12P-stack
    _L12P-fails @ IF
        ." LIBRARY PERSISTENCE L12 FAIL " _L12P-fails @ .
        ." /" _L12P-checks @ . CR
    ELSE
        ." LIBRARY PERSISTENCE L12 PASS " _L12P-checks @ . CR
    THEN ;
