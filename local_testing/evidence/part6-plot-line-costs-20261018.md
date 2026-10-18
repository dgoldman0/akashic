# Plots and lines: what they cost — 2026-10-18

Step 9 of part 6 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md)
measures the guest steps of frames that carry Observatory's plot and Sound
Lab's frequency landmarks, rich and CELL. This records two physical applet
checks with the screen profile: Desk with Observatory and Worlds, and Desk
with Sound Lab.

Both runs used the native simulator, one at a time, under the 900-second
watchdog and the 3.5 GiB aggregate-RSS stop, on a 280×84 screen. Guest steps
are the simulator's semantic steps; an accelerated word counts as one. None
of this is UART, panel or touch evidence.

## Bindings

Both runs bound clean source trees.

| Binding | Value |
| --- | --- |
| Akashic | `cfee9c9df404ca40f238172d22c0df570764b9ec` (tree `ce08720dbeeccc5a2f3bb92fdac5e52fc6615fe6`) |
| MegaPad | `23097286c327d910cd0e7f69c54d06a1cc3f6d85` (tree `ae5e8dff3be073d4113008800f66548efac7168f`) |
| Native extension SHA-256 | `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa` |
| Launcher SHA-256 | `af7efa48169f57cc3eeaa757411246ef68dea5b7223c9e38007a5ad67a56ffd2` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

| Check | Result | Wall time | Peak aggregate RSS |
| --- | --- | ---: | ---: |
| `physical_desktop_acceptance.py --applet observatory --screen-profile` | passed | 39.2 s | 505 MiB |
| `physical_desktop_acceptance.py --applet soundlab --screen-profile` | passed | 31.5 s | 507 MiB |

## How the steps are counted

As in part 5: for each interaction the window runs from its input to the
last PRESENT before the next input, and the idle time after that PRESENT is
left out. "Rich producer" is the steps under `RTHP-PREPARE` and `RTHP-STEP`,
with everything they call. "Outside it" is the rest: handling the input,
the applications' work and paint, Desk's paint and the CELL feed, which is
what a CELL session runs. The word profile samples once every 65,536 steps,
so a split is good to about that much a sample, and a word that runs for
less than that may not show at all.

A frame is a START (`REPLACE_START`, then a `REPLACE_CONTINUE` that reveals
it with the CELL cells that changed) or a DELTA. A START defines every
region and object again.

## Observatory

Desk holds Observatory and Worlds side by side. Observatory first plots its
own series of eight samples. Worlds steps its run three times, Analyze hands
the run's four samples to Observatory, and R profiles them again.

| Interaction | Guest steps, rich | Rich producer | Outside it (CELL) | Frames | Bytes |
| --- | ---: | ---: | ---: | --- | ---: |
| First Worlds step (S) | 30,270,207 | 18,350,179 | 11,920,028 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 61,669 |
| Second Worlds step | 31,188,095 | 18,415,726 | 12,772,369 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 61,951 |
| Third Worlds step | 33,358,011 | 21,495,918 | 11,862,093 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 62,241 |
| Analyze (A): Observatory takes the run | 31,253,252 | 19,726,460 | 11,526,792 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 64,432 |
| Rerun (R): the plot stays | 28,894,342 | 21,495,916 | 7,398,426 | 1 REPLACE_START | 61,176 |
| Analyze's notice ends | 28,967,090 | 18,612,342 | 10,354,748 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 61,472 |

Each START holds 307 objects, or 310 while Analyze's notice shows. The
rerun's START is followed at once by the START that ends the notice, and
one REPLACE_CONTINUE reveals both.

## Sound Lab

Desk holds Sound Lab alone. Its journey opens the frequency field's prompt,
sets 880 Hz and renders again with F5, which moves the pitch landmark.

| Interaction | Guest steps, rich | Rich producer | Outside it (CELL) | Frames | Bytes |
| --- | ---: | ---: | ---: | --- | ---: |
| Frequency prompt opens | 44,491,771 | 22,282,363 | 22,209,408 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 83,147 |
| Enter: frequency set, analysis withdrawn | 35,913,990 | 16,580,707 | 19,333,283 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 79,831 |
| F5: rendered, landmarks moved | 49,611,078 | 16,515,180 | 33,095,898 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 111,586 |
| The render's notice ends | 24,867,649 | 14,680,160 | 10,187,489 | 1 REPLACE_START, 1 REPLACE_CONTINUE | 76,678 |

A changed setting withdraws the waveform, the readouts, the meters and the
landmark lines until the next render, so the Enter frame holds 154 objects
and only the three status lamps of the instrument family. The render's
frame holds 203.

## What the numbers say

- **The plots and lines themselves are cheap.** The instrument planner
  lowers every instrument of both applications, Observatory's plot and
  baseline among them, in about 0.2 to 0.3 million steps a frame, and Sound
  Lab's graph in about 0.07 to 0.13 million. Sending a PLOT, a POLYLINE or
  a series takes less than one profile sample each. In CELL, the widget
  draws Observatory's plot in about 0.13 million steps and its baseline in
  about 0.07 million, and Sound Lab's three landmark lines in about 0.33 to
  0.39 million. CELL draws them only when their panel repaints, so a Worlds
  step draws neither.
- **Every frame in both Desks is a START.** A Worlds step leaves
  Observatory unchanged, yet its frame defines all 307 objects again, about
  61 KB, and costs 18 to 21.5 million steps in the rich producer over its
  START and CONTINUE. Of the first step's START, 13 million steps, Desk's
  shell producer takes about 7.8 million. Why these frames are not
  DELTAs is not diagnosed; part 5 found the same for applications'
  prompts. The producer tests cover keeping an unchanged plot and line in a
  DELTA, but no frame here reaches that path. A moved landmark line needs a
  START in any case, since the provider does not replace a line in a DELTA.
- **Outside the producer, the applications' own work dominates.** A Worlds
  step costs about 12 million steps outside the producer, of which Worlds'
  repaint takes about 6.6 million. Sound Lab's F5 costs 33 million: its
  render, analysis and graph rebuild take about 10.6 million, and the
  widget's CELL waveform takes 3.8 to 4.4 million a repaint, about ten
  times its three lines.
