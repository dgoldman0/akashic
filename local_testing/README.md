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

## Build And Smoke Test

```bash
python3 local_testing/akashic_tui.py build --profile desktop
python3 local_testing/akashic_tui.py smoke --profile desktop
```

Smoke and served sessions use 32 MiB of emulated external memory by default.
This leaves realistic headroom for the userland dictionary and applet working
sets as the Desk image grows; pass `--ext-mem-mib N` to test another budget.
The default smoke gate permits 8 billion guest steps and 120 seconds so the
complete linked Desktop can compile the canonical loadable networking module
and still reach its ready markers. The exact no-override command passed at 6.9
billion guest steps in 92.18 seconds on 2026-07-16. Focused profiles stop as
soon as their own markers stabilize; `--max-steps` and `--timeout` remain
available for explicit qualification budgets.

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

`gate2a-contracts` isolates the policy-neutral memory-span predicates and the
caller-owned scalar/locator schema initializers. It covers signed-length and
unsigned-wrap boundaries, empty/null policy separation, half-open overlap, exact
schema bytes, UTF-8/type/length rejection, and the distinct 110-byte semantic
RREF and 516-byte VFS-locator text bounds.

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
summary. Milestone three still does not claim projection lifecycle,
repair/export, the complete damage matrix, an applet/UI, or overall Gate 4 exit.

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
