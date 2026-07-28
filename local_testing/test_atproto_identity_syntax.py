#!/usr/bin/env python3
"""Qualify the stateless AT Protocol DID and handle syntax libraries."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
DID = ROOT / "akashic" / "atproto" / "did.f"
HANDLE = ROOT / "akashic" / "atproto" / "handle.f"
VECTOR_ROOT = LOCAL_TESTING / "fixtures" / "atproto" / "syntax"

PINNED_INTEROP_COMMIT = "056e5741bb330757205d6b16db5266fffcae937b"
PINNED_GIT_BLOBS = {
    "did_syntax_valid.txt": "5aa6c9e7e3b20b2cbfc764f3a9cac6b37f827209",
    "did_syntax_invalid.txt": "9e724b3d7b5023d11c1fab0fdd247440835f5d02",
    "handle_syntax_valid.txt": "a23a9213839e3a5ee733419a8d84fc889f8e9b5b",
    "handle_syntax_invalid.txt": "49275a390bf9a4bf611c6efbb4de454beadf5d4e",
}

PASS_MARKER = "ATPROTO IDENTITY SYNTAX PASS"
PHASE_MAX_STEPS = 120_000_000
LOAD_STAGES = (
    ("did", "ATPROTO IDENTITY DID READY"),
    ("handle", "ATPROTO IDENTITY HANDLE READY"),
    ("fixture", "ATPROTO IDENTITY FIXTURE READY"),
)


def _requires(path: Path) -> set[str]:
    return set(
        re.findall(
            r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
            path.read_text(encoding="utf-8"),
        )
    )


def _git_blob_id(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode("ascii")
    return hashlib.sha1(header + data).hexdigest()


def _vector_lines(name: str) -> list[str]:
    lines = (VECTOR_ROOT / name).read_text(encoding="utf-8").splitlines()
    return [line for line in lines if line and not line.startswith("#")]


def _assert_static_contracts() -> None:
    did = DID.read_text(encoding="utf-8")
    handle = HANDLE.read_text(encoding="utf-8")
    combined = did + "\n" + handle

    for name, blob in PINNED_GIT_BLOBS.items():
        data = (VECTOR_ROOT / name).read_bytes()
        assert _git_blob_id(data) == blob, (
            f"{name} no longer matches interop commit "
            f"{PINNED_INTEROP_COMMIT}"
        )

    for marker in (
        "PROVIDED akashic-did",
        "DID-VALIDATE",
        "DID-VALID?",
        "DID-METHOD@",
        "DID-SPECIFIC-ID@",
        "DID-LENGTH-MAX",
        "PROVIDED akashic-atproto-handle",
        "AT-HANDLE-VALIDATE",
        "AT-HANDLE-VALID?",
        "AT-HANDLE-NORMALIZED?",
        "AT-HANDLE-NORMALIZE",
        "AT-HANDLE-LENGTH-MAX",
        "AT-HANDLE-LABEL-MAX",
    ):
        assert marker in combined

    for path in (DID, HANDLE):
        source = path.read_text(encoding="utf-8")
        assert {
            "../utils/memory-span.f",
            "../utils/caller-span.f",
        }.issubset(_requires(path))
        assert not re.search(
            r"(?mi)^[ \t]*(VARIABLE|VALUE|DEFER|CREATE|GUARD)\b",
            source,
        ), f"{path} owns mutable module state"
        for line_number, line in enumerate(source.splitlines(), start=1):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )

    assert "VARIABLE _DID-" not in did
    assert ": DID-METHOD " not in did


def _forth_string(value: str) -> str:
    assert '"' not in value
    assert "\\" not in value
    return f'S" {value}"'


def _vector_assertion(value: str, validator: str, expected: str) -> str:
    encoded = value.encode("utf-8")
    if len(encoded) <= 96:
        return (
            f"    {_forth_string(value)} {validator} "
            f"{expected} _IDS-ASSERT\n"
        )

    assert value.isascii()
    lines = []
    offset = 0
    for start in range(0, len(value), 80):
        chunk = value[start : start + 80]
        lines.append(
            f"    {_forth_string(chunk)} _IDS-LONG {offset} + "
            "SWAP CMOVE\n"
        )
        offset += len(chunk)
    lines.append(
        f"    _IDS-LONG {len(encoded)} {validator} "
        f"{expected} _IDS-ASSERT\n"
    )
    return "".join(lines)


def _fixture_source() -> str:
    vector_checks: list[str] = []
    for name, validator, expected in (
        ("did_syntax_valid.txt", "DID-VALIDATE", "DID-S-OK ="),
        ("did_syntax_invalid.txt", "DID-VALIDATE", "DID-S-OK <>"),
        (
            "handle_syntax_valid.txt",
            "AT-HANDLE-VALIDATE",
            "AT-HANDLE-S-OK =",
        ),
        (
            "handle_syntax_invalid.txt",
            "AT-HANDLE-VALIDATE",
            "AT-HANDLE-S-OK <>",
        ),
    ):
        for value in _vector_lines(name):
            vector_checks.append(
                _vector_assertion(value, validator, expected)
            )

    return r"""
\ Exact DID/handle syntax and normalization lifecycle.
PROVIDED atproto-identity-syntax-test

VARIABLE _IDS-FAILS
VARIABLE _IDS-CHECKS
VARIABLE _IDS-DEPTH
VARIABLE _IDS-WRITTEN

CREATE _IDS-LONG 4096 ALLOT
CREATE _IDS-HANDLE 320 ALLOT
CREATE _IDS-DEST 320 ALLOT

: _IDS-ASSERT  ( flag -- )
    1 _IDS-CHECKS +!
    0= IF
        1 _IDS-FAILS +!
        ." ATPROTO IDENTITY SYNTAX ASSERT " _IDS-CHECKS @ . CR
    THEN ;

: _IDS-STACK  ( -- )
    DEPTH DUP _IDS-DEPTH @ <> IF
        ." ATPROTO IDENTITY SYNTAX STACK "
        _IDS-DEPTH @ . ." -> " DUP . CR .S CR
    THEN
    _IDS-DEPTH @ = _IDS-ASSERT ;

: _IDS-BYTE?  ( address length byte -- flag )
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

: _IDS-DID-SLICES  ( -- )
    S" did:key:zABC" DID-METHOD@
    DUP DID-S-OK = _IDS-ASSERT
    DROP
    2DUP S" key" COMPARE 0= _IDS-ASSERT
    2DROP

    S" did:key:zABC" DID-SPECIFIC-ID@
    DUP DID-S-OK = _IDS-ASSERT
    DROP
    2DUP S" zABC" COMPARE 0= _IDS-ASSERT
    2DROP

    S" did:key:zABC" DID-VALID? _IDS-ASSERT
    S" did:METHOD:zABC" DID-VALID? 0= _IDS-ASSERT
    S" did:future:value" DID-VALIDATE DID-S-OK = _IDS-ASSERT
    _IDS-STACK ;

: _IDS-DID-BOUNDARIES  ( -- )
    _IDS-LONG DID-LENGTH-MAX 1+ [CHAR] v FILL
    S" did:m:" _IDS-LONG SWAP CMOVE
    _IDS-LONG DID-LENGTH-MAX DID-VALIDATE
        DID-S-OK = _IDS-ASSERT
    _IDS-LONG DID-LENGTH-MAX 1+ DID-VALIDATE
        DID-S-CAPACITY = _IDS-ASSERT

    S" did:m:v%ab" DID-VALIDATE DID-S-OK = _IDS-ASSERT
    S" did:m:v%AB" DID-VALIDATE DID-S-OK = _IDS-ASSERT
    S" did:m:v%" DID-VALIDATE DID-S-ENCODING = _IDS-ASSERT
    S" did:m:v%0" DID-VALIDATE DID-S-ENCODING = _IDS-ASSERT
    S" did:m:v%XZ" DID-VALIDATE DID-S-ENCODING = _IDS-ASSERT

    S" did:m:vv" _IDS-HANDLE SWAP CMOVE
    0 _IDS-HANDLE 6 + C!
    _IDS-HANDLE 8 DID-VALIDATE DID-S-SYNTAX = _IDS-ASSERT
    0 -1 DID-VALIDATE DID-S-INVALID = _IDS-ASSERT
    _IDS-STACK ;

: _IDS-HANDLE-NORMALIZATION  ( -- )
    S" XX.LCS.MIT.EDU" AT-HANDLE-NORMALIZED?
    DUP AT-HANDLE-S-OK = _IDS-ASSERT
    DROP 0= _IDS-ASSERT
    S" xx.lcs.mit.edu" AT-HANDLE-NORMALIZED?
    DUP AT-HANDLE-S-OK = _IDS-ASSERT
    DROP _IDS-ASSERT

    _IDS-DEST 320 0xA5 FILL
    S" XX.LCS.MIT.EDU" _IDS-DEST 320 AT-HANDLE-NORMALIZE
    DUP AT-HANDLE-S-OK = _IDS-ASSERT
    DROP DUP _IDS-WRITTEN ! 14 = _IDS-ASSERT
    _IDS-DEST _IDS-WRITTEN @ S" xx.lcs.mit.edu"
        COMPARE 0= _IDS-ASSERT
    _IDS-DEST _IDS-WRITTEN @ + C@ 0xA5 = _IDS-ASSERT

    S" Alice.Example" _IDS-HANDLE SWAP CMOVE
    _IDS-HANDLE 13 _IDS-HANDLE 13 AT-HANDLE-NORMALIZE
    DUP AT-HANDLE-S-OK = _IDS-ASSERT
    DROP 13 = _IDS-ASSERT
    _IDS-HANDLE 13 S" alice.example" COMPARE 0= _IDS-ASSERT

    S" Alice.Example" _IDS-HANDLE SWAP CMOVE
    _IDS-HANDLE 13 _IDS-HANDLE 1+ 13 AT-HANDLE-NORMALIZE
    DUP AT-HANDLE-S-ALIAS = _IDS-ASSERT
    DROP 0= _IDS-ASSERT
    _IDS-HANDLE 13 S" Alice.Example" COMPARE 0= _IDS-ASSERT

    _IDS-DEST 320 0xA5 FILL
    S" Alice.Example" _IDS-DEST 4 AT-HANDLE-NORMALIZE
    DUP AT-HANDLE-S-CAPACITY = _IDS-ASSERT
    DROP 0= _IDS-ASSERT
    _IDS-DEST 20 0xA5 _IDS-BYTE? _IDS-ASSERT

    _IDS-DEST 320 0xA5 FILL
    S" bad_handle.test" _IDS-DEST 320 AT-HANDLE-NORMALIZE
    DUP AT-HANDLE-S-SYNTAX = _IDS-ASSERT
    DROP 0= _IDS-ASSERT
    _IDS-DEST 20 0xA5 _IDS-BYTE? _IDS-ASSERT

    S" john.test" AT-HANDLE-VALID? _IDS-ASSERT
    S" john..test" AT-HANDLE-VALID? 0= _IDS-ASSERT
    S" handle.invalid" AT-HANDLE-VALIDATE
        AT-HANDLE-S-OK = _IDS-ASSERT
    0 -1 AT-HANDLE-VALIDATE
        AT-HANDLE-S-INVALID = _IDS-ASSERT
    _IDS-STACK ;

: _IDS-VECTORS  ( -- )
""" + "".join(vector_checks) + r"""
    _IDS-STACK ;

: _IDS-RUN  ( -- )
    0 _IDS-FAILS !
    0 _IDS-CHECKS !
    DEPTH _IDS-DEPTH !
    _IDS-DID-SLICES
    _IDS-DID-BOUNDARIES
    _IDS-HANDLE-NORMALIZATION
    _IDS-VECTORS
    _IDS-FAILS @ 0= IF
        ." ATPROTO IDENTITY SYNTAX PASS " _IDS-CHECKS @ . CR
    ELSE
        ." ATPROTO IDENTITY SYNTAX FAIL " _IDS-FAILS @ .
        ." / " _IDS-CHECKS @ . CR
    THEN ;
"""


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    fixture = harness._minify_forth(_fixture_source()).encode("utf-8")
    autoexec = (
        "\\ autoexec.f - AT Protocol identifier syntax\n"
        "ENTER-USERLAND\n"
        "REQUIRE atproto/did.f\n"
        f'." {LOAD_STAGES[0][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE atproto/handle.f\n"
        f'." {LOAD_STAGES[1][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "REQUIRE local_testing/at-id-syntax-test.f\n"
        "DEPTH IF\n"
        '  ." ATPROTO IDENTITY SYNTAX LOAD STACK FAIL" CR TX-FLUSH\n'
        "THEN\n"
        f'." {LOAD_STAGES[2][1]}" CR TX-FLUSH\n'
        "KEY DROP\n"
        "_IDS-RUN\n"
    )

    profile_name = "atproto-identity-syntax"
    image = Path("/tmp/akashic-atproto-identity-syntax.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("atproto/did.f", "atproto/handle.f"),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "ATPROTO IDENTITY SYNTAX FAIL",
            "ATPROTO IDENTITY SYNTAX ASSERT",
            "ATPROTO IDENTITY SYNTAX STACK",
            "ATPROTO IDENTITY SYNTAX LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/at-id-syntax-test.f", fixture),
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
                max_steps=PHASE_MAX_STEPS,
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
                    "Staged atproto-identity-syntax: FAIL\n"
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
        print(f"Staged atproto-identity-syntax: {'PASS' if ok else 'FAIL'}")
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
        print("ATPROTO IDENTITY SYNTAX STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
