# Shared region catalog and bounded family batches

`tui/rich-terminal/region-catalog.f` is an additive, renderer-neutral ABI1.
It lets multiple ordinary documents and shell bands retain their actual
region membership. Existing CONTROL, GLYPH, INSTRUMENT, STATIC, SERIES and
legacy hybrid plan layouts remain unchanged. The catalog supplies one
owner/generation and one surface geometry for a complete immutable batch.

`RTE-FAMILY-BATCH-VALID?` proves source shape and authority, region geometry,
exact payload coverage, item membership and pane references. It does **not**
authorize publication. The aggregate admission layer must also validate each
family's full semantics and hierarchy, global object identity, SERIES/WAVEFORM
references, negotiated features and total transaction limits before calling a
provider. A valid shape alone cannot bypass that layer.

## Fixed layouts

All fields are native 64-bit cells. Headers, items, references and sample banks
are aligned to eight bytes. Display bytes may be byte-aligned. No allocation,
implicit product cap, or external work bank is used.

The 56-byte `RTE-REGION-CATALOG-SIZE` header uses `_RTE-RC.*` accessors:

| Offset | Field |
|---:|---|
| 0, 8 | OWNER, GENERATION; both nonzero |
| 16, 24 | SURFACE-COLS, SURFACE-ROWS; positive u32 |
| 32, 40 | REGIONS-A, REGIONS-U |
| 48 | RESERVED; zero |

Rows use the existing 96-byte `_RTE-IR.*` schema. IDs are strictly increasing
unsigned nonzero values. Every row has valid signed origin/Z, positive u32
logical dimensions, canonical flags/clip, and zero reserved cell. Explicit
clips are surface-relative and contained in both surface and logical region.
An empty catalog has the canonical `(0,0)` row span; a SERIES-only batch needs
no invented region.

The 72-byte `RTE-FAMILY-BATCH-SIZE` header uses `_RTE-FB.*`:

| Offset | Field |
|---:|---|
| 0 | ABI; 1 |
| 8, 16 | CATALOG-A, CATALOG-U; exactly 56 bytes |
| 24, 32 | FAMILIES-A, FAMILIES-U; positive multiple of 64 |
| 40, 48, 56 | ATTEMPT, SOURCE-GENERATION, SURFACE-GENERATION; nonzero |
| 64 | RESERVED; zero |

Each 64-byte `RTE-FAMILY-ENTRY-SIZE` record uses `_RTE-FE.*`:

| Offset | Field |
|---:|---|
| 0 | KIND |
| 8, 16 | PLAN-A, PLAN-U; exact fixed header extent |
| 24, 32 | BYTES-A, BYTES-U; exact dense display/content or sample bytes |
| 40, 48 | REFS-A, REFS-U; GLYPH only, otherwise `(0,0)` |
| 56 | RESERVED; zero |

| Kind constant | Value | Plan bytes | Item bytes |
|---|---:|---:|---:|
| `RTE-FAMILY-CONTROL` | 1 | 144 | 200 |
| `RTE-FAMILY-GLYPH` | 2 | 144 | 120 |
| `RTE-FAMILY-INSTRUMENT` | 3 | 72 | 216 |
| `RTE-FAMILY-STATIC` | 4 | 144 | 176 |
| `RTE-FAMILY-SERIES` | 5 | 48 | 88 |
| `RTE-FAMILY-PANE` | 6 | 144 | 184 |

PANE uses the CP/SP-compatible 144-byte region-and-items header with genuine
184-byte PANE items. No STATIC item casting is performed. INSTRUMENT retains
its separate copied region subset. Each common embedded region or instrument
region copy must match exactly one catalog row. All plans must match the
catalog's owner, generation and surface. Items must name their plan's region
and match its root dimensions. Instrument items must name a member of their
plan's authenticated region subset.

## Payload and source authority

Each family's positive item bank is independently bounded. CONTROL bytes are
label, shortcut and canonical content in item order. STATIC bytes are label
then value. PANE bytes are titles; INSTRUMENT bytes are units. GLYPH references
are exact dense offset/length pairs matching each item's text capacity.
SERIES bytes are complete uniform i64 values or explicit `(u64 time,i64 value)`
pairs; `SAMPLES-U` is a byte length, and its mode alignment and exact dense
extent are checked directly. Empty borrowed
strings/sample spans must be `(0,0)`. No trailing bytes or containing capacity
can stand in for the used payload. Launcher action bytes belong in a separate
producer correlation bank and are not display payload.

All reachable fixed and variable source spans are checked against module and
engine admission scratch before the first scratch write. Used spans are
pairwise disjoint, including catalog, family vector, plan/item headers,
instrument region copies and payload banks. Adjacent exact slices of one
allocation are allowed. A span that starts at or after the end of every
earlier nonempty span cannot overlap any of them, so only a span that starts
earlier is compared with each earlier span; a batch packed in span order,
such as a frozen copy, is checked in one pass. Caller bytes remain unchanged on success and refusal.
The complete batch and all referenced bytes remain immutable for the dynamic
extent of validation/admission/publication copying.

## Pane reference proof

`RTE-PANE-VALID?` checks the strict 184-byte neutral leaf: nonzero identities,
standard kind, zero parent/reserved, canonical visible/focused flags, focused
implies visible, i32 origin/Z, positive u32 bounds, contained positive content
slot, distinct nonzero chrome/content regions, and clean canonical UTF-8 title.
It does not require a title row: metadata may exist when content starts at row
zero. Signed outer origins are valid.

The batch checks that each pane's content region exists in the same catalog,
has an explicit clip, and paints after its chrome region under `(Z, unsigned
ID)` ordering. A nonempty clip must fit the pane's absolute content slot;
a canonical empty clip is valid. Only one pane can reference a content region.
A pane reference legitimately accounts for an explicitly empty content region.
Rows neither used by actual items nor referenced as pane content are rejected
as orphans. Actual content items retain their own region membership and clip;
no placeholder instrument is required.

## Public API

| Word | Stack |
|---|---|
| `RTE-CATALOG-STORAGE-DISJOINT?` | `( a u -- flag )` |
| `RTE-REGION-CATALOG-VALID?` | `( catalog -- flag )` |
| `RTE-REGION-CATALOG-FIND` | `( id validated-catalog -- region-or-zero )` |
| `RTE-FAMILY-PLAN-SIZE` | `( kind -- bytes-or-zero )` |
| `RTE-FAMILY-ITEM-SIZE` | `( kind -- bytes-or-zero )` |
| `RTE-FAMILY-ITEMS@` | `( fixed-validated-entry -- a u )` |
| `RTE-FAMILY-REGIONS@` | `( fixed-validated-entry -- a u )` |
| `RTE-PANE-VALID?` | `( pane -- flag )` |
| `RTE-FAMILY-BATCH-FIXED?` | `( batch -- flag )` |
| `RTE-FAMILY-BATCH-SPAN-COUNT` | `( fixed-batch -- count )` |
| `RTE-FAMILY-BATCH-SPAN@` | `( index fixed-batch -- a u )` |
| `RTE-FAMILY-BATCH-VALID?` | `( batch -- flag )` |

`FIXED?` and the span enumerators are stack-only and write no scratch. They
let composition prove disjointness from its own module, output and provider
storage before invoking deeper validators. Span order is batch, catalog header,
catalog rows, family vector, followed by five spans per family: plan, items,
bytes, glyph refs, instrument region copies. Inapplicable slots are `(0,0)`;
out-of-range indices return `(0,0)`. The fixed batch must remain immutable
through enumeration. `FIXED?` alone proves no semantic or cross-span validity.

`FIND` requires a previously validated immutable catalog. Item/region accessors
require the entry's fixed header and plan span to have been checked. The
aggregate layer preserves the provider's stricter CONTROL ordering: CONTROL
plans first with globally contiguous control IDs; later object families use
strictly increasing disjoint IDs. SERIES identities occupy their independent
namespace. The catalog is defined and charged once per aggregate, not once per
family referencing it.

`local_testing/test_rich_region_catalog.py` executes the actual native dependency
closure, covering all six families, dense payload ownership, empty pane/series
cases, orphan/duplicate/reference rejection, signed/u32 limits, UTF-8, and
prewrite module/caller alias checks.
