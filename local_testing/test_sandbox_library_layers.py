#!/usr/bin/env python3
"""The sandbox library layers depend only downward and never on the TUI.

sandbox/ is the neutral runtime and runtime/sandbox-*.f is the general host
library.  interop/ and tui/, including Desk, consume them.  Every module of
the two lower layers is checked, so a new module joins without a test edit.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
AKASHIC_ROOT = REPO_ROOT / "akashic"
LOCAL_TESTING = REPO_ROOT / "local_testing"

sys.path.insert(0, str(LOCAL_TESTING))

from forth_dependencies import dependency_closure  # noqa: E402


def _modules(directory: str, pattern: str) -> list[str]:
    return sorted(
        path.relative_to(AKASHIC_ROOT).as_posix()
        for path in (AKASHIC_ROOT / directory).glob(pattern)
    )


NEUTRAL = _modules("sandbox", "*.f")
HOST_LIBRARY = _modules("runtime", "sandbox-*.f")


def test_both_layers_hold_their_modules() -> None:
    assert "sandbox/vm.f" in NEUTRAL
    assert {
        "runtime/sandbox-host.f",
        "runtime/sandbox-limits.f",
        "runtime/sandbox-job-service.f",
        "runtime/sandbox-build.f",
    } <= set(HOST_LIBRARY)


@pytest.mark.parametrize("module", HOST_LIBRARY)
def test_host_library_never_reaches_interop_or_the_tui(module: str) -> None:
    for dependency in dependency_closure(AKASHIC_ROOT, (module,)):
        assert not dependency.startswith(("tui/", "interop/")), dependency


@pytest.mark.parametrize("module", NEUTRAL)
def test_neutral_runtime_never_reaches_a_host_layer(module: str) -> None:
    for dependency in dependency_closure(AKASHIC_ROOT, (module,)):
        assert not dependency.startswith(
            ("tui/", "interop/", "runtime/")
        ), dependency
