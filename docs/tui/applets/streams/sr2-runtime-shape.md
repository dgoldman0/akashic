# Streams SR2 bounded runtime shape

**Status:** complete; runtime shape, cooperative HTTP, and connection
isolation/pressure are deterministically qualified

**Qualified:** 2026-07-25

**Implementation:**
[`runtime-profile.f`](../../../../akashic/tui/applets/streams/runtime-profile.f),
[`payload-carrier.f`](../../../../akashic/tui/applets/streams/payload-carrier.f),
[`flow-core.f`](../../../../akashic/tui/applets/streams/flow-core.f), and
[`execution-pool.f`](../../../../akashic/tui/applets/streams/execution-pool.f)

**HTTP composition:**
[`http-route.f`](../../../../akashic/tui/applets/streams/http-route.f) and
[`http-ownership.md`](../../../web/http-ownership.md)

**Normative product contract:**
[`information-integration.md`](information-integration.md)

## Landed runtime

The first SR2 landing replaces the unreleased SR1 single-inline-buffer layout
with a caller-owned, bounded execution runtime. A flow remains one active
transfer cell so its state and attempt truth stay simple, but a caller supplies
and seals any number of cells in an execution pool. Pool acquisition chooses a
fitting free cell from a rotating cursor, returns an exact lease, reports
`FULL` when every cell is active, and reports `CAPACITY` when a free cell
exists but none fits the requested ingress and egress bounds.

Payload bytes, segment tables, and connector-operation bytes are external to
the 1,904-byte flow descriptor. A payload carrier presents ordered,
caller-supplied segments as one logical byte string. Append fills segments in
order; seal records the exact logical length and SHA3-256 digest; copy and
digest calls revalidate integrity; close wipes when requested and performs an
owned release exactly once. Failed appends and failed carrier-to-carrier copies
restore the prior packed length and clear call scratch.

HTTP and other incremental producers reserve ingress with
`STREAMS-FLOW-INGRESS-BEGIN`, append exact slices with
`STREAMS-FLOW-INGRESS-APPEND`, and publish acceptance only through
`STREAMS-FLOW-INGRESS-COMMIT`. `STREAMS-FLOW-INGRESS-ABORT` cancels an
unpublished reservation and leaves its advanced generation stale. The
complete-event `STREAMS-FLOW-ADMIT` surface uses those same internal
reserve/copy/commit operations; it is not a second body representation or
alternate admission path.

The current named profiles are:

| Profile | Ingress | Egress | Connector operation |
| --- | ---: | ---: | ---: |
| Compact | 1 × 4,096-byte segment | 1 × 4,096-byte segment | 256 bytes |
| Standard | 4 × 4,096-byte segments | 4 × 4,096-byte segments | 512 bytes |

These are current runtime choices, not persistent formats or promises that
later tuning must preserve. A mixed pool may bind compact and standard cells
together, so admitting a larger bounded body does not enlarge every cell.
Profile validation requires the declared segment count, uniform segment
geometry, and exact operation capacity; the real supplied workspace is the
limit rather than a second global payload ceiling.

## Ownership and isolation

Each carrier seals its segment-table address and every segment data/capacity
pair separately from mutable used lengths. A monotonic carrier binding epoch
changes whenever that geometry is initialized again. A flow snapshots both
carrier epochs along with its profile and workspace addresses, and the pool
snapshots the flow binding. Direct table mutation, later flow reset, or carrier
retarget therefore invalidates the binding instead of silently changing an
already sealed cell. Pool construction also rejects overlap among its own
metadata and cell descriptors, payload descriptors, segment tables, payload
byte regions, operation workspaces, and peer connector storage. Two cells may
deliberately share the same connector descriptor, but partially overlapping
connector descriptors are invalid.

One connector serializes its `START`, `POLL`, `CANCEL`, and `CLEANUP`
callbacks through connector-owned busy state. Re-entry through another cell
using that connector returns `BUSY`; it cannot corrupt the first callback's
operation workspace or transfer truth. Different cells still progress
independently, and exact flow/lease release is required before a pool cell is
available again.

Ingress and egress attempts continue to preserve the SR1 distinctions among
failed-before, failed-after-known-effect, cancelled, stale, timed out, and
indeterminate work. Payload integrity failure cannot overwrite primary effect
truth; a failure discovered during close remains separately visible as a
cleanup error. Healthy carrier-backed events and sealed payloads remain
readable and immutable after terminal publication. Exact retirement closes
and wipes both carriers, expires those events, clears operation storage, and
only then makes the cell reusable.

## Measured live memory

The runtime reports live workspace cost through
`STREAMS-EXECUTION-PROFILE-RUNTIME-BYTES`,
`STREAMS-EXECUTION-FLOW-RUNTIME-BYTES`, and the pool runtime-byte accessors.
The count includes each flow, its two carrier descriptors, segment tables,
payload byte regions, and operation workspace. The pool total additionally
includes its descriptor and fixed entry array; shared connector descriptors
are not charged repeatedly.

| Qualified shape | Live bytes |
| --- | ---: |
| One compact cell | 10,848 |
| One standard cell | 35,824 |
| Two-entry pool with one compact and one standard cell | 47,000 |
| One connection-private HTTP bundle | 2,592 |
| Three connection-private bundles in the pressure gate | 7,776 |
| Pressure composition: pool, three bundles, shared router/config/connectors | 55,400 |

The 1,904-byte flow descriptor contains event and attempt metadata but no
inline body buffer and no inline connector-operation buffer. Capacity changes
therefore change caller-supplied workspaces, not every flow descriptor.
Connection-private measurement includes the owner, request and response
descriptors, route match, I/O port, route operation, authority, and their
header/RX/send arenas. The pressure total counts the shared router, route
config, and two connector descriptors once. Mock wire-input, capture, and
fixture-control buffers are test transport data rather than live server
storage and are excluded.

## Cooperative HTTP journey

The second SR2 landing adds strict incremental request framing, copied
caller-owned routing, bounded pull-source responses, and one cooperative
connection owner under general `web/` ownership. Streams contributes only the
admitted route, pool, event metadata, transform, attempt truth, and
per-connection route operation. Listener acceptance, TLS, keep-alive, Desk
hosting, and durable work remain outside this slice.

`POST /hooks/demo` now crosses one already-open mock port as fragmented HTTP,
leases a fitting cell, incrementally commits the exact JSON body, runs one
explicit transform and output attempt, and returns the exact transformed JSON
through partial response sends. The route retains the terminal egress only
while the response pull source can reach it, pinning the carrier generation
separately from the flow generation used for cancellation and retirement.
Connection cleanup then retires and wipes the exact flow generation, releases
the lease, wipes route-operation storage, and closes the port.

The route and connection owner admit only complete non-overlapping caller
geometry. Body limits, header arenas, receive/send scratch, route capacity,
operation arenas, and execution profiles are supplied by the composition;
there is no process-global request, route, response, connection, admission, or
4 KiB body ceiling.

## Connection isolation and pressure

The closing SR2 landing schedules three independent connection owners over one
sealed router and one mixed two-cell pool. A small request leases the compact
cell and reaches a deliberately stalled response send. An interleaved
4,097-byte request skips that cell, leases the standard cell, crosses the
4,096-byte segment boundary, and reaches its independent response. While both
leases remain active, a third request is refused as HTTP `503` without
acquiring a cell or mutating either active flow. The refusal completes while
both leases remain held.

Cancelling the stalled peer retires only its exact flow generation and cancels
only its port while the successful peer remains live and unchanged; that peer
then completes independently. The gate exits with zero active leases, both
cells idle, empty and wiped carriers and connector-operation workspaces, wiped
route operations, closed successful ports, an exactly cancelled slow port,
preserved connector descriptors, and no event, attempt, payload, response, or
callback-state crossover.

The closing linked gate records 493 guest assertions. The stalled compact
owner takes 60 cooperative owner steps, the 4,097-byte standard owner takes
148, and the refused owner takes 30; peak pool occupancy is two. The complete
one-core emulator run takes 1,325,092,021 checked guest steps in 19.63 seconds
with 128 MiB of external memory. These are deterministic fixture and emulator
observations, not a supported production latency claim.

## Clean prerelease replacement

SR2 removes the old one-slot capacity constants, inline payload fields, inline
operation field, semantic-free descriptor padding, SR1 fixture, and SR1 static
suite in the same cutover. There is no alternate layout, adapter, migration,
deprecation path, old-layout reader, or ABI selector. Runtime descriptors use
only current-build structural checks to reject uninitialized or wrongly sized
caller memory. They are never persisted.

## Qualification

[`test_streams_sr2_runtime.py`](../../../../local_testing/test_streams_sr2_runtime.py)
builds the focused linked image and reaches `STREAMS SR2 RUNTIME PASS`. Its
deterministic fixture requalifies inherited connector, event, transform,
attempt, cancellation, timeout, stale-state, uncertain-effect, and cleanup
truth, then adds:

- exact compact and standard bounds, including a 16,384-byte ingress and its
  one-byte-over refusal;
- fragmented direct ingress whose attempt remains unpublished until commit,
  plus abort, stale-generation, capacity, and cancellation rollback;
- an 8,192-byte transform path producing an 8,195-byte egress;
- segmented append, whole-payload digest, integrity failure, wipe, failed-copy
  scratch cleanup, and cross-segment rollback;
- mixed-profile selection, exact measured memory, two simultaneous leases,
  full-pool/one-over refusal, no-fitting-cell refusal, and stale-lease
  rejection;
- two interleaved flows and shared-connector callback re-entry; and
- pool-metadata, peer-workspace, and partial-connector-overlap rejection; and
- post-terminal payload reads, stale-retirement preservation, and exact
  retirement wipe of both carriers and connector-operation storage.

[`test_web_http_primitives.py`](../../../../local_testing/test_web_http_primitives.py)
qualifies strict fragmented framing, hostile framing refusal, copied routing,
bounded response construction, source faults, partial sends, cancellation,
and completion precedence.
[`test_streams_sr2_http_route.py`](../../../../local_testing/test_streams_sr2_http_route.py)
qualifies the first complete request-to-response journey, including exact
metadata/body transformation, live terminal response-source reads, partial
transport acknowledgement, exact retirement, pool release, operation wipe,
and port close.
[`test_streams_sr2_http_pressure.py`](../../../../local_testing/test_streams_sr2_http_pressure.py)
qualifies the closing interleaved pressure journey: compact and standard
selection, a 4,097-byte exact body, two active leases, one-over `503`, a
stalled/cancelled peer, an independently successful response, and exhaustive
isolation and teardown checks.

[`test_streams_sr2_static.py`](../../../../local_testing/test_streams_sr2_static.py)
keeps both the four-module runtime and HTTP composition dependency closures
storage-free, rejects top-level mutable storage, requires the external
workspace and caller-owned HTTP lifecycle surfaces, proves the SR1 files were
replaced, and rejects prerelease compatibility, migration, deprecation, or ABI
layers.

SR2 earns the bounded runtime portion of `offline-contract`, HTTP
`protocol-framing`, deterministic cooperative transport, and the
request/response form of `bidirectional-flow`, including two-connection
pressure and cancellation. It does not earn applet or Desk composition,
listener/TLS hosting, live connectivity, or hardware parity. It adds no VFS
path, durable queue, spool, outbox, retry record, or other persistence; those
are SR3 work.
