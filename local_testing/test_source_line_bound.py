#!/usr/bin/env python3
"""Every Forth source line fits the loader's EVALUATE buffer.

KDOS loads source a line at a time through EVALUATE, whose input holds at
most 255 bytes; a longer line fails with "EVALUATE input exceeds 255 bytes"
and leaves the rest of its file uncompiled.  The native runtime the focused
suites use has no such bound, so this check reads every module and fixture
instead.
"""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# The input buffer KDOS's EVALUATE takes, in bytes.
LINE_BYTES_MAX = 255


def test_every_forth_line_fits_the_loader() -> None:
    long_lines = []
    for folder in ("akashic", "local_testing"):
        for path in sorted((ROOT / folder).rglob("*.f")):
            for number, line in enumerate(path.read_bytes().split(b"\n"), 1):
                size = len(line.rstrip(b"\r"))
                if size > LINE_BYTES_MAX:
                    long_lines.append(f"{path.relative_to(ROOT)}:{number}: {size} bytes")
    assert not long_lines, long_lines
