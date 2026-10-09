#!/usr/bin/env python3
"""Static contracts for the sandbox job service gate."""

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


SERVICE = "runtime/sandbox-job-service.f"
INSTANCE = "runtime/instance.f"
PRACTICE_HEAD = "runtime/practice-head.f"
FIXTURE = LOCAL_TESTING / "sandbox-job-service-gate.f"
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


def test_final_profile_has_only_the_job_service_closure() -> None:
    harness = _source(HARNESS)
    profile = harness.split(
        'PROFILES["sandbox-job-service-gate"] = Profile(', 1
    )[1].split('PROFILES["sandbox-core-contracts"]', 1)[0]

    roots = re.search(r"roots=\((.*?)\),", profile, re.DOTALL)
    assert roots is not None
    assert re.findall(r'"([^"]+\.f)"', roots.group(1)) == [
        SERVICE,
        INSTANCE,
        PRACTICE_HEAD,
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
    assert "_sandbox_job_service_gate_fixture_bytes()" in profile
    assert "sandbox-job-service-gate.f" in harness


def test_final_profile_chunks_keep_exact_module_and_evaluator_boundaries() -> None:
    profile = PROFILES["sandbox-job-service-gate"]
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
        "REQUIRE local_testing/sbox-job-gate.f"
    )


def test_final_profile_coalesces_the_executable_fixture_at_the_tib_limit() -> None:
    profile = PROFILES["sandbox-job-service-gate"]
    fixture_path, fixture_source = profile.initial_files[0]
    compact = _coalesce_audited_forth_lines(
        fixture_source,
        profile.audited_initial_forth_line_bytes,
    )

    assert fixture_path == "local_testing/sbox-job-gate.f"
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
        (SERVICE, INSTANCE, PRACTICE_HEAD),
    )

    assert "runtime/sandbox-host.f" in closure
    assert "runtime/sandbox-limits.f" in closure
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
        "sandbox-module-owner",
        "sandbox/compiler.f",
        "sandbox/verifier.f",
    ):
        assert not any(forbidden in f"/{module.lower()}" for module in closure)


def test_fixture_uses_the_public_job_and_result_path() -> None:
    fixture = _source(FIXTURE)

    assert "PROVIDED sbox-job-gate" in fixture
    assert "SBOX-JOB-SERVICE-MEASURE" in fixture
    # Desk no longer publishes the service; the shared capability owns it.
    assert "pure-compute" not in fixture
    assert "CINST-SERVICE" not in fixture
    assert "SBOX-JOB-SUBMIT" in fixture
    assert "SBOX-JOB-SERVICE-TICK" in fixture
    assert "SBOX-JOB-RESULT-MEASURE" in fixture
    assert "SBOX-JOB-RESULT-TAKE" in fixture
    assert "SBOX-VM-RESULT-CANDIDATE@" in fixture
    assert "SBOX-VM-RESULT-RELEASE" in fixture
    assert "SBOX-PLAN-PUBLISH-VERIFIED" in fixture
    assert "SBOX-MODULE-OWNER" not in fixture
    assert "SBOX-COMPILE" not in fixture
    assert "SBOX-VERIFY" not in fixture
    # Owners are named by their component instance's identity.
    owner = _definition(fixture, "_4OT")
    assert "CINST.ID @" in owner
    assert "CINST.GENERATION @" in owner


def test_fixture_executes_every_job_lifecycle_path() -> None:
    fixture = _source(FIXTURE)
    lifecycle = _definition(fixture, "_S4-LIFECYCLE")
    body = _definition(fixture, "_S4-BODY")

    for word in (
        "SBOX-JOB-QUERY",
        "SBOX-JOB-CANCEL",
        "SBOX-JOB-SERVICE-TICK",
        "SBOX-JOB-DISCARD",
        "SBOX-JOB-OWNER-DRAIN",
        "SBOX-JOB-SERVICE-CLOSE",
        "SBOX-JOB-SERVICE-DRAIN",
        "SBOX-JOB-SERVICE-RUNNABLE",
        "SBOX-JOB-S-NOT-OWNER",
        "SBOX-JOB-S-STALE",
        "SBOX-JOB-S-RESULT",
        "SBOX-JOB-S-INPUT",
        "SBOX-VM-RUN-CANCELLED",
        "SBOX-VM-CANCEL-DEADLINE",
        "SBOX-LIMIT-WALL-MS",
        "SBOX-JOB-SERVICE-STATE-DRAINED",
    ):
        assert word in lifecycle, word
    assert lifecycle.count("_4AUDIT") >= 6
    assert body.index("_S4-INVOKE-TAKE") < body.index("_S4-LIFECYCLE")
    assert body.index("_S4-LIFECYCLE") < body.index("_S4-TEARDOWN")


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
    assert "SBOX JOB GATE FAIL PHASE" in failure
    assert "_4F @" in failure
    assert "STATUS" in failure
    assert '" TOP "' in failure
    assert "_4U0 @" in failure
    assert '" NEXT "' in failure
    assert "_4U1 @" in failure
    assert "TX-FLUSH" in failure


def test_fixture_measures_capacity_four_from_a_complete_policy() -> None:
    fixture = _source(FIXTURE)
    candidate = _definition(fixture, "_4EC")
    limit_store = _definition(fixture, "_4L!")
    limits = _definition(fixture, "_4MI")
    init = _definition(fixture, "_S4-RUNTIME-INIT")

    assert "_4C _4CU 0 FILL" not in candidate
    assert "SBOX-LIMIT-CAP" in limit_store
    assert "SBOX-LIMITS-BEGIN" in limits
    assert "SBOX-LIMITS-SEAL" in limits
    for field in (
        "INSTRUCTION-BUDGET",
        "VALUE-OP-BUDGET",
        "COPY-BUDGET",
        "WALL-MS",
        "DEPTH",
        "OUTPUT-RESULT-BYTES",
    ):
        assert f"SBOX-LIMIT-{field} _4L!" in limits, field
    assert "_SBXJ.STATE" not in fixture

    assert re.search(
        r"4\s+CONSTANT\s+_4SC\b",
        fixture,
    )
    assert re.search(
        r"_4SC\s+SBOX-JOB-SERVICE-MEASURE\s+DROP\s+CONSTANT\s+_4SU\b",
        fixture,
    )
    assert re.search(
        r"CREATE\s+_4SR\s+_4SU\s+7\s+\+\s+ALLOT",
        fixture,
    )
    assert "_4S _4SU 0 FILL" in init
    assert re.search(
        r"_4X\s+@\s+_4M\s+256\s+1000\s+_4J\s+@\s+"
        r"_4SC\s+_4S\s+_4SU\s+SBOX-JOB-SERVICE-INIT\s+THROW",
        init,
    )
    assert "SBOX-JOB-S-LIMITS" in init
    assert re.search(
        r"_4S\s+SBOX-JOB-SERVICE-CAPACITY@\s+_4SC\s+=\s+_4\?",
        init,
    )


def test_the_result_is_read_after_all_borrowed_state_is_gone() -> None:
    fixture = _source(FIXTURE)
    teardown = _definition(fixture, "_S4-TEARDOWN")
    detached = _definition(fixture, "_S4-DETACHED-RESULT")
    body = _definition(fixture, "_S4-BODY")

    service = teardown.index("SBOX-JOB-SERVICE-RELEASE")
    plan = teardown.index("SBOX-PLAN-RELEASE")
    context = teardown.index("CTX-FREE")
    assert service < plan < context
    assert re.search(
        r"_4S\s+_4SU\s+SBOX-JOB-SERVICE-RELEASE",
        teardown,
    )
    assert "_4RB @" in detached
    assert "_4R=?" in detached
    assert "_4AV _4H @ =" in detached
    assert body.index("_S4-TEARDOWN") < body.index(
        "_S4-DETACHED-RESULT"
    )
