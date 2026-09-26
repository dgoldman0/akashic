# Pointer milestones in the physical Desktop journey — 2026-09-26

Part 1 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Mouse and scrolling everywhere", ends with new milestones in the physical
Desktop journey. The guarded launcher
`local_testing/physical_desktop_acceptance.py` ran the extended journey once
with the native simulator. It **passed**: the journey clicked the taskbar and
a list row, scrolled a list and Pad with the wheel, and placed Pad's caret
and selected text with the mouse.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `7cb6b70360271d4011691b39947a4213e8145a59` (tree `41d5e6d1aa6f2c236d9c1903826ab163e3ed79fd`) |
| MegaPad | `e1e21b3cec32972d53cb380d10b36a9c6411b9de` (tree `2bfc540aa7ee3e25896700cb84d5a3b415ce7512`) |
| Native extension SHA-256 | `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c` (the binary qualified on 2026-09-17) |
| Launcher SHA-256 | `85a513f9e7a52c6f733b2a6ec31b3dbdb9bda32314575891e37d3c5dff5c0c01` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The Part 1 changes under test are MegaPad `e1e21b3` (contract, viewer pointer
router, host checks) and Akashic `68c12a3` (guest routing and widgets),
`65ae56e` (journey stages), `87262c2` (UIDL repaint after pointer input), and
`7cb6b70` (journey expectations for loaded text).

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
  --output-parent local_testing/out/pointer-20260926
```

## Result

- Exit 0 with no stop reason, in 129.8 s including image build.
- Peak aggregate RSS 464,015,360 bytes (442.5 MiB).
- 25 milestones. The first 18 are the existing journey, unchanged, ending
  with `soundlab-restored-after-menus`. The 7 new ones are:
  1. `fexplorer-taskbar-clicked` — a raw click on the taskbar's File
     Explorer button focused it;
  2. `fexplorer-list-wheel-scrolled` — one raw wheel detent moved the detail
     list's `large.txt` row up exactly three rows;
  3. `fexplorer-list-row-clicked` — a raw click on that row selected it,
     showing `/large.txt` in the status bar and the file in the preview;
  4. `pad-fixture-opened` — Ctrl+O opened it in Pad as an appended, selected
     third tab, scrolled to its caret at the end;
  5. `pad-wheel-scrolled` — a `SCROLL` control event of one detent up moved
     Pad's view exactly three lines, and the caret followed into view;
  6. `pad-caret-placed` — a `PLACE` control event put the caret at line 16,
     offset 6;
  7. `pad-text-selected` — an `EXTEND` control event moved the caret to
     offset 13 with the anchor held at offset 6, selecting "fixture".
- 28 revision-bound inputs with zero manual input RPCs. The seven new
  inputs are:
  - `send_pointer` click (press and release) at cell (16, 83);
  - `send_pointer` wheel, one detent down, at cell (122, 10);
  - `send_pointer` click at cell (122, 7);
  - `ctrl+o`, which was backpressured once and accepted on the retry;
  - `send_text_event` `SCROLL`, wheel Y −1, on Pad's `TEXT_AREA`;
  - `send_text_event` `PLACE` at item key 16, offset 6;
  - `send_text_event` `EXTEND` at item key 16, offset 13.

  Each raw cell was proven residual in the acknowledged hit map before it
  was sent. Each text position was taken from a pixel that the viewer's own
  layout maps to that position, and carried that frame's content revision
  (29, 30, and 31). No click release was backpressured, so none was owed.
- 36 post-flip physical acknowledgements through the `pygame.display.flip`
  X11 sink.
- The initial (offer 1) and final (offer 36) CELL fallback gates both
  passed. The final gate matched Pad's focus marker, `SOUND LAB`, the
  Daybook date, and `Large fixture line 016`, the selected line.

The `pad-text-selected` capture was inspected. Pad shows its three tabs with
`/large.txt` selected, lines 11 to 46, and "fixture" highlighted on line 16.
File Explorer shows the preview tab and `/large.txt` in its status bar, and
Sound Lab's instruments are live.

Pad's "Ln, Col" status label is refreshed by Pad's tick callback, not by the
editor's pointer handling, so it follows a pointer-moved caret one tick
later. The final capture was taken before that tick and still reads
"Col 7" from the `PLACE`. The editor's own state was already correct.

## Earlier attempts

Two earlier runs of the same stages stopped and were ended by hand after
the cause was read from the live guest:

- `physical-desktop-r7wg5dvg` (Akashic `65ae56e`) waited after the list
  wheel. The guest's list reported a scroll offset of 3, but UIDL paints
  only elements marked dirty, and pointer forwarding never marked them.
  Fixed in `87262c2`, with a UIDL-level regression test.
- `physical-desktop-h5nyfc1u` (Akashic `87262c2`) waited after the row
  click. The list reported the selection, but loading text puts the caret
  at the end, so the preview never showed the fixture's first line that
  the journey expected. Fixed in `7cb6b70`, which also makes the Pad stages
  scroll up from the end.

## Artifact hashes

The artifacts are in
`local_testing/out/pointer-20260926/physical-desktop-ovlyhl8b/`, which is
ignored.

| File | SHA-256 |
| --- | --- |
| `evidence/manifest.json` | `af2e026cefa72c23e97063c1f5b91d6c5e08647ea42539efdd6c8000024fd563` |
| `evidence/performance-trace.json` | `667508df140b0ff65ae60c098b462798be619a86f63a878415cff15eb1fa5d0d` |
| `bindings.json` | `30213a251026315b674d1eb63866d1fed136151bc7b47a90afb3c7a3772257f8` |
| `supervisor.json` | `638d15916ced9b22b24ca1a10675d53b1761a80f3bc46b4ee73141016d267def` |
