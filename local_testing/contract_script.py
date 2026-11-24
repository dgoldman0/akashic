"""Run a contract script as a pytest test.

Many contract scripts in local_testing (Library's L12 and Streams' L13
among them) register a profile of their own, build its image and boot it
through the harness's smoke command, all from a ``main()`` that only a
person ran.  A test file with no pytest test is a unit that runs nothing,
so the test selection tool never saw such a script fail.  A script calls
``run_as_test`` from a test function of its own: the script's image and the
harness's captures go to pytest's temporary folder, and the test passes
when ``main()`` answers 0.  The script keeps its checked-in step budget and
wall timeout.

``main()`` sees the arguments the test passes as its command line, so a
script whose parser requires a mode, such as ``--static-only`` or
``--lifecycle``, runs each mode from a test of its own; a script given no
arguments takes its defaults.  A script that builds one image names its path
``IMAGE``; one that builds several names their folder ``IMAGE_DIR``.  A
script that imports the harness only inside ``main()`` has its captures
moved all the same, since the harness module is shared.

Contracts that are only profiles of the harness, run from its command line
as ``akashic_tui.py smoke PROFILE``, run under pytest through
``run_profile_smoke``, which builds the profile's image in pytest's
temporary folder and runs its smoke with the profile's own step budget and
timeout, as the command line does.
"""

from __future__ import annotations

import sys
from pathlib import Path
from types import ModuleType

import pytest


def run_as_test(script: ModuleType, tmp_path: Path,
                monkeypatch: pytest.MonkeyPatch, *args: str) -> None:
    harness = getattr(script, "harness", None)
    if harness is None:
        import akashic_tui as harness
    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    if hasattr(script, "IMAGE"):
        monkeypatch.setattr(script, "IMAGE",
                            tmp_path / f"{script.__name__}.img")
    if hasattr(script, "IMAGE_DIR"):
        monkeypatch.setattr(script, "IMAGE_DIR", tmp_path)
    monkeypatch.setattr(sys, "argv", [script.__file__, *args])
    assert script.main() == 0


def run_profile_smoke(profile: str, tmp_path: Path,
                      monkeypatch: pytest.MonkeyPatch, *,
                      cols: int = 100, rows: int = 32) -> None:
    import akashic_tui as harness

    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    image = harness.build_image(profile, tmp_path / f"{profile}.img")
    max_steps, timeout = harness._smoke_limits(profile, None, None)
    assert harness.smoke(profile, image, cols=cols, rows=rows,
                         max_steps=max_steps, timeout=timeout)
