# block.f — Block Structure & Chain Management

Block-level data structures, serialization, verification, and chain
management for the Akashic ledger, built on Megapad-64.

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Block Header Layout](#block-header-layout)
- [Block Body Layout](#block-body-layout)
- [Lifecycle](#lifecycle)
- [Building](#building)
- [Finalization](#finalization)
- [Hashing](#hashing)
- [Serialization](#serialization)
- [Verification](#verification)
- [Chain Management](#chain-management)
- [Consensus Integration](#consensus-integration)
- [Debug](#debug)
- [Quick Reference](#quick-reference)
- [Usage Examples](#usage-examples)
- [Internals](#internals)

---

## Design Principles

| Principle | Details |
|---|---|
| **Pointer-based body** | Tx pointer array stores addresses of external `TX-BUF-SIZE` buffers; tx data is not inline |
| **Ring-buffer chain** | Only the last `CHAIN-HISTORY` (64) headers are retained; older blocks require re-fetch |
| **Single mutation point** | `CHAIN-APPEND` is the only path that permanently mutates global state |
| **Non-destructive verify and finalize** | `BLK-VERIFY` and `BLK-FINALIZE` use `ST-SNAPSHOT` / `ST-RESTORE` to tentatively apply, read the state root, then roll back |
| **Delegated consensus** | Callback variable `_BLK-CON-CHECK-XT` defaults to always-true; `consensus.f` patches it |
| **DAG-CBOR encoding** | Both `BLK-HASH` and `BLK-ENCODE` use DAG-CBOR canonical key ordering |
| **Concurrency-safe** | All mutating public words wrapped with `WITH-GUARD` |

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `BLK-MAX-TXS` | 256 | Maximum transactions per block |
| `BLK-PROOF-MAX` | 128 | Maximum consensus proof bytes |
| `CHAIN-HISTORY` | 256 | Recent block headers kept in ring buffer |
| `BLK-HDR-SIZE` | 248 | Block header size (8-byte aligned) |
| `BLK-STRUCT-SIZE` | 2304 | Total block struct size (header + count + pointer array) |
| `_BLK-CBUF-SZ` | 2048 | Internal CBOR encode/hash buffer (sized for future STARK proofs) |

---

## Block Header Layout

248 bytes, 8-byte aligned:

| Offset | Size | Field | Description |
|---|---|---|---|
| 0 | 1 | `version` | Protocol version (u8, currently 1) |
| 1 | 8 | `height` | Block height (u64) |
| 9 | 32 | `prev_hash` | SHA3-256 of previous block |
| 41 | 32 | `state_root` | SMT Merkle root of global state |
| 73 | 32 | `tx_root` | Merkle root of transaction hashes |
| 105 | 8 | `timestamp` | Unix seconds (u64) |
| 113 | 1 | `proof_len` | Consensus proof length (0..128) |
| 114 | 128 | `proof` | Consensus proof data |

---

## Block Body Layout

Immediately after the 248-byte header:

| Offset | Size | Field | Description |
|---|---|---|---|
| +248 | 8 | `tx_count` | Number of transactions (cell) |
| +256 | 2048 | `tx_ptrs` | 256 × 8-byte pointers to external tx buffers |

---

## Lifecycle

### BLK-INIT

```forth
BLK-INIT  ( blk -- )
```

Zero the entire `BLK-STRUCT-SIZE` struct and set `version` to 1.

---

## Building

### BLK-SET-PREV

```forth
BLK-SET-PREV  ( hash blk -- )
```

Copy 32-byte hash into the `prev_hash` field.

### BLK-SET-HEIGHT

```forth
BLK-SET-HEIGHT  ( n blk -- )
```

Store block height.

### BLK-SET-TIME

```forth
BLK-SET-TIME  ( t blk -- )
```

Store Unix timestamp.

### BLK-SET-PROOF

```forth
BLK-SET-PROOF  ( addr len blk -- )
```

Copy consensus proof data.  Silently rejects if `len > BLK-PROOF-MAX`.

### BLK-ADD-TX

```forth
BLK-ADD-TX  ( tx blk -- flag )
```

Append a transaction pointer to the block body.  Returns `FALSE` if the
block is full (`>= BLK-MAX-TXS`), otherwise stores the pointer,
increments the count, and returns `TRUE`.

---

## Finalization

### BLK-FINALIZE

```forth
BLK-FINALIZE  ( blk -- )
```

Block producer finalization path:
1. Snapshot the state with `ST-SNAPSHOT`
2. Apply the transactions tentatively via `ST-APPLY-TX`; on the first
   failure, truncate `tx_count` to the valid prefix and stop (P22)
3. Compute the state Merkle root via `ST-ROOT` → `state_root`, then give
   the state back with `ST-RESTORE`
4. Compute the Merkle root of the kept transactions' hashes → `tx_root`

**Leaves the state as it was.**  `CHAIN-APPEND` is the single mutation
point for state: the producer finalizes its block, seals it, and
appends it, and `CHAIN-APPEND` verifies and applies it as it would a
block from a peer.  Failing transactions are silently dropped — the
block contains only the leading run of valid transactions, and its
`tx_root` covers exactly those.  `BLK-FINALIZE` and `BLK-VERIFY` share
one `ST-SNAPSHOT-SIZE` buffer in XMEM, taken on first use.

---

## Hashing

### BLK-HASH

```forth
BLK-HASH  ( blk hash -- )
```

CBOR-encode the 7 header fields in DAG-CBOR canonical key order, then
SHA3-256 the result into the 32-byte `hash` buffer.  The encoding keeps
its caller's CBOR cursors, so `BLK-HASH` can run in the middle of
another encoding, as gossip's status message calls it.

Key order (shorter first, then lexicographic):
`proof`(5) < `height`(6) < `tx_root`(7) < `version`(7) < `prev_hash`(9) <
`timestamp`(9) < `state_root`(10).

---

## Serialization

### BLK-ENCODE

```forth
BLK-ENCODE  ( blk buf max -- len )
```

Serialize the full block to CBOR.  Outer structure is a 2-element array
`[header-map, txs-array]`.  Each tx is encoded as a nested CBOR byte
string via `TX-ENCODE`, which keeps this encoding's CBOR cursors.
Returns the encoded length, or 0 when the block does not fit in `max`
bytes.  `BLK-ENCODE` keeps its own caller's cursors too.

### BLK-ENCODED-SIZE

```forth
BLK-ENCODED-SIZE  ( blk -- n )
```

Return the number of bytes `BLK-ENCODE` writes for the block, so a
caller can size its buffer from the block.  It runs the same encoding
into a buffer of 0 bytes, where the CBOR encoder counts each byte it
drops (`CBOR-SIZE`), and keeps its caller's cursors.  It costs about
what an encoding costs: each transaction is still encoded into the
scratch buffer to learn its length.

### BLK-DECODE

```forth
BLK-DECODE  ( buf len blk -- flag )
```

Deserialize a full block from CBOR.  Decodes the 7 header fields from
the map, validates the version byte (must equal `_BLK-VERSION`, currently
1), then decodes all transaction bodies with `TX-DECODE` and adds them
with `BLK-ADD-TX`; `TX-DECODE` keeps this decoding's CBOR cursors, so
each transaction follows the one before it.  Returns `TRUE` on
success, `FALSE` on parse or version error, or when the heap cannot
hold a transaction buffer.  `BLK-DECODE` keeps its own caller's
cursors too.

The transactions go in block.f's decode buffers, one `TX-BUF-SIZE`
buffer each.  A buffer comes from the heap the first time a block needs
that many and is reused by every later `BLK-DECODE`, so decoding leaves
the dictionary as it was, and a decoded block's transactions stay valid
until the next `BLK-DECODE`.  A caller that keeps a decoded block past
that copies its transactions first.  `BLK-MAX-TXS` bounds the buffers,
as it bounds a block.

---

## Verification

### BLK-VERIFY

```forth
BLK-VERIFY  ( blk prev-hash -- flag )
```

Full, non-destructive block validation:
1. `prev_hash` matches supplied hash
2. Timestamp is non-zero (except genesis)
3. All transactions pass `TX-VERIFY`
4. No duplicate `(sender, nonce)` pairs (O(n²), bounded by n ≤ 256)
5. Transaction Merkle root matches `tx_root`; a block that fails keeps
   the `tx_root` it claimed
6. State root matches — uses `ST-SNAPSHOT` / `ST-RESTORE` to
   tentatively apply transactions, compare `ST-ROOT`, then roll back.
   The tentative apply goes through state.f's `_ST-APPLY-VERIFIED`,
   which makes every check of `ST-APPLY-TX` except the signature step 3
   has verified.
7. Consensus proof passes `_BLK-CON-CHECK-XT` callback

Returns `TRUE` if valid, `FALSE` otherwise, and nothing else.

### Getters (read-only, not guarded)

```forth
BLK-VERSION@    ( blk -- n )        \ Protocol version
BLK-HEIGHT@     ( blk -- n )        \ Block height
BLK-TX-COUNT@   ( blk -- n )        \ Transaction count
BLK-TIME@       ( blk -- n )        \ Unix timestamp
BLK-PREV-HASH@  ( blk -- addr )     \ -> 32-byte prev_hash
BLK-STATE-ROOT@ ( blk -- addr )     \ -> 32-byte state_root
BLK-TX-ROOT@    ( blk -- addr )     \ -> 32-byte tx_root
BLK-PROOF@      ( blk -- addr len ) \ Consensus proof data
BLK-TX@         ( idx blk -- tx )   \ Tx pointer by index
```

---

## Chain Management

### CHAIN-INIT

```forth
CHAIN-INIT  ( -- )
```

Zero the ring buffer and build a genesis block (height 0, all-zero
prev_hash, empty txs, state root from current state).  Store it in
slot 0 and compute the genesis hash.

### CHAIN-HEIGHT

```forth
CHAIN-HEIGHT  ( -- n )
```

Return the current chain height.  `-1` means empty/uninitialized.

### CHAIN-HEAD

```forth
CHAIN-HEAD  ( -- blk )
```

Return a pointer to the current chain tip header in the ring buffer.

### CHAIN-BLOCK@

```forth
CHAIN-BLOCK@  ( n -- blk | 0 )
```

Retrieve a header by height.  Returns `0` for future, negative, or
evicted blocks (older than `CHAIN-HISTORY` behind the tip).

### CHAIN-APPEND

```forth
CHAIN-APPEND  ( blk -- flag )
```

The **single mutation point** for the chain and global state:
1. Check that `height = chain_height + 1`
2. Run `BLK-VERIFY` against the current head hash
3. Apply transactions permanently via `_ST-APPLY-VERIFIED`, since
   `BLK-VERIFY` has verified their signatures; on the first failure,
   truncate `tx_count` to the valid prefix (A02)
4. Copy the header into the ring buffer
5. Update height and head hash

Returns `TRUE` on success, `FALSE` on failure.

---

## Consensus Integration

`BLK-VERIFY` calls a consensus-proof validator through the callback
variable `_BLK-CON-CHECK-XT`.  The default stub returns `TRUE`
(always passes).  When `consensus.f` is loaded it patches this
variable with the real `CON-CHECK` word.

---

## Debug

### BLK-PRINT

```forth
BLK-PRINT  ( blk -- )
```

Print version, height, tx count, timestamp, and the first 8 bytes
of prev_hash, state_root, and tx_root in hex.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `BLK-INIT` | `( blk -- )` | Zero struct, set version |
| `BLK-SET-PREV` | `( hash blk -- )` | Set prev_hash |
| `BLK-SET-HEIGHT` | `( n blk -- )` | Set height |
| `BLK-SET-TIME` | `( t blk -- )` | Set timestamp |
| `BLK-SET-PROOF` | `( addr len blk -- )` | Set proof data |
| `BLK-ADD-TX` | `( tx blk -- flag )` | Append tx pointer |
| `BLK-FINALIZE` | `( blk -- )` | Compute tx and state roots, state unchanged |
| `BLK-HASH` | `( blk hash -- )` | SHA3-256 of header CBOR |
| `BLK-ENCODE` | `( blk buf max -- len )` | Serialize full block |
| `BLK-ENCODED-SIZE` | `( blk -- n )` | Bytes `BLK-ENCODE` writes for the block |
| `BLK-DECODE` | `( buf len blk -- flag )` | Deserialize full block |
| `BLK-VERIFY` | `( blk prev-hash -- flag )` | Full validation |
| `BLK-PRINT` | `( blk -- )` | Debug print |
| `CHAIN-INIT` | `( -- )` | Build genesis, zero ring |
| `CHAIN-HEIGHT` | `( -- n )` | Current chain height |
| `CHAIN-HEAD` | `( -- blk )` | Chain tip pointer |
| `CHAIN-BLOCK@` | `( n -- blk \| 0 )` | Header by height |
| `CHAIN-APPEND` | `( blk -- flag )` | Validate + apply + store |

---

## Usage Examples

### Build and Finalize a Block

```forth
CREATE my-blk BLK-STRUCT-SIZE ALLOT
my-blk BLK-INIT

\ Link to previous block
CHAIN-HEAD CREATE prev-hash 32 ALLOT
CHAIN-HEAD prev-hash BLK-HASH
prev-hash my-blk BLK-SET-PREV

\ Set metadata
CHAIN-HEIGHT 1+ my-blk BLK-SET-HEIGHT
1709913600      my-blk BLK-SET-TIME

\ Add transactions
tx1 my-blk BLK-ADD-TX DROP
tx2 my-blk BLK-ADD-TX DROP

\ Finalize (computes roots; the state stays as it was)
my-blk BLK-FINALIZE

\ Append: verify, then apply the transactions to the state
my-blk CHAIN-APPEND  ( -- flag )
```

### Append to Chain

```forth
\ Receiver side: decode and validate
CREATE rx-blk BLK-STRUCT-SIZE ALLOT
wire-buf wire-len rx-blk BLK-DECODE DROP

\ Append applies the block permanently
rx-blk CHAIN-APPEND  ( -- flag )
```

---

## Internals

### Dependencies

Requires `sha3.f`, `merkle.f`, `cbor.f`, `tx.f`, `state.f`, `fmt.f`,
and `../concurrency/guard.f`.

### Concurrency Guard

All 13 mutating public words are redefined through `WITH-GUARD` after
loading `guard.f`.  Read-only getters and chain query words
(`CHAIN-HEIGHT`, `CHAIN-HEAD`, `CHAIN-BLOCK@`) are **not** guarded.

### Duplicate Nonce Detection

`BLK-VERIFY` checks for duplicate `(sender, nonce)` pairs using an
O(n²) nested loop, bounded by `n ≤ BLK-MAX-TXS` (256).

### ST-ROOT API

`BLK-FINALIZE`, `BLK-VERIFY`, and `CHAIN-INIT` all call `ST-ROOT`
and `DROP` the flag (Phase 6.6 batch 3 changed `ST-ROOT` from
`( -- addr )` to `( -- addr flag )`).
