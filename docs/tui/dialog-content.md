# DIALOG and BUTTON content lowering

`akashic/tui/dialog-content.f` converts a complete canonical [UDLG
model](dialog-model.md) to DLG1 content and each of its buttons to BTN1
content. It contains no terminal transport, control identity allocation,
or admission policy. The caller publishes the dialog's title as its
CONTROL label, and each button's label as that button's, with their root
metadata.

```forth
UDLGC-DIALOG-BYTES      ( model bytes -- wire-bytes status )
UDLGC-DIALOG-PACK       ( model bytes output-address capacity -- used status )
UDLGC-BUTTON-PACK       ( button output-address capacity -- used status )
UDLGC-STORAGE-DISJOINT? ( address bytes -- flag )
```

`UDLGC-DIALOG-BYTES` and `UDLGC-DIALOG-PACK` validate the whole model. PACK
accepts a nonzero byte-aligned output address apart from the model and the
module's storage, and writes exactly the DLG1 extent; bytes beyond it stay
unchanged. `UDLGC-BUTTON-PACK` writes the eight BTN1 bytes of one button
record of a validated model, checking its roles again.

Statuses are `UDLGC-S-OK=0`, `UDLGC-S-CAPACITY=1` and `UDLGC-S-INVALID=2`.
Refusal returns zero used bytes and writes nothing.

## Exact layouts

DLG1 is the 56-byte header, Python `<IHHQIIiiIIiiII>`, then the message:

| Offset | Field | Type |
|---:|---|---|
| 0 | `UDLGC-DIALOG-TAG = 0x31474C44` (`DLG1`) | u32 |
| 4 | Version 1 | u16 |
| 6 | Flags (NOTICE=1) | u16 |
| 8 | Revision | u64 |
| 16 | Severity | u32 |
| 20 | Message bytes | u32 |
| 24 | Title column, row, width, height | i32, i32, u32, u32 |
| 40 | Message column, row, width, height | i32, i32, u32, u32 |

BTN1 is Python `<IHH>`: `UDLGC-BUTTON-TAG = 0x314E5442` (`BTN1`), version 1
and the roles. The model's key, root size and padding, and each button's
state and slot, belong to the surrounding CONTROL records.

`local_testing/test_dialog_model.py` compares the packed bytes with a
Python byte oracle, has the terminal's own `DLG1-VALIDATE` and
`BTN1-VALIDATE` accept them, and checks short capacity and an output over
the model.
