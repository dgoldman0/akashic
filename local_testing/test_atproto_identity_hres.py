#!/usr/bin/env python3
"""Qualify AT identity composition over generic caller-owned HTTPS resources."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "atproto" / "identity-hres.f"
IDENTITY = ROOT / "akashic" / "atproto" / "identity.f"
HRES = ROOT / "akashic" / "net" / "http-resource.f"
DOC = ROOT / "docs" / "atproto" / "identity-http-resource.md"
HRES_CONTRACT = LOCAL_TESTING / "hres-contracts.f"
CONTRACT = LOCAL_TESTING / "at-identity-hres-test.f"

PASS_MARKER = "AT IDENTITY HRES PASS"
MAX_PHASE_STEPS = 180_000_000
LIFECYCLE_MAX_STEPS = 180_000_000
LOAD_STAGES = (
    ("event", "concurrency/event.f", "AIHR EVENT READY", 120_000_000),
    (
        "semaphore",
        "concurrency/semaphore.f",
        "AIHR SEMAPHORE READY",
        120_000_000,
    ),
    ("guard", "concurrency/guard.f", "AIHR GUARD READY", 120_000_000),
    ("string", "utils/string.f", "AIHR STRING READY", 120_000_000),
    (
        "memory-span",
        "utils/memory-span.f",
        "AIHR MEMORY SPAN READY",
        120_000_000,
    ),
    (
        "caller-span",
        "utils/caller-span.f",
        "AIHR CALLER SPAN READY",
        120_000_000,
    ),
    ("io-port", "net/io-port.f", "AIHR IO PORT READY", 120_000_000),
    (
        "external-io",
        "net/external-io.f",
        "AIHR EXTERNAL IO READY",
        120_000_000,
    ),
    (
        "http-request",
        "net/http-request.f",
        "AIHR HTTP REQUEST READY",
        120_000_000,
    ),
    (
        "http-stream",
        "net/http-stream.f",
        "AIHR HTTP STREAM READY",
        120_000_000,
    ),
    (
        "http-buffered",
        "net/http-buffered.f",
        "AIHR HTTP BUFFERED READY",
        120_000_000,
    ),
    (
        "http-target",
        "net/http-target.f",
        "AIHR HTTP TARGET READY",
        120_000_000,
    ),
    (
        "media-type",
        "net/media-type.f",
        "AIHR MEDIA TYPE READY",
        120_000_000,
    ),
    (
        "json-object",
        "security/jose/json-object.f",
        "AIHR JSON OBJECT READY",
        180_000_000,
    ),
    ("did", "atproto/did.f", "AIHR DID READY", 120_000_000),
    ("handle", "atproto/handle.f", "AIHR HANDLE READY", 120_000_000),
    (
        "did-document",
        "atproto/did-document.f",
        "AIHR DID DOCUMENT READY",
        180_000_000,
    ),
    ("dns-txt", "net/dns-txt.f", "AIHR DNS TXT READY", 180_000_000),
    (
        "identity",
        "atproto/identity.f",
        "AIHR IDENTITY READY",
        180_000_000,
    ),
    (
        "http-resource",
        "net/http-resource.f",
        "AIHR HTTP RESOURCE READY",
        120_000_000,
    ),
    (
        "adapter",
        "atproto/identity-hres.f",
        "AIHR ADAPTER READY",
        120_000_000,
    ),
    (
        "hres-fixture",
        "local_testing/hres-contracts.f",
        "AIHR HRES FIXTURE READY",
        120_000_000,
    ),
    (
        "fixture",
        "local_testing/at-identity-hres-test.f",
        "AIHR FIXTURE READY",
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
                "parenthesized comments must close on their physical line: "
                f"{path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    identity = IDENTITY.read_text(encoding="utf-8")
    hres = HRES.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    hres_contract = HRES_CONTRACT.read_text(encoding="utf-8")
    contract = CONTRACT.read_text(encoding="utf-8")
    forth_code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()

    assert 0 < LIFECYCLE_MAX_STEPS <= MAX_PHASE_STEPS
    assert all(
        0 < stage_steps <= MAX_PHASE_STEPS
        for _, _, _, stage_steps in LOAD_STAGES
    )
    assert len({name for name, _, _, _ in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({marker for _, _, marker, _ in LOAD_STAGES}) == len(LOAD_STAGES)

    assert _requires(SOURCE) == ["../net/http-resource.f", "identity.f"]
    assert "PROVIDED akashic-atid-hres" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "identity HTTP adapter owns mutable module state"
    for forbidden in ("streams", "oauth", "kdos", "tcp-", "udp-"):
        assert forbidden not in forth_code
    assert "hres-" not in "\n".join(
        line.split("\\", 1)[0] for line in identity.splitlines()
    ).lower()

    policy = _word_body(source, "ATID-HRES-SPEC-POLICY!")
    for word in (
        "HRES-SPEC-SUCCESS-RANGE!",
        "HRES-SPEC-MEDIA-MODE!",
        "HRES-SPEC-REDIRECT-MAX!",
        "HRES-SPEC-REDIRECT-AUTHORITY!",
    ):
        assert word in policy
    assert "200 299" in policy
    assert "HRES-MEDIA-IGNORED" in policy
    authority = _word_body(source, "_ATID-HRES-REDIRECT-AUTHORITY")
    assert authority.count("HTARGET-PORT@") == 2
    assert "443" in authority
    response = _word_body(source, "ATID-HRES-RESPONSE!")
    for word in (
        "ATID-HTTP-TARGET@",
        "HRES-RESULT-VALID?",
        "HRES-REQUESTED-TARGET",
        "HTARGET-EQUAL?",
        "HRES-BODY@",
        "HRES-HTTP-STATUS@",
        "HRES-REDIRECT-COUNT@",
        "HRES-EFFECTIVE-TARGET",
        "ATID-HTTP-RESPONSE!",
    ):
        assert word in response
    assert re.search(
        r"(?s)HRES-BODY@\s+R@\s+HRES-HTTP-STATUS@\s+"
        r"R@\s+HRES-REDIRECT-COUNT@\s+R@\s+"
        r"HRES-EFFECTIVE-TARGET\s+R>\s+DROP\s+R>\s+"
        r"ATID-HTTP-RESPONSE!",
        response,
    )

    assert "PROVIDED akashic-http-resource" in hres
    assert "2048 CONSTANT _HRC-BODY-CAP" in hres_contract
    for marker in (
        "_AIHR-TEST-PARTICIPATION",
        "_AIHR-TEST-NONDEFAULT-PORT",
        "_AIHR-TEST-REQUEST-BINDING",
        "https://identity.example.com/value",
        "https://other.example.com:8443/document",
        "AT IDENTITY HRES PASS",
    ):
        assert marker in contract
    for phrase in (
        "state-free",
        "200 through 299",
        "Content-Type",
        "default HTTPS port 443",
        "current exact HTTP action target",
        "public-address policy",
        "cannot inspect",
        "first exact",
        "ATID-S-HTTP",
    ):
        assert phrase in doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, contract)


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - staged AT identity HTTP-resource contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker, _ in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT IDENTITY HRES LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_AIHR-RUN\nTX-FLUSH\n")

    profile_name = "atproto-identity-hres"
    image = Path("/tmp/akashic-atproto-identity-hres.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("atproto/identity-hres.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT IDENTITY HRES FAIL",
            "AT IDENTITY HRES ASSERT",
            "AT IDENTITY HRES STACK",
            "AT IDENTITY HRES LOAD STACK FAIL",
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
                    HRES_CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/at-identity-hres-test.f",
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
                print(f"AT identity HRES load {stage_name}: FAIL")
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
                (
                    *harness._has_forth_error(raw),
                    *harness._matched_failure_markers(
                        profile, raw, machine.screen_text()
                    ),
                )
            )
        )
        ok = PASS_MARKER in raw and not failures
        print(f"AT identity HRES lifecycle: {'PASS' if ok else 'FAIL'}")
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
        print("AT IDENTITY HRES STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
