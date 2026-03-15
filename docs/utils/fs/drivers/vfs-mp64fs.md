# akashic-vfs-mp64fs — MP64FS Binding for the VFS Layer

Bridges the abstract VFS to the Megapad-64 native filesystem
(MP64FS).  All byte transfer goes through the BIOS disk
primitives (`DISK-SEC!`, `DISK-DMA!`, `DISK-N!`, `DISK-READ`,
`DISK-WRITE`) which are already defined by KDOS.

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
| **One VFS per disk** | Each VFS instance backed by MP64FS owns a single disk image.  Multiple MP64FS disks need multiple VFS instances. |
| **Cached metadata** | Superblock, bitmap, and full directory are cached in arena RAM on init.  Only data sectors hit the disk on read/write. |
| **Lazy flush** | Dirty bitmap and directory caches are written back only on explicit `VFS-SYNC` or `VFS-DESTROY`. |
| **Sector-aligned DMA** | Partial-sector reads/writes use a 512-byte scratch buffer.  Full sectors bypass the scratch for direct DMA. |
| **Matches KDOS layout** | Sector 0 = superblock, sector 1 = bitmap, sectors 2–13 = directory (128 entries × 48 bytes), sectors 14+ = data.  Compatible with `diskutil.py` and KDOS `FREAD`/`FWRITE`. |

---

## Quick Start

```forth
\ Create a VFS instance wired to MP64FS
524288 A-XMEM ARENA-NEW  IF -1 THROW THEN
    VMP-NEW  CONSTANT my-vfs

\ Initialise: reads superblock, bitmap, and directory from disk
my-vfs VMP-INIT DROP

\ Set as current VFS context
my-vfs VFS-USE

\ List root directory
my-vfs VFS-DIR

\ Open and read a file
S" /readme.txt" VFS-OPEN  CONSTANT fd
2048 ALLOT CONSTANT buf
buf 2048 fd VFS-READ  .  \ prints bytes read
fd VFS-CLOSE

\ Clean up (flushes dirty caches to disk)
my-vfs VFS-DESTROY
```

---

## On-Disk Format

MP64FS is a flat, single-directory-level filesystem with a
single-extent allocation model and a bitmap free-space tracker.

### Disk Layout

| Sector(s) | Content |
|---|---|
| 0 | **Superblock** — magic `MP64` (bytes 77 80 54 52), version u16@+4, total_sectors u32@+6, geometry |
| 1 | **Bitmap** — 1 bit per sector (4096 sectors max with one 512-byte bitmap sector) |
| 2–13 | **Directory** — 128 entries × 48 bytes = 6144 bytes = 12 sectors |
| 14+ | **Data** — file content |

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

On `VMP-INIT`, the binding allocates a 7712-byte context block
from the VFS arena (stored in `V.BCTX`):

| Offset | Size | Field |
|---|---|---|
| +0 | 512 | Superblock cache (sector 0) |
| +512 | 512 | Bitmap cache (sector 1) |
| +1024 | 6144 | Directory cache (sectors 2–13) |
| +7168 | 512 | Scratch buffer (partial sector I/O) |
| +7680 | 8 | `total-sectors` — u32 from superblock |
| +7688 | 8 | `data-start` — first data sector (constant 14) |
| +7696 | 8 | `dirty-bmap` — nonzero when bitmap cache modified |
| +7704 | 8 | `dirty-dir` — nonzero when directory cache modified |

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
2. DMA-read superblock (sector 0), bitmap (sector 1), and
   directory (12 sectors starting at 2)
3. Parse geometry (total sectors, data start)
4. Populate the VFS root inode's children from the directory
   table: for each non-free root entry (parent == 0xFF),
   allocate an inode and link it into the child list

Returns `ior` = 0 on success.

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
file size).

### _VMP-WRITE

```forth
_VMP-WRITE  ( buf len offset inode vfs -- actual )
```

Write up to `len` bytes at byte `offset`.  Same head/full/tail
sector strategy as read.  Marks the directory cache as dirty
(updates `used_bytes` if the write extends the file).

### _VMP-SYNC

```forth
_VMP-SYNC  ( inode vfs -- ior )
```

If the bitmap cache is dirty, write it back to sector 1.  If the
directory cache is dirty, write the 12 directory sectors back.
The `inode` argument is ignored (sync is global).

### _VMP-CREATE

```forth
_VMP-CREATE  ( inode vfs -- ior )
```

1. Find a free directory slot
2. Find a contiguous run of free sectors in the bitmap (default:
   1 sector for files, 0 for directories)
3. Populate the directory entry (name, type, parent slot, sector
   allocation)
4. Mark bitmap sectors as allocated
5. Store the slot index in `IN.BID` and sector info in `IN.BDATA`

### _VMP-DELETE

```forth
_VMP-DELETE  ( inode vfs -- ior )
```

Clear the allocated bitmap sectors and zero the directory entry.
Marks both caches as dirty.

### _VMP-TRUNCATE

```forth
_VMP-TRUNCATE  ( inode vfs -- ior )
```

Update the `used_bytes` field in the directory cache from the
inode's `IN.SIZE-LO`.

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
