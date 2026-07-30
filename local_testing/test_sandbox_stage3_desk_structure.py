#!/usr/bin/env python3
"""Static contracts for the headless Stage 3 Desk sandbox component."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure, dependency_markers  # noqa: E402


COMPONENT = Path("tui/applets/desk/sandbox-component.f")
JOB_SERVICE = Path("tui/applets/desk/sandbox-service.f")
DESK = Path("tui/applets/desk/desk.f")
HOST = Path("runtime/sandbox-host.f")
FIXTURE = Path("sandbox-stage3-desk-component.f")
FOCUSED_PROFILES = (
    ("sandbox-stage3-desk-component", "_S3D-COMPOSE-RUN"),
    ("sandbox-stage3-desk-cancel", "_S3D-CANCEL-RUN"),
    ("sandbox-stage3-desk-drain", "_S3D-DRAIN-RUN"),
    ("sandbox-stage3-desk-close", "_S3D-CLOSE-RUN"),
)

PUBLIC_WORDS = (
    "DESK-SBOX-COMPONENT-INIT",
    "DESK-SBOX-ADMIT",
    "DESK-SBOX-RUN-SLICE",
    "DESK-SBOX-RUN-STATE@",
    "DESK-SBOX-CANCEL",
    "DESK-SBOX-RESULT-TAKE",
    "DESK-SBOX-CLOSE",
    "DESK-SBOX-DRAIN",
    "DESK-SBOX-COMPONENT-RELEASE",
    "DESK-SBOX-RESULT-VALID?",
    "DESK-SBOX-RESULT-PAYLOAD@",
    "DESK-SBOX-RESULT-RELEASE",
)

FORBIDDEN_DEPENDENCY_FRAGMENTS = (
    "app-desc",
    "applet-host",
    "/agent/",
    "practice",
    "schema",
    "digest",
    "cache",
    "vfs",
    "provider",
    "service",
)


def _source(path: Path) -> str:
    return (AKASHIC_ROOT / path).read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def test_desk_reaches_the_headless_component_through_the_job_service() -> None:
    markers = dependency_markers(_source(DESK), DESK.as_posix())

    assert any(
        marker.raw == "sandbox-service.f"
        and marker.normalized == JOB_SERVICE.as_posix()
        for marker in markers
    )
    closure = dependency_closure(AKASHIC_ROOT, (JOB_SERVICE.as_posix(),))
    assert COMPONENT.as_posix() in closure


def test_component_closure_stays_on_the_isolated_runtime_path() -> None:
    closure = dependency_closure(AKASHIC_ROOT, (COMPONENT.as_posix(),))

    assert "runtime/sandbox-module-owner.f" in closure
    assert "runtime/sandbox-host.f" in closure
    for module in closure:
        if module == COMPONENT.as_posix():
            continue
        normalized = f"/{module.lower()}"
        assert not any(
            fragment in normalized
            for fragment in FORBIDDEN_DEPENDENCY_FRAGMENTS
        ), module


def test_component_is_caller_owned_and_publishes_the_lifecycle_api() -> None:
    source = _source(COMPONENT)

    assert re.search(r"^\s*VARIABLE\s+", source, re.MULTILINE) is None
    assert re.search(r"^\s*CREATE\s+", source, re.MULTILINE) is None
    assert re.search(r"^\s+--", source, re.MULTILINE) is None
    assert "768 CONSTANT DESK-SBOX-COMPONENT-SIZE" in source
    assert "64 CONSTANT DESK-SBOX-RESULT-SIZE" in source
    assert "_SHOST-SPAN-DISJOINT-VALIDATED?" in source
    assert ": _SHOST-SPAN-DISJOINT-VALIDATED?" in _source(HOST)
    assert ": SBOX-HOST-SPAN-DISJOINT?" in _source(HOST)
    for word in PUBLIC_WORDS:
        assert re.search(
            rf"^:\s+{re.escape(word)}(?:\s|$)",
            source,
            re.MULTILINE,
        ), word


def test_take_checks_the_complete_destination_against_the_live_host() -> None:
    source = _source(COMPONENT)
    validated = source.split(
        ": _DSC-TAKE-SPAN-VALIDATED", 1
    )[1].split(": _DSC-TAKE-SPAN-STATUS", 1)[0]
    helper = source.split(": _DSC-TAKE-SPAN-STATUS", 1)[1].split(
        ": _DSC-TAKE-BOUNDARY", 1
    )[0]
    boundary = source.split(": _DSC-TAKE-BOUNDARY", 1)[1].split(
        ": _DSC-ALLOCATE", 1
    )[0]
    commit = source.split(": _DSC-RESULT-TAKE-PRECHECKED", 1)[1].split(
        ": DESK-SBOX-RESULT-TAKE", 1
    )[0]
    public = source.split(": DESK-SBOX-RESULT-TAKE", 1)[1].split(
        "\\ =====================================================================",
        1,
    )[0]

    assert "_DSC-HANDLE-STATUS" in helper
    assert "_DSC-TAKE-SPAN-VALIDATED" in helper
    assert "_DSC-HANDLE-STATUS" not in validated
    assert "_DSC-EXTERNAL-SPAN?" in validated
    assert "_SHOST-SPAN-DISJOINT-VALIDATED?" in validated
    assert "_SHOST-RUN-STATE-VALIDATED" in validated
    assert "DESK-SBOX-RESULT-SIZE" in boundary
    assert "_DSC-TAKE-SPAN-STATUS" in boundary
    assert "_SHOST-RUN-STATE-VALIDATED" in commit
    assert "_SHOST-FINISH-MEASURED-VALIDATED" in commit
    assert "SBOX-HOST-FINISH" not in commit
    assert re.search(
        r"DUP\s+3 PICK\s+DUP\s+6 PICK _DSC\.HOST\s+"
        r"_SHOST-FINISH-MEASURED-VALIDATED",
        commit,
    )
    assert "_DSC-TAKE-BOUNDARY" in public
    assert "_DSC-RESULT-TAKE-PRECHECKED" in public


def test_detached_result_accessors_reuse_one_nested_envelope_proof() -> None:
    source = _source(COMPONENT)
    valid = _definition(source, "DESK-SBOX-RESULT-VALID?")
    generation = _definition(source, "DESK-SBOX-RESULT-GENERATION@")
    run_state = _definition(source, "DESK-SBOX-RESULT-RUN-STATE@")
    payload = _definition(source, "DESK-SBOX-RESULT-PAYLOAD@")

    assert valid.count("SBOX-VM-RESULT-VALID?") == 1
    assert "_SVM-RESULT-TOTAL-VALIDATED@" in valid
    assert "_DSR-GENERATION-VALIDATED@" in generation
    assert "_DSR-RUN-STATE-VALIDATED@" in run_state
    assert "_DSR-PAYLOAD-VALIDATED@" in payload


def test_detached_result_release_reuses_the_nested_envelope_proof() -> None:
    source = _source(COMPONENT)
    private = _definition(source, "_DSR-RELEASE-VALIDATED")
    public = _definition(source, "DESK-SBOX-RESULT-RELEASE")

    assert "_SVM-RESULT-RELEASE-VALIDATED" in private
    assert "SBOX-VM-RESULT-RELEASE" not in private
    assert "_DSC-SCRUB-FREE" not in private
    assert "DESK-SBOX-RESULT-VALID?" in public
    assert "_DSR-RELEASE-VALIDATED" in public


def test_close_publishes_admission_barrier_before_host_cancellation() -> None:
    source = _source(COMPONENT)
    close = source.index(": DESK-SBOX-CLOSE")
    drain = source.index(": _DSC-DRAIN-CLEAR", close)
    body = source[close:drain]

    state = body.index("DESK-SBOX-COMPONENT-STATE-CLOSING")
    cancel = body.index("SBOX-HOST-CANCEL")
    assert state < cancel
    assert "SBOX-VM-CANCEL-HOST-SHUTDOWN" in body


def test_drain_releases_host_before_ending_borrows() -> None:
    source = _source(COMPONENT)
    drain = source.index(": DESK-SBOX-DRAIN")
    state_accessor = source.index(": DESK-SBOX-COMPONENT-STATE@", drain)
    body = source[drain:state_accessor]

    release = body.index("SBOX-HOST-RELEASE")
    clear = body.index("_DSC-DRAIN-CLEAR")
    assert release < clear


def test_headless_component_has_a_focused_executable_gate() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")
    fixture = (LOCAL_TESTING / FIXTURE).read_text(encoding="utf-8")

    assert f'"{FIXTURE.as_posix()}"' in harness
    assert "_S3D-COMPONENT-A" in fixture
    assert "_S3D-COMPONENT-B" in fixture
    assert "_S3D-BUILD-ECHO-CANDIDATE" in fixture
    assert "SBOX-COMPILE" not in fixture
    assert "SBOX-VM-CANCEL-HOST-SHUTDOWN" in fixture
    for profile, entry_word in FOCUSED_PROFILES:
        assert f'PROFILES["{profile}"]' in harness
        assert entry_word in harness
        assert entry_word in fixture
    for word in PUBLIC_WORDS:
        assert word in fixture
