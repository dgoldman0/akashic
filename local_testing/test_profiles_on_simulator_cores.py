#!/usr/bin/env python3
"""Contract profiles that lend work to other full cores, on the simulator.

Four profiles in akashic_tui.py run their contracts in their boot scripts
on machines of several full cores, or lend sandbox jobs to them:
``sandbox-capability-workers-contracts`` on four cores lends every job to
the other cores, ``agent-security`` and ``audio-contracts`` run on two, and
``sandbox-job-service-gate`` checks the job service on one. Their smoke
runs on the emulator. Here each profile's image boots in MegaPad's
simulator on the profile's own cores (``akashic_tui._boot_in_simulator``),
where its boot script runs the contracts to their end, and the test
requires the profile's stable markers and none of its failure markers.
"""

from __future__ import annotations

from pathlib import Path
import sys

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402

PROFILE_NAMES = (
    "sandbox-capability-workers-contracts",
    "agent-security",
    "audio-contracts",
    "sandbox-job-service-gate",
)


@pytest.mark.parametrize("profile_name", PROFILE_NAMES)
def test_the_profile_passes_on_the_simulators_cores(
    profile_name: str, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setattr(harness, "OUTPUT_ROOT", tmp_path)
    profile = harness.PROFILES[profile_name]
    image = harness.build_image(profile_name, tmp_path / f"{profile_name}.img")
    runtime = harness._boot_in_simulator(image, profile)
    said = bytes(runtime.uart_output).decode("latin-1")
    assert not [marker for marker in profile.failure_markers if marker in said], said[-2000:]
    assert not [marker for marker in profile.stable_markers if marker not in said], said[-2000:]
    status = runtime.core_status()
    assert len(status) == profile.full_cores
    if profile_name == "sandbox-capability-workers-contracts":
        # Every job went to another core, so a worker ran them.
        assert any(core["semantic_steps"] for core in status[1:])
