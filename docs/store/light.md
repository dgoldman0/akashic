# akashic-light — Light Client Protocol for KDOS / Megapad-64

Merkle proof generation and verification for light clients.  A light
client holds only block headers and verifies account state against the
state root using authentication paths from the 256-leaf SHA3-256 Merkle
tree.

```forth
REQUIRE light.f
```

`PROVIDED akashic-light` — depends on `akashic-state`, `akashic-block`,
`akashic-merkle`, `akashic-sha3`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Proof Format](#proof-format)
- [Proof Generation](#proof-generation)
- [Proof Verification](#proof-verification)
- [Block Header Access](#block-header-access)
- [RPC Methods](#rpc-methods)
- [Light Client Verification Flow](#light-client-verification-flow)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Thin wrappers** | Leverages existing `MERKLE-OPEN` / `MERKLE-VERIFY` from merkle.f |
| **Zero-copy** | Proof buffers filled in-place; root pointers into ring buffer |
| **Guard-wrapped** | `_lc-guard` serializes proof generation to prevent state/tree races |
| **Header-only** | Light client needs only 248-byte block headers, not full blocks |
| **Drop-in SMT** | When Phase 3b (Sparse Merkle Tree) lands, internal tree changes but the LC- API stays the same |

---

## Proof Format

The state tree is a 256-leaf binary Merkle tree (SHA3-256).
- **Depth**: 8 (= log₂(256))
- **Proof size**: 256 bytes (8 × 32-byte sibling hashes)
- **Layout**: Bottom-to-top — proof[0] is the sibling at the leaf level,
  proof[7] is the sibling one level below the root.

Each leaf is `SHA3-256(account_entry)` where account_entry is the 72-byte
record: `[32B addr | 8B balance | 8B nonce | 8B staked | 8B unstake_h | 8B last_blk]`.

Unused leaf slots contain a zero hash (consistent empty commitment).

---

## Proof Generation

### LC-STATE-PROOF

```forth
LC-STATE-PROOF  ( addr proof -- depth | 0 )
```

Generate a Merkle authentication path for the account at `addr`.

| Parameter | Description |
|---|---|
| `addr` | 32-byte account address (SHA3-256 of Ed25519 public key) |
| `proof` | Buffer ≥ 256 bytes to receive the authentication path |
| **Returns** | `depth` (8) on success; `0` if account not found |

Internally:
1. Calls `_ST-REBUILD-TREE` to rebuild the Merkle tree from current state
2. Finds the account via `_ST-BSEARCH` (O(log n) binary search)
3. Calls `MERKLE-OPEN` on `_ST-TREE` at the found leaf index

### LC-STATE-LEAF

```forth
LC-STATE-LEAF  ( addr leaf -- idx | -1 )
```

Find an account and hash its 72-byte entry into a 32-byte leaf buffer.

| Parameter | Description |
|---|---|
| `addr` | 32-byte account address |
| `leaf` | 32-byte buffer to receive `SHA3-256(entry)` |
| **Returns** | Sorted index in state table; `-1` if not found |

---

## Proof Verification

### LC-VERIFY-STATE

```forth
LC-VERIFY-STATE  ( leaf idx proof depth root -- flag )
```

Verify a state Merkle proof.  Thin wrapper around `MERKLE-VERIFY`.

| Parameter | Description |
|---|---|
| `leaf` | 32-byte leaf hash (from `LC-STATE-LEAF` or computed locally) |
| `idx` | Leaf index in the tree (0–255) |
| `proof` | Authentication path (depth × 32 bytes) |
| `depth` | Tree depth (8 for the 256-leaf state tree) |
| `root` | 32-byte expected state root (from block header) |
| **Returns** | `TRUE` (-1) if valid; `FALSE` (0) otherwise |

### LC-DEPTH

```forth
LC-DEPTH  ( -- 8 )
```

Constant: proof depth for the 256-leaf state tree.

---

## Block Header Access

### LC-STATE-ROOT-AT

```forth
LC-STATE-ROOT-AT  ( height -- addr | 0 )
```

Return a pointer to the 32-byte state root stored in the block header at
`height`.  Returns `0` if the block is not in the ring buffer (evicted or
future).  The ring buffer holds the last 64 blocks.

### LC-BLOCK-HEADER

```forth
LC-BLOCK-HEADER  ( height -- blk | 0 )
```

Return a pointer to the block header at `height`, or `0` if unavailable.
Alias for `CHAIN-BLOCK@`.

---

## RPC Methods

Four new JSON-RPC 2.0 methods in rpc.f:

### chain_getProof

```json
{ "method": "chain_getProof", "params": ["<addr-hex-64>"] }
```

Response:
```json
{
  "result": {
    "stateRoot": "<hex-64>",
    "index": 0,
    "depth": 8,
    "balance": 1000,
    "nonce": 0,
    "proof": ["<hex-64>", "<hex-64>", ... ]
  }
}
```

Returns the Merkle proof, account data, and current state root for the
given account address.  Error if account not found.

### chain_getBlockProof

```json
{ "method": "chain_getBlockProof", "params": [0] }
```

Response:
```json
{
  "result": {
    "height": 0,
    "prevHash": "<hex-64>",
    "stateRoot": "<hex-64>",
    "txRoot": "<hex-64>",
    "timestamp": 0
  }
}
```

Returns key block header fields at the given height. Error if block not
in ring buffer.

### chain_getStateRoot

```json
{ "method": "chain_getStateRoot", "params": [0] }
```

Response:
```json
{ "result": "<hex-64>" }
```

Returns the state root at the given height. If params is empty (`[]`),
returns the current state root.

### chain_verifyProof

```json
{
  "method": "chain_verifyProof",
  "params": ["<leaf-hex-64>", 0, "<proof-hex>", 8, "<root-hex-64>"]
}
```

Response:
```json
{ "result": true }
```

Server-side proof verification.  The `proof-hex` is the concatenated
sibling hashes (depth × 64 hex chars = 512 hex chars for depth 8).

---

## Light Client Verification Flow

A light client verifies an account balance in 4 steps:

1. **Get proof**: Call `chain_getProof` with the account address.
2. **Get header**: Call `chain_getBlockProof` at the desired height (or
   use a locally synced header).
3. **Compute leaf**: Hash the 72-byte account entry locally:
   `SHA3-256([addr‖balance‖nonce‖staked‖unstake_h‖last_blk])`.
4. **Verify**: Call `chain_verifyProof` (or verify locally):
   `MERKLE-VERIFY(leaf, index, proof, 8, stateRoot)` → `TRUE`.

If the state root in the block header is trusted (e.g., from a finalized
block signed by validators), the proof proves the account state without
downloading the full state.

---

## Concurrency

All public `LC-` words are serialized via `_lc-guard` (a `GUARD` from
guard.f).  The guard ensures that the rebuild-tree + binary-search +
merkle-open sequence is atomic — no interleaving with state mutations.

The underlying calls to `MERKLE-OPEN`, `MERKLE-VERIFY`, `MERKLE-BUILD`,
and `MERKLE-LEAF!` use `_merkle-guard`.  State access uses `_st-guard`.
All three guards are distinct, so no deadlock.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `LC-STATE-PROOF` | `( addr proof -- depth \| 0 )` | Generate state Merkle proof |
| `LC-STATE-LEAF` | `( addr leaf -- idx \| -1 )` | Find account, hash entry to leaf |
| `LC-VERIFY-STATE` | `( leaf idx proof depth root -- flag )` | Verify state proof |
| `LC-STATE-ROOT-AT` | `( height -- addr \| 0 )` | State root from block header |
| `LC-BLOCK-HEADER` | `( height -- blk \| 0 )` | Block header at height |
| `LC-DEPTH` | `( -- 8 )` | Proof depth constant |
