# akashic-smt — Sparse Merkle Tree (Compact / Patricia)

General-purpose compact sparse Merkle tree keyed by 32-byte keys
with 32-byte value hashes.  Uses Patricia compression: only populated
leaves and their branch points are stored.

```forth
REQUIRE smt.f
```

`PROVIDED akashic-smt` — depends on `akashic-sha3`, `akashic-guard`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Node Layout](#node-layout)
- [Descriptor Layout](#descriptor-layout)
- [Hashing Scheme](#hashing-scheme)
- [Proof Format](#proof-format)
- [Initialization / Destruction](#initialization--destruction)
- [Insertion](#insertion)
- [Lookup](#lookup)
- [Deletion](#deletion)
- [Root Hash](#root-hash)
- [Prove / Verify](#prove--verify)
- [Query Words](#query-words)
- [Concurrency](#concurrency)
- [Constants](#constants)
- [Usage Example](#usage-example)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Realisation |
|---|---|
| **Patricia compression** | Only populated leaves and their branch points are stored; for *n* leaves there are exactly *n − 1* branch nodes |
| **32-byte keys & values** | Uniform key/value size simplifies hashing and proof generation |
| **XMEM-backed pool** | Node pool allocated in extended memory; descriptor lives in base RAM |
| **Free list** | Singly-linked free chain enables O(1) allocate / free |
| **Deterministic root** | Same key/value set always produces the same root hash, independent of insertion order |
| **Inclusion proofs** | Variable-length path proofs for Merkle inclusion verification |
| **Concurrency-safe** | Public API wrapped with `WITH-GUARD` |
| **Not reentrant** | Module-level VARIABLEs for scratch state |

---

## Node Layout

Each node is 96 bytes (12 cells), uniform for branch and leaf:

```
Offset  Size    Field    Branch meaning         Leaf meaning
------  ------  ------   --------------------   ---------------------
  0       8     type     1 = branch             2 = leaf (0 = free)
  8       8     x0       bit-position           0
 16       8     x1       left-child index       0
 24       8     x2       right-child index      free-next (in free list)
 32      32     fa       cached branch hash     key (32 bytes)
 64      32     fb       (unused)               value (32 bytes)
------
 96 total
```

---

## Descriptor Layout

The tree descriptor is a 64-byte record in base RAM:

```
Offset  Size    Field      Description
------  ------  ---------  -----------
  0       8     pool       XMEM pool base address
  8       8     max        max nodes (8191)
 16       8     root       root node index (0 = empty)
 24       8     lcnt       leaf count
 32       8     ncnt       total allocated node count
 40       8     free       free list head index
 48       8     maxl       max leaves (4096)
 56       8     (reserved)
------
 64 total
```

---

## Hashing Scheme

Domain-separated SHA3-256 hashes (same tags as `merkle.f`):

| Node type | Hash input |
|---|---|
| **Leaf** | `SHA3-256( 0x00 ‖ key[32] ‖ value[32] )` — 65 bytes |
| **Branch** | `SHA3-256( 0x01 ‖ left-hash[32] ‖ right-hash[32] )` — 65 bytes |

The `0x00` / `0x01` domain tag prevents second-preimage attacks
across node types.

---

## Proof Format

A proof is a variable-length array of 40-byte entries, ordered
root-to-leaf:

```
Entry layout (40 bytes):
  +0    8 bytes    bit-position of the branch
  +8   32 bytes    sibling hash at that branch
```

The proof length (number of entries) is returned by `SMT-PROVE` and
passed to `SMT-VERIFY`. A length of 0 means the key was not found.

---

## Initialization / Destruction

### SMT-INIT

```forth
SMT-INIT  ( tree -- flag )
```

Allocate an XMEM pool for up to 8191 nodes. Build the internal free
list. Returns true (−1) on success, false (0) if XMEM allocation
fails. The tree descriptor must be a 64-byte buffer in base RAM.

### SMT-DESTROY

```forth
SMT-DESTROY  ( tree -- )
```

Free the XMEM pool and zero the descriptor. After destruction the
descriptor may be re-initialized with `SMT-INIT`.

---

## Insertion

### SMT-INSERT

```forth
SMT-INSERT  ( key val tree -- flag )
```

Insert or update a leaf. `key` and `val` are addresses of 32-byte
buffers. Returns true on success, false if the leaf capacity or
node pool is exhausted. Both leaf count and node count are checked
before allocation (B11 hardening).

**Algorithm:**

1. Empty tree → create leaf, set as root.
2. Walk from root following key bits at each branch's bit-position.
3. At a leaf:
   - Keys match → update value, rehash path upward.
   - Keys differ → compute first differing bit, find correct
     insertion point, create new branch + leaf, wire children, rehash.

Mid-path insertion is handled correctly: the new branch is spliced
in at the first existing branch whose bit-position exceeds the
diff-bit.

---

## Lookup

### SMT-LOOKUP

```forth
SMT-LOOKUP  ( key tree -- val-addr flag )
```

Search for `key`. If found, returns the address of the 32-byte value
inside the node and true. If not found, returns 0 and false.

**Note:** The returned `val-addr` points into the XMEM node pool
and is only valid until the next mutation.

---

## Deletion

### SMT-DELETE

```forth
SMT-DELETE  ( key tree -- flag )
```

Remove a leaf. Returns true if the key was found and deleted, false
otherwise. When the last leaf is deleted the tree becomes empty
(root index = 0). When a branch becomes redundant (one child
deleted), the branch is removed and its remaining child is promoted
to the parent position.

---

## Root Hash

### SMT-ROOT

```forth
SMT-ROOT  ( tree -- addr )
```

Return the address of the 32-byte root hash. An empty tree returns
a pointer to an all-zero buffer.

---

## Prove / Verify

### SMT-PROVE

```forth
SMT-PROVE  ( key buf buf-len tree -- proof-len flag )
```

Generate an inclusion proof for `key`. `buf` is the proof buffer;
`buf-len` is its capacity in bytes. Returns the number of proof
entries and a success flag. Returns `0 0` if the key is not in the
tree, or if `buf-len` is too small to hold the proof
(needs `depth × 40` bytes; 10240 bytes is safe for up to 256 levels).

### SMT-VERIFY

```forth
SMT-VERIFY  ( key val proof len root -- flag )
```

Verify an inclusion proof. `root` is the address of the expected
32-byte root hash. Returns true if the reconstructed root matches.
Rejects proofs with `len > 256` (max depth for 256-bit keys).

**Stack setup after SMT-PROVE:**

```forth
\ After: key buf buf-len tree SMT-PROVE  →  ( proof-len flag )
DROP  \ drop flag (or check it)
\ proof-len is in hand; push VERIFY args:
key val buf proof-len tree SMT-ROOT SMT-VERIFY
```

---

## Query Words

```forth
SMT-COUNT  ( tree -- n )      \ Number of leaves
SMT-EMPTY? ( tree -- flag )   \ True if no leaves
SMT-MAX    ( tree -- n )      \ Maximum leaf capacity (4096)
```

---

## Concurrency

All public words are wrapped with a module-level `GUARD` via
`WITH-GUARD`. This serializes all access to the tree, making it
safe for multi-task environments. The guard is automatically acquired
on entry and released on exit (including on exception via `CATCH`).

The module is **not reentrant** — it uses shared scratch buffers
(`_SMT-HSC`, `_SMT-TMP`, `_SMT-TM2`) and module-level `VARIABLE`s
for recursive state.

---

## Constants

| Name | Value | Description |
|---|---|---|
| `SMT-MAX-LEAVES` | 4096 | Maximum number of leaves |
| `_SMT-MAX-NODES` | 8191 | Maximum nodes (2n − 1) |
| `_SMT-NODE-SZ` | 96 | Bytes per node |
| `_SMT-FREE` | 0 | Node type: free |
| `_SMT-BRANCH` | 1 | Node type: branch |
| `_SMT-LEAF` | 2 | Node type: leaf |

---

## Usage Example

```forth
CREATE my-tree 64 ALLOT
CREATE my-key 32 ALLOT
CREATE my-val 32 ALLOT
CREATE my-proof 10240 ALLOT

\ Initialize
my-tree SMT-INIT DROP

\ Fill key/value
my-key 32 42 FILL
my-val 32 99 FILL

\ Insert
my-key my-val my-tree SMT-INSERT DROP

\ Lookup
my-key my-tree SMT-LOOKUP
IF  ." Found, value at: " . CR
ELSE  ." Not found" CR
THEN

\ Root hash
my-tree SMT-ROOT   \ -- addr of 32-byte hash

\ Prove + verify round-trip
my-key my-proof 10240 my-tree SMT-PROVE  \ -- proof-len flag
DROP  \ drop flag
my-key my-val my-proof ROT my-tree SMT-ROOT SMT-VERIFY
IF  ." Valid proof" CR  THEN

\ Delete
my-key my-tree SMT-DELETE DROP

\ Cleanup
my-tree SMT-DESTROY
```

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `SMT-INIT` | `( tree -- flag )` | Allocate pool, build free list |
| `SMT-DESTROY` | `( tree -- )` | Free pool, zero descriptor |
| `SMT-INSERT` | `( key val tree -- flag )` | Insert or update leaf |
| `SMT-LOOKUP` | `( key tree -- val-a flag )` | Search for key |
| `SMT-DELETE` | `( key tree -- flag )` | Remove leaf |
| `SMT-ROOT` | `( tree -- addr )` | 32-byte root hash address |
| `SMT-PROVE` | `( key buf buf-len tree -- proof-len flag )` | Generate inclusion proof |
| `SMT-VERIFY` | `( key val proof len root -- flag )` | Verify inclusion proof |
| `SMT-COUNT` | `( tree -- n )` | Leaf count |
| `SMT-EMPTY?` | `( tree -- flag )` | True if empty |
| `SMT-MAX` | `( tree -- n )` | Max leaves (4096) |
