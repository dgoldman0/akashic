"""Recorded feeds through Streams' decoder and its manual refresh.

Runs two deterministic contracts that only the harness's command line ran
before, over the recorded feeds in fixtures/syndication/:

- streams-syndec-contracts decodes the JSON Feed, RSS and Atom recordings
  and rejects the malformed ones without a partial commit.
- streams-manual-refresh-contracts refreshes a source from the Streams
  applet inside Desk, with the recorded JSON Feed pumped through Desk's
  external-I/O service, and checks the refusals, the durable accept, the
  applet after a relaunch and recovery.

With test_streams_syndication_http.py, which admits a source through the
configured provider's open policy, and the captured-chain checks of
test_web_roots.py, these prove the fetch path offline everywhere but the
network itself.  The refresh owner's own contract,
streams-refresh-owner-contracts, is not here yet: it prints nothing within
its 120-second limit, on an image whose modules are the same as main's.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

from contract_script import run_profile_smoke  # noqa: E402


@pytest.mark.parametrize("profile", [
    "streams-syndec-contracts",
    "streams-manual-refresh-contracts",
])
def test_contracts(profile: str, tmp_path: Path, monkeypatch) -> None:
    run_profile_smoke(profile, tmp_path, monkeypatch)
