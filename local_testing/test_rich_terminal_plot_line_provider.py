"""PLOT and POLYLINE through the real provider, real PT and the real host scene.

The neutral engine, the APT-1 provider and PT run unchanged; only caller-owned
capacities and the terminal's negotiated limits are chosen here.
"""

import struct

import pytest

from test_rich_terminal_series_engine import FEATURES, MASK, SeriesProvider
from test_rich_terminal_status_provider import RetainedFeature
from rich_terminal.retained_scene import Point, PlotBody, PolylineBody, RGBA


ONE = 0xFFFFFFFF
VECTOR = FEATURES | RetainedFeature.VECTOR
# The terminal draws lines of up to four points and grants six in all; the
# owner asks for all six.
MAX_POINTS = 4
TOTAL_POINTS = 6
STROKE = 0x20000000
TRIANGLE = ((0, 0), (ONE // 2, ONE), (ONE, 0))


class PlotLineProvider(SeriesProvider):
    def __init__(self, backend, *, features=VECTOR):
        vector = bool(features & RetainedFeature.VECTOR)
        super().__init__(
            backend, features=features,
            path_points=TOTAL_POINTS if vector else 0,
            max_path_points=MAX_POINTS if vector else 0,
            total_path_points=TOTAL_POINTS if vector else 0,
        )

    def status(self, name):
        return self.constant(f"RTAPT-S-{name}")

    def plot(self, *, series=1, identity=1, flags=3, minimum=-10, maximum=10):
        fields = (1, 1, identity, 5, MASK, 0, 1, 0, 0, 0, 2, 20, 2, 20,
                  0x5FD7FFFF, 0x20406080, 0, flags, minimum, maximum,
                  0, 0, 0, 0, 0, 0, series)
        return self.allocate(struct.pack("<27Q", *(value & MASK for value in fields)))

    def polyline(self, points, *, identity=1, closed=False, stroke=STROKE):
        payload = b"".join(struct.pack("<QQ", x & MASK, y & MASK) for x, y in points)
        unit = self.allocate(payload) if payload else 0
        fields = (1, 1, identity, 6, MASK, 0, 1, 0, 0, 0, 2, 20, 2, 20,
                  0x808080FF, 0, 0, int(closed), 0, 0, stroke, 0, unit,
                  len(payload), 0, 0, 0)
        record = self.allocate(struct.pack("<27Q", *(value & MASK for value in fields)))
        return record, unit

    def define_object(self, record, *, neutral=False):
        return self.define_waveform(record, neutral=neutral)


@pytest.fixture(params=("python", "native"))
def provider(request):
    harness = PlotLineProvider(request.param)
    try:
        yield harness
    finally:
        harness.close()


def test_plot_draws_its_series_from_an_owned_copy(provider):
    h = provider
    h.begin()
    values = (-10, -3, 0, 4, 9, 10)
    record, source = h.series(values, capacity=8)
    assert h.define(record, neutral=True) == (0,)
    plot = h.plot()
    assert h.define_object(plot, neutral=True) == (0,)
    # The region, the series' definition and three chunks, then the plot.
    assert h.field("_RTAPT-E.OP-COUNT") == 6
    assert h.field("_RTAPT-E.COPY-USED") == 104 + 48 * 4 + 8 * 6 + 216
    assert h.field("_RTAPT-E.RET-BYTES") == 104 + 80 * 4 + 8 * 6 + 144
    h.runtime.memory.write_bytes(source, b"X" * 48)
    h.runtime.memory.write_bytes(plot, bytes(216))
    h.publish()
    owner = h.installed()
    assert owner.objects[1].body == PlotBody(
        series_id=1, minimum=-10, maximum=10,
        line=RGBA(0x5F, 0xD7, 0xFF, 0xFF), fill=RGBA(0x20, 0x40, 0x60, 0x80),
        fill_to_minimum=True, draw_points=True,
    )
    assert tuple(value for _, value in h.samples()) == values


def test_polyline_points_go_out_as_pairs_within_the_owner_quota(provider):
    h = provider
    h.begin()
    record, points = h.polyline(TRIANGLE, closed=True)
    assert h.define_object(record, neutral=True) == (0,)
    assert h.field("_RTAPT-E.COPY-USED") == 104 + 216 + 16 * 3
    assert h.field("_RTAPT-E.RET-BYTES") == 104 + 120 + 8 * 3
    assert h.owner_field("_RTAPT-O.PENDING-PATH-POINTS") == 3
    # Capture owns the points: the caller may reuse its record and buffer.
    h.runtime.memory.write_bytes(points, b"\xff" * 48)
    h.runtime.memory.write_bytes(record, bytes(216))
    h.publish()
    owner = h.installed()
    assert owner.objects[1].body == PolylineBody(
        points=tuple(Point(x, y) for x, y in TRIANGLE), stroke_width=STROKE,
        color=RGBA(0x80, 0x80, 0x80, 0xFF), closed=True,
    )
    assert owner.usage.path_points == 3
    assert h.owner_field("_RTAPT-O.ACTIVE-PATH-POINTS") == 3
    assert h.owner_field("_RTAPT-O.PENDING-PATH-POINTS") == 0


@pytest.mark.parametrize("change,status", (
    (dict(points=((0, 0), (1, 1), (2, 2), (3, 3), (4, 4))), "CAPACITY"),
    (dict(points=((0, 0),)), "INVALID"),
    (dict(points=((0, 0), (ONE + 1, 0))), "INVALID"),
    (dict(stroke=0), "INVALID"),
    (dict(stroke=ONE + 1), "INVALID"),
))
def test_a_line_outside_its_limits_is_refused_atomically(provider, change, status):
    h = provider
    h.begin()
    before = h.snapshot()
    record, _ = h.polyline(change.get("points", TRIANGLE),
                           stroke=change.get("stroke", STROKE))
    assert h.define_object(record) == (h.status(status),)
    assert h.snapshot() == before
    assert h.owner_field("_RTAPT-O.PENDING-PATH-POINTS") == 0


def test_lines_share_the_owner_quota_across_one_target(provider):
    h = provider
    h.begin()
    first, _ = h.polyline(((0, 0), (1, 1), (2, 2), (3, 3)))
    assert h.define_object(first) == (0,)
    before = h.snapshot()
    second, _ = h.polyline(((0, 0), (1, 1), (2, 2)), identity=2)
    assert h.define_object(second) == (h.status("CAPACITY"),)
    assert h.snapshot() == before
    third, _ = h.polyline(((0, 0), (ONE, ONE)), identity=2)
    assert h.define_object(third) == (0,)
    assert h.owner_field("_RTAPT-O.PENDING-PATH-POINTS") == 6
    h.publish()
    assert h.installed().usage.path_points == 6


def test_a_line_is_never_replaced_in_a_delta(provider):
    h = provider
    h.begin()
    record, _ = h.polyline(TRIANGLE)
    assert h.define_object(record) == (0,)
    h.publish()
    h.begin("PT-RET-DELTA")
    moved, _ = h.polyline(((0, ONE), (ONE, 0)))
    before = h.snapshot()
    assert h.define_object(moved) == (h.status("UNSUPPORTED"),)
    assert h.snapshot() == before


def test_a_plot_binds_only_a_series_of_its_own_candidate(provider):
    h = provider
    h.begin()
    before = h.snapshot()
    assert h.define_object(h.plot(series=9)) == (h.status("INVALID"),)
    assert h.snapshot() == before
    record, _ = h.series((1, 2), capacity=2)
    assert h.define(record) == (0,)
    assert h.define_object(h.plot(flags=4)) == (h.status("INVALID"),)
    assert h.define_object(h.plot(minimum=5, maximum=5)) == (h.status("INVALID"),)
    assert h.define_object(h.plot()) == (0,)


@pytest.mark.parametrize("backend", ("python", "native"))
def test_without_vector_a_line_is_unsupported(backend):
    h = PlotLineProvider(backend, features=FEATURES)
    try:
        h.begin()
        before = h.snapshot()
        record, _ = h.polyline(TRIANGLE)
        assert h.define_object(record) == (h.status("UNSUPPORTED"),)
        assert h.snapshot() == before
    finally:
        h.close()
