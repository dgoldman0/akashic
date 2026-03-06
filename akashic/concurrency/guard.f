\ guard.f — Non-Reentrant Guards for KDOS / Megapad-64
\
\ A guard is a named mutual-exclusion wrapper.  Module authors
\ attach guards to words to ensure non-reentrant access to shared
\ state (e.g., shared VARIABLEs in fp16.f, mat2d.f, MMIO registers).
\
\ Two flavors:
\   GUARD          — spinning guard (busy-waits via SPIN@ style loop)
\   GUARD-BLOCKING — blocking guard (yields via embedded semaphore)
\
\ Both detect re-entry and ABORT instead of deadlocking.
\
\ Data structure — spinning guard (3 cells = 24 bytes):
\   +0   flag     0 = free, -1 = held
\   +8   owner    task descriptor of holder, or 0
\   +16  mode     0 = spin, 1 = blocking
\
\ Data structure — blocking guard (3 cells + semaphore = 64 bytes):
\   +0   flag     0 = free, -1 = held
\   +8   owner    task descriptor of holder, or 0
\   +16  mode     0 = spin, 1 = blocking
\   +24  sem      embedded 1-count semaphore (5 cells = 40 bytes)
\
\ CRITICAL: PAUSE and TASK-YIELD are BIOS hardware coroutine words.
\ Guards use KDOS YIELD? for cooperative spinning — different mechanism.
\
\ Dependencies: semaphore.f (for GUARD-BLOCKING only)
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

3 CONSTANT _GRD-CELLS-SPIN         \ cells for spinning guard
8 CONSTANT _GRD-CELLS-BLOCK        \ cells for blocking guard (3 + 5 sem)
24 CONSTANT _GRD-SIZE-SPIN         \ bytes
64 CONSTANT _GRD-SIZE-BLOCK        \ bytes

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _GRD-FLAG   ( guard -- addr )   ;          \ +0  flag cell
: _GRD-OWNER  ( guard -- addr )   8 + ;      \ +8  owner cell
: _GRD-MODE   ( guard -- addr )   16 + ;     \ +16 mode cell
: _GRD-SEM    ( guard -- sem )    24 + ;     \ +24 embedded semaphore

\ =====================================================================
\  GUARD — Defining Word (spinning)
\ =====================================================================

\ GUARD ( "name" -- )
\   Create a named spinning guard, initially free.
\   Spinning guards busy-wait with YIELD? — suitable for short
\   critical sections where contention is rare.
\
\   Example:   GUARD fp16-guard

: GUARD  ( "name" -- )
    CREATE
        0 ,          \ flag = free
        0 ,          \ owner = none
        0 ,          \ mode = spin
    DOES> ;

\ =====================================================================
\  GUARD-BLOCKING — Defining Word (blocking)
\ =====================================================================

\ GUARD-BLOCKING ( "name" -- )
\   Create a named blocking guard, initially free.
\   Blocking guards yield via semaphore wait — suitable for longer
\   critical sections or when spinning wastes too many cycles.
\
\   The embedded semaphore starts with count 1 (one permit).
\
\   Example:   GUARD-BLOCKING fs-guard

: GUARD-BLOCKING  ( "name" -- )
    CREATE
        0 ,          \ flag = free
        0 ,          \ owner = none
        1 ,          \ mode = blocking
        \ Inline a 1-count semaphore (5 cells = 40 bytes)
        1 ,          \ sem +0: count = 1
        0 ,          \ sem +8: event flag = 0 (unset)
        0 ,          \ sem +16: event wait-count = 0
        0 ,          \ sem +24: event waiter-0 = 0
        0 ,          \ sem +32: event waiter-1 = 0
    DOES> ;

\ =====================================================================
\  GUARD-ACQUIRE — Acquire a Guard
\ =====================================================================

\ GUARD-ACQUIRE ( guard -- )
\   Acquire the guard.  If the same task already holds it, ABORT
\   with a re-entry error (prevents deadlock).
\
\   For spinning guards:  busy-wait on the flag cell with YIELD?.
\   For blocking guards:  SEM-WAIT on the embedded semaphore.

: GUARD-ACQUIRE  ( guard -- )
    \ Re-entry check: if guard is held AND owner matches current task
    DUP _GRD-FLAG @ IF
        DUP _GRD-OWNER @ CURRENT-TASK @ = IF
            -257 THROW    \ guard re-entry detected
        THEN
    THEN
    DUP _GRD-MODE @ IF
        \ Blocking mode: wait on semaphore
        DUP _GRD-SEM SEM-WAIT
    ELSE
        \ Spinning mode: busy-wait on flag
        DUP _GRD-FLAG
        BEGIN DUP @ WHILE YIELD? REPEAT
        DROP
    THEN
    \ Claim it
    -1 OVER _GRD-FLAG !
    CURRENT-TASK @ SWAP _GRD-OWNER ! ;

\ =====================================================================
\  GUARD-RELEASE — Release a Guard
\ =====================================================================

\ GUARD-RELEASE ( guard -- )
\   Release the guard.  Clears the owner and flag.
\   For blocking guards, also signals the embedded semaphore.

: GUARD-RELEASE  ( guard -- )
    0 OVER _GRD-OWNER !     \ clear owner
    0 OVER _GRD-FLAG !      \ clear flag
    DUP _GRD-MODE @ IF
        _GRD-SEM SEM-SIGNAL \ wake one blocked waiter
    ELSE
        DROP
    THEN ;

\ =====================================================================
\  WITH-GUARD — RAII-Style Execute Under Guard
\ =====================================================================

\ WITH-GUARD ( xt guard -- )
\   Acquire guard, execute xt, release guard.
\   If xt THROWs, the guard is still released before re-throw.
\
\   Example:
\     ['] my-fp16-op  fp16-guard WITH-GUARD

: WITH-GUARD  ( xt guard -- )
    DUP >R GUARD-ACQUIRE
    CATCH
    R> GUARD-RELEASE
    DUP IF THROW THEN
    DROP ;

\ =====================================================================
\  GUARD-HELD? — Query Guard Status
\ =====================================================================

\ GUARD-HELD? ( guard -- flag )
\   TRUE (-1) if the guard is currently held, FALSE (0) otherwise.
\   Lock-free read — just reads the flag cell.

: GUARD-HELD?  ( guard -- flag )
    _GRD-FLAG @ 0<> ;

\ =====================================================================
\  GUARD-MINE? — Am I the Holder?
\ =====================================================================

\ GUARD-MINE? ( guard -- flag )
\   TRUE (-1) if the current task holds this guard.

: GUARD-MINE?  ( guard -- flag )
    DUP _GRD-FLAG @ 0= IF DROP 0 EXIT THEN
    _GRD-OWNER @ CURRENT-TASK @ = ;

\ =====================================================================
\  GUARD-INFO — Debug Display
\ =====================================================================

\ GUARD-INFO ( guard -- )
\   Print guard status.

: GUARD-INFO  ( guard -- )
    ." [guard "
    DUP _GRD-MODE @ IF ." blocking" ELSE ." spin" THEN
    ."  "
    DUP GUARD-HELD? IF
        ." HELD owner="
        DUP _GRD-OWNER @ .
    ELSE
        ." FREE"
    THEN
    ." ]" CR
    DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  GUARD             ( "name" -- )           Create spinning guard
\  GUARD-BLOCKING    ( "name" -- )           Create blocking guard
\  GUARD-ACQUIRE     ( guard -- )            Acquire (aborts on re-entry)
\  GUARD-RELEASE     ( guard -- )            Release
\  WITH-GUARD        ( xt guard -- )         RAII execute under guard
\  GUARD-HELD?       ( guard -- flag )       Is guard held?
\  GUARD-MINE?       ( guard -- flag )       Am I the holder?
\  GUARD-INFO        ( guard -- )            Debug display
