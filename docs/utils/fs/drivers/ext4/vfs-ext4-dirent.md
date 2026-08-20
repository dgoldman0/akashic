# ext4 linear directory-entry codec

`akashic/utils/fs/drivers/ext4/vfs-ext4-dirent.f` is an internal dependency of the
public [`vfs-ext4.f`](../vfs-ext4.md) facade. Consumers load the facade, not this
source unit directly.

The unit owns three stack services for linear directory-entry blocks:
`_EXT4-DIRENT>TYPE`, `_EXT4-VALIDATE-DIR-BLOCK`, and
`_EXT4-RESTAMP-DIR-BLOCK`. The type decoder preserves ext4's zero file-type
spelling as supported but unknown, maps values 1 through 7 to the corresponding
VFS file, directory, special, or symlink class, and returns an unsupported flag
for every other value.

The validator authenticates the directory block already staged in the supplied
context. It first validates the format-defined 12-byte tail, then computes the
seeded CRC over the directory inode and generation followed by the first
`block-size - 12` bytes. Only after that checksum succeeds does it validate the
complete record chain: every record is aligned, at least 12 bytes long, bounded
by the checksum tail, and exactly tiles the payload; every live entry names a
bounded inode, has a nonempty valid name, and uses a supported type spelling.
Tail, checksum, or record-chain mismatches return detailed
`EXT4-D-DIRECTORY` corruption. Checked CRC-adapter errors propagate unchanged,
so they retain precedence over any latent record-chain error.

Directory traversal remains facade policy. `_EXT4-SCAN-DIR-BLOCK` owns `.` and
`..` identity and uniqueness, loads each child inode, reconciles a nonzero
on-disk type with the authenticated inode type, publishes VFS cache entries,
and participates in read-directory rollback. The codec neither calls those
services nor exposes scan state.

The restamper accepts an explicit caller-owned block. It rejects null inputs,
an out-of-range directory inode, or a malformed checksum tail before changing
the target checksum. It then zeros only the checksum field, computes the same
seeded CRC, and writes the new checksum only on success. A checked CRC error is
returned unchanged and deliberately leaves the checksum field zero, preserving
the prior fail-closed after-image state. The restamper does not validate the
record chain or perform a media write; its callers retain construction,
transaction, and durability policy.

The module depends directly on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) for context geometry, checked
CRC, and typed errors, and on
[`vfs-ext4-dirhash.f`](vfs-ext4-dirhash.md) for directory-name byte admission.
All 14 validator and restamper scratch cells are private after removal of the
unused `_EXT4-DV-TAIL` cell. The three service results are stack-only; the
restamper's target block is explicit, and the existing context temporary bytes
remain scratch rather than a result surface. The split therefore adds no
mutable cross-module result surface, callback, or execution-token hook.
