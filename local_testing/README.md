# Akashic TUI Development

`akashic_tui.py` is the supported test harness between this repository and the
sibling MegaPad checkout. It builds only the transitive `REQUIRE` closure for
the selected app profile, preserving the source paths inside MP64FS. It does
not use or create `local_testing/emu`.

By default the repositories are expected to be siblings:

```text
fantasy-computing/
  akashic/
  megapad/
```

Set `MEGAPAD_ROOT` when using a different layout.

## Refactor architecture ratchet

Landing L0's host-only architecture inventory is independent of MegaPad images
and filesystem drivers:

```bash
python3 local_testing/refactor_inventory.py --check
python3 -m pytest -q local_testing/test_refactor_inventory.py
```

Use `--format json` for the complete machine-readable dependency, ownership,
capacity, and mutable-state report. The reviewed policy lives in
`local_testing/refactor_architecture.json`; its rationale, current debt, units,
and update rule are documented in `docs/refactor/l0-architecture-baseline.md`.
Unknown source packages and any unreviewed widening of dependency, placement,
unresolved-import, or global-state debt fail the ratchet. Ext4 is not a
prerequisite for these checks or the planned storage refactor.

Landing L1's functional-preservation ledger is also host-only:

```bash
python3 local_testing/refactor_functional_baseline.py --check
python3 -m pytest -q local_testing/test_refactor_functional_baseline.py
```

It pins the current UIDL, direct-input, capability and Desk service surfaces and
maps each preserved behavior group to exact profiles, tests or drivers.
Partially characterized groups name the test prerequisite and trigger that must
be satisfied before a later landing touches the uncovered edge. See
`docs/refactor/l1-functional-preservation-baseline.md` for scope and update
rules.

The L5 neutral-construction profile qualifies the caller-owned transactional
schema, value, and capability builders independently of any applet or resource
owner:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile interop-construction-contracts \
  --max-steps 350000000 --timeout 60
```

Its 120 guest assertions cover malformed contracts, sticky failure, same- and
independent-workspace behavior, destination nonmutation, zero-copy value
publication, deterministic root/key/nested allocation denial, recursive abort,
and exact available-memory restoration. The API and borrowed/owned lifetime
rules are documented in `docs/interop/construction.md`.

L6 independently qualifies the caller-owned owner pool and retained resource
session before their applet integrations:

```bash
python3 -m pytest -q -s \
  local_testing/test_resource_owner_pool.py \
  local_testing/test_resource_session.py
```

The pool fixture covers 282 assertions across publication rollback,
generation/refcount/inflight/close, exact token ledgers, retryable release,
callback containment, output aliasing, per-resource offers, and independent
pools. The session fixture covers 231 assertions across two named offers and
distinct pools, raw nested-span alias nonmutation, exact one-call service
discovery with the named offer last, copied-offer lifetime, compact and
canonical protocols, candidate switching (including same-address input), stale
recovery, committed-stale behavior, rollback, and retryable finalization. The
applet qualification additionally runs `daybook-contracts`,
`pad-resource-contracts`, `desk-service-table-contracts`, `desktop-resource`,
and `desktop-agent-hardening`, plus the focused shared-document pytests and
Library's linked projection-owner gate. None of these checks requires ext4. See
`docs/refactor/l6-resource-owner-pool-and-session.md` for the exact boundary
and final evidence.

L7 re-homes Agent and Daybook product code without changing their applet
surfaces. Its new prerequisite-closing profile drives the real Agent Clear,
Reconnect, and Refresh Models actions through parsed UIDL state and also
qualifies atomic Desk access-policy injection and tamper rejection:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile agent-provider-ui-commands \
  --max-steps 5000000000 --timeout 180
```

The landing additionally runs `agent`, `agent-access`, `agent-security`,
`agent-persistence`, `agent-widgets`, `daybook-contracts`,
`desk-service-table-contracts`, `desktop-agent-hardening`, and
`desktop-resource`, plus the focused L7/Daybook pytests and both refactor
ratchets. These are MP64FS/generic-VFS qualifications; ext4 remains unrelated.
See `docs/refactor/l7-daybook-agent-rehoming.md` for the ownership boundary and
final evidence.

L8 re-homed Library beneath `tui/applets/library/`; its landing document remains
historical evidence. L12 replaces the temporary fixed backend with the current
Library model/document-value/index-key/persistence-adapter/repository/query/
service split over neutral persistence. Documents, collections, membership,
history, and postings are indexed populations; content and metadata are
chunked blobs. The current prototype has one layout with no legacy reader or
migration stack. The final acceptance boundary and measured current-tree
matrix are recorded in
[`evidence/library-l12-close-20260724.md`](evidence/library-l12-close-20260724.md).

The linked projection and executable-lens profiles are:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile library-projection-owner-contracts \
  --max-steps 70000000000 --timeout 1200
python3 local_testing/akashic_tui.py smoke \
  --profile library-applet-functional-contracts \
  --max-steps 55000000000 --timeout 1200
```

The functional applet fixture exercises the real shell/controller lifecycle,
including reopening an existing corpus and visibly blocking corrupt and future
authority without writes. Renderer-free profiles are a testability boundary,
not a standalone Library product. The current L12 wrapper matrix is documented
under “Library L12 qualification” below. None of it requires ext4.

## Build And Smoke Test

```bash
python3 local_testing/akashic_tui.py build --profile desktop
python3 local_testing/akashic_tui.py smoke --profile desktop
```

Smoke and served sessions use 128 MiB of emulated external memory by default.
This leaves realistic headroom for the userland dictionary and applet working
sets as the Desk image grows; pass `--ext-mem-mib N` to test another budget.
The default smoke gate permits 9 billion guest steps and 120 seconds so the
complete linked Desktop can compile its canonical loadable networking and
scoped VFS-access modules and still reach its ready markers. This guest-step
ceiling is emulator qualification headroom, not a product capacity or
scalability parameter. The exact no-override command passed at 8.41 billion
guest steps in 101.27 seconds on 2026-07-21. Focused profiles stop as soon as
their own markers stabilize; `--max-steps` and `--timeout` remain available
for explicit qualification budgets.

## Ext4 compatibility profile

The ext4 format contract is pinned in
`docs/utils/fs/ext4-compatibility-profile.md` and mirrored by the
machine-readable `fixtures/ext4-profile/manifest.json`.  It requires one
source-built e2fsprogs v1.47.4 prefix; ambient `PATH` tools are deliberately
rejected.  Generate the four geometry images plus the supplemental
`read-side-1k-i256` image and run the profile gates with:

```bash
python3 local_testing/generate_ext4_profile_fixtures.py \
  --tool-dir /absolute/e2fsprogs-1.47.4-prefix/sbin \
  --output-dir local_testing/out/ext4-profile

AKASHIC_E2FSPROGS_TOOL_DIR=/absolute/e2fsprogs-1.47.4-prefix/sbin \
  python3 -m pytest -q local_testing/test_ext4_profile.py

AKASHIC_E2FSPROGS_TOOL_DIR=/absolute/e2fsprogs-1.47.4-prefix/sbin \
  python3 -m pytest -q local_testing/test_vfs_ext4.py
```

The shared FAT/ext4 emulator snapshot uses 64 MiB of external memory: KDOS
owns its established 32 MiB userland dictionary zone and the remainder holds
the VFS test arena and loader allocations. Snapshot construction requires an
exact userland-ready marker, so a capacity refusal cannot silently fall back
to compiling drivers into Bank 0.

`test_vfs_ext4.py` then mounts those same images through the clean read-only
ABI-1 binding.  It covers checksummed linear and HTree directories, depth-1
real external extents and bounded traversal through the profile depth limit,
legacy direct/single/double/triple maps, allocation-bitmap cross-checks,
special-inode metadata and unsupported opens, namespaced/raw-ACL xattrs, and
bounded generic symlink traversal including a live block-backed target.  Its
corruption cases include HTree and extent-node checksums, allocation
disagreement, and duplicate/overlapping xattr records. The suite also authors
a private checksum-v3/64-bit JBD2 log with the pinned `debugfs`, and generates
a second 8 MiB journal with pinned `mke2fs` to cross the canonical 4 MiB
fixture size. Checksummed transactions are relocated above logical block 4095
and across the ring end. Standard 64-bit revoke records are exercised in a
three-pass committed-prefix/revoke/replay flow: later committed revokes
suppress same-or-earlier home images, a still-later descriptor remains
replayable, and an incomplete revoke grants no authority. Revoke lookup is
arena-derived and transaction-ID-wrap aware; the 8 MiB case also crosses the
ring end between descriptor data, commit, revoke, and the following commit.
Multi-record collisions, malformed counts and block addresses, and a
same-transaction revoke of a proposed primary-super repair are all refused or
resolved before the first media write. A shared inode-table replay may update
a neighboring inode but must preserve journal inode 8 exactly. The suite exercises
arena-derived map/revoke geometry, committed replay, valid incomplete-tail
discard, pre-write corruption and physical-read-only refusal, ordered flushes,
idempotence, and both repairable and explicitly fail-closed tears in the
journal/ext4 landing sequence. The repairable matrix includes exact
sequential-prefix tears of primary witness removal for both clean landing and
write-active dirty-empty turnover; damaged locators that cannot prove that
transition remain refused. Orphan recovery, checksum-torn tail classification,
ACL enforcement, and every user-visible mutation remain outside this gate.
This remains an explicit-volume emulator suite rather than a default boot-image
or automount profile.

Bounded synthetic cases also qualify the private writer workspace without
issuing storage writes or flushes. They cover exact one-allocation sizing and
reuse, mount-owned `WRITER-CURRENT` admission, clean head/sequence rebasing,
1 KiB and 4 KiB descriptor/revoke geometry, checked arithmetic, guard-inclusive
journal-ring reservation with guard-exclusive `s_max_transaction` accounting,
full-block after-image ownership and CRCs, hash collisions and forged-index
rejection, metadata/revoke cancellation, ordered-data/revoke conflicts, atomic
capacity failures, abort zeroization, and malformed persistent-layout guards.

The 1 KiB writer fixture separately qualifies private clean-to-`RECOVER`
activation. An independently derived `AKW1` guard/primary pair checks the exact
write/flush order, durable dirty-super and empty checksum-v3 result,
write-active publication, and continued staging/abort behavior without any
descriptor or commit emission. Injected sequential-prefix failures cover guard
preseed, guard publication, primary publication, ext4-super update, witness
clear, and guard retirement. Each row must latch the original fault and phase,
force the VFS read-only/dirty, and remount through the forward-only `AKW1`
resolver and existing `AKR1` clean landing with no home write. Follow-on rows
tear the resolver's own dirty-super and standard-primary completions and require
a third mount to converge; fresh-primary UUID and sequence drift must also fail
before any activation write or flush.

The same 1 KiB fixture now qualifies one private durable transaction after
activation. It stages one escaped metadata after-image, one ordered-data home
image, and one 64-bit revoke, then checks the exact serial trace: ordered data,
descriptor, payload, revoke, invalid-byte commit preseed, zero sentinel, body
flush, invalid and valid active-guard publication, identical active-primary
publication, exact reread proof, and final commit/flush. The host independently
reconstructs and verifies descriptor/tag, payload, revoke, commit, and
superblock CRC32C; checks that the primary and guard are standard active
checksum-v3 images; proves the metadata home block is still unchanged while
ordered data is durable; and requires `COMMITTED` to retain all after-images
and refuse retry, abort, or another transaction.

A bounded multi-batch case stages 63 metadata after-images, one ordered-data
image, and 126 revokes. This is the smallest 1 KiB transaction that requires
two descriptor blocks and two revoke blocks. It starts the reservation three
blocks before the journal-ring end so the first descriptor's payload run
crosses from logical block 4095 to logical block 1, then independently verifies
every descriptor tag, journal UUID slot, escaped payload, revoke entry,
checksum, commit, and sentinel. A same-session remount must replay all 63
metadata payloads, parse all 126 revokes with zero matching tag hits, leave
every revoke-named home unchanged, reset the clean journal, and rebase the
existing workspace without arena growth.

A persistent write-active case stages one metadata after-image, one ordered
data image, and one revoke with the guard derived at `s_maxlen-3`. Its exact
same-session lifecycle is `A + E1 + C + E2 + U[C + D]`: one initial `AKW1`
activation, two independent emission/commit cycles, one explicit checkpoint,
then public unmount entered while the second transaction remains `COMMITTED`.
Unmount performs its required checkpoint `C` before clean deactivation `D`.
Each checkpoint performs an ordinary complete log scan followed by a lockstep
retained-authority scan before an exact six-write trace: metadata home, invalid
`AKG1` reset guard, valid reset guard, witnessed empty primary, standard
witness-free primary, and guard retirement. The binder compares every
descriptor home and unescaped payload and every revoke identity in emitter
order, requires exact retained stream exhaustion, and admits only the all-zero
emitted sentinel. The existing 63-metadata/126-revoke ring-wrap case also runs
this binder across both descriptor batches and both revoke batches.
Independently checksummed descriptor-home, payload, revoke-home,
revoke-high-word, and nonzero-sentinel mutations prove that generic JBD2
scanning can accept coherent media which checkpoint must still reject before
its first write or flush.

Checkpoint flush boundaries separate home durability from release and each
reset/authority transition. Checkpoint does not write the ext4 superblock:
`RECOVER`, `WRITE-ACTIVE`, and VFS dirty remain set, so `E2` begins without a
second activation or arena growth. The lifecycle starts the journal sequence
at `0xfffffffa`, crosses the wrapping 32-bit transaction/reset sequence
boundary, checks the first checkpoint's persisted empty-journal head and
sequence directly, and derives and verifies the final sequence across the
unmount checkpoint and deactivation. It also checks full free space, every
entry/hash slot, every byte of the retained metadata and data image regions,
and the final `IDLE` workspace after the first checkpoint and clean
deactivation. Corrupting a retained image must fail checkpoint preflight
before any checkpoint write or flush.

Deactivation `D` begins with an initial flush/reload/root proof and then writes
the invalid reset preseed, valid reset anchor, witnessed primary, clean ext4
superblock, standard primary, and retired anchor, with a flush after each
authority transition. Public unmount clears readiness/current ownership, the
VFS dirty bit, and `V.BCTX` only after final reload/root/attachment proof. The
final clean image remounts without recovery I/O.

Six checkpoint fault rows apply a sequential prefix at each of those six
writes. Failures remain quarantined in the same mount and remount must converge
through the surviving authority. The home, invalid-guard, and valid-guard rows
retain the active committed log and therefore replay one metadata home image;
the reset-primary, standard-primary, and guard-retirement rows have already
crossed the durable home flush and replay zero. No row may release space or
permit another same-session transaction after a checkpoint fault.
Representative home and final-guard flush failures plus post-home and final
strict-reread failures exercise the same quarantine rule at non-write
boundaries. The first three retain the current writer publication; the final
reread occurs after publication withdrawal and proves that the invalidated
workspace cannot be reused.

Clean-deactivation qualification covers all six partial writes,
representative flush barriers (initial, reset-primary, clean-super,
standard-primary, and final-anchor), both fresh primary/anchor witness-proof
reads, and the final strict reread. Every failure returns the exact first ior
through public unmount, records the deactivation phase, forces
read-only/dirty state, retains `V.BCTX`, and makes that VFS terminal stale; a
forced retry returns `VFS-E-STALE` without more I/O. Each captured sparse image
is then mounted through a fresh VFS, converged from its surviving endpoint or
admitted sequential prefix, and cleanly unmounted. A staged transaction
separately proves that both ordinary and forced public unmount return
`VFS-E-BUSY` without waiving transaction authority.

Emission fault injection keeps the first failing ior and phase quarantined in
the same mount and requires a later mount to classify the durable endpoint and
converge forward. Primary-prefix rows exercise old-versus-active selection from
the exact standard guard. Commit-prefix rows require an invalid preseed or the
exact valid commit, never a mixed authoritative commit. Active-to-reset retry
rows exercise the `AKG1` marker/complement, sequence, and full-block CRC proof
before ordinary `AKR1` landing. A failed remount leaves the preserved writer
non-current and unscrubbed; only the authenticated clean remount may scrub its
staged/faulted state and rebase it to `IDLE`. The lifecycle matrix also forces
an attachment failure after current-writer withdrawal, proving that the
preserved workspace is structurally inspectable but unusable, and verifies
that successful clean unmount clears both binding readiness and current-writer
ownership with the block context detached.

These are private durability qualifications, not writable-VFS claims. The
suite now covers activation, emission, same-session metadata checkpoint,
journal-space reuse, `COMMITTED` public-unmount checkpointing, and clean
write-active deactivation. It still has no legacy or modern orphan mutation or
user-visible ext4 mutation operation. External-tool inspection and the
complete release/power-cut matrix also remain open. The public ext4 capability
mask stays read-only until those full writer and release gates pass.

When a resolved profile closure binds directly to MegaPad networking, the
harness injects the one canonical packed `networking.f` and loads it with
KDOS `REQUIRE` immediately after `ENTER-USERLAND`. This avoids re-entering the
BIOS loader while its KDOS autoboot buffer is still live. Parser-only and
abstract-I/O profiles omit networking. The system module is neither renamed
nor linked into an Akashic deployment chunk.

The authoritative profile registry and each journey's assertions live in
`akashic_tui.py`; `--help` lists the accepted profile names. Profiles are
organized around focused library/runtime contracts, direct applet journeys,
and linked Desk journeys. Run the narrow profile for the behavior being changed
and the linked profile that owns its production lifecycle. Generated images,
terminal text, cell JSON, and PNG captures go under `local_testing/out/`.

`vfs-access-contracts` qualifies the neutral caller-owned access layer over two
independent RAM VFS instances. It covers exact range geometry, complete versus
prefix reads, streamed chunk offsets and early stop, callback and backend
failures, nested/interleaved scopes, selector and CWD restoration, exact-once
cleanup under after-effect faults, separate primary and cleanup results, busy
re-entry, idempotent close, and descriptor-leak checks. It deliberately does
not import an applet, a replacement protocol, a record envelope, or a durable
publication policy. Run it with:

```bash
python3 local_testing/akashic_tui.py smoke --profile vfs-access-contracts
```

`checked-record-contracts` qualifies the allocation-free fixed/framed record
envelope independently of VFS and every applet schema. It covers sealed
caller-owned specifications and workspaces, checked geometry, exact and future
format classification, header and payload checksums, canonical fixed tails and
framed padding, semantic callbacks, callback containment, nonmutation, hostile
aliases, same-workspace re-entry refusal, and independent nested workspaces.

`generation-pair-contracts` qualifies the path- and format-neutral A/B
selection/publication primitive. It covers absent/corrupt/fallback/newest
classification, byte-equal and divergent equal-generation candidates,
authority revocation, candidate/pair aliases, overflow, re-entry, callback
faults, inactive-slot choice, and the no-effect/maybe/durable publication
milestones. Run either focused contract with:

```bash
python3 local_testing/akashic_tui.py smoke --profile checked-record-contracts
python3 local_testing/akashic_tui.py smoke --profile generation-pair-contracts
```

The proving consumers retain their own meanings: VFSNAP owns replacement and
recovery, Library owns record schemas, Agent owns transcript paths and status
mapping, and Practice owns its head schema and readonly recovery policy. The
neutral modules do not create a generic applet, repository, or compatibility
format stack.

`gate2a-contracts` isolates the policy-neutral memory-span predicates, inline
caller-owned span sets, checked buffer writer, and caller-owned scalar/locator
schema initializers. It covers signed-length and unsigned-wrap boundaries,
empty/null policy separation, half-open overlap and adjacency, borrowed span
geometry, independent bounded sets and writers, sticky all-or-nothing capacity
failure, decimal cell extrema, exact schema bytes, UTF-8/type/length rejection,
and the distinct 110-byte semantic RREF and 516-byte VFS-locator text bounds.

### Library L12 qualification

The L12 gates target the current implementation directly. The pure/value/key
layer is:

```bash
python3 local_testing/test_library_model_l12.py
python3 local_testing/test_library_metadata_l12.py
python3 local_testing/test_library_document_values_l12.py
python3 local_testing/test_library_index_keys.py
```

These wrappers cover canonical entries and transitions, streamed metadata
facts, value preparation, and every ordered key family. They contain no
Library VFS path or UI.

The persistence, repository, query, and semantic-service layer is:

```bash
python3 local_testing/test_library_persistence_l12.py
python3 local_testing/test_library_repository_l12.py
python3 local_testing/test_library_repository_paths_l12.py
python3 local_testing/test_library_query_l12.py
python3 local_testing/test_library_service_l12.py
python3 local_testing/test_library_service_scale_l12.py
python3 local_testing/test_library_collection_l12.py
python3 local_testing/test_library_restore_l12.py
```

This matrix exercises current checked records/application roots, growing
ordered indexes, chunked content and metadata, exact identity/operation
directories, semantic keyset paging, streamed body verification, exact
mutations and retries, retained history, captures, tombstones, and collection
membership beyond the former fixed catalog shape. The scale fixture is
disposable synthetic setup around the unchanged public collection/service
surface; ordinary semantic and index parity remain covered by the focused
gates.

Maintenance and cold authority are:

```bash
python3 local_testing/test_library_compaction_l12.py
python3 local_testing/test_library_maintenance_l12.py
python3 local_testing/library_managed_two_boot.py --timeout 180
```

Compaction is a budgeted semantic rebuild into the other physical bank, with
explicit finalize/publish/mirror/cleanup and recovery states. Maintenance
inspection and raw export seal all eight current physical roles; repair is
limited to a fully recognized root mirror. The two-boot driver crosses a real
spawn boundary with only serialized MP64FS bytes and the printed RID, then
reopens query/read/content/receipt authority and proves an exact stale-
generation operation replay does not duplicate the document.

The Library projection and applet gates remain linked production closures:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile library-projection-owner-contracts \
  --max-steps 70000000000 --timeout 1200
python3 local_testing/akashic_tui.py smoke \
  --profile library-applet-functional-contracts \
  --max-steps 55000000000 --timeout 1200
```

The projection profile covers service-backed describe/snapshot/replace,
qualified exact reads, capture read-only behavior, lease lifecycle, quiescence,
and the eight-owner/64-lease activation bounds. The applet profile drives the
real shell, UIDL, controller, and service through create/retry, search,
preview, rename, lifecycle, history, collection filtering, bidirectional
keyset paging, reload, existing-corpus activation, and corrupt/future
nonwritable presentation.

Run the remaining persistence contracts, then the host-side storage scale and
packaging ratchets, with:

```bash
python3 local_testing/test_persistence_storage.py
python3 local_testing/test_persistence_atomic_root.py
python3 local_testing/test_persistence_btree.py
python3 local_testing/test_persistence_blob.py
python3 local_testing/test_persistence_reclaim.py
python3 local_testing/test_persistence_compaction.py
python3 -m pytest -q \
  local_testing/test_persistence_boundaries.py \
  local_testing/test_persistence_scale_model.py \
  local_testing/test_vfs_mp64fs.py \
  local_testing/test_akashic_tui_packaging.py \
  local_testing/test_refactor_inventory.py \
  local_testing/test_refactor_functional_baseline.py
python3 local_testing/refactor_inventory.py --check
python3 local_testing/refactor_functional_baseline.py --check
```

The scale model distinguishes corpus size from bounded RAM work and checks
tree height, point/range work, streamed content, page reclamation, and
compaction budgets. Emulator cycle counts remain model measurements rather
than FPGA or storage-device latency. No current Library qualification requires
ext4.

The Streams qualification path is intentionally split by boundary:

- `streams-contracts` covers the owned feed model and typed capabilities.
- `streams-draft-contracts` covers the draft record and replacement primitive.
- `streams-persistence-contracts` covers normal applet load/save/recovery.
- `streams-source-registry-contracts` covers the pointer-free bounded source
  model, exact revisions, validation, and canonical unused records.
- `streams-source-store-contracts` covers the versioned source record, CRC,
  staged replacement, recovery, fail-closed states, and buffer isolation.
- `streams-source-owner-contracts` covers lifecycle loading, optimistic durable
  mutations, sanitized capabilities, and actual Agent-principal authority,
  operand-seal, reviewed-commit, and replay behavior.
- `syndication-contracts` covers the reusable bounded JSON Feed 1/1.1,
  RSS 2.0, and Atom 1.0 codecs, their format-specific owned models, the narrow
  shared item projection, and transactional fixture generations.
- `media-type-contracts` covers the reusable bounded, caller-owned media-type
  syntax model, decoded parameters, bounds, and transactional failure behavior.
- `readable-text-contracts` covers reusable inert plain-text and strict-HTML
  projection, UTF-8/entity behavior, overlap rejection, bounds, and failures.
- `streams-page-contracts` covers Streams-specific media admission composed
  over those reusable boundaries, the exact V1 snapshot ABI, tamper checks,
  transactional raw/normalized hashes, and watched-page fixture generations.
- `streams-source-ui-contracts` covers standalone source creation, independent
  selection, exact toggle/removal, stale-confirmation rejection, and blocked
  storage presentation.
- `local_testing/fixtures/syndication/` is the library-owned JSON Feed, RSS,
  and Atom qualification corpus exercised by `syndication-contracts`.
- `local_testing/fixtures/streams/` contains only Streams-owned watched-page,
  text, and notification qualification data. The page and text generations are
  exercised by `streams-page-contracts`; fixture presence alone is not a claim
  that every corresponding adapter is implemented.
- `streams-xio-contracts` covers the explicitly composed Streams/XIO contract
  using injected port callbacks: submission, completion, actor rollback, stale
  results, and cleanup. It is offline integration evidence, not live-network or
  Desk-responsiveness evidence.
- `public-author-feed` covers bounded request/admission behavior and cooperative
  buffered HTTP lifecycle with deterministic partial-I/O callbacks.
- `tls-port` covers the native connector's deterministic phase progression,
  post-DNS public-address admission, policy override/mutation hardening,
  cancellation, graceful close, and bounded abort fallback without external
  network access.
- `streams` covers the standalone timeline, context, search, and draft UI.
- `desktop-streams` covers real launcher-driven source create/toggle/removal,
  exact source/draft persistence, close, relaunch, and recovery through Desk.
  Its launcher now uses the production online composition; no fixture, source,
  actor, or startup tile is preseeded.
- `streams-multiprotocol-composition` is the focused no-network composition
  gate for the reviewed vertical. It registers the public AT trust
  contribution, imports the exact-host RSS trust artifact, configures the
  authorized production syndication provider, and configures the production
  public Bluesky provider.
- `desktop-streams-vertical` is the opt-in TAP-facing product journey. In one
  Desk-hosted Streams instance it fetches and visibly retains the reviewed RSS
  source, fetches a public Bluesky author feed through AT Protocol XRPC, then
  returns to Sources and proves the RSS result remains visible before clean
  close. This is a real public-XRPC-plus-syndication vertical, not evidence of
  authenticated PDS participation, repository writes, raw sync, subscriptions,
  or a general arbitrary-host feed policy.
- `desktop-agent-hardening` keeps Streams live while proving Desk exposes only
  its two sanitized Observe operations in ordinary read/assist facets.
- `streams-live-public` is the opt-in TAP-facing component journey; it directly
  ticks the XIO service, Streams component, and network loop.

The deterministic `tls-port`, `public-author-feed`, and
`streams-xio-contracts` gates pass in the current tree. The exact
`streams-live-public` command below also passes over the real TAP path through
DNS, TCP, authenticated TLS 1.3, HTTP, provider admission, feed decoding, and
owner commit. It remains a focused component journey rather than a
Desk-hosted responsiveness journey. The connector records cycles per poll,
but the complete live certificate-chain and signature phases do not yet have a
measured per-poll CPU ceiling. Context cleanup also does not prove that every
machine-global KDOS TLS/cryptographic scratch buffer has been sanitized.

The no-network construction/configuration gate is:

```text
python3 local_testing/akashic_tui.py smoke \
  --profile streams-multiprotocol-composition \
  --max-steps 9000000000 --timeout 300
```

Its linked image builds, but the current checkpoint has not recorded a PASS:
the latest bounded run stopped before autoexec at 355,500,000 guest steps and
180 seconds with no guest output. The combined Desk-hosted live witness is
also intentionally opt-in and not yet recorded as passing:

```text
python3 local_testing/akashic_tui.py smoke \
  --profile desktop-streams-vertical --nic-tap mp64tap0 \
  --max-steps 9000000000 --timeout 300
```

The profile authorizes only
`https://foo-dogsquared.github.io/hugo-theme-more-contentful/feed.rss`;
the public actor used by the journey is
`did:plc:z72i7hdynmk6r22z27h6tvur`. The ordinary configured provider remains
fail-closed without a host-supplied authorization policy.

The synthetic Streams page lives at
`local_testing/fixtures/atproto/timeline.json`. The harness copies it into the
guest test namespace as `/testing/streams/timeline.json`; it is qualification
input, not an `akashic/atproto` runtime resource or an applet fallback feed.

Closures that exceed MP64FS's entry or byte limits are linked into
dependency-ordered native Forth chunks under `/.akashic/`, each held to a
stable 120 KiB evaluation budget. This includes the full Desktop and several
large focused Agent/provider profiles; smaller profiles keep ordinary
per-module `REQUIRE` loading. MegaPad's larger `networking.f` remains a
separate system module and KDOS reads its validated extents in guarded
255-sector batches before the Akashic chunks. Linking and deployment-only
comment stripping change only generated images, not source organization,
executable tokens, or runtime ABI. The copied KDOS source receives the
narrower safe transform: only blank
and full-line backslash-comment lines are omitted.

Smoke journeys assert semantic application behavior in the guest, not only boot
markers or screenshots. Focused contract profiles cover bounds, ownership,
failure cleanup, and stack balance; applet profiles cover user interaction; Desk
profiles cover the linked lifecycle and Practice boundary. Keep detailed
assertion inventories beside the corresponding profile implementation so they
cannot drift from this README.

The audio qualification path has no host audio-device dependency and does not
claim that numerical checks establish aesthetic quality. Run it with:

```bash
python3 local_testing/akashic_tui.py smoke \
  --profile audio-contracts --max-steps 2500000000 --timeout 180
```

The guest leaves bounded mono FP16 buffers and one encoded WAV alive for the
duration of the smoke session, while the headless machine records exact raw
S16 and converted FP16 AudioOut submissions without requiring an audible host
sink. The host reads those exact mapped-memory spans and capture bytes,
recomputes its own time- and frequency-domain results, and writes the FP16
vectors, `audio-output-{raw,fp16}.s16le`, `tone.wav`, and a JSON report under
`local_testing/out/audio-contracts/`. This is deliberately separate from
subjective audition; `aplay local_testing/out/audio-contracts/tone.wav` is an
optional human check after the deterministic contracts pass.

Run the focused profile plus `desktop-agent` before changing shared TUI, VFS,
agent, or app-shell behavior. The normal suite is fully native and offline.
The OpenAI profiles use deterministic in-guest fixture credentials and
transports; they never contact OpenAI or require a developer API key.

The substrate and lifecycle regressions also have focused production-emulator
drivers:

```bash
python3 local_testing/test_guard.py
python3 local_testing/test_vfs_replace.py
python3 local_testing/test_explorer_transactions.py
python3 local_testing/test_applet_close.py
```

The applet-close driver deliberately isolates the guarded APP-SHELL contract;
run the `desktop` and `desktop-agent` profiles for the full linked Desk
lifecycle.

The default Desk Practice validator is structural. CRC and record validation
detect corruption and torn envelopes, but do not authenticate a hostile
replacement or validate a manifest/schema object graph. The development image
may provision a blank Practice only when both slots are genuinely absent; this
is bootstrap fixture behavior, not secure Practice enrollment. The current
recovery profile proves fail-closed startup, not an inspection or repair
console.

`CBR-SIZE` is 512 bytes and includes the semantic resource ID plus the typed
operand seal's canonical length, SHA3-256 digest, and seal state. A zero
resource ID is the legacy/non-lens default. Precompiled code that allocates an
older request-record size must be rebuilt.

MP64FS test images support 15 through 8192 sectors. The guest derives a one- or
two-sector allocation bitmap from media capacity, and the directory and data
starts follow that bitmap uniformly. Profiles declare their required media
capacity; the complete Desktop family uses 8192 sectors while smaller focused
profiles retain the 4096-sector default. Focused profiles may omit unrelated
large-file fixtures, but they must not omit production modules or resources in
their declared scope. Generated images also omit non-executable blank/comment
lines; production source and the declared component set remain unchanged.

## Opt-In Live Network

The live profiles require a user-owned TAP interface. From the workspace root,
the setup script creates or reuses `mp64tap0`, enables forwarding and
masquerading, and then exits:

```bash
sudo local_testing/setup_codex_live.sh
```

The Streams live-public profile uses the native cooperative open, close, and
cancellation callbacks. It is a focused component journey, not by itself a
full Desk responsiveness journey, and it accepts no app password or other
credential. Its loop yields between adjacent connector phases so an admitted
ARP or DNS response can advance into the next outbound phase without putting
the CPU to sleep prematurely. On 2026-07-16 the exact command below passed with
`STREAMS LIVE PUBLIC PASS checks=23` after 2,309,503,523 emulator steps in
30.72 seconds. This is the final-tree revalidation after general ticket
extension-uniqueness and loader exception-cleanup hardening:

```bash
python3 akashic/local_testing/akashic_tui.py smoke \
  --profile streams-live-public --nic-tap mp64tap0 \
  --max-steps 5000000000 --timeout 300
```

The chronological failure analysis and final bounded report are retained in
`local_testing/evidence/streams-live-public-20260716.md`. The successful run
keeps certificate and hostname verification enabled. It accepts bounded,
authenticated TLS 1.3 `NewSessionTicket` messages without implementing or
claiming session resumption; unsupported post-handshake messages still fail
closed.

The separate Codex TLS gate authenticates both source-pinned hosts with the
native KDOS TLS stack but sends no application request:

```bash
python3 akashic/local_testing/akashic_tui.py smoke \
  --profile codex-live-tls --nic-tap mp64tap0 \
  --max-steps 5000000000 --timeout 300
```

The Codex source provisions Google Trust Services WE1 as two exact-host
anchors: `auth.openai.com` and `chatgpt.com`. It does not trust `openai.com`,
`api.openai.com`, arbitrary subdomains, or unrelated services. The anchor is
valid through 2029-02-20; certificate/algorithm rotation must be handled as an
explicit reviewed update, not an automatic network download.

The live gate uses MegaPad's standards-only public ClientHello. Private
MegaPad hybrid suites and groups are not offered to OpenAI endpoints. On
failure, the report includes both Akashic's broad transport error and KDOS's
native handshake-phase status, plus a bounded TAP frame trace.

After that keyless gate, the focused device-flow probe can be kept alive for a
browser authorization run:

```bash
python3 akashic/local_testing/akashic_tui.py serve \
  --profile codex-live-auth --nic-tap mp64tap0 \
  --socket /tmp/akashic-tui.sock
```

The `desktop-codex-live` smoke journey automatically focuses Agent, opens F9,
starts login, and verifies that the guest reaches the displayed-code state.
Use `serve` for a watched login that must continue through browser completion,
catalog discovery, and conversation.

## Shared Live Environment

Start the machine owner:

```bash
python3 local_testing/akashic_tui.py serve \
  --profile desktop --socket /tmp/akashic-tui.sock
```

For native Codex account access after the credential-free gate passes:

```bash
python3 local_testing/akashic_tui.py serve \
  --profile desktop-codex-live --nic-tap mp64tap0 \
  --socket /tmp/akashic-tui.sock
```

Attach the viewer from the workspace root in another terminal:

```bash
python3 megapad/session_viewer.py \
  --socket /tmp/akashic-tui.sock \
  --font akashic/assets/fonts/DejaVuSansMono.ttf \
  --title "Akashic TUI"
```

The viewer and automation clients share the same guest. Control it with:

```bash
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock status
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock network
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock forth \
  _ASHELL-LAST-TICK DESK-DESC
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock peek 0x1000 4
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock key alt+1
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock send "hello"
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock resize 120 36
python3 megapad/session_ctl.py --socket /tmp/akashic-tui.sock capture \
  --text akashic/local_testing/out/live.txt \
  --json akashic/local_testing/out/live.cells.json \
  --png akashic/local_testing/out/live.png
```

In the agent desktop profiles, `Alt+1` focuses Pad, `Alt+2` File Explorer,
`Alt+3` Daybook, `Alt+4` Grid, and `Alt+5` Agent. `Ctrl+Space` or `Alt+A` opens
Desk's global agent prompt. Desk's other shortcuts remain documented in
`docs/tui/applets/desk/desk.md`.
In Agent, F8 opens provider-neutral model/run settings and F9 opens account
access. For the direct API provider, `Ctrl+K` opens masked credential entry and
`Ctrl+Shift+K` clears the active credential. Codex device login shows an
external verification URL and one-time code; it does not require a guest
browser or an API key.
Bare F1-F12 keys are forwarded to the guest. Viewer controls use `Ctrl+F5` to
pause/resume, `Ctrl+F10` to pause and step one instruction, `Ctrl+R` to reset,
and `Ctrl+Q` to close only the viewer. Combined guest shortcuts such as
`Ctrl+Shift+S` are encoded with CSI-u and work from both the viewer and
`session_ctl.py`.
