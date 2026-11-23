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
| **Indexed load** | `PST-INIT` walks the log once to build an offset index; `PST-LOAD-BLOCK` seeks straight to its entry |
| **Records sized from need** | One kept record buffer grows to the largest record; records the files cannot hold are refused whole |
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

### state.snap  (~256 KB, 512 sectors)

Periodic state snapshot:

```
[snapshot bytes]   — ST-SNAPSHOT: account count, page count, the pages in order
[8 bytes]          — chain height at snapshot time
[8 bytes]          — the snapshot's size, read first by PST-LOAD-STATE
```

The snapshot holds no memory address, so a later session loads it
into pages of its own.

`PST-SET-CAPACITY ( chain-sectors state-sectors -- )`, called before
`PST-INIT`, sets both files' sector counts when they are created.

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

Encode the block via `BLK-ENCODE` into the record buffer, seek to end
of `chain.dat`, then write the 8-byte length prefix followed by the
CBOR data.  Flushes immediately.

Returns `-1` on success, `0` if `PST-INIT` hasn't been called, the
heap cannot hold the block's encoding, or the chain file cannot hold
its record.  A record that does not fit is refused before anything is
written, so the log keeps only whole records.

### The record buffer

Each record passes whole through one scratch buffer: a block's
encoding on its way to the log, a block read back, and a state snapshot
in either direction.  The buffer comes from the heap (XMEM when
present) the first time a record needs it and is kept.  When a record
needs more, the buffer grows to twice its size, or to the record's size
when that is more: `BLK-ENCODED-SIZE` gives a block's size, the state's
`ST-SNAPSHOT-BYTES` gives a snapshot's, and a record read back is bounded by
the file that holds it.  A full block of 256 hybrid transactions
encodes to about 2.1 MB.

KDOS's XMEM heap reuses freed blocks first-fit and never joins them, so
a buffer freed and taken again at each record's size would leave a hole
of each size behind.  The kept buffer grows once per doubling, and the
holes it leaves are together smaller than the buffer.

---

## Loading Blocks

### PST-LOAD-BLOCK

```forth
PST-LOAD-BLOCK  ( idx blk -- flag )
```

Seek to entry *idx* through the offset index `PST-INIT` builds, read
its 8-byte length and the record into the record buffer, and decode it
via `BLK-DECODE`.

Returns `-1` on success, `0` if the index is out of range, `PST-INIT`
hasn't been called, the record's length runs past the file's end, the
heap cannot hold the record, or decoding fails.

---

## State Snapshots

### PST-SAVE-STATE

```forth
PST-SAVE-STATE  ( -- flag )
```

Snapshot the state (`ST-SNAPSHOT`) into the record buffer, then write
the snapshot (`ST-SNAPSHOT-BYTES` long), the 8-byte chain height and an
8-byte size marker to `state.snap`.  Flushes immediately.  Returns `-1` on success,
`0` if the heap or the state file cannot hold the snapshot.

### PST-LOAD-STATE

```forth
PST-LOAD-STATE  ( -- flag )
```

Read the size marker from the end of `state.snap`, then the snapshot
into the record buffer, and restore via `ST-RESTORE`.  Returns `-1` on
success, `0` if the file is empty, the marker is larger than
`ST-SNAPSHOT-SIZE` or than the file, a short read occurs, or the
snapshot's header gives a size other than the marker's
(`ST-SNAPSHOT-LEN`).  The state is left as it was when it returns `0`.

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
| MP64FS contiguous allocation | Files pre-allocated at fixed sector counts (1024 chain, 512 state by default; `PST-SET-CAPACITY` sets others) |
| Files cannot be resized | Over-allocate at creation; a save that does not fit returns `0` and writes nothing |
| FD pool is 16 slots | persist uses at most 2; 14 remain for application use |
| FREAD/FWRITE use DMA | Whole sectors move between the disk and the record buffer; partial sectors pass through KDOS's own sector scratch, so the 8-byte length cell needs only 8 bytes |
| XMEM heap never joins free blocks | The record buffer is kept and grows by doubling (see [The record buffer](#the-record-buffer)) |
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
