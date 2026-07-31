#!/usr/bin/env python3
"""Static contracts for the final transient Desk sandbox composition gate."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402
from akashic_tui import (  # noqa: E402
    MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
    PROFILES,
    _coalesce_audited_forth_lines,
    _linked_autoexec,
    _linked_chunks,
    dependency_order,
)


SERVICE = "tui/applets/desk/sandbox-service.f"
SERVICE_ENDPOINT = "interop/service-endpoint.f"
FIXTURE = LOCAL_TESTING / "sandbox-stage4-desk-service.f"
HARNESS = LOCAL_TESTING / "akashic_tui.py"


def _source(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def test_final_profile_has_only_the_service_discovery_closure() -> None:
    harness = _source(HARNESS)
    profile = harness.split(
        'PROFILES["sandbox-stage4-desk-service"] = Profile(', 1
    )[1].split('PROFILES["sandbox-core-contracts"]', 1)[0]

    roots = re.search(r"roots=\((.*?)\),", profile, re.DOTALL)
    assert roots is not None
    assert re.findall(r'"([^"]+\.f)"', roots.group(1)) == [
        SERVICE,
        SERVICE_ENDPOINT,
    ]
    assert "linked=True" in profile
    assert (
        "audited_link_line_bytes="
        "MEGAPAD_EVALUATE_SOURCE_MAX_BYTES"
    ) in profile
    assert (
        "audited_initial_forth_line_bytes="
        "MEGAPAD_EVALUATE_SOURCE_MAX_BYTES"
    ) in profile
    assert "_sandbox_stage4_desk_service_fixture_bytes()" in profile
    assert "sandbox-stage4-desk-service.f" in harness


def test_final_profile_chunks_keep_exact_module_and_evaluator_boundaries() -> None:
    profile = PROFILES["sandbox-stage4-desk-service"]
    modules = dependency_order(profile.roots)
    chunks = _linked_chunks(
        modules,
        profile.link_chunk_bytes,
        profile.audited_link_line_bytes,
    )

    expected_provided = []
    for module in modules:
        source = _source(AKASHIC_ROOT / module)
        match = re.search(
            r"^\s*PROVIDED\s+(\S+)\s*$",
            source,
            re.MULTILINE,
        )
        assert match is not None, module
        expected_provided.append(f"PROVIDED {match.group(1)}".encode())

    assert chunks
    lines = [line for chunk in chunks.values() for line in chunk.splitlines()]
    assert all(
        len(line) <= MEGAPAD_EVALUATE_SOURCE_MAX_BYTES
        for line in lines
    )
    assert [line for line in lines if line.startswith(b"PROVIDED ")] == (
        expected_provided
    )

    autoexec = _linked_autoexec(
        profile.autoexec,
        tuple(chunks),
        modules,
    )
    require_offsets = [
        autoexec.index(f"REQUIRE {chunk}")
        for chunk in chunks
    ]
    assert require_offsets == sorted(require_offsets)
    assert require_offsets[-1] < autoexec.index(
        "REQUIRE local_testing/sbox-s4-desk-service.f"
    )


def test_final_profile_coalesces_the_executable_fixture_at_the_tib_limit() -> None:
    profile = PROFILES["sandbox-stage4-desk-service"]
    fixture_path, fixture_source = profile.initial_files[0]
    compact = _coalesce_audited_forth_lines(
        fixture_source,
        profile.audited_initial_forth_line_bytes,
    )

    assert fixture_path == "local_testing/sbox-s4-desk-service.f"
    assert len(compact.splitlines()) < len(fixture_source.splitlines())
    assert all(
        len(line) <= MEGAPAD_EVALUATE_SOURCE_MAX_BYTES
        for line in compact.splitlines()
    )
    assert b" ".join(compact.splitlines()).split() == (
        b" ".join(fixture_source.splitlines()).split()
    )


def test_final_profile_excludes_unrelated_runtime_concerns() -> None:
    closure = dependency_closure(
        AKASHIC_ROOT,
        (SERVICE, SERVICE_ENDPOINT),
    )

    assert "runtime/sandbox-module-owner.f" in closure
    assert "runtime/sandbox-host.f" in closure
    assert "tui/applets/desk/sandbox-admission.f" in closure
    assert "tui/applets/desk/sandbox-component.f" in closure
    for forbidden in (
        "interop/endpoint.f",
        "request-bus",
        "schema",
        "digest",
        "cache",
        "vfs",
        "/agent/",
        "provider",
        "/library/",
        "/pad/",
        "sandbox/compiler.f",
        "sandbox/verifier.f",
    ):
        assert not any(forbidden in f"/{module.lower()}" for module in closure)


def test_fixture_uses_the_public_discovery_job_and_receipt_path() -> None:
    fixture = _source(FIXTURE)

    assert "PROVIDED sbox-s4-desk-service" in fixture
    assert "DESK-SBOX-JOB-CAPACITY" not in fixture
    assert "DESK-SBOX-JOB-SERVICE-SIZE" not in fixture
    assert fixture.count('S" org.akashic.sandbox.pure-compute"') >= 1
    assert "CINST-SERVICE" in fixture
    assert fixture.count("DESK-SBOX-JOB-SUBMIT") == 1
    assert fixture.count("DESK-SBOX-JOB-SERVICE-TICK") == 1
    assert fixture.count("DESK-SBOX-JOB-RESULT-TAKE") == 1
    assert "DESK-SBOX-RECEIPT-ACTIVATION@" in fixture
    assert "DESK-SBOX-RECEIPT-MODULE@" in fixture
    assert "DESK-SBOX-RECEIPT-PAYLOAD@" in fixture
    assert "DESK-SBOX-RECEIPT-RELEASE" in fixture
    assert "DESK-SBOX-JOB-SERVICE-RELEASE" in fixture
    assert "SBOX-PLAN-PUBLISH-VERIFIED" in fixture
    assert "SBOX-COMPILE" not in fixture
    assert "SBOX-VERIFY" not in fixture


def test_fixture_reports_caught_failures_with_the_active_phase() -> None:
    fixture = _source(FIXTURE)
    run = _definition(fixture, "_S4-RUN")
    failure = _definition(fixture, "_S4-FAIL")
    depth = _definition(fixture, "_4D?")

    assert "['] _S4-BODY CATCH" in run
    assert "_S4-FAIL EXIT" in run
    assert "DEPTH _4W @ -" in depth
    assert "OVER _4U0 !" in depth
    assert "2 PICK _4U1 !" in depth
    assert "?DUP IF THROW THEN" in depth
    assert "SBOX STAGE4 DESK SERVICE FAIL PHASE" in failure
    assert "_4F @" in failure
    assert "STATUS" in failure
    assert '" TOP "' in failure
    assert "_4U0 @" in failure
    assert '" NEXT "' in failure
    assert "_4U1 @" in failure
    assert "TX-FLUSH" in failure


def test_fixture_measures_capacity_four_and_uses_the_bounded_scheduler() -> None:
    fixture = _source(FIXTURE)
    candidate = _definition(fixture, "_4EC")
    limit_store = _definition(fixture, "_4L!")
    limits = _definition(fixture, "_4MI")
    init = _definition(fixture, "_S4-RUNTIME-INIT")
    discovery = _definition(fixture, "_4PS")
    invoke_take = _definition(fixture, "_S4-INVOKE-TAKE")

    assert "_4C _4CU 0 FILL" not in candidate
    assert "SBOX-VALUE-LIMIT!" in limit_store
    assert "_SVL-NTH" not in limit_store
    assert "SBOX-VALUE-LIMITS-BEGIN" in limits
    assert "SBOX-VALUE-LIMITS-SEAL" in limits
    assert "DESK-SBOX-JOB-SERVICE-STATE@" in discovery
    assert "_DSJ.STATE" not in discovery

    measured = re.search(
        r"(?P<capacity>4|_4S[A-Z0-9-]*)\s+"
        r"DESK-SBOX-JOB-SERVICE-MEASURE\s+"
        r"(?:DROP|THROW)\s+CONSTANT\s+_4SU\b",
        fixture,
    )
    assert measured is not None
    capacity = measured.group("capacity")
    if capacity != "4":
        assert re.search(
            rf"4\s+CONSTANT\s+{re.escape(capacity)}\b",
            fixture,
        )
    assert re.search(
        r"CREATE\s+_4SR\s+_4SU\s+7\s+\+\s+ALLOT",
        fixture,
    )
    assert "_4S _4SU 0 FILL" in init
    assert re.search(
        r"100000\s+8192\s+262144\s+256\s+"
        rf"_4J\s+@\s+{re.escape(capacity)}\s+"
        r"_4S\s+_4SU\s+"
        r"DESK-SBOX-JOB-SERVICE-INIT",
        init,
    )
    assert "DESK-SBOX-JOB-SERVICE-CAPACITY@" in init
    assert re.search(
        rf"_4S\s+DESK-SBOX-JOB-SERVICE-CAPACITY@\s+"
        rf"{re.escape(capacity)}\s+=\s+_4\?",
        init,
    )
    assert invoke_take.count("DESK-SBOX-JOB-SERVICE-TICK") == 1


def test_receipts_are_read_only_after_all_borrowed_state_is_gone() -> None:
    fixture = _source(FIXTURE)
    teardown = _definition(fixture, "_S4-TEARDOWN")
    detached = _definition(fixture, "_S4-DETACHED-RESULT")
    body = _definition(fixture, "_S4-BODY")

    service = teardown.index("DESK-SBOX-JOB-SERVICE-RELEASE")
    owner = teardown.index("SBOX-MODULE-OWNER-RELEASE")
    plan = teardown.index("SBOX-PLAN-RELEASE")
    context = teardown.index("CTX-FREE")
    assert service < owner < plan < context
    assert re.search(
        r"_4S\s+_4SU\s+DESK-SBOX-JOB-SERVICE-RELEASE",
        teardown,
    )
    assert "DESK-SBOX-RECEIPT-ACTIVATION@" in detached
    assert "DESK-SBOX-RECEIPT-PAYLOAD@" in _definition(
        fixture,
        "_S4-RESULT=?",
    )
    assert body.index("_S4-TEARDOWN") < body.index(
        "_S4-DETACHED-RESULT"
    )
