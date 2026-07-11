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
| `APROV-AUTH-SET` | `( secret-a secret-u provider -- status )` | Copy an opaque credential into provider-owned storage |
| `APROV-AUTH-CLEAR` | `( provider -- status )` | Clear and zero the active credential |
| `APROV-AUTH-PRESENT?` | `( provider -- flag )` | Report whether authentication material is present |

Providers that implement these operations set `APROV-F-AUTH`. The API does
not prescribe API-key syntax or name a vendor. A future local provider can
omit authentication or implement the same port without changing Agent UI.

`ARUNTIME-AUTH-SET`, `ARUNTIME-AUTH-CLEAR`, and
`ARUNTIME-AUTH-PRESENT?` coordinate these operations with runtime state.
Credential replacement and clearing are rejected while a run or review is
active.

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
