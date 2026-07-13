# akashic-guard — Recursive cross-core guards

`guard.f` provides statically declared mutual-exclusion guards for KDOS and
Megapad-64. A guard serializes access by an execution owner identified by the
pair `(hardware core, execution-context token)` and supports recursive
acquisition by that same owner.

```forth
REQUIRE guard.f
```

`PROVIDED akashic-guard` makes repeated inclusion safe.

## Contract

| Property | Contract |
|---|---|
| Cross-core exclusion | Claim, recursion, and release metadata transitions are serialized by a hardware spinlock. |
| Owner identity | Core ID plus the core-0 KDOS task descriptor or negative BIOS `TASK-ID`. BIOS workers use `(COREID, 0)`, so different zero-context workers remain distinct. |
| Recursive entry | The same execution owner may acquire repeatedly; each release removes one level. |
| Non-owner release | Releasing a free guard or another owner's guard throws `GUARD-E-NOT-OWNER` (`-257`). |
| Scoped cleanup | `WITH-GUARD` releases before propagating a body `THROW`. |
| Coroutine boundary | BIOS slots are distinct owners. Do not carry a guard across `TASK-YIELD`: a waiting foreground cannot schedule the suspended holder. |
| Allocation | Guard declarations allocate static dictionary storage only. |
| Publication | A full release publishes writes made in the protected body before a later successful acquisition. |

Recursive behavior is intentional. Akashic public wrappers frequently call
lower-level public words protected by the same module guard. Treating this as
an error would either deadlock those wrappers or require unsafe unguarded
backdoors.

## Memory layout

### Spinning guard — 4 cells / 32 bytes

| Offset | Field | Meaning |
|---:|---|---|
| 0 | depth | `0` when free; positive recursive depth while held |
| 8 | owner-core | Hardware core ID of the holder |
| 16 | owner-task | Core-0 KDOS task descriptor, negative BIOS slot token, or `0` on a worker |
| 24 | mode | `0`, spinning |

### Blocking guard — 9 cells / 72 bytes

The first four cells are identical. At offset 32 is an embedded five-cell,
one-count semaphore; mode is `1`.

The old internal names `_GRD-FLAG` and `_GRD-OWNER` remain compatibility
aliases for `_GRD-DEPTH` and `_GRD-OWNER-TASK`. Code outside the guard module
should use the public query words instead of inspecting these fields.

## Creation

```forth
GUARD short-state-guard
GUARD-BLOCKING longer-state-guard
```

`GUARD` retries with `YIELD?`, the compatibility name for KDOS
`CORE-CHECKPOINT`, when another owner holds it. It is suitable for short
critical sections with rare contention. On secondary full cores the checkpoint
only acknowledges that worker's preemption flag; it does not enter the core-0
scheduler or touch `CURRENT-TASK`.

`GUARD-BLOCKING` waits through an embedded semaphore. Its acquisition loop uses
short `SEM-WAIT-TIMEOUT` retries, which yield and recheck the permit instead of
depending on observing a transient event pulse. Recursive entry bypasses the
semaphore, so it does not consume an additional permit.

## Acquire and release

### `GUARD-TRY-ACQUIRE`

```forth
GUARD-TRY-ACQUIRE ( guard -- acquired? )
```

Make one non-blocking attempt. It returns true if the caller claimed a free
guard or recursively entered its own guard. A successful call must eventually
be balanced by `GUARD-RELEASE`.

```forth
cache-guard GUARD-TRY-ACQUIRE IF
    update-cache
    cache-guard GUARD-RELEASE
THEN
```

### `GUARD-ACQUIRE`

```forth
GUARD-ACQUIRE ( guard -- )
```

Wait until acquisition succeeds. Spinning guards retry with `YIELD?`.
Blocking guards wait for their semaphore permit in bounded, yield-aware
increments and then publish ownership atomically.

### `GUARD-ACQUIRE-TIMEOUT`

```forth
GUARD-ACQUIRE-TIMEOUT ( guard ms -- acquired? )
```

Retry for at most `ms` milliseconds. The first acquisition attempt is always
made, so a zero timeout still succeeds if the guard is immediately available.
A true result owns one recursion level and must be released; false owns
nothing.

The timeout path polls with `YIELD?` for both guard flavors. This keeps the
deadline bounded and avoids holding either guard metadata or event state
across a yield.

### `GUARD-RELEASE`

```forth
GUARD-RELEASE ( guard -- )
```

Remove one recursive level. At depth one it clears ownership and, for a
blocking guard, signals the semaphore after the metadata lock has been
released.

Only the owning `(core, execution-context)` pair may release. A different core
does not become the owner merely because both it and the holder use context
token `0`.

## Scoped execution

```forth
WITH-GUARD ( xt guard -- )
```

`WITH-GUARD` acquires the guard, executes `xt`, releases the guard, and then
rethrows any exception from `xt`. Normal body results remain on the data
stack.

```forth
: update-index  ( item -- )
    ['] index-insert index-guard WITH-GUARD ;
```

This is the preferred form when the protected operation can throw. KDOS
exception-chain heads are per physical worker or core-0 BIOS task, so
simultaneous `WITH-GUARD` calls do not overwrite one another's `CATCH` frames.
A body must still not call `PAUSE` or `TASK-YIELD`, because the foreground can
otherwise block while the guard holder is suspended and unschedulable.

## Queries

```forth
GUARD-HELD? ( guard -- flag )
GUARD-MINE? ( guard -- flag )
GUARD-INFO  ( guard -- )
```

`GUARD-HELD?` is a lock-free aligned status snapshot. It must not be used as a
check before an unguarded claim; only the acquisition words make that decision
atomically.

`GUARD-MINE?` takes the short metadata lock and compares both owner fields.

`GUARD-INFO` takes a coherent metadata snapshot, releases the lock, and only
then prints. Example output:

```text
[guard spin FREE]
[guard blocking HELD core=1 task=0 depth=2]
```

## Synchronization details

Guard metadata shares `EVT-LOCK` with the event and semaphore primitives. A
guard holds it only around a few aligned metadata loads and stores. In
particular, it is released before:

- `SEM-WAIT-TIMEOUT`, `SEM-SIGNAL`, or `SEM-TRYWAIT`
- any event operation
- `YIELD?`
- the guarded body
- `CATCH` or `THROW`
- diagnostic output

This short shared lock closes the old cross-core check-then-set race without
holding a hardware spinlock for the duration of arbitrary Forth code. Internal
code that has manually acquired `EVT-LOCK` must not call a guard operation;
event and semaphore public words already manage that lock themselves.

On the current MP64 memory system, hardware-lock release/acquire is the
publication boundary: body stores precede the releasing unlock, and a later
acquirer observes them after its successful locked metadata transition.

## Owner identity

`CURRENT-TASK` is a KDOS scheduler variable owned by core 0; it is not
per-core TLS. The guard identity helper therefore uses:

- `(0, CURRENT-TASK @)` in the core-0 foreground (`TASK-ID = 0`)
- `(0, -TASK-ID)` in core-0 BIOS background slots 1–3
- `(COREID, 0)` on BIOS worker cores

There is currently one dispatched BIOS execution per worker core. If KDOS
later schedules multiple tasks on secondary cores, it must first expose a
per-core current-task identity and the guard helper must adopt it.

A guard must not be held across task migration. Migration is not part of the
current KDOS task model.

The owner pair distinguishes BIOS coroutine slots through `TASK-ID`; a
foreground attempt can no longer be mistaken for recursive entry into a guard
held by a background slot. Acquire and final release must nevertheless occur
in the same uninterrupted coroutine activation. A spinning or blocking wait in
the foreground cannot run `PAUSE` to resume the suspended holder, so carrying a
guard across `TASK-YIELD` creates a scheduler-level deadlock even though owner
identity and KDOS `CATCH` chains are now correct.

KDOS `CORE-CHECKPOINT`/`YIELD?` is not a BIOS coroutine switch. Its final
multicore action is deferred so early-compiled users such as `LOCK` reach the
installed per-core implementation: core 0 may update its scheduler task,
whereas a secondary one-shot worker only clears its own preemption flag.

## What a guard does not guarantee

Mutual exclusion does not make every operation worker-safe. A guarded word may
still be core-affine because it uses UI state, terminal I/O, dictionary or heap
mutation, the active VFS selector, an applet's module-global current-state
pointer, or another owner-only service.

Consequently, globally enabling every optional `GUARDED` wrapper is not a
multicore-safety policy. Each public surface still needs an execution class
such as owner-only, serialized service, pure, snapshot-read, or
exclusive-buffer.

Do not hold long-lived guards around event loops. A guard around an entire Desk
or app-shell run would serialize for the application's lifetime rather than
provide a worker completion boundary.

## Quick reference

| Word | Stack effect | Behavior |
|---|---|---|
| `GUARD` | `( "name" -- )` | Declare a spinning recursive guard |
| `GUARD-BLOCKING` | `( "name" -- )` | Declare a semaphore-backed recursive guard |
| `GUARD-TRY-ACQUIRE` | `( guard -- flag )` | Attempt without waiting |
| `GUARD-ACQUIRE` | `( guard -- )` | Wait until acquired |
| `GUARD-ACQUIRE-TIMEOUT` | `( guard ms -- flag )` | Bounded acquisition |
| `GUARD-RELEASE` | `( guard -- )` | Release one depth; reject non-owner |
| `WITH-GUARD` | `( xt guard -- )` | Exception-safe scoped execution |
| `GUARD-HELD?` | `( guard -- flag )` | Lock-free status snapshot |
| `GUARD-MINE?` | `( guard -- flag )` | Test the complete execution owner |
| `GUARD-INFO` | `( guard -- )` | Print a coherent metadata snapshot |

### Error code

| Constant | Value | Meaning |
|---|---:|---|
| `GUARD-E-NOT-OWNER` | -257 | Release attempted by a non-owner or on a free guard |

### Dependencies

- `semaphore.f`
- `event.f` transitively
- KDOS/BIOS `COREID`, `CURRENT-TASK`, `TASK-ID`, `LOCK`, `UNLOCK`, `CORE-CHECKPOINT`
  (`YIELD?`), and `EPOCH@`
