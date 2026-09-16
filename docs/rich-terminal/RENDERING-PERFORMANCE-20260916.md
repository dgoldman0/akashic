# Guest planning and physical composition — September 16, 2026

The subsequent [residual and storage pass](RESIDUAL-STORAGE-PERFORMANCE-20260916.md)
reduces sampled guest work to 19.7 million steps and records the latest
physical trials. This report preserves the preceding comparison.

MegaPad `e98c91e` and Akashic `1c7dd9a` reduce isolated physical typing
feedback from 1.121 s to 0.948 s. The burst median remains about 1.58 s.
All 19 characters and the full ordinary Desktop journey pass, but the
roughly 100 ms feedback target remains unmet. The native interpreter binary
is unchanged from `fe31e71`; this pass changes composition and guest work.

## Changes

MegaPad's rich compositor rasterizes each visible character/color/opacity/
italic combination once per composition. It inspects the actual raster for
empty ink before doing slot clipping and blitting. Backgrounds, decorations,
bold overhang, equal character slots, clipping, and hit maps remain intact.
A custom font can paint a space. Raster storage expires with the frame and
adds no persistent font cache or fixed capacity.

The sampled first response contains 784 residual glyph runs and 20,588
characters, including 18,678 spaces. Seven saved real typing offers were
replayed with the previous and current compositor, alternating four trials
per implementation. Every composition produced identical RGBA pixel hashes
and structural hit maps. Medians excluding each first trial improved
2.79–2.99x, from 113–129 ms to 38–45 ms. These are offscreen replay results,
separate from the physical measurements below.

Akashic's `_UTUI-MC-ASSOCIATE` previously scanned every UIDL element at each
ancestor of a semantic widget. It now validates the complete region chain
and scans the document once, checking ancestry for caller-mounted roots.
Cycle/geometry checks, unique ownership, document membership, source
generations, and scratch cleanup remain. No authority is cached across calls.
No applet, public ABI, version counter, capacity, or scheduler change is added.

The isolated production helper uses 13,315 → 3,837 semantic steps for a
32-element document with five ancestors and one mounted root. A deeper
256-element case uses 686,195 → 28,205 steps. A single-ancestor case adds
18 steps (2,761 → 2,779). Both executors produce the same counts and results.
These synthetic reductions do not describe the whole Desktop workload.

## Physical typing

Both runs use the same source-mode `desktop-apt1`, font, 3080×1764 viewport,
normal keyboard forwarder, and exact complete-frame ACK after X11 flip.
One isolated character precedes 18 individual characters scheduled at 5 Hz.
Native profiling is disabled. Latency starts at actual dispatch; scheduling
delay is recorded separately. Each row is one shared-host run, not a latency
distribution or sustained-cadence qualification.

| Sources | Isolated feedback | Burst median | Last-character drain |
| --- | ---: | ---: | ---: |
| MegaPad `fe31e71`, Akashic `5bd5ac5` | 1.121 s | 1.591 s | 1.347 s |
| MegaPad `e98c91e`, Akashic `1c7dd9a` | 0.948 s | 1.578 s | 1.292 s |

Isolated feedback improves 15.5%. The 0.8% burst-median difference is too
small to establish a useful improvement from these individual runs.
All 19 characters appear as `~fluid typing 12345` through Pad's ordinary
retained TEXT_AREA. Maximum scheduling delay falls from 232.901 to
138.644 ms. Physical composition falls from 132.757–171.505 ms to
50.306–61.955 ms across seven complete frames.

The new isolated response comprises 823.633 ms from dispatch to offer
observation, 54.554 ms of harness evidence writing/reconstruction/checking,
54.805 ms of physical composition, and 15.132 ms of flip/ACK. The harness
segment is not product-side projection work. Offer observation includes
guest execution, host services, transport, and viewer polling; it is not an
exclusive Akashic or simulator timer.

Artifact `local_testing/out/typing-20260916/fixed-t8g31h2a/` completes in
59.899 s including fresh source preparation and peaks at 379.199 MiB
aggregate RSS, with exit 0 and no guard stop.

## Remaining work, measured separately

Diagnostics `baseline-4ltwfanq` and `fixed-nvpu593p` bracket the first real
`send_text` through observation of its complete offer. The observer samples
unchanged 8,192-step owner boundaries and existing suspension snapshots.
Phase transitions are separate, and sampling resolution is one boundary
plus signal delivery. These observer-enabled times are not latency benchmarks.

| Guest work | Before, million sampled steps | After, million sampled steps |
| --- | ---: | ---: |
| Entire sampled interval | 35.465 | 33.245 |
| UIDL aggregate | 8.717 | 7.299 |
| Residual glyph planning | 8.184 | 8.184 |
| Delta comparison/normalization | 7.414 | 7.406 |
| Other | 5.997 | 5.210 |
| Hybrid preflight | 2.916 | 2.916 |

Overall work falls about 6.3%. Inclusive association samples fall from
3.973 million steps to 1.745 million, about 56%. The enclosing storage
disjointness checks still account for 6.415 million sampled steps; this is
an overlapping call-stack attribution, not another phase to add to the table.
Source inspection shows that the adapter checks many storage spans through
separate queries, each revalidating mounted relations and scanning the
document. Residual planning and delta comparison together remain about
15.6 million steps, nearly 47% of the sampled interval.

The final diagnostic records 33,239,227 native steps out of 33,244,707
semantic steps, about 99.98%. Most guest steps already execute natively;
this count alone does not measure the cost of the remaining host operations.
The sampled native
C++ run time is 365.650 ms, with 50.193 ms of native state settlement.
Inclusive method timers report 467.307 ms inside native dispatch, 532.211 ms
inside guest dispatch, 127.819 ms across data/return snapshot methods, and
101.723 ms in host terminal service. These nested timers overlap and must
not be summed. Owner boundaries total 869.866 ms of wall time and 856.424 ms
of thread CPU, with 57.061 ms of additional sampling outside those boundaries.

Both Akashic work volume and simulator dispatch/boundary bookkeeping remain
material. Reducing guest work also reduces the number of host boundaries.
The next useful candidates are residual/delta traversal and repeated
authority validation, while preserving mutation-safety checks, followed by
measured call/return and suspension bookkeeping changes. The physical
compositor is now a smaller part of the latency. Low-level guest terminal
service did not dominate the sampled call stacks.

The initial observer had a reporting defect: shutdown re-read cumulative
native counters after sampling stopped. Its top-level `native_delta`,
`native_profile_delta`, and `native_exits` include later idle work and are
discarded. Interval/group counters and method timers stop correctly; before/
after comparisons use those groups. The final observer freezes cumulative
counters at the stop boundary, where they agree with the group sums. Raw
profile hashes and this limitation are recorded in the checked-in evidence.

## Validation and reproduction

MegaPad passes 114 focused compositor/viewer checks. Akashic passes 38
bounded association execution cases on Python/native and 61 accompanying
structural checks. One additional existing documentation assertion fails:
`test_retained_contract_requires_internal_uidl_projection_now` expects the
old “Desk, Pad, and Daybook acceptance checkpoint” heading, while the
unchanged contract heading now includes overlay and Sound Lab acceptance.
That unrelated assertion is deferred; it is not a runtime failure.

The full ordinary physical Desktop journey at the new clean heads passes
18 milestones, 21 interactions, 27 post-flip ACKs, and both complete CELL
fallback gates. Milestone and input sequences equal `physical-menus-vjtw2luk`;
intermediate offer counts can vary. Pad, Daybook, app launching, menus, and
restoration all pass. There are zero manual input RPCs. Artifact
`local_testing/out/typing-20260916/physical-menus-bjjn1z7v/` records
139.113 s, 442.949 MiB peak aggregate RSS, exit 0, and no stop reason.
This is functional acceptance, not a matched full-journey speed comparison.

All tests ran sequentially. Physical runs retain the existing 900 s and
3.5 GiB guards. Resource glances remained above 8 GiB available system RAM.
The native extension SHA256 remains
`b6f7c92fcf51b34a7e8cf8ed2cd0536e9bc0741c494b2b936fb71ae3803616e7`.
No source cache or enlarged step allowance was used.

`local_testing/evidence/rendering-typing-20260916.json` preserves bindings,
physical timing events, Desktop evidence, replay trials/pixel digests,
synthetic helper counts, and diagnostic aggregates. Full diagnostic groups
and compositor profiles remain in their artifact directories. The final
diagnostic directory also retains `profile_typing_layers.py`,
`typing_layer_observer.py`, and analysis scripts; `compositor-replay/`
retains the replay driver and previous compositor source. Exact commands
are in `local_testing/evidence/typing-20260916.md`.
