# Library Gate 4 closure ledger — 2026-07-20

This ledger is the final evidence record for the bounded, headless Library
owner implemented by Gate 4 milestones 1–5. It combines the focused contracts,
spawn-isolated cold drivers, public bounds, static cost model, and literal exit
criteria in one place. The milestone-four measurements remain available in
[`library-projection-owner-20260720.md`](library-projection-owner-20260720.md).

**Ledger state:** final. No known Gate 4 result is outstanding.

## Acceptance boundary

The accepted product is the fixed-bound, sole-VFS-owner Library service. It
owns managed documents, immutable captures, collections, retained revisions,
the disposable query index, exact resource projections, inspection, recognized
head-transaction repair, and opaque evidence export. Production source is
loaded through the linked-chunk path; the focused contract remains an ordinary
injected fixture. The maintenance profile linked five production chunks, and
the milestone-four projection profile linked six. The literal exit driver also
requires both its dependency closure and every generated proof leaf to use the
linked loader. Monolithic injected source is outside this qualified packaging
path and is not substituted for linked-path evidence or mislabeled as a
Library runtime result.

Normal durable state has exactly four private Library objects: one 512-byte
head, two 403,968-byte catalog banks, and one 655,360-byte content arena. The
head is the sole publication point. Stage, backup, and marker objects exist
only as bounded head-replacement transaction evidence. There is no durable
query index, public path selection, or path accessor.

## Public maintenance ABI

The milestone-five caller surface is:

```forth
LIBRARY-INSPECTION-INIT       ( inspection -- )
LIBRARY-VFS-STORE-INSPECT    ( inspection store -- call-status )
LIBRARY-VFS-STORE-RAW-EXPORT ( bytes capacity inspection store -- required-u status )
LIBRARY-VFS-STORE-REPAIR     ( prior-inspection store -- status )
```

`INSPECT` separates call success from corpus health: a successful call returns
`LIBSTORE-S-OK`, while `LIBINS.HEALTH` reports healthy, absent, corrupt,
unsupported-future, or recovery state. Its caller-owned report is staged and
published only after a complete successful inspection. Invalid arguments and
I/O failure leave the caller report unchanged.

The 832-byte inspection layout is exact:

| Offset | Bytes | Public field |
| ---: | ---: | --- |
| 0 | 8 | `LIBINS.HEALTH` |
| 8 | 8 | `LIBINS.REPAIR-MASK` |
| 16 | 8 | `LIBINS.RAW-REQUIRED` |
| 24 | 8 | `LIBINS.FLAGS` |
| 32 | 8 | `LIBINS.HEAD-GENERATION` |
| 40 | 8 | `LIBINS.SELECTED-BANK` |
| 48 | 8 | `LIBINS.CATALOG-COUNT` |
| 56 | 8 | `LIBINS.COLLECTION-COUNT` |
| 64 | 8 | `LIBINS.MUTATION-SEQUENCE` |
| 72 | 8 | `LIBINS.CONTENT-TAIL` |
| 80 | 8 | `LIBINS.CONTENT-RECORD-COUNT` |
| 88 | 8 | reserved, canonical zero |
| 96 | 32 | `LIBINS.EVIDENCE-SEAL` |
| 128 | 32 | `LIBINS.REPAIRED-SEAL` |
| 160 | 672 | seven 96-byte evidence-object records |

The seven object records have the fixed order `HEAD`, `HEAD-STAGE`,
`HEAD-BACKUP`, `HEAD-MARKER`, `BANK-A`, `BANK-B`, `CONTENT`, numbered 0–6.
Each 96-byte object record contains state at offset 0, flags at 8, raw offset at
16, raw byte count at 24, envelope format at 32, store format at 40, generation
at 48, a 32-byte SHA3-256 digest at 56, and eight reserved zero bytes at 88.

Object states are `ABSENT=0`, `RECOGNIZED=1`, `FUTURE=2`, `CORRUPT=3`, and
`RECOVERY=4`. Object flags are `PRESENT=1`, `SELECTED=2`, `COMMITTED=4`, and
`OPAQUE=8`. `LIBRARY-INSPECTION-F-RECOGNIZED-V1=1` and
`LIBRARY-REPAIR-F-HEAD-TRANSACTION=1`. Future and corrupt objects are explicitly
opaque; their semantic fields are not guessed.

The shared public status values are exact: `OK=0`, `ABSENT=1`, `CORRUPT=2`,
`UNSUPPORTED=3`, `INVALID=4`, `CATALOG-FULL=5`, `COLLECTION-FULL=6`,
`CONTENT-FULL=7`, `ALLOCATION=8`, `IO=9`, `RECOVERY=10`, `UNCERTAIN=11`,
`BUSY=12`, `CONFLICT=13`, `IDEMPOTENCY-MISMATCH=14`, `NOT-FOUND=15`,
`RETIRED=16`, `TOMBSTONED=17`, `GONE=18`, and `OUTPUT-CAPACITY=19`.

`RAW-EXPORT` repeats inspection under the same serialized VFS transaction and
treats the supplied inspection seal as an optimistic evidence token. Capacity
zero acts as a size probe; whenever present evidence requires bytes, zero and
any short capacity return the exact required byte count with
`OUTPUT-CAPACITY`. Once copying starts, any read, close, coherence, or other
failure zeroes the entire negotiated required span. Every copied object is
hashed again and compared with the inspection digest, so even a successful but
silently changed second read returns `CONFLICT`. The output order and
per-object offsets are the report order above.

`REPAIR` first performs a fresh inspection and compares its evidence seal with
the caller's prior report. It delegates only an exact, recognized
`VREPL` head-transaction plan, then reopens, fully validates, reloads the active
descriptor, reinspects, and requires the exact predicted repaired seal.
Completed repair reports are idempotent receipts only after a fresh healthy
seal match and an explicit durability barrier. Future, corrupt, ambiguous, and
orphan evidence is preserved for export; repair does not rewrite a bank or the
content arena and never invents a replacement corpus.

All three calls reject invalid/private/store/VFS-overlapping public spans.
Nonzero raw output may not overlap its inspection report. These preflight
failures authorize no mutation.

## Fixed byte and count bounds

The ten ratified Library-domain bounds are:

| Bound | Exact value |
| --- | ---: |
| catalog records | 128 |
| collections | 32 |
| collection members | 128 |
| tags per catalog record | 16 |
| lineage locators | 4 |
| content payload | 65,536 bytes |
| retained content revisions | 4 |
| resource title | 128 bytes |
| tag text | 24 bytes |
| collection title | 64 bytes |

Additional public and durable bounds are:

| Item | Exact value |
| --- | ---: |
| query page | 32 summaries |
| live projection owners | 8 distinct RIDs |
| activation-local projection leases | 64 |
| projection root | 4,072 bytes |
| dynamic projection component state | 128 bytes per live RID |
| maximum projection component state | 1,024 bytes |
| projection index/rebuild allocation | 0 bytes |
| catalog bank header/body/total | 512 / 403,456 / 403,968 bytes |
| content arena header/data/total | 512 / 654,848 / 655,360 bytes |
| maximum padded content frame | 66,048 bytes |
| normal four-object raw evidence | 1,463,808 bytes |
| optional transaction evidence | 1,088 bytes |
| seven-object raw export ceiling | 1,464,896 bytes |
| evidence object / inspection report | 96 / 832 bytes |

Milestone-five maintenance adds 124,784 bytes of fixed static working state:
122,880 bytes preserve the activation index, decoded facts, record seals, and
direct-frame locators byte-for-byte during a read-only probe; 1,904 bytes are
two staged reports plus bounded control/hash state. The optional export buffer
is caller-owned memory, from zero through 1,464,896 bytes (the profiler uses
XMEM). No maintenance cost or allocation grows beyond these published
corpus/evidence bounds.

## Static work model

Milestones 1–3 retain the content-first publication rule: mutation appends and
reads back content, constructs and validates the complete inactive bank, and
publishes only the head. Thus a successful mutation is bounded by one content
frame plus complete-bank work and conservative authoritative reconciliation.
Cold activation validates the selected complete bank and committed content
prefix, then rebuilds the disposable 57,344-byte search index and the bounded
direct-frame locator table. Warm authority checks are bounded head checks;
unchanged queries inspect at most 128 indexed candidates, return at most 32,
and direct-read only exact selected frames. They do not rebuild the index or
fall back to an arena-prefix scan.

Milestone 4 adds bounded root/lease validation and one authoritative exact RID
lookup. Acquire performs one exact-frame read, describe performs no content
read, and snapshot performs one exact-frame read. A successful projection
replace pays the ordinary complete durable publication/reconciliation cost;
stale replacement reads only the named retained frame and refuses. Release is
a bounded 64-entry lease-ledger scan. Exact milestone-four operation cycles,
size slopes, direct-read counters, and the eight-owner/64-lease refusal points
are preserved in the linked milestone-four evidence document.

For milestone 5, let `R` be the exact sum of present evidence-object bytes and
let `V` be one full semantic validation of the deterministic V1 candidate
(selected bank plus committed content chain):

| Operation | Exact bounded work shape |
| --- | --- |
| `INSPECT` | one read/hash of every present object plus `V`; `O(R + V)` |
| zero/short `RAW-EXPORT` | the same inspection; no output copy; `O(R + V)` |
| successful exact `RAW-EXPORT` | inspection plus one exact copy and independent hash of every object; `O(2R + V)` |
| failed export after copying starts | successful-export work through the failure plus zeroing exactly `R`; worst-case `O(3R + V)` |
| successful planned `REPAIR` | fresh inspection, bounded head-only `VREPL`, full reopen/load, and post-inspection; bounded by two raw passes and three full semantic validations |
| completed-repair retry | fresh inspection, durability sync, and activation assurance; one additional full load only if the descriptor is not already healthy/active |

The cost model is deliberately byte-bound rather than logical-record-bound for
raw maintenance: the provisioned V1 topology always contains both complete
banks and the complete arena. The maintenance efficiency shapes separately
cover representative logical state and nine maximum frames (594,944-byte
committed tail). The current-tree capacity profile's direct bounded builder
separately constructs and fully validates all 128 catalog records without
paying for 128 irrelevant public setup mutations.

## Focused and regression profiles

All ten Gate 4 headless profiles were rerun from the maintenance tree. Their
current-source regression matrix is:

| Profile | Assertions | Emulator steps | Host wall |
| --- | ---: | ---: | ---: |
| `library-model-codecs-contracts` | 327 | 381,909,485 | 7.24 s |
| `library-store-format-contracts` | 173 | 248,305,146 | 5.14 s |
| `library-vfs-store-contracts` | 400 | 1,599,593,120 | 25.40 s |
| `library-managed-document-contracts` | 169 | 1,618,938,945 | 24.94 s |
| `library-managed-lifecycle-contracts` | 226 | 2,336,628,769 | 40.28 s |
| `library-capture-collection-contracts` | 153 | 1,983,850,896 | 34.67 s |
| `library-query-index-contracts` | 587 | 2,119,107,521 | 37.24 s |
| `library-projection-owner-contracts` | 723 | 3,748,887,216 | 59.38 s |
| `library-maintenance-contracts` | 219 | 1,757,351,837 | 26.54 s |
| `library-managed-capacity-contracts` | not printed | 5,014,628,800 | 72.74 s |

The maintenance matrix covers healthy semantics, size-only/short/exact export,
all seven objects, byte and SHA identity, alias rejection, read/close/sync
failure cleanup, stale tokens, changed-second-read conflict and full zeroing,
recognized head-transaction repair, idempotent retry, future and corrupt heads,
and preservation of an orphan content suffix. Its production closure loaded in
five linked chunks. The capacity profile intentionally does not print an
assertion total; this ledger does not infer one. It creates exactly 32
collections, then proves the 33rd returns `COLLECTION-FULL` with zero RNG,
write, checkpoint, or output activity and with generation, selected head,
counts, and mutation sequence unchanged.

The current packaging suite passed **58 tests in 1.25 seconds**. Python
bytecode compilation and `git diff --check` also pass; the final literal-exit
block below must record the last precommit rerun rather than inheriting these
checks mechanically.

## Spawn-isolated cold evidence

The following cold drivers passed with a new emulator process for every boot
and only serialized MP64FS bytes plus explicitly printed stable identifiers
crossing process boundaries:

| Driver | Result | Cold property |
| --- | --- | --- |
| `library_managed_two_boot.py` | PASS | managed RID and exact content survive real reload |
| `library_lifecycle_two_boot.py` | PASS | revisions, archive, capture provenance, receipts, and collection membership survive reload |
| `library_query_two_boot.py` | PASS | disposable index rebuild reproduces ordered pages and exact filters |
| `library_projection_two_boot.py` | PASS | projection is reacquired from durable identity; no root, registry, binding, component, result, or token state survives |

The projection cold run accepted RID
`d2eba1cf12cc96c40bfdd044b9e7c02d84501785dd7981a7daf5aa5e5bc5c1be`,
domain revision `1`, and content digest
`a3ef7f13f6f1c6813f3088f35261859175d19b8122d43257dcb9f8889d95ee7c`.
Its image linked 42 modules in six chunks and packaged 13 MP64FS entries.

## Literal Gate 4 exit branch

Run:

```bash
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/library_gate4_exit_two_boot.py --timeout 600
```

The seed passed 43 checks and the fresh clean relaunch passed 99. Each damage
clone passed 27 checks. The clean process proved six immutable managed content
revisions with retained revisions 3–6, archive state, an active immutable
capture with exact provenance/content, a distinct terminal tombstone,
operation-key receipts, tombstone non-reuse, bounded active/archived/all query
pages, and an explicit empty terminal page proving the tombstone was not
discoverable. The host verified that clean readback changed no private Library
object.

| Proof branch | Required public result | Raw bytes | SHA3-256 | Result |
| --- | --- | ---: | --- | --- |
| clean relaunch | six immutable managed revisions, active capture, distinct tombstoned RID | n/a (semantic branch) | n/a | PASS (99) |
| corrupt head | `CORRUPT`, opaque exact export, no mutation | 1,463,808 | `44fc82e40897536462a32f2093145fc886bc646b541231044d00b7ab69023104` | PASS (27) |
| corrupt selected-bank body | recognized envelope but overall `CORRUPT`, opaque exact export, no mutation | 1,463,808 | `83ac821fdc67ea9cd8c5d1c6d2927923d014bb183a2cf6b1ee3c9bd16e3a67e6` | PASS (27) |
| corrupt committed content frame | recognized arena but overall `CORRUPT`, opaque exact export, no mutation | 1,463,808 | `2f1f44247a237c7ad4b621a1a4badd88f24570e28dace3e79501af9742464732` | PASS (27) |
| checksum-valid future head | `FUTURE` / `UNSUPPORTED`, opaque exact export, no mutation | 1,463,808 | `142a4a49596a1208dfc37ffd12e6bf2974c197a620433de2ffb66f124e4da78d` | PASS (27) |

The accepted stable identifiers were managed RID
`d49668ff010b6124bf7361456a2d1376d909bf8cdec5bb20c49a6afa7065dafa`,
capture RID
`261bff9cab02e4604d2b0c56de413ae55f7cec180e2f69ae894b9fc5243421bf`,
and tombstone RID
`baada7e938b96179d57fb6b0d8aa5e33c9b306e6c29a5f24c6d13c5382a85910`.
The committed selector was bank 0.

The driver linked 23 production modules in five chunks of 122,048, 122,859,
121,553, 122,461, and 42,259 bytes. Its generated clean proof used two
top-level-safe leaves of 5,590 and 4,261 bytes behind a 295-byte bootstrap.
Each damage proof used one leaf (3,077, 3,093, 3,095, or 3,091 bytes) behind a
245-byte bootstrap. Only serialized MP64FS bytes and the printed stable seed
evidence crossed process boundaries. The exact terminal line was `Library
Gate 4 literal cold exit: PASS`. The command did not retain a formal aggregate
step/wall metric, so this ledger does not invent one; every fresh process was
individually bounded by the documented 600-second timeout.

## Milestone-five `PERF-CYCLES`

Run:

```bash
MEGAPAD_ROOT=/absolute/path/to/megapad \
  python3 local_testing/library_maintenance_efficiency.py --timeout 600
```

The driver covers a representative 8-document/4-KiB corpus and the
nine-by-65,536-byte content-bound corpus. It enforces same-evidence repeat cost
at no more than twice the first call, exact raw byte counts, recovery residue
repair, active descriptor restoration, and zero reported modeled stalls. The
separate current-tree capacity profile constructs and fully validates the
exact 128-record catalog bound.

| Shape | Inspect first | Inspect repeat | Export exact | Export repeat | Repair head transaction |
| --- | ---: | ---: | ---: | ---: | ---: |
| representative | 85,845,300 | 85,793,126 | 97,983,534 | 97,983,534 | 244,912,698 |
| content bound, 9 × 65,536-byte payloads | 546,637,946 | 546,585,772 | 558,776,180 | 558,776,180 | 1,627,300,611 |

Representative setup passed in 2,411,424,502 emulator steps and 91.109178 s;
its measured fresh-process profile passed in 1,431,980,096 steps and
42.134126 s. The per-operation host events were 127,613,349 / 5.237655 s,
69,513,882 / 3.155377 s, 95,140,843 / 4.541692 s, 165,415,745 / 8.012185 s,
and 267,215,168 / 11.550486 s in table order.

The content-bound setup passed in 8,190,374,543 steps and 175.857359 s; its
measured profile passed in 5,033,425,989 steps and 94.821659 s. The five host
events were 847,906,936 / 16.096082 s, 429,656,409 / 8.391662 s, 455,283,370 /
9.660769 s, 885,700,724 / 18.031729 s, and 1,707,793,658 / 32.904156 s.

Both shapes reported `OK`, zero modeled stalls, normal raw size 1,463,808,
recognized repair health/mask `10/1`, recovery raw size 1,464,320, healthy
post-repair state, and stable repeat output. At 100 MHz the table rows map to
0.858453/0.857931/0.979835/0.979835/2.449127 s and
5.466379/5.465858/5.587762/5.587762/16.273006 s respectively; 50 MHz doubles
those arithmetic values.

## Clock and hardware caveat

The emulator's 64-bit `PERF-CYCLES` counter is the software acceptance metric.
Host wall time is real time on the current host, but includes emulator, boot,
link/load, polling, and harness overhead as identified by each driver. Printed
100 MHz and 50 MHz seconds are arithmetic divisions of guest cycles, not
measured FPGA latency. The emulator reports zero modeled stalls and does not
model shared-BRAM arbitration, 6–10-cycle external-memory latency, SPI-SD or
other storage latency. Synthesis, timing closure, programming, and board
measurement remain separate work and cannot be inferred from these values.

## Explicit nonclaims

This Gate 4 record does **not** close Gate 5. The two applet smoke profiles are
regressions for the existing bounded standalone lens, not evidence for the
complete Library applet experience, recent/sort/path-picking/import/export UI,
or final Desktop-hosted routing.

It also does not claim Pad, Desk, Explorer, Streams, Agent, or Practice
integration; typed cross-component routing; Desk tiles; service bootstrap;
machine-level corpus discovery or migration; sibling imports; public VFS paths;
raised/enterprise-scale bounds; or Gate 8 observation collection. Explorer may
eventually reveal an admitted origin and Desk may route a qualified locator,
but neither receives Library ownership or authority from this gate. No
hardware-performance, ext4, removable-media, or legacy-corpus migration claim
is made.
