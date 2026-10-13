# The Agent's scheduled runs view

F5, or Run > Scheduled runs, shows the scheduled runs the Agent's
[dispatcher](dispatch.md) recorded in its [run store](dispatch-store.md).
The view's model is `akashic/tui/applets/agent/scheduled-runs.f`
(`ASRV-`); the Agent draws it with an ordinary card list.

## Using it

Each run is a card, newest first:
- Its title is its schedule's title, from the request the run kept. A run
  past the store's keep setting kept only its row, and its title says
  "Run 3 (transcript not kept)".
- Its detail says when the run was accepted, how it ended, and the model it
  ran on, when the run kept its request. For example: `2026-10-10 12:00 UTC
  stopped for review: asked to use a tool  gpt-slow`. A run still going
  says `running`. A run accepted while the clock was not set says
  `time unknown`.

Enter opens a run's transcript where the chat's transcript shows. Escape
steps back: from a transcript to the runs, then from the runs to the chat.
F5 goes back to the chat from either, and Ask (Ctrl+L) goes back to the
chat and opens the prompt. The status bar says "Scheduled runs" or
"Scheduled run" while the view shows.

A run's title comes from its schedule, outside the Agent, so the list
shows it as untrusted text. A transcript shows as the chat's does.

Chat keeps going underneath. Its status, its toasts, and its review dialog
still show; the review dialog covers the runs as it covers the chat.

When the view has no cards, it says why:

| Note | Meaning |
|---|---|
| Scheduled runs come through Desk | The Agent has no dispatcher: it runs outside Desk |
| The record of scheduled runs cannot be read | The run store is blocked or closed |
| No scheduled runs yet | The store has no runs |

The cards follow the store. Once the store writes, the list counts its
runs again and keeps the selected run selected, or selects the newest.
Choosing a run after the store wrote, before the list counted again, opens
nothing and says the runs changed.

## Operations

```forth
ASRV-SIZE     ( -- bytes )
ASRV-INIT     ( dispatch view -- )
ASRV-FREE     ( view -- )
ASRV-STALE?   ( view -- flag )
ASRV-REBUILD  ( view -- )
ASRV-COUNT@   ( view -- n )
ASRV-KEY      ( index view -- key )
ASRV-SERIAL   ( index view -- serial )
ASRV-TITLE    ( index view -- address length )
ASRV-DETAIL   ( index view -- address length )
ASRV-NOTE     ( view -- address length )
ASRV-OPEN     ( index view -- status )
ASRV-SHOWN    ( view -- conversation|0 )
ASRV-CLOSE    ( view -- )
```

`ASRV-INIT` sets up a view over a dispatcher, or over 0 outside Desk. The
Agent finds its dispatcher as the service `org.akashic.agent.dispatch`,
which Desk lends it.

`ASRV-REBUILD` counts the rows. `ASRV-STALE?` says whether the store wrote
since, or stopped being readable. Row words take an index below
`ASRV-COUNT@`, row 0 the newest. `ASRV-KEY` gives a row's dispatch key, and
`ASRV-SERIAL` its serial, which names it across rebuilds. The text
`ASRV-TITLE` and `ASRV-DETAIL` return stays put until the next call into
the view or the store; it is 0 0 when there was no memory for it.

`ASRV-OPEN` decodes a row's transcript into a conversation the view owns,
in place of any shown before, and `ASRV-SHOWN` returns it. It answers:

| Status | Meaning |
|---|---|
| `ASRV-S-OK` 0 | Opened |
| `ASRV-S-NONE` 1 | No such row, the rows are stale, or the run kept no transcript |
| `ASRV-S-INVALID` 2 | The transcript could not be decoded |
| `ASRV-S-NOMEM` 3 | No memory for it |

`ASRV-CLOSE` frees the conversation shown. `ASRV-FREE` also frees the
text buffer and leaves the view empty.

The view is caller-owned and caller-serialized. It keeps all its state,
including its text buffer, in the caller's view record. Each text is
measured from its parts before it is written, so the buffer always has
room for it, however long the parts are; the buffer grows only when a text
needs more room than it has.

## Qualification

`local_testing/test_agent_scheduled_runs.py` reuses the dispatcher's suite:
a real runtime over the device-flow source's scripted provider, with the
run store on a RAM filesystem. It runs scheduled runs through a real
dispatcher and reads them back through the view:
- rows newest first, with their titles, details, keys and note;
- rows going stale when the store writes an end, and not while a run
  keeps running;
- transcripts opened, replaced, closed, and refused for a missing row,
  a row past the end, and stale rows;
- a run past the keep setting;
- the notes outside Desk, for no runs, for a store that cannot be read,
  and after Desk closes the dispatcher, and the detail of a run accepted
  while the clock was not set;
- a view set up over a record holding anything;
- a run accepted at a time past what a date can say;
- a store that closes and opens again over the same file;
- a transcript that cannot be decoded;
- each text filling exactly the room it asked for, and a shorter text
  using the room a longer one left;
- text and transcripts with no memory at all, by taking every block of
  external memory first;
- every byte the view takes, given back.

The `agent-ui` smoke profile opens the view with F5 inside the Agent
applet, sees its note, and goes back to the chat with Escape.

Disabling any one of 52 guarded behaviors of the view makes a check fail,
except one: `ASRV-OPEN`'s check for a row past the end. Without it, the
view reads the bytes just before the store's runs as a run, and in the
tests those bytes happen to hold no transcript. The check stays, since
the run table does not check its own bounds. An earlier pass found two
checks the store already makes, now gone: whether a run kept its request
(a trimmed run's request is empty) and whether a run has ended before its
reason is read (a run in flight has none). It also found behaviors no
test reached, now tested: a view set up over any record, the room each
text asks for, memory running out, and a time no date can say.
