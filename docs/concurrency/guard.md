# akashic-guard — Non-Reentrant Guards for KDOS / Megapad-64

Declarative mutual-exclusion wrappers for Forth words that access
shared state.  A guard ensures that only one task at a time can execute
a protected region, and detects (and aborts on) re-entry instead of
deadlocking.

```forth
REQUIRE guard.f
```

`PROVIDED akashic-guard` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation](#creation)
- [Acquire / Release](#acquire--release)
- [RAII — WITH-GUARD](#raii--with-guard)
- [Query](#query)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Constraints](#constraints)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Two flavors** | Spinning guard (busy-wait + `YIELD?`) or blocking guard (semaphore-backed, yields). |
| **Re-entry detection** | If the current task already holds the guard, `GUARD-ACQUIRE` throws -257 instead of deadlocking. |
| **RAII cleanup** | `WITH-GUARD` uses `CATCH` to guarantee release even on `THROW`. |
| **Zero heap allocation** | Guards are statically declared with defining words. |
| **Prefix convention** | Public: `GUARD-`.  Internal: `_GRD-`. |
| **Building block** | Protects shared `VARIABLE`s in fp16.f, mat2d.f, MMIO wrappers, etc. |

---

## Memory Layout

### Spinning Guard — 3 cells = 24 bytes

```
Offset  Size   Field
──────  ─────  ─────────────
0       8      flag     (0 = free, -1 = held)
8       8      owner    (task descriptor of holder, or 0)
16      8      mode     (0 = spin)
```

### Blocking Guard — 8 cells = 64 bytes

```
Offset  Size   Field
──────  ─────  ─────────────
0       8      flag     (0 = free, -1 = held)
8       8      owner    (task descriptor of holder, or 0)
16      8      mode     (1 = blocking)
24      40     sem      (embedded 1-count semaphore)
```

The embedded semaphore starts with count 1 (one permit).  When the
guard is acquired, `SEM-WAIT` decrements the permit to 0.  A second
acquirer blocks on the semaphore until the first releases.

---

## Creation

### `GUARD`

```forth
GUARD ( "name" -- )
```

Create a named **spinning** guard, initially free.  Spinning guards
busy-wait with `YIELD?` — suitable for short critical sections where
contention is rare.

```forth
GUARD fp16-guard
GUARD mmio-guard
```

### `GUARD-BLOCKING`

```forth
GUARD-BLOCKING ( "name" -- )
```

Create a named **blocking** guard, initially free.  Blocking guards
yield via an embedded semaphore — suitable for longer critical sections
or when spinning would waste too many cycles.

```forth
GUARD-BLOCKING fs-guard
GUARD-BLOCKING hash-guard
```

---

## Acquire / Release

### `GUARD-ACQUIRE`

```forth
GUARD-ACQUIRE ( guard -- )
```

Acquire the guard.  Behavior depends on the guard's mode:

- **Spinning:** busy-waits on the flag cell, calling `YIELD?` each
  iteration.
- **Blocking:** calls `SEM-WAIT` on the embedded semaphore (yields
  to the scheduler while waiting).

**Re-entry detection:** if the guard is currently held and the owner
is the current task, throws -257 immediately instead of deadlocking.

```forth
fp16-guard GUARD-ACQUIRE
\ ... use shared fp16 state ...
fp16-guard GUARD-RELEASE
```

### `GUARD-RELEASE`

```forth
GUARD-RELEASE ( guard -- )
```

Release the guard.  Clears the owner and flag.  For blocking guards,
also signals the embedded semaphore to wake one waiting task.

```forth
fp16-guard GUARD-RELEASE
```

---

## RAII — WITH-GUARD

### `WITH-GUARD`

```forth
WITH-GUARD ( xt guard -- )
```

Acquire the guard, execute `xt`, then release the guard.  If `xt`
throws an exception, the guard is **still released** before the
exception propagates (uses `CATCH` internally).

This is the recommended way to use guards — it guarantees cleanup.

```forth
: my-fp16-op  ( x y -- z )  FP16+ FP16* ;

['] my-fp16-op  fp16-guard WITH-GUARD
```

**Exception safety:**

```forth
: risky-op  42 THROW ;
['] risky-op  fp16-guard ['] WITH-GUARD CATCH
\ guard is released, CATCH returns 42
```

---

## Query

### `GUARD-HELD?`

```forth
GUARD-HELD? ( guard -- flag )
```

Non-blocking query.  Returns TRUE (-1) if the guard is currently held,
FALSE (0) otherwise.  Lock-free — reads a single flag cell.

```forth
fp16-guard GUARD-HELD? IF ." busy" CR THEN
```

### `GUARD-MINE?`

```forth
GUARD-MINE? ( guard -- flag )
```

Returns TRUE (-1) if the **current task** holds this guard.  Returns
FALSE if the guard is free or held by a different task.

```forth
fp16-guard GUARD-MINE? IF ." I hold it" CR THEN
```

---

## Debug

### `GUARD-INFO`

```forth
GUARD-INFO ( guard -- )
```

Print guard status:

```
[guard spin FREE]
[guard blocking HELD owner=4839520]
```

---

## Concurrency Model

### Single-Core Cooperative

On a single core with the KDOS cooperative scheduler, guards are most
useful for preventing **re-entry** — a second KDOS task calling the
same guarded word while the first task is mid-execution:

```forth
GUARD fp16-guard

: SAFE-FP16+  ( x y -- z )
    ['] FP16+  fp16-guard WITH-GUARD ;
```

When Task A holds the guard and `YIELD?` causes Task B to run, Task B
will block on `SAFE-FP16+` until Task A releases the guard.

### Multicore

Guards also work across cores.  The spinning variant uses `YIELD?`
which checks the preemption flag — safe for multicore.  The blocking
variant uses `SEM-WAIT` which is itself spinlock-protected (EVT-LOCK).

For multicore-critical MMIO sequences where preemption must also be
disabled, combine WITH-GUARD with critical sections (see critical.f).

### Re-entry Detection

Re-entry throws -257 rather than deadlocking.  Use `CATCH` to handle
re-entry gracefully:

```forth
['] guarded-op ['] WITH-GUARD CATCH
DUP -257 = IF
    DROP  \ re-entry detected, handle gracefully
THEN
```

---

## Constraints

| Constraint | Reason |
|------------|--------|
| **No nesting same guard** | Re-entry throws -257 by design. Use separate guards for nested resources. |
| **Owner tracks CURRENT-TASK** | Outside the KDOS scheduler (CURRENT-TASK = 0), ownership tracking is limited. |
| **Spinning wastes cycles** | Spinning guards busy-wait.  Use `GUARD-BLOCKING` for long critical sections. |
| **Blocking needs scheduler** | `GUARD-BLOCKING` relies on `SEM-WAIT` which calls `YIELD?`.  Works with or without the KDOS scheduler running. |

---

## Quick Reference

### Public Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `GUARD` | `( "name" -- )` | Create spinning guard |
| `GUARD-BLOCKING` | `( "name" -- )` | Create blocking guard (semaphore-backed) |
| `GUARD-ACQUIRE` | `( guard -- )` | Acquire (throws -257 on re-entry) |
| `GUARD-RELEASE` | `( guard -- )` | Release |
| `WITH-GUARD` | `( xt guard -- )` | RAII execute under guard |
| `GUARD-HELD?` | `( guard -- flag )` | Is guard held? |
| `GUARD-MINE?` | `( guard -- flag )` | Am I the holder? |
| `GUARD-INFO` | `( guard -- )` | Debug display |

### Internal Words

| Word | Signature | Behavior |
|------|-----------|----------|
| `_GRD-FLAG` | `( guard -- addr )` | Flag cell accessor |
| `_GRD-OWNER` | `( guard -- addr )` | Owner cell accessor |
| `_GRD-MODE` | `( guard -- addr )` | Mode cell accessor |
| `_GRD-SEM` | `( guard -- sem )` | Embedded semaphore accessor |

### Error Codes

| Code | Meaning |
|------|---------|
| -257 | Guard re-entry detected (same task tried to acquire twice) |

### Dependencies

- `semaphore.f` (for `GUARD-BLOCKING`)
- `event.f` (transitive, via semaphore.f)
