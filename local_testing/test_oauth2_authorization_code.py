#!/usr/bin/env python3
"""Static and linked qualification for generic OAuth authorization attempts."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from forth_dependencies import dependency_closure  # noqa: E402


PROFILE = "oauth2-authorization-code-contracts"
IMAGE = Path("/tmp/akashic-oauth2-authorization-code-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-authorization-code-test.f"
SOURCE_ROOT = LOCAL_TESTING.parent / "akashic"
SOURCE = SOURCE_ROOT / "security" / "oauth2" / "authorization-code.f"

AUTOEXEC = r"""\ autoexec.f - generic OAuth authorization-code contracts
ENTER-USERLAND
." OAUTH2 AUTHORIZATION CODE LOAD START" CR TX-FLUSH
REQUIRE security/oauth2/authorization-code.f
." OAUTH2 AUTHORIZATION CODE SOURCE READY" CR TX-FLUSH
REQUIRE local_testing/oauth2-authcode-test.f
." OAUTH2 AUTHORIZATION CODE FIXTURE READY" CR TX-FLUSH
_O2CT-RUN
"""


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "KDOS parenthesized comments must close on their physical "
                f"line: {path}:{line_number}"
            )


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    lowered = source.lower()

    assert "PROVIDED akashic-oauth2-authcode" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "transaction and operation state must remain caller-owned"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert "../../utils/memory-span.f" in requires
    assert "../../utils/caller-span.f" in requires
    assert "../../net/form-urlencoded.f" in requires
    assert "../../math/entropy.f" in requires
    assert "../jose/base64url.f" in requires
    assert "pkce.f" in requires

    for forbidden in (
        "atproto/",
        "streams/",
        "tui/",
        "xrpc",
        "session.f",
        "repo.f",
        "http-client",
    ):
        assert forbidden not in lowered
    assert not re.search(r"(?i)\b(?:v2|compat(?:ibility)?)\b", source)

    closure = set(
        dependency_closure(
            SOURCE_ROOT,
            ("security/oauth2/authorization-code.f",),
        )
    )
    assert {
        "security/oauth2/authorization-code.f",
        "security/oauth2/pkce.f",
        "net/form-urlencoded.f",
        "math/entropy.f",
        "math/sha256.f",
        "math/crypto-acc.f",
    } <= closure

    for word in (
        "O2CODE-TRANSACTION-SIZE",
        "O2CODE-WORKSPACE-SIZE",
        "O2CODE-STATUS-VALID?",
        "O2CODE-INIT?",
        "O2CODE-INIT",
        "O2CODE-CLEAR?",
        "O2CODE-CLEAR",
        "O2CODE-PHASE@",
        "O2CODE-ERROR@",
        "O2CODE-PREPARE",
        "O2CODE-WITH-PAR",
        "O2CODE-ACCEPT-PAR",
        "O2CODE-WITH-LAUNCH",
        "O2CODE-ACCEPT-CALLBACK",
        "O2CODE-WITH-GRANT",
        "O2CODE-WORKSPACE-CLEAR",
    ):
        assert word in source

    for status in (
        "O2CODE-S-OK",
        "O2CODE-S-INVALID",
        "O2CODE-S-CAPACITY",
        "O2CODE-S-ALIAS",
        "O2CODE-S-PHASE",
        "O2CODE-S-BUSY",
        "O2CODE-S-EXPIRED",
        "O2CODE-S-OVERFLOW",
        "O2CODE-S-ENCODING",
        "O2CODE-S-DUPLICATE",
        "O2CODE-S-MISSING",
        "O2CODE-S-STATE",
        "O2CODE-S-ISSUER",
        "O2CODE-S-RESPONSE",
        "O2CODE-S-DENIED",
        "O2CODE-S-CALLBACK",
        "O2CODE-S-ENTROPY",
        "O2CODE-S-CRYPTO",
        "O2CODE-S-RANGE",
        "O2CODE-S-PROTECTED",
        "O2CODE-S-PLATFORM",
        "O2CODE-S-INTERNAL",
    ):
        assert status in source

    for phase in (
        "O2CODE-PHASE-EMPTY",
        "O2CODE-PHASE-PREPARED",
        "O2CODE-PHASE-PAR-READY",
        "O2CODE-PHASE-AWAITING",
        "O2CODE-PHASE-CODE-READY",
        "O2CODE-PHASE-DENIED",
        "O2CODE-PHASE-SPENT",
    ):
        assert phase in source

    assert re.search(r"(?m)^43 CONSTANT O2CODE-STATE-SIZE$", source)
    assert re.search(r"(?m)^43 CONSTANT O2CODE-VERIFIER-SIZE$", source)
    assert re.search(r"(?m)^43 CONSTANT O2CODE-CHALLENGE-SIZE$", source)
    assert re.search(
        r"(?m)^7 \+ -8 AND CONSTANT O2CODE-TRANSACTION-SIZE$",
        source,
    )
    assert re.search(
        r"(?m)^14760 CONSTANT O2CODE-WORKSPACE-SIZE$", source,
    )
    assert re.search(
        r"(?m)^16384 CONSTANT O2CODE-CALLBACK-QUERY-CAPACITY$",
        source,
    )

    assert "_O2CW.RAW-STATE" in source
    assert "ENTROPY-FILL" in source
    assert "JOSE-B64URL-ENCODE" in source
    assert "OAUTH2-PKCE-GENERATE" in source
    assert "FORM-URLENCODED-DECODE" in source
    assert "MSPAN-OVERLAP?" in source

    object_layout = source[
        source.index("Address-free transaction object") :
        source.index("Caller-owned transient workspace")
    ]
    for raw_pointer_field in (
        "_O2C-BINDING-A",
        "_O2C-ISSUER-A",
        "_O2C-REQUEST-URI-A",
        "_O2C-CODE-A",
        "_O2C-ERROR-A",
        "_O2C-DESCRIPTION-A",
    ):
        assert raw_pointer_field not in object_layout

    prepare_geometry = _word_body(source, "_O2C-PREPARE-GEOMETRY")
    assert prepare_geometry.count("_O2C-ADMIT-SPAN") == 2
    assert prepare_geometry.count("MSPAN-OVERLAP?") == 5
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        prepare_geometry,
    ), "PREPARE geometry must not mutate caller storage"
    generate_state = _word_body(source, "_O2C-GENERATE-STATE")
    assert generate_state.index("ENTROPY-FILL") < generate_state.index(
        "JOSE-B64URL-ENCODE"
    )
    assert "OAUTH2-PKCE-GENERATE" in _word_body(
        source, "_O2C-GENERATE-PKCE"
    )
    prepare_operation = _word_body(source, "_O2C-PREPARE-OP")
    assert prepare_operation.index("_O2C-GENERATE-STATE") < (
        prepare_operation.index("_O2C-GENERATE-PKCE")
    )
    assert prepare_operation.index("_O2C-GENERATE-PKCE") < (
        prepare_operation.index("_O2C-PUBLISH-PREPARED")
    )
    assert ">R _O2C-DROP6 R>" in _word_body(
        source, "_O2C-BIND-PREPARE"
    )
    prepare_call = _word_body(source, "_O2C-PREPARE-CALL")
    assert prepare_call.index("CATCH") < prepare_call.index(
        "_O2C-WIPE-WORKSPACE"
    )
    assert prepare_call.count("_O2C-WIPE-WORKSPACE") >= 2
    prepare_public = _word_body(source, "O2CODE-PREPARE")
    assert prepare_public.index("_O2C-PREPARE-GEOMETRY") < (
        prepare_public.index("_O2C-PREPARE-CALL")
    )

    accept_par_geometry = _word_body(
        source, "_O2C-ACCEPT-PAR-GEOMETRY"
    )
    assert accept_par_geometry.count("_O2C-ADMIT-SPAN") == 3
    assert "O2CODE-MAX-PAR-EXPIRES-IN" in accept_par_geometry
    assert "_O2C-CELL-MAX" in accept_par_geometry
    assert "O2CODE-S-OVERFLOW" in accept_par_geometry
    assert accept_par_geometry.count("MSPAN-OVERLAP?") == 3
    assert "_O2C-PAR-ISSUER-MATCH?" in accept_par_geometry
    assert "_O2C-PAR-CORRELATION-MATCH?" in accept_par_geometry
    assert "O2CODE-S-ISSUER" in accept_par_geometry
    assert "O2CODE-S-STATE" in accept_par_geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        accept_par_geometry,
    ), "ACCEPT-PAR geometry must not mutate the transaction"
    accept_par = _word_body(source, "O2CODE-ACCEPT-PAR")
    assert accept_par.index("_O2C-10DUP") < (
        accept_par.index("_O2C-ACCEPT-PAR-GEOMETRY")
    )
    assert accept_par.index("_O2C-ACCEPT-PAR-GEOMETRY") < (
        accept_par.index("MOVE")
    )
    assert "2DUP +" in accept_par

    callback_run = _word_body(source, "_O2C-PAR-CALLBACK-RUN")
    assert "DEPTH" in callback_run
    assert "EXECUTE" in callback_run
    for retained_field in (
        "_O2C.BINDING",
        "_O2C.ISSUER",
        "_O2C.ISSUER-U @",
        "_O2C.ISSUER-REQUIRED @",
        "_O2C.STATE",
        "_O2C.CHALLENGE",
    ):
        assert retained_field in callback_run
    assert callback_run.index("_O2C.BINDING") < (
        callback_run.index("_O2C.ISSUER")
    )
    assert callback_run.index("_O2C.ISSUER-REQUIRED @") < (
        callback_run.index("_O2C.STATE")
    )
    par_borrow = _word_body(source, "_O2C-WITH-PAR-CALL")
    assert par_borrow.index("-1 R@ _O2C.BORROWED !") < (
        par_borrow.index("CATCH")
    )
    assert par_borrow.count("0 R@ _O2C.BORROWED !") >= 2
    launch_status = _word_body(source, "_O2C-LAUNCH-STATUS")
    assert "_O2C.DEADLINE @" in launch_status
    assert "U< 0=" in launch_status
    launch_call = _word_body(source, "_O2C-WITH-LAUNCH-CALL")
    assert launch_call.index("O2CODE-PHASE-AWAITING") < (
        launch_call.index("CATCH")
    )
    assert launch_call.count("_O2C-FINISH-LAUNCH") >= 2
    finish_launch = _word_body(source, "_O2C-FINISH-LAUNCH")
    assert (
        "_O2C.REQUEST-URI O2CODE-REQUEST-URI-CAPACITY 0 FILL"
        in finish_launch
    )
    assert "_O2C.DEADLINE" not in finish_launch

    callback_geometry = _word_body(source, "_O2C-CALLBACK-GEOMETRY")
    assert callback_geometry.count("_O2C-ADMIT-SPAN") == 1
    assert callback_geometry.count("MSPAN-OVERLAP?") == 3
    assert "O2CODE-CALLBACK-QUERY-CAPACITY" in callback_geometry
    assert not re.search(
        r"(?<![A-Za-z0-9_-])(?:C!|W!|!|MOVE|FILL)"
        r"(?![A-Za-z0-9_-])",
        callback_geometry,
    ), "callback geometry must not mutate object or workspace"

    decode_name = _word_body(source, "_O2C-DECODE-NAME")
    assert decode_name.index("FORM-URLENCODED-DECODE") < (
        decode_name.index("_O2C-NAME-DUPLICATE?")
    )
    assert "_O2C-STORE-NAME-DESCRIPTOR" in decode_name
    process_value = _word_body(source, "_O2C-PROCESS-VALUE")
    for parameter in (
        'S" code"',
        'S" state"',
        'S" iss"',
        'S" error"',
        'S" error_description"',
    ):
        assert parameter in process_value
    assert "_O2C-VALIDATE-UNKNOWN-VALUE" in process_value
    assert "FORM-URLENCODED-DECODE-MEASURE" in _word_body(
        source, "_O2C-VALIDATE-UNKNOWN-VALUE"
    )

    validate_state = _word_body(source, "_O2C-VALIDATE-STATE")
    assert "O2CODE-STATE-SIZE <>" in validate_state
    assert "_O2C-CT-BYTES=" in validate_state
    validate_issuer = _word_body(source, "_O2C-VALIDATE-ISSUER")
    assert "_O2C.ISSUER-REQUIRED @" in validate_issuer
    assert "_O2C.ISSUER-U @" in validate_issuer
    assert "COMPARE 0=" in validate_issuer
    response_kind = _word_body(source, "_O2C-RESPONSE-KIND")
    assert "_O2C-P-CODE" in response_kind
    assert "_O2C-P-ERROR" in response_kind
    assert "_O2C-P-DESCRIPTION" in response_kind

    validate_publish = _word_body(
        source, "_O2C-VALIDATE-AND-PUBLISH"
    )
    assert validate_publish.index("_O2C-VALIDATE-STATE") < (
        validate_publish.index("_O2C-VALIDATE-ISSUER")
    )
    assert validate_publish.index("_O2C-VALIDATE-ISSUER") < (
        validate_publish.index("_O2C-RESPONSE-KIND")
    )
    assert "_O2C-PUBLISH-CODE" in validate_publish
    assert "_O2C-PUBLISH-DENIAL" in validate_publish
    denial_wipe = _word_body(source, "_O2C-WIPE-DENIED-SECRETS")
    for secret_region in (
        "_O2C.STATE",
        "_O2C.VERIFIER",
        "_O2C.CHALLENGE",
        "_O2C.REQUEST-URI",
        "_O2C.CODE",
    ):
        assert secret_region in denial_wipe
    callback_call = _word_body(source, "_O2C-CALLBACK-CALL")
    assert callback_call.index("CATCH") < callback_call.index(
        "_O2C-WIPE-WORKSPACE"
    )
    assert callback_call.count("_O2C-WIPE-WORKSPACE") >= 2
    accept_callback = _word_body(source, "O2CODE-ACCEPT-CALLBACK")
    assert accept_callback.index("_O2C-CALLBACK-GEOMETRY") < (
        accept_callback.index("_O2C-CALLBACK-CALL")
    )
    assert ">R _O2C-DROP3 R>" in _word_body(
        source, "_O2C-BIND-CALLBACK"
    )

    grant_callback = _word_body(source, "_O2C-GRANT-CALLBACK-RUN")
    assert "DEPTH" in grant_callback
    assert "EXECUTE" in grant_callback
    finish_grant = _word_body(source, "_O2C-FINISH-GRANT")
    for wiped_region in (
        "_O2C.STATE",
        "_O2C.VERIFIER",
        "_O2C.CHALLENGE",
        "_O2C.CODE",
    ):
        assert wiped_region in finish_grant
    grant_call = _word_body(source, "_O2C-WITH-GRANT-CALL")
    assert grant_call.index("O2CODE-PHASE-SPENT") < grant_call.index(
        "CATCH"
    )
    assert grant_call.count("_O2C-FINISH-GRANT") >= 2
    assert "O2CODE-PHASE-CODE-READY" in _word_body(
        source, "O2CODE-WITH-GRANT"
    )

    for compile_gate in (
        "1 CELLS 8 <> [IF]",
        "O2CODE-TRANSACTION-SIZE <> [IF]",
        "O2CODE-WORKSPACE-SIZE <> [IF]",
        "_O2C-GEOMETRY-ABORT",
    ):
        assert compile_gate in source

    fixture_markers = (
        "_o2ct-test-prepare-entropy-and-pkce",
        "_o2ct-test-prepare-preflight-and-throw",
        "_o2ct-test-par-borrow",
        "_o2ct-test-accept-par",
        "_o2ct-accept-par-required",
        "_o2ct-seen-issuer-required",
        "_o2ct-test-launch-one-shot",
        "_o2ct-test-callback-rejections-and-success",
        "_o2ct-test-issuer-optional",
        "_o2ct-test-denial-diagnostics",
        "_o2ct-test-callback-geometry-and-throw",
        "_o2ct-test-grant-one-shot",
        "_o2ct-build-malformed-escape",
        "_o2ct-build-decoded-duplicate",
        "_o2ct-build-unknown-decoded-duplicate",
        "O2CODE-S-OVERFLOW",
        "O2CODE-S-EXPIRED",
        "O2CODE-S-DENIED",
        "O2CODE-PHASE-AWAITING",
        "O2CODE-PHASE-SPENT",
        "_o2ct-work-zero?",
        "_o2ct-work-filled?",
        "_o2ct-object-unchanged?",
    )
    for marker in fixture_markers:
        assert marker in fixture

    for module in sorted(closure):
        module_path = SOURCE_ROOT / module
        _assert_physical_comments(
            module_path,
            module_path.read_text(encoding="utf-8"),
        )
    _assert_physical_comments(CONTRACT, fixture)
    assert not re.search(
        r"(?mi)\b(?:\?DO|DO|\+LOOP|LOOP)\b", fixture
    ), "the fixture must use cursor walks rather than indexed loops"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--static-only",
        action="store_true",
        help="check source and fixture contracts without running an image",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("OAUTH2 AUTHORIZATION CODE STATIC PASS")
        return 0

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/authorization-code.f",),
        resources=(),
        autoexec=AUTOEXEC,
        ready_markers=("OAUTH2 AUTHORIZATION CODE PASS",),
        stable_markers=("OAUTH2 AUTHORIZATION CODE PASS",),
        failure_markers=(
            "OAUTH2 AUTHORIZATION CODE FAIL",
            "OAUTH2 AUTHORIZATION CODE ASSERT",
            "OAUTH2 AUTHORIZATION CODE STATUS",
            "OAUTH2 AUTHORIZATION CODE STACK",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-authcode-test.f",
                CONTRACT.read_bytes(),
            ),
        ),
        linked=True,
        include_large_sample=False,
        total_sectors=4096,
    )
    image = harness.build_image(PROFILE, IMAGE)
    ok = harness.smoke(
        PROFILE,
        image,
        cols=120,
        rows=44,
        max_steps=250_000_000,
        timeout=args.timeout,
        ext_mem_mib=128,
    )
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
