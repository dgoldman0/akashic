# Streams

Streams is moving from a Bluesky-shaped reader toward the Desk ecosystem's
bounded information-integration applet. Its first end-to-end configured-source
slice can now manually refresh one exact enabled RSS, Atom, or JSON Feed source
revision through Desk external I/O, retain immutable observation versions in a
replacement store, suppress exact unchanged versions, and recover an
interrupted accepted attempt truthfully. The durable multi-kind source
registry, sanitized source resources, watched-page codecs, existing retained
Bluesky page, partial-thread navigation, local search, and crash-recoverable
unpublished draft remain alongside that path. The Bluesky surface is retained
compatibility, and the draft is frozen legacy-to-migrate input; neither defines
the configured-source product.

Ordinary `STREAMS-ENTRY` remains offline even when Desk exposes external I/O:
it installs no concrete configured-source provider factory, and source
recovery or Observe calls never start network work. `streams-online.f` is the
explicit composition edge; a live configured-source deployment must inject a
factory constructed with its reviewed full-source and canonical-host
authorization policy. The default factory denies every source. Trusted boot
may separately import a reviewed exact-host MPTA artifact before freezing
machine trust; source creation, applet launch, and refresh cannot add or widen
trust. The repository ships neither a catch-all feed trust set nor an ambient
WebPKI fallback. Credentials, scheduling, notification providers, outputs, and
publication are not supported. The complete target boundary and deliberately
unimplemented portions are recorded in
[information-integration.md](information-integration.md).

Normal launches start with no feed and recover the draft stored by the
preceding launch. The host qualification harness alone injects a hand-authored
synthetic page under `/testing/streams/`; `timeline.json` is test input, not a
runtime fallback or library data source.

The five `streams.draft.*` capabilities and `/streams-draft.bin` remain
behavior-compatible only for recovery and later explicit migration. New code
must not build output documents, saved sets, Library access, or generic text
storage on that surface. The exact Gate 0 revision-7 record is retained as
migration input; Library must not read the path or codec.

Streams is a peer applet, not an inter-applet coordinator. Desk hosts target
discovery, capability dispatch, review composition, and applet lifecycle.
Practice retains durable contextual bindings and authority policy; Streams
still validates and owns each operation over its state. This shared boundary
does not make Streams a special workflow substrate.

## Capability surface

Every capability has a distinct bounded input and output schema. Map schemas
are closed, every declared field is required, retained-feed lists are capped
at eight items, and configured-source lists are capped at sixteen identities.
Outputs are owned `CV` graphs rather than newline or field-delimited strings,
so external text cannot be interpreted as protocol structure.

| Capability | Input | Output | Effect |
| --- | --- | --- | --- |
| `streams.selection.current` | `null` | `null \| resource` | Observe |
| `streams.item.read` | item `resource` | item map | Observe |
| `streams.thread.read` | item `resource` | partial-context map with ordered resource list | Observe |
| `streams.feed.read` | `null` | feed-page map with ordered resource list | Observe |
| `streams.search.local` | string, at most 96 bytes | query map with ordered resource list | Observe |
| `streams.draft.create` | `{text}` | draft map | Mutate + Persist |
| `streams.draft.read` | draft `resource` | draft map | Observe |
| `streams.draft.replace` | `{resource, expected_revision, text}` | draft map | Mutate + Persist |
| `streams.draft.validate` | draft `resource` | validation map | Observe |
| `streams.draft.current` | `null` | `null \| resource` | Observe |
| `streams.feed.refresh` | actor string | `{actor, accepted, request_generation, state}` | External |
| `streams.source.query` | `null` | ordered source-resource list | Observe |
| `streams.source.read` | source `resource` | sanitized source map | Observe |
| `streams.source.set-enabled` | `{resource, enabled}` | sanitized source map | Mutate + Persist |
| `streams.source.refresh` | `{resource, expected_revision}` | `{resource, source_revision, accepted, request_generation, state}` | Persist + External |

The draft rows above describe current compatibility behavior, not the near
Streams capability target. They remain unchanged until the separately gated,
verified Library migration and cutover.

An item map contains `resource`, `provider`, `provenance`, `cid`, `author`,
`text`, `created_at`, `indexed_at`, `counts`, `reply`, and `reason`. `author`
and `counts` are nested maps. `reply` is either `null` or a map containing the
exact retained `root` and `parent` resources. Feed, thread, and search results
contain bounded ordered lists of item resources. Callers dereference only the
items they need through `streams.item.read`, which provides one canonical item
shape and avoids duplicating complete item graphs in aggregate results.

`streams.feed.refresh` acknowledges only that Desk accepted and serialized the
start. Its `request_generation` is also exposed by `streams.feed.read`; callers
observe that feed resource for `refreshing`, retained success, or retained
error state. An accepted start is not a claim that cooperative transport open,
HTTP, graceful connection close, decode, or model commit has completed.
Refresh returns `CBUS-S-NOT-FOUND` unless both an explicitly composed provider
and Desk external-I/O service are present.

`streams.source.refresh` accepts only an exact positive RREF whose revision
also equals `expected_revision` and the current enabled syndication source.
Its acknowledgement means that the exact source attempt was durably recorded
before submission to Desk XIO; it does not claim remote success. The request
generation identifies the serialized local operation. Later
`streams.source.read` calls report `accepted`, `succeeded`, `failed`,
`cancelled`, or `indeterminate` from the retained attempt head.

`streams.selection.current` returns a null value when there is no valid
selection; absence is not an error. Item, feed, and thread maps report
`provenance: "public.api.bsky.app"`, `"injected"`, or `"none"` according to
the retained source. Feed state is one of `refreshing`, `public-retained`,
`injected-retained`, `retained`, `retained-after-refresh-error`,
`retained-after-decode-error`, or `unavailable`. Old items remain readable
while a refresh is active. Thread reads report `complete: false` because one
retained author-feed page is not a complete conversation fetch. Feed reads
also expose the retained cursor and last accepted request generation. Local
search reports the scope `retained`.

## Configured sources

Normal lifecycle initialization binds `/streams-sources.bin` and recovers a
pointer-free registry of at most sixteen sources. A source has a stable local
RID, a positive domain revision, kind and format, exact UTF-8 label, endpoint
and provider configuration, enabled state, manual or bounded interval policy,
and explicit redirect, response, page, observation, and retained-revision
limits. The first implemented kinds are syndication, watched page,
notification, and the existing public-Bluesky adapter shape. The manual
acquisition slice supports only enabled syndication sources and deliberately
requires its implemented one-page, sixteen-observation, four-version policy;
other valid registry policies remain configuration-only until their retention
semantics are implemented.

HTTPS source configuration is not TLS provisioning. A live composition must
associate the complete reviewed source snapshot with its canonical host and
port independently of TLS trust; authorization is rechecked both during pure
configuration and at the physical bind. One supported trust route is an
exact-host MPTA artifact imported by trusted boot before Desk freezes machine
trust. The importer does not itself bind an artifact to a source RID or
revision. Imported run artifacts reject global and include-subdomains scopes,
and ordinary Streams never receives their CA bytes or the trust builder.

The owner API provides bounded count/read/create/replace/enable/remove methods.
Creation ignores caller-supplied identity and generates a nonzero 32-byte RID;
replacement, enable, and removal require the exact source revision. Mutations
copy live state to an instance-local candidate, apply one checked change,
persist expected generation `N` to `N+1`, and publish the candidate only after
the replacement store commits. Direct owner mutations advance the component
owner revision exactly once; a no-op enable does not.

Only a proven-absent source record authorizes a fresh generation-zero registry.
Valid state is loaded transactionally without advancing the component
revision. Corrupt or future-format data, I/O failure, and uncertain replacement
recovery preserve the evidence and block mutation instead of manufacturing an
empty registry. The physical path is one VFS singleton, so simultaneous live
Streams instances resolve competing writes as explicit optimistic conflicts;
they are not silently merged or reloaded.

`streams.source.query` returns only semantic RREFs. `streams.source.read`
returns the exact requested revision (or current revision when the RREF uses
revision zero) as a closed fourteen-field projection containing label, kind,
format, enabled state, refresh policy, and declared bounds. It deliberately
omits endpoint and provider-configuration bytes. Its acquisition state is
`never refreshed` when no attempt head exists and otherwise projects the
retained state of the latest exact-source attempt. `blocked` means the durable
observation record could not be admitted safely and no retained attempt or
observation is projected. `unavailable` means configured acquisition failed
before it could establish an owned observation checkpoint. Neither state is
reported as `never refreshed`.

`streams.source.set-enabled` takes an exact positive source revision and a
boolean. It persists and returns the same sanitized projection without
starting acquisition. A stale revision fails, and a request that already
matches the retained enabled state is rejected before request-bus commit so a
redundant Agent call cannot manufacture a component revision. This capability
is intentionally absent from Desk's ordinary Observe and assist facets; it is
available only to an explicitly constructed operator facet with a reviewed
grant for the exact target and operands. Source create, general replace, and
remove remain direct owner/UI operations in this slice.

`streams.source.refresh` is likewise absent from ordinary Observe and assist
facets. An explicit operator facet may grant the exact sealed source revision.
The handler persists `accepted` before XIO submission. A synchronously
terminal submission failure is still returned as an accepted local attempt so
the caller can observe its durable terminal outcome rather than mistake it for
an operation that never began.

The reusable syndication family preserves bounded format-specific JSON Feed
1/1.1, RSS 2.0, and Atom 1.0 models, then exposes a deliberately narrow shared
item projection. A separate reusable media-type parser validates syntax without
choosing policy, and a readable-text projector turns UTF-8 plain text or a
strict inert HTML subset into caller-owned text without a DOM or active-content
path.

Streams composes those latter boundaries into its V1 watched-page snapshot. Its
policy admits `text/plain` or `text/html`, case-insensitively, with either no
parameters or exactly one `charset=utf-8` parameter. Raw input is capped at
128 KiB, the media-type field at 1 KiB, and normalized text at 8 KiB. The
snapshot records raw and normalized SHA3-256 digests plus a model seal, and
commits only after parsing, projection, and hashing succeed. Actual watched-page
fixtures qualify meaningful-content equivalence, content changes, plain-text
changes, and malformed-input preservation. These are transactional codecs, not
yet wired acquisition providers or evidence that configured HTTP acquisition,
observation persistence, scheduling, notifications, outputs, or Outbox are
complete.

## Manual-refresh observation store

Normal lifecycle now owns an exactly 131,072-byte (128 KiB), pointer-free
observation checkpoint behind the optimistic replacement record
`/streams-observation.bin`. Ordinary offline Streams still loads and recovers
that state but cannot start external work. A configured online owner copies the
checkpoint, records `accepted`, saves it, and only then submits the operation
to Desk XIO. Terminal failure preserves prior observations. Successful decode
is applied to another checkpoint copy, lower transport cleanup must succeed,
and the replacement must commit before the new checkpoint is published.

The checkpoint retains one latest attempt head for each of sixteen exact
sources, forty-eight immutable observation versions with at most sixteen per
source and four per provider-native key, sixty-four exact-key heads, and one
owned aggregate string blob. A decoded batch contains at most eight
candidates. The latest attempt accounts for `new`, `revised`, `unchanged`, and
rejected candidates; there are no separate retained attempt-history or
sighting arrays in this first slice.

`BEGIN`, `TERMINAL`, and `APPLY` are transactional checkpoint operations.
`BEGIN` creates the active accepted head. `TERMINAL` closes a failed,
cancelled, stale, cleanup-failed, or indeterminate attempt without modifying
last-good observations. `APPLY` closes a successful attempt while updating
immutable versions and exact-key heads. On relaunch, a durably accepted head
with no terminal record is changed to `indeterminate` and saved before the
checkpoint is exposed.

Each deduplication head is keyed by the source RID, exact source-identity
namespace digest, provider kind, native-identity kind, and exact admitted
native-identity bytes. The source identity is therefore part of equality: the
checkpoint performs no cross-source deduplication. A changed value advances
the same stable observation RID to its next revision; an unchanged candidate
creates no version or duplicate body and only advances exact-key provenance.

Retention uses deterministic checkpoint sequence rather than provider
timestamps or wall-clock order. Each observation admits at most 8 KiB of
content, but all content shares the checkpoint's aggregate blob, so declared
per-record maxima are not promised simultaneously. If a semantically valid
success batch cannot fit, `APPLY` rejects the candidate and the owner records a
terminal capacity attempt while prior observations and exact-key heads remain
unchanged. Malformed input or a rejected `APPLY` transaction preserves the
entire current checkpoint.
Model seals and digests detect accidental corruption; they do not authenticate
a source, content, or acquisition result.

The durable source-store V1 format still has no metadata saying that an
observation companion was ever established. A missing observation record is
therefore treated as the legitimate never-refreshed state; Streams cannot yet
distinguish that case from external loss of a previously established companion
and makes no stronger pair-loss claim. A durable pair marker and migration are
required before that distinction can fail closed.

## Local drafts

This section is a compatibility record for the frozen legacy owner. The draft
is not the model for future Streams outputs or retained findings. Migration
must be non-destructive and idempotent, preserve the original record as
recovery evidence, and use a Streams-owned adapter plus ordinary typed Library
operations after Library is qualified. Gate 1 performs none of that migration.

The current target-scoped draft has the stable resource
`streams:draft:local` and the shape `{resource, revision, text}`. Creation is
rejected with `CBUS-S-BUSY` while that resource already exists. Replacement
requires the exact current draft revision and returns
`CBUS-S-STALE-REVISION` before changing state when it does not match. The
proposed result is fully allocated away from the caller's result, the next
revision is persisted, and only then are the in-memory draft and result graph
committed. Allocation or save failure therefore preserves the previous draft,
caller result, draft revision, and owner revision.
`streams.draft.current` returns this resource whenever the draft exists,
including drafts created from the applet UI, and returns null before creation.
The status-bar editor starts from the current text, commits through the same
bounded revision-safe mutation used by the capability handlers, accepts an
explicitly empty local draft, and wipes its input buffer on submit or cancel.
Cancel leaves the current draft and both revisions unchanged.

Normal app initialization binds the VFS singleton `/streams-draft.bin` and
resolves any interrupted VREPL replacement before accepting edits. A missing
record is an ordinary writable empty state. A complete record restores its
exact UTF-8 bytes and positive revision without advancing the component owner
revision. Corrupt or future-format records, I/O failure, and uncertain
recovery leave the reading and navigation surface available but visibly block
draft overwrites. Once a save fails, the applet likewise blocks later writes
until a fresh lifecycle can establish a safe store state. A zero-filled
component instance that has not run `STREAMS-INIT-CB` remains deliberately
volatile; that mode exists for direct component contracts and controlled
embedding, not for normal app launches.

Validation is local and non-publishing. Its result reports `local_valid`,
`byte_count`, `publishability: "unchecked"`, `external_effect: "none"`, and a
nullable `problem`. This draft revision is part of the Streams resource
contract; it is separate from the component revision used by Desk's request
bus for owner-level optimistic concurrency.

## Applet interaction

The `Sources` menu, `S`, or `Ctrl+S` opens the standalone source manager.
Users can add syndication feeds and watched pages using a conservative
printable-ASCII `https://` spelling, inspect label, kind, format, enabled
state, revision, endpoint, latest attempt counts, and latest retained title,
move an independent per-instance selection, and enable or disable the selected
exact revision. `R` and the `Refresh_Selected_Source` menu action submit the
same exact selected-source operation used by the typed capability. Creation
uses manual, bounded defaults and does not fetch by itself. Removal captures
the selected RID and revision before prompting and requires the exact text
`REMOVE`; a selection change or concurrent update cannot redirect the
confirmed action.
In this milestone `R` accepts only enabled syndication sources; watched pages
remain configurable but receive a precise unsupported-kind notice and no
refresh-owner mutation.
Storage corruption, unsupported formats, uncertain replacement recovery, and
I/O failure preserve the durable evidence but block source management and
source reads until an explicit recovery or fresh lifecycle proves safe state.
Opening Sources preserves the retained feed selection, open context, and draft.
Returning to Timeline intentionally closes that context while preserving the
feed selection and draft. Labels and endpoints are rendered as untrusted text.

Search and draft editing use the shared nonblocking prompt widget, so the applet
continues to route paint, resize, and close decisions through its ordinary
lifecycle. Local search trims its query, rejects values above 96 UTF-8 bytes,
records the bounded query and match count, selects the first author/text match,
and reports empty, unavailable, unmatched, and successful outcomes distinctly.
Arrow movement and successful searches keep the selected item visible through
a per-instance timeline top index, including compact terminal heights.
Opening Context copies the selected item's root identity into per-instance
state and keeps that anchor until the user returns to Timeline or a reload
removes every retained member. Up and Down then move only through feed-ordered
items with that root, skipping interleaved conversations. Context has its own
ordinal viewport, draws only complete three-row cards, and accounts for the
draft footer before deciding how many cards fit. A successful reload preserves
the selected resource when possible, otherwise selects the first surviving
member of the anchored context; it exits Context rather than displaying an
unrelated item when no member survives. `streams.thread.read` uses separate
capability scratch and never changes the open UI root, selection, or viewport.

Provider and user-controlled author, timestamp, post, resource, and draft text
all pass through the TUI's untrusted-text renderer. Newlines, controls,
nonspacing/joining codepoints, and width-2 glyphs are projected to one visible
replacement cell; they cannot move the physical terminal cursor outside the
logical field. Source UTF-8 remains unchanged, and clipping never truncates an
arbitrary byte sequence.

Successful feed loads advance the component owner revision. A failed reload
also advances it when a previously healthy retained feed becomes observably
`retained-after-decode-error`. Explicit refresh state transitions likewise
advance the owner revision. UI draft commits and changes to the selected resource
advance the owner revision exactly once; canceled prompts and clamped/no-op
movement do not. Capability draft handlers use the underlying mutation path
without touching the owner themselves because Desk's request bus performs that
commit for successful mutating calls.

## Integration boundary

Other applets can currently read explicit item, thread, feed, selection, draft,
and sanitized source resources through Desk's ordinary typed capability path.
The draft replacement and legacy public refresh paths are compatibility
surfaces, not contracts for new integrations. New consequential operations
must name the exact Streams target and expected domain state; current UI row or
selection may be observed but must not retarget an Agent-visible or scheduled
mutation. Desk owns discovery, dispatch, review composition, lifecycle, and
machine-serialized external I/O. Practice owns durable contextual bindings and
authority policy, while Streams validates and owns its operation semantics.
In an explicit configured composition, Streams owns provider admission, HTTP
policy, feed decode, observation deduplication, and durable
attempt/observation commit. A composed instance commits a completion only when
instance, source, owner, and request generations remain exact.

The external-I/O service is not itself a Streams capability, and Streams does
not coordinate unrelated applets. When a live Streams target exists, Desk's
curated Observe facet may expose only `streams.source.query` and
`streams.source.read`, with the normal 4 KiB result ceiling and exact target
generation. It grants neither endpoint/configuration disclosure nor source
mutation, refresh, staging, dispatch, or any external effect. Public reads
require no app password, and Streams accepts or stores no credential.
Authenticated AT Protocol operations and publication remain outside this
applet boundary.

The deterministic `streams-refresh-owner-contracts` gate covers durable
acceptance-before-XIO, decode/apply commit, exact deduplication, stale and
cancelled completion, cleanup quarantine, boot recovery, and releasable
offline/factory-failure ownership. `streams-manual-refresh-contracts` composes
the applet with Desk's real serialized XIO service and a deterministic
provider, then proves typed and UI initiation, exact source-revision
projection, failure retention, relaunch recovery, and offline applet teardown
without performing network work. `streams-syndication-http-contracts` seals
the exact configured source/host authorization boundary and bounded outbound
HTTP request, including the generic JSON Feed media spelling.

The optional `streams-configured-refresh-live` gate performs one successful
fetch of the bounded public `foo-dogsquared.github.io` More Contentful RSS
feed through reviewed exact-host trust, DNS, TCP,
authenticated TLS 1.3, bounded HTTP, decode, durable owner commit, cleanup,
and owner release/reinitialization durability. This live gate
is deliberately provider-to-owner; `streams-manual-refresh-contracts` owns the
separate Streams-online and Desk-XIO composition evidence. The live gate does
not require a second public fetch to remain unchanged; deterministic contracts
prove that case. The separate legacy `streams-live-public` journey continues
to qualify the public Bluesky component path. Neither live gate is evidence of
the still-pending Desk-hosted responsiveness/recovery journey.
The connector's complete live certificate/signature phases also lack a
measured per-poll CPU ceiling, and TLS-context cleanup is not yet proof that all
machine-global KDOS TLS/cryptographic scratch has been sanitized.
