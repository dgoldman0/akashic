#!/usr/bin/env python3
"""Qualify the caller-owned AT createRecord request/receipt codec."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "atproto" / "create-record-codec.f"
CONTRACT = LOCAL_TESTING / "crec-codec-test.f"

PROFILE = "atproto-create-record-codec"
IMAGE = Path("/tmp/akashic-atproto-create-record-codec.img")
PASS_MARKER = "CREATE RECORD CODEC PASS"
BOOT_MARKER = "CREATE RECORD CODEC USERLAND READY"
FIXTURE_MARKER = "CREATE RECORD CODEC FIXTURE READY"
BOOT_MAX_STEPS = 180_000_000
PHASE_MAX_STEPS = 120_000_000
EXT_MEM_SIZE = 64 << 20
NUM_CORES = 1

sys.path.insert(0, str(LOCAL_TESTING))
from forth_dependencies import dependency_order  # noqa: E402


MODULES = dependency_order(
    ROOT / "akashic",
    ("atproto/create-record-codec.f",),
)


def _module_marker(index: int) -> str:
    return f"CREATE RECORD CODEC MODULE {index:02d} READY"


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their "
                f"physical line: {path}:{line_number}"
            )


def test_create_record_codec_source_contract() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    requires = _requires(SOURCE)

    assert MODULES[-1] == "atproto/create-record-codec.f"
    assert len(MODULES) == len(set(MODULES))
    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 64 << 20
    assert PHASE_MAX_STEPS < 250_000_000

    assert requires == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../utils/buffer-writer.f",
        "../utils/json-writer.f",
        "../security/jose/json-object.f",
        "did.f",
        "nsid.f",
        "record-key.f",
        "aturi.f",
        "cid.f",
    ]
    assert "PROVIDED akashic-at-crec-codec" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "the reusable codec must not own module-global mutable state"
    assert (
        "JOSE-JSON-MAX-MEMBERS CONSTANT _ATCRC-MEMBER-CAPACITY"
        in source
    )
    assert (
        "JOSE-JSON-MAX-NAME-BYTES CONSTANT _ATCRC-NAMES-CAPACITY"
        in source
    )

    for word in (
        "AT-CREATE-RECORD-S-OK",
        "AT-CREATE-RECORD-S-INTERNAL",
        "AT-CREATE-RECORD-STATUS-VALID?",
        "AT-CREATE-RECORD-CODEC-WORKSPACE-SIZE",
        "AT-CREATE-RECORD-CODEC-WORKSPACE-CLEAR",
        "AT-CREATE-RECORD-BODY",
        "AT-CREATE-RECORD-RECEIPT",
    ):
        assert word in source

    for forbidden_require in (
        "create-record.f",
        "xrpc-exchange.f",
        "http.f",
        "desk",
        "agent",
        "schema",
        "cache",
        "vfs",
    ):
        assert not any(
            forbidden_require in required.lower()
            for required in requires
        )

    body_geometry = _word_body(source, "_ATCRC-BODY-GEOMETRY")
    assert "JOSE-JSON-MAX-DOCUMENT-BYTES" in body_geometry
    assert body_geometry.count("MSPAN-OVERLAP?") >= 9
    assert "_ATCRC-REQUIRED-SPAN-STATUS" in body_geometry

    body_op = _word_body(source, "_ATCRC-BODY-OP")
    for admission in (
        "DID-VALIDATE",
        "NSID-CHECK",
        "_ATCRC-CANONICAL-COLLECTION?",
        "AT-RKEY-VALIDATE",
        "_ATCRC-ADMIT-RECORD",
    ):
        assert admission in body_op

    record_type = _word_body(source, "_ATCRC-RECORD-TYPE")
    assert "NSID-LENGTH-MAX" in record_type
    assert "COMPARE 0=" in record_type
    assert "AT-CREATE-RECORD-S-TYPE" in record_type
    encode = _word_body(source, "_ATCRC-ENCODE-BODY")
    assert encode.count("_ATCRC-STRING") >= 7
    assert "_ATCRW.RECORD-A" in encode
    assert "_ATCRC-APPEND" in encode

    receipt_geometry = _word_body(
        source, "_ATCRC-RECEIPT-GEOMETRY"
    )
    assert "JOSE-JSON-MAX-DOCUMENT-BYTES" in receipt_geometry
    assert "ATURI-LENGTH-MAX" in receipt_geometry
    assert receipt_geometry.count("MSPAN-OVERLAP?") >= 2

    receipt_op = _word_body(source, "_ATCRC-RECEIPT-OP")
    assert "_ATCRC-RECORD-URI?" in receipt_op
    assert "_ATCRC-PARSE-OBJECT" in receipt_op
    receipt_uri = _word_body(source, "_ATCRC-RECEIPT-URI")
    assert "ATURI-VALIDATE" in receipt_uri
    assert "_ATCRW.EXPECTED-A" in receipt_uri
    assert "COMPARE 0=" in receipt_uri
    receipt_cid = _word_body(source, "_ATCRC-RECEIPT-CID")
    assert "AT-CID-TEXT-CHECK" in receipt_cid
    assert "AT-CID-CODEC-DAG-CBOR" in receipt_cid
    detach = _word_body(source, "_ATCRC-RECEIPT-DETACH")
    assert "_ATCRW.URI" in detach
    assert "_ATCRW.CID" in detach
    assert "_ATCRW-URI-OFF 0 FILL" in detach

    assert "PROVIDED at-create-record-codec-test" in fixture
    for test_word in (
        "_crct-test-body-exact",
        "_crct-test-body-capacity",
        "_crct-test-body-admission",
        "_crct-test-receipt-detachment",
        "_crct-test-receipt-admission",
        "_CRCT-RUN",
    ):
        assert test_word in fixture
    for evidence in (
        "u0024type",
        "u0075ri",
        "u0063id",
        "_crct-build-malformed-unknown-record",
        "_crct-build-malformed-unknown-receipt",
        "_crct-raw-cid",
        "_crct-work-span?",
        "_crct-result-uri-a @ _crct-work -",
        "AT-CREATE-RECORD-CODEC-WORKSPACE-CLEAR",
    ):
        assert evidence in fixture

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - staged createRecord codec qualification\n",
        "ENTER-USERLAND\n",
        f'." {BOOT_MARKER}" CR TX-FLUSH\n',
        "KEY DROP\n",
    ]
    for index, module in enumerate(MODULES, start=1):
        lines.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." CREATE RECORD CODEC LOAD STACK FAIL '
                    f'{index:02d}" CR TX-FLUSH THEN\n'
                ),
                f'." {_module_marker(index)}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    lines.extend(
        (
            "REQUIRE local_testing/crec-codec-test.f\n",
            (
                'DEPTH IF ." CREATE RECORD CODEC FIXTURE STACK FAIL" '
                "CR TX-FLUSH THEN\n"
            ),
            f'." {FIXTURE_MARKER}" CR TX-FLUSH\n',
            "KEY DROP\n",
            "_CRCT-RUN\n",
            "TX-FLUSH\n",
        )
    )
    return "".join(lines)


def _vertical(timeout: float) -> bool:
    import akashic_tui as harness

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/create-record-codec.f",),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "CREATE RECORD CODEC FAIL",
            "CREATE RECORD CODEC ASSERT",
            "CREATE RECORD CODEC STATUS",
            "CREATE RECORD CODEC STACK",
            "CREATE RECORD CODEC LOAD STACK FAIL",
            "CREATE RECORD CODEC FIXTURE STACK FAIL",
            "DRIVER THROW",
            "Branch offset overflow",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(
            (
                "local_testing/crec-codec-test.f",
                harness._minify_forth(  # noqa: SLF001
                    CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    stages = (
        ("boot", BOOT_MARKER, BOOT_MAX_STEPS),
        *(
            (f"module-{index:02d}", _module_marker(index), PHASE_MAX_STEPS)
            for index in range(1, len(MODULES) + 1)
        ),
        ("fixture", FIXTURE_MARKER, PHASE_MAX_STEPS),
        ("contracts", PASS_MARKER, PHASE_MAX_STEPS),
    )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=EXT_MEM_SIZE,
        num_cores=NUM_CORES,
    ) as machine:
        machine.boot()
        for index, (stage, marker, max_steps) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=max_steps,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw),  # noqa: SLF001
                        *harness._matched_failure_markers(  # noqa: SLF001
                            profile,
                            raw,
                            machine.screen_text(),
                        ),
                    )
                )
            )
            if marker not in raw or failures:
                print(f"CREATE RECORD CODEC {stage}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(f"  recent guest output:\n{raw[-5000:]}")
                return False
            print(
                f"CREATE RECORD CODEC {stage}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("CREATE RECORD CODEC vertical: PASS")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--static-only",
        action="store_true",
        help="check source and fixture contracts without an emulator",
    )
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run the opt-in single-core 64 MiB emulator gate",
    )
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    test_create_record_codec_source_contract()
    if not args.vertical:
        print("CREATE RECORD CODEC STATIC PASS")
        return 0
    return 0 if _vertical(args.timeout) else 1


if __name__ == "__main__":
    raise SystemExit(main())
