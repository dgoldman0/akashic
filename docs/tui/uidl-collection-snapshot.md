# Canonical UIDL collection snapshots

`akashic/tui/uidl-collection-snapshot.f` freezes renderer-neutral collection
values reached through one ordinary UIDL-TUI resolved observation. Direct
authored UIDL remains textarea-only: a materialized, UIDL-owned `<textarea>`
contributes the `TEXT_AREA` produced by its exact canonical `TXTA`. The generic
mounted path additionally recognizes genuine canonical `TXTA` and `TGRID`
widgets automatically observed beneath a caller-mounted composite during its
ordinary `WDG` draw. It asks the exact owning widget to produce `TEXT_AREA` or
`TEXT_GRID` from the same state used for ordinary drawing and input. It does
not draw, invoke lifecycle code, call an applet, select a renderer, or publish
terminal bytes.

`UCSN-CAPTURE` accepts one `USCOL` builder, validation scratch, collection work,
a pointer-free descriptor bank, and a native entry bank. All storage is caller
bounded. The result is `(descriptor-count native-used status)`, where status is
`OK`, `CAPACITY`, `UNAVAILABLE`, or `INVALID`. Capacity refusal and invalid
source state return zero counts; touched output prefixes and all scratch are
cleared. A capacity refusal discovered by exact measure happens before the
corresponding native entry is written.

## Descriptor identity and geometry

Every 152-byte descriptor contains:

- source kind `UCSN-SOURCE-UIDL`;
- the stable UIDL pool source index;
- the source generation, zero for a direct UIDL-owned widget and a live
  nonzero, non-`-1` lifecycle value for a caller-mounted source;
- a native-entry offset relative to this capture's native bank;
- screen-absolute UIDL-TUI coordinates for the translated semantic root;
- the complete, unclipped semantic-root height and width;
- the screen-absolute row, column, height, and width of the semantic root's
  exact nonempty clip;
- resolved paint z; and
- the 48-byte summary produced by the one deep `USCOL` validation.

The exact layout is:

| Offset | Field |
|--------|-------|
| +0 | source kind |
| +8 | UIDL source index |
| +16 | source generation |
| +24 | native-bank-relative entry offset |
| +32 | translated root row |
| +40 | translated root column |
| +48 | complete root height |
| +56 | complete root width |
| +64 | clip row |
| +72 | clip column |
| +80 | clip height |
| +88 | clip width |
| +96 | resolved z |
| +104 | 48-byte `USCOL` summary |

`UCSN-DESCRIPTOR-BYTES` reports 152. The public generation and clip accessors
are `UCSN-DESCRIPTOR-SOURCE-GENERATION@`,
`UCSN-DESCRIPTOR-CLIP-ROW@`, `UCSN-DESCRIPTOR-CLIP-COLUMN@`,
`UCSN-DESCRIPTOR-CLIP-HEIGHT@`, and `UCSN-DESCRIPTOR-CLIP-WIDTH@`.

The canonical identity is
`(UIDL, source-index, source-generation, semantic-root-key)`. A direct
textarea uses generation zero and root key one. A mounted source uses its
private lifecycle generation (any cell except zero and the exhausted `-1`
sentinel) and a nonzero source-local root key assigned to the exact canonical
widget identity `(family, instance)`. The family is `TEXT_AREA` for `TXTA` or
`TEXT_GRID` for `TGRID`; including it prevents two family-local instance-token
sequences from aliasing. Producer provenance is carried by that validated
`USCOL` family rather than by changing source identity. That tuple is stable
only within one document lineage. Any upper
layer that retains it across publication must also carry the UCTX attachment,
source revision, and publication/resolved-state fences; UCSN deliberately owns
none of those outer lifecycle authorities.

The descriptor row and column are screen-absolute UIDL-TUI coordinates after
adding the widget-local root. For a textarea, that local root excludes gutter
chrome. A text grid's local root is its complete canonical widget region. The
separate clip is the intersection of the complete semantic root, the widget's
exact region ancestry, and the resolved UIDL source rectangle. Zero-area
intersections are omitted. The native `USCOL` value still carries the complete
root and is never cropped or reflowed. These coordinates are not yet
selected-retained-region-relative; later composition subtracts the
retained-region origin and applies surface and renderer clipping.

## Linear work and canonical output

The work bank has two checked parts. A 16-byte directory entry for every index
below the UIDL pool high-water records the first dense node and count owned by
that source, including zero entries for holes.
The remainder is a dense array of 152-byte descriptor nodes. Consequently one
source may own multiple roots without allocating a sparse
`source-high-water × root-capacity` table.

`UCSN-WORK-BYTES ( element-high-water descriptor-capacity -- bytes|0 )`
computes the exact source-directory plus dense-node requirement with signed
overflow checks. Capture scans source-directory entries in ascending UIDL
index and emits each source's strictly ascending root run. All entries in one
source run carry the same generation. Thus descriptor order is strict unsigned
`(source-index, root-key)` order, while generation remains part of identity and
the native bank may remain in producer-visit order. Construction and canonical
emission are linear; there is no post-capture heap or repeated minimum search.

Capture derives the directory/dense split from the document's live pool
high-water, not from a hard-coded maximum. A reusable work bank sized for a
larger high-water remains safe: the surplus becomes additional dense-node
capacity, while the separate descriptor bank still bounds admission. The work
shape supports several roots per source. A direct textarea contributes root
key one; an observed mounted composite may contribute several canonical
text-area and text-grid roots under its one source index and generation.

## Observation and storage authority

Capture is a synchronous UI-owner operation. One outer
`UTUI-RESOLVED-OBSERVE` holds UIDL-TUI and UIDL state across all of the
following work:

1. validate and pairwise-separate all five caller banks;
2. check every bank against UCSN, `USCOL`, UIDL-TUI, every direct canonical
   textarea, and every genuine caller-mounted text-area or text-grid widget,
   including hidden widgets;
3. clear scratch;
4. walk the resolved tree once for direct canonical widgets;
5. traverse the private canonical mounted-relation index, revalidating each
   relation against the current attachment, generation, `(family, instance)`,
   region ancestry, resolved source, and effective visibility;
6. exact-measure and exact-copy each admitted widget through the current
   visitor-scoped seam;
7. deep-validate each native entry exactly once; and
8. emit the pointer-free canonical descriptor stream.

The public visitor operation retains its standalone all-source preflight. UCSN
uses a private preflighted copy entry only while the outer all-bank proof is
live, avoiding a complete widget-pool rescan for every captured root. Mounted
capture dispatches by the relation's validated family to
`TXTA-TEXT-AREA-CAPTURE` or `TGRID-TEXT-GRID-CAPTURE`; it is not a provider
call. No widget pointer leaves UIDL-TUI, and there is no applet callback or
mounted-provider registry.

The five-bank range proof also uses UIDL-TUI's private already-observed storage
queries. It therefore checks the same authoritative UIDL, state, canonical,
and mounted-widget spans without recursively opening a second semantic
observation.

Mounted discovery occurs before snapshotting, inside the ordinary draw that
the app shell runs through `UTUI-DRAW-OBSERVE`. The common `WDG` observer sees
truthful full-draw begin/end/abort phases and canonical partial-draw completion.
It validates an exact canonical `TXTA` or `TGRID`, associates its region
ancestry with one unique caller-mounted UIDL source, and records only a private
`(family, instance)` relation. A successful full composite draw transaction
replaces that source's relation set; a successful partial canonical draw can
upsert one relation.
Widget replacement or detachment, subtree removal, document teardown, and
projection detach invalidate the affected relation state and advance or retire
its generation. The live relation chain is maintained in canonical unsigned
`(source-index, root-key)` order and belongs to the active UCTX.

That canonical order is identity order, not nested paint order. All mounted
roots currently inherit the outer source's resolved z. Pad has one mounted
semantic editor root and Daybook's ordinary wide calendar has one mounted grid
root. Nonoverlapping sibling roots are unambiguous, but an upper admission step
must reject overlapping mounted roots until the generic draw observation also
freezes their relative paint ordinal. Residual fallback remains complete in
that case.

The snapshot uses only private, outer-observation-scoped relation iteration,
geometry, and capture words. Its visitor receives pointer-free source index,
generation, root key, and a borrowed resolved record; no relation or widget
pointer leaves UIDL-TUI. Applications register no provider and receive no
semantic or renderer callback.

The caller invokes snapshot capture after the ordinary paint whose state it is
freezing. Capture refreshes UIDL-TUI's fixed proxy region and authoritative
focus immediately before reading the widget, but it does not run draw-time
scroll adjustment or paint a second scene.

## Current boundary

This slice proves the direct canonical textarea and automatically discovered
mounted canonical text areas and text grids, including exact widget-owned
content, selection/focus state, generation-fenced identity, geometry and clip
translation, caller capacity, alias rejection, and frozen canonical order.
Pad's nested shared textarea is therefore eligible through the generic mounted
path. Its custom panel tabs, underline, gutter, and other chrome are not
`TEXT_AREA` values and remain ordinary residual draw output; there is no
Pad-specific semantic adapter.

`TGRID` is authoritative for the bound live grid widget: it deeply validates
one renderer-neutral `TEXT_GRID` model and uses that same model for CELL draw,
directional selection/input, and snapshot capture. Daybook's ordinary wide
month calendar is the first grid consumer. Daybook builds and atomically binds
the calendar model, while its normal mounted `TGRID` draw supplies discovery;
Daybook has no collection callback or terminal-facing representation. When
Daybook uses its ordinary narrow agenda-only layout, the grid is not drawn and
therefore contributes no mounted root.

UCSN still only freezes the collection bank. Upper claim, aggregate,
publication, input, and residual-composition lifecycle work must consume that
bank before it is evidence of a functional rich-terminal Desk.
