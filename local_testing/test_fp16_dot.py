#!/usr/bin/env python3
"""FP16-DOT and FP16-DOT32 in akashic/math/fp16.f.

FP16-DOT takes its pairs 32 at a time.  It used to add the chunks' binary32
results with an integer +, which is wrong whenever more than one chunk is
nonzero.  The values here make every product and partial sum exact, so the
expected sum does not depend on the order the backend adds in, and these
tests hold on any MegaPad backend.
"""

from __future__ import annotations

import re
import struct

import pytest

from forth_snapshot import ForthSnapshot, program_output


SNAPSHOT = ForthSnapshot(
    ("math/fp16.f",),
    prelude=(
        "CREATE T-BUF 1024 ALLOT",
        "HBW-TALIGN 64 HBW-ALLOT CONSTANT T-A",
        "HBW-TALIGN 64 HBW-ALLOT CONSTANT T-B",
        ': T-X ( u -- ) ." @" HEX U. DECIMAL ;',
        ": T-FILL ( fp16 addr -- ) DUP 64 + SWAP DO DUP I W! 2 +LOOP DROP ;",
    ),
)


def half(value: float) -> int:
    return struct.unpack("<H", struct.pack("<e", value))[0]


def single(value: float) -> int:
    return struct.unpack("<I", struct.pack("<f", value))[0]


def store_pairs(pairs: list[tuple[float, float]]) -> list[str]:
    """Forth lines that store the pairs interleaved at T-BUF."""

    lines, line = [], ""
    for index, (a, b) in enumerate(pairs):
        part = f"{half(a)} T-BUF {4 * index} + W! {half(b)} T-BUF {4 * index + 2} + W! "
        if len(line) + len(part) > 200:
            lines.append(line)
            line = ""
        line += part
    return lines + [line] if line else lines


def run(lines: list[str]) -> list[int]:
    text = program_output(SNAPSHOT.run(lines), lines)
    return [int(value, 16) for value in re.findall(r"@([0-9A-F]+)", text)]


@pytest.mark.parametrize("count", [1, 31, 32, 33, 64, 100])
def test_fp16_dot_adds_its_chunks_in_binary32(count: int) -> None:
    integers = [((index % 7) - 3.0, (index % 5) + 1.0) for index in range(count)]
    fractions = [(0.5, 0.25)] * count
    for pairs in (integers, fractions):
        lines = store_pairs(pairs) + [f"T-BUF {count} FP16-DOT T-X", "TCTRL@ T-X"]
        total, control = run(lines)
        assert total == single(sum(a * b for a, b in pairs))
        assert control == 0


def test_the_dot_words_ignore_a_leftover_accumulate_setting() -> None:
    pairs = [((index % 7) - 3.0, (index % 5) + 1.0) for index in range(33)]
    lines = [
        f"{half(1.0)} T-A T-FILL {half(2.0)} T-B T-FILL",
        "T-A T-B FP16-DOT32 T-X",
        "1 TCTRL! T-A T-B FP16-DOT32 T-X",
        "TCTRL@ T-X",
        *store_pairs(pairs),
        f"1 TCTRL! T-BUF {len(pairs)} FP16-DOT T-X",
    ]
    first, again, control, total = run(lines)
    assert first == again == single(64.0)
    assert control == 0
    assert total == single(sum(a * b for a, b in pairs))
