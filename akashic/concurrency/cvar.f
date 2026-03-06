\ cvar.f — Concurrent Variables for KDOS / Megapad-64
\
\ Atomic cells with change notification.  A concurrent variable
\ wraps a memory cell with spinlock-protected read/write,
\ compare-and-swap, and wait-for-change semantics.
\
\ All mutations are guarded by EVT-LOCK (spinlock 6), making
\ reads and writes effectively atomic even if a single 64-bit
\ store were not naturally atomic.  The embedded event allows
\ CV-WAIT to block efficiently until the value changes.
\
\ Data structure — Concurrent Variable (4 cells = 32 bytes):
\   +0   value       Current value
\   +8   lock#       Spinlock number (default: EVT-LOCK = 6)
\   +16  change-event  Embedded event (pulsed on every write)
\        +16  flag
\        +24  wait-count
\        +32  waiter-0
\        +40  waiter-1
\
\ Total allocation: 6 cells = 48 bytes
\
\ Dependencies: event.f (for EVT-PULSE, EVT-WAIT, EVT-RESET)
\
\ Prefix: CV-  (public API)
\         _CV- (internal helpers)
\
\ Load with:   REQUIRE cvar.f

REQUIRE ../concurrency/event.f

PROVIDED akashic-cvar

\ =====================================================================
\  Constants
\ =====================================================================

48 CONSTANT _CV-SIZE               \ bytes per cvar (6 cells)

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _CV-VAL   ( cv -- addr )              ; \ +0  value
: _CV-LOCK  ( cv -- n )    8 + @ ;        \ +8  spinlock number
: _CV-EVT   ( cv -- ev )   16 + ;         \ +16 embedded event

\ =====================================================================
\  CVAR — Define a Concurrent Variable
\ =====================================================================

\ CVAR ( initial "name" -- )
\   Create a named concurrent variable initialized to `initial`.
\   Uses EVT-LOCK (spinlock 6) for protection.
\
\   Example:   0 CVAR request-count
\              42 CVAR my-config

: CVAR  ( initial "name" -- )
    HERE >R
    ,                \ +0  value = initial
    EVT-LOCK ,       \ +8  lock# = EVT-LOCK (6)
    \ Embedded change-event (4 cells, unset)
    0 ,              \ +16 event flag = 0
    0 ,              \ +24 event wait-count = 0
    0 ,              \ +32 event waiter-0 = none
    0 ,              \ +40 event waiter-1 = none
    R> CONSTANT ;

\ =====================================================================
\  CV@ — Atomic Read
\ =====================================================================

\ CV@ ( cv -- val )
\   Read the concurrent variable's value under spinlock protection.
\
\   On Megapad-64, aligned 64-bit loads are naturally atomic, so
\   the lock is technically redundant for reads.  It's included for
\   consistency and correctness on potential future platforms.

: CV@  ( cv -- val )
    DUP _CV-LOCK LOCK
    @ SWAP
    _CV-LOCK UNLOCK ;

\ =====================================================================
\  CV! — Atomic Write + Notify
\ =====================================================================

\ CV! ( val cv -- )
\   Atomically store `val` into the concurrent variable and pulse
\   the change-event to wake all CV-WAIT callers.
\
\   Example:   42 my-cvar CV!

: CV!  ( val cv -- )
    DUP _CV-LOCK LOCK
    SWAP OVER !                    \ store value
    DUP _CV-LOCK UNLOCK
    _CV-EVT EVT-PULSE ;           \ notify waiters

\ =====================================================================
\  CV-CAS — Compare-and-Swap
\ =====================================================================

\ CV-CAS ( expected new cv -- flag )
\   Atomically compare the current value with `expected`.  If they
\   match, store `new` and return TRUE (-1).  Otherwise, leave the
\   value unchanged and return FALSE (0).
\
\   On success, the change-event is pulsed to wake waiters.
\
\   Example:   0 1 my-counter CV-CAS  ( -- flag )

\ _CV-CAS-CV, _CV-CAS-NEW, _CV-CAS-EXP removed — CV-CAS now uses
\ pure stack manipulation under the lock to avoid shared-state
\ corruption when multiple tasks call CV-CAS concurrently on
\ different cvars.  (Tier 0e fix)

: CV-CAS  ( expected new cv -- flag )
    >R                                 \ save cv  R: ( cv )
    R@ _CV-LOCK LOCK                   \ lock under cv's spinlock
    R@ @ 2 PICK = IF                   \ cv @ = expected?
        R@ !                           \ store new into cv  ( expected )
        DROP                           \ drop expected
        R@ _CV-LOCK UNLOCK
        R> _CV-EVT EVT-PULSE          \ notify waiters
        -1                             \ success
    ELSE
        R@ _CV-LOCK UNLOCK
        R> DROP                        \ discard cv from R
        2DROP                          \ drop new expected
        0                              \ failure
    THEN ;

\ =====================================================================
\  CV-ADD — Atomic Fetch-and-Add
\ =====================================================================

\ CV-ADD ( n cv -- )
\   Atomically add `n` to the concurrent variable's value and
\   pulse the change-event.
\
\   Example:   1 request-count CV-ADD

: CV-ADD  ( n cv -- )
    DUP _CV-LOCK LOCK
    SWAP OVER +!                   \ val += n
    DUP _CV-LOCK UNLOCK
    _CV-EVT EVT-PULSE ;           \ notify waiters

\ =====================================================================
\  CV-WAIT — Block Until Value Changes
\ =====================================================================

\ CV-WAIT ( expected cv -- )
\   Block until the concurrent variable's value differs from
\   `expected`.  Uses the embedded change-event for notification.
\
\   On single-core, this requires another entity (ISR, timer, or
\   cooperative task via SCHEDULE) to call CV! or CV-ADD.  On
\   multicore, another core changes the value.
\
\   Protocol:
\     1. Check current value — if already ≠ expected, return.
\     2. EVT-WAIT on change-event.
\     3. EVT-RESET the change-event.
\     4. Re-check value; if still = expected, loop.

: CV-WAIT  ( expected cv -- )
    BEGIN
        DUP CV@ 2 PICK <> IF        \ value ≠ expected?
            2DROP EXIT               \ done — value changed
        THEN
        DUP _CV-EVT EVT-WAIT        \ wait for pulse
        DUP _CV-EVT EVT-RESET       \ reset for next round
    AGAIN ;

\ =====================================================================
\  CV-WAIT-TIMEOUT — Block with Timeout
\ =====================================================================

\ CV-WAIT-TIMEOUT ( expected cv ms -- flag )
\   Wait up to `ms` milliseconds for the value to differ from
\   `expected`.  Returns TRUE if the value changed, FALSE on timeout.

: CV-WAIT-TIMEOUT  ( expected cv ms -- flag )
    \ Fast path: value already differs
    OVER CV@ 2 PICK <> IF             \ cv's value ≠ expected?
        2DROP DROP -1 EXIT             \ yes → TRUE immediately
    THEN
    ROT >R                             \ R: expected  ( cv ms )
    OVER _CV-EVT SWAP                  \ ( cv ev ms )
    EVT-WAIT-TIMEOUT                   \ ( cv flag )
    IF
        DUP _CV-EVT EVT-RESET
        CV@ R> <> IF  -1  ELSE  0  THEN
    ELSE
        DROP R> DROP 0                 \ timeout
    THEN ;

\ =====================================================================
\  CV-RESET — Reset for Testing
\ =====================================================================

\ CV-RESET ( val cv -- )
\   Force-set the value without notification.  Resets the embedded
\   event.  Intended for testing and reinitialization.

: CV-RESET  ( val cv -- )
    DUP _CV-LOCK LOCK
    SWAP OVER !
    DUP _CV-LOCK UNLOCK
    _CV-EVT EVT-RESET ;

\ =====================================================================
\  CV-INFO — Debug Display
\ =====================================================================

\ CV-INFO ( cv -- )
\   Print concurrent variable status for debugging.

: CV-INFO  ( cv -- )
    ." [cvar"
    ."  val=" DUP @ .
    ."  lock=" DUP 8 + @ .
    ."  evt:" DUP _CV-EVT EVT-INFO
    ." ]" CR
    DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  CVAR             ( initial "name" -- )     Create concurrent variable
\  CV@              ( cv -- val )             Atomic read
\  CV!              ( val cv -- )             Atomic write + notify
\  CV-CAS           ( exp new cv -- flag )    Compare-and-swap
\  CV-ADD           ( n cv -- )               Atomic fetch-and-add
\  CV-WAIT          ( exp cv -- )             Block until value changes
\  CV-WAIT-TIMEOUT  ( exp cv ms -- flag )     Wait with timeout
\  CV-RESET         ( val cv -- )             Force-set without notify
\  CV-INFO          ( cv -- )                 Debug display
