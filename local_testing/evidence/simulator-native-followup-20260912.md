# Profile-guided simulator follow-up — September 12, 2026

The final ordinary source-mode physical Desktop acceptance **passes** at
MegaPad `08b37d5a5a0c09a301385868416529c239f58760` and Akashic
`fb4e5d9a7b098978ec12c809aa91b9941daa612f`, both clean at launch. Outer
elapsed time fell from **511.819576s to 185.862142s** (2.754×). Both runs
completed the same 20 physically acknowledged offers, 14 authorized inputs,
11 visible milestones, and initial/final CELL fallback checks.

The paired `simulator-improvements` branches have since been fast-forwarded
into local main and their worktrees retired. See the
[integration record](simulator-main-integration-20260912.md) for checks and
artifact locations. Feature work and publishing remain outside this work.

## Committed execution changes

- MegaPad `7d9b9d6` keeps counted `DO`, `?DO`, `LOOP`, `+LOOP`, and `UNLOOP`
  operations in native execution, along with identity-bound `I`, `J`, `TRUE`,
  `FALSE`, `CELLS`, and `UM*`. Loop frames retain their fixed return-stack
  positions, modular equality termination, exact ticks, and retained bytes.
  Unadmitted/faulting operations still leave their partial effects to Python.
- `0b4e607` decodes full suspension stack snapshots in bulk from the qualified
  sparse backing. Resume still compares every data and return entry. Cookie
  validation, stale-type removal, inactive retained metadata, custom stack
  behavior, and same-depth raw mutation detection are preserved.
- `d9fda8b` resolves native scalar memory once per page fragment, with one
  contiguous pointer for the common one-page case. Cross-page and sub-cell
  pages retain explicit little-endian byte access. Missing write pages still
  return to Python before effects; cached pointers live for one native run.
- `08b37d5` maintains the highest live dictionary header/code-slot end, allowing
  forward publication to prove non-overlap without rescanning every old word.
  Rewinds and lower-address arenas retain the full overlap check, including
  initial-body spans. Rollback and LATEST reset recompute the live bound.

The Python executor also receives the snapshot and dictionary improvements.
Native remains opt-in. Forth/app sources, host quanta, semantic budgets,
device ownership, and emulator timing are unchanged. No compiled Forth cache
or fixed dictionary capacity was introduced.

## Profile findings and scope

Diagnostic runs used `MEGAFORTH_NATIVE_PROFILE=1` and saved runtime counters
from ordinary acceptance status observations. A local hook sampled every
128th owner-thread `run_boundary` with cProfile. Labels follow the latest
recorded physical milestone, sampled at those boundaries; they are approximate
phase labels, not exact input-to-ACK timing scopes. Periodic sampling and
cProfile overhead make these diagnostic rankings unsuitable for estimating
unprofiled per-function wall-time percentages. Native elapsed counters measure
the complete extension call, including conversion, separately from settlement.

| Live diagnostic interval | Initial | Loops + snapshots | Scalar resolver |
| --- | ---: | ---: | ---: |
| Status-sample wall interval | 441.599s | 233.971s | 173.084s |
| Native call elapsed | 130.286s | 123.892s | 65.885s |
| Python settlement elapsed | 34.755s | 10.671s | 10.209s |
| Successful native entries | 9,121,721 | 1,995,012 | 1,958,054 |

Heads are respectively `d1268e0`, `0b4e607`, and `d9fda8b`. These are
real-time physical journeys, so native work counts and polling can vary;
they are not fixed-work coverage ratios. The initial profile showed millions
of exits around LOOP/I/TRUE/?DO, and repeated scalar reads in stack snapshots.
After those changes, native calls dominated the observed live interval,
motivating the page-fragment resolver work.

The scalar diagnostic additionally profiled the complete cold
`prepare_image_bootstrap` call. It found 35,106 dictionary definitions and
616,247,600 `Word.body_address` calls. Dictionary definition consumed
136.713s of 250.692s recorded internal profile time. After the bound change,
the same cold preparation still published 35,106 words and counted
11,035,530 preparation steps (11,010,029 autoexec steps), while dictionary
definition fell to 1.124s and body-address calls to 84,641. Total recorded
internal profile time was 110.080s. These are instrumented diagnostics,
not source-load throughput claims.

The remaining preparation profile is distributed across token parsing,
checked scalar memory access, stack handling, and hosted services. There is
no similarly concentrated avoidable scan in this profile. Further work needs
targeted evidence for those smaller costs; this follow-up stops here.

## Focused validation

All selectors ran sequentially, without pytest workers or enlarged budgets.
Rows overlap and must not be added as unique case counts.

| Selector | Result |
| --- | --- |
| Native execution/loops, stacks, clock and quantum | 313 passed, 2.49s |
| Native-selected runtime, real CATCH/THROW, source acceleration and quantum | 83 passed, 6.77s |
| Bulk snapshots, memory, stacks, native loops and CATCH/THROW | 248 passed, 4.33s |
| Final scalar memory, native execution/loops, snapshots, quantum and clock | 331 passed, 2.89s |
| Separate ASan/UBSan native memory, execution and loops | 161 passed, 2.60s |
| Dictionary, numeric rollback, index, arenas, userland, bootstrap and native execution | 170 passed, 8.41s |

The sanitizer extension was built separately with the checked-in
`MEGAFORTH_NATIVE_SANITIZER=address-undefined` option. Leak detection was
disabled for the Python host; address and undefined-behavior checks remained
enabled and the selector verified it imported the instrumented extension.

A fixed-order snapshot microbenchmark compared the actual pre-change class
from `7d9b9d6` with the new class: 1,000 snapshots of 600 cells took
0.363843s / 0.009572s (38.01×), preserving the exact tuple. This is a bounded
snapshot measurement, not a Desktop multiplier.

The unchanged CELL helper retained its 280×2 actual cells inside caller bounds
280×84 and its existing 3,000,000-step row watchdog. At `7d9b9d6`, native feed
was 0.274790s; after the scalar change at `d9fda8b`, it was 0.118333s.
Both use 2,432,950 row-feed steps and produce the same 560 cells, revision 2,
4,848 committed frame bytes, frame counters and timer state. CELL SHA-256:
`fca1c2f79d20b6bf2e227900d156dd3a8d8fd8d771879f2d36b9ea87679ff1ee`.
Successful native entries across begin/cursor/feed/commit fell from the earlier
6,185 to 1,123. This counter scope is broader than the timed row writes.

The final clean-checkout pair at MegaPad `2faeeeb` / Akashic `8bad7eb` measured
Python/native row feed at 4.607281s / 0.105723s and the complete native fixture
at 0.510999s, with the same byte/step/timer oracle. Both repository revisions
and statuses stayed unchanged during the run. An earlier final-pair attempt
was rejected by that stability guard when evidence-document writing started;
it produced no accepted timing report and is excluded from these results.

## Final unprofiled physical acceptance

The ordinary `desktop-apt1` journey used 280×84 cells, an 18px X11 viewer,
320 MiB external memory, real time, the unchanged 900s watchdog, 0.75s action
delay and 10s completion hold. It loaded the same 212 source modules in 33
checked-source chunks: 4,028,241 raw source bytes, 4,029,561 container bytes,
63 MP64FS entries and 55,732 free sectors. Source preparation still counted
11,035,530 semantic steps.

| Exact physical ACK milestone/interval | Previous unprofiled | Final unprofiled |
| --- | ---: | ---: |
| First complete Desk | 204.060423s | 71.895276s |
| Pad edited | 258.872017s | 90.142146s |
| Daybook task added | 335.927848s | 114.929302s |
| Daybook date advanced | 349.228896s | 119.822537s |
| Daybook source opened in Pad | 363.453376s | 124.957036s |
| Pad tab activated | 378.130828s | 130.004123s |
| Final Sound Lab instruments | 497.698337s | 171.732388s |
| Desk → Pad edited | 54.811594s | 18.246871s |
| Desk → Daybook task added | 131.867425s | 43.034026s |
| Outer complete run | 511.819576s | 185.862142s |

These use offer ACK timestamps, not the later screenshot-write timestamps.
The final runner ended at 183.315999s; outer time includes construction and
teardown. Session connection fell from 78.089007s to 30.984398s, which is not
a standalone compiler timing. The comparison uses the earlier same-profile
successful native run in `native-desktop-r2`, recorded in the first evidence
ledger. These are sequential observations on a shared host, not balanced or
pinned-host benchmark trials.

The trace contains 92 contiguous events, 20 observed/projected/acknowledged
offers, and 14 inputs returning progress after the required exact-frame ACK.
Eleven visible milestones passed. Both CELL fallback gates passed; no manual
input RPCs occurred. Retained-only Pad-edited and Daybook-task-added screenshots
were visually inspected. The final frame has 1,016 draws, two text areas,
one text grid, two tabsets, eight readouts, two meters, three status objects,
173 instrument cells and no clipped region. The software physical completion
boundary remains `pygame.display.flip`.

Final sampled aggregate RSS peaked at 411,744 KiB (~402 MiB), minimum system
available memory was 10,860,988 KiB (~10.36 GiB), and maximum one-minute load
was 8.64 on 16 logical CPUs. Neither resource guard fired. The earlier run's
sampled RSS peak was 370,696 KiB; child peak RSS was nearly unchanged
(294,516 / 295,048 KiB), so sampled aggregate memory is not claimed improved.

## Retained artifacts

All paths below are relative to
`local_testing/out/simulator-improvements-20260912/` in Akashic main. All raw
outputs were copied and SHA-256 verified before the isolated worktree was
retired. They remain ignored build/test outputs; embedded absolute paths retain
the original execution location and have not been rewritten.

- `native-desktop-profile-before/`, `native-desktop-profile-loops-snapshots/`,
  `native-desktop-profile-scalars/`: diagnostic journeys, native counter
  snapshots, sampled profiles and resource samples.
- `native-source-profile-dictionary/`: fresh-image cold preparation diagnostic.
- `native-desktop-final/`: final unprofiled manifest, exact trace, screenshots,
  source/extension revision bindings and resource samples.
- `followup-tools/`: local diagnostic/monitor harness copies; the optional
  `MEGAFORTH_PROFILE_PREPARE=1` hook was enabled only for the scalar diagnostic.
- `followup-profile-summary.json`, `followup-desktop-comparison.json`,
  `stack-snapshot-benchmark.json`, `native-sanitizers.log`, and `kernels/`:
  derived scope summaries and focused evidence.

The SHA-256 artifact manifest is `followup-artifacts-sha256.json`. It binds
the reports, profiles, traces, screenshots and harness copies; disk images
remain alongside their run but are excluded from that manifest.

| Artifact | SHA-256 |
| --- | --- |
| Final run revisions | `00934d27bd6111fa289dffb3d916370212f8188a8e7c6c91c620e1330091ab18` |
| Final physical manifest | `6bbae6694091706bf93a2eab2a56ab810c2eca2ce90d6dfbb55d63b7bdc4c076` |
| Final performance trace | `8caa33d914ebf1d0490f3262e5624cc4f46a11f32a7a16e261b3094e0f35555f` |
| Profile summary | `d11c0aa1d806669b0d9b3fbd10007a2b3d158f3c5e0248c9442eb2733d8ecb31` |
| Final CELL benchmark | `6f9efa7b0f8b9f288e0cac39eb94e76d5db4ec19aad5c33f93bd3a5c840dfc24` |
| Complete follow-up artifact hash manifest | `5ea022e437f1eee21d4fd33e14979e667531434f11db6cb4ea08bc62f7f933d9` |
