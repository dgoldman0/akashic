#!/usr/bin/env python3
"""Qualify the stateless exact AT Protocol NSID syntax boundary."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
NSID = ROOT / "akashic" / "atproto" / "nsid.f"

PASS_MARKER = "ATPROTO NSID PASS"
BOOT_MAX_STEPS = 180_000_000
PHASE_MAX_STEPS = 120_000_000
LOAD_STAGES = (
    ("boot", "ATPROTO NSID USERLAND READY"),
    ("memory-span", "ATPROTO NSID MEMORY SPAN READY"),
    ("caller-span", "ATPROTO NSID CALLER SPAN READY"),
    ("nsid", "ATPROTO NSID LIBRARY READY"),
    ("fixture", "ATPROTO NSID FIXTURE READY"),
)


def _requires(path: Path) -> set[str]:
    return set(
        re.findall(
            r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
            path.read_text(encoding="utf-8"),
        )
    )


def _assert_static_contracts() -> None:
    source = NSID.read_text(encoding="utf-8")

    assert {
        "../utils/memory-span.f",
        "../utils/caller-span.f",
    }.issubset(_requires(NSID))
    for marker in (
        "PROVIDED akashic-atproto-nsid",
        "5   CONSTANT NSID-LENGTH-MIN",
        "317 CONSTANT NSID-LENGTH-MAX",
        "253 CONSTANT NSID-AUTHORITY-LENGTH-MAX",
        "63  CONSTANT NSID-LABEL-LENGTH-MAX",
        "63  CONSTANT NSID-NAME-LENGTH-MAX",
        ": NSID-CHECK",
        ": NSID-VALID?",
        ": NSID-SPLIT",
        ": NSID-CANONICALIZE",
        "MSPAN-OVERLAP? IF",
        "3 PICK R@ - 1-",
        "OVER I > IF _NSID-LOWER THEN",
    ):
        assert marker in source

    assert not re.search(
        r"(?mi)^[ \t]*(VARIABLE|VALUE|DEFER|CREATE|GUARD)\b",
        source,
    ), "NSID syntax library owns mutable module state"
    assert "[CHAR] * =" not in source

    last_dot_start = source.index(": _NSID-LAST-DOT")
    last_dot_end = source.index(": _NSID-AUTH-LABEL-STATUS")
    last_dot = source[last_dot_start:last_dot_end]
    assert ">R" not in last_dot
    assert "R@" not in last_dot

    canonical = source[source.index(": NSID-CANONICALIZE") :]
    assert canonical.index("NSID-CHECK") < canonical.index(
        "MSPAN-OVERLAP? IF"
    )
    assert canonical.index("MSPAN-OVERLAP? IF") < canonical.index("C!")

    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their "
                f"physical line: {NSID}:{line_number}"
            )


def _fixture_source() -> str:
    return r"""
\ Exact AT Protocol NSID grammar, views, and canonicalization.
PROVIDED atproto-nsid-test

VARIABLE _NQ-FAILS
VARIABLE _NQ-CHECKS
VARIABLE _NQ-DEPTH
VARIABLE _NQ-WRITTEN

CREATE _NQ-LONG 640 ALLOT
CREATE _NQ-DEST 640 ALLOT
CREATE _NQ-SNAPSHOT 640 ALLOT

: _NQ-ASSERT  ( flag -- )
    1 _NQ-CHECKS +!
    0= IF
        1 _NQ-FAILS +!
        ." ATPROTO NSID ASSERT " _NQ-CHECKS @ . CR
    THEN ;

: _NQ-STACK  ( -- )
    DEPTH DUP _NQ-DEPTH @ <> IF
        ." ATPROTO NSID STACK "
        _NQ-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _NQ-DEPTH @ = _NQ-ASSERT ;

: _NQ-BYTES?  ( address length byte -- flag )
    >R
    BEGIN
        DUP
    WHILE
        OVER C@ R@ <> IF
            2DROP R> DROP 0 EXIT
        THEN
        1- SWAP 1+ SWAP
    REPEAT
    2DROP R> DROP -1 ;

: _NQ-MAX!  ( -- )
    _NQ-LONG 640 [CHAR] a FILL
    [CHAR] . _NQ-LONG 63 + C!
    [CHAR] . _NQ-LONG 127 + C!
    [CHAR] . _NQ-LONG 191 + C!
    [CHAR] . _NQ-LONG 253 + C! ;

: _NQ-AUTH254!  ( -- )
    _NQ-LONG 640 [CHAR] a FILL
    [CHAR] . _NQ-LONG 63 + C!
    [CHAR] . _NQ-LONG 127 + C!
    [CHAR] . _NQ-LONG 191 + C!
    [CHAR] . _NQ-LONG 254 + C! ;

: _NQ-LABEL64!  ( -- )
    _NQ-LONG 640 [CHAR] a FILL
    [CHAR] . _NQ-LONG 64 + C!
    [CHAR] . _NQ-LONG 66 + C! ;

: _NQ-NAME64!  ( -- )
    _NQ-LONG 640 [CHAR] a FILL
    [CHAR] . _NQ-LONG 1 + C!
    [CHAR] . _NQ-LONG 3 + C! ;

: _NQ-MIXED!  ( -- )
    S" COM.Example.FooBar2" _NQ-LONG SWAP CMOVE ;

: _NQ-SYNTAX  ( -- )
    S" a.b.c" NSID-CHECK NSID-S-OK = _NQ-ASSERT
    S" com.example.fooBar2" NSID-VALID? _NQ-ASSERT
    S" COM.Example.FooBar2" NSID-CHECK
        NSID-S-OK = _NQ-ASSERT
    S" com.4example.foo" NSID-CHECK
        NSID-S-OK = _NQ-ASSERT

    S" com.example" NSID-CHECK
        NSID-S-AUTHORITY = _NQ-ASSERT
    S" 4com.example.foo" NSID-CHECK
        NSID-S-AUTHORITY = _NQ-ASSERT
    S" com..foo" NSID-CHECK
        NSID-S-AUTHORITY = _NQ-ASSERT
    S" com.-example.foo" NSID-CHECK
        NSID-S-AUTHORITY = _NQ-ASSERT
    S" com.example-.foo" NSID-CHECK
        NSID-S-AUTHORITY = _NQ-ASSERT
    S" com.example." NSID-CHECK NSID-S-NAME = _NQ-ASSERT
    S" com.example.0foo" NSID-CHECK
        NSID-S-NAME = _NQ-ASSERT
    S" com.example.foo-bar" NSID-CHECK
        NSID-S-NAME = _NQ-ASSERT
    S" com.example.foo_bar" NSID-CHECK
        NSID-S-NAME = _NQ-ASSERT

    \ Namespace globs are deliberately outside this exact-NSID API.
    S" com.example.*" NSID-CHECK NSID-S-NAME = _NQ-ASSERT
    S" com.example.foo.*" NSID-VALID? 0= _NQ-ASSERT
    S" com.example.foo*" NSID-VALID? 0= _NQ-ASSERT

    S" COM.Example.FooBar2" NSID-SPLIT
    DUP NSID-S-OK = _NQ-ASSERT
    DROP
    2DUP S" FooBar2" COMPARE 0= _NQ-ASSERT
    2DROP
    2DUP S" COM.Example" COMPARE 0= _NQ-ASSERT
    2DROP

    S" com.example.*" NSID-SPLIT
    DUP NSID-S-NAME = _NQ-ASSERT
    DROP
    OR OR OR 0= _NQ-ASSERT

    NSID-S-OK NSID-STATUS-VALID? _NQ-ASSERT
    NSID-S-PLATFORM NSID-STATUS-VALID? _NQ-ASSERT
    -1 NSID-STATUS-VALID? 0= _NQ-ASSERT
    NSID-S-PLATFORM 1+ NSID-STATUS-VALID? 0= _NQ-ASSERT
    _NQ-STACK ;

: _NQ-BOUNDS  ( -- )
    _NQ-MAX!
    _NQ-LONG NSID-LENGTH-MAX NSID-CHECK
        NSID-S-OK = _NQ-ASSERT
    _NQ-LONG NSID-LENGTH-MAX NSID-SPLIT
    DUP NSID-S-OK = _NQ-ASSERT
    DROP
    DUP NSID-NAME-LENGTH-MAX = _NQ-ASSERT
    2DROP
    DUP NSID-AUTHORITY-LENGTH-MAX = _NQ-ASSERT
    2DROP

    _NQ-LONG NSID-LENGTH-MAX 1+ NSID-CHECK
        NSID-S-CAPACITY = _NQ-ASSERT
    _NQ-AUTH254!
    _NQ-LONG 256 NSID-CHECK
        NSID-S-AUTHORITY = _NQ-ASSERT
    _NQ-LABEL64!
    _NQ-LONG 68 NSID-CHECK
        NSID-S-AUTHORITY = _NQ-ASSERT
    _NQ-NAME64!
    _NQ-LONG 68 NSID-CHECK NSID-S-NAME = _NQ-ASSERT

    0 -1 NSID-CHECK NSID-S-INVALID = _NQ-ASSERT
    0 1 NSID-CHECK NSID-S-INVALID = _NQ-ASSERT
    0 0 NSID-CHECK NSID-S-SYNTAX = _NQ-ASSERT
    _NQ-STACK ;

: _NQ-CANONICALIZATION  ( -- )
    _NQ-DEST 640 0xA5 FILL
    S" COM.Example.FooBar2"
    _NQ-DEST 640 NSID-CANONICALIZE
    DUP NSID-S-OK = _NQ-ASSERT
    DROP
    DUP _NQ-WRITTEN ! 19 = _NQ-ASSERT
    _NQ-DEST _NQ-WRITTEN @
        S" com.example.FooBar2" COMPARE 0= _NQ-ASSERT
    _NQ-DEST _NQ-WRITTEN @ + C@ 0xA5 = _NQ-ASSERT

    \ Exact-base publication admits a larger capacity and writes source-u.
    _NQ-MIXED!
    _NQ-LONG 19 _NQ-LONG 640 NSID-CANONICALIZE
    DUP NSID-S-OK = _NQ-ASSERT
    DROP 19 = _NQ-ASSERT
    _NQ-LONG 19 S" com.example.FooBar2"
        COMPARE 0= _NQ-ASSERT

    \ An adjacent destination is disjoint and therefore admitted.
    _NQ-MIXED!
    _NQ-LONG 19 _NQ-LONG 19 + 64 NSID-CANONICALIZE
    DUP NSID-S-OK = _NQ-ASSERT
    DROP 19 = _NQ-ASSERT
    _NQ-LONG 19 + 19 S" com.example.FooBar2"
        COMPARE 0= _NQ-ASSERT

    \ Partial overlap rejects before modifying either participating span.
    _NQ-MIXED!
    _NQ-LONG _NQ-SNAPSHOT 32 CMOVE
    _NQ-LONG 19 _NQ-LONG 1+ 19 NSID-CANONICALIZE
    DUP NSID-S-ALIAS = _NQ-ASSERT
    DROP 0= _NQ-ASSERT
    _NQ-LONG 32 _NQ-SNAPSHOT 32 COMPARE 0= _NQ-ASSERT

    _NQ-DEST 32 0xA5 FILL
    S" COM.Example.FooBar2"
    _NQ-DEST 18 NSID-CANONICALIZE
    DUP NSID-S-CAPACITY = _NQ-ASSERT
    DROP 0= _NQ-ASSERT
    _NQ-DEST 32 0xA5 _NQ-BYTES? _NQ-ASSERT

    _NQ-DEST 32 0xA5 FILL
    S" com.example.foo-bar"
    _NQ-DEST 32 NSID-CANONICALIZE
    DUP NSID-S-NAME = _NQ-ASSERT
    DROP 0= _NQ-ASSERT
    _NQ-DEST 32 0xA5 _NQ-BYTES? _NQ-ASSERT

    S" com.example.foo" 0 32 NSID-CANONICALIZE
    DUP NSID-S-INVALID = _NQ-ASSERT
    DROP 0= _NQ-ASSERT
    S" com.example.foo" _NQ-DEST -1 NSID-CANONICALIZE
    DUP NSID-S-INVALID = _NQ-ASSERT
    DROP 0= _NQ-ASSERT
    _NQ-STACK ;

: _NQ-RUN  ( -- )
    0 _NQ-FAILS !
    0 _NQ-CHECKS !
    DEPTH _NQ-DEPTH !
    _NQ-SYNTAX
    _NQ-BOUNDS
    _NQ-CANONICALIZATION
    _NQ-FAILS @ 0= IF
        ." ATPROTO NSID PASS " _NQ-CHECKS @ . CR
    ELSE
        ." ATPROTO NSID FAIL " _NQ-FAILS @ .
        ." / " _NQ-CHECKS @ . CR
    THEN ;
"""


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    fixture = harness._minify_forth(_fixture_source()).encode("utf-8")
    autoexec = (
        "\\ autoexec.f - exact AT Protocol NSID qualification\n"
        "ENTER-USERLAND\n"
        f'." {LOAD_STAGES[0][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE utils/memory-span.f\n"
        f'." {LOAD_STAGES[1][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE utils/caller-span.f\n"
        f'." {LOAD_STAGES[2][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE atproto/nsid.f\n"
        f'." {LOAD_STAGES[3][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/atproto-nsid-test.f\n"
        "DEPTH IF\n"
        '  ." ATPROTO NSID LOAD STACK FAIL" CR TX-FLUSH\n'
        "THEN\n"
        f'." {LOAD_STAGES[4][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "_NQ-RUN\n"
    )

    profile_name = "atproto-nsid"
    image = Path("/tmp/akashic-atproto-nsid.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("atproto/nsid.f",),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "ATPROTO NSID FAIL",
            "ATPROTO NSID ASSERT",
            "ATPROTO NSID STACK",
            "ATPROTO NSID LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/atproto-nsid-test.f", fixture),
        ),
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
        output = []
        for index, (stage_name, stage_marker) in enumerate(LOAD_STAGES):
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
                until_text=stage_marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            stage_failures = failures(machine)
            reports.append((stage_name, report))
            output.extend((f"\n--- load {stage_name} ---\n", raw))
            if stage_marker not in raw or stage_failures:
                print(
                    "Staged atproto-nsid: FAIL\n"
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
        output.extend(("\n--- lifecycle ---\n", raw))
        ok = PASS_MARKER in raw and not lifecycle_failures
        root = harness.OUTPUT_ROOT / f"smoke-{profile_name}"
        root.with_suffix(".raw.txt").write_text(
            "".join(output),
            encoding="utf-8",
        )
        print(f"Staged atproto-nsid: {'PASS' if ok else 'FAIL'}")
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
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("ATPROTO NSID STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
