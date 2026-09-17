# Exact glyph-layout reuse — September 16, 2026

Akashic `389688d` and `d828c29` avoid spatial rematching when a fresh glyph
bank has exactly the acknowledged visible layout. Three sequential paired
physical typing comparisons improve median isolated feedback from 0.713 to
0.621 seconds and the median of burst medians from 1.038 to 0.922 seconds.
The delta comparison/normalization phase falls from about 5.73 to 2.52 million
guest steps. This is a useful reduction, but the resulting response still
does not feel fluid at the benchmark's five characters per second.

## Production change and correctness

The observed typing frames have 784 residual glyph runs with unchanged
geometry and styling. One status-line run changes text; Pad's document body
continues through its ordinary semantic text control. The new path is a
generic layout proof in the hybrid producer, with no applet-specific branch.

The active bank still passes the existing full canonical, reference and ID
audit. The shortcut then checks equal slot counts, equal bank geometry, an
all-visible active layout, every non-ID item byte, every pending text
reference, fresh pending IDs and the complete inverse-map binding. A miss
leaves the banks, map, operation count and pending-visible count unchanged
for the existing general matcher. Invisible reserves retain general
tombstone canonicalization.

After the whole proof succeeds, the helper copies stable IDs by ordinal,
compares bounded text spans and writes the existing sparse change markers.
Packed bases are computed once for this immediate pass. Proof is not kept
across emission. Compact-plan validation, sealing, publication and physical
ACK admission retain their existing checks. There is no ABI/version change,
new capacity, source cache or simulator timing modification.

Review found that the first implementation left the pending-visible count
stale for an unchanged frame's revision fence. `d828c29` updates that count
on every successful proof, including an empty bank. An executed regression
first reproduced the wrong glyph carrier and now verifies the current
control/glyph carrier choice on both executors. The layout suite is tracked in this corrective commit. The earlier physical
diagnostic at `389688d` is excluded
from the final paired results and qualification.

## Bounded helper comparison

The same generated bank contains 784 visible one-byte runs, permuted stable
IDs and one changed text byte. Each bank occupies 110,464 bytes. Both source
closures run with the same native extension and checked-in 3,000,000-step
limit per invocation. The general comparison loop runs in Forth. Eight
alternating pairs run sequentially; the first pair is retained as warmup,
and medians use the remaining seven. Compilation and fixture setup are
outside the measured intervals; native profiling is disabled.

| Work | Previous steps | Current steps | Previous thread CPU | Current thread CPU |
| --- | ---: | ---: | ---: | ---: |
| Matching and text comparison | 3,532,925 | 316,234 | 51.992 ms | 4.069 ms |
| Including slot audit and plan compaction | 4,374,413 | 1,157,722 | 62.404 ms | 14.093 ms |

Every trial has identical active and pending bank bytes, map and guard bytes,
operation count, current visible count, object frontier and compact plan.
The active bank stays unchanged and delayed glyph-plan validation passes.
These are generated helper banks, not captured Desktop banks or source-load
timings. Host CPU includes ordinary execution/settlement and result checking.

## Physical typing comparison

Every pair uses the ordinary source-mode Desktop, the same 3080×1764 physical
viewport and font, one isolated character, then eighteen inputs at 5 Hz.
Akashic is `183ca1d` before and `d828c29` after. MegaPad stays at `6bed823`
with extension SHA256
`c346fa9fd03d56b98b1fc97ecb2b4c5ba28a2d3663ffd2fb08d3d15555250172`.
Each previous-source run temporarily selects that commit in the existing
checkout and restores `main` afterward.

| Pair | Akashic | Isolated | Burst median | Final drain |
| --- | --- | ---: | ---: | ---: |
| 1 | Current | 0.621 s | 0.922 s | 0.946 s |
| 1 | Previous | 0.713 s | 1.038 s | 1.039 s |
| 2 | Current | 0.659 s | 0.924 s | 0.941 s |
| 2 | Previous | 0.728 s | 0.999 s | 0.998 s |
| 3 | Current | 0.613 s | 0.921 s | 0.955 s |
| 3 | Previous | 0.689 s | 1.074 s | 1.049 s |

| Median isolated diagnostic interval | Previous | Current |
| --- | ---: | ---: |
| Owner-thread CPU | 528.30 ms | 473.97 ms |
| Native execution elapsed time | 242.37 ms | 212.50 ms |
| Native settlement elapsed time | 17.83 ms | 15.95 ms |
| Delta phase steps | 5,726,443 | 2,515,054 |
| Delta phase owner CPU | 126.98 ms | 58.59 ms |

The observer is identical in all six runs and active only for the isolated
interval. These are paired diagnostics; the unprofiled result below is
separate. Native elapsed timers overlap owner time and cannot be subtracted
from owner CPU as exact CPU costs. Shared-host throughput and composition
vary, so these observations do not assign the whole latency difference to
the change or establish a confidence interval.

Every run shows all 19 characters in order. Median scheduled-due-to-ACK burst
latency improves from 1.064 to 0.966 seconds. Actual dispatch can lag the
requested schedule; individual latencies, backpressure and frame groupings
are retained in the evidence. Native coverage remains above 99.975%.

All three initial, isolated and final images match exactly within each
source version. Cross-version pixel differences are confined to the three
File Explorer size labels for `source-16.src`, `source-18.src` and
`source-23.src`, within `(1871, 655, 1891, 815)`. The retained draw comparison
also verifies every other draw field. Final text-content revisions sometimes
differ because inputs group into different frames; the canonical STX1
decoder proves every content field and item equal after accounting for that
revision alone. The actual revision-bound input/ACK checks are unchanged.

The UIDL aggregate phase measures approximately 3.74 million steps before
and 4.14 million after, despite no change to that module in this slice. This
increase remains unlocalized; its median measured CPU is about 100 ms in
both versions. It is not hidden in the claimed delta-phase reduction.
Hybrid preflight remains near 2.92 million steps, residual planning near
1.43 million. Whole observed intervals vary from 18.45–18.92 million steps
before to 16.05–16.42 million after, including variable idle boundaries.

## Qualification and remaining work

The focused glyph-layout, glyph-growth, glyph-frontier and hybrid-producer
selector passes 182 checks in 8.40 seconds. It covers Python/native bank and
plan equivalence, late misses without writes, malformed references and map
entries, layout and namespace failures, full-width IDs, empty/UTF-8 text,
invisible reserves, stale visibility and 32/128/784-run work reductions.

`physical-menus-4d71g4_a` passes the full ordinary Desktop journey with 18
milestones, 21 inputs, 27 post-flip ACKs and both CELL fallback gates. Its
milestone/input sequences match the previous accepted journey. It uses X11
`pygame.display.flip` and zero manual input RPCs, takes 136.388 seconds and
peaks at 443.988 MiB. This is functional regression evidence, not a controlled
whole-journey timing comparison.

The final unprofiled run, `fixed-vpiuhjzg`, displays all 19 characters with
0.731 s isolated feedback, a 1.090 s burst median and 1.067 s final
drain. The first response includes 585.253 ms to observe the offer,
60.094 ms reconstruction, 66.163 ms composition and 19.397 ms flip/ACK.
Maximum scheduling delay is 275.866 ms, additional to actual-dispatch
latency. The run takes 66.406 seconds and peaks at
381.441 MiB; its three milestone images exactly match the current
diagnostics. This result is slower than the current diagnostic series and
the previous turn's unprofiled sample. It is a current-only observation,
not a controlled reversal or an additional paired speedup measurement.
The paired medians should not be presented as a guaranteed latency.

All checks run sequentially with unchanged budgets and the existing
900-second / 3.5-GiB physical guards. Paired runs take 63.70–67.19 seconds
and peak below 383 MiB, with exit 0 and no guard stop. Resource glances show
about 10–12 GiB available RAM. The earlier `fixed-h5p2u662` diagnostic remains
available but is excluded because it predates the visibility correction.

The next larger target is repeated UIDL aggregation and preflight over
unchanged scene data: together they still execute about seven million guest
steps per isolated update. The remaining delta work and host publication /
reconstruction / composition also matter. The current shortcut addresses
glyph identity matching; it does not remove those full-scene traversals or
the remaining display latency.

Raw artifacts and exact comparison/aggregation scripts are under
`local_testing/out/typing-glyph-layout-20260916/`. The paired runs, in order,
are `fixed-6aieiphj`, `baseline-kd95pkpp`, `fixed-bcned55x`,
`baseline-3eceytv5`, `fixed-x75rp5vy`, and `baseline-y2z6zq1b`. Tracked
`local_testing/evidence/typing-glyph-layout-20260916.json` preserves all
observations, helper trials, source/binary bindings and qualification.
Reproduction commands are in `local_testing/evidence/typing-20260916.md`.
