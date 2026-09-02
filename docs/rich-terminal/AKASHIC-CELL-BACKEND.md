# Akashic transactional cell-backend contract

Status: normative for the APT-1 CELL-1 Akashic implementation.

This document defines the boundary between Akashic's double-buffered screen
and an output backend. It does not define APT-1 byte encoding; that is
specified by the mirrored `APT-1-WIRE.md`.

The additive retained rich-terminal output path is specified separately by
`AKASHIC-RICH-TERMINAL.md`. It projects the same UIDL state, never replaces
the cell screen or ANSI fallback, and shares one atomic publisher with CELL
once retained discovery succeeds.

## 1. Goal

Application and widget painting continues to target the existing Akashic back
buffer. `SCR-FLUSH` projects the difference through a bound backend. ANSI and
APT-1 are backend implementations of the same transactional interface.

ANSI is the constructed default and is a complete supported mode. The generic
backend seam does not require APT-1, and loading Akashic does not imply that an
enhanced terminal exists.

Serialization does not create a second UI model. The screen front buffer
records only state accepted by a backend commit.

## 2. Status values

The interface uses these stable values:

| Value | Name | Meaning |
| ---: | --- | --- |
| 0 | `SCB-S-OK` | The operation was accepted. |
| 1 | `SCB-S-WOULD-BLOCK` | No state changed; retry after capacity or transient owner contention changes. |
| 2 | `SCB-S-SESSION-LOST` | The binding is stale or the enhanced session ended. |
| 3 | `SCB-S-INVALID` | Caller arguments or backend state violate the contract. |

Status returns are ordinary values. Capacity and session loss must not throw
through application paint. Programmer-invalid descriptor construction may
abort at bind time, before the backend becomes current.

Flush modes are `SCB-M-DELTA = 0`, `SCB-M-SNAPSHOT = 1`, and
`SCB-M-NONE = 2`. `NONE` brackets retained-only work with `begin` and `commit`
but carries no CELL spans and omits the cursor callback.

## 3. Backend descriptor

A backend descriptor contains a context pointer and five execution tokens.
Every token receives that context as its final argument:

```
begin   ( mode cols rows span-count cell-count context -- status )
span    ( cells count row col context -- status )
cursor  ( row col visible context -- status )
commit  ( context -- status )
abort   ( context -- )
```

`cells` addresses `count` consecutive native 64-bit cells. The backend must
read them before returning; it cannot retain the caller's pointer. The APT-1
backend encodes named fields and must never copy the native cell word as its
wire representation.

Only one backend transaction may be open. Calls are not reentrant.

## 4. Flush algorithm

`SCR-FLUSH` uses two distinct one-byte-per-row maps. `TOUCHED` is a
screen-owned conservative union of rows that may have changed since the last
accepted commit. Ordinary `SCR-SET` marks its row before mutation; whole-screen
operations mark every row; and `SCR-WITH-BACK-MUTATION` accepts a conservative
half-open row range. A malformed range or a throw while that mutable plane is
borrowed marks every row. Mutations also invalidate any cached admission plan.

`DAMAGE` is the exact immutable plan for one flush attempt. If no valid retry
plan exists, admission proceeds as follows:

1. A force request selects `SNAPSHOT` and marks every row as damage. Otherwise
   CELL or cursor dirtiness selects `DELTA`; only touched rows receive a
   whole-row comparison, and only unequal rows enter `DAMAGE`. A retained-only
   request with no CELL or cursor dirtiness selects `NONE`.
2. Snapshot counts one complete span per row. Delta counts maximal contiguous
   changed spans only within admitted damage rows. None has zero spans and
   zero cells. The selected mode, exact totals, and damage map are then cached
   as one plan.
3. `begin` receives that plan. Once admitted, emission visits only `DAMAGE`,
   calls `span` for its exact snapshot or delta spans, calls `cursor` unless
   the mode is `NONE`, and finally calls `commit`.
4. A successful commit copies complete damage rows from back to front, clears
   `TOUCHED`, dirty, force, and retained-only request state, advances the front
   draw generation, and invalidates the plan. A refusal or later transaction
   failure advances none of them and preserves the exact plan for retry.

Counts and address arithmetic use checked screen dimensions. There is no fixed
span array or arbitrary changed-cell cap, and a delta attempt does not compare
untouched rows.

`SCR-FORCE` sets an explicit force-snapshot flag. Snapshot enumeration never
depends on poisoning front cells with a sentinel, because a native packed cell
could otherwise equal the sentinel. Binding the APT adapter after open, an
accepted resize, or a soft reset calls `SCR-FORCE` before the next flush.

The backend uses `span-count` and `cell-count` to reserve an upper bound for
the complete transaction before accepting `begin`. Therefore, after a
successful `begin`, valid matching `span` calls cannot return
`SCB-S-WOULD-BLOCK`.

For a direct APT-1 CELL delta or snapshot this is exact:
`176 + 52 * span-count + 8 * cell-count` wire bytes from begin through commit.
Negotiation guarantees that one complete maximum-width row span fits a frame
payload, so the adapter never splits a screen span or changes the declared
count. Unified CELL/rich publication reserves its complete mixed transaction at
the publisher boundary instead.

## 5. Acceptance and failure

If `begin` returns `WOULD-BLOCK`, `SESSION-LOST`, or `INVALID`, no other token
is called. Front, `TOUCHED`, `DAMAGE`, and the cached totals remain unchanged;
the dirty or retained-only request that caused the attempt remains pending.

If `span` or `cursor` returns anything other than `OK`, `SCR-FLUSH` calls
`abort` exactly once. Front and all pending-plan state remain unchanged.

If `commit` returns `OK`, the backend has accepted the whole atomic transaction
and front advances. A physical backend may still have a later completion gate,
as APT-1 does. If commit returns another status, the backend has discarded all
staged mutations and front plus pending-plan state remain unchanged. `abort` is
not called after `commit`, because commit terminates the transaction for every
status.

Local front-buffer acceptance is output bookkeeping only. It does not advance
the selected sink's displayed revision and cannot authorize revision-bound
input. A physical selected sink in an APT-1 session advances that authority
only through the exact local completion acknowledgement defined by the
retained/presentation lifecycle; an e-paper implementation must wait for
controller completion and required panel settling before invoking it.

A repeated flush after refusal reuses the immutable cached mode, totals, and
`DAMAGE` map. Any intervening screen, plane, cursor, request, backend, or
geometry mutation invalidates that plan, so the next flush derives a new one
from the latest back buffer. Application paint callbacks need not run again.
The shell therefore tracks application-paint dirty state separately from
pending screen output.

## 6. ANSI backend

The ANSI backend always admits a valid `begin` and commits synchronously. It
must preserve the current byte behavior:

* hide the physical cursor at begin;
* reset cursor/style tracking;
* emit changed cells in row-major order using width-one projection;
* restore the logical cursor when visible;
* emit final SGR reset; and
* call `TERM-FLUSH` at commit.

It does not buffer a whole screen transaction. Its `abort` restores a safe
terminal style/cursor state and flushes, though ordinary valid calls do not
exercise that path.

## 7. APT-1 backend

The reusable APT session/framing implementation lives in MegaPad's optional,
boot-loaded root-level `rich-terminal.f` userland module, not in KDOS
or Akashic. Akashic's APT backend is a small adapter over that already-loaded
public ABI. No Akashic source may `REQUIRE` the module or copy it into the
Akashic tree. The adapter is available only when the product profile loaded the
module explicitly and requested rich-terminal negotiation; baseline profiles
remain unaffected.

The enhanced backend is bound only after successful negotiation. `begin`
checks the current session epoch and reserves sufficient transport and remote
transaction budget for the declared counts. A refusal has no wire effect.
Binding and non-ANSI service require `PT-OWNS?` for the adapter's exact
borrowed session. An ANSI-state adapter may rebind the ANSI backend only when
`PT-STREAM-OWNED?` also proves that no other session owns the global stream.

Each `span` applies `CW-CELL-CP` and serializes the CELL-1 codepoint, foreground
index, background index, and named wire attributes. Wide and continuation
native flags are not transmitted in the width-one CELL-1 profile.

`commit` queues the complete final commit frame within the prior reservation.
The Akashic front buffer may advance after local transport acceptance; it does
not wait for rendering or a remote paint acknowledgement.

The module permits only one locally committed transaction awaiting
`TX_RESULT`. Until it succeeds, the next backend `begin` returns
`SCB-S-WOULD-BLOCK`. A failed result maps to `SCB-S-SESSION-LOST` before any
later application event; no optimistic pipeline or rollback is permitted.

### Rich-terminal publication

The descriptor and flush algorithm above remain the complete ANSI and CELL-only
contract. Before RETAINED-1 is enabled, the APT adapter uses the legacy CELL
transaction and initial snapshot forms exactly as described.

After RETAINED-1 discovery succeeds, the adapter must not independently emit a
legacy CELL transaction or replacement snapshot. Its `begin`, `span`, and
`cursor` calls instead stage the exact CELL enumeration in the one internal
rich-terminal output coordinator. The UIDL retained backend stages semantic
operations in that same coordinator. One `PRESENT_BEGIN`/`PRESENT_COMMIT` then
publishes a CELL-only, retained-only, or mixed change under the shared
transaction ID and revision. Accepted resize recovery uses `CELL_REPLACE` in
that envelope.

`PRESENT_BEGIN`, `PRESENT_COMMIT`, and `presentation_epoch` are frozen APT-1
wire-protocol spellings. They do not name a Presentation object, service,
application layer, or UIDL concept. Above the wire bridge the operations are
neutral staging, reveal, settlement, reconstruction, and retirement.

The APT screen adapter exposes this coordinator through one optional borrowed
publisher descriptor. The descriptor carries the exact PT session, callback
context, normalized CELL transaction callbacks, an ordinary scheduler step,
and a distinct close-settlement callback. The baseline adapter does not depend
on a concrete rich engine. At each `begin` it selects the publisher only when
retained discovery is currently available; otherwise it selects the legacy
CELL path. That decision is latched through span, cursor, commit, or abort, so
discovery and reset transitions cannot split one transaction across paths.

The APT-1 product composition installs `RTHP-STEP` and `RTHP-PREPARE` as one
neutral aggregate screen producer. The visible-UCTX adapter supplies a copied
directory and aggregate semantic snapshot; the producer combines menu controls
and canonical collection controls, `DATA_GRAPHICS` instruments, their exclusive
cell claims, and residual `GLYPH_RUN`s from the same completed draw. It also
honors the screen's final-writer provenance by returning an intersected
document atomically to residual ownership for a later foreground overlay. Desk
and applets remain ordinary UIDL/TUI producers and contain no APT-1,
retained-scene, or renderer branch.

The screen publisher observes exact geometry on every CELL offer. A bounded
producer step can schedule one persistent `SCB-M-NONE` request; the next begin
promotes it to an authoritative CELL offer before prepare. Prepare correlates
that exact geometry and draw generation, consumes the screen's immutable
`DAMAGE` plan when available, and stages one aggregate retained attempt. The
initial or uncertain candidate follows hidden replacement and reveal; a
compatible later draw uses an acknowledged-bank delta, while a retained-
identical draw uses the revision fence. Capacity, source, or preparation
refusal is aggregate backpressure: there is no per-binding wire readiness or
single-record fallback in the selected composition.

`PT-SERVICE` remains owned by the APT screen adapter. Ordinary service calls it
before the publisher scheduler, which may reconcile a completion or admit one
queued lifecycle request. Synchronized close uses a separate operation: it
calls `PT-CLOSE` first to latch MegaPad's finite settlement/publication
deadline and writer barrier, then services PT's pending path and asks the
publisher to settle only an already-admitted result. Later service calls may
reconcile that result, complete a crossed reset, or publish CLOSE, but cannot
restart the bound. Settlement must not submit queued lifecycle work.
Captured or sealed local candidates and an open uncommitted CELL transaction
carry no emitted-result authority and do not block close; the synchronized
session retirement discards them. Once PT is `CLOSING`, only `PT-SERVICE` may
run until ANSI ownership is restored. At that proven boundary, one final
settlement call quarantines any remaining engine-local candidate or lifecycle
state before the adapter restores ANSI.
Every ANSI observation follows the same retirement path, including a
peer-initiated close reached through ordinary service: settlement is invoked
once as a best-effort local quarantine, the latched publisher route is cleared,
and only then is the ANSI screen backend restored. PT has already released wire
ownership at this point, so that callback cannot emit protocol work.

The publisher carries the first fatal neutral engine, producer, or preparation
result across ordinary scheduler calls. This is a volatile status latch, not
application persistence or a second state store: it owns no UIDL, widget, or
document data. Only whole-publisher reconstruction or final retirement clears
it, preventing a later ordinary step from masking a failed output lifecycle.
Close settlement
remains callable while the latch is set so already-admitted protocol work can
reach a finite terminal state; it cannot use settlement to admit new work.

The screen front buffer and retained terminal state advance together only
after the complete unified commit has been accepted locally. Backpressure or a
semantic failure leaves both prior states authoritative, leaves screen dirty,
and discards all staging. The one post-commit `TX_RESULT` gate blocks both CELL
and retained publication. Clearing the screen force-snapshot latch cannot clear
retained replay, and clearing retained dirtiness cannot advance the screen
front buffer.

Negotiation refusal, a pre-`OPEN` timeout, or an ANSI-only physical terminal
keeps or restores the ANSI backend and is not an application error. Once
`OPEN` has crossed the binary switch boundary, session loss retains the APT
backend and input owner, suppresses application callbacks and raw terminal
output, and requires either an acknowledged framed close or an external hard
attachment reset and drain before ANSI may be rebound. A competing live APT
session is a transient `WOULD-BLOCK`, not proof that this idle adapter lost a
session. Because app shutdown and component state finalizers are arbitrary
callbacks, unsafe teardown does not invoke them: it retains the exact live
top-level component instance until the same whole-environment reset/reload
boundary. Raw-freeing that state without its finalizer is not permitted.

### Production opt-in composition

The `desktop-apt1` profile is one production composition boundary. MegaPad
boot-loads its canonical optional root `rich-terminal.f` as a separate
system module before Akashic's `desk-apt1.f` owner and linked Desktop closure
are loaded. Akashic consumes only the public PT ABI; it neither source-loads
nor vendors the module. The baseline `desktop` profile does neither and remains
ANSI-only.

The profile owns one immutable host policy with a declared 400 by 200 maximum
geometry, geometry-derived payload/transaction/credit/publication bytes, and
explicit queue-event, input-byte, history, and service bounds. Both the smoke
runner and shared-session launcher consume that same policy; selecting the
profile may not silently fall back to an ANSI-only host configuration. The
guest's independent receive and transmit streaming buffers admit the control
reserve without buffering a whole snapshot. The receive capacity is 8192
bytes. The transmit minimum is derived from one APT frame header plus the
largest of a complete maximum-width CELL row, one complete caller-bounded
native text collection, and one complete caller-bounded `DATA_GRAPHICS`
instrument payload; at the checked-in bounds it is 917648 bytes. An explicit
product override below that derived minimum is rejected before any storage
allocation.

The retained composition provides storage for one screen-owner record and at
most one live aggregate screen wire owner, with one base screen region plus
caller-derived instrument regions. Its operation, copy, visible-document,
semantic-snapshot, target-bank, instrument, and residual-glyph capacities are
checked derivatives of the maximum screen cells and the ordinary Desk
catalog/UCTX element, string, collection, and `DATA_GRAPHICS` bounds in
`desk-apt1.f`. They are caller-bounded volatile output storage, not application
state or independent terminal reservations. Exact hybrid preflight must fit
both those derived spans and the negotiated terminal limits.

The checked-in Desktop host policy advertises exactly
`RET_CORE | RET_INSTRUMENT | RET_CONTROLS | RET_CONTROL_COLLECTIONS`, with one
owner, one base region, and caller-derived instrument-region capacity;
vector, RGBA-image/resource, series, and cadence families remain unadvertised
with zero capacities. The endpoint implements the bit-9 text/grid/tab control
family and the bit-3 `READOUT`/`METER`/`STATUS` instrument family. The current Akashic
source emits canonical menu controls, `TEXT_AREA`, `TEXT_GRID`, `TABSET`/`TAB`,
canonical `DATA_GRAPHICS` instruments, and residual glyph runs as its selected
production representation. Unsupported or refused semantics remain complete
CELL output rather than being falsely advertised.

The historical local pygame acceptance journey at Akashic `d24540e` and
MegaPad `c7045d6` recorded a complete Desk frame, Pad File-menu open/close and
edit, Daybook task addition and date navigation, and Daybook's ordinary exact
shared-resource handoff into Pad. It used `pygame.display.flip` as the local
host presentation boundary; that is useful compositor evidence, not proof of
physical panel scanout. The run qualifies those exact committed heads,
including the optimization tranche through `e754ac1` and the subsequent
cold-source compatibility corrections, only for their advertised
menu-plus-residual representation. It does not qualify the newer canonical
text-collection path.

A later collection-only X11 journey at Akashic `dd27f34` and MegaPad
`29bdfd6` historically qualified the canonical Pad `TEXT_AREA`, Daybook
`TEXT_GRID`, and Pad `TABSET`/`TAB` families. It remains evidence for that
bounded tranche, not the current full selected-feature vertical.

The current local X11 journey at Akashic `4b6a475` and MegaPad `29bdfd6`
qualified the selected menu, collection, and instrument representation through
the ordinary Desk launcher overlay and a normally launched Sound Lab. Its final
acknowledged frame contained exactly 8 `READOUT`, 2 `METER`, and 3 `STATUS`
objects and preserved the exercised Pad and Daybook semantic state across
legitimate complete-replacement wire-ID rebasing. Exact evidence is recorded in
`local_testing/evidence/rich-desktop-full-vertical-acceptance-20260902.md`.
This is local presentation-API evidence, not physical UART or panel proof. CELL
remains the complete fallback, but CELL-only Desk/editor/calendar/instrument
pixels do not qualify the rich path, and the sink must preserve every nonempty
plane of the selected global revision.

If Desk exits or throws after the binary switch but synchronized release is
not proven, the profile emits no diagnostic bytes. It remains in a silent
`IDLE` quarantine until the host performs the required attachment reset.

## 8. Cursor and geometry

Coordinates are zero-based. `visible` is zero or true. When visible, row and
column must be inside the current geometry; a hidden cursor's stored position
may be clamped by screen resize before projection.

The geometry passed to `begin` is the geometry of all spans in that
transaction. A resize cannot interleave with an open transaction.

## 9. Shell retry contract

Application dirty state means the back buffer needs repainting. Output pending
means front differs from back or a previous flush was refused.

The shell clears application dirty only after completing application paint.
It keeps output pending until `SCR-FLUSH` returns `SCB-S-OK`. A retry
calls `SCR-FLUSH` directly and does not rerun application paint unless the
application became dirty again.

## 10. Current conformance cases

The lightweight suite must prove:

1. ANSI output remains byte-for-byte compatible for a representative styled
   screen and cursor;
2. direct writes, whole-screen writes, and bounded mutable-plane borrows mark
   conservative `TOUCHED` rows, including all-row fallback on malformed or
   throwing borrows;
3. delta admission compares only touched rows, emits maximal spans only from
   unequal `DAMAGE` rows, and admits an equal touched row without a CELL span;
4. snapshot admission marks and emits every complete row, while `SCB-M-NONE`
   emits no span or cursor but still brackets one begin/commit;
5. a refused begin, span/cursor abort, or failed commit leaves front,
   `TOUCHED`, `DAMAGE`, exact totals, and pending requests unchanged;
6. an unmutated retry reuses the same immutable plan, while a plane, cursor,
   backend, request, geometry, or screen mutation forces a new plan;
7. a successful commit copies only admitted damage rows, clears touched and
   force/request state, and advances the correlated front generation;
8. the rich producer may borrow `DAMAGE` only for the exact current plan and
   screen, and a stale or invalid plan exposes canonical `0 0`; and
9. unified CELL/rich refusal advances neither the CELL front nor retained
   authority, while accepted commit keeps both on one transaction revision.
