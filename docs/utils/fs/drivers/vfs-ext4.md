# akashic-vfs-ext4 — checksummed read-only ext4 binding

This VFS ABI 1 binding reads filesystems in the pinned
`akashic-ext4-rw-v1` profile from one explicit KDOS volume. It also implements
a bounded mount-time recovery slice for an internal checksum-v3 JBD2 journal.
It never uses the ambient filesystem volume: reads and the narrowly scoped
recovery writes go through checked volume operations relative to the supplied
`VOL-RAW` or `VOL-SLICE` object. The published binding remains read-only and
has no user-visible mutation fallback.

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
- reflected raw CRC32C for the primary superblock and its UUID-derived seed,
  except for the narrowly authenticated torn-clear state described below;
- the pinned 1/2/4 KiB geometry, 64-byte descriptors, 128/256-byte inode
  forms, flex size, feature policy, admitted clean/recovery state, and all
  volume bounds;
- every primary group descriptor and every initialized block/inode bitmap
  checksum, while honoring the admitted uninitialized-group flags;
- every sparse-super backup copy and its invariant geometry, features, UUID,
  group number, and checksum, plus every backup GDT descriptor CRC and
  immutable metadata location;
- allocation and checksum of each consumed inode;
- the internal JBD2 journal superblock, size-derived inode map, and matching
  UUID. The inode size must be a nonzero whole number of filesystem blocks,
  fit JBD2's 32-bit `s_maxlen`, and not exceed the filesystem block count.
  Mount allocates an exact map plus a half-full power-of-two uniqueness table
  from the caller's arena; arena exhaustion returns `VFS-E-NOMEM` rather than
  imposing a journal-size constant. Every mount materializes the complete
  extent or legacy map in one EOF-bounded tree walk and rejects holes,
  mappings beyond EOF, out-of-range or aliased data blocks, and aliases
  between journal data and its own extent/indirect metadata. A separately
  arena-sized ownership hash also prevents replay home tags from targeting
  those map-metadata blocks; and
- every clean orphan-file block, including its per-block CRC32C tail (the
  bounded reader currently admits one through 4096 blocks).

The driver contains its own reflected CRC32C implementation. Akashic's public
`CRC32C` word is deliberately MSB-first and is not interchangeable with the
ext4 checksum contract.

Known refused feature bits return format-domain `VFS-R-UNSUPPORTED` with
`EXT4-D-FEATURE`. `ORPHAN_PRESENT`, a nonzero legacy orphan chain, a dirty
state without `RECOVER`, or a recovery state outside the implemented JBD2
slice returns a stable refusal. Checksum and structural failures return
format-domain `VFS-R-CORRUPT`. No such failure can leave a mounted or ready
object.

## Bounded mount recovery

The implemented recovery slice admits an internal journal with the exact
`64bit | checksum_v3` incompatibility mask (`0x12`) and JBD2 CRC32C type 4.
It validates the complete journal inode map, descriptor blocks, 64-bit tags,
tagged payloads, escaped payload handling, commit blocks, sequence progression,
and checksums in a non-mutating pass. It then replays only the committed prefix
in a second pass. With an ordinary usable primary, the immutable physical map
used by both passes is populated after the JBD2 geometry is authenticated,
using workspace derived from the journal inode length and bounded by the VFS
arena. Torn-primary bootstrap must materialize that inode-derived map first to
read the one named anchor; the filesystem bound, 32-bit length bound, complete
inode-tree validation, and metadata ownership checks still precede that read.
Tree validation rejects nonzero mappings beyond the inode length, so neither
validation nor materialization can be driven through an attached tree past
journal EOF. The one-pass mapper does not revalidate an entire extent
allocation range once per logical block. A structurally valid
incomplete tail identified by the next
header or sequence discontinuity is discarded. Preflight also treats a
matching-sequence `SUPER_V2` header as the known prefix-torn anchor boundary
only when the complete block passes the anchor checksum, geometry, witness,
and self-location checks; replay never admits it as a transaction record. A
checksum-damaged descriptor, payload, or commit is currently refused rather
than classified as a torn tail. Revoke records and orphan recovery are not yet
admitted.

Recovery requires a physically writable, flush-capable volume. Home writes are
flushed and the resulting filesystem is strictly revalidated before journal
authority changes. At the first noncommitted journal slot, the driver first
writes and flushes the complete intended reset image with byte zero invalid.
It then restores byte zero, writes and flushes the valid recovery anchor, resets
the primary journal superblock and flushes again, and finally clears ext4
`RECOVER` and flushes the primary ext4 superblock. The preseed and valid anchor
differ in only byte zero, so a prefix tear cannot combine a new JBD2 header
with stale cursor contents. Once the ext4 clear is durable, the driver removes
the private witness from journal block 0, flushes, zeros the anchor slot, and
flushes once more. Failed recovery leaves the VFS in `VFS-L-NEW`; a later mount
can retry idempotently when the required witness survived.

The anchor uses JBD2 superblock padding at offsets `0x5c..0x6f` for an `AKR1`
marker, the intended ext4-superblock checksum and complement, and the anchor
logical block and complement. The ordinary JBD2 `s_head` field at `0x58` is
preserved as a standard field and set to that first-unused slot. Both the
anchor and transitional primary copy carry valid JBD2 superblock CRCs. A torn
primary may select only the exact anchor named by an intact marker, complement,
and `s_head` tuple; the driver never scans for arbitrary historical anchors.
Before mutating any intact-witness state, it also validates that exact anchor
and requires the checksummed 1024-byte JBD2 superblocks to match. If only the
padding of a larger filesystem block differs, the primary is treated as torn:
the anchor is copied back and flushed before the ext4 clear. Thus every state
that reaches witness removal has complete-block equality.

A witness-removal tear is repairable only after the ext4 superblock is
independently checksum-valid and clean. The raw primary must be exactly one
sequential-write prefix of the standard zero-witness block followed by the
unchanged suffix of the validated anchor, across the complete filesystem
block. The driver rereads both blocks and repeats that proof immediately before
it writes the standard form directly, flushes it, and retires the exact anchor.
A damaged locator or any other mixture fails closed; there is no fallback scan.
As with the rest of mount validation, this assumes exclusive ownership against
concurrent raw-media mutation. Successful landing leaves no private recovery
authority. External Linux/e2fsprogs mutation and broader hardware power-cut
qualification of the transient convention remain release gates.

## Read-only inspection

The current binding advertises directory enumeration, open/release, reads,
getattr, readlink, list/get xattr, statfs, syncfs, and fsync. Stable ext4 inode
number plus generation is used as the VFS identity. `VFS-CACHE-DENTRY`
therefore makes hard-link aliases share one vnode and preserves the
authoritative on-disk link count.

The implemented reader handles the clean read-side structures exercised by
the four geometry fixtures and the supplemental `read-side-1k-i256` fixture:

- checksummed linear directories and checksummed HTree directories with
  `indirect_levels` 0 or 1, including signed half-MD4 collision continuation;
  `largedir` remains refused, so a level of 2 is invalid;
- extent trees through the profile depth limit of 5, with checked external
  nodes, sparse holes, and unwritten-zero semantics; the supplemental real
  image exercises a depth-1 tree while deeper depths are covered by bounded
  structural traversal;
- legacy direct, single-indirect, double-indirect, and triple-indirect block
  maps on an extents-enabled filesystem;
- allocation-bitmap cross-checks before data, extent-tree, indirect-map, and
  external-xattr blocks are consumed, in addition to the mount-time bitmap
  CRC32C checks;
- regular files, fast and block-backed symlinks, and bounded generic path
  traversal through intermediate and final links, with a nofollow-final
  policy retained for direct `READLINK` and namespace operations;
- 128-byte legacy and 256-byte primary inode checksums and metadata;
- FIFO, character-device, and block-device metadata. `VN.RDEV` uses
  `VFS-RDEV-MAKE`: major occupies the high 32 bits and minor the low 32 bits;
  opening a special inode without a device binding returns stable
  unsupported behavior;
- inline and external-block `user.*`, `trusted.*`, `security.*`, and raw
  `system.posix_acl_access`/`system.posix_acl_default` xattrs, including
  external-block CRC32C and rejection of duplicate or overlapping records;
- concatenated NUL-terminated `LISTXATTR` names and raw `GETXATTR` values;
  and
- read-only `STATFS` geometry/counters and UUID-derived FSID cells.

Directory population snapshots the child head, inode count, and string-pool
cursor. Any I/O, checksum, allocation, or structural failure rolls the cache
back before returning. Sparse reads synthesize zeroes without issuing a media
read for the hole. `SYNCFS` and `FSYNC` are safe no-ops.

`EXT4-BINDING` has `VFS-BF-NEEDS-VOLUME`, `VFS-BF-READ-ONLY`, and
`VFS-BF-STABLE-IDS`. The VFS rejects all mutation before binding dispatch.
`VOL-WRITE` and `VOL-FLUSH` are used only by the mount-time recovery protocol
above; they are not exposed as writable VFS capabilities.

## Deliberate remaining limits

This is completion of the bounded clean read side, not completion of the
writable profile. The remaining boundaries are:

- clean orphan-file admission remains bounded to 4096 filesystem blocks;
- POSIX ACL xattrs are returned as raw bytes, but generic permission
  enforcement is not claimed;
- the real external-tool extent fixture has depth 1 even though the reader
  validates and traverses the profile limit through depth 5;
- the real special-inode fixture covers FIFO, character, and block devices,
  but not a socket inode;
- replay currently requires checksum-v3/64-bit journal records, refuses every
  revoke record, and fails closed on checksum-damaged incomplete tails;
- a primary tear with no intact locator fails closed unless the ext4
  superblock is independently clean and the complete primary block proves the
  exact sequential witness-removal prefix described above;
- legacy and modern orphan recovery and every user-visible mutation operation
  remain unimplemented; and
- recovery-anchor interoperability and the controlled power-cut matrix still
  require external-tool and emulator qualification.

No write capability will be advertised until complete replay/orphan recovery,
ordered-data journaling, external-tool mutation checks, and power-cut
qualification land.

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
