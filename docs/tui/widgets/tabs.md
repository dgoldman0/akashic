# akashic/tui/widgets/tabs.f — Tabbed Panel Widget

**Layer:** 4B  
**Lines:** 350  
**Prefix:** `TAB-` (public), `_TAB-` (internal)  
**Provider:** `akashic-tui-tabs`  
**Dependencies:** `widget.f`, `draw.f`, `box.f`, `region.f`, `keys.f`

## Overview

A row of tab headers with a content area below.  Each tab has a label
and a child region.  Switching tabs activates the corresponding content
region.

The widget uses the top row (row 0) of its region for the tab header
bar, row 1 for an underline, and rows 2..h-1 for tab content regions
(created automatically by `TAB-ADD`).

## Descriptor Layout (80 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=WDG-T-TABS |
| +40 | tabs | address | Pointer to tab entry array |
| +48 | count | u | Current number of tabs |
| +56 | active | u | Currently active tab index |
| +64 | max-tabs | u | Maximum number of tabs (default 8) |
| +72 | switch-xt | xt or 0 | Tab-switched callback `( index widget -- )` |

## Tab Entry Layout (24 bytes each)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | label-a | address | Tab label string address |
| +8 | label-u | u | Tab label string length |
| +16 | content-rgn | region | Content sub-region for this tab |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-NEW` | `( rgn -- widget )` | Create empty tab container |
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

### Callback

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-ON-SWITCH` | `( xt widget -- )` | Set tab-switched callback |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Left | Switch to previous tab |
| Right | Switch to next tab |

## UIDL-TUI Integration

When a `<tabs>` element appears in a UIDL document, the UIDL-TUI
backend does **not** create a `TAB-NEW` widget.  Instead it uses an
inline adapter with a minimal 8-byte state block (one cell: active
tab index, 0-based) stored in the sidecar's `wptr` cell (+48).

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
- **TAB-REMOVE active adjustment.** When removing a tab before the
  active one, `active` is decremented so it continues to track the
  same content.  When removing the active tab itself (or when active
  overshoots after the removal), it is clamped to `count-1`.
- **Label pointers are not copied.** `TAB-ADD` and `TAB-LABEL!` store
  the label address directly; they do **not** copy the string.
  Callers must ensure the label storage outlives the tab (e.g.
  dictionary strings via `CREATE`, not transient `S"` buffers).
