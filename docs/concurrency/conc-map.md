# akashic-conc-map — Concurrent Hash Map for KDOS / Megapad-64

Thread-safe hash map built on KDOS §19 hash tables and `rwlock.f`.
Provides concurrent read access and exclusive write access via a
per-map reader-writer lock.

```forth
REQUIRE conc-map.f
```

`PROVIDED akashic-conc-map` — safe to include multiple times.
Automatically requires `event.f` and `rwlock.f`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Data Structure](#data-structure)
- [CMAP — Define Concurrent Map](#cmap--define-concurrent-map)
- [CMAP-PUT — Insert / Update](#cmap-put--insert--update)
- [CMAP-GET — Lookup](#cmap-get--lookup)
- [CMAP-DEL — Delete](#cmap-del--delete)
- [CMAP-COUNT — Entry Count](#cmap-count--entry-count)
- [CMAP-EACH — Iterate Entries](#cmap-each--iterate-entries)
- [CMAP-CLEAR — Remove All](#cmap-clear--remove-all)
- [Debug](#debug)
- [Concurrency Model](#concurrency-model)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| **RW-lock per map** | Coarse-grained locking: one `RWLOCK` per map. Multiple readers can access simultaneously; writes are exclusive. Simple and correct. |
| **Built on §19 hash tables** | Wraps KDOS `HASHTABLE`, `HT-PUT`, `HT-GET`, `HT-DEL`, `HT-EACH`. Open-addressing with linear probing and CRC-32 hashing. |
| **Snapshot iteration** | `CMAP-EACH` holds `READ-LOCK` for the entire scan, giving point-in-time consistency. |
| **Byte-array keys/values** | Keys and values are fixed-size byte arrays (set at creation). For cell-sized integers, use `keysize=8, valsize=8`. |
| **Prefix convention** | Public: `CMAP-`. Internal: `_CM-`. |

---

## Data Structure

A concurrent map consists of:

1. **CMAP header** (12 cells = 96 bytes):

```
+0   ht           Pointer to underlying HASHTABLE descriptor
+8   rwlock       Inline rwlock (11 cells = 88 bytes)
     +8   lock#       Spinlock number (EVT-LOCK = 6)
     +16  readers     Active reader count
     +24  writer      Writer flag
     +32  read-event  (4 cells)
     +64  write-event (4 cells)
```

2. **HASHTABLE** (allocated inline before the header):

```
+0   keysize     Bytes per key
+8   valsize     Bytes per value
+16  slots       Number of slots
+24  count       Occupied slot count
+32  lock#       Spinlock number (HT-LOCK = 5)
+40  data...     slots × (1 + keysize + valsize) bytes
```

Each hash table slot: `[flag][key bytes][value bytes]`
- Flag: 0 = empty, 1 = occupied, 2 = tombstone

---

## CMAP — Define Concurrent Map

```forth
8 8 31 CMAP my-cache
```

**Signature:** `( keysize valsize slots "name" -- )`

Create a named concurrent hash map.  Allocates the underlying hash
table data and the CMAP header with an inline rwlock.

Parameters:
- **keysize**: bytes per key (8 for cell-sized integers)
- **valsize**: bytes per value (8 for cell-sized integers)
- **slots**: number of hash table slots (prime numbers recommended
  for better distribution: 7, 13, 31, 61, 127, 251, 509)

```forth
8  8  31 CMAP int-cache     \ cell-sized keys and values, 31 slots
16 8  61 CMAP name-cache    \ 16-byte string keys, 8-byte values
```

---

## CMAP-PUT — Insert / Update

```forth
key-addr val-addr my-cache CMAP-PUT
```

**Signature:** `( key-addr val-addr cm -- )`

Insert or update a key-value pair under `WRITE-LOCK`.

- `key-addr`: pointer to key bytes (exactly `keysize` bytes)
- `val-addr`: pointer to value bytes (exactly `valsize` bytes)

If the key already exists, its value is overwritten (count unchanged).
If the key is new and a slot is available, it's inserted (count
incremented).

```forth
CREATE my-key 8 ALLOT   42 my-key !
CREATE my-val 8 ALLOT   99 my-val !
my-key my-val my-cache CMAP-PUT
```

---

## CMAP-GET — Lookup

```forth
key-addr my-cache CMAP-GET   ( -- val-addr | 0 )
```

**Signature:** `( key-addr cm -- val-addr | 0 )`

Look up a key under `READ-LOCK`.  Returns a pointer to the value
within the hash table, or 0 if not found.

**Important:** The returned pointer is valid only while the entry
exists.  Copy the value immediately if the entry might be deleted
concurrently:

```forth
my-key my-cache CMAP-GET DUP IF
    @                    \ read value (8-byte cell)
    ." Found: " . CR
ELSE
    ." Not found" CR
THEN
```

---

## CMAP-DEL — Delete

```forth
key-addr my-cache CMAP-DEL   ( -- flag )
```

**Signature:** `( key-addr cm -- flag )`

Delete a key under `WRITE-LOCK`.  Returns -1 if found and deleted,
0 if the key was absent.

Deletion uses tombstoning (the slot is marked with flag=2), which
preserves linear-probing chains.

---

## CMAP-COUNT — Entry Count

```forth
my-cache CMAP-COUNT .   ( -- n )
```

**Signature:** `( cm -- n )`

Number of occupied entries, read under `READ-LOCK`.

---

## CMAP-EACH — Iterate Entries

```forth
['] my-handler my-cache CMAP-EACH
```

**Signature:** `( xt cm -- )`

Iterate all occupied entries under `READ-LOCK`.  The xt is called
once per entry with `( key-addr val-addr -- )`.

Provides snapshot semantics: the entire iteration happens under a
single read lock, so the view is consistent.

```forth
: show-entry  ( key val -- )
    ." key=" SWAP @ . ."  val=" @ . CR ;

['] show-entry my-cache CMAP-EACH
```

---

## CMAP-CLEAR — Remove All

```forth
my-cache CMAP-CLEAR
```

**Signature:** `( cm -- )`

Zero-fill all hash table data under `WRITE-LOCK`.  Resets count to 0.
All entries become empty.  The map can be reused immediately.

---

## Debug

### CMAP-INFO

```forth
my-cache CMAP-INFO
```

**Signature:** `( cm -- )`

Print map status:

```
[cmap count=3  slots=31  ksize=8  vsize=8  rw:[rwlock lock#=6
  readers=0  writer=0  ...] ]
```

---

## Concurrency Model

### Read/Write Separation

| Operation | Lock Type | Concurrent? |
|-----------|-----------|-------------|
| `CMAP-GET` | `READ-LOCK` | Multiple readers OK |
| `CMAP-COUNT` | `READ-LOCK` | Multiple readers OK |
| `CMAP-EACH` | `READ-LOCK` | Multiple readers OK |
| `CMAP-PUT` | `WRITE-LOCK` | Exclusive |
| `CMAP-DEL` | `WRITE-LOCK` | Exclusive |
| `CMAP-CLEAR` | `WRITE-LOCK` | Exclusive |

### Single-Core

On single core, the RW lock operates without contention.  All
operations acquire and release the lock immediately.

### Multicore

On multicore, multiple cores can read simultaneously via
`CMAP-GET` / `CMAP-EACH`.  Write operations block until all
readers finish and no other writer is active.

### Future Enhancement: Per-Bucket Locking

The current coarse-grained approach uses one lock per map.  For
high-contention multicore workloads, per-bucket RW locks (hashed
to available spinlocks modulo 8) would reduce contention.  The
current API is forward-compatible with this change.

---

## Quick Reference

| Word | Signature | Description |
|------|-----------|-------------|
| `CMAP` | `( ksize vsize slots "name" -- )` | Create concurrent map |
| `CMAP-PUT` | `( key-addr val-addr cm -- )` | Thread-safe insert/update |
| `CMAP-GET` | `( key-addr cm -- val-addr \| 0 )` | Read-locked lookup |
| `CMAP-DEL` | `( key-addr cm -- flag )` | Thread-safe delete |
| `CMAP-COUNT` | `( cm -- n )` | Entry count |
| `CMAP-EACH` | `( xt cm -- )` | Iterate (snapshot semantics) |
| `CMAP-CLEAR` | `( cm -- )` | Remove all entries |
| `CMAP-INFO` | `( cm -- )` | Debug display |

### Constants

| Name | Value | Description |
|------|-------|-------------|
| `_CM-SIZE` | 96 | Bytes per cmap header (12 cells) |

### Dependencies

- **event.f** — via rwlock.f
- **rwlock.f** — `READ-LOCK`, `READ-UNLOCK`, `WRITE-LOCK`, `WRITE-UNLOCK`
- **KDOS §19** — `HASHTABLE` layout, `HT-PUT`, `HT-GET`, `HT-DEL`, `HT-EACH`, `HT-COUNT`
