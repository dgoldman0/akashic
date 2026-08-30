# Hybrid UIDL projection candidates

Status: normative implemented current-head qualification contract. Akashic
publishes ordinary UIDL menu controls and coalesced residual glyph spans through
the selected Desk APT-1 composition. `akashic/tui/uidl-menu-snapshot.f`
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
into complete double-buffered directory and record/text banks, reusing a
validated prior slice for each unchanged document. `hybrid-screen-producer.f`
copies that aggregate and builds one neutral candidate. Initial, reset, resize,
topology-changing, or otherwise uncertain candidates use complete hidden
replacement and reveal. Compatible later candidates compare only with the
exact acknowledged target and use `RET_DELTA`; an equivalent candidate uses
one idempotent replacement as a nonempty revision fence.

A local pygame journey at Akashic `3404fe9` with MegaPad `8941782` passed the
complete Desk, Pad semantic File activation/open/close, Pad edit, and Daybook
task milestones. Eleven later Akashic optimization commits through `e754ac1`
have not been rerun through that physical journey, and the separately required
Daybook-to-Pad shared-resource handoff is not in the harness. Menus are the
currently implemented semantic family. Window/pane, tab, and other control
semantics remain future work only where the ordinary Desk/Pad/Daybook lifecycle
justifies them; unclaimed content remains visible through residual glyph spans.

This document defines the renderer-neutral boundary between the ordinary
UIDL/TUI draw lifecycle and an optional rich output adapter. The boundary is
hybrid: it carries genuine control semantics where those semantics exist and
coalesced residual glyph spans for the remaining visible draw output. It does
not create a second application scene, and it is not a transcription of the
terminal wire protocol.

The checked-in `akashic/tui/rich-terminal/uidl-projector.f`, `uidl-driver.f`,
and `screen-plane.f` are uncomposed prototype residue. Their useful attachment,
stable-key, copied-snapshot, and retirement ideas have already been
forward-refactored into the aggregate adapter and hybrid producer. They are not
to be revived as product paths and should be removed in a separate cleanup
slice after confirming that no lower-stack diagnostic imports them.

## 1. Authority and lifecycle

The candidate is derived from the same ordinary UCTX, UIDL document, mounted
widgets, resolved layout, focus state, and TUI paint that produce CELL output.
Desk, Pad, Daybook, and other applets keep their existing descriptors, sources,
actions, bindings, and draw words. They do not enumerate retained objects,
reserve terminal storage, add renderer annotations, or call a terminal API.

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

The current product path uses `UMSN-CAPTURE` to visit the resolved ordinary
UIDL tree once and copy menubars, menus, items, separators, selection, open,
and activation state. Future families such as windows, panes, tabs, dialogs,
and text areas must add an equivalent generic renderer-independent snapshot
boundary rather than extending this menu-specific record by implication. A
corresponding generic mounted-widget hook may expose the same kind of copied
snapshot for widgets reached through `UTUI-WIDGET-SET`; it must not be specific
to Pad, Daybook, Desk, or APT-1.

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

An accepted visible semantic control claims the cells in its resolved bounds
after ancestor clipping and surface clipping. Claim resolution observes the
ordinary final paint order; the residual exclusion mask is the union of final
accepted visible claims. Overlapping semantic controls retain their normal
z-order and clip relationships in the semantic plan.

A claim is exclusive in the rich plane. The terminal renderer owns rich
representation and rich hit testing for that control, while Akashic retains
authoritative focus, actions, and state transitions. The residual encoder must
not emit the claimed cells, and a second CELL-derived rich object must not be
laid under or over the same control as a hidden duplicate.

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
control, the custom mounted Pad editor surface, and Daybook's drawn calendar
and agenda until equivalent generic widget semantics exist. Their ordinary
paint continues unchanged and is therefore covered without an applet-specific
retained scene.

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

Stable semantic keys are reconciled by a single merge of the new sorted stream
with the previous sorted identity map. Unchanged keys reuse their IDs; new and
removed keys become bounded creation and retirement work. The parent-first
passes above assign each new key from a checked monotone high-water. This is
`O(new-items + old-items + source-high-water)`.

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

The accepted semantic operations and residual spans enter the existing unified
CELL/rich publisher as one immutable contribution. Initial construction,
uncertain retained authority, and topology-changing fallback use a hidden
replacement. A compatible later draw is derived from the acknowledged retained
bank and uses `RET_DELTA`; if that draw is retained-identical, one idempotent
replacement fence advances the exact composite without rebuilding the retained
plane. Hidden replacement, delta, and fence all keep CELL bookkeeping,
semantic rich state, and residual rich state on one commit boundary.

Input against a rich semantic control is eligible only after the exact
composite revision containing that control has reached the selected sink's
completion boundary and been acknowledged. Terminal hit results identify the
private projected semantic key and revision; Akashic revalidates both and
routes the event through ordinary UIDL/widget focus and action handling.
Residual glyph spans do not invent semantic hit targets.

Reset, resize, minimize/restore, and terminal loss rebuild derived output from
the newest authoritative UCTX state. They do not reconstruct application state
from the candidate or terminal model.

## 6. Implemented boundary and cleanup

The selected composition now contains the generic menu snapshot, linear claim
planner, residual span coalescer, visible-UCTX aggregate adapter, and unified
hybrid producer. It publishes an initial or uncertain hidden replacement, then
acknowledged-bank deltas or an identical-frame fence when compatible.
`desk-apt1.f` no longer composes the per-cell producer. The uncomposed
`screen-plane.f` bootstrap and dormant LABEL-only driver/projector are
superseded implementation residue. Remove them in a separate cleanup after
checking that no focused diagnostic imports them; they are not parallel product
paths.

This forward refactor did not revert the working horizontal transport or
physical sink. The current GLYPH_RUN encoder remains useful for residual spans,
style conversion, and byte-oracle coverage, but its one-object-per-cell
topology is not reused.

The recorded local pygame journey at Akashic `3404fe9` and MegaPad `8941782`
passed complete Desk composition, Pad menu open/close and edit, and Daybook task
addition through the normal lifecycle. Eleven later Akashic commits through
`e754ac1` have not been physically rerun, so current-head qualification remains
open. That rerun must also cover the intended Daybook-to-Pad shared-resource
route rather than only independent interaction in each app. A per-cell screen,
one control, an applet-specific fixture, or an active retained model without
the substantive rich pixels does not qualify.
