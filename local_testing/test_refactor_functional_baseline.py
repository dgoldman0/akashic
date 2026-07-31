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
        "behavior_groups": 32,
        "fully_covered_groups": 19,
        "partial_groups": 11,
        "prerequisite_only_groups": 2,
        "prerequisites": 13,
        "evidence_references": 128,
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
    prerelease_groups = {
        "streams.views-drafts-and-actions",
        "streams.observation-truth-and-recovery",
        "streams.desk-manual-refresh",
    }
    assert all(
        behaviors[behavior_id]["prerequisite_ids"]
        == ["streams.prerelease-replacement"]
        for behavior_id in prerelease_groups
    )
    assert streams["prerequisites"] == [
        {
            "id": "streams.prerelease-replacement",
            "before_landing": "SR6",
            "trigger": (
                "A replacement milestone touches or displaces any listed "
                "current "
                "Streams source, observation, draft, rendering or "
                "manual-refresh behavior."
            ),
            "characterization": (
                "Add only the focused evidence needed for a still-live branch "
                "or record an explicit deletion or user-data export decision; "
                "fixtures alone create no preservation duty and the halted L13 "
                "authority cutover and its gates are not required."
            ),
            "reason": (
                "Preserve exact user-created data and only the live behavior "
                "temporarily required to reach a qualified replacement; "
                "otherwise delete displaced prerelease paths instead of "
                "maintaining parallel implementations."
            ),
        }
    ]

    sr2_runtime = behaviors["streams.sr2-storage-free-runtime"]
    assert sr2_runtime["coverage"] == "covered"
    assert sr2_runtime["evidence"] == [
        "driver:local_testing/test_streams_sr2_runtime.py",
        (
            "pytest:local_testing/test_streams_sr2_static.py::"
            "test_streams_sr2_runtime_dependency_closure_is_storage_free"
        ),
    ]
    assert "prerequisite_ids" not in sr2_runtime

    sr2_http = behaviors["streams.sr2-cooperative-http"]
    assert sr2_http["coverage"] == "covered"
    assert sr2_http["evidence"] == [
        "driver:local_testing/test_web_http_primitives.py",
        "driver:local_testing/test_streams_sr2_http_route.py",
        "driver:local_testing/test_streams_sr2_http_pressure.py",
    ]
    assert "prerequisite_ids" not in sr2_http

    sr3_durability = behaviors["streams.sr3-operational-durability"]
    assert sr3_durability["coverage"] == "covered"
    assert sr3_durability["facets"] == [
        "interfaces",
        "persistence",
        "failures",
        "journeys",
    ]
    assert sr3_durability["evidence"] == [
        "driver:local_testing/test_streams_sr3_config_records.py",
        "driver:local_testing/test_streams_sr3_records.py",
        "driver:local_testing/test_streams_sr3_admission.py",
        "driver:local_testing/test_streams_sr3_delivery.py",
        "driver:local_testing/test_streams_sr3_composed.py",
        (
            "pytest:local_testing/test_streams_sr3_static.py::"
            "test_streams_sr3_compaction_closure_is_neutral_and_current_only"
        ),
    ]
    assert "prerequisite_ids" not in sr3_durability


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
