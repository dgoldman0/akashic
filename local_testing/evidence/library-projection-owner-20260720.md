# Library projection-owner milestone evidence — 2026-07-20

This is the final-tree evidence for Gate 4 milestone 4 only. It does not claim
milestone 5 or the overall Gate 4 exit.

## Acceptance boundary

The production closure is linked in top-level source chunks; the focused Forth
contract remains an ordinary injected fixture. The final focused image linked
41 production modules in six chunks and packaged 15 MP64FS entries in 4 MiB.

`library-projection-owner-contracts` passed all 723 assertions in
3,697,243,361 emulator steps and 47.57 seconds of host wall time. The matrix
includes typed full-root/reachable-span preflight, active/exact lifecycle
qualification, fixed-RID sharing, independent leases, rollback, stale-token
refusal, retryable/idempotent quiescent release, owner/lease bounds, immutable
capture behavior, ninth-owner and 65th-lease refusal, ambient-store refusal,
and teardown with an unchanged outer data stack.

`library_projection_two_boot.py` passed with a separately spawned emulator for
each boot. Its image linked 42 modules in six chunks and packaged 13 MP64FS
entries. Only serialized disk bytes and the first process's RID, domain
revision, and digest crossed into the second process; no root, registry,
component, `LBIND`, result, or token memory survived. The accepted values were:

- RID: `d2eba1cf12cc96c40bfdd044b9e7c02d84501785dd7981a7daf5aa5e5bc5c1be`
- domain revision: `1`
- projection-content digest:
  `a3ef7f13f6f1c6813f3088f35261859175d19b8122d43257dcb9f8889d95ee7c`

## Fixed memory and cost model

All three efficiency shapes reported the same bounded owner allocation:

| Item | Bytes/count |
| --- | ---: |
| owner root | 4,072 bytes |
| dynamic component state per live RID owner | 128 bytes |
| maximum dynamic state at eight owners | 1,024 bytes |
| live RID-owner bound | 8 |
| activation-local lease bound | 64 |
| projection-index/rebuild allocation | 0 bytes |

Acquire performs bounded root/lease validation, one authoritative identity
lookup, and one exact direct-frame read. Describe performs typed dispatch and
one identity lookup with no content-byte work. Snapshot adds one direct exact
frame. Successful `resource.replace` adds input hashing, content-first durable
publication, complete inactive-bank write/readback, and the store's current
conservative precommit and post-head authoritative reconciliation; that is two
full validations and two disposable-index rebuilds. These cycles include the
existing sealed whole-bank store mutation, not just projection dispatch.
Repeating the stale old-locator replace reads its one retained exact frame and
refuses without validation or reconstruction.
Release performs a bounded lease-ledger scan and, on final release,
unpublishes the fixed-RID component. Root init validates and clears its fixed
borrowed graph/ledgers; root fini requires empty ledgers and wipes that fixed
state. No unchanged interaction rebuilds the Library query index or performs a
fallback arena-prefix scan.

## Final `PERF-CYCLES`

Common interaction cycles:

| Operation | representative, 128 B | byte bound, 65,536 B | owner/lease bound, 4,096 B |
| --- | ---: | ---: | ---: |
| cold store load | 43,836,818 | 97,938,051 | 76,349,807 |
| root init | 1,564,587 | 1,564,587 | 1,564,587 |
| cold acquire | 2,957,075 | 42,203,090 | 5,439,616 |
| describe first | 3,888,477 | 3,886,874 | 3,933,764 |
| describe repeat | 4,009,232 | 4,007,629 | 4,054,519 |
| snapshot first | 6,201,752 | 45,973,067 | 8,715,489 |
| snapshot repeat | 6,281,880 | 46,066,803 | 8,795,613 |
| warm shared acquire | 2,982,822 | 42,228,837 | 5,465,363 |
| replace success | 157,589,246 | 495,847,848 | 265,851,407 |
| replace stale first | 4,917,265 | 44,164,791 | 7,402,403 |
| replace stale repeat | 4,835,519 | 44,078,606 | 7,315,150 |
| shared release | 42,866 | 42,866 | 42,866 |
| final release | 819,089 | 819,089 | 819,089 |
| root fini | 366,751 | 366,751 | 366,751 |

Bound-specific cycles:

| Operation | Count/status | Cycles |
| --- | ---: | ---: |
| acquire all live RID owners | 8 | 44,841,127 |
| refuse ninth distinct RID owner | `RACQ-S-CAPACITY` | 5,629,117 |
| release all live RID owners | 8 | 1,731,073 |
| acquire all leases on one owner | 64 | 349,865,721 |
| refuse the 65th lease | `RACQ-S-CAPACITY` | 5,448,978 |
| release all 64 leases | 64 | 3,851,128 |

Every unchanged describe, snapshot, and stale replace met the driver's
at-most-2x-first-call gate. The measured content-size slopes were 600.018576
incremental acquire cycles per byte, 608.257751 incremental repeat-snapshot
cycles per byte, 5,171.517276 incremental successful-replace cycles per byte,
and 599.973811 incremental stale-repeat cycles per byte.

Direct-read counters matched the exact frame sizes: 512 bytes for the 128-byte
body, 66,048 bytes for the 65,536-byte body, and 4,608 bytes for the 4,096-byte
body. Each replace call performed one direct read. Eight-owner acquisition
recorded eight direct reads/36,864 bytes; the ninth-owner refusal one/4,608;
the 64-lease acquisition 64/294,912; and the 65th refusal one/4,608. Every
measured interaction reported zero fallback arena scans, zero scan
frames/bytes, and zero modeled stalls. Only successful replace rebuilt the
disposable index: twice, matching its two complete authority validations;
every unchanged call reported zero rebuilds.

## Regression matrix

The final tree also passed:

- managed-document, lifecycle, and query/index two-process cold drivers;
- the query/index empty, one-64-KiB, and 32-by-4-KiB efficiency driver;
- 47 packaging tests and Python bytecode compilation for the M4 harnesses; and
- `git diff --check` before staging.

The dependency and applet smoke results were:

| Profile | Assertions | Emulator steps | Host wall |
| --- | ---: | ---: | ---: |
| `gate3a-resource-contracts` | 408 | 420,412,410 | 7.15 s |
| `library-model-codecs-contracts` | 327 | 410,228,099 | 7.35 s |
| `library-store-format-contracts` | 173 | 281,100,203 | 5.58 s |
| `library-vfs-store-contracts` | 400 | 1,565,354,124 | 23.36 s |
| `library-managed-document-contracts` | 169 | 1,585,561,322 | 23.50 s |
| `library-managed-capacity-contracts` | not printed | 4,890,033,815 | 71.99 s |
| `library-managed-lifecycle-contracts` | 226 | 2,303,221,106 | 34.16 s |
| `library-capture-collection-contracts` | 153 | 1,950,448,129 | 26.20 s |
| `library-query-index-contracts` | 587 | 2,084,993,680 | 31.24 s |
| `library-applet-contracts` | 22 | 1,823,752,128 | 22.86 s |
| `library-applet-functional-contracts` | 70 | 2,426,183,921 | 53.82 s |

The emulator cycle counter is the acceptance metric. The displayed 100 MHz and
50 MHz conversions are clock-rate arithmetic, not measured FPGA latency. The
model reports zero stalls and does not model shared-BRAM arbitration,
6–10-cycle external-memory latency, or SPI-SD latency; synthesis, timing
closure, programming, and board measurement remain separate work.
