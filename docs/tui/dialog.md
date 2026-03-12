# akashic/tui/dialog.f — Modal Dialog Boxes

**Layer:** 4C  
**Lines:** ~340  
**Prefix:** `DLG-` (public), `_DLG-` (internal)  
**Provider:** `akashic-tui-dialog`  
**Dependencies:** `keys.f`, `screen.f`, `widget.f`, `draw.f`, `box.f`, `region.f`

## Overview

Modal popup dialog with a titled box border, a message area, and a
horizontal button row.  `DLG-SHOW` runs a real `KEY-POLL` busy-loop
that blocks the caller until the user picks a button (Enter to accept,
Escape to cancel, Tab / arrow keys to navigate buttons).

The dialog auto-sizes based on the title, message, and button widths,
and centres itself on a 24×80 screen.  Convenience wrappers
`DLG-INFO` and `DLG-CONFIRM` create, show, and free one-shot dialogs.

## Button Label Array (16 bytes per entry)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0 | label-a | address | Button label string address |
| +8 | label-u | u | Button label string length |

Buttons are contiguous `(addr, len)` pairs, 2 cells each.

## Dialog Descriptor (104 bytes)

| Offset | Field | Type | Description |
|--------|-------|------|-------------|
| +0..+39 | header | widget header | Standard 5-cell header, type=`WDG-T-DIALOG` (7) |
| +40 | title-a | address | Dialog title string address |
| +48 | title-u | u | Title string length |
| +56 | msg-a | address | Message body string address |
| +64 | msg-u | u | Message string length |
| +72 | buttons | address | Pointer to button label array |
| +80 | btn-count | u | Number of buttons |
| +88 | selected-btn | u | Currently focused button index |
| +96 | result | n | -1 while open, ≥0 = chosen button index |

## API Reference

### Constructor / Destructor

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-NEW` | `( title-a title-u msg-a msg-u btns count -- widget )` | Allocate dialog descriptor; no region yet |
| `DLG-FREE` | `( widget -- )` | Free the descriptor |

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-SELECTED` | `( widget -- index )` | Currently focused button index |
| `DLG-BTN-COUNT` | `( widget -- n )` | Number of buttons |
| `DLG-RESULT` | `( widget -- n )` | Per-widget result: -1 while open, ≥0 once chosen |
| `DLG-SET-REGION` | `( rgn widget -- )` | Assign a region (for manual placement / testing) |

### Modal Loop

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-SHOW` | `( widget -- index )` | Auto-size, centre, draw, run `KEY-POLL` modal loop; returns chosen button index |

### Convenience Wrappers

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-INFO` | `( msg-a msg-u -- )` | One-shot "Info" dialog with `[ OK ]` button |
| `DLG-CONFIRM` | `( msg-a msg-u -- flag )` | "Yes / No" dialog; returns TRUE for Yes (button 0) |

### Key Handling (via `WDG-HANDLE` or modal loop)

| Key | Action |
|-----|--------|
| Left | Move focus to previous button (clamps at 0) |
| Right | Move focus to next button (clamps at last) |
| Tab | Cycle focus to next button (wraps around) |
| Enter | Accept — sets result to focused button index |
| Escape | Cancel — sets result to last button index |

## Auto-Sizing (DLG-SHOW)

```
width  = max(title-len + 4, msg-len + 4, btn-total-w + 4, 20)
         clamped to 60
height = 5 + ceil(msg-len / (width - 4))
```

The dialog is centred on a 24×80 screen.  The auto-created region
is freed when `DLG-SHOW` returns; the widget itself is not freed.

## Layout

```
┌─ Title ──────────────┐  row 0   box top
│                      │  row 1   blank
│  Message text here   │  row 2+  message (line-wrapped)
│                      │  row h-3 blank
│  [ OK ] [ Cancel ]   │  row h-2 buttons (centred)
└──────────────────────┘  row h-1 box bottom
 ░░░░░░░░░░░░░░░░░░░░░░  shadow
```

The focused button is rendered in reverse video.

## Design Notes

- **Per-widget result**:  the result field lives at +96 in each
  descriptor, so multiple dialogs stay independent (no global state).
- **Real modal loop**: `DLG-SHOW` calls `KEY-POLL` in a tight
  `BEGIN … UNTIL` loop, dispatching events through `WDG-HANDLE`.
  Each accepted event redraws (if dirty) and calls `SCR-FLUSH`.
- **KDOS MAX/MIN are unsigned**: the LEFT handler uses an explicit
  `0>` guard instead of `1- 0 MAX` to avoid unsigned underflow.
- Button label arrays and title/message strings are **caller-owned**
  — the dialog stores pointers but does not copy or free them.
- All draw and handle logic uses `VARIABLE`-based state to avoid
  deep stack manipulation (KDOS best practice).
