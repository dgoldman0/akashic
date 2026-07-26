\ RAM-VFS contracts for bounded, two-root-fenced physical reclamation.

PROVIDED akashic-persistence-reclaim-contracts

VARIABLE _RB-fails
VARIABLE _RB-checks
VARIABLE _RB-depth
VARIABLE _RB-root
VARIABLE _RB-fault-calls
VARIABLE _RB-fault-point
VARIABLE _RB-fault-occurrence
VARIABLE _RB-before-staged
VARIABLE _RB-before-discard
VARIABLE _RB-before-ready-head
VARIABLE _RB-before-ready-index
VARIABLE _RB-before-reusable
VARIABLE _RB-before-allocated
VARIABLE _RB-before-proposed
VARIABLE _RB-snapshot-page
VARIABLE _RB-reserved
VARIABLE _RB-cadence-live-a
VARIABLE _RB-cadence-live-b
VARIABLE _RB-cadence-new-a
VARIABLE _RB-cadence-new-b
VARIABLE _RB-cadence-warm-pages
VARIABLE _RB-cadence-warm-retired
VARIABLE _RB-audit-store
VARIABLE _RB-audit-pstore-work
VARIABLE _RB-audit-callback-mode
VARIABLE _RB-audit-payload
VARIABLE _RB-audit-calls
VARIABLE _RB-audit-enumerator-xt
VARIABLE _RB-audit-shape-pages
VARIABLE _RB-audit-slot-pages
CREATE _RB-reclaim RECLAIM-SIZE ALLOT
CREATE _RB-work RECLAIM-WORK-SIZE ALLOT
CREATE _RB-state RECLAIM-STATE-SIZE ALLOT
CREATE _RB-page-before PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _RB-reclaim-b RECLAIM-SIZE ALLOT
CREATE _RB-work-b RECLAIM-WORK-SIZE ALLOT
CREATE _RB-reclaim-i0 RECLAIM-SIZE ALLOT
CREATE _RB-reclaim-i1 RECLAIM-SIZE ALLOT
CREATE _RB-reclaim-i2 RECLAIM-SIZE ALLOT
CREATE _RB-reclaim-i3 RECLAIM-SIZE ALLOT
CREATE _RB-work-i0 RECLAIM-WORK-SIZE ALLOT
CREATE _RB-work-i1 RECLAIM-WORK-SIZE ALLOT
CREATE _RB-work-i2 RECLAIM-WORK-SIZE ALLOT
CREATE _RB-work-i3 RECLAIM-WORK-SIZE ALLOT
CREATE _RB-ids 129 CELLS ALLOT
CREATE _RB-audit-work RECLAIM-AUDIT-WORK-SIZE ALLOT
CREATE _RB-audit-work-2 RECLAIM-AUDIT-WORK-SIZE ALLOT
1024 CONSTANT _RB-AUDIT-RECLAIM-OFFSET
CREATE _RB-audit-overlap-region
    RECLAIM-AUDIT-WORK-SIZE RECLAIM-SIZE + ALLOT
CREATE _RB-audit-overlap-before RECLAIM-AUDIT-WORK-SIZE ALLOT
CREATE _RB-audit-overlap-reclaim-before RECLAIM-SIZE ALLOT
CREATE _RB-audit-alias-pstore-work PSTORE-WORK-SIZE ALLOT
CREATE _RB-audit-alias-pstore-buffer 512 ALLOT
CREATE _RB-audit-alias-pstore-before PSTORE-WORK-SIZE ALLOT
CREATE _RB-audit-alias-audit-before RECLAIM-AUDIT-WORK-SIZE ALLOT
CREATE _RB-audit-alias-reclaim-before RECLAIM-SIZE ALLOT
CREATE _RB-audit-map 1024 ALLOT
CREATE _RB-audit-page-before PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _RB-audit-root-before PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _RB-audit-bucket-before PERSIST-PAGE-PAYLOAD-SIZE ALLOT
CREATE _RB-audit-root-value PERSIST-ROOT-VALUE-SIZE ALLOT
CREATE _RB-audit-bank1-page PERSIST-PAGE-FILE-SIZE ALLOT
CREATE _RB-audit-bank1-segment PSEG-FILE-SIZE ALLOT
CREATE _RB-audit-page-work PERSIST-PAGE-WORK-SIZE ALLOT
CREATE _RB-audit-segment-work PSEG-WORK-SIZE ALLOT
CREATE _RB-audit-segment-buffer 512 ALLOT
CREATE _RB-audit-shape-store PSTORE-SIZE ALLOT
CREATE _RB-audit-shape-pstore-work PSTORE-WORK-SIZE ALLOT
CREATE _RB-audit-shape-buffer 512 ALLOT
CREATE _RB-audit-shape-identity PERSIST-IDENTITY-SIZE ALLOT
CREATE _RB-audit-shape-reclaim RECLAIM-SIZE ALLOT
GUARD _RB-audit-shape-guard

: _RB-a  ( flag -- )
    1 _RB-checks +!
    0= IF
        1 _RB-fails +! ." PERSISTENCE RECLAIM ASSERT " _RB-checks @ . CR
    THEN ;

: _RB-s  ( actual expected -- )
    2DUP <> IF
        ." PERSISTENCE RECLAIM STATUS actual/expected "
        2DUP SWAP . . CR
    THEN
    = _RB-a ;

: _RB-stack  ( -- )
    DEPTH DUP _RB-depth @ <> IF
        ." PERSISTENCE RECLAIM STACK " _RB-depth @ . ." -> " DUP . CR
        .S CR
    THEN
    _RB-depth @ = _RB-a ;

: _RB-id  ( index -- a ) CELLS _RB-ids + ;

: _RB-current-app-root  ( -- page-id )
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @ ;

: _RB-page-snapshot!  ( page-id -- )
    DUP _RB-snapshot-page !
    _PSTC-store-a _PSTC-work-a PSTORE-READ-PAGE-TX PERSIST-S-OK _RB-s
    _PSTC-work-a PSTORE-PAGE-PAYLOAD$ DROP
        _RB-page-before PERSIST-PAGE-PAYLOAD-SIZE MOVE ;

: _RB-page-snapshot-current=  ( -- flag )
    _RB-snapshot-page @ _PSTC-store-a _PSTC-work-a PSTORE-READ-PAGE
        PERSIST-S-OK _RB-s
    _PSTC-work-a PSTORE-PAGE-PAYLOAD$
        _RB-page-before PERSIST-PAGE-PAYLOAD-SIZE COMPARE 0= ;

: _RB-begin  ( -- )
    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s ;

: _RB-alloc-write  ( byte -- page-id )
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE ROT FILL
    _RB-work _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE
        PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 2 PICK
        _PSTC-store-a _PSTC-work-a PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s ;

: _RB-protected-write  ( byte future-retirement-reserve -- page-id )
    >R
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE ROT FILL
    R> _RB-work _PSTC-store-a _PSTC-work-a
        RECLAIM-ALLOCATE-PROTECTED PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 2 PICK
        _PSTC-store-a _PSTC-work-a PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s ;

: _RB-claim-write  ( byte -- page-id )
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE ROT FILL
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
    DUP _RB-work RECLAIM-CLAIM-HIGH-WATER PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 2 PICK
        _PSTC-store-a _PSTC-work-a PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s ;

: _RB-finish  ( root -- )
    _RB-work RECLAIM-FINALIZE PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PSTC-page RECLAIM-STATE-SIZE _RB-work RECLAIM-STATE!
        PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 2 PICK
        _PSTC-store-a _PSTC-work-a PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    DUP _PSTC-store-a _PSTC-work-a PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-COMMIT PERSIST-S-OK _RB-s
    _RB-work _RB-reclaim RECLAIM-ADOPT PERSIST-S-OK _RB-s
    _RB-root ! ;

: _RB-grow-base  ( -- )
    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _RB-s
    69 0 ?DO
        _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE I 1+ FILL
        _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE
            _PSTC-store-a _PSTC-work-a PSTORE-APPEND-PAGE
        PERSIST-S-OK = SWAP I 1+ = AND _RB-a
    LOOP
    69 _PSTC-store-a _PSTC-work-a PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-COMMIT PERSIST-S-OK _RB-s
    _PSTC-store-a PSTORE-GENERATION@ 2 = _RB-a
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 70 = _RB-a ;

\ Page-budgeting consumers reserve against all three live ledgers through the
\ public work API; inactive, negative, and over-capacity requests fail without
\ changing transaction state.
: _RB-room-contract  ( -- )
    0 0 0 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    0 0 0 0 RECLAIM-TX-ROOM? 0= _RB-a
    _RB-begin
    128 64 64 _RB-work RECLAIM-TX-ROOM? _RB-a
    -1 0 0 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    0 -1 0 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    0 0 -1 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    91 _RB-alloc-write DUP _RB-reserved ! DROP
    127 64 64 _RB-work RECLAIM-TX-ROOM? _RB-a
    128 0 0 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    0 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    0 63 64 _RB-work RECLAIM-TX-ROOM? _RB-a
    0 64 0 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    _RB-reserved @ 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-OK _RB-s
    0 0 63 _RB-work RECLAIM-TX-ROOM? _RB-a
    0 0 64 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    0 0 0 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    _RB-stack ;

\ Hidden copy-on-write owners may insist on the current high-water id while
\ still joining the same bounded consumer-issued ledger.  Only that exact id
\ is admitted; a wrong claim poisons the proposal, and the 128th live claim is
\ the last one accepted.
: _RB-high-water-claim-contract  ( -- )
    0 0 RECLAIM-CLAIM-HIGH-WATER PERSIST-S-INVALID _RB-s
    0 _RB-work RECLAIM-CLAIM-HIGH-WATER PERSIST-S-BUSY _RB-s

    _RB-begin
    93 _RB-claim-write DUP 70 = _RB-a DROP
    _RB-work _RCW.ALLOCATED-COUNT @ 1 = _RB-a
    127 64 64 _RB-work RECLAIM-TX-ROOM? _RB-a
    128 0 0 _RB-work RECLAIM-TX-ROOM? 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 1+
        _RB-work RECLAIM-CLAIM-HIGH-WATER PERSIST-S-CONFLICT _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-TX-READY? 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    128 0 ?DO I 1+ _RB-claim-write DROP LOOP
    _RB-work _RCW.ALLOCATED-COUNT @ RECLAIM-ALLOCATED-MAX = _RB-a
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _RB-work RECLAIM-CLAIM-HIGH-WATER PERSIST-S-CAPACITY _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-TX-READY? 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-stack ;

\ Refused begin paths do not partially initialize a reclaim work object.
\ One exact runtime owner fences OPEN, reentry, and a second work object while
\ leaving the owning work able to continue allocating without duplicates.
: _RB-begin-ownership  ( -- )
    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work
        RECLAIM-TX-BEGIN PERSIST-S-BUSY _RB-s
    _RB-work _RCW.ACTIVE @ 0= _RB-a
    _RB-work _RCW.RECLAIM @ 0= _RB-a
    _RB-reclaim _RCL.ACTIVE-WORK @ 0= _RB-a

    _PSTC-store-b-init PERSIST-S-OK _RB-s
    _PSTC-record-buffer-b 512 _PSTC-work-b PSTORE-WORK-INIT
        PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b PSTORE-PROVISION PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b PSTORE-OPEN PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b _RB-reclaim _RB-work
        RECLAIM-TX-BEGIN PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.ACTIVE @ 0= _RB-a
    _RB-reclaim _RCL.ACTIVE-WORK @ 0= _RB-a

    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _RB-s
    -1 _PSTC-work-a _PSW.BUSY !
    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work
        RECLAIM-TX-BEGIN PERSIST-S-BUSY _RB-s
    0 _PSTC-work-a _PSW.BUSY !
    _RB-work _RCW.ACTIVE @ 0= _RB-a
    _RB-work _RCW.RECLAIM @ 0= _RB-a
    _RB-reclaim _RCL.ACTIVE-WORK @ 0= _RB-a

    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _RB-reclaim _RCL.ACTIVE-WORK @ _RB-work = _RB-a
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-a _RB-reclaim
        RECLAIM-OPEN PERSIST-S-BUSY _RB-s
    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work
        RECLAIM-TX-BEGIN PERSIST-S-BUSY _RB-s

    _RB-work-b RECLAIM-WORK-INIT PERSIST-S-OK _RB-s
    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work-b
        RECLAIM-TX-BEGIN PERSIST-S-BUSY _RB-s
    _RB-work-b _RCW.ACTIVE @ 0= _RB-a
    _RB-work-b _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE
        PERSIST-S-BUSY = SWAP -1 = AND _RB-a
    71 _RB-alloc-write DUP 70 = _RB-a DROP
    72 _RB-alloc-write DUP 71 = _RB-a DROP
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-reclaim _RCL.ACTIVE-WORK @ 0= _RB-a

    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work-b
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _RB-reclaim _RCL.ACTIVE-WORK @ _RB-work-b = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work-b RECLAIM-ABORT PERSIST-S-OK _RB-s ;

\ Pages appended through PSTORE before reclaim begins belong to the current
\ proposal, not the committed retirement population.  Begin seeds them into
\ the issued ledger and abort remains layered under the store transaction.
: _RB-prebegin-append  ( -- )
    _PSTC-store-a _PSTC-work-a PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 73 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE
        _PSTC-store-a _PSTC-work-a PSTORE-APPEND-PAGE
        PERSIST-S-OK _RB-s
    DUP 70 = _RB-a 0 _RB-id !
    _PSTC-store-a _PSTC-work-a _RB-reclaim _RB-work
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _RB-work _RCW.BASE-PAGE-COUNT @ 70 = _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @ 1 = _RB-a
    0 _RB-work _RCW.ALLOCATED-ENTRY @ 70 = _RB-a
    _RB-ids 1 _RB-work RECLAIM-RELEASE-BATCH PERSIST-S-OK _RB-s
    _RB-work _RCW.STAGED-COUNT @ 0= _RB-a
    _RB-work _RCW.DISCARD-COUNT @ 1 = _RB-a
    _RB-work RECLAIM-ABORT PERSIST-S-BUSY _RB-s
    _RB-reclaim _RCL.ACTIVE-WORK @ _RB-work = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-reclaim _RCL.ACTIVE-WORK @ 0= _RB-a ;

: _RB-ready-state-biconditional  ( -- )
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    0 _RB-state _RCS.READY-HEAD !
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-VALID? 0= _RB-a
    1 _RB-state _RCS.REUSABLE-COUNT !
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-VALID? _RB-a
    -1 _RB-state _RCS.READY-HEAD !
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-VALID? 0= _RB-a
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s ;

\ A returned high-water id is a reservation until its checked page is written.
\ The issued ledger must prevent a second allocation from returning the same
\ id, and the rejected operation leaves both proposal geometry and committed
\ application-root bytes untouched before mandatory layered abort cleanup.
: _RB-unwritten-consecutive  ( -- )
    _RB-begin
    _RB-current-app-root _RB-page-snapshot!
    _RB-work _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE
        SWAP _RB-reserved ! PERSIST-S-OK _RB-s
    _RB-work _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE
        PERSIST-S-CONFLICT = SWAP -1 = AND _RB-a
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _RB-reserved @ = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-page-snapshot-current= _RB-a
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-stack ;

\ Finalization also allocates bucket metadata.  It may not steal an unwritten
\ consumer reservation at the proposal high-water mark.
: _RB-unwritten-finalize  ( -- )
    _RB-begin
    _RB-current-app-root DUP _RB-page-snapshot! 0 _RB-id !
    _RB-work _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE
        SWAP _RB-reserved ! PERSIST-S-OK _RB-s
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-work RECLAIM-FINALIZE PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.FINALIZED @ 0= _RB-a
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _RB-reserved @ = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-page-snapshot-current= _RB-a
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-stack ;

\ Exercise the settled Library geometry: 61 retirements require two linked
\ buckets while remaining within the 64-entry per-transaction ledger.
: _RB-retire-61  ( -- )
    _RB-begin
    70 _RB-alloc-write DUP 70 = _RB-a
    61 0 ?DO 60 I - I _RB-id ! LOOP
    _RB-ids 32 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    32 _RB-id 29 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-finish
    _RB-reclaim RECLAIM-RETIRED-COUNT@ 61 = _RB-a
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 73 = _RB-a
    71 _PSTC-store-a _PSTC-work-a PSTORE-READ-PAGE PERSIST-S-OK _RB-s
    _PSTC-work-a PSTORE-PAGE-PAYLOAD$ DROP DUP _RCB.COUNT @ 32 = _RB-a
    DUP _RCB.NEXT @ 72 = _RB-a
    0 OVER _RCB.ENTRY @ 0= _RB-a
    31 SWAP _RCB.ENTRY @ 31 = _RB-a
    72 _PSTC-store-a _PSTC-work-a PSTORE-READ-PAGE PERSIST-S-OK _RB-s
    _PSTC-work-a PSTORE-PAGE-PAYLOAD$ DROP DUP _RCB.COUNT @ 29 = _RB-a
    DUP _RCB.NEXT @ -1 = _RB-a
    0 OVER _RCB.ENTRY @ 32 = _RB-a
    28 SWAP _RCB.ENTRY @ 60 = _RB-a ;

\ Incremental maintenance uses the same allocator.  A rotation cannot write
\ its copied bucket into an id already reserved but not yet physically claimed.
: _RB-unwritten-step  ( -- )
    _RB-begin
    _RB-current-app-root _RB-page-snapshot!
    _RB-work _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE
        SWAP _RB-reserved ! PERSIST-S-OK _RB-s
    RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
        PERSIST-S-CONFLICT = SWAP 0= AND _RB-a
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _RB-reserved @ = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-page-snapshot-current= _RB-a
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-stack ;

: _RB-rotate-2  ( -- )
    _RB-begin
    73 _RB-alloc-write DUP 73 = _RB-a
    RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
        PERSIST-S-OK = SWAP 0= AND _RB-a
    RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
        PERSIST-S-OK = SWAP 0= AND _RB-a
    _RB-finish
    _RB-reclaim RECLAIM-RETIRED-COUNT@ 63 = _RB-a ;

: _RB-promote-reuse-61  ( -- )
    _RB-begin
    77 _RB-alloc-write DUP 77 = _RB-a _RB-root !
    RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
        PERSIST-S-OK = SWAP 29 = AND _RB-a
    29 0 ?DO I 32 + _RB-alloc-write I 32 + = _RB-a LOOP
    RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
        PERSIST-S-OK = SWAP 32 = AND _RB-a
    32 0 ?DO I _RB-alloc-write I = _RB-a LOOP
    _RB-root @ _RB-finish
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 0= _RB-a
    _RB-reclaim RECLAIM-RETIRED-COUNT@ 6 = _RB-a ;

\ The 65th aggregate retirement is rejected without changing the 64 staged
\ ids already accepted in this proposal.
: _RB-retire-cap  ( -- )
    _RB-begin
    79 _RB-alloc-write 65 _RB-id !
    65 0 ?DO I I _RB-id ! LOOP
    _RB-ids 32 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    32 _RB-id 32 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-work _RCW.STAGED-COUNT @ 64 = _RB-a
    64 66 _RB-id !
    65 _RB-id 2 _RB-work RECLAIM-RELEASE-BATCH
        PERSIST-S-CAPACITY _RB-s
    _RB-work _RCW.STAGED-COUNT @ 64 = _RB-a
    _RB-work _RCW.DISCARD-COUNT @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s ;

: _RB-call-bounds  ( -- )
    _RB-begin
    _RB-ids 33 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-INVALID _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-begin
    _RB-ids 33 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-INVALID _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-begin
    33 _RB-work RECLAIM-STEP
        PERSIST-S-INVALID = SWAP 0= AND _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-begin
    _RB-ids 33 _RB-work RECLAIM-RELEASE-BATCH PERSIST-S-INVALID _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s ;

: _RB-invalid-ledgers  ( -- )
    _RB-begin
    0 0 _RB-id ! 0 1 _RB-id !
    _RB-ids 2 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.STAGED-COUNT @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    71 _RB-alloc-write DUP 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.STAGED-COUNT @ 0= _RB-a
    DROP _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    0 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.DISCARD-COUNT @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    72 _RB-alloc-write DUP 0 _RB-id ! DUP 1 _RB-id !
    _RB-ids 2 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.DISCARD-COUNT @ 0= _RB-a
    DROP _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    _RB-work 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-INVALID _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    73 _RB-alloc-write DUP 1 _RB-id ! DUP 2 _RB-id ! DROP
    0 0 _RB-id !
    _RB-ids 3 _RB-work RECLAIM-RELEASE-BATCH PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.STAGED-COUNT @ 0= _RB-a
    _RB-work _RCW.DISCARD-COUNT @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-reclaim _RCL.STATE RECLAIM-STATE-SIZE
        _PSTC-store-a _RB-reclaim RECLAIM-OPEN PERSIST-S-INVALID _RB-s ;

\ A reclaim-local rejection after a consumer page was emitted must poison the
\ shared store proposal.  COMMIT cannot turn that unrelated page into an
\ unreachable durable suffix; only store-first, reclaim-second abort releases
\ the owners, and the next begin reconciles to the committed page bound.
: _RB-layer-failure-poisons  ( -- )
    _PSTC-store-a PSTORE-GENERATION@ _RB-before-staged !
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @
        _RB-before-discard !
    _RB-begin
    _RB-current-app-root _RB-page-snapshot!
    201 _RB-alloc-write DUP 0 _RB-id ! DROP
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-CONFLICT _RB-s
    _RB-work _RCW.STATUS @ PERSIST-S-CONFLICT = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-TX-READY? 0= _RB-a
    _PSTC-store-a PSTORE-STATUS@ PERSIST-S-CONFLICT _RB-s
    _PSTC-work-a PSTORE-WORK-STATUS@ PERSIST-S-CONFLICT _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-BUSY _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-COMMIT PERSIST-S-CONFLICT _RB-s
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ 0<> _RB-a
    _PSTC-store-a PSTORE-GENERATION@ _RB-before-staged @ = _RB-a
    _PSTC-store-a PSTORE-STATUS@ PERSIST-S-CONFLICT _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-page-snapshot-current= _RB-a
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @
        _RB-before-discard @ = _RB-a
    _RB-begin
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _RB-before-discard @ = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-stack ;

: _RB-discard-33  ( -- )
    _RB-begin
    81 _RB-alloc-write DUP 81 = _RB-a _RB-root !
    33 0 ?DO
        I 1+ _RB-alloc-write DUP I 82 + = _RB-a 32 I - _RB-id !
    LOOP
    _RB-ids 32 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-OK _RB-s
    32 _RB-id 1 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-OK _RB-s
    _RB-root @ _RB-finish
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 33 = _RB-a
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 117 = _RB-a ;

\ Reconstruct from the application-root slice with a fresh store and reclaim
\ descriptor.  The two root slots, not process memory, reconstruct the fence.
: _RB-cold-discard  ( -- )
    _PSTC-store-b-init PERSIST-S-OK _RB-s
    _PSTC-record-buffer-b 512 _PSTC-work-b PSTORE-WORK-INIT
        PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b PSTORE-PROVISION PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b PSTORE-OPEN PERSIST-S-OK _RB-s
    _PSTC-store-b PSTORE-GENERATION@ 6 = _RB-a
    _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE PERSIST-S-OK _RB-s
    _RB-reclaim-b RECLAIM-INIT PERSIST-S-OK _RB-s
    _PSTC-work-b PSTORE-PAGE-PAYLOAD$ DROP RECLAIM-STATE-SIZE
        _PSTC-store-b _RB-reclaim-b RECLAIM-OPEN PERSIST-S-INVALID _RB-s
    _PSTC-work-b PSTORE-PAGE-PAYLOAD$ DROP
        _RB-state RECLAIM-STATE-SIZE MOVE
    _RB-state RECLAIM-STATE-SIZE
        _PSTC-store-b _RB-reclaim-b RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-reclaim-b RECLAIM-REUSABLE-COUNT@ 33 = _RB-a
    _RB-reclaim-b RECLAIM-FENCE@ 5 = _RB-a ;

\ A protected consumer allocation preserves its caller's exact future
\ retirement promise.  At the final entry of a READY bucket, a full reserve
\ selects high water without moving any reusable or staged state; one slot
\ less permits reuse, retires the exhausted metadata page, and leaves every
\ promised slot available for later retirements and bounded finalization.
: _RB-protected-allocation-contract  ( -- )
    RECLAIM-STEP-RETIREMENT-MAX 2 = _RB-a
    RECLAIM-ALLOCATION-RETIREMENT-MAX 1 = _RB-a
    RECLAIM-FINALIZE-RETIREMENT-MAX 4 = _RB-a

    0 _RB-work _PSTC-store-a _PSTC-work-a
        RECLAIM-ALLOCATE-PROTECTED
        PERSIST-S-BUSY = SWAP -1 = AND _RB-a

    _RB-begin
    -1 _RB-work _PSTC-store-a _PSTC-work-a
        RECLAIM-ALLOCATE-PROTECTED
        PERSIST-S-INVALID = SWAP -1 = AND _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-TX-READY? 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    _RB-begin
    RECLAIM-RETIRED-MAX 1+ _RB-work
        _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE-PROTECTED
        PERSIST-S-INVALID = SWAP -1 = AND _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    \ Current staged work that already fills part of the promise is genuine
    \ capacity, not the READY-exhaustion fallback.
    _RB-begin
    0 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    RECLAIM-RETIRED-MAX _RB-work
        _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE-PROTECTED
        PERSIST-S-CAPACITY = SWAP -1 = AND _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @ 0= _RB-a
    _RB-work _RCW.STAGED-COUNT @ 1 = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    \ Reserve pressure is considered only after the selected READY entry is
    \ semantically valid.  A transaction-local bucket whose final entry is
    \ its own metadata page must report corruption, not escape to high water.
    _RB-begin
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        DUP _RB-reserved !
    DUP _RB-work RECLAIM-CLAIM-HIGH-WATER PERSIST-S-OK _RB-s DROP
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RECLAIM-BUCKET-MAGIC _PSTC-page _RCB.MAGIC !
    _RECLAIM-BUCKET-READY _PSTC-page _RCB.KIND !
    1 _PSTC-page _RCB.COUNT !
    -1 _PSTC-page _RCB.NEXT !
    _RB-reserved @ 0 _PSTC-page _RCB.ENTRY !
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _RB-reserved @
        _PSTC-store-a _PSTC-work-a PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    _RB-reserved @ _RB-work _RCW.STATE _RCS.READY-HEAD !
    0 _RB-work _RCW.STATE _RCS.READY-INDEX !
    1 _RB-work _RCW.STATE _RCS.REUSABLE-COUNT !
    RECLAIM-RETIRED-MAX _RB-work
        _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE-PROTECTED
        PERSIST-S-CORRUPT = SWAP -1 = AND _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @ 1 = _RB-a
    _RB-work _RCW.STAGED-COUNT @ 0= _RB-a
    _RB-work _RCW.STATE _RCS.READY-HEAD @ _RB-reserved @ = _RB-a
    _RB-work _RCW.STATE _RCS.READY-INDEX @ 0= _RB-a
    _RB-work _RCW.STATE _RCS.REUSABLE-COUNT @ 1 = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    \ Position immediately before the last entry in the first READY bucket.
    \ These non-exhausting allocations need no retirement slots.
    _RB-begin
    31 0 ?DO
        I 141 + RECLAIM-RETIRED-MAX _RB-protected-write
        DUP I 82 + = _RB-a DROP
    LOOP
    _RB-work _RCW.ALLOCATED-COUNT @ DUP 31 = _RB-a
        _RB-before-allocated !
    _RB-work _RCW.STAGED-COUNT @ DUP 0= _RB-a _RB-before-staged !
    _RB-work _RCW.STATE _RCS.READY-HEAD @ _RB-before-ready-head !
    _RB-work _RCW.STATE _RCS.READY-INDEX @ DUP 31 = _RB-a
        _RB-before-ready-index !
    _RB-work _RCW.STATE _RCS.REUSABLE-COUNT @ DUP 2 = _RB-a
        _RB-before-reusable !
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _RB-before-proposed !
    _RB-work _RCW.STATE _RB-state RECLAIM-STATE-SIZE MOVE

    RECLAIM-RETIRED-MAX _RB-work
        _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE-PROTECTED
        SWAP _RB-reserved ! PERSIST-S-OK _RB-s
    _RB-reserved @ _RB-before-proposed @ = _RB-a
    _RB-state RECLAIM-STATE-SIZE _RB-work _RCW.STATE
        RECLAIM-STATE-SIZE COMPARE 0= _RB-a
    _RB-work _RCW.STATE _RCS.READY-HEAD @
        _RB-before-ready-head @ = _RB-a
    _RB-work _RCW.STATE _RCS.READY-INDEX @
        _RB-before-ready-index @ = _RB-a
    _RB-work _RCW.STATE _RCS.REUSABLE-COUNT @
        _RB-before-reusable @ = _RB-a
    _RB-work _RCW.STAGED-COUNT @ _RB-before-staged @ = _RB-a
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @
        _RB-before-proposed @ = _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @
        _RB-before-allocated @ 1+ = _RB-a
    _RB-before-allocated @ _RB-work _RCW.ALLOCATED-ENTRY @
        _RB-reserved @ = _RB-a
    0 RECLAIM-RETIRED-MAX 0 _RB-work RECLAIM-TX-ROOM? _RB-a

    \ An unwritten high-water reservation cannot be issued twice.  The
    \ rejected duplicate neither consumes READY state nor adds a ledger row.
    RECLAIM-RETIRED-MAX _RB-work
        _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE-PROTECTED
        PERSIST-S-CONFLICT = SWAP -1 = AND _RB-a
    _RB-state RECLAIM-STATE-SIZE _RB-work _RCW.STATE
        RECLAIM-STATE-SIZE COMPARE 0= _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @
        _RB-before-allocated @ 1+ = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    \ Reserving one slot less permits the boundary entry to be reused and
    \ stages its exhausted READY bucket.  The remaining 63 slots cover 59
    \ caller retirements plus the exact four-slot finalization maximum.
    _RB-begin
    31 0 ?DO
        I 173 + RECLAIM-RETIRED-MAX _RB-protected-write DROP
    LOOP
    204
    RECLAIM-RETIRED-MAX RECLAIM-ALLOCATION-RETIREMENT-MAX -
        _RB-protected-write DUP 113 = _RB-a DROP
    _RB-work _RCW.STAGED-COUNT @ 1 = _RB-a
    _RB-work _RCW.STATE _RCS.REUSABLE-COUNT @ 1 = _RB-a
    0
    RECLAIM-RETIRED-MAX RECLAIM-ALLOCATION-RETIREMENT-MAX -
    0 _RB-work RECLAIM-TX-ROOM? _RB-a
    RECLAIM-RETIRED-MAX
        RECLAIM-ALLOCATION-RETIREMENT-MAX -
        RECLAIM-FINALIZE-RETIREMENT-MAX -
    0 ?DO I I _RB-id ! LOOP
    _RB-ids 32 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    32 _RB-id
    RECLAIM-RETIRED-MAX
        RECLAIM-ALLOCATION-RETIREMENT-MAX -
        RECLAIM-FINALIZE-RETIREMENT-MAX -
        32 -
    _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-work _RCW.STAGED-COUNT @
        RECLAIM-RETIRED-MAX RECLAIM-FINALIZE-RETIREMENT-MAX -
        = _RB-a
    0 RECLAIM-FINALIZE-RETIREMENT-MAX 0
        _RB-work RECLAIM-TX-ROOM? _RB-a
    _RB-work RECLAIM-FINALIZE PERSIST-S-OK _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s

    \ Issued-ledger exhaustion is checked before READY selection and cannot be
    \ mistaken for reserve fallback.
    _RB-begin
    RECLAIM-ALLOCATED-MAX 0 ?DO I 1+ _RB-claim-write DROP LOOP
    0 _RB-work _PSTC-store-a _PSTC-work-a
        RECLAIM-ALLOCATE-PROTECTED
        PERSIST-S-CAPACITY = SWAP -1 = AND _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @ RECLAIM-ALLOCATED-MAX = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-stack ;

: _RB-nth-page-fault  ( point ordinal context -- status )
    DROP SWAP
    _RB-fault-point @ <> IF DROP PERSIST-S-OK EXIT THEN
    DROP 1 _RB-fault-calls +!
    _RB-fault-calls @ _RB-fault-occurrence @ = IF
        PERSIST-S-FAULT
    ELSE
        PERSIST-S-OK
    THEN ;

\ Neither the initial metadata write nor its link rewrite may expose state
\ from a failed finalize.  Exercise both post-write seams at both ordinals;
\ the enclosing PSTORE proposal is aborted before reclaim releases its owner.
: _RB-finalize-page-fault-at  ( fault-point occurrence -- )
    _RB-fault-occurrence ! _RB-fault-point !
    _RB-begin
    0 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-work _RCW.STATE _RB-state RECLAIM-STATE-SIZE MOVE
    0 _RB-fault-calls !
    ['] _RB-nth-page-fault _PSTC-store-a _PST.FAULT-XT !
    _RB-work RECLAIM-FINALIZE PERSIST-S-FAULT _RB-s
    ['] _PSTC-fault _PSTC-store-a _PST.FAULT-XT !
    _RB-fault-calls @ _RB-fault-occurrence @ = _RB-a
    _RB-state RECLAIM-STATE-SIZE
        _RB-work _RCW.STATE RECLAIM-STATE-SIZE COMPARE 0= _RB-a
    _RB-work _RCW.FINALIZED @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s ;

: _RB-finalize-page-faults  ( -- )
    PERSIST-FAULT-PAGE-WRITTEN 1 _RB-finalize-page-fault-at
    PERSIST-FAULT-PAGE-WRITTEN 2 _RB-finalize-page-fault-at
    PERSIST-FAULT-PAGE-VERIFIED 1 _RB-finalize-page-fault-at
    PERSIST-FAULT-PAGE-VERIFIED 2 _RB-finalize-page-fault-at ;

\ Rotation mutates only transaction-local state before its checked output
\ write.  A failure at either post-write seam leaves committed allocator
\ state untouched and remains recoverable by the required layered abort.
: _RB-step-page-fault-at  ( fault-point -- )
    _RB-fault-point ! 1 _RB-fault-occurrence !
    _RB-reclaim _RCL.STATE _RB-state RECLAIM-STATE-SIZE MOVE
    _RB-begin
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 0 ?DO
        I 160 + _RB-alloc-write DROP
    LOOP
    0 _RB-fault-calls !
    ['] _RB-nth-page-fault _PSTC-store-a _PST.FAULT-XT !
    RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
        PERSIST-S-FAULT = SWAP 0= AND _RB-a
    ['] _PSTC-fault _PSTC-store-a _PST.FAULT-XT !
    _RB-fault-calls @ 1 = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _RB-reclaim _RCL.STATE
        RECLAIM-STATE-SIZE COMPARE 0= _RB-a ;

: _RB-step-page-faults  ( -- )
    PERSIST-FAULT-PAGE-WRITTEN _RB-step-page-fault-at
    PERSIST-FAULT-PAGE-VERIFIED _RB-step-page-fault-at ;

\ With 32 data allocations and their exhausted ready-bucket metadata already
\ staged, finalization crosses the pending-bucket boundary.  Reserve is raw,
\ not staged+reserve, so the final reusable id is consumed and only one new
\ high-water metadata page is appended.
: _RB-staged-metadata-boundary  ( -- )
    _RB-begin
    32 0 ?DO
        I 120 + _RB-alloc-write DUP I 82 + = _RB-a DROP
    LOOP
    _RB-work _RCW.STAGED-COUNT @ 1 = _RB-a
    32 0 ?DO I I _RB-id ! LOOP
    _RB-ids 32 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-work _RCW.STAGED-COUNT @ 33 = _RB-a
    _RB-work RECLAIM-FINALIZE PERSIST-S-OK _RB-s
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ PROOTV.PAGE-COUNT @ 118 = _RB-a
    _RB-work _RCW.STATE _RCS.REUSABLE-COUNT @ 0= _RB-a
    _RB-work _RCW.STAGED-COUNT @ 0= _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s ;

: _RB-repeat-churn  ( -- )
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 117 = _RB-a
    _RB-begin
    101 _RB-alloc-write DUP 82 = _RB-a _RB-root !
    8 0 ?DO
        I _RB-alloc-write DUP I 83 + = _RB-a I _RB-id !
    LOOP
    81 8 _RB-id !
    _RB-ids 9 _RB-work RECLAIM-RELEASE-BATCH PERSIST-S-OK _RB-s
    _RB-root @ _RB-finish
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 117 = _RB-a
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 30 = _RB-a
    _RB-root @ 82 = _RB-a

    _RB-begin
    102 _RB-alloc-write DUP 83 = _RB-a _RB-root !
    7 0 ?DO
        I _RB-alloc-write DUP I 84 + = _RB-a I _RB-id !
    LOOP
    7 _RB-alloc-write DUP 93 = _RB-a 7 _RB-id !
    82 8 _RB-id !
    _RB-ids 9 _RB-work RECLAIM-RELEASE-BATCH PERSIST-S-OK _RB-s
    _RB-root @ _RB-finish
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 117 = _RB-a
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 27 = _RB-a
    _RB-root @ 83 = _RB-a ;

: _RB-discard-abort  ( -- )
    _RB-begin
    92 _RB-alloc-write DUP 84 = _RB-a 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-OK _RB-s
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 27 = _RB-a
    _RB-begin
    93 _RB-alloc-write DUP 84 = _RB-a DROP
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s ;

: _RB-discard-cap  ( -- )
    _RB-begin
    65 0 ?DO I _RB-alloc-write I _RB-id ! LOOP
    _RB-ids 32 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-OK _RB-s
    32 _RB-id 32 _RB-work RECLAIM-DISCARD-BATCH PERSIST-S-OK _RB-s
    _RB-work _RCW.DISCARD-COUNT @ 64 = _RB-a
    _RB-work _RCW.STAGED-COUNT @ _RB-before-staged !
    _RB-work _RCW.DISCARD-COUNT @ _RB-before-discard !
    64 _RB-id @ 1 _RB-id !
    0 0 _RB-id !
    _RB-ids 2 _RB-work RECLAIM-RELEASE-BATCH
        PERSIST-S-CAPACITY _RB-s
    _RB-work _RCW.STAGED-COUNT @ _RB-before-staged @ = _RB-a
    _RB-work _RCW.DISCARD-COUNT @ _RB-before-discard @ = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s ;

: _RB-allocate-cap  ( -- )
    _RB-begin
    128 0 ?DO I _RB-alloc-write DROP LOOP
    _RB-work _RCW.ALLOCATED-COUNT @ 128 = _RB-a
    _RB-work _PSTC-store-a _PSTC-work-a RECLAIM-ALLOCATE
        PERSIST-S-CAPACITY = SWAP -1 = AND _RB-a
    _RB-work _RCW.ALLOCATED-COUNT @ 128 = _RB-a
    _PSTC-store-a _PSTC-work-a PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work RECLAIM-ABORT PERSIST-S-OK _RB-s ;

\ A fault after durable publication can return non-OK while PSTORE has already
\ adopted the new generation.  Reclaim follows that authority and may adopt.
: _RB-post-durable  ( -- )
    _RB-begin
    94 _RB-alloc-write DUP 84 = _RB-a _RB-root !
    83 0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-work RECLAIM-FINALIZE PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PSTC-page RECLAIM-STATE-SIZE _RB-work RECLAIM-STATE!
        PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _RB-root @
        _PSTC-store-a _PSTC-work-a PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    _RB-root @ _PSTC-store-a _PSTC-work-a PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    PERSIST-FAULT-ROOT-PUBLISHED _PSTC-fault-at !
    _PSTC-store-a _PSTC-work-a PSTORE-COMMIT PERSIST-S-FAULT _RB-s
    0 _PSTC-fault-at !
    _PSTC-store-a PSTORE-GENERATION@ 9 = _RB-a
    _PSTC-work-a PSTORE-PROPOSED-ROOT@ 0= _RB-a
    _RB-work _RB-reclaim RECLAIM-ADOPT PERSIST-S-OK _RB-s
    _RB-reclaim RECLAIM-GENERATION@ 9 = _RB-a ;

\ Rotation and allocation share one bucket scratch buffer.  Exercise rotation
\ while reusable ids remain, then exhaust that ready chain and persist it.
\ A cold reopen must find a PENDING OUT bucket, promote it, and allocate from
\ the promoted population; copying allocator scratch would instead persist a
\ READY bucket under OUT and make the later STEP report CORRUPT.
: _RB-ready-backed-rotation-cold  ( -- )
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 0> _RB-a
    _RB-begin
    RECLAIM-MAX-BATCH 0 ?DO
        _RB-work _RCW.STATE _RCS.OUT-HEAD @ -1 = IF
            RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
                PERSIST-S-OK = SWAP 0= AND _RB-a
        ELSE
            LEAVE
        THEN
    LOOP
    _RB-work _RCW.STATE _RCS.OUT-HEAD @ 0>= _RB-a
    210 _RB-alloc-write _RB-finish
    _RB-reclaim _RCL.STATE _RCS.OUT-HEAD @ DUP 0>= _RB-a
    DUP _RB-reserved !
    _PSTC-store-a _PSTC-work-a PSTORE-READ-PAGE PERSIST-S-OK _RB-s
    _PSTC-work-a PSTORE-PAGE-PAYLOAD$ DROP
        _RCB.KIND @ _RECLAIM-BUCKET-PENDING = _RB-a

    _RB-begin
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ DUP 0> _RB-a
    0 ?DO
        I 211 + _RB-alloc-write DUP _RB-root ! DROP
    LOOP
    _RB-root @ _RB-finish
    _RB-reclaim _RCL.STATE _RCS.READY-HEAD @ -1 = _RB-a
    _RB-reclaim _RCL.STATE _RCS.READY-INDEX @ 0= _RB-a
    _RB-reclaim RECLAIM-REUSABLE-COUNT@ 0= _RB-a
    _RB-reclaim _RCL.STATE RECLAIM-STATE-SIZE
        RECLAIM-STATE-VALID? _RB-a

    _PSTC-store-b-init PERSIST-S-OK _RB-s
    _PSTC-record-buffer-b 512 _PSTC-work-b PSTORE-WORK-INIT
        PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b PSTORE-PROVISION PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b PSTORE-OPEN PERSIST-S-OK _RB-s
    _PSTC-store-b PSTORE-CURRENT-ROOT@ PROOTV.APPLICATION-ROOT @
        _PSTC-store-b _PSTC-work-b PSTORE-READ-PAGE PERSIST-S-OK _RB-s
    _PSTC-work-b PSTORE-PAGE-PAYLOAD$ DROP
        _RB-state RECLAIM-STATE-SIZE MOVE
    _RB-reclaim-b RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE
        _PSTC-store-b _RB-reclaim-b RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-reclaim-b _RCL.STATE _RCS.READY-HEAD @ -1 = _RB-a
    _RB-reclaim-b _RCL.STATE _RCS.READY-INDEX @ 0= _RB-a
    _RB-reclaim-b RECLAIM-REUSABLE-COUNT@ 0= _RB-a

    \ This older allocator-scratch fixture intentionally has no application
    \ page enumerator for the synthetic 70-page base.  Bind its test-only
    \ descriptor directly; the focused cold-authority contract below proves
    \ the public audit/latch path against a completely classified store.
    _PSTC-store-b PSTORE-GENERATION@
        _RB-reclaim-b _RCL.AUDITED-GENERATION !
    _PSTC-store-b _PSTC-work-b PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b _RB-reclaim-b _RB-work-b
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    RECLAIM-MAX-BATCH _RB-work-b RECLAIM-STEP
        PERSIST-S-OK = SWAP 0> AND _RB-a
    _RB-work-b _PSTC-store-b _PSTC-work-b RECLAIM-ALLOCATE
        PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 222 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE ROT
        _PSTC-store-b _PSTC-work-b PSTORE-WRITE-PAGE-TX PERSIST-S-OK _RB-s
    _PSTC-store-b _PSTC-work-b PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work-b RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-stack ;

: _RB-cadence-retire  ( page-id -- )
    DUP 0< IF DROP EXIT THEN
    0 _RB-id !
    _RB-ids 1 _RB-work RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s ;

: _RB-cadence-allocate  ( byte -- page-id )
    RECLAIM-MAX-BATCH _RB-work RECLAIM-STEP
        PERSIST-S-OK _RB-s DROP
    _RB-alloc-write ;

: _RB-cadence-one  ( -- )
    _RB-begin
    231 _RB-cadence-allocate _RB-cadence-new-a !
    _RB-cadence-live-a @ _RB-cadence-retire
    232 _RB-cadence-allocate _RB-cadence-new-b !
    _RB-cadence-live-b @ _RB-cadence-retire
    _RB-cadence-new-b @ _RB-finish
    _RB-cadence-new-a @ _RB-cadence-live-a !
    _RB-cadence-new-b @ _RB-cadence-live-b ! ;

\ Two bounded maintenance calls must service one small finalized retirement
\ bucket per generation even while READY retains a partial population.  The
\ old empty-only promotion gate accumulated IN/OUT backlog and grew by about
\ two physical pages per transaction under exactly this cadence.
: _RB-small-batch-cadence  ( -- )
    _RB-current-app-root _RB-cadence-live-a !
    -1 _RB-cadence-live-b !
    32 0 ?DO _RB-cadence-one LOOP
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @
        _RB-cadence-warm-pages !
    _RB-reclaim RECLAIM-RETIRED-COUNT@
        _RB-cadence-warm-retired !
    32 0 ?DO _RB-cadence-one LOOP
    _PSTC-store-a PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @
        _RB-cadence-warm-pages @
    2DUP <> IF
        ." PERSISTENCE RECLAIM CADENCE warm/final " 2DUP . . CR
    THEN
    = _RB-a
    _RB-reclaim RECLAIM-RETIRED-COUNT@
        _RB-cadence-warm-retired @
    2DUP > IF
        ." PERSISTENCE RECLAIM CADENCE retired warm/final " 2DUP . . CR
    THEN
    <= _RB-a
    _RB-reclaim _RCL.STATE RECLAIM-STATE-SIZE
        RECLAIM-STATE-VALID? _RB-a
    _RB-stack ;

: _RB-i-allocate  ( byte reclaim-work store pstore-work -- )
    >R
    OVER OVER R@ RECLAIM-ALLOCATE
        PERSIST-S-OK = SWAP 0= AND _RB-a
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 4 PICK FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 3 PICK R@
        PSTORE-WRITE-PAGE-TX PERSIST-S-OK _RB-s
    2DROP DROP R> DROP ;

: _RB-i-finalize  ( reclaim-work store pstore-work -- )
    >R
    OVER RECLAIM-FINALIZE PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PSTC-page RECLAIM-STATE-SIZE 3 PICK RECLAIM-STATE!
        PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 3 PICK R@
        PSTORE-WRITE-PAGE-TX PERSIST-S-OK _RB-s
    0 OVER R@ PSTORE-APPLICATION-ROOT! PERSIST-S-OK _RB-s
    2DROP R> DROP ;

\ Four active stores share code but no descriptor, workspace, allocator state,
\ VFS binding, or transaction ownership.
: _RB-four-store  ( -- )
    _PSTC-interleave-init
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    _RB-reclaim-i0 RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-reclaim-i1 RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-reclaim-i2 RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-reclaim-i3 RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i0 _RB-reclaim-i0
        RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i1 _RB-reclaim-i1
        RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i2 _RB-reclaim-i2
        RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i3 _RB-reclaim-i3
        RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-work-i0 RECLAIM-WORK-INIT PERSIST-S-OK _RB-s
    _RB-work-i1 RECLAIM-WORK-INIT PERSIST-S-OK _RB-s
    _RB-work-i2 RECLAIM-WORK-INIT PERSIST-S-OK _RB-s
    _RB-work-i3 RECLAIM-WORK-INIT PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 _RB-reclaim-i0 _RB-work-i0
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i1 _PSTC-work-i1 _RB-reclaim-i1 _RB-work-i1
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i2 _PSTC-work-i2 _RB-reclaim-i2 _RB-work-i2
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i3 _PSTC-work-i3 _RB-reclaim-i3 _RB-work-i3
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    11 _RB-work-i0 _PSTC-store-i0 _PSTC-work-i0 _RB-i-allocate
    22 _RB-work-i1 _PSTC-store-i1 _PSTC-work-i1 _RB-i-allocate
    33 _RB-work-i2 _PSTC-store-i2 _PSTC-work-i2 _RB-i-allocate
    44 _RB-work-i3 _PSTC-store-i3 _PSTC-work-i3 _RB-i-allocate
    _RB-work-i0 _PSTC-store-i0 _PSTC-work-i0 _RB-i-finalize
    _RB-work-i1 _PSTC-store-i1 _PSTC-work-i1 _RB-i-finalize
    _RB-work-i2 _PSTC-store-i2 _PSTC-work-i2 _RB-i-finalize
    _RB-work-i3 _PSTC-store-i3 _PSTC-work-i3 _RB-i-finalize
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-COMMIT PERSIST-S-OK _RB-s
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-COMMIT PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-COMMIT PERSIST-S-OK _RB-s
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-COMMIT PERSIST-S-OK _RB-s
    _RB-work-i3 _RB-reclaim-i3 RECLAIM-ADOPT PERSIST-S-OK _RB-s
    _RB-work-i1 _RB-reclaim-i1 RECLAIM-ADOPT PERSIST-S-OK _RB-s
    _RB-work-i0 _RB-reclaim-i0 RECLAIM-ADOPT PERSIST-S-OK _RB-s
    _RB-work-i2 _RB-reclaim-i2 RECLAIM-ADOPT PERSIST-S-OK _RB-s
    _RB-reclaim-i0 RECLAIM-GENERATION@ 1 = _RB-a
    _RB-reclaim-i1 RECLAIM-GENERATION@ 1 = _RB-a
    _RB-reclaim-i2 RECLAIM-GENERATION@ 1 = _RB-a
    _RB-reclaim-i3 RECLAIM-GENERATION@ 1 = _RB-a ;

\ A proving application root used only by the cold-authority contracts stores
\ reclaim state at byte zero, then a cell count and a bounded list of all
\ additional consumer-owned page ids at bytes 128 and 136.  The root page
\ itself is submitted separately and may not reappear in that list.
: _RB-audit-reenter-i0-same  ( -- status )
    _RB-audit-map 3
    _RB-audit-enumerator-xt @ 0
    _RB-reclaim-i0 _PSTC-store-i0 _PSTC-work-i0 _RB-audit-work
    RECLAIM-AUDIT-CURRENT ;

: _RB-audit-reenter-i0-second  ( -- status )
    _RB-audit-map 3
    _RB-audit-enumerator-xt @ 0
    _RB-reclaim-i0 _PSTC-store-i0 _PSTC-work-i0 _RB-audit-work-2
    RECLAIM-AUDIT-CURRENT ;

: _RB-audit-overlap-reclaim  ( -- reclaim )
    _RB-audit-overlap-region _RB-AUDIT-RECLAIM-OFFSET + ;

: _RB-audit-alias-reclaim  ( -- reclaim )
    _RB-audit-alias-pstore-work _PSW.PAGE-WORK
        _PPW.RECORD PERSIST-RECORD-HEADER-SIZE + ;

: _RB-audit-enumerator
  ( snapshot-root generation slot audit-work context -- status )
    4 PICK PROOTV.PAGE-COUNT @ _RB-audit-slot-pages !
    DROP SWAP DROP SWAP DROP
    1 _RB-audit-calls +!
    _RB-audit-callback-mode @ 1 = IF
        2DROP PERSIST-S-OK EXIT
    THEN
    _RB-audit-callback-mode @ 2 = IF -99 THROW THEN
    _RB-audit-callback-mode @ 3 = IF
        2DROP 123 EXIT
    THEN
    _RB-audit-callback-mode @ 4 = IF
        2DROP PERSIST-S-CONFLICT EXIT
    THEN
    _RB-audit-callback-mode @ 5 = IF
        _RB-audit-reenter-i0-same PERSIST-S-BUSY _RB-s
        _RB-audit-work _RCA.STATUS @ PERSIST-S-OK _RB-s
        _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 0= _RB-a
        _RB-reclaim-i0 _RCL.AUDIT-WORK @ _RB-audit-work = _RB-a
    THEN
    _RB-audit-callback-mode @ 6 = IF
        _RB-audit-reenter-i0-second PERSIST-S-BUSY _RB-s
        _RB-audit-work-2 _RCA.STATUS @ PERSIST-S-INVALID _RB-s
        _RB-audit-work-2 _RCA.BUSY @ 0= _RB-a
        _RB-reclaim-i0 _RCL.AUDIT-WORK @ _RB-audit-work = _RB-a
    THEN
    _RB-audit-callback-mode @ 7 = IF
        _PSTC-store-i0 _PSTC-work-i0 _RB-reclaim-i0 _RB-work-i0
            RECLAIM-TX-BEGIN PERSIST-S-BUSY _RB-s
        _RB-work-i0 _RCW.ACTIVE @ 0= _RB-a
        _PSTC-store-i0 _PSTC-work-i0 PSTORE-TX-READY? _RB-a
        _RB-reclaim-i0 _RCL.AUDIT-WORK @ _RB-audit-work = _RB-a
    THEN
    _RB-audit-callback-mode @ 8 = IF
        _PSTC-store-i1 _PSTC-work-i1 _RB-reclaim-i1 _RB-work-i1
            RECLAIM-TX-BEGIN PERSIST-S-BUSY _RB-s
        _RB-work-i1 _RCW.ACTIVE @ 0= _RB-a
        _PSTC-store-i1 _PSTC-work-i1 PSTORE-TX-READY? _RB-a
        _RB-reclaim-i1 _RCL.AUDIT-WORK @ _RB-audit-work = _RB-a
    THEN
    SWAP PROOTV.APPLICATION-ROOT @ SWAP
    2DUP RECLAIM-AUDIT-APPLICATION-ROOT!
    DUP IF -ROT 2DROP EXIT THEN DROP
    OVER _RB-audit-store @ _RB-audit-pstore-work @
        PSTORE-READ-PAGE-SNAPSHOT-TX
    DUP IF -ROT 2DROP EXIT THEN DROP
    NIP
    _RB-audit-pstore-work @ PSTORE-PAGE-PAYLOAD$
    DUP PERSIST-PAGE-PAYLOAD-SIZE <> IF
        2DROP DROP PERSIST-S-CORRUPT EXIT
    THEN
    DROP DUP _RB-audit-payload !
    DUP RECLAIM-STATE-SIZE 3 PICK RECLAIM-AUDIT-STATE!
    DUP IF -ROT 2DROP EXIT THEN DROP
    DUP RECLAIM-STATE-SIZE + @
    DUP 0< OVER 64 > OR IF
        DROP 2DROP PERSIST-S-CORRUPT EXIT
    THEN
    0 ?DO
        DUP RECLAIM-STATE-SIZE CELL+ + I CELLS + @
        2 PICK RECLAIM-AUDIT-APPLICATION-PAGE
        DUP IF -ROT 2DROP UNLOOP EXIT THEN DROP
    LOOP
    DROP
    _RB-audit-callback-mode @ 9 = IF
        _RB-audit-slot-pages @ 1 > IF
            1 OVER RECLAIM-AUDIT-APPLICATION-PAGE
            DUP IF NIP EXIT THEN DROP
            1 OVER
            RECLAIM-AUDIT-APPLICATION-PAGE-SHARED
            DUP IF NIP EXIT THEN DROP
        THEN
    THEN
    _RB-audit-callback-mode @ 10 = IF
        _RB-audit-slot-pages @ 1 > IF
            1 _RB-audit-slot-pages @ 1- 2 PICK
                RECLAIM-AUDIT-APPLICATION-ARENA!
            DUP IF NIP EXIT THEN DROP
        THEN
    THEN
    _RB-audit-callback-mode @ 11 = IF
        _RB-audit-slot-pages @ 2 > IF
            2 1 2 PICK RECLAIM-AUDIT-APPLICATION-ARENA!
            DUP IF NIP EXIT THEN DROP
        THEN
    THEN
    RECLAIM-AUDIT-APPLICATION-COMPLETE ;

: _RB-audit-call-i0  ( map-u -- status )
    _RB-audit-map SWAP
    ['] _RB-audit-enumerator 0
    _RB-reclaim-i0 _PSTC-store-i0 _PSTC-work-i0 _RB-audit-work
    RECLAIM-AUDIT-CURRENT ;

: _RB-audit-call-i1  ( map-u -- status )
    _RB-audit-map SWAP
    ['] _RB-audit-enumerator 0
    _RB-reclaim-i1 _PSTC-store-i1 _PSTC-work-i1 _RB-audit-work
    RECLAIM-AUDIT-CURRENT ;

: _RB-audit-call-i2  ( map-u -- status )
    _RB-audit-map SWAP
    ['] _RB-audit-enumerator 0
    _RB-reclaim-i2 _PSTC-store-i2 _PSTC-work-i2 _RB-audit-work
    RECLAIM-AUDIT-CURRENT ;

: _RB-audit-call-i3  ( map-u -- status )
    _RB-audit-map SWAP
    ['] _RB-audit-enumerator 0
    _RB-reclaim-i3 _PSTC-store-i3 _PSTC-work-i3 _RB-audit-work
    RECLAIM-AUDIT-CURRENT ;

: _RB-audit-shape-out-store-init  ( -- status )
    S" /rba-shape-out-pages" S" /rba-shape-out-segment"
    S" /rba-shape-out-root-a" S" /rba-shape-out-root-b"
    _RB-audit-shape-identity 256 _PSTC-vfs @ 0 0
    _RB-audit-shape-guard ['] _PSTC-fault 0
    _RB-audit-shape-store PSTORE-INIT ;

: _RB-audit-shape-rotate-store-init  ( -- status )
    S" /rba-shape-rotate-pages" S" /rba-shape-rotate-segment"
    S" /rba-shape-rotate-root-a" S" /rba-shape-rotate-root-b"
    _RB-audit-shape-identity 256 _PSTC-vfs @ 0 0
    _RB-audit-shape-guard ['] _PSTC-fault 0
    _RB-audit-shape-store PSTORE-INIT ;

: _RB-audit-shape-ready-store-init  ( -- status )
    S" /rba-shape-ready-pages" S" /rba-shape-ready-segment"
    S" /rba-shape-ready-root-a" S" /rba-shape-ready-root-b"
    _RB-audit-shape-identity 256 _PSTC-vfs @ 0 0
    _RB-audit-shape-guard ['] _PSTC-fault 0
    _RB-audit-shape-store PSTORE-INIT ;

: _RB-audit-shape-open  ( -- )
    _RB-audit-shape-buffer 512 _RB-audit-shape-pstore-work
        PSTORE-WORK-INIT PERSIST-S-OK _RB-s
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-PROVISION PERSIST-S-OK _RB-s
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-OPEN PERSIST-S-ABSENT _RB-s
    _RB-audit-shape-reclaim RECLAIM-INIT PERSIST-S-OK _RB-s ;

: _RB-audit-shape-append  ( expected-page-id -- )
    >R
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE
        _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-APPEND-PAGE
    PERSIST-S-OK = SWAP R> = AND _RB-a ;

: _RB-audit-shape-publish-and-audit  ( page-count -- )
    _RB-audit-shape-pages !
    0 _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-APPLICATION-ROOT! PERSIST-S-OK _RB-s
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-COMMIT PERSIST-S-OK _RB-s
    _RB-audit-shape-store PSTORE-ROOT-FILE@
        _RB-audit-shape-pstore-work _PSW.ROOT-WORK
        PROOT-MIRROR PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _RB-audit-shape-store
        _RB-audit-shape-reclaim RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-BEGIN PERSIST-S-OK _RB-s
    _RB-audit-shape-store _RB-audit-store !
    _RB-audit-shape-pstore-work _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    _RB-audit-map _RB-audit-shape-pages @
        ['] _RB-audit-enumerator 0
        _RB-audit-shape-reclaim _RB-audit-shape-store
        _RB-audit-shape-pstore-work _RB-audit-work
        RECLAIM-AUDIT-CURRENT PERSIST-S-OK _RB-s
    _RB-audit-calls @ 1 = _RB-a
    _RB-audit-shape-reclaim RECLAIM-AUDITED-GENERATION@ 1 = _RB-a
    _RB-audit-shape-reclaim _RCL.AUDIT-WORK @ 0= _RB-a
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ OUT may begin partway through its head bucket.  The consumed prefix page is
\ already application-owned, while only the active suffix contributes to the
\ exact retired count.
: _RB-audit-healthy-partial-out  ( -- )
    _RB-audit-shape-identity PERSIST-IDENTITY-SIZE 9 FILL
    _RB-audit-shape-out-store-init PERSIST-S-OK _RB-s
    _RB-audit-shape-open
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    3 _RB-state _RCS.OUT-HEAD !
    1 _RB-state _RCS.OUT-INDEX !
    1 _RB-state _RCS.RETIRED-COUNT !
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-VALID? _RB-a
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-BEGIN PERSIST-S-OK _RB-s

    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RB-state _PSTC-page RECLAIM-STATE-SIZE MOVE
    1 _PSTC-page RECLAIM-STATE-SIZE + !
    1 _PSTC-page RECLAIM-STATE-SIZE CELL+ + !
    0 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 41 FILL
    1 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 42 FILL
    2 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RECLAIM-BUCKET-MAGIC _PSTC-page _RCB.MAGIC !
    _RECLAIM-BUCKET-PENDING _PSTC-page _RCB.KIND !
    1 _PSTC-page _RCB.GENERATION !
    2 _PSTC-page _RCB.COUNT !
    -1 _PSTC-page _RCB.NEXT !
    1 0 _PSTC-page _RCB.ENTRY !
    2 1 _PSTC-page _RCB.ENTRY !
    3 _RB-audit-shape-append
    4 _RB-audit-shape-publish-and-audit ;

\ A live rotation has both nonempty SOURCE and BUILD chains.  Their equal
\ generation boundary is legal, both populations are counted, and OUT stays
\ empty until rotation completes.
: _RB-audit-healthy-mid-rotation  ( -- )
    _RB-audit-shape-rotate-store-init PERSIST-S-OK _RB-s
    _RB-audit-shape-open
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    3 _RB-state _RCS.ROTATE-SOURCE !
    4 _RB-state _RCS.ROTATE-BUILD !
    2 _RB-state _RCS.RETIRED-COUNT !
    -1 _RB-state _RCS.ROTATING !
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-VALID? _RB-a
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-BEGIN PERSIST-S-OK _RB-s

    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RB-state _PSTC-page RECLAIM-STATE-SIZE MOVE
    0 _PSTC-page RECLAIM-STATE-SIZE + !
    0 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 51 FILL
    1 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 52 FILL
    2 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RECLAIM-BUCKET-MAGIC _PSTC-page _RCB.MAGIC !
    _RECLAIM-BUCKET-PENDING _PSTC-page _RCB.KIND !
    1 _PSTC-page _RCB.GENERATION !
    1 _PSTC-page _RCB.COUNT !
    -1 _PSTC-page _RCB.NEXT !
    1 0 _PSTC-page _RCB.ENTRY !
    3 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RECLAIM-BUCKET-MAGIC _PSTC-page _RCB.MAGIC !
    _RECLAIM-BUCKET-PENDING _PSTC-page _RCB.KIND !
    1 _PSTC-page _RCB.GENERATION !
    1 _PSTC-page _RCB.COUNT !
    -1 _PSTC-page _RCB.NEXT !
    2 0 _PSTC-page _RCB.ENTRY !
    4 _RB-audit-shape-append
    5 _RB-audit-shape-publish-and-audit ;

\ READY links may skip a consumed prefix in the next bucket.  That prefix is
\ application-owned; the two active suffix ids and both metadata pages account
\ for the rest of the committed snapshot.
: _RB-audit-healthy-chained-ready  ( -- )
    _RB-audit-shape-ready-store-init PERSIST-S-OK _RB-s
    _RB-audit-shape-open
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    4 _RB-state _RCS.READY-HEAD !
    2 _RB-state _RCS.REUSABLE-COUNT !
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-VALID? _RB-a
    _RB-audit-shape-store _RB-audit-shape-pstore-work
        PSTORE-BEGIN PERSIST-S-OK _RB-s

    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RB-state _PSTC-page RECLAIM-STATE-SIZE MOVE
    1 _PSTC-page RECLAIM-STATE-SIZE + !
    1 _PSTC-page RECLAIM-STATE-SIZE CELL+ + !
    0 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 61 FILL
    1 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 62 FILL
    2 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 63 FILL
    3 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RECLAIM-BUCKET-MAGIC _PSTC-page _RCB.MAGIC !
    _RECLAIM-BUCKET-READY _PSTC-page _RCB.KIND !
    1 _PSTC-page _RCB.COUNT !
    5 _PSTC-page _RCB.NEXT !
    1 _PSTC-page _RCB.NEXT-INDEX !
    2 0 _PSTC-page _RCB.ENTRY !
    4 _RB-audit-shape-append
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RECLAIM-BUCKET-MAGIC _PSTC-page _RCB.MAGIC !
    _RECLAIM-BUCKET-READY _PSTC-page _RCB.KIND !
    2 _PSTC-page _RCB.COUNT !
    -1 _PSTC-page _RCB.NEXT !
    1 0 _PSTC-page _RCB.ENTRY !
    3 1 _PSTC-page _RCB.ENTRY !
    5 _RB-audit-shape-append
    6 _RB-audit-shape-publish-and-audit ;

\ A valid reclaim descriptor embedded in otherwise-unused audit scratch is
\ still an illegal authority alias.  Rejection precedes every audit-work
\ binding store, so both complete objects remain byte-exact and valid.
: _RB-audit-overlap-arguments  ( -- )
    _RB-audit-overlap-region RECLAIM-AUDIT-WORK-INIT
        PERSIST-S-OK _RB-s
    _RB-audit-overlap-reclaim RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i0
        _RB-audit-overlap-reclaim RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-audit-overlap-region RECLAIM-AUDIT-WORK-VALID? _RB-a
    _RB-audit-overlap-reclaim RECLAIM-VALID? _RB-a
    _RB-audit-overlap-region RECLAIM-AUDIT-WORK-SIZE
        _RB-audit-overlap-reclaim RECLAIM-SIZE
        MSPAN-OVERLAP? _RB-a

    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _RB-audit-store !
    _PSTC-work-i0 _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    _RB-audit-overlap-region _RB-audit-overlap-before
        RECLAIM-AUDIT-WORK-SIZE MOVE
    _RB-audit-overlap-reclaim _RB-audit-overlap-reclaim-before
        RECLAIM-SIZE MOVE
    _RB-audit-overlap-region RECLAIM-AUDIT-WORK-SIZE
        _RB-audit-overlap-before RECLAIM-AUDIT-WORK-SIZE
        COMPARE 0= _RB-a
    _RB-audit-overlap-reclaim RECLAIM-SIZE
        _RB-audit-overlap-reclaim-before RECLAIM-SIZE
        COMPARE 0= _RB-a
    _RB-audit-map 3 ['] _RB-audit-enumerator 0
        _RB-audit-overlap-reclaim _PSTC-store-i0 _PSTC-work-i0
        _RB-audit-overlap-region
        RECLAIM-AUDIT-CURRENT PERSIST-S-INVALID _RB-s
    _RB-audit-calls @ 0= _RB-a
    _RB-audit-overlap-region RECLAIM-AUDIT-WORK-SIZE
        _RB-audit-overlap-before RECLAIM-AUDIT-WORK-SIZE
        COMPARE 0= _RB-a
    _RB-audit-overlap-reclaim RECLAIM-SIZE
        _RB-audit-overlap-reclaim-before RECLAIM-SIZE
        COMPARE 0= _RB-a
    _RB-audit-overlap-region RECLAIM-AUDIT-WORK-VALID? _RB-a
    _RB-audit-overlap-reclaim RECLAIM-VALID? _RB-a
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-TX-READY? _RB-a
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ Publish one exact nonempty state in a previously fresh proving store.  The
\ old application root becomes generation-2 PENDING, so the subsequent audit
\ must validate both distinct slots and the strict old-live retirement rule.
: _RB-audit-build-in  ( -- )
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 _RB-reclaim-i0 _RB-work-i0
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _RB-work-i0 _PSTC-store-i0 _PSTC-work-i0 RECLAIM-ALLOCATE
        PERSIST-S-OK _RB-s
    DUP 1 = _RB-a _RB-root !
    \ A high-water allocation is only reserved until its consumer physically
    \ claims the exact id.  Claim page one before FINALIZE asks reclaim for
    \ the following metadata page.
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _RB-root @
        _PSTC-store-i0 _PSTC-work-i0 PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    0 0 _RB-id !
    _RB-ids 1 _RB-work-i0 RECLAIM-RETIRE-BATCH PERSIST-S-OK _RB-s
    _RB-work-i0 RECLAIM-FINALIZE PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PSTC-page RECLAIM-STATE-SIZE _RB-work-i0 RECLAIM-STATE!
        PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE _RB-root @
        _PSTC-store-i0 _PSTC-work-i0 PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    _RB-root @ _PSTC-store-i0 _PSTC-work-i0 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-COMMIT PERSIST-S-OK _RB-s
    _RB-work-i0 _RB-reclaim-i0 RECLAIM-ADOPT PERSIST-S-OK _RB-s
    _RB-reclaim-i0 RECLAIM-GENERATION@ 2 = _RB-a
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 2 = _RB-a
    _PSTC-store-i0 PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 3 = _RB-a ;

: _RB-audit-empty-root  ( -- )
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _PSTC-page RECLAIM-STATE-SIZE RECLAIM-STATE-INIT
        PERSIST-S-OK _RB-s
    0 _PSTC-page RECLAIM-STATE-SIZE + ! ;

: _RB-audit-root-list1  ( page-id -- )
    _RB-audit-empty-root
    1 _PSTC-page RECLAIM-STATE-SIZE + !
    _PSTC-page RECLAIM-STATE-SIZE CELL+ + ! ;

: _RB-audit-root-list3  ( -- )
    _RB-audit-empty-root
    3 _PSTC-page RECLAIM-STATE-SIZE + !
    1 _PSTC-page RECLAIM-STATE-SIZE CELL+ + !
    2 _PSTC-page RECLAIM-STATE-SIZE CELL+ + CELL+ !
    3 _PSTC-page RECLAIM-STATE-SIZE CELL+ + 2 CELLS + ! ;

: _RB-audit-pending-bucket  ( generation page-id -- )
    >R
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 FILL
    _RECLAIM-BUCKET-MAGIC _PSTC-page _RCB.MAGIC !
    _RECLAIM-BUCKET-PENDING _PSTC-page _RCB.KIND !
    DUP _PSTC-page _RCB.GENERATION !
    1 _PSTC-page _RCB.COUNT !
    -1 _PSTC-page _RCB.NEXT !
    R> 0 _PSTC-page _RCB.ENTRY !
    DROP ;

\ Mirrored current slots are one durable snapshot, not two generations of
\ ownership evidence.  Count the callback itself so a successful audit proves
\ the byte-identical peer was deduplicated.
: _RB-audit-mirrored-once  ( -- )
    _PSTC-store-i1 PSTORE-ROOT-FILE@
    _PSTC-work-i1 _PSW.ROOT-WORK PROOT-MIRROR PERSIST-S-OK _RB-s
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i1 _RB-audit-store !
    _PSTC-work-i1 _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    1 _RB-audit-call-i1 PERSIST-S-OK _RB-s
    _RB-audit-calls @ 1 = _RB-a
    8 _RB-audit-callback-mode !
    1 _RB-audit-call-i1 PERSIST-S-OK _RB-s
    _RB-reclaim-i1 _RCL.AUDIT-WORK @ 0= _RB-a
    _RB-reclaim-i1 RECLAIM-AUDITED-GENERATION@ 1 = _RB-a
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ Recursive use of the same audit work, a second audit work, and reclaim
\ transaction begin all observe the descriptor fence and leave the outer
\ audit's status and latch ownership intact.
: _RB-audit-reentry  ( -- )
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _RB-audit-store !
    _PSTC-work-i0 _RB-audit-pstore-work !
    5 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-OK _RB-s
    _RB-reclaim-i0 _RCL.AUDIT-WORK @ 0= _RB-a
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 2 = _RB-a
    6 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-OK _RB-s
    _RB-reclaim-i0 _RCL.AUDIT-WORK @ 0= _RB-a
    _RB-audit-work-2 _RCA.STATUS @ PERSIST-S-INVALID _RB-s
    7 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-OK _RB-s
    _RB-reclaim-i0 _RCL.AUDIT-WORK @ 0= _RB-a
    _RB-work-i0 _RCW.ACTIVE @ 0= _RB-a
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ Build a generation-2 bank-zero fallback with four completely enumerated
\ application pages, then publish a three-page generation-3 authority in bank
\ one.  Numeric page one crosses from old APP to current META, which is legal
\ only because the independent-bank map is cleared.  The three-byte current
\ size remains insufficient; the exact four-byte maximum audits both slots.
: _RB-audit-cross-bank-max  ( -- )
    S" /rba-i2-bank1-pages" _PSTC-vfs @ 0 0
        _RB-audit-bank1-page PPAGE-FILE-INIT PERSIST-S-OK _RB-s
    S" /rba-i2-bank1-segment" 256 _PSTC-vfs @ 0
        _RB-audit-bank1-segment PSEG-FILE-INIT PERSIST-S-OK _RB-s
    _RB-audit-page-work PPAGE-WORK-INIT PERSIST-S-OK _RB-s
    _RB-audit-segment-buffer 512 _RB-audit-segment-work PSEG-WORK-INIT
        PERSIST-S-OK _RB-s
    _RB-audit-bank1-page _RB-audit-page-work PPAGE-ENSURE
        PERSIST-S-OK _RB-s

    \ Rebind the already durable i2 bank-zero authority with bank one
    \ configured before growing its fallback snapshot.
    _PSTC-store-i2-init PERSIST-S-OK _RB-s
    _RB-audit-bank1-page _RB-audit-bank1-segment _PSTC-store-i2
        PSTORE-BANK1-CONFIGURE PERSIST-S-OK _RB-s
    _PSTC-buffer-i2 512 _PSTC-work-i2 PSTORE-WORK-INIT PERSIST-S-OK _RB-s
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-OPEN-ACTIVE PERSIST-S-OK _RB-s

    _PSTC-store-i2 _PSTC-work-i2 PSTORE-BEGIN PERSIST-S-OK _RB-s
    3 0 ?DO
        _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE I 31 + FILL
        _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE
            _PSTC-store-i2 _PSTC-work-i2 PSTORE-APPEND-PAGE
        PERSIST-S-OK = SWAP I 1+ = AND _RB-a
    LOOP
    _RB-audit-root-list3
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0
        _PSTC-store-i2 _PSTC-work-i2 PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    0 _PSTC-store-i2 _PSTC-work-i2 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-COMMIT PERSIST-S-OK _RB-s
    _PSTC-store-i2 PSTORE-GENERATION@ 2 = _RB-a
    _PSTC-store-i2 PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 4 = _RB-a

    _RB-audit-empty-root
    1 _PSTC-page _RCS.IN-HEAD !
    1 _PSTC-page _RCS.RETIRED-COUNT !
    _PSTC-page _RB-state RECLAIM-STATE-SIZE MOVE
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0 0
        _RB-audit-bank1-page _RB-audit-page-work PPAGE-WRITE-AT
        PERSIST-S-OK _RB-s
    3 2 _RB-audit-pending-bucket
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 1 1
        _RB-audit-bank1-page _RB-audit-page-work PPAGE-WRITE-AT
        PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 81 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 2 2
        _RB-audit-bank1-page _RB-audit-page-work PPAGE-WRITE-AT
        PERSIST-S-OK _RB-s
    _RB-audit-bank1-segment _RB-audit-segment-work PSEG-ENSURE
        PERSIST-S-OK _RB-s
    _RB-audit-bank1-page PPAGE-SYNC PERSIST-S-OK _RB-s
    _RB-audit-bank1-segment PSEG-SYNC PERSIST-S-OK _RB-s

    _PSTC-store-i2 PSTORE-CURRENT-ROOT@
        _RB-audit-root-value PERSIST-ROOT-VALUE-COPY
    3 _RB-audit-root-value PROOTV.PAGE-COUNT !
    0 _RB-audit-root-value PROOTV.APPLICATION-ROOT !
    0 _RB-audit-root-value PROOTV.SEGMENT-TAIL !
    PERSIST-DATA-BANK-1 _RB-audit-root-value PROOTV.DATA-BANK !
    _RB-audit-root-value _PSTC-store-i2 PSTORE-ROOT-FILE@
        _PSTC-work-i2 _PSW.ROOT-WORK PROOT-PUBLISH PERSIST-S-OK _RB-s
    _PSTC-work-i2 _PSW.ROOT-WORK PROOT-GENERATION@ 3 = _RB-a

    \ Cold-open the directly published opposite-bank authority so PSTORE's
    \ in-memory current root and guard-bound slot observations agree exactly.
    _PSTC-store-i2-init PERSIST-S-OK _RB-s
    _RB-audit-bank1-page _RB-audit-bank1-segment _PSTC-store-i2
        PSTORE-BANK1-CONFIGURE PERSIST-S-OK _RB-s
    _PSTC-buffer-i2 512 _PSTC-work-i2 PSTORE-WORK-INIT PERSIST-S-OK _RB-s
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-OPEN-ACTIVE PERSIST-S-OK _RB-s
    _PSTC-store-i2 PSTORE-GENERATION@ 3 = _RB-a
    _PSTC-store-i2 PSTORE-CURRENT-ROOT@ PROOTV.DATA-BANK @
        PERSIST-DATA-BANK-1 = _RB-a
    _PSTC-store-i2 PSTORE-CURRENT-ROOT@ PROOTV.PAGE-COUNT @ 3 = _RB-a
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i2 _RB-reclaim-i2
        RECLAIM-OPEN PERSIST-S-OK _RB-s

    _PSTC-store-i2 _PSTC-work-i2 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i2 _RB-audit-store !
    _PSTC-work-i2 _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    3 _RB-audit-call-i2 PERSIST-S-CAPACITY _RB-s
    _RB-audit-calls @ 0= _RB-a
    4 _RB-audit-call-i2 PERSIST-S-OK _RB-s
    _RB-audit-calls @ 2 = _RB-a
    _PSTC-store-i2 _PSTC-work-i2 PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ Make an opaque old application page become current reclaim metadata without
\ damaging the old root that enumerates it.  Page zero's transition into a
\ newer PENDING population is legal; page one's APP -> META role crossing is
\ the isolated corruption.
: _RB-audit-role-cross  ( -- )
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 73 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE
        _PSTC-store-i3 _PSTC-work-i3 PSTORE-APPEND-PAGE
    PERSIST-S-OK = SWAP 1 = AND _RB-a
    1 _RB-audit-root-list1
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 0
        _PSTC-store-i3 _PSTC-work-i3 PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    0 _PSTC-store-i3 _PSTC-work-i3 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-COMMIT PERSIST-S-OK _RB-s

    _PSTC-store-i3 _PSTC-work-i3 PSTORE-BEGIN PERSIST-S-OK _RB-s
    3 0 _RB-audit-pending-bucket
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 1
        _PSTC-store-i3 _PSTC-work-i3 PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    _RB-audit-empty-root
    1 _PSTC-page _RCS.IN-HEAD !
    1 _PSTC-page _RCS.RETIRED-COUNT !
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE
        _PSTC-store-i3 _PSTC-work-i3 PSTORE-APPEND-PAGE
    PERSIST-S-OK = SWAP 2 = AND _RB-a
    2 _PSTC-store-i3 _PSTC-work-i3 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-COMMIT PERSIST-S-OK _RB-s
    _PSTC-store-i3 PSTORE-GENERATION@ 3 = _RB-a

    _PSTC-page RECLAIM-STATE-SIZE _PSTC-store-i3 _RB-reclaim-i3
        RECLAIM-OPEN PERSIST-S-OK _RB-s
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i3 _RB-audit-store !
    _PSTC-work-i3 _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    3 _RB-audit-call-i3 PERSIST-S-CORRUPT _RB-s
    _RB-audit-calls @ 2 = _RB-a
    _PSTC-store-i3 _PSTC-work-i3 PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ The reclaim descriptor can also be placed in PSTORE page scratch without
\ invalidating either object.  The untouched preflight must reject that exact
\ overlap before snapshot reads can overwrite reclaim state or its latch.
: _RB-audit-pstore-overlap-arguments  ( -- )
    _RB-audit-alias-pstore-buffer 512 _RB-audit-alias-pstore-work
        PSTORE-WORK-INIT PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    _RB-audit-alias-reclaim RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i1
        _RB-audit-alias-reclaim RECLAIM-OPEN PERSIST-S-OK _RB-s
    \ Open while i1 still has its ordinary authority workspace, then rebind
    \ the store to the already initialized alias workspace.  The reclaim
    \ descriptor remains valid inside otherwise-unused page-record scratch,
    \ allowing the audit preflight itself to prove the exact overlap.
    _PSTC-store-i1 _RB-audit-alias-pstore-work
        PSTORE-OPEN-ACTIVE PERSIST-S-OK _RB-s
    _PSTC-store-i1 _RB-audit-alias-pstore-work
        PSTORE-BEGIN PERSIST-S-OK _RB-s
    _RB-audit-alias-pstore-work PSTORE-WORK-VALID? _RB-a
    _RB-audit-alias-reclaim RECLAIM-VALID? _RB-a
    _RB-audit-alias-reclaim RECLAIM-SIZE
        _RB-audit-alias-pstore-work
        PSTORE-WORK-SPAN-DISJOINT? 0= _RB-a
    _PSTC-store-i1 _RB-audit-alias-pstore-work PSTORE-TX-READY? _RB-a

    _PSTC-store-i1 _RB-audit-store !
    _RB-audit-alias-pstore-work _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    _RB-audit-alias-pstore-work _RB-audit-alias-pstore-before
        PSTORE-WORK-SIZE MOVE
    _RB-audit-work _RB-audit-alias-audit-before
        RECLAIM-AUDIT-WORK-SIZE MOVE
    _RB-audit-alias-reclaim _RB-audit-alias-reclaim-before
        RECLAIM-SIZE MOVE
    _RB-audit-map 1 ['] _RB-audit-enumerator 0
        _RB-audit-alias-reclaim _PSTC-store-i1
        _RB-audit-alias-pstore-work _RB-audit-work
        RECLAIM-AUDIT-CURRENT PERSIST-S-INVALID _RB-s
    _RB-audit-calls @ 0= _RB-a
    _RB-audit-alias-pstore-work PSTORE-WORK-SIZE
        _RB-audit-alias-pstore-before PSTORE-WORK-SIZE
        COMPARE 0= _RB-a
    _RB-audit-work RECLAIM-AUDIT-WORK-SIZE
        _RB-audit-alias-audit-before RECLAIM-AUDIT-WORK-SIZE
        COMPARE 0= _RB-a
    _RB-audit-alias-reclaim RECLAIM-SIZE
        _RB-audit-alias-reclaim-before RECLAIM-SIZE
        COMPARE 0= _RB-a
    _RB-audit-alias-pstore-work PSTORE-WORK-VALID? _RB-a
    _RB-audit-alias-reclaim RECLAIM-VALID? _RB-a
    _PSTC-store-i1 _RB-audit-alias-pstore-work PSTORE-TX-READY? _RB-a
    _PSTC-store-i1 _RB-audit-alias-pstore-work
        PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ Exercise the two neutral application-ownership extensions without relying on
\ a Library root.  One pass uniquely submits and then shares a separate
\ application page.  A second pass admits that page only through an exact arena
\ interval, while the existing i0 reclaim metadata page proves that the same
\ interval cannot hide a neutral ownership collision.
: _RB-audit-application-extensions  ( -- )
    \ The preceding overlap case deliberately rebound i1 to its alias
    \ workspace.  Restore the ordinary disjoint workspace before mutating the
    \ same neutral authority.
    _PSTC-store-i1 _PSTC-work-i1
        PSTORE-OPEN-ACTIVE PERSIST-S-OK _RB-s
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE 91 FILL
    _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE
        _PSTC-store-i1 _PSTC-work-i1 PSTORE-APPEND-PAGE
    PERSIST-S-OK = SWAP 1 = AND _RB-a
    0 _PSTC-store-i1 _PSTC-work-i1 PSTORE-APPLICATION-ROOT!
        PERSIST-S-OK _RB-s
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-COMMIT PERSIST-S-OK _RB-s
    0 _PSTC-store-i1 _PSTC-work-i1 PSTORE-READ-PAGE PERSIST-S-OK _RB-s
    _PSTC-work-i1 PSTORE-PAGE-PAYLOAD$
    DUP PERSIST-PAGE-PAYLOAD-SIZE = _RB-a
    DROP _RB-state RECLAIM-STATE-SIZE MOVE
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-i1 _RB-reclaim-i1
        RECLAIM-OPEN PERSIST-S-OK _RB-s

    _PSTC-store-i1 _PSTC-work-i1 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i1 _RB-audit-store !
    _PSTC-work-i1 _RB-audit-pstore-work !
    9 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    2 _RB-audit-call-i1 PERSIST-S-OK _RB-s
    _RB-audit-calls @ 2 = _RB-a
    _RB-audit-map 1+ C@ _RCA-M-CURRENT-APP = _RB-a
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-ABORT PERSIST-S-OK _RB-s

    _PSTC-store-i1 _PSTC-work-i1 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i1 _RB-audit-store !
    _PSTC-work-i1 _RB-audit-pstore-work !
    10 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    2 _RB-audit-call-i1 PERSIST-S-OK _RB-s
    _RB-audit-calls @ 2 = _RB-a
    _RB-audit-map 1+ C@ _RCA-M-CURRENT-APP = _RB-a
    _PSTC-store-i1 _PSTC-work-i1 PSTORE-ABORT PERSIST-S-OK _RB-s

    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _RB-audit-store !
    _PSTC-work-i0 _RB-audit-pstore-work !
    11 _RB-audit-callback-mode !
    0 _RB-audit-calls !
    3 _RB-audit-call-i0 PERSIST-S-CORRUPT _RB-s
    _RB-audit-calls @ 2 = _RB-a
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 0= _RB-a
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s
    0 _RB-audit-callback-mode ! ;

: _RB-audit-page-save  ( page-id -- )
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-READ-PAGE PERSIST-S-OK _RB-s
    _PSTC-work-i0 PSTORE-PAGE-PAYLOAD$
    DUP PERSIST-PAGE-PAYLOAD-SIZE = _RB-a
    DROP _RB-audit-page-before PERSIST-PAGE-PAYLOAD-SIZE MOVE ;

: _RB-audit-page-overwrite  ( payload page-id -- )
    >R
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    PERSIST-PAGE-PAYLOAD-SIZE R>
        _PSTC-store-i0 _PSTC-work-i0 PSTORE-WRITE-PAGE-TX
        PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s ;

: _RB-audit-expect  ( expected-status -- )
    >R
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _RB-audit-store !
    _PSTC-work-i0 _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 R> _RB-s
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s ;

\ Rewrite one committed checked payload at a time under the RAM-VFS proving
\ store, observe cold-audit refusal, then restore the exact saved bytes.  This
\ isolates semantic graph damage while leaving the root snapshots unchanged.
: _RB-cold-authority-corruption  ( -- )
    2 _RB-audit-page-save
    _RB-audit-page-before _RB-audit-bucket-before
        PERSIST-PAGE-PAYLOAD-SIZE MOVE

    \ A self-link is a metadata cycle even though the local bucket envelope is
    \ otherwise valid.
    _RB-audit-bucket-before _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE MOVE
    2 _PSTC-page _RCB.NEXT !
    _PSTC-page 2 _RB-audit-page-overwrite
    PERSIST-S-CORRUPT _RB-audit-expect
    _RB-audit-bucket-before 2 _RB-audit-page-overwrite

    \ Pending retirement generations may not be newer than their root slot.
    _RB-audit-bucket-before _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE MOVE
    3 _PSTC-page _RCB.GENERATION !
    _PSTC-page 2 _RB-audit-page-overwrite
    PERSIST-S-CORRUPT _RB-audit-expect
    _RB-audit-bucket-before 2 _RB-audit-page-overwrite

    \ Generation one is locally valid in the generation-two snapshot, but it
    \ cannot retire an application page still live in the generation-one
    \ fallback.  The healthy generation-two bucket above proves the strict
    \ greater-than case.
    _RB-audit-bucket-before _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE MOVE
    1 _PSTC-page _RCB.GENERATION !
    _PSTC-page 2 _RB-audit-page-overwrite
    PERSIST-S-CORRUPT _RB-audit-expect
    _RB-audit-bucket-before 2 _RB-audit-page-overwrite

    \ One page cannot be both bucket metadata and an active population id.
    _RB-audit-bucket-before _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE MOVE
    2 0 _PSTC-page _RCB.ENTRY !
    _PSTC-page 2 _RB-audit-page-overwrite
    PERSIST-S-CORRUPT _RB-audit-expect
    _RB-audit-bucket-before 2 _RB-audit-page-overwrite

    \ READY is never a safe destination for a page that remains live in the
    \ fallback slot, even when the current state and bucket are otherwise
    \ internally complete.
    1 _RB-audit-page-save
    _RB-audit-page-before _RB-audit-root-before
        PERSIST-PAGE-PAYLOAD-SIZE MOVE
    _RB-audit-root-before _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE MOVE
    -1 _PSTC-page _RCS.IN-HEAD !
    2 _PSTC-page _RCS.READY-HEAD !
    0 _PSTC-page _RCS.RETIRED-COUNT !
    1 _PSTC-page _RCS.REUSABLE-COUNT !
    _PSTC-page 1 _RB-audit-page-overwrite
    _RB-audit-bucket-before _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE MOVE
    _RECLAIM-BUCKET-READY _PSTC-page _RCB.KIND !
    0 _PSTC-page _RCB.GENERATION !
    _PSTC-page 2 _RB-audit-page-overwrite
    PERSIST-S-CORRUPT _RB-audit-expect
    _RB-audit-root-before 1 _RB-audit-page-overwrite
    _RB-audit-bucket-before 2 _RB-audit-page-overwrite

    \ A different valid current header cannot authorize the descriptor opened
    \ from the real current root.
    _RB-audit-root-before _PSTC-page PERSIST-PAGE-PAYLOAD-SIZE MOVE
    _PSTC-page RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    _PSTC-page 1 _RB-audit-page-overwrite
    PERSIST-S-CORRUPT _RB-audit-expect

    \ Match the test-only live descriptor to that empty header to isolate the
    \ subsequent whole-bank classification: pages zero and two remain
    \ unexplained committed orphans even though the header itself is valid.
    _PSTC-page _RB-reclaim-i0 _RCL.STATE
        RECLAIM-STATE-SIZE MOVE
    PERSIST-S-CORRUPT _RB-audit-expect
    _RB-audit-root-before _RB-reclaim-i0 _RCL.STATE
        RECLAIM-STATE-SIZE MOVE
    _RB-audit-root-before 1 _RB-audit-page-overwrite ;

: _RB-cold-authority-audit  ( -- )
    0 RECLAIM-AUDIT-MAP-BYTES?
        PERSIST-S-OK = SWAP 0= AND _RB-a
    -1 RECLAIM-AUDIT-MAP-BYTES?
        PERSIST-S-INVALID = SWAP 0= AND _RB-a
    _RB-audit-build-in
    _RB-reclaim-i0 _RCL.STATE _RB-state RECLAIM-STATE-SIZE MOVE
    _RB-state RECLAIM-STATE-SIZE
        _PSTC-store-i0 _RB-reclaim-i0 RECLAIM-OPEN PERSIST-S-OK _RB-s
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 0= _RB-a
    _RB-audit-overlap-arguments

    \ A nonempty reopened state cannot begin before the complete read-only
    \ audit, and refusal does not poison the clean PSTORE proposal.
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 _RB-reclaim-i0 _RB-work-i0
        RECLAIM-TX-BEGIN PERSIST-S-CONFLICT _RB-s
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-TX-READY? _RB-a
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s

    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _RB-audit-store !
    _PSTC-work-i0 _RB-audit-pstore-work !
    0 _RB-audit-callback-mode !
    2 _RB-audit-call-i0 PERSIST-S-CAPACITY _RB-s
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 0= _RB-a
    1 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-FAULT _RB-s
    2 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-FAULT _RB-s
    3 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-FAULT _RB-s
    4 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-CONFLICT _RB-s
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 0= _RB-a
    0 _RB-audit-callback-mode !
    3 _RB-audit-call-i0 PERSIST-S-OK _RB-s
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 2 = _RB-a
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 2 = _RB-a
    _RB-audit-reentry
    _RB-cold-authority-corruption
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 0= _RB-a
    PERSIST-S-OK _RB-audit-expect
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 2 = _RB-a

    \ A normal transaction abort preserves evidence for the still-current
    \ generation and never advances it.
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 _RB-reclaim-i0 _RB-work-i0
        RECLAIM-TX-BEGIN PERSIST-S-OK _RB-s
    _PSTC-store-i0 _PSTC-work-i0 PSTORE-ABORT PERSIST-S-OK _RB-s
    _RB-work-i0 RECLAIM-ABORT PERSIST-S-OK _RB-s
    _RB-reclaim-i0 RECLAIM-AUDITED-GENERATION@ 2 = _RB-a
    _RB-audit-mirrored-once
    _RB-audit-cross-bank-max
    _RB-audit-role-cross
    _RB-audit-healthy-partial-out
    _RB-audit-healthy-mid-rotation
    _RB-audit-healthy-chained-ready
    _RB-audit-pstore-overlap-arguments
    _RB-audit-application-extensions
    _RB-stack ;

: _PRC-RUN  ( -- )
    0 _RB-fails ! 0 _RB-checks ! DEPTH _RB-depth !
    _PSTC-setup
    _PSTC-first-commit
    _RB-grow-base
    _RB-state RECLAIM-STATE-SIZE RECLAIM-STATE-INIT PERSIST-S-OK _RB-s
    _RB-reclaim RECLAIM-INIT PERSIST-S-OK _RB-s
    _RB-state RECLAIM-STATE-SIZE _PSTC-store-a _RB-reclaim RECLAIM-OPEN
        PERSIST-S-OK _RB-s
    _RB-work RECLAIM-WORK-INIT PERSIST-S-OK _RB-s
    _RB-audit-work RECLAIM-AUDIT-WORK-INIT PERSIST-S-OK _RB-s
    _RB-audit-work-2 RECLAIM-AUDIT-WORK-INIT PERSIST-S-OK _RB-s
    ['] _RB-audit-enumerator _RB-audit-enumerator-xt !
    _RB-room-contract
    _RB-high-water-claim-contract
    _RB-ready-state-biconditional
    _RB-begin-ownership
    _RB-prebegin-append
    _RB-unwritten-consecutive
    _RB-unwritten-finalize
    _RB-retire-61
    _RB-unwritten-step
    _RB-rotate-2
    _RB-promote-reuse-61
    _RB-retire-cap
    _RB-call-bounds
    _RB-invalid-ledgers
    _RB-layer-failure-poisons
    _RB-discard-33
    _RB-cold-discard
    _RB-protected-allocation-contract
    _RB-finalize-page-faults
    _RB-step-page-faults
    _RB-staged-metadata-boundary
    _RB-repeat-churn
    _RB-discard-abort
    _RB-discard-cap
    _RB-allocate-cap
    _RB-post-durable
    _RB-ready-backed-rotation-cold
    _RB-small-batch-cadence
    _RB-four-store
    _RB-cold-authority-audit
    _RB-stack
    _PSTC-old-vfs @ VFS-USE
    _PSTC-vfs @ VFS-DESTROY
    _RB-fails @ 0= IF
        ." PERSISTENCE RECLAIM PASS " _RB-checks @ . CR
    ELSE
        ." PERSISTENCE RECLAIM FAIL " _RB-fails @ . ." /" _RB-checks @ . CR
    THEN ;
