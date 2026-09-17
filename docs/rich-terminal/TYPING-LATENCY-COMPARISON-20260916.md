# Paired typing latency investigation — September 16, 2026

Three alternating previous/current pairs do not reproduce a consistent
latency regression from the control-sort and grouped-storage changes.
Current code is slower in the first isolated-character pair and faster in
the next two. Median isolated feedback is 0.782 s before and 0.761 s after;
the median of the three burst medians is 1.174 s before and 1.136 s after.
The small overall benefit remains far from fluid typing.

An independent comparison on identical captured control banks measures
25.700 → 8.445 ms inside the native executor and 30.475 → 10.493 ms of
host execution CPU time. The replacement is about three times faster for
this operation; the simulator accommodates it. These measurements support
retaining the optimization, without turning the earlier single-run
97 ms regression into a claim about a persistent slowdown.

## Method and source bindings

The six runs alternate clean Akashic `174bb56` and `291129f` in the existing
checkout. `291129f` has the same production sources as `a23e058`; subsequent
commits added tests and evidence. The checkout returns to `main` between
previous-source runs and finishes on `main`. No worktree was created.

Every run binds clean MegaPad `9bf21e6` and native extension SHA256
`b6f7c92fcf51b34a7e8cf8ed2cd0536e9bc0741c494b2b936fb71ae3803616e7`.
The source-mode Desktop, DejaVuSansMono font, 3080×1764 physical X11 sink,
5 Hz individual input schedule, revision authority, and exact post-flip
acknowledgement remain the same. All 19 characters appear in every run.

A diagnostic copy of the ordinary typing harness adds client process/thread
CPU timestamps to existing trace events. A small server observer records
wall time, owner-thread CPU, semantic steps, phase totals, native time,
settlement, and native exits for the isolated character. Signals request
start before the first `send_text` and stop at the first subsequent complete
offer observation. Both requests take effect at existing owner boundaries.
Native profiling is enabled for that interval and then restored to disabled.
Counters freeze at stop; shutdown never substitutes later idle counters.

The observer does not take guest stack snapshots, read control banks, profile
composition, change guest memory, or change execution boundaries. Nevertheless,
these are **paired diagnostics**, not new unprofiled benchmarks. Signal
delivery adds varying idle boundaries. Phase work is a stronger comparison
than exact whole-interval step totals. The burst has native profiling disabled.

## Physical results

Times start at actual character dispatch and end at the first physically
acknowledged complete frame containing it. Intended scheduling delay is
recorded separately and is additional to this table.

| Pair | Sources | Isolated | Burst median | Final drain |
| --- | --- | ---: | ---: | ---: |
| 1 | Previous | 0.760 s | 1.174 s | 1.190 s |
| 1 | Current | 0.787 s | 1.177 s | 1.155 s |
| 2 | Previous | 0.800 s | 1.075 s | 1.061 s |
| 2 | Current | 0.744 s | 1.123 s | 1.164 s |
| 3 | Previous | 0.782 s | 1.200 s | 1.228 s |
| 3 | Current | 0.761 s | 1.136 s | 1.165 s |

The median of scheduled-due-to-ACK burst medians is 1.192 s before and
1.173 s after. Neither timing definition establishes fluidity. Three pairs
on a shared host are insufficient for a confidence interval or a precise
causal end-to-end speedup percentage.

The CPU measurements explain why the isolated results change direction:

| Median isolated diagnostic interval | Previous | Current |
| --- | ---: | ---: |
| Owner interval wall time | 648.979 ms | 627.537 ms |
| Owner-thread CPU time | 619.350 ms | 599.509 ms |
| Native execution, inclusive subset | 260.267 ms | 250.982 ms |
| Native settlement, separate subset | 37.103 ms | 35.431 ms |

Native coverage remains 99.978–99.980% of guest steps in all six runs. There
is no surge in reference-dispatch execution. Delta work falls from roughly
7.41 million to 5.73 million steps in every pair. Delta-phase boundary CPU
falls from 174–180 ms before to 129–154 ms after.

In the first current run, unchanged residual work takes 51.85 ms of boundary
CPU instead of 30.94 ms, and hybrid preflight takes 98.89 instead of 68.17 ms.
Together those increases exceed the delta saving. On the second current run,
the same source head and essentially identical phase work take 32.28 and
66.38 ms respectively. The third takes 33.95 and 65.77 ms. The initially
slower phases do not remain slower across repetitions.

This variation occurs in CPU time as well as wall time. Merely being
descheduled is therefore an incomplete explanation. CPU throughput, cache
state, placement and shared-host contention are possible contributors;
frequency and hardware-cache counters were not measured, so their individual
contributions remain unresolved. Whole-run system CPU busy fractions range
from 35.3% to 49.1%; those averages do not identify first-character contention.
There is no evidence here for a persistent source-dependent memory fast-path
regression, and no instruction to dismiss every future regression as noise.

## Identical-input native comparison

Six sequential repetitions per source execute the real production control
join on the previously captured 150-control banks. Order alternates on each
repetition. Every call keeps the existing 3,000,000-step bound and returns
the same complete map. The host execute timer excludes fixture allocation
and assertions. The table gives medians of the five repetitions after the
first; every raw trial, including the first, is retained.

| Control join | Previous | Current |
| --- | ---: | ---: |
| Semantic steps | 2,359,909 | 679,384 |
| Native execution | 25.700 ms | 8.445 ms |
| Host execute CPU | 30.475 ms | 10.493 ms |
| Host execute wall | 31.796 ms | 10.493 ms |
| Settlement, included in host execute | 2.858 ms | 0.697 ms |

Steps have different execution costs, so the 71.2% step reduction need not
be an identical percentage of host time. The measured operation is still
substantially faster. Its CPU saving is about 20 ms against an isolated
path taking about 760 ms, which explains the limited end-to-end effect.
These are separate measurements; helper and full-path times must not be
added as if they were one trace.

## Burst behavior and visible equivalence

The burst remains sensitive to input admission and frame timing. Some
characters receive backpressure and wait for a new physically acknowledged
offer. The largest observed dispatch-to-acceptance wait is 242 ms. All input
is eventually accepted in order. Complete frames usually add two or three
characters, so a character missing one frame can wait another roughly
0.6-second update. This amplifies modest execution and presentation changes.
It does not justify weakening revision-bound input or acknowledging early.

The first current run has visible counts `1,2,4,7,10,13,16,19`; the next two
have `1,2,4,6,9,12,15,18,19`. That change in grouping complicates comparisons
of a single burst median. Both actual-dispatch and intended-due latencies,
acceptance delays, and exact frame counts are retained in the evidence.

Initial, isolated-character and final pixels are identical across all three
repetitions of each source head. Between heads there are exactly 284 differing
pixels at each milestone, confined to two File Explorer size fields:
`source-17.src` and `source-18.src` change from `119K` to `120K` because the
production source grew. The text projection confirms precisely those two
changes. Pad and Daybook pixels are identical; no pixels were masked.

## Artifacts and continuation

All six physical runs exit 0 with no guard stop. Durations are 62.85–72.81 s
and peak aggregate RSS stays below 381 MiB. Tests are sequential; resource
glances show at least 10 GiB available RAM. The unchanged 900 s / 3.5 GiB
guards, semantic allowances, source loading, ABI, and scheduler remain in
force. No production changes were made in this investigation, so the existing
full Desktop qualification was not rerun.

Artifacts under `local_testing/out/typing-ab-20260916/`, in run order:

1. `baseline-mm8z_g5k`
2. `fixed-osn_t2y_`
3. `baseline-2ymq0_v4`
4. `fixed-loxhizwq`
5. `baseline-3rz06632`
6. `fixed-wrufilrw`

Each directory retains its exact harness and observer, verified against the
recorded hashes. `analysis/` preserves the helper driver, raw helper timings,
aggregators and diagnostic scripts. The tracked
`local_testing/evidence/paired-typing-cpu-20260916.json` retains source/binary
bindings, timing distributions, CPU phases, native exits, input-admission
measurements, pixel hashes and explicit limitations. Reproduction commands
are in `local_testing/evidence/typing-20260916.md`.

The optimization is retained. Further gains must address the large remaining
cost: roughly 600 ms of owner-thread CPU in this diagnostic, of which native
execution accounts for only about 250 ms, plus physical-viewer work. Glyph
traversals and simulator suspension/host-service overhead remain substantial
targets. Future performance claims should pair complete physical timings
with CPU measurements and repeat both source versions.
