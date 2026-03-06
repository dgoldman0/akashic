# akashic-coroutine — Structured Wrappers for BIOS Hardware Coroutine Pair

Structured concurrency wrappers around the Megapad-64 BIOS Phase 8
hardware coroutine (SEP R13 two-task cooperative switching).  Guarantees
cleanup, provides polling loops, and normalises the flag convention.

```forth
REQUIRE coroutine.f
```

`PROVIDED akashic-coroutine` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Hardware Model](#hardware-model)
- [API](#api)
  - [BG-ALIVE?](#bg-alive)
  - [WITH-BACKGROUND](#with-background)
  - [BG-POLL](#bg-poll)
  - [BG-WAIT-DONE](#bg-wait-done)
  - [BG-INFO](#bg-info)
- [Concurrency Model](#concurrency-model)
- [Constraints](#constraints)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Structured cleanup** | `WITH-BACKGROUND` guarantees `TASK-STOP` even on `THROW`. |
| **Single background slot** | One Task 1 (R13) at a time — matches the hardware. |
| **Cooperative only** | No preemption.  Task 0 calls `PAUSE`, Task 1 calls `TASK-YIELD`. |
| **Zero allocation** | No heap usage.  One `VARIABLE` for `BG-POLL` xt storage. |
| **Prefix convention** | Public: `BG-` (plus `WITH-BACKGROUND`).  Internal: `_BG-`. |
| **Building block** | Used by higher-level patterns (NIC polling, background hashing). |

---

## Hardware Model

The BIOS Phase 8 cooperative multitasking uses the SEP instruction to
switch between two hardware tasks:

| Task | PC register | Role | Yield word |
|------|-------------|------|------------|
| **Task 0** | R3 | Main Forth interpreter / application | `PAUSE` |
| **Task 1** | R13 | Single background helper | `TASK-YIELD` |

Context switch is **1 cycle** (a single `SEP` instruction).  There are
no task queues — just two register-selected execution threads.

### Raw BIOS Words

| Word | Signature | Description |
|------|-----------|-------------|
| `PAUSE` | `( -- )` | Task 0 → Task 1 (no-op if no task active) |
| `TASK-YIELD` | `( -- )` | Task 1 → Task 0 |
| `BACKGROUND` | `( xt -- )` | Install xt as Task 1, give it fresh stacks |
| `TASK-STOP` | `( -- )` | Cancel Task 1 (clear saved PC) |
| `TASK?` | `( -- flag )` | 1 if Task 1 active, 0 otherwise |

**CRITICAL:** `PAUSE` and `TASK-YIELD` are **not interchangeable**:

- `PAUSE` loads a saved PC into R13.  If called from Task 1 (where R13
  IS the program counter), it overwrites the live PC → crash.
- Task 0 code must call `PAUSE`.  Task 1 code must call `TASK-YIELD`.

### Task Lifecycle

```
 Task 0                        Task 1
 ──────                        ──────
 ['] bg-xt BACKGROUND          (created, PC saved)
   ...                           │
 PAUSE ──────────────SEP────→  resumes at bg-xt
   │                           does work
   │    ←────────────SEP────── TASK-YIELD
 resumes                         │
   ...                           │
 PAUSE ──────────────SEP────→  resumes after TASK-YIELD
   │                           ... returns from bg-xt ...
   │    ←────────────SEP────── task1_cleanup (auto)
 resumes                       (TASK? = 0)
```

---

## API

### `BG-ALIVE?`

```forth
BG-ALIVE? ( -- flag )
```

Returns TRUE (-1) if a background task is currently active, FALSE (0)
otherwise.  Thin wrapper around `TASK?` normalised to standard Forth
flag convention (`0<>`).

```forth
BG-ALIVE? IF ." background running" CR THEN
```

---

### `WITH-BACKGROUND`

```forth
WITH-BACKGROUND ( xt-bg xt-body -- )
```

Structured scoped execution:

1. Start `xt-bg` as Task 1 via `BACKGROUND`
2. Execute `xt-body` on Task 0 under `CATCH`
3. Unconditionally call `TASK-STOP`
4. Re-`THROW` if `xt-body` raised an exception

This guarantees the background task is stopped even if the body
throws.  Both xts must have signature `( -- )`.

```forth
: my-bg   BEGIN  nic-poll  TASK-YIELD  AGAIN ;
: my-body
    PAUSE                    \ let bg task run once
    do-work
    PAUSE                    \ let bg task run again
;
['] my-bg  ['] my-body  WITH-BACKGROUND
\ bg is guaranteed stopped here
```

**Exception safety:**

```forth
: risky-body  99 THROW ;
['] my-bg  ['] risky-body
['] WITH-BACKGROUND CATCH    \ returns 99, bg is still stopped
```

---

### `BG-POLL`

```forth
BG-POLL ( xt -- )
```

Install `xt` as a background polling loop.  Internally creates an
infinite loop:

```
BEGIN  xt EXECUTE  TASK-YIELD  AGAIN
```

The word returns immediately to Task 0.  Each `PAUSE` from Task 0
gives Task 1 a timeslice to execute `xt` once, then Task 1 yields
back.

`xt` must have signature `( -- )`.  Use `TASK-STOP` to cancel, or
wrap the `PAUSE` calls inside `WITH-BACKGROUND` for auto-cleanup.

```forth
: my-poll  nic-poll ;
['] my-poll BG-POLL
PAUSE PAUSE PAUSE       \ poll runs 3 times
TASK-STOP               \ done polling
```

**Note:** Because `BG-POLL` internally calls `BACKGROUND`, it cannot
be called from inside an already-running Task 1.

---

### `BG-WAIT-DONE`

```forth
BG-WAIT-DONE ( -- )
```

Busy-wait (calling `PAUSE` each iteration) until the background task
finishes naturally.  When a one-shot background task's xt returns,
`task1_cleanup` fires and `TASK?` becomes 0.

Only useful for **one-shot** tasks.  For infinite-loop tasks (e.g.,
those installed by `BG-POLL`), this would spin forever — use
`TASK-STOP` instead.

```forth
: bg-hash  buf len SHA-256 result 32 CMOVE ;
['] bg-hash BACKGROUND
do-other-work
BG-WAIT-DONE             \ wait for hash to finish
\ result buffer is now ready
```

Returns immediately if no background task is active.

---

### `BG-INFO`

```forth
BG-INFO ( -- )
```

Print background task status for debugging:

```
[coroutine bg=ACTIVE]
[coroutine bg=STOPPED]
```

---

## Concurrency Model

### Single-Core Cooperative (Primary Use Case)

The hardware coroutine pair is designed for single-core cooperative
multitasking.  Task 0 (the main Forth interpreter) and Task 1 (one
background helper) take turns explicitly:

```forth
\ Poll NIC while hashing a large buffer
: poll-nic  nic-rx-check ;
['] poll-nic BG-POLL

: hash-loop
    BEGIN
        buf 4096 SHA-256-UPDATE
        PAUSE                \ let NIC poll run
        more-data?
    WHILE REPEAT ;

hash-loop TASK-STOP
```

### Interaction with KDOS Scheduler

The BIOS hardware coroutine (SEP-based) is orthogonal to the KDOS
software task scheduler (`SCHEDULE`, `YIELD`, `SPAWN`).  The coroutine
pair runs within a single KDOS task — both Task 0 and Task 1 share
the same KDOS task slot.

- `PAUSE` / `TASK-YIELD` switch between the two hardware threads
- `YIELD` (KDOS word) marks the current KDOS task as done and lets
  the scheduler pick the next KDOS task

These are different mechanisms and should not be confused.

### Multicore

The hardware coroutine pair is per-core.  Each core has its own R3/R13
register pair.  `BACKGROUND` on core 0 only affects core 0's Task 1.

---

## Constraints

| Constraint | Reason |
|------------|--------|
| **One background slot** | Hardware has one R13 register per core. |
| **No preemption** | SEP is explicit — Task 1 only runs when Task 0 calls `PAUSE`. |
| **No I/O from Task 1** | Micro-core lacks Q flip-flop; `EMIT` traps. Use shared variables. |
| **PAUSE ≠ TASK-YIELD** | Calling the wrong yield word from the wrong task crashes. |
| **Shared address space** | Task 1 shares dictionary and memory with Task 0. |
| **No `[: ;]` closures** | This BIOS/KDOS does not define anonymous quotations. Use named words with `[']`. |

---

## Quick Reference

### Public Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `BG-ALIVE?` | `( -- flag )` | Is Task 1 active? (TRUE/FALSE) |
| `WITH-BACKGROUND` | `( xt-bg xt-body -- )` | Scoped bg task with auto-stop |
| `BG-POLL` | `( xt -- )` | Install polling background loop |
| `BG-WAIT-DONE` | `( -- )` | Wait for one-shot bg task to finish |
| `BG-INFO` | `( -- )` | Debug status display |

### Internal Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `_BG-POLL-XT` | variable | Storage for polling loop xt |
| `_BG-POLL-LOOP` | `( -- )` | Infinite poll-yield loop (Task 1) |

### Dependencies

None.  All BIOS words (`PAUSE`, `TASK-YIELD`, `BACKGROUND`, `TASK-STOP`,
`TASK?`) are always available.
