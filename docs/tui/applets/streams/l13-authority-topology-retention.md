# Halted L13 Streams authority, topology, retention, and cutover

**Status:** cancelled historical prototype decision; non-normative

**Halted:** 2026-07-25

**Controlling contract:** [`information-integration.md`](information-integration.md)

**Reset rationale and salvage ledger:**
[Streams architectural reset handoff](../../../../../STREAMS_ARCHITECTURAL_RESET_HANDOFF.md)

> This entire document records the design of the cancelled L13
> observation-repository effort. It is retained so its implementation,
> migration, failure, and scale decisions can be understood and selectively
> mined. Do not activate the four-tree authority, run its migration or
> authority flip, finish the uncommitted applet cutover, or use its acceptance
> checklist. Its monitored-inbox and no-output boundary does not describe the
> replacement Streams product.

This decision covers configured streaming sources, acquisition attempts,
observation identities and revisions, acquired content, query indexes,
retention truth, and migration evidence. It exists to keep the scalable
cutover inside the product boundary: Streams is a monitored inbox and
immutable observation journal, not another document manager.

## Ownership and exclusions

Streams is the sole writer of configured-source, attempt, observation, and
retention records. Repository mutation is serialized by one Streams owner.
Fetch and decode work may become concurrent later, but concurrency never
creates a second record authority or permits an operation to bypass the
serialized commit lane.

Desk continues to own routing, capability policy, and external-I/O lifecycle.
It stores no Streams records. Library continues to own documents, collections,
and corpus workflows. An eventual explicit typed export may create a
Library-owned capture with provenance back to an exact Streams observation
revision; neither side becomes a second writer for the other.

The following surfaces are excluded from this authority and remain frozen
during L13:

- `/streams-draft.bin` and the five existing draft capabilities;
- the retained public-Bluesky model, identities, schemas, provider, and
  feed/thread/search capabilities;
- editable documents, arbitrary attachments, collections, annotations,
  publication, scheduling, notifications, outputs, and Outbox machinery; and
- Desk XIO, trust, lifecycle, and policy records.

Adapters around an excluded surface are allowed only to preserve its current
behavior. There is no dual write and no convergence of configured
observations with the retained Bluesky model.

## One authority over four ordered indexes

The scalable repository uses one Streams-owned two-bank `PSTORE` authority
under `/streams/`, composed from the neutral page, segment, atomic-root,
`PBTREE`, `PBLOB`, reclamation, and compaction modules. The application-root
page owns four `PBTREE` roots:

| Physical tree | Logical families |
| --- | --- |
| Directory | current or removed source by RID, current source creation order, active attempt by source |
| Attempts | retained attempt history by source and acquisition sequence |
| Identities | exact native-key heads, immutable observation revisions |
| Orderings | global time, source time, and a reserved exact-thread family |

Four workload-separated trees are deliberate. Nine independent trees would
multiply root mechanics without improving authority, while one multiplexed
tree would force small source and recovery operations through the height and
failure domain of the largest observation index. All four roots are selected
by one application-root publication, so a logical transaction remains atomic
across them.

Every key begins with a nonzero one-byte family tag. Positive sequences,
revisions, kinds, and collision ordinals in ABI 1 are bounded to
`1..PERSIST-MAX-SIGNED` and encoded in fixed big-endian 64-bit fields,
followed by raw 32-byte RIDs or digests. Every family has one canonical key
length:

```text
directory/source-rid
    family || source-rid

directory/source-order
    family || creation-sequence || source-rid

directory/active-attempt
    family || source-rid

attempts/by-source
    family || source-rid || attempt-sequence || attempt-rid

identities/native-head
    family || source-rid || namespace || format || native-kind
           || native-digest || collision-ordinal

identities/observation-revision
    family || observation-rid || revision

orderings/global-time
    family || acquisition-sequence || observation-rid || revision

orderings/source-time
    family || source-rid || acquisition-sequence
           || observation-rid || revision

orderings/thread-time (reserved; no ABI 1 rows)
    family || source-rid || namespace || thread-root-digest
           || acquisition-sequence || observation-rid || revision
```

All keys fit the neutral 256-byte limit. An index value is normally one exact
`PERSIST-REF` to a checked semantic record and therefore fits the 64-byte
value limit. Dereference validates the record kind and all fields repeated in
the key. A valid reference to the wrong record kind is corruption, not a
miss.

Range calls seek an exact family/domain prefix, request a bounded candidate
window, validate the prefix on every row, and return a semantic continuation
rather than a physical B+tree cursor. A continuation identifies the query
family, direction, scope, authority epoch, and last accepted stable key. On
resume, the query reopens the latest authority and seeks from that semantic
key, so unrelated inserts cannot turn selection into an array ordinal.

The first configured-source topology adds no text-posting index. The existing
local search remains in the frozen Bluesky adapter. A configured-observation
search index enters later only with an exact projection contract and a scale
case; it is not inferred from Library's document search.

## Semantic records

Semantic records use one current Streams format. Each has a checked kind,
size, exact fields, reserved-zero tail, and semantic seal.

### Source

A current-source record wraps the existing exact pointer-free source value
and adds its stable creation sequence and current retained observation-version
count. The count is sealed wrapper metadata, not part of source configuration
identity: create initializes it to zero, source replacement and enablement
preserve it, migration derives it from exact legacy observations, and a
successful whole-batch apply advances it by only the new and revised versions
that become visible. This avoids an aggregate-count substitution or a
source-history scan at refresh time. Migrated values retain every source byte,
RID, revision, enabled flag, policy, bound, label, endpoint, and
provider-configuration byte. Source order is an index fact, not identity.
Removal replaces the source-RID value with an explicit checked tombstone and
deletes only the current source-order row. The tombstone retains the source
RID, creation sequence, last source revision, a later removal sequence, and exact seal
of the removed source record. It intentionally retains no endpoint or
provider-configuration bytes. The stable source-RID row prevents accidental
recreation from erasing removal history; removal never deletes attempt or
observation history.

### Attempt

An attempt record retains the current acquisition sequence, attempt RID,
source RID and revision, namespace, provider kind, request seal, requested and
effective URI, timestamps, state, outcome, detail, HTTP/decode/XIO/cleanup
facts, and new/revised/unchanged/rejected counts. Acceptance appends an
accepted record. A valid terminal transition appends its replacement and
retargets the same attempt-history key. Attempt IDs and request seals continue
to use their existing byte domains.

The active-attempt family contains only accepted attempts. Current L13
composition admits one active configured refresh per owner, and later
concurrency must retain a fixed active-attempt ceiling independent of corpus
size. Cold recovery scans only that bounded family and terminalizes every
recovered accepted attempt as indeterminate before making the owner available.

### Exact native-key head

A native-key head retains source RID, namespace, format, native kind, the
SHA3-256 digest, the exact admitted native bytes, stable observation RID,
latest revision, and last-seen attempt sequence. Equality remains exactly the
current domain:

```text
source RID, namespace, format, native kind, exact native bytes
```

The digest is only a candidate index. A lookup scans a small explicit
collision bucket and compares exact native bytes from each record. Digest
equality never conflates different native identities. Exhausting the
collision bound fails closed as capacity.

### Observation revision

An immutable observation-version record retains stable observation RID and
positive revision, source RID, namespace, acquisition and attempt identity,
format, semantic digest, exact title, URL, summary, published/modified text,
and an immutable `PBLOB` descriptor for content. Content bytes are fetched
payload, not an editable document. The body remains separately streamable and
ranged; summaries stay in the checked record.

Current configured providers supply no exact thread-root or parent evidence,
so observation-record ABI 1 authorizes no thread-time rows. L13 does not
manufacture thread identity for syndication and does not import or reinterpret
the frozen public-Bluesky thread model. The family tag and canonical key shape
are reserved so a successor checked observation record can add bounded exact
root bytes without changing the four-tree topology. That successor must make
digest-prefixed thread queries verify exact root bytes in each returned record
and use bounded candidate continuations when filtering.

Semantic records contain no physical record references except neutral blob
descriptors that compaction rewrites. Relationships use stable semantic IDs,
allowing compaction to rebuild every record and index.

## Application root and lifecycle

The checked application-root payload contains:

- Streams format and exact 4,032-byte application-payload size inside the
  neutral 4,096-byte checked page;
- logical generation and mutation sequence;
- global acquisition sequence;
- current-source, removed-source-tombstone, retained-attempt,
  observation-version, native-head, and active counts;
- migration provenance, completeness flags, and exact legacy fingerprints;
- the four ordered-index roots;
- reclamation state; and
- a semantic seal over all used bytes.

Cold open reads and validates a bounded set of roots and metadata independent
of corpus size. Full-corpus verification and compaction are explicit bounded
maintenance operations. A corrupt, unsupported-future, uncertain, or
ambiguous authority remains blocked; no such state becomes an empty writable
repository.

The sealed physical roles are:

```text
/streams/root-0             /streams/root-1
/streams/pages-0            /streams/pages-1
/streams/segments-0         /streams/segments-1
/streams/compact-root-0     /streams/compact-root-1
```

The frozen draft remains `/streams-draft.bin`. Legacy
`/streams-sources.bin` and `/streams-observation.bin` are migration evidence,
not members of the new authority.

## Mutation protocols

### Source mutation

Create, replace, enable, and remove validate the complete candidate and exact
expected revision before mutation. One transaction appends the new semantic
record, changes current and ordering indexes, advances the Streams logical
generation once, and publishes. A no-op enable remains a no-op and stale
revisions remain stale. Creation assigns a stable RID and creation sequence;
queries never expose physical or ordinal identity.

Create requires the source RID to be absent from the stable source-RID
family, including tombstones. Remove retargets that row to the checked
tombstone, deletes the source-order row, decrements the current-source count,
and increments the removed-source count in the same publication. Thus the
directory tree has exactly
`2 * current-source-count + removed-source-count + active-attempt-count`
rows. Replace and enable never change those cardinalities.

Remove is rejected while the exact source has an accepted active attempt. A
caller that intends to remove it must first complete the normal cancellation,
cleanup, and terminal-attempt publication; only then may the source-removal
transaction proceed. Removing only the active row would strand an accepted
history record that cold recovery could no longer discover, so that transition
is never authorized.

### Refresh begin

One transaction revalidates the exact enabled source RID and revision. The
provider boundary supplies its already-derived namespace, provider kind, and
canonical requested URI; the provider-agnostic acquisition authority validates
and seals those values as attempt evidence without recreating provider
canonicalization. It then derives the attempt ID and request seal, appends the
accepted attempt, inserts its history and active rows, advances acquisition
sequence, and publishes. Only that durable success authorizes provider
configuration and XIO submission.

### Refresh terminal

Failure, cancellation, stale completion, cleanup failure, and recovery may
replace only the exact matching accepted attempt and remove its active row.
They do not alter native heads or last-good observations.

### Refresh apply

Apply first validates all decoded candidates and computes every exact-key
match, collision, revision, count, content, and policy consequence without
publishing semantic changes. Duplicate keys within one batch remain invalid.
If preflight fails, the accepted attempt is terminalized with the current
distinct outcome and all last-good data remains unchanged.

A successful apply stages all changed immutable revisions, blobs, head
updates, ordering rows, the terminal attempt, and active-row removal. No
partial batch becomes query-visible. At large index heights the operation may
exceed one neutral reclaim ledger. In that case the adapter uses Library's
proven hidden-root pattern:

1. keep the four visible semantic roots unchanged;
2. mutate caller-owned hidden staging roots;
3. publish bounded physical extent/reclaim progress with the old visible
   roots and unchanged logical generation;
4. continue from the hidden roots in a fresh physical transaction; and
5. atomically expose all four staging roots and the successful terminal
   attempt in the final application-root publication.

A crash before the final publication leaves the accepted attempt and old
observations visible. Unreachable staging records are later compaction input.
Cold recovery therefore reports the attempt as indeterminate rather than
guessing that a batch committed.

Provider cleanup/reset must still finish before final successful publication.
The owner must still revalidate component instance, source revision, request
generation, and request seal after cleanup.

## Retention

The initial scalable retention policy is deliberately conservative:

> Refresh admission never deletes older evidence to make room, and capacity
> never silently overwrites last-good state.

Scalability comes first from replacing the fixed whole checkpoint with
growable indexed persistence. Destructive automatic retention is off.
Migrated history remains readable, attempts are retained rather than collapsed
to one head, and source removal retains history.

The existing source `observation-max` and `revision-max` fields remain
explicit semantic admission bounds. Defaults and migrated values remain
exactly 16 and 4. ABI 1 raises each configuration ceiling to 10,000,000 so a
deliberate source can cover the large scalar profile without turning that
profile into a default allocation or an aggregate repository ceiling; it does
not silently reinterpret or raise an existing source's value. Reaching either
configured bound rejects the complete apply, terminalizes the attempt as
capacity when durable storage permits, and leaves all prior observations and
native heads unchanged.

The removed aggregate limits—16 total sources, 48 total observation versions,
64 total key heads, and one 128 KiB shared blob—do not survive as repository
capacities. The decoded batch remains bounded at eight, individual field and
body maxima remain unchanged, and all working buffers remain independent of
corpus cardinality.

An explicit future destructive retention ABI may add independent
terminal-attempt, superseded-revision, inactive-observation, and
removed-source policies without changing authority. Such a transaction must:

- never run implicitly during begin or apply;
- never prune an accepted attempt, current native head, pinned revision, or
  referenced content;
- record a pruning receipt and source/index completeness horizon;
- return `PRUNED` or `GONE`, not `NOT_FOUND`, for known removed history;
- reclaim content only after no retained revision references it; and
- be deterministic, bounded, and safely resumable.

Physical reclamation and compaction are not semantic retention. They may
recover pages and records unreachable under the current semantic roots, but
may not decide which streaming evidence is live.

## Cold migration and authority flip

Migration is cold, idempotent, staged, verified, and one-way:

```text
LEGACY_AUTHORITY -> STAGING -> VERIFIED -> REPOSITORY_AUTHORITY
```

There is no dual-write phase. Before the flip, the existing source and
observation readers perform their complete checked recovery and exact legacy
bytes are fingerprinted. Import builds repository pages and segments without
publishing a new root. Readback verifies counts, IDs, revisions, strings,
digests, attempt states, and every index projection. The first valid new
atomic root is the authority flip. After it exists, boot never consults a
legacy snapshot as writable authority and never rolls back acknowledged new
writes.

Legacy conditions map as follows:

| Legacy evidence | Cutover behavior |
| --- | --- |
| Both snapshots absent | Create an empty repository marked `COMPLETE_EMPTY` |
| Both valid | Import and verify both |
| Valid sources, observation absent | Import sources and mark observation history `UNKNOWN_LEGACY_ABSENT` |
| Source absent, valid observations | Import authentic historical evidence without inventing source configurations; mark source-history completeness unknown |
| Valid empty source registry with observations | Import both; removed sources may legitimately leave history |
| Either record corrupt after supported recovery | Do not flip; preserve legacy authority and diagnostics |
| Unsupported future version | Do not flip; require compatible software |
| I/O, allocation, or storage failure | Do not flip; staging remains safely replaceable or resumable |
| Verification mismatch | Quarantine or discard staging; do not flip |
| Crash before root publication | Legacy remains authority |
| Uncertain root publication | Reopen and resolve the atomic roots before choosing authority |
| Failure after the flip | New repository remains authority and requires repair; never fall back silently |

An accepted legacy attempt has no live request owner after a cold restart. It
is imported with the same attempt identity and evidence, then exposed as
indeterminate. Legacy snapshots remain read-only migration evidence until a
separate verified cleanup removes them; ordinary post-flip code does not
write or query them.

The legacy checkpoint retained one current attempt head per source, so an
older immutable observation can legitimately outlive its original successful
attempt record. Migration never invents the missing request evidence.
Compaction admits such a missing observation-to-attempt join only while the
sealed authority root proves legacy observation provenance; any present
attempt must still agree exactly, and a native authority with a missing join
is corrupt.

## Required cutover invariants

The old adapters cannot be removed until qualification proves all of these:

- source RIDs, revisions, order, and sanitized projections remain exact;
- namespace, attempt-ID, request-seal, observation-ID, native-key, and
  semantic-digest byte domains are unchanged;
- exact old revisions return the same bytes and never advance to current;
- accepted is durable before XIO submission;
- provider cleanup/reset precedes successful publication;
- stale source, owner, request-generation, or seal results cannot commit;
- every failure preserves last-good observations and heads;
- accepted-at-boot becomes indeterminate;
- apply remains whole-batch atomic;
- absent, historically unknown, pruned, and never-existing histories remain
  distinguishable;
- queries are bounded, source-scoped where required, and stable under
  unrelated insertion;
- endpoint and provider-configuration bytes remain absent from sanitized
  capabilities;
- provider-factory injection and trust remain fail-closed;
- draft bytes, revisions, capability IDs, and behavior remain unchanged;
- public-Bluesky IDs, schemas, feed/thread/search behavior, and store remain
  unchanged;
- new observation capabilities do not automatically widen Desk's Agent facet;
  and
- repository mutation remains serialized even when transport workers become
  concurrent.

Acceptance evidence includes identity golden vectors, old/new projection
comparisons, every migration matrix row, fault points around begin/apply/root
flip, stable pagination under insertion, exact historical reads, aggregate
ceiling removal with bounded working memory, no-admission-eviction tests,
compaction liveness, and draft/Bluesky preservation profiles.
