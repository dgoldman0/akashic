#!/usr/bin/env python3
"""Qualify bounded transport-neutral HTTP resource policy and ownership."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "net" / "http-resource.f"
TARGET = ROOT / "akashic" / "net" / "http-target.f"
DOC = ROOT / "docs" / "net" / "http-resource.md"
CONTRACT = LOCAL_TESTING / "hres-contracts.f"

PASS_MARKER = "HTTP RESOURCE CONTRACTS PASS"
MAX_PHASE_STEPS = 120_000_000
LOAD_STAGES = (
    ("event", "concurrency/event.f", "HRES EVENT READY"),
    ("semaphore", "concurrency/semaphore.f", "HRES SEMAPHORE READY"),
    ("guard", "concurrency/guard.f", "HRES GUARD READY"),
    ("string", "utils/string.f", "HRES STRING READY"),
    ("memory-span", "utils/memory-span.f", "HRES MEMORY SPAN READY"),
    ("io-port", "net/io-port.f", "HRES IO PORT READY"),
    ("external-io", "net/external-io.f", "HRES EXTERNAL IO READY"),
    ("http-request", "net/http-request.f", "HRES REQUEST READY"),
    ("http-stream", "net/http-stream.f", "HRES STREAM READY"),
    ("http-buffered", "net/http-buffered.f", "HRES BUFFERED READY"),
    ("http-target", "net/http-target.f", "HRES TARGET READY"),
    ("media-type", "net/media-type.f", "HRES MEDIA TYPE READY"),
    ("source", "net/http-resource.f", "HRES SOURCE READY"),
    ("fixture", "local_testing/hres-contracts.f", "HRES FIXTURE READY"),
)


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing Forth word {name}"
    return match.group("body")


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


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
    target = TARGET.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    forth_code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()

    assert 0 < MAX_PHASE_STEPS <= 180_000_000
    assert len({name for name, _, _ in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({marker for _, _, marker in LOAD_STAGES}) == len(LOAD_STAGES)
    assert _requires(SOURCE) == [
        "external-io.f",
        "http-buffered.f",
        "http-target.f",
        "media-type.f",
        "../utils/memory-span.f",
    ]
    assert "PROVIDED akashic-http-resource" in source
    for forbidden in ("atproto/", "streams", "oauth", "kdos-tls"):
        assert forbidden not in forth_code

    for word in (
        "HRES-SPEC-SUCCESS-RANGE!",
        "HRES-SPEC-MEDIA-MODE!",
        "HRES-SPEC-REDIRECT-AUTHORITY!",
        "HRES-MEDIA-REQUIRED",
        "HRES-MEDIA-IGNORED",
        "HRES-RESULT-VALID?",
        "HRES-BODY-STORAGE@",
        "HRES-MEDIA@",
        "HRES-D-REDIRECT-POLICY",
    ):
        assert word in source
    assert "HTARGET-REDIRECT-RESOLVE" in target
    assert "HTARGET-REDIRECT-RESOLVE" in _word_body(
        source, "_HRES-ADMIT-REDIRECT"
    )
    authority = _word_body(source, "_HRES-ADMIT-REDIRECT-AUTHORITY")
    assert "HRSPEC.REDIRECT-XT" in authority
    assert "CATCH" in authority
    assert "HRES-O-AUTHORITY-REQUIRED" in authority
    assert "_HRES-REDIRECT-CANDIDATE-CLEAR" in authority
    authority_inner = _word_body(source, "_HRES-REDIRECT-AUTH-INNER")
    assert "_HRES-AUTH-CURRENT" in authority_inner
    assert "_HRES-AUTH-CANDIDATE" in authority_inner
    final = _word_body(source, "_HRES-ADMIT-FINAL")
    assert "_HRES-MEDIA-REQUIRED?" in final
    assert "MTYPE-INIT" in final
    admit = _word_body(source, "_HRES-ADMIT-RESPONSE")
    assert "_HRES-FINAL-STATUS?" in admit
    assert "_HRES-ADMIT-FINAL" in admit

    for marker in (
        "_hrc-test-configured-final-policy",
        "_hrc-test-authority-policy",
        "mutated.example.test",
        "HRES-BODY-STORAGE@",
        "HRES-XERR-FAULT",
        "HTTP RESOURCE CONTRACTS PASS",
    ):
        assert marker in fixture
    for phrase in (
        "transport-neutral",
        "success",
        "media",
        "redirect",
        "same-origin",
    ):
        assert phrase in doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(TARGET, target)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - staged HTTP resource contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." HTTP RESOURCE LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_hrc-run\nTX-FLUSH\n")

    profile_name = "http-resource-staged"
    image = Path("/tmp/akashic-http-resource-staged.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("net/http-resource.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "HTTP RESOURCE CONTRACTS FAIL",
            "HRC ASSERT",
            "HRC STACK",
            "HTTP RESOURCE LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/hres-contracts.f",
                harness._minify_forth(
                    CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=4096,
    )
    image_path = harness.build_image(profile_name, image)
    profile = harness.PROFILES[profile_name]

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
                print(f"HTTP resource load {stage_name}: FAIL")
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
        print(f"HTTP resource lifecycle: {'PASS' if ok else 'FAIL'}")
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
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("HTTP RESOURCE STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
