#!/usr/bin/env python3
"""Seconds-scale architecture locks for canonical UIDL collection freezing."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/uidl-collection-snapshot.f"
DOC = ROOT / "docs/tui/uidl-collection-snapshot.md"


def _word(source: str, name: str) -> str:
    match = re.search(rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;", source)
    assert match, f"missing Forth word {name}"
    return match.group(0)


def _executable(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def test_snapshot_contract_is_pointer_free_uidl_keyed_and_renderer_neutral():
    source = SOURCE.read_text(encoding="utf-8")
    executable = _executable(source)

    assert re.findall(r"(?m)^REQUIRE (.+)$", source) == [
        "uidl-tui.f",
        "semantic-collections.f",
        "../utils/memory-span.f",
    ]
    for declaration in (
        "0 CONSTANT UCSN-S-OK",
        "1 CONSTANT UCSN-S-CAPACITY",
        "2 CONSTANT UCSN-S-UNAVAILABLE",
        "3 CONSTANT UCSN-S-INVALID",
        "1 CONSTANT UCSN-SOURCE-UIDL",
        "112 CONSTANT UCSN-DESCRIPTOR-SIZE",
        "16 CONSTANT UCSN-WORK-SOURCE-ENTRY-SIZE",
        "112 CONSTANT UCSN-WORK-NODE-SIZE",
    ):
        assert declaration in source
    for offset in ("8 +", "16 +", "24 +", "32 +", "40 +", "48 +", "56 +", "64 +"):
        assert offset in source.split("112 CONSTANT UCSN-DESCRIPTOR-SIZE", 1)[0]
    for forbidden in (
        "ALLOCATE",
        " FREE",
        "rich-terminal/",
        "applets/",
        "UTUI-PAINT",
        "WDG-DRAW",
        "APT-",
        "RTE-",
        "RUHA-",
        "WPTR",
    ):
        assert forbidden not in executable


def test_work_is_linear_by_source_with_dense_multi_root_runs():
    source = SOURCE.read_text(encoding="utf-8")
    sizing = _word(source, "UCSN-WORK-BYTES")
    link = _word(source, "_UCSN-V-LINK?")
    emit = _word(source, "_UCSN-EMIT-CANONICAL")
    emit_source = _word(source, "_UCSN-EMIT-SOURCE")

    assert "element-high-water descriptor-capacity" in sizing
    assert "UCSN-WORK-SOURCE-ENTRY-SIZE" in sizing
    assert "UCSN-WORK-NODE-SIZE" in sizing
    assert "_UCSN-WS.FIRST" in link
    assert "_UCSN-WS.COUNT" in link
    assert "UCSN-DESCRIPTOR-ROOT-KEY@ U< 0=" in link
    assert "_UCSN-WORK-SOURCE-CAP @ U<" in emit
    assert "_UCSN-E-RUN-COUNT" in emit_source
    assert "_UCSN-WORK-NODE-AT" in emit_source
    for forbidden in ("SORT", "HEAP", "_UCSN-KEY<", "_UCSN-SWAP"):
        assert forbidden not in _executable(source).upper()


def test_one_observation_measures_copies_validates_and_freezes_once():
    source = SOURCE.read_text(encoding="utf-8")
    executable = _executable(source)
    visitor = _word(source, "_UCSN-TREE-VISITOR")
    capture = _word(source, "_UCSN-V-CAPTURE")
    validate = _word(source, "_UCSN-V-VALIDATE?")
    body = _word(source, "_UCSN-CAPTURE-BODY")
    call = _word(source, "_UCSN-CAPTURE-CALL")

    assert executable.count("UTUI-RESOLVED-TREE-EACH") == 1
    assert executable.count("USCOL-ENTRY-VALIDATE") == 1
    assert capture.count(
        "_UTUI-VISITED-COLLECTION-CAPTURE-PREFLIGHTED"
    ) == 2
    assert "UTUI-VISITED-COLLECTION-STORAGE-DISJOINT?" in visitor + _word(
        source, "_UCSN-V-PROBE?"
    )
    assert "_UCSN-V-ROOT-FIT?" in validate
    assert body.index("UTUI-RESOLVED-TREE-EACH") < body.index(
        "_UCSN-EMIT-CANONICAL"
    )
    assert "UTUI-RESOLVED-OBSERVE" in call
    assert "CATCH" in _word(source, "_UCSN-CAPTURE-OBSERVED-CATCH")
    assert "CATCH" in _word(source, "UCSN-CAPTURE")


def test_all_caller_banks_are_preflighted_before_any_scratch_clear():
    source = SOURCE.read_text(encoding="utf-8")
    authority = _word(source, "_UCSN-AUTHORITY-DISJOINT?")
    ranges = _word(source, "_UCSN-RANGES?")
    observed = _word(source, "_UCSN-CAPTURE-OBSERVED")

    for check in (
        "_UCSN-OWNED-DISJOINT?",
        "USCOL-STORAGE-DISJOINT?",
        "_UTUI-STORAGE-DISJOINT-BODY?",
        "_UTUI-CS-OBSERVED?",
    ):
        assert check in authority
    assert " UTUI-STORAGE-DISJOINT?" not in authority
    assert " UTUI-COLLECTION-STORAGE-DISJOINT?" not in authority
    for bank in (
        "_UCSN-BUILDER",
        "_UCSN-VALIDATION-A",
        "_UCSN-WORK-A",
        "_UCSN-DESCRIPTORS-A",
        "_UCSN-NATIVE-A",
    ):
        assert bank in ranges
    assert ranges.count("_UCSN-DISJOINT?") == 10
    assert observed.index("_UCSN-RANGES?") < observed.index(
        "_UCSN-WORK-LAYOUT?"
    )
    assert "_UCSN-CLEAR-SCRATCH" not in observed


def test_document_marks_direct_textarea_as_a_slice_not_pad_completion():
    doc = " ".join(DOC.read_text(encoding="utf-8").lower().split())

    for phrase in (
        "screen-absolute uidl-tui coordinates",
        "one source may own multiple roots",
        "does not capture pad's nested main editor",
        "generic mounted/draw-boundary composition",
        "no applet callback",
    ):
        assert phrase in doc
