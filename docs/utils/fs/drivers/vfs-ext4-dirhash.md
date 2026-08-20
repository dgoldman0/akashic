# ext4 directory-name hash policy

`akashic/utils/fs/drivers/vfs-ext4-dirhash.f` is an internal dependency of the
public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade, not this
source unit directly.

The unit owns the ext4 directory-name byte predicate, the seeded half-MD4
engine, and the checked hash-policy entry point used by HTree validation and
mutation. The byte predicate rejects embedded NUL and `/`; it does not impose
a length policy by itself. The checked entry point first requires a nonempty
name of at most 255 bytes, then applies that predicate, authenticates the root
hash version and mounted superblock `s_flags`, and only then hashes the name.
Malformed names return `VFS-E-INVALID`. Unsupported version or flag policy
returns the existing detailed `EXT4-D-WRITE-POLICY` refusal.

The admitted root version remains version 1 half-MD4. The mounted flags choose
the ext4 signed- or unsigned-byte interpretation; an ambiguous or absent
choice is unsupported. The unused version-4 constant was removed during the
split because version 4 is not admitted and no production or test consumer
used that vocabulary. This removal changes no accepted hash or error path.

All 21 half-MD4 engine and policy scratch objects are private to this unit.
The module depends only on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) for the authenticated hash seed,
flags, and typed errors. It has no descriptor dependency, callback,
execution-token hook, or mutable state shared with the facade. Existing pinned
half-MD4 vectors remain the behavioral oracle; the physical extraction leaves
their name-validation, policy, and hash order unchanged.
