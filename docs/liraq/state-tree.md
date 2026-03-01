# akashic-state-tree — Arena-Backed State Tree for KDOS / Megapad-64

Hierarchical key-value store for the LIRAQ state layer.  Each state
tree lives in a single KDOS arena, enabling multiple simultaneous
trees and O(1) bulk teardown via `ARENA-DESTROY`.

```forth
REQUIRE state-tree.f
```

`PROVIDED akashic-state-tree` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Dependencies](#dependencies)
- [Memory Architecture](#memory-architecture)
- [Document Lifecycle](#document-lifecycle)
- [Node Types & Constants](#node-types--constants)
- [Error Handling](#error-handling)
- [Node Layout](#node-layout)
- [Descriptor Layout](#descriptor-layout)
- [Tree Navigation](#tree-navigation)
- [Value API](#value-api)
- [Path-Based Mutations](#path-based-mutations)
- [Arrays](#arrays)
- [Protected Paths](#protected-paths)
- [Journal](#journal)
- [Object Merge](#object-merge)
- [Array Insertion](#array-insertion)
- [Journal Resize](#journal-resize)
- [Schema Validation](#schema-validation)
- [Snapshot / Restore](#snapshot--restore)
- [Computed Values (Stubs)](#computed-values-stubs)
- [Subscriptions](#subscriptions)
- [Quick Reference](#quick-reference)
- [Internal Words](#internal-words)
- [Cookbook](#cookbook)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Arena-backed** | All memory (nodes, strings, journal) is allotted from a single KDOS arena per tree.  `ARENA-DESTROY` frees everything at once. |
| **Free-list allocation** | Nodes are 96-byte fixed-size records managed by a free-list for O(1) alloc/free. |
| **String pool** | All strings (key names, string values) are stored in a bump-allocated region.  Multiple nodes can reference overlapping pool entries. |
| **No hidden heap use** | No dynamic allocation outside the arena.  All state lives in the passed-in arena. |
| **Multiple trees** | Switch between trees with `ST-USE` / `ST-DOC`, identical to the DOM pattern. |
| **Dot-separated paths** | Access any node with a single path string: `ship.systems.warp.status`. |
| **8 value types** | Free, String, Integer, Boolean, Null, Float, Array, Object.  Float values are stored as packed IEEE-754 FP32 (software, via `akashic-fp32`). |
| **Change journal** | Configurable circular buffer (default 128 entries, resizable via `ST-JRNL-SIZE!`) records every mutation with sequence numbers and source tags. |
| **Schema validation** | Optional type/range/length/readonly constraints stored under the `_schema` path prefix; checked via `ST-VALIDATE`. |
| **Snapshot/restore** | Capture and restore full arena state for undo/rollback. |
| **Subscriptions** | Path-hashed callback table fires on mutation notification. |

---

## Dependencies

```
state-tree.f
├── ../utils/string.f   (akashic-string)
└── ../math/fp32.f      (akashic-fp32)
```

All dependencies are loaded automatically via `REQUIRE` with relative
paths.

**Runtime requirement:** The KDOS arena allocator must be available
(`ARENA-NEW`, `ARENA-ALLOT`).  The arena should be backed by
`A-XMEM` (extended memory, 14+ MiB) rather than `A-HEAP` (~94 KiB).

---

## Memory Architecture

A state tree is created with `ST-DOC-NEW` which allots three regions
from the arena:

```
┌──────────────────────────────────┐
│  State Tree Descriptor (128 B)   │
├──────────────────────────────────┤
│  Node Pool slab                  │
│  (max-nodes × 96 bytes)         │
│  Free-list threaded through +0   │
├──────────────────────────────────┤
│  Journal slab                    │
│  (128 entries × 72 bytes)        │
├──────────────────────────────────┤
│  String Pool (remaining space)   │
│  Bump-only, grows upward         │
└──────────────────────────────────┘
```

### Sizing example

For a 64 KiB arena with 256 max nodes:

| Region | Size |
|---|---|
| Descriptor | 128 bytes |
| Node pool | 256 × 96 = 24,576 bytes |
| Journal | 128 × 72 = 9,216 bytes |
| String pool | ~31,848 bytes (remainder) |

---

## Document Lifecycle

| Word | Stack | Description |
|---|---|---|
| `ST-DOC-NEW` | `( arena max-nodes -- st )` | Create a new state tree in the given arena.  Allots descriptor, node slab, journal slab, and string region.  Builds free-list.  Creates an Object root node.  Calls `ST-USE` on the new tree. |
| `ST-USE` | `( st -- )` | Set `st` as the current state tree for all subsequent operations. |
| `ST-DOC` | `( -- st )` | Return the current state tree handle. |

### Example

```forth
65536 A-XMEM ARENA-NEW DROP CONSTANT my-arena
my-arena 256 ST-DOC-NEW CONSTANT my-tree

\ Switch trees:
other-tree ST-USE
\ ... work with other-tree ...
my-tree ST-USE
```

Teardown: call `ARENA-DESTROY` on the arena to free all memory at
once (nodes, strings, journal, descriptor).

---

## Node Types & Constants

### Type Tags

| Constant | Value | Description |
|---|---|---|
| `ST-T-FREE` | 0 | Unallocated / free-list slot |
| `ST-T-STRING` | 1 | String value (addr + len in pool) |
| `ST-T-INTEGER` | 2 | 64-bit integer value |
| `ST-T-BOOLEAN` | 3 | Boolean (0 = false, non-zero = true) |
| `ST-T-NULL` | 4 | Null sentinel |
| `ST-T-FLOAT` | 5 | IEEE-754 FP32 packed in low 32 bits of cell |
| `ST-T-ARRAY` | 6 | Ordered child list (index-addressed) |
| `ST-T-OBJECT` | 7 | Named child list (key-addressed) |

### Flag Bits

| Constant | Value | Description |
|---|---|---|
| `ST-F-PROTECTED` | 1 | Path starts with `_` (DCS cannot read) |
| `ST-F-READONLY` | 2 | DCS may not mutate (reserved) |

---

## Error Handling

### Words

```forth
ST-ERR         ( -- addr )   \ Address of error code in current tree
ST-FAIL        ( code -- )   \ Store error code
ST-OK?         ( -- flag )   \ True if no error pending
ST-CLEAR-ERR   ( -- )        \ Reset error state
```

### Error Codes

| Constant | Value | Meaning |
|---|---|---|
| `ST-E-NOT-FOUND` | 1 | Path does not exist |
| `ST-E-TYPE` | 2 | Type mismatch |
| `ST-E-FULL` | 3 | Node pool exhausted |
| `ST-E-PROTECTED` | 4 | Path is protected |
| `ST-E-POOL-FULL` | 5 | String pool exhausted |
| `ST-E-BAD-PATH` | 6 | Malformed path |
| `ST-E-BAD-INDEX` | 7 | Invalid array index |

---

## Node Layout

Each node is 96 bytes (12 cells):

| Offset | Accessor | Purpose |
|---|---|---|
| +0 | `SN.TYPE` | Type tag (one of `ST-T-*`) |
| +8 | `SN.FLAGS` | Flag bits (`ST-F-PROTECTED`, etc.) |
| +16 | `SN.PARENT` | Parent node address (0 = root) |
| +24 | `SN.NEXT` | Next sibling |
| +32 | `SN.PREV` | Previous sibling |
| +40 | `SN.FCHILD` | First child |
| +48 | `SN.LCHILD` | Last child |
| +56 | `SN.NCHILD` | Child count |
| +64 | `SN.NAMEA` | Name string address (in pool) |
| +72 | `SN.NAMEL` | Name string length |
| +80 | `SN.VAL1` | Value cell 1 (integer, bool, FP32, or string addr) |
| +88 | `SN.VAL2` | Value cell 2 (string length, unused for int/bool/float) |

When freed, a node's `+0` cell holds the next free-list pointer.

---

## Descriptor Layout

The state tree descriptor is 128 bytes (16 cells), allotted from the
arena:

| Offset | Accessor | Purpose |
|---|---|---|
| +0 | `SD.ARENA` | KDOS arena handle |
| +8 | `SD.NODE-BASE` | Node pool start |
| +16 | `SD.NODE-MAX` | Max node count |
| +24 | `SD.NODE-FREE` | Free-list head (0 = empty) |
| +32 | `SD.NODE-USED` | Count of allocated nodes |
| +40 | `SD.STR-BASE` | String pool region start |
| +48 | `SD.STR-PTR` | String pool bump pointer |
| +56 | `SD.STR-END` | String pool region end |
| +64 | `SD.ROOT` | Root node address |
| +72 | `SD.JRNL-BASE` | Journal entry array |
| +80 | `SD.JRNL-MAX` | Max journal entries |
| +88 | `SD.JRNL-POS` | Circular write position |
| +96 | `SD.JRNL-SEQ` | Sequence counter |
| +104 | `SD.JRNL-CNT` | Entry count |
| +112 | `SD.JRNL-SRC` | Current source tag |
| +120 | `SD.ERR` | Error code |

---

## Tree Navigation

| Word | Stack | Description |
|---|---|---|
| `ST-ROOT` | `( -- node )` | Return the root node (always Object type) |
| `ST-NODE-COUNT` | `( -- n )` | Number of allocated nodes in current tree |
| `ST-NAVIGATE` | `( path-a path-l -- node\|0 )` | Walk a dot-separated path from root.  Returns 0 if any segment is not found. |

### Path format

Paths are dot-separated segments: `ship.systems.warp.status`.
Each segment is either:
- A **key name** (descends into an Object node by child name)
- A **numeric index** (descends into an Array node by position)

### Example

```forth
42 S" ship.speed" ST-SET-PATH-INT
S" ship.speed" ST-NAVIGATE ST-GET-INT .   \ 42
S" ship" ST-NAVIGATE ST-GET-TYPE .        \ 7  (ST-T-OBJECT)
```

---

## Value API

### Reading values

| Word | Stack | Description |
|---|---|---|
| `ST-GET-TYPE` | `( node -- type )` | Return type tag |
| `ST-GET-INT` | `( node -- n )` | Read integer value |
| `ST-GET-BOOL` | `( node -- flag )` | Read boolean value |
| `ST-GET-STR` | `( node -- addr len )` | Read string value (pool pointer + length) |
| `ST-GET-FLOAT` | `( node -- fp32 )` | Read FP32 value (packed in low 32 bits) |
| `ST-NULL?` | `( node -- flag )` | True if node is Null type |

### Writing values

| Word | Stack | Description |
|---|---|---|
| `ST-SET-INT` | `( n node -- )` | Set integer value.  If node was a container, clears children first. |
| `ST-SET-BOOL` | `( flag node -- )` | Set boolean value.  Container coercion as above. |
| `ST-SET-STR` | `( addr len node -- )` | Set string value.  Copies into string pool. |
| `ST-SET-FLOAT` | `( fp32 node -- )` | Set FP32 value.  Container coercion as above. |
| `ST-SET-NULL` | `( node -- )` | Set to Null.  Container coercion as above. |
| `ST-MAKE-OBJECT` | `( node -- )` | Convert node to Object container. |
| `ST-MAKE-ARRAY` | `( node -- )` | Convert node to Array container. |

### Container-to-scalar coercion

When a container node (Array or Object) is overwritten with a scalar
type (`ST-SET-INT`, `ST-SET-STR`, etc.), all children are recursively
destroyed first.  This ensures no orphaned subtrees.

---

## Path-Based Mutations

These words combine path navigation + ensure + set in a single call.
Intermediate Object nodes are auto-created as needed.

| Word | Stack | Description |
|---|---|---|
| `ST-SET-PATH-INT` | `( n path-a path-l -- )` | Set integer at path |
| `ST-SET-PATH-BOOL` | `( flag path-a path-l -- )` | Set boolean at path |
| `ST-SET-PATH-STR` | `( str-a str-l path-a path-l -- )` | Set string at path |
| `ST-SET-PATH-FLOAT` | `( fp32 path-a path-l -- )` | Set FP32 at path |
| `ST-SET-PATH-NULL` | `( path-a path-l -- )` | Set null at path |
| `ST-GET-PATH` | `( path-a path-l -- node\|0 )` | Navigate to node; sets `ST-E-NOT-FOUND` if missing |
| `ST-DELETE-PATH` | `( path-a path-l -- )` | Remove node and entire subtree |

### Example

```forth
42 S" ship.speed" ST-SET-PATH-INT
S" warp" S" ship.drive" ST-SET-PATH-STR
1 S" ship.active" ST-SET-PATH-BOOL

S" ship.speed" ST-GET-PATH ST-GET-INT .     \ 42
S" ship.drive" ST-GET-PATH ST-GET-STR TYPE  \ warp
```

### Auto-creation

`ST-SET-PATH-INT` with path `a.b.c` creates intermediate Object nodes
`a` and `b` automatically if they don't exist:

```forth
7 S" a.b.c.d" ST-SET-PATH-INT
ST-NODE-COUNT .   \ 5  (root + a + b + c + d)
```

---

## Arrays

Array nodes store ordered children accessible by numeric index.

| Word | Stack | Description |
|---|---|---|
| `ST-ENSURE-ARRAY` | `( path-a path-l -- node )` | Ensure path exists as Array; creates if missing |
| `ST-ARRAY-APPEND-INT` | `( n path-a path-l -- )` | Append integer element |
| `ST-ARRAY-APPEND-STR` | `( str-a str-l path-a path-l -- )` | Append string element |
| `ST-ARRAY-COUNT` | `( path-a path-l -- n )` | Number of elements |
| `ST-ARRAY-NTH` | `( path-a path-l n -- node\|0 )` | Get nth element (0-based) |
| `ST-ARRAY-REMOVE` | `( path-a path-l n -- )` | Remove nth element |

### Example

```forth
10 S" scores" ST-ARRAY-APPEND-INT
20 S" scores" ST-ARRAY-APPEND-INT
30 S" scores" ST-ARRAY-APPEND-INT

S" scores" ST-ARRAY-COUNT .             \ 3
S" scores" 0 ST-ARRAY-NTH ST-GET-INT . \ 10
S" scores" 1 ST-ARRAY-REMOVE
S" scores" ST-ARRAY-COUNT .             \ 2
```

Nested arrays work via dotted paths:

```forth
99 S" ship.crew" ST-ARRAY-APPEND-INT
S" ship.crew" ST-ARRAY-COUNT .   \ 1
```

---

## Protected Paths

Paths starting with `_` (underscore) are considered protected.
Protected nodes are flagged with `ST-F-PROTECTED` on creation.

| Word | Stack | Description |
|---|---|---|
| `ST-PROTECTED?` | `( path-a path-l -- flag )` | True if path starts with `_` |

### Example

```forth
S" _internal" ST-PROTECTED? .   \ -1  (TRUE)
S" public" ST-PROTECTED? .      \ 0   (FALSE)

42 S" _secret" ST-SET-PATH-INT
S" _secret" ST-GET-PATH SN.FLAGS @ 1 AND .  \ 1
```

---

## Journal

The state tree includes a 128-entry circular journal for tracking
mutations.  Each entry is 72 bytes (9 cells):

| Offset | Field | Description |
|---|---|---|
| +0 | sequence | Monotonically increasing sequence number |
| +8 | source | Source tag (`ST-SRC-DCS`, `ST-SRC-BINDING`, etc.) |
| +16 | op | Operation code (user-defined) |
| +24 | path-addr | Address of path string |
| +32 | path-len | Length of path string |
| +40 | old-type | Previous value type |
| +48 | old-val | Previous value |
| +56 | new-type | New value type |
| +64 | new-val | New value |

### Source Constants

| Constant | Value | Description |
|---|---|---|
| `ST-SRC-DCS` | 0 | Change from DCS |
| `ST-SRC-BINDING` | 1 | Change from data binding |
| `ST-SRC-BEHAVIOR` | 2 | Change from behavior script |
| `ST-SRC-RUNTIME` | 3 | Change from runtime |

### Words

| Word | Stack | Description |
|---|---|---|
| `ST-JOURNAL-ADD` | `( op path-a path-l old-type old-val new-type new-val -- )` | Record a journal entry |
| `ST-JOURNAL-SEQ` | `( -- n )` | Current sequence number |
| `ST-JOURNAL-COUNT` | `( -- n )` | Number of entries (max 128) |
| `ST-JOURNAL-NTH` | `( n -- addr\|0 )` | Get nth most recent entry (0 = newest).  Returns 0 if out of range. |

### Example

```forth
\ Record a state change
1 0 0  0 0  2 42  ST-JOURNAL-ADD
ST-JOURNAL-SEQ .      \ 1
ST-JOURNAL-COUNT .    \ 1

\ Read back the most recent entry
0 ST-JOURNAL-NTH 64 + @ .   \ 42  (new-val)
```

---

## Object Merge

`ST-MERGE` performs a shallow merge of one object into another.  For
each child of the source object, the matching key in the destination
is created or overwritten with the source value.  Array and object
children are skipped (shallow — only scalar values are copied).

```forth
: ST-MERGE  ( src-path-a src-path-l dst-path-a dst-path-l -- )
```

Both paths must resolve to existing object nodes.  Sets `ST-E-NOT-FOUND`
if either path does not exist, or `ST-E-TYPE` if either is not an object.

### Example

```forth
1 S" src.x" ST-SET-PATH-INT
2 S" src.y" ST-SET-PATH-INT
3 S" dst.z" ST-SET-PATH-INT

S" src" S" dst" ST-MERGE

S" dst.x" ST-GET-PATH ST-GET-INT .   \ 1
S" dst.y" ST-GET-PATH ST-GET-INT .   \ 2
S" dst.z" ST-GET-PATH ST-GET-INT .   \ 3  (preserved)
```

---

## Array Insertion

Insert a value at a specific index in an array, shifting subsequent
elements right.  Analogous to `ST-ARRAY-APPEND-*` but with position
control.

```forth
: ST-ARRAY-INSERT-INT  ( n index path-a path-l -- )
: ST-ARRAY-INSERT-STR  ( str-a str-l index path-a path-l -- )
```

Index must be in range `0..count`.  When `index = count`, behaves
identically to append.  Sets `ST-E-BAD-INDEX` on out-of-bounds.

### Internal helper

```forth
: _ST-INSERT-AT  ( new-node ref-node parent -- )
```

Links `new-node` before `ref-node` in the parent's doubly-linked
child chain, updating prev/next pointers and `SN.FCHILD` if needed.

### Example

```forth
10 S" v" ST-ARRAY-APPEND-INT
30 S" v" ST-ARRAY-APPEND-INT
20 1 S" v" ST-ARRAY-INSERT-INT

S" v" 0 ST-ARRAY-NTH ST-GET-INT .   \ 10
S" v" 1 ST-ARRAY-NTH ST-GET-INT .   \ 20
S" v" 2 ST-ARRAY-NTH ST-GET-INT .   \ 30
```

---

## Journal Resize

The journal defaults to 128 entries.  `ST-JRNL-SIZE!` resizes it,
preserving existing entries up to the new capacity.

```forth
: ST-JRNL-SIZE!  ( new-max -- )
```

Allocates a new journal slab from the arena, copies existing entries
(most-recent-first, up to `min(count, new-max)`), and updates the
descriptor.  A `new-max` less than 1 is a no-op.

### Example

```forth
500 ST-JRNL-SIZE!
ST-DOC SD.JRNL-MAX @ .   \ 500
```

---

## Schema Validation

Schemas are stored as ordinary state-tree nodes under the `_schema`
path prefix.  No special schema API is needed to **define**
constraints — use the standard path setters.

### Constraint keys

| Key | Type | Checks |
|---|---|---|
| `type` | string | Value type matches: `"integer"`, `"string"`, `"boolean"`, `"float"`, `"null"`, `"array"`, `"object"` |
| `min` | integer | Integer value ≥ min |
| `max` | integer | Integer value ≤ max |
| `min-length` | integer | String length ≥ min-length |
| `max-length` | integer | String length ≤ max-length |
| `read-only` | integer (boolean) | If true, sets `ST-F-READONLY` flag on the node |

### Defining a schema

```forth
S" integer" S" _schema.user.age.type" ST-SET-PATH-STR
0           S" _schema.user.age.min"  ST-SET-PATH-INT
150         S" _schema.user.age.max"  ST-SET-PATH-INT
```

### Validation API

```forth
: ST-VALIDATE  ( path-a path-l -- flag )
```

Returns true (non-zero) if the node at `path` satisfies all
constraints defined under `_schema.<path>.*`.  Returns false and sets
`ST-E-SCHEMA` (8) on failure.  Returns true if no constraints exist.

### Error code

| Constant | Value | Meaning |
|---|---|---|
| `ST-E-SCHEMA` | 8 | Schema validation failed |

### Example

```forth
42 S" user.age" ST-SET-PATH-INT
S" integer" S" _schema.user.age.type" ST-SET-PATH-STR
0           S" _schema.user.age.min"  ST-SET-PATH-INT
150         S" _schema.user.age.max"  ST-SET-PATH-INT

S" user.age" ST-VALIDATE IF ." valid" ELSE ." invalid" THEN
\ prints: valid

200 S" user.age" ST-SET-PATH-INT
S" user.age" ST-VALIDATE IF ." valid" ELSE ." invalid" THEN
\ prints: invalid  (200 > max 150)
```

---

## Snapshot / Restore

Capture the full arena state for undo/rollback.  The snapshot is
stored in a 64 KB static buffer (`_ST-SNAP-BUF`).

```forth
: ST-SNAPSHOT  ( -- snap-addr snap-len )
: ST-RESTORE   ( snap-addr snap-len -- )
```

`ST-SNAPSHOT` copies the arena region (from base to string pointer)
into the static buffer and returns its address and length.

`ST-RESTORE` copies a snapshot back over the arena and updates the
string pointer.

> **Limitation:** Only one snapshot at a time (single static buffer).
> Arena must be ≤ 64 KB.

### Example

```forth
42 S" x" ST-SET-PATH-INT
ST-SNAPSHOT                     \ save state
99 S" x" ST-SET-PATH-INT       \ mutate
ST-RESTORE                      \ rollback
S" x" ST-GET-PATH ST-GET-INT .  \ 42
```

---

## Computed Values (Stubs)

Forward declarations for computed values.  Full evaluation linkage
is deferred to Phase 2 (LEL alignment) when array function support
is available.

```forth
4 CONSTANT ST-F-COMPUTED    \ flag bit on node

: ST-COMPUTED?  ( node -- flag )
: ST-COMPUTED!  ( expr-a expr-l path-a path-l -- )
```

`ST-COMPUTED!` stores the expression string at the path and sets the
`ST-F-COMPUTED` flag bit.  `ST-COMPUTED?` tests for that flag.

The `_ST-COMPUTE-XT` variable holds the execution token for the
expression evaluator (defaults to `NOOP`).

---

## Subscriptions

Path-hashed callback table.  When `_ST-NOTIFY` is called with a
path, all active subscriptions whose path hash matches are fired.

```forth
: ST-SUBSCRIBE    ( path-a path-l xt -- sub-id )
: ST-UNSUBSCRIBE  ( sub-id -- )
: _ST-NOTIFY      ( path-a path-l -- )
```

Up to 64 simultaneous subscriptions (`_ST-SUB-MAX`).  Each entry
stores an FNV-1a hash of the path, the xt, and an active flag.

`ST-SUBSCRIBE` returns a subscription ID (0-based).  Returns -1 if
the table is full.

`ST-UNSUBSCRIBE` deactivates the entry by ID.

`_ST-NOTIFY` is an internal word — surface layers call it after
mutations to trigger callbacks.

### Example

```forth
: my-handler  ." state changed!" CR ;
S" user.settings" ' my-handler ST-SUBSCRIBE CONSTANT my-sub

S" user.settings" _ST-NOTIFY   \ prints: state changed!

my-sub ST-UNSUBSCRIBE
S" user.settings" _ST-NOTIFY   \ (silence)
```

---

## Quick Reference

### Lifecycle

| Word | Stack |
|---|---|
| `ST-DOC-NEW` | `( arena max-nodes -- st )` |
| `ST-USE` | `( st -- )` |
| `ST-DOC` | `( -- st )` |
| `ST-ROOT` | `( -- node )` |
| `ST-NODE-COUNT` | `( -- n )` |

### Error Handling

| Word | Stack |
|---|---|
| `ST-ERR` | `( -- addr )` |
| `ST-FAIL` | `( code -- )` |
| `ST-OK?` | `( -- flag )` |
| `ST-CLEAR-ERR` | `( -- )` |

### Path Operations

| Word | Stack |
|---|---|
| `ST-NAVIGATE` | `( path-a path-l -- node\|0 )` |
| `ST-ENSURE-PATH` | `( path-a path-l -- parent last-a last-l )` |
| `ST-GET-PATH` | `( path-a path-l -- node\|0 )` |
| `ST-DELETE-PATH` | `( path-a path-l -- )` |
| `ST-SET-PATH-INT` | `( n path-a path-l -- )` |
| `ST-SET-PATH-BOOL` | `( flag path-a path-l -- )` |
| `ST-SET-PATH-STR` | `( str-a str-l path-a path-l -- )` |
| `ST-SET-PATH-FLOAT` | `( fp32 path-a path-l -- )` |
| `ST-SET-PATH-NULL` | `( path-a path-l -- )` |

### Value Access

| Word | Stack |
|---|---|
| `ST-GET-TYPE` | `( node -- type )` |
| `ST-GET-INT` | `( node -- n )` |
| `ST-GET-BOOL` | `( node -- flag )` |
| `ST-GET-STR` | `( node -- addr len )` |
| `ST-GET-FLOAT` | `( node -- fp32 )` |
| `ST-NULL?` | `( node -- flag )` |
| `ST-SET-INT` | `( n node -- )` |
| `ST-SET-BOOL` | `( flag node -- )` |
| `ST-SET-STR` | `( addr len node -- )` |
| `ST-SET-FLOAT` | `( fp32 node -- )` |
| `ST-SET-NULL` | `( node -- )` |
| `ST-MAKE-OBJECT` | `( node -- )` |
| `ST-MAKE-ARRAY` | `( node -- )` |

### Arrays

| Word | Stack |
|---|---|
| `ST-ENSURE-ARRAY` | `( path-a path-l -- node )` |
| `ST-ARRAY-APPEND-INT` | `( n path-a path-l -- )` |
| `ST-ARRAY-APPEND-STR` | `( str-a str-l path-a path-l -- )` |
| `ST-ARRAY-COUNT` | `( path-a path-l -- n )` |
| `ST-ARRAY-NTH` | `( path-a path-l n -- node\|0 )` |
| `ST-ARRAY-REMOVE` | `( path-a path-l n -- )` |
| `ST-ARRAY-INSERT-INT` | `( n index path-a path-l -- )` |
| `ST-ARRAY-INSERT-STR` | `( str-a str-l index path-a path-l -- )` |

### Journal

| Word | Stack |
|---|---|
| `ST-JOURNAL-ADD` | `( op path-a path-l old-type old-val new-type new-val -- )` |
| `ST-JOURNAL-SEQ` | `( -- n )` |
| `ST-JOURNAL-COUNT` | `( -- n )` |
| `ST-JOURNAL-NTH` | `( n -- addr\|0 )` |
| `ST-JRNL-SIZE!` | `( new-max -- )` |

### Merge

| Word | Stack |
|---|---|
| `ST-MERGE` | `( src-path-a src-path-l dst-path-a dst-path-l -- )` |

### Schema

| Word | Stack |
|---|---|
| `ST-VALIDATE` | `( path-a path-l -- flag )` |

### Snapshot

| Word | Stack |
|---|---|
| `ST-SNAPSHOT` | `( -- snap-addr snap-len )` |
| `ST-RESTORE` | `( snap-addr snap-len -- )` |

### Computed Values

| Word | Stack |
|---|---|
| `ST-COMPUTED?` | `( node -- flag )` |
| `ST-COMPUTED!` | `( expr-a expr-l path-a path-l -- )` |

### Subscriptions

| Word | Stack |
|---|---|
| `ST-SUBSCRIBE` | `( path-a path-l xt -- sub-id )` |
| `ST-UNSUBSCRIBE` | `( sub-id -- )` |

---

## Internal Words

These are implementation details; do not rely on them in application
code.

| Word | Stack | Description |
|---|---|---|
| `_ST-ALLOC` | `( -- node\|0 )` | Pop node from free-list, zero, increment count |
| `_ST-FREE-NODE` | `( node -- )` | Zero node, push onto free-list, decrement count |
| `_ST-NODE-INIT-FREE` | `( -- )` | Build free-list through node pool slab |
| `_ST-STR-COPY` | `( src len -- addr len )` | Copy string into pool; returns pool address and length |
| `_ST-APPEND-CHILD` | `( child parent -- )` | Link child into parent's doubly-linked child list |
| `_ST-DETACH` | `( node -- )` | Unlink node from parent's child list |
| `_ST-FIND-CHILD` | `( parent name-a name-l -- child\|0 )` | Linear scan of children by name |
| `_ST-INDEX-CHILD` | `( parent idx -- child\|0 )` | Walk to nth child (0-based) |
| `_ST-DESTROY` | `( node -- )` | Recursively free node and all descendants |
| `_ST-DESCEND` | `( node seg-a seg-l -- child\|0 )` | Descend one path segment (name or index) |
| `_ST-ENSURE-CHILD` | `( parent name-a name-l type -- child )` | Find or create child node |
| `_ST-CLEAR-CHILDREN` | `( node -- )` | Destroy all children of a container node |
| `_ST-SPLIT-DOT` | `( path-a path-l -- first-a first-l rest-a rest-l flag )` | Split path at first `.` |
| `_ST-JRNL-ENTRY-ADDR` | `( idx -- addr )` | Address of journal entry by index |
| `_ST-COPY-VALUE` | `( src-node dst-node -- )` | Copy scalar value between nodes (type-dispatched) |
| `_ST-INSERT-AT` | `( new-node ref-node parent -- )` | Link new node before ref in doubly-linked child chain |
| `_ST-SCHEMA-PATH` | `( path-a path-l suffix-a suffix-l -- addr len )` | Build `_schema.<path>.<suffix>` in scratch buffer |
| `_ST-FNV1A` | `( addr len -- hash )` | FNV-1a hash of a byte string |
| `_ST-NOTIFY` | `( path-a path-l -- )` | Fire matching subscription callbacks |

---

## Cookbook

### Create a state tree

```forth
65536 A-XMEM ARENA-NEW DROP CONSTANT game-arena
game-arena 256 ST-DOC-NEW CONSTANT game-state
```

### Build a ship object

```forth
100 S" ship.speed"   ST-SET-PATH-INT
S" warp" S" ship.drive"  ST-SET-PATH-STR
1 S" ship.active"   ST-SET-PATH-BOOL
S" ship.target"     ST-SET-PATH-NULL
```

### Read values back

```forth
S" ship.speed" ST-GET-PATH ST-GET-INT .     \ 100
S" ship.drive" ST-GET-PATH ST-GET-STR TYPE  \ warp
S" ship.active" ST-GET-PATH ST-GET-BOOL .   \ 1
S" ship.target" ST-GET-PATH ST-NULL? .      \ -1
```

### Store and retrieve floats

```forth
\ Store pi as an FP32 float
FP32-PI S" ship.heading" ST-SET-PATH-FLOAT
S" ship.heading" ST-GET-PATH ST-GET-FLOAT FP32>INT .   \ 3

\ Integer to float conversion
42 INT>FP32 S" x" ST-SET-PATH-FLOAT
S" x" ST-GET-PATH ST-GET-FLOAT FP32>INT .              \ 42

\ Arithmetic on float state values
FP32-ONE S" a" ST-SET-PATH-FLOAT
FP32-TWO S" b" ST-SET-PATH-FLOAT
S" a" ST-GET-PATH ST-GET-FLOAT
S" b" ST-GET-PATH ST-GET-FLOAT
FP32-ADD FP32>INT .   \ 3
```

### Manage an array

```forth
S" alice" S" crew" ST-ARRAY-APPEND-STR
S" bob"   S" crew" ST-ARRAY-APPEND-STR
S" carol" S" crew" ST-ARRAY-APPEND-STR

S" crew" ST-ARRAY-COUNT .                      \ 3
S" crew" 1 ST-ARRAY-NTH ST-GET-STR TYPE       \ bob
S" crew" 0 ST-ARRAY-REMOVE
S" crew" 0 ST-ARRAY-NTH ST-GET-STR TYPE       \ bob (was index 1)
```

### Delete a subtree

```forth
1 S" a.b.c" ST-SET-PATH-INT
2 S" a.b.d" ST-SET-PATH-INT
S" a.b" ST-DELETE-PATH
S" a.b.c" ST-GET-PATH .    \ 0  (gone)
```

### Multiple simultaneous state trees

```forth
65536 A-XMEM ARENA-NEW DROP 128 ST-DOC-NEW CONSTANT ui-state
65536 A-XMEM ARENA-NEW DROP 256 ST-DOC-NEW CONSTANT game-state

game-state ST-USE
42 S" score" ST-SET-PATH-INT

ui-state ST-USE
S" dark" S" theme" ST-SET-PATH-STR

game-state ST-USE
S" score" ST-GET-PATH ST-GET-INT .   \ 42
```

### Tear down a state tree

```forth
my-arena ARENA-DESTROY
\ All nodes, strings, journal, descriptor freed at once
```
