# Akashic UIDL retained-presentation backend contract

Status: normative for the Phase 3 Akashic retained-presentation integration.

This document defines the Akashic architecture, storage, ownership, projection,
and lifecycle contract for retained presentation. It does not define APT-1 byte
encoding. The mirrored `APT-1-WIRE.md`, `APT-1-RETAINED-1.md`, and ownership
ledgers define terminal protocol identity, transactions, reset, and retirement.

The transactional cell plane remains independently specified by
`AKASHIC-CELL-BACKEND.md`. Retained presentation is an optional projection of
the same UIDL/UCTX interface already rendered into cells. It does not create a
second application UI model, replace the cell screen, or weaken ANSI fallback.

## 1. Non-negotiable architecture

UIDL is the sole application-facing UI description. A hosted component owns its
ordinary domain state and uses the existing UIDL element tree, bindings,
subscriptions, semantic widgets, dirtying, layout, focus, and event mechanisms.
The same `UCTX` owns that UI for the complete activation lifetime.

One internal retained backend exists for one live enhanced terminal session.
The explicit rich composition constructs it and gives it to the UIDL host. Desk
and the applet host attach, project, relayout, and detach UCTXs through generic
host operations. A Desk-owned UIDL context, when present, follows the same path
as a child UCTX; Desk UI code does not author a retained scene manually.

The following are forbidden application interfaces:

* retained-backend or APT discovery through `IEND.SERVICE-XT`;
* applet acquisition of a presentation broker, scope, owner, or lease;
* applet calls that begin, define, update, commit, abort, step, replay, or retire
  a terminal scene;
* applet-visible session, epoch, owner, region, object, resource, series,
  revision, transaction, opcode, frame, or terminal-capacity identities; and
* a handwritten projection controller maintained beside an applet's UIDL.

There is therefore no presentation service identifier and no presentation
endpoint per Desk or per applet. "Global" in this contract means only that one
internal backend serializes one terminal session. It is held by the explicit
composition and UIDL host, not published as application authority.

The retained model is a derived terminal materialization. The UIDL tree,
semantic widget state, and bound application state remain authoritative. The
backend may keep a bounded copied projection recipe, dirty state, mappings, and
wire tombstones so that transport is incremental and reset is replayable. That
cache is not a second application-owned scene and has no independent mutation
API.

## 2. Authority and identity

The internal backend is the sole Akashic component allowed to emit retained
wire frames. It owns discovery state, the shared presentation transaction and
revision domain, resource-upload serialization, owner mappings, replay, and
retirement. The APT shell remains the sole owner of the PT session and terminal
input; the retained backend uses the shell's internal adapter and never creates
another UART reader, writer, or service loop.

Each attached UCTX is represented privately by one bounded projection binding.
The binding contains:

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
state. Conversely, a terminal model is never authoritative input to an applet.

## 3. Internal status values

The host/backend boundary uses these stable ordinary status values:

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `PRES-S-OK` | The host operation or projection was accepted. |
| 1 | `PRES-S-WOULD-BLOCK` | No downstream progress is currently possible; retry from the host loop. |
| 2 | `PRES-S-UNAVAILABLE` | No usable negotiated retained backend or required semantic family exists. |
| 3 | `PRES-S-CAPACITY` | Caller-owned or negotiated capacity cannot admit the projection. |
| 4 | `PRES-S-STALE` | The UCTX, activation binding, source revision, or terminal materialization is no longer current. |
| 5 | `PRES-S-INVALID` | An argument, semantic snapshot, storage configuration, state transition, or callback result is invalid. |
| 6 | `PRES-S-SESSION-LOST` | The enhanced session crossed a structural loss boundary. |
| 7 | `PRES-S-SOURCE` | A semantic resource or series source failed. |

These statuses do not throw through an applet callback and are not returned to
application presentation code, because no such code exists. The UIDL host
records the first non-transient backend error for inspection while leaving
application state intact. One failed projection cannot authorize mutation of
another binding, and a post-`OPEN` structural loss never makes raw ANSI output
safe.

`PRES-S-WOULD-BLOCK` is transport progress, not local projection-capacity
failure. Already accepted desired state remains accepted while egress is
blocked. `PRES-S-CAPACITY` and `PRES-S-INVALID` are fail-before-mutation at
each local admission boundary.

## 4. Backend construction and caller-owned storage

The optional composition constructs the one internal backend with:

```forth
PRES-BACKEND-INIT     ( config backend -- status )
PRES-BACKEND-FINI     ( backend -- status )
PRES-BACKEND-STATUS@  ( backend -- status )
```

`config` names the internal APT adapter, the exact owning `AHOST`, and
caller-owned spans and capacities for:

* live UCTX projection bindings and owner tombstones;
* projected region, object, resource, and series records;
* stable element/subobject-to-wire mappings;
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
* pairwise disjointness of the backend, configuration, every owned span, the
  borrowed PT session and its buffers, and the APT adapter; and
* compatibility with negotiated object, resource, frame, transaction, history,
  and chunk budgets.

Failure returns `PRES-S-CAPACITY` or `PRES-S-INVALID` without partially
initializing, clearing, or retaining a supplied span. After successful init,
attach, project, relayout, detach, service, reset replay, and finalization use
only admitted storage and perform no hidden heap or XMEM allocation.

The backend stores the latest authoritative projection recipe, not raw frames
or an unbounded revision history. Scalar and visibility state coalesces in the
corresponding records. Resource and sample bytes are copied into bounded
staging only for the synchronous interval required by their source and wire
contracts.

`PRES-BACKEND-FINI` succeeds only when no live UCTX binding remains and every
retirement obligation is acknowledged, or the underlying session is proven
destroyed. Refusal leaves the complete backend and its storage valid for retry.
It never clears an uncertain owner tombstone.

## 5. UIDL semantic projection contract

### 5.1 One semantic tree, multiple output planes

UIDL element semantics are backend-neutral. The existing UIDL-TUI renderer
continues to paint the CELL/ANSI representation. The retained integration adds
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

There is no generic `<presentation>` escape hatch, raw scene element, owner
attribute, terminal ID attribute, or transaction element. A generic canvas
does not become an arbitrary retained command stream. A richer projector is
valid only when a semantic element defines enough backend-neutral meaning for
both CELL and retained renderers.

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

## 6. Generic UCTX lifecycle

Only the UIDL host calls the retained lifecycle surface:

```forth
PRES-HOST-BINDING-SIZE  ( -- bytes )
PRES-HOST-BINDING-INIT  ( host-binding -- )

PRES-UCTX-ATTACH    ( host-binding backend -- binding-token status )
PRES-UCTX-PROJECT   ( binding-token backend -- status )
PRES-UCTX-RELAYOUT  ( visible region binding-token backend -- status )
PRES-UCTX-QUIESCE   ( binding-token backend -- status )
PRES-UCTX-DETACH    ( binding-token backend -- status )
```

`host-binding` is an immutable, call-borrowed descriptor containing ABI
version, exact size, zero-reserved fields, the exact `AHOST` and `AHS` slot
addresses, captured nonzero `AHS.ID`, exact CINST address and captured nonzero
`CINST.ID`/`CINST.GENERATION`, exact UCTX address, and exact current region.
The backend never retains the descriptor address. It validates and copies the
complete authority tuple, then returns one opaque nonzero internal token.

The token names a backend-owned record and an exact nonreusable binding
generation; it is not a naked binding-record address. It is valid only with the
backend that issued it and is stored only in host-private slot state. Every
later call validates the token/backend/generation and revalidates that the host
still contains the exact live slot, `AHS.ID`, CINST pointer and generation, and
UCTX before dereferencing UCTX or application-owned state. A foreign backend,
unlinked or reused slot, changed activation generation, changed UCTX, or stale
token returns `PRES-S-STALE` without mutation.

A composition-owned root UCTX, if present, must have a real composition-owned
host slot and activation satisfying the same descriptor and validation; zero
or invented host authority is not a special case. There is no
application-callable variant and no returned application scope.

### 6.1 Attach

Attach occurs after the UCTX document is loaded and its host slot and region
exist. The backend verifies that its configured host is the descriptor host;
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
reports capacity and keeps the prior coherent terminal model; CELL rendering
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
projection recipe and terminal model authoritative while UIDL and CELL state
remain untouched. A successful projection records the newest desired state for
bounded later publication. No protocol byte is emitted from an element or
widget callback.

One ordinary projected UIDL update must fit one admitted presentation
transaction. Initial construction, reset replay, and relayout reconstruction
may use the wire profile's hidden bounded multi-transaction build followed by
one reveal. The backend never exposes a partially rebuilt UCTX merely to evade
an admitted bound.

### 6.3 Relayout and visibility

Relayout runs after ordinary UIDL layout has resolved the UCTX. `region` is the
current root Akashic region and `visible` is the host's actual minimize/restore
state. Moving or resizing a tile updates the owner region and derived layout
without changing semantic element or resource identities.

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

Quiesce may return `PRES-S-OK` while terminal egress or an owner-drop result is
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

Once that local transition succeeds, detach returns `PRES-S-OK` even if egress
is blocked. The host may then detach/free the UCTX, CINST, region, and slot. The
backend retains only the private wire owner/generation and bounded drop
progress; it contains no pointer back into those freed objects.

Detach is idempotent. A binding record becomes reusable only after exact owner
drop is acknowledged or a confirmed epoch/session destruction proves that the
terminal model cannot survive. A UCTX that never materialized a retained owner
creates no wire tombstone.

## 7. Frame projection and atomic publication

UIDL-TUI CELL painting remains the universal path. In the rich composition,
painting a dirty attached UCTX also stages its retained projection. The global
screen flush and internal retained backend then serialize through the one APT
presentation publisher and the one shared transaction-ID/revision clock.

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
of the optional plane leaves a usable UI rather than a blank reserved area.

## 8. Bounded backend service and cadence

Only the terminal/Desk owner loop advances publication:

```forth
PRES-BACKEND-STEP  ( work-budget backend -- status more-work? )
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

Physical presentation cadence is a renderer policy over committed global
revisions, not an application API. UIDL/widget updates retain their own domain
timestamps; cadence never invents sample timing. Input is delivered only
against a physically presented revision as required by RETAINED-1.

## 9. Composition and host order

`tui/desk-apt1.f` is the sole production rich composition root. It constructs
the PT session, CELL adapter, and caller-owned retained backend, then injects
the backend only into the generic UIDL host integration. The baseline
`desktop` profile does not load the APT retained implementation or construct
this backend.

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
8. before `APP.SHUTDOWN`, quiesce retained sources and record retryable
   retirement, refusing shutdown if callback detachment is not proven;
9. run application shutdown, then final retained detach while the exact host
   tuple is still live; and
10. detach/free UIDL, UCTX, activation, region, and host slot.

The host must save a mutated active UCTX before switching away. Retained
projection cannot depend on unsaved global UIDL pools belonging to some other
active child. It either runs while the exact UCTX is active or reads a validated
saved snapshot through UCTX-owned accessors.

## 10. Reset, replay, and loss

The backend privately tracks session identity and presentation epoch. A
successful soft reset invalidates terminal materialization and private wire
identities, not live UCTX attachments.

On an accepted reset boundary, the backend:

1. abandons old-epoch transmission and chunk progress;
2. marks every live region, resource, definition, layout property, and dynamic
   property as not materialized;
3. clears only tombstones whose old terminal model is now proven absent;
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
from the authoritative live UCTX. No terminal model or raw frame archive is
authoritative. Hidden UCTXs defer replay until restore; detached UCTXs are
never replayed.

CELL snapshot reconstruction and retained reconstruction are separate dirty
obligations sharing one session epoch. Clearing the CELL snapshot latch cannot
clear retained replay. A structural loss after binary `OPEN` freezes ordinary
publication and follows APT quarantine; it never selects raw ANSI on the same
uncertain attachment.

## 11. Phase boundary and completion

UIDL/UCTX integration is Phase 3, not deferred work. Phase 3 does not ship an
application-facing retained broker as a bridge and does not require any applet
to maintain terminal-specific presentation state.

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
16. no production applet imports APT/presentation modules, discovers a retained
    service, stores a scope, or issues a scene operation.

Full Desktop, reset, renderer, and sustained-cadence journeys are later
sequential qualification. They complement these bounded headless contracts and
may not justify larger hidden capacities, weakened teardown, or an application-
specific presentation path.
