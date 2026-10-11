# Schedule permissions

`akashic/runtime/schedule-permission.f` keeps the permissions that let
Desk's broker start scheduled work on its own. A permission covers one
automatic action from the [catalog](../interop/scheduled-actions.md), such
as an Agent run, for one schedule of one store, in one Practice.

A user approves a schedule once. After that the broker may start each of
its runs without asking, as long as the request is exactly what was
approved.

## What a permission binds

| Field | Meaning |
|---|---|
| RID | SHA3-256 of `akashic.sched.permission.v1`, the store's identity and the permission's serial as u64 |
| Practice | The Practice the user approved it in |
| revision | Moves on each time the grant is replaced |
| serial | The permission's place in the store's count |
| store, schedule | The subject: the identity of the schedule's store, and the schedule's RID |
| action, schema | The automatic action approved |
| operand digest | `SACT-DIGEST` of the operands: the model, limits and prompt |
| trigger digest | The digest of when the schedule runs (Daybook's `DBAO-TRIGGER-DIGEST`) |
| effects, time, disclosure, output | The limits, from the operands, which the broker compiles a run's authority from |
| granted | When it was approved, in wall-clock milliseconds, or 0 when the clock was not set |

The store keeps no content: no title, no prompt, no model text. Whoever
shows a permission reads those from the schedule it names, and the operand
digest says whether they are still what was approved.

A Practice has at most one permission per schedule. Approving the schedule
again after it changed replaces that permission's grant and moves its
revision on. Revoking deletes it, and because a RID comes from a serial
that only counts up, a revoked RID is never granted again.

## Operations

```forth
SPERM-INIT         ( vfs path path-u store -- status )
SPERM-OPEN         ( store -- status )
SPERM-CLOSE        ( store -- status )
SPERM-STATE@       ( store -- state )
SPERM-REASON@      ( store -- reason )
SPERM-GENERATION@  ( store -- n )
SPERM-HEADER       ( store -- header )
SPERM-COUNT@       ( store -- n )
SPERM-NTH          ( index store -- permission )
SPERM-FIND         ( rid store -- permission|0 )
SPERM-GRANT        ( request practice now store -- permission status )
SPERM-REVOKE       ( rid store -- status )
SPERM-MATCH        ( request practice store -- standing )
```

Requests are the [dispatch contract's](../interop/scheduled-actions.md#requests).

`SPERM-GRANT` records an approval the user gave in `practice`. The request
must be one `SDSP-REQUEST-OK?` accepts that names no occurrence, has its
trigger digest, and names no other Practice; anything else is
`SPERM-S-INVALID` and writes nothing.
- A schedule with no permission in the Practice gets a new one at
  revision 1.
- One whose permission already grants exactly this keeps it, and nothing
  is written. An approval asked for twice gives one permission.
- One whose permission grants something else has its grant replaced and
  its revision moved on.

The permission returned stays put until the next operation.

`SPERM-MATCH` answers how a request stands, as an `SDSP-A-` standing:

| Standing | When |
|---|---|
| approved | The permission it names exists at the revision it names, in the current Practice and the Practice the request names, for its schedule of its store, granting exactly its action, schema, operand digest and trigger digest |
| none | It names no permission |
| withdrawn | The permission it names does not exist: revoked |
| changed | The permission exists, but at another revision, for another subject, or granting something else |
| another Practice | The permission is another Practice's |
| unavailable | The store cannot answer: closed or blocked |

The caller checks the request with `SDSP-REQUEST-OK?` first.

`SPERM-REVOKE` deletes a permission; an unknown RID is
`SPERM-S-NOT-FOUND`.

| Status | Meaning |
|---|---|
| `SPERM-S-OK` | Done |
| `SPERM-S-INVALID` | A bad argument or request, or a write whose file would break a rule |
| `SPERM-S-NOMEM` | Memory ran out; a write reloaded the file |
| `SPERM-S-IO` | The disk refused a write; the file is unchanged and was reloaded |
| `SPERM-S-BLOCKED` | The store is blocked; see `SPERM-REASON@` |
| `SPERM-S-STATE` | The store is in the wrong state for the call |
| `SPERM-S-ENTROPY` | No identity could be drawn |
| `SPERM-S-NOT-FOUND` | No such permission |

The caller owns the `SPERM-SIZE`-byte, cell-aligned store and serializes
all calls. Desk's broker is the only writer, so memory always holds what
the file holds.

## The file

Desk keeps the store at `/schedule-perms.bin` in its Practice filesystem,
replaced whole and atomically through
[vfs-replace](../utils/fs/vfs-replace.md). The file is a checked record
([checked-record](../utils/checked-record.md)) with magic `AKSCHPRM`,
format 1, and its generation as the tag. Its payload is a 64-byte header
(the store's identity, the next serial and the count) and then a 272-byte
record per permission, sorted by RID. The table is a
[record table](../utils/record-table.md), so memory and the file bound how
many permissions there are, not a count.

OPEN finishes or undoes an interrupted replacement, then reads the file. A
missing file is an empty store. OPEN refuses a file unless every rule
holds, and each write checks its file the same way first:
- The count and the payload agree exactly.
- The store has an identity, and the serial counter is past zero.
- The permissions are strictly ascending by RID.
- Each RID is the one its serial gives, and each serial is below the
  counter.
- Each permission names a Practice, a store and a schedule, and has a
  revision.
- Each has an automatic action at its schema, and both digests.
- Each has positive limits and no effects; the catalog takes no effects
  yet.
- Each has a granted time that is not negative, and zero reserved bytes.
- No two permissions share a Practice, store and schedule.

A file the store cannot trust blocks it, with a reason, instead of opening
empty. Damage never reads as having no permissions.

| Reason | Cause |
|---|---|
| `SPERM-R-CORRUPT` | A bad CRC, truncation, a broken rule, or an older format |
| `SPERM-R-FUTURE` | A format newer than this code reads |
| `SPERM-R-UNCERTAIN` | A replacement whose outcome nobody can tell |
| `SPERM-R-IO` | The file could not be read into memory |

A write that fails reloads the last committed file, so a failed grant or
revoke leaves the store as it was. A replacement that may or may not have
reached the disk blocks the store until the next OPEN recovers whichever
file survived.

## Qualification

`local_testing/test_schedule_permission.py` runs on the native simulator
over a RAM filesystem whose operations the test can replace. It checks:
- the lifecycle and its refusals;
- a grant, its replay, and a replaced grant's revision;
- a new trigger, another schedule, another store and another Practice;
- RIDs against hashlib;
- 8 grant refusals, each made before any edit: with reads failing, the
  store stays ready;
- 13 requests and the standing each gets;
- revoking, and the schedule's next grant being a new permission;
- 22 edits a write must refuse and 5 it must accept;
- 11 kinds of damage on disk, each blocking the store and refused by every
  operation;
- a sync fault, a fault at the commit point, and a read fault.

Disabling any one of 63 guarded behaviors makes a check fail.
