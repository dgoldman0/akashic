# FIELD desktop qualification

FIELDS passed the complete native-simulator Desk journey on 2026-09-30 and
is selected in the paired desktop profile. SERIES, PANE and TASKBAR retain
independent qualification gates.

## Executed path and evidence

The real unified `megapad.main --mode simulator --executor native` entry point
prepared and ran Desk, dispatched acknowledged input, composed flowing pixels
and shut down. The listener/client loop used in-process SessionServer dispatch
and SDL used a dummy software sink. Socket transport, physical display, audio
and UART are outside this run's scope.

All 52 Desk stages passed, followed by typed Grid PLACE at B2/key 18 and the
FIELD probe. All four ordinary Sound Lab fields retained their original root,
label and value coordinates. Exact acknowledged FIELD identities drove:

- Frequency 440 to 470 using ADJUST +3.
- Frequency to 2000 with maximum signed-64-bit adjustment, then to 40 with
  minimum signed-64-bit adjustment, proving bounded endpoint clamping.
- Waveform 0 to 4 using ADJUST -1, proving choice wrap.
- Frequency ACTIVATE into its ordinary exact-value prompt, followed by Escape
  and restoration of all four fields at revision 5 and unchanged coordinates.

The probe checked whole-CELL prompt fallback against the actual immutable
acknowledged offer. Initial and final STATUS_FIELD evidence covered 19 authored
fields after Sound Lab launch. `Desk-Fields-Adjusted.png` was inspected: field
content stays within existing pane geometry; shell borders and taskbar remain
on their existing path in this checkpoint.

| Measurement | Run |
| --- | ---: |
| Desktop ready | 34.11s |
| Full journey, Grid/FIELD probes and cleanup | 163.97s |
| Peak process RSS | 271.94MiB |
| Acknowledged offers through the 52-stage journey | 87 |

Other development work ran concurrently. These are functional-run timings,
not a controlled performance comparison. The server, owner thread, backend,
display lease, runtime owner and terminal driver all closed cleanly, with no
terminal failures. The historical offer counter stopped at the journey
boundary, so it excludes the subsequent Grid/FIELD probe offers.

## Source provenance

MegaPad: `856f025d7898f7c2c8333d81a08d7f0cc56770ae`.
Akashic pinned base: `dd68f2cc67f9403c9c9d3d3cc901c4c70608884b`, plus the
FIELD-enabled profile, acceptance instrumentation, authoritative control count,
instrument/base layering, prompt-boundary and ordinary underlay fixes.
Tracked-diff SHA-256:
`7fa88d6d37305dc82f640455573d8f0a5f060d0869da31313b39d1ce13148cae`.
Prepared image SHA-256:
`c4b09f3e041c4d3616cfae84bddfced4ee9bdf90b2f2f1d2de17ee98c4b74f57`.

The fixes are incorporated in this branch: `5d5e517`, `5d2534d`, `0026196`
and `c305c2d`. The qualification checkout stayed frozen during the successful
run. The raw report is `build/field-producer-restored/result.json` under the
paired MegaPad checkout.

## Corrections found through integration

The candidate wrapper now uses the authoritative CONTROL count after FIELD
records are appended. Sparse Sound Lab instrument regions sit below the
independently interactive control layer; a captured-frame replay showed zero
changed RGB bytes while all four FIELD hit targets became reachable. Optional
instrument admission rejects overlap with earlier control claims and exhausted
Z ordering before capture.

Closing Sound Lab's ordinary prompt now dirties its underlying status widget
on submit and cancel. Previously an unchanged status value left old prompt
pixels visible and correctly prevented a rich ownership claim. Native widget
regressions proved Escape, unchanged Enter and invalid Enter repaint the
underlay; no application terminal-specific path was introduced.

## Reproduction

```sh
MP64_RUNTIME_NAMESPACE=field-qualification python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output build/field-producer-restored \
  --require-status-fields --require-fields
```

The FIELD activation and prompt-evidence changes also passed 28 focused
acceptance/profile regressions through the MegaPad Make supervisor.
