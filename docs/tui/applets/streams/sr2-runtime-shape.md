# Streams SR2 bounded runtime shape

**Status:** first SR2 landing complete; cooperative HTTP and final
isolation/pressure qualification remain

**Qualified:** 2026-07-25

**Implementation:**
[`runtime-profile.f`](../../../../akashic/tui/applets/streams/runtime-profile.f),
[`payload-carrier.f`](../../../../akashic/tui/applets/streams/payload-carrier.f),
[`flow-core.f`](../../../../akashic/tui/applets/streams/flow-core.f), and
[`execution-pool.f`](../../../../akashic/tui/applets/streams/execution-pool.f)

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
cleanup error. Terminal work remains immutable until its exact generation is
retired.

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

The 1,904-byte flow descriptor contains event and attempt metadata but no
inline body buffer and no inline connector-operation buffer. Capacity changes
therefore change caller-supplied workspaces, not every flow descriptor.

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
- pool-metadata, peer-workspace, and partial-connector-overlap rejection.

[`test_streams_sr2_static.py`](../../../../local_testing/test_streams_sr2_static.py)
keeps the four-module dependency closure storage-free, rejects top-level
mutable storage, requires the external workspace surface, proves the SR1 files
were replaced, and rejects prerelease ABI, compatibility, migration, adapter,
reader, version, or semantic-free reserved-padding layers.

This landing earns the bounded runtime portion of `offline-contract` and
requalifies the standalone/mock form of `bidirectional-flow`. It does not yet
earn HTTP `protocol-framing`, cooperative transport, applet or Desk
composition, live connectivity, or hardware parity. It adds no VFS path,
durable queue, spool, outbox, retry record, or other persistence; those remain
SR3 work after SR2 establishes the HTTP runtime behavior.
