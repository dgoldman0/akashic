# akashic-scope — Structured Concurrency / Task Groups for KDOS / Megapad-64

Task groups enforce parent-waits-for-children semantics.
Every spawned task belongs to a group, and the group ensures no
orphaned tasks — the parent blocks in `TG-WAIT` until all children
finish, or cancels them with `TG-CANCEL`.

```forth
REQUIRE scope.f
```

`PROVIDED akashic-scope` — safe to include multiple times.
Automatically requires `event.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Data Structure](#data-structure)
- [TASK-GROUP — Define Named Group](#task-group--define-named-group)
- [TG-SPAWN — Spawn Task into Group](#tg-spawn--spawn-task-into-group)
- [TG-WAIT — Wait for All Tasks](#tg-wait--wait-for-all-tasks)
- [TG-CANCEL — Cancel Group](#tg-cancel--cancel-group)
- [TG-ANY — Wait for Any, Cancel Rest](#tg-any--wait-for-any-cancel-rest)
- [WITH-TASKS — Structured Concurrency Block](#with-tasks--structured-concurrency-block)
- [THIS-GROUP — Current Group Variable](#this-group--current-group-variable)
- [Query Words](#query-words)
- [TG-RESET — Reset for Reuse](#tg-reset--reset-for-reuse)
- [Debug](#debug)
- [Error Handling](#error-handling)
- [Binding Table Internals](#binding-table-internals)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Structured concurrency** | No child task can outlive its group. `TG-WAIT` and `WITH-TASKS` guarantee all children complete before the parent proceeds. |
| **First-error capture** | If any task THROWs, the error code is stored in the group's error field (first error wins). The task still counts as completed for accounting. |
| **Cancellation** | `TG-CANCEL` sets a flag that prevents new spawns and signals the done-event. Running tasks can check `TG-CANCELLED?` to exit early. |
| **Nesting** | `WITH-TASKS` saves/restores `THIS-GROUP` on the return stack, so nested blocks interact correctly. |
| **Cooperative scheduling** | All tasks run via KDOS cooperative scheduler (`SPAWN` + `SCHEDULE`). On single core, `TG-WAIT` calls `SCHEDULE` to drive tasks. |
| **FIFO binding table** | Like `future.f`'s ASYNC, `TG-SPAWN` stores (xt, tg) pairs in a circular FIFO that `_TG-RUNNER` reads at execution time. |
| **Prefix convention** | Public: `TG-`. Internal: `_TG-`. |

---

## Data Structure

A task group consists of 5 logical cells (40 bytes) plus a 4-cell
inline event (32 bytes), totaling 9 cells = 72 bytes.

```
+0   active       Count of live tasks in this group
+8   cancelled    0 = normal, -1 = cancelled
+16  done-event   Pointer to embedded event (always → +40)
+24  error        First error code (0 = no error)
+32  name         Pointer to name string (0 = anonymous)
+40  [event]      Embedded event flag
+48  [event]      Embedded event wait-count
+56  [event]      Embedded event waiter-0
+64  [event]      Embedded event waiter-1
```

The done-event is signaled when the active count reaches zero
(i.e., the last task completes via `_TG-DONE`).

### Field Accessors

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `_TG-ACTIVE` | `( tg -- addr )` | Address of active count (+0, identity) |
| `_TG-CANCELLED` | `( tg -- addr )` | Address of cancelled flag (+8) |
| `_TG-EVT` | `( tg -- ev )` | Done-event address (reads pointer at +16) |
| `_TG-ERROR` | `( tg -- addr )` | Address of error field (+24) |
| `_TG-NAME` | `( tg -- addr )` | Address of name pointer (+32) |

---

## TASK-GROUP — Define Named Group

```forth
TASK-GROUP my-workers
```

**Signature:** `( "name" -- )`

Parses a name from the input stream, allocates a 72-byte task group
descriptor, and defines a constant with that name.  The constant
holds the group's base address.

```forth
TASK-GROUP http-fetchers
TASK-GROUP compute-pool
```

---

## TG-SPAWN — Spawn Task into Group

```forth
['] my-worker my-group TG-SPAWN
```

**Signature:** `( xt tg -- )`

Spawn a task into the given task group:
1. If the group is cancelled → no-op (drops xt and tg).
2. If all 8 KDOS task slots are full → no-op.
3. Increments the group's active count.
4. Stores (xt, tg) in the binding FIFO.
5. SPAWNs a `_TG-RUNNER` task.

The user's xt **must** have signature `( -- )`.  Side effects should
be communicated through shared variables, not the data stack.

```forth
TASK-GROUP workers
['] compute-hashes workers TG-SPAWN
['] fetch-data     workers TG-SPAWN
['] compress-log   workers TG-SPAWN
workers TG-WAIT    \ blocks until all 3 finish
```

### Task Slot Limit

KDOS supports at most 8 concurrent task descriptors.  If all slots
are occupied, `TG-SPAWN` silently drops the request.  Plan group
sizes accordingly (typically ≤ 6 tasks per group to leave headroom).

---

## TG-WAIT — Wait for All Tasks

```forth
my-group TG-WAIT
```

**Signature:** `( tg -- )`

Block until all tasks in the group have completed.

**Flow:**
1. **Fast path:** if active count is 0, return immediately.
2. Call `SCHEDULE` to run all READY tasks (essential on single-core).
3. If active count is now 0, return.
4. Otherwise, `EVT-WAIT` on the done-event (multicore path).

Calling `TG-WAIT` on an empty group (no tasks spawned) is a no-op.
Calling it twice is safe (idempotent after completion).

---

## TG-CANCEL — Cancel Group

```forth
my-group TG-CANCEL
```

**Signature:** `( tg -- )`

Mark the group as cancelled:
- Sets the cancelled flag to -1.
- Prevents future `TG-SPAWN` calls from adding tasks.
- Signals the done-event to unblock any pending `TG-WAIT`.

On the cooperative scheduler, already-running tasks cannot be
preempted.  Tasks that check `TG-CANCELLED?` in their body can
exit early for faster cleanup.

Idempotent: calling `TG-CANCEL` twice is harmless.

```forth
: my-worker  ( -- )
    BEGIN
        THIS-GROUP @ TG-CANCELLED? IF EXIT THEN
        do-some-work
    AGAIN ;
```

---

## TG-ANY — Wait for Any, Cancel Rest

```forth
my-group TG-ANY
```

**Signature:** `( tg -- )`

Run spawned tasks via `SCHEDULE`, then cancel the group.

On the cooperative single-core scheduler, `SCHEDULE` runs all ready
tasks to completion, so `TG-ANY` is effectively `SCHEDULE` +
`TG-CANCEL`.  On multicore (future enhancement), this will be
refined to return after the first task completes.

---

## WITH-TASKS — Structured Concurrency Block

```forth
['] my-spawner WITH-TASKS
```

**Signature:** `( xt -- )`

The core structured concurrency primitive:

1. Allocate an anonymous task group.
2. Set `THIS-GROUP` to the new group.
3. Execute xt (which spawns children via `THIS-GROUP @`).
4. Restore `THIS-GROUP` to its previous value.
5. `TG-WAIT` — block until all children complete.

No child task can outlive the `WITH-TASKS` block.

### Usage Pattern

Since this Forth lacks anonymous closures `[: ;]`, the xt must be
a named word that reads `THIS-GROUP @`:

```forth
: spawn-all  ( -- )
    ['] worker-a THIS-GROUP @ TG-SPAWN
    ['] worker-b THIS-GROUP @ TG-SPAWN
    ['] worker-c THIS-GROUP @ TG-SPAWN ;

['] spawn-all WITH-TASKS
\ all 3 workers have completed here
```

### Nesting

`WITH-TASKS` saves and restores `THIS-GROUP` on the return stack,
so nesting works correctly:

```forth
: inner  ( -- )
    ['] sub-task THIS-GROUP @ TG-SPAWN ;

: outer  ( -- )
    ['] main-task THIS-GROUP @ TG-SPAWN
    ['] inner WITH-TASKS ;    \ inner group is fully contained

['] outer WITH-TASKS
\ both main-task and sub-task have completed
```

---

## THIS-GROUP — Current Group Variable

```forth
THIS-GROUP @    \ get current group address
```

**Type:** `VARIABLE`

Holds the address of the current task group set by `WITH-TASKS`.
User code reads it with `THIS-GROUP @` to get the active group
for `TG-SPAWN` calls.

Outside of `WITH-TASKS`, `THIS-GROUP` is 0 (no active group).

---

## Query Words

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `TG-COUNT` | `( tg -- n )` | Number of active (running) tasks |
| `TG-CANCELLED?` | `( tg -- flag )` | TRUE if group is cancelled |
| `TG-ERROR` | `( tg -- n )` | First error code (0 = no error) |

```forth
my-group TG-COUNT .       \ "3 " — 3 tasks still running
my-group TG-CANCELLED? .  \ "0 " — not cancelled
my-group TG-ERROR .       \ "42 " — first task threw 42
```

---

## TG-RESET — Reset for Reuse

```forth
my-group TG-RESET
```

**Signature:** `( tg -- )`

Zero all fields and restore the done-event pointer.  Intended
for testing and group recycling.

**Do NOT call on a group with active tasks or pending TG-WAITs.**

After reset:
- Active count = 0
- Cancelled flag = 0
- Error code = 0
- Done-event = cleared

---

## Debug

### TG-INFO

```forth
my-group TG-INFO
```

**Signature:** `( tg -- )`

Print task group status for debugging:

```
[group active=3  cancelled=0  error=0 ]
```

---

## Error Handling

### CATCH/THROW Integration

Every task spawned via `TG-SPAWN` runs under `CATCH`.  If the
user's xt calls `THROW`, the error code is captured:

```forth
: risky-work  ( -- )
    compute-something
    DUP 0< IF  -1 THROW  THEN   \ signal failure
    store-result ;

['] risky-work my-group TG-SPAWN
my-group TG-WAIT
my-group TG-ERROR ?DUP IF
    ." Task failed with error: " . CR
THEN
```

**Rules:**
- First error wins: if multiple tasks throw, only the first error
  code is stored.
- Error tasks still decrement the active count — `TG-WAIT` won't
  hang because a task threw.
- The group's error field persists until `TG-RESET`.

### Without Error Handling

If error capture is not needed, simply don't THROW:

```forth
: safe-work  ( -- )  1 my-result ! ;
['] safe-work my-group TG-SPAWN
```

---

## Binding Table Internals

`TG-SPAWN` uses a circular FIFO of 8 slots, identical in design
to `future.f`'s ASYNC binding table:

| Array | Purpose |
|-------|---------|
| `_TG-XTS` | Execution token per pending spawn |
| `_TG-TGS` | Task group address per pending spawn |
| `_TG-WIDX` | Write index (advanced by `TG-SPAWN`) |
| `_TG-RIDX` | Read index (advanced by `_TG-RUNNER`) |

The FIFO has 8 entries (matching the 8 KDOS task slots).
Cooperative scheduling guarantees all writes complete before any
runner executes, maintaining strict FIFO order.

`_TG-RUNNER` reads its (xt, tg) binding under `EVT-LOCK`, executes
the xt under `CATCH`, stores any error, and calls `_TG-DONE`
to decrement the group's active count.

---

## Concurrency Model

### Single-Core (Emulator)

On a single core, tasks don't run until `SCHEDULE` is called
(or `TG-WAIT` calls it internally):

```
TG-SPAWN  →  task marked READY in KDOS task table
TG-SPAWN  →  second task marked READY
TG-WAIT   →  calls SCHEDULE
              SCHEDULE runs task 1 to completion
              SCHEDULE runs task 2 to completion
              active count → 0, done-event signaled
              TG-WAIT returns
```

### Multicore (Hardware)

On multicore, tasks are dispatched to different cores.  The
done-event serves as the synchronization point:

```
Core 0: TG-SPAWN → task READY
Core 0: TG-SPAWN → task READY
Core 0: TG-WAIT → SCHEDULE (runs local tasks)
                 → EVT-WAIT (waits for remote tasks)
Core 1: runs task → _TG-DONE → decrements active
Core 2: runs task → _TG-DONE → decrements active → EVT-SET
Core 0: EVT-WAIT exits → TG-WAIT returns
```

### Task Lifetime Guarantee

`WITH-TASKS` provides the strongest guarantee: no child task can
outlive the block.  This is the recommended pattern for production
code:

```forth
: process-batch  ( -- )
    ['] work-a THIS-GROUP @ TG-SPAWN
    ['] work-b THIS-GROUP @ TG-SPAWN ;

['] process-batch WITH-TASKS
\ guaranteed: work-a and work-b are both done here
```

---

## Quick Reference

| Word | Signature | Description |
|------|-----------|-------------|
| `TASK-GROUP` | `( "name" -- )` | Define named task group |
| `TG-SPAWN` | `( xt tg -- )` | Spawn task into group |
| `TG-WAIT` | `( tg -- )` | Wait for all tasks to complete |
| `TG-CANCEL` | `( tg -- )` | Cancel group, unblock TG-WAIT |
| `TG-ANY` | `( tg -- )` | Wait for any, cancel rest |
| `TG-COUNT` | `( tg -- n )` | Active task count |
| `TG-CANCELLED?` | `( tg -- flag )` | Is group cancelled? |
| `TG-ERROR` | `( tg -- n )` | First error code (0 = none) |
| `WITH-TASKS` | `( xt -- )` | Structured concurrency block |
| `THIS-GROUP` | `( -- addr )` | VARIABLE: current group |
| `TG-RESET` | `( tg -- )` | Reset for reuse (testing) |
| `TG-INFO` | `( tg -- )` | Debug display |

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `_TG-SIZE` | 72 | Bytes per task group (9 cells) |

### Dependencies

- **event.f** — `EVT-SET`, `EVT-WAIT`, `EVT-LOCK` for completion signaling
- **KDOS §8** — `SPAWN`, `SCHEDULE`, `TASK-COUNT`, `CATCH`/`THROW`
