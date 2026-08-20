# ext4 admission foundation

`akashic/utils/fs/drivers/vfs-ext4-admission.f` is an internal dependency of
the public [`vfs-ext4.f`](vfs-ext4.md) facade. It is not a second driver or a
separate binding. Load ext4 through the facade:

```forth
REQUIRE utils/fs/drivers/vfs-ext4.f
```

The admission unit owns the pinned on-disk constants and context layout,
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
layout, arithmetic, and CRC adapter for stack-only record decoding and
encoding. The independent
[`vfs-ext4-backups.f`](vfs-ext4-backups.md) unit uses the admitted superblock
and descriptor services to authenticate sparse-super copies. The independent
[`vfs-ext4-dirhash.f`](vfs-ext4-dirhash.md) unit consumes the admitted
superblock hash seed and flags for checked directory-name hashing. The
independent [`vfs-ext4-dirent.f`](vfs-ext4-dirent.md) unit consumes the checked
CRC adapter, context geometry, typed errors, and that name-byte predicate for
linear directory-block validation and checksum encoding. The independent
[`vfs-ext4-jbd2-codec.f`](vfs-ext4-jbd2-codec.md) unit consumes the checked CRC
adapter plus admitted context geometry and journal seed for raw JBD2 checksum
validation and encoding. None of these units calls back into later filesystem
policy.

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
backup authority, directory hashing, the linear directory-entry codec, the
JBD2 checksum codec, and the facade in production order and continue to
compile the aggregate closure in source mode.
