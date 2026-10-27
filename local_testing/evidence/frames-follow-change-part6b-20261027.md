# Part 6b: A document handed to Pad opens before Desk paints — 2026-10-27

Part 6b of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
removes a frame Desk built and sent but never showed. When Daybook or File
Explorer hands Pad a document, Desk's intent route runs inside the sender's
input handling: it focuses Pad at once and queues the request on Desk's
bus. Until this part only Desk's tick pumped the bus, so the input's own
pass usually painted Pad focused with its old document and sent that as a
START, which the next draw overtook before the terminal revealed it. Part 5
traced it, and part 6's runs measured it at 121,952 bytes at Daybook's
handoff and 166,198 at File Explorer's.

Desk's per-pass service now pumps the bus as well (411a8d67). The app shell
runs the service after input and posted actions and before the tick and
the paint, so the request reaches Pad's handler in the input's pass, and
that pass paints Pad with the document open. The tick still pumps the bus
for the requests its own work queues.

This note records the change, its test, and the physical runs that compare
it with part 6's end. All of it is simulator evidence. None of it is UART,
panel or touch evidence. Steps are the simulator's semantic steps.

## The test

`test_desk.py` checks that Desk's service delivers a queued request: one no
capability takes, which the pump completes through the request's
completion word, and that the service reports work then and no work on an
empty bus. With the pump taken out of the service, the check fails. The
service reports work only for requests the pump took from the ring; a
request its handler defers stays out of the ring, so it cannot keep the
shell from sleeping. The selected tests passed, 477 in 11 files run in one
sequential process: the packaging, inventory and functional ledger tests,
both Desk suites, the shared document, wiring structure, applet journey and
desktop acceptance tests, and the retained-architecture checks. Not run:
the emulator tests the selection named, test_applet_close.py,
test_desk_host_characterization.py and test_desk_library_burrow.py.

## Bindings

Every run bound clean trees: Akashic 411a8d67 (tree
`6bd66d7ac54bd6835b8de090912102f5eb9c2d87`) and MegaPad 1833d16f (tree
`ed0550c17cb3f029838036cf95b980dcf4f92365`), with the native extension,
font and Desktop launcher of part 6's runs (SHA-256 `70f973571d88a580584ff748ded12d5bfb57d1eca00443a063d6650056220caa`,
`b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` and
`3a037906ed72cfa5ff7014d5328b184405b748c7db5066347f488bbe3bdace64`). Part
6's profiled journey, the starting point, ran at b330a58e (tree
`b8b1d957124149783f014538d2692917bc05c5a6`). This note is committed after
them.

## The canonical Desktop journey

Across Desk, Pad, Daybook, Sound Lab and File Explorer, at 411a8d67, one
run at a time under the 900-second watchdog and the 3.5 GiB aggregate-RSS
stop, with the presents it committed:

| Run | Time | Comparisons | DELTAs | STARTs | Continuations |
| --- | ---: | ---: | ---: | ---: | ---: |
| with the shadow check | 194.8 s | 4,621 | 52 | 37 | 36 |
| without it | 184.2 s | — | 52 | 37 | 36 |
| without it, with `--screen-profile` and `PYTHONHASHSEED=0` | 177.7 s | — | 52 | 37 | 36 |

Every run passed, the shadow check found no difference and skipped no
comparison, and each run committed one empty present and the same DELTA
refusals as part 6's runs. Part 6's three runs each committed 39 STARTs,
and part 5's 37 to 39 as the timing fell. All three runs here committed 37,
with the shadow check, without it and profiled. The shadow run made 4,621
comparisons, the count of part 5's shadow run whose timing left both STARTs
out: the same two frames go unbuilt. The journey's checks of Pad's new tab
and its text passed in every run.

The profiled run was made as part 6's was, with 100 call chains of 16
words kept an interval, and compared with it input window by input window.
Of the 79 windows, 77 committed the same presents, mode, bytes and cells
alike. The other two are the handoffs. Times are after the input:

| Handoff | Part 6 | Part 6b |
| --- | --- | --- |
| Stage 10, Daybook to Pad | START 121,952 bytes at 0.32 s, never shown; START 122,530 bytes at 1.08 s; its CONTINUE, 233 cells, at 1.40 s; 94.5 million steps | START 122,530 bytes at 0.39 s; its CONTINUE, 233 cells, at 0.76 s; 50.8 million steps |
| Stage 40, File Explorer to Pad | START 166,198 bytes at 0.49 s, never shown; START 169,723 bytes at 1.50 s; its CONTINUE, 1,755 cells, at 1.94 s; 126.5 million steps | START 169,723 bytes at 0.64 s; its CONTINUE, 1,755 cells, at 1.08 s; 72.6 million steps |

Each handoff now shows the same frame, to the byte, and it is on screen
0.64 and 0.86 seconds sooner. In the profile's 100-millisecond interval
after the key at stage 10, Desk's service pumped the bus, 0.33 million
steps, Pad's open handler among them, and the paint began; the one START
that pass sent shows Pad with the document. In part 6's run the handler ran
in Desk's tick, 0.64 seconds after the key. The two windows took 43.7 and
53.9 million guest steps fewer, and the journey sent 288,150 bytes fewer,
6,373,112 in all against 6,661,262: the two STARTs that were never shown.

## Desk with the applets that use the bus

Desk with each applet that uses the bus or takes a handoff, with the
shadow check and an unpinned hash seed, as in part 6's runs. Every run
passed, and the shadow check found no difference and skipped no
comparison. Comparisons and the presents committed, as DELTAs, STARTs,
continuations and empty presents:

| Applet | Part 6 | Part 6b |
| --- | --- | --- |
| Daybook | 427; 9, 8, 8, 1 | 427; 9, 8, 8, 1 |
| Agent | 905; 15, 22, 15, 1 | 905; 15, 21, 14, 1 |
| File Explorer | 1,609; 18, 55, 45, 1 | 1,609; 18, 55, 45, 1 |
| Pad | 437; 10, 6, 6, 1 | 437; 10, 6, 6, 1 |

Daybook, File Explorer and Pad committed the same frames. The Agent's
counts vary between runs of the same code, as parts 5 and 6 found; this
run's are one of part 5's.

## Files

The runs' output stayed in `/dev/shm` and was deleted once its numbers were
read, with part 6's profiled journey. By their shells' `write_bytes`, none
of the seven runs wrote to the drive.
