# Streams

Streams is moving from a Bluesky-shaped reader toward the Desk ecosystem's
bounded information-integration applet. The first landed spine owns a durable
registry for several unlike source kinds, exposes sanitized source resources,
and supplies deterministic JSON Feed and watched-page codec contracts. The
existing retained Bluesky author-feed page, partial-thread navigation, local
search, and crash-recoverable unpublished draft remain available while that
new path is built alongside them; they are no longer the product definition.

Ordinary `STREAMS-ENTRY` remains offline even when Desk exposes external I/O:
it installs no concrete provider factory, and source recovery or Observe calls
never start network work. `bluesky-public.f` supplies the explicit legacy
Bluesky component/entry composition, while `public-trust.f` remains a separate
trusted boot contribution. Authentication and publication are not supported.
The complete target boundary and deliberately unimplemented portions are
recorded in [information-integration.md](information-integration.md).

Normal launches start with no feed and recover the draft stored by the
preceding launch. The host qualification harness alone injects a hand-authored
synthetic page under `/testing/streams/`; `timeline.json` is test input, not a
runtime fallback or library data source.

Streams is a peer applet, not an inter-applet coordinator. Desk remains the
owner of target discovery, capability dispatch, authority, and applet
lifecycle. Practices can record and govern calls made through that shared
boundary without making Streams a special workflow substrate. Streams only
exports operations over state it owns.

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
notification, and the existing public-Bluesky adapter shape. This registry is
configuration authority only: it does not yet claim that ordinary Streams can
refresh those configured sources or retain their observations.

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
omits endpoint and provider-configuration bytes and reports acquisition state
as `not-tracked` until the separate observation checkpoint exists.

`streams.source.set-enabled` takes an exact positive source revision and a
boolean. It persists and returns the same sanitized projection without
starting acquisition. A stale revision fails, and a request that already
matches the retained enabled state is rejected before request-bus commit so a
redundant Agent call cannot manufacture a component revision. This capability
is intentionally absent from Desk's ordinary Observe and assist facets; it is
available only to an explicitly constructed operator facet with a reviewed
grant for the exact target and operands. Source create, general replace, and
remove remain direct owner/UI operations in this slice.

The first provider-family codec preserves JSON Feed 1/1.1 publication, entry,
author, tag, attachment, time, URL, text, and HTML fields in a bounded owned
model. A separate page snapshot normalizer admits only exact `text/plain` and
`text/html`, executes no script, removes structural chrome, bounds raw input at
128 KiB and normalized text at 8 KiB, and records raw and normalized SHA3-256
digests. Both are transactional fixture-qualified adapters, not yet wired
acquisition providers or evidence that RSS/Atom, HTTP admission, observation
persistence, scheduling, notifications, outputs, or Outbox are complete.

## Local drafts

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
state, revision, and endpoint, move an independent per-instance selection,
and enable or disable the selected exact revision. Creation uses manual,
bounded defaults and explicitly does not fetch. Removal captures the selected
RID and revision before prompting and requires the exact text `REMOVE`; a
selection change or concurrent update cannot redirect the confirmed action.
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

Other applets can read explicit item, thread, feed, selection, draft, and
sanitized source resources through Desk's ordinary typed capability path. They
can retain and pass ordered resource lists, dereference exact revisions,
compose those identities with their own operations, request a revision-safe
draft replacement, or explicitly start the legacy public refresh when their
Practice grants the external effect. Desk owns discovery, dispatch, authority,
lifecycle, and machine-serialized external I/O; Practices govern typed calls
and provenance. In the explicit Bluesky composition, Streams owns the
provider, HTTP admission, feed decode, retained model, and draft state. A
composed instance commits a completion only when instance and request
generations match exactly.

The external-I/O service is not itself a Streams capability, and Streams does
not coordinate unrelated applets. When a live Streams target exists, Desk's
curated Observe facet may expose only `streams.source.query` and
`streams.source.read`, with the normal 4 KiB result ceiling and exact target
generation. It grants neither endpoint/configuration disclosure nor source
mutation, refresh, staging, dispatch, or any external effect. Public reads
require no app password, and Streams accepts or stores no credential.
Authenticated AT Protocol operations and publication remain outside this
applet boundary.

The deterministic `streams-xio-contracts`, provider, and connector gates pass
offline, including cooperative open/close, cancellation, stale-completion
rejection, and cleanup. The focused `streams-live-public` component journey
also passes through a real TAP interface across DNS, TCP, authenticated TLS
1.3, HTTP, provider admission, feed decode, owner commit, and cleanup. It is
not evidence of the still-pending Desk-hosted responsiveness/recovery journey.
The connector's complete live certificate/signature phases also lack a
measured per-poll CPU ceiling, and TLS-context cleanup is not yet proof that all
machine-global KDOS TLS/cryptographic scratch has been sanitized.
