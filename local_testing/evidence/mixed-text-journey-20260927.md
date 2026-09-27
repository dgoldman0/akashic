# Mixed-script text in the physical Desktop journey — 2026-09-27

Part 2 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Wide text, emoji, right-to-left and fonts", ends with new milestones in the
physical Desktop journey. The guarded launcher
`local_testing/physical_desktop_acceptance.py` ran the extended journey once
with the native simulator, after each piece had passed its own narrower
checks. It **passed**. Pad and Daybook took typed text that mixes English,
Chinese, an accent built from a combining mark, an emoji sequence, a flag,
Hebrew, and Arabic. Clicks and the caret landed on whole characters, and the
final CELL fallback showed both texts in visual order.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `e3015b159f6c30c48420a2b87c4a88e64c2b920f` (tree `999c079a7784df28680aead93218e3d8f04472c3`) |
| MegaPad | `8676818a8047e85e788fee403b41b67294d83833` (tree `b57a30baf134b8b5bf5f8112a1da32ed5a00b21e`) |
| Native extension SHA-256 | `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c` (the binary qualified on 2026-09-17) |
| Launcher SHA-256 | `abafc2eda332abc7f810698282bf0f15a08a89ae3a67d6722bdab257a2bbff3e` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The viewer's fallback fonts, found through fontconfig, were Noto Sans CJK,
Noto Sans Hebrew, Noto Sans Arabic, Noto Sans Symbols and Symbols2, Noto Sans
Math, and Noto Color Emoji; `bindings.json` records each file's SHA-256.

The Part 2 changes under test are MegaPad `0b8dadb` through `8676818` and
Akashic `53fdba9` through `e3015b1`:

- the contract: `APT-1-TEXT.md` (characters, widths, bidi, Arabic joining,
  positions and the caret), CELL-1 wide and cluster cells, STX1 paragraph
  direction and cell columns, and the rule for sending text longer than one
  TEXT event;
- Akashic: Unicode 15.1 tables, grapheme clusters, the bidirectional
  algorithm, one-row layout, screen storage for wide and multi-scalar
  characters, the text area, input field, labels, tabs, menus, text grid,
  and dialogs measured in cells, and Daybook's agenda clipped by cells;
- MegaPad: the terminal's own text rules, CELL-1 carriage of clusters, rich
  layout of text areas, grids, and labels, the viewer's font set with
  per-character fallbacks, and long text sent as several TEXT events.

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
  --output-parent <scratch directory>
```

## Result

- Exit 0 with no stop reason, in 219.0 s including image build.
- Peak aggregate RSS 491,458,560 bytes (468.7 MiB).
- 43 milestones. The first 31 are the existing journey, unchanged, ending
  with `daybook-calendar-wheel-scrolled`. The 12 new ones are:
  1. `pad-caret-at-line-end` — End put Pad's caret at the end of line 16 of
     `large.txt`;
  2. `pad-line-opened` — Enter opened an empty line after it;
  3. `pad-mixed-text-typed` — one `send_text` of the 61-byte line
     "Hi 中文 é 👨‍👩‍👧 🇯🇵 שלום مرحبا", its "é" an e with a combining acute.
     The Desk advertises 52 bytes per TEXT event, so the terminal sent it as
     two events split between characters. Pad's `TEXT_AREA` carried the
     line logically, its CELL cells showed it in visual order, and the
     readout counted 22 characters;
  4. `pad-caret-placed-on-cluster` — a `PLACE` at item key 17, offset 6,
     put the caret before the combined accent;
  5. `pad-caret-moved-over-cluster` — Right moved it over both of the
     accent's scalars, to offset 8;
  6. `pad-caret-placed-in-hebrew` — a `PLACE` at offset 19 landed on the
     Hebrew word's second letter;
  7. `daybook-focused-for-mixed-task` — Alt+3 focused Daybook;
  8. `daybook-mixed-prompt-opened` — Ctrl+N opened the task prompt, which
     withheld Daybook's menu and calendar, as the document-atomic fallback
     requires, while its cells stayed complete;
  9. `daybook-mixed-task-typed` — one `send_text` of
     "Tea 茶 née 👩‍💻 🇮🇱 שלום شاي", shown in the prompt in visual order;
  10. `daybook-prompt-caret-on-han` — a raw click on the second cell of
      "茶", at cell (202, 39), put the caret on that character;
  11. `daybook-prompt-text-inserted-at-click` — a typed "!" landed before it;
  12. `daybook-mixed-task-added` — Enter added the task, which the agenda
      showed as "[ ] Tea !茶 née 👩‍💻 🇮🇱 שלום شاي".
- 46 revision-bound inputs with zero manual input RPCs.
- The initial (offer 1) and final (offer 63) CELL fallback gates both
  passed. The final gate matched Daybook's focus marker `[3:Daybook*]`,
  `SOUND LAB`, the Daybook date, `Large fixture line 016`, and both mixed
  texts as their cells show them, Arabic in its joined presentation forms.

The `pad-caret-placed-in-hebrew` and `daybook-mixed-task-added` captures were
inspected. Pad shows the mixed line as line 17 with "Ln 17, Col 14". Daybook
shows the new task selected in its agenda, the Hebrew and Arabic words in
right-to-left order after the flag, and "1 entries" in its status bar.

## Checks before the full run

The full journey ran once, as regression, after these narrower checks:

- Unicode conformance. Both bidi implementations, Akashic's `text/bidi.f`
  (`local_testing/test_bidi_conformance.py`) and MegaPad's
  `rich_terminal/text_rules.py` (`tests/test_rich_terminal_text_rules.py`),
  pass all 770,241 cases of `BidiTest.txt` and all 91,707 cases of
  `BidiCharacterTest.txt`: paragraph level, every level, and visual order.
  MegaPad's grapheme segmentation passes every case of
  `GraphemeBreakTest.txt`.
- Each applet alone, in CELL. The standalone `pad` and `daybook` smokes type
  the same texts, check cells, caret, and readout after each click, Right,
  and Backspace, and check that the files hold the exact UTF-8.
- Desk with a single applet, on the rich terminal. `--applet pad` and
  `--applet daybook` run Desk holding only that applet through the same
  physical viewer, with the journeys in
  `local_testing/rich_terminal_applet_journeys.py`. Both passed on the
  sources above. These are development checks, not acceptance evidence.
- Widgets. `local_testing/test_widget_text_widths.py` checks labels, menu
  bars, tab strips, text grid items, and dialogs against MegaPad's text
  rules.

## Defects found on the way

- Typed text longer than one TEXT event was refused as invalid, so the first
  run stopped with Pad's new line empty. A long input-method commit would
  have been lost the same way. APT-1-WIRE Section 12 now has the terminal
  send such text as consecutive events split between characters (MegaPad
  `8676818`, Akashic `0dc288c`).
- The final CELL gate still expected Pad's focus, though the new stages end
  in Daybook (Akashic `8fe7cd0`).
- The standalone Daybook smoke had been passing without running its steps:
  its emulator clock started at 1970, so the sample day never showed. It now
  starts at the sample date, and a smoke whose ready screen never appears
  fails (MegaPad `0540988`, Akashic `07ca0db`).
- The first Desk-with-Pad run took the topmost of Pad's empty text areas,
  which was not its editor, and waited on it while the editor filled. That
  journey now finds the editor by keyboard focus (Akashic `82b3070`).

## Not covered

- Desk's taskbar, hotbar, and launcher labels, and a few unused widgets,
  still measure by bytes. No non-ASCII text reaches them today, since app
  titles are checked to be ASCII.
- Indic and other complex scripts, and mirroring the whole interface for
  right-to-left users, are later work in the plan.
- Unchanged failures outside this part: `test_uidl_tui.py`'s hand-kept
  module list lacks the text grid and tab widgets;
  `test_widget_draw_observer_structure.py` objects to `WDG-T-TEXTAREA` in
  `widget.f`; the collection snapshot's tabset case; and MegaPad's
  `test_shared_server_clients_control_one_machine`.

## Artifact hashes

The artifacts are in
`local_testing/out/mixed-text-20260927/physical-desktop-kab8eshb/`, which is
ignored.

| File | SHA-256 |
| --- | --- |
| `evidence/manifest.json` | `a6a391e456c7ac65fde96bf2a19b722481fc70f11b1202c8aafadb757957b10f` |
| `evidence/performance-trace.json` | `23f0077a1b3681628f9bf4e51617b9ddab5e322508568bd5b137536ec18d55b5` |
| `bindings.json` | `633114676c410c0542693d4468738d8e3e0fd3cb5951f413d08ff08776f322a1` |
| `supervisor.json` | `65219d5441e5a5dda13bc6e1ed16fe844a4340dce2e8b83116ea96163286872e` |
