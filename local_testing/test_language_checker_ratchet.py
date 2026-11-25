"""The findings ratchet: Uroko's checker over the plain library.

The checker (``toolchain/language``, described in
``docs/language/checker.md``) runs over every library module with GUARDED
undefined, as its measurement's main figures do.  Its counts of findings by
type, of inferred effects that mismatch their comments, and of definitions
not inferred, in all and by cause, must match the baseline in
``language_checker_counts.json``.  A count that grows is a regression: the
change adds a finding, a mismatch or a word the checker cannot follow.  A
count that falls is a gain, which the baseline records so that it holds.
Either way the baseline changes in the same commit as the change that moves
it, written by::

    python3 -m toolchain.language.measure --groups library --no-strict \\
        --ratchet local_testing/language_checker_counts.json
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from akashic_path import AKASHIC_ROOT  # noqa: E402  (also puts the root on the path)

from toolchain.language.measure import build, ratchet_counts  # noqa: E402
from toolchain.language.vocabulary import megapad_root  # noqa: E402

BASELINE = Path(__file__).with_name("language_checker_counts.json")
MEGAPAD_ROOT = megapad_root(Path(__file__).absolute().parents[1])


def test_the_checkers_counts_over_the_library_do_not_move_unrecorded():
    if not (MEGAPAD_ROOT / "kdos.f").is_file():
        pytest.skip("MegaPad checkout not found; set MEGAPAD_ROOT")
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))["counts"]
    counts = ratchet_counts(build(AKASHIC_ROOT, MEGAPAD_ROOT, [], ["library"]))
    grew = {name: (baseline.get(name, 0), number) for name, number in counts.items()
            if number > baseline.get(name, 0)}
    fell = {name: (number, counts.get(name, 0)) for name, number in baseline.items()
            if counts.get(name, 0) < number}
    message = []
    if grew:
        message.append("grew, from the baseline to now: " + ", ".join(
            f"{name} {was} -> {now}" for name, (was, now) in sorted(grew.items())))
    if fell:
        message.append("fell, which the baseline must record: " + ", ".join(
            f"{name} {was} -> {now}" for name, (was, now) in sorted(fell.items())))
    assert not message, "; ".join(message) + (
        ".  Rewrite local_testing/language_checker_counts.json in the commit that"
        " moves the counts (see this file's docstring).")
