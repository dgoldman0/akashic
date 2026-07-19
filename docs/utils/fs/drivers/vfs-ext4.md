# akashic-vfs-ext4 — checksummed read-only ext4 binding

This VFS ABI 1 binding reads clean filesystems in the pinned
`akashic-ext4-rw-v1` profile from one explicit KDOS volume. It never uses the
ambient filesystem volume and has no write fallback: all media access goes
through checked `VOL-READ` calls relative to the supplied `VOL-RAW` or
`VOL-SLICE` object.

```forth
REQUIRE utils/fs/drivers/vfs-ext4.f
```

## Mounting

```forth
CREATE bd  /BLOCK-DEVICE ALLOT
CREATE vol /VOLUME ALLOT

bd BD-OPEN THROW
bd vol VOL-RAW THROW

524288 A-XMEM ARENA-NEW THROW CONSTANT fs-arena
fs-arena vol EXT4-NEW THROW CONSTANT fs
```

`EXT4-NEW ( arena volume -- vfs ior )` constructs the core object and invokes
the binding mount callback. Constructor failure returns an inspectable VFS in
`VFS-L-NEW`, with the structured failure copied to `V.LAST-IOR`; it never
publishes `VFS-L-MOUNTED`.

Probe reads the 1024-byte primary superblock at volume-relative byte offset
1024 and returns `EXT4-PROBE-SCORE` (90) for the ext4 magic. A clean nonmatch
returns zero without an error. A checked read failure remains a volume-domain
VFS ior with backend detail and stale/partial/retryable flags preserved.

## Admission boundary

Before setting its private ready marker or publishing inode 2 as the VFS
root, mount verifies:

- the unchanged volume cookie/generation and 512-byte logical sector size;
- reflected raw CRC32C for the primary superblock and its UUID-derived seed;
- the pinned 1/2/4 KiB geometry, 64-byte descriptors, 128/256-byte inode
  forms, flex size, feature policy, clean state, and all volume bounds;
- every primary group descriptor and every initialized block/inode bitmap
  checksum, while honoring the admitted uninitialized-group flags;
- every sparse-super backup copy and its invariant geometry, features, UUID,
  group number, and checksum, plus every backup GDT descriptor CRC and
  immutable metadata location;
- allocation and checksum of each consumed inode;
- the clean internal 4 MiB JBD2 journal superblock and matching UUID; and
- every clean orphan-file block, including its per-block CRC32C tail (the
  bounded reader currently admits one through 4096 blocks).

The driver contains its own reflected CRC32C implementation. Akashic's public
`CRC32C` word is deliberately MSB-first and is not interchangeable with the
ext4 checksum contract.

Known refused feature bits return format-domain `VFS-R-UNSUPPORTED` with
`EXT4-D-FEATURE`. `RECOVER`, `ORPHAN_PRESENT`, a dirty state, or a legacy
orphan chain returns the distinct `EXT4-D-RECOVERY` refusal. Checksum and
structural failures return format-domain `VFS-R-CORRUPT`. No such failure can
leave a mounted or ready object.

## Read-only inspection

The current binding advertises directory enumeration, open/release, reads,
getattr, readlink, list/get xattr, statfs, syncfs, and fsync. Stable ext4 inode
number plus generation is used as the VFS identity. `VFS-CACHE-DENTRY`
therefore makes hard-link aliases share one vnode and preserves the
authoritative on-disk link count.

The implemented reader handles the structures exercised by all four
canonical external fixtures:

- checksummed linear directory blocks;
- depth-zero extent roots, including sparse holes and unwritten-zero
  semantics;
- regular files and fast or block-backed symlinks;
- 128-byte legacy and 256-byte primary inode checksums and metadata;
- inline and external-block `user.*` xattrs, including external-block CRC32C;
- concatenated NUL-terminated `LISTXATTR` names and raw `GETXATTR` values;
  and
- read-only `STATFS` geometry/counters and UUID-derived FSID cells.

Directory population snapshots the child head, inode count, and string-pool
cursor. Any I/O, checksum, allocation, or structural failure rolls the cache
back before returning. Sparse reads synthesize zeroes without issuing a media
read for the hole. `SYNCFS` and `FSYNC` are safe no-ops.

`EXT4-BINDING` has `VFS-BF-NEEDS-VOLUME`, `VFS-BF-READ-ONLY`, and
`VFS-BF-STABLE-IDS`. The VFS rejects all mutation before binding dispatch.
There are no `VOL-WRITE` or `VOL-FLUSH` paths in this module.

## Deliberate remaining limits

This is an implementation landing, not completion of the writable profile.
The following admitted structures still return stable unsupported behavior
and require supplemental real-image fixtures before the compatibility gate is
complete:

- HTree directory index traversal;
- external extent-tree nodes and legacy direct/indirect block maps;
- special-device inode metadata (encountering one is currently refused rather
  than publishing an invented device number);
- non-`user.*` xattr namespaces and POSIX ACL decoding;
- orphan files larger than 4096 filesystem blocks;
- the supplemental corruption matrix for duplicate/overlapping xattr records
  and data/xattr blocks that disagree with their allocation bitmaps;
- journal replay, orphan recovery, and every mutation operation; and
- generic path-level symlink following (ABI 1 currently exposes direct
  `READLINK`, but its resolver does not follow links).

No write capability will be advertised until replay/recovery, ordered-data
journaling, external-tool mutation checks, and power-cut qualification land.

## Public reference

```forth
EXT4-BINDING       ( -- binding )
EXT4-OPS           ( -- ops )
EXT4-CAPS          ( -- capabilities )
EXT4-PROBE-SCORE   ( -- 90 )
EXT4-NEW           ( arena volume -- vfs ior )

EXT4-BLOCK-SIZE@   ( vfs -- bytes )
EXT4-BLOCK-COUNT@  ( vfs -- blocks )
EXT4-GROUP-COUNT@  ( vfs -- groups )
EXT4-INODE-SIZE@   ( vfs -- bytes )
```

The authoritative format decisions, source pins, and qualification matrix
remain in [the ext4 compatibility profile](../ext4-compatibility-profile.md).
