\ =====================================================================
\  Gate 4 milestone 1: managed-create capacity and allocation limits
\ =====================================================================
\  The snapshots below are synthesized only to put CREATE-MANAGED at
\  otherwise unreachable hard limits.  Every snapshot is committed by a
\  real head, then fully loaded through a freshly initialized descriptor
\  before the public API is invoked.  The separate two-process acceptance
\  driver supplies the contract-grade cold-relaunch proof.

VARIABLE _lmc-fails
VARIABLE _lmc-checks
VARIABLE _lmc-depth
VARIABLE _lmc-store-slot
VARIABLE _lmc-store-b-slot
VARIABLE _lmc-vfs
VARIABLE _lmc-replacement-vfs
VARIABLE _lmc-old-vfs
VARIABLE _lmc-arena
VARIABLE _lmc-fd
VARIABLE _lmc-io-a
VARIABLE _lmc-io-u
VARIABLE _lmc-io-off
VARIABLE _lmc-path-a
VARIABLE _lmc-path-u
VARIABLE _lmc-status
VARIABLE _lmc-length
VARIABLE _lmc-generation
VARIABLE _lmc-selector
VARIABLE _lmc-expected
VARIABLE _lmc-catalog-count
VARIABLE _lmc-mutation
VARIABLE _lmc-content-tail
VARIABLE _lmc-content-count
VARIABLE _lmc-collection-count
VARIABLE _lmc-record-u
VARIABLE _lmc-frame-u
VARIABLE _lmc-scale-slot
VARIABLE _lmc-query-status
VARIABLE _lmc-query-count
VARIABLE _lmc-query-next
VARIABLE _lmc-query-generation
VARIABLE _lmc-perf-cycles
VARIABLE _lmc-perf-stalls
VARIABLE _lmc-perf-extmem
VARIABLE _lmc-attempt
VARIABLE _lmc-entry-id
VARIABLE _lmc-entry-key
VARIABLE _lmc-entry-mutation
VARIABLE _lmc-request-key
VARIABLE _lmc-request-bytes
VARIABLE _lmc-request-u
VARIABLE _lmc-expected-status
VARIABLE _lmc-expected-rng
VARIABLE _lmc-write-calls
VARIABLE _lmc-checkpoint-calls
VARIABLE _lmc-random-calls

\ Fixed from the f782632 MP64FS baseline and the handoff's 5x/10% gates.
171490000 CONSTANT _LMC-COLD-32X4K-CYCLE-MAX
 33460000 CONSTANT _LMC-WARM-PAGE-CYCLE-MAX
 31360000 CONSTANT _LMC-WARM-MISS-CYCLE-MAX
172680000 CONSTANT _LMC-BODY-HIT-CYCLE-MAX
177280000 CONSTANT _LMC-SHORT-BODY-CYCLE-MAX

CREATE _lmc-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lmc-id LIB-DIGEST-SIZE ALLOT
CREATE _lmc-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmc-create-key LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmc-zero-entropy LIB-DIGEST-SIZE ALLOT
CREATE _lmc-attempt-cell 8 ALLOT
CREATE _lmc-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lmc-collection-request
    LIBRARY-COLLECTION-CREATE-REQUEST-SIZE ALLOT
CREATE _lmc-result LIB-ENTRY-SIZE ALLOT
CREATE _lmc-entry LIB-ENTRY-SIZE ALLOT
CREATE _lmc-collection LIB-COLLECTION-SIZE ALLOT
CREATE _lmc-content LIB-CONTENT-SIZE ALLOT
CREATE _lmc-query-request LIBRARY-CORPUS-QUERY-REQUEST-SIZE ALLOT
CREATE _lmc-bank-fact LIB-BANK-FACT-SIZE ALLOT
CREATE _lmc-head-fact LIB-HEAD-FACT-SIZE ALLOT
CREATE _lmc-bank-sha LIB-DIGEST-SIZE ALLOT
CREATE _lmc-frame-sha LIB-DIGEST-SIZE ALLOT
CREATE _lmc-chain LIB-DIGEST-SIZE ALLOT
CREATE _lmc-chain-next LIB-DIGEST-SIZE ALLOT
CREATE _lmc-scale-collection-id LIB-DIGEST-SIZE ALLOT
LIB-BANK-SIZE XBUF _lmc-bank
LIB-CONTENT-MAX XBUF _lmc-data
LIB-CONTENT-FRAME-MAX XBUF _lmc-frame
LIBRARY-QUERY-SUMMARY-SIZE LIBRARY-QUERY-PAGE-MAX * XBUF _lmc-query-page
LIBRARY-QUERY-SUMMARY-SIZE LIBRARY-QUERY-PAGE-MAX * XBUF _lmc-query-baseline
LIBRARY-COLLECTION-SUMMARY-SIZE XBUF _lmc-collection-page
LIBRARY-COLLECTION-VIEW-SIZE XBUF _lmc-collection-view

: _lmc-store  ( -- store ) _lmc-store-slot @ ;
: _lmc-store-b  ( -- store ) _lmc-store-b-slot @ ;

: _lmc-assert  ( flag -- )
    1 _lmc-checks +!
    0= IF
        1 _lmc-fails +!
        ." LIBRARY MANAGED CAPACITY ASSERT " _lmc-checks @ . CR
    THEN ;

: _lmc-stack  ( -- )
    DEPTH DUP _lmc-depth @ <> IF
        ." LIBRARY MANAGED CAPACITY STACK "
        _lmc-depth @ . ." -> " DUP . CR .S CR
    THEN
    _lmc-depth @ = _lmc-assert ;

: _lmc-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _lmc-id!  ( value id -- ) DUP RID-CLEAR ! ;

: _lmc-write-at  ( source length offset path-a path-u -- flag )
    _lmc-path-u ! _lmc-path-a ! _lmc-io-off !
    _lmc-io-u ! _lmc-io-a !
    _lmc-path-a @ _lmc-path-u @ VFS-OPEN
    DUP _lmc-fd ! 0= IF 0 EXIT THEN
    _lmc-io-off @ _lmc-fd @ VFS-SEEK
    _lmc-io-a @ _lmc-io-u @ _lmc-fd @ VFS-WRITE-EXACT 0=
    _lmc-fd @ VFS-CLOSE ;

: _lmc-forbid-write  ( source length fd -- ior )
    DROP 2DROP 1 _lmc-write-calls +! -1 ;

: _lmc-count-checkpoint  ( stage -- status )
    DROP 1 _lmc-checkpoint-calls +! LIBSTORE-S-OK ;

: _lmc-zero-random  ( -- value )
    1 _lmc-random-calls +! 0 ;

: _lmc-arm-observers  ( -- )
    0 _lmc-write-calls !
    0 _lmc-checkpoint-calls !
    0 _lmc-random-calls !
    ['] _lmc-forbid-write _LIBVFS-WRITE-EXACT-XT !
    ['] _lmc-count-checkpoint _LIBMU-CHECKPOINT-XT !
    ['] _lmc-zero-random _LIBMU-RANDOM-XT ! ;

: _lmc-disarm  ( -- )
    _LIBVFS-RESET-VFS-HOOKS
    _LIBVFS-RESET-MUTATION-HOOKS ;

: _lmc-request!  ( key expected bytes length -- )
    _lmc-request-u ! _lmc-request-bytes !
    _lmc-expected ! _lmc-request-key !
    _lmc-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    _lmc-expected @
        _lmc-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lmc-request-key @ _lmc-request
        LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lmc-assert
    S" capacity boundary" _lmc-request
        LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lmc-assert
    _lmc-request-bytes @ _lmc-request-u @ _lmc-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lmc-assert
    LIB-MEDIA-TEXT-PLAIN _lmc-request LIBMCR.MEDIA !
    _lmc-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lmc-assert ;

\ Start with a valid revision-one creation receipt, then irreversibly
\ redact the public entry into the canonical tombstone shape.
: _lmc-build-tombstone  ( id operation-key mutation -- )
    _lmc-entry-mutation ! _lmc-entry-key ! _lmc-entry-id !
    _lmc-entry LIB-ENTRY-INIT
    _lmc-entry-id @ _lmc-entry LIBE.ID RID-COPY
    1 _lmc-entry LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _lmc-entry LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _lmc-entry LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _lmc-entry LIBE.MEDIA !
    1 _lmc-entry LIBE.CURRENT-CONTENT-REVISION !
    1 _lmc-entry LIBE.OLDEST-CONTENT-REVISION !
    1 _lmc-entry LIBE.CONTENT-U !
    S" x" _lmc-entry LIBE.CONTENT-DIGEST SHA3-256-HASH
    _lmc-entry-mutation @ _lmc-entry LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _lmc-entry LIBE.CREATED-CLOCK !
    1 _lmc-entry LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _lmc-entry LIBE.MODIFIED-CLOCK !
    _lmc-entry-mutation @ _lmc-entry LIBE.MODIFIED-VALUE !
    4 _lmc-entry LIBE.TITLE-U !
    S" seed" DROP _lmc-entry LIBE.TITLE 4 CMOVE
    _lmc-entry-key @ _lmc-entry LIBE.RECEIPT LIBR.OPERATION-KEY RID-COPY
    LIB-IMPORT-CREATED _lmc-entry LIBE.RECEIPT LIBR.METHOD !
    1 _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-REVISION !
    1 _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN
        _lmc-entry LIBE.RECEIPT LIBR.INITIAL-MEDIA !
    S" x" _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-DIGEST
        SHA3-256-HASH
    1 _lmc-entry LIBE.RECEIPT
        LIBR.EXPECTED-CATALOG-GENERATION !
    _lmc-entry LIB-ENTRY-REQUEST-SEAL!
        LIB-S-OK = _lmc-assert
    2 _lmc-entry LIBE.DOMAIN-REVISION !
    LIB-LIFECYCLE-TOMBSTONED _lmc-entry LIBE.LIFECYCLE !
    LIB-MEDIA-NONE _lmc-entry LIBE.MEDIA !
    0 _lmc-entry LIBE.CURRENT-CONTENT-REVISION !
    0 _lmc-entry LIBE.OLDEST-CONTENT-REVISION !
    0 _lmc-entry LIBE.CONTENT-U !
    _lmc-entry LIBE.CONTENT-DIGEST LIB-DIGEST-SIZE 0 FILL
    0 _lmc-entry LIBE.CREATED-CLOCK !
    0 _lmc-entry LIBE.CREATED-VALUE !
    0 _lmc-entry LIBE.IMPORTED-CLOCK !
    0 _lmc-entry LIBE.IMPORTED-VALUE !
    0 _lmc-entry LIBE.MODIFIED-CLOCK !
    0 _lmc-entry LIBE.MODIFIED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _lmc-entry LIBE.DELETED-CLOCK !
    _lmc-entry-mutation @ _lmc-entry LIBE.DELETED-VALUE !
    0 _lmc-entry LIBE.TITLE-U !
    _lmc-entry LIBE.TITLE LIB-TITLE-MAX 0 FILL
    _lmc-entry LIB-ENTRY-VALID? _lmc-assert ;

: _lmc-encode-entry  ( slot -- )
    LIB-CATALOG-RECORD-SIZE * LIB-BANK-CATALOG-OFFSET +
    _lmc-bank +
    _lmc-entry SWAP LIB-CATALOG-RECORD-SIZE
        LIB-CATALOG-RECORD-ENCODE
    _lmc-status ! _lmc-length !
    _lmc-status @ LIB-S-OK = _lmc-assert
    _lmc-length @ LIB-CATALOG-RECORD-SIZE = _lmc-assert ;

: _lmc-encode-collection  ( slot -- )
    LIB-COLLECTION-RECORD-SIZE * LIB-BANK-COLLECTION-OFFSET +
    _lmc-bank +
    _lmc-collection SWAP LIB-COLLECTION-RECORD-SIZE
        LIB-COLLECTION-RECORD-ENCODE
    _lmc-status ! _lmc-length !
    _lmc-status @ LIB-S-OK = _lmc-assert
    _lmc-length @ LIB-COLLECTION-RECORD-SIZE = _lmc-assert ;

: _lmc-empty-content  ( -- )
    LIB-ARENA-HEADER-SIZE _lmc-content-tail !
    0 _lmc-content-count !
    _lmc-chain LIB-CONTENT-CHAIN-GENESIS
        LIB-S-OK = _lmc-assert ;

: _lmc-build-bank  ( generation catalog-count collection-count mutation -- )
    _lmc-mutation ! _lmc-collection-count !
    _lmc-catalog-count ! _lmc-generation !
    _lmc-bank-fact LIB-BANK-FACT-INIT
    _lmc-generation @ _lmc-bank-fact LIBBF.GENERATION !
    _lmc-catalog-count @ _lmc-bank-fact LIBBF.CATALOG-COUNT !
    _lmc-collection-count @ _lmc-bank-fact LIBBF.COLLECTION-COUNT !
    _lmc-mutation @ _lmc-bank-fact LIBBF.MUTATION-SEQUENCE !
    _lmc-arena-id _lmc-bank-fact LIBBF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    _lmc-content-tail @ _lmc-bank-fact LIBBF.CONTENT-TAIL !
    _lmc-content-count @ _lmc-bank-fact LIBBF.CONTENT-RECORD-COUNT !
    _lmc-chain _lmc-bank-fact LIBBF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE
    _lmc-bank LIB-BANK-HEADER-SIZE + LIB-BANK-BODY-SIZE CRC32
        0xFFFFFFFF AND _lmc-bank-fact LIBBF.BODY-CRC !
    _lmc-bank LIB-BANK-HEADER-SIZE + LIB-BANK-BODY-SIZE
        _lmc-bank-fact LIBBF.BODY-SHA SHA3-256-HASH
    _lmc-bank-fact _lmc-bank LIB-BANK-HEADER-SIZE
        LIB-BANK-HEADER-ENCODE
    _lmc-status ! _lmc-length !
    _lmc-status @ LIB-S-OK = _lmc-assert
    _lmc-length @ LIB-BANK-HEADER-SIZE = _lmc-assert
    _lmc-bank LIB-BANK-SIZE _lmc-bank-sha SHA3-256-HASH
    _lmc-bank-fact LIB-BANK-FACT-VALID? _lmc-assert ;

: _lmc-build-head  ( generation selector -- )
    _lmc-selector ! _lmc-generation !
    _lmc-head-fact LIB-HEAD-FACT-INIT
    _lmc-generation @ _lmc-head-fact LIBHF.GENERATION !
    _lmc-selector @ _lmc-head-fact LIBHF.BANK-SELECTOR !
    _lmc-bank-fact LIBBF.GENERATION @
        _lmc-head-fact LIBHF.BANK-GENERATION !
    _lmc-bank-fact LIBBF.CATALOG-COUNT @
        _lmc-head-fact LIBHF.CATALOG-COUNT !
    _lmc-bank-fact LIBBF.COLLECTION-COUNT @
        _lmc-head-fact LIBHF.COLLECTION-COUNT !
    _lmc-bank-fact LIBBF.MUTATION-SEQUENCE @
        _lmc-head-fact LIBHF.MUTATION-SEQUENCE !
    _lmc-bank-sha _lmc-head-fact LIBHF.BANK-SHA
        LIB-DIGEST-SIZE CMOVE
    _lmc-bank-fact LIBBF.ARENA-ID _lmc-head-fact LIBHF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    _lmc-bank-fact LIBBF.CONTENT-TAIL @
        _lmc-head-fact LIBHF.CONTENT-TAIL !
    _lmc-bank-fact LIBBF.CONTENT-RECORD-COUNT @
        _lmc-head-fact LIBHF.CONTENT-RECORD-COUNT !
    _lmc-bank-fact LIBBF.CONTENT-CHAIN _lmc-head-fact LIBHF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE
    _lmc-head-fact LIB-HEAD-FACT-VALID? _lmc-assert ;

: _lmc-reinit-load  ( -- )
    _lmc-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lmc-assert
    _lmc-vfs @ _lmc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lmc-assert ;

: _lmc-publish  ( generation selector expected -- )
    _lmc-expected ! _lmc-selector ! _lmc-generation !
    _lmc-selector @ IF
        _lmc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
    ELSE
        _lmc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-A-PATH$
    THEN
    _lmc-write-at _lmc-assert
    _lmc-vfs @ VFS-SYNC 0= _lmc-assert
    _lmc-generation @ _lmc-selector @ _lmc-build-head
    _lmc-head-fact _lmc-expected @ _lmc-store
        _LIBRARY-VFS-STORE-SAVE-HEAD
        LIBSTORE-S-OK = _lmc-assert
    _lmc-reinit-load
    _lmc-store LIBRARY-VFS-STORE.GENERATION @
        _lmc-generation @ = _lmc-assert ;

: _lmc-publish-through-second  ( generation selector expected -- )
    _lmc-expected ! _lmc-selector ! _lmc-generation !
    _lmc-selector @ IF
        _lmc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
    ELSE
        _lmc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-A-PATH$
    THEN
    _lmc-write-at _lmc-assert
    _lmc-vfs @ VFS-SYNC 0= _lmc-assert
    _lmc-generation @ _lmc-selector @ _lmc-build-head
    _lmc-head-fact _lmc-expected @ _lmc-store-b
        _LIBRARY-VFS-STORE-SAVE-HEAD
        LIBSTORE-S-OK = _lmc-assert ;

: _lmc-build-catalog-full  ( -- )
    _lmc-bank LIB-BANK-SIZE 0 FILL
    _lmc-empty-content
    LIB-CATALOG-MAX 0 DO
        I 1+ _lmc-id _lmc-id!
        I 1001 + _lmc-key _lmc-id!
        _lmc-id _lmc-key I 1+ _lmc-build-tombstone
        I _lmc-encode-entry
    LOOP
    2 LIB-CATALOG-MAX 0 LIB-CATALOG-MAX _lmc-build-bank ;

: _lmc-build-live-entry  ( -- )
    _lmc-entry LIB-ENTRY-INIT
    0x77 _lmc-entry LIBE.ID _lmc-id!
    1 _lmc-entry LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _lmc-entry LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _lmc-entry LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _lmc-entry LIBE.MEDIA !
    1 _lmc-entry LIBE.CURRENT-CONTENT-REVISION !
    1 _lmc-entry LIBE.OLDEST-CONTENT-REVISION !
    LIB-CONTENT-MAX _lmc-entry LIBE.CONTENT-U !
    _lmc-data LIB-CONTENT-MAX _lmc-entry LIBE.CONTENT-DIGEST
        SHA3-256-HASH
    1 _lmc-entry LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _lmc-entry LIBE.CREATED-CLOCK !
    1 _lmc-entry LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _lmc-entry LIBE.MODIFIED-CLOCK !
    1 _lmc-entry LIBE.MODIFIED-VALUE !
    9 _lmc-entry LIBE.TITLE-U !
    S" full seed" DROP _lmc-entry LIBE.TITLE 9 CMOVE
    1777 _lmc-entry LIBE.RECEIPT LIBR.OPERATION-KEY _lmc-id!
    LIB-IMPORT-CREATED _lmc-entry LIBE.RECEIPT LIBR.METHOD !
    1 _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-REVISION !
    LIB-CONTENT-MAX
        _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN
        _lmc-entry LIBE.RECEIPT LIBR.INITIAL-MEDIA !
    _lmc-data LIB-CONTENT-MAX
        _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-DIGEST
        SHA3-256-HASH
    1 _lmc-entry LIBE.RECEIPT
        LIBR.EXPECTED-CATALOG-GENERATION !
    _lmc-entry LIB-ENTRY-REQUEST-SEAL!
        LIB-S-OK = _lmc-assert
    9 _lmc-entry LIBE.DOMAIN-REVISION !
    9 _lmc-entry LIBE.CURRENT-CONTENT-REVISION !
    6 _lmc-entry LIBE.OLDEST-CONTENT-REVISION !
    9 _lmc-entry LIBE.MUTATION-SEQUENCE !
    9 _lmc-entry LIBE.MODIFIED-VALUE !
    _lmc-entry LIB-ENTRY-VALID? _lmc-assert ;

: _lmc-build-content-full  ( -- )
    _lmc-data LIB-CONTENT-MAX 0x78 FILL
    _lmc-bank LIB-BANK-SIZE 0 FILL
    _lmc-build-live-entry
    0 _lmc-encode-entry
    _lmc-chain LIB-CONTENT-CHAIN-GENESIS
        LIB-S-OK = _lmc-assert
    LIB-ARENA-HEADER-SIZE _lmc-content-tail !
    9 0 DO
        _lmc-content LIB-CONTENT-INIT
        0x77 _lmc-content LIBCT.ID _lmc-id!
        I 1+ _lmc-content LIBCT.DOMAIN-REVISION !
        I 1+ _lmc-content LIBCT.CONTENT-REVISION !
        LIB-KIND-MANAGED-DOCUMENT _lmc-content LIBCT.KIND !
        LIB-MEDIA-TEXT-PLAIN _lmc-content LIBCT.MEDIA !
        _lmc-data _lmc-content LIBCT.DATA-A !
        LIB-CONTENT-MAX _lmc-content LIBCT.DATA-U !
        _lmc-content LIB-CONTENT-DIGEST!
            LIB-S-OK = _lmc-assert
        _lmc-frame LIB-CONTENT-FRAME-MAX 0 FILL
        _lmc-content _lmc-frame LIB-CONTENT-FRAME-MAX
            LIB-CONTENT-RECORD-ENCODE
        _lmc-status ! _lmc-record-u !
        _lmc-status @ LIB-S-OK = _lmc-assert
        _lmc-record-u @ LIB-CONTENT-RECORD-MAX = _lmc-assert
        _lmc-record-u @ LIB-CONTENT-FRAME-SIZE _lmc-frame-u !
        _lmc-frame-u @ LIB-CONTENT-FRAME-MAX = _lmc-assert
        _lmc-frame _lmc-frame-u @ _lmc-content-tail @
            _LIBVFS-CONTENT-PATH$ _lmc-write-at _lmc-assert
        _lmc-frame _lmc-frame-u @ _lmc-frame-sha
            LIB-CONTENT-FRAME-DIGEST LIB-S-OK = _lmc-assert
        _lmc-chain _lmc-content-tail @ _lmc-frame-u @
            _lmc-frame-sha _lmc-chain-next
            LIB-CONTENT-CHAIN-STEP LIB-S-OK = _lmc-assert
        _lmc-chain-next _lmc-chain LIB-DIGEST-SIZE CMOVE
        _lmc-frame-u @ _lmc-content-tail +!
    LOOP
    9 _lmc-content-count !
    _lmc-content-tail @ LIB-ARENA-SIZE < _lmc-assert
    3 1 0 9 _lmc-build-bank ;

: _lmc-build-scale-entry  ( slot -- )
    _lmc-scale-slot !
    _lmc-entry LIB-ENTRY-INIT
    _lmc-scale-slot @ 0x100 + _lmc-entry LIBE.ID _lmc-id!
    1 _lmc-entry LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _lmc-entry LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _lmc-entry LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _lmc-entry LIBE.MEDIA !
    1 _lmc-entry LIBE.CURRENT-CONTENT-REVISION !
    1 _lmc-entry LIBE.OLDEST-CONTENT-REVISION !
    4096 _lmc-entry LIBE.CONTENT-U !
    _lmc-data 4096 _lmc-entry LIBE.CONTENT-DIGEST SHA3-256-HASH
    _lmc-scale-slot @ 1+ DUP
        _lmc-entry LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _lmc-entry LIBE.CREATED-CLOCK !
    DUP _lmc-entry LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _lmc-entry LIBE.MODIFIED-CLOCK !
    _lmc-entry LIBE.MODIFIED-VALUE !
    15 _lmc-entry LIBE.TITLE-U !
    S" scale-title-hit" DROP _lmc-entry LIBE.TITLE 15 CMOVE
    1 _lmc-entry LIBE.TAG-N !
    13 0 _lmc-entry LIBE-TAG LIB-TAG.LEN !
    S" scale-tag-hit" DROP
        0 _lmc-entry LIBE-TAG LIB-TAG.TEXT 13 CMOVE
    _lmc-scale-slot @ 0x1000 +
        _lmc-entry LIBE.RECEIPT LIBR.OPERATION-KEY _lmc-id!
    LIB-IMPORT-CREATED _lmc-entry LIBE.RECEIPT LIBR.METHOD !
    1 _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-REVISION !
    4096 _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN
        _lmc-entry LIBE.RECEIPT LIBR.INITIAL-MEDIA !
    _lmc-data 4096
        _lmc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-DIGEST
        SHA3-256-HASH
    _lmc-scale-slot @
        _lmc-entry LIBE.RECEIPT
            LIBR.EXPECTED-CATALOG-GENERATION !
    _lmc-entry LIB-ENTRY-REQUEST-SEAL!
        LIB-S-OK = _lmc-assert
    _lmc-entry LIB-ENTRY-VALID? _lmc-assert ;

: _lmc-append-scale-content  ( slot -- )
    _lmc-scale-slot !
    _lmc-content LIB-CONTENT-INIT
    _lmc-scale-slot @ 0x100 + _lmc-content LIBCT.ID _lmc-id!
    1 _lmc-content LIBCT.DOMAIN-REVISION !
    1 _lmc-content LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _lmc-content LIBCT.KIND !
    LIB-MEDIA-TEXT-PLAIN _lmc-content LIBCT.MEDIA !
    _lmc-data _lmc-content LIBCT.DATA-A !
    4096 _lmc-content LIBCT.DATA-U !
    _lmc-content LIB-CONTENT-DIGEST!
        LIB-S-OK = _lmc-assert
    _lmc-frame LIB-CONTENT-FRAME-MAX 0 FILL
    _lmc-content _lmc-frame LIB-CONTENT-FRAME-MAX
        LIB-CONTENT-RECORD-ENCODE
    _lmc-status ! _lmc-record-u !
    _lmc-status @ LIB-S-OK = _lmc-assert
    _lmc-record-u @ LIB-CONTENT-FRAME-SIZE _lmc-frame-u !
    _lmc-frame _lmc-frame-u @ _lmc-content-tail @
        _LIBVFS-CONTENT-PATH$ _lmc-write-at _lmc-assert
    _lmc-frame _lmc-frame-u @ _lmc-frame-sha
        LIB-CONTENT-FRAME-DIGEST LIB-S-OK = _lmc-assert
    _lmc-chain _lmc-content-tail @ _lmc-frame-u @
        _lmc-frame-sha _lmc-chain-next
        LIB-CONTENT-CHAIN-STEP LIB-S-OK = _lmc-assert
    _lmc-chain-next _lmc-chain LIB-DIGEST-SIZE CMOVE
    _lmc-frame-u @ _lmc-content-tail +! ;

: _lmc-build-scale-collection  ( -- )
    _lmc-collection LIB-COLLECTION-INIT
    0x4000 _lmc-scale-collection-id _lmc-id!
    _lmc-scale-collection-id _lmc-collection LIBC.ID RID-COPY
    0x4001 _lmc-collection LIBC.OPERATION-KEY _lmc-id!
    1 _lmc-collection LIBC.REVISION !
    33 _lmc-collection LIBC.MUTATION-SEQUENCE !
    16 _lmc-collection LIBC.TITLE-U !
    S" Scale collection" DROP _lmc-collection LIBC.TITLE 16 CMOVE
    32 _lmc-collection LIBC.MEMBER-N !
    4 0 DO 0xFF _lmc-collection LIBC.MEMBERS I + C! LOOP
    4 _lmc-collection LIBC.EXPECTED-CATALOG-GENERATION !
    _lmc-collection LIB-COLLECTION-REQUEST-SEAL!
        LIB-S-OK = _lmc-assert
    _lmc-collection LIB-COLLECTION-VALID? _lmc-assert
    0 _lmc-encode-collection ;

: _lmc-build-query-scale  ( -- )
    _lmc-data 4096 [CHAR] x FILL
    S" scale-body-hit" DROP _lmc-data 14 CMOVE
    _lmc-bank LIB-BANK-SIZE 0 FILL
    _lmc-chain LIB-CONTENT-CHAIN-GENESIS
        LIB-S-OK = _lmc-assert
    LIB-ARENA-HEADER-SIZE _lmc-content-tail !
    32 0 DO
        I _lmc-build-scale-entry
        I _lmc-encode-entry
        I _lmc-append-scale-content
    LOOP
    32 _lmc-content-count !
    _lmc-build-scale-collection
    _lmc-content-tail @ LIB-ARENA-SIZE < _lmc-assert
    5 32 1 33 _lmc-build-bank ;

: _lmc-build-full-collection  ( slot -- )
    _lmc-scale-slot !
    _lmc-collection LIB-COLLECTION-INIT
    _lmc-scale-slot @ 0x5000 + _lmc-collection LIBC.ID _lmc-id!
    _lmc-scale-slot @ 0x6000 +
        _lmc-collection LIBC.OPERATION-KEY _lmc-id!
    1 _lmc-collection LIBC.REVISION !
    _lmc-scale-slot @ 1+
        _lmc-collection LIBC.MUTATION-SEQUENCE !
    8 _lmc-collection LIBC.TITLE-U !
    S" capacity" DROP _lmc-collection LIBC.TITLE 8 CMOVE
    6 _lmc-collection LIBC.EXPECTED-CATALOG-GENERATION !
    _lmc-collection LIB-COLLECTION-REQUEST-SEAL!
        LIB-S-OK = _lmc-assert
    _lmc-collection LIB-COLLECTION-VALID? _lmc-assert
    _lmc-scale-slot @ _lmc-encode-collection ;

: _lmc-build-collection-full  ( -- )
    _lmc-bank LIB-BANK-SIZE 0 FILL
    _lmc-empty-content
    LIB-COLLECTION-MAX 0 DO I _lmc-build-full-collection LOOP
    7 0 LIB-COLLECTION-MAX LIB-COLLECTION-MAX _lmc-build-bank ;

: _lmc-build-live-catalog-full  ( -- )
    _lmc-data 4096 [CHAR] x FILL
    S" scale-body-hit" DROP _lmc-data 14 CMOVE
    _lmc-bank LIB-BANK-SIZE 0 FILL
    _lmc-chain LIB-CONTENT-CHAIN-GENESIS
        LIB-S-OK = _lmc-assert
    LIB-ARENA-HEADER-SIZE _lmc-content-tail !
    LIB-CATALOG-MAX 0 DO
        I _lmc-build-scale-entry
        I _lmc-encode-entry
        I _lmc-append-scale-content
    LOOP
    LIB-CATALOG-MAX _lmc-content-count !
    _lmc-content-tail @ LIB-ARENA-SIZE < _lmc-assert
    6 LIB-CATALOG-MAX 0 LIB-CATALOG-MAX _lmc-build-bank ;

: _lmc-profile-start  ( -- )
    _LIBPQ-RESET
    PERF-RESET ;

: _lmc-profile-stop  ( -- )
    PERF-CYCLES _lmc-perf-cycles !
    PERF-STALLS _lmc-perf-stalls !
    PERF-EXTMEM _lmc-perf-extmem ! ;

: _lmc-cycle-at-most  ( maximum -- )
    _lmc-perf-cycles @ SWAP <= _lmc-assert ;

: _lmc-profile-line  ( label-a label-u -- )
    ." LIBRARY SCALE " TYPE
    ."  cycles=" _lmc-perf-cycles @ .
    ."  stalls=" _lmc-perf-stalls @ .
    ."  extmem=" _lmc-perf-extmem @ .
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

: _lmc-scale-summary  ( slot -- summary )
    LIBRARY-QUERY-SUMMARY-SIZE * _lmc-query-page + ;

: _lmc-scale-query!  ( term-a term-u field-mask -- )
    >R
    _lmc-query-request LIBRARY-CORPUS-QUERY-REQUEST-INIT
    _lmc-query-request LIBRARY-CORPUS-QUERY-TERM!
        LIBSTORE-S-OK = _lmc-assert
    R> _lmc-query-request LIBCQR.FIELD-MASK !
    _lmc-query-request LIBRARY-CORPUS-QUERY-REQUEST-VALID?
        _lmc-assert ;

: _lmc-scale-query  ( -- )
    _lmc-query-request _lmc-query-page LIBRARY-QUERY-PAGE-MAX
        _lmc-store LIBRARY-VFS-STORE-QUERY-CORPUS
    _lmc-query-status ! _lmc-query-generation !
    _lmc-query-next ! _lmc-query-count ! ;

: _lmc-scale-query-ok  ( count -- )
    _lmc-query-count @ = _lmc-assert
    _lmc-query-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-query-next @ -1 = _lmc-assert
    _lmc-query-generation @ 5 = _lmc-assert ;

: _lmc-scale-page-exact  ( -- )
    32 0 DO
        I 0x100 + _lmc-id _lmc-id!
        _lmc-id I _lmc-scale-summary LIBQS.REF RREF.ID RID=
            _lmc-assert
        I _lmc-scale-summary LIBQS.DOMAIN-REVISION @ 1 = _lmc-assert
        I _lmc-scale-summary LIBQS.KIND @
            LIB-KIND-MANAGED-DOCUMENT = _lmc-assert
        I _lmc-scale-summary LIBQS.LIFECYCLE @
            LIB-LIFECYCLE-ACTIVE = _lmc-assert
        I _lmc-scale-summary LIBQS.MEDIA @
            LIB-MEDIA-TEXT-PLAIN = _lmc-assert
        I _lmc-scale-summary LIBQS.CONTENT-U @ 4096 = _lmc-assert
        I _lmc-scale-summary LIBQS.MUTATION-SEQUENCE @
            I 1+ = _lmc-assert
        I _lmc-scale-summary LIBQS.CONTENT-DIGEST
            _lmc-entry LIBE.CONTENT-DIGEST SHA3-256-COMPARE
            _lmc-assert
        I _lmc-scale-summary LIBQS-TITLE$
            S" scale-title-hit" COMPARE 0= _lmc-assert
    LOOP ;

: _lmc-scale-warm-counters  ( -- )
    _LIBPQ-FULL-VALIDATION@ 0= _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lmc-assert
    _LIBPQ-ARENA-SCAN@ 0= _lmc-assert ;

: _lmc-rid-candidate!  ( attempt destination -- )
    _lmc-entry-id ! _lmc-attempt !
    _lmc-attempt @ _lmc-attempt-cell !
    SHA3-256-BEGIN
    S" org.akashic.library.managed-document-rid.v1" SHA3-256-ADD
    _lmc-arena-id LIB-DIGEST-SIZE SHA3-256-ADD
    _lmc-zero-entropy LIB-DIGEST-SIZE SHA3-256-ADD
    _lmc-attempt-cell 8 SHA3-256-ADD
    _lmc-entry-id @ SHA3-256-END ;

: _lmc-build-allocation-full  ( -- )
    _lmc-bank LIB-BANK-SIZE 0 FILL
    _lmc-empty-content
    16 0 DO
        I _lmc-id _lmc-rid-candidate!
        _lmc-id RID-PRESENT? _lmc-assert
        I 2001 + _lmc-key _lmc-id!
        _lmc-id _lmc-key I 1+ _lmc-build-tombstone
        I _lmc-encode-entry
    LOOP
    4 16 0 16 _lmc-build-bank ;

: _lmc-create-failure  ( expected-status expected-generation expected-rng -- )
    _lmc-expected-rng ! _lmc-generation ! _lmc-expected-status !
    _lmc-result LIB-ENTRY-SIZE 165 FILL
    _lmc-arm-observers
    _lmc-request _lmc-result _lmc-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        _lmc-expected-status @ = _lmc-assert
    _lmc-write-calls @ 0= _lmc-assert
    _lmc-checkpoint-calls @ 0= _lmc-assert
    _lmc-random-calls @ _lmc-expected-rng @ = _lmc-assert
    _lmc-result LIB-ENTRY-SIZE _lmc-zero? _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.GENERATION @
        _lmc-generation @ = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.HEAD LIBHF.GENERATION @
        _lmc-generation @ = _lmc-assert
    _lmc-disarm ;

: _lmc-collection-create-request!  ( -- )
    _lmc-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-INIT
    7 _lmc-collection-request LIBCCR.EXPECTED-CATALOG-GENERATION !
    _lmc-create-key LIB-DIGEST-SIZE 0xD5 FILL
    _lmc-create-key _lmc-collection-request
        LIBRARY-COLLECTION-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lmc-assert
    S" overflow" _lmc-collection-request
        LIBRARY-COLLECTION-CREATE-TITLE!
        LIBSTORE-S-OK = _lmc-assert
    _lmc-collection-request LIBRARY-COLLECTION-CREATE-REQUEST-VALID?
        _lmc-assert ;

: _lmc-catalog-full-case  ( -- )
    _lmc-build-catalog-full
    2 1 1 _lmc-publish
    _lmc-create-key LIB-DIGEST-SIZE 0xD1 FILL
    _lmc-create-key 2 S" new" _lmc-request!
    LIBSTORE-S-CATALOG-FULL 2 0 _lmc-create-failure
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        LIB-CATALOG-MAX = _lmc-assert
    _lmc-stack ;

: _lmc-content-full-case  ( -- )
    _lmc-build-content-full
    3 0 2 _lmc-publish
    _lmc-data LIB-CONTENT-MAX 0 FILL
    _LIBPQ-RESET
    _lmc-entry LIBE.ID 9 _lmc-data LIB-CONTENT-MAX
        _lmc-result _lmc-content
        _lmc-store LIBRARY-VFS-STORE-READ-MANAGED-EXACT
        _lmc-status ! _lmc-length !
    ." LIBRARY DIRECT 64K status=" _lmc-status @ .
    ."  required=" _lmc-length @ .
    ."  full=" _LIBPQ-FULL-VALIDATION@ .
    ."  warm=" _LIBPQ-WARM-ASSURANCE@ .
    ."  index=" _LIBPQ-INDEX-REBUILD@ .
    ."  entry=" _LIBPQ-ENTRY-READ@ .
    ."  direct=" _LIBPQ-DIRECT-FRAME-READ@ .
    ."  direct-bytes=" _LIBPQ-DIRECT-FRAME-BYTES@ .
    ."  scans=" _LIBPQ-ARENA-SCAN@ . CR
    _lmc-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-length @ LIB-CONTENT-MAX = _lmc-assert
    _lmc-content LIBCT.CONTENT-REVISION @ 9 = _lmc-assert
    _lmc-data C@ 0x78 = _lmc-assert
    _lmc-data LIB-CONTENT-MAX 1- + C@ 0x78 = _lmc-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lmc-assert
    _LIBPQ-ENTRY-READ@ 1 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 1 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-BYTES@ LIB-CONTENT-FRAME-MAX = _lmc-assert
    _LIBPQ-ARENA-SCAN@ 0= _lmc-assert
    _lmc-create-key LIB-DIGEST-SIZE 0xD2 FILL
    _lmc-create-key 3 _lmc-data LIB-CONTENT-MAX _lmc-request!
    LIBSTORE-S-CONTENT-FULL 3 0 _lmc-create-failure
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-RECORD-COUNT @
        9 = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
        _lmc-content-tail @ = _lmc-assert
    _lmc-stack ;

: _lmc-allocation-case  ( -- )
    _lmc-build-allocation-full
    4 1 3 _lmc-publish
    _lmc-create-key LIB-DIGEST-SIZE 0xD3 FILL
    _lmc-create-key 4 S" new" _lmc-request!
    LIBSTORE-S-ALLOCATION 4 64 _lmc-create-failure
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        16 = _lmc-assert
    _lmc-stack ;

: _lmc-scale-cold-load  ( -- )
    _lmc-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lmc-assert
    _lmc-vfs @ _lmc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-profile-start
    _lmc-store LIBRARY-VFS-STORE-LOAD _lmc-status !
    _lmc-profile-stop
    _lmc-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.GENERATION @ 5 = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        32 = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.COLLECTION-COUNT @
        1 = _lmc-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lmc-assert
    _LMC-COLD-32X4K-CYCLE-MAX _lmc-cycle-at-most
    S" cold-load-32x4k" _lmc-profile-line ;

: _lmc-scale-browse-profile  ( -- )
    0 0 LIBRARY-CORPUS-FIELD-ALL _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-PAGE-CYCLE-MAX _lmc-cycle-at-most
    S" empty-browse-32x4k" _lmc-profile-line ;

: _lmc-scale-title-profiles  ( -- )
    S" scale-title-hit" LIBRARY-CORPUS-FIELD-TITLE
        _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-PAGE-CYCLE-MAX _lmc-cycle-at-most
    _lmc-query-page _lmc-query-baseline
        LIBRARY-QUERY-SUMMARY-SIZE 32 * CMOVE
    S" title-first-32x4k" _lmc-profile-line

    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-PAGE-CYCLE-MAX _lmc-cycle-at-most
    _lmc-query-page LIBRARY-QUERY-SUMMARY-SIZE 32 *
        _lmc-query-baseline LIBRARY-QUERY-SUMMARY-SIZE 32 *
        COMPARE 0= _lmc-assert
    S" title-repeat-32x4k" _lmc-profile-line

    S" zzz" LIBRARY-CORPUS-FIELD-TITLE _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    0 _lmc-scale-query-ok
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 0= _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-MISS-CYCLE-MAX _lmc-cycle-at-most
    S" title-miss-32x4k" _lmc-profile-line ;

: _lmc-scale-tag-profiles  ( -- )
    S" scale-tag-hit" LIBRARY-CORPUS-FIELD-TAGS _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-PAGE-CYCLE-MAX _lmc-cycle-at-most
    _lmc-query-page LIBRARY-QUERY-SUMMARY-SIZE 32 *
        _lmc-query-baseline LIBRARY-QUERY-SUMMARY-SIZE 32 *
        COMPARE 0= _lmc-assert
    S" tag-hit-32x4k" _lmc-profile-line

    S" zzz" LIBRARY-CORPUS-FIELD-TAGS _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    0 _lmc-scale-query-ok
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 0= _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-MISS-CYCLE-MAX _lmc-cycle-at-most
    S" tag-miss-32x4k" _lmc-profile-line ;

: _lmc-scale-collection-profiles  ( -- )
    _lmc-profile-start
    0 0 _lmc-collection-page 1 _lmc-store
        LIBRARY-VFS-STORE-QUERY-COLLECTIONS
    _lmc-query-status ! _lmc-query-generation !
    _lmc-query-next ! _lmc-query-count !
    _lmc-profile-stop
    1 _lmc-scale-query-ok
    _lmc-scale-collection-id
        _lmc-collection-page LIBCS.REF RREF.ID RID= _lmc-assert
    _lmc-collection-page LIBCS.REVISION @ 1 = _lmc-assert
    _lmc-collection-page LIBCS.MEMBER-N @ 32 = _lmc-assert
    _lmc-collection-page LIBCS-TITLE$
        S" Scale collection" COMPARE 0= _lmc-assert
    _lmc-scale-warm-counters
    _LIBPQ-COLLECTION-READ@ 1 = _lmc-assert
    _LIBPQ-ENTRY-READ@ 0= _lmc-assert
    _LMC-WARM-PAGE-CYCLE-MAX _lmc-cycle-at-most
    S" collection-enum-32x4k" _lmc-profile-line

    S" scale-title-hit" LIBRARY-CORPUS-FIELD-TITLE
        _lmc-scale-query!
    _lmc-scale-collection-id _lmc-query-request
        LIBRARY-CORPUS-QUERY-COLLECTION!
        LIBSTORE-S-OK = _lmc-assert
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _lmc-scale-warm-counters
    _LIBPQ-COLLECTION-READ@ 1 = _lmc-assert
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-PAGE-CYCLE-MAX _lmc-cycle-at-most
    _lmc-query-page LIBRARY-QUERY-SUMMARY-SIZE 32 *
        _lmc-query-baseline LIBRARY-QUERY-SUMMARY-SIZE 32 *
        COMPARE 0= _lmc-assert
    S" collection-filter-32x4k" _lmc-profile-line ;

: _lmc-scale-body-profiles  ( -- )
    S" zzz" LIBRARY-CORPUS-FIELD-BODY _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    0 _lmc-scale-query-ok
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 0= _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    _LMC-WARM-MISS-CYCLE-MAX _lmc-cycle-at-most
    S" body-bloom-miss-32x4k" _lmc-profile-line

    S" scale-body-hit" LIBRARY-CORPUS-FIELD-BODY _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-BYTES@
        4096 LIB-CONTENT-RECORD-SIZE LIB-CONTENT-FRAME-SIZE 32 *
        = _lmc-assert
    _LMC-BODY-HIT-CYCLE-MAX _lmc-cycle-at-most
    _lmc-query-page LIBRARY-QUERY-SUMMARY-SIZE 32 *
        _lmc-query-baseline LIBRARY-QUERY-SUMMARY-SIZE 32 *
        COMPARE 0= _lmc-assert
    S" body-hit-32x4k" _lmc-profile-line

    S" z" LIBRARY-CORPUS-FIELD-BODY _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    0 _lmc-scale-query-ok
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-BYTES@
        4096 LIB-CONTENT-RECORD-SIZE LIB-CONTENT-FRAME-SIZE 32 *
        = _lmc-assert
    _LMC-SHORT-BODY-CYCLE-MAX _lmc-cycle-at-most
    S" body-1byte-miss-32x4k" _lmc-profile-line

    S" zz" LIBRARY-CORPUS-FIELD-BODY _lmc-scale-query!
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    0 _lmc-scale-query-ok
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-BYTES@
        4096 LIB-CONTENT-RECORD-SIZE LIB-CONTENT-FRAME-SIZE 32 *
        = _lmc-assert
    _LMC-SHORT-BODY-CYCLE-MAX _lmc-cycle-at-most
    S" body-2byte-miss-32x4k" _lmc-profile-line ;

: _lmc-scale-index-profiles  ( -- )
    S" scale-title-hit" LIBRARY-CORPUS-FIELD-TITLE
        _lmc-scale-query!
    _LIBIX-TEST-LOSE LIBSTORE-S-OK = _lmc-assert
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _LIBPQ-FULL-VALIDATION@ 0= _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lmc-assert
    _LIBPQ-ENTRY-READ@ 64 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 32 = _lmc-assert
    _LIBPQ-ARENA-SCAN@ 0= _lmc-assert
    _lmc-query-page LIBRARY-QUERY-SUMMARY-SIZE 32 *
        _lmc-query-baseline LIBRARY-QUERY-SUMMARY-SIZE 32 *
        COMPARE 0= _lmc-assert
    S" index-loss-32x4k" _lmc-profile-line

    _LIBIX-TEST-DAMAGE LIBSTORE-S-OK = _lmc-assert
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-page-exact
    _LIBPQ-FULL-VALIDATION@ 0= _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lmc-assert
    _LIBPQ-ENTRY-READ@ 64 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 32 = _lmc-assert
    _LIBPQ-ARENA-SCAN@ 0= _lmc-assert
    _lmc-query-page LIBRARY-QUERY-SUMMARY-SIZE 32 *
        _lmc-query-baseline LIBRARY-QUERY-SUMMARY-SIZE 32 *
        COMPARE 0= _lmc-assert
    S" index-damage-32x4k" _lmc-profile-line

    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    32 _lmc-scale-query-ok
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ 32 = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    S" index-repeat-32x4k" _lmc-profile-line ;

: _lmc-query-scale-case  ( -- )
    _lmc-build-query-scale
    5 0 4 _lmc-publish
    _lmc-vfs @ _lmc-store-b LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    ." LIBRARY SCALE SHAPE records=32 body-bytes=131072 tail="
        _lmc-content-tail @ .
    ."  frame-bytes="
        4096 LIB-CONTENT-RECORD-SIZE LIB-CONTENT-FRAME-SIZE . CR
    ." LIBRARY SCALE FOOTPRINT index=" _LIBIX-BYTES .
    ."  locators=" _LIBLOC-BYTES .
    ."  authority="
        LIB-HEAD-FACT-SIZE
        LIB-CATALOG-MAX _LIBVCF-SIZE * +
        LIB-COLLECTION-MAX _LIBVCCF-SIZE * +
        LIB-CATALOG-MAX LIB-DIGEST-SIZE * +
        LIB-COLLECTION-MAX LIB-DIGEST-SIZE * + . CR
    _lmc-scale-cold-load
    _lmc-scale-browse-profile
    _lmc-scale-title-profiles
    _lmc-scale-tag-profiles
    _lmc-scale-collection-profiles
    _lmc-scale-body-profiles
    _lmc-scale-index-profiles
    _lmc-stack ;

: _lmc-live-catalog-full-case  ( -- )
    _lmc-build-live-catalog-full
    6 1 5 _lmc-publish-through-second
    ." LIBRARY SCALE SHAPE records=128 body-bytes=524288 tail="
        _lmc-content-tail @ .
    ."  arena-limit=" LIB-ARENA-SIZE . CR

    0 0 LIBRARY-CORPUS-FIELD-ALL _lmc-scale-query!
    _lmc-profile-start
    _lmc-scale-query
    _lmc-profile-stop
    _lmc-query-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-query-count @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-next @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-generation @ 6 = _lmc-assert
    _lmc-scale-page-exact
    _LIBPQ-FULL-VALIDATION@ 1 = _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lmc-assert
    _LIBPQ-ENTRY-READ@ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    S" second-descriptor-head-128x4k" _lmc-profile-line

    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    _lmc-query-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-query-count @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-next @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-generation @ 6 = _lmc-assert
    _lmc-scale-page-exact
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    S" second-descriptor-repeat-128x4k" _lmc-profile-line

    \ Reseal a different complete cached head while retaining generation six.
    \ The durable head is unchanged, so only the full-head comparison can
    \ distinguish it from the integrity-valid cached identity.
    _LIBAUTH-TEST-RESEAL-HEAD-MISMATCH
        LIBSTORE-S-OK = _lmc-assert
    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    _lmc-query-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-query-count @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-next @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-generation @ 6 = _lmc-assert
    _lmc-scale-page-exact
    _LIBPQ-FULL-VALIDATION@ 1 = _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lmc-assert
    _LIBPQ-ENTRY-READ@ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    S" same-generation-head-change-128x4k" _lmc-profile-line

    _lmc-profile-start _lmc-scale-query _lmc-profile-stop
    _lmc-query-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-query-count @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-next @ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    _lmc-query-generation @ 6 = _lmc-assert
    _lmc-scale-warm-counters
    _LIBPQ-ENTRY-READ@ LIBRARY-QUERY-PAGE-MAX = _lmc-assert
    S" same-generation-repeat-128x4k" _lmc-profile-line

    _lmc-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lmc-assert
    _lmc-vfs @ _lmc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-profile-start
    _lmc-store LIBRARY-VFS-STORE-LOAD _lmc-status !
    _lmc-profile-stop
    _lmc-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.GENERATION @ 6 = _lmc-assert
    _LIBPQ-FULL-VALIDATION@ 1 = _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 0= _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 1 = _lmc-assert
    S" cold-load-128x4k" _lmc-profile-line

    _lmc-create-key LIB-DIGEST-SIZE 0xD4 FILL
    _lmc-create-key 6 S" new" _lmc-request!
    LIBSTORE-S-CATALOG-FULL 6 0 _lmc-create-failure
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        LIB-CATALOG-MAX = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
        _lmc-content-tail @ = _lmc-assert
    _lmc-stack ;

: _lmc-collection-full-case  ( -- )
    _lmc-build-collection-full
    7 0 6 _lmc-publish
    _lmc-collection-create-request!
    _lmc-collection-view LIBRARY-COLLECTION-VIEW-SIZE 165 FILL
    _lmc-arm-observers
    _lmc-collection-request _lmc-collection-view _lmc-store
        LIBRARY-VFS-STORE-CREATE-COLLECTION
        LIBSTORE-S-COLLECTION-FULL = _lmc-assert
    _lmc-write-calls @ 0= _lmc-assert
    _lmc-checkpoint-calls @ 0= _lmc-assert
    _lmc-random-calls @ 0= _lmc-assert
    _lmc-collection-view LIBRARY-COLLECTION-VIEW-SIZE
        _lmc-zero? _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.GENERATION @ 7 = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.HEAD LIBHF.GENERATION @
        7 = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.COLLECTION-COUNT @
        LIB-COLLECTION-MAX = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE.BANK LIBBF.MUTATION-SEQUENCE @
        LIB-COLLECTION-MAX = _lmc-assert
    _lmc-disarm
    _lmc-stack ;

: _lmc-store-replacement-case  ( -- )
    \ The populated source snapshot must not survive descriptor
    \ reinitialization onto a distinct, newly provisioned empty VFS.
    _LIBAUTH-READY @ 0<> _lmc-assert
    _LIBIX-READY @ 0<> _lmc-assert
    _lmc-replacement-vfs @ _lmc-store-b LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    _LIBAUTH-READY @ 0= _lmc-assert
    _LIBIX-READY @ 0= _lmc-assert

    _lmc-arena-id LIB-DIGEST-SIZE 0xB7 FILL
    _lmc-arena-id _lmc-store-b LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lmc-assert
    _lmc-store-b LIBRARY-VFS-STORE.GENERATION @ 1 = _lmc-assert

    0 0 LIBRARY-CORPUS-FIELD-ALL _lmc-scale-query!
    _lmc-query-page
        LIBRARY-QUERY-SUMMARY-SIZE LIBRARY-QUERY-PAGE-MAX *
        0xA5 FILL
    _lmc-profile-start
    _lmc-query-request _lmc-query-page LIBRARY-QUERY-PAGE-MAX
        _lmc-store-b LIBRARY-VFS-STORE-QUERY-CORPUS
    _lmc-query-status ! _lmc-query-generation !
    _lmc-query-next ! _lmc-query-count !
    _lmc-profile-stop
    ." LIBRARY REPLACEMENT RESULT status=" _lmc-query-status @ .
    ."  count=" _lmc-query-count @ .
    ."  next=" _lmc-query-next @ .
    ."  generation=" _lmc-query-generation @ . CR
    _lmc-query-status @ LIBSTORE-S-OK = _lmc-assert
    _lmc-query-count @ 0= _lmc-assert
    _lmc-query-next @ -1 = _lmc-assert
    _lmc-query-generation @ 1 = _lmc-assert
    LIBRARY-QUERY-PAGE-MAX 0 DO
        _lmc-query-baseline I LIBRARY-QUERY-SUMMARY-SIZE * +
            LIBRARY-QUERY-SUMMARY-INIT
    LOOP
    _lmc-query-page
        LIBRARY-QUERY-SUMMARY-SIZE LIBRARY-QUERY-PAGE-MAX *
        _lmc-query-baseline
        LIBRARY-QUERY-SUMMARY-SIZE LIBRARY-QUERY-PAGE-MAX *
        COMPARE 0= _lmc-assert
    _LIBPQ-FULL-VALIDATION@ 0= _lmc-assert
    _LIBPQ-WARM-ASSURANCE@ 1 = _lmc-assert
    _LIBPQ-INDEX-REBUILD@ 0= _lmc-assert
    _LIBPQ-ENTRY-READ@ 0= _lmc-assert
    _LIBPQ-DIRECT-FRAME-READ@ 0= _lmc-assert
    S" replacement-empty-query" _lmc-profile-line
    _lmc-stack ;

: _lmc-run  ( -- )
    0 _lmc-fails ! 0 _lmc-checks ! DEPTH _lmc-depth !
    VFS-CUR _lmc-old-vfs !
    _lmc-arena-id LIB-DIGEST-SIZE 0xA6 FILL
    _lmc-zero-entropy LIB-DIGEST-SIZE 0 FILL
    4194304 A-XMEM ARENA-NEW DUP 0= _lmc-assert DROP
    DUP _lmc-arena !
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lmc-vfs ! 0<> _lmc-assert
    _lmc-arena @ VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lmc-replacement-vfs ! 0<> _lmc-assert
    _lmc-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE ALLOCATE
        ABORT" LIBRARY MANAGED CAPACITY FAIL allocation"
        _lmc-store-slot !
    LIBRARY-VFS-STORE-SIZE ALLOCATE
        ABORT" LIBRARY MANAGED CAPACITY FAIL second allocation"
        _lmc-store-b-slot !
    _lmc-vfs @ _lmc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-arena-id _lmc-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lmc-assert
    _lmc-catalog-full-case
    _lmc-content-full-case
    _lmc-allocation-case
    _lmc-query-scale-case
    _lmc-live-catalog-full-case
    _lmc-collection-full-case
    _lmc-store-replacement-case
    _lmc-disarm
    _lmc-store-b LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lmc-assert
    _lmc-store-b-slot @ FREE 0 _lmc-store-b-slot !
    _lmc-store-slot @ FREE 0 _lmc-store-slot !
    _lmc-old-vfs @ VFS-USE
    _lmc-vfs @ VFS-DESTROY
    _lmc-replacement-vfs @ VFS-DESTROY
    _lmc-stack
    _lmc-fails @ ?DUP IF
        ." LIBRARY MANAGED CAPACITY FAIL " .
        ." / " _lmc-checks @ . CR
    ELSE
        ." LIBRARY MANAGED CAPACITY PASS" CR
    THEN ;

_lmc-run
