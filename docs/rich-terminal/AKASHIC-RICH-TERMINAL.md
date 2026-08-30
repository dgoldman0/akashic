# Akashic rich-terminal engine and UIDL output contract

Status: normative implementation and pre-acceptance contract for the Phase 3
Akashic rich-terminal mode and its UIDL output integration. The selected Desk
composition now implements menu-semantic hybrid publication, repeat full-frame
replacement, and draw-keyed aggregation of every visible attached UCTX.
Physical Desk/Pad/Daybook acceptance and additional native semantic families
remain open.

This document defines the Akashic architecture, storage, ownership, projection,
and lifecycle contract for optional rich-terminal output. It does not define
APT-1 byte encoding. The mirrored `APT-1-WIRE.md`, `APT-1-RETAINED-1.md`, and
ownership ledgers define terminal protocol identity, transactions, reset, and
retirement.

The transactional CELL output path remains independently specified by
`AKASHIC-CELL-BACKEND.md`. Rich-terminal mode adds an optional retained
projection of the same UIDL/UCTX interface already rendered into cells. It does
not create a second application UI model, replace the cell screen, or weaken
ANSI fallback.

## 0. Current implementation status and course correction

### 0.1 Locked near-term execution order

The hybrid CELL/retained architecture is fixed: CELL remains the complete
mandatory fallback; retained-only updates are valid when CELL is unchanged;
and complete replacement is reserved for initial construction, reset, resize,
or genuinely uncertain topology. Until profiling provides contrary evidence,
work proceeds in this order:

1. close the retained-availability handoff by forcing the exact current surface
   through the unified publisher on the unavailable-to-available transition;
2. eliminate accidental complete replacement during ordinary updates;
3. profile and reduce incremental producer cost without weakening
   renderer-neutral ownership or fallback correctness;
4. add only the generic window/pane, tab, and text-area/text-grid semantics
   justified by the Desk/Pad/Daybook journey; and
5. move safe caching and culling of CELL pixels hidden by opaque retained
   output to the terminal side.

A CELL-less "pure rich" mode, unrelated semantic families, or broad terminal
expansion must not displace this sequence without new end-to-end evidence.

The checked-in APT-1 Desk composition now reaches the retained path through
`tui/rich-terminal/uidl-hybrid-adapter.f` and
`tui/rich-terminal/hybrid-screen-producer.f`. The adapter captures a complete,
draw-keyed directory of menu semantics from every visible attached UCTX. The
producer combines those accepted controls with maximal residual glyph spans
from the same completed ordinary draw, then recaptures and atomically replaces
the hidden retained target after later completed draws. The earlier
`screen-plane.f` one-object-per-cell bootstrap is no longer composed. A
full-screen one-object-per-cell frame is specifically forbidden as product
proof.

This implementation is not acceptance evidence by itself. The canonical
Desk/Pad/Daybook journey must still show the exact hybrid frame in the physical
viewer, activate Pad's real File menu through revision-bound normal input,
publish the resulting draw, edit Pad, interact with Daybook, and acknowledge
each exact displayed revision. Custom editor, calendar, and Desk areas remain
truthfully visible through residual spans until their own generic semantic
families land.

The intended product producer is one renderer-neutral **hybrid projection**
derived from the ordinary UIDL and draw lifecycle:

1. capture real semantic controls wherever the ordinary UIDL element or
   mounted widget has renderer-independent meaning;
2. resolve which visible pixels those accepted controls claim, respecting
   ordinary clipping and paint order;
3. paint the same ordinary frame through the existing TUI draw boundary; and
4. emit maximal row-local, equal-style residual glyph spans only for visible
   cells not claimed by an accepted semantic control.

Menus, menu items, dialogs, text areas, selection/focus state, and other real
controls must not be flattened to glyphs merely because the horizontal
GLYPH_RUN path exists. Conversely, a custom draw surface does not acquire
invented semantics. Until a generic renderer-neutral snapshot exists for that
widget, its unclaimed final draw output is carried by residual spans. This is
how the existing mounted Pad editor and Daybook calendar remain visible during
the semantic expansion without adding applet-specific scenes or branches.

A semantic claim is exclusive for the selected rich renderer. The semantic
object owns rich representation and rich hit testing inside its final visible
claim; the residual encoder must skip that area. If the terminal lacks the
semantic family, capture refuses it, or admission cannot represent it, the area
remains unclaimed and therefore receives ordinary residual glyph coverage.
The authoritative UIDL/widget state, focus, action dispatch, and CELL fallback
remain unchanged in both cases.

`akashic/tui/rich-terminal/uidl-projector.f` and `uidl-driver.f` preserve useful
experiments in semantic capture, stable keys, attachment authority, and owner
retirement, but their narrow LABEL ABI is stale relative to the current `RTE`
facade and their repeated scans are not the path forward. They must not be
revived wholesale or installed as a parallel product producer. The correction
is a forward refactor: retain their good lifecycle and identity concepts,
extend the generic `ED.SEMANTICS`/mounted-widget seams for genuine control
snapshots, and replace the temporary screen producer with the hybrid candidate
planner. Once that producer is accepted, remove the superseded per-cell and
dormant LABEL-only product paths rather than preserving legacy alternatives.

Candidate work is linear and has one validation authority. Construction
produces one canonical key order and one frozen candidate; admission performs
one full validation traversal and records the checked counts, extents, quotas,
and identity correlations consumed by later adapter and publisher stages.
Those stages must not rescan the same complete candidate. When bytes remain in
a caller-owned mutable bank, one final mutation-safety validation immediately
before seal/publication is required. It is the only permitted repeated full
traversal; copying into an immutable engine-owned attempt bank removes the need
for it. Uniqueness and stable-ID reuse use a linear merge over canonical keys,
not prior-item searches, repeated-minimum scans, or other quadratic work.

The detailed hybrid candidate contract is
[UIDL-PROJECTION-CANDIDATE.md](UIDL-PROJECTION-CANDIDATE.md). If a later section
of this document describes the earlier LABEL-only driver or the current
per-cell screen bootstrap as the product projection, this section and that
candidate contract take precedence.

## 1. Non-negotiable architecture

UIDL is the sole application-facing UI description. A hosted component owns its
ordinary domain state and uses the existing UIDL element tree, bindings,
subscriptions, semantic widgets, dirtying, layout, focus, and event mechanisms.
The same `UCTX` owns that UI for the complete activation lifetime.

The implementation has three layers. One generic, consumer-neutral Akashic
engine contract owns retained lifecycle for one live enhanced terminal
session. The current `RTAPT` provider implements that contract over APT-1 with
caller-bounded storage and has no knowledge of `AHOST`, `AHS`, CINST, UCTX,
Desk, or any applet. An explicit composition may use that engine outside Desk
and UIDL-TUI without acquiring a second protocol or session implementation.

An immutable caller-owned `RTE` facade is the operation boundary above a
concrete provider. The landed facade exposes neutral status, owner,
transaction, region, GLYPH_RUN definition/replacement and plan preflight,
update-state observation, and storage-disjoint operations plus one opaque
provider context. Genuine semantic control families extend this neutral
boundary as their contracts land; UIDL code must not encode a menu or another
control as a misleading GROUP or GLYPH_RUN. Only the provider bridge names both
vocabularies; generic UIDL code neither names nor loads `RTAPT`.

Above it, UIDL-TUI owns a renderer-neutral optional-projection lifecycle. The
rich-terminal driver implements that lifecycle's private adapter table and
adapts UIDL semantics to the generic engine facade. Desk and the applet host
express only document visibility, quiesce, and final detach through ordinary
UIDL-TUI words; they neither select the adapter nor name its provider. A
Desk-owned UIDL context, when present, follows the same lifecycle as a child
UCTX; Desk UI code does not author a retained scene manually.

The following are forbidden application interfaces:

* retained-backend or APT discovery through `IEND.SERVICE-XT`;
* applet acquisition of a rich-terminal broker, scope, owner, or lease;
* applet calls that begin, define, update, commit, abort, step, replay, or retire
  a terminal scene;
* applet-visible session, epoch, owner, region, object, resource, series,
  revision, transaction, opcode, frame, or terminal-capacity identities; and
* a handwritten projection controller maintained beside an applet's UIDL.

There is therefore no rich-terminal service identifier and no rich-terminal
endpoint per Desk or per applet. The mode/output backend is an internal
composition capability, not an application-visible object. "Global" in this
contract means only that one internal backend serializes one terminal session.
It is held by the explicit composition and UIDL host, not published as
application authority.

Retained terminal state is a derived output materialization. The UIDL tree,
semantic widget state, and bound application state remain authoritative. The
backend may keep a bounded copied projection recipe, dirty state, mappings, and
wire tombstones so that transport is incremental and reset is replayable. That
cache is not a second application-owned scene and has no independent mutation
API.

"Storage" in this contract means only caller-provided volatile memory for that
derived output cache and its finite wire-owner lifecycle. It is not document or
application persistence, a recovery database, or a second application layer.
Reconstruction after terminal reset, resize, or loss re-derives output from
authoritative UIDL; it never reconstructs application state from terminal data.

## 2. Authority and identity

The generic engine is the sole Akashic component allowed to emit retained wire
frames. It owns discovery state, the shared rich-terminal update transaction and
revision domain, resource-upload serialization, wire-owner lifecycle, replay,
and retirement. The APT shell remains the sole owner of the PT session and
terminal input; the engine consumes that session's public ABI and never creates
another UART reader, writer, or service loop.

The UIDL-TUI driver represents each attached UCTX privately with one bounded
projection binding. The binding contains:

* the exact live `AHOST` and `AHS` slot addresses and captured `AHS.ID`;
* the exact CINST address, `CINST.ID`, and `CINST.GENERATION`;
* the exact UCTX identity and current Akashic region/visibility;
* a backend-issued nonzero internal binding token and generation;
* one private retained wire owner ID and generation when materialized;
* stable mappings from `(UCTX, element-index, semantic-subkey)` to wire item
  identities; and
* terminal-eligibility quotas, copied projection state, progress, and retirement
  state.

The complete host/slot/CINST/UCTX tuple is the Akashic authority binding. Focus,
current tile position, an `id=` string, a region pointer, or possession of a
UIDL element pointer alone grants no authority. The backend validates the exact
live tuple at attach and revalidates it through the private binding token before
project, relayout, quiesce, and detach.

The wire ownership ledger's guest-side owner binding is this private projection
binding. It is not handed to application code. Wire owner and item identities
may rotate after reset without changing the live UCTX or any UIDL element
identity.

Terminal reset, replay, resize, or loss of terminal cache must not mutate UIDL,
widget state, application state, documents, media, samples, or any other domain
state. Conversely, retained terminal state is never authoritative input to an
applet.

## 3. Internal status values

The host/backend boundary uses these stable ordinary status values:

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `RTERM-S-OK` | The host operation or projection was accepted. |
| 1 | `RTERM-S-WOULD-BLOCK` | No downstream progress is currently possible; retry from the host loop. |
| 2 | `RTERM-S-UNAVAILABLE` | No usable negotiated retained backend or required semantic family exists. |
| 3 | `RTERM-S-CAPACITY` | Caller-owned capacity cannot store the candidate or a checked limit cannot establish eligibility/admit materialization. |
| 4 | `RTERM-S-STALE` | The UCTX, activation binding, source revision, or terminal materialization is no longer current. |
| 5 | `RTERM-S-INVALID` | An argument, semantic snapshot, storage configuration, state transition, or callback result is invalid. |
| 6 | `RTERM-S-SESSION-LOST` | The enhanced session crossed a structural loss boundary. |
| 7 | `RTERM-S-SOURCE` | A semantic resource or series source failed. |

These statuses do not throw through an applet callback and are not returned to
application rich-terminal code, because no such code exists. Each binding
records its latest diagnostic while leaving application state intact. Only
`INVALID` and `SESSION_LOST` are sticky backend-global failures; `CAPACITY` and
`SOURCE` are local refusal results and cannot poison another binding or the
unified publisher. A post-`OPEN` structural loss never makes raw ANSI output
safe.

In the APT-1 composition, that first fatal result is also a neutral
publisher fault latch. It survives ordinary scheduler calls so a later call
cannot silently turn a failed output lifecycle back into apparent success.
This persistence is only an in-memory status latch: it owns no UIDL or
application data, and it is cleared only by whole-publisher reconstruction or
final retirement. Synchronized teardown may still poll and settle work that
was already admitted; the latch grants no authority to start new publication
during teardown.

`RTERM-S-WOULD-BLOCK` is transport progress, not local projection-capacity
failure. Already accepted desired state remains accepted while egress is
blocked. `RTERM-S-CAPACITY` and `RTERM-S-SOURCE` revoke only the refusing
binding's retained eligibility/readiness. Validation and admission refusal are
fail-before-owner-mutation; refusal discovered during capture first cancels the
partial retained transaction and then retires the already-admitted exact owner.

## 4. Generic engine construction and caller-owned storage

The live facade in `akashic/tui/rich-terminal/engine.f` currently exposes the
neutral GLYPH_RUN definition, replacement, and plan-preflight operations used
by the screen bootstrap. The LABEL ABI inventory below records the earlier
semantic prototype and is **superseded**: those words are no longer the live
facade, and their record layouts are not implementation instructions for the
hybrid vertical. It remains here only to identify lower-stack ownership and
validation decisions that may be forward-refactored. The new semantic-control
ABI is designed from the candidate contract in Section 0, not by restoring
these names or offsets.

An optional composition constructs a concrete engine and publishes its
consumer-neutral operation boundary with:

```forth
RTE-FACADE-BYTES       ( -- bytes )
RTE-VALID?             ( facade -- flag )
RTE-STORAGE-DISJOINT?  ( a u facade -- flag )
RTE-STATUS@            ( facade -- status )

RTE-LIMITS-BYTES       ( -- bytes )
RTE-LIMITS-VALID?      ( limits -- flag )
RTE-LIMITS@            ( limits facade -- status )

RTE-LABEL-PLAN-BYTES       ( -- bytes )
RTE-LABEL-PLAN-ITEM-BYTES  ( -- bytes )
RTE-LABEL-PLAN-VALID?      ( plan -- flag )
RTE-LABEL-PREFLIGHT        ( plan facade -- status )

RTE-OWNER-OPEN         ( owner generation quotas... facade -- status )
RTE-OWNER-STATE@       ( owner generation facade -- owner-state status )
RTE-UPDATE-STATE@      ( facade -- update-state status )
RTE-RETAINED-BEGIN     ( retained-mode facade -- status )
RTE-REGION-DEFINE      ( owner generation region geometry... facade -- status )
RTE-LABEL-BYTES        ( -- bytes )
RTE-LABEL-VALID?       ( label -- flag )
RTE-LABEL-DEFINE       ( label facade -- status )
RTE-RETAINED-SEAL      ( disposition facade -- status )
RTE-RETAINED-CANCEL    ( facade -- status )
RTE-OWNER-DROP         ( owner generation facade -- status )
```

`RTE-*` names the backend-neutral Akashic contract. The APT-1 implementation
uses the collision-free `RTAPT-*` prefix and is only one engine implementation.
Its `RTAPTE-INIT ( rtapt-engine facade -- status )` bridge performs the sole
mapping and proves that the facade descriptor is disjoint from all concrete
provider storage before publishing it. The UIDL-TUI adapter depends only on
`RTE`.

The facade is the neutral boundary for RTAPT's currently implemented owner,
transaction, region, LABEL, plan-preflight, status, and alias operations. Its
ABI-5 descriptor is 144 bytes: the callback at offset 128 performs neutral
LABEL-plan preflight and the callback at offset 136 reports the neutral state
of the one session-global update slot. `IDLE`, `CAPTURING`, `SEALED`,
`PUBLISHING`, and `AWAITING` describe lifecycle coordination only; they expose
no CELL-specific provider state or wire identity. The materializer uses this
read-only observation together with its sole active-attempt authority to
correlate publication settlement without reaching through the facade.

The facade also exposes one 160-byte immutable negotiated-limits snapshot. The
fixed record shape contains neutral
feature-family bits and the terminal-supplied maxima for owner records, live
owners, regions, resources, objects, series, operations per update, update
bytes, resource chunks and total resource bytes, image dimensions, vector
points, label and total UTF-8 bytes, series append/history/sample slots, and
minimum update interval. Coordinate precision, color representation, and the
first image representation are invariants of this facade revision rather than
copied provider enum values.

`RTE-LIMITS@` validates that its caller-owned destination is aligned,
nonwrapping, and disjoint from both facade and provider storage. Pending
discovery returns `RTE-S-WOULD-BLOCK`, a deterministic CELL-only result returns
`RTE-S-UNAVAILABLE`, and structural loss returns
`RTE-S-SESSION-LOST`. A non-OK result leaves the destination unchanged. On
success the facade validates CORE presence, feature dependencies, exact
feature-dependent zero/positive fields, cross-field totals, and transaction
floors. These are negotiated eligibility bounds, not compiled product limits or
resource reservations.
The current provider obtains them through
`RTAPT-LIMITS@ ( engine -- limits status )`, which synchronously copies the
already validated PT CAPS/FORMATS pair into one engine-owned typed snapshot.
The bridge maps every provider field and feature bit into the caller's neutral
record, then scrubs all borrowed raw-record, provider-snapshot, engine, and
destination pointers.

`RTE-LABEL-PREFLIGHT` accepts an aligned, call-borrowed 112-byte neutral plan
header. It describes exactly one root `REGION_DEFINE` followed by `N` root
`LABEL_DEFINE` operations; it contains declarations only, never borrowed text
or a provider payload:

| Offset | Header field | Contract |
| ---: | --- | --- |
| 0 | owner | nonzero private owner identity |
| 8 | generation | nonzero proposed owner generation |
| 16 | surface columns | positive native-cell surface width |
| 24 | surface rows | positive native-cell surface height |
| 32 | region ID | nonzero private root-region identity |
| 40 | region x | nonnegative root origin column |
| 48 | region y | nonnegative root origin row |
| 56 | region columns | positive root width |
| 64 | region rows | positive root height |
| 72 | region z | signed root paint order |
| 80 | region flags | only the current region bits 0 and 1 |
| 88 | items address | aligned borrowed item-array address |
| 96 | items bytes | positive exact multiple of 128 |
| 104 | reserved | zero |

The root bounds use checked addition and must fit inside the declared positive
surface. The header and item array must be nonwrapping, mutually disjoint, and
individually disjoint from facade and provider storage. `N = items-bytes / 128`;
there is no compiled item-count ceiling.

Each item has this exact 128-byte neutral shape:

| Offset | Item field | Contract |
| ---: | --- | --- |
| 0 | object | nonzero; strictly increasing in capture order |
| 8 | parent | zero for the current root-LABEL provider slice |
| 16 | row | signed row relative to the root |
| 24 | column | signed column relative to the root |
| 32 | height | nonnegative declared height |
| 40 | width | nonnegative declared width |
| 48 | root height | positive and exactly equal to header region rows |
| 56 | root width | positive and exactly equal to header region columns |
| 64 | z | signed LABEL paint order |
| 72 | visible | canonical Forth boolean `0` or `-1` |
| 80 | RGBA | packed numeric `0xRRGGBBAA` |
| 88 | horizontal alignment | `0` start, `1` center, `2` end |
| 96 | vertical alignment | `0` top, `1` middle, `2` bottom |
| 104 | ellipsize | canonical Forth boolean `0` or `-1` |
| 112 | retained text capacity | renderer-derived exact reservation for this desired generation |
| 120 | reserved | zero |

Neutral validation proves the complete native-cell shape, object order,
canonical scalar fields, checked row/column edge arithmetic, and the same
visible-intersection rule as `RTE-LABEL-VALID?`. It deliberately does not
import APT-1 scalar widths. The installed provider owns exact representability:
the current RTAPT bridge requires u32 surfaces, region geometry, LABEL extents,
root dimensions, and text capacities; i32 row, column, and z values; and exact
provider geometry conversion. A native-cell plan that cannot cross that
boundary is rejected before owner admission.

The current RTAPT provider then proves all admission arithmetic against one
coherent current limits snapshot and its caller-owned banks. For current copied
text lengths `c_i`, `current_utf8 = sum(c_i)`, it requires:

* owner quotas of one region, `N` objects, and `current_utf8` bytes, including
  checked aggregate reservations already held by other owner records;
* `1 + N` operation records and local copied bytes
  `72 + sum(ALIGN8(128 + c_i))`;
* every current `c_i` within the negotiated per-LABEL maximum and the
  aggregate within negotiated UTF-8 and object bounds; and
* an op-bearing hidden `REPLACE_START` wire transaction of exactly
  `248 + 120 * N + current_utf8` bytes within the negotiated update maximum.

The immediately following `OWNER_OPEN` must use exactly
`(regions=1, resources=0, objects=N, series=0, resource-bytes=0,
utf8-bytes=current_utf8, sample-slots=0)`. Preflight returns no token which
could authorize different quotas or a different selected generation.

That START total is the frozen 160-byte wire transaction envelope, one 88-byte
region definition, and `N` LABEL definitions of `120 + c_i` bytes. The later
empty reveal transaction is exactly 160 bytes. The build and reveal are serial
transactions which reuse bounded staging; their byte budgets are checked
individually and are never added into one fictitious simultaneous requirement.

Owner availability is dynamic. A matching owner can be reused only from a
stable tombstone with a strictly newer generation; any other matching live or
in-flight state is transiently busy. Otherwise a free local owner record must
exist. The provider also requires idle capture/queue state and accounts for
live-owner and aggregate terminal quotas. These checks derive solely from
caller-supplied storage and negotiated limits, not an arbitrary compiled
owner, operation, copy-byte, or LABEL-count limit.

Preflight is advisory and admission-mutation-free. `RTE-S-OK` reserves neither
the observed owner record nor terminal quota and does not authorize a later
call to skip revalidation. Neutral or representation errors return
`RTE-S-INVALID`; unsupported INSTRUMENT capability returns
`RTE-S-UNAVAILABLE`; local or negotiated exhaustion returns
`RTE-S-CAPACITY`; and a currently occupied engine or owner maps to
`RTE-S-WOULD-BLOCK`. Discovery and structural statuses propagate normally.
The plan and item bytes, operation bank, copy bank, and wire are unchanged on
every result. Ordinary success or refusal also leaves the owner ledger,
lifecycle queue, and PT session unchanged; limits discovery may refresh only
the provider's designated negotiated-limits observation scratch. Discovering
an already-lost session may invoke the engine's pre-existing quarantine and
capture-clear transition, but that is structural-loss containment rather than
plan admission and emits no wire. Preflight itself produces no `OWNER_OPEN`,
tombstone, retained capture, owner reservation, or wire frame.

`RTE-LABEL-DEFINE` accepts one aligned, call-borrowed 160-byte neutral record:

| Offset | Field | Contract |
| ---: | --- | --- |
| 0 | owner | nonzero internal owner identity |
| 8 | generation | nonzero owner generation |
| 16 | object | nonzero object identity |
| 24 | region | nonzero region identity |
| 32 | parent | parent object identity, or zero |
| 40 | row | signed integer row relative to the root |
| 48 | column | signed integer column relative to the root |
| 56 | height | nonnegative integer height |
| 64 | width | nonnegative integer width |
| 72 | root height | positive integer root height |
| 80 | root width | positive integer root width |
| 88 | z | signed paint-group order |
| 96 | visible | canonical Forth boolean `0` or `-1` |
| 104 | RGBA | packed numeric `0xRRGGBBAA` |
| 112 | horizontal alignment | `0` start, `1` center, `2` end |
| 120 | vertical alignment | `0` top, `1` middle, `2` bottom |
| 128 | ellipsize | canonical Forth boolean `0` or `-1` |
| 136 | text address | borrowed UTF-8 address |
| 144 | text bytes | exact borrowed UTF-8 byte count |
| 152 | reserved | zero |

The coordinates are integer/root-relative semantic geometry, not a concrete
provider's coordinate representation. Checked signed addition must prove the
bottom and right edges. A visible LABEL must have positive height and width and
a positive intersection with the root; negative row or column therefore
remains valid for partial clipping. An invisible LABEL may have zero extent or
lie completely outside the root. RTAPT deterministically canonicalizes that
case to nonempty clipped provider bounds inside the root while preserving
invisibility, then converts all clipped boundaries directly at full
`UNORM32` precision.

Text is well-formed UTF-8 scalar text without NUL, CR, or LF. Empty text has
the single canonical representation `0 0`. A nonempty borrowed text span may
begin at any byte address; it has no native-cell alignment requirement.
`RTE-LABEL-VALID?` is the full pure value validator: when explicitly called, it
checks every scalar and intrinsic span rule and scans the exact declared text
bytes for scalar UTF-8 and the control-byte exclusions without mutating facade
or provider state.

`RTE-LABEL-DEFINE` deliberately performs bounded dispatch validation instead.
It validates the aligned, nonwrapping, storage-disjoint record, all scalar and
canonical fields, and the canonical nonwrapping text span, including its
disjointness from facade and provider storage. It does not scan the borrowed
content before dispatch, because its declared length has not yet been bounded
by negotiated provider limits. The installed provider must first apply its
negotiated per-LABEL length bound, then validate the admitted bytes for scalar
UTF-8 and NUL/CR/LF exclusions. Those checks finish before text copy, captured
operation mutation, or owner-ledger mutation; failure leaves all three
unchanged. The facade and bridge retain neither borrowed pointer after the
synchronous call.

RTAPT captures an accepted definition into its aligned caller-owned copy bank
as a fixed native header followed by the exact copied text and zero
alignment padding. That retry authority is pointer-free. Its owner ledger
tracks exact active, hidden, and pending object counts and UTF-8 byte totals,
along with monotone object identity, across retained build modes and reveal.
Commit revalidates the captured shape and sends it only through the typed
`PT-LABEL-DEFINE` writer; no raw provider operation payload crosses the neutral
facade.

The safe first APT-1 provider slice accepts only a LABEL with `parent=0` and
only a region identity defined earlier in the same captured candidate. Region
and object identities may remain sparse; neither capture nor preflight infers
existence from a dense count or high-water range. References to an already
committed region and nonroot GROUP parents wait for caller-bounded exact
active/hidden identity-and-type ledgers. The neutral RTE LABEL record keeps its
`parent` field and general region identity unchanged; this is a current
provider-admission restriction, not a contraction of the facade schema.

The renderer-neutral candidate projector can now measure and copy supported
UIDL semantics into caller-owned banks, and the lifecycle driver now selects a
complete build in one of two desired banks belonging to the exact private
binding. It builds the inactive bank, applies `RUPJ-CANDIDATE-VALID?`, maps
retry-stable private identities for a nonempty recipe, completes its metadata,
and changes the authoritative selector last. An accepted empty candidate is
published and returns `RTERM-S-UNAVAILABLE`. A deep-valid nonempty candidate
then undergoes a terminal-eligibility check; its exact success or refusal status
is returned, while either result preserves the candidate and mapping. A
construction, deep-validation, or identity-mapping failure leaves the prior
selector and stable identity mapping available for retry, but revokes its
terminal eligibility and schedules retirement of any live rich output. The old
candidate is no longer authoritative for physical display because it may not
represent current UIDL state.

UIDL-TUI exposes complete neutral resolved geometry/style as a copied 72-byte
record with effective visibility and paint-group z. Each selected 128-byte RUPJ
item now carries that record root-relative when it is available, while
preserving semantic LABEL membership with a zero resolved payload when it is
not. The projector invokes no facade operation. Project invokes only the
read-only `RTE-LIMITS@` after assigning private owner/region/object identities,
then records terminal-negotiated eligibility before selector publication. This
reserves neither an owner nor capture-bank space. The bound neutral driver later
accepts the output adapter's call-borrowed surface snapshot, freezes the exact
selected candidate in one backend-global attempt slot, deep-validates that
copy, constructs a sorted neutral LABEL plan, and performs
`RTE-LABEL-PREFLIGHT` immediately before owner admission. After admission it
keeps only the pointer-free attempt and exact owner lifecycle needed to capture,
settle, reveal, supersede, or retire that derived output. A rejected or stale
attempt cannot erase a newer desired candidate, and an uncertain owner is
dropped to a proven tombstone before its record or generation is reused.

Materialization first commits the complete candidate hidden. A separate
zero-operation shared transaction performs the final reveal only after every
record in the cohort is staged and revalidated against the current surface and
desired generations. Promotion stores each record `LIVE` and publishes the
backend live epoch last. This is output bookkeeping over neutral UIDL—not a
second scene API or an application recovery layer.

A rejected retained-only output follows RETAINED-1's authoritative retry
exception. RTAPT rewinds it to `SEALED` plus `STALE` without discarding the
candidate; hidden and reveal settlement therefore re-offer that exact output and
do not quarantine. If a defensive observation instead finds `IDLE` plus
`STALE`, the sealed retry authority is gone. Hidden settlement records `STALE`
without clearing the desired candidate, identity mapping, or negotiated
eligibility, then retires the exact admitted owner before re-admission. Reveal
settlement never promotes that result `LIVE`: it restarts at cohort record zero,
retires every staged owner through the ordinary tombstone-proven drop path, and
rebuilds from authoritative desired state. `INVALID` and `SESSION_LOST` remain
terminal.

`CAPACITY` and `SOURCE` are instead CELL-preserving per-binding refusals. At
cohort admission they record the local diagnostic, clear only negotiated
eligibility/readiness, and advance to the next binding without clearing the
candidate bank, positional identity mapping, selected candidate, or object-ID
high-water. If capture discovers either refusal after owner admission, the
driver first cancels/reconciles the partial retained transaction, records the
local diagnostic, revokes only eligibility, and publishes exact owner
retirement. The refusal marker remains persistent until `OWNER-STATE@` proves
the exact owner `TOMBSTONE`; only then does the cohort advance to the following
binding, preserving any earlier staged records for the atomic reveal. Reveal
itself remains cohort-wide and does not invent a single-record fallback: its
zero-operation transaction names the shared hidden candidate and contains no
binding operation from which a `CAPACITY`/`SOURCE` result could be safely
attributed. `PREPARE-REVEAL` therefore leaves the cohort intact and reports the
result as retryable publisher backpressure rather than routing it through the
capture-refusal helper.

The lower UIDL layer now supplies the first neutral semantic snapshot
substrate independently of this adapter. `ED.SEMANTICS` selects a per-element
caller-bounded snapshot hook, and `UIDL-SNAPSHOT-SIZE` /
`UIDL-SNAPSHOT-CAPTURE` measure and copy typed records without terminal or
provider identity. The LABEL record contains an exact copy of the current
resolved text. It has no renderer reservation and requires no eligibility
attribute in UIDL. CELL label paint consumes the same `UIDL-TEXT@` value rule.
Thus string/integer/boolean binding semantics are shared below either output
path, while optional rich-output eligibility and materialization remain above
UIDL semantics.

The candidate projector walks the active root tree under one compound
UIDL-TUI, UIDL, projector, and semantic observation and copies eligible LABEL
records plus any available neutral resolved state into bounded item/snapshot
banks. Semantic eligibility does not depend on resolved-state availability:
an unavailable resolved record leaves a zero payload and flags, while invalid
resolved state rejects the complete build. Each binding has two caller-owned
desired item banks, two positional identity banks, and two caller-owned
snapshot banks, so a new complete candidate can replace the selected candidate
atomically without allocating. Each combined slab has one additional final bank
shared by the backend as its sole frozen-attempt slot: for binding capacity `C`,
the physical bank count is checked `2*C + 1`, not three banks per binding.
Candidate construction itself remains wire-inert: no shipped UIDL has been
bulk-annotated for optional rich-output eligibility, and the checked-in Desktop
policy still advertises no retained family. When a product policy supplies an
eligible family, the separately bound materializer owns admission and output.
The eligibility check compares each LABEL's current copied text and the neutral
semantic region, object, and UTF-8 bounds. It
deliberately does not infer provider operation, retry-copy, or encoded-update
costs. The explicit advisory materialization preflight now proves those
representation details, local capture-bank fit, and dynamic owner/tombstone
availability, but its success grants no owner or publication authority.

`config` names the exact borrowed PT session, output policy, and caller-owned
spans and capacities for:

* wire-owner lifecycle records and owner tombstones;
* retained region, object, resource, and series records;
* consumer-supplied stable keys and their wire mappings;
* copied definitions, styles, labels, unit text, vector points, and latest
  dynamic values;
* transaction operation records and copied transaction bytes; and
* one resource-or-series chunk staging span.

The implementation publishes exact record and configuration sizes. Counts and
byte lengths are independent. A product profile chooses capacity from its
supported concurrent UCTXs and negotiated remote budgets. The generic backend
contains no hidden objects-per-applet, strings, history, image, or resend-queue
limit.

Initialization performs a complete preflight before writing any caller byte.
It checks:

* nonzero required capacities and valid zero capacities for disabled optional
  semantic families;
* checked multiplication of record size by record count;
* non-null, nonwrapping spans and required alignment;
* pairwise disjointness of the backend, configuration, every owned span, and
  the borrowed PT session and its buffers; and
* compatibility with negotiated object, resource, frame, transaction, history,
  and chunk budgets.

Failure returns `RTERM-S-CAPACITY` or `RTERM-S-INVALID` without partially
initializing, clearing, or retaining a supplied span. After successful init,
attach, project, relayout, detach, service, reset replay, and finalization use
only admitted storage and perform no hidden heap or XMEM allocation.

The engine stores accepted retained state, not raw frames or an unbounded
revision history. Consumer-specific semantic recipes and host bindings remain
outside the engine. The UIDL-TUI driver supplies separate caller-owned storage
for those bindings, copied semantic snapshots, and projection mappings; it
also performs no hidden allocation. Resource and sample bytes are copied into
bounded staging only for the synchronous interval required by their source and
wire contracts.

`RTERM-BACKEND-FINI` succeeds only when no live engine owner remains and every
retirement obligation is acknowledged, or the underlying session is proven
destroyed. Refusal leaves the complete engine and its storage valid for retry.
It never clears an uncertain owner tombstone. Consumer-specific bindings,
including UIDL UCTX bindings, must already have quiesced and released their
engine owners before finalization.

## 5. UIDL semantic projection contract

This section describes the semantic half of the hybrid candidate, not a
semantic-only scene. Semantic capture and ordinary drawing happen within the
same UCTX revision and normal paint lifecycle. The planner first selects
supported semantic items, then derives their final visible claims, and only
after ordinary painting derives residual glyph spans from unclaimed cells.
Neither half may independently enumerate the application UI.

### 5.1 One semantic tree, multiple output paths

UIDL element semantics are backend-neutral. The existing UIDL-TUI renderer
continues to paint the CELL/ANSI representation. The rich integration adds
an optional projector registry keyed by UIDL element type; it does not replace
the element's CELL render XT or introduce a second document.

Every retained-capable semantic element or widget has:

1. a complete CELL rendering usable on baseline ANSI and CELL-1 terminals;
2. one backend-neutral semantic snapshot contract;
3. an optional retained projector supplied by the rich integration; and
4. the ordinary UIDL binding, subscription, dirty, layout, focus, and event
   behavior appropriate to that element.

Existing semantic elements such as containers, labels, `media`, `canvas`,
`range`, `indicator`, and `status` may gain retained projectors where their
meaning is sufficiently defined. New readout, meter, plot, waveform, image, or
other rich types are added as semantic UIDL elements/widgets, with real CELL
fallbacks. They are not raw aliases for APT opcodes or wire object families.

The semantic registry is not limited to LABEL and is not limited to elements
whose ordinary renderer happens to draw text. Existing high-level chrome such
as menubars, menus, items, dialogs, and text areas is projected as controls once
the corresponding neutral snapshot and terminal capability are real. Mounted
widgets may publish through an equivalent generic widget-semantic hook. A
renderer must never infer a control merely by recognizing glyphs in the final
screen.

There is no generic `<rich-terminal>` or `<apt>` escape hatch, raw scene
element, owner attribute, terminal ID attribute, or transaction element. A
generic canvas does not become an arbitrary retained command stream. A richer
projector is valid only when a semantic element defines enough backend-neutral
meaning for both CELL and retained renderers.

Supported and admitted semantic items own their final visible claim in the
rich plane. Ordinary fallback paint is still produced for CELL, but the hybrid
residual encoder excludes claimed cells so the rich compositor does not render
or hit-test two representations of one control. Unsupported or refused
semantic items make no claim; their normal drawing therefore remains visible
through the residual path.

### 5.2 Stable identity and geometry

Within one attached UCTX, the backend derives stable projection identity from
the element's pool index and an explicit semantic subkey when one element owns
several retained items. `id=` remains the human-facing UIDL identity and must
be unique when supplied, but it is not hashed into wire authority.

An unchanged semantic element retains its private wire identities across value
updates, minimize/restore, tile movement, full-frame transitions, and relayout.
UIDL document teardown ends that identity. A new UCTX never inherits it even if
the new document reuses every `id=` string.

Bounds come from resolved UIDL layout and are copied into the candidate
relative to its root. The selected candidate metadata carries the positive
root height and width used to normalize and validate those bounds. When a
materializer submits that neutral geometry, the RTAPT provider converts it
directly to the retained profile's full `UNORM32` precision; it does not
truncate through an incidental narrower normalized format. Region movement
changes the private owner region. Layout changes may replace derived object
geometry while preserving element and wire identities. Applications do not
maintain parallel coordinates.

### 5.3 Static and dynamic state

The projector classifies semantic snapshots into:

* static definition state: kind, relationships, formatting, style, labels,
  units, axes, immutable vector geometry, and renderer-independent semantic
  bounds;
* layout state: resolved bounds, clipping, stacking, and visibility inherited
  from UIDL layout; and
* dynamic state: current scalar values, status, media revision, series source
  revision/history, and ordinary element visibility.

These revisions are tracked separately. A scalar, status, or sample-only UIDL
update cannot mark an unchanged static definition dirty. Relayout cannot mint
new item identities. Reset invalidates terminal materialization, not the
classification or UCTX identity.

UIDL dirtying is the only ordinary projection trigger. Applets update bound
state or semantic widget state and use the existing `UIDL-DIRTY!` path. They do
not separately notify the retained backend. The projector must still compare
semantic revisions so a conservatively dirtied ancestor cannot cause unchanged
definitions to be retransmitted.

### 5.4 Semantic resources and series

Image/media and series data belong to their semantic UIDL widget models. Their
snapshot APIs are backend-neutral and usable by CELL renderers, retained
projectors, tests, or future output backends. Application code may populate
those ordinary models; it never implements an APT callback or passes a terminal
descriptor.

A resource snapshot contains semantic format, dimensions, exact byte length,
content digest, monotonically increasing source revision, and a bounded pull
source. The first retained image format is raw row-major sRGB straight-alpha
RGBA8 with no row padding; byte length is checked `width * height * 4`. The
backend calls the source only into its owned staging span, copies or consumes
output before return, and retains no returned byte pointer.

A series snapshot declares semantic sample format, timestamp mode, capacity,
current count, time-axis metadata, monotonically increasing source revision,
and a bounded pull source. The source writes complete records into backend-owned
staging, makes positive progress until the declared count is exhausted, returns
stale without output for an obsolete revision, performs no allocation or
blocking work, and never calls back into UIDL or the backend.

The semantic widget must keep the exact current revision reproducible while its
UCTX is live and that revision remains current. A newer widget revision
supersedes incomplete old work at a transaction-safe boundary. The backend may
pull a source in bounded chunks, but terminal publication of one semantic
history remains atomic under the admitted transaction bounds.

Resource replacement uses a fresh increasing private wire resource ID, uploads
and digest-commits the candidate, atomically replaces surviving references,
then drops the old unreferenced resource. The previous terminal resource remains
authoritative through any failed read, upload, digest, or replacement. Admitted
capacity includes the required old/new overlap.

The backend quiesces every retained source context synchronously before the
host calls arbitrary application shutdown or frees application state. No source
callback is permitted after quiesce succeeds.

## 6. UIDL-TUI projection lifecycle and rich-terminal adapter

UIDL-TUI's neutral lifecycle seam described first in this section is live and
is the integration point for the hybrid producer. The later exact
`RTERM-UIDL-*` records and LABEL materializer describe the dormant prototype,
not a module to reinstall. They are retained as a design inventory until the
forward refactor replaces them; where they prescribe LABEL-only membership,
per-item scans, or repeated deep validation, the hybrid candidate contract
supersedes them.

The public host-facing UIDL lifecycle is neutral:

```forth
UTUI-VISIBLE!  ( visible -- )
UTUI-QUIESCE   ( -- status )
UTUI-DETACH    ( -- )
```

`UTUI-VISIBLE!` synchronizes optional projection geometry, and
`UTUI-QUIESCE` is the retryable pre-application-shutdown source barrier.
`UTUI-DETACH` is the sole public final-detach entry and refuses to clear the
UIDL document unless the adapter's final detach succeeds. Desk, app-shell, and
applet-host use only these generic words.

Outer composition alone installs and enters the private adapter seam:

```forth
_UTUI-PROJECTION-ADAPTER!
    ( context attach project relayout quiesce detach -- flag )
_UTUI-PROJECTION-ATTACH
    ( document-binding visible -- status )
```

Installation is immutable and one-way; attach borrows the document binding
only for the synchronous call and stores only the returned opaque token in the
active UCTX. There are no provider-named compatibility aliases and no public
projection-status getter. Backend choice therefore remains entirely in outer
composition.

The rich-terminal adapter uses the following private ABI above the generic
engine. It is not an engine interface or application service:

```forth
RTERM-HOST-BINDING-SIZE  ( -- bytes )
RTERM-HOST-BINDING-INIT  ( host-binding -- )

RTERM-UCTX-ATTACH    ( host-binding backend -- binding-token status )
RTERM-UCTX-PROJECT   ( binding-token backend -- status )
RTERM-UCTX-RELAYOUT  ( visible region binding-token backend -- status )
RTERM-UCTX-QUIESCE   ( binding-token backend -- status )
RTERM-UCTX-DETACH    ( binding-token backend -- status )
```

The renderer-neutral desired-projection input is defined separately in
[UIDL-PROJECTION-CANDIDATE.md](UIDL-PROJECTION-CANDIDATE.md). Its caller-owned
candidate items use stable UIDL element indices and copied semantic snapshots;
they contain no engine, protocol, screen, Desk, or applet identity. Candidate
construction, private identity mapping, and terminal-eligibility checks are
deliberately wire-inert. After a complete build and RUPJ validation, the driver
maps every nonempty candidate's exact semantic keys to retry-stable private
object IDs. It then reads one coherent neutral `RTE` limits snapshot and either
records terminal-negotiated eligibility or publishes the desired candidate and
its mapping without materialization readiness. Eligibility is not owner or
capture-bank admission and reserves no resource. Neither outcome opens an owner,
captures an operation, chooses an output path, or emits bytes.

The first lifecycle foundation is the optional
`akashic/tui/rich-terminal/uidl-driver.f` module. It constructs the private,
caller-bounded binding registry separately from the retained engine:

```forth
RTERM-HOST-BINDING-CAPTURE  ( host slot host-binding -- status )

RTERM-UIDL-CONFIG-BYTES     ( -- bytes )  \ 104
RTERM-UIDL-BINDING-BYTES    ( -- bytes )
                                            \ 384 per binding
RTERM-UIDL-BACKEND-BYTES    ( -- bytes )  \ 512
RTERM-UIDL-CANDIDATE-ITEM-BYTES ( -- bytes )  \ 128
RTERM-UIDL-CANDIDATE-IDENTITY-BYTES ( -- bytes )  \ 32
RTERM-UIDL-CONFIG-INIT
  ( host engine records-a records-u items-a items-per-bank
    identities-a snapshots-a snapshot-bank-u config -- status )
RTERM-UIDL-INIT             ( config backend -- status )
RTERM-UIDL-FINI             ( backend -- status )
RTERM-UIDL-VALID?           ( backend -- flag )
RTERM-UIDL-STORAGE-DISJOINT? ( a u backend -- flag )
RTERM-UIDL-STATUS@          ( backend -- status )
RTERM-UIDL-ACTIVE@          ( backend -- count status )
RTERM-UIDL-INSTALL          ( backend -- status )
RTERM-AHOST-UIDL-READY      ( host slot host-binding -- ior )
```

This foundation has no `RTAPT-*`, screen-publisher, MegaPad, Desk, or applet
dependency. It borrows one immutable `RTE` facade, and its immutable UIDL
callback installation through `_UTUI-PROJECTION-ADAPTER!` carries the exact
driver backend as explicit composition context; neither context is stored in a
UCTX. The 104-byte initialization descriptor supplies the exact host, engine,
384-byte binding-record slab, and caller-owned candidate storage geometry. Its
record capacity determines exactly two item, two positional identity, and two
snapshot banks per binding. Identity extent is derived from the existing item
geometry, not from a compiled or additional product capacity. The 512-byte
backend copies that geometry, contains one fixed-shape 160-byte limits scratch
and one 176-byte neutral materialization-correlation record, and does not retain
the descriptor or a provider limits pointer. Product
composition may therefore clear the descriptor immediately after initialization.

Each candidate item is 128 bytes: its stable semantic key and snapshot slice
are followed by flags at offset 40, a copied 72-byte resolved record at offsets
48 through 119, and a zero reserved cell at offset 120. `HAS_RESOLVED=1` and
`EFFECTIVE_VISIBLE=2` are the only valid flag bits, and effective visibility
implies a resolved record. Resolved coordinates are normalized relative to
the candidate root. Each bank's 64-byte metadata adds the positive root height
and width after its generation/count/quota fields. In the 384-byte binding,
candidate metadata A begins at 144 and B at 208. Offsets 272 through 343 retain
the private owner tuple, region/object allocation state, eligible selector and
generation, and terminal-checked region/object/UTF-8 quotas. Offsets 344 through
375 retain neutral per-binding materialization state and exact staged/live
generation correlations; offset 376 is the boolean late-discovery retry marker.
The backend-global epoch and materialization attempt record retain only scalar
correlation, never borrowed candidate pointers. Exact phases cover cold, cohort
admission, opening, hidden settlement, reveal settlement, live output, finite
drop, and terminal quarantine. Deep validation correlates every active phase
with its one binding record and frozen attempt before provider mutation is
trusted.

Attach and geometry tracking remain local-only. Attach derives a bounded wire
owner ID from the binding-record ordinal and uses the globally nonreused opaque
binding token as that owner's strictly newer generation. Each generation starts
with private root region ID 1 and object high-water zero. No pointer, markup
`id=`, hash, candidate selector, or current focus becomes wire authority.

Project constructs and deep-validates the inactive neutral candidate, maps its
private identities, and then performs its only facade operation,
`RTE-LIMITS@`. The current narrow retained candidate contains supported LABEL
semantics selected from an otherwise ordinary UIDL tree, zero currently
unsupported resolved attributes, one region, and one object per item.
Terminal-negotiated eligibility requires the corresponding advertised family,
each current text value within `max_label_bytes`, and aggregate current UTF-8
within the owner/global bound. The adapter derives representation capacity from
the current candidate and rebuilds generically when text grows; UIDL does not
reserve terminal storage.
It makes no provider-specific operation-count, retry-copy, or encoded-update
estimate; the neutral plan preflight owns those exact checks.

One caller-owned 32-byte positional identity record copies the exact
`(element-index, semantic-subkey, kind)` and its nonzero object ID. Exact keys
reuse IDs from the previously mapped bank; new keys consume a checked monotone
high-water and may leave legal gaps. Deep validation rejects duplicate object
IDs and never treats `id <= high-water` as existence. Mapping completes before
negotiation, so pending discovery or another negotiation refusal cannot remint
an unchanged semantic key. A successful limits check additionally records the
exact eligible generation and neutral semantic quotas. A deep-valid nonempty
candidate is selector-published with its mapping whether negotiation succeeds or
returns a stable refusal; refusal clears only eligibility/materialization
readiness and its exact status is returned. An empty candidate has no mapping. A
build, deep-validation, or identity-mapping failure leaves the prior selector
and mapping untouched for stable retry but clears their eligibility to remain
displayed and schedules materializer retirement.

`RTERM-SURFACE-SNAPSHOT-INIT` constructs the aligned, call-borrowed neutral
surface observation used by `RTERM-UCTX-MATERIALIZATION-PREFLIGHT`. It contains
positive columns and rows, a nonzero geometry generation, and one zero reserved
cell. The terminal owner or unified publisher supplies that exact surface;
neither the driver nor UIDL infers it from the selected root dimensions, and the
driver retains no pointer or generation from the call.

The materialization-preflight operation copies the complete selected A-or-B
item, identity, and snapshot banks into the global final attempt slot before deep
validation. It borrows only the inactive desired item span for the equal-sized
128-byte neutral plan items. A bounded repeated-minimum scan of the frozen
identity copy produces strict ascending object order without rewriting desired
state or identity mappings. The operation then calls `RTE-LABEL-PREFLIGHT`
exactly once. That boundary revalidates current terminal limits, wire
representability and arithmetic, dynamic owner/tombstone availability, and the
exact caller-owned RTAPT owner, operation, and copied-byte capacity.

The explicit advisory entry scrubs the global attempt slot, borrowed inactive
item scratch, header/limits scratch, and borrowed scalar and pointer cells; its
success is not cached. The bound materializer independently freezes the
then-current selected generation, rebuilds and revalidates the plan, and repeats
preflight immediately before `OWNER_OPEN`. It retains exact pointer-free
correlation across capture, hidden settlement, atomic reveal, supersession, and
tombstone-proven retirement. It never opens a default or root-region-only owner.
Construction and attach admit the exact declared application descriptor,
component descriptor, and live component-state spans as well as the fixed host
objects, and reject every alias with driver storage. Every public stateful
driver operation catches internal throws and scrubs its transient descriptor,
slot, CINST, UCTX, region, and application pointers before returning.

`RTERM-AHOST-UIDL-READY` is the reusable neutral host adapter. Its context is
one caller-owned `RTERM-HOST-BINDING-SIZE` scratch span initialized once by
composition before callback installation. Capture performs the complete alias
preflight without first mutating that span. After a successful capture, the
adapter calls `_UTUI-PROJECTION-ATTACH` under a cleanup boundary so only the
active UCTX receives the opaque token, then unconditionally reinitializes the
now-proven-disjoint descriptor even if attach throws. A capture refusal leaves
the already pointer-free scratch unchanged.

`RTERM-UIDL-FINI` is the matching host-unbind boundary. It succeeds only when
the backend has no live bindings, clears the binding records and all item,
identity, and snapshot bank slabs, then clears the backend. It therefore removes
the borrowed AHOST pointer before that host can be freed. A live-binding refusal
leaves every byte intact for quarantine. The immutable UIDL callback table may
retain the same stable backend address; a later exact host may reinitialize and
reinstall that address idempotently.

`host-binding` is an immutable, call-borrowed descriptor containing ABI
version, exact size, zero-reserved fields, the exact `AHOST` and `AHS` slot
addresses, captured nonzero `AHS.ID`, exact CINST address and captured nonzero
`CINST.ID`/`CINST.GENERATION`, exact UCTX address, and exact current region.
The UIDL-TUI driver never retains the descriptor address. It validates and
copies the complete authority tuple, then returns one opaque nonzero internal
token. The generic engine never receives the descriptor or learns any
`AHOST`/`AHS`/CINST/UCTX identity; the private adapter translates a validated
binding into engine owner and output operations.

The token names a backend-owned record and an exact nonreusable binding
generation; it is not a naked binding-record address. It is valid only with the
backend that issued it and is stored only in host-private slot state. Every
later call validates the token/backend/generation and revalidates that the host
still contains the exact live slot, `AHS.ID`, CINST pointer and generation, and
UCTX before dereferencing UCTX or application-owned state. A foreign backend,
unlinked or reused slot, changed activation generation, changed UCTX, or stale
token returns `RTERM-S-STALE` without mutation.

A composition-owned root UCTX, if present, must have a real composition-owned
host slot and activation satisfying the same descriptor and validation; zero
or invented host authority is not a special case. There is no
application-callable variant and no returned application scope.

### 6.1 Attach

Attach occurs after the UCTX document is loaded and its host slot and region
exist. The UIDL-TUI driver verifies that its configured host is the descriptor host;
the slot is linked exactly once, live, and has the captured `AHS.ID`; the slot's
instance is the exact CINST pointer with matching live ID/generation; and its
UCTX and region are the exact descriptor values. Repeating attach with the
complete exact tuple returns the same live binding token idempotently. Reusing
a UCTX, slot, or CINST component with a different tuple is stale or invalid.

Attach reserves one preallocated binding record but has no wire side effect.
The first projection, after normal application initialization and binding,
walks the complete semantic tree, validates all retained-capable snapshots,
derives exact requested quotas, maps stable private identities, and atomically
selects the complete desired snapshot in caller-bounded storage. Required local
item/snapshot counts, byte capacities, and storage overlap must be valid before
that snapshot is selected. Provider operation, retry-copy, and encoded-update
arithmetic is deliberately deferred to the separate neutral preflight. Local
attach and this first complete desired snapshot may occur while retained
discovery is still pending. Pending discovery returns `RTERM-S-WOULD-BLOCK` and
leaves the selected snapshot and mapping intact but grants no materialization
readiness and authorizes no wire owner. When discovery becomes available, the
owner-loop service renegotiates that selected candidate in place; it does not
wait for another UIDL dirty event. The requested quotas must fit the current
terminal maxima before `OWNER_OPEN` is emitted. Each bounded owner-loop step
performs at most one shared limits read. Continued `WOULD_BLOCK` preserves an
already-live coherent retained presentation only for its exact current surface
generation. A completed read deep-validates every marked selected bank before
publishing any settlement; `INVALID` or `SESSION_LOST` quarantines before the
ordinary update-state poll and materializer dispatch.

Terminal-negotiated eligibility freezes the exact current semantic bytes for
one desired generation for explicit advisory materialization preflight; it is
not an owner reservation or UIDL promise. A text-length change builds another
complete candidate and the adapter derives a new retained reservation. That
operation constructs the exact plan and calls
`RTE-LABEL-PREFLIGHT` to prove local provider capture-bank fit and dynamic owner
availability, then scrubs the frozen attempt and plan. The materializer repeats
the proof against the then-current generation immediately before owner
admission. If current content exceeds caller or terminal bounds, projection
reports capacity, revokes eligibility, retires prior rich output, and CELL
rendering continues from the authoritative UIDL tree. A later fitting value
reuses the same semantic key and object identity. A settled `CAPACITY` or
`SOURCE` result is binding-local: admission
skips that record, while a post-admission capture refusal cancels and retires its
exact owner before the cohort advances. Neither result latches a publisher fault
or invalidates the authoritative CELL tree. Representation failures currently
map through these same two neutral local-refusal statuses; unclassified and
structural failures remain fatal rather than being guessed into fallback.

Unavailable retained discovery or an unsupported optional semantic family
does not prevent attach or application initialization. The binding retains its
newest deep-valid desired snapshot and stable mapping but remains a CELL-fallback
binding with no wire owner until a materializer can admit that snapshot.

### 6.2 Project

Project runs with the token's exact UCTX active after normal UIDL binding
updates and layout. The current projector walks the complete active tree under
the fixed observation order UIDL-TUI, UIDL, RUPJ, then semantic state. It
captures every eligible neutral LABEL snapshot into the binding's inactive
bank and asks UIDL-TUI for the corresponding resolved record. `OK` copies and
validates the record root-relative and sets the resolved flags;
`UNAVAILABLE` preserves semantic membership with zero resolved payload and
flags; `INVALID` fails the complete projection. It validates the finished bank
with `RUPJ-CANDIDATE-VALID?`, using the same positive root height and width,
and writes the selector only after its 64-byte metadata is complete. It never
asks an applet to enumerate a second scene.

Candidate selection, identity mapping, and terminal-negotiated eligibility are
separate atomic facts. A build, deep-validation, or identity-mapping failure
preserves the prior selected copied recipe and mapping for retry-stable identity
while revoking their display eligibility; UIDL and CELL state remain untouched.
An accepted empty recipe supersedes the former candidate but
reports `RTERM-S-UNAVAILABLE`. Every deep-valid nonempty recipe maps its stable
private IDs and supersedes the former candidate; `RTERM-UCTX-PROJECT` then
returns the exact limits result, including `RTERM-S-OK`,
`RTERM-S-WOULD-BLOCK`, `RTERM-S-UNAVAILABLE`, or `RTERM-S-CAPACITY`. A non-OK
negotiation result clears only eligibility/materialization readiness, not the
selected candidate, its mapping, or the monotone identity high-water. No
protocol byte is emitted from an element or widget callback. Layout/style state
is now part of the locally accepted desired recipe. The neutral RTE/RTAPT LABEL
path, lifecycle materializer, and unified publisher binding exist below it. They
remain narrow development plumbing rather than a production capability. They
prove useful lifecycle and physical-sink seams, but do not render the
substantive Desk, Pad, or Daybook frame required by Section 11.1.

The first materialization in an epoch is a complete projection obligation, not
an ordinary dirty-element update. Transition to retained availability, and
rediscovery after reset, must materialize or replay every eligible live binding
from its accepted complete desired snapshot, or force a complete current
projection with that binding's exact UCTX active. This work must not depend on
a later incidental UIDL dirty event: the CELL paint which supplied the initial
snapshot may already have consumed the document's dirty flags.

One ordinary projected UIDL update must fit one admitted APT output
transaction. Initial construction, reset replay, and relayout reconstruction
may use the wire profile's hidden bounded multi-transaction build followed by
one reveal. The backend never exposes a partially rebuilt UCTX merely to evade
an admitted bound.

### 6.3 Relayout and visibility

Relayout runs after ordinary UIDL layout has resolved the UCTX. `region` is the
current root Akashic region and `visible` is the host's actual minimize/restore
state. Moving or resizing a tile updates the owner region and derived layout
without changing semantic element, private object, or resource identities.
Geometry change or hiding may revoke terminal eligibility/materialization
readiness for a stale resolved recipe, but it preserves the exact key-to-object
mapping and monotone high-water needed by the next projection or restore.

Desk keeps one region descriptor for each linked child slot and updates its
bounds in place. Minimize publishes hidden visibility before any later layout,
and restore performs ordinary UIDL layout before publishing visible geometry.
A slot already past its callable `LIVE` phase is excluded from collection,
full-frame selection, activation, relayout, and region mutation; its exact
descriptor and bounds remain unchanged through retirement resolution.

A hidden UCTX needs no fabricated geometry. While hidden, the backend sends no
ordinary scalar, series, or resource updates for it. UIDL/widget changes still
advance the copied desired state; scalars coalesce and series retain the newest
complete reproducible revision. Restore publishes one coherent latest view,
reusing static definitions unless they changed or terminal materialization was
lost.

For a UCTX whose retained projection is unavailable, relayout is an idempotent
successful no-op. A transient refusal is retained as a backend diagnostic and
retried from the newest UIDL geometry. It does not roll back Desk layout or
force an unsafe transport fallback.

### 6.4 Pre-shutdown quiesce

Quiesce is host-owned and must run before arbitrary `APP.SHUTDOWN` for every
successfully attached binding. It makes the token unavailable to project and
relayout, synchronously detaches every semantic resource/series source XT and
context, aborts or converts dependent local staging into source-free state, and
records the exact allocation-free retryable owner-drop obligation. It retains
no callback or application-state pointer that shutdown may free.

Quiesce may return `RTERM-S-OK` while terminal egress or an owner-drop result is
pending because the bounded tombstone is independent of the UCTX. It may not
return OK unless local callback detachment is proven. On any other status the
host must not call `APP.SHUTDOWN` or free application/widget/source state; it
must preserve the live tuple and retry or enter coordinated terminal teardown.
Repeated quiesce for the exact token is idempotent.

### 6.5 Detach

Final `UTUI-DETACH` is host-owned and runs after application shutdown, but
before `UCTX-FREE`, `CINST-FREE`, region free, or host-slot reuse. Before it
dematerializes or clears the UIDL document, UIDL-TUI invokes the adapter's
private detach callback with only the exact token and quiesced source-free
binding. That callback never calls application code or a semantic source.

The adapter callback is allocation-free and atomically:

1. makes the binding stale for project and relayout;
2. verifies quiesce removed every source XT/context, then removes all borrowed
   UCTX, widget, CINST, host-slot, and region pointers from pending state;
3. aborts local staging and obsolete in-flight replacement work;
4. records the exact owner-wide terminal drop obligation in the binding record;
   and
5. releases projection storage the tombstone no longer needs.

Once that local transition succeeds, the adapter returns `RTERM-S-OK` even if
egress is blocked. `UTUI-DETACH` then clears ordinary UIDL state, after which
the host may free the UCTX, CINST, region, and slot. The backend retains only
the private wire owner/generation and bounded drop progress; it contains no
pointer back into those freed objects.

Adapter detach is idempotent. A binding record becomes reusable only after
exact owner drop is acknowledged or a confirmed epoch/session destruction proves that the
retained terminal state cannot survive. A UCTX that never materialized a retained owner
creates no wire tombstone.

### 6.6 Generic applet-host composition seam

The generic applet host names no rich-terminal engine or wire protocol. An
explicit product composition may configure one neutral `AHOST` callback plus
an opaque, separately owned context:

```forth
AHOST-UIDL-READY!  ( xt context host -- )
\ xt                ( host slot context -- ior )
AHOST-QUIESCE-ALL  ( host -- ior )
```

Desk exposes only the constructor boundary
`DESK-HOST-LIFECYCLE! ( init-xt fini-xt context -- )`; both callbacks use
`( host context -- ior )`. After its generic host and runtime services are
initialized but before launching any child, Desk invokes composition init,
which may install the exact `AHOST-UIDL-READY!` callback pair. Immediately
after `AHOST-DRAIN` succeeds and before freeing any Desk runtime state, it
invokes composition fini so the callback and every borrowed host pointer can
be removed. It does not inspect the context, name an output backend, or
allocate composition storage. A fini refusal hard-gates every later Desk
destructor. Desk claims the init phase before entering the callback, so the
matching fini is also invoked after an init refusal or throw; composition fini
must therefore be safe and idempotent for every partially initialized state.

The host invokes the callback exactly once for a launch after ordinary UIDL
load and initial region assignment have succeeded, while the exact UCTX is
active, and before crossing the application-initialization boundary. A zero
callback is the baseline configuration. The callback may capture the exact
binding and enter UIDL-TUI's private projection attach, but the host neither
allocates adapter state nor learns the callback context's type. A callback
refusal enters normal transactional launch rollback.

Each linked slot records an independent retirement phase: `LIVE`, `QUIESCING`,
`QUIESCED`, `SHUTDOWN-CLAIMED`, or `DETACHED`. `AHS.STATE` remains the ordinary
running/minimized/focused state so authority validation sees the original live
tuple through final detach. On the first close attempt the host stores
`QUIESCING` before calling `UTUI-QUIESCE` and, for a child which crossed
application init, invoking its optional `APP.QUIESCE-XT`. Only both barriers
plus the final UCTX save succeeding store `QUIESCED`. A refusal preserves the
linked slot, ID, CINST, UCTX, region, UIDL buffer, projection attachment, and
exact activation tuple. The slot becomes noncallable: focus, input, tick, paint, and
application close callbacks must not reach it, while a later host
quiesce/drain attempt may retry the barrier.

After quiesce succeeds, the host stores `SHUTDOWN-CLAIMED` before activation or
`APP.SHUTDOWN`, so a thrown shutdown callback is never repeated. It then runs
`UTUI-DETACH`, the sole public final detach for both projection and document,
with the exact UCTX restored. `AHS.HAS-UIDL` remains true until that detach
succeeds. A detach refusal preserves every child
resource and returns a not-closed result; it cannot trigger relayout or a drain
spin. Only `DETACHED` authorizes owner-resource release, unlink, callback
notification, and freeing the UIDL buffer, UCTX, region, CINST, and slot.

Aggregate close negotiation treats a slot already past `LIVE` as previously
approved, without invoking application code. The outer lifecycle owner then
retries `AHOST-QUIESCE-ALL` and maps an actual barrier refusal to its own defer
or quarantine state. Any relayout implementation that walks `AHS` directly
must skip noncallable slots completely; in particular it must not activate the
slot, replace or free its retained region, or run ordinary UIDL relayout while
retirement is unresolved.

## 7. Frame projection and atomic publication

UIDL-TUI CELL painting remains the universal path. In the rich composition,
painting a dirty attached UCTX also stages its retained projection. The global
screen flush and internal retained backend then serialize through the one APT
output publisher and the one shared transaction-ID/revision clock.

When one logical UI frame changes both CELL and retained state, the unified
output publisher commits the applicable CELL spans/cursor and retained
operations in one atomic terminal update transaction, delimited on the APT-1
wire by `PRESENT_BEGIN` and `PRESENT_COMMIT`. A failed combined commit cannot
advance the screen front buffer or the retained materialization independently.
A frame with no retained changes remains an ordinary valid CELL transaction; a
retained-only update may use `CELL_NONE` under the wire recovery rules.
When a completed draw is retained-identical but still requires a new physical
revision, the producer uses one idempotent replacement of an acknowledged
retained slot as the nonempty `RET_DELTA` revision fence. It prefers a canonical
invisible glyph slot and falls back to an unchanged control or visible glyph;
only a model with no reusable object may take complete replacement instead.

`PRESENT_BEGIN`, `PRESENT_COMMIT`, and `presentation_epoch` are frozen APT-1
wire names only. There is no protocol object or Akashic architectural layer
called a Presentation; the Akashic concepts here are retained materialization,
transactions, and unified publication.

The backend serializes dependencies before references and preserves static
definition/drop ordering. It may coalesce superseded scalar, visibility, and
complete source revisions before publication. It may not coalesce across owner
generation, reorder around definition/drop, invent series samples, or split an
ordinary semantic update into terminal-visible partial state.

The CELL representation remains complete even when a retained counterpart is
visible. Retained projection may enrich, overlay, or replace physical treatment
inside its owned region according to the renderer contract, but loss or absence
of the optional rich-terminal path leaves a usable UI rather than a blank
reserved area.

## 8. Bounded backend service and cadence

Only the terminal/Desk owner loop advances publication:

```forth
RTERM-BACKEND-STEP  ( work-budget backend -- status more-work? )
```

`work-budget` is a positive host-selected number of logical operations or
source chunks. The backend performs at most that work, services live UCTX
bindings fairly, and returns truthful quiescent, more-work, backpressure, or
structural status. It never spins until credit appears, waits for a response,
allocates a resend buffer, recursively pumps Desk, or calls `PT-SERVICE` as a
second session owner.

The service owns the discovery-transition obligation. On `AVAILABLE`, it
schedules complete initial materialization for each eligible visible binding;
after reset it schedules the same complete replay in the new epoch. Hidden
bindings retain their newest accepted desired state and defer materialization
until restore. A terminal `CELL-ONLY` answer leaves local attachments and
application lifecycle intact but never schedules `OWNER_OPEN`.

Fairness applies at protocol-safe boundaries. Once the session-global immutable
resource upload is open, it completes or aborts before another upload,
transaction, or lifecycle request begins. A large image or series cannot
permanently starve current scalar/readout changes in other UCTXs.

Physical display cadence is a renderer policy over committed global
revisions, not an application API. UIDL/widget updates retain their own domain
timestamps; cadence never invents sample timing. Input is delivered only
against a physically displayed revision as required by RETAINED-1.

## 9. Composition and host order

Any explicit rich product composition may construct the generic engine and
bind an appropriate consumer adapter. The Desktop APT-1 profile does so from
`tui/desk-apt1.f`, binding the hybrid producer through UIDL-TUI's private
lifecycle seam. This is product composition, not engine ownership by Desk. A
standalone shell or another non-UIDL Akashic consumer may compose the same
engine without loading Desk or UIDL-TUI. The baseline `desktop` profile does
not load the APT-1 engine or construct rich-terminal state.

The deployment boundary is strict. MegaPad owns the optional boot-loaded
`rich-terminal.f`; a rich product profile loads it before any Akashic
rich module. Akashic never source-`REQUIRE`s or copies that module. Its rich
modules consume only the already-loaded public PT ABI. Baseline profiles load
neither the optional PT module nor the Akashic rich modules, so their source
closure, startup, storage, and output behavior remain unaffected.

The Desktop leaf constructs its concrete layers in dependency order: PT
session, neutral `APTSCB`, caller-bounded `RTAPT`, immutable `RTE` facade,
unified `RTAPTSCB` publisher attachment, the draw-keyed `RUHA` aggregate
adapter, the `RTHP` hybrid producer, and finally the `APTAS` shell owner. Desk
sizes aggregate directory, semantic record/text, claim, residual-span, and
frozen-attempt storage from its installed-document and screen bounds. The
producer installs one hybrid `STEP`/`PREPARE` contribution in the existing
publisher seam; it does not create another session or application scene. Setup
and release continue to publish explicit phases so a constructor or destructor
refusal retains the smallest exact retry authority rather than clearing an
uncertain terminal-output lifecycle.

The name `desk-apt1.f` identifies that opt-in product composition, not a second
Desk implementation or a rich Desk behavior. Both baseline and APT-1 products
load the same `applets/desk/desk.f`; Desk supplies only neutral host-lifecycle
hooks. App descriptors, UCTX, UIDL trees, and Desk layout behavior do not
branch on regular versus rich rendering.

Desk and applets remain ordinary, renderer-neutral UIDL producers. They do not
call the APT-1 adapter, select a terminal renderer, or own the output
materializer. `desk-apt1.f` is the outer product leaf that binds the neutral
UIDL lifecycle callbacks to the APT-1 output adapter; that binding does not add
a rich variant to Desk or any lower-level component.

UIDL-TUI now presents `UTUI-VISIBLE!`, `UTUI-QUIESCE`, and `UTUI-DETACH` to
Desk, app-shell, and applet-host. Those layers contain no adapter or provider
choice. The `_UTUI-PROJECTION-*` attach/install seam is private to outer
composition, where backend choice remains; no compatibility aliases preserve
the former renderer-specific lower-layer surface.
The leaf disarms Desk's pending constructor tuple after each `DESK-RUN`
attempt, including a throw; a quarantined instance keeps its already-copied
tuple, while a later plain Desk constructor cannot resurrect a partial rich
composition after the outer storage was released.

That construction does not itself claim retained semantic support. The
provider side now accepts a neutral LABEL through `RTE`, captures a
pointer-free RTAPT retry record with exact object/UTF-8 ledgers, and dispatches
it through the typed PT writer. The neutral facade and provider now also accept
the exact mutation-free LABEL plan and can preflight its representation,
caller-owned capture banks, current owner/tombstone availability, terminal
quotas, and complete START arithmetic before `OWNER_OPEN`. The lifecycle driver
selects a complete deep-valid candidate together with private, retry-stable
identities before negotiation, and separately records terminal-negotiated
eligibility when the current limits permit it. A refusal preserves the selected
candidate and mapping. A retained-only wire rejection also preserves eligibility
and either re-offers the provider-retained sealed candidate or retires admitted
owners before rebuilding it. Settled local capacity/source refusal preserves
CELL, revokes only the refusing binding's retained readiness, and skips it only
after any admitted owner reaches an exact tombstone. The unified `RTAPTSCB`
bridge admits one optional
immutable, caller-bounded neutral output producer, and the APT-1 composition now
binds the UIDL driver to that seam. Its callbacks receive only the exact observed
screen columns, rows, monotone geometry generation, and a composition-selected
work budget. Engine reconciliation precedes each producer `STEP`. The adapter
always observes the current screen surface, but invokes `PREPARE` only when the
producer has returned canonical `OUTPUT_NEEDED` and an output attempt is
actually being offered. Thus an unrelated CELL flush does not manufacture a
retained materialization attempt.

`STEP` may preflight and admit the newest complete candidate, retire a
superseded owner, or advance hidden materialization within its caller-selected
budget. `PREPARE` only freezes the already-scheduled output contribution for
the shared transaction. The bridge carries canonical `more-work` and
`output-needed` observations, schedules no recursive service loop, and latches
the first fatal neutral producer or engine result across ordinary scheduling.
Reconstruction or retirement clears that latch; synchronized teardown remains
able to settle an already-admitted completion without scheduling new lifecycle
work. None of these callbacks executes applet code or stores application state.

Retained discovery is not a hosted-UCTX launch gate. The mandatory initial CELL
snapshot is produced only after Desk initialization, so host composition,
autostart, local UIDL attach, ordinary application initialization, and the
first complete desired semantic snapshot may all precede discovery settlement.
Attach and project remain locally bounded and wire-inert at that boundary.
The owner-loop service later responds to `AVAILABLE` by renegotiating the newest
selected candidate in place, proving local capture-bank and owner availability,
and scheduling complete materialization rather than waiting for another UIDL
dirty event. A final `CELL-ONLY` answer selects stable CELL fallback and never
opens a retained owner; applet initialization does not poll terminal features
and sees no different service table.

The host lifecycle order is:

1. allocate/register the activation, UCTX, and region;
2. load UIDL and perform initial layout;
3. build the immutable exact host-binding descriptor, attach internally, and
   store the returned token only in host-private slot state;
4. run ordinary application initialization and state/widget binding;
5. paint CELL and project retained semantics from the same active UCTX;
6. publish through the shared frame transaction;
7. on geometry change, run UIDL relayout then retained relayout;
8. before `APP.SHUTDOWN`, call `UTUI-QUIESCE`, then the application's declared
   `APP.QUIESCE-XT`, and record retryable retirement, refusing shutdown if
   either callback-detachment barrier is not proven;
9. after all hosted UCTXs are source-free, close the optional terminal owner
   and prove ANSI safety;
10. run application shutdown, then `UTUI-DETACH` while the exact host tuple is
    still live; and
11. free UCTX, activation, region, and host slot.

The top-level shell performs step 8 as a two-part barrier: it first calls
`UTUI-QUIESCE` for its own UIDL document, if present, then invokes the neutral
`APP.QUIESCE-XT ( instance -- ior )` descriptor callback. Desk implements that
callback only by calling `AHOST-QUIESCE-ALL`, which applies the same ordering
to every child. A refusal or throw is a hard pre-terminal close gate. The shell
preserves its descriptor, instance, UIDL, active UCTX,
root region, terminal owner, posted work, and screen state in quarantine and
runs no later destructor. The same quarantine rule applies if terminal close,
application shutdown, or `UTUI-DETACH` fails. A quarantined top-level
lifecycle is not repaired by the retained backend's APT soft reset, an
`ASHELL-RUN` retry, or terminal-owner release, and the shell exposes no
in-process clear API. It requires an externally confirmed attachment hard
reset/drain followed by fresh module or image initialization. The shell never
repeats an arbitrary shutdown callback after claiming it.

The host must save a mutated active UCTX before switching away. Retained
projection cannot depend on unsaved global UIDL pools belonging to some other
active child. It either runs while the exact UCTX is active or reads a validated
saved snapshot through UCTX-owned accessors.

## 10. Reset, replay, and loss

The backend privately tracks session identity and the frozen wire field
`presentation_epoch`; that field name does not introduce a Presentation object
or layer. A successful soft reset invalidates terminal materialization and
private wire identities, not live UCTX attachments.

On an accepted reset boundary, the backend:

1. abandons old-epoch transmission and chunk progress;
2. marks every live region, resource, definition, layout property, and dynamic
   property as not materialized;
3. clears only tombstones whose old retained terminal state is now proven absent;
4. obtains or retains a complete current semantic snapshot for each visible
   live UCTX; and
5. schedules hidden reconstruction and atomic reveal through new private wire
   owners.

Replay order per UCTX is region, immutable resources, series definitions,
static groups/objects, layout, current scalars/status/visibility, current
complete series history, then reveal. Dependencies precede references. A reset
during resource or series transfer restarts that transfer from zero in the new
epoch.

Copied static and latest dynamic recipes may be used when their UCTX and source
revisions are still exact. Otherwise the generic projector regenerates them
from the authoritative live UCTX. No retained terminal state or raw frame archive is
authoritative. Hidden UCTXs defer replay until restore; detached UCTXs are
never replayed.

CELL snapshot reconstruction and retained reconstruction are separate dirty
obligations sharing one session epoch. Clearing the CELL snapshot latch cannot
clear retained replay. A structural loss after binary `OPEN` freezes ordinary
publication and follows APT quarantine; it never selects raw ANSI on the same
uncertain attachment.

## 11. Phase boundary and completion

UIDL/UCTX integration is Phase 3, not deferred work. Phase 3 does not ship an
application-facing rich-terminal broker as a bridge and does not require any
applet to maintain terminal-specific output state.

The first complete vertical is the canonical Desk with Pad and Daybook both
launched and live. It uses the same applet descriptors, ordinary UIDL
documents, mounted widgets, application state, Desk tiling/focus/input loop,
and normal TUI draw lifecycle in baseline and rich compositions. Without
applet APT imports, terminal-mode branches, renderer reservations, or direct
scene calls, it must demonstrate:

* complete CELL fallback;
* automatic UCTX attach and exact owner admission;
* one renderer-neutral rich projection derived from the ordinary TUI draw
  lifecycle, covering Desk chrome, UIDL renderers, mounted widgets, and applet
  painting reached through the normal draw boundary;
* dynamic bound-state updates without retransmitting unchanged definitions;
* stable element/object identities across relayout and minimize/restore;
* atomic CELL plus retained publication where both change;
* physical display of every nonempty plane in the selected immutable composite
  before its revision becomes input-eligible;
* reset reconstruction from live UCTX semantics;
* allocation-free detach and exact owner retirement before UCTX free;
* a visible Pad editor whose real edit and caret/state change are supplied by
  the rich path; and
* a visible Daybook month/agenda whose real navigation or selection change is
  supplied by the rich path, followed by the ordinary Daybook-to-Pad shared
  resource route.

Focused generic semantic/draw fixtures may qualify bounded implementation
slices while the backend is being built, but no fixture is the vertical.
Closure uses unchanged production applet sources rather than a handwritten
projection. Pad and Daybook are acceptance applications, not protocol object
types: no particular applet is built into the architecture or protocol.

Image/resource lifecycle remains part of Phase 3 closure when the composition
advertises that semantic family. A stock image can qualify codec mechanics but
cannot replace the generic UIDL media lifecycle, fallback, reset, and detach
journey.

### 11.1 Desk, Pad, and Daybook acceptance checkpoint

The blocking cross-repository path is the real product composition:

```text
Desk + ordinary UIDL renderers + mounted-widget/app draw state
  -> renderer-neutral candidate and stable identities
  -> RTE/RTAPT materializer
  -> unified CELL/retained publisher
  -> MegaPad PT wire and retained model
  -> immutable composite
  -> production compositor/view sink pixels
```

The current per-cell screen bootstrap establishes owner settlement, immutable
offers, unified publication, hidden replacement/reveal, and physical-ACK
plumbing. The dormant LABEL experiment separately establishes useful semantic
capture, attachment, and stable-identity ideas. Both remain lower-stack design
evidence; neither is the product candidate. They cannot stand in for the
checkpoint because neither provides the hybrid semantic-control and unclaimed
residual coverage required for Desk chrome, Pad's editor body, and Daybook's
calendar/agenda.

Acceptance requires the complete visible Desk frame, both applets live through
their normal descriptors, at least one real Pad edit and one real Daybook
navigation or selection, and the normal shared-resource handoff from Daybook to
Pad. Every substantive Desk/editor/calendar plane selected for rich output must
survive owner admission, publication, the immutable offer boundary, and
physical composition. The displayed revision and revision-bound input advance
only after every nonempty selected plane has been flipped and exactly
acknowledged.

CELL remains complete and authoritative fallback. It may provide fallback for
an unsupported or refused binding, but a frame whose substantive Desk, editor,
or calendar pixels came only from CELL does not qualify the rich path. A byte
transcript, active retained model, promoted composite, one LABEL, or
applet-specific scene likewise does not complete the checkpoint.

The renderer-neutral boundary may expose semantic text, layout, state, and
generic draw operations. Physical font choice, pixel geometry, clipping,
alpha, rasterization, buffering, and composition remain MegaPad work. A true
cross-renderer content maximum may be generic UIDL behavior; a retained text
reservation is not and must be derived below UIDL from current content and
caller-provided bounds.

This checkpoint does not weaken the capability contract. `RET_INSTRUMENT`
covers LABEL, READOUT, METER, and STATUS as one family, so the checked-in
production policy remains `retained_policy=None` until the terminal model and
renderer truthfully implement every advertised member. A focused LABEL fixture
is lower-stack development evidence, not permission for partial production
advertisement or a substitute for the Desk/Pad/Daybook journey.

### 11.2 Pre-vertical qualification gate

Before vertical closure, each bounded implementation slice is qualified only
with seconds-scale structural tests, byte-oracle tests, focused state-machine
units, and deterministic off-screen compositor units appropriate to that slice.
Focused guest selectors are permitted only when they remain seconds-scale and
exercise a generic seam needed by the acceptance composition; no root-LABEL or
applet-specific selector defines the vertical. Each coherent slice receives
its own progress commit after those lightweight checks pass.

Cold source qualification, exact-single-full-core runs, Desktop smoke,
end-to-end integration, persistence, sustained-cadence, and renderer checks are
deferred until the vertical is closed. At that boundary they run sequentially,
never concurrently, before production handoff. A lightweight pre-closure result
must not be represented as qualification of the complete vertical.

## 12. Initial conformance cases

The lightweight contract suite must prove:

1. baseline Desktop constructs no retained backend, while rich Desktop owns
   exactly one internal session backend that is absent from every application
   service lookup;
2. negative retained discovery leaves the same UIDL documents fully usable
   through CELL/ANSI and creates no wire owner;
3. two live UCTXs attach to the same backend through immutable exact
   host/slot/CINST/UCTX descriptors but receive distinct generation-checked
   private tokens and wire bindings;
4. an unregistered, unlinked, reused, detached, foreign-host, mismatched CINST
   generation or UCTX, foreign-backend token, or stale token is rejected without
   consuming an owner record or mutating wire state;
5. configuration overflow, wrap, misalignment, and overlap fail before changing
   supplied storage, while a negotiated-budget refusal preserves the newest
   deep-valid candidate and stable mapping but grants no materialization
   readiness;
6. a complete semantic-tree candidate maps exact stable IDs before negotiation,
   derives exact quotas, and its neutral plan preflight rejects malformed or
   unrepresentable geometry, insufficient local capture banks, unavailable
   dynamic owner/tombstone state, or excessive exact START bytes before
   `OWNER_OPEN` and without owner or wire mutation;
7. UIDL labels, units, styles, points, scalar values, and semantic snapshots are
   copied or revision-bound so later scratch mutation cannot change committed
   projection;
8. one static UIDL projection followed by scalar and series dirty updates emits
   no duplicate unchanged definitions;
9. resource and series sources are pulled only in bounded chunks, reject stale
   revisions, and are never called after detach begins;
10. an exact `STEP` budget is honored and downstream backpressure causes no
    spin, loss, reordering, or hidden allocation;
11. minimize suppresses ordinary retained output, coalesces latest semantic
    state, preserves private identity mappings, and restore publishes one
    coherent current projection;
12. relayout changes region/layout geometry and may revoke materialization
    readiness while semantic and wire item identities remain stable;
13. reset during an incomplete source transfer rebuilds the complete visible
    projection from current UCTX semantics;
14. a frame changing CELL and retained state advances both atomically or
    neither, including screen front-buffer bookkeeping;
15. pre-shutdown quiesce synchronously detaches every source and creates an
   allocation-free exact-owner tombstone; failure prevents `APP.SHUTDOWN` and
   state free, while successful final detach scrubs all host pointers before
   UCTX, CINST, widget state, region, or slot free; and
16. no production applet imports APT/rich-terminal modules, discovers a retained
    service, stores a scope, or issues a scene operation.

The real Desktop/Pad/Daybook journey, reset, all-advertised-family renderer, and
sustained-cadence cases are deferred sequential acceptance/qualification. They
may not justify larger hidden capacities, weakened teardown, or an
application-specific rich-terminal path.
