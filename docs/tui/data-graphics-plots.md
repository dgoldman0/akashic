# Canonical PLOT and POLYLINE

`akashic/tui/data-graphics-model.f` carries two more object records in the
ordinary pointer-free UDG graph: a `PLOT` that draws one of the graph's
series as a line, and a `POLYLINE` of straight segments. The
`DATA_GRAPHICS` widget paints both in CELL and captures them with the rest
of the graph, so a rich terminal can draw the same records. Neither names a
terminal, renderer or application. See
[data-graphics-series.md](data-graphics-series.md) for `SERIES` and
`WAVEFORM`.

## Native records

Both use the ordinary 80-byte object prefix. All fields are native 64-bit
cells; colors are packed `0xRRGGBBAA` sRGB with straight alpha.

`UDG-K-PLOT=6`, `UDG-PLOT-RECORD-SIZE=136`:

| Offset | Field | Contract |
|---:|---|---|
| 80 | Series key | An earlier `SERIES` in the same graph |
| 88 | Minimum | Signed i64, strictly less than maximum |
| 96 | Maximum | Signed i64 |
| 104 | Line color | Packed u32 RGBA |
| 112 | Fill color | Packed u32 RGBA |
| 120 | Flags | Bit 0 `UDG-PLOT-FILL`, bit 1 `UDG-PLOT-POINTS`; others zero |
| 128 | Reserved | Zero |

`UDG-K-POLYLINE=7`, a 120-byte header and its points:

| Offset | Field | Contract |
|---:|---|---|
| 80 | Stroke | Positive UNORM32 fraction of the smaller side of the rectangle |
| 88 | Color | Packed u32 RGBA |
| 96 | Flags | Bit 0 `UDG-POLYLINE-CLOSED`; others zero |
| 104 | Point count | At least 2, at most u32 |
| 112 | Reserved | Zero |
| 120 | Points | Exactly `count` pairs of cells, x then y |

Each coordinate is a UNORM32 relative to the object's rectangle: 0 is the
left or top edge and `UDG-UNORM-ONE` (`0xFFFFFFFF`) the right or bottom.
`UDG-POLYLINE-RECORD-BYTES ( count -- bytes|0 )` is `120 + 16 * count`, or 0
for fewer than two points. A closed line adds the segment from its last
point to its first; it is not filled. These are the same meanings as the
retained profile's `PLOT` and `POLYLINE` bodies, which carry the points as
u32 pairs.

## Builders and accessors

```forth
UDG-PLOT
  ( key row col h w z flags series-key min max line fill plot-flags builder -- status )
UDG-POLYLINE
  ( key row col h w z flags stroke color path-flags points-a count builder -- status )
UDG-POLYLINE-POINT@ ( index validated-polyline -- x y )
```

Builders use the existing statuses and latch failures without changing the
graph. A plot's series must already be in the graph, with a key below the
plot's. A line's points are borrowed: an aligned span of `16 * count` bytes,
disjoint from the destination, the builder and the module, with every
coordinate a UNORM32; a successful build copies all of them, so the caller
may reuse its buffer at once. The `0 0` measure-only builder returns the same
bytes. Every field has a public offset constant and accessor:
`UDG-PLOT-SERIES-KEY@`, `-MINIMUM@`, `-MAXIMUM@`, `-LINE@`, `-FILL-COLOR@`,
`-FLAGS@`, and `UDG-POLYLINE-STROKE@`, `-COLOR@`, `-FLAGS@`,
`-POINT-COUNT@` and `-POINTS@` (the address of the first pair). Deep
validation repeats every check on the immutable record, including each
coordinate and, for a plot, the series reference against the validated
prefix.

## CELL projection

A plot's samples map to cells exactly as a waveform's do: oldest timestamp
at the left edge, newest at the right, linear in unsigned time, a single
sample centred, and values linear through the declared range, clamped to
the rectangle. Then, in this order:

1. With `UDG-PLOT-FILL` and a visible fill color, every cell beneath the
   line's highest cell in each column is shaded (`░`) down to the bottom
   row.
2. With a visible line color, the line is drawn segment by segment between
   consecutive samples.
3. With `UDG-PLOT-POINTS`, or when there is only one sample, each sample's
   cell gets a point (`●`).

A line's point maps to the cell whose centre it names, the rectangle's
first to last cell across and down, as a pixel renderer maps it to a pixel
centre. A segment, in a plot or a line, takes one character for its whole
length, chosen by its direction in the rectangle: `─` when it rises no more
than one cell in two along, `│` when it runs no more than one in two along,
otherwise `╲` or `╱`. Every cell from one end to the other gets it, by the
integer line rule. A line's direction comes from its points rather than its
cells, so a mark inside one cell still draws as the line it is; the stroke
width does not change the CELL drawing. Every sample and point is visited,
with no cell scratch: a plot's cells run left to right, so the shade is
drawn one column at a time. Drawing stays clipped by the widget's region and
the inherited clip, and hidden or disabled graphs behave as for other
objects.

`local_testing/test_data_graphics_plot.py` builds, measures, validates and
refuses both records, and compares every painted cell with an oracle for
axes and marks, both diagonals, shallow and steep segments, a closed
triangle, a clipped line, Observatory's starting series, filled and clamped
plots, a dense plot of 600 samples, a single sample and a clipped plot.
