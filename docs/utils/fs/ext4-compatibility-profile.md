# Akashic ext4 compatibility profile v1

This document ratifies the exact ext4 format that the Akashic ext4 binding
must implement. It closes the format-selection milestone independently of
implementation status. The checksummed clean read-only reader now lives in
`utils/fs/drivers/vfs-ext4.f`; its implemented structures and remaining
limits are tracked in [the binding documentation](drivers/vfs-ext4.md).
Until replay, recovery, mutation, and the complete bidirectional gates below
pass, MP64FS remains the working native storage binding and FAT/ext4 remain
read-only interoperability work.

The profile ID is `akashic-ext4-rw-v1`.  Its feature decisions are durable:
the driver must not silently admit a refused bit because a host tool happens
to understand it.  A broader format becomes a separately documented profile
revision with new real-image qualification.

## Immutable authorities

The on-disk and behavioral authority is the Linux v6.18 ext4/JBD2
documentation and source:

- annotated tag object `f7b88edb52c8dd01b7e576390d658ae6eef0e134`;
- peeled commit `7d0a66e4bb9081d75c82ec4957c50034cb0ea449`;
- `Documentation/filesystems/ext4/`, `fs/ext4/`, and `fs/jbd2/` at that
  commit.

The creation, inspection, and checking authority is the complete upstream
e2fsprogs v1.47.4 suite:

- annotated tag object `ece89fac4603e400155b7bbf6326284f8511bca9`;
- peeled commit `7ee1d505ef3b37831215f490411f346fe57e9053`;
- release archive `e2fsprogs-1.47.4.tar.xz`, SHA-256
  `fd5bf388cbdbe006a3d3b318d983b2948382440acc85a87f1e7d108653e8db0b`;
- release-archive publication date `2026-03-06`; and
- upstream version banner `1.47.4 (6-Mar-2025)` and libext2fs version `1.47.4`
  for `mke2fs`, `e2fsck`, `debugfs`, and `dumpe2fs`.  The embedded upstream
  banner/release-note year differs from the archive publication year; both
  values are preserved rather than normalized.

All four tools must come from one source build or one equivalently pinned
package.  Qualification enforces one explicit tool directory, exact tool and
library banners, and the canonical image hashes; the archive hash and build
procedure identify the intended source provenance rather than attempting to
infer it from binary banners alone.  Bare tool names and mixed `PATH`
resolution are forbidden.  In the current workspace, bare `mke2fs` is an
Android 1.47.2 build while the host checker and debugger are Ubuntu 1.47.0;
neither mixture is qualification.

The machine-readable authority for this profile is
`local_testing/fixtures/ext4-profile/manifest.json`.  Its committed
`mke2fs.conf` hash, exact command argv, source pins, feature ledger, geometry,
and environment are contract data rather than suggestions.

## Platform envelope

- The volume exposes 512-byte logical sectors through the generation-bound
  KDOS volume API.  No ext4 code may use ambient disk registers.
- The current block contract has 32-bit LBA/capacity fields.  The largest
  admitted volume is therefore `0xffffffff` sectors, or 2 TiB minus 512
  bytes.  The required ext4 `64bit` flag still controls 64-byte descriptors,
  pointer fields, and checksum layout; every nonzero high address must also
  fit the actual volume.
- Filesystem blocks are exactly 1 KiB, 2 KiB, or 4 KiB.  Clusters equal
  filesystem blocks; `bigalloc` is refused.
- The primary inode size is 256 bytes with `i_extra_isize=32`.  A targeted
  legacy form admits 128-byte inodes with `extra_isize` absent; it cannot
  represent post-2038/high-resolution timestamps and is never the creation
  default.
- Group descriptors are 64 bytes.  Primary images use a flex size of 16 and
  multiple groups: 8 groups at 1 KiB, 4 at 2 KiB, and 4 at 4 KiB.
- Ext4 structures are little-endian.  JBD2 structures are big-endian.
- Path components and xattr names are bounded to 255 raw bytes.  Lookup is
  byte-sensitive; `casefold` is refused.  Public VFS offsets are bounded to
  `0..2^63-1` even if an on-disk unsigned size could be larger.

## Exact primary feature set

Pinned v1.47.4 `mke2fs` images have these clean superblock masks:

| Field | Mask | Required features |
| --- | ---: | --- |
| `s_feature_compat` | `0x0000103c` | `has_journal`, `ext_attr`, `resize_inode`, `dir_index`, `orphan_file` |
| `s_feature_ro_compat` | `0x0000046b` | `sparse_super`, `large_file`, `huge_file`, `dir_nlink`, `extra_isize`, `metadata_csum` |
| `s_feature_incompat` | `0x000022c2` | `filetype`, `extent`, `64bit`, `flex_bg`, `metadata_csum_seed` |

`INCOMPAT_RECOVER` is an admitted transient bit, producing incompat mask
`0x000022c6`.  It requires successful journal replay before ordinary access.
`RO_COMPAT_ORPHAN_PRESENT` is an admitted transient bit, producing ro-compat
mask `0x0001046b`; it requires orphan-file recovery.  A nonzero legacy
`s_last_orphan` likewise requires legacy orphan-chain recovery.

The 128-byte-inode fixture clears only `extra_isize`, giving ro-compat mask
`0x0000042b`.

### `COMPAT` admission

The table is the union of feature definitions visible to the pinned Linux and
e2fsprogs sources, including their named legacy/reserved values.  Akashic is
deliberately stricter than the generic kernel rule for compatible bits:
anything outside the exact admitted set is refused because pinned `e2fsck`
cannot qualify a mutation it does not understand.

| Bit | Feature | Decision | Profile meaning |
| ---: | --- | --- | --- |
| `0x00000001` | `dir_prealloc` | Refuse | No directory-preallocation format support. |
| `0x00000002` | `imagic_inodes` | Refuse | No imagic inode semantics. |
| `0x00000004` | `has_journal` | Read/write | Internal journal required for writable mount. |
| `0x00000008` | `ext_attr` | Read/write | In-inode and external-block xattrs. |
| `0x00000010` | `resize_inode` | Read/write | Preserve reserved inode/GDT space; online resize is not exposed. |
| `0x00000020` | `dir_index` | Read/write | Linear and HTree directories are both required. |
| `0x00000040` | `lazy_bg` | Refuse | Legacy lazy-group feature is outside profile. |
| `0x00000080` | `exclude_inode` | Refuse | Legacy/reserved snapshot value. |
| `0x00000100` | `exclude_bitmap` | Refuse | Snapshot exclusion bitmap is outside profile. |
| `0x00000200` | `sparse_super2` | Refuse | V1 uses `sparse_super`, not the v2 backup map. |
| `0x00000400` | `fast_commit` | Refuse | No fast-commit journal records. |
| `0x00000800` | `stable_inodes` | Refuse | Not emitted by the primary pin. |
| `0x00001000` | `orphan_file` | Read/write | Modern orphan file and checksums are mandatory. |

### `RO_COMPAT` admission

| Bit | Feature | Decision | Profile meaning |
| ---: | --- | --- | --- |
| `0x00000001` | `sparse_super` | Read/write | Validate and maintain required backup groups. |
| `0x00000002` | `large_file` | Read/write | 64-bit regular-file sizes within VFS/volume bounds. |
| `0x00000004` | `btree_dir` | Refuse | Reserved/unused format. |
| `0x00000008` | `huge_file` | Read/write | Decode `i_blocks` units and high bits exactly. |
| `0x00000010` | `gdt_csum` / `uninit_bg` | Refuse | V1 uses `metadata_csum`; the two flags must not be conflated. |
| `0x00000020` | `dir_nlink` | Read/write | Honor the saturated directory-link-count convention. |
| `0x00000040` | `extra_isize` | Read/write | Required on 256-byte primary inodes; absent on the 128-byte fixture. |
| `0x00000080` | `has_snapshot` | Refuse | Snapshot format is outside profile. |
| `0x00000100` | `quota` | Refuse | User/group quota metadata is outside profile. |
| `0x00000200` | `bigalloc` | Refuse | Cluster allocation is outside profile. |
| `0x00000400` | `metadata_csum` | Read/write | CRC32C validation and update are mandatory. |
| `0x00000800` | `replica` | Refuse | Non-upstream replica format. |
| `0x00001000` | `readonly` | Read-only | Honor the on-disk write prohibition. |
| `0x00002000` | `project` | Refuse | Project IDs/quotas are outside profile. |
| `0x00004000` | `shared_blocks` | Refuse | Filesystem-level shared blocks are outside profile. |
| `0x00008000` | `verity` | Refuse | Fs-verity data is outside profile. |
| `0x00010000` | `orphan_present` | Read/write recovery | Transient; recover and clear transactionally. |

An unknown ro-compatible bit may be admitted only for a clean,
recovery-free, genuinely read-only mount.  It can never admit a writable
mount.  A known feature marked Refuse above remains refused in V1 even if its
generic feature class would allow another implementation to mount read-only.

### `INCOMPAT` admission

| Bit | Feature | Decision | Profile meaning |
| ---: | --- | --- | --- |
| `0x00000001` | `compression` | Refuse | No compressed-data format. |
| `0x00000002` | `filetype` | Read/write | `ext4_dir_entry_2` file types required. |
| `0x00000004` | `recover` | Read/write recovery | Replay is mandatory before access and before clearing. |
| `0x00000008` | `journal_dev` | Refuse | Internal journal only. |
| `0x00000010` | `meta_bg` | Refuse | Meta block groups are outside V1 geometry. |
| `0x00000040` | `extent` | Read/write | Extents are canonical, with legacy per-inode maps also required. |
| `0x00000080` | `64bit` | Read/write | 64-byte descriptors and 64-bit fields, bounded by the volume. |
| `0x00000100` | `mmp` | Refuse | No multiple-mount-protection protocol. |
| `0x00000200` | `flex_bg` | Read/write | Validate flexible-group metadata placement. |
| `0x00000400` | `ea_inode` | Refuse | Xattr values may not live in separate EA inodes. |
| `0x00001000` | `dirdata` | Refuse | No data-in-directory-entry format. |
| `0x00002000` | `metadata_csum_seed` | Read/write | Use the stored seed for metadata CRC32C. |
| `0x00004000` | `largedir` | Refuse | No >2 GiB/three-level HTree directories. |
| `0x00008000` | `inline_data` | Refuse | No inline file/directory data format. |
| `0x00010000` | `encrypt` | Refuse | No encrypted inode/name format. |
| `0x00020000` | `casefold` | Refuse | Lookup remains byte-sensitive. |

Every unknown incompat bit refuses mount before cache publication, journal
replay, allocation, or any other mutation.

## JBD2 profile

A new v1.47.4 journal is superblock v2 with all three feature masks zero.
Before its first Akashic transaction, the writer establishes incompat mask
`0x12` (`64bit | checksum_v3`) with checksum type CRC32C (`4`).  The first
revoke may add `revoke`, producing `0x13`.

| Class/bit | Feature | Decision |
| --- | --- | --- |
| Compat `0x01` | checksum v1 | Refuse |
| Incompat `0x01` | revoke | Read/write |
| Incompat `0x02` | 64-bit block tags | Read/write |
| Incompat `0x04` | async commit | Refuse |
| Incompat `0x08` | checksum v2 | Refuse |
| Incompat `0x10` | checksum v3 | Read/write |
| Incompat `0x20` | fast commit | Refuse |

JBD2 has no admitted ro-compatible flags.  Any unknown journal flag refuses
mount.

Recovery is ordered as follows:

1. Validate ext4 superblock geometry, feature admission, all referenced
   bounds, and available metadata checksums without publishing a mount.
2. Locate journal inode 8, validate the JBD2 superblock and matching UUID, and
   admit only the feature states above.
3. Scan from the declared sequence/start, honoring escaped blocks and revokes.
   Replay only complete transactions whose descriptor, payload, revoke, and
   commit checksums validate.  An incomplete tail is ignored; corruption or
   an unsupported record refuses mount.
4. Write replayed home metadata, flush, checkpoint/reset the journal, flush,
   and only then clear `RECOVER`.
5. Recover the legacy orphan chain and the orphan file transactionally and
   idempotently, then clear `ORPHAN_PRESENT` when appropriate.

A physically read-only volume that needs replay or orphan recovery is
refused.  A nominal Linux read-only mount can write during recovery; Akashic
must not misrepresent a dirty, unrecovered image as safe read-only access.

The writer uses metadata journaling with ordered data.  New or changed data
blocks must cross `VOL-FLUSH` before the journal commit that exposes their
metadata.  Descriptor/data/revoke journal records cross a flush before their
commit; checkpoint home writes cross a flush before journal-space reuse.  A
checksum or I/O failure aborts the transaction and transitions the mount to a
stable error/read-only state rather than reporting success.

## Required data and metadata behavior

### Checksums

`metadata_csum` and `metadata_csum_seed` are required.  Checksum type is ext4
CRC32C (`1`); the journal uses JBD2 CRC32C code `4`.  Verify before consuming
and recompute on every mutation:

- primary and backup superblocks;
- group descriptors and full block/inode bitmaps;
- inodes, external extent nodes, directory/HTree blocks and tails;
- in-inode/external-block xattrs and orphan-file blocks; and
- every admitted JBD2 descriptor, data tag, revoke, commit, and superblock.

The driver must follow the pinned UUID/seed, inode-number, inode-generation,
and group-number recipes exactly.  A 64-byte descriptor carries full bitmap
checksums across low/high fields; its descriptor checksum remains truncated
as the pinned format specifies.  `INODE_UNINIT`, `BLOCK_UNINIT`, and
`ITABLE_ZEROED` group flags remain valid even when fixture creation disables
lazy inode-table initialization.

### Inodes and file mapping

Read/write regular files, directories, fast and block-backed symlinks, and
hard links.  Decode/preserve special inode types; opening a device inode
without a device binding returns stable unsupported behavior.  There is no
generic VFS `mknod` operation in ABI-1, so profile ratification does not claim
special-node creation.

Support 128- and 256-byte inodes, 32-bit UID/GID, all admitted type/mode bits,
link counts, generations, 64-bit sizes, `i_blocks` accounting, creation time,
and extended timestamps where the inode can represent them.  Reject an
out-of-bounds `i_extra_isize` before accessing optional fields.

The extent writer is canonical.  Readers and mutators must nevertheless
handle an inode without `EXT4_EXTENTS_FL` on an extents-enabled filesystem:
direct, single-, double-, and triple-indirect legacy maps are in profile.
Extent trees support depths through 5, holes, unwritten extents, safe
split/merge, and checksummed external nodes.  Every header count/max/depth,
logical range, physical range, and child pointer is validated and traversal
is bounded.  The clean reader implements every legacy map level and extent
depth through 5; the supplemental external-tool image qualifies a real
depth-1 external extent node, while deeper real-image qualification remains
to be added.

### Directories, links, and names

Support linear `ext4_dir_entry_2` directories and hash-indexed HTree
directories.  The generated default is signed half-MD4.  Collision chains,
continuation bits, checksum tails, and bounded multi-block lookup must be
handled without treating hash equality as name equality.  With `largedir`
refused, an HTree `indirect_levels` value of 2 or more is invalid.

Names are 1–255 uninterpreted bytes excluding NUL and `/`.  No Unicode
normalization, folding, locale collation, or case-insensitive comparison is
performed.

The generic resolver follows intermediate symbolic links and, where the
operation permits it, the final symbolic link.  Traversal is bounded to a
4096-byte path and 40 followed links, detects loops through that bound, and
handles both relative and absolute targets.  Direct `READLINK` and namespace
operations retain a nofollow-final policy.  The supplemental real image
qualifies this path through a live block-backed symbolic link.

### Extended attributes and ACLs

Support xattrs stored in the inode body or one external xattr block, including
standard shared-xattr-block reference counts.  `ea_inode` is refused, so a
value that cannot fit those forms returns a stable capacity error.  Admit the
`user`, `trusted`, `security`, and POSIX ACL access/default namespaces.

The clean reader exposes `user`, `trusted`, and `security` values plus raw
POSIX ACL access/default bytes.  It rejects duplicate names, overlapping
records, and external xattr blocks whose allocation bitmap disagrees with the
inode reference.

ABI-1 can expose and preserve ACL xattrs, but generic permission enforcement
has not been ratified.  Until that semantic layer exists, the binding must not
claim that merely round-tripping an ACL is equivalent to enforcing it.

### Allocation and namespace semantics

All bitmap, group-counter, inode-table, directory, extent, xattr, orphan, and
journal updates are one bounded transaction or a documented sequence of
transactions.  Allocation and growth zero new blocks before ownership or
logical size is published.  Full-block, full-inode, read-only, stale-volume,
and media failures retain their structured causes.  Rename replacement,
unlink-while-open, inode reuse, hard-link counts, truncate, and directory link
counts must match the ABI-1 vnode/dentry lifetime rules.

Clean unmount commits outstanding work, checkpoints the journal, performs the
required volume flushes, clears transient recovery/orphan state, writes a
clean superblock, and flushes again.  Detach, timeout, or media error cannot
produce a false clean-success result.

## Canonical and supplemental external fixtures

The committed generator creates four real, multi-group geometry images and
one supplemental read-side image:

| Image | Role | Size | Block size | Groups | Inode size | Feature mask |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `primary-1k-i256.img` | geometry | 64 MiB | 1 KiB | 8 | 256 | primary |
| `primary-2k-i256.img` | geometry | 128 MiB | 2 KiB | 4 | 256 | primary |
| `primary-4k-i256.img` | geometry | 512 MiB | 4 KiB | 4 | 256 | primary |
| `legacy-1k-i128.img` | geometry | 64 MiB | 1 KiB | 8 | 128 | primary minus `extra_isize` |
| `read-side-1k-i256.img` | supplemental read side | 64 MiB | 1 KiB | 8 | 256 | primary |

Creation fixes the tool suite, private configuration, UUID, label, directory
hash seed, 16 KiB inode ratio, blocks/group, flex size, internal 4 MiB journal,
error policy, root owner, clock, locale, and timezone.  It explicitly clears
all features with `-O none` and adds exactly the profile list.  Lazy inode and
journal initialization and discard are disabled.

Pinned `debugfs` creates the baseline payload, hard link with correct link
count, fast and block-backed symlinks, three-block sparse file with a middle
hole, and inline/external-sized user xattrs in each geometry image.  The
supplemental image adds a checksummed HTree with a real hash-collision pair,
a depth-1 external extent tree, sparse legacy direct/single/double/triple
maps, FIFO/character/block special inodes, `user`/`trusted`/`security` and raw
POSIX ACL xattrs, and live generic traversal through a block-backed symlink.
Pinned mutating `e2fsck -f -y -D` constructs and checks the supplemental
directory index; this exact argv is profile data.  A final pinned read-only
`e2fsck -f -n` must return exactly zero for every image.

Pinned `dumpe2fs` and `debugfs`, plus an independent Python decoder of the raw
superblock at volume offset 1024, must agree on the pinned geometry and feature
fields.  The generator records complete argv, tool hashes, all five image
hashes, observed facts, and output hashes in ignored
`local_testing/out/ext4-profile/qualification.json`.

Run:

```sh
python3 local_testing/generate_ext4_profile_fixtures.py \
  --tool-dir /absolute/e2fsprogs-1.47.4-prefix/sbin \
  --output-dir local_testing/out/ext4-profile

AKASHIC_E2FSPROGS_TOOL_DIR=/absolute/e2fsprogs-1.47.4-prefix/sbin \
  python3 -m pytest -q local_testing/test_ext4_profile.py
```

The host profile deliberately does not enter `akashic_tui.PROFILES`: the
read-only driver is explicit-volume qualification work, not yet a default
boot-image or automount profile.

## Current implementation gate

The ext4 binding milestone starts with read-only admission and inspection of
every admitted clean format above, stable refusal for every known refused
flag, checksum and corruption validation, and comparison with the external
oracles.  The current reader covers the four geometry images and supplemental
read-side image, including checked HTree lookup, external extents, all legacy
map levels, allocation-bitmap cross-checks, special metadata, namespaced raw
xattrs, and bounded generic symlink traversal.

The bounded clean read-side landing does not implement journal replay, legacy
or modern orphan recovery, or mutation; an image requiring recovery is still
refused.  Clean orphan-file admission remains bounded to 4096 filesystem
blocks, ACLs are exposed but not enforced, the real extent fixture reaches
depth 1 rather than the implemented profile limit of 5, and the special-inode
fixture does not yet contain a socket.  Those qualification and semantic
limits remain explicit before any write path can be advertised.

Profile completion does not waive the larger bidirectional matrix: externally
created and journaled images, Akashic mutations inspected by external tools,
raw/MBR/GPT volumes, dirty and damaged images, controlled power cuts, complete
namespace/data/metadata/xattr operations, and MP64FS/RAM/FAT regressions remain
required before the ext4 binding is complete.

## Primary references

- Linux v6.18 ext4 documentation at the pinned tree:
  <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/filesystems/ext4?h=v6.18>
- Linux v6.18 ext4 source at the pinned tree:
  <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/ext4?h=v6.18>
- Linux v6.18 JBD2 source at the pinned tree:
  <https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/jbd2?h=v6.18>
- e2fsprogs v1.47.4 source:
  <https://git.kernel.org/pub/scm/fs/ext2/e2fsprogs.git/tree/?h=v1.47.4>
- e2fsprogs v1.47.4 release archive and signed checksums:
  <https://www.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v1.47.4/>

`lwext4` remains a non-authoritative portable implementation reference.  It
does not alter this feature set or the Linux/e2fsprogs behavioral oracle.
