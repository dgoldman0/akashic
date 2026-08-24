#!/usr/bin/env python3
"""Structural contracts for the neutral retained-presentation API seam."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"
API = AKASHIC_ROOT / "tui" / "presentation" / "api.f"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402


STATUS_CONSTANTS = {
    "PRES-S-OK": 0,
    "PRES-S-WOULD-BLOCK": 1,
    "PRES-S-UNAVAILABLE": 2,
    "PRES-S-CAPACITY": 3,
    "PRES-S-STALE": 4,
    "PRES-S-INVALID": 5,
    "PRES-S-SESSION-LOST": 6,
    "PRES-S-SOURCE": 7,
}

DISPATCH_PAIRS = {
    "PRES-SERVICE-INIT": "PRES-API.SERVICE-INIT-XT",
    "PRES-SERVICE-FINI": "PRES-API.SERVICE-FINI-XT",
    "PRES-SERVICE-STATUS@": "PRES-API.SERVICE-STATUS-XT",
    "PRES-SERVICE-STEP": "PRES-API.SERVICE-STEP-XT",
    "PRES-SCOPE-ACQUIRE": "PRES-API.SCOPE-ACQUIRE-XT",
    "PRES-SCOPE-STATUS@": "PRES-API.SCOPE-STATUS-XT",
    "PRES-BATCH-BEGIN": "PRES-API.BATCH-BEGIN-XT",
    "PRES-ITEM-DEFINE": "PRES-API.ITEM-DEFINE-XT",
    "PRES-RESOURCE-DEFINE": "PRES-API.RESOURCE-DEFINE-XT",
    "PRES-SERIES-DEFINE": "PRES-API.SERIES-DEFINE-XT",
    "PRES-SCALAR-SET": "PRES-API.SCALAR-SET-XT",
    "PRES-SERIES-SET": "PRES-API.SERIES-SET-XT",
    "PRES-VISIBILITY-SET": "PRES-API.VISIBILITY-SET-XT",
    "PRES-DROP": "PRES-API.DROP-XT",
    "PRES-BATCH-COMMIT": "PRES-API.BATCH-COMMIT-XT",
    "PRES-BATCH-ABORT": "PRES-API.BATCH-ABORT-XT",
    "PRES-HOST-BOUNDS!": "PRES-API.HOST-BOUNDS-XT",
    "PRES-HOST-RETIRE": "PRES-API.HOST-RETIRE-XT",
}


def _source() -> str:
    return API.read_text(encoding="utf-8")


def _code(source: str) -> str:
    return "\n".join(
        line.split("\\", 1)[0]
        for line in source.splitlines()
        if not line.lstrip().startswith("\\")
    )


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def test_api_is_a_backend_neutral_service_endpoint_leaf() -> None:
    source = _source()
    code = _code(source)
    closure = set(
        dependency_closure(AKASHIC_ROOT, ("tui/presentation/api.f",))
    )

    assert re.findall(
        r"^REQUIRE\s+(.+?)\s*$", source, re.MULTILINE
    ) == [
        "../../interop/service-endpoint.f",
        "../../utils/memory-span.f",
    ]
    assert closure == {
        "tui/presentation/api.f",
        "interop/service-endpoint.f",
        "runtime/instance.f",
        "utils/memory-span.f",
        "utils/uint-range.f",
    }
    assert re.findall(
        r"^PROVIDED\s+(\S+)\s*$", source, re.MULTILINE
    ) == ["akashic-tui-pres-api"]
    assert len("akashic-tui-pres-api".encode("ascii")) <= 23

    for forbidden in (
        "presentation-terminal.f",
        "PT-SESSION",
        "PT-",
        "APTSCB",
        "UART",
        "XMEM",
        "XBUF",
        "ALLOCATE",
        "ALLOT",
        "CREATE",
    ):
        assert forbidden not in code


def test_statuses_and_global_discovery_are_exact() -> None:
    source = _source()
    for name, value in STATUS_CONSTANTS.items():
        assert re.search(
            rf"^\s*{value}\s+CONSTANT\s+{re.escape(name)}\s*$",
            source,
            re.MULTILINE,
        ), name

    service_id = _definition(source, "PRES-SERVICE-ID")
    discovery = _definition(source, "PRES-BROKER-DISCOVER")
    assert 'S" org.akashic.tui.presentation.v1"' in service_id
    assert "PRES-SERVICE-ID" in discovery
    assert "CINST-SERVICE" in discovery


def test_function_table_is_fixed_shape_but_owns_no_service_capacity() -> None:
    source = _source()
    code = _code(source)

    assert "1 CONSTANT PRES-API-ABI-VERSION" in source
    assert "176 CONSTANT PRES-API-SIZE" in source
    assert "16 CONSTANT PRES-BROKER-HEADER-SIZE" in source
    assert "16 CONSTANT PRES-SCOPE-HEADER-SIZE" in source
    assert "18 CONSTANT _PRES-API-CALLBACK-COUNT" in source
    assert "PRES-API-INIT" in source
    assert "PRES-API-VALID?" in source
    assert "_PRES-BROKER-BIND" in source
    assert "_PRES-SCOPE-BIND" in source
    assert not re.search(
        r"^:\s+PRES-(?:BROKER|SCOPE)-BIND\b", source, re.MULTILINE
    )

    callback_offsets = tuple(
        int(offset)
        for offset in re.findall(
            r"^\s*(\d+)\s+CONSTANT\s+_PRES-API-O-[A-Z-]+-XT\s*$",
            source,
            re.MULTILINE,
        )
    )
    assert callback_offsets == tuple(range(32, 176, 8))

    limit_code = code.replace("PRES-S-CAPACITY", "")
    assert not re.search(
        r"\b(?:CAPACITY|MAX-(?:ITEM|RESOURCE|SERIES|BYTE|OP)|QUEUE-LIMIT)\b",
        limit_code,
    )
    assert not re.search(r"^:\s+PRES-SCOPE\.", source, re.MULTILINE)


def test_every_normative_operation_dispatches_through_the_backend_table() -> None:
    source = _source()
    for wrapper, field in DISPATCH_PAIRS.items():
        definition = _definition(source, wrapper)
        assert field in definition, wrapper
        assert "EXECUTE" in definition, wrapper

    acquire = _definition(source, "PRES-SCOPE-ACQUIRE")
    assert "_PRES-BROKER-VALID?" in acquire
    assert "_PRES-SCOPE-VALID?" in acquire
    assert "PRES-STATUS-VALID?" in acquire
    assert "DUP >R" in acquire
    assert "_PRES-H.API @ R@ <>" in acquire
    dispatch = "R@ PRES-API.SCOPE-ACQUIRE-XT @ EXECUTE"
    assert dispatch in acquire
    assert f"DUP {dispatch}" not in acquire
    assert re.search(
        r"^:\s+PRES-SCOPE-ACQUIRE\s+"
        r"\(\s*caller-instance\s+broker\s+--\s+scope\s+status\s*\)",
        acquire,
    )
    assert "R> DROP PRES-S-OK" in acquire

    for wrapper in DISPATCH_PAIRS.keys() - {
        "PRES-SCOPE-ACQUIRE",
        "PRES-SERVICE-STEP",
    }:
        assert "_PRES-NORMALIZE-STATUS" in _definition(source, wrapper)


def test_header_binding_rejects_every_known_alias_before_writing() -> None:
    source = _source()
    broker_bind = _definition(source, "_PRES-BROKER-BIND")
    scope_bind = _definition(source, "_PRES-SCOPE-BIND")

    assert "PRES-API-SIZE" in broker_bind
    assert "PRES-BROKER-HEADER-SIZE" in broker_bind
    assert "MSPAN-OVERLAP?" in broker_bind
    assert broker_bind.index("MSPAN-OVERLAP?") < broker_bind.index(
        "_PRES-H.API !"
    )

    assert "PRES-BROKER-HEADER-SIZE" in scope_bind
    assert "PRES-SCOPE-HEADER-SIZE" in scope_bind
    assert "PRES-API-SIZE" in scope_bind
    assert scope_bind.count("MSPAN-OVERLAP?") == 2
    assert scope_bind.rindex("MSPAN-OVERLAP?") < scope_bind.index(
        "_PRES-H.API !"
    )

    for definition in (broker_bind, scope_bind):
        assert definition.index("MSPAN-NONWRAPPING?") < definition.index(
            "_PRES-H.API !"
        )

    broker_valid = _definition(source, "_PRES-BROKER-VALID?")
    scope_valid = _definition(source, "_PRES-SCOPE-VALID?")
    assert "PRES-BROKER-HEADER-SIZE SWAP _PRES-H-API-DISJOINT?" in (
        broker_valid
    )
    assert "PRES-SCOPE-HEADER-SIZE SWAP _PRES-H-API-DISJOINT?" in (
        scope_valid
    )

    acquire = _definition(source, "PRES-SCOPE-ACQUIRE")
    assert "PRES-SCOPE-HEADER-SIZE R@ PRES-BROKER-HEADER-SIZE" in acquire
    assert "MSPAN-OVERLAP?" in acquire


def test_child_scene_surface_carries_only_descriptors_and_opaque_scope() -> None:
    source = _source()
    child_words = (
        "PRES-BATCH-BEGIN",
        "PRES-ITEM-DEFINE",
        "PRES-RESOURCE-DEFINE",
        "PRES-SERIES-DEFINE",
        "PRES-SCALAR-SET",
        "PRES-SERIES-SET",
        "PRES-VISIBILITY-SET",
        "PRES-DROP",
        "PRES-BATCH-COMMIT",
        "PRES-BATCH-ABORT",
        "PRES-SCOPE-STATUS@",
    )
    for word in child_words:
        definition = _definition(source, word)
        stack = re.search(r"\((.*?)\)", definition, re.DOTALL)
        assert stack is not None, word
        effect = stack.group(1).lower()
        assert "scope" in effect, word
        for forbidden in (
            "session",
            "epoch",
            "owner-id",
            "generation",
            "region-id",
            "object-id",
            "resource-id",
            "opcode",
            "frame",
        ):
            assert forbidden not in effect, (word, forbidden)
