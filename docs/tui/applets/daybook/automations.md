# Daybook automations

Daybook owns the system's schedules. A schedule fires at a time, in a time
zone, once or repeating, and does one action from the
[catalog](../../../interop/scheduled-actions.md):
- a reminder, a title that comes due for review;
- an Agent run: one bounded run of a model the schedule names, with its
  prompt, started by Desk's broker under a schedule permission you approve.

Schedules fire inside Desk whether or not Daybook is open, survive
restarts, and say so when they were missed.

The Agent run is being built in steps. Today the store, the owner and the
service carry it whole, and the service hands runs to a broker through the
dispatch client, but Desk does not give the service a broker yet. Until it
does, a due Agent run ends at once for review, blocked as the Agent being
unavailable.

## Layers

| Module | Role |
|---|---|
| [`recurrence.f`](recurrence.md) | When a rule repeats: an RFC 5545 subset |
| [`automation-store.f`](automation-store.md) | The file: format, checks, atomic commits, recovery |
| [`automation-owner.f`](automation-owner.md) | What schedules mean: typed operations, firing, approval, runs, review |
| `automation-runner.f` | When to look, and what the clock says |
| `automation-service.f` | The Desk seam: the owner, the runner and the notice |
| `reminders.f` | Daybook's view of the reminders, and the create steps |

Time zones come from [posix-tz](../../../utils/posix-tz.md). The wall clock
is trusted only while `EPOCH-VALID?` says it is set, and intervals use
uptime (`MS@`), so setting the clock never breaks a timer.

Desk opens the service, ticks it and shows its notices (see
[Desk](../desk/desk.md)). Daybook shows the reminders, and makes and changes
them, in its reminders view (see [Daybook](daybook.md)). The service and
the owner never import Desk or Agent code: an Agent run reaches Desk only
through the portable [dispatch contract](../../../interop/scheduled-actions.md).

## The runner

`DBRUN-LOOK` takes one reading of the clock: uptime, the wall clock, and
whether the wall clock is set. The caller looks once a second of uptime
(`DBRUN-PERIOD-MS`), when `DBRUN-NEXT@` comes due.

- While the wall clock is not set, a look finds nothing due and writes
  nothing. Schedules wait.
- Otherwise the runner compares how far the wall clock and uptime moved
  since its last look. Both clocks count the same millisecond tick, so they
  disagree only when someone sets the clock. A difference of more than
  `DBRUN-JUMP-MS` (two seconds) is a jump.
- The first look after the runner starts, or after the clock is set, has
  nothing to compare against.

A look returns that evidence, continuous, a jump, or activation, and
whether anything is due. The service then accepts each due schedule with
it (see [the owner](automation-owner.md#firing)). A single occurrence seen
while the clock ran continuously fires on time. A schedule that came due
across a jump, a restart or the clock being set fires once, as missed,
covering every occurrence it missed. The owner moves the next occurrence
only forward, so a clock set back fires nothing twice.

The runner keeps the earliest due instant until the store's generation
moves, so a look with nothing due reads no schedule records.

## The service

Desk opens one service over its Practice filesystem, at
`/daybook-automations.bin`, ticks it, and lends it to Daybook alone.

```forth
DBSVC-SIZE        ( -- bytes )
DBSVC-OPEN        ( vfs service -- status )
DBSVC-CLOSE       ( service -- )
DBSVC-CLIENT!     ( client service -- )
DBSVC-TICK        ( service -- notice? )
DBSVC-NOTICE      ( service -- address length )
DBSVC-OWNER       ( service -- owner )
DBSVC-CLOCK@      ( service -- clock )
DBSVC-STATUS@     ( service -- status )
DBSVC-NOW         ( -- now )
DBSVC-IN-FLIGHT?  ( service -- flag )
DBSVC-RUN-NOW     ( rid revision service -- id status )
DBSVC-CANCEL      ( id service -- status )
DBSVC-ASK         ( rid revision service -- status )
DBSVC-ASK-STATE@  ( service -- state )
DBSVC-ASK-RID     ( service -- rid )
DBSVC-MODELS      ( buffer capacity service -- bytes status )
```

- `DBSVC-TICK` reads uptime and compares it with the next look. That is
  all an idle tick does, at the same cost however many schedules there
  are. A look reads the wall clock and accepts what is due, a page of
  schedules at a time, each committed on its own; then it asks after runs
  in flight (see below). It returns true when it made a new notice. A
  failed accept stops the look, and the next look tries again.
- `DBSVC-NOTICE` is the latest notice: `Reminder: <title>`,
  `Missed: <title>`, `Agent run: <title>` for a run handed over, `Agent run
  done: <title>` for one that completed, or `Needs review: <title>` for one
  that ended otherwise. When several came due together it is `Reminders:
  <title> and N more`, or `Automations: ...` when not all were reminders. A
  look that accepted nothing but saw a run end makes that run's notice. The
  text stays put until the next notice, so a toast can point at it.
- `DBSVC-OWNER` is the [owner](automation-owner.md) for Daybook's views,
  and `DBSVC-NOW` reads the clock the way its operations take it.
- `DBSVC-CLOCK@` says what the last look saw (`DBRUN-CLOCK-SET`,
  `DBRUN-CLOCK-UNSET`, or `DBRUN-CLOCK-UNKNOWN` before the first).
  `DBSVC-STATUS@` says how the last look went.
- A blocked store still opens a working service, so Daybook can say why
  its reminders are unavailable.

### Handing runs to Desk's broker

Desk gives the service a dispatch client with `DBSVC-CLIENT!` (see
[the dispatch contract](../../../interop/scheduled-actions.md#the-client));
Daybook imports no Desk or Agent code. Without a client the Agent is
unavailable.

Each request the service builds carries the schedule's title, a trigger
naming when it runs in words (`DBREC-DESCRIBE` and its zone), its operands,
its store, RID and revision, the permission and Practice Daybook holds, and
both digests; a hand-over also names the occurrence, its kind and its
dispatch key. Requests and responses live in buffers the service grows to
what they need.

- **Standing.** Before an Agent run is accepted, the service asks the
  broker how its permission stands. Without a broker it is unavailable; a
  schedule Daybook does not hold approved has none, without asking.
- **Hand-over.** An accepted run is handed over at once. The broker
  answers that it started, that it waits behind another run, or that it
  ended; one it cannot take ends for review, as the Agent being
  unavailable, or as invalid.
- **Following.** While runs are in flight, each look asks the broker how
  each stands, and records when it starts and how it ends. A run the
  broker does not know never started, if it had not, or is indeterminate,
  if it had; this also settles runs left in flight when Desk last stopped.
  A broker that cannot answer now is asked again at the next look. A
  summary larger than the response is asked for again with room for it.
  `DBSVC-IN-FLIGHT?` says whether any run is in flight, for Desk to ask
  before shutting down.
- **By hand.** `DBSVC-RUN-NOW` asks the owner for a run by hand and hands
  it over. `DBSVC-CANCEL` asks the broker to cancel a run in flight; the
  end comes with a later look, and a run the broker does not know ends at
  once, cancelled.
- **Approval.** `DBSVC-ASK` asks the broker to have the user approve a
  schedule at the revision Daybook shows. One approval is asked for at a
  time. Each look polls for the answer: an approval Daybook records
  (`DBAO-AUTHORIZE`) at that revision, a refusal, or a request withdrawn
  unanswered. `DBSVC-ASK-STATE@` says how it stands, and `DBSVC-ASK-RID`
  which schedule it is for. An approval that comes after the schedule
  changed is not recorded.
- **Models.** `DBSVC-MODELS` fetches the list of models a schedule may
  name, as the broker gives it.

Nothing is retried on its own.

| Status | Meaning |
|---|---|
| `DBSVC-S-UNAVAILABLE` | The broker cannot be reached |
| `DBSVC-S-PENDING` | An approval is already being asked for |

Other statuses are the owner's.

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
- the notices for one, several and missed reminders;
- an Agent run with no broker needing review, and the notice when it comes
  due with a reminder.

`local_testing/test_daybook_automation_dispatch.py` puts a scripted fake
broker behind the client and follows due runs through its answers:
- handed over and followed to its end, and the request the broker saw;
- waiting, then started, then failed;
- a hand-over the broker cannot take, finds invalid, or refuses;
- standings that block a run, a check that cannot be answered, and a
  schedule not held approved;
- runs left in flight after a restart, settled by what the broker knows;
- Run Now and cancelling, and their refusals;
- asking for an approval: pending, allowed, refused, withdrawn, and allowed
  after the schedule changed;
- a summary larger than the response;
- the model list.

Disabling any one of 37 guarded dispatch behaviors makes a check fail.

They also check:
- that an idle tick writes nothing and costs the same with 1 or 49
  reminders;
- that 49 reminders due in one look all fire, across several pages;
- that a look whose commit fails is tried again at the next.

Disabling any one of 18 behaviors makes at least one check fail: jump
detection and its threshold, activation, starting over when the clock is
unset, refreshing the due time, the unset-clock guard, the due test,
waiting for the next look, paging, stopping on a failed accept, the Agent
run's standing, resetting what a look counts, and each kind of notice.

The `desktop-daybook-reminders` smoke profile runs the whole path in Desk
on the emulator, through ordinary keys, and checks the live reminder file at
each step:
- a reminder made at boot fires once, on time, with its notice;
- the view reviews it, then pauses and resumes another;
- a reminder made through Daybook's prompts fires on time;
- setting the clock back over that firing fires nothing again;
- setting it two days ahead gives one missed item;
- a second machine booted from the disk as it then is shows the same next
  firing and missed item, and writes nothing at boot.

On the rich terminal, `physical_desktop_acceptance.py --applet daybook`
runs Desk with Daybook alone on the real-time simulator. Its boot makes the
same reminders, with the one-off two minutes after boot. Once the Daybook
journey has checked its task, it waits for that reminder to fire and
requires Desk's notice on the bottom row of the physically presented frame,
in both the rich scene and CELL. The notice is Desk's ordinary toast, drawn
through the normal draw path; the rich path has no reminder-specific code.
