# akashic/tui/widgets/tabs.f — Tabbed Panel Widget

**Layer:** 4B  
**Prefix:** `TAB-` (public), `_TAB-` (internal)  
**Provider:** `akashic-tui-tabs`  
**Dependencies:** `widget.f`, `draw.f`, `box.f`, `region.f`, `keys.f`,
`semantic-collections.f`, `memory-span.f`

## Overview

A row of tab headers with a content area below.  Each tab has a label
and a child region.  Switching tabs activates the corresponding content
region.

The widget uses the top row (row 0) of its region for the tab header
bar, row 1 for an underline, and rows 2..h-1 for tab content regions
(created automatically by `TAB-ADD`).

## Descriptor Layout (104 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=WDG-T-TABS |
| +40 | tabs | address | Pointer to tab entry array |
| +48 | count | u | Current number of tabs |
| +56 | active | u | Currently active tab index |
| +64 | max-tabs | u | Caller-selected allocated capacity |
| +72 | switch-xt | xt or 0 | Tab-switched callback `( index widget -- )` |
| +80 | instance | u | Stable nonzero allocation-lifetime identity |
| +88 | next-key | u | Last stable per-widget tab key issued |
| +96 | entry-bytes | u | Exact allocated entry-array byte count |

## Tab Entry Layout (32 bytes each)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | label-a | address | Tab label string address |
| +8 | label-u | u | Tab label string length |
| +16 | content-rgn | region | Content sub-region for this tab |
| +24 | key | u | Stable nonzero identity for this tab's lifetime |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-NEW-CAP` | `( rgn max-tabs -- widget )` | Create an empty tab container with exact caller-selected capacity |
| `TAB-NEW` | `( rgn -- widget )` | Convenience constructor using the default capacity of 8 |
| `TAB-FREE` | `( widget -- )` | Free entry array and descriptor |

### Adding / Removing Tabs

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-ADD` | `( label-a label-u widget -- content-rgn )` | Add tab; returns content region |
| `TAB-REMOVE` | `( index widget -- )` | Remove tab at index; shifts entries, adjusts active |

### Selection

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-SELECT` | `( index widget -- )` | Switch to tab at index |
| `TAB-ACTIVE` | `( widget -- index )` | Get active tab index |

### Labels

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-LABEL!` | `( label-a label-u index widget -- )` | Update label of existing tab |
| `TAB-LABEL@` | `( index widget -- label-a label-u )` | Get label string of tab |

### Content

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-CONTENT` | `( index widget -- rgn )` | Get content region for tab |
| `TAB-COUNT` | `( widget -- n )` | Get number of tabs |
| `TAB-CAPACITY` | `( widget -- n )` | Get allocated entry capacity |
| `TAB-KEY@` | `( index widget -- key )` | Get the stable lifetime key for an entry |
| `TAB-INSTANCE@` | `( widget -- token )` | Get the widget allocation-lifetime identity |

### Callback

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-ON-SWITCH` | `( xt widget -- )` | Set tab-switched callback |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Left | Switch to previous tab |
| Right | Switch to next tab |

The ordinary handler also accepts a left-button mouse event on the header.
`TAB-HIT-INDEX ( absolute-row absolute-column widget -- index flag )` performs
the same geometry calculation independently for callers that need exact hit
resolution.

## Renderer-neutral observation

`TAB-TABSET-MEASURE` and `TAB-TABSET-CAPTURE` expose a caller-bounded canonical
graph consisting of one `TABSET` root and every live `TAB` child. The snapshot
uses the same header geometry, label pointers, selected index, stable widget
instance, and entry keys as ordinary drawing and input. Capture does not own a
retained renderer, know an applet, or apply a second collection limit; a too
small destination refuses the complete suffix.

The root covers only the one- or two-row painted header rather than the content
panel below it. Child labels are borrowed while measuring and copied into the
caller-supplied output bank during capture. Storage-disjoint checks reject any
destination or builder span that aliases the live descriptor, allocated entry
array, labels, regions, or module scratch.

## UIDL-TUI Integration

An authored `<tabs>` element in a UIDL document still uses UIDL-TUI's inline
adapter rather than constructing a `TAB-NEW` widget. Its resolved immediate
`<tab>` children are nevertheless captured as the same renderer-neutral
`TABSET`/`TAB` graph. This is distinct from an ordinary canonical `TAB` widget
mounted into a UIDL region: mounted widgets are drawn through `WDG-DRAW`, and
the generic semantic collector observes their canonical collection source at
that same draw boundary. The inline adapter uses a minimal 8-byte state block
(one cell: active tab index, 0-based) stored in the sidecar's `wptr` cell (+48).

| Phase | Adapter | Behaviour |
|-------|---------|-----------|  
| Render | `_UTUI-RENDER-TABS` | Fills bg, draws `label=` per child tab with reverse-highlight on active, underline on row 1 |
| Event | `_UTUI-H-TABS` | Left/Right keys switch active index |
| Layout | `_UTUI-LAYOUT-TABS` | 2-row header; active tab child gets content area (row+2, col, w, h-2); inactive children get 0×0 dimensions |

Inactive tab children are given 0×0 sidecar dimensions rather than
having their VIS flag cleared, because the layout recursion would
otherwise re-mark them visible.

Lifecycle: `ALLOCATE` 8 bytes at `_UTUI-MATERIALIZE`, `FREE` at
`_UTUI-DEMATERIALIZE`.

See [uidl-tui.md](../uidl-tui.md) for the full backend design.

## Design Notes

- **VARIABLE-based draw.** `_TAB-DRAW` stores widget, region width,
  current entry, and column in VARIABLEs to avoid deep stack
  manipulation and nested-loop issues.
- **No J word.** KDOS Forth's `J` crashes in nested DO loops.  Column
  accumulation is done via a separate helper word `_TAB-COL-ACC`
  with its own `?DO ... LOOP`.
- **Content regions are sub-regions.** `TAB-ADD` calls `RGN-SUB` to
  create a child region occupying rows 2..h-1 of the widget's parent
  region.
- **Active tab highlight.** The active tab's label is drawn with
  `CELL-A-REVERSE` attribute; inactive tabs use normal attributes.
- **Tab separator.** A vertical line (`│`, U+2502) separates adjacent
  tab labels; an underline (`─`, U+2500) runs across row 1.
- **TAB-REMOVE active adjustment.** When removing a tab before the active one,
  `active` is decremented so it continues to track the same content. When
  removing the active tab itself (or when active overshoots after the removal),
  it is clamped to `count-1`. Callers with a sparse backing store map that
  resulting visual ordinal back to their own identity; they must not replace
  it with an unrelated sparse-slot policy.
- **Label pointers are not copied.** `TAB-ADD` and `TAB-LABEL!` store
  the label address directly; they do **not** copy the string.
  Callers must ensure the label storage outlives the tab (e.g.
  dictionary strings via `CREATE`, not transient `S"` buffers).
