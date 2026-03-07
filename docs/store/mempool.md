# akashic-mempool — Transaction Pool for KDOS / Megapad-64

Bounded priority queue of pending transactions, sorted by sender address
(32 bytes) + nonce (u64).  O(log n) duplicate detection via SHA3-256 tx hash.

```forth
REQUIRE mempool.f
```

`PROVIDED akashic-mempool` — depends on `akashic-tx`, `akashic-sha3`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Initialization](#initialization)
- [Transaction Insertion](#transaction-insertion)
- [Transaction Removal](#transaction-removal)
- [Draining](#draining)
- [Queries](#queries)
- [Pruning](#pruning)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Fixed capacity** | 256 slots — bounded memory, no dynamic allocation |
| **Sorted storage** | Binary-search by sender+nonce for O(log n) insert/lookup |
| **Hash dedup** | SHA3-256 seen-set rejects duplicate transactions |
| **Drain buffer** | `MP-DRAIN` pops N highest-priority txs into a caller buffer for block building |
| **Guard-wrapped** | Public API serialized with `WITH-GUARD` |

---

## Initialization

### MP-INIT

```forth
MP-INIT  ( -- )
```

Zero all slots, reset count to 0, clear the seen-hash set.

---

## Transaction Insertion

### MP-ADD

```forth
MP-ADD  ( tx -- flag )
```

Validate the transaction struct, check for duplicates via hash, and
insert into the sorted pool.  Returns `-1` on success, `0` on failure
(duplicate, pool full, or invalid tx).

---

## Transaction Removal

### MP-REMOVE

```forth
MP-REMOVE  ( hash -- flag )
```

Remove a transaction by its SHA3-256 hash.  Returns `-1` if found and
removed, `0` otherwise.

---

## Draining

### MP-DRAIN

```forth
MP-DRAIN  ( n buf -- actual )
```

Pop up to *n* transactions from the pool into *buf* (contiguous tx
structs).  Returns the actual count drained.  Drained slots are held
until `MP-RELEASE` is called.

### MP-RELEASE

```forth
MP-RELEASE  ( -- )
```

Free buffer slots occupied by the last drain operation.

---

## Queries

### MP-COUNT

```forth
MP-COUNT  ( -- n )
```

Number of pending transactions currently in the pool.

### MP-CONTAINS?

```forth
MP-CONTAINS?  ( hash -- flag )
```

Check whether a transaction with the given hash exists in the pool.

---

## Pruning

### MP-PRUNE

```forth
MP-PRUNE  ( -- n )
```

Scan the pool and remove structurally invalid transactions (e.g.,
expired nonces after state advancement).  Returns the number removed.

---

## Concurrency

All public words (`MP-INIT`, `MP-ADD`, `MP-REMOVE`, `MP-DRAIN`,
`MP-RELEASE`, `MP-PRUNE`) are wrapped with a module-level guard to
prevent concurrent access from interrupt or coroutine contexts.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `MP-INIT` | `( -- )` | Initialize empty mempool |
| `MP-ADD` | `( tx -- flag )` | Validate and insert transaction |
| `MP-REMOVE` | `( hash -- flag )` | Remove by tx hash |
| `MP-DRAIN` | `( n buf -- actual )` | Pop up to n txs into buffer |
| `MP-RELEASE` | `( -- )` | Free drained slots |
| `MP-COUNT` | `( -- n )` | Pending transaction count |
| `MP-PRUNE` | `( -- n )` | Remove invalid, return count |
| `MP-CONTAINS?` | `( hash -- flag )` | Check if tx hash is in pool |
| `MP-CAPACITY` | `( -- 256 )` | Maximum pool size |
