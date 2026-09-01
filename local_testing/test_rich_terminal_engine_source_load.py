"""Focused real-Forth source-load check for the neutral retained engine."""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "akashic"
LOCAL_TESTING = ROOT / "local_testing"


def _default_megapad_root() -> Path:
    if ROOT.name.startswith("akashic-"):
        suffix = ROOT.name.removeprefix("akashic-")
        paired = ROOT.parent / f"megapad-{suffix}"
        if paired.is_dir():
            return paired
    return ROOT.parent / "megapad"


MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", _default_megapad_root()))

sys.path.insert(0, str(LOCAL_TESTING))
sys.path.insert(0, str(MEGAPAD_ROOT))

from asm import assemble  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from system import MegapadSystem  # noqa: E402


BIOS_PATH = MEGAPAD_ROOT / "bios.asm"
KDOS_PATH = MEGAPAD_ROOT / "kdos.f"
RUN_BATCH_STEPS = 100_000

# This is a wall-clock watchdog for one compile-only Akashic dependency
# closure, not a guest instruction budget or a product capacity.  Keeping the
# test independent of a cumulative step ceiling lets the timing-correct native
# scheduler choose its normal execution path.
SOURCE_LOAD_WALL_SECONDS = 60.0


def _source_lines(path: Path) -> list[str]:
    """Return executable lines while the resolver supplies module order."""
    lines: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("\\"):
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        lines.append(line)
    return lines


def _next_line(payload: bytes, position: int) -> bytes:
    end = payload.find(b"\n", position)
    return payload[position : end + 1] if end >= 0 else payload[position:]


def _forth_errors(output: bytes) -> list[str]:
    text = output.decode("utf-8", errors="replace")
    patterns = (
        re.compile(r"(?i)\?\s+\(not found\)\s*$"),
        re.compile(
            r"(?i)^\s*(?:undefined word|stack underflow|"
            r"branch offset overflow|evaluate depth limit exceeded|"
            r"dictionary full|module not found|path component not found)\b"
        ),
        re.compile(r"^\s*\?\s*$"),
    )
    return [
        line
        for line in text.splitlines()
        if any(pattern.search(line) for pattern in patterns)
    ]


def test_neutral_engine_dependency_closure_source_loads_in_definition_order() -> None:
    modules = dependency_order(SOURCE_ROOT, ("tui/rich-terminal/engine.f",))
    assert modules == (
        "utils/uint-range.f",
        "utils/memory-span.f",
        "concurrency/event.f",
        "concurrency/semaphore.f",
        "concurrency/guard.f",
        "utils/string.f",
        "tui/rich-terminal/engine.f",
    )

    source = _source_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for module in modules:
        source.extend(_source_lines(SOURCE_ROOT / module))
    source.extend(("30 EMIT", "RTE-HYBRID-ADMISSION-BYTES .", "31 EMIT"))

    system = MegapadSystem(ram_size=1 << 20, ext_mem_size=16 << 20)
    output = bytearray()
    system.uart.on_tx = output.append
    system.load_binary(0, assemble(BIOS_PATH.read_text(encoding="utf-8")))
    system.boot()

    payload = ("\n".join(source) + "\n").encode()
    position = 0
    steps = 0
    deadline = time.monotonic() + SOURCE_LOAD_WALL_SECONDS
    complete = False
    while time.monotonic() < deadline:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if position >= len(payload):
                complete = True
                break
            line = _next_line(payload, position)
            system.uart.inject_input(line)
            position += len(line)
            continue
        executed = system.run_batch(RUN_BATCH_STEPS)
        steps += max(executed, 1)

    assert complete, f"engine source load did not quiesce after {steps:,} steps"
    assert not system.cpu.halted, "engine source load halted the guest"
    errors = _forth_errors(output)
    assert not errors, "Forth compile errors:\n" + "\n".join(errors[-10:])

    start = output.find(b"\x1e")
    end = output.find(b"\x1f", start + 1)
    assert start >= 0 and end > start, "engine source-load probe did not execute"
    assert b"320" in output[start + 1 : end]
