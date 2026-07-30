#!/usr/bin/env python3
"""Focused qualification for retained remote-JWKS AT OAuth metadata."""

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


SOURCE = ROOT / "akashic" / "atproto" / "oauth-remote-hres.f"
SHARED_SOURCE = ROOT / "akashic" / "atproto" / "oauth-hres.f"
INLINE_SOURCE = ROOT / "akashic" / "atproto" / "oauth-deployment-inline.f"
PUBLISHED_SOURCE = (
    ROOT
    / "akashic"
    / "security"
    / "oauth2"
    / "published-key-p256.f"
)
HRES_FIXTURE = LOCAL_TESTING / "hres-contracts.f"
PROFILE_FIXTURE = LOCAL_TESTING / "at-oauth-prof-test.f"
DEPLOYMENT_FIXTURE = LOCAL_TESTING / "at-oauth-deploy-test.f"
INLINE_FIXTURE = LOCAL_TESTING / "at-oauth-inline-test.f"
FIXTURE = LOCAL_TESTING / "at-oauth-remote-hres-test.f"

PROFILE = "at-oauth-remote-hres"
IMAGE = Path("/tmp/akashic-at-oauth-remote-hres.img")
PASS_MARKER = "AT OAUTH REMOTE HRES PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

# Staging and behavior groups are deliberately sequential.  This keeps each
# phase under the checked-in ceiling and limits qualification to vertical-slice
# gates rather than expanding the deferred edge-case matrix.
LOAD_STAGES = (
    ("event", "concurrency/event.f", "ATORH EVENT READY"),
    ("semaphore", "concurrency/semaphore.f", "ATORH SEMAPHORE READY"),
    ("guard", "concurrency/guard.f", "ATORH GUARD READY"),
    ("string", "utils/string.f", "ATORH STRING READY"),
    ("memory-span", "utils/memory-span.f", "ATORH MEMORY READY"),
    ("caller-span", "utils/caller-span.f", "ATORH CALLER READY"),
    ("io-port", "net/io-port.f", "ATORH IO PORT READY"),
    ("external-io", "net/external-io.f", "ATORH EXTERNAL IO READY"),
    ("http-request", "net/http-request.f", "ATORH HTTP REQUEST READY"),
    ("http-stream", "net/http-stream.f", "ATORH HTTP STREAM READY"),
    ("http-buffered", "net/http-buffered.f", "ATORH HTTP BUFFERED READY"),
    ("http-target", "net/http-target.f", "ATORH HTTP TARGET READY"),
    ("media-type", "net/media-type.f", "ATORH MEDIA READY"),
    ("http-resource", "net/http-resource.f", "ATORH HTTP RESOURCE READY"),
    (
        "client-config",
        "security/oauth2/client-config.f",
        "ATORH CONFIG READY",
    ),
    ("json-object", "security/jose/json-object.f", "ATORH JSON READY"),
    (
        "client-metadata",
        "security/oauth2/client-metadata.f",
        "ATORH CLIENT META READY",
    ),
    ("did", "atproto/did.f", "ATORH DID READY"),
    ("handle", "atproto/handle.f", "ATORH HANDLE READY"),
    ("did-document", "atproto/did-document.f", "ATORH DID DOC READY"),
    ("dns-txt", "net/dns-txt.f", "ATORH DNS READY"),
    ("identity", "atproto/identity.f", "ATORH IDENTITY READY"),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATORH RMETA READY",
    ),
    ("oauth-metadata", "security/oauth2/metadata.f", "ATORH META READY"),
    ("oauth-profile", "atproto/oauth-profile.f", "ATORH PROFILE READY"),
    ("oauth-client", "atproto/oauth-client.f", "ATORH CLIENT READY"),
    ("deployment", "atproto/oauth-deployment.f", "ATORH DEPLOY READY"),
    ("base64url", "security/jose/base64url.f", "ATORH B64 READY"),
    ("sha256", "math/sha256.f", "ATORH SHA READY"),
    ("p256", "math/p256.f", "ATORH P256 READY"),
    ("jwk-p256", "security/jose/jwk-p256.f", "ATORH JWK READY"),
    ("jwk-set", "security/jose/jwk-set-p256.f", "ATORH JWK SET READY"),
    ("seam", "local_testing/atoi-seam.f", "ATORH SEAM READY"),
    (
        "published-key",
        "local_testing/o2pp-source.f",
        "ATORH PUBLISHED KEY READY",
    ),
    ("inline", "local_testing/atoi-source.f", "ATORH INLINE READY"),
    ("shared-hres", "local_testing/atohttp-source.f", "ATORH POLICY READY"),
    ("source", "local_testing/atorh-source.f", "ATORH SOURCE READY"),
    (
        "hres-fixture",
        "local_testing/hres-contracts.f",
        "ATORH HRES FIXTURE READY",
    ),
    (
        "profile-fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATORH PROFILE FIXTURE READY",
    ),
    (
        "deployment-fixture",
        "local_testing/at-oauth-deploy-test.f",
        "ATORH DEPLOY FIXTURE READY",
    ),
    (
        "inline-fixture",
        "local_testing/at-oauth-inline-test.f",
        "ATORH INLINE FIXTURE READY",
    ),
    ("fixture", "local_testing/atorh-test.f", "ATORH FIXTURE READY"),
)

GROUP_STAGES = (
    (
        "contracts",
        "_ATORHT-TEST-CONTRACTS",
        "ATORH CONTRACTS GROUP READY",
    ),
    (
        "success-keys-callback",
        "_ATORHT-TEST-SUCCESS",
        "ATORH SUCCESS KEYS CALLBACK GROUP READY",
    ),
    (
        "provenance-source",
        "_ATORHT-TEST-PROVENANCE",
        "ATORH PROVENANCE SOURCE GROUP READY",
    ),
    (
        "preflight",
        "_ATORHT-TEST-PREFLIGHT",
        "ATORH PREFLIGHT GROUP READY",
    ),
)

FAILURE_MARKERS = (
    "AT OAUTH REMOTE HRES FAIL",
    "AT OAUTH REMOTE HRES ASSERT",
    "AT OAUTH REMOTE HRES STATUS",
    "AT OAUTH REMOTE HRES STACK",
    "AT OAUTH REMOTE HRES LOAD STACK",
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

STATUS_NAMES = (
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
    "BINDING",
    "JWKS",
    "NOT-FOUND",
    "ABSENT",
    "REVOKED",
    "CONFLICT",
    "BUSY",
    "LOCKED",
    "ENTROPY",
    "CRYPTO",
    "AUTH",
    "CORRUPT",
    "UNSUPPORTED",
    "IO",
    "RECOVERY",
    "ROLLBACK",
    "FORMAT",
    "KEY",
    "MISMATCH",
    "DISTINCT",
    "CALLBACK",
    "INTERNAL",
    "RANGE",
    "PROTECTED",
    "PLATFORM",
    "METADATA-HTTP",
    "JWKS-TARGET",
    "JWKS-HTTP",
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
    inline = INLINE_SOURCE.read_text(encoding="utf-8")
    published = PUBLISHED_SOURCE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    source_code = _forth_code(source).lower()
    fixture_code = _forth_code(fixture)
    requires = _requires(SOURCE)
    required_names = {Path(item).name for item in requires}

    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    stages = (*LOAD_STAGES, *GROUP_STAGES)
    assert len({name for name, _, _ in stages}) == len(stages)
    assert len({marker for _, _, marker in stages}) == len(stages)
    guest_names = (
        "atoi-seam.f",
        "o2pp-source.f",
        "atoi-source.f",
        "atohttp-source.f",
        "atorh-source.f",
        "hres-contracts.f",
        "at-oauth-prof-test.f",
        "at-oauth-deploy-test.f",
        "at-oauth-inline-test.f",
        "atorh-test.f",
    )
    assert all(len(name.encode("ascii")) <= 23 for name in guest_names)

    assert "PROVIDED akashic-at-oauth-rhres" in source
    assert "PROVIDED akashic-at-oauth-http" in shared
    assert "PROVIDED akashic-oauth2-p256-pub" in published
    assert "PROVIDED at-oauth-rhres-test" in fixture
    assert "published-key-p256.f" in inline
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "remote HRES adapter must retain no module-owned mutable state"

    for required in (
        "memory-span.f",
        "caller-span.f",
        "http-target.f",
        "credential-vault.f",
        "client-config.f",
        "client-metadata.f",
        "published-key-p256.f",
        "oauth-hres.f",
        "oauth-profile.f",
        "oauth-deployment.f",
    ):
        assert required in required_names
    for forbidden_dependency in (
        "key-p256.f",
        "jwk-p256.f",
        "jwk-set-p256.f",
    ):
        assert forbidden_dependency not in required_names
    for forbidden in ("streams", "session.f", "xrpc", "kdos-tls", "tcp-", "udp-"):
        assert forbidden not in source_code

    for word in (
        "AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE",
        "AT-OAUTH-REMOTE-HRES-WORKSPACE-CLEAR",
        "AT-OAUTH-REMOTE-HRES-SPEC-POLICY!",
        "AT-OAUTH-REMOTE-HRES-STATUS-VALID?",
        "AT-OAUTH-REMOTE-HRES-JWKS-TARGET!",
        "AT-OAUTH-REMOTE-HRES-WITH",
    ):
        assert word in source
    assert len(STATUS_NAMES) == 45
    for value, name in enumerate(STATUS_NAMES):
        assert re.search(
            rf"(?m)^{value}[ \t]+CONSTANT[ \t]+"
            rf"AT-OAUTH-REMOTE-HRES-S-{re.escape(name)}$",
            source,
        )

    assert re.search(
        r"(?ms)^_ATORW-STAGED-TARGET-OFF[ \t]+HTARGET-SIZE[ \t]*\+"
        r".*?CONSTANT[ \t]+_ATORW-DEPLOYMENT-OFF",
        source,
    )
    assert re.search(
        r"(?ms)^_ATORW-DEPLOYMENT-OFF"
        r"[ \t]+AT-OAUTH-DEPLOYMENT-WORKSPACE-SIZE[ \t]*\+"
        r".*?CONSTANT[ \t]+_ATORW-PUBLISHED-OFF",
        source,
    )
    assert re.search(
        r"(?ms)^_ATORW-PUBLISHED-OFF"
        r"[ \t]+OAUTH2-P256-PUBLISHED-WORKSPACE-SIZE[ \t]*\+"
        r".*?CONSTANT[ \t]+AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE",
        source,
    )
    assert re.search(
        r"(?m)^AT-OAUTH-REMOTE-HRES-WORKSPACE-SIZE"
        r"[ \t]+115336[ \t]+<>[ \t]+\[IF\]$",
        source,
    )

    target_geometry = _word_body(source, "_ATOR-TARGET-GEOMETRY")
    geometry = _word_body(source, "_ATOR-GEOMETRY")
    remote_prep = _word_body(source, "_ATOR-REMOTE-PREP")
    target_callback = _word_body(
        source, "_ATOR-TARGET-DEPLOYMENT-CALLBACK"
    )
    deployment_callback = _word_body(
        source, "_ATOR-DEPLOYMENT-CALLBACK-RUN"
    )
    public_target = _word_body(
        source, "AT-OAUTH-REMOTE-HRES-JWKS-TARGET!"
    )
    public_with = _word_body(source, "AT-OAUTH-REMOTE-HRES-WITH")
    application_callback = _word_body(source, "_ATOR-PUBLISHED-CALLBACK")

    assert target_geometry.count("HRES-BODY-STORAGE@") >= 1
    assert geometry.count("HRES-BODY-STORAGE@") >= 4
    assert geometry.count("_ATOR-EXTERNAL-STATUS") >= 7
    assert "_ATOR-BODIES-OVERLAP?" in geometry
    assert "_ATOR-TARGET-GEOMETRY" in public_target
    assert "_ATOR-GEOMETRY" in public_with
    assert public_target.index("_ATOR-TARGET-GEOMETRY") < public_target.index(
        "_ATOR-TARGET-WITH-OP"
    )
    assert public_with.index("_ATOR-GEOMETRY") < public_with.index(
        "_ATOR-WITH-OP"
    )

    assert "HTARGET-PARSE" in remote_prep
    assert "JOSE-JWK-SET-P256-MAX-DOCUMENT-BYTES" not in remote_prep
    assert "OAUTH2-P256-KEY-" not in remote_prep
    assert "_ATOR-REMOTE-PREP" in target_callback
    assert "_ATOR-REMOTE-PREP" in deployment_callback
    assert "AT-OAUTH-HRES-TARGET-ENVELOPE?" in deployment_callback
    assert deployment_callback.index("_ATOR-REMOTE-PREP") < (
        deployment_callback.index("AT-OAUTH-HRES-TARGET-ENVELOPE?")
    )

    assert application_callback.count("DEPTH") >= 2
    assert application_callback.count("_ATOR-CALLBACK-GUARD") >= 2
    assert application_callback.count("8 PICK") == 6
    assert "_ATOR-E-CALLBACK-STACK THROW" in application_callback

    for _, group_word, _ in GROUP_STAGES:
        assert group_word in fixture
    for marker in (
        "_ATORHT-INIT",
        "_ATORHT-FINISH",
        PASS_MARKER,
        "AT-OAUTH-REMOTE-HRES-JWKS-TARGET!",
        "AT-OAUTH-REMOTE-HRES-WITH",
        "HRES-BODY-STORAGE@",
        "_ATOID-DEPLOY-CALLS",
    ):
        assert marker in fixture
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        fixture_code,
    ), "focused fixture must not borrow the DO-loop return stack"

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(SHARED_SOURCE, shared)
    _assert_physical_comments(PUBLISHED_SOURCE, published)
    _assert_physical_comments(FIXTURE, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - retained remote-JWKS AT OAuth gates\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH REMOTE HRES LOAD STACK '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATORHT-INIT\n")
    for _, word, marker in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATORHT-FINISH\nTX-FLUSH\n")

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
                "local_testing/o2pp-source.f",
                _packed(PUBLISHED_SOURCE, remove_requires=True),
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
                "local_testing/atorh-source.f",
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
            ("local_testing/atorh-test.f", _packed(FIXTURE)),
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
                print(f"AT OAuth remote HRES {stage_name}: FAIL")
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-5000:])
                return 1
            print(
                f"AT OAuth remote HRES {stage_name}: PASS "
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
            print("AT OAuth remote HRES finish: FAIL")
            for failure in failures:
                print(f"  {failure}")
            print(raw[-5000:])
            return 1

    total_steps = sum(report.steps for _, report in reports)
    total_elapsed = sum(report.elapsed_s for _, report in reports)
    print(
        "AT OAuth remote HRES lifecycle: PASS "
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
    print("AT OAUTH REMOTE HRES STATIC PASS", flush=True)
    if args.static_only:
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
