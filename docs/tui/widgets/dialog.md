# akashic/tui/widgets/dialog.f — Dialogs

**Layer:** 4C  
**Prefix:** `DLG-` (public), `_DLG-` (internal)  
**Provider:** `akashic-tui-dialog`  
**Dependencies:** `keys.f`, `screen.f`, `widget.f`, `draw.f`, `box.f`, `region.f`, `text-lines.f`, `bidi.f`, `dialog-model.f`

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
application. The title is clipped by cells when too wide.

The message is untrusted text: paragraphs, each with a look, broken into
lines by the shared line rule ([APT-1-TEXT](../../rich-terminal/APT-1-TEXT.md)
Section 12) with their direction controls ignored, as `DRW-TEXT-UNTRUSTED`
draws. A message taller than the dialog scrolls: the dialog keeps the last
of its message rows to say `PgDn: more below` while more of the message lies
below it. `DLG-ASK-DETAIL` asks with several paragraphs in a dialog that
takes the host's area but a cell at each side, for a request the user reads
before answering it.

## Buttons and roles

Each button is a record of four cells: label address, label length, roles
and key. Roles:

| Role | Value | Meaning |
|---|---:|---|
| `DLG-B-DEFAULT` | 1 | Selected when the dialog opens |
| `DLG-B-CANCEL` | 2 | Chosen by Escape |
| `DLG-B-DESTRUCTIVE` | 4 | An action that cannot be undone |
| `DLG-B-READ-FIRST` | 8 | Unavailable until a paint has shown the message's last line |

The key is 0, or a function key, `KEY-F1` to `KEY-F12`, that chooses the
button; the button shows the key's name before its label. A dialog needs at
least one button, every label non-empty, at most one default and one cancel
button, no destructive default, and no two buttons with one key. The first
three roles match the `BTN1` flags of the rich terminal contract. A button
that is not available yet is drawn dim, and neither Enter, its key nor a
press chooses it.

## Paragraphs and looks

`DLG-ASK-DETAIL` takes paragraphs as records of three cells: text address,
text length and look. `DLG-ASK`'s message is one paragraph of
`DLG-LOOK-TEXT`; a line feed in any paragraph starts another.

| Look | Value | Shown as |
|---|---:|---|
| `DLG-LOOK-TEXT` | 0 | Ordinary text |
| `DLG-LOOK-LABEL` | 1 | A label naming what follows, bold yellow |
| `DLG-LOOK-VALUE` | 2 | An exact value, light cyan |
| `DLG-LOOK-FAULT` | 3 | What is wrong, bold light red |
| `DLG-LOOK-HEADING` | 4 | A heading, bold white |

Looks are the CELL painting's; the model carries the lines' text.

## API Reference

### Asking

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-ASK` | `( title-a title-u msg-a msg-u buttons count xt context -- ok? )` | Open a dialog over the asking application. Once a button is chosen, `xt` (unless 0) runs `( index context -- )` in that application. False when the application already shows a dialog, the buttons are not valid, or memory is short. |
| `DLG-ASK-DETAIL` | `( title-a title-u paras pcount buttons bcount xt context -- ok? )` | As `DLG-ASK`, with `pcount` paragraphs, each with its look, in a dialog that takes the host's area. False also when there is no paragraph or a look is unknown. |
| `DLG-CONFIRM` | `( msg-a msg-u verb-a verb-u xt context -- ok? )` | Ask before an action that cannot be undone, under the title Confirm: *verb*, destructive, and Cancel, the default. `xt` runs `( confirmed? context -- )`, true only for *verb*. Its meaning is a warning. |
| `DLG-INFO` | `( msg-a msg-u -- ok? )` | An Info dialog with OK, which Escape also chooses. Its meaning is informational. |

The dialog keeps its own copies of the title, paragraphs and labels, so an
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
| `DLG-WITHDRAW` | `( -- )` | Close that dialog unanswered and have the host repaint what it covered: the application no longer asks |

The host decides which cell holds the current application's dialog through
`DLG-CELL-HOOK`. UIDL-TUI keeps it in each UIDL context, so each
application has its own and a context freed with an open dialog frees the
dialog too. `DLG-BOUNDS-HOOK` gives the area to centre in, and
`DLG-DISMISS-HOOK` marks the rectangle a closing dialog leaves for
repainting.

### Capture

A renderer that can show a dialog as a dialog takes it from these.

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-INSTANCE@` | `( widget -- instance\|0 )` | The dialog's identity for as long as it lives; 0 for anything else |
| `DLG-ROOT` | `( widget -- row col height width )` | The screen cells its last paint laid it out in; all zero before |
| `DLG-MODEL-CAPTURE` | `( dst cap widget -- bytes status )` | Write the dialog its last paint laid out as a [UDLG model](../dialog-model.md) at DST, an aligned span apart from the dialog; with DST 0 and CAP 0 only measure it |

The model has the title on the top edge, from column 2 and as wide as the
paint shows it; the message rows in view as the paint broke them, from row 2
and column 2, with the row saying more lies below while it does; and a
record a button where the paint put it, with its key's name. A button that
can be chosen is `ENABLED`, and the selected one `SELECTED` when it can be.
The message's direction controls go out as inert stand-ins (`BIDI-INERT`),
as the paint ignored them. Its revision is new whenever the dialog is laid
out at another size or shows other rows of its message; instances and
revisions only grow, so neither repeats across dialogs. A plain dialog is
neutral, an Info dialog informational and a confirmation a warning. A
dialog not yet painted, one laid out shorter than five rows or narrower
than five columns, one whose message cannot be laid out, or one whose
title, message lines or labels are not clean single-line text, has no
model: `UDLG-S-UNSUPPORTED`, and it stays painted text.

### Accessors

| Word | Stack | Description |
|------|-------|-------------|
| `DLG-FREE` | `( widget -- )` | Free a dialog and its region; its asker is never called back |
| `DLG-SELECTED` | `( widget -- index )` | The button Enter chooses |
| `DLG-BTN-COUNT` | `( widget -- n )` | Number of buttons |
| `DLG-RESULT` | `( widget -- n )` | -1 while open, then the chosen button |
| `DLG-PARAGRAPH` | `( widget index -- a u )` | The dialog's copy of a paragraph's text; `DLG-ASK`'s message is paragraph 0 |

## Input

While a dialog is open, every event of its application is the dialog's.

| Input | Action |
|-------|--------|
| Left | Select the previous button (stops at the first) |
| Right | Select the next button (stops at the last) |
| Tab | Select the next button, wrapping |
| Enter | Choose the selected button |
| Escape | Choose the cancel button, if there is one |
| A button's function key | Choose that button |
| Up, Down | Scroll the message a row |
| PgUp, PgDn | Scroll the message a view less a row |
| Home, End | Scroll to the message's first or last rows |
| Wheel | Scroll the message three rows |
| Left press on a button | Choose that button |
| Anything else | Swallowed |

Only a button that is available is chosen.

## Layout

```
plain:  width  = max(title + 4, widest message line + 4, buttons + 4, 20)
                 cells, at most 60 and two less than the bounds
        height = message rows + 5, at most two less than the bounds
detail: width  = two less than the bounds
        height = two less than the bounds
```

The message is broken at the width less four. When its rows outrun the
`height - 5` rows the dialog has for them, the last of those rows says
`PgDn: more below` until the message's last line is in view. A dialog five
rows high shows one message row on its lower blank row; a shorter one has
no row for the message, so it is never read and a `DLG-B-READ-FIRST`
button stays unavailable until a taller paint shows the last line.

```
┌─ Title ──────────────┐  row 0   box top
│                      │  row 1   blank
│  Message text here   │  row 2+  message, broken by the line rule
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
