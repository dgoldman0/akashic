#!/usr/bin/env python3
"""Structural contracts for caller-bounded presentation authority."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"
BROKER = AKASHIC_ROOT / "tui" / "presentation" / "broker.f"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402


CALLBACK_FIELDS = (
    "PRES-API.SERVICE-INIT-XT",
    "PRES-API.SERVICE-FINI-XT",
    "PRES-API.SERVICE-STATUS-XT",
    "PRES-API.SERVICE-STEP-XT",
    "PRES-API.SCOPE-ACQUIRE-XT",
    "PRES-API.SCOPE-STATUS-XT",
    "PRES-API.BATCH-BEGIN-XT",
    "PRES-API.ITEM-DEFINE-XT",
    "PRES-API.RESOURCE-DEFINE-XT",
    "PRES-API.SERIES-DEFINE-XT",
    "PRES-API.SCALAR-SET-XT",
    "PRES-API.SERIES-SET-XT",
    "PRES-API.VISIBILITY-SET-XT",
    "PRES-API.DROP-XT",
    "PRES-API.BATCH-COMMIT-XT",
    "PRES-API.BATCH-ABORT-XT",
    "PRES-API.HOST-BOUNDS-XT",
    "PRES-API.HOST-RETIRE-XT",
)


def _source() -> str:
    return BROKER.read_text(encoding="utf-8")


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


def test_broker_is_a_neutral_caller_bounded_backend_leaf() -> None:
    source = _source()
    code = _code(source)
    closure = set(
        dependency_closure(AKASHIC_ROOT, ("tui/presentation/broker.f",))
    )

    assert re.findall(
        r"^REQUIRE\s+(.+?)\s*$", source, re.MULTILINE
    ) == ["api.f"]
    assert closure == {
        "tui/presentation/broker.f",
        "tui/presentation/api.f",
        "interop/service-endpoint.f",
        "runtime/instance.f",
        "utils/memory-span.f",
        "utils/uint-range.f",
    }
    assert re.findall(
        r"^PROVIDED\s+(\S+)\s*$", source, re.MULTILINE
    ) == ["akashic-tui-pres-broker"]
    assert len("akashic-tui-pres-broker".encode("ascii")) <= 23

    for forbidden in (
        "ALLOCATE",
        "ALLOT",
        "CREATE",
        "presentation-terminal.f",
        "PT-SESSION",
        "UART",
        "XMEM",
        "XBUF",
        "DESK-",
        "SOUNDLAB",
    ):
        assert forbidden not in code

    assert "PRES-BROKER-C.SCOPE-RECORDS" in source
    assert "PRES-BROKER-C.SCOPE-RECORD-BYTES" in source
    assert "PRES-BROKER-C.SCOPE-RECORD-COUNT" in source
    record_bytes = _definition(source, "_PBR-RECORD-BYTES?")
    assert "PRES-SCOPE-RECORD-SIZE *" in record_bytes
    assert "_PBR-RECORD-COUNT-MAX U>" in record_bytes
    assert not re.search(r"\b(?:MAX-SCOPES|SCOPE-CAPACITY)\b", code)


def test_configuration_and_binding_preflight_every_span_before_mutation() -> None:
    source = _source()
    config_valid = _definition(source, "PRES-BROKER-CONFIG-VALID?")
    preflight = _definition(source, "_PBR-INIT-PREFLIGHT")
    service_init = _definition(source, "_PBR-SERVICE-INIT")
    bind = _definition(source, "PRES-SCOPED-BROKER-BIND")

    assert "_PRES-CELL-ALIGNED?" in config_valid
    assert config_valid.count("MSPAN-NONWRAPPING?") == 2
    assert "_PBR-RECORD-BYTES?" in config_valid
    assert "MSPAN-OVERLAP? 0= NIP" in config_valid

    assert preflight.count("MSPAN-OVERLAP?") == 5
    assert "_PBR.MAGIC @ 0<>" in preflight
    assert "_PBR-STATE-UNINITIALIZED <>" in preflight
    assert "PRES-S-CAPACITY EXIT" in preflight
    assert service_init.index("_PBR-INIT-PREFLIGHT") < service_init.index(
        "0 FILL"
    )
    assert service_init.index("_PBR-INIT-PREFLIGHT") < service_init.index(
        "_PBR.RESOLVER-XT !"
    )

    assert "_PBR-API-OURS?" in bind
    assert "_PBR.MAGIC @ 0<>" in bind
    assert "_PBR-BROKER-EXTENSION-ZERO?" in bind
    first_write = bind.index("_PRES-BROKER-BIND")
    assert bind.index("MSPAN-NONWRAPPING?") < first_write
    assert bind.index("MSPAN-OVERLAP?") < first_write
    assert bind.index("_PBR.MAGIC @ 0<>") < first_write
    assert bind.index("_PBR-BROKER-EXTENSION-ZERO?") < first_write


def test_backend_api_writes_each_callback_exactly_once() -> None:
    source = _source()
    api_init = _definition(source, "PRES-BROKER-API-INIT")
    api_check = _definition(source, "_PBR-API-OURS?")

    assert api_init.count("PRES-API-INIT") == 1
    for field in CALLBACK_FIELDS:
        assert api_init.count(f"{field} !") == 1, field
        assert api_check.count(f"{field} @") == 1, field
    assert len(re.findall(r"PRES-API\.[A-Z-]+-XT\s+!", api_init)) == 18

    descriptor_stub = _definition(source, "_PBR-SCENE-DESCRIPTOR")
    scope_stub = _definition(source, "_PBR-SCENE-SCOPE")
    for stub in (descriptor_stub, scope_stub):
        assert "_PBR-SCOPE-STATUS-CORE" in stub
        assert "PRES-S-UNAVAILABLE" in stub
        assert "!" not in _code(stub)


def test_resolver_is_exact_borrowed_and_checked_before_authority_mutation() -> None:
    source = _source()
    resolve = _definition(source, "_PBR-RESOLVE")
    external = _definition(source, "_PBR-ACTIVATION-EXTERNAL?")
    acquire = _definition(source, "_PBR-SCOPE-ACQUIRE")
    new_live = _definition(source, "_PBR-NEW-LIVE")

    assert "caller-instance resolver-context -- activation-desc status" in source
    assert "non-yielding and non-reentrant" in source
    assert resolve.index("EXECUTE") < resolve.index(
        "PRES-ACTIVATION-DESC-VALID?"
    )
    assert resolve.index("PRES-ACTIVATION-DESC-VALID?") < resolve.index(
        "_PBR-ACTIVATION-EXTERNAL?"
    )
    assert external.count("MSPAN-OVERLAP?") == 3

    assert acquire.index("_PBR-RESOLVE") < acquire.index("_PBR.SUPPORTED @")
    assert acquire.index("_PBR-RESOLVE") < acquire.index("_PBR-FIND-EXACT")
    assert acquire.index("_PBR-FIND-EXACT") < acquire.index(
        "_PBR-FIND-ID"
    )
    assert acquire.index("_PBR-FIND-ID") < acquire.index(
        "_PBR-FIND-LIVE-CALLER"
    )
    assert acquire.index("_PBR-FIND-LIVE-CALLER") < acquire.index(
        "_PBR-FIND-FREE"
    )
    assert re.search(
        r"_PBRR-ID\s+@\s+_PBRA-BROKER\s+@\s+_PBR-FIND-ID\s+IF\s+"
        r"0\s+PRES-S-STALE\s+EXIT\s+THEN",
        acquire,
    )
    assert re.search(
        r"_PBRA-CALLER\s+@\s+_PBRA-BROKER\s+@\s+"
        r"_PBR-FIND-LIVE-CALLER\s+IF\s+"
        r"0\s+PRES-S-STALE\s+EXIT\s+THEN",
        acquire,
    )
    assert "_PBS.LIVE-CALLER @" in acquire
    assert "_PBRA-CALLER @ <> IF 0 PRES-S-STALE EXIT THEN" in acquire
    record_status_tail = acquire.split("_PBR-RECORD-STATUS", 1)[1]
    assert "0 SWAP EXIT" in record_status_tail
    assert "NIP" not in record_status_tail.split("_PBR-FIND-ID", 1)[0]

    for field in ("_PBS.ID !", "_PBS.GENERATION !", "_PBS.LIVE-CALLER !"):
        assert new_live.index(field) < new_live.index("_PBS.STATE !")
    assert new_live.index("_PBS.STATE !") < new_live.index(
        "_PBR.LIVE-COUNT +!"
    )


def test_zero_caller_and_exact_bounds_paths_fail_closed() -> None:
    source = _source()
    acquire = _definition(source, "_PBR-SCOPE-ACQUIRE")
    bounds = _definition(source, "_PBR-HOST-BOUNDS")
    retire = _definition(source, "_PBR-HOST-RETIRE")

    assert "_PBRA-CALLER @ 0= IF 0 PRES-S-INVALID EXIT THEN" in acquire
    assert "_PBRH-CALLER @ 0= IF PRES-S-INVALID EXIT THEN" in bounds
    assert "_PBRT-CALLER @ 0= IF PRES-S-INVALID EXIT THEN" in retire

    assert bounds.index("_PBR-BOUNDS-VALID?") < bounds.index("_PBR-RESOLVE")
    assert bounds.index("_PBR-RESOLVE") < bounds.index(
        "_PBR-HOST-BOUNDS-MATCH?"
    )
    assert bounds.index("_PBR-HOST-BOUNDS-MATCH?") < bounds.index(
        "_PBR-FIND-EXACT"
    )
    assert "_PBR-RECORD-STATUS" in bounds
    assert "_PBS.LIVE-CALLER @" in bounds


def test_retire_detaches_by_exact_live_caller_even_if_resolver_fails() -> None:
    source = _source()
    retire = _definition(source, "_PBR-HOST-RETIRE")
    transition = _definition(source, "_PBR-RETIRE-LIVE")

    assert retire.index("_PBR-FIND-LIVE-CALLER") < retire.index(
        "_PBR-RESOLVE"
    )
    resolver_failure = re.search(
        r"_PBR-RESOLVE\s+\?DUP\s+IF(?P<body>.*?)THEN\s+EXIT",
        retire,
        re.DOTALL,
    )
    assert resolver_failure is not None
    assert "_PBR-RETIRE-LIVE" in resolver_failure.group("body")
    assert "PRES-S-OK" in resolver_failure.group("body")

    for field in (
        "_PBS.RESOURCE-XT !",
        "_PBS.RESOURCE-CTX !",
        "_PBS.SERIES-XT !",
        "_PBS.SERIES-CTX !",
        "_PBS.LIVE-CALLER !",
    ):
        assert transition.index(field) < transition.index("_PBS.STATE !")
    assert "_PBR-SCOPE-RETIRE-PENDING" in transition
    assert transition.index("_PBR.LIVE-COUNT @ 0>") < transition.index(
        "_PBR.LIVE-COUNT +!"
    )
    assert transition.index("_PBR.PENDING-COUNT @") < transition.index(
        "_PBR.PENDING-COUNT +!"
    )
    assert transition.index("_PBR.RECORD-COUNT @ U<") < transition.index(
        "_PBR.PENDING-COUNT +!"
    )
    assert "_PBR.LIVE-COUNT +!" in transition
    assert "_PBR.PENDING-COUNT +!" in transition
    assert "_PBR-SCOPE-FREE" not in transition

    step = _definition(source, "_PBR-SERVICE-STEP")
    fini = _definition(source, "_PBR-SERVICE-FINI")
    assert "_PBR.PENDING-COUNT @" in step
    assert "PRES-S-WOULD-BLOCK -1" in step
    assert "_PBR.PENDING-COUNT @ OR" in fini
    assert "PRES-S-WOULD-BLOCK" in fini
    assert "PRES-BROKER-RETIREMENT-PENDING@" in source


def test_scope_status_rejects_foreign_and_malformed_records() -> None:
    source = _source()
    status = _definition(source, "_PBR-RECORD-STATUS")
    public_status = _definition(source, "_PBR-SCOPE-STATUS-CORE")

    for check in (
        "_PBR-RECORD-BELONGS?",
        "_PRES-SCOPE-VALID?",
        "_PRES-H.API @",
        "_PBS.BROKER @",
        "_PBS.ID @",
        "_PBS.GENERATION @",
        "_PBR-BOUNDS-VALID?",
    ):
        assert check in status
    assert "_PBS.LIVE-CALLER @" in status
    assert "_PBS.RESOURCE-XT @" in status
    assert "_PBS.SERIES-XT @" in status
    assert "PRES-S-STALE" in status
    assert "_PBR-BROKER-VALID?" in public_status
    assert "_PBR-STATE-READY <>" in public_status
