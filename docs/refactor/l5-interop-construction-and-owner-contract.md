# Refactor Landing L5 interop construction and owner contracts

Landing L5 extracts repeated interoperability construction mechanics and uses
them in the existing Library and Daybook owners. It changes code distribution,
not either applet's product. It does not add a resource-owner pool or session,
normalize Daybook's compact document protocol, move applet packages, redesign
storage, increase a dataset limit, or begin the later indexed scale landings.

## Neutral construction boundary

`interop/construction.f` provides three caller-owned transactional builders:

- `CSB` assembles a closed map schema from caller-owned field storage;
- `CVB` owns an unpublished value tree until recursive abort or zero-allocation
  publication; and
- `CAPB` stages and validates a complete capability descriptor before copying
  it into the destination.

The module chooses no field name, capability identity, schema meaning, effect,
handler, resource policy, persistence action, or error text. It invokes no
caller callback and declares no mutable lexical state. Active transactions
latch their first error, refuse same-workspace re-entry without disturbing the
candidate, and leave a destination untouched until seal and publication.
Independent workspaces interleave without shared construction state.

The value builder is for bounded control-plane contract trees. It is not an
in-memory corpus abstraction: large applet datasets remain a paging, indexing,
and streaming concern in later landings.

## Canonical resource-owner boundary

`interop/resource-contract.f` retains the exact current describe, snapshot,
and replace schemas and client-facing argument words. Their manual map assembly
now uses transactional construction internally; the existing compact words are
the current convenience API, not a legacy format layer.

The module adds the missing symmetric owner side:

- snapshot and replace decoders validate the complete closed input and rebuild
  an owned exact QLOC in caller storage;
- replace also returns a bounded borrowed content span and a copied digest only
  after hashing and verifying those bytes;
- describe, snapshot, and replace result constructors copy pointer-bearing
  views into an unpublished owned value tree, enforce the schema and digest/
  locator relations, and publish atomically; and
- canonical capability constructors fix IDs, kinds, schemas, effects, timing,
  concurrency, and callback shape while leaving optional text, flags, and the
  handler with the concrete owner.

Operand records scrub private decode pointers before returning. Result and
capability construction use caller-owned reusable workspaces, so separate owner
paths do not share hidden builder state. The helpers contain no registry,
acquisition, component-revision, storage, lifecycle, qualification, locking,
media, or error-message policy, and successful decoding grants no authority.

## Proving consumers and removed boilerplate

Qualified-locator schema and value serialization replace private field/scratch
builders with `CSB` and `CVB`. Public QLOC bytes, validation, status values, and
the seven-field interoperability map remain unchanged.

Library's projection owner uses the full RCON owner API. It retains RID and
lease accounting, current/retained qualification, media/kind meaning, UTF-8,
read-only and lifecycle rules, store status mapping, and all error text. Its
describe/snapshot/replace maps and resource capability descriptors are no
longer hand-built field by field. A replacement still constructs, validates,
and publishes the complete result before
`LIBRARY-VFS-STORE-REPLACE-MANAGED`; only fixed readback comparison follows a
durable commit, so allocation failure cannot create an unreportable success.

The concrete Daybook owner uses the shared describe result and descriptor
constructors. Its snapshot remains null to string and its replace remains
string to bool under the activation-local component revision. Those compact
descriptors, plus the Daybook applet's task/source/agenda descriptors, use
`CAPB` without changing IDs, titles, descriptions, schemas, effects, flags,
callbacks, or handler bodies.

No Streams module was converted merely to manufacture another workload: its
current placement is not duplicate L5 construction code. Game and Worlds stay
frozen, SoundLab stays outside the later MediaLab direction, and L6 still owns
all resource-owner pool/session and Pad-session work.

## Functional preservation and fault boundary

The production changes touch the L1 groups for Library query/projection,
Daybook resource ownership/contracts, Daybook model actions/Markdown through
its public capabilities, and the existing Pad/Desk resource journeys. Before
conversion, the L1 prerequisite was closed with direct agenda dispatch and a
forced task-capture persistence failure proving exact result cleanup and
unchanged model, dirty, discard, capture-hop, and allocator state.

The construction fixture covers malformed and duplicate schemas/capabilities,
sticky first failure, same-workspace `BUSY`, independent workspaces, candidate
alias refusal, destination nonmutation, zero-copy ownership transfer,
deterministic root/key/nested allocation failure, recursive cleanup, and exact
available-memory restoration.

Gate 3A adds direct owner-helper coverage rather than inferring correctness from
an applet success. It covers snapshot/replace success, type and digest mismatch,
private-tail scrubbing, all three result constructors, contradictory
projection-content evidence, destination nonmutation, deterministic allocation
faults, exact memory restoration, workspace reuse, and every canonical
capability field.

## Qualification

| Command or profile | Result |
| --- | --- |
| `interop-construction-contracts` | 120 assertions; 175,334,698 steps |
| `gate3a-resource-contracts` | 529 assertions; 510,293,563 steps |
| `library-projection-owner-contracts` | 723 assertions; 4,002,337,212 steps |
| `library_projection_two_boot.py` | two-process cold acceptance PASS |
| shared-document, shared-lens, and Desk shared-document pytests | 3 passed |
| `daybook-contracts` | PASS; 1,606,187,110 steps |
| `pad-resource-contracts` | PASS; 2,068,025,642 steps |
| `desktop-resource` | PASS; 6,940,000,000 steps |
| `desktop-agent-hardening` | PASS; 16,370,000,000 steps |
| host architecture/functional/packaging/VFS gate | 205 passed |

The Agent hardening image now reaches its unchanged final journey after 16.37
billion guest instructions because the interpreted linked image loads the new
contract implementation. Its reviewed harness ceiling moves from 16 to 17
billion solely for deterministic emulator headroom. That number is not a
product capacity, performance target, dataset-scale result, or permission to
raise any applet limit.

The complete host packaging/VFS/architecture/functional-baseline gate and both
reviewed ratchets close the landing. No command or changed module requires ext4.

## Architecture ratchet

The reviewed graph has 385 production modules and 1,301 resolved occurrences/
unique edges. The new neutral construction module has two downward dependencies
and four direct consumers: qualified locator, common resource contract, the
Daybook owner, and the Daybook applet.

Construction itself declares no lexical mutable state. Removing QLOC/RCON
private builder globals lowers the independent-library lexical total from
7,072 to 7,057. Library and Daybook add explicit guarded consumer workspaces,
raising the conservative applet total from 2,752 to 2,758; Desk remains 1,100.
Placement debt, layer violations, unresolved imports, cycles, identity debt,
addressability debt, product capacities, and scale policy are unchanged.
