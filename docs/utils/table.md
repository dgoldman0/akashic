# akashic-table — Slot-Array / Table Abstraction for KDOS / Megapad-64

Fixed-width slot array with alloc/free/iterate.  Useful for DNS caches,
session pools, record lists — any collection where entries share a fixed
layout and you need O(1) alloc, free, and indexed access.

```forth
REQUIRE table.f
```

`PROVIDED akashic-table` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Memory Layout](#memory-layout)
- [Creation](#creation)
- [Allocation & Freeing](#allocation--freeing)
- [Query](#query)
- [Iteration](#iteration)
- [Bulk Operations](#bulk-operations)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **Fixed width** | All slots share the same byte size, set at creation. |
| **Flag byte** | Each slot has a 1-byte used/free flag preceding its data. |
| **No heap** | The caller supplies a pre-allocated buffer (`CREATE` / `ALLOT`). |
| **Prefix convention** | Public API: `TBL-`. Internal helpers: `_TBL-`. |
| **XT callbacks** | `TBL-EACH` and `TBL-FIND` accept execution tokens. |

---

## Memory Layout

A table occupies a contiguous block:

```
Offset  Size   Field
──────  ─────  ─────────────
0       8      slot-size   (cell)
8       8      max-slots   (cell)
16      8      used-count  (cell)
24      1+S    slot 0:  [flag | data ...]
24+1×S  1+S    slot 1
  ...
```

Where `S` = slot-size.  Stride per slot = `1 + S`.

Total bytes needed: `24 + max-slots × (1 + slot-size)`.

---

## Creation

### `TBL-CREATE`

```forth
TBL-CREATE ( slot-size max-slots addr -- )
```

Initialise a table at `addr`.  Stores the header fields and
zeros all slot flags.

```forth
CREATE MY-TABLE 256 ALLOT
16 8 MY-TABLE TBL-CREATE    \ 8 slots of 16 bytes each
```

---

## Allocation & Freeing

### `TBL-ALLOC`

```forth
TBL-ALLOC ( tbl -- slot-addr | 0 )
```

Find the first free slot, mark it as used, increment the count,
and return a pointer to the slot's **data area**.  Returns `0` if
all slots are occupied.

```forth
MY-TABLE TBL-ALLOC    \ → addr (or 0 if full)
42 OVER !             \ store 42 at slot[0]
```

### `TBL-FREE`

```forth
TBL-FREE ( tbl slot-addr -- )
```

Mark the slot as free and decrement the used count.  `slot-addr`
must be a data pointer previously returned by `TBL-ALLOC` or
`TBL-SLOT`.

```forth
MY-TABLE slot TBL-FREE
```

---

## Query

### `TBL-COUNT`

```forth
TBL-COUNT ( tbl -- n )
```

Number of currently used slots.

### `TBL-SLOT`

```forth
TBL-SLOT ( tbl idx -- slot-addr | 0 )
```

Return the data address of slot `idx` (0-based).  Returns `0` if
the index is out of range **or** the slot is free.

```forth
MY-TABLE 3 TBL-SLOT   \ → addr or 0
```

---

## Iteration

### `TBL-EACH`

```forth
TBL-EACH ( tbl xt -- )
```

Execute `xt` once for every **used** slot.  The execution token
receives `( slot-addr -- )`.

```forth
: SHOW-SLOT  @ . ;
MY-TABLE ['] SHOW-SLOT TBL-EACH    \ prints all stored values
```

### `TBL-FIND`

```forth
TBL-FIND ( tbl xt -- slot-addr | 0 )
```

Find the first used slot for which `xt` returns true.
`xt` signature: `( slot-addr -- flag )`.

```forth
: IS-42?  @ 42 = ;
MY-TABLE ['] IS-42? TBL-FIND    \ → addr of first slot holding 42, or 0
```

---

## Bulk Operations

### `TBL-FLUSH`

```forth
TBL-FLUSH ( tbl -- )
```

Mark all slots free and reset the used count to 0.

```forth
MY-TABLE TBL-FLUSH
MY-TABLE TBL-COUNT    \ → 0
```

---

## Quick Reference

| Word | Stack Effect | Description |
|------|-------------|-------------|
| `TBL-CREATE` | `( slot-size max-slots addr -- )` | Initialise table |
| `TBL-ALLOC` | `( tbl -- slot-addr \| 0 )` | Allocate next free slot |
| `TBL-FREE` | `( tbl slot-addr -- )` | Free a slot |
| `TBL-COUNT` | `( tbl -- n )` | Number of used slots |
| `TBL-SLOT` | `( tbl idx -- slot-addr \| 0 )` | Slot by index |
| `TBL-EACH` | `( tbl xt -- )` | Iterate used slots |
| `TBL-FIND` | `( tbl xt -- slot-addr \| 0 )` | Search used slots |
| `TBL-FLUSH` | `( tbl -- )` | Free all slots |
