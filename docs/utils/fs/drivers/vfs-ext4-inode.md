# ext4 inode-record format service

`akashic/utils/fs/drivers/vfs-ext4-inode.f` is an internal dependency of the
public [`vfs-ext4.f`](vfs-ext4.md) facade. Consumers load the facade rather
than this source unit directly.

The unit owns eight stack services for inode-record representation: decoding
and encoding ext4's 48-bit `i_blocks` field, checking a bounded `i_block` tail,
decoding canonical special-device numbers, signed 32-bit timestamp loading,
inode-checksum restamping, combined mtime/ctime encoding, and ctime-only
encoding. It depends only on
[`vfs-ext4-admission.f`](vfs-ext4-admission.md) for the admitted context,
on-disk offsets, checked arithmetic, CRC adapter, and typed errors. It has no
descriptor, bitmap, callback, execution-token, transaction, or VFS-operation
dependency.

`i_blocks` values at the facade boundary are normalized to 512-byte sectors.
The decoder combines the low and high on-disk fields, applies the ext4
`HUGE_FILE` unit conversion, and refuses a result beyond the admitted
filesystem capacity. The encoder checks that same capacity, requires exact
sector-per-block divisibility for `HUGE_FILE`, enforces the 48-bit on-disk
limit, and validates every condition before changing the low or high field.

Special-device decoding accepts ext4's canonical old or new device-number
encoding for character and block inodes, requires every unused `i_block` word
to be zero, and rejects noncanonical high bits as data-map corruption. Other
special inode kinds must have the entire array clear. The result is the
binding-neutral 64-bit VFS major/minor representation; device-open policy
remains in the facade.

Timestamp encoding accepts nanoseconds in `[0, 1000000000)` and the ext4
signed-low-word/two-epoch-bit seconds range. A 128-byte record can encode only
zero nanoseconds and epoch zero. A writable 256-byte record must authenticate
aligned `extra_isize` geometry that reaches the extra timestamp fields. All
validation precedes the first timestamp store. The ctime-only service saves
mtime, delegates to the combined encoder, and restores mtime after success.

The checksum restamper validates its pointers, inode number, record size, and
writable extra-field geometry before zeroing either checksum field. It hashes
the filesystem seed, inode number, generation, and complete admitted record.
A checked-CRC error after zeroing intentionally leaves a zero checksum in the
caller-owned target; callers already abort the surrounding operation. Success
writes the low checksum and, when admitted, its high word.

All 34 IB/SD/RI/ITM/ICT/EIB scratch cells are private, and the unit adds no
mutable result or evidence surface. Media lookup, allocation admission, inode
checksum verification, and the five ambient IR identity/locator results
deliberately remain in the facade until the operation-lifetime context stage.
In particular, readable old-format 256-byte records may retain `extra_isize`
zero, while the write services intentionally require the stricter modern
geometry; this extraction does not merge those policies.
