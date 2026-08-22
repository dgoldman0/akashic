#!/usr/bin/env python3
"""Shared source-image and emulator helpers for KDOS TLS verticals."""

from __future__ import annotations

import base64
import sys
import time
from pathlib import Path
from typing import Any


LOCAL_TESTING = Path(__file__).resolve().parent

# Keep both direct-file and unittest-module execution working without making
# local_testing a production Python package.
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


RUN_CHUNK_STEPS = 50_000_000
TOTAL_MAX_STEPS = 1_500_000_000
TOTAL_WALL_TIMEOUT_S = 180.0
EXT_MEM_SIZE = 128 << 20


class VerticalFailure(RuntimeError):
    """An emulator lifecycle failure that needs full guest diagnostics."""


def fixture(name: str) -> bytes:
    """Load one DER fixture from the explicitly selected MegaPad tree."""
    path = (
        harness.MEGAPAD_ROOT
        / "tests"
        / "fixtures"
        / "tls"
        / f"{name}.der.b64"
    )
    encoded = b"".join(path.read_bytes().split())
    return base64.b64decode(encoded, validate=True)


def forth_bytes(name: str, data: bytes) -> list[str]:
    """Render bytes as a compact sequence of Forth C, definitions."""
    lines = [f"CREATE {name}"]
    for offset in range(0, len(data), 16):
        chunk = data[offset:offset + 16]
        lines.append(" ".join(f"{byte} C," for byte in chunk))
    return lines


def guest_failures(profile: Any, machine: Any) -> tuple[str, ...]:
    """Return de-duplicated Forth and profile failure markers."""
    raw = machine.raw_text()
    return tuple(
        dict.fromkeys(
            (
                *harness._has_forth_error(raw),  # noqa: SLF001
                *harness._matched_failure_markers(  # noqa: SLF001
                    profile,
                    raw,
                    machine.screen_text(),
                ),
            )
        )
    )


def diagnostics(machine: Any, *peers: Any) -> str:
    """Format peer state and recent guest output after a vertical failure."""
    peer_lines = []
    for index, peer in enumerate(peers, start=1):
        peer_lines.append(
            f"peer {index}: state={peer.assertion_state!r}; "
            f"errors={peer.errors!r}"
        )
    return "\n".join(
        (
            *peer_lines,
            "screen:",
            machine.screen_text(),
            "recent raw output:",
            machine.raw_text()[-8000:],
        )
    )


def run_until(
    machine: Any,
    profile: Any,
    marker: str,
    *,
    deadline: float,
    steps: list[int],
) -> None:
    """Advance one core in bounded chunks until a marker or exact failure."""
    while True:
        raw = machine.raw_text()
        failures = guest_failures(profile, machine)
        if failures:
            raise VerticalFailure(
                f"guest failed before {marker!r}: {failures!r}"
            )
        if marker in raw:
            return
        if steps[0] >= TOTAL_MAX_STEPS:
            raise VerticalFailure(
                f"guest did not reach {marker!r} within "
                f"{TOTAL_MAX_STEPS:,} steps"
            )
        remaining_wall = deadline - time.monotonic()
        if remaining_wall <= 0:
            raise VerticalFailure(
                f"guest did not reach {marker!r} within "
                f"{TOTAL_WALL_TIMEOUT_S:.0f} seconds"
            )
        report = machine.run(
            max_steps=min(
                RUN_CHUNK_STEPS,
                TOTAL_MAX_STEPS - steps[0],
            ),
            wall_timeout_s=min(5.0, remaining_wall),
            until_text=marker,
            text_scope="raw",
            advance_idle=True,
        )
        steps[0] += report.steps
        if report.reason in ("halted", "stalled"):
            raise VerticalFailure(
                f"guest stopped ({report.reason}) before {marker!r}"
            )
