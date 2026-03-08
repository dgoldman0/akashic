# akashic-merkle — Binary Merkle Tree (SHA3-256)

General-purpose binary Merkle tree over 32-byte leaf hashes.
Used by STARKs, content-addressed storage, authenticated data
structures, and any application needing commitment with selective
opening.

```forth
REQUIRE merkle.f
```

`PROVIDED akashic-merkle` — depends on `akashic-sha3` and
`akashic-guard` (from `../concurrency/guard.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Constants](#constants)
- [Tree Creation](#tree-creation)
- [Accessors](#accessors)
- [Building the Tree](#building-the-tree)
- [Opening (Authentication Path)](#opening-authentication-path)
- [Verification](#verification)
- [Usage Example](#usage-example)
- [Concurrency](#concurrency)
- [Quick Reference](#quick-reference)
- [Tree Layout](#tree-layout)

---

## Design Principles

| Principle | Detail |
|---|---|
| **SHA3-256 internal hash** | Internal nodes compute `SHA3-256(0x01 \|\| left \|\| right)` — 65-byte preimage with a domain separator byte to prevent second-preimage attacks. |
| **Caller-hashed leaves** | Leaf data is hashed by the caller *before* calling `MERKLE-LEAF!`. The tree stores 32-byte leaf hashes directly. |
| **Power-of-2 leaves** | Leaf count `n` must be a power of 2. Tree has `2n − 1` nodes. |
| **1-indexed flat array** | Nodes numbered 1..2n−1. Node 1 = root, nodes n..2n−1 = leaves. Standard heap layout: parent = i/2, children = 2i, 2i+1. |
| **Bottom-up build** | `MERKLE-BUILD` iterates from node n−1 down to 1, computing each parent from its two children. |
| **Variable-based state** | All loop state uses `VARIABLE` words instead of return-stack tricks — `>R`/`R@` inside `DO..LOOP` reads the loop index, not the stashed value. |
| **Concurrency-safe** | Mutating words are wrapped with a guard (see [Concurrency](#concurrency)).  Pure read accessors are left unguarded. |

---

## Constants

### MERKLE-HASH-LEN

```forth
MERKLE-HASH-LEN  ( -- 32 )
```

Hash length in bytes (SHA3-256 output size).

---

## Tree Creation

### MERKLE-TREE

```forth
MERKLE-TREE  ( n "name" -- )
```

Create a named Merkle tree for `n` leaves (must be power of 2).

Allocates one cell for the leaf count plus `(2n − 1) × 32` bytes
of node storage.  All nodes are zeroed on creation.

```forth
8 MERKLE-TREE my-tree    \ 8 leaves → 15 nodes → 488 bytes
```

---

## Accessors

### MERKLE-N

```forth
MERKLE-N  ( tree -- n )
```

Returns the number of leaves in the tree.

### MERKLE-ROOT

```forth
MERKLE-ROOT  ( tree -- addr )
```

Returns the address of the 32-byte root hash (node 1).
Only valid after `MERKLE-BUILD`.

### MERKLE-LEAF@

```forth
MERKLE-LEAF@  ( idx tree -- addr )
```

Returns the address of the 32-byte leaf hash at 0-based index `idx`.
Leaf `idx` is stored at node `n + idx`.

### MERKLE-LEAF!

```forth
MERKLE-LEAF!  ( hash idx tree -- )
```

Copy a 32-byte hash from `hash` into the leaf slot at index `idx`.
The caller is responsible for hashing the original data first:

```forth
CREATE buf 32 ALLOT
my-data my-data-len buf SHA3-256-HASH   \ hash your data
buf 0 my-tree MERKLE-LEAF!              \ store in leaf 0
```

---

## Building the Tree

### MERKLE-BUILD

```forth
MERKLE-BUILD  ( tree -- )
```

Compute all internal nodes from leaves, bottom-up.  Iterates from
node `n − 1` down to node 1:

$$\text{node}[i] = \text{SHA3-256}(\texttt{0x01} \| \text{node}[2i] \| \text{node}[2i+1])$$

All leaves must be set before calling `MERKLE-BUILD`.

---

## Opening (Authentication Path)

### MERKLE-OPEN

```forth
MERKLE-OPEN  ( idx tree proof -- depth )
```

Write the authentication path (Merkle proof) for the leaf at
0-based index `idx` into the `proof` buffer.  Returns `depth`
(the number of siblings = $\log_2(n)$).

The proof buffer must be at least `depth × 32` bytes.  Siblings
are written bottom-to-top: `proof[0]` is the sibling of the leaf,
`proof[1]` is the sibling of the leaf's parent, etc.

At each level the sibling node index is computed as `cur XOR 1`
(flip the lowest bit), then the current position moves up via
`cur = cur >> 1`.

```forth
CREATE proof 256 ALLOT    \ enough for depth ≤ 8
0 my-tree proof MERKLE-OPEN   \ → depth on stack
```

---

## Verification

### MERKLE-VERIFY

```forth
MERKLE-VERIFY  ( leaf-hash idx proof depth root -- flag )
```

Verify that `leaf-hash` at position `idx` is consistent with
`root`, given the authentication path in `proof` of length `depth`.

Returns `TRUE` (−1) if the computed root matches, `FALSE` (0)
otherwise.  Uses constant-time `SHA3-256-COMPARE` for the final
comparison.

The verifier walks bottom-to-top, hashing at each level:

- If `idx` is odd: `hash = H(0x01 || proof[i] || hash)`
- If `idx` is even: `hash = H(0x01 || hash || proof[i])`
- Then `idx = idx >> 1`

After `depth` iterations, the result is compared to `root`.

```forth
leaf-hash 0 proof depth my-tree MERKLE-ROOT MERKLE-VERIFY
\ → TRUE or FALSE
```

---

## Usage Example

Complete example: create a 4-leaf tree, build it, open leaf 2,
and verify the proof.

```forth
\ Create tree and leaf hash buffer
4 MERKLE-TREE mt
CREATE lbuf 32 ALLOT
CREATE bbuf 1 ALLOT
CREATE proof 128 ALLOT
VARIABLE depth

\ Hash leaves: leaf i = SHA3-256(byte i)
0 bbuf C!  bbuf 1 lbuf SHA3-256-HASH  lbuf 0 mt MERKLE-LEAF!
1 bbuf C!  bbuf 1 lbuf SHA3-256-HASH  lbuf 1 mt MERKLE-LEAF!
2 bbuf C!  bbuf 1 lbuf SHA3-256-HASH  lbuf 2 mt MERKLE-LEAF!
3 bbuf C!  bbuf 1 lbuf SHA3-256-HASH  lbuf 3 mt MERKLE-LEAF!

\ Build internal nodes
mt MERKLE-BUILD

\ Print root hash
mt MERKLE-ROOT SHA3-256-.  CR

\ Open leaf 2 and verify
2 mt proof MERKLE-OPEN depth !
2 mt MERKLE-LEAF@  2  proof  depth @  mt MERKLE-ROOT  MERKLE-VERIFY
\ → TRUE (-1)
```

---

## Concurrency

`merkle.f` creates a guard (`GUARD _merkle-guard`) and wraps every
word that mutates tree state with `WITH-GUARD`:

**Guarded:** `MERKLE-BUILD`, `MERKLE-OPEN`, `MERKLE-VERIFY`,
`MERKLE-LEAF!`.

**Unguarded (pure reads):** `MERKLE-TREE`, `MERKLE-N`,
`MERKLE-ROOT`, `MERKLE-LEAF@`.

Because `WITH-GUARD` uses `CATCH` internally, the guard is always
released even if the wrapped word throws.

---

## Quick Reference

| Word | Stack | Description |
|---|---|---|
| `MERKLE-HASH-LEN` | `( -- 32 )` | Hash length constant |
| `MERKLE-TREE` | `( n "name" -- )` | Create tree for n leaves |
| `MERKLE-N` | `( tree -- n )` | Number of leaves |
| `MERKLE-ROOT` | `( tree -- addr )` | Pointer to 32-byte root |
| `MERKLE-LEAF@` | `( idx tree -- addr )` | Pointer to leaf hash |
| `MERKLE-LEAF!` | `( hash idx tree -- )` | Store 32-byte leaf hash |
| `MERKLE-BUILD` | `( tree -- )` | Compute internal nodes |
| `MERKLE-OPEN` | `( idx tree proof -- depth )` | Write auth path |
| `MERKLE-VERIFY` | `( leaf idx proof depth root -- flag )` | Verify opening |

---

## Tree Layout

For `n = 4` leaves, the tree has 7 nodes:

```
        node 1 (root)
       /             \
    node 2          node 3
   /      \        /      \
 node 4  node 5  node 6  node 7
 leaf 0  leaf 1  leaf 2  leaf 3
```

Memory layout (after the cell storing `n`):

| Offset | Node | Role |
|---|---|---|
| CELL+0 | 1 | Root = H(node2, node3) |
| CELL+32 | 2 | H(node4, node5) |
| CELL+64 | 3 | H(node6, node7) |
| CELL+96 | 4 | Leaf 0 |
| CELL+128 | 5 | Leaf 1 |
| CELL+160 | 6 | Leaf 2 |
| CELL+192 | 7 | Leaf 3 |

Proof for leaf 2 (node 6, depth = 2):
- `proof[0]` = node 7 (sibling at leaf level)
- `proof[1]` = node 2 (sibling at parent level)
