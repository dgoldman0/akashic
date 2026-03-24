# akashic/tui/game/widgets/inventory.f — Grid-Based Inventory Widget

**Layer:** 7 (TUI Game Widgets)
**Lines:** 386
**Prefix:** `INV-` (public), `_INV-` (internal)
**Provider:** `ak-tui-gw-inventory`
**Dependencies:** `widget.f`, `draw.f`, `box.f`, `keys.f`

## Overview

A focusable grid-based item screen.  Items occupy slots displayed in
a `cols × rows` grid.  The player navigates with arrow keys and
triggers actions via configurable callbacks (select, use, drop).
Supports scrolling when the item count exceeds the visible grid.

Each slot stores an icon codepoint, foreground colour, and an
item-name string.  An optional parallel quantity array provides
per-slot numeric quantities (stack counts, ammo, etc.).

---

## Slot Entry (32 bytes, 4 cells)

| Offset | Field | Description |
|--------|-------|-------------|
| +0  | icon-cp | Codepoint (0 = empty slot) |
| +8  | icon-fg | Foreground colour |
| +16 | name-a  | Item name string address |
| +24 | name-u  | Item name string length |

---

## Descriptor Layout (152 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type = `WDG-T-INVENTORY` (22) |
| +40 | cols | u | Grid columns |
| +48 | rows | u | Grid rows (visible) |
| +56 | slots | addr | Slot array (separately allocated) |
| +64 | slot-max | u | Maximum number of slots |
| +72 | slot-count | u | Current number of slots used |
| +80 | cursor | u | Current cursor index (0-based) |
| +88 | scroll-top | u | First visible row × cols |
| +96 | on-select-xt | xt | Callback `( index widget -- )` or 0 |
| +104 | on-use-xt | xt | Callback `( index widget -- )` or 0 |
| +112 | on-drop-xt | xt | Callback `( index widget -- )` or 0 |
| +120 | qty-array | addr | Quantity array (1 cell per slot) or 0 |
| +128 | show-qty | flag | Display quantities |
| +136 | title-a | addr | Title string address |
| +144 | title-u | u | Title string length |

---

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `INV-NEW` | `( rgn cols rows max-slots -- widget )` | Allocate descriptor, slot array, and quantity array |
| `INV-FREE` | `( widget -- )` | Free slot array, quantity array, and descriptor |

### Item Management

| Word | Stack | Description |
|------|-------|-------------|
| `INV-ADD` | `( cp fg name-a name-u widget -- index )` | Append item; returns index or −1 if full |
| `INV-REMOVE` | `( index widget -- )` | Clear slot and zero quantity |
| `INV-CLEAR` | `( widget -- )` | Zero all slots, quantities, and reset cursor |
| `INV-COUNT` | `( widget -- n )` | Current number of items |

### Quantities

| Word | Stack | Description |
|------|-------|-------------|
| `INV-QTY!` | `( qty index widget -- )` | Set quantity for a slot |
| `INV-QTY@` | `( index widget -- qty )` | Read quantity for a slot |

### Display

| Word | Stack | Description |
|------|-------|-------------|
| `INV-TITLE!` | `( addr len widget -- )` | Set the title string |

### Cursor

| Word | Stack | Description |
|------|-------|-------------|
| `INV-SELECTED` | `( widget -- index )` | Return current cursor position |

### Callbacks

| Word | Stack | Description |
|------|-------|-------------|
| `INV-ON-SELECT` | `( xt widget -- )` | Register select callback `( index widget -- )` |
| `INV-ON-USE` | `( xt widget -- )` | Register use callback `( index widget -- )` |
| `INV-ON-DROP` | `( xt widget -- )` | Register drop callback `( index widget -- )` |

### Keyboard Handling

| Key | Action |
|-----|--------|
| ← | Move cursor left (clamped at 0) |
| → | Move cursor right (clamped at count − 1) |
| ↑ | Move cursor up one row |
| ↓ | Move cursor down one row |
| ENTER | Fire select callback |
| u | Fire use callback |
| d | Fire drop callback |

---

## Guard

All public mutating words are wrapped through a concurrency guard
(`_inv-guard`) using `WITH-GUARD`.

---

## Usage

```forth
REQUIRE tui/game/widgets/inventory.f

\ Create a 4×3 grid, max 16 items
my-region 4 3 16 INV-NEW CONSTANT inv

\ Add items
0x2694 7 S" Sword"  inv INV-ADD CONSTANT sword-idx
0x1F6E1 4 S" Shield" inv INV-ADD CONSTANT shield-idx

\ Set quantities
5 sword-idx inv INV-QTY!

\ Register callbacks
:noname ( idx wdg -- ) 2DROP ." Selected!" ; inv INV-ON-SELECT

\ Title
S" Backpack" inv INV-TITLE!

\ Cleanup
inv INV-FREE
```
