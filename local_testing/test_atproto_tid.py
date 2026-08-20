#!/usr/bin/env python3
"""Qualify caller-owned TIDs and the feed-model validation migration."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"
TID = SOURCE_ROOT / "atproto" / "tid.f"
FEED_MODEL = SOURCE_ROOT / "atproto" / "feed-model.f"
FIXTURE = LOCAL_TESTING / "atproto-tid-test.f"
PROFILE = "atproto-tid"
IMAGE = Path("/tmp/akashic-atproto-tid.img")
BOOT_MARKER = "AT TID USERLAND READY"
BUNDLE_MARKER = "AT TID BUNDLE READY"
PASS_MARKER = "AT TID PASS"
MAX_PHASE_STEPS = 120_000_000
EXT_MEM_SIZE = 64 << 20
NUM_CORES = 1

sys.path.insert(0, str(LOCAL_TESTING))
from forth_dependencies import dependency_order  # noqa: E402


MODULES = dependency_order(SOURCE_ROOT, ("atproto/feed-model.f",))
EXPECTED_MODULES = (
    "concurrency/event.f",
    "concurrency/semaphore.f",
    "concurrency/guard.f",
    "text/utf8.f",
    "utils/string.f",
    "utils/json.f",
    "utils/uint-range.f",
    "utils/memory-span.f",
    "utils/caller-span.f",
    "atproto/tid.f",
    "atproto/feed-model.f",
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


def test_atproto_tid_source_contract() -> None:
    tid = TID.read_text(encoding="utf-8")
    feed = FEED_MODEL.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    tid_code = _forth_code(tid)

    assert MODULES == EXPECTED_MODULES
    assert re.findall(r"(?mi)^\s*REQUIRE\s+(\S+)", tid) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
    ]
    assert not re.search(
        r"(?mi)^\s*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b", tid_code
    )
    assert "EPOCH@" not in tid_code
    assert "TID-NOW" not in tid
    for word in (
        "TID-STATUS-VALID?",
        "TID-VALIDATE",
        "TID-VALID?",
        "TID-COMPARE",
        "TID-CLOCK-INIT",
        "TID-CLOCK-VALID?",
        "TID-CLOCK-NEXT-MS",
    ):
        assert word in tid
    for loop_word in ("_TID-SYNTAX?", "TID-COMPARE", "_TID-ENCODE"):
        body = _word_body(tid, loop_word)
        assert not re.search(r"(?<![A-Za-z0-9_-])(?:>R|R@|R>)(?![A-Za-z0-9_-])", body)
    next_body = _word_body(tid, "TID-CLOCK-NEXT-MS")
    assert next_body.index("_TID-ENCODE") < next_body.index(
        "_TID-CLOCK-LAST-OFF + !"
    )

    assert "REQUIRE tid.f" in feed
    assert "TID-VALID?" in _word_body(feed, "_BFM-POST-URI?")
    assert "_BFM-TID?" not in feed
    assert "_BFM-TID-CHAR?" not in feed

    for evidence in (
        "2222222222222",
        "222222222zc22",
        "bzzzzzzzzzzzz",
        "TID-S-ALIAS",
        "TID-S-EXHAUSTED",
        "AT TID PASS",
    ):
        assert evidence in fixture

    forbidden_line_parsers = re.compile(
        r"(?i)(?<![A-Za-z0-9_-])"
        r"(?:SOURCE|>IN|REFILL|PARSE|WORD|EVALUATE)"
        r"(?![A-Za-z0-9_-])"
    )
    for module in MODULES:
        path = SOURCE_ROOT / module
        source = path.read_text(encoding="utf-8")
        assert not forbidden_line_parsers.search(_forth_code(source)), module
        _assert_physical_comments(path, source)
    _assert_physical_comments(FIXTURE, fixture)


def _autoexec(core: bool) -> str:
    production = "atproto/tid.f" if core else "atproto/feed-model.f"
    return "".join(
        (
            "\\ autoexec.f - focused caller-owned TID qualification\n",
            "ENTER-USERLAND\n",
            f'." {BOOT_MARKER}" CR TX-FLUSH\n',
            "KEY DROP\n",
            f"REQUIRE {production}\n",
            "REQUIRE local_testing/atproto-tid-test.f\n",
            "DEPTH IF .\" AT TID LOAD STACK FAIL\" CR TX-FLUSH THEN\n",
            f'." {BUNDLE_MARKER}" CR TX-FLUSH\n',
            "KEY DROP\n",
            "_TIDT-RUN\n",
            "TX-FLUSH\n",
        )
    )


def _vertical(timeout: float, core: bool) -> bool:
    import akashic_tui as harness

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(("atproto/tid.f",) if core else ("atproto/feed-model.f",)),
        resources=(),
        autoexec=_autoexec(core),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT TID FAIL",
            "AT TID ASSERT",
            "AT TID LOAD STACK FAIL",
            "DRIVER THROW",
            "Branch offset overflow",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(("local_testing/atproto-tid-test.f", FIXTURE.read_bytes()),),
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
                print(f"AT TID {stage}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(f"  recent guest output:\n{raw[-5000:]}")
                return False
            print(
                f"AT TID {stage}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--vertical", action="store_true", help="run the one-core emulator gate"
    )
    parser.add_argument(
        "--core",
        action="store_true",
        help="with --vertical, load only tid.f for fast primitive iteration",
    )
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    test_atproto_tid_source_contract()
    if not args.vertical:
        print("AT TID STATIC PASS")
        return 0
    return 0 if _vertical(args.timeout, args.core) else 1


if __name__ == "__main__":
    raise SystemExit(main())
