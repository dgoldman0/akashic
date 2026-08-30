# Rich Desktop cold-source measurement — 2026-08-29

This ledger preserves the stored-versus-LZSS measurement that accompanied the
32 MiB MP64FS migration for the rich Desktop profile. It is diagnostic evidence
for packaging and future boot work, not rich-terminal vertical acceptance.

**Akashic revision:** `77f1af95e7cf4c05ab68fdc74db2755cd2eadf13`

**MegaPad revision:** `35e52bba1a552741f436664c5d754b5e73930693`

## Measurement boundary

Both sequential runs used the ordinary `desktop-apt1` closure, a 32 MiB
MP64FS image, one timing-correct core, 128 MiB of external memory, and a
280-by-84 physical rich-terminal session. The closure contained the same 201
modules, 27 checked `AKSRC001` source chunks, and 3,277,942 raw source bytes.
The source closure and profile inputs were identical. The LZSS comparison
image was built by overriding only the profile's explicit source-container
codec:

- stored source containers: 3,279,022 bytes;
- LZSS source containers: 855,433 bytes.

No pre-run whole-image digest was captured. The timing harness calculated its
image digest after execution, when ordinary guest persistence could already
have changed unrelated media state, so those post-run digests are deliberately
not used as input identities here.

The stop boundary was the exact boot marker
`[akashic boot] entering Desk`. The run did not claim a completed Desk frame,
Pad or Daybook interaction, frame acknowledgement, or any other post-entry
rich-terminal acceptance condition. Status was sampled in 500,000-step
batches, so marker step counts have that resolution. Times below are emulator
machine uptime at the sampled marker, not the outer harness's teardown time.
The LZSS process continued beyond the marker while the stored process stopped
there; all later LZSS work and post-run media changes are excluded. Each codec
was run once, so guest-work deltas are the durable comparison and host-wall
deltas are a revision-bound estimate rather than a cross-host benchmark.

## Codec result

| Scope | LZSS | Stored | Stored saving |
| --- | ---: | ---: | ---: |
| Boot through Desk entry, guest instructions | 14.502B | 13.266B | 1.236B (8.523%) |
| Boot through Desk entry, machine uptime | 242.464602 s | 220.343383 s | 22.121218 s (9.123%) |
| Loader ready through framework ready, guest instructions | 13.6035B | 12.354B | 1.2495B (9.185%) |
| Loader ready through framework ready, machine uptime | 226.858610 s | 203.849422 s | 23.009188 s (10.143%) |

Stored containers made this exact boot 1.1004 times as fast through Desk entry.
They removed decompression and its second payload allocation without weakening
the checked header, raw length, CRC, evaluator diagnostics, cleanup, or
dictionary rollback contracts. The larger MP64FS geometry supplied the needed
space rather than reducing the canonical free-space reserve.

The result is useful but not an order-of-magnitude change. In the stored run,
the checked-source-loader-to-framework interval consumed 93.125% of all guest
instructions through Desk entry. Every source line was still parsed and every
definition was still compiled. Stored source is therefore the right default
representation for this volume, but it is not a compiled dictionary, warm
cache, or restorable executable image.

## Growth within the source load

The chunks were bounded to almost equal raw byte sizes, which permits a useful
order diagnostic:

| Chunks | Raw bytes | Guest instructions | Instructions/raw byte |
| --- | ---: | ---: | ---: |
| 1--9 | 1,101,557 | 2.4015B | 2,180 |
| 10--18 | 1,104,277 | 3.9510B | 3,578 |
| 19--27 | 1,072,108 | 5.9995B | 5,596 |

The final third required 2.50 times the guest work of the first despite having
2.7% fewer raw bytes, and its normalized cost was 2.57 times larger. Chunk 1
used 197 million instructions for 122,808 bytes, or 1,604 instructions per
byte. Chunk 22 used 974.5 million for 122,420 bytes, or 7,960 instructions per
byte: 4.96 times the work for almost the same volume.

This proves that cold-source work is not proportional to bytes alone. It does
not by itself assign all growth to one cause: later modules have different
token mixes and may perform more load-time initialization. MegaPad's
`EXT.DICT` policy is nevertheless a credible contributor. Its 64-set,
four-way cache holds 256 names and performs no eviction when a set fills.
`DINS` then reports overflow, and a later `DFIND` miss falls back to a
latest-first linked-list walk through the growing dictionary.

A future performance pass should first instrument dictionary requests, hits,
misses, insertion overflows and linked entries visited alongside per-module
token and initialization work. That evidence can distinguish a lookup-index
repair from work that only a validated compiled dictionary or restorable image
would remove.

## Step and hardware interpretation

One emulator step is one retired MP64 guest instruction, not one emulator
virtual cycle or hardware clock. Retired steps measure architectural software
work. The separate virtual-cycle model drives deterministic timers, devices,
scheduling, strict execution, and replay. RTL or silicon clocks belong to one
physical implementation and determine its realized CPI. A pipeline redesign
therefore does not require the architectural emulator to simulate every
pipeline bubble.

The stored run averaged approximately 60.2 million guest instructions per host
second. Guest-compute time for a particular hardware implementation follows

```text
seconds = guest instructions * realized CPI / clock frequency
```

For 13.266 billion instructions, a hypothetical modernized ASIC sustaining
1.0--1.2 CPI at 2--4 GHz gives arithmetic bounds of about 3.3--8.0 seconds.
At 2--4 CPI the bounds are about 6.6--26.5 seconds. These are scenarios, not
claims about the current 100 MHz FPGA RTL, its memory stalls, or timing
closure. They also exclude physical transport, terminal decode and composition,
display refresh and settling, and input return. Reaching 2--4 GHz would itself
require an ASIC-oriented pipeline, cache, SRAM, memory-system, and peripheral
clock-domain redesign. A roughly 1--2 average-CPI target is a MegaPad RTL/ASIC
goal for common hot work, not a universal instruction latency or an Akashic
contract.

Cold boot is also not evidence that the running Desktop remains source
interpreted. The outer interpreter/compiler performs the large boot-time
build; compiled colon definitions subsequently execute emitted MP64 code.
Higher-level binary resources do not remove this cost unless a future format
also captures and safely restores the compiled dictionary and its audited
load-time state. Such a saved or precompiled dictionary can improve boot, but
does not by itself reduce already-loaded interaction instruction counts.

## Future decision boundary

The current result does not make compiled shards a prerequisite for completing
the rich-terminal vertical. It does preserve the reason to revisit them for a
100 MHz-class FPGA, instant-on behavior, frequent cold emulator iteration, or
energy-sensitive hardware. Source mode remains the canonical cold-build and
qualification path. A compiled path must not land until a real cold build,
warm Desktop smoke, and source/warm equivalence run pass and show useful wall
savings without consuming the Desktop's required MP64FS reserve.
