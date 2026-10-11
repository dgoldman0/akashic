# Daybook automation owner

`akashic/tui/applets/daybook/automation-owner.f` gives Daybook's reminders
their meaning. It wraps the [automation store](automation-store.md) in
typed operations. Each one checks what it is asked, edits the tables, and
commits. A failed commit leaves the reminders exactly as they were.

## Clock

Every operation takes `now`, the wall clock in milliseconds, or
`DBAO-CLOCK-UNSET` (-1) when the clock is not set. The caller reads the
clock once, so one operation sees one time.

Create, replace, resume and unarchive must place the next occurrence, so
they refuse with `DBAO-S-CLOCK` when the clock is not set. Pause, archive,
delete and review still work and record an unknown time as zero.

## Creating

A create takes a draft and a create key. The draft holds a
[recurrence rule](recurrence.md), a title of 1 to 120 bytes on one line,
and a [POSIX TZ zone](../../../utils/posix-tz.md). The create key is 32
bytes the caller chooses, typically once per create dialog.

- The same key with the same draft again returns the reminder it made and
  writes nothing. A dialog that submits twice, or retries after an error,
  makes one reminder.
- The same key with a different draft is `DBAO-S-CONFLICT`.
- The reminder's RID is the SHA3-256 digest of a domain tag, the store's
  identity and the key. It never changes, and a deleted reminder keeps it.

The zone is stored in its canonical form, so `EST+5EDT,M3.2.0/2,M11.1.0/2`
is kept as `EST5EDT,M3.2.0,M11.1.0`. The request digest uses the canonical
form, so both spellings are the same request.

A reminder fires first at its rule's first occurrence at or after `now`.
A rule that started in the past does not fire for the past. A draft with no
occurrence at or after `now` is refused with `DBAO-S-NEVER`, for example a
one-off in the past or a series already over.

## Editing

Every edit names the revision the caller last saw. A stale revision is
`DBAO-S-CONFLICT`, and a successful edit moves the revision on by one, so
two editors never silently overwrite each other.

| Operation | Effect |
|---|---|
| `DBAO-REPLACE` | New rule, title and zone. It fires next at the new rule's first occurrence at or after `now`. A completed reminder becomes enabled again. |
| `DBAO-PAUSE` | Stops an enabled reminder firing |
| `DBAO-RESUME` | Starts a paused reminder again from `now`. Occurrences during the pause never fire. |
| `DBAO-ARCHIVE` | Hides a reminder and stops it firing |
| `DBAO-UNARCHIVE` | Shows it again. An enabled one fires from `now`, skipping what fell while it was archived. |
| `DBAO-DELETE` | Removes the reminder's review items and leaves a tombstone. Further edits are `DBAO-S-DELETED`. |
| `DBAO-DEFAULT-ZONE!` | Sets the zone new reminders start with |

Pausing a paused reminder, or archiving an archived one, is
`DBAO-S-STATE`.

## Firing

The runner asks `DBAO-DUE` for the earliest instant an enabled,
unarchived reminder is due, and calls `DBAO-ACCEPT` with `now` and what it
knows about the clock:

| Basis | Meaning |
|---|---|
| `DBAS-CONTINUOUS` | The clock ran continuously since the last check |
| `DBAS-ACTIVATION` | The first check since the runner started |
| `DBAS-JUMP` | The wall clock jumped since the last check |

`DBAO-ACCEPT` fires every reminder that is due, then commits once.

- Each due reminder gets one review item covering every occurrence from its
  next to the last at or before `now`. The item records the first and last
  ordinals and instants and how many occurrences it covers.
- A single occurrence seen while the clock ran continuously fired on time.
  Anything else is missed: several occurrences at once, the first check
  after a start, or a check after a jump.
- An item still awaiting review at the same revision absorbs later firings.
  The backlog stays one item per reminder, however long nobody looks. A
  merged item counts as missed if any part was, and keeps the strongest
  clock evidence.
- The reminder then moves to its first occurrence after `now`, or completes
  when its series has none.

The next occurrence only moves forward, so a clock that jumps back never
fires anything twice. `DBAO-LAST-FIRED@` names the latest item a firing
made or added to, for the notice.

## Reviewing

`DBAO-REVIEW` takes an item's id and the last ordinal the caller saw in it.
If a firing merged into the item since, the review is `DBAO-S-CONFLICT`, so
an occurrence is never marked reviewed unseen. Each reminder keeps as many
reviewed items as the store's retention says (32 unless changed). Older
ones are pruned, oldest first, and counted in the reminder's pruned count.

## Words

```forth
DBAO-INIT          ( vfs path path-u owner -- status )
DBAO-OPEN          ( owner -- status )
DBAO-CLOSE         ( owner -- status )
DBAO-STORE         ( owner -- store )
DBAO-FIND          ( rid owner -- schedule|0 )
DBAO-CREATE        ( key draft now rid owner -- status )
DBAO-REPLACE       ( rid revision draft now owner -- status )
DBAO-PAUSE         ( rid revision now owner -- status )
DBAO-RESUME        ( rid revision now owner -- status )
DBAO-ARCHIVE       ( rid revision now owner -- status )
DBAO-UNARCHIVE     ( rid revision now owner -- status )
DBAO-DELETE        ( rid revision now owner -- status )
DBAO-REVIEW        ( id last now owner -- status )
DBAO-DEFAULT-ZONE! ( address length owner -- status )
DBAO-DUE           ( owner -- utc-s found? )
DBAO-ACCEPT        ( now basis owner -- fired status )
DBAO-LAST-FIRED@   ( owner -- id )
```

A draft is `DBAO-DRAFT-SIZE` bytes: the rule (`DBAO-D.RULE`), then the
title and zone fields (`DBAO-D.TITLE`, `DBAO-D.ZONE`), filled with
`DBAS-FIELD!`. Reads go through the store's accessors on `DBAO-STORE`.
Records stay put until the next operation.

Statuses 0 to 6 are the store's. The rest are the owner's:

| Status | Meaning |
|---|---|
| `DBAO-S-CLOCK` | The clock is not set |
| `DBAO-S-NOT-FOUND` | No such reminder or review item |
| `DBAO-S-CONFLICT` | A stale revision, a reused create key, or a review of an item that changed |
| `DBAO-S-DELETED` | The reminder was deleted |
| `DBAO-S-TITLE` | The title is empty, too long, not UTF-8, or has a control character |
| `DBAO-S-ZONE` | The zone does not parse |
| `DBAO-S-RULE` | A rule field is out of range |
| `DBAO-S-NEVER` | The rule has no occurrence at or after now |

The caller owns the `DBAO-SIZE`-byte, cell-aligned owner and serializes
all calls.

## Qualification

`local_testing/test_daybook_automation_owner.py` runs the owner on the
native simulator over a RAM filesystem with explicit clock values. It
checks:

- the create key and its replays, including after a cold start;
- 13 create refusals that leave nothing written;
- canonical zones and the default zone;
- a past start firing from now;
- every edit with its revision, clock and state refusals;
- firing on time, nothing twice at the same time or after the clock moves
  back, a jump merging three missed occurrences into the waiting item,
  review conflicts, and a restart catching up as missed;
- series ending by count, UNTIL and as a one-off, then replaced;
- paused and archived reminders staying silent;
- firings at a new revision kept apart from the old one's;
- retention pruning the oldest reviewed item;
- New York's November change moving the instant and keeping the hour;
- commits that fail, leaving reminders unchanged;
- a blocked store refusing every operation.

Breaking any one of 17 behaviors makes at least one check fail. These
include the on-time rule, merging and its revision check, firing strictly
after now, the COUNT and UNTIL caps, the review guard, pruning, revision
checks, key replay and its digest, placement on resume and unarchive,
removing items on delete, the clock check, the archived check, and
canonical zones.
