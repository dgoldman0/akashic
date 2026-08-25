# Akashic rich-terminal engine and UIDL output contract

Status: normative pre-vertical contract for the Phase 3 Akashic rich-terminal
mode and its UIDL output integration.

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

## 1. Non-negotiable architecture

UIDL is the sole application-facing UI description. A hosted component owns its
ordinary domain state and uses the existing UIDL element tree, bindings,
subscriptions, semantic widgets, dirtying, layout, focus, and event mechanisms.
The same `UCTX` owns that UI for the complete activation lifetime.

The implementation has two layers. One generic, consumer-neutral Akashic
`RTAPT`/`RTERM` engine owns retained wire lifecycle for one live enhanced
terminal session. It uses caller-bounded storage and has no knowledge of
`AHOST`, `AHS`, CINST, UCTX, Desk, or any applet. An explicit composition may
use that engine outside Desk and UIDL-TUI without acquiring a second protocol
or session implementation.

Above it, the optional UIDL-TUI rich-terminal driver adapts UIDL semantics to
the generic engine. Desk and the applet host attach, project, relayout, and
detach UCTXs through private driver operations. A Desk-owned UIDL context, when
present, follows the same path as a child UCTX; Desk UI code does not author a
retained scene manually.

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
* admitted quotas, copied projection state, progress, and retirement state.

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
| 3 | `RTERM-S-CAPACITY` | Caller-owned or negotiated capacity cannot admit the projection. |
| 4 | `RTERM-S-STALE` | The UCTX, activation binding, source revision, or terminal materialization is no longer current. |
| 5 | `RTERM-S-INVALID` | An argument, semantic snapshot, storage configuration, state transition, or callback result is invalid. |
| 6 | `RTERM-S-SESSION-LOST` | The enhanced session crossed a structural loss boundary. |
| 7 | `RTERM-S-SOURCE` | A semantic resource or series source failed. |

These statuses do not throw through an applet callback and are not returned to
application rich-terminal code, because no such code exists. The UIDL host
records the first non-transient backend error for inspection while leaving
application state intact. One failed projection cannot authorize mutation of
another binding, and a post-`OPEN` structural loss never makes raw ANSI output
safe.

`RTERM-S-WOULD-BLOCK` is transport progress, not local projection-capacity
failure. Already accepted desired state remains accepted while egress is
blocked. `RTERM-S-CAPACITY` and `RTERM-S-INVALID` are fail-before-mutation at
each local admission boundary.

## 4. Generic engine construction and caller-owned storage

An optional composition constructs the consumer-neutral engine with:

```forth
RTERM-BACKEND-INIT     ( config backend -- status )
RTERM-BACKEND-FINI     ( backend -- status )
RTERM-BACKEND-STATUS@  ( backend -- status )
```

`RTERM-*` names the consumer-neutral Akashic contract. The APT-1
implementation uses the collision-free `RTAPT-*` prefix and is only one engine
implementation; the UIDL-TUI adapter does not depend on that concrete prefix.

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

There is no generic `<rich-terminal>` or `<apt>` escape hatch, raw scene
element, owner attribute, terminal ID attribute, or transaction element. A
generic canvas does not become an arbitrary retained command stream. A richer
projector is valid only when a semantic element defines enough backend-neutral
meaning for both CELL and retained renderers.

### 5.2 Stable identity and geometry

Within one attached UCTX, the backend derives stable projection identity from
the element's pool index and an explicit semantic subkey when one element owns
several retained items. `id=` remains the human-facing UIDL identity and must
be unique when supplied, but it is not hashed into wire authority.

An unchanged semantic element retains its private wire identities across value
updates, minimize/restore, tile movement, full-frame transitions, and relayout.
UIDL document teardown ends that identity. A new UCTX never inherits it even if
the new document reuses every `id=` string.

Bounds come from resolved UIDL layout relative to the owning UCTX region. The
projector converts checked geometry to the retained profile's full `UNORM32`
precision; it must not truncate through an incidental narrower normalized
format. Region movement changes the private owner region. Layout changes may
replace derived object geometry while preserving element and wire identities.
Applications do not maintain parallel coordinates.

### 5.3 Static and dynamic state

The projector classifies semantic snapshots into:

* static definition state: kind, relationships, formatting, style, labels,
  units, axes, immutable vector geometry, and declared capacities;
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

## 6. UIDL-TUI rich-terminal adapter lifecycle

This is the private host/driver ABI above the generic engine, not an engine
interface and not an application service. Only the UIDL host calls it:

```forth
RTERM-HOST-BINDING-SIZE  ( -- bytes )
RTERM-HOST-BINDING-INIT  ( host-binding -- )

RTERM-UCTX-ATTACH    ( host-binding backend -- binding-token status )
RTERM-UCTX-PROJECT   ( binding-token backend -- status )
RTERM-UCTX-RELAYOUT  ( visible region binding-token backend -- status )
RTERM-UCTX-QUIESCE   ( binding-token backend -- status )
RTERM-UCTX-DETACH    ( binding-token backend -- status )
```

The first lifecycle foundation is the optional
`akashic/tui/rich-terminal/uidl-driver.f` module. It constructs the private,
caller-bounded binding registry separately from the retained engine:

```forth
RTERM-HOST-BINDING-CAPTURE  ( host slot host-binding -- status )

RTERM-UIDL-BINDING-BYTES    ( -- bytes )
RTERM-UIDL-BACKEND-BYTES    ( -- bytes )
RTERM-UIDL-INIT             ( host records-a records-u backend -- status )
RTERM-UIDL-FINI             ( backend -- status )
RTERM-UIDL-VALID?           ( backend -- flag )
RTERM-UIDL-STORAGE-DISJOINT? ( a u backend -- flag )
RTERM-UIDL-STATUS@          ( backend -- status )
RTERM-UIDL-ACTIVE@          ( backend -- count status )
RTERM-UIDL-INSTALL          ( backend -- status )
RTERM-AHOST-UIDL-READY      ( host slot host-binding -- ior )
```

This foundation has no `RTAPT-*`, screen-publisher, MegaPad, Desk, or applet
dependency. Its immutable UIDL callback installation carries the exact backend
as explicit composition context; the context is not stored in a UCTX. Until a
separate backend-neutral semantic projector facade exists, attach and geometry
tracking are local-only, project returns `RTERM-S-UNAVAILABLE`, quiesce proves
the empty source set, and detach creates no wire owner or tombstone. In
particular, the foundation must not open a default or root-region-only owner:
owner quotas can be admitted only from one complete supported semantic tree.
Construction and attach admit the exact declared application descriptor,
component descriptor, and live component-state spans as well as the fixed host
objects, and reject every alias with driver storage. Every public stateful
driver operation catches internal throws and scrubs its transient descriptor,
slot, CINST, UCTX, region, and application pointers before returning.

`RTERM-AHOST-UIDL-READY` is the reusable neutral host adapter. Its context is
one caller-owned `RTERM-HOST-BINDING-SIZE` scratch span initialized once by
composition before callback installation. Capture performs the complete alias
preflight without first mutating that span. After a successful capture, the
adapter calls `UTUI-RICH-TERM-ATTACH` under a cleanup boundary so only the
active UCTX receives the opaque token, then unconditionally reinitializes the
now-proven-disjoint descriptor even if attach throws. A capture refusal leaves
the already pointer-free scratch unchanged.

`RTERM-UIDL-FINI` is the matching host-unbind boundary. It succeeds only when
the backend has no live bindings, clears the binding records and backend, and
therefore removes the borrowed AHOST pointer before that host can be freed. A
live-binding refusal leaves every byte intact for quarantine. The immutable
UIDL callback table may retain the same stable backend address; a later exact
host may reinitialize and reinstall that address idempotently.

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
derives exact quotas, and admits the owner atomically. Required counts, byte
capacities, resource overlap, series history, and transaction operation/byte
bounds must all fit local storage and negotiated terminal maxima before
`OWNER_OPEN` is emitted.

The owner reservation is frozen for that UCTX materialization. Dynamic values
may vary within declared semantic capacities but cannot silently enlarge them.
If the tree later changes structurally beyond admission, retained projection
reports capacity and keeps the prior coherent retained terminal state; CELL rendering
continues from the authoritative UIDL tree.

Unavailable retained discovery or an unsupported optional semantic family
does not prevent attach or application initialization. The binding remains a
CELL-fallback binding with no wire owner until a complete supported projection
can be admitted.

### 6.2 Project

Project runs with the token's exact UCTX active after normal UIDL binding updates and
layout. It walks dirty semantic elements through the retained projector
registry, captures complete snapshots into admitted backend storage, validates
the resulting graph, and stages desired retained changes. It never asks an
applet to enumerate a second scene.

Local projection admission is atomic. A failure leaves the previous copied
projection recipe and retained terminal state authoritative while UIDL and CELL state
remain untouched. A successful projection records the newest desired state for
bounded later publication. No protocol byte is emitted from an element or
widget callback.

One ordinary projected UIDL update must fit one admitted APT output
transaction. Initial construction, reset replay, and relayout reconstruction
may use the wire profile's hidden bounded multi-transaction build followed by
one reveal. The backend never exposes a partially rebuilt UCTX merely to evade
an admitted bound.

### 6.3 Relayout and visibility

Relayout runs after ordinary UIDL layout has resolved the UCTX. `region` is the
current root Akashic region and `visible` is the host's actual minimize/restore
state. Moving or resizing a tile updates the owner region and derived layout
without changing semantic element or resource identities.

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

Final detach is host-owned and runs after application shutdown, but before
`UTUI-DETACH`, `UCTX-FREE`, `CINST-FREE`, region free, or host-slot reuse. It
uses only the exact token and quiesced source-free binding; it never calls
application code or a semantic source.

Detach is allocation-free and atomically:

1. makes the binding stale for project and relayout;
2. verifies quiesce removed every source XT/context, then removes all borrowed
   UCTX, widget, CINST, host-slot, and region pointers from pending state;
3. aborts local staging and obsolete in-flight replacement work;
4. records the exact owner-wide terminal drop obligation in the binding record;
   and
5. releases projection storage the tombstone no longer needs.

Once that local transition succeeds, detach returns `RTERM-S-OK` even if egress
is blocked. The host may then detach/free the UCTX, CINST, region, and slot. The
backend retains only the private wire owner/generation and bounded drop
progress; it contains no pointer back into those freed objects.

Detach is idempotent. A binding record becomes reusable only after exact owner
drop is acknowledged or a confirmed epoch/session destruction proves that the
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

Desk exposes only the constructor pass-through
`DESK-UIDL-READY! ( xt context -- )`. During `DESK-INIT-CB`, immediately after
initializing its generic host and before launching any child, Desk copies that
exact callback pair into `AHOST-UIDL-READY!`. It does not inspect the context,
name an output backend, or allocate composition storage.

The host invokes the callback exactly once for a launch after ordinary UIDL
load and initial region assignment have succeeded, while the exact UCTX is
active, and before crossing the application-initialization boundary. A zero
callback is the baseline configuration. The callback may capture the exact
binding and attach an optional driver, but the host neither allocates backend
state nor learns the callback context's type. A callback refusal enters normal
transactional launch rollback.

Each linked slot records an independent retirement phase: `LIVE`, `QUIESCING`,
`QUIESCED`, `SHUTDOWN-CLAIMED`, or `DETACHED`. `AHS.STATE` remains the ordinary
running/minimized/focused state so authority validation sees the original live
tuple through final detach. On the first close attempt the host stores
`QUIESCING` before quiescing the retained UIDL attachment and, for a child
which crossed application init, invoking its optional `APP.QUIESCE-XT`. Only
both barriers plus the final UCTX save succeeding store `QUIESCED`. A refusal
preserves the
linked slot, ID, CINST, UCTX, region, UIDL buffer, driver attachment, and exact
activation tuple. The slot becomes noncallable: focus, input, tick, paint, and
application close callbacks must not reach it, while a later host
quiesce/drain attempt may retry the barrier.

After quiesce succeeds, the host stores `SHUTDOWN-CLAIMED` before activation or
`APP.SHUTDOWN`, so a thrown shutdown callback is never repeated. It then runs
final UIDL/driver detach with the exact UCTX restored. `AHS.HAS-UIDL` remains
true until that detach succeeds. A detach refusal preserves every child
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

When one logical UI frame changes both CELL and retained state, the rich
publisher commits the applicable CELL spans/cursor and retained operations in
one atomic `PRESENT` transaction. A failed combined commit cannot advance the
screen front buffer or the retained materialization independently. A frame
with no retained changes remains an ordinary valid CELL transaction; a
retained-only update may use `CELL_NONE` under the wire recovery rules.

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
`tui/desk-apt1.f` and supplies the engine only to the generic UIDL-TUI driver;
that is a product composition, not engine ownership by Desk. A standalone
shell or another non-UIDL Akashic consumer may compose the same engine without
loading Desk or UIDL-TUI. The baseline `desktop` profile does not load the
APT-1 engine or construct rich-terminal state.

The deployment boundary is strict. MegaPad owns the optional boot-loaded
`rich-terminal.f`; a rich product profile loads it before any Akashic
rich module. Akashic never source-`REQUIRE`s or copies that module. Its rich
modules consume only the already-loaded public PT ABI. Baseline profiles load
neither the optional PT module nor the Akashic rich modules, so their source
closure, startup, storage, and output behavior remain unaffected.

The composition settles retained discovery before launching hosted UCTXs. A
negative or partial result selects stable CELL-only projection for unsupported
semantics; applet initialization does not poll terminal features and sees no
different service table.

The host lifecycle order is:

1. allocate/register the activation, UCTX, and region;
2. load UIDL and perform initial layout;
3. build the immutable exact host-binding descriptor, attach internally, and
   store the returned token only in host-private slot state;
4. run ordinary application initialization and state/widget binding;
5. paint CELL and project retained semantics from the same active UCTX;
6. publish through the shared frame transaction;
7. on geometry change, run UIDL relayout then retained relayout;
8. before `APP.SHUTDOWN`, quiesce retained sources, then the application's
   declared `APP.QUIESCE-XT`, and record retryable retirement, refusing
   shutdown if either callback-detachment barrier is not proven;
9. after all hosted UCTXs are source-free, close the optional terminal owner
   and prove ANSI safety;
10. run application shutdown, then final retained detach while the exact host
    tuple is still live; and
11. detach/free UIDL, UCTX, activation, region, and host slot.

The top-level shell performs step 8 as a two-part barrier: it first quiesces
its own retained UIDL attachment, if present, then invokes the neutral
`APP.QUIESCE-XT ( instance -- ior )` descriptor callback. Desk implements that
callback only by calling `AHOST-QUIESCE-ALL`, which applies the same ordering
to every child. A refusal or throw is a hard pre-terminal close gate. The shell
preserves its descriptor, instance, UIDL, active UCTX,
root region, terminal owner, posted work, and screen state in quarantine and
runs no later destructor. The same quarantine rule applies if terminal close,
application shutdown, or final UIDL detach fails. A quarantined top-level
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

The backend privately tracks session identity and the wire
`presentation_epoch`. A successful soft reset invalidates terminal
materialization and private wire
identities, not live UCTX attachments.

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

The first complete vertical uses the same UIDL document and ordinary semantic
widget APIs in baseline ANSI and rich Desktop compositions. Without applet APT
imports or direct scene calls, it must demonstrate:

* complete CELL fallback;
* automatic UCTX attach and exact owner admission;
* retained semantic definitions derived from UIDL;
* dynamic bound-state updates without retransmitting unchanged definitions;
* stable element/object identities across relayout and minimize/restore;
* atomic CELL plus retained publication where both change;
* reset reconstruction from live UCTX semantics; and
* allocation-free detach and exact owner retirement before UCTX free.

Qualification may use focused semantic fixtures while the backend is being
built, but closure requires an unchanged production UIDL path rather than a
handwritten applet projection. No particular applet is built into this
architecture or protocol contract.

Image/resource lifecycle remains part of Phase 3 closure when the composition
advertises that semantic family. A stock image can qualify codec mechanics but
cannot replace the generic UIDL media lifecycle, fallback, reset, and detach
journey.

### 11.1 Pre-vertical qualification gate

Before vertical closure, each bounded implementation slice is qualified only
with seconds-scale structural tests, byte-oracle tests, and focused unit tests
appropriate to that slice. Each coherent slice receives its own progress
commit after those lightweight checks pass.

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
5. configuration overflow, wrap, misalignment, overlap, and negotiated-budget
   mismatch fail before changing supplied storage;
6. a complete semantic-tree admission derives exact quotas and rejects
   insufficient object, resource, series, operation, or byte capacity before
   `OWNER_OPEN`;
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
    state, and restore publishes one coherent current projection;
12. relayout changes region/layout geometry while semantic and wire item
    identities remain stable;
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

Full Desktop, reset, renderer, and sustained-cadence journeys are later
sequential qualification. They complement these bounded headless contracts and
may not justify larger hidden capacities, weakened teardown, or an application-
specific rich-terminal path.
