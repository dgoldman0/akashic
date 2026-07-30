#!/usr/bin/env python3
"""Focused qualification for acquired confidential inline AT OAuth metadata."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from test_at_oauth_inline import SEAM_DOUBLES, _packed  # noqa: E402


SOURCE = ROOT / "akashic" / "atproto" / "oauth-inline-hres.f"
SHARED_SOURCE = ROOT / "akashic" / "atproto" / "oauth-hres.f"
INLINE_SOURCE = ROOT / "akashic" / "atproto" / "oauth-deployment-inline.f"
HRES_FIXTURE = LOCAL_TESTING / "hres-contracts.f"
PROFILE_FIXTURE = LOCAL_TESTING / "at-oauth-prof-test.f"
DEPLOYMENT_FIXTURE = LOCAL_TESTING / "at-oauth-deploy-test.f"
INLINE_FIXTURE = LOCAL_TESTING / "at-oauth-inline-test.f"
FIXTURE = LOCAL_TESTING / "at-oauth-inline-hres-test.f"

PROFILE = "at-oauth-inline-hres"
IMAGE = Path("/tmp/akashic-at-oauth-inline-hres.img")
PASS_MARKER = "AT OAUTH INLINE HRES PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

# Staging remains sequential.  The long dependency list keeps every checked-in
# phase below the existing ceiling while the behavior matrix stays deliberately
# limited to the vertical-slice gates.
LOAD_STAGES = (
    ("event", "concurrency/event.f", "ATOIH EVENT READY"),
    ("semaphore", "concurrency/semaphore.f", "ATOIH SEMAPHORE READY"),
    ("guard", "concurrency/guard.f", "ATOIH GUARD READY"),
    ("string", "utils/string.f", "ATOIH STRING READY"),
    ("memory-span", "utils/memory-span.f", "ATOIH MEMORY READY"),
    ("caller-span", "utils/caller-span.f", "ATOIH CALLER READY"),
    ("io-port", "net/io-port.f", "ATOIH IO PORT READY"),
    ("external-io", "net/external-io.f", "ATOIH EXTERNAL IO READY"),
    ("http-request", "net/http-request.f", "ATOIH HTTP REQUEST READY"),
    ("http-stream", "net/http-stream.f", "ATOIH HTTP STREAM READY"),
    ("http-buffered", "net/http-buffered.f", "ATOIH HTTP BUFFERED READY"),
    ("http-target", "net/http-target.f", "ATOIH HTTP TARGET READY"),
    ("media-type", "net/media-type.f", "ATOIH MEDIA READY"),
    ("http-resource", "net/http-resource.f", "ATOIH HTTP RESOURCE READY"),
    (
        "client-config",
        "security/oauth2/client-config.f",
        "ATOIH CONFIG READY",
    ),
    ("json-object", "security/jose/json-object.f", "ATOIH JSON READY"),
    (
        "client-metadata",
        "security/oauth2/client-metadata.f",
        "ATOIH CLIENT META READY",
    ),
    ("did", "atproto/did.f", "ATOIH DID READY"),
    ("handle", "atproto/handle.f", "ATOIH HANDLE READY"),
    ("did-document", "atproto/did-document.f", "ATOIH DID DOC READY"),
    ("dns-txt", "net/dns-txt.f", "ATOIH DNS READY"),
    ("identity", "atproto/identity.f", "ATOIH IDENTITY READY"),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATOIH RMETA READY",
    ),
    ("oauth-metadata", "security/oauth2/metadata.f", "ATOIH META READY"),
    ("oauth-profile", "atproto/oauth-profile.f", "ATOIH PROFILE READY"),
    ("oauth-client", "atproto/oauth-client.f", "ATOIH CLIENT READY"),
    ("deployment", "atproto/oauth-deployment.f", "ATOIH DEPLOY READY"),
    ("base64url", "security/jose/base64url.f", "ATOIH B64 READY"),
    ("sha256", "math/sha256.f", "ATOIH SHA READY"),
    ("p256", "math/p256.f", "ATOIH P256 READY"),
    ("jwk-p256", "security/jose/jwk-p256.f", "ATOIH JWK READY"),
    ("jwk-set", "security/jose/jwk-set-p256.f", "ATOIH JWK SET READY"),
    ("seam", "local_testing/atoi-seam.f", "ATOIH SEAM READY"),
    ("inline", "local_testing/atoi-source.f", "ATOIH INLINE READY"),
    ("shared-hres", "local_testing/atohttp-source.f", "ATOIH POLICY READY"),
    ("source", "local_testing/atoih-source.f", "ATOIH SOURCE READY"),
    (
        "hres-fixture",
        "local_testing/hres-contracts.f",
        "ATOIH HRES FIXTURE READY",
    ),
    (
        "profile-fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATOIH PROFILE FIXTURE READY",
    ),
    (
        "deployment-fixture",
        "local_testing/at-oauth-deploy-test.f",
        "ATOIH DEPLOY FIXTURE READY",
    ),
    (
        "inline-fixture",
        "local_testing/at-oauth-inline-test.f",
        "ATOIH INLINE FIXTURE READY",
    ),
    ("fixture", "local_testing/atoih-test.f", "ATOIH FIXTURE READY"),
)

GROUP_STAGES = (
    ("policy", "_ATOIHT-TEST-POLICY", "ATOIH POLICY GROUP READY"),
    ("success", "_ATOIHT-TEST-SUCCESS", "ATOIH SUCCESS GROUP READY"),
    (
        "provenance",
        "_ATOIHT-TEST-PROVENANCE",
        "ATOIH PROVENANCE GROUP READY",
    ),
    ("preflight", "_ATOIHT-TEST-PREFLIGHT", "ATOIH PREFLIGHT GROUP READY"),
)

FAILURE_MARKERS = (
    "AT OAUTH INLINE HRES FAIL",
    "AT OAUTH INLINE HRES ASSERT",
    "AT OAUTH INLINE HRES STATUS",
    "AT OAUTH INLINE HRES STACK",
    "AT OAUTH INLINE HRES LOAD STACK",
    "AT OAUTH INLINE FAIL",
    "AT OAUTH INLINE ASSERT",
    "AT OAUTH DEPLOYMENT FAIL",
    "AT OAUTH DEPLOYMENT ASSERT",
    "AT OAUTH PROFILE FAIL",
    "AT OAUTH PROFILE ASSERT",
    "DRIVER THROW",
    "Branch offset overflow",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
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
    shared = SHARED_SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    source_code = _forth_code(source).lower()
    fixture_code = _forth_code(fixture)

    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    stages = (*LOAD_STAGES, *GROUP_STAGES)
    assert len({name for name, _, _ in stages}) == len(stages)
    assert len({marker for _, _, marker in stages}) == len(stages)
    for guest_name in (
        "atoi-seam.f",
        "atoi-source.f",
        "atohttp-source.f",
        "atoih-source.f",
        "at-oauth-prof-test.f",
        "at-oauth-deploy-test.f",
        "at-oauth-inline-test.f",
        "atoih-test.f",
    ):
        assert len(guest_name.encode("ascii")) <= 23

    assert "PROVIDED akashic-at-oauth-ihres" in source
    assert "PROVIDED akashic-at-oauth-http" in shared
    assert "PROVIDED at-oauth-ihres-test" in fixture
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "inline HRES adapter must retain no module-owned mutable state"
    for required in (
        "client-config.f",
        "credential-vault.f",
        "oauth-hres.f",
        "oauth-profile.f",
        "oauth-deployment-inline.f",
    ):
        assert any(required in item for item in _requires(SOURCE))
    assert any(
        "http-resource.f" in item for item in _requires(SHARED_SOURCE)
    )
    for forbidden in ("streams", "session.f", "xrpc", "kdos-tls", "tcp-", "udp-"):
        assert forbidden not in source_code

    for word in (
        "AT-OAUTH-INLINE-HRES-WORKSPACE-SIZE",
        "AT-OAUTH-INLINE-HRES-WORKSPACE-CLEAR",
        "AT-OAUTH-INLINE-HRES-SPEC-POLICY!",
        "AT-OAUTH-INLINE-HRES-STATUS-VALID?",
        "AT-OAUTH-INLINE-HRES-WITH",
        "AT-OAUTH-HRES-URI-ENVELOPE?",
        "OAUTH2-CLIENT-CONFIG-CLIENT-ID@",
        "HRES-BODY-STORAGE@",
        "AT-OAUTH-INLINE-WITH",
    ):
        assert word in source
    assert re.search(
        r"(?m)^42[ \t]+CONSTANT[ \t]+AT-OAUTH-INLINE-HRES-S-HTTP$",
        source,
    )
    assert "AT-OAUTH-HRES-SPEC-POLICY!" in _word_body(
        source, "AT-OAUTH-INLINE-HRES-SPEC-POLICY!"
    )
    assert "AT-OAUTH-HRES-URI-ENVELOPE?" in _word_body(
        source, "_ATOIH-ENVELOPE-STATUS"
    )

    for marker in (
        "_ATOIHT-TEST-POLICY",
        "_ATOIHT-TEST-SUCCESS",
        "_ATOIHT-TEST-PROVENANCE",
        "_ATOIHT-TEST-PREFLIGHT",
        "_ATOIHT-FINISH",
        PASS_MARKER,
        "HRES-RESULT-VALID?",
        "HRES-REDIRECT-COUNT@",
        "text/plain",
        "_ATOIHT-TAIL-BODY-CAP",
        "_ATOID-DEPLOY-CALLS",
    ):
        assert marker in fixture
    assert not re.search(r"\b_ATOIT-TEST-", fixture)
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        fixture_code,
    ), "focused fixture must not borrow the DO-loop return stack"
    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(SHARED_SOURCE, shared)
    _assert_physical_comments(FIXTURE, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - acquired confidential inline AT OAuth gates\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH INLINE HRES LOAD STACK '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOIHT-INIT\n")
    for _, word, marker in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOIHT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(
            "atproto/oauth-deployment.f",
            "security/jose/jwk-set-p256.f",
            "net/http-resource.f",
        ),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=(
            (
                "local_testing/atoi-seam.f",
                harness._minify_forth(SEAM_DOUBLES).encode("utf-8"),
            ),
            (
                "local_testing/atoi-source.f",
                _packed(INLINE_SOURCE, remove_requires=True),
            ),
            (
                "local_testing/atohttp-source.f",
                _packed(SHARED_SOURCE, remove_requires=True),
            ),
            (
                "local_testing/atoih-source.f",
                _packed(SOURCE, remove_requires=True),
            ),
            (
                f"local_testing/{HRES_FIXTURE.name}",
                _packed(HRES_FIXTURE),
            ),
            (
                f"local_testing/{PROFILE_FIXTURE.name}",
                _packed(PROFILE_FIXTURE),
            ),
            (
                f"local_testing/{DEPLOYMENT_FIXTURE.name}",
                _packed(DEPLOYMENT_FIXTURE),
            ),
            (
                f"local_testing/{INLINE_FIXTURE.name}",
                _packed(INLINE_FIXTURE),
            ),
            ("local_testing/atoih-test.f", _packed(FIXTURE)),
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
                print(f"AT OAuth inline HRES {stage_name}: FAIL")
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-5000:])
                return 1
            print(
                f"AT OAuth inline HRES {stage_name}: PASS "
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
        reports.append(("finish", report))
        if PASS_MARKER not in raw or failures:
            print("AT OAuth inline HRES finish: FAIL")
            for failure in failures:
                print(f"  {failure}")
            print(raw[-5000:])
            return 1

    total_steps = sum(report.steps for _, report in reports)
    total_elapsed = sum(report.elapsed_s for _, report in reports)
    print(
        "AT OAuth inline HRES lifecycle: PASS "
        f"({total_steps:,} steps, {total_elapsed:.2f}s)"
    )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=300.0)
    args = parser.parse_args()

    _assert_static_contracts()
    print("AT OAUTH INLINE HRES STATIC PASS", flush=True)
    if args.static_only:
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
