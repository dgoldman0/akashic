#!/usr/bin/env python3
"""Seconds-scale contracts for the pure packed CELL value module."""

from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "akashic/tui/cell.f"


def _word(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^: {re.escape(name)}(?=\s).*?;\s*(?:\\[^\n]*)?$",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group(0)


def test_cell_value_operations_remain_pure_and_unguarded() -> None:
    source = SOURCE.read_text(encoding="utf-8")

    assert "pure stack computation" in source
    assert "[DEFINED] GUARDED" not in source
    assert "WITH-GUARD" not in source
    assert "REQUIRE ../concurrency/guard.f" not in source
    assert not re.search(r"(?m)^\s*(?:VARIABLE|CREATE|ALLOT)\b", source)

    for name in (
        "CELL-MAKE",
        "CELL-CP@",
        "CELL-FG@",
        "CELL-BG@",
        "CELL-ATTRS@",
        "CELL-FG!",
        "CELL-BG!",
        "CELL-ATTRS!",
        "CELL-CP!",
        "CELL-EQUAL?",
        "CELL-EMPTY?",
        "CELL-HAS-ATTR?",
    ):
        body = _word(source, name)
        assert re.search(
            r"(?<![A-Z0-9_-])(?:@|!)(?![A-Z0-9_-])", body
        ) is None
