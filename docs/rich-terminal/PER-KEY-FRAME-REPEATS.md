# Per-key frame work: what repeats, and what it takes to stop — design, 2026-09-28

Status: proposal. Nothing here is implemented yet.

## Summary

A typed character now costs the guest about 3 million steps on average, and
about 11 million for a key typed alone. Almost all of that (91%) is the rich
frame builder (`RTHP-PREPARE`). Desk's own painting is about 3%. For a
one-character change, the builder still processes the whole frame: it
admits, compares, and partly re-validates every item on screen.

The rule for this work: remove only work that is provably repeated. The proof
must come from the module that owns the data, from facts it already
maintains. A check is never skipped on another module's word.

Under that rule, two changes are safe repeats, both inside the frame
builder's comparison stage:

1. Derive the acknowledged frame's lookup data once, when it is
   acknowledged, instead of on every frame.
2. Carry the glyph builder's own record of which rows it copied unchanged,
   so the comparison does not rediscover it.

Together they should remove roughly 14% of the guest's work per key. For a
key typed alone that is about 1.5 million steps, or 15 to 25 ms on the
simulator today. It helps the real device equally.

The two larger stages, whole-frame admission and the document snapshot, can
only shrink further in one of two ways. The engine could keep its own extra
copy of the frame, which costs memory. Or a check could be dropped, which
weakens protection. Neither is proposed here. They are listed below so the
choice is visible.

## Where one key's guest work goes

Measured with a call-stack observer over every typed key's window, from the
key's arrival to the last publication of its frame. The figures are after
Akashic `538b4020`, as shares of per-key guest work.

| Stage | Share | Verdict |
| --- | ---: | --- |
| Comparing the new frame with the acknowledged one | 26% | part repeat (items 1 and 2) |
| Admitting the whole candidate frame | 21% | exact only with a memory cost (item 3) |
| Snapshotting documents | 12% | real work, plus one check that guards corruption (item 4) |
| Planning plain-text rows | 11% | real work; already follows damage |
| Building controls | 6% | real work; menus are already reused |
| Recording changes for the engine | 5% | real work |

## 1. Derived data for the acknowledged frame — safe repeat

**What happens now.** Every frame, the comparison walks the whole
acknowledged bank. It re-validates every glyph item's structure
(`_RTHP-D-CANONICAL-SLOT?`), rebuilds the object-to-slot map
(`_RTHP-D-BUILD-SLOT-MAP?`), finds the lowest object number
(`_RTHP-D-GLYPH-BOUNDS?`), and sorts the controls by identity
(`_RTHP-D-ACTIVE-CONTROL-INDEX?`, and half of `_RTHP-D-SORT-IDENTITIES?`).

**Why it repeats.** A bank becomes the acknowledged bank in exactly one
place, `_RTHP-TARGET-PUBLISH?`, and no code writes it while it holds that
role. Each result above depends only on that bank's contents. Each is
therefore identical on every frame until the next publication.

**Change.** Compute these once, in `_RTHP-TARGET-PUBLISH?`, and keep them
with the bank. The comparison marks slots as used by writing into the map,
so it will work on a fresh copy of the kept map, or on a separate used-marker
array. A copy is a straight memory move, far cheaper than re-validating.

**Proof.** The owner of the data (the frame builder) computes the result
from the same bytes, at the only point those bytes change role. Any new
publication recomputes. A test pins that nothing writes the acknowledged
bank.

**Expected saving.** About 8% of per-key work.

## 2. The glyph builder's copy record — safe repeat

**What happens now.** The glyph builder already decides exactly which screen
rows are clean. It decides this from the screen's own flush plan, the
acknowledged frame's watermark, and the claim and residue maps. It copies
those rows byte-for-byte from the acknowledged bank
(`_RTHP-RD-COPY-ACTIVE-ROW?`). Then, on purpose, it renumbers every item, so
the new frame is byte-identical to a full rebuild. The comparison then
rediscovers, item by item, what the builder already knew: it re-validates
structure and tries to line up the layout (`_RTHP-D-TRY-GLYPH-LAYOUT?`).

**Change.** Keep the candidate bytes exactly as they are. Beside them, the
builder records, for each item it copied, which acknowledged item it copied.
The comparison pairs those items directly and skips their re-validation and
layout search. Items with no copy record take the existing full path.

**Proof.** The record is written by the same module, in the same frame, by
the same code that performed the copy. Nothing outside the builder writes
it. The candidate stays identical to a full rebuild, so every downstream
guarantee is unchanged.

**Test.** For recorded frames, the plan made with copy records must equal,
byte for byte, the plan made by the existing full comparison. The full
comparison stays in the code as that oracle.

**Expected saving.** About 6% of per-key work.

## 3. Whole-frame admission — exact only with a memory cost; not proposed now

**What happens now.** The engine's admission (`RTE-HYBRID-PREFLIGHT`)
checks every item of the candidate every frame. For glyph runs, 9% of the
per-key work is re-checking text that is unchanged. The admission also
totals counts and byte sizes, so the engine can prove the complete scene
fits. The totals are cheap and needed.

**Why it cannot simply be skipped.** Admission is the engine's boundary
check on data the frame builder owns and can change. The engine keeps no
copy of what it admitted last time. So it cannot tell, by itself, that an
item is the same as before. Skipping on the builder's word would weaken that
boundary.

**Exact option.** The engine keeps its own copy of the admitted items and
text, and compares new items against it, re-checking only items that
differ. This costs a third full copy of the frame (the builder already keeps
two). It also still costs a comparison of every byte. It is worth doing only
if a measurement shows the comparison is much cheaper than the check it
replaces. Recommendation: measure after items 1 and 2, then decide.

## 4. Document snapshot — real work plus a corruption guard; not proposed

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

## Order of work and qualification

1. Item 1: kept derived data for the acknowledged bank.
2. Item 2: copy records, with the full comparison kept as the test oracle.
3. Measure. Then decide on item 3, using the measured comparison-to-check
   cost ratio.

Each step lands with structural and behaviour tests, the rich-path suites,
one canonical physical Desktop journey, and one typing-cadence measurement
with the timing observer. Each lands as its own commit.

## What stays as it is

- Every check at a module boundary, on data another module owns.
- Re-validation of caller-provided banks that the design says must be
  re-validated.
- The canonical candidate: byte-identical to a full rebuild.
- The full comparison path, for every item without a copy record.
