# Desk Library Burrow Checkpoint 5

**Status:** implementation, isolated wire bounds, focused provider compile,
and expanded facet qualification green; product qualification blocked during
cold source boot

**Base:** `b04461c5ec9263842a497ac7e5dafda2e8beae91`
**Scope:** fixed read-only Library Rabbit profile and product capstone

## Contract freeze

Checkpoint 5 adds the framed data plane deliberately excluded from
Checkpoint 4. It does not change the eight-call Agent lifecycle, place Library
read operations in an Agent mandate, or claim a physical listener, TLS,
durable Burrow configuration, remote mutation, subscriptions, ranged reads,
or canonical Desktop admission.

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

The complete Checkpoint-5 source closure did not fit the fixed 8,192-sector
qualification image in ordinary linked form: the initial build needed 239
sectors with only 236 free. The filesystem geometry and canonical Desktop
reserve were not weakened, and source comments were not squeezed merely to
meet an arbitrary byte target.

Checkpoint 5 alone therefore stores its ordinary linked source chunks and all
four qualification leaves in a bounded compressed-at-rest representation.
Each root-level data container has a fixed 40-byte `AKLZSS01` header, positive
raw and payload lengths, an at-most-122,880-byte raw bound, and mandatory raw
CRC32-IEEE. The canonical LSB-first LZSS stream has a 4 KiB back-reference
window, 3 through 18 byte matches, exact input/output exhaustion, and zero
unused final control bits. The uncompressed root alias `coldsrc.f`
validates the single-extent file, decodes into format-bounded allocations,
verifies CRC, and compiles each raw source through
`SOURCE-EVALUATE-CHECKED`. A generated `_BOOT-COLD-SOURCE` wrapper reports the
checked evaluator status, line, column, throw, and token before aborting a
failed boot load. Read-only descriptors are released without rewriting
MP64FS metadata.

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

The product-composed capstone must start the declaration through the Agent
Tool Gateway, connect the independent memory-duplex client, LIST the
Agent-created frozen collection, FETCH its member, decode the plain IVJSON
result, and compare the exact original UTF-8 bytes and digest. It then stops
through the Agent path and uses ordinary Desk close.

Qualification also proves frozen-scope and nonmember/stale-revision rejection,
one real lost-response replay through Tool Gateway yielding a typed
`CBUS-S-NO-EFFECT` convergence result without a second Library write, retained
ownership during a pending stop, no second Rabbit graph, and exact allocator,
mount, facet, transport, manager-declaration, Library-binding, and outer Desk
baselines after teardown.

## Current qualification evidence

The host image gate currently composes 203 modules into 32 ordinary source
chunks. Including the four checked leaves, 3,965,045 raw bytes produce
988,790 container bytes. The image has 54 MP64FS entries and 5,435 free
sectors. The gate expands every container back to its exact source, checks
DATA type and single-extent layout, verifies loader ordering, validates all
four leaf aliases, and proves isolation from ordinary Checkpoint-4/Desktop
linking.

The expanded focused guest loader contract passed in source mode at
101,907,938 guest steps (2.97 seconds across the measured run stages) on one
core with 128 MiB external memory. It verified a real packed source compile,
stack neutrality, invalid-distance and noncanonical-tail rejection, checksum
rejection before evaluation, dictionary/evaluator rollback after unfinished
source, exact allocator and descriptor recovery on every path, and a valid
same-machine retry. The complete packaging suite is 74/74 green (13.43 s on
the final review pass),
including generic image-leaf alias rejection. The architecture inventory is
17/17 green (12.18 s on the final review pass), and the Checkpoint-4,
facet-mount, cold-loader, and
Checkpoint-5 static contracts all pass. Python compilation and formatting
checks are also clean.

These are packaging and focused-loader results, not the product capstone. A
second focused cold-source gate compiles the exact Checkpoint-5 provider after
its 47-module dependency closure: seven chunks compress 818,076 raw bytes to
193,895 bytes, leaving 3,130 sectors free in the 4,096-sector image. It passed
at 1,514,247,710 guest steps in 47.95 seconds. The expanded facet-mount ABI run
is green with 1,082 assertions across 31 source-load stages, 143 contract
stages, and its final marker, under the checked-in 120-million-step phase
ceiling (21 billion theoretical aggregate, one core, 64 MiB).

The first Library qualification attempt incorrectly placed the pre-existing
storage/read boundary and the new wire-maxima workload under one inherited
10-billion-step/330-second aggregate. The storage/read phase reached its exact
`PASS 147` marker, but the process reached 9,994,500,000 steps and the wall
limit before the wire phase's terminal marker. Historical qualified evidence
puts the storage/read phase alone at 9,135,051,648 steps. Static inspection
found only finite bounded work in the new phase; the fixture already described
it as a separate focused runner. The orchestration now restores the original
boundary-only command and exposes the IVJSON maxima/decode work through an
isolated `--wire` mode with explicit phase markers. That correction changes no
Library, IVJSON, or product behavior.

The isolated wire-bound run is now green: its exact PASS marker arrived after
5,501,875,046 guest steps in 154.05 seconds on the timing-correct single-core
source path. It proves exact-size success, one-byte-short nonpublication, all
semantic/schema plain and typed maxima, and caller-bounded read-result decode.

The product journey is not green. The latest 8,192-sector source image booted
the 203-module closure and printed the first leaf marker,
`DESK LIBRARY RABBIT LOAD C4 PROVIDER PASS`, then returned to the Forth prompt
before starting the second leaf. It reached 14,719,559,469 guest steps and the
600.16-second wall limit. The compiled checked-loader failure reporter did not
fire. Dependency-aware scans find no unresolved token or unbalanced control
structure in any leaf, and a separate audit found no CP5 word, defining-word,
immediate, or `PROVIDED` key that shadows the Checkpoint-4 closure or leaves.

The strongest remaining diagnosis is a userland dictionary/XMEM boundary,
not a Rabbit profile failure: current MegaPad reserves a fixed 32 MiB
`U-ZONE-SIZE`, places XMEM allocations immediately above that floor, and has
no extmem dictionary guard comparable to the Bank0 guard. This larger source
closure can therefore cross into live XMEM storage while compiling. That is
an evidence-backed inference, not yet a direct measurement. Independently,
KDOS has a 128-slot module table while this image has roughly 205 module
identities; full-table insertion is silently declined. Neither MegaPad issue
has been patched in this worktree.

Do not rerun the unchanged 600-second product gate. The next session should
first choose and qualify the proper MegaPad dictionary/module-capacity design
or reduce the exact production closure without weakening it. After that, the
product wall allowance also needs an explicit decision: the current packed
boot executes only about 14.72 billion steps in 600 seconds, while the green
Checkpoint-4 journey historically required 17.25 billion steps. The checked
24-billion-step ceiling has not been raised. Exact LIST/FETCH/replay
assertions, persistence `M > L` evidence, product runtime counts, and the
Checkpoint-5 commit remain intentionally blank.
