#!/usr/bin/env python3
"""Focused qualification for caller-owned AT Protocol identity discovery."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "atproto" / "identity.f"
DOC = ROOT / "docs" / "atproto" / "identity.md"
CONTRACT = LOCAL_TESTING / "at-identity-test.f"

PASS_MARKER = "ATPROTO IDENTITY PASS"
MAX_PHASE_STEPS = 180_000_000
LIFECYCLE_MAX_STEPS = 180_000_000
LOAD_STAGES = (
    ("memory-span", "utils/memory-span.f", "ATID MEMORY SPAN READY", 120_000_000),
    ("caller-span", "utils/caller-span.f", "ATID CALLER SPAN READY", 120_000_000),
    ("string", "utils/string.f", "ATID STRING READY", 120_000_000),
    (
        "json-object",
        "security/jose/json-object.f",
        "ATID JSON OBJECT READY",
        180_000_000,
    ),
    ("http-target", "net/http-target.f", "ATID HTTP TARGET READY", 120_000_000),
    ("did", "atproto/did.f", "ATID DID READY", 120_000_000),
    ("handle", "atproto/handle.f", "ATID HANDLE READY", 120_000_000),
    (
        "did-document",
        "atproto/did-document.f",
        "ATID DID DOCUMENT READY",
        180_000_000,
    ),
    ("dns-txt", "net/dns-txt.f", "ATID DNS TXT READY", 180_000_000),
    ("identity", "atproto/identity.f", "ATID IDENTITY READY", 180_000_000),
    (
        "fixture",
        "local_testing/at-identity-test.f",
        "ATID FIXTURE READY",
        120_000_000,
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
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    forth_code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()
    doc = DOC.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert 0 < LIFECYCLE_MAX_STEPS <= MAX_PHASE_STEPS
    assert all(
        0 < stage_steps <= MAX_PHASE_STEPS
        for _, _, _, stage_steps in LOAD_STAGES
    )
    assert len({name for name, _, _, _ in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({marker for _, _, marker, _ in LOAD_STAGES}) == len(LOAD_STAGES)

    assert _requires(SOURCE) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../net/http-target.f",
        "../net/dns-txt.f",
        "did.f",
        "handle.f",
        "did-document.f",
    ]
    assert "PROVIDED akashic-atproto-identity" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "identity core owns mutable module state"
    for forbidden in (
        "streams",
        "oauth",
        "xrpc",
        "udp-send",
        "tcp-",
        "kdos-tls",
        "hres-",
    ):
        assert forbidden not in forth_code

    for word in (
        "ATID-RESULT-SIZE",
        "ATID-RESOLVER-SIZE",
        "ATID-RESULT-INIT",
        "ATID-RESULT-VALID?",
        "ATID-RESULT-READY?",
        "ATID-RESOLVER-CLEAR",
        "ATID-RESOLVER-VALID?",
        "ATID-BEGIN-HANDLE",
        "ATID-BEGIN-DID",
        "ATID-ACTION@",
        "ATID-DNS-NAME@",
        "ATID-DNS-QUERY-BUILD",
        "ATID-DNS-QUERY$",
        "ATID-DNS-RESPONSE!",
        "ATID-HTTP-TARGET@",
        "ATID-HTTP-RESPONSE!",
        "ATID-ACTION-FAIL",
        "ATID-DID@",
        "ATID-HANDLE@",
        "ATID-DOCUMENT@",
        "ATID-PUBLIC-KEY-MULTIBASE@",
        "ATID-PDS-TARGET@",
        "ATID-PDS-ORIGIN@",
        "ATID-EVIDENCE@",
        "ATID-PARTICIPATION-STATUS",
        "ATID-PARTICIPATION-READY?",
        "ATID-RESOLVER-WIPE",
        "ATID-A-DNS-QUERY",
        "ATID-A-DNS-EXCHANGE",
        "ATID-E-HANDLE-VERIFIED",
        "ATID-E-HANDLE-MISSING",
        "ATID-E-HANDLE-INVALID",
        "ATID-E-PARTICIPATION",
    ):
        assert word in source

    assert "4096 CONSTANT DNS-TXT-VALUE-MAX" in (
        ROOT / "akashic" / "net" / "dns-txt.f"
    ).read_text(encoding="utf-8")
    assert "_ATIDW-RR-VALUE-OFF DNS-TXT-VALUE-MAX +" in source
    assert "ATID-DNS-HANDLE-MAX" in source
    assert "244 CONSTANT ATID-DNS-HANDLE-MAX" in source
    assert "8   CONSTANT ATID-DNS-CNAME-MAX" in source
    assert "3   CONSTANT ATID-HTTP-REDIRECT-MAX" in source
    assert "U>=" not in source
    assert not re.search(r"(?mi)\b(?:\?DO|DO)\b", source)

    txt_reduce = _word_body(source, "_ATID-TXT-REDUCE")
    assert "DNS-TXT-ITER-NEXT" in txt_reduce
    assert "DNS-TXT-ITER-VALIDATED?" in txt_reduce
    assert "DNS-TXT-RR-PROVISIONAL?" in _word_body(
        source, "_ATID-RR-DID$"
    )
    decide = _word_body(source, "_ATID-DNS-DECIDE")
    assert decide.index("_ATIDW.DNS-CONFLICT") < decide.index(
        "ATID-E-HANDLE-DNS"
    )
    assert "_ATID-USE-MAPPING" in decide
    assert "_ATID-START-HANDLE-HTTPS" in _word_body(
        source, "_ATID-DNS-FALLBACK"
    )
    assert "ATID-A-DNS-QUERY" in _word_body(source, "_ATID-FOLLOW-CNAME")
    query_build = _word_body(source, "ATID-DNS-QUERY-BUILD")
    assert "DNS-TXT-QUERY-BUILD" in query_build
    assert "_ATIDW.PREV-DNS-ID" in query_build

    http_response = _word_body(source, "ATID-HTTP-RESPONSE!")
    assert "ATID-HTTP-REDIRECT-MAX" in http_response
    assert "_ATID-HTTP-STATUS?" in http_response
    assert "AT-DIDDOC-PARSE" in _word_body(
        source, "_ATID-DIDDOC-HTTP-RESPONSE"
    )
    assert "AT-DIDDOC-PARTICIPATION-STATUS" in source
    assert "ATID-E-HANDLE-INVALID" in _word_body(
        source, "_ATID-DISCOVERY-FAIL"
    )

    for phrase in (
        "transport-neutral",
        "validated terminal",
        "fresh unpredictable",
        "DNS mapping is authoritative",
        "DID input",
        "participation readiness",
        "redirect count",
        "missing or invalid",
    ):
        assert phrase in doc

    for marker in (
        "_AIT-DID-ONLY",
        "_AIT-CNAME-HOP",
        "_AIT-CNAME-LOOP",
        "_AIT-LATE-MALFORMED-TXT",
        "_AIT-DID-ADMISSION-ORDER",
        "_AIT-HANDLE-HTTPS",
        "_AIT-POLICY",
        "_AIT-REDIRECT-BOUND",
        "ATPROTO IDENTITY PASS",
    ):
        assert marker in fixture

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = ["\\ autoexec.f - AT Protocol identity contracts\n", "ENTER-USERLAND\n"]
    for stage_name, module, marker, _ in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." ATPROTO IDENTITY LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_AIT-RUN\nTX-FLUSH\n")

    profile_name = "atproto-identity"
    image = Path("/tmp/akashic-atproto-identity.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("atproto/identity.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "ATPROTO IDENTITY FAIL",
            "ATPROTO IDENTITY ASSERT",
            "ATPROTO IDENTITY STACK",
            "ATPROTO IDENTITY LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/at-identity-test.f",
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
        for index, (stage_name, _, marker, stage_steps) in enumerate(
            LOAD_STAGES
        ):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=stage_steps,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (*harness._has_forth_error(raw), *harness._matched_failure_markers(
                        profile, raw, machine.screen_text()
                    ))
                )
            )
            reports.append((stage_name, report))
            if marker not in raw or failures:
                print(f"ATPROTO identity load {stage_name}: FAIL")
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-4000:])
                return 1

        machine.clear_output()
        machine.send_text("x")
        report = machine.run(
            max_steps=LIFECYCLE_MAX_STEPS,
            wall_timeout_s=timeout,
            until_text=PASS_MARKER,
            text_scope="raw",
        )
        raw = machine.raw_text()
        failures = tuple(
            dict.fromkeys(
                (*harness._has_forth_error(raw), *harness._matched_failure_markers(
                    profile, raw, machine.screen_text()
                ))
            )
        )
        ok = PASS_MARKER in raw and not failures
        print(f"ATPROTO identity lifecycle: {'PASS' if ok else 'FAIL'}")
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
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("ATPROTO IDENTITY STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
