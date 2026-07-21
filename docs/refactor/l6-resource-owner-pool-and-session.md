# Refactor Landing L6 resource-owner pool and retained resource session

Landing L6 extracts the repeated semantic-resource lifetime and client-session
machinery already proved by Library, Daybook, and Pad. It changes code
distribution and lifecycle implementation while preserving those applets'
current products, capabilities, storage rules, limits, and user journeys.

This is the last foundational extraction before the separately reviewed
ecosystem re-homing and data-scale landings. It does not add an applet, replace
an applet, redesign Library or Daybook storage, increase a dataset bound, or
begin Game, Worlds, SoundLab, Streams, or later MediaLab work.

## Neutral owner-pool boundary

`interop/resource-owner-pool.f` supplies a caller-owned, bounded owner root.
Each concrete owner provides its Context/component/resource registries,
external slot and lease arrays, owner data, and three contained callbacks:
locator admission, component-descriptor selection, and concrete-state
initialization. The callbacks retain all resource meaning and policy.

The pool owns only the repeated lifecycle mechanics:

- one published component per admitted live RID and a distinct exact token for
  every acquisition;
- component creation, registration and RID-publication rollback;
- generation, cookie, refcount, lease, inflight and closing-state accounting;
- forged, copied, malformed and stale-token refusal;
- bounded slot/lease capacity without eviction or retargeting;
- retryable quiescence and release, including exact token preservation after a
  cleanup failure; and
- final unpublication, deregistration and component destruction.

Concrete state starts with the neutral member prefix. Handler begin/end scopes
validate and pin that member against its exact pool in constant time; ordinary
dispatch does not deep-walk the registry or every pool slot. The slower deep
graph checks remain lifecycle, attachment, and diagnostic work. Independent
pools keep their own handler scopes, so one resource pool does not serialize or
select another.

Lifecycle/control-plane operations still use one bounded module scratch
trampoline and therefore serialize across pools; owner callbacks must not
recursively enter `ROPOOL` control-plane APIs on the same or another pool. This
does not put a shared scratch lock on the per-pool O(1) handler begin/end path
or add a corpus-sized scan to request dispatch. L6 records that remaining
lifecycle-throughput boundary instead of treating the request hot-path
improvement as a general concurrency claim.

The same module defines `ROFFER`, the activation-local discovery descriptor for
one named resource. A concrete owner initializes its own offer storage with one
exact RID and that RID's owning pool, then lends it through the named resource
service. There is no global “current pool” service. Consumers validate and copy
the offer fields before retaining the resource and never retain the offer
pointer; discovery alone grants no authority.

## Retained client-session boundary

`interop/resource-session.f` supplies caller-owned `RSES` state. An endpoint-
backed session validates the active Context, resource registry and request bus,
looks up exactly the named resource service, copies its valid offer, and
retains that RID with `ROPOOL-ATTACH` before borrowing the owner instance.
Incomplete or contradictory runtime wiring becomes `BLOCKED` and never falls
open to ambient VFS access. An applet instance without an endpoint remains the
explicit `DIRECT` control path.

The session owns its RACQ token, exact authoritative `LBIND`/`RREF`, one request
envelope, and optional candidate binding. It accepts the owner's existing
snapshot/replace capabilities without normalizing their schemas. Its optional
`RCLI` arm is enabled only for the complete exact canonical RCON descriptor
set; Daybook's compact null-to-string/string-to-bool protocol stays unchanged.

Candidate attach/commit supports Pad's transactional resource switch. `STALE`
is sticky until an explicit refresh or valid candidate commit. If an owner
mutation commits but local binding advancement fails, the session reports
committed-stale, discards the unusable local binding/reference, and retains the
token so refresh can recover without repeating the durable mutation. A release
failure likewise preserves the exact request, binding, and token for retry.

## Proving conversions and deletion

Library's projection owner embeds the neutral pool and supplies its existing
eight RID slots and 64 leases. The adapter still owns Library admission,
managed-document/capture descriptor choice, exact retained-history
qualification, storage status, media/UTF-8 policy, and commit order. Only
component/lease/publication/quiescence machinery moved out of Library.

The Daybook document owner uses a one-slot, 64-lease pool and holds its normal
activation anchor. `SDOC-SERVICE` lends its owner-held offer to Desk;
`SDOC-POOL` is a direct composition/diagnostic word, not a Desk service. Desk
still installs exactly eleven named services, with
`org.akashic.resource.daybook` returning the offer rather than a bare RID.
Desk remains the host and Daybook remains the semantic owner inside the Desk
applet ecosystem; this extraction does not create a separate Daybook product.

Daybook and Pad replace their duplicate resource-client state with `RSES`.
Their snapshot, replace, exact-revision, reload, stale-write, post-commit,
export, blocked-runtime, direct-mode, UI, and error behavior remains intact.
The previous Daybook-specific client module is deleted only after these focused
and linked journeys pass; no facade or parallel implementation remains.

## Functional and scale boundary

The touched L1 groups are Library query/projection, Daybook resource ownership
and model/source behavior, Pad's shared-resource editing, and Desk's service
composition/resource journey. L6 closes Daybook's post-commit binding-advance
prerequisite by proving that one committed mutation is recoverable without
being repeated.

The landing improves bounded lifetime work and removes per-request whole-graph
validation, but it is not the later dataset-scale redesign. Library's current
128 catalog entries, eight live projections, 64 leases, 64-KiB content bound,
fixed storage layout and query pages remain unchanged; Daybook's one live
document and 64 leases remain explicit owner capacities. No storage migration,
format-version layer, compatibility implementation, or ext4 prerequisite is
introduced.

## Qualification

The final landing records exact counts and guest steps in this table after all
production files and linked images freeze.

| Command or profile | Result |
| --- | --- |
| `resource-owner-pool-contracts` | 282 assertions; 442,734,192 guest steps |
| `resource-session-contracts` | 231 assertions; 556,673,574 guest steps |
| `gate3a-resource-contracts` | 529 assertions; 510,293,563 guest steps |
| `resource-contracts` | 133 assertions; 310,827,367 guest steps |
| `library-projection-owner-contracts` | 723 assertions; 4,149,593,096 guest steps |
| `library_projection_two_boot.py` | two-process cold acceptance PASS |
| `shared-document-contracts` | 151 assertions; 730,599,935 guest steps |
| `daybook-shared-lens-contracts` | 101 assertions; 1,935,758,857 guest steps |
| `desk-shared-document-contract` | 105 checks across two launches plus shutdown PASS; 3,032,319,447 guest steps |
| `daybook-contracts` | 140 assertions; 1,877,832,146 guest steps |
| `pad-resource-contracts` | 159 assertions; 2,276,595,116 guest steps |
| `pad-contracts` | 260 assertions; 2,904,503,019 guest steps |
| `desk-service-table-contracts` | 91 assertions; 2,901,919,375 guest steps |
| `desktop-resource` | linked journey PASS; 7,339,000,000 guest steps |
| `desktop-agent-hardening` | linked journey PASS; 16,700,000,000 guest steps |
| host architecture/functional/packaging/VFS gate | 205 pytest cases plus both reviewed ratchet checks passed |

The owner-pool fixture directly covers publication and attachment rollback,
callback throws, invalid descriptor initialization, offer validation and
aliasing, distinct and shared RIDs, capacity, anchors, forged/copied/stale
tokens, generation reuse, inflight close, quiescence, retryable release,
malformed members, exact stack balance, and independent pools. The session
fixture covers direct/blocked/active/stale modes, two named offers routing to
two different pools, offer-pointer non-retention, compact and canonical
descriptors, candidate switching, stale refresh, committed-stale recovery, and
retryable finalization. Its initialization adversaries additionally put the
output behind malformed offer, pool, ledger, Context, CREG, registry, bus and
policy pointers and require byte-for-byte nonmutation. Counted callbacks prove
that all three runtime services and the named offer are each queried exactly
once, with the named offer last so no later endpoint callback can exchange the
checked discovery value.

## Ratchet and exit rule

The frozen architecture inventory contains 386 modules, 1,308 resolved
`REQUIRE` occurrences and 1,308 unique resolved edges. It has 78 reviewed
unresolved imports, no dependency cycles, seven existing target-layer
violations, 39 placement-debt modules, two provided-name issues, one
addressability issue, and no generic completion markers. Its graph, reviewed
state, and placement digests are respectively
`d5783340b00f35a60d8adfa1b34052bac03bcafa34e29662b689d0c8b65fa7e5`,
`3d62627065e838443a98b3fa17951fa2482d7a5a7306ceb0dbf84e542f6a2089`,
and `12e80168718dceb99dc12f99af627a22df4fd15ce8356c0b4078cd2e0d129870`.

The class totals are 62 applet modules / 48,004 lines / 2,729 lexical globals,
59 Desk-ecosystem modules / 24,138 lines / 1,100 lexical globals, and 265
independent modules / 128,735 lines / 7,075 lexical globals. Relative to L5,
the applet lexical total falls by 29 while the independent total rises by 18.
The functional ratchet still describes nine applets and 29 journey groups:
11 covered, 16 partial, two prerequisite-only, with 23 prerequisites and 109
evidence entries.

The architecture ratchet classifies both neutral modules as independent and
keeps Library and Daybook policy applet-owned. The old Daybook-specific client
dependency is absent, Desk retains its exact eleven service IDs, and no neutral
module imports an applet or embeds Library/Daybook meaning. The deletion of the
old lens target reduces placement debt from 40 to 39; no target-layer
violation, unresolved-import decision, identity issue, addressability issue,
dependency cycle, storage format, corpus bound, or ext4 dependency changes.

The landing is complete only when the focused owner/session fault gates,
Library cold-process acceptance, Daybook/Pad/Desk functional journeys, both
reviewed ratchets, and the complete host gate are green together. L6 then stops
for review before any L7 ecosystem re-homing begins.
