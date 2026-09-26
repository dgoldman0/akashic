# Pointer follow-ups in the physical Desktop journey — 2026-09-26

This run finishes part 1 of the
[rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Mouse and scrolling everywhere". The
[first run](pointer-journey-20260926.md) left three gaps:

- input fields placed the caret but could not select;
- Daybook's calendar ignored the wheel;
- Pad's "Ln, Col" readout lagged the caret by one frame.

Reading the code also showed that app prompts in Desk never received mouse
events at all.

The guarded launcher `local_testing/physical_desktop_acceptance.py` ran the
extended journey once with the native simulator. It **passed on the first
attempt**.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `66cac5c2c7eb7d18075e1769cc4d749f377885e9` (tree `8206be740843a204a66a2bb55b5064c464446900`) |
| MegaPad | `e1e21b3cec32972d53cb380d10b36a9c6411b9de` (tree `2bfc540aa7ee3e25896700cb84d5a3b415ce7512`) |
| Native extension SHA-256 | `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c` (the binary qualified on 2026-09-17) |
| Launcher SHA-256 | `85a513f9e7a52c6f733b2a6ec31b3dbdb9bda32314575891e37d3c5dff5c0c01` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The changes under test are Akashic commits:

- `a621bf8`: Pad's readout;
- `1aa67fa`: the text grid's scroll callback and Daybook's wheel;
- `f4a8426`: the input field's selection, its key handler, and its horizontal
  scroll;
- `a3d2c36`: pointer input offered to each hosted app before UIDL;
- `66cac5c`: the journey stages.

MegaPad is unchanged: its viewer already sent `SCROLL` for `TEXT_GRID`
targets.

Profile and settings:

- `desktop-apt1` in ordinary source mode;
- simulator backend with `MEGAFORTH_EXECUTOR=native`;
- 280x84, 18 px font, 0.75 s action delay, 10 s hold;
- 900 s watchdog and 3.5 GiB aggregate-RSS stop.

No compiled Forth cache, step-limit change, or timing change was used.

```bash
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent local_testing/out/pointer-followups-20260926
```

## Result

- Exit 0 with no stop reason, in 146.1 s including image build.
- Peak aggregate RSS 465,063,936 bytes (443.5 MiB).
- 31 milestones. The first 21 match the earlier journey through
  `fexplorer-list-row-clicked`. After that row click the journey now presses
  F2 instead of Ctrl+O, and the milestones that follow are:
  1. `fexplorer-rename-prompt-opened`: F2 opened File Explorer's rename
     prompt holding exactly `large.txt`, and a raw drag went from the name's
     first cell to its dot;
  2. `fexplorer-rename-stem-dragged`: the prompt still read
     `Rename: large.txt`, with `large` in reverse video and no caret;
  3. `fexplorer-rename-stem-replaced`: typing `notes` made the prompt read
     exactly `Rename: notes.txt`, which only happens if the drag selected
     exactly `large`;
  4. `fexplorer-rename-cancelled`: Escape closed the prompt, the status bar
     showed `/large.txt` again, and nothing was renamed;
  5. then, as before, `pad-fixture-opened`, `pad-wheel-scrolled`,
     `pad-caret-placed`, and `pad-text-selected`. Pad opened at
     `Ln 49, Col 1`, the empty line after the fixture's final newline. In the
     frames where the wheel, `PLACE`, and `EXTEND` moved the caret, the
     readout already named it: `Ln 46, Col 1` (the caret the wheel moved into
     view), `Ln 16, Col 7`, and `Ln 16, Col 14`;
  6. `pad-caret-moved-by-key`: a Right key moved the caret one scalar and
     dropped the selection, and the same frame read `Ln 16, Col 15`;
  7. `daybook-calendar-wheel-scrolled`: one `SCROLL` detent on Daybook's
     calendar `TEXT_GRID` moved its date from 2026-09-27 to 2026-10-04, and
     the calendar turned to October with the 4th selected.
- 34 accepted revision-bound inputs with zero manual input RPCs. The new ones
  are:
  - `send_key` F2 and `send_text` `notes`, each backpressured once and
    accepted on a newer frame;
  - a raw `send_pointer` drag: press at cell (102, 39), then a move with the
    button held and a release at (107, 39). Both cells were proven residual
    in the acknowledged hit map. The whole gesture was accepted, so nothing
    was owed;
  - `send_key` Escape and Right;
  - `send_text_event` `SCROLL`, wheel Y +1, on Daybook's `TEXT_GRID`, taken
    from a point the viewer's own layout maps to it (content revision 39).
- 46 post-flip physical acknowledgements through the `pygame.display.flip`
  X11 sink.
- The initial (offer 1) and final (offer 46) CELL fallback gates both passed.
  The final gate matched Pad's focus marker, `SOUND LAB`, `2026-10-04`, and
  `Large fixture line 016`.

While the rename prompt was open, File Explorer's semantic slices were
withheld by the same document-atomic rule as Daybook's prompt. The journey
checked this exactly: every other menu forest, Pad, Daybook, and Sound Lab
stayed rich, and File Explorer kept no partial text collection or tab set.
Its tile stayed complete through residual glyphs, which is also why raw
pointer input could reach the prompt.

The captures were inspected. `fexplorer-rename-stem-dragged` shows the
highlighted stem without a caret. `fexplorer-rename-stem-replaced` shows
`notes.txt` with the caret on the dot. `pad-caret-moved-by-key` shows
`Ln 16, Col 15` in Pad's status bar. `daybook-calendar-wheel-scrolled` shows
October 2026 with the 4th selected and `2026-10-04` above the agenda.

## Artifact hashes

The artifacts are in
`local_testing/out/pointer-followups-20260926/physical-desktop-ns0mo38c/`,
which is ignored.

| File | SHA-256 |
| --- | --- |
| `evidence/manifest.json` | `2e3c5acf61358c341ae2ddb2cb28373a42feabd26f00dac7fe81c43edf9d6010` |
| `evidence/performance-trace.json` | `9ed2ed909159cfdf765a9f69e86fd480a70960fa4f48dab75eda6c0a88e9f774` |
| `bindings.json` | `97a852218bedf49c066401b7b6a64799945f536fcc6115e5f37fc51a48034c53` |
| `supervisor.json` | `986f528c39eb764cf5bcf38abe69932a7f3bbe5f6095a376a6027da2f44e5937` |
