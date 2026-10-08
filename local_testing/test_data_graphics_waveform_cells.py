"""Every screen cell the ordinary waveform painter produces, against an oracle.

The oracle paints one trace glyph for every sample, which is the painter's
visible contract. The painter may avoid repainting a cell that already holds
the same glyph and style, but the resulting screen must match exactly.
"""

import re

import pytest

from test_data_graphics_series import PRELUDE, series_runtime

MASK64 = (1 << 64) - 1
TRACE, ZERO, BLANK = 8226, 9472, 32
LCG_A, LCG_C = 6364136223846793005, 1442695040888963407

SETUP = PRELUDE + r'''
VARIABLE _GC-W VARIABLE _GC-R VARIABLE _GC-S VARIABLE _GC-X
: _GC-DUMP ( -- )
    SCR-H 0 DO SCR-W 0 DO J I SCR-GET DUP CELL-CP@ . . LOOP CR LOOP ;
: _GC-NEXT ( -- u ) _GC-X @ 6364136223846793005 * 1442695040888963407 +
    DUP _GC-X ! ;
: _GC-SAW ( count step -- )
    SWAP 0 ?DO DUP I * 65535 AND 32768 - _GS-D I 8 * + ! LOOP DROP ;
: _GC-SQUARE ( count half -- )
    SWAP 0 ?DO I OVER / 1 AND IF 32767 ELSE -32768 THEN
        _GS-D I 8 * + ! LOOP DROP ;
: _GC-NOISE ( count seed -- )
    _GC-X ! 0 ?DO _GC-NEXT 48 RSHIFT 32768 - _GS-D I 8 * + ! LOOP ;
: _GC-EXPLICIT ( count seed first -- )
    SWAP _GC-X ! SWAP 0 ?DO
        DUP _GS-D I 16 * + !
        _GC-NEXT 48 RSHIFT 32768 - _GS-D I 16 * + 8 + !
        _GC-NEXT 54 RSHIFT 1+ +
    LOOP DROP ;
'''


def _lcg(state):
    state = (state * LCG_A + LCG_C) & MASK64
    return state, state


def _signed(value):
    value &= MASK64
    return value - (1 << 64) if value >> 63 else value


def _fill(kind, count, argument, first=0):
    """Return (timestamp, value) pairs matching the Forth generators."""
    if kind == "saw":
        return [(first + 125 * i, _signed(((argument * i) & 0xFFFF) - 32768))
                for i in range(count)]
    if kind == "square":
        return [(first + 125 * i, 32767 if (i // argument) & 1 else -32768)
                for i in range(count)]
    samples, state = [], argument
    if kind == "noise":
        for i in range(count):
            state, value = _lcg(state)
            samples.append((first + 125 * i, (value >> 48) - 32768))
        return samples
    assert kind == "explicit"
    timestamp = first
    for _ in range(count):
        state, value = _lcg(state)
        samples.append((timestamp, (value >> 48) - 32768))
        state, step = _lcg(state)
        timestamp += (step >> 54) + 1
    return samples


def _scale(numerator, denominator, span):
    # _DGRAPH-TIME-SCALE: an unsigned projection onto 0 .. span.
    if numerator == 0:
        return 0
    if numerator == denominator:
        return span
    return numerator * span // denominator


def _meter(value, minimum, maximum, span):
    # _DGRAPH-METER-SCALE clamps outside the declared range.
    if value <= minimum:
        return 0
    if value >= maximum:
        return span
    return (value - minimum) * span // (maximum - minimum)


def _expected(screen, region, obj, samples, bounds, zero):
    cols, rows = screen
    region_row, region_col, region_h, region_w = region
    top, left, height, width = obj
    minimum, maximum = bounds
    grid = [[BLANK] * cols for _ in range(rows)]

    def put(glyph, row, col):
        if 0 <= row < region_h and 0 <= col < region_w:
            grid[region_row + row][region_col + col] = glyph

    span_y, span_x = height - 1, width - 1
    if zero is not None:
        row = top + span_y - _meter(zero, minimum, maximum, span_y)
        for col in range(left, left + width):
            put(ZERO, row, col)
    if samples:
        first = samples[0][0]
        duration = (samples[-1][0] - first) & MASK64
        for timestamp, value in samples:
            col = (span_x // 2 if len(samples) == 1
                   else _scale((timestamp - first) & MASK64, duration, span_x))
            put(TRACE, top + span_y - _meter(value, minimum, maximum, span_y), left + col)
    return grid


CASES = {
    # name: screen, region, object, generator, bounds, zero value or None
    "sound-lab-saw": ((96, 30), (2, 3, 16, 90), (1, 2, 12, 86),
                      ("saw", 16000, 97), (-32768, 32767), 0),
    "square": ((96, 30), (2, 3, 16, 90), (1, 2, 12, 86),
               ("square", 16000, 37), (-32768, 32767), 0),
    "clamped-noise": ((96, 30), (2, 3, 16, 90), (0, 0, 13, 90),
                      ("noise", 16000, 12345), (-8000, 8000), None),
    "explicit-irregular": ((60, 20), (1, 1, 12, 50), (1, 3, 9, 40),
                           ("explicit", 5000, 777, 1000), (-32768, 32767), 0),
    "tall-plot": ((30, 80), (1, 2, 76, 24), (2, 1, 70, 20),
                  ("noise", 3000, 99), (-32768, 32767), 0),
    "clipped-edges": ((40, 12), (1, 2, 6, 20), (-2, -3, 9, 26),
                      ("saw", 4000, 311), (-32768, 32767), 0),
    "one-column": ((20, 20), (0, 0, 20, 20), (2, 5, 14, 1),
                   ("noise", 500, 5), (-32768, 32767), 0),
    "one-row": ((20, 20), (0, 0, 20, 20), (3, 2, 1, 15),
               ("noise", 500, 6), (-32768, 32767), 0),
    "single-sample": ((20, 10), (0, 0, 10, 20), (1, 1, 7, 17),
                      ("saw", 1, 3), (-32768, 32767), 0),
}


def _program(screen, region, obj, generator, bounds, zero):
    cols, rows = screen
    kind, count, argument, *first = generator
    first = first[0] if first else 0
    if kind == "explicit":
        fill = f"{count} {argument} {first} _GC-EXPLICIT"
        series = f"2 {count} UDG-SERIES-EXPLICIT 0 0 _GS-D {count} _GS-B UDG-SERIES _GS-OK"
    else:
        fill = f"{count} {argument} _GC-{kind.upper()}"
        series = f"2 {count} UDG-SERIES-UNIFORM 125 {first} _GS-D {count} _GS-B UDG-SERIES _GS-OK"
    region_row, region_col, region_h, region_w = region
    top, left, height, width = obj
    zero_flags = 0 if zero is None else 1
    return f'''
{cols} {rows} SCR-NEW DUP _GC-S ! SCR-USE
{region_row} {region_col} {region_h} {region_w} RGN-NEW DUP _GC-R ! DGRAPH-NEW _GC-W !
{fill}
_GS-M 130176 _GS-B UDG-BUILDER-INIT _GS-OK
1 0 0 {region_h} {region_w} 3 _GS-B UDG-BEGIN _GS-OK
{series}
3 {top} {left} {height} {width} 0 1 2 {bounds[0]} {bounds[1]} 0x00FFFFFF 0x777777FF
    {zero or 0} {zero_flags} _GS-B UDG-WAVEFORM _GS-OK
_GS-B UDG-END _GS-OK _GS-B UDG-BUILDER-FINISH _GS-OK _GS-U !
_GS-M _GS-U @ _GS-S UDG-ENTRY-VALIDATE _GS-OK
_GS-M _GS-U @ _GS-S _GC-W @ DGRAPH-BIND _GS-OK
SCR-CLEAR RGN-ROOT 7 0 0 DRW-STYLE! _GC-W @ WDG-DRAW
." CELLS-BEGIN " CR _GC-DUMP ." CELLS-END " CR
_GC-W @ DGRAPH-FREE _GC-R @ RGN-FREE RGN-ROOT _GC-S @ SCR-FREE
'''


@pytest.fixture(scope="module")
def runtime():
    runtime = series_runtime(("tui/widgets/data-graphics.f",))
    runtime.evaluate(SETUP.encode(), source_name="waveform-cells-setup", step_budget=4_000_000)
    runtime.drain_uart_output()
    return runtime


@pytest.mark.parametrize("name", sorted(CASES))
def test_painted_cells_match_one_trace_glyph_per_sample(runtime, name):
    screen, region, obj, generator, bounds, zero = CASES[name]
    runtime.evaluate(_program(*CASES[name]).encode(), source_name=f"waveform-cells-{name}",
                     step_budget=200_000_000)
    output = runtime.drain_uart_output().decode(errors="replace")
    assert "SERIES ASSERT" not in output, output[-4000:]
    body = re.search(r"CELLS-BEGIN\s(.*?)CELLS-END", output, re.S)
    assert body, output[-4000:]
    values = [int(token) for token in body.group(1).split()]
    cols, rows = screen
    assert len(values) == 2 * cols * rows
    glyphs = [values[index] for index in range(0, len(values), 2)]
    cells = [values[index] for index in range(1, len(values), 2)]
    kind, count, argument, *first = generator
    samples = _fill(kind, count, argument, *first)
    expected = _expected(screen, region, obj, samples, bounds, zero)
    actual = [glyphs[row * cols:(row + 1) * cols] for row in range(rows)]
    assert actual == expected
    assert any(TRACE in row for row in expected)
    for glyph in (TRACE, ZERO):
        styles = {cell for cell, seen in zip(cells, glyphs) if seen == glyph}
        assert len(styles) <= 1, (glyph, styles)
    assert runtime.main_context.data.snapshot() == ()
