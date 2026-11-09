# akashic-vfs-ext4 — checksummed ext4 bindings

IMPORTANT: STEP CEILINGS ARE NOT CRITICAL COMPARED TO CRITICAL PROPER FUNCTIONING. DO NOT SCRUB PROPER FUNCTIONALITY FOR ARBITRARILY SET STEP LIMITS. STEP AND OTHER LIMITS DETERMINED BY IDENTIFIED SYSTEM RESOURCES AND MONITORING.

> **Deployment status:** `EXT4-STAGED-WRITE-BINDING` is a
> **controlled/trusted-local preview**, not a general-purpose, multi-user, or
> drop-in writable ext4 filesystem. Per-operation `production-closed` language
> in this document means that the real implementation is qualified inside its
> exact advertised envelope; it does not make the staged binding generally
> production-ready. Mutation requires exclusive volume ownership, and generic
> permission/ACL enforcement and the documented external/hardware release gates
> remain open. `EXT4-BINDING` remains the ordinary read-only surface.

Every currently staged namespace mutation requires each participating parent
directory to be root-owned and to have ext4 `S_ISGID` (`0x0400`) clear. This
applies to `CREATE`, `MKDIR`, `LINK`, `UNLINK`, `RMDIR`, the sole parent of
same-parent `RENAME`, and both the old and destination parents of cross-parent
`RENAME`; `S_ISUID` (`0x0800`) is a distinct bit and is not the
setgid-inheritance gate.

This VFS ABI 1 driver reads filesystems in the pinned
`akashic-ext4-rw-v1` profile from one explicit KDOS volume. It publishes two
different descriptors. `EXT4-BINDING` is the ordinary read-only surface.
`EXT4-STAGED-WRITE-BINDING` is the current explicitly staged write surface for
authenticated 1 KiB/256-byte-inode geometry. It
supports a general regular-file write: overwrite, growth from any EOF, and
writes past EOF that leave holes, on extent trees of any depth the format
allows. Each callback commits as much of the caller's span as one
transaction of the bound writer profile holds, allocating runs of free blocks
through every initialized and `BLOCK_UNINIT` group with wraparound and
inserting them into the extent tree with the kernel's merge, split, and
depth-growth rules. Callbacks are independently committed and synchronously
checkpointed; `VFS-WRITE-EXACT` composes a larger request from them and makes
no cross-callback atomicity promise. The broader 1/2/4 KiB and
128/256-byte-inode forms remain available to
read and recovery paths; 2/4 KiB and 128-byte-inode mutation await equivalent
qualification. The staged surface additionally provides atomic `CREATE`,
`MKDIR`, and `LINK` through one directory insert. The parent is a one-block
linear directory or an HTree at indirect level 0 or 1 with any number of
index nodes and leaves, and its own extent map may have any depth. The name
takes slack in its block, and a full block grows the directory as the
kernel's `make_indexed_dir` and `ext4_dx_add_entry` do: a full linear block
converts to a depth-zero HTree with two leaves, a full leaf splits, a full
level-zero root grows to level one, and a full level-one node splits under a
root with room. A full root over a full node at level one answers
`VFS-E-NOSPC`, since a third level needs `largedir`. New directory blocks come
from the general allocator and enter the parent's extent tree through the
general insertion, which may split or deepen it. Its `TRUNCATE` sets a linked regular file's
size to any value: a shrink releases every block past the new EOF at any
extent depth and zeroes the new EOF block's tail, and a growth leaves a hole
after zeroing the old EOF block's tail. A release too large for one
transaction under the bound profile runs across transactions behind a modern
orphan record, which mount recovery completes after a crash. The staged
surface also provides `UNLINK` and `RMDIR` through one directory removal. It
admits every parent the insert admits and takes any record out of it, a leaf's
first record included, as the kernel's `ext4_generic_delete_entry` does. A
regular file with more than one link loses one name and keeps its allocation,
and a last link of an empty file loses its inode in the removal's transaction.
A last link with storage, and every removed directory, enters the modern
orphan file in that transaction with no links; release passes and the deletion
then free it, at once when nothing holds it open and otherwise on its last
staged `RELEASE`, and mount recovery finishes the work after a crash. `RMDIR`
removes any empty directory: of any mode, linear or indexed, of any number of
blocks, with an extent map of any depth. `RENAME` runs the same removal and
insert: it moves a regular file or a directory within one parent or across
two, among every parent the insert admits, over no victim, a regular-file
victim, or an empty directory. The source's record leaves as a removal takes a
record out, and the new name enters as the insert places a name, growing the
parent when its block is full, or takes over the victim's record. A directory
that changes parent names the new one in the `..` of its block 0, and the
parents' link counts change as `ext4_rename` changes them. A victim loses its
link in the rename's transaction; a final one, and every directory victim,
enters the orphan file there and drains as a final unlink's target does.
`MKDIR` also allocates the new directory's one block, a canonical checksummed
`.`/`..` block, and updates the parent's link count and the group's
`used_dirs` count in the same transaction.
`LINK` adds a name for an authenticated root-owned regular inode and raises
its link count in the same transaction; it allocates only when the parent
grows, and never creates ordered data, revoke, or orphan state.
The current worktree also provides focused-qualified, staged-only scalar
`SETATTR` for a linked regular file. A nonempty request can select `MODE`,
`UID`, `GID`, `ATIME`, `MTIME`, and `CTIME` under one exact `1/0/0`
inode-table transaction.
The driver also implements bounded mount-time recovery and
durable transaction emission for an internal checksum-v3 JBD2 journal. It never
uses the ambient filesystem volume: reads and all recovery, activation,
emission, checkpoint, and clean-deactivation writes go through checked volume
operations relative to the supplied `VOL-RAW` or `VOL-SLICE` object.

```forth
REQUIRE utils/fs/drivers/vfs-ext4.f
```

`vfs-ext4.f` remains the sole public entry facade. Private implementation
sources live under `utils/fs/drivers/ext4/` rather than appearing as peer
drivers beside the facade, FAT, and MP64FS. Its internal
[`vfs-ext4-admission.f`](ext4/vfs-ext4-admission.md) dependency owns the on-disk
profile and base binding-context layout, checked volume I/O and CRC adapter,
probing, checked geometry arithmetic, and primary-super validation. The base
layout includes two opaque pointer/span slots for the facade-owned XC operation
record; admission does not interpret that record's schema or policy. The
following
[`vfs-ext4-descriptor.f`](ext4/vfs-ext4-descriptor.md) unit authenticates one
group descriptor and its bounded metadata geometry, and owns the shared
checked descriptor-CRC query and restamper used by later policy owners. The
[`vfs-ext4-bitmap.f`](ext4/vfs-ext4-bitmap.md) unit owns exact short-group
geometry,
format-span bitmap CRC calculation, authenticated bitmap loading, and raw
single-block allocation evidence. It keeps all 22 scratch cells private while
mount-wide ownership validation and mutation policy remain in the facade. The
[`vfs-ext4-inode.f`](ext4/vfs-ext4-inode.md) unit owns stack-only inode-record
decoding, `i_blocks` encoding, canonical special-device decoding, checksum
restamping, and timestamp encoding. It keeps all 34 scratch cells private
while media lookup, checksum verification, and identity/locator-result
lifetime remain in the facade. The
[`vfs-ext4-xattr.f`](ext4/vfs-ext4-xattr.md) unit owns external-xattr block header
admission, physical-location-bound checksum calculation, authenticated loading,
and checksum restamping. Its six scratch cells are private, it exports no
mutable result cell, and authenticated bytes reside in the caller-owned
context `C.BLOCK` only after success; xattr entry parsing, allocation,
reference-count, transaction, and recovery policy remain in the facade. The
[`vfs-ext4-orphan.f`](ext4/vfs-ext4-orphan.md) unit owns the orphan-file block tail
magic plus the checked checksum predicate and restamper. Its seven scratch
cells are private and it exports no mutable result. Orphan-file inode
preparation, mapping, physical reads, operation-lifetime locator state,
planning, transaction, and recovery policy remain in the facade. The
[`vfs-ext4-backups.f`](ext4/vfs-ext4-backups.md) unit authenticates sparse-super
copies, immutable superblock identity, and backup descriptor locations without
treating mutable counters as identity. The independent
[`vfs-ext4-dirhash.f`](ext4/vfs-ext4-dirhash.md) unit owns directory-name byte
admission, the ext4 half-MD4 engine, and the checked mounted hash policy. The
[`vfs-ext4-dirent.f`](ext4/vfs-ext4-dirent.md) unit owns directory-entry type
decoding plus complete linear-block validation and checksum restamping. It
keeps all 14 scratch cells private; directory scanning, child-inode admission,
VFS cache publication, and rollback remain in the facade. The independent
[`vfs-ext4-jbd2-codec.f`](ext4/vfs-ext4-jbd2-codec.md) unit owns raw big-endian
access and shared JBD2 checksum validation and encoding; its tag validator
takes the payload, stored checksum, sequence, and context explicitly instead
of reading scanner state. The independent
[`vfs-ext4-jbd2-map.f`](ext4/vfs-ext4-jbd2-map.md) unit owns reusable arena-backed
logical-map geometry, build-time physical uniqueness reservation, completed
map membership, mapped block I/O, and journal-ring stepping. All 16 scratch
cells are private; snapshot construction, protected-authority policy,
scanning, transactions, and durability remain in the facade. The independent
[`vfs-ext4-jbd2-revoke.f`](ext4/vfs-ext4-jbd2-revoke.md) unit owns recovery
revoke-table geometry, allocation, clearing, modular transaction ordering,
insertion, and lookup. Its ten scratch cells are private; parsing,
`REVOKE-READY` publication, replay authority, scrubbing, and durability remain
in the facade. The facade begins at allocation ownership and
initialized-bitmap policy and retains all later filesystem authority,
recovery, transaction, mutation, and VFS-operation policy. Consumers should
not require these internal units directly.

For namespace cross-phase evidence and home planning, the facade defines one
binding-owned record. Its authority/evidence body holds 17 shared cells and
the 24-byte hash-authority snapshot, then, sized by the staged write
geometry, the directory, root, and level-one node snapshots, the insert's
node work block, its record map and that map's hash-sorted copy, the
level-one walk's block-reference bitmap, and one 256-byte inode snapshot.
RENAME adds the old parent's 256-byte inode snapshot, the block the source's
record leaves as media holds it, and a moved directory's block 0.
Record-scoped `OP` and `OWNER-CTX` cells follow that evidence. The tail holds
one entry-count cell and `{ role, journal kind, home }` entries: one for each
semantic role, and for an insert's growth the format bounds of its three
repeatable families, the directory blocks it appends, the nodes of the
parent's extent tree, and the bitmaps and descriptor pages its allocations
stage. At begin the record binds exactly one of `INSERT`, `UNLINK`, `RMDIR`,
or `RENAME` and the owning ext4 context. Namespace planning and staging
receive the record address explicitly; there is no ambient alias. Seal
carries that operation and context with the ordered vector and performs the
complete bounds, journal-exclusion, uniqueness, and intentional-alias audit.
Insert, removal, and rename each derive their vector from a measuring pass, as
the directory-insert, directory-removal, and RENAME sections describe. Every
live pass's final audit reconciles first-seen distinct-home order against the
transaction tables. Each return after record ownership is established clears
the complete record after any required committed cache projection. A failed
ownership check does not dereference or clear an untrusted pointer; it returns
a typed failure without touching that storage.

A rename's new parent takes the insert's roles, and four roles are its own:
`_XC-HR-RENAME-OLD-PARENT-INODE`, the old parent's inode-table block across
parents; `_XC-HR-RENAME-SOURCE-DIRECTORY`, the block the source's record
leaves when the new name does not edit it; `_XC-HR-RENAME-CHILD-DIRECTORY`, a
moved directory's block 0; and `_XC-HR-RENAME-VICTIM-INODE`, a victim's
inode-table block. `_XC-HR-LIMIT` is 18, and the tail holds 85 entries.

Credit comes from the first-seen distinct homes in the sealed plan. An
operation that drains an orphan sizes its writer from the larger of its own
transaction and the cleanup credit and revoke requirement its cold plan
measures from the prospective deletion; that unbounded cleanup union is not
copied into the bounded role vector. Target-inode and child-directory working
evidence remains facade-private. XH retains its private collector for future
work.

The post-`abb3f94` implementation sequence is fixed in the
[ext4 recovery refactor plan](../ext4-refactor-plan.md). That plan records the
semantic invariants, migration order, commit thresholds, and focused
verification cadence that apply before the next indexed-directory capability.

## Cold source qualification

The real-image harness cold-compiles the dependency-ordered production ext4
source closure into the restored FAT/VFS snapshot. The current ext4 stage is
the admission, descriptor, bitmap-admission, inode-format, external-xattr,
orphan-block, backup-authority, directory-hash, linear-dirent, JBD2-checksum,
journal-map, and recovery-revoke units followed by the public facade; VFS,
CRC, and bitset are already present in earlier measured stages.
It does not use a compiled shard or warm cache.
To avoid making UART echo volume an implementation-size limit, the host
injects each compacted physical source line into the BIOS `FSLOAD`
source-buffer span and invokes an immediate `EVALUATE-CHECKED` shim;
`EVALUATE-FINISH` verifies that no definition remains open. The 255-byte
transport bound applies to one injected physical line, not to total driver
size or filesystem geometry. It is unrelated to the current backup-super
geometry boundary: the validator requires each scheduled backup group number
to equal the 16-bit on-disk `s_block_group_nr`, so a required sparse-super
backup above group 65535 is refused.

The checked-in 1,600,000,000-step ext4 cold-source value is a qualification
watchdog and measurement guide, not an ext4 implementation capacity or a
reason to weaken functionality. At the Stage 5 home-plan checkpoint, a real
cold source build loaded CRC in 5,023,896 of 150,000,000 steps across 26
packed lines, bitset in 2,345,116 of 150,000,000 across 9 packed lines, and
the dependency-derived ext4 closure in 1,049,876,551 of 1,600,000,000 across
3,788 packed lines from 13 source units. The closure contains 30,616 physical
lines, 1,177,113 raw bytes, 27,537 loader-executable lines, and 889,803 packed
bytes. Relative to Stage 4, Stage 5 adds 413 physical lines, 14,020 raw bytes,
374 executable lines, 43 packed lines, 9,952 packed bytes, and 20,249,749 cold
source steps (1.97 percent). This remains net source growth after deleting the
six private XC collector artifacts: the payoff is one ordered authorization and
audit path, not an immediate LOC reduction.

At the Stage 4 context checkpoint, a real cold source build loaded CRC in
5,023,896 of 150,000,000 steps across 26
packed lines, bitset in 2,345,116 of 150,000,000 across 9 packed lines, and
the dependency-derived ext4 closure in 1,029,626,802 of 1,600,000,000 across
3,745 packed lines from 13 source units. Relative to the Stage 3 source shape
at `131bf83`, that closure grew from 29,965 physical lines, 1,153,521 raw
bytes, 26,964 loader-executable lines, 3,719 packed lines, and 873,712 packed
bytes to 30,203 physical lines, 1,163,093 raw bytes, 27,163 executable lines,
3,745 packed lines, and 879,851 packed bytes. The exact deltas are +238
physical lines, +9,572 raw bytes, +199 executable lines, +26 packed lines,
and +6,139 packed bytes. The cold-source cost increased by 18,013,927 steps,
about 1.78 percent; this is the explicit context lifecycle and threading cost,
not a promised size reduction.

At the Stage 3 checkpoint `8918024`, after the private-component nesting in
`979d145`, a real cold source build loaded
CRC in 5,023,896 of 150,000,000 steps across 26 packed lines, bitset in
2,345,116 of 150,000,000 across 9 packed lines, and the dependency-derived
ext4 closure in 1,011,612,875 of 1,600,000,000 across 3,719 packed lines from
13 source units. Before this refactor, indexed full-leaf CREATE measured
1,592,943,041 cold-source steps under the same ext4 watchdog. Linear-to-HTree
conversion plus its authority guards previously measured 1,544,762,450 steps
across 3,646 packed lines under the preceding 1.55-billion guard.
Existing depth-zero HTree CREATE previously measured 1,476,019,687 steps
across 3,535 packed lines under its 1.48-billion guard. The preceding
shared-directory-descriptor source measured 1,447,937,156 steps under its
1.45-billion guard, leaving too little measured margin for the indexed
mutation slice; the completed cold build, rather than a mutation-journey or
harness failure, justified the narrow 1.48-billion value. Historically, the
orphan-backed final-link slice measured 1,402,709,928 steps across 3,421 packed
lines under its 1.42-billion guard. At the earlier cross-parent empty-directory
`RENAME` milestone, the source measured 1,224,225,598 ext4-load steps across
3,095 packed lines under the then-checked-in 1.25-billion watchdog. If correct
source legitimately outgrows it, the budget
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
measures 44,133,436. The
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
budget failures include used and allowed steps.

The compact accumulated Stage 3 gate passed sequentially: Gate 2A smoke in
203,248,854 steps; MP64FS create/write/read/delete/sync and second-bitmap-
sector sync/remount against a 150,183,005-step source snapshot; ext4 canonical
image inspection for `primary-1k-i256`; durable and idempotent checksum-v3
replay; and committed-revoke suppression, later-write-after-revoke,
multi-record collision, revoked-primary-super refusal, and large-ring-wrap
recovery. The first combined revoke run exposed old public-mount oracles that
expected transient revoke state to survive mount-tail cleanup; `8918024`
corrected those assertions, after which all five revoke cases passed. This is
compact representative source/runtime equivalence without a compiled cache or
certificate-preservation shortcut, not a rerun of the broad persistence,
fault-injection, crash-fence, stable-remount, or external-tool matrices.

The Stage 4 focused gate then ran sequentially from cold source. It passed
explicit two-plan-record isolation, poisoned same-record reuse and complete
scrubbing across early `BUSY` and one-short `NOSPC` refusals, the four
admitted CREATE shapes (ordinary linear, linear-to-HTree conversion, existing
depth-zero leaf, and full-leaf split), and canonical MKDIR and LINK. The first
run exposed two harness boundaries rather than production failures: a refused
public CREATE legitimately retained one reusable 184-byte VFS vnode while the
test incorrectly required the whole arena pointer to remain fixed, and the
full-leaf split passed all 54 mutation checks before reaching its 1.45-billion
guard during unmount. The corrected plan-specific oracle retains exact plan
address/span reuse and full-record zeroing; the narrowly revised 1.50-billion
journey completed mutation, unmount, and host media checks in 1,453,284,730
steps. This is the Stage 4 context checkpoint, not qualification of Stage 5 or
a rerun of the broad persistence and fault matrices.

The Stage 5 focused gate passed 11 nodes sequentially in 711.34 seconds from
one source-mode snapshot. The direct no-write plan oracle completed in
95,740,969 of 150,000,000 steps and covered atomic checked insertion, duplicate
and cross-kind refusal,
allowed and forbidden aliases, per-kind credit, role lookup, first-seen order,
post-seal immutability, and exact writer-table reconciliation. Ordinary CREATE
completed in 876,534,019 steps; linear-to-HTree conversion in 1,590,846,839;
existing-leaf CREATE in 988,460,471; and full-leaf split in 1,489,035,605. The
conversion and split retain only 9,153,161 and 10,964,395 steps of margin under
their unchanged checked-in caps. The one-short conversion and split profiles
refused before writes in 165,120,935 and 186,321,841 steps. MKDIR completed in
1,152,460,026 steps, the aliased
two-home LINK in 701,408,577, and the distinct three-home LINK in 706,751,366;
their write-free stable remounts completed in 55,245,025, 62,591,725, and
54,979,893 steps respectively. Exact home-write counts, first-seen
trace order, media afterimages, cache/accounting projection, and the existing
external `debugfs`/pinned `e2fsck` oracles remained authoritative. This is the
Stage 5 namespace-insertion checkpoint, not qualification of XH, XU, the broad
recovery/fault matrices, or a new indexed-directory capability.

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

The common base binding context is 15,592 bytes. The staged constructor also
reserves the facade's 12,184-byte namespace-plan record from `fs-arena`, not the
dedicated writer arena. The base-context-plus-record reservation is 27,776
contiguous bytes; other VFS and mount allocations remain separate. The record
is the exact allocation immediately following the base context and must remain
inside the arena's allocated prefix. Allocation occurs only after authenticated
superblock and staged-geometry qualification. A retained staged mount retries
with the same valid allocation and clears it rather than growing the arena; an
invalid retained certificate fails without dereferencing or clearing the
untrusted span. Ordinary construction keeps the two common ownership slots
zero and does not allocate the additional record.

The staged mount admits nonempty mutation only on authenticated 1 KiB
filesystem geometry with 256-byte inodes and a journal capable of at least the
`1 metadata / 1 ordered data / 0 revoke` transaction of a one-block overwrite.
These checks occur during staged mount before it can publish a writable VFS or
mutate media. A write transaction then holds at most the bound profile's
ordered-data credit in data blocks and its metadata credit in homes, and a
write that needs more spans several transactions. The ordinary constructor
retains the broader read/recovery geometry, including 2/4 KiB filesystems and
128-byte inodes.

A mounted instance can reserve the smallest profile, one metadata home and
one ordered-data block, as follows:

```forth
1 1 0 fs EXT4-WRITER-WORKSPACE-BYTES? THROW
A-XMEM ARENA-NEW THROW CONSTANT writer-arena

writer-arena 1 1 0 fs EXT4-BIND-WRITER-ARENA? THROW
```

The three capacities are maximum metadata, ordered-data, and revoke credits;
there is no driver-chosen split or operation-count ceiling. Overwriting mapped
blocks needs one metadata home, the inode-table block, plus one data credit per
block. Allocating needs the inode plus the bitmap, primary-GDT page, and
primary superblock of each group it draws from, so a one-block allocation into
an inline root fits `4/1/0`; a tree edit adds every external node it rewrites
or creates, and a new node from another group adds that group's bitmap and GDT
page. Larger credits let one transaction carry more blocks of a write and
spread its proof and checkpoint over them. The sizing query proves
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

Initialized block-allocation point and range reads use the shared checked LSB0
bitset operations with the canonical exact group block count, so a partial
final group's padding is never allocation evidence. Invalid internal views are
bounds corruption, while a valid missing allocation bit retains the semantic
detail supplied by the caller. The raw point predicate continues to report an
uninitialized block group as ordinary negative evidence; the requiring block
and range wrappers retain their existing rejection policy.
Ordinary and orphan inode loading applies the same rule to the descriptor's
inode bitmap with the canonical exact group-inode count. Invalid logical views
and valid clear target bits both retain the loader's bounds-corruption result;
the record read and checksum remain filesystem-owned.

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
caller-arena storage; cleanup adds no separate fixed record-count constant.
A record is supported for a regular file that does not use data journaling,
whose map is an extent tree of any depth or a legacy block map, and for an
unlinked directory, which RMDIR leaves in the orphan file. A linked
record's target has exactly the `EXTENTS` flag or, for a legacy map, no flags
at all; an unlinked one may carry any flags but data journaling. Release passes
free a linked record's blocks past EOF and every block of an unlinked record,
from the end of its map, as many removal steps per pass as surely fit the
transaction. A legacy map's step cuts the last group-bounded run of contiguous
blocks from its last pointer block and frees each pointer block once it maps
nothing, so holes, sparse branches, and allocated pointer blocks that map
nothing all release the same way. An unlinked record's deletion then frees an
empty map, or folds into the last pass when its homes still fit and takes the
runs that pass freed as its release ranges. An authenticated external xattr is
retained by a linked record. An unlinked record may have any size,
because the release frees its complete map and EOF selects no retained tail.
It may additionally reference one checksum-valid external xattr block. A raw
`h_refcount` of one gives exact allocation-release authority. A count from 2
through ext4's 1024-reference limit instead retains the allocation and permits
only `h_refcount - 1` plus the corresponding block-checksum restamp. The count
must not exceed the filesystem inode count, and one complete allocated-inode
scan must find exactly that many `i_file_acl` references while rejecting the
same block through any data or map-metadata role. Xattr value inodes remain
unsupported. A deletion's decoded `i_blocks` must equal the blocks its release
ranges hold plus the xattr block, in filesystem sectors; each earlier pass took
its own runs off the count. The map keeps the read side's validation rules,
and each pass's map check refuses as corrupt a block the map names twice or
names both as data and as one of its own map blocks. Every release range must be
allocated and lie outside all static metadata and journal ranges. The mount's
block-ownership proof, which runs before recovery's first cleanup, gives every
block of the release set its one owner, so no other inode or the orphan file
maps any of it, and gives a shared external xattr block a reference count
equal to the inodes that name it. A resident inline xattr area is
admitted only after the structural walker
proves bounded, ordered, nonoverlapping values with no value-inode reference.
If even one record is outside these supported per-record shapes, the whole
union returns a stable refusal before writer allocation or cleanup mutation.

Mount drains a qualified union deterministically: the current legacy head and
its authenticated successor chain first, then modern records ordered by
unsigned `(logical-block, slot)`. Each transaction uses the same
maximum-sized writer. Mount dry-stages and aborts that record,
activates or converges the recovery journal as required, then stages, emits,
and checkpoints the same sealed cleanup before selecting again from the
strictly rebuilt plan. A record whose map still maps blocks it must free
takes a release pass in each such transaction, and its final cleanup or
deletion comes once none remain or folds into the last pass.
Modern completion clears the exact orphan-file slot.
Legacy completion advances `s_last_orphan` to the retained successor in the
checksummed primary-super after-image. A linked intermediate record under the
legacy orphan protocol also clears its consumed `i_dtime` link in that
transaction; a terminal zero-successor record whose admitted map is already
empty does not manufacture a no-op inode rewrite. A linked record under the
modern orphan protocol is admitted only with `i_dtime` already zero. An
unlinked delete zeroes the complete target inode record,
including `i_dtime`, without synthesizing a deletion timestamp; the same
transaction clears its inode-bitmap bit and increments the owning descriptor
and primary-super free-inode counters, and a directory's deletion lowers the
descriptor's used-directory count by one, as `ext4_free_inode` does.
A deletion folded into a release pass certifies the runs that pass freed,
whose allocation bits, group counts, and free-block count the pass staged, and
the checkpoint rebuilds the expected bitmaps, descriptors, and superblock from
those runs. Released data
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
records are regular files mapped by an extent tree of any depth or by a legacy
block map, or unlinked directories, is transactionally drained before mount
publication: release passes free a linked record's blocks past EOF before its
final cleanup removes it, and every block of an unlinked record before its
inode is deleted. A union holding any other record, such as a file in
data-journaling mode or an unlinked symbolic link, returns stable
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
bitmap remains part of authenticating live inode 8. Candidate recovery
after-images recheck inode 8 through a checked group-0 exact logical view:
invalid geometry is bounds corruption, while a valid clear bit remains
ordinary negative preservation evidence for the enclosing journal policy.
Before any journal read,
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
arena allocation. The plan's build keeps the counts taken in the current map
epoch, since only a write changes the orphan file's blocks or a legacy
chain's inodes, and counts the modern file again after one. The
authenticated-empty modern branch completes recovery
metadata only when both protocols are empty, without changing an orphan inode,
orphan-file block, or legacy link. Recovery mutation admits the orphan-file
inode itself only with an extent map of depth zero or one. The generic parser
first validates a recognized depth-two-through-five extent tree or legacy map
completely, preserving corruption diagnostics, then a structurally valid wider
map returns stable `EXT4-D-RECOVERY` unsupported without cleanup or mount
publication. A union of linked and unlinked regular-file records, whose maps
may be extent trees of any depth or legacy block maps, is processed one record
at a time as a sequence of sealed transactions: each record's release passes,
then its final cleanup or deletion. Its count is constrained by authenticated
geometry, checked arithmetic, and caller-arena capacity, with no
cleanup-specific constant. Pinned qualification covers
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
context, and active publications. Once the mount's block-ownership proof
stands, it answers this proof without another walk.

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

For each group, exact logical group bounds are passed to the shared checked
LSB0 bitset operations for both the raw/effective all-allocated proofs and the
private after-image range clear. Invalid geometry is corruption; a valid
retained range that is no longer allocated remains a transaction conflict.
The builder then increments the split group free-block counter, installs the
seeded bitmap CRC32C, and restamps the descriptor CRC. These filesystem-owned
CRC, accounting, authenticated-home, and publication rules remain outside the
generic bitset layer. It coalesces descriptors sharing one primary GDT block,
then increments and restamps the checksum-valid primary superblock inside its
complete 1/2/4 KiB home-block image. Repeated disjoint calls compose through
the transaction-aware acquire boundary; duplicate or partially overlapping
staged frees return `VFS-E-CONFLICT`. Context caches remain media-derived and
unchanged until a later strict reload. If any internal failure occurs after
the first replacement is published, the operation automatically aborts and
scrubs the whole transaction, so no descriptor/bitmap prefix can remain
eligible for emission without its aggregate superblock update. This builder
does not remove an extent or legacy map entry, change `i_blocks`, stage a
revoke, or free an inode, and it emits no media write.

The exact-vector wrapper proves every target and touched bitmap home before
execution. Consecutive physical members are then combined with checked
addition and sent through the scalar builder as one run; gaps and nonmonotonic
members remain separate, and a merged run still chunks exactly at group
boundaries. This changes neither the ordered authority vector nor its sealed
checkpoint representation.

`_EXT4-JTX-STAGE-ALLOCATE-RANGE` is the inverse accounting primitive for one
run of free blocks inside a single group. It requires the run in bounds, outside every
journal/static metadata role, and clear in both the checksum-authenticated raw
bitmap and the transaction's effective bitmap. For a `BLOCK_UNINIT` group the
raw bitmap is the one the group stands for, built as described under run
allocation below, and the effective descriptor may keep the flag only until
the transaction's first allocation in that group stages a bitmap. The group
must retain at least the run's free count, its effective descriptor must
authenticate the same bitmap home and checksum, and the primary super must
retain the count globally. Only after all of those checks succeed does the
builder set the run's bits, decrement both counters, clear `BLOCK_UNINIT`,
replace the bitmap checksum, and restamp the descriptor and super checksums.
The raw and retained clear-range checks and the private after-image set use the
shared checked bitset utility with the exact owning group length; invalid
internal geometry is corruption, while a valid retained-state change remains
the existing transaction conflict. The retained homes are the exact bitmap,
primary GDT block, and primary-super home; context caches remain media-derived
until reload. Any failure after the first replacement aborts and scrubs the
transaction.

This primitive deliberately does not choose storage or make a file map point
at it. `_EXT4-JTX-FIND-FREE-RUN` selects storage for every allocating write,
the general write and the directory insert alike: the first free run of at
most a requested length in the transaction's own view of the bitmaps,
searched as described under run allocation below, with a zero count when no
group has a free block.

The enclosing operation must still perform its ownership checks, ordered
data, map edit, `i_blocks` accounting, and publication in the same
transaction. Keeping those authorities separate lets selection and accounting
be tested exactly while preventing either private piece from being mistaken
for a complete user-visible write operation.

Mutation-side admission also has a reusable authority beyond that free-only
builder. `_EXT4-VALIDATE-INODE-TABLE-HOME` requires a proposed inode-table
after-image to fall in exactly the named descriptor's table and in no other
table, block/inode bitmap, sparse-super/GDT interval, or journal extent. It
provides the live-inode-table authority an in-place data mutation needs, but
does not stage or emit one by itself.

The mounted context additionally caches the successful protocol-home proof
described above. It is acquired lazily, so a clean read-only mount does not pay
for a whole-filesystem walk, and a mount whose block ownership is proved
answers it without one. Activation, emission, checkpoint,
deactivation, and recovery cleanup fail closed unless the certificate is
exactly valid; mount-state reset and active replay clear it.

`_EXT4-JTX-STAGE-FREE-ORPHAN-INODE` is the corresponding inode-release
builder, the deletion that ends an unlinked record. Release passes free the
record's data and map blocks before it, from the map's end, at any extent
depth and for any legacy block map, as the orphan drain describes, so the
builder frees no data of its own. It reauthenticates one canonical selected
plan record and accepts an allocated, unlinked regular or directory inode at or above
`s_first_ino`, with a valid nonnegative 63-bit size, whose map is empty or
whose last release pass freed the rest of it in the same transaction. Any size
is valid, since Linux recovery also deletes an unlinked inode whatever its
`i_size`. An empty map's deletion takes an empty data vector, and decoded
`i_blocks` must then hold exactly the inode's xattr block when it has one. A
folded pass instead hands the deletion the runs it freed, which become the
deletion's certified `RELEASED` vector. Their block total must equal the blocks
the pass freed, and decoded `i_blocks` must equal those runs plus the xattr
block, because each earlier pass took its own runs off the count. A resident
inline xattr area is structurally authenticated with the shared reader walker
and must refer to no value inode. The same walker admits one external xattr
block only when its header, checksum, entries, and allocation are valid. At
`h_refcount == 1` the external block is an independent release singleton,
freed last with its own revoke. At a valid larger refcount it remains
allocated and contributes one exact metadata after-image in which only its
refcount and checksum change. Journal-data mode, inodes of other types,
inconsistent shared-xattr owner counts or aliases, and xattr value inodes
remain refused. The typed block-free builder that stages each freed run
requires every one of its bits set and one descriptor owner for each touched
block-bitmap home. The mount's block-ownership proof keeps every run disjoint
from every other owner, the modern orphan file and the journal included, and
the shared xattr's reference count equal to the inodes that name it, so
release admission walks no other inode.

The builder derives the inode
group, bitmap bit, table locator, primary GDT page, and primary-super home from
authenticated geometry, proves the inode bitmap has one descriptor owner and
aliases no block bitmap, inode table, sparse metadata, or journal range, and
requires every transaction home to be pairwise disjoint except the intentional
legacy protocol/super coalescing.

The builder first stages the complete target inode-table home with exactly the
target record zeroed and every sibling byte preserved. It then releases a
unique external-xattr singleton through the typed block-free builder, with its
exact revoke, and leaves the contents of every released block on the media. A
shared xattr instead gets one exact raw-copy metadata image with only
`h_refcount` and `h_checksum` changed; its allocation bit, group and super
free-block counters, entries, values, hashes, and reserved bytes keep their
values. A folded pass has already staged its runs' bitmap, descriptor and
superblock changes, and the deletion's changes compose into the same
after-images: frees in one block group share its bitmap after-image, and all
group descriptor changes sharing a primary GDT block share one GDT
after-image. It finally
clears exactly one retained inode-bitmap bit, increments the split
group free-inode count, lowers a directory's used-directory count, which must
be at least one, installs the new inode-bitmap CRC32C, restamps the
complete descriptor, increments the primary-super free-inode count, and
restamps the super. Raw and retained allocation checks and the private
singleton clear use the shared checked bitset with the exact authenticated
group inode count. Invalid logical geometry is bounds corruption, while a
valid raw missing bit remains orphan-file corruption and a retained missing bit
remains a transaction conflict. Inode counter, checksum, home-order, and abort
policy stay within the builder; its bitmap CRC still spans the format-defined
`IPG / 8` bytes, including padding the logical bitset does not normalize.
Modern protocol removal adds its distinct orphan-file home, while legacy head
removal composes in the same primary-super home.
Semantic verification reconstructs every complete after-image from raw media:
the inode-table home, every touched block bitmap, every coalesced data/inode
GDT page, the inode bitmap, and the primary super, including range-sized group
and super counter increments. This covers sibling inode records, unrelated
descriptors, and all block padding. Its block and inode bitmap reconstructions
use checked exact-group bitset views: malformed logical geometry is bounds
corruption, while valid missing source allocations retain their data-map or
orphan-file detail. The ext4 CRC and complete-home comparison still cover the
format-defined physical bytes, including padding that the logical mutation
does not touch. Staged-empty verification applies one checked exact-group clear
to the transient authenticated raw bitmap cache, then compares that
reconstruction with the retained home across the complete block.
Invalid clear geometry is bounds corruption and any full-home mismatch retains
the corrupt staged-state refusal. The staged-empty and checkpoint proofs also
independently require the target inode bit to be clear through that exact
logical group view. Invalid query geometry is bounds corruption; a valid bit
that is still set retains the existing corrupt staged-state refusal. Each
proof preserves its existing surrounding complete-home CRC and byte-comparison
order.
Checkpoint release-range verification also requires every released block bit
to be clear through the canonical exact group-block view; malformed view
geometry is bounds corruption, while a valid non-clear range retains the
existing corrupt checkpoint refusal. `itable_unused` remains
at its pre-free conservative high-water value and is not incremented during
release; the now-free target record itself is exactly zero. Publish-then-fail
paths abort and scrub the complete transaction.

Reusable external metadata freed by the transaction, the extent nodes or
legacy pointer blocks a release pass frees and a uniquely released external
xattr, receives a journal revoke: each map block as the pass frees it, then
the xattr. A directory's data blocks release as a file's do, without a revoke.
Checkpoint resets the journal after every transaction, so each transaction is
alone in the log, and no release pass journals an image of a directory block
it frees; a revoke for one could shadow nothing.

`_EXT4-JTX-STAGE-ORPHAN-CLEANUP` owns an initially empty metadata-only
transaction for one deterministically selected record of either protocol. It
dispatches by the authenticated link count. A record whose inode still maps
blocks it must free, past EOF for a linked record and anywhere for an
unlinked one, gets one release pass. A pass that leaves blocks past
EOF keeps the record and seals its own certificate, described with TRUNCATE
below; one that ends the release, or a record whose release is already
complete, composes the linked record's final cleanup. The transaction
composes that final cleanup, or an unlinked inode's deletion, with modern slot
removal or legacy-head advancement. An unlinked record's pass that frees the
rest of its map folds the deletion in when the deletion's homes still fit,
counting each home the pass has not already staged: the inode record and
inode bitmap, the inode group's descriptor page, the superblock, a modern
record's orphan block, and an external xattr block's decrement image, or for
its last reference the xattr group's bitmap and descriptor page and a revoke. A
deletion of an empty map requires used and active metadata homes to equal the
exact credit; a final cleanup or deletion that ends a release uses at most the
pass's capacity and may hold a cancelled entry for a map block it edited and
then freed. The transaction then seals
protocol- and operation-specific
raw authority plus retained after-image CRC32Cs into the arena-owned writer.
Modern modes bind the logical block, slot, physical orphan-file home, and
generation. Legacy modes bind the raw checksummed primary super, head inode,
retained successor, and advanced-head after-image. All modes bind the target inode
generation, table location, target data-entry count, transaction epoch, and
applicable retained-image checksums. Delete modes additionally bind the
inode-bitmap home, GDT home and descriptor offset, and complete retained CRCs
for the zeroed target inode-table block, inode bitmap, GDT, and primary-super
after-images. Data-delete modes additionally bind the `RELEASED` data-map
kind, exact range count, aggregate released-block count, and every physical
`{ first, count }` run in the order the folded pass recorded it. Unused pair
slots must be zero. Delete modes
also bind
the external-xattr home, `NONE`/`RELEASE`/`REFDEC` disposition, post-decrement
refcount, and retained-image CRC. A deletion of an empty map revokes only a
released xattr block; a folded deletion keeps its pass's revokes, each inside
one certified run, with a released xattr block last. Every count must fit the
allocated revoke vector before any entry is read. An explicit verifier-complete state keeps a
valid zero CRC distinct from “not reconstructed yet,” so the strict pre-home
comparison cannot skip a zero-valued checksum. The retained
transaction entries and
semantic verifier bind every distinct touched block-bitmap after-image and
coalesced data-group GDT page. For a linked record the target-entry count
binds the raw `eh_entries` of its inline root, or for a legacy map one entry,
its `i_block` array, while the array maps a block and zero once it maps none,
with data-map kind `NONE` and a zero range vector. A zero count tells the
legacy-chain checkpoint that the transaction frees no block, so the
superblock's free-block count must keep its value. The certificate also binds
the checksum of the target's whole pre-image record, so the reload before the
first home write proves the target unchanged since sealing.
A final cleanup stages the target when it also ends the release or clears a
nonterminal legacy head's `i_dtime` successor, and then allows only the block
count, map, that link, and the checksum to differ from the
pre-image; it binds the tail block it zeroes. For deletion, the target-entry
count binds the certified run count plus a mandatory zero target
after-image. No valid CRC32C value is
reserved as a sentinel. Mode is published last; once published, every generic
and typed staging entry point returns busy, while abort and emit remain legal.
The certificate also binds the exact pre-transaction total, modern, and legacy
orphan counts and publishes an operation/protocol-specific `FINAL` mode for a
one-record prestate or `MORE` mode for a larger prestate, or the protocol's
`RELEASE` mode for a release pass, whose post-checkpoint union equals its
prestate. Abort and every
successful writer rebase scrub the complete sealed transaction certificate.

`_EXT4-MEASURE-ORPHAN-CLEANUP` applies the same per-record authentication
without allocating a writer or publishing an after-image. It returns exact
metadata and revoke credits as explicit values; no caller depends on ambient
post-measurement state. A linked record whose inode maps blocks past EOF
measures a release pass: the bound writer profile's capacity, or for mount
recovery a writer sized to free one full leaf of fragmented extents per pass
and halved until the mount arena and the journal hold it. Otherwise its final
cleanup costs one protocol home for a modern orphan-file slot or a terminal
legacy head, one more for the tail block when bytes past EOF need zeroing, and
the target inode-table home for a nonterminal legacy head, whose consumed
`i_dtime` successor it clears. A deletion's geometry-bounded, constant-space
group scan imposes no candidate array or cleanup-specific capacity. An
unlinked record whose map maps blocks measures a release pass, as a linked one
does. A deletion of an empty map adds one revoke for a uniquely released
external xattr; ordinary data and shared-xattr decrements add none.
Checked arithmetic, complete range/static/journal anti-alias validation, and unique
bitmap-owner proofs make the result the coalesced home count rather than an
upper bound. The sealing builder independently requires its staged active-home
count to equal the measured credit, so media or plan drift remains fail-closed.
An unlinked target whose map is empty instead measures its inode table, inode
bitmap, inode-group GDT page, and primary super for exact credit four under
legacy cleanup; the distinct modern orphan-file home makes that five. A unique
external xattr adds the block-bitmap home of its group and its group's GDT page
when the inode-group GDT page does not already represent it. A shared external
xattr adds one metadata home and no release bitmap or descriptor credit. Whole-union writer sizing adds the single derived transition slot
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
orphan-union, and journal authentication, or the journal's alone while the
context's last complete reload stands (described below), but replaces the
public nonempty-policy refusal with an exact writer-certificate comparison. It requires the
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
and super after-image proof, a directory's used-directory decrement
included. For a data delete that proof streams over every
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
strict reload, a reread of every retained metadata home that requires its
complete image and CRC, and root validation, before any journal block or
reservation can be reused. Every mode rereads its homes this way, a generic
transaction's directory and inode blocks included. Every orphan transaction
requires the certified exact decrement at that boundary, while `FINAL`
additionally requires the authenticated empty-orphan predicate. Thus neither
`FINAL` nor `MORE` admission can survive a mismatched first home-write
boundary. The journal release that follows writes only journal blocks, so the
final post-reset proof authenticates the journal again and validates the root
while the poststate the post-home proof established stands; when the
post-home reload no longer stands, the post-reset proof repeats it in full,
poststate included.

Each of those reloads reauthenticates the mount from media, walking only the
inode maps that have not passed a validation in the current map epoch (see
[Block ownership](#block-ownership)), and repeats no work inside itself. One
authentication runs in a proof scope (see the
[admission foundation](ext4/vfs-ext4-admission.md)), so it reads each block
it needs from media once even though every group check reloads the shared
descriptor page. The journal-map snapshot is a pure function of the witnessed
journal tuple, the journal length, the volume size, the recovery-authority
homes it refuses, and its workspace addresses. When all of those equal the
last successful build for the same context, and the map and uniqueness table
still have that build's CRC32C, the reload keeps the snapshot instead of
rebuilding it entry by entry. Any changed input, or any change to the
workspace, rebuilds it from media. Only a build writes the tables, so one
journal validation checks that CRC32C once, and its later calls whose inputs
still match keep the snapshot it checked.

A complete reload validates the superblock, the groups, the backups and the
orphan union from blocks outside the journal and builds the context's state
from them. Every write starts a new map epoch except, on a mount whose
ownership proof stands, a journal write and ordered data to a fresh block,
described with the validated maps below, and none of those blocks can
receive either, so the driver records the context and the epoch each
complete reload finishes in. While that epoch holds, those blocks read as
the reload read them and the state it built stands, and authenticating the
context again runs only the journal validation. Three reloads authenticate
this way when they can: a checkpoint's pre-home reload after a transaction
that wrote no superblock and whose ordered data, if any, went only to fresh
blocks, its post-reset proof, and the first reload of a deactivation. The
generic pre-home reload then checks the standing orphan union, and the
orphan modes' pre-home reload compares the writer's certificate with the
standing plan. Mount finish drops the record, because
the orphan plan moves to its runtime table there without a write, so the
first transaction after a mount reloads in full.

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

Dirty-empty `IDLE` deactivation begins with a flush, a strict reload that
authenticates only the journal while the last checkpoint's reload stands, and
a root proof. It then uses the existing `AKR1` protocol: W1 installs an invalid-byte
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

A committed transaction whose checkpoint did not finish leaves the writer
`FAULTED` with a checkpoint phase: a checkpoint step that fails keeps its own
phase, and a caller that latches a committed writer whose checkpoint never
started records `CHECKPOINT-PREFLIGHT`. The VFS cache already shows the
committed state and the journal holds it, but each metadata home the checkpoint
writes may be torn, or may still hold its old contents where the checkpoint had
not reached it. While the writer stays faulted, a VFS read callback (LOOKUP,
READDIR, READ with READLINK, GETATTR, LISTXATTR and GETXATTR) that reads a
block the writer's metadata table holds as an active entry answers the writer's
recorded first error, unchanged, instead of the block's contents. No path
empties those tables while the writer is faulted, so they name every such home
until the mount ends. Every other block reads as before: files and folders the
transaction did not touch stay readable unless their path runs through a block
it wrote, such as a shared inode-table block, bitmap or descriptor page.
Ordered data is not gated, because emission wrote and flushed it before the
commit record, and cached names still answer from the cache. A writer record
that fails its shape check cannot name its homes, so every block then answers
the error. A fault before the commit record gates nothing, since the homes then
hold the old state the cache keeps. A writer that fails its own validity check
after its commit publishes latches `VFS-E-CORRUPT` in `COMMIT-FLUSH` before the
checkpoint writes any home. Its context still marks the transaction committed,
so a remount will replay it, and its record cannot be trusted to name the
homes, so every block then answers the error. The gate belongs to the faulted
mount alone; a remount replays the transaction and reads every home normally.
`_EXT4-READ-BLOCK` applies the gate only while a read callback runs, so the
writer's own reads are never refused, and STATFS answers from the mount context
without reading a home.

The object layout, counts, embedded pointers, ring fields, phase/fault state,
image checksums, and hash indices are revalidated before they can drive a
fill, copy, lookup, or media write. The public binding and capability mask
remain read-only. Geometry- and arena-bounded transactional completion is
implemented for unions of linked and unlinked regular-file records whose maps
are extent trees of any depth or legacy block maps, under both orphan
mechanisms. The
implementation adds no fixed cleanup
record-count constant; positive union-drain qualification currently reaches
two records.
Before a supported unlinked deletion may release storage, every physical
range in its admitted map must have the deleted inode as its one owner, as
the mount's block-ownership proof establishes before the first cleanup
transaction may mutate media; a data, map-metadata, or external-xattr
reference from another inode is a corrupt cross-link refusal there, for
every retained record at once. Each release pass, linked or unlinked, proves
the runs and the tree nodes or pointer blocks it frees with the general
write's home-set proof and map check: the target's map maps each exactly
once, and the staged map differs from the old one by exactly the blocks the
pass frees.
Per-shape single-record qualification includes initialized and unwritten
extents, nonzero logical starts, multiple separated logical/physical ranges,
the four-entry inline maximum, the 12-slot legacy-direct map, sparse
single-indirect pointers, one- and two-child double-indirect pointers, legacy
maps of any shape, and a physical range crossing two data groups.
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
implemented mutations. `Staged` distinguishes that operation set from complete
`akashic-ext4-rw-v1` conformance. It describes capability breadth, not a
separate write path: every operation admitted here uses the production driver,
durability lifecycle, recovery machinery, and on-disk ext4 format.

### Block ownership

Before a mount's first write, one walk proves that the block bitmaps hold
exactly the blocks the volume's owners hold, each owned once. The fixed owners
are every group's block and inode bitmaps and inode table, wherever its
descriptor places them, and the superblock and descriptor-table copies each
sparse group holds. Every allocated inode owns its map: an extent tree's data
and the tree nodes below its root, or a legacy map's data and pointer blocks.
The resize inode's map holds the reserved descriptor blocks, and the journal's
and the orphan file's maps hold theirs. The walk validates every allocated
inode through the ordinary complete validators, which claim each block they
authenticate in a claim map of one bit per block, so the walk refuses a block
claimed twice, by two owners or twice by one. Those claims also stand in for
the validators' scan of a node's earlier entries for a repeated block, which
only a plain validation, outside any claim or release scope, runs. That scan
keeps a leaf's earlier ranges sorted, so each entry is compared with its two
neighbours in place of every entry before it. An external xattr block may be
shared, so the walk lists every reference to one; each listed block is then
claimed once and must carry an `h_refcount` equal to the inodes that name it.
Each group's block bitmap, or for a `BLOCK_UNINIT` group the one the group
stands for, must finally equal the claims in the group's blocks. The claim map
is the mount's claim workspace, one bit per block and one block of scratch,
which mount reserves with its other workspaces before its rollback-owned tail;
a mount whose arena is too small for it refuses with `VFS-E-NOMEM`. The
reference list grows at the top of the mount arena and is rolled back when the
proof ends, and the proof refuses with `VFS-E-NOMEM` when the list outgrows the
arena. A failed proof returns a corrupt data-map or xattr result and leaves the
mount unproved, and the driver refuses every write until a remount's proof
succeeds. Mount recovery runs the proof before its first orphan cleanup, and
every mounted mutation runs it at its entry otherwise, so only a mount that
writes pays for it. On the 64 MiB, 1 KiB-block fixture it costs 28.6 million
guest steps. The proof also covers the journal protocol's check that no inode
maps the primary superblock or a journal block, since it gives each of those
blocks its one owner.

The driver is the one writer of a mounted volume, so each transaction
afterwards checks its own changes. A block a transaction frees must have its
bit set and be mapped once by the file's old map, a block it allocates must
have its bit clear, and the maps it changes must differ from their old selves
by exactly the blocks it allocates and frees. Every staged transaction proves
the last with a map check before it can commit. The check claims each changed
map as it stood before the transaction; each block bitmap the transaction
stages then claims the blocks it sets and releases the blocks it clears; and
each changed map as staged, read through the transaction, must release exactly
the claims that remain. A transaction that maps a block by mistake, drops a
block from a map while leaving it allocated, or maps a block twice therefore
refuses before commit. A bitmap's checksum lives in its group's descriptor, so
the descriptors the transaction's descriptor-table pages change name every
bitmap it changes.

Each step of an operation also authenticates its target again: its measure,
its staging and its seal each reload the target, and its checkpoint's reloads
validate every orphan target in turn. A plain validation, one outside a claim
scope, an audit, the protocol scope and a transaction's images, depends only
on the inode number, the mount's geometry, two fields of the record and the
blocks it walks. The fields are the block array, which holds the map or its
root, and the generation, which extent node checksums cover; the blocks are
the map's nodes or pointer blocks and the descriptors and block bitmaps of the
groups its blocks lie in. It reads no data block. Once the proof above stands,
every block has one owner, so the journal's block writes, to inode 8's data,
reach none of the blocks a validation reads. Every block a validation, a
reload or the static-role table reads is one the medium's bitmap marks
allocated, or static metadata in a group whose bitmap is uninitialized. A
fresh block, one the bitmap marks free outside every static role and the
journal, is therefore none of them, and ordered data written only to fresh
blocks, as a hole fill's and an append's at a block boundary are, keeps the
epoch. Every other write starts a new map epoch, and so do each run of the
proof and each mount authentication.
The driver keeps the last eight records that passed a plain validation, each
with its epoch, and a record that passed in the current epoch passes again
without a walk while its block array and generation stay the same. Each map
is therefore walked once per epoch however many steps authenticate it. A
release pass walks its target's map once outside the map check, in its
checkpoint's reload after the home writes, and the map check walks the map
before and after the transaction.

The general write, truncate, the truncate's orphan insertion and the release
passes claim the target's old map during the home-set audit's walk of its tree.
Create, mkdir, link, unlink, rmdir, rename, setattr and an orphan's deletion
name each inode record they stage as kept, created or freed. A created inode's
staged map must hold only blocks the transaction allocates, and a freed inode's
old map only blocks it frees. A kept inode's old and staged maps are both
checked when the transaction changes its file type, block count, flags or map;
otherwise the record passes after one comparison of those fields. A kept
inode's xattr block stays where it is in every transaction, and the check
refuses a kept record whose xattr block changes. An orphan's deletion also
claims the xattr block it frees when the orphan is that block's last owner. A
mount cleanup writer owns the end of the mount arena while it stages, so the
check works entirely in the claim workspace; a check that passes leaves the map
clear, and one that refuses clears it. Guest-step figures this document records
for operations measured before the proof replaced each write's scan of every
other inode include that scan.

### General regular-file write

A nonempty write is admitted on authenticated 1 KiB filesystem geometry with
256-byte inodes for a linked regular file whose inode flags are exactly
`EXTENTS`. The mounted instance needs a trusted clock and a caller-owned writer
arena. Any span the format can represent is accepted: overwrite inside EOF,
growth from any EOF, and a write past EOF, which leaves the blocks between as
holes. The final size must fit 32-bit logical blocks, and stays below 2 GiB
unless `large_file` is set; a larger request refuses with `VFS-E-OVERFLOW`
before the clock is sampled. A mapped unwritten extent refuses with the
data-map unsupported result, and a write that reaches one after other blocks
completes the blocks before it.

One callback commits as much of the caller's span as one journal transaction
holds and returns that byte count, so a larger request returns legal short
success and `VFS-WRITE-EXACT` continues from the new cursor. The transaction
begins with the whole bound profile, which caps it at the profile's
ordered-data credit in data blocks and its metadata credit in homes. The pass
stages every logical block of the span in order. A mapped initialized block
receives its new full-block image in place as ordered data, read and modified
first when the span covers it only in part. An unmapped run is allocated,
zero-filled around the caller's bytes, and inserted into the extent tree. When
the write starts past the block that holds a partial old EOF, that block's
bytes past the old size are written as zeros, since the new size makes them
readable, and bytes of a modified block past the old size are zeroed rather
than read. The inode record is staged last with the new size, `i_blocks`, and
trusted-clock `mtime` and `ctime`.

A pass that runs out of transaction room or free blocks, or reaches a block it
may not write, is discarded and restaged up to the last completely staged block
after which a metadata home was still free: a mapped block counts once its
image is staged, an allocated run once its extent is inserted. That free home
takes the inode record, the transaction's last home. The profile therefore
bounds each transaction exactly rather than through a worst-case credit
estimate, and a profile with one data credit writes one block per transaction.
The restaged pass repeats the first pass's runs up to that point, so it stages
the same homes and always fits. A span that cannot stage even its first block
refuses, with `VFS-E-NOSPC` for a full volume or a profile too small for that
block's homes. A write that starts past a partial old EOF block also stages
that block's zeroed tail, which takes one of the pass's data credits, so the
pass covers one block fewer and a one-credit profile refuses such a write.

On a clean mount the first pass is staged and proved before the journal is
activated, so a refusal performs no media I/O; the live pass then repeats it
against the activated volume, emits it, and checkpoints it synchronously.
Later transactions on the same mount stage, prove, emit, and checkpoint
directly, and every successful callback leaves the writer idle and clean for
the next.

### Extent-tree insertion

Each allocated run is inserted at any depth the format allows, as the kernel's
`ext4_ext_insert_extent` inserts it. The run first tries to extend the extent
before it or the extent after it inside the governing leaf, or to bridge both,
as one initialized extent of at most 32,768 blocks; otherwise it takes a free
entry in that leaf. A full leaf splits at the insertion point, as
`ext4_ext_split` splits it: the entries after the insertion point move to a new
leaf whose first key is the next extent's start, or, when nothing follows,
the new leaf holds just the run, so a file growing at EOF keeps full leaves.
Every full index level between the leaf and the lowest level with a free entry
likewise moves its entries after the path into a new index node that begins
with the index for the new node below, and that level takes the index for the
new node above it. When no level on the path has a free entry, the root's
entries move into a new node one level below and the root becomes one index
naming it, as `ext4_ext_grow_indepth` does, up to the format's five levels
below the inode. A leaf whose first key changes corrects each parent index
upward while the corrected index is its node's first entry.

Every node keeps the read side's invariants: an index key equals its child's
first block, no external node is empty, and each external node is checksummed
against the inode number and generation, with the entry bytes past its count
zeroed. Edited and new nodes are staged straight into the transaction, and a
later read in the same transaction takes the staged image; the root is edited
in the operation's private inode record. New tree nodes are allocated next to
the data they map and add to `i_blocks`.

### Run allocation

Allocation searches the transaction's own view of the bitmaps, so a later run
never takes a block an earlier run in the same transaction took. It searches
the goal's group from the goal, then each following group with wraparound,
then the start of the goal's group. The goal continues the extent before the
hole by the logical gap, as `ext4_ext_find_goal` chooses it, or else starts
the inode's group. A run stays inside one group. Each group's clear-bit count
must equal its effective descriptor free count before the group is searched,
and a bitmap that offers a block in the journal or in a static metadata role
is corrupt rather than allocatable.

A `BLOCK_UNINIT` group counts with the bitmap it stands for, built as the
kernel's `ext4_init_block_bitmap` builds it: the backup superblock, descriptor
table, and reserved descriptor blocks when sparse_super places a copy there,
every bitmap and inode table a descriptor places inside the group, and set
padding past a short last group. The descriptor's free count must equal the
clear bits that leaves. The first allocation in such a group stages that bitmap
with the run set, and clears `BLOCK_UNINIT` in the same descriptor edit that
records the new free count and bitmap checksum.

### Home-set proof

The complete home set of each transaction is proved before emission,
whatever mix of data, tree, and accounting homes it holds. The target inode is
authenticated at the start of every pass: its complete map is validated, its
flags, generation, and external xattr block are checked, and its inode-table
home must fall in exactly its own group's table. Allocation accounting proves
every new block clear in both the raw and the transaction's bitmap and outside
every static role. After staging, one validation walk of the target's
pre-transaction tree counts every overlap with the home set while checking
each target range's mutation role. The count must equal the existing data
blocks and tree nodes the transaction rewrites, so each of those is mapped
exactly once, and the target maps no block the transaction allocated and no
accounting home. The target's external xattr block may not be a home. That
walk also claims the target's map for the map check, which proves that the
staged tree differs from the old one by exactly the blocks the transaction
allocates; with the mount's ownership proof, no other owner holds any home.

Each range's static role is checked against the mount's static-role table.
It holds every group's block bitmap, inode bitmap and inode table and every
superblock copy with the descriptor and reserved descriptor blocks after it,
sorted by first block, each entry carrying the greatest end of the intervals
up to it, so intervals that overlap, as corrupt descriptors could give, are
answered exactly too. The table is built from the descriptors once per map
epoch, since only a write can change them, and answers each range with a
binary search, so a check reads no descriptor and its steps grow with the
logarithm of the group count. The proof that the primary superblock and
descriptor homes alias no group's metadata likewise runs once per epoch. The
build also records each group's block bitmap location and descriptor flags,
which every descriptor's verification in that epoch gave, and the allocation
checks read them in place of loading the group's descriptor. The facts keep
their own epoch, since the intervals also need the journal's witness geometry
and an allocation check can run before the journal is validated: a check
that finds them out of date records them alone in one pass over the
descriptors, and a pass that refuses leaves it loading the one it needs. Mount reserves the table with its claim workspace: four entries
and two cells of descriptor facts a group.

### Progress and crash boundaries

Progress is commit-granular for a transaction that allocates or changes the
size: no caller byte is reported until the commit block is durable, and a
fault before then leaves the old size, map, and free-space accounting in
memory and on the medium, with any newly written block still free. A
transaction that only rewrites mapped blocks inside EOF instead reports the
ordered-data prefix that reached the medium before a fault, through the
completed sectors of the torn block, because those bytes are already
reachable. A fault after commit reports the transaction's bytes, publishes the
committed size, block count, free count, and times, and quarantines the mount
`PARTIAL|READONLY`; the next mount replays every metadata home and never
rewrites ordered data. A committed write publishes the same state into the
shared vnode before generic cursor accounting, so every hard link sees one
EOF, and the caller's bytes leave the driver's block buffer on every return.

### Directory insert

The staged binding advertises `VFS-CAP-CREATE`, `VFS-CAP-MKDIR`, and
`VFS-CAP-LINK` and installs `_EXT4-CREATE`, `_EXT4-MKDIR`, and `_EXT4-LINK` in
operation slots 9, 10, and 17; the ordinary binding keeps those slots null.
All three run one directory insert, and RENAME places its new name through
it. Generic VFS builds the provisional cache
object before the callback, and the callback either commits the namespace
change and publishes its stable identity or returns an error that lets VFS
remove the object.

Every admitted parent has root UID/GID, no setgid bit, no inline or external
xattrs, `extra_isize` 32, project 0, and a zero inode tail past byte 160.
CREATE and MKDIR insert into the current directory, as generic `VFS-MKFILE?`
and `VFS-MKDIR` create there. A linear parent has flags exactly `EXTENTS` and
one block; a linear directory of several blocks stays readable, and writes to
it refuse with the write-policy detail. An HTree parent has flags
`EXTENTS|INDEX`, half-MD4 hashing under the superblock's signed or unsigned
flag, and indirect level 0 or 1; other hash versions refuse with the
write-policy detail. The directory's own extent map may have any depth. A
depth-zero map's sector count must equal its blocks', and a deeper map's must
equal its blocks and nodes.

The cold plan authenticates the parent once. It validates the linear block,
or the HTree root and then every index node and leaf the root names, each by
checksum, header, and entry vector or dirent chain. Every live name in every
leaf is hashed and must lie in the interval its route gives it, and the new
name is looked for in every leaf, so a duplicate anywhere returns
`VFS-E-EXISTS`. A level-zero root must name every other block of the
directory once. At level one the walk marks each block it reaches in a bitmap,
refuses a block named twice, and requires the root, its nodes, and their
entries to account for the whole directory. An unused record must also have a
zero name length and file type, or the walk refuses the directory as corrupt.
Older kernels cleared only the inode number of a block's removed first record,
and debugfs does the same, so a folder they edited refuses every write until
the walk admits such records. The walk selects the leaf the new name's hash
routes to, as the kernel's `dx_probe` does: at each level, the last entry
whose hash, continuation bit included, is at most the name's.
Before an HTree parent's names or a converted block's are hashed, the hash
seed, default version, and `s_flags` of the checksummed live primary
superblock must match the mounted copy.

The name takes the first record with room in its block, splitting a live
record's slack or reusing an unused record, as `add_dirent_to_buf` does. When
no record has room, the insert grows the directory as `make_indexed_dir` and
`ext4_dx_add_entry` do:

- A full linear block becomes a depth-zero HTree. The block keeps `.` and
  `..`, with `..` spanning the rest of the block as the root's first records,
  and gains the root information and two entries; the records after `..`
  split by hash across two new leaves at logical blocks 1 and 2. The root
  records the superblock's default hash version, which must be half-MD4.
  Conversion needs `.` at offset 0 with a 12-byte record and `..` at offset
  12, where the root keeps them, and another layout refuses with the
  write-policy detail.
- A full leaf splits into itself and a new leaf, whose entry goes into the
  leaf's index block after the full leaf's.
- When that index block is a full level-zero root, the root first grows to
  level one: its entries move to a new index node, and it keeps one entry
  naming that node.
- When it is a full level-one node under a root with room, the node first
  splits: it keeps the first half of its entries, a new node takes the rest,
  and the root gains the new node's entry, whose hash is the first moved
  entry's.
- When the root is full at level one as well, the insert returns
  `VFS-E-NOSPC`, since a third level needs `largedir`.

A split follows `do_split`. Records move to the new leaf from the highest hash
down while the moved bytes, each record counted by its rec_len, with half the
next record's, stay within half the block; a leaf whose sizes defeat that rule
splits its records in half by count. The last record of a converted block
also counts the bytes `.` and `..` leave to it, as in the copy that
`make_indexed_dir` splits. The first moved hash separates the leaves, with
the continuation bit when the record before it has the same hash. The kept
records stay in block order and the moved ones follow in hash order, each
packed to its used length, and the new name joins the side its hash falls on.
A side without room for the name, which very long names can leave, returns
`VFS-E-NOSPC`, as does a block with fewer than two live records.

New blocks append at the directory's end, a new index node before the new
leaf. Each comes from the general allocator, at the block that would continue
the directory's last extent or else from the start of the parent's group, and
enters the parent's extent tree through the general insertion, which may
extend an extent, add one, split nodes, or deepen the tree. A directory
without `largedir` stays below 2 GiB, and a larger result refuses with the
write-policy detail. Admission requires `dir_index` and `metadata_csum`, so
every leaf ends in its 12-byte checksum record and every index block in its
8-byte tail, and the insert derives every size and entry limit from the block
size.

A measuring pass then stages the complete insert into a transaction that the
writer profile's metadata capacity bounds, binds each metadata home to the
role it plays, and aborts the transaction. Staging names its own homes: the
entry's inode-table block (`_XC-HR-INODE`), the parent's
(`_XC-HR-PARENT-INODE`), the block that takes or splits the name
(`_XC-HR-PARENT-DIRECTORY`), the routed level-one node and the root
(`_XC-HR-DIRECTORY-NODE`, `_XC-HR-DIRECTORY-ROOT`), the new directory's block
(`_XC-HR-MKDIR-DIRECTORY`), each appended directory block
(`_XC-HR-DIRECTORY-GROWTH`), and the inode descriptor, inode bitmap, and
primary superblock (`_XC-HR-INODE-GDT`, `_XC-HR-INODE-BITMAP`,
`_XC-HR-PRIMARY-SUPER`). Every other home is the primary superblock, a block
bitmap or descriptor page that block allocation staged (`_XC-HR-ALLOCATION`),
or a node of the parent's extent tree (`_XC-HR-DIRECTORY-MAP`), and those
nodes must be exactly the ones the tree edit allocated or first edited. The
growth, map, and allocation roles are families that may bind several homes.
The certificate's entries follow the order in which the transaction first
stages their homes: the entry's inode, the parent's record when its map stays,
the parent's existing directory blocks, the new directory's block with its
allocation, each appended block with its allocation and map edits, the
parent's record when its map grows, and the inode allocation. The plan is
sealed, a clean journal is activated, and the live pass stages the insert
again under exactly the certificate's credits. Every binding staging makes
must name its sealed home, the transaction must hold exactly the sealed homes
in order, and the map proof runs before emission. On a clean mount the
measuring pass runs that proof too, so a refusal leaves the medium untouched
before activation, and a profile too small for the measured transaction
returns `VFS-E-NOSPC` without a write.

While no write has started a new map epoch since the cold plan, the bytes of
the authenticated directory blocks stand, and staging takes them from the
plan's snapshots; once activation has started one, staging rereads each block
and requires its snapshot. The entry's and the parent's inode-table blocks are
read in each pass and must hold their authenticated records. The home-set
proof walks the parent's map as it stood before the transaction, once, with
the transaction's homes published: each existing directory block and tree node
the transaction rewrites must be mapped exactly once, and no allocated or
accounting home at all. The walk claims the old map when the transaction
changes it or the map has external nodes, and its claims count the blocks and
nodes a deeper map's sector count must equal. A map the transaction keeps
gives the claims back; a changed map keeps them for the map check, which
proves that the parent's map, and a new directory's, change by exactly the
blocks the transaction allocates. With the mount's ownership proof, no other
owner holds any home.

Each insert is one metadata-only transaction with no ordered data and no
revoke. Its checkpoint uses the ordinary mode: strict reauthentication before
the home writes and the retained-home check after them, which depend on no
directory shape, and recovery replays its homes like any other transaction's.
A committed transaction whose checkpoint fails keeps the operation's success
and its cache projection, records the checkpoint error in `V.LAST-IOR`, and
quarantines the writer; the next mount replays every home. Until then a VFS
read of one of its homes, such as a lookup that reads the parent's directory
block, answers that error (see
[Private transaction staging and durable emission](#private-transaction-staging-and-durable-emission)).

#### CREATE

CREATE allocates an empty root-owned mode-0666 regular inode with one link,
an empty depth-zero extent root, `extra_isize` 32, trusted-clock
atime/mtime/ctime/crtime, an advanced nonzero generation, and a full inode
checksum. Inode selection starts in the parent's group and wraps across the
groups. It accepts only initialized inode groups, verifies the bitmap checksum
and its free count, skips reserved inode numbers, proves that the bitmap and
inode-table homes have their unique descriptor roles, and rechecks the
selected clear bit. Allocation updates the inode bitmap,
`bg_free_inodes_count`, `bg_itable_unused`, and `s_free_inodes_count` and
restamps their checksums; groups that need inode-table initialization refuse
with the write-policy detail. An insert into slack stages the new
inode-table block, the parent's, the parent's block, the inode descriptor and
bitmap, and the primary superblock, six homes at most. A missing trusted
clock refuses before the writer is touched.

#### MKDIR

MKDIR's parent must have a link count from 2 through 64999, so the new
subdirectory cannot overflow ext4's 65000-link bound. The new inode is a
root-owned mode-0755 directory with link count two, size one block, one
depth-zero extent at logical block zero, exact `i_blocks` sector accounting,
and otherwise CREATE's fields. Its block holds `.` with a 12-byte record, `..`
spanning to the checksum tail, and the tail; it comes from the general
allocator, from the start of the new inode's group, and its allocation is
staged after the parent's existing blocks. The parent's entry has file type 2
and the parent gains one link; the group's `bg_used_dirs_count` rises by one.
Default-ACL or setgid inheritance and non-root credential policy refuse with
the write-policy detail.

#### LINK

LINK adds a name for an authenticated root-owned regular inode on the staged
geometry. Its identity, generation, map, inode-table home, inline and external
xattrs, cache projection, timestamps, flags, and zero deletion time are
checked in the cold plan, and its record must hold in both passes. Its on-disk
link count must be from 1 through 64999, and the callback-visible provisional
count the exact incremented value. Reserved or orphan inodes and nonregular,
immutable, append-only, deleted, or saturated targets refuse; an open target
remains admissible because every dentry and descriptor shares its vnode. The
destination parent need not be the current directory, its cache must be
loaded, and the target and parent must be different inodes. The transaction
raises the target's link count and ctime and inserts one file-type-1 record;
it allocates only when the parent grows. Success publishes the target ctime,
the parent's times and any growth, one more dentry reference and link, and one
more VFS inode count.

### Directory removal

The staged binding advertises `VFS-CAP-UNLINK` and `VFS-CAP-RMDIR` and
installs `_EXT4-UNLINK` and `_EXT4-RMDIR` in operation slots 11 and 12; the
ordinary binding keeps those slots null. Both run one directory removal, the
second operation of the engine the directory insert uses, and RENAME takes
its source's record out through it. It admits every
parent the insert admits: a one-block linear directory, or an HTree at
indirect level 0 or 1 with any number of index nodes and leaves, whose own
extent map may have any depth, under the insert's owner, setgid, xattr,
`extra_isize`, project, and inode-tail rules. A linear directory of several
blocks stays readable, and removals from it refuse with the write-policy
detail. Generic `VFS-RM` resolves the name, refuses the root and the current
directory, and for a directory loads its children and returns
`VFS-E-NOTEMPTY` for a cached child before the callback runs.

The callback follows the insert's flow: entry, plan begin, one trusted-clock
sample, one cold plan, a measuring pass, seal, activation of an inactive
journal, the live pass under the certificate's exact credits, emission, cache
publication, checkpoint, and then the drain an orphan-backed removal needs.
The cold plan authenticates the target, an ordinary inode outside the reserved
range that is neither the journal nor the orphan file, root-owned, neither
immutable nor append-only, at its inode-table home, with valid xattrs and a
record that matches its cached projection. It then walks the parent once with
the insert's walk in find mode. The walk validates every block, hashes every
live name against its route's interval, and at level one proves that the root
and its nodes name each block once. In place of the duplicate search it finds
the target's record with its offset, length, and predecessor, refuses a second
record with the name as corruption, requires the record's inode and file type
to match the target, and counts the parent's records that name the target's
inode. A last link needs exactly one such record. A remaining link needs at
least two, so another name in the same parent keeps the inode reachable, and
fewer refuse with the write-policy detail. The certificate takes the leaf or
linear block the record lies in. The current-directory rule binds CREATE and
MKDIR alone, so a removal's parent may be any directory.

The record leaves its block as the kernel's `ext4_generic_delete_entry` takes
it out. A record with a predecessor in its block joins it: the predecessor's
`rec_len` grows by the record's, whether the predecessor is live or unused,
and the record's bytes become zero. The first record of a block, which only an
HTree leaf holds for a removable name, keeps its `rec_len` and becomes unused,
with inode zero and every byte from `name_len` to its end zero. The block's
checksum is restamped, and no other block of the parent changes: the root, the
index nodes, the extent map, the other leaves, and the parent's size and
sector count stay as they were.

A measuring pass stages the complete removal into a transaction that the
writer profile's metadata capacity bounds, binds each home to its role, and
aborts the transaction. It stages the target's inode-table block
(`_XC-HR-INODE`), the parent's (`_XC-HR-PARENT-INODE`), and the block holding
the record (`_XC-HR-PARENT-DIRECTORY`). A target that enters the orphan file
adds the orphan block and the primary superblock (`_XC-HR-ORPHAN`,
`_XC-HR-PRIMARY-SUPER`); a last link of an empty file, which the removal frees
at once, adds the inode descriptor, the inode bitmap, and the primary
superblock (`_XC-HR-INODE-GDT`, `_XC-HR-INODE-BITMAP`,
`_XC-HR-PRIMARY-SUPER`). The live pass stages the same homes under exactly the
sealed credits. While no write has started a new map epoch since the cold
plan, it takes the authenticated blocks from the plan's snapshots, and once one
has, it rereads each block and requires its snapshot; neither staging pass
repeats the cold plan's authentication. On a clean mount the measuring pass
also runs the map proof, so a refusal leaves the medium untouched before
activation, and a writer too small for the removal or for the drain it needs
returns `VFS-E-NOSPC` without a write. A removal carries no ordered data and
no revoke.

A last link with storage, a last link held open, and every directory enter the
modern orphan file in the removal's transaction: the target keeps its map and
allocation with no links and a new change time, the orphan file gains its
record, and the superblock gains `ORPHAN_PRESENT`. The cold plan qualifies the
deletion that will end the record, requires an empty orphan union with a free
slot and mounted free counts equal to the bitmaps, and sizes the writer from
the deletion's credits and the room one release pass needs. The live pass seals
the unlink-ADD payload, and the checkpoint rebuilds every journaled image from
the media and that payload before its home writes. The payload names the
target's record and its predecessor: a splice names a predecessor at a lower
offset, live or unused, and the blank form for a block's first record names a
predecessor length of zero and a predecessor offset equal to the record's
offset, zero, which no splice can name. A directory target's form follows from
its inode type: the record's file type is 2, the target's links go from two to
zero, and the parent's link count drops by one beside its times. The measuring
pass stages the orphan record without sealing it, so an aborted measuring
transaction leaves no sealed checkpoint state. Recovery replays these homes as
it replays any transaction's.

A target that nothing holds open then drains before the callback returns:
release passes free its blocks from the end of its map, one transaction each,
the last pass also deletes the inode and removes its orphan record, and a
final transaction clears `ORPHAN_PRESENT`. A target held open stays readable
through its descriptors and drains on its last staged `RELEASE`, and while its
record is live staged `SYNCFS` returns `BUSY`. After a crash, mount recovery
drains it.

After commit, the callback publishes the target's change time, or for a freed
empty file the mount's free inode count; a removed directory's one link, which
`VFS-RM` lowers to zero; and the parent's times and link count. Generic
`VFS-RM` then removes the dentry and updates the cache counts. A checkpoint
failure after commit keeps the removal's success, records the error in
`V.LAST-IOR`, and quarantines the writer. A drain failure after a durable
removal does the same and leaves the orphan record for mount recovery. Every
refusal before commit leaves the cache and the medium as they were and clears
the plan record.

#### UNLINK

UNLINK removes a regular file's name. A file with more than one link loses one
name and keeps its inode with one link fewer and a new change time; the
transaction stages three homes, or two when the target and parent share an
inode-table block. Descriptors may keep the removed dentry, which generic VFS
reclaims on its last close. A last link of an empty file with no open
descriptor, zero size and `i_blocks`, an empty map, no external xattr, project
0, and no deletion time is freed in the removal's transaction: its inode record
is zeroed, its inode-bitmap bit cleared, and the descriptor's and superblock's
free-inode counts raised, in at most six homes. Any other last link enters the
orphan file and drains as described above; its map may be an extent tree of
any depth or a legacy block map, and it may hold an external xattr. Symbolic
links and other non-regular targets refuse.

Qualification covers each lifetime from a linear parent: a nonfinal name with
an open descriptor that keeps reading the removed dentry, a shared inode-table
home, an empty last link created and removed in one mount, a closed last link
with storage, and an open one that drains on its last close and, after a crash,
through mount recovery. Descriptor tears of the removal and of a drain
transaction retain or recover the right state, committed home tears replay and
drain, and a missing clock or an undersized writer refuses without a write.
In an indexed folder, one mount removes a leaf's first record, a last link with
a block, which enters the orphan file and leaves an unused record in place;
then the second record, which joins that unused record; then an empty file
created into the leaf and removed at once, whose record blanks again. The
mount takes about 281.5 million steps. A tear in the first removal's leaf write replays
the blank record and drains the file. A level-one HTree with two index nodes
loses `candidate-000069`, the first record of a full leaf whose inode keeps
its other links, beside a MKDIR and RMDIR there. Each result passes pinned
e2fsprogs 1.47.4 `e2fsck` and resolves through the driver on a fresh mount.

#### RMDIR

RMDIR removes any empty directory. The cache must hold it with exactly one
dentry reference, outside the current directory, with no child cached, and
with a link count of two; another cached count refuses with `VFS-E-CONFLICT`.
Its flags are `EXTENTS`, or `EXTENTS|INDEX` for an indexed directory, and
nothing else; it has `extra_isize` 32, project 0, a zero inode tail past byte
160, no external xattr, and no deletion time. Any mode is admitted. Other flags
and inode state refuse with the write-policy detail. The parent's link count
must be from 3 through 65000, and the parent loses one.

The cold plan proves the directory empty as `ext4_empty_dir` does, reading
every logical block through the directory's own extent map, of any depth.
Block 0 holds `.` naming the directory and then `..` naming the parent, in a
checksummed linear block whose later records are unused, or it is a valid DX
root of an indexed directory. Every other block is a valid DX node of an
indexed directory or a checksummed leaf whose records are all unused; an
unused record's name length may be nonzero, as the kernel and the read path
accept. A live record in any block returns `VFS-E-NOTEMPTY`. The map proof
claims the directory's map, requires the claimed blocks to equal its sector
count, and gives the claims back; with the mount's ownership proof, every block
the release will free belongs to the directory alone.

RMDIR always enters the orphan file. As the kernel's `ext4_rmdir` does, its
transaction removes the parent's record, lowers the parent's link count, sets
the directory's links from two to zero with a new change time, and adds the
directory to the orphan file, under the unlink-ADD checkpoint. The directory
then drains through the release passes and deletion a file's last link uses:
at once when no descriptor holds it, on its last staged `RELEASE` when one
does, and through mount recovery after a crash. The deletion lowers the
group's `bg_used_dirs_count`, as `ext4_free_inode` does; its after-image, its
seal, and its checkpoint verifier carry the decrement, and the cold plan
requires a count of at least one. `bg_itable_unused` keeps its high-water
value.

A directory's data blocks release as a file's do, without a revoke.
Checkpoint resets the journal after every transaction (`_EXT4-RESET-JOURNAL`
in `_EXT4-JTX-CHECKPOINT`), so each transaction is alone in the log, and no
release pass journals an image of a directory block it frees; a revoke for one
could shadow nothing. Revokes of the extent nodes a pass frees stay as they are
for every map.

The public RMDIR of the directory MKDIR made writes its five homes in
checkpoint order: the child's inode-table block, the parent's, the parent's
directory block, the orphan block, and the superblock (writes 19 through 23
after activation). Its drain frees the child's block and inode in one
transaction of six homes (writes 42 through 47) and then clears
`ORPHAN_PRESENT` (write 61); the mount takes 148,545,811 steps. One mount
removes directories of mode 0700, of three linear blocks, with a 16-byte `.`
record, indexed with five emptied leaves, and with six blocks under a depth-one
map, and the free counts and `used_dirs` come back exact. A live name in a
later leaf, which the cache does not show, returns `VFS-E-NOTEMPTY` from the
emptiness proof; a third link refuses at entry, before the clock; `DIRSYNC`
refuses with the write-policy detail; a missing clock, a four-block writer,
and a group with no used directories refuse too, and none of them writes. A
tear in the parent's directory block replays the removal and drains the
directory; a crash at the drain's descriptor leaves it to mount recovery,
which frees it with exact counts; a descriptor tear of the removal retains the
directory; and an open directory drains on its last close. In a level-one
HTree with two index nodes, MKDIR takes the start of an empty leaf's unused
record and RMDIR blanks it. Each result passes pinned `e2fsck`.

### RENAME

The staged binding installs `_EXT4-RENAME` in operation slot 13 and adds
`VFS-CAP-RENAME`, `VFS-CAP-ATOMIC-RENAME`, `VFS-CAP-CROSSDIR-RENAME`, and
`VFS-CAP-RENAME-REPLACE` to the staged descriptor; the ordinary binding keeps
the slot null. RENAME is the third operation of the engine the directory
insert and removal use, and it is built from them: the source's record leaves
its parent as a removal takes a record out, and the new name enters the new
parent as an insert places one, or takes over the victim's record. It moves a
regular file or a directory within one parent or across two, over no victim, a
regular-file victim, or an empty directory, and it admits every parent the
insert admits. Generic `VFS-RENAME-AT` looks the new name up in the new
parent, through the dentry cache and LOOKUP, and takes the dentry it finds as
the victim before the callback runs. It refuses a directory moved beneath
itself, a victim of the other kind, a victim that is the current directory, a
directory victim with a cached child, and, under `VFS-RN-NOREPLACE`, an
existing name.

The callback follows the engine's flow: entry, plan begin, one trusted-clock
sample, one cold plan, a measuring pass, seal, activation of an inactive
journal, the live pass under the certificate's exact credits, emission, cache
publication, checkpoint, and then the drain a final victim needs. Entry admits
no flag but `VFS-RN-NOREPLACE`. The source is a regular file, or a directory
that exactly one dentry holds; a symbolic link or another kind of source
refuses with the write-policy detail, and so does a victim of such a kind. A
victim is a vnode distinct from the source's. A directory victim is held by
one dentry outside the current directory, has no child cached, and has a
cached link count of two; another count refuses with `VFS-E-CONFLICT`.

The cold plan authenticates the source, and then the victim, as the removal
authenticates its target: an ordinary inode outside the reserved range that is
neither the journal nor the orphan file, root-owned, neither immutable nor
append-only, at its inode-table home, with valid xattrs and a record that
matches its cached projection. A directory also has flags `EXTENTS` or
`EXTENTS|INDEX`, `extra_isize` 32, a zero inode tail past byte 160, no xattr
block, and project 0. The plan then walks each parent once with the insert's
walk. Across parents the old parent's walk finds the source's record, as a
removal's walk finds its target's, and the new parent's walk looks for room
for the new name as an insert's does, or finds the victim's record by the new
name. Within one parent one walk does both. The source's record must be found.
A victim's record must name the victim, and a regular-file victim with another
link needs another name for it in the new parent, the proof a nonfinal unlink
makes.

The source's record leaves its block as the directory removal takes a record
out: it joins its predecessor, live or unused, or, as a block's first record,
keeps its `rec_len` and becomes unused. Without a victim, the new name then
enters the new parent through the insert's edit. It takes the first record
with room in the block its hash routes to, or the parent grows by conversion,
leaf split, root growth, or node split, and a full root over a full node at
level one returns `VFS-E-NOSPC`. Over a victim, the victim's record takes the
source's inode number and keeps its name, `rec_len`, and file type, and
nothing grows. Within one parent the removal comes first, and the insert plans
against the directory that removal leaves: when the new name routes to the
block that held the source, the plan scans that block again, so a name that
fits where the source was needs no growth, and a block that takes both edits
is staged and stamped once. The kernel's `ext4_rename` adds the new name first
and then deletes the old one, finding it again after a split. Both orders
leave a valid directory, and this one never splits a block that the removal
leaves room in.

A measuring pass stages the complete rename into a transaction that the writer
profile's metadata capacity bounds, binds each home to its role, and aborts
the transaction; the live pass stages the same homes under exactly the sealed
credits. As for the insert and the removal, staging takes each authenticated
block from the plan's snapshots while no write has started a new map epoch
since the cold plan, and once one has, it rereads the block and requires its
snapshot. The certificate's entries follow the order in which the transaction
first stages their homes:

1. the source's inode-table block (`_XC-HR-INODE`) and a victim's
   (`_XC-HR-RENAME-VICTIM-INODE`);
2. across parents, the old parent's inode-table block
   (`_XC-HR-RENAME-OLD-PARENT-INODE`) and the block the source's record
   leaves (`_XC-HR-RENAME-SOURCE-DIRECTORY`); within one parent, that block
   when the new name edits another;
3. the new parent's edit, with the insert's roles: its inode-table block when
   its map stays, the block that takes the name or holds the victim's record,
   any index node and root, a moved directory's block 0
   (`_XC-HR-RENAME-CHILD-DIRECTORY`), each appended block with its
   allocation and map edits, and its inode-table block when its map grows;
4. a final victim's orphan block and the primary superblock (`_XC-HR-ORPHAN`,
   `_XC-HR-PRIMARY-SUPER`).

Only inode-table roles may share a home. The map proof checks every inode the
rename names: the new parent's map changes by exactly the blocks its growth
allocates, and every other map stays as it is, a victim directory's counted
against its sector count. On a clean mount the measuring pass runs that proof
too, so a refusal leaves the medium untouched before activation, and a writer
too small for the rename or for the drain it leads to returns `VFS-E-NOSPC`
without a write. A rename carries no ordered data and no revoke.

After commit the callback publishes the source's change time, a victim's
change time, each parent's times, link count, and any growth, and the mount's
free blocks. Generic `VFS-RENAME-AT` then lowers the victim's cached link
count by one, removes its dentry, and moves the source's dentry to its new
parent and name, keeping its vnode, its open descriptors, and the
current-directory object; for a directory victim the callback first sets that
count to its one remaining link, as RMDIR's does. Until the callback succeeds
the old cached name stays authoritative. A checkpoint failure after commit
keeps the rename's success, records the error in `V.LAST-IOR`, and quarantines
the writer; a drain failure after a durable rename does the same and leaves
the orphan record for mount recovery. Every refusal before commit leaves the
cache and the medium as they were and clears the plan record.

#### Moving directories

A directory renamed within its parent changes only its parent's record. A
directory that moves to another parent names the new parent in the `..` of its
block 0: the second record of a linear block, restamped with the dirent tail,
or the `..` entry of a DX root, restamped with the DX tail. The cold plan
reads block 0 through the directory's own extent map and validates it, with
`.` naming the directory and `..` the old parent. No other block of the moved
directory is read, so it may have any size, shape, map depth, and mode. Its
map proof requires its map to name that block once and no other home the
transaction stages. The directory keeps its link count and takes a new change
time.

The parents' link counts change as `ext4_rename` changes them. The old parent
loses a link when a directory leaves it for another parent, which needs a
count from 3 through 65000. The new parent gains one when a directory arrives
from another parent, which needs a count below 65000, and loses one for a
directory victim, so a directory arriving over a directory victim leaves the
new parent's count as it was. Each parent takes new modification and change
times.

#### Renaming over a victim

The victim loses its link in the rename's transaction. A regular-file victim
with another link keeps its inode with one link fewer and a new change time. A
final regular-file victim, and every directory victim, enters the modern
orphan file in the same transaction with `ORPHAN_PRESENT`: a file goes from
one link to none, and a directory, which the cold plan first proves empty as
RMDIR's proof does, from two to none, each with a new change time. The cold
plan qualifies the deletion that will end the orphan record, as a final
unlink's does, and requires the victim's xattr block to be none of the
rename's own homes. A victim that nothing holds open then drains through its
release passes and deletion before the callback returns; an open one stays
readable through its descriptors and drains on its last staged `RELEASE`; and
mount recovery drains it after a crash.

A rename over a final victim seals the rename form of the unlink-ADD payload,
and the checkpoint rebuilds every journaled image from the media and that
payload before its home writes. The payload names the victim's record with its
parent and block; the source's inode, the block holding its record, the
record, and its predecessor, in the splice or blank form a removal's payload
uses; across parents, the old parent; and for a directory that changes parent,
its block 0, the one home the payload cannot derive, which the writer holds in
a cell of its own. The rebuild sets the victim's links to zero with its change
time, the source's change time, and each parent's modification and change
times with the link changes above, in whatever inode-table blocks they share.
It then rewrites the victim's record to name the source, removes the source's
record, rewrites the moved directory's `..` and restamps that block as its
leaf or DX root, and fills the orphan slot and the superblock flag. The source
has the victim's kind, which the VFS layer guarantees and the source's typed
prestate load proves. Its credit is four to nine metadata images. A rename
with no victim, or over a victim with another link, is an ordinary metadata
transaction, and recovery replays either form as it replays any transaction's.

#### Limits and qualification

A symbolic link or other source or victim that is neither a regular file nor a
directory refuses with the write-policy detail, and a linear parent of several
blocks refuses as it does for the insert and the removal. `VFS-RN-NOREPLACE`
refuses an existing name, and no exchange form exists. The VFS layer refuses
what its cache shows, and the driver's proofs refuse what the cache cannot
show: a live record in a victim directory returns `VFS-E-NOTEMPTY`, as RMDIR's
proof does. `VFS-RENAME-AT` looks up only the new name, so a parent of any
size can take it.

Qualification builds its parents with pinned e2fsprogs 1.47.4: `debugfs`
writes them and `e2fsck -fyD` indexes them. Within one parent, a 40-byte name
takes the space a 40-byte source leaves in a full linear block, directories
are renamed in a linear and an indexed parent, and the first record of an
HTree leaf takes a name of its own length, all without growth; one mount runs
the four renames in 133.5 million steps. A full linear block converts for a
200-byte name, a 150-byte name splits another leaf of the same indexed parent,
and a file from a linear parent enters a full leaf, which splits. A linear and
an indexed non-empty directory move into a level-one parent with two index
nodes, whose leaves hold one name each; each child's `..` then names that
parent, and the indexed child's leaves are unchanged. A directory replaces an
empty directory within one parent and across parents, and a leaf's first
record replaces a file in another leaf, each victim draining through the
orphan file. A tear of the checkpoint in a split leaf, in a moved directory's
block 0, and in the block of a sealed directory-victim rename each replays on
the next mount, and the victim drains. A victim directory with a live record
the cache does not show, a new parent at the link limit, and a symbolic-link
source refuse without a write.

The public fixtures pin each case's homes and write order. An open file
renamed within its block writes homes 278 and 1345 at writes 16 and 17 after
activation, and its descriptor and directory-home tears roll back and replay.
A one-link sparse file is renamed after an unused record, a block with only
small holes converts, and a conversion larger than a two-image writer refuses
before any write. A file moved from `/fixture` into the root writes homes 278,
1345, 275, and 1299 at writes 18 through 21, with a descriptor tear that rolls
back and a final-home tear that replays all four. The empty directory moved
beneath `/landing-dir` writes homes 283, 275, 1299, 1377, and 1364 at writes
19 through 23; a descriptor tear at write 7 rolls it back, and a tear of the
child's block at write 23 replays all five. Renames over a closed final file,
an open final file, and a file with another link pass, as do renames over a
name in an indexed folder across leaves, within one leaf, and from a leaf's
first record, and over such a name from a file in a linear folder. A move
between leaves of a level-one HTree with one index node, followed by a move
into it from a linear parent, takes 200,027,347 steps in one mount. Each
result that writes passes pinned `e2fsck`, and each new case resolves its
names through the driver on a fresh mount.

### General TRUNCATE

`_EXT4-TRUNCATE` sets a linked regular file's size to any value the format
holds, in one journal transaction when its release fits the bound writer
profile and otherwise across several, as described at the end. The generic
VFS prepublishes the requested size and retains the old size while the
guarded callback runs. The callback authenticates the target as the general
write does: a linked regular file outside the reserved inodes, with exactly
the `EXTENTS` flag, the expected generation, a fully validated map, and a
valid external xattr block when it has one. The on-disk size must equal the
VFS's old size, the orphan union must be empty as for every other staged
mutation, and a size past the format's limit refuses with `VFS-E-OVERFLOW`.
A request for the current size refuses as unsupported: the generic VFS marks
the volume dirty after any successful truncate, and a dirty volume whose
journal is inactive refuses every later mutation until the next sync.

A shrink releases every mapped block at or past the block that follows the new
EOF, at any depth the format allows, as the kernel's `ext4_ext_remove_space`
releases it. Working from the end of the file, each step cuts the last
group-bounded run from the last extent that reaches past that block, shortening
the extent or removing its entry; initialized and unwritten extents are
released alike. A leaf that empties is freed with a journal revoke and its
index leaves the parent, upward while parents empty in turn, and a root that
empties becomes an empty depth-zero root. No index key changes, since a node
keeps its first entry until the node itself goes, so every step ends in a valid
tree. One walk serves each leaf, which is staged once after its cuts. The freed
runs are recorded, coalescing with their neighbours, and their allocation
accounting is staged after the cuts through the vector free builder, one
bitmap, descriptor, and superblock update per coalesced run. `i_blocks` falls
by the freed data and tree blocks, and the root's slots past its last entry are
zeroed, as every edited node's are.

When the new EOF falls inside a mapped initialized block, the bytes past it
are zeroed, and that block is staged as a journaled after-image rather than
ordered data. Ordered data lands before commit, so a transaction that then
failed would leave the old size showing zeroed bytes; journaling the block
makes the old and the committed images the only recovery authorities. A
growing truncate leaves the new range as a hole. When the old EOF falls
inside a mapped initialized block, that block's bytes past the old size are
written as zeros, this time as ordered data, since the old size hides them
until commit. The inode record, with the new size, `i_blocks`, and
trusted-clock `mtime` and `ctime`, is the transaction's last home.

The home-set proof is the general write's. One validation walk of the
target's pre-transaction tree counts every overlap with the freed runs and
the transaction's homes; the count must equal the freed blocks, the zeroed
tail, and the existing tree nodes the transaction edits. The map check then
proves that the staged tree differs from the old one by exactly the blocks
the transaction frees.

On a clean mount the transaction is staged and proved before the journal is
activated, so a refusal performs no media I/O; the live pass then repeats it
against the activated volume, emits it, and checkpoints it synchronously. A
failure before commit returns its error, and the VFS restores the old cached
size. A failure after commit returns success with the diagnostic in
`V.LAST-IOR`, republishes the committed size, block count, and times, and
quarantines the mount, whose next mount replays the transaction.

Each block group the freed runs touch costs one bitmap home, each distinct
descriptor page one more, every freed tree node one revoke, and every
coalesced run one entry in the mutation range workspace, so what fits one
transaction follows how many groups the released blocks span and how
scattered they are rather than the file's size. A shrink that does not fit
runs across transactions, as the kernel's ext4 truncates. The first commits
the new size and trusted-clock times together with one modern orphan-file
slot and the primary `ORPHAN_PRESENT` bit, leaving the map and `i_blocks`
unchanged. Release passes then free the blocks past the new EOF from the end
of the file. A pass takes a removal step only while the step's worst case
still fits the profile: its run can add a group's bitmap and descriptor page,
and the superblock until an earlier run of the pass has counted it, and every
level it empties adds a freed node with its own bitmap and descriptor page, an
edited parent, a revoke, and a recorded run.
A pass keeps the inode's size and times, and its home-set proof covers the
runs it frees. The record's final cleanup zeroes the bytes past EOF in the
block that holds it, when any of them is not zero, and clears the slot. The
pass that ends the release carries the final cleanup too when its homes
still fit, as the kernel's last truncate handle removes the orphan; otherwise
the final cleanup is a transaction of its own. A last transaction retires
`ORPHAN_PRESENT`. Every refusal comes before the first commit: the profile
must hold the three-home insertion, the volume must have an orphan file with
room in its runtime plan, and a probe pass staged before any media I/O must
be able to take one removal step, so a profile whose revokes cannot cover the
tree's depth refuses with `VFS-E-NOSPC`. After the insertion commits, a
failure returns success with the diagnostic in `V.LAST-IOR`, republishes the
committed state, and turns the volume read-only, and the next mount finishes
the release.

The orphan record makes a crash recoverable at every point. Before the
insertion commits, the old file stands. After it, mount recovery finds the
linked record and runs the same release passes and final cleanup with its own
writer, sized to free one full leaf of fragmented extents per pass and halved
while the mount arena or the journal cannot hold it, so the file ends at its
new size with its blocks free. A record the kernel leaves for an interrupted
truncate completes the same way, its tail zeroed as the kernel's orphan
cleanup zeroes it. A release pass's checkpoint certificate binds the record's
locators and union, the target's pre-image checksum, and the staged target,
which may differ from its pre-image only in block count, extent root, and
checksum; for a legacy record it also binds the staged superblock, which
keeps the record at the list head. The final cleanup's certificate binds the
same pre-image, the staged target when the cleanup also ends the release or
clears a legacy successor link, which may then differ from its pre-image in
block count, extent root, that link, and checksum, and the tail block's
image, which keeps the bytes before EOF and zeroes the rest.

### Linked-regular-file scalar SETATTR

The current staged descriptor advertises `VFS-CAP-SETATTR` and installs
`_EXT4-SETATTR` in ABI slot 16; the ordinary binding remains read-only with a
null slot. Its focused promotion gate has passed, making only the documented
linked-regular scalar slice production-closed; this is not a broader metadata
or xattr promotion.

An admitted request names a still-linked regular dentry and selects a nonempty
subset of exactly six scalars: `MODE`, `UID`, `GID`, `ATIME`, `MTIME`, and
`CTIME`. Selecting `RDEV`, targeting a nonregular or detached inode, or using a
`MODE` value outside 16 bits refuses. A selected `MODE` is the complete ext4
mode and must retain the regular-file type field (`0x8000`); MODE mutation also
refuses while `system.posix_acl_access` exists because this slice does not
synchronize the ACL mask. UID and GID each admit the full unsigned 32-bit
range. Every selected timestamp requires seconds from `-2147483648` through
`15032385535`, inclusive, and nanoseconds from `0` through `999999999`.

This is a raw scalar persistence interface, not a POSIX credential-policy
layer. It performs no authorization, has no `UTIME_NOW` or `UTIME_OMIT`
encoding, does not clear set-id bits, and does not synthesize ctime when another
field changes. The callback samples no trusted clock: every selected time comes
from the request. Because trusted-clock binding is clean-endpoint-only, a
caller that will need clock-derived operations later in the same mounted
session must bind that clock before the first mutation.

Admission and the dry/live transaction stages reauthenticate the dentry/vnode,
inode generation and locator, complete current mapping, inode-table record,
cache projection, and inline plus external xattrs. The mount's ownership
proof gives the inode-table home its group's table alone, so no inode aliases
it as data, extent-map metadata, or external-xattr storage. An accepted edit
commits
one checksummed inode-table metadata after-image under exact `1/0/0` credit:
there is no data payload, revoke, allocation, accounting edit, or orphan state.
Unselected scalar fields, file bytes, the complete map, links, size, block
count, generation, and all xattrs remain unchanged.

Generic VFS clears `V.LAST-IOR` immediately before dispatch and publishes no
requested vnode field when the callback returns an error. Once the journal
commit is authoritative, a later checkpoint failure instead leaves its
diagnostic in `V.LAST-IOR` while the callback and public SETATTR return success;
generic VFS then publishes the selected fields and dirty state. Setting either
UID or GID nonzero explicitly self-narrows the present staged namespace
envelope: later `LINK`, `UNLINK`, and `RENAME` paths on that regular inode still
require UID and GID both zero and will refuse it. That is a documented boundary
of these raw primitives, not credential-policy composition.

The focused selector
`local_testing/test_vfs_ext4.py::test_staged_vfs_setattr_commits_all_linked_regular_scalars_exactly`
passed `1/1` in 97.68 seconds. Through one shared hard-link vnode it publishes
all six scalars, independently verifies their on-disk timestamp encoding and
inode checksum, observes the exact one-home `1/0/0` transaction, and preserves
the file data, complete map, external xattr, and allocation accounting. This
qualifies only the scalar envelope above; xattr mutation remains next.

## Read and inspection behavior

The current binding advertises targeted lookup, directory enumeration,
open/release, reads, getattr, readlink, list/get xattr, statfs, syncfs, and
fsync. Stable ext4 inode number plus generation is used as the VFS identity.
`VFS-CACHE-DENTRY` therefore makes hard-link aliases share one vnode and
preserves the authoritative on-disk link count.

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

Directory population snapshots the child head and inode count. Any I/O,
checksum, allocation, or structural failure rolls the cache back before
returning, releasing the dentries it cached and with them their names. Sparse reads synthesize zeroes without issuing a media
read for the hole. `FSYNC` now validates or checkpoints a retained writer;
`SYNCFS` additionally lands a write-active empty journal clean while
preserving the still-mounted instance's ready/current authority.

`EXT4-BINDING` has `VFS-BF-NEEDS-VOLUME`, `VFS-BF-READ-ONLY`, and
`VFS-BF-STABLE-IDS`. The VFS rejects all mutation before binding dispatch.
`EXT4-STAGED-WRITE-BINDING` instead omits `READ_ONLY` and adds the qualified
`WRITE`, `CREATE`, `MKDIR`, `TRUNCATE`, `UNLINK`, `RMDIR`, and `LINK`
capability bits and dispatch slots, and it keeps the ordinary binding's
`LOOKUP`. It also wires `RENAME`, `ATOMIC-RENAME`, `CROSSDIR-RENAME`, and
`RENAME-REPLACE` to the rename described above, and it advertises the
focused-qualified linked-regular `SETATTR` slot described above. Its write
slot is the general regular-file write described above, and `VFS-WRITE-EXACT`
composes its transactions. Both bindings retain `VFS-CAP-SPARSE` for sparse
mappings and zero-filled hole reads; the staged write leaves holes when it
writes past EOF and fills them when it writes into them. `VOL-WRITE` and
`VOL-FLUSH` remain confined to authenticated recovery and the staged
transaction lifecycle.

### LOOKUP

Both bindings install `_EXT4-LOOKUP` in operation slot 3 and advertise
`VFS-CAP-LOOKUP`. The VFS calls it for a name its dentry cache lacks: while it
resolves a path, and before CREATE, MKDIR, LINK, and RENAME check a new name.
A lookup reads only the blocks the name can be in, loads only the named
child's inode, and caches only that child, so it never marks the folder as
having its children loaded. The folder's other names stay on media. A folder
of any size therefore resolves its names, opens and reads them, takes new
names by CREATE and RENAME, and loses them by UNLINK while the cache holds
only the names in use. Listing it through `READDIR` caches every name, in a
name pool that grows from the mount arena.

LOOKUP and READDIR are one reader. `_EXT4-DD-AUTH-INODE` authenticates the
directory's inode, which `_EXT4-DD-LOAD-LOGICAL` checks again before it reads
each block through the directory's map. `_EXT4-VALIDATE-DIR-BLOCK` validates
each block's checksum tail and complete dirent chain: record lengths and
bounds, name lengths, inode numbers, name bytes, and file types. The scan then
requires `.` to name the directory and `..` its parent, once each. READDIR
admits every other live record; LOOKUP takes the first record whose name is
the one sought and admits it once the walk of its block is complete, so a
refused lookup publishes nothing. A record is admitted as a child: its inode is
loaded, must have the type the record's file type gives, when it gives one,
and supplies the dentry's generation and the vnode's metadata through
`VFS-CACHE-DENTRY` and `_EXT4-PUBLISH-STAGED`.

- In a linear folder the lookup reads the blocks in order and stops after the
  block that holds the name. A folder read to its end without the name must
  have held `.` and `..`, as READDIR requires, and answers `VFS-E-NOENT`.
- In an HTree folder `_EXT4-DD-AUTH-HTREE-ROOT` validates the root, the name
  is hashed with half-MD4 under the superblock's signed or unsigned flag, and
  `_EXT4-DD-SELECT-ROUTE` routes it as the kernel's `dx_probe` does: the last
  entry whose hash, continuation bit included, is at most the name's. At level
  one the routed index node is read and validated as a node, and its entries
  route the name the same way to one leaf. When that leaf lacks the name, the
  lookup moves on as `ext4_htree_next_block` does: to the next entry of the
  node, or past a node's last entry to the root's next entry and the first
  entry of the node it names, while that entry's hash without the
  continuation bit is the name's. A run of equal hashes is followed into every
  leaf it spans, and a miss reads no leaf beyond it.

A lookup authenticates the blocks it reads and no others, so a damaged leaf or
node refuses only the lookups routed through it. Checks that need every block
belong to READDIR and the writer's walk: that a level-zero root names each
other block once, and that a level-one root, its nodes, and their entries
account for the whole folder. Like READDIR, the lookup accepts an unused
record that still carries a name length or file type, which the writer's walk
refuses. An HTree lookup hashes under the superblock's signed or unsigned hash
flag, which `mke2fs` and the kernel's first read-write mount set; an image
that sets neither refuses a lookup in an indexed folder with the write-policy
detail, while READDIR still lists it.

With `LOOKUP` advertised, the VFS evicts clean ext4 dentries once its cache
passes the high-water mark. An evicted name returns through LOOKUP with its
inode number and generation, and a folder that loses a child loses its
completeness flag, so its next listing reads it again. An open descriptor keeps
its dentry, file or directory.

Qualification builds its folders with pinned e2fsprogs 1.47.4: `debugfs`
writes them and `e2fsck -fyD` indexes the large ones. One mount resolves a
name and an absent name in a one-block linear folder, in the last of three
linear blocks, and in folders indexed at level zero and at level one, each
lookup adding one dentry and leaving its folder unloaded, in 31.5 million
steps. In the read-side image, `collision-083826` is found in the leaf after
the one its hash routes to. In a level-one tree whose root entry for the
second index node is given the lowest hash of that node's first leaf with the
continuation bit, the name with that hash is found past the first node's last
entry. A changed byte in one leaf, and a changed checksum in one index node,
refuse only the lookups routed through them. A listed folder whose names are
evicted lists every name again, and an open directory survives the eviction.
A folder of 330 200-byte names, whose cache entries take 71,280 bytes, more
than the 64 KiB the name pool once reserved, lists in full in 82.7 million
cycles. A folder of 2,000 names, all hard links of one file, lists in full in
218.3 million cycles, about 109,000 a name, since the VFS cache finds each
name's siblings and the shared vnode through its indexes. The same folder
takes a read, a CREATE, a RENAME into it, and an UNLINK in one staged mount of
338.5 million steps, and its result passes `e2fsck` and reads back through a
fresh mount.

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
2. close regular-file writes: bounded overwrite, hole fill, aligned growth,
   exact-write composition, allocation geometry, root composition, and
   depth-one leaf editing and splitting landed first (through `1f4e0ea`), and
   the general write described above has since replaced every one of those
   bounded paths with one routine for any span, any extent depth, multi-block
   transactions, and lazily initialized groups;
3. (merged into item 2);
4. build shared inode allocation and directory insertion, then expose the
   first bounded `CREATE` slice (completed in the current worktree); the
   shared directory insert described above has since replaced the bounded
   CREATE, MKDIR, and LINK paths with one insert that grows its parent;
5. retain general single-transaction `TRUNCATE`, which has replaced the
   same-retained-block shrink and the inline depth-zero release, and close the
   first nonfinal regular-
   file `UNLINK` slice plus atomic closed last-link removal of an already-empty,
   allocation-free regular inode, including descriptor-retained nonfinal
   unlink and orphan-backed closed/open final-link lifetime handling (completed
   in the current worktree);
6. retain `MKDIR` and `RMDIR`, including `.`/`..`, parent/child link
   counts, inode/block allocation and release, and directory accounting
   (completed in the current worktree);
7. retain hard `LINK` and `RENAME` (completed in the current worktree); the
   shared directory insert and removal have since replaced the bounded RENAME
   forms with one rename that moves regular files and directories within or
   across parents, over a regular-file or empty-directory victim;
8. retain HTree insertion: linear-to-HTree conversion, full-leaf splitting,
   and root growth landed first as bounded CREATE paths with representative
   committed replay, and the shared directory insert now converts, splits
   leaves, grows the root, and splits level-one nodes for CREATE, MKDIR, and
   LINK alike; the shared directory removal takes any record out of the same
   parents for UNLINK's three lifetimes and RMDIR's removal of any empty
   directory through the orphan file; and RENAME composes the two for every
   parent they admit. Together they draft-close the namespace/deletion
   vertical; next
   retain the indexed-parent TRUNCATE composition and the focused-qualified
   scalar SETATTR slice, then admit xattr
   mutation; and
9. perform the final profile closure audit across every profile-admitted
   operation and recovery state.

Each remaining family closes its gaps the way the write did: when it next
needs a case its bounded paths lack, one general routine replaces those paths
and the special cases are deleted. Extent-tree editing, truncation, file
deletion, directory insertion, directory removal, and rename are general
routines.

Each landing may move only forward: it must keep all prior qualified behavior,
remain crash-closed, and advertise exactly the capabilities it has earned. An
internal slice is useful implementation evidence but is not public capability;
an explicitly staged capability is public ABI but is still not complete profile
conformance.

## Possible safe mode

Some of the driver's checks can fail only when the driver has a bug, when the
device hands back something other than what it was last given, or when
another writer changes the volume during the mount. They include rereads that
confirm a write landed, re-derivations of after-images the driver built
itself, and cross-checks of a mapped range against the block bitmaps and
static metadata once the mount has proved block ownership. Desk draws the same
line in its check mode (`akashic/tui/check-mode.f`): checks of new data, of
state and of fit run in every mode, while checks that can find only a bug run
when memory changes hands, and on every frame in safe mode.

The driver could follow it. Its normal mode would keep every check of what it
reads from media, the journal's order and every crash-safety rule, and a safe
mode would add the checks above. A caller would choose the mode for each
mount, as Desk takes its own from the settings disk, and a failed check would
turn safe mode on for the rest of the session. For now every check runs on
every mount. Much of the time a normal mode would save goes to work that
repeats an earlier check, rereads blocks nothing has written since, or
recomputes inputs that stay fixed for the whole mount, and that work can go
from every mount with no loss of detection. The choice comes back once those
repeats are gone and the cost of the checks that remain is measured.

## Deliberate remaining limits

The current explicitly staged write surface is not completion of the writable
profile. Its general regular-file write is production-closed on 1 KiB/256-byte-
inode geometry for extent-mapped files at every depth the format allows; exact
writes compose independently durable transactions, and no broader geometry or
operation inherits that status.
`EXT4-STAGED-WRITE-OPS` adds staged `MOUNT`, `WRITE`, `CREATE`, `MKDIR`, and
`LINK` through the shared directory insert, general `TRUNCATE`, and `UNLINK`
and `RMDIR` through the shared directory removal dispatch slots to its copy of
the ordinary table. It also
installs staged `RELEASE` and `SYNCFS` lifetime handling, and `RENAME`
through the shared insert and removal, and it advertises `VFS-CAP-RENAME`,
`VFS-CAP-ATOMIC-RENAME`, `VFS-CAP-CROSSDIR-RENAME`, and
`VFS-CAP-RENAME-REPLACE`. The staged worktree also installs `_EXT4-SETATTR`
and advertises `VFS-CAP-SETATTR` for the focused-qualified linked-regular scalar
slice. The ordinary binding remains `VFS-BF-READ-ONLY` and advertises none of
these mutations. Neither binding yet advertises `SYMLINK`, `SETXATTR`, or
`REMOVEXATTR`. Each later capability, SETATTR expansion, or RENAME expansion
still needs its own bounded credit/chunking contract, reachable-state recovery
closure, namespace/cache behavior where applicable, and interoperability plus
crash qualification. Full profile completion additionally needs general block
and inode allocation, extent and legacy-map growth and shrink, directory-entry
mutation, inode/link/time/accounting updates, xattr mutation, broader per-record
orphan closure, and the final compositional release matrix.

The staged binding's production-closed inventory contains the following
concrete durable paths. The general write stages each transaction's mapped
blocks as ordered full-block images and its allocated runs as zero-backed
ordered blocks, edits the extent tree at any depth, updates every touched
bitmap, group, and super free-block account plus `i_blocks`, `i_size`, and the
trusted-clock times, and carries as many blocks as the bound profile holds.
TRUNCATE releases every block past the new EOF at any extent depth in one
transaction, staging the new EOF block's zeroed tail as a journaled after-image,
and a growth zeroes the old EOF block's tail as ordered data; it preserves links
and a qualified external xattr. UNLINK and RMDIR take any record out of any
parent the insert admits, a leaf's first record included, and change no other
block of the parent. Nonfinal regular-file UNLINK stages two or three homes to
lower one link and update the target's and parent's times, without allocation
or orphan state; open descriptors may retain the removed dentry, and the final
close reclaims that cache object without an ext4 transaction because another
persistent link keeps the inode live. A last link of an empty file with no open
descriptor is freed in at most six homes: its record, the parent's times, the
zeroed inode, its bitmap bit, and the descriptor and primary-super free-inode
counts. Any other last link, and every empty directory RMDIR removes, enters
the modern orphan file in the removal's own transaction, which retains its
allocation while publishing no links, the times, the record's removal, the
orphan record, and `ORPHAN_PRESENT`. Closed targets drain immediately through
release passes and the deletion; open targets remain readable until the last
staged `RELEASE`, which reauthenticates and drains that same inode and
generation, and staged `SYNCFS` returns `BUSY` while the record is live. A
directory's deletion lowers its group's `used_dirs` count, and its blocks
release without revokes. LINK
into slack uses exact deduplicated `2/0/0` or `3/0/0` credit to add one
checksummed record, increment and restamp the target inode, and restamp the
parent inode, and grows the parent as the other inserts do when its block is
full. RENAME takes the source's record out as the removal does and places the
new name as the insert does, growing the new parent when its block is full,
or hands a victim's record to the source. A directory that moves to another
parent gets a new `..` in its block 0, and the parents' link counts change as
`ext4_rename` changes them. The rename restamps the source's change time and
each parent's modification and change times, preserves the source's links,
allocation, data, map, and xattrs, and takes a victim's link in the same
transaction; a final victim, and every directory victim, enters the orphan
file there under the sealed rename form and drains as a final unlink's
target does. Linked-regular scalar SETATTR persists any nonempty subset
of `MODE`, `UID`, `GID`, `ATIME`, `MTIME`, and `CTIME` through one checksummed
inode-table after-image under exact `1/0/0`, without a clock sample, data,
revoke, allocation, or orphan mutation. The other clock-derived mutation paths
update `mtime`/`ctime`; the general write also publishes `VN.BLOCKS`, the
free-block count, and the size. Exact writes compose its transactions: every
callback is independently durable, a later failure preserves earlier
checkpointed progress, and no multi-block atomicity is implied. The initial TRUNCATE slice adds shared-vnode
shrink publication, complete retained-tail zeroing, exact two-home commit,
W7 old-EOF rollback, W17 committed two-home replay, stable remount, and pinned
`debugfs`/`e2fsck` acceptance. Releasing truncation adds count-zero
canonicalization of inline depth-zero roots, release of sparse, saturated, and
hole-only roots, a 340-extent depth-two tree pruned and collapsed both in one
transaction and across several behind a modern orphan record, a final
cleanup of its own that zeroes a partial EOF block's tail, and recovery after
a tear in each transaction of that sequence: the insertion, a release pass,
the final cleanup, and the retirement of `ORPHAN_PRESENT`, which keeps the
writer active. The original singleton fixture supplies clean/stable
external-tool acceptance and precommit descriptor rollback. Empty closed final-link UNLINK adds a clean same-mount
CREATE/remove cycle that restores
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
RMDIR's qualification covers the public removal of the directory MKDIR made
and its drain, directories of every admitted shape, a live name the cache does
not show, refusals that write nothing, hostile aliases of the parent's and
child's blocks, a descriptor tear, a torn checkpoint home that replays and
drains, a crash before the drain that mount recovery completes, and an open
directory drained on its last close. Pinned external tools and the
write-free stable remount accept the result. Bounded hard LINK adds exact shared-home and
distinct-parent transaction topologies, shared-vnode and open-FD publication,
four zero-write refusal cases, W7 provisional rollback, W17 committed
two-home replay, pinned external-tool acceptance, and stable remounts across
both clean namespace topologies. At that LINK closure, fresh source mode
measured 1,140,381,589 ext4-load steps across 2,962 packed lines under the
then-approved 1.15-billion-step watchdog, leaving 9,618,411 steps of headroom;
the descriptor journey measured 4,230,599 steps. RENAME's qualification,
described in its section, covers renames within and across parents with and
without growth, directory moves into a level-one parent with two index nodes,
regular-file and directory victims, checkpoint tears of a split, a directory
move, and a sealed directory-victim rename, zero-write refusals, and the
public cases' exact homes and tears. Qualified singleton-modern-
orphan final-link lifetime closure now covers closed and descriptor-retained
targets, including last-close failure recovery. The shared directory insert
then replaced the bounded CREATE, MKDIR, and LINK slices, with their
conversion, depth-zero leaf split, and singleton root growth, by one insert
that grows a one-block linear or level-zero or level-one HTree parent through
the general allocator and extent-tree insertion.
Broader concurrent orphan unions, unwritten conversion, 2/4 KiB and
128-byte-inode allocation, multi-block atomicity across callbacks, and other
namespace mutation remain later capabilities.

The remaining boundaries are the final-profile closure inventory, not an
ordered list of prerequisites for retaining the qualified write surface:

- POSIX ACL xattrs are returned as raw bytes, but generic permission
  enforcement is not claimed;
- read and recovery retain the authenticated 1/2/4 KiB and 128/256-byte-inode
  forms, while staged mutation is currently qualified on 1 KiB/256-byte-inode
  geometry. The general write edits extent trees through the format's five
  levels below the inode and allocates from initialized and `BLOCK_UNINIT`
  groups with wraparound;
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
  foundations. The staged binding composes them with the general write's
  ordered full-block images, run allocation accounting, extent-tree nodes,
  and timed checksummed inode after-image. All
  operations run only after
  the mount's block-ownership proof and their own mutation-range checks. Broader mutation remains
  gated operation by operation.
  Transaction-aware metadata acquisition, checksum-safe typed
  orphan-inode replacement, free-only physical-block accounting, release
  passes that free a linked record's blocks past EOF or an unlinked record's
  whole map, at any extent depth or for any legacy block map, inode
  allocation release, target-record scrubbing, exact credit measurement,
  modern-slot removal, legacy-head advancement, and operation/protocol-specific
  `FINAL`/`MORE` certificates now compose each record's sealed transactions
  for either orphan mechanism. Production mount
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
  geometry, checked arithmetic, and caller-arena storage, with no separate
  fixed constant. It truncates linked regular files and deletes unlinked ones
  whatever their size and map, and it refuses journal-data files, unlinked
  inodes of other types, inconsistent or out-of-range shared external-xattr
  ownership, and inline or external xattr value inodes; link-count and
  malformed-chain repair stay with e2fsck. Cleanup releases allocation
  authority and leaves freed blocks' contents on the media, so it provides no
  secure deletion or data-block erasure;
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
  image remounts byte-identically with zero I/O in 67,492,163 steps. A hostile
  valid external-xattr block also mapped as orphan-file preallocation is
  rejected as `EXT4-D-DATA-MAP` by the mount's ownership proof. These are
  harness measurements, not driver capacities.
  Mount-level refusal covers a nonzero physical high word, unauthorized or
  malformed external-xattr release shapes, orphan-storage aliasing, a clear
  one-block data bit, and a two-block extent whose second allocation bit is
  clear.
  Checksum-valid allocated live-inode fixtures additionally prove that both a
  data extent and an external-xattr pointer aliasing the candidate are
  rejected as `EXT4-D-DATA-MAP` by the mount's ownership proof before writer
  allocation or media mutation, as is a three-block candidate whose middle
  block alone is named by a live inode. Both orphan protocols are qualified;
  the same-binding retry returns the same refusal.
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
  Deletion of a data-bearing unlinked record follows the general release.
  Release passes free the map from its end, and the pass that frees the rest
  folds the deletion: its seal binds the pass's freed runs as the `RELEASED`
  vector, the pass credit, every revoke inside those runs with a released
  xattr block's last, and a target entry count equal to the run count.
  Inspection tests seal that vector for separated inline extents mixing
  initialized and unwritten entries, four external extent leaves with their
  revokes in release order, all twelve legacy direct slots beside a unique
  external xattr, and a single-indirect map with its pointer block; beside a
  shared xattr a pass keeps its credit as the writer's whole capacity. A
  certificate whose block count, data-map kind, run overlap or run length
  changes fails checkpoint authority, and a shifted run passes authority and
  fails staged verification. Mount recovery deletes legacy maps of any shape:
  holes in the direct pointers, a double-indirect tree with no single root,
  triple trees with data in several branches, and every branch at once across
  186 fragmented data blocks, more than one pass frees, recorded in the orphan
  file or on the superblock's chain. Each ends on a volume pinned e2fsprogs
  1.47.4 finds clean, with the inode record zero and every released block
  free. A duplicated data pointer, a data pointer that names a pointer block,
  a duplicated child, an unallocated child and a misstated `i_blocks` each
  refuse the mount as `EXT4-D-DATA-MAP` corruption before any write. A linked
  record whose legacy map extends past EOF truncates under both protocols,
  keeping the blocks before EOF and zeroing the bytes past it. The staged
  unlink of the 340-extent depth-two file frees it through release passes
  under a sixteen-home, four-revoke profile, closed or held open until its
  last close, and five trace-derived tears of a 120-extent unlink, at the
  unlink's descriptor and inode home, a pass's inode home, the deletion's
  orphan home and the `ORPHAN_PRESENT` clear, recover on remount to the whole
  file or to a clean volume without it. The 1 KiB cross-group fixture still
  coalesces separate data- and inode-group descriptors into one primary GDT
  home, and the boundary fixture proves that one released run may itself
  cross two groups while both data descriptors and the inode descriptor
  coalesce into that home. The per-shape production journeys and their crash
  fences, from the empty and one-block baselines through legacy direct,
  indirect and triple-root maps, run through the same passes.
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
  legacy-format linked map truncates through release passes, as described
  above, and this focused empty-map evidence makes no production,
  crash-recovery, or e2fsck claim. A
  later four-extent unlinked record whose fourth range is also owned by a live
  inode is refused by the mount's ownership proof before any write or flush. Structurally valid
  post-seal total-count, protocol-split, and `MORE`/`FINAL` substitutions all
  fault at checkpoint preflight with zero home writes. A linked-owner matrix
  places a live-inode alias in the later selected record: a two-entry modern
  root and a four-entry legacy root both fail the mount's ownership proof as
  `EXT4-D-DATA-MAP` before qualification, leave the earlier safe record
  untouched, perform no write or flush, and preserve the caller arena on
  retry. Modern-only and legacy-only two-record
  deletion fixtures give unlinked head 18 respectively two and four separated
  initialized/unwritten extents before empty successor 21. Exact stage/abort
  qualification pins the `MODERN_DATA_DELETE_MORE` and
  `LEGACY_DATA_DELETE_MORE` certificates of the pass that folds each deletion,
  with the pass credit, protocol locators, pre-union counts, the target's
  generation, home, offset and entry count, and the released runs. Full
  production mounts restore the canonical block
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
  exact one-home already-truncated sealing with zero target entries, the
  original one-range fixture's cleanup sealed as one four-home transaction
  within the release pass's capacity, post-seal mutation refusal, and abort
  scrubbing. Its controlled crash matrix covers 14 write
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
