#!/usr/bin/env python3
"""Focused linked qualification for strict caller-owned JOSE JSON objects."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "jose-json-object-contracts"
IMAGE = Path("/tmp/akashic-jose-json-object-contracts.img")
CONTRACT = LOCAL_TESTING / "jose-json-object-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "jose"
    / "json-object.f"
)

AUTOEXEC = r"""\ autoexec.f - strict caller-owned JOSE JSON object contracts
ENTER-USERLAND
REQUIRE security/jose/json-object.f
REQUIRE local_testing/jose-json-object-test.f
_JJOT-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    lowered = source.lower()

    assert not re.search(
        r"(?mi)^[ \t]*(?:create|variable|value|defer)\b", source
    ), "the parser must not own mutable module scratch or dispatch slots"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
    ], "strict JSON mechanics require overlap checks and caller qualification"

    for forbidden in (
        "atproto",
        "streams",
        "oauth",
        "session",
        "token-set",
        "xrpc",
        "net/",
        "persistence/",
    ):
        assert forbidden not in lowered

    for word in (
        "JOSE-JSON-S-OK",
        "JOSE-JSON-S-INVALID",
        "JOSE-JSON-S-SYNTAX",
        "JOSE-JSON-S-UTF8",
        "JOSE-JSON-S-CAPACITY",
        "JOSE-JSON-S-ALIAS",
        "JOSE-JSON-S-DEPTH",
        "JOSE-JSON-S-MEMBERS",
        "JOSE-JSON-S-STRING",
        "JOSE-JSON-S-DUPLICATE",
        "JOSE-JSON-S-INTERNAL",
        "JOSE-JSON-MAX-DOCUMENT-BYTES",
        "JOSE-JSON-MAX-DEPTH",
        "JOSE-JSON-MAX-MEMBERS",
        "JOSE-JSON-MAX-STRING-BYTES",
        "JOSE-JSON-OBJECT-WORKSPACE-SIZE",
        "JOSE-JSON-OBJECT-BYTES",
        "JOSE-JSON-OBJECT-PARSE",
        "JOSE-JSON-OBJECT-VALID?",
        "JOSE-JSON-OBJECT-MEMBER@",
        "JOSE-JSON-STRING-MEASURE",
        "JOSE-JSON-STRING-DECODE",
    ):
        assert word in source

    descriptor_section = source.split(
        "\\ =====================================================================\n"
        "\\  Caller workspace layout",
        1,
    )[0]
    assert "_JJD-SOURCE-A" not in descriptor_section
    assert "_JJD-NAMES-A" not in descriptor_section
    assert "_JJD-WORKSPACE" not in descriptor_section
    assert "_JJE-NAME-OFFSET" in descriptor_section
    assert "_JJE-VALUE-OFFSET" in descriptor_section

    value = _word_body(source, "_JJO-VALUE")
    assert "RECURSE" in value
    assert "_JJO-NESTED-KEY" in value
    assert "_JJO-VALUE-STRING" in value
    assert "JOSE-JSON-S-SYNTAX" in value

    value_string = _word_body(source, "_JJO-VALUE-STRING")
    assert "_JJW.EMIT-USED" in value_string
    assert "_JJW.EMIT-MODE" in value_string
    assert "_JJO-STRING" in value_string

    string = _word_body(source, "_JJO-STRING")
    escape = _word_body(source, "_JJO-ESCAPE")
    raw_utf8 = _word_body(source, "_JJO-RAW-UTF8")
    assert "_JJO-RAW-UTF8" in string
    assert "_JJO-HEX4" in escape
    assert "0xD800" in escape and "0xDBFF" in escape
    assert "0xDC00" in escape and "0xDFFF" in escape
    for boundary in ("0xC2", "0xE0", "0xED", "0xF0", "0xF4"):
        assert boundary in raw_utf8

    top = _word_body(source, "_JJO-TOP-OBJECT")
    assert "_JJO-TOP-DUPLICATE?" in top
    assert "_JJO-VALUE" in top
    assert "_JJO-LEFT" in top

    mapper = _word_body(source, "_JJO-CALLER-SPAN>STATUS")
    for word in (
        "CALLER-SPAN-STATUS",
        "CALLER-SPAN-S-OK",
        "CALLER-SPAN-S-RANGE",
        "CALLER-SPAN-S-PROTECTED",
        "CALLER-SPAN-S-PLATFORM",
        "JOSE-JSON-S-INVALID",
        "JOSE-JSON-S-ALIAS",
        "JOSE-JSON-S-INTERNAL",
    ):
        assert word in mapper
    assert "_JJO-SPAN?" not in source
    assert "MSPAN-NONWRAPPING?" not in source

    valid = _word_body(source, "JOSE-JSON-OBJECT-VALID?")
    assert valid.count("_JJO-CALLER-SPAN>STATUS") >= 2
    assert (
        "_JJO-CALLER-SPAN>STATUS"
        in _word_body(source, "JOSE-JSON-OBJECT-WORKSPACE-CLEAR")
    )
    assert (
        "_JJO-CALLER-SPAN>STATUS"
        in _word_body(source, "JOSE-JSON-STRING-WORKSPACE-CLEAR")
    )

    parse_stage = _word_body(source, "_JJO-PARSE-STAGE")
    assert parse_stage.index("_JJO-OUTPUT-ALIASED?") < parse_stage.index(
        "_JJO-TOP-OBJECT"
    )
    assert "_JJO-PUBLISH" not in parse_stage

    parse = _word_body(source, "JOSE-JSON-OBJECT-PARSE")
    assert parse.count("_JJO-CALLER-SPAN>STATUS") >= 4
    assert parse.rindex("_JJO-CALLER-SPAN>STATUS") < parse.index(
        "_JJO-PARSE-ADMITTED"
    )
    assert parse.count("MSPAN-OVERLAP?") >= 6
    assert "_JJO-PARSE-ADMITTED _JJO-PARSE-CALL" in parse

    parse_call = _word_body(source, "_JJO-PARSE-CALL")
    assert parse_call.index("CATCH") < parse_call.index(
        "_JJO-PARSE-THROW-CLEAN"
    )
    assert parse_call.index("_JJO-PARSE-THROW-CLEAN") < parse_call.index(
        "_JJO-PUBLISH-CALL"
    )
    assert "JOSE-JSON-S-INTERNAL" in parse_call

    finally_call = _word_body(source, "_JJO-CALL-FINALLY")
    assert "CATCH" in finally_call
    assert finally_call.count("EXECUTE") >= 2
    assert "THROW" in finally_call

    publish = _word_body(source, "_JJO-PUBLISH")
    assert "_JJO-STAGED-NAMES" in publish
    assert "_JJO-ENTRY-STAGE-OFF" in publish
    assert publish.index("_JJD.MAGIC !") < publish.index("0 FILL")
    assert publish.rindex("_JJO-DESCRIPTOR-MAGIC") > publish.index(
        "_JJO-ENTRY-STAGE-OFF"
    )

    throw_clean = _word_body(source, "_JJO-PARSE-THROW-CLEAN")
    assert "_JJO-CLEAR-DESCRIPTOR" in throw_clean
    assert "_JJO-CLEAR-NAMES" in throw_clean
    assert "_JJO-OBJECT-WORKSPACE-ZERO" in throw_clean

    measure = _word_body(source, "JOSE-JSON-STRING-MEASURE")
    assert measure.count("_JJO-CALLER-SPAN>STATUS") >= 2
    assert "_JJO-CALL-FINALLY" in measure
    decode = _word_body(source, "JOSE-JSON-STRING-DECODE")
    assert decode.count("_JJO-CALLER-SPAN>STATUS") >= 3
    assert decode.count("MSPAN-OVERLAP?") >= 3
    assert "_JJO-CALL-FINALLY" in decode
    decode_run = _word_body(source, "_JJO-STRING-DECODE-RUN")
    assert "_JJO-LEFT" in decode_run
    assert "JOSE-JSON-S-SYNTAX" in decode_run

    fixture = CONTRACT.read_text(encoding="utf-8")
    assert "_jjot-test-object-string-bound" in fixture
    assert "_jjot-test-throw-cleanup" in fixture
    assert "_jjot-test-mapped-spans" in fixture
    assert "_jjot-test-publication-and-cleanup-throws" in fixture
    assert "JOSE-JSON-MAX-STRING-BYTES 1+" in fixture
    assert "_JJO-PARSE-CALL" in _word_body(
        fixture, "_jjot-test-throw-cleanup"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_source_contracts()
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/jose/json-object.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("JOSE JSON OBJECT PASS",),
        stable_markers=("JOSE JSON OBJECT PASS",),
        failure_markers=(
            "JOSE JSON OBJECT FAIL",
            "JOSE JSON OBJECT ASSERT",
            "JOSE JSON OBJECT STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "(not found)",
        ),
        initial_files=(
            ("local_testing/jose-json-object-test.f", CONTRACT.read_bytes()),
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
        rows=44,
        max_steps=900_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
