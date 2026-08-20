#!/usr/bin/env python3
"""Qualify the exact caller-owned Bluesky text-record encoder."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"
SOURCE = SOURCE_ROOT / "atproto" / "bluesky-text-record.f"
FIXTURE = LOCAL_TESTING / "bsky-text-rec-test.f"
PROFILE = "bluesky-text-record"
IMAGE = Path("/tmp/akashic-bluesky-text-record.img")
BOOT_MARKER = "BSKY TEXT RECORD USERLAND READY"
BUNDLE_MARKER = "BSKY TEXT RECORD BUNDLE READY"
PASS_MARKER = "BSKY TEXT RECORD PASS"
MAX_PHASE_STEPS = 120_000_000
EXT_MEM_SIZE = 64 << 20
NUM_CORES = 1

sys.path.insert(0, str(LOCAL_TESTING))
from forth_dependencies import dependency_order  # noqa: E402


MODULES = dependency_order(
    SOURCE_ROOT, ("atproto/bluesky-text-record.f",)
)
EXPECTED_MODULES = (
    "utils/uint-range.f",
    "utils/memory-span.f",
    "utils/caller-span.f",
    "utils/buffer-writer.f",
    "concurrency/event.f",
    "concurrency/semaphore.f",
    "concurrency/guard.f",
    "text/utf8.f",
    "utils/json-writer.f",
    "utils/datetime.f",
    "atproto/bluesky-text-record.f",
)


def _forth_code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(name)}(?=[\s(])(?P<body>.*?)\s+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS comments must close on their physical line: "
                f"{path}:{line_number}"
            )


def test_bluesky_text_record_source_contract() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    code = _forth_code(source)

    assert MODULES == EXPECTED_MODULES
    assert re.findall(r"(?mi)^\s*REQUIRE\s+(\S+)", source) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../utils/buffer-writer.f",
        "../utils/json-writer.f",
        "../utils/datetime.f",
    ]
    assert "PROVIDED akashic-bsky-text-rec" in source
    assert not re.search(
        r"(?mi)^\s*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b", code
    )
    for word in (
        "BSKY-TEXT-RECORD-STATUS-VALID?",
        "BSKY-TEXT-RECORD-MEASURE",
        "BSKY-TEXT-RECORD-WORKSPACE-CLEAR",
        "BSKY-TEXT-RECORD-ENCODE",
    ):
        assert word in source
    assert "BSKY-TEXT-RECORD-TEXT-MAX 6 * 75 +" in source
    assert "DT-RFC3339-UTC-S" in source
    assert "JSONW-STRING" in source
    assert "UTF8-VALID?" in source
    assert "EPOCH@" not in code

    geometry = _word_body(source, "_BSKYTR-GEOMETRY")
    assert geometry.count("MSPAN-OVERLAP?") == 3
    assert "OVER 0<" in geometry
    assert "2 PICK 0<" not in geometry
    op = _word_body(source, "_BSKYTR-OP")
    assert op.index("_BSKYTR-ENCODE-STAGING") < op.index("MOVE")
    encode = _word_body(source, "_BSKYTR-ENCODE-STAGING")
    for key in ("$type", "app.bsky.feed.post", "text", "createdAt"):
        assert key in encode
    assert encode.index("$type") < encode.index("text") < encode.index(
        "createdAt"
    )

    for evidence in (
        "BSKY-TEXT-RECORD-BODY-MAX",
        "BSKY-TEXT-RECORD-S-ALIAS",
        "BSKY-TEXT-RECORD-S-UTF8",
        "BSKY TEXT RECORD PASS",
        "6075",
    ):
        assert evidence in fixture

    forbidden_line_parsers = re.compile(
        r"(?i)(?<![A-Za-z0-9_-])"
        r"(?:SOURCE|>IN|REFILL|PARSE|WORD|EVALUATE)"
        r"(?![A-Za-z0-9_-])"
    )
    for module in MODULES:
        path = SOURCE_ROOT / module
        module_source = path.read_text(encoding="utf-8")
        assert not forbidden_line_parsers.search(_forth_code(module_source)), module
        _assert_physical_comments(path, module_source)
    _assert_physical_comments(FIXTURE, fixture)


def _autoexec() -> str:
    return "".join(
        (
            "\\ autoexec.f - focused Bluesky text record qualification\n",
            "ENTER-USERLAND\n",
            f'." {BOOT_MARKER}" CR TX-FLUSH\n',
            "KEY DROP\n",
            "REQUIRE atproto/bluesky-text-record.f\n",
            "REQUIRE local_testing/bsky-text-rec-test.f\n",
            "DEPTH IF .\" BSKY TEXT RECORD LOAD STACK FAIL\" CR TX-FLUSH THEN\n",
            f'." {BUNDLE_MARKER}" CR TX-FLUSH\n',
            "KEY DROP\n",
            "_BTRT-RUN\n",
            "TX-FLUSH\n",
        )
    )


def _vertical(timeout: float) -> bool:
    import akashic_tui as harness

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/bluesky-text-record.f",),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "BSKY TEXT RECORD FAIL",
            "BSKY TEXT RECORD ASSERT",
            "BSKY TEXT RECORD LOAD STACK FAIL",
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
            ("local_testing/bsky-text-rec-test.f", FIXTURE.read_bytes()),
        ),
        linked=True,
        audited_link_line_bytes=harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
        audited_initial_forth_line_bytes=(
            harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES
        ),
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    stages = (
        ("boot", BOOT_MARKER),
        ("bundle", BUNDLE_MARKER),
        ("contracts", PASS_MARKER),
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
        for index, (stage, marker) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=MAX_PHASE_STEPS,
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
                            profile, raw, machine.screen_text()
                        ),
                    )
                )
            )
            if marker not in raw or failures:
                print(f"BSKY TEXT RECORD {stage}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(f"  recent guest output:\n{raw[-5000:]}")
                return False
            print(
                f"BSKY TEXT RECORD {stage}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--vertical", action="store_true", help="run the one-core emulator gate"
    )
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    test_bluesky_text_record_source_contract()
    if not args.vertical:
        print("BSKY TEXT RECORD STATIC PASS")
        return 0
    return 0 if _vertical(args.timeout) else 1


if __name__ == "__main__":
    raise SystemExit(main())
