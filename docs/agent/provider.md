# Agent Provider and Source Contracts

Akashic separates a live provider from the environment that constructs it.
Both contracts are native, provider-neutral, and independent of Desk and TUI.

## Provider

`akashic/agent/provider.f` defines `APROV`, the live behavior used by
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

## Provider Source

`akashic/agent/provider-source.f` defines `APSOURCE`, an owned construction
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
`org.akashic.agent.provider-source`. A standalone Agent owns the same three
objects. Source selection is explicit through `DESK-AGENT-SOURCE!` or
`AGENT-SOURCE!`; loading a provider module has no selection side effect.

`providers/offline.f` and `providers/devtools/scripted.f` supply sources through
the same contract. There is no parallel global factory path.

## Conversation Store

Provider ownership is independent of transcript ownership.
`agent/conversation-store.f` defines the generic `ACSTORE` port, and
`ARUNTIME-CONVERSATION-STORE!` transfers one store to a runtime. Desk and the
standalone Agent compose the native VFS adapter from
`agent/storage/vfs-conversation.f`; providers never open transcript files.

The runtime must be freed before its provider and provider source. A borrowed
VFS must remain alive until after the runtime has released its store. See
`docs/agent/persistence.md` for the format, recovery behavior, and current
single-conversation boundary.
