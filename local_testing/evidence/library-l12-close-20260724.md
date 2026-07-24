# Library L12 closure ledger — 2026-07-24

This ledger records the acceptance boundary and current-tree qualification for
the Library L12 scalable-storage landing. It supersedes the fixed-backend
measurements in the Gate 4 ledger; those older files remain historical records
of the implementation that L12 deletes.

**Ledger state:** final. Every required current-tree result is green.

## Accepted product boundary

Library remains a single Desk-owned semantic authority. L12 replaces its
temporary fixed catalog banks, membership bitmaps, and content arena with
checked records, atomic application roots, copy-on-write B+trees, immutable
chunked blobs, bounded reclamation, and two-bank semantic compaction. Neutral
modules under `akashic/persistence/` know byte keys, opaque values, physical
roots, and durability fences. Library paths, record meanings, query semantics,
retention, and compaction liveness remain under
`akashic/tui/applets/library/`.

The accepted topology has fifteen ordered populations:

1. shared identity directory;
2. document RID directory;
3. operation receipts;
4. document creation order;
5. document recency order;
6. lifecycle/kind/media creation order;
7. title order;
8. tag postings;
9. short-text candidate postings;
10. collection directory;
11. collection order;
12. collection title order;
13. collection membership;
14. exact document history; and
15. lifecycle/kind/media recency order.

Content and canonical metadata are immutable blobs. Documents, collections,
receipts, history, membership, and search candidates are indexed values.
Repository, query, service, projection, and controller layers consume that one
authority; none retains a fixed-store facade.

The deleted `record-codec.f`, `store-format.f`, fixed-store fixtures, and old
cold/efficiency drivers are not compatibility surfaces. There is one current
layout, no legacy reader, and no migration stack. Provisioning is permitted
only when every reserved role is absent; partial, corrupt, colliding, or future
authority fails closed.

## Scale and work boundary

The corpus has no compiled document, collection, membership, or revision-count
capacity. Durable populations grow through 4 KiB copy-on-write pages and
32 KiB blob chunks. The scalar model covers one million documents, one hundred
thousand collections, ten million retained revisions, ten million membership
edges, sixteen million tag postings, and a conservative 12.666-billion-row
short-text candidate population. The deepest modeled tree has height twelve;
one cold point lookup therefore reads at most twelve index pages, and one
32-row keyset window reads at most 44.

Ordinary work remains bounded and caller-owned. The Library index workspace is
119,840 bytes and contains one B+tree workspace, one blob workspace, one
reclaim workspace, fifteen tree descriptors and root pairs, bounded staging
values, one page scratch buffer, and a 32 KiB content window. Query pages hold
at most 32 rows. Larger content is delivered by range or stream. Compaction
advances by caller-supplied byte, work, and per-step byte budgets.

Tree mutation admission reserves the tallest possible copy-on-write path,
application-root publication, and reclaim finalization before each staged
mutation. A long logical operation may publish intermediate physical roots,
but advances the Library logical generation exactly once.

## Durability and recovery closure

L12 publication writes and verifies immutable records and tree pages, writes
and verifies the application-root record, synchronizes data, and only then
replaces a checked atomic root. A failed known-no-effect transaction is
abortable; a maybe-effect publication is `UNCERTAIN` until a fresh descriptor
reconciles selected authority.

The final storage audit also closed six failure boundaries:

- single-bank staging reset can invalidate its remaining root after physical
  data removal instead of failing midway;
- second-bank configuration rejects descriptor, cache, or backing spans that
  alias any part of the first store, including its descriptor tail, without
  mutating either store;
- standalone atomic-root initialization and second-bank configuration reject
  a segment descriptor inside that bank's own page-cache backing before
  publishing any descriptor fields;
- compaction treats the shared root's optional statistics object as part of
  the complete mutable graph, so coordinator/work/buffer aliases fail
  byte-for-byte before begin-time scratch clearing;
- MP64FS publishes replacement allocation before switching a directory entry,
  and defers retirement until the replacement is durable; and
- delete, shrink, and mixed add/delete commits conservatively publish
  allocation state before directory state, then apply deferred retirements.

Crash-prefix tests remount after every injected boundary and retry the exact
operation. Interrupted publication may conservatively leak a sector, but
cannot make a still-referenced sector reusable. Relocation, delete, shrink,
mixed publication, single-bank reset, and tail-alias cases all retain a
mountable authority.

Incremental blob construction now reads transaction-visible records while a
proposal is open and accounts for each exact caller allowance. Its final
manifest failure path preserves the blob work pointer, returns
`(done?=0 used status)`, invalidates the output descriptor, clears busy state,
and leaves the enclosing store transaction poisoned for explicit abort.

## Semantic and executable boundary

Service create/import, exact replace, archive, tombstone, retained
restore/compare, collection mutation, and compaction requests use explicit
stable identities and optimistic state. Same-operation-key, same-request
retries return the original result; changed requests are idempotency
mismatches. Query continuations contain semantic keys rather than physical
cursors. Search is exact and case-sensitive: titles and bodies use substring
matching and tags use whole-value equality.

Projection receives an explicit service and never consults ambient VFS or UI
selection. Managed resources support describe, snapshot, and exact replace;
captures are read-only. Identity acquisition, exact historical locators,
archived values, tombstones, pruned revisions, owner limits, and activation
lease limits retain distinct outcomes.

The single-instance applet is a bounded lens, not another repository. It
reconstructs its first page, semantic selection, exact preview, and
authoritative status from the service. During one activation, exact
pending-create retry reuses the complete sealed request; close remains deferred
until that activation-local request is retried or explicitly discarded.
Corrupt and checksum-valid future roots are shown as blocked and nonwritable
rather than reprovisioned. Capture import, tombstone, retained restore/compare,
maintenance, raw export, compaction controls, deep editing, multi-Library
selection, and multiple concurrent Library applets remain deferred UI or
integration work; the service boundary already owns the applicable operations.

No L12 qualification requires ext4. All executable and cold-reopen evidence
uses MP64FS through the abstract VFS boundary.

## Failure-handoff resolution

The projection red was fixture authority, not release behavior. The large
bounded snapshot case acquired an identity locator where the snapshot contract
requires an exact RID/domain/digest locator, then called the result validator
without that locator. The tombstone case likewise attempted a post-tombstone
snapshot through identity acquisition even though identity acquisition is
current-active only. The corrected fixture derives and validates exact
locators before mutation, while retaining identity acquisition for its
documented scope.

The applet's persistent one-cell stack delta was also isolated rather than
masked. Collection preview copied the selected summary revision into
`_LAPP-TARGET-REVISION` with `DUP`; the pre-L12 direct-call ABI consumed that
duplicate, but the L12 request descriptor reread the stored field and left the
old value behind. The controller now stores the revision once, and the linked
fixture checks stack balance immediately after entering the collection view.
It separately proves a nonzero semantic selection survives page-buffer
reinitialization and that an exact pending-create retry reuses the sealed
request.

The linked profiles are substantially larger than the harness defaults:
projection needs a 70-billion-step / 1,200-second qualification envelope and
the complete applet lifecycle needs 55 billion steps / 1,200 seconds. These
are emulator gate budgets, not product capacity or latency claims.

## Architecture ratchet

The qualified worktree is based on
`76d7fdef0b2309d7ed47b0b665617b9837f692a8`; the closure commit contains the
production, fixture, documentation, and ledger changes recorded here.

The reviewed graph contains 404 modules, 1,333 resolved `REQUIRE`
occurrences/unique edges, and 78 unchanged reviewed unresolved imports. It has
no cycle, layer violation, or placement-debt module. The final ratchet digests
are:

| Ratchet | SHA-256 |
| --- | --- |
| dependency graph | `8022e4ecb92e66e75eadb821ba01842ca09e72ae143f28201cf69e0356992473` |
| mutable state | `d4f1056d9e157bf8e13337d6fb2217ac24414887ea6959476609a2837bd9b602` |
| placement debt | `4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945` |
| unresolved imports | `98fad31ab92dd0633ed32bc95f3c387e9d222001a4080f7e6926edaec16f21cb` |

The metadata-publication complexity entry remains attributed to its responsible
landing, L12, but is now explicitly `resolved`. The target-landing field is
historical ownership, not an assertion that work remains open. The two
reviewed `PROVIDED` findings and one addressability finding belong to the
pre-existing duplicate `fexplorer copy.f` module; the L12 ratchet neither adds
nor silently reclassifies them.

## Current-tree qualification

Every emulator gate below ran sequentially on 2026-07-24. No smoke,
integration, or persistence test overlapped another test process. Step ceilings
are qualification envelopes; the table records work actually executed.

### Neutral persistence

| Gate | Assertions | Emulator steps | Host wall |
| --- | ---: | ---: | ---: |
| page + segment + store | 68 + 161 + 788 | 491,689,591 | 7.76 s |
| atomic root | 788 | 465,704,923 | 8.01 s |
| B+tree | 9,165 | 3,977,897,893 | 55.89 s |
| chunked blob | 482 | 1,130,197,596 | 16.91 s |
| reclamation | 2,912 | 2,656,809,919 | 38.62 s |
| two-bank compaction | 336 | 697,172,701 | 10.29 s |

The blob total includes exact incremental allowances, transaction-visible
reads, final-manifest failure cleanup, and explicit abort. Atomic-root/store
totals include single-bank reset, full descriptor/cache/backing-span
preflights, and same-bank segment/cache rejection. Compaction includes
descriptor, work-span, and segment-buffer aliases against the shared root's
statistics object, each rejected before mutation.

### Library values, authority, query, and service

| Gate | Assertions | Emulator steps | Host wall |
| --- | ---: | ---: | ---: |
| model | 22 | 213,729,919 | 4.45 s |
| streamed metadata | 61 | 212,912,964 | 4.56 s |
| document values | 49 | 235,334,454 | 4.55 s |
| index keys | 242 | 233,341,978 | 4.60 s |
| persistence adapter | 200 | 3,935,212,649 | 52.63 s |
| repository | 143 | 1,793,322,076 | 24.16 s |
| repository paths | 602 | 2,362,793,672 | 31.51 s |
| query structure | 169 | 1,140,781,914 | 14.61 s |
| query execution | 316 | 11,778,022,300 | 158.37 s |
| semantic service | 411 | 11,281,517,674 | 146.91 s |
| service scale | 105 | 7,060,770,899 | 94.02 s |
| collections | 96 | 1,692,105,878 | 22.31 s |
| retained restore | 147 | 6,253,458,838 | 84.99 s |
| Library compaction | 383 | 3,578,890,879 | 47.33 s |
| inspection / maintenance | 228 | 2,209,222,404 | 28.55 s |

The query wrapper deliberately runs two linked images. The first pins the
summary/policy structure; the second executes current-authority candidate
verification, forward/backward semantic keysets, exact search, collection
filtering, and streamed body checks. The measured execution phase requires
more than the general harness default and completed well inside its checked-in
15-billion-step ceiling.

### Cold process and linked executable closure

| Gate | Assertions | Emulator steps | Host wall |
| --- | ---: | ---: | ---: |
| managed first boot | 60 | 2,845,215,980 | 39.25 s |
| managed cold boot | 95 | 2,190,123,362 | 27.33 s |
| projection owner | 871 | 54,892,285,137 | 721.84 s |
| applet lifecycle | 694 | 44,218,189,422 | 674.92 s |

The two-boot driver passed only the serialized MP64FS image and printed RID
between isolated Python/emulator processes. Cold authority reproduced exact
query/read/content/receipt state and treated stale-generation replay as the
same operation rather than a duplicate document.

Projection linked 56 modules in 10 chunks and passed service-backed
describe/snapshot/replace, exact historical locators, capture read-only
behavior, terminal states, quiescence, eight live owners, and 64 activation
leases. The applet linked 82 modules in 12 chunks and passed 694 checks with no
stack delta through primary mutation, three compactions, collection filtering,
nonzero selection restoration, exact pending retry, cold activation,
corrupt/future refusal, and restored activation.

### Host and static ratchets

The combined host command passed **135 tests in 19.52 seconds**. It includes
the persistence boundary/scale model, 29 MP64FS crash/publication tests,
packaging/deletion rules, and both architecture pytest suites.

`refactor_inventory.py --check` and
`refactor_functional_baseline.py --check` both passed. The functional ledger
contains 9 applets, 29 behavior groups (16 covered, 11 partial, 2
prerequisite-only), 16 prerequisites, and 113 evidence references.
`git diff --check` passed after the final ledger update.
