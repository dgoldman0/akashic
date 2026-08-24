# Akashic retained-presentation service contract

Status: normative for the Phase 3 Akashic retained-presentation service.

This document defines the high-level Akashic API, storage, ownership, and
lifecycle contract for retained presentation. It does not define APT-1 byte
encoding. The mirrored `APT-1-WIRE.md` and `APT-1-OWNERSHIP.md` define the
terminal protocol identity, transaction, reset, and retirement rules.

The transactional cell plane remains independently specified by
`AKASHIC-CELL-BACKEND.md`. Retained presentation is an additive object plane;
it does not replace the cell screen or the ANSI fallback.

## 1. Scope and authority

Desk owns one presentation service, called the broker, for one live Desk
activation. The broker is a high-level Akashic service over the optional APT
session. It is not part of KDOS, does not exist merely because Akashic was
loaded, and is installed only by the explicit rich Desktop composition.

The broker is global to Desk and is discoverable through Desk's existing
global `IEND.SERVICE-XT` service endpoint under the exact identifier:

```text
org.akashic.tui.presentation.v1
```

There is no endpoint per applet. In the `desktop-apt1` composition, discovery
returns the same broker to every eligible caller whether the attached terminal
accepted or declined the retained feature query. Discovery alone grants no
presentation owner and no object mutation authority. A child must acquire an
opaque activation-scoped scope as defined below.

The broker and terminal tree are projections of Akashic application state.
They are not durable application data. A terminal reset, broker replay, or
lost terminal cache must not change SoundLab PCM, metrics, documents, resource
owners, UIDL state, or any other domain state.

The public child API never exposes or accepts:

* a `PT-SESSION` pointer;
* a session ID or presentation epoch;
* a terminal owner ID or owner generation;
* a terminal region, object, or resource ID;
* a raw protocol opcode, frame, or transaction buffer; or
* another applet's scope.

Applications use activation-local scene keys inside an opaque scope. The
broker maps those keys to terminal identities internally.

## 2. Status values

The service uses these stable ordinary status values:

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `PRES-S-OK` | The operation was accepted. |
| 1 | `PRES-S-WOULD-BLOCK` | No downstream progress is currently possible; retry after advancing the owning service. |
| 2 | `PRES-S-UNAVAILABLE` | No usable negotiated retained-presentation backend exists. |
| 3 | `PRES-S-CAPACITY` | Caller-owned or negotiated capacity cannot admit the operation. |
| 4 | `PRES-S-STALE` | The scope, source revision, or activation binding is no longer current. |
| 5 | `PRES-S-INVALID` | An argument, descriptor, alias, state transition, or callback result is invalid. |
| 6 | `PRES-S-SESSION-LOST` | The enhanced session crossed a structural loss boundary. |
| 7 | `PRES-S-SOURCE` | A retained resource or series provider failed. |

Status returns do not throw through an applet callback. A broker keeps a
sticky first non-transient service error for host inspection. One failed
scope or provider does not authorize mutation of another scope and does not
make raw ANSI output safe after a post-`OPEN` session loss.

`PRES-S-WOULD-BLOCK` is transport progress state, not local scene-capacity
failure. A committed local update remains committed while downstream work is
blocked. `PRES-S-CAPACITY` is fail-before-mutation.

## 3. Discovery and caller-aware acquisition

An applet obtains the global broker through its own live `CINST`:

```forth
S" org.akashic.tui.presentation.v1" instance CINST-SERVICE
    ( -- broker | 0 )
```

Zero means that the composition has no retained broker, as on the baseline
ANSI Desktop. It does not mean that a rich composition's attached hardware
declined retained features: `desktop-apt1` still returns its broker in that
case, and acquisition returns `PRES-S-UNAVAILABLE`.

The only child acquisition operation is:

```forth
PRES-SCOPE-ACQUIRE  ( caller-instance broker -- scope status )
```

Acquisition returns zero and `PRES-S-UNAVAILABLE` without consuming an owner
record when the settled discovery result did not enable RETAINED-1. A
supporting terminal may advertise only a subset of the optional retained
families; acquisition then succeeds, while a batch requiring an absent
high-level kind fails before local mutation with `PRES-S-UNAVAILABLE`.

Acquisition is caller-aware even though broker discovery is global. Desk must
atomically verify all of the following before returning a nonzero scope:

1. `caller-instance` is a valid live `CINST` registered in this exact Desk;
2. its endpoint is this Desk's endpoint;
3. it maps to one live `AHOST` child slot;
4. the slot still names the exact `CINST.ID` and `CINST.GENERATION`;
5. an exact existing scope can be returned idempotently, otherwise no scope
   already owns that activation; and
6. for a new scope, one preallocated owner record is available.

The returned scope is a borrowed opaque handle. Internally it is bound to the
exact `CINST.ID`, `CINST.GENERATION`, broker, and stable Desk presentation
region. None of those fields has a public child accessor. Repeating acquire
for the same live caller returns the same scope and `PRES-S-OK`; it does not
allocate a second terminal owner.

The CINST tuple is the Akashic authority binding. The broker separately maps
it to private wire owner/generation values and may rotate those projection
values when the wire ownership/reset contract requires it. Rotation never
changes the child scope or grants a second Akashic activation authority.

The scope is valid only until Desk begins exact-owner retirement. An applet
may store it only in that activation's component state. It must not persist
the handle, copy its representation into domain data, or use it after its
shutdown callback returns.

No scene operation accepts a caller instance, owner pair, sibling selector,
or region identifier. Possession of a valid scope is the whole child-side
authority. The normal applet API therefore has no operation with which to
name a sibling's presentation namespace.

## 4. Service construction and caller-owned storage

The optional composition constructs the broker with:

```forth
PRES-SERVICE-INIT  ( config broker -- status )
PRES-SERVICE-FINI  ( broker -- status )
PRES-SERVICE-STATUS@ ( broker -- status )
```

`PRES-SERVICE-STATUS@` is the host-side accessor for the broker's sticky first
non-transient service error. It does not clear the error or advance transport.

`config` names the APT adapter and the following caller-owned spans and
capacities:

* activation owner records;
* retained item records;
* retained resource records;
* copied definition, style, label/unit text, and polyline-point bytes;
* copied dynamic value/update records;
* transaction operation records and copied transaction bytes; and
* one resource-or-series chunk staging span.

The implementation publishes exact record sizes and a configuration record
size. Counts and byte lengths are independent. A product profile selects them
from its intended concurrent rich applets and negotiated remote budgets; the
generic service contains no hidden object-per-child, string, history, image,
or resend-queue limit.

Initialization performs a complete preflight before writing any caller byte.
It checks:

* nonzero required capacities and the validity of zero optional capacities;
* checked multiplication of record size by record count;
* non-null, nonwrapping spans;
* required alignment;
* pairwise disjointness of the broker, configuration, every owned span, the
  borrowed PT session, its RX/TX/event buffers, and the APT shell adapter; and
* compatibility with the negotiated object, resource, frame, transaction,
  history, and chunk budgets.

Any failure returns `PRES-S-CAPACITY` or `PRES-S-INVALID` without clearing,
partially initializing, or retaining a supplied span. After successful init,
the broker performs no heap or XMEM allocation. `STEP`, reset replay, owner
retirement, and finalization use only these admitted spans.

The service never archives raw frames or an unbounded change history. Retained
item records hold the latest committed projection recipe. Pending scalar state
coalesces in those records. A resource or sample chunk is copied into the one
staging span only for the duration required by the transport contract.

`PRES-SERVICE-FINI` succeeds only when no live scope remains and either every
retirement obligation is acknowledged or the underlying session has been
safely retired/reset such that its terminal model cannot survive. Refusal
leaves the complete broker and storage valid for retry. It never clears an
uncertain owner tombstone.

## 5. Descriptor ABI

Scene mutation is descriptor based. Every public descriptor begins with an
ABI version, exact descriptor size, descriptor kind, and zero-reserved fields.
Each record family has a public `*-SIZE` constant and `*-INIT` word:

```text
PRES-BATCH-DESC-SIZE       PRES-BATCH-DESC-INIT
PRES-ITEM-DESC-SIZE        PRES-ITEM-DESC-INIT
PRES-RESOURCE-DESC-SIZE    PRES-RESOURCE-DESC-INIT
PRES-SERIES-DEF-DESC-SIZE  PRES-SERIES-DEF-DESC-INIT
PRES-SCALAR-DESC-SIZE      PRES-SCALAR-DESC-INIT
PRES-SERIES-SOURCE-DESC-SIZE PRES-SERIES-SOURCE-DESC-INIT
PRES-VISIBILITY-DESC-SIZE  PRES-VISIBILITY-DESC-INIT
PRES-DROP-DESC-SIZE        PRES-DROP-DESC-INIT
```

Unknown ABI versions, undersized records, nonzero reserved fields, unknown
kinds, invalid enum values, arithmetic overflow, and overlapping source and
service storage return `PRES-S-INVALID` before mutation.

Except for an explicitly declared resource or series provider context, every
descriptor is call-borrowed. The broker validates and copies every retained
field before the operation returns. It never retains caller pointers to
labels, styles, polyline points, unit text, scalar values, or update
descriptors.

### 5.1 Batch descriptor

A batch descriptor declares exact counts for item, resource, and series
definitions; scalar, series-source, and visibility updates; and drops, plus
the exact number of descriptor-owned bytes that must be copied. These
declarations let `BEGIN` reserve the complete local transaction before
accepting its first operation. A valid operation matching an admitted batch
cannot later fail merely because a hidden staging array filled up.

The first batch for a new scope also declares that owner's lifetime quotas for
items, resources, series, immutable resource bytes, sample slots, UTF-8 bytes,
operations per terminal transaction, and terminal transaction bytes. The
scope has exactly one Desk-owned region, so the broker adds that required
region reservation; the child cannot create or enlarge a region quota. The
broker validates the complete reservation against its caller-owned remaining
capacity and the negotiated terminal maxima. Successful first commit freezes
it for that scope and later work may consume but not silently enlarge it. This
lets the application select an honest product capacity without adding a
hard-coded broker default. Scope acquisition itself has no wire side effect;
the broker opens the private wire owner from this admitted first-scene quota.

### 5.2 Item definition descriptor

An item definition contains:

* a nonzero activation-local `scene-key`;
* a zero root or existing group `parent-key`;
* a semantic kind;
* region-relative bounds;
* presentation-only flags and style; and
* kind-specific copied definition data.

Initial Phase 3 kinds are group, polyline, image, label, readout, meter,
status, plot, and waveform. Closed polylines express the first vector outline
shapes. These are high-level scene kinds, not wire opcodes.

Geometry is relative to the owning Desk region or parent group. Descriptor
coordinates use unsigned `UNORM32`: `0` is the left/top edge and
`0xffffffff` is the right/bottom edge. Bounds are stored as left, top, right,
and bottom with `left < right` and `top < bottom`. Polyline points are UNORM32
relative to their object's bounds. This preserves the complete retained wire
precision; the broker must not truncate through a narrower intermediate
format. Desk relayout changes only the owning region's physical bounds; it
does not rewrite item geometry or keys.

`PRES-ITEM-DEFINE` creates a missing key or replaces the complete static
definition of an existing key of the same semantic kind. Replacing an item
with a different kind requires an explicit drop in an earlier committed
batch. A parent must be the root or a group in the resulting committed scene,
and grouping must remain acyclic.

### 5.3 Resource definition descriptor

A resource definition contains a nonzero activation-local resource key,
resource format, width, height, exact byte length, SHA3-256 content digest,
source revision, and a bounded pull provider. Retained-1 format 1 is raw
row-major sRGB straight-alpha RGBA8 with no row padding, and byte length is
checked `width * height * 4`. Items refer to the activation-local resource key;
they never receive a terminal resource ID.

The resource provider contract is:

```forth
read  ( offset max-bytes destination destination-u expected-revision context
        -- produced status )
```

The provider writes at most `max-bytes` contiguous bytes beginning at the
exact requested offset into broker-owned staging. It is bounded,
nonallocating, nonreentrant, and returns stale without output when the
requested revision is no longer authoritative. The broker retains no returned
resource pointer. A successful callback must make progress: `produced` is
positive unless the exact requested offset is already the declared byte
length, and zero before that point is `PRES-S-SOURCE`. During ordinary
operation the application keeps the exact resource bytes reproducible until
it commits a replacement, drops the resource, or enters the synchronous
shutdown/retirement interval described for series providers below.

The image format and dimensions must fit the negotiated terminal
profile and the local chunk/storage configuration. Replacing a resource is
atomic at its resource key. A failed or interrupted transfer leaves the last
committed terminal resource usable until replacement commits, or causes a
new-epoch replay after reset.

That high-level replacement never reuses or replaces a wire resource ID. The
broker allocates a fresh strictly increasing wire ID in the same private owner
generation, uploads the complete candidate, and first obtains its successful
digest-checked `RESOURCE_COMMIT`. It then atomically `OBJECT_REPLACE`s every
surviving image reference from the old ID to the new ID in one presentation
transaction. Only after that transaction succeeds does it `RESOURCE_DROP` the
now-unreferenced old ID. The broker retains the old materialized mapping and
model throughout a failed provider read, upload, digest commit, or object
transaction, so the previous image remains visible. The scope's frozen
resource-count and byte quotas must cover the declared peak old/new overlap;
insufficient overlap capacity rejects the replacement before local mutation.

### 5.4 Scalar descriptor

A scalar update contains an existing readout, meter, or status item key and
one signed 64-bit value. Readout formatting/scale/unit, meter range, and status
shape/colors are static definition fields. The scalar record and value are
copied before return and retain no applet scratch pointer. Meter values outside
the statically declared range are rejected before commit.

The newest committed scalar for an item property is authoritative. The broker
may coalesce an older unsent value with a newer committed value, but it may not
cross an owner generation or reorder around an item definition/drop.

### 5.5 Series definition, source, and provider

A series definition contains a nonzero activation-local series key, positive
history capacity, timestamp mode, and uniform interval where applicable. A
plot or waveform item definition names that series key. The broker maps it to
a terminal series identity internally. Definition capacity must fit both the
caller's reserved sample policy and the negotiated terminal history bound.

A series-source update installs the current complete replayable history for an
existing series. It contains the series key, a nonzero monotonically
increasing source revision, exact current sample count, matching timestamp
mode/time-axis metadata, and one provider XT/context pair.

The provider contract is:

```forth
read  ( first max-count destination destination-u expected-revision context
        -- produced status )
```

The broker owns `destination` and calls the provider only from bounded
`PRES-SERVICE-STEP`. `max-count` is derived from the caller-owned staging span
and the negotiated message limit. Samples are signed 64-bit values; explicit
timestamp mode writes complete timestamp/value records and uniform mode writes
values for the declared first timestamp and interval. `first` is the
zero-based index into the descriptor's complete current history. The provider
must:

* perform bounded, nonblocking work without allocation;
* write exactly `produced` complete samples into `destination`;
* return `produced <= max-count`;
* return a positive `produced` until the declared sample count is exhausted;
* return `PRES-S-STALE` without output if `expected-revision` is no longer
  authoritative; and
* never call back into the broker.

The broker copies the produced samples before the callback returns and retains
no sample pointer. It may retain the provider XT/context only while the exact
scope is serviceable. During ordinary operation the application must keep the
source capable of reproducing the descriptor's complete declared history
until it commits a newer revision or the scope is retired. This is what makes
reset replay possible without a shadow raw-frame archive. Applet shutdown is
a synchronous quiescent interval: Desk performs no broker `STEP` during the
callback and immediately retires the exact scope afterward, so a shutdown may
destroy its source before returning without creating a callback race.

A newer committed series-source descriptor supersedes an incomplete older
transfer. The broker aborts the obsolete terminal replacement at a transaction
boundary and starts the newest revision. It does not retransmit the plot's
static axes, style, label, or bounds merely because samples changed.

The broker may pull one source in several bounded local chunks, but it stages
the complete series mutation before emitting `PRESENT_BEGIN`. A history larger
than one wire sample payload becomes one `SERIES_REPLACE` followed by ordered
`SERIES_APPEND` operations inside the same presentation transaction. The
declared sample count must therefore fit the scope's frozen operation/byte
quota and the negotiated maxima for one atomic transaction; otherwise the
batch fails before local mutation with `PRES-S-CAPACITY`. No terminal-visible
partial history is published.

### 5.6 Visibility and drop descriptors

A visibility update changes only an existing item's visible property. An item
drop removes the named item and, for a group, its complete descendant subtree.
A resource or series drop is admitted only when the resulting committed scene
has no reference to it. The drop descriptor names its high-level namespace
(item, resource, or series) and activation-local key.

Owner retirement is not expressed with a child-created drop descriptor. It is
a Desk host operation over the exact acquired scope.

## 6. Local transaction API

The child-side mutation surface is exactly:

```forth
PRES-BATCH-BEGIN     ( batch-desc scope -- status )
PRES-ITEM-DEFINE     ( item-desc scope -- status )
PRES-RESOURCE-DEFINE ( resource-desc scope -- status )
PRES-SERIES-DEFINE   ( series-def-desc scope -- status )
PRES-SCALAR-SET      ( scalar-desc scope -- status )
PRES-SERIES-SET      ( series-source-desc scope -- status )
PRES-VISIBILITY-SET  ( visibility-desc scope -- status )
PRES-DROP            ( drop-desc scope -- status )
PRES-BATCH-COMMIT    ( scope -- status )
PRES-BATCH-ABORT     ( scope -- status )
PRES-SCOPE-STATUS@   ( scope -- status )
```

Only one batch may be open per scope. Calls are not reentrant. `BEGIN`
validates the batch declaration and reserves its complete local staging.
Operations must match the declared counts and copied-byte total exactly.

No operation emits protocol bytes. `COMMIT` first validates the complete
resulting owner scene and then atomically replaces the broker's local retained
state. On success it marks the affected definitions/properties/sources dirty
for later `STEP` and returns without waiting for terminal capacity or an ACK.
On failure the previously committed scene is unchanged.

Except for immutable resource uploads that are staged while still
unreferenced, one ordinary committed batch must serialize into one atomic
presentation transaction under the frozen per-scope and negotiated
operation/byte bounds. Initial, reset, and resize reconstruction may use the
wire protocol's hidden bounded multi-transaction rebuild followed by one
reveal. An ordinary child update is never split into terminal-visible partial
commits merely to evade a declared bound.

`ABORT` discards the local staged batch and is idempotent. A non-OK result from
an operation leaves the batch open but poisoned; only `ABORT` may follow. A
call after scope retirement returns `PRES-S-STALE` without dereferencing an
applet-owned provider context.

Static item/resource/series definitions and dynamic scalar/series-source/
visibility state are tracked separately. A scalar or sample-only commit cannot
mark an unchanged static definition dirty. This separation is a functional
contract, not merely a transport optimization.

## 7. Bounded broker service

Only the Desk owner loop advances the global broker:

```forth
PRES-SERVICE-STEP  ( work-budget broker -- status more-work? )
```

`work-budget` is a positive caller-selected number of logical operations or
provider chunks. The broker performs at most that much work, services scopes
fairly, and returns:

* `PRES-S-OK false` when quiescent;
* `PRES-S-OK true` when the budget ended with more admissible work;
* `PRES-S-WOULD-BLOCK true` when downstream capacity prevented progress; or
* a structural status and a truthful `more-work?` for inspection/recovery.

`STEP` never spins until credit appears, waits for a terminal response,
allocates a resend buffer, or recursively pumps Desk. It attempts at most one
bounded staged resource/series chunk at a time. Protocol bytes remain ordered
and lossless within the negotiated PT transport bounds.

The broker retains latest state, not every submitted renderer revision.
Scalar and visibility updates may coalesce. Definition/drop ordering and
series history may not be weakened. Round-robin service prevents one large
image or waveform from permanently starving other live readouts.

Fairness applies at protocol-safe boundaries. Once the broker opens the one
session-wide immutable-resource upload, it completes or explicitly aborts that
upload before starting a transaction, lifecycle request, or another upload;
it does not interleave chunks from another scope.

The APT shell owner remains the sole component that services the underlying
PT session and owns terminal input. `PRES-SERVICE-STEP` consumes the already
owned session through its internal adapter; it does not call `PT-SERVICE` a
second time and does not compete for UART bytes.

## 8. Desk composition, geometry, and visibility

`tui/desk-apt1.f` is the only production composition root. It constructs the
PT session and cell adapter, initializes the caller-owned broker, injects the
broker into Desk's existing global service table, and runs the ordinary Desk.
The baseline `desktop` profile does not load `presentation-terminal.f`, the
APT broker implementation, or `desk-apt1.f`.

The service identifier, opaque broker/scope ABI, status values, descriptor
builders, and application-facing wrappers live in a backend-neutral interface
module with no PT, UART, or APT implementation dependency. SoundLab may depend
on that interface in every composition. Only `desktop-apt1` loads and
constructs the APT-backed broker behind it.

The APT owner completes the deterministic retained capability query before
Desk invokes any hosted applet `INIT-XT`. The broker is therefore already in
one of two stable acquisition states when SoundLab initializes: supported, or
`PRES-S-UNAVAILABLE`. Production applets do not poll acquisition or impose an
arbitrary retry count. A lower-level query-in-progress state may return
`PRES-S-WOULD-BLOCK`, but the composition must settle it before launching a
retained consumer.

Desk performs caller-aware scope acquisition after the child `CINST` is
registered and its first `RGN` exists. The presentation region identity is
stable for the acquired scope's lifetime and is independent of `AHS.ID` and
the `RGN` pointer.

After every tile, full-frame, terminal-resize, minimize, and restore relayout,
Desk invokes the host-only broker operation:

```forth
PRES-HOST-BOUNDS!  ( row col height width visible caller-instance broker
                     -- status )
```

Visible bounds are the current Akashic `RGN` bounds. A minimized or otherwise
hidden live child is published with `visible = false`; no fabricated geometry
is required. This operation changes only the owner's region bounds/visibility.
Every retained item and resource key remains stable.

For a live child that has not acquired a scope, `PRES-HOST-BOUNDS!` is an
idempotent `PRES-S-OK` no-op. Later acquisition reads that slot's current Desk
region and visibility before admitting the first scene.

While a scope is hidden, the broker sends no ordinary scalar, sample, or
resource updates for it. Committed application changes still update the local
retained descriptors. Scalars coalesce to the newest value. A series retains
only its newest complete replayable source revision/history. On restore, the
broker publishes the newest coherent dynamic state; it retransmits static
definitions only if the terminal lost them or they actually changed.

Relayout refusal is retained as a broker diagnostic and retried from the
latest Desk geometry. It does not roll back the cell layout or force an ANSI
fallback.

Desk calls `PRES-SERVICE-STEP` after child ticks, so a same-tick committed
applet update is eligible for bounded publication. The ordinary APT shell
service still runs first to advance acknowledgements, input, and reset state.

## 9. Exact owner retirement

Applet shutdown remains application-owned. Presentation retirement is
Desk-owned and is attempted even if the applet shutdown callback throws. Desk
invokes this host-only operation before freeing the `CINST`, its state, UIDL
context, or region:

```forth
PRES-HOST-RETIRE  ( caller-instance broker -- status )
```

For a live child that never acquired a scope, retirement is an idempotent
`PRES-S-OK` no-op. It does not create a tombstone.

Scope acquisition reserves an owner record that can become its own retirement
tombstone. Therefore retirement of a valid live owner requires no allocation
and cannot fail for lack of queue capacity. It atomically:

1. marks the scope stale for every child operation;
2. detaches all resource and series provider XT/context pairs so no later
   callback can touch applet state;
3. aborts any open local batch and obsolete in-flight owner replacement;
4. records an exact owner-wide terminal drop obligation in the same owner
   record; and
5. releases item, resource, copied-value, and definition storage that the
   tombstone no longer needs.

Once this local transition succeeds, `PRES-HOST-RETIRE` returns
`PRES-S-OK` even if terminal egress is currently blocked. Desk may then free
the child. The broker retains only the exact internal owner/generation and
drop progress required to finish remotely; it retains no `CINST`, `RGN`, PCM,
or UIDL pointer.

Retirement is idempotent. An exact repeated call returns `PRES-S-OK`. A stale
or different activation cannot adopt, clear, or replace the tombstone. The
owner record becomes reusable only after the exact owner-wide drop is
acknowledged or a confirmed epoch/session reset proves that the old terminal
model was destroyed.

During complete Desk teardown all children undergo the same transition. The
broker storage remains live through APT session close. Only a synchronized
successful close or external hard attachment reset permits final tombstone
clear and `PRES-SERVICE-FINI`. A refused or structurally lost close retains
the broker beside the quarantined APT owner for retry; it is never raw-freed.

## 10. Global reset and replay

The broker privately tracks the PT session identity and presentation epoch.
A terminal soft reset does not invalidate live child scopes. It invalidates
only their terminal materialization.

On any accepted epoch/session reset, the broker:

1. abandons old-epoch transmission and resource/series chunk progress;
2. marks every live region, resource, static definition, and dynamic property
   as not materialized;
3. clears tombstones whose exact old terminal model is now proven absent; and
4. schedules a complete replay of every visible live scope.

Replay order for each scope is region, immutable resources, series definitions,
static groups/objects, current scalar and visibility state, current complete
series history, then an atomic terminal commit. Dependencies are satisfied
before references. A reset during a resource or series transfer restarts that
transfer from offset or sample zero in the new epoch.

Static definitions are replayed from the broker's copied Akashic-side scene
recipe. Scalars are replayed from copied latest values. Series are replayed by
bounded pulls from the still-live current provider revision. No terminal model
or raw wire archive is authoritative.

Hidden scopes defer replay until restore. Retired scopes are never replayed.
A session loss after the binary switch returns `PRES-S-SESSION-LOST`, freezes
ordinary broker publication, and follows the existing APT quarantine rule; it
does not select raw ANSI output.

Cell snapshot reconstruction and retained-scene reconstruction are separate
dirty/replay obligations. Clearing the CELL-1 snapshot latch cannot clear or
satisfy retained replay.

## 11. First production consumer: SoundLab

SoundLab is the first Phase 3 consumer because its displayed signal is the
same bounded PCM used by its analyzer, WAV publication, and AudioOut path. It
is not demonstration-only graph data.

SoundLab retains its existing UIDL and cell painting unchanged. During
`SOUNDLAB-INIT-CB` it performs ordinary domain initialization and initial PCM
render, discovers the global broker from its own instance, and attempts
`PRES-SCOPE-ACQUIRE`. Broker absence on baseline Desktop, or
`PRES-S-UNAVAILABLE` from the rich broker after a declined feature query,
leaves the scope zero and the existing cell UI fully functional. SoundLab does
not poll because `desktop-apt1` settles the query before applet init. A
successful acquisition followed by `PRES-S-UNAVAILABLE` for a missing VECTOR,
INSTRUMENT, or SERIES family likewise aborts only the retained-scene batch and
keeps the cell UI. A capacity or invalid result is an observable rich-profile
composition error but must not corrupt PCM or disable the cell fallback.

Its first committed retained scene contains:

* one root group;
* a static polyline frame, axes, labels, and frequency landmarks;
* frequency, amplitude, duration, peak, RMS, pitch, centroid, and playback
  readouts;
* peak/RMS meter state; and
* one waveform whose source reads the current committed PCM.

Static keys and definitions are committed once. A parameter edit updates
parameter/status values and waveform visibility. Only a successful
SoundLab render commit installs a new waveform source revision and the
matching peak/RMS/pitch/centroid values. A failed candidate render cannot
publish partial metrics or samples. Playback changes update only the playback
status/readout.

The waveform provider reads SoundLab's current authoritative bounded PCM into
the broker's staging span. It returns stale if the requested revision no
longer matches. It does not expose or lend the PCM pointer. When the admitted
series history is smaller than the PCM, SoundLab supplies a deterministic
full-span min/max envelope projection that preserves sample order and extrema;
this changes only the presentation series, never the authoritative PCM used by
save/play/analyze. Reset replay regenerates that exact current projection.

SoundLab does not retire its own owner. Its shutdown callback may free normal
application resources because the Desk owner loop is nonreentrant; Desk then
immediately executes allocation-free `PRES-HOST-RETIRE` before any later
broker step or `CINST` free. No provider callback is permitted after that
retirement transition.

The first vertical is complete when a real Desk-hosted SoundLab can update its
readouts and waveform without retransmitting unchanged axes, labels, styles,
or geometry. Image support remains part of Phase 3 closure, but a stock image
or synthetic documentation fixture is not a substitute for a real app-owned
resource.

## 12. Phase boundary: UIDL remains Phase 4

Phase 3 uses a handwritten SoundLab projection controller over this service.
It does not add a UIDL element, bind a scope to `UCTX`, or make UIDL lifecycle
the presentation owner.

The generic `<presentation>` host widget, reactive state bindings, UCTX-owned
scene teardown/replay, and semantic `<readout>`, `<meter>`, `<plot>`, `<image>`,
and `<status>` widgets are Phase 4. Existing `<canvas>`, `<media>`, `<indicator>`,
`bind=`, subscription, and dirty mechanisms do not become retained terminal
objects merely because the broker exists.

Raw UIDL elements that mirror wire primitives or opcodes are not introduced.
Phase 4 must consume this same high-level scope/descriptor API rather than
creating a parallel terminal ownership model.

## 13. Initial conformance cases

The lightweight contract suite must prove:

1. baseline Desktop has no broker while `desktop-apt1` exposes exactly one
   global broker through the existing endpoint even when retained discovery is
   negative; negative acquisition is `PRES-S-UNAVAILABLE` and consumes no owner
   record;
2. on a supporting terminal, two live child instances discover that same
   broker but acquire distinct opaque scopes bound to their exact
   `CINST.ID`/`CINST.GENERATION`;
3. an unregistered, closed, foreign-Desk, or stale caller is rejected without
   consuming an owner record;
4. configuration overflow, wrap, misalignment, overlap, and negotiated-budget
   mismatch fail before changing any supplied storage;
5. descriptors, labels, unit text, styles, points, and scalar values are
   copied, so caller mutation after return cannot alter committed state;
6. one static definition batch followed by scalar and series updates emits no
   duplicate unchanged definitions;
7. a series provider is pulled only in bounded chunks, rejects a stale
   revision, and is never called after retirement;
8. an exact `STEP` budget is honored and downstream `WOULD-BLOCK` causes no
   spin, loss, reordering, or hidden allocation;
9. minimize suppresses ordinary output, coalesces latest state, and restore
   publishes one coherent current state;
10. relayout changes region bounds while item/resource identities remain
    stable;
11. reset during an incomplete series/resource transfer rebuilds the complete
    visible scene from current Akashic state;
12. shutdown failure still creates an allocation-free exact-owner tombstone
    before `CINST` free, and retry/ACK/reset releases only that tombstone; and
13. SoundLab remains fully usable through ANSI when broker discovery or
    retained negotiation is unavailable.

Full Desktop, reset, renderer, and two-hertz presentation journeys are later
sequential qualification. They do not replace these bounded headless service
contracts and may not justify larger hidden capacities or weakened teardown.
