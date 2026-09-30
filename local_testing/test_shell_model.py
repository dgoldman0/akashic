"""Execute ordinary shell model, presentation and identity helpers in both engines."""

import re

import pytest

from test_rich_glyph_growth import GrowthHarness, MASK64
from test_rich_terminal_control_map import MegaForthRuntime, ROOT, _definitions
from tests.simulator.test_kdos_exceptions import _load_exceptions


class ShellHarness(GrowthHarness):
    def __init__(self, backend):
        self.runtime = _load_exceptions(MegaForthRuntime(execution_backend=backend))
        sources = [(ROOT / "akashic" / path).read_text() for path in (
            "tui/shell-model.f", "tui/applet-host/host.f", "runtime/instance.f",
        )]
        self.definitions = _definitions("\n".join(sources))
        chunks, seen = [], set()

        def include(name):
            if name in seen:
                return
            seen.add(name)
            source = self.definitions[name]
            for token in re.sub(r"\\[^\n]*|\([^)]*\)", "", source).split():
                if token != name and token in self.definitions:
                    include(token)
            chunks.append(source)

        for name in ("SHM-INIT", "SHM-APPEND", "SHM-COPY$", "SHM-SEAL", "SHM-HIT",
                     "SHME-LABEL$", "SHME-TITLE$", "SHME-ACTION$",
                     "AHOST-PRESENTED?", "AHOST-SHELL-MODEL!", "AHOST-SHELL-MODEL@",
                     "AHOST-SHELL-OBSERVE!", "AHOST-SHELL-DRAW-COMPLETE"):
            include(name)
        self.runtime.evaluate(("CREATE _SHM-OWNED-START\n" + "\n".join(chunks) + "\nHERE _SHM-OWNED-LIMIT !").encode(), step_budget=3_000_000)
        self.serial = 0

    def model(self, count=4, text_bytes=64):
        size = 128 + count * 168 + text_bytes
        bank = self.allocate(b"LEFTGUAR" + bytes(size) + b"RIGHTGUA") + 8
        assert self.call("SHM-INIT", size, count, bank)
        return bank, size


@pytest.fixture(params=["python", "native"])
def shell(request):
    return ShellHarness(request.param)


def test_copy_seal_limits_and_independent_banks(shell):
    left, size = shell.model(1, 7)
    right, _ = shell.model(1, 7)
    label = shell.allocate(b"[x]\xc3\xa9!")
    entry, = shell.results("SHM-APPEND", left)
    assert entry == left + 128
    assert shell.results("SHM-APPEND", left) == (0,)
    offset, ok = shell.results("SHM-COPY$", label, 6, left)
    assert (offset, ok) == (296, MASK64)
    shell.field(entry, "SHME.LABEL-OFF", offset)
    shell.field(entry, "SHME.LABEL-U", 6)
    before = shell.runtime.memory.read_bytes(left, size)
    assert shell.results("SHM-COPY$", label, 2, left) == (0, 0)
    assert shell.runtime.memory.read_bytes(left, size) == before
    assert shell.results("SHME-LABEL$", entry, left) == (left + offset, 6)
    shell.runtime.memory.write_bytes(label, b"mutate")
    assert shell.runtime.memory.read_bytes(left + offset, 6) == b"[x]\xc3\xa9!"
    shell.results("SHM-SEAL", left)
    sealed = shell.runtime.memory.read_bytes(left, size)
    assert shell.results("SHM-COPY$", label, 0, left) == (0, 0)
    assert shell.results("SHM-APPEND", left) == (0,)
    assert shell.call("SHM-INIT", size, 1, right)
    assert shell.runtime.memory.read_bytes(left, size) == sealed
    assert shell.runtime.memory.read_bytes(left - 8, 8) == b"LEFTGUAR"
    assert shell.runtime.memory.read_bytes(left + size, 8) == b"RIGHTGUA"


def test_hit_exact_slots_separators_disabled_and_modal(shell):
    model, _ = shell.model()
    for kind, flags, col, width in ((2, 1, 0, 5), (2, 2, 6, 4), (3, 4, 11, 6), (1, 0, 0, 80)):
        entry, = shell.results("SHM-APPEND", model)
        for name, value in (("KIND", kind), ("FLAGS", flags), ("ROW", 23),
                            ("COL", col), ("HEIGHT", 1), ("WIDTH", width)):
            shell.field(entry, "SHME." + name, value)
    assert shell.results("SHM-HIT", 23, 0, model) == (0,)
    shell.results("SHM-SEAL", model)
    for col in (0, 4):
        assert shell.results("SHM-HIT", 23, col, model) == (model + 128,)
    assert shell.results("SHM-HIT", 23, 6, model) == (model + 296,)
    for row, col in ((23, 5), (23, 10), (23, 12), (22, 0), (23, 80)):
        assert shell.results("SHM-HIT", row, col, model) == (0,)
    for flags in (1, 2, 3):
        shell.field(model, "SHM.FLAGS", flags)
        assert shell.results("SHM-HIT", 23, 0, model) == (0,)


def test_actual_presentation_fullframe_minimized_overlay_and_retirement(shell):
    host = shell.allocate(bytes(136))
    first, second, overlay = [shell.allocate(bytes(112)) for _ in range(3)]
    shell.field(host, "AHOST.FOCUS", first)
    for slot in (first, second, overlay):
        shell.field(slot, "AHS.STATE", 1)
        shell.field(slot, "AHS.RGN", 4096)
    shell.field(overlay, "AHS.OVERLAY", 1)
    assert shell.call("AHOST-PRESENTED?", first, MASK64, host)
    assert not shell.call("AHOST-PRESENTED?", second, MASK64, host)
    assert shell.call("AHOST-PRESENTED?", second, 0, host)
    assert shell.call("AHOST-PRESENTED?", overlay, MASK64, host)
    shell.field(second, "AHS.STATE", 2)
    assert not shell.call("AHOST-PRESENTED?", second, 0, host)
    shell.field(overlay, "AHS.CLOSE-PHASE", 1)
    assert not shell.call("AHOST-PRESENTED?", overlay, MASK64, host)
    shell.field(first, "AHS.RGN", 0)
    assert not shell.call("AHOST-PRESENTED?", first, 0, host)


def test_host_observation_borrows_completed_model_and_detaches(shell):
    host = shell.allocate(bytes(136))
    model, _ = shell.model()
    context = shell.allocate(bytes(24))
    shell.runtime.evaluate(b": SHELL-TEST-OBSERVE >R R@ 8 + ! R@ ! 1 R> 16 + +! ;")
    shell.runtime.evaluate(b"' SHELL-TEST-OBSERVE")
    xt = shell.runtime.main_context.data.pop()
    shell.results("AHOST-SHELL-OBSERVE!", xt, context)
    shell.results("AHOST-SHELL-MODEL!", model, host)
    assert shell.results("AHOST-SHELL-DRAW-COMPLETE", host) == (0,)
    assert shell.runtime.memory.read64(context) == model
    assert shell.runtime.memory.read64(context + 8) == host
    assert shell.runtime.memory.read64(context + 16) == 1
    shell.results("AHOST-SHELL-MODEL!", 0, host)
    assert shell.results("AHOST-SHELL-DRAW-COMPLETE", host) == (0,)
    assert shell.runtime.memory.read64(context) == 0
    shell.runtime.evaluate(b": SHELL-TEST-FAIL 2DROP DROP -77 THROW ; ' SHELL-TEST-FAIL")
    xt = shell.runtime.main_context.data.pop()
    shell.results("AHOST-SHELL-OBSERVE!", xt, context)
    assert shell.results("AHOST-SHELL-DRAW-COMPLETE", host) == ((-77) & MASK64,)


def test_null_wrapping_alias_and_corrupt_header_fail_without_mutation(shell):
    model, size = shell.model()
    before = shell.runtime.memory.read_bytes(model, size)
    for address, length in ((0, size), (MASK64 - 7, size), (model, MASK64)):
        assert not shell.call("SHM-INIT", length, 4, address)
    scratch = shell.runtime.find("_SHMI-M").body_address
    assert not shell.call("SHM-INIT", 512, 1, scratch)
    assert shell.runtime.memory.read_bytes(model, size) == before
    for address, length in ((0, 1), (MASK64 - 1, 8), (model, 1), (scratch, 1)):
        assert shell.results("SHM-COPY$", address, length, model) == (0, 0)
        assert shell.runtime.memory.read_bytes(model, size) == before
    for field, value in (("SHM.USED", MASK64), ("SHM.COUNT", 9), ("SHM.ENTRY-LIMIT", MASK64)):
        shell.field(model, field, value)
        damaged = shell.runtime.memory.read_bytes(model, size)
        assert shell.results("SHM-APPEND", model) == (0,)
        assert shell.results("SHM-COPY$", 0, 0, model) == (0, 0)
        assert shell.runtime.memory.read_bytes(model, size) == damaged
        shell.runtime.memory.write_bytes(model, before)


def test_labels_cut_only_at_grapheme_and_cell_boundaries(shell):
    # These are the real Unicode tables, segmenter and production prefix word.
    # Loading them here also compiles the complete new module in both engines.
    for relative in ("text/utf8.f", "text/unicode-tables.f", "text/unicode-props.f",
                     "text/grapheme.f", "tui/shell-model.f"):
        source = (ROOT / "akashic" / relative).read_text()
        source = "\n".join(line for line in source.splitlines()
                           if not line.strip().startswith(("PROVIDED ", "REQUIRE ")))
        shell.runtime.evaluate(source.encode(), step_budget=3_000_000)
    value = "A界e\u0301".encode()
    text = shell.allocate(value)
    for byte_limit, cell_limit, expected in ((64, 3, (4, 3)), (64, 4, (7, 4)),
                                            (6, 9, (4, 3)), (2, 9, (1, 1)),
                                            (64, 0, (0, 0))):
        assert shell.results("SHM-TEXT-PREFIX", text, len(value), byte_limit, cell_limit) == expected
