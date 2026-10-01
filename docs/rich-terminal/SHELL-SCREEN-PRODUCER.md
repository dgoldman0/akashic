# Optional shell candidate and acknowledged input

`shell-screen-producer.f` adds a complete shell candidate to RTHP. It uses
independently completed SHSN authority and the frozen RUHA directory's signed
slot plus CINST owner/generation. It does not infer ownership from application
names, labels, or the last active UIDL context. The capability remains opt-in.

## Construction and storage

| Word | Stack |
|---|---|
| `RSHSP-INIT` | `( source shell-facade producer max-entries max-text work-a work-u bank-a bank-a-u bank-b bank-b-u sidecar -- rte-status )` |
| `RSHSP-INSTALL` | `( sidecar -- rte-status )` |
| `RSHSP-VALID?` | `( sidecar -- flag )` |
| `RSHSP-WORK-USED@` | `( sidecar -- bytes )` |
| `RSHSP-BANK-BYTES@` | `( sidecar -- bytes )` |
| `RSHSP-UNINSTALL-AFTER-STOP` | `( sidecar -- rte-status )` |
| `RSHSP-CONTROL-TARGET@` | `( owner generation control-id intent sidecar -- row col revision found? )` |

The descriptor is 240 bytes. Its configured pointers are producer24, SHSN32,
shell facade40, work48/56, A64/72 and B80/88. Active/pending bank pointers are
96/104, corresponding core target pointers112/120, and draws128/136. Offset144
reports the last measured packed requirement;152 reports scratch high-water.
Entry/text bounds are160/168; the embedded RTHP extension occupies176..239.
`max-text` bounds the SHM text arena, excluding its128-byte header and reserved
168-byte entries. The copied model retains the actual reserved entry limit.

All capacities belong to the caller. Construction proves complete capacities
pairwise disjoint from each other, producer/arena, provider, SHSN/frozen banks,
ordinary live root/host/children, UIDL, screen and module scratch. A preparation
repeats live authority before writing work or the inactive bank. There are no
allocations. Insufficient storage refuses the entire optional shell candidate;
it never truncates an object, string, action or sample history.

Each immutable bank starts with this128-byte header:

| Offset | Value |
|---:|---|
|0|Exact used bytes, aligned8|
|8|Copied family-batch offset|
|16/24|Copied SHM offset/bytes|
|32/40|Correlation192 offset/bytes|
|48/56|Action-byte offset/bytes|
|64/72|Membership112 offset/bytes|
|80|Exact core target-bank pointer|
|88|Completed draw|
|96/104|Wire owner/generation|
|112/120|Next region/object identity|

The metadata spans use canonical consecutive aligned offsets. The deep-copied
family graph follows them. Every graph pointer is bounded within that suffix
before nested parsing. Catalog/object maxima must equal the stored next IDs
minus one. The exact packed requirement is:

`128 + align8(SHM bytes) + 192*correlations + align8(action bytes) + 112*panes + RSHFC-MEASURE(batch)`.

The work arena uses checked aligned bump allocation. Glyph projection reserves
bounded temporary slots per clip, then compacts actual runs before the next
clip. `WORK-USED@` records the peak reservation, including these transient
slots. On capacity failure it reports the first required prefix that did not
fit; `BANK-BYTES@` is set once the full candidate can be measured. Product
ceilings must be selected from these measured values and the total live memory
budget. Merely constructing the descriptor does not prove that a frame fits.

The native 32×12 candidate fixture, with one pane, both taskbar bands, one
ordinary MENUBAR and one STATUS_FIELD, uses 66,296 peak scratch bytes and 8,528
packed bytes. It exercises actual aggregate admission and family emission,
then overwrites the complete work arena before validating the copied bank and
publishing its input authority. These are fixture measurements, not Desk
capacity limits; product qualification must measure the complete desktop.

## Geometry and fallback

Ordinary applet CONTROL IDs, hierarchy and FIELD revision bytes stay unchanged.
Each CONTROL run and each STATIC references its actual pane content region;
its logical origin remains0,0 and its logical dimensions remain the full
surface. Each pane content region has the exact explicit SHM content clip.
Instrument regions retain their independent explicit clips and must fit their
associated pane, above chrome and below interactive content. SERIES is copied
intact, including every waveform sample. New shell controls follow the applet
CONTROL prefix; non-input instrument/static IDs move above that prefix, with
PANE and newly projected glyph IDs following them.

A fully visible instrument root may omit its clip flag in the ordinary RUIP
plan. The sidecar copies its logical rectangle into explicit physical clip
fields without changing object coordinates. Catalog and instrument-plan region
rows receive distinct owned copies, and both must still match exactly. Partial
explicit clips remain unchanged; an effective clip outside its associated pane
still refuses the shell candidate.

The two canonical TASKBAR roots share one explicitly clipped taskbar region.
Their distinct root rectangles preserve the divider and label slots. Canonical
blank spacing may acquire rich material. A band is admitted only when its final
writer proof is clear and every authored spacing gap is still blank. If a
source-authored sibling band cannot be admitted, the complete taskbar set stays
ordinary. Global residue holds only cells outside pane content and admitted
shell claims. Its full-surface region sorts below interactive regions so sparse
residual glyphs cannot create an input barrier.

The initial conservative policy refuses the entire optional shell candidate
when pane contents overlap or a final writer covers any pane outer rectangle.
Modal/unavailable SHSN authority also refuses it. Every refusal uses the
unchanged, already admitted legacy RTHP candidate, with no shell claims leaking
into that candidate.

## START, ACK and teardown

RTHP appends one optional extension pointer at 4128, followed by the
open-request flag at 4136; its descriptor is 4144 bytes. Existing target-bank336 and target-entry48 ABIs stay unchanged. The
64-byte extension descriptor supplies one dispatcher and explicit checked
region/object/UTF8 reservation additions. It installs only before OWNER_OPEN.

The dispatcher events are PREPARE=0, EMIT=1, PUBLISH-CHECK=2, PUBLISH=3,
ABORT=4, RETIRE=5, CURRENT=6, START-ACK=7, DELTA-PROBE=8, DELTA-PREPARE=9 and
DELTA-EMIT=10.

The shell candidate is prepared only after RTHP freezes its ordinary target
bank, before retained BEGIN. Only successful PREPARE selects shell EMIT. Any
failure before BEGIN aborts staged shell state and selects legacy emission.
Any error after shell emission starts cancels the complete capture. A START
defines every object and history with fresh wire identities; an unchanged
current draw is reused. Every SERIES sample and authored history value
survives those replacements. A changed draw whose shell layout matches the
acknowledged one is published as a DELTA instead, described next.

## DELTA publication

A changed draw after an acknowledged one becomes a retained DELTA when its
shell layout matches the acknowledged bank, so typing, caret moves and other
changes inside panes send only what changed and keep every unchanged pane,
control and waveform history under its acknowledged identity.

Before the base producer compares its candidate, DELTA-PROBE checks that the
shell model of the new draw equals the copied acknowledged model apart from
its epoch, which every paint advances. A renamed or refocused task, a new pane
or any other model change leaves the draw to a complete START without further
comparison.

After the base producer has matched its controls, statics, instruments and
series to their acknowledged identities, DELTA-PREPARE builds the shell
candidate. It reads the base candidate's controls and instruments from the
producer's pending target bank, which carries those identities, instead of
from the candidate fields a START reads. It then gives each item the
acknowledged identity in the same place:

- the catalog must be identical, region identities included;
- families must match in order, kind and region;
- applet controls must already carry their acknowledged identities;
- the taskbar takes the acknowledged identities and must otherwise be
  unchanged, because a DELTA cannot replace taskbar controls;
- instruments and series take the identities in place and must be unchanged;
  status fields and panes take them and may change;
- residual glyph runs take the acknowledged runs' identities slot by slot in
  each region. Unused acknowledged slots become invisible empty runs, and
  extra runs get identities above the producer's object frontier.

Taskbar correlations and pane memberships are renumbered with them. Any other
difference refuses the DELTA, and the producer rebuilds the draw with fresh
identities for a complete START. DELTA-EMIT sends the difference between the
pending and active banks through `RTE-FAMILY-BATCH-DELTA-EMIT` inside the open
retained DELTA. After the physical acknowledgement, PUBLISH-CHECK and PUBLISH
promote the pending bank exactly as after a reveal. A DELTA consumes no region
identities, and the published bank's frontier covers its new object
identities.

A DELTA plans residual runs only on rows that changed. After a candidate's
glyphs are built, the producer's ROW-DAMAGE names the rows it rebuilt; it
copied every other row from the acknowledged target because that row's
cells, residue, menus and claims are unchanged, and a complete build marks
every row. A DELTA also keeps the shell's own claims and regions, so the
shell's runs on an unmarked row equal the acknowledged bank's. For each
region whose catalog row equals the acknowledged one, the shell copies those
rows' runs and text from the acknowledged bank and plans each band of marked
rows through the residual planner with a clip of just that band. Runs never
span rows, so the region gets exactly the runs a whole-region plan would
give; a test checks that the two banks are identical byte for byte. While
typing, that is the edited line and the status line instead of every cell of
every pane. Every planner call of one build runs under a single
borrow of the projection planes: every request, claim, work and output span
lies in the sidecar's work arena, so one proof that the arena is disjoint
from screen storage covers them all, as the base producer does for its rows.

The producer's unchanged-frame shortcut republishes its own target alone, so
with the shell installed every changed draw takes the full build. Private
counters record DELTA-PROBE refusals, DELTA-PREPARE refusals and successes,
and where the last refusal happened; Desk acceptance runs record them with the
terminal's count of committed PRESENT modes.

A bank is checked in full once, when it is frozen. STAGE freezes into the
bank that ACTIVE does not name, after dropping PENDING, so a bank that
PENDING or ACTIVE names is never written again. The checks below therefore
compare its identities and do not check its contents again.

After a successful hidden START acknowledgement, START-ACK validates the
immutable pending bank against the exact core pending target, owner, generation
and draw. It advances each region/object frontier to the maximum of the base
frontier and the copied shell frontier. These IDs have been consumed even when
a newer ordinary draw replaces the hidden candidate before reveal. This event
does not publish a bank or change input authority. Unacknowledged or rejected
STARTs do not advance shell frontiers.

PUBLISH-CHECK validates the same immutable pending tuple. Neither ACK check
requires the old draw to remain current while its physical ACK is awaited.
After visible core ACK publication, bounded scalar stores publish the paired
shell bank, preserving the already consumed ID frontiers. Abort discards only
pending authority; retirement clears both banks' authority. Neither operation
rewinds consumed IDs. Repeating START-ACK or publishing after a larger base
reservation cannot move a frontier backwards.

The real Desk regression exposed this timing when ordinary typing completed a
new draw before reveal: the next catalog began at region 54, but the provider
had already acknowledged hidden regions through 61. It correctly rejected the
first region before emitting any text. Advancing only the base candidate's
frontiers at hidden ACK caused that reuse; START-ACK reserves the complete
shell range at the same acknowledgement boundary.

CURRENT and input additionally require exact core active target/draw and the
current SHSN model to equal the copied model. Unacknowledged banks never route
input.

A shell ACTIVATE must match a unique retained CONTROL and correlation, the
canonical parent band and translated slot, source lifecycle tuple, copied label
and action bytes, epoch and draw. It returns the ordinary root mouse coordinate;
existing host/Desk handling performs task focus/restore or catalog activation.
It does not invoke applications directly. Applet intents retain their original
acknowledged IDs and FIELD revisions through `RTHP-CONTROL-TARGET@`.

`UNINSTALL-AFTER-STOP` requires the composition to revoke draw/input callbacks
and drain/stop transport first. It verifies the facade is idle, clears only its
own extension and local authority, and emits nothing. Desk calls it after
`APTAS-UNINSTALL`, then detaches SHSN and finalizes the shell facade. A refused
teardown retains state for a later retry.
