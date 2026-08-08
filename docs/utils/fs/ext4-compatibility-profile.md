# Akashic ext4 compatibility profile v1

This document ratifies the exact ext4 format that the Akashic ext4 binding
must implement. It closes the format-selection milestone independently of
implementation status. The checksummed clean read-only reader now lives in
`utils/fs/drivers/vfs-ext4.f`; its implemented structures and remaining
limits are tracked in [the binding documentation](drivers/vfs-ext4.md).
The bounded checksum-v3 JBD2 replay slice now includes committed revoke
records, and the private writer can establish a crash-resolvable empty
checksum-v3 journal plus ext4 `RECOVER` state, emit one durable ordered
descriptor/payload/revoke/commit transaction, checkpoint its retained metadata
after-images, and release the journal for an immediate sequential transaction
without leaving write-active state. Public unmount can now checkpoint a
`COMMITTED` transaction and cleanly deactivate the write-active journal.
Exact singleton cleanup for admitted modern and legacy orphan state is now
implemented; multi-record/general orphan mutation, user-visible mutation, and
the complete bidirectional gates remain open.
MP64FS remains the working native storage binding and FAT/ext4 remain
read-only interoperability bindings; ext4's mount path may perform the
strictly ordered recovery writes described below.

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
mask `0x0001046b`; it requires orphan-file recovery. A nonzero legacy
`s_last_orphan` is likewise admitted for authenticated post-replay discovery
but requires legacy orphan-chain recovery before mount can be published.

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
| `0x00010000` | `orphan_present` | Read/write recovery | Transient; preserve through replay/cleanup, then clear through witnessed clean landing only after authoritative empty proof. |

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
Before its first Akashic transaction, the private activation transition
establishes incompat mask `0x13` (`64bit | checksum_v3 | revoke`) with checksum
type CRC32C (`4`).

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

### Private clean-to-RECOVER activation

Before the first private transaction, the implementation can now move a clean,
empty journal to incompat mask `0x13` and set ext4 `RECOVER` without exposing a
public write operation. The transition begins by binding a fresh journal-block
0 reread to the exact mounted writer and I/O target. Header form, geometry,
sequence and wrapped next transaction ID, start/head state, feature masks,
UUID, user/dynamic-super fields, transaction limits, and checksum state must
all match. This prevents a feature-zero, unchecksummed old primary from having
stale geometry or identity newly authenticated by activation. A mismatch is a
pre-mutation failure and creates no witness.

The transition has two valid copies of a private `AKW1` activation image: a
guard at the current first-unused journal slot and the primary at journal block
0. In addition to the `AKR1` checksum/anchor tuple, `AKW1` records the intended
dirty ext4-superblock checksum and complement plus the old journal feature,
head, checksum-type, and checksum fields. The guard is first written with byte
zero invalid and flushed, then made valid and flushed. The identical primary
is written and flushed before the two-sector ext4 `RECOVER` update. After that
update is flushed, the implementation rereads and proves the primary, guard,
and dirty ext4 endpoint before it removes `AKW1` from the primary and retires
the guard. The durable result is an empty standard checksum-v3/revoke journal
with `RECOVER` intentionally set, ready for the private transaction emitter.

Every admitted partial-write state resolves forward. An installation tear is
completed from the exact `AKW1` guard and advanced to the dirty ext4 endpoint;
an `AKW1`-clear tear is advanced to the standard primary. Once activation
authority is removed, the already implemented `AKR1` empty-journal
reset/clear protocol performs the ordinary clean landing. No
activation-recovery path reverses a torn write or treats the transition as a
committed user transaction. For private-writer activation, a failure after the
first media phase latches its first ior and phase, faults the writer, and marks
the VFS read-only/dirty so only remount recovery may resolve the uncertain
durable state. Writer-free mount recovery instead returns the media error with
lifecycle `NEW`; a fresh mount resolves any durable witness prefix.

The same `AKW1` primitive is mount-recovery infrastructure. A checksum-valid
clean input with `ORPHAN_PRESENT` set and `RECOVER` clear enters a durable
recovery epoch with `writer|0`, borrowing two existing mount-context block
buffers instead of allocating private writer storage. Writer allocation is
one-time and exact-geometry within a monotonic arena; a recovery-sized
allocation would conflict with later production credits. The dirty endpoint
sets `RECOVER` while preserving `ORPHAN_PRESENT`; the following
`AKE1`-qualified `AKR1` landing clears both only after authenticated empty
proof. No writer is allocated or published, and no write-active endpoint is
exposed by a successfully mounted VFS.

### Private one-transaction emission

The current private writer can emit one fully staged ordered transaction. A
reservation includes a standard active-super guard plus every descriptor,
metadata payload, revoke, and commit block. The guard consumes journal-ring
space but is not a JBD2 record, so the standard `s_max_transaction` bound is
applied to the reservation minus the guard. The ring's separately excluded
spare remains the all-zero sentinel immediately after the commit. Ordered-data
credits are bounded by `s_max_trans_data` and do not consume log records.

Before any commit can become authoritative, ordered data is written to its
home blocks. The descriptor/payload/revoke body follows, including escaped
metadata payloads and checksum-v3 tag/block checksums. The intended commit is
then written with byte zero invalid, the following sentinel is zeroed, and the
entire body is flushed. The invalid preseed and the final checksummed commit
differ in exactly byte zero, so a sequential prefix is either invalid or the
exact commit endpoint.

The writer next publishes the active journal state through two identical
standard checksum-v3/revoke superblocks: a guard `G` in the ring and journal
block 0. Both use the transaction ID as `s_sequence`, the descriptor after
`G` as `s_start`, `G` as `s_head`, and zero private padding. The guard is
preseeded with byte zero invalid and flushed, then made valid and flushed; the
identical primary is written and flushed, and both are reread for exact proof.
Only after that proof is the valid commit written and flushed.

Successful emission publishes the private workspace as `COMMITTED` and
retains every staged entry and after-image. Ordered data is durable at home,
but metadata home blocks are unchanged at this boundary. Retry, abort, and
another transaction remain busy until checkpoint consumes those retained
images and releases the log reservation.

### Private same-session checkpoint and reuse

Checkpoint does not trust retained RAM alone. Before its first home write it
revalidates the writer object, performs an ordinary complete read-only scan of
the active on-media transaction, and repeats the scan in lockstep with retained
emitter order. The active primary/guard pair, transaction ID,
start/head/cursor, each descriptor home and unescaped payload, every revoke
identity, the commit, the exact zero sentinel, the retained entry set, and
retained image CRCs must agree on one complete committed stream. Corruption,
an incomplete stream, stale workspace state, or any disagreement fails before
home mutation.

The checkpoint then writes only retained active metadata after-images to their
home blocks. Ordered data was already made durable before commit and is not
rewritten; cancelled and revoked entries carry no checkpoint authority. Every
home write completes before one volume flush, and that flush plus a strict
filesystem reload and root validation completes before journal-space release.
Until then, the committed active log remains the retry authority.

Release reuses active guard `G` as the `AKG1` reset anchor and publishes an
empty `AKR1`-witnessed primary. Once that primary is durable, checkpoint may
remove its witness while retaining the checksum-valid dirty ext4 superblock
with `RECOVER` set. The exact anchor remains present during the witness-clear
write so either endpoint or an admitted sequential prefix is recoverable.
After the standard witness-free empty primary is flushed, ext4 `RECOVER`
becomes the ordinary durable recovery authority and `G` can be retired and
flushed. This authority handoff needs no additional private witness.

The successful endpoint deliberately remains mounted dirty and write-active:
ext4 `RECOVER`, the in-memory journal `WRITE-ACTIVE` publication, and the VFS
dirty flag stay set. An exact final reread rebases the same workspace to the
persisted empty-journal head and sequence, restores full ring space, scrubs the
consumed transaction, and publishes `IDLE`. A second transaction can begin
immediately, including across 32-bit sequence wrap, without another `AKW1`
activation or arena allocation. Clean deactivation is reserved for clean
unmount/recovery rather than conflated with per-transaction checkpoint.

### Clean write-active deactivation and public unmount

The ext4 callback applies this state matrix:

| Entry state | Public-unmount result |
| --- | --- |
| Clean, non-write-active, with or without retained writer storage | Authenticate the clean endpoint and detach without media mutation. |
| Write-active, transaction-clean `IDLE` | Run the six-write clean landing, prove it, and detach. |
| `COMMITTED` | Authenticate and checkpoint the retained transaction, require the resulting clean `IDLE` writer, then deactivate. |
| `STAGING`, `ACTIVATING`, `EMITTING`, `CHECKPOINTING`, or `DEACTIVATING` | Return `VFS-E-BUSY` and retain mounted lifecycle, `V.BCTX`, readiness, and writer authority. |
| `FAULTED` | Return the exact latched writer ior, retain `V.BCTX`, and transition the VFS to terminal `VFS-L-STALE`. |
| Malformed/missing authority or a non-clean final endpoint | Return corruption, retain `V.BCTX`, and transition the VFS to terminal stale. |

`VFS-UNMOUNT-F-FORCE` bypasses only the VFS core's open-handle refusal. It
does not waive checkpointing, busy-state refusal, clean landing, the final
proof, or failure quarantine.

Dirty-empty `IDLE` deactivation starts with a flush, strict reload, and root
proof. W1 writes and flushes the invalid-byte `AKR1` preseed; W2 writes and
flushes the valid reset anchor; W3 writes and flushes the witnessed empty
primary; W4 writes and flushes the checksum-valid clean ext4 superblock; W5
writes and flushes the standard witness-free primary; and W6 zeroes and
flushes the anchor: six writes and seven flush barriers including the initial
preflight flush. Immediately before W5, fresh raw reads must prove the
primary witness and ext4 endpoint, the named exact anchor, and equality across
the complete filesystem block. Strict final reload/root/attachment proof
precedes writer scrubbing, dirty/write-active/current/readiness withdrawal,
and detach.

Any failure after checkpoint or deactivation enters its media protocol
preserves the first ior and phase, faults the writer, forces read-only/dirty
state, retains `V.BCTX`, and makes the VFS terminal stale. Pre-dispatch
attachment drift or recovery-media refusal instead makes the VFS terminal
stale without entering deactivation or issuing media I/O. The same instance
cannot retry or report clean detach. A fresh VFS must classify the surviving
endpoint or admitted sequential prefix and converge forward; that fresh
converged VFS is mounted non-dirty, while the original VFS remains terminal
stale.

The bounded 1 KiB qualification uses 63 metadata after-images and 126 revokes,
the first counts that require two descriptor batches and two revoke batches
for that geometry. These are test thresholds, not implementation capacities.
It places the guard at `s_maxlen-3`, making the first descriptor's payload run
cross from logical block 4095 to logical block 1. Independent media checks
cover every emitted record and checksum. A clean remount must replay all 63
metadata images, parse all 126 revokes with zero matching tag hits, leave the
revoke-named homes unchanged, reset the journal, and rebase the existing
workspace without arena growth.

The active-to-empty recovery transition reuses `G` as the reset anchor. An
`AKG1` subtype in the otherwise-zero activation-private `AKR1` fields records
the marker and complement, active sequence and complement, and complete active
filesystem-block CRC32C and complement. This authenticates the exact active
predecessor if journal block 0 tears while changing from the active image to
the reset image. Recovery reconstructs that predecessor, proves the complete
primary is one sequential prefix between the active and reset endpoints, and
then proceeds forward through ordinary `AKR1` reset/clear landing.

Writer ownership is mount-generation scoped. Mount clears the private
`WRITER-CURRENT` publication before rebuilding media-derived state. Failed
mounts preserve but cannot use or scrub staged, committed, or faulted bytes.
Only a successful recovery, strict reload, root/attachment validation, and
static workspace-shape proof may zero the workspace, rebase it to the
authenticated clean journal head/sequence, publish `IDLE`, and republish it as
current after remount. In the same mount, only the final authenticated
dirty-empty checkpoint endpoint may perform the corresponding scrub and
rebase. Same-mount faults remain quarantined; a write, flush, checksum, or
reread-proof failure latches its first ior and phase, forces read-only/dirty
state, and requires remount convergence. Unmount clears `WRITER-CURRENT` and
binding readiness only after a successful clean proof and before detaching the
block context. Busy and failed unmount paths retain `V.BCTX` and the relevant
writer state for retry or diagnosis; late terminal faults need not republish
authority already withdrawn after the final media proof.

Recovery is ordered as follows:

1. Validate ext4 superblock geometry, feature admission, all referenced
   bounds, and available metadata checksums without publishing a mount.
2. Locate journal inode 8, validate the JBD2 superblock and matching UUID, and
   admit only the feature states above.
3. Scan from the declared sequence/start, honoring escaped blocks and revokes.
   Replay only complete transactions whose descriptor, payload, revoke, and
   commit checksums validate.  An incomplete tail is ignored; corruption or
   an unsupported record refuses mount.
4. Write replayed home metadata and flush. Strictly reload and validate the
   authoritative post-replay filesystem, including legacy and modern orphan
   state, before changing recovery authority.
5. Recover any nonempty orphan state transactionally and idempotently while
   preserving the applicable recovery authority. An authenticated empty modern
   set requires no orphan inode or orphan-file-block mutation.
6. Checkpoint/reset and flush the journal. After final empty proof, use the
   witnessed clean landing to clear `RECOVER` and `ORPHAN_PRESENT` together,
   then retire its witnesses. A clean input carrying `ORPHAN_PRESENT` without
   `RECOVER` first establishes the recovery epoch through writer-free `AKW1`.

The current implementation covers steps 1 through 4 for
`64bit | checksum_v3` (`0x12`) with the optional standard `revoke` bit
(`0x13`). It also covers the authenticated discovery and classification
precondition for step 5 across legacy and modern orphan state, plus the
authenticated-empty modern branch of steps 5 and 6 for those journals and for
a clean feature-zero journal, which writer-free `AKW1` upgrades before the
clean landing. Replay first authenticates the
complete committed prefix, counts only revokes protected by a valid
transaction commit, then builds the latest transaction ID for each revoked
block before replaying unrevoked descriptor payloads. Journal length comes
from inode 8 and must exactly match the authenticated 32-bit JBD2 `s_maxlen`;
the exact map, uniqueness hash, and recovery-only half-full power-of-two revoke
index come from the caller-provided arena, so 4 MiB is a canonical-fixture
choice rather than a driver ceiling. Failed-mount retries clear and reuse an
existing index instead of leaking arena storage; the private writer separately
reserves its bounded transaction workspace. Revoke comparison uses JBD2's
wrapping 32-bit
transaction ordering.
The recovery profile additionally requires standard `s_jnl_backup_type=1`.
All validated sparse-super copies must carry the same 68-byte `s_jnl_blocks`
tuple as the primary, and that tuple must exactly reproduce inode 8's
`i_block`, size-high, and size-low fields. Because the standard tuple omits
inode flags, generation, and authentication inputs for external extent nodes,
journal inode 8 is deliberately pinned to generation zero and a complete
inline depth-0 extent root: one through four initialized extents, gapless
logical coverage through journal EOF, and bounded, pairwise-disjoint physical
ranges. This is a recovery-authority rule for the fixed internal journal, not
a restriction on ordinary inode maps or journal capacity beyond the inline
extent format itself.
The tuple expander rejects holes, mappings beyond journal EOF, and aliased or
out-of-range data blocks. Before any journal read, the group-1 backup GDT
authenticates every group's block/inode bitmap and inode-table ranges; the
tuple must be disjoint from all of them and from every deterministic sparse
super/GDT/reserved-GDT range. Dirty bootstrap follows a deterministic
independent chain: checksum-valid group-1 backup super, checksum-valid backup
GDT, live inode-8 allocation bit, checksum-valid inode 8, and exact tuple
equality. It does not trust a torn primary descriptor or prefix-mixed
aggregate free-space counters.

The designated sparse super and its geometry-derived backup-GDT span are
replay-frozen. A tag for the shared inode-table block is admitted only when its
authenticated payload preserves journal inode 8 byte-for-byte; neighboring
inode records remain independently mutable. An inode-bitmap payload must keep
inode 8 allocated. A payload for the first primary-GDT block containing group
0's descriptor must retain the witnessed bitmap and inode-table locators and a
valid descriptor checksum. A primary-super payload must retain `RECOVER`, a
valid checksum/seed, every invariant authenticated by the sparse witness, and
all profile/counter bounds needed for the next mount to reach recovery. If the
raw primary checksum is torn, the read-only scan must also prove that such a
replacement belongs to an authenticated committed transaction before replay
writes any home block. A descriptor in an incomplete tail does not suffice.

A valid incomplete tail is ignored, while a checksum-damaged tail remains a
fail-closed limitation rather than being guessed incomplete. A
matching-sequence JBD2 `SUPER_V2` header terminates preflight only after the
complete block validates as the checksummed, self-locating recovery anchor; it
is never replayed as a transaction record.

To make the checkpoint/reset transition and clean deactivation
retryable across 512-byte media tears, the implementation preseeds the selected
journal anchor with the complete intended reset image except for an invalid
byte zero and flushes it. It then restores byte zero and writes and flushes the
valid checksummed copy before updating journal block 0. Those two images differ
in only byte zero, so no prefix cut can combine a new valid JBD2 header with
stale cursor contents. The copy stores an `AKR1` witness in the JBD2 padding at
`0x5c..0x6f`: intended ext4-superblock checksum plus complement and anchor
logical block plus complement. Standard `s_head` at `0x58` is set to the same
first-unused slot.
For clean recovery or deactivation, strict reload first proves the
authoritative orphan state empty while `RECOVER` remains set. The primary
reset is then flushed before the two-sector ext4-superblock clear of
`RECOVER` and `ORPHAN_PRESENT`, and that clear is flushed before the primary
witness is removed and flushed. The anchor slot is then zeroed and flushed
before successful live deactivation returns or recovery publishes a clean
mount. Once the clean ext4 superblock and standard witness-free primary are
authoritative, leftover anchor bytes from a late failed landing are
non-authoritative; a fresh mount may accept that clean endpoint without
reading or zeroing the old slot. A torn primary may select only the exact
self-locating anchor named by an intact primary
marker/complement/`s_head` tuple; there is no historical-anchor scan. Before
the first witness-removal write, the exact anchor must validate and its
checksummed 1024-byte JBD2 superblock must match the primary. A mismatch only
in larger-block padding marks the primary torn; the complete anchor is copied
back and flushed so the whole primary filesystem block equals it before the
clear proceeds.

Same-session checkpoint uses a second, standard endpoint for that authority
handoff. After metadata home writes and their flush, the `AKG1` active reset is
made durable while the independently checksum-valid dirty ext4 superblock
continues to carry `RECOVER`. The exact anchor remains authoritative while the
primary changes from witnessed empty to standard empty. A damaged primary must
equal a single sequential-write prefix of the constructed standard
zero-witness block followed by the unchanged suffix of that exact validated
anchor, across the complete filesystem block. The standard primary is written
and flushed before the anchor is retired. At that point the combination of
checksum-valid dirty ext4 `RECOVER` and a standard empty checksum-v3 journal is
ordinary recovery authority, so clearing `RECOVER` is neither required nor
permitted for per-transaction reuse.

The clean and dirty-empty cleanup endpoints both reread the raw primary and
anchor and repeat their prefix proof immediately before installing the
standard block. Every other torn or inconsistent locator fails closed. Mount
requires exclusive ownership against concurrent raw-media mutation. `AKR1`,
`AKG1`, and `AKE1` remain transient private profile state, not new JBD2
feature bits; stock Linux/e2fsprogs mutation and broader hardware power-cut
qualification must pass before any landing can be called release-ready.

For an emitted active transaction, reset uses the active guard rather than an
unrelated first-unused slot and carries the `AKG1` predecessor proof described
above. A proven empty predecessor whose normalized old head already names the
selected anchor carries `AKE1`: marker/complement, old raw head/complement,
and complete old filesystem-block CRC32C/complement. Its preceding sequence is
derived from the authenticated reset sequence modulo 32 bits. This lets
recovery reconstruct raw head zero or nonzero, authenticate 2/4 KiB padding,
and prove a reset-primary prefix before the `AKR1` marker itself reached the
primary. Ordinary resets without either predecessor relation keep those six
private words zero and fail closed on such an early prefix. These distinctions
preserve retry authority without turning stale historical guards into
candidates.

A physically read-only volume that needs replay or orphan recovery is
refused.  A nominal Linux read-only mount can write during recovery; Akashic
must not misrepresent a dirty, unrecovered image as safe read-only access.

The writer uses metadata journaling with ordered data.  New or changed data
blocks must cross `VOL-FLUSH` before the journal commit that exposes their
metadata.  Descriptor/data/revoke journal records cross a flush before their
commit; checkpoint home writes cross a flush before journal-space reuse.  A
checksum or I/O failure latches the first error, quarantines the live
transaction, and transitions the mount to a stable error/read-only state
rather than reporting success. Because a failed commit write may nonetheless
have reached the exact durable endpoint, only remount recovery may classify
the log and replay an authenticated commit or discard an incomplete
transaction. The implemented private slice reaches the durable-commit boundary
and retains its after-images, then performs a full-log preflight, checkpoint
home-write flush, and dirty-empty journal release before permitting the next
sequential transaction.

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

Clean unmount checkpoints a durable `COMMITTED` transaction before the clean
landing. Staged or in-flight writer states return `VFS-E-BUSY`; force does not
discard them. The landing performs the required volume flushes, clears
transient recovery state, writes and proves a clean superblock/journal
endpoint, and only then detaches. Nonempty modern and legacy orphan cleanup
will join this transition when implemented; authenticated-empty modern orphan
state already uses it. Detach, timeout, or media
error cannot produce a false clean-success result.

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
hash seed, 16 KiB inode ratio, blocks/group, flex size, the canonical
fixtures' internal 4 MiB journal, error policy, root owner, clock, locale, and
timezone. The VFS qualification additionally generates a private 8 MiB journal
and relocates a checksummed transaction above logical block 4095 and across
the journal-ring boundary. This proves both that the fixture value is not an
admission limit and that cursor wrap follows authenticated ring geometry. It
explicitly clears all features with `-O none` and adds exactly the profile
list. Lazy inode and journal initialization and discard are disabled.

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

The bounded reader now includes checksum-v3/64-bit, revoke-aware
committed-prefix replay and a crash-retry anchor for clearing `RECOVER`. Dirty
replay is bootstrapped through the replay-frozen group-1 sparse-super/GDT
witness, and a torn primary super requires a committed, unrevoked
invariant-preserving replacement before any home write. A private arena-bounded
writer foundation now validates and reuses exact workspace geometry, reserves
transaction/ring credits, and owns coalesced metadata, ordered-data, and revoke
after-images. Its private `AKW1` two-copy activation performs exact
fresh-primary rebinding, ordered clean-to-`RECOVER` media writes,
phase-specific fault quarantine, and forward-only crash resolution through the
existing `AKR1` clean landing. The private emitter now writes one ordered-data
home set, one checksummed descriptor/payload/revoke/commit stream, the exact
invalid commit preseed and zero sentinel, and a standard active primary/guard.
It publishes `COMMITTED` only after the final commit flush and retains all
after-images. `AKG1` authenticates active-to-reset retry, while mount-owned
writer-current publication prevents failed retries from erasing fault state.
Checkpoint now authenticates the complete retained on-media log, writes and
flushes metadata after-images, turns the active journal into a standard empty
journal without clearing `RECOVER`, and rebases the same allocation for an
immediate sequential transaction without reactivation or arena growth. It
now also checkpoints `COMMITTED` state during public unmount and performs the
six-write clean deactivation with terminal fault quarantine. Public write
capabilities remain disabled. Modern `ORPHAN_PRESENT` and a nonzero legacy
`s_last_orphan` are now admitted, after any required journal replay and strict
reload, into a unified, non-mutating two-pass preflight. Legacy discovery
follows checksum-valid allocated inodes through `i_dtime` under a
geometry-derived traversal bound; modern discovery streams the authenticated
orphan file. Their exact combined active count sizes one caller-arena-backed,
half-full power-of-two plan. Each four-cell record retains the inode, protocol,
and cleanup locator as legacy `{ inode, legacy, next, 0 }` or modern
`{ inode, modern, logical-block, slot }`; one hash enforces union-wide inode
uniqueness, including modern duplicates and cross-protocol reuse, while the
bounded legacy walk independently rejects cycles. Every referenced inode and
applicable data map is then authenticated. Mount may transactionally clean an
exact one-record union when it is either a linked depth-zero truncation already
at zero size or an unlinked depth-zero deletion with zero or one initialized
block and the qualified allocation/xattr shape. The sealed transaction removes
the modern slot or legacy head, updates and checksums the target inode, and for
admitted deletions releases the exact data and inode allocation plus
descriptor/super counters. Strict reload must prove the union empty before
mount publication. A larger union or a structurally valid record outside those
exact shapes returns the stable recovery-required refusal without partial
cleanup or public mutation. Structural chain, locator, ownership, or
duplicate-membership failures return corruption, while inode allocation and
checksum failures preserve their specific corruption detail. Failed-mount
retries clear and reuse a retained table when it is large enough rather than
abandoning monotonic arena storage; an insufficient caller arena or retained
table fails without a second allocation.

An authenticated empty modern set is completed before mount publication only
when both protocol counts are zero. Writer-free `AKW1` and `AKE1`-qualified
`AKR1` clear `RECOVER` and `ORPHAN_PRESENT` together without changing an
orphan inode/file or legacy link and without allocating a private writer. The
implementation still fails closed on checksum-damaged incomplete tails and
refuses multi-record or otherwise unqualified nonempty cleanup plus every
user-visible mutation. ACLs are exposed but not enforced, the real extent
fixture reaches depth 1 rather than the implemented profile limit of 5, and
the special-inode fixture does not yet contain a socket. Those qualification
and semantic limits remain explicit before any write path can be advertised.
Focused discovery coverage exercises one- and two-inode legacy chains, a mixed
legacy/modern union, stable refusal with same-binding plan reuse, corrupt
legacy links and cycles, allocation/checksum failures, and cross-protocol
duplicate rejection without writes. Exact singleton cleanup has modern and
legacy zero-/one-block coverage across 1/2/4 KiB geometry, controlled 1 KiB
write-prefix and durability-fence cases, and pinned e2fsprogs inspection of the
admitted results. Unified discovery and cleanup still need broader
qualification for longer chains, later modern blocks and large orphan files,
additional ownership and deletion shapes, distinct-key hash collisions, and
arena exhaustion or retained-too-small retry behavior.

The remaining writer gate explicitly includes a geometry-derived production
workspace/capacity contract with bounded transaction chunking,
general multi-record orphan cleanup, the complete
namespace/data/metadata/xattr mutation surface, public-write integration,
external-tool inspection of Akashic-authored active, dirty-empty, and clean
images, and the controlled power-cut/release matrix.

The exact private regular-file callback now provides one narrow chunking
primitive: a larger size-preserving caller range completes only its first
filesystem-block chunk and returns legal short progress, retaining the fixed
`1 metadata / 1 data / 0 revoke` workspace. This removes a caller-size limit
from the qualified slice but does not satisfy the general workspace/chunking
gate for growth, allocation, multi-home metadata, or namespace operations.

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
