# Control-index sorting and fragmented storage — September 16, 2026

The subsequent [paired latency investigation](TYPING-LATENCY-COMPARISON-20260916.md)
does not reproduce a consistent regression across three alternating pairs.
It measures about 3x faster native execution for the same captured control
join and a small overall benefit. This report preserves the initial trial.

Akashic `96d770d` reduces the real typing control join from 2,359,909 to
679,384 semantic steps with an identical output map, a 71.2% reduction.
Akashic `a23e058` makes storage proofs handle fragmented allocation without
falling straight back to every individual buffer. Together they reduce the
sampled first-character interval from 20.153 million to 18.408 million steps.

The latest unprofiled physical run records 0.733 s isolated feedback and a
1.222 s burst median, preserving all 19 characters. Those times are slower
than the preceding 0.636 s / 1.124 s repeat. Shared-host timing varies, and
this pass establishes no visible latency gain or fluidity qualification.
The deterministic work reduction and full functional acceptance are useful;
the roughly 100 ms feedback target remains unmet.

## Control join

The ordinary first-character banks contain 150 controls. Active graph IDs
are already ordered, while the pending semantic index consists of two
ordered runs. The old implementation nevertheless heapsorted all four
indexes. Its comparisons also recalculated the same packed-bank addresses.

The replacement merges adjacent natural runs through the existing ORDER2
map prefix. That prefix has no mapping authority until the final join,
which clears it before filling matched graph ordinals. Ordered inputs need
one scan; each merge pass at least halves the run count, preserving
O(n log n) worst-case work. The sort binds the immutable bank's key base
and stride once. It adds no allocation or capacity, and changes no bank bytes.

Complete 64-bit IDs, all six semantic identity cells, duplicate rejection,
ID/correlation bijections, growth/deletion rules, and caller bounds remain
checked. Exact map equality is verified for the captured typing banks and
synthetic ordered, reversed, shuffled, and independently reordered cases.
The isolated helper retains its checked-in 3,000,000-step allowance.

| Identical helper input | Previous steps | Current steps | Reduction |
| --- | ---: | ---: | ---: |
| Captured typing, 150 controls | 2,359,909 | 679,384 | 71.2% |
| Ordered, 128 controls | 2,184,166 | 314,307 | 85.6% |
| Reordered, 128 controls | 2,068,834 | 914,026 | 55.8% |
| Random full-width identities, 128 controls | 1,728,142 | 1,180,413 | 31.7% |

These compare guest work under native execution, not host elapsed times.
The captured IDs, correlations, and packed-prefix counts come from
`fixed-y5cb8bba`; both implementations execute against the same bounded
fixture banks and return the same complete graph map.

## Allocation-sensitive storage work

The first whole-typing diagnostic after sorting got worse overall despite
the smaller join. Inclusive adapter-storage samples rose from 0.557 million
to 4.383 million steps. The previous enclosing-range optimization was
correctly rejecting a gap and then checking all thirteen spans separately.

The source-layout change exposed recycled XMEM allocations: the descriptor
and small buffers occupied approximately `0x0cae4730..0x0caf3680`, while
large buffers occupied `0x0e229250..0x0f0a22c0`. A live UCTX began at
`0x0caffbb8`, inside the gap. A single range containing both allocations
therefore could not prove disjointness. XMEM's first-fit free list makes
such placement dependent on earlier allocations and reclaimed source buffers.

The proof now splits a rejected group between its lowest and highest actual
buffer starts, then queries each complete subgroup. It never clips a span,
reads or writes a gap, or assumes allocation order. Every split reduces the
number of distinct starts; equal starts make the query exactly the longest
actual span, whose rejection is conclusive. There is no span array, fixed
capacity, allocation, or retained proof. Invalid geometry rejects and source
state is still checked through the existing complete authority query.

For n distinct starts there are at most 2n-1 queries. A completely fragmented
case can therefore cost more queries than the former individual fallback;
clustered and separated allocations benefit without changing acceptance.
Focused execution proves that two distant allocations need three queries
instead of fourteen, even with their fields shuffled, while one clear
allocation still needs one. Real final storage samples return to about
0.549 million steps. The final physical layout still has two distant buffer
allocations, but its sampled context placements differ; the controlled
fragmentation tests establish the split behavior independently of that layout.

## Full-path diagnostic

All runs sample unchanged 8,192-step owner boundaries from the first real
keyboard send through observation of its complete offer. Signal delivery,
phase transitions, and idle boundaries make totals approximate. Native
counters freeze at the same stop boundary. Observer timings are separate
from the unprofiled physical results below.

| Sampled work, million steps | Before | Sort with fragmented fallback | Sort and grouped proofs |
| --- | ---: | ---: | ---: |
| Entire sampled interval | 20.153 | 21.947 | 18.408 |
| Delta comparison/normalization | 7.406 | 5.726 | 5.726 |
| UIDL aggregate | 3.728 | 5.939 | 3.736 |
| Hybrid preflight | 2.916 | 2.916 | 2.916 |
| Residual planning | 1.434 | 1.434 | 1.434 |
| Storage proof, inclusive and overlapping | 0.557 | 4.383 | 0.549 |

The delta phase falls 22.7%, and the whole sampled interval falls about
8.7%. Boundary count falls from 2,460 to 2,247. Final native execution covers
18,404,321 of 18,408,273 semantic steps, about 99.98%. Sampled C++ time is
246.708 ms, with 35.012 ms settlement. Inclusive native dispatch is
320.856 ms, guest dispatch 364.123 ms, data/return snapshots 77.250 ms, and
host terminal service 72.334 ms. These timers overlap and must not be summed.

The initial new observer mistakenly captured control owner cells as graph
IDs. The helper replay rejected those samples; they are excluded. Its
correlations, phase/stack samples, and frozen counters remain usable.
The corrected observer reads the production ID offset and has an additional
bound source hash. No production fix was needed for the diagnostic defect.

The remaining delta phase includes about 1.745 million steps in glyph-ID
normalization and 1.794 million in glyph comparison. Packed glyph-address
calculation appears in about 1.966 million inclusive steps across callers;
that attribution overlaps those operations. These traversals, followed by
hybrid glyph validation and simulator boundary costs, remain useful targets.

## Physical typing and Desktop acceptance

`fixed-6fhz3u7z` binds clean MegaPad `9bf21e6` and Akashic `a23e058`.
It uses the ordinary source-mode Desktop, normal keyboard forwarder, same
font and 3080×1764 viewport, and exact complete-frame ACK after X11 flip.
Profiling is disabled. One isolated character precedes eighteen individually
scheduled inputs at 5 Hz; every character appears in `~fluid typing 12345`.

| Run | Isolated feedback | Burst median | Last-character drain |
| --- | ---: | ---: | ---: |
| Previous repeat, `fixed-5wtujzev` | 0.636 s | 1.124 s | 1.136 s |
| Current, `fixed-6fhz3u7z` | 0.733 s | 1.222 s | 1.372 s |

The current first response consists of 579.691 ms to observe its offer,
73.194 ms of harness evidence/reconstruction/checking, 66.527 ms composition,
and 13.156 ms flip/ACK. Offer observation includes guest execution, host
services, transport, and polling. Composition spans 53.613–69.546 ms across
the run. Maximum scheduling delay is 178.078 ms, additional to the
actual-dispatch latency in the table. The run takes 66.838 s overall and
peaks at 375.246 MiB aggregate RSS, with exit 0 and no guard stop.

`physical-menus-cph7x09w` passes the full ordinary Desktop journey at the same
heads: 18 milestones, 21 interactions, 27 post-flip ACKs, and both complete
CELL fallback gates. Milestone and input sequences equal
`physical-menus-shyfa8mg`. There are zero manual input RPCs; the sink is
`pygame.display.flip` on X11. It takes 141.296 s and peaks at 442.363 MiB,
with exit 0 and no stop reason. This is functional acceptance rather than
a controlled full-journey speed comparison.

The two focused selectors pass 117 checks in 12.53 s and 82 checks in 4.31 s.
The latter includes the additional `e120d06` fixture protecting every gap,
which exercises both recursive children and the exact worst-case query bound.
The earlier unrelated stale contract-heading assertion remains deferred;
it was not rerun here. All tests ran sequentially, with system resource
glances above 9 GiB available RAM and the unchanged 900 s / 3.5 GiB physical
guards. Native extension, source mode, step limits, public ABIs, and version
counters are unchanged. Development remained on the main checkout.

`local_testing/evidence/delta-sort-20260916.json` preserves physical events,
Desktop evidence, diagnostics, captured control banks and storage geometry,
helper work counts, bindings, and reporting limitations. Raw diagnostics are
`baseline-x97wukn3`, `fixed-y5cb8bba`, `fixed-5j0hwpim`, and `fixed-3d35hutv`
under `local_testing/out/typing-20260916/`. The final directory retains the
corrected observer, harness, helper driver, previous producer source, and
report aggregator. Commands are in `local_testing/evidence/typing-20260916.md`.
