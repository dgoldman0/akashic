# akashic-persist — Chain Persistence for KDOS / Megapad-64

Disk-backed persistence using KDOS file I/O primitives.  Block log and
state snapshots are stored in two files on the MP64FS filesystem:
`chain.dat` (append-only block log) and `state.snap` (periodic snapshot).

```forth
REQUIRE persist.f
```

`PROVIDED akashic-persist` — depends on `akashic-block`, `akashic-state`,
`akashic-guard`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Disk Layout](#disk-layout)
- [Initialization](#initialization)
- [Saving Blocks](#saving-blocks)
- [Loading Blocks](#loading-blocks)
- [State Snapshots](#state-snapshots)
- [Queries](#queries)
- [Shutdown](#shutdown)
- [Concurrency](#concurrency)
- [KDOS Constraints](#kdos-constraints)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Append-only** | Block log grows monotonically — no in-place edits |
| **Disk-backed** | Two files on MP64FS: `chain.dat`, `state.snap` |
| **Length-prefixed** | Each log entry: `[8B cbor_len][cbor_len bytes]` |
| **Linear scan** | `PST-LOAD-BLOCK` walks entries sequentially — acceptable for small chains |
| **Auto-create** | `PST-INIT` creates files via MKFILE if they don't exist |
| **Guard-wrapped** | All public words serialized via `WITH-GUARD` |

---

## Disk Layout

### chain.dat  (~512 KB, 1024 sectors)

Append-only block log. Each entry is length-prefixed:

```
Offset  Content
------  -------
  0     [8 bytes: CBOR length of block 0]
  8     [CBOR data for block 0]
  8+L0  [8 bytes: CBOR length of block 1]
 16+L0  [CBOR data for block 1]
  ...
```

A length of 0 or a short read marks end-of-data.

### state.snap  (~20 KB, 40 sectors)

Periodic state snapshot. Fixed layout:

```
[ST-SNAPSHOT-SIZE bytes]  — account table + count
[8 bytes]                 — chain height at snapshot time
```

---

## Initialization

### PST-INIT

```forth
PST-INIT  ( -- flag )
```

Open (or create) `chain.dat` and `state.snap` on disk.  Walks
the existing chain log to count saved blocks.  Returns `-1` on
success, `0` if the filesystem couldn't be loaded or file I/O failed.

Calls `FS-ENSURE` internally — the filesystem is loaded from disk
automatically if not already mounted.

---

## Saving Blocks

### PST-SAVE-BLOCK

```forth
PST-SAVE-BLOCK  ( blk -- flag )
```

Encode the block via `BLK-ENCODE` into an internal 16 KB scratch
buffer, seek to end of `chain.dat`, then write the 8-byte length
prefix followed by the CBOR data.  Flushes immediately.

Returns `-1` on success, `0` if `PST-INIT` hasn't been called or
the block couldn't be encoded.

---

## Loading Blocks

### PST-LOAD-BLOCK

```forth
PST-LOAD-BLOCK  ( idx blk -- flag )
```

Rewind `chain.dat`, walk to entry *idx* by reading and skipping
each preceding entry's 8-byte length + data.  Read the target entry
and decode via `BLK-DECODE`.

Returns `-1` on success, `0` if the index is out of range, `PST-INIT`
hasn't been called, or decoding fails.

---

## State Snapshots

### PST-SAVE-STATE

```forth
PST-SAVE-STATE  ( -- flag )
```

Snapshot the full state tree (`ST-SNAPSHOT`) into the internal
scratch buffer, then write it plus the 8-byte chain height to
`state.snap`.  Flushes immediately.  Returns `-1` on success.

### PST-LOAD-STATE

```forth
PST-LOAD-STATE  ( -- flag )
```

Read `state.snap` into the internal scratch buffer, restore via
`ST-RESTORE`.  Returns `-1` on success, `0` if the file is empty
or a short read occurs.

---

## Queries

### PST-BLOCK-COUNT

```forth
PST-BLOCK-COUNT  ( -- n )
```

Number of blocks currently in the log.  Computed once at `PST-INIT`
and incremented by each `PST-SAVE-BLOCK`.

### PST-CLEAR

```forth
PST-CLEAR  ( -- )
```

Rewind `chain.dat` and write a zero-length marker at offset 0.
Resets block count to 0.  The file itself is not deleted.

---

## Shutdown

### PST-CLOSE

```forth
PST-CLOSE  ( -- )
```

Flush and close both file descriptors (`chain.dat` and `state.snap`).
Resets internal state.  A subsequent `PST-INIT` will reopen the
files and re-scan the block log.

---

## Concurrency

All seven public words are wrapped with `_pst-guard` via `WITH-GUARD`:
`PST-INIT`, `PST-SAVE-BLOCK`, `PST-LOAD-BLOCK`, `PST-CLEAR`,
`PST-SAVE-STATE`, `PST-LOAD-STATE`, `PST-CLOSE`.

---

## KDOS Constraints

| Constraint | Impact |
|---|---|
| MP64FS contiguous allocation | Files pre-allocated at fixed sector counts (1024 chain, 40 state) |
| Files cannot be resized | Over-allocate at creation; `chain.dat` caps at ~512 KB |
| FD pool is 16 slots | persist uses at most 2; 14 remain for application use |
| FREAD/FWRITE use DMA | All I/O goes through the 16 KB `_PST-BUF` scratch buffer |
| OPEN/MKFILE parse from input | Handled via `S" OPEN chain.dat" EVALUATE` |

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `PST-INIT` | `( -- flag )` | Open/create files, count existing blocks |
| `PST-SAVE-BLOCK` | `( blk -- flag )` | Encode + append to chain.dat |
| `PST-LOAD-BLOCK` | `( idx blk -- flag )` | Decode block N from chain.dat |
| `PST-BLOCK-COUNT` | `( -- n )` | Number of saved blocks |
| `PST-CLEAR` | `( -- )` | Reset log (write zero marker) |
| `PST-SAVE-STATE` | `( -- flag )` | Snapshot state to state.snap |
| `PST-LOAD-STATE` | `( -- flag )` | Restore state from state.snap |
| `PST-CLOSE` | `( -- )` | Flush + close all files |
