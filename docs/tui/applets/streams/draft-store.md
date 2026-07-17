# Streams draft store

Status: frozen legacy-to-migrate compatibility surface. This document records
the landed bytes and failure behavior so they remain recoverable; it is not a
design for new Streams documents, saved sets, derived outputs, or Library
storage. Gate 0 retains an exact valid revision-7 fixture in
[`local_testing/fixtures/desk-gate0/`](../../../../local_testing/fixtures/desk-gate0/).
Gate 1 changes no path, record, API, capability, or mutation behavior.

`tui/applets/streams/draft-store.f` is a Streams-owned persistence primitive
for one unpublished local draft. It stores exactly two application values: the
UTF-8 draft bytes and a positive local revision. It does not store credentials,
feeds, transport state, capability authority, or Practice state. The module is
qualified independently and is the persistence boundary used by normal
`streams.f` app initialization and draft mutation.

The store remains Streams-owned throughout the compatibility interval.
Library must never open `/streams-draft.bin`, import this codec, or silently
proxy its revision-sensitive capabilities. A later Streams-owned migration
adapter may export one exact validated revision through typed Library
operations only after the Library owner and migration journal are separately
qualified. The original bytes remain recovery evidence until explicit
retirement approval.

The store is applet-owned rather than a new Desk or Practices service. Desk
continues to own lifecycle and cross-applet dispatch; Practices can govern and
record calls at that boundary. Streams decides when its own in-memory draft is
published to or restored from this local store.

## Instance identity and initialization

The primary initializer is:

```forth
STREAMS-DRAFT-STORE-INIT-AT
  ( target-a target-u vfs store -- status )
```

The target must be an absolute path accepted by the bounded VREPL path rules.
`INIT-AT` remains part of the qualified legacy API. Its stable-path rules
describe compatibility behavior only; they do not authorize new document
owners or a multi-account draft product. A runtime pointer, allocation address,
window handle, or other ephemeral instance ID is never durable identity.

`STREAMS-DRAFT-STORE-INIT ( vfs store -- status )` selects
`/streams-draft.bin` for the current singleton Streams lifecycle.
`STREAMS-DRAFT-STORE-PATH$` reports the configured target. No new caller
should adopt either initializer as a general text-storage contract.

`STREAMS-INIT-CB` treats `ABSENT` as writable-ready and restores an `OK` record
without touching the component owner revision. Corrupt, unsupported, I/O, busy,
or recovery-uncertain states block applet draft mutation rather than replacing
the target. The shared UI and capability mutation path saves the next revision
before committing memory. Direct component instances whose lifecycle has not
run remain explicitly volatile for isolated contracts.

## Record and recovery contract

Version 1 is a fixed 64-byte common envelope followed by at most 3000 exact
UTF-8 bytes. The envelope contains the `AKSDR001` magic, format number, header
size, positive revision, payload length, payload CRC, header CRC, and zero
flags. Empty drafts are present records with a positive revision and a
zero-length payload; they are distinct from an absent target. Unknown formats
with an intact common envelope are reported as unsupported, while torn,
malformed, over-bound, invalid-UTF-8, and integrity-failing records are
reported as corrupt.

Header and payload CRCs detect accidental corruption; they are not an
authentication mechanism. VREPL stages and verifies every byte, records
rollback intent, and uses sync barriers around rotation and cleanup. `LOAD`
first recovers an interrupted replacement. This is recovery over the VFS
contract, not a promise of sector-atomic behavior below the filesystem layer.

```forth
STREAMS-DRAFT-STORE-SAVE
  ( text-a text-u revision store -- status )

STREAMS-DRAFT-STORE-LOAD
  ( destination capacity store -- text-u revision status )

STREAMS-DRAFT-STORE-RECOVER
  ( store -- status )
```

`SAVE` accepts only bounded valid UTF-8 and a positive revision. It preserves
the exact bytes; it does not normalize text or impose revision monotonicity,
which remain responsibilities of the Streams owner. A contained staging
failure preserves the last-good target and cleans the stage, backup, and
marker companions.

`LOAD` is transactional with respect to caller memory. Only a fully read,
bounded, integrity-checked, valid-UTF-8 record is copied into the destination.
Absent, corrupt, unsupported, capacity, recovery, and I/O outcomes return zero
length and revision and leave the destination unchanged. File descriptors and
the caller's previous VFS context are restored on ordinary and exception
paths. `ABSENT` means path resolution proved that no target exists; an existing
target that cannot acquire a file descriptor is `IO`, not absence.

The shared record scratch is wiped across its full capacity before every
public `SAVE` or `LOAD` returns or rethrows. VREPL likewise wipes its complete
read-back verification buffer around public replacement and recovery calls.
Draft text is not a credential, but it is still private user content and must
not linger in shared scratch or an incidental machine snapshot.

## Status values

| Status | Meaning |
| --- | --- |
| `SDSTORE-S-OK` | Save, load, or recover completed safely |
| `SDSTORE-S-ABSENT` | No target record exists |
| `SDSTORE-S-CORRUPT` | The stored record is malformed, torn, over-bound, invalid UTF-8, or fails integrity checks |
| `SDSTORE-S-UNSUPPORTED` | An intact common envelope names an unknown format |
| `SDSTORE-S-INVALID` | Arguments, descriptor, path, or replacement configuration are invalid |
| `SDSTORE-S-CAPACITY` | Input or destination capacity is insufficient |
| `SDSTORE-S-IO` | A VFS operation failed or threw |
| `SDSTORE-S-RECOVERY` | Recovery cannot choose a safe state automatically |
| `SDSTORE-S-BUSY` | The serialized replacement owner is busy |

Run the store and applet-lifecycle qualifications with:

```sh
python local_testing/akashic_tui.py smoke --profile streams-draft-contracts
python local_testing/akashic_tui.py smoke --profile streams-persistence-contracts
```

The focused profiles cover the record, replacement, cleanup, cold recovery,
normal app initialization, and fail-closed mutation contract described above.
The assertions in the profile implementation are the authoritative detailed
inventory.
