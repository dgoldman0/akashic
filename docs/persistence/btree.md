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
root may be at most twelve pages high. The monotonic-build cardinalities before
the next root split begin 11, 89, 635, and 4,457; height nine reaches
74,942,411 entries, height eleven reaches 3,672,178,235, and height twelve
reaches 25,705,247,657. `PBTREE-BALANCED-CAPACITY-FOR-HEIGHT` uses
signed-cell-saturating arithmetic, and it and
`PBTREE-HEIGHT-FOR` expose those build thresholds without materializing a tree.
They do not infer the current height of a tree after deletion: balanced churn
can retain a taller root at a lower cardinality, and the persisted root remains
authoritative for that height.

The implementation keeps no full-dataset arrays and performs no whole-index
rewrite. Point operations read one root-to-leaf path. Mutations copy only that
path plus at most one adjacent sibling per underfull level. The fixed
`PBTREE-WORK-SIZE` is 17,672 bytes, independent of dataset size; a mutation can
allocate or retire at most 25 pages. `PBTREE-PAGE-READS@`,
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

Fresh-bank builders can use:

```forth
( source target-generation out-root tree -- status ) PBTREE-ROOT-REBASE
```

to copy a structurally valid root and stamp one exact positive publication
generation. This is a finalization operation, not a format/version migration:
the private build may have consumed several provisional generations while the
shared application authority must publish at one caller-selected generation.
The source need not match the currently open store generation. The target must
be in `1..PERSIST-MAX-SIGNED`; source and output must not overlap; and the
output remains byte-for-byte unchanged on every rejected generation, root,
tree, span, or alias.

After a successful mutation, `PBTREE-RETIRED-PAGES$` returns the unique pages
made unreachable by that operation. The view is borrowed from the workspace
and is replaced by the next operation. Pages from a committed input root are
retirement candidates; pages made unreachable while chaining mutations may
have been issued in the current transaction instead. Pass a mixed ledger to
`RECLAIM-RELEASE-BATCH`, which discards current-transaction pages and retires
committed pages. The B+tree itself never mutates reclamation state.

## Ordered traversal

Leaves deliberately have no sibling links, avoiding another copy-on-write
update path. A sealed 520-byte caller-owned cursor stores a bounded ancestor
path and the last emitted key:

```forth
( root tree cursor -- status ) PBTREE-CURSOR-INIT
( root tree cursor work -- key-a key-u value-a value-u status ) PBTREE-NEXT
( key-a key-u root tree cursor work -- key-a key-u value-a value-u status )
    PBTREE-SEEK
( last-key-a last-key-u root tree cursor work
  -- key-a key-u value-a value-u status ) PBTREE-RESUME
( root tree cursor work -- key-a key-u value-a value-u status ) PBTREE-PREV
( key-a key-u root tree cursor work -- key-a key-u value-a value-u status )
    PBTREE-SEEK-AT-OR-BEFORE
( key-a key-u root tree cursor work -- key-a key-u value-a value-u status )
    PBTREE-SEEK-BEFORE
```

`SEEK` is inclusive and `RESUME` is exclusive. `NEXT` walks the saved path, so
a full scan does not restart at the root for every row. The reverse family is
symmetric: `PREV` starts at the greatest key and retreats, `SEEK-AT-OR-BEFORE`
is inclusive, and `SEEK-BEFORE` is exclusive. Cursor seals cover the root
identity, scope, generation, flags, last key, and complete bounded path. A
cursor used with another or newer root returns `PERSIST-S-CONFLICT`.
Traversal can update the saved path before a later page or validation failure;
after any result other than success or ordinary end-of-index, callers discard
the cursor and initialize or resume a new one from their last accepted key.

Callers that want a bounded window without reopening the B+tree operation for
every row use the callback range family:

```forth
( root tree cursor limit visitor-xt visitor-context work -- count status )
    PBTREE-RANGE-NEXT
( key-a key-u root tree cursor limit visitor-xt visitor-context work
  -- count status ) PBTREE-RANGE-SEEK
( last-key-a last-key-u root tree cursor limit visitor-xt visitor-context work
  -- count status ) PBTREE-RANGE-RESUME
( root tree cursor limit visitor-xt visitor-context work -- count status )
    PBTREE-RANGE-PREV
( key-a key-u root tree cursor limit visitor-xt visitor-context work
  -- count status ) PBTREE-RANGE-SEEK-AT-OR-BEFORE
( key-a key-u root tree cursor limit visitor-xt visitor-context work
  -- count status ) PBTREE-RANGE-SEEK-BEFORE
```

The limit must be nonnegative. A zero limit succeeds without requiring or
calling a visitor. Forward `RANGE-SEEK` is inclusive and `RANGE-RESUME` is
exclusive. Reverse `RANGE-SEEK-AT-OR-BEFORE` is inclusive and
`RANGE-SEEK-BEFORE` is exclusive; callbacks arrive in descending key order.
The visitor receives borrowed spans valid only for that callback:

```forth
( key-a key-u value-a value-u visitor-context -- status )
```

The returned count includes exactly the callbacks that returned
`PERSIST-S-OK`. A visitor's first non-OK persistence status is returned
unchanged, while a throw or an out-of-domain result is contained as
`PERSIST-S-FAULT`. End-of-index is instead an ordinary successful short
window. Busy state rejects visitor reentry and is cleared on every exit.

All rows in one range share a single operation and its one-page cache. This
removes the mandatory leaf reread imposed by separate public `NEXT` calls:
cost is the initial root-to-leaf path plus only the leaf and ancestor
boundaries crossed. The direct height-three qualification returns each of two
successive 32-row windows in no more than 17 page reads, with no corpus-sized
allocation or restart from the root.

## Immutable snapshot audit

Cold ownership and recovery checks cannot substitute a current-only cursor for
an exact older A/B root. The root and store layers expose checked slot
inspection and a guard-bound arbitrary-bank page seam:

```forth
( slot destination-root root proot-work -- generation status ) PROOT-SLOT@
( slot destination-root store pstore-work -- generation status )
    PSTORE-ROOT-SLOT@
( generation page-count data-bank store pstore-work -- flag )
    PSTORE-SNAPSHOT-BOUND-TX?
( page-id store pstore-work -- status ) PSTORE-READ-PAGE-SNAPSHOT-TX
```

The slot operations zero their destination first and expose the exact 96-byte
root only after the named checked record, positive generation, physical bounds,
and application-root page validate. A missing slot is `PERSIST-S-ABSENT`;
malformed bytes are `PERSIST-S-CORRUPT`; I/O remains distinct. Standalone
`PROOT-SLOT@` requires external publication serialization. The PSTORE form
holds the store guard, verifies store identity, rejects a slot newer than its
loaded authority, and requires exact bytes when the slot generation is
current.

A caller begins an ordinary clean PSTORE transaction and calls
`PSTORE-ROOT-SLOT@` inside it. Success binds the exact slot, generation,
root, `PAGE-COUNT`, and `DATA-BANK` in caller-owned work. Page reads accept no
fallback bank/bound argument and expose the verified payload through
`PSTORE-PAGE-PAYLOAD$`. A second slot read replaces the binding; transaction
end clears it. This uses the existing guard authority, not another session
state machine or persisted format.

The caller then initializes a dedicated fixed audit workspace:

```forth
( pstore-work audit-work -- status ) PBTREE-AUDIT-WORK-INIT
( tree-root snapshot-generation snapshot-page-count snapshot-data-bank
  visitor-xt visitor-context tree audit-work
  -- node-count row-count status ) PBTREE-AUDIT-SNAPSHOT-TX
```

The three explicit snapshot dimensions must exactly match the guard-bound slot
value. This deliberate redundancy catches swapped or stale caller metadata;
the physical page reader still takes its bank and bound only from the bound
root. A persisted B+tree root may be older than the currently selected store
generation, but its generation must exactly equal the submitted slot
generation.

The auditor is iterative and reads each node once in a valid topology. Its
caller-owned frontier has the exact worst-case capacity
`1 + (PBTREE-HEIGHT-MAX - 1) * (PBTREE-BRANCH-CAPACITY - 1)`, so memory is
fixed by the checked height/fanout contract rather than corpus cardinality.
Every checked node must satisfy snapshot bounds, scope, exact expected height
and kind, canonical slots and zero padding, root/non-root occupancy, and strict
local key ordering. Parent high keys travel with pending children and must
equal each child's actual maximum. Leaves are visited globally left-to-right
and each next minimum must exceed the previous maximum. The accumulated leaf
rows must equal the root cardinality exactly. Height decrement rejects branch
cycles, while the high-key and global range proofs reject shared subtrees even
if a visitor accepts every page.

Before a page is counted or read, the visitor receives:

```forth
( page-id expected-height visitor-context -- status )
```

This is the ownership hook for detecting aliases against other trees,
application roots, blobs, and reclaim metadata. `PERSIST-S-OK` accepts the
page; the first other in-domain persistence status is returned unchanged.
Throws and results outside the persistence-status domain become
`PERSIST-S-FAULT`. Returned node and row counts include only work accepted
before the result. After every accepted callback and before the page read, the
auditor rechecks the original generation, page count, and data bank against
the still-bound store snapshot. A callback that replaces or invalidates that
binding yields `PERSIST-S-CONFLICT` without reading under the replacement.
An empty tree invokes no visitor, permits a null visitor execution token, and
returns zero counts; a nonempty tree requires a visitor.

A successful audit begin raises the tree's `PBTREE-WORKING-BYTES@` high-water
mark to at least `PBTREE-AUDIT-WORK-SIZE`, alongside the page-read and key
comparison metrics accumulated by traversal. Rejected preflight calls do not
claim an operation workspace.

All descriptors, roots, workspaces, cursors, input keys, output roots, and the
complete nested `PSTORE` object graph have explicit non-overlap boundaries.
Busy flags reject callback reentry. A rejected nested call leaves the active
audit's status and busy ownership untouched; only the owning call clears busy
on its contained exit.
The linked RAM-VFS qualification exercises height transitions, sorted scans,
seek/resume across a newly published root, fixed-seed mixed mutation traces and
root collapse, cold reopen, chained transaction reads, measured point/window
bounds, injected allocator/write/capacity faults, alias and reentry rejection,
and four stores with simultaneously active transactions.
