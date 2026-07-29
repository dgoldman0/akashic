#!/usr/bin/env python3
"""Static contracts for the focused Stage 3 Agent sandbox landing."""

from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure, dependency_markers  # noqa: E402


OPERATIONS = Path("tui/applets/agent/sandbox-operations.f")
OWNER = Path("runtime/sandbox-module-owner.f")
SERVICE = Path("tui/applets/agent/service.f")
FOCUSED_FIXTURE = Path("sandbox-stage3-agent-operations.f")
FOCUSED_PROFILES = (
    ("sandbox-stage3-agent-operations", "_S3A-COMPILE-VERIFY-RUN"),
    ("sandbox-stage3-agent-test", "_S3A-TEST-RUN"),
    ("sandbox-stage3-agent-invoke", "_S3A-INVOKE-RUN"),
)

PUBLIC_WORDS = (
    "AGENT-SBOX-COMPILE",
    "AGENT-SBOX-VERIFY",
    "AGENT-SBOX-TEST",
    "AGENT-SBOX-INVOKE",
    "AGENT-SBOX-RESULT-RELEASE",
)

FORBIDDEN_DEPENDENCY_FRAGMENTS = (
    "tool-gateway",
    "request-bus",
    "schema",
    "digest",
    "practice",
    "desk",
    "provider",
    "conversation",
    "vfs",
)


def _source(module: Path) -> str:
    return (AKASHIC_ROOT / module).read_text(encoding="utf-8")


def test_agent_service_explicitly_imports_sandbox_operations() -> None:
    markers = dependency_markers(_source(SERVICE), SERVICE.as_posix())

    assert any(
        marker.raw == "sandbox-operations.f"
        and marker.normalized == OPERATIONS.as_posix()
        for marker in markers
    )


def test_agent_sandbox_operations_use_only_the_focused_runtime_path() -> None:
    closure = dependency_closure(AKASHIC_ROOT, (OPERATIONS.as_posix(),))

    assert "sandbox/compiler.f" in closure
    assert "sandbox/verifier.f" in closure
    assert "runtime/sandbox-module-owner.f" in closure
    assert "runtime/sandbox-host.f" in closure

    for module in closure:
        normalized = module.lower()
        assert not any(
            fragment in normalized
            for fragment in FORBIDDEN_DEPENDENCY_FRAGMENTS
        ), module


def test_agent_sandbox_operations_publish_the_explicit_api() -> None:
    source = _source(OPERATIONS)
    owner = _source(OWNER)

    for word in PUBLIC_WORDS:
        definition = re.compile(
            rf"^:\s+{re.escape(word)}(?:\s|$)",
            re.MULTILINE,
        )
        assert definition.search(source) is not None, word
    assert ": SBOX-MODULE-OWNER-SPAN-DISJOINT?" in owner
    assert source.count("SBOX-MODULE-OWNER-SPAN-DISJOINT?") >= 3


def test_provider_boundary_cannot_dispatch_sandbox_operations() -> None:
    agent = AKASHIC_ROOT / "tui/applets/agent"
    boundary = (
        agent / "runtime.f",
        agent / "tool-gateway.f",
        agent / "turn-request.f",
        agent / "provider.f",
        agent / "provider-source.f",
        *sorted((agent / "providers").rglob("*.f")),
    )

    for path in boundary:
        source = path.read_text(encoding="utf-8").lower()
        assert "agent-sbox" not in source, path
        assert "sandbox-operations" not in source, path


def test_stage3_agent_operations_have_a_focused_executable_fixture() -> None:
    harness = (LOCAL_TESTING / "akashic_tui.py").read_text(encoding="utf-8")
    fixture = (LOCAL_TESTING / FOCUSED_FIXTURE).read_text(encoding="utf-8")

    assert f'"{FOCUSED_FIXTURE.as_posix()}"' in harness
    assert "_S3A-OWNER-TAIL" in fixture
    for profile, entry_word in FOCUSED_PROFILES:
        definition = re.compile(
            rf'PROFILES\["{re.escape(profile)}"\]\s*=\s*\(\s*'
            rf'_sandbox_stage3_agent_profile\(\s*"{re.escape(entry_word)}"',
            re.MULTILINE,
        )
        assert definition.search(harness) is not None, profile
        assert entry_word in fixture
    for word in PUBLIC_WORDS:
        assert word in fixture
