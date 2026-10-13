# Agent Provider and Source Contracts

Akashic's Agent applet separates a live provider from the environment that
constructs it. Both contracts are native, internally provider-neutral, and
renderer-free so they can be tested directly. They remain Agent applet-owned
code inside the Desk/TUI ecosystem; renderer independence does not make Agent
a standalone product domain.

## Provider

`akashic/tui/applets/agent/provider.f` defines `APROV`, the live behavior used by
`ARUNTIME`. A provider owns its active sessions and implements connection,
streaming, cancellation, approval, tool-result, and optional authentication
callbacks.

Authentication is deliberately generic:

| Word | Stack | Description |
|---|---|---|
| `APROV-AUTH` | `( provider -- auth \| 0 )` | Borrow the provider's `AAUTH` port |
| `AAUTH-READY?` | `( auth -- flag )` | Report whether an access credential is usable |
| `AAUTH-PENDING?` | `( auth -- flag )` | Report a starting, login-pending, or refreshing operation |
| `AAUTH-BEGIN` / `AAUTH-CANCEL` | `( auth -- status )` | Start or cancel an account login |
| `AAUTH-POLL` | `( auth -- status )` | Advance a pending authentication operation |
| `AAUTH-SECRET-SET` | `( secret-a secret-u auth -- status )` | Replace an opaque direct-provider secret |
| `AAUTH-WITH-ACCESS` | `( callback context auth -- status )` | Borrow access bytes only for one callback |
| `AAUTH-REFRESH` / `AAUTH-LOGOUT` | `( auth -- status )` | Rotate account tokens or clear authentication |

Providers that expose this port set `APROV-F-AUTH`. Its method mask,
state, account metadata, and callbacks cover direct secrets, device login, and
future account systems without naming a vendor. A local provider can omit it.

`ARUNTIME-AUTH-SET`, `ARUNTIME-AUTH-CLEAR`, `ARUNTIME-AUTH-PRESENT?`,
`ARUNTIME-AUTH-BEGIN`, and `ARUNTIME-AUTH-CANCEL` coordinate user operations
with provider connection state. The runtime pumps pending auth before model
and tool work. Secret replacement, logout, and login start are rejected while
a run or review is active.

Model and run options are also provider-neutral. A provider may expose a
borrowed `ARSET` port through `APROV.RUN-SETTINGS`; descriptors and strings
remain provider-owned until its revision changes.

| Word | Stack | Description |
|---|---|---|
| `APROV-RUN-SETTINGS` | `( provider -- settings \| 0 )` | Borrow the provider's optional `ARSET` port |
| `ARSET-REFRESH` / `ARSET-POLL` | `( settings -- status )` | Start or advance model discovery |
| `ARSET-MODEL-NTH` | `( index settings -- model \| 0 )` | Borrow one discovered model descriptor |
| `ARSET-MODEL!` | `( index settings -- status )` | Select a model |
| `ARSET-EFFORT!` / `ARSET-TIER!` | `( index settings -- status )` | Select a model-supported reasoning effort or service tier |
| `ARSET-VERBOSITY!` | `( verbosity settings -- status )` | Select provider-supported text verbosity |

`ARUNTIME-RUN-SETTINGS-REFRESH`, `ARUNTIME-MODEL!`,
`ARUNTIME-EFFORT!`, `ARUNTIME-TIER!`, and `ARUNTIME-VERBOSITY!` reject
changes during a run or review. Desk and Agent render these choices without
depending on Codex, OpenAI, or any particular model slug.

### Designations

A turn runs on the selected model unless it names another in a designation.
A designation (`AGENT-RUN-DESIGNATION-SIZE`, the `ARDES.` fields) names a
model, an effort and a tier by id, and a verbosity. It borrows its strings. A
scheduled run keeps one from when it was approved, so it runs on exactly the
model the user approved, whatever is selected when it runs. An empty effort
names none, for a model that has none. An empty tier asks for no service
tier.

`ATURN.DESIGNATION` holds a turn's designation, or 0 for the selection. A
provider running a designated turn leaves the selection as it was.

| Word | Stack | Description |
|---|---|---|
| `ARSET-DESIGNATION` | `( designation settings -- model\|0 status )` | The model the catalog offers for exactly what the designation names |
| `ARSET-FIND-MODEL` | `( id-a id-u settings -- model \| 0 )` | The model with an id |
| `ARMODEL-FIND-EFFORT` / `ARMODEL-FIND-TIER` | `( id-a id-u model -- index )` | A choice's index by id, or -1 |
| `ARMODEL-SELECTED-EFFORT` / `ARMODEL-SELECTED-TIER` | `( model -- choice \| 0 )` | The model's selected choice |

`ARSET-DESIGNATION` answers OK only when all of these hold:
- the model is in the catalog;
- its effort is one of the model's, or none for a model with none;
- its tier is none or one of the model's;
- its verbosity is automatic, or the model lets a run choose one.

Otherwise it answers `ARSET-S-UNSUPPORTED`. The answer is `ARSET-S-PENDING`
while the catalog is not ready, and `ARSET-S-INVALID` for a missing argument
or a verbosity outside the `ARVERB-` values.

A provider without a catalog runs no designated turn. The scripted
provider checks a designation against the catalog its source gives it, as
the device-flow source does. `SCRIPTED-LAST-RUN` reports the model, effort,
tier and verbosity its last turn ran on; `test_agent_designation.py` covers
designations and the scripted provider.

Disabling any one of the guarded behaviors in designations, the input room,
the Responses engine's designated sessions and the Codex designator makes a
native test or a smoke fail, except one. `ARMODEL-SELECTED-EFFORT` checks
for no model before it reads one. Without that check it reads low memory,
which is zero in the simulator, so the answer comes out the same.

### Input room

`APROV-INPUT ( prompt-a prompt-u reference-a reference-u provider -- used
capacity )` tells how much of the provider's room for one turn's input a
turn with that prompt and reference and no history takes, and how large that
room is. `0 0` is no reference. A reference at address 0 is that many bytes
of text not yet read, counted at the least such text takes. The capacity is
-1 when only memory bounds it, or when the provider does not say.
`APROV-INPUT-FITS? ( prompt-a prompt-u reference-a reference-u provider --
flag )` says whether it fits. A provider fills `APROV.INPUT-XT`
`( prompt-a prompt-u reference-a reference-u context -- used capacity )`.
A scheduled run's prompt, with as much of its document as it may disclose,
is checked against this room when it is approved and again before it
starts, and once its document is read, the prompt and the text are checked
exactly. A turn that does not fit is refused, never cut.

### References

A turn may carry one reference (`ATURN-REFERENCE`): a document's text,
which the model reads as data. A provider sends it apart from the prompt
and never as instructions. The OpenAI encoder sends it as a user item of
its own ahead of the prompt: a note that the next text is a reference
document to read as data, then the text, each an input text.
`OAI-TURN-INPUT-U` counts it exactly. The scripted provider does not echo a
reference: its reply says how many bytes it had and the first eight hex
digits of its SHA3-256, and `SCRIPTED-LAST-REFERENCE` tells the same.

The native OpenAI transport sizes a turn's input, its request body and its
tool history to what they hold, and sends the body without copying it, so
only memory bounds a turn's input and `APROV-INPUT` reports a room of -1. A
tool result keeps the gateway's 32 KiB ceiling. The transport's default
maximum assembled response text is 49,152 bytes. That lower output
boundary leaves room for the visible response, its model-context copy, and thread
metadata to coexist under the 262,144-byte conversation snapshot ceiling; the
transport limit is not presented as an aggregate history budget.

## Provider Source

`akashic/tui/applets/agent/provider-source.f` defines `APSOURCE`, an owned construction
environment. It exists because transports, credential containers, and local
model runtimes may need to outlive the provider objects that borrow them.

| Word | Stack | Description |
|---|---|---|
| `APSOURCE-PROVIDER-NEW` | `( source -- provider status )` | Construct one live provider |
| `APSOURCE-FREE` | `( source -- )` | Release and, where applicable, zero the environment |

The owner must free objects in this order:

1. Agent runtime.
2. Provider.
3. Provider source.

Desk follows this order and exposes its shared source as the service
`org.akashic.agent.provider-source`. A directly composed Agent applet owns the
same three objects for renderer-free tests. Source selection is explicit through `DESK-AGENT-SOURCE!` or
`AGENT-SOURCE!`; loading a provider module has no selection side effect.

`providers/offline.f` and `providers/devtools/scripted.f` supply sources through
the same contract. There is no parallel global factory path. The scripted
provider's replies depend only on the prompt. After echoing it, a prompt
naming a "source" or a "task" asks for a tool, one naming an "approval"
asks for an approval, and one naming "linger" keeps the run open, saying
nothing more, until it is cancelled. Any other prompt completes.

## Desk Access Profiles

`tui/applets/agent/access-profile.f` owns the profile record, structural
validation, and stable selector vocabulary used by Agent's controls.
`tui/applets/desk/agent-access-policy.f` owns the exact `desk.*` identities,
budgets, and effects. Desk injects both its constructor and exact validator
into each runtime. Selection is staged in runtime-owned memory and copied into
the live profile only after both validations succeed; later reads and Mandate
construction repeat the exact-policy check so a structurally valid mutation
cannot expand authority.

Desk owns the visible Agent access choice and compiles it into a fresh Practice
Mandate for each run. The profile is policy input, not authority by itself: the
compiled facet pins each operation to one trusted built-in component descriptor
and one live instance, while the capability bus still checks and consumes its
sealed grant. Changing the visible profile during a run or review is rejected,
and a scoped run fails closed if Desk's Mandate factory is unavailable.

`tui/applets/desk/agent-cap-catalog.f` is Desk's closed, declarative policy
input for that compilation. Applets and packages cannot register Agent rows.
Each catalog row fixes the component identity, operation identity, effects,
review/disclosure flags, result bound, and allowed presets. Desk still omits a
row unless the exact trusted built-in descriptor has a live instance whose
capability effects match the row, so the table neither discovers components nor
creates authority. The facet ABI holds 24 entries. Each preset compiles into
one facet, so the rows any one preset allows must fit in it; the catalog as a
whole may hold more.

Desk starts in **Chat only**. The built-in profiles are deliberately exact:

| Profile | Full-Desk rows | Tool calls | Disclosure bytes | Agent-visible authority |
|---|---:|---:|---:|---|
| Chat only | 0 | 0 | 8192 | Bounded prior user/assistant turns; no applet capabilities |
| Practice read only | 13 | 4 | 32768 | Chat history plus bounded Daybook, Pad, Files, Grid, Streams and Library status observations; no mutation |
| Practice assist | 23 | 8 | 49152 | The read facet plus fixed local navigation, ordinary applet changes, reviewed Library document/collection creation, and sandbox modules: tested, installed after review, and invoked |
| Practice Library Burrow | 24 | 12 | 49152 | The read facet, Assist's changes and Library creation, sandbox tests, and reviewed Streams burrow create, start, and stop operations |

The row counts are maxima for a complete Desk composition; a run omits rows for
trusted applets or operations that are not live. Library document query/read is
intentionally absent because those potentially large values are staged through
Desk context rather than exposed as ambient Agent tools. Every non-observation
row requires one visible local review. Destructive and external effects are not
present in any built-in profile.

Observation results are capped per facet entry (text results currently at 4096 raw
bytes), prompts at 512 bytes, and prior history at 12 messages and 4096 bytes.
Each run also receives a ten-minute wall-time budget, a profile-specific tool
count, and an aggregate disclosure budget. Token and memory fields are zero
because those meters are not yet implemented; the UI and documentation must
not imply that they are enforced.

One `AMRUN` is the accounting and lifetime owner for all gateways bound to that
run. Gateways retain it while bound, so closing the owner immediately disables
new authority but defers physical reclamation until the last gateway releases
its reference. Tool reservations, disclosure reservations and refunds, active
checks, and lifecycle transitions share one exception-safe accounting guard.
Consequently, two gateways on different cores cannot each spend the last unit
of the same budget. Heap-owning `AMRUN` and gateway construction, and gateway
call construction, are core-0 operations; worker entry is rejected before an
allocator-backed path is reached.

The gateway reserves the operation's bounded result allowance before a request
can run. Completion measures the exact compact IVJSON delivered to provider
context, retains that actual charge, and refunds the unused reservation;
terminal failure and pre-dispatch rollback refund the outstanding reservation.
An unencodable or over-limit handler result is replaced with bounded JSON
`null` after a successful effect rather than inviting a duplicate retry. The
entire measurement buffer is erased on success, codec failure, and exception.
Both `CBUS-S-OK` and `CBUS-S-NO-EFFECT` are result-bearing completions. The
gateway measures and charges either result, the model context and provider keep
the actual typed receipt, and the transcript marks the reviewed operation
complete while retaining the raw bus status. `NO-EFFECT` is therefore visible
as successful convergence, not rewritten to `OK`; only the owner decides that
no new revision or component touch occurred.

Gateway state is held only while preparing or transitioning an owned request.
The resulting request/bus continuation is carried per call, and the state guard
is released before `CBUS-POST` or `CBUS-DISPATCH`. Completion may therefore
enter gateway state while the capability bus is held without forming the
opposite gateway-to-bus lock order.

Agent shows each local or provider review in a dialog of its own over the
transcript, starting at the review's first row. The dialog lays out every
review line itself, and exact values show each space as U+00B7 so that no byte
hides at the end of a line. Approval with F6 stays locked until the dialog has
shown the review's last row for the review as it stands: a change to the
request, the gateway revision, or the runtime revision locks it again. F7 can
deny without granting or traversing the request.

Reviewed local operands are sealed when the gateway creates its owned request.
The canonical form is recursively type-tagged IVJSON, so native distinctions
such as `STRING` versus `RESOURCE` remain visible and hash differently even
when their payload text is identical. The one-shot authority grant ABI is
version 2 and binds the canonical byte length and SHA3-256 digest. At the
serialized target-owner boundary, Desk consumes that grant and recomputes the
seal before entering the applet handler; mutation after review is denied and
the consumed grant cannot be replayed. Canonical encoding and seal operations
are guarded, while allocated audit bytes remain caller-owned rather than a
borrowed global buffer.

Review capacity is the existing 65,536-byte canonical-argument contract, not a
second 4 KiB product limit. The gateway and Agent review JSON capacities derive
from that one bound; the UI's 262,144-byte visible scratch is the exact 4x
worst-case escaping allowance. Model context uses a separate 65,536-byte tool
call arena while retaining the independent 32,768-byte tool-result ceiling.
Focused exact-full and one-byte-short checks guard canonical encoding, gateway
review, and both model-context arenas; the Scripted provider separately accepts
an exact 32 KiB result and atomically rejects a value requiring one byte more.
The review renderer fills its exact 262,144-byte worst-case visible arena while
an adjacent digest sentinel proves that expansion stays in bounds.

## Conversation Store

Provider ownership is independent of transcript ownership.
`tui/applets/agent/conversation-store.f` defines the Agent-local `ACSTORE` port, and
`ARUNTIME-CONVERSATION-STORE!` transfers one store to a runtime. Desk and the
directly tested Agent applet compose the native VFS adapter from
`tui/applets/agent/storage/vfs-conversation.f`; providers never open transcript files.

A run writes into the runtime's run conversation, `ARUNTIME-RUN-CONV`: its
messages, its model context, the provider's events and its end all go there.
A chat run's run conversation is the chat conversation, which the store
persists. A run with a conversation of its own saves nothing into the chat
conversation's store while it runs. Chat history, persistence and clearing
always concern the chat conversation. Scheduled runs are such runs; see
[dispatch.md](dispatch.md).

The runtime must be freed before its provider and provider source. A borrowed
VFS must remain alive until after the runtime has released its store. See
[persistence.md](persistence.md) for the format, recovery behavior, and current
single-conversation boundary.
