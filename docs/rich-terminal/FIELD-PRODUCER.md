# FIELD publication from ordinary widgets

The hybrid producer lowers canonical, mounted `UFLD` models from the immutable
`UFLSN` / `RUHA` snapshot into genuine `RTE-CONTROL-FIELD` records. The ordinary
widget remains the source of the label rectangle, value rectangle, value,
choice values, flags, and positive content revision. Applications do not call
terminal APIs, and the producer does not invent collection records or infer
fields from painted text.

`RTHP-STORAGE-BYTES` and `RTHP-INIT` take a caller-selected
`max-field-native` argument immediately after `max-status-native`. The bound
is zero or an aligned unsigned 32-bit byte count; zero selects no FIELD bank.

For FIELD native capacity `N`, the constructor reserves `floor(N / 192)`
source descriptors and control roots. Each descriptor occupies 128 bytes.
The independent native source bank occupies `N` bytes. The shared control
text bank grows by `N`: native headers and padded choice records are larger
than the exact 96-byte FDC1 header and unpadded 16-byte choice records, so this
bound covers the copied outer labels and complete encoded values. Control,
correlation, target, claim, event, and projection workspaces derive from the
resulting maximum control count. The owner reservation conservatively adds
`floor(N / 24)` possible choice slots; concrete admission uses the exact
number of choices. Choices consume shared object slots without consuming
control IDs or extra control operations.

The producer record is 4144 bytes. Its inline admission
record is 456 bytes at offset 1760. The packed target header is 336 bytes;
FIELD root, choice, and UTF8 totals remain at offsets 240, 248, and 256.
Each target entry is
48 bytes: ID, row, column, kind, revision, and accepted-intent bit mask.

Source descriptors and native bytes are copied into independent bounded
storage. Missing FIELD capability or insufficient local capacity omits the
entire source lane before it creates IDs, text, or claims. Invalid source
extents remain invalid even when the capability is absent. Lowering deeply
validates each native model and preserves its exact authored slots. An
optional empty label has the canonical null-address/zero-length shape.

Admitted FIELD controls form a suffix after menus and collections. The shared
plan derives its record extent from the committed aggregate CONTROL-COUNT,
including the FIELD suffix; stripping restores the exact prefix extent. Their
IDs precede instruments, static status fields, and residual glyphs. Each
visible, fully contained FIELD claims its complete root rectangle. Hidden,
partly clipped, or out-of-bounds roots remain on the ordinary path. Mounted
relation identity supplies the claim subkey; the independent native model
key is retained in correlation scope. Two instances may therefore share a
native key without sharing publication identity.

There is no final-writer proof for overlapping semantic roots. Overlap
between FIELD roots removes the whole optional FIELD lane. Overlap with a
previously admitted family, or with a later instrument claim, refuses the
rich candidate; the existing blank/reveal protocol retires any old rich
owner before exposing CELL content. Local capacity and provider quota
fallback restore the exact control, text, and claim prefixes. A refused
FIELD lane stays refused throughout that candidate's later family retries.

Packed acknowledgement banks own both the outer label and complete FDC1
bytes. Packing and unchanged cloning rebase all pointers into their own
banks. A change only to the SELECTED state bit uses one CONTROL-REPLACE while
preserving the exact label, shortcut, FDC1 bytes, revision, geometry, and
content accounting. This allows ordinary selection movement to retain an
unchanged SERIES/WAVEFORM graph. Other FIELD state changes, or changes to
label, value, revision, slots, membership, or identity, still require complete
owner replacement. FIELD semantic content does not use the collection
content-delta path.

Return coordinates identify the first cell of the declared value rectangle,
which may be offset within the root. Disabled and read-only fields produce
no input target. Editable TEXT accepts ACTIVATE; INTEGER and CHOICE also
accept ADJUST. `RTHP-CONTROL-TARGET@` returns the revision from that field's
acknowledged FDC1 value, not the bank-wide source epoch. Owner, generation,
draw, identity, and intent checks precede the return. The ordinary input
bridge and widget additionally check the current application revision before
consuming an adjustment; immutable publication alone cannot authorize a
second stale queued action after the first action changes live state.

`local_testing/test_rich_field_producer.py` executes the production lowering,
source import, fixed audit, packing, cloning, delta comparison, and target
lookup words on Python and native executors, and compiles the full producer
dependency closure in the native runtime. The focused target tests replace
only the outer constructor-validity hook; actual packed-bank authority and
target lookup are exercised. Existing STATUS, instrument, glyph, blank/reveal,
and control-map suites remain regression coverage for the shared paths.

Sparse DATA_GRAPHICS regions can cover a whole pane even when their individual
instruments occupy disjoint cells. A region's pointer barrier follows painter
order, so the shared CONTROL/STATIC/GLYPH region now uses
`max(0, max(instrument-region Z) + 1)`. Instrument regions keep their authored
relative order. Every instrument claim must be disjoint from the earlier
control claim prefix; static claims already check all prior families and
residual glyphs exclude all claimed cells. An overlap or exhausted signed
32-bit Z range refuses the rich candidate through the ordinary fallback.
This derived base Z is shared by all three plans, checked admission and
emission, with no producer ABI growth. Packed instrument-region equality
also preserves the derived order across delta reuse and unchanged cloning.
