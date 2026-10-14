# A typed character's frame work — design, 2026-10-14

Status: approved for parts 1 to 4 and 7 on 2026-10-14, and for parts 5 and
6 later that day. All seven parts are done; each records what it did.

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
- **Exact speed-up:** it does the same work in fewer steps. Its tests check
  that the outputs are byte-identical.

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

**Change.**
- Each admission boundary keeps its own copy of the glyph plans and control
  plans it last admitted, with the plan header each was checked against
  (owner, generation, surface and region geometry). Fields are not kept: a
  field's content check also places its label.
- An item equal to its copy, against an equal header, skips the checks that
  read only what was compared:
  - a glyph run, in every byte but its identity, text included: its fields,
    geometry and ranges, and the UTF-8 decode of its text;
  - a control, in every byte but its identity, its parent and its span
    addresses, with or without a parent as its copy, and with the same
    label, shortcut and content bytes: its fields and kind, its content's
    shape, and its label text.
- Every item still gets the checks that read anything else: its identity and
  order, its text reference or its spans' shape and place, and, for a control,
  its correlation and graph. Totals are added up item by item as before.
- Glyph runs are matched in row-major order, so a changed row shifts nothing
  after it; controls are matched by position. A match never decides
  validity: only the byte comparison does.
- The copy is the engine's own. Its block comes from a memory source the
  caller attaches (`RTE-ADMITTED-MEMORY!`); it is grown, to what the last
  admission needed and half again, before the next admission's first proof,
  and written only after the provider accepted the batch. Without a memory
  source nothing is kept.
- The admission proofs keep every candidate span and admission record apart
  from the blocks. The engine's general storage proof, which guards each
  validator's own scratch and which many modules reach, does not name them.

**Proof.** Only the admitting module writes the copy, from items it has just
checked in full against the same header. An item equal to its copy in every
byte its skipped checks read passes them again; the copy cannot be the
candidate, because the candidate's spans are proved apart from it.

**Effect.** Most of the 23.1% the two admissions take today, chiefly their
per-item checks, such as the UTF-8 decode of every glyph run's text.

**Done** (Akashic `ced4b866`, `a330639c`, `f1656a90`). Per burst frame, the
engine's admission fell from 2.34M to 1.01M steps and the shell's preflight
from 3.34M to 2.15M; the frame build fell from 19.56M to 16.66M. In unit
tests, sixty unchanged runs cost 45.0K steps instead of 118.7K, and ten
unchanged controls 34.2K instead of 54.7K. Putting the blocks into the
engine's general storage proof instead cost about 0.8M steps a frame: the
checks themselves, and other modules' range proofs split around the
blocks.

## Part 6. Remove what the call tree shows is still repeated — repeat, exact speed-up

**Today.** After part 5 a burst frame's build costs 16.7M steps. A call tree
of those frames, with every call chain kept (`MEGAPAD_PROFILE_CHAINS=0
MEGAPAD_PROFILE_CHAIN_DEPTH=0`), shows where they go:
- Desk's shell producer: its preflight 2.2M, its freeze 2.0M, its glyph
  planning 1.3M and its emission 0.5M. Building the batch itself is about
  0.6M.
- The hybrid producer's candidate: 3.8M, of which controls 1.1M, glyph runs
  1.1M and the engine's admission 1.0M.
- The comparison with the acknowledged frame: 1.5M.

**Change.** Four items, smallest risk first, each measured as it lands:
1. Check the shell batch's structure once.
2. Append plain glyph cells without the planner's general path.
3. Remove what the admissions and the shell's storage proof still repeat.
4. Skip, in the shell's emission, glyph families equal to the acknowledged
   ones.

### 6.1 Check the shell batch's structure once

**Today.** The shell checked each frame's family batch graph three times:
the family preflight when it admits the batch, the freeze when it measures
it, and the frozen bank. The middle check cost about 0.75M steps a frame.

**Proof.** The middle check repeats the first. A START freezes right after
its preflight. A DELTA's identity mapping writes the batch in between, but
nothing the graph check reads: it reads identities only as a pane's, which
stay nonzero, and the new glyph arrays come fresh from the work space, apart
from every span the batch names. The freeze still checks every span's shape
and storage, and the frozen bank is still checked in full.

**Done** (Akashic `bf1a0d1a`). The freeze fell from 2.03M to 1.25M steps a
burst frame, and the frame build from 16.66M to 15.86M.

### 6.2 Append plain glyph cells directly — exact speed-up

**Today.** The residual glyph planner read every cell through its general
path: load and check the cell, encode it, compare its style, feed the
grapheme segmenter, append it. That cost about 600 steps a cell, and the two
producers scan about 1,100 cells a frame on the changed rows.

**Change.** Once the general path has added a printable ASCII cell to an open
run, each next cell of that kind, in the run's style and at a column where
no claim begins or ends, is appended directly, up to the run text limit and
the text room. Any other cell goes through the general path as before.
`cell.f` gains `CELL-STYLE@`, a cell with its codepoint cleared, so the
planner compares colours and attributes without knowing the layout.

**Proof.** For such a cell every step of the general path has a known
result:
- a zero claim difference changes no count, so the plane read stays;
- a raw style equal to the run's passes every attribute check and continues
  the run;
- the text is the cell's one byte, or a space for an empty cell;
- the segmenter, given an ordinary character after an ordinary character,
  breaks and keeps its state, as `GR-BREAK?` documents.

A Python model of the general path, written from the planner's contract,
is the oracle in the planner's tests. Random rows with menus, claims, clips,
small run limits and tight text room, holding every kind of cell, give
exactly its results and runs. Mutating the fast path fails them.

**Done** (Akashic `fd7348f9`). A blank cell costs 90 steps instead of 583.
Per burst frame the planner fell from 1.55M to 0.97M steps, and the frame
build from 15.86M to 15.33M. The isolated first character's frame build
fell from 25.69M to 24.64M.

What the planner has left is mostly per call. The shell calls it once for
each changed band of each pane the band crosses, ten to fourteen times a
frame in the typing run, and every call checks every claim and every span:
0.34M and 0.17M a frame across both producers. One call per region would
save about 0.25M of that, but both producers would have to take their kept
rows through the planner, so it is not part of this plan. Copying the
unchanged rows' runs costs another 0.7M a frame.

### 6.3 What the admissions and the shell's proofs still repeat

**Today.** After 6.2 the two admissions cost 3.2M a burst frame. Their
per-item work is the copy comparison of part 5 and the checks part 5 keeps:
each item's spans, which lie at new addresses every frame, its identity and
order, the control graph and the totals. None of that repeats within a
frame. Two repeats sit beside them.

**The batch's span check.** The family preflight's pairwise span check takes
one pass over spans that rise in address in the order the batch lists them:
plan, items, text, references. The shell laid out each glyph family's
references before its text, so every glyph family's references sent the
check down its slow path, which compares a span with every span before it:
about 1,400 pairs a frame. The shell now reserves and compacts a glyph
family's text before its references. Every move still goes to a destination
at or before its source, and only where the two spans lie changes.

**The shell's storage proof.** For each of its four spans the shell asked the
shell source's live predicate, and then the source's install-time check of
the live owners. The live predicate already makes each of those checks on the
same span, as strictly or more, so the second call is gone. Inside the live
predicate, the source's validity and the span's place beside the source's
dependent storage were also checked twice; they are now checked once.

**Done** (Akashic `646da06b`, `c08bc3be`). Per burst frame the shell's proof
fell from 1.16M to 0.91M steps and its preflight from 2.16M to 1.97M; the
frame build fell from 15.33M to 14.89M.

### 6.4 Skip equal glyph families in emission — exact speed-up

**Change.** The shell's DELTA emission compares each glyph run of the pending
bank with the active bank's. When a glyph family has as many runs as the
active family, and its runs, references and text are byte for byte the active
family's, every run is the same, so the family is skipped after three block
comparisons. Any difference takes the run-by-run path. This is the emitter's
own comparison of its own two banks.

**Done** (Akashic `57fafc36`). Emission fell from 0.49M to 0.40M steps a
burst frame. The frame build rose from 14.89M to 15.10M in that run because
the documents' snapshot rose from 2.99M to 3.26M; without the snapshot it
fell from 11.90M to 11.84M.

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
  - This is inferred from the code, not run. No part of this design touches
    that code.
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
| 5 | Part 5 | its own, for the engine copy | done |
| 6 | Part 6 | its own | done |

For each slice:
- unit and byte-oracle tests;
- guest steps per key and wire operations per key, from the typing run, before
  and after;
- Desk with Pad (`physical_desktop_acceptance.py --applet pad`) while building;
- the full Desktop journey once at the end, one run at a time under the
  existing guards.

## Expected effect

Guest steps per burst frame in the typing run, and of those the frame build
(`_RTHP-PREPARE-LIVE`), which the parts change. Rows marked measured come from
the typing tool; the others are estimates from the measured cost of each
stage.

All steps per frame also count Desk's painting, which happens once a key: when
the host is slower, more keys fold into each frame and the figure rises
without any change in the guest. The frame build is the measure to compare.
Within it, the documents' snapshot moves by up to 0.8M from one build to the
next, as the storage its range proofs check shifts with unrelated changes.

| After | Steps per frame | Frame build |
| --- | ---: | ---: |
| Before part 1 (measured) | 25.0M | 20.9M |
| Part 1 (measured) | 24.8M | 21.1M |
| Parts 2 and 3 (measured) | 23.0M | 19.8M |
| Part 4 (measured) | 22.7M | 19.9M |
| Part 7 (measured) | 22.8M | 19.6M |
| Part 5 (measured) | 19.3M | 16.7M |
| 6.1 (measured) | 18.7M | 15.9M |
| 6.2 (measured) | 17.9M | 15.3M |
| 6.3 (measured) | 18.0M | 14.9M |
| 6.4 (measured) | 17.8M | 15.1M |

Part 4 saves nothing in this run, because no run disappears before the typing
starts. In a session where a menu has closed it saves up to 12% of a key.
Part 7 saves device memory traffic, not steps.

What remains of a burst frame's 15.1M build, measured after part 6:
- the documents' snapshot, 3.0M to 3.3M;
- the hybrid producer's candidate, 3.5M, with the engine's admission 1.0M;
- the shell's preflight 2.0M, freeze 1.25M, storage proof 0.9M and
  emission 0.4M;
- the comparison, 1.5M;
- glyph planning and the copying of unchanged rows' runs, about 1.9M across
  both producers.

Smaller repeats measured on the way, each needing a change in more than one
module:
- the planner checks every claim and span once per call, about ten calls a
  frame; one call per region would save about 0.25M;
- the shell's storage proof checks the source's validity and walks UIDL's
  collections once for each of its four spans, about 0.25M together;
- copying unchanged rows' runs one at a time, about 0.7M, could take whole
  rows at once.

The adapter re-validates its own state at each entry, six times a frame and
0.8M in all. That state lives in caller-provided storage, which this design
keeps re-validating.

Going further than that needs the snapshot itself to follow change.

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
