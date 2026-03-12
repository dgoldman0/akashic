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
- [Layer 6 — Guards & Critical Sections](#layer-6--guards--critical-sections)
  - [6.1 guard.f — Non-Reentrant Guards](#61-guardf--non-reentrant-guards)
  - [6.2 critical.f — Critical Sections & Preemption Control](#62-criticalf--critical-sections--preemption-control)
- [Dependency Graph](#dependency-graph)
- [Implementation Order](#implementation-order)
- [Design Constraints & Gotchas](#design-constraints--gotchas)
- [Testing Strategy](#testing-strategy)
- [Hardening — Making Akashic Libraries Concurrency-Safe](#hardening--making-akashic-libraries-concurrency-safe)
  - [The Problem](#the-problem)
  - [Execution Context Analysis](#execution-context-analysis)
  - [Strategy — Layered Approach](#strategy--layered-approach)
  - [New Defining Words — core-local.f](#new-defining-words--core-localf)
  - [Module Classification](#module-classification)
  - [Transformation Recipe](#transformation-recipe)
  - [Invariants & Constraints](#invariants--constraints)
  - [Hardening Implementation Order](#hardening-implementation-order)
- [BIOS SEP Dispatch Refactor — Status: Landed](#bios-sep-dispatch-refactor--status-landed)

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

### BIOS-Level Hardware Coroutine Pair (SEP Dispatch Phase 8)

> **Status:** Landed.  Available in BIOS v1.0 since the SEP dispatch
> refactor (phases 0–9 all complete).

The BIOS exposes a **2-task hardware coroutine** mechanism using the
1802 SEP instruction.  Task 0 runs in R3 (the Forth inner interpreter),
Task 1 runs in R13.  Context-switching is a single `SEP` instruction —
1 cycle, 0 bytes of memory traffic, no task control blocks.

This is **not** a scheduler.  It is a register-file ping-pong: one
foreground task and one background task, cooperatively yielding via
`PAUSE`.

| Word          | Signature        | Behavior                                    |
|---------------|------------------|---------------------------------------------|
| `PAUSE`       | `( -- )`         | Task 0 → Task 1 (no-op if none)            |
| `TASK-YIELD`  | `( -- )`         | Task 1 → Task 0                            |
| `BACKGROUND`  | `( xt -- )`      | Install xt as Task 1 and start it           |
| `TASK-STOP`   | `( -- )`         | Halt Task 1                                 |
| `TASK?`       | `( -- flag )`    | 1 if active, 0 if stopped                   |

**Key constraints:**
- Only **one** background slot (R13).  For >2 tasks, use the KDOS §8
  scheduler.
- Fully cooperative — no preemption, no priority.
- Task 1 shares the same address space / dictionary as Task 0.
- Micro-cores now have SEP/SEX decode (zero area cost) but still lack
  Q flip-flop, so EMIT-based I/O in a background task would trap on
  micro-cores.

**Relationship to KDOS scheduler:**
- BIOS `PAUSE` and KDOS `YIELD?` are **independent mechanisms**.
  `PAUSE` swaps register files; `YIELD?` checks `PREEMPT-FLAG` and
  round-robins the §8 task table.
- They can coexist: a KDOS task can call `PAUSE` to ping-pong with a
  background helper, while the KDOS scheduler manages the broader task
  set on Task 0.
- BIOS `YIELD` (dict #309) is a naming collision with KDOS `YIELD`
  (marks current task as `T.DONE`).  In practice they have different
  stack effects so the dictionary ordering resolves it, but this
  should be documented clearly.

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
- **Non-reentrant guards** — declarative word-level mutual exclusion
- **Critical sections** — scoped preemption-safe regions
- **Hardware coroutine wrappers** — structured use of the BIOS
  BACKGROUND/PAUSE 2-task pair for I/O decoupling

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

**Status:** ✅ Done — `akashic/concurrency/semaphore.f`

---

### 1.3 rwlock.f — Reader-Writer Locks

**Depends on:** event.f, spinlocks

**Purpose:** Multiple concurrent readers OR one exclusive writer.
Critical for shared lookup tables (font cache, route table, hash
tables) that are read-heavy.

**Data structure — 11 cells = 88 bytes:**

Events are embedded inline (same pattern as semaphore.f) for
zero-indirection access.  Each rwlock carries its own spinlock
number so that unrelated rwlocks do not contend on the same
hardware spinlock during state transitions.

| Offset | Field         | Size    | Description                          |
|--------|---------------|---------|--------------------------------------|
| +0     | lock#         | 1 cell  | Per-lock spinlock number             |
| +8     | readers       | 1 cell  | Active reader count                  |
| +16    | writer        | 1 cell  | -1 if write-locked, 0 otherwise      |
| +24    | read-event    | 4 cells | Embedded EVENT: pulsed when writer   |
|        |               | (32 B)  | unlocks, waking blocked readers      |
| +56    | write-event   | 4 cells | Embedded EVENT: pulsed when last     |
|        |               | (32 B)  | reader or writer unlocks, waking     |
|        |               |         | a blocked writer                     |

**Notes on lock# field:**
- KDOS currently has 8 hardware spinlocks (0–7), but this limit
  is expected to be revised by the KDOS team.
- Callers pass a spinlock number at creation time.
- EVT-LOCK (6) is a reasonable default when no dedicated spinlock
  is available.  Multiple rwlocks can share the same spinlock
  number — correctness is preserved, only contention increases.

**Public API:**

| Word            | Signature               | Behavior                             |
|-----------------|-------------------------|--------------------------------------|
| `RWLOCK`        | `( lock# "name" -- )`   | Create a named reader-writer lock    |
| `READ-LOCK`     | `( rwl -- )`            | Acquire shared read access           |
| `READ-UNLOCK`   | `( rwl -- )`            | Release read access                  |
| `WRITE-LOCK`    | `( rwl -- )`            | Acquire exclusive write access       |
| `WRITE-UNLOCK`  | `( rwl -- )`            | Release write access                 |
| `WITH-READ`     | `( xt rwl -- )`         | Execute xt under read lock (RAII)    |
| `WITH-WRITE`    | `( xt rwl -- )`         | Execute xt under write lock (RAII)   |
| `RW-INFO`       | `( rwl -- )`            | Debug: print lock state              |

**Status:** ✅ Complete

---

## Layer 2 — Communication

### 2.1 channel.f — Go-Style Bounded Channels

**Depends on:** event.f

**Purpose:** CSP-style bounded channels.  The primary inter-task
communication mechanism.  A channel embeds an inline circular buffer
+ two events (not-full, not-empty).  Sending blocks if full;
receiving blocks if empty.

**Design decisions (approved):**
- **Custom inline ring ops** — direct `!`/`@`/`CMOVE` under the
  channel's own spinlock.  Does NOT use RING-PUSH/RING-POP (avoids
  double-locking and the global `_RP-RING` variable multi-core issue).
- **Per-channel lock#** — like rwlock.f.  Reduces contention vs.
  sharing EVT-LOCK across all channels.
- **1-cell default + addr-variants** — `CHAN-SEND`/`CHAN-RECV` for
  single 64-bit cell values.  `CHAN-SEND-BUF`/`CHAN-RECV-BUF` for
  arbitrary elem-size (addr-based, uses CMOVE).
- **CHAN-SELECT included** — polls N channels using `CHAN-TRY-RECV`
  in a YIELD? loop.

**Data structure — 15 cells = 120 bytes + data area:**

```
+0    lock#       per-channel spinlock number          (1 cell)
+8    closed      0 | -1                               (1 cell)
+16   elem-size   bytes per element                    (1 cell)
+24   capacity    max elements                         (1 cell)
+32   head        read index                           (1 cell)
+40   tail        write index                          (1 cell)
+48   count       current elements                     (1 cell)
+56   evt-nf      not-full event   (4 cells = 32 B)   (+56..+80)
+88   evt-ne      not-empty event  (4 cells = 32 B)   (+88..+112)
+120  data...     capacity × elem-size bytes
```

**Public API:**

| Word             | Signature                           | Behavior                                     |
|------------------|-------------------------------------|----------------------------------------------|
| `CHANNEL`        | `( lock# elem-size capacity "name" -- )` | Create a bounded channel              |
| `CHAN-SEND`       | `( val chan -- )`                  | Send 1-cell value; block if full             |
| `CHAN-RECV`       | `( chan -- val )`                  | Receive 1-cell value; block if empty         |
| `CHAN-TRY-SEND`   | `( val chan -- flag )`            | Non-blocking 1-cell send                     |
| `CHAN-TRY-RECV`   | `( chan -- val flag )`            | Non-blocking 1-cell receive                  |
| `CHAN-SEND-BUF`   | `( addr chan -- )`               | Send elem-size bytes from addr; blocking     |
| `CHAN-RECV-BUF`   | `( addr chan -- )`               | Receive elem-size bytes to addr; blocking    |
| `CHAN-CLOSE`      | `( chan -- )`                     | Close channel; future sends fail             |
| `CHAN-CLOSED?`    | `( chan -- flag )`                | Is channel closed?                           |
| `CHAN-COUNT`      | `( chan -- n )`                   | Items currently buffered                     |
| `CHAN-SELECT`     | `( chan1 chan2 ... n -- idx val )` | Wait on N channels; return first ready       |
| `CHAN-INFO`       | `( chan -- )`                     | Debug print (UART)                           |

**Closed-channel semantics:**
- `CHAN-SEND` on a closed channel: `-1 THROW`
- `CHAN-RECV` on a closed + empty channel: returns 0
- `CHAN-TRY-RECV` on closed + empty: returns `( 0 0 )`
- `CHAN-SELECT` when all channels closed + empty: returns `( -1 0 )`

**Usage example:**

```forth
6 1 CELLS 8 CHANNEL work-queue
6 1 CELLS 8 CHANNEL results

: worker   BEGIN  work-queue CHAN-RECV  DUP 0= IF DROP EXIT THEN
           process-item  results CHAN-SEND  AGAIN ;

: fan-out  4 0 DO ['] worker SPAWN LOOP ;
```

**Implementation sketch:**

```forth
: _CHAN-PUSH-CELL  ( val chan -- )       \ caller must hold lock
    >R
    R@ _CHAN-TAIL @ R@ _CHAN-ESIZE @ * R@ _CHAN-DATA + !  \ store val
    R@ _CHAN-TAIL @ 1+ R@ _CHAN-CAP @ MOD R@ _CHAN-TAIL !
    1 R> _CHAN-COUNT-ADDR +! ;

: CHAN-SEND  ( val chan -- )
    DUP CHAN-CLOSED? IF -1 THROW THEN
    BEGIN
        DUP _CHAN-FULL? 0= IF
            DUP _CHAN-LOCK# @ LOCK
            DUP _CHAN-FULL? 0= IF            \ re-check under lock
                SWAP OVER _CHAN-PUSH-CELL
                DUP _CHAN-LOCK# @ UNLOCK
                _CHAN-EVT-NE EVT-SET  EXIT
            THEN
            DUP _CHAN-LOCK# @ UNLOCK
        THEN
        DUP _CHAN-EVT-NF EVT-WAIT
    AGAIN ;
```

**Status:** ✅ Done — channel.f + channel.md + test_channel.py (50 tests)

---

### 2.2 mailbox.f — Per-Task Actor Mailboxes

**Status:** ⏭ Deferred — channels subsume this use case.

`channel.f` already provides everything mailboxes would:
bounded buffering, blocking send/recv, non-blocking try variants,
SELECT for multiplexing.  The only thing mailbox adds is implicit
"my inbox" lookup via CURRENT-TASK, which couples tightly to the
KDOS task-identity model (hardcoded 8-slot TASK-TABLE with no
`MAX-TASKS` constant to query).  Not worth the coupling until
KDOS stabilizes its task model.

If actor-style messaging is needed, pass channel addresses explicitly.
Revisit if/when KDOS exposes `MAX-TASKS` and the task table grows.

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

Note: The FIFO binding table approach avoids closures entirely.
`ASYNC` stores (xt, promise) in a circular 8-slot table;
`_FUT-RUNNER` reads bindings in FIFO order.  Cooperative
scheduling guarantees all writes complete before any runner
executes.

**Status:** ✅ Done — `akashic/concurrency/future.f` + `future.md` + `test_future.py` (51 tests)

---

### 3.2 par.f — Parallel Combinators

**Depends on:** future.f, §8.1 multicore dispatch, §8.4 core affinity

**Purpose:** Structured parallel operations over arrays and ranges.
Automatically divides work across available cores.

**Public API:**

| Word            | Signature                           | Behavior                                    |
|-----------------|-------------------------------------|---------------------------------------------|
| `PAR-USE-FULL`  | `( -- )`                            | Use full cores only (default, safe)         |
| `PAR-USE-ALL`   | `( -- )`                            | Use all cores incl. micro-cores             |
| `PAR-CORES`     | `( -- n )`                          | Query active core count                     |
| `PAR-DO`        | `( xt1 xt2 -- )`                   | Run two XTs in parallel, wait for both      |
| `PAR-MAP`       | `( xt addr count -- )`             | Apply xt to each element across cores       |
| `PAR-REDUCE`    | `( xt identity addr count -- val)` | Parallel reduction (fold)                   |
| `PAR-FOR`       | `( xt lo hi -- )`                  | Parallel FOR loop (range divided by cores)  |
| `PAR-SCATTER`   | `( src-addr chunk count -- )`      | Distribute data chunks to core arenas       |
| `PAR-GATHER`    | `( dest-addr count -- )`           | Collect results from core arenas            |
| `PAR-INFO`      | `( -- )`                            | Debug display (shows core types)            |

**Usage example:**

```forth
\ Parallel sum of 1024 elements
['] + 0 data-array 1024 PAR-REDUCE  .

\ Parallel FOR: process indices 0..999
[: ( i -- ) DUP cells data-array + @ process ;] 0 1000 PAR-FOR
```

**Implementation notes:**

- Core-type aware: defaults to `N-FULL` (full cores only); `PAR-USE-ALL`
  opts in to micro-cores for scalar-only workloads.
- `PAR-MAP` divides the array into `PAR-CORES` chunks, dispatches
  each chunk to a core via `CORE-RUN`, then `BARRIER`.
- `PAR-REDUCE` does per-core local reductions in parallel, then a
  final sequential reduction of per-core results on core 0.
- Uses static per-core parameter tables — no heap contention.
- Workers avoid return-stack values across `DO..LOOP` (re-read from
  per-core tables via `COREID` instead).
- All loops that may have zero iterations use `?DO` (not `DO`).

**Status:** ✅ Done — `akashic/concurrency/par.f` + `par.md` + `test_par.py` (38 tests)

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

**Status:** ✅ Done — `akashic/concurrency/scope.f` + `scope.md` + `test_scope.py` (42 tests)

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

**Status:** ✅ Done — `akashic/concurrency/cvar.f` + `cvar.md` + `test_cvar.py` (35 tests)

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

**Status:** ✅ Done — `akashic/concurrency/conc-map.f` + `conc-map.md` + `test_conc_map.py` (26 tests)

---

## Layer 6 — Guards & Critical Sections

Modules like `fp16.f`, `mat2d.f`, `merkle.f`, and any future MMIO
wrapper use shared `VARIABLE`s or shared hardware state that is
**not re-entrant**.  Today the answer is "wrap with `WITH-LOCK`",
but that pushes the burden onto every call site.  Layer 6 provides
declarative, word-level primitives so a module author can mark a
word as non-reentrant at definition time and have the runtime
enforce it.

### 6.1 guard.f — Non-Reentrant Guards

**File:** `akashic/concurrency/guard.f`
**Prefix:** `GUARD-`
**Depends on:** spinlocks (`LOCK`/`UNLOCK`), semaphore.f (for
blocking variant)
**Est.:** ~80 lines

A **guard** is a named mutual-exclusion wrapper that a module author
attaches to words at compile time.  Any word defined between
`GUARD-BEGIN` and `GUARD-END` automatically acquires the guard on
entry and releases it on exit (including early `EXIT` and `ABORT`).

| # | Item | Est. | Status |
|---|------|------|--------|
| 6a | **Guard creation** — `GUARD` defining word creates a guard object (lock cell + owner cell + optional spinlock#) | ~15 lines | ☐ |
| 6b | **Scoped acquire/release** — `GUARD-BEGIN` / `GUARD-END` bracket a region of colon definitions; every `:` inside compiles acquire on entry, release before `;` | ~25 lines | ☐ |
| 6c | **Manual acquire** — `GUARD-ACQUIRE` / `GUARD-RELEASE` for cases where `GUARD-BEGIN`/`GUARD-END` scope doesn't fit | ~10 lines | ☐ |
| 6d | **WITH-GUARD** — `( xt guard -- )` RAII-style execute-under-guard | ~10 lines | ☐ |
| 6e | **Deadlock detection** — if the same task re-enters a guard, ABORT instead of deadlock (owner cell check) | ~10 lines | ☐ |
| 6f | **Blocking variant** — `GUARD-BLOCKING` creates a guard backed by a 1-count semaphore instead of a spinlock (yields instead of busy-waits) | ~10 lines | ☐ |

#### Forth Sketch

```forth
REQUIRE concurrency/semaphore.f

\ --- guard object: 3 cells (lock-flag, owner-task, 0=spin|1=blocking) ---
: GUARD  ( "name" -- )
    CREATE  0 , -1 , 0 ,  ;          \ flag=free, owner=none, mode=spin

: GUARD-BLOCKING  ( "name" -- )
    CREATE  0 , -1 , 1 ,             \ mode=blocking
    1 SEMAPHORE                       \ inline semaphore for blocking waits
;

: GUARD-ACQUIRE  ( guard -- )
    DUP CELL+ @ CURRENT-TASK = IF
        ABORT" GUARD: re-entry detected"
    THEN
    DUP 2 CELLS + @ IF               \ blocking mode?
        DUP 3 CELLS + SEM-WAIT       \ yield-wait on semaphore
    ELSE
        BEGIN  DUP @  0= UNTIL        \ spin on flag cell
        -1 OVER !                     \ claim it
    THEN
    CURRENT-TASK SWAP CELL+ ! ;       \ record owner

: GUARD-RELEASE  ( guard -- )
    -1 OVER CELL+ !                   \ clear owner
    DUP 2 CELLS + @ IF
        DUP 3 CELLS + SEM-SIGNAL
    ELSE
        0 SWAP !
    THEN ;

: WITH-GUARD  ( xt guard -- )
    DUP >R  GUARD-ACQUIRE
    SWAP EXECUTE
    R> GUARD-RELEASE ;

\ --- declarative scope for module authors ---
VARIABLE _guard-current   \ active guard during GUARD-BEGIN region

: GUARD-BEGIN  ( guard -- )  _guard-current ! ;

\ A redefined `:` that wraps every word with guard acquire/release:
\ (the actual implementation would use POSTPONE to compile the
\  acquire/release into each word's thread)
: GUARD-END  ( -- )  -1 _guard-current ! ;
```

#### Usage Example

```forth
GUARD fp16-guard

fp16-guard GUARD-BEGIN

: MY-FP16-OP  ( x y -- z )
    \ guard auto-acquired here
    FP16+ FP16*
    \ guard auto-released here
;

GUARD-END

\ Or manual:
' MY-FP16-OP  fp16-guard WITH-GUARD
```

#### Definition of Done

- Guard acquire/release verified under concurrent tasks
- Re-entry detected and ABORTs (not deadlock)
- `WITH-GUARD` executes xt under guard
- Blocking variant yields instead of spinning
- Two tasks racing the same guarded word: one blocks, other proceeds

---

### 6.2 critical.f — Critical Sections & Preemption Control

**File:** `akashic/concurrency/critical.f`
**Prefix:** `CRIT-`
**Depends on:** KDOS `PREEMPT-OFF`/`PREEMPT-ON`, spinlocks
**Est.:** ~50 lines

Critical sections combine preemption suppression with optional mutual
exclusion.  For code that must not be interrupted or re-scheduled
(MMIO register sequences, multi-step hardware operations), this is
the correct primitive.

| # | Item | Est. | Status |
|---|------|------|--------|
| 6g | **Preemption-safe region** — `CRITICAL-BEGIN` / `CRITICAL-END` disable preemption for the current core, nest correctly (reference-counted) | ~15 lines | ✅ |
| 6h | **Locked critical section** — `CRITICAL-LOCK` / `CRITICAL-UNLOCK` combines preemption disable + spinlock acquire (for multicore safety) | ~15 lines | ✅ |
| 6i | **WITH-CRITICAL** — `( xt -- )` execute xt with preemption disabled | ~10 lines | ✅ |
| 6j | **WITH-CRITICAL-LOCK** — `( xt lock# -- )` preemption off + spinlock + execute + unlock + preemption on | ~10 lines | ✅ |

#### Forth Sketch

```forth
VARIABLE _crit-depth   \ nesting depth (per-core in multicore)

: CRITICAL-BEGIN  ( -- )
    _crit-depth @ 0= IF PREEMPT-OFF THEN
    1 _crit-depth +! ;

: CRITICAL-END  ( -- )
    _crit-depth @ 1- DUP _crit-depth !
    0= IF PREEMPT-ON THEN ;

: WITH-CRITICAL  ( xt -- )
    CRITICAL-BEGIN  EXECUTE  CRITICAL-END ;

: CRITICAL-LOCK  ( lock# -- )
    CRITICAL-BEGIN  LOCK ;

: CRITICAL-UNLOCK  ( lock# -- )
    UNLOCK  CRITICAL-END ;

: WITH-CRITICAL-LOCK  ( xt lock# -- )
    CRITICAL-LOCK
    SWAP EXECUTE
    CRITICAL-UNLOCK ;
```

#### Usage Example

```forth
\ Multi-step MMIO sequence that must not be preempted
: NTT-LOAD-AND-TRANSFORM  ( addr -- )
    ['] _ntt-load-xform  WITH-CRITICAL ;

\ Multicore-safe filesystem operation
: SAFE-FWRITE  ( buf len fd -- )
    ['] _do-fwrite  2 WITH-CRITICAL-LOCK ;  \ spinlock 2 = FS
```

#### Definition of Done

- `CRITICAL-BEGIN` / `CRITICAL-END` nest correctly (depth counter)
- Preemption is off inside, restored on exit
- `WITH-CRITICAL-LOCK` holds spinlock + preemption off for duration
- Nesting two critical sections doesn't re-enable preemption early

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

  guard.f ←── semaphore.f (blocking variant), spinlocks
  critical.f ←── PREEMPT-OFF/ON, spinlocks
```

---

## Implementation Order

Priority order, highest-impact first:

| #  | File         | Layer | Why First                                          | Status |
|----|--------------|-------|----------------------------------------------------|--------|
| 1  | event.f      | 1     | Everything else depends on wait/notify             | ✅     |
| 2  | channel.f    | 2     | Unlocks CSP; makes web server concurrent trivially | ✅     |
| 3  | future.f     | 3     | Most ergonomic async API (ASYNC/AWAIT)             | ✅     |
| 4  | semaphore.f  | 1     | Rate-limiting, resource counting                   | ✅     |
| 5  | par.f        | 3     | Parallel map/reduce for math workloads             | ✅     |
| 6  | scope.f      | 4     | Structured concurrency prevents leaks              | ✅     |
| 7  | cvar.f       | 5     | Atomic variables with change notification          | ✅     |
| 8  | rwlock.f     | 1     | Read-heavy shared structures                       | ✅     |
| 9  | mailbox.f    | 2     | Actor messaging — deferred (channels subsume)      | ⏭     |
| 10 | conc-map.f   | 5     | Fine-grained concurrent hash map                   | ✅     |
| 11 | guard.f      | 6     | Non-reentrant guards for shared-state modules      | ✅     |
| 12 | critical.f   | 6     | Critical sections + preemption control             | ✅     |
| 13 | coroutine.f  | 0     | Structured wrappers for BIOS BACKGROUND/PAUSE pair | ✅     |

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

## Hardening — Making Akashic Libraries Concurrency-Safe

### The Problem

Akashic library modules use global `VARIABLE`s for intermediate scratch
state — this is the standard Forth convention on this platform (limited
return stack, no locals).  Examples:

| Module     | Scratch vars                                         |
|------------|------------------------------------------------------|
| vec2.f     | `_V2-A`, `_V2-B`, `_V2-C`, `_V2-D`, `_V2L-T`, etc. |
| trig.f     | `_TR-QUAD`, `_TR-RED`, `_TR-SWAP`, `_TR-X2`         |
| fp32.f     | `_FP32-` temporaries for add/sub/mul/div             |
| mat2d.f    | `_M-A` through `_M-F` matrix element scratch         |
| string.f   | `_SS-SA`, `_SS-SL`, `_SS-PA`, `_SS-PL`, etc.        |
| sha3.f     | `_SHA3-IPAD` (136 B), `_SHA3-OPAD` (136 B) buffers  |
| field.f    | `_FLD-TMP` (32 B), `_FLD-CMP` (32 B) buffers        |
| aes.f      | `_AES-TAG-BUF` (16 B), `_AES-PAD` (16 B)           |
| ed25519.f  | `_ED-L` (32 B), `_ED-PINV0` (32 B), etc.           |

If two execution contexts call the same module word concurrently,
they trample each other's scratch variables.

Some modules already have guard wrappers at the bottom of the file
(mempool, rpc, xchain, sync, sha256, fft, itc).  These serialize all
access through a single `GUARD` — safe but zero parallelism per module.
Many modules have no protection at all.

### Execution Context Analysis

There are three sources of concurrent execution on this platform.
Each has different characteristics that affect which hardening strategy
is appropriate:

**1. Multi-core dispatch** (`CORE-RUN`, `SPAWN-ON`, `SCHED-ALL`, PAR-*)

Real hardware parallelism.  Up to 16 cores executing simultaneously.
Each core has a unique `COREID`.  This is the primary source of
scratch variable conflicts.

**2. BIOS cooperative background tasks** (`BACKGROUND`/`PAUSE`/`TASK-YIELD`)

Up to 4 tasks round-robin on the same core via register-file swap.
Tasks share `COREID`.  Interleaving occurs only at explicit yield
points (`PAUSE` from Task 0, `TASK-YIELD` from background tasks).
Background tasks are typically polling loops (NIC, UART) installed
via `BG-POLL`.

**3. KDOS scheduled tasks** (`SPAWN`/`SCHEDULE`, `ASYNC`, `TG-SPAWN`)

Cooperative run-to-completion.  `SCHEDULE` picks the next READY task,
calls `T.XT EXECUTE`, marks DONE when it returns, then loops.  **Tasks
do not interleave** — Task A runs its entire xt to completion before
Task B starts.  The only exception is if a task's xt calls `SCHEDULE`
recursively, or spins in `YIELD?` (which marks the task DONE, not
READY — it exits, not context-switches).

**Conclusion:**

| Context          | Truly concurrent? | Identity            | Per-ID storage safe? |
|------------------|--------------------|---------------------|----------------------|
| Multi-core       | Yes                | `COREID` (0–15)     | Yes                  |
| BIOS background  | Yes (at yields)    | Slot 0–3 (implicit) | No (`COREID` shared) |
| KDOS scheduler   | No (run-to-completion) | `CURRENT-TASK`  | N/A — no conflict    |

KDOS tasks don't need hardening — they never overlap.  Multi-core
needs per-core isolation.  BIOS background needs guards (or avoidance).

### Strategy — Layered Approach

Three layers, applied per-module based on its usage profile:

**Layer A: Guards (universal safety net) — all modules with mutable scratch**

Add the standard guard-wrapper footer to every unguarded module.
This is correct under ALL execution models.  Mechanical 3-line
addition per module.  Cost: full serialization (only one caller at
a time per module).

```forth
\ --- Bottom of module ---
REQUIRE ../concurrency/guard.f
GUARD _prefix-guard
' PUBLIC-WORD-1  CONSTANT _pw1-xt
' PUBLIC-WORD-2  CONSTANT _pw2-xt
: PUBLIC-WORD-1  _pw1-xt _prefix-guard WITH-GUARD ;
: PUBLIC-WORD-2  _pw2-xt _prefix-guard WITH-GUARD ;
```

This is the baseline.  Every module should have this as a minimum.
It can be the only layer for modules that are not performance-critical
or not called from PAR-* worker contexts.

**Layer B: Per-core scratch (`CORE-VARIABLE` / `CORE-BUFFER`) — PAR-hot modules**

For modules called from `PAR-MAP`/`PAR-FOR`/`CORE-RUN` workers,
guards defeat the purpose of multi-core dispatch.  Convert scratch
from global `VARIABLE` / `CREATE` to per-core allocations indexed by
`COREID`.

Per-core scratch eliminates cross-core conflicts without any locking.
Combined with a guard, it also handles the BIOS interleaving case:
the guard only fires for same-core contention (rare — background
pollers rarely call math words), while PAR workers on different cores
proceed in parallel without contention.

**Layer C: No action needed — KDOS-only modules**

Modules that are only ever called from KDOS-scheduled task contexts
(run-to-completion) don't need hardening beyond what the scheduler
already provides.  Examples: modules called only from `TG-SPAWN`
or `ASYNC` bodies, where `SCHEDULE` runs tasks sequentially.

In practice, it's hard to *guarantee* a module will never be called
from a PAR worker or BIOS background, so Layer A (guards) should be
applied even to these modules as a safety net.

### New Defining Words — core-local.f

A new utility file `concurrency/core-local.f` provides drop-in
replacements for `VARIABLE` and `CREATE ... ALLOT` that allocate
per-core storage:

```forth
\ CORE-VARIABLE ( "name" -- )
\   Like VARIABLE, but allocates 16 slots (one per core).
\   DOES> returns the per-core address — existing @ and ! work unchanged.
\
\   VARIABLE _V2-A        →  CORE-VARIABLE _V2-A
\   _V2-A @ _V2-C @ ...   →  _V2-A @ _V2-C @ ...   (no change)

: CORE-VARIABLE  ( "name" -- )
    CREATE 16 CELLS ALLOT
    DOES> COREID CELLS + ;

\ CORE-BUFFER ( size "name" -- )
\   Like CREATE name <size> ALLOT, but allocates 16 copies.
\   DOES> returns the per-core buffer address.
\
\   CREATE _FLD-TMP 32 ALLOT  →  32 CORE-BUFFER _FLD-TMP
\   _FLD-TMP 32 0 FILL        →  _FLD-TMP 32 0 FILL  (no change)

: CORE-BUFFER  ( size "name" -- )
    CREATE DUP , 16 * ALLOT
    DOES> DUP @ COREID * + CELL+ ;

\ CORE-XMEM ( size "name" -- )
\   Per-core XMEM blob allocation.  Each core gets its own
\   XMEM region of the specified size.
\   DOES> returns the per-core XMEM address.
\
\   For modules that use XMEM for large scratch buffers
\   (e.g., STARK proof work areas).

: CORE-XMEM  ( size "name" -- )
    CREATE DUP , 16 0 DO DUP XMEM-ALLOC , LOOP DROP
    DOES> CELL+ COREID CELLS + @ ;
```

Memory cost per defining word:

| Word            | Per-instance cost | Example                 | Total  |
|-----------------|-------------------|-------------------------|--------|
| `CORE-VARIABLE` | 128 B (16 cells)  | vec2.f has 8 vars       | 1 KB   |
| `CORE-BUFFER`   | 16 × buffer size  | `_FLD-TMP` 32 B         | 512 B  |
| `CORE-BUFFER`   | 16 × buffer size  | `_SHA3-IPAD` 136 B      | 2.1 KB |
| `CORE-BUFFER`   | 16 × buffer size  | `_AIR-BUF` 1024 B       | 16 KB  |
| `CORE-XMEM`     | 16 pointers + XMEM| Large proof buffers     | 128 B + XMEM |

### Module Classification

> **Not comprehensive** — representative examples per area.  Every
> module with mutable scratch (`VARIABLE` or `CREATE ... ALLOT`) needs
> to be audited individually.  As of this writing, **97 of 160 `.f`
> files (61%) have no guard protection.**

**Guard coverage by area:**

| Area            | Files | Guarded | Coverage | Notes                                |
|-----------------|-------|---------|----------|--------------------------------------|
| net/            | 9     | 9       | 100%     | HTTP, WebSocket, gossip, xchain, etc.|
| web/            | 7     | 7       | 100%     | Server, router, RPC, middleware      |
| store/          | 11    | 10      | 91%      | Block, state, mempool, VM, vault     |
| node/           | 1     | 1       | 100%     | Node runtime                         |
| consensus/      | 1     | 1       | 100%     | Consensus protocol                   |
| math/           | 38    | 24      | 63%      | Some guarded, crypto/STARK gaps      |
| utils/          | 9     | 5       | 56%      | string, table, fmt, datetime exposed |
| concurrency/    | 12    | 4       | 33%      | Primitives self-protect; wrappers don't |
| **audio/**      | **32**| **1**   | **3%**   | **Massive gap — 560+ VARs unguarded**|
| **render/**     | **13**| **0**   | **0%**   | **389 VARs, draw.f alone has 88**    |
| **dom/**        | **1** | **0**   | **0%**   | **69 VARs + 6 buffers**              |
| **css/**        | **2** | **0**   | **0%**   | **51+ VARs for CSS parser**          |
| **markup/**     | **3** | **0**   | **0%**   | **HTML parser: 21 VARs + 35 buffers**|
| **font/**       | **3** | **0**   | **0%**   | **Rasterizer: 44 VARs + 3 buffers**  |
| **liraq/**      | **5** | **0**   | **0%**   | **State tree, LEL, profile — 157 VARs**|
| **sml/**        | **2** | **0**   | **0%**   | **SOM tree: 55 VARs**                |
| **atproto/**    | **6** | **0**   | **0%**   | **Session, repo, XRPC — all exposed**|
| **cbor/**       | **2** | **0**   | **0%**   | **DAG-CBOR codec — AT Proto depends on this**|
| **text/**       | **2** | **0**   | **0%**   | **UTF-8 codec, text layout**         |
| **knowledge/**  | **1** | **0**   | **0%**   | **Taxonomy engine**                  |

**Key problem areas:**

- **Audio** (32 files, 3% coverage): The largest library by file
  count.  FM/additive/granular/modal synthesis, effects, mixing,
  sequencing — all rely on heavy scratch state.  Concurrent audio
  rendering (e.g., PAR-MAP across voices) is a natural use case
  and currently unsafe.

- **Rendering pipeline** (render + dom + css + font + markup + text):
  The entire HTML→CSS→layout→paint→BMP pipeline is completely
  unguarded.  `render/draw.f` alone has 88 VARIABLEs.  This is a
  problem if you want to render multiple pages concurrently or
  parallelize layout across subtrees.

- **Networking** (net/, web/): Already 100% guarded, but serialized.
  A concurrent web server handling multiple requests needs parallel
  request parsing, header building, response construction.  These are
  currently guard-serialized — one request at a time through each
  module.  For throughput, the networking stack would benefit from
  per-core scratch (Category 2/3) so multiple cores can handle
  requests simultaneously.

- **AT Protocol** (atproto/ + cbor/): Completely unguarded.  Session
  management, XRPC, repo ops, DID validation, DAG-CBOR — all have
  scratch VARIABLEs and no protection.  Any concurrent use (multiple
  AT Proto sessions, parallel feed fetches) will corrupt state.

- **LIRAQ / SML** (liraq/ + sml/): The UI framework layer.
  State tree (50 VARs), LEL expression evaluator (43 VARs), SOM tree
  (55 VARs) — all unguarded.  Concurrent UI updates or parallel
  layout would corrupt.

- **Crypto / STARK** (math/stark.f, math/baby-bear.f, etc.):
  The ZK proof system has large scratch buffers and is a prime
  candidate for parallelization.  `stark.f` is unguarded (33 VARs +
  19 buffers).  Parallel proof generation is currently unsafe.

- **Store** (91% covered): Mostly guarded.  Only `genesis.f` is
  missing a guard.  But the guards serialize — parallel block
  validation or concurrent state reads would benefit from rwlock or
  per-core upgrades.

**Category summary (not comprehensive — examples only):**

**Category 1: Guard-only (not PAR-hot)**

Application-level modules where serialization is acceptable.  A guard
is sufficient and simplest.

Examples: store/*, web/*, net/*, utils/string.f, utils/json.f,
atproto/*, cbor/*, dom/*, css/*, markup/*, text/*, font/*,
liraq/*, sml/*, knowledge/*, node/*.

Many of these already have guards (net, web, store).  The rest
(rendering pipeline, audio, AT Proto, LIRAQ, etc.) need guards added.

**Category 2: Per-core scratch + per-core guard (PAR-hot, VARIABLE only)**

Inner-loop compute modules dispatched to secondary cores via PAR-*.
Need per-core scratch for parallelism + per-core guard for BIOS safety.

Examples: math/fp16.f, math/fp32.f, math/trig.f, math/vec2.f,
math/mat2d.f, math/interp.f, math/sort.f, math/filter.f, math/stats.f,
audio synthesis voices (if parallel voice rendering is needed).

**Category 3: Per-core scratch + per-core guard (PAR-hot, with buffers)**

Compute modules with `CREATE ... ALLOT` byte buffers in addition to
`VARIABLE` scratch.  Need `CORE-BUFFER` for the buffers.

Examples: math/sha256.f, math/sha3.f, math/sha512.f, math/field.f,
math/ed25519.f, math/aes.f, math/fft.f, math/stark.f, math/baby-bear.f,
render/draw.f (if parallel tile rendering).

### Transformation Recipe

For each module:

**Step 1: Audit scratch variables.**

Classify every `VARIABLE _PREFIX-*` and `CREATE _PREFIX-* N ALLOT` as:

- **Scratch** — only used within a single public word's execution;
  no state persists between calls.  → `CORE-VARIABLE` or `CORE-BUFFER`
- **Shared mutable** — module-level state that persists across calls
  (counts, config, capacity).  → Keep as `VARIABLE`, protect with
  guard or `CVAR`.
- **Read-only** — initialized once at load time, never mutated.
  → No change needed.

**Step 2: Replace scratch defining words (Category 2/3 only).**

```forth
\ Before:
VARIABLE _V2-A
VARIABLE _V2-B
CREATE _FLD-TMP 32 ALLOT

\ After:
REQUIRE ../concurrency/core-local.f
CORE-VARIABLE _V2-A
CORE-VARIABLE _V2-B
32 CORE-BUFFER _FLD-TMP
```

No other code changes needed — `CORE-VARIABLE` `DOES>` returns an
address that works with `@` and `!` unchanged.  `CORE-BUFFER` `DOES>`
returns a buffer address that works with `CMOVE`, `FILL`, `C@`, `C!`.

**Step 3: Add guard wrapper (all categories).**

```forth
\ --- Bottom of module ---
REQUIRE ../concurrency/guard.f
GUARD _prefix-guard
' PUBLIC-WORD CONSTANT _pw-xt
: PUBLIC-WORD  _pw-xt _prefix-guard WITH-GUARD ;
```

For Category 2/3 modules (per-core scratch + guard), the guard
provides BIOS interleaving safety.  For PAR-* dispatch on different
cores, the per-core scratch means the guard is never contended —
each core's `GUARD-ACQUIRE` sees a free guard because they're
accessing different scratch slots.

Wait — that's wrong.  The guard is a **single shared object**, not
per-core.  If core 0 holds `_v2-guard`, core 1 will spin on it even
though their scratch is separate.

**Correction: per-core scratch makes the guard unnecessary for
cross-core safety.**  The guard is only needed for same-core BIOS
interleaving.  Two options:

**(a) Accept the guard serialization.**  Simple, correct.  PAR-*
workers will serialize on the guard — defeating the per-core scratch
benefit.  Only useful if you want BIOS safety and don't use PAR.

**(b) Use a per-core guard.**  Create 16 guards (one per core),
index by `COREID`:

```forth
CREATE _prefix-guards  16 _GRD-SIZE-SPIN * ALLOT
: _prefix-my-guard  ( -- guard )
    COREID _GRD-SIZE-SPIN * _prefix-guards + ;

: PUBLIC-WORD  _pw-xt _prefix-my-guard WITH-GUARD ;
```

Now each core has its own guard.  Cross-core: no contention (different
guards).  Same-core BIOS interleaving: the per-core guard serializes
tasks on the same core.  PAR-* workers: zero contention, full speed.

Memory cost: 16 × 24 bytes = 384 bytes per module.  Trivial.

**This is the recommended pattern for Category 2/3 modules.**

**Step 4: Handle multi-step APIs.**

For modules with BEGIN/ADD/END patterns (sha256, sha3), the guard
must span multiple calls.  Use explicit `GUARD-ACQUIRE`/`GUARD-RELEASE`
as sha256.f already does:

```forth
: SHA256-BEGIN  _sha256-guard GUARD-ACQUIRE  ... ;
: SHA256-ADD    _sha256-guard GUARD-MINE? 0= IF -258 THROW THEN  ... ;
: SHA256-END    ...  _sha256-guard GUARD-RELEASE ;
```

With per-core guards, this becomes:

```forth
: SHA256-BEGIN  _sha256-my-guard GUARD-ACQUIRE  ... ;
: SHA256-ADD    _sha256-my-guard GUARD-MINE? 0= IF -258 THROW THEN ... ;
: SHA256-END    ...  _sha256-my-guard GUARD-RELEASE ;
```

### Invariants & Constraints

**1. `CORE-VARIABLE` / `CORE-BUFFER` are only safe for scratch.**

Per-core storage must not be used for shared mutable state.  If two
cores need to see the same counter or config, use a regular `VARIABLE`
with a guard, or a `CVAR` for atomic access.

**2. PAR-* worker code must not call `PAUSE`.**

Secondary cores dispatched via `CORE-RUN` run a single word to
completion.  They do not participate in BIOS cooperative scheduling.
If a PAR worker called `PAUSE`, behavior is undefined (there's no
R13 background task on secondary cores).  This is already the case
today — PAR workers are straight-line compute.  Document the
invariant explicitly: `\ YIELD-FREE — PAR-worker safe`.

**3. BIOS background tasks that call library code need guards.**

A background polling loop installed via `BG-POLL` that happens to
call a library module (e.g., SHA256 for packet verification) will
interleave with Task 0 on the same core at yield points.  Per-core
guards handle this correctly.

**4. Read-only tables are free.**

`CREATE _TABLE ... , , ,` tables initialized at load time and never
mutated don't need per-core duplication or guards.  This includes
twiddle factor tables (fft.f), hex-digit tables (sha256.f), and
constant arrays.

**5. Zero-initialization.**

`CORE-BUFFER` allocates via `ALLOT` which does not zero memory.
Modules that assume zero-init after `CREATE ... ALLOT ... 0 FILL`
must call `FILL` on the per-core buffer after `CORE-BUFFER`.  The
`DOES>` body returns the correct per-core address, so
`_BUF 32 0 FILL` at init time only zeros core 0's copy.  Either
zero all 16 copies at load time, or zero on first use.

**6. `CORE-XMEM` slots are allocated once at load time.**

Each core gets a permanent XMEM blob.  XMEM is not garbage-collected
on this platform, so these allocations are lifetime-permanent.  Only
use `CORE-XMEM` for modules that genuinely need large per-core scratch
(STARK proofs, contract-VM arenas).

### Hardening Implementation Order

**Phase 1: Guards everywhere (quick baseline) — 97 unguarded modules**

Add guard wrappers to all unguarded modules.  No per-core conversion.
Correct under all execution models.  Mechanical 3-5 lines per module.

Priority tiers (by dependency depth and risk):

1. **Foundation math** — everything else depends on these:
   `math/exp.f`, `math/fp16-ext.f`, `math/fp-convert.f`,
   `math/rect.f`, `math/accum.f`, remaining unguarded math

2. **Utils** — string, table, fmt, datetime (used by parsers, web)

3. **Rendering pipeline** — render/ (13 files), dom/, css/, font/,
   markup/, text/ — the entire HTML→BMP path is 0% covered

4. **Audio** — 31 unguarded files.  Synthesis, effects, mixing,
   sequencing, analysis — all need guards before any concurrent
   audio work

5. **AT Protocol + CBOR** — atproto/ (6 files) + cbor/ (2 files).
   Any concurrent session handling requires these

6. **LIRAQ / SML** — UI framework layer (7 files, 0% coverage)

7. **Knowledge, store/genesis.f** — lower priority, fewer callers

8. **Crypto / STARK** — math/stark.f, math/baby-bear.f,
   math/ntt.f — guarding is the quick fix, per-core is Phase 4

**Phase 2: core-local.f defining words**

Implement `CORE-VARIABLE`, `CORE-BUFFER`, `CORE-XMEM` in a new file
`concurrency/core-local.f`.  Test with the emulator.

**Phase 3: Per-core scratch for PAR-hot math modules**

Convert Category 2 modules (fp16, fp32, trig, vec2, mat2d) to
per-core scratch + per-core guards.  Verify with PAR-MAP/PAR-REDUCE
tests that parallel execution produces correct results.

Priority order:
1. `math/fp16.f` + `math/fp16-ext.f` — foundation for all FP16 math
2. `math/trig.f` — used by vec2 rotate
3. `math/vec2.f` — primary PAR-MAP target (geometry transforms)
4. `math/fp32.f` — PAR-REDUCE target (statistics)
5. `math/mat2d.f` — PAR-MAP target (affine transforms)

**Phase 4: Per-core buffers for crypto/DSP**

Convert Category 3 modules where parallelism is critical:
1. `math/sha256.f` — parallel block hashing (Merkle tree construction)
2. `math/field.f` — STARK proof arithmetic
3. `math/fft.f` — signal processing (already guarded, upgrade to per-core)

Defer `baby-bear.f` (64 KB per-core cost) and `stark-air.f` (16 KB)
unless profiling shows guard serialization is the bottleneck.

**Phase 5: Per-core for networking (concurrent request handling)**

The net/ and web/ layers are fully guarded but serialized.  For a
concurrent web server handling requests on multiple cores:
1. `web/request.f` — parallel request parsing
2. `web/response.f` — parallel response building
3. `net/headers.f` — parallel header parsing
4. `net/http.f` — parallel HTTP client operations

This is only needed if the application dispatches request handling
to multiple cores via `SPAWN-ON` or PAR-*.

**Phase 6: Per-core for audio (parallel voice rendering)**

If parallel audio rendering is needed (PAR-MAP across polyphonic
voices, parallel effects chains):
1. `audio/osc.f`, `audio/env.f` — oscillator + envelope per voice
2. `audio/synth.f`, `audio/fm.f` — synthesis engines
3. `audio/fx.f` — effects (60 VARs — large per-core cost)
4. `audio/mix.f` — mixer (needs careful shared-vs-scratch audit)

**Phase 7: Audit and stress test**

- Run all existing tests under multi-core emulation
- Add concurrent stress tests: multiple PAR-MAP calls using the same
  module from different cores
- Test BIOS background + main task using same guarded module
- Test concurrent web request handling (multiple cores parsing/building)
- Test parallel audio voice rendering
- Verify no scratch corruption under load

---

## BIOS SEP Dispatch Refactor — Status: Landed

> **Updated 2026-03-06.**  The SEP/SEX register-dispatch refactor has
> shipped in BIOS v1.0.  Phases 0, 1, 4, 5, 7, 8, 9 are all ✅ Done.
> Phase 3 (JIT SEP-NEXT) permanently deferred (ITC destroys JIT).
> Phases 2 and 6 were skipped.  Phase 10 (port I/O bridge) not started
> (requires RTL changes).

The BIOS changes converted internal leaf I/O routines (`emit_char`,
`key_char`, `print_hex_byte`) from `call.l`/`ret.l` to 1802-style
`SEP Rn` dispatch, added `SEX`+D-accumulator byte-processing for DMA
paths (Phase 7 — ~50% serialization compression), and added a Q
flip-flop semaphore for UART busy signaling (Phase 4 — `SEQ`/`REQ`).

### What was NOT affected (confirmed)

All existing concurrency primitives (`event.f`, `semaphore.f`,
`rwlock.f`, `channel.f`, `cvar.f`, `conc-map.f`, `scope.f`, `par.f`,
`future.f`) operate at the Forth word level via `LOCK`/`UNLOCK`,
`YIELD?`, `SPAWN`, `SCHEDULE`, `CORE-RUN`, and `BARRIER`.  None of
these emit machine code or depend on BIOS register allocation.

The `par.f` full-core / micro-core split remains correct.  Micro-cores
now have SEP/SEX decode (zero area cost — they only update psel/xsel
pointers), but still lack Q flip-flop, so `EMIT`-based I/O would trap.
`par.f` defaults to full cores only (`_PAR-NCORES` = `N-FULL`).

### Phase 8 — Cooperative PAUSE via SEP (landed)

BIOS now provides `PAUSE`, `YIELD`, `BACKGROUND`, `TASK-STOP`, and
`TASK-STATUS` as dictionary words.  These implement a 2-task hardware
coroutine using R3 (Task 0) and R13 (Task 1), documented in the
"BIOS-Level Hardware Coroutine Pair" section above.

**Confirmed interop behavior:**

1. **`YIELD?` vs `PAUSE` — they are independent.**  The concurrency
   library uses KDOS `YIELD?` as its cooperative yield point (in
   `EVT-WAIT`, `CHAN-SEND`, `CHAN-RECV`, `CHAN-SELECT`, `SEM-WAIT`,
   etc.).  BIOS `PAUSE` is a separate, lower-level mechanism — a
   pure register-file swap, invisible to the §8 scheduler.  They do
   not interfere.  A KDOS task can call `PAUSE` internally to
   service a hardware coroutine partner without disturbing the
   scheduler's view of task states.

2. **`scope.f` / `TG-WAIT` does not see BIOS tasks.**  `TG-WAIT`
   calls `SCHEDULE` to process the §8 task table.  BIOS Task 1 (R13)
   has no task descriptor, no T.READY/T.BLOCKED state, and is not in
   the task registry.  This is by design — the hardware coroutine
   pair is below the Forth scheduler layer.  `WITH-TASKS` scopes do
   not need to track BIOS Task 1; it should be managed separately
   via `BACKGROUND` / `TASK-STOP`.

3. **BIOS `YIELD` naming collision.**  BIOS dict #309 `YIELD` (alias
   for `PAUSE`) shadows KDOS `YIELD` (marks current task `T.DONE`).
   Dictionary search order resolves this — the KDOS word is defined
   later and wins.  But code that explicitly calls the BIOS version
   should use `PAUSE` instead for clarity.

### Phase 3 — JIT SEP-NEXT (permanently deferred)

The JIT threading model change was abandoned — ITC destroys the JIT
assumptions.  No impact on `CATCH`/`THROW` or any concurrency
primitives.  This watch item is closed.

### Resolved action items

- [x] Verify `YIELD?` interoperates with `PAUSE` — confirmed independent
- [x] Verify `SCHEDULE` / `TG-WAIT` does not see BIOS tasks — confirmed
      by design (separate mechanism, documented above)
- [x] JIT Phase 3 `CATCH`/`THROW` check — N/A, phase permanently deferred
- [x] No changes were needed in any `.f` source files in `akashic/concurrency/`

### Resolved items — coroutine.f

- [x] `coroutine.f` — implemented with 5 public words:
      `BG-ALIVE?`, `WITH-BACKGROUND`, `BG-POLL`, `BG-WAIT-DONE`,
      `BG-INFO`.  22 tests passing (`test_coroutine.py`).
- [x] BIOS renamed `YIELD` → `TASK-YIELD` to avoid KDOS collision.
      `coroutine.f` uses `TASK-YIELD` for Task 1 code, `PAUSE` for
      Task 0 code.  Collision documented in coroutine.f header.
- [ ] Integrate with `par.f` — optionally start a background NIC/UART
      poller before entering `PAR-MAP` / `PAR-REDUCE` so I/O stays
      alive during multi-core compute phases (future work)

---
