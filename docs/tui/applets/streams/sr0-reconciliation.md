# Streams SR0 reconciliation record

**Status:** complete architectural reconciliation; no runtime change

**Date:** 2026-07-25

**Product contract:** [`information-integration.md`](information-integration.md)

**Current behavior:** [`streams.md`](streams.md)

**Reset handoff:**
[Streams architectural reset handoff](../../../../../STREAMS_ARCHITECTURAL_RESET_HANDOFF.md)

SR0 stops the observation-repository cutover and establishes the inputs to SR1.
It changes product direction, ownership, planning, and module disposition only.
It does not claim a new capability ABI or a working bidirectional runtime.

## Decisions adopted

1. Streams is bidirectional internet-data infrastructure. Input, response, and
   output are first-class.
2. Library owns documents and corpus behavior. A Streams spool/outbox is
   bounded operational state used only to finish or reconcile transfers.
3. HTTP is the first proving protocol. SR1 seals a storage-free core; SR2
   proves request-to-response/output behavior; SR3 adds operational durability.
4. General AT Protocol/PDS machinery belongs under `akashic/atproto/`.
   Streams composes connector instances and Bluesky is one application profile.
5. “Full PDS support” means full client-side participation. Hosting a PDS is a
   separate decision.
6. Desk hosts cooperative machine web/external-I/O lifecycles. Streams owns
   admitted route and flow configuration, not request/router/template
   mechanics.
7. The initial flow surface is small, typed, and bounded. No arbitrary workflow
   DSL, scheduler, ambient callback, or universal business Outbox is authorized.
8. Serialized physical external-I/O progression is acceptable initially if
   event, queue, backpressure, cancellation, and delivery semantics are
   caller-owned and concurrency-ready.
9. Credentials are opaque references to separately owned session/credential
   state. Connector records never persist app passwords or trust anchors.
10. Every output is direct-user or explicitly Desk/Practice-reviewed, with an
    exact destination and exact payload. Agent receives no ambient send
    authority.

## Active-document reconciliation

| Document | SR0 status |
| --- | --- |
| Workspace reset handoff | Continuation rationale, staged sequence, exact worktree handoff, and broad salvage ledger |
| `information-integration.md` | Normative forward product and ownership contract |
| `streams.md` | Current prototype/compatibility behavior only |
| `l13-authority-topology-retention.md` | Cancelled historical L13 design; non-normative |
| Workspace master refactor plan | L0-L12 remain complete; L13 halted; Streams uses SR0-SR6 |
| Desk ecosystem contract | Bidirectional owner table, first HTTP journey, operational outbox ownership, and historical Gates 7-8 |

Old implementation facts remain evidence. A top-level supersession or
historical label means a current format/capability description may still be
correct without controlling future design.

## Existing HTTP/network substrate

### Retain within current contracts

| Module | Useful surface | SR0 disposition |
| --- | --- | --- |
| `akashic/net/io-port.f` | `NIO-*` cooperative byte-stream lifecycle | Keep as the transport-port seam |
| `akashic/net/http-request.f` | `HREQ-*` bounded outbound request writer and send step | Keep; current bodies are buffered whole |
| `akashic/net/http-stream.f` | `HSTR-*` incremental HTTP response parser | Keep as response-side parser; do not misapply it as an inbound request parser |
| `akashic/net/http-buffered.f` | `HBUF-*` cooperative outbound exchange | Keep for bounded initial egress |
| `akashic/net/http-resource.f` | Redirect/admission/result/cleanup lifecycle | Keep as a qualified client-side acquisition primitive |
| `akashic/net/http-target.f` | Canonical target/host/port policy | Keep |
| `akashic/net/media-type.f` | Syntax-level media parsing | Keep |
| `akashic/net/sse.f` | SSE format/client input foundation | Keep for later connector work after lifecycle audit |
| `akashic/net/external-io.f` | Desk-hosted accepted/poll/cancel owner | Keep for the first serialized proof |
| `akashic/net/transports/kdos-tls.f` | Cooperative outbound TLS transport | Keep within current trust/address bounds |

Current limitations remain visible:

- outbound request bodies are whole-buffered;
- buffered/resource responses are accumulated rather than streamed onward;
- Desk XIO admits one active machine operation;
- KDOS TLS has machine-global scratch and is outbound-only;
- current resolution is IPv4-A-only with a small hostname bound; and
- loopback/private address and trust policy is deliberately conservative.

SR2 must not weaken address or trust policy merely to make a local webhook
fixture convenient. A cooperative plaintext local-test adapter needs its own
explicitly bounded admission.

### Freeze as compatibility

| Module | Reason |
| --- | --- |
| `akashic/net/http.f` | Blocking, process-global, and non-reentrant |
| `akashic/net/ws.f` | Blocking/global client-only lifecycle; useful frame/masking ideas do not make it a cooperative bidirectional foundation |

Do not build the new runtime on either module. Preserve compatibility callers
until a replacement is proven.

### Rework as general web infrastructure

| Module | Problem to correct |
| --- | --- |
| `akashic/web/server.f` | Global/serial lifecycle; `SRV-STEP` can idle-poll for a long interval; one connection is closed after handling |
| `akashic/web/request.f` | Global state; whole-message parsing; no strict incremental request framing or Content-Length/Transfer-Encoding conflict policy |
| `akashic/web/response.f` | Global buffers/socket; no caller-owned partial-send, backpressure, cancellation, or cleanup state |
| `akashic/web/router.f` | Global route table and route-parameter scratch |
| `akashic/web/middleware.f` | Global middleware/auth/static configuration and request dependence |
| `akashic/web/template.f` | Useful escaping/composition, but global raw variable substitution must become caller-owned, bounded, and escaped by default |

The Flask-like API remains a general `web/` concern. SR2 needs:

- cooperative listener/accept and explicit accepted-connection ownership;
- a bounded incremental inbound request parser with smuggling defenses;
- request-body admission and streaming/whole-body policy;
- a caller-owned response serializer/send pump;
- partial writes, deadlines, cancellation, cleanup, and exact close truth;
- bounded connection and request queues; and
- per-route/per-connection state with no process-global current request.

## Existing AT Protocol substrate

### Keep or recast

| Module | Disposition |
| --- | --- |
| `akashic/atproto/public-author-feed.f` | Keep as the strongest cooperative credential-free compatibility connector/reference; adapt results to generic events |
| `akashic/atproto/feed-model.f` | Keep strictly as a Bluesky `app.bsky.*` projection, never protocol or Streams core |
| `akashic/atproto/aturi.f` | Rework into caller-owned checked utility |
| `akashic/atproto/did.f` | Rework into caller-owned checked utility and extend through proper DID/PDS resolution |
| `akashic/atproto/tid.f` | Rework into caller-owned utility with explicit clock/identity inputs |

### Replace before authenticated PDS use

| Module | Reason |
| --- | --- |
| `akashic/atproto/xrpc.f` | Global host/cursor/buffers, blocking legacy HTTP, raw parameter handling, weak structured error/rate-limit state |
| `akashic/atproto/session.f` | Global ambient bearer state, incomplete zeroization/logout, hard-coded assumptions |
| `akashic/atproto/repo.f` | Global scratch/manual JSON and incomplete repository surface over the legacy XRPC/session path |

The missing general track includes handle/DID/PDS discovery, DID service
parsing, caller-owned zeroizing sessions, structured XRPC errors and rate
limits, list/applyWrites, blobs, Lexicon validation, CAR/MST/sync, and
firehose/Jetstream cursor/reconnect/backpressure.

Broader DNS, TLS scratch, and trust admission are machine/net decisions.
Streams must not solve them by persisting credentials, CA bytes, or ambient
network authority.

## Existing Streams connector inputs

| Module | Disposition |
| --- | --- |
| `syndication-http.f` | Keep as an ingress adapter/reference over general HTTP |
| `configured-provider.f` | Rework useful lifecycle into direction-neutral input/output/bidirectional connector contracts |
| `public-provider.f` | Retire the hardwired seam from the new ABI after compatibility replacement |
| `syndication-decode.f` | Rework to emit generic bounded events, not observation revisions |
| `page-snapshot.f` | Keep as an optional bounded acquisition/transform, not storage or event core |
| `source-registry.f` | Recast stable identity, revision, bounds, and span validation as connector configuration; drop input-only/observation assumptions |

Notification test payloads do not imply a production provider. There is
currently no output connector, delivery ledger, or outbox implementation.

## L13 landed code disposition

| Commit | Disposition |
| --- | --- |
| `4266752` | Do not activate authority/index/repository/query design. Mine checked key-record agreement, keyset continuation, span/bounds, and fault cases |
| `1076080` | Retain exact legacy readers only as offline export/retirement evidence |
| `42028f5` | Stop repository/compaction/migration destination. Reuse accepted-before-effect, terminal/indeterminate, and revalidation ideas in transfer attempts |
| `a095565` | Salvage atomic revalidation/commit concepts only |
| `d00f557` | Rework refresh lifecycle into an event-producing connector |
| `d9978e7` | Preserve exception-containment regression lessons |
| `fdf34c7` | Salvage bounded allocation, cold-open, teardown, and cleanup patterns |

`index-keys.f`, `index-record-agreement.f`,
`semantic-record-agreement.f`, and `persistence-records.f` are historical
contract-mining material. `authority-root.f`, `persistence-adapter.f`,
`repository.f`, `compaction.f`, `migration.f`, and
`observation-construction.f` must not become the product authority.

Leaving the seven commits intact but dormant is safer than rewriting or
reverting history during SR0. A later cleanup decision may archive or revert by
explicit new commits after the corrected product has replacement evidence.

## Dirty pre-SR0 worktree disposition

| File | Decision |
| --- | --- |
| `akashic/tui/applets/streams/streams.f` | Rejected repository/query applet cutover; do not land |
| `akashic/tui/applets/streams/runtime-owner.f` | Span helper exists only for that cutover; do not land independently without a new caller |
| `local_testing/akashic_tui.py` | Old observation/capacity fixture work; preserve separately, do not fold into SR1 |
| `local_testing/streams-refresh-owner.f` | Old observation fault/fixture work; preserve separately, do not fold into SR1 |
| `local_testing/streams-cold-l13-test.f` | Untracked rejected-model cold fixture; do not run or land |
| `local_testing/streams_l13_two_boot.py` | Untracked rejected-model two-boot harness; do not run or land |

Before SR1 implementation touches overlapping files, preserve this exact state
on an archive branch or patch through an explicitly authorized, non-destructive
operation. SR0 itself does not reset, delete, commit, or push it.

SR0's versioned work is one focused documentation commit containing:

```text
docs/tui/applets/streams/information-integration.md
docs/tui/applets/streams/l13-authority-topology-retention.md
docs/tui/applets/streams/streams.md
docs/tui/applets/streams/sr0-reconciliation.md
```

Those documentation paths are no longer dirty at SR0 closure. The pre-SR0
implementation and fixture files listed above remain deliberately uncommitted.
The workspace-root master plan, Desk contract, future-concepts note, and reset
handoff are outside the nested Akashic Git repository.

## Prototype-data decision

The workspace contains no evidence of real user-created Streams state.
Excluding ignored/generated `local_testing/out/` and `prototype_archive`, the
only Streams binary state is seven deterministic Gate 0 fixtures:

- one 79-byte legacy draft fixture;
- three 36,712-byte source-store fixtures; and
- three 131,136-byte observation-store fixtures.

Their README identifies them as deterministic compatibility/qualification
evidence rather than seed, runtime, recovery, or user data. Generated emulator
images are not migration inputs.

SR0 therefore adopts **no migration tax**. Retain exact readers/fixtures as
historical evidence. Before eventual compatibility-reader removal, ask only
whether the user has a real external prototype image or copy outside this
workspace. If none exists, retire the old draft/source/observation formats
without building a migration framework.

## Directional capability families

SR0 names families, not exact IDs or schemas:

- connector query/read/configure/start/stop;
- flow query/read/configure/start/stop;
- bounded event/attempt/delivery inspection;
- exact output enqueue/send;
- delivery query/read/retry/cancel;
- HTTP route/request/response composition through general web contracts;
- AT Protocol account/session/subscription/repository operations through
  general protocol contracts; and
- explicit Library Collect and exact Library/Pad content acquisition.

SR1 seals only the minimum mock connector/event/flow/attempt contracts needed
for one end-to-end input/output proof.

## SR0 exit ledger

- [x] Original L13 is halted in the master plan.
- [x] The Desk ecosystem ownership contract defines bidirectional Streams and
      distinguishes an operational outbox from a universal workflow queue.
- [x] The normative Streams information contract is bidirectional.
- [x] `streams.md` is explicitly current behavior, not future direction.
- [x] The L13 topology document is explicitly historical and non-normative.
- [x] Every landed L13 commit and dirty file has a keep/rework/retire decision.
- [x] HTTP/web/ATProto/connector substrate has an explicit
      keep/freeze/rework/replace map.
- [x] No actual workspace user data was found; the no-migration default is
      recorded.
- [x] The first demonstrator and SR1-SR6 sequencing are consistent across
      active documents.
- [x] No emulator, integration, smoke, persistence, or live-network test was
      run for SR0.

The next implementation phase is SR1, not completion of any old L13 gate.
