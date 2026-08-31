#!/usr/bin/env python3
"""Seconds-scale architecture checks for canonical textarea semantics."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TEXTAREA = ROOT / "akashic" / "tui" / "widgets" / "textarea.f"
GAP_BUFFER = ROOT / "akashic" / "text" / "gap-buf.f"


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;", source)
    assert match, f"missing Forth word {name}"
    return match.group(0)


def _executable(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def test_textarea_owns_one_lower_caller_bounded_text_area_source():
    source = TEXTAREA.read_text()
    section = source.split(
        "10. Renderer-neutral TEXT_AREA observation", 1
    )[1].split("11. Guard", 1)[0]
    executable = _executable(section)

    assert "REQUIRE ../semantic-collections.f" in source
    assert "TXTA-TEXT-AREA-MEASURE" in section
    assert "TXTA-TEXT-AREA-CAPTURE" in section
    assert "USCOL-F-TEXT-AREA" in section
    assert "USCOL-TEXT-ITEM-BEGIN" in section
    assert "USCOL-TEXT-ITEM-END" in section
    assert "GB-COPY" in section

    for forbidden in (
        "ALLOCATE",
        "FREE",
        "TXTA-GET-TEXT",
        "_TXTA-FLAT-BUF",
        "USCOL-ENTRY-VALIDATE",
        "rich-terminal/",
        "uidl-tui",
        "applets/",
    ):
        assert forbidden not in executable


def test_measure_and_capture_share_the_exact_build_path():
    source = TEXTAREA.read_text()
    measure = _word(source, "TXTA-TEXT-AREA-MEASURE")
    capture = _word(source, "TXTA-TEXT-AREA-CAPTURE")

    assert "0 0" in measure
    assert "TXTA-TEXT-AREA-CAPTURE" in measure
    assert "USCOL-BUILDER-INIT" in capture
    assert "_TXTA-SEM-SCAN-SHAPE" in capture
    assert "_TXTA-SEM-POSITIONS" in capture
    assert "_TXTA-SEM-GEOMETRY" in capture
    assert "_TXTA-SEM-EMIT-ROWS" in capture
    assert "USCOL-BUILDER-FINISH" in capture


def test_textarea_value_stays_widget_local_and_gap_copy_has_no_fixed_cap():
    source = TEXTAREA.read_text()
    geometry = _word(source, "_TXTA-SEM-GEOMETRY")
    scan = _word(source, "_TXTA-SEM-SCAN-SHAPE")
    emit = _word(source, "_TXTA-SEM-EMIT-ONE")
    aliases = _word(source, "_TXTA-SEM-SOURCE-OVERLAP?")

    assert "0 _TXTA-SEM-ROOT-ROW !" in geometry
    assert "_TXTA-SEM-GUTTER @ _TXTA-SEM-ROOT-COL !" in geometry
    assert "RGN-ROW" not in geometry
    assert "RGN-COL" not in geometry
    assert "EFFECTIVE" not in geometry

    assert "GB-PRE" in scan
    assert "GB-POST" in scan
    assert "GB-COPY" in emit
    assert "_TXTA-SEM-EMIT-U @ <>" in emit
    for forbidden in ("1024", "MIN", "ALLOCATE", "TXTA-GET-TEXT"):
        assert forbidden not in emit

    assert "_GB-DESC-SZ" in aliases
    assert "_GB-O-BUF" in aliases
    assert "_GB-O-CAP" in aliases
    assert "_GB-O-LIDX" in aliases
    assert "_GB-O-LCAP" in aliases
    assert "GB-STORAGE-DISJOINT?" in aliases
    assert aliases.index("GB-STORAGE-DISJOINT?") < aliases.index(
        "_TXTA-SEM-MODULE-OVERLAP?"
    )


def test_gap_buffer_exposes_a_pure_complete_module_storage_boundary():
    source = GAP_BUFFER.read_text()
    query = _word(source, "GB-STORAGE-DISJOINT?")
    guard = source.split("S15 -- Guard", 1)[1]

    assert "REQUIRE ../utils/memory-span.f" in source
    assert "CREATE _GB-OWNED-START" in source
    assert "CREATE _GB-OWNED-END" in source
    assert "_GB-OWNED-END _GB-OWNED-LIMIT !" in source
    assert source.index("CREATE _GB-OWNED-START") < source.index(
        "VARIABLE _GB-T"
    ) < source.index("CREATE _GB-OWNED-END")
    assert "MSPAN-NONWRAPPING?" in query
    assert "MSPAN-OVERLAP? 0=" in query
    assert "_GB-OWNED-START" in query
    assert "_GB-OWNED-LIMIT" in query
    assert "' GB-STORAGE-DISJOINT?" not in guard
    assert source.count(": GB-STORAGE-DISJOINT?") == 1


def test_semantic_source_graph_and_gap_line_index_are_proven_before_use():
    source = TEXTAREA.read_text()
    storage = _word(source, "_TXTA-SEM-SOURCE-STORAGE?")
    widget_storage = _word(source, "_TXTA-SEM-WIDGET-STORAGE?")
    gap_storage = _word(source, "_TXTA-SEM-GB-STORAGE?")
    gap_index = _word(source, "_TXTA-SEM-GB-INDEX?")
    scan = _word(source, "_TXTA-SEM-SCAN-SHAPE")
    query = _word(source, "TXTA-TEXT-AREA-STORAGE-DISJOINT?")
    capture = _word(source, "TXTA-TEXT-AREA-CAPTURE")

    assert "_TXTA-SEM-WIDGET-STORAGE?" in storage
    assert "_TXTA-SEM-GB-STORAGE?" in storage
    assert "['] _TXTA-DRAW" in widget_storage
    assert "['] _TXTA-HANDLE" in widget_storage
    for field in (
        "_GB-O-CAP",
        "_GB-O-GS",
        "_GB-O-GE",
        "_GB-O-LIDX",
        "_GB-O-LCAP",
        "_GB-O-LCNT",
    ):
        assert field in gap_storage
    assert "_TXTA-SEM-GB-LCNT !" in gap_storage
    assert "_TXTA-SEM-ACTUAL-ROWS @ _TXTA-SEM-GB-LCNT @ <>" in gap_index
    assert "L@ 0<>" in gap_index
    assert "_TXTA-SEM-GB-PREV @ U> 0=" in gap_index
    assert "_TXTA-SEM-CONTENT-U @ U>" in gap_index
    assert "_TXTA-CONTENT-BYTE@ 10 <>" in gap_index
    assert scan.index("_TXTA-SEM-GB-INDEX?") > scan.index("GB-POST")
    assert "_TXTA-SEM-SOURCE-OVERLAP? 0=" in query
    assert capture.count("_TXTA-SEM-SOURCE-OVERLAP?") == 2
    assert capture.count("USCOL-STORAGE-DISJOINT?") == 2


def test_textarea_semantic_provider_storage_is_conservatively_owned():
    source = TEXTAREA.read_text()

    assert "CREATE _TXTA-OWNED-START" in source
    assert "CREATE _TXTA-OWNED-END" in source
    assert "_TXTA-OWNED-END _TXTA-OWNED-LIMIT !" in source
    assert source.index("CREATE _TXTA-OWNED-START") < source.index(
        "VARIABLE _TXTA-SEM-ROOT-KEY"
    ) < source.index("CREATE _TXTA-OWNED-END")
    assert "TXTA-TEXT-AREA-STORAGE-DISJOINT?" in source.split(
        "11. Guard", 1
    )[1]


def test_semantic_capture_is_in_the_optional_textarea_guard_surface():
    source = TEXTAREA.read_text()
    guard = source.split("11. Guard", 1)[1]

    assert "' TXTA-TEXT-AREA-CAPTURE" in guard
    assert "' TXTA-TEXT-AREA-MEASURE" in guard
    assert "' TXTA-TEXT-AREA-STORAGE-DISJOINT?" in guard
    assert "_txta-text-area-capture-xt _txta-guard WITH-GUARD" in guard
    assert "_txta-text-area-measure-xt _txta-guard WITH-GUARD" in guard
    assert "_txta-text-area-storage-disjoint-q-xt" in guard
