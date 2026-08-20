# ext4 JBD2 journal-map service

`akashic/utils/fs/drivers/ext4/vfs-ext4-jbd2-map.f` is an internal dependency of
the public [`vfs-ext4.f`](../vfs-ext4.md) facade. Consumers load the facade, not
this source unit directly.

The unit owns the admitted logical-journal address space. Its eight stack
services allocate or reuse map geometry, read a logical map entry, reserve a
unique physical home while the map is built, query completed-map membership,
perform mapped journal-block reads and writes, and advance through the journal
ring. Snapshot construction, recovery-authority refusal, map publication
policy, JBD2 validation and scanning, transaction assembly, and durability
remain in the facade. Raw endian and checksum work remains in the sibling
[`vfs-ext4-jbd2-codec.f`](vfs-ext4-jbd2-codec.md) unit. Recovery revoke-table
geometry and indexing live in the independent
[`vfs-ext4-jbd2-revoke.f`](vfs-ext4-jbd2-revoke.md) unit.

`_EXT4-ENSURE-JOURNAL-WORKSPACE ( maxlen ctx -- ior )` derives an exact
logical map and a power-of-two open-addressed uniqueness table at no more than
half load. These are caller-arena capacities, not additional format limits.
On retry, an existing allocation is accepted only when its map capacity,
hash-table size, and contiguous layout match exactly. Partial or mismatched
published geometry is journal corruption. A failed allocation publishes none
of the four context fields, and successful publication has no later fallible
step. The service does not clear or authenticate the allocated contents; the
facade snapshot owner clears both views on every build before treating them as
evidence.

`_EXT4-JOURNAL-MAP-UNIQUE?` is intentionally a mutating construction
primitive despite its predicate-shaped result. It inserts a nonzero physical
key into the first empty hash slot and returns true, while a duplicate or full
table returns false. The facade first validates the logical and physical
blocks, protected-authority exclusions, and empty map slot; after a successful
reservation its only remaining action is the infallible map store. The
read-only `_EXT4-JOURNAL-DATA?` probe never changes the table.

The raw map, membership, and ring helpers are preconditioned internal words:
they require already admitted and published journal geometry and return no
`ior`. `_EXT4-JOURNAL-NEXT` advances one position and wraps at `MAXLEN` to
`FIRST`; `_EXT4-JOURNAL-ADVANCE` repeats that operation for the caller's
admitted nonnegative count. The mapped I/O services retain explicit null and
`logical < MAXLEN` checks and propagate the underlying checked block I/O
result. A successful read places raw bytes in caller-owned `C.BLOCK`; content
checksum, type, and sequence authentication remain the caller's responsibility.
A write performs the requested journal media mutation.

The module depends only on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md), whose closure supplies the
admitted context, checked block I/O, typed errors, and VFS arena allocator. All
16 JW/JMH/JR/JWB/JN/JADV scratch cells are private. The unit exports no mutable
global result cell, but it deliberately updates caller-owned arena/map state
and media through its explicit stack operations. It has no callback,
execution-token hook, or dependency on later filesystem policy.
