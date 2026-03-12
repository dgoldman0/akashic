# akashic/tui/list.f — Scrollable List Widget

**Layer:** 4B  
**Lines:** 280  
**Prefix:** `LST-` (public), `_LST-` (internal)  
**Provider:** `akashic-tui-list`  
**Dependencies:** `widget.f`, `draw.f`, `keys.f`

## Overview

A vertically scrollable list of selectable items.  Supports keyboard
navigation (up/down, page-up/page-down, home/end), selection highlight
via reverse video, a selection-changed callback, and programmatic item
replacement.

Items are an external array of `( addr len )` pairs — 2 cells (16 bytes)
per item.  The widget does not copy strings; the caller owns the data.

## Descriptor Layout (88 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=WDG-T-LIST |
| +40 | items | address | Pointer to item array (2 cells per item) |
| +48 | count | u | Number of items |
| +56 | selected | n | Currently selected index (0-based) |
| +64 | scroll-top | u | Index of first visible item |
| +72 | select-xt | xt or 0 | Selection callback `( index widget -- )` |
| +80 | item-xt | xt or 0 | Custom item renderer `( index widget -- )` |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `LST-NEW` | `( rgn items count -- widget )` | Create list; selection starts at 0 |
| `LST-FREE` | `( widget -- )` | Free the descriptor |

### Selection

| Word | Stack | Description |
|------|-------|-------------|
| `LST-SELECT` | `( index widget -- )` | Set selection; auto-scrolls to keep visible |
| `LST-SELECTED` | `( widget -- index )` | Get current selection index |

### Content

| Word | Stack | Description |
|------|-------|-------------|
| `LST-SET-ITEMS` | `( items count widget -- )` | Replace item array; resets selection to 0 |

### Callbacks

| Word | Stack | Description |
|------|-------|-------------|
| `LST-ON-SELECT` | `( xt widget -- )` | Set selection callback `( index widget -- )` |
| `LST-SET-RENDER` | `( xt widget -- )` | Set custom item renderer `( index widget -- )` |

### Scrolling

| Word | Stack | Description |
|------|-------|-------------|
| `LST-SCROLL-TO` | `( index widget -- )` | Ensure item at index is visible |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Up | Move selection up one item |
| Down | Move selection down one item |
| Page Up | Move selection up by region height |
| Page Down | Move selection down by region height |
| Home | Select first item |
| End | Select last item |

## Design Notes

- **VARIABLE-based handler.** `_LST-HANDLE` stores the widget in a
  VARIABLE (`_LST-HND-W`) to avoid deep stack gymnastics inside
  the CASE dispatch.  KDOS Forth's `J` word is unreliable, so nested
  DO loops with outer-index access use VARIABLEs instead.
- **Auto-scroll.** `_LST-ENSURE-VISIBLE` adjusts `scroll-top` so the
  selected item is always within the visible region.
- **Custom renderer.** If `item-xt` is non-zero, it's called instead
  of the default `DRW-TEXT` draw for each visible item.
