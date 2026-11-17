# Checked VFS replacement

`vfs-replace.f` provides a bounded, crash-recoverable way to replace an
application file without truncating the live inode first.

```forth
REQUIRE utils/fs/vfs-replace.f
```

The module writes the candidate beside the target and reads it back. It then
publishes the candidate in the way the filesystem under the target allows:
by one rename over the target where a rename survives a power cut whole, and
otherwise through a durable rollback intent, a backup of the old target and
a sync after each step. It is intended for owner-side persistence such as
Desk applet text resources.

## Filesystem contract

Each descriptor owns four reserved absolute paths in one directory:

| Path | Purpose |
|---|---|
| target | Application-visible file |
| stage | Candidate written and read back before mutation of the target |
| backup | Old target during publication through the marker |
| marker | Fixed 64-byte, checksummed rollback intent |

Publication by one rename creates neither the backup nor the marker. Their
names stay reserved, since recovery inspects all four on every filesystem.

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

`VREPL-REPLACE` begins the same way on every filesystem:

1. Recover any prior transaction.
2. Run the optional owner-supplied precondition.
3. Create the stage file and continue writes until every requested byte has
   been accepted. A zero, negative, or overlong write fails.
4. Reopen the stage and compare its exact length and every byte with the
   caller's source buffer.

It then asks the filesystem under the target what a power cut leaves there,
by reading the binding's capabilities, and publishes the stage in one of two
ways. Both stay, because a writable place may sit on either kind of
filesystem, and applets call the same word on both.

### Publication by one rename

A binding that sets `VFS-CAP-DURABLE-MUTATIONS` and `VFS-CAP-RENAME-REPLACE`
keeps every completed mutation across a power cut and renames over an
existing file as one such mutation; the [VFS contract](vfs.md#operation-table)
states both promises. ext4's staged-write binding is the binding that sets
them.

5. Rename the stage over the target with `VFS-RENAME-AT`. The rename is the
   commit point.

The stage's bytes were on the medium when each write returned, so the save
needs no `VFS-SYNC`, and the rename moves the name from the old file to the
new one as one mutation, on ext4 one journal transaction, so it needs no
marker and no backup. A power cut before the rename's commit block reaches
the medium leaves the old target, or no target on a first save, and a stage
that recovery removes. A power cut after it leaves the new target and no
companion. The driver frees the old file's storage before the rename
returns, and the next mount's recovery frees it when the power cut came
first.

A refused rename has changed nothing. The routine removes the stage and
returns `VREPL-S-IO`, or `VREPL-S-RECOVERY` when the stage cannot be removed
either, as on a volume that a fault has turned read-only. This publication
never returns `VREPL-S-COMMITTED-CLEANUP` or `VREPL-S-UNCERTAIN`.

The rename takes a target that another descriptor holds open as its victim,
and that descriptor goes on reading the old bytes. On ext4 the old file then
waits in the orphan file until the descriptor closes, and the volume takes
every other write meanwhile. A second save in that interval writes its stage
and renames it over the first save's file, which nothing holds, so that victim
drains at once beside the record the open file keeps; a sync lands the journal
with the record in place, and the descriptor's close drains it.
`local_testing/test_vfs_replace_ext4.py` holds that behavior.

### Publication through the marker and the backup

Every other binding, MP64FS and the RAM binding among them, publishes through
the steps built for a filesystem without a journal:

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

A binding that sets `VFS-CAP-DURABLE-MUTATIONS` without
`VFS-CAP-RENAME-REPLACE` has no rename that can take the target as its
victim. It publishes through the marker and the backup, and the routine
leaves out the syncs, since each step is on the medium when it returns.

### Cost on ext4

Both publications were measured on the exact emulator on 2026-11-15, on the
64 MiB test fixture volume with a 2 KiB `/doc.txt`, a mount arena of 524,288
bytes and a writer profile of 16 metadata, 16 data and 2 revoke credits. Each
row is the emulator's own count for the one interpreted line that ran
`VREPL-REPLACE`, with every row returning status 0. Seconds are system cycles
divided by 10^8, the processor time of a 100 MHz device; the emulator
completes storage transfers and flushes at once, so a device's storage
latency comes on top. Writes are 1 KiB blocks, and transactions are the JBD2
commit blocks among them.

| Case | Publication | Instructions | Cycles | Seconds | Writes | Flushes | Transactions | Syncs |
|---|---|---|---|---|---|---|---|---|
| Existing 2 KiB, new 2 KiB | one rename | 129.6 M | 165.6 M | 1.66 | 112 | 61 | 5 | 0 |
| | marker and backup | 385.9 M | 494.8 M | 4.95 | 319 | 210 | 12 | 6 |
| Existing 2 KiB, new 64 KiB | one rename | 206.6 M | 263.9 M | 2.64 | 234 | 94 | 8 | 0 |
| | marker and backup | 464.3 M | 594.7 M | 5.95 | 441 | 243 | 15 | 6 |
| Existing 64 KiB, new 64 KiB | one rename | 205.7 M | 262.7 M | 2.63 | 236 | 94 | 8 | 0 |
| | marker and backup | 463.0 M | 593.2 M | 5.93 | 441 | 243 | 15 | 6 |
| File absent, new 2 KiB | one rename | 66.9 M | 85.8 M | 0.86 | 70 | 39 | 3 | 0 |
| | marker and backup | 251.8 M | 323.0 M | 3.23 | 217 | 140 | 8 | 4 |

A save by one rename over an existing file takes five transactions: the
stage's create, its write, the rename, and two that drain the old file from
the orphan file. A first save takes the first three. A 64 KiB stage is
written in four transactions of 16 data blocks, the writer profile's data
credit, where 2 KiB takes one.

Every row began on a volume whose journal a sync had just landed clean, so
each includes the journal's activation, which the note below measured at
2.1 M cycles, 6 writes and 6 flushes for a single write. Publication by one
rename leaves the journal active, and the next save starts there: a second
2 KiB save over the 2 KiB file, with no sync in between, cost 157.2 M
cycles, 108 writes and 55 flushes. A save that is the first write of its
mount also carries the driver's ownership proof, which the note measured at
35.4 M cycles.

The marker rows are the measurement recorded in
[`user-volume-20261115.md`](../../../local_testing/evidence/user-volume-20261115.md),
taken at Akashic `86d817ea`, when every binding published through the
marker. The rename rows were taken by that note's method at Akashic
`dd275371` with MegaPad `5dd6fe1e`. A run of the same commit with the
capability cleared on the mounted binding took the marker protocol and
reproduced the note's four rows in every column, so the protocol costs on
ext4 what it did before the choice existed.

The volume's size was not varied. The note measured a single overwrite and
a sync at 4.6 times their 64 MiB cost on a 256 MiB volume, through
computation that grows with the volume, so both publications are expected
to cost more there; neither was run on a larger volume.

## Recovery states

`VREPL-RECOVER` is safe to run at activation before opening the target. One
recovery serves both publications, because it decides by the files it finds
and a volume shows which publication left them: a marker or a backup exists
only where the marker protocol ran.

| Durable state | Recovery decision |
|---|---|
| target + stage, no marker | Keep target; delete stale stage |
| stage alone: no target, backup or marker | Delete the stage; the target stays absent |
| target + stage + valid marker | Marker says old target is still live; delete stage and marker |
| backup + stage + valid marker | Restore backup to target; delete stage and marker |
| target + backup + valid marker | Publication was not committed; delete candidate target and restore backup |
| target + backup, no marker | Publication committed; keep target and delete backup |
| missing target + backup, no marker | Restore the known backup |
| marker says original was absent | Delete candidate target/stage and restore absence |
| corrupt or short marker | Fail closed; retain target, stage, and backup for inspection |
| valid marker claiming an old target, but no provable target or backup | Fail closed as recovery-required |

Recovery never deletes a known backup in an ambiguous marked state.

A power cut during publication by one rename leaves one of three states: the
target as it was, with or without a stage beside it; a stage alone, when the
save was the file's first; or the new target. The first two rows settle the
states that hold a stage, and the others need nothing. On a binding with
`VFS-CAP-DURABLE-MUTATIONS` recovery leaves out its syncs as the save does,
since each removal and rename is on the medium when it returns.

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
the filesystem and recover before accepting another write. Only publication
through the marker returns these two.

## Concurrency boundary

Public entry points share a cross-core recursive guard, so module scratch
buffers and descriptor configuration cannot race with another replacement
call. An operation also rejects recursive replacement, including a different
descriptor invoked by a precondition, because the implementation has one
bounded scratch/intent workspace.

The entire recovery or replacement sequence runs inside `VFS-TRANSACTION`,
and every step names the descriptor's own VFS. In a `GUARDED` build the
transaction excludes unrelated public VFS callers for the whole sequence.
Owner serialization remains
defense in depth and the semantic authority boundary: worker cores may prepare
immutable output buffers, but the owner core performs precondition, mutation,
sync, recovery, and revision publication. In an unguarded build,
`VFS-TRANSACTION` is only a plain execution wrapper and owner serialization is
mandatory for safety.
