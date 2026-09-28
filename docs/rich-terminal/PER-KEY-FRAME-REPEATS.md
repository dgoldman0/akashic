# Per-key frame work: what repeats, and what it takes to stop — design, 2026-09-28

Status:

- Kept comparison facts: landed in Akashic `1f9c2253`, in a corrected form
  (see below).
- Engine admission of unchanged items: profiled. The decision is open.
- Document snapshot: not proposed.

Evidence: [lag-storage-proofs-20260928.md](../../local_testing/evidence/lag-storage-proofs-20260928.md).

## Summary

A typed character cost the guest about 3 million steps on average, and
about 11 million for a key typed alone. Almost all of that (91%) is the rich
frame builder (`RTHP-PREPARE`). Desk's own painting is about 3%. For a
one-character change, the builder still processes the whole frame: it
admits, compares, and partly re-validates every item on screen.

The rule for this work: remove only work that is provably repeated. The proof
must come from the module that owns the data, from facts it already
maintains. A check is never skipped on another module's word.

Under that rule, keeping the comparison's facts removed 12% of each typing
frame's guest work: the frame build fell from 9.70M to 8.57M steps per frame.
The engine's admission of unchanged items is the largest remaining repeat:
about a quarter of each frame. It can only be removed exactly with an
engine-owned copy of the admitted frame, which costs about 14 MB for Desk's
largest surface.

## Where one key's guest work went before this work

Measured with a call-stack observer over every typed key's window, from the
key's arrival to the last publication of its frame. The figures are after
Akashic `538b4020`, as shares of per-key guest work.

| Stage | Share | Verdict |
| --- | ---: | --- |
| Comparing the new frame with the acknowledged one | 26% | part repeat, now removed (kept comparison facts) |
| Admitting the whole candidate frame | 21% | exact only with a memory cost (engine admission) |
| Snapshotting documents | 12% | real work, plus one check that guards corruption (document snapshot) |
| Planning plain-text rows | 11% | real work; already follows damage |
| Building controls | 6% | real work; menus are already reused |
| Recording changes for the engine | 5% | real work |

## Kept comparison facts — landed, `1f9c2253`

**What happened.** Every comparison audited the whole acknowledged bank. It
re-validated every glyph item's structure (`_RTHP-D-CANONICAL-SLOT?`),
rebuilt the object-to-slot map (`_RTHP-D-BUILD-SLOT-MAP?`), found the lowest
object number (`_RTHP-D-GLYPH-BOUNDS?`, again at emission), and sorted the
controls by identity (`_RTHP-D-ACTIVE-CONTROL-INDEX?`, and half of
`_RTHP-D-SORT-IDENTITIES?`).

**Correction.** This design first proposed deriving these once, at
publication. That would save nothing. Each bank is compared as the active
bank exactly once: in the typing run, 15 comparisons met 16 publications.
The repeat is across two comparisons. The comparison that built a bank had
already proved the same facts, when the bank was its pending bank.

**Change.** A successful comparison keeps those facts beside the bank it
built: the scalars in the producer record, and the sorted control index in
that bank's own arena annex (two slices of MAX-CONTROLS × 8 bytes, from the
caller bounds). Only that exact bank's publication hands them to the active
role. Any other publication leaves none, and abandoning the pending bank
drops them. The next comparison uses them only for that exact bank at its
exact counts. It still proves the object IDs one exact permutation of the
slot interval, and every kept control ID below its new namespace. A bank
without facts, such as a full START, is audited in full.

**Proof.** The facts come from the module that owns the bank, from checks it
has just run on the same bytes. After those checks, normalization writes only
object IDs and canonical tombstones, which keep every fact true. No producer
word writes a bank while it is active. Tests pin both: the kept path must
give exactly the full audit's results over seeded edit streams, and no word
may store into bank memory through a pointer to the active bank. A scratch
shadow build confirmed both on real frames, over typing and the whole
canonical journey.

**Result.** Per typing frame, the comparison fell from 2.43M to 1.41M steps
and the frame build from 9.70M to 8.57M (12%). The plan check at emission
fell from 0.131M to 0.012M.

## Engine admission of unchanged items — profiled; decision open

**What happens.** The engine's admission (`RTE-HYBRID-PREFLIGHT`) checks every
item of every candidate. It is the engine's boundary check on data the frame
builder owns and can change, so skipping on the builder's word would weaken
that boundary. The exact option is an engine-owned copy of the admitted
candidate. The engine compares each new item with it, and fully checks only
items that differ. The totals it records stay per frame.

**Profile.** A scratch probe compared each admitted item with the one at the
same index in the acknowledged bank, as such a copy would:

- Typing: 695 glyph runs and 154 controls per frame. 99.9% of the runs and
  95% of the controls were unchanged.
- Canonical journey: per-frame medians of 99.7% of runs and 96.5% of controls
  unchanged. 47 of 58 frames had at least 90% of their runs unchanged; the
  rest were layout shifts, such as an application switch.
- Cost: on a typing-size frame, the comparison takes 0.11M steps. The checks
  it would let the engine skip take 2.50M steps (1.85M glyph items, 0.65M
  controls). That is about 4.5%.
- Real machine: the comparison is a block compare of about 117 KB per typing
  frame, one cycle per byte in the emulator's model. The check it replaces
  decodes every text byte in Forth.

**Expected saving.** About 2.3M steps per typing frame, a quarter of today's
frame build. Frames that shift their layout would save less.

**Cost.** Memory for the copy, sized by the same caller bounds as the
candidate. For Desk's largest surface (400 × 200 cells) and control bounds,
about 14 MB: 9.6 MB of glyph items, 3.3 MB of controls, and about 1.1 MB of
text. Desk's fixed banks are about 95 MiB today. The copy lives in the
neutral engine contract, so it needs its own design and approval.

## Document snapshot — real work plus a corruption guard; not proposed

About 7% of per-key work is freshly capturing the edited document. That is
real work, because the document changed. The menu part of that capture
repeats when only the text changed. Removing it would need UIDL-TUI to prove
the menu's inputs unchanged, which needs its own audit first.

About 3% is re-validating the stored slices of unchanged documents before
reusing them. Those slices sit in caller-provided banks. The design
deliberately re-validates them and rejects a digest as proof. Skipping the
check would drop a guard against corruption of those banks, so it is not
proposed.

About 2% is the per-frame storage check against each document's context.
Part of that is already reused (Akashic `09154eb`, `e08e7a3`, `49fddfd`).
Whether the rest could be kept with a per-context layout serial, like the
engine's geometry proof, needs its own look.

## What stays as it is

- Every check at a module boundary, on data another module owns.
- Re-validation of caller-provided banks that the design says must be
  re-validated.
- The canonical candidate: byte-identical to a full rebuild.
- The full audit, for every bank without kept facts.
