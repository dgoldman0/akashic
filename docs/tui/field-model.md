# Canonical typed FIELD model

`akashic/tui/field-model.f` defines `UFLD`, a caller-owned, pointer-free value
for ordinary INTEGER, CHOICE, and TEXT fields. It contains no terminal API or
wire framing. A widget may borrow a completed model; the caller must keep its
bytes alive and immutable for that borrow. Build a replacement in a separate
bank before rebinding.

## Native ABI 1

`UFLD-HEADER-SIZE` is 192 bytes. Each header field occupies one native 64-bit
cell. The model base and every completed extent are aligned to eight bytes.
Keys and revisions are nonzero unsigned values. Numeric field and choice
values are signed 64-bit integers.

| Offset | Field | Constraint |
|---:|---|---|
| 0 | bytes | Exact complete native extent |
| 8 | ABI | `UFLD-ABI = 1` |
| 16 | key | Nonzero stable application key |
| 24 | kind | INTEGER=1, CHOICE=2, TEXT=3 |
| 32 | revision | Nonzero application content revision |
| 40 | width | Positive u32 root width |
| 48 | height | Positive u32 root height |
| 56 | state | VISIBLE=1, ENABLED=2, SELECTED=4 |
| 64 | flags | READ_ONLY=1; other bits zero |
| 72 | label row | Nonnegative i32 |
| 80 | label column | Nonnegative i32 |
| 88 | label height | u32 |
| 96 | label width | u32 |
| 104 | value row | Nonnegative i32 |
| 112 | value column | Nonnegative i32 |
| 120 | value height | Positive u32 |
| 128 | value width | Positive u32 |
| 136 | value | Signed integer or selected choice value; zero for TEXT |
| 144 | minimum | Signed INTEGER lower bound; otherwise zero |
| 152 | maximum | Signed INTEGER upper bound; otherwise zero |
| 160 | step | Positive signed INTEGER step; otherwise zero |
| 168 | label bytes | u32 outer-label byte count |
| 176 | text bytes | u32 TEXT byte count; otherwise zero |
| 184 | choice count | Positive u32 for CHOICE; otherwise zero |

SELECTED requires VISIBLE and ENABLED. READ_ONLY may coexist with selection;
interaction policy belongs to the ordinary widget/application.

Both slots are relative to the root. Exact mathematical endpoints must be
contained in the root, and slots may touch but must not overlap. A nonempty
outer label requires positive label extents. An empty label requires all four
label coordinates/extents to be zero. The value slot always has positive
extents, even for empty TEXT.

The body begins with the exact outer label bytes followed by zero padding to
an eight-byte boundary. INTEGER ends there. TEXT appends its exact value bytes
and zero padding to eight bytes. CHOICE appends records in semantic order:

| Record offset | Field |
|---:|---|
| 0 | Exact record bytes, including header and padding |
| 8 | Signed choice value |
| 16 | Positive u32 label byte count |
| 24 | Exact choice label, followed by zero pad8 |

Choice values are unique; duplicate display labels are allowed. The current
value must match exactly one choice. Choice values are identities, never array
indices. INTEGER requires `minimum <= value <= maximum` and `step > 0`;
current values need not be aligned to the step. TEXT requires zero numeric
fields and zero choice count.

All strings use `USF-TEXT?`: well-formed Unicode-scalar UTF-8, excluding C0,
DEL, C1, U+2028, and U+2029. No implicit display projection occurs. Validation
checks every exact byte count and every padding byte; trailing bytes are
invalid. Counts are bounded by the supplied extent before record traversal.
Choice uniqueness validation uses a bounded quadratic scan and needs no
caller workspace or allocation.

## Construction

`UFLD-BUILDER-SIZE` is 40 bytes: destination at 0, capacity at 8, used bytes at
16, phase at 24, and reserved zero at 32. The aligned builder and destination
must be separate caller storage. A real nonzero aligned destination is required;
capacity need not be aligned and may be too small to begin.

```forth
UFLD-BUILDER-INIT ( dst cap builder -- status )
UFLD-BEGIN        ( key kind revision width height state flags builder -- status )
UFLD-SLOTS        ( lr lc lh lw vr vc vh vw builder -- status )
UFLD-LABEL        ( address bytes builder -- status )
UFLD-INTEGER      ( value minimum maximum step builder -- status )
UFLD-TEXT         ( address bytes builder -- status )
UFLD-CHOICE-VALUE ( value builder -- status )
UFLD-CHOICE       ( value label-address label-bytes builder -- status )
UFLD-FINISH       ( builder -- bytes status )
```

The sequence is INIT (phase 0), BEGIN (phase 1), SLOTS, LABEL (phase 2), then
one kind-specific content operation (phase 3). Call LABEL with `0 0` for an
empty label. SLOTS may be replaced while phase 1 remains active. For CHOICE,
CHOICE-VALUE starts content and repeated CHOICE calls append records. The
current value may be absent while building, but FINISH rejects an empty choice
list or a missing current value. FINISH validates the complete result and does
not seal or allocate storage. Its returned extent is zero on refusal.

Every refused builder operation preserves the destination and builder bytes.
Shape, phase, capacity, string validity, and overlap checks precede writes.
Text inputs cannot overlap any part of the destination capacity, the builder,
or either UFLD/USF module's mutable storage. Successful INIT changes only the
builder, BEGIN writes the fixed header, and later calls append only their
owned content. An unfinished model is not valid for widget binding.

Statuses are `UFLD-S-OK=0`, `UNSUPPORTED=1`, `CAPACITY=2`, and `INVALID=3`.
Unknown ABI or kind returns UNSUPPORTED; malformed state, flags, geometry,
strings, phases, aliases, or noncanonical fields return INVALID.

## Validation and access

```forth
UFLD-VALIDATE         ( model bytes -- status )
UFLD-STORAGE-DISJOINT? ( address bytes -- flag )
UFLD-LABEL@           ( model -- address bytes )
UFLD-TEXT@            ( model -- address bytes )
UFLD-CHOICE-FIRST     ( model -- record )
UFLD-CHOICE-NEXT      ( record -- next )
UFLD-CHOICE-VALUE@    ( record -- signed-value )
UFLD-CHOICE-LABEL@    ( record -- address bytes )
UFLD-CHOICE-SELECTED@ ( model -- record|0 )
UFLD-UTF8-BYTES@      ( validated-model -- bytes )
```

Every header field has `UFLD-NAME-OFFSET` and `UFLD-NAME@` words; the public
slot spelling uses `COLUMN`. Accessors require a validated model/record and
do not repeat validation. SELECTED@ returns zero for a non-CHOICE model.
UTF8-BYTES@ sums the outer label, TEXT value, and all choice labels, excluding
native headers and padding. Its validated-model precondition bounds the sum.
Storage-disjoint checks protect UFLD and its USF dependency's module storage;
callers remain responsible for disjointness from other live objects.

## Shared ordinary adjustment policy

```forth
UFLD-INTEGER-CLAMP ( value min max step signed-adjustment -- result status )
UFLD-CHOICE-WRAP   ( signed-adjustment model bytes -- value status )
```

INTEGER-CLAMP rejects an invalid initial range or nonpositive step. It multiplies
the unsigned magnitude of the signed adjustment by step with `UM*`, then
saturates against the unsigned distance to the selected bound. This includes
INT64_MIN adjustments and the full signed range without overflow or a repeated
step loop. A zero adjustment preserves the current value.

CHOICE-WRAP validates the complete model and kind, finds the current semantic
index, reduces the full signed adjustment modulo the positive choice count,
and returns the signed value at the resulting index. It never changes the
model and never treats a choice value as an index. Helpers return zero result
on refusal. Public mutators, validation, and adjustment helpers use the ordinary
module guard when `GUARDED` is enabled.

`local_testing/test_field_model.py` executes the real native source dependency
closure. It checks byte layout, geometry, strict text, exact padding/extent,
atomic refusal, cross-module aliases, semantic choice order, and signed integer
extremes. Its runtime helper is reusable by ordinary FIELD widget tests.
