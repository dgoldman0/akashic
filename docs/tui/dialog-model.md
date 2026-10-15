# Canonical DIALOG model

`akashic/tui/dialog-model.f` defines `UDLG`, a caller-owned, pointer-free
value for a dialog as it is shown: its title, its message lines, its
meaning and its buttons, each in a slot of cells. It contains no terminal
API or wire framing. The [dialog widget](widgets/dialog.md) writes one with
`DLG-MODEL-CAPTURE`; [dialog content](dialog-content.md) lowers it to the
DLG1 and BTN1 content a renderer takes.

## Native ABI 1

`UDLG-HEADER-SIZE` is 160 bytes. Each header field occupies one native
64-bit cell. The model base and its extent are aligned to eight bytes.

| Offset | Field | Constraint |
|---:|---|---|
| 0 | bytes | Exact complete native extent |
| 8 | ABI | `UDLG-ABI = 1` |
| 16 | key | Nonzero identity of the dialog |
| 24 | revision | Nonzero; new whenever the title, message, meaning or slots change |
| 32 | width | Positive u32 root width |
| 40 | height | Positive u32 root height |
| 48 | flags | NOTICE=1; other bits zero |
| 56 | severity | 0 to 4: neutral, info, success, warning, error |
| 64 | title slot | Row, column, height, width |
| 96 | message slot | Row, column, height, width |
| 128 | title bytes | u32 |
| 136 | message bytes | u32, line feeds included |
| 144 | button count | u32; zero for a notice |
| 152 | reserved | Zero |

A slot is absent, all four cells zero, or present: a nonnegative origin
and positive extents inside the root. The title's slot is present exactly
when it has text, as is the message's. No two slots meet.

The body is the title, then the message, each padded with zeros to eight
bytes, then one record a button:

| Record offset | Field |
|---:|---|
| 0 | Exact record bytes, 64 and the padded label |
| 8 | Roles: DEFAULT=1, CANCEL=2, DESTRUCTIVE=4 |
| 16 | State: VISIBLE=1, ENABLED=2, SELECTED=4 |
| 24 | Slot: row, column, height, width |
| 56 | Label bytes, positive u32 |

The title and every label are clean single-line text. The message is the
lines the dialog shows, joined by line feeds; each line is empty or clean
single-line text, and there are no more lines than the message slot has
rows. At most one button is the default and one the cancel button, and
none is destructive and the default. At most one is selected, and only a
visible enabled one. `UDLG-UTF8-BYTES@` counts the title, the message and
every label.

## Words

```forth
UDLG-VALIDATE           ( model bytes -- status )
UDLG-STORAGE-DISJOINT?  ( address bytes -- flag )
UDLG-TEXT-BYTES         ( title-u message-u -- bytes )
UDLG-BUTTON-BYTES       ( label-u -- bytes )
UDLG-START   ( key revision width height flags severity model -- )
UDLG-TITLE!  ( row col height width a u model -- )
UDLG-MESSAGE-SLOT! ( row col height width model -- )
UDLG-LINE+   ( a u model -- )
UDLG-BUTTON+ ( row col height width roles state a u model -- )
```

A writer measures the model with `UDLG-TEXT-BYTES` and one
`UDLG-BUTTON-BYTES` a button, owns that many aligned bytes, and writes in
order: `UDLG-START`, the title, the message slot and its lines, then the
buttons. The writers keep `bytes` at the end of what is written and check
nothing; `UDLG-VALIDATE` proves the result. Accessors (`UDLG-TITLE@`,
`UDLG-MESSAGE@`, `UDLG-BUTTON-FIRST`, `UDLG-BUTTON-NEXT` and the field
readers) require a validated model.

Statuses are `UDLG-S-OK=0`, `UDLG-S-UNSUPPORTED=1` for another ABI,
`UDLG-S-CAPACITY=2` and `UDLG-S-INVALID=3`. The validator keeps its scratch
apart from the model it reads: a model overlapping that scratch, or the
status-field model's, is invalid.

`local_testing/test_dialog_model.py` builds and reads back a canonical
value, refuses each noncanonical cell and byte, and checks a dialog with
buttons alone and a notice.
