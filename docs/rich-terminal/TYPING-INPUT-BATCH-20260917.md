# Input batching experiment — September 17, 2026

**Reverted.** Draining ready keyboard events before painting reduced internal
draw passes, but neither tested time window established a useful improvement
in physical typing latency. Commit `8bb9bbb` restores the production Akashic
source subtree exactly to `9d211ff`. No batching option, timing constant or
alternative event loop remains. MegaPad was unchanged.

## What was tested

Candidate `462e2dd` gave the shell an 8 ms elapsed-time input pass. Candidate
`d10000e` increased it to 32 ms after direct observation showed that terminal
service often consumed most of the smaller window before key dispatch.
An empty poll ended the pass immediately: neither version waited to collect
future keystrokes or changed the capacity of the existing input queues.

Events stayed ordered. Terminal service, deferred actions and tick checks
ran between keys. Pointer/control events, resize, a callback-completed draw,
quit or terminal failure ended the pass. The elapsed budget was checked
after each dispatch and tick; callbacks and servicing could overrun it.
Normal painting and yielding followed the pass. No applet, renderer, ABI, simulator
timing rule, source cache or test step limit changed.

The focused shell and publisher selector passed 52 checks in 8.59 seconds
for the revised candidate. Executed Python/native cases covered ordering,
backspace, deferred focus changes, empty queues, fairness, ticks, uptime wrap,
slow callbacks, quit/error boundaries, mouse/resize, callback drawing,
Unicode/paste delimiters and legacy hardware-resize checks. Transport,
application dispatch and draw sinks were deterministic doubles; this was not
a full Desktop qualification.

## Physical comparison

Each run used the ordinary source-mode Desktop, the same 3080×1764 physical
X11 viewport and font, one isolated character followed by eighteen inputs
scheduled individually at 5 Hz. All ten runs displayed the complete
`~fluid typing 12345` sequence. There were no new worktrees: baseline runs
temporarily selected `9d211ff` in the existing checkout and restored `main`.

The eight paired measurements used the identical existing CPU observer,
active only for the isolated character and disabled for the burst. They are
paired diagnostics, not unprofiled latency guarantees. The first three pairs
ran candidate then baseline; the final pair reversed that order.

| Window | Pair | Baseline isolated | Candidate isolated | Baseline burst median | Candidate burst median |
| --- | --- | ---: | ---: | ---: | ---: |
| 8 ms | 1 | 0.629 s | 0.613 s | 0.880 s | 0.882 s |
| 8 ms | 2 | 0.632 s | 0.555 s | 0.817 s | 1.590 s |
| 32 ms | 1 | 0.801 s | 0.964 s | 1.077 s | 1.769 s |
| 32 ms | 2 | 0.667 s | 0.629 s | 0.898 s | 1.018 s |

These observations do not establish that batching caused every slowdown.
Shared-host throughput varied. The first 32 ms candidate/baseline pair had
60.3%/51.8% aggregate CPU use, compared with 33.3%/35.0% in the reversed
pair. The second 8 ms run developed much longer frame intervals without a
proportional increase in guest steps; that slowdown remains unlocalized.
All observations, including these slower trials, remain in the evidence.
No paired burst result improved, so there is no measured latency benefit to
justify retaining this implementation.

## What the grouping diagnostic established

Two additional runs used the same read-only observer to sample shell input,
pass-start time and draw generation after existing simulator owner
boundaries. Both observed all 19 characters in order. The 8 ms version used
18 input-bearing passes, while 32 ms used 12, grouping up to three keys.
The draw-generation groupings matched the input-pass groupings. Sampling
cannot distinguish adjacent identical keys or every sub-boundary event;
this diagnostic string has no consecutive identical characters.

In the 32 ms diagnostic, consecutive keys within a pass used about 180,000
native-counted guest steps between observations. Where a draw intervened
without a publication-phase change, the corresponding median was about
700,000 steps. These small samples indicate roughly half a million steps
saved per avoided intermediate paint, rather than the removal of an entire
publication. They are boundary samples, not exact callback instruction
counts or independent wall-time measurements.

The pre-existing output path already retained pending input and combined
several characters into visible frames. Both grouping diagnostics still
produced ten typing frames. Typical steady visible-update intervals remained
around 14–16 million guest steps. UIDL aggregation, hybrid preflight, delta
comparison and publication still ran for those frames. Batching removed
some intermediate drawing while leaving most of that larger cost in place.

An isolated candidate update also measured roughly 3.82 million steps in
UIDL aggregation versus 4.14 million before, despite having only one input to
handle. That difference is not explained by grouping keys and is not claimed
as a batching benefit. The next larger target remains the repeated work over
unchanged scene data during aggregation and preflight, followed by host
reconstruction/composition; this experiment did not optimize those paths.

## Final state and evidence

After reverting, the publisher selector passed 20 checks in 9.57 seconds.
Git subtree IDs confirm that all production files under `akashic/` exactly
match the already-qualified baseline. The candidate-only test file was
removed; its committed history and an artifact copy preserve the experiment.
A new full Desktop acceptance run was unnecessary for this rejected change;
the restored source is the previously accepted source.

All runs and suites were sequential. Physical runs took 60.657–77.330 seconds
and peaked at 382.695 MiB aggregate RSS, with exit 0 and no guard stop. The
existing 900-second / 3.5-GiB guards and focused helper's 3,000,000-step limit
were unchanged. Resource glances showed about 13–15 GiB available RAM.

MegaPad stayed at `6bed823`, with native extension SHA256
`c346fa9fd03d56b98b1fc97ecb2b4c5ba28a2d3663ffd2fb08d3d15555250172`.
The [tracked evidence](../../local_testing/evidence/typing-input-batch-20260917.json)
contains every latency, grouping sample, source/binary binding, resource
result and raw-artifact hash. Artifacts and exact harness/observer copies are
under `local_testing/out/typing-input-batch-20260917/`.

| Experiment | Candidate artifact | Baseline artifact |
| --- | --- | --- |
| 8 ms, pair 1 | `fixed-fh9qbm5a` | `baseline-_79mtbn3` |
| 8 ms, pair 2 | `fixed-h6dpk0zw` | `baseline-dilwgwlp` |
| 32 ms, pair 1 | `fixed-xnuvbzhv` | `baseline-fxwzewqr` |
| 32 ms, reversed pair 2 | `fixed-v2_vwt32` | `baseline-pahfw2de` |
| 8 ms grouping only | `fixed-lr88ypce` | — |
| 32 ms grouping only | `fixed-8optsw0w` | — |

To rerun the physical diagnostic from the Akashic root, select the source
commit being measured in a clean checkout, then use the archived harness.
Restore `main` after any baseline or historical-candidate run. This requires
the local physical display and Unix socket access.

```sh
batch_artifacts="$PWD/local_testing/out/typing-input-batch-20260917"
python "$batch_artifacts/analysis/physical_typing_cpu.py" run \
  --akashic-root "$PWD" --megapad-root "$PWD/../megapad" \
  --font "$PWD/assets/fonts/DejaVuSansMono.ttf" \
  --output-parent "$batch_artifacts" --label fixed
```

Use `analysis/observed/physical_typing_cpu.py` for the separate grouping
diagnostic. The evidence records the different observer hashes, and its
timings are kept separate from paired measurements. Rebuild the aggregate
from the retained artifacts with:

```sh
python "$batch_artifacts/analysis/report_input_batch.py" \
  --pair 8ms fixed-fh9qbm5a baseline-_79mtbn3 \
  --pair 8ms fixed-h6dpk0zw baseline-dilwgwlp \
  --pair 32ms fixed-xnuvbzhv baseline-fxwzewqr \
  --pair 32ms fixed-v2_vwt32 baseline-pahfw2de \
  --grouping fixed-lr88ypce --grouping fixed-8optsw0w \
  --decision 'Reverted: no useful physical typing latency improvement established.' \
  --output /tmp/typing-input-batch-report.json
```
