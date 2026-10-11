# Scheduled actions and dispatch

Two modules carry scheduled work between Daybook, Desk and the Agent
without any of them importing another:
- [`interop/scheduled-action.f`](../../akashic/interop/scheduled-action.f)
  (`SACT-`) is the closed catalog of actions a schedule can name, and
  their operands.
- [`interop/scheduled-dispatch.f`](../../akashic/interop/scheduled-dispatch.f)
  (`SDSP-`) is the portable contract through which Daybook's runner hands
  an occurrence to Desk's broker.

## The catalog

| Action | Name | Class |
|---|---|---|
| `SACT-REMINDER` (1) | `daybook.reminder` | `SACT-MANUAL`: a due item for review; never dispatched |
| `SACT-AGENT-RUN` (2) | `agent.run.request` | `SACT-AUTOMATIC`: one bounded Agent run, started by Desk's broker under a schedule permission |

Each action has one schema, `SACT-SCHEMA` (1). `SACT-CLASS ( action schema
-- class|0 )` answers 0 for anything outside the catalog, and
`SACT-OPERANDS-OK? ( action schema operands u -- status )` checks operands.
A reminder takes none.

### An Agent run's operands

An Agent run's operands are variable length, so a prompt is as long as it
needs to be. The real limit is how much the chosen model's provider
accepts, which the Agent checks before a run starts.

Every field is either a cell or a string. A string is a cell holding its
length, then its bytes, zero-padded to a cell. The fields come in a fixed
order, so one request has exactly one encoding:

| Field | Rule |
|---|---|
| schema | 1 |
| flags | `SACT-F-CONTEXT` only; refused until runs take context |
| effects | 0 (observation only arrives with context) |
| time ms | positive |
| disclosure bytes | positive, and at least the prompt's length, since the prompt is disclosed |
| output bytes | positive: how much of the reply is kept |
| verbosity | 0 to 3, the Agent's `ARVERB-` values |
| provider id | nonempty text without control characters |
| model id | nonempty text without control characters |
| effort id | text without control characters; empty when the model has none |
| tier id | the same |
| context locator | 320 bytes, present only with `SACT-F-CONTEXT` |
| prompt | nonempty UTF-8; tabs and line feeds are the only control characters |

A schedule therefore names its model exactly; the run never falls back to
whatever is selected. The operands never hold a live grant, an LBIND, a
component pointer or an XT.

To build operands, fill a draft (`SACT-DRAFT-SIZE`) with addresses and
lengths through `SACT-D!` and the `SACT-D.` fields. Then call
`SACT-AGENT-ENCODE ( draft dest cap -- bytes status )`, which writes the
canonical bytes and checks them. A destination too small takes nothing,
and the call answers `SACT-S-SMALL` with the size needed.
`SACT-PROVIDER$`, `SACT-MODEL$`, `SACT-EFFORT$`, `SACT-TIER$`,
`SACT-PROMPT$` and `SACT-O.CONTEXT` read the parts back.

`SACT-DIGEST ( action schema operands u dest -- )` is SHA3-256 of the
domain `akashic.sched.operands.v1`, the action, schema and length as u64,
and the bytes. A [schedule permission](../runtime/schedule-permission.md)
binds this digest, so changing the model, prompt or limits needs approval
again.

### Outcomes and reasons

Daybook, Desk and the Agent report a run's end with one closed vocabulary.
`SACT-OUTCOME-OK? ( outcome reason -- flag )` accepts only these pairs:

| Outcome | Reasons |
|---|---|
| completed | none |
| blocked | not approved, revoked, changed, another Practice, Agent unavailable, model unavailable, too large for the model, out of room, invalid, a run already in progress, document unavailable |
| not started | missed, Desk restarted before it ran |
| cancelled | revoked, by you, Desk shut down |
| stopped for review | asked to use a tool, asked for approval, the document changed |
| ran out | time, reply too long, over the disclosure limit |
| failed | provider error, provider did not start, document unreadable, internal error |
| indeterminate | interrupted, Agent's record uncertain, Agent has no record, conflicting request |

`SACT-OUTCOME$` and `SACT-REASON$` give each a short phrase for display.
`SACT-LINE-OK?` checks single-line display text such as titles and
summaries.

## The dispatch contract

### Requests

A request is a fixed header (`SDSP-REQUEST-HEAD`, 288 bytes) followed by
three strings:
- the schedule's title;
- its trigger, a summary of when it runs;
- its operands.

The header holds:
- the action and schema;
- the Practice;
- the store's identity, and the schedule's RID and revision;
- the occurrence id and kind, and the dispatch key;
- the permission's RID and revision;
- the operand and trigger digests;
- the tail length and the size the request was made for.

A request holds no object, pointer or callback, so it can be copied byte
for byte.

To build one:
1. Size it with `SDSP-REQUEST-SIZE`.
2. Clear it with `SDSP-REQUEST-INIT`.
3. Fill the header through the `SDSP-R.` fields.
4. Append the title, trigger and operands with `SDSP-TAIL+`.

The dispatch key is `SDSP-KEY ( store rid id dest -- )`: SHA3-256 of the
domain `akashic.daybook.dispatch.v1`, the store's identity, the schedule
RID and the occurrence id as u64. There is one key per occurrence, and the
Agent maps it to exactly one run.

`SDSP-REQUEST-OK? ( request occurrence? -- status )` checks a request
whole:
- its recorded size;
- an automatic action;
- a store, a schedule and a positive revision;
- a nonempty one-line title, a one-line trigger, and valid operands whose
  digest matches the header.

A request that hands over an occurrence must also name the Practice, an
occurrence kind (on time, missed or Run Now), a positive occurrence id, and
that occurrence's own dispatch key. Any other request, such as an approval
or a standing check, names no occurrence. It may leave the Practice for
Desk to supply.

### Responses

A response (`SDSP-RESPONSE-SIZE ( capacity -- bytes )`) holds:
- the outcome and reason;
- the run's RID;
- the permission's RID and revision, and the Practice that approved it;
- a summary of up to the capacity the caller set.

A summary never holds run content. `SDSP-SUMMARY!` answers `SDSP-S-SMALL`
when the summary is longer than the capacity, and records its length so
the caller can ask again with room for it.

### The client

Desk fills a client record (`SDSP-CLIENT-SIZE`) with
`SDSP-CLIENT-INIT ( context client -- )` and the `SDSP-C.` word fields, and
gives it to Daybook's service. Each word answers `SDSP-S-UNAVAILABLE` when
the client is missing, damaged, or lacks that word. Desk's
[broker](../tui/applets/desk/schedule-broker.md) fills it.

| Word | Effect | Answers |
|---|---|---|
| `SDSP-SUBMIT` | `( request response client -- status )` | started, waiting, ended, invalid, unavailable |
| `SDSP-STATUS` | `( key response client -- status )` | running, waiting, ended, unknown, unavailable, small |
| `SDSP-CANCEL` | `( key client -- status )` | ok, unknown, invalid, unavailable |
| `SDSP-ASK` | `( request client -- ask-id status )` | pending, allowed, invalid, unavailable |
| `SDSP-ASKED` | `( ask-id response client -- status )` | pending, allowed, refused, gone |
| `SDSP-CHECK` | `( request client -- standing status )` | standing: approved, none, withdrawn, changed, another Practice, unavailable |
| `SDSP-MODELS` | `( buffer capacity client -- bytes status )` | a model list, or small |

### Model lists

A model list holds:
- a count;
- the provider id;
- for each model:
  - its id, label and flags (`SDSP-M-VERBOSITY`);
  - its efforts and its tiers, each as a count followed by an id and a label
    for each one.

Check it with `SDSP-LIST-OK? ( list u -- flag )` before reading it. The
`SDSP-LIST-`, `SDSP-MODEL-` and `SDSP-CHOICE-` words then read it without
leaving its bytes. Desk writes lists with `SDSP-PUT` and `SACT-STR!`.

## Qualification

`local_testing/test_scheduled_action.py` (53 tests, native executor)
checks:
- the catalog;
- the canonical bytes against a Python encoder, including a prompt with
  tabs, line feeds and multibyte text;
- every refusal of malformed operands and drafts;
- the operand digest and dispatch key against `hashlib`;
- every outcome and reason pair against the table above;
- requests and each rule they are checked against;
- responses;
- clients without words, or with a damaged header;
- model lists, including truncated ones and ones with trailing bytes.

Disabling any one of 27 guarded behaviors makes a test fail.
