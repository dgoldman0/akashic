# akashic-vfs — Abstract Virtual Filesystem for KDOS / Megapad-64

An arena-backed virtual filesystem data structure.  Each VFS instance
is a self-contained, first-class value on the Forth stack — a tree of
typed inodes with a file-descriptor pool, path resolver, and string
pool.  The VFS analogue of the DOM.

```forth
REQUIRE utils/fs/vfs.f
```

`PROVIDED akashic-vfs` — safe to include multiple times.

---

## Table of Contents

- [Design Principles](#design-principles)
- [Quick Start](#quick-start)
- [Instance Lifecycle](#instance-lifecycle)
- [Inode Layout](#inode-layout)
- [File Descriptor Layout](#file-descriptor-layout)
- [Path Resolution](#path-resolution)
- [File I/O](#file-io)
- [Directory Operations](#directory-operations)
- [Sync & Eviction](#sync--eviction)
- [Binding Contract](#binding-contract)
- [Ramdisk Binding](#ramdisk-binding)
- [Constants](#constants)
- [Quick Reference](#quick-reference)

---

## Design Principles

| Principle | Detail |
|---|---|
| **First-class value** | A VFS instance is a single cell — an address.  Pass it on the stack, store in a VARIABLE, hand to any word. |
| **Arena-backed** | All allocations (descriptor, slabs, FDs, strings, file buffers) come from a single KDOS arena.  `VFS-DESTROY` frees everything in one call. |
| **Binding-dispatched** | The VFS knows nothing about sectors, DMA, or on-disk formats.  Actual byte transfer is delegated to a vtable of 10 execution tokens. |
| **Lazy tree** | Directories are populated on first descent, not at mount time.  A binding for a 2 TiB volume materialises only the directories actually traversed. |
| **No fixed limits** | Inode count, children per directory, and path depth are bounded only by arena capacity.  Slab pages chain on demand. |
| **Concurrent-safe** | Optional guard section wraps all public words in a mutex when `GUARDED` is defined. |

---

## Quick Start

```forth
\ Create a 512 KB ramdisk VFS
524288 A-XMEM ARENA-NEW  IF -1 THROW THEN  CONSTANT my-arena
my-arena VFS-RAM-VTABLE VFS-NEW  CONSTANT my-vfs

\ Create files and directories
S" readme.txt" my-vfs VFS-MKFILE DROP
S" src"        my-vfs VFS-MKDIR  DROP

\ Write to a file
my-vfs VFS-USE
S" readme.txt" VFS-OPEN  CONSTANT fd
S" Hello, world!" DROP 13  fd VFS-WRITE DROP
fd VFS-REWIND
CREATE buf 256 ALLOT
buf 256 fd VFS-READ  ( actual-bytes )
fd VFS-CLOSE

\ Navigate
S" src" my-vfs VFS-CD DROP
my-vfs VFS-DIR

\ Tear down
my-vfs VFS-DESTROY
```

---

## Instance Lifecycle

### VFS-NEW
```forth
VFS-NEW  ( arena vtable -- vfs )
```
Carve a VFS instance from `arena` using `vtable` as the binding
dispatch table.  Allocates descriptor, initial slab page, FD pool,
string pool, and root directory inode.  Pass `VFS-RAM-VTABLE` for
a pure ramdisk.

### VFS-DESTROY
```forth
VFS-DESTROY  ( vfs -- )
```
Flush dirty state via the binding's teardown xt, then destroy the
backing arena.  All inodes, FDs, strings, and file buffers are
reclaimed in bulk.

### VFS-USE / VFS-CUR
```forth
VFS-USE  ( vfs -- )     \ set as current context
VFS-CUR  ( -- vfs )     \ read current context
```
Implicit-context words (`VFS-OPEN`, `VFS-DIR`, etc.) operate on the
instance set by `VFS-USE`.  Explicit-context variants take `vfs` on
the stack.

---

## Inode Layout

Each inode is 112 bytes (14 cells):

| Offset | Field | Notes |
|--------|-------|-------|
| +0 | first-child / next-free | Union: tree link or free-list chain |
| +8 | type | `VFS-T-FILE` (1), `VFS-T-DIR` (2), `VFS-T-SYMLINK` (3), `VFS-T-SPECIAL` (4) |
| +16 | size (2 cells) | u128 file size |
| +32 | mode | Permission / attribute bits |
| +40 | mtime | Modification timestamp |
| +48 | ctime | Creation timestamp |
| +56 | parent | Inode pointer |
| +64 | next-sibling | Singly-linked child list |
| +72 | name-handle | String pool handle |
| +80 | binding-id | Stable on-disk identity (survives eviction) |
| +88 | binding-data (2 cells) | Binding-private storage |
| +104 | flags | `VFS-IF-DIRTY`, `VFS-IF-CHILDREN`, `VFS-IF-PINNED`, `VFS-IF-EVICTABLE` |

Field accessors: `IN.TYPE`, `IN.SIZE-LO`, `IN.SIZE-HI`, `IN.MODE`,
`IN.MTIME`, `IN.CTIME`, `IN.PARENT`, `IN.SIBLING`, `IN.NAME`,
`IN.BID`, `IN.BDATA`, `IN.FLAGS`.

Inodes are allocated from chained **slab pages**.  Each page holds
64 inodes + a header cell linking to the next page.  Growth is
automatic when the free-list empties.

---

## File Descriptor Layout

Each FD is 48 bytes (6 cells):

| Offset | Field | Notes |
|--------|-------|-------|
| +0 | inode | Pointer to referenced inode |
| +8 | cursor (2 cells) | u128 byte offset |
| +24 | flags | `VFS-FF-READ`, `VFS-FF-WRITE`, `VFS-FF-APPEND` |
| +32 | vfs | Back-pointer to owning VFS |
| +40 | next-free | Free-list chain |

Default pool: 256 slots (12 KB).

---

## Path Resolution

### VFS-RESOLVE
```forth
VFS-RESOLVE  ( c-addr u vfs -- inode | 0 )
```
Resolve a path string to an inode.  Paths starting with `/` begin
at root; otherwise at cwd.  Components are `/`-delimited.  `.` =
stay, `..` = parent.  Returns 0 if not found.

The resolver is iterative (not recursive) with no fixed depth limit.
Directories are lazily populated via the binding's `readdir` xt on
first descent.

---

## File I/O

### VFS-OPEN
```forth
VFS-OPEN  ( c-addr u -- fd | 0 )
```
Resolve path in current VFS, allocate an FD.  Returns 0 if the path
does not resolve.  Uses `VFS-CUR`.

### VFS-CLOSE
```forth
VFS-CLOSE  ( fd -- )
```
Release the FD back to the pool.

### VFS-READ
```forth
VFS-READ  ( buf len fd -- actual )
```
Read up to `len` bytes at the cursor position into `buf`.  Advances
cursor by `actual`.  Dispatches through the binding's `read` xt.

### VFS-WRITE
```forth
VFS-WRITE  ( buf len fd -- actual )
```
Write `len` bytes from `buf` at the cursor position.  Advances cursor.
Updates inode size if the write extends the file.

### VFS-SEEK
```forth
VFS-SEEK  ( pos fd -- )
```
Set the cursor to absolute position `pos`.

### VFS-REWIND
```forth
VFS-REWIND  ( fd -- )
```
Reset cursor to 0.

### VFS-TELL
```forth
VFS-TELL  ( fd -- u )
```
Return current cursor position.

### VFS-SIZE
```forth
VFS-SIZE  ( fd -- u )
```
Return the file size from the FD's inode.

---

## Directory Operations

### VFS-MKFILE
```forth
VFS-MKFILE  ( c-addr u vfs -- inode )
```
Create an empty file in the current working directory.

### VFS-MKDIR
```forth
VFS-MKDIR  ( c-addr u vfs -- inode )
```
Create a subdirectory in the current working directory.

### VFS-RM
```forth
VFS-RM  ( c-addr u vfs -- ior )
```
Remove a file or empty directory.  Returns 0 on success, -1 on error
(not found, non-empty directory, root).

### VFS-DIR
```forth
VFS-DIR  ( vfs -- )
```
List the contents of the current working directory.  Prints name,
type, and size for each entry.

### VFS-CD
```forth
VFS-CD  ( c-addr u vfs -- ior )
```
Change the working directory.  Returns 0 on success, -1 if not found
or not a directory.

### VFS-STAT
```forth
VFS-STAT  ( c-addr u vfs -- )
```
Print metadata for the named path (type, size, timestamps).

---

## Sync & Eviction

### VFS-SYNC
```forth
VFS-SYNC  ( vfs -- ior )
```
Walk all slab pages and call the binding's `sync` xt for every dirty
inode.  Returns 0 on success.

### VFS-SET-HWM
```forth
VFS-SET-HWM  ( n vfs -- )
```
Set the inode high-water mark.  When `inode-count` exceeds this
threshold, `VFS-RESOLVE` and `VFS-OPEN` trigger automatic eviction
of unreferenced inodes.

---

## Binding Contract

A binding is a vtable of 10 execution tokens passed to `VFS-NEW`:

| Index | Signature | Function |
|-------|-----------|----------|
| 0 | `( sector-0-buf vfs -- flag )` | **probe** — recognise format |
| 1 | `( vfs -- ior )` | **init** — read superblock, populate ctx |
| 2 | `( vfs -- )` | **teardown** — flush, free ctx |
| 3 | `( buf len off inode vfs -- actual )` | **read** |
| 4 | `( buf len off inode vfs -- actual )` | **write** |
| 5 | `( inode vfs -- )` | **readdir** — populate children |
| 6 | `( inode vfs -- ior )` | **sync** — write back dirty inode |
| 7 | `( inode vfs -- ior )` | **create** — allocate on-disk structures |
| 8 | `( inode vfs -- ior )` | **delete** — free on-disk structures |
| 9 | `( inode vfs -- ior )` | **truncate** — resize data extents |

---

## Ramdisk Binding

`VFS-RAM-VTABLE` is provided by vfs.f itself.  `read` and `write`
copy bytes from/to an arena-allocated content buffer stored in
`binding-data`.  All other xts are no-ops.  No external dependency.

---

## Constants

| Name | Value | Purpose |
|------|-------|---------|
| `VFS-INODE-SIZE` | 112 | Bytes per inode |
| `VFS-FD-SIZE` | 48 | Bytes per file descriptor |
| `VFS-VT-SIZE` | 80 | Bytes per vtable (10 cells) |
| `VFS-DESC-SIZE` | 128 | VFS descriptor size |
| `_VFS-FD-DEFAULT` | 256 | Default FD pool slots |
| `_VFS-SLAB-SLOTS` | 64 | Inodes per slab page |
| `VFS-T-FILE` | 1 | File type tag |
| `VFS-T-DIR` | 2 | Directory type tag |
| `VFS-T-SYMLINK` | 3 | Symlink type tag |
| `VFS-T-SPECIAL` | 4 | Special node type tag |
| `VFS-IF-DIRTY` | 1 | Inode dirty flag |
| `VFS-IF-CHILDREN` | 2 | Children loaded flag |
| `VFS-IF-PINNED` | 4 | Pinned (no eviction) flag |
| `VFS-IF-EVICTABLE` | 8 | Evictable flag |
| `VFS-FF-READ` | 1 | FD read flag |
| `VFS-FF-WRITE` | 2 | FD write flag |
| `VFS-FF-APPEND` | 4 | FD append flag |

---

## Quick Reference

| Word | Stack Effect | Purpose |
|------|-------------|---------|
| `VFS-NEW` | `( arena vtable -- vfs )` | Create instance |
| `VFS-DESTROY` | `( vfs -- )` | Tear down |
| `VFS-USE` | `( vfs -- )` | Set current context |
| `VFS-CUR` | `( -- vfs )` | Get current context |
| `VFS-RESOLVE` | `( c-addr u vfs -- inode\|0 )` | Path → inode |
| `VFS-OPEN` | `( c-addr u -- fd\|0 )` | Open file |
| `VFS-CLOSE` | `( fd -- )` | Close file |
| `VFS-READ` | `( buf len fd -- actual )` | Read bytes |
| `VFS-WRITE` | `( buf len fd -- actual )` | Write bytes |
| `VFS-SEEK` | `( pos fd -- )` | Set cursor |
| `VFS-REWIND` | `( fd -- )` | Cursor → 0 |
| `VFS-TELL` | `( fd -- u )` | Get cursor |
| `VFS-SIZE` | `( fd -- u )` | Get file size |
| `VFS-MKFILE` | `( c-addr u vfs -- inode )` | Create file |
| `VFS-MKDIR` | `( c-addr u vfs -- inode )` | Create directory |
| `VFS-RM` | `( c-addr u vfs -- ior )` | Remove entry |
| `VFS-DIR` | `( vfs -- )` | List cwd |
| `VFS-CD` | `( c-addr u vfs -- ior )` | Change directory |
| `VFS-STAT` | `( c-addr u vfs -- )` | Print metadata |
| `VFS-SYNC` | `( vfs -- ior )` | Flush dirty inodes |
| `VFS-SET-HWM` | `( n vfs -- )` | Set eviction threshold |
