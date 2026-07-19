# Checked VFS replacement

`vfs-replace.f` provides a bounded, crash-recoverable way to replace an
application file without truncating the live inode first.

```forth
REQUIRE utils/fs/vfs-replace.f
```

The module stages and verifies the candidate, records a durable rollback
intent, rotates the old target to a backup, publishes the candidate, and only
then removes the intent and backup. It is intended for owner-side persistence
such as Desk applet text resources.

## Filesystem contract

Each descriptor owns four reserved absolute paths in one directory:

| Path | Purpose |
|---|---|
| target | Application-visible file |
| stage | Candidate written and read back before mutation of the target |
| backup | Old target during publication |
| marker | Fixed 64-byte, checksummed rollback intent |

Paths are copied into the descriptor, cannot contain empty, `.` or `..`
components, and must be pairwise distinct. A path is at most 255 bytes and
each component is at most 23 bytes. The component bound deliberately matches
MP64FS, whose directory entry can persist at most 23 name bytes.

The four paths are private to one replacement descriptor. Applications must
not open them as ordinary resources or share them between targets.
Any existing target or companion must be a regular VFS file; a directory or
special-inode collision fails closed without mutation.

Resolution follows intermediate symbolic links under the ordinary VFS path
contract, but it never follows the terminal target, stage, backup, or marker
name.  Before a missing terminal name can be treated as absent, the shared
lexical parent must resolve successfully to a directory.  A terminal symbolic
link, a non-directory parent, or an unresolved parent therefore reports
recovery state without reading, renaming, or deleting the redirected object.

The marker checksum is corruption detection, not a MAC. A sandbox must deny
untrusted applets direct mutation of all companion paths; otherwise an applet
that can rewrite transaction metadata can defeat the recovery protocol. The
resource owner is the only semantic writer to the target and its companions.

`VREPL-DERIVE-PATHS!` reserves the `.s-`, `.b-`, and `.m-` filename prefixes
and derives fixed 23-byte companion names in the target directory from
SHA3-256 of the full target path. This avoids overflowing MP64FS when the
target already has a 23-byte basename. Derivation is stable, not a claim of
collision-proof identity: owners must register one descriptor per canonical
target and must not permit two live descriptors to claim the same companions.
A target using a reserved prefix is rejected so it cannot masquerade as an
artifact.

## Protocol and commit point

`VREPL-REPLACE` performs these ordered steps:

1. Recover any prior transaction.
2. Run the optional owner-supplied precondition.
3. Create the stage file and continue writes until every requested byte has
   been accepted. A zero, negative, or overlong write fails.
4. Reopen the stage and compare its exact length and every byte with the
   caller's source buffer.
5. `VFS-SYNC` the stage.
6. Create, read back, and `VFS-SYNC` the marker. It records whether the target
   existed, the new length and CRC-32, the first 128 bits of SHA3-256 over the
   target path, and a CRC-32 of the marker record.
7. If a target existed, rename it to the backup name and `VFS-SYNC`.
8. Rename the stage to the target name and `VFS-SYNC`.
9. Remove the marker and `VFS-SYNC`. This successful sync is the commit point.
10. Remove the backup and `VFS-SYNC` as post-commit cleanup.

Before the commit point, a durable marker means recovery rolls back. After
the commit point, no marker means the visible target wins and any remaining
backup is cleanup state.

This ordering is not a claim that the underlying filesystem is power-loss
atomic. `VFS-SYNC` dispatches the selected binding's `SYNCFS` operation. A
disk-backed binding owns the durability semantics of `SYNCFS`, per-file
`FSYNC`, and lifecycle `UNMOUNT`; each successful durability path must finish
at a successful `VOL-FLUSH`. MP64FS writes its cached bitmap and directory
regions separately, so a torn sector or corrupt filesystem metadata can still
require lower-level repair. A failed write or flush keeps the binding dirty
and prevents the protocol from advancing its commit point.

`VFS-RAM-BINDING` deliberately implements `SYNCFS`, `FSYNC`, and `UNMOUNT` as
a no-op durability boundary. RAM-backed fixtures therefore verify ordering,
error propagation, and recovery decisions, not persistence across power loss.
Above the binding-owned lower boundary, the primitive guarantees checked
writes and a deterministic recovery policy for every state it publishes.

## Recovery states

`VREPL-RECOVER` is safe to run at activation before opening the target.

| Durable state | Recovery decision |
|---|---|
| target + stage, no marker | Keep target; delete stale stage |
| target + stage + valid marker | Marker says old target is still live; delete stage and marker |
| backup + stage + valid marker | Restore backup to target; delete stage and marker |
| target + backup + valid marker | Publication was not committed; delete candidate target and restore backup |
| target + backup, no marker | Publication committed; keep target and delete backup |
| missing target + backup, no marker | Restore the known backup |
| marker says original was absent | Delete candidate target/stage and restore absence |
| corrupt or short marker | Fail closed; retain target, stage, and backup for inspection |
| valid marker claiming an old target, but no provable target or backup | Fail closed as recovery-required |

Recovery never deletes a known backup in an ambiguous marked state.

## API

Allocate `VREPL-SIZE` bytes for each descriptor.

```forth
CREATE document-save VREPL-SIZE ALLOT

my-vfs document-save VREPL-INIT THROW

S" /notes.txt" document-save VREPL-DERIVE-PATHS! THROW

text-address text-length document-save VREPL-REPLACE
```

### `VREPL-INIT`

```forth
VREPL-INIT  ( vfs replacement -- status )
```

Initialize a caller-owned descriptor for one VFS.

### `VREPL-DERIVE-PATHS!`

```forth
VREPL-DERIVE-PATHS!  ( target-a target-u replacement -- status )
```

Validate and copy an absolute target path, then deterministically derive its
stage, backup, and marker in the same directory:

```text
.s-<20 lowercase base32 characters>
.b-<20 lowercase base32 characters>
.m-<20 lowercase base32 characters>
```

Each companion component is exactly the MP64FS limit of 23 bytes and encodes
the first 100 SHA3-256 bits. Derivation fails if the parent plus 23 bytes would
exceed the 255-byte VFS path bound. Re-instantiating a descriptor with the
same target produces the same paths, which allows activation-time recovery
without persisting descriptor memory.

The truncated digest provides a 100-bit chosen-target second-preimage space,
not absolute uniqueness. If a valid marker names a different target, recovery
fails closed as marker corruption; ambiguous artifacts and known backups are
retained. Owner-side canonical-target registration is still required to stop
aliases or duplicate live descriptors before mutation. The CRC-32 fields only
detect accidental data/record corruption and are not namespace identity.

### `VREPL-PATHS!`

```forth
VREPL-PATHS!
  ( target-a target-u stage-a stage-u backup-a backup-u
    marker-a marker-u replacement -- status )
```

Validate and copy the four reserved paths. Configuration is rejected while
an operation is active. This manual form remains available for bindings or
owners with their own artifact namespace; all four paths must still be
pairwise distinct and share one parent.

### `VREPL-PRECONDITION!`

```forth
VREPL-PRECONDITION!  ( xt data replacement -- status )
```

Set or clear the optional callback. `xt` has stack effect:

```forth
( target-inode|0 data -- status )
```

Zero accepts; nonzero or `THROW` becomes `VREPL-S-CONFLICT`. The callback is
borrowed, owner-side, and must not mutate the inode. Passing `xt = 0` disables
the check.

VFS does not expose a portable per-file revision. Resource owners that have
an authoritative revision compare it here. This hook is a precondition, not
a substitute for routing every semantic writer through the same owner.
`VFS-TRANSACTION` excludes unrelated callers of guarded public VFS words, but
an unguarded build or code bypassing the public API has no such boundary.

### `VREPL-RECOVER`

```forth
VREPL-RECOVER  ( replacement -- status )
```

Resolve a prior transaction according to the table above. A successful
rollback returns `VREPL-S-ROLLED-BACK`; a clean or post-commit cleanup state
returns `VREPL-S-OK`.

### `VREPL-REPLACE`

```forth
VREPL-REPLACE  ( data length replacement -- status )
```

Replace the target with exactly `length` bytes. The source buffer must remain
valid until the call returns. Zero-length files are supported. The bounded
read-back verification buffer contains caller bytes while the operation is in
flight; public `VREPL-REPLACE` and `VREPL-RECOVER` wipe its full capacity on
ordinary, status-failure, and exception paths before returning or rethrowing.

## Status values

| Constant | Value | Meaning |
|---|---:|---|
| `VREPL-S-OK` | 0 | Clean success |
| `VREPL-S-ROLLED-BACK` | 1 | Recovery restored the pre-transaction state |
| `VREPL-S-COMMITTED-CLEANUP` | 2 | New target committed; backup cleanup remains |
| `VREPL-S-INVALID` | 3 | Invalid descriptor, paths, or arguments |
| `VREPL-S-IO` | 4 | I/O failed while the old state remained recoverable |
| `VREPL-S-CONFLICT` | 5 | Owner precondition rejected the target |
| `VREPL-S-BUSY` | 6 | Recursive use of the same descriptor |
| `VREPL-S-RECOVERY` | 7 | Ambiguous state retained for recovery/inspection |
| `VREPL-S-MARKER-CORRUPT` | 8 | Marker is short, corrupt, or belongs to another target |
| `VREPL-S-UNCERTAIN` | 9 | Sync failed while removing the commit marker |

`VREPL-S-COMMITTED-CLEANUP` is a committed save: the resource owner should
advance its revision and schedule `VREPL-RECOVER` to remove the backup.
`VREPL-S-UNCERTAIN` must not be silently treated as either old or new; reload
the filesystem and recover before accepting another write.

## Concurrency boundary

Public entry points share a cross-core recursive guard, so module scratch
buffers and descriptor configuration cannot race with another replacement
call. An operation also rejects recursive replacement, including a different
descriptor invoked by a precondition, because the implementation has one
bounded scratch/intent workspace.

The entire recovery or replacement sequence runs inside `VFS-TRANSACTION`.
In a `GUARDED` build this excludes unrelated public VFS callers while the
process-global `VFS-CUR` selector is switched, and the caller's prior selector
is restored before the VFS guard is released. Owner serialization remains
defense in depth and the semantic authority boundary: worker cores may prepare
immutable output buffers, but the owner core performs precondition, mutation,
sync, recovery, and revision publication. In an unguarded build,
`VFS-TRANSACTION` is only a plain execution wrapper and owner serialization is
mandatory for safety.
