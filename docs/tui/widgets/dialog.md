# akashic/tui/widgets/dialog.f — Dialogs

**Layer:** 4C  
**Prefix:** `DLG-` (public), `_DLG-` (internal)  
**Provider:** `akashic-tui-dialog`  
**Dependencies:** `keys.f`, `screen.f`, `widget.f`, `draw.f`, `box.f`, `region.f`

## Overview

A dialog asks the application that opens it a question: a titled box with
a message and a row of buttons. It never blocks. `DLG-ASK` opens it over
the asking application, and that application's host — the app shell, or
Desk's applet host — gives the dialog the application's input and paints
it over the application until a button is chosen. Then the dialog closes,
the host repaints what it covered, and the asker is called back with the
button. Everything else runs on meanwhile; in Desk, the other applications
and Desk itself stay usable.

The dialog sizes itself from its title, message and buttons, all measured
in cells, and centres itself in the host's bounds: the whole screen, or for
a UIDL application its document's region, so it never covers another
application. The message wraps between whole characters, so no row ends
inside one, and the title is clipped by cells when too wide.

## Buttons and roles

Each button is a record of three cells: label address, label length and
roles. Roles:

| Role | Value | Meaning |
|---|---:|---|
| `DLG-B-DEFAULT` | 1 | Selected when the dialog opens |
| `DLG-B-CANCEL` | 2 | Chosen by Escape |
| `DLG-B-DESTRUCTIVE` | 4 | An action that cannot be undone |

A dialog needs at least one button, every label non-empty, at most one
default and one cancel button, and no destructive default. The roles match
the `BTN1` flags of the rich terminal contract.

## API Reference

### Asking

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-ASK` | `( title-a title-u msg-a msg-u buttons count xt context -- ok? )` | Open a dialog over the asking application. Once a button is chosen, `xt` (unless 0) runs `( index context -- )` in that application. False when the application already shows a dialog, the buttons are not valid, or memory is short. |
| `DLG-CONFIRM` | `( msg-a msg-u verb-a verb-u xt context -- ok? )` | Ask before an action that cannot be undone, under the title Confirm: *verb*, destructive, and Cancel, the default. `xt` runs `( confirmed? context -- )`, true only for *verb*. |
| `DLG-INFO` | `( msg-a msg-u -- ok? )` | An Info dialog with OK, which Escape also chooses. |

The dialog keeps its own copies of the title, message and labels, so an
asker may pass text it reuses. The callback runs with the application's
state current, after the dialog is gone, so it may ask again.

### Hosting

A host calls these with an application's state current.

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-SHOWN` | `( -- widget\|0 )` | The dialog the current application shows |
| `DLG-HOST-EVENT` | `( event -- handled? )` | Give an event to that dialog before the application sees it; once a button is chosen, close it and call the asker back. False when there is no dialog. |
| `DLG-HOST-PAINT` | `( -- )` | Paint that dialog over the application, after the application has painted, keeping the caller's drawing region |
| `DLG-DISCARD` | `( -- )` | Free that dialog unanswered: the application is going away |

The host decides which cell holds the current application's dialog through
`_DLG-CELL-HOOK`. UIDL-TUI keeps it in each UIDL context, so each
application has its own and a context freed with an open dialog frees the
dialog too. `_DLG-BOUNDS-HOOK` gives the area to centre in, and
`_DLG-DISMISS-HOOK` marks the rectangle a closing dialog leaves for
repainting.

### Constructor and accessors

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-NEW` | `( title-a title-u msg-a msg-u buttons count -- widget\|0 )` | A closed dialog with its own copies; no region until `DLG-ASK` opens one |
| `DLG-FREE` | `( widget -- )` | Free a dialog and its region; its asker is never called back |
| `DLG-SELECTED` | `( widget -- index )` | The button Enter chooses |
| `DLG-BTN-COUNT` | `( widget -- n )` | Number of buttons |
| `DLG-RESULT` | `( widget -- n )` | -1 while open, then the chosen button |

## Input

While a dialog is open, every event of its application is the dialog's.

| Input | Action |
|-------|--------|
| Left | Select the previous button (stops at the first) |
| Right | Select the next button (stops at the last) |
| Tab | Select the next button, wrapping |
| Enter | Choose the selected button |
| Escape | Choose the cancel button, if there is one |
| Left press on a button | Choose that button |
| Anything else | Swallowed |

## Layout

```
width  = max(title + 4, message + 4, buttons + 4, 20) cells,
         at most 60 and two less than the bounds
height = wrapped message rows + 5, at most two less than the bounds
```

```
┌─ Title ──────────────┐  row 0   box top
│                      │  row 1   blank
│  Message text here   │  row 2+  message (wrapped between characters)
│                      │  row h-3 blank
│  [ OK ] [ Cancel ]   │  row h-2 buttons, centred, one cell apart
└──────────────────────┘  row h-1 box bottom
 ░░░░░░░░░░░░░░░░░░░░░░  shadow
```

The selected button is drawn in reverse video. The dialog is laid out
again at each paint, so it follows its application's region. It paints as
an overlay (`DRW-OVERLAY`), so an optional retained projection never paints
the application's semantics above it.

## Design Notes

- **UI-owner lifecycle**: in a `GUARDED` build, constructor, asking,
  accessor and discard calls use the dialog guard. `DLG-HOST-EVENT` and
  `DLG-HOST-PAINT` run unwrapped on the UI owner core because they call
  back into the application and paint through host hooks.
- **KDOS MAX/MIN are unsigned**: the Left handler uses an explicit `0>`
  guard instead of `1- 0 MAX` to avoid unsigned underflow.
- Draw and handle logic keeps its state in `VARIABLE`s rather than deep
  stack manipulation.
