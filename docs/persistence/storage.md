# Neutral atomic persistence

The `akashic/persistence/` package provides caller-owned storage mechanics for
large, incrementally addressed datasets. It is not a document model, an
applet repository, a filesystem driver, or a compatibility layer. Callers
choose all paths, supply a ready VFS, own every descriptor and workspace, and
place their own opaque application-root page above the neutral authority.

```text
application adapter
        |
        +------ ordered indexes / keyset cursors
        +------ immutable chunked blobs
        +------ two-root-fenced page reclamation
        +------ bounded two-bank compaction callbacks
        |
transactional store
   |        |        |
checked   checked   A/B checked
pages     segments  root records
        generic VFS
```

The first proving consumer is
`tui/applets/library/persistence-adapter.f`. That adapter remains inside the
Library applet because it owns the Library-specific records, relationships,
paths, and authority rules mapped onto the neutral mechanisms. It is the
Library prototype's sole durable authority; the displaced record-codec and
store-format layers have been deleted rather than retained as compatibility
readers. The neutral package contains no Library vocabulary.

## Ownership and concurrency

There is no process-global current store or operation scratch. The caller
allocates:

- one `PSTORE-SIZE` descriptor per store;
- one `PSTORE-WORK-SIZE` workspace per independently active operation;
- the segment record buffer borrowed by each workspace;
- an optional page cache and its frame memory;
- optional `PERSIST-STATS-SIZE` counters;
- one initialized spinning guard per store; and
- four distinct absolute paths for an ordinary single-bank store: page file,
  segment file, root A, and root B; and
- an explicit second page/segment descriptor pair when two-bank compaction is
  enabled.

Descriptors copy paths and the 32-byte store identity. Workspaces and all
borrowed buffers must remain alive and disjoint for their documented lifetime.
The store guard is held from `PSTORE-BEGIN` through exactly one
`PSTORE-COMMIT` or `PSTORE-ABORT`; other operations use a scoped acquisition.
A work object that opens an authority is retained as that store's authority
workspace for mutation, while independently bound workspaces may perform
bounded reads.

`PSTORE-SPAN-DISJOINT? ( address length store -- flag )` lets a layering
adapter reject aliases against the complete live store graph without reaching
through private offsets. `PSTORE-WORK-SPAN-DISJOINT? ( address length work --
flag )` does the same for a supplied workspace and its borrowed record buffer,
including a workspace not currently installed in the store descriptor. Both
reject negative or wrapping spans and null nonempty spans before checking
overlap; the canonical empty span `0 0` is accepted. The store
graph includes the descriptor, VFS descriptor, optional counters, optional
cache and backing memory, guard, and bound authority/transaction workspaces.
The fault callback context is opaque and has no byte-length contract, so its
memory is not claimed by these predicates.

`concurrency/guard.f` publishes `GUARD-SPIN-SIZE`,
`GUARD-BLOCKING-SIZE`, `GUARD-SPIN?`, and `GUARD-BLOCKING?` so callers that
embed guard storage do not depend on the guard module's private layout.

## Common values

`core.f` defines the shared status family, physical geometry, record
references, root value, fault points, and counters. Statuses distinguish
absent data, invalid input, capacity, I/O, corrupt bytes, busy ownership,
conflict, uncertain cleanup, not-found, and injected or thrown faults.

A `PERSIST-REF-SIZE` reference is an immutable segment tuple:

```text
(byte offset, aligned physical span, positive record ordinal)
```

The exact 96-byte root value contains the 32-byte store identity, committed
page count, committed segment tail, committed record count, one opaque
application page id, and a physical data-bank selector restricted to zero or
one. Its final 24 bytes remain zero and validated. This is one current format,
not a compatibility or migration ladder. Index roots, blob meaning,
relationship policy, retention, and applet schemas belong above this layer.

The package's internal counter-update paths saturate rather than wrap. Page
reads count physical fetches while cache hits are separate; segment reads
count verified record operations while byte totals reflect the underlying
header and record reads. The structure also exposes root/page/segment writes,
verification, comparisons, syncs and faults. Allocation-event and
live/peak/working-byte cells are caller-owned reporting fields rather than
automatic allocator instrumentation.

## Checked pages

`page-file.f` stores exact 4096-byte records: a 64-byte checked envelope and a
4032-byte opaque payload. Page ids are zero-based physical slots. The basic
write remains exact-tail append. L11 also adds an exact-proposal write for a
caller-selected slot below the proposed page count or the one append slot equal
to it. The physical file must contain exactly the proposed number of complete
pages first; suffix disagreement and gaps fail closed. A physical rewrite
invalidates the caller cache even if later close cleanup reports uncertainty.

The principal operation surface is:

```forth
PPAGE-CACHE-INIT       ( memory bytes slots cache -- status )
PPAGE-FILE-INIT        ( path-a path-u vfs stats cache file -- status )
PPAGE-WORK-INIT        ( work -- status )
PPAGE-ENSURE           ( file work -- status )
PPAGE-FILE-SIZE?       ( file work -- bytes status )
PPAGE-WRITE            ( payload-a payload-u page-id file work -- status )
PPAGE-WRITE-AT         ( payload-a payload-u page-id proposed-count file work -- status )
PPAGE-READ             ( page-id committed-count file work -- status )
PPAGE-VERIFY           ( page-id proposed-count file work -- status )
PPAGE-TRUNCATE         ( committed-count file work -- status )
PPAGE-SYNC             ( file -- status )
```

`PPAGE-CACHE-BYTES`, descriptor/work validation and status accessors, and
`PPAGE-PAYLOAD$` provide construction and borrowed-result support around
those operations.

`READ` may use the caller cache. `VERIFY` always reaches the physical record.
Truncation is shrink-only and invalidates cached frames after success.
`WRITE-AT` is a physical seam, not permission to overwrite a page reachable
from current authority. The transaction allocator above it supplies only a
fresh high-water id, a page fenced safe for reuse, or a page first allocated in
the current proposal.

## Checked variable segments

`segment.f` appends aligned checked records without assigning application
meaning. The caller selects a positive maximum payload when initializing the
file and supplies a workspace buffer large enough for the derived physical
record. A successful write returns the exact immutable reference only after
the complete record is present.

```forth
PSEG-FILE-INIT         ( path-a path-u max-payload vfs stats file -- status )
PSEG-WORK-INIT         ( buffer-a buffer-u work -- status )
PSEG-MEASURE           ( payload-u file -- record-u status )
PSEG-ENSURE            ( file work -- status )
PSEG-WRITE             ( payload-a payload-u ordinal offset ref file work -- status )
PSEG-READ              ( ref committed-tail file work -- status )
PSEG-VERIFY            ( ref proposed-tail file work -- status )
PSEG-TRUNCATE          ( committed-tail file work -- status )
PSEG-SYNC              ( file -- status )
```

`PSEG-MAX-RECORD-U@`, descriptor/work validation and status/record-size
accessors, and `PSEG-PAYLOAD$` provide geometry and borrowed-result support.

Reads validate the checked envelope, ordinal, aligned span, payload, and
committed-tail containment. A failed append may leave a suffix, but it cannot
advance authority; the transaction store reconciles suffixes to the current
root before the next mutation.

## A/B root authority

`atomic-root.f` stores one exact 160-byte checked snapshot in each of two
caller-named files. `PROOT-LOAD` independently classifies both slots, verifies
their physical page and segment bounds, rejects divergent equal generations,
and selects the newest valid candidate. One corrupt candidate and one valid
candidate is an explicit fallback, not silent repair.

`PROOT-PUBLISH` writes the inactive slot, checks its exact size, syncs the VFS,
reads the bytes back, validates their tag and payload, and only then marks the
new generation durable. A fault after that durability boundary returns a fault
status while retaining the newly durable generation in caller state. Slot
generation and data-bank accessors expose both independently observed
snapshots for reclamation and compaction fences.

An ordinary `PROOT-INIT` descriptor configures bank zero. A caller may add one
distinct bank-one page/segment pair with `PROOT-BANK1-CONFIGURE`. Candidate and
proposed-root validation follows each root value's `DATA-BANK`; a root naming
an unconfigured bank fails closed. `PROOT-MIRROR` writes the already selected
authority byte-for-byte at the same generation into the other root slot. It
does not publish a new value or advance the generation.

`PSTORE-BANK1-CONFIGURE` additionally requires both candidate descriptors and
the page cache descriptor/backing memory to be disjoint from the entire
enclosing `PSTORE`, including its cells after the inline root. Rejection is
nonmutating; a failed postcondition rolls both root and store bank pointers
back to the single-bank shape.

The workspace used for publication must first have completed `PROOT-LOAD` for
that descriptor. This keeps the active slot and generation explicit and
prevents a fresh workspace from publishing against unknown authority.

## Transactions

Typical use is:

```forth
PSTORE-INIT
PSTORE-WORK-INIT
PSTORE-PROVISION
PSTORE-OPEN
\ or PSTORE-OPEN-ACTIVE after configuring both physical banks

PSTORE-BEGIN
PSTORE-APPEND-RECORD
PSTORE-APPEND-PAGE
PSTORE-WRITE-PAGE-TX
PSTORE-APPLICATION-ROOT!
PSTORE-COMMIT          \ or PSTORE-ABORT
```

`PSTORE-PROVISION` creates only the neutral page and segment files. It does
not invent an application record. `PSTORE-OPEN` returns `PERSIST-S-ABSENT`
for a clean empty store and otherwise installs one validated root authority
only when its data bank matches the caller's configured expectation.
`PSTORE-OPEN-ACTIVE` performs the same single checked-root load but adopts the
selected configured bank. It is the cold-open entry point after a bank
cutover; it does not probe private roots or trial-open both files. Before
installing a different selected bank, it verifies that bank's maximum physical
record fits the caller's workspace. A capacity failure leaves the store
unloaded and its previous expected-bank geometry intact.

`PSTORE-STAGING-RESET ( store work -- status )` is a destructive offline
staging operation, not an ordinary data-store lifecycle call. Under the
store's guard, and only when no transaction or uncertain state is active, it
removes that store's private A/B root files, syncs the VFS, invalidates each
configured bank cache, and returns the descriptor to unloaded generation
zero. A valid single-bank store is supported: the absent optional bank is a
no-op during cache invalidation. The configured page/segment banks, private
root paths, identity, guard, and workspace remain reusable. A rejection before
guard acquisition removes nothing. Callers must establish their independent
durable authority fence before resetting staging roots.

At begin, physical suffixes are truncated back to the committed root before a
proposal is copied. Record and page proposal bounds advance only after direct
readback and byte comparison. Commit syncs page and segment data before root
publication. A no-effect publication failure retains the old root. A failure
inside the maybe-effect window retires the live descriptor as uncertain;
cold reopen may validly select either the old or the completely written new
root. A fault after durable publication adopts the new root immediately.
Abort releases ownership but does not pretend unwritten suffix bytes were
committed.

Reads are bounded by the current root:

```forth
PSTORE-READ-RECORD     ( ref store work -- status )
PSTORE-READ-PAGE       ( page-id store work -- status )
PSTORE-RECORD-PAYLOAD$ ( work -- payload-a payload-u )
PSTORE-PAGE-PAYLOAD$   ( work -- payload-a payload-u )
```

Returned payload views are borrowed until the next operation on that
workspace.

An active transaction has a separate checked-page surface:

```forth
PSTORE-WRITE-PAGE-TX  ( payload-a payload-u page-id store work -- status )
PSTORE-READ-PAGE-TX   ( page-id store work -- status )
PSTORE-READ-RECORD-TX ( ref store work -- status )
PSTORE-TX-READY?      ( store work -- flag )
PSTORE-TX-POISON      ( failure-status store work -- failure-status )
```

It uses the proposal's page bound, so a copy-on-write index can read or replace
pages it allocated earlier in the same transaction. Writing the exact current
proposal count appends and advances that count; replacing a lower id leaves the
count unchanged. Either operation verifies the complete checked record before
returning. Any non-OK PSTORE transaction operation poisons the proposal.
`PSTORE-TX-POISON` gives a layered mutator the same memory-only state
transition when it discovers a local failure after proposal work has begun. It
records and returns the exact non-OK layered status without performing I/O.
Further transaction operations and `PSTORE-COMMIT` are rejected without
releasing ownership or overwriting that recorded cause; `PSTORE-ABORT` is the
only release path. An `UNCERTAIN` poison also sets the store's sticky
uncertainty flag: abort releases ownership but returns `UNCERTAIN`, and a fresh
descriptor must recover from durable roots. Layer-specific validation that
completes before mutation, and another explicitly proven no-effect result such
as an ordinary missing B+tree delete, does not call the seam and leaves a ready
transaction usable.

## Copy-on-write ordered indexes

`btree.f` is a neutral byte-keyed B+tree over checked pages. A caller supplies
one positive scope per logical tree, an allocation callback, the callback
context, and one store. The core does not know whether a key means a RID,
title, time, history fact, or relationship edge. Each consumer embeds the
resulting 64-byte roots in its own application-root payload.

Nodes use canonical fixed slots: an 11-entry leaf contains keys up to 256 bytes
and values up to 64 bytes, while a branch has at most 14 children. The bounded
height is twelve. Fully packed capacity is used only as a corruption ceiling;
the deterministic monotonic-build thresholds are 11, 89, 635, 4,457, ...
through 25,705,247,657 entries. Leaf overflow splits 6/6, branch overflow splits
7/8, and delete performs copy-on-write adjacent-sibling merge or
redistribution. A churned tree can legitimately retain a taller root at a
lower cardinality, but the half-full invariant bounds that retention; the
persisted root, not a cardinality helper, is authoritative for current height.

```forth
PBTREE-INIT
PBTREE-ROOT-INIT
PBTREE-WORK-INIT
PBTREE-GET
PBTREE-PUT
PBTREE-DELETE
PBTREE-ROOT-REBASE
PBTREE-RANGE-NEXT
PBTREE-RANGE-SEEK
PBTREE-RANGE-RESUME
PBTREE-RANGE-PREV
PBTREE-RANGE-SEEK-AT-OR-BEFORE
PBTREE-RANGE-SEEK-BEFORE
PBTREE-RETIRED-PAGES$
```

One operation has fixed 17,672-byte scratch. Its allocation and retirement
ledgers each hold 25 page ids, derived from `2 * height + 1`; a height-twelve
balanced delete uses at most 23. The output root is copied to caller memory only after every
required page write succeeds. The caller then classifies pages from a committed
input root as retired and pages from a root already stamped with the proposed
generation as current-transaction discards.

Leaves have no mutable sibling links. A 520-byte cursor instead seals the exact
tree scope, root page, generation, height, bounded path, state, and last key.
`PBTREE-NEXT` advances that path, `PBTREE-SEEK` starts at a key, and
`PBTREE-RESUME` starts strictly after a stable last key. Supplying a different
root or generation reports conflict rather than silently continuing through
changed order. A traversal failure can invalidate a partially advanced cursor;
the caller resumes a fresh cursor from its last accepted key. Their bounded
`PBTREE-RANGE-*` counterparts invoke a caller visitor over several rows inside
one operation, retain the one-page cache, and return the exact accepted count
and first non-OK visitor status.

`PBTREE-PREV`, `PBTREE-SEEK-AT-OR-BEFORE`, and
`PBTREE-SEEK-BEFORE` provide symmetric descending traversal, with matching
bounded range forms. `PBTREE-ROOT-REBASE` copies a valid private-build root
with one explicit positive target generation so a fresh bank can be finalized
at the shared authority's exact next generation without retaining provisional
build-generation policy in the neutral tree.

## Immutable blobs

`blob.f` streams content into 32 KiB checked segment records and names them
through an immutable 64-way manifest. Ranged reads touch only the manifest path
and requested chunks; no whole-content buffer is required. The exact descriptor,
workspace, callback, EOF, corruption, and counter contracts are documented in
[`blob.md`](blob.md).

## Incremental page reclamation

`reclaim.f` keeps its exact 128-byte state inside the consumer's application
root. Retired and reusable ids live in checked 32-entry bucket pages. A retired
page from generation G becomes reusable only after both independently observed
A/B root slots have generations at least G; until then the older slot may still
be selected by cold recovery and may still reference that page.

```forth
RECLAIM-STATE-INIT
RECLAIM-OPEN
RECLAIM-TX-BEGIN
RECLAIM-TX-ROOM?
RECLAIM-CLAIM-HIGH-WATER
RECLAIM-ALLOCATE
RECLAIM-ALLOCATE-PROTECTED
RECLAIM-RETIRE-BATCH
RECLAIM-DISCARD-BATCH
RECLAIM-RELEASE-BATCH
RECLAIM-STEP
RECLAIM-FINALIZE
RECLAIM-EMPTY-STATE-FOR-GENERATION
RECLAIM-STATE!
RECLAIM-ADOPT       \ or RECLAIM-ABORT
```

One transaction has 64 staged-retirement slots, 64 current-generation discard
slots, and 128 consumer-issued page-id slots. The retirement ledger is shared
by caller-declared retirements and exhausted ready-bucket metadata encountered
while allocating, so 64 is the total staged population rather than an
unconditional caller batch allowance. The 32-page step remains the incremental
work quantum, not the total transaction limit. If reclamation begins after the
caller has appended pages, it seeds that bounded suffix into the issued ledger;
a suffix larger than the ledger fails before ownership or state changes.
`RECLAIM-STEP`'s moved result counts fenced retired ids promoted to reusable;
persistent-stack rotation may make bounded maintenance progress while
returning zero, and proposal-local discard reuse is not included in that
count.
Its requested count is also the ready-population low-water mark: the call is
write-free when at least that many reusable ids are already staged, but a
partial ready bucket does not prevent one eligible output bucket from being
promoted.  A call still writes at most one rotation or promotion output bucket.
This keeps a bounded producer/consumer cadence from accumulating pending
buckets merely because the ready population remains small but nonzero.
Allocation prefers fenced reusable ids and otherwise returns the proposal
high-water id. Finalization prepares at most two pending buckets and two
immediately reusable discard buckets and may rewrite each once to link it, for
at most eight bucket page writes. It exports the proposed state before the
application root is published. Bucket pages are internal metadata and do not
appear in the consumer's 128-entry issued-page ledger.
`RECLAIM-TX-ROOM?` checks caller-supplied worst-case reservations against all
three live ledgers. The public constants
`RECLAIM-STEP-RETIREMENT-MAX` (2),
`RECLAIM-ALLOCATION-RETIREMENT-MAX` (1), and
`RECLAIM-FINALIZE-RETIREMENT-MAX` (4) are the exact maximum additions those
operations can make to the shared retirement ledger. They let a caller include
maintenance, every consumer allocation, and finalization in one checked
preflight instead of depending on allocator internals.

`RECLAIM-ALLOCATE-PROTECTED` has the stack contract
`( future-retirement-reserve reclaim-context store pstore-work -- page-id
status )`. It prefers a fenced reusable id while preserving the stated number
of retirement slots for the transaction's later work. If the selected id is
the last entry in its READY bucket and retiring that exhausted metadata page
would invade the reserve, the call instead returns PSTORE's exact current
high-water id. That fallback is a successful consumer allocation: it records
the id exactly once in the issued ledger while leaving the reusable count,
READY head/index, and staged-retirement ledger unchanged. A reserve outside
`0..RECLAIM-RETIRED-MAX`, insufficient current ledger room, a duplicate
high-water reservation, genuine damaged READY metadata, or an exhausted
issued ledger remains an error and poisons the active proposal; those cases
are never converted into fallback success.

`RECLAIM-CLAIM-HIGH-WATER` lets a hidden copy-on-write owner insist on
PSTORE's exact current high-water id while admitting that id to the same
consumer-issued ledger before the page is written. Wrong, duplicate, or
over-capacity claims poison the proposal just like an ordinary allocation
failure.
The ready cursor is exact: an empty head requires index zero and is equivalent
to a zero reusable count; a nonempty head requires a positive count. Rotation
preserves its pending source before allocating output metadata, because that
allocation may itself inspect and consume a ready bucket.

The Library consumer claims its allocated application-root slot with one
checked placeholder write before reclaim finalization, then rewrites that same
slot with the serialized root before publication. The claim advances a fresh
high-water allocation (while an allocated reusable id is already ledgered), so
reclaim metadata cannot independently select the application-root slot. This
is one deliberate additional checked-page write per Library commit; failure at
that boundary is still prepublication and abort leaves the prior root bytes
unchanged.

`RECLAIM-RETIRE-BATCH` accepts caller-declared unreachable pages from below the
committed input page bound; those pages cross the two-root fence before reuse.
In contrast, `RECLAIM-DISCARD-BATCH` accepts only pages issued and physically
present in the current proposal that became unreachable during later
mutations. A committed discard is immediately reusable because neither
durable root can reference it.
`RECLAIM-RELEASE-BATCH` atomically preflights an unreachable mixed path and
uses the proposal's issued-page ledger to classify each id into those two
groups. This is required when a second copy-on-write mutation produces a path
with new ancestors and untouched committed descendants.
One runtime reclaim descriptor has exactly one active reclaim workspace.
Another begin or open is rejected until that exact owner adopts or aborts.
Abort is deliberately layered: `PSTORE-ABORT` must first end the physical
proposal, then `RECLAIM-ABORT` discards the staged retirements, discards,
issued-page consumption, and maintenance progress. Reclaim abort refuses to
release ownership while the paired store proposal is still active, preventing
the same reusable id from being reissued into a live proposal. After any
non-OK reclaim operation, the proposal is poisoned and the caller must perform
that same store-first, reclaim-second abort sequence rather than continue it.

After commit, adoption is keyed to authority rather than merely to a return
code. A post-publication injected fault can return non-OK after the root became
durable; the store has already advanced to the exact next generation, so the
matching reclamation state is adopted in process. A maybe-effect/uncertain
publication is not adopted: the live descriptor is discarded and cold open
reconstructs both store and reclamation state from whichever root is selected.
There is no legacy free-list reader, version dispatch, or migration layer.

## Bounded two-bank compaction

`compaction.f` coordinates an offline rebuild between two caller-configured
physical page/segment banks. It does not know record liveness, index shapes,
application-root fields, or retention policy. A consumer callback copies one
bounded unit from the selected source snapshot into a private staging store;
a separate finalizer receives the shared authority's exact next generation
and writes the final application root after rebasing any generation-bound
metadata.

The coordinator advances shared authority exactly once, mirrors that exact
snapshot into the other root slot, and only then permits the old bank to be
truncated. Its recovery operation derives safe convergence from checked root
slots and physical bounds alone. It uses no phase journal, format version,
legacy reader, or migration ladder. Writers and readers must be externally
serialized for the offline interval. The complete topology, budgets, callback
ABIs, state machine, publication fence, abort rules, and crash windows are
documented in [`compaction.md`](compaction.md).

## Library proving consumer

Library meaning remains under `tui/applets/library/`; the neutral persistence
modules know only byte keys, opaque values, immutable blobs, reclamation, and
atomic roots. The applet-owned adapter is the current Library authority. Its
application root contains fifteen neutral trees plus reclaim state:

1. shared identity directory;
2. document RID directory;
3. operation receipts;
4. creation order;
5. recency order;
6. lifecycle/kind/media creation order;
7. title order;
8. tag postings;
9. short-text candidate postings;
10. collection directory;
11. collection order;
12. collection title order;
13. collection membership;
14. exact document history;
15. lifecycle/kind/media recency order.

The adapter implements complete document and collection create/replace/read
paths, exact lifecycle and history behavior, bounded stable-key ranges, and
ranged or streamed content over that one authority. Segment compaction copies
these same fifteen roots and their reachable immutable records; it is not a
second Library backend.

## Scale evidence

The host-only analytical profile holds only scalar geometry; it does not
allocate a synthetic large corpus. Its fifteen indexes are the exact live
adapter topology. The proving workload has 1,000,000 documents, 100,000
collections, 10,000,000 retained revisions, 10,000,000 membership edges,
16,000,000 representative current tag postings, and the explicit conservative
short-text candidate workload below. The three collection-record indexes
require six levels, ordinary million-row document indexes require seven, the
shared directory requires eight, tag/membership/history indexes require nine,
and the body-postings tree requires twelve.

One million documents, a representative 4 KiB streamed-body window, and the
existing 128-byte title contain at most
`(4096+4095+4094)+(128+127+126) = 12,666` 1/2/3-byte window positions per
document, or 12.666 billion posting attempts before per-document
deduplication. The actual number of distinct candidates is lower; this
conservative pre-dedup ceiling is what sizes the tree. Height twelve guarantees
25,705,247,657 monotonic-build rows. The 4 KiB window is an analytical
representative, not a product content limit; content beyond 64 KiB remains
separately streamed and qualified.

Together these scalar profiles have a 2,471,699,942-page conservative live-tree
envelope (10,124,082,962,432 bytes). This is not a physical-file bound under
churn. A cold point lookup reads at most twelve index pages. With the cache
reset once at range entry, a
deep 32-result keyset window uses one cache-preserving B+tree operation and
reads at most 44 index pages (35 on the nine-level edge index). Descending
windows have the same bound. 7,813 edge windows cover a 250,000-edge contiguous
relationship range in at most 273,455 index reads,
well below the 909,091-leaf full scan. That is a bounded no-full-scan
qualification, not an enterprise-throughput claim: it is about 1.09 index
reads per returned edge. Every public window still prepares one bounded
traversal, but callbacks within that window retain the cursor path and
one-page cache instead of reopening an operation for every row. Blob ranges
account for one complete manifest path per touched chunk.

The Library index workspace is exactly 119,840 bytes. Its largest constituents
are one 17,672-byte B+tree workspace, one 46,960-byte blob workspace, one
10,800-byte reclaim workspace, fifteen 80-byte tree descriptors, two arrays of
fifteen 64-byte roots, the current/old document and collection stages, one
4,032-byte page scratch area, and one 32 KiB content scratch window. The
caller-owned `PSTORE` workspace, record buffer, cache, and cache frames remain
separate. `allocation_events = 0` means no dynamic or corpus-proportional
memory allocation during an ordinary operation; copy-on-write transactions
still allocate physical pages.

`LIBPA-INDEX-PAGE-READS@`, `LIBPA-INDEX-PAGE-WRITES@`, and
`LIBPA-INDEX-COMPARISONS@` sum the cumulative neutral B+tree counters across
all fifteen roots. Blob byte/chunk/manifest counters and reclaim progress remain
available from their respective caller-owned workspaces.

Staged mutation admission is page-budget-aware. Before another index mutation,
the adapter derives the largest possible allocation from the current tree
height, reserves the application-root and reclaim finalization pages, and asks
the public reclaim transaction ledger whether that complete reserve fits. If
it does not, the adapter physically publishes the current stage before
continuing. A height-12 B+tree mutation can allocate at most `2h+1 = 25`
checked pages, so at most five such index mutations plus one application root
fit in the 128-page consumer ledger (`5*25+1 = 126`); the live decision also
accounts for allocations already consumed by blob work.

## Fault and cleanup contract

The injected callback receives `(point ordinal context -- status)` at each
segment write/verify, page write/verify, data sync, root write/size/sync/
verify, and post-publication boundary. It may return a nonzero status or
`THROW`. Both are contained.

Every operation restores its busy flag, VFS binding, file descriptor scope,
and guard ownership. Cleanup failure and maybe-effect root publication both
produce `PERSIST-S-UNCERTAIN`. The live descriptor then rejects reads as well
as mutations; recovery uses a fresh descriptor and cold `PSTORE-OPEN` to
select and validate the surviving authority. A failed transactional mutation
with a known no-effect outcome requires `PSTORE-ABORT` before the workspace
can be reused.

## Filesystem boundary

The package requires only the generic VFS and checked access helpers. It does
not require ext4, select a driver, or rely on a current global VFS binding.
RAM-VFS qualification is the deterministic fault and interleaving backend;
other VFS implementations may be measured later without changing applet
semantics.
