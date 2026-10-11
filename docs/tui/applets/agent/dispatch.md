# The Agent's scheduled runs

`akashic/tui/applets/agent/dispatch.f` (`ADISP-`) runs the scheduled work
Desk's [broker](../desk/schedule-broker.md) hands the Agent. Each run
arrives as a plain
[dispatch request](../../../interop/scheduled-actions.md#requests), with
the authority the broker compiled for it from the user's permission. The
Agent:
- starts the run on exactly the model the request names;
- runs it in a conversation of its own, never the chat's;
- records it in its [run store](dispatch-store.md);
- tells the broker how it stands and how it ended.

The Agent lists the runs, and shows each one's transcript, in its
[scheduled runs view](scheduled-runs.md).

## One run at a time

The Agent runs one thing at a time. A scheduled run that cannot start
now, because chat or another scheduled run is running, waits and keeps its
place in line. The broker offers it again once the Agent is idle, and the
first run in line goes first.

Chat waits behind scheduled runs. While a scheduled run waits or runs,
`ARUNTIME-SEND` answers `ARUNTIME-E-HELD`, and the Agent shows "A
scheduled run goes first". Chat cannot cancel a scheduled run either:
`ARUNTIME-CANCEL` gives the same answer. Only Desk cancels one, for the
user, for a revoked permission, or at shutdown.

## Before a run starts

A run is refused, and nothing is recorded, when:

| Check | Reason |
|---|---|
| The Agent's provider is not the one the request names | model unavailable |
| The provider has no catalog, or its catalog does not offer exactly the model, effort, tier and verbosity named | model unavailable |
| The catalog is still loading, or the provider is not connected | Agent unavailable |
| The prompt does not fit the provider's room for a turn's input (`APROV-INPUT-FITS?`) | too large for the model |
| The authority is no longer active, or cannot disclose the prompt | invalid request |
| The run store cannot record the run | Agent unavailable |

A refused run ends blocked. Its authority stays the broker's, which frees
it.

A run that passes is recorded, accepted, and then started. If it cannot
start, it ends failed (its provider did not start), or blocked when there
was no memory for its conversation. Its record keeps whatever its
conversation says.

## How a run ends

| End | Outcome and reason |
|---|---|
| The model finished | completed |
| The model asked for a tool or an approval | stopped for review: asked to use a tool, or asked for approval |
| The run's time ran out | ran out: out of time |
| Its reply passed the run's limit | ran out: reply too long |
| Desk cancelled it | cancelled: by you, Desk shut down, or permission revoked |
| The provider failed, or ended the run itself | failed: provider error |

A scheduled run is offered no tools and reads no chat history. If its
model asks for a tool or an approval anyway, the request is shown in its
transcript and never made: the run stops for review.

A reply keeps no more than the run's output limit, cut where a character
ends. A reply past the limit runs out of room, however the run ended.

When a run ends, its conversation's messages go to the run store as its
transcript. A store that fails to write is tried again at the next pump.
One that cannot take the end at all is given up on. A blocked store's
next open finds the run still in flight and ends it as indeterminate.

## Operations

```forth
ADISP-SIZE    ( -- bytes )
ADISP-INIT    ( runtime vfs dispatch -- status )
ADISP-FINI    ( dispatch -- )
ADISP-VALID?  ( dispatch -- flag )
ADISP-STORE   ( dispatch -- store )
ADISP-START   ( request amrun response dispatch -- status )
ADISP-STATUS  ( key response dispatch -- status )
ADISP-CANCEL  ( key reason dispatch -- status )
ADISP-IDLE?   ( dispatch -- flag )
ADISP-BUSY?   ( dispatch -- flag )
ADISP-PUMP    ( dispatch -- )
```

`ADISP-INIT` configures a dispatcher for a runtime, with its run store at
`/agent-dispatch.bin` in the VFS. It opens the store, and it ends as
interrupted any run the store shows still in flight: the Agent was running
it when it last stopped. The status is the store's (`ADST-S-`). The
dispatcher works whatever state the store is in, so a store that cannot be
used can say why.

`ADISP-START`, `ADISP-STATUS` and `ADISP-CANCEL` answer with the dispatch
contract's `SDSP-S-` statuses, as Desk's broker expects of its handler.
- `ADISP-START` answers:
  - `STARTED`: the Agent owns the authority.
  - `WAITING`: the run keeps its place in line.
  - `RUNNING` or `ENDED`: a run the Agent knows by its dispatch key. A
    request that is not the one its key's run was started for conflicts:
    it ends indeterminate, and nothing new starts.
  - `ENDED`: a run refused, or one that could not start.

  The authority stays the caller's unless the answer is `STARTED`.
- `ADISP-STATUS` answers `RUNNING`, `WAITING`, `ENDED` or `UNKNOWN`. A
  response names the run's RID, its permission at its revision, and its
  Practice. Its summary gives the outcome, the reason and how many bytes of
  reply the run kept, never anything the run said. A summary larger than
  the response's capacity answers `SMALL`.
- `ADISP-CANCEL` takes a waiting run out of line, or stops the current
  run. A reason that cannot explain a cancelled run counts as the user's.

`ADISP-IDLE?` says whether a run could start now. `ADISP-BUSY?` says
whether a scheduled run waits or runs, for Desk's shutdown question.

`ADISP-PUMP` follows the current run after each runtime pump. It stops the
run once its reply passes its limit, takes its end once it is over, and
records that end. `ADISP-FINI` ends the current run as Desk shuts down,
records what it can, releases chat, and closes the store.

A run's correlation id is 2^48 plus its serial in the run store, so it
never meets a chat run's id.

## The runtime's side

The runtime (`runtime.f`) gives a run a conversation of its own:

| Word | Stack | Description |
|---|---|---|
| `ARUNTIME-IDLE?` | `( runtime -- flag )` | Whether a run could start now |
| `ARUNTIME-RUN-START` | `( address length run-id designation conversation amrun runtime -- ior )` | Starts a run in its own conversation, under authority lent until it starts |
| `ARUNTIME-RUN-ENDED?` | `( runtime -- flag )` | Whether that run is over, its end not yet taken |
| `ARUNTIME-RUN-TAKE` | `( runtime -- conversation status cause )` | Hands back its conversation, the status it ended in, and why it stopped for review |
| `ARUNTIME-RUN-STOP` | `( status runtime -- ior )` | Stops it, ending it cancelled or expired |
| `ARUNTIME-HOLD!` | `( flag runtime -- )` | Holds chat while a scheduled run waits or runs |

While such a run runs, the runtime's status is the run's. Once its end is
taken, the runtime goes back to the status it had before, so chat sees no
change.

## Qualification

`local_testing/test_agent_dispatch.py` runs a real runtime over the
device-flow source's scripted provider and catalog, with the run store on a
RAM filesystem and authority compiled as Desk's broker compiles it. It
checks:
- a run on the model it names while chat keeps its selection, chat held
  and unable to cancel it, its transcript, the names in its answers, and
  when it ran;
- known keys, and a conflicting request that starts nothing;
- 12 refusals that record nothing and leave the authority the caller's;
- stopping for review on a tool call and on an approval request, and the
  next run's end being its own;
- the waiting order, and chat waiting behind scheduled runs;
- a waiting run refused, or unable to start, when its turn comes;
- cancelling a running and a waiting run;
- output limits, including a cut that would split a character and a run
  that completed before the dispatcher looked, and time limits;
- a restart, including one whose reconcile could not be written;
- shutdown with a run in flight and with runs waiting;
- a store that fails to write an end, retried and given up on, and a store
  that cannot be used;
- a start the provider refuses;
- no chat history and no tools for a scheduled turn;
- the runtime's own words, used directly.

Disabling any one of 94 guarded behaviors of the dispatcher, or of 40 in
the runtime's part, makes a check fail, except five:
- the summary's check that it fits its buffer, which the catalog's texts
  never fill;
- the dispatcher's alignment check, which its store repeats;
- the end a review stop begins itself, which the provider's own cancel
  event also brings;
- `ARUNTIME-IDLE?`'s checks for an active run and for a running status,
  each of which the other covers, since a run sets both.
