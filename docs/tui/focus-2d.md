# akashic/tui/focus-2d.f — Spatial (2D) Focus Navigation

**Layer:** 6  
**Lines:** 216  
**Prefix:** `F2D-` (public), `_F2D-` (internal)  
**Provider:** `akashic-tui-focus-2d`  
**Dependencies:** `focus.f`, `keys.f`, `widget.f`, `region.f`

## Overview

Plug-in for `focus.f` that adds directional (spatial) focus movement.
Given the currently focused widget, scans the focus chain for the
nearest visible widget in the requested direction using Manhattan
distance with a directional cross-axis bias.

Also provides keyboard-driven mouse emulation: Alt+Arrow for
spatial navigation, Alt+Delete / Alt+End / Alt+PgDn for synthetic
left / middle / right clicks.

## Algorithm

1. Compute center-point of the currently focused widget's region.
2. For each widget in the chain (via `FOC-EACH`):
   - Skip self and hidden widgets.
   - Compute candidate center-point.
   - Apply direction predicate (above? below? left? right?).
   - Compute biased Manhattan score:
     - **Vertical moves:** `|Δrow| + 2×|Δcol|`
     - **Horizontal moves:** `2×|Δrow| + |Δcol|`
   - Track the lowest-scoring candidate.
3. If a candidate was found, `FOC-SET` moves focus to it.

The 2× cross-axis penalty strongly favors candidates that are
aligned along the movement axis, preventing diagonal jumps.

## Key Bindings

| Key Combo | Action |
|-----------|--------|
| Alt + ↑ | `F2D-UP` — focus nearest widget above |
| Alt + ↓ | `F2D-DOWN` — focus nearest widget below |
| Alt + ← | `F2D-LEFT` — focus nearest widget left |
| Alt + → | `F2D-RIGHT` — focus nearest widget right |
| Alt + Delete | `F2D-CLICK-L` — left click on focused widget |
| Alt + End | `F2D-CLICK-M` — middle click on focused widget |
| Alt + PgDn | `F2D-CLICK-R` — right click on focused widget |

## API Reference

### Directional Navigation

| Word | Stack | Description |
|------|-------|-------------|
| `F2D-UP` | `( -- )` | Move focus to nearest widget above current. No-op if no candidate. |
| `F2D-DOWN` | `( -- )` | Move focus to nearest widget below current. No-op if no candidate. |
| `F2D-LEFT` | `( -- )` | Move focus to nearest widget to the left. No-op if no candidate. |
| `F2D-RIGHT` | `( -- )` | Move focus to nearest widget to the right. No-op if no candidate. |

### Synthetic Mouse Clicks

| Word | Stack | Description |
|------|-------|-------------|
| `F2D-CLICK-L` | `( -- )` | Simulate left-click at focused widget center. |
| `F2D-CLICK-M` | `( -- )` | Simulate middle-click at focused widget center. |
| `F2D-CLICK-R` | `( -- )` | Simulate right-click at focused widget center. |

Synthetic clicks build a `KEY-T-MOUSE` event with the button code
in the code field, write `KEY-MOUSE-X` / `KEY-MOUSE-Y` to the
widget's center column / row, and call `WDG-HANDLE` directly on
the focused widget.

### Key Dispatch

| Word | Stack | Description |
|------|-------|-------------|
| `F2D-DISPATCH` | `( ev -- flag )` | Check event for Alt+Arrow or Alt+click combos. Returns `-1` if handled, `0` if not recognized. |

`F2D-DISPATCH` should be called **before** the normal focus chain
dispatch so spatial navigation takes priority.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `F2D-BTN-LEFT` | 1 | Left mouse button |
| `F2D-BTN-MID` | 2 | Middle mouse button |
| `F2D-BTN-RIGHT` | 3 | Right mouse button |

## Guard Support

When `GUARDED` is defined, all public words are wrapped with
`_f2d-guard WITH-GUARD` for thread-safety.

## Design Notes

- **Plug-in architecture.**  `focus-2d.f` does not modify `focus.f`.
  It uses `FOC-EACH` for scanning and `FOC-SET` / `FOC-GET` for
  focus manipulation — pure public API.
- **Direction predicates** are separate words so the generic scan
  loop (`_F2D-SCAN`) can accept any combination of predicate and
  scoring function via execution tokens.
- **No wrapping.**  If no candidate exists in the requested direction,
  focus stays on the current widget.  This is intentional — spatial
  navigation should not wrap around the screen.
- **Score ceiling.**  Initial score is 32767 so any real candidate
  beats it.

## Test Coverage

Tests in `local_testing/test_focus.py` (shared with focus.f):

- §I: Directional navigation — down, up, left, right, diagonal bias, no-candidate, empty chain (7 tests)
- §J: Synthetic clicks — left click dispatch, empty chain safety (2 tests)
- §K: F2D-DISPATCH key routing — Alt+Down, Alt+Right, non-Alt passthrough, char-key passthrough, Alt+Delete click (5 tests)
