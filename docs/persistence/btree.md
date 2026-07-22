# Immutable ordered index

`akashic/persistence/btree.f` is a neutral, caller-owned copy-on-write B+tree
over `PSTORE` checked pages. It owns no paths, schema, application root,
transaction boundary, publication decision, or reclamation policy. A consumer
embeds the returned 64-byte root in its own application-root format and decides
when that root becomes durable.

Keys are nonempty byte strings of at most 256 bytes. Values are byte strings of
at most 64 bytes. Ordering is unsigned lexicographic byte order. Putting an
existing key replaces its value without changing cardinality; deleting a
missing key returns `PERSIST-S-NOT-FOUND`.

## Page geometry and scale

Every node occupies one 4,096-byte checked page with a 4,032-byte checked
payload. Fixed canonical slots give leaves a capacity of 11 key/value entries
and branches a capacity of 14 child/high-key entries. Unused bytes and slots
must be zero, child high keys must be ordered, and node kind, height, scope,
and count are validated on every node read. Each selected child id is then
constrained by the applicable committed or proposed `PSTORE` page bound before
its page is read.

Insertion uses deterministic half splits. Deletion merges or redistributes
with an adjacent sibling, keeps every non-root leaf at least 6 entries and
every non-root branch at least 7 entries, and collapses a one-child root. The
root may be at most nine pages high. The monotonic-build cardinalities before
the next root split begin 11, 89, 635, and 4,457; height nine reaches
74,942,411 entries. `PBTREE-BALANCED-CAPACITY-FOR-HEIGHT` and
`PBTREE-HEIGHT-FOR` expose those build thresholds without materializing a tree.
They do not infer the current height of a tree after deletion: balanced churn
can retain a taller root at a lower cardinality, and the persisted root remains
authoritative for that height.

The implementation keeps no full-dataset arrays and performs no whole-index
rewrite. Point operations read one root-to-leaf path. Mutations copy only that
path plus at most one adjacent sibling per underfull level. The fixed
`PBTREE-WORK-SIZE` is 17,480 bytes, independent of dataset size; a mutation can
allocate or retire at most 19 pages. `PBTREE-PAGE-READS@`,
`PBTREE-PAGE-WRITES@`, `PBTREE-COMPARISONS@`, and
`PBTREE-WORKING-BYTES@` expose actual operation costs. For a nonempty tree of
height `h`, the implementation-bound qualification checks at most `2h-1` page
reads for put/update and `4h-3` for deletion, including sibling repair and
cache-invalidating copy-on-write unwinds. A put writes at most `2h+1` pages
when splits reach a new root; deletion writes at most `2h-1` pages.

## Caller authority and transactions

Initialize one descriptor and one workspace per independently active caller:

```forth
( scope allocator-xt allocator-context store tree -- status ) PBTREE-INIT
( pstore-work work -- status )                         PBTREE-WORK-INIT
( tree root -- status )                                PBTREE-ROOT-INIT
```

The allocator callback has this contract:

```forth
( allocator-context store pstore-work -- page-id status )
```

`PBTREE-HIGH-WATER-ALLOCATE` is the simple append-only allocator. A consumer
with a free-page service can supply another allocator without changing tree
logic. Throws are contained as `PERSIST-S-FAULT`; duplicate, skipped, or
out-of-range page IDs are rejected. Allocation capacity is checked before the
callback is invoked.

`PBTREE-PUT` and `PBTREE-DELETE` require a caller-owned active `PSTORE`
transaction:

```forth
( key-a key-u value-a value-u root out-root tree work -- status ) PBTREE-PUT
( key-a key-u root out-root tree work -- status )                 PBTREE-DELETE
```

They accept either the store's current-generation root or a next-generation
root produced earlier in the same transaction, allowing several mutations to
be chained. The output root is staged internally and copied to `out-root` only
after all tree writes succeed. It therefore remains byte-for-byte unchanged on
validation, allocator, capacity, or storage failure. The tree never begins,
commits, aborts, or publishes the surrounding transaction.

Validation rejected before the mutation run is a no-effect preflight failure.
Once a put or delete has been prepared, any failure poisons the paired `PSTORE`
proposal through `PSTORE-TX-POISON`; the original tree status is retained and
the caller must abort. The sole exception is an ordinary missing delete that
made no allocations. In particular, a late allocator duplicate, range, or
capacity failure after an earlier copy-on-write page succeeded cannot be
followed by an unrelated commit of that now-unreachable page.

A transaction that changes other application state without changing the tree
can use `PBTREE-ROOT-ADVANCE` to copy a current root and advance only its
generation. `PBTREE-GET` reads committed pages and requires a current root;
`PBTREE-GET-TX` reads transaction-visible pages and accepts current or
next-generation roots while the paired transaction is active.

After a successful mutation, `PBTREE-RETIRED-PAGES$` returns the unique pages
made unreachable by that operation. The view is borrowed from the workspace
and is replaced by the next operation. Pages from a committed input root are
retirement candidates; pages made unreachable while chaining mutations may
have been issued in the current transaction instead. Pass a mixed ledger to
`RECLAIM-RELEASE-BATCH`, which discards current-transaction pages and retires
committed pages. The B+tree itself never mutates reclamation state.

## Ordered traversal

Leaves deliberately have no sibling links, avoiding another copy-on-write
update path. A sealed 472-byte caller-owned cursor stores a bounded ancestor
path and the last emitted key:

```forth
( root tree cursor -- status ) PBTREE-CURSOR-INIT
( root tree cursor work -- key-a key-u value-a value-u status ) PBTREE-NEXT
( key-a key-u root tree cursor work -- key-a key-u value-a value-u status )
    PBTREE-SEEK
( last-key-a last-key-u root tree cursor work
  -- key-a key-u value-a value-u status ) PBTREE-RESUME
```

`SEEK` is inclusive and `RESUME` is exclusive. `NEXT` walks the saved path, so
a full scan does not restart at the root for every row. Cursor seals cover the
root identity, scope, generation, flags, last key, and complete bounded path.
A cursor used with another or newer root returns `PERSIST-S-CONFLICT`.
Traversal can update the saved path before a later page or validation failure;
after any result other than success or ordinary end-of-index, callers discard
the cursor and initialize or resume a new one from their last accepted key.

All descriptors, roots, workspaces, cursors, input keys, output roots, and the
complete nested `PSTORE` object graph have explicit non-overlap boundaries.
Busy flags reject callback reentry and are cleared on every contained exit.
The linked RAM-VFS qualification exercises height transitions, sorted scans,
seek/resume across a newly published root, fixed-seed mixed mutation traces and
root collapse, cold reopen, chained transaction reads, measured point/window
bounds, injected allocator/write/capacity faults, alias and reentry rejection,
and four stores with simultaneously active transactions.
