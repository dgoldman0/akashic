"""Structural locks for Daybook's canonical calendar widget migration."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/applets/daybook/daybook.f"


def _source() -> str:
    return SOURCE.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_daybook_uses_a_real_canonical_text_grid_without_a_provider() -> None:
    source = _source()
    init = _word(source, "DAYBOOK-INIT-CB")
    panel = _word(source, "_DB-PANEL-DRAW")

    assert "REQUIRE ../../widgets/text-grid.f" in source
    assert "TGRID-NEW" in init
    assert "TGRID-BIND" in _word(source, "_DB-GRID-REBUILD")
    assert "_DB-GRID-WIDGET @ WDG-DRAW" in panel
    for forbidden in (
        "UTUI-SEMANTIC-SET",
        "UTUI-SEMANTIC-TOUCH",
        "rich-terminal.f",
        "RTAPT-",
        "RET_CONTROL_COLLECTIONS",
    ):
        assert forbidden not in source


def test_daybook_grid_is_double_banked_and_sized_from_calendar_domain() -> None:
    source = _source()
    rebuild = _word(source, "_DB-GRID-REBUILD")

    assert "32 USCOL-TEXT-ITEM-BYTES CONSTANT _DB-GRID-TITLE-ITEM-CAP" in source
    assert "38 _DB-GRID-SHORT-ITEM-CAP * + CONSTANT _DB-GRID-BANK-CAP" in source
    assert "39 8 * CONSTANT _DB-GRID-WORK-CAP" in source
    assert "CMP-FIELD: _DB-GRID-BANK-A" in source
    assert "CMP-FIELD: _DB-GRID-BANK-B" in source
    assert "_DB-GRID-INACTIVE" in rebuild
    bind = rebuild.index("TGRID-BIND")
    publish = rebuild.index("_DB-GRID-ACTIVE-A !", bind)
    assert bind < publish


def test_cell_drawing_and_input_use_the_same_widget_model() -> None:
    source = _source()
    draw = _word(source, "_DB-PANEL-DRAW")
    handle = _word(source, "_DB-PANEL-HANDLE")
    route = _word(source, "_DB-GRID-HANDLE?")

    assert "_DB-WIDE-LAYOUT?" in draw
    assert "_DB-GRID-LAYOUT" in draw
    assert "_DB-GRID-WIDGET @ WDG-DRAW" in draw
    assert "DUP _DB-GRID-HANDLE?" in handle
    assert "KEY-LEFT" in route and "KEY-RIGHT" in route
    assert "_DB-GRID-WIDGET @ WDG-HANDLE" in route
    assert "_DB-DRAW-CALENDAR" not in source


def test_grid_lifecycle_tracks_today_and_frees_child_before_parent() -> None:
    source = _source()
    init = _word(source, "DAYBOOK-INIT-CB")
    tick = _word(source, "DAYBOOK-TICK-CB")
    shutdown = _word(source, "DAYBOOK-SHUTDOWN-CB")

    assert "_DB-NOW-DAY DUP _DB-TODAY-CACHE ! _DB-SELECTED-DATE !" in init
    assert "_DB-REFRESH-TODAY" in tick
    assert "TGRID-FREE" in shutdown
    assert shutdown.index("TGRID-FREE") < shutdown.index("_DB-GRID-RGN @")
    assert shutdown.index("_DB-GRID-RGN @") < shutdown.index("_DB-PANEL-RGN @")
