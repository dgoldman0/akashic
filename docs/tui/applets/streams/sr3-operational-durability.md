# Streams SR3 operational durability

**Status:** all three landings are implemented and qualified; SR3 is complete
for its deterministic offline operational-durability boundary

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
the old bank. Operational status distinguishes the exact count of terminal
cleanups whose append-only records have not yet been compacted from completed
physical reclamation; it does not misreport those items as reclaimed bytes or
pages.

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
| Connector configuration | Stable connector identity, positive configuration revision, direction, protocol/profile and one pinned endpoint identity/seal, explicit queue/retry/timeout bounds, declared idempotency contract, lifecycle policy, and an opaque credential reference rather than secret bytes; no allowlist mode is admitted without a durable allowlist authority |
| Flow configuration | Stable flow identity and positive revision, exact connector identities/revisions, one bounded route/transform description, enable state, and admitted operational policy |
| Checkpoint | Connector/flow identity and revision, protocol-specific cursor/resume/subscription value, ordering fact, and the last committed checkpoint identity |
| Outbox attempt | Stable attempt, event, connector, flow, correlation, and idempotency identities; admitted connector/flow revisions, endpoint seal, protocol/profile/media, and receipt policy/limit; payload length, SHA3-256 digest, and `PBLOB`; distinct accepted and current-ready ordering; dispatch/retry counts; current transfer/effect truth; and an optional receipt identity plus checked record reference |
| Receipt | Stable receipt and attempt identities; request seal and payload length/digest; connector/flow identities and revisions; protocol/profile; acknowledgement/delivery identities and times; bounded protocol result; and optional remote receipt/correlation bytes bound by their exact lengths, a digest, and one checked `PBLOB` containing receipt bytes followed by correlation bytes |

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

The one egress-outbox index set has eight bound physical trees: connector
configuration, flow configuration, checkpoints, attempt directory, shared
ready/active dispatch ordering, terminal retention ordering, idempotency, and
shared operational usage. The usage tree has distinct key families. A
connector row carries its retained item count and retained payload bytes; a
flow row carries its active count. The application root separately carries
the global item/payload totals and retained receipt count/bytes. Usage-tree
cardinality is exactly connector-configuration cardinality plus
flow-configuration cardinality, including canonical zero-valued rows.
Root receipt bytes mean the exact logical remote-receipt plus
remote-correlation bytes retained through receipt `PBLOB`s; the fixed
512-byte semantic-record cost is bounded by the shape rather than charged to
that logical byte counter. A connector receipt policy of `NONE` admits the
semantic receipt record needed for local effect truth but requires those
remote-evidence lengths and bytes to remain zero. `BOUNDED` permits remote
evidence only through the exact positive limit snapshotted into the attempt.
The root rejects a receipt count above terminal count, nonzero receipt bytes
with zero receipts, or an active-plus-terminal count above terminal capacity.

Cold open accepts only the current shape and validates the complete reachable
root before exposing configuration, queue counts, payload bytes, or delivery
state. It recomputes connector and flow usage from the reachable attempts and
their states, and requires exact agreement with every persisted usage row and
the root totals. Every attempt that names a receipt must resolve its checked
record reference and match the receipt identity, attempt identity, request
seal, payload facts, configuration identities/revisions, and admitted
protocol/profile; receipt evidence length must also fit the admitted receipt
limit. A retained attempt or checkpoint, and a temporarily stale flow
reference, may name a positive revision less than or equal to the current
same-ID configuration: a lower revision is valid historical/stale truth that
hot authorization refuses, while a revision above the current configuration
is an impossible future reference and therefore corruption. Unknown kinds,
unknown shapes, malformed lengths, nonzero reserved
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

Hot admission reads and transactionally updates the persisted connector usage
row rather than rescanning retained attempts. Flow active usage is likewise
updated with the state transition that acquires or releases active work. The
full cold-open recomputation is the integrity proof for those hot-path
counters, not an alternate source of live authority.

One `PSTORE` transaction forms the acceptance boundary. It must:

1. write and transactionally validate the exact payload through `PBLOB`;
2. encode the stable attempt identity and semantic outbox record that names
   that blob, exact length, digest, destination, configuration revisions,
   correlation, and idempotency facts;
3. update the required ordered indexes, global capacity counters, and exact
   connector usage row; and
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

Accepted ordering is immutable admission history. Ready ordering is a distinct
monotonic sequence allocated on initial admission and again on every requeue;
a retry therefore joins the current tail and cannot regain its original queue
priority.

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

Capacity reporting therefore exposes current retained item count, current
retained logical payload bytes, configured ceilings, whether admission is full
by either dimension, the exact cleanup-failed terminal count, and the exact
uncompacted-cleanup count. Reclaim reports retired/reusable B+tree pages
separately. Storage damage, unknown format, uncertain publication, and cleanup
uncertainty remain distinct from ordinary full capacity.

## Reviewable landing sequence

SR3 is divided into three informative landings. Each landing advanced the one
current implementation directly, and closeout removed displaced prerelease
paths rather than preserving parallel implementations.

### Landing 1 — Current outbox shape and atomic admission — qualified

Implement the Streams persistence adapter, current root and semantic codecs,
one egress-outbox index set, exact payload snapshot, global and per-connector
item/byte counters, and
single-transaction acceptance boundary. Qualify exact-full and each one-over
case, interrupted publication, cold open, current-shape validation, corrupt
records, unknown shape, and no partial payload/attempt visibility.

This landing may report only durable local acceptance. It does not claim
dispatch, remote delivery, automatic retry, receipts, or completed retention.

The current-shape codecs, eight-tree authority, exact `PBLOB` snapshots,
single-transaction admission, capacity boundaries, interrupted publication,
and cold semantic/physical audits are implemented in the standalone
operational spool. The focused admission gate passes 704 assertions in
2,877,337,637 guest steps and 74.53 seconds; the record gate passes in
734,515,713 guest steps.

### Landing 2 — Recovery and delivery evidence — qualified

Add durable active/terminal transitions, effect truth, exact-byte dispatch,
receipts, restart classification, stale-revision refusal, and the declared
safe-idempotency retry rule. Qualify crash points before effect, after effect
but before acknowledgement publication, and after receipt publication;
exact retry bytes; same-key idempotent retry; no automatic unsafe retry; and
operator-visible indeterminate work.

This landing proves the durable attempt lifecycle against deterministic mock
connectors. It does not by itself claim Desk hosting, live connectivity, or
physical retention completion.

The spool now selects the oldest ready attempt, revision-checks activation,
persists monotonic effect truth and deterministic receipts, streams the exact
payload and remote evidence, safely requeues only the same attempt under exact
idempotency, refuses stale configuration, and converts cold active work into
visible indeterminate truth. The final focused delivery/recovery/cleanup gate
passes 415 assertions in 3,108,360,905 guest steps and 78.96 seconds,
including transaction cleanup on flow saturation, cross-record evidence-time
refusal, convergence replay without reinvoking the receipt source, unsafe
retry refusal, terminal cleanup, and final cold receipt preservation.

### Landing 3 — SR2 composition and finite retirement — qualified

Compose one exact SR2 egress result into outbox acceptance without persisting
runtime descriptors. Dispatch accepted work through a fitting active cell,
preserve active-pool/outbox backpressure independence, and complete terminal
retention, logical cleanup, reclaim, and bounded compaction. Qualify cold
restart across the composed journey, outbox-full behavior while runtime cells
are free, runtime-full behavior while the outbox remains authoritative,
receipt inspection, and truthful physical retirement.

The caller-owned operational dispatcher now snapshots one exact SR2
output-ready result into durable acceptance, validates durable authority before
runtime acquisition, dispatches through a fitting active cell, and preserves
independent runtime-pool and outbox pressure. Terminal retirement selects the
oldest policy-eligible item, pins cleanup failures and uncertain effects,
enforces oldest-safe order under terminal-count pressure, and removes the
selected attempt with its terminal, idempotency, and usage rows in one
revision-checked publication. Item, payload, receipt, remote-evidence,
connector-usage, cleanup-failure, and uncompacted-cleanup counters remain exact
across cold open.

The finite caller-owned compactor consumes only the current operational shape.
It walks the four primary families, copies live payload and receipt blobs
incrementally, and derives all dispatch, terminal, idempotency, and usage
indexes into the inactive bank. In the composed qualification, bank 0 begins
with nonempty page and segment files while bank 1 is empty. The bounded build
takes more than one step and copies more than the surviving 4,097-byte payload;
finalize, publish, mirror, and cleanup advance the durable generation exactly
once, select bank 1, leave bank 1's page and segment files nonempty, and remove
all physical bytes from bank 0's page and segment files. A normal cold open
then adopts bank 1 and passes the physical audit with the cleaned attempt
absent, two terminal attempts and 4,104 payload bytes retained, one zero-byte
remote receipt, one cleanup-failed terminal, no active or ready work, and zero
uncompacted cleanups.

The composed gate passes 401 assertions in 3,073,739,777 guest steps and
89.28 seconds on its first boot, then 348 assertions in 3,771,120,192 guest
steps and 102.19 seconds in a fresh cold process. The structural gate passes
22 checks. Every linked gate ran sequentially with one guest core, 128 MiB of
external memory, and its checked-in 4,000,000,000-step ceiling.

## Sequential qualification plan

Qualification proceeds from cheap structural evidence to focused linked
emulator evidence. Test suites are never run in parallel.

All five stages below are qualified.

1. Host/static checks cover dependency closure, current-shape-only codecs,
   pointer-free records, exact constants, and no observation-repository
   imports.
2. The focused atomic-admission gate covers fresh provision, exact-full and
   one-over capacity, interrupted publication, corrupt/unknown state, and cold
   root selection.
3. The focused recovery/delivery gate covers every attempt/effect state,
   exact retry bytes, receipts, idempotency, cancellation, staleness, and
   visible indeterminate work, plus terminal-order cleanup, pinned uncertainty,
   exact counter/index deletion, and cold reduced-live-set reconciliation.
4. The composed SR2-to-outbox restart gate covers independent runtime
   and durable capacity pressure, terminal cleanup, reclaim, and finite
   physical compaction.
5. The architecture inventory and milestone closeout checks run after the
   focused gates pass.

Each linked gate uses one worker, checked-in step and memory ceilings, bounded
fixtures, and measured guest steps and workspace/storage cost. Heavy gates run
sequentially. Live network, Desk, and hardware witnesses are not substitutes
for deterministic fault and restart evidence and remain unearned unless
separately qualified.

## SR3 exit

SR3 meets its exit: cold restart either resumes accepted work or truthfully
terminalizes it; exact retry bytes and receipts survive restart; indeterminate
effects follow the connector's declared idempotency rule; and full, damaged,
unknown-format, uncertain-publication, cleanup, and finite physical-retirement
states are reported without silent loss. Queued payload remains an operational
Streams snapshot and is never presented as a Library document.

This completion does not make `streams.f` require the operational modules,
expose them as an applet capability, host them through Desk, or award live
HTTP/TLS, live-connectivity, hardware-parity, or SR6 production
workload/profile evidence.
