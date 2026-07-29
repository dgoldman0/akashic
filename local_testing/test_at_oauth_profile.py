#!/usr/bin/env python3
"""Focused qualification for caller-owned AT Protocol OAuth profiles."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "at-oauth-profile-contracts"
IMAGE = Path("/tmp/akashic-at-oauth-profile-contracts.img")
CONTRACT = LOCAL_TESTING / "at-oauth-prof-test.f"
SOURCE = ROOT / "akashic" / "atproto" / "oauth-profile.f"

PASS_MARKER = "AT OAUTH PROFILE PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000
LOAD_STAGES = (
    (
        "memory-span",
        "utils/memory-span.f",
        "ATOP MEMORY SPAN READY",
        120_000_000,
    ),
    (
        "caller-span",
        "utils/caller-span.f",
        "ATOP CALLER SPAN READY",
        120_000_000,
    ),
    ("string", "utils/string.f", "ATOP STRING READY", 120_000_000),
    (
        "json-object",
        "security/jose/json-object.f",
        "ATOP JSON OBJECT READY",
        180_000_000,
    ),
    (
        "http-target",
        "net/http-target.f",
        "ATOP HTTP TARGET READY",
        120_000_000,
    ),
    ("did", "atproto/did.f", "ATOP DID READY", 120_000_000),
    ("handle", "atproto/handle.f", "ATOP HANDLE READY", 120_000_000),
    (
        "did-document",
        "atproto/did-document.f",
        "ATOP DID DOCUMENT READY",
        180_000_000,
    ),
    (
        "dns-txt",
        "net/dns-txt.f",
        "ATOP DNS TXT READY",
        180_000_000,
    ),
    (
        "identity-source",
        "atproto/identity.f",
        "ATOP IDENTITY READY",
        180_000_000,
    ),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATOP RESOURCE METADATA READY",
        180_000_000,
    ),
    (
        "as-metadata",
        "security/oauth2/metadata.f",
        "ATOP AS METADATA READY",
        180_000_000,
    ),
    (
        "oauth-profile",
        "atproto/oauth-profile.f",
        "ATOP SOURCE READY",
        180_000_000,
    ),
    (
        "fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATOP FIXTURE READY",
        180_000_000,
    ),
)
GROUP_STAGES = (
    (
        "identity",
        "_atopt-test-identity",
        "ATOP IDENTITY GROUP READY",
        180_000_000,
    ),
    (
        "exact-binding",
        "_atopt-test-exact-binding",
        "ATOP EXACT BINDING READY",
        180_000_000,
    ),
    (
        "happy",
        "_atopt-test-happy",
        "ATOP HAPPY READY",
        180_000_000,
    ),
    (
        "policy",
        "_atopt-test-policy",
        "ATOP POLICY READY",
        180_000_000,
    ),
    (
        "endpoints",
        "_atopt-test-endpoints",
        "ATOP ENDPOINTS READY",
        180_000_000,
    ),
    (
        "terminal",
        "_atopt-test-terminal",
        "ATOP TERMINAL READY",
        180_000_000,
    ),
    (
        "corruption",
        "_atopt-test-corruption",
        "ATOP CORRUPTION READY",
        120_000_000,
    ),
    (
        "ownership",
        "_atopt-test-ownership",
        "ATOP OWNERSHIP READY",
        180_000_000,
    ),
)


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
    fixture = CONTRACT.read_text(encoding="utf-8")
    forth_code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()

    stages = (*LOAD_STAGES, *GROUP_STAGES)
    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    assert all(
        0 < stage_steps <= MAX_PHASE_STEPS
        for _, _, _, stage_steps in stages
    )
    assert len({name for name, _, _, _ in stages}) == len(stages)
    assert len({marker for _, _, marker, _ in stages}) == len(stages)
    assert len(CONTRACT.name.encode("utf-8")) <= 23

    assert _requires(SOURCE) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../net/http-target.f",
        "../security/oauth2/resource-metadata.f",
        "../security/oauth2/metadata.f",
        "did.f",
        "identity.f",
    ]
    assert "PROVIDED akashic-at-oauth-prof" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "OAuth profile composition must use caller-owned mutable storage"
    for forbidden in (
        "streams",
        "session.f",
        "xrpc",
        "hres-",
        "tcp-",
        "udp-",
        "kdos-tls",
    ):
        assert forbidden not in forth_code

    public_words = (
        "AT-OAUTH-PROFILE-SIZE",
        "AT-OAUTH-PROFILE-STATUS-VALID?",
        "AT-OAUTH-PROFILE-PHASE-VALID?",
        "AT-OAUTH-PROFILE-INIT",
        "AT-OAUTH-PROFILE-WIPE",
        "AT-OAUTH-PROFILE-VALID?",
        "AT-OAUTH-PROFILE-READY?",
        "AT-OAUTH-PROFILE-BEGIN",
        "AT-OAUTH-PROFILE-RESOURCE!",
        "AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!",
        "AT-OAUTH-PROFILE-PHASE@",
        "AT-OAUTH-PROFILE-STATUS@",
        "AT-OAUTH-PROFILE-DID@",
        "AT-OAUTH-PROFILE-RESOURCE@",
        "AT-OAUTH-PROFILE-PDS-TARGET@",
        "AT-OAUTH-PROFILE-RESOURCE-METADATA-TARGET@",
        "AT-OAUTH-PROFILE-ISSUER@",
        "AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-TARGET@",
        "AT-OAUTH-PROFILE-AUTHORIZATION-SERVER-METADATA-TARGET@",
        "AT-OAUTH-PROFILE-AUTHORIZATION-TARGET@",
        "AT-OAUTH-PROFILE-TOKEN-TARGET@",
        "AT-OAUTH-PROFILE-PAR-TARGET@",
    )
    for word in public_words:
        assert word in source

    assert "ATID-RESULT-READY?" in source
    assert "ATID-PARTICIPATION-READY?" not in source
    assert "OAUTH2-RESOURCE-METADATA-VALID?" in source
    assert "OAUTH2-METADATA-VALID?" in source
    assert "HTARGET-PARSE" in source
    assert "HTARGET-SAME-ORIGIN?" in source
    assert "_ATOP-TARGET-CHECKED?" in source
    assert "_ATOP-FIXED-STATUS" in source

    for private_prefix in (
        "_ATOP.",
        "_ATIDR.",
        "_ATIDW.",
        "_ATDD.",
        "_O2RM.",
        "_O2MD.",
    ):
        assert private_prefix not in fixture

    fixture_markers = (
        "_atopt-test-identity",
        "_atopt-test-exact-binding",
        "_atopt-test-happy",
        "_atopt-test-policy",
        "_atopt-test-endpoints",
        "_atopt-test-terminal",
        "_atopt-test-corruption",
        "_atopt-test-ownership",
        "AT OAUTH PROFILE PASS",
    )
    for marker in fixture_markers:
        assert marker in fixture

    for required_case in (
        "ATID-PARTICIPATION-READY?",
        "https://pds.example",
        "https://pds.example/",
        "https://auth.example",
        "https://auth.example/",
        "require_request_uri_registration",
        'S" none"',
        "http://login.example/authorize",
        "https://tokens.example/exchange",
        "AT-OAUTH-PROFILE-S-ALIAS",
        "AT-OAUTH-PROFILE-S-INVALID",
        "AT-OAUTH-PROFILE-PHASE-FAILED",
        "HTARGET.REDIRECT-COUNT",
    ):
        assert required_case in fixture

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - staged AT OAuth profile contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker, _ in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH PROFILE LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOPT-INIT\n")
    for _, word, marker, _ in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOPT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/oauth-profile.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT OAUTH PROFILE FAIL",
            "AT OAUTH PROFILE ASSERT",
            "AT OAUTH PROFILE STATUS",
            "AT OAUTH PROFILE STACK",
            "AT OAUTH PROFILE LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/at-oauth-prof-test.f",
                harness._minify_forth(
                    CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=8192,
    )
    image_path = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    reports: list[tuple[str, object]] = []

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
        stages = (*LOAD_STAGES, *GROUP_STAGES)
        for index, (stage_name, _, marker, stage_steps) in enumerate(stages):
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
                print(f"AT OAuth profile {stage_name}: FAIL")
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-4000:])
                return 1

        machine.clear_output()
        machine.send_text("x")
        report = machine.run(
            max_steps=FINISH_STEPS,
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
        print(f"AT OAuth profile lifecycle: {'PASS' if ok else 'FAIL'}")
        for stage_name, stage_report in reports:
            print(
                f"  {stage_name}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        print(
            f"  finish: {report.steps:,} steps in "
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
    mode.add_argument(
        "--static-only",
        action="store_true",
        help="check source and fixture contracts without running a VM",
    )
    mode.add_argument(
        "--lifecycle",
        action="store_true",
        help="run the staged deterministic guest contracts",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("AT OAUTH PROFILE STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
