# akashic-vfs-ext4 — checksummed read-only ext4 binding

IMPORTANT: STEP CEILINGS ARE NOT CRITICAL COMPARED TO CRITICAL PROPER FUNCTIONING. DO NOT SCRUB PROPER FUNCTIONALITY FOR ARBITRARILY SET STEP LIMITS. STEP AND OTHER LIMITS DETERMINED BY IDENTIFIED SYSTEM RESOURCES AND MONITORING.

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

## Cold source qualification

The real-image harness cold-compiles the production ext4 Forth source into
the restored FAT/VFS snapshot. It does not use a compiled shard or warm cache.
To avoid making UART echo volume an implementation-size limit, the host
injects each compacted physical source line into the BIOS `FSLOAD`
source-buffer span and invokes an immediate `EVALUATE-CHECKED` shim;
`EVALUATE-FINISH` verifies that no definition remains open. The 255-byte
transport bound applies to one injected physical line, not to total driver
size.

The checked-in 800,000,000-step value is a qualification watchdog and
measurement guide, not an ext4 implementation capacity or a reason to weaken
functionality. If correct source legitimately outgrows it, the budget must be
revisited from measured system resources. The harness still performs a real
cold source build and requires the `EXT4-SOURCE-READY` marker with no Forth
diagnostic. The current source passes that cold-build qualification.

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
- the legacy orphan chain rooted at `s_last_orphan` and every modern
  orphan-file block through its authenticated inode size, bounded by filesystem
  geometry. Legacy traversal authenticates each allocated, checksummed inode,
  follows its `i_dtime` link, and uses the admissible inode-number range as a
  nontermination bound. Modern traversal authenticates each
  physical-location-bound per-block CRC32C tail. The exact combined active
  count sizes one arena-derived half-full power-of-two plan. Each occupied
  four-cell record retains the inode, protocol, and cleanup locator: legacy
  `{ inode, legacy, next, 0 }` or modern
  `{ inode, modern, logical-block, slot }`. One shared hash enforces
  union-wide inode uniqueness, including modern duplicates and cross-protocol
  reuse; the bounded legacy walk independently rejects cycles. The scanner
  then authenticates every referenced inode's bounded `i_dtime`, type, size,
  flags, and applicable data map. Linked entries must be truncatable.

Mount admits one exact nonempty cleanup shape: the union contains one retained
record, and that record is either one modern orphan-file slot with no legacy
head, or one legacy head whose retained successor is zero with no active
modern slot. A linked target must be a regular file whose zero size is already
durable, whose retained data map is an inline depth-0 extent root, and which
does not use journal-data mode. An authenticated external xattr is retained;
the root may already be empty or may contain ranges that the bounded
free-block builder can account for exactly. An unlinked target must be an
allocated regular file with zero links and zero size, no external xattr block,
and an inline depth-0 extent root that is either empty or contains exactly one
initialized extent at logical block zero with length one and a zero physical
high word. Its decoded `i_blocks` must exactly equal that zero- or one-block
ownership. The physical block must still be allocated, lie outside all static
metadata and journal ranges, and not alias orphan-file storage. A
filesystem-wide scan of authenticated allocated inodes must also prove that no
other extent or legacy data/map-metadata reference, or external-xattr pointer,
names the candidate block. A resident inline xattr area is admitted only after
the structural walker proves bounded, ordered, nonoverlapping values with no
value-inode reference. Every other nonempty union remains a stable
`EXT4-D-RECOVERY` refusal after any required replay and before a
cleanup-specific transaction is activated or emitted.

For the admitted singleton, mount derives the exact coalesced metadata credit,
proves journal capacity, dry-stages and aborts the transaction, activates or
converges the recovery journal as required, stages and emits the same sealed
transaction, and drives it through ordinary replay, strict empty-union
validation, root validation, and clean landing before publication. Modern
completion clears the exact orphan-file slot. Legacy completion clears
`s_last_orphan` in the checksummed primary-super after-image. For a linked
target it deliberately does not manufacture a no-op `i_dtime` rewrite. An
unlinked delete instead zeroes the complete target inode record, including
`i_dtime`, without synthesizing a deletion timestamp; the same transaction
clears its inode-bitmap bit and increments the owning descriptor and
primary-super free-inode counters.
For the one-block shape it also clears the physical block bit and increments
the matching group and super free-block counters. The released data block is
not overwritten: its bytes remain unchanged after allocation authority is
removed. `itable_unused` remains at its conservative allocation high-water
value; the zeroed record is a normal free-inode representation accepted by
pinned e2fsprogs. The temporary recovery writer is scrubbed and its arena tail
rolled back, so the narrow mount transaction cannot pin a later public writer
geometry.

An authenticated empty modern set is completed before mount publication only
when the legacy/modern union is empty, without changing an orphan inode,
orphan-file block, or legacy link.

The driver contains its own reflected CRC32C implementation. Akashic's public
`CRC32C` word is deliberately MSB-first and is not interchangeable with the
ext4 checksum contract.

Known refused feature bits return format-domain `VFS-R-UNSUPPORTED` with
`EXT4-D-FEATURE`. `ORPHAN_PRESENT` and a nonzero `s_last_orphan` are admitted
through any required committed-journal replay and strict reload for
authenticated discovery. If `ORPHAN_PRESENT` is set and the authoritative
legacy/modern union is empty, mount completes the transient recovery state
before publication: a `RECOVER`-clear input first enters a tear-safe recovery
epoch through writer-free `AKW1` activation while preserving
`ORPHAN_PRESENT`; `AKR1` then lands an empty checksum-v3 journal and a
checksummed primary superblock with both transient bits clear. A valid
nonempty union outside the exact singleton linked-truncate or zero-/one-block
unlinked-delete slices returns the stable `EXT4-D-RECOVERY` refusal. An admitted singleton is
transactionally completed before mount publication; malformed authority still
fails closed, and no public mutation capability is exposed. Malformed links,
cycles, out-of-range locators, and duplicate inode membership return
format-domain `VFS-R-CORRUPT`; inode allocation and checksum failures preserve
their more specific corruption detail. A dirty state without `RECOVER` or a
recovery state outside the implemented JBD2 slice remains a stable refusal. No
such failure can leave a mounted or ready object.

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
commit is currently refused rather than classified as a torn tail. Unified
legacy/modern orphan discovery runs after replay and strict reload. Its exact
union count drives one arena-backed location plan, and failed-mount retries
reuse a sufficient retained allocation rather than consume another monotonic
arena allocation. The authenticated-empty modern branch completes recovery
metadata only when both protocols are empty, without changing an orphan inode,
orphan-file block, or legacy link. The exact singleton modern/legacy
depth-zero cleanup is admitted through the sealed transaction path. Larger
unions and broader truncate/delete shapes remain refused. Pinned
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

`_EXT4-JTX-PREFLIGHT-CAPACITY` is the no-allocation sizing gate for a known
transaction profile. It checks the complete writer byte geometry and computes
the exact JBD2 reservation from the block size: metadata payload blocks,
ceiling-divided descriptor blocks, revoke blocks, one private guard, and one
commit. It then applies the ring's excluded-spare capacity,
`s_max_transaction` (excluding the private guard), and
`s_max_trans_data`. Failure therefore occurs before `_EXT4-JWR-ENSURE` can
consume the monotonic arena. `_EXT4-JTX-BEGIN` independently repeats the same
limits against the allocated writer and current free reservation.

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

Typed metadata editing now uses a transaction-aware acquire/replace boundary.
`_EXT4-JTX-META-ACQUIRE` accepts a freshly authenticated complete home-block
source. If that home already has an active staged metadata entry, acquisition
first validates the retained image CRC32C and copies that newer after-image,
not the stale media source, into writer-owned scratch. A cancelled entry grants
no retained-image authority, so acquisition again starts from the authenticated
source. The retained image stays immutable while scratch is edited.
`_EXT4-JTX-META-REPLACE` then delegates the complete scratch block to the
ordinary coalescing metadata path, including credit checks, data/revoke
conflicts, revoke cancellation, and a new retained image checksum. Consecutive
typed edits to different records in one inode-table block or different slots
in one orphan-file block therefore compose into one same-home after-image
instead of overwriting one another from media.

The first typed builders are private orphan-recovery components.
`_EXT4-JTX-STAGE-ORPHAN-INODE` reauthenticates the plan record and active inode,
requires the modern slot or legacy `i_dtime` link still to match its retained
locator, and reloads the allocated checksum-valid inode and its exact table
location. It snapshots the caller-supplied record in separate writer scratch
before those reads can overwrite a natural context-cache input, requires the
inode generation to retain the authenticated identity, and installs it into
the coalesced block before recomputing the inode checksum. A different inode
record in the same home composes normally; a second replacement of an already
edited copy of the same inode returns `VFS-E-CONFLICT` instead of discarding
the first edit. The checksum builder handles the admitted 128-byte low-half
form and the validated 256-byte `extra_isize`-governed high half.
`_EXT4-JTX-CLEAR-MODERN-ORPHAN-SLOT`
reauthenticates the modern logical-block/slot locator and physical-location-
bound source block. Mutation admission proves that exact physical block is in
bounds and disjoint from the journal, every descriptor-owned bitmap/table,
and every sparse-super/GDT interval, and also rejects an alias with the target
inode's retained external xattr block. Because that descriptor-wide scan
clobbers shared read caches, the builder reconstructs the orphan-file map and
reauthenticates the planned record, physical home, orphan identity, and slot a
second time. It then reacquires the newest same-home image, requires that the
staged slot still names the planned inode, clears it, and recomputes the tail
CRC32C from the orphan inode number, generation, physical block, and block
contents. These checks bind discovery records back to current media before
they can contribute an after-image; they do not validate a proposed inode
record as a complete truncate/delete operation.

`_EXT4-JTX-CLEAR-SINGLETON-LEGACY-HEAD` composes legacy protocol removal into
the transaction-aware primary-super after-image. It requires exact singleton
legacy authority, verifies that `s_last_orphan` still names the retained inode,
preserves the mounted incompat and read-only-compatible feature state, writes
zero to the head, and restamps the super checksum. If block-free accounting
already staged the primary super, acquire/replace composes with that newer
image. A singleton successor is already zero, so the builder does not
manufacture a no-op `i_dtime` rewrite. When it is composed with unlinked
deletion, the separate inode-release builder zeroes the complete target record
rather than writing a deletion time.

`_EXT4-JTX-STAGE-FREE-BLOCK-RANGE` is the first private allocation-accounting
builder. It accepts one nonempty contiguous physical range, proves the whole
range in bounds and disjoint from the journal and every descriptor- or
geometry-authenticated static metadata interval, then walks actual group
geometry including a partial final group. Each touched raw and effective
bitmap must still mark the complete range allocated. Writable admission also
proves that the primary super/GDT homes are not descriptor aliases and that
each touched block bitmap has exactly one descriptor owner and overlaps no
inode bitmap/table, sparse-super/GDT interval, or journal extent. This
anti-alias proof is stronger than the read-side checksum and allocation
admission needed merely to inspect a filesystem.

For each group, the builder clears the retained effective bitmap bits,
increments the split group free-block counter, installs the seeded bitmap
CRC32C, and restamps the descriptor CRC. It coalesces descriptors sharing one
primary GDT block, then increments and restamps the checksum-valid primary
superblock inside its complete 1/2/4 KiB home-block image. Repeated disjoint
calls compose through the transaction-aware acquire boundary; duplicate or
partially overlapping staged frees return `VFS-E-CONFLICT`. Context caches
remain media-derived and unchanged until a later strict reload. If any
internal failure occurs after the first replacement is published, the
operation automatically aborts and scrubs the whole transaction, so no
descriptor/bitmap prefix can remain eligible for emission without its
aggregate superblock update. This builder does not remove an extent or legacy
map entry, change `i_blocks`, stage a revoke, or free an inode, and it emits no
media write.

Mutation-side admission now has two reusable authorities beyond that free-only
builder. `_EXT4-REQUIRE-UNIQUE-BLOCK-OWNER` scans every authenticated allocated
inode and proves that an arbitrary nonempty physical range is mapped only by
the caller's already-authenticated target inode. The ambient probe is
count-delimited, so a valid range beginning at physical block zero is not
mistaken for an inactive proof. Every return clears the probe and restores the
caller's map-validation bound; a successful proof reloads the target inode.
Because the scan reuses the cleanup scanner and shared inode cache, it also
invalidates any retained operation-scoped orphan ownership certificate before
starting. `_EXT4-VALIDATE-INODE-TABLE-HOME` independently requires a proposed
inode-table after-image to fall in exactly the named descriptor's table and in
no other table, block/inode bitmap, sparse-super/GDT interval, or journal
extent. These words provide the range and live-inode-table authority needed by
an in-place data mutation, but do not stage or emit one by themselves.

`_EXT4-JTX-STAGE-FREE-ORPHAN-INODE` is the corresponding first inode-release
builder. It reauthenticates one canonical singleton plan record and accepts
only an allocated, unlinked regular inode whose size is zero and whose inline
depth-0 extent root is either empty or contains exactly one initialized
extent at logical block zero with length one. Decoded `i_blocks` must exactly
match that shape. A resident inline xattr area is structurally authenticated
with the shared reader walker and may not refer to a value inode; an external
xattr block remains outside this slice. The target must be at or above
`s_first_ino`, and journal-data mode, unwritten extents, nonzero logical
offsets, and every larger or external storage-owning shape are refused. For a
one-block target, its allocation bit must be set and the block-bitmap home must
have exactly one descriptor owner. The physical block must lie inside the
mutable data range and be disjoint from static metadata, the journal, and all
modern-orphan-file extents.

Release admission then walks every initialized, checksum-authenticated inode
bitmap and every set inode record except the target. Each record's inode
checksum is verified before the normal complete extent or legacy-map validator
enumerates data ranges and external tree/indirect nodes; a nonzero external
xattr pointer is included as ownership. Extent leaves and index nodes, legacy
direct data and indirect metadata/data, and external xattr storage therefore
all participate in the reverse-owner proof. `INODE_UNINIT` groups contain no
allocated owners and are skipped. Inode 1 retains its format-defined legacy
bad-block-map interpretation; other mode-zero reserved records must be
storage-empty, while fast-symlink and device payload bytes retain their normal
non-map interpretation. Any reference to the candidate is
`EXT4-D-DATA-MAP` corruption, even when both inode records and their allocation
bits are individually checksum-valid.

The builder derives the inode
group, bitmap bit, table locator, primary GDT page, and primary-super home from
authenticated geometry, proves the inode bitmap has one descriptor owner and
aliases no block bitmap, inode table, sparse metadata, or journal range, and
requires every transaction home to be pairwise disjoint except the intentional
legacy protocol/super coalescing.

The builder first stages the complete target inode-table home with exactly the
target record zeroed and every sibling byte preserved. For a one-block target
it then releases physical allocation through the typed block-free builder; it
stages no data-block overwrite and does not wipe the block contents. It finally
clears exactly one retained inode-bitmap bit, increments the split
group free-inode count, installs the new inode-bitmap CRC32C, restamps the
complete descriptor, increments the primary-super free-inode count, and
restamps the super. Modern protocol removal adds its distinct orphan-file
home, while legacy head removal composes in the same primary-super home.
Semantic verification reconstructs every complete after-image from raw media:
the inode-table home, optional block bitmap and data-group descriptor, inode
bitmap, inode-group descriptor, and primary super. This covers sibling inode
records, unrelated descriptors, and all block padding. `itable_unused` remains
at its pre-free conservative high-water value and is not incremented during
release; the now-free target record itself is exactly zero. Publish-then-fail
paths abort and scrub the complete transaction.

The production mount cleanup retains a successful reverse-owner proof only
inside one serialized cleanup invocation, under the driver's exclusive
raw-media-mutation contract. It is keyed to the context, target inode and
generation, and exact physical range; it is not backed by a per-write content
generation counter. Every reuse still repeats local plan, inode, map-shape,
static/journal, and orphan-file authentication. Dry staging and abort,
journal-only activation, real staging, and commit cannot change another inode's
home map while that exclusive contract holds. The proof is invalidated before
retained-journal convergence, consumed immediately after a durable commit and
before replay can write homes, and cleared on every return. It is never
context-persistent and grants no authority across remount, a home write, or an
external raw-media mutator.

`_EXT4-JTX-STAGE-ORPHAN-DEPTH0-TRUNCATE` joins that accounting builder to one
authenticated map-removal case. It accepts only the canonical retained plan
slot found by the plan's own hash probe; an external byte copy, empty table
slot, or injected duplicate in a later probe slot has no cleanup authority.
The media locator is reauthenticated and the target must be a linked regular
file whose zero size is already durable, whose data map is an inline depth-0
extent root, and which does not use journal-data mode. Any external xattr block
is allocation- and checksum-authenticated, retained, and proved disjoint from
the target data ranges. The decoded `i_blocks` value must exactly equal all
captured extent blocks plus that retained xattr block in 512-byte sectors.

Writable ownership admission also reauthenticates the modern orphan file. For
this first slice, that file must itself use inline depth-0 extents and no
external xattr. Every complete orphan-file extent, including unwritten or
preallocated blocks beyond EOF, must be disjoint from every target range and
from the target's retained external xattr block, and every logical orphan
block is reread through its physical-location-bound tail checksum. This
deliberate mutation-side narrowing avoids freeing a checksum-valid cross-inode
alias without narrowing read-side orphan discovery.

For a nonempty captured root, the builder stages an inode with zero extent
entries, clears all four inline entry slots, retains the extent header and
external-xattr pointer, encodes the exact xattr-only `i_blocks` remainder
(including `HUGE_FILE` units), and frees each captured range through the typed
block-free builder. An already empty, exactly accounted root is a successful
no-op. Once the inode afterimage is published, any later semantic, conflict, or
credit failure aborts and scrubs the entire transaction; it recognizes a lower
block-free auto-abort and does not abort twice. The operation intentionally
leaves the orphan slot/list record active for a later durable
protocol-completion step. It stages no data or revoke and performs no media
write.

`_EXT4-JTX-STAGE-SINGLETON-ORPHAN-DEPTH0-FINAL` owns an initially empty
metadata-only transaction and supports either exact singleton protocol. It
dispatches by the authenticated link count, and composes either depth-zero
linked truncation or zero-/one-block unlinked inode release with modern slot
removal or legacy-head removal. It requires used and active metadata homes to
equal the exact credit, then seals protocol- and operation-specific raw
authority plus retained after-image CRC32Cs into the arena-owned writer.
Modern modes bind the logical block, slot, physical orphan-file home, and
generation. Legacy modes bind the raw checksummed primary super, head inode,
zero locators, and cleared-head after-image. All modes bind the target inode
generation, table location, original inline-entry count, transaction epoch,
and applicable retained-image checksums. Delete modes additionally bind the
inode-bitmap home, GDT home and descriptor offset, and complete retained CRCs
for the zeroed target inode-table block, inode bitmap, GDT, and primary-super
after-images. Data-delete modes additionally bind the exact physical range;
the retained transaction entries and semantic verifier bind its block-bitmap
and data-group-descriptor after-images. The explicit entry count binds the raw
preimage shape: an already-truncated linked target has zero, a linked target
being truncated is nonzero, and a delete has the admitted zero or singleton
raw count plus a mandatory zero target after-image. No valid CRC32C value is
reserved as a sentinel. Mode is published last; once published, every generic
and typed staging entry point returns busy, while abort and emit remain legal.
Abort and every successful writer rebase scrub the complete sealed transaction
certificate; this is distinct from the operation-scoped reverse-owner proof.

`_EXT4-MEASURE-SINGLETON-ORPHAN-DEPTH0` applies the same authentication without
allocating a writer or publishing an after-image. An already-truncated
singleton costs one protocol home: the orphan-file block for modern or the
primary super for legacy. A nonempty modern root starts with the target inode
table, primary super, and orphan-file block; a nonempty legacy root starts with
the target inode table and primary super. Both add one uniquely owned block
bitmap per touched group and one copy of each distinct primary GDT page. Thus
the canonical one-block linked-truncate legacy fixture has exact credit four, while its
already-truncated form has credit one. The geometry-bounded, constant-space
group scan imposes no candidate array or cleanup-specific capacity. Checked
arithmetic, complete range/static/journal anti-alias validation, and unique
bitmap-owner proofs make the result the coalesced home count rather than an
upper bound. The final builder independently requires its staged active-home
count to equal the measured credit, so media or plan drift remains fail-closed.
An admitted unlinked target instead measures its inode table, inode bitmap,
inode-group GDT page, and primary super for exact credit four under legacy
cleanup; the distinct modern orphan-file home makes that five. A one-block
target adds its block bitmap, and adds its data-group GDT page only when that
page is distinct from the inode-group GDT page. The canonical fixtures
therefore measure five legacy or six modern homes for the one-block case.

This is a non-emitting staging boundary. The typed builders may issue checked
reads for locator and checksum reauthentication, but they do not activate a
journal, emit a transaction, checkpoint a home block, write, or flush. Before
emission their results exist only in private writer memory. `_EXT4-JTX-ABORT`
performs no volume I/O: it scrubs staged entries, images, and hashes, refunds
the log reservation, clears both writer scratch blocks, and returns the writer
to `IDLE`. Neither staging nor abort completes orphan cleanup or grants a
public write capability.

`_EXT4-COMPLETE-SINGLETON-ORPHAN` is the production mount client of that
private transaction machinery. It finds the exact plan record, measures and
preflights it before allocation, takes an arena mark, allocates only the
measured temporary writer, dry-stages and aborts once, then activates or
converges the recovery journal and emits the same sealed cleanup. Ordinary
replay performs the home writes and clean landing. Strict reload, empty-union,
root, and attachment proofs precede publication; every exit scrubs and rolls
back the temporary arena tail so recovery geometry cannot constrain a later
public writer.

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
finishes. Checkpoint first revalidates the complete workspace, performs a
complete on-media JBD2 log scan, and then repeats that scan in lockstep with the
retained emitter order before issuing a home write. Generic transactions use
the ordinary strict reload and require an authenticated empty orphan union
both before and after their home writes; they therefore gain no authority from
a nonempty orphan plan. The sealed singleton-final mode alone uses a private
pre-home reload that performs the same super, group, backup, orphan-union, and
journal authentication but replaces the public nonempty-policy refusal with
an exact writer-certificate comparison. It requires the sole rebuilt plan
record, raw target identity and table location, the selected protocol's raw
locator and authority, and the frozen retained target/protocol images to match.
Modern authority is the orphan-file generation, mapping, physical home, and
slot; legacy authority is the raw primary-super checksum, head inode, zero
locators, and primary-super home. The active primary and guard, transaction ID,
start/head/cursor, every descriptor home and unescaped payload, every revoke
identity, the commit, the exact zero sentinel, and the retained entry/image
CRCs must describe the same single committed transaction. A mismatch fails
before home mutation. Delete-specific modes also rebuild the raw unlinked
inode/allocation authority and rerun the complete target-inode, bitmap, GDT,
and super after-image proof. For a data delete that proof also derives the
exact block bitmap and data-group descriptor from the certified physical
range. After home writes, checkpoint rereads every retained metadata home,
requires its complete image and CRC, proves the target inode record is zero
and its allocation bit is clear, and, when applicable, proves the released
data bit is clear before accepting the protocol-specific empty-orphan landing.

After that preflight, checkpoint writes each retained active metadata
after-image to its home block. Ordered data is not rewritten because emission
made it durable before commit, and revoked/cancelled entries grant no home-write
authority. All metadata home writes cross one volume flush, followed by a
strict reload and root validation, before any journal block or reservation can
be reused. Both the post-home proof and the final post-reset proof remain
ordinary strict reloads. A singleton-final transaction additionally requires
those reloads to derive the authenticated empty-orphan predicate, so its
special admission cannot survive past the first home-write boundary.

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
authority, publishes `IDLE`, and restores the binding readiness value present
at checkpoint entry. Thus a private recovery checkpoint entered before mount
publication remains unready; an ordinary live checkpoint remains ready. The
next transaction immediately reuses that workspace and ring, including
sequence wrap, without another arena allocation.
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
remain read-only. Transactional completion of the exact singleton linked
zero-size inline-depth-0 and zero-/one-block unlinked-inode cases is
implemented for both orphan mechanisms. Pinned e2fsprogs accepts final
empty-delete media at 1 KiB and ordinary one-block-delete media at 1/2/4 KiB
for both orphan protocols. Broader orphan recovery, the complete user-visible
mutation layer, external-tool inspection of active Akashic-created journal
endpoints, and the remaining release gates must still land before public write
capabilities can be enabled.

The first ordinary-data mutation is also implemented as a private staging
primitive. It admits a linked regular file with an authenticated inline
depth-zero extent map and overwrites a nonempty byte range wholly contained in
one existing initialized block. The transaction shape is exactly one ordered
data block, one inode-table metadata block, and no revokes. The ordered image
is a full-block read-modify-write copy; the metadata image preserves every
other inode-table byte, updates `mtime` and `ctime` from explicit seconds and
nanoseconds, and restamps the ext4 inode checksum. Staging neither emits nor
checkpoints the transaction and grants no public write capability.

Before retaining either after-image, the primitive validates the selected data
block against journal, descriptor, bitmap, inode-table, and sparse-super/GDT
roles; proves that no other inode owns the block; and reauthenticates the
target's generation, locator, complete inline extent map, size, link count,
flags, and external-xattr pointer after every cache-clobbering scan. Inline
depth-zero extent validation excludes target self-overlap, while an external
xattr block equal to the selected data block is rejected separately. A stale
generation, hole, unwritten extent, unsupported inode flag, cross-block write,
growth, or ambiguous ownership fails before publication. Once ordered data has
been retained, any later staging failure aborts and scrubs the transaction.

The exact private write now also completes the real durability lifecycle. A
write-free dry stage is aborted before clean-to-`RECOVER` activation; the live
stage then emits ordered data before its descriptor and final commit,
checkpoints only the inode-table home, and cleanly deactivates through public
unmount. Independent media checks pin the full data block, full inode-table
block, descriptor tag and payload checksums, commit, clean superblock, and
empty guard. A fresh read-only mount performs no recovery I/O and returns the
complete modified file plus the exact nanosecond timestamps.

`_EXT4-MOUNTED-ONEBLOCK-WRITE` now composes that exact slice as a reusable
private mounted client. It accepts source/count, file offset, inode number,
expected generation, explicit seconds/nanoseconds, and the mounted VFS, and
returns `actual ior`. A zero-length request returns `0 0` without allocating a
writer. Every nonempty request preflights and ensures the exact `1/1/0`
workspace. Before either operation it copies the admitted source into one
private `_EXT4-MAX-BLOCK` snapshot, preserving caller bytes even when the
source aliases a shared ext4 cache or writer storage that dry staging,
activation, or writer rebase will overwrite. Every post-copy return scrubs the
complete snapshot; a caller span overlapping that private snapshot is invalid.
The first clean request dry-stages and aborts before activation; after
activation, successful calls synchronously stage, emit, and checkpoint, then
retain the same scrubbed `IDLE` writer for the next call without arena growth.
A staging refusal reports zero progress and aborts only a still-mutable
transaction. Once emission has advanced, existing writer fault/quarantine
semantics retain the uncertain durable state for remount recovery, and an
already latched abort fault takes precedence over the staging error that led
to it. `actual` counts only bytes whose complete checkpoint succeeded;
`actual = 0` after an emission or checkpoint fault does not claim that ordered
data or a replayable transaction is absent. That is another reason this result
contract is not yet the public VFS `WRITE` contract.

Focused mounted-client qualification separates media-clean refusal from the
long durability journey so each remains within the canonical emulator step
budget. Zero length leaves the arena unchanged; a stale generation allocates
the one reusable workspace but emits no write or flush and leaves the clean
journal inactive. A fresh journey performs two disjoint overwrites of the same
file through one writer, preserves the first edit in the second full-block RMW,
and checkpoints both inode after-images. The first source is deliberately
placed in the shared ext4 block cache and the second in writer scratch, pinning
the cross-phase snapshot rule. It then drops the volatile mount at the
authenticated dirty/empty write-active endpoint. A fresh mount performs
the clean landing, returns both edits and the second exact timestamp through
the path and its hard-link alias, and leaves a subsequent unmount clean. The
client remains absent from `EXT4-OPS`: it deliberately does not publish vnode
timestamps or dirty state for continued public access.

A second private word, `_EXT4-WRITE`, now has the exact ABI-1 callback shape
`( source count offset dentry vfs -- actual ior )`. It validates an owned,
linked regular-file dentry, its shared vnode identity/generation and clean
cached state, and a nonwrapping size-preserving single-block range. It then
calls the mounted client with the vnode's ext4 inode number and generation;
it never owns or advances an FD cursor. Exact checkpointed success publishes
only `mtime`/`ctime` seconds and nanoseconds into the shared vnode, making the
result immediately visible through every hard-link alias. Size, blocks,
atime, link count, identity, generation, and vnode-dirty state remain
unchanged. Any failure publishes no vnode fields.

The callback obtains time from a caller-installed per-context provider rather
than ambient `EPOCH@`. `_EXT4-BIND-WRITE-CLOCK` binds it once at an
authenticated clean mounted endpoint before writer allocation. The provider
contract is `( clock-context -- epoch-ms ior )`; one nonzero write samples it
exactly once and converts the admitted scalar to ext4 seconds/nanoseconds.
Zero-length writes do not sample or publish time. The binding survives strict
reload, checkpoint, and live sync/deactivation.

`FSYNC` and `SYNCFS` now validate the retained writer, checkpoint a lower-level
`COMMITTED` transaction if present, return any latched fault, and require an
idle-clean endpoint. `FSYNC` leaves the already-checkpointed filesystem's
empty journal write-active. `SYNCFS` cleanly deactivates it before generic
`VFS-SYNC` clears `VFS-F-DIRTY`, then republishes ready and writer-current
authority so the still-mounted context can reactivate later. Focused
qualification covers missing-clock and duplicate-bind refusal, a sparse-hole
refusal with no cache publication, two live sync/deactivation boundaries,
reactivation through the same writer, exact hard-link cache publication,
unchanged callback-side FD cursors, alias readback, clean unmount, the exact
76-event media trace, and independent raw data/inode/journal checks.

`_EXT4-WRITE` remains absent from `EXT4-OPS` and `EXT4-CAPS`. Its mounted
client still returns zero progress after faults that may follow ordered-data
or commit publication. The next integration gate must derive confirmed byte
progress from ordered-data sector completion and map progress-plus-error and
quarantine flags honestly before generic VFS retry/cursor semantics are safe.

Controlled sequential-write qualification tears the first inode-table home
write at byte 269, one byte into the target inode's new `i_ctime`. The ordered
data and committed journal are already durable, while the torn home is neither
the old nor new inode and fails its inode checksum. A fresh mount replays the
retained inode-table after-image exactly, cleans the journal, and is stable on
another write-free remount. This is one pinned checkpoint tear, not yet the
complete power-cut matrix for ordinary writes.

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
read for the hole. `FSYNC` now validates or checkpoints a retained writer;
`SYNCFS` additionally lands a write-active empty journal clean while
preserving the still-mounted instance's ready/current authority.

`EXT4-BINDING` has `VFS-BF-NEEDS-VOLUME`, `VFS-BF-READ-ONLY`, and
`VFS-BF-STABLE-IDS`. The VFS rejects all mutation before binding dispatch.
`VOL-WRITE` and `VOL-FLUSH` are used only by mount-time recovery, private
activation and emission, same-session checkpoint, and clean deactivation;
they are not exposed as writable VFS capabilities.

## Deliberate remaining limits

This is completion of the bounded clean read side, not completion of the
writable profile. The journaling and crash-recovery substrate is advanced, but
public write support is not a capability-bit flip. `EXT4-OPS` still has no
`WRITE`, `CREATE`, `MKDIR`, `UNLINK`, `RMDIR`, `RENAME`, `TRUNCATE`, `SETATTR`,
`LINK`, `SYMLINK`, `SETXATTR`, or `REMOVEXATTR` callback;
`EXT4-BINDING` remains `VFS-BF-READ-ONLY`; the real `SYNCFS`/`FSYNC` callbacks
do not themselves expose mutation. Writable publication still needs a
production workspace-sizing and chunking contract, general block and inode
allocation,
extent and legacy-map growth and shrink, directory-entry mutation,
inode/link/time/accounting updates, xattr mutation, namespace/cache coherence,
broader orphan recovery, and interoperability plus power-cut qualification.
For the existing one-block shape, trusted time injection, shared-vnode
publication, and live sync semantics are implemented. The durable engine and
private callback still do not constitute the general public mutation layer.

That narrow private write checkpoint has now reached private durability:
one size-preserving regular-file overwrite contained in one already allocated
initialized block, represented by a full-block ordered-data RMW and one
checksummed inode-table after-image for explicit `mtime`/`ctime`. It needs no
allocator or extent edit and fits the exact `1 metadata / 1 data / 0 revoke`
transaction shape. End-to-end emit, checkpoint, clean unmount, write-free
remount, and one checkpoint-home sequential tear/replay case pass. Pinned
external-tool inspection and the broader controlled power-cut matrix remain
qualification gates. The mounted private client adds zero-length behavior,
stable pre-activation refusal, synchronous success, sequential writer reuse,
and dirty/empty crash-remount cleanup without widening the supported data
shape. The operation remains private until its post-publication
progress/error policy is represented honestly and production writer
workspace/chunking policy is settled. Growth, holes, unwritten extents,
cross-block writes, truncation, and namespace mutation remain later phases.

The remaining boundaries are:

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
  preflight, retained-image home writes, dirty-empty journal release,
  immediate sequential workspace reuse, clean write-active deactivation, and
  public clean-unmount integration are implemented as private durability
  foundations. Exact private one-block regular-file overwrite staging now
  composes a full ordered-data RMW with an explicitly timed, checksummed inode
  after-image after mutation-range and filesystem-wide ownership proof. Its
  exact dry-stage/activation/emission/checkpoint/deactivation journey, clean
  remount, and one partial inode-home replay case pass; public mutation and
  broad crash/interoperability qualification remain gated.
  Transaction-aware metadata acquisition, checksum-safe typed
  orphan-inode replacement, free-only physical-block accounting, linked
  zero-size inline depth-0 extent truncation, exact zero-/one-block unlinked
  data and inode allocation release, target-record scrubbing, exact credit
  measurement, modern-slot removal,
  legacy-head removal, and operation/protocol-specific final certificates now
  compose one sealed singleton transaction for either orphan mechanism.
  Production mount selects that exact operation, preflights and dry-stages it,
  handles a clean journal or retained recovery prefix, emits the transaction,
  drives committed cleanup through ordinary replay, and publishes only after
  strict empty-union validation. The temporary mount writer is scrubbed and
  rolled back rather than becoming the production workspace;
- unified legacy-chain and modern orphan-file discovery, inode preflight, and
  authenticated-empty `ORPHAN_PRESENT` completion are implemented. The shared
  exact-count plan retains protocol-specific locations and enforces inode
  uniqueness across the union. Empty completion is authorized only when both
  protocol counts are zero and mutates only journal recovery state and the
  checksummed primary-super transient bits; it does not change an orphan
  inode/file, a legacy link, allocate writer workspace, or expose a
  user-visible write. Cleanup still does not cover a union with more than one
  active record, nonzero-size or tail truncation, depth-positive extent trees,
  legacy direct/indirect map mutation, an unlinked inode with more than one
  extent, an extent longer than one block, a nonzero physical high word, an
  unwritten extent, a nonzero logical offset, a depth-positive root, an
  external xattr block, or an inline xattr value inode,
  external-xattr/value-inode release, general link-count and multi-node
  legacy-chain repair, or multi-transaction chunking. General inode
  allocation, general inode release outside the admitted shape, and every
  user-visible mutation operation remain unimplemented. Cleanup releases
  allocation authority but does not provide secure deletion or data-block
  erasure;
- focused zero-/one-block unlinked qualification covers modern and legacy
  singleton mount completion on the canonical 1/2/4 KiB, 256-byte-inode
  geometries. The fixture construction and post-mount allocation-accounting
  oracle derive the primary GDT page, data and inode bitmap homes and bits,
  free-block and free-inode counters, and conservative `itable_unused` result
  from each image rather than relying on the 1 KiB layout. It pins exact
  four/five-home credit for empty legacy/modern cleanup and five/six-home
  credit for the canonical one-block cases, delete-specific sealing and
  mutation freeze, complete abort scrubbing, exact target-record zeroing with
  sibling inode-table bytes preserved, allocation-bit clearing, and descriptor
  and super accounting. Structurally valid resident inline xattrs are scrubbed
  with the target record; an inline value-inode reference is refused as
  unsupported, and unexplained nonzero `i_blocks` is rejected as corruption.
  Mount-level refusal covers unwritten and offset extents, a nonzero physical
  high word, external xattrs, orphan-storage aliasing, and a clear data bit.
  Checksum-valid allocated live-inode fixtures additionally prove that both a
  data extent and an external-xattr pointer aliasing the candidate are rejected
  as `EXT4-D-DATA-MAP` before writer allocation or media mutation, for both orphan
  protocols; the same-binding retry returns the same refusal with the scoped
  ownership proof and ambient probe cleared.
  Direct exact-shape preflight coverage additionally rejects multiple entries,
  length greater than one, and depth-positive roots before writer allocation
  or media I/O. Every refusal fails before writer allocation or any
  write/flush. A 1 KiB cross-group fixture qualifies separate data- and
  inode-group descriptors coalesced into one primary GDT home. Pinned
  e2fsprogs 1.47.4 accepts both protocols for the empty 1 KiB result, ordinary
  one-block 1/2/4 KiB results, and the 1 KiB same-GDT-page cross-group and
  one-block resident-inline-xattr variants. The established linked
  modern/legacy seal and mount paths pass against the shared
  mode/checkpoint changes. The empty-case controlled matrix covers eight
  modern and seven legacy write prefixes: both sides of final commit, every
  operation-specific metadata home, and final-super publication. Three fences
  per protocol cover commit, replay-home durability, and final-super
  publication; both the writes that survived each failed flush and the
  preceding durable snapshot repair on a fresh mount and then remount without
  another write. Targeted one-block prefix qualification covers the first
  commit byte and the data-bitmap, GDT, and primary-super home writes for both
  protocols. A replay-home flush fence is also exercised for both protocols.
  Substitution of the retained target-inode CRC remains structurally valid but
  is rejected during checkpoint preflight before any home write. These
  controlled crash cases remain pinned to the 1 KiB fixture. The branch in
  which the data- and inode-group descriptors occupy distinct primary GDT
  pages, adding one metadata home, is implemented but not yet qualified; the
  one-block-specific commit and final-super flush fences, shared
  activation/reset prefixes, broader ownership shapes, and active-journal
  external-tool inspection also remain to be qualified;
- focused 1 KiB coverage exercises one- and two-inode legacy chains, a mixed
  legacy/modern union, stable refusal with same-binding plan reuse, legacy
  cycles and invalid links, unallocated and checksum-invalid legacy inodes,
  and cross-protocol duplicate rejection without writes. Passing singleton
  legacy cleanup coverage across 1/2/4 KiB geometry now includes the
  27-write/18-flush successful mount. Focused 1 KiB coverage additionally pins
  exact one-home already-truncated sealing with zero target entries, exact
  four-home one-block linked-truncate sealing with one target entry, post-seal mutation
  refusal, and abort scrubbing. Its controlled crash matrix covers 14 write
  prefixes spanning activation, transaction description and commit, every
  legacy metadata home, reset, final-super publication, witness clearing, and
  guard retirement. It also covers all nine durability fences; both the writes
  surviving each failed flush and the preceding durable snapshot independently
  repair and then remount without another write. Unified discovery still needs
  qualification across longer chains, later modern blocks and files beyond the
  former 4096-block limit, additional unlinked ownership shapes and
  structurally invalid referenced inodes,
  distinct-key hash collisions, and arena exhaustion or a retained workspace
  that is too small; and
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
