# PLOT and POLYLINE publication

Akashic sends a data-graphics graph's `PLOT` and `POLYLINE` records
([data-graphics-plots.md](../tui/data-graphics-plots.md)) to a rich terminal
as two more instrument kinds. A plot belongs to the series family and a line
to the vector family. Neither needs anything of the applet that draws it: the
canonical `DATA_GRAPHICS` widget paints both in CELL, and the same records
reach the terminal through the ordinary instrument planner, engine, provider
and screen producer.

## Neutral instruments

Both keep the 216-byte instrument record.

`RTE-INSTRUMENT-PLOT=5` draws a series as `WAVEFORM` does. `SERIES-ID` names
a series in the same candidate, `MINIMUM` is below `MAXIMUM`, `COLOR-A` is the
line and `COLOR-B` the fill, and `OPTIONS` holds `RTE-PLOT-FILL=1` and
`RTE-PLOT-POINTS=2`. `MODE`, `VALUE`, `SCALE`, the unit and the formatted
text are zero.

`RTE-INSTRUMENT-POLYLINE=6` is straight segments. `VALUE` is the stroke, a
positive UNORM32 fraction of the smaller side of the rectangle; `COLOR-A` is
the color; `OPTIONS` holds `RTE-POLYLINE-CLOSED=1`. `UNIT-A` and `UNIT-U`
hold the points where a `READOUT` holds its unit: at least two pairs of
native cells, x then y, each a UNORM32 relative to the rectangle. `COLOR-B`,
`MODE`, `MINIMUM`, `MAXIMUM`, `SCALE`, `SERIES-ID` and the formatted text are
zero. MegaPad addresses bytes, so the points need no alignment.

Because the points sit where a unit sits, the checked summary's
`INSTRUMENT-UNIT-BYTES` and `-UNIT-ALIGNED` count them, sixteen bytes a
point, and every bank that holds units holds them too. `INSTRUMENT-UNIT-MAX`
stays the longest unit text.

The hybrid admission summary is 504 bytes. It adds `PLOT-COUNT` at 472,
`POLYLINE-COUNT` at 480, `PATH-POINTS` at 488 (the points of every line, the
owner's path-point need) and `PATH-POINTS-MAX` at 496 (the most in one line).
The family admission summary is 600 bytes, with the same four at 568 to 592.
A family batch needs `RTE-F-VECTOR` for any line and `RTE-F-INSTRUMENT` for
any other instrument.

## APT-1 provider

- **Families.** A line needs `VECTOR` and no more points than
  `max_path_points`. Any other instrument needs `INSTRUMENT`, and a plot
  `SERIES` too.
- **Frames.** A `PLOT` frame is 144 bytes, a 104-byte payload. A `POLYLINE`
  frame is 120 bytes and eight more a point, its points going out as `u32`
  pairs.
- **Series.** Like a waveform, a plot binds only a series defined earlier in
  the same complete `REPLACE_START` candidate.
- **Points.** A new line's points join those of the scene target it builds,
  and the target's points stay within the owner's `path_point_quota`, as
  sample slots stay within theirs. The provider counts each target's points,
  not each line's, so it never replaces a line in a `DELTA`; a changed line
  goes out with its whole scene. The publication audit recounts every line.
- **Admission.** Hybrid and family preflight check the counts against each
  other, add plots and lines to the transaction's bytes, and carry the
  points in the owner's need (`RTE-ADMISSION-NEEDS@`, slot 7). An owner asks
  for those points when it opens or grows, and the terminal's
  `total_path_points` bounds every owner's share.

## Planner and producer

The instrument planner lowers both records, copying a line's points to the
unit bank and translating a plot's series reference through the graph's
series correlations. A graph goes to CELL whole when its terminal lacks one
of its records' families, a line has more points than the terminal allows,
or a frame does not fit ([uidl-instrument-planner.md](../tui/uidl-instrument-planner.md)).

The hybrid screen producer recounts plots, lines and points when it builds
and when it emits, and checks them against the admission. Its quota request
asks for the points it needs, never a guessed maximum. A `DELTA` keeps an
unchanged plot or line: the instrument lane is reused when every field and
unit byte matches, a plot's series reference judged as a waveform's.

## Desktop profile

The Desktop terminal advertises `VECTOR`. Each point takes sixteen bytes of
the data-graphics bank Desk selects, so that bank bounds both one line and
all lines: `max_path_points` and `total_path_points` are both its bytes over
sixteen, 57,344 for the 917,504-byte bank.
