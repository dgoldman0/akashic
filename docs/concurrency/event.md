# akashic-event — Wait/Notify Events for KDOS / Megapad-64

Foundational synchronization primitive for the Akashic concurrency
library.  An event is a boolean flag that tasks can wait on and other
tasks (or ISRs, or other cores) can signal.

```forth
REQUIRE event.f
```

`PROVIDED akashic-event` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation](#creation)
- [Signaling & Resetting](#signaling--resetting)
- [Waiting](#waiting)
- [Timeout](#timeout)
- [Pulse](#pulse)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Boolean flag** | An event is set (TRUE) or unset (FALSE). |
| **Waiter tracking** | Up to 2 task descriptors registered per event. |
| **Spinlock-protected** | Mutations guarded by hardware spinlock 6. |
| **Lock-free reads** | `EVT-SET?` reads a single aligned 64-bit cell — atomic on Megapad-64. |
| **Prefix convention** | Public: `EVT-`. Internal: `_EVT-`. |
| **Building block** | Channels, futures, semaphores all use events internally. |

---

## Memory Layout

An event occupies 4 cells = 32 bytes:

```
Offset  Size   Field
──────  ─────  ─────────────
0       8      flag        (0 = unset, -1 = set)
8       8      wait-count  (number of tasks in EVT-WAIT)
16      8      waiter-0    (task descriptor or 0)
24      8      waiter-1    (task descriptor or 0)
```

Waiter slots are limited to 2 — sufficient for most patterns (channel
has 1 sender + 1 receiver; future has 1 producer + 1 consumer).  The
system has at most 8 task slots total.

---

## Creation

### `EVENT`

```forth
EVENT ( "name" -- )
```

Create a manual-reset event, initially unset.  Compiles 32 bytes of
inline data in the dictionary and defines a constant pointing to it.

```forth
EVENT data-ready
EVENT shutdown-signal
EVENT io-complete
```

---

## Signaling & Resetting

### `EVT-SET`

```forth
EVT-SET ( ev -- )
```

Set the event flag to TRUE and wake all registered waiters by marking
them `T.READY`.  The waiter list is cleared.  Safe to call from any
core, from ISRs, or from timer callbacks.

```forth
data-ready EVT-SET      \ wake all tasks waiting on data-ready
```

### `EVT-RESET`

```forth
EVT-RESET ( ev -- )
```

Clear the event flag back to FALSE.  Does **not** affect waiters — if
tasks are currently spinning in `EVT-WAIT`, they will continue waiting
until the event is set again.

```forth
data-ready EVT-RESET    \ clear for next cycle
```

---

## Waiting

### `EVT-WAIT`

```forth
EVT-WAIT ( ev -- )
```

Spin until the event is set.  Calls `YIELD?` on each iteration for
preemption awareness.  The current task is marked `T.BLOCKED` while
waiting (visible in `TASKS` output) and restored to `T.RUNNING` when
the event fires.

**Fast path:** if the event is already set when `EVT-WAIT` is called,
it returns immediately without spinning.

```forth
\ Core 1: wait for data
data-ready EVT-WAIT
\ ... data is now available ...

\ Core 0: signal when ready
process-data  data-ready EVT-SET
```

### `EVT-SET?`

```forth
EVT-SET? ( ev -- flag )
```

Non-blocking query.  Returns TRUE (-1) if the event is currently set,
FALSE (0) otherwise.  Lock-free — reads a single aligned cell.

```forth
data-ready EVT-SET? IF  handle-data  THEN
```

---

## Timeout

### `EVT-WAIT-TIMEOUT`

```forth
EVT-WAIT-TIMEOUT ( ev ms -- flag )
```

Wait up to `ms` milliseconds.  Returns TRUE (-1) if the event was
signaled within the deadline, FALSE (0) if the timeout expired.

Uses `EPOCH@` (BIOS: milliseconds since boot) for timing.

```forth
io-complete 5000 EVT-WAIT-TIMEOUT
IF   ." I/O completed" CR
ELSE ." I/O timed out"  CR  THEN
```

---

## Pulse

### `EVT-PULSE`

```forth
EVT-PULSE ( ev -- )
```

Atomically set the event (waking all current waiters), then immediately
reset it.  Only tasks that are **already spinning** in `EVT-WAIT` will
be woken.  Tasks that check later will see the event as unset.

Useful for one-shot notifications where you don't want the event to
remain set:

```forth
\ Notify current waiters, but don't leave the event set
tick-event EVT-PULSE
```

---

## Debug

### `EVT-INFO`

```forth
EVT-INFO ( ev -- )
```

Print event status:

```
[event SET waiters=0]
[event UNSET waiters=2]
```

---

## Concurrency Model

### Multicore (Primary Use Case)

Events are designed for multicore synchronization.  One core spins in
`EVT-WAIT`; another core calls `EVT-SET` via shared memory:

```forth
\ Core 0:
EVENT batch-done
['] process-batch 1 CORE-RUN    \ dispatch to core 1
batch-done EVT-WAIT              \ wait for core 1
\ ... results ready ...

\ Core 1 (runs process-batch):
: process-batch
    do-heavy-work
    batch-done EVT-SET ;         \ signal core 0
```

### Single-Core Cooperative

The KDOS scheduler is run-to-completion — two cooperative tasks on the
same core cannot interleave.  On a single core, the signal must come
from:

- **A timer ISR** that calls `EVT-SET`
- **A hardware interrupt handler** (e.g., NIC rx-complete)
- **Polling I/O** that detects readiness and signals

For single-core producer/consumer, use `EVT-SET?` (non-blocking poll)
instead of `EVT-WAIT` (blocking spin):

```forth
: consumer
    BEGIN
        data-ready EVT-SET? IF
            data-ready EVT-RESET
            process-data
        THEN
        do-other-work
    AGAIN ;
```

### Interrupt-Driven

Events integrate naturally with ISRs:

```forth
EVENT uart-rx-ready

\ In ISR (short, non-blocking):
: uart-isr   uart-rx-ready EVT-SET ;

\ In main task:
uart-rx-ready EVT-WAIT
uart-rx-ready EVT-RESET
read-uart-data
```

### Implementation Notes

- **Spinlock 6** is dedicated to event operations.  All flag and waiter
  mutations are protected.  `EVT-SET?` is lock-free (atomic read).
- **Waiter list** stores up to 2 task descriptors.  `EVT-SET` marks
  all waiters as `T.READY` and clears the list.  Extra waiters beyond
  2 are silently ignored (they still wake via flag polling, just without
  the `T.READY` fast-path).
- **`T.BLOCKED`** state is used for the first time by `EVT-WAIT`.
  The scheduler's `FIND-READY` already skips `T.BLOCKED` tasks.

---

## Quick Reference

| Word                | Signature               | Behavior                                   |
|---------------------|-------------------------|--------------------------------------------|
| `EVENT`             | `( "name" -- )`         | Create event (initially unset)             |
| `EVT-SET?`          | `( ev -- flag )`        | Is event set? (lock-free)                  |
| `EVT-SET`           | `( ev -- )`             | Signal event, wake all waiters             |
| `EVT-RESET`         | `( ev -- )`             | Clear event flag                           |
| `EVT-WAIT`          | `( ev -- )`             | Spin until event is set                    |
| `EVT-WAIT-TIMEOUT`  | `( ev ms -- flag )`    | Wait with timeout (ms); TRUE if signaled   |
| `EVT-PULSE`         | `( ev -- )`             | Set + immediate reset (one-shot wake)      |
| `EVT-INFO`          | `( ev -- )`             | Debug display                              |

### Internal Words

| Word                  | Signature          | Behavior                              |
|-----------------------|--------------------|---------------------------------------|
| `_EVT-ADD-WAITER`     | `( ev -- )`        | Register current task as waiter       |
| `_EVT-REMOVE-WAITER`  | `( ev -- )`        | Remove current task from waiters      |
| `_EVT-WAKE-ALL`       | `( ev -- )`        | Mark all waiters T.READY, clear list  |

### Constants

| Name               | Value | Meaning                         |
|--------------------|-------|---------------------------------|
| `EVT-LOCK`         | 6     | Hardware spinlock for events    |
| `_EVT-CELLS`       | 4     | Cells per event descriptor      |
| `_EVT-SIZE`        | 32    | Bytes per event descriptor      |
| `_EVT-MAX-WAITERS` | 2     | Waiter slots per event          |
