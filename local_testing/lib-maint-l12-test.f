\ Sealed maintenance-evidence contracts for the current Library repository.

PROVIDED akashic-library-maintenance-l12-contracts

4194304 CONSTANT _LM12-RAW-CAPACITY

VARIABLE _LM12-fails
VARIABLE _LM12-checks
VARIABLE _LM12-depth
VARIABLE _LM12-arena
VARIABLE _LM12-vfs
VARIABLE _LM12-ior
VARIABLE _LM12-old-vfs
VARIABLE _LM12-cwd
VARIABLE _LM12-fault-at
VARIABLE _LM12-fd
VARIABLE _LM12-data-a
VARIABLE _LM12-data-u
VARIABLE _LM12-path-a
VARIABLE _LM12-path-u
VARIABLE _LM12-ok
VARIABLE _LM12-byte
VARIABLE _LM12-report
VARIABLE _LM12-object
VARIABLE _LM12-offset
VARIABLE _LM12-present-n
VARIABLE _LM12-absent-n
VARIABLE _LM12-required
VARIABLE _LM12-before-crc

VARIABLE _LM12-old-read-xt
VARIABLE _LM12-read-mode
VARIABLE _LM12-read-calls
VARIABLE _LM12-raw-read-calls
VARIABLE _LM12-read-corrupted
VARIABLE _LM12-read-buffer
VARIABLE _LM12-read-length
VARIABLE _LM12-read-offset
VARIABLE _LM12-read-inode
VARIABLE _LM12-read-vfs
VARIABLE _LM12-read-actual
VARIABLE _LM12-read-ior

VARIABLE _LM12-old-release-xt
VARIABLE _LM12-release-calls
VARIABLE _LM12-release-fail-at

CREATE _LM12-ops VFS-OPS-SIZE ALLOT
CREATE _LM12-binding VFS-BINDING-DESC-SIZE ALLOT

CREATE _LM12-cache-0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LM12-cache-1 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LM12-builder-cache-0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LM12-builder-cache-1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LM12-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LM12-cache-1-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LM12-builder-cache-0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LM12-builder-cache-1-memory
GUARD _LM12-guard
GUARD _LM12-builder-guard

LIBRARY-REPOSITORY-SIZE XBUF _LM12-repository
LIBRARY-REPOSITORY-WORK-SIZE XBUF _LM12-work
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LM12-record
LIBRARY-REPOSITORY-STAGE-BUFFER-MIN XBUF _LM12-stage
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LM12-builder-record
512 XBUF _LM12-compact-buffer
8192 CONSTANT _LM12-audit-map-capacity
_LM12-audit-map-capacity XBUF _LM12-audit-map
_LM12-audit-map-capacity XBUF _LM12-builder-audit-map

CREATE _LM12-bootstrap RID-SIZE ALLOT
LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LM12-report-a
LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LM12-report-b
LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LM12-report-c
LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LM12-report-d
CREATE _LM12-repaired-seal SHA3-256-LEN ALLOT
CREATE _LM12-digest SHA3-256-LEN ALLOT
CREATE _LM12-root-0-original PROOT-RECORD-SIZE ALLOT
CREATE _LM12-root-1-original PROOT-RECORD-SIZE ALLOT
CREATE _LM12-root-0-work PROOT-RECORD-SIZE ALLOT
CREATE _LM12-root-1-work PROOT-RECORD-SIZE ALLOT
_LM12-RAW-CAPACITY XBUF _LM12-raw

: _LM12-assert  ( flag -- )
    1 _LM12-checks +!
    0= IF
        1 _LM12-fails +!
        ." LIBRARY MAINTENANCE L12 ASSERT " _LM12-checks @ . CR
    THEN ;

: _LM12-stack  ( -- )
    DEPTH DUP _LM12-depth @ <> IF
        ." LIBRARY MAINTENANCE L12 STACK "
        _LM12-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LM12-depth @ = _LM12-assert ;

: _LM12-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY MAINTENANCE L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LM12-assert _LM12-stack ;

: _LM12-fault  ( point ordinal context -- status )
    2DROP _LM12-fault-at @ =
    IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN ;

: _LM12-filled?  ( address length byte -- flag )
    _LM12-byte !
    0 ?DO
        DUP I + C@ _LM12-byte @ <> IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _LM12-zero?  ( address length -- flag )
    0 ?DO
        DUP I + C@ IF DROP 0 UNLOOP EXIT THEN
    LOOP
    DROP -1 ;

: _LM12-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _LM12-status ;

: _LM12-file-present?  ( path-a path-u -- flag )
    _LM12-vfs @ VFS-RESOLVE?
    DUP IF 2DROP 0 EXIT THEN
    DROP 0<> ;

: _LM12-read-file  ( destination expected-u path-a path-u -- flag )
    _LM12-path-u ! _LM12-path-a !
    _LM12-data-u ! _LM12-data-a !
    _LM12-path-a @ _LM12-path-u @ VFS-FF-READ
        _LM12-vfs @ VFS-OPEN?
    _LM12-ior ! _LM12-fd !
    _LM12-ior @ IF 0 EXIT THEN
    _LM12-fd @ 0= IF 0 EXIT THEN
    _LM12-fd @ VFS-SIZE _LM12-data-u @ <> IF
        _LM12-fd @ VFS-CLOSE? DROP 0 EXIT
    THEN
    _LM12-data-a @ _LM12-data-u @ _LM12-fd @
        VFS-READ-EXACT 0=
    _LM12-fd @ VFS-CLOSE? 0= AND ;

: _LM12-put-file  ( source-a source-u path-a path-u -- )
    _LM12-path-u ! _LM12-path-a !
    _LM12-data-u ! _LM12-data-a !
    _LM12-path-a @ _LM12-path-u @ _LM12-file-present? IF
        _LM12-path-a @ _LM12-path-u @ _LM12-vfs @ VFS-RM
            0= _LM12-assert
    THEN
    _LM12-path-a @ _LM12-path-u @ _LM12-vfs @ VFS-CREATE
        DUP 0<> _LM12-assert
    DUP 0= IF DROP EXIT THEN DROP
    _LM12-path-a @ _LM12-path-u @
        VFS-FF-READ VFS-FF-WRITE OR _LM12-vfs @ VFS-OPEN?
    _LM12-ior ! _LM12-fd !
    _LM12-ior @ 0= _LM12-assert
    _LM12-fd @ 0<> _LM12-assert
    _LM12-fd @ 0= IF EXIT THEN
    _LM12-data-a @ _LM12-data-u @ _LM12-fd @ VFS-WRITE-EXACT
        0= _LM12-assert
    _LM12-fd @ VFS-CLOSE? 0= _LM12-assert
    _LM12-vfs @ VFS-SYNC 0= _LM12-assert ;

: _LM12-remove-file  ( path-a path-u -- )
    _LM12-vfs @ VFS-RM 0= _LM12-assert ;

: _LM12-raw-address?  ( address -- flag )
    DUP _LM12-raw U< 0=
    SWAP _LM12-raw _LM12-RAW-CAPACITY + U< AND ;

: _LM12-read-wrapper
  ( buffer length offset inode vfs -- actual ior )
    _LM12-read-vfs ! _LM12-read-inode ! _LM12-read-offset !
    _LM12-read-length ! _LM12-read-buffer !
    1 _LM12-read-calls +!
    \ Mode 3 fails the first evidence read itself.  This exercises the
    \ inspection commit boundary rather than the later export stream.
    _LM12-read-mode @ 3 = IF
        0 VFS-E-IO EXIT
    THEN
    _LM12-read-mode @ 2 =
    _LM12-read-buffer @ _LM12-raw-address? AND IF
        1 _LM12-raw-read-calls +!
        _LM12-raw-read-calls @ 2 = IF
            0 VFS-E-IO EXIT
        THEN
    THEN
    _LM12-read-buffer @ _LM12-read-length @ _LM12-read-offset @
    _LM12-read-inode @ _LM12-read-vfs @
        _LM12-old-read-xt @ EXECUTE
    _LM12-read-ior ! _LM12-read-actual !
    _LM12-read-mode @ 1 =
    _LM12-read-corrupted @ 0= AND
    _LM12-read-ior @ 0= AND
    _LM12-read-actual @ 0> AND IF
        _LM12-read-buffer @ DUP C@ 1 XOR SWAP C!
        -1 _LM12-read-corrupted !
    THEN
    _LM12-read-actual @ _LM12-read-ior @ ;

: _LM12-read-arm  ( mode -- )
    _LM12-read-mode !
    0 _LM12-read-calls !
    0 _LM12-raw-read-calls !
    0 _LM12-read-corrupted !
    ['] _LM12-read-wrapper _LM12-ops VFS-OP-READ CELLS + ! ;

: _LM12-read-restore  ( -- )
    _LM12-old-read-xt @ _LM12-ops VFS-OP-READ CELLS + !
    0 _LM12-read-mode ! ;

: _LM12-release-wrapper  ( cookie inode vfs -- ior )
    1 _LM12-release-calls +!
    _LM12-old-release-xt @ EXECUTE
    DUP IF EXIT THEN
    _LM12-release-calls @ _LM12-release-fail-at @ = IF
        DROP VFS-E-IO
    THEN ;

: _LM12-release-arm  ( fail-at -- )
    _LM12-release-fail-at !
    0 _LM12-release-calls !
    ['] _LM12-release-wrapper
        _LM12-ops VFS-OP-RELEASE CELLS + ! ;

: _LM12-release-restore  ( -- )
    _LM12-old-release-xt @
        _LM12-ops VFS-OP-RELEASE CELLS + ! ;

: _LM12-prime-raw  ( length -- )
    DUP _LM12-required !
    _LM12-raw SWAP 0xA5 FILL
    _LM12-raw _LM12-required @ CRC32 _LM12-before-crc ! ;

: _LM12-raw-unchanged?  ( length -- flag )
    _LM12-raw SWAP CRC32 _LM12-before-crc @ = ;

: _LM12-prime-seal  ( -- )
    _LM12-repaired-seal SHA3-256-LEN 0xA7 FILL ;

: _LM12-seal-pristine?  ( -- flag )
    _LM12-repaired-seal SHA3-256-LEN 0xA7 _LM12-filled? ;

: _LM12-present-count  ( report -- count )
    0 SWAP
    LIBRARY-REPOSITORY-EVIDENCE-COUNT 0 ?DO
        I OVER LRI.OBJECT LRIO.PRESENT @ IF
            SWAP 1+ SWAP
        THEN
    LOOP
    DROP ;

: _LM12-layout?  ( report -- flag )
    _LM12-report !
    0 _LM12-offset !
    0 _LM12-present-n !
    0 _LM12-absent-n !
    -1 _LM12-ok !
    LIBRARY-REPOSITORY-EVIDENCE-COUNT 0 ?DO
        I _LM12-report @ LRI.OBJECT DUP _LM12-object !
        LRIO.PRESENT @ IF
            1 _LM12-present-n +!
        ELSE
            1 _LM12-absent-n +!
        THEN
        I _LIBREPO-EVIDENCE-PATH$ IF
            _LM12-file-present?
        ELSE
            2DROP 0
        THEN
        _LM12-object @ LRIO.PRESENT @ 0<> <> IF
            0 _LM12-ok !
        THEN
        _LM12-object @ LRIO.BYTES @ DUP 0< IF
            DROP 0 _LM12-ok !
        ELSE
            _LM12-raw _LM12-offset @ + OVER
                _LM12-digest SHA3-256-HASH
            _LM12-digest _LM12-object @ LRIO.DIGEST
                SHA3-256-COMPARE 0= IF 0 _LM12-ok ! THEN
            _LM12-offset +!
        THEN
    LOOP
    _LM12-offset @ _LM12-report @ LRI.RAW-REQUIRED @ <>
        IF 0 _LM12-ok ! THEN
    _LM12-present-n @ _LM12-absent-n @ +
        LIBRARY-REPOSITORY-EVIDENCE-COUNT <>
        IF 0 _LM12-ok ! THEN
    _LM12-ok @ ;

: _LM12-clean?  ( -- flag )
    _LM12-work _LRW.BUSY @ 0=
    _LM12-work _LRW.FD @ 0= AND
    _LM12-work _LRW.ROOT _PROOT-W.FD @ 0= AND
    _LM12-repository _LR.GUARD @ GUARD-HELD? 0= AND
    _LM12-vfs @ V.OPEN-COUNT @ 0= AND ;

: _LM12-runtime-init  ( -- )
    VFS-CUR _LM12-old-vfs !
    VFS-RAM-OPS _LM12-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _LM12-binding VFS-BINDING-DESC-SIZE MOVE
    _LM12-ops _LM12-binding VB.OPS !
    _LM12-ops VFS-OP-READ CELLS + @ _LM12-old-read-xt !
    _LM12-ops VFS-OP-RELEASE CELLS + @ _LM12-old-release-xt !
    67108864 A-XMEM ARENA-NEW
        DUP 0= _LM12-assert DROP _LM12-arena !
    _LM12-arena @ _LM12-binding 0 VFS-NEW
        _LM12-ior ! _LM12-vfs !
    _LM12-ior @ 0= _LM12-assert
    _LM12-vfs @ 0<> _LM12-assert
    _LM12-cache-0-memory _LM12-cache-0 _LM12-cache-init
    _LM12-cache-1-memory _LM12-cache-1 _LM12-cache-init
    _LM12-builder-cache-0-memory
        _LM12-builder-cache-0 _LM12-cache-init
    _LM12-builder-cache-1-memory
        _LM12-builder-cache-1 _LM12-cache-init
    S" maintenance-cwd" _LM12-vfs @ VFS-MKDIR 0= _LM12-assert
    S" /maintenance-cwd" _LM12-vfs @ VFS-RESOLVE?
    DUP 0= _LM12-assert DROP
    DUP 0<> _LM12-assert
    DUP _LM12-cwd !
    _LM12-vfs @ V.CWD !
    _LM12-bootstrap RID-SIZE 0x4D FILL
    0 _LM12-fault-at !
    _LM12-stack ;

: _LM12-repository-init  ( -- )
    _LM12-vfs @
    _LM12-cache-0 _LM12-cache-1
    _LM12-builder-cache-0 _LM12-builder-cache-1
    _LM12-guard _LM12-builder-guard
    ['] _LM12-fault 0 _LM12-repository
    LIBRARY-REPOSITORY-INIT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-record LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LM12-stage LIBRARY-REPOSITORY-STAGE-BUFFER-MIN
    _LM12-builder-record LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LM12-compact-buffer 512
    _LM12-audit-map _LM12-audit-map-capacity
    _LM12-builder-audit-map _LM12-audit-map-capacity
    _LM12-repository _LM12-work LIBRARY-REPOSITORY-WORK-INIT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-repository LIBRARY-REPOSITORY-VALID? _LM12-assert
    _LM12-work LIBRARY-REPOSITORY-WORK-VALID? _LM12-assert
    _LM12-stack ;

: _LM12-provision-and-bootstrap  ( -- )
    _LM12-repository _LM12-work LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-ABSENT _LM12-status
    _LM12-repository _LM12-work LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-OK _LM12-status

    \ Provisioning has four present empty data files and no authority.
    _LM12-report-a _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-a LIBRARY-REPOSITORY-INSPECTION-SEALED?
        _LM12-assert
    _LM12-report-a LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-ABSENT = _LM12-assert
    _LM12-raw _LM12-RAW-CAPACITY _LM12-report-a
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-report-a LRI.RAW-REQUIRED @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-a _LM12-layout? _LM12-assert
    _LM12-present-n @ 4 = _LM12-assert
    _LM12-absent-n @ 4 = _LM12-assert
    _LM12-prime-seal
    _LM12-report-a _LM12-repaired-seal
        _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-CONFLICT _LM12-status
    _LM12-seal-pristine? _LM12-assert

    _LM12-bootstrap _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-BOOTSTRAP
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-a _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-a LIBRARY-REPOSITORY-INSPECTION-SEALED?
        _LM12-assert
    _LM12-report-a LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-FALLBACK = _LM12-assert
    _LM12-report-a LRI.REPAIR-MASK @
        LIBRARY-REPOSITORY-REPAIR-MIRROR = _LM12-assert
    _LM12-report-a _LM12-present-count 5 = _LM12-assert
    _LM12-report-a LRI.RAW-REQUIRED @
        _LM12-RAW-CAPACITY <= _LM12-assert
    _LM12-raw _LM12-RAW-CAPACITY _LM12-report-a
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-report-a LRI.RAW-REQUIRED @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-a _LM12-layout? _LM12-assert
    _LM12-present-n @ 5 = _LM12-assert
    _LM12-absent-n @ 3 = _LM12-assert
    _LM12-stack ;

: _LM12-repair-and-stale  ( -- )
    _LM12-prime-seal
    _LM12-report-a _LM12-repaired-seal
        _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-b _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-b LIBRARY-REPOSITORY-INSPECTION-SEALED?
        _LM12-assert
    _LM12-report-b LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-OK = _LM12-assert
    _LM12-report-b LRI.REPAIR-MASK @ 0= _LM12-assert
    _LM12-repaired-seal _LM12-report-b LRI.SEAL
        SHA3-256-COMPARE _LM12-assert
    _LM12-report-b _LM12-present-count 6 = _LM12-assert

    \ An old sealed observation cannot authorize either operation.
    _LM12-report-a LRI.RAW-REQUIRED @ DUP _LM12-prime-raw
    _LM12-raw SWAP _LM12-report-a
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-report-a LRI.RAW-REQUIRED @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-CONFLICT _LM12-status
    _LM12-required @ _LM12-raw-unchanged? _LM12-assert
    _LM12-prime-seal
    _LM12-report-a _LM12-repaired-seal
        _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-CONFLICT _LM12-status
    _LM12-seal-pristine? _LM12-assert
    _LM12-stack ;

: _LM12-sink-contracts  ( -- )
    _LM12-repository _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-INVALID _LM12-status
    _LM12-work _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-INVALID _LM12-status

    _LM12-report-b LRI.RAW-REQUIRED @ DUP 0> _LM12-assert
    1- DUP _LM12-prime-raw
    _LM12-raw SWAP _LM12-report-b
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-report-b LRI.RAW-REQUIRED @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-CAPACITY _LM12-status
    _LM12-required @ _LM12-raw-unchanged? _LM12-assert

    0 _LM12-report-b LRI.RAW-REQUIRED @ _LM12-report-b
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R 0= _LM12-assert
    R> LIBRARY-REPOSITORY-S-INVALID _LM12-status

    _LM12-report-b LIBRARY-REPOSITORY-INSPECTION-SIZE CRC32
        _LM12-before-crc !
    _LM12-report-b _LM12-report-b LRI.RAW-REQUIRED @ _LM12-report-b
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R 0= _LM12-assert
    R> LIBRARY-REPOSITORY-S-INVALID _LM12-status
    _LM12-report-b LIBRARY-REPOSITORY-INSPECTION-SIZE CRC32
        _LM12-before-crc @ = _LM12-assert

    _LM12-work _LM12-report-b LRI.RAW-REQUIRED @ _LM12-report-b
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R 0= _LM12-assert
    R> LIBRARY-REPOSITORY-S-INVALID _LM12-status

    _LM12-report-b LIBRARY-REPOSITORY-INSPECTION-SIZE CRC32
        _LM12-before-crc !
    _LM12-report-b _LM12-report-b
        _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-INVALID _LM12-status
    _LM12-report-b LIBRARY-REPOSITORY-INSPECTION-SIZE CRC32
        _LM12-before-crc @ = _LM12-assert
    _LM12-stack ;

: _LM12-second-read-and-stream-faults  ( -- )
    \ A failed inspection never exposes the partially initialized scratch
    \ report to its caller.
    _LM12-report-d LIBRARY-REPOSITORY-INSPECTION-SIZE 0xA6 FILL
    _LM12-report-d LIBRARY-REPOSITORY-INSPECTION-SIZE CRC32
        _LM12-before-crc !
    3 _LM12-read-arm
    _LM12-report-d _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-IO _LM12-status
    _LM12-read-restore
    _LM12-read-calls @ 1 = _LM12-assert
    _LM12-report-d LIBRARY-REPOSITORY-INSPECTION-SIZE CRC32
        _LM12-before-crc @ = _LM12-assert
    _LM12-clean? _LM12-assert

    \ Corrupt one byte only in the coherent reinspection.  No export byte
    \ may be committed when that second observation has a different seal.
    _LM12-report-b LRI.RAW-REQUIRED @ DUP _LM12-prime-raw
    1 _LM12-read-arm
    _LM12-raw SWAP _LM12-report-b
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-report-b LRI.RAW-REQUIRED @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-CONFLICT _LM12-status
    _LM12-read-restore
    _LM12-read-corrupted @ _LM12-assert
    _LM12-raw-read-calls @ 0= _LM12-assert
    _LM12-required @ _LM12-raw-unchanged? _LM12-assert
    _LM12-clean? _LM12-assert

    \ Fail the second destination read after materialization starts.
    _LM12-report-b LRI.RAW-REQUIRED @ DUP _LM12-prime-raw
    2 _LM12-read-arm
    _LM12-raw SWAP _LM12-report-b
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-report-b LRI.RAW-REQUIRED @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-IO _LM12-status
    _LM12-read-restore
    _LM12-raw-read-calls @ 2 = _LM12-assert
    _LM12-raw _LM12-required @ _LM12-zero? _LM12-assert
    _LM12-clean? _LM12-assert
    _LM12-stack ;

: _LM12-uncertain-contracts  ( -- )
    _LM12-report-b _LM12-present-count 1+
        _LM12-release-arm
    _LM12-report-c _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-release-restore
    _LM12-report-c LIBRARY-REPOSITORY-INSPECTION-SEALED?
        _LM12-assert
    _LM12-report-c LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-UNCERTAIN = _LM12-assert
    _LM12-report-c LRI.REPAIR-MASK @ 0= _LM12-assert

    \ Diagnostic raw evidence remains available when the same uncertainty
    \ is reproduced by the guarded reinspection.
    _LM12-report-c LRI.RAW-REQUIRED @ DUP _LM12-prime-raw
    _LM12-report-b _LM12-present-count 1+ _LM12-release-arm
    _LM12-raw SWAP _LM12-report-c
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-report-c LRI.RAW-REQUIRED @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-release-restore
    _LM12-report-c _LM12-layout? _LM12-assert

    _LM12-prime-seal
    _LM12-report-b _LM12-present-count 1+ _LM12-release-arm
    _LM12-report-c _LM12-repaired-seal
        _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-CONFLICT _LM12-status
    _LM12-release-restore
    _LM12-seal-pristine? _LM12-assert
    _LM12-clean? _LM12-assert
    _LM12-stack ;

: _LM12-copy-future  ( source destination -- )
    >R
    DUP R@ PROOT-RECORD-SIZE MOVE
    DROP
    _PROOT-RECORD-FORMAT 1+ R@ CREC-H-FORMAT + !
    R@ _CREC-HEADER-CRC R@ CREC-H-HEADER-CRC + !
    R> DROP ;

: _LM12-copy-corrupt  ( source destination -- )
    >R
    DUP R@ PROOT-RECORD-SIZE MOVE
    DROP
    R@ CREC-H-HEADER-CRC + DUP @ 1 XOR SWAP !
    R> DROP ;

: _LM12-save-roots  ( -- )
    _LM12-root-0-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-0$ _LM12-read-file _LM12-assert
    _LM12-root-1-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _LM12-read-file _LM12-assert ;

: _LM12-restore-roots  ( -- )
    _LM12-root-0-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-0$ _LM12-put-file
    _LM12-root-1-original PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _LM12-put-file ;

: _LM12-raw-current-report  ( report -- )
    DUP LRI.RAW-REQUIRED @ DUP _LM12-prime-raw
    _LM12-raw SWAP ROT
        _LM12-repository _LM12-work LIBRARY-REPOSITORY-RAW-EXPORT
    >R
    _LM12-required @ = _LM12-assert
    R> LIBRARY-REPOSITORY-S-OK _LM12-status ;

: _LM12-refuse-repair  ( report -- )
    _LM12-prime-seal
    _LM12-repaired-seal _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-CONFLICT _LM12-status
    _LM12-seal-pristine? _LM12-assert ;

: _LM12-future-and-corrupt  ( -- )
    _LM12-save-roots
    _LM12-root-1-original _LM12-root-1-work _LM12-copy-future
    \ A future peer beside a valid current root must not be mistaken for an
    \ ordinary fallback and overwritten by mirror repair.
    _LM12-root-1-work PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _LM12-put-file
    _LM12-report-d _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-d LIBRARY-REPOSITORY-INSPECTION-SEALED?
        _LM12-assert
    _LM12-report-d LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-FUTURE = _LM12-assert
    _LM12-report-d _LM12-raw-current-report
    _LM12-report-d _LM12-layout? _LM12-assert
    _LM12-report-d _LM12-refuse-repair
    _LM12-restore-roots

    _LM12-root-0-original _LM12-root-0-work _LM12-copy-corrupt
    _LM12-root-1-original _LM12-root-1-work _LM12-copy-corrupt
    _LM12-root-0-work PROOT-RECORD-SIZE
        _LIBREPO-ROOT-0$ _LM12-put-file
    _LM12-root-1-work PROOT-RECORD-SIZE
        _LIBREPO-ROOT-1$ _LM12-put-file
    _LM12-report-c _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-c LIBRARY-REPOSITORY-INSPECTION-SEALED?
        _LM12-assert
    _LM12-report-c LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-CORRUPT = _LM12-assert
    _LM12-report-c _LM12-raw-current-report
    _LM12-report-c _LM12-layout? _LM12-assert
    _LM12-report-c _LM12-refuse-repair
    _LM12-restore-roots

    _LM12-report-b _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-b LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-OK = _LM12-assert
    _LM12-clean? _LM12-assert
    _LM12-stack ;

: _LM12-faulted-repair-cleanup  ( -- )
    _LIBREPO-ROOT-1$ _LM12-remove-file
    _LM12-report-a _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-a LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-FALLBACK = _LM12-assert
    _LM12-prime-seal
    PERSIST-FAULT-ROOT-SYNCED _LM12-fault-at !
    _LM12-report-a _LM12-repaired-seal
        _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-FAULT _LM12-status
    0 _LM12-fault-at !
    _LM12-seal-pristine? _LM12-assert
    _LM12-clean? _LM12-assert

    \ The synced mirror may already be durable, but the old authorization is
    \ stale either way.  Fresh inspection settles the prototype state.
    _LM12-report-b _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LM12-status
    _LM12-report-b LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-OK = _LM12-assert
    _LM12-report-b LIBRARY-REPOSITORY-INSPECTION-SEALED?
        _LM12-assert
    _LM12-report-a _LM12-repaired-seal
        _LM12-repository _LM12-work
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-CONFLICT _LM12-status
    _LM12-seal-pristine? _LM12-assert
    _LM12-clean? _LM12-assert
    _LM12-stack ;

: _LM12-finish  ( -- )
    _LM12-read-restore
    _LM12-release-restore
    _LM12-repository _LM12-work LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK _LM12-status
    DEPTH 0= _LM12-assert
    0 _LM12-vfs @ VFS-UNMOUNT 0= _LM12-assert
    _LM12-vfs @ VFS-DESTROY
    _LM12-old-vfs @ VFS-USE
    _LM12-arena @ ARENA-DESTROY
    _LM12-stack ;

: _LM12-RUN  ( -- )
    0 _LM12-fails !
    0 _LM12-checks !
    DEPTH _LM12-depth !
    _LM12-runtime-init
    _LM12-repository-init
    _LM12-provision-and-bootstrap
    _LM12-repair-and-stale
    _LM12-sink-contracts
    _LM12-second-read-and-stream-faults
    _LM12-uncertain-contracts
    _LM12-future-and-corrupt
    _LM12-faulted-repair-cleanup
    _LM12-finish
    _LM12-fails @ IF
        ." LIBRARY MAINTENANCE L12 FAIL "
        _LM12-fails @ . ." /" _LM12-checks @ . CR
    ELSE
        ." LIBRARY MAINTENANCE L12 PASS "
        _LM12-checks @ . CR
    THEN ;
