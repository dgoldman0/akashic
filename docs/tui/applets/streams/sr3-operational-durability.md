# Streams SR3 operational durability

**Status:** implementation contract fixed; SR3 implementation and
qualification are in progress

**Scope:** one bounded durable egress outbox over the neutral persistence
substrate, with exact payload snapshots, restart and delivery truth, receipts,
and finite retention

**Qualified predecessor:**
[`sr2-runtime-shape.md`](sr2-runtime-shape.md)

**Normative product contract:**
[`information-integration.md`](information-integration.md)

**Controlling sequence:**
[Streams architectural reset handoff](../../../../../STREAMS_ARCHITECTURAL_RESET_HANDOFF.md)

## Milestone boundary

SR2 already qualifies the caller-owned active-cell pool, segmented payload
carriers, exact attempt/effect distinctions, and cooperative HTTP
request-to-response journey. It deliberately adds no durable queue, retry
record, VFS path, or restart behavior. Those completed SR2 properties are
inputs to this milestone, not evidence that SR3 is complete.

SR3 adds only the operational persistence needed to continue, deliver,
reconcile, and inspect bounded flows. The first durable slice is one egress
outbox. It is not a document repository, an observation corpus, an archive,
or a general workflow database. An ingress queue may later use the same
contract, but it is not required to prove this first slice and must not be
simulated by changing the meaning of the egress records.

The durable spool and the active-cell pool are separate authorities:

- an SR2 cell owns one currently executing transfer and its caller-supplied
  live workspaces;
- the SR3 outbox owns accepted semantic work across process lifetime; and
- dispatch temporarily acquires exact durable work into a fitting active cell
  without persisting the cell, carrier, operation workspace, callback, or any
  other runtime address.

Increasing either capacity does not increase the other. A full active pool
pauses or refuses dispatch while accepted outbox work remains durable. A full
outbox refuses new durable acceptance even when an active cell is free.

## Neutral substrate and Streams ownership

The outbox is a Streams consumer of the existing neutral
[`persistence/`](../../../../akashic/persistence/) substrate:

- `PSTORE` supplies checked page/segment storage, one transactional proposal,
  and A/B checked-root publication;
- the copy-on-write B+tree supplies bounded ordered indexes;
- `PBLOB` stores an exact payload as immutable checked chunks and a manifest;
- reclaim tracks pages retired by committed index/root replacement; and
- bounded two-bank compaction is the physical path for removing unreachable
  records and payload chunks from finite storage.

These layers do not acquire Streams vocabulary or policy. Streams supplies
its own paths, current application-root encoding, semantic record encoders,
index keys, capacity counters, retention rules, recovery decisions, and
dispatch policy. Reusing this substrate does not revive or rename the rejected
four-tree source/observation repository.

Logical deletion alone is not a claim that disk space was recovered. Removing
an outbox item makes its semantic records and blob unreachable in a committed
Streams root and retires replaced B+tree pages through reclaim. Segment
records and blob chunks become physically reusable only after a bounded
compaction publishes a new bank containing the live set and safely retires
the old bank. Operational status must distinguish logical terminal cleanup,
pending physical retirement, and completed physical reclamation.

## Pointer-free semantic state

All durable records are encoded from values. They may contain stable local
identities, revisions, bounded strings or byte fields, digests, lengths,
ordinals, timestamps, state/reason codes, and neutral persistent references.
They never contain Forth addresses, runtime descriptor images, active-cell
leases or generations, carrier segment tables, callback execution tokens,
VFS descriptor addresses, or borrowed spans.

The current durable model has the following semantic families:

| Record | Required meaning |
| --- | --- |
| Connector configuration | Stable connector identity, positive configuration revision, direction, protocol/profile and admitted endpoint policy, explicit queue/retry/timeout bounds, declared idempotency contract, lifecycle policy, and an opaque credential reference rather than secret bytes |
| Flow configuration | Stable flow identity and positive revision, exact connector identities/revisions, one bounded route/transform description, enable state, and admitted operational policy |
| Checkpoint | Connector/flow identity and revision, protocol-specific cursor/resume/subscription value, ordering fact, and the last committed checkpoint identity |
| Outbox attempt | Stable attempt, event, connector, flow, correlation, and idempotency identities; configuration revisions; exact destination/protocol/media facts; payload length, SHA3-256 digest, and `PBLOB` descriptor; accepted ordering; current transfer/effect truth; reason/detail; and retention state |
| Receipt | Exact attempt identity, acknowledgement/delivery identity and time, bounded protocol result, remote correlation or receipt bytes when present, and the payload identity/digest to which it applies |

Connector and flow records are operational configuration, not authored
documents. Checkpoints are continuation facts, not content history. Attempts
and receipts are bounded delivery evidence, not a searchable publication
archive. Fields not needed for configuration, continuation, delivery,
reconciliation, or bounded inspection do not belong in these formats.

## One current durable shape

The Streams application root and every semantic record identify one exact
current shape with a Streams-specific kind, exact encoded length, required
reserved-zero fields, and an integrity check or checked containing record as
appropriate. The root also names the exact index roots, current counters,
capacity policy, retention state, and store identity needed to validate the
complete authority.

Cold open accepts only the current shape and validates the complete reachable
root before exposing configuration, queue counts, payload bytes, or delivery
state. Unknown kinds, unknown shapes, malformed lengths, nonzero reserved
fields, invalid enum values, counter/index disagreement, bad blob
descriptors, corrupt checked records, and invalid references fail closed as
damaged or unknown-format state. They are never treated as an empty outbox and
never skipped as if the affected work did not exist.

This is self-identification for validation, not a compatibility ladder. Before
the first supported release, changing the shape atomically replaces this
prototype and its fixtures. No old-shape reader, schema selector, migration
service, dual write, fallback decoder, or legacy record remains. If real
user-created prototype data is later found, it is explicitly inventoried and
exported before replacement rather than silently imposing a permanent reader.

## Capacity and exact acceptance

The caller configures independent positive limits for:

- outbox items, counting every accepted item until its committed logical
  retirement; and
- exact logical payload bytes, summing the snapshotted payload length of every
  such item.

Fixed maximum semantic-record sizes and bounded indexes make the non-payload
storage cost per retained item explicit. Terminal records and receipts remain
inside item/retention policy until cleanup commits; merely reaching a terminal
state does not create uncounted storage.

Admission preflights both counters with overflow-safe arithmetic before
starting publication. The item that reaches both limits exactly is accepted.
The next item, a one-byte payload over the remaining byte allowance, or an
item-count one-over is refused as capacity with no attempt identity exposed,
no accepted status, and no mutation of current authority. Item capacity and
byte capacity are tested independently as well as together.

One `PSTORE` transaction forms the acceptance boundary. It must:

1. write and transactionally validate the exact payload through `PBLOB`;
2. encode the stable attempt identity and semantic outbox record that names
   that blob, exact length, digest, destination, configuration revisions,
   correlation, and idempotency facts;
3. update the required ordered indexes and both capacity counters; and
4. publish one new validated Streams application root.

The API reports **durably accepted** only after the complete proposal is known
to be the selected durable root. A prepublication failure leaves the previous
root authoritative. A maybe-effect publication result is not rewritten as
accepted or rejected from volatile state: the live owner reports uncertain
publication and cold recovery selects and validates the independently checked
root. Recovery then observes either the complete old state with no attempt or
the complete new state with payload and attempt together. It must never expose
an attempt without its exact snapshot, a snapshot without its attempt and
capacity charge, or a partially updated index.

Accepted means only that Streams has durably accepted the declared local work.
It never means that a remote effect began, succeeded, or was acknowledged.

## Dispatch, effect, and retry truth

Recovery and dispatch preserve at least these visible states:

| State | Durable truth |
| --- | --- |
| Accepted | The exact payload snapshot and attempt identity are committed locally; no remote success is implied |
| Active | Dispatch of that exact attempt began under the recorded connector/flow revisions |
| Acknowledged/delivered | The declared effect and its bounded receipt are committed |
| Failed before effect | The connector established that no external effect occurred |
| Failed after known effect | The connector established that the effect occurred even though later transport or cleanup failed |
| Cancelled | Cancellation truth is committed without erasing any stronger effect evidence |
| Stale | The recorded connector/flow revision no longer authorizes dispatch; the item is not silently retargeted |
| Indeterminate | A crash, cancellation, transport loss, or missing acknowledgement leaves external-effect truth uncertain |

Primary delivery/effect truth is monotonic. Later cleanup failure is recorded
separately and cannot downgrade known delivery to failure or uncertainty. A
lost acknowledgement or interrupted active dispatch is not rewritten as
“not sent.” Cold recovery turns any item whose pre-crash effect cannot be
proved into visible indeterminate work unless durable protocol evidence
already establishes a stronger terminal state.

Every retry names the original immutable payload length, digest, `PBLOB`
snapshot, attempt identity, destination, correlation, and idempotency facts.
It never follows a newer Library/Pad revision, a newer transient carrier, or
a changed connector revision. A stale configuration requires an explicit new
attempt under the new revision rather than retargeting the old one.

An indeterminate effect is not automatically retried by default. Automatic
retry is permitted only when the recorded connector configuration declares a
safe idempotency contract for that exact operation and the retry preserves the
same admitted idempotency identity. Under that declaration, remote
deduplication and the durable receipt/state transition must prevent a
committed effect from being duplicated. Without it, the item remains
operator-visible for reconciliation or an explicitly reviewed new action.

## Retention, cleanup, and finite storage

Terminal retention is explicit and bounded by policy, not an incidental
side-effect of queue processing. Policy determines which terminal states are
retained, their maximum count and/or age, when receipts may be removed, and
which indeterminate or cleanup-failed items remain pinned for operator
attention. Indeterminate work is never silently expired as successful,
failed-before, or absent.

Cleanup is another committed state transition. It first removes the item and
its secondary index entries from the current application root, decrements the
exact item and payload-byte counters, and records any required cleanup truth.
Only then may the attempt record, receipt, and blob be unreachable. Reclaim
handles retired pages under its two-root fence; compaction later copies the
bounded live set and physically retires unreachable segment/blob storage.

Capacity reporting therefore exposes at least current retained item count,
current retained logical payload bytes, configured ceilings, whether
admission is full by either dimension, logical cleanup backlog, and physical
retirement/compaction state. Storage damage, unknown format, uncertain
publication, and cleanup uncertainty remain distinct from ordinary full
capacity.

## Reviewable landing sequence

SR3 is divided into three informative landings. A later landing may refine the
current prerelease implementation directly; it must not leave a parallel
prototype or compatibility seam behind.

### Landing 1 — Current outbox shape and atomic admission

Implement the Streams persistence adapter, current root and semantic codecs,
one egress-outbox index, exact payload snapshot, item/byte counters, and
single-transaction acceptance boundary. Qualify exact-full and each one-over
case, interrupted publication, cold open, current-shape validation, corrupt
records, unknown shape, and no partial payload/attempt visibility.

This landing may report only durable local acceptance. It does not claim
dispatch, remote delivery, automatic retry, receipts, or completed retention.

### Landing 2 — Recovery and delivery evidence

Add durable active/terminal transitions, effect truth, exact-byte dispatch,
receipts, restart classification, stale-revision refusal, and the declared
safe-idempotency retry rule. Qualify crash points before effect, after effect
but before acknowledgement publication, and after receipt publication;
exact retry bytes; same-key idempotent retry; no automatic unsafe retry; and
operator-visible indeterminate work.

This landing proves the durable attempt lifecycle against deterministic mock
connectors. It does not by itself claim Desk hosting, live connectivity, or
physical retention completion.

### Landing 3 — SR2 composition and finite retirement

Compose one exact SR2 egress result into outbox acceptance without persisting
runtime descriptors. Dispatch accepted work through a fitting active cell,
preserve active-pool/outbox backpressure independence, and complete terminal
retention, logical cleanup, reclaim, and bounded compaction. Qualify cold
restart across the composed journey, outbox-full behavior while runtime cells
are free, runtime-full behavior while the outbox remains authoritative,
receipt inspection, and truthful physical retirement.

Closeout updates the architecture inventory and milestone ledger only after
all required gates pass. It removes any displaced prerelease path rather than
preserving a second implementation.

## Sequential qualification plan

Qualification proceeds from cheap structural evidence to focused linked
emulator evidence. Test suites are never run in parallel.

1. Run host/static checks for dependency closure, current-format-only codecs,
   pointer-free records, exact constants, no observation-repository imports,
   and no compatibility or legacy reader.
2. Run the focused atomic-admission gate for fresh provision, exact-full and
   one-over capacity, interrupted publication, corrupt/unknown state, and cold
   root selection.
3. Run the focused recovery/delivery gate for every attempt/effect state,
   exact retry bytes, receipts, idempotency, cancellation, staleness, and
   visible indeterminate work.
4. Run the composed SR2-to-outbox restart gate, including independent runtime
   and durable capacity pressure, terminal cleanup, reclaim, and finite
   physical compaction.
5. Run the architecture inventory and milestone closeout suites after the
   focused gates pass.

Each linked gate uses one worker, checked-in step and memory ceilings, bounded
fixtures, and measured guest steps and workspace/storage cost. Heavy gates run
sequentially. Live network, Desk, and hardware witnesses are not substitutes
for deterministic fault and restart evidence and remain unearned unless
separately qualified.

## SR3 exit

SR3 is complete only when a cold restart either resumes accepted work or
truthfully terminalizes it; exact retry bytes and receipts survive restart;
indeterminate effects follow the connector's declared idempotency rule; and
full, damaged, unknown-format, uncertain-publication, and cleanup states are
reported without silent loss. Queued payload remains an operational Streams
snapshot and is never presented as a Library document.

Until the three landings and sequential gates above are complete, this file is
the implementation contract and plan. It does not award SR3, live
connectivity, live Desk, or hardware-parity evidence.
