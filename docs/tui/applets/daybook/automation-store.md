# Daybook automation store

`akashic/tui/applets/daybook/automation-store.f` keeps Daybook's schedules
on disk: reminders, and schedules that run the Agent. It holds the records
and guarantees what reaches the file. The [owner](automation-owner.md)
decides what the records mean and when they change.

## The file

Everything lives in one file, `/daybook-automations.bin` in Desk, replaced
whole and atomically through [vfs-replace](../../../utils/fs/vfs-replace.md).
The file is a checked record ([checked-record](../../../utils/checked-record.md))
with magic `AKDBAUTO`, format 2, and its generation as the tag. Its payload
is a header, four tables kept sorted, and a region of variable-length
bytes:

| Part | Record | Sorted by | Holds |
|---|---|---|---|
| Schedules | 512 bytes | RID | Every schedule ever created. A deleted one stays as a tombstone, so its RID is never reused. |
| Actions | 144 bytes | RID | One per live schedule that runs the Agent: its operands and the permission it was approved under |
| Occurrences | 272 bytes | id | Firings and Agent runs, awaiting review or kept after it, and the short records of a deleted schedule's runs |
| Keys | 96 bytes | key bytes | One per create, so a repeated create finds the schedule it already made |
| Blob | variable | table order | Each action's operands, then each occurrence's summary, each padded with zeroes to a cell |

Cells are native-endian 64-bit values. Text fields are a length cell
followed by the bytes, zero after the text. A blob slot is two cells: in
the file, an offset into the blob and a length; in memory, the address of
a heap copy the record owns and the length.

The header holds the store's 32-byte identity, the next schedule serial, the
next occurrence id, the four counts and the blob's size, how many reviewed
occurrences each schedule keeps (32 by default), and the default zone for
new schedules (`UTC0` at first).

A schedule holds its RID, revision, serial, state (enabled, paused,
completed or deleted), whether it is archived, its action from the
[catalog](../../../interop/scheduled-actions.md) (a reminder or an Agent
run), its [recurrence rule](recurrence.md), its next ordinal and that
occurrence's instant in UTC, its last occurrence and that occurrence's
kind, how many reviewed occurrences were pruned, its title, its
[zone](../../../utils/posix-tz.md), and when it was created and changed in
wall-clock milliseconds.

An action holds its schedule's RID, the action and its schema, whether the
schedule is approved, and the Practice, permission and permission revision
it was approved under. Those three are zero until it is approved. Its
operands, the model, limits and prompt, are in the blob.

An occurrence holds:
- its id, its schedule's RID, and the revision that fired it;
- the first and last ordinals and instants it covers, and how many firings
  it merged;
- its kind: on time, missed, or asked for by hand (Run Now);
- its review state: in flight, awaiting review, reviewed, or clear;
- the clock evidence behind it: seen continuously, caught up at start,
  caught up after the clock jumped, or asked for by hand;
- when it was accepted and reviewed;
- its action.

An Agent run's occurrence also holds its phase (accepted, running or
ended), its outcome and reason, its dispatch key, the run's RID, when it
started and ended, a flag marking the short record a deleted schedule
keeps, and a summary in the blob. A reminder's occurrence leaves these
zero.

The store never saves uptime.

## Checks

OPEN refuses a file unless every rule holds, and COMMIT applies the same
check to each file before it writes it, so the store never writes a file
it would refuse to read:

- The counts and the blob's size describe the payload exactly, and the
  header's reserved bytes are zero.
- The store has an identity. The serial and occurrence counters are above
  every value in use.
- Each table is strictly ascending, so no RID, id or key repeats.
- A schedule has a revision, a known state, action and result, a title of 1
  to 120 bytes of UTF-8 on one line, and a zone that parses. Its rule passes
  `DBREC-CHECK`. Its next instant is exactly the one its rule and zone give
  its next ordinal, within any UNTIL or COUNT. Only a completed schedule has
  no next occurrence.
- A tombstone keeps only its identity, revision, serial and times.
- Every schedule that runs the Agent has exactly one action, and every
  action names such a schedule. An action that is approved names a
  Practice, a permission and a revision; one that is not names none.
- An occurrence names a schedule at a revision it has reached, and has that
  schedule's action. Its ordinals, instants and merged count agree with
  each other. A firing covers ordinals; a run asked for by hand covers
  none.
- A reminder's item awaits review or was reviewed, has no review time
  while it awaits review, and holds none of a run's fields.
- A run in flight has its dispatch key and no outcome, end, review, flags
  or summary. An accepted run has no run RID yet; a running one has one.
- An ended run has an outcome and reason the catalog pairs. It needs review
  unless it completed. One that completed, ran out or stopped for review
  has a run RID; one that was blocked or never started has none.
- A deleted schedule keeps only short records of its runs: ended, reviewed
  or clear, with no summary. A live schedule's items are never short
  records.
- At most one run of a schedule is in flight, and no two runs in flight
  share a dispatch key.
- The blob holds exactly each action's operands, which pass the catalog's
  checks, then each summary, which is one line of text, in table order and
  zero-padded. An empty part has no offset.
- A key names a schedule that exists.

The 120-byte title is an interface rule, as it is for a Daybook entry.
Nothing else is capped: the tables are [record tables](../../../utils/record-table.md),
which grow as needed, and operands and summaries are as long as they are,
bounded by memory and the file.

## States

| State | Meaning |
|---|---|
| `DBAS-CLOSED` | Configured, nothing read |
| `DBAS-READY` | The tables in memory are the file's |
| `DBAS-BLOCKED` | Nothing is loaded and nothing will be written |

OPEN first finishes or undoes any interrupted replacement, then reads the
file. A missing file opens as an empty store. A file the store cannot
trust blocks it, with a reason, instead of opening empty:

| Reason | Cause |
|---|---|
| `DBAS-R-CORRUPT` | A bad CRC, truncation, a broken rule, a file too short to be a record, or an older format |
| `DBAS-R-FUTURE` | A format newer than this code reads |
| `DBAS-R-UNCERTAIN` | A replacement whose outcome nobody can tell, or one recovery could not resolve |
| `DBAS-R-IO` | The file could not be read into memory |

Format 1, slice 1's reminders-only layout, is not read: nothing has been
released, so the format changed in place.

## Commits

The [owner](automation-owner.md) edits the tables in memory and calls
`DBAS-COMMIT`, which writes them as the next generation. A commit that
fails reloads the last committed file, so the edits are undone and memory
never runs ahead of the disk. A replacement that may or may not have
reached the disk blocks the store instead (`DBAS-R-UNCERTAIN`). The next
OPEN recovers whichever file survived.

`DBAS-REVERT` drops edits not yet committed by reading the file again,
for an operation that fails before it commits.

The store's identity is drawn from the entropy source the first time it is
needed, by `DBAS-IDENTITY` or the first commit, and is saved with that
commit.

## Words

```forth
DBAS-INIT          ( vfs path path-u store -- status )
DBAS-OPEN          ( store -- status )
DBAS-CLOSE         ( store -- status )
DBAS-COMMIT        ( store -- status )
DBAS-REVERT        ( store -- status )
DBAS-STATE@        ( store -- state )
DBAS-REASON@       ( store -- reason )
DBAS-GENERATION@   ( store -- n )
DBAS-IDENTITY      ( store -- id status )
DBAS-HEADER        ( store -- header )
DBAS-SCHEDULE-COUNT@  DBAS-ACTION-COUNT@  DBAS-OCCURRENCE-COUNT@
DBAS-KEY-COUNT@    ( store -- n )
DBAS-SCHEDULE  DBAS-ACTION  DBAS-OCCURRENCE  DBAS-KEY  ( index store -- record )
DBAS-FIND-SCHEDULE    ( rid store -- index found? )
DBAS-FIND-ACTION      ( rid store -- index found? )
DBAS-ACTION-OF        ( rid store -- action|0 )
DBAS-FIND-KEY         ( key store -- index found? )
DBAS-FIND-OCCURRENCE  ( id store -- index found? )
DBAS-FIND-KEYED       ( key store -- occurrence|0 )
DBAS-INSERT-SCHEDULE  ( index store -- schedule status )
DBAS-INSERT-ACTION    ( index store -- action status )
DBAS-INSERT-KEY       ( index store -- key-record status )
DBAS-APPEND-OCCURRENCE  ( store -- occurrence status )
DBAS-DELETE-ACTION      ( index store -- )
DBAS-DELETE-OCCURRENCE  ( index store -- )
DBAS-BLOB$         ( slot -- address length )
DBAS-BLOB!         ( address length slot -- status )
DBAS-TITLE-OK?     ( address length -- flag )
DBAS-FIELD$        ( field -- address length )
DBAS-FIELD!        ( address length field capacity -- )
```

`DBAS-BLOB!` sets a slot to a copy of the bytes, which may be the slot's
own, and frees what it held; zero bytes empty it. Deleting an action or an
occurrence frees its blob.

| Status | Meaning |
|---|---|
| `DBAS-S-OK` | Done |
| `DBAS-S-INVALID` | A bad argument, or a commit whose file would break a rule |
| `DBAS-S-NOMEM` | Memory ran out; a commit reloaded the file |
| `DBAS-S-IO` | The disk refused a commit; the file is unchanged and was reloaded |
| `DBAS-S-BLOCKED` | The store is blocked; see `DBAS-REASON@` |
| `DBAS-S-STATE` | The store is in the wrong state for the call |
| `DBAS-S-ENTROPY` | No identity could be drawn; a commit reloaded the file |

The caller owns the `DBAS-SIZE`-byte, cell-aligned store and serializes all
calls. The store writes only its file and the companions vfs-replace
derives beside it.

## Qualification

`local_testing/test_daybook_automation_store.py` runs on the native
simulator over a RAM filesystem whose operations the test can replace. It
checks:

- the lifecycle and its refusals;
- that a missing file opens empty and nothing is written before a commit;
- a round trip of every table and of the blob, and growth to 44 schedules
  inserted out of order;
- that `akashic_tui.daybook_automations`, the reader journeys use, reads
  what COMMIT wrote;
- 116 edits COMMIT must refuse (67 to reminders, 49 to Agent runs), each
  leaving the file and memory as they were, and 20 it must accept;
- 24 kinds of damage to the file on disk, each blocking the store with the
  right reason without writing;
- a read fault and an unreadable replacement marker;
- a sync fault at each step of replacing an existing file and of writing
  the first one, each followed by a cold reopen;
- a write that stores nothing.

Disabling any one of 52 guarded rules makes a check fail. The one guard no
check reaches is the refusal of a negative blob size: such a file breaks
other rules too, so it is refused anyway, and the guard keeps the check
from reading past the payload on the way.
