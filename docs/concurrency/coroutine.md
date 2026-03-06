# akashic-coroutine — Structured Wrappers for BIOS Cooperative Multitasking

Structured concurrency wrappers around the Megapad-64 BIOS Phase 8
four-task round-robin cooperative scheduler (SEP R20).  Guarantees
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
  - [BG-ANY?](#bg-any)
  - [WITH-BACKGROUND](#with-background)
  - [WITH-BG](#with-bg)
  - [BG-POLL](#bg-poll)
  - [BG-POLL-SLOT](#bg-poll-slot)
  - [BG-WAIT-DONE](#bg-wait-done)
  - [BG-WAIT-ALL](#bg-wait-all)
  - [BG-STOP-ALL](#bg-stop-all)
  - [BG-INFO](#bg-info)
- [Concurrency Model](#concurrency-model)
- [Constraints](#constraints)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Structured cleanup** | `WITH-BACKGROUND` / `WITH-BG` guarantee `TASK-STOP` even on `THROW`. |
| **Three background slots** | Slots 1–3, matching the hardware (4-task round-robin). |
| **Cooperative only** | No preemption.  Task 0 calls `PAUSE`, background tasks call `TASK-YIELD`. |
| **Zero allocation** | No heap usage.  Three `VARIABLE`s for `BG-POLL` xt storage. |
| **Prefix convention** | Public: `BG-` (plus `WITH-BACKGROUND` / `WITH-BG`).  Internal: `_BG-`. |
| **Building block** | Used by higher-level patterns (NIC polling, background hashing). |

---

## Hardware Model

The BIOS Phase 8 cooperative multitasking uses the SEP instruction with
R20 (REX-extended register) to round-robin between up to four tasks:

| Task | Slot | Role | Yield word |
|------|------|------|------------|
| **Task 0** | — | Main Forth interpreter / application (always active) | `PAUSE` |
| **Task 1** | 1 | Background helper | `TASK-YIELD` |
| **Task 2** | 2 | Background helper | `TASK-YIELD` |
| **Task 3** | 3 | Background helper | `TASK-YIELD` |

Each background slot gets independent data-stack and return-stack
regions.  Context switch is a single `SEP R20` instruction.  `PAUSE`
scans slots 1–3 round-robin, loading the next active task's saved PC
into R20 before executing SEP.

### Raw BIOS Words

| Word | Signature | Description |
|------|-----------|-------------|
| `PAUSE` | `( -- )` | Task 0 → next active bg task (no-op if none active) |
| `TASK-YIELD` | `( -- )` | Any bg task → Task 0 |
| `BACKGROUND` | `( xt -- )` | Start xt in slot 1 with fresh stacks |
| `BACKGROUND2` | `( xt -- )` | Start xt in slot 2 with fresh stacks |
| `BACKGROUND3` | `( xt -- )` | Start xt in slot 3 with fresh stacks |
| `TASK-STOP` | `( n -- )` | Cancel task in slot n (1–3) |
| `TASK?` | `( n -- flag )` | Is slot n active? (1/0) |
| `#TASKS` | `( -- n )` | Count of active background tasks (0–3) |

**CRITICAL:** `PAUSE` and `TASK-YIELD` are **not interchangeable**:

- `PAUSE` loads a saved PC into R20.  If called from a background task
  (where R20 IS the program counter), it overwrites the live PC → crash.
- Task 0 code must call `PAUSE`.  Background task code must call `TASK-YIELD`.

### Task Lifecycle

```
 Task 0                        Slot 1              Slot 2
 ──────                        ──────              ──────
 ['] bg1 BACKGROUND            (created)
 ['] bg2 BACKGROUND2                               (created)
   ...
 PAUSE ───SEP R20───────────→  resumes at bg1
   │                           does work
   │    ←────────────SEP────── TASK-YIELD
 PAUSE ───SEP R20───────────────────────────────→  resumes at bg2
   │                                               does work
   │    ←──────────────────────────────SEP──────── TASK-YIELD
 resumes
   ...
 PAUSE ───SEP R20───────────→  resumes
   │                           ... returns ...
   │    ←────────────SEP────── task_cleanup (auto)
 resumes                       (1 TASK? = 0)
```

---

## API

### `BG-ALIVE?`

```forth
BG-ALIVE? ( n -- flag )
```

Returns TRUE (-1) if slot n (1–3) has an active background task,
FALSE (0) otherwise.  Thin wrapper around `TASK?` normalised to
standard Forth flag convention (`0<>`).

```forth
1 BG-ALIVE? IF ." slot 1 running" CR THEN
```

---

### `BG-ANY?`

```forth
BG-ANY? ( -- flag )
```

Returns TRUE (-1) if any background task (slots 1–3) is active.
Uses the BIOS `#TASKS` word.

```forth
BG-ANY? IF ." at least one task running" CR THEN
```

---

### `WITH-BACKGROUND`

```forth
WITH-BACKGROUND ( xt-bg xt-body -- )
```

Structured scoped execution for **slot 1**:

1. Start `xt-bg` as Task 1 via `BACKGROUND`
2. Execute `xt-body` on Task 0 under `CATCH`
3. Unconditionally call `1 TASK-STOP`
4. Re-`THROW` if `xt-body` raised an exception

This guarantees slot 1 is stopped even if the body throws.
Both xts must have signature `( -- )`.

```forth
: my-bg   BEGIN  nic-poll  TASK-YIELD  AGAIN ;
: my-body
    PAUSE                    \ let bg task run once
    do-work
    PAUSE                    \ let bg task run again
;
['] my-bg  ['] my-body  WITH-BACKGROUND
\ slot 1 is guaranteed stopped here
```

**Exception safety:**

```forth
: risky-body  99 THROW ;
['] my-bg  ['] risky-body
['] WITH-BACKGROUND CATCH    \ returns 99, slot 1 is still stopped
```

---

### `WITH-BG`

```forth
WITH-BG ( slot xt-bg xt-body -- )
```

Generic scoped execution for **any slot** (1–3):

1. Start `xt-bg` in the given slot
2. Execute `xt-body` on Task 0 under `CATCH`
3. Unconditionally call `slot TASK-STOP`
4. Re-`THROW` if `xt-body` raised an exception

```forth
2 ['] my-poller  ['] my-work  WITH-BG
\ slot 2 is guaranteed stopped here
```

---

### `BG-POLL`

```forth
BG-POLL ( xt -- )
```

Install `xt` as a background polling loop in **slot 1**.  Internally
creates an infinite loop:

```
BEGIN  xt EXECUTE  TASK-YIELD  AGAIN
```

The word returns immediately to Task 0.  Each `PAUSE` from Task 0
gives slot 1 a timeslice to execute `xt` once, then it yields back.

`xt` must have signature `( -- )`.  Use `1 TASK-STOP` to cancel.

```forth
: my-poll  nic-poll ;
['] my-poll BG-POLL
PAUSE PAUSE PAUSE       \ poll runs 3 times
1 TASK-STOP             \ done polling
```

---

### `BG-POLL-SLOT`

```forth
BG-POLL-SLOT ( slot xt -- )
```

Install `xt` as a background polling loop in **any slot** (1–3).

```forth
2 ['] my-nic-poll BG-POLL-SLOT
PAUSE PAUSE PAUSE
2 TASK-STOP
```

Multiple slots can run simultaneously:

```forth
['] poll-nic  BG-POLL               \ slot 1
2 ['] poll-usb BG-POLL-SLOT         \ slot 2
3 ['] poll-rtc BG-POLL-SLOT         \ slot 3
PAUSE PAUSE PAUSE                   \ all three run
BG-STOP-ALL
```

---

### `BG-WAIT-DONE`

```forth
BG-WAIT-DONE ( n -- )
```

Busy-wait (calling `PAUSE` each iteration) until slot n finishes
naturally.  When a one-shot background task's xt returns, the cleanup
handler fires and `n TASK?` becomes 0.

Returns immediately if slot n is not active.

Only useful for **one-shot** tasks.  For infinite-loop tasks (e.g.,
those installed by `BG-POLL`), this would spin forever — use
`n TASK-STOP` instead.

```forth
: bg-hash  buf len SHA-256 result 32 CMOVE ;
['] bg-hash BACKGROUND
do-other-work
1 BG-WAIT-DONE           \ wait for hash to finish
\ result buffer is now ready
```

---

### `BG-WAIT-ALL`

```forth
BG-WAIT-ALL ( -- )
```

Busy-wait until all background tasks (slots 1–3) finish naturally.
Only useful when all running tasks are one-shot.

```forth
['] hash-part1 BACKGROUND
['] hash-part2 BACKGROUND2
['] hash-part3 BACKGROUND3
BG-WAIT-ALL               \ wait for all three
```

---

### `BG-STOP-ALL`

```forth
BG-STOP-ALL ( -- )
```

Unconditionally stop all background tasks in slots 1–3.
Equivalent to `1 TASK-STOP 2 TASK-STOP 3 TASK-STOP`.

---

### `BG-INFO`

```forth
BG-INFO ( -- )
```

Print background task status for debugging:

```
[coroutine 1=ON 2=-- 3=ON n=2]
[coroutine 1=-- 2=-- 3=-- n=0]
```

---

## Concurrency Model

### Single-Core Cooperative (Primary Use Case)

The four-task scheduler is designed for single-core cooperative
multitasking.  Task 0 (the main Forth interpreter) and up to three
background helpers take turns explicitly:

```forth
\ Poll NIC + USB while hashing a large buffer
: poll-nic  nic-rx-check ;
: poll-usb  usb-check ;

['] poll-nic BG-POLL               \ slot 1
2 ['] poll-usb BG-POLL-SLOT        \ slot 2

: hash-loop
    BEGIN
        buf 4096 SHA-256-UPDATE
        PAUSE                \ round-robin through active slots
        more-data?
    WHILE REPEAT ;

hash-loop
BG-STOP-ALL
```

### Interaction with KDOS Scheduler

The BIOS cooperative scheduler (SEP-based) is orthogonal to the KDOS
software task scheduler (`SCHEDULE`, `YIELD`, `SPAWN`).  The four
hardware tasks run within a single KDOS task — Task 0 and slots 1–3
all share the same KDOS task slot.

- `PAUSE` / `TASK-YIELD` switch between the hardware threads
- `YIELD` (KDOS word) marks the current KDOS task as done and lets
  the scheduler pick the next KDOS task

These are different mechanisms and should not be confused.

**Note:** KDOS defines `VARIABLE TASK-COUNT` for its own scheduler
slot tracking, which is unrelated to the BIOS `#TASKS` word that
counts active cooperative background tasks.

### Multicore

The cooperative scheduler is per-core.  Each core has its own R20
trampoline and task PC table.  `BACKGROUND` on core 0 only affects
core 0's slots.

---

## Constraints

| Constraint | Reason |
|------------|--------|
| **Three background slots** | Hardware has slots 1–3 (Task 0 is always active). |
| **No preemption** | SEP is explicit — bg tasks only run when Task 0 calls `PAUSE`. |
| **No I/O from bg tasks** | Micro-core lacks Q flip-flop; `EMIT` traps. Use shared variables. |
| **PAUSE ≠ TASK-YIELD** | Calling the wrong yield word from the wrong task crashes. |
| **Shared address space** | All tasks share dictionary and memory. |
| **No `[: ;]` closures** | This BIOS/KDOS does not define anonymous quotations. Use named words with `[']`. |
| **Round-robin ordering** | `PAUSE` scans slots 1→2→3 round-robin; ordering is deterministic but not adjustable. |

---

## Quick Reference

### Public Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `BG-ALIVE?` | `( n -- flag )` | Is slot n active? (TRUE/FALSE) |
| `BG-ANY?` | `( -- flag )` | Any bg task active? |
| `WITH-BACKGROUND` | `( xt-bg xt-body -- )` | Scoped bg in slot 1 with auto-stop |
| `WITH-BG` | `( slot xt-bg xt-body -- )` | Scoped bg in any slot with auto-stop |
| `BG-POLL` | `( xt -- )` | Install polling background loop (slot 1) |
| `BG-POLL-SLOT` | `( slot xt -- )` | Install polling background loop (any slot) |
| `BG-WAIT-DONE` | `( n -- )` | Wait for slot n to finish |
| `BG-WAIT-ALL` | `( -- )` | Wait for all bg tasks to finish |
| `BG-STOP-ALL` | `( -- )` | Stop all bg tasks |
| `BG-INFO` | `( -- )` | Debug status display |

### Internal Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `_BG-START` | `( xt slot -- )` | Dispatch to BACKGROUND/2/3 |
| `_BG-POLL-XT1` | variable | Polling xt storage for slot 1 |
| `_BG-POLL-XT2` | variable | Polling xt storage for slot 2 |
| `_BG-POLL-XT3` | variable | Polling xt storage for slot 3 |
| `_BG-POLL-LOOP1` | `( -- )` | Infinite poll-yield loop (slot 1) |
| `_BG-POLL-LOOP2` | `( -- )` | Infinite poll-yield loop (slot 2) |
| `_BG-POLL-LOOP3` | `( -- )` | Infinite poll-yield loop (slot 3) |

### Dependencies

None.  All BIOS words (`PAUSE`, `TASK-YIELD`, `BACKGROUND`, `BACKGROUND2`,
`BACKGROUND3`, `TASK-STOP`, `TASK?`, `#TASKS`) are always available.
