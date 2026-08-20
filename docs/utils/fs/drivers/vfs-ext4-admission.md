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
[`vfs-ext4-descriptor.f`](vfs-ext4-descriptor.md) unit is its next consumer and
authenticates group descriptors before the facade applies allocation policy.

Most mutable scratch in this unit is private to admission. Four cells remain
an intentional temporary cross-module surface: `_EXT4-IO-VFS` and
`_EXT4-IO-VOL` identify the callback-selected checked I/O session, while
`_EXT4-IO-EXPECTED` and `_EXT4-IO-COMPLETED` preserve write-attempt evidence
consumed by later durability code. They are implementation state, not public
API, and are candidates for the operation-lifetime context stage rather than
for a backwards dependency into admission.

Physical extraction does not change the profile, error precedence, source
order, or cold-source qualification model. Packaging and the real-image
harness resolve admission, descriptor loading, and the facade in that order
and continue to compile the aggregate closure in source mode.
