\ semaphore.f — Counting Semaphores for KDOS / Megapad-64
\
\ Classic counting semaphore built on top of event.f.
\ Use for rate-limiting (e.g., max N concurrent TCP connections),
\ producer-consumer synchronization, and general resource counting.
\
\ SEM-WAIT decrements the count; if the count would go negative,
\ the caller spins in an event-wait loop until SEM-SIGNAL raises it.
\ SEM-SIGNAL increments the count and pulses the embedded event to
\ wake one blocked waiter.
\
\ Data structure — 5 cells = 40 bytes:
\   +0   count       current count (signed, 64-bit)
\   +8   event       embedded event (4 cells = 32 bytes)
\                      +8   flag
\                      +16  wait-count
\                      +24  waiter-0
\                      +32  waiter-1
\
\ The event is embedded inline — no pointer indirection, no heap.
\ Atomicity uses EVT-LOCK (spinlock 6), same as event.f, so that
\ count mutation and event signaling are atomic together.
\
\ REQUIRE event.f
\
\ Prefix: SEM-   (public API)
\         _SEM-  (internal helpers)
\
\ Load with:   REQUIRE semaphore.f

REQUIRE ../concurrency/event.f

PROVIDED akashic-semaphore

\ =====================================================================
\  Constants
\ =====================================================================

5 CONSTANT _SEM-CELLS              \ cells per semaphore descriptor
40 CONSTANT _SEM-SIZE              \ bytes per semaphore (5 × 8)

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _SEM-COUNT  ( sem -- addr )   ;          \ +0  count cell
: _SEM-EVT    ( sem -- ev )     8 + ;      \ +8  embedded event

\ =====================================================================
\  SEMAPHORE — Defining Word
\ =====================================================================

\ SEMAPHORE ( initial "name" -- )
\   Create a named counting semaphore with the given initial count.
\   The initial count is typically the number of available resources.
\
\   Example:   3 SEMAPHORE tcp-slots   \ max 3 concurrent connections
\              tcp-slots SEM-WAIT      \ acquire a slot
\              ... use slot ...
\              tcp-slots SEM-SIGNAL    \ release the slot

: SEMAPHORE  ( initial "name" -- )
    HERE >R
    ,                \ +0  count = initial
    \ Embedded event (4 cells, initially unset)
    0 ,              \ +8  event flag = unset
    0 ,              \ +16 event wait-count = 0
    0 ,              \ +24 event waiter-0 = none
    0 ,              \ +32 event waiter-1 = none
    R> CONSTANT ;

\ =====================================================================
\  Query
\ =====================================================================

\ SEM-COUNT ( sem -- n )
\   Return the current count.  Lock-free read — single aligned cell.

: SEM-COUNT  ( sem -- n )
    @ ;

\ =====================================================================
\  SEM-WAIT — Acquire (Decrement)
\ =====================================================================

\ SEM-WAIT ( sem -- )
\   Decrement the semaphore count.  If the count is already 0 (or
\   negative), block in an event-wait loop until SEM-SIGNAL raises
\   the count.
\
\   Multicore: another core calls SEM-SIGNAL to unblock this one.
\   Single core: the signal must come from an ISR or another core.
\
\   The embedded event is used as a pulse notification — each
\   SEM-SIGNAL pulses the event, waking one waiter who then
\   re-checks the count under lock.

: SEM-WAIT  ( sem -- )
    BEGIN
        \ Try to decrement under lock
        EVT-LOCK LOCK
        DUP @ 0> IF                    \ count > 0?
            -1 OVER +!                 \ count--
            EVT-LOCK UNLOCK
            DROP EXIT                  \ acquired — done
        THEN
        EVT-LOCK UNLOCK
        \ Count is 0 — wait for a signal
        DUP _SEM-EVT EVT-WAIT
        DUP _SEM-EVT EVT-RESET        \ reset for next wait cycle
    AGAIN ;

\ =====================================================================
\  SEM-SIGNAL — Release (Increment)
\ =====================================================================

\ SEM-SIGNAL ( sem -- )
\   Increment the semaphore count and wake one blocked waiter
\   (if any) by pulsing the embedded event.
\
\   Safe to call from any core and from ISRs.

: SEM-SIGNAL  ( sem -- )
    EVT-LOCK LOCK
    1 OVER +!                          \ count++
    EVT-LOCK UNLOCK
    _SEM-EVT EVT-PULSE ;              \ wake one waiter

\ =====================================================================
\  SEM-TRYWAIT — Non-Blocking Acquire
\ =====================================================================

\ SEM-TRYWAIT ( sem -- flag )
\   Try to decrement the count without blocking.
\   Returns TRUE (-1) if acquired, FALSE (0) if count was 0.

: SEM-TRYWAIT  ( sem -- flag )
    EVT-LOCK LOCK
    DUP @ 0> IF
        -1 OVER +!                     \ count--
        EVT-LOCK UNLOCK
        DROP -1                        \ acquired
    ELSE
        EVT-LOCK UNLOCK
        DROP 0                         \ not acquired
    THEN ;

\ =====================================================================
\  SEM-WAIT-TIMEOUT — Acquire with Timeout
\ =====================================================================

\ SEM-WAIT-TIMEOUT ( sem ms -- flag )
\   Try to acquire the semaphore within `ms` milliseconds.
\   Returns TRUE (-1) if acquired, FALSE (0) if timed out.
\
\   Uses EPOCH@ (BIOS: milliseconds since boot) for timing.

VARIABLE _SEM-DEADLINE

: SEM-WAIT-TIMEOUT  ( sem ms -- flag )
    EPOCH@ + _SEM-DEADLINE !
    BEGIN
        \ Try to decrement under lock
        EVT-LOCK LOCK
        DUP @ 0> IF
            -1 OVER +!
            EVT-LOCK UNLOCK
            DROP -1 EXIT               \ acquired
        THEN
        EVT-LOCK UNLOCK
        \ Check timeout
        EPOCH@ _SEM-DEADLINE @ > IF
            DROP 0 EXIT                \ timed out
        THEN
        \ Wait for signal with remaining time
        DUP _SEM-EVT EVT-SET? IF
            DUP _SEM-EVT EVT-RESET     \ consume the pulse, retry
        ELSE
            YIELD?                     \ yield and retry
        THEN
    AGAIN ;

\ =====================================================================
\  SEM-INFO — Debug Display
\ =====================================================================

\ SEM-INFO ( sem -- )
\   Print semaphore status for debugging.

: SEM-INFO  ( sem -- )
    ." [semaphore count=" DUP @ .
    ."  evt:" DUP _SEM-EVT EVT-INFO
    ." ]" CR
    DROP ;

\ =====================================================================
\  Convenience / RAII Pattern
\ =====================================================================

\ WITH-SEM ( xt sem -- )
\   Acquire the semaphore, execute xt, then release.
\   Ensures SEM-SIGNAL is called even if xt ABORTs (via CATCH).
\
\   Example:   ['] do-work tcp-slots WITH-SEM

: WITH-SEM  ( xt sem -- )
    DUP >R SEM-WAIT
    CATCH
    R> SEM-SIGNAL
    THROW ;                            \ re-throw if xt failed

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  SEMAPHORE        ( initial "name" -- )  Create counting semaphore
\  SEM-COUNT        ( sem -- n )           Current count (lock-free)
\  SEM-WAIT         ( sem -- )             Acquire (block if count=0)
\  SEM-SIGNAL       ( sem -- )             Release (increment + wake)
\  SEM-TRYWAIT      ( sem -- flag )        Non-blocking acquire
\  SEM-WAIT-TIMEOUT ( sem ms -- flag )     Acquire with timeout
\  SEM-INFO         ( sem -- )             Debug display
\  WITH-SEM         ( xt sem -- )          RAII: acquire, exec, release
