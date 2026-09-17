# Simulator suspension bookkeeping — September 16, 2026

MegaPad `9b4041f` moves complete suspension snapshots into the native memory
resolver and reuses immutable ordinary continuation values by call site.
Three alternating current/previous physical typing pairs support retaining
the change. Median state settlement falls from 39.86 to 19.52 ms. Median
isolated feedback is 0.856 s before and 0.736 s after; the median of the three
burst medians is 1.298 s before and 1.067 s after. These observations remain
far from fluid typing, and host variation prevents assigning the entire
observed latency difference to the code change.

## Change and correctness boundary

The existing 8,192-step owner boundaries repeatedly materialized complete
data and return snapshots in Python. Native execution also constructed new
frozen continuation objects for call sites seen in earlier intervals.
The change reads the same complete stack cells through a fresh native memory
resolver, retains matching continuation objects, and removes stale active
metadata only after the complete snapshot passes preflight. Inactive metadata
survives for subsequent `RP!`. Custom stacks and memory retain the reference
path; data mutation is still rejected before return metadata is inspected.

Ordinary continuation values are interned by `(caller_xt, return_ip)` and
discarded with native plans on dictionary-generation invalidation. Every
call still writes a fresh raw cookie. Root and fault continuations retain
their distinct control state. No stack entries, comparisons, guest steps,
owner boundaries, clock effects, input revision checks, or post-flip ACKs
are omitted. This adds no guest ABI version, capacity limit, source cache,
or application-specific executor path. Akashic production code is unchanged.

A separate cProfile discovery run found 4,370 return snapshots and 17,247
continuation normalizations in its first-character interval. Its Python-loop
timings are inflated, and cumulative accounting for outer/native frames is
inconsistent. That run is excluded from all performance comparisons below;
only its call counts motivated the candidate.

## Paired physical results

All six runs use clean Akashic `b68b801`, the ordinary source-mode Desktop,
DejaVuSansMono at the same 3080×1764 viewport, one isolated character and
eighteen individually scheduled inputs at 5 Hz. The small CPU observer and
harness are identical to the previous paired investigation. Profiling runs
only during the isolated interval and is then disabled. These are paired
diagnostics, not unprofiled benchmarks.

The order is current/previous, repeated three times in the existing checkout.
Each previous-source run binds MegaPad `9bf21e6` and its matching original
extension; each current run binds `9b4041f` and its matching rebuilt extension.
The checkout and binary return to current main after every comparison.
No worktree is created. Extension SHA256 values are:

- Previous: `b6f7c92fcf51b34a7e8cf8ed2cd0536e9bc0741c494b2b936fb71ae3803616e7`
- Current: `c346fa9fd03d56b98b1fc97ecb2b4c5ba28a2d3663ffd2fb08d3d15555250172`

Times start at actual dispatch and end at the first physically acknowledged
complete frame containing the character. Scheduling delays are additional.

| Pair | Simulator | Isolated | Burst median | Final drain |
| --- | --- | ---: | ---: | ---: |
| 1 | Current | 0.812 s | 1.067 s | 1.108 s |
| 1 | Previous | 0.856 s | 1.298 s | 1.504 s |
| 2 | Current | 0.736 s | 1.104 s | 1.128 s |
| 2 | Previous | 0.737 s | 1.164 s | 1.267 s |
| 3 | Current | 0.729 s | 1.056 s | 1.072 s |
| 3 | Previous | 1.072 s | 1.643 s | 1.850 s |

| Median isolated diagnostic interval | Previous | Current |
| --- | ---: | ---: |
| Owner-thread CPU | 669.21 ms | 576.45 ms |
| Native execution elapsed time, included in owner wall time | 282.77 ms | 263.05 ms |
| Native settlement elapsed time, included in owner wall time | 39.86 ms | 19.52 ms |

The first pair has nearly equal native execution time (282.77 ms previous,
284.11 ms current), while owner CPU falls 669.21 → 623.06 ms. The second pair
has only a 3 ms owner CPU difference: the previous run also executes native
work faster, 248.70 versus 262.91 ms. The last previous run slows to 351.60 ms
native execution and 96.64 ms composition, against 263.05 and 74.45 ms in its
current counterpart. Those changes exceed what this bookkeeping modification
alone establishes. Three pairs on a shared host do not give a confidence
interval or an exact causal end-to-end speedup percentage.

Settlement is consistently lower: 18.37–21.97 ms current versus 34.42–52.03 ms
previous. Native coverage remains 99.978–99.979%. Whole sampled intervals
contain 18.24–18.65 million steps; signal delivery varies the idle boundaries.
The substantive guest work is unchanged: approximately 3.74 million steps
in UIDL aggregation, 2.92 million in hybrid preflight, and 5.73 million in
delta comparison/normalization. Native elapsed timers and owner CPU timers
are different timing domains and must not be subtracted as exact CPU costs.

Every run displays all 19 characters in order. Initial, isolated-character,
and final screenshots are pixel-identical across all six runs. Scheduled
due-to-ACK burst medians are 1.310 s previous and 1.097 s current. Input
backpressure, exact frame grouping, each character's latency, and source and
binary bindings are retained in the JSON evidence.

## Qualification and remaining work

The existing focused selector passes 276 checks in 2.97 s. The expanded
snapshot/native memory, clock, bulk, loop, stack and session selector passes
501 checks in 5.37 s. A further native-selected quantum, KDOS exception and
shared-session selector passes 35 checks in 2.71 s. These selectors overlap;
the counts are not a count of unique tests. New coverage includes sub-cell
pages, sparse zero cells, raw same-depth mutations, root/fault metadata,
inactive retained frames, data-failure precedence, fresh cookies, and
dictionary invalidation. The expanded fixture initially supplied an invalid
non-root dispatch ID; correcting the fixture resolved all eight failures.

`physical-menus-b_3el8iw` passes the complete ordinary Desktop journey:
18 milestones, 21 interactions, 27 physical ACKs and both CELL fallback gates.
It uses X11 `pygame.display.flip`, with zero manual input RPCs. The run takes
137.862 s and peaks at 444.078 MiB. Milestone and input sequences match the
previous accepted journey. This is functional acceptance, not a controlled
full-journey timing comparison.

The final unprofiled run, `fixed-biqfel0h`, displays all 19 characters with
0.697 s isolated feedback, a 1.035 s burst median, and 1.085 s final drain.
Its first response includes 552.855 ms to observe the offer, 56.741 ms of
harness reconstruction, 76.401 ms composition and 11.417 ms flip/ACK.
Maximum scheduling delay is 252.436 ms, additional to actual-dispatch latency.
It takes 70.714 s and peaks at 381.539 MiB. Its three milestone screenshots
also match the diagnostic pixels exactly. This current-only measurement is
not an additional paired speedup comparison.

All checks run sequentially under unchanged step budgets and the existing
900 s / 3.5 GiB physical guards. The six diagnostic runs take 64.82–78.35 s
and peak below 381 MiB, with exit 0 and no guard stop. Resource glances show
roughly 10–12 GiB available RAM during the physical series.

The change removes measurable host work, but accelerating native dispatch
alone cannot account for all remaining latency. Large traversals still
rebuild, validate, normalize and compare mostly unchanged scene data, and
their guest steps also generate host-boundary work. Carrying existing
unchanged-row evidence farther through glyph normalization and preflight is
a larger candidate to investigate, while preserving complete mutation and
publication checks. That architectural change is not implemented or claimed
as a saving in this report.

Raw artifacts are under `local_testing/out/typing-owner-20260916/`:
`fixed-t7sfb9n8`, `baseline-9epd68jd`, `fixed-_6gv6yld`, `baseline-pclybjn8`,
`fixed-leodqc_a`, and `baseline-wgwnvo7w`, in run order. Each preserves its
exact observer/harness, checked against recorded hashes. `analysis/` retains
the aggregators. The separate discovery run is `baseline-3kdxntka`.
Tracked `local_testing/evidence/typing-owner-20260916.json` contains the
paired observations, pixel comparisons, and final qualification. Commands
are recorded in `local_testing/evidence/typing-20260916.md`.
