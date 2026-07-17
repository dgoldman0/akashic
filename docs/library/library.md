# Library product boundary

Status: Gate 1 product contract and package placeholder. Library has no runtime
module, store, capability, projection owner, applet, or UI yet. The names and
limits below describe the ratified direction; later focused gates must seal
formats, schemas, lifecycle behavior, and measured bounds before code relies on
them.

Library is the machine-level corpus of material a user deliberately keeps. A
Practice may bind Library resources into an activity, but the corpus and its
records remain Library-owned. Library is useful on its own and does not depend
on Streams, Desk, Pad, Agent, Daybook, Grid, or a Practice being active.

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

## Initial identity and content classes

The first bounded Library has two closed content classes:

1. A **managed document** has a Library-generated RID and mutable current
   content. Every successful exact replacement creates an immutable content
   revision. The initial policy retains the current revision and three
   immediately preceding revisions.
2. A **capture** has a Library-generated RID and one immutable copied content
   revision. It records the exact admitted origin facts available at import.
   A reference to changing external content without copied bytes is not a
   safely retained capture.

The initial admitted content is bounded valid UTF-8: plain text, Markdown,
CSV captures, and safe observation projections whose projection contract and
digest have already been qualified. Binary data, PDF, OCR, live/follow-latest
links, and automatic ingestion are outside this first contract.

A Library RID is never copied from an origin. Domain revision, component
revision, store generation, content digest, source/observation identity, and
activation epoch remain distinct facts. Create and import use a caller
operation idempotency key; equal content does not imply equal operation or
identity.

## Provenance and lifecycle

An imported record retains a bounded qualified semantic origin or VFS snapshot
fact, exact origin revision and digests when available, media/projection facts,
and import method. It never persists an activation-local `LBIND`, acquisition
token, live grant, component pointer, or handler choice. Provenance records
where bytes came from; it does not assert their trustworthiness.

Archiving preserves the RID, retained content, provenance, and exact-revision
resolution while hiding the record from normal active views. Removing a
record from a collection changes membership only. Separately confirmed
destructive deletion tombstones the RID permanently: the RID is not reused,
content is no longer returned, and later resolution reports the broken
reference rather than manufacturing an empty or current replacement. A
pruned historical revision similarly reports `gone`/`retired`; it never falls
forward to latest.

## Owner and lens rule

Only active/open records should later receive bounded one-RID Library
projection owners. Acquisition is through the Library domain root, keyed by a
stable RID rather than current UI selection. The root must validate the exact
requested domain state and return a semantic reference plus an
activation-local lifetime token. A client attaches an activation-local
`LBIND`; failed attachment rolls the token back, and quiescent release is
idempotent. Registry presence is not authority and cannot bypass owner retain
accounting. The initial proposed pool bound is eight live projections, subject
to focused qualification rather than Gate 1 implementation.

Pad is the deep-editing lens for managed documents and a read-only lens for
captures. Library remains the semantic owner. Explorer may reveal an admitted
physical origin and Desk may route a qualified locator, but neither receives
Library ownership or authority by discovery. A Practice binding makes a
resource relevant and nameable; it neither copies the record nor grants read,
replace, archive, or deletion.

Consequential operations name an exact Library target and expected domain
state. They never mean the selected Library row, active Pad tab, focused
applet, or newest revision. Create/import instead names the catalog
precondition and operation key defined by its future sealed schema.

## Intended package boundary

The reserved domain package is `akashic/library/`. Its eventual model,
catalog/content stores, index, import semantics, and concrete projection
adapter remain Library code. The reserved applet package is
`akashic/tui/applets/library/`; it is a Library lens, not the owner module.
Portable mechanics move to `interop/` or `utils/fs/` only after two materially
independent owners prove the same contract.

The existing `akashic/knowledge/taxonomy.f` and `akashic/store/vault.f` are not
Library foundations. Neither provides this bounded durable owner, revision,
recovery, identity, or projection contract.

## Current boundary and gate order

Gate 1 adds only these documents and placeholder directories. It deliberately
adds no `.f`, `.uidl`, manifest, VFS path, record format, stable capability ID,
handler registration, resource publication, or Library UI.

The later order is:

1. Gate 3 seals durable locator, live-binding, service, and handler contracts.
2. Gate 4 qualifies the headless Library owner, stores, revisions, recovery,
   archive/tombstone behavior, index rebuild, and projection lifecycle.
3. Gate 5 makes the standalone Library applet useful.
4. Gate 6 connects Pad, Explorer, and Desk through typed interop without
   sibling imports.
5. Gate 8 performs explicit observation collection and the separately
   approved Streams-draft migration only after Library is proven.

Until those gates land, no current component may depend on or route to a
Library implementation.
