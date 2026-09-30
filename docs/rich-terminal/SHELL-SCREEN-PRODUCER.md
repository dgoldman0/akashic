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

RTHP appends one optional extension pointer at4128; its descriptor becomes4136
bytes. Existing target-bank336 and target-entry48 ABIs stay unchanged. The
64-byte extension descriptor supplies one dispatcher and explicit checked
region/object/UTF8 reservation additions. It installs only before OWNER_OPEN.

The shell candidate is prepared only after RTHP freezes its ordinary target
bank, before retained BEGIN. Only successful PREPARE selects shell EMIT. Any
failure before BEGIN aborts staged shell state and selects legacy emission.
Any error after shell emission starts cancels the complete capture. An installed
extension uses complete START/reveal replacement on changed draws, with fresh
wire object and history identities; an unchanged current draw is reused. Every
SERIES sample and authored history value survives those replacements. This
first shell path does not claim identity reuse across selection redraws. Safe
per-pane DELTA is a future optimization. The standalone SERIES path retains its
separate, strict unchanged-history identity-reuse qualification.

PUBLISH-CHECK validates immutable pending bytes against the exact core pending
target, owner, generation and draw. It deliberately does not require the old
draw to remain current while its physical ACK is awaited. After core ACK
publication, bounded scalar stores publish the paired shell bank and its exact
ID frontiers. Abort discards only pending authority. Retirement clears both.
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
