# Native bulk and pointer execution — September 16, 2026

Ordinary string, memory and stack-pointer operations now stay inside the
native Forth interpreter. The physical typing comparison improved from
1.262 s to 1.121 s for an isolated character and from 2.531 s to 1.591 s for
the burst median. All 19 characters were retained. These are individual
shared-host runs, not a latency distribution or a fluid-typing pass.

## Implementation

MegaPad commits `127112e`, `d2ee98a` and `7a76542` add native `COMPARE`,
`FILL`, `CMOVE`, `CMOVE>`, `MOVE`, `SP@` and `RP@`. Full-span preflight
preserves sparse pages, unsigned comparisons, each copy's overlap semantics,
host page aliasing, return-stack protection and reference partial faults.
MMIO, wrapping and unsafe spans still enter the reference operation before
effects. Only original BIOS primitive identities are admitted.

Successful `RP@` reads settle their capture count into Python's unbounded
return-stack generation before callbacks, faults or suspension. Overflow
retains capture registration before the push fault. `4d2f90d` removes the
unnecessary numeric interface version and compatibility gate introduced with
that change. The extension and Python owner use one current internal
interface and are rebuilt together.

`fe31e71` keeps the bulk handlers in a non-inlined helper. Their allocation
and cleanup no longer enlarge the scalar dispatch loop: the compiled run
body fell from 10,875 to 8,675 bytes on this build. Five alternating process
pairs measured 2.8–14.0% higher throughput on the existing scalar kernels
than the initial inline bulk implementation. Raw trials are preserved in
`local_testing/evidence/interpreter-bulk-outlining-20260916.json`.

Guest steps, virtual clocks, the 8,192-step native allowance, source loading,
physical input/ACK rules and capacities are unchanged. Akashic production
Forth remains identical to `de6a6aa`; no applet or renderer shortcut was added.

## Bounded kernels

Five alternating sequential process pairs use the existing four trials per
kernel and unchanged 1.5-million-step RUN limit. The table uses the 15 warmed
trials per build. Each extension loads its matching Python owner because the
return interface changed; both hashes are recorded. Every trial has the
same semantic count and result cells before and after.

| Kernel | Previous build | Final build | Speedup | Steps |
| --- | ---: | ---: | ---: | ---: |
| arithmetic | 1.930 ms | 1.967 ms | 0.98x | 380,008 |
| field_reads | 4.684 ms | 4.724 ms | 0.99x | 640,028 |
| loop_calls | 5.023 ms | 4.140 ms | 1.21x | 200,005 |
| dynamic_calls | 5.371 ms | 4.555 ms | 1.18x | 240,005 |
| scattered_reads | 2.833 ms | 2.569 ms | 1.10x | 520,008 |
| compare_strings | 158.446 ms | 1.518 ms | 104.39x | 110,017 |
| fill_bytes | 108.226 ms | 1.635 ms | 66.19x | 80,008 |
| forward_copy | 144.652 ms | 1.842 ms | 78.53x | 130,023 |
| move_bytes | 140.424 ms | 1.941 ms | 72.34x | 130,023 |
| stack_pointers | 132.537 ms | 1.809 ms | 73.27x | 130,005 |

The large gains apply to kernels that previously crossed Python on every
iteration. Arithmetic and field reads are within 2% of the previous build;
there is no comparable whole-interpreter multiplier. Raw trials and bindings:
`local_testing/evidence/interpreter-bulk-kernels-20260916.json`.

The previous extension is from MegaPad `193c54c` (the same executor as
`15613d8`), SHA256
`49a9386fcdc1747192ce1e385b219bd12514f301c8197ddfb412528be084e0fb`.
The final extension at `fe31e71` is
`b6f7c92fcf51b34a7e8cf8ed2cd0536e9bc0741c494b2b936fb71ae3803616e7`.

## Physical typing

Both runs use ordinary source-mode `desktop-apt1`, the normal keyboard
forwarder, complete X11 compositions at 3080×1764 and exact post-flip ACKs.
One isolated character precedes 18 individually scheduled characters at 5 Hz.
Native profiling is disabled. No source, step or watchdog override is used.

| MegaPad | Isolated character | Burst median delay | Last-character drain |
| --- | ---: | ---: | ---: |
| `15613d8`, previous pass | 1.262 s | 2.531 s | 2.274 s |
| `fe31e71`, bulk and pointer primitives | 1.121 s | 1.591 s | 1.347 s |

The observed reductions are 11.1%, 37.1% and 40.8%, respectively. Scheduling
delay is separate from dispatch-to-ACK latency: the latest maximum was
232.901 ms, versus 288.148 ms previously. All 19 inputs were accepted and
the final Pad text was `~fluid typing 12345`.

Artifact `local_testing/out/typing-20260916/fixed-gt5zpk40/` binds clean
MegaPad `fe31e71` and Akashic `5bd5ac5`. It completed in 60.137 s including
fresh source preparation, with 393.414 MiB peak aggregate RSS and no guard
stop. Composition alone ranged from 132.757 to 171.505 ms across its seven
complete frames. The roughly 100 ms feedback target is still unmet.

## Validation and next work

The native-default execution, bulk, pointer, memory, loop, clock, quantum,
CATCH, snapshot and session selector passes 726 cases in 7.72 s. Coverage
includes exact budget boundaries, sparse allocation, fragmented pages,
overlap and host aliases, partial MMIO faults, shadowed words, unbounded
capture generations, overflow, callbacks and cancellation.

The full ordinary physical Desktop/menu journey also passed at the same
clean source and binary bindings: 18 milestones, 21 interactions, 26
post-flip ACKs and both complete CELL fallback gates. The milestone and
input sequences match the previous journey; the count of intermediate
offers is not fixed. It took 127.555 s with 439.965 MiB peak aggregate
RSS, exit 0 and no guard stop. The sink was `pygame.display.flip` on X11,
with zero manual input RPCs. Artifact:
`local_testing/out/typing-20260916/physical-menus-vjtw2luk/`.

All checks ran sequentially. The physical runs kept the existing 900 s and
3.5 GiB guards, and system available memory stayed above 8 GiB. Exact commands
and artifact paths remain in `local_testing/evidence/typing-20260916.md`.
Machine-readable physical results and timing events are preserved in
`local_testing/evidence/interpreter-bulk-physical-20260916.json`.

The next interpreter candidates are call/return metadata construction and
host suspension snapshots, followed by a measured comparison of threaded
dispatch and additional superinstructions. Their benefit remains unmeasured.
The typing trace also demonstrates a separate compositor cost; faster guest
execution alone cannot meet the current feedback target at this viewport.
