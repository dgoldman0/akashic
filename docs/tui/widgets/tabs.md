# akashic/tui/widgets/tabs.f — Tabbed Panel Widget

**Layer:** 4B  
**Lines:** 282  
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

### Adding Tabs

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-ADD` | `( label-a label-u widget -- content-rgn )` | Add tab; returns content region |

### Selection

| Word | Stack | Description |
|------|-------|-------------|
| `TAB-SELECT` | `( index widget -- )` | Switch to tab at index |
| `TAB-ACTIVE` | `( widget -- index )` | Get active tab index |

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
