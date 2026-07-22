"""Landing L0 architecture, ownership, capacity, and scale ratchets."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
if str(LOCAL_TESTING) not in sys.path:
    sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import (
    MODULE_KEY_BYTES,
    PROVIDED_RE,
    REQUIRE_RE,
    dependency_closure,
    dependency_markers,
    module_key,
    normalize_module,
)
from refactor_inventory import (
    SOURCE_ROOT,
    _dependency_violation,
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
    assert normalize_module(
        "../../../math/sha3.f", "tui/applets/library/model.f"
    ) == (
        "math/sha3.f"
    )
    markers = dependency_markers(
        "REQUIRE ../../../math/sha3.f\nREQUIRE model.f\n",
        "tui/applets/library/store.f",
    )
    assert [(marker.raw, marker.normalized, marker.line) for marker in markers] == [
        ("../../../math/sha3.f", "math/sha3.f", 1),
        ("model.f", "tui/applets/library/model.f", 2),
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
        "module_count": 400,
        "resolved_require_occurrence_count": 1335,
        "unique_resolved_edge_count": 1335,
        "unresolved_require_count": 78,
        "cycle_count": 0,
        "layer_violation_count": 0,
        "placement_debt_count": 0,
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


def test_every_module_has_a_reviewed_responsibility_class() -> None:
    report = _report()
    assert report["placement_debt"] == []
    assert all(
        module["class"] in {"independent", "desk-ecosystem", "applet"}
        for module in report["modules"]
    )
    by_path = {module["path"]: module for module in report["modules"]}
    library_modules = {
        module["path"]: module
        for module in report["modules"]
        if module["path"].startswith("tui/applets/library/")
    }
    assert {path.rsplit("/", 1)[-1] for path in library_modules} == {
        "controller.f",
        "library.f",
        "model.f",
        "persistence-adapter.f",
        "projection-adapter.f",
        "query.f",
        "record-codec.f",
        "repository.f",
        "service.f",
        "store-format.f",
        "view.f",
    }
    assert all(
        module["class"] == "applet"
        for module in library_modules.values()
    )
    assert all(
        module["owner"] == "library"
        for module in library_modules.values()
    )
    assert all(
        module["placement"] == "correct"
        for module in library_modules.values()
    )
    assert all(
        rule["prefix"] != "library/"
        for rule in _policy()["ownership"]["prefixes"]
    )
    assert by_path["tui/applets/daybook/shared-document.f"]["class"] == (
        "applet"
    )
    assert by_path["tui/applets/agent/runtime.f"]["class"] == "applet"
    assert by_path["tui/applets/agent/runtime.f"]["owner"] == "agent"
    assert by_path["tui/applets/agent/runtime.f"]["placement"] == "correct"
    assert by_path["tui/applets/agent/access-profile.f"]["owner"] == "agent"
    assert by_path["tui/applets/agent/access-profile.f"]["placement"] == (
        "correct"
    )
    assert by_path["tui/applets/agent/service.f"]["owner"] == "agent"
    assert by_path["tui/applets/desk/agent-access-policy.f"]["owner"] == (
        "desk"
    )
    assert by_path["interop/resource-owner-pool.f"]["class"] == "independent"
    assert by_path["interop/resource-owner-pool.f"]["placement"] == "correct"
    assert by_path["interop/resource-session.f"]["class"] == "independent"
    assert by_path["interop/resource-session.f"]["placement"] == "correct"
    assert by_path["game/ecs.f"]["class"] == "independent"
    assert by_path["tui/game/game-applet.f"]["class"] == "desk-ecosystem"
    assert by_path["game/ecs.f"]["ownership_decision"] == (
        "deferred-current-placement"
    )
    assert by_path["tui/game/game-applet.f"]["ownership_decision"] == (
        "deferred-current-placement"
    )
    assert by_path["game/ecs.f"]["target"] == "game/ecs.f"
    assert by_path["tui/game/game-applet.f"]["target"] == (
        "tui/game/game-applet.f"
    )
    assert by_path["tui/applets/streams/observation-state.f"]["class"] == (
        "applet"
    )
    assert classify_module("new-product/widget.f", _policy())["class"] == (
        "unclassified"
    )


def test_public_applet_seams_are_exact_and_private_imports_still_fail() -> None:
    policy = _policy()
    assert policy["public_applet_seams"] == [
        {
            "from": "tui/applets/desk/agent-access-policy.f",
            "to": "tui/applets/agent/service.f",
            "purpose": (
                "Desk-owned access policy composes the public Agent service "
                "without importing Agent internals."
            ),
        },
        {
            "from": "tui/applets/desk/desk.f",
            "to": "tui/applets/daybook/shared-document.f",
            "purpose": (
                "Desk product composition borrows Daybook's public "
                "resource-owner service."
            ),
        },
    ]
    desk_policy = classify_module(
        "tui/applets/desk/agent-access-policy.f", policy
    )
    agent_service = classify_module("tui/applets/agent/service.f", policy)
    agent_runtime = classify_module("tui/applets/agent/runtime.f", policy)
    desk = classify_module("tui/applets/desk/desk.f", policy)
    daybook_service = classify_module(
        "tui/applets/daybook/shared-document.f", policy
    )
    daybook_private = classify_module(
        "tui/applets/daybook/daybook.f", policy
    )
    assert _dependency_violation(
        "tui/applets/desk/agent-access-policy.f",
        "tui/applets/agent/service.f",
        desk_policy,
        agent_service,
        policy,
    ) is None
    assert _dependency_violation(
        "tui/applets/desk/agent-access-policy.f",
        "tui/applets/agent/runtime.f",
        desk_policy,
        agent_runtime,
        policy,
    ) == "applet-imports-sibling"
    assert _dependency_violation(
        "tui/applets/desk/desk.f",
        "tui/applets/daybook/shared-document.f",
        desk,
        daybook_service,
        policy,
    ) is None
    assert _dependency_violation(
        "tui/applets/desk/desk.f",
        "tui/applets/daybook/daybook.f",
        desk,
        daybook_private,
        policy,
    ) == "applet-imports-sibling"


def test_current_layer_and_addressability_debt_is_exact() -> None:
    report = _report()
    assert report["layer_violations"] == []
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


def test_l9_host_and_platform_dependency_boundaries_are_ratchets() -> None:
    policy = _policy()
    assert policy["dependency_constraints"] == [
        {
            "rule": "shared-host-hardcodes-vfs-driver",
            "from": "tui/app-shell.f",
            "forbid_target_prefix": "utils/fs/drivers/",
        },
        {
            "rule": "shared-applet-host-hardcodes-vfs-driver",
            "from_prefix": "tui/applet-host/",
            "forbid_target_prefix": "utils/fs/drivers/",
        },
    ]

    app_shell_closure = set(
        dependency_closure(SOURCE_ROOT, ("tui/app-shell.f",))
    )
    assert "utils/fs/vfs.f" in app_shell_closure
    assert not {
        module
        for module in app_shell_closure
        if module.startswith("tui/platform/")
    }
    assert not {
        module
        for module in app_shell_closure
        if module.startswith("utils/fs/drivers/")
    }

    host_closure = set(
        dependency_closure(SOURCE_ROOT, ("tui/applet-host/host.f",))
    )
    assert not {
        module
        for module in host_closure
        if module.startswith("tui/applets/")
        or module.startswith("tui/platform/")
        or module.startswith("utils/fs/drivers/")
    }

    report = _report()
    by_path = {module["path"]: module for module in report["modules"]}
    assert "utils/fs/vfs.f" in by_path["tui/app-shell.f"]["requires"]
    assert by_path["tui/platform/mp64fs-vfs.f"]["requires"] == [
        "utils/fs/drivers/vfs-mp64fs.f"
    ]
    assert [
        (edge["from"], edge["to"])
        for edge in report["edges"]
        if edge["from"].startswith("tui/")
        and edge["to"].startswith("utils/fs/drivers/")
    ] == [
        (
            "tui/platform/mp64fs-vfs.f",
            "utils/fs/drivers/vfs-mp64fs.f",
        )
    ]


def test_l9_desk_uses_only_public_shell_and_host_apis() -> None:
    desk = (SOURCE_ROOT / "tui/applets/desk/desk.f").read_text(
        encoding="utf-8"
    )
    assert "_ASHELL-" not in desk
    assert "_AHOST-" not in desk


def test_l9_desk_keeps_the_exact_service_namespace() -> None:
    desk = (SOURCE_ROOT / "tui/applets/desk/desk.f").read_text(
        encoding="utf-8"
    )
    _, setup_marker, setup_tail = desk.partition(
        ": _DESK-SERVICE-TABLE-SETUP"
    )
    assert setup_marker
    setup, next_marker, _ = setup_tail.partition("\n:")
    assert next_marker
    service_ids = tuple(re.findall(r'S" ([^"]+)"', setup))
    assert service_ids == (
        "org.akashic.net.external-io",
        "org.akashic.agent.runtime",
        "org.akashic.agent.tool-gateway",
        "org.akashic.agent.provider-source",
        "org.akashic.agent.access-profile",
        "org.akashic.runtime.registry",
        "org.akashic.runtime.context",
        "org.akashic.runtime.resource-registry",
        "org.akashic.interop.request-bus",
        "org.akashic.resource.daybook",
        "org.akashic.interop.endpoint",
    )

    host = (SOURCE_ROOT / "tui/applet-host/host.f").read_text(
        encoding="utf-8"
    )
    assert "_DESK-SERVICE" not in host
    assert all(service_id not in host for service_id in service_ids)


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
    target_landings = {item["id"]: item["target_landing"] for item in ledger}
    assert target_landings["library.metadata-mutation"] == "L12"
    assert target_landings["library.corpus-query"] == "L12"
    assert target_landings["streams.observation-checkpoint"] == "L13"
    assert target_landings["desk.host-catalogs"] == "deferred"
    assert {
        landing
        for item_id, landing in target_landings.items()
        if item_id.startswith(("agent.", "daybook.", "pad.", "fexplorer."))
        or item_id.startswith(("grid.", "runtime.", "interop.", "uidl."))
    } == {"deferred"}


def test_scale_profiles_and_measurement_gaps_are_explicit() -> None:
    policy = _policy()
    assert policy["filesystem"] == {
        "required_abstraction": "akashic/utils/fs/vfs.f",
        "ext4_prerequisite": False,
        "note": "Scale and architecture qualification use the generic VFS contract; ext4 is an optional integration backend.",
    }
    assert policy["scale_profiles"]["library"]["workstation"] == {
        "documents": 100000,
        "revisions_or_relationship_edges": 1000000,
        "content_bytes_must_exceed": 65536,
        "purpose": "interactive Library corpus and ordinary performance qualification",
    }
    assert policy["scale_profiles"]["library"]["large_host_model"] == {
        "documents": 1000000,
        "revisions": 10000000,
        "relationship_edges": 10000000,
        "purpose": "prove Library index geometry, amplification, and bounded working memory without aggregate target allocation",
    }
    assert policy["scale_profiles"]["streams"]["workstation"] == {
        "sources": 10000,
        "observations": 1000000,
        "retained_attempts": 2000000,
        "purpose": "interactive Streams source, refresh, timeline, thread, and search qualification",
    }
    assert policy["scale_profiles"]["streams"]["large_host_model"] == {
        "sources": 100000,
        "observations": 10000000,
        "retained_attempts": 20000000,
        "purpose": "prove skewed source histories, deep continuation, amplification, and bounded working memory",
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
    assert policy["scale_profiles"]["persistence_instance_workload"] == {
        "interleaved_stores": 4,
        "hidden_process_global_current_store": False,
    }
    assert "instance_workload" not in policy["scale_profiles"]
    assert all(
        "runtime_routes" not in profile
        for applet in ("library", "streams")
        for profile in policy["scale_profiles"][applet].values()
    )
    assert "high-degree" in policy["scale_profiles"][
        "library_model_workload"
    ][
        "relationship_distribution"
    ]
    assert "thread" in policy["scale_profiles"]["streams_model_workload"][
        "query_shape"
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
    repository = by_path[
        "tui/applets/library/repository.f"
    ]["lexical_definitions"]
    assert "_library-vfs-store-guard" in repository["guard"]
    assert "_LIBVP-FRAME" in repository["create"]
    assert "_LIBVP-CATALOG-FACTS" in repository["create"]
    bus = by_path["interop/request-bus.f"]["lexical_definitions"]
    assert "_CBUS-DISPATCH-DEPTH" in bus["variable"]
    assert "_CBUS-OWNER-OP-DEPTH" in bus["variable"]


def test_all_capacity_sources_are_production_modules() -> None:
    for capacity in _policy()["capacities"]:
        path = SOURCE_ROOT / capacity["module"]
        assert path.is_file(), capacity
        assert path.suffix == ".f"
