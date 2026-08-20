# ext4 group-descriptor admission

`akashic/utils/fs/drivers/vfs-ext4-descriptor.f` is an internal dependency of
the public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade, not
this source unit directly.

The unit locates a 64-byte descriptor in either the primary or a supplied
backup descriptor table, reads it through the checked admission I/O layer,
verifies its seeded CRC, rejects high block addresses and invalid metadata
pointers, bounds the inode-table span, and validates initialized flags and
counter widths. It depends only on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) and has no callback into later
allocation, recovery, or mutation policy.

On a successful return, callers consume four parser-result cells:
`_EXT4-GD-BLOCK`, `_EXT4-GD-OFF`, `_EXT4-GD-FLAGS`, and `_EXT4-GD-SPAN`.
They respectively identify the descriptor home, its byte offset, authenticated
initialization flags, and the bounded inode-table span. After any nonzero
return their contents are unspecified and are not authority evidence. The
other six parser cells are private. These four cells are temporary operation-
order coupling to be replaced by explicit operation-lifetime state; adding
getters would not change that lifetime contract.

The physical split preserves the descriptor parser and its error precedence
byte for byte. The cold-source harness and packaging closure resolve admission,
descriptor loading, and then the facade in one direction.
