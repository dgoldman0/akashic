"""Seconds-scale structural locks for neutral semantic collection families."""

from pathlib import Path
import re
import struct


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/semantic-collections.f"
DOC = ROOT / "docs/tui/semantic-collections.md"


def _source() -> str:
    return SOURCE.read_text(encoding="utf-8")


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*$", source)
    assert match is not None, name
    return match.group(0)


def test_native_layouts_are_aligned_pointer_free_and_u32_interoperable() -> None:
    source = _source()

    for declaration in (
        "0 CONSTANT USCOL-S-OK",
        "1 CONSTANT USCOL-S-UNSUPPORTED",
        "2 CONSTANT USCOL-S-CAPACITY",
        "3 CONSTANT USCOL-S-UNAVAILABLE",
        "4 CONSTANT USCOL-S-INVALID",
        "32 CONSTANT USCOL-ENTRY-HEADER-SIZE",
        "1 CONSTANT USCOL-FAMILY-ABI",
        "1 CONSTANT USCOL-F-TEXT-AREA",
        "2 CONSTANT USCOL-F-TEXT-GRID",
        "3 CONSTANT USCOL-F-TABSET",
        "4 CONSTANT USCOL-F-ITEM-VIEW",
        "168 CONSTANT USCOL-TEXT-FIXED-SIZE",
        "72 CONSTANT USCOL-ITEM-HEADER-SIZE",
        "24 CONSTANT USCOL-RUN-SIZE",
        "80 CONSTANT USCOL-TABSET-FIXED-SIZE",
        "40 CONSTANT USCOL-TAB-HEADER-SIZE",
        "128 CONSTANT USCOL-IV-FIXED-SIZE",
        "16 CONSTANT USCOL-COLUMN-HEADER-SIZE",
        "56 CONSTANT USCOL-VI-HEADER-SIZE",
        "16 CONSTANT USCOL-FIELD-HEADER-SIZE",
        "64 CONSTANT USCOL-SUMMARY-SIZE",
        "88 CONSTANT USCOL-BUILDER-SIZE",
    ):
        assert declaration in source

    native_text = struct.pack("<21Q", *range(21))
    native_item = struct.pack("<9Q", *range(9))
    native_run = struct.pack("<3Q", *range(3))
    native_tabset = struct.pack("<10Q", *range(10))
    native_tab = struct.pack("<5Q", *range(5))
    native_view = struct.pack("<16Q", *range(16))
    native_view_item = struct.pack("<7Q", *range(7))
    assert len(native_text) == 168
    assert len(native_item) == 72
    assert len(native_run) == 24
    assert len(native_tabset) == 80
    assert len(native_tab) == 40
    assert len(native_view) == 128
    assert len(native_view_item) == 56
    assert struct.unpack_from("<Q", native_text, 160)[0] == 20
    assert struct.unpack_from("<Q", native_item, 64)[0] == 8
    assert struct.unpack_from("<Q", native_tab, 32)[0] == 4
    assert struct.unpack_from("<Q", native_view, 120)[0] == 15
    assert struct.unpack_from("<Q", native_view_item, 48)[0] == 6

    # Text items, tabs, and view items each stop at the u32 count.
    assert source.count("_USCOL-B.COUNT@ 0xFFFFFFFF = IF") == 3
    assert "USCOL-MAX" not in source
    assert "ITEM-MAX" not in source
    assert "TAB-MAX" not in source


def test_module_is_renderer_wire_and_registration_neutral() -> None:
    source = _source()
    requires = re.findall(r"(?m)^REQUIRE (.+)$", source)

    assert requires == [
        "../text/utf8.f",
        "../text/grapheme.f",
        "../text/text-style.f",
        "../utils/memory-span.f",
    ]
    for forbidden in (
        "ALLOCATE",
        " FREE",
        "uidl-tui.f",
        "UTUI-",
        "WDG-",
        "RTAPT-",
        "APT-1",
        "RET_CONTROL_COLLECTIONS",
        "UTUI-SEMANTIC-SET",
        "UTUI-SEMANTIC-REVISION!",
        "Pad",
        "Daybook",
    ):
        assert forbidden not in source

    for accessor in (
        "USCOL-ENTRY-BYTES@",
        "USCOL-ENTRY-FAMILY@",
        "USCOL-ENTRY-FAMILY-ABI@",
        "USCOL-ENTRY-KEY@",
        "USCOL-ENTRY-PAYLOAD@",
    ):
        assert f": {accessor}" in source

    for accessor, offset in (
        ("USCOL-ENTRY-BYTES@", 0),
        ("USCOL-ENTRY-FAMILY@", 8),
        ("USCOL-ENTRY-FAMILY-ABI@", 16),
        ("USCOL-ENTRY-KEY@", 24),
    ):
        body = _word(source, accessor)
        if offset:
            assert f"{offset} + @" in body
        else:
            assert "+ @" not in body
    payload = _word(source, "USCOL-ENTRY-PAYLOAD@")
    assert payload.count("USCOL-ENTRY-HEADER-SIZE") == 2


def test_builder_and_validation_authority_has_a_public_alias_boundary() -> None:
    source = _source()
    disjoint = _word(source, "USCOL-STORAGE-DISJOINT?")

    assert "CREATE _USCOL-OWNED-START" in source
    assert "CREATE _USCOL-OWNED-END" in source
    assert "_USCOL-OWNED-END _USCOL-OWNED-LIMIT !" in source
    assert "MSPAN-NONWRAPPING? 0=" in disjoint
    assert "_USCOL-OWNED-LIMIT @" in disjoint
    assert "MSPAN-OVERLAP? 0=" in disjoint


def test_builder_has_exact_measure_copy_and_gap_fill_lifecycle() -> None:
    source = _source()
    reserve = _word(source, "_USCOL-B-RESERVE")
    begin = _word(source, "USCOL-TEXT-ITEM-BEGIN")
    end = _word(source, "USCOL-TEXT-ITEM-END")
    contiguous = _word(source, "USCOL-TEXT-ITEM")
    latch = _word(source, "_USCOL-B-LATCH")

    assert "_USCOL-B.DST@ IF" in reserve
    assert "_USCOL-B.USED!" in reserve
    assert "_USCOL-B-PHASE-TEXT-ITEM-FILL" in begin
    assert "USCOL-ITEM-TEXT-OFFSET +" in begin
    assert "0\n    THEN\n    USCOL-S-OK" in begin
    assert "_USCOL-B.COUNT@ 1+" in end
    assert "_USCOL-B-PHASE-TEXT-ITEMS" in end
    assert "USCOL-TEXT-ITEM-BEGIN" in contiguous
    assert "MOVE" in contiguous
    assert "USCOL-TEXT-ITEM-END" in contiguous
    assert "_USCOL-B.STATUS@" in latch
    assert "_USCOL-BL-B @ _USCOL-B.STATUS@ ;" in latch


def test_work_sizing_is_count_only_and_bounded_to_key_uniqueness() -> None:
    source = _source()
    public = _word(source, "USCOL-VALIDATION-WORK-BYTES")
    keys = _word(source, "_USCOL-WORK-FOR-KEYS")

    assert "8 _USCOL-MUL?" in keys
    assert public.count("_USCOL-WORK-FOR-KEYS") == 2
    assert "USCOL-ITEM-NEXT" not in public
    assert "USCOL-TAB-NEXT" not in public
    assert "USCOL-TEXT-ITEM-COUNT@" in public
    assert "USCOL-TABSET-COUNT@" in public
    assert "_USCOL-GENERAL-OVERLAP-FREE?" not in source
    assert "_USCOL-END-SORT" not in source
    assert "_USCOL-RANGE-SUM" not in source


def test_validator_is_the_one_utf8_geometry_and_uniqueness_authority() -> None:
    source = _source()
    analyze = _word(source, "_USCOL-TEXT-ANALYZE")
    text = _word(source, "_USCOL-VALIDATE-TEXT")
    item = _word(source, "_USCOL-VT-ITEM-HEADER?")
    validate = _word(source, "USCOL-ENTRY-VALIDATE")

    assert analyze.count("UTF8-VALID?") == 1
    assert "UTF8-DECODE" not in source
    assert "_USCOL-TEXT-ANALYZE" in text
    assert "_USCOL-UNIQUE-CELLS?" in text
    assert "USCOL-ITEM-ROW-SPAN@ 1 <> IF 0 EXIT THEN" in item
    assert "_USCOL-VT-ORDER-STEP?" in text
    assert "_USCOL-VT-CANONICAL?" not in source
    assert "_USCOL-VT-UNIT-STEP" not in source
    assert "_USCOL-V-COUNT @ 36 _USCOL-MUL?" in text
    assert "72 _USCOL-ADD?" in text
    assert "_USCOL-V-UTF8 @ _USCOL-ADD?" in text
    assert "_USCOL-V-RUNS @ 12 _USCOL-MUL?" in text
    assert "_USCOL-U32?" in text
    assert "USCOL-SUMMARY-SIZE 0 FILL" in validate
    assert validate.index("USCOL-SUMMARY-SIZE 0 FILL") < validate.index(
        "USCOL-VALIDATION-WORK-BYTES"
    )
    assert validate.index("USCOL-VALIDATION-WORK-BYTES") < validate.index(
        "_USCOL-V-ROOT?"
    )
    assert validate.index("_USCOL-V-ROOT?") < validate.index(
        "_USCOL-V-SUMMARY!"
    )


def test_summary_derives_wire_size_without_rescanning_the_forest() -> None:
    source = _source()
    derive = _word(source, "USCOL-SUMMARY-STX1-BYTES")
    doc = DOC.read_text(encoding="utf-8")

    assert "USCOL-SUMMARY-ITEM-COUNT@ 36 _USCOL-MUL?" in derive
    assert "72 _USCOL-ADD?" in derive
    assert "USCOL-SUMMARY-UTF8-BYTES@ _USCOL-ADD?" in derive
    assert "USCOL-SUMMARY-RUN-COUNT@ 12 _USCOL-MUL?" in derive
    assert "USCOL-ITEM" not in derive
    assert "72 + 36*item-count + total-utf8 + 12*total-runs" in doc

    items = _word(source, "USCOL-SUMMARY-ITM1-BYTES")
    for term in (
        "USCOL-SUMMARY-CHILD-COUNT@ 8 _USCOL-MUL?",
        "USCOL-SUMMARY-ITEM-COUNT@ 32 _USCOL-MUL?",
        "USCOL-SUMMARY-FIELD-COUNT@ 8 _USCOL-MUL?",
        "USCOL-SUMMARY-UTF8-BYTES@ _USCOL-ADD?",
        "USCOL-SUMMARY-RUN-COUNT@ 12 _USCOL-MUL?",
    ):
        assert term in items
    assert "USCOL-VI-" not in items
    assert "40 + 8*column-count + 32*item-count + 8*field-count" in doc
    assert "same immutable attempt bank" in doc
    assert "does not register a provider" in doc
    assert "Packing must not repeat UTF-8, key, geometry, caret, or overlap" in doc
