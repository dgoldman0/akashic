\ RAM-VFS contracts for the neutral two-bank compaction coordinator.

PROVIDED akashic-persistence-compaction-contracts

VARIABLE _PCCT-fails
VARIABLE _PCCT-checks
VARIABLE _PCCT-depth
VARIABLE _PCCT-arena
VARIABLE _PCCT-vfs
VARIABLE _PCCT-ior
VARIABLE _PCCT-old-vfs
VARIABLE _PCCT-fault-at
VARIABLE _PCCT-callback-mode
VARIABLE _PCCT-finalize-fail
VARIABLE _PCCT-step-count
VARIABLE _PCCT-page-id
VARIABLE _PCCT-current-root
VARIABLE _PCCT-next-root
VARIABLE _PCCT-callback-source
VARIABLE _PCCT-callback-store
VARIABLE _PCCT-callback-work
VARIABLE _PCCT-callback-allowance
VARIABLE _PCCT-final-generation
VARIABLE _PCCT-context-seen
VARIABLE _PCCT-observed-generation
VARIABLE _PCCT-expected-generation
VARIABLE _PCCT-expected-bank

4096 CONSTANT _PCCT-STEP-CHARGE

CREATE _PCCT-ops VFS-OPS-SIZE ALLOT
CREATE _PCCT-binding VFS-BINDING-DESC-SIZE ALLOT
CREATE _PCCT-context 64 ALLOT
CREATE _PCCT-identity PERSIST-IDENTITY-SIZE ALLOT

CREATE _PCCT-source-stats PERSIST-STATS-SIZE ALLOT
CREATE _PCCT-source-cache PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _PCCT-source-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * ALLOT
CREATE _PCCT-source-store PSTORE-SIZE ALLOT
CREATE _PCCT-source-work PSTORE-WORK-SIZE ALLOT
CREATE _PCCT-source-buffer 512 ALLOT
GUARD _PCCT-source-guard

CREATE _PCCT-bank1-stats PERSIST-STATS-SIZE ALLOT
CREATE _PCCT-bank1-cache PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _PCCT-bank1-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * ALLOT
CREATE _PCCT-bank1-page PERSIST-PAGE-FILE-SIZE ALLOT
CREATE _PCCT-bank1-segment PSEG-FILE-SIZE ALLOT

CREATE _PCCT-builder-stats PERSIST-STATS-SIZE ALLOT
CREATE _PCCT-builder-cache PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _PCCT-builder-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * ALLOT
CREATE _PCCT-builder-store PSTORE-SIZE ALLOT
CREATE _PCCT-builder-work PSTORE-WORK-SIZE ALLOT
CREATE _PCCT-builder-buffer 512 ALLOT
GUARD _PCCT-builder-guard

CREATE _PCCT-compact PCOMPACT-SIZE ALLOT
CREATE _PCCT-compact-work-a PCOMPACT-WORK-SIZE ALLOT
CREATE _PCCT-compact-work-b PCOMPACT-WORK-SIZE ALLOT
CREATE _PCCT-compact-buffer-a 512 ALLOT
CREATE _PCCT-compact-buffer-b 512 ALLOT
CREATE _PCCT-root-snapshot PROOT-FILE-SIZE ALLOT
CREATE _PCCT-work-snapshot PCOMPACT-WORK-SIZE ALLOT
CREATE _PCCT-compact-snapshot PCOMPACT-SIZE ALLOT
CREATE _PCCT-stats-snapshot PERSIST-STATS-SIZE ALLOT
CREATE _PCCT-compact-alias-arena
    PERSIST-STATS-SIZE PCOMPACT-SIZE + ALLOT
VARIABLE _PCCT-saved-root-stats

CREATE _PCCT-observer-work PROOT-WORK-SIZE ALLOT
CREATE _PCCT-observer-value PERSIST-ROOT-VALUE-SIZE ALLOT
CREATE _PCCT-size-page-work PERSIST-PAGE-WORK-SIZE ALLOT
CREATE _PCCT-size-segment-work PSEG-WORK-SIZE ALLOT
CREATE _PCCT-size-segment-buffer 512 ALLOT

CREATE _PCCT-record 64 ALLOT
CREATE _PCCT-source-ref PERSIST-REF-SIZE ALLOT
CREATE _PCCT-builder-ref PERSIST-REF-SIZE ALLOT
CREATE _PCCT-seed-ref PERSIST-REF-SIZE ALLOT
CREATE _PCCT-page PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _PCCT-final-page PERSIST-PAGE-PAYLOAD-SIZE ALLOT

CREATE _PCCT-builder-tree PBTREE-SIZE ALLOT
CREATE _PCCT-builder-tree-work PBTREE-WORK-SIZE ALLOT
CREATE _PCCT-tree-root-a PBTREE-ROOT-SIZE ALLOT
CREATE _PCCT-tree-root-b PBTREE-ROOT-SIZE ALLOT
CREATE _PCCT-rebased-root PBTREE-ROOT-SIZE ALLOT
CREATE _PCCT-empty-reclaim RECLAIM-STATE-SIZE ALLOT

CREATE _PCCT-cold-stats PERSIST-STATS-SIZE ALLOT
CREATE _PCCT-cold-cache PERSIST-PAGE-CACHE-SIZE ALLOT
CREATE _PCCT-cold-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * ALLOT
CREATE _PCCT-cold-store PSTORE-SIZE ALLOT
CREATE _PCCT-cold-work PSTORE-WORK-SIZE ALLOT
CREATE _PCCT-cold-buffer 512 ALLOT
GUARD _PCCT-cold-guard
CREATE _PCCT-cold-tree PBTREE-SIZE ALLOT
CREATE _PCCT-cold-tree-work PBTREE-WORK-SIZE ALLOT
CREATE _PCCT-cold-root PBTREE-ROOT-SIZE ALLOT
CREATE _PCCT-cold-reclaim-state RECLAIM-STATE-SIZE ALLOT
CREATE _PCCT-cold-reclaim RECLAIM-SIZE ALLOT

: _PCCT-assert  ( flag -- )
    1 _PCCT-checks +!
    0= IF
        1 _PCCT-fails +!
        ." PERSISTENCE COMPACTION ASSERT " _PCCT-checks @ . CR
    THEN ;

: _PCCT-stack  ( -- )
    DEPTH DUP _PCCT-depth @ <> IF
        ." PERSISTENCE COMPACTION STACK " _PCCT-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _PCCT-depth @ = _PCCT-assert ;

: _PCCT-status  ( actual expected -- )
    2DUP <> IF
        ." PERSISTENCE COMPACTION STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _PCCT-assert _PCCT-stack ;

: _PCCT-fault  ( point ordinal context -- status )
    2DROP _PCCT-fault-at @ =
    IF PERSIST-S-FAULT ELSE PERSIST-S-OK THEN ;

: _PCCT-source-store-init  ( -- status )
    S" /pc-b0-pages" S" /pc-b0-segment"
    S" /pc-root-a" S" /pc-root-b"
    _PCCT-identity 256 _PCCT-vfs @ _PCCT-source-stats
    _PCCT-source-cache _PCCT-source-guard
    ['] _PCCT-fault 0 _PCCT-source-store PSTORE-INIT ;

: _PCCT-builder-store-init  ( -- status )
    S" /pc-b0-pages" S" /pc-b0-segment"
    S" /pc-stage-a" S" /pc-stage-b"
    _PCCT-identity 256 _PCCT-vfs @ _PCCT-builder-stats
    _PCCT-builder-cache _PCCT-builder-guard
    ['] _PCCT-fault 0 _PCCT-builder-store PSTORE-INIT ;

: _PCCT-cold-store-init  ( -- status )
    S" /pc-b0-pages" S" /pc-b0-segment"
    S" /pc-root-a" S" /pc-root-b"
    _PCCT-identity 256 _PCCT-vfs @ _PCCT-cold-stats
    _PCCT-cold-cache _PCCT-cold-guard
    ['] _PCCT-fault 0 _PCCT-cold-store PSTORE-INIT ;

: _PCCT-callback-failure  ( status -- done? bytes-used status )
    0 0 ROT ;

: _PCCT-key-value  ( step -- key-a key-u value-a value-u )
    DUP 0= IF DROP S" alpha" S" one" EXIT THEN
    1 = IF S" beta" S" two" ELSE S" gamma" S" three" THEN ;

: _PCCT-other-root  ( root -- other-root )
    _PCCT-tree-root-a =
    IF _PCCT-tree-root-b ELSE _PCCT-tree-root-a THEN ;

: _PCCT-step-callback
  ( source-root builder-store builder-work allowance context -- done? bytes-used status )
    >R
    R@ _PCCT-context = _PCCT-context-seen !
    3 PICK _PCCT-callback-source !
    2 PICK _PCCT-callback-store !
    1 PICK _PCCT-callback-work !
    DUP _PCCT-callback-allowance !
    2DROP 2DROP
    R> DROP

    _PCCT-callback-mode @ 1 = IF
        0 _PCCT-callback-allowance @ 1+ PERSIST-S-OK EXIT
    THEN
    _PCCT-callback-mode @ 2 = IF -901 THROW THEN
    _PCCT-callback-allowance @ _PCCT-STEP-CHARGE < IF
        PERSIST-S-CAPACITY _PCCT-callback-failure EXIT
    THEN

    _PCCT-callback-store @ _PCCT-callback-work @ PSTORE-BEGIN
    DUP IF _PCCT-callback-failure EXIT THEN DROP
    _PCCT-record 24 _PCCT-builder-ref
        _PCCT-callback-store @ _PCCT-callback-work @
        PSTORE-APPEND-RECORD
    DUP IF _PCCT-callback-failure EXIT THEN DROP
    _PCCT-current-root @ _PCCT-other-root _PCCT-next-root !
    _PCCT-step-count @ _PCCT-key-value
    _PCCT-current-root @ _PCCT-next-root @
    _PCCT-builder-tree _PCCT-builder-tree-work PBTREE-PUT
    DUP IF _PCCT-callback-failure EXIT THEN DROP
    _PCCT-next-root @ PBTREE-ROOT-PAGE@
        _PCCT-callback-store @ _PCCT-callback-work @
        PSTORE-APPLICATION-ROOT!
    DUP IF _PCCT-callback-failure EXIT THEN DROP
    _PCCT-callback-store @ _PCCT-callback-work @ PSTORE-COMMIT
    DUP IF _PCCT-callback-failure EXIT THEN DROP
    _PCCT-next-root @ _PCCT-current-root !
    1 _PCCT-step-count +!
    _PCCT-step-count @ 3 =
    _PCCT-STEP-CHARGE PERSIST-S-OK ;

: _PCCT-finalize-callback
  ( exact-generation builder-store builder-work context -- status )
    >R
    R@ _PCCT-context = _PCCT-context-seen !
    2 PICK _PCCT-final-generation !
    1 PICK _PCCT-callback-store !
    DUP _PCCT-callback-work !
    2DROP DROP
    R> DROP
    _PCCT-finalize-fail @ IF PERSIST-S-FAULT EXIT THEN

    _PCCT-current-root @ _PCCT-final-generation @
        _PCCT-rebased-root _PCCT-builder-tree PBTREE-ROOT-REBASE
    DUP IF EXIT THEN DROP
    _PCCT-final-generation @
        _PCCT-empty-reclaim RECLAIM-STATE-SIZE
        RECLAIM-EMPTY-STATE-FOR-GENERATION
    DUP IF EXIT THEN DROP
    _PCCT-callback-store @ _PCCT-callback-work @ PSTORE-BEGIN
    DUP IF EXIT THEN DROP
    _PCCT-final-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PCCT-rebased-root _PCCT-final-page PBTREE-ROOT-SIZE MOVE
    _PCCT-empty-reclaim
        _PCCT-final-page PBTREE-ROOT-SIZE +
        RECLAIM-STATE-SIZE MOVE
    _PCCT-final-generation @
        _PCCT-final-page PBTREE-ROOT-SIZE RECLAIM-STATE-SIZE + + !
    _PCCT-final-page PERSIST-PAGE-PAYLOAD-SIZE
        _PCCT-callback-store @ _PCCT-callback-work @ PSTORE-APPEND-PAGE
    DUP IF NIP EXIT THEN
    DROP _PCCT-page-id !
    _PCCT-page-id @
        _PCCT-callback-store @ _PCCT-callback-work @
        PSTORE-APPLICATION-ROOT!
    DUP IF EXIT THEN DROP
    _PCCT-callback-store @ _PCCT-callback-work @ PSTORE-COMMIT ;

: _PCCT-setup  ( -- )
    VFS-CUR _PCCT-old-vfs !
    VFS-RAM-OPS _PCCT-ops VFS-OPS-SIZE MOVE
    VFS-RAM-BINDING _PCCT-binding VFS-BINDING-DESC-SIZE MOVE
    _PCCT-ops _PCCT-binding VB.OPS !
    33554432 A-XMEM ARENA-NEW DUP 0= _PCCT-assert DROP _PCCT-arena !
    _PCCT-arena @ _PCCT-binding 0 VFS-NEW _PCCT-ior ! _PCCT-vfs !
    _PCCT-ior @ 0= _PCCT-assert
    _PCCT-vfs @ 0<> _PCCT-assert

    _PCCT-identity PERSIST-IDENTITY-SIZE 83 FILL
    _PCCT-context 64 0 FILL
    _PCCT-record 64 0 FILL
    S" neutral opaque record" _PCCT-record SWAP MOVE
    _PCCT-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PCCT-final-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PCCT-source-ref PERSIST-REF-INIT
    _PCCT-builder-ref PERSIST-REF-INIT
    _PCCT-seed-ref PERSIST-REF-INIT

    _PCCT-source-stats PERSIST-STATS-INIT
    _PCCT-bank1-stats PERSIST-STATS-INIT
    _PCCT-builder-stats PERSIST-STATS-INIT
    _PCCT-cold-stats PERSIST-STATS-INIT
    _PCCT-source-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2
        _PCCT-source-cache PPAGE-CACHE-INIT PERSIST-S-OK _PCCT-status
    _PCCT-bank1-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2
        _PCCT-bank1-cache PPAGE-CACHE-INIT PERSIST-S-OK _PCCT-status
    _PCCT-builder-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2
        _PCCT-builder-cache PPAGE-CACHE-INIT PERSIST-S-OK _PCCT-status
    _PCCT-cold-cache-memory PERSIST-PAGE-CACHE-FRAME-SIZE 2 * 2
        _PCCT-cold-cache PPAGE-CACHE-INIT PERSIST-S-OK _PCCT-status

    S" /pc-b1-pages" _PCCT-vfs @ _PCCT-bank1-stats
        _PCCT-bank1-cache _PCCT-bank1-page PPAGE-FILE-INIT
        PERSIST-S-OK _PCCT-status
    S" /pc-b1-segment" 256 _PCCT-vfs @ _PCCT-bank1-stats
        _PCCT-bank1-segment PSEG-FILE-INIT PERSIST-S-OK _PCCT-status

    _PCCT-source-store-init PERSIST-S-OK _PCCT-status
    _PCCT-bank1-page _PCCT-bank1-segment _PCCT-source-store
        PSTORE-BANK1-CONFIGURE PERSIST-S-OK _PCCT-status
    _PCCT-source-buffer 512 _PCCT-source-work PSTORE-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-source-store _PCCT-source-work PSTORE-PROVISION
        PERSIST-S-OK _PCCT-status
    _PCCT-source-store _PCCT-source-work PSTORE-OPEN
        PERSIST-S-ABSENT _PCCT-status

    _PCCT-builder-store-init PERSIST-S-OK _PCCT-status
    _PCCT-bank1-page _PCCT-bank1-segment _PCCT-builder-store
        PSTORE-BANK1-CONFIGURE PERSIST-S-OK _PCCT-status
    _PCCT-builder-buffer 512 _PCCT-builder-work PSTORE-WORK-INIT
        PERSIST-S-OK _PCCT-status

    101 ['] PBTREE-HIGH-WATER-ALLOCATE 0
        _PCCT-builder-store _PCCT-builder-tree PBTREE-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-builder-work _PCCT-builder-tree-work PBTREE-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-builder-tree _PCCT-tree-root-a PBTREE-ROOT-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-tree-root-a _PCCT-current-root !

    _PCCT-observer-work PROOT-WORK-INIT PERSIST-S-OK _PCCT-status
    _PCCT-size-page-work PPAGE-WORK-INIT PERSIST-S-OK _PCCT-status
    _PCCT-size-segment-buffer 512 _PCCT-size-segment-work PSEG-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-compact-buffer-a 512 _PCCT-compact-work-a PCOMPACT-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-compact-buffer-b 512 _PCCT-compact-work-b PCOMPACT-WORK-INIT
        PERSIST-S-OK _PCCT-status ;

: _PCCT-source-first-commit  ( -- )
    _PCCT-source-store _PCCT-source-work PSTORE-BEGIN
        PERSIST-S-OK _PCCT-status
    _PCCT-record 24 _PCCT-source-ref
        _PCCT-source-store _PCCT-source-work PSTORE-APPEND-RECORD
        PERSIST-S-OK _PCCT-status
    _PCCT-source-ref _PCCT-page PERSIST-REF-SIZE MOVE
    _PCCT-page PERSIST-PAGE-PAYLOAD-SIZE
        _PCCT-source-store _PCCT-source-work PSTORE-APPEND-PAGE
    SWAP _PCCT-page-id ! PERSIST-S-OK _PCCT-status
    _PCCT-page-id @ _PCCT-source-store _PCCT-source-work
        PSTORE-APPLICATION-ROOT! PERSIST-S-OK _PCCT-status
    _PCCT-source-store _PCCT-source-work PSTORE-COMMIT
        PERSIST-S-OK _PCCT-status
    _PCCT-source-store PSTORE-GENERATION@ 1 = _PCCT-assert
    _PCCT-source-store PSTORE-CURRENT-ROOT@ PROOTV.DATA-BANK @
        PERSIST-DATA-BANK-0 = _PCCT-assert
    _PCCT-stack ;

: _PCCT-observe-authority  ( expected-generation expected-bank -- )
    >R
    _PCCT-observer-value
    _PCCT-source-store PSTORE-ROOT-FILE@
    _PCCT-observer-work PROOT-LOAD
    DUP PERSIST-S-OK = >R
    DROP _PCCT-observed-generation !
    R> _PCCT-assert
    _PCCT-observed-generation @ = _PCCT-assert
    _PCCT-observer-value PROOTV.DATA-BANK @ R> = _PCCT-assert
    _PCCT-stack ;

: _PCCT-page-size  ( bank -- bytes )
    _PCCT-source-store PSTORE-PAGE-FILE-FOR-BANK@
        _PCCT-size-page-work PPAGE-FILE-SIZE?
    DUP PERSIST-S-OK = _PCCT-assert DROP ;

: _PCCT-segment-size  ( bank -- bytes )
    _PCCT-source-store PSTORE-SEGMENT-FILE-FOR-BANK@
        _PCCT-size-segment-work PSEG-FILE-SIZE?
    DUP PERSIST-S-OK = _PCCT-assert DROP ;

: _PCCT-source-files-live  ( -- )
    PERSIST-DATA-BANK-0 _PCCT-page-size 0> _PCCT-assert
    PERSIST-DATA-BANK-0 _PCCT-segment-size 0> _PCCT-assert
    _PCCT-stack ;

: _PCCT-old-bank-empty  ( -- )
    PERSIST-DATA-BANK-0 _PCCT-page-size 0= _PCCT-assert
    PERSIST-DATA-BANK-0 _PCCT-segment-size 0= _PCCT-assert
    _PCCT-stack ;

: _PCCT-init-coordinator  ( -- )
    _PCCT-source-store PSTORE-ROOT-FILE@
    _PCCT-builder-store _PCCT-builder-work
    ['] _PCCT-step-callback ['] _PCCT-finalize-callback _PCCT-context
    16384 4 8192 _PCCT-compact PCOMPACT-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-compact PCOMPACT-VALID? _PCCT-assert
    _PCCT-stack ;

: _PCCT-compact-alias  ( -- compact )
    _PCCT-compact-alias-arena PERSIST-STATS-SIZE 8 - + ;

: _PCCT-snapshot-root-work  ( -- )
    _PCCT-source-store PSTORE-ROOT-FILE@
        _PCCT-root-snapshot PROOT-FILE-SIZE MOVE
    _PCCT-compact-work-b
        _PCCT-work-snapshot PCOMPACT-WORK-SIZE MOVE ;

: _PCCT-root-work-unchanged  ( -- )
    _PCCT-source-store PSTORE-ROOT-FILE@ PROOT-FILE-SIZE
        _PCCT-root-snapshot PROOT-FILE-SIZE COMPARE 0= _PCCT-assert
    _PCCT-compact-work-b PCOMPACT-WORK-SIZE
        _PCCT-work-snapshot PCOMPACT-WORK-SIZE COMPARE 0= _PCCT-assert
    _PCCT-stack ;

\ The shared-root graph includes its optional stats object.  Coordinator
\ initialization and BEGIN must reject every public mutable span that reaches
\ those stats before zeroing either destination.  Each rejection is an exact
\ byte-for-byte no-effect preflight.
: _PCCT-root-stats-alias-preflight  ( -- )
    _PCCT-source-store PSTORE-ROOT-FILE@ _PROOT-F.STATS @
        _PCCT-saved-root-stats !

    \ The immutable coordinator descriptor may only partially overlap stats;
    \ the valid stats tail supplies the overlapping destination sentinel.
    _PCCT-compact-alias PCOMPACT-SIZE 165 FILL
    _PCCT-compact-alias-arena PERSIST-STATS-INIT
    _PCCT-compact-alias
        _PCCT-compact-snapshot PCOMPACT-SIZE MOVE
    _PCCT-compact-alias-arena
        _PCCT-source-store PSTORE-ROOT-FILE@ _PROOT-F.STATS !
    _PCCT-source-store PSTORE-ROOT-FILE@ PROOT-VALID? _PCCT-assert
    _PCCT-source-store PSTORE-ROOT-FILE@
        _PCCT-root-snapshot PROOT-FILE-SIZE MOVE
    _PCCT-source-store PSTORE-ROOT-FILE@
    _PCCT-builder-store _PCCT-builder-work
    ['] _PCCT-step-callback ['] _PCCT-finalize-callback _PCCT-context
    16384 4 8192 _PCCT-compact-alias PCOMPACT-INIT
        PERSIST-S-INVALID _PCCT-status
    _PCCT-source-store PSTORE-ROOT-FILE@ PROOT-FILE-SIZE
        _PCCT-root-snapshot PROOT-FILE-SIZE COMPARE 0= _PCCT-assert
    _PCCT-compact-alias PCOMPACT-SIZE
        _PCCT-compact-snapshot PCOMPACT-SIZE COMPARE 0= _PCCT-assert
    _PCCT-saved-root-stats @
        _PCCT-source-store PSTORE-ROOT-FILE@ _PROOT-F.STATS !

    \ A separately valid work descriptor may borrow the stats span as its
    \ segment buffer.  BEGIN must reject it without touching either object.
    _PCCT-source-stats _PCCT-stats-snapshot
        PERSIST-STATS-SIZE MOVE
    _PCCT-source-stats PERSIST-STATS-SIZE
        _PCCT-compact-work-b PCOMPACT-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-snapshot-root-work
    _PCCT-compact _PCCT-compact-work-b PCOMPACT-BEGIN
        PERSIST-S-INVALID _PCCT-status
    _PCCT-root-work-unchanged
    _PCCT-source-stats PERSIST-STATS-SIZE
        _PCCT-stats-snapshot PERSIST-STATS-SIZE COMPARE 0= _PCCT-assert
    _PCCT-compact-buffer-b 512
        _PCCT-compact-work-b PCOMPACT-WORK-INIT
        PERSIST-S-OK _PCCT-status

    \ The work span itself is also rejected when its otherwise-unused idle
    \ root scratch owns the shared stats object.
    _PCCT-compact-work-b _PCW.SOURCE-ROOT PERSIST-STATS-INIT
    _PCCT-compact-work-b _PCW.SOURCE-ROOT
        _PCCT-source-store PSTORE-ROOT-FILE@ _PROOT-F.STATS !
    _PCCT-source-store PSTORE-ROOT-FILE@ PROOT-VALID? _PCCT-assert
    _PCCT-compact-work-b PCOMPACT-WORK-VALID? _PCCT-assert
    _PCCT-snapshot-root-work
    _PCCT-compact _PCCT-compact-work-b PCOMPACT-BEGIN
        PERSIST-S-INVALID _PCCT-status
    _PCCT-root-work-unchanged
    _PCCT-saved-root-stats @
        _PCCT-source-store PSTORE-ROOT-FILE@ _PROOT-F.STATS !
    _PCCT-compact-buffer-b 512
        _PCCT-compact-work-b PCOMPACT-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-source-store PSTORE-VALID? _PCCT-assert
    _PCCT-compact PCOMPACT-VALID? _PCCT-assert
    _PCCT-stack ;

: _PCCT-build-and-fault-publish  ( -- )
    _PCCT-compact _PCCT-compact-work-a PCOMPACT-BEGIN
        PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-BUILDING = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-SOURCE-BANK@
        PERSIST-DATA-BANK-0 = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-TARGET-BANK@
        PERSIST-DATA-BANK-1 = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-NEXT-GENERATION@ 2 = _PCCT-assert
    GPAIR-SLOT-A _PCCT-source-store PSTORE-ROOT-FILE@
        PROOT-SLOT-GENERATION@ 1 = _PCCT-assert
    GPAIR-SLOT-B _PCCT-source-store PSTORE-ROOT-FILE@
        PROOT-SLOT-GENERATION@ 1 = _PCCT-assert

    1 _PCCT-callback-mode !
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-CAPACITY _PCCT-status
    _PCCT-compact-work-a PCOMPACT-BYTES-USED@ 0= _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-WORK-USED@ 0= _PCCT-assert
    1 PERSIST-DATA-BANK-0 _PCCT-observe-authority
    _PCCT-source-files-live

    2 _PCCT-callback-mode !
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-FAULT _PCCT-status
    _PCCT-compact-work-a PCOMPACT-WORK-USED@ 0= _PCCT-assert
    1 PERSIST-DATA-BANK-0 _PCCT-observe-authority

    0 _PCCT-callback-mode !
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-READY = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-WORK-USED@ 3 = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-BYTES-USED@
        _PCCT-STEP-CHARGE 3 * = _PCCT-assert
    _PCCT-builder-store PSTORE-GENERATION@ 3 = _PCCT-assert
    _PCCT-context-seen @ _PCCT-assert

    -1 _PCCT-finalize-fail !
    _PCCT-compact-work-a PCOMPACT-FINALIZE
        PERSIST-S-FAULT _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-READY = _PCCT-assert
    1 PERSIST-DATA-BANK-0 _PCCT-observe-authority
    _PCCT-source-files-live

    0 _PCCT-finalize-fail !
    _PCCT-compact-work-a PCOMPACT-FINALIZE PERSIST-S-OK _PCCT-status
    _PCCT-final-generation @ 2 = _PCCT-assert
    _PCCT-builder-store PSTORE-GENERATION@ 4 = _PCCT-assert
    _PCCT-rebased-root PBTREE-ROOT-GENERATION@ 2 = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-FINALIZED = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-CLEANUP
        PERSIST-S-CONFLICT _PCCT-status
    _PCCT-source-files-live

    PERSIST-FAULT-ROOT-SYNCED _PCCT-fault-at !
    _PCCT-compact-work-a PCOMPACT-PUBLISH
        PERSIST-S-FAULT _PCCT-status
    0 _PCCT-fault-at !
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-UNCERTAIN = _PCCT-assert
    2 PERSIST-DATA-BANK-1 _PCCT-observe-authority
    _PCCT-source-files-live
    _PCCT-stack ;

: _PCCT-cold-recover-published  ( -- )
    _PCCT-compact _PCCT-compact-work-b PCOMPACT-RECOVER
        PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-b PCOMPACT-STATE@
        PCOMPACT-STATE-CLEANED = _PCCT-assert
    _PCCT-compact-work-b PCOMPACT-NEXT-GENERATION@ 2 = _PCCT-assert
    _PCCT-compact-work-b PCOMPACT-TARGET-BANK@
        PERSIST-DATA-BANK-1 = _PCCT-assert
    _PCCT-compact-work-b PCOMPACT-CLEANUP-ELIGIBLE? _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-UNCERTAIN = _PCCT-assert
    2 PERSIST-DATA-BANK-1 _PCCT-observe-authority
    _PCCT-old-bank-empty
    _PCCT-stack ;

: _PCCT-seed-old-bank  ( -- )
    _PCCT-page PERSIST-PAGE-PAYLOAD-SIZE 37 FILL
    _PCCT-page PERSIST-PAGE-PAYLOAD-SIZE 0
        PERSIST-DATA-BANK-0 _PCCT-source-store
        PSTORE-PAGE-FILE-FOR-BANK@
        _PCCT-size-page-work PPAGE-WRITE PERSIST-S-OK _PCCT-status
    _PCCT-record 24 1 0 _PCCT-seed-ref
        PERSIST-DATA-BANK-0 _PCCT-source-store
        PSTORE-SEGMENT-FILE-FOR-BANK@
        _PCCT-size-segment-work PSEG-WRITE PERSIST-S-OK _PCCT-status
    PERSIST-DATA-BANK-0 _PCCT-source-store
        PSTORE-PAGE-FILE-FOR-BANK@ PPAGE-SYNC
        PERSIST-S-OK _PCCT-status
    PERSIST-DATA-BANK-0 _PCCT-source-store
        PSTORE-SEGMENT-FILE-FOR-BANK@ PSEG-SYNC
        PERSIST-S-OK _PCCT-status
    _PCCT-source-files-live ;

: _PCCT-cold-recover-mirrored  ( -- )
    _PCCT-seed-old-bank
    _PCCT-compact _PCCT-compact-work-a PCOMPACT-RECOVER
        PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-CLEANED = _PCCT-assert
    _PCCT-compact-work-b PCOMPACT-STATE@
        PCOMPACT-STATE-CLEANED = _PCCT-assert
    2 PERSIST-DATA-BANK-1 _PCCT-observe-authority
    _PCCT-old-bank-empty
    _PCCT-stack ;

: _PCCT-expect-alpha  ( -- )
    S" alpha" _PCCT-cold-root _PCCT-cold-tree _PCCT-cold-tree-work
        PBTREE-GET
    PERSIST-S-OK = >R
    S" one" COMPARE 0= R> AND _PCCT-assert _PCCT-stack ;

: _PCCT-expect-beta  ( -- )
    S" beta" _PCCT-cold-root _PCCT-cold-tree _PCCT-cold-tree-work
        PBTREE-GET
    PERSIST-S-OK = >R
    S" two" COMPARE 0= R> AND _PCCT-assert _PCCT-stack ;

: _PCCT-expect-gamma  ( -- )
    S" gamma" _PCCT-cold-root _PCCT-cold-tree _PCCT-cold-tree-work
        PBTREE-GET
    PERSIST-S-OK = >R
    S" three" COMPARE 0= R> AND _PCCT-assert _PCCT-stack ;

: _PCCT-cold-open-and-query  ( expected-generation expected-bank -- )
    _PCCT-expected-bank !
    _PCCT-expected-generation !
    _PCCT-cold-store-init PERSIST-S-OK _PCCT-status
    _PCCT-bank1-page _PCCT-bank1-segment _PCCT-cold-store
        PSTORE-BANK1-CONFIGURE PERSIST-S-OK _PCCT-status
    _PCCT-cold-buffer 512 _PCCT-cold-work PSTORE-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-cold-store _PCCT-cold-work PSTORE-OPEN-ACTIVE
        PERSIST-S-OK _PCCT-status
    _PCCT-cold-store PSTORE-GENERATION@
        _PCCT-expected-generation @ = _PCCT-assert
    _PCCT-cold-store PSTORE-EXPECTED-DATA-BANK@
        _PCCT-expected-bank @ = _PCCT-assert
    _PCCT-cold-store PSTORE-CURRENT-ROOT@ PROOTV.DATA-BANK @
        _PCCT-expected-bank @ = _PCCT-assert
    _PCCT-cold-store PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _PCCT-cold-store _PCCT-cold-work PSTORE-READ-PAGE
        PERSIST-S-OK _PCCT-status
    _PCCT-cold-work PSTORE-PAGE-PAYLOAD$ DROP
        DUP _PCCT-cold-root PBTREE-ROOT-SIZE MOVE
        DUP PBTREE-ROOT-SIZE + _PCCT-cold-reclaim-state
            RECLAIM-STATE-SIZE MOVE
        PBTREE-ROOT-SIZE RECLAIM-STATE-SIZE + + @
            _PCCT-expected-generation @ = _PCCT-assert

    101 ['] PBTREE-HIGH-WATER-ALLOCATE 0
        _PCCT-cold-store _PCCT-cold-tree PBTREE-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-cold-work _PCCT-cold-tree-work PBTREE-WORK-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-cold-root _PCCT-cold-tree PBTREE-ROOT-VALID? _PCCT-assert
    _PCCT-cold-root PBTREE-ROOT-GENERATION@
        _PCCT-expected-generation @ = _PCCT-assert
    _PCCT-cold-root PBTREE-ROOT-CARDINALITY@ 3 = _PCCT-assert
    _PCCT-expect-alpha
    _PCCT-expect-beta
    _PCCT-expect-gamma

    _PCCT-cold-reclaim RECLAIM-INIT PERSIST-S-OK _PCCT-status
    _PCCT-cold-reclaim-state RECLAIM-STATE-SIZE
        _PCCT-cold-store _PCCT-cold-reclaim RECLAIM-OPEN
        PERSIST-S-OK _PCCT-status
    _PCCT-cold-reclaim RECLAIM-GENERATION@
        _PCCT-expected-generation @ = _PCCT-assert
    _PCCT-cold-reclaim RECLAIM-RETIRED-COUNT@ 0= _PCCT-assert
    _PCCT-cold-reclaim RECLAIM-REUSABLE-COUNT@ 0= _PCCT-assert
    _PCCT-stack ;

: _PCCT-observe-builder-private  ( expected-generation -- )
    >R
    _PCCT-observer-value
    _PCCT-builder-store PSTORE-ROOT-FILE@
    _PCCT-observer-work PROOT-LOAD
    DUP PERSIST-S-OK = _PCCT-assert
    DROP R> = _PCCT-assert
    _PCCT-stack ;

: _PCCT-complete-opposite-cycle-reusing-all  ( -- )
    \ A rejected reset is non-destructive: active transaction ownership is
    \ detected before either private root path is removed.
    4 _PCCT-observe-builder-private
    _PCCT-builder-store _PCCT-builder-work PSTORE-BEGIN
        PERSIST-S-OK _PCCT-status
    _PCCT-builder-store _PCCT-builder-work PSTORE-STAGING-RESET
        PERSIST-S-BUSY _PCCT-status
    _PCCT-builder-store PSTORE-GENERATION@ 4 = _PCCT-assert
    4 _PCCT-observe-builder-private
    _PCCT-builder-store _PCCT-builder-work PSTORE-ABORT
        PERSIST-S-OK _PCCT-status

    \ Reuse the exact coordinator, staging descriptor/workspace, private root
    \ paths, and CLEANED operation work in the opposite bank direction.
    _PCCT-compact _PCCT-compact-work-a PCOMPACT-BEGIN
        PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-SOURCE-BANK@
        PERSIST-DATA-BANK-1 = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-TARGET-BANK@
        PERSIST-DATA-BANK-0 = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-NEXT-GENERATION@ 3 = _PCCT-assert
    _PCCT-builder-store PSTORE-GENERATION@ 0= _PCCT-assert
    _PCCT-builder-store PSTORE-EXPECTED-DATA-BANK@
        PERSIST-DATA-BANK-0 = _PCCT-assert

    0 _PCCT-step-count !
    _PCCT-builder-tree _PCCT-tree-root-a PBTREE-ROOT-INIT
        PERSIST-S-OK _PCCT-status
    _PCCT-tree-root-a _PCCT-current-root !
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STEP PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-FINALIZE PERSIST-S-OK _PCCT-status
    _PCCT-final-generation @ 3 = _PCCT-assert
    _PCCT-compact-work-a PCOMPACT-PUBLISH PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-MIRROR PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-CLEANUP PERSIST-S-OK _PCCT-status
    _PCCT-compact-work-a PCOMPACT-STATE@
        PCOMPACT-STATE-CLEANED = _PCCT-assert
    3 PERSIST-DATA-BANK-0 _PCCT-observe-authority
    PERSIST-DATA-BANK-1 _PCCT-page-size 0= _PCCT-assert
    PERSIST-DATA-BANK-1 _PCCT-segment-size 0= _PCCT-assert
    _PCCT-stack ;

: _PCCT-recover-absent-stack  ( -- )
    \ Exercise the recover-load failure arm after all durable checks are done.
    \ It must return exactly one status cell.
    _PCCT-source-store PSTORE-ROOT-FILE@ DUP PROOT-PATH-A$
        _PCCT-vfs @ VFS-RM 0= _PCCT-assert
    PROOT-PATH-B$ _PCCT-vfs @ VFS-RM 0= _PCCT-assert
    _PCCT-vfs @ VFS-SYNC 0= _PCCT-assert
    _PCCT-compact _PCCT-compact-work-b PCOMPACT-RECOVER
        PERSIST-S-ABSENT _PCCT-status
    _PCCT-stack ;

: _PCCT-RUN  ( -- )
    0 _PCCT-fails !
    0 _PCCT-checks !
    DEPTH _PCCT-depth !
    0 _PCCT-fault-at !
    0 _PCCT-callback-mode !
    0 _PCCT-finalize-fail !
    0 _PCCT-step-count !
    0 _PCCT-context-seen !
    _PCCT-setup
    _PCCT-source-first-commit
    _PCCT-init-coordinator
    _PCCT-root-stats-alias-preflight
    _PCCT-build-and-fault-publish
    _PCCT-cold-recover-published
    _PCCT-cold-recover-mirrored
    2 PERSIST-DATA-BANK-1 _PCCT-cold-open-and-query
    _PCCT-complete-opposite-cycle-reusing-all
    3 PERSIST-DATA-BANK-0 _PCCT-cold-open-and-query
    _PCCT-recover-absent-stack
    _PCCT-old-vfs @ VFS-USE
    _PCCT-vfs @ VFS-DESTROY
    _PCCT-stack
    _PCCT-fails @ 0= IF
        ." PERSISTENCE COMPACTION PASS " _PCCT-checks @ . CR
    ELSE
        ." PERSISTENCE COMPACTION FAIL "
        _PCCT-fails @ . ." /" _PCCT-checks @ . CR
    THEN ;
