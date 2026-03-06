# akashic-critical — Critical Sections & Preemption Control for KDOS / Megapad-64

Nestable preemption control combined with optional hardware spinlock
mutual exclusion.  For code that must not be interrupted or
rescheduled (MMIO register sequences, multi-step hardware operations,
lock-free data structure updates), critical sections are the correct
primitive.

```forth
REQUIRE critical.f
```

`PROVIDED akashic-critical` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Data](#data)
- [Preemption Control — CRITICAL-BEGIN / CRITICAL-END](#preemption-control--critical-begin--critical-end)
- [RAII — WITH-CRITICAL](#raii--with-critical)
- [Spinlock Integration — CRITICAL-LOCK / CRITICAL-UNLOCK](#spinlock-integration--critical-lock--critical-unlock)
- [RAII — WITH-CRITICAL-LOCK](#raii--with-critical-lock)
- [Query & Debug](#query--debug)
- [Concurrency Model](#concurrency-model)
- [Constraints](#constraints)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Nestable** | `CRITICAL-BEGIN` / `CRITICAL-END` use a depth counter.  Only the outermost call touches the hardware preemption flag. |
| **Two layers** | Preemption-only (no lock) for single-core atomicity; preemption + spinlock for multicore safety. |
| **RAII cleanup** | `WITH-CRITICAL` and `WITH-CRITICAL-LOCK` use `CATCH` to guarantee restore even on `THROW`. |
| **Lock ordering** | Preemption is disabled *before* the spinlock is acquired, preventing priority inversion or scheduler deadlock. |
| **Zero allocation** | One global `VARIABLE` (`_crit-depth`).  No heap. |
| **Prefix convention** | Public: `CRITICAL-`.  Internal: `_CRIT-`. |

---

## Data

### _crit-depth — Nesting Counter

```
Variable   _crit-depth   ( -- addr )
```

Holds the current nesting depth.  0 = not in a critical section.
Incremented by `CRITICAL-BEGIN`, decremented by `CRITICAL-END`.
Only the transition 0→1 calls `PREEMPT-OFF`; only the transition
1→0 calls `PREEMPT-ON`.

In a future multicore extension this would become a per-core variable
(one cell per hardware core, indexed by `COREID`).

---

## Preemption Control — CRITICAL-BEGIN / CRITICAL-END

### CRITICAL-BEGIN

```forth
CRITICAL-BEGIN  ( -- )
```

Enter a critical section.  Disables timer-based preemption if this is
the outermost nesting level (depth was 0).  Always increments the
depth counter.

Safe to nest arbitrarily:

```forth
CRITICAL-BEGIN
  \ ... outer critical work ...
  CRITICAL-BEGIN
    \ depth = 2, still protected
  CRITICAL-END
  \ depth = 1, still protected
CRITICAL-END
\ depth = 0, preemption re-enabled
```

### CRITICAL-END

```forth
CRITICAL-END  ( -- )
```

Leave a critical section.  Decrements the depth counter.  Re-enables
preemption only when the outermost scope exits (depth reaches 0).

**Important:** Every `CRITICAL-BEGIN` must be paired with exactly one
`CRITICAL-END`.  Mismatched pairing will leave preemption permanently
disabled (too few ENDs) or enable it prematurely (too many ENDs).

---

## RAII — WITH-CRITICAL

### WITH-CRITICAL

```forth
WITH-CRITICAL  ( xt -- )
```

Execute `xt` with preemption disabled.  If `xt` throws, preemption
is restored before the exception propagates.

```forth
\ Multi-step MMIO sequence that must not be preempted
['] _ntt-load-xform  WITH-CRITICAL
```

Implementation:

```forth
: WITH-CRITICAL  ( xt -- )
    CRITICAL-BEGIN  CATCH  CRITICAL-END
    DUP IF THROW THEN  DROP ;
```

---

## Spinlock Integration — CRITICAL-LOCK / CRITICAL-UNLOCK

### CRITICAL-LOCK

```forth
CRITICAL-LOCK  ( lock# -- )
```

Disable preemption, then acquire hardware spinlock `lock#`.

The ordering matters: preemption is disabled *first* so the scheduler
cannot preempt a task while it holds a spinlock (which would cause
priority inversion or deadlock if a higher-priority task tries the
same lock).

```forth
7 CRITICAL-LOCK
\ ... multicore-safe work under spinlock 7 ...
7 CRITICAL-UNLOCK
```

### CRITICAL-UNLOCK

```forth
CRITICAL-UNLOCK  ( lock# -- )
```

Release hardware spinlock `lock#`, then re-enable preemption (or
decrement the nesting depth if inside a nested critical section).

---

## RAII — WITH-CRITICAL-LOCK

### WITH-CRITICAL-LOCK

```forth
WITH-CRITICAL-LOCK  ( xt lock# -- )
```

Disable preemption, acquire spinlock, execute `xt`, release spinlock,
restore preemption.  If `xt` throws, both the spinlock and preemption
state are properly restored before the exception propagates.

```forth
\ Multicore-safe filesystem write
['] _do-fwrite  2 WITH-CRITICAL-LOCK   \ spinlock 2 = FS
```

Implementation:

```forth
: WITH-CRITICAL-LOCK  ( xt lock# -- )
    DUP >R CRITICAL-LOCK
    CATCH
    R> CRITICAL-UNLOCK
    DUP IF THROW THEN  DROP ;
```

---

## Query & Debug

### CRITICAL-DEPTH

```forth
CRITICAL-DEPTH  ( -- n )
```

Return current nesting depth.  0 = not in a critical section.
Useful for assertions and debugging.

### CRITICAL-INFO

```forth
CRITICAL-INFO  ( -- )
```

Print human-readable status:

```
[critical depth=0 ]
[critical depth=2 ]
```

---

## Concurrency Model

Critical sections operate at two levels:

1. **Single-core** — `CRITICAL-BEGIN` / `CRITICAL-END` disable timer
   preemption, ensuring the current task cannot be rescheduled.
   Cooperative yields (`YIELD?`) are effectively suppressed because
   the preemption flag is never set while the timer is off.

2. **Multicore** — `CRITICAL-LOCK` / `CRITICAL-UNLOCK` add a hardware
   spinlock on top of preemption disable.  Other cores busy-wait on
   the spinlock while the holder executes in a non-preemptible state.

### When to use which

| Scenario | Primitive |
|----------|-----------|
| Single-core MMIO sequence | `CRITICAL-BEGIN` / `CRITICAL-END` |
| Multi-step variable update (single core) | `WITH-CRITICAL` |
| Multicore filesystem operation | `WITH-CRITICAL-LOCK` with lock# 2 |
| Protecting a shared ring buffer | `WITH-CRITICAL-LOCK` with lock# 4 |
| Short atomic flag check | Usually overkill — use `LOCK`/`UNLOCK` directly |

### Interaction with other primitives

- **guard.f** — Guards provide ownership tracking and re-entry
  detection.  Critical sections provide raw preemption control.
  Use guards for module-level protection; critical sections for
  hardware-level atomicity.

- **semaphore.f / event.f** — Do NOT call `SEM-WAIT` or `EVT-WAIT`
  inside a critical section.  These words may yield or spin, but
  preemption is off — the signaling task may never get to run.

- **coroutine.f** — `PAUSE` / `TASK-YIELD` are BIOS hardware words
  and operate independently of KDOS preemption.  They work inside
  critical sections (the BIOS coroutine mechanism is not gated by
  the preemption flag).

---

## Constraints

| Constraint | Detail |
|------------|--------|
| **No blocking inside** | Do not `SEM-WAIT`, `EVT-WAIT`, or busy-spin with `YIELD?` inside a critical section — the waiting task will never be preempted, so the signaler cannot run. |
| **Keep it short** | Preemption is off — long critical sections starve other tasks. |
| **Pair correctly** | Every `CRITICAL-BEGIN` needs a `CRITICAL-END`.  Use `WITH-CRITICAL` to avoid mismatches. |
| **Single-core depth** | `_crit-depth` is a single variable.  Multicore would need per-core storage. |
| **Spinlock ordering** | Always acquire spinlocks in a consistent global order to avoid deadlock between cores. |

---

## Quick Reference

```
CRITICAL-BEGIN       ( -- )            Enter critical section
CRITICAL-END         ( -- )            Leave critical section
CRITICAL-DEPTH       ( -- n )          Query nesting depth
WITH-CRITICAL        ( xt -- )         RAII preemption-safe scope
CRITICAL-LOCK        ( lock# -- )      Preempt-off + spinlock
CRITICAL-UNLOCK      ( lock# -- )      Release spinlock + preempt-on
WITH-CRITICAL-LOCK   ( xt lock# -- )   RAII preempt + spinlock scope
CRITICAL-INFO        ( -- )            Debug display
```

### KDOS Spinlock Assignments (reference)

| Lock# | Resource |
|-------|----------|
| 0 | Dictionary |
| 1 | UART |
| 2 | Filesystem |
| 3 | Heap |
| 4 | Ring buffers |
| 5 | Hash tables |
| 6 | Events (EVT-LOCK) |
| 7 | IPI messaging |
