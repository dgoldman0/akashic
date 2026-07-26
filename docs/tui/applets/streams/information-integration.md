# Streams information integration contract

**Status:** normative product and ownership contract; SR2 is complete and SR3
implementation is in progress

**Reconciled:** 2026-07-25

**Controlling decision:** [Streams architectural reset handoff](../../../../../STREAMS_ARCHITECTURAL_RESET_HANDOFF.md)

**SR0 inventory and disposition:** [`sr0-reconciliation.md`](sr0-reconciliation.md)

**SR1 core and qualification:**
[`sr1-storage-free-core.md`](sr1-storage-free-core.md)

**SR2 bounded runtime:** [`sr2-runtime-shape.md`](sr2-runtime-shape.md)

**SR3 operational durability:**
[`sr3-operational-durability.md`](sr3-operational-durability.md)

**Current implementation:** [`streams.md`](streams.md)

This contract replaces the former Gate 1 monitored-inbox definition and the
cancelled L13 observation-repository target. It defines what Streams is
supposed to become. It does not claim that the current prototype already
implements the capability horizon below.

The old four-tree repository design remains available only as a historical and
salvage record in
[`l13-authority-topology-retention.md`](l13-authority-topology-retention.md).
Its migration, authority flip, retention model, and cutover checklist are not
active work.

## Product boundary

Streams is Akashic's bidirectional internet-data and streaming infrastructure.
Its characteristic question is:

> How does internet data enter, move through, transform within, and leave the
> system—and what happened to each transfer?

The product shape is:

```text
HTTP routes / webhooks / feeds / SSE / WebSocket / ATProto / remote APIs
                                  |
                                  v
                         input connectors
                                  |
                                  v
                       bounded event envelopes
                                  |
                     route / filter / transform
                         /         |          \
                        v          v           v
              HTTP response   output sink   Library capture
              or web page     / delivery    (explicit and optional)
```

Input and output are equally part of the product. A connector may be input,
output, or bidirectional. HTTP server requests and responses, HTTP clients and
webhooks, feeds, streamed connections, and AT Protocol/PDS participation all
belong in the product horizon.

Streams is not a document-management system with network acquisition attached.
Receiving bytes does not automatically create a document. A durable payload
snapshot kept only to finish or reconcile a bounded transfer is operational
storage, not a corpus record. Long-term retention, titles and user metadata,
managed revisions, collections, archive lifecycle, and corpus search belong
to Library.

Streams must remain useful without Library. It can receive, transform, answer,
send, retry, and report on bounded transfers by itself. Library adds deliberate
long-term collection and exact authored-content acquisition; it is never the
hidden backing store for every event.

## Ecosystem ownership

| Owner | Authoritative responsibility |
| --- | --- |
| Streams | Connector instances, events in transit, cursors, flows, bounded queues/spools, transfer attempts, acknowledgements, retries, delivery, receipts, and uncertain-effect reconciliation |
| Library | Deliberately collected captures and managed documents, exact revisions, metadata, collections, archive lifecycle, and corpus search |
| Pad | Editing and authoring through an exact owner projection; no network delivery ledger |
| `net/` | Transport, client-side HTTP framing, TLS adapters, URI/URL/header/media mechanics, and I/O ports |
| `web/` | HTTP server request/response parsing and construction, routing, middleware, and templates |
| `atproto/` | General identity, discovery, sessions, XRPC, repositories, blobs, sync, and subscription protocol machinery |
| `syndication/` and `markup/` | Portable feed, HTML, readable-text, and format projections |
| Desk | Applet/service lifecycle, typed routing, review composition, and machine external-I/O hosting |
| Practice | Durable authorization context, attenuation, bindings, and visible grants |
| Daybook | Human schedules and occurrence history; it may invoke one exact typed Streams operation |
| Agent | May propose or invoke explicitly granted bounded operations; no ambient network or raw untrusted-content authority |

Desk does not parse provider payloads or own transfer records. Library never
opens Streams-private storage. Pad does not become the owner of content merely
by displaying it. Practice binding makes a resource nameable but neither
copies it nor grants an operation.

## Streams-owned contracts

SR1 sealed the minimum connector, event, flow, attempt, ownership, and effect
semantics against one prototype byte layout. The first SR2 landing has
requalified those semantics after replacing that unreleased layout outright.
The current runtime has external segmented carriers, named compact and
standard workspaces, and a measured mixed-profile pool. It contains no
alternate descriptor, ABI selector, adapter, migration, deprecation path, or
old-layout reader.

One flow is still one active transfer cell, but it is no longer the system's
only admission slot and it contains no inline body or operation buffer. Pool
capacity is supplied by the caller; a fitting free cell is leased exactly,
all-active exhaustion reports `FULL`, and a free pool with no fitting profile
reports `CAPACITY`. Connector callbacks serialize at the shared connector
descriptor. Protocol-specific extension, persistence, applet/Desk
composition, and cross-owner capability schemas remain work for their named
later milestones.

### Connector

A connector is one admitted protocol endpoint and operational instance. It has:

- stable local identity and positive configuration revision;
- input, output, or bidirectional direction;
- protocol/profile kind and explicit endpoint or route policy;
- bounded request, response, payload, queue, retry, redirect, and timeout
  policy as applicable;
- an opaque reference to separately owned credentials or session material,
  never embedded secret bytes;
- current lifecycle and health state; and
- protocol-specific cursor, resume, or acknowledgement state where required.

Connector configuration does not grant arbitrary DNS, socket, HTTP, redirect,
credential, trust, or publication authority. Admission and effect authority
are checked independently.

### Event

An event is a bounded in-transit envelope, not a document. It identifies:

- event, connector, flow, correlation, and idempotency facts;
- ingress, egress, or internal direction;
- origin/destination and protocol/profile kind;
- media type and bounded protocol metadata;
- received/accepted ordering, time, sequence, cursor, or resume facts;
- exact payload location, byte length, and digest;
- acknowledgement or delivery state; and
- ownership, borrowing, expiry, and cleanup rules.

An event payload may be borrowed for a synchronous response, owned in bounded
memory, or durably snapshotted in an ingress queue or egress outbox. The
contract must state which. No caller may retain a borrowed payload after its
declared lifetime or silently reinterpret an expired queue entry as a saved
document.

The HTTP composition must state whether a payload is one small inline message,
one caller-owned bounded body, or an ordered bounded stream. A streamed
payload needs one logical identity, order and completion facts, an exact
whole-payload digest, backpressure, cancellation, and cleanup. Increasing the
SR1 inline limit without defining that profile is not sufficient.

### Flow

A flow explicitly connects admitted connectors and bounded transforms. It
owns routing and operational state, not a universal workflow language.

The first surface is a small typed or compiled set of routes, filters, and
transforms. It is not arbitrary code persisted as data, a general rules
engine, cron, or a cross-applet automation graph. A Daybook schedule may later
invoke one exact Streams operation through ordinary typed authority; that
does not make Streams a scheduler.

Backpressure is part of the flow contract. Queue admission, refusal, pause,
resume, cancellation, timeout, and teardown must remain truthful whether
physical network progression is serialized or concurrent.

Streams now owns a caller-supplied bounded set of active transfer cells; the
general web runtime will separately own its bounded route and connection
state. Payload storage is external segmented carrier geometry rather than a
fixed inline field in every cell. Pool capacity and measured memory cost are
explicit, exhaustion refuses new work without retargeting an occupied cell,
and one connector serializes its callbacks across sharing cells. Two
interleaved mock flows, an 8,192-byte transform path, exact profile bounds,
and a full two-cell pool plus one refused admission prove the runtime is
neither a hidden singleton nor tied to the historical 4 KiB payload. The HTTP
landings prove the corresponding framing, connection isolation, pressure,
and cancellation properties. A durable queue is not simulated by keeping
more live cells; it remains SR3 work.

### Transfer attempt and delivery

Ingress and egress effects use explicit attempts. States must distinguish at
least:

- accepted;
- active;
- acknowledged or delivered;
- failed before effect;
- failed after a known effect;
- cancelled;
- stale; and
- indeterminate.

Accepted means only that the owner durably or otherwise authoritatively
accepted the declared work. It does not imply remote success. Retried effects
name exact payload bytes and idempotency/correlation facts; they never silently
follow a newer Library document revision.

Cleanup and uncertain-effect reconciliation are product semantics. A transport
failure, cancellation, crash, or lost acknowledgement must not be rewritten as
“not sent” merely because the local call failed.

### Operational persistence

Streams may durably own only the state required to configure, continue,
deliver, reconcile, or inspect bounded flows:

- connector and flow configuration;
- cursor, resume, and subscription checkpoints;
- bounded ingress queues and egress outboxes;
- exact payload snapshots required for retry or reconciliation;
- attempt, acknowledgement, delivery, and receipt records; and
- explicit terminal retention and cleanup state.

These records must have bounded retention or capacity behavior. They must not
grow Library-style titles, arbitrary user metadata, revision trees,
collections, archive search, or indefinite content retention.

SR3 keeps durable queue/spool capacity separate from SR2's active-cell pool.
Each persisted format identifies its current shape and has item and byte
ceilings, full/one-over behavior, and fail-closed unknown-format handling.
Qualification covers interrupted publication, corrupt or unknown records,
queue exhaustion, restart, exact retry bytes, idempotency, receipts, and
operator-visible indeterminate work. Before the first supported release,
format changes replace the prototype atomically rather than accumulating
legacy readers.

Work is reported durably accepted only after the exact payload snapshot and
attempt identity commit. An indeterminate external effect is not retried
automatically unless the connector's declared idempotency contract makes that
safe. Durable formats store semantic records and payload bytes or chunks, not
raw runtime descriptors.

## Protocol and package boundaries

Streams composes general Akashic protocol layers and may drive their
requirements. It must not create applet-private replacements for them.

### HTTP and web

The existing `akashic/net/` packages provide URI, URL, headers, media types,
request construction, bounded response parsing, cooperative HTTP exchange,
resource acquisition, SSE, WebSocket, TLS, and I/O-port mechanisms.

The existing `akashic/web/` packages provide request parsing, response
construction, routing, middleware, server behavior, templates, and a concrete
RPC composition.

Those packages remain broader starting points rather than one completed
cooperative web runtime. SR2 made the subset needed by its first route
caller-owned, bound request and response bodies, composed runtime cancellation
and cleanup, and qualified framing, smuggling, route isolation, and
simultaneous connection ownership. Listener acceptance and Desk service
hosting remain outside that accepted-connection slice.

The active-cell pool, payload profiles, clean descriptor replacement, and
first cooperative route-to-response journey are complete. The closing landing
carried that composition through two interleaved requests, a body larger than
4,096 bytes without enlarging every cell, a slow or cancelled peer, pool
exhaustion, and exact teardown within measured workspace memory. General code
uses descriptor accessors and never persists raw runtime layouts. SR2 does not
add a durable queue.

Routes, requests, responses, middleware, and template expansion remain general
`web/` behavior. Streams owns the admitted route/connector, event flow,
attempt, and user-visible operational state.

### AT Protocol and PDS

General AT Protocol participation belongs under `akashic/atproto/`. Streams
owns configured AT Protocol connector instances and uses them for input and
output. Bluesky's `app.bsky.*` behavior is one adapter/profile over those
general operations, not the Streams data model.

The current package has useful AT URI, DID, TID, basic XRPC, basic repository
CRUD, and public author-feed pieces. It does not yet provide the required
caller-owned secure PDS runtime. The forward contract includes:

- handle/DID resolution and PDS service discovery;
- caller-owned, zeroizing login, refresh, logout, and session state;
- caller-owned XRPC state with structured errors, pagination, rate limits, and
  retry metadata;
- repository get/list/create/put/delete and supported atomic/batch writes;
- blob upload and references;
- lexicon/record validation appropriate to the selected methods;
- repository sync/export primitives, including CAR/MST handling where needed;
- subscription/firehose or Jetstream-style input with cursor, reconnect,
  cancellation, and backpressure; and
- authorized record/blob output through the same delivery semantics as other
  Streams sinks.

“Full PDS support” here means full client-side participation with a PDS.
Hosting a complete PDS on Akashic is a separate federation, storage,
moderation, abuse, and security product decision.

## Library and Pad interoperability

There are two distinct owner-preserving operations.

### Collect input

Collect copies one exact event/payload into a new Library capture with a
distinct Library RID, exact bytes and digest, media type, origin, and
connector/attempt provenance. The Library commit is explicit. Streams does not
mark a queue entry “saved,” and Library does not depend on that queue entry
remaining alive.

### Deliver authored content

An output operation acquires one exact Library/Pad-owned revision or packaged
asset, freezes the bytes and digest required for delivery, and hands that
bounded payload to a Streams attempt. A retry uses those same bytes. It never
implicitly follows “current.”

Templates may be packaged resources or exact Library-owned authored content
under a later contract. Streams may reference and render them through general
`web/` facilities; it must not build a competing template-document store.

## Capability horizon

Names and schemas below are directional, not stable capability ABI
assignments. The SR1 record seals only the minimum storage-free runtime
descriptors; SR2 and later milestones must close their own protocol and
cross-owner schemas before composition.

| Resource/effect | Required shape |
| --- | --- |
| Connector query/read | Bounded summaries and exact sanitized configuration/health reads |
| Connector configure/start/stop | Exact connector identity/revision, admitted policy, and truthful lifecycle |
| Flow query/read | Bounded summaries, exact topology and current operational state |
| Flow configure/start/stop | Exact flow revision and connector/transform operands |
| Event/attempt inspection | Exact bounded envelope, transfer state, failure, cursor, and cleanup facts |
| Output enqueue/send | Exact connector/destination, payload bytes or exact owner revision, idempotency key, and visible review |
| Delivery query/read/retry/cancel | Exact attempt identity and expected state; no selection-relative effect |
| HTTP route/response | General `web/` contracts composed by a Streams connector/flow |
| AT Protocol account/subscription/repository operation | General `atproto/` machinery composed by a Streams connector |
| Library collect/content acquire | Typed cross-owner copy or exact immutable acquisition; never shared private storage |

Observe facets never imply output authority. A selected UI row never becomes
an ambient destination. Every external effect names the exact connector,
destination, payload identity/digest, expected operational state, and reviewed
authorization.

## Current older prototype state

The current implementation predates this contract. Its facts remain documented
in [`streams.md`](streams.md):

- the older Bluesky-shaped retained page, thread, feed, search, and public
  refresh surface;
- `/streams-draft.bin` and five draft capabilities;
- configured source and manual syndication refresh behavior;
- the fixed source and observation snapshot stores; and
- the landed but not production-composed L13 repository modules.

The SR2 `runtime-profile.f`, `payload-carrier.f`, `flow-core.f`, and
`execution-pool.f` now sit beside those older prototype surfaces. They are the
qualified replacement runtime, but they are not yet required by `streams.f`,
exposed as an applet capability, composed with Desk, or backed by any durable
store. The standalone `http-route.f` composition qualifies the accepted
HTTP/web journey without making it the live applet authority. Deterministic
mock output is therefore not a claim of production applet output.

Disposition:

- preserve exact user-created data and only the still-live behavior
  temporarily required to bridge to a qualified replacement;
- delete displaced prerelease paths when their replacement lands rather than
  accumulating parallel implementations;
- do not build new product semantics on the private draft or fixed observation
  checkpoint;
- do not activate the L13 four-tree repository, run its authority-flip
  migration, or finish its applet cutover;
- recast source configuration as connector configuration;
- recast useful accepted-before-effect, cancellation, cleanup, stale-result,
  and indeterminate-recovery behavior as general transfer semantics; and
- treat old observations and scale fixtures as prototype evidence, not the
  target workload.

No prototype data migration is required merely because code or deterministic
fixtures exist. If an inventory identifies actual user-created sources,
observations, or draft content, preserve and export that exact data before
retiring its reader. Otherwise the unreleased prototype incurs no migration
tax.

## First replacement slice

SR1 qualified the storage-free mock connector → event → transform → output
semantics, and the first SR2 landing carried them into the bounded pool and
segmented carriers. The first composed demonstrator remains deliberately
HTTP-first and storage-light:

1. Configure a local route such as `POST /hooks/demo`.
2. Receive one bounded JSON or form request without blocking Desk.
3. Produce one bounded event with connector, media, correlation, and payload
   facts.
4. Route it through one explicit transform.
5. Render one HTML or JSON response through the general web layer.
6. Optionally make one immediate, volatile attempt to send the exact result to
   a second local HTTP/webhook sink.
7. Show accepted, active, acknowledged/delivered, failed, cancelled, stale, or
   indeterminate state.
8. Leave Library unchanged unless the user explicitly chooses Collect.

SR2 landed in three reviewable stages. The pool/payload/cutover boundary, the
cooperative HTTP journey, and the closing interleaving/pressure gate are
complete. The route uses a named fitting profile; a 4,097-byte request crosses
the first byte beyond the compact carrier while an interleaved small request
remains in that cell, so the larger path does not enlarge every cell. Two active leases,
one-over refusal, slow-peer cancellation, independent completion, and exact
teardown are qualified. “Enqueued” or “durably accepted” remains SR3 language.

The in-memory/mock flow contract is now qualified before durable queues. The
deterministic cooperative HTTP slice is also qualified before AT Protocol and
Bluesky restructuring. Applet/Desk hosting, listener/TLS composition, live
connectivity, and hardware parity remain unqualified. HTTP output, AT Protocol
restructuring, and Library/draft migration must not be combined in one landing.

## Acceptance and evidence

The replacement direction is proven only when Streams visibly moves internet
data in both directions while Library remains the deliberate home for
documents.

The first slice must prove:

- one bounded input connector, route/transform, and output/response;
- exact ownership and cleanup for every payload;
- queue refusal/backpressure and cancellation without freezing Desk;
- truthful terminal and indeterminate outcomes;
- no hidden document/corpus persistence;
- exact reviewed authority for every external effect; and
- deterministic mock/fault behavior before an optional live-network witness.

| Label | Evidence |
| --- | --- |
| `offline-contract` | Deterministic schemas, bounds, lifecycle, failure, cancellation, cleanup, and retry |
| `protocol-framing` | Request/response parser and serializer behavior, hostile framing, size limits, and EOF cases |
| `cooperative-transport` | Progress and teardown without blocking the Desk owner loop |
| `bidirectional-flow` | One admitted input traverses a bounded transform and produces an exact response or delivery |
| `live-connectivity` | One reviewed real endpoint exchange; never a substitute for deterministic evidence |
| `live-desk` | Desk-hosted responsiveness, review, close, and relaunch behavior |
| `hardware-parity` | Equivalent qualified behavior on the physical/RTL target |

No label implies a stronger one. Concurrency may increase physical throughput,
but one-worker and many-worker execution must preserve the same event,
backpressure, retry, delivery, and cleanup semantics.

The current SR2 runtime earns the bounded-runtime portion of
`offline-contract`; the HTTP landings earn `protocol-framing`, deterministic
cooperative transport, and the request/response form of `bidirectional-flow`.
External segmented carriers, exact payload
copy/digest/integrity, compact and standard profiles, a mixed measured pool,
two interleaved flows, full/one-over and no-fitting-cell refusal,
single-shot ownership, separate ingress and egress attempts, failure/effect
distinctions, callback serialization and faults,
timeout/deadline-overflow/stale handling, and exactly-once cleanup are
qualified by
[`test_streams_sr2_runtime.py`](../../../../local_testing/test_streams_sr2_runtime.py).
[`test_streams_sr2_static.py`](../../../../local_testing/test_streams_sr2_static.py)
qualifies the storage-free dependency closure, absence of top-level mutable
storage, clean SR1 layout replacement, and absence of a prerelease
compatibility or ABI layer.
[`test_web_http_primitives.py`](../../../../local_testing/test_web_http_primitives.py)
qualifies strict request, route, response, partial-send, source-fault, and
cancellation behavior, while
[`test_streams_sr2_http_route.py`](../../../../local_testing/test_streams_sr2_http_route.py)
qualifies one exact fragmented JSON request-to-response lifecycle, and
[`test_streams_sr2_http_pressure.py`](../../../../local_testing/test_streams_sr2_http_pressure.py)
qualifies interleaved compact/standard requests, a 4,097-byte body, exact
full/one-over refusal, a stalled/cancelled peer, independent success, and
cross-request cleanup. All live, Desk, and hardware labels remain unearned.
