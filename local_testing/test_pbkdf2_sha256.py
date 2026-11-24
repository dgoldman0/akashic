#!/usr/bin/env python3
"""Focused linked qualification for resumable PBKDF2-HMAC-SHA-256.

The guest derives the RFC 7914 vectors and keys that exercise a hashed long
password, an empty password and salt, a partial last block, and single
iteration steps, then prints the device cycles it counted.  The Python side
recomputes every expected key with hashlib from the contract's own inputs,
so a wrong byte in the contract cannot pass as a wrong implementation.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "pbkdf2-sha256-contracts"
IMAGE = Path("/tmp/akashic-pbkdf2-sha256-contracts.img")
CONTRACT = LOCAL_TESTING / "pbkdf2-sha256-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "security" / "pbkdf2-sha256.f"
SHA256 = LOCAL_TESTING.parent / "akashic" / "math" / "sha256.f"

AUTOEXEC = r"""\ autoexec.f - resumable PBKDF2-HMAC-SHA-256 contracts
ENTER-USERLAND
REQUIRE security/pbkdf2-sha256.f
REQUIRE local_testing/pbkdf2-sha256-test.f
_PBKT-RUN
"""

# Contract array -> (password array, salt array, iterations, key length).
# A password or salt of None is empty.
VECTORS = {
    "_pbkt-exp-rfc1": ("_pbkt-passwd", "_pbkt-salt", 1, 64),
    "_pbkt-exp-rfc2": ("_pbkt-password", "_pbkt-nacl", 80000, 64),
    "_pbkt-exp-long": ("_pbkt-long", "_pbkt-salt", 2, 40),
    "_pbkt-exp-empty": (None, None, 3, 32),
    "_pbkt-exp-steps": ("_pbkt-step", "_pbkt-step-salt", 37, 33),
}

# RFC 7914 section 11, transcribed independently of hashlib.
RFC7914 = {
    "_pbkt-exp-rfc1": bytes.fromhex(
        "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc"
        "49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783"
    ),
    "_pbkt-exp-rfc2": bytes.fromhex(
        "4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56"
        "a1d425a1225833549adb841b51c9b3176a272bdebba1d078478f62b397f33c8d"
    ),
}

CYCLE_LINE = re.compile(r"^(PBKDF2 CYCLES [^=]+|SHA256-[A-Z0-9-]+ CYCLES X100)=(\d+)")


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _contract_arrays(text: str) -> dict[str, bytes]:
    arrays: dict[str, bytes] = {}
    for match in re.finditer(
        r"(?m)^CREATE (\S+)\n((?:[ \t]+(?:0x[0-9A-Fa-f]{2} C,[ \t]*)+\n)+)",
        text,
    ):
        arrays[match.group(1)] = bytes(
            int(value, 16)
            for value in re.findall(r"0x([0-9A-Fa-f]{2}) C,", match.group(2))
        )
    return arrays


def _assert_vectors() -> None:
    arrays = _contract_arrays(CONTRACT.read_text(encoding="utf-8"))
    for expected_name, (password, salt, iterations, length) in VECTORS.items():
        derived = hashlib.pbkdf2_hmac(
            "sha256",
            arrays[password] if password else b"",
            arrays[salt] if salt else b"",
            iterations,
            length,
        )
        assert arrays[expected_name] == derived, expected_name
    for name, value in RFC7914.items():
        assert arrays[name] == value, name


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    assert "REQUIRE ../math/sha256.f" in source
    assert "REQUIRE ../utils/memory-span.f" in source
    # The derivation keeps its state in the caller's workspace only.
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "PBKDF2 must not own mutable module storage"
    # A general library: it depends on SHA-256 and span checks only.
    assert re.findall(r"(?m)^REQUIRE (\S+)", source) == [
        "../math/sha256.f",
        "../utils/memory-span.f",
    ]
    for word in (
        "PBKDF2-SHA256-WORKSPACE-SIZE",
        "PBKDF2-SHA256-STATUS-VALID?",
        "PBKDF2-SHA256-BEGIN",
        "PBKDF2-SHA256-STEP",
        "PBKDF2-SHA256-FINISH",
        "PBKDF2-SHA256-ABANDON",
    ):
        assert re.search(rf"(?m)^: {re.escape(word)}(?=\s)", source), word
    # Iterations hash inside one held SHA-256 transaction per step; the key
    # blocks and first U values use the public, self-qualifying words.
    iterate = _word_body(source, "_PBK-ITERATE")
    assert iterate.count("SHA256-HELD-HASH") == 2
    assert iterate.count("+ 96") == 2
    assert "SHA256-HASH" not in iterate.replace("SHA256-HELD-HASH", "")
    assert "SHA256-WITH-TRANSACTION" in _word_body(source, "_PBK-RUN-HELD")
    first = _word_body(source, "_PBK-FIRST")
    assert "SHA256-HASH-3" in first and "SHA256-HASH\n" in first
    step = _word_body(source, "PBKDF2-SHA256-STEP")
    assert step.index("_PBK-LIVE?") < step.index("CATCH")
    assert step.count("_PBK-WIPE") == 2
    assert "THROW" in step
    begin = _word_body(source, "PBKDF2-SHA256-BEGIN")
    assert begin.index("_PBK-ADMIT") < begin.index("0 FILL")
    assert begin.count("_PBK-WIPE") == 2
    assert begin.rindex("_PBK-LIVE") > begin.rindex("_PBK-FIRST")
    finish = _word_body(source, "PBKDF2-SHA256-FINISH")
    assert finish.index("MSPAN-OVERLAP?") < finish.index("MOVE")
    assert finish.rstrip().endswith("_PBK-WIPE PBKDF2-SHA256-S-OK")
    live = _word_body(source, "_PBK-LIVE?")
    assert live.count("SHA256-CALLER-SPAN-STATUS") == 2
    # The held SHA-256 transaction exists in sha256.f and nowhere else.
    sha = SHA256.read_text(encoding="utf-8")
    assert re.search(r"(?m)^: SHA256-WITH-TRANSACTION\b", sha)
    assert re.search(r"(?m)^: SHA256-HELD-HASH(?=\s)", sha)


def _report_cycles() -> None:
    raw = harness.OUTPUT_ROOT / f"smoke-{PROFILE}.raw.txt"
    if not raw.exists():
        return
    for line in raw.read_text(encoding="utf-8").replace("\r", "").splitlines():
        match = CYCLE_LINE.match(line.strip())
        if match:
            cycles = int(match.group(2))
            print(
                f"  {match.group(1)}: {cycles:,} cycles, "
                f"{cycles / 100e6:.4f} s at 100 MHz"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=900.0)
    args = parser.parse_args()

    _assert_vectors()
    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/pbkdf2-sha256.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("PBKDF2 SHA256 PASS",),
        stable_markers=("PBKDF2 SHA256 PASS",),
        failure_markers=(
            "PBKDF2 SHA256 FAIL",
            "PBKDF2 SHA256 ASSERT",
            "PBKDF2 SHA256 STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/pbkdf2-sha256-test.f", CONTRACT.read_bytes()),
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
        max_steps=3_000_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    _report_cycles()
    return 0 if ok else 1


def test_contracts(tmp_path: Path, monkeypatch) -> None:
    """Run the contract script under pytest."""
    from contract_script import run_as_test

    run_as_test(sys.modules[__name__], tmp_path, monkeypatch)


if __name__ == "__main__":
    raise SystemExit(main())
