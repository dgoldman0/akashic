# Library domain package

Status: the pure model/codecs and store formats, the sole VFS owner, and the
first three ordered Gate 4 implementation milestones are implemented and
qualified. The public headless owner now creates and replaces managed
documents, imports immutable captures, manages metadata and lifecycle, exposes
retained history and receipts, creates/replaces and enumerates RID-based
collections, and serves bounded authoritative corpus queries through a
disposable title/body/tag index. The package still has no projection-owner
lifecycle, repair/export surface, applet/UI, or Streams integration, so the
overall Gate 4 exit is not yet claimed.

The current modules are:

- `model.f`: bounded caller-owned Library records, canonical validators,
  initial-request seals, retry comparisons, and pure catalog/collection
  cross-record transition checks.
- `record-codec.f`: deterministic V1 envelopes for catalog entries,
  collections, and immutable content revisions.
- `store-format.f`: deterministic V1 arena, catalog-bank, and head formats plus
  the ordered content-frame commitment used by the VFS owner.
- `vfs-store.f`: the sole owner of Library-private VFS paths, committed-snapshot
  loading/provisioning, fail-closed recovery, the guarded public headless
  document/capture/history/receipt/collection mutation and read surface, and
  the activation-local disposable search index and bounded query API.

The model, record codec, and store-format modules remain VFS-free. `vfs-store.f`
alone performs I/O and chooses the private storage topology. None publishes a
resource or imports a sibling domain or applet.

## Sealed Gate 4A bounds

The initial catalog holds at most 128 entries and 32 collections. A collection
uses a canonical 128-bit membership bitmap. Entries admit at most 16 tags and
four typed lineage locators. Managed documents retain at most four content
revisions; content is valid UTF-8 bounded to 65,536 bytes.

The persisted widths are fixed for V1:

| Shape | Bytes |
| --- | ---: |
| VFS locator | 320 |
| origin union | 328 |
| lineage slot | 328 |
| immutable receipt | 328 |
| catalog entry payload | 2,832 |
| catalog record | 3,072 |
| collection payload | 224 |
| collection record | 320 |
| transient content view | 128 |
| content header | 160 |
| largest content record | 65,696 |

A full set of fixed catalog and collection records occupies at most 403,456
bytes before store framing. Titles are bounded to 128 bytes, tag text to 24,
collection titles to 64, and VFS snapshot paths to 255.

## Canonical model rules

All unused fixed-capacity bytes must be zero. Tags and direct qualified lineage
locators are strict bytewise sorted sets, so duplicates and alternate orderings
are rejected. Catalog and collection identities and operation keys are unique
and globally disjoint. Collection membership may name only allocated catalog
slots.

Revision-one entries are active initial requests. Their domain-separated
request seal covers the caller's request payload, including the expected
catalog generation; the operation key is compared separately. The seal excludes
owner-generated identity, operation counters, and clocks. Later archive,
content, metadata, and tombstone revisions preserve
the byte-exact immutable receipt. A tombstone erases content, metadata, origin,
lineage, and non-deletion clocks while permanently retaining identity and the
receipt.

The pure transition validators freeze identity, kind, media, initial request
facts, and tombstones; prevent content rollback and same-revision digest
substitution; and require both the domain revision and mutation sequence to
advance whenever a persisted entry or collection changes.

## Codec and lifetime rules

Fixed records have a 64-byte envelope and canonical zero padding. Content
records have a 160-byte header, an exact eight-byte-aligned record length, and
zero padding. Decoders validate magic, header CRC, format, lengths, flags,
payload CRC, canonical padding, and the model. Content additionally validates
SHA3-256 identity and UTF-8. A checksummed future format is reported as
unsupported rather than malformed.

`LIB-CONTENT-RECORD-DECODE` returns `LIBCT.DATA-A` as a borrowed pointer into
the caller's encoded record buffer. The view is valid only while that buffer is
alive and unchanged. `LIB-CONTENT-RECORD-MEASURE` safely derives the required
record size from a complete V1 header; it does not prove payload integrity.
Source, payload, and destination aliases are rejected before modifying the
aliased bytes.

## Sealed Gate 4B pure store ABI

The content arena is 655,360 bytes: one 512-byte immutable header followed by
654,848 bytes of sector-framed content. Each frame is the exact aligned content
record padded to a 512-byte boundary and is at most 66,048 bytes. Its immutable
arena identity, exact committed tail, record count, and ordered chain prevent
an owner from treating uncommitted suffix bytes as published content.

Each complete catalog bank is 403,968 bytes: one 512-byte header followed by
the complete 403,456-byte fixed catalog/collection body. The body holds all 128
catalog slots followed by all 32 collection slots. Its header seals generation,
counts, mutation sequence, arena identity and committed content facts, body
CRC32, and body SHA3-256. A 448-byte VFS fixed-snapshot payload seals the chosen
bank, complete-bank SHA3-256, the same catalog/content facts, and all format
geometry. The payload generation and selected bank generation must equal the
outer snapshot generation.

Arena, bank, and head headers have canonical zero tails. They verify CRC before
format dispatch, so intact future evidence is reported as unsupported while a
damaged future header remains a checksum failure. Caller-owned decoded facts
are written only after full validation, aliases with codec-private state are
rejected, and head-to-bank/head-to-arena comparisons require every duplicated
generation, catalog, mutation, arena, tail, count, and chain fact to agree.

The content commitment starts at
`SHA3-256("org.akashic.library.content-chain.genesis.v1")`. Each step commits the
prior chain, absolute arena offset, sector span, and SHA3-256 of the complete
padded frame under the separate
`org.akashic.library.content-chain.step.v1` domain. Absolute offsets and spans
are bounded, sector aligned, and encoded as native little-endian 64-bit cells.

There is no earlier Library store or Library on-disk state to migrate. These V1
shapes are new and intentionally do not decode or wrap the old taxonomy/vault
prototypes, Streams draft bytes, or another owner's files. No existing durable
format or path changes in this landing; future Library formats remain explicit
unsupported evidence until a separately qualified migration exists.

## Sealed VFS loading and first-use boundary

`vfs-store.f` privately owns `/library/head.bin`, the two complete catalog
banks, and the fixed content arena. Callers cannot select or discover a path.
The fixed-snapshot head is the sole commit point: loading hashes the complete
selected bank before dispatching its format, validates the selected bank body,
immutable arena header, committed content-frame prefix, ordered chain, catalog
and collection constraints, and catalog-to-content relations, and publishes
caller-visible facts only after the whole candidate and resource cleanup pass.
An inactive bank and bytes beyond the committed content tail are not adopted.

Catalog-to-content validation requires each live current revision to resolve to
the same RID, kind, media, revision, length, and digest; retained historical
frames must remain inside the sealed window. Every frame for one RID is ordered
strictly by content and domain revision. If the immutable receipt's initial
revision is retained, its media, length, and digest must match that frame even
after later content becomes current. These checks belong here because the same
entry legitimately has both current and retained historical records.

On an entirely absent store, provisioning creates exactly the two fixed banks
and content arena, cold-verifies their geometry and initial evidence, writes
the empty generation-one bank header only after its body is ready, and commits
the head last. A retry with the same arena identity performs no write; a
different identity conflicts. A bank written without its head is preserved as
recovery evidence and is never silently resumed or adopted.

## Public headless owner surface

Managed create and capture import accept caller operation keys and an expected
catalog generation. Library generates a globally disjoint RID, retains the
immutable receipt, and resolves a same-key/same-request retry to the original
RID even after later publication. A changed request under that key is an
idempotency mismatch, while a new operation key that equals any existing RID is
a conflict. Crossed identity/key collisions are also rejected by the pure model
and cold loader even when every containing record is otherwise resealed. Two
identical captures deliberately imported with two keys receive distinct Library
RIDs. VFS capture origins are copied exactly and qualified against
`SHA3-256("org.akashic.library.vfs-snapshot.v1")`; the implemented semantic
origin branch remains the closed exact-qualified-locator variant defined by the
model.

Managed replacement accepts only the exact current domain revision and appends
one immutable content frame. The logical window retains the current content
revision plus its three predecessors. History summaries expose both the exact
content-frame domain revision and the independent content revision; reads,
compare, and restore address the former. Metadata and lifecycle changes advance
the domain revision without inventing content frames. A frame below the logical
window is `GONE`, never silently redirected to current, and restore writes the
selected retained bytes as a new current revision.

Archive preserves the RID, receipt, retained content, provenance, and exact
reads. Destructive tombstone is separately named, terminal, clears content and
sensitive descriptive state, preserves minimal identity/deletion/receipt
evidence, and never permits the original operation key to allocate a replacement
RID. Collection persistence remains a private catalog-slot bitmap, while every
public request and view uses stable member RIDs. Collection removal never
deletes a resource, and resource lifecycle changes do not rewrite independent
collection membership.

All mutations reuse the same ordered commitment: content first when present,
then a complete inactive bank, full readback, and the sole head replacement.
Bank-only metadata/lifecycle/collection changes still rebuild and verify the
complete inactive bank. Public outputs are caller-owned and remain unpublished
until argument validation, durable reconciliation, and cleanup complete. No
public API exposes a Library-private VFS path or persistent catalog slot.

Every successful authoritative load rebuilds one activation-local per-slot
title/body/tag candidate index while the selected bank and current content
frames are already being validated. Its fixed candidate allocation is 57,344
bytes for the 128-slot catalog bound. The index adds no path, sidecar, persisted
field, or store-descriptor state. It is generation/store bound and checksummed,
and is published only after the complete corpus passes. Missing or damaged
index state is therefore reconstructed on the next guarded refresh; a failed
load returns its explicit status and never turns authoritative records into an
empty result set.

`LIBRARY-VFS-STORE-QUERY-CORPUS` returns at most 32 caller-owned summaries in
canonical catalog-slot order. Empty term is a bounded browse. Nonempty terms
are exact case-sensitive UTF-8 bytes: title and current-body fields use
substring matching, tags use whole-value equality, and selected fields are ORed
without duplicating an entry. Active/archived, managed/capture, admitted media,
and exact collection-RID filters are authoritative facts rather than index
answers; tombstones are never discoverable. Raw slot continuation is pinned to
the returned catalog generation. `LIBRARY-VFS-STORE-QUERY-COLLECTIONS` provides
the corresponding bounded generation-stable collection enumeration. No ASCII
or Unicode case folding/normalization, semantic ranking, OCR, embeddings, or
automatic summaries are implied.
Callers reuse the identical term and filter scope when advancing a returned raw
slot cursor; changing scope starts a new request at slot zero.

The focused emulator profiles are `library-managed-document-contracts`,
`library-managed-capacity-contracts`, `library-managed-lifecycle-contracts`, and
`library-capture-collection-contracts`, plus
`library-query-index-contracts`. Separate spawn-isolated two-process drivers
prove the milestone-two lifecycle state and the milestone-three index rebuild
across real cold reloads:

```bash
python3 local_testing/library_lifecycle_two_boot.py --timeout 600
python3 local_testing/library_query_two_boot.py --timeout 600
```

## Remaining Gate 4 boundary

The next ordered milestone is projection acquire/share/reference-count/
quiescent-release. Recognized-format repair/raw export and the complete Gate 4
damage and exit matrix remain later milestones. No caller should infer a
capability, projection owner, or UI route from the current records or query
surface.
For the broader product boundary and gate handoff, see
[`../../docs/library/library.md`](../../docs/library/library.md). It is the
ratified product-boundary document.
