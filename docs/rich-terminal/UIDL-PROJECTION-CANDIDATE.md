# Hybrid UIDL projection candidates

Status: normative implementation contract and historical qualification record.
The selected Desk APT-1 source/profile now advertises ordinary UIDL menu
controls, canonical text and tab collections, canonical `DATA_GRAPHICS`
instruments, and coalesced residual glyph spans under
`RET_CORE | RET_INSTRUMENT | RET_CONTROLS | RET_CONTROL_COLLECTIONS`. The full
selected vertical passed local physical Desk acceptance at Akashic `4b6a475`
with MegaPad `29bdfd6`.
`akashic/tui/uidl-menu-snapshot.f`
captures ordinary UIDL-TUI menu trees through one coherent resolved-tree visit
into caller-bounded, pointer-free work storage and ascending-key canonical
records. Local semantic visibility remains distinct from effective
paintability, so a closed menu retains truthful state without claiming rows it
did not paint.

`akashic/tui/rich-terminal/uidl-control-planner.f` converts those records into
one caller-bounded RTE CONTROL plan in parent-first publication order and a
separate canonical, attachment-token-scoped source-key correlation bank.
`uidl-claim-ledger.f` applies the all-or-none semantic admission result and emits
only clipped nonempty PAINTABLE claims. `residual-glyph-planner.f` unions those
claims and emits maximal equal-style GLYPH_RUN plan items plus copied UTF-8
references for the unclaimed ordinary screen cells.

The draw-keyed `uidl-hybrid-adapter.f` aggregates every visible attached UCTX
into complete double-buffered directory and record/text/native banks, reusing a
validated prior slice for each unchanged document. The adapter consults the
ordinary screen's final-writer provenance and atomically omits the semantic
slices of a document touched by a later foreground overlay, so residual
projection exclusively owns its covered pixels and hit area for that draw.
`hybrid-screen-producer.f` copies that aggregate and builds one neutral
control/instrument/glyph candidate. Initial, reset, resize, topology-changing,
or otherwise uncertain candidates use complete hidden replacement and reveal.
Compatible later candidates compare only with the exact acknowledged target
and use `RET_DELTA`; an equivalent candidate uses one idempotent replacement as
a nonempty revision fence.

As historical menu-plus-residual qualification, a local pygame journey at
Akashic `d24540e` with MegaPad `c7045d6` passed the
complete Desk, Pad semantic File activation/open/close, Pad edit, Daybook task
and date-navigation milestones, and Daybook's ordinary exact shared-resource
handoff into Pad. It qualifies those exact committed heads, including the
eleven Akashic optimization commits through `e754ac1` and the subsequent
cold-source compatibility corrections, at the host presentation-API boundary.
The selected Desk/Pad/Daybook checkpoint at those exact heads is historically
closed for the menu-plus-residual path; it did not advertise or exercise
semantic text collections. Physical UART delivery, panel completion, and touch
also remain open. At those historical heads, menus were the only advertised
semantic family. The current selected source/profile additionally activates
`RET_CONTROL_COLLECTIONS`, whose endpoint contract covers `TEXT_AREA`,
`TEXT_GRID`, `TABSET`, and `TAB`, plus `RET_INSTRUMENT`, whose selected product
contract covers `READOUT`, `METER`, and `STATUS`. This Akashic projection emits
both complete selected subsets. Window, pane, vector, image, series, cadence,
and other feature families remain unadvertised, and unclaimed content remains
visible through residual glyph spans.

Neutral collection records and builders now feed a direct-plus-mounted
canonical collection freezer. The resolved-tree walk observes direct authored
`<tabs>` elements, while ordinary `WDG` drawing records exact mounted `TXTA`,
`TGRID`, and `TAB` instances in a UIDL-TUI-private relation index.
`UCSN-CAPTURE` freezes their `TEXT_AREA`, `TEXT_GRID`, or `TABSET`/`TAB` values;
the aggregate adapter copies the descriptor/native banks; and the hybrid
producer maps the three `USCOL` families to the four exact neutral `CONTROL`
kinds.
Ordinary canonical `DATA_GRAPHICS` models likewise pass through the generic
UIDL snapshot and aggregate into the instrument planner rather than through an
applet scene. The engine, APT-1 bridge, claim path, aggregate accounting, and
acknowledged tab target route use these generic boundaries. None of those seams
is a callback or containing-app dispatch entry.

Pad, Daybook, and Sound Lab are acceptance targets, not semantic providers. The
selected source/profile activates collection and instrument capability, but
refusal still leaves their ordinary painting covered automatically by residual
`GLYPH_RUN`s. Once
admitted, Pad's clipped canonical editor and output `TEXT_AREA` roots, Pad's
two-row canonical `TABSET` root, and Daybook's clipped canonical `TEXT_GRID`
root become claims. TAB descendants carry semantic state and input identity
without claiming the root twice. Their remaining chrome and any mounted
surface without reusable semantics stay residual. Sound Lab's admitted
`DATA_GRAPHICS` root contributes its exact `READOUT`, `METER`, and `STATUS`
instrument graph. The complete `4b6a475`/`29bdfd6` physical Desk run qualified
these roots, acknowledged tab activation, ordinary editor/calendar
interactions, final-writer overlay handling, normal Sound Lab launch, and
unified publication. Its evidence is
`local_testing/evidence/rich-desktop-full-vertical-acceptance-20260902.md`.

That dependency inversion is complete. `semantic-collections.f` owns the
neutral entry header, family records, status vocabulary, builders, and deep
validators while depending only on UTF-8 and memory-span utilities. It sits
beneath both the canonical widget library and UIDL-TUI. The canonical textarea
measures and copies a widget-local `TEXT_AREA` directly from its ordinary flat
or gap-buffer state. The canonical text grid copies its bound, already
validated `TEXT_GRID` model from the same state used by its ordinary CELL draw
and selection handling. Neither widget owns attachment identity, clipping,
publication identity, or terminal storage.
`uidl-collection-snapshot.f` now observes direct UIDL-owned canonical
textareas and authored `<tabs>` elements during one resolved-tree walk. It also
enumerates canonical text areas, grids, and tabsets recorded beneath caller-
mounted composites by ordinary full or partial `WDG` draws. It deep-validates
and freezes each native value once, translates the complete semantic root into
screen-absolute UIDL-TUI coordinates, records exact ancestry/source clipping
and mounted generation in its 152-byte descriptor, and emits strict unsigned
`(source-index, root-key)` order. Its linear source-directory plus dense-node
work permits multiple root keys per source without a post-capture sort. Pad's
canonical editor/output text areas and tab header plus Daybook's canonical
calendar grid now reach this same freezer; their remaining ordinary drawing
stays residual. No containing-app callback or second semantic source is
involved.

Root-key order is stable identity order, not nested paint order. Mounted roots
currently share their outer source's resolved z, so later admission must refuse
overlapping mounted roots until ordinary draw observation supplies a generic
relative paint ordinal. This does not block Pad's nonoverlapping nested editor
and tab roots; refused overlap remains on the complete residual path.

This document defines the renderer-neutral boundary between the ordinary
UIDL/TUI draw lifecycle and an optional rich output adapter. The boundary is
hybrid: it carries genuine control semantics where those semantics exist and
coalesced residual glyph spans for the remaining visible draw output. It does
not create a second application scene, and it is not a transcription of the
terminal wire protocol.

The former `akashic/tui/rich-terminal/uidl-projector.f`, `uidl-driver.f`, and
`screen-plane.f` prototypes have been removed after confirming that neither the
selected composition nor a lower-stack diagnostic imports their providers.
Their useful attachment, stable-key, copied-snapshot, and retirement ideas were
forward-refactored into the aggregate adapter and hybrid producer. Their
`RUPJ-*`, `RTERM-*`, and `RTSCREEN-*` interfaces are not product paths. The
composed neutral engine exposes the live `RTE-S-*` status vocabulary directly;
there is no dormant `RTERM-S-*` alias layer.

## 1. Authority and lifecycle

The candidate is derived from the same ordinary UCTX, UIDL document, mounted
widgets, resolved layout, focus state, and TUI paint that produce CELL output.
Desk, Pad, Daybook, and other applets keep their existing descriptors, sources,
actions, bindings, and draw words. They do not enumerate retained objects,
reserve terminal storage, add renderer annotations, or call a terminal API.
They also do not register semantic providers, import rich-terminal or semantic
collection modules, use collection builders, or maintain a parallel semantic
revision. This is a dependency rule, not merely a convention for the current
acceptance fixtures.

Projection is entered only through UIDL-TUI's existing private optional
projection seam during the normal attach/project/relayout/quiesce/detach
lifecycle. One exact UCTX revision supplies both semantic observations and the
ordinary final draw surface. The projector must not call an applet's draw or
state callbacks a second time to manufacture a rich scene.

The UIDL tree, widget state, focus and selection state, action dispatch, and
application data remain authoritative. A candidate is copied derived output.
Terminal materialization may be discarded and rebuilt without changing any of
that state.

## 2. Candidate composition

One candidate contains:

* exact source and surface generations for the ordinary frame from which it
  was captured;
* positive surface dimensions and the root clip;
* canonical semantic proposals with stable renderer-neutral keys;
* the accepted semantic claims selected against one coherent neutral
  capability snapshot;
* maximal residual glyph spans for visible cells outside the union of those
  claims; and
* checked counts, byte extents, quotas, and a seal covering the complete
  candidate.

Semantic items and residual spans are two representations within one desired
projection and one publication attempt. They are not separate producers and
must not advance independently.

### 2.1 Semantic proposals

The advertised product path uses `UMSN-CAPTURE` to visit the resolved ordinary
UIDL tree once and copy menubars, menus, items, separators, selection, open,
and activation state. `UCSN-CAPTURE` now also freezes renderer-neutral
`TEXT_AREA` values owned by direct UIDL textareas or canonical mounted `TXTA`
widgets, `TEXT_GRID` values owned by canonical mounted `TGRID` widgets, and
`TABSET`/`TAB` graphs owned by authored `<tabs>` elements or mounted canonical
`TAB` widgets. `UDGSN-CAPTURE` freezes ordinary canonical `DATA_GRAPHICS`
models from the same resolved draw into renderer-neutral graph descriptors and
native entries. RUHA carries all of them in the same aggregate. Generic
lowering maps collections to their exact neutral control kinds and the selected
data-graphics objects to `READOUT`, `METER`, and `STATUS` instruments without
changing menu semantics. These implemented seams are active in the selected
source/profile and passed the complete local physical journey at Akashic
`4b6a475` with MegaPad `29bdfd6`, including the ordinary Desk overlay and normal
Sound Lab launch. Exact evidence is recorded in
`local_testing/evidence/rich-desktop-full-vertical-acceptance-20260902.md`.
Future families such as windows, panes, and dialogs must add an equivalent
generic renderer-independent snapshot boundary rather than extending either
existing record by implication. That boundary and its family records, builder,
validator, and status vocabulary belong below UIDL-TUI and the canonical
widget library, never in the containing applet. UIDL-TUI can then observe the
semantics automatically while traversing the same ordinary lifecycle. One
canonical implementation may expose several
stable-keyed semantic objects for a genuine composite widget; it does not
register a callback, lend an applet context, or maintain a parallel
terminal-facing revision.

That automatic projection is a read-only, caller-bounded observation of the
same authoritative state and lifecycle revision that ordinary draw uses. For
one observed revision it must reproduce identical exact content, and every
represented mutation must advance the ordinary authoritative state before the
change is observable. UIDL-TUI supplies attachment/source identity, resolved
geometry, clipping, visibility, and lifecycle fences; a copied candidate cannot
make inconsistent source state truthful after the fact.

`SEMANTIC-CONTENT-1` deliberately defines no direct `TEXT_AREA` or `TEXT_GRID`
item-hit input; its semantic content hit targets are TAB records. The selected
checkpoint therefore activates a real Pad tab through the acknowledged generic
control route, while Pad editor and Daybook interactions use their ordinary
focused keyboard route. Either form of input becomes eligible only after the
exact complete composite has been physically acknowledged, then enters the
existing Desk/UCTX/widget input path against that acknowledged revision. There
is no generic mounted-provider registry, no mounted-provider dispatcher, and
no applet callback. A future direct collection-item input protocol would have
to restore and validate the authoritative canonical widget through this same
ordinary UI tree, but that separate protocol work is neither part of this
slice nor a condition for advertising its output capability.

Each semantic proposal contains at least:

* a stable key `(source-kind, source-index, semantic-subkey)`;
* a neutral control kind and versioned snapshot extent;
* resolved bounds, clipping, visibility, and paint order from UIDL-TUI;
* copied current value and presentation-independent control state; and
* a source generation sufficient to reject stale input or mutation.

The snapshot describes meaning, not how the terminal draws it. It contains no
wire owner/object identity, APT opcode, font, pixel allocation, retained text
reservation, terminal capacity, Desk slot, or applet type. A control family is
added only when its neutral state and event mapping are truthful; a GROUP,
LABEL, or GLYPH_RUN must not be renamed to pretend that it is a menu, editor,
or calendar.

The selected renderer may accept a proposal only when its advertised neutral
capability and current caller/terminal bounds can represent the complete
control. Partial semantic materialization is refusal. The proposal then makes
no claim and ordinary residual coverage supplies its pixels.

### 2.2 Semantic claims

An accepted visible semantic control or instrument graph claims the cells in
its resolved bounds after ancestor clipping and surface clipping. Claim
resolution observes the ordinary final paint order; the residual exclusion mask
is the union of final accepted visible claims. Overlapping semantics retain
their normal z-order and clip relationships in the semantic plan.

The ordinary screen separately records final-writer provenance across direct
draws and guarded overlays. If a later foreground layer touches a document's
region, aggregate capture omits that document's menu, collection, and
`DATA_GRAPHICS` slices atomically for the draw. Residual projection then owns
both the covered pixels and hit area; it is invalid to retain hidden semantic
targets beneath the foreground overlay.

A claim is exclusive in the rich plane. The terminal renderer owns rich
representation and, for controls that expose a target, rich hit testing, while
Akashic retains authoritative focus, actions, and state transitions. The
residual encoder must not emit the claimed cells, and a second CELL-derived rich
object must not be laid under or over the same semantic root as a hidden
duplicate.

CELL remains a complete independent fallback plane. If semantic support is
unavailable, capture is invalid, or admission refuses a control, no claim is
published and its ordinary CELL drawing becomes eligible for residual
encoding. Refusal never reserves a blank rectangle.

### 2.3 Residual glyph spans

After semantic claims are final, the planner scans the already-painted ordinary
surface once in row-major order. It skips claimed cells and emits one residual
glyph span for each maximal contiguous sequence of unclaimed cells on a row
with the same foreground, background, and text attributes. The span carries
the glyph sequence and exact cell width. A claim boundary, row boundary, style
change, or representability boundary ends a span.

Residual spans are the generic coverage path for draw work that has no honest
semantic snapshot yet. This includes Desk chrome not represented by a semantic
control, Pad's gutter and other panel chrome outside its canonical editor/tab
roots, and Daybook's agenda and non-grid chrome outside its canonical calendar
grid. While collection capability is disabled or an editor, grid, or tab graph
is refused, those ordinary cells also remain unclaimed and take this same
complete residual route. In the selected source/profile the capability is
active; this refusal rule remains the complete fallback for an unsupported
endpoint or an inadmissible candidate. Ordinary paint continues unchanged
throughout.

A full-screen one-object-per-cell projection is forbidden as product
architecture and cannot serve as vertical acceptance evidence. Actual
candidates contain semantic items and coalesced spans, not one object for every
cell. Caller storage may nevertheless reserve checked worst-case span capacity
from the maximum cell count: a pathological checkerboard can legitimately
approach one run per cell. Exact preflight admits only the candidate actually
constructed; worst-case storage does not make per-cell topology the policy.

Residual topology may change when styles or claims change. Stable identity is
mandatory for semantic keys. The planner may use stable span keys where they
remain exact, or atomically replace the bounded residual plane when spans
split/merge; it must not mint one stable object identity per screen cell to
avoid solving replacement correctly.

## 3. Canonical order and linear identity mapping

Semantic proposals are written once in canonical ascending key order. Residual
spans follow in canonical `(row, starting-column)` order after claim
resolution. Duplicate or descending keys are invalid.

Canonical key order is not hierarchy order. A legal UIDL reparent can place an
older pool index beneath a newer parent. Identity merge therefore consumes the
ascending key stream, while control publication resolves explicit parent keys
through caller-bounded lookup storage and emits the fixed-depth menu family in
MENUBAR, MENU, then ITEM/SEPARATOR passes. New monotone terminal identities are
assigned in that same parent-first order; retired entries are dropped in
reverse depth. Authored sibling ordinals remain the renderer-neutral ordering
authority, so none of these passes sorts by repeated whole-bank search.

For a candidate compatible with the exact acknowledged retained target, stable
semantic keys are reconciled by a single merge of the new sorted stream with
the previous sorted identity map. Unchanged keys reuse their retained-wire IDs;
new and removed keys become bounded creation and retirement work. A complete
`RET_REPLACE_START` instead begins with an empty graph and assigns fresh IDs
from the checked monotone owner high-water even when renderer-neutral keys and
application state are unchanged. The parent-first passes assign each new key in
that order. This is `O(new-items + old-items + source-high-water)`.

The following algorithms are forbidden on the product path:

* scanning all earlier candidate items to prove each new key unique;
* scanning the complete prior identity bank for every new key;
* repeatedly selecting the minimum remaining object ID; and
* sorting by repeated whole-bank search after capture.

Canonical construction makes uniqueness, quota accumulation, claim order, and
identity reuse part of the same linear planning work.

## 4. Construction, validation, and freezing

Construction is fail-before-publication. It writes an inactive caller-owned
bank, captures semantic snapshots and the ordinary surface generation, and
leaves the active selector unchanged on any invalid source, arithmetic failure,
or capacity refusal. There is no truncation.

The complete candidate crosses one full validation authority:

1. construction establishes canonical records and checked running aggregates;
2. admission performs one full linear traversal, resolves neutral capability,
   claims, residual spans, quotas, and stable identities, and freezes the exact
   candidate or copies it to the engine-owned attempt bank; and
3. downstream adapter query, hidden publication, reveal, and acknowledgement
   consume the frozen descriptor and checked aggregates without walking the
   candidate again.

If publication continues to borrow a caller-owned bank that can mutate after
admission, the publisher performs one final full mutation-safety validation
immediately before seal/publication. That is the only allowed repeated full
traversal. It must correlate the exact address, extent, generation, canonical
order, record validity, text bytes, counts, quotas, and seal. If admission
copied the candidate into an immutable engine-owned attempt bank, an O(1)
generation/seal correlation replaces that traversal.

In particular, the seal, adapter capability query, hidden replacement, and
reveal seams must not each deep-validate the same large candidate. Public
boundaries may still perform constant-time descriptor, phase, generation, and
storage-disjoint checks. A validation certificate is private derived state,
never caller authority, and is invalidated by selector, generation, extent, or
owner changes.

All storage remains caller-bounded. Bounds derive from supplied spans, the
actual candidate, and negotiated neutral limits. UIDL must not carry retained
buffer reservations, and the product must not introduce an unrelated fixed
control, span, text, or screen-object limit.

## 5. Publication and input

The accepted semantic controls, instruments, and residual spans enter the
existing unified CELL/rich publisher as one immutable contribution. Initial
construction, uncertain retained authority, and topology-changing fallback use
a hidden replacement. A compatible later draw is derived from the acknowledged
retained bank and uses `RET_DELTA`; if that draw is retained-identical, one
idempotent replacement fence advances the exact composite without rebuilding
the retained plane. Hidden replacement, delta, and fence all keep CELL
bookkeeping, semantic rich state, and residual rich state on one commit
boundary.

Input against a rich semantic hit target is eligible only after the exact
composite revision containing that target has reached the selected sink's
completion boundary and been acknowledged. The accepted target is bound to
that exact composite revision and carries its current retained-wire control
identity plus any family-specific revision or item identity required by its
input contract. A later complete replacement may assign a different numeric
control ID; input then uses only the new acknowledged target. Akashic retains
the attachment/source identity needed to restore the authoritative UCTX and
reach the ordinary UIDL/widget focus and action path.

The implemented menu and TAB routes meet that rule. A sealed TAB child target
is reduced to a point in the exact candidate, becomes active only after that
candidate is physically acknowledged, and returns through Desk as ordinary
mouse input to the canonical widget. `TEXT_AREA` and `TEXT_GRID` continue to
use the existing Pad and Daybook keyboard paths, likewise withheld until exact
complete-composite acknowledgement. `SEMANTIC-CONTENT-1` defines no direct
AREA|GRID item-hit input, so adding such input is outside this slice rather
than a capability-activation blocker. Collection capability bit 9 and
instrument capability bit 3 are active in the selected source/profile. The
`4b6a475`/`29bdfd6` journey physically qualified collection output,
acknowledged tab activation, ordinary editor/calendar interactions, final-writer
overlay handling, and Sound Lab's exact instrument graph with every action
withheld until acknowledgement. Residual glyph spans do not invent semantic hit
targets.

Reset, resize, minimize/restore, and terminal loss rebuild derived output from
the newest authoritative UCTX state. They do not reconstruct application state
from the candidate or terminal model.

## 6. Implemented boundary and cleanup

The selected composition source now contains generic menu, collection, and
`DATA_GRAPHICS` snapshots, linear control/instrument claim planning, residual
span coalescing, the final-writer-aware visible-UCTX aggregate adapter, generic
collection and instrument lowering, and the unified hybrid producer. Its
advertised production mode publishes menu semantics, all canonical collection
families, `READOUT`/`METER`/`STATUS` instruments, and residual coverage.
Collection and instrument capability are active in the selected source/profile,
and the full vertical passed complete local physical Desk acceptance at
`4b6a475`/`29bdfd6`.
Initial or uncertain candidates use hidden replacement, followed by
acknowledged-bank deltas or an identical-frame fence when compatible.
`desk-apt1.f` no longer composes the per-cell producer. The uncomposed
`screen-plane.f` bootstrap and dormant LABEL-only driver/projector were removed
after the composition, packaging closure, and focused diagnostic imports were
audited. Their former providers and status aliases are absent; they are not
parallel product paths.

This forward refactor did not revert the working horizontal transport or
physical sink. The current GLYPH_RUN encoder remains useful for residual spans,
style conversion, and byte-oracle coverage, but its one-object-per-cell
topology is not reused.

The historical local pygame journey at Akashic `d24540e` and MegaPad `c7045d6`
passed complete Desk composition, Pad menu open/close and edit, Daybook task
addition and date navigation, and the ordinary Daybook-to-Pad shared-resource
route through the normal lifecycle. The exact evidence is recorded in
`local_testing/evidence/rich-desktop-daybook-pad-acceptance-20260830.md`; that
menu-plus-residual host presentation-API checkpoint is closed. It is not
acceptance evidence for the newer semantic `TEXT_AREA`, `TEXT_GRID`,
`TABSET`, or `TAB` path. A per-cell screen, one control, a special fixture, or
an active retained model without the substantive rich pixels would not have
qualified and still does not qualify this semantic-family extension.

The collection-only local X11 journey at Akashic `dd27f34` with MegaPad
`29bdfd6` historically supplied the missing collection evidence. The current
`4b6a475`/`29bdfd6` journey requalified those semantics across legitimate
retained-wire ID rebasing, exercised ordinary final-writer overlay occlusion,
normally launched Sound Lab, and accepted one nonempty instrument region with
exactly 8 `READOUT`, 2 `METER`, and 3 `STATUS` objects. The complete record is
`local_testing/evidence/rich-desktop-full-vertical-acceptance-20260902.md`.
