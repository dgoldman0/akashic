#!/usr/bin/env python3
"""Focused qualification for the caller-owned form body writer."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "net" / "form-urlencoded-writer.f"
DOC = ROOT / "docs" / "net" / "form-urlencoded-writer.md"
CONTRACT = LOCAL_TESTING / "fuew-test.f"
PROFILE = "form-urlencoded-writer-contracts"
IMAGE = Path("/tmp/akashic-form-urlencoded-writer-contracts.img")

AUTOEXEC = r"""\ autoexec.f - caller-owned form writer contracts
ENTER-USERLAND
REQUIRE net/form-urlencoded-writer.f
REQUIRE local_testing/fuew-test.f
_FUEWT-RUN
TX-FLUSH
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def test_form_urlencoded_writer_source_contract() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    lowered = source.lower()
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert "PROVIDED akashic-fue-writer" in source
    assert len(CONTRACT.name) <= 23
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    )
    assert re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    ) == [
        "form-urlencoded.f",
        "../utils/memory-span.f",
        "../utils/caller-span.f",
    ]
    for forbidden in (
        "atproto",
        "streams",
        "session",
        "xrpc",
        "oauth",
        "http-request",
        "http-buffered",
    ):
        assert forbidden not in lowered

    for word in (
        "FUEW-SIZE",
        "FUEW-STATE-BUILDING",
        "FUEW-STATE-SEALED",
        "FUEW-S-OK",
        "FUEW-S-INVALID",
        "FUEW-S-STATE",
        "FUEW-S-CAPACITY",
        "FUEW-S-ALIAS",
        "FUEW-S-RANGE",
        "FUEW-S-PROTECTED",
        "FUEW-S-PLATFORM",
        "FUEW-S-INTERNAL",
        "FUEW-STATUS-VALID?",
        "FUEW-VALID?",
        "FUEW-INIT",
        "FUEW-FIELD",
        "FUEW-SEAL",
        "FUEW-BODY@",
        "FUEW-STATE@",
        "FUEW-LENGTH@",
        "FUEW-FIELD-COUNT@",
        "FUEW-WIPE",
    ):
        assert word in source

    valid = _word_body(source, "FUEW-VALID?")
    assert "_FUEW-WRITER-STATUS" in valid
    assert "_FUEW-MAGIC-VALUE" in valid
    assert "_FUEW-SPAN-STATUS" in valid
    assert "MSPAN-OVERLAP?" in valid

    init = _word_body(source, "FUEW-INIT")
    assert init.index("_FUEW-WRITER-STATUS") < init.index("0 FILL")
    assert init.index("_FUEW-SPAN-STATUS") < init.index("0 FILL")
    assert init.index("MSPAN-OVERLAP?") < init.index("0 FILL")
    assert "FUEW-VALID? 0=" in init
    assert init.count("0 FILL") >= 3
    assert (
        init.index("_FUEW-MAGIC-VALUE R@ _FUEW.MAGIC !")
        > init.index("FUEW-STATE-BUILDING R@ FUEW.STATE !")
    )

    geometry = _word_body(source, "_FUEW-FIELD-GEOMETRY")
    assert geometry.count("_FUEW-SOURCE-ALIASES?") == 2
    assert geometry.count("_FUEW-MEASURE") == 2
    assert "_FUEW-FIELD-TOTAL" in geometry
    assert "FUEW.CAPACITY @" in geometry
    assert "FUEW.LENGTH @" in geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_.-])(?:C!|W!|!|\+!|MOVE|FILL)"
        r"(?![A-Za-z0-9_.-])",
        geometry,
    )

    commit = _word_body(source, "_FUEW-FIELD-COMMIT")
    assert commit.count("FORM-URLENCODED-ENCODE") == 2
    assert commit.count("_FUEW-ZERO-FIELD") >= 4
    assert commit.index("_FUEW-ZERO-FIELD") < commit.index(
        "FORM-URLENCODED-ENCODE"
    )
    assert commit.index("2DUP <>") < commit.index("FUEW.LENGTH +!")
    assert commit.index("FUEW.LENGTH +!") < commit.index(
        "FUEW.FIELD-COUNT +!"
    )
    mismatch = re.search(
        r"(?ms)2DUP[ \t]+<>[ \t]+IF"
        r"(?P<body>.*?)FUEW-S-INTERNAL[ \t]+EXIT",
        commit,
    )
    assert mismatch is not None
    mismatch_body = mismatch.group("body")
    assert "DROP >R" in mismatch_body
    assert "DUP R@ SWAP _FUEW-ZERO-FIELD" in mismatch_body
    assert "_FUEW-DROP5" in mismatch_body

    field = _word_body(source, "FUEW-FIELD")
    assert field.index("_FUEW-FIELD-GEOMETRY") < field.index(
        "_FUEW-FIELD-COMMIT"
    )

    seal = _word_body(source, "FUEW-SEAL")
    assert "FUEW-STATE-BUILDING <>" in seal
    assert "FUEW-STATE-SEALED" in seal

    body = _word_body(source, "FUEW-BODY@")
    assert "FUEW-STATE-SEALED <>" in body
    assert "FUEW.BODY @" in body
    assert "FUEW.LENGTH @" in body

    wipe = _word_body(source, "FUEW-WIPE")
    assert wipe.count("0 FILL") == 2
    assert wipe.index("FUEW.CAPACITY @ 0 FILL") < wipe.index(
        "FUEW-SIZE 0 FILL"
    )

    doc = DOC.read_text(encoding="utf-8")
    for phrase in (
        "caller-owned byte arena",
        "Ordinary `FIELD` failures are deliberately nonsticky",
        "complete attempted tail contribution is cleared",
        "complete advertised arena",
        "FUEW-STATE-BUILDING",
        "FUEW-STATE-SEALED",
        "zeroes the complete advertised arena",
        "duplicate names are not rejected",
        "Content-Type: application/x-www-form-urlencoded",
    ):
        assert phrase in doc

    assert "PROVIDED akashic-fuew-contracts" in fixture
    for test_word in (
        "_fuewt-test-vocabulary-and-shape",
        "_fuewt-test-empty-lifecycle",
        "_fuewt-test-canonical-body",
        "_fuewt-test-transactional-capacity",
        "_fuewt-test-alias-and-adjacency",
        "_fuewt-test-invalid-sources",
        "_fuewt-test-internal-mismatch-rollback",
        "_fuewt-test-reinitialize-and-corruption",
    ):
        assert test_word in fixture
    assert "6 _FUEW-FIELD-COMMIT" in fixture
    assert "FUEW-S-INTERNAL _fuewt-status" in fixture
    assert "_fuewt-body 3 + 6 _fuewt-zero?" in fixture
    assert not re.search(
        r"(?mi)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture
    ), "the fixture must use cursor walks rather than indexed loops"
    for path, forth_source in ((SOURCE, source), (CONTRACT, fixture)):
        for line_number, line in enumerate(
            forth_source.splitlines(), start=1
        ):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )


def _linked_contracts() -> bool:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("net/form-urlencoded-writer.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("FORM WRITER PASS",),
        stable_markers=("FORM WRITER PASS",),
        failure_markers=(
            "FORM WRITER FAIL",
            "FORM WRITER ASSERT",
            "FORM WRITER STATUS",
            "FORM WRITER STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            (
                "local_testing/fuew-test.f",
                CONTRACT.read_bytes(),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=2048,
    )
    image = harness.build_image(PROFILE, IMAGE)
    return harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=40,
        max_steps=250_000_000,
        timeout=120.0,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source contracts without building or running an image",
    )
    args = parser.parse_args()

    test_form_urlencoded_writer_source_contract()
    if args.static_only:
        print("FORM URLENCODED WRITER STATIC PASS")
        return 0
    return 0 if _linked_contracts() else 1


if __name__ == "__main__":
    raise SystemExit(main())
