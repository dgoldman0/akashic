# Library product boundary

Status: Gate 4A is complete for the pure bounded model and deterministic record
codecs. The first Gate 4B landing also seals the pure arena, catalog-bank, head,
and ordered content-chain formats. Library still has no qualified durable VFS
owner, path lifecycle, publication/recovery procedure, index, capability,
projection owner, applet, UI, or sibling integration. Those absences are
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

Desk may later host Library services and route intents, and the Library applet
may show Library records, but hosting and presentation do not transfer domain
ownership.

## Gate 4A foundation now sealed

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
| simultaneous projections (future owner) | 8 |

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
commit decision. The future owner must look up an operation key first: a sealed
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

## Gate 4B pure storage format now sealed

`akashic/library/store-format.f` remains VFS-free. It defines three bounded V1
shapes for the future serialized owner:

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

## Remaining Gate 4B VFS-owner handoff

The pure formats intentionally do not choose VFS paths, perform allocation or
I/O, publish a new head, select recovery evidence, or define an index layout.
The remaining Gate 4B owner must seal and qualify those choices.

The store must also validate the catalog-to-content relation. A live catalog
entry's current revision must resolve to content with the same RID, kind,
media, content revision, length, and digest; the content record's domain
revision must also be admissible in the store's publication history. Older
content records may remain valid only when they are one of that entry's
retained historical revisions. The isolated model cannot decide that relation:
a content record with the same RID is correct or stale depending on the catalog
generation and whether it is current or retained. This check therefore belongs
with the atomic catalog/content publication and recovery logic rather than in a
new persisted Gate 4A field.

Indexes remain derived and rebuildable. They cannot become authority for
identity, content, membership, provenance, or lifecycle.

## Owner and lens rule

Only active/open records should later receive bounded one-RID Library
projection owners. Acquisition is through the Library domain root, keyed by a
stable RID rather than current UI selection. The root must validate the exact
requested domain state and return a semantic reference plus an activation-local
lifetime token. A client attaches an activation-local `LBIND`; failed
attachment rolls the token back, and quiescent release is idempotent. Registry
presence is not authority and cannot bypass owner retain accounting.

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

The domain package is `akashic/library/`. Model, record codecs, future
catalog/content stores, index, import semantics, and concrete projection owner
remain Library code. The reserved applet package is
`akashic/tui/applets/library/`; it is a Library lens, not the owner. Portable
mechanics move to `interop/` or `utils/fs/` only after two materially independent
owners prove the same contract.

The existing `akashic/knowledge/taxonomy.f` and `akashic/store/vault.f` are not
Library foundations. Neither supplies this bounded durable owner, revision,
recovery, identity, or projection contract.

The remaining order is:

1. Complete Gate 4B by qualifying private VFS paths, atomic publication,
   retained content, recovery, and idempotent mutation behavior over the sealed
   pure formats.
2. The later Gate 4 owner/index work qualifies lifecycle mutation, index
   rebuild, exact revision resolution, and bounded projections.
3. Gate 5 makes the standalone Library applet useful.
4. Gate 6 connects Pad, Explorer, and Desk through typed interop without
   sibling imports.
5. Gate 8 performs explicit observation collection and any separately approved
   migration only after Library is proven.

Until each boundary lands, no component may infer its VFS paths, register a
Library capability, route to a selected row, or treat these pure codecs as a
durable owner.
