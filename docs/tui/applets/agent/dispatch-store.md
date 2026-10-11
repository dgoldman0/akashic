# The Agent's scheduled runs

`akashic/tui/applets/agent/storage/dispatch-store.f` (`ADST-`) is the
Agent's record of the scheduled runs Desk's
[broker](../desk/schedule-broker.md) hands it. The Agent records a run
before its provider starts, so a run that may have started is never
forgotten, and records how it ended, with its transcript.

A run is the Agent's answer to one occurrence's
[hand-over](../../../interop/scheduled-actions.md#requests): its dispatch
key names the run for good. Handing the same occurrence over again finds
the same run instead of starting another.

## What a run keeps

| Field | Meaning |
|---|---|
| serial | The run's place in the store's count, from 1 |
| phase | Accepted (in flight: its provider may have started) or ended |
| outcome, reason | How it ended, as a pair the [catalog](../../../interop/scheduled-actions.md#outcomes) allows; 0 while in flight |
| run RID | SHA3-256 of `akashic.agent.dispatch-run.v1`, the store's identity, the Practice and the dispatch key |
| dispatch key | The occurrence's key, from its request |
| request digest | SHA3-256 of `akashic.agent.dispatch-request.v1` and the request's bytes |
| Practice | The Practice its request names |
| permission, revision | The permission its request names, at that revision |
| accepted, ended | Wall-clock milliseconds, or 0 when the clock was not set or the run has not ended |
| reply bytes | How much reply the run kept |
| request | The request the run ran, byte for byte |
| transcript | The run's conversation as `ATHREAD-ENCODE` wrote it; the store keeps it opaque |

The newest ended runs keep their request and transcript, as many as the
store's keep setting says. It is 32 until changed. Older ended runs are
trimmed to their row: when they ran, how they ended, and the run's
identity. A run in flight is never trimmed. Rows are kept for good: how
long the Agent keeps its history belongs to the Practice's log and
retention settings, which are not yet built.

The request digest still tells a later hand-over with the same key apart
once a run is trimmed.

## Operations

```forth
ADST-INIT         ( vfs path path-u store -- status )
ADST-OPEN         ( store -- status )
ADST-CLOSE        ( store -- status )
ADST-STATE@       ( store -- state )
ADST-REASON@      ( store -- reason )
ADST-GENERATION@  ( store -- n )
ADST-HEADER       ( store -- header )
ADST-COUNT@       ( store -- n )
ADST-NTH          ( index store -- run )
ADST-FIND         ( key store -- run|0 )
ADST-KEPT?        ( run -- flag )
ADST-REQUEST$     ( run -- address length )
ADST-TRANSCRIPT$  ( run -- address length )
ADST-DIGEST       ( request dest -- )
ADST-ACCEPT       ( request now store -- run status )
ADST-TRANSCRIPT!  ( address length run store -- status )
ADST-FINISH       ( outcome reason reply-u now run store -- status )
ADST-RECONCILE    ( now store -- n status )
ADST-KEEP!        ( n store -- status )
```

`now` is the wall clock in milliseconds, or -1 when it is not set.

`ADST-ACCEPT` records the run a request asks for, before its provider
starts. The request must be an occurrence's hand-over that
`SDSP-REQUEST-OK?` accepts, naming a permission at a revision; anything
else is `ADST-S-INVALID` and writes nothing. When a run with its dispatch
key is already recorded, that run is returned unchanged:
`ADST-S-EXISTING` when it was accepted for exactly this request, byte for
byte, and `ADST-S-CONFLICT` when not.

`ADST-TRANSCRIPT!` sets the transcript of a run in flight to its own copy
of the bytes. It is written with the next write, normally `ADST-FINISH`'s.

`ADST-FINISH` ends a run in flight with an outcome and reason the catalog
pairs, and the reply bytes it kept. A run its provider refused to start
ends blocked. None ends as not started, which only Daybook records, for a
run it never handed over. Ending a run trims the oldest ended runs past
the keep setting.

A write that fails reloads the last committed file. A run that failed to
end is therefore in flight again, without the transcript it was given:
whoever retries the end gives the transcript again.

`ADST-RECONCILE` ends every run still in flight as indeterminate,
interrupted. Those are runs the Agent was running when it last stopped,
which may or may not have reached their provider. The Agent calls it once
when it opens the store, before it runs anything, and nothing is written
when no run was in flight.

`ADST-KEEP!` sets how many ended runs keep their request and transcript.
Lowering it trims at once; raising it brings nothing back. A setting below
zero is `ADST-S-INVALID`.

A run a word returns stays put until the next operation.

| Status | Meaning |
|---|---|
| `ADST-S-OK` | Done |
| `ADST-S-INVALID` | A bad argument, request or end, or a write whose file would break a rule |
| `ADST-S-NOMEM` | Memory ran out; a write reloaded the file |
| `ADST-S-IO` | The disk refused a write; the file is unchanged and was reloaded |
| `ADST-S-BLOCKED` | The store is blocked; see `ADST-REASON@` |
| `ADST-S-STATE` | The store, or the run, is in the wrong state for the call |
| `ADST-S-ENTROPY` | No identity could be drawn |
| `ADST-S-EXISTING` | The key's run was accepted for exactly this request |
| `ADST-S-CONFLICT` | The key's run was accepted for another request |

The caller owns the `ADST-SIZE`-byte, cell-aligned store and serializes
all calls. The store does not limit how many runs are in flight. The
Agent's one-run-at-a-time rule is the runtime's.

## The file

The Agent keeps the store at `/agent-dispatch.bin`, replaced whole and
atomically through [vfs-replace](../../../utils/fs/vfs-replace.md). The
file is a checked record ([checked-record](../../../utils/checked-record.md))
with magic `AKAGDISP`, format 1, and its generation as the tag. Its
payload is:
- a 64-byte header: the store's identity, the next serial, the keep
  setting, the run count and the blob's size;
- a 264-byte record per run, in serial order;
- a 40-byte key per run, the dispatch key and the run's serial, in key
  order;
- a blob region holding each kept run's request and then each one's
  transcript, each padded to a cell ([blob-slot](../../../utils/blob-slot.md)).

Runs and keys are [record tables](../../../utils/record-table.md), so
memory and the file bound how many there are, not a count. Each write
rewrites the whole file, kept transcripts included.

OPEN finishes or undoes an interrupted replacement, then reads the file.
A missing file is an empty store. OPEN refuses a file unless every rule
holds, and each write checks its file the same way first:
- The count and the blob's size describe the payload exactly.
- The store has an identity, and the serial counter is past zero.
- The runs are strictly ascending by serial, each below the counter.
- Each run's RID is the one its Practice and key give.
- Each run has a key, a request digest, a Practice and a permission at a
  revision. Its times and reply bytes are not negative, and its reserved
  bytes are zero.
- A run in flight has no outcome, reason, end time or reply bytes, and
  keeps its request. It may hold its transcript so far.
- An ended run has an end a recorded run may have. It keeps its request,
  or neither request nor transcript.
- No more ended runs keep their request than the setting says, so the
  setting is not below zero.
- The keys are strictly ascending, and each names, by serial, a run with
  that key.
- Each kept request is a hand-over `SDSP-REQUEST-OK?` accepts, exactly as
  long as its record says, with its run's digest, key, Practice,
  permission and revision.
- The blob holds each part where its slot says, and nothing else.

A file the store cannot trust blocks it, with a reason, instead of opening
empty. Damage never reads as having no runs, which would let a repeated
hand-over start a run again.

| Reason | Cause |
|---|---|
| `ADST-R-CORRUPT` | A bad CRC, truncation, a broken rule, or an older format |
| `ADST-R-FUTURE` | A format newer than this code reads |
| `ADST-R-UNCERTAIN` | A replacement whose outcome nobody can tell |
| `ADST-R-IO` | The file could not be read into memory |

A replacement that may or may not have reached the disk blocks the store
until the next OPEN recovers whichever file survived.

## Qualification

`local_testing/test_agent_dispatch_store.py` runs on the native simulator
over a RAM filesystem whose operations the test can replace. It checks:
- the lifecycle and its refusals;
- accepting a run, the same hand-over again, and conflicting ones;
- 9 accept refusals, each made before any edit: with reads failing, the
  store stays ready;
- transcripts and ends, 10 end refusals and 4 transcript refusals;
- each of 8 ends a recorded run may have;
- the keep setting, trimming, and runs in flight left whole;
- finding runs across a gap in the serials;
- reconciling runs left in flight;
- RIDs, keys and request digests against hashlib;
- the file's layout, byte for byte;
- 41 edits a write must refuse and 13 it must accept. Each refused edit
  keeps the rest of the file consistent, so only its own rule refuses it;
- 18 kinds of damage on disk, each blocking the store and refused by every
  operation, and a changed transcript byte, which is no damage;
- a sync fault while accepting and while ending, a fault at the commit
  point, and a read fault.

Disabling any one of 114 guarded behaviors makes a check fail, except
seven:
- Three checks that the count and blob size describe the payload. A file
  with a wrong count or blob size misplaces the runs, keys or blob, and the
  checks of those refuse it anyway. The guards keep the reads inside the
  payload.
- The check that a kept request's bytes hold a header before it is read.
  The size check refuses a short request anyway; the guard keeps the read
  inside its bytes.
- The check that runs ascend by serial. Every key finding its run by binary
  search already implies it.
- `ADST-FIND`'s check for an unknown key. Without it the store reads low
  memory, which is zero in the simulator, and no run has serial zero.
- Removing a new run whose request could not be copied. No test here can
  make memory run out at that point.
