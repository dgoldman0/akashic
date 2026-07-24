\ Focused RAM-VFS contracts for the L12 Desk/Library repository owner.

PROVIDED akashic-library-repository-l12-contracts

VARIABLE _LR12-fails
VARIABLE _LR12-checks
VARIABLE _LR12-depth
VARIABLE _LR12-arena
VARIABLE _LR12-vfs
VARIABLE _LR12-ior
VARIABLE _LR12-old-vfs
VARIABLE _LR12-fault-at
VARIABLE _LR12-cwd
VARIABLE _LR12-owner-calls
VARIABLE _LR12-byte

CREATE _LR12-ops VFS-OPS-SIZE ALLOT
CREATE _LR12-binding VFS-BINDING-DESC-SIZE ALLOT

CREATE _LR12-cache-a0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LR12-cache-a1 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LR12-cache-ac0 PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _LR12-cache-ac1 PERSIST-PAGE-CACHE-SIZE ALLOT
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LR12-cache-a0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LR12-cache-a1-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LR12-cache-ac0-memory
PERSIST-PAGE-CACHE-FRAME-SIZE 2 * XBUF _LR12-cache-ac1-memory
GUARD _LR12-guard-a
GUARD _LR12-guard-ac

LIBRARY-REPOSITORY-SIZE XBUF _LR12-repository-a
LIBRARY-REPOSITORY-WORK-SIZE XBUF _LR12-work-a
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LR12-record-a
LIBRARY-REPOSITORY-STAGE-BUFFER-MIN XBUF _LR12-stage-a
LIBRARY-REPOSITORY-RECORD-BUFFER-MIN XBUF _LR12-builder-record-a
512 XBUF _LR12-compact-buffer-a

CREATE _LR12-bootstrap RID-SIZE ALLOT
LIBRARY-REPOSITORY-INSPECTION-SIZE XBUF _LR12-inspection
CREATE _LR12-repaired-seal SHA3-256-LEN ALLOT
CREATE _LR12-raw 64 ALLOT

: _LR12-assert  ( flag -- )
    1 _LR12-checks +!
    0= IF
        1 _LR12-fails +!
        ." LIBRARY REPOSITORY L12 ASSERT " _LR12-checks @ . CR
    THEN ;

: _LR12-stack  ( -- )
    DEPTH DUP _LR12-depth @ <> IF
        ." LIBRARY REPOSITORY L12 STACK "
        _LR12-depth @ . ." -> " DUP . CR .S CR
    THEN
    _LR12-depth @ = _LR12-assert ;

: _LR12-filled?  ( address length byte -- flag )
    _LR12-byte !
    0 ?DO
        DUP I + C@ _LR12-byte @ <> IF
            DROP 0 UNLOOP EXIT
        THEN
    LOOP
    DROP -1 ;

: _LR12-status  ( actual expected -- )
    2DUP <> IF
        ." LIBRARY REPOSITORY L12 STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _LR12-assert _LR12-stack ;

: _LR12-fault  ( point ordinal context -- status )
    2DROP _LR12-fault-at @ =
    IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN ;

: _LR12-owner-ok  ( context repository work -- status )
    2DROP DROP
    1 _LR12-owner-calls +!
    LIBRARY-REPOSITORY-S-OK ;

: _LR12-owner-bad-status  ( context repository work -- status )
    2DROP DROP 99 ;

: _LR12-owner-throw  ( context repository work -- status )
    2DROP DROP -777 THROW ;

: _LR12-owner-reenter  ( context repository work -- status )
    ROT DROP LIBRARY-REPOSITORY-LOAD
    LIBRARY-REPOSITORY-S-BUSY =
    IF LIBRARY-REPOSITORY-S-OK
    ELSE LIBRARY-REPOSITORY-S-CONFLICT THEN ;

: _LR12-cache-init  ( memory cache -- )
    >R
    PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 R> PPAGE-CACHE-INIT
        PERSIST-S-OK _LR12-status ;

: _LR12-runtime-init  ( -- )
    VFS-CUR _LR12-old-vfs !
    VFS-RAM-OPS _LR12-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _LR12-binding VFS-BINDING-DESC-SIZE MOVE
    _LR12-ops _LR12-binding VB.OPS !
    67108864 A-XMEM ARENA-NEW DUP 0= _LR12-assert DROP _LR12-arena !
    _LR12-arena @ _LR12-binding 0 VFS-NEW _LR12-ior ! _LR12-vfs !
    _LR12-ior @ 0= _LR12-assert
    _LR12-vfs @ 0<> _LR12-assert

    _LR12-cache-a0-memory _LR12-cache-a0 _LR12-cache-init
    _LR12-cache-a1-memory _LR12-cache-a1 _LR12-cache-init
    _LR12-cache-ac0-memory _LR12-cache-ac0 _LR12-cache-init
    _LR12-cache-ac1-memory _LR12-cache-ac1 _LR12-cache-init
    S" elsewhere" _LR12-vfs @ VFS-MKDIR 0= _LR12-assert
    S" /elsewhere" _LR12-vfs @ VFS-RESOLVE?
    DUP 0= _LR12-assert DROP
    DUP 0<> _LR12-assert
    DUP _LR12-cwd !
    _LR12-vfs @ V.CWD !
    _LR12-bootstrap RID-SIZE 0x42 FILL
    0 _LR12-fault-at !
    0 _LR12-owner-calls !
    _LR12-stack ;

: _LR12-repository-a-init  ( -- )
    _LR12-vfs @
    _LR12-cache-a0 _LR12-cache-a1
    _LR12-cache-ac0 _LR12-cache-ac1
    _LR12-guard-a _LR12-guard-ac
    ['] _LR12-fault 0 _LR12-repository-a
    LIBRARY-REPOSITORY-INIT
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-VALID? _LR12-assert
    _LR12-record-a LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LR12-stage-a LIBRARY-REPOSITORY-STAGE-BUFFER-MIN
    _LR12-builder-record-a LIBRARY-REPOSITORY-RECORD-BUFFER-MIN
    _LR12-compact-buffer-a 512
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-WORK-INIT
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-work-a LIBRARY-REPOSITORY-WORK-VALID? _LR12-assert
    _LR12-stack ;

: _LR12-init-preflight-contracts  ( -- )
    \ Invalid builder caches are rejected before the output repository or
    \ either inline source/builder descriptor can be touched.
    _LR12-repository-a LIBRARY-REPOSITORY-SIZE 0xA5 FILL
    _LR12-vfs @
    _LR12-cache-a0 _LR12-cache-a1
    0 _LR12-cache-ac1
    _LR12-guard-a _LR12-guard-ac
    ['] _LR12-fault 0 _LR12-repository-a
    LIBRARY-REPOSITORY-INIT
        LIBRARY-REPOSITORY-S-INVALID _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-SIZE 0xA5
        _LR12-filled? _LR12-assert

    _LR12-vfs @
    _LR12-cache-a0 _LR12-cache-a1
    _LR12-cache-ac0 0
    _LR12-guard-a _LR12-guard-ac
    ['] _LR12-fault 0 _LR12-repository-a
    LIBRARY-REPOSITORY-INIT
        LIBRARY-REPOSITORY-S-INVALID _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-SIZE 0xA5
        _LR12-filled? _LR12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-SIZE 0 FILL
    _LR12-stack ;

: _LR12-owner-contracts  ( -- )
    77 ['] _LR12-owner-ok _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-owner-calls @ 1 = _LR12-assert

    77 0 _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-INVALID _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-STATUS@
        LIBRARY-REPOSITORY-S-OK = _LR12-assert
    _LR12-work-a LIBRARY-REPOSITORY-WORK-STATUS@
        LIBRARY-REPOSITORY-S-OK = _LR12-assert

    77 ['] _LR12-owner-bad-status _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-INVALID _LR12-status
    77 ['] _LR12-owner-throw _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-FAULT _LR12-status
    77 ['] _LR12-owner-reenter _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-stack ;

: _LR12-cold-provision-bootstrap  ( -- )
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-ABSENT _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-LOADED? _LR12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-PROVISIONED? 0= _LR12-assert

    S" /library" _LR12-vfs @ VFS-CREATE 0<> _LR12-assert
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-CORRUPT _LR12-status
    S" /library" _LR12-vfs @ VFS-RM 0= _LR12-assert

    _LR12-repository-a _LIBREPO-ENSURE-DIRECTORY
        LIBRARY-REPOSITORY-S-OK _LR12-status
    S" /library" _LR12-vfs @ VFS-RESOLVE?
    DUP 0= _LR12-assert DROP
    DUP 0<> _LR12-assert
    _LR12-vfs @ V.CWD !
    S" pages-1" _LR12-vfs @ VFS-MKDIR 0= _LR12-assert
    _LR12-cwd @ _LR12-vfs @ V.CWD !
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-CORRUPT _LR12-status
    S" /library/pages-1" _LR12-vfs @ VFS-RM 0= _LR12-assert

    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-PROVISION
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-PROVISIONED? _LR12-assert
    _LR12-vfs @ V.CWD @ _LR12-cwd @ = _LR12-assert

    _LR12-inspection
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-inspection LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-ABSENT = _LR12-assert
    LIBRARY-REPOSITORY-EVIDENCE-PAGES-0 _LR12-inspection LRI.OBJECT
        LRIO.PRESENT @ _LR12-assert
    LIBRARY-REPOSITORY-EVIDENCE-SEGMENTS-1 _LR12-inspection LRI.OBJECT
        LRIO.PRESENT @ _LR12-assert

    _LR12-bootstrap _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-BOOTSTRAP
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@ 1 = _LR12-assert
    _LR12-work-a LIBRARY-REPOSITORY-LOGICAL-GENERATION@ 0= _LR12-assert
    _LR12-work-a LIBRARY-REPOSITORY-DOCUMENT-COUNT@ 0= _LR12-assert
    _LR12-stack ;

: _LR12-maintenance  ( -- )
    _LR12-inspection
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-inspection LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-FALLBACK = _LR12-assert
    _LR12-inspection LRI.REPAIR-MASK @
        LIBRARY-REPOSITORY-REPAIR-MIRROR AND 0<> _LR12-assert

    PERSIST-FAULT-ROOT-SYNCED _LR12-fault-at !
    _LR12-inspection _LR12-repaired-seal
    _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-ROOT-MIRROR-REPAIR
        LIBRARY-REPOSITORY-S-FAULT _LR12-status
    0 _LR12-fault-at !

    _LR12-inspection
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-INSPECT
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-inspection LRI.HEALTH @
        LIBRARY-REPOSITORY-HEALTH-OK = _LR12-assert
    _LR12-inspection LRI.SLOT-0-GENERATION @ 1 = _LR12-assert
    _LR12-inspection LRI.SLOT-1-GENERATION @ 1 = _LR12-assert

    _LR12-raw 64 _LR12-inspection
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-RAW-EXPORT
    DUP LIBRARY-REPOSITORY-S-CAPACITY = _LR12-assert DROP
    _LR12-inspection LRI.RAW-REQUIRED @ = _LR12-assert
    _LR12-stack ;

: _LR12-second-owner  ( -- )
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK _LR12-status
    DEPTH 0= _LR12-assert
    _LR12-cache-a0-memory _LR12-cache-a0 _LR12-cache-init
    _LR12-cache-a1-memory _LR12-cache-a1 _LR12-cache-init
    _LR12-cache-ac0-memory _LR12-cache-ac0 _LR12-cache-init
    _LR12-cache-ac1-memory _LR12-cache-ac1 _LR12-cache-init
    _LR12-repository-a-init
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-LOAD
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@ 1 = _LR12-assert
    _LR12-work-a LIBRARY-REPOSITORY-LOGICAL-GENERATION@ 0= _LR12-assert
    _LR12-bootstrap _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-BOOTSTRAP
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-stack ;

: _LR12-compaction-abort  ( -- )
    1048576 256 65536
    _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-COMPACTION-BIND
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-COMPACTION-BOUND? _LR12-assert
    _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-COMPACTION-BEGIN
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-work-a LIBRARY-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-BUILDING = _LR12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-BLOCKED? _LR12-assert
    77 ['] _LR12-owner-ok _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-CONFLICT _LR12-status
    _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-COMPACTION-STEP
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-work-a LIBRARY-REPOSITORY-COMPACTION-STATE@
    DUP PCOMPACT-STATE-BUILDING =
    SWAP PCOMPACT-STATE-READY = OR _LR12-assert
    _LR12-work-a LIBRARY-REPOSITORY-COMPACTION-WORK@
        1 = _LR12-assert
    _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-COMPACTION-ABORT
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-work-a LIBRARY-REPOSITORY-COMPACTION-STATE@
        PCOMPACT-STATE-IDLE = _LR12-assert
    _LR12-repository-a LIBRARY-REPOSITORY-BLOCKED? 0= _LR12-assert

    \ A durable post-publication failure remains unavailable even when its
    \ status is CORRUPT rather than UNCERTAIN.  Exercise the repository's
    \ state-derived fence independently of the neutral coordinator's own
    \ publication fault matrix.
    PCOMPACT-STATE-PUBLISHED
        _LR12-work-a _LRW.COMPACT _PCW.STATE !
    PERSIST-S-CORRUPT _LR12-work-a
        _LIBREPO-COMPACTION-BLOCK-UPDATE
    _LR12-repository-a LIBRARY-REPOSITORY-BLOCKED? _LR12-assert
    77 ['] _LR12-owner-ok _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-CONFLICT _LR12-status
    PCOMPACT-STATE-IDLE _LR12-work-a _LRW.COMPACT _PCW.STATE !
    PERSIST-S-OK _LR12-work-a _LIBREPO-COMPACTION-BLOCK-UPDATE
    _LR12-repository-a LIBRARY-REPOSITORY-BLOCKED? 0= _LR12-assert
    77 ['] _LR12-owner-ok _LR12-repository-a _LR12-work-a
        LIBRARY-REPOSITORY-WITH-OWNER
        LIBRARY-REPOSITORY-S-OK _LR12-status
    _LR12-repository-a LIBRARY-REPOSITORY-GENERATION@ 1 = _LR12-assert
    _LR12-stack ;

: _LR12-finish  ( -- )
    _LR12-repository-a _LR12-work-a LIBRARY-REPOSITORY-FINI
        LIBRARY-REPOSITORY-S-OK _LR12-status
    DEPTH 0= _LR12-assert
    0 _LR12-vfs @ VFS-UNMOUNT 0= _LR12-assert
    _LR12-vfs @ VFS-DESTROY
    _LR12-old-vfs @ VFS-USE
    _LR12-arena @ ARENA-DESTROY
    _LR12-stack ;

: _LR12-RUN  ( -- )
    0 _LR12-fails !
    0 _LR12-checks !
    DEPTH _LR12-depth !
    _LR12-runtime-init
    _LR12-init-preflight-contracts
    _LR12-repository-a-init
    _LR12-owner-contracts
    _LR12-cold-provision-bootstrap
    _LR12-maintenance
    _LR12-compaction-abort
    _LR12-second-owner
    _LR12-finish
    _LR12-fails @ IF
        ." LIBRARY REPOSITORY L12 FAIL "
        _LR12-fails @ . ." /" _LR12-checks @ . CR
    ELSE
        ." LIBRARY REPOSITORY L12 PASS "
        _LR12-checks @ . CR
    THEN ;
