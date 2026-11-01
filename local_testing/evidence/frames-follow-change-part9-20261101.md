# Part 9: one projection, two drivers — 2026-11-01

Part 9 of [FRAMES-FOLLOW-CHANGE](../../docs/rich-terminal/FRAMES-FOLLOW-CHANGE.md)
makes a frame's work follow what changed. Beside the full driver, which
lowers, packs and compares every document's capture and remains the one
full path, a change driver lowers again only the roots whose facts moved,
takes the rest from the bank on screen, and compares only what it lowered.
This note records the part's result, its end-of-part checks, a gap in the
Agent's change counting that those checks found and d1db8bc9 closes, and
what stays open. Each slice's design and results are in the plan's Done
notes; 9a.1, 9b.1 and 9b.2 also have notes of their own. All of it is
simulator evidence. None of it is UART, panel or touch evidence. Steps are
the simulator's semantic steps.

## The result

Part 9's baseline, the typing run at 4f4c935a, built a burst frame of
typed letters in 9.63 million steps and sent its burst as 18 DELTAs of
13,158 bytes. At d1db8bc9 the same run builds a burst frame in 2.05
million steps and sends the same 18 DELTAs and bytes: the documents'
snapshot takes 0.66 million, the producer's candidate 0.45 million, of
which 0.19 million is the candidate from the bank on screen, the copy of
the bank on screen 0.23 million, and Desk's shell batch 0.41 million. The
profile records one call chain every 65,536 steps, so a burst frame's
figure carries about four percent; on 7563cde6 the same run measured 2.02
million.

The canonical journey, which at 9a.1 committed 49 DELTAs, 37 STARTs, 36
CONTINUEs and one NONE, now commits 61 DELTAs, 25 STARTs, 25 CONTINUEs and
one NONE, and sends 4,785,556 bytes where 9b.2's run sent 6,594,384. RUHA
no longer carves 20.0 million bytes when Desk loads; its block starts at
114,240 bytes and grew to 702,632 in the journey at 9a.4. The shadow check
compares every shortcut the change driver takes with what the full driver
would build, and in the journey it made 30,483 comparisons without a
difference.

## The Agent's transcript

Desk holding the Agent, with the shadow check on, failed at 7563cde6, the
last slice's commit: 23 differences in 2,257 comparisons, the first at the
unpack stage in draw 14, where the candidate from the bank on screen held
other bytes for the screen's item 0 than a full lowering. The nine other
applications passed. Run at twelve commits back to 9a.3b's end, the
failure starts at 0384f5e7, the commit of 9c.2b that lets fields and
dialogs come and go in a DELTA, and its parent 52e39747 passes.

Two throwaway diagnostics, applied in the RAM clone only, recorded the
first unpack difference. In draw 14 no root's facts had moved, so the
candidate took the whole frame from the bank, yet the screen's collection
text was 6,257 bytes in the bank and 6,268 in the full lowering, with as
many collections and items. The text first differed in a card's length:
"Connected through Akashic's provider-neutral runtime. " is 54 bytes in the
bank and 65 in the full lowering, which holds the next delta, "You asked: ",
as well; the Agent's journey runs on the device-flow fixture, whose replies
come from the scripted provider (`providers/devtools/scripted.f`).

The transcript is a canonical card list whose callbacks read the
conversation the Agent shows, so the list learns that a card changed only
when the Agent tells it. The Agent told it of another conversation shown,
through LST-ROWS!, and of cards added or dropped, through LST-RECOUNT in its
panel's draw, which does nothing while the count of cards stays the same. A
reply streaming into its message, and a message's state in its card's
header, change a card in place, so the list's revision, which the
transcript's root facts read (`tui/uidl-root-facts.f`), stood still while
the card changed. The gap is older than 0384f5e7, since the list never
counted a card changed in place; how 9c.2b brought these frames to the
candidate, which a full lowering built before, was not traced. d1db8bc9's
message dates the candidate's trust in unmoved facts to 0384f5e7, which is
imprecise: the candidate has taken roots whose facts did not move since
9a.3b.3b.

d1db8bc9 has the panel's draw follow the conversation shown
(`_AG-LIST-FOLLOW`): it keeps the conversation the list's rows came from and
that conversation's revision then, and when either differs it tells the
list, with LST-RECOUNT when the count of cards changed and otherwise with
LST-REFRESH, the list's word for rows changed in place. By a reading of its
code, the runtime moves a conversation's revision within each operation that
changes it: each event it handles moves it after the handling, and the
resolution of a review appends its audit record first, so a state set later
in the same operation is covered. A widget changed while UIDL paints asks
for no paint pass of its own (`UTUI-PAINTING`), so following in the draw
sends no extra frame.

## Tests

`test_agent_transcript_follows.py`, new with d1db8bc9, runs the Agent's
own words in the native simulator on a state block, an instance and a
runtime record of its own. Each delta of the journey's reply, and the
reply's completion, move the list's revision with the count of cards
unchanged; a card added at the end moves it as before; the same
conversation drawn again moves nothing; and a conversation replaced by
another at the same revision moves it. On the code before d1db8bc9, the two
deltas and the completion moved nothing, and neither did the replacement.
`test_agent_overlays.py`, `test_uidl_retained_architecture.py`,
`test_akashic_tui_packaging.py` and the refactor ratchet passed with it,
one file per process.

The end of part's selection was the rich-terminal set and every test file
that reads a file part 9 changed, the new test among them: 176 files, run
one file at a time with `TMPDIR` in `/dev/shm`, the largest process
peaking at 1.36 GiB. 4,829 tests passed in 161 files, and none failed or
was skipped. The other 15 are standalone drivers, from which pytest
collects nothing: `test_applet_close.py`, `test_applet_host.py`,
`test_at_authenticated_provider_vertical.py`,
`test_at_bidirectional_vertical.py`, `test_at_xrpc_feed_vertical.py`,
`test_desk_host_characterization.py`, `test_explorer_transactions.py`,
`test_library_capability_boundaries_l1.py`,
`test_library_capability_create_boundary_l1.py`,
`test_library_capability_l1.py`, `test_library_ui_l1.py`,
`test_observatory_worlds_slice.py`, `test_streams_authenticated_applet.py`,
`test_streams_burrow_lifecycle.py` and
`test_streams_library_rabbit_provider_load.py`. They were not run.

Not run: emulator smokes, `test_l7_agent_actions.py` among them, which
builds an image of the Agent's provider commands;
`test_streams_sr3_composed.py`, which spawns a worker and runs only when
asked for; and `test_vfs_ext4.py`, which needs the host's ext4 tools and
was checked when main was merged in (da622de5).

## Physical runs

Every run went through `physical_typing_cadence.py` or
`physical_desktop_acceptance.py`, one at a time, from a RAM clone, with
MegaPad at 1833d16f and output in `/dev/shm`. Desk with each of nine
applications ran at 7563cde6; d1db8bc9 changes only the Agent's panel,
which Desk holding another application never draws. Desk with the Agent,
the typing runs and the three canonical journeys ran at d1db8bc9, since
the canonical Desktop, which the typing runs also use, shows an Agent
tile.

Each run with the shadow check passed with no difference and nothing
skipped.

| Run | Commit | Seconds | Comparisons | Judged | Roots | Changed | Items | Presents D/S/C/N | Bytes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| Typing | d1db8bc9 | 15.8 | 7,339 | 17 | 544 | 36 | 36 | 18 DELTAs | 13,158 |
| Pad | 7563cde6 | 43.2 | 1,956 | 14 | 129 | 33 | 34 | 12/3/3/1 | 617,805 |
| File Explorer | 7563cde6 | 122.5 | 4,248 | 48 | 292 | 98 | 66 | 28/41/36/1 | 3,908,964 |
| Daybook | 7563cde6 | 136.6 | 1,498 | 13 | 68 | 25 | 23 | 11/4/4/1 | 626,147 |
| Streams | 7563cde6 | 98.5 | 503 | 5 | 29 | 9 | 8 | 3/6/6/1 | 575,197 |
| Agent | d1db8bc9 | 64.2 | 2,408 | 24 | 209 | 45 | 34 | 20/11/11/1 | 1,590,417 |
| Sound Lab | 7563cde6 | 28.0 | 394 | 4 | 39 | 16 | 6 | 3/3/3/1 | 663,613 |
| Observatory | 7563cde6 | 34.8 | 363 | 4 | 48 | 7 | 2 | 0/8/8/1 | 819,455 |
| Small Terminal | 7563cde6 | 29.2 | 252 | 3 | 29 | 8 | 1 | 1/4/4/3 | 692,239 |
| Photo | 7563cde6 | 28.1 | 133 | 2 | 11 | 6 | 3 | 1/3/3/1 | 8,758,813 |
| Damaged | 7563cde6 | 26.8 | 539 | 6 | 32 | 10 | 9 | 5/2/2/1 | 890,294 |
| Canonical journey | d1db8bc9 | 194.8 | 30,483 | 65 | 2,554 | 132 | 122 | 61/25/25/1 | 4,785,556 |

Judged, roots, changed and items are the root facts' judge, as in part
9a.1; presents count DELTAs, STARTs, CONTINUEs and NONEs, and the typing
row's presents and bytes are its profiled burst's.

Against 9b.2's runs, every application sends as many DELTAs or more and as
many STARTs or fewer: Pad 12 DELTAs and 3 STARTs against 9 and 6, File
Explorer 28 and 41 against 16 and 52, the Agent 20 and 11 against 9 and
20, and the canonical journey 61 and 25 against 49 and 37. Observatory,
Small Terminal and Photo send the same presents. The Agent's run at
7563cde6, which failed, is described above.

Without the shadow check the canonical journey passed in 181.3 seconds and
sent the same presents, the same 4,785,556 bytes and the same refusal
counts as with it. In safe mode it passed in 276.1 seconds with 61 DELTAs,
26 STARTs, 24 CONTINUEs and one NONE, 4,903,187 bytes, and every check on;
the candidate from the bank on screen and the copy of it were refused
safe mode's reason in every frame they were asked, 87 and 67 times, so
safe mode took neither path. The profiled typing run passed in 16.3
seconds. Each run's shell reported a `write_bytes` of 0.

## Open

- The full lowering's menu reuse (`_RTHP-W-MENU-REUSE-COPY`) maps the
  bank's menu identities by place, from the bank's first object. A bank
  whose DELTA defined or dropped controls keeps the identities on screen
  until the next START (9c.2), so after a DELTA that defined or dropped
  menu controls the mapping would name other controls. By a reading of
  the code, the comparison's parent and index checks would then refuse the
  frame, which would go out as a START, and the shadow check's menus stage
  would report it; no run has reached it. It was found while building 9c.3b
  and is left open.
- `test_desk_library_burrow.py` is a script with no test functions, so
  pytest collects nothing from it. Its `--static-only` check fails at its
  pin of 24 candidates in Desk's agent capability catalog
  (`agent-cap-catalog.f`), which has held 26 since bd02c699 on 2026-10-09.
  This predates part 9 and is left for the product journey's next use.

## Files

The runs came from RAM clones of each commit, and their output stayed in
`/dev/shm` and was deleted once its numbers were read; each run's shell
reported a `write_bytes` of 0. The two diagnostics lived only in throwaway
commits of the RAM clone, never pushed.
