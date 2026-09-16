# Typing latency — September 16, 2026

The working target is individual characters at 5–10 characters/second with
feedback around 100 ms. A bulk text RPC is not evidence for that target.

The latest Akashic changes at `a23e058` reduce the control join by 71% on
identical captured input and make storage proofs handle fragmented allocation.
Sampled first-character work falls from 20.153 million to 18.408 million steps.
The current physical run records 0.733 s isolated feedback and a 1.222 s burst
median, slower than the preceding repeat; this pass establishes no visible
latency gain. All 19 characters and the full Desktop journey pass. See the
[delta-sort and storage report](DELTA-SORT-PERFORMANCE-20260916.md) for the
controlled work comparison, physical results, and remaining costs.

The preceding Akashic changes at `87abdaa` cut sampled first-character work from
32.8 million to 19.7 million steps. Unchanged semantic coverage now preserves
clean residual rows, and one storage proof covers clustered adapter buffers.
The final unprofiled repeat measures 0.636 s isolated feedback and a 1.124 s
burst median, with all 19 characters intact. A slower initial run and a fresh
previous-code comparison are retained because host timing varied materially.
The full Desktop journey passes. See the
[residual and storage report](RESIDUAL-STORAGE-PERFORMANCE-20260916.md) for
all trials, remaining costs, and qualification. The target remains unmet.

The preceding compositor and guest-lookup changes at MegaPad `e98c91e` /
Akashic `1c7dd9a` preserved all 19 characters and lowered isolated feedback
from 1.121 s to 0.948 s. Burst median delay remains about 1.58 s. Physical
composition now takes 50–62 ms, and the full Desktop journey passes.
See [the rendering and guest-work measurements](RENDERING-PERFORMANCE-20260916.md)
for the updated 33.2-million-step profile, remaining costs, and qualification.
The earlier interpreter-only series follows below.

The initial physical baseline was about 2.6 seconds per Pad character. Fresh
ordinary Desktop diagnostics at Akashic `9e42004` and MegaPad `eaa4d3b` sampled
the unchanged 8,192-step semantic owner boundaries. No compiler cache, source
substitution, step-budget change, or scheduler change was used. These runs
composed offscreen and are attribution evidence, not physical acceptance or
unprofiled latency benchmarks.

Artifacts: `local_testing/out/typing-20260916/baseline-skb838w4` (86 s,
298 MiB aggregate peak RSS) and `baseline-d5cta9ku` (call-stack follow-up).
The diagnostic distinguishes intervals whose packed guest phase sequence
changed; those intervals are not assigned to either neighboring phase.
Suspended call stacks are statistical samples, not exact function counters.

| Pad character work | Sampled semantic steps |
| --- | ---: |
| Complete input-to-offer interval | 49.6 million |
| UIDL aggregate phase | 8.7 million |
| Residual glyph planning | 8.2 million |
| Delta comparison/normalization | 7.4 million |
| Engine STEP, inclusive | 12.2 million |

The engine service cost is separate from the named phases above: most of it
falls in the generic OTHER phase. STEP repeatedly scans the complete control
and owner ledgers even when idle with no queue or completion to process.

## Idle service slice

`_RTAPT-IDLE-SERVICE?` proves the engine's existing storage geometry, exact
idle state, empty lifecycle queue, absent active operation, zero transaction
tails, and zero CELL geometry. Only that status-only branch avoids the deep
ledger audit. It does not certify ledger contents or cache a validation result.
Nonidle or incoherent descriptors enter the existing full validator.

RICH-BEGIN, queued lifecycle work, completion reconciliation, explicit
RTAPT-VALID?, and final publication continue using the existing full audits.
Caller changes between polls therefore remain subject to validation before
those banks acquire authority. Readiness results and sticky status behavior
are unchanged.

Focused Python/native execution and structural checks: 62 passed in 1.95 s.
The execution fixture observes storage/audit/PT boundaries explicitly; it tests
the production gate and STEP dispatch, not a whole PT session. The physical comparisons below qualify both guest slices together; they do
not isolate either slice's wall-time savings.

## Projection coverage slice

Each acknowledged target now retains the four coordinates of every non-menu
semantic claim. Exact ordered equality permits reuse of unchanged residual
rows even when document generations or editor content revisions advance.
CELL and residue damage remain independent inputs and are never cleared.
Menu rows retain their separate BACK/residue invalidation rule. Changed,
added, removed, or reordered coverage conservatively dirties both old and new
covered rows; invalid old geometry refuses the incremental route.

The 224-byte private bank header records the rectangle count. Each bank
reserves 32 bytes per possible control/instrument from the existing caller
bounds and copies only the admitted non-menu rectangles. No hash, pointer to
live widget storage, applet-specific exception, or new capacity limit is used.
Clones preserve the exact packed extent and source reuse cannot alter an ACK
bank. Both Python/native execution cases cover growth, shrink, movement,
removal, menu-role changes, malformed bounds, and clone ownership.

Focused coverage, packed-bank, instrument, control-map, and glyph selectors:
352 passed in 17.49 s. Physical cadence and the full Desk journey pass below.

## Physical typing and simulator execution

This earlier matched comparison keeps Akashic's production Forth from `de6a6aa` and
the ordinary source-mode `desktop-apt1` composition fixed. Input uses the normal viewer keyboard
forwarder and exact physical ACK proofs. One isolated character is followed
by 18 individually scheduled characters at 5 characters/second (about 60
words/minute using five characters/word). It is a short cadence experiment,
not a sustained typing qualification or a bulk-text RPC.

| MegaPad revision | Single character | Burst median visibility delay | Last character drain |
| --- | ---: | ---: | ---: |
| `ec1794d` — corrected input, original executor | 2.435 s | 5.158 s | 5.243 s |
| `4bc24f4` — native dispatch/memory reuse | 1.690 s | 3.031 s | 3.552 s |
| `efed68a` — host handoff/snapshot work | 1.413 s | 2.500 s | 2.397 s |
| `15613d8` — superinstructions and prepared dynamic calls | 1.262 s | 2.531 s | 2.274 s |
| `fe31e71` — bulk primitives and stack-pointer reads | 1.121 s | 1.591 s | 1.347 s |

All five displayed the complete `~fluid typing 12345` through Pad's ordinary
retained TEXT_AREA, with 19 accepted single-character inputs and physical X11
flips before ACKs. Single-character delay fell 54%; the burst median fell 69%.
These are one-run comparisons, not percentile estimates from repeated trials.
The last run took 60.137 s including fresh source preparation and used
393.414 MiB aggregate peak RSS. The existing 900 s watchdog and 3.5 GiB guard
were unchanged; available system memory stayed above 8 GiB.

Input deadlines are generated in the viewer event loop. Composition can delay
actual dispatch: the five runs' worst scheduling delays were 239, 222, 214,
288 and 233 ms. Both desired and actual timestamps are recorded. The table measures
actual dispatch to visible physical ACK, so scheduling delay is additional.
This is still far from fluid typing; no 100 ms acceptance is claimed.

The earlier `eaa4d3b` run lost the `g` during a publication boundary. MegaPad
`ec1794d` makes temporary model/result waits retryable and keeps bounded
keyboard intentions until the next physical ACK. It discards frame-specific
clicks and invalidates the keyboard queue on authority/context changes.
Focused viewer/driver/core checks: 106 passed. No old wire proof is replayed.

Native execution was a material cost, rather than an explanation based only
on the guest step count. Four bounded dispatch kernels improved 2.01–3.05x
with identical semantic steps/results. The native change preserves sparse
shared memory, continuation cookies, exact fallback effects, and the existing
8,192-step allowance. Subsequent host changes keep every semantic boundary,
input-admission opportunity, and virtual-clock update while avoiding an OS
yield per batch and per-slot Python calls during snapshot decoding.
Python/native parity passed 96 checks; the expanded stack/session/clock
selector passed 154. The latter includes the native checks and must not be
counted as an additional 154 independent cases.

The remaining work is substantial. Guest snapshots, validation and delta
planning still traverse a large live scene; native execution and host
bookkeeping still cost time. Composition took 133–172 ms in this series;
the subsequent compositor change reduces it to 50–62 ms. The new association
lookup reduces sampled guest work from 35.5 to 33.2 million steps, while
residual planning and delta comparison still consume about 15.6 million.
The linked rendering report separates those costs. Normal keystrokes still
do not appear as they are typed.

Exact commands, bindings, artifacts, and limits are recorded in
`local_testing/evidence/typing-20260916.md`. The reproducible typing runner is
`local_testing/physical_typing_cadence.py`; its default workload and input/ACK
path match the measured diagnostic, with unused menu-test scaffolding removed.

## Full Desktop regression result

The latest qualification at MegaPad `9bf21e6` / Akashic `a23e058` passes
18 milestones, 21 interactions, 27 post-flip ACKs, and both complete CELL
fallback gates. It takes 141.296 s and peaks at 442.363 MiB. Milestone and
input sequences equal the previous journey; this is functional acceptance.

The preceding qualification at MegaPad `9bf21e6` / Akashic `87abdaa` passes
18 milestones, 21 interactions, 26 post-flip ACKs, and both complete CELL
fallback gates. It takes 123.010 s and peaks at 441.895 MiB, with the same
milestone and input sequences as the previous journey. This is functional
acceptance; full-journey elapsed times are not a controlled speed comparison.

The preceding qualification at MegaPad `e98c91e` / Akashic `1c7dd9a` passes
18 milestones, 21 interactions, 27 post-flip ACKs, and both complete CELL
fallback gates. It took 139.113 s and peaked at 442.949 MiB. Its milestone
and input sequences equal the prior journey. See the rendering report for
the exact bindings and the separate typing comparison.

The prior qualification at MegaPad `fe31e71` / Akashic `5bd5ac5` passed the
same 18 milestones and 21 interactions with 26 post-flip ACKs and both CELL
fallback gates. It took 127.555 s and peaked at 439.965 MiB. The full results
are in the linked bulk and pointer report; the earlier qualification follows.

The existing ordinary physical menu/Desktop acceptance passed with Akashic
`a730baa` (production Forth unchanged from `de6a6aa`) and MegaPad `efed68a`.
It completed 18 milestones and 21 scripted interactions under 27 exact
post-flip ACKs, including real Pad editing, Daybook task/date/source actions,
menu opening/closing, app launching, and initial/final complete CELL fallback.
There were no manual input RPCs. Total time was 154.121 s and aggregate peak
RSS 437.512 MiB, within the unchanged 900 s / 3.5 GiB limits.

Artifact: `local_testing/out/typing-20260916/physical-menus-5jxqkwdc/`.
The manifest identifies `pygame.display.flip` as the physical sink boundary
and `x11` as the video driver. This validates the ordinary journey after the
changes; it does not turn the typing latency result into a fluidity pass.
