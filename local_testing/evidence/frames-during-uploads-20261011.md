# Frames during uploads — 2026-10-11

Part 8 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Frames during uploads", is done when "no frame waits for a whole upload: on
the physical viewer the screen keeps answering input while a picture uploads,
and the picture appears once its upload commits". The guarded launcher
`local_testing/physical_desktop_acceptance.py` ran Desk with only File
Explorer on a paced link to the hosted terminal, then the canonical journey on
an ordinary link, with the native simulator. Both **passed**. The first paced
run failed and led to a fix, recorded below.

This is functional regression evidence. The paced link is a test setting, not
a model of any particular link, and the times are the simulator's, not a
device's. None of this is UART, panel or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit in every run.
The launcher enforces both for the canonical journey and records them for the
single-applet runs.

| Run | Akashic | MegaPad |
| --- | --- | --- |
| Paced, first | `c3a38105da3033cbebfe6d49f5b8f925a9f54b44` (tree `1bdee718ebe7a48317b029b2088ef190762838e6`) | `5d61a17f7cd576ee290ce182ead6d69d2241051e` (tree `12a6e4905a580bf7eb2c00cc1c08f343f258d9a6`) |
| Paced, after the fix | `a26234b645b24eb2dbb3880fb483710b9c91adb5` (tree `8b8b62cf681a432b384153a2298d69d377e1d591`) | the same |
| Canonical | `02b6c6550750af10e9067aedda1b21191b7f6e25` (tree `103623d88642602bec9eabee5718b3aa39aee463`) | the same |

| Binding | Value |
| --- | --- |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` |
| Launcher SHA-256, paced runs | `ac02af60ee4f2adcf7bb971fddbeb8b65a5bfb7b1ed7e39e141e415927465739` |
| Launcher SHA-256, canonical | `b4d5c2323759b87369c82e13bd0d6150bfa2e197688378d8477123b71fd5657a` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The settings are part 7's: `desktop-apt1` and `desktop-apt1-fexp` in ordinary
source mode, simulator backend with the native executor, 280x84, 18 px font,
0.75 s action delay, 10 s hold, 900 s watchdog and 3.5 GiB aggregate-RSS
stop. No compiled Forth cache, step-limit change or timing change was used.

## Runs

| Run | Stages | Result | Wall time | Peak aggregate RSS |
| --- | ---: | --- | ---: | ---: |
| Desk with only File Explorer, paced `100000:1000`, Akashic `c3a38105` | 3 of 19 | fail | 56.2 s | 475 MB |
| The same, Akashic `a26234b6` | 19 | pass | 165.2 s | 482 MB |
| Canonical Desktop journey | 55 | pass | 295.5 s | 560 MB |

The canonical journey sent 1 upload, in one chunk, and 133 PRESENT
transactions among 12,358,496 bytes in 61,255 frames. Part 7's canonical run
sent 12,164,876 bytes in 61,157 frames.

## The paced link

`--terminal-link-pace 100000:1000` makes the hosted terminal take the guest's
bytes no faster than 100,000 a second and advertise resource chunks of what
the link carries in one 1,000 µs frame time: 100 bytes. The sample picture's
64,000 bytes therefore go in 640 chunks, each answered by the CREDIT that
covers it.

With the link paced, File Explorer's journey adds a check to its first
preview. Once the terminal holds the upload open with some chunks taken, the
journey sends an EXPAND on the folder tree, which changes nothing the picture
depends on. The screen may not change while a picture uploads, so the runner
offers the journey the frame on screen after each status poll, and the input
is bound to it. The terminal's own counters, read from those polls:

| Moment | Chunks taken | Upload | PRESENTs committed |
| --- | ---: | --- | ---: |
| Input sent | 20 of 640 | open | 8 |
| Its answer presented, 2.3 s later | 124 | open | 9 |
| Picture shown | 640 | committed | 11 |

The frame answering the input was committed while the upload was open: 104
chunks went between the input and that frame, and 516 after it. The picture
then appeared once its upload committed. Across the run the terminal took 3
uploads in 1,920 chunks and 46 PRESENT transactions, 4,694,731 bytes in 8,930
frames.

## The first run's failure

The first paced run sent the probe input with 7 chunks taken. 0.38 s and 77
chunks later the guest closed its terminal session with the upload still
open, and the terminal failed the session. The frame answering the input
never began: the terminal had 8 PRESENT_BEGIN and 8 PRESENT_COMMIT both
before and after it.

The engine refused an update while one of the upload's frames awaited its
answer, or on the job's turn. The producer's DELTA path treats a refused
begin as a stale candidate, so it rebuilt the whole draw and tried a full
START, paths that had never run beside a job. The guest's failure record was
not saved, so this cause is inferred from the counters. Akashic `a26234b6`
changed two things:

- The engine's step that takes an update's answer sends a waiting upload's
  next frame at once. The step that takes one of the upload's own answers
  sends nothing, so the two alternate without hidden state.
- The producer prepares no frame while one of the upload's frames awaits its
  answer, which the facade's `RTE-JOB@` shows.

The runner now also saves the guest's own state when the backend fails.

## Findings

- Small chunks cost round trips, not bytes. The 640 chunks took about 8 s,
  while their bytes need about 1.1 s at the pace: each chunk waits for its
  CREDIT, and the guest sends the next on a later pass. A terminal sets its
  chunk size from its link and frame time; on a fast link with a 16 ms frame
  a chunk is far larger.
- With 100-byte chunks the 72-byte frame header adds 72% to a picture's
  bytes. At ordinary chunk sizes it is negligible.
- The guest's PT-CLOSE never sends RESOURCE_ABORT with reason 2 (local
  shutdown) for an open upload, so any teardown during an upload fails the
  session instead of closing it. It is a MegaPad guest-module defect older
  than part 8, left for its own fix.
- A frame that needs more room while an upload is open is refused the owner
  request. The draw keeps what does not fit as CELL, and the rebuild after
  the picture's commit asks again, but its recorded reason reads as a
  terminal refusal.

## Not covered

- Choosing chunk sizes from the device side, and drops and pixel questions
  beside an upload, which part 8 leaves out.
- Reset, resize, reconnect, UART, panel and touch remain open, as for every
  family.
