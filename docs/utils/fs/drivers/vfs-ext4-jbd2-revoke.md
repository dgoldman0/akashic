# ext4 JBD2 recovery revoke index

`akashic/utils/fs/drivers/vfs-ext4-jbd2-revoke.f` is an internal dependency of
the public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade, not
this source unit directly.

The unit owns recovery revoke-table geometry, arena allocation and reuse,
bounded open-addressed insertion and lookup, and the 32-bit modular transaction
ordering needed to retain the latest revoke for each physical home. The facade
continues to own revoke-record parsing and checksums, recovery scan ordering,
`REVOKE-READY` publication, replay counters and authority, mount-tail span
validation and scrubbing, and all media durability policy.

`_EXT4-REVOKE-GEOMETRY?` accepts either completely empty table geometry or a
nonzero table with a power-of-two slot count in the derived cell-addressable
bound. `_EXT4-ENSURE-REVOKE-WORKSPACE` invalidates `REVOKE-READY` before every
validation and allocation path. A zero record count needs no fresh allocation.
An existing table is reused only when its retained capacity is sufficient and
is cleared in full; refusing growth leaves its pointer, slot count, and arena
allocation intact while readiness remains false. A fresh allocation publishes
no table before `ARENA-ALLOT?` succeeds, then installs the table, clears it,
and finally publishes its slot count with no later fallible operation.

The table stores `(physical-block + 1, transaction-id)` pairs, reserving zero
as the empty key. `_EXT4-REVOKE-PUT` checks the physical bound, table geometry,
and table presence before probing. An empty slot receives the key and sequence;
an existing key is updated only when the candidate transaction is later under
the JBD2 32-bit serial rule. Equality and a delta of at least half the sequence
space are not later. A full table is journal corruption. The flag-only
`_EXT4-JOURNAL-REVOKED?` query performs no table mutation and reports a replay
write revoked when its transaction is equal to or older than the latest stored
revoke, including across wraparound.

Context validity and query geometry are trusted private preconditions for the
flag-only helpers. The facade must establish valid geometry and readiness when
it needs typed refusal. The module intentionally mutates caller-owned context,
arena, and table bytes through its explicit stack services, but exports no
mutable global result cell. All ten JRW/JRH scratch cells are private.

The sole direct dependency is
[`vfs-ext4-admission.f`](vfs-ext4-admission.md), whose closure supplies the
admitted context layout, filesystem bounds, typed errors, and VFS arena. The
module has no callback, execution-token hook, journal-map dependency, or
backwards edge into replay or transaction policy.
