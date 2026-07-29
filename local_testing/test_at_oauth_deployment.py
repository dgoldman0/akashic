#!/usr/bin/env python3
"""Focused static and staged qualification for AT OAuth deployments."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "at-oauth-deployment-contracts"
IMAGE = Path("/tmp/akashic-at-oauth-deployment-contracts.img")
SOURCE = ROOT / "akashic" / "atproto" / "oauth-deployment.f"
DOC = ROOT / "docs" / "atproto" / "oauth-deployment.md"
INDEX_DOC = ROOT / "docs" / "atproto" / "atproto.md"
PROFILE_CONTRACT = LOCAL_TESTING / "at-oauth-prof-test.f"
CONTRACT = LOCAL_TESTING / "at-oauth-deploy-test.f"

PASS_MARKER = "AT OAUTH DEPLOYMENT PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

LOAD_STAGES = (
    ("memory-span", "utils/memory-span.f", "ATOD MEMORY SPAN READY"),
    ("caller-span", "utils/caller-span.f", "ATOD CALLER SPAN READY"),
    (
        "client-config",
        "security/oauth2/client-config.f",
        "ATOD CLIENT CONFIG READY",
    ),
    ("string", "utils/string.f", "ATOD STRING READY"),
    (
        "json-object",
        "security/jose/json-object.f",
        "ATOD JSON OBJECT READY",
    ),
    (
        "client-metadata",
        "security/oauth2/client-metadata.f",
        "ATOD CLIENT METADATA READY",
    ),
    ("http-target", "net/http-target.f", "ATOD HTTP TARGET READY"),
    ("did", "atproto/did.f", "ATOD DID READY"),
    ("handle", "atproto/handle.f", "ATOD HANDLE READY"),
    (
        "did-document",
        "atproto/did-document.f",
        "ATOD DID DOCUMENT READY",
    ),
    ("dns-txt", "net/dns-txt.f", "ATOD DNS TXT READY"),
    ("identity", "atproto/identity.f", "ATOD IDENTITY READY"),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATOD RESOURCE METADATA READY",
    ),
    (
        "as-metadata",
        "security/oauth2/metadata.f",
        "ATOD AS METADATA READY",
    ),
    ("oauth-profile", "atproto/oauth-profile.f", "ATOD PROFILE READY"),
    ("oauth-client", "atproto/oauth-client.f", "ATOD CLIENT READY"),
    (
        "oauth-deployment",
        "atproto/oauth-deployment.f",
        "ATOD SOURCE READY",
    ),
    (
        "profile-fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATOD PROFILE FIXTURE READY",
    ),
    (
        "deployment-fixture",
        "local_testing/at-oauth-deploy-test.f",
        "ATOD FIXTURE READY",
    ),
)

GROUP_STAGES = (
    ("statuses", "_atodt-test-statuses", "ATOD STATUSES READY"),
    ("successes", "_atodt-test-successes", "ATOD SUCCESSES READY"),
    (
        "client-application",
        "_atodt-test-client-application",
        "ATOD CLIENT APPLICATION READY",
    ),
    (
        "grants-responses",
        "_atodt-test-grants-responses",
        "ATOD GRANTS RESPONSES READY",
    ),
    (
        "redirects-scope",
        "_atodt-test-redirects-scope",
        "ATOD REDIRECTS SCOPE READY",
    ),
    (
        "auth-dpop-keys",
        "_atodt-test-auth-dpop-keys",
        "ATOD AUTH DPOP KEYS READY",
    ),
    (
        "precedence",
        "_atodt-test-precedence",
        "ATOD PRECEDENCE READY",
    ),
    ("callbacks", "_atodt-test-callbacks", "ATOD CALLBACKS READY"),
    (
        "preflight-ownership",
        "_atodt-test-preflight-ownership",
        "ATOD PREFLIGHT OWNERSHIP READY",
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


def _forth_code(source: str) -> str:
    return "\n".join(line.split("\\", 1)[0] for line in source.splitlines())


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
    profile_fixture = PROFILE_CONTRACT.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    index_doc = INDEX_DOC.read_text(encoding="utf-8")
    fixture_code = _forth_code(fixture)

    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    assert len({name for name, _, _ in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({name for name, _, _ in GROUP_STAGES}) == len(GROUP_STAGES)
    markers = tuple(
        marker for _, _, marker in (*LOAD_STAGES, *GROUP_STAGES)
    )
    assert len(set(markers)) == len(markers)
    assert len(CONTRACT.name.encode("utf-8")) <= 23
    assert len(PROFILE_CONTRACT.name.encode("utf-8")) <= 23

    assert "PROVIDED akashic-at-oauth-deployment" in source
    assert _requires(SOURCE) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../security/oauth2/client-config.f",
        "../security/oauth2/client-metadata.f",
        "oauth-profile.f",
        "oauth-client.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "deployment binding must retain no module-owned mutable state"

    for word in (
        "AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE",
        "AT-OAUTH-DEPLOYMENT-WORKSPACE-CLEAR",
        "AT-OAUTH-DEPLOYMENT-STATUS-VALID?",
        "AT-OAUTH-DEPLOYMENT-WITH",
        "AT-OAUTH-CLIENT-VIEW-ADMIT",
        "AT-OAUTH-CLIENT-VIEW-REDIRECT-ADMIT",
        "OAUTH2-CLIENT-CONFIG-WITH",
        "OAUTH2-CLIENT-METADATA-WITH",
    ):
        assert word in source
    policy = _word_body(source, "_ATOD-POLICY")
    policy_order = (
        "_ATOD-CLIENT-ID-POLICY",
        "_ATOD-APPLICATION-POLICY",
        "_ATOD-GRANT-POLICY",
        "_ATOD-RESPONSE-POLICY",
        "_ATOD-REDIRECT-POLICY",
        "_ATOD-SCOPE-POLICY",
        "_ATOD-AUTH-METHOD-POLICY",
        "_ATOD-AUTH-ALGORITHM-POLICY",
        "_ATOD-DPOP-POLICY",
        "_ATOD-KEY-SOURCE-POLICY",
    )
    assert [policy.index(word) for word in policy_order] == sorted(
        policy.index(word) for word in policy_order
    )
    for status in (
        "OK",
        "INVALID",
        "CAPACITY",
        "ALIAS",
        "CONFIG",
        "PROFILE",
        "METADATA",
        "CLIENT-ID",
        "APPLICATION",
        "GRANT",
        "RESPONSE",
        "REDIRECT",
        "SCOPE",
        "AUTH-METHOD",
        "AUTH-ALGORITHM",
        "DPOP",
        "KEY-SOURCE",
        "CALLBACK",
        "INTERNAL",
        "RANGE",
        "PROTECTED",
        "PLATFORM",
    ):
        assert f"AT-OAUTH-DEPLOYMENT-S-{status}" in source
    assert re.search(
        r"(?m)^AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE 53760 <> \[IF\]$",
        source,
    )

    assert "PROVIDED at-oauth-prof-test" in profile_fixture
    assert "PROVIDED at-oauth-deploy-test" in fixture
    assert "_ATOPT-INIT" in fixture
    assert "_atopt-build-identity" in fixture
    assert "_atopt-profile-ready" in fixture

    groups = (
        "_atodt-test-statuses",
        "_atodt-test-successes",
        "_atodt-test-client-application",
        "_atodt-test-grants-responses",
        "_atodt-test-redirects-scope",
        "_atodt-test-auth-dpop-keys",
        "_atodt-test-precedence",
        "_atodt-test-callbacks",
        "_atodt-test-preflight-ownership",
    )
    run_body = _word_body(fixture, "_ATODT-RUN")
    for group in groups:
        assert group in fixture
        assert group in run_body

    for marker in (
        "AT OAUTH DEPLOYMENT PASS",
        "https://app.example.com/oauth/client-metadata.json",
        "com.example.app:/oauth/callback",
        "https://client.example/oauth/client-metadata.json",
        "private_key_jwt",
        "https://client.example/oauth/jwks.json",
        "repo:write atproto",
        "atproto transition:generic repo:write",
        "AT-OAUTH-DEPLOYMENT-S-CLIENT-ID",
        "AT-OAUTH-DEPLOYMENT-S-APPLICATION",
        "AT-OAUTH-DEPLOYMENT-S-GRANT",
        "AT-OAUTH-DEPLOYMENT-S-RESPONSE",
        "AT-OAUTH-DEPLOYMENT-S-REDIRECT",
        "AT-OAUTH-DEPLOYMENT-S-SCOPE",
        "AT-OAUTH-DEPLOYMENT-S-AUTH-METHOD",
        "AT-OAUTH-DEPLOYMENT-S-AUTH-ALGORITHM",
        "AT-OAUTH-DEPLOYMENT-S-DPOP",
        "AT-OAUTH-DEPLOYMENT-S-KEY-SOURCE",
        "AT-OAUTH-DEPLOYMENT-S-METADATA",
        "_atodt-callback-throw",
        "_atodt-callback-extra",
        "_atodt-callback-missing",
        "_atodt-callback-overconsume",
        "_atodt-saved-view-invalid",
        "_atodt-inputs-unchanged?",
        "_atodt-work-zero?",
        "_atodt-work-wiped-canary?",
        "_atodt-all-work-filled?",
        "3 _atodt-redirect-mode !",
        "OAUTH2-CLIENT-METADATA-MAX-DOCUMENT-BYTES 1+",
        "_atodt-config 1+",
        "_atopt-profile 1+",
        "_atodt-work 1+",
        "0 _atodt-config !",
        "0 _atopt-profile !",
    ):
        assert marker in fixture

    private_tokens = set(
        re.findall(
            r"(?<![A-Za-z0-9-])_[A-Za-z0-9.-]+",
            fixture_code,
        )
    )
    assert all(
        token.lower().startswith(("_atodt", "_atopt"))
        for token in private_tokens
    ), "fixture must not call private production words"
    assert not re.search(
        r"(?i)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture_code
    ), "fixture cursor walks must not borrow the DO-loop return stack"

    for marker in (
        "AT-OAUTH-DEPLOYMENT-WITH",
        "53,760",
        "byte-for-byte",
        "application_type",
        "authorization_code",
        "private_key_jwt",
        "dpop_bound_access_tokens",
        "checked JWK",
        "HTTP provenance",
        "callback-scoped",
    ):
        assert marker in doc
    for marker in (
        "REQUIRE oauth-deployment.f",
        "akashic-at-oauth-deployment",
        "oauth-deployment.md",
        "53,760",
    ):
        assert marker in index_doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - staged AT OAuth deployment contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH DEPLOYMENT LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATODT-INIT\n")
    for _, word, marker in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATODT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/oauth-deployment.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT OAUTH DEPLOYMENT FAIL",
            "AT OAUTH DEPLOYMENT ASSERT",
            "AT OAUTH DEPLOYMENT STATUS",
            "AT OAUTH DEPLOYMENT STACK",
            "AT OAUTH DEPLOYMENT LOAD STACK FAIL",
            "AT OAUTH PROFILE FAIL",
            "AT OAUTH PROFILE ASSERT",
            "AT OAUTH PROFILE STATUS",
            "DRIVER THROW",
            "Branch offset overflow",
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
    image = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    reports: list[tuple[str, object]] = []

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        stages = (*LOAD_STAGES, *GROUP_STAGES)
        for index, (stage_name, _, marker) in enumerate(stages):
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
                print(f"AT OAuth deployment {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-4000:])
                return 1
            print(
                f"AT OAuth deployment {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )

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
        print(f"AT OAuth deployment lifecycle: {'PASS' if ok else 'FAIL'}")
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
        help="check source and fixture contracts without building a guest",
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
        print("AT OAUTH DEPLOYMENT STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
