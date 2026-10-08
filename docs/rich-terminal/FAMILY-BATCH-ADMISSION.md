# Shared catalog and family admission

`region-catalog.f` and `family-batch.f` add a complete-candidate shell path. The
existing 224-byte RTE facade, 168-byte hybrid plan, and 456-byte hybrid admission
remain unchanged. A batch borrows immutable source records for the dynamic
extent of preflight; successful preflight does not retain their addresses.
Concrete DEFINE calls still copy every accepted record and payload into the
provider's candidate bank before publication.

## Source and facade ABI

The region catalog is 56 bytes: owner, generation, surface columns/rows, an
exact span of existing 96-byte region records, and a zero reserved cell.
Catalog region IDs are positive, unique, and increasing. Each family entry is
64 bytes: kind, plan address/size, display or sample address/size, glyph-ref
address/size, and a zero reserved cell. A 72-byte batch contains ABI1, catalog
address/size, family-entry address/size, attempt, source generation, surface
generation, and a zero reserved cell.

| Family kind | Plan bytes | Item bytes | Extra source |
| --- | ---: | ---: | --- |
| CONTROL1 | 144 | 200 | Dense label, shortcut, content bytes |
| GLYPH2 | 144 | 120 | Dense display bytes and one 16-byte ref per item |
| INSTRUMENT3 | 72 | 216 | Separate exact region copies and dense units |
| STATIC4 | 144 | 176 | Dense label/value bytes |
| SERIES5 | 48 | 88 | Dense sample bytes; `SAMPLES-U` is bytes |
| PANE6 | 144 | 184 | Dense title bytes |

Used spans may be adjacent slices of one backing allocation, but must not
overlap. Catalog rows are separate from embedded family region copies.
Every item must match its catalog region and logical root dimensions exactly.
A PANE authenticates a unique same-owner content region painted after its
chrome region, with an explicit clip contained in its translated content slot.
A canonical empty content clip is valid and needs no fabricated content item.
Unreferenced catalog rows are rejected.

`RTE-FAMILY-BATCH-FIXED?`, `RTE-FAMILY-BATCH-SPAN-COUNT`, and
`RTE-FAMILY-BATCH-SPAN@` support a stack-only authority pass. Before any deep
validator writes scratch, all source spans and the output must exclude the
catalog, engine, parser, family, facade, and concrete-provider storage. Output
must also be disjoint from every source span. Failures leave output unchanged.

The optional shell facade is 56 bytes: magic, size, self, base RTE facade,
scalar preflight callback, PANE DEFINE callback, PANE REPLACE callback.
`RTAPTE-SHELL-INIT ( base-rte shell -- status )` binds the APT1 implementation;
`RTAPTE-SHELL-FINI` clears it. `RTE-FAMILY-BATCH-PREFLIGHT ( batch admission
shell -- status )` produces the checked admission only on exact provider
success. `RTE-PANE-DEFINE` and `RTE-PANE-REPLACE` take `( pane shell -- status )`.
All other family emission uses the existing base facade APIs.

## Checked summary

The new admission is 544 bytes. Cells0..31 are owner, generation, and surface
columns/rows; cells32/40 are ABI1 and size544; bytes48..119 are zero reserved.
The named family aggregate offsets120..455 retain the existing HA meanings.
The instrument-region count is the number of distinct catalog rows actually
used by instruments, regardless of how many family plans copy those rows.

| Offset | Aggregate |
| ---: | --- |
| 456 | Exact catalog region count |
| 464 | Last catalog region ID |
| 472/480 | First/last OBJECT identity, including CONTROL |
| 488 | PANE count |
| 496/504/512 | PANE title bytes, per-title aligned bytes, maximum title bytes |
| 520 | Last PANE identity |
| 528 | TASKBAR/TASK/LAUNCHER control count |
| 536 | Exact required neutral feature bits |

CONTROL entries precede other OBJECT families and their identities remain
contiguous across plans. All OBJECT identities are globally increasing in
batch order; SERIES uses a separate increasing identity namespace. A WAVEFORM
must reference a SERIES in an earlier family entry of the same batch. Duplicate,
forward, missing, and cross-generation history references are rejected before
provider admission. A history-only batch may have no catalog rows or OBJECTs.

The neutral layer computes family semantics, exact UTF-8, copy alignment,
maximum payloads, sample slots, history capacities, and chunk counts. The
provider receives only the checked scalar summary, validates its own typed
header and required feature dependencies, and applies negotiated, transaction,
owner-reservation, operation-bank, and copy-bank quotas. It never walks caller
items or casts the typed summary's reserved header as legacy region geometry.
Catalog region costs are charged once; each PANE adds one object, one operation,
`184 + align8(title bytes)` copied bytes, and `144 + title bytes` framed bytes.

## Candidate and input boundaries

PANE, TASKBAR, and SERIES publication is limited to complete
`REPLACE_START` candidates. PANE replacement is allowed only when the target
and its geometry are already authenticated in that candidate. No API in this
slice mutates arbitrary committed pane/taskbar geometry or existing history.
The ordinary provider object ledger remains aggregate-only. Changed shell
geometry must therefore publish a complete owner replacement; abort preserves
the prior owner and its immutable copied sources.

TASKBAR roots have one row and no label or content. TASK and LAUNCHER children
have authored positive single-row slots, a real same-region TASKBAR parent,
strict single-line UTF-8 labels, increasing canonical order, and disjoint slots
inside the parent, including hidden children. At most one TASK is selected.
MINIMIZED32 belongs only to TASK and cannot be combined with SELECTED. Other
control kinds retain their previous state masks. ACTIVATE remains an ordinary
app input event; widgets do not call terminal APIs.

The optional shell capability remains a product-composition decision. These
modules do not enable PANES or TASKBARS in the Desktop profile.
