# Daybook automation owner

`akashic/tui/applets/daybook/automation-owner.f` gives Daybook's schedules
their meaning. It wraps the [automation store](automation-store.md) in
typed operations. Each one checks what it is asked, edits the tables, and
commits. A failed commit leaves the schedules exactly as they were.

A schedule names an action from the
[catalog](../../../interop/scheduled-actions.md):
- a reminder, which makes an item for review;
- an Agent run, which Desk's broker starts under a schedule permission.

## Clock

Every operation takes `now`, the wall clock in milliseconds, or
`DBAO-CLOCK-UNSET` (-1) when the clock is not set. The caller reads the
clock once, so one operation sees one time.

Create, replace, resume, unarchive, accept and Run Now refuse with
`DBAO-S-CLOCK` when the clock is not set: they place an occurrence or
record when a run was asked for. Pause, archive, delete, review and the
broker's reports still work and record an unknown time as zero.

## Creating

A create takes a draft and a create key. The draft holds:
- a [recurrence rule](recurrence.md);
- a title of 1 to 120 bytes on one line;
- a [POSIX TZ zone](../../../utils/posix-tz.md);
- an action, and its operands. A reminder takes none. An Agent run takes
  the catalog's canonical operands, which name the model, the limits and
  the prompt.

The create key is 32 bytes the caller chooses, typically once per create
dialog.

- The same key with the same draft again returns the schedule it made and
  writes nothing. A dialog that submits twice, or retries after an error,
  makes one schedule.
- The same key with a different draft, including different operands, is
  `DBAO-S-CONFLICT`.
- The schedule's RID is the SHA3-256 digest of a domain tag, the store's
  identity and the key. It never changes, and a deleted schedule keeps it.

The zone is stored in its canonical form, so `EST+5EDT,M3.2.0/2,M11.1.0/2`
is kept as `EST5EDT,M3.2.0,M11.1.0`. The request digest uses the canonical
form, so both spellings are the same request.

A schedule fires first at its rule's first occurrence at or after `now`.
A rule that started in the past does not fire for the past. A draft with no
occurrence at or after `now` is refused with `DBAO-S-NEVER`, for example a
one-off in the past or a series already over.

An Agent run's schedule is created unapproved.

## Approval

`DBAO-AUTHORIZE` records the permission an Agent run's schedule was
approved under, as Desk's broker answered: the Practice, the permission and
its revision, all present. It names the schedule revision the caller saw,
so an approval of what has since changed is `DBAO-S-CONFLICT`. A reminder
takes no approval (`DBAO-S-MANUAL`).

Approval is cleared when:
- a replace changes when or how the run runs: its rule, its zone or its
  operands. A new title alone keeps it.
- Desk's answer at a firing says the permission no longer stands: none,
  withdrawn, changed, or another Practice's.
- a run ends refused for one of those reasons, under the very permission
  and revision Daybook holds. A refusal of an older approval changes
  nothing.

An Agent that cannot be reached is not a refusal, so the approval stays.

## Editing

Every edit names the revision the caller last saw. A stale revision is
`DBAO-S-CONFLICT`, and a successful edit moves the revision on by one, so
two editors never silently overwrite each other.

| Operation | Effect |
|---|---|
| `DBAO-REPLACE` | New rule, title, zone and operands; the action stays (`DBAO-S-ACTION` otherwise). It fires next at the new rule's first occurrence at or after `now`. A completed schedule becomes enabled again. |
| `DBAO-PAUSE` | Stops an enabled schedule firing |
| `DBAO-RESUME` | Starts a paused schedule again from `now`. Occurrences during the pause never fire. |
| `DBAO-ARCHIVE` | Hides a schedule and stops it firing |
| `DBAO-UNARCHIVE` | Shows it again. An enabled one fires from `now`, skipping what fell while it was archived. |
| `DBAO-DELETE` | Leaves a tombstone. Further edits are `DBAO-S-DELETED`. |
| `DBAO-DEFAULT-ZONE!` | Sets the zone new schedules start with |

Pausing a paused schedule, or archiving an archived one, is `DBAO-S-STATE`.

Deleting a reminder removes its items. Deleting an Agent run's schedule
keeps a short record of each of its runs: when it ran, how it ended and its
run RID, but no summary. Any still awaiting review count as reviewed then,
and the retention applies. A run in flight keeps the schedule
(`DBAO-S-BUSY`), and so does an indeterminate one awaiting review
(`DBAO-S-REVIEW`): whether it ran must be looked at first.

## Firing

The runner asks `DBAO-DUE` for the earliest instant an enabled, unarchived
schedule is due. At that instant it pages through the due schedules with
`DBAO-DUE-QUERY`, which writes for each its RID, revision and next
ordinal, and accepts each with `DBAO-OCC-ACCEPT`. It passes `now`, what it
knows about the clock, and, for an Agent run, its permission's standing:

| Basis | Meaning |
|---|---|
| `DBAS-CONTINUOUS` | The clock ran continuously since the last check |
| `DBAS-ACTIVATION` | The first check since the runner started |
| `DBAS-JUMP` | The wall clock jumped since the last check |

Each accept commits on its own and returns the item it made or added to.

- The schedule's occurrences from its next to the last at or before `now`
  make one firing. A single occurrence seen while the clock ran
  continuously fired on time. Anything else is missed: several occurrences
  at once, the first check after a start, or a check after a jump.
- A reminder's firing is a review item. An item still awaiting review at
  the same revision absorbs later firings, so the backlog stays one item
  per reminder, however long nobody looks. A merged item counts as missed
  if any part was, and keeps the strongest clock evidence.
- An Agent run's on-time firing is accepted when its permission stands,
  Daybook holds it approved, and no run of the schedule is in flight. The
  item is in flight, with its dispatch key. Otherwise it ends at once for
  review, blocked with the reason.
- A missed Agent run never starts: it ends for review as not started,
  missed.
- Ended items merge only with an item awaiting review at the same revision
  with the same outcome and reason. A run that was accepted is always an
  item of its own.
- The schedule then moves to its first occurrence after `now`, or
  completes when its series has none.

The entry names the ordinal it found due. Accepting it again answers
`DBAO-S-ACCEPTED` with the schedule's latest item and writes nothing. An
edit since the query is a conflict. The next occurrence only moves
forward, so a clock that jumps back never fires anything twice.

## Runs

The dispatch key is `SDSP-KEY` of the store's identity, the schedule's RID
and the item's id. There is one key per run.

`DBAO-RUN-NOW` asks for a run by hand. It is an accepted item of kind
manual, covering no ordinal, and it leaves the schedule's next occurrence
alone. Only an enabled, unarchived, approved Agent run's schedule takes
one, and only while no run of it is in flight. A reminder is never run by
hand (`DBAO-S-MANUAL`).

Desk's broker reports by dispatch key:
- `DBAO-OCC-STARTED` records the run's RID and when it started.
- `DBAO-OCC-FINISH` records the outcome and reason, the run's RID when it
  ran, when it ended, and a one-line summary without run content.

A run that completed needs no review; any other end does.

Both reports are idempotent: the same report again changes nothing, and a
different one is `DBAO-S-CONFLICT`. An end is checked whole before
anything changes:
- its outcome and reason must be a pair the catalog allows;
- its summary must be one line within the response's capacity;
- a run that ran cannot have been blocked or not started;
- one that never ran cannot have completed, run out or stopped for review;
- a run RID other than the one recorded is a conflict.

A run that ends before Daybook heard it start still keeps its RID. Nothing
is ever retried.

## Reviewing

`DBAO-REVIEW` takes an item's id and the last ordinal the caller saw in it.
If a firing merged into the item since, the review is `DBAO-S-CONFLICT`, so
an occurrence is never marked reviewed unseen. Each schedule keeps as many
settled items (reviewed, or runs that completed) as the store's retention
says (32 unless changed). Older ones are pruned, oldest first, and counted
in the schedule's pruned count. Pruning never removes an item in flight or
one awaiting review.

## Paged reads

`DBAO-QUERY` writes the RIDs of live schedules in RID order from an index,
up to a maximum, and returns where to continue. `DBAO-HISTORY` writes the
ids of one schedule's items, newest first, skipping as many as the cursor
says.

## Words

```forth
DBAO-INIT          ( vfs path path-u owner -- status )
DBAO-OPEN          ( owner -- status )
DBAO-CLOSE         ( owner -- status )
DBAO-STORE         ( owner -- store )
DBAO-FIND          ( rid owner -- schedule|0 )
DBAO-ACTION        ( rid owner -- action|0 )
DBAO-CREATE        ( key draft now rid owner -- status )
DBAO-REPLACE       ( rid revision draft now owner -- status )
DBAO-PAUSE DBAO-RESUME DBAO-ARCHIVE DBAO-UNARCHIVE DBAO-DELETE
                   ( rid revision now owner -- status )
DBAO-AUTHORIZE     ( rid revision response now owner -- status )
DBAO-REVIEW        ( id last now owner -- status )
DBAO-DEFAULT-ZONE! ( address length owner -- status )
DBAO-QUERY         ( cursor entries max owner -- n cursor' status )
DBAO-HISTORY       ( rid cursor entries max owner -- n cursor' status )
DBAO-DUE           ( owner -- utc-s found? )
DBAO-DUE-QUERY     ( through-s cursor entries max owner -- n cursor' status )
DBAO-OCC-ACCEPT    ( entry basis standing now owner -- id status )
DBAO-OCC-STARTED   ( key run now owner -- status )
DBAO-OCC-FINISH    ( key response now owner -- status )
DBAO-RUN-NOW       ( rid revision now owner -- id status )
DBAO-TRIGGER-DIGEST  ( schedule dest -- )
```

A draft is `DBAO-DRAFT-SIZE` bytes: the rule (`DBAO-D.RULE`), the title
and zone fields (`DBAO-D.TITLE`, `DBAO-D.ZONE`, filled with
`DBAS-FIELD!`), the action (`DBAO-D.ACTION`), and the operands' address and
length (`DBAO-D.OPERANDS`, filled with `SACT-D!`). A due entry is
`DBAO-DUE-SIZE` bytes, read with `DBAO-E.RID`, `DBAO-E.REVISION` and
`DBAO-E.ORDINAL`. Responses are the dispatch contract's. Reads go through
the store's accessors on `DBAO-STORE`. Records stay put until the next
operation.

`DBAO-TRIGGER-DIGEST` is the digest a permission binds of when a schedule
runs: SHA3-256 of a domain tag, its rule and its canonical zone field.

Statuses 0 to 6 are the store's. The rest are the owner's:

| Status | Meaning |
|---|---|
| `DBAO-S-CLOCK` | The clock is not set |
| `DBAO-S-NOT-FOUND` | No such schedule, item or run |
| `DBAO-S-CONFLICT` | A stale revision, a reused create key, a review of an item that changed, or another answer for the same run |
| `DBAO-S-DELETED` | The schedule was deleted |
| `DBAO-S-TITLE` | The title is empty, too long, not UTF-8, or has a control character |
| `DBAO-S-ZONE` | The zone does not parse |
| `DBAO-S-RULE` | A rule field is out of range |
| `DBAO-S-NEVER` | The rule has no occurrence at or after now |
| `DBAO-S-ACCEPTED` | That occurrence was accepted before |
| `DBAO-S-BUSY` | A run of the schedule is in flight |
| `DBAO-S-REVIEW` | An indeterminate run awaits review |
| `DBAO-S-MANUAL` | A reminder is never dispatched or approved |
| `DBAO-S-APPROVAL` | The schedule is not approved |
| `DBAO-S-OPERANDS` | The operands are malformed for the action |
| `DBAO-S-ACTION` | Not an action in the catalog, or not the schedule's |

The caller owns the `DBAO-SIZE`-byte, cell-aligned owner and serializes
all calls.

## Qualification

`local_testing/test_daybook_automation_owner.py` runs the owner on the
native simulator over a RAM filesystem with explicit clock values. It
checks:

- the create key and its replays, including after a cold start;
- 18 create refusals, each made before any edit: with reads failing, the
  store stays ready;
- canonical zones and the default zone;
- a past start firing from now;
- every edit with its revision, clock and state refusals;
- firing on time, nothing twice at the same time or after the clock moves
  back, a jump merging three missed occurrences into the waiting item,
  review conflicts, and a restart catching up as missed;
- series ending by count, UNTIL and as a one-off, then replaced;
- paused and archived schedules staying silent;
- firings at a new revision kept apart from the old one's;
- retention pruning the oldest reviewed item;
- New York's November change moving the instant and keeping the hour;
- commits that fail, leaving schedules unchanged;
- a blocked store refusing every operation.

For Agent runs it checks:
- operands kept and replayed, and an action that never changes;
- approval and what clears it;
- the accept entry's refusals;
- an on-time run accepted with its own dispatch key, and later firings
  blocked while it is in flight;
- runs of different schedules in flight together;
- each standing that blocks a run, and which ones clear approval;
- missed runs never starting;
- the broker's started and finished reports, their repeats and conflicts;
- 10 refused ends that change nothing;
- an end for a run Daybook never heard start;
- refusals clearing only the approval they name;
- Run Now and its refusals;
- deleting with short records, and its refusals;
- pruning that keeps runs in flight and awaiting review;
- paged reads of schedules and history.

Disabling any one of 68 guarded behaviors makes a check fail.
