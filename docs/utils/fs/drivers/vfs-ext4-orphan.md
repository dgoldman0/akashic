# ext4 orphan-file block checksum codec

`akashic/utils/fs/drivers/vfs-ext4-orphan.f` is an internal dependency of the
public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade rather
than this source unit directly.

The unit owns the orphan-file block tail magic and two stack services: a
non-mutating checksum predicate and a checked checksum restamper. It depends
only on [`vfs-ext4-admission.f`](vfs-ext4-admission.md) for admitted filesystem
geometry, the admitted orphan-inode identity, checksum seed and workspace, the
checked CRC adapter, and typed errors. It performs no media I/O and has no
inode-loader, map, callback, execution-token, transaction, recovery, or VFS
operation dependency.

An orphan-file block ends with an eight-byte tail containing the magic and
stored checksum. The seeded CRC covers a 16-byte prefix containing the orphan
inode, generation, and low/high physical block number followed by the block
bytes before that tail. The current profile requires the physical number and
generation to fit their 32-bit encoded fields and writes a zero physical high
word. Both services require the supplied orphan inode to match the identity in
the admitted context and the physical block to lie within that context.

`_EXT4-ORPHAN-BLOCK-CHECKSUM?` treats a null block or context, identity or
range mismatch, over-width value, bad magic, or checksum mismatch as
`FALSE 0`. Either checked-CRC failure instead returns `FALSE ior`, preserving
the raw error for the caller. The predicate never changes the caller-supplied
block.

`_EXT4-RESTAMP-ORPHAN-BLOCK` returns `VFS-E-INVALID` for a null block or
context. Identity, range, width, and magic failures are typed
`EXT4-D-ORPHAN-FILE` corruption, and checked-CRC errors propagate unchanged.
Every gate and both CRC additions precede its sole target mutation, the final
checksum store. Because the complete tail is excluded from the CRC, the
stamper never needs to clear the existing checksum; the caller-supplied block
therefore remains byte-identical on every failure.

The six `_EXT4-ROB-*` cells and one `_EXT4-OCV-*` cell are private, and the
unit exports no mutable result or evidence cell. The facade retains
`_EXT4-PREPARE-ORPHAN-FILE`, `_EXT4-READ-ORPHAN-BLOCK`, mapping and inode
authentication, and all operation-lifetime `_EXT4-OV-*` state. Its reader maps
a valid predicate mismatch to detailed orphan-file corruption while preserving
raw CRC errors. The caller-owned context `C.BLOCK` contains authenticated
orphan bytes only after that reader returns success; after any error it is not
authority evidence. Orphan planning, transaction staging, recovery, and
durability policy likewise remain in the facade.
