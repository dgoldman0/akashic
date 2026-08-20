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
- Stage 3 is in progress. The cold ext4 source harness derives the driver's
  dependency-ordered closure and removes the VFS, CRC, and bitset foundation
  already present in earlier measured stages. The first physical component,
  `vfs-ext4-admission.f`, now owns the on-disk profile and private context
  layout, checked I/O and CRC adapter, probe helpers, checked arithmetic, and
  primary-super admission.
  `vfs-ext4.f` remains the only public facade and begins with group-descriptor
  admission. The aggregate source stage now loads `(admission, facade)` in
  production order rather than relying on a handwritten concatenation list.
  Four checked-I/O session/evidence cells remain a temporary cross-component
  surface until the operation-lifetime context stage.

## Baseline and objective

The frozen semantic comparison point is the clean `ext4-recovery` tree at
`abb3f9462d379b0adb2f09d1009831dd2f85afdb`. Documentation and refactor commits
advance `HEAD`, but that commit remains the behavior, ordering, persistent-byte,
and crash comparison baseline. It includes bounded depth-zero HTree full-leaf
CREATE and its recovery qualification. The next feature boundary remains HTree
root-depth growth or a separately chosen indexed-directory mutation.
Refactoring must not silently cross that boundary or admit indexed LINK/MKDIR,
broader map shapes, or another previously gated filesystem behavior.

The objective is to establish one authoritative implementation for each of
these recurring mechanisms:

- validated half-open integer-range algebra;
- checked LSB0 bitmap operations over caller-described storage;
- the production source closure and its semantic module boundaries;
- operation-lifetime mutation state; and
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
validation. Group descriptors and every later authority, recovery, mutation,
and VFS-operation policy remain in the facade until they form another
one-directional ownership boundary. The facade's direct CRC edge is removed;
CRC is an implementation dependency of admission's checked adapter.

Candidate boundaries are validated geometry/authority, JBD2 recovery and
transaction execution, directory/HTree mechanics, allocation and extent
mutation, orphan handling, and VFS operation adapters. They are candidates,
not mandatory filenames: cohesion and acyclic load order decide the actual
split. New KDOS `PROVIDED` names must remain unique within the registry's
truncated module-key width.

This seam is not permission to enable a compiled Forth shard. Source loading
remains the qualification path, and each extracted module must have one real
production consumer rather than becoming an empty namespace or forwarding
layer.

## Stage 4: operation-lifetime contexts

Move mutable driver globals into caller-owned contexts by operation family and
lifetime, beginning with the namespace and allocation families that will later
consume the shared preplan. Directory authority, mutation planning,
transaction execution, recovery, and mount state must remain separate
concepts; this stage must not replace thousands of globals with one monolithic
record.

The currently guarded public VFS entry points serialize mutations, so this is
primarily a composability, test-isolation, and future-concurrency repair. It
does not justify weakening the guard before reentrancy has separate evidence.

## Stage 5: ordered ext4 home preplanning

Introduce a small ext4-local, caller-bounded plan whose entries bind an
operation role, a journal kind, and a home block. The plan must expose checked
insertion, role lookup, first-seen distinct-home traversal, per-kind credit,
and intentional-alias inspection. Its representation is not promoted as a
generic Akashic collection in this stage.

Migrate one bounded mutation family completely as the pilot. Replace its
private home array, count, duplicate scan, and credit derivation; retain its
operation-specific authentication and staging policy. Delete the replaced
planner in the same implementation tranche. Once the pilot proves the seam,
migrate CREATE/HTree planning and the remaining bounded mutation families one
at a time. RENAME may continue to share the unlink-family operation machinery
while that family migrates.

The modern-orphan cleanup walk is not converted to a home list. Its geometry-
driven constant-space measurement is the correct representation for an
unbounded on-disk union. Only after the ext4 migrations expose a genuinely
neutral contract and a second subsystem needs it should promotion beyond ext4
be considered.

## Stage 6: resume the indexed-directory vertical

After CREATE and its HTree variants use the shared home preplan, resume the
next selected indexed-directory capability. New functionality must consume the
new seam directly; it must not add another private home collector. A newly
found cleanup defect interrupts that vertical only when the next end-to-end
step cannot be correct without the repair. At this point qualification returns
to the full feature-development standard, including boundary, refusal,
transaction, crash-fence, repair, stable-remount, and external-tool evidence
appropriate to the new mutation.

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
cold-source measurement is 1,592,943,041 of the 1,600,000,000-step watchdog
across 3,724 packed lines; that narrow measured guard is not an implementation
capacity. Static source shape may advance between those intentionally sparse
cold measurements.

## Commit boundaries

Use a commit when an independently reviewable invariant has one production
owner:

- this plan and its driver-document link;
- the range utility and compatibility migrations;
- the bitmap utility and each filesystem migration;
- the explicit source-closure seam and its packaging contract;
- each acyclic source-module extraction together with its facade and packaging
  update;
- each coherent operation-context migration; and
- the home-plan contract plus one fully migrated operation family, with the old
  collector removed; and
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

The planned cleanup is complete when the migrated operation families share one
ordered role/home preplan; scalar range and bitmap contracts have one checked
Akashic implementation with filesystem wrappers retaining their policies;
mutable mutation state has explicit operation lifetimes; the production facade
loads an explicit acyclic source closure; duplicate paths are gone; and the
accumulated focused regression set passes from a real cold source build. The
Stage 5 gate is the transition back to the selected indexed-directory vertical
and its full feature-development qualification cadence.
