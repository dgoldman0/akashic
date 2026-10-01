# Typed Grid desktop qualification

The typed Grid producer and ordinary input path passed the full headless Desk
journey on 2026-09-30. GRID_CELLS is selected in the paired desktop profile;
other new families remain subject to their own qualification.

## Executed path and evidence

The real unified entry point ran simulator mode with the native executor.
The harness substituted only the Unix listener and its client loop with
in-process dispatch, and used the production compositor with an SDL dummy
sink. It acknowledged every rendered offer before submitting input.

After all 52 Desk stages, the harness found the typed Grid from its authored
NUMBER/FORMULA roles, resolved NUMBER item 18 through the acknowledged hit
map, and sent PLACE with the exact content revision. The next acknowledged
snapshot changed the primary key from 1 (A1) to 18 (B2), displayed value `3`,
and carried content revision 60. Grid bounds were x=[0,88), y=[44,81).
The rendered image was inspected: selection stayed within B2's cell bounds.

The native backend, owner thread, terminal driver, display lease and runtime
owner all closed cleanly. This covers in-process transport and software
composition; it does not qualify sockets, a physical display, audio or UART.

| Measurement | This run |
| --- | ---: |
| Desktop ready | 34.35 s |
| Full journey plus Grid selection and cleanup | 124.41 s |
| Peak process RSS | 284.25 MiB |

Other development checks ran concurrently. These are functional-run timings,
not an isolated performance comparison with earlier Desk measurements.

The run used MegaPad `2293ea1d60c1dc0adeab5f4cf652b146e8dd9ee7` and Akashic
`ec42df92457b8e33ff53d101900aa98a7ac390a3` plus the GRID_CELLS profile,
acceptance-pointer helper and Grid coordinate correction. The built image
SHA-256 was `aaa9ba35caa818f83de52b46eabe8a431df80e1c8d88879d3215805dcb64fbb6`.
The run's Akashic tracked-diff SHA-256 was
`6c4e9354d1debacb00de4a928352203a06070e19b0b1450db4453848311c6cd8`.
The adjacent status-string stack correction was separately qualified by the
focused real-Grid source test; the image had already been built when that
correction was made.

## Defects found and covered

- The panel guard decoded packed coordinates as column/row before applying
  row/column bounds. A typed event at the lower-left pane was dropped.
  The regression uses row 44 / column 0, actual panel and TGRID handlers,
  primary-key rebuilding, four outside edges and unselectable headers.
- Grid's ordinary status update left its cell pointer on the stack for known
  cell types. Removing the unnecessary duplicate balances every CASE arm.
  The same native-source test asserts empty data and return stacks.
- The acceptance pointer helper allowed PLACE only for TEXT_AREA. It now
  allows selectable TEXT_GRID cells too, while rejecting headers, absent
  items, nonzero grid scalar offsets, EXTEND and FOLLOW.

The focused real-Grid closure checks passed (2 tests, including 23 Forth
route/selection assertions). The complete desktop-acceptance unit suite
passed (120 tests). The earlier profile/publisher/application-boundary gate
passed 296 cases; its sole stale prose assertion was removed and the three
application-boundary tests passed on rerun without weakening authority checks.

## Reproduction

From the Akashic checkout with the paired MegaPad native extensions built:

```sh
MEGAPAD_ROOT=/path/to/megapad MP64_RUNTIME_NAMESPACE=grid-acceptance \
  python local_testing/run_headless_grid_acceptance.py \
    --megapad-root /path/to/megapad --output build/grid-producer-qualification
```

The runner writes the image, initial/final/selected PNGs, retained offers,
input evidence and `result.json`. It records both repository heads and
tracked-diff hashes so an uncommitted run is identifiable. The Grid probe
has a 20-second response deadline in addition to the full-run deadline.
