# akashic/utils/term.f — Terminal Geometry Utilities

**Lines:** 170  
**Prefix:** `TERM-` (public), `_TERM-` (internal)  
**Provider:** `akashic-term`  
**Dependencies:** None (uses BIOS UART Geometry words directly)

## Overview

Wraps the six BIOS UART Geometry register words behind a consistent
`TERM-` prefix and adds derived convenience words for area
calculation, fitness testing, clamping, centering, change detection,
and resize-with-timeout.

The underlying hardware is the UART Geometry device at MMIO address
`0xFFFF_FF00_0000_0010`, which exposes the host terminal's column and
row counts and supports cooperative resize requests.

## BIOS Words Used

| BIOS Word | Stack | Description |
|-----------|-------|-------------|
| `COLS` | `( -- n )` | Read column count (16-bit) |
| `ROWS` | `( -- n )` | Read row count (16-bit) |
| `TERMSIZE` | `( -- cols rows )` | Read both dimensions |
| `RESIZED?` | `( -- flag )` | Check & clear RESIZED flag (W1C) |
| `RESIZE-DENIED?` | `( -- flag )` | Check & clear REQ_DENIED flag (W1C) |
| `RESIZE-REQUEST` | `( cols rows -- )` | Write REQ_COLS/REQ_ROWS + trigger |

## API Reference

### §1 — Direct BIOS Wrappers

| Word | Stack | Description |
|------|-------|-------------|
| `TERM-W` | `( -- n )` | Current terminal width in columns. Delegates to `COLS`. |
| `TERM-H` | `( -- n )` | Current terminal height in rows. Delegates to `ROWS`. |
| `TERM-SIZE` | `( -- w h )` | Current terminal dimensions. Delegates to `TERMSIZE`. |
| `TERM-RESIZED?` | `( -- flag )` | Check if a resize has occurred since the last check. Clears the hardware flag (write-1-to-clear). |

### §2 — Derived Geometry Words

| Word | Stack | Description |
|------|-------|-------------|
| `TERM-AREA` | `( -- n )` | Total cells: width × height. |
| `TERM-FIT?` | `( w h -- flag )` | TRUE if a w×h rectangle fits within the current terminal. |
| `TERM-CLAMP` | `( w h -- w' h' )` | Clamp dimensions to current terminal bounds (MIN each axis). |
| `TERM-CENTER` | `( w h -- col row )` | Compute 0-based top-left coordinates to center a w×h rectangle in the terminal. |

### §3 — Snapshot & Change Detection

| Word | Stack | Description |
|------|-------|-------------|
| `TERM-SAVE` | `( -- w h )` | Return current dimensions for later comparison (alias for `TERM-SIZE`). |
| `TERM-CHANGED?` | `( old-w old-h -- flag )` | Compare saved dimensions against current; TRUE if different. |

### §4 — Resize Request with Timeout

| Word | Stack | Description |
|------|-------|-------------|
| `TERM-RESIZE` | `( w h -- ior )` | Request the host to resize the terminal. Blocks (polling) until `RESIZED?`, `RESIZE-DENIED?`, or timeout. Returns: 0 = accepted, -1 = denied, -2 = timeout. |
| `TERM-RESIZE-TIMEOUT!` | `( ms -- )` | Set the resize poll timeout in milliseconds. Default: 2000. |

## State Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `_TERM-RESIZE-TIMEOUT` | 2000 | Resize poll timeout in milliseconds. |

## Guard Support

When `GUARDED` is defined, all eleven public words are wrapped with
`_term-guard WITH-GUARD` for thread-safety.

## TUI Framework Integration

### event.f — Hardware Resize Polling

`event.f` now `REQUIRE`s `term.f` and adds a
`_TUI-EVT-CHECK-HW-RESIZE` step in the main event loop (step 4,
after input dispatch, before deferred actions).  Each iteration polls
`TERM-RESIZED?`; when set, reads `TERM-SIZE` and invokes the
registered resize callback `( w h -- )`.  This complements the
existing ANSI-escape-based `KEY-T-RESIZE` path.

### app.f — Auto-Sizing

`APP-INIT ( w h -- )` now supports auto-sizing: when both width and
height are 0, it calls `TERM-SIZE` to read the hardware dimensions
instead.  Usage: `0 0 APP-INIT` to match the current terminal size.

## Design Notes

- **Write-1-to-clear flags.** `RESIZED?` and `RESIZE-DENIED?` are
  W1C (write-1-to-clear) hardware registers.  Reading them returns
  the current value and atomically clears the flag.  This means
  each call is a one-shot check — call once per poll cycle.
- **No dependencies.** `term.f` uses only BIOS dictionary words
  that are available immediately after KDOS boot.  No other akashic
  files are required.
- **Cooperative resize.** `TERM-RESIZE` is a polling loop that calls
  `RESIZE-REQUEST` then spins on `RESIZED?` / `RESIZE-DENIED?`.  The
  host may deny or ignore the request.  The timeout prevents hangs.
- **TERM-CENTER rounding.** Uses integer division (`2 /`), so the
  centering is biased left/up by one cell when the remainder is odd.
