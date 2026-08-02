# akashic-vfs-ext4 — checksummed read-only ext4 binding

This VFS ABI 1 binding reads filesystems in the pinned
`akashic-ext4-rw-v1` profile from one explicit KDOS volume. It also implements
a bounded mount-time recovery slice for an internal checksum-v3 JBD2 journal
and a private one-transaction durable-emission slice. It never uses the
ambient filesystem volume: reads and the narrowly scoped recovery, activation,
private-emission, checkpoint, and clean-deactivation writes go through checked
volume operations relative to the supplied `VOL-RAW` or `VOL-SLICE` object.
The published binding remains read-only and has no user-visible mutation
fallback.

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
  except for a dirty prefix tear with a committed valid repair payload or the
  narrowly authenticated torn-clear state described below;
- the pinned 1/2/4 KiB geometry, 64-byte descriptors, 128/256-byte inode
  forms, flex size, feature policy, admitted clean/recovery state, and all
  volume bounds;
- every primary group descriptor and every initialized block/inode bitmap
  checksum, while honoring the admitted uninitialized-group flags;
- every sparse-super backup copy and its invariant geometry, features, UUID,
  group number, journal-inode backup tuple, and checksum, plus every backup
  GDT descriptor CRC and immutable metadata location;
- allocation and checksum of each consumed inode;
- the internal JBD2 journal superblock, size-derived inode map, and matching
  UUID. Superblock `s_jnl_backup_type` must be `1`; its checksum-covered 68-byte
  `s_jnl_blocks` tuple must exactly reproduce inode 8's `i_block`, size-high,
  and size-low fields. Journal inode 8 is pinned to generation zero and an
  inline depth-0 extent root containing one through four initialized extents
  with exact gapless EOF coverage and bounded, nonoverlapping physical
  ranges. This recovery-authority constraint does not narrow the general
  file reader's extent-depth or legacy-map support. The inode size must be a
  nonzero whole number of filesystem blocks, fit JBD2's 32-bit `s_maxlen`,
  and not exceed the filesystem block count. Mount expands that authenticated
  inline tuple directly into an exact map plus a half-full power-of-two
  uniqueness table from the caller's arena; arena exhaustion returns
  `VFS-E-NOMEM` rather than imposing a journal-size constant. It rejects holes,
  mappings beyond EOF, out-of-range or aliased blocks, and any journal block
  that overlaps a descriptor-authenticated block/inode bitmap or inode-table
  range, any deterministic sparse super/GDT/reserved-GDT range, or inode-8
  bootstrap metadata; and
- the designated group-1 recovery chain: checksum-valid sparse backup super,
  checksum-valid backup-GDT group-0 descriptor, live inode-8 allocation bit,
  checksum-valid inode 8, and exact tuple equality. Dirty bootstrap uses this
  chain without trusting the primary GDT or aggregate free-space counters.
  Replay may not target the designated sparse super or backup-GDT span.
  Authenticated primary-super payloads must retain `RECOVER`, valid checksum
  and seed, all next-mount profile checks, bounded aggregate counters, and all
  witness invariants. A payload for the first primary-GDT block containing
  group 0's descriptor must retain the witnessed bitmap/table locators and
  descriptor checksum. An inode-bitmap payload must keep inode 8 allocated,
  and an inode-table payload must preserve inode 8's exact 128- or 256-byte
  record while allowing neighboring records to change; and
- every modern orphan-file block through its authenticated inode size, bounded
  by filesystem geometry, including the physical-location-bound per-block
  CRC32C tail. The scanner counts and indexes all nonzero entries in an
  arena-derived half-full power-of-two table while rejecting duplicates, then
  authenticates each allocated inode, bounded `i_dtime`, type, size, flags,
  and applicable data map. Linked entries must be truncatable. An authenticated
  empty modern set is completed before mount publication without changing the
  orphan inode or any orphan-file block. A nonempty set is still refused after
  preflight because journaled truncate/delete and slot cleanup are not
  implemented.

The driver contains its own reflected CRC32C implementation. Akashic's public
`CRC32C` word is deliberately MSB-first and is not interchangeable with the
ext4 checksum contract.

Known refused feature bits return format-domain `VFS-R-UNSUPPORTED` with
`EXT4-D-FEATURE`. `ORPHAN_PRESENT` is admitted through any required
committed-journal replay and strict reload. If the authoritative modern orphan
set is empty, mount completes the transient recovery state before publication:
a `RECOVER`-clear input first enters a tear-safe recovery epoch through
writer-free `AKW1` activation while preserving `ORPHAN_PRESENT`; `AKR1`
then lands an empty checksum-v3 journal and a checksummed primary superblock
with both transient bits clear. A nonempty modern set returns the stable
`EXT4-D-RECOVERY` refusal. A
nonzero legacy orphan chain, a dirty state without `RECOVER`, or a recovery
state outside the implemented JBD2 slice likewise returns a stable refusal.
Checksum and structural failures return format-domain `VFS-R-CORRUPT`. No such
failure can leave a mounted or ready object.

## Bounded mount recovery

The implemented recovery slice admits an internal journal with the
`64bit | checksum_v3` incompatibility mask (`0x12`) and its standard optional
`revoke` bit (`0x13`), using JBD2 CRC32C type 4. It validates the complete
journal tuple map, descriptor blocks, 64-bit tags, tagged payloads, escaped
payload handling, revoke blocks, commit blocks, sequence progression, and
checksums in a non-mutating pass. It counts only revokes whose enclosing
transaction has an authenticated commit, builds the latest-sequence revoke
index in a second non-mutating pass, and then replays only unrevoked home
blocks from the committed prefix. All passes use the immutable map expanded
from the checksum-valid group-1 tuple; no external extent node, legacy pointer
block, primary descriptor, or block-allocation bitmap is needed to expand or
locate that tuple during dirty bootstrap. The witnessed inode-allocation
bitmap remains part of authenticating live inode 8. Before any journal read,
every tuple extent is also proven disjoint from all backup-GDT-described
bitmap and inode-table ranges and all deterministic
sparse-super/GDT/reserved-GDT ranges.

The exact map, its uniqueness table, and the recovery-only half-full
power-of-two revoke index are derived from authenticated journal geometry and
the exact committed revoke-record count. Their initial allocation is bounded
by the VFS arena. Failed-mount retries on the same binding clear and reuse that
index; they never abandon an arena allocation to grow it. The eventual
transaction writer therefore negotiates separate reserved workspace rather
than inheriting this recovery allocation policy. Transaction-ID comparison
remains correct across 32-bit sequence wrap. A structurally valid incomplete
tail identified by the next header or sequence discontinuity is discarded.
Preflight also treats a matching-sequence `SUPER_V2` header as the known
prefix-torn anchor boundary only when the complete block passes the anchor
checksum, geometry, witness, and self-location checks; replay never admits it
as a transaction record. A checksum-damaged descriptor, payload, revoke, or
commit is currently refused rather than classified as a torn tail. Modern
orphan discovery runs after replay and strict reload. The authenticated-empty
branch completes recovery metadata without changing orphan-file contents;
nonempty transactional truncate/delete and slot clearing are not yet admitted.
Pinned
qualification covers multi-record hash collisions, malformed revoke geometry
and ownership, a revoked primary-super repair, and transactions relocated
above logical journal block 4095 and across the end of an 8192-block ring.
Scan and replay therefore use authenticated ring geometry rather than
fixture-sized cursor assumptions.

The type-1 journal tuple is validated without consulting allocation metadata,
then cross-checked through the designated sparse-super/backup-GDT witness to
the checksum-valid live inode. The whole designated witness range is
replay-frozen. Mutable primary authority may be replayed only when the
authenticated candidate preserves the next retry's locators and inode-8
identity. A primary-super candidate must also satisfy the same pre-witness
profile and counter bounds as an ordinary checksum-valid mount, so a crash
after its home write can still reach the journal on the next retry. If the raw
primary super checksum is torn and no private `AKR1`
witness exists, preflight must find a valid primary-super replacement and then
authenticate that transaction's commit before the replay pass can perform its
first home write. A candidate in an incomplete tail grants no authority.

Recovery requires a physically writable, flush-capable volume. Home writes are
flushed and the resulting filesystem is strictly revalidated, including the
authoritative orphan scan, while `RECOVER` remains set. Only an authenticated
empty orphan result reaches the recovered-super endpoint. At the first
noncommitted journal slot, the driver first
writes and flushes the complete intended reset image with byte zero invalid.
It then restores byte zero, writes and flushes the valid recovery anchor, resets
the primary journal superblock and flushes again, and finally clears ext4
`RECOVER` and `ORPHAN_PRESENT` together and flushes the primary ext4
superblock. The preseed and valid anchor
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

An Akashic-emitted active transaction uses a standard checksum-v3 journal
superblock in both journal block 0 and a ring guard `G`. Its `s_head` names
`G`, while `s_start` names the following ring block where the descriptor
stream begins. The private padding is zero, so the active primary and guard
remain ordinary JBD2 superblocks rather than a new feature format. If the
primary is prefix-torn, the unchanged old/new `s_head` locates the one exact
guard; recovery reconstructs the preceding empty primary and requires a
full-block sequential-prefix proof before accepting the guard.

After replay, the active-to-empty reset reuses `G` as its reset anchor. This
`AKR1` subtype carries an `AKG1` value/complement pair, the active sequence and
complement, and the CRC32C and complement of the complete active filesystem
block. Those authenticated predecessor fields let a later mount reconstruct
the exact active primary if the primary write tore between the active and
reset images, prove the full-block prefix, and continue forward through the
ordinary reset/clear protocol.

An empty-to-reset landing uses the same private words for an `AKE1` subtype
when the old journal is proven empty and its normalized head names the reset
anchor. `AKE1` stores the old raw head and complete-block CRC32C with
complements. Its anchor sequence authenticates the preceding sequence modulo
32-bit wrap. Recovery can therefore reconstruct the exact old standard
primary—including a raw zero-head spelling and 2/4 KiB padding—and prove an
early reset-primary prefix even before the `AKR1` marker reached journal block
0. Ordinary resets without that empty-predecessor relation retain the
fail-closed zero private tuple.

## Private clean-to-RECOVER activation

The private writer can now activate an empty clean journal before its first
transaction. This is not a transaction commit and is not reachable through a
public VFS mutation operation. Before the first media write, activation binds
the writer context and current I/O target to the same attached VFS and volume,
rereads journal block 0, and compares its identity and complete writer-relevant
state with the mounted primary: header form, block geometry, sequence, start,
raw and normalized head, feature masks, UUID, user/dynamic-super fields,
transaction limits, checksum fields, and wrapped next transaction ID. This
exact rebinding is required even for a feature-zero journal, whose old primary
has no JBD2 checksum and therefore must not have stale identity or geometry
silently authenticated by the transition.

Activation uses a private `AKW1` witness to change the journal to
`64bit | checksum_v3 | revoke` (`0x13`) and the ext4 primary from clean to
`RECOVER`. The witness extends the existing private JBD2-padding convention
through offset `0x87`. It records the clean and dirty ext4-superblock checksums
with complements, the exact guard logical block, and the old journal feature,
head, checksum-type, and checksum fields needed to prove a torn installation.
The writer first preseeds the guard block with the complete activation image
except for invalid byte zero and flushes it. It then writes and flushes the
valid guard, writes and flushes the identical activation primary at journal
block 0, writes and flushes the checksummed ext4 `RECOVER` endpoint, and
rereads all three durable images. Only after that proof does it remove `AKW1`
from the primary, flush, zero and flush the guard, and publish the in-memory
write-active state. Successful activation deliberately leaves an empty,
standard checksum-v3 journal with ext4 `RECOVER` set for the private
transaction emitter.

Crash resolution is forward-only. A sequential-prefix tear while installing
the primary is advanced to the exact `AKW1` guard, and a clean or torn ext4
primary is advanced to the authenticated dirty endpoint; a tear while clearing
`AKW1` is advanced to the standard checksum-v3 primary. The resolver then
retires the activation guard and passes the empty dirty journal through the
existing `AKR1` reset/clear landing, which returns the filesystem to a strictly
validated clean mount without replaying a user transaction. A crash before the
activation primary is installed leaves the old clean primary authoritative and
the unreferenced guard harmless.

Mount-time empty-orphan completion is a writer-free caller of the same
activation primitive. It passes `writer|0` and borrows
`_EXT4-C.DIR-BLOCK` and `_EXT4-C.TREE-BLOCK` for the two block buffers. It
does not call `_EXT4-JWR-ENSURE`: private writer storage is allocated once
from the monotonic mount arena, and later reuse requires identical metadata,
data, revoke, and total geometry. Automatically allocating a small recovery
writer would make a later production-sized reservation fail with
`VFS-E-CONFLICT`. The writer-free path establishes recovery authority,
immediately proceeds through `AKE1`-qualified `AKR1`, allocates no writer, and
exposes no write-active endpoint through the successfully mounted VFS.

For writer-backed activation, once the first media phase has begun, any write,
flush, checksum, or reread-proof failure latches the first ior and exact phase
in the writer, marks it faulted, and forces the VFS read-only and dirty. The
same writer cannot retry activation or begin a transaction; remount recovery
resolves whichever durable witness state survived. Writer-free mount recovery
retains no synthetic writer fault: it returns the media error with the binding
still unpublished, and a fresh mount resolves any durable witness prefix.
Failures in fresh-primary rebinding occur before mutation and are rejected
without creating activation authority.

## Private transaction staging and durable emission

The driver has a private, non-published foundation for the ordered JBD2
writer. A caller supplies metadata, ordered-data, and revoke
capacities; the driver derives exact half-full hash geometry and the complete
byte requirement, makes one checked allocation from the binding arena, and
publishes the workspace only after its internal layout is complete. The same
geometry is reused without arena growth. A mount-generation `WRITER-CURRENT`
publication bit prevents preserved workspace bytes from becoming transaction
authority during a retry. Mount clears it before rebuilding media-derived
state; a failed mount neither republishes nor scrubs the old staged,
`COMMITTED`, or faulted state. Only after recovery, strict reload, root
validation, and attachment validation reach an authenticated clean endpoint
does mount shape-check the allocation, zero its owned tables and images,
rebase it to the persisted journal head and wrapped next transaction ID, and
publish `IDLE` and then current ownership. Same-mount faults remain sticky.
Successful clean unmount clears `WRITER-CURRENT` and binding readiness before
detaching the block context; the retained allocation remains shape-inspectable
but no longer has transaction authority. Busy or failed unmount retains the
block context; a busy entry retains current authority, while a terminal fault
preserves its exact phase for diagnosis. Different requested geometry is
refused rather than leaking another monotonic-arena allocation.

The production workspace contract is not yet ratified. Public operations
cannot size this allocate-once object from whichever mutation happens first,
because a later operation with larger legitimate credits would then conflict.
Writable publication therefore also requires geometry-derived sizing from the
authenticated journal and caller-provided storage, plus bounded transaction
chunking for operations that cannot fit one reservation. It must not introduce
an arbitrary operation-count ceiling.

A private transaction reserves journal credits and ring space before accepting
any block. It owns complete block-sized metadata and ordered-data after-images,
coalesces repeated writes by home block, records image CRC32C, and keeps
cancelled metadata and revoke entries indexed so probe chains and consumed
credits remain stable. Metadata and revoke operations cancel and reactivate
one another without deleting hash slots. One home block cannot simultaneously
carry active metadata and ordered data, or active ordered data and a revoke.
Abort zeroes staged authority, refunds the reservation, and reuses the same
arena storage.

One fully staged transaction can now be emitted durably. Its ring reservation
contains one standard active-super guard plus the descriptor blocks, metadata
payload blocks, revoke blocks, and one commit block. The guard consumes ring
space but is not a JBD2 transaction record, so `s_max_transaction` is checked
against the reservation excluding that guard. The ring's separately excluded
spare is retained as the exact zero sentinel immediately after the commit;
ordered-data blocks are bounded separately by `s_max_trans_data` and are not
journal-ring records.

Emission first writes ordered data to its home blocks. It then writes the
checksummed descriptor/payload/revoke body, preseeds the exact intended commit
block with byte zero invalid, writes the following sentinel as an all-zero
block, and flushes the whole body. The invalid preseed and final valid commit
differ in exactly byte zero. The writer next installs an invalid-byte preseed
of the standard active super at guard `G`, flushes, installs and flushes the
valid guard, installs and flushes the identical active primary, and rereads
both copies for exact proof. Only then does it write and flush the valid commit.
The active primary and guard use transaction sequence `TID`, `s_start` at the
descriptor after `G`, `s_head=G`, checksum-v3/revoke features, and zero private
padding.

Success publishes `COMMITTED` only after the final commit flush. Ordered data
is already at home, while metadata home blocks remain unchanged. All staged
metadata, data, and revoke entries and their after-images remain owned by the
writer; retry, abort, and a new transaction remain busy until checkpoint
finishes. Checkpoint first revalidates the complete workspace, performs an
ordinary complete on-media scan, and then repeats that scan in lockstep with
the retained emitter order before issuing a home write. The active primary and
guard, transaction ID, start/head/cursor, every descriptor home and unescaped
payload, every revoke identity, the commit, the exact zero sentinel, and the
retained entry/image CRCs must describe the same single committed transaction.
A mismatch fails before home mutation.

After that preflight, checkpoint writes each retained active metadata
after-image to its home block. Ordered data is not rewritten because emission
made it durable before commit, and revoked/cancelled entries grant no home-write
authority. All metadata home writes cross one volume flush, followed by a
strict reload and root validation, before any journal block or reservation can
be reused.

Journal release preserves the mounted write-active state. It reuses the active
guard `G` as an `AKG1`-qualified `AKR1` reset anchor, publishes and flushes the
empty witnessed primary, then removes the primary witness and flushes it while
the exact dirty ext4 superblock still has `RECOVER` set. During witness removal,
`G` proves an admitted sequential prefix; after the ordinary empty primary is
durable, ext4 `RECOVER` is the standard recovery authority. Only then is `G`
zeroed and flushed. Thus checkpoint does not clear `RECOVER`, does not clear
the in-memory write-active publication, and does not run clean-to-`RECOVER`
activation again.

An exact final reread rebases the same workspace to the reset journal
head/sequence, restores the full ring reservation, scrubs retained transaction
authority, and publishes `IDLE`. The next transaction immediately reuses that
workspace and ring, including sequence wrap, without another arena allocation.
Clean deactivation is the separate public-unmount operation described below,
not part of per-transaction space release.

## Clean write-active deactivation and unmount

Public unmount applies the writer state rather than silently discarding it:

| Entry state | Result |
| --- | --- |
| Clean and non-write-active, with or without retained writer storage | Prove the clean endpoint and detach without media writes. |
| Write-active, transaction-clean `IDLE` | Perform the clean landing and detach only after its final proof. |
| `COMMITTED` | Authenticate and checkpoint the retained transaction, require the resulting clean `IDLE` state, then deactivate. |
| `STAGING`, `ACTIVATING`, `EMITTING`, `CHECKPOINTING`, or `DEACTIVATING` | Return `VFS-E-BUSY` with lifecycle, block context, readiness, and writer authority retained. |
| `FAULTED` | Return the exact first writer error, retain the block context, and make the VFS terminal `VFS-L-STALE`. |
| Malformed/missing authority or a non-clean final endpoint | Return corruption, retain the block context, and make the VFS terminal stale. |

`VFS-UNMOUNT-F-FORCE` bypasses only the core VFS open-handle refusal. It does
not bypass a checkpoint, a busy writer state, clean landing, final proof, or
failure quarantine.

Dirty-empty `IDLE` deactivation begins with a flush, strict reload, and root
proof. It then uses the existing `AKR1` protocol: W1 installs an invalid-byte
reset-anchor preseed; W2 installs the exact valid `AKE1`-qualified anchor; W3
installs the witnessed empty primary; W4 writes the checksummed clean ext4
superblock with `RECOVER` and `ORPHAN_PRESENT` clear; W5 installs the standard
witness-free primary; and W6 retires the anchor. The protocol has six writes
and seven flush barriers, including the initial preflight flush. `AKE1`
authenticates the old empty primary across any W3 sequential-prefix tear.
Immediately before W5,
the driver rereads the raw primary and named anchor, revalidates their witness
and ext4-super binding, and requires full-filesystem-block equality. A final
strict reload, root and attachment proof precedes writer scrubbing, dirty-bit
clear, publication withdrawal, and block-context detach.

Any failure after deactivation enters its media protocol retains the first
ior and exact phase, faults the writer, forces read-only/dirty state, preserves
`V.BCTX`, and makes that VFS terminal stale. Pre-dispatch attachment drift or
recovery-media refusal instead makes the VFS terminal stale without entering
deactivation or issuing media I/O. The same instance cannot retry or claim a
clean detach. A fresh VFS mount must classify the surviving authoritative
endpoint or admitted sequential prefix and converge forward. That fresh VFS
is mounted non-dirty while the original VFS remains terminal stale; a
successful clean-unmount endpoint remounts without recovery writes. Once the
clean ext4 superblock and standard witness-free primary are authoritative,
leftover anchor bytes from a late failed landing are non-authoritative and a
fresh mount need not read or zero that old slot.

The bounded 1 KiB qualification uses 63 metadata after-images and 126 revokes,
the first counts that require two descriptor batches and two revoke batches
for that geometry. These are test thresholds, not implementation capacities.
With the guard at `s_maxlen-3`, the first descriptor's payload run crosses
from logical block 4095 to logical block 1. Independent media checks cover
every tag, UUID slot, escaped payload, revoke, checksum, commit, and sentinel;
a clean remount then replays all 63 metadata images, observes zero revoke-tag
hits while leaving all 126 revoke-named homes unchanged, resets the journal,
and rebases the existing workspace without arena growth.

Any write, flush, checksum, or reread-proof failure after emission begins
latches the first ior and exact phase, faults the writer, and forces the VFS
read-only and dirty. The same mount cannot retry or erase that uncertainty.
Remount classifies the durable commit endpoint, replays only an authenticated
commit, and converges through the standard active guard and `AKG1`-qualified
reset path. Only a successful same-session checkpoint at the authenticated
dirty/empty endpoint, or a final authenticated clean remount, may scrub and
rebase the preserved writer workspace.

The object layout, counts, embedded pointers, ring fields, phase/fault state,
image checksums, and hash indices are revalidated before they can drive a
fill, copy, lookup, or media write. The public binding and capability mask
remain read-only. Legacy-orphan discovery, transactional cleanup for both
orphan mechanisms, the complete user-visible mutation layer, external-tool
inspection of Akashic-created transactions/endpoints, and the remaining
release gates must all land before public write capabilities can be enabled.

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
read for the hole. `SYNCFS` and `FSYNC` are safe no-ops while the binding is
read-only; before writable capabilities are exposed they must drive the
required transaction commit/checkpoint durability rather than remain no-ops.

`EXT4-BINDING` has `VFS-BF-NEEDS-VOLUME`, `VFS-BF-READ-ONLY`, and
`VFS-BF-STABLE-IDS`. The VFS rejects all mutation before binding dispatch.
`VOL-WRITE` and `VOL-FLUSH` are used only by mount-time recovery, private
activation and emission, same-session checkpoint, and clean deactivation;
they are not exposed as writable VFS capabilities.

## Deliberate remaining limits

This is completion of the bounded clean read side, not completion of the
writable profile. The remaining boundaries are:

- POSIX ACL xattrs are returned as raw bytes, but generic permission
  enforcement is not claimed;
- the real external-tool extent fixture has depth 1 even though the reader
  validates and traverses the profile limit through depth 5;
- the real special-inode fixture covers FIFO, character, and block devices,
  but not a socket inode;
- replay currently requires checksum-v3/64-bit journal records, supports
  checksummed 64-bit revoke records, and fails closed on checksum-damaged
  incomplete tails;
- the recovery profile deliberately requires the group-1 sparse-super/GDT
  witness and the checksum-covered inline depth-0 journal tuple; external
  journal-map nodes are not recovery authority;
- a checksum-torn dirty primary super fails closed unless a fully committed
  transaction carries its valid invariant-preserving replacement, or the
  private `AKR1` clear witness proves the exact cleanup state described above;
- private transaction staging, clean-to-`RECOVER` activation quarantine, one
  ordered descriptor/payload/revoke/commit emission, full-log checkpoint
  preflight, retained-image home writes, dirty-empty journal release, and
  immediate sequential workspace reuse, clean write-active deactivation, and
  public clean-unmount integration are implemented as private durability
  foundations;
- modern orphan-file discovery, inode preflight, and authenticated-empty
  `ORPHAN_PRESENT` completion are implemented. Empty completion mutates only
  journal recovery state and the checksummed primary-super transient bits; it
  does not change the orphan inode/file, allocate writer workspace, or expose a
  user-visible write. Nonempty modern cleanup, legacy-chain discovery and
  cleanup, and every user-visible mutation operation remain unimplemented;
- modern preflight still needs qualification for journal-replayed orphan
  afterimages, later blocks and files beyond the former 4096-block limit,
  unlinked and structurally invalid referenced inodes, hash collisions, and
  arena retry/exhaustion behavior; and
- empty completion has 1/2/4 KiB happy-path and write-free-remount coverage,
  plus same-binding writer-free W3 retry and four controlled prefix cases:
  1 KiB AKW1 W3 primary, 1/4 KiB AKE1/AKR1 W9 early primary, and 1 KiB AKR1
  W10 recovered-super. Broader recovery-anchor interoperability and the full
  controlled power-cut matrix still require external-tool and emulator
  qualification.

No write capability will be advertised until complete replay/orphan recovery,
the full ordered-data mutation surface, external-tool mutation checks, and
power-cut qualification land.

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
