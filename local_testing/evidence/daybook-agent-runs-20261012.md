# Scheduled Agent runs in Desk — 2026-10-12

A Daybook schedule can now start one bounded Agent run at a chosen time.
The run uses the model the schedule names, under a permission that Desk's
user approved and can see and revoke. It runs whether or not Daybook and
the Agent are open. This is step 1 of the second Daybook scheduler slice,
prompt-only runs; step 2, one exact document as context, comes next. The
design is in [automations](../../docs/tui/applets/daybook/automations.md),
[scheduled actions](../../docs/interop/scheduled-actions.md) and the
Agent's [dispatcher](../../docs/tui/applets/agent/dispatch.md).

This note records the runs that qualify step 1 end to end on
`feature/daybook-scheduler`: Akashic `5679fd5f` with MegaPad `5f06bc22`.
MegaPad did not change in this slice.

This is functional evidence. It is not a timing comparison with earlier
runs, and it covers neither a real device nor a real model provider.

## Runs

| Run | Backend and clock | Akashic tree | Result | Time | Peak RSS |
| --- | --- | --- | --- | --- | --- |
| `desktop-daybook-agent` smoke | emulator, virtual clock | `5679fd5f`, clean | pass | 202.9 s | 314,384 KiB, one process |
| `desktop-daybook-agent-recovery` smoke | emulator, virtual clock | `5679fd5f`'s content, before its commit | pass | 236.4 s | 753,660 KiB, one process with its relaunches |
| `desktop-daybook-reminders` smoke | emulator, virtual clock | `5679fd5f`'s content, before its commit | pass | 182.7 s | 533,992 KiB, one process |
| Desk with the Agent | simulator, host clock | `5679fd5f`, clean | pass | 57.1 s | 487,927,808 bytes, aggregate |
| Desk with Daybook | simulator, host clock | `5679fd5f`, clean | pass | 158.6 s | 499,159,040 bytes, aggregate |
| Desktop journey | simulator, host clock | `5679fd5f`, clean | pass | 215.0 s | 557,592,576 bytes, aggregate |

The two smokes run before the commit used exactly the files it holds; only
the commit message came after them.

Every run used MegaPad `5f06bc22` (clean). The three physical runs used its
native extension (SHA-256
`5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6`),
DejaVuSansMono at 18 px, the simulator backend with the native executor,
a 0.75 s action delay, a 10 s hold, the 900 s watchdog and the 3.5 GiB
aggregate-RSS stop. All six ran in source mode, with no compiled Forth
cache, step-limit change, or timing change, and each ran alone.

```bash
python3 local_testing/akashic_tui.py smoke --profile desktop-daybook-agent
python3 local_testing/akashic_tui.py smoke --profile desktop-daybook-agent-recovery
python3 local_testing/akashic_tui.py smoke --profile desktop-daybook-reminders
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent <scratch directory> [--applet agent | --applet daybook]
```

## What the runs show

**The Agent smoke (CELL, emulator).** Desk runs with Daybook and the Agent.
The Agent's development device-flow source gives the scripted provider a
signed-in account and a catalog of two models: gpt-fast ("Swift") and
gpt-slow ("Deliberate"). The journey types ordinary keys, moves the virtual
clock, and reads Daybook's live automation file after each step.

- Daybook made "Morning brief": daily, three minutes ahead, on gpt-slow at
  high effort, the priority tier and medium verbosity, with ten minutes,
  16,384 bytes of reply and a two-line prompt of 101 bytes. Desk's approval
  named all of it, disclosed exactly the prompt's bytes, and unlocked Allow
  only once read to the end. After A, Daybook's file held exactly those
  operands, approved, and Alt+P listed the permission.
- The run's details named its model and limits in the approval's words.
- With Daybook and the Agent idle, the run fired on time and completed.
  Daybook kept one item with the run's identity and summary, and the
  Agent's scheduled runs (F5) listed it on gpt-slow.
- A chat run that lingers held the next run, due on time. The run waited,
  chat could not send ahead of it, and once Escape cancelled the chat it
  ran next and completed as a run of its own.
- Setting the clock back over that run started nothing. Paused, the run
  started nothing when its time passed, and resuming it skipped what fell
  in between. A jump two days ahead started nothing and left one missed
  item covering both occurrences, for review.
- "Task sweep", once, on gpt-fast, whose prompt asks for a task, stopped for
  review because its model asked to use a tool. Daybook's file, its
  automations, the run's details and the Agent's runs all said so.
- Desk's idle load was then 0.8% of the clock, under the 10% ceiling.

**The recovery smoke (CELL, emulator, three machines).** One lingering run
on gpt-fast ends every way other than by itself.

- The permission file held none of the run's words: not its title, prompt
  or model.
- While the run ran, chat refused to send, and Alt+Q asked before shutting
  down; Keep running kept the run. The disk was kept as it then was, as a
  power loss would leave it. Revoking the permission cancelled the run.
- A second machine booted that disk. The Agent ended the run it found in
  flight as indeterminate, interrupted; Daybook adopted that end; boot
  started nothing. Run by hand there, the run made Alt+Q ask again, and
  Shut down cancelled it as Desk closed.
- A third machine booted the disk Desk left. Daybook and the Agent showed
  that run cancelled because Desk shut down, beside the interrupted run,
  and Daybook's file held those two runs and no other. Deleting the
  schedule waited until the interrupted run was reviewed, then left a
  tombstone and a short record of each run, with its run and how it ended
  but no summary. The Agent kept both runs. Alt+P listed the kept
  permission as for "A schedule Daybook no longer has", and R revoked it.

**The reminders smoke** passed as in slice 1, with its restart now on the
relaunch the recovery smoke shares: generation 3 at the firing, 11 through
the restart, and 0.7% idle load.

**Desk with the Agent (rich).** The Agent-alone journey on the rich
terminal passed: its stored transcript, a wheel scroll, End, the Ask
prompt, the approval review and F6. The Agent now holds a dispatcher, a
conversation per scheduled run and a scheduled-runs view, and the journey
needed no change.

**Desk with Daybook (rich).** The Daybook-alone journey passed: its agenda
and task, and the reminder that fires two minutes after boot, shown in the
rich frame and in CELL. Daybook's automations view now makes Agent runs and
shows a schedule's details, and the journey needed no change.

**Desktop journey.** The canonical journey passed with the same 48
milestones and 51 inputs as the 2026-09-28 runs. Desk now hosts the schedule
broker, the Agent's dispatcher and the permission store in every run, and
none of them changed what the journey sees.

## Not covered

- Step 2: one exact document as a run's context.
- A real model provider. Scheduled runs ran on the scripted provider. The
  OpenAI and Codex providers honour a run's model only in their unit
  tests.
- A real device's clock, UART, panel or touch, and setting the clock on a
  device.
- The Agent's scheduled-runs view on the rich terminal. The rich Agent
  journey does not open it, and a run to list would need Daybook beside
  the Agent.
- An unavailable model, a prompt too large for the provider, and a
  signed-out Agent. Unit tests show the dispatcher refusing each before it
  starts, with its reason, and Daybook keeping a refused run for review.
- Long prompts. A 100,000-byte prompt round-trips through Daybook's create
  and store in a unit test; the smoke's prompt is 101 bytes.
- More than one Agent run at a time, which is its own project.
- Daybook's automations list gives a row's detail a fixed 32 cells, so a
  long detail is cut even in full frame. A run's details page shows it
  whole.
