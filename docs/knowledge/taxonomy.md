# akashic-taxonomy — Arena-Backed Hierarchical Taxonomy for KDOS / Megapad-64

A hierarchical classification engine with broader/narrower term
relationships, synonym rings, faceted categories, and item
classification.  Each taxonomy lives in a single KDOS arena, enabling
O(1) bulk teardown via `ARENA-DESTROY`.

```forth
REQUIRE taxonomy.f
```

`PROVIDED akashic-taxonomy` — safe to include multiple times.
Automatically loads `akashic-string` (`../utils/string.f`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Memory Architecture](#memory-architecture)
- [Taxonomy Lifecycle](#taxonomy-lifecycle)
- [Concept CRUD](#concept-crud)
- [Tree Navigation](#tree-navigation)
- [Reparenting & Rename](#reparenting--rename)
- [Synonym Rings](#synonym-rings)
- [Faceted Classification](#faceted-classification)
- [Item Classification](#item-classification)
- [Search](#search)
- [Iteration & Traversal](#iteration--traversal)
- [Diagnostics](#diagnostics)
- [Error Handling](#error-handling)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Arena-backed** | All memory (concepts, links, strings, hash table) is allotted from a single KDOS arena.  `ARENA-DESTROY` frees everything at once. |
| **Pool allocation** | Concepts (80 bytes) and item-links (24 bytes) are managed by free-lists for O(1) alloc/free. |
| **String pool** | Labels are stored in a bump-allocated string region inside the arena with copy-on-write semantics. |
| **No hidden heap use** | All output goes through a static result buffer (`_TAX-RBUF`, 256 entries max).  No dynamic allocation outside the arena. |
| **Multiple taxonomies** | Switch between taxonomies with `TAX-USE` / `TAX-TX`. |
| **Synonym rings** | Circular linked lists tie together concepts that are equivalent (e.g. "Cat" ↔ "Feline"). |
| **Facet bits** | Each concept carries a 64-bit bitmask for faceted filtering. |
| **Cycle detection** | `TAX-MOVE` detects ancestor cycles before reparenting. |

---

## Dependencies

```
knowledge/taxonomy.f
└── ../utils/string.f  (akashic-string)
```

**Runtime requirement:** The KDOS arena allocator must be available
(`ARENA-NEW`, `ARENA-ALLOT`).  Use `A-XMEM` (extended memory) for
non-trivial taxonomies.

---

## Memory Architecture

A taxonomy is created with `TAX-CREATE` which allots five regions
from the arena:

```
┌──────────────────────────────────────┐
│  Taxonomy Descriptor (128 bytes)     │
├──────────────────────────────────────┤
│  Concept Pool (80 × max-concepts)    │  free-list managed
├──────────────────────────────────────┤
│  Link Pool (24 × max-links)          │  free-list managed
├──────────────────────────────────────┤
│  Hash Table (8 × 256 slots)          │  item → link lookup
├──────────────────────────────────────┤
│  String Region (remaining)           │  bump-allocated labels
└──────────────────────────────────────┘
```

### Memory Budget

| Component | Formula | Example (256 concepts, 512 links) |
|---|---|---|
| Descriptor | 128 B | 128 B |
| Concept pool | 80 × 256 | 20,480 B |
| Link pool | 24 × 512 | 12,288 B |
| Hash table | 8 × 256 | 2,048 B |
| String region | remainder | ~96 KiB (in 131,072 arena) |

### Concept Node Layout (80 bytes = 10 cells)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `TC.ID` | Auto-incrementing concept ID |
| +8 | `TC.PARENT` | Broader concept (0 = top-level) |
| +16 | `TC.FCHILD` | First narrower concept (0 = leaf) |
| +24 | `TC.LCHILD` | Last narrower concept |
| +32 | `TC.NEXT-SIB` | Next sibling at same parent |
| +40 | `TC.PREV-SIB` | Previous sibling at same parent |
| +48 | `TC.LABEL-A` | Label string address |
| +56 | `TC.LABEL-L` | Label string length |
| +64 | `TC.FACETS` | Up to 64 facet bit-flags |
| +72 | `TC.SYN-NEXT` | Next concept in synonym ring (0 = isolated) |

### Item-Concept Link Layout (24 bytes = 3 cells)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `TL.ITEM` | Application-supplied item identifier |
| +8 | `TL.CONCEPT` | Concept this item is classified under |
| +16 | `TL.NEXT` | Next link in hash chain |

### Taxonomy Descriptor Layout (128 bytes = 16 cells)

| Offset | Field | Purpose |
|---|---|---|
| +0 | `TD.ARENA` | KDOS arena handle |
| +8 | `TD.CON-BASE` | Concept pool start |
| +16 | `TD.CON-MAX` | Max concept count |
| +24 | `TD.CON-FREE` | Concept free-list head |
| +32 | `TD.CON-USED` | Allocated concept count |
| +40 | `TD.LINK-BASE` | Link pool start |
| +48 | `TD.LINK-MAX` | Max link count |
| +56 | `TD.LINK-FREE` | Link free-list head |
| +64 | `TD.LINK-USED` | Allocated link count |
| +72 | `TD.STR-BASE` | String pool start |
| +80 | `TD.STR-PTR` | String pool bump pointer |
| +88 | `TD.STR-END` | String pool end |
| +96 | `TD.NEXT-ID` | Next concept ID to assign |
| +104 | `TD.ROOT-LIST` | First top-level concept |
| +112 | `TD.ROOT-LAST` | Last top-level concept |
| +120 | `TD.ITEM-HASH` | Hash table base for item lookup |

---

## Taxonomy Lifecycle

| Word | Stack | Description |
|---|---|---|
| `TAX-CREATE` | `( arena -- tx )` | Create a taxonomy in the given arena.  Allots descriptor, pools, hash table, and string region.  Builds free-lists.  Calls `TAX-USE`. |
| `TAX-DESTROY` | `( tx -- )` | Destroy the taxonomy.  Currently a no-op — use `ARENA-DESTROY` on the arena for actual deallocation. |
| `TAX-USE` | `( tx -- )` | Set `tx` as the current taxonomy for all subsequent operations. |
| `TAX-TX` | `( -- tx )` | Return the current taxonomy handle. |

### Example

```forth
131072 A-XMEM ARENA-NEW ABORT" arena fail"
TAX-CREATE CONSTANT my-tax
my-tax TAX-USE

\ ... build taxonomy ...

\ Teardown (frees arena + all taxonomy memory):
my-tax TD.ARENA @ ARENA-DESTROY
```

---

## Concept CRUD

| Word | Stack | Description |
|---|---|---|
| `TAX-ADD` | `( label-a label-l -- concept )` | Add a top-level concept with the given label string.  Returns the concept pointer.  0 on error (pool full). |
| `TAX-ADD-UNDER` | `( label-a label-l parent -- concept )` | Add a child concept under `parent`.  Returns the concept pointer. |
| `TAX-REMOVE` | `( concept -- )` | Remove a concept and its entire subtree.  Cleans up synonym ring and item links.  Passing 0 is a safe no-op. |

### Adding Concepts

```forth
S" Animals" TAX-ADD CONSTANT animals
S" Cats" animals TAX-ADD-UNDER CONSTANT cats
S" Dogs" animals TAX-ADD-UNDER CONSTANT dogs
S" Plants" TAX-ADD CONSTANT plants
```

After this: `animals` has two children (`cats`, `dogs`), and there
are two top-level roots (`animals`, `plants`).  Concept count = 4.

### Removing Concepts

```forth
animals TAX-REMOVE   \ removes animals, cats, and dogs (entire subtree)
TAX-COUNT .          \ → 1  (only plants remains)
```

---

## Tree Navigation

| Word | Stack | Description |
|---|---|---|
| `TAX-ID` | `( concept -- id )` | Concept's auto-incrementing ID. |
| `TAX-LABEL` | `( concept -- addr len )` | Concept's label string. |
| `TAX-PARENT` | `( concept -- parent\|0 )` | Broader concept (0 = top-level). |
| `TAX-DEPTH` | `( concept -- n )` | Depth from root (root = 0, child = 1, etc.). |
| `TAX-CHILDREN` | `( concept -- addr n )` | Immediate children (result buffer). |
| `TAX-ROOTS` | `( -- addr n )` | All top-level concepts (result buffer). |
| `TAX-ANCESTORS` | `( concept -- addr n )` | Walk up to root, collecting all ancestors. |
| `TAX-DESCENDANTS` | `( concept -- addr n )` | DFS of entire subtree (excluding self). |
| `TAX-COUNT` | `( -- n )` | Total number of allocated concepts. |

### Result Buffers

`TAX-CHILDREN`, `TAX-ROOTS`, `TAX-ANCESTORS`, `TAX-DESCENDANTS`,
and other query words return `( addr n )` into a shared static
buffer.  **Copy the data before calling another query** — the buffer
is overwritten on the next query.

```forth
animals TAX-CHILDREN    \ ( addr n )
DUP . CR                \ print count
0 DO                    \ iterate
    DUP I 8 * + @       \ get i-th concept pointer
    TAX-LABEL TYPE CR
LOOP DROP
```

---

## Reparenting & Rename

| Word | Stack | Description |
|---|---|---|
| `TAX-MOVE` | `( concept new-parent -- )` | Reparent `concept` under `new-parent`.  Pass 0 for `new-parent` to promote to top-level.  Fails with `TAX-E-CYCLE` if `new-parent` is a descendant of `concept`. |
| `TAX-RENAME` | `( label-a label-l concept -- )` | Change the label of a concept. |

```forth
dogs plants TAX-MOVE     \ move dogs under plants
0 cats TAX-MOVE          \ promote cats to top-level
S" Felines" cats TAX-RENAME
```

---

## Synonym Rings

Synonyms are implemented as circular linked lists through the
`TC.SYN-NEXT` field.  Every concept is initially in a ring of size 1
(pointing to itself).

| Word | Stack | Description |
|---|---|---|
| `TAX-ADD-SYNONYM` | `( c1 c2 -- )` | Link `c1` and `c2` as synonyms by merging their rings. |
| `TAX-REMOVE-SYNONYM` | `( concept -- )` | Remove `concept` from its synonym ring (reverts to isolated). |
| `TAX-SYNONYMS` | `( concept -- addr n )` | All members of the synonym ring (result buffer). |
| `TAX-FIND-SYNONYM` | `( label-a label-l -- concept\|0 )` | Find any concept whose label or synonym label matches (case-insensitive). |

```forth
S" Cat" TAX-ADD CONSTANT cat-c
S" Feline" TAX-ADD CONSTANT feline-c
cat-c feline-c TAX-ADD-SYNONYM
cat-c TAX-SYNONYMS NIP .    \ → 2
S" feline" TAX-FIND-SYNONYM  0<> .  \ → -1
```

---

## Faceted Classification

Each concept carries a 64-bit bitmask for faceted filtering.

| Word | Stack | Description |
|---|---|---|
| `TAX-SET-FACET` | `( bit concept -- )` | Set facet bit (0–63). |
| `TAX-CLEAR-FACET` | `( bit concept -- )` | Clear facet bit. |
| `TAX-HAS-FACET?` | `( bit concept -- flag )` | Test whether facet bit is set. |
| `TAX-FACETS@` | `( concept -- bits )` | Raw 64-bit facet bitmask. |
| `TAX-FILTER-FACET` | `( mask -- addr n )` | All concepts whose facet bits include all bits in `mask`. |

```forth
0 animals TAX-SET-FACET       \ bit 0 = "living"
1 animals TAX-SET-FACET       \ bit 1 = "multicellular"
0 plants TAX-SET-FACET        \ bit 0 = "living"

\ Filter: which concepts have bit 0 set?
1 TAX-FILTER-FACET NIP .      \ → 2  (animals + plants)

\ Filter: bits 0 AND 1?
3 TAX-FILTER-FACET NIP .      \ → 1  (only animals)
```

---

## Item Classification

Items are arbitrary 64-bit identifiers (e.g. record handles, file
IDs) that can be classified under one or more concepts.

| Word | Stack | Description |
|---|---|---|
| `TAX-CLASSIFY` | `( item-id concept -- )` | Classify an item under a concept.  Duplicate classification is a no-op. |
| `TAX-UNCLASSIFY` | `( item-id concept -- )` | Remove a classification. |
| `TAX-ITEMS` | `( concept -- addr n )` | Items classified directly under this concept. |
| `TAX-ITEMS-DEEP` | `( concept -- addr n )` | Items under this concept or any descendant (recursive DFS). |
| `TAX-CATEGORIES` | `( item-id -- addr n )` | All concepts an item is classified under. |

```forth
42 animals TAX-CLASSIFY            \ item 42 → Animals
42 cats TAX-CLASSIFY               \ item 42 → Cats also
animals TAX-ITEMS NIP .            \ → 1
animals TAX-ITEMS-DEEP NIP .       \ → 2  (item on animals + item on cats)
42 TAX-CATEGORIES NIP .            \ → 2  (animals + cats)
42 animals TAX-UNCLASSIFY
animals TAX-ITEMS NIP .            \ → 0
```

---

## Search

| Word | Stack | Description |
|---|---|---|
| `TAX-FIND` | `( label-a label-l -- concept\|0 )` | Find concept by exact label (case-insensitive).  Returns 0 if not found. |
| `TAX-FIND-PREFIX` | `( prefix-a prefix-l -- addr n )` | All concepts whose label starts with the given prefix (case-insensitive). |
| `TAX-FIND-SYNONYM` | `( label-a label-l -- concept\|0 )` | Find concept by label or any synonym's label. |

```forth
S" Animals" TAX-FIND  TAX-LABEL TYPE CR   \ → Animals
S" Ani" TAX-FIND-PREFIX NIP .              \ → 1
S" feline" TAX-FIND-SYNONYM               \ finds via synonym ring
```

---

## Iteration & Traversal

| Word | Stack | Description |
|---|---|---|
| `TAX-EACH-CHILD` | `( xt concept -- )` | Call `xt ( concept -- )` for each immediate child. |
| `TAX-EACH-ROOT` | `( xt -- )` | Call `xt ( concept -- )` for each top-level concept. |
| `TAX-DFS` | `( xt concept -- )` | Depth-first traversal of subtree (including root).  `xt ( concept -- )` called for each node. |
| `TAX-DFS-ALL` | `( xt -- )` | Depth-first traversal of the entire taxonomy. |

### Callback Signature

All iteration callbacks have the signature `( concept -- )`.  The
callback receives one concept pointer on the data stack and must
consume it (or DROP it).

```forth
: show-label  TAX-LABEL TYPE 32 EMIT ;

['] show-label animals TAX-DFS    \ prints: Animals Cats Dogs
['] show-label TAX-EACH-ROOT      \ prints: Animals Plants
['] show-label TAX-DFS-ALL        \ prints: Animals Cats Dogs Plants
```

### Counter Pattern

```forth
VARIABLE count
: inc-count  DROP 1 count +! ;

0 count !
['] inc-count animals TAX-DFS
count @ .    \ → 3  (Animals + Cats + Dogs)
```

---

## Diagnostics

| Word | Stack | Description |
|---|---|---|
| `TAX-STATS` | `( -- link-count concept-count )` | Number of allocated item links and concepts. |
| `TAX-OK?` | `( -- flag )` | True if no error is pending. |
| `TAX-ERR` | `( -- addr )` | Address of the error variable (fetch with `@`). |

---

## Error Handling

Operations that can fail set `TAX-ERR` and return 0 (or skip the
operation).  Check with `TAX-OK?` after any fallible call.

| Constant | Value | Meaning |
|---|---|---|
| `TAX-E-OK` | 0 | No error |
| `TAX-E-NOT-FOUND` | 1 | Concept not found |
| `TAX-E-FULL` | 2 | Pool is full |
| `TAX-E-CYCLE` | 3 | Move would create a cycle |
| `TAX-E-DUP` | 4 | Duplicate entry |
| `TAX-E-POOL-FULL` | 5 | Pool exhausted |
| `TAX-E-BAD-ARG` | 6 | Invalid argument |

```forth
animals cats TAX-MOVE        \ try to move parent under child
TAX-OK? .                    \ → 0  (failed)
TAX-ERR @ .                  \ → 3  (TAX-E-CYCLE)
```

---

## Quick Reference

| Word | Stack Effect | Category |
|---|---|---|
| `TAX-CREATE` | `( arena -- tx )` | Lifecycle |
| `TAX-DESTROY` | `( tx -- )` | Lifecycle |
| `TAX-USE` | `( tx -- )` | Lifecycle |
| `TAX-TX` | `( -- tx )` | Lifecycle |
| `TAX-ADD` | `( a u -- concept )` | CRUD |
| `TAX-ADD-UNDER` | `( a u parent -- concept )` | CRUD |
| `TAX-REMOVE` | `( concept -- )` | CRUD |
| `TAX-RENAME` | `( a u concept -- )` | CRUD |
| `TAX-ID` | `( concept -- id )` | Navigation |
| `TAX-LABEL` | `( concept -- a u )` | Navigation |
| `TAX-PARENT` | `( concept -- parent\|0 )` | Navigation |
| `TAX-DEPTH` | `( concept -- n )` | Navigation |
| `TAX-CHILDREN` | `( concept -- addr n )` | Navigation |
| `TAX-ROOTS` | `( -- addr n )` | Navigation |
| `TAX-ANCESTORS` | `( concept -- addr n )` | Navigation |
| `TAX-DESCENDANTS` | `( concept -- addr n )` | Navigation |
| `TAX-COUNT` | `( -- n )` | Navigation |
| `TAX-MOVE` | `( concept new-parent -- )` | Mutation |
| `TAX-ADD-SYNONYM` | `( c1 c2 -- )` | Synonyms |
| `TAX-REMOVE-SYNONYM` | `( concept -- )` | Synonyms |
| `TAX-SYNONYMS` | `( concept -- addr n )` | Synonyms |
| `TAX-FIND-SYNONYM` | `( a u -- concept\|0 )` | Search |
| `TAX-SET-FACET` | `( bit concept -- )` | Facets |
| `TAX-CLEAR-FACET` | `( bit concept -- )` | Facets |
| `TAX-HAS-FACET?` | `( bit concept -- flag )` | Facets |
| `TAX-FACETS@` | `( concept -- bits )` | Facets |
| `TAX-FILTER-FACET` | `( mask -- addr n )` | Facets |
| `TAX-CLASSIFY` | `( item concept -- )` | Items |
| `TAX-UNCLASSIFY` | `( item concept -- )` | Items |
| `TAX-ITEMS` | `( concept -- addr n )` | Items |
| `TAX-ITEMS-DEEP` | `( concept -- addr n )` | Items |
| `TAX-CATEGORIES` | `( item -- addr n )` | Items |
| `TAX-FIND` | `( a u -- concept\|0 )` | Search |
| `TAX-FIND-PREFIX` | `( a u -- addr n )` | Search |
| `TAX-EACH-CHILD` | `( xt concept -- )` | Iteration |
| `TAX-EACH-ROOT` | `( xt -- )` | Iteration |
| `TAX-DFS` | `( xt concept -- )` | Iteration |
| `TAX-DFS-ALL` | `( xt -- )` | Iteration |
| `TAX-STATS` | `( -- links concepts )` | Diagnostics |
| `TAX-OK?` | `( -- flag )` | Error |
| `TAX-CLEAR-ERR` | `( -- )` | Error |

---

## Internal Words

These words are implementation details and may change without notice.

| Word | Purpose |
|---|---|
| `_TAX-STR-COPY` | Copy a string into the taxonomy's string pool. |
| `_TAX-ALLOC-CONCEPT` | Allocate a concept from the free-list. |
| `_TAX-FREE-CONCEPT` | Return a concept to the free-list. |
| `_TAX-APPEND-CHILD` | Add child as last sibling of parent. |
| `_TAX-APPEND-ROOT` | Add concept to the root list. |
| `_TAX-DETACH` | Unlink a concept from its parent or root list. |
| `_TAX-SYN-LINK` | Merge two synonym rings. |
| `_TAX-SYN-UNLINK` | Remove a concept from its synonym ring. |
| `_TAX-RM-CON-LINKS` | Remove all item links for a concept. |
| `_TAX-IS-ANCESTOR?` | Ancestor walk for cycle detection. |
| `_TAX-DFS-COLLECT` | Recursive DFS for descendants. |
| `_TAX-COLLECT-DEEP` | Recursive DFS for deep item collection. |
| `_TAX-HASH-SLOT` | Compute hash table slot address. |
| `_TAX-RBUF-*` | Static result buffer management. |

---

## Cookbook

### Build a Simple Taxonomy

```forth
131072 A-XMEM ARENA-NEW ABORT" arena fail"
TAX-CREATE CONSTANT tx

S" Science" TAX-ADD CONSTANT sci
S" Physics" sci TAX-ADD-UNDER CONSTANT phys
S" Chemistry" sci TAX-ADD-UNDER CONSTANT chem
S" Quantum Mechanics" phys TAX-ADD-UNDER CONSTANT qm

phys TAX-DEPTH .         \ → 1
qm TAX-DEPTH .           \ → 2
sci TAX-DESCENDANTS NIP . \ → 3
```

### Classify and Query Items

```forth
100 phys TAX-CLASSIFY
101 qm TAX-CLASSIFY
102 chem TAX-CLASSIFY

phys TAX-ITEMS NIP .         \ → 1  (just 100)
phys TAX-ITEMS-DEEP NIP .    \ → 2  (100 + 101 via qm)
100 TAX-CATEGORIES NIP .     \ → 1  (phys)
```

### Faceted Filtering

```forth
\ Bit 0 = "theoretical", bit 1 = "experimental"
0 qm TAX-SET-FACET
1 chem TAX-SET-FACET
0 phys TAX-SET-FACET  1 phys TAX-SET-FACET

1 TAX-FILTER-FACET NIP .   \ → 2  (phys has bit 0; qm has bit 0)
3 TAX-FILTER-FACET NIP .   \ → 1  (only phys has both bits)
```

### Walk the Tree

```forth
VARIABLE acc
: sum-ids  TAX-ID acc @ + acc ! ;

0 acc !
['] sum-ids TAX-DFS-ALL
acc @ .    \ sum of all concept IDs
```
