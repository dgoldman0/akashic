# Desk, Library, and Rabbit Burrow checkpoint 1

**Qualified:** 2026-08-09

**Contract:** [`desk-library-burrow-checkpoint0.md`](desk-library-burrow-checkpoint0.md)

**Status:** Library capability surface and narrow lens cleanup complete;
Desk/Agent control-plane composition begins at Checkpoint 2

Checkpoint 1 gives the existing Desk-hosted Library owner a first-class,
typed capability surface. It does not add a second service, durable store,
controller cache, or VFS owner. The handlers execute synchronously against the
one live applet instance and its activation-local repository, service, and work
graph; each invocation uses a resettable activation-owned construction
workspace and publishes only a completely sealed result graph.

## Landed surface

The Library component `org.akashic.library.applet` version `0.1.0` now owns
exactly these five descriptors:

| Capability | Kind/effects | Implemented owner operation |
| --- | --- | --- |
| `library.status` | resource; `OBSERVE` | Reports authoritative readiness and logical generation without provisioning an absent Library. |
| `library.document.create` | command; `MUTATE\|PERSIST` | Creates or exactly replays one invocation-derived managed-text document. |
| `library.collection.create` | command; `MUTATE\|PERSIST` | Creates or exactly replays one invocation-derived collection with canonical sorted/unique members. |
| `library.document.query` | resource; `OBSERVE` | Atomically verifies an exact collection revision and request seal before returning an active managed-text page. |
| `library.document.read` | resource; `OBSERVE` | Atomically verifies the same collection scope, membership, exact document revision, lifecycle, kind, media, digest, and UTF-8 content. |

The request and result maps, field order, effects, and limits are the closed
Checkpoint-0 contracts. Resource and operation IDs derive independently from
the capability invocation ID. Fresh mutations return `CBUS-S-OK`; exact
no-write replay returns result-bearing `CBUS-S-NO-EFFECT`; altered replay,
operation-kind collision, stale generation, and collection replacement remain
precise conflicts. Domain failures preserve their Library service code in
`CBR.ERROR-CODE` while mapping to the corresponding capability-bus status.

Document and collection service DTOs now report whether a successful command
changed durable authority and the resulting logical generation. These are
outcomes of the existing owner transaction, not values inferred by a handler
from before/after probes. Collection-create replay resolves the operation key
and verifies the current initial collection, so a collection replaced after
creation cannot masquerade as a no-effect replay of its historical create.

## Library cleanup

`collection-values.f` is the Library-owned pure preparation layer for initial
collection shape, canonical membership, and the existing v2 request seal. Its
membership validation is bounded by the caller-provided span and signed-cell
arithmetic; it does not turn the capability's 64-child IVJSON bound into a
durable collection limit. The persistence adapter now consumes that helper
instead of owning duplicate semantic hashing and canonicalization code.

The applet still owns one runtime and one durable owner. Its runtime now also
contains the capability construction workspace, which is initialized and
wiped with the applet lifecycle. Capability-created objects become visible
through the ordinary authoritative reload path. The narrow lens fixes also:

- invalidate the status row whenever controller state changes;
- preserve collection/back state labels instead of showing stale search or
  filter copy outside corpus views; and
- render `No collections yet` for an empty Collections view.

## Capacity and qualification boundary

No existing checked-in step ceiling was raised. No emulator timing, native
scheduler behavior, MegaPad source, MP64FS geometry, canonical Desktop
free-space reserve, capability-bus argument ceiling, or TLS/network code
changed.

The public create surface admits the full existing 4,096-byte applet authoring
window and has an exact-full test. The public read surface uses the existing
`LIB-CONTENT-WINDOW-MAX` value of 65,536 bytes; an exact 65,536-byte current
document succeeds and a 65,537-byte current document returns
`LIBRARY-SERVICE-S-OUTPUT-CAPACITY` without publishing partial output. This is
an interaction/materialization bound, not a durable corpus or document-size
limit, and the service's bounded range/stream operations remain intact.

The 65,537-byte boundary fixture source-loads the same 93-module Library stack
from an unchanged 8,192-sector MP64FS image. Constructing both large retained
revisions on that 4 MiB guest filesystem exhausted its physical sectors before
the semantic assertion, so only the fixture's storage-heavy activation is
rebound to the established 32 MiB caller-owned RAM VFS. Core capability, UI,
and exact-4 KiB create profiles remain on MP64FS. This does not claim that a
larger canonical image fits, change the canonical reserve, or qualify a new
platform storage profile.

Ordinary one-shot ingestion above the current arena transaction page geometry
remains a pre-existing adapter qualification gap. Checkpoint 1 neither raises
that internal page count to hide the issue nor shrinks durable Library
semantics around it. The public create contract is 4 KiB; larger ingestion
should be qualified separately through a genuinely bounded staged/streaming
path.

## Green evidence

All emulator profiles were source-loaded and run sequentially with unchanged
timing.

| Evidence | Result | Measured execution |
| --- | --- | --- |
| `test_library_collection_values_l1.py` | PASS, 167 assertions | 239,509,108 steps; 7.40 s |
| `library-applet-contracts` | PASS, 24 assertions | 3,558,090,691 steps; 80.52 s; 4,521 free sectors |
| `test_library_ui_l1.py` | PASS, 25 assertions | 3,745,440,487 steps; 87.37 s; 4,514 free sectors |
| `test_library_capability_l1.py` | PASS, 439 assertions | 7,731,254,064 steps; 226.32 s; 187,884 KiB peak RSS; 4,443 free sectors |
| `test_library_capability_boundaries_l1.py` | PASS, 147 assertions | 9,135,051,648 steps; 275.09 s; 187,580 KiB peak RSS; 4,425 free sectors |
| `test_library_capability_create_boundary_l1.py` | PASS, 29 assertions | 4,430,366,215 steps; 118.90 s; 187,956 KiB peak RSS; 4,425 free sectors |
| `pytest local_testing/test_akashic_tui_packaging.py -q` | PASS, 63 tests | 3.48 s |

The focused contracts cover descriptor ownership and schemas, absent status,
fresh create, exact and altered replay, stale generation, canonical collection
membership, replaced-collection replay, exact scoped first/after query,
foreign/stale/tampered scope rejection, exact read, revision conflict,
archived/tombstoned exclusion, authoritative UI reload, exact 4 KiB create,
exact 65,536-byte read, and one-byte-over refusal.

## Exit

Checkpoint 1 is independently green. Checkpoint 2 may consume these five
Library descriptors through Desk's trusted candidate catalog and Agent review;
it must not import Library service pointers, weaken the closed schemas, or
reinterpret this focused evidence as a full Desktop image-fit claim.
