"""Execute the real screen/draw residue lifecycle on small guest surfaces.

These units load only the screen's actual source dependency closure.  They
exercise scalar and bulk drawing, exception unwinding, and resize without
booting Desktop, creating a terminal session, or using a model of the code.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys

import pytest


ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", ROOT.parent / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from simulator.runtime import MegaForthRuntime  # noqa: E402
from tests.simulator.test_kdos_exceptions import _load_exceptions  # noqa: E402


STEP_BUDGET = 3_000_000
MASK64 = (1 << 64) - 1


def _word(path: str, name: str) -> str:
    source = (ROOT / "akashic" / path).read_text()
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match[0]


class ScreenHarness:
    def __init__(self, backend: str):
        self.runtime = _load_exceptions(MegaForthRuntime(execution_backend=backend))
        # The exception fixture loads KDOS's real reclaiming Bank-0 allocator;
        # public XMEM routing is outside this small screen fixture.  Select
        # its ordinary Bank-0 route explicitly rather than inventing an
        # allocator or exposing dictionary bytes as screen-owned storage.
        self.evaluate(": ALLOCATE (BANK0-ALLOCATE) ; : FREE (BANK0-FREE) ;")
        for relative in (
            "utils/uint-range.f", "utils/memory-span.f", "tui/cell.f",
            "tui/ansi.f", "text/utf8.f", "text/cell-width.f",
            "utils/term.f", "tui/screen.f", "tui/draw.f",
        ):
            source = (ROOT / "akashic" / relative).read_text()
            # Only source-loading directives are removed.  The complete
            # production definitions and their normal top-level state run.
            source = re.sub(r"(?m)^\s*(?:REQUIRE|PROVIDED)\s+[^\n]+", "", source)
            self.evaluate(source)
        self.evaluate("""
            : RP-BASE 65 7 0 0 CELL-MAKE 1 2 SCR-SET ;
            : RP-NEXT 67 7 0 0 CELL-MAKE 1 2 SCR-SET ;
            : RP-LEAF 66 7 0 0 CELL-MAKE 1 2 SCR-SET ;
            : RP-REPLACE ['] RP-LEAF DRW-REPLACEMENT ;
            : RP-BULK 90 0 0 4 8 DRW-FILL-RECT ;
            : RP-BULK-REPLACE ['] RP-BULK DRW-REPLACEMENT ;
            : RP-THROW RP-REPLACE -77 THROW ;
            : RP-NESTED ['] RP-THROW DRW-REPLACEMENT ;
            : RP-CATCH ['] RP-NESTED CATCH ;
            : RP-FOREGROUND ['] RP-LEAF DRW-OVERLAY ;
            : RP-FOREGROUND-REPLACE ['] RP-FOREGROUND DRW-REPLACEMENT ;
            : RP-PROJECTION-ARGS ;
            : RP-PROJECTION ['] RP-PROJECTION-ARGS SCR-WITH-PROJECTION-PLANES ;
            : RP-FRAME ['] RP-PROJECTION-ARGS SCR-WITH-PROJECTION-FRAME-PLANES ;
            : RP-REFUSE DROP SCB-S-WOULD-BLOCK ;
            : RP-REFUSE! ['] RP-REFUSE SCR-BACKEND@ SCB.COMMIT-XT ! ;
            : RP-ACCEPT! ['] _SCBA-COMMIT SCR-BACKEND@ SCB.COMMIT-XT ! ;
        """)
        self.screen = self.call("SCR-NEW", 8, 4)[0]
        self.call("SCR-USE", self.screen)

    def evaluate(self, source: str):
        self.runtime.evaluate(source.encode(), source_name="screen-residue-test.f",
                              step_budget=STEP_BUDGET)
        assert self.runtime.main_context.data.snapshot() == ()

    def call(self, name: str, *inputs: int) -> tuple[int, ...]:
        stack = self.runtime.main_context.data
        assert stack.snapshot() == ()
        for value in inputs:
            stack.push(value)
        self.runtime.execute(name, step_budget=STEP_BUDGET)
        result = stack.snapshot()
        while stack.depth():
            stack.pop()
        assert self.runtime.main_context.returns.snapshot() == ()
        return result

    def address(self, name: str) -> int:
        word = self.runtime.find(name)
        assert word is not None, name
        return word.body_address

    def plane(self, offset: int, count: int = 32) -> tuple[int, ...]:
        address = self.runtime.memory.read64(self.screen + offset)
        return tuple(self.runtime.memory.read64(address + 8 * i) for i in range(count))

    def close(self):
        self.call("SCR-FREE", self.screen)


@pytest.fixture(params=("python", "native"))
def screen(request):
    harness = ScreenHarness(request.param)
    yield harness
    harness.close()


def test_replacement_keeps_current_underlay_across_partial_draws(screen):
    screen.call("RP-BASE")
    expected = screen.plane(24)
    screen.call("RP-REPLACE")
    assert screen.plane(128) == expected
    assert screen.plane(24)[10] & 0xFFFFFFFF == ord("B")

    # An unchanged overlay drawn again must not capture its own pixels.
    screen.call("RP-REPLACE")
    assert screen.plane(128) == expected
    screen.call("RP-NEXT")
    screen.call("RP-REPLACE")
    assert screen.plane(128)[10] & 0xFFFFFFFF == ord("C")
    assert screen.plane(24)[10] & 0xFFFFFFFF == ord("B")

    # Ordinary close repaint leaves the complete fallback identical.
    screen.call("RP-NEXT")
    assert screen.plane(128) == screen.plane(24)


def test_bulk_draw_and_scalar_fill_share_the_same_residue_authority(screen):
    screen.call("SCR-FILL", 42)
    screen.call("RP-BULK-REPLACE")
    assert screen.plane(128) == (42,) * 32
    assert all(cell & 0xFFFFFFFF == ord("Z") for cell in screen.plane(24))
    screen.call("RP-BULK")
    assert screen.plane(128) == screen.plane(24)
    screen.call("SCR-FILL", 43)
    assert screen.plane(128) == screen.plane(24) == (43,) * 32


def test_nested_exception_and_foreground_restore_scope_authority(screen):
    screen.call("RP-BASE")
    assert screen.call("RP-CATCH") == ((-77) & MASK64,)
    assert screen.call("_SCR-REPLACEMENT?") == (0,)
    assert screen.runtime.memory.read64(screen.address("_SCR-REPLACEMENT-DEPTH")) == 0
    assert screen.plane(128)[10] & 0xFFFFFFFF == ord("A")
    screen.call("RP-NEXT")
    assert screen.plane(128) == screen.plane(24)

    # Unsupported foreground content survives even under a replacement body.
    screen.call("RP-FOREGROUND-REPLACE")
    assert screen.plane(128) == screen.plane(24)
    occlusion = screen.runtime.memory.read64(screen.screen + 120)
    assert screen.runtime.memory.read8(occlusion + 10) == 255


def test_residue_only_change_remains_dirty_until_accepted_commit(screen):
    screen.call("RP-BASE")
    screen.call("RP-REPLACE")
    assert screen.call("SCR-FLUSH?") == (0,)
    assert screen.call("SCR-PROJECTION-DIRTY?") == (0,)
    front = screen.plane(16)

    # The ordinary writer now writes B: BACK does not change, but the residue
    # changes A -> B and must invalidate a supposedly unchanged projection.
    screen.call("RP-LEAF")
    assert screen.plane(24) == front
    assert screen.call("SCR-PROJECTION-DIRTY?") == (MASK64,)
    damage = screen.runtime.memory.read64(screen.screen + 144)
    assert screen.runtime.memory.read_bytes(damage, 4) == bytes((0, 1, 0, 0))
    screen.call("SCR-DRAW-COMPLETE")
    assert screen.call("RP-PROJECTION")[4:] == (1, MASK64)
    screen.call("RP-REFUSE!")
    assert screen.call("SCR-FLUSH?") == (1,)
    assert screen.call("SCR-PROJECTION-DIRTY?") == (MASK64,)
    assert screen.runtime.memory.read_bytes(damage, 4) == bytes((0, 1, 0, 0))
    screen.call("RP-ACCEPT!")
    assert screen.call("SCR-FLUSH?") == (0,)
    assert screen.call("SCR-PROJECTION-DIRTY?") == (0,)
    assert screen.runtime.memory.read_bytes(damage, 4) == bytes(4)
    screen.call("RP-LEAF")
    assert screen.call("SCR-PROJECTION-DIRTY?") == (0,)


def test_resize_and_borrows_preserve_paired_cells_and_screen_authority(screen):
    screen.call("RP-BASE")
    screen.call("RP-REPLACE")
    before_back, before_residue = screen.plane(24), screen.plane(128)
    screen.call("SCR-RESIZE", 10, 5)
    resized_back, resized_residue = screen.plane(24, 50), screen.plane(128, 50)
    for row in range(4):
        assert resized_back[row * 10:row * 10 + 8] == before_back[row * 8:row * 8 + 8]
        assert resized_residue[row * 10:row * 10 + 8] == before_residue[row * 8:row * 8 + 8]
    projection = screen.call("RP-PROJECTION")
    frame = screen.call("RP-FRAME")
    assert projection[2:4] == (10, 5)
    assert frame[1] == projection[0] and frame[9] == projection[1]
    assert frame[2:4] == projection[2:4]
    assert frame[5] == projection[4] and projection[5] == MASK64
    assert frame[11] == 5
    assert screen.runtime.memory.read_bytes(frame[10], frame[11]) == bytes((0, 1, 0, 0, 0))
    assert frame[6] == MASK64  # The new geometry still requires a full snapshot.
    assert screen.call("SCR-STORAGE-DISJOINT?", projection[1], 8) == (0,)
    residue_front = screen.runtime.memory.read64(screen.screen + 152)
    assert screen.call("SCR-STORAGE-DISJOINT?", residue_front, 8) == (0,)
    assert screen.call("SCR-BACKEND@")[0] % 8 == 0
    assert screen.call("SCR-STORAGE-DISJOINT?", 0, 0) == (MASK64,)


def test_clear_and_restore_resolves_to_exact_clean_projection(screen):
    screen.call("RP-BASE")
    screen.call("RP-REPLACE")
    assert screen.call("SCR-FLUSH?") == (0,)
    committed = screen.plane(152)
    front = screen.plane(16)
    assert committed == screen.plane(128)

    # The ordinary painter clears and restores content before the menu paints
    # again.  Neither final plane changed, despite transient residue writes.
    screen.call("SCR-CLEAR")
    screen.call("RP-BASE")
    screen.call("RP-REPLACE")
    assert screen.plane(24) == front
    assert screen.plane(128) == committed
    assert screen.call("SCR-PROJECTION-DIRTY?") == (0,)
    frame = screen.call("RP-FRAME")
    assert screen.runtime.memory.read_bytes(frame[10], frame[11]) == bytes(4)

    # A resolved unequal row becomes a fresh candidate when written again.
    screen.call("RP-NEXT")
    screen.call("RP-REPLACE")
    assert screen.call("SCR-PROJECTION-DIRTY?") == (MASK64,)
    screen.call("RP-BASE")
    screen.call("RP-REPLACE")
    assert screen.call("RP-PROJECTION")[-1] == 0
    assert screen.plane(152) == committed


def test_refused_projection_keeps_accepted_residue_baseline(screen):
    screen.call("RP-BASE")
    screen.call("RP-REPLACE")
    assert screen.call("SCR-FLUSH?") == (0,)
    committed = screen.plane(152)
    cell_front = screen.plane(16)
    screen.call("RP-NEXT")
    screen.call("RP-REPLACE")
    assert screen.plane(24) == cell_front
    screen.call("RP-REFUSE!")
    assert screen.call("SCR-FLUSH?") == (1,)
    assert screen.call("SCR-PROJECTION-DIRTY?") == (MASK64,)
    assert screen.plane(152) == committed

    # Restoring the accepted underlay after refusal is clean; a refused
    # candidate must never become the comparison baseline.
    screen.call("RP-BASE")
    screen.call("RP-REPLACE")
    assert screen.call("SCR-PROJECTION-DIRTY?") == (0,)
    screen.call("RP-NEXT")
    screen.call("RP-REPLACE")
    screen.call("RP-ACCEPT!")
    assert screen.call("SCR-FLUSH?") == (0,)
    assert screen.plane(152) == screen.plane(128)
    assert screen.plane(152) != committed
    assert screen.call("SCR-PROJECTION-DIRTY?") == (0,)


def test_real_adapter_classifier_preserves_dirty_child_under_clean_menu(screen):
    # Minimal ordinary document accessors isolate the actual production
    # classifier and per-element paint boundary from a full UIDL source load.
    screen.evaluate("""
        VARIABLE _UTUI-PROJ-ATTACHED -1 _UTUI-PROJ-ATTACHED !
        VARIABLE _UTUI-PAINT-LAYER-OBSERVER
        10 CONSTANT UIDL-T-MENUBAR 11 CONSTANT UIDL-T-MENU
        : UIDL-TYPE @ ; : UIDL-PARENT 8 + @ ;
        CREATE RP-PARENT 11 , 0 , CREATE RP-CHILD 12 , RP-PARENT ,
        CREATE RP-OTHER 13 , 0 ,
        : _UTUI-RENDER-ONE-BODY DROP RP-LEAF ;
    """)
    for path, name in (
        ("tui/uidl-tui.f", "_UTUI-PAINT-LAYER-OBSERVER!"),
        ("tui/rich-terminal/uidl-hybrid-adapter.f", "_RUHA-REPLACEABLE-PAINT?"),
        ("tui/uidl-tui.f", "_UTUI-RENDER-ONE-IN-STATE"),
    ):
        screen.evaluate(_word(path, name))
    screen.evaluate("' _RUHA-REPLACEABLE-PAINT? _UTUI-PAINT-LAYER-OBSERVER! DROP")
    screen.call("RP-BASE")
    child = screen.call("RP-CHILD")[0]
    screen.call("_UTUI-RENDER-ONE-IN-STATE", child)
    assert screen.plane(128)[10] & 0xFFFFFFFF == ord("A")
    assert screen.plane(24)[10] & 0xFFFFFFFF == ord("B")
    screen.call("_UTUI-RENDER-ONE-IN-STATE", screen.call("RP-OTHER")[0])
    assert screen.plane(128) == screen.plane(24)
