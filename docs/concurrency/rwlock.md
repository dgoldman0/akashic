# akashic-rwlock — Reader-Writer Locks for KDOS / Megapad-64

Multiple concurrent readers OR one exclusive writer.  Critical for
shared lookup tables (font cache, route table, hash tables) that
are read-heavy.

```forth
REQUIRE rwlock.f
```

`PROVIDED akashic-rwlock` — safe to include multiple times.
Automatically requires `event.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation](#creation)
- [Read Access](#read-access)
- [Write Access](#write-access)
- [Query](#query)
- [RAII Patterns](#raii-patterns)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Shared reads** | Multiple readers proceed concurrently; no exclusion between readers. |
| **Exclusive writes** | A writer blocks until all readers and any prior writer drain. |
| **Per-lock spinlock** | Each rwlock carries its own `lock#` — unrelated locks don't contend. |
| **Embedded events** | Two 4-cell events inlined at +24 and +56; no heap, no indirection. |
| **Prefix convention** | Public: `READ-`, `WRITE-`, `RW-`, `WITH-`.  Internal: `_RW-`. |
| **RAII support** | `WITH-READ` / `WITH-WRITE` wrap lock/exec/unlock with CATCH. |

---

## Memory Layout

An rwlock occupies 11 cells = 88 bytes:

```
Offset  Size     Field
──────  ───────  ─────────────────
0       8        lock#            (hardware spinlock number, 0–7)
8       8        readers          (active reader count)
16      8        writer           (-1 if write-locked, 0 otherwise)
24      32       read-event       (embedded EVENT — 4 cells)
  24      8        flag
  32      8        wait-count
  40      8        waiter-0
  48      8        waiter-1
56      32       write-event      (embedded EVENT — 4 cells)
  56      8        flag
  64      8        wait-count
  72      8        waiter-0
  80      8        waiter-1
```

- **read-event** is pulsed when a writer unlocks, waking blocked
  readers.
- **write-event** is pulsed when the last reader unlocks or a
  writer unlocks, waking a blocked writer.

---

## Creation

### `RWLOCK`

```forth
RWLOCK ( lock# "name" -- )
```

Create a named reader-writer lock that uses the given hardware
spinlock for its critical sections.

```forth
6 RWLOCK cache-rw        \ uses spinlock 6 (EVT-LOCK)
5 RWLOCK route-rw        \ uses spinlock 5 (Hash)
```

`EVT-LOCK` (6) is a reasonable default when no dedicated spinlock
is available.  Multiple rwlocks can share the same spinlock number —
correctness is preserved, only contention increases.

---

## Read Access

### `READ-LOCK`

```forth
READ-LOCK ( rwl -- )
```

Acquire shared read access.  Blocks while a writer is active.
Multiple readers can hold the lock simultaneously.

```forth
cache-rw READ-LOCK
\ ... read shared data ...
cache-rw READ-UNLOCK
```

**Protocol:**
1. Lock spinlock
2. If no writer → `readers++`, unlock, done
3. If writer active → unlock, wait on read-event, retry

### `READ-UNLOCK`

```forth
READ-UNLOCK ( rwl -- )
```

Release read access.  If this was the last active reader, pulse
write-event to wake any blocked writer.

```forth
cache-rw READ-UNLOCK
```

---

## Write Access

### `WRITE-LOCK`

```forth
WRITE-LOCK ( rwl -- )
```

Acquire exclusive write access.  Blocks while any readers are
active OR another writer holds the lock.

```forth
cache-rw WRITE-LOCK
\ ... modify shared data ...
cache-rw WRITE-UNLOCK
```

**Protocol:**
1. Lock spinlock
2. If readers=0 AND writer=0 → set `writer=-1`, unlock, done
3. Otherwise → unlock, wait on write-event, retry

### `WRITE-UNLOCK`

```forth
WRITE-UNLOCK ( rwl -- )
```

Release write access.  Pulses both read-event (wake waiting
readers) and write-event (wake a waiting writer).

```forth
cache-rw WRITE-UNLOCK
```

---

## Query

### `RW-READERS`

```forth
RW-READERS ( rwl -- n )
```

Return the current active reader count.  Lock-free — reads a
single aligned cell.

```forth
cache-rw RW-READERS .       \ "3 " if 3 readers active
```

### `RW-WRITER?`

```forth
RW-WRITER? ( rwl -- flag )
```

Return TRUE (-1) if a writer currently holds the lock.  Lock-free.

```forth
cache-rw RW-WRITER? IF ." locked for writing" THEN
```

---

## RAII Patterns

### `WITH-READ`

```forth
WITH-READ ( xt rwl -- )
```

Acquire read lock, execute `xt`, release — even if `xt` throws
an exception.  Uses `CATCH` / `THROW` for exception safety.

```forth
['] show-cache cache-rw WITH-READ
```

Equivalent to:

```forth
cache-rw READ-LOCK
['] show-cache CATCH
cache-rw READ-UNLOCK
THROW
```

### `WITH-WRITE`

```forth
WITH-WRITE ( xt rwl -- )
```

Acquire write lock, execute `xt`, release — even if `xt` throws.

```forth
['] flush-cache cache-rw WITH-WRITE
```

Equivalent to:

```forth
cache-rw WRITE-LOCK
['] flush-cache CATCH
cache-rw WRITE-UNLOCK
THROW
```

---

## Debug

### `RW-INFO`

```forth
RW-INFO ( rwl -- )
```

Print rwlock status:

```
[rwlock lock#=6 readers=2 writer=0 revt:[event UNSET waiters=0]
 wevt:[event UNSET waiters=0]
]
```

---

## Concurrency Model

### Multicore Read-Heavy Pattern

Multiple cores read concurrently; one core writes with exclusion:

```forth
6 RWLOCK font-cache-rw

: lookup-glyph  ( codepoint -- addr )
    font-cache-rw READ-LOCK
    glyph-table SEARCH
    font-cache-rw READ-UNLOCK ;

: rasterize-glyph  ( codepoint -- )
    font-cache-rw WRITE-LOCK
    render-and-store
    font-cache-rw WRITE-UNLOCK ;
```

Cores 1–3 can all call `lookup-glyph` simultaneously.  When core 0
calls `rasterize-glyph`, it waits for all readers to finish, takes
exclusive access, writes, then releases — allowing readers to
resume.

### Fairness

The current implementation is **reader-preferring**: if readers
continuously hold the lock, a writer may wait indefinitely.  This
is acceptable for read-heavy structures where writes are rare
(cache invalidation, config reload).

If writer starvation becomes an issue in practice, a future
revision can add a `write-waiting` flag that blocks new readers
when a writer is queued.

### Implementation Notes

- **Per-lock spinlock** guards `readers` and `writer` field
  mutations.  The spinlock is held only for a few instructions
  (check + increment/decrement), never across the main
  operation.

- **read-event** is pulsed by `WRITE-UNLOCK` to wake all readers
  that were blocked behind the writer.

- **write-event** is pulsed by `READ-UNLOCK` (when last reader
  drains) and by `WRITE-UNLOCK` (to wake the next queued writer).

- **`WITH-READ` / `WITH-WRITE`** use `CATCH` / `THROW` so unlocks
  happen even on exceptions.  Prefer them over manual lock/unlock
  pairs.

---

## Quick Reference

| Word            | Signature              | Behavior                            |
|-----------------|------------------------|-------------------------------------|
| `RWLOCK`        | `( lock# "name" -- )` | Create reader-writer lock           |
| `READ-LOCK`     | `( rwl -- )`           | Acquire shared read access          |
| `READ-UNLOCK`   | `( rwl -- )`           | Release read access                 |
| `WRITE-LOCK`    | `( rwl -- )`           | Acquire exclusive write access      |
| `WRITE-UNLOCK`  | `( rwl -- )`           | Release write access                |
| `WITH-READ`     | `( xt rwl -- )`        | RAII: read lock, execute, unlock    |
| `WITH-WRITE`    | `( xt rwl -- )`        | RAII: write lock, execute, unlock   |
| `RW-READERS`    | `( rwl -- n )`         | Active reader count (lock-free)     |
| `RW-WRITER?`    | `( rwl -- flag )`      | Writer active? (lock-free)          |
| `RW-INFO`       | `( rwl -- )`           | Debug display                       |

### Internal Words

| Word           | Signature          | Behavior                              |
|----------------|--------------------|---------------------------------------|
| `_RW-LOCK#`    | `( rwl -- addr )`  | Address of lock# cell (+0)            |
| `_RW-READERS`  | `( rwl -- addr )`  | Address of readers cell (+8)          |
| `_RW-WRITER`   | `( rwl -- addr )`  | Address of writer cell (+16)          |
| `_RW-REVT`     | `( rwl -- ev )`    | Address of embedded read-event (+24)  |
| `_RW-WEVT`     | `( rwl -- ev )`    | Address of embedded write-event (+56) |

### Constants

| Name          | Value | Meaning                      |
|---------------|-------|------------------------------|
| `_RW-CELLS`   | 11    | Cells per rwlock descriptor  |
| `_RW-SIZE`    | 88    | Bytes per rwlock descriptor  |
