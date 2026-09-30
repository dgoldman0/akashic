# PANE and taskbar provider leaves

The concrete provider in `akashic/tui/rich-terminal/apt1-engine.f` captures
ordinary authored geometry into genuine PANE objects and TASKBAR, TASK and
LAUNCHER controls. These APIs do not parse painted text, infer application
identity, create a title row or reconstruct geometry from labels.

## PANE

`RTAPT-PANE-DEFINE ( pane engine -- status )` and
`RTAPT-PANE-REPLACE ( pane engine -- status )` borrow one aligned 184-byte
record. Fields occupy successive 8-byte cells:

| Offset | Field |
|---:|---|
| 0..24 | OWNER, GENERATION, ID, KIND (`RTAPT-PANE-STANDARD=1`) |
| 32..56 | VISIBLE, Z, REGION, PARENT |
| 64..104 | ROW, COL, HEIGHT, WIDTH, ROOT-HEIGHT, ROOT-WIDTH |
| 112..144 | CONTENT-REGION, CONTENT-ROW, CONTENT-COL, CONTENT-HEIGHT, CONTENT-WIDTH |
| 152..176 | FOCUSED, TITLE-A, TITLE-U, RESERVED |

VISIBLE and FOCUSED are canonical 0/-1 flags. PARENT and RESERVED are zero.
The inner rectangle is relative to the outer rectangle, has positive extent,
and fits entirely inside it. ROOT dimensions equal the exact captured chrome
region's logical dimensions. The title is single-line scalar UTF8, excluding
C0, DEL, C1, U+2028 and U+2029; an empty title is canonical 0/0.

Both chrome and content regions must already exist in this captured candidate
under the exact owner/generation. The content region is distinct, explicitly
clipped, unique to its pane, and paints after chrome by `(z, region ID)`.
A nonempty physical clip fits inside the pane's translated content rectangle.
An explicit canonical empty clip is valid. Outer and content rectangles may
be identical; titles remain semantic metadata where no physical title space
exists.

The public scope is complete `REPLACE_START`. REPLACE additionally requires
an earlier PANE in that same candidate, with identical geometry/region tuple;
visibility, focus and title bytes can change. Title growth is conservatively
refused because these ordinary object leaves keep aggregate UTF8 reservations,
not a per-pane mutable text ledger. Committed pane/title/topology changes use
a new full-owner replacement. Arbitrary committed DELTA replacements are
refused before capture; region high-water marks never substitute for geometry.

Capture owns 184 fixed bytes plus the 8-aligned title, clearing the borrowed
pointer and padding. One operation emits the native PANE 104-byte payload plus
title and the 40-byte frame header. DEFINE charges one object and exact title
UTF8. Publication revalidates copied shape, same-owner region references,
content uniqueness/clip/order and capability before emission. Prefix scans
check every inspected copy offset, length, alignment and fixed header before
reading it. Abort clears pending storage and preserves the acknowledged scene.

## TASKBAR, TASK and LAUNCHER

These use the existing CONTROL 200 neutral descriptor and ordinary CONTROL
capture API, with genuine kinds 10, 11 and 12 and MINIMIZED state bit 32. TASKBAR is a
one-row root with empty label, shortcut and content. Children have explicit
one-row parent-relative slots; their position and width are never repacked.
TASK permits visible/enabled/selected/minimized; selected and minimized are
exclusive. LAUNCHER permits only visible/enabled. Labels are nonempty strict
single-line UTF8, content is empty, and children have zero Z and row.

A complete START candidate proves each child's earlier TASKBAR parent, exact
same region, containment, disjoint sibling slots, unique sibling order and at
most one selected TASK. Hidden slots participate in these checks too. Direct
calls reject aliases into provider scratch before loading borrowed text.
The captured graph and copied text are revalidated before genuine CONTROL
serialization. Taskbar definitions and changes currently use full-owner
replacement; committed taskbar DELTA and REPLACE are unsupported because the
aggregate control ledger does not retain complete slot geometry.

The provider does not decide which ordinary cells to suppress or how to
activate a shell entry. The shell planner supplies exact modeled bands,
pane ownership and immutable input correlation; the publisher proves final
paint coverage and acknowledged lifecycle identity. Explicit divider cells
remain outside the two taskbar bands. Ordinary gaps are accepted only when
the completed CELL source proves the expected blank cells.

The paired native protocol contract is implemented by MegaPad's
`PT-PANE-DEFINE`, `PT-PANE-REPLACE`, `PT-CONTROL-DEFINE` and final retained graph
validation. PANES maps neutral bit 0x200 to wire 0x800 and requires CORE,
at least two regions, positive object/UTF8 quotas, payload 104 and update 304.
TASKBARS maps neutral bit 0x800 to wire 0x2000 and requires CONTROLS.

MegaPad's `docs/rich-terminal/APT-1-RETAINED-1.md` states:

> The renderer draws pane material only in outer-minus-content chrome and leaves
> the content rectangle untouched.

Its taskbar graph likewise requires exact guest-authored slots, including
pairwise disjoint hidden or disabled children. The provider's candidate-only
scope is intentionally narrower than the protocol's general replacement
support; no unproven committed geometry is accepted through these leaf APIs.

## Shared region admission

`provider-family.f` adds `RTAPT-FAMILY-PREFLIGHT ( summary engine -- status )`.
It consumes a typed, aligned 544-byte scalar summary; it never walks source
plans, descriptors or text. `family-batch.f` validates those sources and
derives the summary before calling the provider. The legacy 456-byte hybrid
summary and base facade remain unchanged.

| Offset | Fields |
|---:|---|
| 0..24 | OWNER, GENERATION, SURFACE-COLS, SURFACE-ROWS |
| 32, 40 | ABI = 1, SIZE = 544 |
| 48..119 | Reserved, all zero |
| 120..455 | Existing named family aggregates at their original offsets |
| 456, 464 | Unique catalog region count, last region ID |
| 472, 480 | First and last retained object IDs, including controls |
| 488..520 | PANE count, title bytes, aligned title bytes, maximum title bytes, last PANE ID |
| 528, 536 | Taskbar control count, exact required feature mask |

The provider independently checks the typed header, feature dependencies,
family count relationships, title accounting and ID bounds. The instrument
region count means distinct catalog rows used by instruments, so repeated
family references do not reserve or define a region twice. CONTROL identities
form the contiguous prefix of the shared retained object ID ordering; SERIES
identities use their independent namespace. PANE content regions may
be intentionally empty, provided the neutral catalog proves their explicit
pane reference.

Admission charges each catalog region once, then adds exact operation, copy,
frame, UTF8, object, series and declared sample-slot totals across all families.
It checks negotiated and caller-owned capacities before an owner is opened or
a candidate begins. Existing owners consume their reserved quotas without a
second global reservation. No owner, operation bank or copy bank is changed;
as with legacy admission, negotiation may refresh the engine's designated
limits cache, and structural session loss retains normal quarantine behavior.
The borrowed summary and the module's private scratch cannot overlap provider
storage, and all borrowed pointers and temporary copied summary bytes are
cleared before return.
