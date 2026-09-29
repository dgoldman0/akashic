# Desk refusals: a screen that cannot be rich shows as CELL — 2026-09-28

Before this work, a completed draw that could not be shown rich could stop
Desk. Once a rich session was open, a screen whose retained text, controls
or glyphs did not fit the terminal's limits ended in a publisher fault.
Before a session opened, the same refusal turned the rich path off for
good. Two defects also turned ordinary refusals into faults. This note
records the three changes and the physical runs that checked them.

The first defect was in the hybrid adapter (Akashic `0c5a77ab`). When Desk
reused a window's earlier capture and the reused slice no longer fit the
snapshot banks, the whole snapshot was refused as `CAPACITY`. That window
is now captured afresh, so it falls back to CELL on its own, like any other
family refusal.

The second was in the screen producer (`12c1036d`). It reported every
refused residual glyph plan as `INVALID`, a broken contract. It now keeps
the planner's reason: `CAPACITY` stays `CAPACITY`, and a cell the retained
plane cannot show, blinking or wider than a glyph run, becomes
`UNAVAILABLE`. The plan was to size the glyph text bank from what the
screen can hold instead. The screen's cluster pool has no fixed bound, so
no size always fits, and a screen beyond four bytes a cell is a screen that
cannot be shown rich.

The third change (`a39ce973`) is the rule for such a screen, now in section
3 of [AKASHIC-RICH-TERMINAL.md](../../docs/rich-terminal/AKASHIC-RICH-TERMINAL.md).
The producer records the refused draw and does not build it again. Before
an owner opens, it keeps waiting for a newer draw. Once an owner is open,
the rich frame is replaced by an empty one: a hidden replacement with no
operations is sealed and published while the CELL offer waits, and its
reveal is carried with the CELL frame. The newer CELL frame and the empty
retained scene therefore appear at one boundary, and no newer CELL frame
shows under the older rich one. The owner stays open with nothing retained,
CELL shows each draw, and the first later draw that fits goes back through
a full hidden replacement and reveal. A snapshot with no visible document
to publish is such a draw; before, it was treated as backpressure and could
hold CELL back.

This is functional evidence. It is not a timing comparison with earlier
runs, and not UART, panel, or touch evidence.

## Runs

| Run | Akashic tree | Result | Time | Peak aggregate RSS | Milestones / inputs |
| --- | --- | --- | --- | --- | --- |
| Small terminal | `12c1036d` plus the changes committed as `a39ce973` | pass | 66.3 s | 459,907,072 bytes | 7 / 6 |
| Desktop journey | `a39ce973`, clean | pass | 234.4 s | 482,037,760 bytes | 48 / 51 |

After the small-terminal run, one sentence was added to the design doc
before the commit. With that sentence taken out, `a39ce973` gives the
run's recorded hash of uncommitted changes exactly, so the run checked
the committed code.

An earlier small-terminal run failed in the runner, not in Desk. The runner
required non-black retained pixels in every frame, and an empty retained
scene has none. It now requires them only in frames with retained regions,
and it rebuilds an empty scene's text from CELL only for a journey that
says it expects one.

Both runs used MegaPad `10916b9` (clean), its native extension qualified
on 2026-09-17 (SHA-256 `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c`),
DejaVuSansMono at 18 px with the styled faces and fallback fonts, the
simulator backend with `MEGAFORTH_EXECUTOR=native`, 280x84 cells, a 0.75 s
action delay, a 10 s hold, the 900 s watchdog and the 3.5 GiB
aggregate-RSS stop. Both ran in ordinary source mode, with no compiled
Forth cache, step-limit change, or timing change.

```bash
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent <scratch directory> [--applet small-terminal]
```

## What the runs show

**Small terminal.** This check is Desk with Pad, as in the Pad check, on a
terminal that allows 5,120 bytes of retained UTF-8 text instead of Desk's
worst case. Pad's empty editor fits. The Open prompt does not, because
while it is open Pad's controls are withheld and the whole screen is left
to residual glyphs. A 48-line file does not fit either. The two-line
`example.f` fits again.

| Milestone | Offer | CELL revision | Retained revision | Retained draws |
| --- | --- | --- | --- | --- |
| `small-terminal-pad-rich` | 1 | 4 | 4 | 489 |
| `small-terminal-prompt-shown-as-cell` | 3 | 6 | 6 | 0 |
| `small-terminal-large-path-typed` | 5 | 8 | 6 | 0 |
| `small-terminal-large-file-shown-as-cell` | 6 | 9 | 6 | 0 |
| `small-terminal-prompt-shown-again` | 7 | 10 | 6 | 0 |
| `small-terminal-example-path-typed` | 9 | 12 | 6 | 0 |
| `small-terminal-rich-again` | 11 | 14 | 14 | 489 |

At offer 3 both revisions are 6. The empty retained scene and the prompt's
CELL frame appeared at one acknowledged boundary. From offer 5 to offer 9
CELL moves on while the retained revision stays at 6, so nothing retained
was sent while CELL showed each screen. At offer 11 the two revisions meet
again at 14. The editor is back as two new `TEXT_AREA` controls under the
same owner, owner 1 generation 1, so the session was never closed or
reopened. Each input went out only after the exact frame before it had
been composited and acknowledged.

The captures `small-terminal-large-file-shown-as-cell` and
`small-terminal-rich-again` show the difference. The first has CELL's flat
tabs and dashed rule over the 48-line file. The second has the rich menu
and tabs, with `example.f` in the editor.

**Desktop journey.** It sent the same 48 milestones and 51 inputs as the
earlier runs of 2026-09-27 and 2026-09-28, and its trees were clean at
launch and at exit. Every frame carried retained draws, from 709 to
1,038, so no screen of the ordinary journey was refused and the rich
path it takes is unchanged.

Tests without the viewer cover the parts a physical run cannot reach
directly. `test_rich_blank_frame.py` runs the blank path's own words in
MegaForth with the engine stubbed: a refused draw asks for the empty frame
and holds CELL, the empty frame is sealed, revealed, and retires the rich
frame's input targets, and with nothing retained CELL shows each draw until
one fits. The adapter's reuse test runs the reuse fallback, and the
producer tests check each glyph build keeps the planner's reason.

## Not covered

Nothing here lets Desk ask the terminal for more room. The terminal
announces its limits when a session opens and they stay fixed for that
session, so a screen beyond them can only be shown as CELL. A request that
the terminal answers yes or no is a separate item.

A refusal before an owner opens is checked only by a structural producer
test, which reads the source. Neither a physical run nor an executable
test runs it.

The survey that led to this work also found a limit that is not fixed
here. The adapter's document records are sized by `_DESK-MAX-INSTALLED`, 32
installed applet types, not by the number of open UIDL documents. Every
open window, the launcher and each dialog take one, so a 33rd open document
fails to launch (`RUHA-ATTACH` returns `RUHA-S-UNAVAILABLE`). No draw is
refused. The ANSI Desk has no such limit. This was found by reading the
code and has not been run.
