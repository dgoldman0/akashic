#!/usr/bin/env python3
"""Interval timeouts must run on uptime, never on the wall clock.

event.f, semaphore.f and guard.f measure their timeouts with MS@.  These
tests prove it by moving the wall clock during a wait: a wait whose wall
clock is pinned or pushed back must still time out, and a wait whose wall
clock jumps far forward must not time out early.  A wall-clock deadline
fails both: the first case never ends and the second ends at the first poll.

The modules load over the real BIOS with a small KDOS contract, the same
pattern test_worker_job.py uses, because full KDOS fills a test machine's
dictionary by itself.  The contract's YIELD? runs a per-test hook, which is
where each test moves the wall clock through the RTC's EPOCH byte registers.
"""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys

import pytest


PROJECT_ROOT = Path(__file__).resolve().parents[2]
AKASHIC_ROOT = Path(__file__).resolve().parents[1]
MEGAPAD_ROOT = Path(os.environ.get("MEGAPAD_ROOT", PROJECT_ROOT / "megapad"))
sys.path.insert(0, str(MEGAPAD_ROOT))

from asm import assemble  # noqa: E402
from system import MegapadSystem  # noqa: E402


BIOS_PATH = MEGAPAD_ROOT / "bios.asm"
CONCURRENCY = AKASHIC_ROOT / "akashic" / "concurrency"
MODULES = (
    CONCURRENCY / "event.f",
    CONCURRENCY / "semaphore.f",
    CONCURRENCY / "guard.f",
)

# A realistic wall clock, far from the few seconds of uptime a test runs.
WALL_EPOCH_MS = 1_760_000_000_000

KDOS_CONTRACT = [
    # Two task records: event.f stores a waiting task's status in its
    # record, and guard.f tells owners apart by the current task.
    "CREATE TASK-A 0 ,",
    "CREATE TASK-B 0 ,",
    "VARIABLE CURRENT-TASK TASK-A CURRENT-TASK !",
    "1 CONSTANT T.READY",
    "2 CONSTANT T.RUNNING",
    "3 CONSTANT T.BLOCKED",
    ": T.STATUS! ! ;",
    "VARIABLE YIELD-HOOK 0 YIELD-HOOK !",
    ": YIELD? YIELD-HOOK @ ?DUP IF EXECUTE THEN ;",
    ": LOCK BEGIN DUP SPIN@ 0<> WHILE REPEAT DROP ;",
    ": UNLOCK SPIN! ;",
    "6 CONSTANT EVT-LOCK",
    "CREATE _HANDLER 0 ,",
    ": CATCH SP@ >R _HANDLER @ >R RP@ _HANDLER ! EXECUTE R> _HANDLER ! R> DROP 0 ;",
    ": THROW ?DUP IF _HANDLER @ RP! R> _HANDLER ! R> SWAP >R SP! DROP R> THEN ;",
]

# Test words shared by every case.  EPOCH-SET writes the eight EPOCH bytes
# low byte first, which is how software sets the RTC.
TEST_WORDS = [
    ": EPOCH-SET ( ms -- ) 8 0 DO DUP 255 AND 0xFFFFFF0000000B08 I + C! "
    "8 RSHIFT LOOP DROP ;",
    "VARIABLE PINNED",
    ": PIN-WALL PINNED @ EPOCH-SET ;",
    "VARIABLE POLLS",
    "EVENT EV",
    "0 SEMAPHORE SEM",
    "GUARD GRD",
    ": JUMP-THEN-SIGNAL 1 POLLS +! "
    "POLLS @ 1 = IF EPOCH@ 3600000 + EPOCH-SET THEN "
    "POLLS @ 3 = IF EV EVT-SET THEN ;",
    ": JUMP-THEN-RELEASE 1 POLLS +! "
    "POLLS @ 1 = IF EPOCH@ 3600000 + EPOCH-SET THEN "
    "POLLS @ 3 = IF TASK-A CURRENT-TASK ! GRD GUARD-RELEASE "
    "TASK-B CURRENT-TASK ! THEN ;",
]


def _forth_lines(path: Path) -> list[str]:
    source: list[str] = []
    for line in path.read_text().splitlines():
        stripped = line.split("\\", 1)[0].strip()
        if not stripped:
            continue
        if stripped.startswith("REQUIRE ") or stripped.startswith("PROVIDED "):
            continue
        source.append(stripped)
    # Pack lines below the BIOS input-buffer limit; colon definitions may
    # span packed lines.
    lines: list[str] = []
    packed = ""
    for line in source:
        candidate = f"{packed} {line}" if packed else line
        if len(candidate) <= 180:
            packed = candidate
        else:
            lines.append(packed)
            packed = line
    if packed:
        lines.append(packed)
    return lines


def _next_line(data: bytes, pos: int) -> bytes:
    newline = data.find(b"\n", pos)
    return data[pos : newline + 1] if newline >= 0 else data[pos:]


def _text(output: bytearray) -> str:
    return "".join(
        chr(value) if 0x20 <= value < 0x7F or value in (9, 10, 13) else ""
        for value in output
    )


def _feed(system: MegapadSystem, output: bytearray, lines: list[str],
          budget: int) -> str:
    data = ("\n".join(lines) + "\n").encode()
    pos = 0
    steps = 0
    while steps < budget:
        if system.cpu.halted:
            break
        if system.cpu.idle and not system.uart.has_rx_data:
            if pos >= len(data):
                break
            chunk = _next_line(data, pos)
            system.uart.inject_input(chunk)
            pos += len(chunk)
        ran = system.run_batch(min(100_000, budget - steps))
        steps += max(ran, 1)
    text = _text(output)
    if pos < len(data) or not system.cpu.idle:
        raise AssertionError(
            f"Forth input stalled at {pos}/{len(data)} bytes after {steps} "
            f"steps (a wait that never ended?):\n{text[-3000:]}"
        )
    return text


def run(lines: list[str], budget: int = 120_000_000) -> str:
    """Boot BIOS, load the contract and modules, then run lines."""
    system = MegapadSystem(ram_size=1024 * 1024, rtc_epoch_ms=WALL_EPOCH_MS)
    output = bytearray()
    system.uart.on_tx = output.append
    system.load_binary(0, assemble(BIOS_PATH.read_text()))
    system.boot()
    loaded = _feed(
        system, output,
        KDOS_CONTRACT
        + [line for path in MODULES for line in _forth_lines(path)]
        + TEST_WORDS,
        budget=200_000_000,
    )
    problems = [
        line for line in loaded.splitlines()
        if "not found" in line.lower() or "underflow" in line.lower()
    ]
    assert not problems, "module load failed:\n" + "\n".join(problems)
    output.clear()
    return _feed(system, output, lines, budget)


def _value(text: str, label: str) -> int:
    match = re.search(rf"{label}=(-?\d+)", text)
    assert match, f"{label} not printed:\n{text[-3000:]}"
    return int(match.group(1))


# The event waits below run with no current task.  _EVT-ADD-WAITER drops one
# cell too many when it registers a real task, which breaks the caller's
# stack; that separate defect is reported rather than fixed under the
# scheduler work, and these tests are about the clock, not waiter slots.


def test_event_wait_times_out_while_wall_clock_is_pinned():
    text = run([
        "0 CURRENT-TASK !",
        "EPOCH@ PINNED !",
        "' PIN-WALL YIELD-HOOK !",
        "MS@ EV 40 EVT-WAIT-TIMEOUT SWAP MS@ SWAP - "
        '." waited=" . ." signaled=" .',
        "0 YIELD-HOOK !",
    ])
    assert _value(text, "signaled") == 0
    assert _value(text, "waited") >= 40


def test_semaphore_wait_times_out_while_wall_clock_moves_back():
    text = run([
        "1000 PINNED !",
        "' PIN-WALL YIELD-HOOK !",
        'SEM 40 SEM-WAIT-TIMEOUT ." acquired=" .',
        "0 YIELD-HOOK !",
    ])
    assert _value(text, "acquired") == 0


def test_event_wait_survives_a_forward_wall_clock_jump():
    text = run([
        "0 CURRENT-TASK !",
        "0 POLLS !",
        "' JUMP-THEN-SIGNAL YIELD-HOOK !",
        'EV 600000 EVT-WAIT-TIMEOUT ." signaled=" .',
        "0 YIELD-HOOK !",
        'POLLS @ ." polls=" .',
    ])
    assert _value(text, "signaled") == -1
    assert _value(text, "polls") == 3


def test_guard_timeout_survives_a_forward_wall_clock_jump():
    text = run([
        "GRD GUARD-ACQUIRE",
        "TASK-B CURRENT-TASK !",
        "0 POLLS !",
        "' JUMP-THEN-RELEASE YIELD-HOOK !",
        'GRD 600000 GUARD-ACQUIRE-TIMEOUT ." acquired=" .',
        "0 YIELD-HOOK !",
        "GRD GUARD-RELEASE",
    ])
    assert _value(text, "acquired") == -1


def test_guard_timeout_expires_while_wall_clock_is_pinned():
    text = run([
        "GRD GUARD-ACQUIRE",
        "TASK-B CURRENT-TASK !",
        "EPOCH@ PINNED !",
        "' PIN-WALL YIELD-HOOK !",
        'GRD 40 GUARD-ACQUIRE-TIMEOUT ." acquired=" .',
        "0 YIELD-HOOK !",
        "TASK-A CURRENT-TASK ! GRD GUARD-RELEASE",
    ])
    assert _value(text, "acquired") == 0


# Every wall-clock read in the library, with the reason it needs wall time.
# Intervals and timeouts must use MS@; a new wall-clock read belongs here
# only after deciding it really means calendar time.
WALL_CLOCK_READS = {
    "akashic/utils/datetime.f": (
        {"EPOCH@": 1, "DT-NOW-MS": 2, "DT-NOW-S": 1},
        "defines the wall-clock words",
    ),
    "akashic/tui/applets/agent/providers/codex/auth.f": (
        {"EPOCH@": 1}, "token expiry is a calendar instant",
    ),
    "akashic/tui/applets/daybook/daybook.f": (
        {"DT-NOW-S": 1}, "today's date",
    ),
    "akashic/tui/applets/daybook/automation-service.f": (
        {"EPOCH@": 2}, "reminders fire at calendar instants, read only once set",
    ),
    "akashic/tui/applets/agent/dispatch.f": (
        {"DT-NOW-MS": 1}, "a scheduled run's record says when it ran, read only once set",
    ),
    "akashic/node/node.f": ({"DT-NOW-S": 1}, "block timestamp"),
    "akashic/web/response.f": ({"DT-NOW-S": 1}, "HTTP Date header"),
    "akashic/web/server.f": ({"DT-NOW-S": 1}, "log stamp"),
    "akashic/web/middleware.f": ({"DT-NOW-S": 1}, "log stamp"),
}


def _wall_clock_reads() -> dict[str, dict[str, int]]:
    found: dict[str, dict[str, int]] = {}
    for path in sorted((AKASHIC_ROOT / "akashic").rglob("*.f")):
        counts: dict[str, int] = {}
        for line in path.read_text(errors="replace").splitlines():
            line = re.sub(r"(^|\s)\\(\s.*|$)", " ", line)
            line = re.sub(r"(^|\s)\((\s[^)]*)?\)", " ", line)
            for token in line.split():
                if token in ("EPOCH@", "DT-NOW-MS", "DT-NOW-S"):
                    counts[token] = counts.get(token, 0) + 1
        if counts:
            found[str(path.relative_to(AKASHIC_ROOT))] = counts
    return found


def test_wall_clock_is_read_only_where_calendar_time_is_meant():
    expected = {name: counts for name, (counts, _) in WALL_CLOCK_READS.items()}
    assert _wall_clock_reads() == expected


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-q"]))
