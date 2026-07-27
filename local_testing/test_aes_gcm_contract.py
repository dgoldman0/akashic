#!/usr/bin/env python3
"""Focused native qualification for caller-owned AES-128/256-GCM."""

from __future__ import annotations

import argparse
import hashlib
import importlib
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "aes-gcm-contracts"
IMAGE = Path("/tmp/akashic-aes-gcm-contracts.img")
CONTRACT = LOCAL_TESTING / "aes-gcm-contract-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "math" / "aes.f"
NATIVE = LOCAL_TESTING.parent.parent / "megapad" / "accel" / "mp64_crypto.h"
NATIVE_FINGERPRINT_PREFIX = b"mp64-aes-gcm-native-sha256:"

AUTOEXEC = r"""\ autoexec.f - caller-owned native AES-GCM contracts
ENTER-USERLAND
REQUIRE math/aes.f
REQUIRE local_testing/aes-gcm-contract-test.f
_AGCT-RUN
"""


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    native = NATIVE.read_text(encoding="utf-8")

    assert "GUARD _aes-gcm-guard" in source
    assert "[DEFINED] GUARDED" not in source
    assert not re.search(r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER)\b", source)
    assert not re.search(r"(?mi)^[ \t]*CREATE\b", source)
    for old_word in (
        "AES-GCM-BEGIN",
        "AES-GCM-FEED-AAD",
        "AES-GCM-FEED-DATA",
        "AES-GCM-FINISH",
        "AES-GCM-TAG@",
        "AES-GCM-TAG-EQ?",
        "AES-GCM-USE-128",
        "AES-GCM-USE-256",
        "AES-GCM-ENCRYPT",
        "AES-GCM-DECRYPT",
    ):
        assert not re.search(rf"(?m)^:\s+{re.escape(old_word)}\b", source)

    for word in (
        "AES-GCM-DESCRIPTOR-SIZE",
        "AES-GCM-WORKSPACE-SIZE",
        "AES-GCM-DESCRIPTOR-VALID?",
        "AES-GCM-SEAL",
        "AES-GCM-OPEN",
        "AES-GCM-S-AUTH",
    ):
        assert word in source
    for requirement in (
        "AES-GCM-LENGTH-MAX",
        "AES-GCM-HARDWARE-POLL-LIMIT",
        "_AGCM-POLL-FINAL",
        "_AGCM-BIND-SAFE",
        "_AGCM-RUN-SAFE",
        "_AGCM-BODY-SAFE",
        "_AGCM-CLEAR-ENGINE-SAFE",
        "_AGCM-WIPE-OUTPUT-SAFE",
        "_AGCM-PUBLISH-TAG-SAFE",
        "_AGCM-WIPE-WORKSPACE-SAFE",
        "_AGCM-PREPARE-OPEN-PUBLISH-SAFE",
        "_AGCM-CALL-SAFE",
        "_AGCM-OP-OPEN-AUTH",
        "_AGCM-OP-OPEN-PUBLISH",
        "CATCH",
        "MSPAN-OVERLAP?",
    ):
        assert requirement in source

    def word_body(name: str) -> str:
        match = re.search(
            rf"(?ms)^:\s+{re.escape(name)}\b.*?;\s*$",
            source,
        )
        assert match is not None, name
        return match.group(0)

    for safe_word in (
        "_AGCM-BIND-SAFE",
        "_AGCM-RUN-SAFE",
        "_AGCM-BODY-SAFE",
        "_AGCM-CLEAR-ENGINE-SAFE",
        "_AGCM-WIPE-OUTPUT-SAFE",
        "_AGCM-PUBLISH-TAG-SAFE",
        "_AGCM-WIPE-WORKSPACE-SAFE",
        "_AGCM-WIPE-DESCRIPTOR-OUTPUT-SAFE",
        "_AGCM-PREPARE-OPEN-PUBLISH-SAFE",
        "_AGCM-CALL-SAFE",
    ):
        assert "CATCH" in word_body(safe_word)

    feed_data = word_body("_AGCM-FEED-DATA")
    assert feed_data.index("_AGCM-OP-OPEN-AUTH <> IF") < feed_data.index(
        "AES-DOUT@"
    )
    body = word_body("_AGCM-BODY")
    assert body.count("_AGCM-PASS-SAFE") == 3
    assert body.index("_AGCM-PASS-SAFE", body.index("\\ Authenticate")) < body.index(
        "_AGCM-PREPARE-OPEN-PUBLISH-SAFE"
    )
    admitted = source[source.index(": _AGCM-ADMITTED") :]
    assert admitted.index("_AGCM-BODY-SAFE") < admitted.index(
        "_AGCM-CLEAR-ENGINE-SAFE"
    )
    assert admitted.index("_AGCM-CLEAR-ENGINE-SAFE") < admitted.index(
        "_AGCM-PUBLISH-TAG-SAFE"
    )
    assert admitted.index("_AGCM-PUBLISH-TAG-SAFE") < admitted.index(
        "_AGCM-WIPE-OUTPUT-SAFE"
    )
    assert admitted.index("_AGCM-WIPE-OUTPUT-SAFE") < admitted.index(
        "_AGCM-WIPE-WORKSPACE-SAFE"
    )
    call_locked = word_body("_AGCM-CALL-LOCKED")
    assert call_locked.index("_AGCM-BIND-SAFE") < call_locked.index(
        "_AGCM-CLEAR-ENGINE-SAFE"
    )
    assert call_locked.index("_AGCM-CLEAR-ENGINE-SAFE") < call_locked.index(
        "_AGCM-WIPE-DESCRIPTOR-OUTPUT-SAFE"
    )
    assert call_locked.index("_AGCM-WIPE-DESCRIPTOR-OUTPUT-SAFE") < (
        call_locked.index("_AGCM-WIPE-WORKSPACE-SAFE")
    )

    aes_start = native[native.index("struct CryptoAES") :]
    assert "status = 1;" in aes_start
    assert "if (aad_len == 0 && data_len == 0)" in aes_start
    assert "if (aad_processed == aad_len && data_len == 0)" in aes_start
    assert "idx != din_written" in aes_start
    assert "std::min<uint32_t>(remaining, 16)" in aes_start
    assert "difference |= computed_tag[i] ^ tag[i]" in aes_start
    assert "std::memcmp(computed_tag, tag, 16)" not in aes_start
    assert "aes_secure_clear(rkeys, sizeof(rkeys))" in aes_start
    assert "aes_secure_clear(&h, sizeof(h))" in aes_start
    assert "aes_secure_clear(&ghash_state, sizeof(ghash_state))" in aes_start
    assert "if (difference != 0)" in aes_start
    assert "aes_secure_clear(dout, sizeof(dout))" in aes_start
    assert "configuration_complete" in aes_start
    assert "latch_transaction_fault" in aes_start
    assert "key_written_mask == 0xFFFFFFFFu" in aes_start
    assert "#error \"Megapad native AES-GCM requires" in native
    assert "struct u128" not in native
    assert "MP64_AES_MODEL_SOURCE_SHA256" in native
    fixture = CONTRACT.read_text(encoding="utf-8")
    assert "_agct-test-native-configuration-masks" in fixture
    for primitive in (
        "AES-KEY!",
        "AES-IV!",
        "AES-AAD-LEN!",
        "AES-DATA-LEN!",
        "AES-CMD!",
        "AES-TAG@",
        "AES-DOUT@",
    ):
        assert primitive in fixture


def _assert_native_binary_fingerprint() -> None:
    accelerator = importlib.import_module("_mp64_accel")
    artifact = Path(accelerator.__file__).resolve()
    source_digest = hashlib.sha256(NATIVE.read_bytes()).hexdigest().encode("ascii")
    fingerprint = NATIVE_FINGERPRINT_PREFIX + source_digest
    if fingerprint not in artifact.read_bytes():
        raise RuntimeError(
            "stale _mp64_accel binary: rebuild the native accelerator before "
            "running AES-GCM qualification; linked binary does not match "
            f"{NATIVE.name} SHA-256 {source_digest.decode('ascii')} ({artifact})"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=600.0)
    args = parser.parse_args()

    _assert_source_contracts()
    _assert_native_binary_fingerprint()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("math/aes.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("AES-GCM PASS",),
        stable_markers=("AES-GCM PASS",),
        failure_markers=(
            "AES-GCM FAIL",
            "AES-GCM ASSERT",
            "AES-GCM STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/aes-gcm-contract-test.f", CONTRACT.read_bytes()),
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
