# Akashic ext4 compatibility profile v1

This document ratifies the exact ext4 format that the Akashic ext4 binding
must implement. It closes the format-selection milestone independently of
implementation status. The checksummed reader, ordinary read-only binding, and
explicit staged-write binding live in `utils/fs/drivers/vfs-ext4.f`; their
implemented structures and remaining limits are tracked in
[the binding documentation](drivers/vfs-ext4.md).
The bounded checksum-v3 JBD2 replay slice now includes committed revoke
records, and the journal writer can establish a crash-resolvable empty
checksum-v3 journal plus ext4 `RECOVER` state, emit one durable ordered
descriptor/payload/revoke/commit transaction, checkpoint its retained metadata
after-images, and release the journal for an immediate sequential transaction
without leaving write-active state. Public unmount can now checkpoint a
`COMMITTED` transaction and cleanly deactivate the write-active journal.
Cleanup for a union whose records all fit the currently supported modern and
legacy per-record orphan shapes is now implemented as one exact transaction
per record. Its count is bounded by authenticated geometry, checked arithmetic,
and caller-arena capacity rather than a cleanup-specific constant; positive
union-drain qualification currently reaches two records. Broader record
shapes, mutation beyond the staged write operations, and the complete
bidirectional gates remain open. MP64FS remains the working native storage
binding. FAT and
the ordinary ext4 binding remain read-only interoperability surfaces; ext4
additionally exposes the explicitly named staged capability described below.

The profile ID is `akashic-ext4-rw-v1`.  Its feature decisions are durable:
the driver must not silently admit a refused bit because a host tool happens
to understand it.  A broader format becomes a separately documented profile
revision with new real-image qualification.

## Production contract and delivery ratchet

`akashic-ext4-rw-v1` remains the complete production contract. It is not a
rule that every final operation, recovery shape, geometry, and fault fence must
be implemented before any narrower operation can be developed and qualified.
Internal or explicitly staged operation slices may land under this profile
without inventing a weaker format profile, provided the public capability mask
continues to describe only behavior that has actually passed its promotion
gate. `Staged` names incremental conformance status only. A slice that passes
its per-operation promotion gate is the real production implementation and is
production-closed inside its documented envelope; it is not yet a claim of
complete profile conformance.

This document uses three distinct admission terms:

- **profile-admitted** means required by the final
  `akashic-ext4-rw-v1` production contract;
- **currently recovery-supported** means the valid on-disk recovery states
  the present recovery implementation can complete; and
- **operation-admitted** means the requests and durable states exposed by one
  promoted mutation operation.

Every staged or public mutation slice is crash-closed: before it is exposed,
the driver must recover every recovery state it elects to accept and every
durable state that slice can create. After replay and strict reload, any valid
but currently unsupported orphan union refuses before the first orphan-cleanup
write, mount publication, or writer enablement. Corrupt state and insufficient
bounded workspace remain distinct failures. Recovery authenticates and
preflights the complete discovered union before mutating any member; it never
cleans a supported prefix and then discovers an unsupported remainder.

The implementation therefore advances from a qualified recovery baseline,
not from every shape that a parser happens to recognize. A shape belongs in
that baseline only after it has production cleanup, exact allocation and
accounting proofs, a zero-write stable clean remount, pinned e2fsprogs
acceptance, and representative crash recovery for each materially distinct
home/authority topology. Otherwise admission must clamp it to a stable
write-free refusal. Recovery coverage is expanded when an enabled or next
operation can create a new state, pinned Linux/e2fsprogs or a representative
external corpus produces a state the driver chooses to accept, or concrete
crash, fuzz, checker, or field evidence exposes a gap. Dense recovery that no
longer fits one transaction requires a bounded resumable multi-transaction
protocol that retains recovery authority; it does not justify an open-ended
ladder of speculative special cases.

Qualification is compositional. The complete journal lifecycle matrix remains
required once for each materially distinct transaction/recovery state-machine
topology, while each operation supplies its own semantic, durability,
interoperability, and checker evidence. Adding a cleanup shape does not by
itself multiply every protocol, geometry, and fault fence unless it changes
write ordering, metadata-home roles, witness authority, batching, ring wrap,
or resolver behavior. Complete profile release still requires the full
profile-admitted operation and recovery closure.

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
- The cold-source harness's 255-byte bound applies to one transported physical
  source line and is not a filesystem capacity. Separately, the current
  backup-super validator requires each scheduled backup group number to equal
  the 16-bit on-disk `s_block_group_nr`; a required sparse-super backup above
  group 65535 is outside the implemented profile.
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

Before the first activation write, the mounted-context protocol-home
certificate must prove that no allocated non-journal inode owns either the
primary-super home block or any extent in the authenticated journal tuple.

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
buffers instead of allocating private writer storage. The dirty endpoint sets
`RECOVER` while preserving `ORPHAN_PRESENT`; the following
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
| Clean, non-write-active, with or without a dedicated writer profile | Authenticate the clean endpoint, scrub and release any dedicated profile, and detach without media mutation. |
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

Writer ownership is mount-generation scoped and storage-kind explicit. The
production profile is one caller-selected metadata/data/revoke tuple allocated
at the base of a fresh dedicated arena; mount cleanup uses a separate scoped
tail allocation in the ordinary mount arena. Mount clears the private
`WRITER-CURRENT` publication before rebuilding media-derived state. Failed
mounts preserve but cannot use or scrub staged, committed, or faulted bytes.
`EXT4-WRITER-WORKSPACE-BYTES?` returns the exact tuple-specific byte count only
after applying ring, `s_max_transaction`, and `s_max_trans_data` limits.
`EXT4-BIND-WRITER-ARENA?` accepts a fresh live arena with a recognized backing
source, nonwrapping aligned backing, and no overlap with the VFS arena; it
allocates and publishes atomically. Live writer validation requires the same
store kind and arena, the exact allocation endpoint, and exclusive bump-pointer
ownership. A smaller later credit request reuses the profile; an oversized
component returns `VFS-E-NOSPC` without reallocating or changing capacities.
Only a successful recovery, strict reload, root/attachment validation, and
static workspace-shape proof may zero the workspace, rebase it to the
authenticated clean journal head/sequence, publish `IDLE`, and republish it as
current after remount. In the same mount, only the final authenticated
dirty-empty checkpoint endpoint may perform the corresponding scrub and
rebase. Same-mount faults remain quarantined; a write, flush, checksum, or
reread-proof failure latches its first ior and phase, forces read-only/dirty
state, and requires remount convergence. After a successful clean proof,
unmount withdraws `WRITER-CURRENT`, scrubs the complete dedicated writer,
rolls its arena back to fresh, clears its storage publication and binding
readiness, and detaches the block context. Busy and failed unmount paths retain
`V.BCTX`, the dedicated arena, and the relevant writer state for retry or
diagnosis; late terminal faults need not republish authority already withdrawn
after the final media proof.

Recovery is ordered as follows:

1. Validate ext4 superblock geometry, feature admission, all referenced
   bounds, and available metadata checksums without publishing a mount.
2. Locate journal inode 8, require its external-xattr pointer to be zero,
   validate the JBD2 superblock and matching UUID, and admit only the feature
   states above.
3. Before active replay, invalidate any cached protocol-home ownership
   certificate. Scan from the declared sequence/start, honoring escaped blocks
   and revokes.
   Replay only complete transactions whose descriptor, payload, revoke, and
   commit checksums validate.  An incomplete tail is ignored; corruption or
   an unsupported record refuses mount.
4. Write replayed home metadata and flush. Strictly reload and validate the
   authoritative post-replay filesystem, including legacy and modern orphan
   state, before changing recovery authority. A current full protocol-home
   ownership proof is required before any cleanup/reset write; retained-orphan
   completion obtains that proof before its own transaction.
5. Authenticate and measure the entire discovered legacy/modern union before
   its first cleanup write. A valid union containing any shape outside the
   currently recovery-supported closure is a stable unsupported refusal;
   corruption and insufficient bounded workspace remain distinct errors.
   Replay may be needed before this authoritative union is knowable, but after
   replay and strict reload such a refusal retains journal/recovery authority
   (`RECOVER`, `ORPHAN_PRESENT`, and `s_last_orphan` as applicable), publishes
   no mount, enables no writer, and performs no partial cleanup. If the whole
   union is supported, recover it transactionally and idempotently: drain the
   legacy head and successor chain first, then modern records in `(logical
   block, slot)` order, using one exact transaction per record and one reusable
   writer sized to the maximum exact record credit. Intermediate transactions
   retain recovery authority. An authenticated empty modern set requires no
   orphan inode or orphan-file-block mutation.
6. Checkpoint/reset and flush the journal. After final empty proof, use the
   witnessed clean landing to clear `RECOVER` and `ORPHAN_PRESENT` together,
   then retire its witnesses. A clean input carrying `ORPHAN_PRESENT` without
   `RECOVER` first establishes the recovery epoch through writer-free `AKW1`.

The current implementation covers steps 1 through 4 for
`64bit | checksum_v3` (`0x12`) with the optional standard `revoke` bit
(`0x13`). It also covers complete union discovery, authentication, and exact
measurement for step 5, then sequential recovery when every record fits the
currently supported linked-truncate or unlinked-delete slice. The count is
bounded by authenticated geometry, checked arithmetic, and caller-arena
capacity rather than a cleanup-specific constant. It also covers the step 6
empty landing. An
already empty modern set follows the writer-free branch for those
journals and for a clean feature-zero journal, which `AKW1` upgrades before
the clean landing. Replay first authenticates the
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
inode flags, generation, external-xattr ownership, and authentication inputs
for external extent nodes, journal inode 8 is deliberately pinned to generation
zero, a zero external-xattr pointer, and a complete inline depth-0 extent root:
one through four initialized extents, gapless logical coverage through journal
EOF, and bounded, pairwise-disjoint physical ranges. This is a
recovery-authority rule for the fixed internal journal, not a restriction on
ordinary inode maps or journal capacity beyond the inline extent format itself.
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

The requirements in this section define final profile conformance. Their
shared safety invariants apply to every staged slice, but an operation that is
not yet exposed does not block promotion of an unrelated crash-closed
operation whose complete request and recovery closure is qualified. Such an
intermediate promotion remains an operation claim, not a claim that the whole
profile is complete.

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
uses this transition after the complete union has been drained;
authenticated-empty modern orphan state uses its writer-free form. Detach,
timeout, or media
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
invariant-preserving replacement before any home write. A private writer
foundation now validates a caller-selected capacity tuple against authenticated
journal limits, binds it to a fresh dedicated arena, serves every
componentwise-contained transaction without arena growth, and owns coalesced
metadata, ordered-data, and revoke after-images. Its private `AKW1` two-copy
activation performs exact
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
six-write clean deactivation with terminal fault quarantine. The explicitly
named staged binding publishes qualified existing-block overwrite, strict
no-gap append inside an initialized partial EOF block, and allocation-backed
fill of complete in-size holes; the ordinary ext4 binding remains read-only and
every other mutation capability remains disabled. Modern
`ORPHAN_PRESENT` and a nonzero legacy
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
applicable data map is then authenticated.

The recovery baseline admits the orphan-file inode itself only with an extent
map of depth zero or one. A recognized depth-two-through-five extent tree or
legacy map is still validated completely so malformed authority remains
corruption; a structurally valid wider map then returns stable
`EXT4-D-RECOVERY` unsupported before cleanup or mount publication. This clamp
applies to recovery mutation authority, not to the generic read mapper.

Before its first cleanup write, mount authenticates and exactly measures every
record in the complete union. Each record must be either a linked truncation
already at zero size whose data map is an inline depth-zero extent root or an
exact empty legacy-format `i_block` array, or an unlinked deletion with an
empty or one-to-four-entry inline depth-zero extent root, a resident depth-1
root with one to four checksum-valid external leaves, or a legacy map using any of the
12 direct slots and one optional complete single-indirect block. The legacy
map may additionally use an optional double-indirect root with zero or more
occupied children when its exact canonical data-plus-map vector, plus any
present external-xattr owner range, fits the `2P+16` caller workspace; its
triple-indirect root remains zero. As a separate unlinked map family, slot 14
may name one allocated triple-indirect root whose full block is all zero while
the single- and double-indirect slots remain zero. Direct slots may be
occupied; their ordered data singletons precede the root's one map singleton
under distinct `LEGACY-SPARSE-TRIPLE` authority. The root contributes one block
to `i_blocks` and receives one exact revoke. This shape remains subject to the
same caller-workspace bound. As a second triple shape, when every direct slot
and the external-xattr pointer are zero, the root may contain exactly one
pointer to one allocated all-zero level-2 block. The ordered
`{ triple-root, level-2-child }` vector contributes two map blocks and revokes
under distinct `LEGACY-SPARSE-TRIPLE-CHILD` authority. The linked legacy-format
alternative
requires the `EXTENTS` flag clear and all 12 direct pointers plus the single-,
double-, and triple-indirect roots zero. It contributes no release ranges or
revokes, and its decoded `i_blocks` may contain only the contribution from an
authenticated retained external xattr block. An
unlinked target may retain any
authenticated nonnegative 63-bit size because deletion releases its complete
map and inode rather than preserving an EOF-selected tail. It may reference one
authenticated external xattr block. A refcount of one releases that
allocation; a count from 2 through ext4's 1024-reference limit retains it and
authorizes only an exact decrement plus checksum restamp. The authenticated
count must equal a complete role-aware scan of allocated `i_file_acl` owners,
while data and map-metadata aliases remain corrupt. Xattr value inodes remain
unsupported. Each extent entry may
have an initialized decoded length of 1..32768 blocks or an unwritten decoded
length of 1..32767 blocks, with
`logical_start + decoded_length <= 0xffffffff`; these are ext4 `ee_len` and
logical-domain bounds rather than cleanup caps. Logical and physical ordering,
aggregate data-plus-map-metadata-plus-xattr `i_blocks`, every exact release
range, and the zero inactive tail are authenticated and sealed together. Each
resident root key must match the first logical block in its complete leaf, and
the leaves must remain ordered and nonoverlapping across root bounds. Their
blocks join the exact release vector and each receives a revoke. Legacy zero
data-pointer slots are holes. Occupied direct slots, single-indirect entries,
and entries in every double-indirect child become ordered singleton data ranges
in outer/inner slot order. The optional single root, double root, and all
children follow as map singletons. Duplicate data pointers and data/map or
map/map aliases are corruption. An empty double root is admitted as one map
singleton. The all-zero triple root is admitted as one trailing map singleton
after zero or more direct data entries. Separately, with direct data and the
external-xattr pointer absent, the root may name exactly one allocated all-zero
level-2 child; root and child become two ordered map singletons. Repeated or
known-owner aliases are corrupt. A second distinct root child, any nonzero
pointer in the admitted child, child composition, or a present triple root
combined with a single- or double-indirect map remain unsupported. Exact
double-indirect authority larger than the caller workspace also remains
unsupported recovery. The optional xattr block is independent of both map
families and must not overlap their data ranges. If any record is outside
those per-record shapes, the complete
union refuses before writer allocation or cleanup mutation. The largest exact
current metadata credit across all records sizes one reusable writer, with one
derived extra slot when a shared-EA decrement could become a final-owner
release after an earlier orphan is deleted. Per-transaction credit remains
exact. The
count remains bounded by authenticated filesystem geometry, checked
arithmetic, and available caller-arena storage; cleanup adds no separate fixed
record-count constant.

The modern orphan inode used to locate those records is not restricted to the
target cleanup shape. Mutation admission validates its complete read-profile
extent tree or legacy direct/indirect map while the exact target ranges are
published, covering leaf storage, preallocation beyond EOF, external extent
nodes, and indirect metadata. It authenticates an external orphan-file xattr,
proves that block separately disjoint from the orphan inode's own complete map,
and rereads every logical orphan block through its location-bound checksum
tail before restoring the selected target record.

Cleanup selects the current legacy head until its authenticated successor
chain is empty, then selects modern entries in unsigned `(logical block, slot)`
order. One exact transaction removes each selected modern slot or advances the
legacy head to its retained successor, updates and checksums the target inode,
and for admitted deletions releases every exact data range, an optional unique
external-xattr block, and the inode allocation plus every touched descriptor
and super counter. An already-empty linked extent or legacy-format map releases
no storage. A shared xattr remains allocated and receives one exact
metadata after-image changing only `h_refcount` and `h_checksum`. The sealed
authority retains the map family, complete ordered range vector, xattr
`NONE`/`RELEASE`/`REFDEC` action, post-refcount, and retained CRC; adjacent
physical members may execute as one
checked allocation-accounting run without replacing those certificate
entries. A linked intermediate record under the legacy orphan protocol clears
its consumed `i_dtime` successor in the same transaction; the terminal
zero-successor/already-empty-map case avoids a no-op inode rewrite, while
linked records under the modern orphan protocol require `i_dtime` to be zero.
Every sealed record carries a `FINAL` or `MORE` certificate and the exact pre-transaction
total, modern, and legacy counts. Checkpoint reauthenticates that complete
prestate before home writes and proves afterward that the selected inode is
absent from the orphan union, the selected protocol and total counts fell by
exactly one, and the other protocol count is unchanged. `FINAL` proves an
authenticated empty landing; `MORE` proves a nonempty remainder and permits the same writer to be
rebased for the next record. `RECOVER` and any present `ORPHAN_PRESENT` remain
set across intermediate transactions and clear only after authenticated empty
landing. Structural chain, locator, ownership, or duplicate-membership failures
return corruption, while inode allocation and checksum failures preserve their
specific corruption detail. Failed-mount retries clear and reuse a retained
table when it is large enough rather than abandoning monotonic arena storage;
an insufficient caller arena or retained table fails without a second
allocation.

Every linked data range and every unlinked release range is admitted through
one combined filesystem-wide other-inode ownership scan before release. For an
unlinked target, up to four inline extents or 12 direct-slot singletons and the
optional external-xattr singleton are published together. An overlap through
another allocated inode's data or map metadata is a corrupt data-map refusal.
For a shared xattr, exact `i_file_acl` references are counted and must match the
authenticated refcount; any other role remains corrupt. The scoped proof is
bound to the context, inode, generation, map family, exact ordered data tuple,
xattr home, action, and raw refcount; it
may survive journal-only staging and emission but is invalidated before checkpoint can
write a home.
Whole-union qualification completes this proof for every retained supported
record before the first record is mutated.

An authenticated empty modern set is completed before mount publication only
when both protocol counts are zero. Writer-free `AKW1` and `AKE1`-qualified
`AKR1` clear `RECOVER` and `ORPHAN_PRESENT` together without changing an
orphan inode/file or legacy link and without allocating a private writer. The
implementation still fails closed on checksum-damaged incomplete tails and
refuses any unqualified per-record cleanup shape plus every user-visible
mutation. ACLs are exposed but not enforced, the real extent
fixture reaches depth 1 rather than the implemented profile limit of 5, and
the special-inode fixture does not yet contain a socket. Those qualification
and semantic limits remain explicit in the final profile release claim. They
block an operation that depends on them, but do not block an unrelated
crash-closed operation that cannot create or admit those states.
Focused discovery coverage exercises one- and two-inode legacy chains, a mixed
legacy/modern union, stable refusal with same-binding plan reuse, corrupt
legacy links and cycles, allocation/checksum failures, and cross-protocol
duplicate rejection without writes. Per-shape single-record cleanup
qualification covers modern and legacy empty/one-block cases across 1/2/4 KiB
geometry, controlled 1 KiB one-block write-prefix and durability-fence cases,
and pinned e2fsprogs inspection. Focused modern production coverage also
reclaims a checksum-valid sparse unlinked orphan with
`i_size = 2^32 + 777` and one initialized extent under the unchanged
1,200,000,000-step guard; its collected legacy counterpart remains pending.
The 1 KiB profile also qualifies a three-block initialized logical-offset
extent and a two-block unwritten logical-offset
extent crossing two data groups, including exact coalesced credit, per-group allocation
accounting, distinct nonzero payload preservation with no overlapping
data-home write, a byte-identical zero-I/O clean remount, and pinned e2fsprogs
inspection. Range-wide negative admission also covers a two-block extent with
only its second allocation bit clear and a three-block extent with only its
middle block aliased by a live inode. New two-record 1 KiB qualification drains
modern-only, legacy-only, and mixed unions through two sequential exact
transactions, reuses the maximum-credit writer, verifies final accounting, and
proves a byte-stable zero-I/O remount. Its separate pinned e2fsprogs 1.47.4
acceptance test remains pending; the baseline audit must either land it or
clamp this union shape to stable refusal. The
mixed case also crosses the second-transaction commit/home durability fence;
both the surviving prefix and the preceding durable snapshot converge on a
fresh mount and remount without another write. Pinned e2fsck 1.47.4 acceptance
of those repaired outputs is likewise required before this union shape enters
the frozen baseline. A
linked two-record legacy-orphan-protocol chain additionally qualifies real `MORE`, successor
rebuild, terminal `FINAL`, clean deactivation, exact media changes, and a
zero-I/O remount. Companion success cases give the linked head one or two
uniquely owned, separately described extents and qualify four-credit
`LEGACY_MORE` with an exact target-entry count of one or two. The two-range
root has logical starts zero and two; both ranges receive exact
block-bitmap/GDT/super accounting, retain distinct payload bytes without a
data-home write, reach terminal `FINAL`, and remount with zero I/O. That
legacy synthetic protocol-state fixture is the
`18 -> 21 -> 0` chain and intentionally has no namespace dirents for inodes 18
or 21; it is not an e2fsck oracle and is not claimed as an e2fsck-clean
namespace image. A parallel modern linked fixture qualifies exact five-credit
`MODERN_MORE` over one extent followed by one-credit `MODERN_FINAL`. It pins a
48-write/35-flush trace, exact first-home order, three primary-super writes,
two orphan-home writes, unchanged inode 21 and payload media, restored
allocation accounting, zero final slots, and a zero-I/O stable remount. It now
measures 1,185,669,720 guest steps under the existing 1,500,000,000-step
watchdog; the remount measures 55,255,628. It is likewise synthetic and not an
e2fsck namespace oracle. Separate focused dry-stage qualification admits an
exact empty legacy-format linked map under both the modern and legacy orphan
protocols in a two-record `MORE` prestate. It pins a clear `EXTENTS` flag, all
60 `i_block` bytes zero, zero `i_blocks`, target entry count zero, data-map kind
`NONE`, no release ranges or revokes, exact one-home modern and two-home legacy
metadata credit, the corresponding protocol after-images, staged verification,
and abort. A nonempty legacy-format linked map remains unsupported. This
focused evidence makes no production, crash-recovery, or e2fsck claim.
Whole-union refusal is qualified with an earlier
supported record followed by a valid two-extent record, and post-seal
count/mode substitution is rejected before home writes. A later selected
linked record whose final range aliases a live inode is also refused before
emission: modern qualification covers a two-entry inline root, legacy fills all
four format-defined entries, retry preserves the arena, and the ambient owner
table and certificate return clean. Unified discovery and cleanup now also
has positive modern-only and legacy-only two-record `DATA_DELETE_MORE`
coverage. Exact stage/abort oracles pin the six-credit modern and five-credit
legacy modes, locators, pre-union counts, target identity, and single released
range. Production mounts restore the canonical block/inode bitmaps and free
counts while retaining the initialized-inode high-water mark, reclaim both
inodes through `MORE` then `FINAL`, preserve the seeded payload, and remount
without I/O. The modern path measured 1,573,133,619 guest steps and the legacy
path 1,563,424,804 under their scoped 2,000,000,000-step watchdog; each stable
remount measured 55,738,449. Pinned e2fsck 1.47.4 acceptance remains a pending
release qualification gate. Full-inline-root qualification extends the modern
head to two separated initialized/unwritten ranges and the legacy head to all
four format-defined entries. Its exact stage/abort certificates bind the
complete ordered range vector, aggregate block count, entry count, and zero
inactive tail. Persistence-traced production measures 1,786,988,013 modern and
2,196,652,327 legacy guest steps under the scoped 3,000,000,000-step watchdog;
either clean remount measures 55,772,107. The corresponding direct
stage/seal/abort workloads measured 615,185,969 and 825,905,086 steps. These
watchdogs are qualification guards, not implementation capacities.
Resident depth-1 deletion qualification admits one through four external
leaves and every extent entry that fits each mounted block. A 13-entry
one-leaf regression crosses the old 12-slot boundary, while a four-leaf
fixture retains six data ranges followed by four leaf singletons and stages
their exact revokes under both orphan protocols. Focused modern production
reclaims all data and leaf blocks under the unchanged 1,800,000,000-step
watchdog without writing released payload or leaf homes. Deeper extent trees
remain unsupported for deletion.
Legacy-direct deletion qualification fills all 12 direct slots under both
orphan protocols while retaining 12 ordered singleton certificate/checkpoint
ranges and an explicit map-family discriminator. Sparse slots 0, 5, and 11
compact in slot order; duplicate pointers and mismatched `i_blocks` are corrupt,
while over-budget double-indirect maps and triple roots combined with single-
or double-indirect maps are unsupported. Direct data plus an empty triple root
is admitted under the separate sparse-triple authority described below.
Contiguous
singleton execution is combined only after exact-vector validation. Full
production cleanup with
`i_size = 2^32 + 777` measures 1,156,337,987 modern and 1,157,813,068 legacy
guest steps under a scoped 1,300,000,000-step watchdog and leaves released
payload bytes unchanged. A maximum-union stage/abort regression adds the
separate unique external-xattr block and exercises all 13 owner ranges in
577,776,029 steps. The focused modern/legacy pair now passes pinned
e2fsprogs 1.47.4 `e2fsck -f -n` after rebuilding both production cleanup
fixtures, completing in 200.43 host seconds. A separate single-indirect tier
fills all 12 direct slots plus the final
1 KiB pointer entry, retains data then pointer-node authority, stages the exact
node revoke, and rejects a node/data self-alias. With the larger shared
mutation workspace, focused modern production releases three data blocks plus
the pointer block in 1,313,528,725 guest steps under a scoped
1,500,000,000-step watchdog and reaches a byte-identical zero-I/O remount.
Legacy-protocol, maximum-fanout, external-xattr, crash, and pinned e2fsck
qualification remain pending for this tier. Sparse-double admission accepts
an optional double root with zero or more occupied children in root-slot order
when the exact canonical data, map, and present-xattr owner vector fits the
shared `2P+16` workspace. Focused empty-root staging retains the double root as
the exact one-map authority and one revoke. Multi-child preflight covers
`{ double root, child@2, child@7 }`; exact multi-child staging covers
`{ single root, double root, child@2, child@7 }` and retains all four map
revokes. A separate external-xattr composition covers `{ single root, double
root, child@2, external EA }`, retaining the three map revokes followed by the
EA revoke. A boundary check fills the exact 528-pair 1 KiB workspace with 524
data and four map ranges when no xattr is present, while a present xattr or one
more data pointer is unsupported. Child/data aliasing and duplicate child
homes are corrupt; over-budget double-indirect authority remains unsupported.
The sparse-double authority capacity is 528, 1040, or 2064 pairs at 1, 2, or
4 KiB. Focused sparse-double one-child modern production releases three data
and three map blocks in 1,431,070,159 guest steps under a scoped
1,600,000,000-step watchdog, preserves all six homes without a payload write,
and reaches a byte-identical zero-I/O remount. Multi-child and external-xattr
production, legacy-protocol qualification, crash qualification, and pinned
e2fsck acceptance remain pending for this sparse-double tier. Triple-indirect
admission covers either an all-zero root with optional direct
data, or exactly one allocated all-zero level-2 child when direct data and the
external-xattr pointer are absent. Additional root children, nonzero
grandchildren, child composition, and any single-/double-indirect composition
remain unsupported. Separate focused 1 KiB staging qualification covers one
unlinked inode with slots 0 through 13 zero, one allocated all-zero
triple-indirect root, no data, and root-only `i_blocks` under both orphan
protocols. The modern case completes in 534,968,795 guest steps under its
800,000,000-step watchdog and pins six metadata credits, one
revoke, and `MODERN_DATA_DELETE_FINAL`. The legacy case completes in
529,173,143 steps under the same watchdog and pins five metadata credits, one
revoke, `LEGACY_DATA_DELETE_FINAL`, and the exact legacy head and locator
authority. Both stage and seal retain zero target entries, one singleton
map-metadata release range, one map block, the root's exact revoke, and distinct
`LEGACY-SPARSE-TRIPLE` authority; preplan and staged verification pass, and
abort returns the writer and ownership scope clean with zero home writes. The
modern case additionally refuses checkpoint-certificate tampering with
target-entry count, range count, range span, or map kind. A second staging pair
adds one seeded direct singleton in slot 5 ahead of the same empty triple root.
Modern completes in 538,439,735 guest steps and legacy in 530,481,498 under the
unchanged 800,000,000-step watchdog. Both bind one target data entry, the exact
ordered `{ direct, triple-root }` release vector, one root revoke, and the same
protocol-specific credit and locator authority. A maximum-bound pair fills
direct slots 0 through 11 ahead of the root. Modern completes in 538,468,086
guest steps and legacy in 546,064,724 under the unchanged 800,000,000-step
watchdog. Both pin 12 target data entries and blocks, the exact 13-singleton
release vector with the root last, one map entry and block, the sole trailing
root revoke, six modern or five legacy metadata credits, zero home
writes, and clean abort. A further focused 1 KiB staging pair admits zero data
with one triple root naming one allocated all-zero level-2 child. The modern
case uses root slot 7 and completes in 597,938,156 guest steps; the legacy case
exercises the final legal root slot and completes in 560,613,920 steps, both
under the unchanged 800,000,000-step watchdog. Each binds zero target entries,
the ordered `{ triple-root, level-2-child }` release vector, two map blocks and
exact revokes, exact root-plus-child `i_blocks`, distinct
`LEGACY-SPARSE-TRIPLE-CHILD` authority, six modern or five legacy metadata
credits, zero home writes, and clean abort. Focused modern
checkpoint-certificate tests refuse partial and coordinated count/revoke
downgrades while the child type remains sealed. A fully coherent rewrite into
the root-only type remains structurally valid in isolation but is rejected by
staged-source reauthentication. Focused refusal coverage treats repeated or
root/direct/xattr-aliased children, an unallocated child, and incorrect
root-plus-child `i_blocks` as corruption; a second distinct child, a nonzero
grandchild, and direct-data or external-xattr composition remain unsupported.
Focused modern production checkpoints the
cleanup in 1,359,573,029 guest steps under the existing 1,500,000,000-step
watchdog. Its exact 37-write/24-flush trace has the same six cleanup homes as
the root-only modern shape: the primary super is written three times and the
GDT, block bitmap, inode bitmap, inode table, and orphan file are each written
once. Both map allocation bits and the target inode bit clear, free counters
return to their canonical values, and neither the pointer-bearing root nor its
all-zero child is written. A byte-identical zero-I/O stable remount completes
in 56,369,050 guest steps under the standard 1,200,000,000-step watchdog.
Legacy final-slot production parity completes in 1,379,226,136 guest steps
under the same production watchdog. Its exact 35-write/24-flush trace has five
cleanup homes: the primary super is written three times and the GDT, block
bitmap, inode bitmap, and inode table are each written once, with no
orphan-file-home write. It restores the same two map bits, inode bit, and
canonical accounting without writing either released map home, and its
byte-identical zero-I/O stable remount also completes in 56,369,050 guest
steps. Both resulting images pass the pinned e2fsprogs 1.47.4
`e2fsck -f -n` check. A representative modern F12 replay-home flush failure
reaches the injected fence in 1,088,178,921 guest steps under the standard
1,200,000,000-step watchdog. The F11-to-F12 interval contains exactly the six
expected cleanup-home writes and excludes both the triple root and its child.
Fresh mounts converge both permitted failed-flush durability views: the F12
writes surviving and only the prior F11 fence surviving. Each repair completes
in 271,891,434 guest steps, matches every cleanup home and both preserved map
homes to the known clean image, and never writes either map home. Each repaired
image then reaches a byte-identical zero-I/O stable remount in 55,920,483 guest
steps. Legacy F12 parity; representative F11 commit and F16 final-super fences,
followed by the full controlled write-prefix and durability matrix, under both
orphan protocols; broader 2/4 KiB geometry; and implementation, admission, and
qualification of additional triple-root child fanout remain pending for this
child-bearing tier.
The one-direct modern certificate refuses
missing or extra target counts, a missing range, widened data or root
singletons, swapped data/root order, and a downgraded map kind before its
restored authority and transaction tables pass. Root-only negative admission
covers single- or double-indirect composition, direct/root aliasing, and
aliasing the triple root with the external-xattr home. Focused single-record
production and byte-identical zero-I/O stable
remount qualification now cover the direct composition under both orphan
protocols. The modern journey checkpoints the cleanup in 1,305,226,732 guest
steps and the legacy journey in 1,318,122,553, each under the unchanged
1,500,000,000-step watchdog; both stable remounts complete in 56,367,757 steps
under the standard 1,200,000,000-step watchdog. Their exact
37-write/24-flush modern and 35-write/24-flush legacy traces retain the same
six or five cleanup homes as the root-only shape, clear the direct-block,
triple-root, and target-inode allocation bits, restore every free counter, and
never write either released block home. Pinned e2fsprogs 1.47.4
`e2fsck -f -n` accepts both recovered images. Crash qualification for the
direct composition remains pending. For the root-only shape, the single-record
modern production journey emits and checkpoints the cleanup in
1,301,139,781 guest steps under its 1,500,000,000-step watchdog. Its exact
37-write/24-flush trace has six distinct ext4 cleanup homes: the primary super
is written three times, while the GDT, block bitmap, inode bitmap, inode table,
and orphan file are each written once. The released triple-root home is never
written; its allocation bit and the target inode bit clear, all free counters
return to their expected values, and a byte-identical zero-I/O stable remount
completes in 56,367,001 guest steps under the standard 1,200,000,000-step
watchdog. The corresponding single-record legacy production journey completes
in 1,314,117,314 guest steps under the same 1,500,000,000-step production
watchdog. Its exact 35-write/24-flush trace has five distinct cleanup homes:
the primary super is written three times, and the GDT, block bitmap, inode
bitmap, and inode table are each written once; neither the orphan-file home nor
the triple-root home is written. It likewise clears the root and inode
allocation bits, restores every counter, and reaches a byte-identical zero-I/O
stable remount in 56,367,001 guest steps under the 1,200,000,000-step watchdog.
This establishes modern/legacy production and remount parity for the exact
root-only shape. Pinned e2fsprogs 1.47.4 `e2fsck -f -n` accepts both recovered
images. A representative F12 replay-home flush failure now qualifies both
protocols: the modern fault journey reaches F12 in 1,034,182,900 guest steps
and the legacy journey in 1,051,627,465, each under the standard
1,200,000,000-step watchdog. The F11-to-F12 interval contains exactly the six
modern or five legacy cleanup-home writes, excluding the triple root and, for
legacy, the orphan file. Fresh mounts converge both permitted failed-flush
durability views: the F12 writes surviving and only the prior F11 fence
surviving. Modern repairs complete in 270,728,727 guest steps and legacy
repairs in 266,212,919 for either view. The expected cleanup homes, orphan-file
home, and preserved triple-root home match the known clean image; no repair
writes the triple-root home, and each result reaches a byte-identical zero-I/O
stable remount in 55,919,141 steps. Other crash windows and the full crash
matrix remain pending. A separate
checksum-valid modern orphan-file fixture maps 31 logical blocks through a
preserved depth-1 external extent node. Linked production cleanup retains its
exact 34-write/24-flush trace, completes in 1,111,798,161 steps, and reaches a
zero-I/O byte-stable remount in 67,492,163; unlinked JFI admission completes
without writes in 240,654,652. A valid external xattr simultaneously named as
orphan-file preallocation is rejected as a corrupt data map in 121,741,936
steps with no residual ownership scope. Valid depth-2 extent and legacy
orphan-file maps are now fully validated and then refused without I/O; a
checksum-damaged depth-2 index remains corrupt. Unified discovery and cleanup
also has focused evidence for unique external-xattr deletion: direct
stage/seal/abort
passes for xattr-only and data-plus-xattr targets, and one modern
data-plus-xattr production mount reaches checkpoint with canonical allocation
accounting. Shared-xattr evidence now covers exact EA-only and data-plus-EA
stage/seal/abort under both protocols, corrupt owner-count mismatch, and
complete modern and legacy production decrements. Each run performs exactly
one retained-xattr home write and reaches a byte-identical zero-I/O remount;
modern pins 36 writes/24 flushes and legacy pins 34 writes/24 flushes. The seal
regression also proves the derived
one-slot writer-capacity delta and zero-CRC strict comparison. A two-record
modern fixture now exercises the corresponding live transition: the first
orphan decrements the only shared block from two references to one and the
second releases its allocation. Its exact credits are six and six inside a
seven-home writer; the 60-write/35-flush result restores allocation accounting,
preserves the freed refcount-one payload, and remounts with zero I/O. The
single-record production cases use a scoped 1,500,000,000-step watchdog,
moderately above the general
1,200,000,000 guard; it is qualification headroom, not a format or driver
capacity. The transition uses the existing 3,000,000,000 multi-record/data
watchdog and completed in 155.6 host seconds. Remaining negative/crash cases
and pinned e2fsck acceptance are still pending. Broader qualification is also
needed for chains longer than two,
later modern blocks and large orphan files, additional ownership and deletion
shapes, distinct-key hash collisions, and arena exhaustion or retained-too-
small retry behavior. The one-block linked chain now also qualifies crashes
inside its first `LEGACY_MORE` while successor 21 remains active. Eight
trace-derived write cuts tear the commit; the inode, GDT, block-bitmap, and
primary-super homes; and the reset-primary, witness-clear, and guard-retirement
writes. Seven durability cuts cross the commit, complete-home, reset-preseed,
reset-anchor, reset-primary, witness-clear, and guard-retirement fences; for
each failed flush, both the writes that survived and the preceding durable
snapshot independently converge on the successful final values for every
affected ext4 home and a write/flush-free remount. The payload is never a
home-write target, and inode 21 remains byte-exact through its terminal
`FINAL`; the synthetic fixture's no-e2fsck qualification remains unchanged.
The parallel modern fixture now qualifies two focused successor-aware cuts:
the uniquely modern orphan-file home is torn against its checksum-valid
`(0, 21)` intermediate after-image, and the complete-home failed flush repairs
both its surviving and prior-durable media. Each path reaches the successful
final homes and a write/flush-free stable remount; repair measures 771,167,177
guest steps. The remaining eight modern write prefixes and six durability
fences, modern/legacy `DATA_DELETE_MORE`, and multi-range `LEGACY_MORE` remain.
Activation, descriptor, and active-primary writes are
qualified by singleton matrices but are not duplicated here with an active
successor.

Writer promotion now has two gates. The staged-operation gate requires a
bounded, filesystem-consistent request/chunk contract, complete recovery
closure for every state the operation admits or can create, truthful ABI and
capability publication, operation-specific external-tool inspection, and the
representative crash and durability evidence for its distinct state-machine
topology. The existing-block size-preserving overwrite does not depend on
broader orphan cleanup shapes that it cannot create. Neither does the linked,
size-preserving in-size hole fill: its committed transaction binds the
allocation accounting and extent attachment, and it creates no orphan state.
Strict growth from the exact partial-block EOF inside an already initialized
block likewise changes only ordered data, `i_size`, and inode timestamps; it
does not allocate storage or create an orphan state.
Broader orphan shapes remain a final-profile backlog unless external evidence
or a next operation makes them reachable.

The final-completion gate additionally includes general profile-admitted
orphan/truncate/delete algorithms, qualified compositionally across structure
families and resource boundaries with interim topology clamps removed; the
complete namespace/data/metadata/xattr mutation surface; Akashic-authored
active, dirty-empty, and clean image interoperability; and the remaining
controlled power-cut/release matrices. The detailed pending cases below are
that closure inventory, not an assertion that every item is the next
prerequisite for the current linked-file write operations.

The staged regular-file callback provides one block-bounded transaction
primitive. A larger size-preserving caller range completes only its first
target logical block and returns legal short progress. A strict EOF append must
fit wholly between the current partial-block EOF and that same initialized
block's boundary; a request that would need another logical block refuses
rather than silently widening the admitted growth operation. Initialized
overwrite and strict initialized-tail append each consume `1/1/0`;
allocation-backed fill of a complete in-size hole consumes `4/1/0` from any
containing caller profile. This removes both a caller-size
limit and first-operation workspace selection from the qualified
size-preserving surface, supplies bounded allocation for the admitted hole
shape, and supplies strict growth inside an existing initialized tail. It does
not supply the general planners for allocation-backed or block-boundary EOF
growth, extent-root growth, arbitrary allocation geometry, or namespace
operations. Its progress and later-error behavior is qualified through
`VFS-WRITE?` and `VFS-WRITE-EXACT` on `EXT4-STAGED-WRITE-BINDING`. That
descriptor alone adds `WRITE` and omits `READ_ONLY`; the ordinary
`EXT4-BINDING`, `EXT4-CAPS`, and `EXT4-OPS` remain unchanged and read-only.
Positive-credit initialized overwrite retains conservative ordered-sector
prefix progress because its bytes were already reachable. Hole fill and strict
append use negative-credit, commit-granular progress: newly reachable caller
bytes remain unconfirmed until successful journal emission. Generic VFS
advances only by that operation's confirmed progress and blocks retry after
writer quarantine.

Strict initialized-tail append is current operation-admitted capability, not a
fixture-specific approximation of general append. It requires a linked regular
file with exact `EXTENTS` flags, an authenticated depth-0 or depth-1 map of the
existing final block, a non-block-aligned current EOF, no gap, and a complete
request contained in that block. The ordered full-block RMW preserves the
pre-EOF prefix and extent map, while the single inode after-image advances
`i_size`, updates `mtime`/`ctime`, and leaves `i_blocks` and free-space
accounting unchanged. The public hard-link journey grows inode 14 from 54 to 60
bytes with `APPEND`, publishes the shared vnode EOF and timestamps, reaches a
write-free stable ordinary remount, and passes pinned `debugfs` read/map/stat
and read-only `e2fsck` inspection. Gap growth and a request mixing in-size
overwrite with EOF growth refuse as `EXT4-D-WRITE-POLICY` before clock
sampling, journal activation, media I/O, progress, or vnode mutation.

The append-specific W7 and W16 cuts close both sides of its reachability fence.
At ordered-data home write W7, no journal commit has made the new tail
reachable: the public call reports zero progress, retains the old 54-byte EOF
and timestamps in the shared vnode, and faults the mounted writer. Fresh
recovery replays no append metadata, both hard-link names expose the original
file, and any raw appended tail prefix remains hidden beyond EOF. At inode-home
checkpoint write W16, the transaction is already committed: the call reports
the complete six-byte progress and cursor 60, immediately publishes EOF 60 and
the committed timestamps through the shared vnode, and returns the exact
partial/read-only quarantine error. The torn inode home is checksum-invalid;
fresh recovery replays exactly that one inode-table home without rewriting the
ordered data block, both names expose the committed 60-byte file, and the next
remount is byte-stable and write-free. These cuts add no allocation or orphan
topology; they qualify the distinct commit-granular publication rule of the
current append envelope.

For a depth-zero target, the current edit attaches the selected block by
sorted singleton insertion or exact logical-and-physical initialized
coalescing. A full resident root is admitted when coalescing preserves its
entry count.

The positive composition gate now crosses two distinct initialized blocks in
the real depth-1 extent file with one `VFS-WRITE-EXACT` request. The first
callback checkpoints the eight-byte tail of logical block 10; the second
checkpoints the sixteen-byte head of logical block 11 through the same writer.
The exact data and inode homes, two clock samples, final timestamp, unchanged
external extent node and map, write-free remount, pinned `debugfs` read/map,
and clean `e2fsck` result are all qualified. This is a multi-block transfer
made from independently durable block transactions. It is not an atomic
multi-block transaction and does not widen the per-chunk `1/1/0` profile. This
initialized-pair journey does not itself admit a hole, unwritten extent,
allocation, growth, or append.

A separate composition gate constructs a valid four-block sparse inode with
initialized logical blocks 0 and 3 and complete holes at 1 and 2. One public
`VFS-WRITE-EXACT` fills both holes as independently durable `4/1/0`
transactions through the same writer. Exact allocation, extent mapping,
`i_blocks`, free-space, cursor, time, ordered-home, full-file readback, clean
unmount, write/flush-free remount, pinned `debugfs`, and read-only `e2fsck`
checks all pass. This qualifies consecutive in-size hole composition without
claiming an atomic two-block transaction. The first allocation inserts a
singleton and the second coalesces into it, forming a length-two initialized
extent while the inline root remains at three entries. This qualifies adjacent
initialized coalescing as part of the current hole-fill operation; only an
unmergeable full root still requires extent-root growth.

The staged-operation crash evidence includes the final commit flush of a
second write through the reused public writer. The successful trace derives
that boundary as F22 after the second ordered-data body fence and before its
inode checkpoint. A flush failure leaves both durability views with both data
edits and the first inode home. Recovery replays exactly one inode home when
the final commit survived, and zero when only the prior fence survived; the
latter still completes active-journal recovery. Both paths clear recovery
authority, preserve the appropriate exact timestamp, and remain unchanged on
a second clean remount. This representative reachable-state proof complements
the existing torn inode-home checkpoint recovery without turning promotion
into an exhaustive ordinal matrix.

The same staged one-block overwrite accepts an existing initialized block
through an authenticated external extent tree rather than requiring an inline
depth-0 root. The real supplemental depth-1 fixture qualifies data/inode
checkpoint and readback while leaving its extent node byte-exact. A
checksum-valid target leaf that aliases the selected data block to its own
external extent node is rejected before media mutation. The scoped full-tree
audit checks every target data range and external node against journal and
static-metadata roles, requires exactly one leaf reference to the selected
physical block, and rejects that block as node metadata. A valid node relocated
into the journal ring and a selected block duplicated across distinct leaves
are both qualified refusals. One paired reverse-owner scan covers both the data
and inode-table destinations, including other inodes' external xattrs and map
metadata. The reader retains its bounded depth-5 validator, while staged
mutation admits only authenticated depth-0 and depth-1 trees.

The per-operation proof is now complemented by a mount-scoped protocol-home
certificate. Before activation or any private protocol write, every allocated
inode other than authenticated journal inode 8 is parsed through its complete
data/map-metadata/external-xattr ownership surface and refused if any range
intersects the exact journal tuple or the filesystem block containing the
primary superblock. Journal inode 8 is excluded only because its exact inline
tuple and zero external-xattr pointer are independently authenticated. A dirty
replay clears the certificate before preflight and reacquires it only from the
strictly reloaded, root-validated current filesystem before reset/clear/retire
writes; a retained orphan reaches its cleanup proof with the certificate still
clear. Hostile checksum-valid aliases through another inode are qualified for
both a journal-ring block and the primary-super home. This closes that
reverse-ownership release gate without changing the remaining operation
planning, mutation-surface, and interoperability gates.

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
