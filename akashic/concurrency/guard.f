\ guard.f — Recursive Cross-Core Guards for KDOS / Megapad-64
\
\ A guard is a named mutual-exclusion wrapper for shared state.  Guard
\ ownership is the pair (hardware core, execution context).  Core-0
\ foreground uses its KDOS task descriptor; BIOS background slots use a
\ negative TASK-ID token.  BIOS worker cores use zero, with COREID keeping
\ zero-context workers distinct.
\
\ Guards are recursive for the same execution owner.  This is required by
\ Akashic's public wrapper pattern, where a guarded public word may call
\ another guarded public word protected by the same guard.
\
\ Metadata transitions are serialized by EVT-LOCK.  That hardware lock is
\ held only for the few aligned loads/stores that claim, recurse, or release
\ a guard.  It is never held across a semaphore/event operation, YIELD?, the
\ protected body, CATCH, or THROW.
\
\ Two flavors:
\   GUARD          — spinning guard (retry + YIELD?)
\   GUARD-BLOCKING — semaphore-backed guard for longer waits
\
\ Data structure — spinning guard (4 cells = 32 bytes):
\   +0   depth       0 = free, positive = recursive hold depth
\   +8   owner-core  hardware core ID of holder
\   +16  owner-task  core-0 task/context token, or 0 on workers
\   +24  mode        0 = spin, 1 = blocking
\
\ Data structure — blocking guard (4 cells + semaphore = 72 bytes):
\   +0..+24          fields above
\   +32              embedded 1-count semaphore (5 cells = 40 bytes)
\
\ Dependencies: semaphore.f (and event.f transitively)
\
\ Prefix: GUARD-  (public API)
\         _GRD-   (internal helpers)
\
\ Load with:   REQUIRE guard.f

REQUIRE ../concurrency/semaphore.f

PROVIDED akashic-guard

\ =====================================================================
\  Constants
\ =====================================================================

4 CONSTANT _GRD-CELLS-SPIN
9 CONSTANT _GRD-CELLS-BLOCK
32 CONSTANT _GRD-SIZE-SPIN
72 CONSTANT _GRD-SIZE-BLOCK

\ Object geometry is public for callers that supply guard storage instead of
\ defining it lexically.  Flavor inspection remains separate from ownership
\ and acquisition; it is only a shape check for initialized storage.
_GRD-SIZE-SPIN CONSTANT GUARD-SPIN-SIZE
_GRD-SIZE-BLOCK CONSTANT GUARD-BLOCKING-SIZE

\ Guard metadata shares event.f's hardware synchronization lock.  Guard
\ code never calls an event/semaphore/yield word while this lock is held.
EVT-LOCK CONSTANT _GRD-META-LOCK

-257 CONSTANT GUARD-E-NOT-OWNER

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _GRD-DEPTH       ( guard -- addr )   ;          \ +0
: _GRD-OWNER-CORE  ( guard -- addr )   8 + ;      \ +8
: _GRD-OWNER-TASK  ( guard -- addr )   16 + ;     \ +16
: _GRD-MODE        ( guard -- addr )   24 + ;     \ +24
: _GRD-SEM         ( guard -- sem )    32 + ;     \ +32

\ Compatibility aliases for code which inspected the old internal layout.
: _GRD-FLAG   ( guard -- addr )   _GRD-DEPTH ;
: _GRD-OWNER  ( guard -- addr )   _GRD-OWNER-TASK ;

\ =====================================================================
\  Defining Words
\ =====================================================================

\ GUARD ( "name" -- )
\   Create an initially free spinning guard.

: GUARD  ( "name" -- )
    CREATE
        0 ,          \ depth = free
        0 ,          \ owner core
        0 ,          \ owner task
        0 ,          \ mode = spin
    DOES> ;

\ GUARD-BLOCKING ( "name" -- )
\   Create an initially free semaphore-backed guard.  Recursive entry does
\   not consume another semaphore permit.

: GUARD-BLOCKING  ( "name" -- )
    CREATE
        0 ,          \ depth = free
        0 ,          \ owner core
        0 ,          \ owner task
        1 ,          \ mode = blocking
        \ Inline a 1-count semaphore (5 cells = 40 bytes)
        1 ,          \ sem +0: count = 1
        0 ,          \ sem +8: event flag = 0
        0 ,          \ sem +16: event wait-count = 0
        0 ,          \ sem +24: event waiter-0 = 0
        0 ,          \ sem +32: event waiter-1 = 0
    DOES> ;

\ =====================================================================
\  Owner Identity and Atomic Metadata Helpers
\ =====================================================================

\ CURRENT-TASK is a core-0 scheduler variable, not per-core TLS.  TASK-ID
\ distinguishes its foreground (0) from the three BIOS background coroutine
\ slots.  Negative slot tokens cannot alias aligned KDOS task descriptors.
\ A BIOS worker never reads core-0 task state; one dispatched execution per
\ worker makes (COREID, 0) unambiguous.

: _GRD-CURRENT-TASK  ( -- task )
    COREID 0= IF
        TASK-ID ?DUP IF NEGATE ELSE CURRENT-TASK @ THEN
    ELSE
        0
    THEN ;

\ _GRD-MINE-LOCKED? ( guard -- flag )
\   Caller holds _GRD-META-LOCK.

: _GRD-MINE-LOCKED?  ( guard -- flag )
    DUP _GRD-DEPTH @ 0= IF  DROP 0 EXIT  THEN
    DUP _GRD-OWNER-CORE @ COREID <> IF  DROP 0 EXIT  THEN
    _GRD-OWNER-TASK @ _GRD-CURRENT-TASK = ;

\ _GRD-CLAIM-LOCKED ( guard -- )
\   Publish owner fields before making the positive depth visible.  Caller
\   holds _GRD-META-LOCK and has already established that depth is zero.

: _GRD-CLAIM-LOCKED  ( guard -- )
    COREID OVER _GRD-OWNER-CORE !
    _GRD-CURRENT-TASK OVER _GRD-OWNER-TASK !
    1 SWAP _GRD-DEPTH ! ;

\ _GRD-TRY-META ( guard -- flag )
\   Atomically claim a free guard or recurse for the same owner.

: _GRD-TRY-META  ( guard -- flag )
    _GRD-META-LOCK LOCK
    DUP _GRD-DEPTH @ 0= IF
        DUP _GRD-CLAIM-LOCKED
        _GRD-META-LOCK UNLOCK
        DROP -1 EXIT
    THEN
    DUP _GRD-MINE-LOCKED? IF
        1 OVER _GRD-DEPTH +!
        _GRD-META-LOCK UNLOCK
        DROP -1 EXIT
    THEN
    _GRD-META-LOCK UNLOCK
    DROP 0 ;

\ _GRD-TRY-REENTER ( guard -- flag )
\   Atomically recurse only; never claims a free guard.  Blocking guards use
\   this before touching their semaphore permit.

: _GRD-TRY-REENTER  ( guard -- flag )
    _GRD-META-LOCK LOCK
    DUP _GRD-MINE-LOCKED? IF
        1 OVER _GRD-DEPTH +!
        _GRD-META-LOCK UNLOCK
        DROP -1 EXIT
    THEN
    _GRD-META-LOCK UNLOCK
    DROP 0 ;

\ _GRD-TRY-CLAIM ( guard -- flag )
\   Atomically claim only if free; never recurses.  For blocking guards the
\   caller must already own the embedded semaphore permit.

: _GRD-TRY-CLAIM  ( guard -- flag )
    _GRD-META-LOCK LOCK
    DUP _GRD-DEPTH @ 0= IF
        DUP _GRD-CLAIM-LOCKED
        _GRD-META-LOCK UNLOCK
        DROP -1 EXIT
    THEN
    _GRD-META-LOCK UNLOCK
    DROP 0 ;

\ =====================================================================
\  Acquisition
\ =====================================================================

\ GUARD-TRY-ACQUIRE ( guard -- flag )
\   Attempt one acquisition without waiting.  A recursive acquisition by
\   the same owner succeeds and increments depth.

: GUARD-TRY-ACQUIRE  ( guard -- flag )
    DUP _GRD-MODE @ IF
        \ Recursive entry must not consume a second semaphore permit.
        DUP _GRD-TRY-REENTER IF  DROP -1 EXIT  THEN
        \ The semaphore and metadata each use EVT-LOCK, but in disjoint
        \ calls: neither lock hold spans the other operation.
        DUP _GRD-SEM SEM-TRYWAIT 0= IF  DROP 0 EXIT  THEN
        DUP _GRD-TRY-CLAIM IF  DROP -1 EXIT  THEN
        \ Defensive rollback if metadata and permit ever disagree.
        DUP _GRD-SEM SEM-SIGNAL
        DROP 0 EXIT
    THEN
    _GRD-TRY-META ;

\ _GRD-ACQUIRE-BLOCKING ( guard -- )
\   Wait for the binary permit, then atomically publish ownership.

: _GRD-ACQUIRE-BLOCKING  ( guard -- )
    DUP GUARD-TRY-ACQUIRE IF  DROP EXIT  THEN
    BEGIN
        \ SEM-WAIT relies on a transient EVT-PULSE.  A bounded semaphore
        \ retry also yields cooperatively, but rechecks the count after each
        \ yield and therefore cannot miss its only wakeup.
        DUP _GRD-SEM 1 SEM-WAIT-TIMEOUT IF
            DUP _GRD-TRY-CLAIM IF  DROP EXIT  THEN
            \ A claim failure is not expected, but never leak the permit.
            DUP _GRD-SEM SEM-SIGNAL
        THEN
    AGAIN ;

\ GUARD-ACQUIRE ( guard -- )
\   Wait until acquired.  Same-owner entry is recursive.

: GUARD-ACQUIRE  ( guard -- )
    DUP _GRD-MODE @ IF  _GRD-ACQUIRE-BLOCKING EXIT  THEN
    BEGIN
        DUP GUARD-TRY-ACQUIRE 0=
    WHILE
        YIELD?
    REPEAT
    DROP ;

\ GUARD-ACQUIRE-TIMEOUT ( guard ms -- flag )
\   Attempt acquisition for at most ms milliseconds.  The first try is
\   immediate, so a zero timeout can still acquire a free guard.  Timeout
\   polling never holds _GRD-META-LOCK across YIELD?.

: GUARD-ACQUIRE-TIMEOUT  ( guard ms -- flag )
    DUP 0< IF  DROP 0  THEN
    EPOCH@ + >R
    BEGIN
        DUP GUARD-TRY-ACQUIRE IF
            R> DROP DROP -1 EXIT
        THEN
        EPOCH@ R@ >= IF
            R> DROP DROP 0 EXIT
        THEN
        YIELD?
    AGAIN ;

\ =====================================================================
\  Release
\ =====================================================================

\ GUARD-RELEASE ( guard -- )
\   Decrement recursive depth, or fully release at depth one.  Releasing a
\   free guard or another execution owner's guard throws
\   GUARD-E-NOT-OWNER.  A blocking guard's semaphore is signaled only after
\   the metadata lock has been released.

: GUARD-RELEASE  ( guard -- )
    _GRD-META-LOCK LOCK
    DUP _GRD-MINE-LOCKED? 0= IF
        _GRD-META-LOCK UNLOCK
        DROP GUARD-E-NOT-OWNER THROW
    THEN
    DUP _GRD-DEPTH @ 1 > IF
        -1 OVER _GRD-DEPTH +!
        _GRD-META-LOCK UNLOCK
        DROP EXIT
    THEN
    \ Clear owner first and publish free depth last.
    0 OVER _GRD-OWNER-TASK !
    0 OVER _GRD-OWNER-CORE !
    0 OVER _GRD-DEPTH !
    DUP _GRD-MODE @ >R
    _GRD-META-LOCK UNLOCK
    R> IF  _GRD-SEM SEM-SIGNAL  ELSE  DROP  THEN ;

\ =====================================================================
\  Scoped Execution
\ =====================================================================

\ WITH-GUARD ( xt guard -- )
\   Acquire guard, execute xt, and release on both normal and exceptional
\   exits.  Body results below CATCH's status cell are preserved.

: WITH-GUARD  ( xt guard -- )
    DUP >R GUARD-ACQUIRE
    CATCH
    R> GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;

\ =====================================================================
\  Queries and Debugging
\ =====================================================================

\ GUARD-HELD? is a lock-free aligned snapshot.  It is suitable for status
\ display, not for making an acquisition decision.

: GUARD-HELD?  ( guard -- flag )
    _GRD-DEPTH @ 0<> ;

: GUARD-SPIN?  ( guard -- flag )
    _GRD-MODE @ 0= ;

: GUARD-BLOCKING?  ( guard -- flag )
    _GRD-MODE @ 1 = ;

: GUARD-MINE?  ( guard -- flag )
    _GRD-META-LOCK LOCK
    DUP _GRD-MINE-LOCKED?
    _GRD-META-LOCK UNLOCK
    SWAP DROP ;

\ Take a coherent metadata snapshot, then print without holding EVT-LOCK.

: _GRD-SNAPSHOT  ( guard -- depth core task mode )
    _GRD-META-LOCK LOCK
    DUP _GRD-DEPTH @
    OVER _GRD-OWNER-CORE @
    2 PICK _GRD-OWNER-TASK @
    3 PICK _GRD-MODE @
    _GRD-META-LOCK UNLOCK
    4 ROLL DROP ;

: GUARD-INFO  ( guard -- )
    _GRD-SNAPSHOT
    ." [guard "
    IF  ." blocking"  ELSE  ." spin"  THEN
    ."  "
    2 PICK IF
        ." HELD core=" OVER .
        ." task=" DUP .
        ." depth=" 2 PICK .
    ELSE
        ." FREE"
    THEN
    ." ]" CR
    2DROP DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  GUARD                  ( "name" -- )       Create spinning guard
\  GUARD-BLOCKING         ( "name" -- )       Create blocking guard
\  GUARD-TRY-ACQUIRE      ( guard -- flag )   Acquire without waiting
\  GUARD-ACQUIRE          ( guard -- )        Acquire, waiting as needed
\  GUARD-ACQUIRE-TIMEOUT  ( guard ms -- flag) Bounded acquisition
\  GUARD-RELEASE          ( guard -- )        Release one recursion level
\  WITH-GUARD             ( xt guard -- )     Exception-safe scoped use
\  GUARD-HELD?            ( guard -- flag )   Lock-free status snapshot
\  GUARD-MINE?            ( guard -- flag )   Current owner?
\  GUARD-INFO             ( guard -- )        Debug display
