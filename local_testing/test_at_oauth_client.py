#!/usr/bin/env python3
"""Qualify AT Protocol policy over generic OAuth client configuration."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "at-oauth-client-contracts"
IMAGE = Path("/tmp/akashic-at-oauth-client-contracts.img")
SOURCE = ROOT / "akashic" / "atproto" / "oauth-client.f"
DOC = ROOT / "docs" / "atproto" / "oauth-client.md"
PROFILE_CONTRACT = LOCAL_TESTING / "at-oauth-prof-test.f"
CONTRACT = LOCAL_TESTING / "at-oauth-client-test.f"

PASS_MARKER = "AT OAUTH CLIENT PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

LOAD_STAGES = (
    (
        "memory-span",
        "utils/memory-span.f",
        "ATOC MEMORY SPAN READY",
        120_000_000,
    ),
    (
        "caller-span",
        "utils/caller-span.f",
        "ATOC CALLER SPAN READY",
        120_000_000,
    ),
    (
        "client-config",
        "security/oauth2/client-config.f",
        "ATOC CLIENT CONFIG READY",
        180_000_000,
    ),
    ("string", "utils/string.f", "ATOC STRING READY", 120_000_000),
    (
        "json-object",
        "security/jose/json-object.f",
        "ATOC JSON OBJECT READY",
        180_000_000,
    ),
    (
        "http-target",
        "net/http-target.f",
        "ATOC HTTP TARGET READY",
        120_000_000,
    ),
    ("did", "atproto/did.f", "ATOC DID READY", 120_000_000),
    ("handle", "atproto/handle.f", "ATOC HANDLE READY", 120_000_000),
    (
        "did-document",
        "atproto/did-document.f",
        "ATOC DID DOCUMENT READY",
        180_000_000,
    ),
    ("dns-txt", "net/dns-txt.f", "ATOC DNS TXT READY", 180_000_000),
    (
        "identity",
        "atproto/identity.f",
        "ATOC IDENTITY READY",
        180_000_000,
    ),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATOC RESOURCE METADATA READY",
        180_000_000,
    ),
    (
        "as-metadata",
        "security/oauth2/metadata.f",
        "ATOC AS METADATA READY",
        180_000_000,
    ),
    (
        "oauth-profile",
        "atproto/oauth-profile.f",
        "ATOC PROFILE READY",
        180_000_000,
    ),
    (
        "oauth-client",
        "atproto/oauth-client.f",
        "ATOC SOURCE READY",
        180_000_000,
    ),
    (
        "profile-fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATOC PROFILE FIXTURE READY",
        180_000_000,
    ),
    (
        "client-fixture",
        "local_testing/at-oauth-client-test.f",
        "ATOC FIXTURE READY",
        180_000_000,
    ),
)

GROUP_STAGES = (
    (
        "happy",
        "_atoct-test-happy",
        "ATOC HAPPY GROUP READY",
        180_000_000,
    ),
    (
        "client-id-positive",
        "_atoct-test-client-id-positive",
        "ATOC CLIENT ID POSITIVE READY",
        180_000_000,
    ),
    (
        "client-id-form",
        "_atoct-test-client-id-form",
        "ATOC CLIENT ID FORM READY",
        180_000_000,
    ),
    (
        "client-id-dots",
        "_atoct-test-client-id-dots",
        "ATOC CLIENT ID DOTS READY",
        180_000_000,
    ),
    (
        "client-id-host",
        "_atoct-test-client-id-host",
        "ATOC CLIENT ID HOST READY",
        180_000_000,
    ),
    (
        "redirect-web-form",
        "_atoct-test-redirect-web-form",
        "ATOC REDIRECT WEB FORM READY",
        180_000_000,
    ),
    (
        "redirect-web-port",
        "_atoct-test-redirect-web-port",
        "ATOC REDIRECT WEB PORT READY",
        180_000_000,
    ),
    (
        "redirect-native-custom",
        "_atoct-test-redirect-native-custom",
        "ATOC REDIRECT NATIVE CUSTOM READY",
        180_000_000,
    ),
    (
        "redirect-native-https",
        "_atoct-test-redirect-native-https",
        "ATOC REDIRECT NATIVE HTTPS READY",
        180_000_000,
    ),
    (
        "scope",
        "_atoct-test-scope",
        "ATOC SCOPE GROUP READY",
        180_000_000,
    ),
    (
        "auth",
        "_atoct-test-auth",
        "ATOC AUTH GROUP READY",
        180_000_000,
    ),
    (
        "api-geometry",
        "_atoct-test-api-geometry",
        "ATOC API GEOMETRY READY",
        180_000_000,
    ),
    (
        "readiness-precedence",
        "_atoct-test-readiness-precedence",
        "ATOC READINESS PRECEDENCE READY",
        180_000_000,
    ),
    (
        "ownership",
        "_atoct-test-ownership",
        "ATOC OWNERSHIP GROUP READY",
        180_000_000,
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
        code = code.replace("[CHAR] (", "")
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    profile_fixture = PROFILE_CONTRACT.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
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
    assert len(PROFILE_CONTRACT.name.encode("utf-8")) <= 23

    assert _requires(SOURCE) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../security/oauth2/client-config.f",
        "oauth-profile.f",
    ]
    assert "PROVIDED akashic-at-oauth-client" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "AT client policy must own no mutable module state"
    for forbidden in (
        "streams",
        "xrpc",
        "hres-",
        "http-resource",
        "json-",
        "private-key",
        "credential-vault",
        "browser",
    ):
        assert forbidden not in forth_code

    for word in (
        "AT-OAUTH-CLIENT-WORKSPACE-SIZE",
        "AT-OAUTH-CLIENT-WORKSPACE-CLEAR",
        "AT-OAUTH-CLIENT-STATUS-VALID?",
        "AT-OAUTH-CLIENT-ADMIT",
        "AT-OAUTH-CLIENT-S-OK",
        "AT-OAUTH-CLIENT-S-ALIAS",
        "AT-OAUTH-CLIENT-S-CONFIG",
        "AT-OAUTH-CLIENT-S-PROFILE",
        "AT-OAUTH-CLIENT-S-CLIENT-ID",
        "AT-OAUTH-CLIENT-S-REDIRECT",
        "AT-OAUTH-CLIENT-S-SCOPE",
        "AT-OAUTH-CLIENT-S-AUTH-METHOD",
        "AT-OAUTH-CLIENT-S-AUTH-ALGORITHM",
        "AT-OAUTH-CLIENT-S-DPOP",
        "AT-OAUTH-CLIENT-S-PLATFORM",
    ):
        assert word in source

    assert re.search(
        r"(?m)^432 CONSTANT AT-OAUTH-CLIENT-WORKSPACE-SIZE$",
        source,
    )
    geometry = _word_body(source, "_ATOC-GEOMETRY")
    assert geometry.count("MSPAN-OVERLAP?") == 2
    assert "OAUTH2-CLIENT-CONFIG-VALID?" in geometry
    assert "AT-OAUTH-PROFILE-READY?" in geometry

    binding = _word_body(source, "_ATOC-BIND")
    for accessor in (
        "OAUTH2-CLIENT-CONFIG-CLIENT-ID@",
        "OAUTH2-CLIENT-CONFIG-REDIRECT-URI@",
        "OAUTH2-CLIENT-CONFIG-APPLICATION-TYPE@",
    ):
        assert accessor in binding

    assert "OAUTH2-CLIENT-CONFIG-SCOPE@" in source
    assert "OAUTH2-CLIENT-CONFIG-AUTH-METHOD@" in source
    assert "OAUTH2-CLIENT-CONFIG-AUTH-ALGORITHM@" in source
    assert "OAUTH2-CLIENT-CONFIG-DPOP-BOUND?" in source
    assert "CATCH" in _word_body(source, "_ATOC-ADMIT-CALL")
    assert "_ATOC-WIPE-WORKSPACE" in _word_body(
        source, "_ATOC-FINISH"
    )
    public_admit = _word_body(source, "AT-OAUTH-CLIENT-ADMIT")
    assert public_admit.index("_ATOC-GEOMETRY") < public_admit.index(
        "_ATOC-ADMIT-CALL"
    )

    assert "PROVIDED at-oauth-prof-test" in profile_fixture
    assert "PROVIDED at-oauth-client-test" in fixture
    for _, group_word, _, _ in GROUP_STAGES:
        assert group_word in fixture
    for marker in (
        "AT OAUTH CLIENT PASS",
        "HTTPS://CLIENT.EXAMPLE/?tenant=1",
        "client%2Ejson",
        "0x7f000001",
        "com.example.app:/oauth/callback?slot=1",
        "transition:generic atproto repo:write",
        "client_secret_basic",
        "private_key_jwt",
        "RS256",
        "AT-OAUTH-CLIENT-S-AUTH-ALGORITHM",
        "AT-OAUTH-CLIENT-S-ALIAS",
        "_atoct-work-zero?",
        "_atoct-inputs-unchanged?",
    ):
        assert marker in fixture
    assert not re.search(
        r"(?i)\b(?:_ATOC-(?!ADMIT-CALL\b)|_ATOCW[.-])",
        "\n".join(
            line.split("\\", 1)[0] for line in fixture.splitlines()
        ),
    ), "fixture must use public production APIs"
    assert fixture.count("_ATOC-ADMIT-CALL") == 1

    for marker in (
        "AT-OAUTH-CLIENT-ADMIT",
        "caller-owned",
        "deployment",
        "client_id",
        "redirect_uri",
        "dpop_bound_access_tokens",
        "private_key_jwt",
        "ES256",
        "http://localhost",
    ):
        assert marker in doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - staged AT OAuth client contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker, _ in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH CLIENT LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOCT-INIT\n")
    for _, word, marker, _ in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOCT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/oauth-client.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT OAUTH CLIENT FAIL",
            "AT OAUTH CLIENT ASSERT",
            "AT OAUTH CLIENT STATUS",
            "AT OAUTH CLIENT STACK",
            "AT OAUTH CLIENT LOAD STACK FAIL",
            "AT OAUTH PROFILE ASSERT",
            "AT OAUTH PROFILE STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                f"local_testing/{PROFILE_CONTRACT.name}",
                harness._minify_forth(
                    PROFILE_CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                f"local_testing/{CONTRACT.name}",
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
                print(f"AT OAuth client {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
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
        print(f"AT OAuth client lifecycle: {'PASS' if ok else 'FAIL'}")
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
        help="check source, documentation, and fixture contracts",
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
        print("AT OAUTH CLIENT STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
