# akashic/tui/progress.f — Progress Bar & Spinner Widget

**Layer:** 4A  
**Lines:** 263  
**Prefix:** `PRG-` (public), `_PRG-` (internal)  
**Provider:** `akashic-tui-progress`  
**Dependencies:** `widget.f`, `draw.f`

## Overview

A progress widget displays either a **bar** (filled/empty ratio) or a
**spinner** (animated Braille dot cycle).  Both styles are driven by a
value / max pair; the spinner additionally uses a frame counter
advanced by `PRG-TICK`.

Progress widgets are non-interactive — `WDG-HANDLE` always returns 0.

## Descriptor Layout (72 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header |
| +40 | value | u | Current progress value |
| +48 | max | u | Maximum value (denominator) |
| +56 | style | constant | `PRG-BAR` or `PRG-SPINNER` |
| +64 | frame | u | Spinner frame counter |

## Style Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `PRG-BAR` | 0 | Horizontal bar using block elements |
| `PRG-SPINNER` | 1 | Animated Braille dot spinner |

## Block Characters (Bar Style)

| Symbol | Codepoint | Usage |
|--------|-----------|-------|
| `█` | U+2588 | Fully filled column |
| `░` | U+2591 | Empty column |
| `▏`–`▉` | U+258F–U+2589 | 1/8 – 7/8 fractional fill |

The bar computes `filled_eighths = value × width × 8 / max`,
then renders `filled_eighths / 8` full blocks, one fractional
block (if any), and empty blocks for the remainder.

## Spinner Frames

10 Braille dot patterns cycle through:

```
⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏
```

The spinner draws the current frame's character at column 0, row 0,
and fills the remaining columns with spaces.

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `PRG-NEW` | `( rgn max style -- widget )` | Allocate + init; value starts at 0 |
| `PRG-FREE` | `( widget -- )` | Free the descriptor |

### Value Mutation

| Word | Stack | Description |
|------|-------|-------------|
| `PRG-SET` | `( value widget -- )` | Set value; clamps to max; marks dirty |
| `PRG-INC` | `( widget -- )` | Increment value by 1; clamps to max; marks dirty |
| `PRG-TICK` | `( widget -- )` | Advance spinner frame by 1 (wraps at 10); marks dirty |

### Queries

| Word | Stack | Description |
|------|-------|-------------|
| `PRG-PCT` | `( widget -- percent )` | Compute `value × 100 / max` (0 if max = 0) |

### Drawing (via `WDG-DRAW`)

`WDG-DRAW` activates the widget's region, calls the internal
draw-xt `_PRG-DRAW`, then clears the dirty flag.

- **Bar style:** Draws on row 0 using the full region width.  
  Handles `max = 0` gracefully (fills with empty blocks).
- **Spinner style:** Draws the current Braille character at (0, 0),
  fills columns 1..width-1 with spaces.

## Internal Words

| Word | Stack | Description |
|------|-------|-------------|
| `_PRG-DRAW` | `( widget -- )` | Dispatch to bar or spinner draw |
| `_PRG-DRAW-BAR` | `( widget -- )` | Render horizontal bar |
| `_PRG-DRAW-SPIN` | `( widget -- )` | Render spinner frame |
| `_PRG-HANDLE` | `( event widget -- 0 )` | Always returns 0 |

## Usage Example

```forth
\ ---- 20×1 region for a bar ----
0 0 20 1 RGN-NEW   100 PRG-BAR PRG-NEW   ( bar )

\ ---- set to 42% and draw ----
42 OVER PRG-SET
DUP WDG-DRAW

\ ---- increment step by step ----
DUP PRG-INC   DUP WDG-DRAW      \ now 43%

\ ---- spinner in a 10×1 region ----
2 0 10 1 RGN-NEW   0 PRG-SPINNER PRG-NEW   ( spinner )
DUP PRG-TICK   DUP WDG-DRAW    \ frame 1
DUP PRG-TICK   DUP WDG-DRAW    \ frame 2

\ ---- clean up ----
DUP WDG-REGION RGN-FREE   PRG-FREE
SWAP DUP WDG-REGION RGN-FREE   PRG-FREE
```

## Design Notes

- **Fractional bar fill.** Unicode block elements give 1/8-column
  resolution.  A 20-column bar has 160 distinct fill levels.
- **max = 0 safety.** When max is 0, the bar draws all-empty and
  `PRG-PCT` returns 0 — no division by zero.
- **Clamping.** `PRG-SET` and `PRG-INC` clamp the value to max,
  so the bar never overflows.
- **Spinner is value-independent.** The spinner frame advances only
  via `PRG-TICK`, not via the value/max pair.  The value/max can
  still be queried with `PRG-PCT` while a spinner is active.
