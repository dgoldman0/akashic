\ Focused A/B root-slot and immutable B+tree snapshot-audit contracts.
\
\ This fixture reuses the compact RAM-VFS builders from persist-btree-test.f
\ but does not execute that fixture's full 40-billion-step qualification.

PROVIDED akashic-persistence-snapshot-audit-contracts

VARIABLE _PBTSA-mode
VARIABLE _PBTSA-calls
VARIABLE _PBTSA-current-slot
VARIABLE _PBTSA-old-slot
VARIABLE _PBTSA-generation-a
VARIABLE _PBTSA-generation-b
VARIABLE _PBTSA-bound-generation
VARIABLE _PBTSA-bound-root
VARIABLE _PBTSA-node-count
VARIABLE _PBTSA-row-count
VARIABLE _PBTSA-status-value
VARIABLE _PBTSA-expected-rows
VARIABLE _PBTSA-expected-status
VARIABLE _PBTSA-fd
VARIABLE _PBTSA-ior
VARIABLE _PBTSA-target-page

8192 CONSTANT _PBTSA-MARK-CAPACITY

CREATE _PBTSA-audit-work PBTREE-AUDIT-WORK-SIZE ALLOT
CREATE _PBTSA-slot-a-root PERSIST-ROOT-VALUE-SIZE ALLOT
CREATE _PBTSA-slot-b-root PERSIST-ROOT-VALUE-SIZE ALLOT
CREATE _PBTSA-slot-scratch PERSIST-ROOT-VALUE-SIZE ALLOT
CREATE _PBTSA-tree-root PBTREE-ROOT-SIZE ALLOT
CREATE _PBTSA-bad-tree-root PBTREE-ROOT-SIZE ALLOT
CREATE _PBTSA-page-original PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _PBTSA-page-mutated PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _PBTSA-root-record-original PROOT-RECORD-SIZE ALLOT
CREATE _PBTSA-root-record-mutated PROOT-RECORD-SIZE ALLOT
CREATE _PBTSA-marks _PBTSA-MARK-CAPACITY ALLOT

: _PBTSA-zero?  ( address length -- flag )
    0 ?DO DUP I + C@ IF DROP 0 UNLOOP EXIT THEN LOOP DROP -1 ;

: _PBTSA-slot-root  ( slot -- root-value )
    GPAIR-SLOT-A = IF _PBTSA-slot-a-root ELSE _PBTSA-slot-b-root THEN ;

: _PBTSA-slot-path$  ( slot -- path-a path-u )
    _PBTC-store PSTORE-ROOT-FILE@ >R
    GPAIR-SLOT-A = IF R> PROOT-PATH-A$ ELSE R> PROOT-PATH-B$ THEN ;

: _PBTSA-read-root-record  ( slot destination -- )
    >R _PBTSA-slot-path$
    VFS-FF-READ _PBTC-vfs @ VFS-OPEN?
    _PBTSA-ior ! _PBTSA-fd !
    _PBTSA-ior @ 0= _PBTC-assert
    _PBTSA-fd @ 0<> _PBTC-assert
    R> PROOT-RECORD-SIZE _PBTSA-fd @ VFS-READ-EXACT
        0= _PBTC-assert
    _PBTSA-fd @ VFS-CLOSE? 0= _PBTC-assert ;

: _PBTSA-write-root-record  ( slot source -- )
    >R _PBTSA-slot-path$
    VFS-FF-READ VFS-FF-WRITE OR _PBTC-vfs @ VFS-OPEN?
    _PBTSA-ior ! _PBTSA-fd !
    _PBTSA-ior @ 0= _PBTC-assert
    _PBTSA-fd @ 0<> _PBTC-assert
    0 _PBTSA-fd @ VFS-SEEK? 0= _PBTC-assert
    R> PROOT-RECORD-SIZE _PBTSA-fd @ VFS-WRITE-EXACT
        0= _PBTC-assert
    _PBTSA-fd @ VFS-CLOSE? 0= _PBTC-assert
    _PBTC-vfs @ VFS-SYNC 0= _PBTC-assert ;

: _PBTSA-read-slot  ( slot root-value -- generation status )
    _PBTC-store _PBTC-pstore-work PSTORE-ROOT-SLOT@ ;

: _PBTSA-visitor
  ( page-id expected-height visitor-context -- status )
    DROP
    1 _PBTSA-calls +!
    _PBTSA-mode @ 2 = IF 2DROP -771 THROW THEN
    _PBTSA-mode @ 3 = IF 2DROP 99 EXIT THEN
    DUP 1 < OVER PBTREE-HEIGHT-MAX > OR IF
        2DROP PERSIST-S-CORRUPT EXIT
    THEN
    DROP
    _PBTSA-mode @ 5 =
    _PBTSA-calls @ 1 = AND IF
        DROP
        _PBTSA-tree-root
        _PBTSA-bound-generation @
        _PBTSA-bound-root @ PROOTV.PAGE-COUNT @
        _PBTSA-bound-root @ PROOTV.DATA-BANK @
        ['] _PBTSA-visitor 0 _PBTC-tree _PBTSA-audit-work
            PBTREE-AUDIT-SNAPSHOT-TX
        PERSIST-S-BUSY = >R
        0= >R
        0= R> AND R> AND _PBTC-assert
        _PBTSA-audit-work PBTREE-AUDIT-WORK-STATUS@
            PERSIST-S-OK = _PBTC-assert
        _PBTSA-audit-work _PBTA.BUSY @ -1 = _PBTC-assert
        PERSIST-S-OK EXIT
    THEN
    _PBTSA-mode @ 6 =
    _PBTSA-calls @ 1 = AND IF
        DROP
        _PBTSA-old-slot @ DUP _PBTSA-slot-root _PBTSA-read-slot
        PERSIST-S-OK = >R
        _PBTSA-bound-generation @ <> R> AND _PBTC-assert
        PERSIST-S-OK EXIT
    THEN
    _PBTSA-mode @ 4 =
    _PBTSA-calls @ 2 = AND IF
        DROP PERSIST-S-CORRUPT EXIT
    THEN
    _PBTSA-mode @ 1 = IF DROP PERSIST-S-OK EXIT THEN
    DUP 0< OVER _PBTSA-MARK-CAPACITY >= OR IF
        DROP PERSIST-S-CAPACITY EXIT
    THEN
    _PBTSA-marks + DUP C@ IF
        DROP PERSIST-S-CORRUPT
    ELSE
        1 SWAP C! PERSIST-S-OK
    THEN ;

: _PBTSA-visitor-reset  ( mode -- )
    _PBTSA-mode !
    0 _PBTSA-calls !
    _PBTSA-marks _PBTSA-MARK-CAPACITY 0 FILL ;

: _PBTSA-bind-and-load-tree  ( slot -- )
    DUP _PBTSA-slot-root DUP _PBTSA-bound-root !
    _PBTSA-read-slot
    SWAP _PBTSA-bound-generation !
    PERSIST-S-OK _PBTC-status
    _PBTSA-bound-root @ PROOTV.APPLICATION-ROOT @
    _PBTC-store _PBTC-pstore-work PSTORE-READ-PAGE-SNAPSHOT-TX
        PERSIST-S-OK _PBTC-status
    _PBTC-pstore-work PSTORE-PAGE-PAYLOAD$
    DUP PERSIST-PAGE-PAYLOAD-SIZE = _PBTC-assert
    DROP _PBTSA-tree-root PBTREE-ROOT-SIZE MOVE
    _PBTSA-tree-root _PBTC-tree PBTREE-ROOT-VALID? _PBTC-assert
    _PBTSA-tree-root PBTREE-ROOT-GENERATION@
        _PBTSA-bound-generation @ = _PBTC-assert ;

: _PBTSA-audit-root  ( -- tree-root )
    _PBTSA-bad-tree-root _PBTR.MAGIC @ _PBTR-MAGIC = IF
        _PBTSA-bad-tree-root
    ELSE
        _PBTSA-tree-root
    THEN ;

: _PBTSA-audit  ( expected-rows expected-status visitor-mode -- )
    _PBTSA-visitor-reset
    _PBTSA-expected-status !
    _PBTSA-expected-rows !
    _PBTSA-audit-root
    _PBTSA-bound-generation @
    _PBTSA-bound-root @ PROOTV.PAGE-COUNT @
    _PBTSA-bound-root @ PROOTV.DATA-BANK @
    ['] _PBTSA-visitor 0 _PBTC-tree _PBTSA-audit-work
        PBTREE-AUDIT-SNAPSHOT-TX
    _PBTSA-status-value !
    _PBTSA-row-count !
    _PBTSA-node-count !
    _PBTSA-status-value @ _PBTSA-expected-status @ =
        _PBTC-assert
    _PBTSA-status-value @ PERSIST-S-OK = IF
        _PBTSA-row-count @ _PBTSA-expected-rows @ = _PBTC-assert
        _PBTSA-node-count @ 0> _PBTC-assert
        _PBTSA-calls @ _PBTSA-node-count @ = _PBTC-assert
    THEN
    _PBTSA-bad-tree-root PBTREE-ROOT-SIZE 0 FILL
    _PBTC-stack ;

: _PBTSA-read-node  ( page-id -- )
    DUP _PBTSA-target-page !
    _PBTC-store _PBTC-pstore-work PSTORE-READ-PAGE-SNAPSHOT-TX
        PERSIST-S-OK _PBTC-status
    _PBTC-pstore-work PSTORE-PAGE-PAYLOAD$
    DUP PERSIST-PAGE-PAYLOAD-SIZE = _PBTC-assert
    DROP
    DUP _PBTSA-page-original PERSIST-PAGE-PAYLOAD-SIZE MOVE
    _PBTSA-page-mutated PERSIST-PAGE-PAYLOAD-SIZE MOVE ;

: _PBTSA-read-root-node  ( -- )
    _PBTSA-tree-root PBTREE-ROOT-PAGE@ _PBTSA-read-node ;

: _PBTSA-write-root-node  ( source -- )
    PERSIST-PAGE-PAYLOAD-SIZE
    _PBTSA-target-page @
    _PBTC-store PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @
    _PBTSA-bound-root @ PROOTV.DATA-BANK @
    _PBTC-store PSTORE-PAGE-FILE-FOR-BANK@
    _PBTC-pstore-work _PSW.PAGE-WORK PPAGE-WRITE-AT
        PERSIST-S-OK _PBTC-status ;

: _PBTSA-restore-root-node  ( -- )
    _PBTSA-page-original _PBTSA-write-root-node ;

: _PBTSA-healthy-snapshots  ( -- )
    GPAIR-SLOT-A _PBTSA-slot-a-root _PBTSA-read-slot
        SWAP _PBTSA-generation-a ! PERSIST-S-OK _PBTC-status
    GPAIR-SLOT-B _PBTSA-slot-b-root _PBTSA-read-slot
        SWAP _PBTSA-generation-b ! PERSIST-S-OK _PBTC-status
    _PBTSA-generation-a @ _PBTSA-generation-b @ > IF
        GPAIR-SLOT-A _PBTSA-current-slot !
        GPAIR-SLOT-B _PBTSA-old-slot !
    ELSE
        GPAIR-SLOT-B _PBTSA-current-slot !
        GPAIR-SLOT-A _PBTSA-old-slot !
    THEN
    _PBTSA-current-slot @ _PBTSA-bind-and-load-tree
    _PBTSA-tree-root PBTREE-ROOT-CARDINALITY@ 90 = _PBTC-assert
    _PBTSA-tree-root PBTREE-ROOT-HEIGHT@ 3 = _PBTC-assert
    _PBTSA-bound-generation @
        _PBTSA-bound-root @ PROOTV.PAGE-COUNT @ <> _PBTC-assert
    _PBTC-tree PBTREE-METRICS-RESET PERSIST-S-OK _PBTC-status
    90 PERSIST-S-OK 0 _PBTSA-audit
    _PBTC-tree PBTREE-WORKING-BYTES@
        PBTREE-AUDIT-WORK-SIZE >= _PBTC-assert

    _PBTSA-old-slot @ _PBTSA-bind-and-load-tree
    _PBTSA-tree-root PBTREE-ROOT-CARDINALITY@ 89 = _PBTC-assert
    _PBTSA-tree-root PBTREE-ROOT-HEIGHT@ 2 = _PBTC-assert
    89 PERSIST-S-OK 0 _PBTSA-audit ;

: _PBTSA-empty-snapshot  ( -- )
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    GPAIR-SLOT-A _PBTSA-slot-a-root _PBTSA-read-slot
        SWAP _PBTSA-generation-a ! PERSIST-S-OK _PBTC-status
    GPAIR-SLOT-B _PBTSA-slot-b-root _PBTSA-read-slot
        SWAP _PBTSA-generation-b ! PERSIST-S-OK _PBTC-status
    _PBTSA-generation-a @ _PBTSA-generation-b @ > IF
        GPAIR-SLOT-A
    ELSE
        GPAIR-SLOT-B
    THEN
    _PBTSA-bind-and-load-tree
    _PBTSA-tree-root PBTREE-ROOT-CARDINALITY@ 0= _PBTC-assert
    _PBTSA-tree-root PBTREE-ROOT-HEIGHT@ 0= _PBTC-assert
    _PBTSA-tree-root
    _PBTSA-bound-generation @
    _PBTSA-bound-root @ PROOTV.PAGE-COUNT @
    _PBTSA-bound-root @ PROOTV.DATA-BANK @
    0 0 _PBTC-tree _PBTSA-audit-work PBTREE-AUDIT-SNAPSHOT-TX
    PERSIST-S-OK = >R
    0= >R
    0= R> AND R> AND _PBTC-assert
    _PBTC-store _PBTC-pstore-work PSTORE-ABORT
        PERSIST-S-OK _PBTC-status ;

: _PBTSA-dimension-rejection  ( -- )
    _PBTSA-current-slot @ _PBTSA-bind-and-load-tree
    0 _PBTSA-visitor-reset
    _PBTSA-tree-root
    _PBTSA-bound-generation @ 1+
    _PBTSA-bound-root @ PROOTV.PAGE-COUNT @
    _PBTSA-bound-root @ PROOTV.DATA-BANK @
    ['] _PBTSA-visitor 0 _PBTC-tree _PBTSA-audit-work
        PBTREE-AUDIT-SNAPSHOT-TX
    PERSIST-S-CONFLICT = >R 2DROP R> _PBTC-assert
    _PBTSA-calls @ 0= _PBTC-assert

    0 _PBTSA-visitor-reset
    _PBTSA-tree-root
    _PBTSA-bound-generation @
    _PBTSA-bound-root @ PROOTV.PAGE-COUNT @ 1-
    _PBTSA-bound-root @ PROOTV.DATA-BANK @
    ['] _PBTSA-visitor 0 _PBTC-tree _PBTSA-audit-work
        PBTREE-AUDIT-SNAPSHOT-TX
    PERSIST-S-CONFLICT = >R 2DROP R> _PBTC-assert
    _PBTSA-calls @ 0= _PBTC-assert

    0 _PBTSA-visitor-reset
    _PBTSA-tree-root
    _PBTSA-bound-generation @
    _PBTSA-bound-root @ PROOTV.PAGE-COUNT @
    _PBTSA-bound-root @ PROOTV.DATA-BANK @
        PERSIST-DATA-BANK-0 = IF
            PERSIST-DATA-BANK-1
        ELSE
            PERSIST-DATA-BANK-0
        THEN
    ['] _PBTSA-visitor 0 _PBTC-tree _PBTSA-audit-work
        PBTREE-AUDIT-SNAPSHOT-TX
    PERSIST-S-CONFLICT = >R 2DROP R> _PBTC-assert
    _PBTSA-calls @ 0= _PBTC-assert

    _PBTSA-tree-root _PBTSA-bad-tree-root PBTREE-ROOT-SIZE MOVE
    1 _PBTSA-bad-tree-root _PBTR.GENERATION +!
    90 PERSIST-S-CONFLICT 0 _PBTSA-audit
    _PBTSA-calls @ 0= _PBTC-assert _PBTC-stack ;

: _PBTSA-wrong-high-key  ( -- )
    _PBTSA-read-root-node
    _PBTSA-page-mutated DUP _PBTN.COUNT @ 1- SWAP _PBTB-KEY$
    DUP 2 = _PBTC-assert
    1- + DUP C@ 1+ SWAP C!
    _PBTSA-page-mutated _PBTSA-write-root-node
    90 PERSIST-S-CORRUPT 1 _PBTSA-audit
    _PBTSA-restore-root-node ;

: _PBTSA-duplicate-child  ( -- )
    _PBTSA-read-root-node
    0 _PBTSA-page-mutated _PBTB-CHILD@
    1 _PBTSA-page-mutated _PBTB-ENTRY _PBTB-CHILD-OFF + !
    _PBTSA-page-mutated _PBTSA-write-root-node
    90 PERSIST-S-CORRUPT 1 _PBTSA-audit
    _PBTSA-restore-root-node ;

: _PBTSA-cycle-child  ( -- )
    _PBTSA-read-root-node
    _PBTSA-tree-root PBTREE-ROOT-PAGE@
    0 _PBTSA-page-mutated _PBTB-ENTRY _PBTB-CHILD-OFF + !
    _PBTSA-page-mutated _PBTSA-write-root-node
    90 PERSIST-S-CORRUPT 1 _PBTSA-audit
    _PBTSA-restore-root-node ;

: _PBTSA-child-out-of-bounds  ( -- )
    _PBTSA-read-root-node
    _PBTSA-bound-root @ PROOTV.PAGE-COUNT @
    0 _PBTSA-page-mutated _PBTB-ENTRY _PBTB-CHILD-OFF + !
    _PBTSA-page-mutated _PBTSA-write-root-node
    90 PERSIST-S-CORRUPT 1 _PBTSA-audit
    _PBTSA-restore-root-node ;

: _PBTSA-root-occupancy  ( -- )
    _PBTSA-read-root-node
    1 _PBTSA-page-mutated _PBTN.COUNT !
    _PBTSA-page-mutated _PBTN-ENTRIES-OFF _PBTB-ENTRY-SIZE + +
    PERSIST-PAGE-PAYLOAD-SIZE
        _PBTN-ENTRIES-OFF _PBTB-ENTRY-SIZE + - 0 FILL
    _PBTSA-page-mutated _PBTSA-write-root-node
    90 PERSIST-S-CORRUPT 1 _PBTSA-audit
    _PBTSA-restore-root-node ;

: _PBTSA-nonroot-occupancy  ( -- )
    _PBTSA-read-root-node
    0 _PBTSA-page-mutated _PBTB-CHILD@ _PBTSA-read-node
    _PBTSA-page-mutated _PBTN.KIND @ _PBTN-BRANCH =
        _PBTC-assert
    1 _PBTSA-page-mutated _PBTN.COUNT !
    _PBTSA-page-mutated _PBTN-ENTRIES-OFF _PBTB-ENTRY-SIZE + +
    PERSIST-PAGE-PAYLOAD-SIZE
        _PBTN-ENTRIES-OFF _PBTB-ENTRY-SIZE + - 0 FILL
    _PBTSA-page-mutated _PBTSA-write-root-node
    90 PERSIST-S-CORRUPT 1 _PBTSA-audit
    _PBTSA-restore-root-node ;

: _PBTSA-cardinality  ( -- )
    _PBTSA-tree-root _PBTSA-bad-tree-root PBTREE-ROOT-SIZE MOVE
    1 _PBTSA-bad-tree-root _PBTR.CARDINALITY +!
    90 PERSIST-S-CORRUPT 1 _PBTSA-audit ;

: _PBTSA-visitor-failures  ( -- )
    _PBTSA-current-slot @ _PBTSA-bind-and-load-tree
    90 PERSIST-S-CORRUPT 4 _PBTSA-audit
    90 PERSIST-S-FAULT 2 _PBTSA-audit
    90 PERSIST-S-FAULT 3 _PBTSA-audit ;

: _PBTSA-reentry  ( -- )
    _PBTSA-current-slot @ _PBTSA-bind-and-load-tree
    90 PERSIST-S-OK 5 _PBTSA-audit
    _PBTSA-audit-work PBTREE-AUDIT-WORK-STATUS@
        PERSIST-S-OK = _PBTC-assert
    90 PERSIST-S-OK 0 _PBTSA-audit ;

: _PBTSA-rebinding  ( -- )
    _PBTSA-current-slot @ _PBTSA-bind-and-load-tree
    90 PERSIST-S-CONFLICT 6 _PBTSA-audit
    _PBTSA-node-count @ 0= _PBTC-assert
    _PBTSA-row-count @ 0= _PBTC-assert
    _PBTSA-calls @ 1 = _PBTC-assert
    _PBTSA-current-slot @ _PBTSA-bind-and-load-tree
    90 PERSIST-S-OK 0 _PBTSA-audit ;

: _PBTSA-corrupt-root-slot  ( -- )
    _PBTSA-current-slot @ _PBTSA-root-record-original
        _PBTSA-read-root-record
    _PBTSA-root-record-original _PBTSA-root-record-mutated
        PROOT-RECORD-SIZE MOVE
    _PBTSA-root-record-mutated DUP C@ 1 XOR SWAP C!
    _PBTSA-current-slot @ _PBTSA-root-record-mutated
        _PBTSA-write-root-record
    _PBTSA-slot-scratch PERSIST-ROOT-VALUE-SIZE 0xA5 FILL
    _PBTSA-current-slot @ _PBTSA-slot-scratch _PBTSA-read-slot
    SWAP 0= _PBTC-assert
        PERSIST-S-CORRUPT _PBTC-status
    _PBTSA-slot-scratch PERSIST-ROOT-VALUE-SIZE _PBTSA-zero?
        _PBTC-assert
    _PBTSA-current-slot @ _PBTSA-root-record-original
        _PBTSA-write-root-record
    _PBTSA-current-slot @ _PBTSA-bind-and-load-tree ;

: _PBTSA-absent-slots  ( -- )
    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN PERSIST-S-OK _PBTC-status
    _PBTSA-slot-scratch PERSIST-ROOT-VALUE-SIZE 0xA5 FILL
    GPAIR-SLOT-A _PBTSA-slot-scratch _PBTSA-read-slot
    SWAP 0= _PBTC-assert
        PERSIST-S-ABSENT _PBTC-status
    _PBTSA-slot-scratch PERSIST-ROOT-VALUE-SIZE _PBTSA-zero?
        _PBTC-assert
    _PBTC-store _PBTC-pstore-work PSTORE-ABORT
        PERSIST-S-OK _PBTC-status ;

: _PBTSA-RUN  ( -- )
    0 _PBTC-fails !
    0 _PBTC-checks !
    0 _PBTC-fault-at !
    DEPTH _PBTC-depth !
    1 _PBTC-phase ! _PBTC-setup
    _PBTC-pstore-work _PBTSA-audit-work PBTREE-AUDIT-WORK-INIT
        PERSIST-S-OK _PBTC-status
    2 _PBTC-phase ! _PBTSA-absent-slots
    3 _PBTC-phase ! _PBTC-first
    4 _PBTC-phase ! _PBTC-empty-alpha
    5 _PBTC-phase ! _PBTSA-empty-snapshot
    6 _PBTC-phase ! _PBTC-build-height-three

    _PBTC-store _PBTC-pstore-work PSTORE-BEGIN
        PERSIST-S-OK _PBTC-status
    7 _PBTC-phase ! _PBTSA-healthy-snapshots
    8 _PBTC-phase ! _PBTSA-dimension-rejection
    9 _PBTC-phase ! _PBTSA-current-slot @ _PBTSA-bind-and-load-tree
    10 _PBTC-phase ! _PBTSA-wrong-high-key
    11 _PBTC-phase ! _PBTSA-duplicate-child
    12 _PBTC-phase ! _PBTSA-cycle-child
    13 _PBTC-phase ! _PBTSA-child-out-of-bounds
    14 _PBTC-phase ! _PBTSA-root-occupancy
    15 _PBTC-phase ! _PBTSA-nonroot-occupancy
    16 _PBTC-phase ! _PBTSA-cardinality
    17 _PBTC-phase ! _PBTSA-reentry
    18 _PBTC-phase ! _PBTSA-rebinding
    19 _PBTC-phase ! _PBTSA-visitor-failures
    20 _PBTC-phase ! _PBTSA-corrupt-root-slot
    _PBTC-store _PBTC-pstore-work PSTORE-ABORT
        PERSIST-S-OK _PBTC-status

    _PBTC-old-vfs @ VFS-USE
    _PBTC-vfs @ VFS-DESTROY
    _PBTC-stack
    _PBTC-fails @ 0= IF
        ." PERSISTENCE SNAPSHOT AUDIT PASS " _PBTC-checks @ . CR
    ELSE
        ." PERSISTENCE SNAPSHOT AUDIT FAIL "
        _PBTC-fails @ . ." /" _PBTC-checks @ . CR
    THEN ;
