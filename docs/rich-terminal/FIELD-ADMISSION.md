# Typed FIELD admission

FIELD uses the existing CONTROL lane and its immutable root bounds. It is
not a collection or an instrument. `RTE-CONTROL-FIELD` and
`RTAPT-CONTROL-FIELD` are kind 13. The local `*-F-FIELDS` feature is `0x1000`,
explicitly mapped to APT-1 `0x4000`; it requires CONTROLS, independently of
CONTROL_COLLECTIONS. The payload and complete transaction minima are 176
and 376 bytes. These codecs do not enable a product profile by themselves.

The 200-byte neutral CONTROL record and 160-byte provider copy header retain
their layouts. LABEL is the optional, identity-stable outer label; SHORTCUT
is empty. CONTENT is one exact FDC1 value. CONTENT-ITEMS is its choice count,
CONTENT-UTF8 is the sum of every choice label or the TEXT value, and
CONTENT-RUNS and CONTENT-FIELDS are zero. Each FIELD root consumes one control
and object slot; every choice consumes one additional shared object slot,
including hidden and read-only choices. Displaying an INTEGER stores no
additional guest UTF8. The outer label is charged separately.

`FDC1-VALIDATE ( content-a content-u label-a label-u cols rows -- choices
content-utf8 flag )` derives the content aggregates. Failure returns three
zeros. The helper validates the exact 96-byte header, scalar UTF8, independent
single-line strings, signed integer constraints, unique signed choice values,
current-choice membership, and canonical unused fields. The label and value
rectangles stay within the declared root and do not overlap. There is no
implicit label width, geometry inference, or terminal text editing.

The helper is independent of native UFLD storage and terminal APIs. Its
source-span checks precede scratch stores, and all temporary pointers are
cleared before return. `FDC1-STORAGE-DISJOINT?` lets the neutral and provider
boundaries reject caller storage that overlaps its private scratch. Provider
engine layout proofs also exclude that scratch from session and engine banks.

The checked hybrid admission summary is 384 bytes. FIELD-CONTROLS is appended
at offset 376; it counts FIELD roots independently from collection roots and
item-view roots. The standalone CONTROL preflight callback similarly appends
`field-controls` after `utf8-bytes`. Provider admission reads only these fixed
aggregates. It never traverses the caller control or FDC1 bank.

Capture copies the outer label and complete FDC1 body into owned storage.
Its copy cost is `160 + align8(label bytes + FDC1 bytes)`; its complete frame
cost is `120 + label bytes + FDC1 bytes`. Concrete capture rejects missing
capability before copying or accounting. Fixed copied-bank checks establish
bounded framing; publication and replay validate the exact owned value before
emission through the ordinary PT CONTROL writers. No borrowed source pointer
survives capture. The existing mutable-control ledger accounts for exact
choice and UTF8 deltas during replacement, commit, and abort. PT and the host
remain the immutable identity/geometry and newer-content-revision authorities.

`RTE-INTENT-ADJUST` is 11. The input target callback keeps its existing
`( owner generation id action context -- row col revision found )` contract.
A FIELD target names a cell inside its committed value rectangle. ADJUST
requires the exact positive FDC1 revision and a nonzero signed count, delivered
once through `KEY-MOUSE-FIELD-ADJUST` and `KEY-MOUSE-FIELD-ADJUSTMENT`. It does
not expand into wheel events. ACTIVATE remains an ordinary click; its wire
message has no content revision. Producer acknowledgement and live-state
checks retain authority over that target, while apps own accepted values and
editing.
