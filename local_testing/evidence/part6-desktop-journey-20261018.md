# Part 6 closing runs — 2026-10-18

Part 6 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Plots and waveforms", is done when "Observatory's plot of Worlds' telemetry
goes out as a `PLOT` over an exact series in the physical viewer, its
baseline a vector line; Sound Lab's frequency landmarks go out as vector
lines that move when it renders new settings; the same widget draws both in
CELL; the Desktop advertises `VECTOR` with a point budget its owner reserves
as it needs; and the full Desktop journey passes with the new milestones".
The guarded launcher `local_testing/physical_desktop_acceptance.py` ran Desk
with Observatory and Worlds, Desk with Sound Lab, Desk with File Explorer
and then the canonical Desktop journey, with the native simulator. All four
**passed** in their closing runs. The earlier runs found the faults below;
two defects found on the way stay open.

This is functional regression evidence. The times are the simulator's, not
a device's. None of this is UART, panel or touch evidence. What the frames
cost is in [part6-plot-line-costs-20261018.md](part6-plot-line-costs-20261018.md).

## What the journeys check

- **Desk with Observatory and Worlds** (`--applet observatory`, a new
  profile). Observatory's starting plot must go out as a `PLOT` over a
  series holding exactly its eight samples, with its baseline a `POLYLINE`
  along the row below, and CELL must show the plot's caption. Alt+2 focuses
  Worlds, S steps its run three times, counted only as each press arrives,
  and A hands the run over; Desk brings Observatory forward. The plot's
  series must then hold exactly Worlds' four samples, one a step and the
  starting one, the same samples Observatory's table lists, and in that
  same frame Observatory's status must say `Profiled 4 samples`. R profiles
  the series again and the plot must stay.
- **Desk with Sound Lab** (`--applet soundlab`, a new profile). A render
  must show the frequency landmarks as three `POLYLINE`s: a line across one
  row from 0 Hz to 4 kHz and a mark at the pitch and at the centroid Sound
  Lab reports. CELL must draw the same line, its caption and the letters
  for the marks. The frequency is set to 880 Hz through its field's prompt
  and F5 renders again; the pitch mark must move along the same line, in
  the rich frame and in CELL.
- **Canonical Desktop.** At Sound Lab's `soundlab-instruments-live`
  milestone the frame must carry its three landmark lines, and at
  `soundlab-rerendered` the new render must have moved the pitch mark along
  the same line. The press that follows on File Explorer's task now waits
  for Sound Lab's notice to end, for the reason under the canonical runs.

## Bindings

The closing runs bound clean source trees, unchanged at exit. Runs the
tables mark as uncommitted or diagnostic did not.

| Run | Akashic | MegaPad |
| --- | --- | --- |
| Observatory and Sound Lab, closing | `cfee9c9df404ca40f238172d22c0df570764b9ec` (tree `ce08720dbeeccc5a2f3bb92fdac5e52fc6615fe6`) | `23097286c327d910cd0e7f69c54d06a1cc3f6d85` (tree `ae5e8dff3be073d4113008800f66548efac7168f`) |
| File Explorer and canonical, closing | `3e43d9d0ab606ab940999b319e56ce14d2d91860` (tree `4d95f51da2016753217c795f559e92a3a9ef5646`) | `23097286c327d910cd0e7f69c54d06a1cc3f6d85` (tree `ae5e8dff3be073d4113008800f66548efac7168f`) |

| Binding | Value |
| --- | --- |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Launcher SHA-256 | `af7efa48169f57cc3eeaa757411246ef68dea5b7223c9e38007a5ad67a56ffd2` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The settings are the earlier parts': ordinary source mode, simulator
backend with the native executor, 280x84, 18 px font, 0.75 s action delay,
10 s hold, 900 s watchdog and 3.5 GiB aggregate-RSS stop; a single applet's
journey has its own 300 s timeout. No compiled Forth cache, step-limit
change or timing change was used.

## Desk with Sound Lab

| Run | Result | Time | Peak aggregate RSS |
| --- | --- | ---: | ---: |
| First, `ba0fed35` | failed: CELL lacks the landmark caption | 12 s | 411 MiB |
| Two diagnostic runs | failed the same way | 11 to 12 s | 410 to 422 MiB |
| With the caption fix, uncommitted | passed | 33 s | 509 MiB |
| Closing, with the screen profile | **passed** | 31.5 s | 507 MiB |

Sound Lab painted its caption, `Frequency landmarks: 0 Hz`, and then its
`4 kHz` label, right-aligned in a field across the same row. A right-aligned
label blanks its whole field first, so it wiped the caption in CELL. The
label is now painted first (`692c9e5d`).

## Desk with Observatory and Worlds

| Run | Result | Time | Peak aggregate RSS |
| --- | --- | ---: | ---: |
| First, `692c9e5d` | stopped by its timeout at stage 0 | 304 s | 466 MiB |
| Second, journey fixes uncommitted | failed: `Worlds lost focus` | 25 s | 507 MiB |
| Third to sixth, two with diagnostic changes | stopped by the timeout at stage 3 | 304 to 305 s | 507 to 528 MiB |
| Seventh, `636cd60f` | passed, with the two faults below | 35 s | 508 MiB |
| Eighth, `fe0554ad` with a CELL dump | passed; the dump showed a stale CELL panel | 38 s | 527 MiB |
| Closing, `cfee9c9d`, with the screen profile | **passed** | 39.2 s | 505 MiB |

The first two runs found the journey wrong: Desk cuts a task's label to
ten characters, so Observatory's focused task reads `[1:Observator*]`, and
Desk brings Observatory forward when Analyze resolves to it (`636cd60f`).

The next four stopped while the journey waited for Observatory's plot of
Worlds' run. Worlds' toast said Observatory had refused the snapshot, and a
diagnostic build showed the request's status was `CBUS-S-NEEDS-APPROVAL`.
Worlds sent Analyze as a component, Observatory's capability declares
`MUTATE`, and the default policy holds a component's mutating request for
an approval Desk never asks for. Analyze has never worked inside Desk:
neither application was in a Desk profile before. Analyze is the user's own
press, so Worlds now sends it as the user, as Daybook does for a save
(`049ccb36`).

The seventh run passed, but its record showed two faults. Its three Worlds
steps were two presses: one was refused for backpressure, then dropped for
a newer frame, while the journey had already counted it. The journey now
counts a step only when its press arrives and checks that Worlds hands over
one sample a step plus its starting one (`fe0554ad`). And the frame where
the plot first held Worlds' run showed Observatory's old readouts printed
under the new ones, and its old eight-mark CELL plot under the new rich
line. A CELL dump in the eighth run confirmed that Observatory's whole CELL
panel kept the starting series until R. Desk swaps each application's UIDL
state in and out, and Observatory's capability handler, which runs from
Desk's request pump, wrote its status label and repaint mark into whichever
application's state was live. Observatory now marks its view stale there
and shows it from its own tick (`cfee9c9d`), and the journey requires the
status to name the run in the frame whose plot first holds it.

## Canonical Desktop

| Run | Result | Time | Peak aggregate RSS |
| --- | --- | ---: | ---: |
| First, `cfee9c9d` | stopped at stage 28 by the watchdog | 900 s | 550 MiB |
| Diagnostic 1 (`akashic_tui.py accept`, 300 s timeout, `cfee9c9d`) | passed | 276 s | 562 MiB |
| Diagnostic 2 (600 s timeout, `cfee9c9d`) | passed | 266 s | 551 MiB |
| Second, `c24b46fb` | stopped at stage 35 by the watchdog | 900 s | 535 MiB |
| Diagnostic 3 (600 s timeout, `c24b46fb`) | stopped at stage 35 by its timeout | 605 s | 551 MiB |
| Diagnostic 4, with the screen profile | stopped at stage 35 by its timeout | 605 s | 534 MiB |
| Desk with File Explorer, `3e43d9d0` | passed | 169 s | 524 MiB |
| Closing, `3e43d9d0` | **passed**, all 68 stages | 307 s | 568 MiB |

**First run.** The journey pressed File Explorer's task as Sound Lab's
render notice still showed. The terminal took the press, but the guest
read it only after it had sent the frame that ends the notice, a START
that gives every control a new identity. The press named a control that
frame no longer had, so the guest dropped it without a word; File Explorer
never took focus, and the journey waited at stage 28 until the watchdog
stopped it. The two diagnostic runs passed: there the terminal refused the
press for backpressure while the notice showed and took it on the frame
where the notice had ended. The journey now waits for the notice to end
before it presses (`c24b46fb`). The dropped press stays open.

**Second run and diagnostics 3 and 4.** From then on the journey stalled
every time at stage 35: File Explorer renamed the file, but no revealed
frame ever carried its 1.4-second "Renamed" notice. While the third
diagnostic stalled, its guest state was read through the session socket:
idle, with no failure. The fourth, with the screen profile, showed the
cause. The paint that first drew the
notice started its clock. The START carrying it took about 0.7 s to build
and the terminal took it about 0.65 s later, just after the notice had
ended. The screen no longer matched the START, so the producer rightly did
not reveal it and built another, without the notice. A notice's time now
starts when the output that shows it has gone out, which for a rich
terminal is when the frame carrying it is revealed (`210f1d4e`).

**Closing runs.** Desk with File Explorer passed its whole journey,
including its rename notice, under the new notice timing. The canonical
journey passed all 68 stages. Times into the run, from launch:

| Milestone | Time |
| --- | ---: |
| Launcher open, modal over the whole screen | 44.8 s |
| Sound Lab's instruments live, with its three landmark lines | 52.5 s |
| Sound Lab rendered again, its pitch mark moved | 89.4 s |
| File Explorer's notice `Renamed` shown | 113.3 s |

## Observed, not changed

Where a rich `PLOT` or `WAVEFORM` leaves its background clear, the
compositor shows the CELL drawing of the same instrument beneath it: CELL's
stepped line and marks under Observatory's plot, and CELL's waveform under
Sound Lab's, as since the series work. The rich drawing is complete on its
own; whether the renderer should cover an instrument's cells is a question
for the compositor, not for part 6.

## Faults found

- Sound Lab's right-aligned `4 kHz` label wiped its landmark caption in
  CELL. Fixed by `692c9e5d`.
- Worlds' Analyze was held for an approval Desk never asks for. Fixed by
  `049ccb36`.
- Observatory's capability handler wrote its UIDL elements under another
  application's context, so its CELL panel and status kept the old series.
  Fixed by `cfee9c9d`. Handlers in Daybook, File Explorer, Grid, Pad, Sound
  Lab and Streams do the same and stay open.
- A press the guest reads after a START it published for its own reasons
  names a control that frame no longer has, and the guest drops it without
  a word. Open; the canonical journey waits for Sound Lab's notice to end
  (`c24b46fb`).
- A notice's time started at the paint that drew it, so a rich frame slower
  than the notice could never reveal it. Its time now starts when the
  output that shows it has gone out (`210f1d4e`).
- Two journey faults: Observatory's focus label and Desk's focus move after
  Analyze (`636cd60f`), and a Worlds step counted before its press arrived
  (`fe0554ad`).
