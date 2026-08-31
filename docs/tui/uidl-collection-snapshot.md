# Canonical UIDL collection snapshots

`akashic/tui/uidl-collection-snapshot.f` freezes renderer-neutral collection
values reached through one ordinary UIDL-TUI resolved-tree observation. The
current functional slice recognizes a materialized, UIDL-owned `<textarea>`
and asks its canonical `TXTA` widget to produce the same `TEXT_AREA` value that
the widget derives from its ordinary edit and draw state. It does not draw,
invoke lifecycle code, select a renderer, or publish terminal bytes.

`UCSN-CAPTURE` accepts one `USCOL` builder, validation scratch, collection work,
a pointer-free descriptor bank, and a native entry bank. All storage is caller
bounded. The result is `(descriptor-count native-used status)`, where status is
`OK`, `CAPACITY`, `UNAVAILABLE`, or `INVALID`. Capacity refusal and invalid
source state return zero counts; touched output prefixes and all scratch are
cleared. A capacity refusal discovered by exact measure happens before the
corresponding native entry is written.

## Descriptor identity and geometry

Every 112-byte descriptor contains:

- source kind `UCSN-SOURCE-UIDL`;
- the stable UIDL pool source index;
- a native-entry offset relative to this capture's native bank;
- screen-absolute UIDL-TUI coordinates for the translated semantic root;
- the complete, unclipped semantic-root height and width;
- resolved paint z; and
- the 48-byte summary produced by the one deep `USCOL` validation.

The canonical key is `(UIDL, source-index, semantic-root-key)`. The current
textarea root key is one. Producer provenance is carried by the validated
`USCOL` family rather than by changing source identity.
That triple is stable only within one document lineage. Any upper layer that
retains it across publication must also carry the UCTX attachment, source
revision, and resolved-state generation; UCSN deliberately owns none of those
lifecycle fences.

The descriptor row and column are screen-absolute UIDL-TUI coordinates after
adding the widget-local root. For a textarea, that local root excludes gutter
chrome. These coordinates are not yet selected-retained-region-relative.
Later composition subtracts the retained region origin and applies ancestor,
surface, and renderer clipping; this snapshot never clips or reflows the
native entry.

## Linear work and canonical output

The work bank has two checked parts. A 16-byte directory entry for every index
below the UIDL pool high-water records the first dense node and count owned by
that source, including zero entries for holes.
The remainder is a dense array of 112-byte descriptor nodes. Consequently one
source may own multiple roots without allocating a sparse
`source-high-water × root-capacity` table.

`UCSN-WORK-BYTES ( element-high-water descriptor-capacity -- bytes|0 )`
computes the exact source-directory plus dense-node requirement with signed
overflow checks. Capture scans source-directory entries in ascending UIDL
index and emits each source's strictly ascending root run. Construction and
canonical emission are linear; there is no post-capture heap or repeated
minimum search.

Capture derives the directory/dense split from the document's live pool
high-water, not from a hard-coded maximum. A reusable work bank sized for a
larger high-water remains safe: the surplus becomes additional dense-node
capacity, while the separate descriptor bank still bounds admission. The work
shape supports several roots per source, but this producer slice currently
enumerates exactly root key one for each admitted direct textarea.

## Observation and storage authority

Capture is a synchronous UI-owner operation. One outer
`UTUI-RESOLVED-OBSERVE` holds UIDL-TUI and UIDL state across all of the
following work:

1. validate and pairwise-separate all five caller banks;
2. check every bank against UCSN, `USCOL`, UIDL-TUI, every canonical textarea,
   and every genuine caller-mounted textarea, including hidden widgets;
3. clear scratch;
4. walk the resolved tree once;
5. exact-measure and exact-copy each supported widget through the current
   visitor seam;
6. deep-validate each native entry exactly once; and
7. emit the pointer-free canonical descriptor stream.

The public visitor operation retains its standalone all-source preflight. UCSN
uses a private preflighted copy entry only while the outer all-bank proof is
live, avoiding a complete widget-pool rescan for every captured root. No widget
pointer leaves UIDL-TUI, and there is no applet callback or mounted-provider
registry.

The five-bank range proof also uses UIDL-TUI's private already-observed storage
queries. It therefore checks the same authoritative UIDL, state, canonical,
and mounted-widget spans without recursively opening a second semantic
observation.

The caller invokes snapshot capture after the ordinary paint whose state it is
freezing. Capture refreshes UIDL-TUI's fixed proxy region and authoritative
focus immediately before reading the widget, but it does not run draw-time
scroll adjustment or paint a second scene.

## Current boundary and next seam

This slice proves direct canonical UIDL textareas, including exact flat and
gap-buffer content, selection/focus state, geometry translation, caller
capacity, alias rejection, and frozen identity order. It deliberately excludes
caller-mounted replacements from semantic admission. Protecting their storage
does not make them semantic providers.

It also does not capture Pad's nested main editor. Pad mounts a composite panel
whose canonical editor is reached inside the ordinary panel draw boundary, not
as the direct widget of a UIDL `<textarea>`. The next required lower-layer step
is generic mounted/draw-boundary composition that can discover canonical
widgets and residual draw work without a Pad-specific adapter. Tabs and grids
then enter through the same generic source/run mechanism. Until that seam and
the upper claim/residual lifecycle are complete, this module is snapshot
plumbing rather than evidence of a functional rich-terminal Desk.
