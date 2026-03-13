# akashic/tui/widgets/scroll.f — Scrollable Viewport Widget

**Layer:** 7  
**Lines:** 382  
**Prefix:** `SCRL-` (public), `_SCRL-` (internal)  
**Provider:** `akashic-tui-scroll`  
**Dependencies:** `widget.f`, `region.f`, `draw.f`, `keys.f`

## Overview

A scrollable viewport over a virtual content area that can be larger
than the visible region.  Content is rendered by a user-supplied
draw callback:

```
draw-xt signature:  ( offset-y offset-x viewport-rgn -- )
```

The callback receives the current scroll offset and the viewport
region (already activated for clipping).  It must draw its content
relative to the viewport — row 0 col 0 of its output corresponds to
`(offset-y, offset-x)` of the virtual area.

### Scroll Indicators

When content overflows the viewport, scroll-position indicators are
drawn on the right edge (vertical) and bottom edge (horizontal).
Each indicator consists of a track (`░` U+2591) and a thumb (`█`
U+2588), positioned proportionally.  Indicators can be toggled
with `SCRL-INDICATORS`.

## Descriptor Layout (88 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+32 | header | widget header | Standard 5-cell header, type=WDG-T-SCROLL |
| +40 | content-h | u | Total virtual content height (rows) |
| +48 | content-w | u | Total virtual content width (columns) |
| +56 | offset-y | u | Current vertical scroll offset |
| +64 | offset-x | u | Current horizontal scroll offset |
| +72 | draw-xt | xt | User draw callback |
| +80 | indicators | flag | TRUE to show scroll indicators (default: on) |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `SCRL-NEW` | `( rgn content-h content-w draw-xt -- widget )` | Create scrollable viewport |
| `SCRL-FREE` | `( widget -- )` | Free descriptor |

### Content Dimensions

| Word | Stack | Description |
|------|-------|-------------|
| `SCRL-SET-SIZE` | `( widget h w -- )` | Update content dimensions; re-clamps offsets |

### Scrolling

| Word | Stack | Description |
|------|-------|-------------|
| `SCRL-SCROLL-TO` | `( widget y x -- )` | Set scroll offset (clamped) |
| `SCRL-SCROLL-BY` | `( widget dy dx -- )` | Relative scroll (clamped) |
| `SCRL-ENSURE-VISIBLE` | `( widget row col -- )` | Adjust offsets so (row, col) is within viewport |
| `SCRL-OFFSET` | `( widget -- y x )` | Get current scroll offset |

### Display

| Word | Stack | Description |
|------|-------|-------------|
| `SCRL-INDICATORS` | `( widget flag -- )` | Enable/disable scroll indicators |

### Key Handling (via `WDG-HANDLE`)

| Key | Action |
|-----|--------|
| Up | Scroll up 1 row |
| Down | Scroll down 1 row |
| Left | Scroll left 1 column |
| Right | Scroll right 1 column |
| Page Up | Scroll up by half viewport height |
| Page Down | Scroll down by half viewport height |

## Design Notes

- **Offset clamping.** `_SCRL-CLAMP-Y` and `_SCRL-CLAMP-X` ensure
  offsets stay in `[0, max(0, content-dim - viewport-dim)]`.
- **Indicator glyphs.** Uses Unicode block elements for the scrollbar:
  - Track: `░` (U+2591)
  - Thumb: `█` (U+2588)
  - Arrow constants defined but not currently used in rendering.
- **Inline key handling.** `_SCRL-HANDLE` applies offset deltas
  directly rather than calling `SCRL-SCROLL-BY` (which is defined
  after the handler).
- When `GUARDED` is defined, every public word is wrapped with
  `WITH-GUARD` for concurrency safety.
