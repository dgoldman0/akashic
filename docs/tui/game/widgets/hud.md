# akashic/tui/game/widgets/hud.f — HUD Overlay Widget

**Layer:** 7 (TUI Game Widgets)
**Lines:** 345
**Prefix:** `HUD-` (public), `_HUD-` (internal)
**Provider:** `ak-tui-gw-hud`
**Dependencies:** `widget.f`, `draw.f`

## Overview

A transparent overlay widget rendered atop the Game-View.  Displays
status indicators arranged in a vertical slot list: progress bars,
text labels, and single-glyph icons.  Non-focusable — does not
consume keyboard events.

### Slot Types

| Constant | Value | Description |
|----------|-------|-------------|
| `HUD-SLOT-EMPTY` | 0 | Unused / cleared slot |
| `HUD-SLOT-BAR`   | 1 | Progress bar (health, mana, XP, …) |
| `HUD-SLOT-TEXT`   | 2 | Dynamic text label |
| `HUD-SLOT-ICON`   | 3 | Single Unicode glyph with colour |

### Slot Entry (56 bytes, 7 cells)

| Offset | Field | Description |
|--------|-------|-------------|
| +0  | type    | Slot type (0–3) |
| +8  | label-a | Label string address |
| +16 | label-u | Label string length |
| +24 | val     | Bar: current value / Icon: codepoint |
| +32 | max     | Bar: maximum value / Icon: fg colour |
| +40 | fg      | Bar fill colour |
| +48 | bg      | Bar empty colour |

---

## Descriptor Layout (40 + N bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type = `WDG-T-HUD` (19) |
| +40 | slot-max | u | Maximum slots (`max-slots` arg) |
| +48 | slot-count | u | Slots currently used |
| +56… | slots | inline | `max-slots × 56` bytes, slot array |

---

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `HUD-NEW` | `( rgn max-slots -- widget )` | Allocate HUD descriptor and inline slot storage |
| `HUD-FREE` | `( widget -- )` | Free the descriptor |

### Bar Slots

| Word | Stack | Description |
|------|-------|-------------|
| `HUD-ADD-BAR` | `( hud label-a label-u max fg bg -- id )` | Append a progress bar slot |
| `HUD-SET-BAR` | `( hud slot-id current -- )` | Update the bar's current value |

### Text Slots

| Word | Stack | Description |
|------|-------|-------------|
| `HUD-ADD-TEXT` | `( hud label-a label-u -- id )` | Append a text label slot |
| `HUD-SET-TEXT` | `( hud slot-id addr len -- )` | Replace the label text |

### Icon Slots

| Word | Stack | Description |
|------|-------|-------------|
| `HUD-ADD-ICON` | `( hud cp fg -- id )` | Append an icon slot |
| `HUD-SET-ICON` | `( hud slot-id cp -- )` | Change the icon codepoint |

### General

| Word | Stack | Description |
|------|-------|-------------|
| `HUD-CLEAR` | `( hud -- )` | Zero all slots and reset count |

---

## Guard

All public mutating words are wrapped through a concurrency guard
(`_hud-guard`) using `WITH-GUARD`, serialising access from
multiple tasks.

---

## Usage

```forth
REQUIRE tui/game/widgets/hud.f

\ Create a HUD with room for 4 slots
my-region 4 HUD-NEW  CONSTANT my-hud

\ Add a health bar (max 100, green fill, grey empty)
my-hud S" HP" 100 2 8 HUD-ADD-BAR  CONSTANT hp-slot
my-hud hp-slot 73 HUD-SET-BAR    \ 73 / 100

\ Add a text label
my-hud S" Level 5" HUD-ADD-TEXT  DROP

\ Add a coin icon
my-hud 0x25CF 3 HUD-ADD-ICON  DROP

\ Later: free
my-hud HUD-FREE
```
