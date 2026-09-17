# Simulator call and fetch optimization — September 17, 2026

MegaPad implements three conventional interpreter improvements, preceded by
a small native-entry guard. Akashic production is unchanged. The changes
reduce interpreter overhead; they do not reduce the guest work needed to
publish a typing update. They are retained as a modest improvement, with about
10% lower median native time in the paired typing diagnostic. Visible latency
remains far from fluid and varies across runs.

## Implementation

- `9b4147d`: Store the next instruction's semantic cost with its prepared
  plan. Decline a native entry before marshalling stacks when the remaining
  allowance cannot cover it. This replaces the previous unsupported-position
  set and preserves the reference dispatcher's partial-budget effects.
- `8f835a0`: Reuse prepared call targets and carry the selected plan directly
  across calls and returns. Static calls cache their plan; `EXECUTE` checks
  the current XT against its cached target. The cache occupies the unused
  call operand, keeping instructions at 24 bytes. Plan objects survive map
  rehash and body replacement; clearing the dictionary generation discards
  every cached target.
- `466fdb8`: Index temporary continuation changes by return-stack position
  instead of hashing each change. Two growable arrays cover the actual span
  reached above and below the entry pointer, without allocating the unused
  stack capacity. Fresh cookies, explicit user-cell deletions and inactive
  retained slots remain authoritative for `RP!`.
- `4693d4f`: Fuse a literal or plain created/constant address followed by
  `@`, `C@`, `W@` or `L@`. Preflight both operations before committing, and
  write the pushed address before reading so partial stack aliases preserve
  the original order. All original instruction indices and partial-budget
  paths remain available.

The internal interface, compiler flags, 8,192-step native quantum, guest
clocks and test budgets are unchanged. These are generic interpreter paths;
there is no app-specific accelerator or compiled Forth cache.

## Focused checks and kernels

The final native-selected selector passes 912 checks in 12.92 seconds.
New executed cases cover dynamic target changes, plan replacement/rehash/
clear, nested returns across multiple quanta, retained raw return bytes and
125 address/fetch budget, alias, overflow, sparse-page and branch-entry cases.
Four entry-guard regressions first fail against the previous implementation
because it still enters native execution with insufficient allowance.

A 380,008-step admission probe preserves all 46 owner yields and its result
while removing 21 zero-progress entries caused by a one-tick allowance.
Two legitimate empty entries remain in that probe.

The existing kernel runner stays at a 1,500,000-step invocation limit and
300,000-step setup limit. Each process runs four trials, with the first
discarded for medians. Processes run sequentially, alternating variant order.
All trials have identical semantic counts and results across the compared
variants. Per-slice comparisons have four process pairs; the combined
comparison has five. These are shared-host observations, not confidence
intervals or physical typing timings.

| Kernel | Before ms | After ms | Throughput ratio |
| --- | ---: | ---: | ---: |
| `arithmetic` | 2.107 | 2.232 | 0.944× |
| `field_reads` | 5.559 | 5.252 | 1.058× |
| `direct_reads` | 2.828 | 2.538 | 1.114× |
| `loop_calls` | 4.751 | 4.768 | 0.997× |
| `dynamic_calls` | 5.341 | 5.019 | 1.064× |
| `scattered_reads` | 3.206 | 3.114 | 1.029× |
| `compare_strings` | 1.699 | 1.750 | 0.971× |
| `fill_bytes` | 2.059 | 1.946 | 1.058× |
| `forward_copy` | 2.128 | 2.237 | 0.951× |
| `move_bytes` | 2.186 | 2.160 | 1.012× |
| `stack_pointers` | 2.078 | 2.096 | 0.991× |

Earlier isolated slice gains do not consistently compound. The combined
result supports a useful direct-read improvement, with mixed smaller changes
elsewhere. A further attempt to restore local instruction copies was slower
in most kernels and was discarded before physical qualification. Its raw
trials and patch remain in the artifacts, with no production option added.

## Physical typing

| Pair | Baseline isolated | Candidate isolated | Baseline burst median | Candidate burst median | Native interval, before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.678 s | 0.651 s | 0.978 s | 1.183 s | 217.7 → 187.4 ms |
| 2 | 0.627 s | 0.719 s | 0.900 s | 0.902 s | 215.9 → 209.7 ms |
| 3 | 0.706 s | 0.615 s | 1.015 s | 0.876 s | 233.6 → 196.9 ms |

Each fresh run uses the ordinary source-mode Desktop, the same physical X11
viewport and font, one isolated character followed by eighteen inputs at
5 Hz. The same observer profiles only the isolated-character interval and
disables native profiling for the burst. All timing domains remain separate:
native time is a subset of observed owner work and cannot be subtracted
directly from end-to-end latency to infer an exact speedup ceiling.

The three pairs run candidate/baseline, baseline/candidate, then
candidate/baseline. Historical runs use the existing checkout with a matching
archived native binary, restoring `main` and its binary afterward. No new
worktree is created. Host load and scheduling differ; all slow trials remain
in the evidence.

All 114 characters appear, and all saved ready, isolated-character and final
milestone pixels match exactly across the six runs. Median native time falls
217.745 → 196.896 ms, about 10%, and native time per semantic step falls
13.606 → 12.002 ns. Every pair reduces native time, although the amount varies.
The median zero-progress native call count falls 814 → 31. Remaining empty
calls retain their legitimate reference fallbacks.

Observed isolated feedback medians are 0.678 → 0.651 s, and burst medians
0.978 → 0.902 s. The first pair's burst is slower, the second effectively
unchanged and the third faster. Final-character drain medians are slightly
worse, 0.896 → 0.910 s. These results establish neither a precise causal
end-to-end speedup nor fluid typing. Median settlement is 18.575 → 19.355 ms;
this change does not establish a settlement improvement.

Retain the changes as a modest interpreter improvement. The observed typing
interval still performs roughly 16 million guest steps, with about 4.14
million in UIDL aggregation, 2.92 million in hybrid preflight, 2.51 million in
delta comparison and 1.43 million in residual planning. These phase counts
are nearly unchanged. Calls and fetches execute more cheaply while repeated
scene processing, host boundary work and physical reconstruction/composition
remain. This pass does not exhaust more substantial interpreter techniques,
such as caching stack values across proven-safe operation sequences, and
does not measure their prospective benefit.

## Final qualification and evidence

The full ordinary Desktop journey passes 18 visible milestones, 21 inputs,
27 physical ACKs and both CELL fallback gates in 137.064 seconds, peaking at
443.207 MiB aggregate RSS. It includes live Pad editing, Daybook task and date
changes, source opening, taskbar/launcher actions and ordinary app menus.
Artifact: `physical-menus-lr_4of8a`.

The final unprofiled typing run displays all 19 characters, with 0.624 s
isolated feedback, a 0.880 s burst median and 0.860 s final-character drain.
Its ready, isolated-character and final pixels exactly match the paired
baseline. It takes 63.918 seconds and peaks at 380.902 MiB. This single run
confirms behavior without the observer; it is not another matched baseline
comparison. Artifact: `fixed-s_lcw4am`.

The six paired diagnostics take 60.624–66.880 seconds each and peak at
376.551–382.602 MiB, with exit 0 and no guard stop.

All selectors, builds and physical runs are sequential. The physical guards
remain 900 seconds and 3.5 GiB aggregate RSS. Resource glances show roughly
13–14 GiB system memory available during the paired runs.

The baseline is MegaPad `6bed823`; the retained candidate is `4693d4f`.
Both use Akashic `eb97390`. Native binary SHA256 values are respectively
`c346fa9fd03d56b98b1fc97ecb2b4c5ba28a2d3663ffd2fb08d3d15555250172`
and `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c`.

The [tracked evidence](../../local_testing/evidence/simulator-calls-20260917.json)
preserves every paired physical latency, source/binary binding, resource
result, kernel trial and raw-artifact hash. Complete artifacts and exact
analysis drivers remain under `local_testing/out/simulator-calls-20260917/`.

Rebuild the tracked aggregate from the retained artifacts, from the Akashic
root:

```sh
python local_testing/out/simulator-calls-20260917/analysis/report_simulator_calls.py \
  --output-parent local_testing/out/simulator-calls-20260917 \
  --pair baseline-hj8w416q fixed-q0msi0aq \
  --pair baseline-brqigoij fixed-iv9kw54e \
  --pair baseline-32nbkw0k fixed-614w1t1q \
  --desktop physical-menus-lr_4of8a --unprofiled fixed-s_lcw4am \
  --output /tmp/simulator-calls-evidence.json
```

For a new measurement, select the intended MegaPad source commit in a clean
checkout and force-rebuild its native extension before running the archived
`analysis/physical_typing_cpu.py` driver. Its arguments are `run`,
`--akashic-root`, `--megapad-root`, `--font`, `--output-parent` and `--label`.
Use the same source-mode Desktop, font and observer for both variants, and
restore the current checkout and matching binary afterward. The archived
kernel drivers record binary and Python-boundary hashes; keep a matching
`simulator` package beside any binary used with `--extension-dir`.
