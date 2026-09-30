# SERIES/WAVEFORM desktop qualification

SERIES passed the complete native-simulator Desk journey on 2026-09-30 and
is selected in the paired desktop profile. PANE and TASKBAR retain their
independent qualification gate; this run did not enable the shell producer.

## Executed path and sample evidence

The real unified `megapad.main --mode simulator --executor native` entry point
prepared and ran Desk, dispatched acknowledged input, composed flowing pixels
and shut down. The listener/client loop used direct in-process SessionServer
dispatch and SDL used a dummy software sink. Socket transport, physical display,
audio playback and UART are outside this run's scope.

All 52 Desk stages passed, followed by typed Grid PLACE, the FIELD probe and
the 13-stage SERIES probe. Ordinary FIELD activation set Sound Lab duration
to 2000ms; ordinary F5 rendered a genuine 16,000-sample history. Every signed
64-bit sample and timestamp in the acknowledged retained history was compared
with the paused ordinary Sound Lab canonical UDG source. No decimation or
substitute sample data was used. Uniform sampling was 125 microseconds, from
timestamp 0 through 1,999,875 microseconds.

The probe then changed amplitude through the ordinary exact-value prompt and
rendered again. The second full history differed from the first and matched
every sample of its changed source. Both renders retained the authored waveform
bounds `[188, 54, 278, 66]` (left, top, right, bottom).

| Acknowledged offer | Amplitude | History identity (owner, generation, series) | WAVEFORM ID |
| --- | ---: | --- | ---: |
| 112: first render | 75% | `(1, 1, 25)` | 39121 |
| 122: changed render | 40% | `(1, 1, 27)` | 43150 |
| 123: ordinary Down selection | 40% | `(1, 1, 27)` | 43150 |

Offer 123 strictly proved stable reuse: selection moved from `Amplitude (%)`
to `Duration (ms)`, while history identity, WAVEFORM identity, bounds, all
16,000 samples and the ordinary source graph hash remained unchanged. The
recorded publication mode is `stable_identity`, with no relaxed replacement
substitution. Sample SHA-256 values were:

- First render: `f3f4a68dd3897f155e03c306f7cb3ac5042fa405ecb9b7e16a26ddda1a55fbf2`.
- Changed render and stable reuse: `5dcb18ee44497dee2e657f759826447d5d79d38aa7a3c850a10ecf158d030bd3`.

The corresponding source graph SHA-256 values were
`b49a7e1e1a508e46ceaf0e701dcae506443bf67d9778c90b6f67370f5dc660cc`
and `ebdf98283326532f08738190785b2af777066c9fcd1f273e741f750e38e5a400`.

## Run measurements and cleanup

| Measurement | Run |
| --- | ---: |
| Desktop ready | 35.501137646s |
| Full journey, Grid/FIELD/SERIES probes and cleanup | 207.909071056s |
| Peak process RSS | 275.2109375MiB |
| Acknowledged offers across the full run | 123 |

These are functional-run measurements, not a controlled timing comparison.
The offer counter includes the probes after the 52-stage journey. Server,
owner thread, backend, display lease, runtime owner and terminal driver all
closed cleanly; the launcher exited 0 and recorded no terminal failures.

The profile used 384MiB external memory, with finite SERIES limits of 32,768
samples per history, 65,536 total reserved sample slots and 4,096 samples per
append. Complete changed histories publish within one candidate transaction;
cross-transaction streaming was not part of this qualification.

## Source provenance

MegaPad: `fb94adec7d234d7721137be291c06e6190fc016f`, with no tracked diff.
Akashic pinned base: `04b4f5a5544501b88564de646a2d6fa5e7692466`, plus the
FIELD/SERIES-enabled profile, acceptance instrumentation, ordinary Sound Lab
prompt-underlay repair and SELECTED-only FIELD delta correction.
Akashic tracked-diff SHA-256:
`c7f5dc50d95663c65063f37be9b1ba9b7326c9ccd55d0e8eed17cabc3c6887c6`.
Prepared image SHA-256:
`074614a0493518716e59a59a443c27b207f28259481bf94b608abb9a8dd72ed6`.

The raw report is `build/series-selection-final/result.json` under the paired
MegaPad checkout. `series-selection-final.log` records the completed 13-stage
probe, and `Desk-Series-Verified.png` accompanies the retained-offer evidence.
The source hashes in the report match the frozen qualification checkout.

## Correction found through integration

The first full run correctly compared both complete histories but exposed a
selection-only FIELD change forcing complete owner replacement. The generic
producer now permits CONTROL-REPLACE when only the SELECTED bit changes and
label, shortcut, FDC1 content/revision, geometry and accounting remain exact.
Other state, content, revision or geometry changes retain the full-replacement
requirement. This preserves unchanged SERIES/WAVEFORM identities during
ordinary selection without introducing application terminal-specific behavior.

Six focused mixed FIELD/SERIES regressions cover all 16,000 immutable samples,
unchanged identities, refusal of incompatible changes, and real PT/host
publication of two CONTROL-REPLACE frames with no SERIES define/replace/append.
The FIELD producer, SERIES producer, FIELD provider and instrument regression
suites passed 244 cases; the qualified profile/packaging gate passed 31 cases.

## Reproduction

```sh
MP64_RUNTIME_NAMESPACE=series-qualification python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output build/series-selection-final \
  --require-status-fields --require-fields --require-series
```

Use the recorded source/profile checkpoint to reproduce the exact evidence.
The runner writes the report, prepared image, acknowledged offers, ordinary
source comparison evidence and composed PNGs.
