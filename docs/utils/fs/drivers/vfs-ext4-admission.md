# ext4 admission foundation

`akashic/utils/fs/drivers/vfs-ext4-admission.f` is an internal dependency of
the public [`vfs-ext4.f`](vfs-ext4.md) facade. It is not a second driver or a
separate binding. Load ext4 through the facade:

```forth
REQUIRE utils/fs/drivers/vfs-ext4.f
```

The admission unit owns the shared pinned on-disk constants and context layout,
structured ext4 errors, the checked CRC32C adapter, checked volume reads and
writes, probe helpers, checked unsigned arithmetic, sparse-super geometry, and
primary-super validation. It depends directly on `vfs.f` and `math/crc.f` and
has no dependency or callback into the facade. The internal
[`vfs-ext4-descriptor.f`](vfs-ext4-descriptor.md) unit consumes that foundation
to authenticate, verify, and checksum group descriptors. The independent
[`vfs-ext4-bitmap.f`](vfs-ext4-bitmap.md) unit combines admitted geometry,
descriptor evidence, checked reads and CRCs, and exact generic bitset queries
for allocation-bitmap admission. The independent
[`vfs-ext4-inode.f`](vfs-ext4-inode.md) unit consumes the admitted inode
layout, arithmetic, and CRC adapter for stack-only record decoding,
special-device representation, and encoding. The independent
[`vfs-ext4-xattr.f`](vfs-ext4-xattr.md) unit uses admitted checked reads,
context geometry, and the CRC adapter to authenticate and restamp external
xattr blocks without moving entry parsing, allocation, reference-count, or
transaction policy out of the facade. The independent
[`vfs-ext4-orphan.f`](vfs-ext4-orphan.md) unit owns the orphan-file block tail
magic and consumes admitted geometry, identity, workspace, and checked CRCs
for stack-only checksum verification and restamping. The independent
[`vfs-ext4-backups.f`](vfs-ext4-backups.md) unit uses the admitted superblock
and descriptor services to authenticate sparse-super copies. The independent
[`vfs-ext4-dirhash.f`](vfs-ext4-dirhash.md) unit consumes the admitted
superblock hash seed and flags for checked directory-name hashing. The
independent [`vfs-ext4-dirent.f`](vfs-ext4-dirent.md) unit consumes the checked
CRC adapter, context geometry, typed errors, and that name-byte predicate for
linear directory-block validation and checksum encoding. The independent
[`vfs-ext4-jbd2-codec.f`](vfs-ext4-jbd2-codec.md) unit consumes the checked CRC
adapter plus admitted context geometry and journal seed for raw JBD2 checksum
validation and encoding. The independent
[`vfs-ext4-jbd2-map.f`](vfs-ext4-jbd2-map.md) unit consumes admitted journal
geometry, checked block I/O, typed errors, and the VFS arena available through
the admission closure for logical mapping, mapped I/O, and ring stepping. The
independent [`vfs-ext4-jbd2-revoke.f`](vfs-ext4-jbd2-revoke.md) unit consumes
admitted filesystem bounds, journal workspace layout, typed errors, and that
arena for recovery revoke allocation and indexing. None of these units calls
back into later filesystem policy.

Most mutable scratch in this unit is private to admission. Four cells remain
an intentional temporary cross-module surface: `_EXT4-IO-VFS` and
`_EXT4-IO-VOL` identify the callback-selected checked I/O session, while
`_EXT4-IO-EXPECTED` and `_EXT4-IO-COMPLETED` preserve write-attempt evidence
consumed by later durability code. They are implementation state, not public
API, and are candidates for the operation-lifetime context stage rather than
for a backwards dependency into admission.

Physical extraction does not change the profile, error precedence, or
cold-source qualification model. Packaging and the real-image harness resolve
admission, descriptor loading, bitmap admission, inode-record formatting,
external-xattr block authentication, orphan-file block checksums, backup
authority, directory hashing, the linear directory-entry codec, the JBD2
checksum codec, the JBD2 map service, the JBD2 recovery revoke index, and the
facade in production order and continue to compile the aggregate closure in
source mode.
