# Streams SR1 storage-free core

**Status:** semantic milestone complete; its unreleased byte layout and
qualification fixture were replaced by the SR2 bounded runtime on 2026-07-25

**Scope:** the caller-owned connector, event, flow, and transfer-attempt
contracts required before protocol, persistence, applet, or Desk composition

**Current successor:** [`sr2-runtime-shape.md`](sr2-runtime-shape.md)

**Normative product contract:**
[`information-integration.md`](information-integration.md)

**Controlling sequence:**
[Streams architectural reset handoff](../../../../../STREAMS_ARCHITECTURAL_RESET_HANDOFF.md)

## Milestone boundary

SR1 proved that the replacement Streams direction could have a small, bounded,
storage-free execution core. It does not revive the cancelled L13 repository
and does not claim that the current applet or Desk runs this core.

The SR1 descriptor layout is no longer present. Its connector/event/flow and
attempt semantics were carried forward and requalified in the storage-free
SR2 runtime; no alternate SR1 implementation, reader, or adapter remains.

## Historically qualified semantic surface

| Contract | Historical SR1 shape |
| --- | --- |
| Connector | Sealed positive-revision input, output, or bidirectional descriptor with exact identity, endpoint, protocol, and bounded output callbacks |
| Event | Sealed ingress, egress, or internal envelope with event, connector, flow, correlation, idempotency, origin, destination, revision, protocol, media, sequence, time, payload length, and SHA3-256 payload digest |
| Payload ownership | One single-shot borrowed or owned binding, or flow-inline; owned BUILDING events can roll back through the exact release callback, and callbacks borrow immutable event/payload bytes only for their call |
| Flow | One caller-owned, single-admission state machine with an explicit transform and one input and output connector snapshot |
| Attempt | Separate ingress and egress evidence carrying direction, state, effect truth, reason, detail/error, cleanup error, generation, times, identities, payload length, and digest |
| Output operation | At most 256 caller-owned bytes passed across start, poll, cancel, and cleanup callbacks |

The historical SR1 fixture used these fixed bounds:

- one admitted event per flow (`STREAMS-FLOW-QUEUE-CAPACITY = 1`);
- at most 4,096 payload bytes (`STREAMS-FLOW-PAYLOAD-MAX = 4096`);
- at most 256 output-operation bytes (`STREAMS-FLOW-OP-MAX = 256`); and
- a positive timeout no greater than 600,000 milliseconds.

Queue admission copies the exact ingress bytes into the flow-owned slot. A
full flow refuses the new event without taking its ownership. An accepted
owned event is released exactly once; repeated close does not release it
again. A release failure or throw remains visible as cleanup failure after
the live pointers have been cleared. Payload binding cannot be overwritten by
a second borrowed or owned tuple. If envelope sealing fails after an owned
binding, closing the BUILDING event releases that original tuple exactly once.

Connector descriptors remain caller-owned. Their storage and structurally
valid sealed configuration must remain available through exact flow
retirement. A positive revision change is handled as staleness; invalidating
or reusing the descriptor storage before retirement violates this lifetime
precondition.

## Capacity and evolution boundary

SR1 qualifies one prototype execution cell, not the final Streams queue or a
product-wide capacity limit. Its singular ingress/egress event and attempt
fields make the one-slot behavior structural. The 4,096-byte payload and
256-byte operation bounds also size storage embedded in each flow descriptor;
they are not runtime knobs. The timeout is configurable per flow within its
qualified ceiling.

The first SR2 landing has now settled the runtime-facing shape before HTTP
composition:

- a bounded caller-owned pool of execution cells with explicit pool-full
  refusal and connector-callback ownership;
- payload storage separated from the cell layout, with named compact and
  standard bounded profiles;
- exact ordering, digest, cancellation, and cleanup rules when one logical
  payload spans more than one buffer or event; and
- one clean replacement of the prototype descriptor layout.

The standalone cell had no persisted representation, released consumer, or
compatibility obligation. SR2 replaced it atomically and added no parallel
layout, adapter, migration, deprecation period, or old-layout reader. Current
runtime descriptors use magic and size checks only to reject uninitialized or
wrongly sized caller memory within the current build.

The replacement must preserve SR1's ownership, attempt/effect truth,
staleness, cleanup, generation, and retirement semantics. Raising a constant
without redesigning and requalifying the runtime shape is not an accepted
scale path. General HTTP and persistence code must use the public contract
rather than persisting raw descriptors, depending on prototype offsets, or
retaining inline addresses. The SR2 runtime fixture now moves bounded payloads
larger than the old inline limit without enlarging every execution cell. The
real HTTP journey remains the next landing.

## Attempt and effect truth

Ingress and egress are deliberately different attempts. A successful
transform acknowledges ingress before output begins. The ingress
acknowledgement remains true if the later egress attempt fails, is cancelled,
or becomes indeterminate.

Attempt state and external-effect truth are separate fields. SR1 preserves the
following distinctions:

| Condition | Attempt truth |
| --- | --- |
| Transform rejects or throws before output exists | Ingress `failed-before`, effect not applied; no egress attempt |
| Transform cancels | Ingress cancelled, effect not applied |
| Output reports failure before effect | Egress `failed-before`, effect not applied |
| Output reports failure after a known effect | Egress `failed-after`, effect applied |
| Output cannot establish effect truth | Egress indeterminate, effect uncertain |
| Output callback throws after start may have begun | Egress indeterminate/effect uncertain unless earlier evidence already proved the effect applied |
| Connector revision changes before admission or continuation | Stale refusal/terminal state, never silently retargeted |
| Cancellation before output starts | The current ingress or egress attempt is cancelled without invoking an unstarted output |
| Cancellation while output is active | The exact output cancel callback decides cancelled versus indeterminate truth |
| Deadline reached | Timeout is explicit and active output is cancelled through the same bounded callback contract |
| Output cleanup fails or throws | Primary delivery/effect truth is retained; cleanup error is reported separately |

Terminal work is immutable. Healthy carrier-backed events and payload bytes
remain readable until a caller retires the exact current generation.
Retirement closes and wipes both carriers, expires the events, clears
operation storage, and only then permits reuse; the next admission receives a
new generation. Two caller-owned flows progress independently; the core
declares no hidden flow-owned mutable state.

## Deterministic evidence

The original SR1-only fixture was deleted with its byte layout. The current
[`test_streams_sr2_runtime.py`](../../../../local_testing/test_streams_sr2_runtime.py)
builds the focused linked profile and requalifies the complete SR1 semantic
surface against the replacement runtime. Its happy path admits `ping`,
transforms it to `tx:ping`, seals and revalidates the payload digest,
acknowledges ingress, delivers egress, performs output cleanup once, and
reads the exact terminal egress, proves a stale retirement leaves it intact,
then retires the exact generation and proves both carriers and operation
storage were wiped.

The replacement fixture retains coverage of:

- connector direction validation and bidirectional descriptors;
- borrowed and owned event lifecycle, single-shot binding, failed-seal
  rollback, full-queue refusal, and exactly-once release;
- exact and over-limit payload and operation sizes, zero/maximum/over-maximum
  timeouts, and admission deadline-overflow refusal;
- release errors and throws;
- pending start followed by poll and delivery;
- transform failure, cancellation, and throw;
- output failed-before, failed-after-known-effect, indeterminate, callback
  throw, and attempted payload mutation;
- monotonic effect evidence across later poll failure and active connector
  staleness, so known-applied work cannot be downgraded to uncertain;
- cancellation before output, while output-ready, and while delivering,
  including a throwing cancel callback;
- timeout, stale connector revision, terminal immutability, retirement, reuse,
  and independent flows; and
- output cleanup errors and throws without loss of primary attempt truth.

It additionally qualifies external segmented carriers, compact and standard
profiles, a mixed caller-owned execution pool, measured live memory,
full/one-over and no-fitting-cell refusal, shared-connector serialization, and
cross-cell isolation. The complete current record is
[`sr2-runtime-shape.md`](sr2-runtime-shape.md).

[`test_streams_sr2_static.py`](../../../../local_testing/test_streams_sr2_static.py)
proves that the linked dependency closure remains storage-free, excludes the
old source/observation/repository/runtime/app path, declares no top-level
mutable storage, contains no SR1 layout surface, and introduces no prerelease
compatibility or ABI layer.

| Qualification | Passed evidence |
| --- | --- |
| Focused linked runtime profile | `python local_testing/test_streams_sr2_runtime.py` reached `STREAMS SR2 RUNTIME PASS` |
| Host/static architecture ratchets | `python -m pytest -q local_testing/test_streams_sr2_static.py` passed the dependency, storage, replacement, and no-glut checks |

SR1 earns only:

- `offline-contract`; and
- the standalone/mock form of `bidirectional-flow`.

It does not earn `protocol-framing`, `cooperative-transport`,
`live-connectivity`, `live-desk`, or `hardware-parity`. In particular, the
mock output connector is not an applet, Desk, HTTP, webhook, or other
production output.

## Archived pre-reset evidence

Before SR1 work overlapped the dirty pre-reset tree, exact patches were
preserved under
[`prototype_archive/streams-pre-sr1-dirty-20260725/`](../../../../../prototype_archive/streams-pre-sr1-dirty-20260725/).
The dirty pre-reset state was captured there before SR1 work. Those patches
are historical recovery/salvage evidence, not SR1 inputs, a supported
implementation, or authority to preserve or finish the old L13 cutover.

## Explicit non-goals

SR1 adds no:

- persistence, VFS path, cursor checkpoint, durable queue, spool, outbox,
  receipt store, recovery, migration, or retention policy;
- HTTP client/server, route, request, response, webhook, template, SSE, or
  WebSocket behavior;
- AT Protocol/PDS or Bluesky connector;
- applet entry point, Desk owner/service composition, UI, or live network
  witness;
- Library/Pad Collect or authored-content delivery path; or
- compatibility cutover, observation sidecar, old L13 qualification, or
  replacement of the existing prototype surfaces.

## Exit and SR2 handoff

The SR1 exit is satisfied: one bounded mock input produces an exact event, one
explicit transform consumes it, and one mock output emits an exact result
while backpressure, cancellation, timeout, stale state, primary/effect truth,
and cleanup remain explicit.

SR2 has carried those semantics into the external-carrier, mixed-profile pool
described by [`sr2-runtime-shape.md`](sr2-runtime-shape.md). Its next landing
composes the general `web/` and `net/` repairs needed for the first real
bidirectional HTTP slice. Route/server/request/response/template mechanics
remain general, Streams configuration and attempt truth remain
Streams-owned, and the milestone remains storage-free until that runtime
behavior establishes what SR3 actually needs to persist.
