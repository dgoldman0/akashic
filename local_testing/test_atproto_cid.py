#!/usr/bin/env python3
"""Qualify stateless blessed AT Protocol CID text admission."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "atproto" / "cid.f"
DOC = ROOT / "docs" / "atproto" / "cid.md"

PASS_MARKER = "ATPROTO CID PASS"
BOOT_MAX_STEPS = 180_000_000
PHASE_MAX_STEPS = 120_000_000
LOAD_STAGES = (
    ("boot", "ATPROTO CID USERLAND READY"),
    ("caller-span", "ATPROTO CID CALLER SPAN READY"),
    ("cid", "ATPROTO CID LIBRARY READY"),
    ("fixture", "ATPROTO CID FIXTURE READY"),
)

FIXTURE = r"""
\ Blessed AT Protocol CIDv1 text profile.
PROVIDED atproto-cid-test

VARIABLE _CQT-FAILS
VARIABLE _CQT-CHECKS
VARIABLE _CQT-DEPTH
CREATE _CQT-COPY 59 ALLOT
CREATE _CQT-SNAPSHOT 59 ALLOT

: _CQT-ASSERT  ( flag -- )
    1 _CQT-CHECKS +!
    0= IF
        1 _CQT-FAILS +!
        ." ATPROTO CID ASSERT " _CQT-CHECKS @ . CR
    THEN ;

: _CQT-STACK  ( -- )
    DEPTH DUP _CQT-DEPTH @ <> IF
        ." ATPROTO CID STACK "
        _CQT-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _CQT-DEPTH @ = _CQT-ASSERT ;

: _CQT-EXPECT-OK  ( actual-codec actual-status expected-codec -- )
    >R
    AT-CID-S-OK = _CQT-ASSERT
    R> = _CQT-ASSERT ;

: _CQT-EXPECT-FAIL  ( actual-codec actual-status expected-status -- )
    >R
    R> = _CQT-ASSERT
    AT-CID-CODEC-NONE = _CQT-ASSERT ;

: _CQT-ADMITTED  ( -- )
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-CODEC-DAG-CBOR _CQT-EXPECT-OK

    S" bafkreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-CODEC-RAW _CQT-EXPECT-OK

    \ Digest bits may fill every base32 position, including the three
    \ digest bits sharing the seventh symbol with the fixed header.
    S" bafyreih777777777777777777777777777777777777777777777777774"
    AT-CID-TEXT-CHECK AT-CID-CODEC-DAG-CBOR _CQT-EXPECT-OK

    S" bafkreiaaaebagbafaydqqcikbmga2dqpcaireeyuculbogazdinryhi6d4"
    AT-CID-TEXT-CHECK AT-CID-CODEC-RAW _CQT-EXPECT-OK

    S" bafyreih777777777777777777777777777777777777777777777777774"
    AT-CID-TEXT-VALID? _CQT-ASSERT
    AT-CID-CODEC-DAG-CBOR AT-CID-CODEC-VALID? _CQT-ASSERT
    AT-CID-CODEC-RAW AT-CID-CODEC-VALID? _CQT-ASSERT
    AT-CID-CODEC-NONE AT-CID-CODEC-VALID? 0= _CQT-ASSERT
    _CQT-STACK ;

: _CQT-ENCODING  ( -- )
    S" Bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-ENCODING _CQT-EXPECT-FAIL
    S" bafyreiAaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-ENCODING _CQT-EXPECT-FAIL
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa="
    AT-CID-TEXT-CHECK AT-CID-S-ENCODING _CQT-EXPECT-FAIL
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"
    AT-CID-TEXT-CHECK AT-CID-S-ENCODING _CQT-EXPECT-FAIL

    \ Values b, c, and d differ only in noncanonical trailing pad bits.
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab"
    AT-CID-TEXT-CHECK AT-CID-S-ENCODING _CQT-EXPECT-FAIL
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaac"
    AT-CID-TEXT-CHECK AT-CID-S-ENCODING _CQT-EXPECT-FAIL
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaad"
    AT-CID-TEXT-CHECK AT-CID-S-ENCODING _CQT-EXPECT-FAIL

    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-LENGTH _CQT-EXPECT-FAIL
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-LENGTH _CQT-EXPECT-FAIL
    _CQT-STACK ;

: _CQT-PROFILE  ( -- )
    \ CIDv2, CBOR codec, SHA-512 code, and wrong digest lengths remain
    \ well-formed base32 text but are outside the blessed AT profile.
    S" bajyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-PROFILE _CQT-EXPECT-FAIL
    S" bafireiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-PROFILE _CQT-EXPECT-FAIL
    S" bafyrgiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-PROFILE _CQT-EXPECT-FAIL
    S" bafyrehyaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-PROFILE _CQT-EXPECT-FAIL
    S" bafyreiiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK AT-CID-S-PROFILE _CQT-EXPECT-FAIL
    _CQT-STACK ;

: _CQT-OWNERSHIP  ( -- )
    S" bafyreih777777777777777777777777777777777777777777777777774"
    _CQT-COPY SWAP CMOVE
    _CQT-COPY _CQT-SNAPSHOT AT-CID-TEXT-LENGTH CMOVE
    _CQT-COPY AT-CID-TEXT-LENGTH AT-CID-TEXT-CHECK
    AT-CID-CODEC-DAG-CBOR _CQT-EXPECT-OK
    _CQT-COPY AT-CID-TEXT-LENGTH
    _CQT-SNAPSHOT AT-CID-TEXT-LENGTH COMPARE 0= _CQT-ASSERT

    0 -1 AT-CID-TEXT-CHECK
    AT-CID-S-INVALID _CQT-EXPECT-FAIL
    0 AT-CID-TEXT-LENGTH AT-CID-TEXT-CHECK
    AT-CID-S-INVALID _CQT-EXPECT-FAIL
    0 0 AT-CID-TEXT-CHECK
    AT-CID-S-LENGTH _CQT-EXPECT-FAIL
    _CQT-STACK ;

: _CQT-INTERLEAVED  ( -- )
    \ Both complete results remain live while a second call executes.
    S" bafyreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    AT-CID-TEXT-CHECK
    S" bafkreiaaaebagbafaydqqcikbmga2dqpcaireeyuculbogazdinryhi6d4"
    AT-CID-TEXT-CHECK
    AT-CID-S-OK = _CQT-ASSERT
    AT-CID-CODEC-RAW = _CQT-ASSERT
    AT-CID-S-OK = _CQT-ASSERT
    AT-CID-CODEC-DAG-CBOR = _CQT-ASSERT
    _CQT-STACK ;

: _CQT-STATUSES  ( -- )
    AT-CID-TEXT-LENGTH 59 = _CQT-ASSERT
    AT-CID-S-OK AT-CID-STATUS-VALID? _CQT-ASSERT
    AT-CID-S-PLATFORM AT-CID-STATUS-VALID? _CQT-ASSERT
    -1 AT-CID-STATUS-VALID? 0= _CQT-ASSERT
    AT-CID-S-PLATFORM 1+ AT-CID-STATUS-VALID? 0= _CQT-ASSERT
    _CQT-STACK ;

: _CQT-RUN  ( -- )
    0 _CQT-FAILS !
    0 _CQT-CHECKS !
    DEPTH _CQT-DEPTH !
    _CQT-ADMITTED
    _CQT-ENCODING
    _CQT-PROFILE
    _CQT-OWNERSHIP
    _CQT-INTERLEAVED
    _CQT-STATUSES
    _CQT-FAILS @ 0= IF
        ." ATPROTO CID PASS " _CQT-CHECKS @ . CR
    ELSE
        ." ATPROTO CID FAIL " _CQT-FAILS @ .
        ." / " _CQT-CHECKS @ . CR
    THEN ;
"""


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


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

    assert _requires(SOURCE) == ["../utils/caller-span.f"]
    for marker in (
        "PROVIDED akashic-atproto-cid",
        "59 CONSTANT AT-CID-TEXT-LENGTH",
        "0x55 CONSTANT AT-CID-CODEC-RAW",
        "0x71 CONSTANT AT-CID-CODEC-DAG-CBOR",
        ": AT-CID-CODEC-VALID?",
        ": AT-CID-STATUS-VALID?",
        ": AT-CID-TEXT-CHECK",
        ": AT-CID-TEXT-VALID?",
        "CALLER-SPAN-STATUS _ATCID-CALLER>STATUS",
        '6 S" afyrei" COMPARE',
        '6 S" afkrei" COMPARE',
        "[CHAR] a [CHAR] h 1+ WITHIN",
        "AT-CID-TEXT-LENGTH 2 - + C@ _ATCID-FINAL?",
    ):
        assert marker in source

    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "CID admission library owns mutable module state"
    assert "CAPACITY" not in source
    assert " C!" not in source

    encoding = source[
        source.index(": _ATCID-ENCODING?") :
        source.index(": _ATCID-PROFILE")
    ]
    loop = encoding[encoding.index("0 ?DO") : encoding.index("LOOP")]
    for return_stack_word in (">R", "R@", "R>"):
        assert return_stack_word not in loop

    check = source[source.index(": AT-CID-TEXT-CHECK") :]
    assert check.index("_ATCID-SPAN-STATUS") < check.index(
        "_ATCID-ENCODING?"
    )

    for phrase in (
        "exactly 59 ASCII bytes",
        "not an implementation capacity",
        "canonical zero trailing bits",
        "require `AT-CID-CODEC-DAG-CBOR`",
        "https://atproto.com/specs/data-model#link-and-cid-formats",
    ):
        assert phrase in doc
    _assert_physical_comments(SOURCE, source)


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    fixture = harness._minify_forth(FIXTURE).encode("utf-8")
    autoexec = (
        "\\ autoexec.f - blessed AT Protocol CID qualification\n"
        "ENTER-USERLAND\n"
        f'." {LOAD_STAGES[0][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE utils/caller-span.f\n"
        f'." {LOAD_STAGES[1][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE atproto/cid.f\n"
        f'." {LOAD_STAGES[2][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/atproto-cid-test.f\n"
        "DEPTH IF\n"
        '  ." ATPROTO CID LOAD STACK FAIL" CR TX-FLUSH\n'
        "THEN\n"
        f'." {LOAD_STAGES[3][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "_CQT-RUN\n"
        "TX-FLUSH\n"
    )

    profile_name = "atproto-cid"
    image = Path("/tmp/akashic-atproto-cid.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("atproto/cid.f",),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "ATPROTO CID FAIL",
            "ATPROTO CID ASSERT",
            "ATPROTO CID STACK",
            "ATPROTO CID LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(("local_testing/atproto-cid-test.f", fixture),),
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
                    "Staged atproto-cid: FAIL\n"
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
        print(f"Staged atproto-cid: {'PASS' if ok else 'FAIL'}")
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
        print("ATPROTO CID STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
