#!/usr/bin/env python3
"""Qualify public AT token exchange through durable session reopen."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from test_oauth2_p256_key import P256_JWK_DOUBLES  # noqa: E402


PROFILE = "at-token-p256-vertical"
IMAGE = Path("/tmp/akashic-at-token-p256-vertical.img")
PASS_MARKER = "AT SESSION INSTALL PASS"

RAW_PAR = SOURCE_ROOT / "atproto" / "oauth-par.f"
PAR_WRAPPER = SOURCE_ROOT / "atproto" / "oauth-par-p256.f"
AUTHORIZATION = SOURCE_ROOT / "atproto" / "oauth-authorization.f"
VAULT = SOURCE_ROOT / "security" / "credential-vault.f"
KEY_OWNER = SOURCE_ROOT / "security" / "oauth2" / "key-p256.f"
ERROR_RESPONSE = SOURCE_ROOT / "security" / "oauth2" / "error-response.f"
TOKEN_REQUEST = SOURCE_ROOT / "security" / "oauth2" / "token-request.f"
DPOP_NONCE = SOURCE_ROOT / "security" / "oauth2" / "dpop-nonce.f"
TOKEN_RESPONSE = SOURCE_ROOT / "security" / "oauth2" / "token-response.f"
TOKEN_SET = SOURCE_ROOT / "security" / "oauth2" / "token-set.f"
SESSION = SOURCE_ROOT / "security" / "oauth2" / "session.f"
GRANT = SOURCE_ROOT / "atproto" / "oauth-grant.f"
TOKEN = SOURCE_ROOT / "atproto" / "oauth-token.f"
TOKEN_P256 = SOURCE_ROOT / "atproto" / "oauth-token-p256.f"
CV_DEPS = LOCAL_TESTING / "cv-deps.f"

PROFILE_FIXTURE = LOCAL_TESTING / "at-oauth-prof-test.f"
CLIENT_FIXTURE = LOCAL_TESTING / "at-oauth-client-test.f"
HTTP_FIXTURE = LOCAL_TESTING / "o2-http-post-common.f"
RAW_PAR_FIXTURE = LOCAL_TESTING / "at-oauth-par-test.f"
KEY_FIXTURE = LOCAL_TESTING / "oauth2-p256-key-test.f"
PAR_P256_FIXTURE = LOCAL_TESTING / "at-par-p256-test.f"
AUTHORIZATION_FIXTURE = LOCAL_TESTING / "at-oauth-authz-test.f"
CONTRACT = LOCAL_TESTING / "at-token-p256-test.f"
SESSION_CONTRACT = LOCAL_TESTING / "at-session-test.f"
FIXTURES = (
    PROFILE_FIXTURE,
    CLIENT_FIXTURE,
    HTTP_FIXTURE,
    RAW_PAR_FIXTURE,
    KEY_FIXTURE,
    PAR_P256_FIXTURE,
    AUTHORIZATION_FIXTURE,
    CONTRACT,
    SESSION_CONTRACT,
)

MAX_PHASE_STEPS = 180_000_000
# Final reporting composes session, authorization, and durable-PAR teardown,
# so it receives the same approved ceiling as every other serial phase.
FINISH_STEPS = MAX_PHASE_STEPS

# Load the ordinary PAR closure before cv-deps.  This preserves its exact
# HTTP/profile/auth-code dependencies while allowing the established
# deterministic crypto/VFS seam to support the exact vault and key owner.
RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    ("atproto/oauth-par.f",),
)
PACKED_RAW = tuple(
    (f"local_testing/tv-r{index:02d}.f", module)
    for index, module in enumerate(RAW_MODULES, start=1)
)
RAW_LOAD_STAGES = tuple(
    (
        f"raw-{index:02d}",
        guest,
        f"AT TOKEN RAW {index:02d} READY",
        MAX_PHASE_STEPS,
    )
    for index, (guest, _) in enumerate(PACKED_RAW, start=1)
)

OWNER_MODULES = (
    ("seam", "local_testing/tv-seam.f", None),
    ("vault", "local_testing/tv-vault.f", VAULT),
    ("key", "local_testing/tv-key.f", KEY_OWNER),
    ("par-wrapper", "local_testing/tv-parw.f", PAR_WRAPPER),
    ("authorization", "local_testing/tv-authz.f", AUTHORIZATION),
)
OWNER_LOAD_STAGES = tuple(
    (
        name,
        guest,
        f"AT TOKEN OWNER {index:02d} READY",
        MAX_PHASE_STEPS,
    )
    for index, (name, guest, _) in enumerate(OWNER_MODULES, start=1)
)

TOKEN_MODULES = (
    ("error-response", "local_testing/tv-error.f", ERROR_RESPONSE),
    ("token-request", "local_testing/tv-treq.f", TOKEN_REQUEST),
    ("dpop-nonce", "local_testing/tv-nonce.f", DPOP_NONCE),
    ("token-response", "local_testing/tv-tresp.f", TOKEN_RESPONSE),
    ("token-set", "local_testing/tv-tset.f", TOKEN_SET),
    ("session", "local_testing/tv-session.f", SESSION),
    ("grant", "local_testing/tv-grant.f", GRANT),
    ("token", "local_testing/tv-token.f", TOKEN),
    ("token-p256", "local_testing/tv-tp256.f", TOKEN_P256),
)
TOKEN_LOAD_STAGES = tuple(
    (
        name,
        guest,
        f"AT TOKEN MODULE {index:02d} READY",
        MAX_PHASE_STEPS,
    )
    for index, (name, guest, _) in enumerate(TOKEN_MODULES, start=1)
)

FIXTURE_LOAD_STAGES = tuple(
    (
        f"fixture-{index:02d}",
        f"local_testing/{fixture.name}",
        f"AT TOKEN FIXTURE {index:02d} READY",
        MAX_PHASE_STEPS,
    )
    for index, fixture in enumerate(FIXTURES, start=1)
)

RUNTIME_STAGES = (
    (
        "par-setup",
        "_ATP2T-INIT",
        "AT TOKEN PAR SETUP READY",
        MAX_PHASE_STEPS,
    ),
    (
        "par-ready",
        "_ATP2T-TEST-HAPPY",
        "AT TOKEN PAR READY",
        MAX_PHASE_STEPS,
    ),
    (
        "auth-setup",
        "_ATAUT-INIT",
        "AT TOKEN AUTH SETUP READY",
        MAX_PHASE_STEPS,
    ),
    (
        "auth-launch",
        "_ATAUT-TEST-LAUNCH",
        "AT TOKEN AUTH LAUNCH READY",
        MAX_PHASE_STEPS,
    ),
    (
        "token-setup",
        "_ATTT-INIT",
        "AT TOKEN SETUP READY",
        MAX_PHASE_STEPS,
    ),
    (
        "prepare",
        "_ATTT-PREPARE",
        "AT TOKEN PREPARE READY",
        MAX_PHASE_STEPS,
    ),
    (
        "first-build",
        "_ATTT-FIRST-BUILD",
        "AT TOKEN FIRST BUILD READY",
        MAX_PHASE_STEPS,
    ),
    (
        "challenge",
        "_ATTT-CHALLENGE",
        "AT TOKEN CHALLENGE READY",
        MAX_PHASE_STEPS,
    ),
    (
        "retry-build",
        "_ATTT-RETRY-BUILD",
        "AT TOKEN RETRY BUILD READY",
        MAX_PHASE_STEPS,
    ),
    (
        "session-setup",
        "_ATSI-SETUP",
        "AT SESSION SETUP READY",
        MAX_PHASE_STEPS,
    ),
    (
        "success-install",
        "_ATSI-SUCCESS-INSTALL",
        "AT SESSION INSTALL READY",
        MAX_PHASE_STEPS,
    ),
    (
        "session-reopen",
        "_ATSI-REOPEN",
        "AT SESSION REOPEN READY",
        MAX_PHASE_STEPS,
    ),
)

FAILURE_MARKERS = (
    "AT TOKEN P256 FAIL",
    "AT TOKEN P256 ASSERT",
    "AT TOKEN P256 STATUS",
    "AT TOKEN P256 STACK",
    "AT SESSION INSTALL FAIL",
    "AT TOKEN LOAD STACK FAIL",
    "AT PAR P256 FAIL",
    "AT PAR P256 ASSERT",
    "AT PAR P256 STATUS",
    "AT PAR P256 STACK",
    "AT OAUTH PAR FAIL",
    "AT OAUTH PAR ASSERT",
    "AT OAUTH PAR STATUS",
    "AT OAUTH AUTHORIZATION FAIL",
    "AT OAUTH AUTHORIZATION ASSERT",
    "AT OAUTH AUTHORIZATION STATUS",
    "AT OAUTH AUTHORIZATION STACK",
    "AT OAUTH PROFILE ASSERT",
    "AT OAUTH PROFILE STATUS",
    "AT OAUTH CLIENT ASSERT",
    "AT OAUTH CLIENT STATUS",
    "OAUTH2 HTTP POST FAIL",
    "OAUTH2 HTTP POST ASSERT",
    "OAUTH2 HTTP POST STATUS",
    "OAUTH2 P256 KEY FAIL",
    "OAUTH2 P256 KEY ASSERT",
    "OAUTH2 P256 KEY STACK",
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


def _provided_ids(source: str) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*PROVIDED[ \t]+(\S+)",
        source,
    )


def _forth_code(source: str) -> str:
    return "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    )


def _word_count(source: str, name: str) -> int:
    return len(
        re.findall(
            rf"(?<![A-Za-z0-9_-]){re.escape(name)}"
            rf"(?![A-Za-z0-9_-])",
            _forth_code(source),
        )
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
    raw_token = TOKEN.read_text(encoding="utf-8")
    p256_token = TOKEN_P256.read_text(encoding="utf-8")
    token_request = TOKEN_REQUEST.read_text(encoding="utf-8")
    nonce = DPOP_NONCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    session_fixture = SESSION_CONTRACT.read_text(encoding="utf-8")
    seam = CV_DEPS.read_text(encoding="utf-8") + "\n" + P256_JWK_DOUBLES

    all_stages = (
        *RAW_LOAD_STAGES,
        *OWNER_LOAD_STAGES,
        *TOKEN_LOAD_STAGES,
        *FIXTURE_LOAD_STAGES,
        *RUNTIME_STAGES,
    )
    assert RAW_MODULES[-1] == "atproto/oauth-par.f"
    assert 0 < FINISH_STEPS <= MAX_PHASE_STEPS
    assert all(
        0 < stage_steps <= MAX_PHASE_STEPS
        for _, _, _, stage_steps in all_stages
    )
    assert len({name for name, _, _, _ in all_stages}) == len(all_stages)
    assert len({marker for _, _, marker, _ in all_stages}) == len(
        all_stages
    )
    for _, guest, _, _ in (
        *RAW_LOAD_STAGES,
        *OWNER_LOAD_STAGES,
        *TOKEN_LOAD_STAGES,
        *FIXTURE_LOAD_STAGES,
    ):
        assert len(Path(guest).name.encode("utf-8")) <= 23

    raw_ids = {
        module_id
        for module in RAW_MODULES
        for module_id in _provided_ids(
            (SOURCE_ROOT / module).read_text(encoding="utf-8")
        )
    }
    seam_ids = set(_provided_ids(seam))
    assert {
        "akashic-memory-span",
        "akashic-caller-span",
        "akashic-entropy",
        "akashic-guard",
    } <= raw_ids & seam_ids
    assert OWNER_LOAD_STAGES[0][0] == "seam"
    assert all_stages.index(RAW_LOAD_STAGES[-1]) < all_stages.index(
        OWNER_LOAD_STAGES[0]
    )

    exact_module_ids: set[str] = set()
    for _, _, path in (*OWNER_MODULES[1:], *TOKEN_MODULES):
        assert path is not None
        ids = _provided_ids(path.read_text(encoding="utf-8"))
        assert len(ids) == 1
        assert len(ids[0].encode("ascii")) <= 23
        assert ids[0] not in raw_ids
        assert ids[0] not in seam_ids
        assert ids[0] not in exact_module_ids
        exact_module_ids.add(ids[0])

    assert _requires(TOKEN) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../net/http-target.f",
        "../security/oauth2/client-config.f",
        "../security/oauth2/authorization-code.f",
        "../security/oauth2/http-post.f",
        "../security/oauth2/error-response.f",
        "../security/oauth2/token-request.f",
        "../security/oauth2/dpop-nonce.f",
        "oauth-profile.f",
        "oauth-client.f",
        "oauth-grant.f",
    ]
    assert _requires(TOKEN_P256) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../security/credential-vault.f",
        "../security/oauth2/client-config.f",
        "../security/oauth2/http-post.f",
        "../security/oauth2/token-request.f",
        "../security/oauth2/dpop-nonce.f",
        "../security/oauth2/key-p256.f",
        "oauth-profile.f",
        "oauth-client.f",
        "oauth-token.f",
    ]
    for source, label in (
        (raw_token, "raw AT token adapter"),
        (p256_token, "AT token P-256 wrapper"),
    ):
        assert not re.search(
            r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
            source,
        ), f"{label} must own no mutable module-global state"

    for marker in (
        "AT-OAUTH-TOKEN-WORKSPACE-SIZE",
        "AT-OAUTH-TOKEN-WORKSPACE-CLEAR",
        "AT-OAUTH-TOKEN-PREPARE",
        "AT-OAUTH-TOKEN-BUILD",
        "AT-OAUTH-TOKEN-ACCEPT-NONCE-CHALLENGE",
        "AT-OAUTH-TOKEN-ACCEPT-SUCCESS",
        "O2TREQ-CAPTURE",
        "O2TREQ-CLAIM-RETRY",
        "O2TREQ-TERMINAL",
        "OAUTH2-DPOP-NONCE-REPLACE",
        'S" use_dpop_nonce"',
        "AT-OAUTH-GRANT-WITH",
    ):
        assert marker in raw_token
    for marker in (
        "AT-OAUTH-TOKEN-P256-INPUT-SIZE",
        "AT-OAUTH-TOKEN-P256-I.IAT",
        "AT-OAUTH-TOKEN-P256-I.VAULT",
        "AT-OAUTH-TOKEN-P256-I.CONFIG",
        "AT-OAUTH-TOKEN-P256-I.PROFILE",
        "AT-OAUTH-TOKEN-P256-I.TOKEN-REQUEST",
        "AT-OAUTH-TOKEN-P256-I.NONCE-OWNER",
        "AT-OAUTH-TOKEN-P256-I.POST",
        "AT-OAUTH-TOKEN-P256-I.REQUEST-A",
        "AT-OAUTH-TOKEN-P256-I.REQUEST-CAP",
        "AT-OAUTH-TOKEN-P256-I.FORM-A",
        "AT-OAUTH-TOKEN-P256-I.FORM-CAP",
        "AT-OAUTH-TOKEN-P256-I.RESPONSE-A",
        "AT-OAUTH-TOKEN-P256-I.RESPONSE-CAP",
        "AT-OAUTH-TOKEN-P256-INPUT-CLEAR",
        "AT-OAUTH-TOKEN-P256-WORKSPACE-SIZE",
        "AT-OAUTH-TOKEN-P256-WORKSPACE-CLEAR",
        "AT-OAUTH-TOKEN-P256-BUILD",
    ):
        assert marker in p256_token
    for forbidden in ("_ATOT", "_O2PK", "_O2DN", "_O2TRQ", "_O2HP."):
        assert forbidden not in p256_token

    prepare = _word_body(raw_token, "AT-OAUTH-TOKEN-PREPARE")
    assert prepare.index("_ATOT-PREPARE-GEOMETRY") < prepare.index(
        "_ATOT-PREPARE-OP"
    )
    assert "_ATOTW-RAN" not in raw_token
    for sentinel in (
        "_ATOT-CB-PREPARE",
        "_ATOT-CB-BUILD-ERROR",
        "_ATOT-CB-RESPONSE",
    ):
        assert sentinel in raw_token
    prepare_callback = _word_body(raw_token, "_ATOT-PREPARE-VALIDATE")
    assert "14 PICK 14 PICK" not in prepare_callback
    build_geometry = _word_body(raw_token, "_ATOT-BUILD-GEOMETRY")
    assert re.search(
        r"6 PICK 6 PICK\s+4 PICK O2TREQ-SIZE MSPAN-OVERLAP\?",
        build_geometry,
    )
    build_callback = _word_body(raw_token, "_ATOT-BUILD-CALLBACK")
    assert "14 PICK 14 PICK" not in build_callback
    assert "_ATOTW.CORRELATION _ATOT-CORRELATION-SIZE" in (
        build_callback
    )
    for field in (
        'S" grant_type" S" authorization_code"',
        'S" code"',
        'S" redirect_uri"',
        'S" client_id"',
        'S" code_verifier"',
    ):
        assert field in build_callback
    assert build_callback.index("OAUTH2-HTTP-POST-BEGIN") < (
        build_callback.index("OAUTH2-HTTP-POST-SEAL")
    )
    correlation = _word_body(raw_token, "_ATOT-CORRELATION-STATUS")
    assert "_ATOTW.CORRELATION _ATOT-CORRELATION-SIZE" in correlation
    challenge_callback = _word_body(
        raw_token,
        "_ATOT-CHALLENGE-PROVENANCE",
    )
    success_callback = _word_body(
        raw_token,
        "_ATOT-SUCCESS-PROVENANCE",
    )
    assert "10 PICK 10 PICK" not in challenge_callback
    assert "10 PICK 10 PICK" not in success_callback
    challenge_policy = _word_body(raw_token, "_ATOT-CHALLENGE-POLICY")
    for marker in (
        "OAUTH2-HTTP-POST-O-OAUTH-ERROR",
        "400 <>",
        "401 <>",
        "_ATOT-CHALLENGE-ERROR",
        "_ATOT-ROTATE-NONCE",
    ):
        assert marker in challenge_policy
    challenge_finish = _word_body(raw_token, "_ATOT-CHALLENGE-FINISH")
    assert challenge_finish.index("O2TREQ-CLAIM-RETRY") < (
        challenge_finish.index("AT-OAUTH-TOKEN-S-RETRY")
    )
    success_policy = _word_body(raw_token, "_ATOT-SUCCESS-POLICY")
    assert success_policy.index("_ATOT-ROTATE-NONCE") < (
        success_policy.index("_ATOT-SUCCESS-GRANT")
    )
    success_finish = _word_body(raw_token, "_ATOT-SUCCESS-FINISH")
    assert "O2TREQ-TERMINAL" in success_finish

    p256_operation = _word_body(p256_token, "_ATTP-OP")
    assert p256_operation.index("_ATTP-ADMIT-CONFIG") < (
        p256_operation.index("_ATTP-WITH-NONCE")
    )
    nonce_callback = _word_body(p256_token, "_ATTP-NONCE-CALLBACK")
    for earlier, later in (
        ("_ATTP-CONFIGURE-POST", "_ATTP-POST-GEOMETRY"),
        ("_ATTP-POST-GEOMETRY", "_ATTP-PREPARE-DPOP-INPUT"),
        ("_ATTP-PREPARE-DPOP-INPUT", "_ATTP-SIGN"),
        ("_ATTP-SIGN", "_ATTP-RAW-BUILD"),
    ):
        assert nonce_callback.index(earlier) < nonce_callback.index(later)
    dpop_input = _word_body(p256_token, "_ATTP-PREPARE-DPOP-INPUT")
    assert 'S" POST"' in dpop_input
    assert "OAUTH2-P256-KEY-DPOP-I.NONCE-A" in dpop_input
    assert "OAUTH2-P256-KEY-DPOP-I.TOKEN-A" in dpop_input

    assert "PROVIDED akashic-oauth2-trequest" in token_request
    assert "PROVIDED akashic-oauth2-dpnonce" in nonce
    assert _requires(CONTRACT) == ["at-oauth-authz-test.f"]
    assert _requires(SESSION_CONTRACT) == ["at-token-p256-test.f"]
    for marker in (
        "PROVIDED at-token-p256-test",
        "_ATTT-PREPARE",
        "_ATTT-FIRST-BUILD",
        "_ATTT-CHALLENGE",
        "_ATTT-RETRY-BUILD",
        "_ATTT-SUCCESS",
        "_ATTT-FINISH",
        "use_dpop_nonce",
        "par-nonce-1",
        "token-nonce-2",
        "token-nonce-3",
        "_O2PKD-DPOP-CALLS",
        "_ATTT-FIRST-IAT",
        "_ATTT-RETRY-IAT",
        "_attt-retry-post",
        "_attt-correlation-attempt-at?",
        "O2TREQ-ATTEMPT-FIRST",
        "O2TREQ-ATTEMPT-RETRY",
        "O2TREQ-PHASE-TERMINAL",
        "_attt-terminal-payload-zero?",
        "AT TOKEN P256 PASS",
    ):
        assert marker in fixture
    assert _word_count(fixture, "AT-OAUTH-TOKEN-PREPARE") == 1
    assert _word_count(fixture, "AT-OAUTH-TOKEN-P256-BUILD") == 1
    assert _word_count(fixture, "_attt-build-p256") == 3
    assert _word_count(
        fixture, "AT-OAUTH-TOKEN-ACCEPT-NONCE-CHALLENGE"
    ) == 1
    assert _word_count(fixture, "AT-OAUTH-TOKEN-ACCEPT-SUCCESS") == 1
    assert _word_count(fixture, "_attt-exchange") == 3
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        _forth_code(fixture),
    ), "focused fixture must not borrow the DO-loop return stack"
    for marker in (
        "PROVIDED at-session-install-test",
        "_ATSI-SETUP",
        "_ATSI-SUCCESS-INSTALL",
        "_ATSI-REOPEN",
        "_ATSI-FINISH",
        "O2SESSION-RECORD-SIZE CVAULT-BACKING-SIZE",
        "OAUTH2-CLIENT-CONFIG-BINDING@",
        "AT-OAUTH-PROFILE-ISSUER@",
        "O2SESSION-INSTALL",
        "O2SESSION-OPEN",
        "O2SESSION-PHASE-ACTIVE",
        "O2SESSION-WITH-ACCESS",
        "O2SESSION-WITH-TOKEN-TYPE",
        "O2SESSION-WITH-SCOPE",
        PASS_MARKER,
    ):
        assert marker in session_fixture
    assert "O2SESSION-RECOVER" not in session_fixture
    assert "O2SESSION-REFRESH-" not in session_fixture
    assert 'S" /vault"' in session_fixture
    assert 'S" /session-vault"' not in session_fixture
    assert _word_count(session_fixture, "O2SESSION-INSTALL") == 1
    assert _word_count(session_fixture, "O2SESSION-OPEN") == 1
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        _forth_code(session_fixture),
    ), "session continuation must not borrow the DO-loop return stack"
    stage_names = [name for name, _, _, _ in RUNTIME_STAGES]
    assert stage_names.index("retry-build") < stage_names.index(
        "session-setup"
    )
    assert stage_names.index("session-setup") < stage_names.index(
        "success-install"
    )
    assert stage_names.index("success-install") < stage_names.index(
        "session-reopen"
    )

    # The deterministic seam exposes proof invocations and every proof input.
    # Real JTI entropy/signature construction remains covered by the exact
    # standalone DPoP qualification.
    for marker in (
        "PROVIDED akashic-oauth2-dpop256",
        "_O2PKD-DPOP-CALLS",
        "_O2PKD-DPOP-IAT",
        "_O2PKD-DPOP-NONCE-A",
        "deterministic-dpop-proof",
    ):
        assert marker in P256_JWK_DOUBLES

    for module in RAW_MODULES:
        path = SOURCE_ROOT / module
        _assert_physical_comments(
            path,
            path.read_text(encoding="utf-8"),
        )
    for path in (
        VAULT,
        KEY_OWNER,
        PAR_WRAPPER,
        AUTHORIZATION,
        *(path for _, _, path in TOKEN_MODULES),
        *FIXTURES,
    ):
        _assert_physical_comments(
            path,
            path.read_text(encoding="utf-8"),
        )


def _packed(path: Path, *, remove_requires: bool = False) -> bytes:
    return harness._minify_forth(  # noqa: SLF001
        path.read_text(encoding="utf-8"),
        remove_requires=remove_requires,
    ).encode("utf-8")


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - public AT token nonce-retry vertical\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, guest, marker, _ in (
        *RAW_LOAD_STAGES,
        *OWNER_LOAD_STAGES,
        *TOKEN_LOAD_STAGES,
        *FIXTURE_LOAD_STAGES,
    ):
        lines.extend(
            (
                f"REQUIRE {guest}\n",
                (
                    'DEPTH IF ." AT TOKEN LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker, _ in RUNTIME_STAGES:
        lines.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    lines.append("_ATSI-FINISH\nTX-FLUSH\n")
    return "".join(lines)


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    seam_source = CV_DEPS.read_text(encoding="utf-8")
    seam_source += "\n"
    seam_source += P256_JWK_DOUBLES
    owner_files = (
        (
            OWNER_MODULES[0][1],
            harness._minify_forth(seam_source).encode("utf-8"),
        ),
        (OWNER_MODULES[1][1], _packed(VAULT, remove_requires=True)),
        (OWNER_MODULES[2][1], _packed(KEY_OWNER, remove_requires=True)),
        (OWNER_MODULES[3][1], _packed(PAR_WRAPPER, remove_requires=True)),
        (
            OWNER_MODULES[4][1],
            _packed(AUTHORIZATION, remove_requires=True),
        ),
    )
    return (
        tuple(
            (
                guest,
                harness._minify_forth(  # noqa: SLF001
                    (SOURCE_ROOT / module).read_text(encoding="utf-8"),
                    remove_requires=True,
                ).encode("utf-8"),
            )
            for guest, module in PACKED_RAW
        )
        + owner_files
        + tuple(
            (guest, _packed(path, remove_requires=True))
            for _, guest, path in TOKEN_MODULES
        )
        + tuple(
            (
                f"local_testing/{fixture.name}",
                _packed(fixture),
            )
            for fixture in FIXTURES
        )
    )


def _run_vertical(timeout: float) -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=_initial_files(),
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
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        stages = (
            *RAW_LOAD_STAGES,
            *OWNER_LOAD_STAGES,
            *TOKEN_LOAD_STAGES,
            *FIXTURE_LOAD_STAGES,
            *RUNTIME_STAGES,
        )
        for index, (stage_name, _, marker, stage_steps) in enumerate(
            stages
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
            raw_text = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw_text),  # noqa: SLF001
                        *harness._matched_failure_markers(  # noqa: SLF001
                            profile,
                            raw_text,
                            machine.screen_text(),
                        ),
                    )
                )
            )
            reports.append((stage_name, report))
            if marker not in raw_text or failures:
                print(f"AT SESSION P256 {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-4000:])
                return 1
            print(
                f"AT SESSION P256 {stage_name}: PASS "
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
        raw_text = machine.raw_text()
        failures = tuple(
            dict.fromkeys(
                (
                    *harness._has_forth_error(raw_text),  # noqa: SLF001
                    *harness._matched_failure_markers(  # noqa: SLF001
                        profile,
                        raw_text,
                        machine.screen_text(),
                    ),
                )
            )
        )
        ok = PASS_MARKER in raw_text and not failures
        print(f"AT SESSION P256 vertical: {'PASS' if ok else 'FAIL'}")
        for stage_name, stage_report in reports:
            print(
                f"  {stage_name}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; "
                f"stop={stage_report.reason}"
            )
        print(
            f"  finish: {report.steps:,} steps in "
            f"{report.elapsed_s:.2f}s; stop={report.reason}"
        )
        if not ok:
            for failure in failures:
                print(f"  {failure}")
            print(raw_text[-4000:])
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--static-only",
        action="store_true",
        help="check the focused source/fixture/packaging contracts",
    )
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run token exchange through durable session install/reopen",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("AT SESSION P256 STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
