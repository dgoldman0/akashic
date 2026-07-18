# akashic-vfs-mp64fs — volume-bound MP64FS

This binding connects the VFS to the Megapad-64 native filesystem. It is a
validated VFS ABI 1 binding and requires one explicit KDOS volume. It never
falls back to the ambient disk and all media traffic goes through
`VOL-READ`, `VOL-WRITE`, and `VOL-FLUSH`.

```forth
REQUIRE utils/fs/drivers/vfs-mp64fs.f
```

`PROVIDED akashic-vfs-mp64fs` makes repeated inclusion safe.

## Mounting

```forth
CREATE bd  /BLOCK-DEVICE ALLOT
CREATE vol /VOLUME ALLOT

bd BD-OPEN THROW
bd vol VOL-RAW THROW

524288 A-XMEM ARENA-NEW THROW CONSTANT fs-arena
fs-arena vol VMP-NEW THROW CONSTANT fs
```

`VMP-NEW ( arena volume -- vfs ior )` constructs the VFS and invokes the
binding's mount callback. A separate `VMP-INIT` call is not required;
`VMP-INIT ( vfs -- ior )` remains an idempotent compatibility entrypoint.
The same API accepts a checked `VOL-SLICE`, so filesystem LBA zero is volume
LBA zero rather than parent-device LBA zero.

Mount validates all of the following before exposing files:

- the volume descriptor, cookie, media generation, and 512-byte sector size;
- MP64FS magic, marker, and exact `super.total_sectors == VOL.SECTORS`;
- bitmap/directory geometry and metadata reservations;
- every occupied directory entry and both of its possible extents;
- primary/secondary non-overlap within a file and exclusive sector ownership
  between files.

The binding stores the attachment snapshot in `V.VOL-COOKIE` and
`V.MEDIA-GEN`. Core preflight catches attachment changes before dispatch.
If a volume operation reports stale media after that preflight, the driver
atomically changes the VFS lifecycle to `VFS-L-STALE` before returning the
error.

## Binding descriptor

`VMP-BINDING` is the public validated descriptor and `VMP-OPS` is its
27-slot operation table. The descriptor has `VFS-BF-NEEDS-VOLUME` and
advertises probe, mount, unmount, directory enumeration, open/release,
read/write, create/mkdir, unlink/rmdir, rename, truncate, getattr, syncfs, and
fsync.

MP64FS directory slots are reusable and have no generation number. Therefore
the binding intentionally does **not** advertise `VFS-CAP-STABLE-HANDLES` or
`VFS-BF-STABLE-IDS`. Unlinking an open file returns `VFS-E-BUSY`; replacing
an open rename victim does the same before either cached directory entry is
changed. This prevents an old FD from aliasing a newly reused slot or extent.

`PROBE` has the ABI shape `( volume -- score ior )`. It reads sector zero only
through that supplied volume, returns `VMP-PROBE-SCORE` (100) for `MP64`, zero
for a clean nonmatch, and a structured volume-domain ior for checked I/O
failure. It performs no mount allocation or mutation.

A constructor mount failure is terminal for that returned `VFS-L-NEW` object,
matching the core's lack of a remount transition. `VMP-INIT` returns the saved
`V.LAST-IOR` on a compatibility retry without allocating another context.
Root-population rollback clears the context's ready marker before the failure
is returned.

## I/O and errors

Read and write callbacks use the VFS ABI shape:

```forth
_VMP-READ   ( buf len offset dentry vfs -- actual ior )
_VMP-WRITE  ( buf len offset dentry vfs -- actual ior )
```

Partial head and tail sectors use the context scratch sector. Full sectors are
transferred directly, splitting at MP64FS's optional second extent. The driver
counts completed sectors before returning a failure, so `actual` remains
meaningful. An error after any progress has `VFS-IOR-F-PARTIAL`.

KDOS volume iors are translated at the binding boundary:

- VFS domain is `VFS-IOR-D-VOLUME` for transport, media, and attachment
  failures;
- the backend ior's meaningful low 32 bits are retained in
  `VFS-IOR-DETAIL`;
- retryable, partial, corrupt, stale, and read-only flags are mapped to their
  VFS equivalents;
- decoded on-disk validation failures use `VFS-IOR-D-FORMAT` and a corrupt
  or unsupported reason.

Callers can use `VFS-READ?` and `VFS-WRITE?` to receive progress and the
structured ior without throwing.

## Persistence and mutation

The binding caches the superblock, allocation bitmap, directory table, and one
scratch sector in its arena context. File growth prefers the primary extent
and uses the format's single secondary extent when necessary. Rename updates
the existing reusable directory slot and parent byte in the same cached metadata
transaction.

Free sectors are zeroed through `VOL-WRITE` before the bitmap or extent fields
claim them. A seek gap and truncate growth are likewise zeroed before
`used_bytes` advances, including the invisible tail of a pre-existing partial
sector. If zeroing fails, the old logical size remains published; harmless
zeroed free space or extra zeroed allocation may remain cached, but stale bytes
cannot become readable.

`VFS-SYNC` dispatches `SYNCFS`, which writes the dirty bitmap and directory
caches through `VOL-WRITE`, then issues `VOL-FLUSH`. Dirty flags are cleared
only after every required write and the flush succeed. Unmount reports sync
failure rather than silently discarding it.

## On-disk layout

| Region | Contents |
|---|---|
| volume sector 0 | `MP64` superblock and geometry |
| sector 1 onward | one or two allocation-bitmap sectors |
| next 12 sectors | 128 directory entries × 48 bytes |
| remaining sectors | file extents |

A directory entry stores a 24-byte NUL-padded name, primary sector/count,
used-byte count, type, parent slot, and optional secondary sector/count.
Directory parent `0xFF` denotes the VFS root.

## Public reference

```forth
VMP-BINDING          ( -- binding )
VMP-OPS              ( -- ops )
VMP-PROBE-SCORE      ( -- 100 )
VMP-NEW              ( arena volume -- vfs ior )
VMP-INIT             ( vfs -- ior )  \ compatibility; mount is automatic

_VMP-PROBE-VOLUME    ( volume -- score ior )
_VMP-READDIR         ( dentry vfs -- ior )
_VMP-READ            ( buf len off dentry vfs -- actual ior )
_VMP-WRITE           ( buf len off dentry vfs -- actual ior )
_VMP-CREATE          ( dentry vfs -- ior )
_VMP-DELETE          ( dentry vfs -- ior )
_VMP-RENAME          ( name-a name-u dentry parent victim flags vfs -- ior )
_VMP-TRUNCATE        ( dentry vfs -- ior )
_VMP-SYNCFS          ( vfs -- ior )
_VMP-FSYNC           ( dentry vfs -- ior )
_VMP-UNMOUNT         ( flags vfs -- ior )
```
