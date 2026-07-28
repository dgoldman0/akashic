#!/usr/bin/env python3
"""Qualify the stateless AT Protocol record-key syntax boundary."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "atproto" / "record-key.f"
DOC = ROOT / "docs" / "atproto" / "record-key.md"

PASS_MARKER = "ATPROTO RKEY PASS"
BOOT_MAX_STEPS = 180_000_000
PHASE_MAX_STEPS = 120_000_000
LOAD_STAGES = (
    ("boot", "ATPROTO RKEY USERLAND READY"),
    ("memory-span", "ATPROTO RKEY MEMORY SPAN READY"),
    ("caller-span", "ATPROTO RKEY CALLER SPAN READY"),
    ("record-key", "ATPROTO RKEY LIBRARY READY"),
    ("fixture", "ATPROTO RKEY FIXTURE READY"),
)

FIXTURE = r"""
\ Exact AT Protocol general record-key grammar.
PROVIDED atproto-rkey-test

VARIABLE _RKT-FAILS
VARIABLE _RKT-CHECKS
VARIABLE _RKT-DEPTH
CREATE _RKT-LONG 520 ALLOT

: _RKT-ASSERT  ( flag -- )
    1 _RKT-CHECKS +!
    0= IF
        1 _RKT-FAILS +!
        ." ATPROTO RKEY ASSERT " _RKT-CHECKS @ . CR
    THEN ;

: _RKT-STACK  ( -- )
    DEPTH DUP _RKT-DEPTH @ <> IF
        ." ATPROTO RKEY STACK "
        _RKT-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _RKT-DEPTH @ = _RKT-ASSERT ;

: _RKT-SYNTAX  ( -- )
    S" 3jui7kd54zh2y" AT-RKEY-VALID? _RKT-ASSERT
    S" self" AT-RKEY-VALID? _RKT-ASSERT
    S" Example.COM" AT-RKEY-VALID? _RKT-ASSERT
    S" ~1.2-3_" AT-RKEY-VALID? _RKT-ASSERT
    S" pre:fix" AT-RKEY-VALID? _RKT-ASSERT
    S" _" AT-RKEY-VALID? _RKT-ASSERT
    S" a" AT-RKEY-VALID? _RKT-ASSERT

    S" " AT-RKEY-VALIDATE AT-RKEY-S-SYNTAX = _RKT-ASSERT
    S" ." AT-RKEY-VALIDATE AT-RKEY-S-SYNTAX = _RKT-ASSERT
    S" .." AT-RKEY-VALIDATE AT-RKEY-S-SYNTAX = _RKT-ASSERT
    S" alpha/beta" AT-RKEY-VALID? 0= _RKT-ASSERT
    S" #extra" AT-RKEY-VALID? 0= _RKT-ASSERT
    S" @handle" AT-RKEY-VALID? 0= _RKT-ASSERT
    S" any space" AT-RKEY-VALID? 0= _RKT-ASSERT
    S" any+space" AT-RKEY-VALID? 0= _RKT-ASSERT
    S" dHJ1ZQ==" AT-RKEY-VALID? 0= _RKT-ASSERT
    S" alpha%2Fbeta" AT-RKEY-VALID? 0= _RKT-ASSERT
    _RKT-STACK ;

: _RKT-BOUNDS  ( -- )
    _RKT-LONG 520 [CHAR] a FILL
    _RKT-LONG AT-RKEY-LENGTH-MAX AT-RKEY-VALID?
        _RKT-ASSERT
    _RKT-LONG AT-RKEY-LENGTH-MAX 1+
        AT-RKEY-VALIDATE AT-RKEY-S-CAPACITY = _RKT-ASSERT
    0 -1 AT-RKEY-VALIDATE AT-RKEY-S-INVALID = _RKT-ASSERT
    0 1 AT-RKEY-VALIDATE AT-RKEY-S-INVALID = _RKT-ASSERT
    0 0 AT-RKEY-VALIDATE AT-RKEY-S-SYNTAX = _RKT-ASSERT
    0 _RKT-LONG 255 + C!
    _RKT-LONG 512 AT-RKEY-VALIDATE
        AT-RKEY-S-SYNTAX = _RKT-ASSERT

    AT-RKEY-S-OK AT-RKEY-STATUS-VALID? _RKT-ASSERT
    AT-RKEY-S-PLATFORM AT-RKEY-STATUS-VALID? _RKT-ASSERT
    -1 AT-RKEY-STATUS-VALID? 0= _RKT-ASSERT
    AT-RKEY-S-PLATFORM 1+ AT-RKEY-STATUS-VALID? 0= _RKT-ASSERT
    _RKT-STACK ;

: _RKT-RUN  ( -- )
    0 _RKT-FAILS !
    0 _RKT-CHECKS !
    DEPTH _RKT-DEPTH !
    _RKT-SYNTAX
    _RKT-BOUNDS
    _RKT-FAILS @ 0= IF
        ." ATPROTO RKEY PASS " _RKT-CHECKS @ . CR
    ELSE
        ." ATPROTO RKEY FAIL " _RKT-FAILS @ .
        ." / " _RKT-CHECKS @ . CR
    THEN ;
"""


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their "
                f"physical line: {path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    doc = " ".join(DOC.read_text(encoding="utf-8").split())

    assert re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source
    ) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
    ]
    for marker in (
        "PROVIDED akashic-atproto-record-key",
        "1   CONSTANT AT-RKEY-LENGTH-MIN",
        "512 CONSTANT AT-RKEY-LENGTH-MAX",
        ": AT-RKEY-STATUS-VALID?",
        ": AT-RKEY-VALIDATE",
        ": AT-RKEY-VALID?",
        "[CHAR] ~ =",
        "_ATRK-DOT-RESERVED?",
    ):
        assert marker in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    )
    validate = source[source.index(": AT-RKEY-VALIDATE") :]
    assert "0 ?DO" in validate and " I + C@" in validate
    loop = validate[validate.index("0 ?DO") : validate.index("LOOP")]
    for return_stack_word in (">R", "R@", "R>"):
        assert return_stack_word not in loop
    for phrase in (
        "1 through 512 ASCII characters",
        "The exact values `.` and `..` are rejected",
        "Keys are case-sensitive and are never normalized",
        "https://atproto.com/specs/record-key",
    ):
        assert phrase in doc
    _assert_physical_comments(SOURCE, source)


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    fixture = harness._minify_forth(FIXTURE).encode("utf-8")
    autoexec = (
        "\\ autoexec.f - exact AT Protocol record-key qualification\n"
        "ENTER-USERLAND\n"
        f'." {LOAD_STAGES[0][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE utils/memory-span.f\n"
        f'." {LOAD_STAGES[1][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE utils/caller-span.f\n"
        f'." {LOAD_STAGES[2][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE atproto/record-key.f\n"
        f'." {LOAD_STAGES[3][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/rkey-syntax-test.f\n"
        "DEPTH IF\n"
        '  ." ATPROTO RKEY LOAD STACK FAIL" CR TX-FLUSH\n'
        "THEN\n"
        f'." {LOAD_STAGES[4][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "_RKT-RUN\n"
        "TX-FLUSH\n"
    )

    profile_name = "atproto-record-key"
    image = Path("/tmp/akashic-atproto-record-key.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("atproto/record-key.f",),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "ATPROTO RKEY FAIL",
            "ATPROTO RKEY ASSERT",
            "ATPROTO RKEY STACK",
            "ATPROTO RKEY LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(("local_testing/rkey-syntax-test.f", fixture),),
        linked=False,
        include_large_sample=False,
        total_sectors=2048,
    )
    image_path = harness.build_image(profile_name, image)
    profile = harness.PROFILES[profile_name]

    def failures(machine: object) -> tuple[str, ...]:
        raw = machine.raw_text()
        screen = machine.screen_text()
        found = list(harness._has_forth_error(raw))
        found.extend(
            harness._matched_failure_markers(profile, raw, screen)
        )
        return tuple(dict.fromkeys(found))

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=64 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        reports = []
        for index, (stage_name, marker) in enumerate(LOAD_STAGES):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=(
                    BOOT_MAX_STEPS
                    if stage_name == "boot"
                    else PHASE_MAX_STEPS
                ),
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            stage_failures = failures(machine)
            reports.append((stage_name, report))
            if marker not in raw or stage_failures:
                print(
                    "Staged atproto-record-key: FAIL\n"
                    f"  {stage_name}: {report.steps:,} steps in "
                    f"{report.elapsed_s:.2f}s; stop={report.reason}"
                )
                for failure in stage_failures:
                    print(f"  {stage_name} failure: {failure}")
                print(f"  recent guest output:\n{raw[-4000:]}")
                return 1

        machine.clear_output()
        machine.send_text("x")
        lifecycle = machine.run(
            max_steps=PHASE_MAX_STEPS,
            wall_timeout_s=timeout,
            until_text=PASS_MARKER,
            text_scope="raw",
        )
        raw = machine.raw_text()
        lifecycle_failures = failures(machine)
        ok = PASS_MARKER in raw and not lifecycle_failures
        print(f"Staged atproto-record-key: {'PASS' if ok else 'FAIL'}")
        for stage_name, report in reports:
            print(
                f"  {stage_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}"
            )
        print(
            f"  lifecycle: {lifecycle.steps:,} steps in "
            f"{lifecycle.elapsed_s:.2f}s; stop={lifecycle.reason}"
        )
        if not ok:
            for failure in lifecycle_failures:
                print(f"  lifecycle failure: {failure}")
            print(f"  recent guest output:\n{raw[-4000:]}")
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("ATPROTO RKEY STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
