"""Landing L0 architecture, ownership, capacity, and scale ratchets."""

from __future__ import annotations

import json
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import (
    MODULE_KEY_BYTES,
    PROVIDED_RE,
    REQUIRE_RE,
    dependency_markers,
    module_key,
    normalize_module,
)
from refactor_inventory import (
    SOURCE_ROOT,
    _lexical_definitions,
    build_report,
    check_report,
    classify_module,
    load_policy,
)

def _policy() -> dict:
    return load_policy()


def _report() -> dict:
    return build_report(_policy())


def test_shared_dependency_grammar_matches_kdos_ascii_space_rules() -> None:
    assert REQUIRE_RE.match("REQUIRE module.f")
    assert PROVIDED_RE.match("PROVIDED module-id")
    assert REQUIRE_RE.match("REQUIRE\tmodule.f") is None
    assert PROVIDED_RE.match("PROVIDED\tmodule-id") is None
    assert normalize_module("../math/sha3.f", "library/model.f") == (
        "math/sha3.f"
    )
    markers = dependency_markers(
        "REQUIRE ../math/sha3.f\nREQUIRE model.f\n", "library/store.f"
    )
    assert [(marker.raw, marker.normalized, marker.line) for marker in markers] == [
        ("../math/sha3.f", "math/sha3.f", 1),
        ("model.f", "library/model.f", 2),
    ]
    assert len(module_key("x")) == MODULE_KEY_BYTES


def test_packaging_harness_uses_the_shared_dependency_core() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")
    assert "from forth_dependencies import (" in harness
    assert "return _shared_dependency_closure(SOURCE_ROOT, roots)" in harness
    assert "return _shared_dependency_order(SOURCE_ROOT, roots)" in harness
    assert "return _shared_normalize_module(module, requiring)" in harness
    assert "key = module_key(module_id)" in harness


def test_lexical_inventory_finds_all_top_level_definitions_only() -> None:
    definitions = _lexical_definitions(
        "VARIABLE first VARIABLE second\n"
        "17 VALUE selected\n"
        ": factory CREATE 8 ALLOT ;\n"
        "' VARIABLE CONSTANT variable-xt\n"
        "( VARIABLE commented ) GUARD lock\n"
        'S" VALUE not-a-definition (with \\x48)" DEFER callback\n'
        "[CHAR] ( CONSTANT open-paren VARIABLE after-char\n"
        "\\comment VARIABLE hidden-by-line-comment\n"
        ".( VARIABLE hidden-by-dot-paren )\n"
        "[DEFINED] VARIABLE [IF]\n"
    )
    assert definitions == {
        "create": [],
        "variable": ["first", "second", "after-char"],
        "value": ["selected"],
        "defer": ["callback"],
        "xbuf": [],
        "guard": ["lock"],
        "constant": ["variable-xt", "open-paren"],
    }


def test_live_graph_matches_the_reviewed_l0_ratchet() -> None:
    policy = _policy()
    report = build_report(policy)
    assert check_report(report, policy) == []
    expected_summary = {
        "module_count": 380,
        "resolved_require_occurrence_count": 1284,
        "unique_resolved_edge_count": 1283,
        "unresolved_require_count": 78,
        "cycle_count": 0,
        "layer_violation_count": 7,
        "placement_debt_count": 40,
        "provided_issue_count": 2,
        "addressability_issue_count": 1,
        "marker_issue_count": 0,
    }
    assert {
        key: report["summary"][key] for key in expected_summary
    } == expected_summary
    json.dumps(report, sort_keys=True)


def test_unresolved_imports_are_named_debt_not_external_dependencies() -> None:
    report = _report()
    assert len(report["unresolved_requires"]) == 78
    assert {entry["from"].split("/", 1)[0] for entry in report[
        "unresolved_requires"
    ]} == {"audio", "store"}
    assert all(entry["raw"] != entry["to"] for entry in report[
        "unresolved_requires"
    ])
    assert "external_edges" not in report


def test_every_module_has_a_settled_responsibility_class() -> None:
    report = _report()
    assert all(
        module["class"] in {"independent", "desk-ecosystem", "applet"}
        for module in report["modules"]
    )
    by_path = {module["path"]: module for module in report["modules"]}
    assert by_path["library/model.f"]["class"] == "applet"
    assert by_path["library/model.f"]["owner"] == "library"
    assert by_path["daybook/shared-document.f"]["class"] == "applet"
    assert by_path["agent/runtime.f"]["class"] == "applet"
    assert by_path["agent/runtime.f"]["owner"] == "agent"
    assert by_path["agent/runtime.f"]["target"] == (
        "tui/applets/agent/runtime.f"
    )
    assert by_path["agent/access-profile.f"]["placement"] == "split-required"
    assert by_path["agent/access-profile.f"]["split_targets"] == [
        "tui/applets/agent/access-profile.f",
        "tui/applets/desk/agent-access-policy.f",
    ]
    assert by_path["interop/shared-document-lens.f"]["class"] == (
        "desk-ecosystem"
    )
    assert by_path["tui/applets/streams/observation-state.f"]["class"] == (
        "applet"
    )
    assert classify_module("new-product/widget.f", _policy())["class"] == (
        "unclassified"
    )


def test_current_layer_and_addressability_debt_is_exact() -> None:
    report = _report()
    assert report["layer_violations"] == [
        {
            "rule": "applet-imports-sibling",
            "from": "tui/applets/desk/desk.f",
            "to": "agent/access-profile.f",
        },
        {
            "rule": "applet-imports-sibling",
            "from": "tui/applets/desk/desk.f",
            "to": "agent/mandate-run.f",
        },
        {
            "rule": "applet-imports-sibling",
            "from": "tui/applets/desk/desk.f",
            "to": "agent/providers/offline.f",
        },
        {
            "rule": "applet-imports-sibling",
            "from": "tui/applets/desk/desk.f",
            "to": "agent/runtime.f",
        },
        {
            "rule": "applet-imports-sibling",
            "from": "tui/applets/desk/desk.f",
            "to": "agent/storage/vfs-conversation.f",
        },
        {
            "rule": "applet-imports-sibling",
            "from": "tui/applets/desk/desk.f",
            "to": "daybook/shared-document.f",
        },
        {
            "rule": "shared-host-hardcodes-vfs-driver",
            "from": "tui/app-shell.f",
            "to": "utils/fs/drivers/vfs-mp64fs.f",
        },
    ]
    assert report["addressability_issues"] == [
        {
            "kind": "whitespace-in-module-path",
            "module": "tui/applets/fexplorer/fexplorer copy.f",
        }
    ]
    assert {issue["kind"] for issue in report["provided_issues"]} == {
        "duplicate-provided-identity",
        "bounded-provided-key-collision",
    }


def test_capacity_ledger_is_live_and_distinguishes_scope() -> None:
    report = _report()
    capacities = report["capacities"]
    assert capacities
    assert all(capacity["matches"] for capacity in capacities)
    assert {capacity["scope"] for capacity in capacities} >= {
        "aggregate-corpus",
        "whole-corpus-buffer",
        "whole-document-buffer",
        "working-set",
        "queue",
        "instance-pool",
    }
    assert {capacity["scale_axis"] for capacity in capacities} >= {
        "primary-record-cardinality",
        "relationship-cardinality",
        "model-complexity",
        "content-bytes",
        "simultaneous-instances",
        "work-scheduling",
    }


def test_structure_and_complexity_ledger_is_source_anchored() -> None:
    report = _report()
    ledger = report["complexity_ledger"]
    assert len(ledger) >= 12
    assert all(item["matches"] for item in ledger)
    assert all(item["evidence_symbols"] for item in ledger)
    assert {item["id"].split(".", 1)[0] for item in ledger} >= {
        "library",
        "streams",
        "agent",
        "daybook",
        "pad",
        "fexplorer",
        "grid",
        "desk",
        "runtime",
        "interop",
        "uidl",
    }
    assert all("O(" in item["current_complexity"] for item in ledger)


def test_scale_profiles_and_measurement_gaps_are_explicit() -> None:
    policy = _policy()
    assert policy["filesystem"] == {
        "required_abstraction": "akashic/utils/fs/vfs.f",
        "ext4_prerequisite": False,
        "note": "Scale and architecture qualification use the generic VFS contract; ext4 is an optional integration backend.",
    }
    assert policy["scale_profiles"]["workstation"]["primary_records"] == 100000
    assert policy["scale_profiles"]["large_host_model"] == {
        "primary_records": 1000000,
        "revisions": 10000000,
        "relationship_edges": 10000000,
        "purpose": "prove index geometry, amplification, and bounded working memory without aggregate target allocation",
    }
    assert {
        workload["id"]
        for workload in policy["scale_profiles"]["query_workloads"]
    } == {
        "point-lookup",
        "ordered-and-compound-range",
        "relationship-neighborhood",
        "text-candidate-plus-exact",
        "deep-keyset-pagination",
    }
    assert policy["scale_profiles"]["instance_workload"] == {
        "same_type_applets": 2,
        "interleaved_stores": 4,
        "interleaved_request_buses": 4,
        "interleaved_long_jobs": 4,
        "hidden_process_global_current_instance": False,
    }
    assert "high-degree" in policy["scale_profiles"]["model_workload"][
        "relationship_distribution"
    ]
    baseline = policy["hot_path_baseline"]
    assert "PERF-CYCLES" in baseline["existing_guest_counters"]
    assert "allocation event count" in baseline["missing_instrumentation"]
    assert "logical persistence page reads and writes" in baseline[
        "missing_instrumentation"
    ]
    assert "not an allocation counter" in baseline["clarification"]
    assert "must not be relabelled" in baseline["clarification"]
    coverage = {entry["area"]: entry["status"] for entry in baseline["coverage"]}
    assert coverage == {
        "Library": "measured",
        "Streams": "functional-and-capacity-only",
        "Agent": "functional-and-capacity-only",
        "Daybook/Pad/Grid/FExplorer": "functional-and-capacity-only",
        "Desk/TUI": "journey-only",
    }


def test_live_module_inventory_includes_exact_mutable_symbols() -> None:
    report = _report()
    by_path = {module["path"]: module for module in report["modules"]}
    store = by_path["library/vfs-store.f"]["lexical_definitions"]
    assert "_library-vfs-store-guard" in store["guard"]
    assert "_LIBVP-FRAME" in store["create"]
    assert "_LIBVP-CATALOG-FACTS" in store["create"]
    bus = by_path["interop/request-bus.f"]["lexical_definitions"]
    assert "_CBUS-DISPATCH-DEPTH" in bus["variable"]
    assert "_CBUS-OWNER-OP-DEPTH" in bus["variable"]


def test_all_capacity_sources_are_production_modules() -> None:
    for capacity in _policy()["capacities"]:
        path = SOURCE_ROOT / capacity["module"]
        assert path.is_file(), capacity
        assert path.suffix == ".f"
