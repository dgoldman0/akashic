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
| **Non-destructive verify** | `BLK-VERIFY` uses `ST-SNAPSHOT` / `ST-RESTORE` to tentatively apply, check, then rollback |
| **Delegated consensus** | Callback variable `_BLK-CON-CHECK-XT` defaults to always-true; `consensus.f` patches it |
| **DAG-CBOR encoding** | Both `BLK-HASH` and `BLK-ENCODE` use DAG-CBOR canonical key ordering |
| **Concurrency-safe** | All mutating public words wrapped with `WITH-GUARD` |

---

## Constants

| Constant | Value | Description |
|---|---|---|
| `BLK-MAX-TXS` | 256 | Maximum transactions per block |
| `BLK-PROOF-MAX` | 128 | Maximum consensus proof bytes |
| `CHAIN-HISTORY` | 64 | Recent block headers kept in ring buffer |
| `BLK-HDR-SIZE` | 248 | Block header size (8-byte aligned) |
| `BLK-STRUCT-SIZE` | 2304 | Total block struct size (header + count + pointer array) |

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
1. Compute the Merkle root of all transaction hashes → `tx_root`
2. Apply every transaction to global state via `ST-APPLY-TX`
3. Compute the state Merkle root via `ST-ROOT` → `state_root`

**Mutates global state.**  Only the block producer should call this.

---

## Hashing

### BLK-HASH

```forth
BLK-HASH  ( blk hash -- )
```

CBOR-encode the 7 header fields in DAG-CBOR canonical key order, then
SHA3-256 the result into the 32-byte `hash` buffer.

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
string via `TX-ENCODE`.  Returns encoded length.

### BLK-DECODE

```forth
BLK-DECODE  ( buf len blk -- flag )
```

Deserialize a block from CBOR (**header-only**).  Decodes the 7 header
fields from the map; skips the tx array (caller must handle tx buffer
allocation separately).  Returns `TRUE` on success, `FALSE` on parse
error.

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
5. Transaction Merkle root matches `tx_root`
6. State root matches — uses `ST-SNAPSHOT` / `ST-RESTORE` to
   tentatively apply transactions, compare `ST-ROOT`, then roll back
7. Consensus proof passes `_BLK-CON-CHECK-XT` callback

Returns `TRUE` if valid, `FALSE` otherwise.

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
3. Apply all transactions permanently via `ST-APPLY-TX`
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
| `BLK-FINALIZE` | `( blk -- )` | Compute roots, apply state |
| `BLK-HASH` | `( blk hash -- )` | SHA3-256 of header CBOR |
| `BLK-ENCODE` | `( blk buf max -- len )` | Serialize full block |
| `BLK-DECODE` | `( buf len blk -- flag )` | Deserialize header |
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

\ Finalize (computes roots, applies state)
my-blk BLK-FINALIZE
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
