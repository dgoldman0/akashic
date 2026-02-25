# Concurrency Library — Roadmap

A structured concurrency library for KDOS / Megapad-64, layered on top
of the existing §8 scheduler, hardware spinlocks, multicore dispatch,
run queues, IPI messaging, and lock-aware ring buffers.

KDOS already has the low-level primitives.  What it lacks are the
higher-level abstractions that make concurrent programming safe and
ergonomic: semaphores, channels, futures, parallel combinators, and
structured task lifetimes.

---

## Table of Contents

- [Current State — What KDOS Already Has](#current-state--what-kdos-already-has)
- [What's Missing](#whats-missing)
- [Architecture Principles](#architecture-principles)
- [Layer 1 — Synchronization Primitives](#layer-1--synchronization-primitives)
  - [1.1 event.f — Wait/Notify Events](#11-eventf--waitnotify-events)
  - [1.2 semaphore.f — Counting Semaphores](#12-semaphoref--counting-semaphores)
  - [1.3 rwlock.f — Reader-Writer Locks](#13-rwlockf--reader-writer-locks)
- [Layer 2 — Communication](#layer-2--communication)
  - [2.1 channel.f — Go-Style Bounded Channels](#21-channelf--go-style-bounded-channels)
  - [2.2 mailbox.f — Per-Task Actor Mailboxes](#22-mailboxf--per-task-actor-mailboxes)
- [Layer 3 — Futures & Async Patterns](#layer-3--futures--async-patterns)
  - [3.1 future.f — Promises and ASYNC/AWAIT](#31-futuref--promises-and-asyncawait)
  - [3.2 par.f — Parallel Combinators](#32-parf--parallel-combinators)
- [Layer 4 — Structured Concurrency](#layer-4--structured-concurrency)
  - [4.1 scope.f — Task Groups and Lifetimes](#41-scopef--task-groups-and-lifetimes)
- [Layer 5 — Concurrent Data Structures](#layer-5--concurrent-data-structures)
  - [5.1 cvar.f — Concurrent Variables](#51-cvarf--concurrent-variables)
  - [5.2 conc-map.f — Concurrent Hash Map](#52-conc-mapf--concurrent-hash-map)
- [Dependency Graph](#dependency-graph)
- [Implementation Order](#implementation-order)
- [Design Constraints & Gotchas](#design-constraints--gotchas)
- [Testing Strategy](#testing-strategy)

---

## Current State — What KDOS Already Has

### §8 — Cooperative Scheduler & Tasks (kdos.f lines 4584–4780)

Task states: `T.FREE` (0), `T.READY` (1), `T.RUNNING` (2),
`T.BLOCKED` (3), `T.DONE` (4).

Task descriptor — 6 cells = 48 bytes:

| Offset | Field     | Description                     |
|--------|-----------|---------------------------------|
| +0     | status    | Task state (0–4)                |
| +8     | priority  | 0 = highest, 255 = lowest       |
| +16    | xt        | Execution token (task body)     |
| +24    | dsp_save  | Saved data stack pointer        |
| +32    | rsp_save  | Saved return stack pointer      |
| +40    | name_addr | Pointer to name string or 0     |

Task registry: Up to **8 tasks**.  Each gets a 256-byte private data
stack area.

| Word              | Signature                     | Behavior                                      |
|-------------------|-------------------------------|-----------------------------------------------|
| `TASK`            | `( xt priority "name" -- )`   | Create a named task, register it as READY      |
| `SPAWN`           | `( xt -- )`                   | Create anonymous task with priority 128        |
| `BG`              | `( xt -- )`                   | SPAWN + SCHEDULE (one-shot convenience)        |
| `KILL`            | `( tdesc -- )`                | Mark task as DONE                              |
| `RESTART`         | `( tdesc -- )`                | Reset a DONE task back to READY                |
| `SCHEDULE`        | `( -- )`                      | Round-robin all READY tasks until none remain  |
| `FIND-READY`      | `( -- tdesc\|0 )`             | Find first READY task descriptor               |
| `RUN-TASK`        | `( tdesc -- )`                | Execute task's XT, mark DONE on return         |
| `YIELD`           | `( -- )`                      | Cooperative yield: mark current task DONE      |
| `YIELD?`          | `( -- )`                      | Check preempt flag or timer; yield if set      |
| `TASKS`           | `( -- )`                      | Display all registered tasks                   |
| `TASK-COUNT-READY`| `( -- n )`                    | Count READY tasks                              |
| `T.STATUS`        | `( tdesc -- n )`              | Read task status                               |
| `T.PRIORITY`      | `( tdesc -- n )`              | Read task priority                             |
| `T.XT`            | `( tdesc -- xt )`             | Read task execution token                      |
| `T.INFO`          | `( tdesc -- )`                | Print task info                                |

### §8 — Timer Preemption (kdos.f lines 4770–4810)

Polling-based preemption.  A timer compare-match sets `PREEMPT-FLAG`,
which cooperative `YIELD?` checks on each call.

| Word             | Signature    | Behavior                                           |
|------------------|--------------|----------------------------------------------------|
| `PREEMPT-ON`     | `( -- )`     | Enable timer-based preemption (auto-reload timer)  |
| `PREEMPT-OFF`    | `( -- )`     | Disable preemption                                 |
| `TIME-SLICE`     | variable     | Cycle count per time slice (default: 50,000)       |
| `PREEMPT-FLAG`   | variable     | Set by timer, cleared by YIELD?                    |

### §8.1 — Multicore Dispatch (kdos.f lines 4830–4970)

| Word              | Signature           | Behavior                                   |
|-------------------|---------------------|--------------------------------------------|
| `CORE-RUN`        | `( xt core -- )`    | Dispatch XT to secondary core via WAKE-CORE|
| `CORE-WAIT`       | `( core -- )`       | Busy-wait until core is idle               |
| `ALL-CORES-WAIT`  | `( -- )`            | Wait for all secondary cores               |
| `ALL-FULL-WAIT`   | `( -- )`            | Wait for full cores only (excl. micro)     |
| `BARRIER`         | `( -- )`            | Synonym for ALL-CORES-WAIT                 |
| `CORES`           | `( -- )`            | Display per-core status                    |
| `P.RUN-PAR`       | `( pipe -- )`       | Run pipeline steps in parallel             |
| `P.BENCH-PAR`     | `( pipe -- )`       | Benchmark parallel pipeline execution      |

### §8.1 — Spinlocks (kdos.f lines 4900–4920)

Hardware spinlocks — 8 MMIO-backed mutexes via `SPIN@` / `SPIN!`.

| Word     | Signature    | Behavior                            |
|----------|--------------|-------------------------------------|
| `LOCK`   | `( n -- )`   | Acquire spinlock n (busy-wait + YIELD?) |
| `UNLOCK` | `( n -- )`   | Release spinlock n                  |

### §8.2 — Per-Core Run Queues (kdos.f lines 4985–5100)

Circular task queues per core (8 entries deep × 16 cores max).

| Word        | Signature            | Behavior                          |
|-------------|----------------------|-----------------------------------|
| `RQ-PUSH`   | `( xt core -- )`     | Enqueue task onto core's queue    |
| `RQ-POP`    | `( core -- xt\|0 )`  | Dequeue next task                 |
| `RQ-COUNT`  | `( core -- n )`      | Number of enqueued tasks          |
| `RQ-EMPTY?` | `( core -- flag )`   | Is core's queue empty?            |
| `RQ-FULL?`  | `( core -- flag )`   | Is core's queue full?             |
| `RQ-CLEAR`  | `( core -- )`        | Clear a core's queue              |
| `RQ-INIT`   | `( -- )`             | Initialize all queues             |
| `SCHED-CORE`| `( core -- )`        | Dispatch all queued tasks on core |
| `SCHED-ALL` | `( -- )`             | Dispatch tasks from all queues    |
| `RQ-INFO`   | `( -- )`             | Display queue status              |

### §8.3 — Work Stealing (kdos.f lines 5115–5195)

| Word           | Signature              | Behavior                              |
|----------------|------------------------|---------------------------------------|
| `STEAL-FROM`   | `( victim thief -- f)` | Steal one task from victim to thief   |
| `RQ-BUSIEST`   | `( exclude -- core\|-1)` | Find core with most queued tasks    |
| `WORK-STEAL`   | `( core -- flag )`     | Try to steal one task for core        |
| `BALANCE`      | `( -- )`               | Rebalance work across full cores      |
| `SCHED-BALANCED` | `( -- )`             | BALANCE + SCHED-ALL                   |

### §8.4 — Core Affinity (kdos.f lines 5200–5300)

| Word          | Signature            | Behavior                           |
|---------------|----------------------|------------------------------------|
| `AFFINITY!`   | `( core task# -- )`  | Set affinity (-1 = any)            |
| `AFFINITY@`   | `( task# -- core )`  | Get affinity                       |
| `SPAWN-ON`    | `( xt core -- )`     | Create task on core's queue        |
| `SCHED-AFFINE`| `( -- )`             | Push tasks to affinity cores       |
| `AFF-INFO`    | `( -- )`             | Display affinity table             |

### §8.5 — Per-Core Preemption (kdos.f lines 5305–5360)

| Word              | Signature           | Behavior                     |
|-------------------|---------------------|------------------------------|
| `PREEMPT-FLAG!`   | `( val core -- )`   | Set per-core preempt flag    |
| `PREEMPT-FLAG@`   | `( core -- val )`   | Read per-core preempt flag   |
| `PREEMPT-SET`     | `( core -- )`       | Set flag for core            |
| `PREEMPT-CLR`     | `( core -- )`       | Clear flag for core          |
| `PREEMPT-ON-ALL`  | `( -- )`            | Enable for all cores         |
| `PREEMPT-OFF-ALL` | `( -- )`            | Disable for all cores        |
| `PREEMPT-INFO`    | `( -- )`            | Display per-core state       |

### §8.6 — IPI Messaging (kdos.f lines 5365–5480)

Structured inter-core message passing via shared-memory circular inbox
queues.  3-cell messages (type, sender, payload).  Protected by
hardware spinlock 7.

| Word             | Signature                        | Behavior                            |
|------------------|----------------------------------|-------------------------------------|
| `MSG-SEND`       | `( type payload target -- flag)` | Send message to core's inbox        |
| `MSG-RECV`       | `( -- type sender payload flag)` | Receive from own inbox              |
| `MSG-PEEK`       | `( -- flag )`                    | Check if inbox has messages         |
| `MSG-BROADCAST`  | `( type payload -- n )`          | Send to all other cores             |
| `MSG-FLUSH`      | `( -- n )`                       | Drain all messages                  |
| `MSG-HANDLER!`   | `( xt type -- )`                 | Register handler for message type   |
| `MSG-DISPATCH`   | `( -- flag )`                    | Receive + dispatch to handler       |
| `MSG-INFO`       | `( -- )`                         | Display per-core inbox status       |

Message types: `MSG-CALL` (0), `MSG-DATA` (1), `MSG-SIGNAL` (2),
`MSG-USER` (3).

### §8.7 — Shared Resource Locks (kdos.f lines 5485–5540)

| Word                              | Signature      | Behavior                         |
|-----------------------------------|----------------|----------------------------------|
| `DICT-ACQUIRE` / `DICT-RELEASE`  | `( -- )`       | Lock/unlock dictionary (spin 0)  |
| `UART-ACQUIRE` / `UART-RELEASE`  | `( -- )`       | Lock/unlock UART (spinlock 1)    |
| `FS-ACQUIRE` / `FS-RELEASE`      | `( -- )`       | Lock/unlock filesystem (spin 2)  |
| `HEAP-ACQUIRE` / `HEAP-RELEASE`  | `( -- )`       | Lock/unlock heap (spinlock 3)    |
| `WITH-LOCK`                      | `( xt lock# -- )`| Execute xt while holding lock  |

Spinlock assignments: 0=Dictionary, 1=UART, 2=Filesystem, 3=Heap,
4=Ring buffers, 5=Hash tables, 7=IPI messaging.

### §8.8 — Micro-Cluster Support (kdos.f lines 5545–5620)

| Word              | Signature      | Behavior                         |
|-------------------|----------------|----------------------------------|
| `CLUSTER-ENABLE`  | `( n -- )`     | Enable micro-cluster n (0–2)     |
| `CLUSTER-DISABLE` | `( n -- )`     | Disable micro-cluster n          |
| `CLUSTERS-ON`     | `( -- )`       | Enable all clusters              |
| `CLUSTERS-OFF`    | `( -- )`       | Disable all clusters             |
| `HW-BARRIER-WAIT` | `( -- )`      | Hardware barrier synchronization |
| `SPAD-C@`         | `( off -- c )` | Read from cluster scratchpad     |
| `SPAD-C!`         | `( c off -- )` | Write to cluster scratchpad      |
| `CLUSTER-STATE`   | `( -- )`       | Display cluster enable status    |

### §8.9 — Cluster MPU

| Word             | Signature            | Behavior                     |
|------------------|----------------------|------------------------------|
| `CL-MPU-SETUP`   | `( base limit -- )` | Set cluster memory window    |
| `CL-ENTER-USER`  | `( -- )`            | Switch to user mode          |
| `CL-EXIT-USER`   | `( -- )`            | Return to supervisor mode    |
| `CL-MPU-OFF`     | `( -- )`            | Disable cluster MPU          |

### §18 — Ring Buffers (kdos.f lines 10786–10890)

Lock-aware circular buffers.

| Word          | Signature                  | Behavior                     |
|---------------|----------------------------|------------------------------|
| `RING`        | `( elem-size cap "name" -- )`| Create named ring buffer   |
| `RING-PUSH`   | `( elem-addr ring -- flag )`| Lock → enqueue → unlock     |
| `RING-POP`    | `( elem-addr ring -- flag )`| Lock → dequeue → unlock     |
| `RING-PEEK`   | `( idx ring -- addr\|0 )`  | Read-only, lock-free         |
| `RING-FULL?`  | `( ring -- flag )`         | Is full?                     |
| `RING-EMPTY?` | `( ring -- flag )`         | Is empty?                    |
| `RING-COUNT`  | `( ring -- n )`            | Element count                |

### §19 — Hash Tables

Write operations lock-protected (spinlock 5); reads (`HT-GET`,
`HT-EACH`) are lock-free.

### BIOS-Level Multicore Primitives

| Word          | Signature            | Behavior                          |
|---------------|----------------------|-----------------------------------|
| `COREID`      | `( -- n )`           | Current core ID                   |
| `NCORES`      | `( -- n )`           | Total core count                  |
| `WAKE-CORE`   | `( xt core -- )`     | IPI-wake secondary core           |
| `CORE-STATUS`  | `( core -- n )`     | 0 = idle, nonzero = busy          |
| `SPIN@`       | `( n -- flag )`      | Try-acquire hardware spinlock     |
| `SPIN!`       | `( n -- )`           | Release hardware spinlock         |
| `IPI-SEND`    | `( val core -- )`    | Send IPI to core                  |
| `IPI-STATUS`  | `( -- n )`           | Check IPI status                  |
| `IPI-ACK`     | `( -- )`             | Acknowledge IPI                   |
| `MBOX!`       | `( val -- )`         | Write to mailbox                  |
| `MBOX@`       | `( -- val )`         | Read from mailbox                 |

---

## What's Missing

KDOS has no:

- **Semaphores** — counting waiter abstraction
- **Condition variables / events** — wait/notify without polling
- **Reader-writer locks** — shared reads, exclusive writes
- **Channels** — typed producer/consumer queues (CSP model)
- **Futures / promises** — async result passing
- **Parallel combinators** — map/reduce/for over arrays across cores
- **Structured concurrency** — task groups with lifetime guarantees
- **Concurrent data structures** — atomic variables, concurrent maps

All concurrency is cooperative at the Forth level.  Blocking is done
via busy-wait + `YIELD?`.  There is no "park this task and wake it
when X happens" mechanism — which is the single biggest gap.

---

## Architecture Principles

1. **Blocking = YIELD loop, not busy-spin.**  `SEM-WAIT` marks the
   task `T.BLOCKED` and calls `YIELD`.  The scheduler skips blocked
   tasks.  The signaler sets it back to `T.READY`.

2. **Build on ring buffers.**  A `CHANNEL` is a `RING` + two events
   (not-full, not-empty).  No new data structures needed.

3. **Build on existing spinlocks.**  All shared mutable state
   protected by the 8 hardware spinlocks.  Where 8 is not enough,
   software spinlocks (CAS on memory cells) provide finer granularity.

4. **Prefix convention.**  Each file gets its own prefix:
   - `event.f`     → `EVT-`
   - `semaphore.f` → `SEM-`
   - `rwlock.f`    → `RW-`
   - `channel.f`   → `CHAN-`
   - `mailbox.f`   → `MBOX-` (extends existing `MBOX@`/`MBOX!`)
   - `future.f`    → `FUT-`
   - `par.f`       → `PAR-`
   - `scope.f`     → `TG-`
   - `cvar.f`      → `CV-`
   - `conc-map.f`  → `CMAP-`

5. **Internal prefix:** `_PREFIX-` for private helper words.

6. **Zero heap allocation in hot paths.**  Events, semaphores, and
   channels are statically declared with defining words (like `RING`).
   Only `ASYNC` / task group spawn may allocate.

7. **Core-0 ownership.**  Library-level task management runs on
   core 0.  Secondary cores consume work from run queues.

---

## Layer 1 — Synchronization Primitives

### 1.1 event.f — Wait/Notify Events

**Depends on:** §8 (TASK scheduler, T.BLOCKED state), spinlocks

**Purpose:** The foundational wait/notify mechanism.  Every higher
layer (channels, futures, task groups) uses events internally.

An event is a boolean flag + a waiter list.  `EVT-WAIT` marks the
calling task as T.BLOCKED and enters a yield loop.  `EVT-SET`
flips the flag and marks all waiters as T.READY.

**Data structure — 4 cells = 32 bytes:**

| Offset | Field       | Description                        |
|--------|-------------|------------------------------------|
| +0     | flag        | 0 = unset, -1 = set               |
| +8     | wait-count  | Number of tasks currently waiting  |
| +16    | waiter-0    | Task descriptor of first waiter    |
| +24    | waiter-1    | Task descriptor of second waiter   |

(Waiter slots limited to 2 — sufficient since max 8 tasks total.
Can extend to a linked list if task slots grow.)

**Public API:**

| Word                 | Signature               | Behavior                                   |
|----------------------|-------------------------|--------------------------------------------|
| `EVENT`              | `( "name" -- )`         | Create a manual-reset event (initially unset) |
| `EVT-WAIT`           | `( ev -- )`             | Block until event is signaled               |
| `EVT-WAIT-TIMEOUT`   | `( ev ms -- flag )`    | Wait with timeout; TRUE if signaled         |
| `EVT-SET`            | `( ev -- )`             | Signal event, wake all waiters              |
| `EVT-RESET`          | `( ev -- )`             | Clear event back to unset                   |
| `EVT-PULSE`          | `( ev -- )`             | SET + immediate RESET (wake current waiters)|
| `EVT-SET?`           | `( ev -- flag )`        | Is the event currently set?                 |

**Internal words:**

| Word                 | Signature               | Behavior                                   |
|----------------------|-------------------------|--------------------------------------------|
| `_EVT-ADD-WAITER`    | `( ev -- )`             | Add current task to waiter list             |
| `_EVT-WAKE-ALL`      | `( ev -- )`             | Set all waiters to T.READY                  |
| `_EVT-REMOVE-WAITER` | `( ev -- )`             | Remove current task from waiter list        |

**Implementation sketch:**

```forth
: EVT-WAIT  ( ev -- )
  DUP EVT-SET? IF DROP EXIT THEN   \ fast path: already set
  DUP _EVT-ADD-WAITER
  CURRENT-TASK T.BLOCKED OVER !     \ mark self blocked
  BEGIN  DUP EVT-SET?  0= WHILE  YIELD  REPEAT
  _EVT-REMOVE-WAITER
;

: EVT-SET  ( ev -- )
  -1 OVER !                         \ set flag
  _EVT-WAKE-ALL                     \ wake all waiters
;
```

**Status:** ✅ Done — `akashic/concurrency/event.f`

---

### 1.2 semaphore.f — Counting Semaphores

**Depends on:** event.f, spinlocks

**Purpose:** Classic counting semaphore.  Use for rate-limiting
(e.g., max N concurrent TCP connections), producer-consumer
synchronization, and general resource counting.

**Data structure — 3 cells = 24 bytes:**

| Offset | Field  | Description                    |
|--------|--------|--------------------------------|
| +0     | count  | Current count (signed)         |
| +8     | lock#  | Spinlock number for atomicity  |
| +16    | event  | Embedded event for blocking    |

**Public API:**

| Word            | Signature             | Behavior                                     |
|-----------------|-----------------------|----------------------------------------------|
| `SEMAPHORE`     | `( initial "name" -- )`| Create a named counting semaphore           |
| `SEM-WAIT`      | `( sem -- )`          | Decrement; if <0, block (YIELD loop)         |
| `SEM-SIGNAL`    | `( sem -- )`          | Increment; wake one blocked waiter           |
| `SEM-TRYWAIT`   | `( sem -- flag )`     | Non-blocking attempt; TRUE if acquired       |
| `SEM-COUNT`     | `( sem -- n )`        | Current count                                |

**Implementation sketch:**

```forth
: SEM-WAIT  ( sem -- )
  BEGIN
    DUP SEM-COUNT 0> IF
      DUP _SEM-LOCK  DUP _SEM-DEC  DUP _SEM-UNLOCK  EXIT
    THEN
    DUP _SEM-EVT EVT-WAIT
  AGAIN
;

: SEM-SIGNAL  ( sem -- )
  DUP _SEM-LOCK  DUP _SEM-INC  DUP _SEM-UNLOCK
  _SEM-EVT EVT-PULSE      \ wake one waiter
;
```

**Status:** ☐ Not started

---

### 1.3 rwlock.f — Reader-Writer Locks

**Depends on:** event.f, spinlocks

**Purpose:** Multiple concurrent readers OR one exclusive writer.
Critical for shared lookup tables (font cache, route table, hash
tables) that are read-heavy.

**Data structure — 5 cells = 40 bytes:**

| Offset | Field         | Description                     |
|--------|---------------|---------------------------------|
| +0     | readers       | Active reader count             |
| +8     | writer        | -1 if write-locked, 0 otherwise |
| +16    | lock#         | Spinlock number                 |
| +24    | read-event    | Event: readers can proceed      |
| +32    | write-event   | Event: writer can proceed       |

**Public API:**

| Word            | Signature          | Behavior                             |
|-----------------|--------------------|--------------------------------------|
| `RWLOCK`        | `( "name" -- )`    | Create a named reader-writer lock    |
| `READ-LOCK`     | `( rwl -- )`       | Acquire shared read access           |
| `READ-UNLOCK`   | `( rwl -- )`       | Release read access                  |
| `WRITE-LOCK`    | `( rwl -- )`       | Acquire exclusive write access       |
| `WRITE-UNLOCK`  | `( rwl -- )`       | Release write access                 |
| `WITH-READ`     | `( xt rwl -- )`    | Execute xt under read lock           |
| `WITH-WRITE`    | `( xt rwl -- )`    | Execute xt under write lock          |

**Status:** ☐ Not started

---

## Layer 2 — Communication

### 2.1 channel.f — Go-Style Bounded Channels

**Depends on:** ring buffers (§18), event.f

**Purpose:** CSP-style typed channels.  The primary inter-task
communication mechanism.  A channel is a RING buffer + two events
(not-full, not-empty).  Sending blocks if full; receiving blocks
if empty.

**Data structure:**

A `CHANNEL` wraps:
- A `RING` buffer (already lock-protected)
- An `evt-not-full` event (for senders)
- An `evt-not-empty` event (for receivers)
- A `closed` flag

**Public API:**

| Word             | Signature                        | Behavior                                     |
|------------------|----------------------------------|----------------------------------------------|
| `CHANNEL`        | `( cell-size capacity "name" -- )` | Create a bounded channel                   |
| `CHAN-SEND`       | `( val chan -- )`               | Send value; block if full                   |
| `CHAN-RECV`       | `( chan -- val )`               | Receive value; block if empty               |
| `CHAN-TRY-SEND`   | `( val chan -- flag )`          | Non-blocking send; TRUE if sent             |
| `CHAN-TRY-RECV`   | `( chan -- val flag )`          | Non-blocking receive                        |
| `CHAN-CLOSE`      | `( chan -- )`                   | Close channel; future sends fail            |
| `CHAN-CLOSED?`    | `( chan -- flag )`              | Is channel closed?                          |
| `CHAN-COUNT`      | `( chan -- n )`                 | Items currently buffered                    |
| `CHAN-SELECT`     | `( chan1 chan2 ... n -- idx val )` | Wait on N channels, return first ready    |

**Usage example:**

```forth
1 CELLS 8 CHANNEL work-queue
1 CELLS 8 CHANNEL results

: worker   BEGIN  work-queue CHAN-RECV  DUP 0= IF DROP EXIT THEN
           process-item  results CHAN-SEND  AGAIN ;

: fan-out  4 0 DO ['] worker SPAWN LOOP ;
```

**Implementation sketch:**

```forth
: CHAN-SEND  ( val chan -- )
  DUP CHAN-CLOSED? IF  2DROP -1 ABORT" send on closed channel"  THEN
  BEGIN
    DUP _CHAN-RING RING-FULL? 0= IF          \ room available
      SWAP OVER _CHAN-RING RING-PUSH DROP     \ push value
      _CHAN-EVT-NE EVT-SET  EXIT              \ signal not-empty
    THEN
    DUP _CHAN-EVT-NF EVT-WAIT                 \ wait for room
  AGAIN
;

: CHAN-RECV  ( chan -- val )
  BEGIN
    DUP _CHAN-RING RING-EMPTY? 0= IF          \ data available
      _CHAN-TMP OVER _CHAN-RING RING-POP DROP  \ pop value
      OVER _CHAN-EVT-NF EVT-SET               \ signal not-full
      _CHAN-TMP @  EXIT
    THEN
    DUP CHAN-CLOSED? IF  DROP 0 EXIT  THEN    \ closed + empty = done
    DUP _CHAN-EVT-NE EVT-WAIT                 \ wait for data
  AGAIN
;
```

**Status:** ☐ Not started

---

### 2.2 mailbox.f — Per-Task Actor Mailboxes

**Depends on:** ring buffers (§18), event.f

**Purpose:** Actor-style per-task mailboxes.  Lighter-weight than
channels when you need 1:1 task messaging.  Each task gets a
private inbox (a small ring buffer).

This extends (not replaces) the BIOS-level `MBOX@`/`MBOX!` which
are raw inter-core mailboxes.  Task-level mailboxes are per-task,
not per-core.

**Public API:**

| Word             | Signature               | Behavior                          |
|------------------|-------------------------|-----------------------------------|
| `MBOX-INIT`      | `( task# -- )`          | Initialize mailbox for task       |
| `MBOX-SEND`      | `( msg task# -- flag )` | Send message to task's mailbox    |
| `MBOX-RECV`      | `( -- msg )`            | Receive from own mailbox (blocks) |
| `MBOX-TRY-RECV`  | `( -- msg flag )`       | Non-blocking receive              |
| `MBOX-EMPTY?`    | `( -- flag )`           | Check own mailbox                 |

**Status:** ☐ Not started

---

## Layer 3 — Futures & Async Patterns

### 3.1 future.f — Promises and ASYNC/AWAIT

**Depends on:** event.f, §8 scheduler (SPAWN)

**Purpose:** Futures/promises for async result passing.  `ASYNC`
spawns a task and returns a promise.  `AWAIT` blocks until the
promise is fulfilled.

**Data structure — 3 cells = 24 bytes:**

| Offset | Field    | Description                        |
|--------|----------|------------------------------------|
| +0     | value    | Result value (valid after resolve) |
| +8     | resolved | 0 = pending, -1 = resolved         |
| +16    | event    | Embedded event for waiters         |

**Public API:**

| Word              | Signature              | Behavior                                    |
|-------------------|------------------------|---------------------------------------------|
| `PROMISE`         | `( -- promise )`       | Allocate a promise (one-write cell + event) |
| `FULFILL`         | `( val promise -- )`   | Write result, signal waiters                |
| `AWAIT`           | `( promise -- val )`   | Block until fulfilled, return value         |
| `AWAIT-TIMEOUT`   | `( promise ms -- v f)` | Wait with timeout; TRUE if resolved         |
| `RESOLVED?`       | `( promise -- flag )`  | Has the promise been fulfilled?             |
| `ASYNC`           | `( xt -- promise )`    | SPAWN task, return promise for xt's result  |

**Usage example:**

```forth
\ Launch parallel work, collect results
['] compute-hash ASYNC   ( -- p1 )
['] fetch-data   ASYNC   ( -- p1 p2 )
SWAP AWAIT               ( -- p2 hash )
SWAP AWAIT               ( -- hash data )
combine-results
```

**Implementation sketch:**

```forth
: ASYNC  ( xt -- promise )
  PROMISE >R
  R@ SWAP                     \ ( promise xt )
  [: ( promise xt -- )
    EXECUTE                    \ run the xt, leaves result on stack
    SWAP FULFILL               \ fulfill the promise
  ;] SWAP CURRY               \ create closure with promise+xt
  SPAWN                        \ spawn the closure as a task
  R>                           \ return the promise
;

: AWAIT  ( promise -- val )
  DUP RESOLVED? IF  @ EXIT  THEN
  DUP 16 + EVT-WAIT           \ wait on embedded event
  @                            \ read value
;
```

Note: `CURRY` / closure creation may require a small trampoline
allocation.  Alternative: use a shared variable indexed by promise
address to bind xt + promise, avoiding heap allocation.

**Status:** ☐ Not started

---

### 3.2 par.f — Parallel Combinators

**Depends on:** future.f, §8.1 multicore dispatch, §8.4 core affinity

**Purpose:** Structured parallel operations over arrays and ranges.
Automatically divides work across available cores.

**Public API:**

| Word            | Signature                           | Behavior                                    |
|-----------------|-------------------------------------|---------------------------------------------|
| `PAR-DO`        | `( xt1 xt2 -- )`                   | Run two XTs in parallel, wait for both      |
| `PAR-MAP`       | `( xt addr count -- )`             | Apply xt to each element across cores       |
| `PAR-REDUCE`    | `( xt identity addr count -- val)` | Parallel reduction (fold)                   |
| `PAR-FOR`       | `( xt lo hi -- )`                  | Parallel FOR loop (range divided by cores)  |
| `PAR-SCATTER`   | `( src-addr chunk count -- )`      | Distribute data chunks to core arenas       |
| `PAR-GATHER`    | `( dest-addr count -- )`           | Collect results from core arenas            |

**Usage example:**

```forth
\ Parallel sum of 1024 elements
['] + 0 data-array 1024 PAR-REDUCE  .

\ Parallel FOR: process indices 0..999
[: ( i -- ) DUP cells data-array + @ process ;] 0 1000 PAR-FOR
```

**Implementation notes:**

- `PAR-MAP` divides the array into `NCORES` chunks, uses `SPAWN-ON`
  to dispatch each chunk to a core, then `BARRIER`.
- `PAR-REDUCE` does per-core local reductions in parallel, then a
  final sequential reduction of per-core results on core 0.
- Uses per-core arenas for intermediate storage — no heap contention.

**Status:** ☐ Not started

---

## Layer 4 — Structured Concurrency

### 4.1 scope.f — Task Groups and Lifetimes

**Depends on:** event.f, §8 scheduler

**Purpose:** Structured concurrency / nurseries.  Every task
belongs to a group, and groups enforce
parent-waits-for-children semantics.  Prevents orphaned tasks.

**Data structure — Task Group (5 cells = 40 bytes):**

| Offset | Field       | Description                      |
|--------|-------------|----------------------------------|
| +0     | active      | Number of active tasks in group  |
| +8     | cancelled   | -1 if group cancelled, 0 normal  |
| +16    | done-event  | Event signaled when active → 0   |
| +24    | error       | First error code (0 = none)      |
| +32    | name        | Pointer to name string           |

**Public API:**

| Word            | Signature           | Behavior                                         |
|-----------------|---------------------|--------------------------------------------------|
| `TASK-GROUP`    | `( "name" -- )`     | Create a named task group                        |
| `TG-SPAWN`      | `( xt tg -- )`     | Spawn task into group                            |
| `TG-WAIT`       | `( tg -- )`        | Block until all tasks in group complete           |
| `TG-CANCEL`     | `( tg -- )`        | Kill all tasks in group                          |
| `TG-ANY`        | `( tg -- val )`    | Wait for first task to finish, cancel rest       |
| `TG-COUNT`      | `( tg -- n )`      | Number of active tasks                           |
| `WITH-TASKS`    | `( xt -- )`        | Create anon group, run xt, wait for all children |

**Usage example:**

```forth
: parallel-fetch
  [: ( -- )
    ['] fetch-users  THIS-GROUP TG-SPAWN
    ['] fetch-posts  THIS-GROUP TG-SPAWN
    ['] fetch-config THIS-GROUP TG-SPAWN
  ;] WITH-TASKS    \ automatically waits for all 3, cleans up
;
```

**Status:** ☐ Not started

---

## Layer 5 — Concurrent Data Structures

### 5.1 cvar.f — Concurrent Variables

**Depends on:** event.f, spinlocks

**Purpose:** Atomic cells with change notification.  A concurrent
variable wraps a memory cell with atomic read/write, compare-and-swap,
and wait-for-change semantics.

**Public API:**

| Word         | Signature                     | Behavior                              |
|--------------|-------------------------------|---------------------------------------|
| `CVAR`       | `( initial "name" -- )`       | Create a concurrent variable          |
| `CV@`        | `( cvar -- val )`             | Atomic read                           |
| `CV!`        | `( val cvar -- )`             | Atomic write + notify waiters         |
| `CV-CAS`     | `( expected new cvar -- flag )` | Compare-and-swap                    |
| `CV-WAIT`    | `( expected cvar -- )`        | Block until value ≠ expected          |
| `CV-ADD`     | `( n cvar -- )`               | Atomic fetch-and-add                  |

```forth
\ Example: atomic counter
0 CVAR request-count
: bump-count  1 request-count CV-ADD ;
```

**Status:** ☐ Not started

---

### 5.2 conc-map.f — Concurrent Hash Map

**Depends on:** §19 hash tables, rwlock.f

**Purpose:** Extends the existing hash table subsystem with
finer-grained locking.  Uses per-bucket RW locks (hashed to
available spinlocks modulo 8, or software spinlocks for more
buckets).

**Public API:**

| Word         | Signature                | Behavior                             |
|--------------|--------------------------|--------------------------------------|
| `CMAP`       | `( buckets "name" -- )`  | Create concurrent map                |
| `CMAP-PUT`   | `( val key cmap -- )`    | Thread-safe insert/update            |
| `CMAP-GET`   | `( key cmap -- val flag )`| Lock-free read                      |
| `CMAP-DEL`   | `( key cmap -- flag )`   | Thread-safe delete                   |
| `CMAP-EACH`  | `( xt cmap -- )`         | Iterate (snapshot semantics)         |

**Status:** ☐ Not started

---

## Dependency Graph

```
        ┌───────────────────────────────────────────────┐
        │          KDOS §8 Scheduler + Spinlocks        │
        │          §18 Ring Buffers   §19 Hash Tables   │
        │          BIOS: SPIN@ WAKE-CORE COREID         │
        └──────────────────┬────────────────────────────┘
                           │
                    ┌──────┴──────┐
                    │  event.f    │  ← everything depends on this
                    └──┬───┬──┬──┘
           ┌───────────┤   │  └────────────┐
           ▼           ▼   │               ▼
     semaphore.f   rwlock.f│          cvar.f
           │           │   │               │
           │           │   │               ▼
           │           ▼   │         conc-map.f
           │      (used by │          (§19 + rwlock)
           │       layer 5)│
           │               │
           ▼               ▼
      channel.f        mailbox.f
      (ring + evt)     (ring + evt)
           │
           ▼
       future.f
       (evt + spawn)
           │
      ┌────┴────┐
      ▼         ▼
   par.f     scope.f
  (future    (evt + task
  + cores)    groups)
```

---

## Implementation Order

Priority order, highest-impact first:

| #  | File         | Layer | Why First                                          | Status |
|----|--------------|-------|----------------------------------------------------|--------|
| 1  | event.f      | 1     | Everything else depends on wait/notify             | ✅     |
| 2  | channel.f    | 2     | Unlocks CSP; makes web server concurrent trivially | ☐      |
| 3  | future.f     | 3     | Most ergonomic async API (ASYNC/AWAIT)             | ☐      |
| 4  | semaphore.f  | 1     | Rate-limiting, resource counting                   | ☐      |
| 5  | par.f        | 3     | Parallel map/reduce for math workloads             | ☐      |
| 6  | scope.f      | 4     | Structured concurrency prevents leaks              | ☐      |
| 7  | cvar.f       | 5     | Atomic variables with change notification          | ☐      |
| 8  | rwlock.f     | 1     | Read-heavy shared structures                       | ☐      |
| 9  | mailbox.f    | 2     | Actor messaging (lower priority than channels)     | ☐      |
| 10 | conc-map.f   | 5     | Fine-grained concurrent hash map                   | ☐      |

---

## Design Constraints & Gotchas

### 8-Task Slot Limit

The task registry holds 8 slots.  `ASYNC` and `TG-SPAWN` can exhaust
this quickly.  Mitigations:

1. **Task pool** — recycle DONE slots lazily before allocating new
2. **Run queues** — use `RQ-PUSH` directly (no slot limit) for
   fire-and-forget work; reserve task slots for work that needs
   AWAIT or lifetime tracking
3. **Grow the table** — bump to 16 or 32 slots (costs 48 bytes each)

### 8 Hardware Spinlocks

The hardware provides exactly 8 MMIO spinlocks.  6 are already
assigned (dict, uart, fs, heap, ring, hash tables, IPI).  For
finer-grained locking (per-bucket hash maps, per-channel):

- **Software spinlocks** — CAS loop on a regular memory cell:
  ```forth
  : SOFT-LOCK   ( addr -- )  BEGIN  0 -1 ROT CAS  UNTIL ;
  : SOFT-UNLOCK ( addr -- )  0 SWAP ! ;
  ```
  (Requires a CAS primitive — can be built from `SPIN@`/`SPIN!`
  guarding a memory cell, or added as a BIOS word.)

### Non-Re-Entrant FP16

Math modules (`fp16.f`, `mat2d.f`) use shared VARIABLEs and are
**not re-entrant**.  Concurrent math requires:

- Per-core scratch areas (already exist via arenas)
- `WITH-LOCK` around FP16 operations, OR
- Pure-stack versions of FP16 words (no shared state)

### Closure / Curry Problem

`ASYNC` needs to bind a promise to an XT.  KDOS doesn't have closures.
Options:

- **Trampoline word** — compile a small anonymous definition that
  references the promise via a literal:
  ```forth
  : ASYNC  ( xt -- promise )
    PROMISE >R  HERE  R@ LITERAL,  SWAP COMPILE,
    ['] FULFILL COMPILE,  POSTPONE ;
    LATEST SPAWN  R>
  ;
  ```
- **Shared binding table** — index promises by task slot number
  (simpler, no codegen, limited to 8 concurrent ASYNCs)

### Timeout Implementation

`EVT-WAIT-TIMEOUT` needs a time source.  KDOS has:

- `TIMER@` — 64-bit cycle counter
- `MS` — millisecond delay word
- `TICKS` — system tick counter

Timeout = record `TIMER@` at entry, check elapsed on each YIELD
iteration.

---

## Testing Strategy

### Unit Tests (Python emulator)

Each module gets a `test_<module>.py` in `local_testing/`:

- **test_event.py** — create events, set/wait/reset/pulse, verify
  task blocking/waking, timeout behavior
- **test_channel.py** — bounded send/recv, blocking on full/empty,
  close semantics, select
- **test_future.py** — ASYNC/AWAIT, timeout, multiple awaiters
- **test_semaphore.py** — counting up/down, try-wait, blocking
- **test_par.py** — PAR-MAP/REDUCE correctness vs sequential

### Integration Tests

- **Concurrent web server** — spawn N worker tasks, fan-out
  incoming connections via channel, verify correct responses
- **Producer-consumer pipeline** — multiple producers → channel →
  multiple consumers → results channel → collector
- **Work stealing under load** — saturate queues, verify balance

### Stress Tests

- **Task exhaustion** — spawn until slots full, verify graceful error
- **Spinlock contention** — multiple cores competing for same lock
- **Channel backpressure** — fast producer, slow consumer

---
