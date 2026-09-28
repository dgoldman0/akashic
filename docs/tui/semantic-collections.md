# Renderer-neutral UIDL semantic collections

`akashic/tui/semantic-collections.f` defines the native family
payloads for a canonical reusable widget that exposes a `TEXT_AREA`,
`TEXT_GRID`, `TABSET` with nested `TAB` values, or `ITEM_VIEW` (a list, tree,
table, sections, or cards). It does not register a provider
or advertise a terminal capability, choose a renderer, or contain APT-1 bytes.
Production applets must not import this module or construct these payloads.

The module owns its entry header, status vocabulary, builders, validators, and
conservative storage-disjoint query, and depends only on UTF-8, the text
meanings of [text-style](../text/text-style.md), and memory-span utilities. It therefore sits below both the canonical widget library and
UIDL-TUI. `uidl-collection-snapshot.f` freezes direct canonical UIDL textarea
and authored tabset values, plus canonical textareas, text grids, tabsets,
lists, and trees automatically observed below ordinary caller-mounted widget
draws. Its
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
canonical `TXTA`, `TGRID`, `TAB`, `LST`, and `TREE` widgets. A list captures
as a `LIST` item view, a `TABLE` when it has several columns or a label,
`SECTIONS` when its first row is a section heading, or `CARDS` in card mode,
with any style runs its style source gives, and a tree as a `TREE` item view
(see [list](widgets/list.md) and [tree](widgets/tree.md)). A composed aggregate carries
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

Each text item has the 72-byte native header `(key, row, column, row-span,
column-span, role, state, text-bytes, run-count)` followed by the exact UTF-8
bytes, zero alignment padding, and then `run-count` style runs of three cells
each, `(start, length, meaning)`. A run says what `length` scalars of the
text from scalar `start` mean, as one of the ten meanings of
[text-style](../text/text-style.md); a character takes the meaning of the
run over its first scalar. Items are in `(row, column, key)` order. Keys are
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

`ITEM_VIEW` carries the item-view value of SEMANTIC-CONTENT-1 (ITM1), and
its roles, item roles, column kinds, and item states have the ITM1 values. At
`+72` it stores `(role, flags, column-count, item-total, viewport-first,
viewport-count, item-count)`; flag bits 0 and 1 hold the paragraph direction.
Its first column begins at `+128`. A column has the 16-byte header `(kind,
label-bytes)` and its label padded to eight. The carried items follow the last
column. An item has the 56-byte header `(key, parent, ordinal, depth, state,
role, field-count)` and then its fields. A field has the 16-byte header
`(text-bytes, run-count)`, its text padded to eight, and its style runs, the
same three-cell runs a text item carries.

The item total counts every item in the view's order, carried or not. The
view carries every ordinal in its viewport and the selected item, in
increasing ordinal order, so a long list costs only what it shows. Keys are
nonzero and unique, and an item is not its own parent. At most one item is
selected and at most one is current, and an unavailable item is not selected.
An expanded item is expandable and a checked item is checkable. Each item has
between one field and one per column. `LIST`, `TABLE`, and `CARDS` hold only
top-level items that cannot expand. In a `TREE` an item has a parent exactly
when its depth is above zero, and a carried parent is expanded and one level
shallower. In `SECTIONS` a section has no parent, no state, and one field,
and every other item has depth one and names a section. Between neighbouring
ordinals the order is preorder: ordinal zero has depth zero, and the depth
rises by at most one, to a child of the item before. A carried parent always
comes earlier in the order.

State values are presentation-independent. `SELECTED` requires `VISIBLE` and
`ENABLED`; a tabset root itself does not admit `SELECTED`; and at most one tab
is selected. Text-item roles are `CONTENT`, `ROW_HEADER`, and `COLUMN_HEADER`.
An item cannot be both `CURRENT` and `UNAVAILABLE`.

`TEXT_AREA` items are state-zero `CONTENT` rows: row span one, column zero,
column span equal to the declared logical columns, which count cells, and no
wider than that many cells, each character taking its width by the shared
text rules (`GR-SWIDTH`, [grapheme](../text/grapheme.md)). Primary and
optional anchor keys name carried rows, and their offsets count Unicode
scalars. Their style runs are in start order, lie within the text, do not
overlap, and never touch another run with the same meaning, so every styling
has one encoding. `TEXT_GRID` permits all three roles and
arbitrary positive in-row column spans, allows at most one `CURRENT` item,
uses a primary key with zero scalar offsets and no anchor, and carries no
style runs.

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
does not dereference source text. `USCOL-TEXT-ITEM-RUN ( start length meaning
builder -- status )` then appends the item's style runs in order, and
`USCOL-TEXT-ITEM-END` completes the item.
The builder zeroes native padding and refuses a text item, tab, or view item
count once it has reached the interoperable `u32` maximum. There is no smaller
collection cap.

An item view is `USCOL-ITEMS-BEGIN`, `USCOL-ITEMS-SHAPE ( role flags total
first count builder -- status )`, one `USCOL-ITEMS-COLUMN ( kind label-a
label-u builder -- status )` per column, its items, and `USCOL-ITEMS-END`. An
item is `USCOL-ITEMS-ITEM-BEGIN ( key parent ordinal depth state role builder
-- status )`, its fields, and `USCOL-ITEMS-ITEM-END`. A field is
`USCOL-ITEMS-FIELD ( text-a text-u builder -- status )`, or
`USCOL-ITEMS-FIELD-BEGIN ( text-u builder -- text-dst|0 status )`, its text
copied to the returned destination, `USCOL-ITEMS-FIELD-RUN` for each style
run, and `USCOL-ITEMS-FIELD-END`. A source therefore walks only the items it
carries, never the whole order.

`USCOL-STORAGE-DISJOINT? ( address bytes -- flag )` checks a caller span
against the module's builder, validation, and summary authority before an upper
collector writes it. Zero-length spans use the canonical `(0, 0)` form;
negative, wrapping, or module-overlapping spans fail closed.

## One deep validation authority

`USCOL-VALIDATION-WORK-BYTES ( entry available -- bytes status )` derives
conservative scratch from the fixed item or tab count without prewalking
variable members. Counts below two need no scratch. Text and tab families need
exactly `8*n` bytes for the independent member-key uniqueness sort. An item
view needs `16*n` bytes: a key and an item address per carried item, sorted
once for uniqueness and then searched for each carried parent.

Producers publish an application's text as CELL shows it, with
`UTF8-SAFE-BYTES` and `UTF8-SAFE-COPY` from [utf8](../text/utf8.md): each
ill-formed unit, each C0 control but a TAB the family allows (text areas and
grids), and DEL become U+FFFD, so the text is valid and has one scalar for
each unit of the source. `USCOL-TEXT-ITEM`, `USCOL-ITEMS-FIELD` and
`USCOL-TAB` copy their text this way. Producers that fill a destination
themselves (the text area and list) use the same words, count caret
positions with `UTF8-UNIT-INDEX`, and take style runs from `TSTY-RUNS`, which
counts the same units. This module itself never decodes; validation's single
`UTF8-VALID?` check stays the one encoding proof.

`USCOL-ENTRY-VALIDATE ( entry available work-a work-u summary -- status )` is
the single deep family authority. It checks exact native extent and padding,
root and viewport bounds, stable keys and canonical order, states and roles,
caret/selection rules, style runs, and family shape. Each text span is passed to the
existing `UTF8-VALID?` exactly once; one following byte pass derives scalar
count and rejects disallowed controls without implementing another decoder.
Key uniqueness uses caller scratch and does not impose key order.

Because ABI 1 requires unit-row items, canonical order gives one linear
same-row overlap proof with unrestricted column spans. The validator has no
second rectangle pass, `O(n^2)` fallback, or fixed item limit.

The 64-byte output summary is cleared before ordinary validation failures and
is populated only after the complete entry succeeds. It correlates the exact
frozen native slice by family, root key, entry byte length, child/item count,
total UTF-8 bytes, total style runs, and total fields. For an item view the
child count is the column count, and the UTF-8 total counts labels and fields.
It is not a certificate that can be detached from that slice.

## Frozen STX1 translation

`akashic/tui/rich-terminal/uidl-semantic-content-stx1.f` can translate one
text entry only after an upper owner has deep-validated and frozen it.
The same frozen native entry and summary are required.
Both stay in the same immutable attempt bank. Current RUHA ABI 6 carries the
native collection descriptor/value banks, validates complete frozen slices
before reuse, and supplies them to the generic collection lowerer.
`USSTX-PACK` takes one such entry and exact byte length, its 64-byte summary,
the positive source revision, and a caller-bounded destination. It correlates
family, family ABI, root key, entry length, item count, and disjoint spans in
constant time before touching the destination. A genuine non-text family
returns `UNSUPPORTED`; an adequate but malformed destination or correlation
returns `INVALID`; insufficient storage returns `CAPACITY` without changing
the destination.

For a validated text entry, canonical STX1 length is exactly
`72 + 36*item-count + total-utf8 + 12*total-runs`. The validator overflow-checks that result as
`u32`, and `USCOL-SUMMARY-STX1-BYTES` derives it from the correlated summary
without another item pass. `USSTX-PACK` writes canonical little-endian fields,
writes the already-proved ABI-1 row span as one, omits native alignment
padding, and performs one item/text/run-copy walk with remaining-byte cursors. It
does not call `USCOL-ENTRY-VALIDATE`, decode UTF-8, sort keys, or repeat the
geometry, caret, state, uniqueness, and overlap proofs. The caller's freeze is
therefore part of the authority boundary; the packer is not safe evidence for
a summary detached from or raced against its source entry.

The destination STX1 tag stays zero until cursor, item-count, total-UTF-8,
total-run, and exact output-length accounting agree. The final tag write follows the last
fallible operation. The content revision is the positive source revision
carried by the enclosing record, not a new packer counter.
Packing must not repeat UTF-8, key, geometry, caret, or overlap proofs already
bound to the frozen entry and summary.

## Frozen ITM1 translation

`akashic/tui/rich-terminal/uidl-semantic-items-itm1.f` translates one frozen,
deep-validated item view in the same way. `USITM-PACK ( entry entry-bytes
summary source-revision destination capacity -- bytes status )` correlates the
summary with the entry in constant time, refuses another family as
`UNSUPPORTED`, and returns `CAPACITY` without touching a destination that is
too small. Canonical ITM1 length is exactly
`40 + 8*column-count + 32*item-count + 8*field-count + total-utf8 +
12*total-runs`, which the validator checks as `u32` and
`USCOL-SUMMARY-ITM1-BYTES` derives from the summary. The packer omits native
padding and walks the columns, items, fields, and runs once. The ITM1 tag is
written last, after every count agrees, and the packer repeats none of the
validation's proofs.

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
- `USCOL-TEXT-ITEM-BYTES`, `USCOL-TAB-BYTES`, `USCOL-COLUMN-BYTES`, and
  `USCOL-FIELD-BYTES` return checked aligned native member sizes.
- `USCOL-BUILDER-INIT`, the `USCOL-TEXT-*`, `USCOL-TAB*`, and `USCOL-ITEMS-*`
  words, and `USCOL-BUILDER-FINISH` implement caller-owned measure/copy
  construction.
- `USCOL-VALIDATION-WORK-BYTES` and `USCOL-ENTRY-VALIDATE` size and perform the
  one deep proof.
- `USCOL-STORAGE-DISJOINT?` protects the module-owned construction and
  validation authority from caller-bank aliases.
- `USCOL-SUMMARY-*` accessors, `USCOL-SUMMARY-STX1-BYTES`, and
  `USCOL-SUMMARY-ITM1-BYTES` expose only the correlated post-validation facts
  the aggregate planner needs.
- `USSTX-PACK` and `USITM-PACK` in the rich-terminal translators consume those
  frozen facts and emit one exact canonical STX1 or ITM1 value without
  becoming a second validator.
