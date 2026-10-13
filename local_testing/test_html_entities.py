#!/usr/bin/env python3
"""The HTML named character references in markup/html-entities.f."""

from __future__ import annotations

import re

from test_widget_pointer import _run_forth  # also puts MegaPad on the path

import generate_html_entities as generator

ROOTS = ("markup/html-entities.f",)


def _counts(output: str) -> tuple[int, int]:
    match = re.search(r"\x02\s*(-?\d+)\s+(-?\d+)\s*\x03", output)
    assert match is not None, output[-3000:]
    return int(match.group(1)), int(match.group(2))


def test_generated_table_is_current() -> None:
    assert generator.main(["--check"]) == 0


def test_every_reference_decodes_to_its_scalars() -> None:
    entries = generator.references()
    lines = [
        "VARIABLE _HE-N  VARIABLE _HE-BAD",
        ": _HE-CHECK  ( a u cp1 cp2 n -- )",
        "  >R >R >R HENT-LOOKUP ROT R> = ROT R> = ROT R> = AND AND",
        "  0= IF 1 _HE-BAD +! THEN 1 _HE-N +! ;",
        # The whole text arrived, and the index found every entry.
        "_HENT-AT @ _HENT-BYTES = 0= IF 1 _HE-BAD +! THEN",
    ]
    for name, scalars in entries:
        cp2 = scalars[1] if len(scalars) == 2 else 0
        lines.append(f'S" {name}" {scalars[0]} {cp2} {len(scalars)} _HE-CHECK')
    lines.append("2 EMIT _HE-N @ . _HE-BAD @ . 3 EMIT")
    output = _run_forth(lines, roots=ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    assert _counts(output) == (len(entries), 0)


def test_names_are_exact_and_case_sensitive() -> None:
    """Only a whole name, in its own case, finds a reference."""

    lines = [
        ": _HE-NONE  ( a u -- ) HENT-LOOKUP 2 EMIT . . . 3 EMIT ;",
        'S" " _HE-NONE',
        'S" am" _HE-NONE',
        'S" ampx" _HE-NONE',
        'S" aMP" _HE-NONE',
        'S" zzzzzzzz" _HE-NONE',
        'S" CounterClockwiseContourIntegralX" _HE-NONE',
        ": _HE-ONE  ( a u -- ) HENT-LOOKUP 2 EMIT . . . 3 EMIT ;",
        'S" AMP" _HE-ONE',
        'S" amp" _HE-ONE',
        'S" acE" _HE-ONE',
    ]
    output = _run_forth(lines, roots=ROOTS).decode("utf-8", errors="replace")
    assert "not found" not in output and "underflow" not in output, output[-3000:]
    # Each prints n cp2 cp1.
    found = [
        tuple(int(value) for value in group.split())
        for group in re.findall(r"\x02([^\x03]*)\x03", output)
    ]
    assert found == [
        (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0),
        (1, 0, 38), (1, 0, 38), (2, 0x333, 0x223E),
    ]
