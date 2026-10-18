# Typed DIALOG and BUTTON admission

DIALOG and BUTTON use the existing CONTROL lane and its immutable root
bounds. They are not a collection. `RTE-CONTROL-DIALOG` and
`RTAPT-CONTROL-DIALOG` are kind 15; `RTE-CONTROL-BUTTON` and
`RTAPT-CONTROL-BUTTON` are kind 16. Both need the local `*-F-DIALOGS` feature,
`0x8000`, explicitly mapped to APT-1 `RET_DIALOGS`, which also allows modal
regions. It requires CONTROLS. The payload and complete transaction minima
are 136 and 336 bytes: CONTROL and the smallest DLG1 body.

The 200-byte neutral CONTROL record and 160-byte provider copy header retain
their layouts. Both kinds are roots: PARENT and ORDER are zero.

| Kind | LABEL | SHORTCUT | CONTENT | CONTENT-UTF8 | State |
| --- | --- | --- | --- | --- | --- |
| DIALOG | optional title | empty | exact DLG1 | the message's bytes | VISIBLE only |
| BUTTON | nonempty | optional | exact 8-byte BTN1 | zero | VISIBLE, ENABLED, SELECTED |

CONTENT-ITEMS, CONTENT-RUNS and CONTENT-FIELDS are zero for both. Each
consumes one control and object slot. The title, message, label and shortcut
are charged to UTF-8; BTN1 carries no text. A button's label and shortcut
are strict single-line text, as a taskbar's are. A dialog's contents are the
other roots of its owner and region inside its bounds above it, as the
contract says; admission checks each root alone.

`DLG1-VALIDATE ( content-a content-u title-a title-u cols rows -- utf8 flag )`
derives the message's bytes; failure returns two zeros. It validates the
exact 56-byte header, a positive revision, a severity from 0 to 4, the
NOTICE flag alone, a title slot present exactly when the title is and a
message slot exactly when the message is, both inside the dialog's root and
apart, and message lines of clean single-line text, no more than the
message slot's rows. `BTN1-VALIDATE ( a u -- flag )` validates the 8-byte
tag, version and roles, never destructive and default together. The
validators keep no pointers, and `DLG1-STORAGE-DISJOINT?` joins
`FDC1-STORAGE-DISJOINT?`: the neutral and provider boundaries reject caller
storage that overlaps either validator's scratch, and the provider's layout
proof keeps both out of the session.

Admission carries no dialog or button count. A family batch requires
DIALOGS when it holds a dialog or button control or a modal catalog region.
The provider accepts that requirement only when the batch has controls or a
modal region, and gates each dialog or button again at capture, before
copying or accounting, so a terminal without DIALOGS refuses it as
UNSUPPORTED.

Capture copies the label, shortcut and complete DLG1 or BTN1 into owned
storage. The copy costs `160 + align8(label + shortcut + content bytes)`.
Fixed copied-bank checks establish bounded framing; replay validates the
exact owned value, and sending checks a dialog's DLG1 once more, before the
ordinary PT CONTROL writers emit it. A DELTA may replace both kinds, so each
takes a mutable-control ledger entry. PT and the host remain the authorities
on which replacements are allowed: a button's state, label, shortcut and
roles, and a dialog's state and complete content with a newer DLG1 revision,
under a fixed title.
