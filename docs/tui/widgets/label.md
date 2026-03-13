# akashic/tui/widgets/label.f — Static Text Label Widget

**Layer:** 4A  
**Lines:** 209  
**Prefix:** `LBL-` (public), `_LBL-` (internal)  
**Provider:** `akashic-tui-label`  
**Dependencies:** `widget.f`, `draw.f`

## Overview

A label displays a static UTF-8 text string inside a region.  Text can
be aligned left, centered, or right-justified.  When the text is wider
than the region, it wraps onto subsequent rows (line-breaking on
codepoint boundaries, not word boundaries).  Rows beyond the region
height are silently clipped.

Labels are non-interactive — `WDG-HANDLE` always returns 0.

## Descriptor Layout (64 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header |
| +40 | text-addr | address | Pointer to UTF-8 text string |
| +48 | text-len | u | Byte length of text |
| +56 | align | constant | `LBL-LEFT`, `LBL-CENTER`, or `LBL-RIGHT` |

## Alignment Constants

| Constant | Value | Effect |
|----------|-------|--------|
| `LBL-LEFT` | 0 | Left-aligned (default) |
| `LBL-CENTER` | 1 | Horizontally centered |
| `LBL-RIGHT` | 2 | Right-aligned |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `LBL-NEW` | `( rgn text-a text-u align -- widget )` | Allocate + init a label |
| `LBL-FREE` | `( widget -- )` | Free the descriptor |

### Mutators

| Word | Stack | Description |
|------|-------|-------------|
| `LBL-SET-TEXT` | `( text-a text-u widget -- )` | Change displayed text; marks dirty |
| `LBL-SET-ALIGN` | `( align widget -- )` | Change alignment; marks dirty |

### Drawing (via `WDG-DRAW`)

`WDG-DRAW` activates the widget's region, calls the internal
draw-xt `_LBL-DRAW`, then clears the dirty flag.  The draw routine:

1. Reads the region's width and height.
2. For each row, consumes up to *width* codepoints from the text
   (via `_LBL-CONSUME`), then draws the slice with the current
   alignment using `DRW-TEXT`, `DRW-TEXT-CENTER`, or
   `DRW-TEXT-RIGHT`.
3. Clears any remaining rows below the last text line with
   spaces (`DRW-HLINE` with the space character).

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_LBL-DRAW` | `( widget -- )` | Full draw implementation |
| `_LBL-HANDLE` | `( event widget -- 0 )` | Always returns 0 (non-interactive) |
| `_LBL-CONSUME` | `( maxcp -- blen )` | Advance internal addr/len vars by up to *maxcp* codepoints; return byte span consumed |
| `_LBL-DRAW-ROW` | `( addr blen row -- )` | Clear row, draw text slice with alignment |

Internal variables used by draw:

| Variable | Purpose |
|----------|---------|
| `_LBL-DRW-ADDR` | Current text pointer (advanced during draw) |
| `_LBL-DRW-LEN` | Remaining text byte length |
| `_LBL-DRW-ALIGN` | Alignment constant for current draw |

## Usage Example

```forth
\ ---- create a 20×1 region at row 3 col 5 ----
3 5 20 1 RGN-NEW      ( rgn )

\ ---- create a centred label ----
S" Hello, World!" LBL-CENTER LBL-NEW   ( widget )

\ ---- draw it ----
DUP WDG-DRAW

\ ---- change text ----
S" Goodbye!" OVER LBL-SET-TEXT
DUP WDG-DRAW

\ ---- clean up ----
DUP WDG-REGION RGN-FREE
LBL-FREE
```

## Design Notes

- **Text storage is by reference.** The label stores the address and
  length of the caller's string — it does not copy or own the
  string memory.  The caller must keep the string alive while the
  label exists.
- **Wrapping is codepoint-based, not word-based.** If the text
  contains multi-byte UTF-8 sequences, `_LBL-CONSUME` counts
  codepoints (by detecting lead-byte vs continuation-byte) to
  ensure no character is split across rows.
- **No scroll.** Text that overflows the region height is silently
  clipped.  For scrolling text, wrap a label in a scroll container
  (Layer 5+).
