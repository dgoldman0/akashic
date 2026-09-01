#!/usr/bin/env python3
"""Seconds-scale architecture checks for canonical TABSET semantics."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TABS = ROOT / "akashic" / "tui" / "widgets" / "tabs.f"


def _word(source: str, name: str) -> str:
    source = _executable(source)
    match = re.search(rf"(?ms)^:\s+{re.escape(name)}(?=\s).*?;", source)
    assert match, f"missing Forth word {name}"
    return match.group(0)


def _executable(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def test_tabs_are_a_lifetime_identified_caller_sized_collection_source() -> None:
    source = TABS.read_text(encoding="utf-8")

    assert "REQUIRE ../semantic-collections.f" in source
    assert "REQUIRE ../../utils/memory-span.f" in source
    assert "80 CONSTANT _TAB-O-INSTANCE" in source
    assert "88 CONSTANT _TAB-O-NEXT-KEY" in source
    assert "96 CONSTANT _TAB-O-ENTRY-BYTES" in source
    assert "104 CONSTANT _TAB-DESC-SIZE" in source
    assert "24 CONSTANT _TAB-E-KEY" in source
    assert "32 CONSTANT _TAB-ENTRY-SIZE" in source

    constructor = _word(source, "TAB-NEW-CAP")
    assert "_TAB-CAPACITY-BYTES?" in constructor
    assert "_TAB-NC-CAP @" in constructor
    assert "_TAB-O-ENTRY-BYTES" in constructor
    assert "_TAB-CLAIM-INSTANCE" in constructor
    assert "_TAB-MAX-DEFAULT" not in constructor

    capture = _word(source, "TAB-TABSET-CAPTURE")
    assert "_TAB-O-COUNT" in capture
    assert "_TAB-O-MAX" not in capture
    assert "_TAB-MAX-DEFAULT" not in capture


def test_tab_keys_are_stable_entry_identity_not_labels_or_array_positions() -> None:
    source = TABS.read_text(encoding="utf-8")
    add = _word(source, "TAB-ADD")
    remove = _word(source, "TAB-REMOVE")
    relabel = _word(source, "TAB-LABEL!")
    key_at = _word(source, "TAB-KEY@")

    assert "_TAB-CLAIM-KEY" in add
    assert "_TAB-E-KEY" in add
    assert "_TAB-ENTRY-SIZE *" in remove
    assert "CMOVE" in remove
    assert "_TAB-E-KEY" not in relabel
    assert "_TAB-E-KEY + @" in key_at
    assert "LABEL" not in key_at


def test_tabset_measure_and_capture_share_one_neutral_bounded_build_path() -> None:
    source = TABS.read_text(encoding="utf-8")
    section = source.split("7. Renderer-neutral TABSET observation", 1)[1].split(
        "8. Guard", 1
    )[0]
    executable = _executable(section)
    capture = _word(source, "TAB-TABSET-CAPTURE")
    measure = _word(source, "TAB-TABSET-MEASURE")

    assert "0 0" in measure
    assert "TAB-TABSET-CAPTURE" in measure
    assert "USCOL-BUILDER-INIT" in capture
    assert "USCOL-TABSET-BEGIN" in capture
    assert "USCOL-TAB" in capture
    assert "USCOL-TABSET-END" in capture
    assert "USCOL-BUILDER-FINISH" in capture
    assert "_TAB-E-KEY" in capture
    assert "_TAB-E-LABEL-A" in capture
    assert "_TAB-E-LABEL-U" in capture
    assert "0 0 _TAB-C-BUILDER @ USCOL-TAB" in capture

    for forbidden in (
        "rich-terminal/",
        "uidl-tui",
        "applets/",
        "Pad",
        "ALLOCATE",
        "FREE",
        "_TAB-MAX-DEFAULT",
    ):
        assert forbidden not in executable


def test_tabset_claims_only_the_complete_ordinary_header_paint() -> None:
    source = TABS.read_text(encoding="utf-8")
    capture = _word(source, "TAB-TABSET-CAPTURE")
    draw = _word(source, "_TAB-DRAW")
    columns = _word(source, "_TAB-COL-ACC")

    assert "RGN-H DUP 0> 0=" in capture
    assert "2 MIN _TAB-C-ROOT-H !" in capture
    assert "_TAB-C-ROOT @ 0 0 _TAB-C-ROOT-H @" in capture
    assert "RGN-W" in capture
    assert "_TAB-E-CONTENT-RGN" not in capture

    assert "DRW-HLINE" in draw
    assert "RGN-H 1 >" in draw
    assert "_TAB-E-LABEL-U + @ + 2 +" in columns
    assert "0x2502" not in draw


def test_tabs_expose_complete_module_and_live_source_storage_boundaries() -> None:
    source = TABS.read_text(encoding="utf-8")
    module = _word(source, "TAB-STORAGE-DISJOINT?")
    live = _word(source, "TAB-TABSET-STORAGE-DISJOINT?")
    capture = _word(source, "TAB-TABSET-CAPTURE")
    guard = source.split("8. Guard", 1)[1]

    assert "CREATE _TAB-OWNED-START" in source
    assert "CREATE _TAB-OWNED-END" in source
    assert "_TAB-OWNED-END _TAB-OWNED-LIMIT !" in source
    assert "MSPAN-NONWRAPPING?" in module
    assert "MSPAN-OVERLAP? 0=" in module
    assert "TAB-STORAGE-DISJOINT?" in live
    for source_span in (
        "_TAB-DESC-SIZE",
        "RGN-SIZE",
        "_TAB-O-ENTRY-BYTES",
        "_TAB-E-LABEL-A",
        "_TAB-E-LABEL-U",
        "_TAB-E-CONTENT-RGN",
    ):
        assert source_span in live
    assert capture.count("TAB-STORAGE-DISJOINT?") == 2
    assert "TAB-TABSET-STORAGE-DISJOINT?" in capture + _word(
        source, "_TAB-CAPTURE-PREFLIGHT?"
    )
    assert "' TAB-STORAGE-DISJOINT?" not in guard
    assert "' TAB-TABSET-STORAGE-DISJOINT?" in guard


def test_keyboard_and_public_selection_share_callback_semantics() -> None:
    source = TABS.read_text(encoding="utf-8")
    transition = _word(source, "_TAB-SELECT!")
    handle = _word(source, "_TAB-HANDLE")
    hit = _word(source, "TAB-HIT-INDEX")
    public = _word(source, "TAB-SELECT")

    assert "_TAB-O-ACTIVE" in transition
    assert "_TAB-O-SWITCH-XT" in transition
    assert "EXECUTE" in transition
    assert handle.count("_TAB-SELECT!") == 3
    assert "KEY-T-MOUSE" in handle
    assert "KEY-MOUSE-LEFT" in handle
    assert "TAB-HIT-INDEX" in handle
    assert "RGN-ROW" in hit
    assert "RGN-COL" in hit
    assert "_TAB-E-LABEL-U" in hit
    assert "1 _TAB-HIT-POS !" in hit
    assert "2 + _TAB-HIT-SPAN !" in hit
    assert "_TAB-SELECT!" in public
