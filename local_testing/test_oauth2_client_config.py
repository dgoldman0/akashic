#!/usr/bin/env python3
"""Static and bounded linked qualification for OAuth client configuration."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-client-config-contracts"
IMAGE = Path("/tmp/akashic-oauth2-client-config-contracts.img")
SOURCE = ROOT / "akashic" / "security" / "oauth2" / "client-config.f"
DOC = ROOT / "docs" / "security" / "oauth2-client-config.md"
FIXTURE = LOCAL_TESTING / "oauth2-clientcfg-test.f"
MAX_STEPS = 250_000_000

AUTOEXEC = r"""\ autoexec.f - immutable OAuth client configuration
ENTER-USERLAND
." OAUTH2 CLIENT CONFIG LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/client-config.f
." OAUTH2 CLIENT CONFIG SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-clientcfg-test.f
." OAUTH2 CLIENT CONFIG FIXTURE READY" CR TX-FLUSH
_O2CCT-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    lowered = source.lower()

    assert "PROVIDED akashic-oauth2-client-config" in source
    assert re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source) == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "the generic client configuration must own no mutable module state"
    for forbidden in (
        "atproto/",
        "streams/",
        "xrpc",
        "http-target",
        "json",
        "private-key",
        "credential-vault",
    ):
        assert forbidden not in lowered
    assert not re.search(r"(?i)\b(?:v2|compat(?:ibility)?)\b", source)

    for word in (
        "OAUTH2-CLIENT-CONFIG-INPUT-SIZE",
        "OAUTH2-CLIENT-CONFIG-SIZE",
        "OAUTH2-CLIENT-CONFIG-INPUT-CLEAR",
        "OAUTH2-CLIENT-CONFIG-INIT",
        "OAUTH2-CLIENT-CONFIG-WIPE",
        "OAUTH2-CLIENT-CONFIG-VALID?",
        "OAUTH2-CLIENT-CONFIG-BINDING@",
        "OAUTH2-CLIENT-CONFIG-CLIENT-ID@",
        "OAUTH2-CLIENT-CONFIG-REDIRECT-URI@",
        "OAUTH2-CLIENT-CONFIG-SCOPE@",
        "OAUTH2-CLIENT-CONFIG-AUTH-METHOD@",
        "OAUTH2-CLIENT-CONFIG-AUTH-ALGORITHM@",
        "OAUTH2-CLIENT-CONFIG-APPLICATION-TYPE@",
        "OAUTH2-CLIENT-CONFIG-REFRESH?",
        "OAUTH2-CLIENT-CONFIG-DPOP-BOUND?",
        "OAUTH2-CLIENT-CONFIG-WITH",
        "OAUTH2-CLIENT-VIEW-CLIENT-ID@",
        "OAUTH2-CLIENT-VIEW-REDIRECT-URI@",
        "OAUTH2-CLIENT-VIEW-SCOPE@",
        "OAUTH2-CLIENT-VIEW-AUTH-METHOD@",
        "OAUTH2-CLIENT-VIEW-AUTH-ALGORITHM@",
        "OAUTH2-CLIENT-VIEW-FLAGS@",
    ):
        assert word in source

    assert re.search(
        r"(?m)^104 CONSTANT OAUTH2-CLIENT-CONFIG-INPUT-SIZE$", source
    )
    assert (
        "CONSTANT OAUTH2-CLIENT-CONFIG-SIZE" in source
        and "OAUTH2-CLIENT-CONFIG-SIZE 11072 <>" in source
    )
    assert "OAUTH2-CLIENT-CONFIG-BINDING-CAPACITY" in source
    assert "_O2CC-FLAGS-KNOWN INVERT AND 0=" in source
    assert "_O2CC-CANONICAL-ARENA?" in source

    init_status = _word_body(source, "_O2CC-INIT-STATUS")
    assert init_status.index("_O2CC-INPUT-STATUS") < init_status.index(
        "_O2CC-INPUT-ALIASES-CONFIG?"
    )
    assert init_status.index("_O2CC-INPUT-ALIASES-CONFIG?") < (
        init_status.index("_O2CC-ZERO?")
    )
    assert init_status.index("_O2CC-ZERO?") < init_status.index(
        "_O2CC-INPUT-CONTENT-STATUS"
    )
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        init_status,
    )
    publish = _word_body(source, "_O2CC-PUBLISH")
    assert publish.index("OAUTH2-CLIENT-CONFIG-SIZE 0 FILL") < (
        publish.index("_O2CC-COPY-REQUIRED")
    )
    assert publish.rindex("_O2CC-MAGIC-VALUE") > publish.rindex(
        "OAUTH2-CLIENT-CONFIG-I.FLAGS"
    )

    for accessor in (
        "OAUTH2-CLIENT-CONFIG-BINDING@",
        "OAUTH2-CLIENT-CONFIG-CLIENT-ID@",
        "OAUTH2-CLIENT-CONFIG-REDIRECT-URI@",
        "OAUTH2-CLIENT-CONFIG-SCOPE@",
        "OAUTH2-CLIENT-CONFIG-AUTH-METHOD@",
        "OAUTH2-CLIENT-CONFIG-AUTH-ALGORITHM@",
        "OAUTH2-CLIENT-CONFIG-FLAGS@",
    ):
        assert "_O2CC-OBJECT-STATUS" in _word_body(source, accessor)
    with_body = _word_body(source, "OAUTH2-CLIENT-CONFIG-WITH")
    assert "1 PICK 0=" in with_body
    assert "_O2CC-OBJECT-STATUS" in with_body
    assert "_O2CC-CALLBACK-SAFE" in with_body
    assert "CATCH" in _word_body(source, "_O2CC-CALLBACK-SAFE")

    for marker in (
        "_o2cct-test-public-copy",
        "_o2cct-test-private-and-scope",
        "_o2cct-test-syntax",
        "_o2cct-test-state-alias-and-corruption",
        "_o2cct-test-validated-view",
        "OAUTH2-CLIENT-CONFIG-S-ALIAS",
        "OAUTH2-CLIENT-CONFIG-S-CAPACITY",
        "OAUTH2-CLIENT-CONFIG-S-CALLBACK",
        "_O2CC.CLIENT-ID-U @ + C!",
    ):
        assert marker in fixture

    for marker in (
        "provider-neutral",
        "opaque binding",
        "exact selected redirect URI",
        "Private keys",
        "AT Protocol",
        "callback-scoped view",
    ):
        assert marker in doc

    for path, forth_source in ((SOURCE, source), (FIXTURE, fixture)):
        for line_number, line in enumerate(
            forth_source.splitlines(), start=1
        ):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source, fixture, and documentation contracts only",
    )
    parser.add_argument("--timeout", type=float, default=150.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("OAUTH2 CLIENT CONFIG STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/client-config.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 CLIENT CONFIG PASS",),
        stable_markers=("OAUTH2 CLIENT CONFIG PASS",),
        failure_markers=(
            "OAUTH2 CLIENT CONFIG FAIL",
            "OAUTH2 CLIENT CONFIG ASSERT",
            "OAUTH2 CLIENT CONFIG STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-clientcfg-test.f",
                FIXTURE.read_bytes(),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=42,
        max_steps=MAX_STEPS,
        timeout=args.timeout,
        ext_mem_mib=64,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
