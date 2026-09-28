# Lists and trees in the physical Desktop journey — 2026-09-27

Part 4 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Lists and trees", is done when "the journey selects and opens a file in File
Explorer and launches an app from the launcher through item events". The
guarded launcher `local_testing/physical_desktop_acceptance.py` ran the
canonical journey with the native simulator after the narrower checks below.
It **passed**. The launcher was a rich list, and item `SELECT` and `OPEN`
events launched Sound Lab from it. File Explorer's detail table was a rich
table. An item `SCROLL` moved it three rows, `SELECT` selected large.txt, and
`OPEN` opened the file in Pad.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Bindings

Both source trees were clean at launch and unchanged at exit; the launcher
enforces both conditions.

| Binding | Value |
| --- | --- |
| Akashic | `e41d66843cd796185c4beaddeb1d0a360f71920f` (tree `7f36ead756bf0493eed194b493ca4d550b7c8dc2`) |
| MegaPad | `465a6ad8ea9f0ebf0580ec6ee98da52cac816ea2` (tree `052ea6d0437cb3f2c29581053cbb2b35791a2968`) |
| Native extension SHA-256 | `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c` (the binary qualified on 2026-09-17) |
| Launcher SHA-256 | `756e53af49d729f6f4b70520f9803dd97088553b66aeb7fc187613a5f16c8d81` |
| Font | DejaVuSansMono.ttf, SHA-256 `b4a6c3e4faab8773f4ff761d56451646409f29abedd68f05d38c2df667d3c582` |

The styled faces and fallback fonts are the same as in part 3.
`bindings.json` records each file's SHA-256.

The Part 4 changes under test are:

- the contract: MegaPad `b77dfbf` (the `ITEM_VIEW` kind, its `ITM1` body, and
  the item events) and Akashic `4d20ee7` (the mirrored documents and the
  plan's contract paragraph);
- MegaPad `7962b40` (the ITM1 codec, scene, events, viewer rendering and hit
  map, and guest module) and `465a6ad` (PT control state bits renamed so the
  `OPEN` event no longer shadows one);
- Akashic `58d78a7`, `c46ece9` and `4753e5e`: the native item-view family,
  its ITM1 packer, and both rich engines;
- Akashic `be932b5`: the list and tree widgets rebuilt around keys and
  callbacks, their item-view capture, item events back to the widgets, and
  File Explorer's tree and detail table;
- Akashic `fc57bb1`: item views through the target pack and onto the wire;
- Akashic `a52b7c4` and `e41d668`: the journey's File Explorer stages driven
  by item events;
- Akashic `24d9cfc` and `7ae9040`: Desk's launcher as an overlay document
  holding a canonical list, on generic applet-host overlay slots with their
  own IDs.

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

- Exit 0 with no stop reason, in 249.3 s including image build.
- Peak aggregate RSS 491,560,960 bytes (468.8 MiB).
- 48 milestones and 51 revision-bound inputs, with zero manual input RPCs.
  These are the same milestones as part 3's run. Five inputs are now item
  events, all sent to `ITEM_VIEW` roots:
  1. offer 17, before `soundlab-launch-source`: `SELECT` on Sound Lab's row
     of the launcher list. Keys still work there: the journey's End key
     before it moved the selection to Streams;
  2. offer 18: `OPEN` on the same row, which launched Sound Lab as applet 6;
  3. offer 28, after `fexplorer-taskbar-clicked`: one `SCROLL` detent on
     File Explorer's table, which moved its first shown row from 0 to 3;
  4. offer 29: `SELECT` on large.txt's row, after which the table reported
     that row selected and the status bar showed `/large.txt`;
  5. offer 38, after `fexplorer-rename-cancelled`: `OPEN` on large.txt's
     row, which opened the file in Pad (`pad-fixture-opened`).
- large.txt kept the same item key across the rename prompt. While the
  prompt was up, File Explorer's item view was withheld, as the
  document-atomic fallback requires. When the prompt closed, the table was
  published again under a new wire ID (control 3910, then 6215), and the
  `OPEN` named the row by the same key as the `SELECT` before it.
- The initial (offer 1) and final (offer 69) CELL fallback gates both
  passed. The final gate matched Pad's focus marker `[1:Akashic Pa*]`,
  `SOUND LAB`, the Daybook date `2026-10-06`, the mixed Daybook task as its
  cells show it, and ": SQUARE DUP * ;".

Three captures were inspected. In `soundlab-launch-source` the launcher sits
over the File Explorer and Agent tiles as a two-column list of names and
states, with Sound Lab highlighted, its status line, and its key hint. In
`fexplorer-taskbar-clicked` File Explorer's detail table shows its Name,
Size and Type header and rows. In `fexplorer-list-row-clicked` the table
starts at its fourth row, coldsrc.f, and large.txt is highlighted.

The run took 58 s longer than part 3's, and its first frame came 19 s
later. The guest did the same work before that frame in both runs (about
6,300 scheduling batches), and this run completed fewer batches in total
(105,065 against 125,191) in more time. That points to a slower host, not
more guest work: other programs kept the host's load average between 12
and 15 over the run. The wall time is therefore not a measure of Part 4's
cost.

## Checks before the full run

- Unit and structure tests. In Akashic: the item-view capture
  (`test_semantic_item_views.py`), pointer and item-event input to lists and
  trees (`test_widget_pointer.py`), the TUI layers (`test_tui.py`), the
  explorer (`test_explorer.py`), UIDL-TUI (`test_uidl_tui.py`), the retained
  architecture and ratchet tests, the engine contract tests, the applet host
  contract (`test_applet_host.py`, including overlay IDs), and the journey
  harness (`test_rich_terminal_desktop_acceptance.py`). In MegaPad, all 680
  rich-terminal tests at `465a6ad`, covering the ITM1 codec and structure
  rules, the scene, wire and viewer input, including a double press
  becoming `OPEN`, and the guest module.
- Desk with File Explorer alone, on the rich terminal. `--applet fexp`
  passed its 8 milestones with 7 inputs in 89.3 s, peak aggregate RSS
  456,040,448 bytes, on `24d9cfc` with the overlay-ID change that was then
  committed as `7ae9040`. It selects and opens rows in the table,
  expands, selects and collapses a folder in the tree with item `EXPAND` and
  `COLLAPSE`, and opens and closes the launcher. This is a development
  check, not acceptance evidence.

## Defects found on the way

- The hybrid producer's control-target pack admitted kinds only up to
  `TAB`, so the first published item view made the pack invalid and Desk
  stopped with -3203. The APT-1 engine had no wire kind for `ITEM_VIEW`, so
  every transaction holding one was refused and retried without end. The
  journey harness refused item-view draws. All three now accept the kind.
- File Explorer changed its own mounted table and tree without marking
  their UIDL elements dirty. UIDL repaints only marked elements, so CELL
  output kept the old rows. File Explorer now marks them.
- The tree kept expansion as a bitmap of depth-first row numbers. Opening a
  branch moved every later branch's state onto the wrong node, and the
  bitmap stopped at 512 nodes. Expansion and selection are now keyed.
- Opening the launcher took the next applet number, so after one use Sound
  Lab became applet 7, and the first full run stopped at the watchdog. Host
  overlays now take IDs from their own range below -1.
- The journey's row stage still waited for File Explorer's Preview tab,
  which selection no longer shows, because the table stays in view so the
  row can be opened. The second full run stopped at the watchdog while the
  guest sat idle. The stage now checks the table's selection and the status
  path.
- The new `OPEN` event kind in MegaPad's guest module reused the name
  `PT-CONTROL-OPEN`, which already named the menu-open state bit. A later
  Forth constant silently shadows an earlier one, so the record check
  tested the wrong bits and refused visible controls that were not enabled,
  such as menu separators. Akashic's engine mapping had the same shadowed
  name. The state bits now carry `-F-` names, and a structure test rejects
  any constant defined twice.
- Several test scripts loaded modules in a hand-written order that the new
  dependencies broke. They now use the shared dependency resolver.
- After the run, the applet boundary test showed that Desk and File
  Explorer configured their lists with the collection model's column kinds
  (`USCOL-IV-TEXT` and `USCOL-IV-NUMBER`), which applets must not name. The
  list widget now has its own names for the two kinds, `LST-TEXT-COLUMN`
  and `LST-NUMBER-COLUMN`, with the same values. The Desk plus File
  Explorer check passed again with them, in 72.2 s.

## Known defect seen in this run

File Explorer keeps the listed directory's inodes as raw pointers. The VFS
evicts closed, unchanged file inodes once it holds more than its high-water
mark (256 by default) and reuses their slots, and nothing tells File
Explorer. In this run, daybook.md's row showed an empty name and size 0 in
`soundlab-launch-source`, and "soundlab.uidl 992" from
`fexplorer-taskbar-clicked` on. daybook.md itself was missing from the
table. Acting on such a row acts on whatever the slot now holds. This is
older than Part 4: the old list copied each row's text when it was filled,
which hid the stale pointer but not its effect on open, preview, rename and
delete. The table now draws each row from the inode, so the fault shows. It
does not affect the journey's checks, so it is recorded here and in
`docs/tui/applets/fexplorer/fexplorer.md` rather than fixed in this part.

## Not covered

- Daybook's agenda (sections and checked items), Streams cards and the Agent
  transcript are still painted text, so the `SECTIONS` and `CARDS` roles and
  the `CHECK` event have no consumer yet. Library's design check is not done.
- The Desktop journey sends `EXPAND` and `COLLAPSE` nowhere; only the File
  Explorer applet check does.
- The journey sends `OPEN` as a control event. It does not press twice in
  the viewer; MegaPad's viewer tests cover that.
- The launcher costs one UIDL context, about 105 KiB, while it is open.
- Unchanged Akashic failures outside this part: the collection snapshot's
  tabset case and its RUHA ABI3 test; five app-shell script checks refused
  by the stricter app-descriptor validation; the File Explorer script, whose
  load stops at its step cap; the stale Desk, app-compositor and
  batch-diagnostic scripts, which still list modules by hand; and the
  applet boundary test's check for the phrase "outside this slice, not an
  activation blocker", which the engine contract does not contain at any
  part 3 or part 4 commit.

## Artifact hashes

The kept artifacts are in
`local_testing/out/item-views-20260927/physical-desktop-la_jrjpm/`, which is
ignored.

| File | SHA-256 |
| --- | --- |
| `evidence/manifest.json` | `34a9219e6534b34088185ff30c2e64daf965a24b95161164add64f415140956a` |
| `evidence/performance-trace.json` | `b6bcdd07578bee4cade0b35125a8866d1023a9385f3290b79908b8f5864496ed` |
| `bindings.json` | `feea42a991cb0ae6049f046d2524660ed45595163a7445fad28846a1bfce5c06` |
| `supervisor.json` | `214d80b1915ebad641d2f1eee9dc65c8dc17f129f68b401786007839366818ee` |
