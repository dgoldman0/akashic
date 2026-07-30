#!/usr/bin/env python3
"""Qualify the minimal public-client AT Protocol PAR vertical slice."""

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


PROFILE = "at-oauth-par-vertical"
IMAGE = Path("/tmp/akashic-at-oauth-par-vertical.img")
SOURCE = SOURCE_ROOT / "atproto" / "oauth-par.f"
O2CODE_SOURCE = SOURCE_ROOT / "security" / "oauth2" / "authorization-code.f"
HTTP_POST_SOURCE = SOURCE_ROOT / "security" / "oauth2" / "http-post.f"
PROFILE_FIXTURE = LOCAL_TESTING / "at-oauth-prof-test.f"
CLIENT_FIXTURE = LOCAL_TESTING / "at-oauth-client-test.f"
HTTP_COMMON = LOCAL_TESTING / "o2-http-post-common.f"
CONTRACT = LOCAL_TESTING / "at-oauth-par-test.f"
FIXTURES = (
    PROFILE_FIXTURE,
    CLIENT_FIXTURE,
    HTTP_COMMON,
    CONTRACT,
)

PASS_MARKER = "AT OAUTH PAR PASS"
LOAD_PHASE_STEPS = 180_000_000
RUNTIME_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

LOAD_MODULES = dependency_order(
    SOURCE_ROOT,
    ("atproto/oauth-par.f",),
)
PACKED_MODULES = tuple(
    (f"local_testing/atpar-{index:02d}.f", module)
    for index, module in enumerate(LOAD_MODULES, start=1)
)
LOAD_STAGES = tuple(
    (
        f"load-{index:02d}",
        packed_path,
        f"AT OAUTH PAR LOAD {index:02d} READY",
        LOAD_PHASE_STEPS,
    )
    for index, (packed_path, _) in enumerate(PACKED_MODULES, start=1)
)
FIXTURE_LOAD_STAGES = tuple(
    (
        f"fixture-{index:02d}",
        f"local_testing/{fixture.name}",
        f"AT OAUTH PAR FIXTURE {index:02d} READY",
        LOAD_PHASE_STEPS,
    )
    for index, fixture in enumerate(FIXTURES, start=1)
)
RUNTIME_STAGES = (
    (
        "setup",
        "_ATPART-INIT",
        "AT OAUTH PAR SETUP READY",
        RUNTIME_PHASE_STEPS,
    ),
    (
        "rejections",
        "_ATPART-TEST-REJECTIONS",
        "AT OAUTH PAR REJECTIONS READY",
        RUNTIME_PHASE_STEPS,
    ),
    (
        "build",
        "_ATPART-TEST-BUILD",
        "AT OAUTH PAR BUILD READY",
        RUNTIME_PHASE_STEPS,
    ),
    (
        "accept",
        "_ATPART-TEST-ACCEPT",
        "AT OAUTH PAR ACCEPT READY",
        RUNTIME_PHASE_STEPS,
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
    o2code = O2CODE_SOURCE.read_text(encoding="utf-8")
    http_post = HTTP_POST_SOURCE.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    forth_code = "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    ).lower()

    all_stages = (
        *LOAD_STAGES,
        *FIXTURE_LOAD_STAGES,
        *RUNTIME_STAGES,
    )
    assert 0 < FINISH_STEPS <= RUNTIME_PHASE_STEPS
    assert all(
        0 < stage_steps <= LOAD_PHASE_STEPS
        for _, _, _, stage_steps in all_stages
    )
    assert len({name for name, _, _, _ in all_stages}) == len(all_stages)
    assert len({marker for _, _, marker, _ in all_stages}) == len(
        all_stages
    )
    assert LOAD_MODULES[-1] == "atproto/oauth-par.f"
    assert len(PACKED_MODULES) == len(LOAD_STAGES)
    for packed_path, _ in PACKED_MODULES:
        assert len(Path(packed_path).name.encode("utf-8")) <= 23
    for fixture_path in FIXTURES:
        assert len(fixture_path.name.encode("utf-8")) <= 23

    assert _requires(SOURCE) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../net/http-target.f",
        "../security/oauth2/client-config.f",
        "../security/oauth2/authorization-code.f",
        "../security/oauth2/http-post.f",
        "../security/oauth2/par-response.f",
        "did.f",
        "handle.f",
        "oauth-profile.f",
        "oauth-client.f",
    ]
    assert "PROVIDED akashic-at-oauth-par" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "AT PAR composition must own no mutable module-global state"
    for forbidden in (
        "streams",
        "xrpc",
        "credential-vault",
        "key-p256",
        "browser",
        "session",
        "deployment",
    ):
        assert forbidden not in forth_code
    for private_prefix in (
        "_O2HP.",
        "_O2C.",
        "_O2CC",
        "_ATOP",
    ):
        assert private_prefix not in source

    for word in (
        "AT-OAUTH-PAR-WORKSPACE-SIZE",
        "AT-OAUTH-PAR-WORKSPACE-CLEAR",
        "AT-OAUTH-PAR-STATUS-VALID?",
        "AT-OAUTH-PAR-PREPARE",
        "AT-OAUTH-PAR-BUILD",
        "AT-OAUTH-PAR-ACCEPT",
        "AT-OAUTH-PAR-S-OK",
        "AT-OAUTH-PAR-S-ALIAS",
        "AT-OAUTH-PAR-S-BINDING",
        "AT-OAUTH-PAR-S-DPOP",
        "AT-OAUTH-PAR-S-TARGET",
        "AT-OAUTH-PAR-S-NONCE",
    ):
        assert word in source

    assert not re.search(
        r"(?m)^AT-OAUTH-PAR-WORKSPACE-SIZE[ \t]+\d+[ \t]+<>",
        source,
    ), "symbolically derived workspace size must not be hard-coded"
    assert "_ATPARW-CHILD-OFF _ATPARW-CHILD-SIZE +" in source
    assert "CONSTANT AT-OAUTH-PAR-WORKSPACE-SIZE" in source

    build_op = _word_body(source, "_ATPAR-BUILD-OP")
    assert build_op.index("_ATPAR-BUILD-POST-ARENAS") < build_op.index(
        "OAUTH2-CLIENT-CONFIG-WITH"
    )
    build_callback = _word_body(
        source,
        "_ATPAR-BUILD-PAR-CALLBACK",
    )
    assert build_callback.index(
        "_ATPAR-BORROWED-ISSUER-STATUS"
    ) < build_callback.index("OAUTH2-HTTP-POST-BEGIN")
    assert build_callback.index(
        "OAUTH2-HTTP-POST-CORRELATION!"
    ) < build_callback.index("_ATPAR-FIELD")
    assert "OAUTH2-HTTP-POST-FIELD" in _word_body(
        source,
        "_ATPAR-FIELD",
    )
    assert "OAUTH2-HTTP-POST-SEAL" in _word_body(
        source,
        "_ATPAR-SEAL",
    )

    accept_envelope = _word_body(source, "_ATPAR-ACCEPT-ENVELOPE")
    for marker in (
        "OAUTH2-HTTP-POST-CORRELATION@",
        "OAUTH2-HTTP-POST-DPOP-INCLUDED?",
        "OAUTH2-HTTP-POST-DPOP-SENT?",
        "OAUTH2-HTTP-POST-AUTHORIZATION-INCLUDED?",
        "OAUTH2-HTTP-POST-AUTHORIZATION-SENT?",
        "201",
        "OAUTH2-HTTP-POST-NONCE@",
    ):
        assert marker in accept_envelope
    accept_callback = _word_body(
        source,
        "_ATPAR-ACCEPT-PAR-CALLBACK",
    )
    assert accept_callback.index(
        "AT-OAUTH-PROFILE-ISSUER@"
    ) < accept_callback.index("OAUTH2-HTTP-POST-CORRELATION@")
    assert accept_callback.index(
        "OAUTH2-HTTP-POST-CORRELATION@"
    ) < accept_callback.index("O2CODE-ACCEPT-PAR")
    assert "_ATPAR-ACCEPT-POST-ARENAS" in _word_body(
        source,
        "AT-OAUTH-PAR-ACCEPT",
    )

    for public_api in (
        "OAUTH2-HTTP-POST-CORRELATION!",
        "OAUTH2-HTTP-POST-CORRELATION@",
        "OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS",
    ):
        assert public_api in http_post
    correlation_store = _word_body(
        http_post,
        "OAUTH2-HTTP-POST-CORRELATION!",
    )
    assert "OAUTH2-HTTP-POST-STATE-BUILDING" in correlation_store
    assert "_O2HP-CLEAR-CORRELATION" in correlation_store
    external_span = _word_body(
        http_post,
        "OAUTH2-HTTP-POST-EXTERNAL-SPAN-STATUS",
    )
    assert external_span.count("MSPAN-OVERLAP?") == 4

    par_loan = _word_body(o2code, "_O2C-PAR-CALLBACK-RUN")
    for marker in (
        "_O2C.ISSUER",
        "_O2C.ISSUER-U",
        "_O2C.ISSUER-REQUIRED",
        "_O2C.STATE",
        "_O2C.CHALLENGE",
    ):
        assert marker in par_loan
    accept_par = _word_body(o2code, "O2CODE-ACCEPT-PAR")
    assert "_O2C-ACCEPT-PAR-GEOMETRY" in accept_par
    accept_geometry = _word_body(o2code, "_O2C-ACCEPT-PAR-GEOMETRY")
    assert "_O2C-PAR-ISSUER-MATCH?" in accept_geometry
    assert "_O2C-PAR-CORRELATION-MATCH?" in accept_geometry
    assert accept_geometry.index(
        "_O2C-PAR-ISSUER-MATCH?"
    ) < accept_geometry.index("_O2C-PAR-CORRELATION-MATCH?")

    assert _requires(CONTRACT) == [
        "at-oauth-prof-test.f",
        "at-oauth-client-test.f",
        "o2-http-post-common.f",
    ]
    for marker in (
        "PROVIDED at-oauth-par-test",
        "_ATPART-INIT",
        "_ATPART-TEST-REJECTIONS",
        "_ATPART-TEST-BUILD",
        "_ATPART-TEST-ACCEPT",
        "_ATPART-FINISH",
        "AT-OAUTH-PAR-S-ALIAS",
        "AT-OAUTH-PAR-S-TARGET",
        "AT-OAUTH-PAR-S-BINDING",
        "OAUTH2-HTTP-POST-CORRELATION@",
        "OAUTH2-HTTP-POST-AUTHORIZATION-SENT?",
        "O2CODE-PHASE-PAR-READY",
        "Content-Length: 301",
        "DPoP: vertical-dpop-proof",
        "par-nonce-1",
        "_atpart-work-zero?",
        "_atpart-unchanged?",
    ):
        assert marker in fixture
    assert not re.search(
        r"(?mi)\b(?:_ATPAR(?:W|-)|_O2C[.]|_O2HP[.]|_O2CC|_ATOP)\b",
        "\n".join(
            line.split("\\", 1)[0] for line in fixture.splitlines()
        ),
    ), "fixture must use public production APIs"
    assert not re.search(
        r"(?mi)\b(?:DO|\?DO|LOOP|\+LOOP)\b",
        fixture,
    ), "focused fixture must not use return-stack loop indices"
    for broad_group in (
        "_atopt-test-",
        "_atoct-test-",
        "_O2HPT-RUN-",
        "_o2ct-test-",
    ):
        assert broad_group not in fixture

    for module in LOAD_MODULES:
        module_path = SOURCE_ROOT / module
        _assert_physical_comments(
            module_path,
            module_path.read_text(encoding="utf-8"),
        )
    for fixture_path in FIXTURES:
        _assert_physical_comments(
            fixture_path,
            fixture_path.read_text(encoding="utf-8"),
        )


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - staged AT OAuth public-client PAR vertical\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker, _ in LOAD_STAGES:
        lines.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH PAR LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for stage_name, module, marker, _ in FIXTURE_LOAD_STAGES:
        lines.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH PAR LOAD STACK FAIL '
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
    lines.append("_ATPART-FINISH\nTX-FLUSH\n")
    return "".join(lines)


def _run_vertical(timeout: float) -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT OAUTH PAR FAIL",
            "AT OAUTH PAR ASSERT",
            "AT OAUTH PAR STATUS",
            "AT OAUTH PAR STACK",
            "AT OAUTH PAR LOAD STACK FAIL",
            "AT OAUTH PROFILE ASSERT",
            "AT OAUTH PROFILE STATUS",
            "AT OAUTH CLIENT ASSERT",
            "AT OAUTH CLIENT STATUS",
            "OAUTH2 HTTP POST ASSERT",
            "OAUTH2 HTTP POST STATUS",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            tuple(
                (
                    packed_path,
                    harness._minify_forth(  # noqa: SLF001
                        (SOURCE_ROOT / module).read_text(encoding="utf-8"),
                        remove_requires=True,
                    ).encode("utf-8"),
                )
                for packed_path, module in PACKED_MODULES
            )
            + tuple(
                (
                    f"local_testing/{fixture.name}",
                    harness._minify_forth(  # noqa: SLF001
                        fixture.read_text(encoding="utf-8")
                    ).encode("utf-8"),
                )
                for fixture in FIXTURES
            )
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
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        stages = (
            *LOAD_STAGES,
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
            raw = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw),  # noqa: SLF001
                        *harness._matched_failure_markers(  # noqa: SLF001
                            profile,
                            raw,
                            machine.screen_text(),
                        ),
                    )
                )
            )
            reports.append((stage_name, report))
            if marker not in raw or failures:
                print(f"AT OAuth PAR {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-4000:])
                return 1
            print(
                f"AT OAuth PAR {stage_name}: PASS "
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
                    *harness._has_forth_error(raw),  # noqa: SLF001
                    *harness._matched_failure_markers(  # noqa: SLF001
                        profile,
                        raw,
                        machine.screen_text(),
                    ),
                )
            )
        )
        ok = PASS_MARKER in raw and not failures
        print(f"AT OAuth PAR vertical: {'PASS' if ok else 'FAIL'}")
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
            print(raw[-4000:])
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--static-only",
        action="store_true",
        help="check source and focused fixture contracts only",
    )
    mode.add_argument(
        "--vertical",
        action="store_true",
        help="run the staged one-core public-client PAR vertical",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("AT OAUTH PAR STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
