# ext4 sparse-super backup authority

`akashic/utils/fs/drivers/vfs-ext4-backups.f` is an internal dependency of the
public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade, not this
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

The module depends directly on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) for authenticated superblock
geometry, checked I/O, checksum helpers, and typed errors, and on
[`vfs-ext4-descriptor.f`](vfs-ext4-descriptor.md) for descriptor parsing. It
exports only three stack services used by later recovery and transaction
policy: journal-tuple equality, immutable-super equality, and complete backup
validation. All 13 parser cells are private, so the split introduces no new
mutable result or evidence seam and no callback into the facade.
