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

    assert mutable_definition.search(host) is None
    assert "SBOX-HOST-ENTRY-RESOLVE-EXACT" in host
    assert "SBOX-HOST-INIT" in host
    assert "SBOX-HOST-RUN-SLICE" in host
    assert "SBOX-HOST-CANCEL" in host
    assert "SBOX-HOST-FINISH" in host
    assert "SBOX-HOST-RELEASE" in host
    assert "SBOX-VM-INSTANCE-BOUND?" in host
    assert ": SBOX-VM-INSTANCE-BOUND?" in vm
