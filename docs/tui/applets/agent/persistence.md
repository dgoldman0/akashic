# Agent Conversation Persistence

Akashic persists the Agent applet's local, provider-neutral transcript through
an applet-owned storage port. The renderer-free implementation is native Forth
and runs on the KDOS filesystem without a host service, Python runtime, or
OpenAI dependency. Direct testability does not make it independent of the
Desk/TUI product ecosystem.

## Modules

```text
akashic/tui/applets/agent/conversation-store.f
akashic/tui/applets/agent/storage/thread-codec.f
akashic/tui/applets/agent/storage/vfs-conversation.f
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

Format version 1 is little-endian and bounded to 262,144 bytes. An 80-byte
header contains:

- Magic `AKTHR001` and format version.
- Monotonic snapshot generation.
- Exact payload length, message count, and model-context item count.
- Conversation ID and revision.
- Model-context revision.
- CRC-32 of the complete payload.

Each message has a fixed 48-byte record followed by UTF-8 text padded to an
eight-byte boundary. Records preserve role, state, run ID, timestamp, and
flags. Each model-context item has a fixed 72-byte record followed by its
source, name, call-ID, and data strings, again padded to an eight-byte
boundary. Context records preserve their kind, role, run ID, flags, and
status, so provider messages, canonical tool calls, tool results, and opaque
provider state survive a restart without reconstructing them from display
text. Decoding validates the complete header, both counts, lengths, UTF-8,
record boundaries, item semantics, and checksum before allocating a
conversation. The current limits are 64 transcript messages and 128 context
items, subject to the shared snapshot-byte ceiling.

## Transaction And Recovery Model

The VFS adapter alternates between `/agent-thread-a.bin` and
`/agent-thread-b.bin`. It writes and syncs the inactive slot before adopting
its generation. Loading validates both slots and chooses the newest valid
generation; a torn or corrupt newest file falls back to the prior valid file.
Equal-generation slots are accepted only when their complete verified bytes
are identical. Divergent equal-generation snapshots are split-brain evidence
and loading fails closed rather than choosing an arbitrary conversation. Two
absent slots report `ACSTORE-S-NOT-FOUND`, which is the first-use state from
which the runtime creates its initial snapshot. Present but invalid evidence,
including two corrupt candidates, fails closed.

The slot-independent selection and inactive-publication state now comes from
the neutral `utils/generation-pair.f` primitive. Agent storage still owns both
paths, the thread codec, exact byte comparison, VFS transactions, status
mapping, allocation, and recovery policy; the extraction does not turn an
Agent transcript into a standalone product or generic storage schema.
Candidate values retain stable descriptor identity; they never retain the
decoded conversation that is returned to the caller or freed after selection.

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
result after a complete write. Creating an absent inactive path is already an
external effect, so a fault at that boundary is conservatively uncertain even
before a complete snapshot exists. Faults before the durability boundary do
not advance the in-memory generation. Once sync succeeds, the pair adopts the
durable generation even if restoring the prior selector or releasing the store
guard then throws; the result remains uncertain rather than attempting a false
rollback. A pre-sync uncertain slot may nevertheless contain a complete,
valid newer generation, so a later load validates both slots normally and may
adopt it. This is deliberately not reported as a clean failure or silently
rolled back.

Descriptor and selector ownership markers are cleared before close/restore is
called. This prevents an operation that completed and then threw from being
retried as a double-close or double-restore during outer cleanup. A binding
that throws before performing such a void operation can therefore strand the
resource; that is an invariant violation in the binding, not a recoverable
storage result. Every load attempt first revokes prior RAM authority. Only a
successful pair selection republishes it; split-brain, corrupt, absent, read,
decode, cleanup, and post-body guard-release failures therefore leave
generation zero and no active slot instead of restoring history-dependent
authority. Deterministic tests cover after-effect close/sync faults, free-list
integrity, selector restoration, allocation recovery, unchanged RAM
publication before durability, durable adoption before selector restoration,
equal-byte and divergent equal-generation classification, second-slot
read/decode revocation, post-body guard-release faults, returned-conversation
cleanup, stable published candidate identity, and later acceptance of a valid
uncertain generation.

Messages stored as streaming, pending, or awaiting approval cannot honestly be
resumed without provider and tool execution state. Decode therefore marks them
cancelled, adds `AMSG-F-RECOVERED`, clears the active run, removes the
interrupted run's model-context records, and appends one audit message:

```text
Previous agent run was interrupted before completion.
```

Approval decisions are durable system messages flagged as audit records and
as approved or denied. Direct provider reviews identify the provider and
retain their displayed action text. A local capability decision additionally
records the provider, tool and call identity, target ID and generation,
expected revision, effect bits, canonical-operand encoding and byte length,
the domain-separated SHA3-256 operand fingerprint, and the exact canonical
operand. Approval is capped at 4096 canonical operand bytes, so every value
that can be approved is both displayable and inline in the audit record. An
oversized request cannot be approved; its denial record retains the length and
fingerprint plus an explicit operand-omission marker.

The recorded encoding is `typed-ivjson-v1`: every recursive value is rendered
as a type tag plus its payload. This prevents two distinct native operands from
sharing review text or a fingerprint merely because their ordinary JSON form
would be the same. The request carries the creation-time seal into the version
2 one-shot grant, and owner dispatch recomputes it after consuming authority
but before entering the capability handler. A post-review operand change is
therefore denied without leaving reusable approval behind.

For a local approval, the complete audit message must be appended and a clean
snapshot save must succeed before the capability grant is issued. Missing
storage, capacity or allocation failure, invalid canonical operands, and any
failed or uncertain save therefore settle the request as denied without
executing the effect. A failed save also removes the provisional audit message
from memory so a later unrelated save cannot turn a failed approval into a
durable approved record. Approval delivery failures terminate the run rather
than hiding a provider or gateway request that may still be outstanding.

Credentials are deliberately excluded. Provider secrets remain in the
zeroizing credential container and are never serialized with conversation
history.

## Current Boundary

This checkpoint provides one durable active conversation and model-context
ledger, corruption fallback, interrupted-state recovery, exact reviewed-action
audit records, and durable clear. Snapshot capacity remains a hard boundary:
the runtime reports the store failure, the Agent applet labels history as
unavailable, and clearing the conversation is the explicit recovery path; it
does not silently discard older records to make a save fit.
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
