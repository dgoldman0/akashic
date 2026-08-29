# Desk, Library, and Rabbit Burrow checkpoint 4

**Drafted:** 2026-08-09

**Contract:** [`desk-library-burrow-checkpoint0.md`](desk-library-burrow-checkpoint0.md)

**Status:** qualified on 2026-08-12; product journey, persistence evidence,
supporting regressions, architecture ratchets, and canonical Desktop reserve
are green

Checkpoint 4 composes the already-qualified Desk/Practice/Agent control plane,
Library capability owner, and Streams Burrow lifecycle into one focused product
profile. The qualifying journey must go through the normal Desk catalog,
applet lifecycle, Agent Tool Gateway, review UI, capability bus, live component
instances, human Library and Streams views, and ordinary Desk close. A fixture
may supply a deterministic Scripted provider, caller-owned Burrow storage, and
bounded observation hooks; it may not call Library capability handlers or the
Streams manager directly and may not replace rendered product behavior with a
renderer-free assertion.

This checkpoint consumes the Checkpoint-1 through Checkpoint-3 contracts. It
does not add Rabbit request framing, Library-backed Rabbit `LIST`/`FETCH`, or a
Rabbit peer facet. Those remain Checkpoint 5 work.

## Exact focused composition

The permanent focused profile is `desktop-library-burrow`, on the existing
8,192-sector MP64FS geometry. It links these roots in this order:

1. `tui/applets/desk/desk.f`
2. `tui/applets/library/library.f`
3. `tui/applets/streams/rabbit-capabilities.f`
4. `tui/applets/streams/streams.f`
5. `tui/applets/agent/agent.f`
6. `tui/applets/agent/providers/devtools/scripted.f`

It carries the normal Desk, Library, Streams, and Agent UIDL/configuration
resources and the two test-only guest leaves
`local_testing/streams-burrow-prov.f` and
`local_testing/desk-library-burrow.f`. It excludes the unrelated large sample,
and it adds no Rabbit framed client or Rabbit-client shortcut. Because the real
Streams applet is part of the composition, its ordinary product dependencies
remain in the linked closure; Checkpoint 4 makes no network-transport claim
from their presence.

The Rabbit capability root and boot `REQUIRE` must precede `streams.f`.
Streams selects its Rabbit-capable 19-descriptor build at load time only when
that optional extension is already present. Reversing the order would silently
select the ordinary 15-descriptor build and cannot be repaired after the fact.
The canonical Desktop remains on that ordinary 15-descriptor boundary and does
not acquire the Rabbit closure or change its 2,048-sector free-space reserve.
The later secure-network integration preserves that same component and reserve
contract by storing the canonical Desktop's Akashic source in the checked
`AKSRC001` stored-source representation on its 32 MiB MP64FS volume. Every
module is still compiled from source at boot; this is not a compiled
dictionary cache.

The profile provisions a normal Practice head only on blank qualification
media. It then registers and queues exactly three real applet descriptors
through `DESK-QUEUE-LAUNCH`, in this order:

| Slot | Applet entry | Exact component target |
| ---: | --- | --- |
| 1 | `LIBRARY-APPLET-ENTRY` | `org.akashic.library.applet` version `0.1.0` |
| 2 | `STREAMS-ENTRY` | `org.akashic.streams` version `0.5.0` |
| 3 | `AGENT-ENTRY` | `org.akashic.agent` version `1.0.0` |

Library and Agent keep their normal lifecycle callbacks. The Streams
descriptor wraps only initialization to bind the caller-owned Burrow pools and
borrowed deterministic provider before delegating once to `STREAMS-INIT-CB`;
the normal Streams tick, request-close, and shutdown behavior remains in
force. All three applets must be live before the Agent mandate is frozen.

## Live focused authority

After all three applets are live, the normal Desk mandate factory must produce
the following exact facets. The witness checks both membership and each frozen
entry's resolution back to the expected live component instance and
generation.

| Access preset | Exact live rows | Tool budget | Required operations |
| --- | ---: | ---: | --- |
| Chat only | 0 | 0 | none |
| Practice read only | 4 | 4 | `streams.source.query`, `streams.source.read`, `library.status`, `streams.burrow.status` |
| Practice assist | 6 | 8 | the four read rows plus `library.document.create` and `library.collection.create` |
| Practice Library Burrow | 9 | 12 | the six assist rows plus `streams.burrow.create`, `streams.burrow.start`, and `streams.burrow.stop` |

The operator preset is exactly `desk.practice-library-burrow`. Its catalog
allowance is `OBSERVE|NAVIGATE|MUTATE|PERSIST`; after the mandate factory
intersects that allowance with the nine operations actually present in this
focused composition, the frozen live facet's exact effective effects are
`OBSERVE|MUTATE|PERSIST`. Its disposition is commit, and it has no `EXTERNAL`
or destructive effect. The two Library mutations and three Burrow mutations
require review. Assist never receives a Burrow mutation.

The following absences are part of the live witness, not merely catalog-source
inspection:

- `library.document.query` and `library.document.read` are absent from every
  ordinary Agent facet;
- `streams.draft.publish` and `streams.source.refresh` are absent from this
  focused composition;
- Assist lacks Burrow create, start, and stop;
- Read lacks both Library creates and all Burrow mutations; and
- no focused facet contains an `EXTERNAL` effect.

The preflight mandate runs are freed immediately. The human-triggered Agent
turn freezes a fresh nine-entry operator facet and consumes eight of its
twelve-call budget. The four unused calls remain bounded retry/status allowance
and are not manufactured into extra product behavior.

## Exact eight-call result chain

The Scripted provider emits one single-flight sequence through Agent's normal
event queue and gateway. Each call has a distinct call ID, receives a typed
result from the capability bus, and copies only the fields needed by the next
call before the borrowed result is released.

| Call | Capability | Reviewed | Required result dependency |
| ---: | --- | :---: | --- |
| 1 | `library.status` | no | Captures the authoritative initial logical generation. |
| 2 | `library.document.create` | yes | Uses call 1's generation; captures the document resource and post-create logical generation. |
| 3 | `library.collection.create` | yes | Uses call 2's generation and the document resource as its one member; captures the collection resource, domain revision, post-create logical generation, and request digest. |
| 4 | `streams.burrow.create` | yes | Uses the exact collection resource/domain revision/request digest, `library-read-v1`, `memory-duplex`, and peer capacity one; captures the configured Burrow resource and revision. |
| 5 | `streams.burrow.start` | yes | Uses the Burrow resource and call 4's revision; captures the truthful `starting` revision. |
| 6 | `streams.burrow.status` | no | Runs after normal Streams ticks advance provider acquire/open; requires `running`, the same Burrow resource, and peer count one. |
| 7 | `streams.burrow.stop` | yes | Uses the Burrow resource and call 6's revision; captures the truthful `stopping` revision. |
| 8 | `streams.burrow.status` | no | Runs after normal Streams ticks advance cancel/finalize/release; requires `stopped`, cleanup not pending, and peer count zero. |

Exactly five review screens are therefore approved: document create,
collection create, Burrow create, Burrow start, and Burrow stop. Status calls
remain observations. The harness must validate canonical operands in the
ordinary Agent review screen and approve through the visible `F6` path; it may
scroll a long review before approval but may not bypass review state.

The collection scope carried into Burrow create is the exact output of the
Library owner. The fixture must not synthesize a replacement resource,
revision, or request digest. Likewise, start and stop expected revisions and
both status probes form one truthful manager revision chain rather than a set
of unrelated fixture expectations.

## Human product path

Qualification starts from the rendered Desk with visible Library, Streams,
and Agent tiles. Normal `Alt+number` focus shortcuts select each live applet.
The human path is:

1. focus Agent, open its prompt with `Ctrl+L`, submit the Library Burrow
   request, and approve the document, collection, Burrow-create, and
   Burrow-start mutation reviews with `F6`;
2. after the first Burrow status result and while the pending Burrow-stop
   review still holds the lifecycle at `running`, focus Streams, open the
   Burrow view with `Ctrl+B`, and observe that live state and exact collection
   scope;
3. return to Agent, approve the fifth review for Burrow stop, and after stop
   completes revisit the same Streams view and observe `stopped`,
   no cleanup pending, and zero peers;
4. focus Library, use `Ctrl+R` for an authoritative reload, and observe the
   Agent-created document and content;
5. use the ordinary Collections view shortcut and observe the Agent-created
   collection; and
6. request outer Desk close only after those visible assertions complete.

The focused harness's `F12` input is only a bounded trigger that posts the
outer `ASHELL-QUIT` action. It is not a child close shortcut. Desk must then run
its normal request-close negotiation, child shutdown, Agent provider release,
and Practice finalization. Each of Library, Streams, and Agent must shut down
exactly once. Streams shutdown must leave no provider lease, zero the supplied
declaration and replay pools, and release its component instance. The provider
and provider source must be freed, and the fixture's total allocator-available
baseline—including MP64 XMEM free-list blocks—must be recovered. A direct host
session close or a fixture call to an owner shutdown callback is not teardown
evidence.

Renderer-free checks may ratchet profile roots and preload order, catalog
membership, review flags, facet negatives, call ordering, and the ban on
direct owner/manager calls. They are supporting structural evidence only. The
rendered focus, review, Library reload, Streams Burrow views, and Desk teardown
above remain mandatory product evidence.

## Caller-owned fixture geometry

The focused journey supplies one aligned declaration row and three aligned
replay rows to `STREAMS-BURROW-COMPOSITION-STATE!`, together with one
deterministic opaque provider state. The three replay rows correspond exactly
to the create, start, and stop mutations. Declaration capacity one, replay
capacity three, and the requested peer capacity one describe only this bounded
witness. They are not product constants and do not change the manager's
caller-sized storage contract.

The supplied spans must be nonwrapping, nonoverlapping, and separate from the
Streams applet state and provider. The fixture may inspect those owned spans
after normal shutdown to prove cleanup; it may not drive `SRBMGR-MUTATE`,
`SRBMGR-TICK`, `SRBMGR-QUIESCE`, or any owner capability handler. Normal Desk
ticks are the only driver for start and stop progress.

## Persistence headroom rule

Build fit alone is insufficient. The product runner observes the in-memory
MP64FS image after completed write effects and takes named stable samples at
the built image, Desk-ready state, each tool result, both Streams views, both
Library views, ordinary Desk teardown, and the saved final image. A transient
filesystem view during a multi-block commit is counted and ignored rather than
treated as a valid sample; every named milestone must parse as a valid MP64FS
image.

Let:

- `B` be free sectors in the built focused image;
- `M` be the minimum valid free-sector observation across the entire journey;
- `F` be free sectors in the saved final image; and
- `L` be the largest positive decrease between consecutive named stable
  samples.

The reported observed peak persistence consumption is `B - M`; retained
consumption is `B - F`. Qualification requires `M > L`, so the measured
minimum headroom can absorb one more persistence increment at least as large
as the largest one actually observed. This is an evidence-derived bounded
rule, not a new product capacity or a substitute for the canonical Desktop
reserve. If the inequality does not hold, Checkpoint 4 stops without claiming
honest persistence headroom. The canonical 2,048-sector reserve, 8,192-sector
geometry, emulator timing, and native scheduler remain unchanged.

The first human-readable fixture (`Note` / `café`) completed the whole UI and
owner journey but failed this rule with `M=126` and `L=373`; it is retained as
diagnostic evidence, not a pass. The qualified composition uses the smallest
still-visible UTF-8 document witness, title `N` and content `é`. This keeps the
same owner operations, five reviews, collection, Burrow revision chain, UI
reload, and ordinary close while avoiding a payload-size claim from this tight
focused image. Checkpoint 1 remains the separate evidence for the capability's
larger request boundaries.

## Integration hardening found by the journey

Qualification exposed four production defects that smaller owner tests did not
exercise together:

- Desk's built-in queue helper leaked one constructor-row pointer on every new
  built-in. Removing the stray duplicate restores stack-neutral queueing,
  including the full-table refusal path.
- Desk interop initialization retained the prompt region once, and interop
  finalization retained the capability bus once. Removing those two duplicates
  returns the shell data stack exactly to its entry depth.
- Full-frame paint policy previously hid peers without expanding the focused
  child. Desk now assigns the whole usable area to focus while peers remain
  live on ordinary tiles, and generic host hit-testing gives the overlapping
  focused region pointer priority.
- The old UIDL four-context arena and direct screen bump allocations predated
  MegaPad's reclaiming XMEM-aware `ALLOCATE`/`FREE` path. UIDL contexts, screen
  descriptors, and screen buffers now use that public owner path directly;
  resize is transactional, destruction releases both buffers, and the former
  arbitrary sixteen-context ceiling is gone.

Focused host evidence allocates and frees 17 contexts, resizes and destroys a
screen, exercises overlapping full-frame focus, and checks exact Bank 0/XMEM
recovery. Desk characterization separately checks exact stack, heap, and XMEM
baselines after normal shell teardown.

## Qualification record

| Evidence | Result | Guest steps / host wall | Build or persistence measurement |
| --- | --- | --- | --- |
| Static product/profile contract | PASS | 0.30 s host | n/a |
| Focused profile build | PASS | Included in product run | 185 modules / 27 chunks, MegaPad networking, 4 resources, 8 directories, 48 entries; `B=901` free sectors |
| Composed source-mode product journey | PASS | 17,248,995,260 steps / 523.56 s | `B=901`, `M=462`, peak consumed 439, `L=153`, `F=630`, retained consumed 271 sectors; `M > L` PASS; 1,333 valid completed-write samples |
| Host packaging and focused-product checks | PASS | Packaging 67 tests / 4.15 s; host 979,591,183 steps / 24.52 s; Desk characterization 4,511,275,329 steps / 102.49 s; Desk close 4,528,135,938 steps / 103.31 s | Exact queue-stack, shell-stack, allocator-recovery, full-frame, and architecture ratchets green |
| Canonical Desktop rebuild | PASS | 0.80 s host build | 185 modules / 22 chunks, MegaPad networking, 10 resources, 11 directories, 51 entries; 2,127 free sectors, 79 above reserve |

The heavyweight product journey must be explicitly approved and run alone on
one timing-correct native core. All other smoke, integration, and persistence
tests remain sequential. No checked-in step ceiling may be raised merely to
obtain a result; any justified ceiling change must record the old and new
values and the measured bounded progress.

## Checkpoint 5 boundary

Checkpoint 4 ends at a locally running and then cleanly stopped opaque Rabbit
Burrow whose declaration is scoped to the Library collection. It does not
send or receive a framed Rabbit request and does not prove Library data flows
through that transport.

Checkpoint 5 alone may add the framed Rabbit `LIST`/`FETCH` client and server
routing, exact response bounds, deterministic memory-duplex exchange, and the
least-authority Library peer facet containing `library.document.query` and
`library.document.read`. Those operations must not be smuggled into the
ordinary Agent facet, Scripted provider, Checkpoint-4 fixture, or visible
status proof. This checkpoint also makes no TLS, physical-network, durable
Burrow, MegaPad, or canonical full-Rabbit image-admission claim.

## Exit

Checkpoint 4 is complete only after the focused product journey and its
supporting gates are green sequentially, the qualification table contains
measured values, the evidence-derived headroom inequality passes, the
canonical Desktop reserve remains green, and normal Desk teardown is observed.
Until then this document records the contract and pending qualification shape,
not a completed checkpoint.
