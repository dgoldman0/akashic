# Dialog publication from the ordinary dialog widget

The hybrid producer lowers each document's frozen dialog, which
[UDLSN](../tui/uidl-dialog-snapshot.md) captures from the ordinary
[dialog widget](../tui/widgets/dialog.md) and `RUHA` carries in its snapshot,
into one `RTE-CONTROL-DIALOG` and an `RTE-CONTROL-BUTTON` for each shown
button. The widget's canonical [UDLG model](../tui/dialog-model.md) is the
only source of the dialog's place, title, message, severity, revision and
buttons. Applications call no terminal API, and the producer infers nothing
from painted text. [DIALOG-ADMISSION.md](DIALOG-ADMISSION.md) gives the
controls' wire rules.

## Composition and bounds

`RTHP-STORAGE-BYTES` and `RTHP-INIT` take `max-dialog-native` immediately
after `max-field-native` and before `max-pictures`; `RTHP-FIRST-CAPACITIES`
starts it at zero. The bound is zero or an aligned unsigned 32-bit byte
count, and zero selects no dialog bank.

For dialog native capacity `N`, the arena holds `floor(N / 160)` 64-byte
UDLSN descriptors, since every model has its 160-byte header, and an `N`-byte
native bank. A dialog's controls are its DIALOG and its buttons, and every
button takes a 64-byte record, so the lane holds at most `floor(N / 64)`
controls; they join the control, correlation, target and projection
workspaces as fields do. The shared control text bank grows by `N`, which
covers a title and DLG1, whose 56-byte header is smaller than the model's,
and each label with its 8-byte BTN1. With a memory source the arena grows to
the dialogs a draw shows, half again, as other content does.

The producer record is 4984 bytes. The packed target header is 368 bytes;
the dialog lane's controls, dialogs and UTF8 bytes sit at 344, 352 and 360.

## Lowering

Source descriptors and models are copied into the producer's own banks.
Without the negotiated `DIALOGS` feature, or without room, the copy leaves the
lane empty and the directory names no dialog, so every dialog stays CELL.
Extents that do not fit their banks are invalid even without the feature.

The dialog controls follow the fields: menus, collections, fields, then each
document's DIALOG and its buttons in directory order. A document's slice must
be exactly one frozen dialog: one descriptor naming one valid model of the
descriptor's key and size, or it is invalid. The DIALOG lies where the
dialog does, its title the label (none when the dialog has no title), its
content DLG1 and its UTF8 the message. Each shown button follows at the
dialog's origin plus its slot, its label the label and BTN1 the content, its
state VISIBLE, ENABLED and SELECTED as the model gives them. A hidden button
takes no control. Every control has the depth of a document's overlay, 255;
buttons follow their dialog and so draw over it.

Each correlation names the dialog: the document's token, the source
`UDLSN-SOURCE-OVERLAY`, which no field source shares, the dialog's key in
SUBKEY and SCOPE, and index 0 for the DIALOG and `i + 1` for button `i`. Its
lifecycle generation is 1: the key, a dialog widget's instance, is already
unique for the dialog's life.

The DIALOG claims its whole rectangle, so its buttons and the rest of its
paint lie inside that claim. A dialog off the screen or outside its
document's rectangle stays CELL. One that meets another dialog's claim
removes the whole lane; one that meets an earlier family's claim refuses the
rich candidate, as a field does, since that family's projection would then be
wrong under it. Local capacity removes the lane and restores the exact
control, text and claim prefixes. An opaque provider refusal is retried
without dialogs after statics and before fields, and a lane refused once
stays refused through that candidate's later retries. Removing the fields
removes the dialog lane after them, which is then built again.

## Input, packing and DELTA

A shown, enabled BUTTON is a press target at its first cell, which the
dialog's own button covers, so ACTIVATE becomes an ordinary click there. The
DIALOG takes no input of its own.

Packed acknowledgement banks own every title, label, DLG1 and BTN1; packing
and unchanged cloning rebase them. A DELTA keeps the dialog lane's shape: a
dialog that appears or goes, or a changed number of buttons, takes a
complete replacement. A DIALOG keeps its title and geometry, and its DLG1
may change only with a strictly newer revision, in one CONTROL-REPLACE. A
BUTTON keeps its geometry and may change its label, roles and state.

## Tests

`local_testing/test_rich_dialog_producer.py` executes the production
lowering, source copy, audit, packing, cloning, DELTA comparison and target
lookup words on Python and native executors against independent UDLG, UDLSN,
DLG1 and BTN1 byte fixtures. Only the outer constructor-validity hook is
replaced.
