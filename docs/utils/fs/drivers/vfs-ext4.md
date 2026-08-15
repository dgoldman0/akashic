# akashic-vfs-ext4 — checksummed ext4 bindings

IMPORTANT: STEP CEILINGS ARE NOT CRITICAL COMPARED TO CRITICAL PROPER FUNCTIONING. DO NOT SCRUB PROPER FUNCTIONALITY FOR ARBITRARILY SET STEP LIMITS. STEP AND OTHER LIMITS DETERMINED BY IDENTIFIED SYSTEM RESOURCES AND MONITORING.

This VFS ABI 1 driver reads filesystems in the pinned
`akashic-ext4-rw-v1` profile from one explicit KDOS volume. It publishes two
different descriptors. `EXT4-BINDING` is the ordinary read-only surface.
`EXT4-STAGED-WRITE-BINDING` is the current explicitly staged write surface for
authenticated 1 KiB/256-byte-inode geometry. It
supports block-bounded overwrite of initialized extents, strict no-gap append
inside an already allocated partial EOF block, and allocation-backed fill of
complete logical holes inside the existing file size under the extent-root
conditions described below. It also performs allocation-backed no-gap growth
one initialized block per callback from exact aligned EOF under that
authenticated resident-root insertion, coalescing, single-leaf-composition, or
resident depth-one leaf edit/split envelope. `VFS-WRITE-EXACT`
composes a qualified request from an initialized partial tail or aligned EOF
through additional newly allocated logical blocks. That route uses an optional
`1/1/0` tail RMW followed by independently checkpointed allocation
transactions through one reusable writer. An ordinary resident-root
insert/coalesce uses `4/1/0`; a saturated unmergeable resident root is composed
into one external leaf under an exact topology-derived `5/1/0`, `6/1/0`, or
`7/1/0` transaction. Allocation may then continue from a resident depth-one
root containing one through its authenticated inline index capacity: the root
selects the governing checksum-valid leaf, and insertion with a spare leaf slot
or exact in-place coalescing uses `5/1/0` for the bitmap, GDT, primary
superblock, selected leaf, and inode homes. If that leaf is full and cannot
coalesce, it splits while the resident root retains an index slot, under exact
topology-derived `6/1/0` through `8/1/0` credit. A full root remains editable
when the selected leaf has room; a full root plus an unmergeable full selected
leaf is the typed unsupported depth-growth boundary. Each callback is independently
committed and synchronously checkpointed, targets at most one logical block,
and makes no cross-callback atomicity promise. Free-block selection may cross
from the target inode's initialized group into a later initialized group; the
current public evidence covers a group-0-to-group-1 transition whose
descriptors share one primary GDT block, a group-0-to-group-16 transition onto
the next primary GDT block, and a two-allocation root-composition transaction
whose data and leaf accounting span distinct bitmaps and distinct primary GDT
pages, plus a same-group singleton-leaf split. The broader 1/2/4 KiB and
128/256-byte-inode forms remain available to
read and recovery paths; 2/4 KiB and 128-byte-inode mutation await equivalent
qualification. The staged surface additionally provides atomic empty-file
`CREATE` in authenticated one-block linear-directory slack. Its `TRUNCATE`
surface includes strict same-retained-block shrink under exact `2/0/0` credit
and one block-releasing shrink-to-zero shape. The latter accepts one initialized
depth-zero extent, first commits the zero-size inode into either an empty modern
orphan union or the first free slot of an existing authenticated modern-only
union, then uses the existing linked-orphan cleanup to release the data block,
and finally clears transient `ORPHAN_PRESENT` after the complete union drains
while leaving the mounted writer active. The
staged surface also provides two `UNLINK` lifetimes. A regular inode with more
than one link may lose one same-parent name without changing allocation, even
when an open descriptor retains the removed dentry. An already-empty inode
with one link and no external allocation may
lose its final name and inode allocation in one at-most-six-home transaction.
Neither shape creates orphan state; nonempty final-link removal and open
final-link removal remain later boundaries. The same surface now provides a
bounded atomic `MKDIR`: it allocates one inode and one globally unowned block,
builds a canonical checksummed one-block `.`/`..` directory, inserts its typed
name into the authenticated one-block linear parent, and updates parent links,
free-space, and `used_dirs` accounting in one exact `7/0/0` through `9/0/0`
transaction. It also provides bounded empty-directory `RMDIR` for that exact
canonical child shape. Removal atomically splices the typed parent entry,
decrements the parent link and group `used_dirs` count, frees the child inode
and data block, and revokes the freed directory-block home under exact
`6/0/1` through `8/0/1` credit; the canonical fixture uses `7/0/1`.
The staged binding also provides bounded hard `LINK` for an authenticated
root-owned regular inode and one-block linear destination parent. It adds the
typed directory record, increments the target link count, and updates target
and parent timestamps under exact deduplicated `2/0/0` or `3/0/0` credit,
without allocation, ordered data, revoke, or orphan state.
The staged binding now includes qualified atomic no-replacement `RENAME` for
regular files and one cross-parent empty-directory slice. Regular-file
same-parent rename keeps the in-place rewrite fast path when the source record
is large enough; otherwise it deterministically compacts the authenticated
block without allocating another block. Regular-file cross-parent rename
canonically compacts the source block while removing the old record and the
destination block while appending the renamed record. It uses exact
deduplicated `3/0/0` through `5/0/0` metadata credit; the canonical fixture is
`4/0/0` over homes 278, 275, 1345, and 1299. The directory slice admits only a
canonical empty source moved between distinct admitted parents. In addition to
the two parent blocks and inode roles, it journals the child directory block,
transfers one parent link, and rewrites the child's `..` entry and checksum
under exact `4/0/0` through `6/0/0` credit. Its canonical `5/0/0` homes are
283, 275, 1299, 1377, and 1364. Neither form allocates storage or creates
orphan state. Same-parent directories and replacement remain gated.
Directory growth, HTree parents, inheritance beyond the explicit root-owned
non-setgid envelope, and broader directory shapes remain gated. The driver
also implements bounded mount-time recovery and
durable transaction emission for an internal checksum-v3 JBD2 journal. It never
uses the ambient filesystem volume: reads and all recovery, activation,
emission, checkpoint, and clean-deactivation writes go through checked volume
operations relative to the supplied `VOL-RAW` or `VOL-SLICE` object.

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

The checked-in 1,250,000,000-step ext4 cold-source value is a qualification
watchdog and measurement guide, not an ext4 implementation capacity or a
reason to weaken functionality. With qualified cross-parent empty-directory
`RENAME`, the source measures 1,224,225,598 ext4-load steps across 3,095
packed lines, leaving 25,774,402 steps of measured headroom. If correct source
legitimately outgrows it, the budget
must be revisited from measured system resources. The harness still performs a
real cold source build and requires the `EXT4-SOURCE-READY` marker with no
Forth diagnostic. At the hardware-CRC benchmark baseline recorded by `6531ef0`,
the base snapshot measured 135,845,261 steps, the hardware CRC module cold-
loaded in 4,992,533 steps across 26 packed lines, and the production ext4 source
then cold-loaded in 832,013,844 steps across 2,389 packed lines under its
watchdog. At `851d2c6`, the expanded production source measures 853,752,745
steps across 2,431 packed lines under the same watchdog. Singleton depth-one
existing-leaf allocation then measured 862,136,179 steps. With full singleton-
leaf splitting enabled, that source measured 871,995,119 steps across 2,455
packed lines under the then-current watchdog. Runtime recovery
journeys use a separate 1,200,000,000-step default watchdog. The 18-group
cross-primary-GDT-page success fixture uses a scoped 1,300,000,000-step guard
and completes in 1,224,541,529 steps; its stable remount takes 149,039,299.
Geometry-bounded multi-record production and selected
multi-record fault journeys use a scoped 1,500,000,000-step watchdog because
the real cold-source path plus repeated whole-plan authentication legitimately
crossed the default. The mixed successful cleanup measured 1,209,747,492
steps; linked one-block `LEGACY_MORE` measured 1,102,821,323, linked one-block
`MODERN_MORE` now measures 1,185,669,720, and repair from the durable image
immediately before the legacy commit fence measured 1,366,762,951. Focused
modern orphan-home and complete-home-fence repair measures 771,167,177 steps,
with a 55,254,562-step write-free remount. The
multi-range data-bearing two-record unlinked journeys have a separate
3,000,000,000-step watchdog because the persistence harness traces every
write and flush around dry staging and real emission. The modern two-range
production journey measures 1,786,988,013 steps and the legacy four-range
journey measures 2,196,652,327; each clean remount measures 55,772,107. The
modern `ADD_MORE` orphan-home tear journey, which first replays the insertion
and then drains two independently data-bearing linked records, measures
1,679,279,160 steps under that same watchdog; its write-free stable remount
measures 44,133,436. The public retained-union `TRUNCATE(0)` composition
journey measures 1,656,718,410 steps under the same unchanged watchdog. The
clean insertion and injected-fault setup journeys
measure 519,567,371 and 421,722,917 steps respectively. The
direct COW stage/seal/abort workloads without persistence tracing measure
615,185,969 and 825,905,086 steps respectively. These are workload-specific
harness measurements, not physical-runtime projections. Neither watchdog is
an implementation capacity. The default was
established after the fresh-proof W18 crash-repair
journey exceeded the old ceiling; the measured journey completed in
811,281,646 steps, on one core, below 1 GiB peak RSS with no swapping. It is
historical sizing evidence, not a claim that W18 is rerun for every source
revision. `EXT4_REPORT_STEPS` reports actual use and source/backing media;
budget failures include used and allowed steps. The current source passes cold
builds and focused recovery qualification without a compiled cache or
certificate-preservation shortcut.

At bounded hard-`LINK` closure, the production source measured 1,140,381,589
steps across 2,962 packed lines in source mode. The then-approved 1.15-billion
watchdog left 9,618,411 steps, about 0.84 percent measured growth margin. That
is the historical pre-`RENAME` baseline, not a filesystem or implementation
capacity. The corresponding descriptor journey completed in 4,230,599 steps.
The first qualified in-place `RENAME` revision used the 1.20-billion source
watchdog and measured 1,168,101,972 ext4-load steps across 3,003 packed lines.
After same-block compaction qualification, the exact cold source measures
1,176,731,432 of 1,200,000,000 steps across 3,017 packed lines, and the
descriptor journey measures 4,445,902 steps. After cross-parent regular-file
no-replacement qualification, exact cold source mode measures 1,219,522,351
of 1,250,000,000 steps across 3,085 packed lines, and the descriptor journey
measures 4,543,322 steps. After cross-parent empty-directory qualification,
exact cold source mode measures 1,224,225,598 of 1,250,000,000 steps across
3,095 packed lines, and the descriptor journey measures 4,549,770 steps.

## Mounting

```forth
CREATE bd  /BLOCK-DEVICE ALLOT
CREATE vol /VOLUME ALLOT

bd BD-OPEN THROW
bd vol VOL-RAW THROW

524288 A-XMEM ARENA-NEW THROW CONSTANT fs-arena
fs-arena vol EXT4-NEW THROW CONSTANT fs
```

`EXT4-NEW ( arena volume -- vfs ior )` constructs the ordinary read-only
instance and invokes its mount callback. Constructor failure returns an
inspectable VFS in `VFS-L-NEW`, with the structured failure copied to
`V.LAST-IOR`; it never publishes `VFS-L-MOUNTED`.

Use the explicit staged constructor for the current write surface:

```forth
fs-arena vol EXT4-STAGED-WRITE-NEW THROW CONSTANT fs

8 1 0 fs EXT4-WRITER-WORKSPACE-BYTES? THROW
A-XMEM ARENA-NEW THROW CONSTANT writer-arena
writer-arena 8 1 0 fs EXT4-BIND-WRITER-ARENA? THROW

\ APP-NOW-MS ( clock-context -- epoch-ms ior )
' APP-NOW-MS app-clock fs EXT4-BIND-WRITE-CLOCK? THROW
```

The staged mount admits nonempty mutation only on authenticated 1 KiB
filesystem geometry with 256-byte inodes and a journal capable of at least the
`1 metadata / 1 ordered data / 0 revoke` initialized-RMW transaction. These checks
occur during staged mount before it can publish a writable VFS or mutate media.
The allocation-backed hole and aligned-EOF growth operations, including the
allocation leg of a cross-tail exact request, require the journal and bound
writer profile to contain the exact measured topology. An ordinary
insert/coalesce consumes `4/1/0`; single-leaf root composition consumes
`5/1/0` through `7/1/0`; editing a selected resident depth-one leaf consumes
`5/1/0`; splitting its saturated unmergeable leaf while the root has capacity
consumes exact `6/1/0` through `8/1/0`. A crossing request still preflights the
ordinary `4/1/0` allocation floor before the first clock sample or tail
mutation. Each later allocation callback then reauthenticates its current root
and geometry and resolves its exact credit before beginning a transaction, so
a larger root-composition, existing-leaf, or split requirement can cleanly stop
after an independently durable tail prefix. An `8/1/0` containing profile admits every
currently qualified allocation topology. The ordinary constructor retains the
broader read/recovery geometry, including 2/4 KiB filesystems and 128-byte
inodes.

A mounted instance can reserve an initialized-RMW profile as follows (use
`8 1 0` in both calls to admit every currently qualified hole-fill,
aligned-EOF, root-composition, leaf-split, and exact-write topology as well):

```forth
1 1 0 fs EXT4-WRITER-WORKSPACE-BYTES? THROW
A-XMEM ARENA-NEW THROW CONSTANT writer-arena

writer-arena 1 1 0 fs EXT4-BIND-WRITER-ARENA? THROW
```

The three capacities are maximum metadata, ordered-data, and revoke credits;
there is no driver-chosen split or operation-count ceiling. Initialized-block
overwrite and initialized partial-tail append consume `1/1/0`;
allocation-backed hole fill and aligned-EOF growth consume exact
topology-derived `4/1/0` through `8/1/0`. A `1/1/0` profile therefore serves
both initialized-RMW operations. A `4/1/0` containing profile serves ordinary
resident insert/coalesce allocations, a `5/1/0` profile also serves selected
resident depth-one existing-leaf edits, and an `8/1/0` containing profile
serves every currently qualified allocation and exact-write composition. The
sizing query proves
that the complete tuple fits the journal ring,
`s_max_transaction`, and `s_max_trans_data`. Binding requires a fresh dedicated
arena whose backing is disjoint from the VFS arena. Its descriptor, backing,
and bump pointer remain
exclusively owned by ext4 until clean unmount, which scrubs the complete writer
and rolls the arena back to fresh. Busy or faulted unmount retains it for retry
or diagnosis. The caller may destroy the arena only after successful unmount.

`EXT4-BIND-WRITE-CLOCK?` installs exactly one trusted per-instance time
provider with stack effect `( clock-context -- epoch-ms ior )`. Clock and
writer-arena binding may occur in either order at the authenticated clean
mounted endpoint, before the first nonempty mutation. A nonempty staged write
requires both; zero-length writes require neither and do not sample the clock.
`EXT4-BINDING`, `EXT4-OPS`, `EXT4-CAPS`, and `EXT4-NEW` remain read-only and
unchanged by this setup.

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
credit for each supported record. The largest measurement sizes one reusable
temporary writer, with one additional metadata slot when a current shared-xattr
decrement could become a final-owner release after an earlier orphan is
deleted. That topology-derived slot covers the only possible delta: the
retained xattr after-image is replaced by a block-bitmap home and at most one
new primary-GDT page. Each transaction still begins with its exact current
credit. The record count is bounded by
authenticated filesystem geometry, checked arithmetic, and available
caller-arena storage; cleanup adds no separate fixed record-count constant. A
linked record is supported only for a regular file whose zero size is already
durable and which does not use journal-data mode. Its retained data map may be
an inline depth-0 extent root, or an exact empty legacy-format map with the
`EXTENTS` flag clear and all 60 bytes of `i_block` zero. An authenticated
external xattr is retained. An empty map has no release ranges or revokes and
its decoded `i_blocks` must equal only that retained xattr contribution; a
nonempty inline extent root may contain ranges that the bounded free-block
builder can account for exactly. An unlinked target must be an
allocated regular file with zero links and an authenticated nonnegative
63-bit size. Its complete data map may be an empty or one-to-four-entry inline
depth-0 extent root, a resident depth-1 root with one to four checksum-valid
external leaves, or a legacy map using any of the 12 direct slots and one
optional complete single-indirect block. The legacy map may additionally use
an optional double-indirect root with zero or more occupied child pointer
blocks when its exact canonical data-plus-map vector, plus any present
external-xattr owner range, fits the `2P+16` caller workspace for
`P = block_size / 4`. As a separate map family, slot 14 may name one allocated
triple-indirect root whose full block is all zero while the single- and
double-indirect slots remain zero. Direct slots may be occupied. Their ordered
data singletons precede the root's one map singleton under
`LEGACY-SPARSE-TRIPLE` authority; the root contributes one block to `i_blocks`
and receives one exact revoke. This shape remains subject to the same
caller-workspace bound. As a second triple shape, when every direct slot and
the external-xattr pointer are zero, the root may contain exactly one nonzero
pointer to one allocated all-zero level-2 pointer block. Its ordered
`{ triple-root, level-2-child }` map vector is sealed under
`LEGACY-SPARSE-TRIPLE-CHILD` authority; both blocks contribute to `i_blocks`
and each receives an exact revoke. Each depth-1 leaf may use
every entry that fits the mounted block size. Every resident root key must equal its leaf's
first logical block, and each nonfinal leaf must end no later than the next
root key. The external leaves join the exact release and reverse-owner
authority and each receives a journal revoke. The inode size need not be zero
because
deletion releases the complete authenticated map and then removes the inode;
EOF does not select a retained tail.
It may additionally reference one checksum-valid external xattr block. A raw
`h_refcount` of one gives exact allocation-release authority. A count from 2
through ext4's 1024-reference limit instead retains the allocation and permits
only `h_refcount - 1` plus the corresponding block-checksum restamp. The count
must not exceed the filesystem inode count, and one complete allocated-inode
scan must find exactly that many `i_file_acl` references while rejecting the
same block through any data or map-metadata role. Xattr value inodes remain
unsupported. Each extent entry may be initialized or unwritten and
must have a zero physical high word. An initialized decoded length may be
1..32768 blocks and an unwritten decoded length 1..32767 blocks, exactly as
encoded by ext4 `ee_len`; every `logical_start + decoded_length` must be at
most `0xffffffff`. The entries must retain ext4's exact logical ordering and
nonoverlap rules. In a legacy map, zero direct and pointer-block slots are
holes and every nonzero data pointer becomes an ordered singleton release
range. Direct data precedes single-indirect data and then data from every
double-indirect child in outer/inner slot order. Map singletons follow as the
optional single root, double root, and every child in outer-slot order.
Duplicate physical pointers or data/map and map/map aliases are corrupt. An
empty double root is admitted as one map singleton. The all-zero triple root is
likewise one trailing map singleton after zero or more direct data entries. A
separate child-bearing triple root is admitted only with zero direct data and
no external xattr: it may contain one pointer to one allocated all-zero child,
and the root and child become two ordered trailing map singletons. A repeated
child or an alias with the root, direct data, or external-xattr home is
corrupt. A second distinct root child, any nonzero pointer in the admitted
child, direct-data or external-xattr composition with that child, or a present
triple root combined with a single- or double-indirect map remain unsupported.
A double-indirect vector larger than the caller workspace also remains an
unsupported recovery shape. Physical ranges must not overlap each other or the
optional xattr block, and decoded `i_blocks` must exactly equal the aggregate
data, map-metadata, and xattr block count in filesystem sectors.
Every release range must be
allocated, lie outside all static metadata and journal ranges, and not alias
orphan-file storage. One combined filesystem-wide scan of authenticated
allocated inodes must prove that no other extent or legacy data/map-metadata
reference names any block in the complete release set. For a shared external
xattr, the same role-aware scan admits the counted `i_file_acl` references but
still rejects every data or map-metadata alias. A resident inline xattr area is
admitted only after the structural walker
proves bounded, ordered, nonoverlapping values with no value-inode reference.
If even one record is outside these supported per-record shapes, the whole
union returns a stable refusal before writer allocation or cleanup mutation.

Mount drains a qualified union deterministically: the current legacy head and
its authenticated successor chain first, then modern records ordered by
unsigned `(logical-block, slot)`. Each record gets one exact transaction using
the same maximum-sized writer. Mount dry-stages and aborts that record,
activates or converges the recovery journal as required, then stages, emits,
and checkpoints the same sealed cleanup before selecting again from the
strictly rebuilt plan. Modern completion clears the exact orphan-file slot.
Legacy completion advances `s_last_orphan` to the retained successor in the
checksummed primary-super after-image. A linked intermediate record under the
legacy orphan protocol also clears its consumed `i_dtime` link in that
transaction; a terminal zero-successor record whose admitted map is already
empty does not manufacture a no-op inode rewrite. A linked record under the
modern orphan protocol is admitted only with `i_dtime` already zero. An
unlinked delete zeroes the complete target inode record,
including `i_dtime`, without synthesizing a deletion timestamp; the same
transaction clears its inode-bitmap bit and increments the owning descriptor
and primary-super free-inode counters.
For a nonempty map it also clears every certified physical-range allocation
bit, increments each touched group by the sum of its exact range chunks, and
increments the primary-super free-block counter by the aggregate certified
data-block count. Released data
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

Every ext4 and JBD2 checksum is computed by MegaPad's shared reflected CRC32C
engine through Akashic's checked `CRC32C-RAW?` interface. The driver has no
software checksum table or fallback. Probe and mount require the hardware
capability before issuing media I/O. Engine status 1 becomes a binding-domain
unsupported error, status 2 becomes a retryable binding-domain busy error, and
other nonzero hardware or Forth failures become binding-domain I/O errors with
their original status retained as detail. A fragmented checksum releases the
engine after each fragment and carries the returned raw accumulator forward;
a post-acquisition fault unwinds the transaction as the same owner, while a
rejected acquisition leaves the existing owner untouched.

The checked status is threaded through validation, replay, orphan cleanup,
journal activation/emission/checkpoint/deactivation, and public write staging.
Transaction staging computes each checked image CRC before publishing a table
entry, hash slot, count, or after-image, so a busy or failed engine leaves the
complete writer-owned span unchanged. This is current production behavior for
the documented capability envelope, not a fixture-only checksum model.

The 2026-08-11 hardware-CRC qualification used cold source mode throughout.
Focused capability, ownership, fragmented-seed, negative-length-unwind, and
fail-atomic staging proofs passed. Representative ext4 gates then passed a
checksum-v3 replay with durable idempotent remount, modern one-block orphan
cleanup, two staged writes followed by stable remount plus pinned `debugfs`
readback and `e2fsck`, committed inode-home checkpoint-tear recovery, and
superblock-corruption refusal before mount publication. The measured guest
journeys were respectively 166,679,303 + 39,640,092; 898,232,073;
689,723,144 + 45,222,390; 310,969,314 + 177,572,396 + 40,229,230; and
24,516,008 steps. These representative gates qualify the shared checksum
cutover without reopening the full orphan or power-cut matrix.

A controlled paired benchmark compared the pre-cutover `d44323f` with the
hardware-CRC qualification commit `d08537d` (the executable cutover is
`3efc593`) on the same MegaPad accelerator, host, canonical image, pinned
e2fsprogs prefix, and two-test pytest process. The base snapshot was identical
at 135,845,261 steps in both runs.

| Measured phase | `d44323f` software CRC | Hardware CRC | Change |
| --- | ---: | ---: | ---: |
| Checksum + ext4 cold source | 922,146,018 | 837,006,377 | -9.23% |
| Superblock-corruption refusal | 39,184,937 | 24,516,008 | -37.44% |
| Checksum-v3 recovery | 228,448,399 | 166,679,303 | -27.04% |
| Recovered-image mount/read | 54,971,663 | 39,640,092 | -27.89% |
| Runtime journey subtotal | 322,604,999 | 230,835,403 | -28.45% |

The complete pytest process fell from 56.74 to 52.44 seconds (-7.58%). Guest
steps are the primary deterministic comparison; host scheduling, fixed snapshot
construction, Python setup, and external-tool work dilute the wall-time change.
Across source loading and the three measured guest journeys, total guest work
fell 14.21%. This paired result demonstrates a real speedup on the sampled
checksum-heavy ext4 paths, not merely absence of a regression.

Known refused feature bits return format-domain `VFS-R-UNSUPPORTED` with
`EXT4-D-FEATURE`. `ORPHAN_PRESENT` and a nonzero `s_last_orphan` are admitted
through any required committed-journal replay and strict reload for
authenticated discovery. If `ORPHAN_PRESENT` is set and the authoritative
legacy/modern union is empty, mount completes the transient recovery state
before publication: a `RECOVER`-clear input first enters a tear-safe recovery
epoch through writer-free `AKW1` activation while preserving
`ORPHAN_PRESENT`; `AKR1` then lands an empty checksum-v3 journal and a
checksummed primary superblock with both transient bits clear. Any union whose
records all fit the exact linked-truncate shapes (an inline depth-0 extent map
or an exact empty legacy-format map), empty/one-to-four-entry inline-depth-0,
resident depth-1 fanout, or admitted legacy direct/indirect unlinked-delete slices is
transactionally drained before mount
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
orphan-file block, or legacy link. Recovery mutation admits the orphan-file
inode itself only with an extent map of depth zero or one. The generic parser
first validates a recognized depth-two-through-five extent tree or legacy map
completely, preserving corruption diagnostics, then a structurally valid wider
map returns stable `EXT4-D-RECOVERY` unsupported without cleanup or mount
publication. A union whose records all fit the supported linked map or admitted
unlinked deletion shapes is processed as a sequence of sealed one-record
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

The exact-vector wrapper proves every target and touched bitmap home before
execution. Consecutive physical members are then combined with checked
addition and sent through the scalar builder as one run; gaps and nonmonotonic
members remain separate, and a merged run still chunks exactly at group
boundaries. This changes neither the ordered authority vector nor its sealed
checkpoint representation.

`_EXT4-JTX-STAGE-ALLOCATE-BLOCK` is the inverse accounting primitive for one
exact already-owner-proved block. The enclosing operation may use it for the
ordered data candidate and, during root composition, again for the new extent
leaf. It requires the selected physical block to be in
bounds, outside every journal/static metadata role, and clear in both the
checksum-authenticated raw bitmap and the transaction's effective bitmap.
The initialized group must retain a positive bounded free count, its effective
descriptor must authenticate the same bitmap home and checksum, and the
primary super must retain a positive bounded global count. Only after all of
those checks succeed does the builder set the bit, decrement both counters,
replace the bitmap checksum, and restamp the descriptor and super checksums.
The retained homes are the exact bitmap, primary GDT block, and primary-super
home; context caches remain media-derived until reload. Any failure after the
first replacement aborts and scrubs the transaction.

This primitive deliberately does not choose storage or make a file map point
at it. `_EXT4-FIND-FREE-BLOCK` supplies the separate read-only selection step.
Starting from a caller-provided locality group, it visits each runtime group at
most once with explicit wraparound, uses the actual final-group length, and
requires every initialized bitmap's observed clear-bit count to equal its
authenticated descriptor counter. Candidate arithmetic is checked and the
result must pass the complete journal/static-role validator; the exact bitmap
home and clear bit are then reauthenticated after that cache-clobbering scan.
Groups with `BLOCK_UNINIT` are skipped rather than initialized implicitly. If
only such groups advertise free space, selection returns a stable unsupported
result rather than claiming disk-full or interpreting nonexistent bitmap
authority.

`_EXT4-FIND-FREE-BLOCK-EXCLUDING` performs the same authenticated geometry
walk for root composition while withholding the first planned candidate from
selection without pretending its raw bitmap bit is already set. Raw clear-bit
counts must still match descriptor counters. It returns a distinct second block
or clean `NOSPC`; it cannot manufacture authority by decrementing the observed
free count during planning.

The allocation-backed file operation derives each candidate group again from
the selected physical block before its reverse-owner proof. It certifies that
group's exact block-bitmap and primary-GDT homes rather than reusing the inode's
locality group. Root composition repeats this derivation independently for the
leaf candidate. After each `_EXT4-JTX-STAGE-ALLOCATE-BLOCK` independently
derives and stages its accounting replacements, the operation requires its
staged group, bitmap, GDT, and primary-super homes to equal the corresponding
certified homes. A mismatch aborts and scrubs the transaction before the inode
after-image is retained. This binding is required even when two group
descriptors happen to share one GDT block, because their block-bitmap homes and
descriptor offsets remain distinct.

The enclosing file operation must still perform complete reverse-owner proof,
ordered full-block initialization, an authenticated resident insert/coalesce,
single-leaf root transition, or singleton existing-leaf edit, exact one- or
two-block `i_blocks` accounting, leaf and inode checksum work, and publication
in the same transaction. Keeping those
authorities separate lets selection and accounting be tested exactly while
preventing either private piece from being mistaken for a complete user-visible
write operation.

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
only an allocated, unlinked regular inode with a valid nonnegative 63-bit size
whose data map is an empty or one-to-four-entry inline depth-0 extent root, a
resident depth-1 root with one to four external leaves, or a legacy map with
direct slots, at most one complete single-indirect block, and an optional
double-indirect root with zero or more occupied children whose exact canonical
authority fits the caller workspace. It separately admits either one allocated
all-zero triple-indirect root with zero or more direct data slots, or—with
every direct slot and the external-xattr pointer zero—one triple root
containing exactly one pointer to one allocated all-zero level-2 child. The
single- and double-indirect slots must be zero in both cases. Unlike linked
truncation, unlinked deletion does not require zero size: it releases the
complete authenticated map and zeroes the inode. Every extent entry must have
a zero physical high word. The depth-1 root and every external leaf are checksum- and
allocation-checked; each root key must equal its leaf's first key, sibling
logical bounds must agree, and no leaf may alias data or another leaf.
Initialized decoded lengths are 1..32768 blocks and unwritten decoded lengths
are 1..32767 blocks; every `logical_start + decoded_length` must be at most
`0xffffffff`. A resident inline xattr area is structurally authenticated with
the shared reader walker and may not refer to a value inode. The same walker
admits one external xattr block only when its header, checksum, entries, and
allocation are valid. At `h_refcount == 1` the external block is an independent
release singleton rather than an inline extent or direct-data slot. At a valid
larger refcount it remains allocated and contributes one exact metadata
after-image; only its refcount and checksum may change. Legacy zero data-pointer
slots are holes. Occupied direct slots, single-indirect entries, and entries in
every double-indirect child remain ordered data singletons in outer/inner slot
order. The optional single root, double root, and all children follow as map
singletons with exact journal revokes. Duplicate data pointers and data/map or
map/map aliases are corrupt. An empty double root contributes its exact root
singleton and revoke. The empty triple root contributes one trailing map
singleton and one revoke under distinct `LEGACY-SPARSE-TRIPLE` authority after
any direct data entries. Its complete block and both lower indirect slots must
remain zero. The child-bearing shape contributes the exact ordered
`{ triple-root, level-2-child }` map vector and two revokes under
`LEGACY-SPARSE-TRIPLE-CHILD` authority. Duplicate or known-owner aliases are
corrupt. Exact double-indirect authority larger than the caller workspace, a
second distinct triple-root child, a nonzero grandchild, child composition
with direct data or an external xattr, and any triple root combined with a
single- or double-indirect map are unsupported.
Decoded `i_blocks` must exactly match all data and map blocks plus that
optional xattr singleton. The target must be at or above `s_first_ino`.
Journal-data mode, extent trees deeper than the admitted resident depth-1
fanout, over-budget double-indirect maps, triple-indirect fanout or data beyond
the admitted all-zero child, child composition, single-/double-combined
triple-indirect maps, malformed lengths or ranges,
inconsistent shared-xattr
owner counts or aliases, and xattr value inodes remain refused. Every candidate
range bit must be set and each distinct touched block-bitmap home must have
exactly one descriptor owner. Every release range must lie inside mutable data
space, be disjoint from every other target range, and be disjoint from static
metadata, the journal, and all modern-orphan-file extents.

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
non-map interpretation. Any data or map-metadata reference to a candidate range
is `EXT4-D-DATA-MAP` corruption, even when both inode records and their
allocation bits are individually checksum-valid. A shared candidate xattr has
one exception at the semantic `i_file_acl` boundary: exact references to that
same block are counted, and their total including the target must equal the
authenticated header refcount. All admitted data ranges, external map-metadata
blocks, and the optional external-xattr singleton are published together for
this scan, so proving one entry cannot conceal an alias in a later entry. The
retained ownership certificate binds the map family, ordered data-and-map
tuple, xattr home, disposition, and raw pre-transaction refcount as separate
fields.

The builder derives the inode
group, bitmap bit, table locator, primary GDT page, and primary-super home from
authenticated geometry, proves the inode bitmap has one descriptor owner and
aliases no block bitmap, inode table, sparse metadata, or journal range, and
requires every transaction home to be pairwise disjoint except the intentional
legacy protocol/super coalescing.

The builder first stages the complete target inode-table home with exactly the
target record zeroed and every sibling byte preserved. It releases each
physical data range, reusable external map-metadata block, and unique
external-xattr singleton through the typed block-free builder, including exact
chunks crossing group boundaries. Extent leaves and the legacy indirect block
receive exact revokes; the builder stages no released-block overwrite and does
not wipe block contents. A shared xattr
instead gets one exact raw-copy metadata image with only `h_refcount` and
`h_checksum` changed. Its allocation bit, group and super free-block counters,
entries, values, hashes, and reserved bytes remain untouched. After
exact-vector target validation, physically
adjacent data ranges execute as one allocation-accounting run without changing
their separate certificate or checkpoint entries. Multiple ranges that touch
the same block group compose into one bitmap after-image, and all group
descriptor changes sharing a primary GDT block compose into one GDT
after-image. It finally
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
generation, map family, range count, and every ordered physical
`{ first, count }` pair;
it is not backed by a per-write content generation counter. Every reuse still
repeats local plan, inode, map-shape, static/journal, and orphan-file
authentication. Dry staging and abort,
journal-only activation, real staging, and commit cannot change another inode's
home map while that exclusive contract holds. The proof is invalidated before
retained-journal convergence, consumed immediately after a durable commit and
before replay can write homes, and cleared on every return. It is never
context-persistent and grants no authority across remount, a home write, or an
external raw-media mutator.

`_EXT4-JTX-STAGE-LINKED-ORPHAN-TRUNCATE` joins that accounting builder to one
authenticated map-removal case. It accepts only the canonical retained plan
slot found by the plan's own hash probe; an external byte copy, empty table
slot, or injected duplicate in a later probe slot has no cleanup authority.
The media locator is reauthenticated and the target must be a linked regular
file whose zero size is already durable, whose data map is either an inline
depth-0 extent root or an exact empty legacy-format `i_block` array, and which
does not use journal-data mode. The legacy-format case requires the `EXTENTS`
flag clear and all 12 direct pointers plus the single-, double-, and
triple-indirect roots zero. Any external xattr block is allocation- and
checksum-authenticated, retained, and proved disjoint from the target data
ranges. The decoded `i_blocks` value must exactly equal all captured extent
blocks plus that retained xattr block in 512-byte sectors; for an empty map,
only the retained xattr contribution may remain.

Writable ownership admission also reauthenticates the modern orphan file
through the complete read-profile mapper; cleanup no longer narrows that
inode to an inline depth-0 extent root. While the exact target ranges are
published, the full extent tree or legacy direct/indirect map is validated so
leaf data, unwritten or preallocated storage beyond EOF, external extent
nodes, and indirect metadata all participate in the disjointness proof. An
external orphan-file xattr block is allocation- and checksum-authenticated
under the same target scope. A separate singleton pass proves that this xattr
block does not itself alias any data or map-metadata reference in the orphan
inode, without making the xattr loader reject its own valid owner. Every
logical orphan block is then reread through its physical-location-bound tail
checksum, the ambient ownership scope is withdrawn on every return, and the
selected target record is reauthenticated before staging continues. The
target cleanup shapes remain the deliberately bounded inline-depth-0,
resident depth-1 fanout, and admitted legacy direct/indirect deletion cases described
above.

For a nonempty captured extent root, the builder stages an inode with zero extent
entries, clears all four inline entry slots, retains the extent header and
external-xattr pointer, encodes the exact xattr-only `i_blocks` remainder
(including `HUGE_FILE` units), and frees each captured range through the typed
block-free builder. An already-empty, exactly accounted extent or legacy-format
map has no storage work. Modern orphan-protocol cleanup therefore needs only
its slot after-image, while a nonterminal legacy orphan-protocol record still
stages the target inode to clear its consumed `i_dtime` successor. Once the
inode afterimage is published, any later semantic, conflict, or credit failure
aborts and scrubs the entire transaction; it recognizes a lower block-free
auto-abort and does not abort twice. The operation intentionally leaves the
orphan slot/list record active for a later durable protocol-completion step. It
stages no data images and performs no media write.
Reusable external metadata freed by the transaction—the admitted extent leaves
or legacy pointer blocks and a uniquely released external xattr—is retained in
canonical map order followed by the xattr.

`_EXT4-JTX-STAGE-ORPHAN-CLEANUP` owns an initially empty metadata-only
transaction for one deterministically selected record of either protocol. It
dispatches by the authenticated link count, and composes either admitted
zero-size linked truncation or an admitted unlinked inode release with modern slot
removal or legacy-head advancement. It requires used and active
metadata homes to equal the exact credit, then seals protocol- and operation-specific
raw authority plus retained after-image CRC32Cs into the arena-owned writer.
Modern modes bind the logical block, slot, physical orphan-file home, and
generation. Legacy modes bind the raw checksummed primary super, head inode,
retained successor, and advanced-head after-image. All modes bind the target inode
generation, table location, target data-entry count, transaction epoch, and
applicable retained-image checksums. Delete modes additionally bind the
inode-bitmap home, GDT home and descriptor offset, and complete retained CRCs
for the zeroed target inode-table block, inode bitmap, GDT, and primary-super
after-images. Data-delete modes additionally bind the map family, exact range
count, aggregate released-block count, and every ordered physical
`{ first, count }` pair. A depth-1 shape retains its data ranges flattened in
root/leaf order followed by every external-leaf singleton in root order. A
legacy indirect shape retains direct data, single-indirect data, and sparse
double-child data in outer/inner slot order, followed by the optional single
root, double root, and every child in outer-slot order. Unused pair slots must
be zero. Delete modes
also bind
the external-xattr home, `NONE`/`RELEASE`/`REFDEC` disposition, post-decrement
refcount, and retained-image CRC. The exact revoke count and identities are
derived from those typed fields and must fit the allocated revoke vector before
any entry is read. An explicit verifier-complete state keeps a
valid zero CRC distinct from “not reconstructed yet,” so the strict pre-home
comparison cannot skip a zero-valued checksum. The retained
transaction entries and
semantic verifier bind every distinct touched block-bitmap after-image and
coalesced data-group GDT page. For linked truncation the explicit target-entry
count binds the authenticated pre-truncation data-entry count: an empty extent
root or exact empty legacy-format map has zero, while a nonempty inline extent
root binds raw `eh_entries`. An empty legacy-format map additionally seals
data-map kind `NONE` and a zero range/revoke vector; the raw and staged checks
bind the clear `EXTENTS` flag and all-zero `i_block` array. For deletion, the
target-entry count binds the admitted inline, external-leaf, direct,
single-indirect, or sparse-double semantic data-entry count plus a mandatory
zero target after-image. No valid CRC32C value is
reserved as a sentinel. Mode is published last; once published, every generic
and typed staging entry point returns busy, while abort and emit remain legal.
The certificate also binds the exact pre-transaction total, modern, and legacy
orphan counts and publishes an operation/protocol-specific `FINAL` mode for a
one-record prestate or `MORE` mode for a larger prestate. Abort and every
successful writer rebase scrub the complete sealed transaction certificate;
this is distinct from the operation-scoped reverse-owner proof.

`_EXT4-MEASURE-ORPHAN-CLEANUP` applies the same per-record authentication
without allocating a writer or publishing an after-image. It returns exact
metadata and revoke credits as explicit values; no caller depends on ambient
post-measurement state. An already-empty-map record costs one protocol home for
a modern orphan-file slot or a terminal legacy orphan-protocol head; a
nonterminal legacy head also needs the target inode-table home to clear its
consumed `i_dtime` successor. A nonempty linked extent map under the modern orphan
protocol starts with the target inode table, primary super, and orphan-file
block; under the legacy orphan protocol it starts with the target inode table
and primary super. Both add one uniquely owned block
bitmap per touched group and one copy of each distinct primary GDT page. Thus
the canonical one-block linked-truncate legacy-protocol fixture has exact
credit four, while its already-empty-map form has credit one. The
geometry-bounded, constant-space
group scan imposes no candidate array or cleanup-specific capacity. A deletion
adds one revoke for every admitted external map-metadata block (each depth-1
extent leaf or legacy pointer block) and one for a uniquely
released external xattr; ordinary data and shared-xattr decrements add none.
Checked arithmetic, complete range/static/journal anti-alias validation, and unique
bitmap-owner proofs make the result the coalesced home count rather than an
upper bound. The sealing builder independently requires its staged active-home
count to equal the measured credit, so media or plan drift remains fail-closed.
An admitted unlinked target instead measures its inode table, inode bitmap,
inode-group GDT page, and primary super for exact credit four under legacy
cleanup; the distinct modern orphan-file home makes that five. A nonempty
root adds one block-bitmap home per distinct data group touched by any entry
and each distinct data-group GDT page not already represented by the
inode-group GDT page. Several entries in one group therefore do not duplicate
either home. A shared external xattr adds one metadata home but no release
bitmap or descriptor credit; a unique one participates in the release-group
scan. Whole-union writer sizing adds the single derived transition slot
described above when a current shared reference could become a final release.
The
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
and super after-image proof. For a data delete that proof streams over every
certified physical range, reconstructs one combined after-image for each
distinct touched block bitmap, and aggregates all descriptor edits on each
coalesced GDT page.
After home writes, checkpoint rereads every retained metadata home, requires
its complete image and CRC, proves the target inode record and allocation bit
are clear, and proves every certified range bit is clear with every derived
bitmap and GDT home retained before accepting the protocol-specific poststate.
For `REFDEC`, it instead proves the xattr allocation bit is still set and that
the durable block has the certified post-refcount, checksum, complete retained
image, and CRC.
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
implemented for unions of the exact linked zero-size inline-depth-0 extent or
exact empty legacy-format map and nonnegative-size inline-depth-0, resident
depth-1 fanout, or legacy
direct/indirect unlinked-inode cases admitted above under both orphan mechanisms. The
implementation adds no fixed cleanup
record-count constant; positive union-drain qualification currently reaches
two records.
Before a supported linked truncation or unlinked deletion may release storage,
it publishes every physical range in the admitted map together and performs one
complete allocated-inode scan. Any data, map-metadata, or external-xattr
reference from another inode to any of those ranges is a corrupt cross-link
refusal. When physical ranges are present, the operation-scoped certificate
binds the context, inode, generation, map family, range count, and all ordered
range pairs; it may bridge measurement, dry staging, activation, restaging,
and journal emission, but checkpoint invalidates it before its first home
write. Whole-union qualification performs this proof for every retained linked
or unlinked record before the first cleanup transaction may mutate media.
Per-shape single-record qualification includes initialized and unwritten
extents, nonzero logical starts, multiple separated logical/physical ranges,
the four-entry inline maximum, the 12-slot legacy-direct maximum, sparse
single-indirect pointers, one- and two-child double-indirect pointers, and a
physical range crossing two data groups.
Pinned e2fsprogs accepts final
empty-delete media at 1 KiB, ordinary one-block-delete media at 1/2/4 KiB, and
the new multi-block 1 KiB results for both orphan protocols. Broader per-record
orphan shapes and the complete user-visible mutation layer remain required for
final writable-profile conformance. They are not prerequisites for an
unrelated operation that cannot create those orphan states. Each operation
still requires its own external-tool, semantic, and representative crash
evidence before it is counted as production-closed or promoted beyond an
explicitly staged boundary.

## Current staged writes

`EXT4-STAGED-WRITE-BINDING` is the explicit ABI-1 surface for the currently
implemented mutations. A nonempty write request is admitted
only on authenticated 1 KiB filesystem geometry with 256-byte inodes and only
for a linked regular file whose inode flags are exactly `EXTENTS`. An
initialized-block overwrite or tail-only partial-tail append may use an
authenticated depth-0 or depth-1 extent tree. At an unaligned authenticated
EOF, a nonempty request may fit within the initialized tail or cross it. A
crossing request must start exactly at EOF, fill the remaining tail, leave at
least one byte for aligned allocation callbacks, and end at or below
`0xffffffff`. Each freshly reauthenticated aligned leg must find an unmapped
target representable by a qualified depth-zero edit or resident depth-one
selected-leaf edit or capacity-preserving split, and the request must preflight reusable
ordinary `4/1/0` capacity before its first clock sample. Allocation-backed hole fill and
aligned-EOF growth require either an authenticated inline depth-0 extent root
or a resident depth-1 root whose authenticated indexes name checksum-valid,
nonoverlapping external leaves. A
depth-zero candidate may use sorted insertion into a spare resident slot, exact
logical-and-physical initialized coalescing, or—when all four resident slots
are occupied and no coalesce is valid—one depth-zero-to-depth-one composition
through a newly allocated checksummed external leaf. In the depth-one form,
the root's logical intervals choose the target leaf. The candidate is inserted
there when it has capacity, exactly coalesced in place, or used to split a
saturated unmergeable selected leaf into two external leaves while the
resident root retains an index slot. Both operations
require an exact `i_blocks` account and an unmapped target logical block. Hole
fill keeps that block inside the existing file size and before its final
partial logical block. Aligned growth instead requires the request offset to
equal an exactly block-aligned authenticated EOF and advances it without a gap.
A callback remains block-bounded and returns
legal short success for a larger request; `VFS-WRITE-EXACT` may re-enter at the
new EOF for additional allocations while every next callback still satisfies
the structural admission. Exact requests may likewise continue across adjacent
complete in-size holes. The mounted instance must also have a trusted clock and
a caller-owned writer arena. Overwrite and partial-tail append require a
profile containing `1 metadata / 1 ordered data / 0 revoke`. Allocation-backed
operations require a containing profile for the measured `4/1/0` through
`8/1/0` topology; `8/1/0` contains the complete current set.

`Staged` distinguishes the currently implemented operation set from complete
`akashic-ext4-rw-v1` conformance. It describes capability breadth, not a
separate write path: every operation admitted here uses the production driver,
durability lifecycle, recovery machinery, and on-disk ext4 format.

Every callback invocation is bounded at the next filesystem-block boundary and
may return short success. For an admitted cross-tail span, the first callback
returns the checkpointed tail prefix and `VFS-WRITE-EXACT` re-enters at the now-
aligned EOF for the independently durable allocation leg. This is request-level
composition, not callback fallthrough or atomic batching. Requests overflowing
the 32-bit final size or lacking the ordinary `4/1/0` allocation floor fail
with zero progress before clock sampling. A later callback whose freshly
measured root composition exceeds the containing profile fails before media
I/O while preserving any earlier independently checkpointed prefix. The public
route otherwise sends partial-tail append directly
to initialized RMW and aligned-EOF growth directly to allocation. An in-size request first attempts
initialized overwrite; only its exact clean unmapped result is eligible for
allocation-backed hole fill. Corruption, an unwritten extent, stale authority,
or another refusal is returned without reinterpretation. The qualified surface
does not create a sparse gap, perform overwrite-through-EOF growth, convert
unwritten extents, grow a depth-one root beyond its resident index capacity,
grow a deeper tree, allocate more than one
logical block per callback, or provide a multi-block atomic-write contract.

The initialized-RMW typed stage builds exactly one ordered data-block
after-image, one inode-table metadata-block after-image, and no revokes. Its
ordered image is a full-block read-modify-write copy. Overwrite preserves
`i_size`; append writes the authenticated new EOF into the same inode
after-image. The allocation-backed stage described below instead constructs a
zero-backed ordered block and four metadata after-images for an ordinary
insert/coalesce. Root composition additionally retains the new leaf and, when
the second allocation uses different accounting geometry, one more bitmap and
one more primary-GDT home. It therefore uses exactly five through seven
metadata after-images, one ordered data image, and no revokes. Editing a
selected resident depth-one leaf retains exactly five metadata after-images—
the data bitmap, GDT, primary superblock, existing leaf, and inode—plus one
ordered data image and no revokes. Splitting a saturated selected leaf retains
the existing and new leaves in addition to the allocation accounting and
inode, for exactly six through eight metadata after-images, one ordered data
image, and no revokes. All four operations update
`mtime` and `ctime` from the trusted clock and restamp the ext4 inode checksum.
Dry staging itself neither emits nor checkpoints; the
staged callback composes it with activation, emission, synchronous checkpoint,
vnode publication, and clean unmount behavior.

Before retaining the initialized-RMW after-image pair, its primitive authenticates
the complete target tree under a scoped mutation audit. Every target leaf range
and external extent node is checked against journal, primary-super/GDT,
descriptor, bitmap, inode-table, and sparse-super/GDT roles. Leaf-local
validation rejects physical overlap within each leaf; the scoped audit
additionally requires the selected physical block to occur in exactly one leaf
across the complete tree and never as an external node. A nonzero
external-xattr block must differ from the selected block and pass the same
mutation-role check. The allocation stage performs the expanded ownership
proof over the selected data block plus every distinct planned metadata home
described below.

For initialized RMW, the exact inode-table home is authenticated
separately. One filesystem-wide other-inode walk then publishes both
transaction destinations—the selected data block and inode-table home—and
refuses either range through another allocated inode's data, extent/legacy map
metadata, or external-xattr pointer.
The target's generation, locator, complete map, size, link count, flags, and
external-xattr pointer are reauthenticated after each cache-clobbering scan. A
stale generation, unwritten extent, unsupported inode flag, cross-block write,
duplicate selected-block mapping, or ambiguous ownership fails before
publication. Overwrite additionally refuses growth. Append independently
reauthenticates exact old EOF, partial-block placement, checked new size, and
initialized mapping. An exact clean in-size hole returns a distinct unmapped
result to the public router; it is not an overwrite after-image. Once ordered
data has been retained, any later staging failure aborts and scrubs the
transaction.

Depth-positive qualification writes logical block 10 of a 12-block file through
its real depth-1 root and external node.
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
Deeper trees use the same bounded reader/parser, but staged mutation policy
stops at depth 1 after authenticating a structurally valid wider tree. A valid
deeper tree is unsupported for write; malformed trees remain corruption.

### Initialized partial-tail append

The staged binding admits no-gap EOF growth when the linked regular file ends
partway through an already allocated initialized extent block. The request
offset must equal the authenticated `i_size`, the EOF must be nonempty and
unaligned, checked `offset + count` must remain representable by the current
VFS cursor model, and this initialized-RMW callback may consume only the unused
remainder of that same block. A request fitting wholly in the tail completes
there. A request in the qualified crossing envelope is short-completed through
the tail and may be continued only after `VFS-WRITE-EXACT` advances to the
aligned allocation route. The complete depth-0 or depth-1 extent tree, target
mapping, inode locator/generation, link count, flags, xattr pointer, and both
transaction homes are authenticated exactly as for overwrite. Gaps and mixed
overwrite-plus-growth requests refuse before clock sampling or writer work.
Exact aligned EOF is classified separately and routes to the allocation-backed
growth operation below rather than this initialized-RMW mode. Sparse or
unwritten tails refuse during dry staging before journal activation or mutation
I/O.

Append uses the existing `1 metadata / 1 ordered data / 0 revoke` full-block
RMW transaction. It changes only the bytes in the allocated tail, `i_size`, the
inode checksum, and clock-derived `mtime`/`ctime`; the extent tree, physical
mapping, `i_blocks`, free-space accounting, link count, generation, atime, and
xattrs remain unchanged. The public VFS append flag reselects the shared
vnode's current EOF even after the descriptor was deliberately sought
elsewhere. After commit, the callback publishes the exact new size and times
into that shared vnode before generic cursor accounting, so every hard-link
alias observes the same committed EOF without a dirty-vnode fallback.

The public inode-14 qualification appends six bytes at EOF 54 and produces an
exact 60-byte file while retaining the one initialized mapping to physical
block 1346 and `i_blocks = 4`. The 1/1/0 success journey measures 672,608,905
guest steps; its ordinary hard-link remount measures 65,968,242 steps with no
writes or flushes. Pinned e2fsprogs 1.47.4 `debugfs` reads identical bytes
through both names and reports inode 14, two links, size 60, block count 4, and
the unchanged mapping; read-only `e2fsck -f -n` reports a clean filesystem.

Two trace-derived cuts close the new reachability boundary without duplicating
the shared journal matrix. At ordered-data write W7, all six caller bytes are
already present in the initialized home block, but the inode transaction has
not committed. Commit-granular append credit therefore reports `actual = 0`,
keeps the cursor and shared vnode at EOF 54 with old times, and recovery applies
zero inode homes; both names expose the old file and a second remount is
write-free. At inode checkpoint write W16, journal commit is durable and the
home tears. The public call reports all six bytes, advances the cursor and
shared vnode to 60 with committed times, and quarantines the volume
`PARTIAL|READONLY`. Recovery replays exactly one inode-table home, never
rewrites block 1346, and reaches the exact successful inode followed by a
byte-stable write-free remount. Neither path creates orphan state.

### Allocation-backed aligned-EOF growth

The staged binding also admits linked-file growth from an exactly block-aligned
authenticated EOF. Its offset must equal EOF, and each block-bounded callback's
target logical block must be unmapped in either an authenticated inline
depth-zero resident extent root or a resident depth-one root whose indexes name
checksum-valid, nonoverlapping external leaves. The depth-zero edit may use a spare resident
slot, exact logical-and-physical initialized coalescing, or the qualified
saturated-root composition into one new external leaf and a one-index resident
depth-one root. The depth-one edit selects the governing leaf by the root's
logical intervals, inserts or coalesces there, and repairs only that index key
when the leaf's first key changes. A saturated unmergeable selected leaf splits
into a second leaf and adjacent resident index while root capacity remains. A larger public
request returns one committed block-bounded chunk to `VFS-WRITE?`;
`VFS-WRITE-EXACT` advances and reauthenticates at the new EOF. A gap, mixed
overwrite plus growth, a mapped or unwritten target, a full resident root with
a full unmergeable selected leaf, or a deeper tree refuses without being
reinterpreted as another write mode. Public gap and mixed-growth requests refuse
before clock sampling, writer work, or media I/O. Capacity, second-candidate,
and structural-map refusals occur after that callback's clock sample but
complete during write-free preflight or dry staging before journal activation.

This is current production capability inside the documented 1 KiB/256-byte-
inode envelope. It is not a fixture-specific approximation of general growth.
The mounted engine first measures the authenticated target and selected
allocation geometry. Ordinary insert/coalesce resolves signed metadata credit
`-4`. Saturated-root composition resolves `-5`, `-6`, or `-7` after selecting a
distinct second free block for the leaf and deduplicating the data/leaf bitmap,
GDT, primary-super, leaf, and inode homes. A selected resident depth-one leaf
edit resolves `-5` for the data bitmap, GDT, primary superblock, existing leaf,
and inode homes. A saturated selected-leaf split resolves exact `-6` through
`-8` after selecting the distinct new leaf and deduplicating its bitmap/GDT
homes with the data allocation's accounting. A containing profile must admit
that exact result before `_EXT4-JTX-BEGIN`. The transaction writes a fully
initialized zero-backed data
candidate with the caller span overlaid and stages allocation accounting for
every new block. A resident depth-zero edit stores the mapping in the
checksummed inode after-image. Root composition stores the complete map in its
new leaf and publishes the resident index in the inode; an existing-leaf edit
stores the map in the selected leaf and publishes only its repaired index key
when required. A split replaces the selected leaf with the lower half, creates
a checksummed upper leaf, and inserts their first keys and pointers into the
resident root. Every unselected leaf remains byte-exact, and preexisting
unselected index pairs remain value-exact. Every form publishes incremented `i_blocks`, the applicable exact
`i_size`, and clock-derived `mtime`/`ctime` in the checksummed inode after-image.
Negative signed credit makes progress
commit-granular: no caller byte is reported until the complete allocation,
mapping, and EOF transaction commits. Success, and a later checkpoint failure
after commit, publish the shared vnode size, block count, filesystem free-block
count, and timestamps before returning confirmed progress.

The public hard-link qualification grows an exactly 1,024-byte file by one
24-byte request, attaches a new initialized logical block, advances `i_size` to
1,048 and `i_blocks` from 4 to 6, decrements free space once, and leaves the
unused 1,000 bytes of the new block zero. Both names expose the same committed
bytes and metadata; a clean ordinary remount is write-free, and pinned
e2fsprogs `debugfs` read/map/stat plus read-only `e2fsck` accept the result.

W7 and W22 close the operation-specific crash boundary. A tear of the ordered
candidate at W7 reports `actual = 0`, retains the old EOF, `i_blocks`, free
count, and timestamps in memory, and leaves the raw candidate free, unmapped,
and unreachable; recovery replays no metadata home and the next remount is
write-free. At W22 the journal commit is already durable and the final
inode-table checkpoint home tears. The callback reports the complete request,
publishes the new size, block count, free count, and timestamps, and quarantines
the mount `PARTIAL|READONLY`. Fresh recovery replays the four allocation/inode
metadata homes, never rewrites the ordered candidate, and reaches the exact
successful image followed by a byte-stable write-free remount. Growing a linked
inode in this transaction creates no orphan state; broader allocation and
orphan recovery are admitted when write or interoperability evidence makes them
reachable, not by speculative orphan expansion.

The focused W7 and W22 journeys pass in 190.29 and 190.46 host seconds. A
shared-fixture capstone passes success, policy refusal, W7, and W22 together in
265.57 seconds; pinned e2fsprogs `debugfs`/`e2fsck` qualification passes in a
separate explicitly configured run in 105.60 seconds.

Commit `57961e0` extends request-level composition through additional allocated
EOF blocks without changing that transaction primitive. A single exact request
grows an exactly 1,024-byte hard-linked file by one full block and 24 bytes in a
second new logical block. The first `4/1/0` callback inserts logical block 1 at
physical block 1351; the second selects 1352 and coalesces the adjacent mapping
into a length-two initialized extent. Two clock samples, two independently
checkpointed accounting/inode rounds, exact `i_blocks` growth from 4 to 8, and
two decremented free blocks are published cumulatively. The unused 1,000-byte
suffix of the second candidate is zero despite a poisoned prestate. Both hard
links, a byte-stable write-free ordinary remount, pinned `debugfs`, and read-only
`e2fsck` agree on the exact 2,072-byte result.

At the `57961e0` historical landing, a later clean structural refusal proved
that allocated EOF progress survived the then-unimplemented root transition. A
first allocation filled the fourth resident-root slot and checkpointed a
complete new block; the next exact-write callback reauthenticated that full
root, selected another free candidate, and refused before retaining ordered
data or allocation metadata because it could not yet insert or coalesce the
mapping. The terminal ior had no partial flag, while the cursor, shared vnode,
`i_blocks`, free-space count, first timestamp, allocation bit, and on-disk inode
all retained the first callback's durable 1,024-byte prefix. The refused
candidate remained poisoned, free, unmapped, and unwritten. Ordinary remount
was write-free and pinned `e2fsck` accepted the prefix image. Commit `851d2c6`
supersedes only that format boundary: a containing `5/1/0` through `7/1/0`
profile and two usable candidates now compose the full root. Sequential prefix
durability and the absence of multi-block atomicity are unchanged. A combined aligned-EOF,
cross-tail, and additional-EOF capstone passes all 13 selected success,
external-tool, refusal, and recovery checks sequentially in 805.56 host seconds.

Commits `d367584` and `38a6d03` qualify one broader initialized allocation
boundary without claiming arbitrary geometry. A checksum-valid unwritten
ballast extent consumes the canonical group-0 free run while leaving the
hard-linked target at its 1,024-byte aligned EOF. Its next 24-byte append starts
selection in the inode's group 0 but obtains physical block 8451 from initialized
group 1. The exact replacement homes are group-1 block bitmap 260, primary GDT
block 2 at descriptor offset 64, primary superblock home 1, and target inode
home 278. The operation maps logical block 1, advances `i_size` to 1,048 and
`i_blocks` to 6, decrements group 1 and global free space once, leaves the
group-0 bitmap and descriptor unchanged, and zeroes the unused candidate
suffix. Both hard links, a write-free stable remount, pinned `debugfs`, and
read-only `e2fsck` agree on the result.

The paired refusal maps a live non-target extent to the actual selected
group-1 bitmap home 260. Reverse-owner proof rejects the operation with the
data-map corruption class before any media I/O; candidate 8451 remains free,
poisoned, and unmapped, and every target, ballast, and accounting home remains
unchanged. The distinct committed checkpoint cut is W19 at bitmap home 260,
after its allocation bit becomes durable but before the GDT, superblock, or
inode home is checkpointed. Fresh recovery replays exactly bitmap 260, GDT 2,
super 1, and inode 278; it never rewrites ordered candidate 8451, group-0 bitmap
259, or ballast inode home 279. The repaired image equals the exact success
image and reaches a hash-identical zero-I/O remount. These four focused
success, external-tool, alias-refusal, and W19 checks pass sequentially in
199.19 host seconds. Existing W7 and W22 evidence continues to close the
unchanged `4/1/0` transaction's precommit reachability and final-inode
checkpoint endpoints.

Commit `5c19364` extends that same candidate-owned proof across a primary-GDT-
page boundary. A pinned supplemental 144 MiB image has 18 block groups and
64-byte descriptors, so groups 0--15 reside in primary GDT block 2 while group
16 begins primary GDT block 3 at descriptor offset 0. A checksummed depth-one
ballast inode consumes every clear run in initialized groups 0, 1, 3, 5, 7, 8,
and 9, using external leaf 2504 and unwritten extents past its unchanged
3,072-byte size. Groups 2, 4, 6, and 10--15 retain `BLOCK_UNINIT` and are
skipped. Public aligned-EOF growth for group-0 inode 14 then selects physical
block 131333, index 260 in initialized group 16, and binds its exact bitmap home
131073, GDT home 3, primary-super home 1, and inode home 295. The transaction
remains exactly `4/1/0`; primary GDT block 2, ballast inode home 296, and leaf
2504 remain byte-exact and unwritten. Stable-remount, hard-link, zero-backed
suffix, pinned `debugfs`, and read-only `e2fsck` checks all pass.

The distinct W20 cut tears checkpoint home 3 after descriptor-16 free-count
byte `0x0c`, with bitmap 131073 already checkpointed but the primary superblock
and target inode still old. Recovery replays bitmap 131073, GDT 3, superblock 1,
and inode 295 once each. It never rewrites ordered candidate 131333, group-0
bitmap 260, local GDT block 2, ballast inode 296, or ballast leaf 2504. Clean
deactivation writes primary superblock 1 once more outside replay, and the exact
success image reaches a checker-clean hash-identical zero-I/O remount. The
focused fixture, success, external-tool, and W20 set
passes all four checks sequentially in 249.82 host seconds. This qualifies the
exact second-page/offset-zero geometry; it does not initialize `BLOCK_UNINIT`
groups, prove wraparound, cover nonzero descriptor offsets on the second page,
or admit 2/4 KiB mutation.

### Saturated extent-root composition

Commit `851d2c6` closes the formerly unmergeable four-entry resident-root
boundary for both aligned-EOF growth and complete in-size hole fill. After
authenticating the inline depth-zero root and selecting the data candidate, the
planner still prefers a valid left, right, or bridge coalesce and then a spare-
slot insertion. If the root is saturated and none applies, it selects a second,
distinct free block, composes the four old extents plus the new initialized
singleton into one external depth-zero leaf, and replaces the inode's resident
root with one depth-one index. The index key is the leaf's first logical block;
both headers preserve the old extent-root generation. The leaf checksum is
bound to the target inode number and inode generation. An inode whose root is
already the exact singleton depth-one form is handled by the separate
existing-leaf edit below. Root composition itself still starts at depth zero,
and creates only one leaf; the later singleton-leaf split described below is
the separately qualified transition to two leaves. Deeper growth remains
outside the allocating envelope.

Root composition allocates two filesystem blocks in one transaction: one
ordered initialized data block and one metadata leaf. It sets both allocation
bits and decrements aggregate free space twice. When both blocks share a group,
that group's free counter falls by two; otherwise each selected group's counter
falls by one. On the qualified 1 KiB geometry, `i_blocks` advances by four
512-byte sectors. The primary-super image is composed in place, as is a shared
primary-GDT image; bitmap and GDT homes are otherwise retained separately. The
distinct metadata topology is therefore exactly:

- five homes when both allocations share a bitmap and GDT page;
- six homes when they use distinct bitmaps whose descriptors share one primary
  GDT page; or
- seven homes when the two bitmaps and primary GDT pages are all distinct.

The mounted write engine accepts signed credit zero as a request for the
allocation resolver. Before it begins either the dry or live transaction, the
resolver reauthenticates the target, selects both candidates, derives their
bitmap/GDT homes, deduplicates the primary super and any shared accounting
home, and returns exact negative credit `-5`, `-6`, or `-7`. The caller's bound
writer is a containing profile, not the transaction shape: an `8/1/0` profile
can run every currently qualified measured allocation from `4/1/0` through
`8/1/0` without inflating the smaller transaction. A full-root operation bound
only to
`4/1/0`, or a geometry with only one usable initialized free block, returns a
clean pre-I/O `NOSPC` refusal; it does not weaken the edit or partially stage
one allocation.

Measurement performs only the revalidation needed to derive exact credit.
Dry and live staging each publish the selected data block plus every distinct
metadata home as one range vector and perform the complete filesystem-wide
other-owner scan. The target inode is excluded only after its complete existing
map has passed a scoped role audit. Candidate selection, bitmap/GDT ownership,
inode-table ownership, external-xattr disjointness, and target bytes are then
reauthenticated after each cache-clobbering scan. The new leaf itself is one of
the proved metadata ranges. This eight-range maximum—one data destination plus
seven distinct metadata homes—is geometry-derived, not an operation-count
constant. In the maximum topology, measurement orders those metadata ranges as
`{ 269, 2, 1, 295, 131333, 131073, 3 }`; the separate data range is block
73988.

Retained metadata order follows staging rather than measurement-vector order.
The data allocation retains its bitmap, GDT, and the primary super; the new
leaf follows; leaf-allocation accounting then retains or replaces its bitmap,
GDT, and already-present primary super; the inode-table home is last. In the
five-home topology that order is `{ 259, 2, 1, 1355, 278 }`, with ordered data
home 1354. The exact-six typed topology uses
`{ 259, 2, 1, 8451, 260, 278 }`, again with data home 1354; its two bitmap
edits compose through one retained GDT block, and the typed transaction aborts
without media I/O. In the maximum qualified topology the exact retained and
checkpoint order is `{ 269, 2, 1, 131333, 131073, 3, 295 }`: group-9 bitmap,
first primary GDT page, primary super, leaf, group-16 bitmap, second primary
GDT page, and target inode table. The corresponding data home is 73988. Each
ordered data home is emitted before journal metadata; clean deactivation later
writes primary-super home 1 again outside the transaction checkpoint.

The same-group five-home public journey grows a 6,144-byte four-extent file with
a saturated root by 24 bytes, allocating data block 1354 and a checksummed leaf
at block 1355. The result has leaf entries for logical blocks 0, 2, 4, 5, and
6, one resident index, and `i_blocks` increased from 10 to 14. A separate
public in-size journey inserts logical block 1 into the middle of the same
saturated shape without changing `i_size`; both hard-link views, stable
ordinary remount, `debugfs`, and read-only `e2fsck` accept the composed
depth-one tree. Nonzero and deliberately different inode/extent-root
generations prove that leaf checksum authority and header-generation
preservation are not conflated.

The maximum seven-home public journey uses the 18-group fixture. Its data
candidate is block 73988, group 9 index 259, with bitmap 269 and descriptor
offset 576 in GDT block 2. Its leaf candidate is block 131333, group 16 index
260, with bitmap 131073 and descriptor offset zero in GDT block 3. Both
allocation counters, the one shared super image, leaf, inode, exact file bytes,
hard-link alias, stable zero-I/O remount, `debugfs` mapping, ballast tree, and
read-only `e2fsck` are checked. This is exact cross-page composition evidence;
it does not claim implicit initialization of the intervening `BLOCK_UNINIT`
groups.

W23 closes the new leaf-home crash boundary for the five-home form. Ordered
data block 1354 is durable at W7; bitmap 259, GDT 2, and primary super 1 reach
their transaction homes at W20--W22; leaf 1355 tears at byte 13 during W23,
before inode home 278 at W24. The committed callback reports its caller bytes
and quarantines the mount. Fresh recovery replays exactly the five metadata
homes in `{ bitmap, GDT, super, leaf, inode }` order, never rewrites ordered
data 1354, reconstructs the exact successful operation homes, and reaches a
second byte-stable zero-I/O remount. It writes the clean primary-super endpoint
separately after those five replay homes. No orphan state is created.

### Resident depth-one existing-leaf allocation

Allocation-backed hole fill and aligned-EOF growth may continue from a
checksum-valid resident depth-one root containing one through its authenticated
inline index capacity. The driver captures the complete fanout, chooses the
governing leaf from the root's logical intervals, and reauthenticates the inode
and selected leaf before use. It inserts the new initialized extent when that
leaf has a spare entry or applies an exact left, right, or bridge coalesce in
place. Those forms do not allocate another tree block. A full leaf remains
eligible for a coalesce that does not add an entry; a full unmergeable selected
leaf instead takes the split transition below when the root retains capacity.
Only a full root plus full unmergeable selected leaf, or a deeper tree, is
unsupported.

The transaction is exactly `5/1/0`. Ordered data is emitted first, followed by
the data allocation bitmap, primary GDT, primary superblock, existing leaf, and
inode homes. The leaf checksum is restamped against the filesystem seed, inode
number, and inode generation. If insertion or right coalescing changes the
leaf's first logical block, the inode after-image repairs that selected
resident index key while preserving every pointer and the authenticated header
generations. Unselected leaves remain byte-exact and preexisting unselected
index pairs remain value-exact. Only one new data block is allocated, so on the qualified 1 KiB
geometry free space falls by one and `i_blocks` rises by two 512-byte sectors.

The public qualification continues from the five-entry leaf produced by root
composition, checkpoints a partial-tail `1/1/0` leg, and then inserts the next
logical block into that existing leaf under exact `5/1/0` credit. The success
journey now measures 866,727,642 guest steps; its ordinary byte-stable,
write-free remount measures 512,274,129. Exact leaf bytes and checksum,
inode/root topology, data zeroing, allocation and free-space accounting, both hard-link
views, `debugfs`, and read-only `e2fsck` are checked.

A separate leading-hole journey inserts logical block zero before the former
first key and verifies the resident key changes from two to zero while its leaf
pointer and tree topology remain fixed. The authority gate also changes the
leaf to a different checksum-valid image between authentication and use and
requires `STALE` from full-byte revalidation. Typed negative gates reject the
leaf when it aliases the target's data, its external-xattr role, or another
linked inode's data. A typed 84-entry unmergeable-leaf gate now stages and
aborts the exact split without media I/O. The committed existing-leaf W23
cut replays exactly its five metadata homes without rewriting ordered data and
then reaches a write-free stable remount.

Multi-leaf admission retains one bounded target-local range vector containing
the external-xattr block when present, every resident external-leaf home, and
every initialized or unwritten data extent in the target map. Pairwise overlap
checking rejects data/data, data/node, node/node, and xattr overlap across
different leaves before staging or publication. The complete temporary vector
is scrubbed on every return path.

### Resident depth-one leaf split

On qualified 1 KiB geometry an external extent leaf has 84 usable entries once
its checksum tail is reserved. When a selected leaf has all 84 entries, the new
initialized mapping cannot coalesce, and the resident root has a free index
slot, the allocator selects a second free block for extent metadata. It treats
the selected leaf's old entries and new singleton as one sorted 85-entry
sequence, rewrites that leaf with the lower 42 entries, writes the new leaf
with the upper 43, and restamps both checksums against the filesystem seed,
inode number, and inode generation. The resident inode root retains depth one
and the authenticated header generation and inserts the new adjacent index.

The split allocates one ordered data block and one metadata leaf. Its exact
deduplicated metadata set contains the data bitmap, data GDT, primary
superblock, inode, existing leaf, new leaf, and any distinct bitmap and GDT
needed by the new-leaf allocation. It therefore consumes exact `6/1/0`,
`7/1/0`, or `8/1/0` credit. The existing leaf is a replacement home and the new
leaf is an allocation home; both remain in the same committed journal
transaction as allocation accounting and the two-index inode after-image. On
1 KiB geometry free space falls by two and `i_blocks` rises by four 512-byte
sectors. Reverse-owner admission covers one data destination plus all eight
possible distinct metadata homes in one nine-range proof.

The public same-group qualification starts with 84 one-block extents at even
logical blocks 0 through 166 in leaf 1353. Filling logical hole 1 selects data
block 1364 and new leaf 1454 under exact `6/1/0` credit. The resulting root
indexes keys 0 and 82, the leaves contain 42 and 43 entries, file size remains
171,008 bytes, and `i_blocks` advances from 170 to 174. Both leaf checksums,
both allocation bits, exact whole-file bytes, `debugfs` read/map/stat, and
read-only e2fsprogs 1.47.4 `e2fsck` are checked. The public write measures
1,136,810,443 guest steps; an active-empty remount performs zero transaction
home replays and completes in 187,081,244 steps.

A committed checkpoint fault tears new leaf 1454 at byte 13 after the bitmap,
GDT, primary superblock, and existing leaf have landed but before the inode.
The faulting public journey measures 1,049,742,606 guest steps and returns
committed progress with partial/read-only quarantine. Fresh recovery measures
206,112,098 steps and replays exactly the six metadata homes in
`{ bitmap, GDT, super, existing leaf, new leaf, inode }` order. It does not
rewrite ordered data block 1364 and reconstructs the byte-exact clean result.
That singleton-to-two-leaf result supplied the first split and crash-boundary
evidence. Commit `1f4e0ea` closes mutation from an already multi-leaf resident
root: target intervals select the proper leaf, selected-key repair leaves the
other root pairs unchanged, and a full selected leaf splits from two indexes to
three while the root retains capacity. The clean public second-leaf edit
allocates data block 1455, changes only leaf 1454 from 43 to 44 entries, advances
`i_blocks` from 174 to 176 under exact `5/1/0`, and survives a stable remount.
The clean public multi-leaf split allocates data 1455 and new leaf 1456, produces
root keys 0, 1, and 84 with 42/43 selected halves, advances `i_blocks` to 178
under exact `6/1/0`, and likewise survives remount. Pinned e2fsprogs 1.47.4
`debugfs` and read-only `e2fsck` accept both results. A four-index root remains
writable when the selected leaf has room; the four-index/full-selected-leaf
case returns typed unsupported depth growth before publication and does not
misreport physical `NOSPC`. The focused final capstone covers the three
prepublication alias roles, singleton-split regression, fanout selection and
key repair, cross-leaf alias refusal, typed and public fanout splitting, both
external-oracle paths, and both four-index boundaries: 14 tests pass in one
sequential process. Deeper-tree mutation is still outside this envelope.

### Initial atomic CREATE slice

The staged binding now advertises `VFS-CAP-CREATE` and installs `_EXT4-CREATE`
in operation slot 9. The ordinary binding remains read-only and retains a null
CREATE slot. `VFS-MKFILE?` first loads the parent directory and creates a
provisional cache dentry/vnode; the ext4 callback either commits the on-disk
namespace operation and publishes its stable inode identity or returns an
error, allowing the VFS to remove that provisional object.

The admitted parent is an authenticated one-block linear directory with flags
exactly `EXTENTS`, one initialized mapped block, a valid directory checksum
tail, root UID/GID, no setgid bit, and no inline or external xattrs. Its entire
dirent sequence is revalidated, including `.`/`..`, name syntax, record
alignment and bounds, target inode bounds, duplicate-name refusal, and usable
record slack. HTree/indexed directories, multi-block directories, directory
growth, default-ACL inheritance, and non-root credential policy return typed
unsupported or `NOSPC`; none is silently approximated. The existing directory
data block is proved disjoint from static metadata and the journal and uniquely
owned by the parent before it becomes a metadata replacement home.

Inode selection starts in the parent group and wraps across runtime geometry.
It accepts only initialized inode groups, verifies the bitmap checksum and its
free count, skips reserved inode numbers, proves the bitmap and inode-table
homes have their unique descriptor roles, and rechecks the selected clear bit.
Allocation advances the free inode's prior generation modulo 32 bits with zero
mapped to one, updates `bg_free_inodes_count`, `bg_itable_unused`, and
`s_free_inodes_count`, and restamps the bitmap, descriptor, and superblock
checksums. Groups requiring `INODE_UNINIT`/inode-table initialization remain an
explicit later slice.

The new 256-byte inode is an empty root-owned mode-0666 regular file with one
link, an initialized empty depth-zero extent header, `extra_isize=32`, trusted-
clock atime/mtime/ctime/crtime, and a full metadata checksum. The parent keeps
its topology and link count but receives the same trusted mtime/ctime. Dirent
insertion either splits authenticated slack from a live record or consumes a
free record while preserving a valid trailing free record, then restamps the
directory checksum.

All edits are one no-data/no-revoke transaction over the deduplicated set of
primary superblock, primary GDT page, inode bitmap, new inode-table page,
parent inode-table page, and directory block: at most exact `6/0/0` credit and
fewer homes when pages coincide. A clean mount dry-stages the complete edit
before journal activation; live staging reauthenticates every locator, emits,
checkpoints synchronously, and only then publishes inode number, generation,
metadata, parent times, and free-inode accounting into the VFS cache. The
focused public qualification creates `/created.txt` as inode 33, resolves the
same dentry, unmounts cleanly, and passes pinned e2fsprogs 1.47.4 `debugfs`
stat/list plus read-only `e2fsck`. A missing trusted clock rolls the provisional
VFS object back before writer creation or media I/O.

Operation-specific crash qualification covers both sides of commit authority.
A W7 torn journal descriptor returns an I/O error, removes the provisional VFS
object, leaves all six ext4 homes and free-inode accounting unchanged, and
requires no transaction-home replay. A committed W22 directory-home tear
returns CREATE success, retains inode 33 and the complete cache projection,
records the checkpoint error in `V.LAST-IOR`, and quarantines the live mount.
The next ordinary read-only mount replays all six metadata homes, resolves the
file with its exact timestamps and identity, and passes `e2fsck`; the following
mount is byte-stable and performs zero writes.

### Initial atomic MKDIR slice

The staged binding now advertises `VFS-CAP-MKDIR` and installs `_EXT4-MKDIR`
in operation slot 10. The ordinary binding remains read-only with a null MKDIR
slot. Generic `VFS-MKDIR` attaches an empty provisional directory before the
callback. An ext4 refusal leaves generic VFS to remove that object; commit
authority publishes the stable inode, one-block directory projection, parent
link and timestamps, and free-space accounting before generic VFS increments
its inode count.

The parent uses the CREATE slice's authenticated one-block checksummed linear-
directory envelope: root UID/GID, no setgid bit, flags exactly `EXTENTS`, one
initialized mapped block, no inline or external xattr, a complete valid
dirent chain and checksum tail, and enough existing slack for the typed
directory entry. Its on-disk link count must be from 2 through 64999 so the
new subdirectory cannot overflow ext4's 65000-link bound. Indexed or multi-
block parents, directory growth, default-ACL or setgid inheritance, non-root
credential policy, and groups requiring inode-table initialization remain
typed refusal boundaries.

Inode selection retains CREATE's initialized-group bitmap, inode-table,
generation, descriptor, and primary-superblock authentication. MKDIR also
selects a clear data-block bit from runtime initialized geometry. A paired
whole-filesystem owner proof establishes that the parent owns its complete
one-block map exactly once and that the distinct candidate has no inode owner;
static-metadata, journal, bitmap, descriptor, superblock, and inode-table
aliases are rejected separately. Dry staging performs that proof before
journal activation, and live staging repeats it and recaptures both blocks
from current media.

The new inode is a root-owned mode-0755 directory with link count two, size one
filesystem block, one depth-zero initialized extent at logical block zero,
exact `i_blocks` sector accounting, `extra_isize=32`, an advanced nonzero
generation, trusted atime/mtime/ctime/crtime, and a full inode checksum. Its
new checksummed directory block contains `.` with a 12-byte record, `..`
covering the remaining usable space, and the metadata-checksum tail. The
parent receives a file-type-2 dirent, one additional link, and the same
trusted mtime/ctime. Allocation sets the inode and block bitmap bits,
decrements group/global free-inode and free-block counts, increments
`bg_used_dirs_count`, updates `bg_itable_unused`, and repairs every affected
checksum.

All state changes are one no-data/no-revoke transaction. Deduplication derives
exact `7/0/0` through `9/0/0` credit from inode-table and primary-GDT page
sharing. The canonical root fixture consumes `8/0/0`: child inode-table block
283, parent inode-table block 275, parent directory block 1299, child directory
block 1364, inode bitmap 267, block bitmap 259, primary GDT block 2, and
primary superblock 1. The successful path validates the cache projection, raw
inode and extent, canonical dirents, allocation bits, group/global counters,
link counts, checksums, and exact checkpoint order, then passes pinned
e2fsprogs 1.47.4 `debugfs` and read-only `e2fsck` plus a zero-write byte-stable
ordinary remount.

A missing trusted clock, a caller profile containing only seven metadata
homes, an indexed parent, and a checksum-valid `used_dirs` count exceeding the
group's allocated inode count each refuse without activation, media mutation,
or cache drift. A W7 descriptor tear returns the precommit I/O error, removes
the provisional directory, leaves both allocation bits and every ext4 home
old, and requires no home replay. At W25, the committed child-directory home
tears after public success: the complete directory/cache projection remains
published, the checkpoint error is retained in `V.LAST-IOR`, and the live
writer is quarantined. Recovery replays all eight canonical homes; pinned
`e2fsck` accepts both recovery branches, and each following mount is byte-
stable and write-free. The focused success journey consumes 1,054,460,044
runtime steps under its existing 1.20-billion-step watchdog.

### Bounded empty-directory RMDIR

The staged binding advertises `VFS-CAP-RMDIR` and installs `_EXT4-RMDIR` in
operation slot 12; the ordinary binding retains a null slot. Admission is the
exact root-owned mode-0755 directory produced by the bounded MKDIR slice:
link count two, one initialized depth-zero logical-zero extent, size one
filesystem block, exact sector accounting, `extra_isize=32`, no external ACL,
project ID, index flag, or post-160 inode state, and canonical checksummed
`.`/`..` contents. The cache must have loaded the directory as empty, with no
open references, exactly one dentry reference, and the target outside the
active CWD. Other valid empty encodings remain typed write-policy refusals;
loaded children return `NOTEMPTY`.

The parent remains inside the authenticated one-block linear-directory
envelope and must contain one exact file-type-2 target entry. Its link count
must be at least three. The parent and child inode maps are independently
authenticated, then one two-owner reverse-map walk publishes both distinct
directory ranges and excludes only their two legitimate inode owners. Every
other allocated inode is checked against both ranges in that single walk.
Dry and live staging each repeat the proof and recapture the target, child
block, parent inode, and parent directory before retaining an after-image.

Removal zeroes the complete child inode, decrements and restamps the parent
inode, splices and restamps the parent directory, clears the child block bit,
and revokes the unchanged freed directory block. It then clears the child
inode bit, increments group/global free inode and block counts, decrements
`bg_used_dirs_count`, and restamps the retained descriptor and primary
superblock after-images. `bg_itable_unused` is deliberately not restored. The
deduplicated transaction admits exact `6/0/1` through `8/0/1` credit; the
canonical same-group fixture uses seven metadata homes and one revoke. The
freed child block is revoke-only and is never written as a checkpoint home.

Clean qualification removes inode 33, restores both allocation counts, the
parent link count, and `used_dirs`, preserves every other parent-directory
byte under an independently reconstructed exact splice, and preserves the
freed child-block bytes. Pinned e2fsprogs 1.47.4 `debugfs` and read-only
`e2fsck` accept the result, and the following ordinary remount is byte-stable
and write-free. The canonical checkpoint homes are target inode W22, parent
inode W23, parent directory W24, GDT W25, block bitmap W26, superblock W27,
and inode bitmap W28.

A W7 descriptor tear retains the directory and both allocations with zero
home replay. A committed W25 GDT tear leaves the first three complete homes
plus a torn descriptor; recovery replays all seven after-images while honoring
the child-block revoke, then reaches a write-free stable remount. Zero-write
refusal evidence covers a missing clock, missing revoke capacity, six rather
than seven metadata slots, `used_dirs == 0`, a noncanonical empty child, an
open reference, and hostile third-inode aliases of either the parent or child
directory home. The clean RMDIR journey measures 1,016,967,358 steps and its
stable remount 42,878,737 under the unchanged 1.20-billion runtime watchdog.

### Bounded hard LINK

The staged binding advertises `VFS-CAP-LINK` and installs `_EXT4-LINK` in
operation slot 17; the ordinary binding remains read-only with a null LINK
slot. Generic `VFS-LINK` constructs a provisional dentry that shares the target
vnode and increments `VN.NLINK` and `VN.DREFS` before callback dispatch. It
attaches that dentry and increments `V.ICOUNT` only after callback success.
Generic prerequisite commit `1f688d1` also rejects a namespace-detached target
or parent before dispatch and makes callback refusal restore both provisional
counts, the dentry, and reclaimable tail name-pool capacity.

The admitted target is a root-owned regular inode on authenticated 1 KiB/
256-byte-inode geometry. Its stable identity, generation, complete current map,
inode-table home, inline and external xattr forms, cache projection, timestamps,
mutable flags, and zero deletion time are revalidated during both dry and live
staging. Its old on-disk link count must be from 1 through 64999, while the
callback-visible provisional cache count must be the exact incremented value
from 2 through ext4's 65000 bound. Reserved or orphan inodes and nonregular,
immutable, append-only, deleted, or saturated targets refuse. An open regular
target remains admissible because every dentry and descriptor shares the same
vnode.

The destination parent is independently reauthenticated through the existing
root-owned, non-setgid, checksummed one-block linear-directory insertion
envelope. It must have a loaded cache, one initialized extent, a unique owner,
a complete valid dirent chain and checksum tail, no HTree or xattr state, an
absent destination name, and enough existing record slack. The target and
parent inode identities must differ. The parent need not be the current
directory, so the qualified surface includes both same-parent and distinct
root-parent links without approximating directory growth or indexed insertion.

Dry and live staging each authenticate the target inode, parent inode, and
parent directory before retaining after-images. The transaction increments and
restamps only the target inode, restamps the parent inode, and inserts and
restamps one file-type-1 directory entry. Target size, mtime, atime, generation,
map, `i_blocks`, xattrs, allocation state, and all free-space and orphan
accounts remain unchanged. The exact deduplicated homes are acquired in target
inode-table, parent inode-table, and parent-directory order, giving `2/0/0`
when both inode records share a table block and `3/0/0` otherwise. On the
canonical same-parent fixture, the shared target/parent inode-table home is W16
and the directory home is W17. The distinct-root fixture writes each of the
three homes once in target, parent, directory order.

Complete success publishes the target ctime, parent mtime/ctime, one additional
dentry reference and link, and one additional VFS inode count while leaving
`V.VCOUNT`, allocation counts, and every open descriptor unchanged. A
precommit callback error lets the generic VFS discard the complete provisional
object. Once commit authority exists, a later checkpoint error instead returns
public LINK success, keeps the new dentry attached, retains the structured
diagnostic in `V.LAST-IOR`, and quarantines the writer for recovery.

Five focused LINK tests close the current envelope. Clean same-parent linking
qualifies the shared vnode, open-FD continuity, exact cache counts, pinned
e2fsprogs 1.47.4 `debugfs` and read-only `e2fsck`, and a byte-stable write-free
ordinary remount. A W7 descriptor tear proves complete provisional rollback and
zero home replay. A committed W17 directory-home tear keeps the public link and
diagnostic, then replays both homes before a stable remount. A distinct-root
link qualifies exact three-home ordering, external inspection, and stable
remount. The fifth test proves zero-write refusal for a missing clock, a
one-metadata-credit profile, a nonregular target, and link-count saturation.

### Qualified NOREPLACE RENAME

The staged binding installs `_EXT4-RENAME` in operation slot 13 and adds
`VFS-CAP-RENAME`, `VFS-CAP-ATOMIC-RENAME`, and
`VFS-CAP-CROSSDIR-RENAME` to the staged descriptor. It does not add
`VFS-CAP-RENAME-REPLACE`; the ordinary ext4 binding remains read-only with a
null RENAME slot.

The same-parent admission envelope is one authenticated, root-owned mutable
regular source in its existing root-owned, non-setgid, checksummed one-block
linear parent. The source cache parent and requested destination parent are
identical, the destination name is absent, and no victim may reach the
callback. The source entry must identify that inode with regular-file or
unknown file type, and the parent block must retain a complete valid chain and
unique ownership.
When `ALIGN4(8 + new-name-length)` is no larger than the source entry's current
`rec_len`, the fast path rewrites that record in place. Otherwise the bounded
same-block path rebuilds from the authenticated directory snapshot into a
distinct scratch image. It emits every live non-source entry in original
order at its minimum aligned record length, discards unused records, and
appends the renamed source exactly once as the final live entry consuming the
remainder before the checksum tail. This deterministic compaction must prove
destination absence, exact source identity, complete input bounds, and
aggregate same-block capacity before transaction activation; insufficient
aggregate space returns `VFS-E-NOSPC` without a media write. Neither path
allocates, grows, or indexes a directory block.

Dry and live staging reauthenticate the source inode, parent inode, complete
directory block, source record, map, xattrs, identities, generations, and
cache projections. The transaction changes the source inode ctime, parent
mtime/ctime, the selected directory after-image, and the affected inode and
directory checksums. It preserves source and parent link counts, source size,
atime/mtime, map, data, `i_blocks`, generation, xattrs, allocation bitmaps,
free-space and directory accounting, and orphan state. There is no ordered
data or revoke. The exact deduplicated homes are the source inode-table block,
parent inode-table block, and parent directory block: `2/0/0` when the two
inode records share a table block and `3/0/0` otherwise.

The callback follows the generic RENAME publication contract: the old cached
name remains authoritative until callback success, while committed source and
parent timestamps are published by the driver. Its postcommit path converts a
checkpoint failure into public namespace success with the diagnostic retained
for recovery, so generic VFS can publish the new name only after commit
authority.

The established in-place qualification passes across sequential invocations
in 656.98 seconds. The canonical open-file case writes shared inode-table home
278 at W16 and parent
directory home 1345 at W17, preserves data and external xattrs, passes pinned
e2fsprogs 1.47.4 `debugfs` plus read-only `e2fsck`, and reaches a write-free
byte-stable remount. A second success renames the data-bearing one-link sparse
inode 17 after a valid unused predecessor, proving exact distinct homes 279,
278, and 1345 and covering the deletion-policy and predecessor-independence
boundaries. W7 preserves the old name and both old homes without replay. W17
publishes success, retains the checkpoint diagnostic, and replays both
committed homes before a stable remount. The refusal matrix proves that a
missing clock, one-home-short profile, and directory source
perform no media writes and leave the cache and pools unchanged.

The qualified compactor adds three focused sequential results. Its canonical
success completes in 108.40 seconds with open-FD continuity, independent
directory after-image checks, pinned external-tool acceptance, and a stable
write-free remount. An aggregate-full same-block case returns zero-write
`VFS-E-NOSPC` in 46.93 seconds. The in-place fast-path regression completes in
105.09 seconds. Exact transaction credit remains `2/0/0` or `3/0/0` for this
same-parent envelope.

The cross-parent envelope admits the same regular-file source and two
distinct authenticated, root-owned, non-setgid, checksummed one-block linear
parents, with an absent destination and no victim. Before activation it runs
one paired owner walk for the old and new directory blocks, then fully
reauthenticates the source inode, both parent inodes, both complete directory
blocks, maps, xattrs, identities, generations, and cache projections after
that walk. The old-parent after-image discards unused records and the exact
source record, emits the other live records in original order at minimum
aligned lengths, and lets the final survivor consume the remaining space. The
new-parent after-image discards unused records, emits existing live records in
original order at minimum aligned lengths, and appends the moved source once
as the final record consuming the remainder before the checksum tail. This is
an aggregate-fit proof; it does not allocate or grow either directory.

One cross-parent transaction changes source ctime, old-parent mtime/ctime,
new-parent mtime/ctime, both directory after-images, and their inode and
directory checksums. Its deduplicated homes are the source, old-parent, and
new-parent inode-table blocks plus the two directory blocks, giving exact
`3/0/0` through `5/0/0` credit. In the canonical fixture, source inode 14 and
old-parent inode 13 compose in table home 278, new-parent inode 2 occupies
table home 275, and old/new directory blocks occupy homes 1345 and 1299, for
exact `4/0/0`. Source and both parent link counts, source size, atime/mtime,
map, data, `i_blocks`, generation, xattrs, allocation bitmaps, free-space and
directory accounting, and orphan state remain unchanged. After commit
authority, the driver publishes all three timestamp projections and generic
VFS moves the same dentry to its new parent and name, preserving the shared
vnode and an already-open descriptor.

The canonical success proves exact W18/W19/W20/W21 writes to homes
278/275/1345/1299, independent raw after-images, data and xattr preservation,
pinned e2fsprogs 1.47.4 acceptance, and a byte-stable write-free remount. A
three-credit writer profile and an existing destination victim both refuse
without a mutation home write. A W7 descriptor tear rolls every provisional
home back and preserves the old namespace. A committed W21 final-home tear
publishes the new namespace after three completed home checkpoints; recovery
then replays all four committed homes before the stable remount.

#### Cross-parent empty-directory slice

The qualified directory request is deliberately narrower than the regular-
file envelope. It admits one source directory with exactly one dentry
reference, two distinct authenticated root-owned, non-setgid, checksummed one-
block linear parents, an absent destination name, and no victim. Same-parent
directory rename is unsupported. The public `VFS-RENAME-AT` path may present
an unloaded source child cache. The ext4 callback requires no cached child and
proves the exact empty media shape itself, so callers need no private preload;
any already-cached child returns `VFS-E-NOTEMPTY`. The callback reauthenticates
the source as the exact canonical one-block directory shape produced by the
qualified `MKDIR`: link count two, one initialized depth-zero extent, and only
`.` plus `..`, with `.` naming the source and `..` naming the old parent.

`VN.DREFS` must be exactly one, but descriptor and working-directory lifetimes
are independent of that namespace reference. An already-open directory FD
continues to name the same dentry and vnode across publication, and moving the
current working directory preserves the same `V.CWD` object. The source's
cached parent and name change only after commit authority; precommit failure
leaves both projections untouched.

The transaction reuses the regular cross-parent compact-remove and typed
compact-append after-images, with the appended source retaining directory
file type. It additionally copies the authenticated child block, rewrites only
the `..` inode from the old parent to the new parent, and restamps the child
directory checksum. Source ctime and both parents' mtime/ctime are updated.
The source link count remains two, the old-parent link count decreases by one,
and the new-parent link count increases by one. Source atime/mtime, size,
extent map, `i_blocks`, generation, allocation bitmaps, free-space and
directory accounting, xattrs, and orphan state remain unchanged.

The source, old-parent, and new-parent inode-table roles plus the old-parent,
new-parent, and child directory blocks deduplicate to exact `4/0/0` through
`6/0/0` credit. Metadata homes are acquired in source-inode, old-parent-inode,
new-parent-inode, old-directory, new-directory, child-directory order. In the
canonical move, source inode 33 and new-parent inode 34 share table home 283,
old-parent inode 2 occupies table home 275, and the old, new, and child
directory blocks occupy 1299, 1377, and 1364. The exact distinct vector is
therefore `[283, 275, 1299, 1377, 1364]` under `5/0/0`, checkpointed at
W19/W20/W21/W22/W23. W7 remains the precommit descriptor cut. At W23 the
first four homes are already complete and the torn child block has the new
`..` prefix without its matching final checksum; recovery replays all five
committed after-images before the write-free stable remount.

The stable two-directory preimage completed in 193.06 seconds, and canonical
success with independent raw after-images, cache/link/timestamp checks, pinned
`debugfs`/`e2fsck`, and stable remount completed in 304.10 seconds. The focused
short-credit/refusal, W7 rollback, and W23 replay cases all pass in their
combined sequential run. A same-parent plus regular-file cross-parent
regression completed in 193.01 seconds. A same-session `MKDIR` followed by
directory `RENAME` completed in 1,524,547,503 guest steps under its measured
2,000,000,000-step composition watchdog, in 260.07 seconds. Cold source mode measures
1,224,225,598 of 1,250,000,000 steps across 3,095 packed lines; the descriptor
journey measures 4,549,770 steps.

`VFS-CAP-RENAME-REPLACE` remains absent. Destination victims, directory
replacement, same-parent directory moves, multi-block or indexed parents, and
directory growth remain gated. The next delivery phase is full deletion and
truncation lifetime semantics rather than another rename expansion.

### Same-retained-block shrink TRUNCATE

The retained-block subpath accepts a strict shrink whose new EOF is nonaligned
and lies inside the old final initialized logical block.
The generic VFS prepublishes the requested shared-vnode size and retains the
old size while the guarded callback runs. The ext4 callback reauthenticates
that exact old EOF, positive link count, inode identity, complete depth-zero or
depth-one extent map, selected block, xattr pointer, inode-table home, and
unique ownership of the data/inode-home pair. A same-size or growing request,
an aligned nonzero new EOF, or a nonzero shrink selecting an earlier logical
block returns typed unsupported and the VFS restores its old cache projection.
Those refused shapes can require a wider block-release policy and are not
approximated by retaining blocks beyond the qualified boundary. Exact zero
dispatches to the separate one-block release path below.

An admitted call zeroes the entire retained block suffix beginning at the new
EOF, writes the exact 64-bit inode size, updates trusted-clock `mtime`/`ctime`,
and restamps the inode checksum. It preserves the extent map, physical block,
`i_blocks`, link count, generation, atime, xattrs, block bitmaps, descriptors,
superblock free count, and orphan state. The zeroed file block and inode-table
block are both JBD2 metadata payloads in an exact `2 metadata / 0 ordered data /
0 revoke` transaction. The file block deliberately is not ordinary ordered
data: a precommit ordered write could zero bytes still visible under the old
EOF. Journaling both full-block after-images makes the old pair or the
committed new pair the only recovery authorities.

Clean qualification shrinks inode 14 and both hard-link aliases from 54 to 24
bytes, clamps the calling descriptor cursor, leaves `i_blocks=4` and free-space
accounting fixed, and proves bytes 24 through 1023 zero. A cold ordinary mount
reads both aliases with the exact prefix and performs no writes; pinned
e2fsprogs 1.47.4 `debugfs` observes the unchanged mapping/link/block counts and
read-only `e2fsck` accepts the image. A missing trusted clock refuses before
writer creation or media I/O and restores the prepublished cached size.

The W7 descriptor tear returns the volume I/O error, restores the old cached
EOF, leaves the descriptor cursor and both filesystem homes unchanged, and
requires no transaction-home replay. At W17 the committed transaction's data
home has landed and its inode home tears. The callback returns TRUNCATE success,
reapplies the new vnode size and timestamps after checkpoint quarantine, and
retains the partial/read-only error in `V.LAST-IOR`. Recovery replays both
homes; the following mount is byte-stable and write-free.

### One-block release TRUNCATE-to-zero

The first block-releasing slice accepts a linked regular file whose positive
old size is at most one filesystem block and whose authenticated depth-zero
extent root contains exactly one initialized logical-zero singleton. The inode
may retain one qualified external xattr block. Other maps, partial block
release, nonzero block-releasing EOFs, unwritten extents, and depth-positive
release remain typed unsupported boundaries.

The callback composes an insertion, one cleanup transaction per retained
record, and a final clear through a caller-owned writer sized componentwise to
the maximum exact insertion, prospective-target cleanup, retained-union
cleanup, and one-home clear requirements. The qualified canonical topology
needs five metadata slots and no revokes; broader supported cleanup topologies
are not forced into that fixture value. Thus the empty-union path has three
synchronously checkpointed transactions, while `ADD_MORE` drains the complete
enlarged union. First, an
exact `3/0/0`
`ADD_FIRST` transaction atomically sets the target size and trusted-clock
`mtime`/`ctime`, inserts the target inode number into the first authenticated
empty modern orphan-file slot, and sets `ORPHAN_PRESENT` in the primary
superblock. If an authenticated modern-only union is already active, exact
`2/0/0` `ADD_MORE` instead changes only the target inode and deterministic
first free orphan-file slot, preserving the already-set feature bit and primary
superblock byte-exact. Both certificates bind the complete pre-union counts,
require spare geometry-derived runtime-plan capacity, reject a duplicate
target, and rebuild their exact after-images from current media before the
first home write. Their poststate is exactly the old union plus the new linked
zero-size inode while the old extent and `i_blocks` remain recoverable.

Before insertion, every preexisting record is authenticated and measured and
must still be linked. An unlinked record is a live-session lifetime authority
that this operation may not consume, so it returns `BUSY` before the clock or
media mutation; crash-time mount recovery retains its broader delete semantics.
Admission also reconciles each initialized block bitmap's exact clear-bit
count with its authenticated group descriptor and reconciles the group sum
with the mounted superblock free count. `BLOCK_UNINIT` groups remain lazy and
cannot own any admitted release range. Together with disjoint allocated-range
ownership, this proves the union's cumulative counter updates before `ADD`
even though cleanup is deliberately checkpointed one record at a time.

Second, the existing linked-orphan cleanup measures its exact homes, replaces
the target map with an empty extent root, updates `i_blocks`, releases the data
bitmap bit and free-block counters, and clears the modern slot. On the qualified
fixture this is a five-metadata transaction because target inode, orphan block,
block bitmap, primary GDT page, and primary superblock are distinct. The
external xattr remains allocated and accounts for the final two 512-byte
sectors. Third, an exact `1/0/0` transaction clears transient
`ORPHAN_PRESENT` only after authenticated empty-union proof. It deliberately
leaves ext4 `RECOVER` and the private writer active so a later operation can
reuse the mounted write session.

After each cleanup emit, the driver projects the committed `i_blocks` value
into the shared cached vnode identified by inode number and generation before
checkpoint. Thus a retained union member already materialized by directory
enumeration cannot remain stale after its on-disk map is released; all hard
link dentries continue to share that one corrected vnode. A checkpoint failure
does not roll this projection back because the committed journal remains the
authoritative state.

Public success clamps every descriptor sharing the vnode to EOF zero, exposes
zero bytes through both hard-link names, advances free space by one block, and
publishes `VN.BLOCKS=2` for the retained xattr. Clean unmount deactivates the
journal; a cold ordinary remount performs no writes, and pinned e2fsprogs
1.47.4 `debugfs` plus read-only `e2fsck` accept the empty mapped file.

A torn first-transaction descriptor returns the precommit volume error and
restores the old 54-byte public file, four-sector block count, inode home, and
allocated data block. A committed tear of the first inode checkpoint home
returns public truncate success with EOF zero and quarantines the live writer;
fresh mount replay installs the orphan, existing mount recovery releases its
data block, clears the slot and transient bit, and reaches a checker-clean,
write-free stable remount. Separate `ADD_MORE` qualification begins with one
linked zero-size orphan retaining two sparse data ranges, checkpoints a second
linked truncation, tears the orphan-file home after its new slot bytes but
before its checksum, then proves that fresh-mount replay reconstructs and
drains the full two-record union. The final image frees all three data blocks,
preserves both positive link counts and the target xattr, passes pinned
`e2fsck`, and remounts without I/O. These boundaries prove that durable EOF
zero cannot strand the old allocation and that a failed precommit orphan
insertion cannot publish the shrink. A focused authenticated retained-union
mount fixture, intentionally bypassing ordinary mount-time orphan draining,
also drives public `VFS-TRUNCATE` through `ADD_MORE` and the full two-record
drain in 1,656,718,410 guest steps. It verifies inode 17's already-cached vnode
changes from four sectors to zero, all three data blocks become free, the
target retains its two-sector xattr accounting, the feature bit clears, and
pinned `e2fsck` accepts the image. The ordinary one-record public journey with
the exact counter audit and stable remount completes in 1,195,226,705 steps
under the unchanged 1.2-billion guard. The consolidated zero-release,
retained-shrink, policy,
orphan-cleanup, and CREATE adjacency capstone passes all eight selected tests
sequentially in 573.98 host seconds.

### Regular-file UNLINK lifetimes

The staged binding now advertises `VFS-CAP-UNLINK` and installs `_EXT4-UNLINK`
in operation slot 11. The ordinary binding remains read-only with a null
UNLINK slot. The nonfinal lifetime removes one regular-file name when the
target has at least two links and the same authenticated parent contains
another live name for that inode. Descriptors may retain the selected dentry:
generic VFS lifetime rules detach it from the namespace after commit, keep the
shared vnode and exact dentry readable through those descriptors, and reclaim
that dentry on its last close. The closed final lifetime accepts only an
already-empty, allocation-free inode with link count one and exactly one
authenticated directory reference. Nonempty final-link removal, unlink while
any descriptor references the final link, directory removal through `UNLINK`, and
nonfinal links whose remaining name is outside the same-parent proof remain
explicit later boundaries. The bounded empty-directory `RMDIR` path is a
separate operation with its own admission and revoke contract.

The target and parent must be root-owned objects on the qualified 1 KiB/
256-byte-inode staged geometry. The target inode, its complete current extent
map, external xattrs, inode-table locator, generation, link count, and cache
projection are reauthenticated. Immutable/append targets are refused. The
parent uses the same one-block checksummed linear-directory envelope as the
initial CREATE slice: one initialized extent block, no HTree indexing or
inline/external xattrs, a valid checksum tail, complete `.`/`..` and dirent
validation, unique ownership of the directory block, and no directory growth.
The selected name must match exactly one live regular-file dirent with a live
predecessor; the implementation merges its `rec_len` into that predecessor,
zeroes the removed record bytes, and restamps the directory checksum.

The nonfinal transaction decrements on-disk `i_links_count`, updates only the
target ctime, updates parent mtime/ctime, and replaces the directory block. Its exact
metadata credit is derived from the deduplicated inode-table and directory
homes: two homes when target and parent records share a table block, otherwise
three. It carries no ordered data and no revokes. File size, mtime, map,
`i_blocks`, generation, xattrs, allocation bitmaps, free-block/free-inode
counts, and orphan state do not change. A one-home caller profile returns
`NOSPC` after one trusted-clock sample but before activation or media writes on
the canonical two-home case.

Final-link admission additionally requires zero size and `i_blocks`, a
canonical empty extent or legacy map, no external xattr or project ID, and no
open reference. It authenticates the group-relative inode-bitmap index,
initialized bitmap and set allocation bit, primary descriptor and inode-table
locators, and primary superblock. One deduplicated transaction of at most
`6/0/0` zeroes the complete target inode, updates parent mtime/ctime, splices
and checksums the directory record, clears the inode bit, increments group and
global free-inode counts, and restamps their checksums. No orphan interval is
needed because the admitted inode has no data, map-node, or external-xattr
allocation that can survive its final name.

After commit authority, the callback publishes target ctime for a nonfinal
removal and parent times for both shapes; generic `VFS-RM` then removes the
dentry, decrements the vnode link count, and updates cache counts. A later
checkpoint failure therefore returns public unlink success, retains its
structured error in `V.LAST-IOR`, and quarantines the mount. Before commit,
the callback returns the operation error and generic VFS leaves the old
namespace and vnode projection intact. Open final-link and missing-clock
refusals occur before clock sampling or media writes. Once a clock is bound, a
nonempty last link is refused by the ext4 write policy before activation; an
undersized workspace likewise leaves cache and media untouched. Every refusal
scrubs the operation snapshots. Clean open-nonfinal qualification retains the
removed dentry with `OPEN_REFS=1` and `DREFS=2`, reads the complete 54-byte file
through the detached descriptor, then proves close returns those counts to
`0/1`. Its mutation journey measures 602,649,678 guest steps; pinned `e2fsck`
passes and a 52,426,213-step stable remount performs no writes.

Clean qualification removes `/fixture/hardlink.txt` while preserving the
54-byte `/fixture/payload.txt` inode, its data block and external xattr, and
passes a write-free ordinary remount plus pinned e2fsprogs 1.47.4 `debugfs`
and read-only `e2fsck`. W7 descriptor failure leaves both names and both old
metadata homes byte-exact; recovery discards the incomplete transaction. At
W17, the shared inode-table home is complete and the committed directory home
tears. The cache retains the removed name's absence and link count one while
the live mount is quarantined; recovery replays both homes exactly once and
the following remount is byte-stable and write-free. The final sequential
adjacency capstone combines all four UNLINK cases with initial CREATE,
same-retained-block TRUNCATE, one-block-release TRUNCATE, and TRUNCATE policy
refusal: all eight pass in 534.05 host seconds.

Clean same-mount CREATE followed by final UNLINK restores the original
free-inode and VFS cache counts, leaves inode 33 completely zero, and passes a
write-free ordinary remount plus pinned `debugfs` and read-only `e2fsck`. A
torn UNLINK descriptor retains the created name, inode, and allocation;
recovery replays no ext4 home before reaching a stable mount. A committed torn
directory home occurs after public absence and capacity recovery; the live
mount retains the checkpoint diagnostic, and fresh recovery replays the target
inode, parent inode, directory, inode bitmap, primary descriptor, and primary
superblock exactly once. The following remount is byte-stable and write-free,
and neither path sets `ORPHAN_PRESENT`. The expanded sequential capstone runs
the prior eight cases plus these three final-link cases: all 11 pass in 949.80
host seconds.

### Allocation-backed in-size hole fill

The staged binding publicly routes an exact clean unmapped target to the typed
allocation operation for one complete logical hole inside the current file
size. Its admission contract is structural: a linked regular file with flags
exactly `EXTENTS`, an authenticated inline depth-0 root or resident depth-1
root with authenticated external leaves, a target representable by a spare-slot insertion, an exact
logical-and-physical initialized coalescing edit, or the qualified saturated-
root composition or selected-leaf split within resident root capacity, an exact `i_blocks` account, and a
hole before
the final partial logical block qualifies. Admission is derived from
authenticated on-disk geometry and inode state, not a named image or path.

The topology-derived `4/1/0` through `8/1/0` transaction selects an
authenticated free data block from runtime group geometry, retains a full
zeroed image with the caller span overlaid, and attaches it by inserting a
sorted initialized singleton, applying a checked left/right/bridge coalesce,
editing the selected resident leaf, composing the saturated depth-zero root
through a second leaf allocation, or splitting a saturated selected leaf while
the resident root has capacity,
without changing `i_size`. Its metadata after-images set every new bitmap bit,
decrement the exact group and primary-super free-block counters, restamp their
checksums, increment `i_blocks` for every allocation, update `mtime`/`ctime`,
and restamp the inode. One other-inode scan covers the data destination and all
four through eight distinct metadata homes. The target's complete existing map
is separately checked against static metadata and journal roles before that
inode is excluded from the scan.

The in-size hole-fill mode refuses an existing initialized mapping, unwritten
conversion, a full resident root whose selected leaf is full and unmergeable,
a deeper extent tree, a cross-block request, the final partial logical block,
and EOF growth.
Those are boundaries of this mode, not claims that such files are invalid or
unreadable. The public router reaches it only after the initialized overwrite
builder has authenticated the target as exactly unmapped.

Both transaction shapes, all four public transaction primitives, and their
qualified exact-write compositions use the real durability lifecycle. A write-
free dry stage is
aborted before clean-to-`RECOVER` activation; the live stage emits ordered data
before its descriptor and final commit and then synchronously checkpoints the
active metadata homes. Initialized overwrite and append each have one
inode-table metadata home. Ordinary hole fill and aligned-EOF growth have four
metadata homes: the inode table, block bitmap, primary GDT, and primary
superblock. Saturated-root composition has exactly five through seven homes and
attaches the same initialized data block through one additionally allocated
leaf. Singleton-leaf splitting has exactly six through eight homes and replaces
the existing leaf while allocating a second. All forms update authenticated
free-block accounting and `i_blocks` for every allocation; aligned growth also
advances `i_size`.
Public unmount cleanly deactivates the retained writer, and a fresh ordinary
read-only mount reads the resulting file without requiring a new mutation
capability.

Pinned e2fsprogs 1.47.4 independently accepts that public result. `debugfs`
reads the exact three-block file, maps logical block 1 to the geometry-selected
candidate, and reports size 3,072 with `i_blocks = 6`; read-only
`e2fsck -f -n` reports a clean filesystem.

Three operation-specific cuts close the materially distinct new allocation
boundaries without claiming that every shared journal ordinal has been
re-enumerated. A tear in the ordered candidate block reports `actual = 0`,
leaves the cursor and vnode unchanged, and quarantines the writer before any
allocation home is written. Fresh recovery enters the empty active journal but
replays zero homes, so the torn raw candidate remains free and unreachable and
the original sparse file is preserved. GDT and primary-super checkpoint-home
tears occur after the allocation transaction is committed: both report the
complete confirmed caller count and publish committed vnode block accounting,
filesystem free space, and timestamps before returning the quarantine error.
Fresh recovery writes all four metadata homes, never rewrites the ordered
candidate, publishes the allocated extent and exact free-block/`i_blocks` state
on reload, and reaches a byte-stable write/flush-free remount. The
combined public success, external-tool, ordered-data, GDT, and primary-super
capstone passes five tests sequentially in 310.47 host seconds.

### Tail-to-next-block exact composition

Commit `c8f0804` qualifies a single `VFS-WRITE-EXACT` request beginning at EOF
byte 1,016, eight bytes before the block boundary, and continuing 24 bytes into
one allocated next logical block.
The initialized tail data/inode pair and allocation data/four metadata homes
commit in two ordered rounds through one writer. The clock is sampled once per
callback, the second timestamp wins on complete success, hard-link views agree
on the exact 1,048-byte result, and a write-free ordinary remount plus pinned
`debugfs` and `e2fsck` accept the image.

The two callbacks are separate durability boundaries. At commit `f6411bf`, that
distinction was proved against a saturated unmergeable resident root: the first
eight bytes remained checkpointed and advanced the cursor and vnode to byte
1,024, while the freshly reauthenticated allocation leg refused with a zero-
progress format/unsupported result. Its terminal ior had flags zero, allocation
accounting, extent root, and candidate remain unchanged, the first timestamp
stayed published, and the idle-clean writer remained reusable. The following
ordinary remount was write-free and byte-stable. That record is historical;
the current allocation leg resolves the full-root topology and proceeds when
its containing profile and two-block geometry admit it.

Two trace-derived crash cuts close the new combined reachability boundary.
At ordered candidate write W22, the first callback's data and inode home are
already checkpointed; the torn candidate remains free and unmapped, recovery
replays zero metadata homes, and the 1,024-byte prefix remains authoritative on
a stable remount. At the final inode-home checkpoint W37, both transaction
commits are durable and the journal authoritatively retains all four allocation/
inode after-images; three second-leg homes reached their checkpoints before the
inode home tears. The tear's inode suffix is therefore the already checkpointed
first-leg inode rather than the original input inode. The public call reports
all 32 bytes and the final vnode state; recovery replays the four metadata
homes, never rewrites either ordered data home, and converges on the exact
successful 1,048-byte image and a write-free stable remount. Neither cut creates
orphan state. The consolidated cross-tail closure capstone passes deterministic
refusal, success, pinned external-tool inspection, late clean refusal, W22, and
W37 sequentially: six tests in 383.36 host seconds.

Consecutive-hole composition is also qualified on a valid four-block sparse
inode whose initialized endpoints surround two complete logical holes. One
public `VFS-WRITE-EXACT` fills both holes through the same reusable writer as
two independently durable `4/1/0` transactions, allocating geometry-selected
blocks 1351 and 1352. Trace checks bound the lifecycle at 89 events and require
the two candidate/bitmap/GDT/inode rounds in order, while exact cursor,
timestamp, `i_blocks`, free-space, and full-file readback checks prove
cumulative publication. Clean unmount completes in 1,285,188,318 guest steps
under the established scoped 1.5-billion multi-record ceiling; the ordinary
remount completes in 62,181,924 steps with no writes or flushes, and pinned
`debugfs` plus read-only `e2fsck` accept the result. The request has
independently durable block semantics, not an atomic two-block transaction. Its
first allocation inserts a singleton; its second coalesces with that singleton
into a real length-two initialized extent, leaving the inline root at three
entries with one resident slot still available. This directly qualifies
adjacent initialized coalescing on the current public hole-fill path. Focused
typed stages also qualify bridge coalescing and right coalescing in a full
resident root. Before `851d2c6`, the unmergeable full root was the one remaining
resident shape requiring extent-root growth; it is now the qualified single-
leaf composition described above.

`_EXT4-MOUNTED-ONEBLOCK-WRITE` now composes that exact slice as a reusable
private mounted client. It accepts source/count, file offset, inode number,
expected generation, explicit seconds/nanoseconds, the mounted VFS, a signed
metadata credit, and a typed stage XT, and returns `actual ior`. A nonzero
credit is already exact. Signed zero invokes the allocation credit resolver,
which performs a read-only authenticated planning pass and returns exact
negative credit before transaction capacity preflight and begin. Positive credit
selects ordered-sector prefix progress for bytes already reachable through the
old inode size. Negative credit selects commit-granular progress for operations
whose caller bytes are not yet reachable—allocation-backed hole fill,
initialized partial-tail append, and aligned-EOF growth—while its absolute value
is the real metadata credit. A zero-length request returns `0 0` without
allocating a writer. Every nonempty request preflights and ensures the resolved
`abs(metadata-credit)/1/0`: `1/1/0` for overwrite or partial-tail append,
`4/1/0` for a depth-zero ordinary allocation, exact `5/1/0` for a selected
resident depth-one leaf edit, and `5/1/0` through `7/1/0` for saturated-root
composition, or `6/1/0` through `8/1/0` for a selected-leaf split while the
root retains capacity.
Allocation-backed public routes pass signed zero; the
resolver's negative result withholds progress until journal commit. Each cross-
tail leg performs that exact per-callback capacity check; request classification
additionally preflights the ordinary `4/1/0` floor before the first `1/1/0` leg
can sample time or publish bytes. Before any operation it
copies the admitted source into one private `_EXT4-MAX-BLOCK` snapshot,
preserving caller bytes even when the source aliases a shared ext4 cache or
writer storage that dry staging, activation, or writer rebase will overwrite.
Every post-copy return scrubs the complete snapshot; a caller span overlapping
that private snapshot is invalid. The public router also protects the complete
unconsumed caller span from its own fallback buffer so later
`VFS-WRITE-EXACT` chunks cannot be scrubbed accidentally.

The first clean request dry-stages and aborts before activation; after
activation, successful calls synchronously stage, emit, and checkpoint, then
retain the same scrubbed `IDLE` writer for the next call without arena growth.
A staging refusal reports zero progress and aborts only a still-mutable
transaction. Once emission has advanced, existing writer fault/quarantine
semantics retain the uncertain durable state for remount recovery, and an
already latched abort fault takes precedence over the staging error that led
to it. For initialized overwrite, `actual` is the conservative contiguous
prefix of caller bytes confirmed by the ordered-data write. If `c` whole
512-byte sectors completed and the caller range begins at byte `o` within the
block, the exact rule is `min(count, max(0, c * 512 - o))`; a tear inside the
next sector proves none of that sector. Hole fill and append report no caller
progress until the complete typed transaction has passed emission, because a
new data allocation or bytes beyond old EOF are not yet reachable file content.
Once an operation has crossed its corresponding progress boundary, a later
proof or checkpoint error retains the complete confirmed count. For committed
append, the callback also publishes the committed EOF and times before
returning a checkpoint error so generic VFS advances the descriptor without
creating stale dirty-vnode state.

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

The nonzero-`actual`/`PARTIAL` invariant is per callback.
`VFS-WRITE-EXACT` returns the terminal ior and does not synthesize `PARTIAL`
from an earlier successful callback. A clean zero-progress refusal on the
second leg can therefore have flags zero while the FD cursor and shared vnode
EOF expose the independently checkpointed prefix from the first leg.

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
client remains absent from the ordinary `EXT4-OPS`: it deliberately does not
publish vnode timestamps or dirty state itself. `_EXT4-WRITE`, installed in
`EXT4-STAGED-WRITE-OPS`, supplies the ABI callback boundary and publishes the
successful timestamp and VFS dirty state.

Fault qualification now crosses a 512-byte boundary inside one initialized
block. A 24-byte request beginning at byte 500 tears six bytes into the second
sector after the first sector completed: the callback reports exactly 12
confirmed bytes even though raw-media inspection shows that six later caller
bytes also changed. A separate body-flush failure occurs after the ordered
block completed and reports the full nine-byte request with
`PARTIAL|READONLY`. Both cases retain the exact underlying writer fault,
quarantine the mounted instance, scrub the private source snapshot, preserve
the old inode-table home, and publish no vnode timestamps.

The public staged path also qualifies one second-transaction durability
boundary derived from its successful two-write trace. At flush ordinal 22,
the second ordered-data block is already behind its body fence but the final
commit block has not been confirmed durable. The faulted call reports all six
caller bytes with `PARTIAL|READONLY`, keeps the first write's published vnode
time, and quarantines the reused writer at `COMMIT-FLUSH`. Both modeled
durability views contain both data edits and only the first inode-table home.
If the final commit reached media, a fresh mount replays exactly the second
inode after-image; if only the prior fence survived, it applies no inode home
and retains the first timestamp. Both results clean the active journal and are
byte-stable on another write-free remount. This is a representative reachable
commit fence for the promoted operation, not a claim that every power-cut
ordinal has already been enumerated.

A private driver word, `_EXT4-WRITE`, has the exact ABI-1 callback shape
`( source count offset dentry vfs -- actual ior )`. It validates an owned,
linked regular-file dentry, its shared vnode identity/generation and clean
cached state, and a nonwrapping caller range. An in-size nonempty call derives
`min(count, block_size - (offset mod block_size))` and sends exactly that first
block-bounded chunk through the initialized-overwrite/hole-fill router. A
larger in-size request therefore returns legal short success rather than
widening either qualified transaction. A growth request must begin at exact
EOF. At a partial EOF it may fit the remaining initialized tail or enter the
qualified crossing envelope, in which case the callback preflights `4/1/0` and
returns only the independently committed tail prefix. `VFS-WRITE?` exposes
that short result directly; `VFS-WRITE-EXACT` advances the buffer and offset and
re-enters at aligned EOF for each allocation leg. At aligned EOF the callback
admits at most one data block; its mounted client resolves the current
allocation/root topology to exact `4/1/0` through `8/1/0` credit before begin.
Only the exact-write caller chains committed short results into additional new
logical blocks.
The callback passes the
vnode's ext4 inode number and generation and never owns or advances an FD
cursor. Every exact checkpointed success publishes `mtime`/`ctime` seconds and
nanoseconds into the shared vnode, making the result immediately visible
through every hard-link alias. Initialized overwrite leaves `VN.BLOCKS`
unchanged; successful hole fill publishes the exact incremented ext4
`i_blocks` value into `VN.BLOCKS`. Initialized partial-tail append publishes the
new `VN.SIZE` and leaves `VN.BLOCKS` unchanged; aligned-EOF growth publishes the
new size, exact incremented block count, and free-space count. Atime, link count,
identity, generation, and vnode-dirty state remain unchanged. A pre-commit
failure publishes no vnode fields. A committed partial-tail append that later
fails checkpoint has authoritative full progress, EOF, and times; committed
aligned growth additionally has authoritative block and free-space accounting.
Those fields are published before the partial/read-only error returns.

Block-bounded qualification supplies 1,040 caller bytes at offset 1,016 of the
3 KiB sparse-file shape with a `1/1/0` profile. The initialized first block
checkpoints exactly eight bytes and returns short success; the next independently
bounded request reaches the hole and fails cleanly with `NOSPC`, leaving the
first overwrite durable and its timestamp published. A separate public
`VFS-WRITE?` journey binds `4/1/0`, writes inside that complete logical hole,
allocates one initialized block, and publishes the exact new block count after
its four-home checkpoint. These tests establish both sides of the capacity
boundary without claiming mixed-route multi-block atomicity.

Positive multi-block qualification uses one public `VFS-WRITE-EXACT` request
across the only adjacent initialized pair in the real depth-1 extent fixture.
The request writes eight bytes at the end of logical block 10 and sixteen at
the start of logical block 11. It completes as two independent `1/1/0`
transactions through one allocation-stable writer, samples the clock once per
chunk, and leaves the final vnode/inode time at the second sample. The trace
contains the ordered homes for physical blocks 1362 then 1363 and two
inode-table checkpoints; external extent node 1353 is never written. A clean
ordinary remount performs no I/O, pinned `debugfs` observes the exact 12 KiB
file and unchanged six-range extent map, and pinned `e2fsck` accepts the image.
This promotes a size-preserving multi-block transfer over existing initialized
allocation. It does not promote an atomic multi-block transaction: every
completed chunk is independently durable, a later error leaves earlier chunks
checkpointed, and the FD cursor is the cumulative progress witness.

Generic cursor qualification uses the real staged binding. Its operation table
uses the staged mount gate and installs `_EXT4-WRITE`; its capability mask adds
`WRITE`, and its flags omit `READ_ONLY`. The ordinary `EXT4-BINDING`,
`EXT4-CAPS`, and `EXT4-OPS` remain unchanged. Through the staged binding,
`VFS-WRITE-EXACT` advances an FD only by each callback's confirmed prefix. The
current generic-cursor regression uses a `1/1/0` profile: it checkpoints the
initialized eight-byte prefix, then stops at the allocation step with `NOSPC`
and the cursor at 1,024. The single-hole `4/1/0` journey separately establishes
successful allocation publication. A positive `4/1/0` exact journey now
composes the initialized eight-byte suffix and the following complete logical
hole as two transactions through one writer, advances the cursor to 2,048,
publishes the second timestamp and new block count, and leaves the later
initialized block untouched. Its paired reverse journey fills the complete
hole first, then overwrites eight bytes at the start of the following
initialized block through the same writer. It advances the cursor to 2,056,
writes only the candidate and following data homes, publishes the second clock
sample, and finishes with the initialized-overwrite callback geometry. Together
the tests qualify both `1/1/0 -> 4/1/0` and `4/1/0 -> 1/1/0` transitions. The
callback contract makes no mixed-route atomicity claim.

The same staged binding qualifies generic fault propagation. An ordered-data
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
than ambient `EPOCH@`. `EXT4-BIND-WRITE-CLOCK?` binds it once at an
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
qualification covers missing-clock and duplicate-bind refusal, two live
sync/deactivation boundaries, reactivation through the same writer, exact
hard-link cache publication, unchanged callback-side FD cursors, alias
readback, clean unmount, and independent raw data/inode/journal checks.

`_EXT4-WRITE` remains absent from the ordinary `EXT4-OPS` and `EXT4-CAPS` and
is present only in `EXT4-STAGED-WRITE-OPS`. Generic `VFS-WRITE?` advances only
the calling FD by the returned confirmed prefix; the callback itself owns no
FD. This is a real, deliberately named staged capability. It does not make the
ordinary ext4 binding writable and does not imply support for general data
shapes, allocation geometry beyond the qualified block transactions and their
evidenced initialized and two-allocation transitions across the first two
primary GDT pages, sparse/gap growth, growth past a full resident depth-one
root/full selected-leaf boundary, deeper extent-tree mutation, or namespace
mutation.

Controlled sequential-write qualification tears the first inode-table home
write at byte 269, one byte into the target inode's new `i_ctime`. The ordered
data and committed journal are already durable, while the torn home is neither
the old nor new inode and fails its inode checksum. A fresh mount replays the
retained inode-table after-image exactly, cleans the journal, and is stable on
another write-free remount. This is one pinned checkpoint tear, not yet the
complete power-cut matrix for ordinary writes.

## Read and inspection behavior

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
`EXT4-STAGED-WRITE-BINDING` instead omits `READ_ONLY` and adds the qualified
`WRITE`, `CREATE`, `MKDIR`, `TRUNCATE`, `UNLINK`, `RMDIR`, and `LINK`
capability bits and dispatch slots. The current worktree additionally wires
`RENAME`, `ATOMIC-RENAME`, and `CROSSDIR-RENAME` to the qualified regular-file
and cross-parent empty-directory no-replacement slices described above; it
does not wire `RENAME-REPLACE`. Its
write slot covers the initialized overwrite,
initialized partial-tail append, in-size hole-fill, and aligned-EOF growth
operations described above.
`VFS-WRITE-EXACT` composes those same primitives for the qualified tail-to-one-
new-block route; it does not introduce a fifth transaction primitive.
Both bindings retain `VFS-CAP-SPARSE` for existing sparse mappings and
zero-filled hole reads. The bounded allocation operation is
part of the staged `WRITE` contract; it is not implied for arbitrary holes by
the `SPARSE` capability bit. `VOL-WRITE` and `VOL-FLUSH` remain confined to
authenticated recovery and the staged transaction lifecycle.

## Recovery baseline and writable ratchet

The final target remains full `akashic-ext4-rw-v1` production capability. The
delivery plan is now an operation-scoped ratchet rather than a requirement to
finish a speculative Cartesian product of orphan topology, protocol, geometry,
and fault position before performing ordinary write work.

The governing rule is reachability closure: the driver must recover every
recovery state it elects to accept and every durable state an enabled
operation can create. After replay and strict reload, a valid orphan union
outside the currently qualified recovery closure refuses before its first
cleanup write, mount publication, or writer enablement. Corruption and bounded
workspace exhaustion remain distinct failures. The complete union is
authenticated and preflighted before any member is mutated, so recovery never
cleans a supported prefix and then encounters an unsupported remainder.
Journal and filesystem recovery authority remains present on refusal.

The recovery baseline now clamps recognized-but-unqualified orphan-file maps to
a stable write-free unsupported result after complete structural validation;
malformed authority remains corruption. Future recovery expansion is driven by
states reachable from the next enabled operation, external interoperability
evidence, or a concrete crash/corruption finding. Parser recognition alone is
not admission, but speculative recovery breadth is not a prerequisite for the
next unrelated write ratchet.

Before each additional write capability is promoted, audit the recovery states
that operation can actually create against the same standard: production
cleanup, exact allocation/accounting proof, clean stable remount, pinned
e2fsprogs acceptance, and representative crash recovery for each materially
distinct home/authority topology. Valid reachable shapes lacking that closure
remain fail-closed until their qualification is complete.

Maintain a per-operation reachability ledger containing its request boundary,
transaction homes and credits, possible durable crash states, recovery entry
points, external/checker evidence, and public ABI/capability effect. Expand
recovery ahead of schedule only when the enabled or next operation can create
the state, pinned Linux/e2fsprogs or a representative corpus produces a state
the driver chooses to accept, or concrete crash, fuzz, checker, or field
evidence exposes a gap. If recovery density exceeds one transaction, build a
bounded resumable cleanup protocol that retains recovery authority rather than
adding isolated topology-specific exceptions.

Qualification is compositional. Run the exhaustive journal lifecycle matrix
once per materially distinct state-machine topology, then add the semantic,
durability, interoperability, and checker evidence belonging to each
operation. A new recovery shape does not multiply every protocol, geometry,
and fence unless it changes write ordering, metadata-home roles, witness
authority, batching, ring wrap, or resolver behavior.

The ratchet order is:

1. freeze or clamp the qualified recovery baseline (completed);
2. close initialized overwrite, bounded allocation-backed hole fill and
   aligned growth, exact-write composition, allocation geometry, depth-zero
   root composition, singleton depth-one mutation, and singleton-leaf
   splitting (completed through `3091fca`);
3. make an existing authenticated multi-leaf depth-one root writable: select
   and reauthenticate the governing leaf, insert or coalesce, repair its
   resident index key, and split that leaf while the root retains index
   capacity, preserving untouched leaves byte-exact and preexisting
   unselected index pairs value-exact (completed at `1f4e0ea`);
4. build shared inode allocation and directory insertion, then expose the
   first bounded `CREATE` slice (completed in the current worktree);
5. retain completed same-retained-block shrink and one-block
   `TRUNCATE`-to-zero release, and close the first nonfinal regular-file
   `UNLINK` slice plus atomic closed last-link removal of an already-empty,
   allocation-free regular inode, including descriptor-retained nonfinal
   unlink (completed in the current worktree); retain nonempty and open
   final-link deletion as explicit later lifetime boundaries;
6. retain bounded `MKDIR` and `RMDIR`, including `.`/`..`, parent/child link
   counts, inode/block allocation and release, directory accounting, and
   child-block revoke authority (completed in the current worktree);
7. retain bounded hard `LINK` and no-victim `RENAME`, including regular-file
   same-parent in-place/compacted forms, regular-file cross-parent canonical
   remove/append mutation, and canonical cross-parent empty-directory link
   transfer plus `..` rewrite (completed in the current worktree);
8. close full deletion and truncation lifetime semantics, then add remaining
   metadata and xattr mutation; and
9. perform the final profile closure audit across every profile-admitted
   operation and recovery state.

Extent-tree depth and indexed-directory HTree depth are independent ratchets.
Broaden either only when the next operation or a realistic pinned corpus
demands it. `CREATE` may require a directory-leaf split before any regular-file
workload requires extent depth two; neither tree's speculative generalization
gates the other.

Each landing may move only forward: it must keep all prior qualified behavior,
remain crash-closed, and advertise exactly the capabilities it has earned. An
internal slice is useful implementation evidence but is not public capability;
an explicitly staged capability is public ABI but is still not complete profile
conformance.

## Deliberate remaining limits

The current explicitly staged write surface is not completion of the writable
profile. Its initialized-overwrite, initialized partial-tail append, in-size
hole-fill, and aligned-EOF growth operations are production-closed for their
documented request envelopes. Their qualified tail-to-allocation and additional
allocated-EOF exact compositions preserve independently durable prefixes, but
no broader geometry or operation inherits that status.
`EXT4-STAGED-WRITE-OPS` adds staged `MOUNT`, `WRITE`, bounded linear-directory
`CREATE` and `MKDIR`, qualified shrink `TRUNCATE`, bounded regular-file
`UNLINK`—including nonfinal and empty final-link removal—and bounded canonical
empty-directory `RMDIR` plus bounded regular-file `LINK` dispatch slots to its
copy of the ordinary table. The current worktree also installs the qualified
regular-file and cross-parent empty-directory no-replacement RENAME callback
and advertises `VFS-CAP-RENAME`,
`VFS-CAP-ATOMIC-RENAME`, and `VFS-CAP-CROSSDIR-RENAME`. It deliberately omits
`VFS-CAP-RENAME-REPLACE`. The ordinary binding remains `VFS-BF-READ-ONLY` and
advertises none of these mutations.
Neither binding yet advertises `SETATTR`, `SYMLINK`, `SETXATTR`, or
`REMOVEXATTR`. Each later capability or RENAME expansion
still needs its own bounded credit/chunking contract, reachable-state recovery
closure, namespace/cache behavior where applicable, and interoperability plus
crash qualification. Full profile completion additionally needs general block
and inode allocation, extent and legacy-map growth and shrink, directory-entry
mutation, inode/link/time/accounting updates, xattr mutation, broader per-record
orphan closure, and the final compositional release matrix.

The staged binding's production-closed inventory now contains thirteen
concrete durable paths. Initialized
overwrite uses a full-block ordered-data RMW plus one checksummed inode-table
after-image and consumes `1/1/0`. Strict append uses the same transaction shape
to extend exact partial EOF inside the initialized block, updating `i_size`
without allocation. In-size hole fill allocates one geometry-
selected block, attaches it through a resident depth-zero insertion, checked
adjacent initialized coalescing, qualified single-leaf root composition, or a
selected resident depth-one existing-leaf edit or capacity-preserving split,
updates every required bitmap,
group, and super free-block account plus `i_blocks`, and consumes exact
`4/1/0` through `8/1/0` credit.
Aligned-EOF growth uses the same topology-derived allocation transaction and
also advances `i_size`. Same-retained-block TRUNCATE journals its zeroed data
block and checksummed size/timestamp inode as exact `2/0/0`, without allocation
or orphan state. One-block TRUNCATE-to-zero uses `3/0/0` orphan publication,
an exactly measured linked-orphan cleanup of at most `5/0/0`, and `1/0/0`
transient-bit retirement; it frees one initialized data block while preserving
links and a qualified external xattr. Nonfinal regular-file UNLINK uses exact
deduplicated `2/0/0` or `3/0/0` metadata credit to decrement one link, update
target/parent times, and remove one checksummed linear-directory record without
allocation or orphan state. Open descriptors may retain the removed dentry;
the final close reclaims that cache object without an ext4 transaction because
another persistent link keeps the inode live. Closed final-link UNLINK admits only a canonical
empty regular inode with zero size, zero `i_blocks`, no external xattr or
project ID, no open references, and exactly one authenticated directory
reference. Its at-most-six-home transaction removes that record, updates the
parent times, zeroes the complete inode record, clears the inode bitmap bit,
and increments the descriptor and primary-super free-inode counts. No orphan
interval is needed because no data, extent node, legacy map block, or external
xattr allocation can survive the atomic namespace commit. Bounded `RMDIR`
accepts only the canonical one-block empty directory produced by MKDIR. It
uses exact `6/0/1` through `8/0/1` credit to remove the typed parent entry,
decrement parent links and `used_dirs`, free the inode and directory block,
and revoke the unchanged freed block; the canonical path is `7/0/1`. Bounded
hard LINK uses exact deduplicated `2/0/0` or `3/0/0` credit to add one
checksummed linear-directory record, increment and restamp the target inode,
and restamp the parent inode without allocation, ordered data, revoke, or
orphan state. Same-parent regular-file RENAME likewise uses exact deduplicated
`2/0/0` or `3/0/0` metadata credit. It uses an in-place source-record rewrite
when possible and otherwise emits the qualified deterministic same-block
compacted after-image, restamps source ctime and parent mtime/ctime, and
preserves link counts, allocation, data, maps, xattrs, and orphan state.
Cross-parent regular-file RENAME uses exact deduplicated `3/0/0` through
`5/0/0` credit for the three inode-table roles and two directory blocks. It
performs one paired owner proof followed by full reauthentication, installs
canonical compact-remove and compact-append after-images, and restamps source
ctime plus both parents' mtime/ctime while preserving all link counts,
allocation, data, maps, xattrs, accounting, and orphan state. The canonical
four-home case uses homes 278, 275, 1345, and 1299. Cross-parent
empty-directory RENAME adds the authenticated canonical child block to that
plan and transfers one link from the old parent to the new parent. It requires
exactly one cached dentry reference, preserves open-FD and CWD identity,
rewrites and restamps the child's `..` record, and consumes exact `4/0/0`
through `6/0/0`. Its canonical `5/0/0` vector is
`[283, 275, 1299, 1377, 1364]`. The
timestamped mutation paths update clock-derived
`mtime`/`ctime`; both
allocation-backed operations change `VN.BLOCKS` and free-space accounting, and
both append modes change file size. Exact writes compose the qualified
initialized and hole callbacks across evidenced adjacent blocks and compose the
qualified tail-to-allocation and additional allocated-EOF routes as sequential
`1/1/0` and/or topology-derived `4/1/0` through `8/1/0` transactions. Every
callback is independently durable; a later failure
preserves earlier checkpointed progress, and no multi-block atomicity is
implied. The landed
hole-fill lifecycle includes dry-stage, activation, ordered emission,
synchronous checkpoint, clean deactivation, and a byte-stable write-free
ordinary remount. Its pinned external-tool journey and representative ordered
candidate, GDT-home, and primary-super-home crash recovery are also qualified.
Aligned growth adds its own pinned external-tool journey and W7 ordered-
candidate/W22 inode-home crash closure. Cross-tail composition adds success,
pinned external-tool, deterministic-refusal, late clean-refusal, W22 ordered-
candidate, and W37 committed-inode closure. Additional allocated EOF composition
adds insert-then-coalesce success and the historical late full-root durable-
prefix refusal. The
same-primary-GDT-page initialized cross-group slice adds candidate-derived
accounting-home certification, actual-bitmap alias refusal, and W19 replay of
the exact later-group homes. The cross-GDT-page slice adds an 18-group pinned
fixture, group-16 allocation through primary GDT block 3, and exact W20 replay
without touching the inode-local GDT page. Saturated-root composition adds
public EOF and hole-fill trees, exact five/seven-home public accounting plus
six-home typed stage/abort, distinct inode/root-generation evidence, maximum cross-GDT-page publication with
external checking, clean profile/single-candidate refusals, and W23 leaf-home
replay. Singleton depth-one continuation adds exact five-home existing-leaf
publication, leaf checksum, resident-index pointer/topology preservation and
first-key repair, data/accounting checks, stable remount, and external-tool
acceptance. Singleton-leaf splitting adds exact six-home public publication and
typed staging, two checksummed 42/43-entry leaves, two-index root publication,
whole-file external-tool acceptance, active-empty remount cleanup, and exact
six-home committed new-leaf replay without ordered-data rewrite. Existing
multi-leaf depth-one mutation adds interval-based target selection, full-fanout
capture, selected-leaf reauthentication and key repair, byte-exact preservation
of unselected leaves, exact in-place editing under a full root, two-to-three
index splitting, target-local cross-leaf alias rejection, stable remount, and
pinned `debugfs`/`e2fsck` acceptance. The initial CREATE slice adds initialized-
group inode selection and allocation, checksum/accounting updates, one-block
linear-directory slack insertion, parent/new inode construction, cache
publication, clean unmount, precommit rollback, six-home committed replay,
write-free stable remount, and pinned `debugfs`/`e2fsck` acceptance in one
at-most-six-home transaction. The initial MKDIR slice adds one authenticated
globally unowned data-block allocation, a canonical checksummed `.`/`..`
directory, typed parent insertion, parent/child link accounting,
`bg_used_dirs_count`, exact seven-to-nine-home credit, clean and external-tool
acceptance, four zero-write refusals, precommit rollback, and committed
eight-home replay on the canonical fixture. The initial TRUNCATE slice adds shared-vnode
shrink publication, complete retained-tail zeroing, exact two-home commit,
W7 old-EOF rollback, W17 committed two-home replay, stable remount, and pinned
`debugfs`/`e2fsck` acceptance. The block-releasing TRUNCATE slice adds
authenticated empty-to-singleton modern-orphan publication, exact linked
cleanup and data release, transient-bit retirement without deactivating the
writer, clean/stable external-tool acceptance, precommit descriptor rollback,
and committed inode-home recovery through the orphan path. Empty closed
final-link UNLINK adds a clean same-mount CREATE/remove cycle that restores
inode capacity and cache counts; a precommit descriptor tear retains the name,
inode, and allocation with no UNLINK home replay; and a committed torn
directory home publishes absence and free-inode accounting before recovery
replays all six after-images. Both recovery views reach byte-stable remounts
accepted by pinned `e2fsck`, and no path sets `ORPHAN_PRESENT`. The expanded
CREATE/TRUNCATE/UNLINK capstone passes all 11 selected tests sequentially in
949.80 host seconds. Bounded MKDIR then adds exact inode/block allocation,
canonical `.`/`..` construction, parent-link and `used_dirs` accounting,
four zero-write refusal gates, W7 precommit rollback, and W25 committed
eight-home replay, with pinned external-tool and stable-remount acceptance.
Bounded RMDIR adds a single-walk two-owner proof, exact parent namespace and
inode after-image oracles, inode/block release with parent-link and
`used_dirs` decrement, a revoke-only freed child block, six zero-write refusal
gates plus hostile aliases of each protected owner range, W7 rollback, and W25
committed seven-home replay. Pinned external tools and the write-free stable
remount accept the result. Bounded hard LINK adds exact shared-home and
distinct-parent transaction topologies, shared-vnode and open-FD publication,
four zero-write refusal cases, W7 provisional rollback, W17 committed
two-home replay, pinned external-tool acceptance, and stable remounts across
both clean namespace topologies. At that LINK closure, fresh source mode
measured 1,140,381,589 ext4-load steps across 2,962 packed lines under the
then-approved 1.15-billion-step watchdog, leaving 9,618,411 steps of headroom;
the descriptor journey measured 4,230,599 steps. Qualified same-parent RENAME
adds an open-FD shared-home success, a distinct three-home one-link sparse
success after an unused predecessor, four zero-write refusals, W7 rollback,
W17 committed replay, pinned external-tool acceptance, and stable remount.
The additional same-block compactor success preserves an open FD, passes
external inspection and a stable remount in 108.40 seconds; aggregate-full
zero-write refusal passes in 46.93 seconds; and the in-place regression passes
in 105.09 seconds. Cross-parent regular-file RENAME adds canonical exact
`4/0/0` success over homes 278/275/1345/1299, zero-write short-credit and
existing-victim refusals, W7 rollback of every provisional home, W21 committed
final-home recovery that replays all four after-images, open-FD/shared-vnode
continuity, pinned external-tool acceptance, and a stable remount. Fresh
source mode now measures 1,219,522,351 ext4-load steps across 3,085 packed
lines under the 1.25-billion-step watchdog; the descriptor journey measures
4,543,322 steps. Cross-parent empty-directory RENAME adds the public unloaded-
child-cache path, exact-one-dentry admission with open-FD and CWD continuity,
parent-link transfer, and the checksummed child `..` rewrite. Its canonical
`5/0/0` success checkpoints homes `[283, 275, 1299, 1377, 1364]` at W19
through W23; short-credit/refusal, W7 rollback, and W23 five-home replay all
pass. The stable preimage completed in 193.06 seconds, canonical success in
304.10 seconds, and the same-parent plus regular cross-parent regression in
193.01 seconds. Same-session `MKDIR` then directory `RENAME` completed in
1,524,547,503 guest steps under a measured 2,000,000,000-step composition
watchdog, in 260.07 seconds. Fresh source mode now measures 1,224,225,598 ext4-load steps
across 3,095 packed lines under the 1.25-billion-step watchdog; the descriptor
journey measures 4,549,770 steps. Replacement, victims, and same-parent
directory moves remain outside this envelope. The next phase is full deletion
and truncation lifetime semantics.
Nonempty and open final-link deletion remain later lifetime closure, rather
than a reason to expand orphan recovery speculatively. General sparse/gap growth, unwritten conversion, growth beyond a
full resident root plus full unmergeable selected leaf, mutation starting from
a deeper extent tree, other broader allocation and mutation geometry, multi-
block atomicity, partial or wider block-releasing truncation, and other namespace mutation remain later
capabilities.

The remaining boundaries are the final-profile closure inventory, not an
ordered list of prerequisites for retaining the qualified write surface:

- POSIX ACL xattrs are returned as raw bytes, but generic permission
  enforcement is not claimed;
- read and recovery retain the authenticated 1/2/4 KiB and 128/256-byte-inode
  forms, while staged mutation is currently qualified on 1 KiB/256-byte-inode
  geometry. The initialized-overwrite extent corpus reaches depth 1; hole fill
  and aligned-EOF allocation start either from a depth-0 resident root or from
  a depth-1 resident root containing one through its authenticated inline index
  capacity, with every index naming one checksum-valid external leaf.
  The depth-0 form uses a spare-slot insertion, exact initialized coalescing
  edit, or one saturated-root composition into a single external leaf and
  resident depth-one index. The depth-1 form selects the governing leaf by its
  logical interval and inserts with spare leaf capacity or coalesces in place
  under exact `5/1/0` credit; when that leaf is saturated and cannot coalesce,
  exact `6/1/0` through `8/1/0` credit splits it while the resident root retains
  an index slot.
  Allocation selection is qualified across an initialized group-0-to-group-1
  boundary whose 64-byte descriptors share one 1 KiB primary GDT block, an
  initialized group-0-to-group-16 boundary whose descriptor begins the next
  primary GDT block, a two-allocation group-0/group-1 composition with distinct
  bitmaps sharing one GDT page, and a two-allocation group-9/group-16
  composition with distinct bitmaps and GDT pages. `BLOCK_UNINIT` initialization, partial-last-group
  mutation, wraparound, wider GDT-page layouts, and 2/4 KiB allocation remain
  unqualified.
  The consecutive-hole
  journey proves coalescing by extending the first allocated singleton to
  length two while leaving the root at three entries. The planner also admits
  a full resident root when coalescing preserves its entry count and otherwise
  performs the qualified single-leaf transition. A full existing leaf remains
  eligible for a coalesce that adds no entry or a capacity-preserving split.
  A full resident root remains writable through an in-place selected-leaf edit;
  only a full root plus full unmergeable selected leaf requires unsupported
  deeper growth. Deeper
  trees remain readable through the bounded profile depth limit of 5;
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
  public clean-unmount integration are implemented as shared durability
  foundations. The staged binding composes them with a full ordered-data RMW
  and timed checksummed inode after-image for initialized overwrite or strict
  partial-tail append, or with a newly allocated zero-backed ordered block plus
  four authenticated allocation/inode metadata homes for an ordinary hole fill
  or aligned-EOF growth. Saturated-root composition adds one checksummed leaf
  and any distinct second bitmap/GDT accounting homes, for an exact five-to-
  seven-home transaction. Cross-tail exact writes sequence those existing RMW and
  allocation foundations rather than introducing a third transaction shape.
  Aligned growth carries map, `i_blocks`, `i_size`, times, and checksum in the
  one inode after-image. All
  operations run only after
  mutation-range and filesystem-wide ownership proof. Broader mutation remains
  gated operation by operation.
  Transaction-aware metadata acquisition, checksum-safe typed
  orphan-inode replacement, free-only physical-block accounting, linked
  zero-size inline depth-0 extent or exact empty legacy-format-map truncation,
  exact nonnegative-size
  inline-depth-0, resident depth-1 fanout, or legacy
  direct/indirect unlinked data and inode allocation release, target-record
  scrubbing, exact credit measurement, modern-slot removal, legacy-head
  advancement, and operation/protocol-specific `FINAL`/`MORE` certificates now
  compose one sealed transaction for either orphan mechanism. Production mount
  authenticates and measures the entire supported union before cleanup writes,
  allocates one writer at the maximum safe per-record capacity described above,
  then drains
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
  fixed constant, but still does not cover linked nonzero-size/tail truncation,
  target extent trees deeper than the resident depth-1 fanout, target legacy
  double-indirect maps with authority larger than the caller workspace,
  triple-indirect fanout beyond one allocated all-zero level-2 child, any
  nonzero grandchild, child composition with direct data or an external xattr,
  or a triple root combined with a single- or double-indirect legacy map, a
  nonzero physical high word,
  inconsistent or out-of-range
  shared external-xattr ownership, inline or external xattr value-inode
  release, or general
  link-count and malformed-chain repair. General inode
  allocation, general inode release outside the admitted shape, and every
  user-visible mutation operation remain unimplemented. Cleanup releases
  allocation authority but does not provide secure deletion or data-block
  erasure;
- focused per-shape empty, inline depth-0, and resident depth-1 unlinked
  qualification covers modern and legacy cleanup. Empty and one-block
  baselines span the
  canonical 1/2/4 KiB, 256-byte-inode geometries; 1 KiB qualification additionally
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
  Focused nonzero-size production coverage now reclaims a checksum-valid
  modern sparse orphan with `i_size = 2^32 + 777` and one initialized extent
  under the unchanged 1,200,000,000-step guard. The corresponding legacy case
  is collected but remains pending.
  Mutation-side orphan-file qualification fully validates that inode's
  complete read-profile map rather than trusting an inline-root surrogate,
  then admits only the qualified depth-0/1 extent subset. A checksum-valid
  depth-1 orphan-file fixture places all 31 logical blocks behind a preserved
  external extent node. Linked production cleanup completes with its existing
  exact 34-write/24-flush trace in 1,111,798,161 guest steps, and the resulting
  image remounts byte-identically with zero I/O in 67,492,163 steps. The
  corresponding unlinked JFI admission and complete owner proof take
  240,654,652 steps without a media write. A hostile valid external-xattr
  block also mapped as orphan-file preallocation is rejected as
  `EXT4-D-DATA-MAP` in 121,741,936 steps with all temporary ownership state
  cleared. These are harness measurements, not driver capacities.
  Mount-level refusal covers a nonzero physical high word, unauthorized or
  malformed external-xattr release shapes, orphan-storage aliasing, a clear
  one-block data bit, and a two-block extent whose second allocation bit is
  clear.
  Checksum-valid allocated live-inode fixtures additionally prove that both a
  data extent and an external-xattr pointer aliasing the candidate are
  rejected as `EXT4-D-DATA-MAP` before writer allocation or media mutation.
  A three-block candidate whose middle block alone is named by a live inode
  proves that reverse-owner admission covers the complete range. Both orphan
  protocols are qualified; the same-binding retry returns the same refusal
  with the scoped ownership proof and ambient probe cleared.
  Focused unique-external-xattr qualification covers xattr-only and
  data-plus-xattr deletion plus a complete modern production checkpoint.
  Shared-xattr qualification now separately passes exact EA-only
  stage/seal/abort and data-plus-EA staging under both protocols, plus complete
  EA-only modern and legacy production cleanup. Each production case performs
  exactly one retained-xattr home write, retains the allocation, and remounts
  byte-identically with zero I/O; modern pins 36 writes/24 flushes and legacy
  pins 34 writes/24 flushes. The focused seal proof also exercises the one-slot
  plan-capacity transition bound and rejects a substituted nonzero checkpoint
  CRC when the reconstructed CRC is the valid value zero. A header refcount
  that exceeds the exact counted owner set is corrupt rather than an
  unsupported shape.
  A two-record modern production fixture now qualifies the state transition
  that requires the capacity reserve: two unlinked inodes begin as the only
  owners of one freshly allocated group-0 xattr block, inode 18 decrements it
  from two to one, and inode 21 then releases the final allocation. Both exact
  transactions use six metadata homes inside a writer sized to seven. The
  complete drain has the pinned 60-write/35-flush trace, restores the block
  bitmap and free-block counters to canonical values, preserves the valid
  refcount-one payload without a release overwrite, and remounts with zero I/O.
  These production cases use a scoped 1,500,000,000-step watchdog, a moderate
  increase over the general 1,200,000,000 guard; this is qualification
  headroom rather than an implementation capacity. The two-record transition
  uses the existing 3,000,000,000 multi-data watchdog because it performs two
  complete ownership proofs; it completed in 155.6 host seconds. The remaining
  negative/crash matrix and pinned e2fsck acceptance remain pending before this
  shape closes its release-qualification gate.
  Multi-range qualification admits a separated two-entry modern root and the
  four-entry inline maximum under legacy cleanup, mixing initialized and
  unwritten entries and logical gaps. Deletion qualification now admits the
  complete resident depth-1 fanout of one through four external leaves. A
  13-entry one-leaf regression proves that authorization is bounded by mounted
  block geometry rather than the legacy 12-slot direct-map count; its retained
  release vector contains those 13 data ranges followed by the leaf singleton.
  The four-leaf fixture captures six data ranges covering eight blocks followed
  by four leaf singletons, and modern and legacy dry staging retain all four
  exact revokes in root order. Its modern production mount reclaims all twelve
  blocks under the unchanged 1,800,000,000-step watchdog, preserves every
  released payload without a data or leaf home write, restores allocation
  accounting, and publishes a clean mounted VFS. The shared mutation range
  capacity is now the shared sparse-double legacy authority budget:
  528, 1040, or 2064 pairs at 1, 2, or 4 KiB. The existing one-leaf modern production path
  completed in
  1,686,717,231 guest steps under the feature-specific 1,800,000,000-step
  watchdog. Cross-leaf data overlap, leaf/data or leaf/leaf aliasing, and
  another inode owning a leaf are corrupt data-map input; deeper trees remain
  unsupported. Every refusal is stack-balanced and fails before writer
  allocation or media I/O. The established
  1 KiB cross-group fixture qualifies separate data- and inode-group
  descriptors coalesced into one primary GDT home; the new boundary fixture
  proves that one certified data range may itself cross two groups while both
  data descriptors and the inode descriptor coalesce into that home. The
  separated multi-range fixtures place every active range in one data group
  and prove cumulative bitmap and descriptor changes still retain exactly one
  data-bitmap home and one shared GDT home. Their sealed authority binds the
  raw entry count, exact range count, aggregate block count, every ordered
  pair, and a zero inactive tail; changing a later active pair is rejected by
  exact staged verification. Legacy-direct deletion qualification separately
  fills all 12 direct slots under both orphan protocols. Its certificate and
  checkpoint plan retain 12 ordered singleton ranges and an explicit map-family
  discriminator even though the contiguous physical vector executes as one
  allocation-accounting run. Sparse slots 0, 5, and 11 compact to three
  ordered singleton ranges. Duplicate pointers and mismatched `i_blocks` are
  corrupt data maps.
  A maximum-union regression adds the separate unique external-xattr block,
  exercises all 13 ambient owner ranges, and keeps the 12 data pairs plus xattr
  field distinct through staged verification and abort. Full production cleanup
  with `i_size = 2^32 + 777` completes in
  1,156,337,987 modern and 1,157,813,068 legacy guest steps under a scoped
  1,300,000,000-step watchdog, preserving all seeded data-block payloads while
  restoring exact allocation accounting. The focused modern/legacy pair now
  passes pinned e2fsprogs 1.47.4 `e2fsck -f -n` after rebuilding both
  production fixtures, completing in 200.43 host seconds.
  Single-indirect qualification separately fills all 12 direct slots and the
  final entry of the 1 KiB pointer block, crossing the old direct-only
  12-block boundary. Its canonical
  vector retains direct data, indirect data, and the pointer-block singleton in
  that order; staging seals the distinct map family and exact root revoke. A
  node/data self-alias is corrupt. With the larger shared mutation workspace,
  focused modern production cleanup releases three data blocks and the pointer
  block in 1,313,528,725 guest steps under a scoped 1,500,000,000-step
  watchdog. It preserves all four homes without a payload write, restores
  allocation accounting, and remounts byte-identically with zero I/O.
  Legacy-protocol, maximum-fanout,
  external-xattr composition, crash, and pinned e2fsck qualification remain
  pending for this tier.
  Sparse-double admission accepts an optional double root with zero or more
  occupied children in root-slot order when the exact canonical data, map, and
  present-xattr owner vector fits the shared `2P+16` workspace; the
  single-indirect root remains independently optional. Focused empty-root
  staging retains the double root as the exact one-map authority and one
  revoke. Multi-child preflight covers `{ double root, child@2, child@7 }`;
  exact multi-child staging covers `{ single root, double root, child@2,
  child@7 }` and retains all four map revokes. A separate external-xattr
  composition covers `{ single root, double root, child@2, external EA }`,
  retaining the three map revokes followed by the EA revoke. A boundary check
  admits 524 data plus four map ranges into the exact 528-pair 1 KiB workspace
  when no xattr is present, while a present xattr or one additional data
  pointer returns unsupported recovery. Child/data aliasing and duplicate
  child homes are corrupt; over-budget double-indirect authority remains
  unsupported. Focused sparse-double one-child modern production cleanup
  releases three data blocks and all three map blocks in 1,431,070,159 guest
  steps under a scoped 1,600,000,000-step watchdog. It preserves all six homes
  without a payload write, restores allocation accounting, and remounts
  byte-identically with zero I/O. Multi-child and external-xattr production,
  legacy-protocol qualification, crash qualification, and pinned e2fsck
  acceptance remain pending for this sparse-double tier.
  Triple-indirect admission covers either an all-zero root with optional
  direct data, or exactly one allocated all-zero level-2 child when direct data
  and the external-xattr pointer are absent. Additional root children, nonzero
  grandchildren, child composition, and any single-/double-indirect
  composition remain unsupported.
  Separate focused 1 KiB staging qualification covers one unlinked inode with
  slots 0 through 13 zero, one allocated all-zero triple-indirect root, no
  data, and root-only `i_blocks` under both orphan protocols. The modern case
  completes in 534,968,795 guest steps under its 800,000,000-step watchdog and
  pins six metadata credits, one revoke, and `MODERN_DATA_DELETE_FINAL`. The
  legacy case completes in 529,173,143 steps under the same watchdog and pins
  five metadata credits, one revoke, `LEGACY_DATA_DELETE_FINAL`, and the exact
  legacy head and locator authority. Both stage and seal retain zero target
  entries, one singleton map-metadata release range, one map block, the root's exact
  revoke, and distinct `LEGACY-SPARSE-TRIPLE` authority; preplan and staged
  verification pass, and abort returns the writer and ownership scope clean
  with zero home writes. A second staging pair adds one seeded direct singleton
  in slot 5 ahead of the same empty triple root. Modern completes in 538,439,735
  guest steps and legacy in 530,481,498 under the unchanged 800,000,000-step
  watchdog. Both bind one target data entry, the exact ordered
  `{ direct, triple-root }` release vector, one root revoke, and the same
  protocol-specific credit and locator authority. A maximum-bound pair fills
  direct slots 0 through 11 ahead of the root. Modern completes in 538,468,086
  guest steps and legacy in 546,064,724 under the unchanged 800,000,000-step
  watchdog. Both pin 12 target data entries and blocks, the exact 13-singleton
  release vector with the root last, one map entry and block, the sole trailing
  root revoke, six modern or five legacy metadata credits, zero home
  writes, and clean abort. A further focused 1 KiB staging pair admits zero
  data with one triple root naming one allocated all-zero level-2 child. The
  modern case uses root slot 7 and completes in 597,938,156 guest steps; the
  legacy case exercises the final legal root slot and completes in 560,613,920
  steps, both under the unchanged 800,000,000-step watchdog. Each binds zero
  target entries, the ordered `{ triple-root, level-2-child }` release vector,
  two map blocks and exact revokes, exact root-plus-child `i_blocks`, distinct
  `LEGACY-SPARSE-TRIPLE-CHILD` authority, six modern or five legacy metadata
  credits, zero home writes, and clean abort. Focused modern
  checkpoint-certificate tests refuse partial and coordinated count/revoke
  downgrades while the child type remains sealed. A fully coherent rewrite
  into the older root-only type is still a structurally valid checkpoint
  certificate, but staged-source reauthentication rejects it as a data-map
  mismatch. Focused refusal coverage treats a repeated
  child, root/direct/xattr aliases, an unallocated child, and incorrect
  root-plus-child `i_blocks` as corruption; a second distinct child, a nonzero
  grandchild, and direct-data or external-xattr composition remain unsupported.
  Focused modern production checkpoints the cleanup in 1,359,573,029 guest
  steps under the existing 1,500,000,000-step watchdog. Its exact
  37-write/24-flush trace has the same six cleanup homes as the root-only
  modern shape: the primary super is written three times and the GDT, block
  bitmap, inode bitmap, inode table, and orphan file are each written once.
  Both map allocation bits and the target inode bit clear, free counters return
  to their canonical values, and neither the pointer-bearing root nor its
  all-zero child is written. A byte-identical zero-I/O stable remount completes
  in 56,369,050 guest steps under the standard 1,200,000,000-step watchdog.
  Legacy final-slot production parity completes in 1,379,226,136 guest steps
  under the same production watchdog. Its exact 35-write/24-flush trace has
  five cleanup homes: the primary super is written three times and the GDT,
  block bitmap, inode bitmap, and inode table are each written once, with no
  orphan-file-home write. It restores the same two map bits, inode bit, and
  canonical accounting without writing either released map home, and its
  byte-identical zero-I/O stable remount also completes in 56,369,050 guest
  steps. Both resulting images pass the pinned e2fsprogs 1.47.4
  `e2fsck -f -n` check. A representative modern F12 replay-home flush failure
  reaches the injected fence in 1,088,178,921 guest steps under the standard
  1,200,000,000-step watchdog. The F11-to-F12 interval contains exactly the
  six expected cleanup-home writes and excludes both the triple root and its
  child. Fresh mounts converge both permitted failed-flush durability views:
  the F12 writes surviving and only the prior F11 fence surviving. Each repair
  completes in 271,891,434 guest steps, matches every cleanup home and both
  preserved map homes to the known clean image, and never writes either map
  home. Each repaired image then reaches a byte-identical zero-I/O stable
  remount in 55,920,483 guest steps. Legacy F12 parity; representative F11
  commit and F16 final-super fences, followed by the full controlled
  write-prefix and durability matrix, under both orphan protocols; broader
  2/4 KiB geometry; and implementation, admission, and qualification of
  additional triple-root child fanout remain pending for this child-bearing
  tier.
  The one-direct modern certificate
  refuses missing or extra target counts, a missing range, widened data or root
  singletons, swapped data/root order, and a downgraded map kind before its
  restored authority and transaction tables pass. Root-only negative admission
  covers single- or double-indirect composition, direct/root aliasing, and
  aliasing the triple root with the external-xattr home. Focused single-record
  production and byte-identical zero-I/O stable
  remount qualification now cover the direct composition under both orphan
  protocols. The modern journey checkpoints the cleanup in 1,305,226,732 guest
  steps and the legacy journey in 1,318,122,553, each under the unchanged
  1,500,000,000-step watchdog; both stable remounts complete in 56,367,757
  steps under the standard 1,200,000,000-step watchdog. Their exact
  37-write/24-flush modern and 35-write/24-flush legacy traces retain the same
  six or five cleanup homes as the root-only shape, clear the direct-block,
  triple-root, and target-inode allocation bits, restore every free counter,
  and never write either released block home. Pinned e2fsprogs 1.47.4
  `e2fsck -f -n` accepts both recovered images. Crash qualification for the
  direct composition remains pending. For the root-only shape, the
  single-record modern production journey emits and checkpoints the cleanup in
  1,301,139,781 guest steps under
  its 1,500,000,000-step watchdog. Its exact 37-write/24-flush trace has six
  distinct ext4 cleanup homes: the primary super is written three times, while
  the GDT, block bitmap, inode bitmap, inode table, and orphan file are each
  written once. The released triple-root home is never written; its allocation
  bit and the target inode bit clear, all free counters return to their expected
  values, and a byte-identical zero-I/O stable remount completes in 56,367,001
  guest steps under the standard 1,200,000,000-step watchdog. The corresponding
  single-record legacy production journey completes in 1,314,117,314 guest
  steps under the same 1,500,000,000-step production watchdog. Its exact
  35-write/24-flush trace has five distinct cleanup homes: the primary super is
  written three times, and the GDT, block bitmap, inode bitmap, and inode table
  are each written once; neither the orphan-file home nor the triple-root home
  is written. It likewise clears the root and inode allocation bits, restores
  every counter, and reaches a byte-identical zero-I/O stable remount in
  56,367,001 guest steps under the 1,200,000,000-step watchdog. This establishes
  modern/legacy production and remount parity for the exact root-only shape.
  Pinned e2fsprogs 1.47.4 `e2fsck -f -n` accepts both recovered images. A
  representative F12 replay-home flush failure now qualifies both protocols:
  the modern fault journey reaches F12 in 1,034,182,900 guest steps and the
  legacy journey in 1,051,627,465, each under the standard 1,200,000,000-step
  watchdog. The F11-to-F12 interval contains exactly the six modern or five
  legacy cleanup-home writes, excluding the triple root and, for legacy, the
  orphan file. Fresh mounts converge both permitted failed-flush durability
  views: the F12 writes surviving and only the prior F11 fence surviving.
  Modern repairs complete in 270,728,727 guest steps and legacy repairs in
  266,212,919 for either view. The expected cleanup homes, orphan-file home,
  and preserved triple-root home match the known clean image; no repair writes
  the triple-root home, and each result reaches a byte-identical zero-I/O
  stable remount in 55,919,141 steps. Other crash windows and the full crash
  matrix remain pending.
  Pinned
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
  release qualification gate. A linked legacy-orphan-protocol `18 -> 21 -> 0` fixture
  additionally runs
  the real `MORE`, successor-plan rebuild, terminal `FINAL`, and clean
  deactivation path. It proves the exact 42-write/35-flush trace, the
  intermediate `i_dtime` clear, byte preservation of the terminal inode, and a
  zero-I/O remount. Companion journeys give the linked head one or two
  uniquely owned, separately described extents. The four-credit transaction
  seals plain `LEGACY_MORE` with an exact target-entry count of one or two;
  the two-range root uses logical starts zero and two. Recovery clears every
  extent and `i_blocks`, restores the exact block bitmap/GDT/super free counts
  without touching either seeded payload, advances to terminal `FINAL`, and
  remounts with zero I/O. A parallel modern fixture seals a five-credit
  `MODERN_MORE` over the inode, GDT, block bitmap, primary super, and orphan
  file, then clears successor 21's orphan-file slot with one-credit
  `MODERN_FINAL`. Its exact
  48-write/35-flush trace contains three primary-super writes and two
  orphan-home writes; inode 21 and the payload are never home-write targets.
  Both modern slots finish zero with a valid checksum, allocation accounting
  returns exactly to the linked-modern base, and the remount performs zero
  I/O. These synthetic protocol-state fixtures intentionally have no
  namespace dirents for inodes 18 or 21; they are not e2fsck oracles and are
  not claimed as e2fsck-clean namespace images. Separate focused dry-stage
  qualification admits an exact empty legacy-format linked map under both the
  modern and legacy orphan protocols in a two-record `MORE` prestate. It pins
  a clear `EXTENTS` flag, all 60 `i_block` bytes zero, zero `i_blocks`, target
  entry count zero, data-map kind `NONE`, no release ranges or revokes, exact
  one-home modern and two-home legacy metadata credit, the corresponding
  protocol after-images, staged verification, and abort. A nonempty
  legacy-format linked map remains unsupported. This focused evidence makes no
  production, crash-recovery, or e2fsck claim. A
  later four-extent unlinked record whose fourth range is also owned by a live
  inode proves combined all-range ownership refusal after an earlier supported
  record qualifies but before any write or flush. Structurally valid
  post-seal total-count, protocol-split, and `MORE`/`FINAL` substitutions all
  fault at checkpoint preflight with zero home writes. A linked-owner matrix
  places a live-inode alias in the later selected record: a two-entry modern
  root and a four-entry legacy root both fail whole-union qualification as
  `EXT4-D-DATA-MAP`, leave the earlier safe record untouched, perform no write
  or flush, preserve the caller arena on retry, and clear the ambient range
  table and operation certificate. Modern-only and legacy-only two-record
  deletion fixtures give unlinked head 18 respectively two and four separated
  initialized/unwritten extents before empty successor 21. Exact stage/abort
  qualification pins the six-credit `MODERN_DATA_DELETE_MORE` and five-credit
  `LEGACY_DATA_DELETE_MORE` certificates, including protocol locators,
  pre-union counts, target generation/home/offset/entry count, and the complete
  physical range vector. Full production mounts restore the canonical block
  bitmap and aggregate free-block counters, reclaim both inodes through `MORE`
  then `FINAL`, preserve every seeded extent and gap payload without a
  data-home write, and produce a byte-stable zero-I/O remount. Their pinned
  e2fsprogs 1.47.4 acceptance test remains a pending
  release qualification gate. The per-shape
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
  controlled crash cases remain pinned to the 1 KiB fixture. The linked
  one-block `LEGACY_MORE` path now has a successor-aware controlled matrix.
  Eight trace-derived cuts tear the commit, each of the inode, GDT,
  block-bitmap, and primary-super homes, and the reset-primary, witness-clear,
  and guard-retirement writes. Seven failed durability fences cover commit,
  the complete home batch, reset-preseed and reset-anchor durability,
  primary-reset durability, witness clearing, and guard retirement; both the
  writes surviving each failed flush and the preceding
  durable snapshot independently finish successor 21, reproduce every
  affected ext4 home exactly, preserve the payload without a data-home write,
  and remount without another write or flush. The branch in which the data- and
  inode-group descriptors occupy distinct primary GDT pages, adding one
  metadata home, is implemented but not yet qualified. The parallel modern
  fixture now has two focused successor-aware cuts. A torn first-`MORE`
  orphan-file home is checked against the exact checksum-valid `(0, 21)`
  intermediate image, and the complete-home failed flush repairs both the
  surviving writes and the preceding durable snapshot. Each converges on the
  successful final homes and a write-free stable remount. The remaining eight
  modern write prefixes and six modern durability fences, modern/legacy
  `DATA_DELETE_MORE`, and multi-range `LEGACY_MORE` remain to be qualified.
  Activation, descriptor, and active-primary writes are qualified by singleton
  matrices but are not duplicated here with an active successor. The
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

An operation may be exposed through the explicitly named staged binding once
its implemented request, durability, progress, and refusal boundary is honest.
Counting it as production-closed or promoting it beyond that boundary still
requires reachable replay/orphan closure, external-tool checks, and
representative power-cut qualification. Full `akashic-ext4-rw-v1` conformance
remains withheld until the complete mutation surface, profile-admitted recovery
closure, and final compositional release matrix land.

## Public reference

```forth
EXT4-BINDING              ( -- binding )
EXT4-OPS                  ( -- ops )
EXT4-CAPS                 ( -- capabilities )
EXT4-PROBE-SCORE          ( -- 90 )
EXT4-NEW                  ( arena volume -- vfs ior )

EXT4-STAGED-WRITE-BINDING ( -- binding )
EXT4-STAGED-WRITE-OPS     ( -- ops )
EXT4-STAGED-WRITE-CAPS    ( -- capabilities )
EXT4-STAGED-WRITE-NEW     ( arena volume -- vfs ior )

EXT4-WRITER-WORKSPACE-BYTES?
  ( meta-cap data-cap revoke-cap vfs -- bytes ior )
EXT4-BIND-WRITER-ARENA?
  ( arena meta-cap data-cap revoke-cap vfs -- ior )
EXT4-BIND-WRITE-CLOCK?
  ( now-ms-xt clock-context vfs -- ior )

EXT4-BLOCK-SIZE@          ( vfs -- bytes )
EXT4-BLOCK-COUNT@         ( vfs -- blocks )
EXT4-GROUP-COUNT@         ( vfs -- groups )
EXT4-INODE-SIZE@          ( vfs -- bytes )
```

The authoritative format decisions, source pins, and qualification matrix
remain in [the ext4 compatibility profile](../ext4-compatibility-profile.md).
