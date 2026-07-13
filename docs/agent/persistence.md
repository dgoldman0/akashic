# Agent Conversation Persistence

Akashic persists the local, provider-neutral transcript through a storage port.
The implementation is native Forth and runs on the KDOS filesystem;
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

Slot reads and writes are exact: a zero-progress or short transfer is an I/O
failure, never a shorter valid snapshot. Each slot operation holds one VFS
transaction across active-VFS selection, open/create, transfer, close, and
sync. A dedicated recursive store guard covers allocation, codec scratch,
generation selection, publication, construction, and destruction as well, so
owner-core callers cannot interleave through the module-global working state.
The adapter remains core-affine because allocation and the active-VFS selector
are not worker-safe. The runtime must also linearize store lifetime: no caller
may race `AVFSSTORE-FREE` or use the store after ownership is released. Within
that lifetime contract, the guard provides scratch-state safety and coherent
generation publication; it does not provide conflicting-edit resolution or
turn a borrowed store pointer into a concurrent ownership mechanism.

The store callback ABI remains status-based even when a VFS binding or codec
unexpectedly `THROW`s. The adapter catches the fault only after independently
attempting descriptor close, active-VFS restoration, candidate-conversation
release, and buffer release. The original fault takes precedence over a
cleanup fault internally; the public load/save callback then reports
`ACSTORE-S-IO` rather than exposing an exception or misclassifying an
invariant failure as corrupt snapshot data. Ordinary returned codec statuses
retain their existing `INVALID`, `CAPACITY`, and `NOMEM` meanings.

Save has one additional result, `ACSTORE-S-UNCERTAIN`. It is returned when an
unexpected fault occurs after writing may have begun, or when close/sync or
the final selector restore cannot prove the effect, including a nonzero sync
result after a complete write. For faults before the save body adopts the new
generation, the in-memory generation and active slot do not advance. A fault
while releasing the store guard after a successful body is later still: RAM
adoption has already occurred, so it is retained and the result remains
uncertain rather than attempting a false rollback. The inactive slot may
nevertheless contain a complete, valid newer generation, so a later load
validates both slots normally and may adopt it. This is deliberately not
reported as a clean failure or silently rolled back.

Descriptor and selector ownership markers are cleared before close/restore is
called. This prevents an operation that completed and then threw from being
retried as a double-close or double-restore during outer cleanup. A binding
that throws before performing such a void operation can therefore strand the
resource; that is an invariant violation in the binding, not a recoverable
storage result. Deterministic tests cover after-effect close/sync faults,
free-list integrity, selector restoration, allocation recovery, unchanged RAM
publication before adoption, second-slot read/decode rollback, post-body guard
release faults, returned-conversation cleanup, and later acceptance of a valid
uncertain generation.

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
  fallback, fail-closed loading, recovery normalization, thrown dependency
  cleanup, uncertain publication recovery, ownership, and stack balance.
- `agent-persistence` reconstructs multiple runtimes over one native VFS and
  verifies completed approval audit, interrupted approval recovery, next-run
  continuity, and durable clearing.
- `agent-ui` verifies the ordinary conversation and review experience with the
  VFS store attached. Full-image in-place warm reset remains a separate MegaPad
  development-session issue, not a storage acceptance mechanism.
