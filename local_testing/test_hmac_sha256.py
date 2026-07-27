#!/usr/bin/env python3
"""Focused linked qualification for generic caller-owned HMAC-SHA-256."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "hmac-sha256-contracts"
IMAGE = Path("/tmp/akashic-hmac-sha256-contracts.img")
CONTRACT = LOCAL_TESTING / "hmac-sha256-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "math" / "hmac-sha256.f"

AUTOEXEC = r"""\ autoexec.f - generic caller-owned HMAC-SHA-256 contracts
ENTER-USERLAND
REQUIRE math/hmac-sha256.f
REQUIRE local_testing/hmac-sha256-test.f
_H256T-RUN
"""


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "HMAC-SHA-256 must not own mutable module storage"
    assert "REQUIRE sha256.f" in source
    assert "REQUIRE ../utils/memory-span.f" in source
    assert "SHA256-HASH-2" in source
    for forbidden in ("atproto/", "streams/", "oauth2/"):
        assert forbidden not in source.lower()
    for word in (
        "HMAC-SHA256-DIGEST-SIZE",
        "HMAC-SHA256-WORKSPACE-SIZE",
        "HMAC-SHA256-STATUS-VALID?",
        "HMAC-SHA256-WORKSPACE-CLEAR",
        "HMAC-SHA256",
    ):
        assert word in source
    admitted = source[
        source.index(": _H256-ADMITTED") :
        source.index(": _H256-PUBLISH")
    ]
    publish = source[
        source.index(": _H256-PUBLISH") :
        source.index(": _H256-COMPUTE-CALL")
    ]
    compute_call = source[
        source.index(": _H256-COMPUTE-CALL") :
        source.index(": _H256-CLEAR-RETURN")
    ]
    clear_return = source[
        source.index(": _H256-CLEAR-RETURN") :
        source.index(": _H256-PUBLISH-CLEAR")
    ]
    publish_clear_start = source.index(": _H256-PUBLISH-CLEAR")
    public_start = source.index(": HMAC-SHA256\n", publish_clear_start)
    publish_clear = source[publish_clear_start:public_start]
    public = source[
        public_start :
        source.index("\\ Compile-time layout checks")
    ]
    normalize = source[
        source.index(": _H256-NORMALIZE-KEY") :
        source.index(": _H256-RUN")
    ]
    run = source[
        source.index(": _H256-RUN") :
        source.index(": _H256-BIND")
    ]
    assert "SHA256-HASH" in normalize
    assert "HMAC-SHA256-S-CRYPTO" in normalize
    assert run.count("SHA256-HASH-2") == 2
    assert run.count("HMAC-SHA256-S-CRYPTO") >= 2
    assert admitted.index("_H256-BIND") < admitted.index("_H256-RUN")
    assert "MOVE" not in admitted
    assert "CATCH" not in admitted
    assert "HMAC-SHA256-DIGEST-SIZE MOVE" in publish
    assert "1 PICK >R" in compute_call
    assert "CATCH" in compute_call
    assert "_H256-DROP6" in compute_call
    assert "HMAC-SHA256-S-CRYPTO" in compute_call
    assert "HMAC-SHA256-WORKSPACE-SIZE 0 FILL" in clear_return
    assert "CATCH" not in clear_return
    assert "HMAC-SHA256-S-CRYPTO" not in clear_return
    assert "CATCH" in publish_clear
    assert publish_clear.count(
        "HMAC-SHA256-WORKSPACE-SIZE 0 FILL"
    ) == 2
    assert publish_clear.index("CATCH") < publish_clear.index(
        "HMAC-SHA256-WORKSPACE-SIZE 0 FILL"
    ) < publish_clear.index("R> THROW")
    assert "R> THROW" in publish_clear
    assert "HMAC-SHA256-S-CRYPTO" not in publish_clear
    assert public.index("_H256-COMPUTE-CALL") < public.index(
        "_H256-PUBLISH-CLEAR"
    )
    assert "_H256-CLEAR-RETURN" in public
    assert "_H256-CALL" not in source
    assert source.count("HMAC-SHA256-WORKSPACE-SIZE 0 FILL") >= 3


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=600.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/hmac-sha256.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("HMAC SHA256 PASS",),
        stable_markers=("HMAC SHA256 PASS",),
        failure_markers=(
            "HMAC SHA256 FAIL",
            "HMAC SHA256 ASSERT",
            "HMAC SHA256 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/hmac-sha256-test.f", CONTRACT.read_bytes()),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=800_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
