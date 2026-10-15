# A document's dialog, frozen

`akashic/tui/uidl-dialog-snapshot.f` captures the dialog the current UIDL
document shows into caller-owned banks, as one [UDLG model](dialog-model.md)
and a pointer-free descriptor. A document shows at most one dialog, so a
capture records none or one. The [dialog widget](widgets/dialog.md) writes
the model as its last paint laid the dialog out; its host paints it after
everything the document paints.

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

The descriptor is 64 bytes of native cells:

| Offset | Field |
|---:|---|
| 0 | Source: `UDLSN-SOURCE-OVERLAY = 1` |
| 8 | The dialog's instance, its identity while it lives |
| 16 | Native offset in the document's native bank, zero |
| 24 | Root row on the screen |
| 32 | Root column |
| 40 | Root height |
| 48 | Root width |
| 56 | Native entry bytes |

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
