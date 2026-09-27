# Styled text and links in the physical Desktop journey — 2026-09-27

Part 3 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Styled text and links in text areas", ends with new milestones in the
physical Desktop journey. The guarded launcher
`local_testing/physical_desktop_acceptance.py` ran the extended journey once
with the native simulator, after each piece had passed its own narrower
checks. It **passed**. Pad showed a Markdown file with its heading, link, and
strong text styled, both in the rich view and in CELL. A Ctrl-click on the
link sent a `FOLLOW` event, and Pad opened the Forth file the link names,
with its Forth highlighted.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `7e6832c132ea77f5776523e1dc70454d32f8baeb` (tree `8f5cdf73ba23aa350016c5b11703c8f156cab15f`) |
| MegaPad | `370981d8ae2fb823a0e256f978c62df2df47dc16` (tree `4258e464a5df3608bdd7dfdec50c56979732259f`) |
| Native extension SHA-256 | `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c` (the binary qualified on 2026-09-17) |
| Launcher SHA-256 | `6dbfaca300827f5a7f867ddc2249687ba809a350554d22b91595a08ddddf566c` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The viewer found the font's real bold, oblique, and bold oblique faces
through fontconfig (DejaVuSansMono-Bold, -Oblique, and -BoldOblique), and the
same fallback fonts as part 2. `bindings.json` records each file's SHA-256.

The Part 3 changes under test are:

- the contract: MegaPad `35875eb` (style runs in STX1 and the `FOLLOW`
  control event) and Akashic `e209890` (the mirrored documents and the
  plan's contract paragraph);
- MegaPad `370981d`: style runs in the semantic content codec, the `FOLLOW`
  event through the wire, shared session, and guest module, the viewer's
  reference theme and link routing, and real styled font faces;
- Akashic `0e7de0e`: the text meanings, the Forth and Markdown scanners, the
  CELL palette, styled drawing, the text area's style source and follow
  word, style runs through capture, validation, and STX1, and Pad's
  highlighting and link following;
- Akashic `7e6832c`: the journeys, the Pad smoke, and their shared fixtures.

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
  --output-parent local_testing/out/styled-text-20260927
```

## Result

- Exit 0 with no stop reason, in 191.2 s including image build.
- Peak aggregate RSS 513,183,744 bytes (489.4 MiB).
- 48 milestones. The first 43 are the existing journey, unchanged, ending
  with `daybook-mixed-task-added`, whose next input is now Alt+1. The 5 new
  ones are:
  1. `pad-focused-for-link` — Alt+1 focused Pad, and Ctrl+O followed;
  2. `pad-open-prompt-shown` — Pad's Open prompt withheld Pad's menu and
     text areas, as the document-atomic fallback requires, while its cells
     stayed complete; the path `/notes.md` was typed;
  3. `pad-notes-path-typed` — the prompt showed the path, and Enter opened
     it;
  4. `pad-markdown-styled` — Pad's `TEXT_AREA` carried `notes.md` with one
     `HEADING` run over "# Notes" and, on "Read [the example](example.f)
     and \*\*try it\*\*.", a `LINK` run at scalars 5 to 28 and a `STRONG` run
     at 34 to 43. The viewer's hit target reported scalar 12, inside the
     link's text, as a link character, and the journey sent a `FOLLOW` there
     with Ctrl;
  5. `pad-link-followed-to-forth` — Pad opened `/example.f` in a new tab.
     Its line ": SQUARE DUP * ;" carried `KEYWORD` runs on ":" and ";".
- 51 revision-bound inputs with zero manual input RPCs.
- The initial (offer 1) and final (offer 71) CELL fallback gates both
  passed. The final gate matched Pad's focus marker `[1:Akashic Pa*]`,
  `SOUND LAB`, the Daybook date `2026-10-05`, the mixed Daybook task as its
  cells show it, and ": SQUARE DUP * ;".

Three captures were inspected. In `pad-markdown-styled` the heading is
orange and bold, the link blue and underlined, and the strong text bold.
In `pad-link-followed-to-forth`, `example.f` is Pad's fifth tab and its ":",
";", and "9" are coloured as keywords and a number. In the existing
`daybook-source-opened-in-pad`, Daybook's own Markdown file, handed to Pad,
shows "# Daybook" as a heading: the plan's case of Daybook's file in Pad.

## Checks before the full run

The full journey ran once, as regression, after these narrower checks:

- Unit and structure tests. In Akashic: the scanners and file types
  (`test_syntax_styles.py`), CELL looks, laid-out lines, palettes, and
  Ctrl-click (`test_textarea_styles.py`), and runs through capture,
  validation, and STX1, decoded by MegaPad's decoder
  (`test_semantic_style_runs.py`), with the updated collection, snapshot,
  packer, text area, text grid, engine, adapter, and journey tests. In
  MegaPad: the codec, scene, wire, shared session, viewer routing, styled
  painting, font discovery, and the guest module's `FOLLOW` decoding.
- Pad alone, in CELL. The standalone Pad smoke opens `notes.md`, checks the
  CELL colour and attributes of each marked word, Ctrl-clicks the link with
  an SGR press, and waits for `example.f` with its Forth highlighted.
- Desk with Pad alone, on the rich terminal. `--applet pad` passed its 12
  milestones with 11 inputs in 64.4 s, peak RSS 458,813,440 bytes, on the
  same commits. This is a development check, not acceptance evidence.

## Defects found on the way

- `utils/file-types.f` had never worked. Its table pointed into the one
  transient buffer that interpreted `S"` strings share, and each entry held
  the extension's address and length in swapped order. Nothing used it
  until Pad's highlighting did.
- The native text-area item grew a run count, which made its header 72
  bytes, the validation summary 56, and the builder 80. Five places had
  built in the old sizes. The snapshot descriptor would have let the new
  count overwrite the next descriptor. The RUHA adapter's fields after its
  collection builder were overwritten, which made one test run until its
  step budget ended. The rich engine and the APT-1 engine checked each text
  body against the old STX1 size, so they would have refused every text
  area; they now carry the run total and check the exact size. Desk's
  control copy bank reserved the old prefix. Each now derives from or
  carries the new sizes.
- Several test harnesses read module text directly. Two byte oracles did
  not load `text-style.f`, and the adapter storage proof could not read a
  constant derived from other sizes. They now do.

## Not covered

- Library's document view, the plan's second consumer, still draws its
  text by hand.
- There is no e-paper theme yet. The contract allows one that uses only
  weight and underline.
- A plain click on a link in read-only text sends `FOLLOW`, but no applet
  shows read-only text with links yet; MegaPad's unit tests cover that
  routing.
- Pad follows only links to files, by a path relative to the linking file's
  folder or an absolute one. A target ends at its first blank, `#` and `?`
  suffixes are dropped, and a target with a scheme such as `https:` is
  refused with a message.
- Publishing scans each carried row again, about 3.4 million guest steps per
  pass for 60 lines of Forth. A full 60-line redraw costs 11% more for Forth
  and 8% more for Markdown than plain text.
- Unchanged failures outside this part: the collection snapshot's tabset
  case; that file's RUHA constructor test, stale since the adapter's ABI 6
  (it passes 10 of the 12 caller banks, asserts old sizes, and runs until its
  step budget ends); and MegaPad's
  `test_shared_server_clients_control_one_machine`.

## Artifact hashes

The artifacts are in
`local_testing/out/styled-text-20260927/physical-desktop-9unrourl/`, which is
ignored.

| File | SHA-256 |
| --- | --- |
| `evidence/manifest.json` | `2e45e6348b2c2ca0459836f3db29979224736ea44221fa35f6ad3e93bc96b908` |
| `evidence/performance-trace.json` | `6cf9aa8cf05aa4d1251899856024091cc71ad9f273b7cc8f868c109891bbd211` |
| `bindings.json` | `403ef9fdcaa9b97300c318b2b390e086fb9f834766bf5e0247387f5b0465f70c` |
| `supervisor.json` | `6285c8515c105e5326d5eeb4c69e31863f0370c58c16e8b87839349a79c1a4e1` |
