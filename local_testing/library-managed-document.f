\ =====================================================================
\  Gate 4 milestone 1: public managed-document vertical slice
\ =====================================================================

VARIABLE _lmd-fails
VARIABLE _lmd-checks
VARIABLE _lmd-depth
VARIABLE _lmd-store-slot
VARIABLE _lmd-vfs
VARIABLE _lmd-old-vfs
VARIABLE _lmd-arena
VARIABLE _lmd-status
VARIABLE _lmd-required
VARIABLE _lmd-count
VARIABLE _lmd-next
VARIABLE _lmd-generation
VARIABLE _lmd-arm-stage
VARIABLE _lmd-arm-status
VARIABLE _lmd-stage-mask
VARIABLE _lmd-read-faults
VARIABLE _lmd-write-calls
VARIABLE _lmd-random-calls
VARIABLE _lmd-close-calls
VARIABLE _lmd-close-fail-at
VARIABLE _lmd-old-delete-xt
VARIABLE _lmd-old-sync-xt
VARIABLE _lmd-head-sync-armed
VARIABLE _lmd-head-sync-failed

CREATE _lmd-arena-id LIB-DIGEST-SIZE ALLOT
CREATE _lmd-key-a LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmd-key-b LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmd-key-c LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmd-key-d LIB-OPERATION-KEY-SIZE ALLOT
CREATE _lmd-request LIBRARY-MANAGED-CREATE-REQUEST-SIZE ALLOT
CREATE _lmd-result-a LIB-ENTRY-SIZE ALLOT
CREATE _lmd-result-b LIB-ENTRY-SIZE ALLOT
CREATE _lmd-result-c LIB-ENTRY-SIZE ALLOT
CREATE _lmd-read-entry LIB-ENTRY-SIZE ALLOT
CREATE _lmd-read-content LIB-CONTENT-SIZE ALLOT
CREATE _lmd-summary LIBRARY-QUERY-SUMMARY-SIZE ALLOT
CREATE _lmd-head-before LIB-HEAD-FACT-SIZE ALLOT
CREATE _lmd-ops VFS-OPS-SIZE ALLOT
CREATE _lmd-binding VFS-BINDING-DESC-SIZE ALLOT
LIB-CONTENT-MAX XBUF _lmd-bytes

: _lmd-store  ( -- store ) _lmd-store-slot @ ;

: _lmd-assert  ( flag -- )
    1 _lmd-checks +!
    0= IF
        1 _lmd-fails +!
        ." LIBRARY MANAGED ASSERT " _lmd-checks @ . CR
    THEN ;

: _lmd-stack  ( -- )
    DEPTH DUP _lmd-depth @ <> IF
        ." LIBRARY MANAGED STACK " _lmd-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _lmd-depth @ = _lmd-assert ;

: _lmd-zero?  ( a u -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _lmd-request!  ( key expected-generation -- )
    _lmd-request LIBRARY-MANAGED-CREATE-REQUEST-INIT
    _lmd-request LIBMCR.EXPECTED-CATALOG-GENERATION !
    _lmd-request LIBRARY-MANAGED-CREATE-OPERATION-KEY!
        LIBSTORE-S-OK = _lmd-assert
    S" Milestone one" _lmd-request LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lmd-assert
    S" content-first managed document" _lmd-request
        LIBRARY-MANAGED-CREATE-CONTENT!
        LIBSTORE-S-OK = _lmd-assert
    LIB-MEDIA-TEXT-MARKDOWN _lmd-request LIBMCR.MEDIA !
    _lmd-request LIBRARY-MANAGED-CREATE-REQUEST-VALID? _lmd-assert ;

: _lmd-query  ( expected start -- )
    _lmd-summary 1 _lmd-store LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lmd-status ! _lmd-generation ! _lmd-next ! _lmd-count ! ;

: _lmd-read  ( rid revision capacity -- )
    >R _lmd-bytes R> _lmd-read-entry _lmd-read-content _lmd-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lmd-status ! _lmd-required ! ;

: _lmd-checkpoint  ( stage -- status )
    DUP 1- 1 SWAP LSHIFT _lmd-stage-mask @ OR _lmd-stage-mask !
    DUP _lmd-arm-stage @ = IF DROP _lmd-arm-status @ EXIT THEN
    DROP LIBSTORE-S-OK ;

: _lmd-read-once-fault  ( destination length fd -- ior )
    _lmd-read-faults @ IF
        -1 _lmd-read-faults +! 2DROP DROP -1 EXIT
    THEN
    VFS-READ-EXACT ;

: _lmd-readback-checkpoint  ( stage -- status )
    DUP 1- 1 SWAP LSHIFT _lmd-stage-mask @ OR _lmd-stage-mask !
    4 = IF
        1 _lmd-read-faults !
        ['] _lmd-read-once-fault _LIBVFS-READ-EXACT-XT !
    THEN
    LIBSTORE-S-OK ;

: _lmd-count-write  ( source length fd -- ior )
    1 _lmd-write-calls +! VFS-WRITE-EXACT ;

: _lmd-count-random  ( -- value )
    1 _lmd-random-calls +! RANDOM ;

: _lmd-count-close  ( fd -- )
    1 _lmd-close-calls +!
    VFS-CLOSE
    _lmd-close-fail-at @
        _lmd-close-calls @ = IF -7501 THROW THEN ;

: _lmd-arm-head-sync  ( inode vfs -- ior )
    _lmd-old-delete-xt @ EXECUTE
    DUP 0= _lmd-head-sync-failed @ 0= AND IF
        -1 _lmd-head-sync-armed !
    THEN ;

: _lmd-fail-armed-sync  ( vfs -- ior )
    _lmd-head-sync-armed @ IF
        0 _lmd-head-sync-armed !
        -1 _lmd-head-sync-failed !
        DROP -1 EXIT
    THEN
    _lmd-old-sync-xt @ EXECUTE ;

: _lmd-head-fault-begin  ( -- )
    _lmd-ops VFS-OP-SYNCFS CELLS + @ _lmd-old-sync-xt !
    _lmd-ops VFS-OP-UNLINK CELLS + @ _lmd-old-delete-xt !
    ['] _lmd-arm-head-sync _lmd-ops VFS-OP-UNLINK CELLS + !
    ['] _lmd-fail-armed-sync _lmd-ops VFS-OP-SYNCFS CELLS + !
    0 _lmd-head-sync-armed ! 0 _lmd-head-sync-failed ! ;

: _lmd-head-fault-end  ( -- )
    _lmd-old-delete-xt @ _lmd-ops VFS-OP-UNLINK CELLS + !
    _lmd-old-sync-xt @ _lmd-ops VFS-OP-SYNCFS CELLS + ! ;

: _lmd-uncertain-checkpoint  ( stage -- status )
    DUP 1- 1 SWAP LSHIFT _lmd-stage-mask @ OR _lmd-stage-mask !
    5 = IF _lmd-head-fault-begin THEN
    LIBSTORE-S-OK ;

: _lmd-arm  ( stage status -- )
    _lmd-arm-status ! _lmd-arm-stage ! 0 _lmd-stage-mask !
    ['] _lmd-checkpoint _LIBMU-CHECKPOINT-XT ! ;

: _lmd-disarm  ( -- )
    _LIBVFS-RESET-VFS-HOOKS _LIBVFS-RESET-MUTATION-HOOKS
    0 _lmd-arm-stage ! 0 _lmd-arm-status ! ;

: _lmd-head-snapshot  ( -- )
    _lmd-store LIBRARY-VFS-STORE.HEAD _lmd-head-before
        LIB-HEAD-FACT-SIZE CMOVE ;

: _lmd-head-unchanged?  ( -- flag )
    _lmd-store LIBRARY-VFS-STORE.HEAD LIB-HEAD-FACT-SIZE
        _lmd-head-before LIB-HEAD-FACT-SIZE COMPARE 0= ;

: _lmd-basic-create  ( -- )
    _lmd-key-a 1 _lmd-request!
    _lmd-request _lmd-result-a _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lmd-assert
    _lmd-result-a LIB-ENTRY-VALID? _lmd-assert
    _lmd-result-a LIBE.ID RID-PRESENT? _lmd-assert
    _lmd-result-a LIBE.ID _lmd-key-a RID= 0= _lmd-assert
    _lmd-result-a LIBE.KIND @ LIB-KIND-MANAGED-DOCUMENT = _lmd-assert
    _lmd-result-a LIBE.LIFECYCLE @ LIB-LIFECYCLE-ACTIVE = _lmd-assert
    _lmd-result-a LIBE.DOMAIN-REVISION @ 1 = _lmd-assert
    _lmd-result-a LIBE.CURRENT-CONTENT-REVISION @ 1 = _lmd-assert
    _lmd-result-a LIBE.RECEIPT LIBR.OPERATION-KEY
        _lmd-key-a RID= _lmd-assert
    _lmd-result-a LIBE.RECEIPT LIBR.EXPECTED-CATALOG-GENERATION @
        1 = _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.BANK LIBBF.CATALOG-COUNT @
        1 = _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.BANK LIBBF.CONTENT-RECORD-COUNT @
        1 = _lmd-assert
    _lmd-stack ;

: _lmd-query-read  ( -- )
    0 0 _lmd-query
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-count @ 1 = _lmd-assert
    _lmd-next @ -1 = _lmd-assert
    _lmd-generation @ 2 = _lmd-assert
    _lmd-summary LIBQS.REF RREF-VALID? _lmd-assert
    _lmd-summary LIBQS.REF RREF.ID
        _lmd-result-a LIBE.ID RID= _lmd-assert
    _lmd-summary LIBQS.DOMAIN-REVISION @ 1 = _lmd-assert
    _lmd-summary LIBQS.KIND @ LIB-KIND-MANAGED-DOCUMENT = _lmd-assert
    _lmd-summary LIBQS.LIFECYCLE @ LIB-LIFECYCLE-ACTIVE = _lmd-assert
    _lmd-summary LIBQS-TITLE$ S" Milestone one" COMPARE 0= _lmd-assert
    _lmd-result-a LIBE.ID 1 LIB-CONTENT-MAX _lmd-read
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-required @ 30 = _lmd-assert
    _lmd-read-entry LIB-ENTRY-VALID? _lmd-assert
    _lmd-read-content LIB-CONTENT-VALID? _lmd-assert
    _lmd-read-content LIBCT.DATA-A @ _lmd-bytes = _lmd-assert
    _lmd-read-content LIBCT-DATA$
        S" content-first managed document" COMPARE 0= _lmd-assert
    _lmd-read-entry LIB-ENTRY-SIZE _lmd-result-a LIB-ENTRY-SIZE COMPARE
        0= _lmd-assert
    _lmd-stack ;

: _lmd-idempotency  ( -- )
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    0 _lmd-write-calls ! 0 _lmd-random-calls !
    ['] _lmd-count-write _LIBVFS-WRITE-EXACT-XT !
    ['] _lmd-count-random _LIBMU-RANDOM-XT !
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lmd-assert
    _lmd-result-b LIBE.ID _lmd-result-a LIBE.ID RID= _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-result-a LIB-ENTRY-SIZE
        COMPARE 0= _lmd-assert
    _lmd-write-calls @ 0= _lmd-assert
    _lmd-random-calls @ 0= _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmd-assert
    _lmd-disarm
    S" changed title" _lmd-request LIBRARY-MANAGED-CREATE-TITLE!
        LIBSTORE-S-OK = _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-IDEMPOTENCY-MISMATCH = _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-stack ;

: _lmd-public-failures  ( -- )
    _lmd-result-a LIBE.ID 1 29 _lmd-read
    _lmd-status @ LIBSTORE-S-OUTPUT-CAPACITY = _lmd-assert
    _lmd-required @ 30 = _lmd-assert
    _lmd-read-entry LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-read-content LIB-CONTENT-SIZE _lmd-zero? _lmd-assert
    _lmd-read-entry LIB-ENTRY-SIZE 165 FILL
    _lmd-read-content LIB-CONTENT-SIZE 165 FILL
    _lmd-result-a LIBE.ID 1 LIB-CONTENT-MAX 1+ _lmd-read
    _lmd-status @ LIBSTORE-S-OUTPUT-CAPACITY = _lmd-assert
    _lmd-required @ 0= _lmd-assert
    _lmd-read-entry C@ 165 = _lmd-assert
    _lmd-read-entry LIB-ENTRY-SIZE 1- + C@ 165 = _lmd-assert
    _lmd-read-content C@ 165 = _lmd-assert
    _lmd-read-content LIB-CONTENT-SIZE 1- + C@ 165 = _lmd-assert
    _lmd-summary LIBRARY-QUERY-SUMMARY-SIZE 165 FILL
    0 0 _lmd-summary LIBRARY-QUERY-PAGE-MAX 1+ _lmd-store
        LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lmd-status ! _lmd-generation ! _lmd-next ! _lmd-count !
    _lmd-status @ LIBSTORE-S-OUTPUT-CAPACITY = _lmd-assert
    _lmd-summary C@ 165 = _lmd-assert
    _lmd-summary LIBRARY-QUERY-SUMMARY-SIZE 1- + C@ 165 = _lmd-assert
    _lmd-result-a LIBE.ID 1 _lmd-bytes LIB-CONTENT-MAX
        _LIBM-PRIVATE-BEGIN _lmd-read-content _lmd-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lmd-status ! _lmd-required !
    _lmd-status @ LIBSTORE-S-INVALID = _lmd-assert
    _lmd-required @ 0= _lmd-assert
    0 0 _LIBRC-PRIVATE-BEGIN 1 _lmd-store
        LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lmd-status ! _lmd-generation ! _lmd-next ! _lmd-count !
    _lmd-status @ LIBSTORE-S-INVALID = _lmd-assert
    _lmd-result-a LIBE.ID 1 _lmd-bytes LIB-CONTENT-MAX
        _lib-model-guard _lmd-read-content _lmd-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lmd-status ! _lmd-required !
    _lmd-status @ LIBSTORE-S-INVALID = _lmd-assert
    0 0 _lib-codec-guard 1 _lmd-store
        LIBRARY-VFS-STORE-QUERY-ACTIVE
    _lmd-status ! _lmd-generation ! _lmd-next ! _lmd-count !
    _lmd-status @ LIBSTORE-S-INVALID = _lmd-assert
    _lmd-result-a LIBE.ID 1 _lmd-bytes LIB-CONTENT-MAX
        _UD-CP _lmd-read-content _lmd-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lmd-status ! _lmd-required !
    _lmd-status @ LIBSTORE-S-INVALID = _lmd-assert
    _lmd-result-a LIBE.ID 1 _lmd-bytes LIB-CONTENT-MAX
        _QLOC-GUARD _lmd-read-content _lmd-store
        LIBRARY-VFS-STORE-READ-MANAGED-EXACT
    _lmd-status ! _lmd-required !
    _lmd-status @ LIBSTORE-S-INVALID = _lmd-assert
    2 0 _lmd-query
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-generation @ 2 = _lmd-assert
    1 0 _lmd-query
    _lmd-status @ LIBSTORE-S-CONFLICT = _lmd-assert
    _lmd-count @ 0= _lmd-assert
    _lmd-generation @ 2 = _lmd-assert
    _lmd-stack ;

: _lmd-cleanup-before-publication  ( -- )
    0 _lmd-close-calls ! 0 _lmd-close-fail-at !
    ['] _lmd-count-close _LIBVFS-CLOSE-XT !
    _lmd-result-b LIBE.ID 1 LIB-CONTENT-MAX _lmd-read
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-close-calls @ DUP 0> _lmd-assert _lmd-close-fail-at !
    0 _lmd-close-calls !
    _lmd-bytes LIB-CONTENT-MAX 165 FILL
    _lmd-read-entry LIB-ENTRY-SIZE 165 FILL
    _lmd-read-content LIB-CONTENT-SIZE 165 FILL
    _lmd-result-b LIBE.ID 1 LIB-CONTENT-MAX _lmd-read
    _lmd-status @ LIBSTORE-S-IO = _lmd-assert
    _lmd-required @ 30 = _lmd-assert
    _lmd-bytes C@ 165 = _lmd-assert
    _lmd-bytes LIB-CONTENT-MAX 1- + C@ 165 = _lmd-assert
    _lmd-read-entry LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-read-content LIB-CONTENT-SIZE _lmd-zero? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE-CLEANUP-FAILED? _lmd-assert
    _lmd-disarm
    _lmd-stack ;

: _lmd-mutation-boundaries  ( -- )
    _lmd-key-b 2 _lmd-request!
    _lmd-head-snapshot

    0 _lmd-write-calls !
    1 LIBSTORE-S-IO _lmd-arm
    ['] _lmd-count-write _LIBVFS-WRITE-EXACT-XT !
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-IO = _lmd-assert
    _lmd-stage-mask @ 1 = _lmd-assert
    _lmd-write-calls @ 0= _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-head-unchanged? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmd-assert
    _lmd-disarm

    2 LIBSTORE-S-IO _lmd-arm
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-IO = _lmd-assert
    _lmd-stage-mask @ 3 = _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-head-unchanged? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmd-assert
    _lmd-disarm

    3 LIBSTORE-S-IO _lmd-arm
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-IO = _lmd-assert
    _lmd-stage-mask @ 7 = _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-head-unchanged? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmd-assert
    _lmd-disarm

    0 _lmd-stage-mask ! 0 _lmd-read-faults !
    ['] _lmd-readback-checkpoint _LIBMU-CHECKPOINT-XT !
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-IO = _lmd-assert
    _lmd-stage-mask @ 15 = _lmd-assert
    _lmd-read-faults @ 0= _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-head-unchanged? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmd-assert
    _lmd-disarm

    0 0 _lmd-query
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-count @ 1 = _lmd-assert
    _lmd-stack ;

: _lmd-interrupt-before-head  ( -- )
    _lmd-key-b 2 _lmd-request!
    5 LIBSTORE-S-IO _lmd-arm
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-IO = _lmd-assert
    _lmd-stage-mask @ 31 = _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 2 = _lmd-assert
    0 0 _lmd-query
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-count @ 1 = _lmd-assert
    _lmd-disarm
    _lmd-stack ;

: _lmd-lost-response  ( -- )
    _lmd-key-c 2 _lmd-request!
    6 LIBSTORE-S-IO _lmd-arm
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-IO = _lmd-assert
    _lmd-stage-mask @ 63 = _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-zero? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lmd-assert
    _lmd-disarm
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lmd-assert
    _lmd-result-b LIBE.ID RID-PRESENT? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 3 = _lmd-assert
    0 0 _lmd-query
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-count @ 1 = _lmd-assert
    _lmd-next @ 1 = _lmd-assert
    _lmd-generation @ 3 = _lmd-assert
    _lmd-summary LIBQS.REF RREF.ID
        _lmd-result-a LIBE.ID RID= _lmd-assert
    3 1 _lmd-query
    _lmd-status @ LIBSTORE-S-OK = _lmd-assert
    _lmd-count @ 1 = _lmd-assert
    _lmd-next @ -1 = _lmd-assert
    _lmd-generation @ 3 = _lmd-assert
    _lmd-summary LIBQS.REF RREF.ID
        _lmd-result-b LIBE.ID RID= _lmd-assert
    _lmd-stack ;

: _lmd-uncertain-head-reconciliation  ( -- )
    _lmd-key-d 3 _lmd-request!
    0 _lmd-stage-mask !
    ['] _lmd-uncertain-checkpoint _LIBMU-CHECKPOINT-XT !
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lmd-assert
    _lmd-head-fault-end
    _lmd-head-sync-failed @ _lmd-assert
    _lmd-stage-mask @ 31 = _lmd-assert
    _lmd-result-b LIB-ENTRY-VALID? _lmd-assert
    _lmd-result-b LIBE.RECEIPT LIBR.OPERATION-KEY
        _lmd-key-d RID= _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 4 = _lmd-assert
    _lmd-store LIBRARY-VFS-STORE-BLOCKED? 0= _lmd-assert
    _lmd-store LIBRARY-VFS-STORE-PROVISIONED? _lmd-assert
    _lmd-store LIBRARY-VFS-STORE-CLEANUP-FAILED? _lmd-assert
    _lmd-result-b _lmd-result-c LIB-ENTRY-SIZE CMOVE
    _lmd-disarm

    0 _lmd-write-calls ! 0 _lmd-random-calls !
    ['] _lmd-count-write _LIBVFS-WRITE-EXACT-XT !
    ['] _lmd-count-random _LIBMU-RANDOM-XT !
    _lmd-result-b LIB-ENTRY-SIZE 165 FILL
    _lmd-request _lmd-result-b _lmd-store
        LIBRARY-VFS-STORE-CREATE-MANAGED
        LIBSTORE-S-OK = _lmd-assert
    _lmd-result-b LIB-ENTRY-SIZE _lmd-result-c LIB-ENTRY-SIZE
        COMPARE 0= _lmd-assert
    _lmd-write-calls @ 0= _lmd-assert
    _lmd-random-calls @ 0= _lmd-assert
    _lmd-store LIBRARY-VFS-STORE.GENERATION @ 4 = _lmd-assert
    _lmd-disarm
    _lmd-stack ;

: _lmd-run  ( -- )
    0 _lmd-fails ! 0 _lmd-checks ! DEPTH _lmd-depth !
    VFS-CUR _lmd-old-vfs !
    _lmd-arena-id LIB-DIGEST-SIZE 0xA4 FILL
    _lmd-key-a LIB-OPERATION-KEY-SIZE 0x11 FILL
    _lmd-key-b LIB-OPERATION-KEY-SIZE 0x22 FILL
    _lmd-key-c LIB-OPERATION-KEY-SIZE 0x33 FILL
    _lmd-key-d LIB-OPERATION-KEY-SIZE 0x44 FILL
    4194304 A-XMEM ARENA-NEW DUP 0= _lmd-assert DROP
    DUP _lmd-arena !
    VFS-RAM-OPS _lmd-ops VFS-OPS-SIZE CMOVE
    VFS-RAM-BINDING _lmd-binding VFS-BINDING-DESC-SIZE CMOVE
    _lmd-ops _lmd-binding VB.OPS !
    _lmd-binding 0 VFS-NEW ?DUP IF THROW THEN
        DUP _lmd-vfs ! 0<> _lmd-assert
    _lmd-vfs @ VFS-USE
    LIBRARY-VFS-STORE-SIZE ALLOCATE
        ABORT" LIBRARY MANAGED FAIL allocation" _lmd-store-slot !
    _lmd-vfs @ _lmd-store LIBRARY-VFS-STORE-INIT
        LIBSTORE-S-OK = _lmd-assert
    _lmd-arena-id _lmd-store LIBRARY-VFS-STORE-PROVISION
        LIBSTORE-S-OK = _lmd-assert
    _lmd-basic-create
    _lmd-query-read
    _lmd-idempotency
    _lmd-public-failures
    _lmd-mutation-boundaries
    _lmd-interrupt-before-head
    _lmd-lost-response
    _lmd-cleanup-before-publication
    _lmd-uncertain-head-reconciliation
    _lmd-disarm
    _lmd-store LIBRARY-VFS-STORE-FINI
        LIBSTORE-S-OK = _lmd-assert
    _lmd-store-slot @ FREE 0 _lmd-store-slot !
    _lmd-old-vfs @ VFS-USE
    _lmd-vfs @ VFS-DESTROY
    _lmd-stack
    _lmd-fails @ ?DUP IF
        ." LIBRARY MANAGED FAIL " . ." / " _lmd-checks @ . CR
    ELSE
        ." LIBRARY MANAGED PASS " _lmd-checks @ . CR
    THEN ;

_lmd-run
