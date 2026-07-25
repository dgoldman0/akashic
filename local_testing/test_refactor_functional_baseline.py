"""Landing L1 functional-preservation ledger ratchets."""

from __future__ import annotations

import copy
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from refactor_functional_baseline import (
    _defined_profile_names,
    _forth_strings,
    check_ledger,
    load_ledger,
    summary,
)


def test_live_functional_ledger_is_complete_and_source_anchored() -> None:
    ledger = load_ledger()
    assert check_ledger(ledger) == []
    assert summary(ledger) == {
        "applets": 9,
        "behavior_groups": 30,
        "fully_covered_groups": 17,
        "partial_groups": 11,
        "prerequisite_only_groups": 2,
        "prerequisites": 13,
        "evidence_references": 115,
    }


def test_streams_reset_replaces_cancelled_l13_gates() -> None:
    ledger = load_ledger()
    applets = {applet["id"]: applet for applet in ledger["applets"]}
    library = applets["library"]
    streams = applets["streams"]

    assert "L13" not in library["active_landings"]
    assert streams["active_landings"] == [
        "L2",
        "L3",
        "L4",
        "L9",
        "SR1",
        "SR2",
        "SR3",
        "SR4",
        "SR5",
        "SR6",
    ]

    behaviors = {
        behavior["id"]: behavior for behavior in streams["behaviors"]
    }
    compatibility_groups = {
        "streams.views-drafts-and-actions",
        "streams.observation-truth-and-recovery",
        "streams.desk-manual-refresh",
    }
    assert all(
        behaviors[behavior_id]["prerequisite_ids"]
        == ["streams.compatibility-retirement"]
        for behavior_id in compatibility_groups
    )
    assert streams["prerequisites"] == [
        {
            "id": "streams.compatibility-retirement",
            "before_landing": "SR6",
            "trigger": (
                "A replacement milestone touches or retires any listed legacy "
                "Streams source, observation, draft, rendering or "
                "manual-refresh behavior."
            ),
            "characterization": (
                "Add only the focused characterization needed for the touched "
                "compatibility branch, or record an approved explicit "
                "retirement or export decision; the halted L13 authority "
                "cutover and its gates are not required."
            ),
            "reason": (
                "Current compatibility behavior remains authoritative until "
                "replacement evidence exists, while the additive storage-free "
                "SR1 core must not be gated on the cancelled "
                "observation-repository design."
            ),
        }
    ]

    sr1 = behaviors["streams.sr1-storage-free-flow"]
    assert sr1["coverage"] == "covered"
    assert sr1["evidence"] == [
        "driver:local_testing/test_streams_sr1_core.py",
        (
            "pytest:local_testing/test_streams_sr1_static.py::"
            "test_streams_sr1_core_dependency_closure_is_storage_free"
        ),
    ]
    assert "prerequisite_ids" not in sr1


def test_partial_behavior_must_name_a_reviewable_prerequisite() -> None:
    ledger = copy.deepcopy(load_ledger())
    behavior = ledger["applets"][1]["behaviors"][0]
    assert behavior["coverage"] == "partial"
    behavior["prerequisite_ids"] = []
    errors = check_ledger(ledger)
    assert any("partial behavior lacks a prerequisite" in error for error in errors)


def test_evidence_must_resolve_to_an_exact_live_gate() -> None:
    ledger = copy.deepcopy(load_ledger())
    ledger["applets"][0]["behaviors"][0]["evidence"] = [
        "profile:not-a-real-profile"
    ]
    errors = check_ledger(ledger)
    assert any("unknown emulator profile" in error for error in errors)


def test_profile_lookup_does_not_masquerade_as_a_definition() -> None:
    source = (
        '    "literal": Profile(roots=(), resources=(), autoexec=""),\n'
        'PROFILES["assigned"] = PROFILES["literal"]\n'
        'value = PROFILES["lookup-only"]\n'
    )
    assert _defined_profile_names(source) == {"literal", "assigned"}


def test_capability_scanner_ignores_comments_and_other_string_bodies() -> None:
    source = (
        '\\ S" commented.cap"\n'
        '( S" parenthetical.cap" )\n'
        'C" S" nested.cap"\n'
        'S" live.cap" DROP\n'
    )
    assert _forth_strings(source) == ["live.cap"]


def test_uidl_surface_drift_is_detected() -> None:
    ledger = copy.deepcopy(load_ledger())
    ledger["applets"][0]["uidl_surface"]["actions"].remove("archive")
    errors = check_ledger(ledger)
    assert any("UIDL action/menu/shortcut/element surface drifted" in error for error in errors)


def test_direct_input_and_capability_set_drift_is_detected() -> None:
    ledger = copy.deepcopy(load_ledger())
    library = ledger["applets"][0]
    library["direct_input_contracts"][0]["sha256"] = "0" * 64
    streams = ledger["applets"][1]
    streams["capability_surface"]["ids"].pop()
    errors = check_ledger(ledger)
    assert any("direct-input word drifted" in error for error in errors)
    assert any("exact capability ID set drifted" in error for error in errors)
