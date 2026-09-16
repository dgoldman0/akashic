# Instrument reuse physical qualification — September 16, 2026

The ordinary native Desktop journey passed with the unchanged-instrument
publisher enabled. It exercised Pad editing/menus/tabs, Daybook task/date/source
interactions, the ordinary Sound Lab continuation, File Explorer View and
Daybook Go popups with instruments live, and final Sound Lab focus restoration.
The complete Desk, View popup, and Go popup captures were visually inspected.

## Bound sources and execution

- Akashic: `3b5638c1d80abcc89d2f2fdc057503cc5aa231fb`, including implementation
  commits `aa300ee` and `dacd9ad`.
- MegaPad: `eaa4d3bfefbc1a5c2b1b17c880a09729849d3afe`.
- Both repositories were clean and unchanged during the run.
- Native extension SHA-256:
  `a94e93df6ef1d223c47734c248ac2a061645e800b0f6addeb968297b507ccb38`.
- Existing physical wrapper SHA-256:
  `9d3959eb7227dc9857fd874d04c81d6831f6f1f8bf1b7315ef15eeb099668fdb`.

The existing wrapper was invoked from the workspace root:

```sh
python3 worktree-retirement-archives/2026-09-13-rich-interaction/retired-support/diagnostics/physical_menu_acceptance.py \
  --akashic-root /home/kir/Documents/Projects/fantasy-computing/akashic \
  --megapad-root /home/kir/Documents/Projects/fantasy-computing/megapad \
  --font /home/kir/Documents/Projects/fantasy-computing/akashic/assets/fonts/DejaVuSansMono.ttf \
  --output-parent /home/kir/Documents/Projects/fantasy-computing/akashic/local_testing/out/instrument-reuse-20260916
```

It built a fresh ordinary `desktop-apt1` source image, used native semantic
execution, 280×84 geometry, 18 px DejaVuSansMono, a 0.75-second action delay,
and a 10-second final hold. No compiled Forth cache or exit profiler was used.
X11 `pygame.display.flip` remains the physical reference-sink boundary; this
does not measure an external UART or hardware panel.

The successful artifact directory is
`local_testing/out/instrument-reuse-20260916/physical-menus-b6xygsvm/`.
It records **26 physical ACKs, 21 accepted inputs, 18 captured milestones,
and both CELL fallback gates**. Inputs used the exact acknowledged offer and
hit map; manual input RPC count was zero. All later menu frames retained eight
readouts, two meters, and three status indicators in one instrument region.

Supervised elapsed time was **186.077 seconds**, peak aggregate RSS was
**437.355 MiB**, and exit status was zero. The existing 3.5 GiB memory guard
and 900-second watchdog were unchanged, and neither fired. Checks ran
sequentially; system memory checks during the live journey showed roughly
9–10 GiB available. The preceding implementation selector passed 320 focused
checks in 16.42 seconds without workers or enlarged helper budgets.

An initial sandboxed attempt, `physical-menus-xlqd3wzu`, failed to bind its
local Unix socket before Desktop startup. It was interrupted and its process
cleanup verified before the run with local socket/display access began. It is
not performance or functional acceptance evidence.

## Matched interaction observations

The baseline is the September 13 main integration run documented in
[its ledger](rich-main-integration-20260913.md). Both runs used the same
wrapper, native binary, geometry, font, action delay, and final hold.
Latency is input RPC start through the next action's authorizing ACK, including
all intervening offers. Counter deltas use the corresponding status samples,
not an exact exclusive measurement of the input handler.

| Interaction, instruments live | Before | After | Decoded bytes before → after |
| --- | ---: | ---: | ---: |
| Focus File Explorer | 7.969 s | 2.534 s | 168,730 → 3,172 |
| Open View menu | 7.953 s | 2.923 s | 170,478 → 4,965 |
| Close View menu | 8.093 s | 3.143 s | 170,478 → 4,917 |
| Focus Daybook | 7.400 s | 2.613 s | 168,422 → 2,912 |
| Open Go menu | 7.957 s | 2.896 s | 169,114 → 3,371 |
| Close Go menu | 8.239 s | 3.064 s | 169,114 → 3,467 |
| Restore Sound Lab focus | 8.103 s | 2.760 s | 168,566 → 3,056 |

Each of these interactions now uses one acknowledged offer instead of two.
Together they changed from 55.715 to 19.933 seconds, 767,389,618 to
393,857,407 sampled semantic steps, and 1,184,902 to 25,860 decoded bytes.
The full journey changed from 224.407 to 186.077 seconds.

These are single-run observations under ordinary host load, with Daybook's
runtime date also advancing between runs. They are not controlled throughput
estimates. The protocol reduction and preserved physical app state establish
that the intended reuse path is exercised.

The separate typing baseline remains: Pad character latency was 2.448 seconds
before and 2.574 seconds after, with 51,227,073 versus 49,342,777 sampled
semantic steps. Task prompt typing was 2.200 versus 2.630 seconds. Prompt
opening/submission still crosses two offers and uses complete replacement.
This slice resolves the instrument-driven replacement penalty; it does not
resolve baseline typing or the shared prompt representation.

## Evidence fingerprints

- Physical manifest SHA-256:
  `af580109d8ba25513d5af3f49f633d3b020a916595b75a5adaacecdf9a766edb`.
- Performance trace SHA-256:
  `dd5decbb0acabf5939dc2abd55cd939699e2138aad8e0060d18f7cddb43add9f`.
- Source/runtime bindings SHA-256:
  `ce007a380267fc00a901aa4d01a349bdf554de65bb52eafadea37e8fa8daa268`.
- Supervisor result SHA-256:
  `6d00e74a7ebaa2927c66073499163b65c4dba97850a3773a3ac3306c30098698`.

The ignored output parent retains `comparison.json` and
`compare_instrument_reuse.py` to reproduce all 21 interaction intervals from
the two raw traces and manifests. The durable summary above remains available
if local captures are later removed.
