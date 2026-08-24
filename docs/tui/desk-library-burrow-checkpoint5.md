# Desk Library Burrow Checkpoint 5

**Status:** complete integrated product qualification green

**Qualified executable code:** `4b8680568a229b1bd114d3a05fa4e73f745157ab`

**Evidence-wording descendant:** `503c09109e7a677e89ffbcc7e174cf35d4ada795`
(comment-only; executable behavior is unchanged)

**Paired MegaPad code:** `ca02a40c04840791c731dbb7c77ecd7e85eb4909`

**Feature base:** `b04461c5ec9263842a497ac7e5dafda2e8beae91`

**Integration ancestry:** merge `5753ffd` contains ext4 head `e213334` and
Burrow/TLS head `386a8a5`

**Scope:** fixed read-only Library Rabbit profile and product capstone

Immediately before the documentation-only landing record that contains this
disposition, local Akashic `main` had been fast-forwarded to A* closure head
`c69fbe57cb6169c80560033e94d3d9a640ad9def` and local MegaPad `main` to M*
closure head `a8cb7995363ebd5177e7e94375abd068e322329f`. Their cached
`origin/main` refs remained respectively
`d2e9551ffc37e324bb83acf51108f506599edfd5` and
`f4b8144786001e423291b9458f24e0efa7ab70ce`; neither landing had been pushed.
This disposition record descends from those closure heads but is documentation
only. It is not a newly tested code checkpoint: the qualified executable
anchors above remain Akashic
`4b8680568a229b1bd114d3a05fa4e73f745157ab` against MegaPad
`ca02a40c04840791c731dbb7c77ecd7e85eb4909`.

## Contract freeze

Checkpoint 5 adds the framed data plane deliberately excluded from
Checkpoint 4. It does not change the eight-call Agent lifecycle, place Library
read operations in an Agent mandate, or claim a physical listener, TLS,
Public Rabbit transport, durable Burrow configuration, remote mutation,
subscriptions, ranged reads, ext4 coupling, or canonical Desktop admission.

The first profile has exactly two routes on one exact versioned selector:

| Rabbit request | Selector | Peer-controlled IVJSON body | Local capability |
| --- | --- | --- | --- |
| `LIST` | `/v1/library/documents` | `after`, `limit` | `library.document.query` |
| `FETCH` | `/v1/library/documents` | `resource`, `domain_revision` | `library.document.read` |

`after` remains the Library capability's nullable, scope-sealed cursor and
`limit` remains in the closed range 1 through 32. `resource` is one canonical
revision-zero Library resource URI and `domain_revision` is positive. The
wire maps are closed: missing, duplicate, or additional fields fail before
capability dispatch.

The peer never supplies `collection`, `collection_domain_revision`, or
`request_digest`. The graph provider copies those three values from the
manager's acquisition specification into lease-owned storage. A profiled
facet mount decodes only the reduced peer map and constructs the full
five-field canonical capability arguments from the peer fields plus that
server-owned copy. The ordinary Library capability schemas then deep-validate
the constructed graph, and the authoritative Library handler atomically
checks the frozen collection scope, request seal, exact membership, and
document revision.

## Authority and ownership

Each lease owns one dedicated capability facet. It contains exactly
`library.document.query` and `library.document.read` against the live Library
component generation, with effects exactly `OBSERVE` and flags exactly
`INVOKE|DISCLOSE_RESULT`. It is not the Agent Practice facet. The facet,
profile binding, mount request graphs, and caller-provided JSON arenas outlive
the attached Rabbit server and Burrow row.

The manager continues to own lifecycle through the existing graph-provider
ABI. A deterministic qualification provider builds an actual memory-duplex
server/client graph and exposes only the independent client end to the
capstone. Teardown completes the Burrow and server first, resets/finalizes the
router so it no longer borrows mount handlers, finalizes the mounts and
profile, then invalidates the provider lease on successful release. Pending
cleanup retains the complete graph.

Streams binds Library only through public capability descriptors, the exact
live component target, the capability bus, and the dedicated facet. The
profile must not import Library service/controller/VFS internals or create a
second Library owner.

The descriptive host fixture filenames exceed MP64FS's 23-byte component
limit. The product image therefore carries the four Checkpoint-4/5 leaves as
the explicit qualification-only containers `c5-srbprov.f.lz`,
`c5-dlburrow.f.lz`, `c5-slrabbit.f.lz`, and `c5-dlcap.f.lz`. The sources
retain their host paths and `PROVIDED` identities. The capstone now declares
the prefix-distinct bounded identity `akashic-test-c5-dlb`: its former
descriptive identity collided with the Checkpoint-4 fixture after KDOS reduced
both keys to 23 bytes, which could silently skip the capstone. Image
validation checks injected Forth leaves and the linked closure in one
module-key namespace.

## Cold-source image representation

The generic complete-Desktop packaging path now owns the bounded
compressed-at-rest source representation; it is not a Checkpoint-5-only
facility. Checkpoint 5 uses that ordinary path for the linked Akashic source
chunks and adds only its four qualification leaves. This promotion followed
the earlier CP5 image-pressure finding that an ordinary linked build needed
239 sectors when only 236 remained. The filesystem geometry and canonical
Desktop mutable reserve were not weakened, and no CP5-only generic loader API
remains.

Each root-level data container has a fixed 40-byte `AKLZSS01` header, positive
raw and payload lengths, an at-most-122,880-byte raw bound, and mandatory raw
CRC32-IEEE. The canonical LSB-first LZSS stream has a 4 KiB back-reference
window, 3 through 18 byte matches, exact input/output exhaustion, and zero
unused final control bits. The uncompressed root alias `coldsrc.f` validates
the single-extent file, decodes into format-bounded allocations, verifies CRC,
and compiles each raw source through `SOURCE-EVALUATE-CHECKED`. A generated
`_BOOT-COLD-SOURCE` wrapper reports the checked evaluator status, line, column,
throw, and token before aborting a failed boot load. Read-only descriptors are
released without rewriting MP64FS metadata.

This remains a cold source build. It is not a compiled Forth shard, warm
dictionary cache, or source-timing substitute: every module is decoded and
compiled at boot. On a fatal packaged-source error the loader restores its
dictionary and evaluator checkpoint before boot aborts; that statement does
not claim rollback of module registrations or arbitrary load-time side
effects.

## Encoded capacity contract

The fixed disclosure and response-arena minima are the schema-wide plain
IVJSON maxima already derived at Checkpoint 0:

| Result | Semantic plain maximum | Schema-wide plain maximum |
| --- | ---: | ---: |
| LIST / `library.document.query` | 35,072 | 67,912 |
| FETCH / `library.document.read` | 393,750 | 395,605 |

The FETCH maximum includes a valid 65,536-byte UTF-8 string in which every
byte requires six-byte JSON escaping. Tests regenerate the maxima from actual
graphs: an exact-size output arena succeeds and a one-byte-short arena fails
without partial publication. Frame, queue, parser, transport, and independent
client-result capacities are derived separately from the exact Rabbit
message/frame measurement APIs; none reuses a JSON number as an unrelated
capacity.

IVJSON response decoding uses a caller-supplied document bound. The generic
65,536-byte JSON default remains unchanged because raising it globally would
turn this one profile's disclosure envelope into an unrelated system limit.

## Capstone exit

The qualified product-composed capstone starts the declaration through the
Agent Tool Gateway, connects the independent memory-duplex client, LISTs the
Agent-created frozen collection, FETCHes its member, decodes the plain IVJSON
result, and compares the exact original UTF-8 bytes and digest. It then stops
through the Agent path and uses ordinary Desk close.

Qualification also proves frozen-scope and nonmember/stale-revision rejection,
one real lost-response replay through Tool Gateway yielding a typed
`CBUS-S-NO-EFFECT` convergence result without a second Library write, retained
ownership during a pending stop, no second Rabbit graph, and exact allocator,
mount, facet, transport, manager-declaration, Library-binding, and outer Desk
baselines after teardown.

## Current qualification evidence

The exact qualified 8,192-sector image composes 205 modules into 32 checked
cold-source chunks. Across the linked chunks and four qualification leaves,
3,976,822 raw bytes produce 991,083 container bytes. The image has 54 MP64FS
entries and 4,731 free sectors at build completion. The gate expands every
container back to its exact source, checks DATA type and single-extent layout,
verifies loader ordering, validates all four leaf aliases, and keeps the CP5
leaves isolated from ordinary Checkpoint-4/Desktop linking.

The final product command was:

For a current rerun, use the landed MegaPad `main` checkout at documentation
head `b399bd0`; the qualified executable dependency remains code ancestor
`ca02a40`.

```bash
MEGAPAD_ROOT=/path/to/megapad \
  python3 local_testing/test_desk_library_burrow_capstone.py \
    --product --timeout 1200
```

It passed against the exact MegaPad code named above on one timing-correct
core with 128 MiB external memory. The complete cold-source journey used
27,100,000,000 guest steps in 811.14 seconds; the cold configuration marker
arrived at 17,410,000,000 steps. CP5 now has a checked, measured
30-billion-step whole-journey ceiling. Checkpoint 4 retains its independently
qualified 24-billion-step ceiling, and no local wait, input-settlement,
scheduler, source-loading, filesystem-reserve, or emulator-timing contract was
weakened. The command widens only the host wall timeout to 1,200 seconds.

The MP64FS ledger recorded a 4,292-sector minimum, 439-sector peak
consumption, 155-sector largest stable persistence increment, and 4,452-sector
final image with 279 sectors retained relative to the build. It accepted 1,521
valid completed-write samples and ignored zero transient parse views. Thus the
minimum remaining capacity exceeded the largest observed stable increment;
the journey did not manufacture headroom by relaxing the Desktop reserve.

The transcript contains exactly nine physical Tool Gateway calls, eight
logical results, and six review approvals. It proves the deliberate first
START receipt drop, replay from the stable RUNNING owner revision, typed
`NO_EFFECT` convergence, ordered LIST and FETCH success, frozen-scope,
nonmember, and stale-revision rejection, and the complete framed data plane.
The RUNNING and STOPPED Desk views, exact Library UTF-8/digest readback, outer
Agent completion, ordinary Desk close, and final ownership/allocator teardown
all occur exactly once.

Supporting qualifications remain independently green. The public provider
lifecycle gate acquired, opened, boundedly cancelled, finalized, released,
and tore down the lower owner through the real component registry, request
bus, capability descriptors, and public graph ABI at
8,085,169,445 steps in 209.61 seconds (`fc7def5`). The isolated wire-bound run
passed at 5,501,875,046 steps in 154.05 seconds. The expanded facet-mount ABI
run has 1,082 assertions, and delayed replay has 589 checks. The current
compact post-integration matrix is 87/87 green in 61.84 seconds.

## Resolved qualification history

The following were staged integration failures, not current blockers:

- Compiled `IS` calls in the CP4/CP5 installer words attempted to parse an
  exhausted runtime input line. The fixtures now install deferred actions by
  captured XT and deferred body.
- The caller-owned graph slab planner retained queue wire ceilings and allowed
  nested binding helpers to overwrite the queue base. The planner now has its
  declared stack effect and preserves the binding base independently.
- The inactive-lease validation path lacked its final `NIP`, leaking the
  provider context beneath the flag and contaminating graph readiness.
- Live Library lookup used the enclosing `APP-DESC` where the component
  registry requires `APP.COMP-DESC`; it now resolves the exact live component
  instance.
- Acquire preflight consumed the saved peer capacity before its comparison.
  The value is explicitly reloaded and the focused gate pins the bounded
  caller geometry.
- Receipt replay initially raced the STARTING-to-RUNNING owner revision. The
  duplicate is now released only from the stable RUNNING revision, without
  weakening request-bus revision validation.
- The Library capability descriptor array was not guaranteed eight-byte
  alignment, and provider queue teardown passed a queue-root slot rather than
  the stored queue pointer. Both public lifecycle defects are closed and
  exercised by the focused gate.
- The real Streams and Library component descriptors were bare `CREATE`
  bodies even though the profile admits them as aligned borrowed spans. Both
  now use padded backing with stable aligned public accessors, and CP5 checks
  their exact identities at runtime.
- The inherited 24-billion-step CP4 ceiling was exhausted while ordinary UI
  input was settling with the final Stop review presented, after replay,
  LIST/FETCH, status, and RUNNING evidence had completed. CP5 alone now uses
  the measured 30-billion-step ceiling; CP4 remains unchanged.

The green result qualifies this in-memory, read-only Library Rabbit vertical.
It does not add evidence for a public network Rabbit endpoint, TLS behavior,
ext4/Rabbit coupling, durable remote configuration, remote mutation, or any
other exclusion in the contract freeze.
