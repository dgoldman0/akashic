\ =====================================================================
\  Deterministic Gate 4B contracts for the sole Library VFS owner
\ =====================================================================

VARIABLE _lvsc-fails
VARIABLE _lvsc-checks
VARIABLE _lvsc-depth
VARIABLE _lvsc-store-a-slot
VARIABLE _lvsc-store-b-slot
VARIABLE _lvsc-vfs
VARIABLE _lvsc-other-vfs
VARIABLE _lvsc-arena
VARIABLE _lvsc-old-vfs
VARIABLE _lvsc-write-calls
VARIABLE _lvsc-read-calls
VARIABLE _lvsc-read-fail-at
VARIABLE _lvsc-read-throw
VARIABLE _lvsc-fd
VARIABLE _lvsc-io-a
VARIABLE _lvsc-io-u
VARIABLE _lvsc-io-off
VARIABLE _lvsc-path-a
VARIABLE _lvsc-path-u
VARIABLE _lvsc-remaining
VARIABLE _lvsc-chunk
VARIABLE _lvsc-text-a
VARIABLE _lvsc-text-u
VARIABLE _lvsc-text-dest
VARIABLE _lvsc-text-len
VARIABLE _lvsc-head-generation
VARIABLE _lvsc-head-expected
VARIABLE _lvsc-head-sha
VARIABLE _lvsc-content-revision
VARIABLE _lvsc-content-data-a
VARIABLE _lvsc-content-data-u
VARIABLE _lvsc-fdfree-before
VARIABLE _lvsc-cwd-before
VARIABLE _lvsc-bank-format
VARIABLE _lvsc-initial-mismatch
VARIABLE _lvsc-bank-generation
VARIABLE _lvsc-link-buf
VARIABLE _lvsc-link-cap
VARIABLE _lvsc-link-in
VARIABLE _lvsc-link-target-a
VARIABLE _lvsc-link-target-u
VARIABLE _lvsc-rename-path-a
VARIABLE _lvsc-rename-path-u
VARIABLE _lvsc-rename-name-a
VARIABLE _lvsc-rename-name-u
VARIABLE _lvsc-rename-in
VARIABLE _lvsc-alias-target

CREATE _lvsc-link-ops VFS-OPS-SIZE ALLOT
CREATE _lvsc-link-binding VFS-BINDING-DESC-SIZE ALLOT

CREATE _lvsc-arena-id-a LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-arena-id-b LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-entry LIB-ENTRY-SIZE ALLOT
CREATE _lvsc-entry2 LIB-ENTRY-SIZE ALLOT
CREATE _lvsc-collection LIB-COLLECTION-SIZE ALLOT
CREATE _lvsc-content LIB-CONTENT-SIZE ALLOT
CREATE _lvsc-frame LIB-STORE-SECTOR-SIZE 2 * ALLOT
CREATE _lvsc-chain LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-frame-sha LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-chain-next LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-bank-fact LIB-BANK-FACT-SIZE ALLOT
CREATE _lvsc-head-fact LIB-HEAD-FACT-SIZE ALLOT
CREATE _lvsc-bank-sha LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-future-sha LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-before-sha LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-after-sha LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-discard-sha LIB-DIGEST-SIZE ALLOT
CREATE _lvsc-io-byte 1 ALLOT
CREATE _lvsc-hash-block 16384 ALLOT
LIB-BANK-SIZE XBUF _lvsc-bank

: _lvsc-link-return  ( target-a target-u -- actual ior )
    _lvsc-link-target-u ! _lvsc-link-target-a !
    _lvsc-link-cap @ 0= IF _lvsc-link-target-u @ 0 EXIT THEN
    _lvsc-link-target-u @ _lvsc-link-cap @ > IF
        0 VFS-E-OVERFLOW EXIT
    THEN
    _lvsc-link-target-a @ _lvsc-link-buf @ _lvsc-link-target-u @ MOVE
    _lvsc-link-target-u @ 0 ;

: _lvsc-readlink  ( buffer capacity inode vfs -- actual ior )
    DROP _lvsc-link-in ! _lvsc-link-cap ! _lvsc-link-buf !
    _lvsc-link-in @ IN.BID @
    DUP 900 = IF DROP S" library-target" _lvsc-link-return EXIT THEN
    DUP 901 = IF DROP S" head-target.bin" _lvsc-link-return EXIT THEN
    DUP 902 = IF DROP S" catalog-a-target.bin" _lvsc-link-return EXIT THEN
    DUP 903 = IF DROP S" content-target.bin" _lvsc-link-return EXIT THEN
    DROP 0 VFS-E-CORRUPT ;

: _lvsc-link-binding-init  ( -- )
    VFS-RAM-OPS _lvsc-link-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _lvsc-link-binding VFS-BINDING-DESC-SIZE MOVE
    _lvsc-link-ops _lvsc-link-binding VB.OPS !
    _lvsc-link-binding VB.CAPS DUP @ VFS-CAP-READLINK OR SWAP !
    ['] _lvsc-readlink
        _lvsc-link-ops VFS-OP-READLINK CELLS + ! ;

: _lvsc-store-a  ( -- store ) _lvsc-store-a-slot @ ;
: _lvsc-store-b  ( -- store ) _lvsc-store-b-slot @ ;
: _lvsc-repl  ( -- replacement )
    _lvsc-store-a _LIBRARY-VFS-STORE.CORE VFSNAP.REPLACE ;

: _lvsc-assert  ( flag -- )
    1 _lvsc-checks +!
    0= IF
        1 _lvsc-fails +!
        ." LIBRARY VFS STORE ASSERT " _lvsc-checks @ . CR
    THEN ;

: _lvsc-stack  ( -- )
    DEPTH DUP _lvsc-depth @ <> IF
        ." LIBRARY VFS STORE STACK " _lvsc-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _lvsc-depth @ = _lvsc-assert ;

: _lvsc-allocate  ( size variable -- )
    >R ALLOCATE ABORT" LIBRARY VFS STORE FAIL allocation" R> ! ;

: _lvsc-free  ( variable -- )
    DUP @ ?DUP IF FREE 0 SWAP ! ELSE DROP THEN ;

: _lvsc-rename-path  ( path-a path-u new-a new-u -- inode | 0 )
    _lvsc-rename-name-u ! _lvsc-rename-name-a !
    _lvsc-rename-path-u ! _lvsc-rename-path-a !
    _lvsc-rename-path-a @ _lvsc-rename-path-u @
        VFS-RP-NOFOLLOW-FINAL _lvsc-vfs @ VFS-RESOLVE-POLICY?
    ?DUP IF 2DROP 0 EXIT THEN
    ?DUP 0= IF 0 EXIT THEN _lvsc-rename-in !
    _lvsc-rename-name-a @ _lvsc-rename-name-u @
        _lvsc-rename-in @ _lvsc-vfs @ VFS-RENAME IF 0 EXIT THEN
    _lvsc-rename-in @ ;

: _lvsc-cache-link  ( name-a name-u bid parent -- flag )
    >R VFS-T-SYMLINK SWAP 1 R> _lvsc-vfs @ VFS-CACHE-DENTRY
    ?DUP IF 2DROP 0 EXIT THEN
    0<> ;

: _lvsc-nofollow-link?  ( path-a path-u -- flag )
    VFS-RP-NOFOLLOW-FINAL _lvsc-vfs @ VFS-RESOLVE-POLICY?
    ?DUP IF 2DROP 0 EXIT THEN
    ?DUP 0= IF 0 EXIT THEN IN.TYPE @ VFS-T-SYMLINK = ;

: _lvsc-alias-target?  ( path-a path-u target -- flag )
    _lvsc-alias-target !
    _lvsc-vfs @ VFS-RESOLVE _lvsc-alias-target @ = ;

: _lvsc-direct-bank-open-body  ( -- status )
    _LIBVFS-BANK-A-PATH$ LIB-BANK-SIZE _LIBVP-OPEN-COMMITTED
    DUP IF EXIT THEN DROP _LIBVP-CLOSE-NOW ;

: _lvsc-exact-file?  ( path-a path-u expected-u -- flag )
    >R VFS-CUR VFS-RESOLVE ?DUP 0= IF R> DROP 0 EXIT THEN
    DUP IN.TYPE @ VFS-T-FILE =
    OVER IN.SIZE-HI @ 0= AND
    SWAP IN.SIZE-LO @ R> = AND ;

: _lvsc-no-write  ( source length fd -- ior )
    DROP 2DROP 1 _lvsc-write-calls +! -1 ;

: _lvsc-fault-read  ( destination length fd -- ior )
    1 _lvsc-read-calls +!
    _lvsc-read-calls @ _lvsc-read-fail-at @ = IF
        DROP 2DROP
        _lvsc-read-throw @ IF -7401 THROW THEN
        -1 EXIT
    THEN
    VFS-READ-EXACT ;

: _lvsc-write-at  ( source length offset path-a path-u -- flag )
    _lvsc-path-u ! _lvsc-path-a ! _lvsc-io-off !
    _lvsc-io-u ! _lvsc-io-a !
    _lvsc-path-a @ _lvsc-path-u @ VFS-OPEN
    DUP _lvsc-fd ! 0= IF 0 EXIT THEN
    _lvsc-io-off @ _lvsc-fd @ VFS-SEEK
    _lvsc-io-a @ _lvsc-io-u @ _lvsc-fd @ VFS-WRITE-EXACT 0=
    _lvsc-fd @ VFS-CLOSE ;

: _lvsc-read-at  ( destination length offset path-a path-u -- flag )
    _lvsc-path-u ! _lvsc-path-a ! _lvsc-io-off !
    _lvsc-io-u ! _lvsc-io-a !
    _lvsc-path-a @ _lvsc-path-u @ VFS-OPEN
    DUP _lvsc-fd ! 0= IF 0 EXIT THEN
    _lvsc-io-off @ _lvsc-fd @ VFS-SEEK
    _lvsc-io-a @ _lvsc-io-u @ _lvsc-fd @ VFS-READ-EXACT 0=
    _lvsc-fd @ VFS-CLOSE ;

: _lvsc-file-sha  ( path-a path-u destination -- flag )
    _lvsc-head-sha ! _lvsc-path-u ! _lvsc-path-a !
    _lvsc-path-a @ _lvsc-path-u @ VFS-OPEN
    DUP _lvsc-fd ! 0= IF 0 EXIT THEN
    _lvsc-fd @ VFS-SIZE _lvsc-remaining !
    SHA3-256-BEGIN
    BEGIN _lvsc-remaining @ 0> WHILE
        _lvsc-remaining @ 16384 MIN _lvsc-chunk !
        _lvsc-hash-block _lvsc-chunk @ _lvsc-fd @ VFS-READ-EXACT IF
            _lvsc-discard-sha SHA3-256-END
            _lvsc-fd @ VFS-CLOSE 0 EXIT
        THEN
        _lvsc-hash-block _lvsc-chunk @ SHA3-256-ADD
        _lvsc-chunk @ NEGATE _lvsc-remaining +!
    REPEAT
    _lvsc-head-sha @ SHA3-256-END
    _lvsc-fd @ VFS-CLOSE -1 ;

: _lvsc-text!  ( source-a source-u destination length-cell -- )
    _lvsc-text-len ! _lvsc-text-dest !
    _lvsc-text-u ! _lvsc-text-a !
    _lvsc-text-u @ _lvsc-text-len @ !
    _lvsc-text-a @ _lvsc-text-dest @ _lvsc-text-u @ CMOVE ;

: _lvsc-id!  ( value id -- ) DUP RID-CLEAR ! ;

: _lvsc-build-entry  ( -- )
    _lvsc-entry LIB-ENTRY-INIT
    0x11 _lvsc-entry LIBE.ID _lvsc-id!
    1 _lvsc-entry LIBE.DOMAIN-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _lvsc-entry LIBE.KIND !
    LIB-LIFECYCLE-ACTIVE _lvsc-entry LIBE.LIFECYCLE !
    LIB-MEDIA-TEXT-PLAIN _lvsc-entry LIBE.MEDIA !
    1 _lvsc-entry LIBE.CURRENT-CONTENT-REVISION !
    1 _lvsc-entry LIBE.OLDEST-CONTENT-REVISION !
    5 _lvsc-entry LIBE.CONTENT-U !
    S" hello" _lvsc-entry LIBE.CONTENT-DIGEST SHA3-256-HASH
    1 _lvsc-entry LIBE.MUTATION-SEQUENCE !
    LIB-CLOCK-MUTATION-SEQUENCE _lvsc-entry LIBE.CREATED-CLOCK !
    1 _lvsc-entry LIBE.CREATED-VALUE !
    LIB-CLOCK-MUTATION-SEQUENCE _lvsc-entry LIBE.MODIFIED-CLOCK !
    1 _lvsc-entry LIBE.MODIFIED-VALUE !
    S" First note" _lvsc-entry LIBE.TITLE
        _lvsc-entry LIBE.TITLE-U _lvsc-text!
    0xA1 _lvsc-entry LIBE.RECEIPT LIBR.OPERATION-KEY _lvsc-id!
    LIB-IMPORT-CREATED _lvsc-entry LIBE.RECEIPT LIBR.METHOD !
    1 _lvsc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-REVISION !
    5 _lvsc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-U !
    LIB-MEDIA-TEXT-PLAIN
        _lvsc-entry LIBE.RECEIPT LIBR.INITIAL-MEDIA !
    S" hello" _lvsc-entry LIBE.RECEIPT LIBR.INITIAL-CONTENT-DIGEST
        SHA3-256-HASH
    _lvsc-entry LIB-ENTRY-REQUEST-SEAL! DROP
    2 _lvsc-entry LIBE.DOMAIN-REVISION !
    2 _lvsc-entry LIBE.CURRENT-CONTENT-REVISION !
    6 _lvsc-entry LIBE.CONTENT-U !
    S" world!" _lvsc-entry LIBE.CONTENT-DIGEST SHA3-256-HASH
    2 _lvsc-entry LIBE.MUTATION-SEQUENCE !
    2 _lvsc-entry LIBE.MODIFIED-VALUE ! ;

: _lvsc-build-collection  ( -- )
    _lvsc-collection LIB-COLLECTION-INIT
    0x31 _lvsc-collection LIBC.ID _lvsc-id!
    0xB1 _lvsc-collection LIBC.OPERATION-KEY _lvsc-id!
    1 _lvsc-collection LIBC.REVISION !
    3 _lvsc-collection LIBC.MUTATION-SEQUENCE !
    S" Research" _lvsc-collection LIBC.TITLE
        _lvsc-collection LIBC.TITLE-U _lvsc-text!
    1 _lvsc-collection LIBC.MEMBER-N !
    1 _lvsc-collection LIBC.MEMBERS C!
    _lvsc-collection LIB-COLLECTION-REQUEST-SEAL! DROP ;

: _lvsc-build-one-content  ( revision data-a data-u -- )
    _lvsc-content-data-u ! _lvsc-content-data-a !
    _lvsc-content-revision !
    _lvsc-content LIB-CONTENT-INIT
    0x11 _lvsc-content LIBCT.ID _lvsc-id!
    _lvsc-content-revision @ _lvsc-content LIBCT.DOMAIN-REVISION !
    _lvsc-content-revision @ _lvsc-content LIBCT.CONTENT-REVISION !
    LIB-KIND-MANAGED-DOCUMENT _lvsc-content LIBCT.KIND !
    LIB-MEDIA-TEXT-PLAIN _lvsc-content LIBCT.MEDIA !
    _lvsc-content-data-a @ _lvsc-content LIBCT.DATA-A !
    _lvsc-content-data-u @ _lvsc-content LIBCT.DATA-U !
    _lvsc-content LIB-CONTENT-DIGEST! LIB-S-OK = _lvsc-assert ;

: _lvsc-build-content-frames  ( -- )
    _lvsc-frame LIB-STORE-SECTOR-SIZE 2 * 0 FILL
    _lvsc-initial-mismatch @ IF
        1 S" wrong" _lvsc-build-one-content
    ELSE
        1 S" hello" _lvsc-build-one-content
    THEN
    _lvsc-content _lvsc-frame LIB-STORE-SECTOR-SIZE
        LIB-CONTENT-RECORD-ENCODE
    LIB-S-OK = _lvsc-assert
    168 = _lvsc-assert
    _lvsc-chain LIB-CONTENT-CHAIN-GENESIS LIB-S-OK = _lvsc-assert
    _lvsc-frame LIB-STORE-SECTOR-SIZE _lvsc-frame-sha
        LIB-CONTENT-FRAME-DIGEST LIB-S-OK = _lvsc-assert
    _lvsc-chain LIB-ARENA-HEADER-SIZE LIB-STORE-SECTOR-SIZE
        _lvsc-frame-sha _lvsc-chain-next LIB-CONTENT-CHAIN-STEP
        LIB-S-OK = _lvsc-assert
    _lvsc-chain-next _lvsc-chain LIB-DIGEST-SIZE CMOVE
    2 S" world!" _lvsc-build-one-content
    _lvsc-content _lvsc-frame LIB-STORE-SECTOR-SIZE +
        LIB-STORE-SECTOR-SIZE LIB-CONTENT-RECORD-ENCODE
    LIB-S-OK = _lvsc-assert
    168 = _lvsc-assert
    _lvsc-frame LIB-STORE-SECTOR-SIZE + LIB-STORE-SECTOR-SIZE
        _lvsc-frame-sha LIB-CONTENT-FRAME-DIGEST LIB-S-OK = _lvsc-assert
    _lvsc-chain LIB-ARENA-HEADER-SIZE LIB-STORE-SECTOR-SIZE +
        LIB-STORE-SECTOR-SIZE _lvsc-frame-sha _lvsc-chain-next
        LIB-CONTENT-CHAIN-STEP LIB-S-OK = _lvsc-assert ;

: _lvsc-seal-bank  ( -- )
    _lvsc-bank LIB-BANK-HEADER-SIZE + LIB-BANK-BODY-SIZE CRC32
        0xFFFFFFFF AND _lvsc-bank-fact LIBBF.BODY-CRC !
    _lvsc-bank LIB-BANK-HEADER-SIZE + LIB-BANK-BODY-SIZE
        _lvsc-bank-fact LIBBF.BODY-SHA SHA3-256-HASH
    _lvsc-bank-fact _lvsc-bank LIB-BANK-HEADER-SIZE
        LIB-BANK-HEADER-ENCODE
    LIB-S-OK = _lvsc-assert
    LIB-BANK-HEADER-SIZE = _lvsc-assert
    _lvsc-bank LIB-BANK-SIZE _lvsc-bank-sha SHA3-256-HASH ;

: _lvsc-build-bank  ( -- )
    _lvsc-bank LIB-BANK-SIZE 0 FILL
    _lvsc-entry _lvsc-bank LIB-BANK-CATALOG-OFFSET +
        LIB-CATALOG-RECORD-SIZE LIB-CATALOG-RECORD-ENCODE
    LIB-S-OK = _lvsc-assert
    LIB-CATALOG-RECORD-SIZE = _lvsc-assert
    _lvsc-collection _lvsc-bank LIB-BANK-COLLECTION-OFFSET +
        LIB-COLLECTION-RECORD-SIZE LIB-COLLECTION-RECORD-ENCODE
    LIB-S-OK = _lvsc-assert
    LIB-COLLECTION-RECORD-SIZE = _lvsc-assert
    _lvsc-bank-fact LIB-BANK-FACT-INIT
    _lvsc-bank-generation @ _lvsc-bank-fact LIBBF.GENERATION !
    1 _lvsc-bank-fact LIBBF.CATALOG-COUNT !
    1 _lvsc-bank-fact LIBBF.COLLECTION-COUNT !
    3 _lvsc-bank-fact LIBBF.MUTATION-SEQUENCE !
    _lvsc-arena-id-a _lvsc-bank-fact LIBBF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    LIB-ARENA-HEADER-SIZE LIB-STORE-SECTOR-SIZE 2 * +
        _lvsc-bank-fact LIBBF.CONTENT-TAIL !
    2 _lvsc-bank-fact LIBBF.CONTENT-RECORD-COUNT !
    _lvsc-chain-next _lvsc-bank-fact LIBBF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE
    _lvsc-seal-bank ;

: _lvsc-tombstone-entry2  ( -- )
    3 _lvsc-entry2 LIBE.DOMAIN-REVISION !
    LIB-LIFECYCLE-TOMBSTONED _lvsc-entry2 LIBE.LIFECYCLE !
    LIB-MEDIA-NONE _lvsc-entry2 LIBE.MEDIA !
    0 _lvsc-entry2 LIBE.CURRENT-CONTENT-REVISION !
    0 _lvsc-entry2 LIBE.OLDEST-CONTENT-REVISION !
    0 _lvsc-entry2 LIBE.CONTENT-U !
    _lvsc-entry2 LIBE.CONTENT-DIGEST LIB-DIGEST-SIZE 0 FILL
    3 _lvsc-entry2 LIBE.MUTATION-SEQUENCE !
    _lvsc-entry2 LIBE.CREATED-CLOCK 48 0 FILL
    LIB-CLOCK-MUTATION-SEQUENCE _lvsc-entry2 LIBE.DELETED-CLOCK !
    3 _lvsc-entry2 LIBE.DELETED-VALUE !
    0 _lvsc-entry2 LIBE.TITLE-U !
    _lvsc-entry2 LIBE.TITLE LIB-TITLE-MAX 0 FILL
    0 _lvsc-entry2 LIBE.TAG-N !
    _lvsc-entry2 _LIBE-TAGS + LIB-TAG-MAX LIB-TAG-SIZE * 0 FILL
    _lvsc-entry2 LIBE.ORIGIN LIB-ORIGIN-SIZE 0 FILL
    0 _lvsc-entry2 LIBE.LINEAGE-N !
    _lvsc-entry2 _LIBE-LINEAGE +
        LIB-LINEAGE-MAX LIB-LINEAGE-SIZE * 0 FILL ;

: _lvsc-build-catalog-cross-bank  ( -- )
    _lvsc-build-bank
    _lvsc-entry _lvsc-entry2 LIB-ENTRY-SIZE CMOVE
    _lvsc-entry LIBE.RECEIPT LIBR.OPERATION-KEY
        _lvsc-entry2 LIBE.ID RID-COPY
    0xA2 _lvsc-entry2 LIBE.RECEIPT LIBR.OPERATION-KEY _lvsc-id!
    _lvsc-tombstone-entry2
    _lvsc-entry2 LIB-ENTRY-VALID? _lvsc-assert
    _lvsc-entry2
        _lvsc-bank LIB-BANK-CATALOG-OFFSET + LIB-CATALOG-RECORD-SIZE +
        LIB-CATALOG-RECORD-SIZE LIB-CATALOG-RECORD-ENCODE
    LIB-S-OK = _lvsc-assert
    LIB-CATALOG-RECORD-SIZE = _lvsc-assert
    2 _lvsc-bank-fact LIBBF.CATALOG-COUNT !
    _lvsc-seal-bank ;

: _lvsc-build-collection-cross-bank  ( -- )
    _lvsc-entry LIBE.ID _lvsc-collection LIBC.OPERATION-KEY RID-COPY
    _lvsc-collection LIB-COLLECTION-VALID? _lvsc-assert
    _lvsc-build-bank ;

: _lvsc-build-head  ( generation bank-sha -- )
    _lvsc-head-sha ! _lvsc-head-generation !
    _lvsc-head-fact LIB-HEAD-FACT-INIT
    _lvsc-head-generation @ _lvsc-head-fact LIBHF.GENERATION !
    1 _lvsc-head-fact LIBHF.BANK-SELECTOR !
    _lvsc-bank-fact LIBBF.GENERATION @
        _lvsc-head-fact LIBHF.BANK-GENERATION !
    _lvsc-bank-fact LIBBF.CATALOG-COUNT @
        _lvsc-head-fact LIBHF.CATALOG-COUNT !
    _lvsc-bank-fact LIBBF.COLLECTION-COUNT @
        _lvsc-head-fact LIBHF.COLLECTION-COUNT !
    _lvsc-bank-fact LIBBF.MUTATION-SEQUENCE @
        _lvsc-head-fact LIBHF.MUTATION-SEQUENCE !
    _lvsc-head-sha @ _lvsc-head-fact LIBHF.BANK-SHA
        LIB-DIGEST-SIZE CMOVE
    _lvsc-bank-fact LIBBF.ARENA-ID _lvsc-head-fact LIBHF.ARENA-ID
        LIB-DIGEST-SIZE CMOVE
    _lvsc-bank-fact LIBBF.CONTENT-TAIL @
        _lvsc-head-fact LIBHF.CONTENT-TAIL !
    _lvsc-bank-fact LIBBF.CONTENT-RECORD-COUNT @
        _lvsc-head-fact LIBHF.CONTENT-RECORD-COUNT !
    _lvsc-bank-fact LIBBF.CONTENT-CHAIN _lvsc-head-fact LIBHF.CONTENT-CHAIN
        LIB-DIGEST-SIZE CMOVE ;

: _lvsc-save-head  ( generation expected bank-sha -- status )
    _lvsc-head-sha ! _lvsc-head-expected ! _lvsc-head-generation !
    _lvsc-head-generation @ _lvsc-head-sha @ _lvsc-build-head
    _lvsc-head-fact _lvsc-head-expected @ _lvsc-store-a
        _LIBRARY-VFS-STORE-SAVE-HEAD ;

: _lvsc-reinit  ( -- )
    _lvsc-store-a LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-vfs @ _lvsc-store-a LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lvsc-assert ;

: _lvsc-bank-format!  ( format destination-sha -- )
    _lvsc-head-sha ! _lvsc-bank-format !
    _lvsc-bank-format @ _lvsc-bank _LIBSB-FORMAT + !
    _lvsc-bank _LIBSF-BANK-CRC
        _lvsc-bank _LIBSB-HEADER-CRC + !
    _lvsc-bank LIB-BANK-SIZE _lvsc-head-sha @ SHA3-256-HASH ;

: _lvsc-unpublished-contracts  ( -- )
    _lvsc-store-a LIBRARY-VFS-STORE-LOADED? 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.HEAD LIB-HEAD-FACT-VALID?
        0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.ARENA LIB-ARENA-FACT-VALID?
        0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIB-BANK-FACT-VALID?
        0= _lvsc-assert ;

: _lvsc-status-contracts  ( -- )
    LIBSTORE-S-OK 0= _lvsc-assert
    LIBSTORE-S-ABSENT 1 = _lvsc-assert
    LIBSTORE-S-CORRUPT 2 = _lvsc-assert
    LIBSTORE-S-UNSUPPORTED 3 = _lvsc-assert
    LIBSTORE-S-INVALID 4 = _lvsc-assert
    LIBSTORE-S-CATALOG-FULL 5 = _lvsc-assert
    LIBSTORE-S-COLLECTION-FULL 6 = _lvsc-assert
    LIBSTORE-S-CONTENT-FULL 7 = _lvsc-assert
    LIBSTORE-S-ALLOCATION 8 = _lvsc-assert
    LIBSTORE-S-IO 9 = _lvsc-assert
    LIBSTORE-S-RECOVERY 10 = _lvsc-assert
    LIBSTORE-S-UNCERTAIN 11 = _lvsc-assert
    LIBSTORE-S-BUSY 12 = _lvsc-assert
    LIBSTORE-S-CONFLICT 13 = _lvsc-assert
    LIBSTORE-S-IDEMPOTENCY-MISMATCH 14 = _lvsc-assert
    LIBSTORE-S-NOT-FOUND 15 = _lvsc-assert
    LIBSTORE-S-RETIRED 16 = _lvsc-assert
    LIBSTORE-S-TOMBSTONED 17 = _lvsc-assert
    LIBSTORE-S-GONE 18 = _lvsc-assert
    LIBSTORE-S-OUTPUT-CAPACITY 19 = _lvsc-assert
    _lvsc-stack ;

: _lvsc-init-contracts  ( -- )
    VFS-CUR _lvsc-store-a LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LAST-STATUS@
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LAST-VFSNAP@
        VFSNAP-S-OK = _lvsc-assert

    \ Hostile topology and VFS/store aliases are rejected before INIT FILL.
    VFS-CUR DUP LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-INVALID = _lvsc-assert
    VFS-CUR _LIBVFS-HEAD-PATH$ DROP LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-INVALID = _lvsc-assert
    _lvsc-store-b LIBRARY-VFS-STORE-SIZE 165 FILL
    _LIBVFS-HEAD-PATH$ DROP _lvsc-store-b LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-INVALID = _lvsc-assert
    _lvsc-store-b C@ 165 = _lvsc-assert
    _lvsc-store-b LIBRARY-VFS-STORE-SIZE 1- + C@ 165 = _lvsc-assert
    _LIBVFS-HEAD-PATH$ S" /library/head.bin" COMPARE 0= _lvsc-assert

    -1 _lvsc-repl VREPL.PRE-XT !
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? 0= _lvsc-assert
    0 _lvsc-repl VREPL.PRE-XT !
    -1 _lvsc-repl VREPL.PRE-DATA !
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? 0= _lvsc-assert
    0 _lvsc-repl VREPL.PRE-DATA !
    10 _lvsc-repl VREPL.TARGET-BASE !
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? 0= _lvsc-assert
    _LIBVFS-HEAD-NAME-BASE _lvsc-repl VREPL.TARGET-BASE !
    10 _lvsc-repl VREPL.STAGE-BASE !
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? 0= _lvsc-assert
    _LIBVFS-HEAD-NAME-BASE _lvsc-repl VREPL.STAGE-BASE !
    10 _lvsc-repl VREPL.BACKUP-BASE !
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? 0= _lvsc-assert
    _LIBVFS-HEAD-NAME-BASE _lvsc-repl VREPL.BACKUP-BASE !
    10 _lvsc-repl VREPL.MARKER-BASE !
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? 0= _lvsc-assert
    _LIBVFS-HEAD-NAME-BASE _lvsc-repl VREPL.MARKER-BASE !
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? _lvsc-assert

    _lvsc-store-a LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-VALID? 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-INVALID = _lvsc-assert
    _lvsc-stack ;

: _lvsc-provision-contracts  ( -- )
    _lvsc-arena-id-a LIB-DIGEST-SIZE 0 FILL
    _lvsc-arena-id-b LIB-DIGEST-SIZE 0 FILL
    17 _lvsc-arena-id-a C!
    34 _lvsc-arena-id-b C!

    VFS-CUR _lvsc-store-a LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-ABSENT = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOADED? 0= _lvsc-assert

    \ The first-use files may exist only after a full cold readback passes.
    0 _lvsc-read-calls ! 1 _lvsc-read-fail-at ! 0 _lvsc-read-throw !
    ['] _lvsc-fault-read _LIBVFS-READ-EXACT-XT !
    _lvsc-arena-id-a _lvsc-store-a LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-IO = _lvsc-assert
    ['] VFS-READ-EXACT _LIBVFS-READ-EXACT-XT !
    _lvsc-read-calls @ 1 = _lvsc-assert
    _LIBVFS-HEAD-PATH$ VFS-CUR VFS-RESOLVE 0= _lvsc-assert
    _LIBVFS-BANK-A-PATH$ LIB-BANK-SIZE _lvsc-exact-file? _lvsc-assert
    _LIBVFS-BANK-B-PATH$ LIB-BANK-SIZE _lvsc-exact-file? _lvsc-assert
    _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _lvsc-exact-file? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOADED? 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? 0= _lvsc-assert
    _LIBVP-FD @ 0= _lvsc-assert
    _LIBVP-SHA-ACTIVE @ 0= _lvsc-assert
    _LIBVP-CRC-ACTIVE @ 0= _lvsc-assert
    VFS-CUR _lvsc-vfs @ = _lvsc-assert

    \ Exact pristine topology is resumable for the same requested ID.
    _lvsc-arena-id-a _lvsc-store-a LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-PROVISIONED? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOADED? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 1 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.HEAD LIBHF.GENERATION @
        1 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.HEAD LIBHF.BANK-SELECTOR @
        0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIBBF.GENERATION @
        1 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.HEAD LIBHF.ARENA-ID
        _lvsc-arena-id-a SHA3-256-COMPARE _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.ARENA LIBAF.ARENA-ID
        _lvsc-arena-id-a SHA3-256-COMPARE _lvsc-assert
    _LIBVFS-HEAD-PATH$ 512 _lvsc-exact-file? _lvsc-assert
    _LIBVFS-BANK-A-PATH$ LIB-BANK-SIZE _lvsc-exact-file? _lvsc-assert
    _LIBVFS-BANK-B-PATH$ LIB-BANK-SIZE _lvsc-exact-file? _lvsc-assert
    _LIBVFS-CONTENT-PATH$ LIB-ARENA-SIZE _lvsc-exact-file? _lvsc-assert
    VFS-CUR _lvsc-vfs @ = _lvsc-assert

    0 _lvsc-write-calls !
    ['] _lvsc-no-write _LIBVFS-WRITE-EXACT-XT !
    _lvsc-arena-id-a _lvsc-store-a LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lvsc-assert
    ['] VFS-WRITE-EXACT _LIBVFS-WRITE-EXACT-XT !
    _lvsc-write-calls @ 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 1 = _lvsc-assert

    _lvsc-arena-id-b _lvsc-store-a LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-CONFLICT = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOADED? 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.HEAD LIB-HEAD-FACT-VALID?
        0= _lvsc-assert

    _lvsc-store-a LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lvsc-assert
    VFS-CUR _lvsc-store-a LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOADED? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 1 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-stack ;

: _lvsc-namespace-contracts  ( -- )
    _lvsc-vfs @ VFS-USE
    _lvsc-vfs @ _lvsc-store-a LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    _LIBAUTH-READY @ _lvsc-assert

    \ A valid complete store behind a /library symlink is not Library's
    \ sealed namespace.  The Library parent preflight rejects before the
    \ public VFSNAP call and clears published warm authority; terminal-name
    \ atomicity remains inside VFSNAP/VREPL.
    _LIBVFS-DIRECTORY$ S" library-target" _lvsc-rename-path
        DUP _lvsc-alias-target ! 0<> _lvsc-assert
    S" library" 900 _lvsc-vfs @ V.ROOT @ _lvsc-cache-link _lvsc-assert
    _LIBVFS-DIRECTORY$ _lvsc-nofollow-link? _lvsc-assert
    _LIBVFS-DIRECTORY$ _lvsc-alias-target @
        _lvsc-alias-target? _lvsc-assert
    _lvsc-vfs @ _LIBVP-VFS !
    ['] _lvsc-direct-bank-open-body _LIBVP-RUN
        LIBSTORE-S-RECOVERY = _lvsc-assert
    _LIBVP-FD @ 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-RECOVERY = _lvsc-assert
    _lvsc-unpublished-contracts
    _LIBAUTH-READY @ 0= _lvsc-assert
    _LIBVFS-DIRECTORY$ _lvsc-vfs @ VFS-RM 0= _lvsc-assert

    \ An absent parent must not erase a durability core's latched damage.
    \ RECOVER and LOAD-HEAD delegate to blocked VFSNAP before considering
    \ their normal first-use parent shortcuts.
    _lvsc-store-a _LIBRARY-VFS-STORE.CORE DUP
        VFSNAP-S-CORRUPT SWAP VFSNAP.LAST-STATUS !
    VFSNAP.FLAGS DUP @ _VFSNAP-STORE-F-BLOCKED OR SWAP !
    _lvsc-store-a _LIBRARY-VFS-STORE-RECOVER
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-store-a _LIBRARY-VFS-STORE-LOAD-HEAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LAST-VFSNAP@
        VFSNAP-S-CORRUPT = _lvsc-assert

    S" library" _lvsc-alias-target @ _lvsc-vfs @ VFS-RENAME
        0= _lvsc-assert
    _lvsc-reinit
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert

    \ VFSNAP/VREPL owns the terminal head classification.  Library adapts
    \ its RECOVERY result and never accepts the valid redirected envelope.
    _LIBVFS-HEAD-PATH$ S" head-target.bin" _lvsc-rename-path
        DUP _lvsc-alias-target ! 0<> _lvsc-assert
    _LIBVFS-DIRECTORY$ VFS-RP-NOFOLLOW-FINAL _lvsc-vfs @
        VFS-RESOLVE-POLICY? ?DUP IF THROW THEN
    >R S" head.bin" 901 R> _lvsc-cache-link _lvsc-assert
    _LIBVFS-HEAD-PATH$ _lvsc-nofollow-link? _lvsc-assert
    _LIBVFS-HEAD-PATH$ _lvsc-alias-target @
        _lvsc-alias-target? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-RECOVERY = _lvsc-assert
    _lvsc-unpublished-contracts
    _LIBAUTH-READY @ 0= _lvsc-assert
    _LIBVFS-HEAD-PATH$ _lvsc-vfs @ VFS-RM 0= _lvsc-assert
    S" head.bin" _lvsc-alias-target @ _lvsc-vfs @ VFS-RENAME
        0= _lvsc-assert
    _lvsc-reinit
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert

    \ Direct bank and content names are inspected nofollow inside the same
    \ serialized read transaction.  A valid target does not become corpus
    \ authority, and the ordinary corruption path invalidates warm state.
    _LIBVFS-BANK-A-PATH$ S" catalog-a-target.bin" _lvsc-rename-path
        DUP _lvsc-alias-target ! 0<> _lvsc-assert
    _LIBVFS-DIRECTORY$ VFS-RP-NOFOLLOW-FINAL _lvsc-vfs @
        VFS-RESOLVE-POLICY? ?DUP IF THROW THEN
    >R S" catalog-a.bin" 902 R> _lvsc-cache-link _lvsc-assert
    _LIBVFS-BANK-A-PATH$ _lvsc-nofollow-link? _lvsc-assert
    _LIBVFS-BANK-A-PATH$ _lvsc-alias-target @
        _lvsc-alias-target? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-unpublished-contracts
    _LIBAUTH-READY @ 0= _lvsc-assert
    _LIBVFS-BANK-A-PATH$ _lvsc-vfs @ VFS-RM 0= _lvsc-assert
    S" catalog-a.bin" _lvsc-alias-target @ _lvsc-vfs @ VFS-RENAME
        0= _lvsc-assert
    _lvsc-reinit
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert

    _LIBVFS-CONTENT-PATH$ S" content-target.bin" _lvsc-rename-path
        DUP _lvsc-alias-target ! 0<> _lvsc-assert
    _LIBVFS-DIRECTORY$ VFS-RP-NOFOLLOW-FINAL _lvsc-vfs @
        VFS-RESOLVE-POLICY? ?DUP IF THROW THEN
    >R S" content.bin" 903 R> _lvsc-cache-link _lvsc-assert
    _LIBVFS-CONTENT-PATH$ _lvsc-nofollow-link? _lvsc-assert
    _LIBVFS-CONTENT-PATH$ _lvsc-alias-target @
        _lvsc-alias-target? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-unpublished-contracts
    _LIBAUTH-READY @ 0= _lvsc-assert
    _LIBVFS-CONTENT-PATH$ _lvsc-vfs @ VFS-RM 0= _lvsc-assert
    S" content.bin" _lvsc-alias-target @ _lvsc-vfs @ VFS-RENAME
        0= _lvsc-assert
    _lvsc-reinit
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-stack ;

: _lvsc-nonempty-contracts  ( -- )
    _lvsc-vfs @ VFS-USE
    _lvsc-vfs @ _lvsc-store-a LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lvsc-assert

    \ Publish one fully sealed inactive-bank snapshot: one managed entry,
    \ retained revisions 1+2, and one collection whose sole bit names it.
    0 _lvsc-initial-mismatch !
    2 _lvsc-bank-generation !
    _lvsc-build-entry
    _lvsc-build-collection
    _lvsc-build-content-frames
    _lvsc-entry LIB-ENTRY-VALID? _lvsc-assert
    _lvsc-collection LIB-COLLECTION-VALID? _lvsc-assert
    _lvsc-build-bank
    _lvsc-frame LIB-STORE-SECTOR-SIZE 2 * LIB-ARENA-HEADER-SIZE
        _LIBVFS-CONTENT-PATH$ _lvsc-write-at _lvsc-assert
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-vfs @ VFS-SYNC 0= _lvsc-assert
    2 1 _lvsc-bank-sha _lvsc-save-head LIBSTORE-S-OK = _lvsc-assert

    \ A cold descriptor publishes facts only after all record relations pass.
    _lvsc-reinit
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOADED? _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 2 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.HEAD LIBHF.BANK-SELECTOR @
        1 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIBBF.GENERATION @
        2 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        1 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIBBF.COLLECTION-COUNT @
        1 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIBBF.MUTATION-SEQUENCE @
        3 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-RECORD-COUNT @
        2 = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-TAIL @
        LIB-ARENA-HEADER-SIZE LIB-STORE-SECTOR-SIZE 2 * + = _lvsc-assert

    \ The inactive bank is not discovered, and bytes after committed tail
    \ are deliberately outside the content scan.
    0x5A _lvsc-io-byte C!
    _lvsc-io-byte 1 LIB-BANK-SIZE 1- _LIBVFS-BANK-A-PATH$
        _lvsc-write-at _lvsc-assert
    0x6B _lvsc-io-byte C!
    _lvsc-io-byte 1 4096 _LIBVFS-CONTENT-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    0 _lvsc-io-byte C!
    _lvsc-io-byte 1 LIB-BANK-SIZE 1- _LIBVFS-BANK-A-PATH$
        _lvsc-read-at _lvsc-assert
    _lvsc-io-byte C@ 0x5A = _lvsc-assert
    0 _lvsc-io-byte C!
    _lvsc-io-byte 1 LIB-BANK-SIZE 1- _LIBVFS-BANK-A-PATH$
        _lvsc-write-at _lvsc-assert

    \ A throwing transfer during the selected-bank hash must unwind the
    \ hash context, FD, CWD, and selector; the next cold load must work.
    _lvsc-vfs @ V.FDFREE @ _lvsc-fdfree-before !
    _lvsc-vfs @ V.CWD @ _lvsc-cwd-before !
    _lvsc-other-vfs @ VFS-USE
    0 _lvsc-read-calls ! 1 _lvsc-read-fail-at ! -1 _lvsc-read-throw !
    ['] _lvsc-fault-read _LIBVFS-READ-EXACT-XT !
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-IO = _lvsc-assert
    ['] VFS-READ-EXACT _LIBVFS-READ-EXACT-XT !
    _lvsc-read-calls @ 1 = _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-CLEANUP-FAILED? 0= _lvsc-assert
    _LIBVP-FD @ 0= _lvsc-assert
    _LIBVP-SHA-ACTIVE @ 0= _lvsc-assert
    _LIBVP-CRC-ACTIVE @ 0= _lvsc-assert
    _lvsc-vfs @ V.FDFREE @ _lvsc-fdfree-before @ = _lvsc-assert
    _lvsc-vfs @ V.CWD @ _lvsc-cwd-before @ = _lvsc-assert
    VFS-CUR _lvsc-other-vfs @ = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    VFS-CUR _lvsc-other-vfs @ = _lvsc-assert
    _lvsc-vfs @ VFS-USE

    \ Selected bytes are commit evidence: a body tamper blocks and clears
    \ all facts, while restoring the committed byte makes LOAD recoverable.
    0xA5 _lvsc-io-byte C!
    _lvsc-io-byte 1 LIB-BANK-SIZE 1- _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? _lvsc-assert
    0 _lvsc-io-byte C!
    _lvsc-io-byte 1 LIB-BANK-SIZE 1- _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? 0= _lvsc-assert

    \ Whole-bank commitment precedes format dispatch.  The same checksummed
    \ future header is CORRUPT under the old seal, then UNSUPPORTED once a
    \ newer head commits its exact whole-bank digest.
    3 _lvsc-bank-generation !
    _lvsc-build-bank
    2 _lvsc-future-sha _lvsc-bank-format!
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? _lvsc-assert
    _lvsc-reinit
    3 2 _lvsc-future-sha _lvsc-save-head
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-UNSUPPORTED = _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? _lvsc-assert

    4 _lvsc-bank-generation !
    _lvsc-build-bank
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-reinit
    4 3 _lvsc-bank-sha _lvsc-save-head LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert

    \ Fully reseal a wrong revision-1 payload.  All frame, chain, bank, and
    \ head hashes agree, so only the immutable receipt relation rejects it.
    -1 _lvsc-initial-mismatch !
    5 _lvsc-bank-generation !
    _lvsc-build-content-frames
    _lvsc-build-bank
    _lvsc-frame LIB-STORE-SECTOR-SIZE 2 * LIB-ARENA-HEADER-SIZE
        _LIBVFS-CONTENT-PATH$ _lvsc-write-at _lvsc-assert
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-vfs @ VFS-SYNC 0= _lvsc-assert
    5 4 _lvsc-bank-sha _lvsc-save-head LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? _lvsc-assert

    0 _lvsc-initial-mismatch !
    6 _lvsc-bank-generation !
    _lvsc-build-content-frames
    _lvsc-build-bank
    _lvsc-frame LIB-STORE-SECTOR-SIZE 2 * LIB-ARENA-HEADER-SIZE
        _LIBVFS-CONTENT-PATH$ _lvsc-write-at _lvsc-assert
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-reinit
    6 5 _lvsc-bank-sha _lvsc-save-head LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 6 = _lvsc-assert

    \ Whole-bank integrity cannot make crossed identity/key namespaces
    \ canonical.  The cold loader rejects both catalog-to-catalog and
    \ catalog-to-collection collisions after every record is resealed.
    7 _lvsc-bank-generation !
    _lvsc-build-catalog-cross-bank
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-vfs @ VFS-SYNC 0= _lvsc-assert
    7 6 _lvsc-bank-sha _lvsc-save-head LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? _lvsc-assert

    _lvsc-build-entry
    _lvsc-build-collection
    8 _lvsc-bank-generation !
    _lvsc-build-collection-cross-bank
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-vfs @ VFS-SYNC 0= _lvsc-assert
    _lvsc-reinit
    8 7 _lvsc-bank-sha _lvsc-save-head LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-CORRUPT = _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? _lvsc-assert

    \ Restore a canonical selected bank before the orphan evidence case.
    _lvsc-build-entry
    _lvsc-build-collection
    9 _lvsc-bank-generation !
    _lvsc-build-bank
    _lvsc-bank LIB-BANK-SIZE 0 _LIBVFS-BANK-B-PATH$
        _lvsc-write-at _lvsc-assert
    _lvsc-vfs @ VFS-SYNC 0= _lvsc-assert
    _lvsc-reinit
    9 8 _lvsc-bank-sha _lvsc-save-head LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE.GENERATION @ 9 = _lvsc-assert

    \ Exact post-bank/pre-head evidence is an orphan, never resumable
    \ pristine preparation.  LOAD preserves it and leaves the head absent.
    _LIBVFS-BANK-B-PATH$ _lvsc-before-sha _lvsc-file-sha _lvsc-assert
    _LIBVFS-HEAD-PATH$ _lvsc-vfs @ VFS-RM 0= _lvsc-assert
    _LIBVFS-HEAD-PATH$ _lvsc-vfs @ VFS-RESOLVE 0= _lvsc-assert
    _lvsc-reinit
    _lvsc-vfs @ V.FDFREE @ _lvsc-fdfree-before !
    0 _lvsc-write-calls !
    ['] _lvsc-no-write _LIBVFS-WRITE-EXACT-XT !
    _lvsc-store-a LIBRARY-VFS-STORE-LOAD
        LIBSTORE-S-RECOVERY = _lvsc-assert
    ['] VFS-WRITE-EXACT _LIBVFS-WRITE-EXACT-XT !
    _lvsc-write-calls @ 0= _lvsc-assert
    _lvsc-unpublished-contracts
    _lvsc-store-a LIBRARY-VFS-STORE-BLOCKED? _lvsc-assert
    _LIBVFS-HEAD-PATH$ _lvsc-vfs @ VFS-RESOLVE 0= _lvsc-assert
    _LIBVFS-BANK-B-PATH$ _lvsc-after-sha _lvsc-file-sha _lvsc-assert
    _lvsc-before-sha _lvsc-after-sha SHA3-256-COMPARE _lvsc-assert
    0 _lvsc-io-byte C!
    _lvsc-io-byte 1 4096 _LIBVFS-CONTENT-PATH$
        _lvsc-read-at _lvsc-assert
    _lvsc-io-byte C@ 0x6B = _lvsc-assert
    _lvsc-vfs @ V.FDFREE @ _lvsc-fdfree-before @ = _lvsc-assert
    VFS-CUR _lvsc-vfs @ = _lvsc-assert
    _LIBVP-FD @ 0= _lvsc-assert
    _lvsc-store-a LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lvsc-assert
    _lvsc-stack ;

: _lvsc-run  ( -- )
    0 _lvsc-fails ! 0 _lvsc-checks ! DEPTH _lvsc-depth !
    VFS-CUR DUP _lvsc-old-vfs ! 0= _lvsc-assert
    4194304 A-XMEM ARENA-NEW DUP 0= _lvsc-assert DROP
    DUP _lvsc-arena !
    _lvsc-link-binding-init
    _lvsc-link-binding 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lvsc-vfs ! 0<> _lvsc-assert
    _lvsc-arena @ VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lvsc-other-vfs ! 0<> _lvsc-assert
    _lvsc-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE _lvsc-store-a-slot _lvsc-allocate
    LIBRARY-VFS-STORE-SIZE _lvsc-store-b-slot _lvsc-allocate
    _lvsc-status-contracts
    _lvsc-init-contracts
    _lvsc-provision-contracts
    _lvsc-namespace-contracts
    _lvsc-nonempty-contracts
    _lvsc-store-b-slot _lvsc-free
    _lvsc-store-a-slot _lvsc-free
    _lvsc-old-vfs @ VFS-USE
    VFS-CUR _lvsc-old-vfs @ = _lvsc-assert
    _lvsc-vfs @ VFS-DESTROY
    _lvsc-stack
    _lvsc-fails @ ?DUP IF
        ." LIBRARY VFS STORE FAIL " . ." / " _lvsc-checks @ . CR
    ELSE
        ." LIBRARY VFS STORE PASS " _lvsc-checks @ . CR
    THEN ;

_lvsc-run
