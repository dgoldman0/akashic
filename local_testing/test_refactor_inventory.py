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

DORMANT_STREAMS_L13_MODULES = {
    "tui/applets/streams/acquisition-authority.f",
    "tui/applets/streams/apply-authority.f",
    "tui/applets/streams/authority-root.f",
    "tui/applets/streams/compaction.f",
    "tui/applets/streams/index-keys.f",
    "tui/applets/streams/index-record-agreement.f",
    "tui/applets/streams/migration.f",
    "tui/applets/streams/observation-construction.f",
    "tui/applets/streams/persistence-adapter.f",
    "tui/applets/streams/persistence-records.f",
    "tui/applets/streams/query.f",
    "tui/applets/streams/repository-refresh-owner.f",
    "tui/applets/streams/repository.f",
    "tui/applets/streams/runtime-owner.f",
    "tui/applets/streams/semantic-record-agreement.f",
    "tui/applets/streams/source-authority.f",
}
COMMITTED_STREAMS_COMPATIBILITY_ROOTS = (
    "tui/applets/streams/streams.f",
    "tui/applets/streams/streams-online.f",
)
STREAMS_SR1_CORE = "tui/applets/streams/flow-core.f"


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
        "module_count": 548,
        "resolved_require_occurrence_count": 1937,
        "unique_resolved_edge_count": 1937,
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
        "capabilities.f",
        "capability-work.f",
        "collection-values.f",
        "controller.f",
        "document-values.f",
        "index-keys.f",
        "library.f",
        "model.f",
        "persistence-adapter.f",
        "projection-adapter.f",
        "query.f",
        "repository.f",
        "service.f",
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


def test_halted_streams_l13_modules_are_exact_and_dormant() -> None:
    policy = _policy()
    historical_rules = {
        rule["module"]: rule
        for rule in policy["ownership"]["exact"]
        if rule.get("ownership_decision") == "historical-dormant-l13"
    }
    assert set(historical_rules) == DORMANT_STREAMS_L13_MODULES
    assert all(
        rule["class"] == "applet"
        and rule["owner"] == "streams"
        and rule["placement"] == "correct"
        and rule["target"] == module
        for module, rule in historical_rules.items()
    )

    for root in (
        *COMMITTED_STREAMS_COMPATIBILITY_ROOTS,
        STREAMS_SR1_CORE,
    ):
        closure = set(dependency_closure(SOURCE_ROOT, (root,)))
        assert root in closure
        assert DORMANT_STREAMS_L13_MODULES.isdisjoint(closure), root


def test_public_applet_seams_are_exact_and_private_imports_still_fail() -> None:
    policy = _policy()
    assert policy["public_applet_seams"] == [
        {
            "from": "tui/applets/desk/agent-cap-catalog.f",
            "to": "tui/applets/agent/access-profile.f",
            "purpose": (
                "Desk-owned capability selection policy uses Agent's public "
                "access-profile selector contract."
            ),
        },
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
    desk_catalog = classify_module(
        "tui/applets/desk/agent-cap-catalog.f", policy
    )
    agent_access = classify_module(
        "tui/applets/agent/access-profile.f", policy
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
        "tui/applets/desk/agent-cap-catalog.f",
        "tui/applets/agent/access-profile.f",
        desk_catalog,
        agent_access,
        policy,
    ) is None
    assert _dependency_violation(
        "tui/applets/desk/agent-cap-catalog.f",
        "tui/applets/agent/runtime.f",
        desk_catalog,
        agent_runtime,
        policy,
    ) == "applet-imports-sibling"
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
        "org.akashic.sandbox.pure-compute",
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
    compatibility_ids = {
        capacity["id"]
        for capacity in _policy()["capacities"]
        if capacity.get("status") == "compatibility"
    }
    assert compatibility_ids == {
        "streams.sources",
        "streams.observations",
        "streams.keys",
        "streams.checkpoint-bytes",
        "streams.source-registry",
    }
    qualified_sr2_runtime_ids = {
        capacity["id"]
        for capacity in _policy()["capacities"]
        if capacity.get("status") == "qualified-sr2-runtime"
    }
    assert qualified_sr2_runtime_ids == {
        "streams.sr2-segment-bytes",
        "streams.sr2-compact-segments",
        "streams.sr2-standard-segments",
        "streams.sr2-compact-operation-bytes",
        "streams.sr2-standard-operation-bytes",
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
    statuses = {item["id"]: item.get("status", "open") for item in ledger}
    assert statuses["library.metadata-mutation"] == "resolved"
    assert statuses["streams.observation-checkpoint"] == (
        "superseded-compatibility"
    )
    checkpoint = next(
        item
        for item in ledger
        if item["id"] == "streams.observation-checkpoint"
    )
    assert checkpoint["replacement_requirement"] == (
        "retain only as frozen compatibility evidence until SR6 retirement; "
        "derive any future operational persistence from the SR2 flow and "
        "delivery semantics in SR3, never from the superseded observation "
        "corpus"
    )
    target_landings = {item["id"]: item["target_landing"] for item in ledger}
    assert target_landings["library.metadata-mutation"] == "L12"
    assert "library.corpus-query" not in target_landings
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
        "collections": 100000,
        "revisions": 10000000,
        "relationship_edges": 10000000,
        "representative_current_tag_postings": 16000000,
        "representative_current_text_postings": 12666000000,
        "index_tree_count": 15,
        "purpose": "prove the live Library index geometry, amplification, and bounded working memory without aggregate target allocation",
    }
    assert policy["scale_profiles"]["streams"]["workstation"] == {
        "status": "historical-inactive",
        "sources": 10000,
        "observations": 1000000,
        "retained_attempts": 2000000,
        "purpose": "interactive Streams source, refresh, timeline, thread, and search qualification",
    }
    assert policy["scale_profiles"]["streams"]["large_host_model"] == {
        "status": "historical-inactive",
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
    assert policy["scale_profiles"]["streams_model_workload"]["status"] == (
        "historical-inactive"
    )
    assert policy["scale_profiles"]["sr1_contract"] == {
        "status": "qualified-prototype-cell",
        "input_connectors": 1,
        "execution_cells": 1,
        "transforms": 1,
        "output_connectors": 1,
        "admission_slots_per_cell": 1,
        "payload_max_bytes": 4096,
        "operation_max_bytes": 256,
        "storage": "none",
        "qualification": "deterministic-mocks",
        "capacity_role": (
            "SR1 prototype cell bounds, not supported product limits"
        ),
    }
    assert policy["scale_profiles"]["streams_capacity_convergence"] == {
        "status": "sr3-deterministic-durability-qualified",
        "sr2": {
            "landing_status": {
                "runtime_shape": "qualified",
                "cooperative_http": "qualified",
                "connection_isolation_pressure": "qualified",
            },
            "runtime": "bounded caller-owned execution-cell pool",
            "payload": (
                "named payload profiles with body and connection storage "
                "separate from each cell"
            ),
            "http": (
                "caller-owned strict request framing, copied routing, "
                "bounded response sources and exact interleaved cooperative "
                "request-to-response journeys under pool pressure"
            ),
            "qualification": [
                "two interleaved cells",
                (
                    "one body larger than 4096 bytes without enlarging "
                    "every cell"
                ),
                "exact-full and one-over pool refusal",
                "slow or cancelled peer teardown",
                (
                    "measured live workspace memory and deterministic "
                    "owner-step cost"
                ),
            ],
            "persistence": "none",
            "cutover_rule": (
                "the unreleased SR1 layout is replaced atomically; no "
                "parallel layout, ABI selector, adapter, migration, "
                "deprecation path, or old-layout reader; general code does "
                "not persist raw descriptors"
            ),
        },
        "sr3": {
            "landing_status": {
                "atomic_admission": "qualified",
                "delivery_recovery_cleanup": "qualified",
                "sr2_runtime_composition": "qualified",
                "finite_retirement": "qualified",
            },
            "runtime_relation": (
                "durable queues and spools are separate from the "
                "active-cell pool"
            ),
            "capacity": (
                "independent item and byte bounds with exact-full and "
                "one-over behavior"
            ),
            "acceptance": (
                "exact payload snapshot and attempt identity commit before "
                "durable acceptance"
            ),
            "delivery": (
                "durable ready, active, terminal, receipt, stale-revision, "
                "cancellation, cleanup-failure, and visible indeterminate "
                "truth with current-only recovery"
            ),
            "recovery": (
                "self-identifying current format, interrupted publication, "
                "corrupt or unknown refusal, restart, receipts, and visible "
                "indeterminate work; prerelease changes replace the prototype"
            ),
            "composition": (
                "caller-owned dispatch binds exact durable authority to a "
                "fitting SR2 cell, commits active authority before runtime "
                "effect, and retires the cell only after durable terminal "
                "evidence"
            ),
            "retirement": (
                "revision-checked logical cleanup and current-only bounded "
                "two-bank live-set compaction remove unreachable records and "
                "payloads, reopen the selected bank, and physically remove "
                "the old bank"
            ),
            "retry": (
                "no automatic indeterminate-effect retry without a safe "
                "declared idempotency contract"
            ),
            "qualification": [
                "current configuration and operational record codecs",
                "exact-full and one-over atomic admission",
                (
                    "delivery, receipt, stale-revision, "
                    "indeterminate-recovery, and logical-cleanup journeys"
                ),
                (
                    "SR2 dispatch composition with authority-before-effect "
                    "and finite runtime retirement"
                ),
                (
                    "bounded live-set compaction, old-bank removal, "
                    "selected-bank reopen, and cold physical audit"
                ),
            ],
            "cutover_rule": (
                "the unreleased durable prototype has one current record and "
                "compaction path; no parallel format, version selector, "
                "adapter, migration, deprecation path, or old-layout reader "
                "remains"
            ),
        },
        "sr6": {
            "status": "production-workload-profile-stage",
            "purpose": (
                "qualify supported workload profiles without redesigning "
                "runtime semantics or durable record shapes"
            ),
            "required_axes": [
                "connectors",
                "flows",
                "in-flight cells",
                "payload-size mix",
                "ingress items and bytes",
                "egress items and bytes",
                "throughput",
                "latency",
                "memory",
                "disk amplification",
                "recovery time",
            ],
        },
    }
    assert policy["scale_profiles"]["future_sr6"] == {
        "status": "production-workload-profile-stage",
        "workload": (
            "derive production-supported profiles from the qualified SR2 "
            "runtime and SR3 deterministic durable path"
        ),
        "must_not_require": [
            "runtime semantic redesign",
            "durable record-shape redesign",
            "reuse of historical source and observation cardinalities",
        ],
    }
    assert policy["hot_path_budgets"] == {
        "cold_open_page_read_policy": (
            "complete valid-slot application and reclaim ownership audit"
        ),
        "cold_open_working_memory": (
            "two caller-owned bytes per largest valid-slot page plus fixed "
            "audit work"
        ),
        "large_profile_point_lookup_max_index_pages": 12,
        "large_profile_32_result_keyset_max_index_page_reads": 44,
        "large_profile_250000_edge_range_max_index_page_reads": 273455,
        "library_index_tree_count": 15,
        "library_index_workspace_bytes": 170568,
        "btree_mutation_max_allocated_pages": 25,
        "allocated_page_ledger": 128,
        "staging_admission_policy": "bounded high-water arena reservation",
        "staging_mutation_page_reservation": (
            "2h+1 pages at the tallest current staging root"
        ),
        "staging_publication_reservation": (
            "one application-root page within the 128-page physical "
            "transaction arena"
        ),
        "stage_policy_within_physical_arena": True,
        "reclaim_maintenance_max_page_writes_per_step": 1,
        "ui_max_collection_pages": 3,
        "ordinary_operation_corpus_proportional_allocation": False,
        "required_measurements": [
            "logical page reads and writes",
            "bytes read and written",
            "comparisons",
            "allocation events and peak live bytes",
            "cache hits and misses",
            "guest cycles and stalls",
            "peak working memory",
        ],
    }
    assert policy["hot_path_budget_amendment"] == {
        "landing": "L12",
        "superseded_l11_projection": {
            "index_tree_count": 7,
            "library_index_workspace_bytes": 84672,
            "large_profile_point_lookup_max_index_pages": 9,
            "large_profile_32_result_keyset_max_index_page_reads": 66,
            "large_profile_250000_edge_range_max_index_page_reads": 515658,
            "metadata_mutation_representative_pages": 77,
            "metadata_mutation_structural_ceiling_pages": 139,
        },
        "live_topology": {
            "index_tree_count": 15,
            "library_index_workspace_bytes": 170568,
            "large_profile_point_lookup_max_index_pages": 12,
            "large_profile_32_result_keyset_max_index_page_reads": 44,
            "large_profile_250000_edge_range_max_index_page_reads": 273455,
            "btree_mutation_max_allocated_pages": 25,
            "allocated_page_ledger": 128,
            "staging_admission_policy": (
                "bounded high-water arena reservation"
            ),
            "staging_mutation_page_reservation": (
                "2h+1 pages at the tallest current staging root"
            ),
            "staging_publication_reservation": (
                "one application-root page within the 128-page physical "
                "transaction arena"
            ),
        },
        "resolved": (
            "L12 admits each staged mutation only when its dynamic tree-height "
            "reservation and the next application-root page fit the bounded "
            "physical staging arena; physical publications split long logical "
            "operations without advancing their logical generation, and "
            "two-bank compaction replaces the prior bank arena with an "
            "explicitly owned target-build arena."
        ),
        "evidence": [
            "exact fifteen-root Library adapter topology",
            "twelve-level churn-retained body-postings bound",
            "7,813 cache-preserving 32-result membership slices",
            "170,568-byte caller-owned Library index workspace",
            "all-tree page-read, page-write, and comparison telemetry",
            "2h+1 mutation-page reservation from the tallest current staging root",
            "bounded 128-page high-water arena admission",
            "two-byte-per-page cold ownership and structural-uniqueness audit",
            "physical and final publication paths with distinct logical-generation semantics",
        ],
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
    assert "Library aggregate fifteen-tree page reads" in baseline[
        "existing_guest_counters"
    ]
    assert "Library aggregate fifteen-tree page writes" in baseline[
        "existing_guest_counters"
    ]
    assert "Library aggregate fifteen-tree comparisons" in baseline[
        "existing_guest_counters"
    ]
    assert "allocation event count" in baseline["missing_instrumentation"]
    assert "logical persistence page reads and writes" not in baseline[
        "missing_instrumentation"
    ]
    assert "not an allocation counter" in baseline["clarification"]
    assert "logical page telemetry" in baseline["clarification"]
    coverage = {entry["area"]: entry["status"] for entry in baseline["coverage"]}
    assert coverage == {
        "Library": "analytical-and-focused-guest",
        "Streams": "deterministic-runtime-and-durability-qualified",
        "Agent": "functional-and-capacity-only",
        "Daybook/Pad/Grid/FExplorer": "functional-and-capacity-only",
        "Desk/TUI": "journey-only",
    }
    streams_coverage = next(
        entry for entry in baseline["coverage"] if entry["area"] == "Streams"
    )
    assert "SR2+" not in streams_coverage["missing"]
    assert "SR6" in streams_coverage["missing"]
    assert "production workload" in streams_coverage["missing"]


def test_live_module_inventory_includes_exact_mutable_symbols() -> None:
    report = _report()
    by_path = {module["path"]: module for module in report["modules"]}
    repository = by_path[
        "tui/applets/library/repository.f"
    ]["lexical_definitions"]
    assert repository["guard"] == []
    assert repository["create"] == []
    assert {"_LR-GUARD", "_LR-BUILDER-GUARD"} <= set(
        repository["constant"]
    )
    bus = by_path["interop/request-bus.f"]["lexical_definitions"]
    assert "_CBUS-DISPATCH-DEPTH" in bus["variable"]
    assert "_CBUS-OWNER-OP-DEPTH" in bus["variable"]


def test_all_capacity_sources_are_production_modules() -> None:
    for capacity in _policy()["capacities"]:
        path = SOURCE_ROOT / capacity["module"]
        assert path.is_file(), capacity
        assert path.suffix == ".f"
