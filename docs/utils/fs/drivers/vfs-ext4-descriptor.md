# ext4 group-descriptor admission

`akashic/utils/fs/drivers/vfs-ext4-descriptor.f` is an internal dependency of
the public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade, not
this source unit directly.

The unit locates a 64-byte descriptor in either the primary or a supplied
backup descriptor table, reads it through the checked admission I/O layer,
verifies its seeded CRC, rejects high block addresses and invalid metadata
pointers, bounds the inode-table span, and validates initialized flags and
counter widths. It also owns the shared descriptor-CRC predicate and the
checked descriptor restamper used by allocation, deletion, recovery, and
transaction builders. It depends only on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) and has no callback into later
allocation, recovery, or mutation policy.

On a successful return, callers consume four parser-result cells:
`_EXT4-GD-BLOCK`, `_EXT4-GD-OFF`, `_EXT4-GD-FLAGS`, and `_EXT4-GD-SPAN`.
They respectively identify the descriptor home, its byte offset, authenticated
initialization flags, and the bounded inode-table span. After any nonzero
return their contents are unspecified and are not authority evidence. The
other five loader cells and all five checksum-service cells are private. These
four result cells are temporary operation-order coupling to be replaced by
explicit operation-lifetime state; adding getters would not change that
lifetime contract.

The CRC predicate temporarily clears the stored checksum but restores it on
success, mismatch, and either checked-CRC error. A caller chooses how a valid
mismatch is typed; descriptor loading retains `EXT4-D-DESC-CHECKSUM`, while
recovery candidate admission retains its boolean negative result. Raw CRC
errors propagate unchanged. The restamper validates its pointer and group
before mutation, then clears the checksum before hashing; if hashing fails,
the caller-owned target intentionally retains a zero checksum and the caller
must abort its operation. On success it writes the low 16 bits of the seeded
CRC.

The parser now delegates its checksum phase to that shared predicate, and the
group-0 recovery candidate uses the same service after preserving its existing
pointer-field checks. This removes duplicate CRC algebra and checksum-only
scratch without changing descriptor error precedence. The cold-source harness
and packaging closure resolve admission, descriptor loading and checksum
services, exact bitmap admission, inode-record formatting, external-xattr
block authentication, sparse-super backup authority, the independent
directory-hash service, the linear directory-entry codec, the independent
JBD2 checksum codec, and then the facade without a backwards dependency.
