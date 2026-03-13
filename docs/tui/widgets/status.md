# akashic/tui/widgets/status.f — Status Bar Widget

**Layer:** 7  
**Lines:** 168  
**Prefix:** `SBAR-` (public), `_SBAR-` (internal)  
**Provider:** `akashic-tui-status`  
**Dependencies:** `widget.f`, `draw.f`

## Overview

A single-row bar for persistent status information (filename, mode,
cursor position, etc.).  Left-aligned text grows from column 0;
right-aligned text is flush to the right edge.  The bar fills its
entire region width with a background colour, then overlays the two
text spans.

The widget does not handle key events (always returns 0).

## Descriptor Layout (80 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+32 | header | widget header | Standard 5-cell header, type=WDG-T-STATUS |
| +40 | left-addr | address | Left text address |
| +48 | left-len | u | Left text length |
| +56 | right-addr | address | Right text address |
| +64 | right-len | u | Right text length |
| +72 | bg-style | packed | fg (bits 0–7), bg (bits 8–15), attrs (bits 16–23) |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `SBAR-NEW` | `( rgn -- widget )` | Create status bar; default style: white on blue |
| `SBAR-FREE` | `( widget -- )` | Free descriptor |

### Text

| Word | Stack | Description |
|------|-------|-------------|
| `SBAR-LEFT!` | `( widget addr len -- )` | Set left-aligned text; marks dirty |
| `SBAR-RIGHT!` | `( widget addr len -- )` | Set right-aligned text; marks dirty |

### Style

| Word | Stack | Description |
|------|-------|-------------|
| `SBAR-STYLE!` | `( widget fg bg attrs -- )` | Set bar colours and attributes |

### Key Handling (via `WDG-HANDLE`)

The status bar does not consume any keys — `_SBAR-HANDLE` always
returns 0.

## Design Notes

- **Packed style.** `fg | (bg << 8) | (attrs << 16)` stored in a
  single cell.  `_SBAR-PACK-STYLE` / `_SBAR-UNPACK-STYLE` convert
  between packed and `( fg bg attrs )` form.
- **No text ownership.** The widget stores pointers to caller-owned
  strings.  The caller must ensure the strings remain valid while
  the status bar is displayed.
- **Default style.** White (7) on blue (4), no attributes.
- When `GUARDED` is defined, every public word is wrapped with
  `WITH-GUARD` for concurrency safety.
