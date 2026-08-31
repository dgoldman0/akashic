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
key that is absent or names an available content item.

The widget owns only its 72-byte descriptor. The descriptor contains the
standard 40-byte widget header, borrowed model address and exact byte count,
an optional `( item-key widget -- )` selection callback, and a nonzero
allocation-lifetime instance token.

## Public API

| Word | Stack | Purpose |
|---|---|---|
| `TGRID-NEW` | `( region -- widget )` | Allocate an initially unbound widget |
| `TGRID-BIND` | `( entry bytes work-a work-u summary widget -- status )` | Deep-validate and atomically bind one grid |
| `TGRID-SELECTED@` | `( widget -- item-key )` | Read the primary item key, or zero |
| `TGRID-SELECT!` | `( item-key widget -- status )` | Select an available content item and invoke the callback |
| `TGRID-ON-SELECT` | `( xt widget -- )` | Install the ordinary selection callback |
| `TGRID-INSTANCE@` | `( widget -- token )` | Read the allocation-lifetime identity |
| `TGRID-TEXT-GRID-MEASURE` | `( root-key builder widget -- bytes status )` | Measure the exact native entry |
| `TGRID-TEXT-GRID-CAPTURE` | `( root-key dst cap builder widget -- bytes status )` | Copy the entry and patch only the copied root identity, geometry, and state |
| `TGRID-TEXT-GRID-STORAGE-DISJOINT?` | `( address bytes widget -- flag )` | Reject aliases of live widget, region, model, or module storage |
| `TGRID-FREE` | `( widget -- )` | Free the descriptor, never the borrowed model |

Logical item rectangles are partitioned across the current physical widget
region for CELL drawing. Header roles are bold; `CURRENT`, `UNAVAILABLE`, and
primary state map to underline, dim, and reverse attributes. Arrow navigation
uses available content coordinates. At an edge the event remains unconsumed so
a composed owner can apply its normal higher-level behavior, such as changing
the displayed month.
