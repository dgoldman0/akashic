"""Configured HTTPS syndication: authorization, spans, media and leases.

Runs the streams-syndication-http-contracts profile, the deterministic
contract local_testing/streams-syndication-http.f, which only the harness's
command line ran before.  It covers the default factory's open policy, the
reviewed-policy constructor, span and media admission, and the bind and
start refusals.
"""

from __future__ import annotations

import sys
from pathlib import Path

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from contract_script import run_profile_smoke  # noqa: E402


def test_contracts(tmp_path: Path, monkeypatch) -> None:
    run_profile_smoke("streams-syndication-http-contracts",
                      tmp_path, monkeypatch)
