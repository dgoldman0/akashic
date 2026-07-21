\ =====================================================================
\  Gate 4 milestone 5: bounded Library inspection/repair/raw export
\ =====================================================================

VARIABLE _lmc-fails
VARIABLE _lmc-checks
VARIABLE _lmc-depth
VARIABLE _lmc-old-vfs
VARIABLE _lmc-vfs
VARIABLE _lmc-arena
VARIABLE _lmc-store-slot
VARIABLE _lmc-fd
VARIABLE _lmc-data-a
VARIABLE _lmc-data-u
VARIABLE _lmc-path-a
VARIABLE _lmc-path-u
VARIABLE _lmc-object-id
VARIABLE _lmc-object
VARIABLE _lmc-report
VARIABLE _lmc-position
VARIABLE _lmc-remaining
VARIABLE _lmc-chunk
VARIABLE _lmc-expected-offset
VARIABLE _lmc-before-crc
VARIABLE _lmc-report-crc
VARIABLE _lmc-read-calls
VARIABLE _lmc-sync-calls
VARIABLE _lmc-required

CREATE _lmc-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lmc-report-a LIBRARY-INSPECTION-SIZE ALLOT
CREATE _lmc-report-b LIBRARY-INSPECTION-SIZE ALLOT
CREATE _lmc-report-c LIBRARY-INSPECTION-SIZE ALLOT
CREATE _lmc-head-original 512 ALLOT
CREATE _lmc-head-work 512 ALLOT
CREATE _lmc-future-spec CREC-SPEC-SIZE ALLOT
CREATE _lmc-future-crec-work CREC-WORK-SIZE ALLOT
CREATE _lmc-io-byte 1 ALLOT
CREATE _lmc-digest LIB-DIGEST-SIZE ALLOT
CREATE _lmc-compare-block 16384 ALLOT
LIBRARY-RAW-EXPORT-MAX XBUF _lmc-export

: _lmc-store  ( -- store ) _lmc-store-slot @ ;

: _lmc-assert  ( flag -- )
    1 _lmc-checks +!
    0= IF
        1 _lmc-fails +!
        ." LIBRARY MAINTENANCE ASSERT " _lmc-checks @ . CR
    THEN ;

: _lmc-stack  ( -- )
    DEPTH DUP _lmc-depth @ <> IF
        ." LIBRARY MAINTENANCE STACK " _lmc-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _lmc-depth @ = _lmc-assert ;

: _lmc-future-encode
  ( source-a source-u payload-a payload-u tag -- checked-status )
    DROP
    DUP 3 PICK <> IF 2DROP 2DROP CREC-S-SEMANTIC EXIT THEN
    DROP SWAP CMOVE CREC-S-OK ;

: _lmc-future-validate
  ( context-a context-u payload-a payload-u tag -- checked-status )
    2DROP 2DROP DROP CREC-S-OK ;

_LIBVFS-HEAD-RECORD-MAGIC 8 2 CREC-TAG-POSITIVE
    ' _lmc-future-encode ' _lmc-future-validate _lmc-future-spec
    CREC-SPEC-INIT IF -4915 THROW THEN
LIB-HEAD-PAYLOAD-SIZE CREC-HEADER-SIZE LIB-HEAD-PAYLOAD-SIZE +
    _lmc-future-spec CREC-SPEC-FIXED! IF -4915 THROW THEN
_lmc-future-spec CREC-SPEC-SEAL IF -4915 THROW THEN
_lmc-future-crec-work CREC-WORK-INIT IF -4915 THROW THEN

: _lmc-allocate  ( size variable -- )
    >R ALLOCATE ABORT" LIBRARY MAINTENANCE FAIL allocation" R> ! ;

: _lmc-free  ( variable -- )
    DUP @ ?DUP IF FREE 0 SWAP ! ELSE DROP THEN ;

: _lmc-zero?  ( a u -- flag )
    DUP 7 AND IF 2DROP 0 EXIT THEN
    0 ?DO DUP I + @ IF DROP 0 UNLOOP EXIT THEN 8 +LOOP
    DROP -1 ;

: _lmc-path$  ( object-id -- a u )
    CASE
        LIBRARY-EVIDENCE-HEAD OF _LIBVFS-HEAD-PATH$ ENDOF
        LIBRARY-EVIDENCE-HEAD-STAGE OF _LIBVFS-HEAD-STAGE-PATH$ ENDOF
        LIBRARY-EVIDENCE-HEAD-BACKUP OF _LIBVFS-HEAD-BACKUP-PATH$ ENDOF
        LIBRARY-EVIDENCE-HEAD-MARKER OF _LIBVFS-HEAD-MARKER-PATH$ ENDOF
        LIBRARY-EVIDENCE-BANK-A OF _LIBVFS-BANK-A-PATH$ ENDOF
        LIBRARY-EVIDENCE-BANK-B OF _LIBVFS-BANK-B-PATH$ ENDOF
        LIBRARY-EVIDENCE-CONTENT OF _LIBVFS-CONTENT-PATH$ ENDOF
    ENDCASE ;

: _lmc-present?  ( object-id -- flag )
    _lmc-path$ _lmc-vfs @ VFS-RESOLVE 0<> ;

: _lmc-put  ( data-a data-u path-a path-u -- )
    _lmc-path-u ! _lmc-path-a ! _lmc-data-u ! _lmc-data-a !
    _lmc-path-a @ _lmc-path-u @ _lmc-vfs @ VFS-RESOLVE IF
        _lmc-path-a @ _lmc-path-u @ _lmc-vfs @ VFS-RM 0= _lmc-assert
    THEN
    _lmc-path-a @ _lmc-path-u @ _lmc-vfs @ VFS-CREATE
        DUP 0<> _lmc-assert DUP 0= IF DROP EXIT THEN DROP
    _lmc-path-a @ _lmc-path-u @ VFS-OPEN DUP _lmc-fd !
        0<> _lmc-assert
    _lmc-fd @ 0= IF EXIT THEN
    _lmc-data-a @ _lmc-data-u @ _lmc-fd @ VFS-WRITE-EXACT
        0= _lmc-assert
    _lmc-fd @ VFS-CLOSE
    _lmc-vfs @ VFS-SYNC 0= _lmc-assert ;

: _lmc-read-exact  ( destination expected-u path-a path-u -- flag )
    _lmc-path-u ! _lmc-path-a ! _lmc-data-u ! _lmc-data-a !
    _lmc-path-a @ _lmc-path-u @ VFS-OPEN DUP _lmc-fd ! 0= IF 0 EXIT THEN
    _lmc-fd @ VFS-SIZE _lmc-data-u @ <> IF
        _lmc-fd @ VFS-CLOSE 0 EXIT
    THEN
    _lmc-data-a @ _lmc-data-u @ _lmc-fd @ VFS-READ-EXACT 0=
    _lmc-fd @ VFS-CLOSE ;

: _lmc-file-equal?  ( expected-a expected-u path-a path-u -- flag )
    _lmc-path-u ! _lmc-path-a ! _lmc-data-u ! _lmc-data-a !
    _lmc-path-a @ _lmc-path-u @ VFS-OPEN DUP _lmc-fd ! 0= IF 0 EXIT THEN
    _lmc-fd @ VFS-SIZE _lmc-data-u @ <> IF
        _lmc-fd @ VFS-CLOSE 0 EXIT
    THEN
    0 _lmc-position ! _lmc-data-u @ _lmc-remaining !
    BEGIN _lmc-remaining @ 0> WHILE
        _lmc-remaining @ 16384 MIN DUP _lmc-chunk !
        _lmc-compare-block SWAP _lmc-fd @ VFS-READ-EXACT IF
            _lmc-fd @ VFS-CLOSE 0 EXIT
        THEN
        _lmc-compare-block _lmc-chunk @
            _lmc-data-a @ _lmc-position @ + _lmc-chunk @ COMPARE IF
            _lmc-fd @ VFS-CLOSE 0 EXIT
        THEN
        _lmc-chunk @ _lmc-position +!
        _lmc-chunk @ NEGATE _lmc-remaining +!
    REPEAT
    _lmc-fd @ VFS-CLOSE -1 ;

: _lmc-export-object-exact?  ( object-id report -- flag )
    _lmc-report ! _lmc-object-id !
    _lmc-object-id @ _lmc-report @ LIBINS-OBJECT DUP _lmc-object !
        LIBEO.FLAGS @ LIBRARY-EVIDENCE-F-PRESENT AND 0= IF
        _lmc-object @ LIBEO.STATE @ LIBRARY-EVIDENCE-S-ABSENT =
        _lmc-object @ LIBEO.RAW-U @ 0= AND
        _lmc-object-id @ _lmc-present? 0= AND EXIT
    THEN
    _lmc-object @ LIBEO.RAW-U @ DUP 0> 0= IF DROP 0 EXIT THEN
    _lmc-export _lmc-object @ LIBEO.RAW-OFFSET @ + SWAP
        _lmc-object-id @ _lmc-path$ _lmc-file-equal? 0= IF
        0 EXIT
    THEN
    _lmc-export _lmc-object @ LIBEO.RAW-OFFSET @ +
        _lmc-object @ LIBEO.RAW-U @ _lmc-digest SHA3-256-HASH
    _lmc-digest _lmc-object @ LIBEO.SHA SHA3-256-COMPARE ;

: _lmc-export-layout-contracts  ( report -- )
    _lmc-report ! 0 _lmc-expected-offset !
    LIBRARY-EVIDENCE-OBJECT-N 0 DO
        I _lmc-report @ LIBINS-OBJECT DUP LIBEO.RAW-OFFSET @
            _lmc-expected-offset @ = _lmc-assert
        LIBEO.RAW-U @ _lmc-expected-offset +!
        I _lmc-report @ _lmc-export-object-exact? _lmc-assert
    LOOP
    _lmc-expected-offset @
        _lmc-report @ LIBINS.RAW-REQUIRED @ = _lmc-assert ;

: _lmc-semantics-zero?  ( report -- flag )
    DUP LIBINS.FLAGS @ 0=
    OVER LIBINS.REPAIR-MASK @ 0= AND
    OVER LIBINS.HEAD-GENERATION @ 0= AND
    OVER LIBINS.SELECTED-BANK @ 0= AND
    OVER LIBINS.CATALOG-COUNT @ 0= AND
    OVER LIBINS.COLLECTION-COUNT @ 0= AND
    OVER LIBINS.MUTATION-SEQUENCE @ 0= AND
    OVER LIBINS.CONTENT-TAIL @ 0= AND
    SWAP LIBINS.CONTENT-RECORD-COUNT @ 0= AND ;

: _lmc-no-read  ( destination length fd -- ior )
    DROP 2DROP 1 _lmc-read-calls +! -1 ;

: _lmc-no-sync  ( vfs -- ior )
    DROP 1 _lmc-sync-calls +! -1 ;

: _lmc-export-fault-read  ( destination length fd -- ior )
    _LIBMA-EXPORT-STARTED @ IF
        DROP 2DROP 1 _lmc-read-calls +! -1 EXIT
    THEN
    VFS-READ-EXACT ;

: _lmc-export-corrupt-read  ( destination length fd -- ior )
    _lmc-fd ! _lmc-data-u ! _lmc-data-a !
    _lmc-data-a @ _lmc-data-u @ _lmc-fd @ VFS-READ-EXACT
    DUP 0= _LIBMA-EXPORT-STARTED @ AND
        _lmc-read-calls @ 0= AND _lmc-data-u @ 0> AND IF
        _lmc-data-a @ DUP C@ 1 XOR SWAP C!
        1 _lmc-read-calls +!
    THEN ;

: _lmc-prime-export  ( u -- )
    DUP _lmc-export SWAP 0xA5 FILL
    _lmc-export SWAP CRC32 _lmc-before-crc ! ;

: _lmc-export-unchanged?  ( u -- flag )
    _lmc-export SWAP CRC32 _lmc-before-crc @ = ;

: _lmc-transaction-clean  ( -- )
    VFS-CUR _lmc-vfs @ = _lmc-assert
    _LIBVP-FD @ 0= _lmc-assert
    _LIBVP-SHA-ACTIVE @ 0= _lmc-assert
    _LIBVP-CRC-ACTIVE @ 0= _lmc-assert ;

: _lmc-healthy-contracts  ( -- )
    LIBRARY-EVIDENCE-HEAD 0= _lmc-assert
    LIBRARY-EVIDENCE-CONTENT 6 = _lmc-assert
    LIBRARY-EVIDENCE-OBJECT-N 7 = _lmc-assert
    LIBRARY-RAW-EXPORT-MAX
        512 3 * 64 + LIB-BANK-SIZE 2 * + LIB-ARENA-SIZE + =
        _lmc-assert
    _lmc-report-a LIBRARY-INSPECTION-INIT
    _lmc-report-a _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-stack
    _lmc-report-a LIBINS.HEALTH @ LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.FLAGS @
        LIBRARY-INSPECTION-F-RECOGNIZED-V1 = _lmc-assert
    _lmc-report-a LIBINS.REPAIR-MASK @ 0= _lmc-assert
    _lmc-report-a LIBINS.HEAD-GENERATION @ 1 = _lmc-assert
    _lmc-report-a LIBINS.SELECTED-BANK @ 0= _lmc-assert
    _lmc-report-a LIBINS.CATALOG-COUNT @ 0= _lmc-assert
    _lmc-report-a LIBINS.COLLECTION-COUNT @ 0= _lmc-assert
    _lmc-report-a LIBINS.MUTATION-SEQUENCE @ 0= _lmc-assert
    _lmc-report-a LIBINS.CONTENT-TAIL @
        LIB-ARENA-HEADER-SIZE = _lmc-assert
    _lmc-report-a LIBINS.CONTENT-RECORD-COUNT @ 0= _lmc-assert
    LIBRARY-EVIDENCE-HEAD _lmc-report-a LIBINS-OBJECT
        LIBEO.STATE @ LIBRARY-EVIDENCE-S-RECOGNIZED = _lmc-assert
    LIBRARY-EVIDENCE-BANK-A _lmc-report-a LIBINS-OBJECT
        LIBEO.FLAGS @ LIBRARY-EVIDENCE-F-SELECTED AND 0<> _lmc-assert

    0 0 _lmc-report-a _lmc-store LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-OUTPUT-CAPACITY = _lmc-assert
    _lmc-report-a LIBINS.RAW-REQUIRED @ = _lmc-assert
    _lmc-stack

    _lmc-report-a LIBINS.RAW-REQUIRED @ DUP _lmc-required !
        1- _lmc-prime-export
    _lmc-export _lmc-required @ 1- _lmc-report-a _lmc-store
        LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-OUTPUT-CAPACITY = _lmc-assert
    _lmc-required @ = _lmc-assert
    _lmc-required @ 1- _lmc-export-unchanged? _lmc-assert
    _lmc-stack

    _lmc-export _lmc-report-a LIBINS.RAW-REQUIRED @
        _lmc-report-a _lmc-store
        LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.RAW-REQUIRED @ = _lmc-assert
    _lmc-stack
    _lmc-report-a _lmc-export-layout-contracts
    _lmc-stack ;

: _lmc-invalid-io-contracts  ( -- )
    \ Report/store aliasing is rejected before either owner shape changes.
    _lmc-store _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-INVALID = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-VALID? _lmc-assert

    _lmc-report-b LIBRARY-INSPECTION-SIZE 0xA6 FILL
    _lmc-report-b LIBRARY-INSPECTION-SIZE CRC32 _lmc-before-crc !
    0 _lmc-read-calls !
    ['] _lmc-no-read _LIBVFS-READ-EXACT-XT !
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-IO = _lmc-assert
    ['] VFS-READ-EXACT _LIBVFS-READ-EXACT-XT !
    _lmc-read-calls @ 0> _lmc-assert
    _lmc-report-b LIBRARY-INSPECTION-SIZE CRC32
        _lmc-before-crc @ = _lmc-assert
    _lmc-transaction-clean

    _lmc-report-a LIBRARY-INSPECTION-SIZE CRC32 _lmc-before-crc !
    _lmc-report-a _lmc-report-a LIBINS.RAW-REQUIRED @
        _lmc-report-a _lmc-store LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-INVALID = _lmc-assert
    DROP
    _lmc-report-a LIBRARY-INSPECTION-SIZE CRC32
        _lmc-before-crc @ = _lmc-assert

    \ Once materialization starts, an operational failure exposes neither
    \ a prefix nor a caller-sentinel suffix: the full negotiated span zeros.
    _lmc-report-a LIBRARY-INSPECTION-SIZE CRC32 _lmc-report-crc !
    _lmc-report-a LIBINS.RAW-REQUIRED @ DUP _lmc-required !
        _lmc-prime-export
    0 _lmc-read-calls !
    ['] _lmc-export-fault-read _LIBVFS-READ-EXACT-XT !
    _lmc-export _lmc-required @ _lmc-report-a _lmc-store
        LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-IO = _lmc-assert
    _lmc-required @ = _lmc-assert
    ['] VFS-READ-EXACT _LIBVFS-READ-EXACT-XT !
    _lmc-read-calls @ 1 = _lmc-assert
    _lmc-export _lmc-required @ _lmc-zero? _lmc-assert
    _lmc-report-a LIBRARY-INSPECTION-SIZE CRC32
        _lmc-report-crc @ = _lmc-assert
    _lmc-transaction-clean

    \ A successful VFS read may still return bytes different from the
    \ inspected evidence.  Corrupt exactly one byte on the second read;
    \ export must reject the incoherent object and scrub the whole span.
    _lmc-report-a LIBRARY-INSPECTION-SIZE CRC32 _lmc-report-crc !
    _lmc-report-a LIBINS.RAW-REQUIRED @ DUP _lmc-required !
        _lmc-prime-export
    0 _lmc-read-calls !
    ['] _lmc-export-corrupt-read _LIBVFS-READ-EXACT-XT !
    _lmc-export _lmc-required @ _lmc-report-a _lmc-store
        LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-CONFLICT = _lmc-assert
    _lmc-required @ = _lmc-assert
    ['] VFS-READ-EXACT _LIBVFS-READ-EXACT-XT !
    _lmc-read-calls @ 1 = _lmc-assert
    _lmc-export _lmc-required @ _lmc-zero? _lmc-assert
    _lmc-report-a LIBRARY-INSPECTION-SIZE CRC32
        _lmc-report-crc @ = _lmc-assert
    _lmc-transaction-clean
    _lmc-stack ;

: _lmc-repair-contracts  ( -- )
    _lmc-head-original 512 _LIBVFS-HEAD-PATH$ _lmc-read-exact _lmc-assert
    _lmc-head-original 512 _LIBVFS-HEAD-STAGE-PATH$ _lmc-put
    LIBRARY-EVIDENCE-HEAD-STAGE _lmc-present? _lmc-assert

    \ A report is a sealed observation, never a best-effort export hint.
    _lmc-report-a LIBINS.RAW-REQUIRED @ DUP _lmc-prime-export
    _lmc-export OVER _lmc-report-a _lmc-store
        LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-CONFLICT = _lmc-assert
    DROP
    _lmc-export-unchanged? _lmc-assert

    _lmc-report-b LIBRARY-INSPECTION-INIT
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-b LIBINS.HEALTH @ LIBSTORE-S-RECOVERY = _lmc-assert
    _lmc-report-b LIBINS.REPAIR-MASK @
        LIBRARY-REPAIR-F-HEAD-TRANSACTION = _lmc-assert
    LIBRARY-EVIDENCE-HEAD-STAGE _lmc-report-b LIBINS-OBJECT
        LIBEO.STATE @ LIBRARY-EVIDENCE-S-RECOGNIZED = _lmc-assert

    \ An inspection I/O failure precedes VREPL mutation and leaves both the
    \ report token and recognized stage byte-for-byte intact.
    _lmc-report-b LIBRARY-INSPECTION-SIZE CRC32 _lmc-before-crc !
    0 _lmc-read-calls !
    ['] _lmc-no-read _LIBVFS-READ-EXACT-XT !
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-REPAIR
        LIBSTORE-S-IO = _lmc-assert
    ['] VFS-READ-EXACT _LIBVFS-READ-EXACT-XT !
    _lmc-read-calls @ 0> _lmc-assert
    _lmc-report-b LIBRARY-INSPECTION-SIZE CRC32
        _lmc-before-crc @ = _lmc-assert
    _lmc-head-original 512 _LIBVFS-HEAD-STAGE-PATH$
        _lmc-file-equal? _lmc-assert
    _lmc-transaction-clean

    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-REPAIR
        LIBSTORE-S-OK = _lmc-assert
    LIBRARY-EVIDENCE-HEAD-STAGE _lmc-present? 0= _lmc-assert
    _lmc-report-b LIBINS.REPAIRED-SEAL RID-PRESENT? _lmc-assert

    \ The completed token is not an OK receipt until a fresh durability
    \ barrier succeeds.  A failed barrier blocks the descriptor without
    \ rewriting the caller's token or exposing false success.
    _lmc-report-b LIBRARY-INSPECTION-SIZE CRC32 _lmc-before-crc !
    0 _lmc-sync-calls !
    ['] _lmc-no-sync _LIBVFS-SYNC-XT !
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-REPAIR
        LIBSTORE-S-IO = _lmc-assert
    ['] VFS-SYNC _LIBVFS-SYNC-XT !
    _lmc-sync-calls @ 1 = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-BLOCKED? _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-LAST-STATUS@
        LIBSTORE-S-IO = _lmc-assert
    _lmc-report-b LIBRARY-INSPECTION-SIZE CRC32
        _lmc-before-crc @ = _lmc-assert
    _lmc-transaction-clean

    \ Retrying that same completed token after the barrier is available
    \ reopens and reloads the owner before publishing OK.
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-REPAIR
        LIBSTORE-S-OK = _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-LOADED? _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-BLOCKED? 0= _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-PROVISIONED? _lmc-assert
    _lmc-store LIBRARY-VFS-STORE-LAST-STATUS@
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-b LIBRARY-INSPECTION-SIZE CRC32
        _lmc-before-crc @ = _lmc-assert
    _lmc-transaction-clean

    _lmc-report-c LIBRARY-INSPECTION-INIT
    _lmc-report-c _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-c LIBINS.HEALTH @ LIBSTORE-S-OK = _lmc-assert
    _lmc-report-b LIBINS.REPAIRED-SEAL
        _lmc-report-c LIBINS.EVIDENCE-SEAL SHA3-256-COMPARE _lmc-assert
    _lmc-stack ;

: _lmc-future-contracts  ( -- )
    _lmc-head-original CREC-HEADER-SIZE + LIB-HEAD-PAYLOAD-SIZE
        LIB-HEAD-PAYLOAD-SIZE
        _lmc-head-original CREC-H-TAG + @
        _lmc-head-work 512 _lmc-future-spec _lmc-future-crec-work
        CREC-ENCODE
    CREC-S-OK = _lmc-assert
    512 = _lmc-assert
    _lmc-head-work 512 _LIBVFS-HEAD-PATH$ _lmc-put

    _lmc-report-a LIBRARY-INSPECTION-INIT
    _lmc-report-a _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.HEALTH @ LIBSTORE-S-UNSUPPORTED = _lmc-assert
    _lmc-report-a _lmc-semantics-zero? _lmc-assert
    LIBRARY-EVIDENCE-HEAD _lmc-report-a LIBINS-OBJECT DUP
        LIBEO.STATE @ LIBRARY-EVIDENCE-S-FUTURE = _lmc-assert
    DUP LIBEO.FLAGS @ LIBRARY-EVIDENCE-F-OPAQUE AND 0<> _lmc-assert
    LIBEO.ENVELOPE-FORMAT @ 2 = _lmc-assert

    _lmc-export _lmc-report-a LIBINS.RAW-REQUIRED @
        _lmc-report-a _lmc-store
        LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.RAW-REQUIRED @ = _lmc-assert
    _lmc-report-a _lmc-export-layout-contracts
    _lmc-report-a _lmc-store LIBRARY-VFS-STORE-REPAIR
        LIBSTORE-S-UNSUPPORTED = _lmc-assert
    _lmc-head-work 512 _LIBVFS-HEAD-PATH$ _lmc-file-equal? _lmc-assert
    _lmc-report-b LIBRARY-INSPECTION-INIT
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-b LIBINS.HEALTH @ LIBSTORE-S-UNSUPPORTED = _lmc-assert
    _lmc-report-a LIBINS.EVIDENCE-SEAL
        _lmc-report-b LIBINS.EVIDENCE-SEAL SHA3-256-COMPARE _lmc-assert
    _lmc-head-original 512 _LIBVFS-HEAD-PATH$ _lmc-put
    _lmc-stack ;

: _lmc-corrupt-contracts  ( -- )
    _lmc-head-original _lmc-head-work 512 CMOVE
    1 _lmc-head-work CREC-H-HEADER-CRC + +!
    _lmc-head-work 512 _LIBVFS-HEAD-PATH$ _lmc-put

    _lmc-report-a LIBRARY-INSPECTION-INIT
    _lmc-report-a _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.HEALTH @ LIBSTORE-S-CORRUPT = _lmc-assert
    _lmc-report-a _lmc-semantics-zero? _lmc-assert
    LIBRARY-EVIDENCE-HEAD _lmc-report-a LIBINS-OBJECT DUP
        LIBEO.STATE @ LIBRARY-EVIDENCE-S-CORRUPT = _lmc-assert
    LIBEO.FLAGS @ LIBRARY-EVIDENCE-F-OPAQUE AND 0<> _lmc-assert
    _lmc-export _lmc-report-a LIBINS.RAW-REQUIRED @
        _lmc-report-a _lmc-store
        LIBRARY-VFS-STORE-RAW-EXPORT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.RAW-REQUIRED @ = _lmc-assert
    _lmc-report-a _lmc-export-layout-contracts
    _lmc-report-a _lmc-store LIBRARY-VFS-STORE-REPAIR
        LIBSTORE-S-CORRUPT = _lmc-assert
    _lmc-head-work 512 _LIBVFS-HEAD-PATH$ _lmc-file-equal? _lmc-assert
    _lmc-report-b LIBRARY-INSPECTION-INIT
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-b LIBINS.HEALTH @ LIBSTORE-S-CORRUPT = _lmc-assert
    _lmc-report-a LIBINS.EVIDENCE-SEAL
        _lmc-report-b LIBINS.EVIDENCE-SEAL SHA3-256-COMPARE _lmc-assert
    _lmc-head-original 512 _LIBVFS-HEAD-PATH$ _lmc-put
    _lmc-stack ;

: _lmc-orphan-contracts  ( -- )
    \ A fully written content suffix without a commit head is retained raw
    \ evidence.  Maintenance neither adopts it nor guesses a replacement.
    0x6B _lmc-io-byte C!
    _LIBVFS-CONTENT-PATH$ VFS-OPEN DUP _lmc-fd ! 0<> _lmc-assert
    4096 _lmc-fd @ VFS-SEEK
    _lmc-io-byte 1 _lmc-fd @ VFS-WRITE-EXACT 0= _lmc-assert
    _lmc-fd @ VFS-CLOSE
    _lmc-vfs @ VFS-SYNC 0= _lmc-assert
    _LIBVFS-HEAD-PATH$ _lmc-vfs @ VFS-RM 0= _lmc-assert

    _lmc-report-a LIBRARY-INSPECTION-INIT
    _lmc-report-a _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.HEALTH @ LIBSTORE-S-RECOVERY = _lmc-assert
    _lmc-report-a LIBINS.REPAIR-MASK @ 0= _lmc-assert
    _lmc-report-a _lmc-store LIBRARY-VFS-STORE-REPAIR
        LIBSTORE-S-RECOVERY = _lmc-assert
    LIBRARY-EVIDENCE-HEAD _lmc-present? 0= _lmc-assert
    _lmc-report-b LIBRARY-INSPECTION-INIT
    _lmc-report-b _lmc-store LIBRARY-VFS-STORE-INSPECT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-report-a LIBINS.EVIDENCE-SEAL
        _lmc-report-b LIBINS.EVIDENCE-SEAL SHA3-256-COMPARE _lmc-assert
    _LIBVFS-CONTENT-PATH$ VFS-OPEN DUP _lmc-fd ! 0<> _lmc-assert
    4096 _lmc-fd @ VFS-SEEK
    0 _lmc-io-byte C!
    _lmc-io-byte 1 _lmc-fd @ VFS-READ-EXACT 0= _lmc-assert
    _lmc-fd @ VFS-CLOSE
    _lmc-io-byte C@ 0x6B = _lmc-assert
    _lmc-stack ;

: _lmc-run  ( -- )
    0 _lmc-fails ! 0 _lmc-checks ! DEPTH _lmc-depth !
    VFS-CUR DUP _lmc-old-vfs ! 0= _lmc-assert
    4194304 A-XMEM ARENA-NEW DUP 0= _lmc-assert DROP
        DUP _lmc-arena !
    VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lmc-vfs ! 0<> _lmc-assert
    _lmc-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE _lmc-store-slot _lmc-allocate
    _lmc-arena-id LIB-DIGEST-SIZE 0 FILL 0x51 _lmc-arena-id C!
    _lmc-vfs @ _lmc-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmc-assert
    _lmc-arena-id _lmc-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lmc-assert
    _lmc-healthy-contracts
    _lmc-invalid-io-contracts
    _lmc-repair-contracts
    _lmc-future-contracts
    _lmc-corrupt-contracts
    _lmc-orphan-contracts
    _lmc-store LIBRARY-VFS-STORE-FINI LIBSTORE-S-OK = _lmc-assert
    _lmc-store-slot _lmc-free
    _lmc-old-vfs @ VFS-USE
    _lmc-vfs @ VFS-DESTROY
    _lmc-stack
    _lmc-fails @ ?DUP IF
        ." LIBRARY MAINTENANCE FAIL " . ." / " _lmc-checks @ . CR
    ELSE
        ." LIBRARY MAINTENANCE PASS " _lmc-checks @ . CR
    THEN ;

_lmc-run
