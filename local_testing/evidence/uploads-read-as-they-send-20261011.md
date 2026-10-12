# Uploads that read as they send — 2026-10-11

Part 11 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md)
made a picture's upload read its bytes a chunk at a time, as the terminal
takes them, and made a picture the terminal refuses stay refused until its
widget is given another source. This records the photo check, the new
damaged-picture check, File Explorer's check and the full Desktop journey
after it, against part 10's runs in
[screen-changes-20261011.md](screen-changes-20261011.md).

Every run used the native simulator, one at a time, under the 900-second
watchdog and the 3.5 GiB aggregate-RSS stop. Guest steps are the simulator's
semantic steps; an accelerated word counts as one. The times are the
simulator's, not a device's, and none of this is UART, panel or touch
evidence.

## Bindings

Every run bound clean source trees, unchanged at exit.

| Binding | Photo and File Explorer's checks | Damaged-picture check and the Desktop journey |
| --- | --- | --- |
| Akashic | `5025559bbf76c6cb0e5088b7cb9a10ae5524bd86` (tree `82e5af1bbcfb0e5a57e1fd1557ae30879878eca6`) | `760235f336d69ea612fc8398478a00bfa71152c9` (tree `4f7922e8827253946759039282ba273b7eff4c1a`) |
| MegaPad | `1e87765e0835f1eb18f0322a7d4d43bf401a9314` (tree `5d226f5c461fd9c62a5f910968251f859e900f6e`) | the same |
| Native extension SHA-256 | `5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6` | the same |
| Launcher SHA-256 | `e5f1b34addac6c8d4556a2cf938bc93f536802750933197424b011a4a75ac316` | the same |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` | the same |

The two Akashic commits differ only in the physical runner's failure
diagnostics, which no passing run reads: the guest's sources are the same.
MegaPad is part 10's; part 11 changed none of it.

## Done

- **An upload holds at most one chunk of its picture in the guest's
  memory.** The photo's 8,144,442-byte file went as a BEGIN, nine chunks and
  a COMMIT, each chunk read from the file into one 917,576-byte block when
  the terminal was ready for it. Before part 11 the lane read the whole file
  into an 8,144,442-byte staging block first.
- **The photo's Preview showed the photograph after 88,543,269 guest
  steps,** within the 90 million part 11 allows and 0.1% above part 10's
  88,448,039.
- **A picture the terminal refuses is sent once and shows CELL with the
  reason.** In the damaged-picture check, the terminal took damaged.png as
  one upload and refused it, CELL said "The picture is damaged", and the
  Details tab and the Preview again sent nothing more. The producer tests
  show the other pictures staying rich.

## The photo check

`local_testing/physical_desktop_acceptance.py --applet photo --screen-profile`:

| | Part 10 | Part 11 |
| --- | ---: | ---: |
| Result | passed, 49.3 s | passed, 53.5 s |
| Peak aggregate RSS | 533 MB | 527 MB |
| Guest steps, Preview tab to photograph | 88,448,039 | 88,543,269 |
| The same span on the simulator | 4.62 s | 4.91 s |
| The upload's frames | BEGIN, 9 chunks, COMMIT | BEGIN, 9 chunks, COMMIT |
| The most of the file the guest held at once | 8,144,442 bytes | 917,576 bytes |

The chunk frames carried 8,145,090 bytes: the file's 8,144,442 and 72 bytes
of framing each. A chunk is the terminal's limit, 917,576 bytes on the
Desktop, the frame payload less the chunk's 32-byte prefix; the last carried
the remaining 803,834.

The transactions after part 11:

| After activation | CELL | Retained | Bytes | Guest steps before it |
| ---: | --- | --- | ---: | ---: |
| 0.51 s | none | full replacement starts, 208 operations | 41,790 | 44,040,476 |
| 0.63 s | delta, 15,224 cells in 80 spans | replacement continues | 126,168 | 5,177,375 |
| 4.61 s | none | full replacement starts, 131 operations | 17,339 | 28,508,339 |
| 4.69 s | none | replacement continues | 160 | 7,929,895 |

They are part 10's four, the same sizes; only the guest steps between them
moved. Reading the chunks costs little. The profile charges the lane's
chunk feeding, with everything it calls, about 0.6 million of the 88.5
million steps, and the file reads about 0.13 million; it samples once each
65,536-step quantum, so these are rounded to that.

## The damaged picture

`--applet damaged`: Desk with File Explorer and damaged.png, a PNG whose
header names a 64 by 48 picture and whose image data is no deflate stream.
The guest reads what the file says it is; the terminal, decoding it at
COMMIT, refuses it with RET_BAD_CONTENT. The check **passed** in 50.4 s with
a peak aggregate RSS of 489 MB.

The terminal's upload frames, counted from just before the Preview first
showed:

| | Preview shown, picture refused | Details tab, then the Preview again |
| --- | ---: | ---: |
| RESOURCE_BEGIN | 1 | 1 |
| RESOURCE_CHUNK | 1 | 1 |
| RESOURCE_COMMIT | 1 | 1 |
| RESOURCE_ABORT | 0 | 0 |

Both times CELL said "damaged.png" over "The picture is damaged" in the
Preview, and no picture showed rich.

The check's first run failed, and found a defect now fixed. Once the
terminal refused the file, Desk threw -3203, an INVALID screen step.
`RTAPT-UPDATE-STATE@` reports the engine's last status beside its update
state, and the step that took the refused COMMIT had left that status at
REJECTED. The lane asks for the frame to be built again at once after a
refusal, so the producer prepared it in the same turn, found the engine
idle with a status that was not OK, and took it as INVALID. A job's outcome
is now only the job's: the step that reconciles a refused job frame reports
OK. While finding it, the runner's failure diagnostics were found to name
the screen publisher's fields one cell too early, also fixed.

## File Explorer's check

`--applet fexp` **passed** in 79.5 s with a peak aggregate RSS of 508 MB.
The sample picture went three times, once for each Preview of it the
journey opens, as one BEGIN, one chunk and a COMMIT each.

## The full Desktop journey

`local_testing/physical_desktop_acceptance.py --screen-profile`, the
canonical journey with Pad, Daybook, the launcher and Sound Lab, **passed**
in 231.3 s with a peak aggregate RSS of 538 MB, against part 10's 215.3 s
and 560 MB. Its sample picture went as one BEGIN, one chunk and a COMMIT.
Its only complete CELL snapshot was the session's first; across the journey
42,473 CELL cells were sent, against part 10's 42,548.

## On a device

The memory part 11 saves is the device's: Desk's memory source no longer
has to find a block the size of the largest picture file shown, only one
the size of the terminal's chunk. The guest steps are unchanged within the
run-to-run spread, so part 10's arithmetic stands: the photo's 88.5 million
steps would take 0.044 to 0.089 s on a 2 GHz chip at one to two clocks an
instruction, and about 3.3 s at the 100 MHz FPGA target.

## What remains

- Part 9's other two defects: a picture whose cells another root claims
  shows its label in CELL with nothing rich, and claims stay through a soft
  reset until the producer rebuilds.
- Part 8's two: the guest module's PT-CLOSE does not abort an open upload,
  and a frame that needs more room during an upload records a terminal
  refusal.
- A picture inside a larger file, such as a PDF's: the PDF part brings a
  source for a span of another source.
- `RTE-RESOURCE-FEED` checks the whole engine each chunk, about 36,000
  steps; the photo's nine chunks spend about a third of a million.
- Smaller copies of large picture files for small previews.
