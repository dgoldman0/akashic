\ RAM-VFS contracts for the neutral transactional persistence store.

PROVIDED akashic-persistence-store-contracts


VARIABLE _PSTC-fails
VARIABLE _PSTC-checks
VARIABLE _PSTC-depth
VARIABLE _PSTC-arena
VARIABLE _PSTC-vfs
VARIABLE _PSTC-ior
VARIABLE _PSTC-old-vfs
VARIABLE _PSTC-page-id
VARIABLE _PSTC-fault-at
VARIABLE _PSTC-old-generation
VARIABLE _PSTC-old-pages
VARIABLE _PSTC-seam-fault
VARIABLE _PSTC-old-release-xt

CREATE _PSTC-ops VFS-OPS-SIZE ALLOT
CREATE _PSTC-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _PSTC-stats-a PERSIST-STATS-SIZE ALLOT
CREATE _PSTC-stats-b PERSIST-STATS-SIZE ALLOT
CREATE _PSTC-cache-a PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _PSTC-cache-b PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _PSTC-cache-mem-a PERSIST-PAGE-CACHE-FRAME-SIZE 2 * ALLOT
CREATE _PSTC-cache-mem-b PERSIST-PAGE-CACHE-FRAME-SIZE 2 * ALLOT
CREATE _PSTC-store-a PSTORE-SIZE ALLOT
CREATE _PSTC-store-b PSTORE-SIZE ALLOT
CREATE _PSTC-work-a PSTORE-WORK-SIZE ALLOT
CREATE _PSTC-work-b PSTORE-WORK-SIZE ALLOT
CREATE _PSTC-record-buffer-a 512 ALLOT
CREATE _PSTC-record-buffer-b 512 ALLOT
CREATE _PSTC-record 256 ALLOT
CREATE _PSTC-record-2 256 ALLOT
CREATE _PSTC-ref PERSIST-REF-SIZE ALLOT
CREATE _PSTC-ref-2 PERSIST-REF-SIZE ALLOT
CREATE _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _PSTC-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _PSTC-store-i0 PSTORE-SIZE ALLOT
CREATE _PSTC-store-i1 PSTORE-SIZE ALLOT
CREATE _PSTC-store-i2 PSTORE-SIZE ALLOT
CREATE _PSTC-store-i3 PSTORE-SIZE ALLOT
CREATE _PSTC-work-i0 PSTORE-WORK-SIZE ALLOT
CREATE _PSTC-work-i1 PSTORE-WORK-SIZE ALLOT
CREATE _PSTC-work-i2 PSTORE-WORK-SIZE ALLOT
CREATE _PSTC-work-i3 PSTORE-WORK-SIZE ALLOT
CREATE _PSTC-buffer-i0 512 ALLOT
CREATE _PSTC-buffer-i1 512 ALLOT
CREATE _PSTC-buffer-i2 512 ALLOT
CREATE _PSTC-buffer-i3 512 ALLOT
CREATE _PSTC-identity-i0 PERSIST-IDENTITY-SIZE ALLOT
CREATE _PSTC-identity-i1 PERSIST-IDENTITY-SIZE ALLOT
CREATE _PSTC-identity-i2 PERSIST-IDENTITY-SIZE ALLOT
CREATE _PSTC-identity-i3 PERSIST-IDENTITY-SIZE ALLOT
GUARD _PSTC-guard-a
GUARD _PSTC-guard-b
GUARD _PSTC-guard-i0
GUARD _PSTC-guard-i1
GUARD _PSTC-guard-i2
GUARD _PSTC-guard-i3

: _PSTC-assert  ( flag -- )
    1 _PSTC-checks +!
    0= IF 1 _PSTC-fails +! ." PERSISTENCE STORE ASSERT " _PSTC-checks @ . CR THEN ;

: _PSTC-stack  ( -- )
    DEPTH DUP _PSTC-depth @ <> IF
        ." PERSISTENCE STORE STACK " _PSTC-depth @ . ." -> " DUP . CR .S CR
    THEN
    _PSTC-depth @ = _PSTC-assert ;

: _PSTC-status  ( actual expected -- )
    2DUP <> IF ." PERSISTENCE STORE STATUS actual/expected " 2DUP . . CR THEN
    = _PSTC-assert _PSTC-stack ;

: _PSTC-fault  ( point ordinal context -- status )
    2DROP _PSTC-fault-at @ = IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN ;

: _PSTC-store-a-init  ( -- status )
    S" /pstore-pages" S" /pstore-segment"
    S" /pstore-root-a" S" /pstore-root-b"
    _PSTC-identity 256 _PSTC-vfs @ _PSTC-stats-a _PSTC-cache-a _PSTC-guard-a
    ['] _PSTC-fault 0 _PSTC-store-a PSTORE-INIT ;

: _PSTC-store-b-init  ( -- status )
    S" /pstore-pages" S" /pstore-segment"
    S" /pstore-root-a" S" /pstore-root-b"
    _PSTC-identity 256 _PSTC-vfs @ _PSTC-stats-b _PSTC-cache-b _PSTC-guard-b
    ['] _PSTC-fault 0 _PSTC-store-b PSTORE-INIT ;

: _PSTC-store-i0-init  ( -- status )
    S" /i0-pages" S" /i0-segment" S" /i0-root-a" S" /i0-root-b"
    _PSTC-identity-i0 256 _PSTC-vfs @ 0 0 _PSTC-guard-i0
    ['] _PSTC-fault 0 _PSTC-store-i0 PSTORE-INIT ;

: _PSTC-store-i1-init  ( -- status )
    S" /i1-pages" S" /i1-segment" S" /i1-root-a" S" /i1-root-b"
    _PSTC-identity-i1 256 _PSTC-vfs @ 0 0 _PSTC-guard-i1
    ['] _PSTC-fault 0 _PSTC-store-i1 PSTORE-INIT ;

: _PSTC-store-i2-init  ( -- status )
    S" /i2-pages" S" /i2-segment" S" /i2-root-a" S" /i2-root-b"
    _PSTC-identity-i2 256 _PSTC-vfs @ 0 0 _PSTC-guard-i2
    ['] _PSTC-fault 0 _PSTC-store-i2 PSTORE-INIT ;

: _PSTC-store-i3-init  ( -- status )
    S" /i3-pages" S" /i3-segment" S" /i3-root-a" S" /i3-root-b"
    _PSTC-identity-i3 256 _PSTC-vfs @ 0 0 _PSTC-guard-i3
    ['] _PSTC-fault 0 _PSTC-store-i3 PSTORE-INIT ;

: _PSTC-store-i1-as-i0-init  ( -- status )
    S" /i0-pages" S" /i0-segment" S" /i0-root-a" S" /i0-root-b"
    _PSTC-identity-i0 256 _PSTC-vfs @ 0 0 _PSTC-guard-i1
    ['] _PSTC-fault 0 _PSTC-store-i1 PSTORE-INIT ;

: _PSTC-release-uncertain  ( cookie inode vfs -- ior )
    _PSTC-old-release-xt @ EXECUTE
    DUP IF EXIT THEN
    DROP -912 ;

: _PSTC-setup  ( -- )
    VFS-CUR _PSTC-old-vfs !
    VFS-RAM-OPS _PSTC-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _PSTC-binding VFS-BINDING-DESC-SIZE MOVE
    _PSTC-ops _PSTC-binding VB.OPS !
    4194304 A-XMEM ARENA-NEW DUP 0= _PSTC-assert DROP _PSTC-arena !
    _PSTC-arena @ _PSTC-binding 0 VFS-NEW _PSTC-ior ! _PSTC-vfs !
    _PSTC-ior @ 0= _PSTC-assert
    _PSTC-vfs @ 0<> _PSTC-assert
    _PSTC-stats-a PERSIST-STATS-INIT
    _PSTC-stats-b PERSIST-STATS-INIT
    _PSTC-cache-mem-a PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 _PSTC-cache-a
        PPAGE-CACHE-INIT PERSIST-S-OK _PSTC-status
    _PSTC-cache-mem-b PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2 _PSTC-cache-b
        PPAGE-CACHE-INIT PERSIST-S-OK _PSTC-status
    _PSTC-identity PERSIST-IDENTITY-SIZE 61 FILL
    _PSTC-record 256 0 FILL
    S" exact neutral record" _PSTC-record SWAP MOVE
    _PSTC-record-2 256 0 FILL
    S" failed suffix record" _PSTC-record-2 SWAP MOVE
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PSTC-identity-i0 PERSIST-IDENTITY-SIZE 1 FILL
    _PSTC-identity-i1 PERSIST-IDENTITY-SIZE 2 FILL
    _PSTC-identity-i2 PERSIST-IDENTITY-SIZE 3 FILL
    _PSTC-identity-i3 PERSIST-IDENTITY-SIZE 4 FILL
    _PSTC-ref PERSIST-REF-INIT
    _PSTC-ref-2 PERSIST-REF-INIT ;

: _PSTC-first-commit  ( -- )
    _PSTC-store-a-init PERSIST-S-OK _PSTC-status
    _PSTC-store-a PSTORE-VALID? _PSTC-assert _PSTC-stack
    _PSTC-record-buffer-a 512 _PSTC-work-a PSTORE-WORK-INIT
        PERSIST-S-OK _PSTC-status
    _PSTC-work-a PSTORE-WORK-RECORD-BUFFER$
        SWAP _PSTC-record-buffer-a = SWAP 512 = AND _PSTC-assert _PSTC-stack
    _PSTC-store-a _PSTC-work-a PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-a _PSTC-work-a PSTORE-OPEN PERSIST-S-ABSENT _PSTC-status
    _PSTC-store-a PSTORE-GENERATION@ 0= _PSTC-assert
    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-record 20 _PSTC-ref _PSTC-store-a _PSTC-work-a
        PSTORE-APPEND-RECORD PERSIST-S-OK _PSTC-status
    _PSTC-ref _PSTC-page PERSIST-REF-SIZE MOVE
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _PSTC-store-a _PSTC-work-a
        PSTORE-APPEND-PAGE
        SWAP _PSTC-page-id ! PERSIST-S-OK _PSTC-status
    _PSTC-page-id @ 0= _PSTC-assert _PSTC-stack
    0 _PSTC-store-a _PSTC-work-a PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PSTC-status
    _PSTC-store-a _PSTC-work-a PSTORE-COMMIT PERSIST-S-OK _PSTC-status
    _PSTC-store-a PSTORE-GENERATION@ 1 = _PSTC-assert
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 1 = _PSTC-assert
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.RECORD-COUNT @ 1 = _PSTC-assert
    _PSTC-stack ;

: _PSTC-span-boundaries  ( -- )
    _PSTC-store-a PSTORE-SIZE _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PERSIST-ROOT-VALUE-SIZE _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-vfs @ VFS-DESC-SIZE _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-stats-a PERSIST-STATS-SIZE _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-stats-a 8 + PERSIST-STATS-SIZE 8 - _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-cache-a PERSIST-PAGE-CACHE-SIZE _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-cache-mem-a PERSIST-PAGE-CACHE-FRAME-SIZE 2 * _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-guard-a PSTORE-SPIN-GUARD-SIZE _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-work-a PSTORE-WORK-SIZE _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-record-buffer-a 512 _PSTC-store-a
        PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-record 20 _PSTC-store-a PSTORE-SPAN-DISJOINT? _PSTC-assert
    0 0 _PSTC-store-a PSTORE-SPAN-DISJOINT? _PSTC-assert
    0 1 _PSTC-store-a PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-record 0 _PSTC-store-a PSTORE-SPAN-DISJOINT? _PSTC-assert
    _PSTC-record -1 _PSTC-store-a PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    -8 16 _PSTC-store-a PSTORE-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-work-a PSTORE-WORK-SIZE _PSTC-work-a
        PSTORE-WORK-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-record-buffer-a 512 _PSTC-work-a
        PSTORE-WORK-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-record-buffer-a 512 + 1 _PSTC-work-a
        PSTORE-WORK-SPAN-DISJOINT? _PSTC-assert
    0 0 _PSTC-work-a PSTORE-WORK-SPAN-DISJOINT? _PSTC-assert
    0 1 _PSTC-work-a PSTORE-WORK-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-record 0 _PSTC-work-a PSTORE-WORK-SPAN-DISJOINT? _PSTC-assert
    _PSTC-record -1 _PSTC-work-a
        PSTORE-WORK-SPAN-DISJOINT? 0= _PSTC-assert
    -8 16 _PSTC-work-a PSTORE-WORK-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-record 1 _PSTC-record
        PSTORE-WORK-SPAN-DISJOINT? 0= _PSTC-assert
    _PSTC-stack ;

: _PSTC-readback  ( -- )
    0 _PSTC-store-a _PSTC-work-a PSTORE-READ-PAGE PERSIST-S-OK _PSTC-status
    _PSTC-work-a PSTORE-PAGE-PAYLOAD$
        _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE COMPARE 0= _PSTC-assert _PSTC-stack
    _PSTC-ref _PSTC-store-a _PSTC-work-a PSTORE-READ-RECORD
        PERSIST-S-OK _PSTC-status
    _PSTC-work-a PSTORE-RECORD-PAYLOAD$
        DUP 20 = _PSTC-assert
        _PSTC-record 20 COMPARE 0= _PSTC-assert _PSTC-stack ;

: _PSTC-suffix-reconcile  ( -- )
    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-record-2 20 _PSTC-ref-2 _PSTC-store-a _PSTC-work-a
        PSTORE-APPEND-RECORD PERSIST-S-OK _PSTC-status
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _PSTC-status
    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-record 20 _PSTC-ref-2 _PSTC-store-a _PSTC-work-a
        PSTORE-APPEND-RECORD PERSIST-S-OK _PSTC-status
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _PSTC-status ;

: _PSTC-cold-open  ( -- )
    _PSTC-store-b-init PERSIST-S-OK _PSTC-status
    _PSTC-record-buffer-b 512 _PSTC-work-b PSTORE-WORK-INIT
        PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-OPEN PERSIST-S-OK _PSTC-status
    _PSTC-store-b PSTORE-GENERATION@ 1 = _PSTC-assert
    0 _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PAGE-PAYLOAD$
        _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE COMPARE 0= _PSTC-assert _PSTC-stack ;

: _PSTC-tx-page-seams  ( -- )
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-TX-READY? _PSTC-assert _PSTC-stack
    _PSTC-store-a _PSTC-work-b PSTORE-TX-READY? 0= _PSTC-assert _PSTC-stack
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 55 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 1
        _PSTC-store-b _PSTC-work-b PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 2 = _PSTC-assert
    1 _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE-TX
        PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PAGE-PAYLOAD$ DROP C@ 55 = _PSTC-assert

    \ Rewriting the transaction-local slot does not grow the proposed bound.
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 66 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 1
        _PSTC-store-b _PSTC-work-b PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 2 = _PSTC-assert
    1 _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE-TX
        PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PAGE-PAYLOAD$ DROP C@ 66 = _PSTC-assert
    0 _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE-TX
        PERSIST-S-OK _PSTC-status
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 3
        _PSTC-store-b _PSTC-work-b PSTORE-WRITE-PAGE-TX
        PERSIST-S-NOT-FOUND _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-TX-READY? 0= _PSTC-assert _PSTC-stack
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status

    \ Abort leaves authority at one page; the next begin reconciles the suffix.
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 1 = _PSTC-assert
    1 _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE-TX
        PERSIST-S-NOT-FOUND _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status ;

\ A layered failure can invalidate an otherwise ready proposal without doing
\ more I/O.  Commit must leave that poisoned transaction owned so only ABORT
\ can release it and the next BEGIN can reconcile any proposal suffix.
: _PSTC-layer-poison  ( -- )
    _PSTC-store-b PSTORE-GENERATION@ _PSTC-old-generation !
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-stats-b PSTAT.BYTES-WRITTEN @ _PSTC-old-pages !
    PERSIST-S-OK _PSTC-store-b _PSTC-work-b PSTORE-TX-POISON
        PERSIST-S-INVALID _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-TX-READY? _PSTC-assert _PSTC-stack
    PERSIST-S-CAPACITY _PSTC-store-b _PSTC-work-b PSTORE-TX-POISON
        PERSIST-S-CAPACITY _PSTC-status
    _PSTC-stats-b PSTAT.BYTES-WRITTEN @ _PSTC-old-pages @ = _PSTC-assert
    _PSTC-store-b _PSTC-work-b PSTORE-TX-READY? 0= _PSTC-assert
    _PSTC-store-b PSTORE-STATUS@ PERSIST-S-CAPACITY _PSTC-status
    _PSTC-work-b PSTORE-WORK-STATUS@ PERSIST-S-CAPACITY _PSTC-status
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _PSTC-store-b _PSTC-work-b
        PSTORE-APPEND-PAGE
        SWAP -1 = SWAP PERSIST-S-BUSY = AND _PSTC-assert _PSTC-stack
    _PSTC-store-b _PSTC-work-b PSTORE-COMMIT
        PERSIST-S-CONFLICT _PSTC-status
    _PSTC-store-b PSTORE-STATUS@ PERSIST-S-CAPACITY _PSTC-status
    _PSTC-work-b PSTORE-WORK-STATUS@ PERSIST-S-CAPACITY _PSTC-status
    _PSTC-store-b PSTORE-GENERATION@ _PSTC-old-generation @ = _PSTC-assert
    _PSTC-stats-b PSTAT.BYTES-WRITTEN @ _PSTC-old-pages @ = _PSTC-assert
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ = _PSTC-assert
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status ;

: _PSTC-tx-rewrite-fault-at  ( point -- )
    _PSTC-seam-fault !
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 77 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 1
        _PSTC-store-b _PSTC-work-b PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _PSTC-status
    _PSTC-seam-fault @ _PSTC-fault-at !
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 88 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 1
        _PSTC-store-b _PSTC-work-b PSTORE-WRITE-PAGE-TX
        PERSIST-S-FAULT _PSTC-status
    0 _PSTC-fault-at !
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 1 = _PSTC-assert
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status ;

: _PSTC-tx-rewrite-faults  ( -- )
    PERSIST-FAULT-PAGE-WRITTEN _PSTC-tx-rewrite-fault-at
    PERSIST-FAULT-PAGE-VERIFIED _PSTC-tx-rewrite-fault-at ;

: _PSTC-segment-fault-at  ( point -- )
    _PSTC-fault-at !
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-record-2 20 _PSTC-ref-2 _PSTC-store-b _PSTC-work-b
        PSTORE-APPEND-RECORD PERSIST-S-FAULT _PSTC-status
    0 _PSTC-fault-at !
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status ;

: _PSTC-page-fault-at  ( point -- )
    _PSTC-fault-at !
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 66 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _PSTC-store-b _PSTC-work-b
        PSTORE-APPEND-PAGE
        SWAP -1 = SWAP PERSIST-S-FAULT = AND _PSTC-assert _PSTC-stack
    0 _PSTC-fault-at !
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status ;

: _PSTC-mutation-faults  ( -- )
    PERSIST-FAULT-SEGMENT-WRITTEN _PSTC-segment-fault-at
    PERSIST-FAULT-SEGMENT-VERIFIED _PSTC-segment-fault-at
    PERSIST-FAULT-PAGE-WRITTEN _PSTC-page-fault-at
    PERSIST-FAULT-PAGE-VERIFIED _PSTC-page-fault-at ;

: _PSTC-root-durable-fault  ( -- )
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 77 FILL
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _PSTC-store-b _PSTC-work-b
        PSTORE-APPEND-PAGE
        SWAP _PSTC-page-id ! PERSIST-S-OK _PSTC-status
    _PSTC-page-id @ 1 = _PSTC-assert
    1 _PSTC-store-b _PSTC-work-b PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PSTC-status
    PERSIST-FAULT-ROOT-PUBLISHED _PSTC-fault-at !
    _PSTC-store-b _PSTC-work-b PSTORE-COMMIT PERSIST-S-FAULT _PSTC-status
    0 _PSTC-fault-at !
    _PSTC-store-b PSTORE-GENERATION@ 2 = _PSTC-assert
    _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @ 1 = _PSTC-assert
    1 _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE PERSIST-S-OK _PSTC-status
    _PSTC-stack ;

: _PSTC-data-sync-fault  ( -- )
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 88 FILL
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _PSTC-store-b _PSTC-work-b
        PSTORE-APPEND-PAGE
        SWAP _PSTC-page-id ! PERSIST-S-OK _PSTC-status
    2 _PSTC-store-b _PSTC-work-b PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PSTC-status
    PERSIST-FAULT-DATA-SYNCED _PSTC-fault-at !
    _PSTC-store-b _PSTC-work-b PSTORE-COMMIT PERSIST-S-FAULT _PSTC-status
    0 _PSTC-fault-at !
    _PSTC-store-b PSTORE-GENERATION@ 2 = _PSTC-assert
    _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 2 = _PSTC-assert
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-work-b PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 2 = _PSTC-assert
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _PSTC-status ;

: _PSTC-store-b-reopen  ( -- )
    _PSTC-store-b-init PERSIST-S-OK _PSTC-status
    _PSTC-record-buffer-b 512 _PSTC-work-b PSTORE-WORK-INIT
        PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-OPEN PERSIST-S-OK _PSTC-status ;

: _PSTC-root-maybe-fault-at  ( point -- )
    _PSTC-store-b PSTORE-GENERATION@ _PSTC-old-generation !
    _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ _PSTC-old-pages !
    _PSTC-fault-at !
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 99 FILL
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _PSTC-store-b _PSTC-work-b
        PSTORE-APPEND-PAGE
        SWAP _PSTC-page-id ! PERSIST-S-OK _PSTC-status
    _PSTC-page-id @ _PSTC-old-pages @ = _PSTC-assert _PSTC-stack
    _PSTC-page-id @ _PSTC-store-b _PSTC-work-b PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _PSTC-status
    _PSTC-store-b _PSTC-work-b PSTORE-COMMIT
        PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-b PSTORE-UNCERTAIN? _PSTC-assert _PSTC-stack
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN
        PERSIST-S-UNCERTAIN _PSTC-status
    0 _PSTC-fault-at !
    _PSTC-store-b-reopen
    _PSTC-store-b PSTORE-GENERATION@ _PSTC-old-generation @ = IF
        _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @
            _PSTC-old-pages @ = _PSTC-assert
    ELSE
        _PSTC-store-b PSTORE-GENERATION@
            _PSTC-old-generation @ 1+ = _PSTC-assert
        _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @
            _PSTC-old-pages @ 1+ = _PSTC-assert
    THEN
    _PSTC-stack ;

: _PSTC-root-maybe-faults  ( -- )
    PERSIST-FAULT-ROOT-WRITTEN _PSTC-root-maybe-fault-at
    PERSIST-FAULT-ROOT-SIZED _PSTC-root-maybe-fault-at
    PERSIST-FAULT-ROOT-SYNCED _PSTC-root-maybe-fault-at
    PERSIST-FAULT-ROOT-VERIFIED _PSTC-root-maybe-fault-at ;

: _PSTC-interleave-init  ( -- )
    _PSTC-store-i0-init PERSIST-S-OK _PSTC-status
    _PSTC-store-i1-init PERSIST-S-OK _PSTC-status
    _PSTC-store-i2-init PERSIST-S-OK _PSTC-status
    _PSTC-store-i3-init PERSIST-S-OK _PSTC-status
    _PSTC-buffer-i0 512 _PSTC-work-i0 PSTORE-WORK-INIT PERSIST-S-OK _PSTC-status
    _PSTC-buffer-i1 512 _PSTC-work-i1 PSTORE-WORK-INIT PERSIST-S-OK _PSTC-status
    _PSTC-buffer-i2 512 _PSTC-work-i2 PSTORE-WORK-INIT PERSIST-S-OK _PSTC-status
    _PSTC-buffer-i3 512 _PSTC-work-i3 PSTORE-WORK-INIT PERSIST-S-OK _PSTC-status
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-OPEN PERSIST-S-ABSENT _PSTC-status
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-OPEN PERSIST-S-ABSENT _PSTC-status
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-OPEN PERSIST-S-ABSENT _PSTC-status
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-OPEN PERSIST-S-ABSENT _PSTC-status ;

: _PSTC-interleave-page  ( byte store work -- )
    >R SWAP
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE ROT FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 2 PICK R@
        PSTORE-APPEND-PAGE SWAP 0= SWAP PERSIST-S-OK = AND _PSTC-assert
    0 SWAP R> PSTORE-APPLICATION-ROOT! PERSIST-S-OK _PSTC-status ;

: _PSTC-interleave-read-byte  ( expected store work -- )
    >R SWAP _PSTC-page-id !
    0 SWAP R@ PSTORE-READ-PAGE PERSIST-S-OK _PSTC-status
    _PSTC-page-id @ R> PSTORE-PAGE-PAYLOAD$ DROP C@ =
        _PSTC-assert _PSTC-stack ;

: _PSTC-four-store-interleave  ( -- )
    _PSTC-interleave-init
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    11 _PSTC-store-i0 _PSTC-work-i0 _PSTC-interleave-page
    22 _PSTC-store-i1 _PSTC-work-i1 _PSTC-interleave-page
    33 _PSTC-store-i2 _PSTC-work-i2 _PSTC-interleave-page
    44 _PSTC-store-i3 _PSTC-work-i3 _PSTC-interleave-page
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-COMMIT PERSIST-S-OK _PSTC-status
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-COMMIT PERSIST-S-OK _PSTC-status
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-COMMIT PERSIST-S-OK _PSTC-status
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-COMMIT PERSIST-S-OK _PSTC-status
    _PSTC-store-i0 PSTORE-GENERATION@ 1 = _PSTC-assert
    _PSTC-store-i1 PSTORE-GENERATION@ 1 = _PSTC-assert
    _PSTC-store-i2 PSTORE-GENERATION@ 1 = _PSTC-assert
    _PSTC-store-i3 PSTORE-GENERATION@ 1 = _PSTC-assert
    11 _PSTC-store-i0 _PSTC-work-i0 _PSTC-interleave-read-byte
    22 _PSTC-store-i1 _PSTC-work-i1 _PSTC-interleave-read-byte
    33 _PSTC-store-i2 _PSTC-work-i2 _PSTC-interleave-read-byte
    44 _PSTC-store-i3 _PSTC-work-i3 _PSTC-interleave-read-byte ;

\ A layered UNCERTAIN result has the same sticky meaning as uncertainty
\ discovered inside PSTORE.  Commit still refuses the owned proposal, while
\ abort releases it without pretending that durable state became certain.
: _PSTC-layer-uncertain  ( -- )
    _PSTC-store-i2 PSTORE-GENERATION@ _PSTC-old-generation !
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    PERSIST-S-UNCERTAIN _PSTC-store-i2 _PSTC-work-i2 PSTORE-TX-POISON
        PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i2 PSTORE-UNCERTAIN? _PSTC-assert _PSTC-stack
    _PSTC-store-i2 PSTORE-STATUS@ PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-work-i2 PSTORE-WORK-STATUS@ PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-COMMIT
        PERSIST-S-CONFLICT _PSTC-status
    _PSTC-store-i2 PSTORE-STATUS@ PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-work-i2 PSTORE-WORK-STATUS@ PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i2 PSTORE-GENERATION@ _PSTC-old-generation @ = _PSTC-assert
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-ABORT
        PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i2 PSTORE-STATUS@ PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-BEGIN
        PERSIST-S-UNCERTAIN _PSTC-status ;

\ Cleanup uncertainty returned by a nested page operation becomes sticky at
\ the store boundary.  A fresh descriptor can still recover solely from the
\ durable roots once the uncertain transaction has released its authority.
: _PSTC-cleanup-uncertain  ( -- )
    _PSTC-ops VFS-OP-RELEASE CELLS + @ _PSTC-old-release-xt !
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _PSTC-status
    ['] _PSTC-release-uncertain
        _PSTC-ops VFS-OP-RELEASE CELLS + !
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 77 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 1
        _PSTC-store-i0 _PSTC-work-i0 PSTORE-WRITE-PAGE-TX
        PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-old-release-xt @ _PSTC-ops VFS-OP-RELEASE CELLS + !
    _PSTC-store-i0 PSTORE-UNCERTAIN? _PSTC-assert _PSTC-stack
    _PSTC-store-i0 PSTORE-STATUS@ PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT
        PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i0 PSTORE-STATUS@ PERSIST-S-UNCERTAIN _PSTC-status
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN
        PERSIST-S-UNCERTAIN _PSTC-status
    0 _PSTC-store-i0 _PSTC-work-i0 PSTORE-READ-PAGE
        PERSIST-S-UNCERTAIN _PSTC-status

    _PSTC-store-i1-as-i0-init PERSIST-S-OK _PSTC-status
    _PSTC-buffer-i1 512 _PSTC-work-i1 PSTORE-WORK-INIT
        PERSIST-S-OK _PSTC-status
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-PROVISION PERSIST-S-OK _PSTC-status
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-OPEN PERSIST-S-OK _PSTC-status
    _PSTC-store-i1 PSTORE-GENERATION@ 1 = _PSTC-assert
    11 _PSTC-store-i1 _PSTC-work-i1 _PSTC-interleave-read-byte ;

: _PSTC-run  ( -- )
    0 _PSTC-fails ! 0 _PSTC-checks ! DEPTH _PSTC-depth ! 0 _PSTC-fault-at !
    _PSTC-setup
    _PSTC-first-commit
    _PSTC-span-boundaries
    _PSTC-readback
    _PSTC-suffix-reconcile
    _PSTC-cold-open
    _PSTC-tx-page-seams
    _PSTC-layer-poison
    _PSTC-tx-rewrite-faults
    _PSTC-mutation-faults
    _PSTC-root-durable-fault
    _PSTC-data-sync-fault
    _PSTC-root-maybe-faults
    _PSTC-four-store-interleave
    _PSTC-layer-uncertain
    _PSTC-cleanup-uncertain
    _PSTC-old-vfs @ VFS-USE
    _PSTC-vfs @ VFS-DESTROY
    _PSTC-stack
    _PSTC-fails @ 0= IF
        ." PERSISTENCE STORE PASS " _PSTC-checks @ . CR
    ELSE
        ." PERSISTENCE STORE FAIL " _PSTC-fails @ . ." /" _PSTC-checks @ . CR
    THEN ;
