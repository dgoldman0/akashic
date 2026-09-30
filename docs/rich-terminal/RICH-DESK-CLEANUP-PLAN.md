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
   that also occur on main are left as they were: two in
   `test_uidl_collection_snapshot.py`, the data-graphics byte oracle, and
   about 450 in the older emulator-snapshot TUI harnesses.
2. **Shell off by default.** Done. The registered `desktop-apt1` profile uses the
   shell-off rich profile. The shell stays available as an explicit
   development profile until step 3 lands.
3. **Shell DELTA.** Publish only changed panes and bands, keeping identities
   of unchanged panes and waveform histories. Measure typing cadence, then
   make the shell the default again.
4. **Waveform painting.** Paint each covered screen cell once, with the same
   visible result. The canonical history keeps every sample. Done: a Sound
   Lab repaint fell from about 25 million to 6.4 million guest steps; the rest
   is per-sample placement arithmetic.
5. **Remove compatibility layers.** The absent-family constructor wrappers
   used only by tests (`RTHP-INIT`, `RTHP-INIT-STATUS`, `RTHP-INIT-FIELDS`,
   `RTHP-STORAGE-BYTES`, `RTHP-STORAGE-BYTES-STATUS`, `RUHA-INIT`,
   `RUHA-INIT-STATUS`) and the tests that pin their text; the old HP/HA
   admission and legacy START emission once family batches cover them;
   Desk's legacy taskbar painter and slot lookup; Sound Lab's old narrow-pane
   settings painter.
6. **Tools on the new launcher.** `akashic_tui.py` and the other runners
   start MegaPad through `megapad.py` or the packaged servers, so MegaPad can
   delete its forwarding scripts.
7. **Sizes from real needs.** Derive the shell arena and banks, the producer
   arena, the XMEM split and sample storage from actual content bounds, and
   grow within caller-provided bounds where possible.
8. **Capacity negotiation.** Designed with the owner, together with MegaPad
   step 9: the producer asks the terminal for more retained space and acts on
   the approval or denial, instead of silently falling back.
9. **Unused code.** Remove the unused mounted `SFIELD` path and
   `_DESK-TASKBAR-SLOT-AT`, or give them a real use.
10. **Small fixes.** Restore Grid's CELL colors for errors, formulas and
    numbers. Stop Desk ignoring taskbar clicks between a relayout or focus
    change and the next paint. Stop swallowing draw-observer exceptions. Stop
    zero-filling the 48 KiB shell model bank on every Desk paint. Stop Sound
    Lab writing region internals directly. Stop binding readiness to the
    `[4:Grid]` label.
11. **Docs.** Remove sandbox paths, update commit IDs cited in docs to the
    re-authored IDs in both repositories, and fold completed qualification
    notes into current documentation.
12. **Final gates.** Rerun the paired MegaPad gates and this branch's gates,
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
