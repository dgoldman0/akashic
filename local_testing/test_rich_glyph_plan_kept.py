"""A glyph plan the producer holds is kept only for exactly its inputs.

The residual planner reads the draw's planes, the claims, how many of them
are menus, the first object ID, the run text limit and the surface.  The
producer keeps a plan it holds, instead of planning the draw again, only
when every one of these is what the plan was made from.  These execute the
production words that record and compare them.
"""

import struct

import pytest

from test_rich_menu_projection_damage import DamageHarness, MASK64


@pytest.fixture(params=("python", "native"))
def harness(request):
    return DamageHarness(request.param,
                         extra_words=("_RTHP-GLYPHS-HELD?", "_RTHP-GLYPHS-KEEP"))


def _claims(rects):
    return b"".join(struct.pack("<10Q", 1, 1, 1, i, 0, 0, *rect)
                    for i, rect in enumerate(rects))


def _planned(h, *, claims=((0, 0, 1, 4), (2, 3, 4, 9)), menus=1, capacity=None):
    """A producer whose banks hold a plan of draw 7, just recorded."""
    data = _claims(claims)
    capacity = len(data) if capacity is None else capacity
    producer = h.allocate(bytes(h.constant("RTHP-SIZE")))
    claims_a = h.allocate(data + bytes(max(capacity - len(data), 0)))
    copy_a = h.allocate(bytes(max(capacity, 8)))
    limits = producer + h.offset("_RTHP.LIMITS")
    for name, value in (("_RTHP.CLAIMS-A", claims_a), ("_RTHP.CLAIMS-U", max(capacity, len(data))),
                        ("_RTHP.CLAIMS-USED", len(data)), ("_RTHP.MENU-CLAIMS", menus),
                        ("_RTHP.GLYPH-CLAIMS-A", copy_a), ("_RTHP.GLYPH-CLAIMS-U", capacity),
                        ("_RTHP.COLS", 12), ("_RTHP.ROWS", 5),
                        ("_RTHP.GLYPH-COUNT", 9), ("_RTHP.GLYPH-TEXT-USED", 41)):
        h.field(producer, name, value)
    h.field(limits, "_RTE-L.GLYPH-RUN-BYTES", 256)
    h.variable("_RTHP-W-DRAW", 7)
    h.variable("_RTHP-W-GLYPH-FIRST", 300)
    h.results("_RTHP-GLYPHS-KEEP", producer)
    return producer, claims_a, limits


def _read(h, base, name):
    return h.runtime.memory.read64(base + h.offset(name))


def test_a_recorded_plan_is_held_for_its_own_inputs(harness):
    h = harness
    producer, _claims_a, _limits = _planned(h)
    assert _read(h, producer, "_RTHP.GLYPH-DRAW") == 7
    assert _read(h, producer, "_RTHP.GLYPH-RUNS") == 9
    assert _read(h, producer, "_RTHP.GLYPH-TEXT") == 41
    assert h.call("_RTHP-GLYPHS-HELD?", producer)


@pytest.mark.parametrize("change", ["draw", "cols", "rows", "limit", "menus", "first",
                                    "claim-count", "claim-rect", "claim-identity"])
def test_any_other_input_plans_again(harness, change):
    h = harness
    producer, claims_a, limits = _planned(h)
    memory = h.runtime.memory
    if change == "draw":
        h.variable("_RTHP-W-DRAW", 8)
    elif change == "cols":
        h.field(producer, "_RTHP.COLS", 13)
    elif change == "rows":
        h.field(producer, "_RTHP.ROWS", 4)
    elif change == "limit":
        h.field(limits, "_RTE-L.GLYPH-RUN-BYTES", 255)
    elif change == "menus":
        h.field(producer, "_RTHP.MENU-CLAIMS", 0)
    elif change == "first":
        h.variable("_RTHP-W-GLYPH-FIRST", 301)
    elif change == "claim-count":
        h.field(producer, "_RTHP.CLAIMS-USED", 80)
    elif change == "claim-rect":
        memory.write64(claims_a + 80 + 72, 10)
    elif change == "claim-identity":
        memory.write64(claims_a + 8, 2)
    assert not h.call("_RTHP-GLYPHS-HELD?", producer)


def test_no_plan_is_held_before_one_is_recorded(harness):
    h = harness
    producer = h.allocate(bytes(h.constant("RTHP-SIZE")))
    h.variable("_RTHP-W-DRAW", 7)
    assert not h.call("_RTHP-GLYPHS-HELD?", producer)


def test_claims_the_copy_cannot_hold_are_never_held(harness):
    h = harness
    producer, _claims_a, _limits = _planned(h, capacity=80)
    assert _read(h, producer, "_RTHP.GLYPH-CLAIMS-USED") == MASK64
    assert not h.call("_RTHP-GLYPHS-HELD?", producer)
