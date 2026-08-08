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
size or filesystem geometry. It is unrelated to the current backup-super
geometry boundary: the validator requires each scheduled backup group number
to equal the 16-bit on-disk `s_block_group_nr`, so a required sparse-super
backup above group 65535 is refused.

The checked-in 800,000,000-step cold-source value is a qualification watchdog
and measurement guide, not an ext4 implementation capacity or a reason to
weaken functionality. If correct source legitimately outgrows it, the budget
must be revisited from measured system resources. The harness still performs a
real cold source build and requires the `EXT4-SOURCE-READY` marker with no
Forth diagnostic. Runtime recovery journeys use a separate 1,200,000,000-step
default watchdog. The geometry-bounded multi-record production and mixed
second-commit fault journeys use a scoped 1,500,000,000-step watchdog because
the real cold-source path plus repeated whole-plan authentication legitimately
crossed the default; the mixed successful cleanup measured 1,209,747,492
steps. Neither value is an implementation capacity. The default was
established after the fresh-proof W18 crash-repair
journey exceeded the old ceiling; the measured journey completed in
811,281,646 steps, on one core, below 1 GiB peak RSS with no swapping. It is
historical sizing evidence, not a claim that W18 is rerun for every source
revision. `EXT4_REPORT_STEPS` reports actual use and source/backing media;
budget failures include used and allowed steps. The current source passes cold
builds and focused recovery qualification under their checked-in watchdogs,
without a compiled cache or certificate-preservation shortcut.

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

The mounted instance can reserve a caller-selected private writer profile
without enabling public mutation:

```forth
1 1 0 fs EXT4-WRITER-WORKSPACE-BYTES? THROW
A-XMEM ARENA-NEW THROW CONSTANT writer-arena

writer-arena 1 1 0 fs EXT4-BIND-WRITER-ARENA? THROW
```

The three capacities are maximum metadata, ordered-data, and revoke credits;
there is no driver-chosen split or operation-count ceiling. The sizing query
also proves that the complete tuple fits the authenticated journal ring,
`s_max_transaction`, and `s_max_trans_data`. The binding requires a fresh
dedicated arena whose backing is disjoint from the VFS arena. Its descriptor,
backing, and bump pointer remain exclusively owned by ext4 until clean
unmount, which scrubs the complete writer and rolls the arena back to fresh.
Busy or faulted unmount retains it for retry or diagnosis. The caller may
destroy the arena only after successful unmount. These words configure the
private substrate; `EXT4-BINDING` remains read-only and still publishes no
`WRITE` callback.

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
  and size-low fields. Journal inode 8 is pinned to generation zero, has no
  external-xattr block, and uses an inline depth-0 extent root containing one
  through four initialized extents with exact gapless EOF coverage and bounded,
  nonoverlapping physical ranges. This recovery-authority constraint does not
  narrow the general file reader's extent-depth or legacy-map support. The inode
  size must be a nonzero whole number of filesystem blocks, fit JBD2's 32-bit
  `s_maxlen`, and not exceed the filesystem block count. Mount expands that
  authenticated inline tuple directly into an exact map plus a half-full
  power-of-two uniqueness table from the caller's arena; arena exhaustion
  returns `VFS-E-NOMEM` rather than imposing a journal-size constant. It rejects
  holes, mappings beyond EOF, out-of-range or aliased blocks, and any journal
  block that overlaps a descriptor-authenticated block/inode bitmap or
  inode-table range, any deterministic sparse super/GDT/reserved-GDT range, or
  inode-8 bootstrap metadata; and
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

Before the first cleanup-specific write, mount authenticates every record in
the complete legacy/modern union and measures the exact coalesced metadata
credit for each supported record. The maximum of those exact measurements
sizes one reusable temporary writer. The record count is bounded by
authenticated filesystem geometry, checked arithmetic, and available
caller-arena storage; cleanup adds no separate fixed record-count constant. A
linked record is supported only for a regular file whose zero size is already
durable, whose retained data map is an inline depth-0 extent root, and which
does not use journal-data mode. An authenticated external xattr is retained;
the root may already be empty or may contain ranges that the bounded
free-block builder can account for exactly. An unlinked target must be an
allocated regular file with zero links and zero size, no external xattr block,
and an inline depth-0 extent root that is either empty or contains exactly one
extent with a zero physical high word. Its initialized decoded length may be
1..32768 blocks or its unwritten decoded length 1..32767 blocks, exactly as
encoded by ext4 `ee_len`; `logical_start + decoded_length` must be at most
`0xffffffff`. Its decoded `i_blocks` must exactly equal that empty or
single-extent ownership. An ext4 inline depth-0 root can encode as many as four
extent entries, but the current unlinked-delete slice admits at most one;
multi-entry roots are refused before cleanup mutation. The complete physical
range must still be allocated, lie outside all static metadata and journal
ranges, and not alias orphan-file
storage. A filesystem-wide scan of authenticated allocated inodes must also
prove that no other extent or legacy data/map-metadata reference, or
external-xattr pointer, names any block in the candidate range. A resident
inline xattr area is admitted only after the structural walker proves bounded,
ordered, nonoverlapping values with no value-inode reference. If even one
record is outside these supported per-record shapes, the whole union returns a
stable `EXT4-D-RECOVERY` refusal before writer allocation or cleanup mutation.

Mount drains a qualified union deterministically: the current legacy head and
its authenticated successor chain first, then modern records ordered by
unsigned `(logical-block, slot)`. Each record gets one exact transaction using
the same maximum-sized writer. Mount dry-stages and aborts that record,
activates or converges the recovery journal as required, then stages, emits,
and checkpoints the same sealed cleanup before selecting again from the
strictly rebuilt plan. Modern completion clears the exact orphan-file slot.
Legacy completion advances `s_last_orphan` to the retained successor in the
checksummed primary-super after-image. A linked legacy intermediate record also
clears its consumed `i_dtime` link in that transaction; a terminal
zero-successor record whose extent root is already empty does not manufacture a
no-op inode rewrite. A linked modern record is admitted only with `i_dtime`
already zero. An unlinked delete zeroes the complete target inode record,
including `i_dtime`, without synthesizing a deletion timestamp; the same
transaction clears its inode-bitmap bit and increments the owning descriptor
and primary-super free-inode counters.
For a nonempty extent it also clears every physical-range allocation bit,
increments each touched group by its exact range chunk, and increments the
primary-super free-block counter by the complete extent length. Released data
blocks are not overwritten: their bytes remain unchanged after allocation
authority is removed. `itable_unused` remains at its conservative allocation
high-water value; the zeroed record is a normal free-inode representation
accepted by pinned e2fsprogs.

Each sealed record carries a `FINAL` or `MORE` certificate plus the exact
pre-transaction total, modern, and legacy counts. Checkpoint reauthenticates
the complete pre-union before its first home write, then strictly rebuilds the
poststate and proves that the selected inode no longer appears in the union,
the selected protocol count and total count each decreased by exactly one, and
the other protocol count did not change. `FINAL` requires a one-record prestate
and an authenticated empty poststate; `MORE` requires a prestate greater than
one and a nonempty poststate. `RECOVER` and any present `ORPHAN_PRESENT` authority are
retained across every intermediate transaction. They are cleared only after
the loop reaches an authenticated empty union and the witnessed clean landing
is durable. The temporary recovery writer is then scrubbed and its arena tail
rolled back, so temporary recovery workspace cannot pin a later public writer
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
checksummed primary superblock with both transient bits clear. Any union whose
records all fit the exact linked-truncate or empty/single-contiguous-inline-
depth-0-extent unlinked-delete slices is transactionally drained before mount
publication; a union containing any other record returns stable
`EXT4-D-RECOVERY` without a cleanup write. Malformed authority still fails
closed, and no public mutation capability is exposed. Malformed links,
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
orphan-file block, or legacy link. A union whose records all fit the supported
modern/legacy depth-zero shapes is processed as a sequence of sealed one-record
transactions; its count is constrained by authenticated geometry, checked
arithmetic, and caller-arena capacity rather than a cleanup-specific constant.
Broader truncate/delete shapes remain refused. Pinned qualification covers
multi-record hash collisions,
malformed revoke geometry
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

Before activation, private emission, checkpoint cleanup, clean deactivation,
or recovery landing may replace a journal block or the filesystem block that
contains the primary superblock, a mount-scoped reverse-ownership proof scans
every allocated inode other than inode 8 through the complete ordinary
map/external-xattr validator. Any referenced range that intersects the exact
authenticated journal extent tuple or the primary-super home refuses the write
before media mutation. Inode 8 is the sole exclusion because journal
authentication requires its exact self-contained inline tuple and a zero
external-xattr pointer. Proof scope is fail-closed and constant-workspace; every
return restores the shared mutation/map bounds and clears its temporary inode,
context, and active publications.

A committed replay invalidates this certificate before preflight and keeps it
invalid across replay, flush, authenticated reload, and root validation. The
authoritative post-replay image must pass a fresh full proof before any journal
reset, superblock clear, witness removal, or anchor retirement. If replay
retains an orphan, recovery returns without the certificate and union cleanup
performs the same proof before convergence, activation, or any other write. No
retained writer image or pre-replay certificate substitutes for checking the
current filesystem.

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
allocates no writer: the path establishes recovery authority, immediately
proceeds through `AKE1`-qualified `AKR1`, and exposes no write-active endpoint
through the successfully mounted VFS. When nonempty orphan cleanup needs
transactions, that separate drain first measures every supported record,
snapshots the ordinary mount arena, allocates one temporary mount-store writer
at the maximum exact per-record credit, and scrubs and rolls the complete tail
back on every exit. Recovery therefore cannot select or pin the production
profile; a caller may bind an independently sized dedicated profile after
mount.

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
writer. A caller supplies maximum metadata, ordered-data, and revoke
capacities; the driver derives exact half-full hash geometry and the complete
byte requirement, admits the tuple against authenticated journal limits, and
makes one checked allocation from a fresh dedicated arena. It publishes the
store kind and arena before publishing the complete writer pointer last. Any
componentwise-contained transaction request reuses that profile without arena
growth; a larger request returns `VFS-E-NOSPC` without changing the selected
profile. A mount-generation `WRITER-CURRENT`
publication bit prevents preserved workspace bytes from becoming transaction
authority during a retry. Mount clears it before rebuilding media-derived
state; a failed mount neither republishes nor scrubs the old staged,
`COMMITTED`, or faulted state. Only after recovery, strict reload, root
validation, and attachment validation reach an authenticated clean endpoint
does mount shape-check the allocation, zero its owned tables and images,
rebase it to the persisted journal head and wrapped next transaction ID, and
publish `IDLE` and then current ownership. Same-mount faults remain sticky.
Successful clean unmount withdraws current authority, scrubs the complete
dedicated allocation, rolls its arena back to the original fresh mark, clears
the storage publication, and only then detaches the block context. Busy or
failed unmount retains the block context and arena; a busy entry retains
current authority, while a terminal fault preserves its exact phase for
diagnosis.

`_EXT4-JTX-PREFLIGHT-JOURNAL` is the storage-independent sizing gate for a
candidate profile. It checks complete byte geometry and computes the exact
JBD2 reservation from the block size: metadata payload blocks,
ceiling-divided descriptor blocks, revoke blocks, one private guard, and one
commit. It then applies the ring's excluded-spare capacity,
`s_max_transaction` (excluding the private guard), and
`s_max_trans_data`. `_EXT4-JTX-PREFLIGHT-CAPACITY` additionally requires an
existing profile to contain a transaction request, or proves ordinary mount
arena space for the separate scoped recovery writer. `_EXT4-JTX-BEGIN`
independently repeats the journal and selected-profile limits against current
free reservation.

This closes first-operation geometry selection: no mutation implicitly sizes
the persistent writer. It does not make every future operation fit one
transaction. Allocation, namespace, xattr, and general truncate paths still
need bounded planners that split work only at filesystem-consistent
intermediate states when their exact credits exceed the selected profile.

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

`_EXT4-JTX-ADVANCE-LEGACY-HEAD` composes legacy protocol removal into the
transaction-aware primary-super after-image. It requires the exact selected
legacy head, verifies that `s_last_orphan` still names the retained inode,
preserves the mounted incompat and read-only-compatible feature state, advances
the head to the authenticated retained successor, and restamps the super
checksum. If block-free accounting already staged the primary super,
acquire/replace composes with that newer image. For a linked nonterminal head,
the inode-truncation builder clears the consumed successor value from
`i_dtime` in the same transaction. A terminal zero-successor record whose root
is already empty needs no no-op `i_dtime` rewrite. When head advancement is
composed with unlinked deletion, the separate inode-release builder zeroes the
complete target record rather than writing a deletion time.

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

Mutation-side admission also has reusable authorities beyond that free-only
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

The mounted context additionally caches the successful protocol-home proof
described above. It is acquired lazily, so a clean read-only mount does not pay
for another whole-filesystem scan. Activation, emission, checkpoint,
deactivation, and recovery cleanup fail closed unless the certificate is
exactly valid; mount-state reset and active replay clear it.

`_EXT4-JTX-STAGE-FREE-ORPHAN-INODE` is the corresponding first inode-release
builder. It reauthenticates one canonical selected plan record and accepts
only an allocated, unlinked regular inode whose size is zero and whose inline
depth-0 extent root is either empty or contains exactly one initialized or
unwritten extent with a zero physical high word. Initialized decoded lengths
are 1..32768 blocks and unwritten decoded lengths are 1..32767 blocks;
`logical_start + decoded_length` must be at most `0xffffffff`. Decoded
`i_blocks` must exactly match the complete extent length. A resident inline
xattr area is structurally authenticated with the
shared reader walker and may not refer to a value inode; an external xattr
block remains outside this slice. The target must be at or above `s_first_ino`.
Journal-data mode, multiple extents, depth-positive roots, malformed lengths
or ranges, and external storage-owning shapes remain refused. Every candidate
range bit must be set and each touched block-bitmap home must have exactly one
descriptor owner. The physical range must lie inside mutable data space and
be disjoint from static metadata, the journal, and all modern-orphan-file
extents.

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
non-map interpretation. Any reference to the candidate range is
`EXT4-D-DATA-MAP` corruption, even when both inode records and their allocation
bits are individually checksum-valid.

The builder derives the inode
group, bitmap bit, table locator, primary GDT page, and primary-super home from
authenticated geometry, proves the inode bitmap has one descriptor owner and
aliases no block bitmap, inode table, sparse metadata, or journal range, and
requires every transaction home to be pairwise disjoint except the intentional
legacy protocol/super coalescing.

The builder first stages the complete target inode-table home with exactly the
target record zeroed and every sibling byte preserved. For a nonempty target
it then releases the complete physical extent through the typed block-free
builder, including exact range chunks crossing group boundaries; it stages no
data-block overwrite and does not wipe block contents. It finally
clears exactly one retained inode-bitmap bit, increments the split
group free-inode count, installs the new inode-bitmap CRC32C, restamps the
complete descriptor, increments the primary-super free-inode count, and
restamps the super. Modern protocol removal adds its distinct orphan-file
home, while legacy head removal composes in the same primary-super home.
Semantic verification reconstructs every complete after-image from raw media:
the inode-table home, every touched block bitmap, every coalesced data/inode
GDT page, the inode bitmap, and the primary super, including range-sized group
and super counter increments. This covers sibling inode records, unrelated
descriptors, and all block padding. `itable_unused` remains
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

`_EXT4-JTX-STAGE-ORPHAN-DEPTH0` owns an initially empty metadata-only
transaction for one deterministically selected record of either protocol. It
dispatches by the authenticated link count, and composes either depth-zero
linked truncation or empty/single-extent unlinked inode release with modern
slot removal or legacy-head advancement. It requires used and active metadata
homes to equal the exact credit, then seals protocol- and operation-specific
raw authority plus retained after-image CRC32Cs into the arena-owned writer.
Modern modes bind the logical block, slot, physical orphan-file home, and
generation. Legacy modes bind the raw checksummed primary super, head inode,
retained successor, and advanced-head after-image. All modes bind the target inode
generation, table location, original inline-entry count, transaction epoch,
and applicable retained-image checksums. Delete modes additionally bind the
inode-bitmap home, GDT home and descriptor offset, and complete retained CRCs
for the zeroed target inode-table block, inode bitmap, GDT, and primary-super
after-images. Data-delete modes additionally bind the exact physical range;
the retained transaction entries and semantic verifier bind every touched
block-bitmap after-image and coalesced data-group GDT page. The explicit entry
count binds the raw extent-entry count, not the number of physical blocks: an
already-truncated linked target has zero, a linked target being truncated is
nonzero, and a delete has the admitted zero or single raw-extent count plus a
mandatory zero target after-image. No valid CRC32C value is
reserved as a sentinel. Mode is published last; once published, every generic
and typed staging entry point returns busy, while abort and emit remain legal.
The certificate also binds the exact pre-transaction total, modern, and legacy
orphan counts and publishes an operation/protocol-specific `FINAL` mode for a
one-record prestate or `MORE` mode for a larger prestate. Abort and every
successful writer rebase scrub the complete sealed transaction certificate;
this is distinct from the operation-scoped reverse-owner proof.

`_EXT4-MEASURE-ORPHAN-DEPTH0` applies the same per-record authentication without
allocating a writer or publishing an after-image. An already-truncated record
costs one protocol home for a modern slot or a terminal legacy head; a
nonterminal legacy head also needs the target inode-table home to clear its
consumed `i_dtime` successor. A nonempty modern root starts with the target
inode table, primary super, and orphan-file block; a nonempty legacy root
starts with the target inode table and primary super. Both add one uniquely owned block
bitmap per touched group and one copy of each distinct primary GDT page. Thus
the canonical one-block linked-truncate legacy fixture has exact credit four, while its
already-truncated form has credit one. The geometry-bounded, constant-space
group scan imposes no candidate array or cleanup-specific capacity. Checked
arithmetic, complete range/static/journal anti-alias validation, and unique
bitmap-owner proofs make the result the coalesced home count rather than an
upper bound. The sealing builder independently requires its staged active-home
count to equal the measured credit, so media or plan drift remains fail-closed.
An admitted unlinked target instead measures its inode table, inode bitmap,
inode-group GDT page, and primary super for exact credit four under legacy
cleanup; the distinct modern orphan-file home makes that five. A nonempty
extent adds one block-bitmap home per touched data group and each distinct
data-group GDT page not already represented by the inode-group GDT page. The
canonical one-block fixtures therefore measure five legacy or six modern
homes. The qualified two-block group-boundary fixture measures six legacy or
seven modern homes: it touches two bitmap homes while both data descriptors
and the inode descriptor coalesce into the same primary GDT page.

This is a non-emitting staging boundary. The typed builders may issue checked
reads for locator and checksum reauthentication, but they do not activate a
journal, emit a transaction, checkpoint a home block, write, or flush. Before
emission their results exist only in private writer memory. `_EXT4-JTX-ABORT`
performs no volume I/O: it scrubs staged entries, images, and hashes, refunds
the log reservation, clears both writer scratch blocks, and returns the writer
to `IDLE`. Neither staging nor abort completes orphan cleanup or grants a
public write capability.

`_EXT4-COMPLETE-ORPHAN-PLAN` is the production mount client of that private
transaction machinery. Before allocation or a cleanup write, it authenticates
and measures every record in the supported union, takes an arena mark, and
allocates one reusable temporary writer sized to the maximum exact record
credit. It selects the legacy head until the legacy chain is empty, then the
lowest unsigned modern `(logical-block, slot)`. Each selected record is
dry-staged and aborted, then staged, emitted, and checkpointed as one exact
transaction. Checkpoint strictly rebuilds the plan before the next selection;
the loop ends only at authenticated empty-union, root, and attachment proofs.
Every exit scrubs and rolls back the temporary arena tail so recovery geometry
cannot constrain a later public writer.

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
a nonempty orphan plan. Sealed orphan `FINAL` and `MORE` modes instead use a
private pre-home reload that performs the same super, group, backup,
orphan-union, and journal authentication but replaces the public nonempty-
policy refusal with an exact writer-certificate comparison. It requires the
selected record to remain in the completely rebuilt plan, the plan's total and
per-protocol counts to equal the certified prestate, the raw target identity
and table location, the selected protocol's raw locator and authority, and the
frozen retained target/protocol images to match.
Modern authority is the orphan-file generation, mapping, physical home, and
slot; legacy authority is the raw primary-super checksum, head inode, retained
successor, and primary-super home. The active primary and guard, transaction ID,
start/head/cursor, every descriptor home and unescaped payload, every revoke
identity, the commit, the exact zero sentinel, and the retained entry/image
CRCs must describe the same single committed transaction. A mismatch fails
before home mutation. Delete-specific modes also rebuild the raw unlinked
inode/allocation authority and rerun the complete target-inode, bitmap, GDT,
and super after-image proof. For a data delete that proof streams over the
entire certified physical range, reconstructs every touched block-bitmap
after-image, and aggregates all descriptor edits on each coalesced GDT page.
After home writes, checkpoint rereads every retained metadata home, requires
its complete image and CRC, proves the target inode record and allocation bit
are clear, and proves every certified range bit is clear with every derived
bitmap and GDT home retained before accepting the protocol-specific poststate.
That poststate must omit the selected inode from the orphan union, decrease the
total and selected protocol counts by exactly one, and leave the other protocol
count unchanged.
`FINAL` additionally proves authenticated emptiness; `MORE` proves that at
least one authenticated record remains.

After that preflight, checkpoint writes each retained active metadata
after-image to its home block. Ordered data is not rewritten because emission
made it durable before commit, and revoked/cancelled entries grant no home-write
authority. All metadata home writes cross one volume flush, followed by a
strict reload and root validation, before any journal block or reservation can
be reused. Both the post-home proof and the final post-reset proof remain
ordinary strict reloads. Every orphan transaction requires the certified exact
decrement at both boundaries, while `FINAL` additionally requires the
authenticated empty-orphan predicate. Thus neither `FINAL` nor `MORE`
admission can survive a mismatched first home-write boundary.

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
| Clean and non-write-active, with or without a dedicated writer profile | Prove the clean endpoint, scrub and release any dedicated profile, and detach without media writes. |
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
remain read-only. Geometry- and arena-bounded transactional completion is
implemented for unions of the exact linked zero-size inline-depth-0 and
empty/single-contiguous-inline-depth-0-extent unlinked-inode cases under both
orphan mechanisms. The implementation adds no fixed cleanup record-count
constant; positive union-drain qualification currently reaches two records.
Before a linked cleanup may release storage, it publishes every physical
range in the inline root together and performs one complete allocated-inode
scan. Any data, map-metadata, or external-xattr reference from another inode
to any of those ranges is a corrupt cross-link refusal. The operation-scoped
certificate binds the context, inode, generation, range count, and all ordered
range pairs; it may bridge measurement, dry staging, activation, restaging,
and journal emission, but checkpoint invalidates it before its first home
write. Whole-union qualification performs this proof for every retained
linked record before the first cleanup transaction may mutate media.
Per-shape single-record qualification includes initialized and unwritten
extents, nonzero logical starts, and a physical range crossing two data groups.
Pinned e2fsprogs accepts final
empty-delete media at 1 KiB, ordinary one-block-delete media at 1/2/4 KiB, and
the new multi-block 1 KiB results for both orphan protocols. Broader per-record
orphan shapes, the complete user-visible mutation layer, external-tool
inspection of active Akashic-created journal
endpoints, and the remaining release gates must still land before public write
capabilities can be enabled.

The first ordinary-data mutation is also implemented as a private staging
primitive. It admits a linked regular file with an authenticated extent map,
including maps with external extent-tree nodes, and overwrites a nonempty byte
range wholly contained in one existing initialized block. The transaction
shape is exactly one ordered data block, one inode-table metadata block, and
no revokes. The ordered image is a full-block read-modify-write copy; the
metadata image preserves every other inode-table byte, updates `mtime` and
`ctime` from explicit seconds and nanoseconds, and restamps the ext4 inode
checksum. Staging neither emits nor checkpoints the transaction and grants no
public write capability.

Before retaining either after-image, the primitive authenticates the complete
target tree under a scoped mutation audit. Every target leaf range and external
extent node is checked against journal, primary-super/GDT, descriptor, bitmap,
inode-table, and sparse-super/GDT roles. Leaf-local validation rejects physical
overlap within each leaf; the scoped audit additionally requires the selected
physical block to occur in exactly one leaf across the complete tree and never
as an external node. A nonzero external-xattr block must differ from the
selected block and pass the same mutation-role check.

The exact inode-table home is authenticated separately. One filesystem-wide
other-inode walk then publishes both transaction destinations—the selected
data block and inode-table home—and refuses either range through another
allocated inode's data, extent/legacy map metadata, or external-xattr pointer.
The target's generation, locator, complete map, size, link count, flags, and
external-xattr pointer are reauthenticated after each cache-clobbering scan. A
stale generation, hole, unwritten extent, unsupported inode flag, cross-block
write, growth, duplicate selected-block mapping, or ambiguous ownership fails
before publication. Once ordered data has been retained, any later staging
failure aborts and scrubs the transaction.

Depth-positive qualification writes logical block 10 of the supplemental
12-block extent-tree fixture through its real depth-1 root and external node.
The generic VFS path checkpoints the selected data block and inode-table home,
reads the replacement back through the unchanged tree, never writes the
external extent node, and cleanly unmounts. A checksum-valid adversarial leaf
that maps logical block 0 onto its own extent-node block is refused as
`EXT4-D-DATA-MAP`; relocating the valid node into an unused journal-ring block
is refused as `EXT4-D-JOURNAL`; and two independently valid external-leaf
shapes that repeat the selected physical block are refused on the second hit.
The paired other-owner qualification separately exercises refusal through its
second range and success for the actual data/inode-home pair. The write-path
refusals return with scoped authority cleared and perform no write or flush;
the standalone two-leaf parser qualification explicitly closes its test scope.
Deeper trees use the same bounded parser and mutation audit, but the real
mutation fixture currently qualifies depth 1.

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
to it. `actual` is now the conservative contiguous prefix of caller bytes
confirmed by the ordered-data write, rather than a checkpoint-success bit. For
the full-block RMW, if `c` whole 512-byte sectors completed and the caller
range begins at byte `o` within the block, the exact rule is
`min(count, max(0, c * 512 - o))`. A tear inside the next sector proves none of
that sector. Once the full ordered block has been accepted, descriptor,
commit, proof, or checkpoint failure reports the complete caller count.

Every error with nonzero `actual` has `VFS-IOR-F-PARTIAL`, including an error
with `actual = count`. A low-level torn-sector error may retain `PARTIAL` even
when the conservative caller prefix is zero. Writer quarantine preserves the
first error's domain, reason, detail, and causal flags, adds
`VFS-IOR-F-READONLY` at the mounted-client boundary, and leaves the VFS
`RO|DIRTY`; same-mount retry is therefore forbidden without discarding the
original diagnostic. Bytes after `actual` are indeterminate, not asserted
unchanged. A checkpoint-entry refusal after commit is explicitly latched at a
valid checkpoint phase rather than leaving replayable authority available for
same-session retry.

Focused mounted-client qualification separates media-clean refusal from the
long durability journey so each remains within its measured emulator
watchdog. Zero length leaves the arena unchanged; a stale generation allocates
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

Fault qualification now crosses a 512-byte boundary inside one initialized
block. A 24-byte request beginning at byte 500 tears six bytes into the second
sector after the first sector completed: the callback reports exactly 12
confirmed bytes even though raw-media inspection shows that six later caller
bytes also changed. A separate body-flush failure occurs after the ordered
block completed and reports the full nine-byte request with
`PARTIAL|READONLY`. Both cases retain the exact underlying writer fault,
quarantine the mounted instance, scrub the private source snapshot, preserve
the old inode-table home, and publish no vnode timestamps.

A second private word, `_EXT4-WRITE`, now has the exact ABI-1 callback shape
`( source count offset dentry vfs -- actual ior )`. It validates an owned,
linked regular-file dentry, its shared vnode identity/generation and clean
cached state, and a nonwrapping size-preserving caller range. A nonempty call
derives `min(count, block_size - (offset mod block_size))` and sends exactly
that first block-bounded chunk to the mounted client. A larger request
therefore returns legal short success rather than widening the qualified
`1/1/0` transaction or refusing merely because the caller span crosses a
block. `VFS-WRITE-EXACT` or another caller may advance the buffer and offset
and invoke the callback again. The callback passes the vnode's ext4 inode
number and generation and never owns or advances an FD cursor. Exact
checkpointed success publishes only `mtime`/`ctime` seconds and nanoseconds
into the shared vnode, making the result immediately visible through every
hard-link alias. Size, blocks, atime, link count, identity, generation, and
vnode-dirty state remain unchanged. Any failure publishes no vnode fields.

Block-bounded qualification supplies 1,040 caller bytes at offset 1,016 of the
3 KiB sparse fixture. The allocated first block checkpoints exactly eight
bytes and returns `actual = 8, ior = 0`; the caller-shaped retry advances its
buffer and submits the 1,032-byte suffix at offset 1,024, where the hole is
refused before another media transaction. The first timestamp remains
published, the writer stays idle-clean and allocation-stable, and clean
unmount emits the ordinary deactivation trace. This pins both removal of the
old `count <= block_size` limit and safe cross-block short progress without
claiming hole allocation or a multi-block atomic transaction.

Generic cursor qualification uses a cloned test-only binding: its private
copy of the operation table installs `_EXT4-WRITE`, its copied capability mask
adds `WRITE`, and only its copied flags clear `READ_ONLY`. The production
`EXT4-BINDING`, `EXT4-CAPS`, and `EXT4-OPS` are asserted unchanged. Through
that clone, `VFS-WRITE-EXACT` starts an FD at 1,016 and drives `VFS-WRITE?`
twice. The first call checkpoints eight bytes and advances the FD, source, and
remaining count; the second preserves the later `EXT4-D-RECOVERY` refusal at
the logical-block hole with the cursor at 1,024. The clock sample consumed by
the failing attempt is not published, the writer remains idle-clean, the FD
closes, and ordinary clean unmount succeeds. This qualifies ABI-1 composition;
it does not change public ext4 write admission.

The same cloned binding qualifies generic fault propagation. An ordered-data
tear during a 24-byte `VFS-WRITE?` at offset 500 changes 18 raw caller bytes
but certifies only the 12-byte prefix ending at the first complete sector.
The call returns `actual = 12` with `PARTIAL | READONLY`, advances the FD to
512, records that result in `V.LAST-IOR`, and quarantines the writable clone as
read-only and dirty. The writer retains the causal volume fault with `PARTIAL`
but without the derived `READONLY` consequence. A retry is rejected by generic
VFS admission before callback or clock dispatch, leaves the cursor at 512, and
does not replace `V.LAST-IOR`; vnode times, size, and dirty state remain
unpublished. This distinguishes certified cursor progress from raw torn-sector
effects and pins the retry boundary after quarantine.

The callback obtains time from a caller-installed per-context provider rather
than ambient `EPOCH@`. `_EXT4-BIND-WRITE-CLOCK` binds it once at an
authenticated clean mounted endpoint before the first mutation. Clock and
dedicated-profile binding may occur in either order while the profile remains
untouched, idle, and clean. The provider contract is
`( clock-context -- epoch-ms ior )`; one nonzero write samples it exactly once
and converts the admitted scalar to ext4 seconds/nanoseconds. Zero-length
writes do not sample or publish time. The binding survives strict reload,
checkpoint, and live sync/deactivation.

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

`_EXT4-WRITE` remains absent from `EXT4-OPS` and `EXT4-CAPS`, but the exact
slice now has an honest VFS progress/error contract. Generic `VFS-WRITE?` may
advance only the calling FD by the returned confirmed prefix; the callback
itself still owns no FD. Public exposure remains a separate gate because the
binding is still globally read-only and lacks operation-specific chunk
planners, general data shapes, and the complete release qualification required
by the writable profile.

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
  nodes, sparse holes, unwritten-zero semantics, and an explicit ext4 u32
  logical end-exclusive bound independent of the host cell width; the
  supplemental real
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
bounded per-operation credit/chunking contract, general block and inode
allocation,
extent and legacy-map growth and shrink, directory-entry mutation,
inode/link/time/accounting updates, xattr mutation, namespace/cache coherence,
broader per-record orphan shapes, and interoperability plus power-cut
qualification.
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
shape. Its post-publication progress/error policy is now represented honestly;
the operation remains private while general operation planning, public
admission, and broader crash/interoperability policy are unsettled.
Growth, holes, unwritten extents, multi-block atomicity, truncation, and
namespace mutation remain later phases.

The remaining boundaries are:

- POSIX ACL xattrs are returned as raw bytes, but generic permission
  enforcement is not claimed;
- the real external-tool extent fixture has depth 1 and now qualifies both
  reading and the private one-block overwrite, while deeper trees have only
  bounded structural traversal through the profile limit of 5;
- the real special-inode fixture covers FIFO, character, and block devices,
  but not a socket inode;
- replay currently requires checksum-v3/64-bit journal records, supports
  checksummed 64-bit revoke records, and fails closed on checksum-damaged
  incomplete tails;
- recovery/write authority deliberately requires the group-1 sparse-super/GDT
  witness and the checksum-covered inline depth-0 journal tuple; external
  journal-map nodes are not recovery authority. Clean primary-only authority
  for a one-group filesystem is not implemented, so those otherwise readable
  filesystems currently fail closed at journal validation;
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
  zero-size inline depth-0 extent truncation, exact empty/single-inline-
  depth-0-extent unlinked data and inode allocation release, target-record
  scrubbing, exact credit measurement, modern-slot removal, legacy-head
  advancement, and operation/protocol-specific `FINAL`/`MORE` certificates now
  compose one sealed transaction for either orphan mechanism. Production mount
  authenticates and measures the entire supported union before cleanup writes,
  allocates one writer at the maximum exact per-record credit, then drains
  legacy-head-first followed by modern `(logical-block, slot)` order. Every
  record is dry-staged and aborted, then restaged, emitted, checkpointed, and
  strictly reauthenticated before the reusable writer begins the next
  transaction. Publication follows only authenticated empty-union validation.
  The temporary mount writer is scrubbed and rolled back rather than becoming
  the production workspace;
- unified legacy-chain and modern orphan-file discovery, inode preflight, and
  authenticated-empty `ORPHAN_PRESENT` completion are implemented. The shared
  exact-count plan retains protocol-specific locations and enforces inode
  uniqueness across the union. Empty completion is authorized only when both
  protocol counts are zero and mutates only journal recovery state and the
  checksummed primary-super transient bits; it does not change an orphan
  inode/file, a legacy link, allocate writer workspace, or expose a
  user-visible write. Cleanup derives its record count from authenticated
  geometry, checked arithmetic, and caller-arena storage rather than a separate
  fixed constant, but still does not cover nonzero-size or tail truncation,
  depth-positive extent trees,
  legacy direct/indirect map mutation, an unlinked inode with more than one
  extent, a nonzero physical high word, a depth-positive root, an external
  xattr block, an inline xattr value inode, external-xattr/value-inode release,
  or general link-count and malformed-chain repair. General inode
  allocation, general inode release outside the admitted shape, and every
  user-visible mutation operation remain unimplemented. Cleanup releases
  allocation authority but does not provide secure deletion or data-block
  erasure;
- focused single-record, per-shape empty/single-extent unlinked qualification
  covers modern and legacy mount completion. Empty and one-block baselines span
  the canonical 1/2/4 KiB, 256-byte-inode geometries; 1 KiB qualification additionally
  covers a three-block initialized extent at logical block 7 and a two-block
  unwritten extent at logical block 11 whose physical range crosses data
  groups 3 and 4. The fixture construction and post-mount allocation-accounting
  oracle derive the primary GDT page, data and inode bitmap homes and bits,
  free-block and free-inode counters, and conservative `itable_unused` result
  from each image rather than relying on the 1 KiB layout. It pins exact
  four/five-home credit for empty legacy/modern cleanup and five/six-home
  credit for the canonical one-block and same-group three-block cases. The
  cross-group range pins six/seven homes because two data bitmaps share the
  inode GDT page. Qualification also covers delete-specific sealing and
  mutation freeze, complete abort scrubbing, exact target-record zeroing with
  sibling inode-table bytes preserved, every allocation bit and group counter,
  unchanged distinct nonzero released-block payloads with no overlapping
  data-home write, a byte-identical zero-I/O clean remount, and
  descriptor/super accounting. Structurally valid resident inline
  xattrs are scrubbed
  with the target record; an inline value-inode reference is refused as
  unsupported, and unexplained nonzero `i_blocks` is rejected as corruption.
  Mount-level refusal covers a nonzero physical high word, external xattrs,
  orphan-storage aliasing, a clear one-block data bit, and a two-block extent
  whose second allocation bit is clear.
  Checksum-valid allocated live-inode fixtures additionally prove that both a
  data extent and an external-xattr pointer aliasing the candidate are
  rejected as `EXT4-D-DATA-MAP` before writer allocation or media mutation.
  A three-block candidate whose middle block alone is named by a live inode
  proves that reverse-owner admission covers the complete range. Both orphan
  protocols are qualified; the same-binding retry returns the same refusal
  with the scoped ownership proof and ambient probe cleared.
  Direct exact-shape preflight coverage additionally rejects multiple inline
  extent entries and depth-positive roots before writer allocation or media
  I/O. Every
  refusal fails before writer allocation or any write/flush. The established
  1 KiB cross-group fixture qualifies separate data- and inode-group
  descriptors coalesced into one primary GDT home; the new boundary fixture
  proves that one certified data range may itself cross two groups while both
  data descriptors and the inode descriptor coalesce into that home. Pinned
  e2fsprogs 1.47.4 accepts both protocols for the empty 1 KiB result, ordinary
  one-block 1/2/4 KiB results, the initialized-offset and cross-group unwritten
  multi-block results, and the 1 KiB same-GDT-page cross-group and one-block
  resident-inline-xattr variants. The established linked
  modern/legacy seal and mount paths pass against the shared `FINAL`/`MORE`
  mode and checkpoint changes. Two-record 1 KiB empty-root fixtures qualify
  modern-only, legacy-only, and mixed legacy/modern unions, including two
  sequential exact transactions, maximum-credit writer reuse, final allocation
  accounting, and a byte-stable zero-I/O remount. The separate pinned
  e2fsprogs 1.47.4 acceptance test for these new outputs remains a pending
  release qualification gate.
  The mixed fixture additionally crosses the second-transaction commit/home
  durability fence: both the surviving writes and the preceding durable
  snapshot converge on a fresh mount and then remount without another write.
  Pinned e2fsck 1.47.4 acceptance of those repaired outputs remains a pending
  release qualification gate. A linked legacy `18 -> 21 -> 0` fixture
  additionally runs
  the real `MORE`, successor-plan rebuild, terminal `FINAL`, and clean
  deactivation path. It proves the exact 42-write/35-flush trace, the
  intermediate `i_dtime` clear, byte preservation of the terminal inode, and a
  zero-I/O remount. A companion journey gives the linked head one uniquely
  owned block: its four-credit transaction seals plain `LEGACY_MORE` with one
  target extent, clears the extent and `i_blocks`, restores the exact block
  bitmap/GDT/super free counts without touching payload bytes, advances to the
  terminal `FINAL`, and remounts with zero I/O. That synthetic protocol-state
  fixture intentionally has no
  namespace dirents for inodes 18 or 21; it is not an e2fsck oracle and is not
  claimed as an e2fsck-clean namespace image. A
  later-valid two-extent record proves whole-union refusal after an earlier
  supported record qualifies but before any write or flush. Structurally valid
  post-seal total-count, protocol-split, and `MORE`/`FINAL` substitutions all
  fault at checkpoint preflight with zero home writes. A linked-owner matrix
  places a live-inode alias in the later selected record: a two-entry modern
  root and a four-entry legacy root both fail whole-union qualification as
  `EXT4-D-DATA-MAP`, leave the earlier safe record untouched, perform no write
  or flush, preserve the caller arena on retry, and clear the ambient range
  table and operation certificate. The per-shape
  single-record empty-case controlled matrix covers
  eight modern and seven legacy write prefixes: both sides of final commit,
  every operation-specific metadata home, and final-super publication. Three fences
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
  first `MORE` transaction still needs commit, partial-home, reset, witness,
  guard-retirement, and flush-fence crash qualification while its successor
  remains active; linked `MODERN_MORE` and modern/legacy
  `DATA_DELETE_MORE`, plus successful multi-range linked release, also lack
  positive oracles. The
  one-block-specific commit and final-super flush fences, shared
  activation/reset prefixes, broader ownership shapes, and active-journal
  external-tool inspection also remain to be qualified;
- focused 1 KiB coverage exercises one- and two-inode legacy chains, a mixed
  legacy/modern union, stable refusal with same-binding plan reuse, legacy
  cycles and invalid links, unallocated and checksum-invalid legacy inodes,
  and cross-protocol duplicate rejection without writes. Passing per-shape
  single-record legacy cleanup coverage across 1/2/4 KiB geometry now includes
  the 32-write/24-flush successful mount. Focused 1 KiB coverage additionally pins
  exact one-home already-truncated sealing with zero target entries, exact
  four-home one-block linked-truncate sealing with one target entry, post-seal mutation
  refusal, and abort scrubbing. Its controlled crash matrix covers 14 write
  prefixes spanning activation, transaction description and commit, every
  legacy metadata home, reset, final-super publication, witness clearing, and
  guard retirement. It also covers all nine durability fences; both the writes
  surviving each failed flush and the preceding durable snapshot independently
  repair and then remount without another write. Unified discovery still needs
  qualification for unions larger than two records, including longer legacy
  chains and three-or-more modern/mixed sets; later modern blocks and files
  beyond the former 4096-block limit; additional unlinked ownership shapes and
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
