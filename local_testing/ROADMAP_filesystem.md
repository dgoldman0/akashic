# Filesystem Support — Roadmap

Extended filesystem support for KDOS / Megapad-64.  Read (and where
useful, write) foreign filesystem images via the existing generic
block device, plus a VFS dispatch layer that unifies access through
the existing `OPEN` / `FREAD` / `FWRITE` / `FCLOSE` API.

The emulator's `Storage` device is a dumb sector-addressed block
device with DMA — it has zero knowledge of any filesystem format.
MP64FS parsing lives entirely in Forth (KDOS §7.6).  Adding new
filesystem drivers requires **no emulator changes** and **no BIOS
changes** — only new Forth modules and (optionally) Python-side
image builders for test fixture creation.

---

## Table of Contents

- [Current State — What We Already Have](#current-state--what-we-already-have)
  - [Storage Hardware](#storage-hardware)
  - [BIOS Disk Primitives](#bios-disk-primitives)
  - [KDOS File Abstraction](#kdos-file-abstraction)
  - [MP64FS](#mp64fs)
  - [Python-side Tooling](#python-side-tooling)
- [What's Missing](#whats-missing)
- [Architecture Overview](#architecture-overview)
- [Phase 0 — Abstract VFS Data Structure](#phase-0--abstract-vfs-data-structure)
  - [0.1 VFS Instance Lifecycle](#01-vfs-instance-lifecycle)
  - [0.2 Inode Slab & Cache](#02-inode-slab--cache)
  - [0.3 File Descriptor Pool](#03-file-descriptor-pool)
  - [0.4 Path Resolution](#04-path-resolution)
  - [0.5 OPEN / READ / WRITE / CLOSE / SEEK](#05-open--read--write--close--seek)
  - [0.6 Directory Operations](#06-directory-operations)
  - [0.7 Binding Contract](#07-binding-contract)
  - [0.8 Mount Table (Optional Convenience Layer)](#08-mount-table-optional-convenience-layer)
  - [0.9 MP64FS Binding](#09-mp64fs-binding)
- [Phase 1 — FAT16/FAT32 (Read-Write)](#phase-1--fat16fat32-read-write)
  - [1.1 BPB Parsing & Geometry](#11-bpb-parsing--geometry)
  - [1.2 FAT Table Navigation](#12-fat-table-navigation)
  - [1.3 Directory Traversal (SFN)](#13-directory-traversal-sfn)
  - [1.4 File Read](#14-file-read)
  - [1.5 File Write & Cluster Allocation](#15-file-write--cluster-allocation)
  - [1.6 Long Filename Support (LFN)](#16-long-filename-support-lfn)
  - [1.7 FAT12 Extension](#17-fat12-extension)
- [Phase 2 — Read-Only Archive Formats](#phase-2--read-only-archive-formats)
  - [2.1 tar (ustar)](#21-tar-ustar)
  - [2.2 romfs](#22-romfs)
- [Phase 3 — ISO 9660 (Read-Only)](#phase-3--iso-9660-read-only)
  - [3.1 Primary Volume Descriptor](#31-primary-volume-descriptor)
  - [3.2 Directory Records & Path Table](#32-directory-records--path-table)
  - [3.3 File Read](#33-file-read)
  - [3.4 Rock Ridge / Joliet (Optional)](#34-rock-ridge--joliet-optional)
- [Phase 4 — Minix FS v1 (Read-Write)](#phase-4--minix-fs-v1-read-write)
  - [4.1 Superblock & Geometry](#41-superblock--geometry)
  - [4.2 Inode & Zone Bitmaps](#42-inode--zone-bitmaps)
  - [4.3 Inode Table & Indirect Blocks](#43-inode-table--indirect-blocks)
  - [4.4 Directory Lookup](#44-directory-lookup)
  - [4.5 File Read/Write](#45-file-readwrite)
  - [4.6 File Creation & Deletion](#46-file-creation--deletion)
- [Phase 5 — ext2 (Read-Only)](#phase-5--ext2-read-only)
  - [5.1 Superblock & Block Group Descriptors](#51-superblock--block-group-descriptors)
  - [5.2 Inode Lookup](#52-inode-lookup)
  - [5.3 Extent Trees (ext4 Compat)](#53-extent-trees-ext4-compat)
  - [5.4 Directory Traversal](#54-directory-traversal)
  - [5.5 File Read](#55-file-read)
- [Phase 6 — Diagnostics & Utilities](#phase-6--diagnostics--utilities)
  - [6.1 FS-IDENTIFY](#61-fs-identify)
  - [6.2 FS-STAT](#62-fs-stat)
  - [6.3 MOUNT-INFO](#63-mount-info)
  - [6.4 HEXDUMP / SECTOR-DUMP](#64-hexdump--sector-dump)
- [Future Candidates](#future-candidates)
- [Format Feasibility Summary](#format-feasibility-summary)
- [Python-side Image Builders](#python-side-image-builders)
- [Dependency Graph](#dependency-graph)
- [Implementation Order](#implementation-order)
- [Design Constraints](#design-constraints)
- [Testing Strategy](#testing-strategy)
- [Decision Log](#decision-log)

---

## Current State — What We Already Have

### Storage Hardware

The emulator's `Storage` class (`devices.py`) presents a flat
sector-addressed block device at MMIO offset `0x0200`:

| Register | Offset | Size | Function |
|----------|--------|------|----------|
| CMD | +0x00 | 1 B | 0x01=READ, 0x02=WRITE, 0x03=STATUS, 0xFF=FLUSH |
| STATUS | +0x01 | 1 B | bit7=present, bit0=busy, bit1=error |
| SECTOR | +0x02 | 4 B LE | 32-bit sector number |
| DMA_ADDR | +0x06 | 8 B LE | 64-bit RAM target for DMA |
| SEC_COUNT | +0x0E | 1 B | Sectors per command (max 255) |
| DATA | +0x0F | 1 B | Byte-at-a-time alternative port |

Backed by a host file loaded into a `bytearray`.  512-byte sectors.
32-bit sector addressing (~2 TiB theoretical max).  SEC_COUNT is
1 byte, so a single DMA command transfers at most 255 sectors
(127.5 KiB); the BIOS helper `disk_read_sectors` handles
multi-batch for larger transfers.

**The storage layer is completely filesystem-agnostic.**  It knows
nothing about MP64FS — it just reads and writes sectors.  The
emulator can also hot-swap images at runtime (`swap_image`) and
auto-extends images on write beyond current size.

### BIOS Disk Primitives

Six words exposed to Forth (no changes needed):

| Word | Stack Effect | Function |
|------|-------------|----------|
| `DISK@` | ( -- status ) | Read STATUS register |
| `DISK-SEC!` | ( sector -- ) | Set 32-bit sector number |
| `DISK-DMA!` | ( addr -- ) | Set 64-bit DMA address |
| `DISK-N!` | ( count -- ) | Set sector count (1–255) |
| `DISK-READ` | ( -- ) | Issue READ command |
| `DISK-WRITE` | ( -- ) | Issue WRITE command |

Plus Higher-level KDOS helpers:

| Word | Stack Effect | Function |
|------|-------------|----------|
| `DISK?` | ( -- flag ) | Is disk present? |
| `B.LOAD` | ( desc sector -- ) | DMA read into buffer descriptor |
| `B.SAVE` | ( desc sector -- ) | DMA write from buffer descriptor |

### KDOS File Abstraction

**File descriptor layout (7 cells = 56 bytes):**

| Offset | Field | Notes |
|--------|-------|-------|
| +0 | start_sector | Primary extent start |
| +8 | max_sectors | Primary extent size |
| +16 | used_bytes | Current file size |
| +24 | cursor | Read/write position |
| +32 | dir_slot | Index into directory cache |
| +40 | ext1_start | Second extent start |
| +48 | ext1_count | Second extent count |

**File I/O words:**

| Word | Stack Effect | Notes |
|------|-------------|-------|
| `OPEN` | ( "name" -- fdesc\|0 ) | Allocates fd in dictionary |
| `FREAD` | ( addr len fdesc -- actual ) | Multi-batch DMA, advances cursor |
| `FWRITE` | ( addr len fdesc -- ) | Bounds-checked, advances cursor |
| `FSEEK` | ( pos fdesc -- ) | Set cursor |
| `FREWIND` | ( fdesc -- ) | Cursor = 0 |
| `FSIZE` | ( fdesc -- n ) | Return used_bytes |
| `FFLUSH` | ( fdesc -- ) | Writeback used_bytes to dir + sync |

**No `FCLOSE`** — open file descriptors consume dictionary space
permanently.  This is a known gap addressed by the VFS layer (Phase 0).

**Path resolution:** `_RESOLVE-PATH` handles leading `/` (absolute),
`..` (parent traversal), `name/` (subdirectory descent), final
component as filename.  Up to 16 levels of nested `LOAD`/`REQUIRE`.

### MP64FS

The native filesystem.  1 MiB default (2048 sectors), scalable to
larger images with dynamic bitmap geometry.

**Disk layout:**

| Sectors | Content |
|---------|---------|
| 0 | Superblock (magic `"MP64"`, version, geometry) |
| 1 | Allocation bitmap (1 sector per 4096 sectors) |
| 2–13 | Directory (128 entries × 48 bytes = 6144 bytes) |
| 14+ | Data area |

**Directory entry (48 bytes):**

| Offset | Size | Field |
|--------|------|-------|
| +0 | 24 B | Name (NUL-terminated, max 23 chars) |
| +24 | u16 | start_sector |
| +26 | u16 | sec_count |
| +28 | u32 | used_bytes |
| +32 | u8 | type (0=free, 1=raw, ..., 8=dir, 9=stream, 10=link) |
| +33 | u8 | flags (bit0=ro, bit1=system, bit2=encrypted, bit3=append) |
| +34 | u8 | parent slot (0xFF = root) |
| +35 | u8 | reserved |
| +36 | u32 | mtime |
| +40 | u32 | data CRC-32 |
| +44 | u16 | ext1_start (second extent) |
| +46 | u16 | ext1_count |

**Limits:** 128 files, 23-char names, 2 extents per file,
contiguous allocation only, single mtime, no permissions model
beyond flags, CRC-32 only on Python side.

### Python-side Tooling

`diskutil.py` — `MP64FS` class for host-side image creation:
`format()`, `inject_file()`, `read_file()`, `delete_file()`,
`mkdir()`, `mkstream()`, `mklink()`, `check()` (CRC verify),
`compact()` (defrag), `info()`.

CLI via `diskutil.py`: `format`, `ls`, `inject`, `cat`, `rm`,
`mkdir`, `check`, `compact`, `info`.

---

## What's Missing

1. **VFS dispatch layer** — currently `OPEN`/`FREAD`/`FWRITE` are
   hardwired to MP64FS.  No way to mount a second filesystem.
2. **`FCLOSE`** — file descriptors leak dictionary space.
3. **FAT support** — the universal interchange format.  SD cards,
   USB sticks, UEFI boot partitions all use FAT.
4. **Read-only archive formats** — tar and romfs for asset bundles
   and distribution images.
5. **ISO 9660** — CD-ROM / distribution images.
6. **Unix-style filesystem** — Minix FS for real permissions, hard
   links, proper inode semantics.
7. **ext2 read access** — read data from Linux volumes.
8. **Auto-detection** — identify a filesystem from its superblock
   without manual specification.
9. **Multi-device support** — infrastructure for a second storage
   controller (future hardware).

---

## Architecture Overview

The VFS is an **abstract, passable data structure** — analogous to
the DOM.  A VFS instance is a single cell on the Forth stack: an
address to an arena-backed tree of inodes, a file-descriptor pool,
and a string pool.  It knows nothing about sectors, DMA, or MMIO.

**Bindings** are separate modules that connect a VFS instance to a
backing store (disk image, network, memory buffer, cryptographic
vault).  The abstract layer defines the tree and the I/O API; the
binding implements the actual byte transfer.

```
                    ┌─────────────────────────────┐
                    │  Application Layer          │
                    │  VFS-OPEN  VFS-READ         │
                    │  VFS-WRITE VFS-CLOSE        │
                    │  VFS-DIR   VFS-MKDIR        │
                    │  (receive/pass VFS as value) │
                    └──────────┬──────────────────┘
                               │
              ┌────────────────┼─────────────────┐
              │                │                 │
     ┌────────▼────────┐       │      ┌──────────▼──────────┐
     │  VFS Instance A  │       │      │  VFS Instance B     │
     │  (abstract tree) │       │      │  (abstract tree)    │
     │  inodes, FDs,    │       │      │  inodes, FDs,       │
     │  path resolver   │       │      │  path resolver      │
     └────────┬─────────┘       │      └──────────┬──────────┘
              │                 │                  │
     ┌────────▼─────────┐      │       ┌──────────▼──────────┐
     │  MP64FS Binding   │      │       │  FAT Binding        │
     │  (sector layout,  │      │       │  (BPB, cluster      │
     │   bitmap, dirs)   │      │       │   chains, 8.3)      │
     └────────┬──────────┘      │       └──────────┬──────────┘
              │                 │                   │
              └────────┬────────┘───────────────────┘
                       │
            ┌──────────▼─────────────┐
            │  Sector I/O Layer      │
            │  DISK-SEC!  DISK-DMA!  │  ← global hardware,
            │  DISK-N!   DISK-READ   │    shared by bindings
            │  DISK-WRITE            │
            └──────────┬─────────────┘
            ┌──────────▼─────────────┐
            │  Storage MMIO Device   │
            └────────────────────────┘

     Optional convenience layer:
     ┌──────────────────────────────────────┐
     │  Mount Table  (vfs-mount.f)          │
     │  maps path prefixes → VFS instances  │
     │  MOUNT  UMOUNT  global OPEN/FREAD    │
     └──────────────────────────────────────┘
```

A VFS instance is self-contained.  You can create one, populate it
via a binding, pass it to any word that accepts a VFS, and destroy
it by tearing down its arena.  Multiple VFS instances coexist
without sharing any mutable state.  The optional mount table maps
path prefixes to VFS instances for backward-compatible global
`OPEN`/`FREAD` dispatch — but the mount table is sugar on top of
the core abstraction, not the core itself.

---

## Phase 0 — Abstract VFS Data Structure

**Modules:**
- `akashic/utils/fs/vfs.f` — abstract VFS (no hardware dependency).  **PROVIDED:** `akashic-vfs`
- `akashic/utils/fs/vfs-mount.f` — optional global mount table.  **PROVIDED:** `akashic-vfs-mount`

**Prefix:** `VFS-` (public), `_VFS-` (internal)

The VFS is an **abstract, first-class data structure** — a tree of
typed inodes backed by an arena, with a file-descriptor pool, a
path resolver, and a string pool.  It is the filesystem analogue
of the DOM: a passable, self-contained value on the Forth stack.

The abstract VFS knows **nothing about sectors, DMA, MMIO, or any
on-disk format**.  It is a pure in-memory tree with an I/O API
whose actual byte transfer is delegated to a **binding** — a
separate module (Phase 1+) that connects a VFS instance to a
backing store.

Without a binding, a VFS instance is a **ramdisk**: you can create
files, write bytes, read them back, list directories — all in
memory.  This is useful on its own (scratch space, in-memory asset
stores, test fixtures, IPC buffers, cryptographic vault trees).

### 0.1 VFS Instance Lifecycle

```forth
VFS-NEW      ( arena vtable -- vfs )
VFS-DESTROY  ( vfs -- )
VFS-USE      ( vfs -- )          \ set as current context
VFS-CUR      ( -- vfs )          \ read current context
```

`VFS-NEW` carves a VFS instance from the given KDOS arena.  The
`vtable` is the binding's dispatch table (§0.7); pass
`VFS-RAM-VTABLE` for a pure ramdisk with no backing store.  The
returned `vfs` is a single cell — an address — passable, storable
in a `CONSTANT` or `VARIABLE`, handed to any word.

`VFS-DESTROY` flushes dirty state via the binding's sync xt, then
frees the arena.  All inodes, FDs, and strings are reclaimed in
bulk — no per-object teardown.

`VFS-USE` / `VFS-CUR` follow the DOM's `DOM-USE` / `DOM-DOC`
pattern: a `VARIABLE _VFS-CUR` holds the active instance, and
all implicit-context words (`VFS-OPEN`, `VFS-DIR`, etc.) read it.
Explicit-context variants that take vfs on the stack are also
provided.

**VFS descriptor layout:**

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| +0 | cell | vtable | 10 binding xts (§0.7) |
| +8 | cell | flags | RO, dirty, mounted, … |
| +16 | cell | inode-slab-head | First slab page (§0.2) |
| +24 | cell | inode-free | Free-list head across slab pages |
| +32 | cell | inode-count | Live (allocated) inodes |
| +40 | cell | inode-hwm | High-water mark for eviction policy |
| +48 | cell | fd-pool | Pre-allocated FD slot array (§0.3) |
| +56 | cell | fd-max | Number of FD slots |
| +64 | cell | root-inode | Root directory inode |
| +72 | cell | cwd-inode | Current working directory |
| +80 | cell | str-pool | String pool base (bump + refcount) |
| +88 | cell | str-ptr | Next free byte in string pool |
| +96 | cell | str-end | String pool limit |
| +104 | cell | binding-ctx | Opaque pointer — binding's private state |
| +112 | cell | arena | Back-pointer to owning arena |
= 120 bytes (15 cells)

Creation allocates the descriptor, the initial inode slab page,
the FD pool, the string pool, and a root directory inode (type
`VFS-T-DIR`, inode number 1, name `"/"`).

### 0.2 Inode Slab & Cache

Inodes are the core objects in the VFS tree.  Each inode represents
a file, directory, symlink, or special node.

**Inode layout (14 cells = 112 bytes):**

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| +0 | cell | next-free / first-child | Union: free-list chain or tree link |
| +8 | cell | type | `VFS-T-FILE`, `VFS-T-DIR`, `VFS-T-SYMLINK`, … |
| +16 | 2 cells | size | u128 file size (supports >4 GiB) |
| +32 | cell | mode | Permission / attribute bits |
| +40 | cell | mtime | Modification timestamp |
| +48 | cell | ctime | Creation / change timestamp |
| +56 | cell | parent | Inode pointer |
| +64 | cell | next-sibling | Inode pointer (child list is singly-linked) |
| +72 | cell | name-handle | String pool handle |
| +80 | cell | binding-id | Stable on-disk identity (inode #, dir offset, cluster, …).  Opaque to VFS — the binding interprets it.  Survives eviction. |
| +88 | 2 cells | binding-data | 2 cells of binding-private data (start sector, extent info, FAT cluster, …).  Opaque to VFS. |
| +104 | cell | flags | Dirty, children-loaded, evictable, pinned, … |
= 112 bytes per inode

**Field accessor pattern** (same as DOM):

```forth
: IN.TYPE       8 + ;       \ +8
: IN.SIZE       16 + ;      \ +16  (2 cells)
: IN.MODE       32 + ;      \ +32
: IN.MTIME      40 + ;      \ +40
: IN.CTIME      48 + ;      \ +48
: IN.PARENT     56 + ;      \ +56
: IN.SIBLING    64 + ;      \ +64
: IN.NAME       72 + ;      \ +72
: IN.BID        80 + ;      \ +80  binding-id
: IN.BDATA      88 + ;      \ +88  binding-data (2 cells)
: IN.FLAGS      104 + ;     \ +104
```

**Slab allocation:**

Inodes are allocated from **chained slab pages**.  Each slab page
holds a fixed number of 112-byte inode slots plus a header cell
pointing to the next page.  When the current page fills, a new
page is allocated from the arena and linked to the chain.

```forth
_VFS-INODE-ALLOC   ( vfs -- inode )    \ pop from free-list; grow slab if empty
_VFS-INODE-FREE    ( inode vfs -- )    \ push onto free-list
```

Allocation is O(1) (free-list pop).  Slab growth is O(1) amortised
(arena bump).  No fixed upper bound on inode count — the limit is
arena capacity.

**Eviction (inode cache):**

For filesystems with millions of entries, materialised inodes for
closed / unreferenced paths can be evicted.  An evicted inode is
removed from the tree and returned to the free-list.  Its
`binding-id` is sufficient for the binding to reconstruct it on
next access.

Eviction rules:
- An inode is **pinnable** (refcount > 0 from open FDs, or
  explicitly pinned by the application).  Pinned inodes are never
  evicted.
- An inode is **evictable** when refcount = 0, not pinned, and not
  on the path from root to cwd.
- `_VFS-EVICT` scans the LRU tail of the inode list when
  `inode-count` exceeds `inode-hwm`.  It calls the binding's sync
  xt for dirty inodes before freeing them.
- The parent directory's `children-loaded` flag is cleared when
  any child is evicted, so the next descent re-populates via
  `xt-readdir`.

Eviction is **not required for correctness** — it is a memory
pressure valve.  Small or bounded filesystems never trigger it.
Large-scale use (cryptographic key trees, chain state) relies on
it.

**Refcounting:**

Each inode carries an implicit refcount: the number of open FDs
referencing it.  `VFS-OPEN` increments; `VFS-CLOSE` decrements.
Multiple FDs can reference the same inode (same file opened
twice).  Refcount 0 makes the inode eligible for eviction; it
does **not** free it immediately.

### 0.3 File Descriptor Pool

File descriptors are lightweight cursors into inodes.

**FD layout (6 cells = 48 bytes):**

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| +0 | cell | inode | Pointer to the referenced inode |
| +8 | 2 cells | cursor | u128 byte offset (matches inode size width) |
| +24 | cell | flags | Read, write, append, … |
| +32 | cell | vfs | Back-pointer to owning VFS instance |
| +40 | cell | next-free | Free-list chain (when not in use) |
= 48 bytes per FD

```forth
: FD.INODE    ;            \ +0
: FD.CURSOR   8 + ;        \ +8  (2 cells)
: FD.FLAGS    24 + ;       \ +24
: FD.VFS      32 + ;       \ +32
```

The FD pool is pre-allocated at `VFS-NEW` time.  Default: 256 slots
(256 × 48 = 12288 bytes).  Configurable via a creation parameter.
`VFS-OPEN` pops from the free-list; `VFS-CLOSE` pushes back.

FDs carry no format-specific data.  All format knowledge lives in
the inode's `binding-id` / `binding-data` and the binding's xts.

### 0.4 Path Resolution

```forth
VFS-RESOLVE   ( c-addr u vfs -- inode | 0 )
```

Resolve a path string to an inode.  Algorithm:

1. If the path starts with `/`, begin at `root-inode`; otherwise
   begin at `cwd-inode`.
2. For each `/`-delimited component:
   a. If the current inode is a directory whose `children-loaded`
      flag is clear, call the binding's `xt-readdir` to populate
      its children.
   b. Walk the child list (first-child → sibling chain), comparing
      `name-handle` strings.  `.` = stay, `..` = parent.
   c. If not found, return 0.
3. Return the final inode.

Path resolution is **lazy** — directories are populated on first
descent, not at mount time.  A binding for a 2 TiB FAT volume
materialises only the directories actually traversed.

Max path depth: limited only by arena memory (no fixed
`MAX_DEPTH`).  The resolver is iterative, not recursive.

### 0.5 OPEN / READ / WRITE / CLOSE / SEEK

These are the core file I/O words.  They operate on the current
VFS (`VFS-CUR`) by default; explicit-context variants take `vfs`
on the stack.

```forth
VFS-OPEN     ( c-addr u -- fd | 0 )         \ resolve path, alloc FD
VFS-READ     ( buf len fd -- actual )        \ read bytes at cursor
VFS-WRITE    ( buf len fd -- actual )        \ write bytes at cursor
VFS-CLOSE    ( fd -- )                       \ release FD, decr inode refcount
VFS-SEEK     ( pos fd -- )                   \ set cursor
VFS-REWIND   ( fd -- )                       \ cursor = 0
VFS-SIZE     ( fd -- u )                     \ inode size
VFS-TELL     ( fd -- u )                     \ current cursor
```

**READ and WRITE always dispatch through the binding.**  The
abstract layer does not cache file content.  Every `VFS-READ`
call invokes:

```
xt-read   ( buf len offset inode vfs -- actual )
```

where `offset` is the FD's cursor, `inode` carries the
`binding-id` and `binding-data` the binding needs to locate the
data, and `vfs` provides the `binding-ctx`.  The abstract layer
advances the cursor by `actual` bytes afterward.

The binding decides how to fulfil the read — sector DMA, memory
copy, network fetch, decryption, whatever.  The abstract layer
does not interpret the bytes.

**WRITE** follows the same pattern:

```
xt-write  ( buf len offset inode vfs -- actual )
```

The binding writes the bytes and may update the inode's
`binding-data` (e.g., allocate new clusters).  It sets the
inode's dirty flag.  The abstract layer updates `inode.size` if
the write extended the file.

Read-only bindings set `xt-write` to an error stub that returns
`-1` and sets an I/O error flag.

### 0.6 Directory Operations

```forth
VFS-DIR       ( vfs -- )                \ list cwd contents
VFS-CD        ( c-addr u vfs -- ior )   \ change cwd
VFS-MKDIR     ( c-addr u vfs -- ior )   \ create directory
VFS-RM        ( c-addr u vfs -- ior )   \ remove file or empty dir
VFS-MKFILE    ( c-addr u vfs -- inode ) \ create empty file
VFS-STAT      ( c-addr u vfs -- )       \ print file/dir info
```

**VFS-DIR** walks the cwd inode's child list and prints names,
types, and sizes.  If `children-loaded` is clear, it calls
`xt-readdir` first.

**VFS-MKDIR / VFS-MKFILE / VFS-RM** operate on the in-memory tree.
They allocate / free inodes, update the parent's child list, and
call the binding's `xt-sync` to persist the mutation.  For a
ramdisk binding, `xt-sync` is a no-op.

**Mutation notifications:**  After any structural change (create,
delete, rename), the abstract layer calls:

```
xt-sync   ( inode vfs -- ior )
```

The binding decides what to write back (directory entry, bitmap,
FAT chain, journal record, etc.).  The abstract layer marks the
inode clean after a successful sync.

### 0.7 Binding Contract

A binding is a separate module that provides a **vtable** — a
table of 10 execution tokens — and optionally a `binding-ctx`
initialization word.  The vtable is passed to `VFS-NEW` and
stored in the VFS descriptor.  The binding's xts are the only
code that touches the backing store.

**Vtable layout (10 cells = 80 bytes):**

| Index | xt Signature | Function |
|-------|-------------|----------|
| 0 | `( sector-0-buf vfs -- flag )` | **probe**: given sector 0 from a block device, return true if this binding recognises the format |
| 1 | `( vfs -- ior )` | **init**: read superblock / header, populate binding-ctx, create root inode's children (or defer to readdir) |
| 2 | `( vfs -- )` | **teardown**: flush dirty state, free binding-ctx resources |
| 3 | `( buf len offset inode vfs -- actual )` | **read**: read `len` bytes at `offset` from the file represented by `inode` into `buf` |
| 4 | `( buf len offset inode vfs -- actual )` | **write**: write `len` bytes at `offset` to the file represented by `inode` from `buf` |
| 5 | `( inode vfs -- )` | **readdir**: populate the children of a directory inode (lazy load) |
| 6 | `( inode vfs -- ior )` | **sync**: write back a dirty inode (and its associated on-disk structures) to the backing store |
| 7 | `( inode vfs -- ior )` | **create**: allocate on-disk structures for a newly created inode (dir entry, clusters, bitmap, …) |
| 8 | `( inode vfs -- ior )` | **delete**: free on-disk structures for a removed inode |
| 9 | `( inode vfs -- ior )` | **truncate**: resize / free data extents when file size changes |

Read-only bindings set xts 4, 7, 8, 9 to `_VFS-RO-STUB` which
aborts with "read-only filesystem".

**Ramdisk vtable (`VFS-RAM-VTABLE`):** Provided by `vfs.f` itself.
`read` and `write` copy bytes from/to an arena-allocated content
buffer stored in `binding-data`.  `readdir`, `sync`, `create`,
`delete` are no-ops or trivial arena operations.  No external
dependency.

**Binding context (`binding-ctx`):**  The binding allocates its own
private state — superblock cache, sector buffer, FAT table cache,
cryptographic key material, whatever it needs — and stores the
pointer in `vfs.binding-ctx`.  The abstract layer never
dereferences it; it only passes it through to the binding's xts.

**Binding identity (`binding-id` per inode):**  Each binding
assigns a stable identity to every inode it creates — an on-disk
inode number, a directory entry offset, a cluster number, a
content hash.  This identity survives inode eviction (§0.2).  If
an evicted inode is re-accessed, the binding reconstructs it from
`binding-id` alone.

### 0.8 Mount Table (Optional Convenience Layer)

**Module:** `akashic/utils/fs/vfs-mount.f`
**Prefix:** `VMNT-` (public), `_VMNT-` (internal)
**PROVIDED:** `akashic-vfs-mount`

The mount table is a **thin routing layer** that maps path
prefixes to VFS instances.  It exists solely to provide the
traditional `OPEN "/sd/readme.txt"` experience across multiple
VFS instances.  It is not required — applications that pass VFS
instances explicitly never need it.

**API:**

```forth
VMNT-MOUNT    ( vfs c-addr u -- ior )    \ bind VFS to mount point
VMNT-UMOUNT   ( c-addr u -- ior )        \ unbind
VMNT-RESOLVE  ( c-addr u -- vfs c-addr' u' | 0 )  \ longest-prefix match, return VFS + remainder path
VMNT-OPEN     ( c-addr u -- fd | 0 )     \ longest-prefix match → VFS-OPEN
VMNT-INFO     ( -- )                     \ list all mounts
```

**Constants:**

```forth
64  CONSTANT VMNT-MAX-ENTRIES   \ max simultaneous mount points
256 CONSTANT VMNT-PREFIX-SIZE   \ max bytes per mount-point prefix string
```

**Mount table entry layout (272 bytes = 34 cells):**

| Field | Size | Notes |
|-------|------|-------|
| prefix | 256 B | NUL-terminated prefix string |
| prefix-len | cell | Cached length of prefix (avoids repeated strlen) |
| vfs | cell | Pointer to VFS instance |

Total table: 64 × 272 = 17408 bytes (~17 KB).

The table holds **handles to VFS instances**, not driver state.
Each VFS instance is independently created, configured, and
destroyable.  The mount table is a directory of references.

**Lookup algorithm:**  `VMNT-RESOLVE` scans all entries, computing
the longest matching prefix.  Ties are broken by match length
(longest wins).  The remainder of the path (after stripping the
prefix) is returned for the VFS to resolve internally.

**Auto-detect mount helper:**

```forth
VMNT-AUTO   ( arena sector-0-buf c-addr u -- ior )
```

Reads sector 0 from the current disk into `sector-0-buf`, iterates
registered bindings calling each `probe` xt, creates a VFS with
the matching binding, calls `init`, and mounts at the given path.

### 0.9 MP64FS Binding

**Module:** `akashic/utils/fs/vfs-mp64fs.f`
**Prefix:** `VMP-` (public), `_VMP-` (internal)
**PROVIDED:** `akashic-vfs-mp64fs`

The first binding.  Wraps the existing MP64FS code as a VFS
binding, split cleanly from the abstract layer.

- **probe:** Check sector 0 bytes 0–3 = `"MP64"`.
- **init:** Read superblock, bitmap, directory sectors into
  `binding-ctx`.  Create inode stubs for root directory entries
  (name + binding-id = dir slot index; children populated lazily).
- **read:** Translate inode `binding-data` (start sector +
  extent info) into `DISK-SEC!` / `DISK-DMA!` / `DISK-READ`
  calls.  Handle multi-extent files.
- **write:** Same translation for writes.  Update bitmap for
  new allocation.  Mark inode dirty.
- **readdir:** For subdirectory inodes, scan the MP64FS directory
  table for entries whose parent slot matches the inode's
  `binding-id`.
- **sync:** Write back dirty directory entries, bitmap, superblock.
- **create / delete:** Allocate / free directory slots + data
  sectors via the existing MP64FS bitmap logic.
- **teardown:** Flush all dirty state, free `binding-ctx`.

After Phase 0, the boot sequence becomes:

```forth
my-arena VMP-VTABLE VFS-NEW CONSTANT boot-vfs
boot-vfs VFS-USE
boot-vfs VMP-INIT              \ binding reads disk, populates root
boot-vfs S" /" VMNT-MOUNT      \ register in mount table

\ existing code works unchanged through VMNT-OPEN:
S" /kernel.f" VMNT-OPEN  ...   \ dispatches to boot-vfs → MP64FS binding

\ or pass the VFS explicitly:
boot-vfs S" kernel.f" VFS-OPEN  ...  \ no mount table needed
```

All existing `REQUIRE`, `LOAD`, `DIR`, `OPEN` words can be
retrofitted to call `VMNT-OPEN` internally, preserving backward
compatibility while routing through the new architecture.

---

## Phase 1 — FAT16/FAT32 (Read-Write)

**Module:** `akashic/utils/fs/fat.f`
**Prefix:** `FAT-` (public), `_FAT-` (internal)
**PROVIDED:** `akashic-fat`

The universal interchange format.  SD cards, USB sticks, UEFI ESP
partitions.  This is the highest-value foreign filesystem to
support.

### 1.1 BPB Parsing & Geometry

Read the BIOS Parameter Block (BPB) from sector 0 of the mounted
range.  Extract:

| BPB Field | Offset | Size | Used For |
|-----------|--------|------|----------|
| BytsPerSec | 0x0B | u16 | Should be 512 |
| SecPerClus | 0x0D | u8 | Cluster size (1, 2, 4, 8, ..., 128) |
| RsvdSecCnt | 0x0E | u16 | Sectors before first FAT |
| NumFATs | 0x10 | u8 | Usually 2 |
| RootEntCnt | 0x11 | u16 | FAT12/16: root dir entries; FAT32: 0 |
| TotSec16 | 0x13 | u16 | Total sectors (16-bit, 0 for FAT32) |
| FATSz16 | 0x16 | u16 | Sectors per FAT (FAT12/16) |
| TotSec32 | 0x20 | u32 | Total sectors (32-bit) |
| FATSz32 | 0x24 | u32 | Sectors per FAT (FAT32) |
| RootClus | 0x2C | u32 | FAT32: root directory cluster |

**FAT type determination** (per Microsoft FAT spec):
- Count data clusters.  < 4085 → FAT12.  < 65525 → FAT16.  Else FAT32.

**Mount context** (~128 bytes): geometry fields + cached FAT sector
+ current directory cluster.

**probe:** Check bytes 0x1FE–0x1FF = 0x55AA (boot signature), then
validate BPB fields (BytsPerSec=512, SecPerClus is power of 2,
NumFATs ≥ 1).

### 1.2 FAT Table Navigation

```forth
_FAT-NEXT-CLUSTER  ( cluster ctx -- next-cluster )
```

Read the FAT entry for a given cluster.  For FAT16: each entry is
2 bytes, so `cluster × 2` gives the byte offset into the FAT.
Compute which FAT sector contains that offset, DMA-read it (with
a 1-sector cache), extract the entry.

For FAT32: each entry is 4 bytes (mask off upper 4 bits).

**End-of-chain:** FAT16 ≥ 0xFFF8, FAT32 ≥ 0x0FFFFFF8.

**Cluster-to-sector:** `first-data-sector + (cluster - 2) × sec-per-cluster`.

**FAT sector cache:** Keep one FAT sector cached in the mount
context.  Most sequential reads hit the same FAT sector, so
this avoids repeated DMA for cluster chain walks.

### 1.3 Directory Traversal (SFN)

FAT directories are arrays of 32-byte entries:

| Offset | Size | Field |
|--------|------|-------|
| 0x00 | 8 | Short name (space-padded) |
| 0x08 | 3 | Extension (space-padded) |
| 0x0B | 1 | Attributes (RO, Hidden, System, Volume, Dir, Archive) |
| 0x14 | 2 | First cluster high (FAT32) |
| 0x1A | 2 | First cluster low |
| 0x1C | 4 | File size |

`0x00` at offset 0 = end of directory.  `0xE5` = deleted entry.

```forth
_FAT-FIND-ENTRY  ( c-addr u ctx -- dirent-addr | 0 )
```

Walk directory cluster chain, DMA each cluster, scan 32-byte
entries for 8.3 name match (case-insensitive).  Return pointer
to entry in cache buffer, or 0 if not found.

**Subdirectories:** If attributes bit 4 is set, the entry is a
directory.  Its first cluster points to another directory cluster
chain.  `.` and `..` entries are standard.

### 1.4 File Read

```forth
_FAT-READ  ( addr len fdesc -- actual )
```

The fd stores the current cluster and byte offset within it.
Read loop:

1. Compute bytes remaining in current cluster.
2. DMA-read min(requested, remaining-in-cluster) from the
   appropriate sector(s) within the cluster.
3. If more data needed and not end-of-chain, follow FAT to next
   cluster, repeat.
4. Return bytes actually read.

### 1.5 File Write & Cluster Allocation

```forth
_FAT-WRITE  ( addr len fdesc -- ior )
```

Same structure as read, but:

1. If cursor is at end of allocated clusters, allocate a new
   cluster: scan FAT for a free entry (value 0), update the
   chain, write back FAT sector.
2. DMA-write data.
3. Update directory entry's file size and modification time.

**Free cluster search:** Linear scan from last-allocated cluster
(or `FSInfo` hint on FAT32).  Write both FAT copies for
consistency.

**MKFILE / RM / MKDIR:** Follow the same 32-byte directory entry
creation/deletion pattern.  MKDIR allocates one cluster, writes
`.` and `..` entries.

### 1.6 Long Filename Support (LFN)

LFN entries are stored as sequences of 32-byte directory
entries with attribute byte 0x0F, preceding the 8.3 SFN entry.
Each LFN entry holds 13 UTF-16LE characters across three
disjoint fields in the 32-byte record.

**LFN is deferrable to v2.**  SFN-only support is fully
functional and interoperable — every FAT file has an SFN entry.
LFN adds ~60 lines for decode and ~40 for encode.

### 1.7 FAT12 Extension

FAT12 uses 12-bit entries packed into 1.5-byte pairs.  Reading
a cluster entry requires extracting 12 bits across a byte
boundary.  ~20 additional lines on top of the FAT16 base.

FAT12 is mainly relevant for floppy disk images (1.44 MiB) and
very small SD cards.  Low priority but trivial once FAT16 works.

---

## Phase 2 — Read-Only Archive Formats

Minimal-effort formats useful for asset bundles, Forth source
distribution, and data packs.

### 2.1 tar (ustar)

**Module:** `akashic/utils/fs/tar.f`
**PROVIDED:** `akashic-tar`

tar archives are sequences of 512-byte header records followed
by file data rounded up to 512-byte boundaries.  Perfect fit for
the sector-based block device.

**Header (ustar, 512 bytes):**

| Offset | Size | Field |
|--------|------|-------|
| 0 | 100 | Filename (NUL-terminated) |
| 100 | 8 | Mode (octal ASCII) |
| 108 | 8 | UID |
| 116 | 8 | GID |
| 124 | 12 | Size (octal ASCII) |
| 136 | 12 | Mtime (octal) |
| 148 | 8 | Checksum |
| 156 | 1 | Type ('0'=file, '5'=dir, etc.) |
| 157 | 100 | Linkname |
| 257 | 6 | Magic "ustar" |
| 263 | 2 | Version "00" |
| 265 | 32 | Uname |
| 297 | 32 | Gname |
| 329 | 8 | Devmajor |
| 337 | 8 | Devminor |
| 345 | 155 | Prefix |

**probe:** Check bytes 257–261 = `"ustar"`.

**mount:** No superblock to read.  Mount context just records the
sector range.

**open:** Sequential scan of headers from sector 0.  Parse
filename, compare, if match record the data start sector and
size.  Terminate on two consecutive zero-filled sectors.

**read:** Direct DMA from the recorded sector offset.  Trivial.

**dir:** Same sequential scan, print each filename + size.

**No write support** — tar has no allocation table or directory
structure to update.

**Estimated size:** ~60 lines of Forth, ~30 lines of Python
image builder.

### 2.2 romfs

**Module:** `akashic/utils/fs/romfs.f`
**PROVIDED:** `akashic-romfs`

Linux romfs — a minimal read-only filesystem designed for
embedded systems.

**Superblock (first 16+ bytes):**

| Offset | Size | Field |
|--------|------|-------|
| 0 | 8 | Magic: `"-rom1fs-"` |
| 8 | 4 | Full size (BE u32) |
| 12 | 4 | Checksum |
| 16 | var | Volume name (NUL-terminated, 16-byte aligned) |

File entries follow immediately, each 16-byte aligned:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 4 | next_ptr ∣ type (low 4 bits = type, rest = next offset) |
| 4 | 4 | spec_info (hard link target, directory start, etc.) |
| 8 | 4 | size |
| 12 | 4 | checksum |
| 16 | var | name (NUL-terminated, 16-byte aligned) |
| aligned | var | file data |

**probe:** Check bytes 0–7 = `"-rom1fs-"`.

**Types:** 0=hard link, 1=directory, 2=regular file,
3=symlink, 4=block dev, 5=char dev, 6=socket, 7=fifo.

Only types 1 (dir) and 2 (file) matter for us.

**Estimated size:** ~80 lines of Forth, ~40 lines of Python
image builder.

---

## Phase 3 — ISO 9660 (Read-Only)

**Module:** `akashic/utils/fs/iso9660.f`
**PROVIDED:** `akashic-iso9660`

The standard for CD-ROM images and software distribution.
All data is stored in 2048-byte logical blocks (4 × 512-byte
sectors on our device).

### 3.1 Primary Volume Descriptor

Located at logical block 16 (sector 64):

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | Type (1 = primary) |
| 1 | 5 | "CD001" |
| 6 | 1 | Version (1) |
| 80 | 8 | Volume space size (both-endian u32) |
| 128 | 4 | Logical block size (both-endian u16) |
| 132 | 8 | Path table size |
| 140 | 4 | Path table LBA (LE u32) |
| 156 | 34 | Root directory record |

**probe:** Read sector 64, check bytes 1–5 = `"CD001"`.

### 3.2 Directory Records & Path Table

Directory records are variable-length:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | Record length |
| 2 | 8 | Extent LBA (both-endian u32) |
| 10 | 8 | Data length (both-endian u32) |
| 25 | 1 | Flags (bit1=directory) |
| 32 | 1 | File identifier length |
| 33 | var | File identifier |

Identifiers use `"FILENAME.EXT;1"` format.  Directories are
stored as extent chains of directory records.

### 3.3 File Read

Once the extent LBA and data length are known from the directory
record, file read is a straight sector DMA — no cluster chains,
no indirection.  ISO 9660 files are contiguous on disk.

### 3.4 Rock Ridge / Joliet (Optional)

- **Rock Ridge:** POSIX extensions via System Use Entries in
  directory records.  Adds long filenames, permissions, symlinks.
  ~80 extra lines.
- **Joliet:** UCS-2 filenames via a supplementary volume
  descriptor.  ~40 extra lines.

Both are deferrable.  Base ISO 9660 with standard identifiers is
fully functional.

**Estimated size:** ~120 lines of Forth, ~50 lines of Python.

---

## Phase 4 — Minix FS v1 (Read-Write)

**Module:** `akashic/utils/fs/minixfs.f`
**PROVIDED:** `akashic-minixfs`

The teaching filesystem from Tanenbaum's Operating Systems.
Clean Unix semantics (permissions, hard links, timestamps,
regular directories).  The most realistic path to proper
Unix-style filesystem support on KDOS.

### 4.1 Superblock & Geometry

Located at offset 1024 bytes (sector 2):

| Offset | Size | Field |
|--------|------|-------|
| 0 | u16 | s_ninodes |
| 2 | u16 | s_nzones (v1) |
| 4 | u16 | s_imap_blocks |
| 6 | u16 | s_zmap_blocks |
| 8 | u16 | s_firstdatazone |
| 10 | u16 | s_log_zone_size |
| 12 | u32 | s_max_size |
| 16 | u16 | s_magic (0x137F for v1, 0x138F for v1 30-char names) |
| 18 | u16 | s_state |

**probe:** Read sector 2, check magic at offset 16 = 0x137F or
0x138F.

Zone size = 1024 << s_log_zone_size bytes (typically 1024).

### 4.2 Inode & Zone Bitmaps

- **Inode bitmap:** `s_imap_blocks` blocks starting at block 2.
  Bit N = 1 means inode N is allocated.
- **Zone bitmap:** `s_zmap_blocks` blocks starting after inode
  bitmap.  Bit N = 1 means zone N is allocated.

Same bit-manipulation code pattern as MP64FS bitmap.

### 4.3 Inode Table & Indirect Blocks

Inodes start after the zone bitmap.  Minix v1 inode (32 bytes):

| Offset | Size | Field |
|--------|------|-------|
| 0 | u16 | i_mode (permissions + file type) |
| 2 | u16 | i_uid |
| 4 | u32 | i_size |
| 8 | u32 | i_time |
| 12 | u8 | i_gid |
| 13 | u8 | i_nlinks |
| 14 | u16 ×7 | i_zone[0..6] — direct zone numbers |
| 28 | u16 | i_zone[7] — indirect |
| 30 | u16 | i_zone[8] — double indirect |

**Zone lookup:**
- Zones 0–6: direct.
- Zone 7: read indirect block (512 × u16 entries).
- Zone 8: double indirect (u16 → indirect block → u16 → data).

Max file size: 7 × 1K + 512 × 1K + 512 × 512 × 1K ≈ 262 MiB.

### 4.4 Directory Lookup

Minix v1 directories are regular files containing 16-byte or
32-byte entries (depending on magic: 14-char or 30-char names):

| Size | Field |
|------|-------|
| u16 | inode number (0 = deleted) |
| 14 or 30 | filename (NUL-padded) |

Walk directory data zones, scan entries.

### 4.5 File Read/Write

Read: walk inode zone list, DMA each zone.
Write: if a zone pointer is 0, allocate from zone bitmap, update
inode.  If past direct zones, allocate/update indirect block.

### 4.6 File Creation & Deletion

- **Create:** allocate inode from bitmap, write inode, add
  directory entry, allocate initial zones.
- **Delete:** clear directory entry, decrement link count, if
  links = 0 free all zones + indirect blocks + inode.

**Estimated size:** ~250 lines of Forth, ~80 lines of Python
image builder.

---

## Phase 5 — ext2 (Read-Only)

**Module:** `akashic/utils/fs/ext2.f`
**PROVIDED:** `akashic-ext2`

Read-only access to ext2/3/4 volumes.  ext2 is the base format;
ext3 adds journaling (ignorable for read-only), ext4 adds
extent trees (§5.3 handles them).

### 5.1 Superblock & Block Group Descriptors

Superblock at offset 1024 bytes:

| Offset | Size | Field |
|--------|------|-------|
| 0 | u32 | s_inodes_count |
| 4 | u32 | s_blocks_count |
| 24 | u32 | s_log_block_size (block = 1024 << this) |
| 40 | u32 | s_blocks_per_group |
| 56 | u16 | s_magic (0xEF53) |
| 60 | u16 | s_state |
| 76 | u32 | s_rev_level |
| 88 | u16 | s_inode_size (≥ 128) |
| 96 | u32 | s_feature_compat |
| 100 | u32 | s_feature_incompat |

**probe:** Read sector 2, check magic at superblock offset 56 =
0xEF53.

Block Group Descriptor Table starts at block 2 (for 1K blocks)
or block 1 (for ≥ 2K blocks).  Each BGD is 32 bytes:

| Field | Offset | Size |
|-------|--------|------|
| bg_inode_table | 8 | u32 |
| bg_inode_bitmap | 4 | u32 |
| bg_block_bitmap | 0 | u32 |

### 5.2 Inode Lookup

Inode N is in block group `(N - 1) / inodes_per_group`.  Index
within group: `(N - 1) % inodes_per_group`.  Read the inode
table block for that group, extract the 128+ byte inode.

ext2 inode (128 bytes, first 40 used for basic fields):

| Offset | Size | Field |
|--------|------|-------|
| 0 | u16 | i_mode |
| 4 | u32 | i_size (low 32) |
| 28 | u32 | i_flags |
| 40 | u32 ×12 | i_block[0..11] — direct blocks |
| 88 | u32 | i_block[12] — indirect |
| 92 | u32 | i_block[13] — double indirect |
| 96 | u32 | i_block[14] — triple indirect |
| 108 | u32 | i_size_high (for >4G files, ext4) |

### 5.3 Extent Trees (ext4 Compat)

If `i_flags & 0x80000` (EXT4_EXTENTS_FL), the `i_block` field
contains an extent tree header:

| Offset | Size | Field |
|--------|------|-------|
| 0 | u16 | eh_magic (0xF30A) |
| 2 | u16 | eh_entries |
| 4 | u16 | eh_max |
| 6 | u16 | eh_depth (0 = leaf) |

Followed by extent entries (12 bytes each):

| Offset | Size | Field |
|--------|------|-------|
| 0 | u32 | ee_block (logical block) |
| 4 | u16 | ee_len |
| 6 | u16 | ee_start_hi |
| 8 | u32 | ee_start_lo |

Depth 0 = leaf extents (direct block runs).
Depth > 0 = index nodes pointing to child extent blocks.

For read-only access, walking extent trees is straightforward:
binary search the index, read the child block, repeat until
depth 0, then the leaf gives a contiguous block run.

### 5.4 Directory Traversal

ext2 directories are regular files containing variable-length
records:

| Offset | Size | Field |
|--------|------|-------|
| 0 | u32 | inode |
| 4 | u16 | rec_len |
| 6 | u8 | name_len |
| 7 | u8 | file_type |
| 8 | var | name |

Walk records via `rec_len` until end of directory data.

### 5.5 File Read

Same pattern as minixfs: walk block list (direct → indirect →
double indirect, or extent tree), DMA each block.  Read-only,
so no bitmap or allocation logic needed.

**Estimated size:** ~300 lines of Forth, ~60 lines of Python
(can use `mke2fs` to create test images).

---

## Phase 6 — Diagnostics & Utilities

### 6.1 FS-IDENTIFY

```forth
FS-IDENTIFY    ( start-sec -- c-addr u | 0 0 )
```

Read magic bytes from the given sector range, return the
filesystem name as a string (`"mp64fs"`, `"fat32"`, `"ext2"`,
etc.) or 0 0 if unrecognized.  Checks are ordered by
distinctiveness:

1. Sector 0 bytes 0–3 = `"MP64"` → mp64fs
2. Sector 0 bytes 0x1FE–0x1FF = 0x55AA + valid BPB → fat12/16/32
3. Sector 0 bytes 0–7 = `"-rom1fs-"` → romfs
4. Sector 2 offset 16 = 0x137F/0x138F → minixfs v1
5. Sector 2 offset 56 = 0xEF53 → ext2/3/4
6. Sector 64 bytes 1–5 = `"CD001"` → iso9660
7. Sector 0 bytes 257–261 = `"ustar"` → tar

### 6.2 FS-STAT

```forth
FS-STAT        ( c-addr u -- )
```

Print statistics for the mounted filesystem at the given mount
point: type, capacity, used/free space, file count, mount flags.

### 6.3 MOUNT-INFO

```forth
MOUNT-INFO     ( -- )
```

List all active mounts with mount point, driver name, sector
range, and flags.

### 6.4 HEXDUMP / SECTOR-DUMP

```forth
SECTOR-DUMP    ( sector -- )
```

Read and hex-dump a single 512-byte sector.  Useful for
debugging new filesystem drivers.

---

## Future Candidates

These are not on the current roadmap but remain feasible for
later phases:

| Filesystem | Access | Complexity | Value | Notes |
|-----------|--------|-----------|-------|-------|
| CP/M | RW | ~80 LOF | Retro interop | 128-byte logical sectors, extent-based directory, no subdirs |
| littlefs | RW | ~500 LOF | Flash hardware | COW metadata, wear leveling; relevant if Megapad targets NOR flash |
| Amiga OFS/FFS | RO | ~250 LOF | Retro interop | Per-block checksums, header/data block chains |
| NTFS | RO | ~2000+ LOF | Low | B-tree MFT, attribute-based everything; impractical in Forth |
| HFS+ | RO | ~1500+ LOF | Low | B-tree catalog, complex | 
| Btrfs/ZFS/XFS | — | 10K+ LOF equiv | None | COW/B-tree/journal; completely out of scope |
| ext3/4 write | RW | ~800+ LOF | Moderate | Journaling + extent manipulation; ext2 read-only is the pragmatic choice |
| F2FS/JFFS2/YAFFS | — | ~1000+ LOF | Flash-only | Raw NAND access patterns the block device doesn't expose |
| UDF | RO | ~300 LOF | DVD interop | Successor to ISO 9660; more complex but well-documented |
| SquashFS | RO | ~400 LOF | Compressed images | Requires decompression (zlib/lz4); possible if we add a decompress primitive |

---

## Format Feasibility Summary

| Format | Est. Lines | R/W | Probe Signature | Sector for Superblock | Notes |
|--------|------------|-----|-----------------|----------------------|-------|
| VFS layer | ~150 | — | — | — | Prerequisite for everything |
| FAT16/32 | ~300 | RW | 0x55AA + BPB | 0 | Universal interop |
| FAT12 | +20 | RW | (same) | 0 | Floppy images |
| LFN | +100 | RW | (same) | 0 | Long filenames for FAT |
| tar | ~60 | RO | "ustar" @257 | 0 | Asset bundles |
| romfs | ~80 | RO | "-rom1fs-" @0 | 0 | Embedded RO images |
| ISO 9660 | ~120 | RO | "CD001" @sec64 | 64 | CD-ROM / distribution |
| Minix v1 | ~250 | RW | 0x137F @sec2 | 2 | Unix semantics |
| ext2 | ~300 | RO | 0xEF53 @sec2 | 2 | Linux volume access |
| Diagnostics | ~60 | — | — | — | FS-IDENTIFY, MOUNT-INFO |

**Total estimated:** ~1440 lines of Forth across all phases,
~400 lines of Python image builders/tests.

---

## Python-side Image Builders

Each filesystem driver benefits from a Python-side image builder
for creating test fixtures (and for pre-populating media on the
host).

| Driver | Python Class | Purpose |
|--------|-------------|---------|
| MP64FS | `MP64FS` (exists in `diskutil.py`) | Native format, already done |
| FAT | `FATImage` | Create FAT16/32 images, inject files, set BPB |
| tar | `TarImage` | Create ustar archives from file lists |
| romfs | `RomfsImage` | Pack files into romfs layout |
| ISO 9660 | `ISOImage` (or shell out to `mkisofs`) | Create ISO images |
| Minix v1 | `MinixImage` (or shell out to `mkfs.minix`) | Create minixfs images |
| ext2 | Shell out to `mke2fs` / `debugfs` | Create ext2 images |

For ISO, Minix, and ext2 the pragmatic approach is to shell out
to standard Linux tools (`mkisofs`/`genisoimage`, `mkfs.minix`,
`mke2fs`) and use the resulting images as test fixtures.  Only FAT,
tar, and romfs warrant pure-Python builders (for portability and
because the formats are simple enough).

---

## Dependency Graph

```
Phase 0: VFS Layer ─────────────────────────────────┐
   0.1 Driver registration                         │
   0.2 MOUNT / UMOUNT                              │
   0.3 VFS-aware OPEN/FREAD/FWRITE/FCLOSE          │
   0.4 MP64FS retrofit                             │
        │                                           │
        ├────────────────┬──────────────────┐       │
        │                │                  │       │
        ▼                ▼                  ▼       │
Phase 1: FAT     Phase 2: tar/romfs   Phase 3: ISO │
   1.1 BPB          2.1 tar              3.1 PVD   │
   1.2 FAT table    2.2 romfs            3.2 Dir   │
   1.3 Dir SFN                           3.3 Read  │
   1.4 Read                                        │
   1.5 Write                                       │
   1.6 LFN (v2)                                    │
   1.7 FAT12 (v2)                                  │
        │                │                  │       │
        └────────────────┴──────────────────┘       │
                         │                          │
                         ▼                          │
                  Phase 4: Minix FS                 │
                     4.1–4.6                        │
                         │                          │
                         ▼                          │
                  Phase 5: ext2                     │
                     5.1–5.5                        │
                         │                          │
                         ▼                          │
                  Phase 6: Diagnostics              │
                     6.1–6.4                        │
```

Phases 1, 2, and 3 are independent of each other — they only
depend on Phase 0.  Phase 4 and 5 can also be done in any order
after Phase 0, but are sequenced by complexity (minixfs teaches
inode/zone concepts useful for ext2).

---

## Implementation Order

| Step | Deliverable | Est. Lines | Depends On |
|------|-------------|------------|------------|
| 1 | VFS driver vtable + registration | ~30 | — |
| 2 | MOUNT / UMOUNT + mount table | ~40 | Step 1 |
| 3 | FD pool + VFS-aware OPEN/FREAD/FWRITE/FCLOSE | ~50 | Step 2 |
| 4 | MP64FS retrofit as VFS driver | ~30 | Step 3 |
| 5 | Round-trip test: MOUNT mp64fs → OPEN → FREAD → FCLOSE | ~0 (test) | Step 4 |
| 6 | FAT BPB + geometry + probe | ~40 | Step 3 |
| 7 | FAT table navigation + cluster walk | ~50 | Step 6 |
| 8 | FAT directory traversal (SFN) | ~40 | Step 7 |
| 9 | FAT file read | ~30 | Step 8 |
| 10 | FAT round-trip: mount SD image → DIR → OPEN → FREAD | ~0 (test) | Step 9 |
| 11 | FAT file write + cluster alloc | ~60 | Step 9 |
| 12 | FAT MKFILE / RM / MKDIR | ~50 | Step 11 |
| 13 | tar driver (probe + open + read + dir) | ~60 | Step 3 |
| 14 | romfs driver | ~80 | Step 3 |
| 15 | ISO 9660 driver | ~120 | Step 3 |
| 16 | Minix FS v1 (read path: super + inode + zones + dir) | ~150 | Step 3 |
| 17 | Minix FS v1 (write path: alloc + create + delete) | ~100 | Step 16 |
| 18 | ext2 read-only driver | ~300 | Step 3 |
| 19 | FS-IDENTIFY + MOUNT-INFO + SECTOR-DUMP | ~60 | Step 2 |
| 20 | FAT LFN support | ~100 | Step 8 |
| 21 | FAT12 extension | ~20 | Step 7 |
| 22 | ISO Rock Ridge / Joliet | ~120 | Step 15 |

---

## Design Constraints

**No emulator changes.**  The `Storage` device is already a generic
block device.  All filesystem logic lives in Forth.

**No BIOS changes.**  The six `DISK-*` words are sufficient.  All
sector I/O goes through them.

**VFS is opt-in.**  If `akashic-vfs` is not loaded, the existing
MP64FS code works exactly as before — no regressions for code that
doesn't need multi-filesystem support.

**Read-only drivers are cheaper.**  A read-only driver (tar, romfs,
ISO 9660, ext2) skips all allocation, bitmap, and write-back logic
— roughly half the complexity of a read-write driver.

**One sector-cache per driver context.**  Each mounted filesystem
gets a 512-byte (or 1024/2048 for larger block sizes) cache buffer
in its mount context.  This avoids redundant DMA on sequential
access without requiring a global block cache.  The VFS layer does
not implement a unified buffer cache — that's a future enhancement.

**FAT write support updates both FAT copies.**  Standard practice
for consistency.  We don't implement journaling or fsck — power-loss
tolerance comes from the FAT spec's simple write-both-copies model.

**Mount points are static strings, not path components.**  The VFS
matches mount points by string prefix (`"/sd"`, `"/cd"`, `"/"`).
This is simpler than Linux-style mount namespace manipulation and
sufficient for 4 simultaneous mounts.

**FD pool replaces dictionary allocation.**  The current `OPEN`
allocates descriptors in dictionary space (never freed).  The VFS
FD pool pre-allocates 16 slots.  `FCLOSE` returns slots.  This is
a breaking change for code that stores fd addresses long-term — but
such code is rare and the benefit (no memory leak) justifies it.

**All drivers must implement probe.**  Auto-detection via `MOUNT`
with driver-id 0 is the primary user experience.  Drivers that
can't implement a reliable probe (unlikely — all target formats
have distinctive magic bytes) fall back to explicit driver-id.

---

## Testing Strategy

All tests follow the `local_testing/test_*.py` snapshot pattern
where appropriate.  Python-side tests validate image builders
independently; emulator tests validate the Forth driver via UART
assertion.

### VFS Layer Tests

| Test | Verifies |
|------|----------|
| MOUNT mp64fs → DIR → same output as before | Retrofit correctness |
| OPEN → FREAD → FCLOSE → OPEN reuses fd slot | FD pool reclamation |
| MOUNT auto-detect on MP64FS image | Probe dispatch |
| MOUNT unknown image → error | Probe failure path |
| UMOUNT → fd ops fail | Unmount invalidation |
| 4 simultaneous mounts | Mount table capacity |

### FAT Tests

| Test | Verifies |
|------|----------|
| Python `FATImage`: create FAT16, inject 3 files, verify BPB | Image builder |
| MOUNT fat16 image → DIR lists files | BPB + dir traversal |
| OPEN + FREAD: compare file content to injected bytes | Cluster walk + read |
| Large file spanning multiple clusters | Multi-cluster chain |
| FAT32 image with root dir as cluster chain | FAT32 root handling |
| MKFILE + FWRITE + FCLOSE + re-OPEN + FREAD roundtrip | Write support |
| CD into subdirectory → DIR | Subdirectory traversal |
| RM file → DIR no longer lists it → free space increased | Delete + bitmap |
| File not found → OPEN returns 0 | Error path |
| SFN case insensitivity: "README.TXT" matches "readme.txt" | 8.3 comparison |

### Archive Format Tests

| Test | Verifies |
|------|----------|
| tar: mount → DIR lists files → OPEN → FREAD content correct | tar read |
| tar: probe on non-tar image returns false | Probe specificity |
| romfs: mount → DIR → OPEN → FREAD | romfs read |
| romfs: subdirectory navigation | Directory type handling |

### ISO 9660 Tests

| Test | Verifies |
|------|----------|
| ISO: mount → DIR lists root | PVD + root dir parsing |
| ISO: OPEN file → FREAD content | Extent read |
| ISO: CD into subdir → DIR | Multi-level directory records |

### Minix FS Tests

| Test | Verifies |
|------|----------|
| minixfs: mount → DIR root | Superblock + inode 1 + dir |
| minixfs: OPEN + FREAD regular file | Zone traversal |
| minixfs: file with indirect zones | Indirect block handling |
| minixfs: create file + write + read back | Bitmap alloc + inode create |
| minixfs: delete file → inode freed | Unlink + zone free |
| minixfs: hard link count updates | Link semantics |

### ext2 Tests

| Test | Verifies |
|------|----------|
| ext2: mount → DIR root | Superblock + BGD + inode 2 |
| ext2: OPEN + FREAD file | Block list traversal |
| ext2: file with indirect blocks | Indirect block handling |
| ext2: ext4 image with extents | Extent tree walk |
| ext2: CD into nested dirs | Directory record walking |

### Cross-Driver Tests

| Test | Verifies |
|------|----------|
| Mount mp64fs at "/" + fat at "/sd" simultaneously | Multi-mount |
| OPEN "/sd/readme.txt" → dispatches to FAT driver | Path-based routing |
| FS-IDENTIFY correctly labels each format | Auto-detection |
| MOUNT-INFO lists all mounts | Diagnostics |

---

## Decision Log

| Decision | Rationale | Date |
|----------|-----------|------|
| VFS as Phase 0, not optional | Every FS driver needs dispatch; retrofitting MP64FS first ensures zero regression for existing code | 2026-03-05 |
| FD pool (16 slots) over dictionary allocation | Fixes the existing FCLOSE gap; 16 slots × 72 bytes = 1152 bytes, cheap | 2026-03-05 |
| FAT as first foreign FS | Universal interchange format; highest real-world interop value | 2026-03-05 |
| SFN-first, LFN deferred | SFN is fully functional and interoperable; LFN is cosmetic for most use cases; ~100 lines deferred | 2026-03-05 |
| tar and romfs before ISO 9660 | Simpler (60–80 lines vs 120); immediately useful for Forth source/asset distribution | 2026-03-05 |
| Minix FS before ext2 | Simpler inode model teaches the concepts needed for ext2; also provides write support (ext2 is read-only) | 2026-03-05 |
| ext2 read-only, not read-write | ext2 write requires block group bitmap updates, inode allocation, and careful sequencing; read-only covers the "access Linux data" use case at half the cost | 2026-03-05 |
| ext4 extent support in ext2 driver | Many ext4 volumes are readable as ext2 except for extent-based files; ~40 extra lines for extent tree walk covers the common case | 2026-03-05 |
| One sector-cache per mount, no global cache | Global buffer cache adds significant complexity (LRU, writeback, coherency); per-mount single-sector cache captures most sequential-access benefit at near-zero cost | 2026-03-05 |
| Shell out to mkfs tools for test fixtures | Writing pure-Python ext2/minix image builders is 500+ lines each for questionable value; `mke2fs` and `mkfs.minix` are standard Linux tools available everywhere | 2026-03-05 |
| Mount points as string prefixes | Simpler than inode-based mount namespace; sufficient for 4 mounts; matches the "named drive" mental model natural for a Forth system | 2026-03-05 |
| Future FS candidates documented, not roadmapped | CP/M, littlefs, Amiga FFS etc. are feasible but lower priority; documenting them prevents knowledge loss without committing schedule | 2026-03-05 |
