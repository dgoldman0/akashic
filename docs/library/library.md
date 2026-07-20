# Library product boundary

Status: the pure bounded model/codecs, deterministic arena/catalog/head formats,
sole VFS owner, and the first four ordered Gate 4 headless milestones are
implemented and qualified. Library now owns managed-document and capture
mutation, retained history, receipts, lifecycle, collections, a disposable
title/body/tag index, bounded authoritative corpus/collection queries, and an
activation-local projection-owner lifecycle. A bounded standalone applet now
exercises the public storage surface as a user-facing corpus lens: it can browse
and search active/archived records, preview exact content, create and rename
managed documents, archive/unarchive, inspect retained history, browse/filter
collections, and page results. It does not provide Desktop hosting, sibling
integration, deep Pad editing, capture import, destructive deletion,
recognized-format repair, or opaque raw export. The overall Gate 4 exit and
complete Gate 5 experience are not yet claimed; those remaining absences are
contract boundaries, not implied behavior.

Library is the machine-level corpus of material a user deliberately keeps. A
Practice may eventually bind Library resources into an activity, but the corpus
and its records remain Library-owned. Library is useful on its own and does not
depend on Streams, Desk, Pad, Agent, Daybook, Grid, or a Practice being active.

## Ownership boundary

Library owns:

- stable Library identities for managed documents and immutable captures;
- copied content, exact managed-document revisions, content identity, and
  explicit provenance and bounded typed lineage;
- titles, admitted media type, tags, collections, archive state, tombstones,
  and the distinction between archiving, collection removal, and destructive
  deletion;
- authoritative catalog/content records and disposable rebuildable
  title/body/tag indexes; and
- bounded corpus query and projection-acquisition policy.

Library does not own:

- network acquisition, provider parsing, source configuration, credentials, or
  refresh state;
- Pad editing mechanics, Grid calculation, Explorer file navigation, Daybook
  time semantics, Agent conversations, or Practice authority;
- every file, observation, transcript, or note automatically; or
- a rule engine, workflow/outbound ledger, OCR/PDF pipeline, vector database,
  synchronization service, collaboration server, or universal
  citation/claim/backlink graph.

Desk may later host Library services and route intents. The current standalone
Library applet shows Library records through the public headless owner surface,
but presentation does not transfer domain ownership and does not establish a
Desktop route or capability.

## Bounded Library foundation

`akashic/library/model.f` defines pointer-free catalog, provenance, receipt,
lineage, and collection payloads. Its only borrowed pointer is the data address
in the transient content view. `akashic/library/record-codec.f` defines pure
caller-buffer V1 encoders, decoders, and validators. Neither module calls VFS,
publishes a resource, selects a store path, or imports a sibling domain or UI.

The initial limits are:

| Contract | Bound |
| --- | ---: |
| catalog entries | 128 |
| collections | 32 |
| members per collection | 128 |
| tags per entry | 16 |
| lineage locators per entry | 4 |
| UTF-8 content bytes | 65,536 |
| retained managed-document revisions | 4 |
| query page | 32 |
| simultaneous live RID projection owners | 8 |
| activation-local projection leases | 64 |

The fixed ABI widths are 328 bytes for an origin, receipt, or lineage slot;
2,832 bytes for a catalog payload inside a 3,072-byte record; and 224 bytes for
a collection payload inside a 320-byte record. The transient content view is
128 bytes. Its 160-byte record header plus at most 65,536 content bytes yields
a 65,696-byte maximum record. All 128 catalog and 32 collection records occupy
at most 403,456 bytes before any later store framing.

Canonical validation includes the following guardrails:

- bounded valid UTF-8 with zero-filled unused capacity;
- strict bytewise sorted, unique tags and exact direct qualified lineage
  locators;
- canonical collection bitmaps and membership only in allocated catalog slots;
- unique catalog RIDs and operation keys, unique collection RIDs and operation
  keys, and global disjointness between the two sets;
- a byte-exact immutable import/create receipt retained through archive and
  tombstone states;
- active-only revision-one entries, immutable capture content, frozen media,
  managed-content non-rollback, and no same-revision length/digest
  substitution; and
- strict domain-revision and mutation-sequence advancement for every persisted
  change, with tombstones terminal and byte-identical in all successors.

The receipt's request seal is domain separated. It covers method, initial
content facts, kind, title, tags, origin, lineage, import contract, source owner,
and expected catalog generation. The operation key is compared separately. The
seal excludes Library-generated RID, operation counters, and clocks.
Collection create seals similarly cover the initial title, bitmap/count, and
expected catalog generation while excluding the owner-generated RID and
counters. Therefore an owner can distinguish a true same-key replay from a
same-key/different-request conflict after later metadata changes or deletion.

The expected catalog generation is a caller precondition, not a persisted
commit decision. The owner must look up an operation key first: a sealed
matching prior request is a replay even if the catalog has since advanced; only
an unseen key is checked against the requested generation.

## Initial identity and content classes

The first bounded Library has two closed content classes:

1. A **managed document** has a Library-generated RID and mutable current
   content. Every successful exact replacement creates an immutable content
   revision. The initial policy retains the current revision and three
   immediately preceding revisions.
2. A **capture** has a Library-generated RID and one immutable copied content
   revision. It records the exact admitted origin facts available at import. A
   reference to changing external content without copied bytes is not a safely
   retained capture.

The initial admitted content is bounded valid UTF-8: plain text, Markdown, CSV
captures, and safe observation projections whose projection contract and digest
have already been qualified. Binary data, PDF, OCR, live/follow-latest links,
and automatic ingestion are outside this first contract.

A Library RID is never copied from an origin. Domain revision, content
revision, store generation, content digest, source/observation identity, and
activation epoch remain distinct facts. Create and import use a caller
operation idempotency key; equal content does not imply equal operation or
identity.

## Provenance and lifecycle

An imported record retains either a bounded exact qualified semantic origin or
an exact VFS snapshot locator, along with the admitted origin revision/digest,
source owner, locator digest, projection/import contract, and import method. It
never persists an activation-local `LBIND`, acquisition token, live grant,
component pointer, or handler choice. Provenance records where copied bytes came
from; it does not assert their trustworthiness.

Ordinary VFS import policy is the source owner `vfs` plus
`SHA3-256("org.akashic.library.vfs-snapshot.v1")`. The pure model also permits a
different present contract digest so a later owner can admit an explicitly
reviewed migration. The model's structural acceptance is not migration
authority.

Archiving preserves RID, retained content, provenance, and exact-revision
resolution while hiding the record from normal active views. Removing a record
from a collection changes membership only. Separately confirmed destructive
deletion tombstones the RID permanently: content and mutable descriptive facts
are erased, the RID and receipt remain, and later resolution reports a broken
reference rather than manufacturing empty or current content. A pruned
historical revision likewise reports `gone`/`retired`; it never falls forward
to latest.

## Record codec and borrowed views

Catalog and collection records use a 64-byte fixed envelope and canonical zero
padding. Content records are exactly eight-byte aligned. Validation covers
magic, header CRC, V1 format, declared and actual lengths, flags, payload CRC,
zero padding, and the complete model. Content records additionally bind the
payload with SHA3-256 and require valid UTF-8. A checksummed future format is
reported as unsupported; a damaged header is never trusted for dispatch.

`LIB-CONTENT-RECORD-DECODE` places a borrowed pointer to payload bytes in
`LIBCT.DATA-A`. The caller must keep the encoded record buffer alive and
unchanged for the lifetime of that view. `LIB-CONTENT-RECORD-MEASURE` validates
a complete header and returns the exact bounded record size, but it is not a
payload-integrity check. Encode/decode aliases are rejected without modifying
the aliased bytes; an invalid non-aliased decode destination is deterministically
zeroed.

## Pure storage format

`akashic/library/store-format.f` remains VFS-free. It defines three bounded V1
shapes for the serialized owner:

- a 655,360-byte immutable content arena with a 512-byte header and 654,848
  bytes of append-only, sector-framed content;
- two possible 403,968-byte complete catalog banks, each with a 512-byte header
  and the full 403,456-byte catalog/collection body; and
- a 448-byte VFS fixed-snapshot payload that names exactly one verified bank
  and repeats the selected generation, catalog, arena, tail, count, and content
  chain facts.

The bank header seals its complete body with CRC32 and SHA3-256. The head seals
the complete selected bank with SHA3-256 and must agree with its decoded bank
and immutable arena facts. Arena, bank, and head headers check CRC before future
format dispatch, require their geometry and unused bytes to be canonical, and
refuse aliased or hostile caller spans without partial decoded output.

Content publication is ordered independently of file layout. The genesis and
step hashes use distinct `org.akashic.library.content-chain.*.v1` domains. Each
step binds the previous chain, absolute arena byte offset, sector span, and the
SHA3-256 digest of the complete padded record frame. Thus a chosen head can
seal one exact committed prefix without silently adopting an orphan suffix.

This is a new V1 format for a domain with no prior Library store or Library
bytes to migrate. It does not reinterpret or retain compatibility wrappers for
the taxonomy/vault prototypes, Streams draft, or another owner's durable state.
No existing format/path, ownership, authority, content class, retention bound,
or legacy surface changes here, so this landing trips none of the contract's
mandatory return-to-user triggers.

## VFS loading and provisioning

`akashic/library/vfs-store.f` is the sole owner of the private
`/library/head.bin`, two complete catalog banks, and fixed content arena. It
exposes no path accessor. The owner inspects `/library` and each reserved
terminal name without following a symbolic link; namespace/type collisions
fail closed rather than redirecting authority. The fixed-snapshot head is the
only commit point; neither the inactive bank nor content bytes beyond the
committed tail are selected by discovery.

Loading keeps all decoded facts private until it has recovered and validated
the head, hashed the complete selected bank before format dispatch, checked the
bank body and immutable arena, scanned the exact committed content prefix and
ordered chain, and closed every FD/hash/CRC/CWD/VFS-selector resource. Only
then are the head, bank, arena, and generation facts published. Any corrupt,
checksummed-future, catalog/content-mismatched, or interrupted evidence clears
those public facts and fails closed.

A live catalog entry's current revision must resolve to content with the same
RID, kind, media, revision, length, and digest, and every revision inside its
logical retained window must be present. Older append-only frames may remain as
non-resolvable pruned or tombstoned evidence, but are not treated as retained;
each RID's content and domain revisions must still increase strictly across the
whole committed prefix. Whenever the immutable receipt's initial revision is
present there, its media, length, and digest must match that frame. The isolated
model cannot decide these relations because a content record with the same RID
can be current, retained, pruned, or tombstoned under the selected publication.

For an entirely absent corpus, provisioning creates exactly the two bounded
banks and arena, performs cold readback, writes the empty generation-one active
bank header after its body, and publishes the head last. Same-arena retries are
write-free and idempotent; a different arena conflicts. Exact post-bank,
pre-head evidence is preserved and reported as recovery instead of being
silently adopted.

## Headless owner and disposable queries

The VFS owner exposes guarded create/import, exact read and replacement,
metadata and lifecycle mutation, retained-history read/compare/restore, receipt
lookup, and RID-based collection create/replace/read operations. Content writes
precede complete inactive-bank construction and readback; only the fixed head
replacement publishes a mutation. Caller operation keys, exact expected
catalog/domain/collection revisions, capacity preflight, uncertain-head
reconciliation, and terminal tombstones preserve retry and conflict semantics
without substituting a content digest for operation or resource identity.

`LIBRARY-VFS-STORE-READ-IDENTITY ( rid entry store -- status )` performs one
authoritative RID lookup without query/index discovery or reconstruction. It
returns active or archived metadata with `OK`, returns terminal metadata with
`TOMBSTONED`, and reports an unknown RID as `NOT_FOUND`. After safe arguments
are admitted, every nonterminal failure clears output; `TOMBSTONED` instead
returns the terminal entry. Alias rejection is nonmutating. This store-level
archived metadata read is separate from projection identity acquisition, which
admits active current state only.

The third milestone adds no durable format or fifth path. During each complete
authoritative load, Library derives fixed per-catalog-slot candidate bitsets
from live/archived titles and tags plus each live/archived current content
frame. The 128-slot bound consumes a fixed 57,344-byte candidate allocation.
The activation-local index is bound to the selected store and generation,
checksummed, and published only after the complete bank/arena/content candidate
passes. Loss or damage is reconstructed by the next guarded refresh. An
authoritative load failure remains an explicit error; it cannot manufacture an
empty corpus or change identity, content, membership, provenance, lifecycle,
receipt, generation, or mutation facts.

`LIBRARY-VFS-STORE-QUERY-CORPUS` serves caller-owned pages of at most 32
summaries in canonical catalog-slot order, with generation-pinned raw-slot
continuation. Empty term is bounded browse. Nonempty terms are exact
case-sensitive UTF-8 bytes: title/current-body use substring matching, tags use
whole-value equality, and selected fields are ORed with one result per RID.
Active/archived, managed/capture, media, and exact collection-RID filters are
checked against authoritative facts; tombstones are excluded. Collection
enumeration is separately bounded and generation stable. ASCII/Unicode folding,
normalization, semantic ranking, embeddings, OCR, and automatic summaries stay
outside this milestone. A continuation reuses the same term/filter scope and
copies back both returned generation and raw slot; changing scope starts at
slot zero.

## Projection owner and lens rule

`akashic/library/projection-owner.f` implements the Library domain acquisition
root `LIBRARY-PROJECTION-OWNER$` (`org.akashic.library`). Its fixed-RID
resource projections use `LIBRARY-PROJECTION-CONTRACT$`
(`org.akashic.library.utf8-content.v1`). The activation can publish at most
eight distinct live RID owners and can track at most 64 activation-local
leases. Same-RID acquisitions share one fixed component instance but return
distinct validated lifetime tokens alongside their semantic resource
references.

Every acquisition passes through the root even if the RID is already present
in the resource registry. The root validates the exact requested RID/domain
state through its explicitly supplied VFS-store instance; it never consults
`VFS-CUR`, UI selection, history position, or another ambient store selector.

`LIBRARY-PROJECTION-ROOT-INIT ( store context creg rreg bus root -- status )`
borrows that complete runtime graph, including the request bus, until
successful root finalization. Its embedded RACQ header is only the portable
callback/token ABI. Generic `RACQ-ATTACH` cannot validate the full 4,072-byte
root and reachable borrows, so `LIBRARY-PROJECTION-ATTACH ( locator root
context rreg binding result -- status )` is the only supported attachment
entry. Binding and result must be distinct caller-owned buffers disjoint from
all inputs and protected owner state.

Managed-document descriptors expose describe, exact-locator snapshot, and
current-exact replace; immutable-capture descriptors omit replace. Identity
acquisition means active current state. Archived identity is unavailable, but
a qualified exact archived locator stays readable and immutable; tombstoned
and pruned states retain distinct terminal outcomes. Failed `LBIND` attachment
rolls back the new lease.

Tokens are activation-local, non-authoritative outside the private owner
ledger, and never persistent. Public release is idempotent: it waits for
request-dispatch quiescence, decrements accounting exactly once, preserves the
original token and binding after a retryable cleanup failure, and unpublishes
and wipes the slot only after successful final release. At capacity,
acquisition refuses another distinct RID instead of evicting or retargeting an
owner. Registry presence is not authority and cannot bypass retain accounting.

Pad is the deep-editing lens for managed documents and a read-only lens for
captures. Library remains the semantic owner. Explorer may reveal an admitted
physical origin and Desk may route a qualified locator, but neither receives
Library ownership or authority by discovery. A Practice binding makes a
resource relevant and nameable; it neither copies the record nor grants read,
replace, archive, or deletion.

Consequential operations name an exact Library target and expected domain
state. They never mean the selected Library row, active Pad tab, focused
applet, or newest revision.

## Current package and gate order

The domain package is `akashic/library/`. Model, record codecs, the
catalog/content owner, disposable index, import semantics, and concrete
projection owner remain Library code. The implemented standalone applet package
is `akashic/tui/applets/library/`; it is a bounded Library lens over the public
owner API, not the owner, a projection owner, or a Desktop registration.
Portable mechanics move to `interop/` or `utils/fs/` only after two materially
independent owners prove the same contract.

The existing `akashic/knowledge/taxonomy.f` and `akashic/store/vault.f` are not
Library foundations. Neither supplies this bounded durable owner, revision,
recovery, identity, or projection contract.

The remaining order is:

1. Qualify recognized-format repair/raw export and the complete Gate 4 damage
   and exit matrix without weakening the sealed authoritative/query boundary.
2. Gate 5 expands and qualifies the present bounded standalone Library lens
   into the complete applet experience without transferring domain ownership.
3. Gate 6 connects Pad, Explorer, and Desk through typed interop without
   sibling imports.
4. Gate 8 performs explicit observation collection and any separately approved
   migration only after Library is proven.

Until each boundary lands, no component may infer its VFS paths, register a
Library capability, route to a selected row, or treat these pure codecs as a
durable owner.
