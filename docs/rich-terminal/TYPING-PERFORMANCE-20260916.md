# Typing latency — September 16, 2026

The working target is individual characters at 5–10 characters/second with
feedback around 100 ms. A bulk text RPC is not evidence for that target.

The current physical baseline is about 2.6 seconds per Pad character. Fresh
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
the production gate and STEP dispatch, not a whole PT session. Physical typing
and realistic cadence remain to be measured after the performance slices.

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
352 passed in 17.49 s. Physical typing cadence is the next qualification.

## Physical typing and simulator execution

The matched comparison keeps Akashic `de6a6aa` and the ordinary source-mode
`desktop-apt1` composition fixed. Input uses the normal viewer keyboard
forwarder and exact physical ACK proofs. One isolated character is followed
by 18 individually scheduled characters at 5 characters/second (about 60
words/minute using five characters/word). It is a short cadence experiment,
not a sustained typing qualification or a bulk-text RPC.

| MegaPad revision | Single character | Burst median visibility delay | Last character drain |
| --- | ---: | ---: | ---: |
| `ec1794d` — corrected input, original executor | 2.435 s | 5.158 s | 5.243 s |
| `4bc24f4` — native dispatch/memory reuse | 1.690 s | 3.031 s | 3.552 s |
| `efed68a` — host handoff/snapshot work | 1.413 s | 2.500 s | 2.397 s |

All three displayed the complete `~fluid typing 12345` through Pad's ordinary
retained TEXT_AREA, with 19 accepted single-character inputs and physical X11
flips before ACKs. Single-character delay fell 42%; the burst median fell 52%.
These are one-run comparisons, not percentile estimates from repeated trials.
The last run took 62.861 s including fresh source preparation and used
394.633 MiB aggregate peak RSS. The existing 900 s watchdog and 3.5 GiB guard
were unchanged; available system memory stayed around 9–10 GiB.

Input deadlines are generated in the viewer event loop. Composition can delay
actual dispatch: the three runs' worst scheduling delays were 239, 222, and
214 ms. Both desired and actual timestamps are recorded. The table measures
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
bookkeeping still cost time; physical composition alone takes roughly
130–150 ms at 3080×1764. Further work must measure all three. Faster guest-step
execution helps, but this measured change does not by itself make normal
keystrokes appear as they are typed.

Exact commands, bindings, artifacts, and limits are recorded in
`local_testing/evidence/typing-20260916.md`. The reproducible typing runner is
`local_testing/physical_typing_cadence.py`; its default workload and input/ACK
path match the measured diagnostic, with unused menu-test scaffolding removed.
