\ rwlock.f — Reader-Writer Locks for KDOS / Megapad-64
\
\ Multiple concurrent readers OR one exclusive writer.
\ Critical for shared lookup tables (font cache, route table,
\ hash tables) that are read-heavy.
\
\ READ-LOCK succeeds when no writer is active; multiple readers
\ can hold the lock simultaneously.  WRITE-LOCK succeeds only when
\ no readers AND no writer are active — it waits for both to drain.
\
\ Data structure — 11 cells = 88 bytes:
\   +0   lock#       per-rwlock spinlock number (hardware 0–7)
\   +8   readers     active reader count
\   +16  writer      -1 if write-locked, 0 otherwise
\   +24  read-event  embedded event (4 cells = 32 bytes)
\                      pulsed when writer unlocks → wakes readers
\   +56  write-event embedded event (4 cells = 32 bytes)
\                      pulsed when last reader or writer unlocks
\                      → wakes a blocked writer
\
\ The two events are embedded inline (same pattern as semaphore.f)
\ for zero-indirection access.  Each rwlock carries its own spinlock
\ number so unrelated rwlocks do not contend on the same hardware
\ spinlock during state transitions.
\
\ REQUIRE event.f
\
\ Prefix: RW-    (public API)
\         _RW-   (internal helpers)
\
\ Load with:   REQUIRE rwlock.f

REQUIRE ../concurrency/event.f

PROVIDED akashic-rwlock

\ =====================================================================
\  Constants
\ =====================================================================

11 CONSTANT _RW-CELLS              \ cells per rwlock descriptor
88 CONSTANT _RW-SIZE               \ bytes per rwlock (11 × 8)

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _RW-LOCK#   ( rwl -- addr )   ;          \ +0   spinlock number
: _RW-READERS ( rwl -- addr )   8 + ;      \ +8   active reader count
: _RW-WRITER  ( rwl -- addr )   16 + ;     \ +16  writer flag
: _RW-REVT    ( rwl -- ev )     24 + ;     \ +24  read-event  (32 B)
: _RW-WEVT    ( rwl -- ev )     56 + ;     \ +56  write-event (32 B)

\ =====================================================================
\  RWLOCK — Defining Word
\ =====================================================================

\ RWLOCK ( lock# "name" -- )
\   Create a named reader-writer lock that uses the given hardware
\   spinlock for its critical sections.
\
\   EVT-LOCK (6) is a reasonable default when no dedicated spinlock
\   is available.  Multiple rwlocks can share the same spinlock
\   number — correctness is preserved, only contention increases.
\
\   Example:   6 RWLOCK cache-rw       \ uses spinlock 6
\              cache-rw READ-LOCK
\              ... read shared data ...
\              cache-rw READ-UNLOCK

: RWLOCK  ( lock# "name" -- )
    HERE >R
    ,                \ +0   lock# = spinlock number
    0 ,              \ +8   readers = 0
    0 ,              \ +16  writer  = 0 (unlocked)
    \ Embedded read-event (4 cells, initially unset)
    0 ,              \ +24  flag = unset
    0 ,              \ +32  wait-count = 0
    0 ,              \ +40  waiter-0 = none
    0 ,              \ +48  waiter-1 = none
    \ Embedded write-event (4 cells, initially unset)
    0 ,              \ +56  flag = unset
    0 ,              \ +64  wait-count = 0
    0 ,              \ +72  waiter-0 = none
    0 ,              \ +80  waiter-1 = none
    R> CONSTANT ;

\ =====================================================================
\  Internal — Lock/Unlock Helpers
\ =====================================================================

\ _RW-SPIN-LOCK ( rwl -- )
\   Acquire this rwlock's hardware spinlock.

: _RW-SPIN-LOCK  ( rwl -- )
    @ LOCK ;

\ _RW-SPIN-UNLOCK ( rwl -- )
\   Release this rwlock's hardware spinlock.

: _RW-SPIN-UNLOCK  ( rwl -- )
    @ UNLOCK ;

\ =====================================================================
\  READ-LOCK — Acquire Shared Read Access
\ =====================================================================

\ READ-LOCK ( rwl -- )
\   Acquire the rwlock for reading.  Blocks while a writer is active.
\   Multiple readers can hold the lock simultaneously.
\
\   Protocol:
\     1. Lock spinlock
\     2. If no writer → readers++, unlock, done
\     3. If writer active → unlock, wait on read-event, retry

: READ-LOCK  ( rwl -- )
    BEGIN
        DUP _RW-SPIN-LOCK
        DUP _RW-WRITER @ 0= IF        \ no writer?
            1 OVER _RW-READERS +!      \ readers++
            DUP _RW-SPIN-UNLOCK
            DROP EXIT                  \ acquired
        THEN
        DUP _RW-SPIN-UNLOCK
        \ Writer is active — wait for read-event pulse
        DUP _RW-REVT EVT-WAIT
        DUP _RW-REVT EVT-RESET
    AGAIN ;

\ =====================================================================
\  READ-UNLOCK — Release Read Access
\ =====================================================================

\ READ-UNLOCK ( rwl -- )
\   Release the read lock.  If this was the last reader,
\   pulse write-event to wake a blocked writer (if any).

: READ-UNLOCK  ( rwl -- )
    DUP _RW-SPIN-LOCK
    -1 OVER _RW-READERS +!            \ readers--
    DUP _RW-READERS @ 0= IF           \ last reader?
        DUP _RW-SPIN-UNLOCK
        _RW-WEVT EVT-PULSE            \ wake writer
    ELSE
        DUP _RW-SPIN-UNLOCK
        DROP
    THEN ;

\ =====================================================================
\  WRITE-LOCK — Acquire Exclusive Write Access
\ =====================================================================

\ WRITE-LOCK ( rwl -- )
\   Acquire the rwlock for writing.  Blocks while any readers are
\   active OR another writer holds the lock.
\
\   Protocol:
\     1. Lock spinlock
\     2. If readers=0 AND writer=0 → set writer=-1, unlock, done
\     3. Otherwise → unlock, wait on write-event, retry

: WRITE-LOCK  ( rwl -- )
    BEGIN
        DUP _RW-SPIN-LOCK
        DUP _RW-READERS @ 0=          \ no readers?
        OVER _RW-WRITER  @ 0=         \ no writer?
        AND IF
            -1 OVER _RW-WRITER !       \ writer = locked
            DUP _RW-SPIN-UNLOCK
            DROP EXIT                  \ acquired
        THEN
        DUP _RW-SPIN-UNLOCK
        \ Readers or writer active — wait for write-event pulse
        DUP _RW-WEVT EVT-WAIT
        DUP _RW-WEVT EVT-RESET
    AGAIN ;

\ =====================================================================
\  WRITE-UNLOCK — Release Write Access
\ =====================================================================

\ WRITE-UNLOCK ( rwl -- )
\   Release the write lock.  Pulse read-event (wake waiting readers)
\   AND write-event (wake a waiting writer), so both reader and
\   writer waiters get a chance to proceed.

: WRITE-UNLOCK  ( rwl -- )
    DUP _RW-SPIN-LOCK
    0 OVER _RW-WRITER !               \ writer = unlocked
    DUP _RW-SPIN-UNLOCK
    DUP _RW-REVT EVT-PULSE            \ wake readers
        _RW-WEVT EVT-PULSE ;          \ wake writers

\ =====================================================================
\  Query
\ =====================================================================

\ RW-READERS ( rwl -- n )
\   Return the current active reader count.  Lock-free read.

: RW-READERS  ( rwl -- n )
    _RW-READERS @ ;

\ RW-WRITER? ( rwl -- flag )
\   Return TRUE if a writer currently holds the lock.  Lock-free read.

: RW-WRITER?  ( rwl -- flag )
    _RW-WRITER @ 0<> ;

\ =====================================================================
\  RAII Convenience
\ =====================================================================

\ WITH-READ ( xt rwl -- )
\   Acquire read lock, execute xt, release.
\   Ensures READ-UNLOCK is called even if xt ABORTs (via CATCH).
\
\   Example:   ['] show-cache cache-rw WITH-READ

: WITH-READ  ( xt rwl -- )
    DUP >R READ-LOCK
    CATCH
    R> READ-UNLOCK
    THROW ;

\ WITH-WRITE ( xt rwl -- )
\   Acquire write lock, execute xt, release.
\   Ensures WRITE-UNLOCK is called even if xt ABORTs (via CATCH).
\
\   Example:   ['] flush-cache cache-rw WITH-WRITE

: WITH-WRITE  ( xt rwl -- )
    DUP >R WRITE-LOCK
    CATCH
    R> WRITE-UNLOCK
    THROW ;

\ =====================================================================
\  RW-INFO — Debug Display
\ =====================================================================

\ RW-INFO ( rwl -- )
\   Print rwlock status for debugging.

: RW-INFO  ( rwl -- )
    ." [rwlock lock#=" DUP @ .
    ."  readers=" DUP _RW-READERS @ .
    ."  writer=" DUP _RW-WRITER @ .
    ."  revt:" DUP _RW-REVT EVT-INFO
    ."  wevt:" DUP _RW-WEVT EVT-INFO
    ." ]" CR
    DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  RWLOCK        ( lock# "name" -- )    Create reader-writer lock
\  READ-LOCK     ( rwl -- )             Acquire shared read access
\  READ-UNLOCK   ( rwl -- )             Release read access
\  WRITE-LOCK    ( rwl -- )             Acquire exclusive write access
\  WRITE-UNLOCK  ( rwl -- )             Release write access
\  WITH-READ     ( xt rwl -- )          RAII: read lock, exec, unlock
\  WITH-WRITE    ( xt rwl -- )          RAII: write lock, exec, unlock
\  RW-READERS    ( rwl -- n )           Active reader count (lock-free)
\  RW-WRITER?    ( rwl -- flag )        Writer active? (lock-free)
\  RW-INFO       ( rwl -- )             Debug display
