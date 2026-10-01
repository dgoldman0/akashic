# STATUS_FIELD desktop qualification

STATUS_FIELDS passed the complete native-simulator Desk journey on 2026-09-30
and is now selected in the paired desktop profile. FIELD and later families
retain independent qualification gates.

## Executed path

The real unified `megapad.main --mode simulator --executor native` path ran
through production preparation, owner execution, acknowledged display offers,
input dispatch, software composition and cleanup. Only the Unix listener/client
loop was replaced by in-process dispatch; SDL used a dummy software sink.
Sockets, physical display, audio and UART are not qualified by this run.

All 52 journey stages passed, including menus, launcher, typed list selection,
rename drag/edit/cancel, Unicode Pad/Daybook input and link following. A final
acknowledged typed Grid PLACE selected B2/key 18, returning content revision 59.
Initial status counts by pane were 4/2/2/2/6/0; Sound Lab launches later. Final
counts were 4/2/2/2/6/3, 19 authored fields total, with observed value changes.
The image was inspected and the Grid/status bounds remain within the existing
pane/cell geometry. This qualifies actual retained objects, not an image mockup.

| Measurement | Run |
| --- | ---: |
| Desktop ready | 34.96s |
| Full journey, Grid probe and cleanup | 151.52s |
| Peak process RSS | 288.09MiB |
| Acknowledged offers through the 52-stage journey | 86 |

Other development tests ran concurrently; these are functional-run timings,
not a controlled performance comparison. Owner thread, backend, display lease,
runtime owner and terminal driver all closed cleanly. The historical offer
counter excludes the subsequent Grid probe offer.

## Source and allocation provenance

MegaPad:`856f025d7898f7c2c8333d81a08d7f0cc56770ae`.
Akashic:`15d4976e54b2aa87b6f4297534a40d791038c8c4` plus the status-enabled 384MiB profile and
acceptance changes in the pinned qualification checkout.
Image SHA-256:`249dc37507f5b770c1c65d60bcefaf2f5792f6c7d03d44bc358668fcf8b96ffa`.
Akashic tracked-diff SHA-256:`fc0662ffc4d5150b1339f24945c9bf9a40488b4d9c94010650f198bbb471a21c`.

The former 320MiB profile exhausted external memory while preparing this exact
STATUS source checkpoint. At 384MiB, real native preparation completed with
XMEM-HERE=380189824 and XMEM-LIMIT=403701760, leaving 23511936 bytes (22.423MiB)
before live Desk. This preserves declared UI capacities; networking allocations
also depend on partition size. Generic static-bank right-sizing remains open.
The newer FIELD composition has its own image preparation/qualification gate.

## Acceptance corrections exercised by the real run

Typed status values stay outside visible-text marker evidence. Selected file
paths and Pad caret state use exact authored STATUS_FIELD claims in the current
ordinary status row. Broad proportional tile bounds are insufficient for exact
row checks: Desk reserves divider cells and UIDL currently leaves an unused
bottom content row. Helpers now derive actual pane bounds; strict prompt checks
exclude dividers while still rejecting unexpected text inside the prompt.

The journey's initial ready condition includes only the first five applets;
Sound Lab coverage is required after its actual launch, at the final snapshot.
Failures and waiting states now save the actual offer and composed image for
replay. Focused regressions cover typed/legacy paths, decoy status values,
wrong rows/slots, actual divider cells and replay of the previously stalled
offer. The existing whole-CELL modal fallback check also covers STATUS_FIELD.

## Reproduction

```sh
MP64_RUNTIME_NAMESPACE=status-acceptance python local_testing/run_headless_grid_acceptance.py \
  --megapad-root /path/to/megapad --output build/status-producer-qualification \
  --require-status-fields
```

The runner writes `result.json`, the image, exact retained offers, input evidence
and initial/final/selected PNGs. FIELD-era failure diagnostics use that newer
producer layout; the recorded STATUS run retains its own source/diff hashes.
