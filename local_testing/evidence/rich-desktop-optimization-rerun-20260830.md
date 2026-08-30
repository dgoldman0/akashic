# Rich Desktop optimization rerun evidence — 2026-08-30

Status: non-normative measurement ledger for the local reference-sink rerun.
It records what the optimization comparison measured and supplies arithmetic
hardware scenarios; it does not extend APT-1 conformance or qualify a physical
UART or panel.

## Revisions and configuration

The qualifying rerun used Akashic `eedcfb9` and MegaPad `4f074ae`. The
comparison baseline used Akashic `3404fe9` and MegaPad `8941782`. Both used the
280x84 X11 pygame viewer, a 360-second timeout, 0.75-second scripted action
delay, zero hold, and acknowledgement immediately after
`pygame.display.flip()` returned.

The local raw traces were:

- `local_testing/out/desktop-apt1-physical-acceptance-eedcfb9-4f074ae-rerun1/performance-trace.json`;
- `local_testing/out/desktop-apt1-physical-acceptance-3404fe9-8941782-replay3/performance-trace.json`.

`local_testing/out/` is intentionally ignored. This checked-in ledger is the
durable result; the architecture document carries only the summary.

## Aggregate comparison

| Measurement | Baseline | `eedcfb9` | Change |
| --- | ---: | ---: | ---: |
| First-offer guest instructions | 3.770B | 4.0865B | +8.4% |
| Post-first-offer guest instructions | 948.0M | 715.5M | -24.5% |
| Total guest instructions | 4.718B | 4.802B | +1.8% |
| Post-first-offer decoded frames | 1,386 | 221 | -84.1% |
| Post-first-offer decoded bytes | 190,131 | 24,541 | -87.1% |
| Total decoded frames | 2,818 | 1,653 | -41.3% |
| Total decoded bytes | 934,353 | 768,763 | -17.7% |
| Complete offers | 10 | 9 | -1 |
| Acceptance elapsed time | 181.465 s | 180.895 s | -0.3% |

The optimized journey therefore did more total cold work and reached its first
offer later, but materially reduced already-loaded interaction work and wire
traffic. The single elapsed comparison is effectively flat and includes the
script's fixed delays; it is not evidence that cold boot became faster. The
aggregate cannot assign an independent gain to each of the eleven optimization
commits.

## Current per-offer counters

`Guest instructions` are cumulative retired MP64 instructions reported by the
emulator. `Frames` and `bytes` are cumulative complete decoded wire frames and
their full wire byte lengths at the terminal boundary.

| Visible offer | State reached | Guest instructions | Delta | Frames | Delta | Bytes | Delta |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | Complete Desk, before Pad focus | 4.0865B | — | 1,432 | — | 744,222 | — |
| 2 | Pad focus / File-menu activation source | 4.1555B | 69.0M | 1,432 | 0 | 744,222 | 0 |
| 3 | Pad File menu open | 4.2595B | 104.0M | 1,502 | 70 | 751,146 | 6,924 |
| 4 | Pad File menu closed | 4.3790B | 119.5M | 1,567 | 65 | 757,855 | 6,709 |
| 5 | Pad text edited | 4.4565B | 77.5M | 1,583 | 16 | 759,532 | 1,677 |
| 6 | Daybook focused | 4.5315B | 75.0M | 1,592 | 9 | 760,734 | 1,202 |
| 7 | Daybook new-task prompt open | 4.6070B | 75.5M | 1,600 | 8 | 762,256 | 1,522 |
| 8 | Daybook task text entered | 4.6790B | 72.0M | 1,609 | 9 | 763,162 | 906 |
| 9 | Daybook task committed | 4.8020B | 123.0M | 1,653 | 44 | 768,763 | 5,601 |

The eight post-first intervals range from 69.0M to 123.0M instructions and
average 89.4M. Their 221 frames total 24,541 decoded bytes. The zero-byte Pad
focus transition still receives a real acknowledged revision through its
idempotent fence; it is not a missing offer.

## Reference-viewer timing scopes

The trace uses `time.monotonic_ns`. Across the nine offers:

| Scoped interval | Range | Mean | Boundary |
| --- | ---: | ---: | --- |
| Renderer-neutral projection | 9.210--14.155 ms | 10.641 ms | Projection function only |
| Pygame compositor body | 88.412--100.268 ms | 92.323 ms | Local draw/flip body recorded by the runner |
| Draw, flip, and present acknowledgement | 101.150--159.952 ms | 115.093 ms | Call through post-`flip()` acknowledgement |

These are local host measurements. `pygame.display.flip()` is the selected
reference boundary; it is not proof of scanout, optical completion, e-paper
settling, or touch latency.

## Hardware interpretation

There are three separate timing domains:

1. retired guest instructions measure architectural software work;
2. emulator virtual cycles drive deterministic timers, devices, scheduling,
   strict execution, and replay; and
3. RTL or silicon clocks determine realized hardware CPI and physical time.

For a particular implementation, guest-compute time is projected as:

```text
seconds = retired guest instructions * realized CPI / clock frequency
```

At 2 GHz and 1--2 average CPI, the current post-first action range projects to
about 35--123 ms of guest compute. This is a scenario for a future MegaPad
implementation, not current FPGA evidence, and excludes UART transfer,
terminal decode and composition, panel refresh, and touch/input return. A
1--2-CPI goal is a MegaPad RTL/ASIC concern; Akashic and the architectural
emulator need not model pipeline bubbles to preserve their behavior.

For contrast, the same 69.0--123.0M range at the current 100 MHz target and a
four-clock simple-instruction floor is at least 2.76--4.92 seconds before
longer instructions, misses, memory service, or contention. In that scenario
guest execution remains the post-first bottleneck. On the hypothetical 2 GHz
implementation, the 115,200-baud line or the panel can instead dominate a
larger update. These comparisons identify likely bottleneck transitions; they
are not concurrent end-to-end measurements.

With 8N1 framing, physical line time has the no-gap lower bound:

```text
seconds = 10 * complete wire bytes / baud
```

| Traffic | 115,200 baud | 1,000,000 baud |
| --- | ---: | ---: |
| First offer, 744,222 bytes | 64.60 s | 7.442 s |
| All post-first updates, 24,541 bytes | 2.13 s | 245 ms |
| One post-first update, 0--6,924 bytes | 0--601 ms | 0--69 ms |
| One nonempty post-first update, 906--6,924 bytes | 79--601 ms | 9--69 ms |

These are derived serialization floors, not measurements. The current viewer
receives complete UART batches in process without baud pacing, the physical
MegaPad rich-TX seam remains open, and real traffic also includes replies,
gaps, scheduling, and backpressure. CPU, transport, composition, and panel
work may partly overlap, but normalized input remains gated by acknowledgement
of the exact physically completed revision.

For an e-paper sink that means controller completion plus the required settle
interval, not merely queued pixels. Physical qualification should record
effective link throughput; projection and composition p50/p95/max;
offer-to-physical-ACK latency; coalesced or superseded revisions; refresh mode;
BUSY/READY timing; settle time; and touch-to-authoritative-input latency.

A saved or precompiled Forth dictionary can remove cold source compilation.
It does not reduce the interaction instruction deltas above once equivalent
compiled words are loaded. That is why boot optimization, steady-state
software/code-generation work, hardware CPI, link capacity, and panel policy
remain separate decisions.
