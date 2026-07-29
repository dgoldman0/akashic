#!/usr/bin/env python3
"""Qualify state-free AT Protocol OAuth token-grant admission."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "at-oauth-grant-contracts"
IMAGE = Path("/tmp/akashic-at-oauth-grant-contracts.img")
SOURCE = ROOT / "akashic" / "atproto" / "oauth-grant.f"
SESSION_SOURCE = ROOT / "akashic" / "security" / "oauth2" / "session.f"
TOKEN_SET_SOURCE = ROOT / "akashic" / "security" / "oauth2" / "token-set.f"
SESSION_DEPS = LOCAL_TESTING / "oauth2-session-deps.f"
PROFILE_CONTRACT = LOCAL_TESTING / "at-oauth-prof-test.f"
CONTRACT = LOCAL_TESTING / "at-oauth-grant-test.f"

PASS_MARKER = "AT OAUTH GRANT PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

# Compile the production token-set and session modules.  Their deterministic
# lower-stack fixture keeps this policy gate out of unrelated crypto/VFS
# lifecycle work, which has its own exact session/vault qualification.
LOAD_STAGES = (
    (
        "session-deps",
        "local_testing/oauth2-session-deps.f",
        "ATOG SESSION DEPS READY",
        180_000_000,
    ),
    (
        "token-set",
        "security/oauth2/token-set.f",
        "ATOG TOKEN SET READY",
        180_000_000,
    ),
    (
        "session",
        "security/oauth2/session.f",
        "ATOG SESSION READY",
        180_000_000,
    ),
    ("string", "utils/string.f", "ATOG STRING READY", 120_000_000),
    (
        "json-object",
        "security/jose/json-object.f",
        "ATOG JSON OBJECT READY",
        180_000_000,
    ),
    (
        "http-target",
        "net/http-target.f",
        "ATOG HTTP TARGET READY",
        120_000_000,
    ),
    ("did", "atproto/did.f", "ATOG DID READY", 120_000_000),
    ("handle", "atproto/handle.f", "ATOG HANDLE READY", 120_000_000),
    (
        "did-document",
        "atproto/did-document.f",
        "ATOG DID DOCUMENT READY",
        180_000_000,
    ),
    ("dns-txt", "net/dns-txt.f", "ATOG DNS TXT READY", 180_000_000),
    (
        "identity",
        "atproto/identity.f",
        "ATOG IDENTITY READY",
        180_000_000,
    ),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATOG RESOURCE METADATA READY",
        180_000_000,
    ),
    (
        "as-metadata",
        "security/oauth2/metadata.f",
        "ATOG AS METADATA READY",
        180_000_000,
    ),
    (
        "oauth-profile",
        "atproto/oauth-profile.f",
        "ATOG PROFILE READY",
        180_000_000,
    ),
    (
        "token-response",
        "security/oauth2/token-response.f",
        "ATOG TOKEN RESPONSE READY",
        180_000_000,
    ),
    (
        "grant-adapter",
        "atproto/oauth-grant.f",
        "ATOG ADAPTER READY",
        180_000_000,
    ),
    (
        "profile-fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATOG PROFILE FIXTURE READY",
        180_000_000,
    ),
    (
        "grant-fixture",
        "local_testing/at-oauth-grant-test.f",
        "ATOG FIXTURE READY",
        180_000_000,
    ),
)

GROUP_STAGES = (
    (
        "happy",
        "_ATOGT-TEST-HAPPY",
        "ATOG HAPPY GROUP READY",
        180_000_000,
    ),
    (
        "policy",
        "_ATOGT-TEST-POLICY",
        "ATOG POLICY GROUP READY",
        180_000_000,
    ),
    (
        "refresh",
        "_ATOGT-TEST-REFRESH",
        "ATOG REFRESH GROUP READY",
        180_000_000,
    ),
    (
        "expiry",
        "_ATOGT-TEST-EXPIRY",
        "ATOG EXPIRY GROUP READY",
        180_000_000,
    ),
    (
        "callbacks",
        "_ATOGT-TEST-CALLBACKS",
        "ATOG CALLBACK GROUP READY",
        180_000_000,
    ),
    (
        "geometry",
        "_ATOGT-TEST-GEOMETRY",
        "ATOG GEOMETRY GROUP READY",
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
        if "(" in code:
            assert ")" in code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    session_source = SESSION_SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    profile_fixture = PROFILE_CONTRACT.read_text(encoding="utf-8")
    forth_code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()
    fixture_lower = fixture.lower()

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
    assert len(SESSION_DEPS.name.encode("utf-8")) <= 23
    assert TOKEN_SET_SOURCE.is_file()

    assert _requires(SOURCE) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../security/oauth2/token-response.f",
        "../security/oauth2/session.f",
        "did.f",
        "oauth-profile.f",
    ]
    assert "PROVIDED akashic-at-oauth-grant" in source
    assert "PROVIDED akashic-oauth2-session" in session_source
    assert re.search(
        r"(?m)^96 CONSTANT O2SESSION-GRANT-SIZE$", session_source
    )
    for word in (
        "O2SESSION-G.ACCESS-A",
        "O2SESSION-G.ACCESS-U",
        "O2SESSION-G.TOKEN-TYPE-A",
        "O2SESSION-G.TOKEN-TYPE-U",
        "O2SESSION-G.REFRESH-A",
        "O2SESSION-G.REFRESH-U",
        "O2SESSION-G.SCOPE-A",
        "O2SESSION-G.SCOPE-U",
        "O2SESSION-G.ID-A",
        "O2SESSION-G.ID-U",
        "O2SESSION-G.EXPIRES-AT-MS",
        "O2SESSION-G.FLAGS",
        "O2SESSION-GRANT-CLEAR",
    ):
        assert re.search(
            rf"(?m)^:[ \t]+{re.escape(word)}(?=[ \t\r\n(])",
            session_source,
        ), f"missing production session grant contract {word}"
    session_grant_clear = _word_body(
        session_source, "O2SESSION-GRANT-CLEAR"
    )
    assert "_O2S-ADMIT-SPAN" in session_grant_clear
    assert "O2SESSION-GRANT-SIZE 0 FILL" in session_grant_clear
    assert (
        "_O2SG-FLAGS 8 + O2SESSION-GRANT-SIZE <> [IF]"
        in session_source
    )
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "AT OAuth grant admission must own no mutable module state"

    for forbidden in (
        "streams",
        "xrpc",
        "http-",
        "hres-",
        "cva",
        "o2session-install",
        "o2session-reauthorize",
        "o2session-refresh",
    ):
        assert forbidden not in forth_code

    public_words = (
        "AT-OAUTH-GRANT-WORKSPACE-SIZE",
        "AT-OAUTH-GRANT-WORKSPACE-CLEAR",
        "AT-OAUTH-GRANT-STATUS-VALID?",
        "AT-OAUTH-GRANT-MODE-VALID?",
        "AT-OAUTH-GRANT-MODE-INITIAL",
        "AT-OAUTH-GRANT-MODE-REFRESH",
        "AT-OAUTH-GRANT-WITH",
    )
    for word in public_words:
        assert word in source

    for status in (
        "AT-OAUTH-GRANT-S-OK",
        "AT-OAUTH-GRANT-S-PROFILE",
        "AT-OAUTH-GRANT-S-RESPONSE",
        "AT-OAUTH-GRANT-S-TOKEN-TYPE",
        "AT-OAUTH-GRANT-S-SCOPE",
        "AT-OAUTH-GRANT-S-SUBJECT",
        "AT-OAUTH-GRANT-S-SUBJECT-BINDING",
        "AT-OAUTH-GRANT-S-REFRESH",
        "AT-OAUTH-GRANT-S-TIME",
        "AT-OAUTH-GRANT-S-OVERFLOW",
        "AT-OAUTH-GRANT-S-CALLBACK",
        "AT-OAUTH-GRANT-S-PLATFORM",
    ):
        assert status in source

    assert re.search(
        r"(?m)^AT-OAUTH-GRANT-WORKSPACE-SIZE 35240 <> \[IF\]$",
        source,
    )
    geometry = _word_body(source, "_ATOG-WITH-GEOMETRY")
    assert "_ATOG-SPAN-STATUS" in geometry
    assert "_ATOG-FIXED-STATUS" in geometry
    assert "AT-OAUTH-PROFILE-SIZE" in geometry
    assert "AT-OAUTH-PROFILE-READY?" in geometry
    assert geometry.count("MSPAN-OVERLAP?") >= 3

    policy = _word_body(source, "_ATOG-POLICY")
    for word in (
        "_ATOG-STAGE-ACCESS",
        "_ATOG-STAGE-TYPE",
        "_ATOG-STAGE-SCOPE",
        "_ATOG-CHECK-SUBJECT",
        "_ATOG-STAGE-REFRESH",
        "_ATOG-STAGE-EXPIRY",
        "_ATOG-CLIENT-CALLBACK-SAFE",
    ):
        assert word in policy
    assert "DID-VALIDATE" in _word_body(source, "_ATOG-CHECK-SUBJECT")
    assert "AT-OAUTH-PROFILE-DID@" in _word_body(
        source, "_ATOG-CHECK-SUBJECT"
    )
    assert 'S" atproto"' in _word_body(source, "_ATOG-ATPROTO-SCOPE?")
    assert "[CHAR] d" in _word_body(source, "_ATOG-DPOP?")

    with_operation = _word_body(source, "_ATOG-WITH-OP")
    assert "OAUTH2-TOKEN-RESPONSE-WITH" in with_operation
    assert "_ATOGW.PARSER-STATUS" in with_operation
    assert "_ATOGW.POLICY-STATUS" in with_operation
    assert "_ATOG-WIPE-RETURN" in with_operation
    assert "CATCH" in _word_body(source, "_ATOG-WITH-CALL")
    callback_safe = _word_body(source, "_ATOG-CLIENT-CALLBACK-SAFE")
    assert "CATCH" in callback_safe
    assert "AT-OAUTH-GRANT-S-CALLBACK" in callback_safe
    callback_run = _word_body(source, "_ATOG-CLIENT-CALLBACK-RUN")
    assert "DEPTH" in callback_run
    assert "EXECUTE" in callback_run

    assert "PROVIDED at-oauth-prof-test" in profile_fixture
    assert "PROVIDED at-oauth-grant-test" in fixture
    for _, group_word, _, _ in GROUP_STAGES:
        assert group_word in fixture
    for marker in (
        "AT OAUTH GRANT PASS",
        "transition:generic atproto",
        "transition:generic atproto repo:write",
        "atproto:write",
        "xatproto",
        "DPoP-1",
        r"did\u003Aplc\u003Aabcdefghijklmnopqrstuvwx",
        r"s\u0075b",
        "did:plc:abcdefghijklmnopqrstuvwy",
        "AT-OAUTH-GRANT-S-TOKEN-TYPE",
        "AT-OAUTH-GRANT-S-SUBJECT-BINDING",
        "AT-OAUTH-GRANT-S-REFRESH",
        "AT-OAUTH-GRANT-S-OVERFLOW",
        "AT-OAUTH-GRANT-S-CALLBACK",
        "AT-OAUTH-GRANT-S-ALIAS",
        "_atogt-saved-grant-zero?",
    ):
        assert marker in fixture

    for private_prefix in (
        "_atogw.",
        "_atogw-",
        "_atog-",
        "_o2tr",
        "_o2sg",
        "_o2s.",
        "_o2s-",
        "_atop.",
        "_atop-",
    ):
        assert private_prefix not in fixture_lower
    for forbidden_integration in (
        "o2session-init",
        "o2session-install",
        "o2session-reauthorize",
        "o2session-refresh",
        "o2session-open",
        "cvault-",
    ):
        assert forbidden_integration not in fixture_lower
    for public_grant_field in (
        "O2SESSION-G.ACCESS-A",
        "O2SESSION-G.TOKEN-TYPE-A",
        "O2SESSION-G.REFRESH-A",
        "O2SESSION-G.SCOPE-A",
        "O2SESSION-G.ID-A",
        "O2SESSION-G.ID-U",
        "O2SESSION-G.EXPIRES-AT-MS",
        "O2SESSION-G.FLAGS",
    ):
        assert public_grant_field in fixture

    assert not re.search(
        r"(?mi)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture
    ), "the fixture must use cursor walks rather than indexed loops"
    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - staged AT OAuth grant contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker, _ in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH GRANT LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOGT-INIT\n")
    for _, word, marker, _ in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOGT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/oauth-grant.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT OAUTH GRANT FAIL",
            "AT OAUTH GRANT ASSERT",
            "AT OAUTH GRANT STATUS",
            "AT OAUTH GRANT STACK",
            "AT OAUTH GRANT LOAD STACK FAIL",
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
                f"local_testing/{SESSION_DEPS.name}",
                harness._minify_forth(
                    SESSION_DEPS.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
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
                print(f"AT OAuth grant {stage_name}: FAIL")
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
        print(f"AT OAuth grant lifecycle: {'PASS' if ok else 'FAIL'}")
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
        print("AT OAUTH GRANT STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
