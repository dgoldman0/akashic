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


SERVICE = Path("runtime/sandbox-job-service.f")
ADMISSION = Path("runtime/sandbox-admission.f")
COMPONENT = Path("runtime/sandbox-slot.f")
HOST = Path("runtime/sandbox-host.f")
VM = Path("sandbox/vm.f")

PUBLIC_WORDS = (
    "SBOX-JOB-SERVICE-MEASURE",
    "SBOX-JOB-SERVICE-INIT",
    "SBOX-JOB-SERVICE-VALID?",
    "SBOX-JOB-SERVICE-OWNER?",
    "SBOX-JOB-SUBMIT",
    "SBOX-JOB-SERVICE-TICK",
    "SBOX-JOB-QUERY",
    "SBOX-JOB-CANCEL",
    "SBOX-JOB-RESULT-TAKE",
    "SBOX-JOB-DISCARD",
    "SBOX-JOB-OWNER-DRAIN",
    "SBOX-JOB-SERVICE-CLOSE",
    "SBOX-JOB-SERVICE-DRAIN",
    "SBOX-JOB-SERVICE-STATE@",
    "SBOX-JOB-SERVICE-ACTIVATION@",
    "SBOX-JOB-SERVICE-COUNT",
    "SBOX-JOB-SERVICE-CAPACITY@",
    "SBOX-JOB-SERVICE-RELEASE",
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

    assert not any(module.startswith("tui/") for module in closure)

    for module in closure:
        normalized = f"/{module.lower()}"
        assert not any(
            fragment in normalized
            for fragment in FORBIDDEN_DEPENDENCY_FRAGMENTS
        ), module


def test_service_publishes_the_complete_bounded_job_lifecycle() -> None:
    source = _source()

    assert not re.search(
        r"^\s*\d+\s+CONSTANT\s+SBOX-JOB-CAPACITY\s*$",
        source,
        re.MULTILINE,
    )
    assert "CONSTANT SBOX-JOB-SERVICE-SIZE" not in source
    assert (
        "256 CONSTANT SBOX-JOB-SERVICE-HEADER-SIZE"
        in source
    )
    assert re.search(
        r"^\s*\d+\s+CONSTANT\s+_SBXJ-CAPACITY\s*$",
        source,
        re.MULTILINE,
    )
    assert re.search(
        r"^:\s+_SBXJ\.CAPACITY\s+"
        r"\(\s*service\s+--\s+address\s*\)",
        source,
        re.MULTILINE,
    )
    assert "64 CONSTANT _SBXJS-ADMISSION" in source
    for word in PUBLIC_WORDS:
        assert re.search(
            rf"^:\s+{re.escape(word)}(?:\s|$)",
            source,
            re.MULTILINE,
        ), word


def test_capacity_is_measured_stored_and_part_of_exact_initialization() -> None:
    source = _source()
    measure = _definition(
        source,
        "SBOX-JOB-SERVICE-MEASURE",
    )
    init = _definition(source, "SBOX-JOB-SERVICE-INIT")
    header = _definition(source, "_SBXJ-HEADER?")
    capacity_at = _definition(
        source,
        "SBOX-JOB-SERVICE-CAPACITY@",
    )

    measure_effect = " ".join(
        _stack_effect(
            source,
            "SBOX-JOB-SERVICE-MEASURE",
        ).split()
    )
    assert measure_effect == "capacity -- service-u|0 status"
    assert "SBOX-JOB-SERVICE-HEADER-SIZE" in measure
    assert "_SBXJS-SIZE *" in measure
    assert "_SBXJ-SIGNED-MAX" in measure

    init_effect = " ".join(
        _stack_effect(
            source,
            "SBOX-JOB-SERVICE-INIT",
        ).split()
    )
    assert init_effect.endswith(
        "activation-id capacity service service-u -- status"
    )
    boundary = _definition(source, "_SBXJI-BOUNDARY")
    assert "_SBXJI-BOUNDARY" in init
    assert "SBOX-JOB-SERVICE-MEASURE" in boundary
    assert "_SBXJI-SERVICE-U @" in boundary
    assert "_SBXJ.CAPACITY !" in init
    assert "_SBXJ.SIZE !" in init

    assert "_SBXJ.CAPACITY @" in header
    assert "_SBXJ.SIZE @" in header
    assert "SBOX-JOB-SERVICE-MEASURE" in header
    assert "SBOX-JOB-SERVICE-VALID?" in capacity_at
    assert "_SBXJ.CAPACITY @" in capacity_at


def test_every_slot_bound_and_rotation_uses_validated_service_capacity() -> None:
    source = _source()

    assert not re.search(
        r"\bSBOX-JOB-CAPACITY\b",
        source,
    )
    for word in (
        "_SBXJ-SLOTS-VALID?",
        "_SBXJ-ACTIVE-SHAPE?",
        "_SBXJ-LOOKUP",
        "_SBXJSUB-FREE-SLOT",
        "_SBXJSUB-BOUNDARY",
        "_SBXJT-ADVANCE-CURSOR",
        "SBOX-JOB-SERVICE-TICK",
        "SBOX-JOB-OWNER-DRAIN",
        "SBOX-JOB-SERVICE-CLOSE",
        "SBOX-JOB-SERVICE-DRAIN",
    ):
        assert "_SBXJ.CAPACITY @" in _definition(source, word), word

    for word in (
        "_SBXJ-SLOTS-VALID?",
        "_SBXJ-LOOKUP",
        "_SBXJSUB-FREE-SLOT",
        "SBOX-JOB-OWNER-DRAIN",
        "SBOX-JOB-SERVICE-CLOSE",
        "SBOX-JOB-SERVICE-DRAIN",
    ):
        assert "0 ?DO" in _definition(source, word), word

    tick = _definition(source, "SBOX-JOB-SERVICE-TICK")
    advance = _definition(source, "_SBXJT-ADVANCE-CURSOR")
    assert "MOD" in tick
    assert "MOD" in advance


def test_submission_uses_service_policy_and_copies_caller_identity() -> None:
    source = _source()
    submit = _definition(source, "SBOX-JOB-SUBMIT")
    submit_effect = _stack_effect(source, "SBOX-JOB-SUBMIT")

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
        "_SBXJ.LIMITS",
        "_SBXJ.INSTRUCTION-BUDGET",
        "_SBXJ.VALUE-OP-BUDGET",
        "_SBXJ.COPY-BUDGET",
    ):
        assert service_policy in submit
    assert "SBOX-ADMISSION-INIT" in submit
    assert "SBOX-ADMISSION-INVOKE" in submit
    assert "_SBXJS.CALLER-ID" in submit
    assert "_SBXJS.CALLER-GENERATION" in submit
    assert submit.index("SBOX-ADMISSION-INVOKE") < submit.index(
        "SBOX-JOB-STATE-RUNNABLE"
    )
    assert re.search(
        r"_SBXJSUB-FREE-SLOT\s+_SBXJSUB-SLOT\s+!",
        submit,
    )
    assert not re.search(r"_SBXJSUB-FREE-SLOT\s+DUP", submit)


def test_tick_advances_at_most_one_job_by_one_fixed_slice() -> None:
    source = _source()
    tick = _definition(source, "SBOX-JOB-SERVICE-TICK")

    assert tick.count("_SBXA-RUN-SLICE-VALIDATED") == 1
    assert tick.index("SBOX-JOB-SERVICE-VALID?") < tick.index(
        "_SBXA-RUN-SLICE-VALIDATED"
    )
    assert "_SBXJ.SLICE-STEPS @" in tick
    assert "_SBXJ.CURSOR @" in tick
    assert "_SBXJ.CAPACITY @" in tick
    assert "MOD" in tick
    assert "_SBXJT-ADVANCE-CURSOR" in tick
    assert "_SBXJT-STATUS @ EXIT" in tick
    assert (
        "_SBXJT-STATUS @ SBOX-JOB-STATUS-VALID? 0=" in tick
    )
    assert not re.search(
        r"_SBXJT-STATUS\s+@\s+DUP\s+"
        r"SBOX-JOB-STATUS-VALID\?",
        tick,
    )


def test_slot_validation_checks_the_embedded_graph_only_once() -> None:
    source = _source()
    slot = _definition(source, "_SBXJ-SLOT-VALID?")

    assert slot.count("SBOX-ADMISSION-VALID?") == 1
    assert "SBOX-ADMISSION-ACTIVATION@" not in slot
    assert "SBOX-ADMISSION-INVOCATION@" not in slot
    assert "SBOX-ADMISSION-RUN-STATE@" not in slot
    assert "_SBXA.OWNER @" in slot
    assert "_SBXJ.MODULE-OWNER @" in slot
    assert "_SBXA.HEAD @" in slot
    assert "_SBXJ.HEAD @" in slot
    assert "_SBXA.PARENT @" in slot
    assert "_SBXJ.PARENT @" in slot
    assert "_SBXA.ACTIVATION-GENERATION @" in slot
    assert "_SBXA.ACTIVATION-ID @" in slot
    assert "_SBXS.LIVE-GENERATION @" in slot
    assert "_SHOST-RUN-STATE-VALIDATED" in slot


def test_measured_service_zero_scans_are_cellwise_and_exact() -> None:
    source = _source()
    zero = _definition(source, "_SBXJ-ZERO?")

    assert "2DUP OR 7 AND" in zero
    assert "8 / 0 ?DO" in zero
    assert "I 8 * + @" in zero
    assert "C@" not in zero


def test_validated_tick_slice_is_private_and_public_wrappers_stay_checked() -> None:
    admission = _source(ADMISSION)
    component = _source(COMPONENT)
    host = _source(HOST)
    vm = _source(VM)

    admission_private = _definition(admission, "_SBXA-RUN-SLICE-VALIDATED")
    component_private = _definition(component, "_SBXS-RUN-SLICE-VALIDATED")
    host_private = _definition(host, "_SHOST-RUN-SLICE-VALIDATED")
    vm_private = _definition(vm, "_SVM-RUN-SLICE-VALIDATED")
    assert "_SBXS-RUN-SLICE-VALIDATED" in admission_private
    assert "_SHOST-RUN-SLICE-VALIDATED" in component_private
    assert "_SVM-RUN-SLICE-VALIDATED" in host_private
    assert "_SVM-RESUME-READY?" in vm_private
    assert "_SVM-STEP-ADMITTED" in vm_private

    admission_public = _definition(
        admission,
        "SBOX-ADMISSION-RUN-SLICE",
    )
    component_public = _definition(component, "SBOX-SLOT-RUN-SLICE")
    host_public = _definition(host, "SBOX-HOST-RUN-SLICE")
    vm_public = _definition(vm, "SBOX-VM-RUN-SLICE")
    assert "SBOX-ADMISSION-VALID?" in admission_public
    assert "SBOX-SLOT-RUN-SLICE" in admission_public
    assert "_SBXS-HANDLE-STATUS" in component_public
    assert "SBOX-HOST-RUN-SLICE" in component_public
    assert "_SHOST-ACTIVE?" in host_public
    assert "SBOX-VM-RUN-SLICE" in host_public
    assert "SBOX-VM-INSTANCE-VALID?" in vm_public
    assert "_SVM-RUN-SLICE-VALIDATED" in vm_public


def test_result_and_shutdown_paths_end_borrows_before_reuse() -> None:
    source = _source()
    take = _definition(source, "SBOX-JOB-RESULT-TAKE")
    owner_drain = _definition(source, "SBOX-JOB-OWNER-DRAIN")
    close = _definition(source, "SBOX-JOB-SERVICE-CLOSE")
    drain = _definition(source, "SBOX-JOB-SERVICE-DRAIN")
    release = _definition(source, "SBOX-JOB-SERVICE-RELEASE")

    assert "_SBXA-RESULT-TAKE-PRECHECKED" in take
    assert take.index("_SBXJ-LOOKUP") < take.index(
        "_SBXA-RESULT-TAKE-PRECHECKED"
    )
    assert take.index("_SBXJ-EXTERNAL-SPAN?") < take.index(
        "_SBXA-RESULT-TAKE-PRECHECKED"
    )
    assert take.index("_SBXA-RECEIPT-BOUNDARY") < take.index(
        "_SBXA-SERVICE-RESULT-SPAN-STATUS"
    )
    assert take.index("_SBXA-SERVICE-RESULT-SPAN-STATUS") < take.index(
        "_SBXA-RESULT-TAKE-PRECHECKED"
    )
    assert "_SBXJTAKE-STATUS" not in source
    discard = _definition(source, "_SBXJ-DISCARD-SLOT")
    assert "_SBXJD-" not in source
    assert "VARIABLE" not in discard
    assert "SBOX-ADMISSION-DRAIN" in discard
    assert "SBOX-ADMISSION-STATE@" in discard
    assert "_SBXJ-DISCARD-SLOT" in take
    assert take.index("_SBXA-RESULT-TAKE-PRECHECKED") < take.index(
        "_SBXJ-DISCARD-SLOT"
    )
    assert "_SBXJS.CALLER-ID" in owner_drain
    assert "_SBXJS.CALLER-GENERATION" in owner_drain
    assert "_SBXJ-DISCARD-SLOT" in owner_drain

    state_barrier = close.index(
        "SBOX-JOB-SERVICE-STATE-CLOSING"
    )
    cancel_barrier = close.index("SBOX-ADMISSION-CLOSE")
    assert state_barrier < cancel_barrier
    assert "SBOX-JOB-SERVICE-CLOSE" in drain
    assert "_SBXJ-DISCARD-SLOT" in drain
    assert "_SBXJ-DRAIN-CLEAR" in drain
    assert drain.index("SBOX-JOB-SERVICE-CLOSE") < drain.index(
        "_SBXJ-DRAIN-CLEAR"
    )
    release_effect = " ".join(
        _stack_effect(
            source,
            "SBOX-JOB-SERVICE-RELEASE",
        ).split()
    )
    assert release_effect == "service service-u -- status"
    assert "_SBXJ.SIZE @" in release
    assert "0 FILL" in release
    assert release.index("SBOX-JOB-SERVICE-DRAIN") < release.rindex(
        "0 FILL"
    )


def test_service_has_a_linked_load_only_profile() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(
        encoding="utf-8"
    )

    assert 'PROFILES["sandbox-desk-service"]' in harness
    assert '"runtime/sandbox-job-service.f"' in harness
    assert "SBOX DESK SERVICE LOAD PASS" in harness
    profile = harness.split(
        'PROFILES["sandbox-desk-service"]', 1
    )[1].split("\n\n\n", 1)[0]
    assert "linked=True" in profile
    assert "include_large_sample=False" in profile
    assert "initial_files=" not in profile
