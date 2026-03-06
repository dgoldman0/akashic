\ coroutine.f — Structured Wrappers for BIOS Cooperative Multitasking
\
\ The BIOS (Phase 8) exposes a 4-task round-robin cooperative scheduler
\ using SEP R20:
\   Task 0 = R3  (Forth inner interpreter / main application — always active)
\   Task 1 = slot 1  (background helper)
\   Task 2 = slot 2  (background helper)
\   Task 3 = slot 3  (background helper)
\
\ Each background task gets independent data-stack and return-stack
\ regions.  R20 is the dedicated SEP trampoline register (REX-extended,
\ chosen to avoid conflicts with scratch registers).
\
\ Raw BIOS words:
\   PAUSE        ( -- )        Round-robin yield to next active bg task
\   TASK-YIELD   ( -- )        Any bg task yields back to Task 0
\   BACKGROUND   ( xt -- )     Start xt in slot 1
\   BACKGROUND2  ( xt -- )     Start xt in slot 2
\   BACKGROUND3  ( xt -- )     Start xt in slot 3
\   TASK-STOP    ( n -- )      Cancel task in slot n (1–3)
\   TASK?        ( n -- flag ) Is slot n active? (0/1)
\   #TASKS       ( -- n )      Count of active background tasks (0–3)
\
\ CRITICAL: PAUSE and TASK-YIELD are NOT interchangeable.
\   PAUSE (called from Task 0) scans slots 1–3 round-robin, loads the
\   next active task's PC into R20, and executes SEP R20.  When called
\   from inside a background task, R20 IS the live program counter —
\   PAUSE would overwrite it with a stale address → crash.
\   Task 0 code calls PAUSE.  Background task code calls TASK-YIELD.
\
\ This file adds structured wrappers that guarantee cleanup:
\
\   WITH-BACKGROUND  ( xt-bg xt-body -- )
\       Start xt-bg as Task 1, execute xt-body on Task 0, then
\       1 TASK-STOP — even if xt-body THROWs.
\
\   WITH-BG  ( slot xt-bg xt-body -- )
\       Generic: start xt-bg in any slot (1–3), execute xt-body on
\       Task 0, then slot TASK-STOP — even if xt-body THROWs.
\
\   BG-POLL  ( xt -- )
\       Install xt as a polling loop in slot 1.
\
\   BG-POLL-SLOT  ( slot xt -- )
\       Install xt as a polling loop in slot n (1–3).
\
\   BG-ALIVE?  ( n -- flag )
\       Is slot n active?  TRUE (-1) / FALSE (0).
\
\   BG-ANY?  ( -- flag )
\       TRUE if any background task is active.
\
\   BG-WAIT-DONE  ( n -- )
\       Busy-wait until slot n finishes naturally.
\
\   BG-WAIT-ALL  ( -- )
\       Busy-wait until all background tasks finish.
\
\   BG-STOP-ALL  ( -- )
\       Stop all background tasks (slots 1–3).
\
\ Naming note: The BIOS renamed its background yield word from YIELD
\ to TASK-YIELD to avoid collision with KDOS YIELD (marks current
\ task T.DONE).  This library uses PAUSE (round-robin across slots
\ 1–3) and TASK-YIELD (any bg task → Task 0).
\
\ Constraints:
\   - Three background slots (1–3).
\   - Fully cooperative — no preemption.
\   - Micro-cores lack Q flip-flop; EMIT traps there.
\   - All tasks share address space / dictionary.
\
\ Dependencies: none (BIOS words are always available)
\
\ Prefix: BG-  (public API, except WITH-BACKGROUND / WITH-BG)
\         _BG- (internal helpers)
\
\ Load with:   REQUIRE coroutine.f

PROVIDED akashic-coroutine

\ =====================================================================
\  _BG-START — Internal: Start XT in Slot N
\ =====================================================================

\ _BG-START ( xt slot -- )
\   Start xt in background slot n (1–3).  Dispatches to the
\   appropriate BIOS word.

: _BG-START  ( xt slot -- )
    DUP 1 = IF DROP BACKGROUND  EXIT THEN
    DUP 2 = IF DROP BACKGROUND2 EXIT THEN
        3 = IF      BACKGROUND3 EXIT THEN
    -24 THROW ;    \ invalid slot → "invalid numeric argument"

\ =====================================================================
\  BG-ALIVE? — Query Background Task Status
\ =====================================================================

\ BG-ALIVE? ( n -- flag )
\   TRUE (-1) if background task in slot n (1–3) is active.
\   Thin wrapper around TASK? normalised to Forth flag convention.

: BG-ALIVE?  ( n -- flag )
    TASK? 0<> ;

\ =====================================================================
\  BG-ANY? — Any Background Task Active?
\ =====================================================================

\ BG-ANY? ( -- flag )
\   TRUE (-1) if any background task (slots 1–3) is active.

: BG-ANY?  ( -- flag )
    #TASKS 0<> ;

\ =====================================================================
\  WITH-BACKGROUND — Scoped Background Task (Slot 1)
\ =====================================================================

\ WITH-BACKGROUND ( xt-bg xt-body -- )
\   Start xt-bg as Task 1, execute xt-body on Task 0,
\   then unconditionally 1 TASK-STOP.  If xt-body THROWs, the
\   background task is still stopped before the exception propagates.
\
\   xt-bg   must have signature ( -- ).  It runs as Task 1.
\   xt-body must have signature ( -- ).  It runs as Task 0.
\
\   Example:
\     ['] my-poller  ['] my-work  WITH-BACKGROUND
\     \ slot 1 is guaranteed stopped here

: WITH-BACKGROUND  ( xt-bg xt-body -- )
    SWAP BACKGROUND              \ start xt-bg as Task 1
    CATCH                        \ execute xt-body under CATCH
    1 TASK-STOP                  \ unconditional cleanup
    DUP IF THROW THEN            \ re-throw if xt-body failed
    DROP ;                       \ discard 0 (no error)

\ =====================================================================
\  WITH-BG — Scoped Background Task (Any Slot)
\ =====================================================================

\ WITH-BG ( slot xt-bg xt-body -- )
\   Generic scoped execution for any slot (1–3).
\   Start xt-bg in the given slot, execute xt-body on Task 0,
\   then unconditionally TASK-STOP that slot.
\
\   Example:
\     2 ['] my-poller  ['] my-work  WITH-BG
\     \ slot 2 is guaranteed stopped here

: WITH-BG  ( slot xt-bg xt-body -- )
    ROT >R                    \ ( xt-bg xt-body ) R:( slot )
    SWAP R@ _BG-START         \ start xt-bg in slot; ( xt-body ) R:( slot )
    CATCH                     \ execute xt-body under CATCH
    R> TASK-STOP              \ unconditional cleanup
    DUP IF THROW THEN
    DROP ;

\ =====================================================================
\  _BG-POLL-XT — Storage for Polling Loop XTs
\ =====================================================================

\ Three poll-xt slots, one per background task.
VARIABLE _BG-POLL-XT1
VARIABLE _BG-POLL-XT2
VARIABLE _BG-POLL-XT3

\ _BG-POLL-LOOP1 ( -- )  polling loop for slot 1
: _BG-POLL-LOOP1  ( -- )
    BEGIN  _BG-POLL-XT1 @ EXECUTE  TASK-YIELD  AGAIN ;

\ _BG-POLL-LOOP2 ( -- )  polling loop for slot 2
: _BG-POLL-LOOP2  ( -- )
    BEGIN  _BG-POLL-XT2 @ EXECUTE  TASK-YIELD  AGAIN ;

\ _BG-POLL-LOOP3 ( -- )  polling loop for slot 3
: _BG-POLL-LOOP3  ( -- )
    BEGIN  _BG-POLL-XT3 @ EXECUTE  TASK-YIELD  AGAIN ;

\ =====================================================================
\  BG-POLL — Install Polling Background Task (Slot 1)
\ =====================================================================

\ BG-POLL ( xt -- )
\   Install xt as a background polling loop in slot 1.  Each PAUSE
\   from Task 0 gives slot 1 a timeslice to run xt once, then it
\   yields back via TASK-YIELD.
\
\   Returns immediately.  Use 1 TASK-STOP to cancel.
\
\   Example:
\     ['] my-nic-poll BG-POLL
\     ... do work, calling PAUSE periodically ...
\     1 TASK-STOP

: BG-POLL  ( xt -- )
    _BG-POLL-XT1 !
    ['] _BG-POLL-LOOP1 BACKGROUND ;

\ =====================================================================
\  BG-POLL-SLOT — Install Polling Background Task (Any Slot)
\ =====================================================================

\ BG-POLL-SLOT ( slot xt -- )
\   Install xt as a background polling loop in slot n (1–3).
\
\   Example:
\     2 ['] my-nic-poll BG-POLL-SLOT
\     ... do work ...
\     2 TASK-STOP

: BG-POLL-SLOT  ( slot xt -- )
    OVER 1 = IF _BG-POLL-XT1 ! DROP ['] _BG-POLL-LOOP1 BACKGROUND  EXIT THEN
    OVER 2 = IF _BG-POLL-XT2 ! DROP ['] _BG-POLL-LOOP2 BACKGROUND2 EXIT THEN
    OVER 3 = IF _BG-POLL-XT3 ! DROP ['] _BG-POLL-LOOP3 BACKGROUND3 EXIT THEN
    2DROP -24 THROW ;

\ =====================================================================
\  BG-WAIT-DONE — Wait for One-Shot Background Task to Finish
\ =====================================================================

\ BG-WAIT-DONE ( n -- )
\   Spin-wait (calling PAUSE each iteration) until slot n finishes
\   naturally (its xt returns → task_cleanup fires → TASK? returns 0).
\
\   Only useful for one-shot tasks.  For infinite-loop tasks
\   (BG-POLL), this would spin forever — use n TASK-STOP instead.
\
\   Example:
\     ['] my-hash BACKGROUND
\     ... do other work, calling PAUSE ...
\     1 BG-WAIT-DONE
\     \ hash is now ready

: BG-WAIT-DONE  ( n -- )
    BEGIN  DUP BG-ALIVE?  WHILE  PAUSE  REPEAT  DROP ;

\ =====================================================================
\  BG-WAIT-ALL — Wait for All Background Tasks to Finish
\ =====================================================================

\ BG-WAIT-ALL ( -- )
\   Spin-wait until all background tasks finish naturally.
\   Only useful when all running tasks are one-shot.

: BG-WAIT-ALL  ( -- )
    BEGIN  BG-ANY?  WHILE  PAUSE  REPEAT ;

\ =====================================================================
\  BG-STOP-ALL — Stop All Background Tasks
\ =====================================================================

\ BG-STOP-ALL ( -- )
\   Unconditionally stop all background tasks in slots 1–3.

: BG-STOP-ALL  ( -- )
    1 TASK-STOP  2 TASK-STOP  3 TASK-STOP ;

\ =====================================================================
\  BG-INFO — Debug Display
\ =====================================================================

\ BG-INFO ( -- )
\   Print background task status for all slots.

: BG-INFO  ( -- )
    ." [coroutine"
    4 1 DO
        SPACE I 48 + EMIT  ." ="
        I TASK? IF ." ON" ELSE ." --" THEN
    LOOP
    ."  n=" #TASKS 48 + EMIT
    ." ]" CR ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  BG-ALIVE?         ( n -- flag )            Is slot n active?
\  BG-ANY?           ( -- flag )              Any bg task active?
\  WITH-BACKGROUND   ( xt-bg xt-body -- )     Scoped bg in slot 1
\  WITH-BG           ( slot xt-bg xt-body -- ) Scoped bg in any slot
\  BG-POLL           ( xt -- )                Install poll loop (slot 1)
\  BG-POLL-SLOT      ( slot xt -- )           Install poll loop (any slot)
\  BG-WAIT-DONE      ( n -- )                 Wait for slot n to finish
\  BG-WAIT-ALL       ( -- )                   Wait for all bg tasks
\  BG-STOP-ALL       ( -- )                   Stop all bg tasks
\  BG-INFO           ( -- )                   Debug display
\
\  Raw BIOS (always available, no REQUIRE needed):
\    PAUSE            ( -- )                   Round-robin yield to next bg task
\    TASK-YIELD       ( -- )                   Any bg task → Task 0
\    BACKGROUND       ( xt -- )                Start xt in slot 1
\    BACKGROUND2      ( xt -- )                Start xt in slot 2
\    BACKGROUND3      ( xt -- )                Start xt in slot 3
\    TASK-STOP        ( n -- )                 Cancel slot n (1–3)
\    TASK?            ( n -- flag )            Is slot n active? (0/1)
\    #TASKS           ( -- n )                 Count active bg tasks
