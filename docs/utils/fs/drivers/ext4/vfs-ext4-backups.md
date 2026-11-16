# ext4 sparse-super backup authority

`akashic/utils/fs/drivers/ext4/vfs-ext4-backups.f` is an internal dependency of the
public [`vfs-ext4.f`](../vfs-ext4.md) facade. Consumers load the facade, not this
source unit directly.

The unit owns validation of sparse-super copies and their backup group
descriptor tables. A backup superblock must authenticate its own checksum and
seed, name the required group, and match the live primary superblock's immutable
profile. Mutable counters, timestamps, state, `LAST_ORPHAN`, `RECOVER`, and
`ORPHAN_PRESENT` may legitimately differ. The journal-backup tuple comparison
separately binds the tuple type and all 68 tuple bytes.

Each backup GDT descriptor is parsed through the same checked descriptor
service as the primary table. Its own CRC and bounds must validate, and its
block-bitmap, inode-bitmap, and inode-table locations must match the primary
descriptor. Mutable counters and bitmap checksums may lag after ordinary
filesystem activity. The complete validator visits exactly the scheduled
sparse groups and preserves the existing checksum, seed, immutable-field, and
descriptor error order.

A validation that passed stands while none of its inputs changes. The unit
keeps the context, the volume, a copy of the primary superblock it compared
with, the CRC32C of every group's three primary locations, and the count of
writes that met a backup. `_EXT4-BK-NOTE ( lba count -- )`, which the
facade's write watch calls for every write, counts a write to another volume
and one whose blocks meet a sparse group's backup superblock, its descriptor
blocks or their reserved successors. The facade's group validation, which
precedes every backup validation, chains each group's locations through
`_EXT4-GL-BEGIN`, `_EXT4-GL-ADD ( ctx -- ior )` and `_EXT4-GL-RECORD
( ctx -- )`, recording the chain with its context and map epoch. A later
validation of the same context stands when that count has not moved, the
chain of the current epoch equals the kept one, and the primary superblock's
fixed fields equal the copy's; anything else validates every copy, in the
same order as before. A mount drops the kept validation through
`_EXT4-BKM-DROP`.

The module depends directly on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) for authenticated superblock
geometry, checked I/O, checksum helpers, and typed errors, and on
[`vfs-ext4-descriptor.f`](vfs-ext4-descriptor.md) for descriptor parsing. It
exports stack services used by later recovery and transaction policy:
journal-tuple equality, immutable-super equality, complete backup
validation, the backup write note, the location chain and the drop. Its
scratch cells and the kept validation are private; the facade reaches them
only through those services, and the unit calls nothing in the facade.
