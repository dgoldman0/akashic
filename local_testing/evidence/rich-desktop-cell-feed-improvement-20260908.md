# Rich Desktop CELL-feed correction — 2026-09-08

Status: the redundant inner engine-storage check is removed and the focused
public CELL-feed path remains correct. A sequential two-row measurement shows
lower semantic work and elapsed feed time. This does not establish complete
Desktop throughput, physical presentation, or simulator rich acceptance.

## Change and exact source binding

Akashic `6ada8881884bb79d036a28cab76ab0de1e571247` removes the second
`_RTAPT-ENGINE-STORAGE?` call inside `_RTAPT-CELL-FEED-READY?`. Its three public
callers still validate storage first, return any latched quarantine status
next, and then check feed state and shape. Invalid-storage rejection and
quarantine/busy ordering are preserved. All 11 focused structural checks pass.

Akashic `78608e77a2a8026ad6ec453ac72aa9e365212437` adds
`local_testing/test_rich_terminal_cell_feed.py`. Its four executable cases
exercise all three public feed operations against malformed/overlapping
storage, quarantine precedence, and busy-state rejection, with unchanged
engine/wire state on rejection and preserved caller-stack values. The positive
case negotiates through the real terminal host and commits spans, cells, and
cursor state. All four pass; the commit records 1.27 seconds for that selector.

The measurement recorded clean launch state at:

- Akashic `78608e77a2a8026ad6ec453ac72aa9e365212437`;
- MegaPad `c10058bab26820fc5fb78891106d0ec5316661e3`.

Both measurements use that same current fixture and MegaPad source. The
baseline substitutes only `apt1-engine.f` from Akashic
`2f090eeb3aca70677a7c67729dbdab386c764005`; it is not a run of the entire older
checkout. Engine-source SHA-256 values are:

- baseline: `8e82d0450e0b40c218af52ccab6da0908c5a5d6c2647087f033a58a25b2913ae`;
- corrected: `92d3a59190a907a96cb51320d4e8402f5de8f5e984dc0de7abed5608f7fd663c`.

## Bounded comparison

The executable fixture loads the complete production terminal and engine
sources, performs actual negotiation, publishes its initial CELL snapshot,
and completes retained discovery before measurement. Actual geometry is
280 columns by two rows, inside caller maxima of 280x84: 560 measured cells.
Each row retains its checked-in 3,000,000-step watchdog. Baseline and corrected
fixtures execute sequentially and close independently.

| Measurement | Baseline | Corrected |
| --- | ---: | ---: |
| Timed span/cell feed, seconds | 8.159745327 | 4.753684869 |
| Semantic operations | 4,321,270 | 2,432,950 |
| Operations per cell | 7,716.55 | 4,344.55 |
| Cells per second | 68.63 | 117.80 |
| Complete fixture, seconds | 9.508073538 | 6.226350772 |
| Committed decoded frame bytes | 4,848 | 4,848 |

The measured feed is 1.7165 times as fast, with 41.74% less elapsed time and
43.70% fewer semantic operations. The reduction is 1,888,320 operations,
exactly 3,372 operations per cell for this fixture.

Both runs commit revision 2 with the same 560 cells, expected foreground,
background, attributes, and cursor at row 1/column 279. The serialized cell
tuple hash is identical:
`fca1c2f79d20b6bf2e227900d156dd3a8d8fd8d771879f2d36b9ea87679ff1ee`.
Equal cell hashes and frame-byte counts are the measured equivalence checks;
this is not a claim of a separately hashed byte-for-byte wire capture.

The timed interval is the sum of the two `CF-ROW-WRITE` calls, including
span creation, cell writes, and their ordinary semantic-backend return work.
Source compilation, initial negotiation/snapshot, retained discovery, final
cursor/commit, and host processing of the completed update are outside that
interval. Complete-fixture times include setup and teardown and must not be
substituted for the feed measurement. No physical viewer runs in this fixture.

## Evidence and remaining boundary

Raw records are under `local_testing/out/close-20260908-cell-feed/`:

| File | SHA-256 |
| --- | --- |
| `comparison.json` | `3bbe3b4ef353a882b61e9360882b59af5675d243903049eeb3974bfdb08c15c6` |
| `revisions.json` | `eadcef030141cad2f7f963c6cb0053dd00e14e15dcff3b25f481b84582bc81ce` |

This measurement supports the specific duplicate-check correction identified
at the stopped r3 checkpoint. It does not extrapolate a complete 280x84 frame,
retained publication, the whole Desktop journey, or any emulator/simulator
speed ratio. Ordinary simulator r4 acceptance uses the unchanged physical
profile and 900-second watchdog as separate evidence; the separate
`rich-desktop-speed-decision-20260908.md` ledger records its initial-frame ACK
and timeout. Full simulator interaction acceptance and merge qualification
remain open.
