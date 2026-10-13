# Daybook reminders in Desk — 2026-10-10

Daybook now owns the system's first automation: the reminder. A reminder is
made in Daybook, in a time zone, once or repeating. Desk fires it whether or
not Daybook is open. It survives restarts, a firing missed while the machine
was off shows once as missed, and setting the clock back fires nothing
twice. The design is in
[automations](../../docs/tui/applets/daybook/automations.md).

This note records the runs that qualify it end to end on
`feature/daybook-scheduler`: Akashic `64c94446` with MegaPad `5f06bc22`,
whose wall clock can now be set without tearing and says whether it is set.

This is functional evidence. It is not a timing comparison with earlier
runs, and it does not cover a real device's clock, UART, panel, or touch.

## Runs

| Run | Backend and clock | Akashic tree | Result | Time | Peak RSS |
| --- | --- | --- | --- | --- | --- |
| `desktop-daybook-reminders` smoke | emulator, virtual clock | `64c94446`, clean | pass | 173.7 s | 532,588 KiB, one process |
| Desk with Daybook | simulator, host clock | `ce7ed3e7` plus the change committed as `64c94446` | pass | 155.1 s | 483,950,592 bytes, aggregate |
| Desktop journey | simulator, host clock | `64c94446`, clean | pass | 216.4 s | 518,434,816 bytes, aggregate |

The Desk-with-Daybook tree differs from `64c94446` only by documentation
and a unit test added before the commit.

Every run used MegaPad `5f06bc22` (clean). The two physical runs used its
native extension (SHA-256
`5a06333ad02eaf40b39fb67c2ce4a28069581073d625f1a6b351d212678ccbb6`),
DejaVuSansMono at 18 px, the simulator backend with
`MEGAFORTH_EXECUTOR=native`, 280x84 cells, a 0.75 s action delay, a 10 s
hold, the 900 s watchdog and the 3.5 GiB aggregate-RSS stop. All three ran
in source mode, with no compiled Forth cache, step-limit change, or timing
change, and each ran alone.

```bash
python3 local_testing/akashic_tui.py smoke --profile desktop-daybook-reminders
python3 local_testing/physical_desktop_acceptance.py \
  --akashic-root . --megapad-root ../megapad \
  --font assets/fonts/DejaVuSansMono.ttf \
  --output-parent <scratch directory> [--applet daybook]
```

## What the runs show

**The smoke (CELL, emulator).** Desk with Daybook boots with two reminders
made through Daybook's owner: "Water the plants" 90 seconds ahead, and
"Stretch" daily at 09:00 UTC. The journey moves the virtual clock, types
ordinary keys, and reads the live reminder file after each step.

- "Water the plants" fired once, on time, with its toast (store
  generation 3).
- The reminders view marked that firing reviewed, then paused and resumed
  "Stretch".
- "Feed the cat", made through Daybook's three prompts for the minute three
  minutes on, daily, in the default zone, fired on time.
- Setting the clock back six minutes and letting seven pass wrote nothing.
- Setting it two days ahead gave one missed item covering two occurrences.
- A second machine booted from the disk as it then was showed the same next
  firing and missed item. The store stayed at generation 11 through its
  boot.
- Desk's idle load was 0.7% of the clock over 7.6 virtual seconds, under
  the profile's 10% ceiling.

**Desk with Daybook (rich).** Its boot makes the same two reminders, with
the one-off two minutes ahead on the simulator's real-time clock. The usual
Daybook journey checked its task at 44 s, then waited for the reminder. At
142 s a frame showed "Reminder: Water the plants" on the bottom row, both in
the rich projection rebuilt from retained draws and in CELL. The capture
`daybook-reminder-notice-retained-only.png` shows the whole Desk frame from
the retained scene alone, with the toast centred on the taskbar row beside
the semantic Daybook task. The toast is Desk's ordinary overlay, and the
rich path needed no change. Afterwards the run's disk held the reminder file
at generation 3: "Water the plants" completed, with one on-time firing on a
continuous clock awaiting review.

**Desktop journey.** The canonical journey passed with the same 48
milestones and 51 inputs as the 2026-09-28 runs. Desk now opens the reminder
service and ticks it in every run. With no reminders, the disk has no
reminder file afterwards, so the service wrote nothing.

## Not covered

- Setting the clock on a device. There is no network time and no set-clock
  screen yet. The simulator and hybrid servers seed the clock from the host,
  and the emulator's server runs it in real time.
- Two cores reading the RTC at once can tear a value, because the chip's
  cores share one read latch.
- The rest of the contract's Gate 14: actions other than reminders, the
  broker and its Practice permission, Agent triggers, Run Now, and raw
  export and repair.
