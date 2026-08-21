# ext4 recovery refactor plan

This document fixes the refactor sequence that follows the bounded depth-zero
HTree full-leaf CREATE milestone at commit `abb3f94`. The first tranches
extract the small general libraries already justified by independent Akashic
consumers. The ext4 monolith is then split along explicit semantic boundaries
before operation state and transaction-home planning are consolidated inside
those boundaries.
No refactor stage may change the filesystem formats admitted by the driver or
weaken any authority, recovery, transaction, or persistence guarantee already
qualified by the production source path.

The plan is intentionally staged. Each stage must leave one production path,
not a permanent compatibility path beside its replacement. A later stage may
be reordered only when a newly discovered dependency makes the stated order
incorrect; that change belongs in this document before the implementation is
redirected.

## Implementation ledger

- Stage 1 is complete through `78bcc71`. `uint-range.f` owns validated scalar
  geometry; memory-span retains its established API and layout; MP64FS,
  `binimg`, and ext4 now delegate their duplicated overlap, membership, and
  range-construction proofs through the shared algebra while preserving typed
  fail-closed policy at their boundaries.
- Stage 2 is complete for the identified Akashic MP64FS and ext4 consumer
  families. The checked `bitset.f` contract landed at `4557527` and now owns
  logical bitmap admission and range mutation for MP64FS's allocation and
  pending-free views.
  MP64FS retains contiguous first-fit search, pending-mask application, and
  durability sequencing. The ext4 migration now uses exact logical popcount
  for block accounting and bounded shared queries for free-block candidate
  selection, and its singleton block-allocation family uses checked query and
  mutation views. Block-range release now likewise delegates its exact-group
  raw/effective allocation proofs and private after-image clear while ext4
  retains authentication, counters, checksums, and transactional publication.
  Foundational block point/range allocation reads also use the canonical exact
  group bound rather than direct byte/shift scans. Durable-delete semantic
  verification now reconstructs its block and inode bitmap after-images with
  the same checked logical views while retaining full ext4 CRC/home comparison.
  The inode-release builder now also delegates its exact-group raw/retained
  singleton checks and private clear without moving inode accounting or
  transaction policy. Staged-delete, checkpoint, and final-release admission
  now use exact checked singleton queries as well, removing ext4's last manual
  all-set reader. Checkpoint release-range verification likewise uses exact
  checked all-clear queries. The XC inode-allocation family now delegates its
  exact-group popcount, reserved-aware search, raw/effective singleton checks,
  and private bit set, eliminating ext4's generic range bridge and its shared
  scratch state. The ordinary/bootstrap inode loader and recovery's inode-8
  allocation witness now share the canonical exact group-inode count and
  checked singleton query. The reverse-owner scan now also walks each
  authenticated inode bitmap through checked exact-group singleton queries
  while retaining its filesystem-specific ascending iteration and owner
  policy. Staged inode-bitmap verification now reconstructs its exact full-home
  delta by applying a checked singleton clear to the transient raw cache, then
  compares every physical byte. Filesystem checksum, accounting, iteration,
  padding-authentication, and durability policy remain with their owners.
- Stage 3 is complete for the acyclic mechanism boundaries that can be
  extracted without adding mutable cross-component results or late-bound
  callbacks. The cold ext4 source harness derives the driver's
  dependency-ordered closure and removes the VFS, CRC, and bitset foundation
  already present in earlier measured stages. The first physical component,
  `ext4/vfs-ext4-admission.f`, now owns the on-disk profile and base binding
  context layout, checked I/O and CRC adapter, probe helpers, checked
  arithmetic, and primary-super admission. Facade-owned operation records may
  use opaque pointer/span slots in that base layout without moving their schema
  or policy into admission. `ext4/vfs-ext4-descriptor.f` now owns authenticated
  group-descriptor location, shared CRC verification/restamping, pointer/span,
  flag, and counter admission. Its loader and the group-0 recovery candidate
  delegate to the same predicate, eliminating their duplicate CRC algebra.
  `ext4/vfs-ext4-bitmap.f` now owns canonical short-group geometry,
  nominal-format bitmap CRCs, authenticated bitmap loading, and the raw
  exact-bit allocation predicate. All 22 scratch cells are private after
  making the CRC calculators stack-direct, and mount validation delegates its
  duplicate CRC tails without moving allocation-owner policy.
  `ext4/vfs-ext4-inode.f` owns stack-only `i_blocks` decode/encode, bounded
  `i_block`-tail checks, canonical special-device decoding, signed timestamp
  loading, inode-checksum restamping, and mtime/ctime encoding. All 34 scratch
  cells are private; inode media lookup, checksum verification, and the
  success-only IR identity/locator results remain facade-local until a concrete
  later feature needs that seam.
  `ext4/vfs-ext4-xattr.f` owns external-xattr block header admission, shared
  physical-location-bound CRC calculation, authenticated loading, and
  checksum restamping. Its six scratch cells are private and it exports no
  mutable result: authenticated bytes reside in the caller-owned context
  `C.BLOCK` only after a successful load. Entry parsing, allocation,
  reference-count, transaction, and recovery policy remain in the facade.
  `ext4/vfs-ext4-orphan.f` owns the orphan-file block tail magic and the checked
  checksum predicate and restamper. All seven scratch cells are private and
  the unit exports no mutable result. The facade reader delegates its duplicate
  checksum tail while retaining inode preparation, mapping, physical I/O, and
  all `_EXT4-OV-*` operation state.
  `ext4/vfs-ext4-backups.f` owns sparse-super copy authority, immutable-super
  comparison, exact journal-backup tuples, and backup-GDT location checks; all
  13 of its scratch cells are private.
  `ext4/vfs-ext4-dirhash.f` owns directory-name byte admission, the seeded
  half-MD4 engine, and checked mounted hash policy; all 21 of its scratch
  objects are private, and its unused rejected-version constant is gone.
  `ext4/vfs-ext4-dirent.f` owns directory-entry type decoding, full linear-block
  validation, and checksum restamping. Its three services keep all 14 scratch
  cells private after removal of the dead validator-tail cell; scan, inode,
  cache, rollback, transaction, and durability policy remain in the facade.
  `ext4/vfs-ext4-jbd2-codec.f` owns raw big-endian access and the shared JBD2
  block, superblock, commit, and tag checksum validators and encoders. Tag
  validation takes its sequence and context explicitly, all 11 codec scratch
  cells are private, and the module adds no mutable cross-component result
  surface.
  `ext4/vfs-ext4-jbd2-map.f` owns reusable arena-backed map geometry,
  physical-home uniqueness reservation during construction, completed-map
  membership, mapped journal-block I/O, and logical ring stepping. Its 16
  scratch cells are private; snapshot construction and all recovery-authority,
  scan, transaction, and durability policy remain in the facade.
  `ext4/vfs-ext4-jbd2-revoke.f` owns recovery revoke-table geometry,
  caller-arena allocation and reuse, bounded insertion and lookup, and modular
  transaction ordering. Its ten scratch cells are private; the facade retains
  record parsing/checksums, `REVOKE-READY` publication, replay authority,
  scrubbing, and durability.
  `vfs-ext4.f` remains the only public facade and begins with allocation-owner
  and initialized-bitmap policy. The aggregate source stage now loads
  `(admission, descriptor, bitmap, inode, xattr, orphan, backups, dirhash,
  dirent, jbd2-codec, jbd2-map, jbd2-revoke, facade)` in production order
  rather than relying on a handwritten concatenation list.
  Commit `979d145` performs the final organizational nesting of those private
  sources and their documentation under `utils/fs/drivers/ext4/`; it preserves
  the public facade, dependency order, provider identities, and production
  source closure.
  Four checked-I/O session/evidence cells and four success-only descriptor
  parser-result cells remain documented cross-component surfaces. Five inode-
  lookup identity/locator cells remain facade-local operation-lifetime state;
  bitmap admission, inode formatting, external-xattr and orphan-block
  handling, backups, dirhash, dirent, and the JBD2 codec, map, and revoke
  services add none. Those I/O, descriptor, and inode surfaces are outside the
  bounded Stage 4 pilot and remain facade-local until a concrete feature needs
  their seam. The remaining extent/map, xattr-entry, inode-media, orphan-
  planning, and JBD2 recovery/transaction families likewise carry mutable
  operation state, late policy callbacks, or success results across their
  prospective seams. Stage 3 does not turn those couplings into module APIs
  merely to create more files.
- Stage 4 is complete at the CREATE/HTree context checkpoint. The 44 selected
  ambient objects are gone; the facade now owns one 3,664-byte binding record
  containing 39 cells, a 24-byte hash authority, three 1,024-byte block
  snapshots, and one 256-byte inode snapshot. Admission carries only its
  opaque pointer/span. Exact allocated-prefix ownership, fresh-allocation
  rollback, retained-mount reuse, explicit plan threading, sealed topology
  authority, branch-specific comparison, and complete return-path scrubbing
  are now one production path. The shared CREATE/MKDIR/LINK insertion path
  consumed the Stage 4 record without adding indexed MKDIR/LINK or, at that
  checkpoint, Stage 5 home planning.
  Relative to the Stage 3 source shape at `131bf83`, the 13-unit production
  closure grew from 29,965 to 30,203 physical lines, 1,153,521 to 1,163,093
  raw bytes, 26,964 to 27,163 loader-executable lines, 3,719 to 3,745 packed
  lines, and 873,712 to 879,851 packed bytes. This is +238 physical lines,
  +9,572 raw bytes, +199 executable lines, +26 packed lines, and +6,139 packed
  bytes. A source-mode cold build passed at 1,029,626,802 of 1,600,000,000
  steps, and the sequential focused gate passed two-record isolation,
  poisoned-record reuse/refusal cleanup, all four admitted CREATE shapes, and
  canonical MKDIR and LINK. The initial run found an overbroad whole-VFS-arena
  oracle and a full-leaf split guard reached only after all 54 mutation checks;
  the plan-specific oracle and narrow 1.50-billion journey bound then passed,
  with the split completing in 1,453,284,730 steps.
- Stage 5 is complete at the namespace-insertion home-plan checkpoint. A
  488-byte tail extends the Stage 4 record to 4,152 bytes with one count cell
  and 20 enum-derived `{ role, journal kind, home }` entries. The entry span is
  derived from the complete semantic role universe, not a fixed maximum for a
  current topology. Cold planning inserts the vector, and seal fully audits it;
  dry/live planning rebinds every expected role, kind, home, and exact
  role count; preflight and writer construction derive per-kind first-seen
  credits; and the final staging boundary reconciles first-seen home order
  against the transaction tables. The six private XC collector artifacts and
  its collector-derived credit path are gone. CREATE's four admitted shapes,
  canonical MKDIR, and LINK's two- and three-distinct-home cases passed the
  sequential focused gate without changing their checked-in journey caps.
  Relative to Stage 4, the 13-unit closure grew from 30,203 to 30,616 physical
  lines, 1,163,093 to 1,177,113 raw bytes, 27,163 to 27,537 executable lines,
  3,745 to 3,788 packed lines, and 879,851 to 889,803 packed bytes. This is
  +413 physical lines, +14,020 raw bytes, +374 executable lines, +43 packed
  lines, and +9,952 packed bytes even after collector deletion. The cold source
  build passed at 1,049,876,551 of 1,600,000,000 steps, 20,249,749 steps above
  Stage 4. Stage 5 centralizes authorization; it does not claim a LOC payback.
- The root-growth probe was the first direct consumer of both checkpoints. It
  extends the record by six cells—one explicit probe admission, one derived
  root-growing shape flag, and the new DX node's home/group/bitmap/GDT tuple—
  and extends the enum-sized home tail by three roles for the node image,
  allocation bitmap, and descriptor. It added no snapshot, topology maximum,
  ambient home collector, or independent credit counter. At that checkpoint
  the record was 4,272 bytes: a 3,712-byte evidence body and a 560-byte,
  23-role home tail. A saturated 123-entry root with a full selected leaf plans
  the new DX node at logical EOF and the split leaf at EOF+1, rebinds both exact
  candidates after seal, and composes the two extent-map/allocation edits. The
  external-map same-group probe has 14 semantic roles and 11 first-seen homes.
  The original probe was deliberately nonpublishing: ordinary CREATE left
  probe admission clear and retained the old early `VFS-E-NOSPC`; the probe
  dry-staged then aborted before writer activation. The later live
  qualification activates, emits, checkpoints, and externally validates the
  exact 11-home transition. Stage 6 then added two locator cells
  and one operation-owned DX-node snapshot, making the record 5,312 bytes with
  a 4,752-byte evidence body at that checkpoint. An ordinary staged CREATE on
  a fresh mount of that produced singleton depth-one tree now authenticates
  all 124 leaves and updates one slack leaf through the unchanged exact six-home
  transaction. The production CREATE wrapper now supplies that root-growth
  admission and passes the same exact public journey. A committed W28 tear in
  the new DX-node home leaves the first three checkpoint homes landed, replays
  all 11 afterimages on a fresh mount, passes the external checker, and is
  followed by a write-free byte-identical remount. The fault journey completed
  in 1,875,529,452 of 2,400,000,000 steps, recovery in 279,355,135 of
  1,200,000,000, and the stable mount in 149,036,061 of 1,200,000,000. The
  exact ten-versus-eleven-home profile refusal then completed in 346,405,702 of
  1,600,000,000 steps; the unrelated-inode root-owner refusal completed in
  564,354,763 of 1,600,000,000. Both observed zero writes and flushes and an
  identical pre/post image SHA-256. This closed the focused root-growth vertical
  and handed off to the indexed LINK/MKDIR directory boundary. The original
  exact source-mode qualification
  passed with the 13-unit ext4 closure loading in 1,073,526,553 of
  1,600,000,000 steps across 3,842 packed
  lines. Its saturated-root journey completed in 1,545,877,690 of
  1,600,000,000 steps while the harness observed zero storage writes and zero
  flushes; it checked the complete seven-entry extent vector, checksum
  idempotence of every staged structural image, and immediate cache, writer,
  plan, private-buffer, and owner-range cleanup after abort.

## Baseline and objective

The frozen semantic comparison point is the clean `ext4-recovery` tree at
`abb3f9462d379b0adb2f09d1009831dd2f85afdb`. Documentation and refactor commits
advance `HEAD`, but that commit remains the behavior, ordering, persistent-byte,
and crash comparison baseline. It includes bounded depth-zero HTree full-leaf
CREATE and its recovery qualification. Stage 6 has now crossed positive HTree
root-depth activation, representative committed replay, stable-remount
boundaries, and the first existing-slack indexed LINK and MKDIR happy-path
slices. Exact
one-short credit and unrelated-owner refusal close the focused root-growth
vertical. Both namespace slices admit only existing slack in depth-zero and
singleton depth-one parents without parent growth. LINK and MKDIR now have
happy-path evidence at both depths, and one combined full-selected-leaf test
proves that both operations return `VFS-E-NOSPC` without writes, flushes, or
cache/accounting drift. This closes the namespace-insertion draft boundary
compositionally: the operations add no journal role or recovery branch, so the
existing indexed selected-leaf/root-growth replay evidence and the established
operation-specific linear LINK/MKDIR recovery matrices remain authoritative.
Refactoring must not silently broaden either operation to leaf splitting or
growth, broader map shapes, or another previously gated filesystem behavior.

The objective is to establish one authoritative implementation for each of
these recurring mechanisms:

- validated half-open integer-range algebra;
- checked LSB0 bitmap operations over caller-described storage;
- the production source closure and its semantic module boundaries;
- the CREATE/HTree evidence and namespace-operation plan lifetimes; and
- ordered, role-aware transaction-home preplanning.

Success is fewer independent implementations of the same invariant, not fewer
source lines. No stage introduces a generic authority framework merely to give
different ext4 proofs a common vocabulary.

The existing JBD2 transaction object remains the transaction engine. It
already owns metadata/data/revoke acquisition, same-home composition, credit,
emission, and checkpoint. The missing seam is the ordered certificate prepared
by callers before acquisition; the refactor must not create a second journal
or transaction representation.

## Invariants that do not move

Every migration preserves the following behavior exactly unless a later
feature change names and qualifies a new contract:

- Home identity is deduplicated while first insertion order is retained.
  Staging, journal emission, and checkpoint order must not be changed by
  sorting or by an implementation-dependent traversal.
- A role has one exact home. Two roles may intentionally alias one home, but a
  role may not silently change homes and a home may not cross metadata, data,
  and revoke kinds.
- Credit is the exact number of distinct homes in each journal kind. Capacity
  is supplied by the operation's caller-owned storage; it is not a global
  design limit.
- Measurement is media-read-only and leaves transaction state unchanged. No
  partially built plan may authorize a write; staging requires a completely
  authenticated sealed plan.
- Cold, dry, and live passes continue to reauthenticate mutable filesystem
  state at their existing boundaries. A cached descriptor is not authority to
  skip the live check.
- Malformed or wrapping range and bitmap geometry fails closed. An invalid
  query must not be represented as an ordinary non-overlap or clear bit.
- Bitmap range mutation validates the complete range before changing the first
  byte. Popcount observes exactly the logical bit count and neither counts nor
  normalizes high padding bits in the final byte.
- Filesystem-format concerns stay in the driver: block/inode geometry,
  checksums, dirty state, free-space accounting, allocation policy, and JBD2
  semantics are not generic utility responsibilities.
- Production qualification continues through the cold source loader. A warm
  cache or compiled shard is not evidence for source loading or source/runtime
  equivalence.

## Stage 1: extract scalar range algebra

Add stateless validated half-open range algebra for a start plus a
nonnegative cell-sized count. Validity and overlap must be distinguishable so
fail-closed ext4 callers cannot confuse malformed geometry with disjoint
geometry. Preserve the established `MSPAN-*` API and in-memory set layout while
delegating its scalar predicates. Migrate scalar duplicates in ext4, MP64FS,
and `binimg` only after their existing invalid-input policies are retained by
their wrappers. Do not replace ext4's headerless authoritative vectors with a
generic range-set representation, and do not duplicate the lower-layer KDOS
`BLOCK-RANGE?` primitive merely to claim complete deduplication. The first
commit owns the scalar contract and compatibility wrappers; filesystem
migrations follow in independently reviewable commits that delete each
replaced predicate.

## Stage 2: extract bounded bitmap algebra

Add a checked, stateless LSB0 bitmap utility over a buffer and explicit
logical bit count. Its initial surface is byte-span sizing without `bits + 7`
overflow, bit test/set/clear, all-set/all-clear range predicates, whole-range
set/clear, exact-N set-bit count, and find-clear with an unambiguous status.
`(0, 0)` may describe an empty optional view; a null buffer with a positive bit
count is invalid. Search policy, run allocation, filesystem checksums,
accounting, padding rewrites, and transaction behavior stay with their current
owners. Migrate MP64FS first, then one ext4 helper family at a time with the
exact group block or inode count supplied by its authenticated caller.

The KDOS bitmap implementation remains below Akashic's dependency layer and is
not part of this extraction. Run-search helpers are promoted only when a
second real caller demonstrates a common contract.

## Stage 3: explicit source closure and semantic split

Before moving ext4 mechanisms, teach the source harness and packaging checks
to derive and inject the driver's explicit dependency closure in load order.
Keep `utils/fs/drivers/vfs-ext4.f` as the public order-preserving facade and
move coherent mechanisms behind it without late-bound execution-token cycles.
The split must preserve the exact production source closure used by the
harness and package.

The first split is the acyclic admission prefix. It depends directly on VFS
and CRC, has no callback into the facade, and ends after primary-super
validation. The next acyclic unit authenticates one group descriptor and
exposes its block, offset, flags, and inode-table span to callers only after a
successful return; those temporary result cells are not evidence after an
error. It also owns the shared descriptor checksum predicate and restamper.
The predicate restores any temporarily cleared checksum on every return. A
restamp CRC error intentionally leaves the caller-owned target with a zero
checksum, and the caller aborts its operation. The loader and group-0 recovery
candidate now delegate to that predicate instead of retaining separate
checksum implementations. The allocation-bitmap unit then owns checked
short-group geometry, nominal-format bitmap CRCs, authenticated bitmap loaders,
and the exact-bit raw allocation predicate. It keeps 22 scratch cells private,
makes both CRC calculators stack-direct, and removes the facade's duplicate
bitmap CRC tails. Logical queries exclude short-final-group padding while ext4
CRCs retain their format-defined nominal byte spans. Raw `BLOCK_UNINIT`
evidence remains `FALSE 0`; stricter loader and facade policy is unchanged.
The inode-format unit then moves eight stack services for normalized
`i_blocks`, bounded `i_block`-tail checks, canonical special-device decoding,
signed timestamp loading, checksum restamping, and timestamp encoding behind
an admission-only dependency. Its 34 scratch cells are private, and it leaves
media lookup, readable-old-format checksum policy, and IR identity/locator
results in the facade rather than creating a new mutable cross-module seam.
The external-xattr block unit likewise depends only on admission. It owns
header admission, a shared location-bound checksum calculator, authenticated
physical loading, and checksum restamping behind stack-only services. All six
scratch cells are private. The loader restores the stored checksum on every
checked-CRC error and before reporting a mismatch; the caller-owned context
`C.BLOCK` is authentication evidence only after success. The stamper instead
leaves that field zero on a checked-CRC error; callers stop and route the
failure through their enclosing transaction owner. Xattr entry parsing,
allocation and reference-count authority, transaction reconstruction, and
recovery remain in the facade.
The orphan-file block unit also depends only on admission. It owns the tail
magic and two explicit stack services for checksum verification and
restamping, with all seven scratch cells private and no mutable result surface.
The predicate leaves caller bytes unchanged and distinguishes ordinary
negative evidence as `FALSE 0` from checked-CRC failure as `FALSE ior`. The
restamper validates arguments, admitted orphan identity, physical bounds,
encoded widths, and tail magic before CRC calculation. Its sole target
mutation is the final checksum store after both CRC additions; because the tail
is excluded from the CRC, every failure leaves the caller block byte-identical.
The facade reader delegates its duplicate CRC tail and treats `C.BLOCK` as
authenticated only after success, while inode preparation, mapping, reads,
`_EXT4-OV-*` lifetime, orphan planning, transaction, and recovery policy remain
in the facade. A backup-authority unit uses the admission and descriptor
foundations to
authenticate sparse-super copies and backup descriptor locations; its three
services are stack-only and all scratch state remains private. The independent
dirhash unit owns name-byte validation, seeded
half-MD4, and the mounted version/flag policy behind one checked entry point.
It depends only on admission, keeps all hash scratch private, and moves before
the facade without a callback or mutable cross-module seam. The linear dirent
codec depends on admission and dirhash and owns three stack services for type
decoding, complete block validation, and checksum restamping. Its validator
checks the tail and CRC before parsing the record chain, so a checked-CRC error
retains precedence over latent directory corruption. Its restamper completes
argument, inode-bound, and tail validation before zeroing the checksum; a later
CRC error leaves that field zero. All 14 scratch cells are private, and
scanner-owned dot identities, inode loading, cache publication, and rollback
remain in the facade. The independent JBD2 codec likewise depends only on
admission. It owns raw big-endian access, checked block/super/commit validation,
and the corresponding encoders, while taking tag payload, stored checksum,
sequence, and context inputs explicitly.
Its 11 scratch cells remain private, its validators restore temporarily cleared
checksum fields, and its encoders retain the prior zero-on-CRC-error state. The
shared superblock stamper removes the duplicate witness/reset/activation
checksum tails without moving their policy or write ordering. The independent
JBD2 map service also depends only on admission and owns the caller-arena
map/hash allocation, mutating build-time uniqueness reservation, read-only
completed-map membership, mapped journal I/O, and ring stepping. It
deliberately does not authenticate or clear reused contents; facade-owned
snapshot construction does that before the map becomes evidence. The recovery
revoke-index service likewise depends only on admission. It owns bounded table
geometry, caller-arena allocation and retry clearing, modular transaction
ordering, and insert/query mechanics, while invalidating readiness on every
workspace attempt. The facade alone publishes `REVOKE-READY` after successful
parsing and population and retains replay authority, counters, scrubbing, and
durability.

Allocation ownership begins the facade because broadening that prefix would
capture mutation hooks whose implementations are bound much later. Every later
authority, recovery, mutation, and VFS-operation policy remains in the facade
until it forms another one-directional ownership boundary. The facade's direct
CRC edge is removed; CRC is an implementation dependency of admission's
checked adapter.

The remaining geometry/authority, JBD2 recovery and transaction, directory-
scan, xattr-entry, allocation/extent, orphan-planning, and VFS operation
families are intentionally not Stage 3 extraction candidates. Each still
crosses a prospective seam through mutable operation state, late policy
callbacks, or success-result lifetimes. No further physical split is part of
the current critical path. A later feature may justify one only after giving
that specific lifetime an explicit caller-owned interface. Any later KDOS
`PROVIDED` names must remain unique within the registry's truncated module-key
width.

This seam is not permission to enable a compiled Forth shard. Source loading
remains the qualification path, and each extracted module must have one real
production consumer rather than becoming an empty namespace or forwarding
layer.

## Stage 4: CREATE/HTree cross-phase context pilot

Stage 4 is one bounded pilot, not a driver-wide conversion of mutable globals.
Move only the CREATE/HTree state published by the first authenticated planning
pass and later consumed or compared by the dry and live staging passes into an
explicit binding-owned record funded by the binding's caller-provided arena.

The migration inventory comprised `_XC-INDEXED`, `_XC-SHAPE-SET`, every
`_XC-INDEX-BASE*` field, `_XC-INDEX-CANDIDATE-BASELINE`, every
`_XC-CONVERT-BASE*` field, `_XC-CONVERT-CANDIDATE-BASELINE`, and the retained
comparison buffers `_XC-CONVERT-HASH-BASE`, `_XC-DIR-SNAPSHOT`,
`_XC-ROOT-SNAPSHOT`, `_XC-INDEX-MAP-SNAPSHOT`, and `_XC-PARENT-SNAPSHOT`.
Stage 6 later added `_XC-NODE-SNAPSHOT` as the immutable route-node authority
needed by singleton depth-one mutation.
These were 44 mutable objects at the start of the pilot; `_XC-P.STATE` replaces
the former `_XC-SHAPE-SET` flag in the record lifecycle. This inventory is a
migration boundary, not a permanent ABI: a value may instead become
stack-local when that removes rather than relocates state.

The context does not absorb `_XC-ROOT-CURRENT`, `_XC-CONVERT-PLAN`, current-
pass route, scan, sort, allocation, CRC, or I/O scratch, transaction writer and
transaction objects, staged afterimages, postcommit cache projection, shared
mutation-owner or protocol scopes, mount or recovery state, or another
operation family. Immutable request and name data remain explicit planner
inputs. Stage 4 does not require every `_XC-*` object, much less every driver
global, to move.

At the Stage 4 checkpoint the staged binding allocated one facade-defined
3,664-byte record from its caller-provided VFS arena: 39 cells, a 24-byte
hash-authority snapshot, three 1,024-byte block snapshots, and one 256-byte
inode snapshot. Stage 5 appended its original 488-byte home-plan tail. The
root-growth probe added six evidence cells and three enum-derived home roles.
Singleton depth-one mutation subsequently added two evidence cells and one
1,024-byte DX-node snapshot. The later XU/XR collector migration adds
operation and owner-context cells to that authority/evidence body and extends
the enum-derived role universe from 23 to 30 entries. The current record is
therefore 5,496 bytes: a 4,768-byte authority/evidence body containing the
existing 47 insertion cells and snapshots plus `OP` and `OWNER-CTX`, followed
by a 728-byte tail containing one count cell and 30
`{ role, journal kind, home }` entries. With the unchanged 15,568-byte base
context, the contiguous base-context-plus-record reservation is 21,064 bytes.
Admission does not interpret that record. Its
base context owns only the opaque
`_EXT4-C.XC-PLAN` pointer and `_EXT4-C.XC-PLAN-SPAN`; the common base context
is 15,568 bytes. The record must be the exact next allocation after that base
context and wholly inside the arena's allocated prefix. Ordinary bindings keep
both ownership slots zero and do not allocate the additional record. A staged
mount retry revalidates and clears the same allocation rather than growing the
arena. A retained certificate that fails ownership validation returns a typed
failure without dereferencing or clearing its untrusted span.

The allocation may remain for the binding lifetime, but its evidence is valid
for exactly one guarded namespace operation. Each operation resolves the
record once, clears it, binds its exact operation and owner context, advances
it through building-without-shape, building-with-shape, and sealed states, and
passes its address explicitly through planning and staging. Indexed and
linear-to-HTree conversion baselines and snapshots become immutable once
sealed and are compared during dry and live replanning. The ordinary
nonconversion linear branch intentionally
refreshes its parent-inode and directory buffers after each phase's
reauthentication; those buffers remain bounded per-pass workspace so this
refactor preserves existing refusal behavior rather than turning them into
authority for a topology change. A sealed ordinary plan cannot become indexed
or acquire conversion authority that its cold pass did not bind; either change
returns conflict.

After ownership is established, every refusal, transaction failure, postcommit
failure, and successful return scrubs the complete record and facade-private
scratch after any required committed cache projection. An ownership failure
never attempts to scrub an untrusted address. No ambient alias to the plan
record may substitute for an explicit argument, and no callee may retain that
argument beyond its call. Shared CREATE/MKDIR/LINK threading through
`_XC-INSERT-COMMON` was the first implementation consequence of this lifetime
boundary; at the Stage 4 checkpoint it did not admit indexed MKDIR/LINK or
implement Stage 5 home planning.

The existing public mutation guard remains authoritative. Independent plan
records must prove isolation and reset behavior, but this stage neither claims
nor enables concurrent mutation.

Stage 4 is accepted when the complete inventory above has explicit ownership
and lifetime, no listed object remains dictionary-global, and canonical
linear CREATE, linear-to-HTree conversion, existing-leaf CREATE, and full-leaf
split retain identical refusal timing, journal home identity and first-seen
order, credit, persistent bytes, and cache projection. Canonical linear MKDIR
and LINK must retain the same properties because they share the threaded
`_XC-INSERT-COMMON` path. Poisoned-record reuse at the same address and span
must prove complete zeroing, and retained mount retry must revalidate and clear
that allocation without allocating a second record. Two independent
plan-record fixtures must prove that no prior operation supplies evidence to
the next. Exact allocated-prefix ownership validation and the absence of an
ambient plan alias are part of the source contract. The implementation commit
must delete the migrated ambient objects, pass one
sequential cold-source/focused runtime checkpoint, and report both physical
and packed-source deltas; parallel old/new evidence paths are not accepted.

Stop and revise if the pilot requires transaction or recovery state, a generic
callback framework, an ambient context pointer, a new fixed capacity, a
changed admitted topology, or a material cold-source regression. Once this
pilot passes, proceed directly to Stage 5; remaining driver globals are not a
prerequisite.

## Stage 5: ordered ext4 home preplanning

Add a small ext4-local, caller-bounded plan to the Stage 4 context. Its entries
bind an operation role, a journal kind, and a home block. The plan must expose
checked insertion, role lookup, first-seen distinct-home traversal, per-kind
credit, and intentional-alias inspection. Every API in that surface must have
an immediate production consumer: planning inserts each required role and uses
alias inspection to authorize any co-located role pair before sealing; dry and
live staging resolve the expected kind and home by role; preflight and writer
construction derive their credits by kind; and the post-staging audit walks
the sealed first-seen home order against the transaction tables. Omit an API
if the implementation does not use it for one of those checks. The
representation is not promoted as a generic Akashic collection in this stage.

Migrate the shared `_XC-INSERT-COMMON` namespace-insertion collector as one
production path. CREATE's ordinary linear insertion, linear-to-HTree
conversion, existing depth-zero leaf insertion, and full-leaf split are the
qualification pilot. MKDIR and LINK already share that collector and therefore
consume the same plan without gaining a new admitted behavior. Replace
`_XC-META-HOME-MAX`, `_XC-META-HOMES`, `_XC-META-COUNT`, `_XC-META-HOME`,
`_XC-META-RESET`, `_XC-ADD-META-HOME`, and the collector-derived credit path;
retain operation-specific authentication and staging policy, and delete every
named artifact in the same implementation tranche. Acceptance covers the four
CREATE shapes above plus canonical MKDIR and LINK, including LINK's two- and
three-distinct-home cases; each must preserve homes, first-seen order, credit,
refusal timing, persistent result, and cache projection.

This stage is now complete. At this historical checkpoint the record tail
contained one count and 20 enum-derived triple entries, so capacity follows
the declared semantic role universe instead of the largest current role
vector. Seal checks the complete
table and the explicit inode/parent, conversion-bitmap, and operation-local GDT
alias policy. Every exposed plan operation has a production consumer. The old
collector declarations, reset/add helper, scratch home, count, and credit path
were deleted together. The focused sequential gate passed the direct plan
contract, all four CREATE shapes, both one-short credit refusals, MKDIR, and
both LINK home topologies from a real cold source build. At that checkpoint XH
and XU still retained their private collectors; no compatibility copy of the
XC collector remained.

XH allocation/hole-fill, XU unlink/rename, recovery, orphan cleanup, and every
other mutation family were outside that critical-path pilot. No new private
collector may be added. XU/XR has since migrated at the indexed-deletion seam;
XH remains future work.

The modern-orphan cleanup walk is not converted to a home list. Its geometry-
driven constant-space measurement is the correct representation for an
unbounded on-disk union. Only after the ext4 migrations expose a genuinely
neutral contract and a second subsystem needs it should promotion beyond ext4
be considered.

## Stage 6: resume the indexed-directory vertical

After the namespace-insertion family uses the sealed home preplan, resume the
next selected indexed-directory capability immediately. New HTree
functionality must consume the new context and plan directly; it must not add
another private home collector. No whole-driver context conversion or
migration of another mutation family intervenes unless the next end-to-end
indexed operation cannot be correct without it. At this point qualification
returns to the full feature-development standard, including boundary, refusal,
transaction, crash-fence, repair, stable-remount, and external-tool evidence
appropriate to the new mutation.

The first positive Stage 6 slice is now implemented. Mutation preserves the
root limit/count as root geometry while binding an active entry table for
routing. A depth-zero tree continues to route from the root snapshot. A
depth-one tree is admitted only when the root names exactly one checksummed DX
node; that node must enumerate every remaining logical directory block exactly
once, cannot name itself, and is retained in the operation-owned node snapshot
across cold, dry, and live passes. CREATE may insert into authenticated slack
in one of those leaves without changing the root, node, extent map, block
bitmap, directory size, or sector count. A fresh-mount `new2.txt` capstone
routes through node logical 124/home 1364 to leaf logical 1/home 1357, commits
the exact six homes, unmounts cleanly, and passes pinned `debugfs` and
`e2fsck`. Depth-one leaf splitting remains fail-closed. The production CREATE
wrapper now admits the same exact root-growth transition, and the public
11-home journey plus fresh-mount follow-on mutation pass. Its representative
new-DX-node checkpoint tear now replays all 11 homes and reaches a write-free
byte-stable remount. Its exact-credit and unrelated-owner boundaries refuse
without writes or flushes and retain byte-identical media. The broader refusal
matrix does not interrupt the next indexed-directory feature sequence.

The indexed namespace slices reuse that authenticated HTree authority without
adding plan machinery. LINK keeps its exact three roles and no allocation;
MKDIR keeps its exact nine roles and child inode/block allocation. Both admit
existing slack in depth-zero and singleton depth-one parents while the root,
optional DX node, extent map, other leaves, parent size, and parent sector count
remain immutable. MKDIR now has a representative depth-zero happy path plus a
direct singleton-depth-one success. One combined public full-leaf
test exercises the LINK and MKDIR no-growth boundary and proves exact
`VFS-E-NOSPC`, complete public/cache rollback, scrubbed operation authority,
zero storage writes or flushes, and byte-identical media. Together with the
existing indexed CREATE selected-leaf and root-growth recovery/stable-remount
evidence and the operation-specific linear LINK/MKDIR crash matrices, this
draft-closes the namespace-insertion tranche without cloning recovery tests for
an unchanged home-list protocol. Indexed LINK/MKDIR splitting and growth remain
gated; the next Stage 6 work is the remaining indexed deletion, truncation,
metadata, and xattr forms. The focused static-contract, combined-refusal, and
singleton-depth-one MKDIR gate passed sequentially as three tests in 554.75
host seconds.

Before indexed deletion changes admission, the existing linear UNLINK, RMDIR,
and RENAME paths now share the binding-owned sealed namespace plan. This is a
collector-only checkpoint and adds no filesystem behavior. The record binds
one of the exact `INSERT`, `UNLINK`, `RMDIR`, or `RENAME` operation tags plus
the owning ext4 context at begin; seal carries both values with the ordered
role/kind/home vector, and every dry/live stage requires the same operation and
context before rebinding the exact vector and reconciling first-seen homes
against the transaction tables.

The linear XU vectors are exact. Nonfinal UNLINK binds metadata roles
`INODE=target-home`, `PARENT-INODE=parent-home`, and
`PARENT-DIRECTORY=directory-home`. Direct final UNLINK appends metadata roles
`INODE-GDT=inode-gdt-home`, `INODE-BITMAP=inode-bitmap-home`, and
`PRIMARY-SUPER=primary-super-home`. Orphan-backed final UNLINK instead appends
metadata roles `ORPHAN=orphan-home` and `PRIMARY-SUPER=primary-super-home`.
RMDIR binds the common first three metadata roles, then metadata
`RELEASE-BLOCK-GDT=child-block-gdt-home`, metadata
`RELEASE-BLOCK-BITMAP=child-block-bitmap-home`, metadata
`PRIMARY-SUPER=primary-super-home`, revoke
`RELEASE-DIRECTORY=child-directory-block`, metadata
`INODE-GDT=inode-gdt-home`, and metadata
`INODE-BITMAP=inode-bitmap-home`. Same-parent RENAME uses the common first
three metadata roles. Cross-parent regular-file RENAME binds metadata
`INODE=source-home`, `PARENT-INODE=old-parent-home`,
`RENAME-NEW-PARENT-INODE=new-parent-home`,
`PARENT-DIRECTORY=old-directory-home`, and
`RENAME-NEW-PARENT-DIRECTORY=new-directory-home`; the admitted directory move
adds metadata `RENAME-CHILD-DIRECTORY=child-directory-home`.

Accordingly, `_XU-META-HOME-MAX`, `_XU-META-HOMES`, `_XU-META-COUNT`,
`_XU-META-HOME`, `_XU-META-RESET`, and `_XU-ADD-META-HOME` are gone, as is
credit derived from that collector. Namespace credits now come from
first-seen distinct homes in the sealed plan. Orphan cleanup is deliberately
not represented as a bounded role list: its authenticated geometry still
derives the cleanup credit/revoke requirement, and the XU writer's containing
capacity is the maximum of that requirement and the sealed namespace plan.
`_XU-META-CAP` and `_XU-REVOKE-CAP` are therefore containing writer
capacities, not collector outputs. The linear XU/XR media snapshots remain
facade-private at this collector-only checkpoint. Indexed UNLINK will move
their cross-phase authority into the plan
when it consumes that evidence; this migration itself neither admits indexed
UNLINK/RMDIR/RENAME nor changes any existing transaction, recovery, or
persistence behavior. XH retains its private collector for future migration.

## Verification cadence

Refactor-only commits use deliberately narrow evidence until a meaningful
amount of duplicate machinery has been removed. For each early tranche:

1. run whitespace/diff checks and the smallest static or host-side contract
   check that covers the changed seam;
2. compile changed Python only when Python changes; and
3. run at most one directly relevant happy-path mutation for a migrated
   operation family.

Do not repeatedly run the broad recovery, persistence, fault-injection, crash-
fence, cold-source, stable-remount, or external-tool matrices while behavior is
only being rearranged. Run heavy suites sequentially, and do not increase
checked-in step guards merely to accelerate qualification. After a substantial
tranche is integrated, run one sequential source-mode cold build and a compact
representative happy-path equivalence set. Before leaving refactoring for new
functionality, run the accumulated sequential equivalence gate. When new
filesystem functionality resumes, restore the extensive qualification cadence
and include the refactored paths in that feature's evidence. The last recorded
cold source build is the closed root-growth capstone: CRC at 5,091,826 of
150,000,000 steps across 26 packed lines, bitset at 2,386,559 of 150,000,000
across 9 packed lines, and the dependency-derived ext4 closure at
1,097,074,756 of 1,600,000,000 across 3,860 packed lines from 13 source units.
Its seven selected tests passed sequentially in 926.68 host seconds: public
11-home root growth and external oracles, the committed W28 recovery and
stable-remount journey, exact-credit and unrelated-owner refusals, and the
six-home fresh-mount depth-one CREATE plus external oracles. The final
depth-one mutation measured 1,449,054,483 of 2,400,000,000 steps.

The earlier Stage 5 home-plan checkpoint measured CRC at 5,023,896 of
150,000,000 steps across 26 packed lines, bitset at 2,345,116 of 150,000,000
across 9 packed lines, and the dependency-derived ext4 closure at
1,049,876,551 of 1,600,000,000 across 3,788 packed lines from 13 source units.
Its 11-node sequential focused set passed the static and direct plan contracts,
ordinary CREATE, linear-to-HTree conversion, existing-leaf CREATE, full-leaf
split, the conversion and split one-short credit refusals, MKDIR, and LINK with
both two and three distinct homes. The conversion and split journeys passed
their unchanged 1.60- and 1.50-billion checked-in bounds at 1,590,846,839 and
1,489,035,605 steps. This qualifies the Stage 5 XC migration, not XH, XU, broad
recovery/fault matrices, or a new indexed-directory capability.

The preceding sequential Stage 3 checkpoint passed Gate 2A, MP64FS
create/write/read/delete/sync and second-bitmap-sector sync/remount, canonical
ext4 image inspection, checksum-v3 replay, and five revoke/recovery cases. The
first revoke run found stale post-mount transient-state expectations; `8918024`
corrected those oracles and all five cases then passed. This is the accumulated
Stage 1-3 checkpoint, not a rerun of the broad recovery matrices. The later
Stage 4 and Stage 5 checkpoints remain bounded refactor qualification rather
than broad feature qualification. Static source shape may advance between
intentionally sparse cold measurements.

## Commit boundaries

Use a commit when an independently reviewable invariant has one production
owner:

- this plan and its driver-document link;
- the range utility and compatibility migrations;
- the bitmap utility and each filesystem migration;
- the explicit source-closure seam and its packaging contract;
- each acyclic source-module extraction together with its facade and packaging
  update;
- the complete 44-object CREATE/HTree cross-phase context and lifecycle; and
- the home-plan contract plus the fully migrated namespace-insertion collector,
  with the old collector removed; and
- each subsequent family migration when its former collector is deleted.

Do not commit half-routed operations or leave dormant old/new paths for a later
cleanup commit. Commit messages should name the invariant centralized, the old
implementation removed, and the focused evidence run. Follow-up corrections
receive new commits rather than amendments.

## Stop conditions and completion

Stop and revise the plan before proceeding if a migration changes an admitted
filesystem shape, transaction home/order/credit, refusal timing, persistent
bytes, recovery decision, or authenticated bound. Also stop if a proposed
generic interface requires a filesystem policy, if a capacity ceases to be
derived from caller storage or authenticated geometry, or if source loading
cannot be qualified within measured system resources without weakening the
implementation.

The current critical-path cleanup is complete: namespace insertion and the
linear XU/XR family use one ordered role/kind/home preplan; its cross-phase
operation and context are sealed alongside CREATE/HTree evidence; scalar range
and bitmap contracts have one checked Akashic implementation with filesystem
wrappers retaining their policies; the production facade loads an explicit
acyclic source closure; and the replaced XC and XU collectors are gone. The
latest recorded cold-source accumulated gate remains the earlier indexed checkpoint; this
collector-only migration adds no new measurement claim. XH remains future
collector cleanup. Indexed UNLINK is the next consumer that must move XU's
private cross-phase snapshots into the shared record before broadening
directory admission.
