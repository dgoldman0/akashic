# ext4 allocation-bitmap admission

`akashic/utils/fs/drivers/ext4/vfs-ext4-bitmap.f` is an internal dependency of the
public [`vfs-ext4.f`](../vfs-ext4.md) facade. Consumers load the facade rather than
this source unit directly.

The unit owns eight stack services: canonical block- and inode-group counts,
the exact physical interval for a block group, block- and inode-bitmap CRC
calculation, authenticated block- and inode-bitmap loading, and the raw
single-block allocation predicate. It depends directly on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md),
[`vfs-ext4-descriptor.f`](vfs-ext4-descriptor.md), and the generic checked
`bitset.f` layer. It has no callback or execution-token dependency on later
allocation, recovery, transaction, or VFS policy.

Logical and physical bounds remain deliberately distinct. Group counts use
checked arithmetic and shorten the final group to the admitted filesystem
block or inode total. `BITSET-TEST?` receives that exact logical count, so
padding is never allocation evidence. Bitmap CRCs instead cover the ext4
format span `blocks_per_group / 8` or `inodes_per_group / 8`, including the
nominal backing padding required by the on-disk checksum contract.

Each authenticated loader reads a descriptor, rejects the applicable
`BLOCK_UNINIT` or `INODE_UNINIT` flag, reads the named bitmap home, calculates
the shared CRC, and compares it with the complete descriptor checksum. A CRC
adapter error propagates unchanged; a mismatch remains
`EXT4-D-BITMAP-CHECKSUM` corruption. Success returns the physical bitmap home
and leaves its authenticated bytes in the caller-owned context `C.BLOCK`
buffer. After any error that buffer is not evidence.

`_EXT4-BLOCK-ALLOCATED?` intentionally remains a narrower raw predicate. It
validates physical and exact group geometry, but returns `FALSE 0` for
`BLOCK_UNINIT`; facade-owned require wrappers decide when that negative result
is corruption and also enforce mutation-owner alias policy. It therefore does
not delegate to the stricter authenticated block-bitmap loader.

All 22 GBC/GIC/GBR/LBB/LIB/BA scratch cells are private. The two CRC
calculators are stack-direct, so their former four scratch cells are gone.
Mount-wide bitmap validation remains in the facade because it composes CRC
evidence with allocation ownership and group accounting, but its duplicate CRC
tails now delegate to this unit. The unit adds no mutable global result or
evidence cell; loaders consume descriptor results only after a successful
descriptor load and return their bytes through the caller-owned context buffer.
