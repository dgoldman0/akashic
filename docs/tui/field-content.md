# FIELD content lowering

`akashic/tui/field-content.f` converts a complete canonical [UFLD
model](field-model.md) to FDC1 content. It contains no terminal transport,
control identity allocation, or admission policy. The caller separately
publishes the model's outer label and root metadata in CONTROL.

```forth
UFLDC-BYTES             ( model bytes -- wire-bytes status )
UFLDC-PACK              ( model bytes output-address capacity -- used status )
UFLDC-STORAGE-DISJOINT? ( address bytes -- flag )
```

Both conversion operations deeply validate the entire native model, including
strict text, slots, choices, exact extent, and zero padding. BYTES returns the
exact FDC1 extent. PACK accepts a nonzero byte-aligned output address and writes
exactly that extent; bytes beyond it remain unchanged. The source must remain
alive and immutable during the call. No allocation or native pointers appear
in the output.

Statuses are `UFLDC-S-OK=0`, `UFLDC-S-CAPACITY=1`, and
`UFLDC-S-INVALID=2`. Refusal returns zero used bytes and preserves the complete
output bank. CAPACITY covers insufficient output space and content exceeding
the u32 wire extent. Malformed or unsupported native models, null output,
wrapping spans, and prohibited aliases return INVALID.

The entire output capacity must be disjoint from the supplied native model
span and from mutable module storage. Both source and destination spans are
checked before any encoder scratch or output write. The public storage guard
includes the encoder, UFLD, and its USF dependency; callers remain responsible
for disjointness from other live application objects. Public conversion words
use the ordinary module guard when `GUARDED` is enabled.

## Exact FDC1 layout

The 96-byte header (`UFLDC-HEADER-SIZE`) uses explicit little-endian fields,
equivalent to Python `<IHHQIIiiIIiiIIqqqqII>`:

| Offset | Field | Type |
|---:|---|---|
| 0 | `UFLDC-TAG = 0x31434446` (`FDC1`) | u32 |
| 4 | Version 1 | u16 |
| 6 | INTEGER=1, CHOICE=2, TEXT=3 | u16 |
| 8 | Content revision | u64 |
| 16 | Flags (READ_ONLY=1) | u32 |
| 20 | Reserved zero | u32 |
| 24 | Label column, row, width, height | i32, i32, u32, u32 |
| 40 | Value column, row, width, height | i32, i32, u32, u32 |
| 56 | Current numeric value | i64 |
| 64 | Minimum | i64 |
| 72 | Maximum | i64 |
| 80 | Step | i64 |
| 88 | Choice count | u32 |
| 92 | TEXT byte count | u32 |

INTEGER has no body. TEXT appends its exact value bytes, including an empty
value. CHOICE appends records in native semantic order: signed i64 value,
u32 label byte count, reserved u32 zero, then the exact label bytes. Choice
records have a 16-byte header. Duplicate labels remain valid; signed choice
values preserve their identity and order.

There is no body alignment, padding, terminator, or trailing data. Native
outer-label bytes and native padding are omitted. Root key, width, height, and
state belong to the surrounding CONTROL record and are not encoded in FDC1.
Slot geometry, revision, read-only flag, and content are preserved exactly.

`local_testing/test_field_content.py` executes the real native source closure.
Independent Python byte oracles cover all kinds, arbitrary signed choices,
INT64_MIN, UTF-8, empty TEXT, asymmetric slots, flags, and unsigned revisions.
Refusal tests cover short capacity, native corruption, unaligned native input,
and source/destination/module aliases with unchanged output.
