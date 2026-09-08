# Rich Desktop simulator checkpoint — 2026-09-08

Status: stopped diagnostic checkpoint, not rich Desktop acceptance. The
simulator loads the ordinary source, negotiates APT-1, and displays complete
CELL fallback. It has not produced its first complete retained offer or
reached the previously failing Daybook interaction. Neither simulator rich
completion nor readiness to merge the current work into main is established.

## Revisions, earlier attempts, and scope

Attempt `close-20260908-simulator-r3` recorded clean launch state at:

- Akashic `75952bd21ed70b85d2a8b324e0cdcf713eb9a594`;
- MegaPad `da5dd03207f26588ee0f5770c6a7fbb42e7bdace`.

It used the unchanged `desktop-apt1` profile with `--backend simulator`,
checked cold stored source, 320 MiB external memory, canonical 280x84 geometry,
18-pixel X11 pygame viewer, realtime RTC, 900-second watchdog, 0.75-second
action delay, and ten-second post-pass hold. Phase profiling was off. The
8192-step semantic host quantum permits synchronous primitive/accelerator
overshoot; it does not alter guest IDL or impose a hard wall-time deadline.

Four committed MegaPad repairs precede this checkpoint:

- `65cf61d` lets ordinary polling yield resumably to host terminal service,
  preserving interrupt-bound IDL and cumulative watchdog accounting. Attempt
  r1 reached initial status at 2.030935066 seconds, then timed out at
  17.773449375 seconds because synchronous source loading held the live owner.
- `27858f8` completes ordinary autoexec preparation before exposing the socket,
  then invokes the same deferred Desktop entry in the live session.
- `90eaad6` advances the existing live RTC from elapsed host time, preserving
  deterministic standalone runtimes and ordinary source deadlines.
- `da5dd03` preserves ordinary top-level data-stack effects across preparation.
  Attempt r2 had rejected the completed source closure as leaving dirty stacks;
  its server exited before a client connected. The fix retains return-stack
  validation without imposing an additional empty-data-stack ABI.

The source header loader's payload-length stack leak is a separate deferred
defect. Preserving those existing effects does not repair the leak, but it
also does not explain the current measured per-cell publication cost.

## Observed state and why the wait stopped

R3 connected at 80.719800499 trace seconds and returned initial status at
80.919163272 seconds. Source preparation completed, but that result did not
establish fast live execution. At the user's request to stop the prolonged
black-screen wait, the machine was paused around 371 seconds overall for
bounded inspection instead of continuing to the full watchdog.

The paused status recorded 148,061,362 semantic steps in 18,073 boundaries,
generation 1, CELL revision 4, terminal state ACTIVE, and no machine or
terminal failure. The CELL snapshot and an independent capture of the actual
viewer window both show the ordinary tiled Desk, Pad, File Explorer, Daybook,
Grid, and Agent. The window's diagnostic strip says CELL fallback, stage 0,
waiting for a retained frame. These captures establish visible fallback at
the inspection point; they do not establish a retained presentation ACK.

Publication state places execution in the second CELL-only publication:
`_RTAPT-CB-STATE=0`, mode 2, 84 spans, and 23,520 cells. The sampled cursor was
row 10, cell 106, with write status zero. The wire had one `PRESENT_BEGIN` but
no completed retained offer. No scripted acceptance action was authorized.

Two sequential diagnostic advances, each limited to 250 existing host
boundaries, showed forward progress without incoming events or errors:

| Sample | Cursor before → after | Cells | Semantic steps | Wall seconds |
| --- | --- | ---: | ---: | ---: |
| 1 | row 10/cell 106 → row 11/cell 68 | 242 | 2,048,094 | 3.843965190 |
| 2 | row 11/cell 68 → row 12/cell 30 | 242 | 2,048,107 | 3.803553144 |

The combined local rate is approximately 63.29 cells/second and 8,463 semantic
operations per cell. Extending that
rate to 23,520 cells gives approximately 371.6 seconds for one full CELL pass.
That is an extrapolation from two small windows, not a measured frame time or
a prediction for subsequent retained work. The observation is slow continuing
execution, not a demonstrated deadlock or quadratic growth.

R3 was ultimately terminated with SIGINT. Its trace ends with outcome
`failure` at 883.876338980 seconds and contains zero `offer_observed`,
`offer_acknowledged`, or input events. The elapsed interval includes the long
diagnostic pause and is not suitable for a backend speed comparison.

## Concrete next candidate

At the pinned Akashic revision, `akashic/tui/rich-terminal/apt1-engine.f:7338`
checks `_RTAPT-ENGINE-STORAGE?` in `RTAPT-CELL-WRITE`; line 7342 then calls
`_RTAPT-CELL-FEED-READY?`, whose first operation at line 7287 repeats that
same storage check. The storage predicate at line 1907 calls the fixed range
validator at line 789. Each range validation includes five four-span session
disjointness checks and ten engine-range overlap checks: 30 fixed overlap
checks per validation, repeated twice for each cell before the PT writer.

The narrow candidate is to remove only the redundant inner storage validation
after confirming all three helper callers retain their own outer check.
Preserve invalid-storage rejection, quarantined-state handling, status order,
and every remaining feed-state/shape check. Validate that change with focused
checks, then repeat one bounded cell-rate measurement before deciding whether
another full Desktop attempt is justified. No new semantic family, applet
adapter, alternate renderer, or speculative scaling model is required.

For reference, the [separately passing emulator r1](rich-desktop-emulator-reacceptance-20260908.md) acknowledged its complete
Desk at 486.098092178 seconds, the Daybook task at 578.061029954 seconds, and
the final existing journey at 682.191468000 seconds. R3 reached none of those
retained checkpoints. Simulator semantic steps and retired emulator
instructions are different units and must not be compared as equivalent work.

## Artifact binding

The ignored run directory is
`local_testing/out/close-20260908-simulator-r3/`; its `diagnostics/` preserves
the paused snapshots, source/publication probes, bounded samples, and both
images, with a `sha256.json` inventory. The PNG hashes bind encoded files;
these are diagnostic captures, not acceptance-manifest raster hashes.

| Artifact | SHA-256 |
| --- | --- |
| `performance-trace.json` | `372c405ca26499cc86c1ff1ff532d88d8edf99994b6c501ce2ae6d3dc30fd87e` |
| `diagnostics/paused-status.json` | `2d5a0c995c53d4c0580de9cbd8f6cdbc3052ddda2a42c71d7927805fc5a05be1` |
| `diagnostics/publication.json` | `3be4b28595a4a854785a9f4a31d1a3c94389465d92b9594b11748019f9361088` |
| `diagnostics/phase.json` | `04c9b542596dcb0190b76ce4a485fed00fbe9803b2e67621b4a5a274a36daa05` |
| `diagnostics/cell-step-sample.json` | `65294a1e3cb788138753403d5581467cddcb9bd135abe150ddf1baafe8987bde` |
| `diagnostics/cell.json` | `566dc80ed35998a009cfe39e3d4bb05f8cc123e531b5fc67c04d0f7564798639` |
| `diagnostics/cell.png` | `da9f24358ec7248380c8b4101ea846d1e505d26a6df4b1982c8a2e3fff4026db` |
| `diagnostics/window.png` | `bd2dc052a35c2ccafb9bcb8e655a8f88b3f46d1fd5ed0585dc0885e119a7803a` |
