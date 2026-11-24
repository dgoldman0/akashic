"""Run the machine TLS trust contracts kept as harness profiles.

The trust registry, its MPTA import, the AT Protocol public trust and the
Codex provider source are checked by profiles of akashic_tui.py that only
its command line ran, so the test selection tool never saw them fail.  Each
profile runs here as a test of its own, on the emulator, with the profile's
own step budget.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from contract_script import run_profile_smoke  # noqa: E402

PROFILES = (
    "tls-trust-registry",
    "tls-trust-mpta",
    "tls-trust-registry-error",
    "tls-trust-registry-throw",
    "tls-trust-registry-builder",
    "atproto-public-trust",
    "codex-source",
)


@pytest.mark.parametrize("profile", PROFILES)
def test_trust_contract(profile: str, tmp_path: Path, monkeypatch) -> None:
    run_profile_smoke(profile, tmp_path, monkeypatch)
