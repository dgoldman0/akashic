# A refused rich area falls back to CELL — 2026-09-28

Opening a binary file in Pad from File Explorer used to close Desk. Akashic
`e7ba3175` fixed that cause: application text now reaches a renderer as CELL
shows it. Akashic `9a916f1e` removes the wider failure mode. Before it, any
refusal from a semantic capture family in any visible document refused the
whole aggregate snapshot. `INVALID` and `CAPACITY` then closed Desk, and a
lasting `UNAVAILABLE` would have left the flush loop waiting for a rich frame
forever.

Now the refusal stays local:

- In the collection and data-graphics snapshots, a root that its own widget
  cannot publish is left out alone, and CELL draws its area. Its entry bytes
  and work node or descriptor are cleared.
- In the hybrid adapter, a family refusal that remains falls back one
  document the way final-writer occlusion already did: a directory-only
  zero-slice identity, a dirty and unstaged record, and unchanged provenance.
  Every other document keeps its rich content.
- Running out of a caller bank, a caller bank aliasing live widget storage,
  broken UIDL-TUI source state, RUHA's own bank checks, and a family result
  that breaks its contract still refuse the capture or the aggregate.

This is functional regression evidence. It is not a timing comparison with
earlier runs, and not UART, panel, or touch evidence.

## Tests

The refusal paths do not occur in the ordinary Desk journey, so they are
proved below it:

- `test_uidl_collection_snapshot.py::test_a_root_its_widget_cannot_publish_falls_back_alone`
  mounts a text area and a text grid and breaks each in turn: one byte that is
  not UTF-8 in the grid's bound model, and a gutter as wide as the text area.
  The other root stays, no byte of the refused root survives in the native
  bank, the result passes frozen validation, an empty but whole snapshot
  results when both are refused, both return once mended, and a native bank
  one root too small still refuses with `CAPACITY`.
- Structural tests in `test_uidl_collection_snapshot_structure.py`,
  `test_uidl_data_graphics_snapshot.py`, and
  `test_rich_terminal_uidl_hybrid_adapter.py` pin which failures each level
  forgives and which stay fatal.
- The data-graphics snapshot's full source closure compiles with no
  undefined word.

Two failures in `test_uidl_collection_snapshot.py`, the tabset oracle (the
same 13 checks) and the RUHA ABI3 constructor test, fail identically on
`e7ba3175` and are not caused by this change. Akashic `e0c1f862` separately
restores the 34 instrument-reuse harness cases that had errored since the
producer began naming the ITM1 module; all 130 pass.

## Desktop journey

The canonical physical Desktop journey ran once on the committed trees as the
final regression and passed.

| Binding | Value |
| --- | --- |
| Akashic | `e0c1f8622fc0d2a81a0d9d1fcda84373abb6bcaa` (tree `1a9ccbb43b74aab52885b250b3c75478b38edeb5`), clean |
| MegaPad | `465a6ad8ea9f0ebf0580ec6ee98da52cac816ea2` (tree `052ea6d0437cb3f2c29581053cbb2b35791a2968`), clean |
| Native extension SHA-256 | `120704dae29f3a22c29c38153d888b379e42277af566aa11d2f2c2a3ecfd6a4c` |

It used DejaVuSansMono at 18 px, the simulator backend with
`MEGAFORTH_EXECUTOR=native`, 280x84 cells, a 0.75 s action delay, a 10 s
hold, the 900 s watchdog and the 3.5 GiB aggregate-RSS stop, in ordinary
source mode with no compiled Forth cache, step-limit change, or timing change.

| Result | This run | Previous canonical run (`167ba89e`) |
| --- | --- | --- |
| Outcome | pass, exit 0, no stop reason | pass |
| Milestones / inputs | 48 / 51, same sequence | 48 / 51 |
| Peak aggregate RSS | 492,318,720 bytes | 492,568,576 bytes |
| Offers | 69 | 71 |
| Guest steps at the last event | 6,852.5M | 7,496.1M |
| Guest steps at the first offer | 408.9M | 408.8M |
| Wall time to the first offer | 68.9 s | 51.5 s |
| Wall time | 255.4 s | 209.6 s |

The first offer came at the same guest step in both runs but 17.4 s later in
wall time, and this run retired less guest work overall. Its longer wall time
therefore reflects a slower host during the run, not more guest work.
