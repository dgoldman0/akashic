# akashic/tui/widgets/split.f — Split Pane Widget

**Layer:** 7  
**Lines:** 256  
**Prefix:** `SPL-` (public), `_SPL-` (internal)  
**Provider:** `akashic-tui-split`  
**Dependencies:** `widget.f`, `region.f`, `draw.f`

## Overview

Divides a region into two sub-regions (pane A and pane B) separated
by a one-character-wide divider.  The split can be horizontal
(top / bottom) or vertical (left / right).

The ratio controls how space is allocated: pane A gets `ratio`
rows (horizontal) or columns (vertical) of the available space
(total minus the 1-cell divider).  Pane B gets the rest.  A ratio
of 0 or one exceeding the available space is clamped.

The widget itself does **not** draw child widgets — that is the
caller's responsibility.  `SPL-DRAW` only renders the divider line
and marks the widget clean.  After a resize or ratio change, call
`SPL-RECOMPUTE` to rebuild the pane regions.

## Descriptor Layout (80 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+32 | header | widget header | Standard 5-cell header, type=WDG-T-SPLIT |
| +40 | mode | constant | `SPL-H` (horizontal) or `SPL-V` (vertical) |
| +48 | ratio | u | Size of pane A in rows or columns |
| +56 | pane-a | region | Sub-region for pane A |
| +64 | pane-b | region | Sub-region for pane B |
| +72 | divider | codepoint | Character for the divider line |

## API Reference

### Constants

| Word | Value | Description |
|------|-------|-------------|
| `SPL-H` | 0 | Horizontal split: A on top, B on bottom |
| `SPL-V` | 1 | Vertical split: A on left, B on right |

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `SPL-NEW` | `( rgn mode ratio -- widget )` | Create split pane; computes initial sub-regions |
| `SPL-FREE` | `( widget -- )` | Free both pane regions and descriptor |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `SPL-PANE-A` | `( widget -- rgn )` | Get pane A region |
| `SPL-PANE-B` | `( widget -- rgn )` | Get pane B region |

### Mutators

| Word | Stack | Description |
|------|-------|-------------|
| `SPL-SET-RATIO` | `( widget n -- )` | Adjust split position; recomputes panes, marks dirty |
| `SPL-RECOMPUTE` | `( widget -- )` | Rebuild pane regions from current ratio and parent geometry |

### Key Handling (via `WDG-HANDLE`)

The split pane does not consume any keys — `_SPL-HANDLE` always
returns 0.  Child widgets should be given focus independently.

## UIDL-TUI Integration

When a `<split>` element appears in a UIDL document, the UIDL-TUI
backend uses a pure inline adapter — no `SPL-NEW` widget is created.
The adapter reads the `ratio=` attribute (default 50) and draws a
vertical divider (`│`, U+2502) at `col + w * ratio / 100`.  Child
panes are laid out by the standard stack layout.

See [uidl-tui.md](../uidl-tui.md) for the full backend design.

## Design Notes

- **Default dividers.** Horizontal splits use `─` (U+2500); vertical
  splits use `│` (U+2502).  The character is stored in the descriptor
  and can be overridden by writing to offset +72.
- **Sub-region lifecycle.** `SPL-RECOMPUTE` creates new sub-regions
  via `RGN-SUB` each time.  `SPL-FREE` releases both pane regions.
- When `GUARDED` is defined, every public word is wrapped with
  `WITH-GUARD` for concurrency safety.
