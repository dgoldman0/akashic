# ext4 JBD2 checksum codec

`akashic/utils/fs/drivers/vfs-ext4-jbd2-codec.f` is an internal dependency of
the public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade, not
this source unit directly.

The unit owns the raw 32-bit big-endian load/store primitives and the shared
checksum-v3 mechanisms for JBD2 descriptor/revoke blocks, superblocks, commit
blocks, and tags. It provides both validation predicates and the checksum
encoders used by journal activation, reset, transaction emission, and witness
cleanup. The standard 1024-byte journal-super checksum is stamped through one
shared encoder, including when the facade clears its private recovery witness
fields.

Tag verification receives every changing input explicitly as
`(buffer stored sequence ctx -- flag ior)`. It does not reach into the
facade's journal-scanner state. The corresponding encoder receives
`(payload tid ctx -- crc ior)`, and the verifier reuses that encoder before
comparing the computed CRC with the stored value. The caller-supplied context
provides the authenticated block size, journal seed, and existing temporary
CRC workspace.

Checksum mismatches and structurally invalid commit records return `FALSE 0`;
the recovery or admission caller retains responsibility for assigning the
appropriate typed refusal. Validation errors from the checked CRC adapter are
propagated unchanged as `FALSE ior`. Block, superblock, and commit validators
restore any checksum field they temporarily zero on both success and CRC
error. The block, superblock, and commit encoders instead deliberately leave
their target field zero and return the raw `ior` if CRC calculation fails,
exactly as before the split; the tag encoder returns `0 ior` because it does
not write a checksum field itself.

The module depends only on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) and has no callback,
execution-token hook, or mutable result surface shared with the facade. All 11
of its endian, validator, and encoder scratch cells are private. Journal
geometry and authority, scan ordering, witness policy, transaction assembly,
media writes, and durability remain in the facade.
