# Desk, Library, and Rabbit Burrow checkpoint 3

**Qualified:** 2026-08-09

**Contract:** [`desk-library-burrow-checkpoint0.md`](desk-library-burrow-checkpoint0.md)

**Status:** Streams Burrow manager, capability boundary, applet lifecycle, and
focused extension composition complete; Checkpoint 4 is next

Checkpoint 3 gives Streams an activation-local owner for Rabbit Burrow
declarations, replay, cooperative lifecycle, and visible applet control. The
provider/manager core, capability boundary, real Streams callback lifecycle,
ordinary Streams regression, codec regression, and packaging boundary are now
independently green.

## Frozen capability surface

The target remains `org.akashic.streams` version `0.5.0`. The Rabbit extension
owns exactly four descriptors:

| Capability | Kind/effects | Exact request |
| --- | --- | --- |
| `streams.burrow.create` | command; `MUTATE` | `collection:R0`, `collection_domain_revision:REV+`, `request_digest:H64`, `profile:"library-read-v1"`, `transport:"memory-duplex"`, `peer_capacity:REV+` |
| `streams.burrow.status` | resource; `OBSERVE` | `burrow:R0` |
| `streams.burrow.start` | command; `MUTATE` | `burrow:R0`, `expected_domain_revision:REV+` |
| `streams.burrow.stop` | command; `MUTATE` | `burrow:R0`, `expected_domain_revision:REV+` |

All maps are closed and ordered. The common 18-field result remains, in order,
`burrow`, `domain_revision`, `state`, `activation_epoch`, `durable`,
`collection`, `collection_domain_revision`, `request_digest`, `profile`,
`transport`, `security_mode`, `peer_count`, `peer_capacity`, `service_count`,
`cleanup_pending`, `last_status`, `last_detail`, and `operation_receipt`.
Lifecycle state is exactly `configured`, `starting`, `running`, `stopping`,
`stopped`, or `blocked`; `durable` is false, the security mode is
`deterministic-fixture`, and status has a null receipt while mutations return
an exact lowercase `H64` receipt.

The adapter enforces semantic URI revision zero, positive domain revisions,
exact lowercase digests, and the literal profile and transport values rather
than relying on their coarser schema shapes. The encoded maxima remain the
Checkpoint-0 figures:

| Surface | Semantic plain / typed | Schema-wide plain / typed |
| --- | ---: | ---: |
| Create request | 334 / 404 | 1,362 / 1,432 |
| Status request | 105 / 126 | 673 / 694 |
| Start/stop request | 152 / 181 | 720 / 749 |
| Mutation result | 806 / 988 | 2,877 / 3,059 |
| Status result | 744 / 924 | 2,495 / 2,675 |

No descriptor declares `PERSIST` or `EXTERNAL`. The three mutations remain
reviewed authority; status remains observation. The capability-bus canonical
argument ceiling is still 65,536 bytes.

## Provider and manager ownership

`rabbit-provider.f` defines the Streams-owned, transport-neutral borrowed
provider ABI. A composition owns the sealed descriptor, its context, and all
concrete graphs. The callbacks cover acquire, acquire tick, open, service,
cancel, finalize, release, counts, and lease validity. Every nonzero lease is
retained even when a callback reports pending or failure; release failure keeps
it valid, and successful release must invalidate it before the manager drops
the borrowed value. The graph specification carries the exact collection
scope, request digest, and positive caller-requested peer capacity. The ABI has
no hidden product capacity and sanitizes results into the frozen status range
0..12 and detail range 0..14.

`rabbit-manager.f` owns no concrete Rabbit graph, Library object, component
instance, or capability-bus request. Its declaration rows, replay rows, plans,
and result records all use caller-owned storage with validated geometry and no
fixed product row limit. Public declaration rows and the separate replay
journal are append-only for one activation. A stopped declaration retains a
pointer-free tombstone, its Burrow RID is not reused, and its provider storage
can be reclaimed and reused.

Create, start, and stop use transactional plan/commit records. A plan captures
the manager serial and COMMIT refuses a stale plan before mutation. Replay is
classified before an expected-domain-revision check: the same invocation,
operation, canonical argument length, and digest returns `CBUS-S-NO-EFFECT`
with the current truthful public state and historical receipt; an altered
request or operation collision conflicts. The journal is non-evicting and a
slot is reserved before a fresh mutation.

Lifecycle work is cooperative and bounded to one declaration and one provider
phase per tick. The manager opens only after acquire is ready, treats one-shot
OPEN pending as a sanitized open failure with rollback, and never hot-loops a
blocked cleanup. Explicit stop, close, or UI retry can re-enter cleanup. Hidden
phase progress and routine service counts do not revise public state; each
observable state/status change advances the Burrow domain revision exactly
once. Stopped declarations can restart, peer count returns to zero, and the
declared peer capacity remains truthful.

## Capability transaction and Streams composition

`rabbit-capabilities.f` supplies the four exact schemas, descriptors, and
manager adapter. It owns no manager, provider, component instance, or durable
state. A resolver supplies the live activation manager and an invalidator
reports a public owner change. Fresh mutations construct and deep-validate the
complete typed result in owned scratch before manager COMMIT; construction
failure therefore cannot mutate the manager. A fresh successful commit touches
the component once. Exact replay returns its typed result without a second
commit, touch, or invalidation.

Streams accepts caller-sized declaration and replay pools plus a borrowed
provider through `STREAMS-BURROW-COMPOSITION-STATE!`. It validates the
caller-supplied pool capacities, nonwrapping spans, alignment, and non-overlap
with applet state and the provider; graph specifications separately require an
exact positive peer capacity. Initialization derives the activation epoch from
the live component instance. Tick delegates to the manager and invalidates
applet state only for a public change; close performs one bounded cleanup pass
and retains the close request while a lease remains; shutdown releases the
manager before the rest of Streams authority.

The applet now has a fourth Burrow view with bounded roster selection and
direct start/stop controls. It renders lifecycle state, domain revision,
activation epoch, collection and request seal, peer/capacity/service counts,
cleanup state, and sanitized status/detail. It does not expose raw pointers,
leases, tokens, facets, or provider configuration. Human start/stop actions use
the same transactional manager core as capability mutations.

The integrated boot exposed a compile-time composition defect: placing the
Burrow `[IF]` branch inside the long `_STM-CAP-SETUP` definition produced a
boot-stack underflow in the preloaded extension build. Conditional selection
now happens at top level, where it defines either the full or no-op
`_STM-BURROW-CAP-SETUP`; the ordinary capability setup calls that helper with
normal runtime stack behavior. The lifecycle autoexec retains an immediate
`DEPTH` failure assertion after both linked roots load, so a future module-load
stack regression fails before any lifecycle fixture can mask it.

Checkpoint 3 deliberately binds only the deterministic opaque provider seam.
Actual Library LIST/FETCH routing and the least-authority Rabbit peer facet are
later product-composition work, not evidence claimed here.

## Wide JSON-schema traversal correction

The 18-field result exposed a core traversal defect rather than an invalid
schema. `_IVJSON-SCHEMA-COMPATIBLE-R?` had kept recursion depth on the return
stack and then read `R@` while walking map fields with `DO`. In Forth, `R@`
inside that loop is the loop counter, so a sufficiently late field in a flat
map was misclassified as excessive recursion depth.

The traversal now keeps depth on the data stack and passes `depth + 1` to each
child without using return-stack scratch inside the map loop. A direct
18-required-field flat-map regression proves both `CS-SCHEMA-VALIDATE` and
`IVJSON-SCHEMA-COMPATIBLE?` accept the valid shape. This fixes traversal; it
does not raise the schema depth limit or weaken validation.

## Packaging and immutable capacity boundary

The Rabbit capability module is an optional, preloaded Streams extension.
Rabbit-capable focused/product profiles load `rabbit-capabilities.f` before
`streams.f`, selecting the complete 19-capability Streams build and its manager
and UI paths. An ordinary canonical Desktop build does not package that source
closure and retains the 15-capability Streams build with an explicit
`Burrow extension not installed` state. This is a product packaging boundary,
not permission to truncate the Rabbit-capable composition or shrink its
caller-provided pools.

The current canonical 4 MiB Desktop build contains 185 modules in 22 chunks
and 51 entries. It has 2,152 free sectors, 104 above the unchanged
2,048-sector MP64FS reserve. This is canonical build-fit evidence only; it is
not evidence that the Rabbit extension closure has been admitted to that
image.

No checked-in test ceiling, emulator timing, native scheduler behavior,
MP64FS geometry, canonical reserve, MegaPad source, or TLS/network code was
changed for this work.

## Green evidence

The emulator profiles ran sequentially with unchanged timing and checked-in
step ceilings.

| Evidence | Result | Measurement or qualified boundary |
| --- | --- | --- |
| `test_streams_burrow_manager.py` | PASS, 333 assertions | Borrowed provider contract, transactional operations, replay, revisions, cooperative lifecycle, rollback, retained cleanup, retry, restart, and final release |
| `test_streams_burrow_caps.py` | PASS, 566 assertions | Exact descriptors and bounds, semantic requests, mutation replay/conflicts, typed results, one-touch mutation, no-touch replay, status, and schema-wide construction |
| `test_streams_burrow_lifecycle.py` | PASS, 94 assertions | Boot: 2,648,500,000 steps in 62.19 s; 2,784,480,985 steps across all recorded stages; focused 8,192-sector image has 95 modules in 11 chunks and 5,180 free sectors |
| `streams-manual-refresh-contracts` | PASS, 245 assertions | 7,257,256,747 steps in 179.36 s under the unchanged 9,000,000,000-step ceiling |
| `codec-json` | PASS | 232,202,112 steps in 7.93 s, including the wide flat-map schema regression |
| `pytest local_testing/test_akashic_tui_packaging.py -q` | PASS, 64 tests | 4.68 s |
| Canonical Desktop build | PASS | 185 modules, 22 chunks, 51 entries, and 2,152 free sectors: 104 above the unchanged 2,048-sector reserve |

The integrated lifecycle evidence uses the real Streams initialization, tick,
close, and shutdown callbacks with the Rabbit extension preloaded. It proves
the 19-capability descriptor set, caller-owned composition geometry,
tick-driven transition to running, visible direct start, retained close during
cleanup, later close allowance, provider release, component-instance free, and
heap-baseline recovery. The ordinary Streams run demonstrates that the
15-capability non-extension build retains its existing manual-refresh behavior.

The first ordinary Streams manual-refresh run stopped at the generic
120-second host wall timeout after 5,197,500,000 steps without producing a
result and is non-evidence. Its qualifying rerun changed only the host watchdog
to 240 seconds; it retained the existing 9,000,000,000-step ceiling,
exact-single-core execution, and emulator timing. The lifecycle witness retained
its existing 8,000,000,000-step cold-boot ceiling and the 120,000,000-step
ceiling for each fixture/runtime phase.

## Exit

Checkpoint 3 is independently green and complete. Checkpoint 4 may now compose
the normal Desk/Agent product journey and exact nine-row focused operator facet
against these Streams descriptors and lifecycle callbacks. It must preserve
caller-owned capacity, truthful replay, retained cleanup, and the optional
extension packaging boundary rather than importing manager or provider state.

Real Library-backed Rabbit peer LIST/FETCH routing remains later work. This
checkpoint makes no TLS, physical-network, MegaPad, or canonical full-Rabbit
image-admission claim.
