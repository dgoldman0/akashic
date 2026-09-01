#!/usr/bin/env python3
"""Seconds-scale architecture checks for canonical TABSET semantics."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TABS = ROOT / "akashic" / "tui" / "widgets" / "tabs.f"
PAD = ROOT / "akashic" / "tui" / "applets" / "pad" / "pad.f"


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


def test_pad_uses_one_caller_bounded_canonical_tab_widget() -> None:
    source = PAD.read_text(encoding="utf-8")
    executable = _executable(source)
    init = _word(source, "PAD-INIT-CB")

    assert "REQUIRE ../../widgets/tabs.f" in source
    assert "_PAD-FNAME-CAP 1+ CONSTANT _PAD-TAB-LABEL-CAP" in source
    assert "_PAD-MAX-BUFS CELLS CMP-FIELD: _PAD-TAB-SLOTS" in source
    assert "CMP-FIELD: _PAD-TAB-LABELS" in source
    assert "_PAD-PANEL WDG-REGION _PAD-MAX-BUFS TAB-NEW-CAP" in init
    assert "TAB-NEW" not in init.replace("TAB-NEW-CAP", "")

    for forbidden in (
        "rich-terminal/",
        "RTE-",
        "RUHA-",
        "STX1",
        "scene",
        "provider",
    ):
        assert forbidden not in executable


def test_pad_keeps_dense_visual_order_separate_from_sparse_editor_slots() -> None:
    source = PAD.read_text(encoding="utf-8")
    add = _word(source, "_PAD-TAB-ADD-SLOT")
    remove = _word(source, "_PAD-TAB-REMOVE-SLOT")
    post_close = _word(source, "_PAD-POST-CLOSE-ACTIVE")
    open_buffer = _word(source, "_PAD-BUF-OPEN")
    close_buffer = _word(source, "_PAD-BUF-CLOSE")
    switch_buffer = _word(source, "_PAD-BUF-SWITCH")
    switched = _word(source, "_PAD-ON-TAB-SWITCH")
    next_tab = _word(source, "_PAD-NEXT-ACTIVE")
    previous_tab = _word(source, "_PAD-PREV-ACTIVE")

    assert "TAB-COUNT _PDT-ORD !" in add
    assert "TAB-ADD" in add
    assert "_PAD-TAB-SLOT!" in add
    assert "TAB-REMOVE" in remove
    assert "I 1+ _PAD-TAB-SLOT@ I _PAD-TAB-SLOT!" in remove
    assert "TAB-ACTIVE _PAD-TAB-SLOT@" in post_close
    assert post_close.index("_PAD-TABS @ ?DUP IF") < post_close.index(
        "_PAD-MAX-BUFS 0 DO"
    )
    assert "_PAD-TAB-ADD-SLOT" in open_buffer
    assert "_PAD-TAB-SELECT-SLOT" in open_buffer
    assert "_PAD-TAB-REMOVE-SLOT" in close_buffer
    assert "_PAD-POST-CLOSE-ACTIVE" in close_buffer
    assert "_PAD-MAX-BUFS 0 DO" not in close_buffer
    assert "_PAD-TAB-SELECT-SLOT" in close_buffer
    assert "_PAD-TAB-SELECT-SLOT" in switch_buffer
    assert "_PAD-TAB-SLOT@" in switched
    assert "_PAD-BUF-SWITCH" in switched
    assert "TAB-ACTIVE 1+" in next_tab
    assert "_PAD-TAB-SLOT@" in next_tab
    assert "TAB-ACTIVE" in previous_tab
    assert "_PAD-TAB-SLOT@" in previous_tab


def test_pad_labels_are_stable_current_and_owned_by_pad() -> None:
    source = PAD.read_text(encoding="utf-8")
    desired = _word(source, "_PAD-TAB-WANTED")
    sync_one = _word(source, "_PAD-TAB-LABEL-SYNC")
    sync_all = _word(source, "_PAD-TAB-LABELS-SYNC")
    draw_tabs = _word(source, "_PAD-DRAW-TAB-WIDGET")

    assert "_PAD-TAB-LABELS +" in _word(source, "_PAD-TAB-LABEL")
    assert "_PBE-DIRTY" in desired
    assert "[CHAR] *" in desired
    assert "TAB-LABEL@" in sync_one
    assert "COMPARE 0=" in sync_one
    assert "TAB-LABEL!" in sync_one
    assert "TAB-COUNT 0 ?DO" in sync_all
    assert "_PAD-TAB-SLOT@ _PAD-TAB-LABEL-SYNC" in sync_all
    assert draw_tabs.index("_PAD-TAB-LABELS-SYNC") < draw_tabs.index("WDG-DRAW")


def test_pad_routes_canonical_mouse_hits_without_stealing_editor_keys() -> None:
    source = PAD.read_text(encoding="utf-8")
    draw_panel = _word(source, "_PAD-PANEL-DRAW")
    handle_panel = _word(source, "_PAD-PANEL-HANDLE")
    paint = _word(source, "PAD-PAINT-CB")
    remove = _word(source, "_PAD-TAB-REMOVE-SLOT")
    free_tabs = _word(source, "_PAD-TABS-FREE")

    assert "_PAD-DRAW-TAB-WIDGET" in draw_panel
    assert "_PAD-TXTA @ ?DUP IF WDG-DRAW" in draw_panel
    assert handle_panel.index("KEY-T-MOUSE") < handle_panel.index(
        "_PAD-TABS @ WDG-HANDLE"
    )
    assert handle_panel.index("_PAD-TABS @ WDG-HANDLE") < handle_panel.index(
        "_PAD-TXTA @ ?DUP"
    )
    for editor_key in ("KEY-LEFT", "KEY-RIGHT", "KEY-T-CHAR"):
        assert editor_key not in handle_panel
    assert "_PAD-TABS @ ?DUP IF WDG-DIRTY? OR THEN" in paint
    assert "_PAD-DRAW-TABS" not in _executable(source)
    assert "TAB-CONTENT _PDT-RGN !" in remove
    assert "_PDT-RGN @ ?DUP IF RGN-FREE" in remove
    assert "TAB-COUNT 0 ?DO" in free_tabs
    assert "TAB-CONTENT ?DUP IF RGN-FREE" in free_tabs
    assert "TAB-FREE" in free_tabs
    assert "_PAD-TABS-FREE" in _word(source, "PAD-SHUTDOWN-CB")
