# akashic-future — Promises and ASYNC/AWAIT for KDOS / Megapad-64

Futures and promises for asynchronous result passing.  `ASYNC`
spawns a task and returns a promise.  `AWAIT` blocks until the
promise is fulfilled and returns the result.

```forth
REQUIRE future.f
```

`PROVIDED akashic-future` — safe to include multiple times.
Automatically requires `event.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creating Promises](#creating-promises)
- [Fulfilling a Promise](#fulfilling-a-promise)
- [Awaiting a Result](#awaiting-a-result)
- [Timeout](#timeout)
- [ASYNC — Spawn + Promise](#async--spawn--promise)
- [Recycling Promises](#recycling-promises)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **One-shot write** | A promise can be fulfilled exactly once. Double-fulfill THROWs `-1`. |
| **Embedded event** | Each promise contains an inline 4-cell EVENT for blocking/wakeup. |
| **Lock-free reads** | `RESOLVED?` and `AWAIT` (fast path) read single aligned 64-bit cells. |
| **Spinlock-protected writes** | `FULFILL` holds `EVT-LOCK` (spinlock 6) during the value + resolved mutation. |
| **Dictionary allocation** | `PROMISE` allocates from HERE — simple, no pool management needed. |
| **FIFO binding table** | `ASYNC` stores (xt, promise) in a circular table; cooperative scheduling guarantees FIFO consumption. |
| **Prefix convention** | Public: `FUT-` and bare names (`PROMISE`, `FULFILL`, `AWAIT`, `ASYNC`). Internal: `_FUT-`. |

---

## Memory Layout

A promise occupies 6 cells = 48 bytes:

```
Offset  Size    Field
──────  ──────  ──────────────────────────
0       8       value       result (valid after FULFILL)
8       8       resolved    0 = pending, -1 = resolved
16      32      event       embedded EVENT (4-cell, initially unset)
```

The embedded event follows the standard `EVENT` layout:

```
+16     8       flag        0 = unset, -1 = set
+24     8       wait-count  tasks waiting on this promise
+32     8       waiter-0    task descriptor slot 0
+40     8       waiter-1    task descriptor slot 1
```

---

## Creating Promises

### `PROMISE`

```forth
PROMISE ( -- addr )
```

Allocate a fresh promise from the dictionary (HERE).  Returns the
address of the 48-byte descriptor.  The promise starts in PENDING
state — `resolved` = 0, embedded event unset.

Each call advances the dictionary pointer by 48 bytes.

```forth
PROMISE            ( -- p )
PROMISE CONSTANT my-result   \ named promise
```

---

## Fulfilling a Promise

### `FULFILL`

```forth
FULFILL ( val p -- )
```

Store `val` as the promise's result, mark it as resolved, and
signal the embedded event to wake all AWAITing tasks.

**One-shot semantics:** THROWs `-1` if the promise has already been
fulfilled.  A promise can only be fulfilled once.

Safe to call from any core.

```forth
42 my-result FULFILL        \ resolve with 42
```

### `RESOLVED?`

```forth
RESOLVED? ( p -- flag )
```

TRUE (−1) if the promise has been fulfilled, FALSE (0) if pending.
Lock-free single-cell read.

```forth
my-result RESOLVED? IF ." done" CR THEN
```

---

## Awaiting a Result

### `AWAIT`

```forth
AWAIT ( p -- val )
```

If the promise is already resolved, return the value immediately
(fast path — no locking, no event interaction).

Otherwise, block via `EVT-WAIT` on the embedded event until another
task calls `FULFILL`, then return the value.

```forth
my-result AWAIT .           \ print the result
```

**Single-core note:** `EVT-WAIT` spins with `YIELD?`.  On single
core without preemption, this requires an ISR or another core to
call `FULFILL`.  On multicore, another core fulfills via shared
memory.

---

## Timeout

### `AWAIT-TIMEOUT`

```forth
AWAIT-TIMEOUT ( p ms -- val flag )
```

Wait up to `ms` milliseconds for the promise to be fulfilled.
Returns `( val TRUE )` if resolved within the timeout, or
`( 0 FALSE )` if the timeout expired.

```forth
my-result 5000 AWAIT-TIMEOUT IF
    ." result: " .
ELSE
    ." timeout!" CR
THEN
```

---

## ASYNC — Spawn + Promise

### `ASYNC`

```forth
ASYNC ( xt -- promise )
```

Allocate a fresh promise, spawn a task that will execute `xt`, and
return the promise immediately.  The spawned task executes `xt`
(which must leave exactly **one value** on the data stack) and
fulfills the promise with that value.

The promise can be AWAITed immediately — if the task hasn't run
yet, `AWAIT` will block until it does.

```forth
: compute-hash  data-buf hash-algorithm run-hash ;

['] compute-hash ASYNC   ( -- p )
p AWAIT .                 ( -- )
```

### Parallel Pattern

```forth
['] compute-hash ASYNC          ( -- p1 )
['] fetch-data   ASYNC          ( -- p1 p2 )
SWAP AWAIT                      ( -- p2 hash )
SWAP AWAIT                      ( -- hash data )
combine-results
```

### How ASYNC Works

1. `PROMISE` allocates a 48-byte descriptor from HERE.
2. The (xt, promise) pair is stored in an internal FIFO binding
   table (8 slots, circular).
3. `SPAWN` creates a READY task running `_FUT-RUNNER`.
4. When `SCHEDULE` (or preemptive scheduling) runs the task,
   `_FUT-RUNNER` reads its binding from the FIFO, executes the
   xt, and calls `FULFILL` with the result.

**FIFO ordering guarantee:** cooperative scheduling ensures all
`ASYNC` calls complete (storing bindings) before any `_FUT-RUNNER`
task executes (reading bindings).  The round-robin scheduler
processes spawned tasks in creation order.

### Error Handling

If the xt THROWs, the spawned task dies and the promise remains
PENDING.  Use `AWAIT-TIMEOUT` to avoid hangs, or wrap the xt
in `CATCH`:

```forth
: safe-compute
    ['] compute-hash CATCH IF
        0                       \ fallback value on error
    THEN ;

['] safe-compute ASYNC SCHEDULE AWAIT .
```

---

## Recycling Promises

### `FUT-RESET`

```forth
FUT-RESET ( p -- )
```

Reset a promise back to PENDING state.  Zeroes all 48 bytes
including the embedded event.  Intended for testing and promise
recycling.

**Warning:** Do NOT call on a promise that has active AWAITers.

```forth
42 my-result FULFILL
my-result AWAIT DROP          \ consume result
my-result FUT-RESET           \ reuse the promise
99 my-result FULFILL          \ fulfill again
```

---

## Debug

### `FUT-INFO`

```forth
FUT-INFO ( p -- )
```

Print promise status to UART:

```
[future PENDING evt:[event UNSET waiters=0]
]
```

```
[future RESOLVED val=42 evt:[event SET waiters=0]
]
```

---

## Concurrency Model

### Manual Fulfill (Primary Pattern)

```forth
PROMISE CONSTANT result

\ On core 0:
result AWAIT .              \ blocks until fulfilled

\ On core 1 (via CORE-RUN or SPAWN-ON):
expensive-computation result FULFILL
```

### ASYNC + SCHEDULE (Cooperative)

```forth
: work-a  compute-part-a ;
: work-b  compute-part-b ;

: main
    ['] work-a ASYNC
    ['] work-b ASYNC
    SCHEDULE                \ run both tasks
    SWAP AWAIT              \ get result A
    SWAP AWAIT              \ get result B
    combine ;
```

### ASYNC + Multicore

```forth
: main
    ['] work-a ASYNC        \ creates READY task
    ['] work-b ASYNC        \ creates READY task
    \ Dispatch to secondary cores
    SCHED-ALL               \ or SCHED-BALANCED
    \ Await results on core 0
    SWAP AWAIT SWAP AWAIT
    combine ;
```

### Implementation Notes

- **FULFILL atomicity:** The value write and resolved-flag write
  are protected by `EVT-LOCK` (spinlock 6).  The event signal
  (`EVT-SET`) happens after the lock is released, ensuring
  AWAITers see a consistent state.

- **AWAIT fast path:** `RESOLVED?` is a lock-free single-cell
  read.  If already resolved, `AWAIT` returns immediately with
  just a memory read — no spinlock, no event interaction.

- **Binding table:** The ASYNC binding table holds 8 entries
  (matching the 8-task slot limit).  Entries are consumed in FIFO
  order.  The table wraps around (modulo 8) for reuse.

- **No closure / CURRY needed:** The FIFO binding table avoids
  the need for closures or runtime code generation.  Each
  `_FUT-RUNNER` task reads its binding from the table instead
  of carrying captured variables.

---

## Quick Reference

| Word              | Signature                  | Behavior                            |
|-------------------|----------------------------|-------------------------------------|
| `PROMISE`         | `( -- addr )`              | Allocate pending promise            |
| `RESOLVED?`       | `( p -- flag )`            | Is promise fulfilled?               |
| `FULFILL`         | `( val p -- )`             | Store result, wake waiters          |
| `AWAIT`           | `( p -- val )`             | Block until fulfilled, return value |
| `AWAIT-TIMEOUT`   | `( p ms -- val flag )`     | Await with timeout                  |
| `ASYNC`           | `( xt -- promise )`        | Spawn task, return promise          |
| `FUT-RESET`       | `( p -- )`                 | Reset to PENDING (recycling)        |
| `FUT-INFO`        | `( p -- )`                 | Debug display                       |

### Internal Words

| Word               | Signature           | Behavior                             |
|--------------------|---------------------|--------------------------------------|
| `_FUT-VALUE`       | `( p -- addr )`     | Address of value field (+0)          |
| `_FUT-RESOLVED`    | `( p -- addr )`     | Address of resolved flag (+8)        |
| `_FUT-EVT`         | `( p -- ev )`       | Embedded event at +16                |
| `_FUT-RUNNER`      | `( -- )`            | Generic task body for ASYNC          |
| `_FUT-ASYNC-XTS`   | `( -- addr )`       | Binding table: xt array              |
| `_FUT-ASYNC-PROMS` | `( -- addr )`       | Binding table: promise array         |
| `_FUT-AWIDX`       | `( -- addr )`       | Binding table write index            |
| `_FUT-ARIDX`       | `( -- addr )`       | Binding table read index             |

### Constants

| Name              | Value | Meaning                           |
|-------------------|-------|-----------------------------------|
| `_FUT-PCELLS`     | 6     | Cells per promise descriptor      |
| `_FUT-PBYTES`     | 48    | Bytes per promise (6 × 8)         |
| `_FUT-BIND-CAP`   | 8     | ASYNC binding table capacity      |
