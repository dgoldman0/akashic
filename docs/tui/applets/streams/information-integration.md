# Streams Information Integration Contract

Status: proposed target contract. This document defines the intended Streams
information-integration boundary; it does not claim that the described
resources, providers, capabilities, persistence, UI, or ecosystem witnesses
are implemented. Current behavior remains documented in `streams.md`.

## Product boundary

Streams is an independently useful applet for acquiring, retaining, comparing,
processing, and deliberately routing internet-originated natural-language
information over time. Its characteristic questions are:

- What arrived or changed?
- What repeated, matched a rule, or was saved?
- What was derived from which exact evidence?
- What was staged or sent, and what remains failed or uncertain?

Streams must remain useful when Bluesky, Pad, Agent, and Practice-specific
bindings are omitted. Those integrations add lenses, analysis, and contextual
authority; they do not supply missing core acquisition, provenance, search,
diffing, rules, output, or recovery behavior.

| Owner | Responsibility |
| --- | --- |
| Streams | Source configuration, provider admission, immutable observations, revision/change detection, deterministic local processing, saved findings, derived-output lineage, staged payloads, and the delivery ledger |
| Desk | Applet lifecycle, typed target and intent routing, approval surfaces, serialized external I/O, and bounded operation advancement |
| Pad | Optional deep reading of an exact snapshot and editing of an exact mutable output revision |
| Agent | Bounded semantic analysis and proposals under a Mandate; no ambient network, stage, or dispatch authority |
| Practice | Durable contextual bindings and separately attenuated authority; promoted knowledge only after explicit acceptance |

Desk does not parse provider payloads. Pad does not schedule acquisition or own
provenance. Agent does not perform foundational parsing, hashing, diffing,
deduplication, routing, or delivery bookkeeping. Practice does not absorb
Streams' evictable cache or live provider sessions.

## Resource identity and ownership

External addresses, provider-native identifiers, local resource identities,
content digests, resource revisions, and component revisions are distinct
facts. None may silently stand in for another.

Every durable resource has a stable local identity that survives relaunch and
does not depend on its array position, UI selection, current provider label, or
external address. A digest proves byte identity, not trustworthiness, semantic
correctness, or authority. Aggregate operations return bounded resource lists
and small summaries; callers dereference only the resources they need.

Provider-specific data remains a closed, kind-discriminated typed extension.
The common envelope must not become a fixed map of mostly-null Bluesky, feed,
page-watch, wiki, and notification fields.

### Source

A source is a mutable, revisioned local configuration owned by Streams. It
contains:

- stable local identity, kind/provider, label, and enabled state;
- exact admitted external configuration and redirect policy;
- manual or bounded refresh policy;
- provider-specific bounded configuration;
- retention policy and last attempt/result; and
- conditional-request metadata where supported.

Credentials, if admitted by a later milestone, are separate owner-private
state. Ordinary source reads return a sanitized projection and never disclose
credential material. Configuring a semantic source does not grant arbitrary
HTTP, socket, DNS, or redirect authority.

### Observation

An observation is one immutable acquired version. It records:

- local observation and source identities;
- provider kind and provider-native identity;
- exact/canonical origin where the provider establishes one;
- acquisition, publication, and update times when known;
- admitted media/content type and representation;
- raw and normalized digests where applicable;
- explicit previous-version/revision relations;
- retrieval provenance and result; and
- typed provider-specific metadata and external relations.

A changed external entity creates a new observation version. Deduplication may
suppress a redundant retained body, but it must preserve each distinct source
and retrieval provenance. Cross-source similarity may group findings without
declaring them identical.

### Saved set

A saved set is mutable, revisioned, durable Streams state containing exact
observation identities and digests. Saving either pins the required bounded
content or fails explicitly; it must not leave a durable collection pointing
only at content eligible for silent eviction. Annotations, user classifications,
and collected relationships belong to saved state rather than rewriting an
immutable observation.

### Output and Outbox

An output begins as a mutable, revisioned draft with exact lineage. Lineage
records every input observation identity/digest and deterministic
transformation. Agent-created material additionally records trusted Mandate,
invocation, provider/model, and run provenance when those facts are available
from an owner-controlled source.

Staging freezes an exact payload, destination, disclosure set, lineage, and
output revision. Later draft edits cannot mutate a staged dispatch. Each send
or reconciliation is a separate immutable attempt with a stable invocation or
idempotency identity and an append-only status history.

## Provisional bounds

The following values bound the first contract and fixture corpus. They are
provisional until measured against the normal Desk image and representative
providers; changing them requires capacity and recovery tests, not silent
growth.

| Domain | Provisional first bound |
| --- | --- |
| Sources | 16 |
| Source configuration payload | 2 KiB of endpoint plus provider-config bytes inside one 2,288-byte registry record |
| Redirects | 3 per operation |
| Concurrent Streams external operations | 1 per instance |
| Transient response body | 128 KiB per response; 256 KiB aggregate refresh budget |
| Retained observation versions | 48 total, 16 per source |
| Versions of one provider-native entity | 4 |
| Compact deduplication heads | 64 provider-native entities |
| Searchable/normalized content | 8 KiB per observation within an 80 KiB checkpoint blob |
| Query page | 32 resource references |
| Saved sets | 16, with 64 members each |
| Outputs | 32, with 32 KiB text and 64 lineage references each |
| Delivery attempts | 8 per output |
| Agent-visible result | 4 KiB per operation; larger content is paged |

Every store also declares version, byte capacity, retention/eviction order,
corruption behavior, interrupted-replacement recovery, and cleanup ownership.
Corrupt or future-format state remains available for bounded inspection or
repair and blocks unsafe mutation; it is not replaced with a manufactured
empty store.

The first physical contract uses two independently recoverable replacement
targets. `/streams-sources.bin` owns the source registry. A separate
`/streams-observe.bin` acquisition checkpoint owns source attempt state,
deduplication heads, and immutable observations, so one refresh transaction
cannot leave cursor/result state out of step with committed observations.
Source repair must not erase readable observations, and observation repair
must not silently rewrite source authority. Both use checked VFS replacement;
exactly one missing after an established pair is a recovery condition rather
than permission to synthesize the missing half.

## Target capability surface

These operation identifiers describe the intended narrow owner surface. They
are not an implementation inventory.

| Capability | Effect | Contract |
| --- | --- | --- |
| `streams.source.query` | Observe | Return a bounded page of source resources and sanitized summaries |
| `streams.source.read` | Observe | Read one sanitized source revision and last-result state |
| `streams.source.create` | Mutate + Persist | Create one bounded provider configuration without fetching |
| `streams.source.replace` | Mutate + Persist | Replace one exact source revision |
| `streams.source.set-enabled` | Mutate + Persist | Enable or disable one exact source revision without fetching |
| `streams.source.remove` | Destructive + Persist | Remove one source under explicit retention policy |
| `streams.source.refresh` | External | Start refresh of one already configured source; accepts no arbitrary URL |
| `streams.observation.query` | Observe | Search/filter a bounded retained page and return resource identities |
| `streams.observation.read` | Observe | Read one bounded common envelope and typed extension |
| `streams.observation.content` | Observe | Read exact admitted content through bounded pages |
| `streams.observation.revisions` | Observe | Return a bounded ordered version chain |
| `streams.saved.query` | Observe | Return bounded saved-set identities and summaries |
| `streams.saved.read` | Observe | Read one exact saved-set revision and member identities |
| `streams.saved.create` | Mutate + Persist | Create a bounded saved set |
| `streams.saved.replace` | Mutate + Persist | Replace membership/metadata at an exact expected revision |
| `streams.saved.remove` | Destructive + Persist | Remove one saved set without deleting independently retained evidence |
| `streams.output.query` | Observe | Return bounded output/Outbox identities and summaries |
| `streams.output.read` | Observe | Read one output revision, lineage, stage, and delivery state |
| `streams.output.create` | Mutate + Persist | Create a local derived draft with exact lineage |
| `streams.output.replace` | Mutate + Persist | Replace one exact unstaged draft revision |
| `streams.output.stage` | Mutate + Persist | Freeze exact payload, destination, disclosure, and lineage |
| `streams.output.dispatch` | External + Persist | Persist an attempt and start delivery of one exact staged revision |
| `streams.output.reconcile` | External | Query status for one exact prior attempt where supported |
| `streams.output.remove` | Destructive + Persist | Remove eligible local output state under retained-ledger policy |

Query arguments, maps, lists, strings, and provider extensions have closed
schemas. Mutation uses domain-resource expected revisions in addition to the
request bus's component-instance revision. Selection and focus are never an
adequate target for Agent or consequential calls.

## Authority

Reachability, operation description, Mandate, and invocation authority remain
separate:

- A Practice binding makes a resource nameable; it grants no operation.
- A capability facet selects exact operations on exact target generations; it
  is not itself authority.
- A Mandate bounds a run, effects, disclosure, tools, time, and disposition;
  it is not itself authority.
- A one-use owner-side grant authorizes one sealed invocation.

### User control

The standalone UI exposes the same domain operations through direct owner
methods or typed requests. Destructive removal, stage, disclosure, dispatch,
and unsafe retry require a preview/confirmation showing exact resource,
revision, target, payload digest, and uncertainty. User-principal default
policy is not a substitute for a humane consequential-action surface.

### Agent control

The ordinary read facet may contain only curated, bounded source summaries,
observation query/read/content pages, saved-set reads, and output reads. Pure
Observe calls may receive automatic per-Mandate grants within disclosure and
tool budgets.

The ordinary assist facet may add reviewed saved-set and output
create/replace operations. Agent material remains proposal data until the
owning context accepts the exact mutation. External text is untrusted evidence,
not instruction, and must not be inserted into system/tool instruction context.

Source configuration/removal, refresh, stage, dispatch, reconciliation,
destination changes, and deletion are absent from ordinary read/assist facets.
Agent-operated versions require an explicit operator facet and a reviewed,
sealed, one-use grant for the exact target and operands. Read authority never
implies refresh, transform, stage, disclose, or dispatch authority.

### Practice control

A Practice may bind selected sources, rules, saved sets, outputs,
destinations, and identities. It does not bind every retained observation or
provider session by default. Observation, transformation, staging,
disclosure, refresh, and dispatch are distinct granted operations even where
the current effect bitmask is coarser. Promotion of a finding to durable domain
knowledge is explicit and does not transfer Streams cache or scheduler
ownership.

Practice roots and activation-local references are not, by themselves, a
completed durable binding graph. The implementation must not claim durable
promotion until root validation, schema/version handling, reactivation, and
recovery are proved.

## Asynchronous acceptance and delivery semantics

Refresh and dispatch handlers acknowledge only that a durable bounded
operation was accepted for cooperative advancement. They do not report remote
success.

Before external submission, the owner persists:

- exact source or staged-output revision;
- frozen request/payload and target digest;
- invocation/idempotency identity;
- requested time and current attempt state; and
- enough reconciliation metadata to avoid unsafe blind replay.

The durable state machine distinguishes at least:

1. draft/local;
2. staged and awaiting authority;
3. accepted for local execution;
4. sending;
5. accepted by the immediate provider;
6. confirmed, where separately knowable;
7. failed and safely retryable;
8. rejected/non-retryable; and
9. indeterminate after a possibly escaped effect.

An HTTP success code is evidence about one protocol exchange, not universal
delivery confirmation. Cancellation or close proves lower transport cleanup;
it does not retroactively prove that an outward effect did not occur. A retry
is a new recorded attempt and reuses a logical idempotency identity only where
the provider contract supports it.

Old observations remain readable during refresh and after ordinary failure.
Provider callbacks never commit applet or Practice state directly; owner commit
revalidates component, instance, source, request, and operation generations.

## Pad witness

The lowest-risk ecosystem witness is deterministic Pad interoperation:

1. Pin and expose one exact retained observation as a read-only semantic text
   resource.
2. Post the existing `resource.open` intent with an exact RREF.
3. Verify that Pad retains the exact revision while Streams refreshes.
4. Expose one mutable derived output through `resource.snapshot` and
   exact-revision `resource.replace`.
5. Edit it in Pad and observe the new output revision in Streams without
   changing lineage, stage, or destination state.

This witness requires general substrate work and is not currently proved:

- Pad's shared lens is currently initialized for the Daybook resource and
  rejects other RIDs.
- The current shared-document owner is a singleton tied to `/daybook.md`.
- The resource registry currently permits one semantic RID per owner instance
  because invocation authority does not seal resource identity.

The first implementation should therefore use one bounded, store-backed
projection-owner instance per open or explicitly promoted resource, or first
extend and qualify authority sealing for resource identity. It must not alias
many observation RIDs to the main Streams instance, add a Streams-specific Pad
hook, or use a silently editable temporary VFS copy. Immutable observations
open read-only; mutable outputs alone expose replacement.

## Provider shapes for the first milestone

The common contract is proved against materially unlike fixtures before any
schema is frozen:

- RSS, Atom, and JSON Feed entries and updates;
- watched bounded public HTML/text snapshots and revisions; and
- a simple bidirectional notification provider using bounded polling and
  outward publication.

Fixtures cover empty, Unicode, duplicate, updated, malformed, oversized,
unsupported encoding/media, redirect, no-change, meaningful-change,
navigation-noise, accepted, rejected, retryable, timeout, and indeterminate
cases. Fixtures are explicit tests and never production fallback content.

## Explicit exclusions

- A provider-neutral timeline formed by renaming the current Bluesky model.
- A full Bluesky client, authentication, home timeline, social actions, or
  publication as the milestone nucleus.
- A general browser, JavaScript runtime, crawler, arbitrary HTTP tool, raw
  network inspector, or search-result scraper.
- Email/JMAP or a permanently open notification subscription in the first
  slice.
- An unlimited archive, scheduler, rule engine, taxonomy, or revision history.
- Agent-required parsing, hashing, diffing, deduplication, routing, or delivery
  bookkeeping.
- Silent disclosure or dispatch based only on read, compose, or Practice
  binding authority.
- A provider-private TCP/TLS/X.509 stack, trust bundle, or connector.
- Persisted runtime pointers, handler tokens, invocation handles, or
  activation-local grants.
- A claim that fixture success proves live service, Desk responsiveness,
  complete crypto timing, scratch erasure, or hardware parity.

## Acceptance journey

The information-integration milestone is complete only when a build omitting
Bluesky, Pad, Agent, and Practice-specific bindings can:

1. launch with no hidden content and configure several feed/page sources plus
   the selected notification source/destination;
2. refresh cooperatively without freezing Desk and retain old information on
   ordinary failure;
3. present exact provenance, detect a meaningful page revision, and suppress
   true duplicate/no-change content without erasing provenance;
4. search, apply an inspectable deterministic rule, and save related exact
   findings;
5. generate a cited output with exact lineage;
6. stage and send an alert through a genuine outward effect;
7. show accepted, confirmed, failed, retryable, rejected, or indeterminate
   state truthfully; and
8. close and relaunch with sources, retained revisions, rules, saved sets,
   outputs, and delivery history recovered within declared bounds.

The Pad witness is a separate optional ecosystem gate. Agent and durable
Practice journeys follow only after the same resource contracts work
standalone and through Pad.

## Evidence labels

Evidence is reported with the narrowest label it actually proves:

| Label | Evidence |
| --- | --- |
| `offline-contract` | Deterministic schemas, fixtures, bounds, lifecycle, capacity, corruption, cancellation, and recovery |
| `live-connectivity` | One real provider exchange through the admitted network composition |
| `cooperative-transport` | Shared DNS/TCP/TLS/HTTP progression and terminal cleanup without blocking the owner loop |
| `cooperative-client` | Provider operation progression, cancellation, stale-completion rejection, and transactional owner commit |
| `live-desk` | Desk-hosted responsiveness, approval, close, relaunch, and serialized external-I/O journey |
| `hardware-parity` | Equivalent qualified behavior on the physical/RTL target |

No label implies a stronger one. Optional live runs do not replace deterministic
contracts, and deterministic fixtures do not prove a live service journey.
