# akashic-vfs-mp64fs — MP64FS Binding for the VFS Layer

Bridges the abstract VFS to the Megapad-64 native filesystem
(MP64FS).  Production transfer uses KDOS's serialized
`DISK-READ-CHECKED`, `DISK-WRITE-CHECKED`, and `DISK-FLUSH-CHECKED`
operations.  The binding does not poll the controller or translate its
results independently.

```forth
REQUIRE utils/fs/drivers/vfs-mp64fs.f
```

`PROVIDED akashic-vfs-mp64fs` — safe to include multiple times.
Depends on `akashic-vfs`.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Quick Start](#quick-start)
- [On-Disk Format](#on-disk-format)
- [Binding Context](#binding-context)
- [API Reference](#api-reference)
- [Vtable Callbacks](#vtable-callbacks)
- [Internal Helpers](#internal-helpers)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **Ambient disk binding** | Each VFS instance owns independent MP64FS cache state, but every instance currently targets KDOS's singleton checked disk API. Explicit device/volume identity, multi-disk routing, and stale-media handles belong to the next block-device contract. |
| **Cached metadata** | Superblock, bitmap, and full directory are cached in arena RAM on init.  Only data sectors hit the disk on read/write. |
| **Checked I/O** | Initialization refuses failed metadata reads. Data callbacks throw the precise nonzero block status rather than converting an I/O failure into EOF or a short success. |
| **Durable explicit sync** | Dirty bitmap and directory caches are written on `VFS-SYNC`, followed by the checked device FLUSH. Dirty state is retained until the complete sequence succeeds. `VFS-DESTROY` has only a void, best-effort teardown hook and is not a substitute for an explicit, reportable `VFS-SYNC`. |
| **Sector-aligned DMA** | Partial-sector reads/writes use a 512-byte scratch buffer.  Full sectors bypass the scratch for direct DMA. |
| **Matches KDOS layout** | Sector 0 = superblock, bitmap starts at 1, the next 12 sectors are the directory, and data follows. Geometry is derived from media capacity. |

---

## Quick Start

```forth
\ Create a VFS instance wired to MP64FS
524288 A-XMEM ARENA-NEW  IF -1 THROW THEN
    VMP-NEW  CONSTANT my-vfs

\ Initialise: reads superblock, bitmap, and directory from disk
my-vfs VMP-INIT ?DUP IF THROW THEN

\ Set as current VFS context
my-vfs VFS-USE

\ List root directory
my-vfs VFS-DIR

\ Open and read a file
S" /readme.txt" VFS-OPEN  CONSTANT fd
2048 ALLOT CONSTANT buf
buf 2048 fd VFS-READ  .  \ prints bytes read
fd VFS-CLOSE

\ Make the durability boundary explicit before the void teardown callback
my-vfs VFS-SYNC ?DUP IF THROW THEN

\ Clean up
my-vfs VFS-DESTROY
```

---

## On-Disk Format

MP64FS stores a flat directory table with parent slot IDs, allowing a bounded
directory tree. Files use a primary extent plus one optional secondary extent
and a bitmap free-space tracker.

### Disk Layout

| Sector(s) | Content |
|---|---|
| 0 | **Superblock** — magic `MP64`, marker 1, total_sectors u32@+6, derived geometry |
| 1..`bmap_sectors` | **Bitmap** — 1 bit per sector; `ceil(total_sectors / 4096)` sectors |
| next 12 sectors | **Directory** — 128 entries × 48 bytes = 6144 bytes |
| remaining sectors | **Data** — file content |

### Directory Entry (48 bytes)

| Offset | Size | Field |
|---|---|---|
| +0 | 24 | `name` — NUL-padded filename |
| +24 | 2 | `start_sec` — first data sector |
| +26 | 2 | `sec_count` — number of allocated sectors |
| +28 | 4 | `used_bytes` — actual byte count |
| +32 | 1 | `type` — 0=free, 1=raw/text, 8=dir |
| +33 | 1 | `flags` |
| +34 | 1 | `parent` — parent dir slot (0xFF = root) |
| +35 | 1 | reserved |
| +36 | 4 | `mtime` — modification time |
| +40 | 4 | `crc` |
| +44 | 2 | `ext1_start` — extension extent start |
| +46 | 2 | `ext1_count` — extension extent count |

---

## Binding Context

On `VMP-INIT`, the binding allocates an 8264-byte context block
from the VFS arena (stored in `V.BCTX`):

| Offset | Size | Field |
|---|---|---|
| +0 | 512 | Superblock cache (sector 0) |
| +512 | 1024 | Bitmap cache (two sectors maximum) |
| +1536 | 6144 | Directory cache (12 sectors) |
| +7680 | 512 | Scratch buffer (partial sector I/O) |
| +8192 | 48 | Six parsed geometry cells: total, data start, bitmap start/count, directory start/count |
| +8240 | 8 | `dirty-bmap` — nonzero when bitmap cache modified |
| +8248 | 8 | `dirty-dir` — nonzero when directory cache modified |
| +8256 | 8 | `ready` — nonzero only after complete metadata validation |

---

## API Reference

### VMP-NEW

```forth
VMP-NEW  ( arena -- vfs )
```

Create a VFS instance pre-wired to the MP64FS vtable.
Equivalent to `VMP-VTABLE VFS-NEW`.  The caller must still call
`VMP-INIT` on the returned VFS before use.

### VMP-INIT

```forth
VMP-INIT  ( vfs -- ior )
```

Initialise the MP64FS binding for a VFS instance:

1. Allocate binding context from the arena
2. DMA-read the superblock and validate marker 1 plus all derived geometry
   against `DISK-SECTORS`
3. DMA-read the complete bitmap and directory using the validated geometry
4. Populate the VFS root inode's children from the directory
   table: for each non-free root entry (parent == 0xFF),
   allocate an inode and link it into the child list

Returns `ior` = 0 on success, -1 for no disk/arena failure, -2 for bad magic,
-3 for a non-1 marker or inconsistent geometry, and -4 when a metadata sector
is advertised as free.  A malformed directory entry returns -5.  A checked
metadata-read failure returns its stable positive block-I/O status and no
bytes from the failed read are parsed or published.

### VMP-VTABLE

```forth
VMP-VTABLE  ( -- addr )
```

Address of the 10-slot VFS vtable populated with MP64FS
callbacks.  Used directly with `VFS-NEW` when `VMP-NEW` isn't
suitable.

---

## Vtable Callbacks

All callbacks match the VFS vtable contract defined in
[vfs.md](../vfs.md).

### _VMP-PROBE

```forth
_VMP-PROBE  ( sector-0-buf vfs -- flag )
```

Check bytes 0–3 for the magic sequence `MP64` (77, 80, 54, 52).
Returns `TRUE` if all four bytes match, `FALSE` otherwise.

### _VMP-INIT

```forth
_VMP-INIT  ( vfs -- ior )
```

Low-level init: allocates context, caches metadata, parses
geometry.  Called by `VMP-INIT` which then populates children.

### _VMP-READDIR

```forth
_VMP-READDIR  ( inode vfs -- )
```

Scan the cached directory for entries whose `parent` field matches
the inode's binding-id.  For each match, allocate a child inode
and link it into the parent's child list.

### _VMP-READ

```forth
_VMP-READ  ( buf len offset inode vfs -- actual )
```

Read up to `len` bytes starting at byte `offset` within the file.
Uses sector-aligned DMA for full sectors; a scratch buffer for
partial head/tail sectors.  Returns actual bytes read (clamped to
file size). A checked block failure is thrown; it is never reported as EOF or
zero progress. The current VFS callback does not return the controller's
structured completed-sector count alongside that exception.

### _VMP-WRITE

```forth
_VMP-WRITE  ( buf len offset inode vfs -- actual )
```

Write up to `len` bytes at byte `offset`. The binding grows the primary extent
in place when possible. If fragmented space blocks that growth, it allocates
the requested run as `ext1`; later growth extends that secondary extent in
place. Transfers stop and restart at extent boundaries. If allocation cannot
cover the whole request, VFS partial-write semantics apply. The callback marks
the bitmap/directory caches and inode metadata dirty and updates `used_bytes`.
A checked device failure throws the precise status. The current VFS callback
does not return the controller's structured completed-sector count on that
error, so callers must not infer that an unreported suffix succeeded.

### _VMP-SYNC

```forth
_VMP-SYNC  ( inode vfs -- ior )
```

For a non-root inode, first reflect its current name into its stable directory
slot. If the bitmap cache is dirty, write its validated sector count; if the
directory cache is dirty, write all validated directory sectors. Then issue
the checked device FLUSH that orders and makes those writes durable according
to the active backend contract. Only after all three stages succeed are the
cache dirty flags cleared. VFS also invokes the binding once with inode 0 so
metadata-only operations are flushed.

### _VMP-CREATE

```forth
_VMP-CREATE  ( inode vfs -- ior )
```

1. Find a free directory slot
2. Find one free sector for a file (directories allocate no data sectors)
3. Populate the directory entry (name, type, parent slot, sector
   allocation)
4. Mark bitmap sectors as allocated
5. Store the slot index in `IN.BID` and sector info in `IN.BDATA`

### _VMP-DELETE

```forth
_VMP-DELETE  ( inode vfs -- ior )
```

Clear both allocated extents and zero the directory entry. Marks both caches
as dirty.

### _VMP-TRUNCATE

```forth
_VMP-TRUNCATE  ( inode vfs -- ior )
```

Resize allocation and `used_bytes` to the inode's `IN.SIZE-LO`. Shrinking frees
unused secondary sectors first, then unused primary sectors while retaining
one primary sector for a file. Truncating to zero frees `ext1` and keeps that
single primary sector. Growth delegates to the same two-extent allocator used
by writes.

### _VMP-TEARDOWN

```forth
_VMP-TEARDOWN  ( vfs -- )
```

Flush dirty caches via `_VMP-SYNC`, then clear the `V.BCTX`
pointer.  Arena deallocation handles the memory.

---

## Internal Helpers

| Word | Stack | Description |
|---|---|---|
| `_VMP-CTX` | `( vfs -- ctx )` | Fetch the binding context from `V.BCTX` |
| `_VMP-DIRENT` | `( slot ctx -- de )` | Address of directory entry by slot index |
| `_VMP-NAMELEN` | `( de -- n )` | Length of NUL-terminated name (max 24) |
| `_VMP-DE.SEC` | `( de -- u16 )` | Start sector of entry |
| `_VMP-DE.COUNT` | `( de -- u16 )` | Sector count of entry |
| `_VMP-DE.USED` | `( de -- u32 )` | Used bytes of entry |
| `_VMP-DE.TYPE` | `( de -- u8 )` | Type field (0=free, 1=raw, 8=dir) |
| `_VMP-DE.PARENT` | `( de -- u8 )` | Parent directory slot |
| `_VMP-BIT-SET` | `( sector ctx -- )` | Mark a sector as allocated in bitmap cache |
| `_VMP-BIT-CLR` | `( sector ctx -- )` | Mark a sector as free in bitmap cache |
| `_VMP-BIT-TST` | `( sector ctx -- flag )` | Test whether a sector is allocated |
| `_VMP-FIND-FREE-SLOT` | `( ctx -- slot \| -1 )` | First free directory slot |
| `_VMP-FIND-FREE-RUN` | `( count ctx -- sector \| -1 )` | First contiguous free sector run |

---

## Quick Reference

```
VMP-NEW              ( arena -- vfs )
VMP-INIT             ( vfs -- ior )
VMP-VTABLE           ( -- addr )

_VMP-PROBE           ( sec0-buf vfs -- flag )
_VMP-INIT            ( vfs -- ior )
_VMP-READDIR         ( inode vfs -- )
_VMP-READ            ( buf len off inode vfs -- actual )
_VMP-WRITE           ( buf len off inode vfs -- actual )
_VMP-SYNC            ( inode vfs -- ior )
_VMP-CREATE          ( inode vfs -- ior )
_VMP-DELETE          ( inode vfs -- ior )
_VMP-TRUNCATE        ( inode vfs -- ior )
_VMP-TEARDOWN        ( vfs -- )
```
