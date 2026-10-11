# Daybook automation store

`akashic/tui/applets/daybook/automation-store.f` keeps Daybook's reminders on
disk. It holds the records and guarantees what reaches the file. The owner,
which comes later, decides what the records mean and when they change.

## The file

Everything lives in one file, `/daybook-automations.bin` in Desk, replaced
whole and atomically through [vfs-replace](../../../utils/fs/vfs-replace.md).
The file is a checked record ([checked-record](../../../utils/checked-record.md))
with magic `AKDBAUTO`, format 1, and its generation as the tag. Its payload
is a header followed by three tables, each kept sorted:

| Table | Record | Sorted by | Holds |
|---|---|---|---|
| Schedules | 512 bytes | RID | Every schedule ever created. A deleted one stays as a tombstone, so its RID is never reused. |
| Occurrences | 128 bytes | id | Firings awaiting review, and reviewed ones still kept |
| Keys | 96 bytes | key bytes | One per create, so a repeated create finds the schedule it already made |

Cells are native-endian 64-bit values. Text fields are a length cell
followed by the bytes, zero after the text.

The header holds the store's 32-byte identity, the next schedule serial, the
next occurrence id, the three counts, how many reviewed occurrences each
schedule keeps (32 by default), and the default zone for new schedules
(`UTC0` at first).

A schedule holds its RID, revision, serial, state (enabled, paused,
completed or deleted), whether it is archived, its action (a reminder), its
[recurrence rule](recurrence.md), its next ordinal and that occurrence's
instant in UTC, its last occurrence and result, how many reviewed
occurrences were pruned, its title, its [zone](../../../utils/posix-tz.md),
and when it was created and changed in wall-clock milliseconds.

An occurrence holds its id, its schedule's RID and the revision that fired
it, the first and last ordinals and instants it covers, how many firings it
merged, whether it fired on time or was missed, whether it awaits review,
the clock evidence behind it (seen continuously, caught up at start, or
caught up after the clock jumped), and when it was accepted and reviewed.

The store never saves uptime.

## Checks

OPEN refuses a file unless every rule holds, and COMMIT applies the same
check to each file before it writes it, so the store never writes a file
it would refuse to read:

- The counts describe the payload exactly, and the header's reserved bytes
  are zero.
- The store has an identity. The serial and occurrence counters are above
  every value in use.
- Each table is strictly ascending, so no RID, id or key repeats.
- A schedule has a revision, a known state, action and result, a title of 1
  to 120 bytes of UTF-8 on one line, and a zone that parses. Its rule passes
  `DBREC-CHECK`. Its next instant is exactly the one its rule and zone give
  its next ordinal, within any UNTIL or COUNT. Only a completed schedule has
  no next occurrence.
- A tombstone keeps only its identity, revision, serial and times.
- An occurrence names a schedule that exists and is not deleted, at a
  revision that schedule has reached. Its ordinals, instants and merged
  count agree with each other, and one awaiting review has no review time.
- A key names a schedule that exists.

The 120-byte title is an interface rule, as it is for a Daybook entry.
Nothing else is capped: the tables grow as needed, bounded by memory and
the file.

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
| `DBAS-R-CORRUPT` | A bad CRC, truncation, a broken rule, or a file too short to be a record |
| `DBAS-R-FUTURE` | A format newer than this code reads |
| `DBAS-R-UNCERTAIN` | A replacement whose outcome nobody can tell, or one recovery could not resolve |
| `DBAS-R-IO` | The file could not be read into memory |

## Commits

The owner edits the tables in memory and calls `DBAS-COMMIT`, which writes
them as the next generation. A commit that fails reloads the last committed
file, so the edits are undone and memory never runs ahead of the disk. A
replacement that may or may not have reached the disk blocks the store
instead (`DBAS-R-UNCERTAIN`). The next OPEN recovers whichever file
survived.

The store's identity is drawn from the entropy source the first time it is
needed, by `DBAS-IDENTITY` or the first commit, and is saved with that
commit.

## Words

```forth
DBAS-INIT          ( vfs path path-u store -- status )
DBAS-OPEN          ( store -- status )
DBAS-CLOSE         ( store -- status )
DBAS-COMMIT        ( store -- status )
DBAS-STATE@        ( store -- state )
DBAS-REASON@       ( store -- reason )
DBAS-GENERATION@   ( store -- n )
DBAS-IDENTITY      ( store -- id status )
DBAS-HEADER        ( store -- header )
DBAS-SCHEDULE-COUNT@  DBAS-OCCURRENCE-COUNT@  DBAS-KEY-COUNT@  ( store -- n )
DBAS-SCHEDULE  DBAS-OCCURRENCE  DBAS-KEY  ( index store -- record )
DBAS-FIND-SCHEDULE    ( rid store -- index found? )
DBAS-FIND-KEY         ( key store -- index found? )
DBAS-FIND-OCCURRENCE  ( id store -- index found? )
DBAS-INSERT-SCHEDULE  ( index store -- schedule status )
DBAS-INSERT-KEY       ( index store -- key-record status )
DBAS-APPEND-OCCURRENCE  ( store -- occurrence status )
DBAS-DELETE-OCCURRENCE  ( index store -- )
DBAS-TITLE-OK?     ( address length -- flag )
DBAS-FIELD$        ( field -- address length )
DBAS-FIELD!        ( address length field capacity -- )
```

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
- a round trip of every table, and growth to 44 schedules inserted out of
  order;
- 57 edits COMMIT must refuse, each leaving the file and memory as they
  were, and 10 it must accept;
- 13 kinds of damage to the file on disk, each blocking the store with the
  right reason without writing;
- a read fault and an unreadable replacement marker;
- a sync fault at each step of replacing an existing file and of writing
  the first one, each followed by a cold reopen;
- a write that stores nothing.

Disabling any one of these makes at least one check fail: the next-instant
rule, table order, the commit-time check, tombstone zeroes, an occurrence's
schedule reference, the reload after a failed commit, blocking on an
uncertain replacement or an unresolvable recovery, the newer-format reason,
or advancing the generation.
