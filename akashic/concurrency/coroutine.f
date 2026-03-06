\ coroutine.f — Structured Wrappers for BIOS Hardware Coroutine Pair
\
\ The BIOS (Phase 8) exposes a 2-task hardware coroutine using SEP:
\   Task 0 = R3 (Forth inner interpreter / main application)
\   Task 1 = R13 (single background helper)
\
\ Raw BIOS words:
\   PAUSE       ( -- )       Task 0 → Task 1 (no-op if none)
\   TASK-YIELD  ( -- )       Task 1 → Task 0
\   BACKGROUND  ( xt -- )    install xt as Task 1 and start it
\   TASK-STOP   ( -- )       cancel Task 1
\   TASK?       ( -- flag )  1 if Task 1 active, 0 otherwise
\
\ CRITICAL: PAUSE and TASK-YIELD are NOT interchangeable.
\   PAUSE overwrites R13 to load Task 1's saved PC.  When psel=13
\   (i.e. inside Task 1), R13 IS the program counter — PAUSE would
\   overwrite it with a stale address → crash.
\   Task 0 code calls PAUSE.  Task 1 code calls TASK-YIELD.
\
\ This file adds structured wrappers that guarantee cleanup:
\
\   WITH-BACKGROUND  ( xt-bg xt-body -- )
\       Start xt-bg as Task 1, execute xt-body on Task 0, then
\       TASK-STOP — even if xt-body THROWs.
\
\   BG-POLL  ( xt -- )
\       Install xt as a polling loop: BEGIN xt EXECUTE TASK-YIELD AGAIN.
\       The word returns immediately; Task 1 runs on each PAUSE
\       from Task 0.  Use WITH-BACKGROUND to auto-stop, or TASK-STOP.
\
\   BG-ALIVE?  ( -- flag )
\       Alias for TASK?.  TRUE if background task is still running.
\
\   BG-WAIT-DONE  ( -- )
\       Busy-wait (with PAUSE) until background task finishes.
\       Only useful for one-shot background tasks that return.
\
\ Naming note: The BIOS renamed its background yield word from YIELD
\ to TASK-YIELD to avoid collision with KDOS YIELD (marks current
\ task T.DONE).  This library uses PAUSE (Task 0 → Task 1) and
\ TASK-YIELD (Task 1 → Task 0).
\
\ Constraints:
\   - One background slot only (R13).
\   - Fully cooperative — no preemption.
\   - Micro-cores lack Q flip-flop; EMIT traps there.
\   - Background task shares address space / dictionary.
\
\ Dependencies: none (BIOS words are always available)
\
\ Prefix: BG-  (public API, except WITH-BACKGROUND)
\         _BG- (internal helpers)
\
\ Load with:   REQUIRE coroutine.f

PROVIDED akashic-coroutine

\ =====================================================================
\  BG-ALIVE? — Query Background Task Status
\ =====================================================================

\ BG-ALIVE? ( -- flag )
\   TRUE (-1) if a background task is currently active.
\   Thin wrapper around TASK? normalised to Forth flag convention.

: BG-ALIVE?  ( -- flag )
    TASK? 0<> ;

\ =====================================================================
\  WITH-BACKGROUND — Scoped Background Task
\ =====================================================================

\ WITH-BACKGROUND ( xt-bg xt-body -- )
\   Start xt-bg as the background task, execute xt-body on Task 0,
\   then unconditionally TASK-STOP.  If xt-body THROWs, the
\   background task is still stopped before the exception propagates.
\
\   xt-bg   must have signature ( -- ).  It runs as Task 1.
\   xt-body must have signature ( -- ).  It runs as Task 0.
\
\   Example:
\     [: BEGIN _NIC-POLL TASK-YIELD AGAIN ;]
\     [: big-buf big-len SHA-256 ;]
\     WITH-BACKGROUND
\     \ background poller is guaranteed stopped here

: WITH-BACKGROUND  ( xt-bg xt-body -- )
    SWAP BACKGROUND              \ start xt-bg as Task 1
    CATCH                        \ execute xt-body under CATCH
    TASK-STOP                    \ unconditional cleanup
    DUP IF THROW THEN            \ re-throw if xt-body failed
    DROP ;                       \ discard 0 (no error)

\ =====================================================================
\  _BG-POLL-XT — Storage for Polling Loop XT
\ =====================================================================

VARIABLE _BG-POLL-XT

\ _BG-POLL-LOOP ( -- )
\   Internal: infinite loop that calls the stored xt, then yields
\   back to Task 0 via TASK-YIELD.  Runs as Task 1.  Never returns
\   (loops until TASK-STOP).

: _BG-POLL-LOOP  ( -- )
    BEGIN
        _BG-POLL-XT @ EXECUTE
        TASK-YIELD
    AGAIN ;

\ =====================================================================
\  BG-POLL — Install Polling Background Task
\ =====================================================================

\ BG-POLL ( xt -- )
\   Install xt as a background polling loop.  Each PAUSE from Task 0
\   gives Task 1 a timeslice to run xt once, then Task 1 yields
\   back via TASK-YIELD.
\
\   xt must have signature ( -- ).  It is called once per round-trip.
\
\   Returns immediately.  The polling loop runs until TASK-STOP is
\   called (or until used inside WITH-BACKGROUND which auto-stops).
\
\   Example:
\     [: _NIC-POLL ;] BG-POLL
\     ... do work, calling PAUSE periodically ...
\     TASK-STOP

: BG-POLL  ( xt -- )
    _BG-POLL-XT !
    ['] _BG-POLL-LOOP BACKGROUND ;

\ =====================================================================
\  BG-WAIT-DONE — Wait for One-Shot Background Task to Finish
\ =====================================================================

\ BG-WAIT-DONE ( -- )
\   Spin-wait (calling PAUSE each iteration) until the background
\   task finishes naturally (its xt returns → task1_cleanup fires
\   → TASK? returns 0).
\
\   Only useful for one-shot tasks.  For infinite-loop tasks
\   (BG-POLL), this would spin forever — use TASK-STOP instead.
\
\   Example:
\     [: big-buf big-len SHA-256 hash-buf 32 CMOVE ;] BACKGROUND
\     ... do other work, calling PAUSE ...
\     BG-WAIT-DONE
\     \ hash is now ready in hash-buf

: BG-WAIT-DONE  ( -- )
    BEGIN  BG-ALIVE?  WHILE  PAUSE  REPEAT ;

\ =====================================================================
\  BG-INFO — Debug Display
\ =====================================================================

\ BG-INFO ( -- )
\   Print background task status for debugging.

: BG-INFO  ( -- )
    ." [coroutine bg="
    BG-ALIVE? IF ." ACTIVE" ELSE ." STOPPED" THEN
    ." ]" CR ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  BG-ALIVE?         ( -- flag )              Is Task 1 active?
\  WITH-BACKGROUND   ( xt-bg xt-body -- )     Scoped bg task (auto-stop)
\  BG-POLL           ( xt -- )                Install polling bg loop
\  BG-WAIT-DONE      ( -- )                   Wait for one-shot bg task
\  BG-INFO           ( -- )                   Debug display
\
\  Raw BIOS (always available, no REQUIRE needed):
\    PAUSE            ( -- )                   Task 0 → Task 1
\    TASK-YIELD       ( -- )                   Task 1 → Task 0
\    BACKGROUND       ( xt -- )                Start Task 1
\    TASK-STOP        ( -- )                   Cancel Task 1
\    TASK?            ( -- flag )              Task 1 status (0/1)
