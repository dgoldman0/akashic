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
        |
transactional store
   |        |        |
checked   checked   A/B checked
pages     segments  root records
        generic VFS
```

The initial proving consumer is
`tui/applets/library/persistence-adapter.f`. That adapter remains inside the
Library applet and is deliberately non-authoritative until Library's complete
cutover. Its nested use of the old Library record codec is temporary L10
scaffolding scheduled for deletion in L12; the neutral package contains no
Library vocabulary.

## Ownership and concurrency

There is no process-global current store or operation scratch. The caller
allocates:

- one `PSTORE-SIZE` descriptor per store;
- one `PSTORE-WORK-SIZE` workspace per independently active operation;
- the segment record buffer borrowed by each workspace;
- an optional page cache and its frame memory;
- optional `PERSIST-STATS-SIZE` counters;
- one initialized spinning guard per store; and
- four distinct absolute paths: page file, segment file, root A, and root B.

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
page count, committed segment tail, committed record count, and one opaque
application page id. Its remaining 32 bytes are one zero flags cell and 24
zero reserved bytes; both are validated as part of this single current
format, not used as a compatibility or migration ladder. Index roots, blob
meaning, relationship policy, retention, and applet schemas belong above this
layer.

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
generation accessors expose both observed slot generation numbers for the
later reclamation fence.

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

PSTORE-BEGIN
PSTORE-APPEND-RECORD
PSTORE-APPEND-PAGE
PSTORE-WRITE-PAGE-TX
PSTORE-APPLICATION-ROOT!
PSTORE-COMMIT          \ or PSTORE-ABORT
```

`PSTORE-PROVISION` creates only the neutral page and segment files. It does
not invent an application record. `PSTORE-OPEN` returns `PERSIST-S-ABSENT`
for a clean empty store and otherwise installs one validated root authority.

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
height is nine. Fully packed capacity is used only as a corruption ceiling;
the deterministic monotonic-build thresholds are 11, 89, 635, 4,457, ...
through 74,942,411 entries. Leaf overflow splits 6/6, branch overflow splits
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
PBTREE-RETIRED-PAGES$
```

One mutation has fixed 17,480-byte scratch. Its allocation and retirement
ledgers each hold 19 page ids, derived from `2 * height + 1`; a balanced delete
uses at most 17. The output root is copied to caller memory only after every
required page write succeeds. The caller then classifies pages from a committed
input root as retired and pages from a root already stamped with the proposed
generation as current-transaction discards.

Leaves have no mutable sibling links. A 472-byte cursor instead seals the exact
tree scope, root page, generation, height, bounded path, state, and last key.
`PBTREE-NEXT` advances that path, `PBTREE-SEEK` starts at a key, and
`PBTREE-RESUME` starts strictly after a stable last key. Supplying a different
root or generation reports conflict rather than silently continuing through
changed order. A traversal failure can invalidate a partially advanced cursor;
the caller resumes a fresh cursor from its last accepted key.

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
RECLAIM-ALLOCATE
RECLAIM-RETIRE-BATCH
RECLAIM-DISCARD-BATCH
RECLAIM-RELEASE-BATCH
RECLAIM-STEP
RECLAIM-FINALIZE
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

## Library proving consumer

L11 keeps all Library meaning under `tui/applets/library/`. Its one current
application root contains five neutral trees—for RID lookup, creation order,
title order, explicit membership edges, and exact revision history—plus the
reclaim state. The applet-owned adapter exercises point lookup, bounded stable
key slices, membership lookup and enumeration, history descriptors, and ranged
or streamed content. The existing create/read calls route through this same
indexed authority, so the proving surface does not create a second durable
truth.

This remains a non-authoritative, create-oriented vertical slice. It neither
removes current Library behavior nor claims that update/re-key, lifecycle,
text-candidate, repository, projection, or TUI paging conversion is complete.
Those parity and cutover tasks remain L12, after which the temporary current
record-codec seam can be deleted. There is one accepted root shape and no old
format reader or migration ladder.

## Scale evidence

The host-only analytical profile holds only scalar geometry; it does not
allocate a synthetic million-document corpus. Its seven indexes describe the
settled L12 target—1,000,000 documents, 10,000,000 revisions, and 10,000,000
relationship edges—and size the L11 neutral mechanics rather than claiming
that the current five-index adapter has already completed L12.

The earlier policy values of six pages for a point lookup and 32 pages /
262,144 bytes for a metadata mutation were provisional, pre-geometry
placeholders. Settled node occupancy and churn retain up to nine index levels.
The explicit representative steady-state transaction totals 65 copy-on-write
index writes, two writes of one allocated application-root page, six reclaim
finalization writes, and four demand-coupled maintenance writes produced by 66
bounded reclaim steps when two prior pending buckets are available. The
machine policy records that representative scenario as nine lookup pages and
77 mutation pages / 315,392 checked-page bytes. It separately records the
unconditional 66-step structural ceiling as 139 pages / 569,344 checked-page
bytes: arbitrary pre-existing reclaim backlog can require one maintenance
output write on every step, never more than one. These values replace the
placeholders with settled geometry and explicitly labeled scenario and ceiling
accounting; they are not larger constants standing in for the old
aggregate-bank algorithm.

After balanced churn, the target indexes require at most nine levels and have
an 8,749,977-page conservative live-tree envelope (35,839,905,792 bytes). This
is not a physical-file bound under churn. A cold point lookup reads at most
nine index pages. With the current public per-call cache reset, a deep
32-result keyset window reads at most 66 index pages; 7,813 such windows cover
a 250,000-edge contiguous relationship range in at most 515,658 index reads,
well below the 909,091-leaf full scan. That is a bounded no-full-scan
qualification, not an enterprise-throughput claim: it is about 2.06 index
reads per returned edge because every public window re-prepares traversal and
resets the per-operation cache. Cursor- and cache-preserving range traversal
is an explicit L12 measurement and optimization trigger. Blob ranges account
for one complete manifest path per touched chunk.

In that same steady-state scenario, the deferred L12 representative directory
replacement plus two ordered re-keys consumes 66 consumer-issued pages, three
finalization-bucket allocations, and four maintenance-bucket allocations: 73
physical page allocations in all. Its 77 checked-page writes total 315,392
bytes. It retires 48 committed consumer pages and seven metadata pages, and
discards 14 proposal-local pages. The 3,136-byte aligned segment record and
160-byte atomic authority record are accounted separately, for 318,688 total
bytes.

The Library index workspace is exactly 84,624 bytes. It includes one 17,480-
byte B-tree workspace, one 46,936-byte blob workspace, and one 10,800-byte
reclaim workspace; the caller-owned `PSTORE` workspace, record buffer, cache,
and cache frames remain separate objects. In this evidence,
`allocation_events = 0` means no dynamic or corpus-proportional memory
allocation during an ordinary operation; it does not mean that a copy-on-write
transaction allocates no physical pages.

Current reclamation bounds the checked page file only. Immutable segment
records retired by index changes are not yet compacted or reclaimed, so the
physical segment file can continue to grow under churn even when the page
high-water mark plateaus. Eventual bounded segment compaction is therefore a
separate later requirement, not an L11 claim.

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
