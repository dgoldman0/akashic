# Canonical Text Grid Widget

**Prefix:** `TGRID-` (public), `_TGRID-` (internal)  
**Provider:** `akashic-tui-text-grid`

`TGRID` presents one logical, renderer-neutral text grid through the ordinary
widget lifecycle. Its model is a caller-owned, deeply validated
`USCOL-F-TEXT-GRID` entry. CELL drawing, directional selection, and generic
rich observation all read that exact entry; there is no renderer callback or
second item schema.

## Ownership

The caller owns the model bytes and keeps the bound entry stable until another
successful bind or widget destruction. `TGRID-BIND` validates the complete
entry with caller-provided work and summary storage before atomically replacing
the prior binding. It requires read-only grid content, a local `(0,0)` root
whose size matches the widget region, zero grid anchor/offsets, and a primary
key that is absent or names an available data item.

The widget owns only its 96-byte descriptor. The descriptor contains the
standard 40-byte widget header, borrowed model address and exact byte count,
an optional `( item-key widget -- )` selection callback, a nonzero
allocation-lifetime instance token, and an optional `( steps widget -- )`
scroll callback, a right text inset, and a full-rectangle selection flag.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `TGRID-NEW` | `( region -- widget )` | Allocate an initially unbound widget |
| `TGRID-BIND` | `( entry bytes work-a work-u summary widget -- status )` | Deep-validate and atomically bind one grid |
| `TGRID-SELECTED@` | `( widget -- item-key )` | Read the primary item key, or zero |
| `TGRID-SELECT!` | `( item-key widget -- status )` | Select an available data item and invoke the callback |
| `TGRID-ON-SELECT` | `( xt widget -- )` | Install the ordinary selection callback |
| `TGRID-ON-SCROLL` | `( xt widget -- )` | Install the wheel callback |
| `TGRID-CELL-INSET!` | `( right-inset widget -- )` | Reserve trailing cells in each data item's CELL text area; initially zero |
| `TGRID-FILL-SELECTION!` | `( flag widget -- )` | Reverse the selected item's full CELL rectangle; initially false |
| `TGRID-INSTANCE@` | `( widget -- token )` | Read the allocation-lifetime identity |
| `TGRID-TEXT-GRID-MEASURE` | `( root-key builder widget -- bytes status )` | Measure the exact native entry |
| `TGRID-TEXT-GRID-CAPTURE` | `( root-key dst cap builder widget -- bytes status )` | Copy the entry and patch only the copied root identity, geometry, and state |
| `TGRID-TEXT-GRID-STORAGE-DISJOINT?` | `( address bytes widget -- flag )` | Reject aliases of live widget, region, model, or module storage |
| `TGRID-FREE` | `( widget -- )` | Free the descriptor, never the borrowed model |

The native family ABI and item layout are unchanged. These are the grid roles:

| Role | Value | Data item | CELL text alignment |
|---|---|---|---|
| `USCOL-ROLE-CONTENT` | 1 | Yes | Shared paragraph alignment |
| `USCOL-ROLE-ROW-HEADER` | 2 | No | Shared paragraph alignment, bold |
| `USCOL-ROLE-COLUMN-HEADER` | 3 | No | Shared paragraph alignment, bold |
| `USCOL-ROLE-NUMBER` | 4 | Yes | Right, with at least one trailing cell |
| `USCOL-ROLE-FORMULA` | 5 | Yes | Right, with at least one trailing cell |
| `USCOL-ROLE-ERROR` | 6 | Yes | Left |

`USCOL-GRID-DATA-ROLE? ( role -- flag )` recognizes roles 1, 4, 5, and 6;
`USCOL-GRID-ROLE? ( role -- flag )` recognizes all six. `TEXT_AREA` remains
restricted to `CONTENT`. Formula items contain caller-provided display text;
the widget does not evaluate expressions. Capture preserves each role and the
complete UTF-8 text, independent of CELL clipping.
`USCOL-TEXT-GRID-TYPED? ( validated-grid-entry -- flag )` scans an already
deeply validated grid for roles 4–6, for capability decisions over frozen
entries. Its caller must validate the entry before invoking it.

Logical item rectangles are partitioned across the current physical widget
region for CELL drawing. Each item's text is laid out as one paragraph by
the shared text rules and clipped to its rectangle by cells: right-to-left
content and headers are set against the rectangle's right edge, and a wide
character the edge cuts shows blanks. Numeric and formula text is right-aligned in the width
remaining after the greater of one trailing cell or the configured inset.
Error text starts at the left edge. The configured inset applies to all data
roles, leaves headers unchanged, and never changes the model or pointer hit
rectangles. If the inset consumes the text width, no text is painted.

Only header roles are bold; `CURRENT`, `UNAVAILABLE`, and
primary state map to underline, dim, and reverse attributes. Arrow navigation
uses available data coordinates. Full-rectangle selection includes blank text,
the trailing inset, and every physical row in the item; the default highlights
only painted glyphs, preserving existing `CONTENT` grids such as Daybook.
At an edge the event remains unconsumed so
a composed owner can apply its normal higher-level behavior, such as changing
the displayed month.

A primary press selects the available data item drawn under it, mapped
back through the same partition the CELL draw uses. `KEY-MOUSE-TEXT-PLACE`
selects the item named by `KEY-MOUSE-TEXT-KEY`, a position a rich renderer
took from its own layout. Other pointer events, and presses on headers,
unavailable items, or empty cells, are not consumed.

The grid cannot scroll itself: its caller builds the model and decides which
rows it shows, as Daybook decides which month its calendar shows. A wheel
step over a bound grid therefore calls the scroll callback with signed steps,
negative for up and positive for down, and the caller moves its own content.
A rich renderer's `SCROLL` event on the grid arrives as the same wheel steps.
Without a callback the wheel is not consumed.
