# Streams Information Integration Contract

Status: Gate 1 corrected product contract. The landed manual configured-source
refresh slice is the implementation baseline; later work may deepen the
source, acquisition, and observation product, but it must not turn Streams
into the machine corpus, document editor, scheduler, workflow engine, or
outbound-delivery ledger. Current UI and capability details remain in
[`streams.md`](streams.md).

## Product boundary

Streams is the bounded monitored inbox for internet-originated information.
It owns three connected concerns:

1. exact local source configuration and provider admission;
2. explicit, recoverable acquisition attempts; and
3. immutable retained observations, revisions, provenance, and inbox search.

Its characteristic questions are:

- What sources am I monitoring, and under which admitted bounds?
- What arrived or changed?
- Which exact attempt and source revision produced this observation?
- Did a refresh fail, become stale, exceed capacity, or remain indeterminate?

Streams remains useful without Library, Pad, Agent, or Practice-specific
bindings. Those peers add deliberate corpus promotion, editing lenses,
analysis proposals, and contextual nomination/authority; none supplies or
absorbs Streams' acquisition semantics.

| Role | Boundary |
| --- | --- |
| Streams | Owns source configuration, provider policy, attempt state, immutable observations, exact-key revision detection, retained inbox search, and acquisition recovery. |
| Library | Owns deliberately collected captures, managed documents, metadata, collections, archive/tombstone lifecycle, and corpus search. |
| Desk | Hosts applet/service lifecycles, routes typed intents, and advances serialized external I/O; it owns no Streams records. |
| Pad | Edits ordinary files or exact mutable resources through an owner contract; it never becomes the owner merely by opening text. |
| Agent | May read or propose under an exact bounded facet and Mandate; external text is evidence, not instruction or ambient authority. |
| Practice | Binds stable resource/root facts and separately records authority; binding neither copies data nor grants an operation. |
| Daybook | Owns human planner time semantics and, only after its later gate, typed schedules and occurrence history. Streams is not a scheduler. |

Desk does not parse provider payloads. Library does not read Streams' VFS
records. Pad does not schedule acquisition or own observation provenance.
Practice does not absorb the inbox. Cross-product work uses typed operations,
qualified locators, and intents rather than sibling implementation imports.

## Current ownership inventory

The implemented source registry, source store, observation checkpoint,
observation store, configured provider, syndication decoder/HTTP adapter, and
refresh owner remain Streams domain code. General HTTP, media, readable-text,
syndication-format, TLS, and external-I/O machinery remain platform modules.

The current private draft is the one known ownership error:

- `/streams-draft.bin` and `streams.draft.create/read/replace/validate/current`
  are a legacy compatibility surface to migrate to a Library managed document
  opened through Pad.
- The validated Gate 0 revision-7 record is frozen migration input and recovery
  evidence. It is not a template for Streams outputs, saved findings, or a
  general document system.
- Library must never open the path or import the codec. A later Streams-owned
  migration adapter exports one exact validated revision through typed Library
  operations and preserves the original bytes until separately approved
  retirement.
- Until that migration gate, the current owner and behavior remain unchanged.
  Gate 1 adds no proxy, journal, store, capability, or route.

The legacy public Bluesky selection/item/thread/feed/local-search/refresh
surface also remains compatibility behavior. It converges with configured
observations only after parity is independently proved; Gate 1 does not
reinterpret its existing identities or schemas.

## Resource identity and ownership

External addresses, provider-native identifiers, local resource identities,
source revisions, observation revisions, store generations, component
revisions, activation epochs, and content digests are distinct facts. None may
silently stand in for another.

Every durable semantic resource has a stable local identity that does not
depend on array position, UI selection, provider label, external address, or a
live component instance. A digest proves byte identity, not trustworthiness,
semantic correctness, ownership, or invocation authority. Aggregate operations
return bounded resource references plus small summaries; callers dereference
only what they need.

Selection and focus are observation conveniences. Consequential calls name an
explicit source/observation RID and exact domain revision where required.
Persistent cross-product references use a qualified locator or semantic
`RREF`; activation-local `LBIND`, component instance/generation, acquisition
token, capability pointer, callback, or grant is never durable state.

### Source

A source is a mutable, revisioned local configuration owned by Streams. The
landed record contains a stable caller-supplied RID, kind/format, label,
enabled flag, endpoint and provider configuration, redirect/response/page and
observation bounds, refresh policy/interval fields, and a positive optimistic
revision.

Strings are exact valid UTF-8. Provider code separately admits schemes, hosts,
redirects, media, and provider-specific configuration before external work.
Ordinary source reads are sanitized and never disclose endpoint/provider
configuration where the operation contract excludes it. A configured source
does not grant arbitrary HTTP, DNS, socket, redirect, credential, or trust
authority.

The interval/cadence fields remain inert compatibility data. Refresh is
explicit. They must not become a hidden timer merely because the fields exist;
a later visible schedule belongs to Daybook and invokes a typed Streams
operation only after its own authority gate.

Credentials, if later admitted, remain separate owner-private state. TLS trust
is machine boot authority: source creation, enablement, applet launch, and
refresh cannot import CA bytes or widen a frozen trust snapshot.

### Acquisition attempt

The refresh owner coordinates one exact source snapshot, a configured
provider, Desk-hosted external-I/O submission, decode, durable commit, stale
checks, cancellation, and cleanup. It is not a scheduler or general effect
ledger.

`BEGIN` records `accepted` and is durably saved before external submission.
`TERMINAL` records failure, cancellation, stale completion, cleanup failure,
or recovery without changing last-good observations. `APPLY` validates one
already-decoded batch and transactionally records success, immutable versions,
key heads, and new/revised/unchanged counts. An accepted attempt found after
relaunch becomes `indeterminate` before publication; the owner never guesses
that an effect did or did not escape.

A refresh acknowledgement means only that one exact bounded attempt was
durably accepted. It does not report remote success. Provider callbacks never
commit applet or Practice state directly; owner publication revalidates the
instance, source RID/revision, and request generation after lower cleanup.

### Observation

An observation is one immutable acquired version. It retains a stable logical
RID and positive revision, exact source identity/namespace, provider-native
identity, admitted content and metadata, attempt identity, digests, and the
provenance the provider actually supplied. Unavailable facts remain
unavailable rather than being reconstructed from current source state.

The landed checkpoint is exactly 131,072 pointer-free bytes and contains:

- one latest attempt head for each of sixteen exact sources;
- forty-eight immutable observation versions, at most sixteen per source;
- sixty-four provider-native key heads; and
- one canonical owned string blob.

The exact key includes source RID, source-identity namespace, provider kind,
native-identity kind, and admitted native-identity bytes. The checkpoint does
not perform cross-source deduplication. A first key creates revision 1 of a
stable observation RID; changed semantic content advances that RID; an
unchanged candidate consumes no new version/body.

Retention follows deterministic checkpoint sequence, never provider timestamp
or wall-clock order. One body contributes at most 8 KiB to the shared blob. A
valid batch that cannot fit is rejected while prior observations and key heads
remain unchanged. There is no rolling eviction or compaction: capacity blocks
new admission and preserves last-good evidence.

Future observation query/read/content/revision operations must be bounded and
explicitly source-scoped for Agent facets. Exact old-revision reads never
advance to current. A safe text projection states its projection contract,
media type, exact byte length, and digest and never executes untrusted markup.

## Durable records and asymmetric loss

| Record | Current path | Meaning |
| --- | --- | --- |
| Source registry snapshot | `/streams-sources.bin` | Configuration authority and optimistic source generation |
| Observation checkpoint snapshot | `/streams-observation.bin` | Attempt heads, immutable observation versions, and exact-key heads |
| Legacy private draft | `/streams-draft.bin` | Frozen compatibility/migration input; not part of the target Streams model |

Source and observation records use separate optimistic replacement envelopes
so an acquisition commit does not rewrite configuration authority. Corrupt,
future-format, I/O-uncertain, or ambiguous-recovery state blocks unsafe
mutation and is never replaced by a manufactured empty value.

Source-store V1 does not record that an observation companion ever existed. A
valid nonempty source store with a missing observation record therefore means
“never refreshed or unproven companion loss,” not a proven clean empty
history. Gate 1 preserves that limitation. A pair marker would change format
and recovery semantics and requires a separate migration decision.

## Bounds

Implemented bounds are format/behavior contracts; proposed query bounds remain
provisional until their focused gate.

| Domain | Bound | Status |
| --- | --- | --- |
| Sources | 16 | Landed |
| Source record | 2,288 bytes | Landed |
| Label / endpoint / provider config | 96 / 1,024 / 1,024 UTF-8 bytes | Landed |
| Redirects / response / pages | 3 / 128 KiB / 2 | Landed |
| Concurrent configured refreshes | 1 per owner instance | Landed |
| Decoded candidate batch | 8 | Landed |
| Observation checkpoint | Exactly 131,072 bytes | Landed |
| Attempt heads | 16, latest per source | Landed |
| Observation versions | 48 total, 16 per source, 4 per key | Landed |
| Exact-key heads | 64 | Landed |
| Observation title / URL / summary / body | 256 / 512 / 1,024 / 8,192 bytes | Landed |
| Observation query page | 32 small references/summaries | Proposed; not implemented |

No Streams bound reserves capacity for Library collections, output documents,
rules, schedules, or outbound attempts because Streams does not own those
models.

## Owner capability surface

The near target adds only explicit source/observation operations. The four
landed configured-source capabilities are identified below; source create,
replace, and remove currently remain direct owner/UI operations. Observation
operations are planned and become stable only with their focused schema and
projection tests.

| Capability | Effect | Contract/status |
| --- | --- | --- |
| `streams.source.query` | Observe | Landed user-principal bounded registry view; whole-registry access is not an ordinary Agent facet |
| `streams.source.read` | Observe | Landed exact sanitized source revision |
| `streams.source.create` | Mutate + Persist | Planned direct-owner operation; no fetch |
| `streams.source.replace` | Mutate + Persist | Planned explicit RID and expected source revision |
| `streams.source.set-enabled` | Mutate + Persist | Landed explicit source resource; no fetch |
| `streams.source.remove` | Destructive + Persist | Planned explicit RID/revision and retention policy |
| `streams.source.refresh` | Persist + External | Landed explicit configured source RID/revision; no arbitrary URL |
| `streams.observation.query.within` | Observe | Planned bounded query over a sealed exact source-RID allowlist |
| `streams.observation.read` | Observe | Planned exact bounded envelope/provenance read |
| `streams.observation.content` | Observe | Planned exact admitted projection with length/digest |
| `streams.observation.revisions` | Observe | Planned bounded exact version chain |

The current `streams.selection.current`, item/thread/feed/local-search, public
feed refresh, and five draft capability IDs remain documented compatibility
surface in `streams.md` and the Gate 0 manifest. They are not evidence that
selection is an adequate mutation target or that Streams should grow a
document/output subsystem.

Schemas are closed. Mutation checks domain revision in addition to generic
component revision. Source refresh/configuration/removal and all external work
remain outside ordinary read/assist facets. An Agent-visible query takes a
sealed source-RID scope or one-source projection owner; the current null-input
whole-registry query enters a facet only when the whole registry is explicitly
authorized.

## Interoperation

### Collect in Library

“Collect” creates a new Library identity and copies one exact admitted
observation projection. It is not a Streams saved flag or pin. The initiating
flow acquires the exact observation owner through the Streams root, copies one
owner-serialized result with locator/revision, provenance, semantic digest,
projection contract, exact bytes/length/content digest, releases its
activation-local token on every terminal path, and asks Library to commit and
read back the capture under a caller operation key. Library never reads the
checkpoint or source endpoint.

### Open in a lens

A future fixed-RID observation projection is read-only. Pad may show admitted
text only through `resource.open` after qualified resolution/acquisition and
`resource.snapshot`; it does not receive a writable temporary VFS copy. Any
derived/editable document is a separately created Library managed document
with lineage to the observation. Streams never owns that document.

### Practice and authority

A Practice may bind a source or exact Library result, but binding only makes a
stable resource relevant/nameable. It does not copy observations, confer read
or refresh authority, persist an `LBIND`, or make Practice the owner. A
separate exact facet/grant, preset attenuation, live resolution, and Mandate
seal every invocation.

## Provider scope

The landed configured refresh supports exact-host authorized RSS, Atom, and
JSON Feed over the shared HTTP/TLS/XIO substrate. Watched HTML/text snapshot
admission exists as a codec/policy foundation but is not wired through the
syndication-only owner/checkpoint format. Notification configuration shapes do
not establish a qualified provider, immutable observation codec, subscription
model, or outbound operation.

Before adding a materially different provider, return with its store-format,
authorization, polling/subscription, privacy, and failure semantics. Do not
squeeze it through the syndication codec merely because source kind/format
cells exist.

## Explicit non-ownership

The following are outside the near Streams surface:

- saved sets, annotations, classifications, corpus archive/search, and durable
  “knowledge” organization: Library collections/tags/lineage;
- mutable drafts, derived outputs, reports, and cited documents: Library
  managed documents edited through Pad;
- interval execution, reminders, recurrence, and occurrence history: Daybook
  after its schedule/authority gates;
- generic rules and cross-applet conditional workflows: unresolved separate
  product decision, not Practice or Desk by convenience;
- outbound notification/publication, Outbox, reconciliation, and delivery
  ledger: unresolved product owner and a direction gate;
- credentials, generic HTTP/browser/crawler behavior, raw network tools,
  arbitrary cron jobs, universal search, taxonomy/claims graph, or persisted
  runtime pointers/grants.

Pure bounded source-local filters/change predicates may remain only when they
cannot cause cross-applet or external effects. External content is untrusted
evidence and is never inserted into instruction/tool context by parsing it.

## Acceptance journey

The configured information-integration slice is complete when a standalone
Streams build can:

1. launch with no fabricated content and configure several admitted sources;
2. explicitly refresh one exact source without freezing Desk;
3. durably distinguish accepted, succeeded, failed, cancelled, stale,
   capacity-blocked, cleanup-failed, and recovered-indeterminate attempts;
4. preserve last-good observations on every rejected or ordinary-failure path;
5. show exact source/revision/provenance and suppress true unchanged values;
6. query/read bounded retained observation revisions without endpoint/provider
   secrets or silent advance to current; and
7. close and relaunch with sources, attempts, exact-key heads, and immutable
   observations recovered within declared bounds.

Library collection, Pad viewing, Agent disclosure, Practice binding, and
Daybook scheduling are separate typed ecosystem gates. None is needed to claim
the source/acquisition/observation product is coherent.

## Evidence labels

| Label | Evidence |
| --- | --- |
| `offline-contract` | Deterministic schemas, fixtures, bounds, lifecycle, capacity, corruption, cancellation, and recovery |
| `live-connectivity` | One real provider exchange through the admitted network composition |
| `cooperative-transport` | Shared DNS/TCP/TLS/HTTP progression and terminal cleanup without blocking the owner loop |
| `cooperative-client` | Provider progression, cancellation, stale rejection, and transactional owner commit |
| `live-desk` | Desk-hosted responsiveness, close, relaunch, and serialized external-I/O journey |
| `hardware-parity` | Equivalent qualified behavior on the physical/RTL target |

No label implies a stronger one. Optional live runs do not replace deterministic
contracts, and fixture success does not prove a live service or hardware path.
