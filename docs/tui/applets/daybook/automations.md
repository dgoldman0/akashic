# Daybook automations

Daybook owns the system's schedules. Its first automation is the reminder:
a title that fires at a time, in a time zone, once or repeating. Reminders
fire inside Desk whether or not Daybook is open, survive restarts, and say
so when they were missed.

## Layers

| Module | Role |
|---|---|
| [`recurrence.f`](recurrence.md) | When a rule repeats: an RFC 5545 subset |
| [`automation-store.f`](automation-store.md) | The file: format, checks, atomic commits, recovery |
| [`automation-owner.f`](automation-owner.md) | What reminders mean: typed operations, firing, review |
| `automation-runner.f` | When to look, and what the clock says |
| `automation-service.f` | The Desk seam: the owner, the runner and the notice |

Time zones come from [posix-tz](../../../utils/posix-tz.md). The wall clock
is trusted only while `EPOCH-VALID?` says it is set, and intervals use
uptime (`MS@`), so setting the clock never breaks a timer.

## The runner

`DBRUN-LOOK` takes one reading of the clock: uptime, the wall clock, and
whether the wall clock is set. The caller looks once a second of uptime
(`DBRUN-PERIOD-MS`), when `DBRUN-NEXT@` comes due.

- While the wall clock is not set, a look fires nothing and writes nothing.
  Reminders wait.
- Otherwise the runner compares how far the wall clock and uptime moved
  since its last look. Both clocks count the same millisecond tick, so they
  disagree only when someone sets the clock. A difference of more than
  `DBRUN-JUMP-MS` (two seconds) is a jump.
- The first look after the runner starts, or after the clock is set, has
  nothing to compare against.

Each look passes that evidence to `DBAO-ACCEPT`: continuous, a jump, or
activation. A single occurrence seen while the clock ran continuously fires
on time. A reminder that came due across a jump, a restart or the clock
being set fires once, as missed, covering every occurrence it missed. The
owner moves the next occurrence only forward, so a clock set back fires
nothing twice.

The runner keeps the earliest due instant until the store's generation
moves, so a look with nothing due reads no reminder records.

## The service

Desk opens one service over its Practice filesystem, at
`/daybook-automations.bin`, and ticks it.

```forth
DBSVC-SIZE        ( -- bytes )
DBSVC-OPEN        ( vfs service -- status )
DBSVC-CLOSE       ( service -- )
DBSVC-TICK        ( service -- notice? )
DBSVC-NOTICE      ( service -- address length )
DBSVC-OWNER       ( service -- owner )
DBSVC-CLOCK@      ( service -- clock )
DBSVC-STATUS@     ( service -- status )
DBSVC-NOW         ( -- now )
```

- `DBSVC-TICK` reads uptime and compares it with the next look. That is
  all an idle tick does, at the same cost however many reminders there
  are. A look reads the wall clock and fires what is due. It returns true
  when it made a new notice.
- `DBSVC-NOTICE` is the latest notice: `Reminder: <title>`,
  `Missed: <title>`, or `Reminders: <title> and N more` when several fired
  together. The text stays put until the next notice, so a toast can point
  at it.
- `DBSVC-OWNER` is the [owner](automation-owner.md) for Daybook's views,
  and `DBSVC-NOW` reads the clock the way its operations take it.
- `DBSVC-CLOCK@` says what the last look saw (`DBRUN-CLOCK-SET`,
  `DBRUN-CLOCK-UNSET`, or `DBRUN-CLOCK-UNKNOWN` before the first).
  `DBSVC-STATUS@` says how the last look went.
- A blocked store still opens a working service, so Daybook can say why
  its reminders are unavailable.

## Qualification

`local_testing/test_daybook_automation_service.py` runs on the native
simulator.

The runner checks place each look exactly:
- an unset clock that writes nothing;
- an on-time firing that never repeats, even after the clock moves back an
  hour and runs past the same time;
- a three-day jump and a restart each giving one missed item;
- setting the clock again starting over;
- two seconds of disagreement counting as drift and a millisecond more as
  a jump;
- a reminder created between looks being seen at the next.

The service checks drive the simulator's real clock from the host:
- an unset clock refusing creates;
- one second at a time up to a reminder, which fires once at its second;
- the notices for one, several and missed reminders.

They also check that an idle tick writes nothing and costs the same with
1 or 49 reminders. Disabling any one of nine behaviors makes at least one
check fail: jump detection and its threshold, activation, starting over
when the clock is unset, refreshing the due time, the unset-clock guard,
waiting for the next look, and the missed and several-reminder notices.
