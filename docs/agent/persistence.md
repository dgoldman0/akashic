# Agent Conversation Persistence

Akashic persists the local, provider-neutral transcript through a storage port.
The implementation is native Forth and runs on the physical MegaPad filesystem;
it has no host service, Python runtime dependency, Desk dependency, or OpenAI
dependency.

## Modules

```text
akashic/agent/conversation-store.f
akashic/agent/storage/thread-codec.f
akashic/agent/storage/vfs-conversation.f
```

`conversation-store.f` defines `ACSTORE`, the generic load/save/free port.
`thread-codec.f` owns the bounded binary format. `vfs-conversation.f` adapts
that format to any Akashic VFS. The VFS adapter belongs under agent storage
because its paths, generation policy, and recovery semantics are specific to
agent transcripts; the VFS itself remains a reusable filesystem facility.

## Runtime Ownership

```forth
vfs AVFSSTORE-NEW             ( store status )
store runtime ARUNTIME-CONVERSATION-STORE!  ( status )
```

`ARUNTIME-CONVERSATION-STORE!` transfers ownership of the store to the
runtime. The store borrows its VFS, so the VFS must outlive the runtime. On
binding, the runtime loads the newest valid snapshot or creates the first
snapshot when neither slot exists. A valid loaded transcript replaces the
new runtime's empty conversation and advances the next run ID beyond every
stored message.

The runtime persists immediately when a prompt starts, after approval
decisions and explicit clearing, and during shutdown. Event-driven changes are
persisted from `ARUNTIME-PUMP`; active streaming is throttled to one snapshot
per 500 milliseconds. `ARUNTIME.STORE-STATUS` exposes the latest storage
result. If existing files are invalid, the runtime keeps its in-memory
conversation but refuses to overwrite the damaged evidence automatically.

## Snapshot Format

Format version 1 is little-endian and bounded to 262,144 bytes. A 64-byte
header contains:

- Magic `AKTHR001` and format version.
- Monotonic snapshot generation.
- Exact payload length and message count.
- Conversation ID and revision.
- CRC-32 of the complete payload.

Each message has a fixed 48-byte record followed by UTF-8 text padded to an
eight-byte boundary. Records preserve role, state, run ID, timestamp, and
flags. Decoding validates the complete header, count, lengths, UTF-8, record
boundaries, and checksum before allocating a conversation. The current
conversation limit is 64 messages.

## Transaction And Recovery Model

The VFS adapter alternates between `/agent-thread-a.bin` and
`/agent-thread-b.bin`. It writes and syncs the inactive slot before adopting
its generation. Loading validates both slots and chooses the newest valid
generation; a torn or corrupt newest file falls back to the prior valid file.
If neither file is valid, loading fails closed.

Messages stored as streaming, pending, or awaiting approval cannot honestly be
resumed without provider and tool execution state. Decode therefore marks them
cancelled, adds `AMSG-F-RECOVERED`, clears the active run, and appends one audit
message:

```text
Previous agent run was interrupted before completion.
```

Approval decisions are durable system messages flagged as audit records and
as approved or denied. The record names the gateway capability when available;
direct provider reviews retain their displayed action text.

Credentials are deliberately excluded. Provider secrets remain in the
zeroizing credential container and are never serialized with conversation
history.

## Current Boundary

This checkpoint provides one durable active conversation, corruption fallback,
interrupted-state recovery, approval-decision audit records, and durable clear.
It does not yet provide a thread catalog, titles, archive/search, provider
continuation IDs, context attachments, encrypted history, approval principals,
or exactly-once tool-execution journals. Those belong to the larger durable
Desk environment rather than to this storage port.

Deterministic coverage is split intentionally:

- `conversation-store` validates the codec, both generations, corruption
  fallback, fail-closed loading, recovery normalization, ownership, and stack
  balance.
- `agent-persistence` reconstructs multiple runtimes over one native VFS and
  verifies completed approval audit, interrupted approval recovery, next-run
  continuity, and durable clearing.
- `agent-ui` verifies the ordinary conversation and review experience with the
  VFS store attached. Full-image in-place warm reset remains a separate MegaPad
  development-session issue, not a storage acceptance mechanism.
