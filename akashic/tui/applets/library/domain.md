# Library applet domain package

Status: Library's current prototype domain, persistence, query, service,
projection, and executable lens are implemented under the Desk applet. The
fixed catalog/bank/arena backend has been removed. Documents, collections,
membership edges, history, receipts, and search postings now live in ordered
indexes and immutable chunked blobs over the neutral persistence libraries.
This is one current layout, not a compatibility transition: there is no legacy
reader, old-format facade, or migration stack.

Renderer-free fixtures are a test boundary. Nothing in this package gives
Library a product meaning outside the Desk ecosystem.

## Module boundary

- `model.f` defines caller-owned Library entries, receipts, metadata facts,
  collections, and transient content views. It has no VFS or persistence
  policy.
- `document-values.f` prepares canonical create, capture, replacement,
  metadata, lifecycle, restore, and tombstone values. Controllers and
  projections do not manufacture sealed entries directly.
- `index-keys.f` defines Library's bytewise ordered key families. The neutral
  B+tree sees only opaque byte keys and values.
- `persistence-adapter.f` owns Library record layouts, application-root
  meaning, index families, chunked content and metadata ownership, logical
  generations, exact mutations, reclamation participation, and semantic
  compaction.
- `repository.f` alone chooses `/library/*` paths and composes the adapter with
  the neutral store and compaction coordinator. It owns physical open,
  provisioning, inspection, raw export, mirror repair, and recovery.
- `query.f` owns public request, summary, continuation, and page shapes plus
  exact Library search and filter policy.
- `service.f` is the applet's public semantic command/read/query/maintenance
  boundary. It exposes no persistence page, index key, or VFS path.
- `projection-adapter.f` adapts one explicit Library service to the neutral
  resource-owner pool.
- `controller.f`, `view.f`, and `library.f` own activation state, actions,
  rendering/input, and lifecycle composition.

The neutral machinery under `akashic/persistence/` is independently useful:

- `store.f` composes checked page and record files with an A/B atomic root;
- `btree.f` supplies immutable copy-on-write ordered indexes;
- `blob.f` supplies immutable 32 KiB-chunked content;
- `reclaim.f` supplies bounded two-root-fenced page reuse; and
- `compaction.f` coordinates a budgeted two-bank rebuild and publication.

Those libraries know nothing about Library identities, documents, collections,
metadata, queries, or Desk.

## Domain values and invariants

Library has two content classes:

1. A managed document has a Library-generated RID and replaceable current
   content.
2. A capture has a Library-generated RID and immutable copied content with an
   exact admitted origin.

RIDs and operation keys are distinct. A shared identity directory keeps
document RIDs, collection RIDs, and receipt keys globally disjoint. Equal
content does not imply equal identity. A same-key, same-request retry resolves
to the original RID even after later changes; the same key with different
sealed request facts is an idempotency mismatch.

An entry contains compact current facts and an immutable receipt. Full metadata
is a canonical fact stream:

- every fact is a kind and exact payload with no padding;
- kind/payload order is strict, rejecting alternate order and duplicates;
- tags and derived-from lineage may repeat as distinct sorted facts;
- at most one origin is present; and
- the entry retains the fact byte length, counts, and SHA3-256 digest while the
  complete stream lives as an immutable blob.

Titles are at most 128 UTF-8 bytes, one tag value at most 24, and a collection
title at most 64. Content and metadata lengths are checked signed values rather
than fixed corpus allocations. A caller may materialize a bounded 64 KiB
content window or use range/stream delivery for a larger blob.

The logical managed-document history contains current content plus its three
predecessors. Content, metadata, and lifecycle revisions are separate facts:
metadata or archive changes advance the domain revision without inventing a
content revision. A pruned content revision is `GONE`, never redirected to
current. Restore reads retained immutable bytes and publishes them as a new
current revision.

Archive preserves identity, receipt, provenance, content, and collection
membership. Tombstone is terminal. It removes current content and sensitive
descriptive state while preserving the RID, deletion facts, and receipt needed
to keep references and operation retries honest. Removing collection
membership never deletes a document.

Collection records contain an exact member count, not an embedded bitmap or
fixed member array. Membership is an ordered `(collection, creation sequence,
RID)` keyset. Create and replacement accept canonical RID sets, reconcile
membership edges, and keep unchanged member order stable.

## Current persistent authority

`repository.f` seals these private roles:

```text
/library/root-0             /library/root-1
/library/pages-0            /library/pages-1
/library/segments-0         /library/segments-1
/library/compact-root-0     /library/compact-root-1
```

The two atomic-root records select one physical data bank. Each bank has a
checked page file and append-only checked-record segment. The current
application-root page contains Library logical generation, mutation sequence,
aggregate counts, bootstrap identity, ordered-index roots, and reclamation
state. It does not contain a fixed catalog.

The adapter maintains ordered indexes for shared identities, current documents,
operation receipts, creation/recency/state/title order, exact tags, body
candidates, collections, membership, and retained history. Current document
and collection values are immutable segment records. Content and metadata are
immutable blob manifests and chunks. Reads resolve one atomic root and validate
every page, record, reference, and Library value they traverse.

Provisioning is allowed only when every reserved role is absent. Reopening with
the same bootstrap ID is idempotent; a different ID conflicts. Namespace/type
collisions and partial authority fail closed rather than being adopted or
rewritten.

There is one serialized Library application-root and record layout. The code
does not dispatch among Library format versions or retain the removed
catalog/bank/arena representation.

## Scaling and bounded work

Corpus size is not a compile-time document, collection, or membership count.
Ordered trees grow by pages, segment records append, blobs grow by chunks, and
reclamation rotates bounded buckets. Limits are storage, checked integer
geometry, and deliberately bounded synchronous work—not a 128-row catalog.

A logical mutation may touch many index rows. The adapter reserves against the
transaction's actual page and reclaim ledgers before each staged mutation. Its
copy-on-write allowance is derived from the tallest staging tree (`2h + 1`
pages) plus the application-root and reclaim-finalization reserve. When the
next mutation no longer fits, the adapter publishes the intermediate physical
roots, starts a fresh physical transaction, and continues. Only the final
publication advances the Library logical generation. There is no arbitrary
fixed row-count staging limit.

Other bounded surfaces remain intentional:

- query pages contain at most 32 caller-owned rows;
- adapter range calls and internal candidate batches have fixed work buffers;
- body verification streams blob chunks and preserves matcher state across
  chunk boundaries;
- content reads may request a bounded range or stream to a caller callback;
- collection reconciliation flushes bounded edge batches while preserving one
  logical result; and
- compaction accepts byte and work allowances, copies one bounded semantic
  unit per step, and publishes the rebuilt bank once.

Caller-owned descriptors and workspaces make separate repository/service graphs
interleavable. Activation cache slots, page rows, preview bytes, compaction
scratch, and codec buffers are working-set budgets, not corpus capacities.

## Query contract

Corpus search is exact and case-sensitive. Title and body fields use substring
semantics; tags use whole-value equality. Candidate indexes reduce the search
set, but every returned document is checked against current authoritative
entry, metadata, collection, and streamed body facts. Tombstones are never
discoverable.

Requests can filter lifecycle, kind, media, and exact collection RID. Browse,
collection, and history pages use stable semantic keysets. Corpus and
collection continuations carry creation sequence plus RID; history carries
revision order plus RID. The observed logical generation is diagnostic
provenance, not a conflict token. `AFTER` and `BEFORE` reopen the latest
authority at the captured semantic key, so unrelated mutations do not expose a
physical cursor or invalidate a page.

There is no case folding, Unicode normalization, semantic ranking, OCR,
embedding search, or unbounded result materialization.

## Service and projection boundary

The service owns managed create, capture import, exact content/metadata/
lifecycle replacement, tombstone, retained restore/read/compare, receipt
lookup, collection create/replace/read, bounded queries, inspection, raw
export, mirror repair, and compaction lifecycle. Every consequential mutation
names an exact RID and expected domain/logical state. Public outputs are
caller-owned and publish only after validation and durable reconciliation.

`projection-adapter.f` publishes
`org.akashic.library` /
`org.akashic.library.utf8-content.v1` projections through one explicitly
supplied service. An activation holds at most eight distinct live RID owners
and 64 leases. Managed projections describe, snapshot, and replace; captures
are read-only. Identity acquisition means active current state. Qualified exact
archived revisions remain readable, while tombstoned and pruned revisions keep
their distinct terminal results. Tokens are activation-local and never durable.

## Failure, inspection, and maintenance

Repository load selects validated atomic-root evidence. A single valid older
slot is a recognized fallback, not silent corruption. Both invalid roots,
future root records, damaged checked pages/segments, ambiguous authority, and
unfinished unsafe compaction states remain explicit and blocked. They never
become an empty writable corpus.

Inspection reports the eight sealed physical roles with exact presence,
length, digest, health, and a SHA3-256 evidence seal. Raw export re-inspects
that seal and copies exact bytes in bounded 64 KiB chunks; a stale or changed
second read fails without publishing a partial bundle. Repair is deliberately
narrow: it may mirror a fully validated fallback root. It does not salvage,
reset, reinterpret future bytes, or manufacture missing application state.

Compaction rebuilds only live Library evidence through the adapter into the
other data bank. Begin, bounded step, finalize, publish, mirror, cleanup,
abort, and recovery are explicit. A failed or uncertain phase keeps the owner
blocked until the coordinator reaches a safe state.

## Applet lens and qualification

The executable lens browses/searches active and archived documents, previews a
bounded content prefix, creates and renames managed documents,
archives/unarchives, browses collections, inspects retained history, and pages
in both directions. A later activation reconstructs its first page and preview
from the same durable service. Corrupt and checksummed-future authority are
presented as visible nonwritable states rather than a blank corpus. `UNCERTAIN`
remains an operation or in-memory compaction result; it is not invented as a
durable cold-open UI mode.

Capture import, tombstone, restore/compare, maintenance/raw export, deep Pad
editing, and sibling applet routing remain deferred UI/integration work; their
service implementation is not removed.

Current focused qualification is driven by the `test_library_*_l12.py`
wrappers, `library_managed_two_boot.py`, and these linked profiles:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile library-projection-owner-contracts \
  --max-steps 70000000000 --timeout 1200
python3 local_testing/akashic_tui.py smoke \
  --profile library-applet-functional-contracts \
  --max-steps 55000000000 --timeout 1200
```

Neither qualification path requires ext4 support.
