# ext4 external-xattr block codec

`akashic/utils/fs/drivers/vfs-ext4-xattr.f` is an internal dependency of the
public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade rather
than this source unit directly.

The unit owns the ext4 external-xattr block constants and three stack
services: seeded checksum calculation, authenticated physical-block loading,
and checksum restamping of an already authenticated caller-owned image. It
depends only on [`vfs-ext4-admission.f`](vfs-ext4-admission.md) for checked
physical reads, context geometry and buffers, the filesystem checksum seed,
the checked CRC adapter, and typed errors. It has no callback, execution-token
hook, descriptor, bitmap, inode, transaction, or VFS-operation dependency.

The checksum covers the little-endian 64-bit physical block number followed by
the complete block with `h_checksum` zero. The loader reads into the supplied
context's `C.BLOCK` buffer, checks the external-xattr magic, nonzero reference
count, one-block geometry, and reserved header words, then verifies that
location-bound checksum. A checked-read or checked-CRC error propagates
unchanged, while malformed headers and checksum mismatches remain typed
`EXT4-D-XATTR` corruption.

Checksum verification temporarily clears `h_checksum`. Once that field has
been cleared, the loader restores its stored value before returning from
either checked-CRC error path and also before comparing or reporting a
mismatch. Authenticated bytes are available in the caller-owned `C.BLOCK`
buffer only after a zero return; after any error the buffer is not authority
evidence. The loader therefore returns only an `ior` and exports no buffer
pointer or mutable result cell.

The stamper accepts an already authenticated caller-owned image, clears its
checksum, calculates the same physical-location-bound CRC, and writes the new
checksum only after successful calculation. A checked-CRC error intentionally
leaves `h_checksum` zero in the caller-owned target or after-image, and the
existing callers stop and route that failure through their enclosing
transaction owner.

All six `_EXT4-XC-*` and `_EXT4-XB-*` scratch cells are private to the unit:
the CRC/stamper context, physical-block, and buffer cells, plus the loader
context, physical-block, and stored-checksum cells. The immutable magic and
reference-count-limit constants remain available to facade policy, but the
unit adds no exported mutable global result. Inline and external xattr entry
parsing, namespace and name handling, allocation authority, reference-count
policy, transaction reconstruction, publication, and recovery remain in the
facade.
