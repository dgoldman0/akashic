#!/usr/bin/env python3
"""Live architecture inventory and layering ratchet for the Desk refactor.

The inventory is deliberately host-only and standard-library-only.  It scans
the production Forth tree without importing the emulator packaging harness, so
the architectural checks neither require an MP64FS image nor any filesystem
driver such as ext4.

JSON output is the machine-readable dependency graph.  ``--check`` compares the
live graph, placement debt, literal capacity facts, and known cycles with the
settled Landing L0 policy in ``refactor_architecture.json``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

from forth_dependencies import (
    PROVIDED_RE,
    REQUIRE_RE,
    dependency_markers,
    module_key,
)


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = REPOSITORY_ROOT / "akashic"
DEFAULT_POLICY_PATH = Path(__file__).with_name("refactor_architecture.json")

LITERAL_CONSTANT_RE = re.compile(
    r"^\s*(?P<value>-?(?:0x[0-9A-Fa-f]+|[0-9]+))\s+"
    r"CONSTANT\s+(?P<name>\S+)(?:\s|$)",
    re.MULTILINE,
)

DEFINITION_KINDS = {
    "CREATE": "create",
    "VARIABLE": "variable",
    "VALUE": "value",
    "DEFER": "defer",
    "XBUF": "xbuf",
    "GUARD": "guard",
    "CONSTANT": "constant",
}
FORTH_QUOTING_WORDS = {
    "'",
    "[']",
    "CHAR",
    "[CHAR]",
    "POSTPONE",
    "[COMPILE]",
    "[DEFINED]",
    "[UNDEFINED]",
}
FORTH_STRING_WORDS = {'S"', 'C"', '."', 'ABORT"'}
FORTH_PAREN_STRING_WORDS = {".("}
MUTABLE_DEFINITION_KINDS = (
    "create",
    "variable",
    "value",
    "defer",
    "xbuf",
    "guard",
)


def _forth_code_tokens(text: str) -> Iterable[str]:
    """Yield Forth tokens while omitting comments and parsed string bodies."""
    index = 0
    quoted_next = False
    while index < len(text):
        while index < len(text) and text[index].isspace():
            index += 1
        if index >= len(text):
            break

        start = index
        while index < len(text) and not text[index].isspace():
            index += 1
        token = text[start:index]
        upper = token.upper()

        if quoted_next:
            quoted_next = False
            yield token
            continue
        if upper in FORTH_QUOTING_WORDS:
            quoted_next = True
            yield token
            continue
        if token.startswith("\\"):
            newline = text.find("\n", index)
            index = len(text) if newline < 0 else newline + 1
            continue
        if token == "(":
            close = text.find(")", index)
            index = len(text) if close < 0 else close + 1
            continue
        if upper in FORTH_STRING_WORDS:
            close = text.find('"', index)
            index = len(text) if close < 0 else close + 1
            continue
        if upper in FORTH_PAREN_STRING_WORDS:
            close = text.find(")", index)
            index = len(text) if close < 0 else close + 1
            continue
        yield token


def load_policy(path: Path = DEFAULT_POLICY_PATH) -> dict[str, Any]:
    """Load the settled, reviewed architecture policy."""
    return json.loads(path.read_text(encoding="utf-8"))


def _module_paths() -> tuple[Path, ...]:
    return tuple(sorted(SOURCE_ROOT.rglob("*.f")))


def _noncanonical_marker_issues(module: str, text: str) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    for line_number, line in enumerate(text.splitlines(), start=1):
        candidate = line.lstrip(" ")
        if re.match(r"^REQUIRE(?:\s|$)", candidate) and not REQUIRE_RE.match(line):
            issues.append(
                {
                    "kind": "noncanonical-require-marker",
                    "module": module,
                    "line": line_number,
                    "text": line,
                }
            )
        if re.match(r"^PROVIDED(?:\s|$)", candidate) and not PROVIDED_RE.match(line):
            issues.append(
                {
                    "kind": "noncanonical-provided-marker",
                    "module": module,
                    "line": line_number,
                    "text": line,
                }
            )
    return issues


def _lexical_definitions(text: str) -> dict[str, list[str]]:
    """Return top-level definitions, including repeated words on one line.

    A token scan is necessary because Akashic commonly declares several
    ``VARIABLE`` words on one source line.  Colon bodies, quoted word names,
    strings, and comments are skipped so a defining word used by a factory or
    mentioned as data is not mistaken for a module-owned declaration.
    """
    definitions: dict[str, list[str]] = {
        kind: [] for kind in DEFINITION_KINDS.values()
    }
    in_colon = False
    skip_quoted_name = False
    pending_kind: str | None = None

    for token in _forth_code_tokens(text):
        upper = token.upper()
        if in_colon:
            if token == ";":
                in_colon = False
            continue
        if upper in {":", ":NONAME"}:
            in_colon = True
            pending_kind = None
            continue
        if skip_quoted_name:
            skip_quoted_name = False
            continue
        if upper in FORTH_QUOTING_WORDS:
            skip_quoted_name = True
            continue
        if pending_kind is not None:
            definitions[pending_kind].append(token)
            pending_kind = None
            continue
        if upper in DEFINITION_KINDS:
            pending_kind = DEFINITION_KINDS[upper]
    return definitions


def classify_module(module: str, policy: dict[str, Any]) -> dict[str, Any]:
    """Return the reviewed ownership class and current/target placement."""
    ownership = policy["ownership"]
    for rule in ownership["exact"]:
        if module == rule["module"]:
            return {
                "class": rule["class"],
                "owner": rule.get("owner"),
                "placement": rule["placement"],
                "target": rule.get("target", module),
                "split_targets": rule.get("split_targets", []),
                "ownership_decision": rule.get(
                    "ownership_decision", "settled"
                ),
            }

    for rule in ownership["prefixes"]:
        prefix = rule["prefix"]
        if module.startswith(prefix):
            suffix = module[len(prefix) :]
            target_prefix = rule.get("target_prefix", prefix)
            return {
                "class": rule["class"],
                "owner": rule.get("owner"),
                "placement": rule["placement"],
                "target": f"{target_prefix}{suffix}",
                "split_targets": [],
                "ownership_decision": rule.get(
                    "ownership_decision", "settled"
                ),
            }

    if module.startswith("tui/applets/"):
        parts = module.split("/")
        owner = parts[2] if len(parts) > 2 else None
        return {
            "class": "applet",
            "owner": owner,
            "placement": "correct",
            "target": module,
            "split_targets": [],
            "ownership_decision": "settled",
        }
    if module.startswith("tui/"):
        return {
            "class": "desk-ecosystem",
            "owner": None,
            "placement": "correct",
            "target": module,
            "split_targets": [],
            "ownership_decision": "settled",
        }
    if any(
        module.startswith(prefix)
        for prefix in ownership["independent_prefixes"]
    ):
        return {
            "class": "independent",
            "owner": None,
            "placement": "correct",
            "target": module,
            "split_targets": [],
            "ownership_decision": "settled",
        }
    return {
        "class": "unclassified",
        "owner": None,
        "placement": "unclassified",
        "target": module,
        "split_targets": [],
        "ownership_decision": "unsettled",
    }


def _dependency_violation(
    source: str,
    target: str,
    source_class: dict[str, Any],
    target_class: dict[str, Any],
) -> str | None:
    source_kind = source_class["class"]
    target_kind = target_class["class"]

    if source_kind == "independent" and target_kind in {
        "desk-ecosystem",
        "applet",
    }:
        return "independent-imports-ecosystem"
    if source_kind == "desk-ecosystem" and target_kind == "applet":
        return "shared-tui-imports-applet"
    if source_kind == "applet" and target_kind == "applet":
        source_owner = source_class.get("owner")
        target_owner = target_class.get("owner")
        if (
            source_owner
            and target_owner
            and source_owner != target_owner
        ):
            return "applet-imports-sibling"
    return None


def _declared_dependency_violations(
    source: str, target: str, policy: dict[str, Any]
) -> tuple[str, ...]:
    rules: list[str] = []
    for constraint in policy["dependency_constraints"]:
        source_matches = (
            source == constraint.get("from")
            if "from" in constraint
            else source.startswith(constraint["from_prefix"])
        )
        if source_matches and target.startswith(constraint["forbid_target_prefix"]):
            rules.append(constraint["rule"])
    return tuple(rules)


def _strongly_connected_components(
    modules: tuple[str, ...], edges: tuple[tuple[str, str], ...]
) -> tuple[tuple[str, ...], ...]:
    """Return deterministic dependency cycles using Tarjan SCCs."""
    adjacency: dict[str, list[str]] = {module: [] for module in modules}
    for source, target in edges:
        adjacency[source].append(target)
    for dependencies in adjacency.values():
        dependencies.sort()

    index = 0
    indices: dict[str, int] = {}
    lowlinks: dict[str, int] = {}
    stack: list[str] = []
    on_stack: set[str] = set()
    components: list[tuple[str, ...]] = []

    def visit(module: str) -> None:
        nonlocal index
        indices[module] = index
        lowlinks[module] = index
        index += 1
        stack.append(module)
        on_stack.add(module)

        for dependency in adjacency[module]:
            if dependency not in indices:
                visit(dependency)
                lowlinks[module] = min(lowlinks[module], lowlinks[dependency])
            elif dependency in on_stack:
                lowlinks[module] = min(lowlinks[module], indices[dependency])

        if lowlinks[module] != indices[module]:
            return
        component: list[str] = []
        while True:
            member = stack.pop()
            on_stack.remove(member)
            component.append(member)
            if member == module:
                break
        ordered = tuple(sorted(component))
        if len(ordered) > 1 or module in adjacency[module]:
            components.append(ordered)

    for module in modules:
        if module not in indices:
            visit(module)
    return tuple(sorted(components))


def _literal_constants(text: str) -> dict[str, int]:
    return {
        match.group("name"): int(match.group("value"), 0)
        for match in LITERAL_CONSTANT_RE.finditer(text)
    }


def _capacity_facts(policy: dict[str, Any]) -> tuple[dict[str, Any], ...]:
    source_cache: dict[str, str] = {}
    facts: list[dict[str, Any]] = []
    for expected in policy["capacities"]:
        module = expected["module"]
        if module not in source_cache:
            source_cache[module] = (SOURCE_ROOT / module).read_text(
                encoding="utf-8"
            )
        constants = _literal_constants(source_cache[module])
        symbol = expected["symbol"]
        actual = constants.get(symbol)
        fact = dict(expected)
        fact["actual"] = actual
        fact["matches"] = actual == expected["value"]
        facts.append(fact)
    return tuple(facts)


def _complexity_facts(policy: dict[str, Any]) -> tuple[dict[str, Any], ...]:
    """Anchor reviewed structure/complexity claims to live source words."""
    source_tokens: dict[str, set[str]] = {}
    facts: list[dict[str, Any]] = []
    for expected in policy["complexity_ledger"]:
        module = expected["module"]
        if module not in source_tokens:
            source_tokens[module] = set(
                _forth_code_tokens(
                    (SOURCE_ROOT / module).read_text(encoding="utf-8")
                )
            )
        missing = [
            symbol
            for symbol in expected["evidence_symbols"]
            if symbol not in source_tokens[module]
        ]
        fact = dict(expected)
        fact["missing_evidence_symbols"] = missing
        fact["matches"] = not missing
        facts.append(fact)
    return tuple(facts)


def _git_head() -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=REPOSITORY_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def build_report(policy: dict[str, Any] | None = None) -> dict[str, Any]:
    """Build the complete deterministic machine-readable L0 inventory."""
    if policy is None:
        policy = load_policy()

    paths = _module_paths()
    module_names = tuple(path.relative_to(SOURCE_ROOT).as_posix() for path in paths)
    module_set = set(module_names)
    modules: list[dict[str, Any]] = []
    internal_edges: list[tuple[str, str]] = []
    edge_records: list[dict[str, Any]] = []
    unresolved_requires: list[dict[str, Any]] = []
    layer_violations: list[dict[str, Any]] = []
    placement_debt: list[dict[str, Any]] = []
    provided_by: dict[str, list[str]] = defaultdict(list)
    provided_keys: dict[bytes, list[tuple[str, str]]] = defaultdict(list)
    provided_issues: list[dict[str, Any]] = []
    addressability_issues: list[dict[str, Any]] = []
    marker_issues: list[dict[str, Any]] = []

    classifications = {
        module: classify_module(module, policy) for module in module_names
    }

    for path, module in zip(paths, module_names):
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        classification = classifications[module]
        marker_issues.extend(_noncanonical_marker_issues(module, text))
        dependencies: list[str] = []
        if any(" " in part or "\t" in part for part in Path(module).parts):
            addressability_issues.append(
                {
                    "kind": "whitespace-in-module-path",
                    "module": module,
                }
            )
        for marker in dependency_markers(text, module):
            dependency = marker.normalized
            record = {
                "from": module,
                "line": marker.line,
                "raw": marker.raw,
                "to": dependency,
            }
            if dependency in module_set:
                dependencies.append(dependency)
                internal_edges.append((module, dependency))
                edge_records.append(record)
                violation = _dependency_violation(
                    module,
                    dependency,
                    classification,
                    classifications[dependency],
                )
                if violation:
                    layer_violations.append(
                        {
                            "rule": violation,
                            "from": module,
                            "to": dependency,
                        }
                    )
                for declared in _declared_dependency_violations(
                    module, dependency, policy
                ):
                    layer_violations.append(
                        {
                            "rule": declared,
                            "from": module,
                            "to": dependency,
                        }
                    )
            else:
                unresolved_requires.append(record)

        lexical = _lexical_definitions(text)
        provides = sorted(PROVIDED_RE.findall(text))
        for identity in provides:
            provided_by[identity].append(module)
            provided_keys[module_key(identity)].append((module, identity))
        if len(provides) != 1:
            provided_issues.append(
                {
                    "kind": "module-provided-count",
                    "module": module,
                    "identities": provides,
                }
            )
        modules.append(
            {
                "path": module,
                "class": classification["class"],
                "owner": classification.get("owner"),
                "placement": classification["placement"],
                "target": classification["target"],
                "split_targets": classification["split_targets"],
                "ownership_decision": classification["ownership_decision"],
                "lines": len(text.splitlines()),
                "bytes": len(raw),
                "requires": sorted(dependencies),
                "provides": provides,
                "lexical_definitions": lexical,
                "lexical_definition_counts": {
                    kind: len(names) for kind, names in lexical.items()
                },
            }
        )
        if classification["placement"] != "correct":
            placement_debt.append(
                {
                    "module": module,
                    "owner": classification.get("owner"),
                    "status": classification["placement"],
                    "target": classification["target"],
                    "split_targets": classification["split_targets"],
                }
            )

    for identity, providers in sorted(provided_by.items()):
        if len(providers) > 1:
            provided_issues.append(
                {
                    "kind": "duplicate-provided-identity",
                    "identity": identity,
                    "modules": sorted(providers),
                }
            )
    for key, providers in sorted(provided_keys.items(), key=lambda item: item[0]):
        unique = sorted(set(providers))
        if len(unique) > 1:
            provided_issues.append(
                {
                    "kind": "bounded-provided-key-collision",
                    "key_hex": key.hex(),
                    "providers": [list(provider) for provider in unique],
                }
            )

    edges = tuple(sorted(set(internal_edges)))
    graph_payload = {
        "modules": list(module_names),
        "edges": [list(edge) for edge in edges],
        "unresolved_requires": [
            [record["from"], record["raw"], record["to"]]
            for record in sorted(
                unresolved_requires,
                key=lambda item: (item["from"], item["line"], item["to"]),
            )
        ],
    }
    graph_sha256 = hashlib.sha256(
        json.dumps(
            graph_payload, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()
    state_payload = [
        [
            module["path"],
            {
                kind: module["lexical_definitions"][kind]
                for kind in MUTABLE_DEFINITION_KINDS
            },
        ]
        for module in modules
    ]
    state_sha256 = hashlib.sha256(
        json.dumps(
            state_payload, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()

    class_totals: dict[str, dict[str, int]] = defaultdict(
        lambda: {"modules": 0, "lines": 0, "bytes": 0, "lexical_globals": 0}
    )
    for module in modules:
        total = class_totals[module["class"]]
        total["modules"] += 1
        total["lines"] += module["lines"]
        total["bytes"] += module["bytes"]
        definitions = module["lexical_definition_counts"]
        total["lexical_globals"] += sum(
            definitions[name] for name in MUTABLE_DEFINITION_KINDS
        )

    sorted_placement_debt = sorted(
        placement_debt, key=lambda item: (item["module"], item["target"])
    )
    sorted_unresolved_requires = sorted(
        unresolved_requires,
        key=lambda item: (item["from"], item["line"], item["to"]),
    )
    placement_sha256 = hashlib.sha256(
        json.dumps(
            sorted_placement_debt, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()
    unresolved_sha256 = hashlib.sha256(
        json.dumps(
            sorted_unresolved_requires, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
    ).hexdigest()

    return {
        "schema": policy["schema"],
        "baseline_name": policy["baseline"]["name"],
        "live_commit": _git_head(),
        "source_root": "akashic/",
        "summary": {
            "module_count": len(module_names),
            "resolved_require_occurrence_count": len(edge_records),
            "unique_resolved_edge_count": len(edges),
            "unresolved_require_count": len(unresolved_requires),
            "cycle_count": len(
                _strongly_connected_components(module_names, edges)
            ),
            "layer_violation_count": len(layer_violations),
            "placement_debt_count": len(placement_debt),
            "provided_issue_count": len(provided_issues),
            "addressability_issue_count": len(addressability_issues),
            "marker_issue_count": len(marker_issues),
            "graph_sha256": graph_sha256,
            "state_sha256": state_sha256,
            "placement_sha256": placement_sha256,
            "unresolved_sha256": unresolved_sha256,
            "class_totals": dict(sorted(class_totals.items())),
        },
        "cycles": [
            list(component)
            for component in _strongly_connected_components(module_names, edges)
        ],
        "layer_violations": sorted(
            layer_violations,
            key=lambda item: (item["rule"], item["from"], item["to"]),
        ),
        "placement_debt": sorted_placement_debt,
        "provided_issues": provided_issues,
        "addressability_issues": sorted(
            addressability_issues, key=lambda item: (item["kind"], item["module"])
        ),
        "marker_issues": sorted(
            marker_issues,
            key=lambda item: (item["kind"], item["module"], item["line"]),
        ),
        "unresolved_requires": sorted_unresolved_requires,
        "edges": sorted(
            edge_records, key=lambda item: (item["from"], item["to"], item["line"])
        ),
        "modules": modules,
        "capacities": list(_capacity_facts(policy)),
        "complexity_ledger": list(_complexity_facts(policy)),
        "scale_profiles": policy["scale_profiles"],
        "hot_path_budgets": policy["hot_path_budgets"],
        "hot_path_baseline": policy["hot_path_baseline"],
    }


def _canonical_rows(rows: Iterable[dict[str, Any]], keys: tuple[str, ...]) -> list:
    return [[row.get(key) for key in keys] for row in rows]


def check_report(report: dict[str, Any], policy: dict[str, Any]) -> list[str]:
    """Return human-readable baseline/policy mismatches."""
    expected = policy["baseline"]["expected"]
    actual_summary = report["summary"]
    errors: list[str] = []

    for key in (
        "module_count",
        "resolved_require_occurrence_count",
        "unique_resolved_edge_count",
        "unresolved_require_count",
        "cycle_count",
        "layer_violation_count",
        "placement_debt_count",
        "provided_issue_count",
        "addressability_issue_count",
        "marker_issue_count",
        "graph_sha256",
        "state_sha256",
        "placement_sha256",
        "unresolved_sha256",
    ):
        if actual_summary[key] != expected[key]:
            errors.append(
                f"{key}: expected {expected[key]!r}, got {actual_summary[key]!r}"
            )

    structured_checks = (
        ("cycles", report["cycles"], expected["cycles"]),
        (
            "layer violations",
            _canonical_rows(
                report["layer_violations"], ("rule", "from", "to")
            ),
            expected["layer_violations"],
        ),
        (
            "PROVIDED issues",
            report["provided_issues"],
            expected["provided_issues"],
        ),
        (
            "addressability issues",
            report["addressability_issues"],
            expected["addressability_issues"],
        ),
        (
            "marker issues",
            report["marker_issues"],
            expected["marker_issues"],
        ),
    )
    for label, actual, wanted in structured_checks:
        if actual != wanted:
            errors.append(f"{label} changed: expected {wanted!r}, got {actual!r}")

    for capacity in report["capacities"]:
        if not capacity["matches"]:
            errors.append(
                f"capacity {capacity['id']}: {capacity['symbol']} expected "
                f"{capacity['value']}, got {capacity['actual']!r}"
            )

    for item in report["complexity_ledger"]:
        if not item["matches"]:
            errors.append(
                f"complexity {item['id']}: missing source evidence "
                f"{item['missing_evidence_symbols']!r}"
            )

    return errors


def _summary_text(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        f"schema: {report['schema']}",
        f"commit: {report['live_commit']}",
        f"modules: {summary['module_count']}",
        "resolved REQUIRE occurrences: "
        f"{summary['resolved_require_occurrence_count']}",
        f"unique resolved edges: {summary['unique_resolved_edge_count']}",
        f"unresolved REQUIREs: {summary['unresolved_require_count']}",
        f"cycles: {summary['cycle_count']}",
        f"layer violations: {summary['layer_violation_count']}",
        f"placement debt modules: {summary['placement_debt_count']}",
        f"PROVIDED issues: {summary['provided_issue_count']}",
        f"addressability issues: {summary['addressability_issue_count']}",
        f"marker issues: {summary['marker_issue_count']}",
        f"graph sha256: {summary['graph_sha256']}",
        f"state sha256: {summary['state_sha256']}",
        f"placement sha256: {summary['placement_sha256']}",
        f"unresolved sha256: {summary['unresolved_sha256']}",
        "classes:",
    ]
    for name, facts in summary["class_totals"].items():
        lines.append(
            f"  {name}: {facts['modules']} modules, {facts['lines']} lines, "
            f"{facts['lexical_globals']} lexical globals"
        )
    return "\n".join(lines)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--policy",
        type=Path,
        default=DEFAULT_POLICY_PATH,
        help="architecture policy JSON",
    )
    parser.add_argument(
        "--format",
        choices=("summary", "json"),
        default="summary",
        help="report rendering",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when the live architecture differs from the reviewed baseline",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    policy = load_policy(args.policy)
    report = build_report(policy)

    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(_summary_text(report))

    if args.check:
        errors = check_report(report, policy)
        if errors:
            for error in errors:
                print(f"L0 ARCHITECTURE MISMATCH: {error}", file=sys.stderr)
            print(
                "Inspect the JSON report and update the reviewed policy only "
                "when the architectural change is intentional.",
                file=sys.stderr,
            )
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
