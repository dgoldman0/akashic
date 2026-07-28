#!/usr/bin/env python3
"""Static contracts for the permanent Stage 1 neutral sandbox boundary."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"
POLICY_PATH = LOCAL_TESTING / "refactor_architecture.json"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import (  # noqa: E402
    PROVIDED_RE,
    dependency_closure,
    module_key,
)


SANDBOX_MODULES = (
    Path("sandbox/format.f"),
    Path("sandbox/machine.f"),
    Path("sandbox/candidate.f"),
    Path("sandbox/profile.f"),
    Path("sandbox/plan.f"),
    Path("sandbox/binding.f"),
    Path("sandbox/compiler.f"),
    Path("sandbox/verifier.f"),
    Path("sandbox/vm.f"),
)

FORBIDDEN_DEPENDENCY_PREFIXES = (
    "agent/",
    "interop/",
    "runtime/",
    "store/",
    "tui/",
)


def _source(module: Path) -> str:
    return (AKASHIC_ROOT / module).read_text(encoding="utf-8")


def test_stage1_foundation_has_bounded_unique_module_identities() -> None:
    identities: list[str] = []
    for module in SANDBOX_MODULES:
        matches = PROVIDED_RE.findall(_source(module))
        assert len(matches) == 1, module
        identity = matches[0]
        assert len(identity.encode("ascii")) <= 23
        identities.append(identity)

    assert len({module_key(identity) for identity in identities}) == len(identities)


def test_stage1_foundation_dependency_closure_is_neutral() -> None:
    closure = dependency_closure(
        AKASHIC_ROOT,
        tuple(module.as_posix() for module in SANDBOX_MODULES),
    )

    assert "sandbox/format.f" in closure
    assert "sandbox/compiler.f" in closure
    assert "sandbox/verifier.f" in closure
    assert "sandbox/vm.f" in closure
    assert "utils/memory-span.f" in closure
    assert "utils/caller-span.f" in closure
    assert all(
        not module.startswith(FORBIDDEN_DEPENDENCY_PREFIXES)
        for module in closure
    )
    assert "utils/itc.f" not in closure
    assert "store/contract-vm.f" not in closure


def test_stage1_foundation_owns_no_mutable_module_scratch() -> None:
    mutable_definition = re.compile(
        r"^\s*(?:VARIABLE|VALUE|CREATE)\b",
        re.MULTILINE,
    )
    for module in SANDBOX_MODULES:
        assert mutable_definition.search(_source(module)) is None, module


def test_format_contract_is_explicit_width_and_subtraction_first() -> None:
    source = _source(Path("sandbox/format.f"))

    assert "SBOX-BYTE-LENGTH-MAX" in source
    assert "SBOX-BYTE-ALIGN" in source
    assert "SBOX-BYTE-PAD16" in source
    assert "SBOX-BYTE-SLICE" in source
    assert "2 PICK 2 PICK - OVER SWAP U>" in source
    assert "_SBOX-BYTE-U16@" in source
    assert "_SBOX-BYTE-U32@" in source
    assert "_SBOX-BYTE-U64@" in source
    assert "C@" in source
    assert " W@" not in source
    assert " L@" not in source


def test_sandbox_is_an_independent_architecture_prefix() -> None:
    policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
    assert "sandbox/" in policy["ownership"]["independent_prefixes"]


def test_focused_foundation_profiles_are_registered() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")
    assert 'PROFILES["sandbox-format-contracts"]' in harness
    assert 'PROFILES["sandbox-core-contracts"]' in harness
    assert 'PROFILES["sandbox-stage1-contracts"]' in harness
    assert 'PROFILES["sandbox-stage1-vm-scalar-contracts"]' in harness
    assert 'PROFILES["sandbox-stage1-vm-state-contracts"]' in harness
    assert 'PROFILES["sandbox-stage1-vm-terminal-contracts"]' in harness
