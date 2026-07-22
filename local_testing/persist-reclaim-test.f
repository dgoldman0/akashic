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
VARIABLE _RB-snapshot-page
VARIABLE _RB-reserved
VARIABLE _RB-cadence-live-a
VARIABLE _RB-cadence-live-b
VARIABLE _RB-cadence-new-a
VARIABLE _RB-cadence-new-b
VARIABLE _RB-cadence-warm-pages
VARIABLE _RB-cadence-warm-retired
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

: _RB-a  ( flag -- )
    1 _RB-checks +!
    0= IF
        1 _RB-fails +! ." PERSISTENCE RECLAIM ASSERT " _RB-checks @ . CR
    THEN ;

: _RB-s  ( actual expected -- )
    2DUP <> IF
        ." PERSISTENCE RECLAIM STATUS actual/expected " 2DUP . . CR
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
    _RB-stack
    _PSTC-old-vfs @ VFS-USE
    _PSTC-vfs @ VFS-DESTROY
    _RB-fails @ 0= IF
        ." PERSISTENCE RECLAIM PASS " _RB-checks @ . CR
    ELSE
        ." PERSISTENCE RECLAIM FAIL " _RB-fails @ . ." /" _RB-checks @ . CR
    THEN ;
