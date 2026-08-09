# Library applet product boundary

Library is the Library-owned corpus of material a user deliberately keeps,
hosted and composed by Desk. It owns
managed documents, immutable captures, metadata, provenance, retained history,
collections, lifecycle, query policy, and resource projections. Its domain and
service can run without a renderer in focused tests; that does not make Library
a standalone product outside Desk.

The current prototype uses scalable ordered indexes and chunked blobs over the
neutral persistence framework. The removed fixed catalog, collection bitmap,
complete-bank, and content-arena design is not retained behind a facade.
There is one current Library layout, no legacy reader, and no migration or
compatibility stack.

## Ownership

Library owns:

- stable Library identities for managed documents, captures, and collections;
- copied content, exact content revisions, content identity, and retained
  history;
- titles, canonical tag/origin/lineage metadata, immutable operation receipts,
  archive state, and terminal tombstones;
- collection membership as stable Library RIDs;
- authoritative Library record/index/blob meanings and logical generations;
- exact corpus, collection, and history query semantics;
- inspection, coherent raw evidence, narrow repair, and semantic compaction;
  and
- admission and lifetime policy for Library resource projections.

Library does not own:

- network acquisition, provider parsing, source credentials, or refresh state;
- Pad editing mechanics, Explorer navigation, Streams source policy, Daybook
  time semantics, Agent conversations, Grid calculation, or Practice
  authority;
- a universal graph, workflow engine, synchronization service, collaboration
  server, OCR/PDF pipeline, or vector database; or
- the neutral mechanics of atomic roots, checked pages/segments, ordered
  indexes, chunked blobs, page reclamation, or two-bank compaction.

Those neutral mechanics live under `akashic/persistence/` and contain no Desk
or Library vocabulary. Library-specific model and persistence adapters remain
under `akashic/tui/applets/library/`.

## Product values

A managed document has a Library-generated RID and mutable current content. A
capture has a Library-generated RID and immutable copied content plus admitted
origin facts. Content equality never substitutes for identity or operation
identity.

Create/import and collection creation use caller-generated operation keys. The
receipt seals the exact initial request. A same-key, same-request retry returns
the original object even after later mutation; a changed request under that key
is an idempotency mismatch. Document RIDs, collection RIDs, and receipt keys
share one collision directory.

Metadata is a canonical immutable fact stream rather than fixed tag/lineage
slots. Facts are strictly ordered by kind and payload; duplicate or alternate
encodings are rejected. It admits any number of distinct tags and derived-from
lineage facts, at most one origin, and retains a compact count/digest summary
with the current entry.

Managed history exposes current content plus three predecessors. Metadata and
lifecycle changes advance domain revision without inventing content revisions.
A pruned revision is `GONE`; it never falls forward to latest. Restore
publishes retained bytes as a new current revision.

Archive preserves identity, content, receipt, provenance, history, and
collection membership while excluding the document from active views.
Tombstone is a separate terminal operation that clears content and sensitive
description while preserving enough identity, deletion, and receipt evidence
to keep references and retries honest.

A collection stores its aggregate member count and an ordered membership
keyset. It has no fixed membership bitmap. Removing membership does not delete
a document; archiving or tombstoning a document does not silently rewrite the
independent collection.

## Scale model

The corpus is not bounded by a compiled document, collection, or relationship
count. Durable populations grow through copy-on-write B+tree pages,
append-only checked records, and immutable 32 KiB blob chunks. Physical page
reuse is fenced by both atomic roots and advanced through bounded reclamation
buckets.

The remaining limits are explicit work and interaction bounds:

| Surface | Current bound or behavior |
| --- | --- |
| title | 128 UTF-8 bytes |
| one tag value | 24 UTF-8 bytes |
| collection title | 64 UTF-8 bytes |
| retained content | current plus three predecessors |
| query page | at most 32 rows |
| content materialization | bounded range; larger values stream |
| collection membership | ordered keyset, reconciled in bounded batches |
| compaction | caller-supplied byte/work budget per step |
| live projection owners | 8 RIDs and 64 activation-local leases |

These are not enlarged fixed arrays standing in for enterprise data. Query
pages use semantic keyset continuation, body verification streams immutable
content, and compaction copies bounded semantic units into the inactive data
bank.

Large multi-index mutations use a persisted high-water staging arena. Before
each step the adapter reserves the tallest copy-on-write path and the next
application-root publication within one bounded physical transaction. It may
publish intermediate physical roots without changing visible Library state,
then advances the logical generation exactly once at final publication.
Compaction replaces the old bank and its retained baseline with a fresh,
explicitly owned target-build arena. This avoids both corpus-proportional
memory and an arbitrary fixed mutation row limit.

## Durable owner

`repository.f` is the sole owner of Library's private topology:

```text
/library/root-0             /library/root-1
/library/pages-0            /library/pages-1
/library/segments-0         /library/segments-1
/library/compact-root-0     /library/compact-root-1
```

The validated A/B root selects one data bank. The application-root page names
Library's logical generation, mutation sequence, aggregate counts, bootstrap
identity, ordered-index roots, and reclamation state. Documents, collections,
receipts, membership, history, and search postings are index populations;
content and metadata are immutable blobs.

Cold open does not trust that embedded reclamation header by itself. Before a
nonempty workspace becomes ready, the adapter uses two caller-owned bytes per
committed page and fixed caller-owned audit work to prove both valid root-slot
snapshots: one byte records exact ownership and one independently rejects
duplicate structural traversal. Clean roots submit the application root,
reclaim state, and all fifteen trees; arena roots additionally prove their
pre-stage baseline and exact retained suffix. Only a successful audit of the
still selected generation authorizes the next transaction. The supplied map
is an operational memory budget rather than a persisted Library limit; an
undersized map reports capacity without creating a second format or bypass.
The bundled desktop controller supplies independent 1 MiB source and builder
maps, while direct repository deployments size those maps for their authority
and can rebuild the work graph from the reported requirement.

Publication follows the neutral transaction fence: append/check records,
write/read back copy-on-write pages, write/read back the application root, then
replace the atomic root. A failed transaction leaves no new logical authority.
An uncertain publication is reconciled against the selected root before a
caller may retry.

Provisioning happens only when every reserved role is absent. Namespace/type
collisions, partial stores, unknown bootstrap identities, corrupt checked
records, and unsupported future roots fail closed rather than being adopted as
empty state.

## Query and service

Search is exact and case-sensitive. Titles and bodies use substring matching;
tags use whole-value equality. Durable candidate indexes narrow the scan, then
Library verifies the current authoritative title, metadata, body, lifecycle,
kind, media, and collection facts before returning a row.

Corpus and collection pages are ordered by creation sequence and RID; history
is ordered by revision and RID. Continuations contain those semantic boundary
keys. The observed logical generation is diagnostic, not a physical cursor or
an optimistic lock, so unrelated mutations do not force page conflicts.

The semantic service exposes:

- managed create and capture import;
- exact content, metadata, lifecycle, and tombstone mutations;
- current, exact, retained, receipt, and collection reads;
- retained compare and restore;
- first/after/before corpus, collection, and history pages;
- bounded content range/stream delivery;
- inspection, mirror repair, and coherent raw export; and
- explicit begin/step/finalize/publish/mirror/cleanup compaction.

Every consequential mutation names a stable RID and expected exact state.
Caller-owned outputs are published only after complete validation, durable
reconciliation, and cleanup. Service APIs expose no VFS path, tree key, page
identifier, or storage cursor.

## Failure and maintenance policy

Repository inspection classifies `OK`, `ABSENT`, recognized root `FALLBACK`,
`CORRUPT`, in-memory/operation `UNCERTAIN`, and checksummed `FUTURE` evidence.
It reports each sealed physical role with exact presence, length, and digest.

Raw export revalidates an inspection seal and copies the exact evidence in
bounded chunks. Changed evidence fails without publishing a partial output.
Repair is intentionally limited to mirroring a fully validated fallback root.
It never guesses through corruption, reinterprets future bytes, adopts an
orphan suffix, resets a corpus, or fabricates domain records.

Compaction rebuilds live semantic evidence into the other data bank under
explicit budgets. Publication changes shared authority once, then mirrors it
before the retired bank can be cleaned. Failed or uncertain compaction remains
blocked until explicit abort or recovery reaches a safe state.

At applet initialization, the durable cold states that can be presented are
healthy/fallback, absent, corrupt, or future. `UNCERTAIN` is an operation or
in-memory compaction state, not a durable cold repository health mode; the
applet must not pretend otherwise.

## Projection and other lenses

`projection-adapter.f` exposes `org.akashic.library` resources using
`org.akashic.library.utf8-content.v1`. It receives one explicit Library
service and never consults ambient VFS or UI selection. Managed resources
support describe, snapshot, and exact replace; captures are read-only.
Archived exact locators remain readable while identity acquisition is active
current state only. Tombstoned and pruned locators keep distinct terminal
results.

Pad may become the deep-editing lens and Explorer may reveal a qualified
physical origin, but Library remains semantic owner. A Practice binding can
make a Library resource relevant without copying it or granting implicit
mutation authority. Consequential actions never mean “the selected Library
row” or “the active Pad tab.”

## Current applet surface

The executable applet browses and searches active/archived/all documents,
previews a bounded content prefix, creates and renames managed documents,
archives/unarchives, browses and filters collections, inspects retained
history, and pages in both directions. It reconstructs the first page and
preview from existing authority on a later activation. Corrupt and future
authority are visibly blocked and nonwritable rather than shown as an empty
corpus.

Capture import, tombstone, retained restore/compare, maintenance/raw export,
deep Pad editing, and sibling routing remain deferred UI/integration work. The
service behavior is preserved; it has not been stripped to match the small
current lens.

For implementation details, see
[`../../../../akashic/tui/applets/library/domain.md`](../../../../akashic/tui/applets/library/domain.md).
