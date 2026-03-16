# akashic-undo — Undo / Redo System for Gap Buffer

Two stacks of edit records with coalescing.  Consecutive same-type,
adjacent edits merge into a single undoable action (sequential typing
/ backspacing).  Entries are moved between stacks on undo/redo — no
copying.

```forth
REQUIRE text/undo.f
```

`PROVIDED akashic-undo` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Edit Types](#edit-types)
- [Descriptor Layout](#descriptor-layout)
- [Constructor / Destructor](#constructor--destructor)
- [Recording Edits](#recording-edits)
- [Undo / Redo](#undo--redo)
- [Coalescing](#coalescing)
- [Quick Reference](#quick-reference)
- [Dependencies](#dependencies)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Dual stack** | Separate undo and redo stacks with matching semantics. |
| **Edit coalescing** | Sequential typing / deleting merges into one record. |
| **Move semantics** | Undo/redo moves entries between stacks — no allocation. |
| **Bounded** | Max 512 entries per stack; oldest evicted when full. |
| **Prefix convention** | Public: `UNDO-`. Internal: `_UD-` (state), `_UE-` (entry). |

---

## Edit Types

| Constant | Value | Description |
|----------|-------|-------------|
| `UNDO-T-INS` | 0 | Text was inserted |
| `UNDO-T-DEL` | 1 | Text was deleted |

---

## Descriptor Layout

### Undo State (56 bytes / 7 cells)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | `ustk` | Undo stack array (cell-pointers to entries) |
| +8 | `ucap` | Undo max entries (512) |
| +16 | `ucnt` | Current undo count |
| +24 | `rstk` | Redo stack array |
| +32 | `rcap` | Redo max entries (512) |
| +40 | `rcnt` | Current redo count |
| +48 | `coal` | Coalescing flag (−1 = on, 0 = off) |

### Undo Entry (40 bytes / 5 cells)

| Offset | Field | Description |
|--------|-------|-------------|
| +0 | `type` | `UNDO-T-INS` or `UNDO-T-DEL` |
| +8 | `pos` | Byte offset in buffer |
| +16 | `len` | Byte count |
| +24 | `data` | `ALLOCATE`'d copy of affected bytes |
| +32 | `dcap` | Allocated capacity of data buffer |

---

## Constructor / Destructor

### UNDO-NEW

```
( -- ud )
```

Allocate a new undo state.  Both stacks start empty; coalescing
starts enabled.

### UNDO-FREE

```
( ud -- )
```

Free all entries on both stacks, the stack arrays, and the
descriptor.

```forth
UNDO-NEW  ( ud )
\ ... record edits, undo, redo ...
UNDO-FREE
```

---

## Recording Edits

### UNDO-PUSH

```
( type pos addr u ud -- )
```

Record an edit.  Clears the redo stack (any new edit after undo
discards the redo history).  Attempts to coalesce with the top undo
entry.  If coalescing fails, creates a new entry.

```forth
\ After inserting "Hi" at position 0:
UNDO-T-INS  0  S" Hi"  my-ud  UNDO-PUSH

\ After deleting 3 bytes at position 5:
UNDO-T-DEL  5  deleted-addr 3  my-ud  UNDO-PUSH
```

---

## Undo / Redo

### UNDO-UNDO

```
( gb ud -- flag )
```

Undo the most recent edit.  Reverses the operation on the gap
buffer: an insert is undone by deleting; a delete is undone by
re-inserting the saved bytes.  Moves the entry to the redo stack.
Returns `−1` if an edit was undone, `0` if nothing to undo.

### UNDO-REDO

```
( gb ud -- flag )
```

Re-apply the most recently undone edit.  Moves the entry back to the
undo stack.  Returns `−1` if applied, `0` if nothing to redo.

Both operations break coalescing — the next `UNDO-PUSH` will start a
new entry.

### UNDO-CAN-UNDO?

```
( ud -- flag )
```

True if the undo stack is non-empty.

### UNDO-CAN-REDO?

```
( ud -- flag )
```

True if the redo stack is non-empty.

---

## Coalescing

Consecutive `UNDO-PUSH` calls merge into a single entry when all of
these hold:

1. **Same edit type** (both insert or both delete)
2. **Adjacent position** — for insert: new `pos = old pos + old len`;
   for backspace-delete: `new pos + new len = old pos`;
   for forward-delete: `new pos = old pos`
3. **No newline** in the new data
4. **Coalescing enabled** (not broken)

Coalescing breaks automatically on:

- **Newline** in the edited text
- **Cursor jump** (non-adjacent position)
- **Undo or redo** execution
- **Explicit break** via `UNDO-BREAK`

### UNDO-BREAK

```
( ud -- )
```

Force a coalescing break.  The next `UNDO-PUSH` starts a fresh entry.

### UNDO-CLEAR

```
( ud -- )
```

Free all entries from both stacks.

---

## Quick Reference

| Word | Stack | Description |
|------|-------|-------------|
| `UNDO-T-INS` | `( -- 0 )` | Edit type: insert |
| `UNDO-T-DEL` | `( -- 1 )` | Edit type: delete |
| `UNDO-NEW` | `( -- ud )` | Create undo state |
| `UNDO-FREE` | `( ud -- )` | Free undo state |
| `UNDO-PUSH` | `( type pos addr u ud -- )` | Record edit |
| `UNDO-UNDO` | `( gb ud -- flag )` | Undo last edit |
| `UNDO-REDO` | `( gb ud -- flag )` | Redo last undo |
| `UNDO-CLEAR` | `( ud -- )` | Clear both stacks |
| `UNDO-BREAK` | `( ud -- )` | Break coalescing |
| `UNDO-CAN-UNDO?` | `( ud -- flag )` | Undo available? |
| `UNDO-CAN-REDO?` | `( ud -- flag )` | Redo available? |

---

## Dependencies

- `text/gap-buf.f` — `GB-MOVE!`, `GB-INS`, `GB-DEL` (used by undo/redo execution)

## Consumers

- Akashic Pad — per-document undo state

## Internal State

Module-level `VARIABLE`s:

- `_UD-T` — current undo-state handle
- `_UDO-E`, `_UDO-GB` — entry / gap buffer during undo/redo execution
- `_UC-TYPE`, `_UC-POS`, `_UC-ADDR`, `_UC-LEN`, `_UC-E` — coalescing temporaries
- `_UE-A` through `_UE-D` — entry construction temporaries

Not reentrant without the `GUARDED` guard section.
