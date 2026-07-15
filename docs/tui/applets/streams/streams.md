# Streams

Streams is a text-first communications and subscription applet. It retains one
bounded Bluesky author-feed page, supports timeline and partial-thread
navigation, searches the retained page, and owns one crash-recoverable
unpublished local draft. Ordinary `STREAMS-ENTRY` is offline even when Desk
exposes external I/O: it contains only the abstract provider seam and installs
no provider factory. `bluesky-public.f` supplies the explicit Bluesky
component/entry composition, and `public-trust.f` remains a separate trusted
boot contribution rather than a dependency of either ordinary Streams or that
composition module. The concrete provider uses the same cooperative KDOS TLS
connector as Codex. Initialization and observe capabilities never start network
work. Authentication and publication are not supported.

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
are closed, every declared field is required, list sizes are capped by the
eight-item feed model, and text and resource fields use the corresponding
Bluesky adapter bounds. Outputs are owned `CV` graphs rather than newline or
field-delimited strings, so post text cannot be interpreted as protocol
structure.

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

Other applets can read explicit item, thread, feed, selection, and draft
resources through Desk's ordinary typed capability path. They can retain and
pass ordered resource lists, dereference selected items, compose those
identities with their own operations, request a revision-safe draft
replacement, or explicitly start a public refresh when their Practice grants
the external effect. Desk owns discovery, dispatch, authority, lifecycle, and
machine-serialized external I/O; Practices govern the typed call and its
provenance. In the explicit Bluesky composition, Streams owns the provider,
HTTP admission, feed decode, retained model, and draft state. Ordinary Streams
owns only the offline model, abstract provider seam, and draft state. A
composed instance commits a completion only when instance and request
generations match exactly.

The external-I/O service is not itself a Streams capability, and Streams does
not coordinate unrelated applets. No built-in Agent facet currently exposes
Streams capabilities or grants this external effect. Public reads require no
app password, and Streams accepts or stores no credential. Authenticated AT
Protocol operations and publication remain outside this applet boundary.

The deterministic `streams-xio-contracts`, provider, and connector gates pass
offline, including cooperative open/close, cancellation, stale-completion
rejection, and cleanup. They are not evidence that the full public refresh has
completed through a live TAP interface or through a Desk-hosted responsiveness
journey. The connector's complete live certificate/signature phases also lack
a measured per-poll CPU ceiling, and TLS-context cleanup is not yet proof that
all machine-global KDOS TLS/cryptographic scratch has been sanitized.
