# akashic-persist — Chain Persistence for KDOS / Megapad-64

Append-only block log in extended memory (XMEM) with state snapshot
support.  On restart, replay saved blocks to rebuild chain state.

```forth
REQUIRE persist.f
```

`PROVIDED akashic-persist` — depends on `akashic-block`, `akashic-state`,
`akashic-guard`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Block Log Format](#block-log-format)
- [Initialization](#initialization)
- [Saving Blocks](#saving-blocks)
- [Loading Blocks](#loading-blocks)
- [State Snapshots](#state-snapshots)
- [Queries](#queries)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Append-only** | Block log grows monotonically — no in-place edits |
| **XMEM-backed** | 1 MB region in extended memory (16 MB address space) |
| **Length-prefixed** | Each log entry: `[cell: cbor_len][cbor_len bytes]` |
| **Linear scan** | `PST-LOAD-BLOCK` walks entries sequentially — acceptable for small chains |
| **Guard-wrapped** | `PST-INIT`, `PST-SAVE-BLOCK`, `PST-LOAD-BLOCK`, `PST-CLEAR` serialized |

---

## Block Log Format

The block log is a contiguous region in XMEM:

```
Offset  Content
------  -------
  0     [8 bytes: CBOR length of block 0]
  8     [CBOR data for block 0]
  8+L0  [8 bytes: CBOR length of block 1]
 16+L0  [CBOR data for block 1]
  ...
```

Each entry is 8 + `cbor_len` bytes.  The write cursor (`_PST-LOG-POS`)
tracks the next available offset.

---

## Initialization

### PST-INIT

```forth
PST-INIT  ( -- )
```

Allocate a 1 MB region in XMEM for the block log.  Reset write
position and block count to 0.

---

## Saving Blocks

### PST-SAVE-BLOCK

```forth
PST-SAVE-BLOCK  ( blk -- flag )
```

Encode the block via `BLK-ENCODE`, then append the length-prefixed
entry to the log.  Returns `-1` on success, `0` if the block couldn't
be encoded or the log is full.

---

## Loading Blocks

### PST-LOAD-BLOCK

```forth
PST-LOAD-BLOCK  ( idx blk -- flag )
```

Walk the log to entry *idx*, decode the CBOR data into *blk* via
`BLK-DECODE`.  Returns `-1` on success, `0` if the index is out of
range or decoding fails.

---

## State Snapshots

### PST-SAVE-STATE

```forth
PST-SAVE-STATE  ( dst -- )
```

Copy the full state snapshot (`ST-SNAPSHOT`) plus the chain height
into a caller-supplied buffer.  Layout:

```
[ST-SNAPSHOT-SIZE bytes]  [8-byte chain height]
```

Total size: `ST-SNAPSHOT-SIZE + 8` bytes.

### PST-LOAD-STATE

```forth
PST-LOAD-STATE  ( src -- )
```

Restore state from a buffer previously written by `PST-SAVE-STATE`.

---

## Queries

### PST-BLOCK-COUNT

```forth
PST-BLOCK-COUNT  ( -- n )
```

Number of blocks currently in the log.

### PST-CLEAR

```forth
PST-CLEAR  ( -- )
```

Reset the log — discard all saved blocks.  Does not free XMEM.

---

## Concurrency

`PST-INIT`, `PST-SAVE-BLOCK`, `PST-LOAD-BLOCK`, and `PST-CLEAR` are
wrapped with `_pst-guard` via `WITH-GUARD`.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `PST-INIT` | `( -- )` | Allocate XMEM, reset log |
| `PST-SAVE-BLOCK` | `( blk -- flag )` | Encode + append block |
| `PST-LOAD-BLOCK` | `( idx blk -- flag )` | Decode block N from log |
| `PST-BLOCK-COUNT` | `( -- n )` | Number of saved blocks |
| `PST-CLEAR` | `( -- )` | Discard all blocks |
| `PST-SAVE-STATE` | `( dst -- )` | Snapshot state + height |
| `PST-LOAD-STATE` | `( src -- )` | Restore state + height |
