# Daybook's agenda and Streams' cards as item views — 2026-09-28

Part 4 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Lists and trees", met its "done when" on 2026-09-27
([item-views-journey-20260927.md](item-views-journey-20260927.md)). Its
remaining consumers were Daybook's agenda, Streams' cards and the Agent
transcript, with Library as the design check. This note records the first
two, the Library check, and why the Agent transcript is not done.

Daybook's agenda is now a canonical list in sections, with check boxes,
published as a `SECTIONS` item view (Akashic `d6bfab6`). Streams' timeline
and context view are card lists, published as `CARDS` item views whose post
text carries `LINK` style runs over web links (Akashic `167ba89e`). The
canonical physical Desktop journey passed at both commits as regression.
Desk with only Daybook, and Desk with only Streams, checked the new work
through the physical viewer, including item `CHECK`, `SELECT` and `OPEN`
events.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Runs

| Run | Akashic tree | Result | Time | Peak aggregate RSS | Milestones / inputs |
| --- | --- | --- | --- | --- | --- |
| Desk with Daybook | `65c79c5` plus the change committed as `d6bfab6` | pass | 67.1 s | 472,068,096 bytes | 9 / 8 |
| Desktop journey | `d6bfab6`, clean | pass | 212.0 s | 514,514,944 bytes | 48 / 51 |
| Desk with Streams | `d6bfab6` plus the change committed as `167ba89e` | pass | 75.3 s | 462,041,088 bytes | 3 / 2 |
| Desktop journey | `167ba89e`, clean | pass | 209.6 s | 492,568,576 bytes | 48 / 51 |

The Streams check's tree differs from `167ba89e` only by an argument the
harness ignores, removed before the commit.

Every run used MegaPad `465a6ad` (clean), its native extension qualified on
2026-09-17 (SHA-256 `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c`),
DejaVuSansMono at 18 px with part 3's styled faces and fallback fonts, the
simulator backend with `MEGAFORTH_EXECUTOR=native`, 280x84 cells, a 0.75 s
action delay, a 10 s hold, the 900 s watchdog and the 3.5 GiB
aggregate-RSS stop. All ran in ordinary source mode, with no compiled Forth
cache, step-limit change, or timing change. The launcher requires clean
trees for the Desktop journey, and both were clean at launch and at exit.
The single-applet checks are development checks and allow a changed tree.

```bash
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent <scratch directory> [--applet daybook|streams]
```

## What the runs show

**Daybook.** Desk with Daybook adds a mixed-script task through the prompt,
as in part 3. The agenda is then a `SECTIONS` item view with `SCHEDULE`,
`TASKS` and `NOTES` headings, and the new task is an unchecked checkable
item under `TASKS`. A `CHECK` on it (`item_check` on its key, 20) marked it
done: the view reported it `CHECKED` and CELL showed `[x]`. In the Desktop
journey the agenda is rich as well, and the journey finds the added task in
its item view.

**Streams.** Desk with Streams starts Streams in the tile with a fixed
three-post feed (`local_testing/fixtures/streams/desk-timeline.json`),
loaded through the same entry an injected source uses. The timeline is a
`CARDS` item view of three text columns. Each card carries the author and
time, the post text, and `reply` for the reply. The first post's text has
one `LINK` run over `https://example.test/streams/fixtures`, with the
sentence's closing full stop outside it, and no other field is styled. A
`SELECT` on the reply's card selected it without opening anything. An
`OPEN` on it opened its context: a second `CARDS` view holding only the
thread's two posts, with the reply selected. CELL showed the cards and the
context heading throughout. The captures `streams-cards-shown` and
`streams-context-opened` show the cards with separators, the link
underlined in the link colour, and the selected card highlighted.

The Desktop journey does not show Streams' cards. There Streams is a
built-in without a tile or a feed.

Both Desktop journeys sent the same 48 milestones and 51 inputs as the
2026-09-27 run, with its five item events: `SELECT` and `OPEN` in the
launcher, and `SCROLL`, `SELECT` and `OPEN` in File Explorer's table.

## Checks before the runs

- Unit and structure tests: the list widget's sections, check boxes and
  cards, its capture with style runs and untrusted text, and its pointer
  and key input (`test_semantic_item_views.py`, `test_widget_pointer.py`,
  46 tests with the syntax tests); `SYN-SCAN-URLS` (`test_syntax_styles.py`);
  the single-applet journeys over synthetic frames
  (`test_rich_terminal_applet_journeys.py`, 11 tests); and the refactor
  ratchet (`test_refactor_inventory.py`, 18 tests).
- Streams' contract profiles, which now drive the cards with key events
  and read the lists' scroll state: `streams-contracts` (579 checks),
  `streams-source-ui-contracts` (111), `streams-persistence-contracts`
  (108), `streams-source-owner-contracts` (392), `streams-draft-contracts`
  (277) and `streams-xio-contracts` (312) all pass.
- Guest cost in the standalone Streams app, in steps from a key to its
  screen change: opening a context took 57.8 M and 49.8 M steps (painted
  cards: 63.0 M and 47.0 M), returning to the timeline 50.0 M twice
  (47.0 M and 46.8 M), and opening search 36.3 M (36.0 M). The card lists
  cost about 6% more on a view switch.

## Defects found on the way

- The list's card drawing word ticked a callback defined later in the file.
  KDOS's tick prints nothing for an unknown word, so the list compiled and
  its first draw reset the machine. The callbacks now come first.
- Showing a row in a list too short to show one whole row scrolled past the
  row. It now starts the view at the row, as Streams' compact layout with
  its draft footer needs.
- The first version of Streams' card sync showed the list's own, stale
  selection when the list's height changed. The contract profile caught it;
  the sync now shows the selection it takes from Streams.
- Seven modules outside this part free memory with `FREE DROP`, although
  KDOS's `FREE` returns nothing, so each drops a cell it does not own:
  `game/ecs.f`, `game/systems.f`, `render/qoi.f`,
  `render/visualization/meter.f`, `waveform.f` and `spectrum.f`, and
  `tui/applets/streams/atproto-authenticated-provider.f`. They are not
  fixed here. The tree widget had the same defect and was fixed with File
  Explorer (`e06b36a`).

## Library design check

Library draws its record lists by hand: the corpus (kind, archived mark,
title), collections (title and member count) and retained history
(revision and bytes), one query page at a time, beside a preview pane. The
item-view family fits them without change. Each list is a `TABLE` of text
and number columns over the page's rows. A `SELECT` drives the preview, and
an `OPEN` does what Enter does, filtering the corpus by a collection. The
archived mark is a column, not `UNAVAILABLE`, because archived records stay
readable.

Two limits showed. An item view carries one page as its whole order, so a
renderer cannot tell that more pages exist or scroll into the next; page
turning stays with Library's own keys and menu, as in CELL. No ordinary use
needs more yet. And the preview is wrapped document text, which belongs to
part 3's text areas, not to item views. The Agent transcript has the same
need.

## The Agent transcript is not done

The Agent wraps each message to the tile's width, and its approval review
unlocks Approve only after the user has paged through every operand row it
drew. `CARDS` put each field on one line, so a message card would show only
its first line, and a renderer that wrapped the text itself would break the
row count the review relies on. Publishing the transcript needs a choice:
extend `ITM1` with wrapped card fields and move the review's rule onto
items, or show the transcript through part 3's text-area family with the
Agent's own wrapped rows. That choice is left to the project owner.

## Not covered

- The Agent transcript, as above.
- Streams in the Desktop journey, where it has no tile.
- A `SCROLL` on cards: the fixed feed fits the tile. File Explorer's table
  covers item `SCROLL` in the Desktop journey, and unit tests cover it for
  cards.
- Failures that were the same before these changes: the standalone Streams
  and `desktop-streams` smokes, whose wall-clock waits expire while the
  guest repaints; `streams-page-contracts` assertion 52;
  `streams-manual-refresh-contracts`, which prints nothing within its 120 s;
  the gate-0 baseline test, which finds the workspace
  `DESK_ECOSYSTEM_CONTRACT.md` changed on 2026-09-26; the applet boundary
  test's phrase check; and the older failures listed in the 2026-09-27 note.

## Artifact hashes

The kept artifacts are in `local_testing/out/item-views-daybook-20260927/`
(the Desktop journey at `d6bfab6`) and
`local_testing/out/item-views-consumers-20260928/` (the other three runs),
both ignored.

| Run | File | SHA-256 |
| --- | --- | --- |
| Desk with Daybook (`physical-desktop-oqyua9dv`) | `evidence/manifest.json` | `a23300872270de17b8de21204ba4df51eab742d809baef324e3cafa5540b7755` |
| | `bindings.json` | `1ec6f29f0f67b6f6c43c1d11bb475d946ab2f63e2cc0581943297f721b7df5e1` |
| | `supervisor.json` | `fe3943413f8d38a6a256aed78de04dcffee9e1af685b3c48d2025c6b218ff38e` |
| Desktop journey at `d6bfab6` (`physical-desktop-_r66sfdy`) | `evidence/manifest.json` | `6e7589f7034adcfeec079471185978d58b0351c78cd27d046b81baaa80a49ebb` |
| | `bindings.json` | `c2d8c9bbc356b255165f57b33d1f43c211741f071087a34d178cf3b23a330994` |
| | `supervisor.json` | `224c65b27feeac6fc930f98ce0ca98560b54c9bc23ff278199364204eaa30766` |
| Desk with Streams (`physical-desktop-36gkc8uq`) | `evidence/manifest.json` | `2730a8e23442abcdd85a36e7afc74d2c083fe574d1fdb712601d92cccb7ff4e2` |
| | `bindings.json` | `b1603f5295f2acb22631377f105d4c245f1915d16c8fb25b96bc8bbd6c05dc4d` |
| | `supervisor.json` | `1f3cee71a9b41f7772edb3ad2358ddd448feb938f60d664645c14c6dcfc6c676` |
| Desktop journey at `167ba89e` (`physical-desktop-1r2so1zj`) | `evidence/manifest.json` | `da51c3c13281e3969921f2a6cd218d05a57d9daf5c1c373abac124b85b02a148` |
| | `bindings.json` | `436435fa5345cc0920cd9ce760f59feaa6bd1c419849542b0345c892678dbedb` |
| | `supervisor.json` | `e3b175b9496732d68b73c6a604478a197fcbeb998fc18f332427f5fc82b56ad9` |
