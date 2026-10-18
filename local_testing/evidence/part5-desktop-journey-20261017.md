# Part 5 closing runs — 2026-10-17

Part 5 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Fields, buttons, dialogs and status", is done when "the Desktop journey, in
the physical viewer, renames a file in File Explorer through a semantic
field, answers a dialog with a semantic button and shows a notice with its
meaning; while a prompt or a dialog is open, the rest of its application
stays rich and inactive beneath it; and Desk keeps running while a dialog
waits". The guarded launcher `local_testing/physical_desktop_acceptance.py`
ran Desk with only File Explorer, then the canonical Desktop journey, with
the native simulator. Both **passed**. Two earlier canonical runs failed and
led to the fixes recorded below.

This is functional regression evidence. The times are the simulator's, not
a device's. None of this is UART, panel or touch evidence.

## What the canonical journey now checks

The journey grew from 59 to 68 stages for this part.

- **Launcher (stage 12).** Desk's launcher is centred on the whole screen,
  so on the 3x2 Desktop it crosses the divider between File Explorer's tile
  and the Agent's tile beneath it. It must go out in the shell's frame: one
  Applets dialog around its list, modal over the whole screen, with the
  dialog and list active and the taskbar and every applet's controls
  inactive beneath it. Before this part's fix that frame fell back without
  the shell, because the planner refused any pane content over another
  pane's chrome.
- **Sound Lab's exact-value prompt (stages 22 to 27).** Activating Sound
  Lab's Frequency field opens its prompt over Sound Lab's status row,
  holding the value the field shows: a TEXT field in a modal region, with
  Sound Lab's menu bar and all four setting fields rich and inactive
  beneath it and every other applet active. Ctrl+A selects the value, 880
  is typed over it and Enter sets it. The new setting withdraws Sound Lab's
  readouts and meters, which describe its last render, until F5 renders it
  again; the journey waits for the whole instrument family to return.
- **Rename, notice and question (stages 31 to 40).** File Explorer's rename
  prompt renames `large.txt` to `notes.txt`. The renamed file stays
  selected and File Explorer's notice, `Renamed`, must be neutral and show
  in CELL on its row. Delete asks File Explorer's confirm question, with
  Delete destructive and Cancel the default cancel button, File Explorer
  rich and inactive beneath it and every other applet active. Alt+1 gives
  Pad focus while the question waits, the question still open and holding
  File Explorer alone; Alt+2 brings File Explorer back, and the question's
  Cancel button answers it. The file must still be listed and selected,
  and Pad then opens it.

File Explorer's own journey completes its rename too, and the Agent's
scrolls its approval review with the wheel; both passed in the physical
viewer earlier on 2026-10-17.

## Bindings

Both source trees were clean at launch and unchanged at exit in every run.

| Run | Akashic | MegaPad |
| --- | --- | --- |
| Canonical, first | `7250807a` | `4b7be457` |
| Canonical, second | `d44e122f` | `4b7be457` |
| File Explorer and canonical, closing | `484ac1aa7184be3fd62fd19bf1c5ad45839b1160` (tree `ceebaed2a7cee72038542c94353ffc2665f8280f`) | `4b7be4574a13f2c63c806e47c9ec67c532d5062c` (tree `f1182282803a20e0cad5977e7625b3228f79b449`) |

| Binding | Value |
| --- | --- |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Launcher SHA-256 | `e5f1b34addac6c8d4556a2cf938bc93f536802750933197424b011a4a75ac316` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The settings are the earlier parts': `desktop-apt1` and `desktop-apt1-fexp`
in ordinary source mode, simulator backend with the native executor,
280x84, 18 px font, 0.75 s action delay, 10 s hold, 900 s watchdog and
3.5 GiB aggregate-RSS stop. No compiled Forth cache, step-limit change or
timing change was used.

## Runs

| Run | Result | Time | Peak aggregate RSS |
| --- | --- | ---: | ---: |
| Canonical, first | failed at stage 26 | 78 s | 550 MiB |
| Canonical, second | stopped at stage 35 by the watchdog | 900 s | 534 MiB |
| Canonical, diagnostic (`akashic_tui.py accept`, 300 s timeout, `ef38c9a0`) | passed | 264 s | 561 MiB |
| Desk with File Explorer, closing | **passed** | 146 s | 521 MiB |
| Canonical, closing | **passed**, all 68 stages | 259 s | 551 MiB |

**First run.** After the new frequency was entered, the frame carried Sound
Lab's three status lamps but none of its eight readouts and two meters, and
the journey requires all of them from Sound Lab's launch on. That is Sound
Lab working as designed: a changed setting makes its last render stale, and
it withdraws the analysis that described it. The journey now presses F5 and
waits for the instruments to return (`d44e122f`).

**Second run.** After Enter on the rename, the renamed file was listed and
selected but no frame ever carried File Explorer's notice, and the screen
never changed again, so the journey waited until the outer watchdog stopped
it at 900 s. A watchdog stop writes no failure frame, and the canonical
journey did not yet say what it waited for; it does now (`ef38c9a0`).

The cause was the app shell's notice timing. It set a notice's deadline
when the notice was raised, and a paint showed the notice only while that
deadline had not passed. File Explorer raises `Renamed` for 1.4 s after the
rename's file work, and on the busy 3x2 Desktop the next paint can come
later than that. In the diagnostic run, which passed, the frame with the
notice came 1.9 s after Enter. In the second run, the first changed frame
came 3.5 s after Enter and carried no notice, and the notice's expiry then
changed nothing on screen, so no frame followed. A device whose paint is
slow would lose notices the same way. A notice now counts its time from the
first paint that shows it (`bfa6b307`). In the closing run the notice's
frame came about 4 s after Enter and carried the notice.

**Closing runs.** Desk with File Explorer passed its whole journey,
including its launcher under the shared modal-scope check, its rename and
notice, its delete question and its Go to warning. The canonical journey
passed all 68 stages. Times into the run, from launch:

| Milestone | Time |
| --- | ---: |
| Launcher open, modal over the whole screen | 37.0 s |
| Sound Lab's prompt open | 62.1 s |
| Sound Lab's frequency set | 69.8 s |
| Sound Lab rendered again | 72.5 s |
| File Explorer's notice `Renamed` shown | 98.4 s |
| File Explorer's delete question shown | 104.9 s |
| Pad focused while the question waits | 107.2 s |
| File Explorer back, question still open | 109.4 s |
| Question cancelled by its button | 111.7 s |
| Pad opened the renamed file | 115.4 s |

## Faults found

- The shell planner refused an overlay pane over another pane's chrome,
  so Desk's screens fell back without the shell wherever they crossed a
  tile divider. Fixed by `89ff57e1`, which also plans an overlay pane's own
  glyphs without the panes' chrome claims, so its glyphs cover the divider.
- The app shell timed a notice from when it was raised, so a late paint
  could show no notice at all. Fixed by `bfa6b307`.
