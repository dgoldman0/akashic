#!/usr/bin/env python3
"""Qualify the shared exact-token KDOS network owner."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "net" / "kdos-network-owner.f"
DOC = ROOT / "docs" / "net" / "kdos-network-owner.md"
CONTRACT = LOCAL_TESTING / "kdos-net-owner-test.f"

PASS_MARKER = "KDOS NET OWNER PASS"
MAX_PHASE_STEPS = 120_000_000
LOAD_STAGES = (
    ("source", "net/kdos-network-owner.f", "KDOS NET OWNER READY"),
    (
        "fixture",
        "local_testing/kdos-net-owner-test.f",
        "KDOS NET OWNER FIXTURE READY",
    ),
)


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        code = line.split("\\", 1)[0]
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "parenthesized comments must close on their physical line: "
                f"{path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    contract = CONTRACT.read_text(encoding="utf-8")
    code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()

    assert 0 < MAX_PHASE_STEPS <= 180_000_000
    assert not re.search(r"(?mi)^[ \t]*REQUIRE\b", source)
    assert "PROVIDED akashic-kdos-net-owner" in source
    assert len(re.findall(r"(?mi)^[ \t]*VARIABLE\b", source)) == 1
    assert not re.search(r"(?mi)^[ \t]*(?:CREATE|VALUE|DEFER|GUARD)\b", source)
    for word in (
        "KDOSNET-S-OK",
        "KDOSNET-S-INVALID",
        "KDOSNET-S-BUSY",
        "KDOSNET-S-NOT-OWNER",
        "KDOSNET-S-PLATFORM",
        "KDOSNET-CLAIM",
        "KDOSNET-RELEASE",
        "KDOSNET-OWNER?",
        "KDOSNET-OPERATE?",
        "KDOSNET-OWNER@",
    ):
        assert word in source
    for forbidden in (
        "dns-",
        "tls-",
        "http",
        "atproto",
        "streams",
        "oauth",
        "credential",
        "tcp-",
        "udp-",
    ):
        assert forbidden not in code

    claim = _word_body(source, "KDOSNET-CLAIM")
    release = _word_body(source, "KDOSNET-RELEASE")
    owner_at = _word_body(source, "KDOSNET-OWNER@")
    operate = _word_body(source, "KDOSNET-OPERATE?")
    for body in (claim, release):
        assert "COREID" in body
    assert "COREID" not in owner_at
    assert "COREID" in operate
    assert "KDOSNET-OWNER?" in operate
    assert "KDOSNET-S-BUSY" in claim
    assert "_KDOSNET-OWNER !" in claim
    assert "KDOSNET-S-NOT-OWNER" in release
    assert release.index("<>") < release.index("0 _KDOSNET-OWNER !")
    assert "KDOSNET-S-NOT-OWNER" in contract
    assert "KDOSNET-S-BUSY" in contract
    assert len(CONTRACT.name) <= 23
    for phrase in (
        "machine-layer",
        "nonzero opaque identity",
        "never dereferences",
        "core-0-only mutations",
        "coherent read-only queries on every core",
        "nonrecursive",
        "no queue",
        "remains quarantined",
        "`kdos-dns` and `kdos-tls`",
    ):
        assert phrase in doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, contract)


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - staged KDOS network-owner contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." KDOS NET OWNER LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_KNOT-RUN\nTX-FLUSH\n")

    profile_name = "kdos-network-owner"
    image = Path("/tmp/akashic-kdos-network-owner.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("net/kdos-network-owner.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "KDOS NET OWNER FAIL",
            "KDOS NET OWNER ASSERT",
            "KDOS NET OWNER STACK",
            "KDOS NET OWNER LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/kdos-net-owner-test.f",
                harness._minify_forth(
                    CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=1024,
    )
    image_path = harness.build_image(profile_name, image)
    profile = harness.PROFILES[profile_name]

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=100,
        rows=32,
        batch_steps=100_000,
        ext_mem_size=64 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        reports = []
        for index, (stage_name, _, marker) in enumerate(LOAD_STAGES):
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
                        *harness._has_forth_error(raw),
                        *harness._matched_failure_markers(
                            profile, raw, machine.screen_text()
                        ),
                    )
                )
            )
            reports.append((stage_name, report))
            if marker not in raw or failures:
                print(f"KDOS network owner load {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in "
                    f"{report.elapsed_s:.2f}s; stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-4000:])
                return 1

        machine.clear_output()
        machine.send_text("x")
        report = machine.run(
            max_steps=MAX_PHASE_STEPS,
            wall_timeout_s=timeout,
            until_text=PASS_MARKER,
            text_scope="raw",
        )
        raw = machine.raw_text()
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
        ok = PASS_MARKER in raw and not failures
        print(f"KDOS network owner lifecycle: {'PASS' if ok else 'FAIL'}")
        for stage_name, stage_report in reports:
            print(
                f"  {stage_name}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        print(
            f"  lifecycle: {report.steps:,} steps in "
            f"{report.elapsed_s:.2f}s; stop={report.reason}"
        )
        if not ok:
            for failure in failures:
                print(f"  {failure}")
            print(raw[-4000:])
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("KDOS NETWORK OWNER STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
