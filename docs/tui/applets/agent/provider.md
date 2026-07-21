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

The native OpenAI transport uses a 196,608-byte request-body allowance and a
200,704-byte HTTP wire buffer so its independent 32 KiB prompt, 64 KiB history,
and 32 KiB tool-result ceilings can compose with JSON and header overhead. Its
default maximum assembled response text is 49,152 bytes. That lower output
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
the same contract. There is no parallel global factory path.

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

Desk starts in **Chat only**. The built-in profiles are deliberately exact:

| Profile | Agent-visible authority |
|---|---|
| Chat only | Bounded prior user/assistant turns; no applet capabilities |
| Practice read only | Chat history plus the fixed, bounded observation facet; no mutation |
| Practice assist | The read facet plus fixed navigation, mutation, and persistence operations, each requiring one visible local review |

Destructive and external effects are not present in any built-in profile.
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

Gateway state is held only while preparing or transitioning an owned request.
The resulting request/bus continuation is carried per call, and the state guard
is released before `CBUS-POST` or `CBUS-DISPATCH`. Completion may therefore
enter gateway state while the capability bus is held without forming the
opposite gateway-to-bus lock order.

Agent anchors each new local or provider review at its first row. Approval with
F6 remains locked until the viewport reaches the final review row; F7 can deny
without granting or traversing the request.

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

## Conversation Store

Provider ownership is independent of transcript ownership.
`tui/applets/agent/conversation-store.f` defines the Agent-local `ACSTORE` port, and
`ARUNTIME-CONVERSATION-STORE!` transfers one store to a runtime. Desk and the
directly tested Agent applet compose the native VFS adapter from
`tui/applets/agent/storage/vfs-conversation.f`; providers never open transcript files.

The runtime must be freed before its provider and provider source. A borrowed
VFS must remain alive until after the runtime has released its store. See
[persistence.md](persistence.md) for the format, recovery behavior, and current
single-conversation boundary.
