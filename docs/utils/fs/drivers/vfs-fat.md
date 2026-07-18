# akashic-vfs-fat — checked read-only FAT binding

This VFS ABI 1 binding reads FAT16 and FAT32 from one explicit KDOS volume.
It has no ambient-disk fallback and issues media I/O only through `VOL-READ`.
The implementation is intentionally read-only.

```forth
REQUIRE utils/fs/drivers/vfs-fat.f
```

## Mounting

```forth
CREATE bd  /BLOCK-DEVICE ALLOT
CREATE vol /VOLUME ALLOT

bd BD-OPEN THROW
bd vol VOL-RAW THROW

524288 A-XMEM ARENA-NEW THROW CONSTANT fs-arena
fs-arena vol VFAT-NEW THROW CONSTANT fs
```

`VFAT-NEW ( arena volume -- vfs ior )` constructs and mounts the filesystem.
`VFAT-INIT ( vfs -- ior )` remains an idempotent compatibility entrypoint.
A bounded `VOL-SLICE` works the same way; every BPB and cluster sector is
relative to that slice.

Mount validates the volume descriptor, cookie, generation, and sector size,
then checks the BPB before following any variable-size structure. The BPB
total-sector count must exactly match `VOL.SECTORS`. Reserved/FAT/root/data
geometry, FAT entry capacity, FAT type, and the FAT32 root cluster are bounded
before directory traversal. FAT12 is reported as an unsupported format.

`PROBE` has the ABI shape `( volume -- score ior )`. It reads sector zero only
through the supplied volume, returns `VFAT-PROBE-SCORE` (60) for a plausible
FAT BPB, zero for a clean nonmatch, and a structured volume-domain ior for a
checked read failure. Probe does not allocate a mount context.

A failed constructor mount is terminal for that returned `VFS-L-NEW` object,
because the core has no remount transition. A later compatibility `VFAT-INIT`
returns the saved `V.LAST-IOR` without consuming more arena space. Population
rollback clears the FAT type/ready marker before returning.

## Read-only contract

`VFAT-BINDING` has these flags:

- `VFS-BF-NEEDS-VOLUME`
- `VFS-BF-READ-ONLY`

It advertises probe, mount/unmount, readdir, open/release, read, getattr,
syncfs, and fsync. It does **not** advertise write, create, mkdir, unlink,
rmdir, rename, truncate, setattr, or link. The VFS therefore rejects mutation with
`VFS-E-READONLY` before dispatch. Driver-local mutation entrypoints also fail
closed and no `VOL-WRITE` or `VOL-FLUSH` path exists.

ABI 1 generic lookup is byte-sensitive. FAT short names are exposed in their
decoded on-disk spelling (normally uppercase); this binding therefore does not
claim `VFS-BF-CASE-INSENSITIVE` until a pinned folding rule exists.

`SYNCFS` and `FSYNC` are safe no-ops for this read-only binding.

## Reads and errors

```forth
_VFAT-READ  ( buf len offset dentry vfs -- actual ior )
```

The driver walks FAT chains with a traversal budget derived from the validated
data-cluster count. Cycles, out-of-range clusters, premature end-of-chain, and
out-of-volume sectors are rejected rather than treated as EOF. One cached FAT
sector and one cached directory sector reduce repeated reads; file data uses a
separate scratch sector.

Both the fixed FAT16 root and cluster-backed FAT16/FAT32 directories stop at
the first entry whose initial byte is `0x00`; bytes and later clusters after
that end marker are not published. FAT32 root identity comes from `BPB_RootClus`,
and 32-bit cluster fields are preserved when resolving and reading files above
cluster `0xffff`.

KDOS volume errors are translated into VFS structured iors. The backend ior's
low 32 bits are retained in `VFS-IOR-DETAIL`, transport failures use the volume
domain, and retryable/partial/corrupt/stale/read-only flags are mapped. If an
in-flight operation reports stale media, the driver first latches
`VFS-L-STALE`. Decoded FAT corruption uses the format domain. Any successful
progress returned with an error is marked partial.

## Public reference

```forth
VFAT-BINDING        ( -- binding )
VFAT-OPS            ( -- ops )
VFAT-PROBE-SCORE    ( -- 60 )
VFAT-NEW            ( arena volume -- vfs ior )
VFAT-INIT           ( vfs -- ior )

_VFAT-PROBE-VOLUME  ( volume -- score ior )
_VFAT-READDIR       ( dentry vfs -- ior )
_VFAT-READ          ( buf len off dentry vfs -- actual ior )
_VFAT-SYNCFS        ( vfs -- ior )
_VFAT-FSYNC         ( dentry vfs -- ior )
_VFAT-UNMOUNT       ( flags vfs -- ior )
```
