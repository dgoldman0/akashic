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
Library's projection two-boot gate. None of these checks requires ext4. See
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
```

`test_vfs_ext4.py` then mounts those same images through the clean read-only
ABI-1 binding.  It covers checksummed linear and HTree directories, depth-1
real external extents and bounded traversal through the profile depth limit,
legacy direct/single/double/triple maps, allocation-bitmap cross-checks,
special-inode metadata and unsupported opens, namespaced/raw-ACL xattrs, and
bounded generic symlink traversal including a live block-backed target.  Its
corruption cases include HTree and extent-node checksums, allocation
disagreement, and duplicate/overlapping xattr records.  Journal replay,
orphan recovery, ACL enforcement, and every mutation operation remain outside
this read-side gate.  This remains an explicit-volume emulator suite rather
than a default boot-image or automount profile.

When a resolved profile closure binds directly to MegaPad networking, the
harness injects the one canonical packed `networking.f` and loads it with
KDOS `REQUIRE` immediately after `ENTER-USERLAND`. This avoids re-entering the
BIOS loader while its KDOS autoboot buffer is still live. Parser-only and
abstract-I/O profiles omit networking. The system module is neither renamed
nor linked into an Akashic deployment chunk.

The authoritative profile registry and each journey's assertions live in
`akashic_tui.py`; `--help` lists the accepted profile names. Profiles are
organized around focused library/runtime contracts, standalone applet journeys,
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

`library-model-codecs-contracts` qualifies the foundational caller-owned Library
model and its catalog, collection, and immutable content-revision records.
`library-store-format-contracts` qualifies the foundational VFS-free arena,
complete-bank, and head formats: fixed geometry, exact wire CRC/SHA3 vectors,
checksum-before-future dispatch, hostile aliases and nonmutation, duplicated
cross-seals, and the absolute-offset ordered content-frame chain. Neither
profile selects paths, performs VFS I/O, publishes resources, or imports an
applet or sibling domain.

`library-vfs-store-contracts` qualifies the foundational VFS-owner slice. It
proves the private four-file topology and sole-head commit point, exact
selected-bank/arena/content validation before fact publication, committed-tail
and inactive-bank isolation, absent first-use full readback, same-arena
idempotency, different-arena conflict, post-bank/pre-head orphan refusal,
receipt-to-initial-content consistency, future/corrupt ordering, and exact
cleanup plus successful retry after injected I/O failure. Public content and
catalog mutation remain outside this profile.

`library-managed-document-contracts` qualifies Gate 4's first implementation
milestone through the public owner API: managed create with a caller operation
key and expected generation, owner RID allocation, content-first/inactive-bank/
sole-head publication, generation-pinned query, exact read, idempotent retry,
mutation-boundary faults, uncertain-head reconciliation, and output isolation.
`library-managed-capacity-contracts` adds valid fully loaded catalog-full,
content-full, and owner-RID-collision snapshots and proves each refusal occurs
before mutation. Run the separate true cold-relaunch acceptance with:

```bash
python3 local_testing/library_managed_two_boot.py --timeout 180
```

That driver starts two spawn-isolated Python processes with one fresh emulator
session each; only serialized MP64FS bytes and the first boot's printed RID
cross the boundary. These profiles establish milestone 1, not the overall Gate
4 exit.

`library-managed-lifecycle-contracts` qualifies Gate 4's second ordered
implementation milestone for managed resources: five exact replacements, the
four-revision logical window and explicit `GONE`, stale refusal, metadata,
including a typed lineage locator, archive/unarchive, archived exact reads,
active-query hide/reappearance, history list/read/compare and diagnostic-status
readback, restore-as-new, public receipt survival, destructive tombstone, and
terminal same-key non-reuse. `library-capture-collection-contracts` qualifies
exact VFS capture provenance and copied bytes, negative managed-replacement
refusal, same-key retry/mismatch, distinct-key identical imports, operation-key
versus RID collision refusal, RID-only collection create/retry/read/replace,
stale collection refusal, collection-removal versus deletion, archive
preservation, and tombstone behavior without rewriting membership.

Run the milestone-two cold acceptance with:

```bash
python3 local_testing/library_lifecycle_two_boot.py --timeout 600
```

The first spawn-isolated guest creates a managed document, advances it through
five replacements and archive, imports a capture, and creates a two-member
collection. Only the serialized MP64FS bytes and the three printed RIDs cross
to the second process. Its fresh guest verifies generation, archived current
bytes, retained revisions and `GONE`, both receipts, exact capture
origin/content, and collection membership. These milestone-two profiles and
driver do not themselves exercise the separately qualified disposable index,
projection lifecycle, repair/export, complete damage matrix, or overall Gate 4
exit.

`library-query-index-contracts` qualifies Gate 4's third ordered milestone. It
proves bounded exact UTF-8 title/body/tag search, empty-term browse,
active/archived, kind, media, and exact collection-RID filters, deterministic
raw-slot continuation, collection enumeration, current-body replacement,
tombstone exclusion, stale generation refusal, over-capacity output nonmutation,
and stale-conflict output clearing. It also destroys and damages the
activation-local index, then proves byte-identical
authoritative result pages after rebuild while head, bank, arena, and generation
facts remain unchanged.

Run the milestone-three cold acceptance with:

```bash
python3 local_testing/library_query_two_boot.py --timeout 600
```

The first guest creates three catalog-ordered resources whose common term is
found once in a title, once in a current body, and once as an exact tag, plus a
collection spanning active and archived entries. Only serialized MP64FS bytes
and printed stable RIDs cross to a fresh spawned process. The cold guest rebuilds
the disposable index from authoritative records and proves the same ordered
2+1 corpus pages, field/lifecycle/kind/media/collection filters, and collection
summary. That milestone-three profile does not by itself claim projection
lifecycle, repair/export, the complete damage matrix, an applet/UI, or overall
Gate 4 exit.

The milestones 1–3 efficiency rework extends the query and capacity contracts
with warm-authority, direct-frame, index-loss/damage, full-head-change,
distinct-store replacement, 32×4 KiB, 64 KiB, and exact-full 128-identity
evidence. Run the apples-to-apples MP64FS profiler with:

```bash
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/library_query_efficiency.py --timeout 600
```

For each empty, one-64-KiB, and 32×4-KiB corpus, setup and profiling run in
separate spawn-isolated processes with only serialized disk bytes crossing the
boundary. `PERF-CYCLES` is the exact acceptance metric; host event timing is an
approximate 250,000-step sampled wrapper, and whole-phase timing includes boot
and compilation plus the small measurement handshakes. The driver enforces the
handoff's fixed 5× warm-path and 10% cold-load cycle gates at 32×4 KiB. Tag
hit/miss coverage lives in
`library-managed-capacity-contracts`, whose synthetic corpus can set exact
catalog tags without doubling the public-mutation setup time.

The printed 100 MHz and 50 MHz values are clock-rate projections, not measured
FPGA latency. The emulator currently reports zero modeled stalls and does not
model shared-BRAM arbitration, 6–10-cycle external-memory access, or SPI-SD
latency; board synthesis and measurement remain required.

### Gate 4 milestone 4: projection lifecycle

`library-projection-owner-contracts` qualifies Gate 4's fourth ordered
milestone. It links the complete production Library/projection closure in six
top-level chunks; the contract fixture remains an ordinary separately injected
Forth file. Run the focused contract with:

```bash
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/akashic_tui.py smoke \
    --profile library-projection-owner-contracts \
    --max-steps 15000000000 --timeout 600
```

The 723-assertion matrix covers full-root and reachable-span alias rejection,
always-through-root validation, same-RID owner sharing, distinct lease tokens,
failed-`LBIND` rollback, copied/stale-token refusal, retryable release,
dispatch-`BUSY` quiescence, idempotent repeat release, active identity,
immutable exact archived reads, tombstone/pruned terminal behavior, refusal of
ambient-VFS fallback, capture read-only behavior, the eight-owner and 64-lease
bounds, ninth-owner and 65th-lease refusal, slot reuse without retargeting, and
root teardown.

Run the two-process cold acceptance and the bound-scale profiler with:

```bash
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/library_projection_two_boot.py --timeout 600
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/library_projection_efficiency.py --timeout 600
```

The cold driver verifies and reuses the exact linked chunk manifest in two
fresh emulator processes. Only serialized disk bytes plus the printed RID,
domain revision, and digest cross the process boundary; no root, registry,
component, binding, or token state survives. The profiler covers a
representative 128-byte resource, one 64-KiB byte-bound resource, all eight
live owners plus a ninth-owner refusal, all 64 leases plus the 65th refusal,
and successful plus repeated-stale `resource.replace`. It enforces bounded
unchanged-call cost, direct exact-frame reads without arena fallback or index
reconstruction on unchanged calls, the deliberate complete publication
readback on successful replace, and zero modeled stalls. Final measurements
and the clock-model caveat are in
[`evidence/library-projection-owner-20260720.md`](evidence/library-projection-owner-20260720.md).

These results qualify milestone four. Milestone five and the complete Gate 4
exit are qualified separately below; projection tests do not stand in for that
maintenance and damage evidence.

### Gate 4 milestone 5 and complete headless exit

`library-maintenance-contracts` qualifies the caller-owned inspection report,
sealed optimistic evidence token, recognized head-transaction repair, and
bounded opaque raw export. Run it with:

```bash
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/akashic_tui.py smoke \
    --profile library-maintenance-contracts \
    --max-steps 15000000000 --timeout 600
```

The 219-assertion linked profile covers complete healthy V1 semantics; size,
short-buffer, and exact seven-object export; byte/SHA identity; report/output
alias rejection; read, close, and durability failure cleanup; stale evidence;
recognized replacement residue repair and idempotent retry; future and corrupt
heads; and a preserved orphan content suffix. A successful but silently
changed second read is rejected as `CONFLICT` and the entire negotiated output
is zeroed. Future, corrupt, ambiguous, and orphan evidence remains export-only;
repair never guesses or resets it.

Run the literal Gate 4 exit and maintenance cost profiler with:

```bash
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/library_gate4_exit_two_boot.py --timeout 600
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/library_maintenance_efficiency.py --timeout 600
```

The exit driver uses fresh spawned emulator processes with only serialized
MP64FS bytes and printed stable evidence crossing each process boundary. Its
clean relaunch proves an archived managed document with six immutable content
revisions, an active immutable capture, and a distinct tombstoned RID. It then
clones that verified disk and proves fail-closed, byte-preserving maintenance
behavior for a damaged head, damaged selected bank, damaged committed content
frame, and checksum-valid future head. Both the dependency closure and each
generated proof leaf use the linked loader path.

The complete command/result ledger, fixed memory and byte bounds, emulator
cycles, and target-clock interpretation are in
[`evidence/library-gate4-close-20260720.md`](evidence/library-gate4-close-20260720.md).
Together with the preceding focused/capacity profiles and the managed,
lifecycle, query, and projection cold drivers, this satisfies the literal
headless Gate 4 exit. It does not claim the complete Gate 5 applet or any
Desktop, Pad, Explorer, Streams, Agent, or Practice integration.

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
