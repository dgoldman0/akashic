#!/usr/bin/env python3
"""Validate the reviewed L1 functional-preservation ledger.

This is deliberately a host-only ratchet.  It checks that the ledger's current
UIDL and direct-input surfaces still match source, named public/provider words
still exist, exact capability/service sets have not drifted, covered and
partial behavior has runnable evidence, and partial or prerequisite-only
behavior points at a concrete prerequisite.  It does not run emulator profiles
or pretend that source presence proves behavior.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LEDGER_PATH = Path(__file__).with_name(
    "refactor_functional_baseline.json"
)
HARNESS_PATH = Path(__file__).with_name("akashic_tui.py")
EXPECTED_APPLETS = {
    "agent",
    "daybook",
    "desk",
    "fexplorer",
    "grid",
    "library",
    "pad",
    "soundlab",
    "streams",
}
EXPECTED_DIRECT_INPUT_APPLETS = {
    "agent",
    "daybook",
    "desk",
    "grid",
    "library",
    "pad",
    "soundlab",
    "streams",
}
VALID_LANDINGS = {f"L{number}" for number in range(2, 15)}
VALID_COVERAGE = {"covered", "partial", "prerequisite"}


def load_ledger(path: Path = DEFAULT_LEDGER_PATH) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _defined_profile_names(text: str) -> set[str]:
    names = set(
        re.findall(r'^\s{4}"([^"]+)": Profile\(', text, re.MULTILINE)
    )
    names.update(
        re.findall(
            r'^PROFILES\["([^"]+)"\]\s*=', text, re.MULTILINE
        )
    )
    return names


def _profile_names() -> set[str]:
    return _defined_profile_names(HARNESS_PATH.read_text(encoding="utf-8"))


def _forth_word(text: str, word: str) -> str | None:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$)(.*?);",
        text,
        re.MULTILINE | re.DOTALL,
    )
    return None if match is None else match.group(0)


def _normalized_sha256(text: str) -> str:
    normalized = " ".join(text.split())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def _forth_strings(text: str) -> list[str]:
    """Return executable ``S\"`` bodies, excluding comments and other strings."""

    strings: list[str] = []
    index = 0
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
        if token.startswith("\\"):
            newline = text.find("\n", index)
            index = len(text) if newline < 0 else newline + 1
            continue
        if token == "(" or upper == ".(":
            close = text.find(")", index)
            index = len(text) if close < 0 else close + 1
            continue
        if upper in {'S"', 'C"', '."', 'ABORT"'}:
            close = text.find('"', index)
            if close < 0:
                break
            if upper == 'S"':
                strings.append(text[index:close].lstrip(" "))
            index = close + 1
    return strings


def _uidl_surface(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    menus = re.findall(r"<menu\s+label=([^\s/>]+)", text)
    actions = sorted(set(re.findall(r"\bdo=([^\s/>]+)", text)))
    element_ids = sorted(set(re.findall(r"\bid=([^\s/>]+)", text)))
    shortcuts: dict[str, str] = {}
    for line in text.splitlines():
        action = re.search(r"\bdo=([^\s/>]+)", line)
        key = re.search(r"\bkey=([^\s/>]+)", line)
        if not action or not key:
            continue
        previous = shortcuts.setdefault(action.group(1), key.group(1))
        if previous != key.group(1):
            raise ValueError(
                f"UIDL action {action.group(1)!r} has conflicting shortcuts"
            )
    return {
        "menus": menus,
        "actions": actions,
        "shortcuts": dict(sorted(shortcuts.items())),
        "element_ids": element_ids,
    }


def _check_evidence(reference: str, profiles: set[str]) -> str | None:
    if reference.startswith("profile:"):
        profile = reference.removeprefix("profile:")
        if profile not in profiles:
            return f"unknown emulator profile {profile!r}"
        return None

    if reference.startswith("pytest:"):
        node = reference.removeprefix("pytest:")
        if "::" not in node:
            return f"pytest evidence lacks an exact test node: {reference}"
        relative_path, test_name = node.rsplit("::", 1)
        path = REPOSITORY_ROOT / relative_path
        if not path.is_file():
            return f"pytest evidence file is missing: {relative_path}"
        text = path.read_text(encoding="utf-8")
        if not re.search(
            rf"^def\s+{re.escape(test_name)}\s*\(", text, re.MULTILINE
        ):
            return f"pytest evidence test is missing: {node}"
        return None

    if reference.startswith("driver:"):
        relative_path = reference.removeprefix("driver:")
        path = REPOSITORY_ROOT / relative_path
        if not path.is_file():
            return f"driver evidence file is missing: {relative_path}"
        if not path.read_text(encoding="utf-8").strip():
            return f"driver evidence file is empty: {relative_path}"
        return None

    return f"unknown evidence reference kind: {reference}"


def _duplicates(values: Iterable[str]) -> set[str]:
    seen: set[str] = set()
    duplicates: set[str] = set()
    for value in values:
        if value in seen:
            duplicates.add(value)
        seen.add(value)
    return duplicates


def check_ledger(ledger: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if ledger.get("schema") != "akashic.refactor.functional-preservation.v1":
        errors.append("unexpected or missing ledger schema")
    if not re.fullmatch(r"[0-9a-f]{40}", ledger.get("baseline_commit", "")):
        errors.append("baseline_commit must be a full lowercase Git object ID")
    if ledger.get("landing") != "L1":
        errors.append("ledger must identify Landing L1")
    if ledger.get("production_behavior_change") is not False:
        errors.append("L1 must not claim a production behavior change")

    required_facets = ledger.get("required_facets", [])
    if len(required_facets) != len(set(required_facets)) or not required_facets:
        errors.append("required_facets must be a nonempty unique list")
    required_facet_set = set(required_facets)

    scope = ledger.get("scope", {})
    included = scope.get("included_applets", [])
    if set(included) != EXPECTED_APPLETS or len(included) != len(EXPECTED_APPLETS):
        errors.append("scope must include exactly the nine active applet baselines")
    excluded = scope.get("excluded", {})
    if set(excluded) != {"game", "worlds"}:
        errors.append("scope must explicitly exclude Game and Worlds")

    applets = ledger.get("applets", [])
    applet_ids = [applet.get("id", "") for applet in applets]
    if set(applet_ids) != EXPECTED_APPLETS or len(applet_ids) != len(
        EXPECTED_APPLETS
    ):
        errors.append("applets must contain each active baseline exactly once")

    profiles = _profile_names()
    direct_input_applets: set[str] = set()
    all_behavior_ids: list[str] = []
    all_prerequisite_ids: list[str] = []

    for applet in applets:
        applet_id = applet.get("id", "<missing>")
        prefix = f"{applet_id}."
        landings = applet.get("active_landings", [])
        if not landings or len(landings) != len(set(landings)):
            errors.append(f"{applet_id}: active_landings must be nonempty and unique")
        invalid_landings = set(landings) - VALID_LANDINGS
        if invalid_landings:
            errors.append(
                f"{applet_id}: invalid active landings {sorted(invalid_landings)}"
            )

        uidl = applet.get("uidl_surface")
        if uidl is not None:
            uidl_path = REPOSITORY_ROOT / uidl.get("path", "")
            if not uidl_path.is_file():
                errors.append(f"{applet_id}: UIDL path is missing: {uidl_path}")
            else:
                live = _uidl_surface(uidl_path)
                expected = {
                    key: uidl.get(key)
                    for key in ("menus", "actions", "shortcuts", "element_ids")
                }
                if live != expected:
                    errors.append(
                        f"{applet_id}: UIDL action/menu/shortcut/element surface drifted"
                    )

        direct_inputs = applet.get("direct_input_contracts", [])
        if direct_inputs:
            direct_input_applets.add(applet_id)
        for contract in direct_inputs:
            relative_path = contract.get("path", "")
            source_path = REPOSITORY_ROOT / relative_path
            word = contract.get("word", "")
            bindings = contract.get("bindings", [])
            if not source_path.is_file():
                errors.append(
                    f"{applet_id}: direct-input path is missing: {relative_path}"
                )
                continue
            if not bindings or len(bindings) != len(set(bindings)):
                errors.append(
                    f"{applet_id}: {word} bindings must be nonempty and unique"
                )
            body = _forth_word(source_path.read_text(encoding="utf-8"), word)
            if body is None:
                errors.append(f"{applet_id}: direct-input word is missing: {word}")
            elif _normalized_sha256(body) != contract.get("sha256"):
                errors.append(f"{applet_id}: direct-input word drifted: {word}")

        capability = applet.get("capability_surface")
        if capability is None:
            errors.append(f"{applet_id}: missing exact capability surface")
        else:
            relative_path = capability.get("path", "")
            source_path = REPOSITORY_ROOT / relative_path
            if not source_path.is_file():
                errors.append(
                    f"{applet_id}: capability path is missing: {relative_path}"
                )
            else:
                prefix_value = capability.get("literal_prefix", "")
                ignored = set(capability.get("ignored_literals", []))
                live_ids = sorted(
                    {
                        value
                        for value in _forth_strings(
                            source_path.read_text(encoding="utf-8")
                        )
                        if value.startswith(prefix_value) and value not in ignored
                    }
                )
                if live_ids != capability.get("ids"):
                    errors.append(f"{applet_id}: exact capability ID set drifted")

        service = applet.get("service_surface")
        if service is not None:
            relative_path = service.get("path", "")
            source_path = REPOSITORY_ROOT / relative_path
            word = service.get("word", "")
            if not source_path.is_file():
                errors.append(
                    f"{applet_id}: service path is missing: {relative_path}"
                )
            else:
                body = _forth_word(source_path.read_text(encoding="utf-8"), word)
                if body is None:
                    errors.append(f"{applet_id}: service setup word is missing: {word}")
                elif _forth_strings(body) != service.get("ids"):
                    errors.append(f"{applet_id}: exact service ID set drifted")

        for contract in applet.get("source_contracts", []):
            relative_path = contract.get("path", "")
            source_path = REPOSITORY_ROOT / relative_path
            if not source_path.is_file():
                errors.append(
                    f"{applet_id}: source contract path is missing: {relative_path}"
                )
                continue
            source = source_path.read_text(encoding="utf-8")
            literals = contract.get("required_literals", [])
            if not literals or len(literals) != len(set(literals)):
                errors.append(
                    f"{applet_id}: {relative_path} literals must be nonempty and unique"
                )
            for literal in literals:
                if literal not in source:
                    errors.append(
                        f"{applet_id}: {literal!r} disappeared from {relative_path}"
                    )

        prerequisites = applet.get("prerequisites", [])
        prerequisite_ids = [item.get("id", "") for item in prerequisites]
        all_prerequisite_ids.extend(prerequisite_ids)
        if _duplicates(prerequisite_ids):
            errors.append(f"{applet_id}: duplicate prerequisite IDs")
        for item in prerequisites:
            prerequisite_id = item.get("id", "")
            if not prerequisite_id.startswith(prefix):
                errors.append(
                    f"{applet_id}: prerequisite ID must use the applet prefix"
                )
            if item.get("before_landing") not in landings:
                errors.append(
                    f"{prerequisite_id}: before_landing is not an active landing"
                )
            for field in ("trigger", "characterization", "reason"):
                if not item.get(field, "").strip():
                    errors.append(f"{prerequisite_id}: missing {field}")

        facet_coverage = set(applet.get("not_applicable", {}))
        behaviors = applet.get("behaviors", [])
        behavior_ids = [behavior.get("id", "") for behavior in behaviors]
        all_behavior_ids.extend(behavior_ids)
        if not behaviors or _duplicates(behavior_ids):
            errors.append(f"{applet_id}: behaviors must be nonempty with unique IDs")
        referenced_prerequisites: set[str] = set()
        for behavior in behaviors:
            behavior_id = behavior.get("id", "")
            if not behavior_id.startswith(prefix):
                errors.append(f"{applet_id}: behavior ID must use the applet prefix")
            coverage = behavior.get("coverage")
            if coverage not in VALID_COVERAGE:
                errors.append(f"{behavior_id}: invalid coverage state {coverage!r}")
            facets = set(behavior.get("facets", []))
            if not facets or not facets <= required_facet_set:
                errors.append(f"{behavior_id}: has missing or unknown facets")
            facet_coverage.update(facets)
            if not behavior.get("preserve") or any(
                not item.strip() for item in behavior.get("preserve", [])
            ):
                errors.append(f"{behavior_id}: preserve statements must be nonempty")
            evidence = behavior.get("evidence", [])
            if len(evidence) != len(set(evidence)):
                errors.append(f"{behavior_id}: evidence must be unique")
            if coverage in {"covered", "partial"} and not evidence:
                errors.append(f"{behavior_id}: covered/partial behavior lacks evidence")
            if coverage == "prerequisite" and evidence:
                errors.append(f"{behavior_id}: prerequisite-only behavior claims evidence")
            for reference in evidence:
                evidence_error = _check_evidence(reference, profiles)
                if evidence_error:
                    errors.append(f"{behavior_id}: {evidence_error}")

            linked = behavior.get("prerequisite_ids", [])
            if coverage == "covered" and linked:
                errors.append(f"{behavior_id}: covered behavior links prerequisites")
            if coverage in {"partial", "prerequisite"} and not linked:
                errors.append(
                    f"{behavior_id}: {coverage} behavior lacks a prerequisite"
                )
            unknown = set(linked) - set(prerequisite_ids)
            if unknown:
                errors.append(
                    f"{behavior_id}: unknown prerequisites {sorted(unknown)}"
                )
            referenced_prerequisites.update(linked)

        unreferenced = set(prerequisite_ids) - referenced_prerequisites
        if unreferenced:
            errors.append(
                f"{applet_id}: unreferenced prerequisites {sorted(unreferenced)}"
            )
        missing_facets = required_facet_set - facet_coverage
        extra_not_applicable = set(applet.get("not_applicable", {})) - required_facet_set
        if missing_facets:
            errors.append(f"{applet_id}: missing facets {sorted(missing_facets)}")
        if extra_not_applicable:
            errors.append(
                f"{applet_id}: unknown not-applicable facets {sorted(extra_not_applicable)}"
            )

        for reference in applet.get("supplemental_evidence", []):
            evidence_error = _check_evidence(reference, profiles)
            if evidence_error:
                errors.append(f"{applet_id}: supplemental {evidence_error}")

    if _duplicates(all_behavior_ids):
        errors.append("behavior IDs must be globally unique")
    if _duplicates(all_prerequisite_ids):
        errors.append("prerequisite IDs must be globally unique")
    if direct_input_applets != EXPECTED_DIRECT_INPUT_APPLETS:
        errors.append(
            "direct-input contracts must cover exactly the applets with "
            "applet-specific non-UIDL bindings"
        )
    return errors


def summary(ledger: dict[str, Any]) -> dict[str, int]:
    behaviors = [
        behavior
        for applet in ledger["applets"]
        for behavior in applet["behaviors"]
    ]
    return {
        "applets": len(ledger["applets"]),
        "behavior_groups": len(behaviors),
        "fully_covered_groups": sum(
            behavior["coverage"] == "covered" for behavior in behaviors
        ),
        "partial_groups": sum(
            behavior["coverage"] == "partial" for behavior in behaviors
        ),
        "prerequisite_only_groups": sum(
            behavior["coverage"] == "prerequisite" for behavior in behaviors
        ),
        "prerequisites": sum(
            len(applet["prerequisites"]) for applet in ledger["applets"]
        ),
        "evidence_references": sum(
            len(behavior["evidence"]) for behavior in behaviors
        ),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate the ledger")
    parser.add_argument(
        "--ledger", type=Path, default=DEFAULT_LEDGER_PATH, help="ledger path"
    )
    args = parser.parse_args(argv)
    if not args.check:
        parser.error("--check is required")
    ledger = load_ledger(args.ledger)
    errors = check_ledger(ledger)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    counts = summary(ledger)
    print(
        "L1 functional baseline OK: "
        f"{counts['applets']} applets, "
        f"{counts['behavior_groups']} behavior groups "
        f"({counts['fully_covered_groups']} covered, "
        f"{counts['partial_groups']} partial, "
        f"{counts['prerequisite_only_groups']} prerequisite-only), "
        f"{counts['prerequisites']} prerequisites, "
        f"{counts['evidence_references']} evidence references"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
