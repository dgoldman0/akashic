# The Agent transcript as a card log — 2026-09-28

Part 4 of the [rich experience plan](../../docs/rich-terminal/RICH-EXPERIENCE-PLAN.md),
"Lists and trees", left the Agent transcript as its last consumer
([item-views-consumers-20260928.md](item-views-consumers-20260928.md)).
This note records it. The transcript is now the canonical card list in log
mode, with each message's text in a wrapping column (Akashic `d4e56c1a`).
The approval review is a dialog of its own over the transcript. Desk with
only the Agent checked the work through the physical viewer, and the
canonical physical Desktop journey passed as regression.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Runs

| Run | Akashic tree | Result | Time | Peak aggregate RSS | Milestones / inputs |
| --- | --- | --- | --- | --- | --- |
| Desk with the Agent | `d4e56c1a` plus the changes committed as `8dbf9908` and `fe25bf15` | pass | 73.0 s | 473,432,064 bytes | 7 / 6 |
| Desktop journey | `fe25bf15`, clean | pass | 240.6 s | 493,359,104 bytes | 48 / 51 |

An earlier run of the Desk-with-Agent check failed, and it found a defect,
fixed in `8dbf9908`: a review short enough to fit its dialog kept the
footer "F6 locked" after the dialog had shown its last row. The unlock was
recorded after the footer was drawn, and the redraw that should have
followed waited for a tick that Desk does not give a clean slot. The
dialog now settles the unlock before it draws the footer. The only change
between the two runs is that fix and its smoke check.

Both runs used MegaPad `10916b9` (clean), its native extension qualified
on 2026-09-17 (SHA-256 `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c`),
DejaVuSansMono at 18 px with part 3's styled faces and fallback fonts, the
simulator backend with `MEGAFORTH_EXECUTOR=native`, 280x84 cells, a 0.75 s
action delay, a 10 s hold, the 900 s watchdog and the 3.5 GiB
aggregate-RSS stop. Both ran in ordinary source mode, with no compiled
Forth cache, step-limit change, or timing change. The Desktop journey's
trees were clean at launch and at exit. The single-applet check is a
development check and allows a changed tree.

```bash
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent <scratch directory> [--applet agent]
```

## What the runs show

**Desk with the Agent.** The Agent starts from a long stored conversation,
saved at boot through its own conversation store
(`local_testing/agent_transcript.py`): a question, and an answer with a
long wrapping paragraph, a line with dashes and curly quotes, a
right-to-left line, ninety numbered lines and a last line. The transcript
is a `CARDS` item view of two text columns, the second marked `WRAP`. Each
card's header is its role, styled `HEADING`, and no card is selected. The
answer is taller than the 80-row view, so the view starts inside it, with
the viewport row saying how many of its rows are above. By MegaPad's own
card row count the view ended with the transcript, and CELL showed "End of
the long answer." on the view's last row.

One wheel detent, sent as an item `SCROLL`, moved the view exactly three
rows up; CELL then showed "Step 88" on the last row. End returned the view
to the end. Ctrl+L opened the Ask prompt, and the request "approval check"
made the demo provider ask for approval. While the prompt and then the
review dialog were open, the Agent's menu and transcript were withheld, as
foreground paint requires, and CELL showed them. The dialog showed the
request, "Persist the simulated change?", and "Provider approval request
(no local tool envelope)"; it fits the panel, so its first frame showed
the last row and its footer said "[F6] Approve once". F6 approved. The
transcript then ended with the request, the reply ending "Approved.", the
review, and the approval record, and the view followed the end.

The captures `agent-transcript-at-end` and `agent-review-approved` show
the rich cards: role headings in the heading colour, a rule between
cards, and each text indented under its header. `agent-review-unlocked`
shows the dialog, drawn by CELL over the whole panel.

**Desktop journey.** It sent the same 48 milestones and 51 inputs as the
earlier runs of 2026-09-27 and 2026-09-28. The Agent's tile there starts
with an empty conversation, so the journey shows no transcript.

## Not covered

The Desk Agent smoke journeys `desktop-agent` and
`desktop-agent-hardening` stop early, on this commit and on the commit
before the transcript work, for a separate reason: the Access menu's
dropdown is cut off at the Agent tile's right edge, so "Read-only" never
shows in full. The review dialog's lock over a review longer than the
dialog is covered by the agent-ui smoke's dialog contract, not by the
physical run, whose review fits.
