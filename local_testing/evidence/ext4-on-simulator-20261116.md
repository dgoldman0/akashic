# ext4 tests on MegaPad's simulator — 2026-11-16

Akashic's ext4 tests ran their journeys only on MegaPad's emulator, which
executes the BIOS, KDOS and the driver instruction by instruction and moves
each storage request a byte at a time. A whole run of
`test_vfs_ext4.py` took 86 minutes and peaked at 5.4 GiB. This note records
the work of 2026-11-16 that lets the four files using the ext4 harness run
on MegaPad's simulator as well, what each step cost and bought, and what
the simulator still leaves to the emulator. The emulator remains the
default backend and the device-faithful reference;
`AKASHIC_EXT4_BACKEND=simulator` chooses the simulator
([`../README.md`](../README.md), "On the emulator or the simulator").

Every run was made one at a time in RAM worktrees of the two
`ext4-tests-on-simulator` branches, with MegaPad's native libraries built in
its worktree and named to Akashic by `MEGAPAD_ROOT`. The standing sample is
the 22 test ids (25 cases) in
`~/.cache/fantasy-engine/notes/ext4-sample-ids-20261115.txt`, all from
`test_vfs_ext4.py`, run with `EXT4_REPORT_STEPS=1`; the source rules are
`test_vfs_ext4.py -k test_ext4_`. Times are wall-clock seconds on this
machine. Memory is `/usr/bin/time`'s maximum resident set of the test
process; for a whole file it is the larger of that and the largest
proportional set of the run's process tree, sampled every two seconds,
since a simulator run forks.

## What changed

MegaPad, on `ext4-tests-on-simulator`:

| Commit | Change |
|---|---|
| `868900b6` | Test faults and the request observer are one C++ definition both storage controllers use (`docs/storage-faults.md`) |
| `a64281ad` | The simulator's storage can adopt a caller's buffer or mapping and trust its file to hold the medium |
| `8ac8a39f` | The CRC words run in the simulator's engine; one C++ CRC recurrence serves the emulator's CRC unit and the simulator's service |
| `c1576aa7` | The native service classes load on first use, so help needs no build |
| `436060c3` | The storage service is C++ and the engine runs all seventeen disk words |
| `4d91f585` | Test targets build the simulator's library only when a source changed |
| `adcbd59e` | The session boundary test lets the hosted owner load the simulator's extension |

Akashic, on `ext4-tests-on-simulator`:

| Commit | Change |
|---|---|
| `5b351e0f` | The harness runs journeys on either machine: backend choice, per-backend step budgets, checks that read each line's own output |
| `ac1183ee` | Simulator journeys run on copy-on-write clones of one loaded machine |

## The standing sample, step by step

| After | Emulator | Simulator |
|---|---|---|
| Harness on either machine (`5b351e0f`, MegaPad `a64281ad`) | 238 s | 130 s |
| CRC words in the engine (MegaPad `8ac8a39f`) | 224 s | 65 s |
| Disk words in the engine (MegaPad `436060c3`) | 227 s | 68 s |
| Clones of one loaded machine (`ac1183ee`) | 225 s | 21 s |

All 25 cases passed in every run, with no skip, and the 36 source rules
passed on both machines each time. The emulator's times differ only by
the machine's load: the one change to the emulator, its CRC unit's move
onto the shared recurrence, kept its behaviour.

The CRC words had been the largest cost: an ext4 mount feeds about 51,000
cells to the CRC unit, and each return from the engine to Python cost about
12 microseconds. Moving the disk words into the engine took a two-sector
KDOS `BD-READ` from 76 to 82 microseconds to 0.90, and a `BD-WRITE` to
1.51, with no return to Python, yet the sample barely moved: each journey
then spent most of its time loading its own machine, 0.84 to 0.90 s against
0.114 s for a 1 KiB-block mount journey itself. The fork of the test
process that runs a journey costs 3.1 to 3.3 ms.

The simulator's journeys took 0.190 to 0.202 of the emulator's steps for
the same work, 48 journeys with a median of 0.198, the same in every run.
Its budget is a quarter of the emulator's, and the largest share of a
budget any journey used was 0.17 on the simulator and 0.22 on the
emulator. The simulator's test process peaked at 534 MiB where the
emulator's reached 2,589 to 2,672 MiB.

## The four files whole on the simulator

Each file then ran whole on the simulator, one after another, under a
guard that would have stopped a run whose process tree passed 4 GiB. The
emulator's times are the test tool's records of 2026-11-16 for Akashic
`efddbd54` and MegaPad `977ef95e`; the two Akashic commits between that
record and these branches' base change neither the ext4 tests nor the
driver.

| File | Cases | Emulator | Simulator | Simulator's peak |
|---|---|---|---|---|
| `test_vfs_ext4.py` | 835 | 5,164 s, 5,393 MiB | 381 s | 1,705 MiB |
| `test_vfs_ext4_user_volume.py` | 14 | 1,012 s | 54 s | 796 MiB |
| `test_vfs_ext4_retained_orphan.py` | 8 | 988 s | 47 s | 890 MiB |
| `test_vfs_replace_ext4.py` | 11 | 359 s | 23 s | 1,004 MiB |

Every case passed but one, which skipped on purpose: the `orphan-home`
case of `test_unlinked_cleanup_write_prefixes_converge_on_fresh_mount`
under the legacy orphan protocol, which has no write of its own to the
orphan home and has skipped on either machine since `700f6aea`
(2026-08-02). The four files took 505 s together against 7,523 s, about a
fifteenth. A mount journey on the 1 KiB-block fixture now returns from
the engine to Python 160 times in 3.5 million steps: 67 times at a call
of `!` that the engine left to Python, 30 times at the end of one of its
65,536-step intervals, and 63 times at other words and returns.

## Two traces the timing study could not match

The timing study before this work
(`~/.cache/fantasy-engine/notes/ext4-simulator-timing-20261116.txt`) found
two cases,
`W2-reset-guard` and `W5-C-completion`, whose write and flush traces
differed between the machines. Both differences came from the study's own
harness. Those recovery runs pass one path as both image and backing file,
so the emulator's run rewrote its own input, and the study's simulator twin,
run afterwards, read the converged medium and so made no writes. Fed each
run's own input, all five recovery runs of the two cases matched in output,
trace, final medium and capture.

## What stays with the emulator

Two tests read the emulator processor's CRC registers through `configure`,
and two print the device's cycle count; they run on the emulator whichever
backend is chosen. The simulator completes each storage request when the
guest makes it, so it cannot hold one stalled; no ext4 test plants a stall.
A transfer or flush returns to Python when a test's admission hook must run,
as in the save tests' `Machine`, or when the filesystem lock is held.

## Not run

The physical Desktop journey, the test tool's wide run, the emulator's
Desktop smokes and the whole of `test_vfs_ext4.py` on the emulator were not
run for this work.
