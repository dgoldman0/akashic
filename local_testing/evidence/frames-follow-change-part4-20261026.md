# Part 4: safe mode — 2026-10-26

Part 4 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
adds safe mode. In safe mode every frame is built in full from live state,
with every check on, and the full build's result is what the terminal
receives. A key in Desk's system settings turns it on, and so do a boot
option and the rich path itself, when a handover proof finds memory laid
out wrongly. Desk then says on screen that safe mode is on and why. In safe
mode the checks name the structure they find damaged, a damaged build is
shown as plain text, and the bank of the frame on screen carries a CRC-64
seal that a DELTA or a click must match before it uses the bank. The key
lives on a settings disk that MegaPad gained for it: a second storage
controller with a write-protected medium, in the emulator, the simulator,
the BIOS, KDOS and the RTL.

This note records the commits, the four defects found on the way, the
tests, the physical runs after each slice and at the end of the part, and
what a typed letter's frame costs in each mode. Apart from the RTL
testbenches, which ran in Icarus Verilog, all of it is simulator evidence.
None of it is UART, panel or touch evidence, and no FPGA image was built.
Steps are the simulator's semantic steps.

## What changed

| Commit | Change |
| --- | --- |
| Akashic be9a8c80 | The switch. `tui/check-mode.f` holds why safe mode is on (`CHK-WHY-CONFIG`, `CHK-WHY-BOOT` or `CHK-WHY-ANOMALY`), keeps the first reason for the session, and answers every check's `CHK-EVERY-FRAME?` with true. Safe mode turns off five shortcuts that reuse an earlier frame's work: the snapshot adapter's reuse of an unchanged document, the producer's held glyph plan and its damaged-rows path, its menu reuse, its unchanged route, and the shell's copied rows. The DELTA comparison with the frame on screen stays, so safe mode still sends only what changed. `--safe-mode` on the launchers boots in safe mode, and the final guest diagnostics report the mode. |
| Akashic 6a1f557d | A defect fix, below. |
| Akashic 7104badb | Each check that runs only with every check on names the structure it finds damaged (`CHK-NAME`, `CHK-DAMAGE`, `CHK-DAMAGE-COUNT`). In safe mode a build refused for damage is shown as plain text, and rich is tried again on the next draw. The shell checks its acknowledged bank again before a DELTA builds on it or a click is routed through it. |
| Akashic f818fb24 | A handover proof that fails names what it found and turns safe mode on (`CHK-ANOMALY`, `CHK-HANDOVER`): the snapshot adapter's proofs at install, start and attach, and the producers' and the engine's proofs that a block from Desk's memory source lies apart from what they hold. The rich terminal's owner says in a warning notice that safe mode is on and why, and says once more when a check first names damage in safe mode. |
| Akashic 92be7c95 | A test-harness fix, below, and the runner's check that a safe run shows the notice, as a warning in rich and in CELL. |
| Akashic 29796abf | The seal (decision 9). In safe mode the screen producer's pending bank and the shell's frozen bank take the CRC-64 of what they hold, from the CRC engine, when their frame is sent. A DELTA or a click uses the acknowledged bank only while a fresh CRC still matches; a mismatch names the bank, and the frame goes out whole. A bank without a seal is not used either, and nothing is named. |
| Akashic a7027072 | A defect fix, below. |
| MegaPad e5b4ae34 | A second storage controller at MMIO +0x0280 holds the settings disk, whose medium is write-protected, in the emulator and the simulator, with eight BIOS unit words appended to the dictionary. Both controllers share the disk's one DMA port. |
| MegaPad 0683cfe5 | The RTL: the disk window split in two, a second `mp64_disk` with its own SD slot whose card is always write-protected, and an arbiter for the two controllers' byte DMA on the disk's port. |
| MegaPad 1833d16f | KDOS opens a block device on either unit (`BD-OPEN-UNIT`), and `SETTINGS-OPEN` opens the settings disk's raw volume, read-only, beside the system volume. KDOS mounts no filesystem on it. |
| Akashic 0b0625d4 | Desk's system settings (decision 10). `tui/platform/settings-disk.f` mounts the settings volume's filesystem for one read and gives everything back; `tui/desk-system-settings.f` reads `system.toml`, whose `[desk.rich-terminal] safe-mode = true` turns safe mode on for the config reason before Desk builds its first frame. The host builds a 2048-sector settings image beside every Desktop image and attaches it; `--settings-safe-mode` builds it asking for safe mode. |
| Akashic 12a856f9 | A defect fix, below, with two smaller fixes: the TOML layer's error state is left as it was, and an empty settings file reads as no bytes. |
| Akashic 75a5c9e5 | The Desktop launcher and the typing run fail a run whose guest reports safe mode for another reason than the one asked, or reports it on when none was asked. |

Settings that are absent, unreadable or malformed ask for nothing: they
are outside data, so none of them is an anomaly or names damage. The plain
Desktop loads none of this.

## Defects found on the way

Four defects were found and fixed, each in its own commit. Two of them only
the physical runs found.

- **A shell click read the wrong bank** (6a1f557d). The click is routed
  through the acknowledged bank, but the control lookup read the batch of
  whichever bank a check had read last. Since part 3 (41a5851e) normal
  mode skips the freeze's check, so after later frames the lookup could
  read an earlier START's batch, at its offset, in a bank a newer frame may
  have rewritten. It showed while slice 2's damage test was being written,
  whose clicks found nothing.
- **The Pad journey dropped a key** (92be7c95). The first safe run of Desk
  with Pad at f818fb24 timed out at 303.5 seconds. A Backspace the terminal
  held back, because the notice's end was a newer frame, was discarded as
  every journey does, but the journey had already recorded the caret it
  waited to leave, so it never sent the key again. The fault was the
  journey's, not safe mode's.
- **The shell's seals overwrote its embedded extension record**
  (a7027072). At 29796abf both runs of Desk with Pad stopped at boot with
  `desktop exception -3203`, the app shell's terminal status INVALID. The
  shell's two seal fields sat at offsets 176 and 184 of its record, inside
  the 40-byte extension record it embeds at 168, and even normal mode
  writes a seal of 0 at every freeze. The unit tests' staged harness never
  proves the extension, so it passed. A test now reads the record's
  offsets from the source and requires each field to lie apart.
- **The settings read left no current filesystem** (12a856f9). At 0b0625d4
  both runs stopped with a Forth ABORT" after Desk's setup had finished.
  `VFS-NEW` makes each new filesystem current and `VFS-DESTROY` clears the
  current one, so after the read Desk had none. Desk's run begins with its
  catalog, which aborts without one. The runs kept no abort text; the
  runs after the fix passed. The unit tests mounted no boot disk. A test
  now mounts one first, as Desk's composition does; on 0b0625d4's reader
  it finds no current filesystem.

## Tests

The Akashic files that load or read what each slice changed ran one file
at a time, with MegaPad on the path: 96 for be9a8c80, 11 for 6a1f557d,
102 for 7104badb, 110 for f818fb24, 4 for 92be7c95, 118 for 29796abf, 14
for a7027072, 9 for 0b0625d4, and one each for 12a856f9
(`test_desk_system_settings`, 10 tests) and 75a5c9e5
(`test_rich_terminal_applet_journeys`, 60). The new files are
`test_app_shell_apt1_safe_notice.py`, which runs the owner's notice words
from the production source, and `test_desk_system_settings.py`, which runs
KDOS and the settings modules in the native simulator against real MP64FS
settings images.

The plan's damage test is in `test_shell_delta.py` (7104badb): a write into
the shell's acknowledged bank goes unseen in normal mode, where a click and
the next DELTA still go through it, while in safe mode the click goes
nowhere, the DELTA is refused, the START that follows freezes the other
bank, and the check names the shell's banks. The seal's tests (29796abf)
check the CRC against a CRC-64/WE computed in Python and against the
standard check value, change one byte of a label the frame shows and of a
run in the shell's bank, and cover a bank without a seal and a busy CRC
engine.

MegaPad ran its suites through the Makefile, one at a time. For
e5b4ae34: the storage, bus, BIOS and disk-utility system classes (431), the
storage, session, strict-cycle and hybrid session files, and the simulator
suite on both executors (3,079 each). For 0683cfe5, from a RAM copy of
`rtl/` with iverilog: the new `tb_byte_dma_arbiter` (10 checks) and
`tb_disk_pair_dma` (7), and `soc_smoke` (32), `soc_elaborate`,
`peripherals` (73), `disk_controller` (65), `disk_bus_dma` (15),
`platform_sim` (5), `soc_wots` (66), `soc_tile_icache` (11) and `tacc_soc`
(43); Verilator lints the arbiter clean, and Yosys synthesizes it to 96
cells. A full SoC synthesis was not run. For 1833d16f: the simulator suite
on both executors (3,081 each, 9 skipped), the KDOS load benchmark, and the
system tests of KDOS, application loading, the PROVIDED guard and the BIOS,
1,859 passing and 3 failing.

The three failures predate the part. `TestKDOSModuleSystem::test_relative_require_throw_rolls_back_and_retries`,
`TestAppLoad::test_app_load_throw_restores_loader_and_machine_state` and
`TestKDOSDynamicModuleRegistry::test_nested_throw_rolls_back_all_provisional_ids_then_retries`
fail the same way on clean checkouts of earlier commits, the last of them
on 2faa96d8 too. That system-test run peaked at 6.7 GiB in one process,
above the 4 GiB at which a run needs approval first; a later run of the
same set should ask, or be split.

## Bindings

The runs at the end bound clean trees. This note is committed after them.

| Binding | Value |
| --- | --- |
| Akashic | `75a5c9e54e206469cd74b22d5669611106a907dc` (tree `ed43bc88f928bd587a483d7e8392ccd2e8a17ea9`) |
| MegaPad | `1833d16f70322ee95a3a5404c323d4b8dfdf92dc` (tree `ed0550c17cb3f029838036cf95b980dcf4f92365`) |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |
| Typing harness SHA-256 | `618fb25dfb7c7925eb8ed93825be93e28e22d3565df4fa54ce4df3a5f6f82f1f` |
| Desktop launcher SHA-256 | `3a037906ed72cfa5ff7014d5328b184405b748c7db5066347f488bbe3bdace64` |

## Desk with Pad after each slice

The native simulator at 280 × 84, one run at a time, after an uncapped wait
for other heavy runs, under the 900-second watchdog and the 3.5 GiB
aggregate-RSS stop. Up to a7027072 every run had the shadow check, which
compared 437 times in normal mode, 224 of the snapshot, 75 of the
producer's runs, 42 of its menus and 96 of the shell's runs, and found no
difference; in safe mode it compared nothing, since no shortcut was taken.
From 7104badb on, when checks began naming damage, no run named any.

| Commit | Safe mode | Time | Normal mode | Time | Notes |
| --- | --- | ---: | --- | ---: | --- |
| be9a8c80 | boot, pass | 43.4 s | pass | 43.8 s | |
| 7104badb | boot, pass | 52.5 s | pass | 49.3 s | |
| f818fb24 | boot, timed out | 303.5 s | pass | 45.0 s | the journey's dropped key |
| 92be7c95 | boot, pass | 52.5 s | pass | 51.4 s | the notice on the first frame |
| 29796abf | boot, failed at boot | — | failed at boot | — | the seals over the extension record |
| a7027072 | boot, pass | 60.9 s | pass | 52.6 s | |
| 0b0625d4 | config, failed at boot | — | failed at boot | — | no current filesystem |
| 12a856f9 | config, pass | 52.9 s | pass | 44.6 s | without the shadow check |

At a7027072 the safe run committed 10 DELTAs, 7 STARTs, 7 continuations
and one empty present, and the normal run 10, 6, 6 and one. The runs at
12a856f9 committed the same, so the settings path and the boot option give
the same frames. The normal run at 12a856f9 had the template settings
attached, which ask for nothing, and the guest reported safe mode off.

## The end of the part

At 75a5c9e5, the canonical Desktop journey across Desk, Pad and Daybook:

| Run | Time | Comparisons | DELTAs | STARTs | Continuations |
| --- | ---: | ---: | ---: | ---: | ---: |
| With the shadow check | 228.5 s | 4,692 | 52 | 39 | 36 |
| Without it | 219.8 s | — | 52 | 39 | 36 |
| With the settings asking for safe mode, and the shadow check | 417.5 s | 0 | 51 | 40 | 37 |

Each run also committed one empty present, and none named damage. In
normal mode the journey made parts 1 to 3's 4,692 comparisons and found no
difference. In safe mode the guest reported the system settings as the
reason, with every check on, and the first frame showed the notice, as a
warning in rich and in CELL. The journey's own part took 412.7 seconds in
safe mode, against 224.1 and 214.9 in normal mode. Its scripted pauses are
the same in every mode, so the difference is the guest's work.

## What safe mode costs

The typing run with `--screen-profile`, every call chain kept and
`PYTHONHASHSEED=0`, at 75a5c9e5, once in normal mode and once in safe mode
asked at boot. The first character comes alone; the other 18 arrive at five
a second. Millions of steps:

| | Normal mode | Safe mode |
| --- | ---: | ---: |
| Isolated character, all steps | 20.31 | 41.96 |
| Its frame build | 18.28 | 39.26 |
| Checks in it | 8.98 | 15.99 |
| Fit | 0.13 | 0.72 |
| Building, copying and comparing | 9.18 | 22.54 |
| The documents' snapshot | 1.51 | 6.62 |
| The seal's CRC-64 | — | 2.23 |
| Desk's painting | 0.92 | 0.98 |
| Time on the host | 0.45 s | 2.48 s |

Normal mode costs what it did at the end of part 3, as the plan expected.
A burst frame's build took 9.63 million steps against 9.62, all a burst
frame's steps 11.41 million against 11.36, and the isolated character 20.31
million against 20.18. The burst made 17 frames rather than 18, since its
keys arrive on the host's clock. Its checks took 3.51 million: items 1.80,
repeats 1.16, handover proofs 0.49 and state 0.05.

The isolated character is one DELTA in both modes, so it compares them
directly. In safe mode it costs about twice what it costs in normal mode.
Checks take 15.99 million steps against 8.98, and the rest of the build,
which reuses nothing, takes 22.54 million against 9.18. The snapshot
adapter, which captures every document afresh, takes 6.62 million against
1.51, its checks included. Taking and checking the seal, over the screen
producer's bank and the shell's, costs 2.23 million. At slice 1, before
damage naming, the notice and the seal, the same character cost 38.37
million.

The plan expected safe mode to cost about what the path cost before part
3: 16 million steps for a burst frame and 26 million for an isolated
character. It costs more. Before part 3 every check ran too, but the
reuse shortcuts still saved work, and safe mode turns them off.

In safe mode the burst made only three frames for its 18 keys. Each frame
took longer than the 200 ms between keys, so the guest folded several keys
into each one, as normal mode did before part 3. Its third frame was a
START of 115,750 bytes, the first frame without safe mode's notice, which
shows for ten seconds. That START and its continuation are half the burst's
four presents. The burst's average, a frame build of 23.58 million steps a
present, therefore mixes a START's cost into it, and is not what a DELTA
costs. At slice 1, before the notice existed, the safe burst made 11 DELTAs
with a frame build of 23.97 million each.

## Files

The runs' output stayed in `/dev/shm` and was deleted after this note was
written. By its shell's `write_bytes`, each run at the end wrote nothing to
the drive.
