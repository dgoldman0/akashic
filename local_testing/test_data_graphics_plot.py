"""Canonical PLOT and POLYLINE records: model proofs and every painted cell.

The model tests build, measure and deeply validate the two records and
refuse malformed ones.  The cell tests compare the ordinary CELL painter
with an oracle of its visible contract: a plot's line through every sample,
its shade beneath and its points, and a line's segments in line characters.
"""

import re

import pytest

from test_data_graphics_series import PRELUDE, run_series, series_runtime

MASK64 = (1 << 64) - 1
UNORM = 0xFFFFFFFF
ACROSS, DOWN, FALLING, RISING = 9472, 9474, 9586, 9585
POINT, SHADE, BLANK = 9679, 9617, 32


def test_plot_record_builds_validates_and_refuses():
    program = PRELUDE + r'''
: _GP-PLOT ( flags -- status )
    >R 4 1 2 5 30 0 1 2 -100 900 0x5FD7FFFF 0x203040FF R>
    _GS-B UDG-PLOT ;
\ An explicit series of three samples, then a plot of it with points.
0 _GS-D ! 10 _GS-D 8 + ! 1 _GS-D 16 + ! 20 _GS-D 24 + !
2 _GS-D 32 + ! 30 _GS-D 40 + !
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 16 UDG-SERIES-EXPLICIT 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
UDG-PLOT-POINTS _GP-PLOT _GS-OK
_GS-B UDG-END _GS-OK _GS-B UDG-BUILDER-FINISH _GS-OK _GS-U !
_GS-U @ 112 72 + 48 + 136 + = _GS-A
_GS-M _GS-U @ _GS-S UDG-ENTRY-VALIDATE _GS-OK
_GS-M UDG-OBJECT-COUNT@ 1 = _GS-A _GS-M UDG-SERIES-COUNT@ 1 = _GS-A
_GS-M UDG-FIRST-RECORD DUP _GS-R ! UDG-RECORD-NEXT _GS-W !
_GS-W @ UDG-RECORD-KIND@ UDG-K-PLOT = _GS-A
_GS-W @ UDG-PLOT-SERIES-KEY@ 2 = _GS-A
_GS-W @ UDG-PLOT-MINIMUM@ -100 = _GS-A
_GS-W @ UDG-PLOT-MAXIMUM@ 900 = _GS-A
_GS-W @ UDG-PLOT-LINE@ 0x5FD7FFFF = _GS-A
_GS-W @ UDG-PLOT-FILL-COLOR@ 0x203040FF = _GS-A
_GS-W @ UDG-PLOT-FLAGS@ UDG-PLOT-POINTS = _GS-A
\ A changed plot no longer validates.
4 UDG-PLOT-FLAGS-OFFSET _GS-WMUTATE
1 UDG-PLOT-RESERVED-OFFSET _GS-WMUTATE
900 UDG-PLOT-MINIMUM-OFFSET _GS-WMUTATE
0x100000000 UDG-PLOT-LINE-OFFSET _GS-WMUTATE
9 UDG-PLOT-SERIES-KEY-OFFSET _GS-WMUTATE
\ Refused before a record is reserved: a flag beyond fill and points, an
\ empty range, a series the graph lacks, and a key out of order.
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 16 UDG-SERIES-EXPLICIT 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
4 _GP-PLOT UDG-S-INVALID = _GS-A
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 16 UDG-SERIES-EXPLICIT 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
4 1 2 5 30 0 1 2 900 900 0x5FD7FFFF 0 0 _GS-B UDG-PLOT UDG-S-INVALID = _GS-A
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 16 UDG-SERIES-EXPLICIT 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
4 1 2 5 30 0 1 3 -1 1 0x5FD7FFFF 0 0 _GS-B UDG-PLOT UDG-S-INVALID = _GS-A
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 0 2 5 30 0 1 4 -1 1 0x5FD7FFFF 0 0 _GS-B UDG-PLOT UDG-S-INVALID = _GS-A
\ Measuring alone needs no graph and gives the same bytes.
0 0 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 16 UDG-SERIES-EXPLICIT 0 0 _GS-D 3 _GS-B UDG-SERIES _GS-OK
UDG-PLOT-FILL UDG-PLOT-POINTS OR _GP-PLOT _GS-OK
_GS-B UDG-END _GS-OK _GS-B UDG-BUILDER-FINISH _GS-OK 368 = _GS-A
_GS-DONE
'''
    run_series(program, minimum=26)


def test_polyline_record_builds_validates_and_refuses():
    program = PRELUDE + r'''
CREATE _GL-PS 64 7 + ALLOT : _GL-P _GL-PS 7 + -8 AND ;
: _GL-POINTS ( -- )
    0 _GL-P ! 0x7FFFFFFF _GL-P 8 + !
    0xFFFFFFFF _GL-P 16 + ! 0x7FFFFFFF _GL-P 24 + !
    0x7FFFFFFF _GL-P 32 + ! 0 _GL-P 40 + ! ;
: _GL-LINE ( flags a count -- status )
    >R >R >R 2 1 2 3 30 0 1 0x08000000 0xC0C0C0FF R> R> R>
    _GS-B UDG-POLYLINE ;
_GL-POINTS
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
UDG-POLYLINE-CLOSED _GL-P 3 _GL-LINE _GS-OK
_GS-B UDG-END _GS-OK _GS-B UDG-BUILDER-FINISH _GS-OK _GS-U !
_GS-U @ 112 120 + 48 + = _GS-A
3 UDG-POLYLINE-RECORD-BYTES 168 = _GS-A
1 UDG-POLYLINE-RECORD-BYTES 0= _GS-A
_GS-M _GS-U @ _GS-S UDG-ENTRY-VALIDATE _GS-OK
_GS-M UDG-OBJECT-COUNT@ 1 = _GS-A
_GS-M UDG-FIRST-RECORD _GS-W !
_GS-W @ UDG-RECORD-KIND@ UDG-K-POLYLINE = _GS-A
_GS-W @ UDG-POLYLINE-STROKE@ 0x08000000 = _GS-A
_GS-W @ UDG-POLYLINE-COLOR@ 0xC0C0C0FF = _GS-A
_GS-W @ UDG-POLYLINE-FLAGS@ UDG-POLYLINE-CLOSED = _GS-A
_GS-W @ UDG-POLYLINE-POINT-COUNT@ 3 = _GS-A
1 _GS-W @ UDG-POLYLINE-POINT@ 0x7FFFFFFF = SWAP 0xFFFFFFFF = AND _GS-A
\ The record owns its copy of the points.
-1 _GL-P 16 + ! 1 _GS-W @ UDG-POLYLINE-POINT@ DROP 0xFFFFFFFF = _GS-A
_GL-POINTS
\ A changed line no longer validates.
2 UDG-POLYLINE-FLAGS-OFFSET _GS-WMUTATE
0 UDG-POLYLINE-STROKE-OFFSET _GS-WMUTATE
2 UDG-POLYLINE-POINT-COUNT-OFFSET _GS-WMUTATE
1 UDG-POLYLINE-RESERVED-OFFSET _GS-WMUTATE
0x100000000 UDG-POLYLINE-POINTS-OFFSET 8 + _GS-WMUTATE
\ Refused: one point, a coordinate past one, no stroke, an unknown flag,
\ and points that are unaligned or missing.
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
0 _GL-P 1 _GL-LINE UDG-S-INVALID = _GS-A
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
0x100000000 _GL-P 8 + ! 0 _GL-P 3 _GL-LINE UDG-S-INVALID = _GS-A _GL-POINTS
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 1 2 3 30 0 1 0 0xC0C0C0FF 0 _GL-P 3 _GS-B UDG-POLYLINE UDG-S-INVALID = _GS-A
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
2 _GL-P 3 _GL-LINE UDG-S-INVALID = _GS-A
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
0 _GL-P 4 + 3 _GL-LINE UDG-S-INVALID = _GS-A
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
0 0 3 _GL-LINE UDG-S-INVALID = _GS-A
\ Points inside the graph being built are refused.
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 8 40 3 _GS-B UDG-BEGIN _GS-OK
0 _GS-M 128 + 3 _GL-LINE UDG-S-INVALID = _GS-A
_GS-DONE
'''
    run_series(program, minimum=27)


# ---------------------------------------------------------------------
# Painted cells
# ---------------------------------------------------------------------

def _scale(numerator, denominator, span):
    # _DGRAPH-TIME-SCALE: an unsigned projection onto 0 .. span.
    if numerator == 0:
        return 0
    if numerator == denominator:
        return span
    return numerator * span // denominator


def _meter(value, minimum, maximum, span):
    if value <= minimum:
        return 0
    if value >= maximum:
        return span
    return (value - minimum) * span // (maximum - minimum)


def _glyph(dx, dy):
    if abs(dy) * 2 <= abs(dx):
        return ACROSS
    if abs(dx) * 2 <= abs(dy):
        return DOWN
    return FALLING if (dx < 0) == (dy < 0) else RISING


def _walk(c0, r0, c1, r1):
    cells = []
    dc, sc = abs(c1 - c0), (-1 if c1 < c0 else 1)
    dr, sr = -abs(r1 - r0), (-1 if r1 < r0 else 1)
    err = dc + dr
    while True:
        cells.append((r0, c0))
        if c0 == c1 and r0 == r1:
            return cells
        e2 = 2 * err
        if e2 >= dr:
            err += dr
            c0 += sc
        if e2 <= dc:
            err += dc
            r0 += sr


def _truncate(numerator, denominator):
    quotient = abs(numerator) // denominator
    return -quotient if numerator < 0 else quotient


def _grid(screen, region):
    cols, rows = screen
    grid = [[BLANK] * cols for _ in range(rows)]
    region_row, region_col, region_h, region_w = region

    def put(glyph, row, col):
        if 0 <= row < region_h and 0 <= col < region_w:
            grid[region_row + row][region_col + col] = glyph

    return grid, put


def _expected_lines(screen, region, lines):
    grid, put = _grid(screen, region)
    for (top, left, height, width), points, closed in lines:
        pairs = list(zip(points, points[1:]))
        if closed:
            pairs.append((points[-1], points[0]))
        for (x0, y0), (x1, y1) in pairs:
            glyph = _glyph(_truncate(x1 - x0, 65536) * width,
                           _truncate(y1 - y0, 65536) * height)
            c0, r0 = _scale(x0, UNORM, width - 1), _scale(y0, UNORM, height - 1)
            c1, r1 = _scale(x1, UNORM, width - 1), _scale(y1, UNORM, height - 1)
            for row, col in _walk(c0, r0, c1, r1):
                put(glyph, top + row, left + col)
    return grid


def _expected_plot(screen, region, obj, samples, bounds, flags):
    grid, put = _grid(screen, region)
    top, left, height, width = obj
    minimum, maximum = bounds
    span_y, span_x = height - 1, width - 1
    first = samples[0][0]
    duration = (samples[-1][0] - first) & MASK64
    cells = []
    for timestamp, value in samples:
        col = (span_x // 2 if len(samples) == 1
               else _scale((timestamp - first) & MASK64, duration, span_x))
        cells.append((col, span_y - _meter(value, minimum, maximum, span_y)))
    segments = list(zip(cells, cells[1:]))
    if flags & 1:
        tops = {}
        visited = ([(cells[0][1], cells[0][0])] if len(cells) == 1 else
                   [cell for (c0, r0), (c1, r1) in segments for cell in _walk(c0, r0, c1, r1)])
        for row, col in visited:
            tops[col] = min(row, tops.get(col, row))
        for col, row in tops.items():
            for shade_row in range(row + 1, span_y + 1):
                put(SHADE, top + shade_row, left + col)
    for (c0, r0), (c1, r1) in segments:
        glyph = _glyph(c1 - c0, r1 - r0)
        for row, col in _walk(c0, r0, c1, r1):
            put(glyph, top + row, left + col)
    if flags & 2 or len(cells) == 1:
        for col, row in cells:
            put(POINT, top + row, left + col)
    return grid


SETUP = PRELUDE + r'''
VARIABLE _GC-W VARIABLE _GC-R VARIABLE _GC-S
: _GC-DUMP ( -- )
    SCR-H 0 DO SCR-W 0 DO J I SCR-GET CELL-CP@ . LOOP CR LOOP ;
: _GC-PAIR! ( a b index -- ) 16 * _GS-D + DUP >R 8 + ! R> ! ;
'''


def _paint(runtime, screen, region, build, name):
    cols, rows = screen
    region_row, region_col, region_h, region_w = region
    program = f'''
{cols} {rows} SCR-NEW DUP _GC-S ! SCR-USE
{region_row} {region_col} {region_h} {region_w} RGN-NEW DUP _GC-R ! DGRAPH-NEW _GC-W !
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 {region_h} {region_w} 3 _GS-B UDG-BEGIN _GS-OK
{build}
_GS-B UDG-END _GS-OK _GS-B UDG-BUILDER-FINISH _GS-OK _GS-U !
_GS-M _GS-U @ _GS-S UDG-ENTRY-VALIDATE _GS-OK
_GS-M _GS-U @ _GS-S _GC-W @ DGRAPH-BIND _GS-OK
SCR-CLEAR RGN-ROOT 7 0 0 DRW-STYLE! _GC-W @ WDG-DRAW
." CELLS-BEGIN " CR _GC-DUMP ." CELLS-END " CR
_GC-W @ DGRAPH-FREE _GC-R @ RGN-FREE RGN-ROOT _GC-S @ SCR-FREE
'''
    runtime.evaluate(program.encode(), source_name=f"plot-cells-{name}",
                     step_budget=200_000_000)
    output = runtime.drain_uart_output().decode(errors="replace")
    assert "SERIES ASSERT" not in output, output[-4000:]
    body = re.search(r"CELLS-BEGIN\s(.*?)CELLS-END", output, re.S)
    assert body, output[-4000:]
    values = [int(token) for token in body.group(1).split()]
    assert len(values) == cols * rows
    return [values[row * cols:(row + 1) * cols] for row in range(rows)]


@pytest.fixture(scope="module")
def runtime():
    runtime = series_runtime(("tui/widgets/data-graphics.f",))
    runtime.evaluate(SETUP.encode(), source_name="plot-cells-setup", step_budget=4_000_000)
    runtime.drain_uart_output()
    return runtime


LINE_CASES = {
    # name: screen, region, [(object, points, closed)]
    # Sound Lab's frequency strip: an axis across one row, and two marks
    # each one cell wide, drawn above it.
    "axis-and-marks": ((40, 6), (1, 2, 3, 34), [
        ((1, 0, 1, 32), [(0, 0x7FFFFFFF), (UNORM, 0x7FFFFFFF)], False),
        ((1, 6, 1, 1), [(0x7FFFFFFF, 0), (0x7FFFFFFF, UNORM)], False),
        ((1, 20, 1, 1), [(0x7FFFFFFF, 0), (0x7FFFFFFF, UNORM)], False),
    ]),
    "both-diagonals": ((24, 12), (0, 0, 12, 24), [
        ((1, 1, 8, 8), [(0, 0), (UNORM, UNORM)], False),
        ((1, 12, 8, 8), [(0, UNORM), (UNORM, 0)], False),
    ]),
    "shallow-and-steep": ((30, 14), (0, 0, 14, 30), [
        ((1, 1, 4, 24), [(0, 0), (UNORM, UNORM)], False),
        ((5, 2, 8, 3), [(0, 0), (UNORM, UNORM)], False),
    ]),
    "closed-triangle": ((20, 10), (0, 0, 10, 20), [
        ((1, 2, 7, 14), [(0x7FFFFFFF, 0), (UNORM, UNORM), (0, UNORM)], True),
    ]),
    "clipped": ((20, 8), (1, 1, 5, 12), [
        ((-1, -2, 7, 18), [(0, 0x40000000), (UNORM, 0x40000000), (0x80000000, UNORM)], False),
    ]),
}


def _line_build(lines):
    steps, key, offset = [], 2, 0
    for (top, left, height, width), points, closed in lines:
        for index, (x, y) in enumerate(points):
            steps.append(f"{x} {y} {offset + index} _GC-PAIR!")
        flags = "UDG-POLYLINE-CLOSED" if closed else "0"
        steps.append(
            f"{key} {top} {left} {height} {width} {key} 1 0x08000000 0xC0C0C0FF {flags}"
            f" _GS-D {offset * 16} + {len(points)} _GS-B UDG-POLYLINE _GS-OK")
        key += 1
        offset += len(points)
    return "\n".join(steps)


@pytest.mark.parametrize("name", sorted(LINE_CASES))
def test_painted_line_cells_follow_each_segment(runtime, name):
    screen, region, lines = LINE_CASES[name]
    actual = _paint(runtime, screen, region, _line_build(lines), name)
    assert actual == _expected_lines(screen, region, lines)
    assert any(cell != BLANK for row in actual for cell in row)
    assert runtime.main_context.data.snapshot() == ()


def _lcg_samples(count, seed, step, low, high):
    samples, state, timestamp = [], seed, 1000
    for _ in range(count):
        state = (state * 6364136223846793005 + 1442695040888963407) & MASK64
        samples.append((timestamp, low + (state >> 33) % (high - low + 1)))
        timestamp += step + (state >> 60)
    return samples


PLOT_CASES = {
    # name: screen, region, object, samples, bounds, flags
    # Observatory's starting series: eight amounts falling by 500.
    "observatory-demo": ((80, 16), (1, 2, 13, 74), (1, 0, 10, 70),
                         [(i, 8000 - 500 * i) for i in range(8)], (4500, 8000), 2),
    "filled": ((40, 14), (0, 0, 14, 40), (1, 1, 11, 36),
               [(0, 0), (10, 900), (20, 300), (40, 700), (50, 100)], (0, 1000), 1),
    "filled-points-clamped": ((40, 14), (0, 0, 14, 40), (1, 1, 11, 36),
                              [(0, -50), (5, 1200), (9, 500), (30, 499)], (0, 1000), 3),
    "dense": ((50, 14), (0, 0, 14, 50), (1, 1, 12, 46),
              _lcg_samples(600, 99, 7, -5000, 5000), (-5000, 5000), 0),
    "single-sample": ((20, 10), (0, 0, 10, 20), (1, 1, 7, 17), [(5, 50)], (0, 100), 1),
    "clipped": ((30, 10), (1, 1, 6, 20), (-2, -3, 9, 28),
                [(0, 10), (3, 90), (8, 40), (12, 60)], (0, 100), 3),
}


def _plot_build(obj, samples, bounds, flags):
    top, left, height, width = obj
    steps = [f"{timestamp} {value} {index} _GC-PAIR!"
             for index, (timestamp, value) in enumerate(samples)]
    steps.append(f"2 {len(samples)} UDG-SERIES-EXPLICIT 0 0 _GS-D {len(samples)}"
                 " _GS-B UDG-SERIES _GS-OK")
    steps.append(f"3 {top} {left} {height} {width} 0 1 2 {bounds[0]} {bounds[1]}"
                 f" 0x5FD7FFFF 0x203040FF {flags} _GS-B UDG-PLOT _GS-OK")
    return "\n".join(steps)


@pytest.mark.parametrize("name", sorted(PLOT_CASES))
def test_painted_plot_cells_follow_every_sample(runtime, name):
    screen, region, obj, samples, bounds, flags = PLOT_CASES[name]
    actual = _paint(runtime, screen, region, _plot_build(obj, samples, bounds, flags), name)
    assert actual == _expected_plot(screen, region, obj, samples, bounds, flags)
    assert any(cell != BLANK for row in actual for cell in row)
    assert runtime.main_context.data.snapshot() == ()
