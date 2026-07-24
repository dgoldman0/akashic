#!/usr/bin/env python3
"""Fresh-dictionary structural and execution contracts for L12 queries."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


STRUCTURAL_PROFILE = "library-query-l12-contracts"
EXECUTION_PROFILE = "library-query-l12-execution-contracts"
STRUCTURAL_IMAGE = Path("/tmp/akashic-library-query-l12-contracts-v2.img")
EXECUTION_IMAGE = Path("/tmp/akashic-library-query-l12-execution-contracts.img")
STRUCTURAL_CONTRACT = LOCAL_TESTING / "lib-query-l12-test.f"
EXECUTION_CONTRACT = LOCAL_TESTING / "lib-query-exec-l12.f"

STRUCTURAL_AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/query.f
REQUIRE local_testing/lib-query-l12-test.f
_LQ12-RUN
0 0xFFFFFF0000000006 C!
"""

EXECUTION_AUTOEXEC = r"""\ autoexec.f
ENTER-USERLAND
REQUIRE tui/applets/library/query.f
REQUIRE local_testing/lib-query-exec-l12.f
0 0xFFFFFF0000000006 C!
"""


def run_profile(
    profile_name: str,
    image_path: Path,
    contract_path: Path,
    autoexec: str,
    ready_marker: str,
    max_steps: int,
    timeout: float,
) -> bool:
    harness.PROFILES[profile_name] = harness.Profile(
        roots=(
            "persistence/store.f",
            "tui/applets/library/persistence-adapter.f",
            "tui/applets/library/query.f",
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(ready_marker,),
        stable_markers=(ready_marker,),
        failure_markers=(
            "LIBRARY QUERY L12 FAIL",
            "LIBRARY QUERY L12 ASSERT",
            "LIBRARY QUERY L12 STACK",
            "LIBRARY QUERY L12 EXEC FAIL",
            "LIBRARY QUERY L12 EXEC ASSERT",
            "LIBRARY QUERY L12 EXEC STACK",
            "DRIVER THROW",
            " ? (not found)",
            "dictionary full",
            "exception",
        ),
        initial_files=(
            (f"local_testing/{contract_path.name}", contract_path.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=8192,
    )
    image = harness.build_image(profile_name, image_path)
    return harness.smoke(
        profile_name,
        image,
        cols=120,
        rows=40,
        max_steps=max_steps,
        timeout=timeout,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=360.0)
    args = parser.parse_args()

    structural_ok = run_profile(
        STRUCTURAL_PROFILE,
        STRUCTURAL_IMAGE,
        STRUCTURAL_CONTRACT,
        STRUCTURAL_AUTOEXEC,
        "LIBRARY QUERY L12 PASS",
        10_000_000_000,
        args.timeout,
    )
    execution_ok = run_profile(
        EXECUTION_PROFILE,
        EXECUTION_IMAGE,
        EXECUTION_CONTRACT,
        EXECUTION_AUTOEXEC,
        "LIBRARY QUERY L12 EXEC PASS",
        15_000_000_000,
        args.timeout,
    )
    return 0 if structural_ok and execution_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
