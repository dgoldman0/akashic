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
HOST = Path("runtime/sandbox-host.f")
VM = Path("sandbox/vm.f")

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


def _source(path: Path = SERVICE) -> str:
    return (AKASHIC_ROOT / path).read_text(encoding="utf-8")


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

    assert tick.count("_DSA-RUN-SLICE-VALIDATED") == 1
    assert tick.index("DESK-SBOX-JOB-SERVICE-VALID?") < tick.index(
        "_DSA-RUN-SLICE-VALIDATED"
    )
    assert "_DSJ.SLICE-STEPS @" in tick
    assert "_DSJ.CURSOR @" in tick
    assert "DESK-SBOX-JOB-CAPACITY MOD" in tick
    assert "_DSJT-ADVANCE-CURSOR" in tick
    assert "_DSJT-STATUS @ EXIT" in tick


def test_slot_validation_checks_the_embedded_graph_only_once() -> None:
    source = _source()
    slot = _definition(source, "_DSJ-SLOT-VALID?")

    assert slot.count("DESK-SBOX-ADMISSION-VALID?") == 1
    assert "DESK-SBOX-ADMISSION-ACTIVATION@" not in slot
    assert "DESK-SBOX-ADMISSION-INVOCATION@" not in slot
    assert "DESK-SBOX-ADMISSION-RUN-STATE@" not in slot
    assert "_DSA.OWNER @" in slot
    assert "_DSJ.MODULE-OWNER @" in slot
    assert "_DSA.HEAD @" in slot
    assert "_DSJ.HEAD @" in slot
    assert "_DSA.PARENT @" in slot
    assert "_DSJ.PARENT @" in slot
    assert "_DSA.ACTIVATION-GENERATION @" in slot
    assert "_DSA.ACTIVATION-ID @" in slot
    assert "_DSC.LIVE-GENERATION @" in slot
    assert "_SHOST-RUN-STATE-VALIDATED" in slot


def test_fixed_service_zero_scans_are_cellwise_and_exact() -> None:
    source = _source()
    zero = _definition(source, "_DSJ-ZERO?")

    assert "2DUP OR 7 AND" in zero
    assert "8 / 0 ?DO" in zero
    assert "I 8 * + @" in zero
    assert "C@" not in zero


def test_validated_tick_slice_is_private_and_public_wrappers_stay_checked() -> None:
    admission = _source(ADMISSION)
    component = _source(COMPONENT)
    host = _source(HOST)
    vm = _source(VM)

    admission_private = _definition(admission, "_DSA-RUN-SLICE-VALIDATED")
    component_private = _definition(component, "_DSC-RUN-SLICE-VALIDATED")
    host_private = _definition(host, "_SHOST-RUN-SLICE-VALIDATED")
    vm_private = _definition(vm, "_SVM-RUN-SLICE-VALIDATED")
    assert "_DSC-RUN-SLICE-VALIDATED" in admission_private
    assert "_SHOST-RUN-SLICE-VALIDATED" in component_private
    assert "_SVM-RUN-SLICE-VALIDATED" in host_private
    assert "_SVM-RESUME-READY?" in vm_private
    assert "_SVM-STEP-ADMITTED" in vm_private

    admission_public = _definition(
        admission,
        "DESK-SBOX-ADMISSION-RUN-SLICE",
    )
    component_public = _definition(component, "DESK-SBOX-RUN-SLICE")
    host_public = _definition(host, "SBOX-HOST-RUN-SLICE")
    vm_public = _definition(vm, "SBOX-VM-RUN-SLICE")
    assert "DESK-SBOX-ADMISSION-VALID?" in admission_public
    assert "DESK-SBOX-RUN-SLICE" in admission_public
    assert "_DSC-HANDLE-STATUS" in component_public
    assert "SBOX-HOST-RUN-SLICE" in component_public
    assert "_SHOST-ACTIVE?" in host_public
    assert "SBOX-VM-RUN-SLICE" in host_public
    assert "SBOX-VM-INSTANCE-VALID?" in vm_public
    assert "_SVM-RUN-SLICE-VALIDATED" in vm_public


def test_result_and_shutdown_paths_end_borrows_before_reuse() -> None:
    source = _source()
    take = _definition(source, "DESK-SBOX-JOB-RESULT-TAKE")
    owner_drain = _definition(source, "DESK-SBOX-JOB-OWNER-DRAIN")
    close = _definition(source, "DESK-SBOX-JOB-SERVICE-CLOSE")
    drain = _definition(source, "DESK-SBOX-JOB-SERVICE-DRAIN")
    release = _definition(source, "DESK-SBOX-JOB-SERVICE-RELEASE")

    assert "_DSA-RESULT-TAKE-PRECHECKED" in take
    assert take.index("_DSJ-LOOKUP") < take.index(
        "_DSA-RESULT-TAKE-PRECHECKED"
    )
    assert take.index("_DSJ-EXTERNAL-SPAN?") < take.index(
        "_DSA-RESULT-TAKE-PRECHECKED"
    )
    assert take.index("_DSA-RECEIPT-BOUNDARY") < take.index(
        "_DSA-SERVICE-RESULT-SPAN-STATUS"
    )
    assert take.index("_DSA-SERVICE-RESULT-SPAN-STATUS") < take.index(
        "_DSA-RESULT-TAKE-PRECHECKED"
    )
    assert "_DSJTAKE-STATUS" not in source
    discard = _definition(source, "_DSJ-DISCARD-SLOT")
    assert "_DSJD-" not in source
    assert "VARIABLE" not in discard
    assert "DESK-SBOX-ADMISSION-DRAIN" in discard
    assert "DESK-SBOX-ADMISSION-STATE@" in discard
    assert "_DSJ-DISCARD-SLOT" in take
    assert take.index("_DSA-RESULT-TAKE-PRECHECKED") < take.index(
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
    assert "DESK-SBOX-JOB-SERVICE-SIZE 0 FILL" in release
    assert "OVER _DSJ-OWNER-CORE 0 FILL" in release
    assert release.index("DESK-SBOX-JOB-SERVICE-DRAIN") < release.index(
        "OVER _DSJ-OWNER-CORE 0 FILL"
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
