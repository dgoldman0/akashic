# Desk, Library, and Rabbit Burrow checkpoint 0

**Ratified:** 2026-08-09

**Base:** `c65d30e81d50eb0c71166a6c1dcd9e294d372480`

**Branch:** `desk-library-burrow-orchestration`

**Status:** implementation contract; no product capability is claimed by this
document

This is the tracked Checkpoint-0 record for the bounded Desk orchestration
slice. The workspace handoff remains the full execution guide. Rabbit Landings
0–3 are qualified substrate; Signal Hunt, Worlds, the dated Streams SR4 queue,
TLS, physical networking, and all MegaPad changes are outside this slice.

The intended product journey uses normal Desk app lifecycle, a separately
authorized Practice, Agent Tool Gateway/review/capability dispatch, the live
Library service and lens, a Streams-owned activation-local Burrow manager and
visible status, framed deterministic memory transport, and ordinary Desk close.
A direct service/manager fixture is not substitute evidence.

## Ownership and exact targets

- Library is the sole durable semantic owner. Its target component is
  `org.akashic.library.applet` version `0.1.0`; the projection owner string
  `org.akashic.library` is not a component target.
- Streams owns Burrow declarations, graph lifecycle, pumping, status, and
  cleanup. Its target is `org.akashic.streams` version `0.5.0`.
- Desk owns trusted candidate catalog, exact live-target resolution, applet
  lifecycle, and review composition. Practice supplies authorization; Agent
  invokes but owns neither domain.
- Streams reaches Library only through exact component capabilities and a
  least-authority peer facet. It never imports Library service code or paths.

## Frozen capability contracts

Maps are closed and fields have the listed order. Text limits are decoded UTF-8
bytes. `R0` is the canonical 92-byte resource URI with URI revision zero;
`REV+` is a positive domain revision; `N` is nonnegative; `H64` is exactly 64
lowercase hexadecimal characters.

| Capability | Kind/effects | Request fields | Result fields |
|---|---|---|---|
| `library.status` | resource; `OBSERVE` | null | `ready:BOOL`, `logical_generation:N` |
| `library.document.create` | command; `MUTATE\|PERSIST` | `expected_logical_generation:N`, `title:STRING[1..128]`, `media_type:"text/plain"|"text/markdown"`, `content:STRING[0..4096]` | `resource:R0`, `domain_revision:REV+`, `logical_generation:N`, `operation_receipt:H64`, `content_digest:H64` |
| `library.collection.create` | command; `MUTATE\|PERSIST` | `expected_logical_generation:N`, `title:STRING[1..64]`, `members:LIST[0..64] OF R0` | `resource:R0`, `domain_revision:REV+`, `logical_generation:N`, `request_digest:H64` |
| `library.document.query` | resource; `OBSERVE` | exact collection scope, nullable cursor, limit 1..32 | exact scope, 0..32 rows, nullable next cursor |
| `library.document.read` | resource; `OBSERVE` | exact collection scope plus exact member resource/domain revision | exact scope/member, media, byte count, digest, content up to 65,536 bytes |
| `streams.burrow.create` | command; `MUTATE` | exact collection scope, `library-read-v1`, `memory-duplex`, caller-fitting peer capacity | common Burrow result |
| `streams.burrow.status` | resource; `OBSERVE` | `burrow:R0` | common Burrow result |
| `streams.burrow.start` | command; `MUTATE` | `burrow:R0`, `expected_domain_revision:REV+` | common Burrow result |
| `streams.burrow.stop` | command; `MUTATE` | `burrow:R0`, `expected_domain_revision:REV+` | common Burrow result |

The exact collection scope is `collection:R0`,
`collection_domain_revision:REV+`, `request_digest:H64`.
`request_digest` is the existing `LIBC.REQUEST-SEAL`, not a second membership
digest. Members are canonical sorted/unique RIDs. Sixty-four is the existing
IVJSON inline-child bound, not a durable collection limit.

The query cursor is `fingerprint:H64`,
`observed_logical_generation:N`, `first_order_sequence:REV+`,
`first_resource:R0`, `last_order_sequence:REV+`, `last_resource:R0`. A row is
`resource:R0`, `domain_revision:REV+`, `title:STRING[1..128]`, managed-text
`media_type`, `content_bytes:N`, `content_digest:H64`.

The exact query request is collection scope followed by `after:NULL|CURSOR`,
`limit:INT[1..32]`; its result repeats collection scope followed by
`documents:LIST[0..32] OF ROW`, `next:NULL|CURSOR`. The exact read request is
collection scope followed by `resource:R0`, `domain_revision:REV+`; its result
repeats those fields followed by managed-text `media_type`, `content_bytes:N`,
`content_digest:H64`, `content:STRING[0..65536]`. Scope and membership are
verified atomically before either operation publishes a result.

The common Burrow result is, in order: `burrow:R0`,
`domain_revision:REV+`, lifecycle state, `activation_epoch:REV+`,
`durable:false`, exact collection scope, `profile:"library-read-v1"`,
`transport:"memory-duplex"`, `security_mode:"deterministic-fixture"`, peer
count/capacity, service count, cleanup pending, closed numeric last status and
detail, and `operation_receipt:NULL|H64`. Status has a null receipt; mutations
return their operation receipt.

`last_status` is `INT[0..12]`: 0 none, 1 invalid, 2 state, 3 busy, 4 capacity,
5 conflict, 6 not found, 7 pending, 8 denied, 9 unavailable, 10 I/O, 11 corrupt,
12 fault. `last_detail` is `INT[0..14]`: 0 none, 1 declaration, 2 Library
binding, 3 Library dispatch, 4 provider acquire, 5 router, 6 server,
7 subscription, 8 transport, 9 facet mount, 10 Burrow open, 11 Burrow pump,
12 Burrow finalize, 13 provider release, 14 invariant. These are sanitized
manager codes, not pass-through lower-owner values.

Burrow create is collection scope followed by
`profile:"library-read-v1"`, `transport:"memory-duplex"`,
`peer_capacity:REV+`; status is `burrow:R0`; start and stop are `burrow:R0`,
`expected_domain_revision:REV+`. The lifecycle enum is exactly `configured`,
`starting`, `running`, `stopping`, `stopped`, or `blocked`.

Query and read are absent from ordinary Agent facets and belong only to the
fixed Rabbit peer facet. The two Library creates and all three Burrow mutations
are reviewed. No capability in this slice declares `EXTERNAL`.

## Revisions, replay, and errors

The following namespaces never substitute for one another:

1. `CBR.EXPECT-REV`: live target CINST revision;
2. Library logical generation: optimistic durable mutation generation;
3. Library document/collection domain revision;
4. Burrow activation-local domain revision; and
5. URI revision, always zero for these semantic resource references.

Document and collection resource/operation identities derive separately from
`CBR.INVOCATION-ID`. The existing document receipt and collection request seal
remain distinct semantic request evidence. Burrow create/start/stop have
separate receipt domains. Same invocation and same request converges; changed
replay conflicts.
Collection replay is a no-write success only while the current collection still
has the original operation key and request seal.

The new NUL-delimited invocation domains are:

- `akashic.library.cap.document-create.operation.v1`
- `akashic.library.cap.document-create.resource.v1`
- `akashic.library.cap.collection-create.operation.v1`
- `akashic.library.cap.collection-create.resource.v1`
- `akashic.streams.cap.burrow-create.resource.v1`
- `akashic.streams.cap.burrow-create.receipt.v1`
- `akashic.streams.cap.burrow-start.receipt.v1`
- `akashic.streams.cap.burrow-stop.receipt.v1`

Library keeps its existing document request-seal domain and
`akashic.library.collection-create-request.v2`; the new strings derive identity
and Burrow receipts rather than duplicating those Library seals.

Burrow revision one is `CONFIGURED`. Every observable lifecycle/status change,
including tick-driven transitions and terminal block, increments once; hidden
cleanup work does not. IDs are not reused within an activation, and activation
epoch changes across Streams activations.

Fresh successful mutations return `CBUS-S-OK`. Exact no-write replay returns
result-bearing `CBUS-S-NO-EFFECT`; Tool Gateway, Agent runtime/UI, audit, and the
scripted provider must treat that as successful convergence while retaining the
typed result and avoiding a CINST touch or second owner commit.

Library domain failures retain the exact Library status in `CBR.ERROR-CODE`.
Invalid maps to bus invalid, busy to bus busy, absent/not-found/tombstoned/gone
to bus not-found, and remaining domain failures to bus failed. CINST stale
revision is not reused for a Library or Burrow domain conflict.

The status probe alone reports a wholly absent, provisionable Library as
successful `ready:false`, generation zero. It does not flatten corruption or a
partial store into “not ready.”

## Encoded bounds

Compact byte bounds are `plain / typed`. Requests seal as typed IVJSON; results
use plain IVJSON. “Schema-wide” includes values admitted by coarse schema types
before canonical URI, lowercase hex, enum, and minimum-length checks.

| Capability | Request semantic | Request schema-wide | Result semantic | Result schema-wide |
|---|---:|---:|---:|---:|
| Library status | 4 / 13 | 4 / 13 | 56 / 81 | 56 / 81 |
| Document create | 25,448 / 25,497 | 25,513 / 25,562 | 357 / 416 | 1,565 / 1,624 |
| Collection create, 64 members | 6,538 / 7,406 | 42,890 / 43,758 | 270 / 318 | 1,158 / 1,206 |
| Document query, 32 rows | 702 / 819 | 3,046 / 3,163 | 35,072 / 37,430 | 67,912 / 70,270 |
| Document read, 65,536-byte content | 386 / 447 | 1,842 / 1,903 | 393,750 / 393,852 | 395,605 / 395,707 |
| Burrow create | 334 / 404 | 1,362 / 1,432 | 806 / 988 | 2,877 / 3,059 |
| Burrow status | 105 / 126 | 673 / 694 | 744 / 924 | 2,495 / 2,675 |
| Burrow start/stop | 152 / 181 | 720 / 749 | 806 / 988 | 2,877 / 3,059 |

`CBR-ARGS-CANONICAL-MAX` remains 65,536. The review and Agent review-JSON
buffers move from 4,096 to 65,536; 4,096 cannot encode even a safe-ASCII 4 KiB
document request, and 32 KiB cannot cover the schema-wide 64-member collection.
Agent result capacity remains 32,768. Rabbit query/read mounts receive
caller-owned arenas of at least 67,912 and 395,605 bytes, with frame sizes
derived separately by `RBF-FRAME-MEASURE`. Exact-full and one-byte-short tests
must regenerate and enforce these figures.

## Desk authority and table capacity

The current Desk has 16 candidate entries. Seven additions give 23 for an
all-current-applets-live operator and nine for the focused Library/Streams
composition. Checkpoint 0 ratifies 24 facet entries: `CFACET-SIZE` changes from
1,928 to 2,824 bytes, adding 896 bytes to each inline owner. Implementation must
audit the facet core, Desk state, Agent mandate-run copy, Rabbit host/mount
spans, embedded harness profiles, and Rabbit test allocations/sentinels.

Desk's hard-coded capability ID lists become a Desk-trusted declarative
candidate catalog. It remains only policy input; exact live target, Practice
authorization, selected preset, effects, disclosure, and mandate bounds still
attenuate it.

Built-in Assist may receive reviewed Library creates and safe statuses but not
Burrow lifecycle mutation. Add the separately sealed selector
`AAP-PRESET-PRACTICE-LIBRARY-BURROW = 4`, ID
`desk.practice-library-burrow`, and label `Practice Library Burrow`. It has
chat-history/context-observe/review flags, Assist effects, commit disposition,
12 history items/4,096 history bytes, 600,000 ms, zero memory/token budgets, 12
tool calls, 49,152 disclosure bytes, and no external effect. The calls cover
eight central operations plus four retry/status operations. Its focused facet
contains the two existing Streams reads and seven new entries.

## Image evidence and immutable boundaries

Build-only measurements on the clean base used unchanged MegaPad and no smoke,
integration, persistence, or emulator run:

| 8,192-sector image | Modules/chunks | Resources/entries | Free sectors/bytes |
|---|---:|---:|---:|
| canonical Desktop | 184 / 22 | 10 / 51 | 2,204 / 1,128,448 |
| Desktop plus current Library | 203 / 29 | 11 / 60 | 613 / 313,856 |
| focused Desk/Agent/Library/Streams/scripted | 178 / 26 | 4 / 44 | 1,370 / 701,440 |
| standalone Library | 82 / 13 | 1 / 24 | 4,834 / 2,475,008 |

The canonical reserve is 2,048 sectors. Current Desktop passes by 156 sectors;
Desktop plus Library fails by 1,435 sectors before new source exists. The
focused probe disabled the unrelated large sample; its measurement is 678
sectors below the canonical reserve and is not a
replacement reserve claim. A 10,240-sector probe was rejected by MP64FS's
existing 8,192-sector maximum. Do not change MegaPad or reduce the reserve.
Canonical default integration remains blocked until Akashic-side packaging or
source work closes the deficit honestly.

The focused profile may qualify the bounded product journey only after final
free-sector and peak-persistence measurements demonstrate headroom. It must use
normal Desk catalog/launch/focus/review/close behavior and visible Library and
Streams applets; it is not permission for a renderer-free product claim.

Tests remain sequential. Emulator/native-scheduler timing is immutable. A
nonsemantic step ceiling or capacity may move modestly only after measured
bounded progress and with old/new value, steps, wall time, memory, free sectors,
and affected owners recorded. Never increase a limit to hide a defect or remove
end-to-end behavior to preserve an arbitrary ceiling.

The workspace `DESK_ECOSYSTEM_CONTRACT.md` was not amended. Its current
195,517-byte SHA-256
`cd034f972349220be6e5f152774a7130ac74eb62d4cee687a5856fe7427dff4f` already
differs from the Gate-0 fixture's 187,791-byte `5bdb9709...` pin. That host test
is a pre-existing stale baseline in the canonical workspace. Any later
normative amendment must preserve the old hash lineage and update the fixture
and test explicitly; this checkpoint does not silently bless either version.

## Minimum Library cleanup

Add a pure Library-owned collection-create preparation helper rather than
duplicating invariants in the capability or applet. Reuse the controller's one
repository/service/work owner. Also fix and directly regress the known prompt
dismissal/status-row invalidation, collection/back state-label disappearance,
and empty Collections copy, and prove Agent-created content becomes visible via
ordinary authoritative reload. Storage redesign, durable format/identity work,
full Gate 5, viewer input work, and MegaPad are excluded.

## Checkpoint 0 exit

Checkpoint 0 changes documentation only. It freezes the authority, schemas,
effects, replay and revision rules, lifecycle, encoded bounds, capacity policy,
minimum Library cleanup, and qualification shape above. Product work begins at
Checkpoint 1 with the Library-owned helper and capability surface; later
checkpoints must not silently weaken this contract to fit an arbitrary harness
or image number.
