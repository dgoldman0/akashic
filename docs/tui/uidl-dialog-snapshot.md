# A document's dialog, frozen

`akashic/tui/uidl-dialog-snapshot.f` captures the dialog the current UIDL
document shows into caller-owned banks, as one [UDLG model](dialog-model.md)
and a pointer-free descriptor: the [dialog widget](widgets/dialog.md) it
shows, else the one `<dialog>` element its resolved tree shows. A capture
records none or one. The dialog widget writes the model as its last paint
laid the dialog out; its host paints it after everything the document
paints.

A dialog element is the document's own paint ([UIDL-TUI](uidl-tui.md#dialog-management)).
Its model is written as it paints: the title on the top edge two cells in,
its leading labels as the message, one line each on the rows under the top
edge inside the frame, and no buttons. Its revision is
`UTUI-DIALOG-REVISION`, which grows whenever a dialog is laid out or its
title or one of its labels is set. It is captured only when it is the one
dialog element shown, lies wholly on the screen with room for its frame
and title, its message lines are clean, start-aligned single-row labels,
and each of its later visible children is a mounted widget: its contents,
roots of their own that the descriptor counts. Anything else it held would
be painted text beneath it, so it stays painted text.

```forth
UDLSN-CAPTURE ( descriptors-a descriptors-u native-a native-u -- n used status )
UDLSN-FROZEN-VALIDATE ( descriptors-a descriptors-u native-a native-u -- status )
UDLSN-STORAGE-DISJOINT? ( address bytes -- flag )
```

Statuses are `UDLSN-S-OK=0`, `UDLSN-S-CAPACITY=1`, `UDLSN-S-UNAVAILABLE=2`
and `UDLSN-S-INVALID=3`. A capture records nothing, successfully, for a
document that shows no dialog, one not yet painted, one not wholly on the
screen, or one its widget cannot describe: that dialog stays painted text.
CAPACITY means a bank too short for the descriptor or the model; INVALID
covers malformed or aliased banks. A refused capture reports no bytes used,
and the caller publishes none of what it may have written.

The descriptor is 80 bytes of native cells:

| Offset | Field |
|---:|---|
| 0 | Source: `UDLSN-SOURCE-OVERLAY = 3` for a dialog widget, `UDLSN-SOURCE-ELEMENT = 4` for a dialog element, apart from the field sources |
| 8 | Its identity: a dialog widget's instance, or a dialog element's index plus one |
| 16 | Native offset in the document's native bank, zero |
| 24 | Root row on the screen |
| 32 | Root column |
| 40 | Root height |
| 48 | Root width |
| 56 | Native entry bytes |
| 64 | The depth its contents paint at: 255 for a dialog widget's buttons; the dialog lies just below |
| 72 | How many roots its contents are: none for a dialog widget |

Caller banks are aligned, disjoint from each other, from module scratch,
from the model's scratch and from UIDL authority; the widget checks that
the native bank lies apart from the dialog and its region.

Frozen validation never consults the live tree. A slice is valid with no
descriptor and no native bytes, or with one descriptor naming a valid
model that fills the native bank exactly, with the same identity and root
size.

`local_testing/test_uidl_dialog_snapshot.py` captures a painted dialog,
refuses short, empty and aliased banks, leaves a cramped dialog to CELL,
refuses frozen slices their descriptor does not name, and checks that the
document's overlay is the painted dialog.
