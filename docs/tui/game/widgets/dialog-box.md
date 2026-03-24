# akashic/tui/game/widgets/dialog-box.f — RPG Dialog Box Widget

**Layer:** 7 (TUI Game Widgets)
**Lines:** 381
**Prefix:** `DBOX-` (public), `_DBOX-` (internal)
**Provider:** `ak-tui-gw-dialog-box`
**Dependencies:** `widget.f`, `draw.f`, `box.f`, `keys.f`, `region.f`

## Overview

An RPG-style dialog box with typewriter-effect text reveal, optional
speaker name, portrait canvas, and branching choices.  Rendered at the
bottom of the game view.

Text is revealed character by character via `DBOX-TICK`.  The player
can press **ENTER** or **SPACE** to skip to full reveal.  Once the
text is fully revealed, arrow keys navigate branching choices and
**ENTER** confirms a selection.

### Portrait

An optional Braille canvas sub-widget may be placed to the left of
the text area via `DBOX-PORTRAIT!`.  It is freed automatically by
`DBOX-FREE`.

---

## Descriptor Layout (152 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type = `WDG-T-DIALOG-BOX` (20) |
| +40 | speaker-a | addr | Speaker name string address |
| +48 | speaker-u | u | Speaker name string length |
| +56 | text-a | addr | Full message text address |
| +64 | text-u | u | Full message text length |
| +72 | reveal-pos | u | Characters revealed so far |
| +80 | speed | u | Characters per tick (default 1) |
| +88 | choices-a | addr | Choice labels array (addr+len pairs) or 0 |
| +96 | choice-count | u | Number of choices |
| +104 | choice-sel | u | Currently highlighted choice (0-based) |
| +112 | result | n | −1 = open, ≥ 0 = chosen index |
| +120 | portrait | addr | Canvas widget address (or 0) |
| +128 | flags2 | u | Internal flags |
| +136 | on-done-xt | xt | Callback `( choice widget -- )` or 0 |
| +144 | reserved | — | Padding |

---

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `DBOX-NEW` | `( rgn -- widget )` | Allocate 152-byte descriptor; reveal-pos = 0, speed = 1, result = −1 |
| `DBOX-FREE` | `( widget -- )` | Free portrait (if any) and descriptor |

### Text Setup

| Word | Stack | Description |
|------|-------|-------------|
| `DBOX-SET` | `( speaker-a u text-a u widget -- )` | Set speaker + message; resets reveal-pos and result to defaults |
| `DBOX-RESET` | `( widget -- )` | Reset reveal-pos to 0, result to −1. Does **not** clear choices |

### Typewriter

| Word | Stack | Description |
|------|-------|-------------|
| `DBOX-TICK` | `( widget -- )` | Advance reveal by `speed` characters |
| `DBOX-SKIP` | `( widget -- )` | Jump reveal to end of text |
| `DBOX-SPEED!` | `( n widget -- )` | Set characters-per-tick |
| `DBOX-REVEALED?` | `( widget -- flag )` | True if all text is revealed |

### Choices

| Word | Stack | Description |
|------|-------|-------------|
| `DBOX-CHOICES!` | `( labels count widget -- )` | Set choice labels (array of addr+len pairs) |
| `DBOX-RESULT` | `( widget -- n )` | Return selected choice (−1 if still open) |
| `DBOX-DONE?` | `( widget -- flag )` | True if result ≥ 0 |

### Callbacks

| Word | Stack | Description |
|------|-------|-------------|
| `DBOX-ON-DONE` | `( xt widget -- )` | Register callback `( choice widget -- )` fired on confirm |

### Portrait

| Word | Stack | Description |
|------|-------|-------------|
| `DBOX-PORTRAIT!` | `( canvas widget -- )` | Attach a Braille canvas sub-widget |

### Keyboard Handling

| Key | Action |
|-----|--------|
| ENTER | If not fully revealed → skip. If revealed with choices → confirm selection |
| SPACE | Same as ENTER |
| ↑ | Move choice highlight up |
| ↓ | Move choice highlight down |

---

## Guard

All public mutating words are wrapped through a concurrency guard
(`_dbox-guard`) using `WITH-GUARD`.

---

## Usage

```forth
REQUIRE tui/game/widgets/dialog-box.f

my-region DBOX-NEW CONSTANT dlg

\ Set dialog text
S" Elder" S" The ancient forest calls..." dlg DBOX-SET

\ Advance typewriter 3 ticks
dlg DBOX-TICK  dlg DBOX-TICK  dlg DBOX-TICK

\ Present choices
CREATE my-choices
  S" Accept quest"  , ,
  S" Decline"       , ,
my-choices 2 dlg DBOX-CHOICES!

\ After player confirms
dlg DBOX-RESULT  ( -- 0 or 1 )

dlg DBOX-FREE
```
