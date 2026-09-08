# Rich Desktop closure — emulator acceptance, 2026-09-08

Status: successful reacceptance of the existing full rich Desktop journey on
the emulator at the local X11 presentation boundary. This record closes the
previous emulator acceptance failures; simulator acceptance remains a separate
result. It adds no application or terminal feature to the selected journey.

## Exact revisions and invocation

The run used the two rich-terminal feature worktrees, recorded clean at launch:

- Akashic `75952bd21ed70b85d2a8b324e0cdcf713eb9a594`;
- MegaPad `65cf61ddbe12888f1dce8d8e2af644b0b2bdaba8`.

From the Akashic worktree, with `MEGAPAD_ROOT` selecting
`../megapad-rich-terminal-vertical`, the measured command was:

```text
python -u local_testing/akashic_tui.py accept \
  --profile desktop-apt1 --backend emulator \
  --output local_testing/out/close-20260908-emulator-r1.img \
  --socket /tmp/akashic-close-20260908-emulator-r1.sock \
  --artifact-root local_testing/out/close-20260908-emulator-r1
```

Effective settings were the canonical 280x84 geometry, 18-pixel X11 pygame
font, 320 MiB external memory, timing-correct single-lane native emulator,
realtime RTC, 900-second acceptance timeout, 0.75-second scripted action delay,
and ten-second post-pass hold. The optional phase observer was off. The build
used checked cold stored source: 212 modules in 33 chunks, 4,028,291 source
bytes in 4,029,611 container bytes, both optional MegaPad system modules,
ten resources, and ten directories. The 32 MiB MP64FS image had 63 entries and
55,732 free sectors at build time; this is not a post-run filesystem count.

## Result and prior failure closure

The command printed `Physical desktop acceptance: PASS` and exited zero.
The trace has 92 contiguous events, with exactly one observation, completed
projection, and post-flip acknowledgement for each offer 1 through 20. All
14 input RPCs returned `progress` after their exact authorizing offer's ACK.
The manifest records 11 physical milestones, exact initial/final CELL fallback
evidence, and zero manual-input RPCs. No trace event records an error.

The ordinary Pad menu opens and closes, the `~` edit survives, Daybook's real
prompt accepts and saves `^`, navigation advances its acknowledged date from
2026-09-08 to 2026-09-09, its shared `/daybook.md` opens in Pad, and retained
tab activation restores the original edit. The ordinary launcher then opens
Sound Lab and the final frame preserves the exercised Pad/Daybook state.

This passes the Daybook prompt transition corrected at `11c6a6d`, then crosses
the stage-8 checkpoint where the September 4 `11c6a6d`/`8c6b102` run stalled
despite complete CELL/rich output. Akashic `b4d52e5`, contained in this run,
replaced the fixed September 2 date predicate with the date from the exact
acknowledged Daybook header; the new run proceeds through navigation and final
acceptance on September 8. The evidence therefore closes that known harness
failure without weakening the date or displayed-frame requirements.

The final offer has model/CELL/retained scope 23/23/23, 1,016 draws, six menu
forests, two text areas, one text grid, two tabsets, eight readouts, two meters,
three status objects, 173 instrument cells, and no clipped region. Its
retained-only raster contains 5,359,810 nonblack pixels. The recorded physical
completion boundary is `pygame.display.flip`, followed by the exact offer ACK.

## Comparable checkpoint timing

Times below are trace seconds since runner startup, taken from the
`offer_acknowledged` event for each milestone's exact offer. Artifact-write
timestamps occur later and are not substituted for physical completion.

| Acknowledged checkpoint | Offer | Seconds |
| --- | ---: | ---: |
| Complete initial Desk | 1 | 486.098092178 |
| Daybook task saved, stage 8 | 11 | 578.061029954 |
| Daybook date advanced | 12 | 587.697482776 |
| Final Sound Lab frame with preserved Pad/Daybook state | 20 | 682.191468000 |

Initial-Desk to saved-task ACK took 91.962937776 seconds; initial-Desk to final
ACK took 196.093375822 seconds. The manifest was recorded at 683.264295037
seconds and acceptance finished after its hold at 693.264483012 seconds.
External `/usr/bin/time -v` measured 697.75 seconds (11:37.75), with maximum
reported RSS 439,996 KiB and no swaps.

External wall time includes image packaging and process teardown. Trace time
starts just after server launch, excludes packaging, and includes connecting,
guest startup, rendering, input delays, and artifact recording. The ten-second
hold is included only in runner/external completion, not the final ACK time.
These are one-run host diagnostics, not a controlled performance comparison.
Any backend comparison must use the same checkpoints and delay/hold settings.

The final pre-screen status sample counted 9,323,500,000 retired emulator
instructions, 18,647 batches, 6,627 decoded frames, 1,534,807 decoded bytes,
426 machine publications, 1,536,963 publication bytes, and zero buffered
decoder bytes. These status counters precede the screen RPC; they are not exact
ACK-time counters. Simulator semantic-step counts are a different unit and
must not be compared as retired emulator instructions.

## Raw artifact binding and limits

Raw output is retained under
`local_testing/out/close-20260908-emulator-r1/`. The directory has 38 files:
the five records below and complete PNG, retained-only PNG, and retained text
for each of 11 milestones. Both JSON evidence files parse, all retained-text
hashes match their manifest records, and all 22 PNG headers specify 3080x1764.

| File | SHA-256 |
| --- | --- |
| `manifest.json` | `34b67c6ab7cbe7d314ec612880d9c1bc66907f78daf35957ea2b5eab4039af8a` |
| `performance-trace.json` | `613abce5d5aa8f98c646edf0a96182d0618c1c3f9264db2c0f520b112d066fa4` |
| `run-revisions.json` | `0fec4bf8ad4c8dca7d2028ddd5d62a7e35e5c627b35f655c5487a1a77fc42d29` |
| `run.log` | `6cdc57c6016903c02590395bf94768798ce107466d3c08b675f5d93a06b39d58` |
| `wall-time.txt` | `c6df7dd447165ced19af6cc97a1359680da1bbb0753d037fcf0373aed63295b6` |

The manifest binds the complete, retained-only, and retained-text frame hashes;
its raster hashes describe raw surface pixels, not PNG encoding bytes.
`local_testing/out/` is ignored, so this ledger should remain the durable record.
This is one emulator session and geometry through the existing software viewer.
It does not qualify the semantic simulator, physical UART/panel completion,
touch, reset/resize, persistence, sustained cadence, or new semantic families.
