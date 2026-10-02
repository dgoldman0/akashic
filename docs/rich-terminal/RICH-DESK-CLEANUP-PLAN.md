# Rich Desk cleanup plan

Accepted 2026-09-30. Branch `feature/rich-desk-producers`, paired with MegaPad
`integration/unified-runtime-rich-desk`, whose own steps are in MegaPad
`docs/integration-cleanup-plan.md`. Neither branch merges into main or is
pushed until the final step passes; both repositories are then pushed
together, because this branch needs the paired MegaPad session modules.

## Why

The rich Desk producers arrived as 50 commits made in one day in a separate
environment. A read-only review found the applet and UIDL boundaries intact:
applets make no terminal calls, no UIDL annotation was added, and new Forth
uses the return stack correctly inside DO loops. It also found:

- With the shell sidecar installed, every changed draw is a complete hidden
  START and reveal, never a DELTA. The shell became the default
  `desktop-apt1` profile, so every keystroke republishes the whole retained
  scene, including up to 16,000 waveform samples. The recorded 52-stage
  journey took about 226 s with the shell, against about 120 s before it.
- The ordinary waveform painter draws every sample on each Sound Lab repaint:
  up to 16,000 guarded `DRW-CHAR` calls, most of them repainting a cell that
  already holds the trace, about 25 million guest steps per repaint. The
  previous painter drew one point per column.
- Silent fallbacks at capacity limits: a failed shell prepare emits the
  non-shell START, an over-limit SERIES graph is dropped whole, and a full
  Desk shell model switches to the legacy taskbar painter.
- Provisional sizes: an 8 MiB shell work arena and two 4 MiB banks sized for
  a 280×84 screen, a 94 MB producer arena from simultaneous worst cases, a
  256 MiB general XMEM split chosen after a 2.5 MB shortfall, and 16-bit
  samples stored in 8-byte cells.
- Same-day compatibility layers, unused code and small bugs, listed below.
- Qualification only with a dummy display and in-process dispatch; the
  physical Desktop journey never ran.

## Rules

AGENTS.md governs this work, including its rich-terminal section. CELL stays
the complete mandatory fallback; it is not legacy. Applets gain no terminal
calls, scenes, fixtures or special profiles. Speed-ups only remove provably
redundant work. The real device comes first. Develop against Desk plus the
applet in question; run the full physical Desktop journey once, as the final
gate. Commit each coherent slice once it is green.

## Steps

1. **Baseline.** Run the rich-terminal and Desk gates against the paired
   MegaPad branch through its Make supervisor before changing code. Done: the
   import had broken 101 tests it never ran, all stale harnesses or layout
   pins plus two misplaced production details; they are repaired. Failures
   that also occur on main are left for step 12: two in
   `test_uidl_collection_snapshot.py`, the data-graphics byte oracle, and
   about 450 in the older emulator-snapshot TUI harnesses.
2. **Shell off by default.** Done, until step 3 turned it back on.
3. **Shell DELTA.** Done. A changed draw with the acknowledged shell layout
   goes out as a retained DELTA that keeps the identities of unchanged panes,
   controls and waveform histories, and the shell is the default again.
   Typing on the Desktop, one key alone and the median in a burst: shell off
   0.29 s and 0.37 s; shell on, at first 1.27 s and 2.40 s, now 0.47 s and
   0.73 s. The speed-ups removed only redundant work: each frozen bank and
   snapshot is checked once, a DELTA copies the rows the base producer did
   not rebuild, the span overlap check and the bank copy no longer grow with
   the square of the span count, the band helpers and the planner's screen
   proof run once per build, and an idle producer step checks only its
   identity. The shell still adds about 14 million guest steps to a typed
   frame beyond the base producer's 12 million; the largest parts are the
   full-frame preflight, about 3.6 million, and the sidecar's per-event
   storage proof, about 2.6 million.
4. **Waveform painting.** Paint each covered screen cell once, with the same
   visible result. The canonical history keeps every sample. Done: a Sound
   Lab repaint fell from about 25 million to 6.4 million guest steps; the rest
   is per-sample placement arithmetic.
5. **Remove compatibility layers.** The absent-family constructor wrappers
   used only by tests, and the tests that pin their text. Done: one
   `RTHP-STORAGE-BYTES`, `RTHP-INIT` and `RUHA-INIT` each, with every family's
   arguments. The base producer's own admission and START emission stay:
   they publish the screen when no shell is installed and when the shell
   cannot build a draw, so they are the shell's fallback rather than legacy
   code, and the START emission is now named for the base projection. Desk's
   older taskbar painter and its hit test, its fallback when the shell model
   was full, went with step 7. Sound Lab's old narrow-pane settings painter
   is gone: its typed fields split a narrow panel in half instead.
6. **Tools on the new launcher.** `akashic_tui.py` and the other runners
   start MegaPad through `megapad.py` or the packaged servers, so MegaPad can
   delete its forwarding scripts. Done: the runners use
   `megapad.py --mode MODE`, and MegaPad's forwarders are gone.
7. **Sizes from real needs.** Done. Nothing in the rich path is sized for a
   largest screen or a fullest document any more. The engine's working
   banks, the screen producer's arena, the shell producer's work space and
   banks, the shell snapshot's banks and Desk's own taskbar model start small
   and grow to what each frame needs. All but Desk's model grow from Desk's
   memory source, the system heap, through `utils/memory-source.f`; a refusal
   leaves that part CELL, and the fallback record keeps the bytes asked for
   and held. Nothing is relocated: the frame on screen keeps its storage
   until the frame that replaces it is shown, and the next frame is a
   complete START. Desk no longer has a screen-size limit (the 400 by 200
   constants are gone) or a screen-width term in its transmit buffer, and
   Desk's older taskbar painter is gone with the fallback it served. Only the
   terminal keeps geometry and quota budgets, as its own policy. In the Desk
   + Pad check at 280 by 84 cells, Desk's rich storage grows to about 15 MB,
   and after loading the general memory has about 178 MiB free for it. The
   memory split stays as it was: networking takes a quarter of the general
   partition, so a larger one would also grow its tables. Sample storage
   follows the data-graphics bank, which grows like the others.
8. **Capacity negotiation.** Together with MegaPad step 9: the producer
   asks the terminal for more retained space and acts on the approval or
   denial, instead of silently falling back. On a denial that part stays
   CELL, and a record says which part fell back, how much space it asked for
   and how much it had; nothing is drawn on screen. Done. The owner opens
   with what the first frame needs, plus half again so that a frame growing
   a little does not ask on every draw, and never more than the terminal
   offers at all. When a later frame needs more than the owner holds, the
   producer asks the terminal to grow it and waits for the answer; after a
   no it asks once more for exactly the need. If that is refused too, the
   parts that do not fit stay CELL for that draw, and a newer draw asks
   again. The producer's record, read with `RTHP-FALLBACK@`, counts the
   draws that had a part stay CELL and gives, for the latest, which parts,
   why (the terminal refused, more than it offers, Desk's own memory, or
   other) and the quotas needed against those held. It covers the fallbacks
   that were silent before: a refused open, a draw shown only as CELL,
   families the admission ladder strips, series graphs beyond the
   terminal's limits, and a shell frame that falls back to the base START.
   The terminal keeps its own record of each refusal in its session status.
9. **Unused code.** Remove the unused mounted `SFIELD` path and
   `_DESK-TASKBAR-SLOT-AT`, or give them a real use. Done: both are
   removed, and status fields come only from ordinary UIDL status labels.
10. **Small fixes.** Restore Grid's CELL colors for errors, formulas and
    numbers. Stop Desk ignoring taskbar clicks between a relayout or focus
    change and the next paint. Stop swallowing draw-observer exceptions. Stop
    zero-filling the 48 KiB shell model bank on every Desk paint. Stop Sound
    Lab writing region internals directly. Stop binding readiness to the
    `[4:Grid]` label. Done: presses resolve against the taskbar still on
    screen; an observer that throws is detached and its error kept; a build
    clears only the header and the entries in use, which saves about 49,000
    cycles per Desk paint; readiness accepts Desk's label with any slot
    number.
11. **Docs.** Remove sandbox paths, update commit IDs cited in docs to the
    re-authored IDs in both repositories, and fold completed qualification
    notes into current documentation.
12. **Tests that already failed.** After everything else, fix the failures
    from step 1 that also occur on main. Done. The draw observer and UIDL
    semantic structure tests pass, and the Daybook shared lens test now
    links its closure. The data-graphics byte oracle's step limit is
    300,000,000; it needs 252,092,686. The UIDL collection oracle and the
    old emulator-snapshot test files now run on the native runtime through
    `local_testing/native_forth.py`, with fixtures repaired where the code
    had moved on. `test_app_compositor.py` went with its deleted module, and
    old Desk lifecycle checks that the real-Desk tests cover were dropped.
13. **Final gates.** Rerun the paired MegaPad gates and this branch's gates,
    run the physical Desktop journey once through
    `local_testing/physical_desktop_acceptance.py`, and run the numeric
    suites. Then merge into main and push together with MegaPad.

## Provenance

The imported commits were re-authored as Daniel with a
`Co-Authored-By: Codex <codex@openai.com>` trailer. Trees, parents and dates
are unchanged; commit IDs cited in messages, including MegaPad IDs, were
remapped. The original history is kept at
`refs/imports/codex-2026-09-30/main`, and the old-to-new commit map is
`.git/imports/codex-2026-09-30/commit-map.txt` in the main checkout.
