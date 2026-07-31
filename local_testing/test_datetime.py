#!/usr/bin/env python3
"""Qualify the checked, state-free datetime replacement."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "utils" / "datetime.f"
FIXTURE = LOCAL_TESTING / "datetime-test.f"
PROFILE = "checked-datetime"
IMAGE = Path("/tmp/akashic-checked-datetime.img")
BOOT_MARKER = "DATETIME USERLAND READY"
BUNDLE_MARKER = "DATETIME BUNDLE READY"
PASS_MARKER = "DATETIME PASS"
MAX_PHASE_STEPS = 120_000_000
EXT_MEM_SIZE = 64 << 20
NUM_CORES = 1

sys.path.insert(0, str(LOCAL_TESTING))
from forth_dependencies import dependency_order  # noqa: E402


MODULES = dependency_order(ROOT / "akashic", ("utils/datetime.f",))


def _forth_code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS comments must close on their physical line: "
                f"{path}:{line_number}"
            )


def test_datetime_source_contract() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    code = _forth_code(source)

    assert MODULES == ("utils/caller-span.f", "utils/datetime.f")
    assert re.findall(r"(?mi)^\s*REQUIRE\s+(\S+)", source) == [
        "caller-span.f"
    ]
    assert "PROVIDED akashic-datetime" in source
    assert not re.search(
        r"(?mi)^\s*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b", code
    )
    for word in (
        "DT-STATUS-VALID?",
        "DT-MONTH-DAYS",
        "DT-EPOCH-S>YMD",
        "DT-YMD>EPOCH-S",
        "DT-DATE-S",
        "DT-RFC3339-UTC-S",
        "DT-NOW-MS",
        "DT-NOW-S",
    ):
        assert word in source
    for removed in (
        "DT-ISO8601",
        "DT-PARSE-ISO",
        "DT-EPOCH>YMD",
        "DT-YMD>EPOCH ",
        "DT-DATE ",
        "DT-TIME",
        "_DT-DIM@",
    ):
        assert removed not in source
    assert "CALLER-SPAN-STATUS" in source
    assert "DUP IF >R _DT-3DROP 0 R> EXIT THEN" in source

    tree = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (ROOT / "akashic").rglob("*.f")
    )
    assert "DT-ISO8601" not in tree
    assert "DT-PARSE-ISO" not in tree
    assert "_DT-DIM@" not in tree
    assert "PROVIDED datetime-test" in fixture
    assert "9999-12-31T23:59:59Z" in fixture
    assert "DATETIME PASS" in fixture

    forbidden_line_parsers = re.compile(
        r"(?i)(?<![A-Za-z0-9_-])"
        r"(?:SOURCE|>IN|REFILL|PARSE|WORD|EVALUATE)"
        r"(?![A-Za-z0-9_-])"
    )
    for module in MODULES:
        module_source = (ROOT / "akashic" / module).read_text(
            encoding="utf-8"
        )
        assert not forbidden_line_parsers.search(_forth_code(module_source))
        _assert_physical_comments(ROOT / "akashic" / module, module_source)
    _assert_physical_comments(FIXTURE, fixture)


def _autoexec() -> str:
    return "".join(
        (
            "\\ autoexec.f - focused datetime qualification\n",
            "ENTER-USERLAND\n",
            f'." {BOOT_MARKER}" CR TX-FLUSH\n',
            "KEY DROP\n",
            "REQUIRE utils/datetime.f\n",
            "REQUIRE local_testing/datetime-test.f\n",
            "DEPTH IF .\" DATETIME LOAD STACK FAIL\" CR TX-FLUSH THEN\n",
            f'." {BUNDLE_MARKER}" CR TX-FLUSH\n',
            "KEY DROP\n",
            "_DTT-RUN\n",
            "TX-FLUSH\n",
        )
    )


def _vertical(timeout: float) -> bool:
    import akashic_tui as harness

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("utils/datetime.f",),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "DATETIME FAIL",
            "DATETIME ASSERT",
            "DATETIME LOAD STACK FAIL",
            "DRIVER THROW",
            "Branch offset overflow",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
            "(not found)",
        ),
        initial_files=(("local_testing/datetime-test.f", FIXTURE.read_bytes()),),
        linked=True,
        audited_link_line_bytes=harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES,
        audited_initial_forth_line_bytes=(
            harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES
        ),
        include_large_sample=False,
        total_sectors=2048,
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
                print(f"DATETIME {stage}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(f"  recent guest output:\n{raw[-5000:]}")
                return False
            print(
                f"DATETIME {stage}: PASS "
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

    test_datetime_source_contract()
    if not args.vertical:
        print("DATETIME STATIC PASS")
        return 0
    return 0 if _vertical(args.timeout) else 1


if __name__ == "__main__":
    raise SystemExit(main())
