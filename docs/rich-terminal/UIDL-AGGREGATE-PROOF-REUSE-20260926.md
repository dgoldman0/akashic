# UIDL aggregate proof reuse — September 26, 2026

A typed character made the Desktop guest repeat the same storage proofs
several times before publishing its frame. Three Akashic commits remove the
repetition without weakening any proof that guards a write. Guest work for
the first typed character falls from 16.16 million to 13.74 million
semantic steps. Leaving out the polling and transition phases, which vary
with host timing, it falls from 13.08 million to 11.19 million (−14%).

This is guest work, so it carries over to the real device. In the simulator
it is worth about 30 ms per character, which the current host load hides.

## What changed

- `09154eb` tests occlusion rectangles one row at a time. Each row span is
  clear when its first byte is zero and `COMPARE` finds it equal to itself
  shifted by one byte. On MegaPad `COMPARE` is a BIOS word built on the
  `BCOMP` block-compare instruction. The query used to visit every cell of
  every visible document on each capture.
- `e08e7a3` stops repeating the aggregate proof:
  - RUHA gains `RUHA-SNAPSHOT-IDENTITY@`. It reports the identity of the
    snapshot held for an exact completed draw (generation, content epoch,
    document count) behind the same borrow gate that every lifecycle edge
    closes. It does not capture, prove storage, or hand out the payload.
  - The producer's currency check and its unchanged-path recheck use the
    identity query, so a flush retry while a delta awaits its ACK now costs
    a few hundred steps instead of a full proof.
  - The unchanged-content probe hands its exact observation to the rebuild
    in the same live stage. The handoff is cleared on entry, read by exactly
    one word, and falls back to a fresh observation if the draw changed.
  - RUHA's screen-storage proof uses the enclose-then-split prover instead
    of 13 separate queries.
- `49fddfd` moves that prover into `utils/memory-span.f` as
  `MSPAN-SET-PROVE-DISJOINT?`, over a span set the caller fills by its own
  rules:
  - RUHA and the menu, collection and data-graphics captures each prove
    their caller spans with one enclosed query instead of one per span.
    Each such query walks the whole document's storage.
  - The data-graphics capture returns an empty result before its authority
    proof when the document has no mounted DATA_GRAPHICS relation, since the
    complete path would then read and write nothing.

Every capture, the only step that writes, still runs behind a full proof in
the same call. Fragmented storage still splits down to exact per-span
proofs. The L0 ratchet records the reviewed mutable-state change.

## Guest work

First-character profiles use the archived `simulator-calls-20260917`
observer at an 8,192-step quantum for phase attribution. MegaPad is
`a649f32` throughout.

| Phase | Before (`31d5056`) | Changes 1–4 (`e08e7a3`) | All five (`49fddfd`) |
| --- | ---: | ---: | ---: |
| UIDL aggregate | 4.14 M | 2.65 M | 2.25 M |
| Hybrid preflight | 2.92 M | 2.92 M | 2.92 M |
| Delta compare | 2.52 M | 2.51 M | 2.51 M |
| Residual plan | 1.43 M | 1.43 M | 1.44 M |
| Other measured phases | 2.07 M | 2.06 M | 2.07 M |
| Polling ("other") | 2.92 M | 2.07 M | 2.42 M |
| Transition boundaries | 0.16 M | 0.15 M | 0.13 M |
| Total | 16.16 M | 13.79 M | 13.74 M |
| Without polling and transition | 13.08 M | 11.57 M | 11.19 M |

The before profile ran at Akashic `31d5056`, whose code equals `dd8d4ab`.
The "other" phase covers the app shell's polling loop. Part of its first
drop is real (the removed currency proofs ran there), but it also counts
polling while the guest waits on the host at both ends of the measured
window. That share varies with host timing, which is why it rose between the
last two runs.

## Qualification

- The canonical 22-stage physical Desktop journey passes after changes 1–4
  (156.4 s) and after all five (122.7 s): 18 milestones in order, 21
  revision-bound inputs with no manual input, 27 physical acknowledgements,
  and both CELL fallback checks. The native binary is unchanged.
- Rendering is unchanged. Old and new milestone screenshots differ only in
  16 cells of the File Explorer size column, which lists the image's source
  shards; their sizes follow the edited source files. The old tree
  reproduces the earlier runs' pixels exactly.
- Fast selectors pass 432 tests. They include a new exact-emulator test of
  17 occlusion rectangles and the prover harness on both simulator
  executors for both RUHA proofs, with nested and throwing cases.
- Two alternating old/new typing pairs at the 65,536-step default cannot
  resolve the expected ~30 ms simulator gain. Viewer composition, which
  involves no guest work, ranged from 57 to 115 ms across the four runs.

## What remains

About 11 million measured guest steps per character remain. The largest are
hybrid preflight (2.9 M), delta comparison (2.5 M), UIDL aggregation
(2.25 M, mostly Pad's real recapture) and residual planning (1.4 M). Each
still walks the whole screen or document on every update. The
[host-quantum report](SIMULATOR-QUANTUM-PERFORMANCE-20260926.md) also records
that the Desktop guest polls continuously instead of idling.

## Evidence

`local_testing/evidence/uidl-aggregate-proof-reuse-20260926.json` holds the
three profiles, both journeys, the four typing runs, the pixel comparison,
bindings, raw-file hashes and analysis hashes. Artifacts are in
`local_testing/out/lever1-20260926/`, which is ignored.
