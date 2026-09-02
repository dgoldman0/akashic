# Renderer-neutral UIDL semantic collections

`akashic/tui/semantic-collections.f` defines the native family
payloads for a canonical reusable widget that exposes a `TEXT_AREA`,
`TEXT_GRID`, or `TABSET` with nested `TAB` values. It does not register a provider
or advertise a terminal capability, choose a renderer, or contain APT-1 bytes.
Production applets must not import this module or construct these payloads.

The module owns its entry header, status vocabulary, builders, validators, and
conservative storage-disjoint query, and depends only on UTF-8 and memory-span
utilities. It therefore sits below both the canonical widget library and
UIDL-TUI. `uidl-collection-snapshot.f` freezes direct canonical UIDL textarea
and authored tabset values, plus canonical textareas, text grids, and tabsets
automatically observed below ordinary caller-mounted widget draws. Its
pointer-free descriptor carries UIDL source identity, mounted-source
generation, resolved geometry, and exact ancestry/source clipping. UCTX
attachment identity, selected-region and renderer clipping, revision fences,
admission, and publication remain upper concerns and do not enter this lower
module.

The payload is an aligned, pointer-free snapshot. Its root begins with the
module-owned 32-byte `USCOL` entry header and then carries bounds,
control state, and one family payload. A lower widget source may express those
bounds in its own region coordinates; the upper lifecycle descriptor owns
translation into a selected retained region and effective clipping. A
canonical composite widget may project a tabset and text area as two ordinary
sibling entries. UCSN's source-directory/dense-node work shape permits several
root-keyed entries for one UIDL source. The current producer admits direct
canonical textareas and authored tabsets and automatically discovered mounted
canonical `TXTA`, `TGRID`, and `TAB` widgets. A composed aggregate carries
attachment identity, source revision, and publication/resolved-state fences;
UCSN does not emit that envelope.

## Native layouts

All native fields are eight-byte cells. Every entry and variable member starts
on an eight-byte boundary, and variable text is followed by zero padding.

The common root payload at entry offsets `+32` through `+64` is `(row, column,
height, width, state)`. `TEXT_AREA` and `TEXT_GRID` add, at `+72`, `(flags,
rows, columns, viewport-row, viewport-column, viewport-rows,
viewport-columns, primary-key, anchor-key, primary-scalar-offset,
anchor-scalar-offset, item-count)`. Their first item begins at `+168`.

Each text item has the 64-byte native header `(key, row, column, row-span,
column-span, role, state, text-bytes)` followed by the exact UTF-8 bytes and
zero alignment padding. Items are in `(row, column, key)` order. Keys are
nonzero and globally unique but need not increase as rows or layout change.
ABI 1 requires `row-span = 1` for every item while retaining arbitrary positive
column spans. The downstream STX1 wire format can represent larger row spans.
A later native ABI can add the corresponding general rectangle proof when a
real canonical widget needs it; ABI 1 does not carry that speculative cost.

`TABSET` stores its child count at `+72`; the first tab begins at `+80`. Each
tab has the 40-byte native header `(key, order, state, label-bytes,
shortcut-bytes)`, then its label and shortcut and zero alignment padding. Tab
orders strictly increase; tab keys are independently unique and may appear in
any unsigned-key order.

State values are presentation-independent. `SELECTED` requires `VISIBLE` and
`ENABLED`; a tabset root itself does not admit `SELECTED`; and at most one tab
is selected. Text-item roles are `CONTENT`, `ROW_HEADER`, and `COLUMN_HEADER`.
An item cannot be both `CURRENT` and `UNAVAILABLE`.

`TEXT_AREA` items are state-zero `CONTENT` rows: row span one, column zero,
column span equal to the declared logical columns, and no more than that many
Unicode scalars. Primary and optional anchor keys name carried rows, and their
offsets count Unicode scalars. `TEXT_GRID` permits all three roles and
arbitrary positive in-row column spans, allows at most one `CURRENT` item, and
uses a primary key with zero scalar offsets and no anchor.

## Caller-owned construction

`USCOL-BUILDER-INIT` selects exact measure mode with `(0, 0)` or copy mode with
caller storage. Begin/shape/positions/item/end calls perform only checked size
arithmetic, copy requested bytes, and maintain an exact latched status. They do
not repeat the deep family proof.

The normal contiguous convenience is `USCOL-TEXT-ITEM`. The canonical
gap-buffer-backed textarea source calls
`USCOL-TEXT-ITEM-BEGIN` with the declared text length.
Copy mode returns the exact writable text destination, so two sides of a gap
can be copied directly into the reserved item; measure mode returns zero and
does not dereference source text. `USCOL-TEXT-ITEM-END` completes the item.
The builder zeroes native padding and refuses either item or tab count once it
has reached the interoperable `u32` maximum. There is no smaller collection
cap.

`USCOL-STORAGE-DISJOINT? ( address bytes -- flag )` checks a caller span
against the module's builder, validation, and summary authority before an upper
collector writes it. Zero-length spans use the canonical `(0, 0)` form;
negative, wrapping, or module-overlapping spans fail closed.

## One deep validation authority

`USCOL-VALIDATION-WORK-BYTES ( entry available -- bytes status )` derives
conservative scratch from the fixed item or tab count without prewalking
variable members. Counts below two need no scratch. Either family needs
exactly `8*n` bytes for the independent member-key uniqueness sort.

`USCOL-ENTRY-VALIDATE ( entry available work-a work-u summary -- status )` is
the single deep family authority. It checks exact native extent and padding,
root and viewport bounds, stable keys and canonical order, states and roles,
caret/selection rules, and family shape. Each text span is passed to the
existing `UTF8-VALID?` exactly once; one following byte pass derives scalar
count and rejects disallowed controls without implementing another decoder.
Key uniqueness uses caller scratch and does not impose key order.

Because ABI 1 requires unit-row items, canonical order gives one linear
same-row overlap proof with unrestricted column spans. The validator has no
second rectangle pass, `O(n^2)` fallback, or fixed item limit.

The 48-byte output summary is cleared before ordinary validation failures and
is populated only after the complete entry succeeds. It correlates the exact
frozen native slice by family, root key, entry byte length, child/item count,
and total UTF-8 bytes. It is not a certificate that can be detached from that
slice.

## Frozen STX1 translation

`akashic/tui/rich-terminal/uidl-semantic-content-stx1.f` can translate one
text entry only after an upper owner has deep-validated and frozen it.
The same frozen native entry and summary are required.
Both stay in the same immutable attempt bank. Current RUHA ABI 6 carries the
native collection descriptor/value banks, validates complete frozen slices
before reuse, and supplies them to the generic collection lowerer.
`USSTX-PACK` takes one such entry and exact byte length, its 48-byte summary,
the positive source revision, and a caller-bounded destination. It correlates
family, family ABI, root key, entry length, item count, and disjoint spans in
constant time before touching the destination. A genuine non-text family
returns `UNSUPPORTED`; an adequate but malformed destination or correlation
returns `INVALID`; insufficient storage returns `CAPACITY` without changing
the destination.

For a validated text entry, canonical STX1 length is exactly
`72 + 32*item-count + total-utf8`. The validator overflow-checks that result as
`u32`, and `USCOL-SUMMARY-STX1-BYTES` derives it from the correlated summary
without another item pass. `USSTX-PACK` writes canonical little-endian fields,
writes the already-proved ABI-1 row span as one, omits native alignment
padding, and performs one item/text-copy walk with remaining-byte cursors. It
does not call `USCOL-ENTRY-VALIDATE`, decode UTF-8, sort keys, or repeat the
geometry, caret, state, uniqueness, and overlap proofs. The caller's freeze is
therefore part of the authority boundary; the packer is not safe evidence for
a summary detached from or raced against its source entry.

The destination STX1 tag stays zero until cursor, item-count, total-UTF-8, and
exact output-length accounting agree. The final tag write follows the last
fallible operation. The content revision is the positive source revision
carried by the enclosing record, not a new packer counter.
Packing must not repeat UTF-8, key, geometry, caret, or overlap proofs already
bound to the frozen entry and summary.

For a tabset, the current generic lowerer emits one bounded root plus its
ordered tab children using their copied label, shortcut, and state. That upper
adapter and its capability/admission policy remain outside this lower
family-module contract.

The selected `desktop-apt1` source/profile now carries all four collection
kinds through RUHA, generic lowering, and the retained control path. Their
ordinary Pad/Daybook journey and acknowledgement-bound Pad tab activation
passed the local X11 boundary at Akashic `4b6a475` with MegaPad `29bdfd6`;
`local_testing/evidence/rich-desktop-full-vertical-acceptance-20260902.md`
records the evidence. This lower module and its focused selectors remain
implementation evidence only, not a substitute for that journey.

## Public entry points

- `USCOL-S-*`, `USCOL-STATUS-VALID?`, and the `USCOL-ENTRY-*` accessors define
  the lower status and entry vocabulary.
- Layout/accessor constants use the `USCOL-*` prefix.
- `USCOL-TEXT-ITEM-BYTES` and `USCOL-TAB-BYTES` return checked aligned native
  member sizes.
- `USCOL-BUILDER-INIT`, the `USCOL-TEXT-*` and `USCOL-TAB*` words, and
  `USCOL-BUILDER-FINISH` implement caller-owned measure/copy construction.
- `USCOL-VALIDATION-WORK-BYTES` and `USCOL-ENTRY-VALIDATE` size and perform the
  one deep proof.
- `USCOL-STORAGE-DISJOINT?` protects the module-owned construction and
  validation authority from caller-bank aliases.
- `USCOL-SUMMARY-*` accessors and `USCOL-SUMMARY-STX1-BYTES` expose only the
  correlated post-validation facts the aggregate planner needs.
- `USSTX-PACK` in the rich-terminal translator consumes those frozen facts and
  emits one exact canonical STX1 value without becoming a second validator.
