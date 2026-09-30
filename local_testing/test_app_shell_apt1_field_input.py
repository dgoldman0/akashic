"""Execute production APTAS control mapping and real PT ADJUST tail readers.

Only the renderer-neutral resolver and screen dimensions are fixture inputs;
the descriptor parsing, action dispatch, revision proof and ordinary mouse
event/sideband writes are production Forth, in both semantic engines.
"""

import re
import struct

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64
from test_rich_terminal_control_map import (
    MEGAPAD_ROOT, MegaForthRuntime, ROOT, _definitions,
)


class FieldInputHarness(GrowthHarness):
    def __init__(self, backend):
        self.runtime = MegaForthRuntime(execution_backend=backend)
        source = "\n".join(path.read_text() for path in (
            ROOT / "akashic/tui/app-shell.f",
            ROOT / "akashic/tui/keys.f",
            MEGAPAD_ROOT / "rich-terminal.f",
            ROOT / "akashic/tui/app-shell-apt1.f",
        ))
        self.definitions = _definitions(source)
        # APTAS embeds the generic shell descriptor; preserve its production
        # arithmetic declarations instead of duplicating those offsets here.
        for match in re.finditer(
            r"(?m)^ASHELL-TERMINAL-DESC-SIZE[^\n]* CONSTANT (\S+)", source,
        ):
            self.definitions[match[1]] = match[0]
        self.definitions.update({
            "SCR-W": "120 CONSTANT SCR-W",
            "SCR-H": "40 CONSTANT SCR-H",
        })
        chunks, seen = [], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            declaration = self.definitions[name]
            for token in re.sub(r"\\[^\n]*|\([^)]*\)", "", declaration).split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(declaration)

        for name in ("APTAS-SIZE", "_APTAS-MAP-CONTROL", "_APTAS-POLL-POINTER"):
            include(name)
        self.runtime.evaluate("\n".join(chunks).encode(), step_budget=3_000_000)
        self.serial = 0
        self.owner = self.allocate(bytes(self.constant("APTAS-SIZE")))
        self.output = self.allocate(b"\xA5" * 24)
        # Resolver context: observed identity/action/context, returned target,
        # and invocation count.  The returned cell is the FIELD value origin.
        self.context = self.allocate(bytes(80))
        self.runtime.evaluate(b"""
            : FIELD-TEST-RESOLVE ( owner generation id kind context -- row col rev has )
                >R R@ 24 + ! R@ 16 + ! R@ 8 + ! R@ !
                R@ R@ 32 + ! 1 R@ 72 + +!
                R@ 40 + @ R@ 48 + @ R@ 56 + @ R> 64 + @ ;
            ' FIELD-TEST-RESOLVE
        """)
        callback = self.runtime.main_context.data.pop()
        self.field(self.owner, "_APTAS.CONTROL-XT", callback)
        self.field(self.owner, "_APTAS.CONTROL-CONTEXT", self.context)
        self.variable("_APTAS-C", self.owner)
        self.variable("_APTAS-EV", self.output)
        self.variable("KEY-MOUSE-FIELD-ADJUSTMENT", 117)
        self.variable("KEY-MOUSE-FIELD-REVISION", 116)
        self.variable("KEY-MOUSE-X", 118)
        self.variable("KEY-MOUSE-Y", 119)
        self.target()

    def target(self, row=7, col=34, revision=19, found=MASK64):
        self.runtime.memory.write_bytes(
            self.context + 40,
            struct.pack("<QQQQ", row & MASK64, col & MASK64, revision, found),
        )

    def event(self, count=1, revision=19, kind=11, tail_length=16, event_type=0x205):
        # PT normalizes the wire header into eight cells and borrows the exact
        # little-endian Qq adjustment tail from its admitted event storage.
        tail = self.allocate(struct.pack("<Qq", revision, count))
        values = (event_type, 0, 41, 43, 47, kind, tail, tail_length)
        self.runtime.memory.write_bytes(
            self.owner + self.offset("_APTAS.EVENT"), struct.pack("<8Q", *values),
        )

    def output_values(self):
        return struct.unpack("<3Q", self.runtime.memory.read_bytes(self.output, 24))

    def assert_unpublished(self):
        assert self.runtime.memory.read_bytes(self.output, 24) == b"\xA5" * 24
        assert self.variable("KEY-MOUSE-FIELD-ADJUSTMENT") == 117
        assert self.variable("KEY-MOUSE-FIELD-REVISION") == 116
        assert self.variable("KEY-MOUSE-X") == 118
        assert self.variable("KEY-MOUSE-Y") == 119


@pytest.fixture(params=["python", "native"])
def field_input(request):
    return FieldInputHarness(request.param)


@pytest.mark.parametrize("count", [1, -1, 32768, -32769, (1 << 63) - 1, -(1 << 63)])
def test_adjust_preserves_complete_signed_count_in_one_ordinary_event(field_input, count):
    h = field_input
    h.event(count=count)
    assert h.call("_APTAS-MAP-CONTROL")
    assert h.output_values() == (h.constant("KEY-T-MOUSE"), 512, (7 << 16) | 34)
    assert h.variable("KEY-MOUSE-FIELD-ADJUSTMENT") == count & MASK64
    assert h.variable("KEY-MOUSE-FIELD-REVISION") == 19
    assert (h.variable("KEY-MOUSE-X"), h.variable("KEY-MOUSE-Y")) == (35, 8)
    assert struct.unpack("<5Q", h.runtime.memory.read_bytes(h.context, 40)) == (
        41, 43, 47, 11, h.context,
    )
    assert h.runtime.memory.read64(h.context + 72) == 1
    # There is no synthetic wheel queue to drain, even for I64_MIN/MAX.
    assert not h.call("_APTAS-POLL-POINTER")
    assert h.variable("KEY-MOUSE-FIELD-ADJUSTMENT") == count & MASK64


@pytest.mark.parametrize("revision,target_revision,count,tail_length,event_type", [
    (0, 0, 1, 16, 0x205),
    (18, 19, 1, 16, 0x205),
    (20, 19, 1, 16, 0x205),
    (19, 19, 0, 16, 0x205),
    (19, 19, 1, 0, 0x205),
    (19, 19, 1, 8, 0x205),
    (19, 19, 1, 15, 0x205),
    (19, 19, 1, 17, 0x205),
    (19, 19, 1, 24, 0x205),
    (19, 19, 1, 16, 0x203),
])
def test_adjust_refuses_stale_zero_or_malformed_tails_without_publishing(
    field_input, revision, target_revision, count, tail_length, event_type,
):
    h = field_input
    h.target(revision=target_revision)
    h.event(count=count, revision=revision, tail_length=tail_length, event_type=event_type)
    assert not h.call("_APTAS-MAP-CONTROL")
    h.assert_unpublished()


@pytest.mark.parametrize("row,col,found", [
    (7, 34, 0), (-1, 34, MASK64), (7, -1, MASK64),
    (40, 34, MASK64), (7, 120, MASK64), (65536, 34, MASK64),
])
def test_adjust_requires_resolver_authority_and_an_in_surface_value_slot(
    field_input, row, col, found,
):
    h = field_input
    h.event()
    h.target(row=row, col=col, found=found)
    assert not h.call("_APTAS-MAP-CONTROL")
    h.assert_unpublished()


def test_adjust_with_no_resolver_is_inert(field_input):
    h = field_input
    h.event()
    h.field(h.owner, "_APTAS.CONTROL-XT", 0)
    assert not h.call("_APTAS-MAP-CONTROL")
    assert h.runtime.memory.read64(h.context + 72) == 0
    h.assert_unpublished()


def test_activate_still_uses_the_resolved_cell_without_an_adjustment_tail(field_input):
    h = field_input
    h.event(kind=1, tail_length=0)
    assert h.call("_APTAS-MAP-CONTROL")
    assert h.output_values() == (h.constant("KEY-T-MOUSE"), h.constant("KEY-MOUSE-LEFT"), (7 << 16) | 34)
    assert h.variable("KEY-MOUSE-FIELD-ADJUSTMENT") == 117
    assert h.variable("KEY-MOUSE-FIELD-REVISION") == 116
    assert h.runtime.memory.read64(h.context + 24) == 1


def test_adjust_does_not_repurpose_pending_pointer_state(field_input):
    h = field_input
    h.event(count=-9)
    for accessor, value in (("_APTAS.PTR-WHEEL-Y", 3),
                            ("_APTAS.PTR-CHANGED", 2), ("_APTAS.PTR-DRAG", 1)):
        h.field(h.owner, accessor, value)
    assert h.call("_APTAS-MAP-CONTROL")
    for accessor, value in (("_APTAS.PTR-WHEEL-Y", 3),
                            ("_APTAS.PTR-CHANGED", 2), ("_APTAS.PTR-DRAG", 1)):
        assert h.runtime.memory.read64(h.owner + h.offset(accessor)) == value
    assert h.variable("KEY-MOUSE-FIELD-ADJUSTMENT") == (-9) & MASK64
    assert h.variable("KEY-MOUSE-FIELD-REVISION") == 19
