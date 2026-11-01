"""The candidate taken from the bank on screen carries its instruments.

FRAMES-FOLLOW-CHANGE 9c.4.  When no data-graphics root moved, the candidate
taken from the bank on screen takes that bank's instrument regions,
instruments with their correlations and units, and series with theirs,
numbered as a full lowering numbers them: the instrument regions from the
one past the candidate's region, the instruments from the first identity
past the controls Desk's shell adds, and the series from the candidate's
first series.  A bank whose frame left out a graph the terminal could not
take is not taken, since the bank does not keep the graphs left out.

These tests run the production words over test_rich_instrument_reuse's
instruments, packed into a bank as a frame on screen keeps them and
unpacked into a later candidate.  The series, and the whole path against a
full lowering, are compared by the shadow check's unpack stage in the
physical journeys.
"""

from __future__ import annotations

import struct

import pytest

from test_rich_instrument_reuse import InstrumentHarness

INSTRUMENT = 216
CORRELATION = 80
REGION = 96


class UnpackHarness(InstrumentHarness):
    def __init__(self, backend):
        super().__init__(backend, ("_RTHP-UB-INSTRUMENTS?", "_RTHP-UB-BANK?",
                                   "_RTHP-TG-HEADER!"))

    def on_screen(self, *, kinds=(1, 2, 3), units=b"Hz\xc2\xb0C", series_first=1):
        """The instruments of a candidate of region 7 and first object 100,
        packed into the bank on screen, whose series begin at SERIES-FIRST;
        the producer then holds a later candidate's region, first object and
        first series, and nothing in its instrument banks."""
        self.setup(kinds=kinds, units=units)
        assert self.call("_RTHP-PACK-ADMITTED-CANDIDATE", self.bank, self.producer)
        # The series an instrument binds begin there on screen.
        self.field(self.bank, "_RTHP-TB.FIRST-SERIES", series_first)
        memory = self.runtime.memory
        self.before = {
            "regions": memory.read_bytes(self.packed("INSTRUMENT-REGIONS"), REGION),
            "items": memory.read_bytes(self.packed("INSTRUMENTS"), self.count * INSTRUMENT),
            "corr": memory.read_bytes(self.packed("INSTRUMENT-CORR"), self.count * CORRELATION),
        }
        for name, value in (("REGION", 17), ("FIRST-OBJECT", 300), ("CONTROL-COUNT", 0),
                            ("SHELL-CONTROLS", 0), ("FIRST-SERIES", 9)):
            self.field(self.producer, "_RTHP." + name, value)
        if self.count:
            for name, data in (("INSTRUMENT-REGIONS", REGION),
                               ("INSTRUMENTS", self.count * INSTRUMENT),
                               ("INSTRUMENT-CORR", self.count * CORRELATION),
                               ("INSTRUMENT-UNITS", len(self.units))):
                memory.write_bytes(getattr(self, name.lower().replace("-", "_")), b"\xa5" * data)
        for name in ("INSTRUMENT-COUNT", "INSTRUMENT-REGION-COUNT", "INSTRUMENT-UNITS-USED"):
            self.field(self.producer, "_RTHP." + name, 0)
        self.variable("_RTHP-UB-P", self.producer)
        self.variable("_RTHP-UB-A", self.bank)
        self.variable("_RTHP-W-P", self.producer)

    def get(self, suffix):
        return self.runtime.memory.read64(self.producer + self.offset("_RTHP." + suffix))


@pytest.fixture(params=("python", "native"))
def h(request):
    return UnpackHarness(request.param)


def test_instruments_are_numbered_as_a_full_lowering_numbers_them(h):
    h.on_screen()
    assert h.call("_RTHP-UB-INSTRUMENTS?")
    memory = h.runtime.memory
    # The region past the candidate's, and the instruments from its first
    # object past no controls.
    region = memory.read_bytes(h.instrument_regions, REGION)
    assert struct.unpack_from("<Q", region)[0] == 18
    assert region[8:] == h.before["regions"][8:]
    for i in range(h.count):
        item = memory.read_bytes(h.instruments + i * INSTRUMENT, INSTRUMENT)
        old = h.before["items"][i * INSTRUMENT:(i + 1) * INSTRUMENT]
        assert struct.unpack_from("<Q", item, 16)[0] == 300 + i
        assert struct.unpack_from("<Q", item, 48)[0] == 18
        # A unit's text lies in the candidate's own copy.
        unit_a, unit_u = struct.unpack_from("<2Q", item, 176)
        if unit_u:
            assert unit_a == h.instrument_units
        for start, end in ((0, 16), (24, 48), (56, 176), (184, INSTRUMENT)):
            assert item[start:end] == old[start:end]
        corr = memory.read_bytes(h.instrument_corr + i * CORRELATION, CORRELATION)
        assert struct.unpack_from("<2Q", corr, 56) == (18, 300 + i)
        old_corr = h.before["corr"][i * CORRELATION:(i + 1) * CORRELATION]
        assert corr[:56] == old_corr[:56] and corr[72:] == old_corr[72:]
    assert memory.read_bytes(h.instrument_units, len(h.units)) == h.units
    assert (h.get("INSTRUMENT-COUNT"), h.get("INSTRUMENT-REGION-COUNT"),
            h.get("INSTRUMENT-UNITS-USED"), h.get("INSTRUMENT-LAST"),
            h.get("INSTRUMENT-LAST-REGION")) == (h.count, 1, len(h.units), 300 + h.count - 1, 18)
    # The runs and status fields begin past the instruments.
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 300 + h.count
    plan = h.producer + h.offset("_RTHP.INSTRUMENT-PLAN")
    assert memory.read64(plan + h.offset("_RTE-IP.ITEMS-U")) == h.count * INSTRUMENT
    h.guards()


def test_an_instrument_bound_to_a_series_follows_the_series_numbering(h):
    h.on_screen(series_first=5)
    h.runtime.memory.write64(h.packed("INSTRUMENTS") + 208, 5)
    assert h.call("_RTHP-UB-INSTRUMENTS?")
    assert h.runtime.memory.read64(h.instruments + 208) == 9
    # The others name no series.
    assert h.runtime.memory.read64(h.instruments + INSTRUMENT + 208) == 0


@pytest.mark.parametrize("where", ("instrument", "region"))
def test_a_bank_numbered_otherwise_is_not_taken(h, where):
    h.on_screen()
    if where == "instrument":
        h.runtime.memory.write64(h.packed("INSTRUMENTS") + INSTRUMENT + 16, 105)
    else:
        h.runtime.memory.write64(h.packed("INSTRUMENT-REGIONS"), 9)
    assert not h.call("_RTHP-UB-INSTRUMENTS?")


def test_a_bank_without_instruments_strips_them_from_the_candidate(h):
    h.on_screen(kinds=(), units=b"")
    assert h.call("_RTHP-UB-INSTRUMENTS?")
    assert (h.get("INSTRUMENT-COUNT"), h.get("INSTRUMENT-REGION-COUNT")) == (0, 0)
    assert h.variable("_RTHP-W-GLYPH-FIRST") == 300


@pytest.mark.parametrize("left_out", (0, 40))
def test_a_bank_whose_frame_left_out_a_graph_is_not_taken(h, left_out):
    """The bank records the graphs its candidate left out, and the
    candidate is not taken from a bank that left any out."""
    h.setup()
    h.field(h.producer, "_RTHP.OMITTED-GRAPHS-USED", left_out)
    h.variable("_RTHP-TG-P", h.producer)
    h.variable("_RTHP-TG-BANK", h.bank)
    h.results("_RTHP-TG-HEADER!")
    assert h.runtime.memory.read64(h.bank + h.offset("_RTHP-TB.OMITTED-GRAPHS")) == left_out
    assert ("    9 _RTHP-UB-WHY !\n"
            "    _RTHP-UB-A @ _RTHP-TB.OMITTED-GRAPHS @ IF 0 EXIT THEN\n"
            in h.definitions["_RTHP-UB-BANK?"])
