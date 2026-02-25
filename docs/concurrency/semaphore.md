# akashic-semaphore — Counting Semaphores for KDOS / Megapad-64

Classic counting semaphore built on top of `event.f`.  Use for
rate-limiting, producer-consumer synchronization, and general
resource counting.

```forth
REQUIRE semaphore.f
```

`PROVIDED akashic-semaphore` — safe to include multiple times.
Automatically requires `event.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation](#creation)
- [Acquire & Release](#acquire--release)
- [Non-Blocking & Timeout](#non-blocking--timeout)
- [RAII Pattern](#raii-pattern)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Counting** | Count tracks available resources; 0 = none available. |
| **Embedded event** | 4-cell event inlined at +8; no heap, no indirection. |
| **Same spinlock** | Uses EVT-LOCK (spinlock 6) for atomic count + signal. |
| **Prefix convention** | Public: `SEM-`. Internal: `_SEM-`. |
| **RAII support** | `WITH-SEM` wraps acquire/execute/release with CATCH. |

---

## Memory Layout

A semaphore occupies 5 cells = 40 bytes:

```
Offset  Size   Field
──────  ─────  ─────────────
0       8      count        (signed 64-bit integer)
8       8      event flag   (0 = unset, -1 = set)
16      8      event wait-count
24      8      event waiter-0
32      8      event waiter-1
```

The event at +8 is a standard `EVENT` structure embedded inline.
`_SEM-EVT` returns the address of +8 for use with `EVT-WAIT`,
`EVT-PULSE`, etc.

---

## Creation

### `SEMAPHORE`

```forth
SEMAPHORE ( initial "name" -- )
```

Create a named counting semaphore.  The initial count is the number
of available resources.

```forth
3 SEMAPHORE tcp-slots       \ 3 concurrent connections
1 SEMAPHORE uart-mutex      \ binary semaphore (mutex)
0 SEMAPHORE work-ready      \ signaling semaphore (starts empty)
```

---

## Acquire & Release

### `SEM-WAIT`

```forth
SEM-WAIT ( sem -- )
```

Decrement the count.  If the count is already 0, block in a
yield-aware spin loop until `SEM-SIGNAL` raises it.  The caller
is marked `T.BLOCKED` while waiting (via the embedded event).

```forth
tcp-slots SEM-WAIT          \ blocks until a slot is available
\ ... use the slot ...
tcp-slots SEM-SIGNAL        \ release the slot
```

### `SEM-SIGNAL`

```forth
SEM-SIGNAL ( sem -- )
```

Increment the count and pulse the embedded event to wake one blocked
waiter.  Safe to call from any core and from ISRs.

```forth
tcp-slots SEM-SIGNAL        \ release a resource
```

### `SEM-COUNT`

```forth
SEM-COUNT ( sem -- n )
```

Return the current count.  Lock-free — reads a single aligned cell.

```forth
tcp-slots SEM-COUNT .       \ print available slots
```

---

## Non-Blocking & Timeout

### `SEM-TRYWAIT`

```forth
SEM-TRYWAIT ( sem -- flag )
```

Try to decrement without blocking.  Returns TRUE (-1) if acquired,
FALSE (0) if count was 0.

```forth
tcp-slots SEM-TRYWAIT IF
    \ got a slot
ELSE
    ." busy, try later" CR
THEN
```

### `SEM-WAIT-TIMEOUT`

```forth
SEM-WAIT-TIMEOUT ( sem ms -- flag )
```

Try to acquire within `ms` milliseconds.  Returns TRUE (-1) if
acquired, FALSE (0) if timed out.  Uses `EPOCH@` for timing.

```forth
tcp-slots 5000 SEM-WAIT-TIMEOUT IF
    \ got a slot within 5 seconds
ELSE
    ." connection pool exhausted" CR
THEN
```

---

## RAII Pattern

### `WITH-SEM`

```forth
WITH-SEM ( xt sem -- )
```

Acquire the semaphore, execute `xt`, then release — even if `xt`
throws an exception.  Uses `CATCH` / `THROW` for exception safety.

```forth
['] handle-connection tcp-slots WITH-SEM
```

Equivalent to:

```forth
tcp-slots SEM-WAIT
['] handle-connection CATCH
tcp-slots SEM-SIGNAL
THROW
```

---

## Debug

### `SEM-INFO`

```forth
SEM-INFO ( sem -- )
```

Print semaphore status:

```
[semaphore count=2 evt:[event UNSET waiters=0]
]
```

---

## Concurrency Model

### Multicore (Primary Use Case)

One core blocks in `SEM-WAIT`; another calls `SEM-SIGNAL`:

```forth
\ Core 0: rate-limited dispatch
3 SEMAPHORE worker-slots

: dispatch-work  ( xt -- )
    worker-slots SEM-WAIT       \ block until slot free
    1 CORE-RUN                  \ run on core 1
    worker-slots SEM-SIGNAL ;   \ release when done
```

### Binary Semaphore (Mutex)

A semaphore with initial count 1 acts as a mutex:

```forth
1 SEMAPHORE my-mutex

: critical-section
    my-mutex SEM-WAIT
    \ ... exclusive access ...
    my-mutex SEM-SIGNAL ;
```

For simpler mutual exclusion, prefer `WITH-LOCK` on a hardware
spinlock.  Binary semaphores are useful when you need the richer
semantics (timeout, try-wait, cross-core blocking).

### Producer-Consumer

A semaphore with initial count 0 acts as a signaling mechanism:

```forth
0 SEMAPHORE items-ready

: producer
    produce-item  buffer-push
    items-ready SEM-SIGNAL ;    \ notify consumer

: consumer
    items-ready SEM-WAIT        \ block until item available
    buffer-pop  process-item ;
```

### Implementation Notes

- **Spinlock 6** (EVT-LOCK) guards both the count cell and the
  embedded event.  `SEM-WAIT` acquires EVT-LOCK to atomically check
  and decrement the count; if the count is 0 it releases the lock
  and falls into `EVT-WAIT` on the embedded event.

- **EVT-PULSE** is used by `SEM-SIGNAL` instead of `EVT-SET` to
  avoid leaving the event permanently set.  Each signal wakes
  waiters who then re-check the count — this handles the case where
  multiple waiters race for a single increment.

- **`WITH-SEM`** uses `CATCH` / `THROW` for exception safety.
  If the called XT aborts, the semaphore is still released.

---

## Quick Reference

| Word               | Signature               | Behavior                              |
|--------------------|-------------------------|---------------------------------------|
| `SEMAPHORE`        | `( initial "name" -- )` | Create counting semaphore             |
| `SEM-COUNT`        | `( sem -- n )`          | Current count (lock-free)             |
| `SEM-WAIT`         | `( sem -- )`            | Acquire (block if count=0)            |
| `SEM-SIGNAL`       | `( sem -- )`            | Release (increment + wake)            |
| `SEM-TRYWAIT`      | `( sem -- flag )`       | Non-blocking acquire                  |
| `SEM-WAIT-TIMEOUT` | `( sem ms -- flag )`    | Acquire with timeout                  |
| `SEM-INFO`         | `( sem -- )`            | Debug display                         |
| `WITH-SEM`         | `( xt sem -- )`         | RAII: acquire, execute, release       |

### Internal Words

| Word         | Signature          | Behavior                            |
|--------------|--------------------|-------------------------------------|
| `_SEM-COUNT` | `( sem -- addr )`  | Address of count cell (+0)          |
| `_SEM-EVT`   | `( sem -- ev )`    | Address of embedded event (+8)      |

### Constants

| Name          | Value | Meaning                        |
|---------------|-------|--------------------------------|
| `_SEM-CELLS`  | 5     | Cells per semaphore descriptor |
| `_SEM-SIZE`   | 40    | Bytes per semaphore descriptor |
