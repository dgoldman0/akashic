# Daybook automations

Daybook owns the system's schedules. A schedule fires at a time, in a time
zone, once or repeating, and does one action from the
[catalog](../../../interop/scheduled-actions.md):
- a reminder, a title that comes due for review;
- an Agent run: one bounded run of a model the schedule names, with its
  prompt, started by Desk's broker under a schedule permission you approve.

Schedules fire inside Desk whether or not Daybook is open, survive
restarts, and say so when they were missed.

Desk opens its [broker](../desk/schedule-broker.md) and gives the
service its client, so a due Agent run reaches the Agent while Daybook and
the Agent are closed. Daybook's automations view makes Agent runs, shows
them, and runs, approves and cancels them (see [Daybook](daybook.md)).

## Layers

| Module | Role |
|---|---|
| [`recurrence.f`](recurrence.md) | When a rule repeats: an RFC 5545 subset |
| [`automation-store.f`](automation-store.md) | The file: format, checks, atomic commits, recovery |
| [`automation-owner.f`](automation-owner.md) | What schedules mean: typed operations, firing, approval, runs, review |
| `automation-runner.f` | When to look, and what the clock says |
| `automation-service.f` | The Desk seam: the owner, the runner and the notice |
| `automation-view.f` | Daybook's view of its automations, and the create steps |

Time zones come from [posix-tz](../../../utils/posix-tz.md). The wall clock
is trusted only while `EPOCH-VALID?` says it is set, and intervals use
uptime (`MS@`), so setting the clock never breaks a timer.

Desk opens the service, ticks it and shows its notices (see
[Desk](../desk/desk.md)). Daybook's automations view shows the schedules and
their items, makes and changes reminders, and runs, approves and cancels
Agent runs (see [Daybook](daybook.md)). The service and
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
DBSVC-LABEL       ( rid service -- address length )
DBSVC-WHEN$       ( schedule service -- address length )
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
- **Names.** `DBSVC-LABEL` gives a schedule's title by its RID, for Desk
  to name the permission granted for it, or 0 0 when Daybook has no such
  schedule. The text stays put until the store is next used.
  `DBSVC-WHEN$` says when a schedule runs, with its zone, in the words
  Desk's approval shows; the text stays put until the next call.

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

## Making an Agent run

An Agent run takes the reminder's steps, when and its title, how it
repeats and its zone, then these, in the view (`automation-view.f`):

1. `DBAV-MODELS-FETCH` asks Desk's broker for the models an Agent run may
   name, first with no room and then with the room the list needs. A list
   that is not whole, names no model, or comes with a refusal is none, and
   the create cannot go on.
2. The model, by its label or its id, then each choice it offers in turn
   (`DBAV-NEXT-KIND`): its effort, its tier, where the first choice is
   none, the model's default, and its verbosity, where the first is the
   model's default. A model that offers none of them asks nothing more.
3. How many minutes it may run, and how many bytes of its reply it keeps:
   whole numbers above zero, as large as a cell holds.
4. Its prompt, which may be any length and hold tabs and new lines. What
   the run may disclose is exactly its prompt. With it the operands are
   whole, and checked as the catalog checks them.

`DBAV-CREATE` then makes the schedule under the create's key, placing a
start given as only a time at its next such time, and
`DBAV-ASK-CREATED` asks Desk's user to approve it at the revision it has.
The approval, not the view, checks that the model's provider takes a
prompt that large.

## Details

`DBAV-OPEN` opens the schedule a row shows in detail. Its facts, each a
label (`DBAV-FACT-LABEL`) and a text (`DBAV-FACT-TEXT`), are its title;
when it runs, as `DBSVC-WHEN$` says it; when it runs next, or that it is
paused, done or archived; and for an Agent run whether Daybook holds it
approved, the model it names with its choices and its limits in the
catalog's words (`SACT-SAY-MODEL`, `SACT-SAY-LIMITS`, which Desk's approval
uses too), its provider, and its prompt exactly as stored. After them come
its items, newest first: when each was due, how many a missed item covers,
how an Agent run stands or ended, whether it awaits review, and on a line
of its own its run's summary.

The facts follow the store. Once it changes, `DBAV-OPENED-STALE?` says so,
and `DBAV-REREAD` reads the items again, a page of ids at a time into a
buffer that grows to them, or says the schedule was deleted.
`DBAV-OPENED-RUN-NOW`, `DBAV-OPENED-ASK` and `DBAV-OPENED-CANCEL` act on
the opened Agent run, and refuse while its facts are older than the store;
the run cancel finds is its newest item, since a schedule has at most one
run in flight and runs no other meanwhile.

`local_testing/test_daybook_automation_view.py` and
`test_daybook_automation_view_runs.py` check the automations view, the
second over the same fake broker:
- its sections, and each row's detail, for reminders and for Agent runs
  approved or not, waiting, running, and ended for review;
- Run Now, asking for approval and where it stands, and cancelling, with
  their refusals and messages;
- rows from before the store changed, which take no action;
- a deleted schedule's short records, which no section shows;
- details that grow to what they say, give their memory back, and stop at
  what fitted when memory runs out.

Disabling any one of 35 guarded view behaviors makes a check fail, except
one: the approval note's guard for a view with no service. Without it the
note reads the service's fields from address zero, which the simulator's
memory holds as zero, so the note is the same.

`local_testing/test_daybook_automation_view_create.py` makes Agent runs
in the view over the fake broker, which answers with a real model list:
- the list fetched with the room it needs, even when the room it first
  asks for falls short; refused when the broker cannot answer, has no
  client, answers with a list that is not whole or names no model, asks
  for no more room than it had, claims bytes beyond the room, or refuses
  after writing it; and without memory for it;
- the choices in turn, and choices beyond those offered refused;
- the limits, as large as a cell holds and no larger;
- the operands the prompt completes, a run created at its next time, and
  the approval asked for at its revision with those exact operands;
- a 100,000-byte prompt kept whole;
- prompts refused when empty or not text, without memory, or without a
  model or limits;
- the memory a create took, given back.

`local_testing/test_daybook_automation_view_details.py` opens schedules
in detail over the same fake broker:
- an Agent run's facts, word for word, and a reminder's;
- items newest first: fired, missed once and several times, runs by hand
  and on schedule, how they ended, whether they await review, and their
  summaries;
- a history longer than a page of ids, an id the store no longer has,
  and nothing past the last fact;
- facts that grow old when the store changes, and a schedule deleted,
  with and without its runs' short records;
- actions on the opened schedule: refused while its facts are old, for a
  reminder, when nothing is opened, for a run already over, and for
  another schedule's run whose id the room still holds;
- without memory a schedule stays closed, and details give back their
  memory.

Disabling any one of 43 guarded behaviors of the details makes a check
fail.

Disabling any one of 86 guarded behaviors of the create makes a check
fail, except four that no check can show. The fetch refuses a broker that
claims more bytes than the room it had before reading them, and without
that guard the list check refuses the same lists. A choice asked about
before any model is chosen, and an approval asked for no schedule, read
from address zero, which the simulator holds as zero. A number that is not
digits reads as zero, so it is refused with or without the digit check.

The service checks also cover:
- that an idle tick writes nothing and costs the same with 1 or 49
  reminders;
- that 49 reminders due in one look all fire, across several pages;
- that a look whose commit fails is tried again at the next.

Disabling any one of 18 behaviors makes at least one check fail: jump
detection and its threshold, activation, starting over when the clock is
unset, refreshing the due time, the unset-clock guard, the due test,
waiting for the next look, paging, stopping on a failed accept, the Agent
run's standing, resetting what a look counts, and each kind of notice.

The `desktop-daybook-agent` smoke profile runs Desk with Daybook and the
Agent, whose development device-flow source gives the scripted provider a
ready catalog of two models, and makes an Agent run through Daybook's
ordinary keys:
- Ctrl+G, then the time and title, a daily repeat and the default zone;
- the second model, its second effort, its tier and the third verbosity,
  each page listing the catalog's choices;
- ten minutes and 16,384 bytes of reply;
- a two-line prompt longer than the editor's first room, with Escape asking
  before it would discard and a key taking that back;
- Ctrl+S, after which Desk's approval screen names the schedule, the
  model, effort, tier, verbosity and limits, and discloses exactly the
  prompt's bytes, and allows it only once read to the end;
- A, after which Daybook says it is approved, Daybook's file holds the run
  approved with exactly those operands, and Desk's run permissions name it.
- its details, full frame, naming the model and limits in the words Desk's
  approval used, and showing the prompt;
- three minutes later, with Daybook and the Agent idle, the run firing on
  time and completing, Desk's notices for both, one completed item in
  Daybook's file with the run's identity and summary, and the run in the
  Agent's scheduled runs (F5) on gpt-slow.

Desk then sleeps under 10% of the clock with the run scheduled.

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
