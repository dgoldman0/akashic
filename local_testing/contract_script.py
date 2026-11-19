"""Run a contract script as a pytest test.

Many contract scripts in local_testing (Library's L12 and Streams' L13
among them) register a profile of their own, build its image and boot it
through the harness's smoke command, all from a ``main()`` that only a
person ran.  A test file with no pytest test is a unit that runs nothing,
so the test selection tool never saw such a script fail.  A script calls
``run_as_test`` from a test function of its own: the script's image and the
harness's captures go to pytest's temporary folder, the script's own
arguments take their defaults, and the test passes when ``main()`` answers
0.  The script keeps its checked-in step budget and wall timeout.
"""

from __future__ import annotations

import sys
from pathlib import Path
from types import ModuleType

import pytest


def run_as_test(script: ModuleType, tmp_path: Path,
                monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(script.harness, "OUTPUT_ROOT", tmp_path)
    if hasattr(script, "IMAGE"):
        monkeypatch.setattr(script, "IMAGE",
                            tmp_path / f"{script.__name__}.img")
    monkeypatch.setattr(sys, "argv", [script.__file__])
    assert script.main() == 0
