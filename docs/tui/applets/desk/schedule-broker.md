# Desk's schedule broker

`akashic/tui/applets/desk/schedule-broker.f` (`SBRK-`) starts the
scheduled work Daybook hands over, and only work a user approved. It keeps
the [schedule permissions](../../../runtime/schedule-permission.md) and
answers Daybook through the
[dispatch contract](../../../interop/scheduled-actions.md#the-dispatch-contract).
A handler that Desk sets starts the runs.

A broker belongs to one Practice: its head, its root Context, and the
filesystem holding its permissions at `/schedule-perms.bin`. Neither
Daybook nor the handler sees the other. Daybook gets the broker's client
record, and the handler gets plain requests and the authority the broker
compiled.

## Operations

```forth
SBRK-SIZE          ( -- bytes )
SBRK-INIT          ( vfs head context broker -- status )
SBRK-FINI          ( broker -- )
SBRK-VALID?        ( broker -- flag )
SBRK-STORE         ( broker -- store )
SBRK-CLIENT        ( broker -- client )
SBRK-HANDLER!      ( handler broker -- )
SBRK-TICK          ( broker -- )
SBRK-ASKING        ( broker -- id request | 0 0 )
SBRK-ANSWER        ( id allowed? now broker -- status )
SBRK-REVOKE        ( rid broker -- status )
SBRK-ACTIVE?       ( broker -- flag )
```

`SBRK-INIT` takes a valid Practice head and its own root Context (the
Context's Practice must be that head), then opens the permissions. The
broker works whatever state the permissions are in, so a damaged file can
say why. The status is the store's: `SPERM-S-BLOCKED` for a file that
blocked the store, and `SPERM-S-INVALID` or `SPERM-S-STATE` for bad
arguments or a broker already open.

`SBRK-STORE` is the permission store, for listing. `SBRK-CLIENT` is the
client record for Daybook's service. The caller owns the `SBRK-SIZE`-byte,
cell-aligned broker and serializes every call; Desk calls it from its own
loop.

## The handler

`SBRK-HANDLER-INIT ( context handler -- )` makes a handler record
(`SBRK-HANDLER-SIZE`). Fill in its words through the `SBRK-H.` fields and
set it with `SBRK-HANDLER!`. A missing, damaged or moved record counts as no
handler.

| Word | Effect |
|---|---|
| start | `( request run response context -- status )` |
| status | `( key response context -- status )` |
| cancel | `( key reason context -- status )` |
| models | `( buffer capacity context -- bytes status )` |
| idle? | `( context -- flag )` |

Start gets a request and `run`, the authority the broker compiled for it.
It answers as status would after the attempt:

| Answer | Meaning |
|---|---|
| started | The run started. The response names it, and the handler now owns `run`. |
| waiting | It cannot start a run now. It keeps this run's place in line until start or cancel names the dispatch key again. |
| running, ended, small | A run with that dispatch key already exists. |
| ended | It refused, and the response says why. |

Any other answer means it could not answer. Unless the answer is started,
`run` stays the broker's, and the broker releases it.

Status, cancel and models answer as the client's words do, and a response
names the run's permission. Cancel ends a run for `reason`, or gives up a
waiting run's place. Idle? says whether start could start a run now.

## Daybook's client

| Word | What the broker does |
|---|---|
| submit | Checks the request and starts its run (below). A dispatch key the broker already knows is answered as status, so one occurrence handed over twice is one run. |
| status | Answers a run it holds, and asks the handler about any other. |
| cancel | Ends a waiting run itself, cancelled by you. A run that already ended at the broker is left as it is. It asks the handler to cancel any other run. |
| ask | Records an approval for Desk's user (below). |
| asked | Gives an approval's answer. |
| check | Says how a request that names no occurrence stands. |
| models | Asks the handler. |

### How a request stands

A request stands as `SPERM-MATCH` answers in Desk's Practice. One
exception: a permission whose limits differ from the ones the request's
operands carry has changed. The operand digest binds both, so they differ
only when the permission file was altered past its checks.

### Starting a run

A submitted request must be one `SDSP-REQUEST-OK?` accepts as a hand-over.
Anything else is invalid. The broker then:
1. Checks that the request's permission stands. If it does not, the run is
   blocked:

   | Standing | Reason |
   |---|---|
   | none | not approved |
   | withdrawn | revoked |
   | changed | changed |
   | another Practice | another Practice |
   | unavailable | Agent unavailable |

2. Compiles the run's authority from that permission alone, never from a
   chat preset:
   - a new active child of the Practice's root Context, with no
     filesystem, bindings or facets;
   - a capability facet with no entries;
   - a read-only Mandate for the Agent, with the permission's effects
     (none today) and its time and disclosure limits, and no tool,
     memory or token budget.

   The Mandate's and the facet's IDs are SHA3-256 of the Practice, the
   activation's epoch, the dispatch key, the child Context's ID and
   generation, and a tag (`desk.schedule.mandate` or
   `desk.schedule.facet`). An authority that cannot be made fails as an
   internal error, or is blocked as out of room when memory ran out.
3. Offers the run to the handler.

An answer other than the five above blocks the run as the Agent being
unavailable. When the broker blocks or ends a run itself, the response
names the request's permission and revision and Desk's Practice, and holds
no run and no summary. That way Daybook clears its approval only when the
refusal is about the permission it holds.

### Waiting runs

A run the handler answers waiting stays with the broker, holding a copy of
its request. Runs wait in the order they were handed over. Each
`SBRK-TICK` goes through them while the handler is idle, and offers each
one again as above. So a waiting run is checked again, and gets a freshly
compiled authority, only when it can start.
- A run that starts lets go of its request.
- A run the handler answers waiting again stops the tick. The runs behind
  it are not offered, so none of them can go first.
- A run that is refused, or that the handler ends without naming a run,
  ends at the broker, and the handler gives up its place.
- A run the handler ends while naming a run is the handler's. Status asks
  the handler about it.

### Remembering runs

The broker remembers the runs of this session until Daybook hears how they
ended:
- A waiting run answers waiting.
- A run the broker ended is told once, and then forgotten.
- A started run is asked about through the handler. It is forgotten once
  the handler says it ended in full, or that it knows no such run.

The handler keeps the record of each run it started.

## Approvals

Ask takes a request that `SPERM-GRANTABLE?` accepts in Desk's Practice.
Anything else is invalid, and nothing is recorded. The broker keeps a copy
of the request and answers pending with the approval's id. Ids count up
from 1.

Approvals wait in the order they were asked for. `SBRK-ASKING` gives the
oldest one awaiting an answer, with its request; the pointer stays valid
until the broker is next called. Desk shows that request.

If the same schedule of the same store is asked about again, the broker
withdraws the approval still awaiting an answer for it. An approval that
was already answered keeps its answer.

`SBRK-ANSWER` records the user's answer. `now` is the wall clock in
milliseconds, or -1 when it is not set.
- Allow grants the request's permission in Desk's Practice with
  `SPERM-GRANT`. If the store refuses the grant, the approval keeps
  waiting, and the status is the store's.
- Refuse records a refusal.
- An id that is unknown, or already answered, is `SPERM-S-NOT-FOUND`.

Asked answers pending while the user has not answered. After that it gives
the answer once, then forgets the approval:
- allowed, with the response naming the permission, its revision and the
  Practice;
- refused;
- gone, for an approval that was withdrawn, or that it no longer knows.

## Revoking, closing, and what is in flight

`SBRK-REVOKE` revokes a permission through the store. If that write fails,
the status is the store's and nothing else changes. Otherwise every run in
flight under the permission is cancelled, as revoked:
- a waiting run ends at the broker, and gives up its place;
- the handler cancels a run that started.

`SBRK-ACTIVE?` answers whether a run is in flight: waiting, or started and
not ended as far as the handler says. Ended, too long to tell, or unknown
all count as over. Any other answer, or no handler, counts as in flight.

`SBRK-FINI` cancels every run in flight, because Desk shut down, in the same
way revoking does. It then frees what the broker holds and closes the
store.

## Qualification

`local_testing/test_schedule_broker.py` runs on the native simulator over a
RAM filesystem, with a fake handler. The fake retains each run it is given,
as a gateway would. A run the broker keeps is therefore seen to be released
by the broker, and a run the handler took is seen to be left alone. The
suite checks:
- the lifecycle and its refusals;
- approvals, their answers and order, and the one a repeated ask
  withdraws;
- grants the store refuses;
- each standing;
- every refusal before the handler is offered a run, including handler
  records that are not one;
- the authority a run gets, and its IDs against hashlib;
- each answer the handler can give;
- waiting runs, which start in order once the handler is idle and are
  checked again as they start;
- cancelling, revoking and closing;
- what counts as in flight.

Disabling any one of 145 guarded behaviors makes a test fail, except one.
`SBRK-ANSWER` checks for an unknown id before it reads the approval. Without
that check, it reads the state of a null approval from low memory, which
happens not to say pending, so the answer is still not found.
