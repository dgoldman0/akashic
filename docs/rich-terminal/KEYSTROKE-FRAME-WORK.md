# A typed character's frame work — design, 2026-10-14

Status: approved for parts 1 to 4 and 7 on 2026-10-14; parts 5 and 6 need
their own approval. Parts 1 to 4 and 7 are done; each records what it did.

Earlier work: [PER-KEY-FRAME-REPEATS.md](PER-KEY-FRAME-REPEATS.md)
(2026-09-28) and part 10 of the [rich experience plan](RICH-EXPERIENCE-PLAN.md)
(`local_testing/evidence/screen-changes-20261011.md`). This is step 3 of
MegaPad's `docs/simulator-speed-plan.md`.

## Summary

A character typed into Pad on the rich Desktop costs the guest 27.5 million
steps. 89% of that is the rich frame builder (`RTHP-PREPARE`). Desk's own
painting is 3.3%. At the 100 MHz FPGA target and one to two clocks a step,
that is about 0.3 to 0.55 s of guest work per key. This is arithmetic, not a
measurement.

A keystroke changes the editor's text, the caret and the status line. The
frame builder still:

- resends six controls whose content did not change, about 15.8 KB a key;
- builds, admits and compares two complete candidates for the whole screen,
  the hybrid producer's and Desk's shell producer's;
- checks about 450 storage spans one by one against every module's storage,
  and checks some of them several times in one call;
- misses the comparison's fast path on every frame, because of an invisible
  slot tail.

This design removes that work in seven parts. Each part says what kind of
change it is:

- **Repeat:** it removes work that is provably repeated, or whose result is
  never used, and says how that is proved.
- **Behavior:** it changes what is sent, and says why nothing is lost.
- **Design:** it changes how the frame is built. It stays exact because the
  full path is kept and checked against it.

No part skips a check on another module's word or gives up a guarantee.

## Where a keystroke's steps go

Measured on 2026-10-14 with Akashic `f0645eea` and MegaPad `7537b2a2`
(`feature/simulator-speed`):

- the `desktop-apt1` image at 280 × 84;
- the hosted simulator with the native executor;
- twelve characters typed into Pad after the Desktop keyboard journey.

A sampler recorded the guest call chain at every host quantum yield, every
65,536 steps, which gave 446 samples per key. Rows overlap where one stage
calls another.

| Stage | Share | Steps per key |
| --- | ---: | ---: |
| Rich frame builder (`RTHP-PREPARE`) | 89.3% | 24.6M |
| Shell producer: build its family batch (`_RSHSP-BUILD-BATCH`) | 21.4% | 5.9M |
| — of which its preflight (`RTE-FAMILY-BATCH-PREFLIGHT`) | 13.8% | 3.8M |
| Shell producer: freeze the batch into a bank (`_RSHSP-FREEZE`) | 7.6% | 2.1M |
| Shell producer: emit the delta (`_RSHSP-DELTA-EMIT`) | 4.8% | 1.3M |
| Shell producer: storage checks at each call (`_RSHSP-AUTHORITY?`) | 3.4% | 0.9M |
| Hybrid producer: snapshot the documents (`RUHA-SNAPSHOT-FOR@`) | 10.4% | 2.9M |
| Hybrid producer: build the candidate (`_RTHP-BUILD-OBSERVED-CANDIDATE`) | 19.4% | 5.3M |
| — of which engine admission (`RTE-HYBRID-PREFLIGHT`) | 9.3% | 2.6M |
| Hybrid producer: compare with the acknowledged frame (`_RTHP-DELTA-CANDIDATE?`) | 16.8% | 4.6M |
| — of which glyph identity matching and the per-slot compare | 12.1% | 3.3M |
| Terminal service | 4.1% | 1.1M |
| Desk's painting (`DESK-PAINT-CB`) | 3.3% | 0.9M |
| Storage-aliasing checks, across all of the above (`*-STORAGE-DISJOINT?`) | 14.7% | 4.0M |

At a quarter of the area (140 × 42), a key still costs 20.3M steps. So most
of the cost follows the number of items on screen, not the number of cells.
Before `f0645eea`, a key cost 29.3M steps.

Each slice is measured with the project's typing tool,
`local_testing/physical_typing_cadence.py --screen-profile`, read by
`local_testing/screen_change_profile.py`. It charges every guest step to the
words it ran under, exactly, at each host boundary. Its baseline, on this
design's commit (Akashic `28d118d2`): the isolated first character costs
34.9M guest steps; the burst of 18 characters makes 10 frames of 25.0M steps
each, and each frame sends 9 retained operations, 17.6 KB.

## What a keystroke changes

On the wire, measured at the host terminal over the same twelve keys, each
key sends seven `CONTROL_REPLACE` operations (16.2 KB) and one
`OBJECT_REPLACE` (107 bytes). Only one of the seven controls changed: Pad's
editor text area. The other six (three item views, a text area and two text
grids, 15.8 KB together) carried exactly their previous content, with only a
newer content revision.

On screen, the edited row, the caret and the status line change. In
September, 99.9% of glyph runs and 95% of controls were unchanged in each
typing frame (PER-KEY-FRAME-REPEATS).

## Rules kept from earlier work

- Remove only work that is provably repeated. The proof comes from the module
  that owns the data. A check is never skipped on another module's word, and a
  digest is not a proof.
- The terminal receives exactly the frames and operations the full path would
  send. The exception is a part that changes behavior on purpose, and then the
  full path changes the same way.
- Every boundary check stays. Each item that crosses a boundary is checked
  there. It is checked either directly, or because it is byte for byte what
  that boundary already checked and kept.
- Storage is sized from what the screen and content need now, and grows on
  demand. Nothing reserves a guessed maximum.
- Everything stays renderer-neutral and below the applet layer. CELL stays
  complete.

## Part 1. Send only the controls that changed — behavior

**Today.**
- Every text area, text grid, item view and document control takes the
  aggregate content epoch as its content revision
  (`hybrid-screen-producer.f:4896`; comment at 3241, "Collections use the
  aggregate epoch").
- The epoch moves whenever any document is captured again, which happens on
  every key.
- The comparison requires each control's revision to equal its bank's epoch
  (`_RTHP-D-CONTENT-REVISION?`, 11013). It treats a newer revision as a change.
- So every content control on screen is resent each key. Input targets record
  the same epoch (1729).

**Change.**
- A content control whose packed body equals the acknowledged control's body,
  in every byte but the revision, keeps the acknowledged revision.
- Any other control takes the current epoch, which is newer than any revision
  it has had.
- The comparison makes this choice. It already pairs each control with its
  acknowledged one and rewrites identities in the pending bank, and it now
  rewrites the revision there too. It then sees no change, and sends nothing
  for the unchanged controls.
- The same step updates the input target entries, so each records its
  control's own revision. The comparison accepts a revision at or below the
  bank's epoch.

**Why nothing is lost.**
- The terminal already holds exactly that content. SEMANTIC-CONTENT-1 requires
  a strictly newer revision only for a changed body (MegaPad
  `docs/rich-terminal/SEMANTIC-CONTENT-1.md:611-617`).
- Positioned and item input names the control's content revision in the
  acknowledged composite. The client checks it against what it published
  (629-630, 684). An unchanged control's published revision is the one it
  kept, so input stays bound to exactly the content the user saw.
- The revision still rises every time a control's content changes.

**Proof.** The producer compares its own new candidate with its own
acknowledged bank, byte for byte. Both are its own data.

**Effect.**
- About 15.8 KB less on the wire per key: 16.2 KB becomes about 0.4 KB.
- The guest no longer encodes and checks six control operations a key. That
  is part of today's 4.8% for emission.
- The host terminal no longer decodes and validates six controls a key.

**Done** (Akashic `dc8b20fa`). In the typing run, a burst frame now sends 2
retained operations and 736 bytes instead of 9 and 17.6 KB, and the isolated
character 4 and 1.1 KB instead of 11 and 18.0 KB. Guest steps per frame did not
change measurably (25.0M and 24.8M): emission fell by 0.3M, and RUHA's storage
proofs rose by about 0.5M because the new words moved storage, which changes
where its enclosures split. Desk with Pad and the full Desktop journey pass.

## Part 2. Prove storage once per enclosure — repeat

**Today.** Each boundary proves that the spans it handles do not overlap any
module's private storage, the provider's storage or the live screen.

- The family batch preflight checks each of about 450 spans in turn
  (`_RTE-FA-AUTHORITY?`, `family-batch.f:141`). Each check walks a chain of
  module checks, nested so that some regions are tested several times, and
  then asks the provider.
- Emission repeats this for both the pending and the active batch
  (`_RTE-FEM-AUTHORITY?`, `shell-family-emit.f:30`).
- The shell's own check on each of its calls, at least six a key, runs its
  header check twice and three spans four times, with nothing written in
  between (`_RSHSP-AUTHORITY?`, `shell-screen-producer.f:918`).

Altogether, storage checks take 14.7% of a key. In the typing run, per
frame: the family preflight's per-span checks take 0.35M steps, emission's two
passes 0.76M, and the shell's own checks 1.91M.

**Change.**
- Family admission and family emission compute the enclosure of a batch's
  nonempty spans themselves, on the stack, and ask the module checks and the
  provider about it once. Only when the enclosure is refused do they ask about
  each span, exactly as before.
- The checks against the admission record and the shell facade, which can lie
  among the spans, stay per span. So do the shape checks: alignment, no
  wrapping, not empty.
- The pass stays stack-only: nothing is written before every span is proved
  apart from the module's own storage.
- The shell checks its header once per call. It proves RUHA's storage apart
  from its four spans in one proof instead of four.

**Proof.**
- If a span lies inside an enclosure, and the enclosure is disjoint from a
  region, the span is disjoint from it too.
- A refused enclosure falls back to the per-span checks. So the result is
  exactly what the per-span checks give.
- The module derives the enclosure from the spans it is checking, so it relies
  on no other module.
- Every proof is still made during the call, so live storage that has moved is
  still caught.
- A provider's storage-disjoint callback must decide by overlap alone, so that
  a disjoint enclosure implies disjoint parts. The provider contract now says
  so, and the APT-1 provider's chain was read for it.

**Done** (Akashic `50a179db` and `ff30db0b`). Measured together with part 3:
a burst frame went from 24.8M to 23.0M steps. Emission fell from 1.03M to
0.52M, the shell's own checks from 1.91M to 1.14M, and the family preflight
from 3.59M to 3.34M. An enclosure that spans protected storage is refused and
falls back, so the saving depends on where storage lies.

## Part 3. Check once what was just checked — repeat

**Today.**
- The shell validates its copy of the shell model four times per build:
  - when it is copied (`shell-screen-producer.f:836`);
  - in the planner (`shell-planner.f:258`);
  - in the membership builder (`shell-membership.f:155`);
  - in the frozen bank (`shell-screen-producer.f:759`).

  Each pass cost about 0.3M steps in October.

**Change.** Use the `-PROVED` pattern the code already has. The planner's band
words skip the model check for a caller that has just made it
(`shell-planner.f:226`); `RSHPL-BUILD` and `RSHMM-BUILD` get the same peers.
The public builders still check, and the frozen bank's check stays, since it
covers the copy in the bank.

**Proof.** The shell checks its copy right after copying it, and only reads it
afterwards. Tests pin this: the copy is checked before the only calls to the
proved builders, and nothing stores into it.

**Done** (Akashic `50a179db`), measured with part 2. The planner's and the
membership builder's model checks took 0.26M steps a frame.

## Part 4. Keep the comparison's fast path when the slot tail is invisible — repeat

**Today.**
- When only text changes, the comparison proves the whole glyph layout equal in
  one pass and takes the acknowledged IDs (`_RTHP-D-GLYPH-LAYOUT?`, 11630).
  This needs every acknowledged slot to be visible.
- Once any run disappears, for example when a menu closes, the candidate is
  padded with invisible tombstones up to the acknowledged slot count
  (`_RTHP-RESERVE-GLYPHS?`, 7442). The tail stays until the next full
  replacement.
- From then on, every frame takes the general matcher: identity
  normalization, then a compare of every slot. In the sampled run, typed after
  the Desktop keyboard journey had opened and closed menus, the fast path never
  ran, and the general matcher took 12.1% of each key.

**Change.** Also take the fast path when both banks have the same slot count,
the same visible prefix, and canonical tombstone tails.

**Proof.**
- The acknowledged bank's tail is canonical. Either the audit or the kept facts
  prove it (`_RTHP-D-CANONICAL-SLOT?`).
- On a byte-equal visible prefix, the general matcher gives equal anchors the
  same IDs and rebuilds the tail canonically (11495). The fast path keeps each
  tombstone's ID and writes the same canonical text reference.
- The tests run both paths on the same banks with a tombstone tail: unchanged
  text, a changed run, and a tail reference that arrived non-canonical. The
  results are byte-identical, change markers and compaction plan included.

**Effect.** Up to 12.1% of a key, less the fast path's own pass, which is one
compare per slot.

**Done** (Akashic `46754721`). The typing tool's run never leaves a tombstone
tail, so its frames did not change: 23.0M and 22.7M steps a burst frame, within
run-to-run noise.

## Part 5. Admission keeps what it admitted — repeat, with memory

**Today.**

Two boundaries check every item of every frame:
- the engine's admission of the hybrid candidate (`RTE-HYBRID-PREFLIGHT`,
  `engine.f:4549`): 9.3% of a key;
- the family batch preflight of the shell's batch: 13.8%.

In September, skipping checks of unchanged items on the producer's word was
rejected, because that would weaken the boundary. The exact way was left open:
a copy owned by the admitting module.

The shell's DELTA path has a further problem. Its preflight admits the batch
before the identities are mapped to the acknowledged ones (`_RSHSP-BUILD-DELTA`,
1319). So the batch it admits is not the one that is frozen and sent, and its
admission summary goes unused. Changed items are checked again, one operation
at a time, when they are sent (`engine.f:4628-4651`).

**Change.**
- Each admitting module keeps its own copy of the items it last admitted. With
  them it keeps the context they were checked against: limits, catalog
  geometry and owner.
- It compares each new item with its copy (`COMPARE`, a block compare on the
  device). It fully checks only items that differ, or every item when the
  context differs.
- Admission still records its totals per frame. It keeps each item's share of
  them and adds them up.
- Checks across items stay whole-frame: span overlap, identity order and region
  membership.
- The copy is sized from the admitted frame and grows on demand. A typing
  frame at 280 × 84 is about 700 glyph runs and 150 controls, so the copy is
  on the order of 200 KB per boundary. September's 14 MB figure was sized for
  a 400 × 200 maximum.
- The shell's DELTA path admits the batch it actually sends: identities are
  mapped first, then the batch is admitted.

**Proof.** Only the admitting module writes the copy, from items it has just
checked in full. An item equal to its copy in every byte, against the same
context, passes the same item checks.

**Effect.** Most of the 23.1% the two admissions take today, chiefly their
per-item checks, such as the UTF-8 decode of every glyph run's text.

**Needs approval.** This adds memory to the neutral engine contract, and
September said that needs its own approval.

## Part 6. Build and compare only what changed — design

**Today.** On each key:
- The hybrid producer builds a complete candidate with fresh identities and
  packs it. The comparison then maps it back to the acknowledged identities.
- Desk's shell producer builds its own complete batch from that. It maps
  identities slot by slot, freezes a complete bank, and compares every item
  with the acknowledged bank to find what to send.
- Glyph rows already follow the screen's exact row damage. Clean rows are still
  copied one at a time and renumbered.

**Change.**
- The shell derives its DELTA batch from its acknowledged bank. It replaces
  only the controls the hybrid producer's comparison marked as changed, and the
  glyph rows in the exact row damage.
- Emission takes its list of changes from those same marks, instead of
  comparing every item. The freeze still checks the finished bank once.
- The hybrid producer keeps the acknowledged identities of the rows and
  controls it reuses, so they need no renumbering and no matching.

**Exactness.** This part changes how the frame is built, so a check keeps it
exact, not proof alone:
- The full path stays. A diagnostic mode runs both paths on every frame and
  requires the same pending banks and the same operations, byte for byte. It
  is a switch in the producer, not in any applet.
- Tests over seeded edit streams compare the two paths, as
  `test_rich_kept_comparison_facts.py` does for the kept facts. The streams
  cover text, moves, growth, shrinking, new controls and refusals.
- A shadow run over typing and the canonical journey must record zero
  differences before the new path is used for real.
- Any frame the new path cannot handle takes the full path. That includes a
  START, a refusal, a change of geometry or owner, storage growth, a different
  family layout, and a change to the shell model.

**Rule change to approve.** The hybrid producer's rule today is that its
candidate is byte-identical to a full rebuild before identities are mapped.
That is why every frame mints fresh identities and maps them back. This part
would hold the rule at the outputs instead: the pending banks and the
operations are byte-identical to the full path's.

**Effect.** Most of what the earlier parts leave of the build, the freeze and
the comparison.

## Part 7. Reserve glyph slots from what is needed — repeat, device memory

**Today.** For each glyph region, the shell reserves a slot for every cell
before planning (`shell-screen-producer.f:610-617`). At 280 × 84 that is about
3.3 MB for the base region alone, zero-filled on every key and then compacted,
and each pane's content region adds its own area. The simulator counts a `FILL`
as one step, so none of this appears in the tables above. On the device it is
real memory traffic: `BFILL` takes N + 2 cycles, so at least 3.3 million
cycles a key.

**Change.** A DELTA region that reuses the acknowledged rows reserves one slot
for each acknowledged visible run, and for each changed row one slot per
scanned cell, the most the planner makes in a row. It never reserves more than
one slot a cell, the old reservation. A region planned whole, as in a START,
keeps one slot a cell. The text keeps its limit of four bytes a cell: a
character of several scalars can take more, so a changed row's text has no
smaller bound. The reservation grows on demand, like the rest of the work
space.

**Proof.**
- Copied runs come from the acknowledged visible runs, and every run the
  planner makes holds at least one cell of its own. So below the cap no copy or
  planner call runs out of room, and at the cap the build fails exactly where
  it did.
- The reserved bytes are zeroed, then overwritten or compacted away, so the
  batch does not depend on the size of the reservation. In the shell's test,
  planning one row and planning every row give byte-identical banks.

**Done** (Akashic `230d83b3`). In the shell's test, one changed row of a 9 × 19
pane, with every cell its own run, reserves 28 slots instead of 171 and uses
27. The build's work-space high-water falls from 66,392 to 27,000 bytes, and
with every row changed it is exactly a START's. On the 280 × 84 Desktop a key
changes one or two rows, so the base region's slots fall from 23,520 (3.2 MB)
to its acknowledged runs plus 280 a changed row; the text's 94 KB stays. That
is an estimate from the formula: the typing tool counts steps, not memory
traffic. Guest steps did not change measurably.

## Defects found on the way

These are recorded here and not fixed, unless a part touches the code:

- **Shell input lookup can read the wrong bank.**
  - `RSHSP-CONTROL-TARGET@` searches `_RSHSP-V-BATCH`
    (`shell-screen-producer.f:1462`). Only the bank check (691) and START-ACK
    (972) set that variable.
  - So while a pending bank waits for its ACK, input finds controls in the
    unacknowledged batch.
  - After a failed or grown re-freeze, the variable can name a bank that is
    being rewritten.
  - This is inferred from the code, not run. Part 6 touches this code and would
    fix it.
- **A possible full START while typing fast.** A newer draw can arrive after a
  sealed DELTA is acknowledged, but before the step observes the ACK. Then
  `_RTHP-DELTA-ACKED-RECAPTURE` (`hybrid-screen-producer.f:13115`) promotes the
  bank and rebuilds with a full START. The reveal case (13267) continues live
  instead. This is uncertain: the typing run saw one DELTA per key.

## Order and checks

| Slice | Content | Approval | State |
| --- | --- | --- | --- |
| 1 | Part 1 | this review | done |
| 2 | Parts 2 and 3 | this review | done |
| 3 | Part 4 | this review | done |
| 4 | Part 7 | this review | done |
| 5 | Part 5 | its own, for the engine copy | not started |
| 6 | Part 6 | its own, for the rule change | not started |

For each slice:
- unit and byte-oracle tests;
- guest steps per key and wire operations per key, from the typing run, before
  and after;
- Desk with Pad (`physical_desktop_acceptance.py --applet pad`) while building;
- the full Desktop journey once at the end, one run at a time under the
  existing guards.

## Expected effect

Guest steps per burst frame in the typing run. Rows marked measured come from
the typing tool; the others are estimates from the measured cost of each
stage. Frames vary by about 0.3M from run to run, mostly in Desk's painting
and in where storage lies.

| After | Guest steps per frame |
| --- | ---: |
| Before part 1 (measured) | 25.0M |
| Part 1 (measured) | 24.8M |
| Parts 2 and 3 (measured) | 23.0M |
| Part 4 (measured) | 22.7M |
| Part 7 (measured) | 22.8M |
| Part 5 | about 17.5M |
| Part 6 | about 11M |

Part 4 saves nothing in this run, because no run disappears before the typing
starts. In a session where a menu has closed it saves up to 12% of a key.
Part 7 saves device memory traffic, not steps.

What would remain:
- the documents' snapshot, 3.4M;
- Desk's painting and the terminal service, about 2.5M;
- the work on the changed items themselves.

Going further needs the snapshot itself to follow change.

## Not in this design

- **Recapturing only the part of a document that changed.** The snapshot
  recaptures the whole edited document. Doing less needs a change signal per
  widget. Today UIDL's dirty marks miss widget state that changes outside
  UIDL; Pad bridges that gap itself (`pad.f:2705-2734`). That needs revisions in
  the canonical widgets first.
- **Re-validating unchanged documents' slices.** That guards caller-provided
  banks against corruption, and it stays, as PER-KEY-FRAME-REPEATS decided.
- **An STX1 item patch on the wire.** SEMANTIC-CONTENT-1 names this as the next
  protocol step, if replacing a whole text area becomes the bottleneck. After
  part 1, that is one small control a key.
- **Host-side terminal work.** That is MegaPad's per-frame decoding and
  validation. Part 1 reduces it as a side effect.
- **The hybrid producer's unsent glyph delta.** With the shell installed, the
  shell's emission replaces the hybrid producer's
  (`hybrid-screen-producer.f:13157`), so the hybrid producer's glyph delta is
  never sent. Its identities still feed the object frontier the shell
  allocates from, so dropping it would change identities on the wire. After
  part 4 its comparison is cheap in the usual case, so it stays.
