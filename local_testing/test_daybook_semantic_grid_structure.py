"""Structural locks for Daybook's renderer-neutral calendar grid."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/applets/daybook/daybook.f"
DOC = ROOT / "docs/tui/applets/daybook/daybook.md"


def _source() -> str:
    return SOURCE.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_daybook_imports_only_the_neutral_collection_family() -> None:
    source = _source()

    assert "REQUIRE ../../uidl-semantic-collections.f" in source
    for forbidden in (
        "rich-terminal.f",
        "RTAPT-",
        "APT-1",
        "RET_CONTROL_COLLECTIONS",
        "RTE-F-CONTROL-COLLECTIONS",
    ):
        assert forbidden not in source


def test_wide_calendar_and_grid_shapes_are_exact() -> None:
    source = _source()
    wide = _word(source, "_DB-WIDE-LAYOUT?")
    draw = _word(source, "_DB-PANEL-DRAW")
    emit = _word(source, "_DB-SEMANTIC-EMIT")

    for declaration in (
        "72 CONSTANT _DB-WIDE-MIN-WIDTH",
        "14 CONSTANT _DB-WIDE-MIN-HEIGHT",
        "25 CONSTANT _DB-CALENDAR-WIDTH",
        "10 CONSTANT _DB-CALENDAR-HEIGHT",
        " 8 CONSTANT _DB-SEM-GRID-ROWS",
        " 7 CONSTANT _DB-SEM-GRID-COLUMNS",
    ):
        assert declaration in source

    assert "_DB-WIDE-MIN-WIDTH >=" in wide
    assert "_DB-WIDE-MIN-HEIGHT >=" in wide
    assert "_DB-WIDE-LAYOUT?" in draw
    assert "USCOL-F-TEXT-GRID _DB-SEM-ROOT-KEY" in emit
    assert "0 0 _DB-CALENDAR-HEIGHT _DB-CALENDAR-WIDTH" in emit
    assert "_DB-SEM-GRID-ROWS _DB-SEM-GRID-COLUMNS" in emit
    assert "USCOL-CONTENT-READ-ONLY" in emit


def test_narrow_layout_emits_an_exact_empty_payload() -> None:
    payload = _word(_source(), "_DB-SEMANTIC-PAYLOAD")

    predicate = payload.index("_DB-WIDE-LAYOUT? 0= IF")
    empty = payload.index("0 UTUI-SEMANTIC-S-OK EXIT", predicate)
    emit = payload.index("_DB-SEMANTIC-EMIT", empty)
    assert predicate < empty < emit


def test_grid_items_have_stable_scoped_keys_and_roles() -> None:
    source = _source()
    title = _word(source, "_DB-SEM-EMIT-TITLE")
    weekdays = _word(source, "_DB-SEM-EMIT-WEEKDAYS")
    dates = _word(source, "_DB-SEM-EMIT-DATES")
    date_key = _word(source, "_DB-SEM-DATE-KEY")

    for declaration in (
        " 1 CONSTANT _DB-SEM-ROOT-KEY",
        " 1 CONSTANT _DB-SEM-TITLE-KEY",
        " 2 CONSTANT _DB-SEM-WEEKDAY-KEY-BASE",
        " 9 CONSTANT _DB-SEM-DATE-KEY-BIAS",
    ):
        assert declaration in source

    assert "_DB-SECONDS-DAY / _DB-SEM-DATE-KEY-BIAS +" in date_key
    assert "USCOL-ROLE-ROW-HEADER" in title
    assert "_DB-SEM-GRID-COLUMNS 0 DO" in weekdays
    assert "USCOL-ROLE-COLUMN-HEADER" in weekdays
    assert "_DB-SG-DAYS @ 1+ 1 DO" in dates
    assert "USCOL-ROLE-CONTENT" in dates
    assert "_DB-TODAY-CACHE @ =" in dates
    assert "USCOL-ITEM-CURRENT" in dates


def test_selected_date_is_primary_and_today_is_cached() -> None:
    source = _source()
    emit = _word(source, "_DB-SEMANTIC-EMIT")
    init = _word(source, "DAYBOOK-INIT-CB")
    tick = _word(source, "DAYBOOK-TICK-CB")

    assert "CMP-CELL: _DB-TODAY-CACHE" in source
    assert "_DB-SELECTED-DATE @ _DB-SEM-DATE-KEY 0 0 0" in emit
    assert "_DB-NOW-DAY DUP _DB-TODAY-CACHE ! _DB-SELECTED-DATE !" in init
    assert "_DB-REFRESH-TODAY IF -1 _DB-VIEW-DIRTY ! THEN" in tick
    assert "_DB-VIEW-DIRTY @ IF" in tick
    assert "_DB-INVALIDATE" in tick


def test_provider_uses_normal_widget_registration_and_touch_lifecycle() -> None:
    source = _source()
    init = _word(source, "DAYBOOK-INIT-CB")
    invalidate = _word(source, "_DB-INVALIDATE")
    snapshot = _word(source, "_DB-SEMANTIC-SNAPSHOT")

    attach = init.index("_DB-PANEL _DB-E-BODY @ UTUI-WIDGET-SET")
    register = init.index("['] _DB-SEMANTIC-SNAPSHOT", attach)
    assert attach < register
    assert "1 ['] _DB-SEMANTIC-SNAPSHOT 0 _DB-CURRENT-INSTANCE @" in init
    assert "_DB-E-BODY @ UTUI-SEMANTIC-SET" in init
    assert "UTUI-SEMANTIC-TOUCH" in invalidate
    assert "UTUI-SEMANTIC-S-OK <> IF" in invalidate
    assert "UIDL-DIRTY!" in invalidate
    context_guard = snapshot.index("_DB-SG-CONTEXT @ DUP 0= IF")
    activate = snapshot.index("_DB-ACTIVATE", context_guard)
    element_guard = snapshot.index("_DB-SG-ELEM @ _DB-E-BODY @ = 0=", activate)
    region = snapshot.index("_DB-SG-ELEM @ UTUI-ELEM-RGN", element_guard)
    assert context_guard < activate < element_guard < region
    assert "UTUI-ELEM-RGN" in snapshot
    assert "_DB-SEMANTIC-PAYLOAD" in snapshot


def test_daybook_documentation_records_the_neutral_contract() -> None:
    doc = " ".join(DOC.read_text(encoding="utf-8").split())

    for phrase in (
        "exactly 72 columns by 14 rows",
        "one renderer-neutral `TEXT_GRID`",
        "valid zero-entry snapshot",
        "8-by-7 logical grid",
        "signed epoch-day plus 9",
        "cached day-aligned `today`",
        "contains no terminal bytes",
    ):
        assert phrase in doc
