# Landing the rich components work: the runs — 2026-10-18

The rich components work (parts 5 and 6 of the rich experience plan and the
work after them) lands on main in Akashic and MegaPad together. This note
records how the integration was checked and the runs that qualify the
merged pair.

This is functional regression evidence. The times are the host's, not a
device's, and none of this is UART, panel or touch evidence.

## What lands

| Repository | Commit | Contents |
| --- | --- | --- |
| MegaPad | `dd108ff2` | `feature/rich-components` (`23097286`, 10 commits) merged over main `6b5e35f8` |
| Akashic | `69d82a5e` | `feature/rich-components` (`7c03894c`, 131 commits) merged over main `a2c8cc6d` |
| Akashic | `377f187e` | the Desk shell model test starts a notice's time as a flush would |
| Akashic | `2055cfec` | the agent-widgets smoke expects no overlay from the Agent's run settings |
| Akashic | this note's commit | this note |

Both mains fast-forward to the integration branches.

## Order, conflicts and lost work

Each repository had one branch to land. Akashic's other unmerged remote
branches carry no work main lacks: `bsky-http-fixes` (February) was applied
to main in `0746f36c`, which says so, and main's `http.f` has its SNI fix.
`kalki-additions` (February) reached main as `a5c9df54`, whose math, font and
text modules are its files byte for byte but one REQUIRE path, and as
rebased copies of its other commits. `fix/observatory-slice` is contained in
main and in the feature branch. MegaPad's `dict-cache-profile` and
`secure-server-transport-amended-sibling` stay off main on purpose, as at
the last landing. No worktree had uncommitted changes, and no stash was
touched.

Main is an ancestor of each feature branch, so the merges had no conflicts.
Each merge's tree equals its feature branch's head exactly, no commit of the
feature branch or of main is missing from the integration branch, and the
two fixes above are the only changes made while landing. The Akashic merge
message says 130 commits; there are 131, counting `7c03894c` and the
branch's earlier merge of main.

## Runs

Every run used a fresh checkout of the integration pair, with the native
simulator and emulator extensions built from it, and ran alone after an
uncapped wait for other heavy runs. Each failure was then run on the
untouched mains: a failure that main shows the same way is recorded as
existing.

| Run | Result | Notes |
| --- | --- | --- |
| MegaPad simulator suite (`make test-simulator`) | pass, 3,074 tests, 9 skipped | 146 s |
| MegaPad rich-terminal, session and benchmark tests (`make test-simulator`) | pass, 2,086 tests | 113 s, 1.3 GB |
| MegaPad dual-backend rich-terminal oracles (`make test-rich-terminal-dual`) | pass, 8 tests | |
| Image builds, every profile | pass, 160 images | 83 s |
| Akashic pytest files, one at a time | 284 pass, 23 fail | 22 fail the same way on main; the Desk shell model test was fixed |
| Emulator smokes of every profile whose closure the branch changed | 55 pass, 10 fail | 9 fail the same way on main; agent-widgets was fixed |
| Script tests whose closure the branch changed | 29 pass, 5 fail | all 5 fail on main |
| Desk with each applet alone, simulator, native executor | pass, all 10 (Pad, File Explorer, Daybook, Streams, Agent, Sound Lab, Observatory, small terminal, photo, damaged) | 27 to 137 s each |
| Canonical Desktop journey, simulator, native executor | pass | 189 s, 328 MiB; 52 changed frames as DELTAs, 38 as STARTs |
| L0 inventory and L1 functional baseline checks | pass | on the final integration head |

### Failures that predate the branch

All of these fail on main the same way:

- 19 legacy pytest files that build their machine snapshot only when run as
  scripts, so under pytest every case stops at once on `TypeError` (the
  blockchain tests, `test_fmt`, `test_focus`, `test_string`, `test_utf8` and
  others); the counts match main exactly.
- `test_reentrant_text_projection_contract.py`, `test_gap_buf.py` (two
  memory-span words not found) and `test_vfs_ext4.py` (source counts).
- Smokes: `uidl-lifecycle` (its checks call `_SCR-EMIT-CP`, which left
  `screen.f` on 26 September), `streams` (four journey errors), `soundlab`
  (waits for "centroid 880Hz", which the readout shows as "880 Hz"),
  `streams-contracts` (20 of 579), `package-contracts` (dictionary full
  after its checks pass), `desktop-resource`, `desktop-streams`,
  `streams-multiprotocol-composition` (RSS trust) and `desktop-fallback`.
- Scripts: `test_desk_host_characterization.py` (checks 126, 127 and 288),
  both Desk Library Burrow static checks (26 catalog candidates where 24
  are expected; main fails an earlier check), the Streams authenticated
  vertical (dictionary full, at bundle 87 on main and 89 here) and Rabbit
  landing 3 (core assert 1702).

The `streams` smoke once showed a fifth error, Ctrl+L not leaving the
retained context in time. Two reruns of the integration head did not show
it, and the commit a bisect blamed changes nothing that smoke runs, so it
is a wall-clock flake under host load.

### Fixed while landing

- `test_desk_shell_model.py` passes on main and failed two checks here.
  Bisecting found `210f1d4e`, which starts a notice's time when its output
  goes out; the test paints without a flush, so its notice never started
  its time. The test now starts it as a flush would (`377f187e`).
- The `agent-widgets` smoke passes on main and failed two checks here: it
  still required the Agent's run settings to be a foreground overlay, which
  `e4c05db6` deliberately ended. It now expects no overlay there and stops
  at its failure marker (`2055cfec`).

## Not covered

- The 73 smoke profiles and 146 script tests whose closure the branch did
  not change. Their code is main's, and MegaPad changed only rich-terminal
  code they do not load.
- 28 legacy pytest files marked "HARNESS UPDATE REQUIRED". None loads a
  changed module or the shared harness.
- Runs above the 15-billion-step ceiling, which need approval: the Library
  fixtures (`library-projection-owner-contracts`,
  `library-applet-functional-contracts`), the Desk Library Burrow and
  capstone runtimes (24 and 30 billion steps), and `test_document_view.py`
  (20 billion), whose closure changed only by two new region words and a
  relaxed card check-box rule. The other skipped large pytest files load no
  changed module.
- The emulator `desktop`, `desktop-agent` and `desktop-agent-hardening`
  smokes, which already failed before this work.
- A real device, a real model provider, UART, panel and touch.
