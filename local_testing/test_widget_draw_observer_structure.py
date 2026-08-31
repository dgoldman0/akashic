#!/usr/bin/env python3
"""Seconds-scale architecture locks for generic widget draw observation."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WIDGET = ROOT / "akashic/tui/widget.f"
TEXTAREA = ROOT / "akashic/tui/widgets/textarea.f"
UIDL_TUI = ROOT / "akashic/tui/uidl-tui.f"


def _definitions(source: str, name: str) -> list[str]:
    return re.findall(
        rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;", source
    )


def _first(source: str, name: str) -> str:
    definitions = _definitions(source, name)
    assert definitions, f"missing Forth word {name}"
    return definitions[0]


def _last(source: str, name: str) -> str:
    definitions = _definitions(source, name)
    assert definitions, f"missing Forth word {name}"
    return definitions[-1]


def _executable(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def test_observer_is_renderer_neutral_and_preserves_draw_authority() -> None:
    source = WIDGET.read_text(encoding="utf-8")
    executable = _executable(source)
    draw = _first(source, "WDG-DRAW")
    scope = _first(source, "WDG-DRAW-OBSERVE")

    assert re.findall(r"(?m)^REQUIRE (.+)$", source) == [
        "region.f",
        "../concurrency/guard.f",
    ]
    for forbidden in (
        "uidl",
        "textarea",
        "semantic",
        "rich-terminal",
        "applets/",
        "ALLOCATE",
        " FREE",
    ):
        assert forbidden.lower() not in executable.lower()

    assert draw.index("RGN-USE") < draw.index("WDG-DRAW-PHASE-FULL-BEGIN")
    assert draw.index("WDG-DRAW-PHASE-FULL-BEGIN") < draw.index("CATCH")
    assert "WDG-DRAW-PHASE-FULL-ABORT" in draw
    assert draw.index("WDG-DRAW-PHASE-FULL-END") < draw.index("WDG-CLEAN")

    assert "_WDG-OBS-ACTIVE @ IF" in scope
    assert "CATCH _WDG-OBS-IOR !" in scope
    assert scope.index("_WDG-OBS-CLEAR") < scope.index("THROW")
    assert "WITH-GUARD" not in _last(source, "WDG-DRAW-OBSERVE")
    assert "_wdg-draw-observe-xt EXECUTE" in _last(
        source, "WDG-DRAW-OBSERVE"
    )


def test_partial_textarea_reports_only_after_successful_clean() -> None:
    source = TEXTAREA.read_text(encoding="utf-8")
    partial = _first(source, "TXTA-DRAW-ROWS")

    ordered = (
        "RGN-USE",
        "_TXTA-DRAW-RANGE",
        "WDG-CLEAN",
        "WDG-DRAW-PARTIAL-COMPLETE",
    )
    positions = [partial.index(word) for word in ordered]
    assert positions == sorted(positions)
    assert "TXTA-TEXT-AREA-CAPTURE" not in partial
    assert "USCOL-" not in partial


def test_uidl_widget_renderers_use_the_common_draw_boundary() -> None:
    source = UIDL_TUI.read_text(encoding="utf-8")

    for name in (
        "_UTUI-RENDER-INPUT",
        "_UTUI-RENDER-REGION",
        "_UTUI-RENDER-TREE",
        "_UTUI-RENDER-TEXTAREA",
    ):
        renderer = _first(source, name)
        assert "WDG-DRAW" in renderer
        assert "_WDG-O-DRAW-XT" not in renderer
        assert "_INP-DRAW" not in renderer
        assert "_TREE-DRAW" not in renderer
        assert "_TXTA-DRAW" not in renderer
        assert renderer.index("WDG-DRAW") < renderer.index(
            "_UTUI-RESTORE-DOC-RGN"
        )
