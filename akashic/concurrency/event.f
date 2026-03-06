\ event.f — Wait/Notify Events for KDOS / Megapad-64
\
\ Foundational synchronization primitive for the concurrency library.
\ An event is a boolean flag that tasks can wait on and other tasks
\ (or ISRs, or other cores) can signal.
\
\ EVT-WAIT spins in a yield-aware loop until the flag is set.
\ EVT-SET flips the flag and marks all registered waiters as T.READY.
\
\ On a single core, the signaler must be an ISR, timer callback, or
\ code on another core — two cooperative tasks on the same core cannot
\ interleave (the scheduler is run-to-completion).  On multiple cores,
\ one core can spin in EVT-WAIT while another calls EVT-SET via shared
\ memory.  This is the intended primary use case.
\
\ All higher-level primitives (channels, futures, semaphores) build on
\ events as their wait/notify mechanism.
\
\ Data structure — 4 cells = 32 bytes:
\   +0   flag        0 = unset, -1 = set
\   +8   wait-count  number of tasks currently in EVT-WAIT
\   +16  waiter-0    task descriptor of first waiter (or 0)
\   +24  waiter-1    task descriptor of second waiter (or 0)
\
\ Atomicity: spinlock 6 (EVT-LOCK) guards flag + waiter mutations.
\
\ Prefix: EVT-   (public API)
\         _EVT-  (internal helpers)
\
\ Load with:   REQUIRE event.f

PROVIDED akashic-event

\ =====================================================================
\  Constants
\ =====================================================================

6 CONSTANT EVT-LOCK                \ hardware spinlock for event ops
4 CONSTANT _EVT-CELLS              \ cells per event descriptor
32 CONSTANT _EVT-SIZE              \ bytes per event descriptor (4 × 8)
2 CONSTANT _EVT-MAX-WAITERS        \ waiter slots per event

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _EVT-FLAG   ( ev -- addr )   ;            \ +0
: _EVT-WCNT   ( ev -- addr )   8 + ;        \ +8  wait-count
: _EVT-W0     ( ev -- addr )   16 + ;       \ +16 waiter-0
: _EVT-W1     ( ev -- addr )   24 + ;       \ +24 waiter-1

\ =====================================================================
\  EVENT — Defining Word
\ =====================================================================

\ EVENT ( "name" -- )
\   Create a manual-reset event, initially unset.
\   Compiles inline data (32 bytes) and defines a constant
\   pointing to it.
\
\   Example:   EVENT my-done
\              my-done EVT-SET

: EVENT  ( "name" -- )
    HERE >R
    0 ,              \ +0  flag  = unset
    0 ,              \ +8  wait-count = 0
    0 ,              \ +16 waiter-0 = none
    0 ,              \ +24 waiter-1 = none
    R> CONSTANT ;

\ =====================================================================
\  Query
\ =====================================================================

\ EVT-SET? ( ev -- flag )
\   Return TRUE (-1) if the event is currently set, FALSE (0) otherwise.
\   Lock-free read — the flag cell is a single aligned 64-bit word,
\   so reads are atomic on Megapad-64.

: EVT-SET?  ( ev -- flag )
    @ 0<> ;

\ =====================================================================
\  Internal — Waiter Management
\ =====================================================================

\ _EVT-ADD-WAITER ( ev -- )
\   Register the current task as a waiter on this event.
\   Must be called under EVT-LOCK.

: _EVT-ADD-WAITER  ( ev -- )
    CURRENT-TASK @ DUP 0= IF  2DROP EXIT  THEN   \ no current task
    SWAP
    DUP _EVT-W0 @ 0= IF                          \ slot 0 free?
        _EVT-W0 !
        1 SWAP _EVT-WCNT +!  EXIT
    THEN
    DUP _EVT-W1 @ 0= IF                          \ slot 1 free?
        _EVT-W1 !
        1 SWAP _EVT-WCNT +!  EXIT
    THEN
    2DROP ;                                       \ both full, ignore

\ _EVT-REMOVE-WAITER ( ev -- )
\   Remove the current task from this event's waiter list.
\   Must be called under EVT-LOCK.

: _EVT-REMOVE-WAITER  ( ev -- )
    CURRENT-TASK @ DUP 0= IF  2DROP EXIT  THEN   \ no current task
    SWAP
    DUP _EVT-W0 @ ROT = IF                       \ in slot 0?
        0 OVER _EVT-W0 !
        -1 SWAP _EVT-WCNT +!  EXIT
    THEN
    CURRENT-TASK @
    OVER _EVT-W1 @ = IF                          \ in slot 1?
        0 OVER _EVT-W1 !
        -1 SWAP _EVT-WCNT +!  EXIT
    THEN
    DROP ;                                        \ not found

\ _EVT-WAKE-ALL ( ev -- )
\   Mark all waiters as T.READY and clear the waiter list.
\   Must be called under EVT-LOCK.

: _EVT-WAKE-ALL  ( ev -- )
    DUP _EVT-W0 @ ?DUP IF  T.READY SWAP T.STATUS!  THEN
    DUP _EVT-W1 @ ?DUP IF  T.READY SWAP T.STATUS!  THEN
    0 OVER _EVT-W0 !
    0 OVER _EVT-W1 !
    0 SWAP _EVT-WCNT ! ;

\ =====================================================================
\  EVT-SET — Signal the Event
\ =====================================================================

\ EVT-SET ( ev -- )
\   Set the event flag and wake all waiters.
\   Safe to call from any core.

: EVT-SET  ( ev -- )
    EVT-LOCK LOCK
    -1 OVER !                  \ set flag
    _EVT-WAKE-ALL
    EVT-LOCK UNLOCK ;

\ =====================================================================
\  EVT-RESET — Clear the Event
\ =====================================================================

\ EVT-RESET ( ev -- )
\   Clear the event flag back to unset.
\   Does NOT affect waiters — if tasks are spinning in EVT-WAIT,
\   they will continue to wait.

: EVT-RESET  ( ev -- )
    EVT-LOCK LOCK
    0 SWAP !
    EVT-LOCK UNLOCK ;

\ =====================================================================
\  EVT-WAIT — Block Until Signaled
\ =====================================================================

\ EVT-WAIT ( ev -- )
\   Spin until the event is set.  Calls YIELD? on each iteration
\   for preemption awareness.
\
\   On multicore: another core calls EVT-SET, this core sees the
\   flag change via shared memory.
\
\   On single core: the signal must come from an ISR or timer callback.
\   Two cooperative tasks on the same core cannot interleave — the
\   scheduler is run-to-completion.
\
\   The current task is marked T.BLOCKED while waiting (informational
\   for TASKS display and future scheduler enhancements).

: EVT-WAIT  ( ev -- )
    \ Fast path: already set
    DUP EVT-SET? IF  DROP EXIT  THEN
    \ Register as waiter
    EVT-LOCK LOCK
    DUP _EVT-ADD-WAITER
    EVT-LOCK UNLOCK
    \ Mark task as blocked (informational)
    CURRENT-TASK @ ?DUP IF  T.BLOCKED SWAP T.STATUS!  THEN
    \ Spin until flag is set
    BEGIN  DUP EVT-SET? 0= WHILE  YIELD?  REPEAT
    \ Clean up: remove from waiter list, restore running state
    EVT-LOCK LOCK
    DUP _EVT-REMOVE-WAITER
    EVT-LOCK UNLOCK
    CURRENT-TASK @ ?DUP IF  T.RUNNING SWAP T.STATUS!  THEN
    DROP ;

\ =====================================================================
\  EVT-WAIT-TIMEOUT — Block with Timeout
\ =====================================================================

\ EVT-WAIT-TIMEOUT ( ev ms -- flag )
\   Wait up to `ms` milliseconds for the event to become set.
\   Returns TRUE (-1) if the event was signaled within the timeout,
\   FALSE (0) if the timeout expired.
\
\   Uses EPOCH@ (BIOS: milliseconds since boot) for timing.

\ _EVT-DEADLINE removed — deadline now lives on the return stack
\ inside EVT-WAIT-TIMEOUT to avoid shared-state corruption when
\ multiple tasks call EVT-WAIT-TIMEOUT concurrently.  (Tier 0a fix)

: EVT-WAIT-TIMEOUT  ( ev ms -- flag )
    \ Fast path: already set
    OVER EVT-SET? IF  2DROP -1 EXIT  THEN
    \ Compute deadline → return stack
    EPOCH@ + >R                       \ R: ( deadline )
    \ Register as waiter
    EVT-LOCK LOCK
    DUP _EVT-ADD-WAITER
    EVT-LOCK UNLOCK
    \ Mark task as blocked
    CURRENT-TASK @ ?DUP IF  T.BLOCKED SWAP T.STATUS!  THEN
    \ Spin with timeout check
    BEGIN
        DUP EVT-SET? IF                       \ signaled?
            \ Clean up and return TRUE
            EVT-LOCK LOCK
            DUP _EVT-REMOVE-WAITER
            EVT-LOCK UNLOCK
            CURRENT-TASK @ ?DUP IF  T.RUNNING SWAP T.STATUS!  THEN
            R> DROP                           \ discard deadline
            DROP -1 EXIT
        THEN
        EPOCH@ R@ > IF                        \ timed out?
            \ Clean up and return FALSE
            EVT-LOCK LOCK
            DUP _EVT-REMOVE-WAITER
            EVT-LOCK UNLOCK
            CURRENT-TASK @ ?DUP IF  T.RUNNING SWAP T.STATUS!  THEN
            R> DROP                           \ discard deadline
            DROP 0 EXIT
        THEN
        YIELD?
    AGAIN ;

\ =====================================================================
\  EVT-PULSE — Set + Immediate Reset
\ =====================================================================

\ EVT-PULSE ( ev -- )
\   Atomically set the event (waking all waiters), then immediately
\   reset it.  Only tasks currently spinning in EVT-WAIT will be woken.
\   Tasks that check later will see the event unset.

: EVT-PULSE  ( ev -- )
    EVT-LOCK LOCK
    -1 OVER !                  \ set flag
    DUP _EVT-WAKE-ALL          \ wake waiters
    0 OVER !                   \ immediately reset
    EVT-LOCK UNLOCK
    DROP ;

\ =====================================================================
\  EVT-INFO — Debug Display
\ =====================================================================

\ EVT-INFO ( ev -- )
\   Print event status for debugging.

: EVT-INFO  ( ev -- )
    ." [event"
    DUP EVT-SET? IF ."  SET" ELSE ."  UNSET" THEN
    ."  waiters=" DUP _EVT-WCNT @ .
    ." ]" CR
    DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  EVENT            ( "name" -- )          Create event (initially unset)
\  EVT-SET?         ( ev -- flag )         Is event set?
\  EVT-SET          ( ev -- )              Signal event, wake waiters
\  EVT-RESET        ( ev -- )              Clear event flag
\  EVT-WAIT         ( ev -- )              Spin until event is set
\  EVT-WAIT-TIMEOUT ( ev ms -- flag )      Wait with timeout (ms)
\  EVT-PULSE        ( ev -- )              Set + immediate reset
\  EVT-INFO         ( ev -- )              Debug display
