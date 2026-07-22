# Neutral atomic persistence

The `akashic/persistence/` package provides caller-owned storage mechanics for
large, incrementally addressed datasets. It is not a document model, an
applet repository, a filesystem driver, or a compatibility layer. Callers
choose all paths, supply a ready VFS, own every descriptor and workspace, and
place their own opaque application-root page above the neutral authority.

```text
application adapter
        |
        v
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
through private offsets. The checked graph includes the store descriptor,
VFS descriptor, optional counters, optional cache and backing memory, guard,
and bound authority/transaction workspaces and their segment buffers. The
fault callback context is opaque and has no byte-length contract, so its
memory is not claimed by this predicate.

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
4032-byte opaque payload. Page ids are zero-based physical slots. L10 writes
only at the current complete-page tail, verifies exact file geometry, and
rejects partial pages, overwrite attempts, wrapping spans, and aliases against
the descriptor, workspace, VFS, counters, or cache.

The principal operation surface is:

```forth
PPAGE-CACHE-INIT       ( memory bytes slots cache -- status )
PPAGE-FILE-INIT        ( path-a path-u vfs stats cache file -- status )
PPAGE-WORK-INIT        ( work -- status )
PPAGE-ENSURE           ( file work -- status )
PPAGE-FILE-SIZE?       ( file work -- bytes status )
PPAGE-WRITE            ( payload-a payload-u page-id file work -- status )
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

Reads authenticate the checked envelope, ordinal, aligned span, payload, and
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
