#!/usr/bin/env python3
"""Focused guest qualification for the bounded cold-source loader."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "cold-source-loader-contracts"
IMAGE = Path("/tmp/akashic-cold-source-loader-contracts.img")
LOADER = LOCAL_TESTING / "cold-source-loader.f"
TOTAL_MAX_STEPS = 250_000_000
CHECKSUM_MARKER = "COLD SOURCE LOADER CHECKSUM PASS"
ROLLBACK_MARKER = "COLD SOURCE LOADER ROLLBACK PASS"
PASS_MARKER = "COLD SOURCE LOADER CONTRACTS PASS"
DONE_MARKER = "COLD SOURCE LOADER CONTRACTS DONE"


def _failure_fixtures() -> tuple[tuple[str, bytes], ...]:
    """Build bounded containers for the guest loader's failure paths."""
    header_bytes = harness.COLD_SOURCE_HEADER_BYTES

    bad_distance = bytearray(harness._pack_cold_source(b"ABCABC"))
    assert bad_distance[header_bytes:] == b"\x07ABC\x20\x00"
    bad_distance[-2:] = b"\x30\x00"  # distance four after three literals

    bad_canonical = bytearray(harness._pack_cold_source(b"A"))
    assert bad_canonical[header_bytes:] == b"\x01A"
    bad_canonical[header_bytes] = 0x03  # one nonzero unused control bit

    bad_crc = bytearray(
        harness._pack_cold_source(
            b": _CSLC-CRC-SHOULD-NOT-LAND 1 ;\n",
            codec=harness.COLD_SOURCE_CODEC_STORED,
        )
    )
    bad_crc[32] ^= 0x01

    bad_evaluate = harness._pack_cold_source(
        b": _CSLC-ROLLBACK-PREFIX 91 ;\n"
        b": _CSLC-UNFINISHED\n",
        codec=harness.COLD_SOURCE_CODEC_STORED,
    )
    retry = harness._pack_cold_source(
        b": _CSLC-RETRY-WORD 37 ;\n",
        codec=harness.COLD_SOURCE_CODEC_STORED,
    )

    fixtures = (
        ("csl-dist.src", bytes(bad_distance)),
        ("csl-canon.src", bytes(bad_canonical)),
        ("csl-crc.src", bytes(bad_crc)),
        ("csl-eval.src", bad_evaluate),
        ("csl-retry.src", retry),
    )
    maximum_container_bytes = (
        header_bytes
        + harness.COLD_SOURCE_RAW_MAX_BYTES
        + (harness.COLD_SOURCE_RAW_MAX_BYTES + 7) // 8
    )
    assert all(
        len(name.encode("utf-8")) <= harness.MAX_NAME_LEN
        and header_bytes < len(content) <= maximum_container_bytes
        for name, content in fixtures
    )
    return fixtures


FAILURE_FIXTURES = _failure_fixtures()


AUTOEXEC = r"""\ autoexec.f - bounded cold-source guest contract
ENTER-USERLAND
VARIABLE _cslc-fails
VARIABLE _cslc-checks
VARIABLE _cslc-depth
VARIABLE _cslc-xfree
VARIABLE _cslc-fds
VARIABLE _cslc-here
VARIABLE _cslc-latest
VARIABLE _cslc-edepth
: _cslc-assert  ( flag -- )
    1 _cslc-checks +!
    0= IF
        1 _cslc-fails +!
        ." COLD SOURCE LOADER ASSERT " _cslc-checks @ . CR TX-FLUSH
    THEN ;
: _cslc-available  ( -- bytes )
    XMEM-FREE XMEM-FL @
    BEGIN DUP WHILE
        DUP @ ROT + SWAP 8 + @
    REPEAT
    DROP ;
: _cslc-fd-used  ( -- count )
    0 FD-MAX 0 DO I FD-SLOT @ 0<> IF 1+ THEN LOOP ;
: _cslc-resources-recovered?  ( -- flag )
    _cslc-available _cslc-xfree @ =
    _cslc-fd-used _cslc-fds @ = AND ;
: _cslc-finish  ( -- )
    _cslc-fails @ 0= IF
        ." COLD SOURCE LOADER CONTRACTS PASS"
    ELSE
        ." COLD SOURCE LOADER CONTRACTS FAIL " _cslc-fails @ .
    THEN CR
    ." COLD SOURCE LOADER CONTRACTS DONE" CR TX-FLUSH ;
0 _cslc-fails ! 0 _cslc-checks ! DEPTH _cslc-depth !
_cslc-available _cslc-xfree ! _cslc-fd-used _cslc-fds !
REQUIRE utils/memory-span.f
DEPTH _cslc-depth @ = _cslc-assert
_cslc-resources-recovered? _cslc-assert
1 2 MSPAN-NONWRAPPING? _cslc-assert
-1 1 MSPAN-NONWRAPPING? 0= _cslc-assert
." COLD SOURCE LOADER VALID PASS" CR TX-FLUSH

\ Decode failures must release their descriptor and both bounded allocations.
COLD-SOURCE-LOAD csl-dist.src CSL-S-DISTANCE = _cslc-assert
_cslc-resources-recovered? _cslc-assert
." COLD SOURCE LOADER DISTANCE PASS" CR TX-FLUSH
COLD-SOURCE-LOAD csl-canon.src CSL-S-CANONICAL = _cslc-assert
_cslc-resources-recovered? _cslc-assert
." COLD SOURCE LOADER CANONICAL PASS" CR TX-FLUSH

\ A complete decode with the wrong raw checksum must fail before evaluation.
COLD-SOURCE-LOAD csl-crc.src CSL-S-CHECKSUM = _cslc-assert
_cslc-resources-recovered? _cslc-assert
." COLD SOURCE LOADER CHECKSUM PASS" CR TX-FLUSH

"""


def _profile() -> harness.Profile:
    return harness.Profile(
        roots=("utils/memory-span.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("COLD SOURCE LOADER CONTRACTS PASS",),
        stable_markers=("COLD SOURCE LOADER CONTRACTS PASS",),
        failure_markers=(
            "COLD SOURCE LOADER CONTRACTS FAIL",
            "COLD SOURCE LOADER ASSERT",
            "COLD SOURCE LOAD FAIL",
            "EVALUATE depth limit exceeded",
            "dictionary full",
            "exception",
            "? (not found)",
        ),
        linked=True,
        cold_source_codec=harness.COLD_SOURCE_CODEC_LZSS,
        include_large_sample=False,
        initial_files=FAILURE_FIXTURES,
        total_sectors=1024,
    )


def _assert_static_contracts() -> None:
    source = LOADER.read_text(encoding="utf-8")
    executable = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    )
    tokens = set(executable.split())
    assert "PROVIDED akashic-cold-source-loader" in source
    assert "COLD-SOURCE-LOAD" in tokens
    assert "(FCLOSE-NOFS)" in tokens
    assert "FCLOSE" not in tokens
    assert "CRC32-IEEE-BUF" in tokens
    assert "SOURCE-EVALUATE-CHECKED" in tokens
    assert "EVALUATOR-RESET" in tokens
    assert "LATEST!" in tokens
    assert not re.search(r"(?m)^.*\bDO\b.*\bR(?:@|>)\b", executable)
    assert max(map(len, source.splitlines())) <= 255
    assert tuple(name for name, _ in FAILURE_FIXTURES) == (
        "csl-dist.src",
        "csl-canon.src",
        "csl-crc.src",
        "csl-eval.src",
        "csl-retry.src",
    )


def _send_line(machine: harness.MachineSession, source: str) -> None:
    assert len(source.encode("utf-8")) <= harness.MEGAPAD_EVALUATE_SOURCE_MAX_BYTES
    machine.send_text(source)
    machine.send_key("enter")


def _run(timeout: float) -> int:
    profile = harness.PROFILES[PROFILE]
    image = harness.build_image(PROFILE, IMAGE)
    remaining = TOTAL_MAX_STEPS
    reports = []
    transcript = []

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=100,
        rows=30,
        batch_steps=250_000,
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()

        def run_until(label: str, marker: str) -> bool:
            nonlocal remaining
            report = machine.run(
                max_steps=remaining,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            remaining -= report.steps
            reports.append((label, report))
            if marker not in machine.raw_text():
                return False
            return remaining > 0

        if not run_until("decode/checksum failures", CHECKSUM_MARKER):
            transcript.append(machine.raw_text())
            return _report(False, reports, transcript, machine, profile)
        first_raw = machine.raw_text()
        prompt_after_checksum = first_raw.rfind("> ") > first_raw.index(
            CHECKSUM_MARKER
        )
        transcript.append(first_raw)
        machine.clear_output()

        # The valid autoexec now ends normally.  Observe its prompt, then
        # Measure evaluation rollback in an independent interpreter command:
        # EVALUATOR-RESET intentionally ends that source owner and returns the
        # loader status on the data stack for the following command to check.
        # Rebaseline allocator and descriptor ownership here because AUTOEXEC's
        # FSLOAD source buffer has been released by the time this prompt runs.
        if not prompt_after_checksum:
            if not run_until("evaluation rollback prompt", "> "):
                transcript.append(machine.raw_text())
                return _report(False, reports, transcript, machine, profile)
            transcript.append(machine.raw_text())
            machine.clear_output()

        _send_line(
            machine,
            "HERE _cslc-here ! LATEST _cslc-latest ! "
            "EVAL-DEPTH @ _cslc-edepth ! "
            "_cslc-available _cslc-xfree ! _cslc-fd-used _cslc-fds !",
        )
        if not run_until("evaluation baseline", "> "):
            transcript.append(machine.raw_text())
            return _report(False, reports, transcript, machine, profile)
        transcript.append(machine.raw_text())
        machine.clear_output()

        _send_line(machine, "COLD-SOURCE-LOAD csl-eval.src")
        if not run_until("evaluation failure", "> "):
            transcript.append(machine.raw_text())
            return _report(False, reports, transcript, machine, profile)
        transcript.append(machine.raw_text())
        machine.clear_output()

        _send_line(
            machine,
            "CSL-S-EVALUATE = _cslc-assert "
            "CSL-LAST-EVAL@ EVAL-S-UNFINISHED = _cslc-assert "
            "HERE _cslc-here @ = _cslc-assert "
            "LATEST _cslc-latest @ = _cslc-assert "
            "EVAL-DEPTH @ _cslc-edepth @ = _cslc-assert",
        )
        _send_line(
            machine,
            "_cslc-resources-recovered? _cslc-assert "
            f'." {ROLLBACK_MARKER}" CR TX-FLUSH',
        )
        if not run_until("rollback assertions", ROLLBACK_MARKER):
            transcript.append(machine.raw_text())
            return _report(False, reports, transcript, machine, profile)
        transcript.append(machine.raw_text())
        machine.clear_output()

        # A valid call after all four failures proves that descriptor and
        # allocation ownership is reusable in the same machine.
        _send_line(
            machine,
            "COLD-SOURCE-LOAD csl-retry.src CSL-S-OK = _cslc-assert "
            "_CSLC-RETRY-WORD 37 = _cslc-assert",
        )
        _send_line(
            machine,
            "_cslc-resources-recovered? _cslc-assert "
            "DEPTH _cslc-depth @ = _cslc-assert "
            '." COLD SOURCE LOADER REUSE PASS" CR TX-FLUSH',
        )
        _send_line(machine, "_cslc-finish")
        ok = run_until("valid retry", DONE_MARKER)
        transcript.append(machine.raw_text())
        return _report(ok, reports, transcript, machine, profile)


def _report(ok, reports, transcript, machine, profile) -> int:
    raw = "".join(transcript)
    failures = tuple(
        dict.fromkeys(
            (
                *harness._has_forth_error(raw),
                *harness._matched_failure_markers(
                    profile, raw, machine.screen_text()
                ),
            )
        )
    )
    ok = ok and not failures and PASS_MARKER in raw
    print(f"Cold source loader contracts: {'PASS' if ok else 'FAIL'}")
    for label, report in reports:
        print(
            f"  {label}: {report.steps:,} steps in "
            f"{report.elapsed_s:.2f}s; stop={report.reason}"
        )
    if not ok:
        for failure in failures:
            print(f"  {failure}")
        print(raw[-8000:])
        print(machine.screen_text())
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--static-only", action="store_true")
    parser.add_argument("--timeout", type=float, default=30.0)
    args = parser.parse_args()

    _assert_static_contracts()
    harness.PROFILES[PROFILE] = _profile()
    if args.static_only:
        print("COLD SOURCE LOADER STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
