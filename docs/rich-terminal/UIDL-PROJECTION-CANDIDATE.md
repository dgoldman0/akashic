# Hybrid UIDL projection candidates

Status: normative target contract. The hybrid candidate and semantic control
families described here are not implemented yet.

This document defines the renderer-neutral boundary between the ordinary
UIDL/TUI draw lifecycle and an optional rich output adapter. The boundary is
hybrid: it carries genuine control semantics where those semantics exist and
coalesced residual glyph spans for the remaining visible draw output. It does
not create a second application scene, and it is not a transcription of the
terminal wire protocol.

The checked-in `akashic/tui/rich-terminal/uidl-projector.f` and
`uidl-driver.f` are an earlier LABEL-only experiment. Their useful attachment,
stable-key, copied-snapshot, and retirement ideas inform this contract, but the
modules are dormant, stale against the current GLYPH_RUN facade, and contain
repeated or quadratic candidate scans. They are not to be revived as the
product driver. The implementation proceeds by forward-refactoring their good
concepts into one new hybrid planner.

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

`ED.SEMANTICS` remains the generic element capture registry. It must grow
beyond LABEL to cover existing controls whose ordinary model already has real
renderer-independent meaning, including menubars, menus, items, dialogs, text
areas, focus, selection, and activation state. A corresponding generic mounted
widget hook may expose the same kind of copied snapshot for widgets reached
through `UTUI-WIDGET-SET`; it must not be specific to Pad, Daybook, Desk, or
APT-1.

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
architecture and cannot serve as vertical acceptance evidence. Caller capacity
may bound the number and bytes of actual semantic items and coalesced spans,
but product storage must not be derived from `rows * columns` retained objects.
A pathological checkerboard can legitimately approach the caller bound and
return capacity; it does not justify a permanent object-per-cell policy.

Residual topology may change when styles or claims change. Stable identity is
mandatory for semantic keys. The planner may use stable span keys where they
remain exact, or atomically replace the bounded residual plane when spans
split/merge; it must not mint one stable object identity per screen cell to
avoid solving replacement correctly.

## 3. Canonical order and linear identity mapping

Semantic proposals are written once in canonical ascending key order. Residual
spans follow in canonical `(row, starting-column)` order after claim
resolution. Duplicate or descending keys are invalid.

Stable semantic object IDs are assigned by a single merge of the new sorted
keys with the previous sorted identity map. Unchanged keys reuse their IDs;
new keys consume a checked monotone high-water; removed keys become bounded
retirement work. This is `O(new-items + old-items)`.

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
CELL/rich publisher as one immutable contribution. Initial construction and
topology-changing replacement remain hidden until the exact complete composite
is committed and physically acknowledged. CELL bookkeeping, semantic rich
state, and residual rich state advance together or not at all.

Input against a rich semantic control is eligible only after the exact
composite revision containing that control has been physically displayed and
acknowledged. Terminal hit results identify the private projected semantic key
and revision; Akashic revalidates both and routes the event through ordinary
UIDL/widget focus and action handling. Residual glyph spans do not invent
semantic hit targets.

Reset, resize, minimize/restore, and terminal loss rebuild derived output from
the newest authoritative UCTX state. They do not reconstruct application state
from the candidate or terminal model.

## 6. Forward-refactor boundary

The implementation sequence is intentionally forward-only:

1. keep `screen-plane.f` temporarily as lower-stack publication evidence while
   the hybrid interfaces are built;
2. add the generic semantic control and mounted-widget snapshot seams needed by
   the real Desk/Pad/Daybook journey;
3. add a caller-bounded linear claim planner and residual span coalescer with
   focused structural and off-screen tests;
4. bind that one producer to the existing UIDL-TUI lifecycle and unified
   publisher, reusing current owner, hidden replace/reveal, acknowledgement,
   reset, and teardown machinery;
5. switch `desk-apt1.f` from the per-cell producer to the hybrid producer; and
6. delete superseded per-cell product machinery and the dormant LABEL-only
   driver/projector rather than retaining parallel legacy paths.

This sequence does not revert the working horizontal transport and physical
sink. It changes the candidate source at a coherent composition boundary. The
current GLYPH_RUN encoder remains useful for residual spans, style conversion,
and byte-oracle coverage, but its one-object-per-cell topology is not reused.

The blocking proof remains the ordinary Desk composition with canonical Pad
and Daybook launched through their real descriptors and UCTX lifecycle. The
frame must contain genuinely semantic high-level controls plus rich residual
coverage for unclaimed custom drawing, preserve complete CELL fallback, show a
real Pad edit and Daybook navigation/selection, and bind input only after exact
physical acknowledgement. A per-cell screen, one LABEL, an applet-specific
fixture, or an active retained model without those pixels does not qualify.
