\ scope.f — Structured Concurrency / Task Groups for KDOS / Megapad-64
\
\ Task groups enforce parent-waits-for-children semantics.
\ Every spawned task belongs to a group, and the group ensures no
\ orphaned tasks — the parent blocks in TG-WAIT until all children
\ finish, or cancels them with TG-CANCEL.
\
\ A task group is a lightweight descriptor (5 logical cells) with
\ an embedded event for completion notification.  Tasks spawned
\ into a group via TG-SPAWN are wrapped by _TG-RUNNER, which
\ decrements the active count on completion and signals the
\ done-event when the last task finishes.
\
\ Error handling: if a spawned task's xt THROWs, the error code
\ is captured (first error wins) in the group's error field.  The
\ task still counts as "done" for active-count purposes.
\
\ WITH-TASKS provides Structured Concurrency:
\   Creates an anonymous group, sets THIS-GROUP, runs user code
\   (which spawns children via THIS-GROUP @), then TG-WAITs.
\   No child can outlive the WITH-TASKS block.
\
\ Binding table: like future.f's ASYNC, TG-SPAWN uses a FIFO
\ table of (xt, tg) pairs so the generic _TG-RUNNER reads its
\ binding at execution time.  Cooperative scheduling guarantees
\ writes complete before runners execute.
\
\ Data structure — Task Group:
\
\   Logical descriptor: 5 cells (40 bytes)
\     +0   active       Count of live tasks in this group
\     +8   cancelled    0 = normal, -1 = cancelled
\     +16  done-event   Pointer to embedded event (at +40)
\     +24  error        First error code (0 = no error)
\     +32  name         Pointer to name string (0 = anonymous)
\
\   Physical allocation: 9 cells (72 bytes)
\     +40  [event flag]        Embedded event — 4 cells
\     +48  [event wait-count]
\     +56  [event waiter-0]
\     +64  [event waiter-1]
\
\ Dependencies: event.f (for EVT-SET, EVT-WAIT, EVT-LOCK)
\               §8 scheduler (SPAWN, SCHEDULE, TASK-COUNT)
\
\ Prefix: TG-  (public API)
\         _TG- (internal helpers)
\
\ Load with:   REQUIRE scope.f

REQUIRE ../concurrency/event.f

PROVIDED akashic-scope

\ =====================================================================
\  Constants
\ =====================================================================

72 CONSTANT _TG-SIZE               \ total bytes per task group

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _TG-ACTIVE    ( tg -- addr )             ; \ +0  active count
: _TG-CANCELLED ( tg -- addr )   8 + ;      \ +8  cancelled flag
: _TG-EVT       ( tg -- ev )    16 + @ ;    \ +16 → event address
: _TG-ERROR     ( tg -- addr )  24 + ;      \ +24 error code
: _TG-NAME      ( tg -- addr )  32 + ;      \ +32 name pointer

\ =====================================================================
\  Internal — Allocate Task Group
\ =====================================================================

\ _TG-ALLOC ( -- tg )
\   Allocate a fresh task group from the dictionary (HERE).
\   Returns the address of the 72-byte descriptor.  The done-event
\   pointer at +16 points to the inline event at +40.

: _TG-ALLOC  ( -- tg )
    HERE >R
    0 ,              \ +0  active = 0
    0 ,              \ +8  cancelled = 0
    R@ 40 + ,        \ +16 done-event → +40
    0 ,              \ +24 error = 0
    0 ,              \ +32 name = 0 (anonymous)
    \ Inline event (4 cells = 32 bytes, initially unset)
    0 ,              \ +40 event flag = 0
    0 ,              \ +48 event wait-count = 0
    0 ,              \ +56 event waiter-0 = none
    0 ,              \ +64 event waiter-1 = none
    R> ;

\ =====================================================================
\  TASK-GROUP — Define a Named Task Group
\ =====================================================================

\ TASK-GROUP ( "name" -- )
\   Create a named task group constant.  Allocates 72 bytes
\   (9 cells) and defines a constant pointing to the descriptor.
\
\   Example:   TASK-GROUP my-workers
\              ['] my-job my-workers TG-SPAWN

: TASK-GROUP  ( "name" -- )
    _TG-ALLOC CONSTANT ;

\ =====================================================================
\  Query
\ =====================================================================

\ TG-COUNT ( tg -- n )
\   Number of active (not yet completed) tasks in the group.

: TG-COUNT  ( tg -- n )
    @ ;

\ TG-CANCELLED? ( tg -- flag )
\   TRUE (-1) if the group has been cancelled, FALSE (0) otherwise.

: TG-CANCELLED?  ( tg -- flag )
    _TG-CANCELLED @ 0<> ;

\ TG-ERROR ( tg -- n )
\   First error code thrown by a task in this group.
\   Returns 0 if no task has thrown.

: TG-ERROR  ( tg -- n )
    _TG-ERROR @ ;

\ =====================================================================
\  Binding FIFO — (xt, tg) pairs for TG-SPAWN / _TG-RUNNER
\ =====================================================================
\
\ Same pattern as future.f's ASYNC binding table.  TG-SPAWN writes
\ (xt, tg) at the write index; _TG-RUNNER reads at the read index.
\ Cooperative scheduling guarantees all writes complete before any
\ runner executes, preserving FIFO order.

CREATE _TG-XTS   8 CELLS ALLOT    \ xt per pending TG-SPAWN
CREATE _TG-TGS   8 CELLS ALLOT    \ tg per pending TG-SPAWN

VARIABLE _TG-WIDX                  \ write index (next TG-SPAWN)
VARIABLE _TG-RIDX                  \ read index (next _TG-RUNNER)
0 _TG-WIDX !
0 _TG-RIDX !

\ Per-runner state variables (used instead of R-stack to avoid
\ the R@ inside DO..LOOP gotcha and keep stack discipline clear).
VARIABLE _TG-RUN-XT               \ current runner's xt
VARIABLE _TG-RUN-TG               \ current runner's task group

\ =====================================================================
\  Internal — Task Completion Bookkeeping
\ =====================================================================

\ _TG-DONE ( tg -- )
\   Decrement the group's active count under EVT-LOCK.  If it
\   reaches zero, signal the done-event to unblock TG-WAIT.

: _TG-DONE  ( tg -- )
    EVT-LOCK LOCK
    DUP @ 1-                       \ ( tg new-active )
    DUP 2 PICK !                   \ store new-active at tg+0
    EVT-LOCK UNLOCK
    0= IF  16 + @ EVT-SET          \ last task: signal done-event
    ELSE  DROP  THEN ;

\ =====================================================================
\  Internal — Generic Task Runner
\ =====================================================================

\ _TG-RUNNER ( -- )
\   Generic task body for all TG-SPAWN'd tasks.  Reads its
\   (xt, tg) binding from the FIFO, executes the xt under CATCH,
\   stores any error, and calls _TG-DONE.
\
\   The user's xt must have signature ( -- ).  Any THROW is caught
\   and stored as the group's error (first error wins).

: _TG-RUNNER  ( -- )
    \ Read binding from FIFO (under lock)
    EVT-LOCK LOCK
    _TG-RIDX @ DUP
    CELLS _TG-XTS + @  _TG-RUN-XT !
    CELLS _TG-TGS + @  _TG-RUN-TG !
    _TG-RIDX @ 1+ 7 AND _TG-RIDX !
    EVT-LOCK UNLOCK
    \ Execute user xt with error handling
    _TG-RUN-XT @ CATCH               \ ( 0 | error-code )
    DUP IF
        \ Store first error in group
        _TG-RUN-TG @ _TG-ERROR @ 0= IF
            _TG-RUN-TG @ _TG-ERROR !
        ELSE  DROP  THEN
    ELSE  DROP  THEN
    \ Decrement active count, signal if last
    _TG-RUN-TG @ _TG-DONE ;

\ =====================================================================
\  TG-SPAWN — Spawn Task into Group
\ =====================================================================

\ TG-SPAWN ( xt tg -- )
\   Spawn a task into the given task group.  Increments the
\   group's active count, stores (xt, tg) in the binding FIFO,
\   and SPAWNs a _TG-RUNNER.
\
\   If the group is cancelled, TG-SPAWN is a no-op (xt is not run).
\   If all 8 KDOS task slots are full, the spawn is silently dropped.
\
\   The user's xt must have signature ( -- ).  Side effects
\   should be communicated through shared variables, not the
\   data stack.
\
\   Example:
\     ['] compute-hash my-group TG-SPAWN
\     ['] fetch-data   my-group TG-SPAWN
\     my-group TG-WAIT

: TG-SPAWN  ( xt tg -- )
    \ Refuse if group is cancelled
    DUP _TG-CANCELLED @ IF  2DROP EXIT  THEN
    \ Refuse if no task slots available
    TASK-COUNT @ 8 < 0= IF  2DROP EXIT  THEN
    \ Increment active count and store binding (under lock)
    EVT-LOCK LOCK
    DUP @ 1+ OVER !                   \ active++
    _TG-WIDX @ >R
    SWAP R@ CELLS _TG-XTS + !         \ store xt at FIFO[widx]
    R@ CELLS _TG-TGS + !              \ store tg at FIFO[widx]
    R> 1+ 7 AND _TG-WIDX !            \ advance write index
    EVT-LOCK UNLOCK
    \ Spawn the runner task
    ['] _TG-RUNNER SPAWN ;

\ =====================================================================
\  TG-WAIT — Wait for All Tasks in Group
\ =====================================================================

\ TG-WAIT ( tg -- )
\   Block until all tasks in the group have completed.
\   Calls SCHEDULE first to ensure spawned tasks get CPU time
\   (essential on single-core where tasks run cooperatively).
\
\   Flow:
\     1. Fast path: if active count is already 0, return.
\     2. Call SCHEDULE to run all READY tasks.
\     3. If active count is now 0 (all tasks completed
\        during SCHEDULE), return.
\     4. Otherwise, EVT-WAIT on the done-event (multicore path).
\
\   Example:   my-group TG-WAIT

: TG-WAIT  ( tg -- )
    DUP @ 0= IF  DROP EXIT  THEN     \ fast path: no active tasks
    SCHEDULE                           \ run ready tasks
    DUP @ 0= IF  DROP EXIT  THEN     \ all done after schedule?
    16 + @ EVT-WAIT ;                  \ still active: wait on event

\ =====================================================================
\  TG-CANCEL — Cancel Group
\ =====================================================================

\ TG-CANCEL ( tg -- )
\   Mark the group as cancelled and signal the done-event.
\   Prevents new tasks from being spawned into the group
\   (TG-SPAWN checks the cancelled flag).
\
\   On the cooperative scheduler, already-running tasks cannot be
\   preempted.  Tasks that check TG-CANCELLED? in their body can
\   exit early.  The done-event is signaled to unblock any TG-WAIT.
\
\   Idempotent: calling TG-CANCEL twice is harmless.
\
\   Example:   my-group TG-CANCEL

: TG-CANCEL  ( tg -- )
    DUP _TG-CANCELLED @ IF  DROP EXIT  THEN   \ already cancelled
    -1 OVER _TG-CANCELLED !                    \ set cancelled flag
    DUP @ 0= IF  DROP EXIT  THEN              \ no active tasks
    16 + @ EVT-SET ;                            \ unblock TG-WAIT

\ =====================================================================
\  TG-ANY — Wait for Any, Cancel Rest
\ =====================================================================

\ TG-ANY ( tg -- )
\   Run spawned tasks via SCHEDULE, then cancel the group.
\
\   On the cooperative single-core scheduler, SCHEDULE runs all
\   ready tasks to completion, so TG-ANY is effectively
\   SCHEDULE + TG-CANCEL.  On multicore (future enhancement),
\   this will be refined to return after the first task completes.
\
\   Example:   my-group TG-ANY

: TG-ANY  ( tg -- )
    DUP @ 0= IF  DROP EXIT  THEN
    SCHEDULE
    TG-CANCEL ;

\ =====================================================================
\  THIS-GROUP — Current Task Group Variable
\ =====================================================================

\ THIS-GROUP holds the address of the current task group set by
\ WITH-TASKS.  User code reads it with THIS-GROUP @ to get the
\ active group for TG-SPAWN calls.
\
\ Outside of WITH-TASKS, THIS-GROUP is 0 (no active group).

VARIABLE THIS-GROUP
0 THIS-GROUP !

\ =====================================================================
\  WITH-TASKS — Structured Concurrency Block
\ =====================================================================

\ WITH-TASKS ( xt -- )
\   Create an anonymous task group, set THIS-GROUP, execute xt
\   (which spawns children via THIS-GROUP @), then TG-WAIT.
\   No child task can outlive the WITH-TASKS block.
\
\   THIS-GROUP is saved/restored on the return stack for nesting.
\
\   Since this Forth lacks anonymous closures [: ;], the xt
\   must be a named word that reads THIS-GROUP @:
\
\     : spawn-all
\       ['] worker-a THIS-GROUP @ TG-SPAWN
\       ['] worker-b THIS-GROUP @ TG-SPAWN ;
\     ['] spawn-all WITH-TASKS
\
\   Nesting is supported:
\     : inner  ['] sub-task THIS-GROUP @ TG-SPAWN ;
\     : outer
\       ['] main-task THIS-GROUP @ TG-SPAWN
\       ['] inner WITH-TASKS ;
\     ['] outer WITH-TASKS

: WITH-TASKS  ( xt -- )
    _TG-ALLOC                         \ ( xt tg )
    THIS-GROUP @ >R                   \ save old group  R: ( old-tg )
    DUP THIS-GROUP !                  \ THIS-GROUP = tg  ( xt tg )
    >R                                \ ( xt )  R: ( old-tg tg )
    EXECUTE                           \ run user xt ( -- )
    R>                                \ ( tg )  R: ( old-tg )
    R>                                \ ( tg old-tg )
    THIS-GROUP !                      \ restore THIS-GROUP  ( tg )
    TG-WAIT ;                         \ wait for all children

\ =====================================================================
\  TG-RESET — Reset Group for Reuse
\ =====================================================================

\ TG-RESET ( tg -- )
\   Zero all fields and restore the done-event pointer.
\   Intended for testing and group recycling.
\
\   Do NOT call on a group with active tasks or pending TG-WAITs.

: TG-RESET  ( tg -- )
    DUP _TG-SIZE 0 FILL               \ zero everything
    DUP 40 + OVER 16 + !              \ restore done-event → +40
    DROP ;

\ =====================================================================
\  TG-INFO — Debug Display
\ =====================================================================

\ TG-INFO ( tg -- )
\   Print task group status for debugging.

: TG-INFO  ( tg -- )
    ." [group"
    ."  active=" DUP @ .
    ."  cancelled=" DUP _TG-CANCELLED @ .
    ."  error=" DUP _TG-ERROR @ .
    ." ]" CR DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  TASK-GROUP     ( "name" -- )         Define named task group
\  TG-SPAWN       ( xt tg -- )         Spawn task into group
\  TG-WAIT        ( tg -- )            Wait for all tasks to complete
\  TG-CANCEL      ( tg -- )            Cancel group, unblock TG-WAIT
\  TG-ANY         ( tg -- )            Wait for any, cancel rest
\  TG-COUNT       ( tg -- n )          Active task count
\  TG-CANCELLED?  ( tg -- flag )       Is group cancelled?
\  TG-ERROR       ( tg -- n )          First error code (0 = none)
\  WITH-TASKS     ( xt -- )            Structured concurrency block
\  THIS-GROUP     ( -- addr )          VARIABLE: current group
\  TG-RESET       ( tg -- )            Reset for reuse (testing)
\  TG-INFO        ( tg -- )            Debug display
