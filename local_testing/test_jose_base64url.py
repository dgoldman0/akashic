#!/usr/bin/env python3
"""Focused linked qualification for strict caller-owned JOSE Base64url."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "jose-base64url-contracts"
IMAGE = Path("/tmp/akashic-jose-base64url-contracts.img")
CONTRACT = LOCAL_TESTING / "jose-base64url-test.f"
SOURCE = LOCAL_TESTING.parent / "akashic" / "security" / "jose" / "base64url.f"

AUTOEXEC = r"""\ autoexec.f - strict caller-owned JOSE Base64url contracts
ENTER-USERLAND
REQUIRE security/jose/base64url.f
REQUIRE local_testing/jose-base64url-test.f
_JBUT-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t(])(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    lowered = source.lower()

    assert not re.search(
        r"(?mi)^[ \t]*(?:create|variable|value|defer)\b", source
    ), "the codec must not own mutable module storage or lookup buffers"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
    ], "the generic JOSE codec must depend only on neutral caller-span utilities"

    for forbidden in (
        "atproto",
        "streams",
        "oauth",
        "../../net/base64.f",
        "b64-err",
        "_be-src",
        "_bd-src",
    ):
        assert forbidden not in lowered

    for word in (
        "JOSE-B64URL-S-OK",
        "JOSE-B64URL-S-INVALID",
        "JOSE-B64URL-S-CAPACITY",
        "JOSE-B64URL-S-ALIAS",
        "JOSE-B64URL-S-RANGE",
        "JOSE-B64URL-S-PROTECTED",
        "JOSE-B64URL-S-PLATFORM",
        "JOSE-B64URL-ENCODED-LENGTH",
        "JOSE-B64URL-DECODED-LENGTH",
        "JOSE-B64URL-ENCODE",
        "JOSE-B64URL-DECODE",
    ):
        assert word in source

    mapper = _word_body(source, "_JBU-CALLER>STATUS")
    for generic, public in (
        ("CALLER-SPAN-S-OK", "JOSE-B64URL-S-OK"),
        ("CALLER-SPAN-S-RANGE", "JOSE-B64URL-S-RANGE"),
        ("CALLER-SPAN-S-PROTECTED", "JOSE-B64URL-S-PROTECTED"),
        ("CALLER-SPAN-S-PLATFORM", "JOSE-B64URL-S-PLATFORM"),
    ):
        assert generic in mapper
        assert public in mapper
    assert mapper.count("JOSE-B64URL-S-PLATFORM") >= 2, (
        "undocumented caller-span results must remain platform failures"
    )

    span = _word_body(source, "_JBU-CALLER-SPAN-STATUS")
    assert "CALLER-SPAN-STATUS" in span
    assert "_JBU-CALLER>STATUS" in span

    decoded_length = _word_body(source, "JOSE-B64URL-DECODED-LENGTH")
    assert "_JBU-CALLER-SPAN-STATUS" in decoded_length
    assert "_JBU-DECODED-LENGTH-ADMITTED" in decoded_length

    for preflight in (
        "_JBU-ENCODE-PREFLIGHT",
        "_JBU-DECODE-PREFLIGHT",
    ):
        body = _word_body(source, preflight)
        assert not re.search(
            r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)(?![A-Za-z0-9_-])",
            body,
        ), f"{preflight} must not mutate caller storage"
        assert body.count("_JBU-CALLER-SPAN-STATUS") == 2, (
            f"{preflight} must qualify source and full destination capacity"
        )
        assert "MSPAN-OVERLAP?" in body
        assert "JOSE-B64URL-S-CAPACITY" in body
        assert "JOSE-B64URL-S-ALIAS" in body

    encode = _word_body(source, "JOSE-B64URL-ENCODE")
    decode = _word_body(source, "JOSE-B64URL-DECODE")
    assert encode.index("_JBU-ENCODE-PREFLIGHT") < encode.index("_JBU-ENCODE-RUN")
    assert decode.index("_JBU-DECODE-PREFLIGHT") < decode.index("_JBU-DECODE-RUN")

    canonical = _word_body(source, "_JBU-CANONICAL?")
    assert "_JBU-DECODE-CHAR" in canonical
    assert "4 MOD 1 =" in canonical
    assert "15 AND 0=" in canonical
    assert "3 AND 0=" in canonical

    assert "CATCH" not in source, (
        "admitted read/write faults and ambiguous partial publication must propagate"
    )
    assert "_JBU-SPAN?" not in source, (
        "all caller geometry must flow through the mapped caller-span boundary"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/jose/base64url.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("JOSE BASE64URL PASS",),
        stable_markers=("JOSE BASE64URL PASS",),
        failure_markers=(
            "JOSE BASE64URL FAIL",
            "JOSE BASE64URL ASSERT",
            "JOSE BASE64URL STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/jose-base64url-test.f", CONTRACT.read_bytes()),
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
