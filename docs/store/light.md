# akashic-light — Light Client Protocol for KDOS / Megapad-64

Inclusion proofs of account state for light clients.  A light client
holds only block headers.  It checks an account against the state root
in a trusted header with a proof from the state's sparse Merkle tree
(`smt.f`), so it never needs the rest of the state.

```forth
REQUIRE light.f
```

`PROVIDED akashic-light` — depends on `akashic-state`, `akashic-block`,
`akashic-sha3`.

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
| **Thin wrappers** | `LC-STATE-PROOF` is `ST-PROVE` and `LC-VERIFY-STATE` is `SMT-VERIFY`, under the light client's names |
| **Caller's storage** | A proof is written into the caller's buffer, within the size the caller gives |
| **Guard-wrapped** | `_lc-guard` serializes the light client's words |
| **Header-only** | A light client needs only 248-byte block headers, not full blocks |

---

## Proof Format

The state tree is a compact sparse Merkle tree, a Patricia tree keyed
by the 32-byte account address.  The value it keeps under an address is
the account's leaf, the SHA3-256 hash of its 72-byte entry:
`[32B addr | 8B balance | 8B nonce | 8B staked | 8B unstake_h | 8B last_blk]`,
each number a little-endian cell.  The tree hashes its nodes with
domain tags:

```
leaf node:   SHA3-256( 0x00 || address[32] || leaf[32] )
branch node: SHA3-256( 0x01 || left-hash[32] || right-hash[32] )
```

A proof lists the branches above the account's leaf, root to leaf, one
40-byte entry each:

```
+0    8 bytes    bit position of the branch (a little-endian cell)
+8   32 bytes    hash of the branch's other child, the sibling
```

The bit position names a bit of the address, counted from the most
significant bit of its first byte.  The address's bit there says which
side the path takes: 1 goes right, so the sibling is the left child,
and 0 goes left.  A proof is as long as the leaf is deep, which is
about log₂ of the number of accounts and never more than 256 entries
(10240 bytes).  A lone account's leaf is the root, so its proof holds no
entries.

---

## Proof Generation

### LC-STATE-PROOF

```forth
LC-STATE-PROOF  ( addr proof buf-len -- len flag )
```

Write the inclusion proof for the account at `addr` into `proof`.

| Parameter | Description |
|---|---|
| `addr` | 32-byte account address (SHA3-256 of Ed25519 public key) |
| `proof` | Buffer to receive the proof's entries |
| `buf-len` | The buffer's size in bytes; 10240 bytes hold any proof |
| **Returns** | The number of entries and `TRUE`; `0 FALSE` if the account is missing, the tree cannot be built, or the proof does not fit |

The flag tells a lone account's empty proof, `0 TRUE`, from a missing
account, `0 FALSE`.  The word is `ST-PROVE`: it rebuilds the state tree
when the state has changed since the last rebuild, then proves the
account with `SMT-PROVE`.

### LC-STATE-LEAF

```forth
LC-STATE-LEAF  ( addr leaf -- flag )
```

Find an account and hash its 72-byte entry into a 32-byte leaf buffer.

| Parameter | Description |
|---|---|
| `addr` | 32-byte account address |
| `leaf` | 32-byte buffer to receive `SHA3-256(entry)` |
| **Returns** | `TRUE` (-1) if found; `FALSE` (0) if not |

---

## Proof Verification

### LC-VERIFY-STATE

```forth
LC-VERIFY-STATE  ( key leaf proof len root -- flag )
```

Verify a state proof.  The word is `SMT-VERIFY`: it hashes the leaf
node from `key` and `leaf`, climbs the proof from its last entry to its
first, and compares the result with `root`.

| Parameter | Description |
|---|---|
| `key` | 32-byte account address |
| `leaf` | 32-byte leaf, from `LC-STATE-LEAF` or computed locally |
| `proof` | The proof's entries, from `LC-STATE-PROOF` or a peer |
| `len` | Number of entries |
| `root` | 32-byte expected state root, from a block header |
| **Returns** | `TRUE` (-1) if valid; `FALSE` (0) otherwise |

A proof can come from an untrusted peer.  One longer than 256 entries,
or holding an entry whose bit position is 256 or more, is invalid; the
position is checked before the key's bit is read.

---

## Block Header Access

### LC-STATE-ROOT-AT

```forth
LC-STATE-ROOT-AT  ( height -- addr | 0 )
```

Return a pointer to the 32-byte state root stored in the block header at
`height`.  Returns `0` if the block is not in the ring buffer (evicted or
future).  The ring buffer holds the last `CHAIN-HISTORY` (256) blocks.

### LC-BLOCK-HEADER

```forth
LC-BLOCK-HEADER  ( height -- blk | 0 )
```

Return a pointer to the block header at `height`, or `0` if unavailable.
Alias for `CHAIN-BLOCK@`.

---

## RPC Methods

rpc.f serves the light client protocol over JSON-RPC 2.0;
[rpc.md](../web/rpc.md) gives each method's errors.

### chain_getProof

```json
{ "method": "chain_getProof", "params": ["<addr-hex-64>"] }
```

Response:
```json
{
  "result": {
    "stateRoot": "<hex-64>",
    "address": "<hex-64>",
    "entry": "<hex-144>",
    "leaf": "<hex-64>",
    "balance": 1000,
    "nonce": 0,
    "proof": [{"bit": 4, "sibling": "<hex-64>"}, ...]
  }
}
```

Returns the account's entry, its leaf, the current state root, and the
proof in the format above, its entries in the same order.  Error if the
account is not found.

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
  "params": ["<address-hex-64>", "<leaf-hex-64>", [{"bit": 4, "sibling": "<hex-64>"}], "<root-hex-64>"]
}
```

Response:
```json
{ "result": true }
```

Server-side proof verification with `LC-VERIFY-STATE`.  The address,
leaf, proof and state root from `chain_getProof` verify as they came.

---

## Light Client Verification Flow

A light client checks an account's balance in four steps:

1. **Get proof**: call `chain_getProof` with the account's address.
2. **Get header**: take the state root from a trusted block header,
   synced locally or read with `chain_getBlockProof`.
3. **Check the entry**: hash `entry` with SHA3-256 and compare it with
   `leaf`; the entry's first 32 bytes are the address, and its balance
   and nonce follow as little-endian cells.
4. **Verify**: start from `SHA3-256(0x00 || address || leaf)` and climb
   the proof from its last entry to its first.  At each entry, read the
   address's bit at the entry's position: if it is 1, hash
   `0x01 || sibling || current`, else `0x01 || current || sibling`.
   The result must equal the state root.  On the machine,
   `LC-VERIFY-STATE` performs the climb and the comparison; a client
   can also ask the server with `chain_verifyProof`.

If the header's state root is trusted, for example from a finalized
block signed by validators, the proof establishes the account's entry
without the rest of the state.

---

## Concurrency

All public `LC-` words are serialized via `_lc-guard` (a `GUARD` from
guard.f).  `LC-STATE-PROOF` runs `ST-PROVE`, which holds the state's
guard, `_st-guard`, across the tree's rebuild and the proof, so no state
mutation falls between them.  The tree's own words take `_smt-guard`.
The three guards are distinct, so no deadlock.

---

## Quick Reference

| Word | Stack Effect | Description |
|---|---|---|
| `LC-STATE-PROOF` | `( addr proof buf-len -- len flag )` | Generate an account's state proof |
| `LC-STATE-LEAF` | `( addr leaf -- flag )` | Find account, hash entry to leaf |
| `LC-VERIFY-STATE` | `( key leaf proof len root -- flag )` | Verify state proof |
| `LC-STATE-ROOT-AT` | `( height -- addr \| 0 )` | State root from block header |
| `LC-BLOCK-HEADER` | `( height -- blk \| 0 )` | Block header at height |
