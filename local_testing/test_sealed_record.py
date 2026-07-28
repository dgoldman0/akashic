#!/usr/bin/env python3
"""Static and linked qualification for generic authenticated sealed records."""

from __future__ import annotations

import argparse
import hashlib
import hmac
import re
import sys
from pathlib import Path

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


SOURCE = LOCAL_TESTING.parent / "akashic" / "security" / "sealed-record.f"
BASE = LOCAL_TESTING / "sealed-rec-base.f"
SUITES = (
    (
        "positive",
        LOCAL_TESTING / "sealed-rec-pos.f",
        "_SRT-POSITIVE-RUN",
        "SEALED RECORD POSITIVE PASS",
    ),
    (
        "negative",
        LOCAL_TESTING / "sealed-rec-neg.f",
        "_SRT-NEGATIVE-RUN",
        "SEALED RECORD NEGATIVE PASS",
    ),
    (
        "boundary",
        LOCAL_TESTING / "sealed-rec-bound.f",
        "_SRT-BOUNDARY-RUN",
        "SEALED RECORD BOUNDARY PASS",
    ),
)

REFERENCE_SHA256 = (
    "895763a5dfd58652b4edb040277d4dbd39768fe66213ff3ab02b36251b690115"
)
KDF_INFO = b"Akashic sealed record AES-256-GCM v1"


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _reference_record(fixture: str) -> bytes:
    init_start = fixture.index(": _srt-init-vector")
    init_end = fixture.index(": _srt-init", init_start + 1)
    chunks = re.findall(r'S" ([0-9a-f]+)"', fixture[init_start:init_end])
    assert len(chunks) == 4
    record = bytes.fromhex("".join(chunks))
    assert len(record) == 208
    assert hashlib.sha256(record).hexdigest() == REFERENCE_SHA256
    return record


def _assert_reference_vector(fixture: str) -> None:
    record = _reference_record(fixture)
    root = bytes(range(0x00, 0x20))
    key_id = bytes(range(0x20, 0x40))
    record_id = bytes(range(0x40, 0x60))
    salt = bytes(range(0xA0, 0xC0))
    plaintext = bytes(range(0x00, 0x20))

    assert record[:8] == b"AKSSEAL1"
    assert int.from_bytes(record[8:16], "big") == 1
    assert int.from_bytes(record[16:24], "big") == 160
    assert int.from_bytes(record[24:32], "big") == len(record)
    assert int.from_bytes(record[32:40], "big") == len(plaintext)
    assert int.from_bytes(record[40:48], "big") == 0x0102030405060708
    assert int.from_bytes(record[48:56], "big") == 0x1112131415161718
    assert int.from_bytes(record[56:64], "big") == 0
    assert record[64:96] == key_id
    assert record[96:128] == record_id
    assert record[128:160] == salt

    prk = hmac.new(salt, root, hashlib.sha256).digest()
    key = hmac.new(prk, KDF_INFO + b"\x01", hashlib.sha256).digest()
    t2 = hmac.new(prk, key + KDF_INFO + b"\x02", hashlib.sha256).digest()
    assert prk.hex() == (
        "417e7502c38837c356dc6d3f1c84cfac"
        "0efea0e929628cb89ce52f74716620ad"
    )
    assert key.hex() == (
        "12839ff96b75c11a3b9b2d579d116cc2"
        "e0a0383ff45d45990728dfcfd5229b86"
    )
    assert t2[:12].hex() == "f92c4cf60589a1c00f192d48"
    assert AESGCM(key).decrypt(t2[:12], record[160:], record[:160]) == plaintext


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    base = BASE.read_text(encoding="utf-8")
    fixtures = {
        name: path.read_text(encoding="utf-8")
        for name, path, _entry, _marker in SUITES
    }
    all_fixtures = "\n".join((base, *fixtures.values()))

    provided = re.search(r"(?m)^PROVIDED[ \t]+(\S+)$", source)
    assert provided is not None
    assert provided.group(1) == "akashic-sealed-record"
    assert len(provided.group(1)) <= 23
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "sealed-record must not own mutable module state"

    requirements = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requirements == [
        "../math/aes.f",
        "../math/hmac-sha256.f",
        "../math/entropy.f",
        "../utils/memory-span.f",
        "../utils/caller-span.f",
    ]
    for forbidden in ("oauth2/", "atproto/", "streams/", "utils/fs/"):
        assert forbidden not in "\n".join(requirements).lower()
    for raw_hardware_word in (
        "AES-KEY!",
        "AES-IV!",
        "AES-CMD!",
        "AES-DIN!",
        "AES-DOUT@",
        "AES-TAG!",
        "AES-TAG@",
    ):
        assert raw_hardware_word not in source

    for word in (
        "SEALED-RECORD-DESCRIPTOR-SIZE",
        "SEALED-RECORD-WORKSPACE-SIZE",
        "SEALED-RECORD-SIZE",
        "SEALED-RECORD-DESCRIPTOR-CLEAR",
        "SEALED-RECORD-WORKSPACE-CLEAR",
        "SEALED-RECORD-SEAL",
        "SEALED-RECORD-OPEN",
        "SEALED-RECORD-S-BUSY",
        "SEALED-RECORD-S-CALLBACK",
        "SEALED-RECORD-S-AUTH",
        "SEALED-RECORD-S-PROTECTED",
        "SEALED-RECORD-S-PLATFORM",
    ):
        assert word in source

    assert re.search(
        r"(?m)^80 CONSTANT SEALED-RECORD-DESCRIPTOR-SIZE$", source
    )
    assert re.search(
        r"(?m)^[ \t]*CONSTANT SEALED-RECORD-WORKSPACE-SIZE$", source
    )
    assert re.search(
        r"(?m)^0x414B535345414C31 CONSTANT _SR-MAGIC", source
    )
    assert f'S" {KDF_INFO.decode()}"' in source
    assert "_SR-KDF-INFO-U 36 <> [IF]" in source
    assert "AES-GCM-SEAL" in source
    assert "AES-GCM-OPEN" in source
    assert source.count("HMAC-SHA256") >= 3
    assert "ENTROPY-FILL" in source

    resolver = _word_body(source, "_SR-RESOLVER-INVOKE")
    assert "DEPTH" in resolver
    assert "_SR-RESOLVER-CANARY" in resolver
    assert "1 PICK R@ <>" in resolver
    assert "_SR-E-RESOLVER-STACK THROW" in resolver
    preflight = _word_body(source, "_SR-COMMON-PREFLIGHT")
    assert "_SR-WORKSPACE-BUSY" in preflight
    assert "_SR-EXPECTED-IDS-ALIASED?" in preflight

    seal_publish = _word_body(source, "_SR-PUBLISH-SEAL")
    assert seal_publish.index("8 0 FILL") < seal_publish.index(
        "_SRW.TOTAL-U @ 8 - MOVE"
    )
    assert seal_publish.index("_SRW.TOTAL-U @ 8 - MOVE") < seal_publish.rindex(
        "8 MOVE"
    )
    open_publish = _word_body(source, "_SR-PUBLISH-OPEN")
    assert open_publish.index("_SRW.OUTPUT-CAP @ 0 FILL") < open_publish.index(
        "_SRW.DATA-U @ MOVE"
    )
    cleanup = _word_body(source, "_SR-RETHROW-AFTER-CLEANUPS")
    assert "_SR-CATCH-IOR" in cleanup
    assert "_SR-WIPE-WORKSPACE" in cleanup

    for text in (source, base, *fixtures.values()):
        assert not re.search(
            r"(?mi)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
            r"(?![A-Za-z0-9_-])",
            text,
        ), "sealed-record code must not use KDOS DO-loop return-stack state"
        for line_number, line in enumerate(text.splitlines(), start=1):
            code = line.split("\\", 1)[0]
            if "(" in code:
                assert ")" in code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their physical "
                    f"line: {line_number}"
                )

    for marker in (
        "_srt-test-reference-open",
        "_srt-test-seal-open",
        "_srt-test-auth-and-shape",
        "_srt-test-resolver-contracts",
        "_srt-test-rejections",
        "_srt-extra-result-resolver",
        "_srt-missing-result-resolver",
        "_srt-substituted-context-resolver",
        "_srt-recursive-resolver",
        "SEALED-RECORD-S-BUSY",
        "_srt-workspace-clean?",
    ):
        assert marker in all_fixtures
    for entry in (
        "_SRT-POSITIVE-RUN",
        "_SRT-NEGATIVE-RUN",
        "_SRT-BOUNDARY-RUN",
    ):
        assert entry in all_fixtures
    assert "_srt-vector _srt-record 208 MOVE" in fixtures["negative"]
    assert "_srt-vector _srt-record 208 MOVE" in fixtures["boundary"]
    _assert_reference_vector(base)


def _autoexec(fixture: Path, entry: str) -> str:
    return (
        "\\ autoexec.f - bounded generic sealed-record contracts\n"
        "ENTER-USERLAND\n"
        '." SEALED RECORD LOAD START" CR TX-FLUSH\n'
        "REQUIRE security/sealed-record.f\n"
        '." SEALED RECORD SOURCE READY" CR TX-FLUSH\n'
        "REQUIRE local_testing/sealed-rec-base.f\n"
        f"REQUIRE local_testing/{fixture.name}\n"
        '." SEALED RECORD FIXTURE READY" CR TX-FLUSH\n'
        f"{entry}\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source, fixture, and independent vector without a guest",
    )
    parser.add_argument(
        "--suite",
        choices=("all", *(name for name, _path, _entry, _marker in SUITES)),
        default="all",
        help="run all bounded guest suites or one named suite",
    )
    parser.add_argument("--timeout", type=float, default=300.0)
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("SEALED RECORD STATIC PASS")
        return 0

    selected = (
        SUITES
        if args.suite == "all"
        else tuple(suite for suite in SUITES if suite[0] == args.suite)
    )
    for name, fixture, entry, marker in selected:
        profile = f"sealed-record-{name}"
        image = Path(f"/tmp/akashic-sealed-record-{name}.img")
        harness.PROFILES[profile] = harness.Profile(
            roots=("security/sealed-record.f",),
            resources=(),
            autoexec=_autoexec(fixture, entry),
            ready_markers=(marker,),
            stable_markers=(marker,),
            failure_markers=(
                "SEALED RECORD FAIL",
                "SEALED RECORD ASSERT",
                "SEALED RECORD STACK",
                "DRIVER THROW",
                "dictionary full",
                "exception",
                "Module not found",
                "Path component not found",
                "? (not found)",
            ),
            initial_files=(
                ("local_testing/sealed-rec-base.f", BASE.read_bytes()),
                (f"local_testing/{fixture.name}", fixture.read_bytes()),
            ),
            linked=True,
            include_large_sample=False,
            total_sectors=4096,
        )
        image_path = harness.build_image(profile, image)
        ok = harness.smoke(
            profile,
            image_path,
            cols=120,
            rows=40,
            max_steps=250_000_000,
            timeout=args.timeout,
            ext_mem_mib=128,
        )
        if not ok:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
