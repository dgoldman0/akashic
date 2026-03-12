# akashic/tui/menu.f — Menu Bar & Dropdown Menus

**Layer:** 4C  
**Lines:** ~280  
**Prefix:** `MNU-` (public), `_MNU-` (internal)  
**Provider:** `akashic-tui-menu`  
**Dependencies:** `widget.f`, `draw.f`, `box.f`, `region.f`

## Overview

Horizontal menu bar with dropdown menus.  Each top-level menu has a
label displayed in the bar (row 0 of the widget region) and a list of
items shown in a dropdown box when that menu is opened.

Items support action callbacks, separator lines, disabled state, and a
checked indicator.  Navigation uses arrow keys; Escape closes the
dropdown.

The widget's region should be tall enough for the bar row plus the
tallest dropdown (item-count + 2 for the box border).

## Menu Item Descriptor (32 bytes, 4 cells)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | label-a | address | Item label string address |
| +8 | label-u | u | Item label string length |
| +16 | action-xt | xt | Callback `( -- )` invoked on selection |
| +24 | flags | u | Bitfield: `MNU-F-SEPARATOR`(1), `MNU-F-DISABLED`(2), `MNU-F-CHECKED`(4) |

## Top-Level Menu Entry (32 bytes, 4 cells)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | label-a | address | Menu title string address |
| +8 | label-u | u | Menu title string length |
| +16 | items-addr | address | Address of item descriptor array |
| +24 | item-count | u | Number of items in this menu |

## Menu Descriptor (80 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=WDG-T-MENU |
| +40 | menus | address | Pointer to top-level menu array |
| +48 | menu-count | u | Number of top-level menus |
| +56 | active-menu | n | Currently open menu index (-1 = none) |
| +64 | active-item | u | Currently highlighted item in open menu |
| +72 | bar-region | region | Region for the menu bar row |

## Flag Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MNU-F-SEPARATOR` | 1 | Item is a horizontal separator line |
| `MNU-F-DISABLED` | 2 | Item is greyed out and not selectable |
| `MNU-F-CHECKED` | 4 | Item displays a ✓ check mark |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `MNU-NEW` | `( rgn menus count -- widget )` | Create menu bar widget |
| `MNU-FREE` | `( widget -- )` | Free descriptor (not the menu/item arrays) |

### Open / Close

| Word | Stack | Description |
|------|-------|-------------|
| `MNU-OPEN` | `( index widget -- )` | Open dropdown for menu at index |
| `MNU-CLOSE` | `( widget -- )` | Close any open dropdown |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `MNU-ACTIVE` | `( widget -- n )` | Currently open menu index (-1 = none) |
| `MNU-ACTIVE-ITEM` | `( widget -- u )` | Currently highlighted item index |

### Item Manipulation

| Word | Stack | Description |
|------|-------|-------------|
| `MNU-ITEM-ENABLE` | `( widget menu# item# -- )` | Clear disabled flag on item |
| `MNU-ITEM-DISABLE` | `( widget menu# item# -- )` | Set disabled flag on item |
| `MNU-ITEM-CHECK` | `( widget menu# item# flag -- )` | Set or clear checked flag |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Down | Open first menu (when closed) or move to next item |
| Up | Move to previous item |
| Left | Switch to previous menu |
| Right | Switch to next menu |
| Enter | Fire action callback and close menu |
| Escape | Close dropdown |

Separator and disabled items are automatically skipped during
Up/Down navigation.

## Drawing Behaviour

The bar renders each top-level menu label with 1-character padding
on each side.  The active (open) menu label is drawn in reverse
video.

The dropdown is drawn as a `BOX-SINGLE` border starting at row 1,
aligned to the column of the active menu label.  Items inside the
box show a `✓` prefix when checked, a `─` line for separators, and
dimmed text for disabled items.  The currently highlighted item is
drawn in reverse video.

## Design Notes

- Menu and item descriptor arrays are **caller-allocated** — the
  widget stores pointers to them but does not own or free them.
- All draw and handle logic uses `VARIABLE`-based state to avoid
  deep stack manipulation (KDOS best practice).
- The `_MNU-SKIP-DISABLED-DOWN` / `_MNU-SKIP-DISABLED-UP` helpers
  ensure navigation never rests on a separator or disabled item.
