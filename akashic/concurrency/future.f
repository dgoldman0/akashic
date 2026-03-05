\ future.f — Promises and ASYNC/AWAIT for KDOS / Megapad-64
\
\ Futures and promises for asynchronous result passing.  ASYNC
\ spawns a task and returns a promise.  AWAIT blocks until the
\ promise is fulfilled and returns the result value.
\
\ A promise is a one-shot write-once cell: FULFILL stores a value
\ and signals an embedded event; AWAIT checks the resolved flag
\ and either returns immediately (fast path) or waits on the event.
\
\ Data structure — 6 cells = 48 bytes:
\   +0   value       result (valid after FULFILL)          (1 cell)
\   +8   resolved    0 = pending, -1 = resolved            (1 cell)
\   +16  event       embedded event (4 cells = 32 B)       (+16..+40)
\
\ ASYNC binding:
\   ASYNC stores (xt, promise) in a FIFO binding table before
\   spawning a generic _FUT-RUNNER task.  The runner reads the
\   next binding, executes the xt, and fulfills the promise with
\   the result.  FIFO ordering is guaranteed by cooperative
\   scheduling — all ASYNC calls complete before any runner
\   executes (SPAWN marks READY; execution waits for SCHEDULE).
\
\ REQUIRE event.f
\
\ Prefix: FUT-  (public API)
\         _FUT- (internal helpers)
\
\ Load with:   REQUIRE future.f

REQUIRE ../concurrency/event.f

PROVIDED akashic-future

\ =====================================================================
\  Constants
\ =====================================================================

6 CONSTANT _FUT-PCELLS             \ cells per promise descriptor
48 CONSTANT _FUT-PBYTES            \ bytes per promise (6 × 8)
8 CONSTANT _FUT-BIND-CAP           \ ASYNC binding table capacity

\ =====================================================================
\  Field Accessors
\ =====================================================================

: _FUT-VALUE    ( p -- addr )   ;          \ +0  result value
: _FUT-RESOLVED ( p -- addr )   8 + ;      \ +8  resolved flag
: _FUT-EVT      ( p -- ev )     16 + ;     \ +16 embedded event (32 B)

\ =====================================================================
\  PROMISE — Allocate a Promise
\ =====================================================================

\ PROMISE ( -- addr )
\   Allocate a fresh promise from the dictionary (HERE).  Returns
\   the address of the 48-byte descriptor.  The promise starts in
\   the PENDING state (resolved = 0, embedded event unset).
\
\   Each call advances the dictionary pointer by 48 bytes.
\   For long-running systems, recycle with FUT-RESET.
\
\   Example:   PROMISE   ( -- p )
\              42 SWAP FULFILL

: PROMISE  ( -- addr )
    HERE
    0 ,              \ +0  value = 0
    0 ,              \ +8  resolved = 0 (pending)
    \ Embedded event (4 cells, initially unset)
    0 ,              \ +16 event flag = 0 (unset)
    0 ,              \ +24 event wait-count = 0
    0 ,              \ +32 event waiter-0 = none
    0 ,              \ +40 event waiter-1 = none
;

\ =====================================================================
\  Query
\ =====================================================================

\ RESOLVED? ( p -- flag )
\   Return TRUE (-1) if the promise has been fulfilled, FALSE (0)
\   if still pending.  Lock-free read — single aligned 64-bit cell.

: RESOLVED?  ( p -- flag )
    _FUT-RESOLVED @ 0<> ;

\ =====================================================================
\  FULFILL — Write Result to Promise
\ =====================================================================

\ FULFILL ( val p -- )
\   Store `val` as the promise's result, mark it as resolved, and
\   signal the embedded event to wake all AWAITing tasks.
\
\   THROWs -1 if the promise has already been fulfilled (one-shot
\   semantics: a promise can only be fulfilled once).
\
\   Safe to call from any core.
\
\   Example:   42 my-promise FULFILL

: FULFILL  ( val p -- )
    DUP RESOLVED? IF  2DROP -1 THROW  THEN   \ double fulfill
    EVT-LOCK LOCK
    >R
    R@ !                            \ store val at +0 (value)
    -1 R@ _FUT-RESOLVED !           \ mark resolved
    EVT-LOCK UNLOCK
    R> _FUT-EVT EVT-SET ;           \ wake all waiters

\ =====================================================================
\  AWAIT — Block Until Fulfilled
\ =====================================================================

\ AWAIT ( p -- val )
\   If the promise is already resolved, return the value immediately
\   (fast path).  Otherwise, block via EVT-WAIT on the embedded
\   event until another task calls FULFILL, then return the value.
\
\   On single-core without preemption, EVT-WAIT spins with YIELD?,
\   which requires preemption or an ISR to break the loop.  On
\   multicore, another core fulfills the promise via shared memory.
\
\   Example:   my-promise AWAIT .

: AWAIT  ( p -- val )
    DUP RESOLVED? IF  @ EXIT  THEN  \ fast path: already resolved
    DUP _FUT-EVT EVT-WAIT           \ block until signaled
    @ ;                              \ read value

\ =====================================================================
\  AWAIT-TIMEOUT — Block with Timeout
\ =====================================================================

\ AWAIT-TIMEOUT ( p ms -- val flag )
\   Wait up to `ms` milliseconds for the promise to be fulfilled.
\   Returns ( val TRUE ) if resolved within the timeout, or
\   ( 0 FALSE ) if the timeout expired.
\
\   Example:   p 5000 AWAIT-TIMEOUT IF . ELSE ." timeout" THEN

: AWAIT-TIMEOUT  ( p ms -- val flag )
    OVER RESOLVED? IF              \ fast path: already resolved
        DROP @ -1 EXIT
    THEN
    OVER _FUT-EVT SWAP             \ ( p ev ms )
    EVT-WAIT-TIMEOUT               \ ( p flag )
    IF    @ -1                     \ resolved: ( val TRUE )
    ELSE  DROP 0 0                 \ timed out: ( 0 FALSE )
    THEN ;

\ =====================================================================
\  FUT-RESET — Re-Use a Promise
\ =====================================================================

\ FUT-RESET ( p -- )
\   Reset a promise back to the PENDING state.  Zeroes all fields
\   including the embedded event.  Intended for testing and promise
\   recycling.  Do NOT call on a promise that has active AWAITers.

: FUT-RESET  ( p -- )
    _FUT-PBYTES 0 FILL ;

\ =====================================================================
\  ASYNC — Spawn Task, Return Promise
\ =====================================================================

\ ASYNC binding table — FIFO queue of (xt, promise) pairs.
\ ASYNC writes at _FUT-AWIDX, _FUT-RUNNER reads at _FUT-ARIDX.
\ Cooperative scheduling guarantees all writes complete before any
\ runner executes, preserving FIFO order.

CREATE _FUT-ASYNC-XTS    8 CELLS ALLOT   \ xt per pending ASYNC
CREATE _FUT-ASYNC-PROMS  8 CELLS ALLOT   \ promise per pending ASYNC
VARIABLE _FUT-AWIDX                       \ write index (next ASYNC)
VARIABLE _FUT-ARIDX                       \ read index (next RUNNER)
0 _FUT-AWIDX !
0 _FUT-ARIDX !

\ _FUT-RUNNER ( -- )
\   Generic task body for all ASYNC-spawned tasks.  Reads its
\   (xt, promise) binding from the FIFO table, executes the xt
\   (which must leave exactly one value on the data stack), and
\   fulfills the promise with that value.
\
\   If the xt THROWs, the task dies and the promise remains
\   pending.  Callers should use AWAIT-TIMEOUT to avoid hangs,
\   or wrap their xt in CATCH if error handling is needed.

: _FUT-RUNNER  ( -- )
    EVT-LOCK LOCK
    _FUT-ARIDX @ DUP                   \ ( ridx ridx )
    CELLS _FUT-ASYNC-XTS + @           \ ( ridx xt )
    SWAP CELLS _FUT-ASYNC-PROMS + @    \ ( xt promise )
    _FUT-ARIDX @ 1+ 7 AND _FUT-ARIDX !  \ advance read index
    EVT-LOCK UNLOCK
    >R EXECUTE R>                       \ ( result promise )
    FULFILL ;                           \ fulfill with result

\ ASYNC ( xt -- promise )
\   Allocate a fresh promise, store (xt, promise) in the binding
\   table, and SPAWN a _FUT-RUNNER task.  Returns the promise
\   immediately.
\
\   The spawned task will execute `xt` (which must leave exactly
\   one value on the data stack) and FULFILL the promise with
\   that value.
\
\   The promise can be AWAITed immediately — if the task hasn't
\   run yet, AWAIT will block until it does.
\
\   Example:
\     ['] compute-hash ASYNC   ( -- p )
\     p AWAIT .                 ( -- )
\
\   Parallel pattern:
\     ['] compute-hash ASYNC
\     ['] fetch-data   ASYNC
\     SWAP AWAIT  SWAP AWAIT
\     combine-results

: ASYNC  ( xt -- promise )
    PROMISE >R                          \ allocate promise
    EVT-LOCK LOCK
    _FUT-AWIDX @ CELLS _FUT-ASYNC-XTS + !      \ store xt
    R@ _FUT-AWIDX @ CELLS _FUT-ASYNC-PROMS + !  \ store promise
    _FUT-AWIDX @ 1+ 7 AND _FUT-AWIDX !          \ advance write idx
    EVT-LOCK UNLOCK
    ['] _FUT-RUNNER SPAWN               \ spawn the runner
    R> ;                                \ return promise

\ =====================================================================
\  FUT-INFO — Debug Display
\ =====================================================================

\ FUT-INFO ( p -- )
\   Print promise status for debugging.

: FUT-INFO  ( p -- )
    ." [future"
    DUP RESOLVED? IF
        ."  RESOLVED val=" DUP @ .
    ELSE
        ."  PENDING"
    THEN
    ."  evt:" DUP _FUT-EVT EVT-INFO
    ." ]" CR
    DROP ;

\ =====================================================================
\  Quick Reference
\ =====================================================================
\
\  PROMISE        ( -- addr )            Allocate a pending promise
\  RESOLVED?      ( p -- flag )          Is promise fulfilled?
\  FULFILL        ( val p -- )           Store result, wake waiters
\  AWAIT          ( p -- val )           Block until fulfilled
\  AWAIT-TIMEOUT  ( p ms -- val flag )   Await with timeout
\  ASYNC          ( xt -- promise )      Spawn task → promise
\  FUT-RESET      ( p -- )              Reset to PENDING (testing)
\  FUT-INFO       ( p -- )              Debug display
