# Simulator integration into paired mains — September 12, 2026

The simulator improvements were fast-forwarded into both local mains without
conflicts, then their two worktrees and the enclosing support directory were
retired. The merged source heads are:

- MegaPad `2faeeebed028256932c70028314ff445f72b7024` (10 commits).
- Akashic `fb4d752fad47f89493d044d18c2b68f3ebc75a19` (4 commits).

Subsequent integration-record commits change documentation only. This task
issued no push commands and added no feature work. Remote-tracking refs did
advance via pushes during the round; `completion.json` records those observed
updates separately from this task's local changes.

## Main verification

The independent native simulator extension was rebuilt with
`make simulator-accel` in MegaPad main. Akashic main was checked to resolve its
sibling MegaPad main and import that rebuilt extension.

Checks ran sequentially with unchanged budgets and no pytest workers:

| Focused selector | Result |
| --- | --- |
| MegaPad native execution, loops, memory, snapshots, dictionary and audio | 207 passed, 1.77s |
| Akashic physical Desktop acceptance-runner units | 87 passed, 0.70s |

The initial Make invocation rejected an overlong monitor namespace before any
tests ran. Retrying with a valid namespace passed; no implementation or test
change was needed. Build and test logs, extension identity and resource samples
are retained in the retirement archive below. Peak sampled process-group RSS
was 456,172 KiB, minimum available system memory was 12,696,876 KiB, and maximum
one-minute load was 5.87 on 16 logical CPUs. No resource guard fired.

The full physical Desktop acceptance and final CELL equivalence results remain
the previously qualified implementation results, documented in the
[follow-up ledger](simulator-native-followup-20260912.md). Integration did not
repeat the full Desktop journey or produce a new throughput measurement.

## Evidence preservation and retirement

All 280 files from the isolated Akashic `local_testing/out/` were copied into
Akashic main at the same relative paths: **275,565,316 bytes**, including disk
images, diagnostic attempts, profiles, screenshots, logs and harness copies.
Every source/destination pair was SHA-256 verified before removal. The existing
follow-up manifest still verifies all 223 of its entries and retains SHA-256
`5ea022e437f1eee21d4fd33e14979e667531434f11db6cb4ea08bc62f7f933d9`.

The current output root is
`local_testing/out/simulator-improvements-20260912/` in Akashic main. Replace
the historical absolute prefix
`.worktrees/simulator-improvements/akashic/` with `akashic/` when locating a
file referenced by an original report. Raw report bytes were not rewritten.

All other ignored worktree files and every enclosing support file were copied
to the workspace's
`worktree-retirement-archives/2026-09-12-simulator/`, preserving the early raw
kernel evidence, helper scripts, compiled extensions and generated caches.
Across both destinations, 488 files totaling 301,900,188 bytes were preserved.

The archive's `pre-removal-manifest.json` records both heads, repository refs
and stashes, all 2,804 worktree file entries, the 15 enclosing support files,
and every preserved destination and hash. Complete inventories were rechecked
immediately before removal. No accessible process used either worktree; both
heads were reachable from their mains and both worktrees were clean.

Both worktrees were removed with ordinary `git worktree remove`, without
force. Only verified support files were then removed from the enclosing
directory. `removal-result.json` records the result. Branch refs and stashes
were retained. The two older detached L7 worktrees were left untouched during
this simulator integration and retirement stage.

After this stage completed, the two historical L7 worktrees were preserved and
retired in a [separate recorded step](l7-worktree-retirement-20260912.md).
