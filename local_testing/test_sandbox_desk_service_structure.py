#!/usr/bin/env python3
"""Static contracts for the bounded transient Desk sandbox job service."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402


SERVICE = Path("tui/applets/desk/sandbox-service.f")
ADMISSION = Path("tui/applets/desk/sandbox-admission.f")
COMPONENT = Path("tui/applets/desk/sandbox-component.f")

PUBLIC_WORDS = (
    "DESK-SBOX-JOB-SERVICE-INIT",
    "DESK-SBOX-JOB-SERVICE-VALID?",
    "DESK-SBOX-JOB-SERVICE-OWNER?",
    "DESK-SBOX-JOB-SUBMIT",
    "DESK-SBOX-JOB-SERVICE-TICK",
    "DESK-SBOX-JOB-QUERY",
    "DESK-SBOX-JOB-CANCEL",
    "DESK-SBOX-JOB-RESULT-TAKE",
    "DESK-SBOX-JOB-DISCARD",
    "DESK-SBOX-JOB-OWNER-DRAIN",
    "DESK-SBOX-JOB-SERVICE-CLOSE",
    "DESK-SBOX-JOB-SERVICE-DRAIN",
    "DESK-SBOX-JOB-SERVICE-STATE@",
    "DESK-SBOX-JOB-SERVICE-ACTIVATION@",
    "DESK-SBOX-JOB-SERVICE-COUNT",
    "DESK-SBOX-JOB-SERVICE-RELEASE",
)

FORBIDDEN_DEPENDENCY_FRAGMENTS = (
    "schema",
    "registry",
    "capability",
    "persistence",
    "/store/",
    "/library",
    "/pad",
    "/agent/",
    "provider",
    "request-bus",
    "app-manifest",
    "app-catalog",
    "app-loader",
    "applet-host",
)


def _source() -> str:
    return (AKASHIC_ROOT / SERVICE).read_text(encoding="utf-8")


def _definition(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}(?:\s|$).*?;\s*$",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(0)


def _stack_effect(source: str, word: str) -> str:
    match = re.search(
        rf"^:\s+{re.escape(word)}\s*\n?\s*\((.*?)\)",
        source,
        re.MULTILINE | re.DOTALL,
    )
    assert match is not None, word
    return match.group(1).lower()


def test_service_dependency_boundary_excludes_deferred_concerns() -> None:
    closure = dependency_closure(AKASHIC_ROOT, (SERVICE.as_posix(),))

    assert ADMISSION.as_posix() in closure
    assert COMPONENT.as_posix() in closure
    assert "runtime/sandbox-module-owner.f" in closure
    assert "runtime/sandbox-host.f" in closure
    assert "runtime/practice-head.f" in closure
    assert "runtime/instance.f" in closure

    desk_modules = {
        module for module in closure
        if module.startswith("tui/applets/desk/")
    }
    assert desk_modules == {
        SERVICE.as_posix(),
        ADMISSION.as_posix(),
        COMPONENT.as_posix(),
    }

    for module in closure:
        normalized = f"/{module.lower()}"
        assert not any(
            fragment in normalized
            for fragment in FORBIDDEN_DEPENDENCY_FRAGMENTS
        ), module


def test_service_publishes_the_complete_bounded_job_lifecycle() -> None:
    source = _source()

    assert "4 CONSTANT DESK-SBOX-JOB-CAPACITY" in source
    assert "64 CONSTANT _DSJS-ADMISSION" in source
    assert (
        "_DSJ-SLOTS DESK-SBOX-JOB-CAPACITY _DSJS-SIZE * +"
        in source
    )
    assert "CONSTANT DESK-SBOX-JOB-SERVICE-SIZE" in source
    for word in PUBLIC_WORDS:
        assert re.search(
            rf"^:\s+{re.escape(word)}(?:\s|$)",
            source,
            re.MULTILINE,
        ), word


def test_submission_uses_service_policy_and_copies_caller_identity() -> None:
    source = _source()
    submit = _definition(source, "DESK-SBOX-JOB-SUBMIT")
    submit_effect = _stack_effect(source, "DESK-SBOX-JOB-SUBMIT")

    for forbidden_input in (
        "instruction",
        "value-op",
        "copy-budget",
        "slice",
        "limits",
        "class",
    ):
        assert forbidden_input not in submit_effect

    for service_policy in (
        "_DSJ.LIMITS",
        "_DSJ.INSTRUCTION-BUDGET",
        "_DSJ.VALUE-OP-BUDGET",
        "_DSJ.COPY-BUDGET",
    ):
        assert service_policy in submit
    assert "DESK-SBOX-ADMISSION-INIT" in submit
    assert "DESK-SBOX-ADMISSION-INVOKE" in submit
    assert "_DSJS.CALLER-ID" in submit
    assert "_DSJS.CALLER-GENERATION" in submit
    assert submit.index("DESK-SBOX-ADMISSION-INVOKE") < submit.index(
        "DESK-SBOX-JOB-STATE-RUNNABLE"
    )


def test_tick_advances_at_most_one_job_by_one_fixed_slice() -> None:
    source = _source()
    tick = _definition(source, "DESK-SBOX-JOB-SERVICE-TICK")

    assert tick.count("DESK-SBOX-ADMISSION-RUN-SLICE") == 1
    assert "_DSJ.SLICE-STEPS @" in tick
    assert "_DSJ.CURSOR @" in tick
    assert "DESK-SBOX-JOB-CAPACITY MOD" in tick
    assert "_DSJT-ADVANCE-CURSOR" in tick
    assert "_DSJT-STATUS @ EXIT" in tick


def test_result_and_shutdown_paths_end_borrows_before_reuse() -> None:
    source = _source()
    take = _definition(source, "DESK-SBOX-JOB-RESULT-TAKE")
    owner_drain = _definition(source, "DESK-SBOX-JOB-OWNER-DRAIN")
    close = _definition(source, "DESK-SBOX-JOB-SERVICE-CLOSE")
    drain = _definition(source, "DESK-SBOX-JOB-SERVICE-DRAIN")

    assert "DESK-SBOX-ADMISSION-RESULT-TAKE" in take
    assert "_DSJ-DISCARD-SLOT" in take
    assert take.index("DESK-SBOX-ADMISSION-RESULT-TAKE") < take.index(
        "_DSJ-DISCARD-SLOT"
    )
    assert "_DSJS.CALLER-ID" in owner_drain
    assert "_DSJS.CALLER-GENERATION" in owner_drain
    assert "_DSJ-DISCARD-SLOT" in owner_drain

    state_barrier = close.index(
        "DESK-SBOX-JOB-SERVICE-STATE-CLOSING"
    )
    cancel_barrier = close.index("DESK-SBOX-ADMISSION-CLOSE")
    assert state_barrier < cancel_barrier
    assert "DESK-SBOX-JOB-SERVICE-CLOSE" in drain
    assert "_DSJ-DISCARD-SLOT" in drain
    assert "_DSJ-DRAIN-CLEAR" in drain
    assert drain.index("DESK-SBOX-JOB-SERVICE-CLOSE") < drain.index(
        "_DSJ-DRAIN-CLEAR"
    )


def test_service_has_a_linked_load_only_profile() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(
        encoding="utf-8"
    )

    assert 'PROFILES["sandbox-desk-service"]' in harness
    assert '"tui/applets/desk/sandbox-service.f"' in harness
    assert "SBOX DESK SERVICE LOAD PASS" in harness
    profile = harness.split(
        'PROFILES["sandbox-desk-service"]', 1
    )[1].split("\n\n\n", 1)[0]
    assert "linked=True" in profile
    assert "include_large_sample=False" in profile
    assert "initial_files=" not in profile
