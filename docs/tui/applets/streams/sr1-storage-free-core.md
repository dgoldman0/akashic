# Streams SR1 storage-free core

**Status:** complete; standalone deterministic qualification passed
2026-07-25; SR2 is next

**Scope:** the caller-owned connector, event, flow, and transfer-attempt
contracts required before protocol, persistence, applet, or Desk composition

**Implementation:** [`flow-core.f`](../../../../akashic/tui/applets/streams/flow-core.f)

**Normative product contract:**
[`information-integration.md`](information-integration.md)

**Controlling sequence:**
[Streams architectural reset handoff](../../../../../STREAMS_ARCHITECTURAL_RESET_HANDOFF.md)

## Milestone boundary

SR1 proves that the replacement Streams direction has a small, bounded,
storage-free execution core. It does not revive the cancelled L13 repository
and does not claim that the current applet or Desk runs this core.

The implementation has no VFS, persistence, network, `web/`, `atproto/`,
Library, applet, or old Streams source/observation/repository dependency. Its
only direct requirements are the general identity, memory-span, and SHA3
helpers. It defines no top-level mutable storage: connector, event, flow,
payload, operation, result, and attempt bytes all belong to caller-supplied
descriptors.

## Sealed standalone surface

| Contract | SR1 shape |
| --- | --- |
| Connector | Sealed positive-revision input, output, or bidirectional descriptor with exact identity, endpoint, protocol, and bounded output callbacks |
| Event | Sealed ingress, egress, or internal envelope with event, connector, flow, correlation, idempotency, origin, destination, revision, protocol, media, sequence, time, payload length, and SHA3-256 payload digest |
| Payload ownership | One single-shot borrowed or owned binding, or flow-inline; owned BUILDING events can roll back through the exact release callback, and callbacks borrow immutable event/payload bytes only for their call |
| Flow | One caller-owned, single-admission state machine with an explicit transform and one input and output connector snapshot |
| Attempt | Separate ingress and egress evidence carrying direction, state, effect truth, reason, detail/error, cleanup error, generation, times, identities, payload length, and digest |
| Output operation | At most 256 caller-owned bytes passed across start, poll, cancel, and cleanup callbacks |

The fixed SR1 bounds are:

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

SR2 must settle the production-facing shape before HTTP composition makes
these choices expensive to change:

- a bounded caller-owned pool of execution cells with explicit pool-full
  refusal and connector-callback ownership;
- payload and connection storage separated from the cell layout, with named
  profiles for small inline messages and larger bounded or streamed bodies;
- exact ordering, digest, cancellation, and cleanup rules when one logical
  payload spans more than one buffer or event; and
- one clean replacement of the prototype descriptor layout if the supported
  runtime shape needs different storage.

The standalone cell has no persisted representation, released consumer, or
compatibility obligation. SR2 replaces it atomically; it does not add parallel
layouts, adapters, migrations, deprecation periods, or legacy readers. The
current magic, size, and ABI fields reject mismatched caller memory within the
current build only. They are not a promise to preserve this prototype layout.

The replacement must preserve SR1's ownership, attempt/effect truth,
staleness, cleanup, generation, and retirement semantics. Raising a constant
without redesigning and requalifying the runtime shape is not an accepted
scale path. General HTTP and persistence code must use the public contract
rather than persisting raw descriptors, depending on prototype offsets, or
retaining inline addresses. SR2 must move at least one bounded HTTP body
larger than the SR1 inline limit without enlarging every execution cell.

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

Terminal work is immutable. A caller must retire the exact current generation
before the one-slot flow can be reused; retirement clears payload and
operation storage and the next admission receives a new generation. Two
caller-owned flows progress independently; the core declares no hidden
flow-owned mutable state.

## Deterministic evidence

[`test_streams_sr1_core.py`](../../../../local_testing/test_streams_sr1_core.py)
builds the focused linked profile and runs deterministic mock connectors. Its
happy path admits the exact input bytes `ping`, transforms them to
`tx:ping`, seals and revalidates the payload digest, acknowledges ingress,
delivers egress, performs output cleanup once, and retires the exact
generation.

The same fixture covers:

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

[`test_streams_sr1_static.py`](../../../../local_testing/test_streams_sr1_static.py)
proves that the linked dependency closure remains storage-free and excludes
the old source/observation/repository/runtime/app path. It also proves that
the production core declares no top-level mutable definition.

| Qualification | Passed evidence |
| --- | --- |
| Focused linked core profile | `python local_testing/test_streams_sr1_core.py` reached `STREAMS SR1 CORE PASS` |
| Host/static architecture ratchets | `python -m pytest -q local_testing/test_streams_sr1_static.py` passed the dependency-closure and mutable-storage checks |

SR1 earns only:

- `offline-contract`; and
- the standalone/mock form of `bidirectional-flow`.

It does not earn `protocol-framing`, `cooperative-transport`,
`live-connectivity`, `live-desk`, or `hardware-parity`. In particular, the
mock output connector is not an applet, Desk, HTTP, webhook, or other
production output.

## Preserved compatibility state

Before SR1 work overlapped the dirty pre-reset tree, exact patches were
preserved under
[`prototype_archive/streams-pre-sr1-dirty-20260725/`](../../../../../prototype_archive/streams-pre-sr1-dirty-20260725/).
The original tracked and untracked compatibility files were left untouched.
Those patches are recovery/salvage evidence, not SR1 inputs and not authority
to finish the old L13 cutover.

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

SR2 now composes these semantics with only the general `web/` and `net/`
repairs needed for the first real bidirectional HTTP slice. It must keep the
route/server/request/response/template mechanics general, keep Streams
configuration and attempt truth applet-owned, prove cooperative Desk
progress/teardown, first settle the execution-pool and payload-profile
boundary above, and remain storage-free until that runtime behavior
establishes what SR3 actually needs to persist.
