# akashic-vfs — validated virtual-filesystem contract

`vfs.f` provides an arena-backed VFS core for KDOS. It separates namespace
entries (dentries) from shared file identity and metadata (vnodes), dispatches
filesystem work through a validated binding descriptor, and carries an
explicit KDOS volume attachment when a binding needs block storage.

```forth
REQUIRE utils/fs/vfs.f
```

The module provides `akashic-vfs`. ABI 1 is the only binding ABI: the former
raw ten-XT table is not accepted.

Callers that need exact selector/CWD/FD cleanup plus complete, prefix, ranged,
or callback-streamed reads should use the policy-neutral
[`vfs-access.f` layer](vfs-access.md). Replacement protocols, fixed record
envelopes, and domain stores remain separate higher-level concerns.

The first ext4 implementation slice is the checksummed, read-only
[`akashic-vfs-ext4` binding](drivers/vfs-ext4.md). It is constrained by the
ratified [`akashic-ext4-rw-v1` profile](ext4-compatibility-profile.md) and does
not yet claim completion of that writable profile.

## Quick start

```forth
524288 A-XMEM ARENA-NEW IF -1 THROW THEN CONSTANT my-arena
my-arena VFS-RAM-BINDING 0 VFS-NEW ?DUP IF THROW THEN CONSTANT my-vfs

S" readme.txt" my-vfs VFS-MKFILE DROP
my-vfs VFS-USE

S" readme.txt" VFS-OPEN CONSTANT fd
S" Hello" fd VFS-WRITE DROP
fd VFS-REWIND

CREATE buf 64 ALLOT
buf 64 fd VFS-READ .
fd VFS-CLOSE

0 my-vfs VFS-UNMOUNT ?DUP IF THROW THEN
my-vfs VFS-DESTROY
```

`VFS-RAM-BINDING` needs no volume. A disk binding sets
`VFS-BF-NEEDS-VOLUME` and receives a valid `vol` object:

```forth
arena binding vol VFS-NEW  ( -- vfs ior )
```

## Object model

A public value historically called an “inode” is now a dentry. A dentry owns
one name and one parent and points to a shared vnode. Multiple hard-link
dentries therefore share size, timestamps, binding identity, data, link count,
and open-reference state.

### Dentry (`VFS-INODE-SIZE` = 64)

`VFS-INODE-SIZE` remains as a source-compatibility name for the dentry size.

| Accessor | Offset | Meaning |
|---|---:|---|
| `D.CHILD` | 0 | First child or slab free-list link |
| `D.SIBLING` | 8 | Next sibling |
| `D.PARENT` | 16 | Parent dentry |
| `D.VNODE` | 24 | Shared vnode |
| `D.NAME` | 32 | Refcounted string handle |
| `D.FLAGS` | 40 | Dentry flags |
| `D.COOKIE` | 48 | Binding-private directory cookie |
| `D.OWNER` | 56 | Owning VFS instance (`D.ALIAS` is a retired spelling) |

`VFS-DF-UNLINKED` marks a dentry removed from the namespace but retained by
an open FD. It is reaped after the final close.

### Vnode (`VFS-VNODE-SIZE` = 184)

| Accessor | Meaning |
|---|---|
| `VN.TYPE` | `VFS-T-FILE`, `VFS-T-DIR`, `VFS-T-SYMLINK`, or `VFS-T-SPECIAL` |
| `VN.SIZE-LO`, `VN.SIZE-HI` | Logical size |
| `VN.MODE`, `VN.UID`, `VN.GID`, `VN.RDEV` | POSIX metadata |
| `VN.ATIME`, `VN.MTIME`, `VN.CTIME` | Timestamp seconds |
| `VN.ATIME-NS`, `VN.MTIME-NS`, `VN.CTIME-NS` | Timestamp nanoseconds |
| `VN.NLINK` | Namespace link count |
| `VN.BID` | Stable binding identity |
| `VN.BDATA` | Two binding-private cells |
| `VN.FLAGS` | Dirty/loaded/pinned state |
| `VN.BLOCKS` | Allocated-block count |
| `VN.OPEN-REFS`, `VN.DREFS` | Lifetime references |
| `VN.GEN` | Binding generation |

`VN.RDEV` uses a binding-neutral representation: the unsigned major number is
stored in bits 32–63 and the unsigned minor number in bits 0–31. Filesystem
drivers translate their native device encoding with `VFS-RDEV-MAKE`; consumers
can use `VFS-RDEV-MAJOR` and `VFS-RDEV-MINOR` without knowing that encoding.

Legacy `IN.*` accessors remain usable. Namespace accessors (`IN.CHILD`,
`IN.PARENT`, `IN.SIBLING`, `IN.NAME`) address the dentry; metadata accessors
such as `IN.SIZE-LO`, `IN.MODE`, `IN.BID`, `IN.BDATA`, and `IN.FLAGS`
dereference its vnode.

### File descriptor (`VFS-FD-SIZE` = 64)

| Accessor | Meaning |
|---|---|
| `FD.INODE` | Retained dentry |
| `FD.CUR-LO`, `FD.CUR-HI` | Cursor |
| `FD.FLAGS` | `VFS-FF-READ`, `VFS-FF-WRITE`, `VFS-FF-APPEND` |
| `FD.VFS` | Owning VFS |
| `FD.COOKIE` | Cookie returned by binding `OPEN` |
| `FD.GEN` | Attachment generation captured at open |
| `FD.FREE` | Pool free-list link |

The default pool contains 256 FDs.

## Lifecycle and volume attachment

```forth
VFS-PROBE     ( binding volume -- score ior )
VFS-NEW       ( arena binding volume -- vfs ior )
VFS-UNMOUNT   ( flags vfs -- ior )
VFS-DESTROY   ( vfs -- )
VFS-USE       ( vfs -- )
VFS-CUR       ( -- vfs )
```

`VFS-NEW` validates the descriptor before allocating. A binding must advertise
`MOUNT` and `UNMOUNT`. If it sets `VFS-BF-NEEDS-VOLUME`, `volume` must pass
`VOL-VALID?` and must not pass `VOL-STALE?`.

`VFS-PROBE` is the pre-mount format-selection call. It performs the same
descriptor and supplied-volume validation, refuses an unadvertised `PROBE`
without invoking its XT, and returns a score from 0 through
`VFS-PROBE-MAX` (100). A successful callback outside that range is treated as
corrupt. Probe must inspect only the supplied volume and must not mutate it.

Before mount, the core records:

- `V.VOLUME`: the exact volume object;
- `V.VOL-COOKIE`: `VOL.COOKIE` at attachment;
- `V.MEDIA-GEN`: `VOL.MEDIA-GEN` at attachment.

Every checked operation verifies the required volume, cookie, and media
generation. Drift changes the lifecycle to `VFS-L-STALE`; that state is
terminal and subsequent operations return `VFS-E-STALE`.

Read-only authority is cumulative. `VFS-BF-READ-ONLY` or
`VOL-F-READONLY` sets `VFS-F-RO` on the new VFS even when the other layer is
writable. No binding can use a writable descriptor to weaken a read-only
volume attachment.

Pre-mount capacity failures return `0 VFS-E-NOMEM` and restore the arena bump
pointer to its entry value. A mount callback failure returns the complete,
inspectable VFS plus its ior, but does not publish it as mounted.

Ordinary unmount returns `VFS-E-BUSY` while FDs are open. Pass
`VFS-UNMOUNT-F-FORCE` only when abandoning those handles is intentional. A
successful unmount callback runs once. A callback error restores mounted state
except when stale was returned or latched, in which case stale remains
terminal. Unmount checks the attachment before callback dispatch; drift latches
stale without issuing I/O through a closed or rebound volume.

`VFS-DESTROY` force-unmounts and destroys the arena. It cannot report the
unmount result; callers needing a reportable durability boundary must call
`VFS-SYNC` and `VFS-UNMOUNT` first. Destroying the current VFS also clears
`VFS-CUR`, so no global handle points into the reclaimed arena.

Lifecycle values are `VFS-L-NEW`, `VFS-L-MOUNTED`,
`VFS-L-UNMOUNTING`, `VFS-L-UNMOUNTED`, and `VFS-L-STALE`.

## Structured results

Canonical APIs return a packed VFS ior. Zero means success.

```text
63                       32 31       24 23       16 15          0
+--------------------------+-----------+-----------+-------------+
| backend detail (u32)     | flags u8  | domain u8 | reason u16  |
+--------------------------+-----------+-----------+-------------+
```

```forth
VFS-IOR-MAKE    ( detail flags domain reason -- ior )
VFS-IOR-DETAIL  ( ior -- u32 )
VFS-IOR-FLAGS   ( ior -- u8 )
VFS-IOR-DOMAIN  ( ior -- u8 )
VFS-IOR-REASON  ( ior -- u16 )
```

`VFS-IOR-MAKE` masks every input to its documented width. Disk bindings
translate KDOS block/volume results: the underlying low 32 bits belong in
detail, while domain, reason, and flags use the VFS encoding.

Domains are `VFS-IOR-D-CORE`, `VFS-IOR-D-VOLUME`,
`VFS-IOR-D-BINDING`, and `VFS-IOR-D-FORMAT`. Flags include
`VFS-IOR-F-RETRYABLE`, `VFS-IOR-F-PARTIAL`, `VFS-IOR-F-CORRUPT`,
`VFS-IOR-F-STALE`, and `VFS-IOR-F-READONLY`.

Stable reason constants are:

| Constant | Meaning |
|---|---|
| `VFS-R-INVALID` | Invalid argument or operation |
| `VFS-R-NOENT` | Entry absent |
| `VFS-R-EXISTS` | Entry already exists |
| `VFS-R-NOTDIR`, `VFS-R-ISDIR` | Type mismatch |
| `VFS-R-NOTEMPTY` | Directory not empty |
| `VFS-R-READONLY` | Mutation forbidden |
| `VFS-R-NOSPC`, `VFS-R-NOMEM` | Storage or memory exhaustion |
| `VFS-R-IO`, `VFS-R-CORRUPT` | I/O or integrity failure |
| `VFS-R-UNSUPPORTED` | Capability absent |
| `VFS-R-CONFLICT` | Incompatible replacement |
| `VFS-R-STALE` | Attachment no longer current |
| `VFS-R-BUSY` | Lifecycle/resource busy |
| `VFS-R-OVERFLOW` | Range or representability failure |
| `VFS-R-BADF` | Invalid FD/access mode |
| `VFS-R-NAMETOOLONG` | Name exceeds contract |
| `VFS-R-LOOP` | Link/path loop |
| `VFS-R-XDEV` | Cross-filesystem operation |
| `VFS-R-NOVOLUME` | Required volume absent |

Prebuilt core iors use the `VFS-E-*` spelling, for example
`VFS-E-NOENT`, `VFS-E-UNSUPPORTED`, and `VFS-E-STALE`.

## Paths and file I/O

### Canonical checked API

```forth
VFS-RESOLVE?          ( path-a path-u vfs -- inode ior )
VFS-RESOLVE-POLICY?   ( path-a path-u policy vfs -- inode ior )
VFS-LOOKUP            ( name-a name-u parent vfs -- inode ior )
VFS-OPEN?             ( path-a path-u flags vfs -- fd ior )
VFS-CLOSE?            ( fd -- ior )
VFS-READ?             ( buf len fd -- actual ior )
VFS-WRITE?            ( buf len fd -- actual ior )
VFS-SEEK?             ( position fd -- ior )
VFS-CD?               ( path-a path-u vfs -- ior )
VFS-TRUNCATE          ( size fd -- ior )
VFS-FSYNC             ( fd -- ior )
```

`VFS-RESOLVE?` checks lifecycle and attachment before returning even a cached
entry or root. It preserves errors from lazy `READDIR`, returns
`VFS-E-NOTDIR` when an intermediate component is not a directory, and returns
`VFS-E-NOENT` only when traversal completed without finding the entry.
Absolute paths start at root, relative paths at cwd, and `.`/`..` have their
usual meaning. A nonempty path requires a non-null, non-wrapping memory span;
an empty path intentionally resolves to cwd. Paths and expanded link targets
are bounded by `VFS-PATH-MAX` (4096 bytes).

`VFS-RESOLVE?` follows both intermediate and terminal symbolic links. Relative
targets start at the directory containing the link, absolute targets restart
at root, and the unconsumed path suffix is then resolved against that target.
Traversal follows at most `VFS-SYMLINK-MAX` (40) links and returns
`VFS-E-LOOP` at the bound. `READLINK` failures are preserved; an empty target
resolves as `VFS-E-NOENT`, and an expansion beyond `VFS-PATH-MAX` returns
`VFS-E-NAMETOOLONG`.

`VFS-RESOLVE-POLICY?` makes terminal-link treatment explicit. Pass
`VFS-RP-FOLLOW-FINAL` for the default behavior or
`VFS-RP-NOFOLLOW-FINAL` to return the terminal symlink dentry itself.
Intermediate links are followed under both policies. `OPEN` and `CD` follow
their terminal link; unlink, create-existence checks, and `VFS-STAT` select
no-follow so they continue to address the named namespace object.

On a cached-name miss, resolution uses targeted `VFS-LOOKUP` when the binding
advertises it; otherwise it loads the complete directory through `READDIR`.
`LOOKUP` returns `VFS-E-NOENT` for an absent name and preserves every other
binding error. A cached hit never invokes the callback.

`VFS-READ?` and `VFS-WRITE?` return progress and error together. Legal partial
progress advances the cursor even when the same call returns a nonzero ior.
Bindings must set `VFS-IOR-F-PARTIAL` when applicable. The core rejects a
negative or overlong `actual` as corruption.

`VFS-OPEN?` catches a binding `OPEN` exception and returns its exact nonzero
code only after returning the provisional FD to the pool; no descriptor or
open reference is published. `VFS-CLOSE?` likewise catches a binding
`RELEASE` exception, retires the open reference, returns the FD to the pool,
and then reports the exact code. A release exception may have happened after
the backend took effect, so callers must not retry the same FD. The scoped
access layer applies that exact-once rule across selector and CWD restoration.

Positions and logical sizes are currently restricted to nonnegative one-cell
values (`0 .. 2^63-1`). `VFS-SEEK?`, truncate, checked I/O, and append reject a
high-bit value or nonzero high cursor/size cell before dispatch. Append selects
the vnode's current EOF under the VFS guard.

`VFS-READ-EXACT` and `VFS-WRITE-EXACT` repeat checked calls until the requested
length completes. Zero progress before completion returns `VFS-E-IO`; a
binding error is returned unchanged after any legal progress.

### Source-compatible conveniences

```forth
VFS-RESOLVE      ( path-a path-u vfs -- inode|0 )
VFS-OPEN         ( path-a path-u -- fd|0 )
VFS-CLOSE        ( fd -- )
VFS-READ         ( buf len fd -- actual )
VFS-WRITE        ( buf len fd -- actual )
VFS-SEEK         ( position fd -- )
VFS-CD           ( path-a path-u vfs -- 0|-1 )
```

These retain older stack shapes. `VFS-RESOLVE` uses the same terminal-follow
policy as `VFS-RESOLVE?`. The I/O/seek/close forms throw a structured ior.
`VFS-OPEN` requests read access only when the current VFS is read-only, and
read/write access otherwise. New code should use the checked forms when it
must inspect the error class.

Cursor helpers are `VFS-REWIND`, `VFS-TELL`, and `VFS-SIZE`.

## Namespace operations

```forth
VFS-MKFILE?    ( name-a name-u vfs -- inode ior )
VFS-MKDIR      ( name-a name-u vfs -- ior )
VFS-CREATE     ( path-a path-u vfs -- inode|0 )
VFS-LINK       ( name-a name-u target parent vfs -- inode ior )
VFS-SYMLINK    ( target-a target-u name-a name-u parent vfs -- inode ior )
VFS-RENAME-AT  ( new-a new-u inode new-parent flags vfs -- ior )
VFS-RENAME     ( new-a new-u inode vfs -- ior )
VFS-RM         ( path-a path-u vfs -- ior )
```

Names are nonempty, at most 255 bytes, contain neither `/` nor NUL, and cannot
be exactly `.` or `..`. Their memory span must be non-null and non-wrapping.
Leading or trailing dots in other names are legal.

`VFS-LINK` creates a second dentry for the target vnode. Directories cannot be
hard-linked. Removing one name decrements `VN.NLINK` without invalidating other
names or open FDs. Every dentry carries an owner tag; link, rename, metadata,
and cache helpers reject a dentry from another VFS with `VFS-E-XDEV` before
binding dispatch.

`VFS-RENAME-AT` supports cross-directory moves, replacement, and
`VFS-RN-NOREPLACE`. The binding operation completes before the cached tree is
published. Replacing an open destination unlinks its dentry but retains the
old vnode until close. Renaming onto a distinct hard-link dentry for the same
vnode is a no-op that retains both names and the link count. Directory cycles,
nonempty directory replacement, and file/directory type conflicts are
rejected.

`VFS-SYMLINK` is capability-gated. ABI 1 exposes the operation for ext4-class
bindings, but the RAM binding intentionally does not advertise it. Bindings
that publish symlink dentries must advertise `VFS-CAP-READLINK` for traversal;
otherwise resolving through one returns `VFS-E-UNSUPPORTED`. To inspect a
link without following it, resolve with `VFS-RP-NOFOLLOW-FINAL` and pass the
returned dentry to `VFS-READLINK`.

`VFS-DIR` lists cwd and `VFS-STAT` prints cached metadata.

## Metadata, symlinks, xattrs, and statfs

```forth
VFS-GETATTR      ( inode vfs -- ior )
VFS-SETATTR      ( attr-request inode vfs -- ior )
VFS-READLINK     ( buf capacity inode vfs -- actual ior )
VFS-LISTXATTR    ( buf capacity inode vfs -- actual ior )
VFS-GETXATTR     ( name-a name-u buf capacity inode vfs -- actual ior )
VFS-SETXATTR     ( name-a name-u value-a value-u flags inode vfs -- ior )
VFS-REMOVEXATTR  ( name-a name-u inode vfs -- ior )
VFS-STATFS       ( statfs-buffer bytes vfs -- ior )
```

Every word checks readiness and its capability before invoking an XT.
Mutating forms also enforce read-only policy. An absent capability returns
`VFS-E-UNSUPPORTED` without invoking a populated-but-unadvertised slot.

### SETATTR request (`VFS-SETATTR-REQ-SIZE` = 88)

| Accessor | Meaning |
|---|---|
| `VA.MASK` | Selected fields |
| `VA.MODE`, `VA.UID`, `VA.GID` | Mode and ownership |
| `VA.ATIME`, `VA.ATIME-NS` | Access time |
| `VA.MTIME`, `VA.MTIME-NS` | Modification time |
| `VA.CTIME`, `VA.CTIME-NS` | Change time |
| `VA.RDEV` | Special-device identity |

Mask bits are `VFS-SA-MODE`, `VFS-SA-UID`, `VFS-SA-GID`,
`VFS-SA-ATIME`, `VFS-SA-MTIME`, `VFS-SA-CTIME`, and `VFS-SA-RDEV`.
The binding commits the request first; only after callback success does the
core publish selected values into the shared vnode. A selected zero is an
update, while unselected fields remain unchanged. Size changes use
`VFS-TRUNCATE` rather than SETATTR.

Xattr names are 1–255 bytes. SET flags are zero, `VFS-XATTR-CREATE`, or
`VFS-XATTR-REPLACE`; CREATE and REPLACE cannot be combined. A null buffer with
zero capacity is a size query for READLINK/LISTXATTR/GETXATTR, so `actual` may
exceed zero in that case. With a nonzero capacity, `actual` cannot exceed it.

### STATFS result (`VFS-STATFS-SIZE` = 96)

The stable fields are `VSF.BSIZE`, `VSF.FRSIZE`, `VSF.BLOCKS`, `VSF.BFREE`,
`VSF.BAVAIL`, `VSF.FILES`, `VSF.FFREE`, `VSF.NAMEMAX`, `VSF.FLAGS`,
`VSF.FSID-LO`, and `VSF.FSID-HI`. `VSF.RESERVED` is zero for ABI 1.

## Sync and eviction

```forth
VFS-SYNC       ( vfs -- ior )
VFS-FSYNC      ( fd -- ior )
VFS-SET-HWM    ( n vfs -- )
```

`VFS-SYNC` invokes the binding's `SYNCFS` exactly once. The binding owns data,
metadata, journal, and flush ordering. Only after success does the generic
cache clear dirty observations. `VFS-FSYNC` delegates one vnode durability
operation and clears that vnode's dirty flag only on success. Read-only policy
does not forbid sync of state dirtied before the policy change.

The dentry slab grows in 64-slot pages. Growth uses checked allocation; an
exhausted arena returns `VFS-E-NOMEM` without publishing a partial namespace
mutation. Each new page retains the older-page link so sync and eviction walk
the complete cache. Eviction removes eligible cached dentries without changing backend
link counts. Automatic per-dentry eviction is enabled only for bindings with
targeted `LOOKUP`; a `READDIR`-only binding keeps its complete enumeration.
RAM-created vnodes are pinned because RAM `READDIR` cannot reconstruct them.

Bindings populate lookup/readdir results through:

```forth
VFS-CACHE-DENTRY
  ( name-a name-u type bid generation parent vfs -- dentry ior )
VFS-CACHE-DROP
  ( dentry vfs -- ior )
```

`VFS-CACHE-DENTRY` keys vnode identity by the nonzero `BID` plus generation.
Loading a second on-disk hard-link name therefore attaches another dentry to
the existing vnode rather than duplicating metadata. The helper does not
change persistent `VN.NLINK`; the binding publishes the authoritative link
count from disk. `VFS-CACHE-DROP` removes only the cache reference and returns
busy for an open dentry. Once the last dentry and open reference disappears,
the vnode is reclaimable even while its on-disk link count is nonzero.

## Binding ABI 1

### Descriptor (`VFS-BINDING-DESC-SIZE` = 80)

| Accessor | Meaning |
|---|---|
| `VB.MAGIC` | `VFS-BINDING-MAGIC` (`VFSBND01`) |
| `VB.MAJOR`, `VB.MINOR` | ABI version 1.0 |
| `VB.DESC-SIZE` | Descriptor bytes, at least 80 |
| `VB.OPS-SIZE` | Operation prefix bytes, at least `VFS-OPS-SIZE` |
| `VB.CAPS` | Operation and semantic capabilities |
| `VB.FLAGS` | Binding policy flags |
| `VB.OPS` | 27-cell operation table |
| `VB.NAME`, `VB.NAME-LEN` | Optional diagnostic name |

Treat shared descriptors and operation tables as immutable. Tests or fault
injectors must copy both and repoint `VB.OPS` before modification.

`VFS-BINDING-VALID?` checks magic, major, minimum sizes, nonzero ops pointer,
and every advertised operation bit. If an operation is advertised, its XT
must be nonzero. A nonzero XT without its cap remains unreachable and returns
unsupported through public dispatch. It also rejects contradictory semantic
claims: rename semantics require `RENAME`, data-only fsync requires `FSYNC`,
stable IDs require `GETATTR`, and stable handles require both stable IDs and
`GETATTR`.

The ABI major is an exact compatibility boundary. A different major is
rejected. Minor revisions within major 1 may add descriptor or operation-table
suffixes while preserving the ABI-1 prefix; older cores accept that prefix by
using the minimum sizes and capability bits and ignore additions they do not
understand. This is forward negotiation, not a second legacy runtime ABI.

Binding flags are `VFS-BF-NEEDS-VOLUME`, `VFS-BF-CASE-INSENSITIVE`,
`VFS-BF-READ-ONLY`, and `VFS-BF-STABLE-IDS`.

ABI 1 cache matching is byte-sensitive. `VFS-BF-CASE-INSENSITIVE` is defined
for a future pinned folding contract but is rejected by descriptor validation
today; a binding must not advertise it.

### Operation table

The operation cap is `1 << slot` and uses the corresponding `VFS-CAP-*` name.

| Slot | Operation | Callback stack effect |
|---:|---|---|
| 0 | `PROBE` | `( volume -- score ior )` |
| 1 | `MOUNT` | `( vfs -- ior )` |
| 2 | `UNMOUNT` | `( flags vfs -- ior )` |
| 3 | `LOOKUP` | `( name-a name-u parent vfs -- dentry ior )` |
| 4 | `READDIR` | `( directory vfs -- ior )` |
| 5 | `OPEN` | `( inode vfs -- cookie ior )` |
| 6 | `RELEASE` | `( cookie inode vfs -- ior )` |
| 7 | `READ` | `( buf len offset inode vfs -- actual ior )` |
| 8 | `WRITE` | `( buf len offset inode vfs -- actual ior )` |
| 9 | `CREATE` | `( inode vfs -- ior )` |
| 10 | `MKDIR` | `( inode vfs -- ior )` |
| 11 | `UNLINK` | `( inode vfs -- ior )` |
| 12 | `RMDIR` | `( inode vfs -- ior )` |
| 13 | `RENAME` | `( new-a new-u inode new-parent victim flags vfs -- ior )` |
| 14 | `TRUNCATE` | `( inode vfs -- ior )` |
| 15 | `GETATTR` | `( inode vfs -- ior )` |
| 16 | `SETATTR` | `( attr-request inode vfs -- ior )` |
| 17 | `LINK` | `( new-dentry target vfs -- ior )` |
| 18 | `SYMLINK` | `( target-a target-u new-dentry vfs -- ior )` |
| 19 | `READLINK` | `( buf capacity inode vfs -- actual ior )` |
| 20 | `SYNCFS` | `( vfs -- ior )` |
| 21 | `FSYNC` | `( inode vfs -- ior )` |
| 22 | `LISTXATTR` | `( buf capacity inode vfs -- actual ior )` |
| 23 | `GETXATTR` | `( name-a name-u buf capacity inode vfs -- actual ior )` |
| 24 | `SETXATTR` | `( name-a name-u value-a value-u flags inode vfs -- ior )` |
| 25 | `REMOVEXATTR` | `( name-a name-u inode vfs -- ior )` |
| 26 | `STATFS` | `( statfs-buffer bytes vfs -- ior )` |

`PROBE` returns a score from 0 through 100 and performs no mutation. `LOOKUP`
publishes a successful result with `VFS-CACHE-DENTRY`; the public dispatcher
verifies that its vnode, parent, and exact byte name match the request.

`READDIR` must not publish partial cache state as complete. The core sets
`VFS-IF-CHILDREN` only when the callback returns zero; an error remains
retryable. Mutation callbacks must either complete their backend transaction
or return an error before the core publishes the cache change.

`TRUNCATE` sees the requested logical size already staged in the vnode; the
core restores the prior size if the callback fails. SETATTR instead receives a
separate request and is published only after success.

Semantic caps are `VFS-CAP-ATOMIC-RENAME`,
`VFS-CAP-CROSSDIR-RENAME`, `VFS-CAP-RENAME-REPLACE`,
`VFS-CAP-SPARSE`, `VFS-CAP-DATA-ONLY-FSYNC`, and
`VFS-CAP-STABLE-HANDLES`. For an ext4 binding, `VN.BID` should be the inode
number and `VN.GEN` the inode generation so cache reload and hard-link aliases
retain one shared vnode identity.

## RAM binding

`VFS-RAM-BINDING` and `VFS-RAM-OPS` are defined by `vfs.f`. RAM files keep a
buffer pointer and capacity in `IN.BDATA`. Growth is copy-on-grow: allocation
and copying complete before the new pointer is published. Sparse gaps and
newly exposed truncate bytes are zeroed.

The RAM binding supports mount/unmount, readdir, open/release, read/write,
create/mkdir, unlink/rmdir, rename, truncate, getattr, hard link, syncfs, and
fsync. It truthfully leaves lookup, setattr, symlink/readlink, xattrs, and
statfs unadvertised; public calls return `VFS-E-UNSUPPORTED`.

## Concurrency

When `GUARDED` is defined and true, public words are wrapped by a recursive VFS
guard. `VFS-TRANSACTION ( xt -- ... )` holds that exclusion region across a
multi-call operation and preserves results/throws. Without `GUARDED`, it is a
plain `EXECUTE` compatibility fallback.

Bindings must preserve their own internal lock order. A binding must not hold
a cache/vnode lock while waiting on the controller in an order that can invert
the VFS guard or volume/device serialization.
