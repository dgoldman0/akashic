#!/usr/bin/env python3
"""Static contracts for the Stage 2 runtime integration boundary."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402


OWNER = Path("runtime/sandbox-module-owner.f")
HOST = Path("runtime/sandbox-host.f")
VM = Path("sandbox/vm.f")
VERTICAL = Path("sandbox-stage2-vertical.f")


def test_module_owner_is_above_the_neutral_sandbox() -> None:
    closure = dependency_closure(AKASHIC_ROOT, (OWNER.as_posix(),))

    assert "runtime/identity.f" in closure
    assert "sandbox/plan.f" in closure
    assert "sandbox/profile.f" in closure
    assert "utils/itc.f" not in closure
    assert "store/contract-vm.f" not in closure
    assert not any(
        module.startswith(("agent/", "interop/", "store/", "tui/"))
        for module in closure
    )


def test_module_owner_has_no_cross_invocation_scratch() -> None:
    source = (AKASHIC_ROOT / OWNER).read_text(encoding="utf-8")
    mutable_definition = re.compile(
        r"^\s*(?:VARIABLE|VALUE|CREATE)\b",
        re.MULTILINE,
    )

    assert mutable_definition.search(source) is None
    assert "SBOX-MODULE-OWNER-RESOLVE-EXACT" in source
    assert "SBOX-MODULE-OWNER-ADD" in source
    assert "SBOX-MODULE-OWNER-S-STALE-REVISION" in source


def test_module_owner_profile_is_registered() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")

    assert 'PROFILES["sandbox-module-owner-contracts"]' in harness


def test_invocation_host_stays_above_the_neutral_sandbox() -> None:
    closure = dependency_closure(AKASHIC_ROOT, (HOST.as_posix(),))

    assert "runtime/context.f" in closure
    assert "sandbox/vm.f" in closure
    assert OWNER.as_posix() not in closure
    assert "utils/itc.f" not in closure
    assert "store/contract-vm.f" not in closure
    assert not any(
        module.startswith(("agent/", "interop/", "store/", "tui/"))
        for module in closure
    )


def test_invocation_host_is_per_run_and_uses_exact_vm_ownership() -> None:
    host = (AKASHIC_ROOT / HOST).read_text(encoding="utf-8")
    vm = (AKASHIC_ROOT / "sandbox/vm.f").read_text(encoding="utf-8")
    mutable_definition = re.compile(
        r"^\s*(?:VARIABLE|VALUE|CREATE)\b",
        re.MULTILINE,
    )
    multiline_paren_comment = re.compile(
        r"^\s*\([^)\n]*$",
        re.MULTILINE,
    )

    assert mutable_definition.search(host) is None
    assert multiline_paren_comment.search(host) is None
    assert multiline_paren_comment.search(vm) is None
    assert "CTX-FREE DROP" not in host
    assert "FREE DROP" not in host
    assert "SBOX-HOST-ENTRY-RESOLVE-EXACT" in host
    assert "SBOX-HOST-INIT" in host
    assert "SBOX-HOST-RUN-SLICE" in host
    assert "SBOX-HOST-CANCEL" in host
    assert "SBOX-HOST-FINISH" in host
    assert "SBOX-HOST-RELEASE" in host
    assert "SBOX-VM-INSTANCE-BOUND?" in host
    assert ": SBOX-VM-INSTANCE-BOUND?" in vm


def test_successful_finish_does_not_rescrub_proven_zero_allocations() -> None:
    host = (AKASHIC_ROOT / HOST).read_text(encoding="utf-8")
    vm = (AKASHIC_ROOT / VM).read_text(encoding="utf-8")
    generic = host.split(": _SHOST-CLEANUP  ", 1)[1].split(
        ": _SHOST-FREE-ZEROED", 1
    )[0]
    finished = host.split(": _SHOST-CLEANUP-FINISHED", 1)[1].split(
        ": _SHOST-DROP10", 1
    )[0]
    finish = host.split(": SBOX-HOST-FINISH", 1)[1].split(
        ": SBOX-HOST-CONTEXT-IDENTITY@", 1
    )[0]
    vm_release = vm.split(
        ": _SVM-RELEASE-FINISHED-VALIDATED", 1
    )[1].split(": SBOX-VM-RELEASE", 1)[0]

    assert generic.count("_SHOST-SCRUB-FREE") == 4
    assert "_SVM-RELEASE-FINISHED-VALIDATED" in finished
    assert "_SHOST-CLEANUP EXIT" in finished
    assert finished.count("_SHOST-FREE-ZEROED") == 4
    assert "SBOX-VM-RUN-FINISHED <>" in vm_release
    assert "_SVI.SCRUBBED @ 1 <>" in vm_release
    assert "SBOX-VM-INSTANCE-VALID?" not in vm_release
    assert "SBOX-VM-INSTANCE-DESCRIPTOR-SIZE 0 FILL" in vm_release
    assert finish.index("SBOX-VM-FINISH") < finish.index(
        "_SHOST-CLEANUP-FINISHED"
    )
    assert host.count("_SHOST-CLEANUP-FINISHED") == 2


def test_production_signature_parser_consumes_the_value_once() -> None:
    compiler = (AKASHIC_ROOT / "sandbox/compiler.f").read_text(
        encoding="utf-8"
    )
    parse_entry = compiler.split(": _SCC-PARSE-ENTRY", 1)[1].split(
        ": _SCC-RESOLVE-FIXUPS", 1
    )[0]
    signature_prefix = parse_entry.split('S" SIGNATURE"', 1)[1].split(
        "SBOX-ABI-SIGNATURE-VALUE-TO-VALUE", 1
    )[0]

    assert "_SCC-NEXT-REQUIRED" not in signature_prefix


def test_stage2_vertical_composes_two_exact_isolated_modules() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")
    vertical = (LOCAL_TESTING / VERTICAL).read_text(encoding="utf-8")

    assert 'PROFILES["sandbox-stage2-vertical"]' in harness
    assert "runtime/sandbox-module-owner.f" in harness
    assert "runtime/sandbox-host.f" in harness
    assert vertical.count("SBOX-MODULE-OWNER-ADD") == 2
    assert vertical.count("SBOX-HOST-INIT") == 2
    assert "_S2V-SOURCE-ECHO" in vertical
    assert "_S2V-SOURCE-INCREMENT" in vertical
    assert "SBOX-MODULE-OWNER-S-STALE-REVISION" in vertical
    assert "SBOX-HOST-CONTEXT-IDENTITY@" in vertical
    assert "SBOX STAGE2 VERTICAL PASS" in vertical
