#!/usr/bin/env python3
"""Static and bounded linked qualification for durable OAuth sessions."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE = ROOT / "akashic" / "security" / "oauth2" / "session.f"
TOKEN_SOURCE = ROOT / "akashic" / "security" / "oauth2" / "token-set.f"
VAULT_SOURCE = ROOT / "akashic" / "security" / "credential-vault.f"
DOC = ROOT / "docs" / "security" / "oauth2-session.md"
VAULT_DOC = ROOT / "docs" / "security" / "credential-vault.md"
DEPS = LOCAL_TESTING / "oauth2-session-deps.f"
FIXTURE = LOCAL_TESTING / "oauth2-session-test.f"
PHASE_MAX_STEPS = 180_000_000


def _flat(text: str) -> str:
    return " ".join(text.split())


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _ordered(text: str, *markers: str) -> None:
    cursor = -1
    for marker in markers:
        found = text.find(marker, cursor + 1)
        assert found >= 0, f"missing ordered marker: {marker}"
        cursor = found


def _assert_static_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    token_source = TOKEN_SOURCE.read_text(encoding="utf-8")
    vault_source = VAULT_SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    vault_doc = VAULT_DOC.read_text(encoding="utf-8")
    deps = DEPS.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    lowered = source.lower()

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../credential-vault.f",
        "token-set.f",
        "../../runtime/identity.f",
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../../concurrency/guard.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER)\b", source
    ), "all session operation state must be caller-owned"
    for forbidden in (
        "atproto/",
        "streams/",
        "bluesky",
        "xrpc",
        "jetstream",
        "net/",
        "es256",
    ):
        assert forbidden not in lowered
    assert not re.search(r"(?i)\b(?:v2|compat(?:ibility)?)\b", source)

    for status in (
        "O2SESSION-S-OK",
        "O2SESSION-S-REVOKED",
        "O2SESSION-S-CONFLICT",
        "O2SESSION-S-STATE",
        "O2SESSION-S-CALLBACK",
        "O2SESSION-S-RECOVERY",
        "O2SESSION-S-ROLLBACK",
        "O2SESSION-S-FORMAT",
        "O2SESSION-S-CACHE",
    ):
        assert status in source
    for phase in (
        "O2SESSION-PHASE-ACTIVE",
        "O2SESSION-PHASE-REFRESH-CLAIMED",
        "O2SESSION-PHASE-REFRESH-EXPOSED",
    ):
        assert phase in source
    for word in (
        "O2SESSION-CONFIG-CLEAR",
        "O2SESSION-GRANT-CLEAR",
        "O2SESSION-INIT",
        "O2SESSION-INSTALL",
        "O2SESSION-OPEN",
        "O2SESSION-REAUTHORIZE",
        "O2SESSION-CLOSE",
        "O2SESSION-FINI",
        "O2SESSION-REFRESH-CLAIM",
        "O2SESSION-REFRESH-ABORT",
        "O2SESSION-REFRESH-EXPOSE",
        "O2SESSION-REFRESH-COMMIT",
        "O2SESSION-LOGOUT",
        "O2SESSION-RECOVER",
        "O2SESSION-STATE@",
        "O2SESSION-EXPIRY@",
        "O2SESSION-EXPIRED?",
        "O2SESSION-WITH-RID",
        "O2SESSION-WITH-BINDING",
        "O2SESSION-WITH-ISSUER",
        "O2SESSION-WITH-TOKEN-TYPE",
        "O2SESSION-WITH-SCOPE",
        "O2SESSION-WITH-ACCESS",
        "O2SESSION-WITH-ID",
        "OAUTH2-SESSION-SIZE",
        "O2SESSION-RECORD-SIZE",
    ):
        assert re.search(
            rf"^:[ \t]+{re.escape(word)}(?=[ \t\r\n(])"
            rf"|CONSTANT[ \t]+{re.escape(word)}$",
            source,
            re.MULTILINE,
        ), f"missing public contract {word}"

    assert re.search(
        r"(?m)^256[ \t]+CONSTANT O2SESSION-BINDING-CAPACITY$",
        source,
    )
    assert re.search(
        r"(?m)^2048 CONSTANT O2SESSION-ISSUER-CAPACITY$", source
    )
    assert "_O2SR-H-RESERVED1 8 +" in source
    assert (
        "O2SESSION-RECORD-SIZE CVAULT-SECRET-CAPACITY-MAX U>"
        in source
    )
    assert "O2TOK-REFRESH-BEGIN" not in source
    assert "O2TOK-WITH-REFRESH-LEASE" not in source
    assert "O2TOK-REFRESH-COMMIT" not in source
    assert "_O2TOK.REFRESH" not in source

    build = _flat(_word_body(source, "_O2S-RECORD-BUILD"))
    _ordered(
        build,
        "O2SESSION-RECORD-SIZE 0 FILL",
        "_O2S-RECORD-HEADER-BUILD",
        "_O2S.BINDING",
        "O2SESSION-G.TOKEN-TYPE-A",
        "O2SESSION-G.ACCESS-A",
    )
    for length_source in (
        "O2SESSION-G.TOKEN-TYPE-U",
        "O2SESSION-G.ACCESS-U",
        "O2SESSION-G.REFRESH-U",
        "O2SESSION-G.SCOPE-U",
        "O2SESSION-G.ID-U",
    ):
        assert f"2 PICK {length_source} @ MOVE" in build
        assert f"OVER {length_source} @ MOVE" not in build
    install = _flat(_word_body(source, "O2SESSION-INSTALL"))
    _ordered(
        install,
        "_O2S-GRANT-STATUS",
        "DUP O2SESSION-PHASE-ACTIVE",
        "_O2S-RECORD-BUILD",
        "CVAULT-CREATE",
        "_O2S-HYDRATE",
    )
    validate = _word_body(source, "_O2S-RECORD-VALID?")
    for marker in (
        "_O2S-RECORD-HEADER-VALID?",
        "_O2S-RECORD-LENGTHS-VALID?",
        "_O2S-RECORD-FLAGS-VALID?",
        "_O2S-RECORD-BINDING-VALID?",
        "_O2S-RECORD-PADDING-VALID?",
    ):
        assert marker in validate

    load = _flat(_word_body(source, "_O2S-LOAD"))
    _ordered(
        load,
        "CVAULT-WITH",
        "_O2S.OP-STATUS !",
        "O2SESSION-CREDENTIAL-KIND <>",
        "_O2S-RECORD-VALID?",
    )
    load_expected = _flat(_word_body(source, "_O2S-LOAD-EXPECTED"))
    _ordered(
        load_expected,
        "_O2S-LOAD",
        "_O2S.OP-GENERATION @",
        "_O2S.OP-EXPECTED @ =",
    )
    reauthorize = _flat(_word_body(source, "O2SESSION-REAUTHORIZE"))
    _ordered(
        reauthorize,
        "_O2S-LOAD-EXPECTED",
        "_O2S-RECORD-BUILD",
        "CVAULT-REPLACE",
        "_O2S-HYDRATE",
    )
    logout = _flat(_word_body(source, "O2SESSION-LOGOUT"))
    _ordered(logout, "_O2S-LOAD-EXPECTED", "CVAULT-REVOKE")
    recover = _flat(_word_body(source, "O2SESSION-RECOVER"))
    assert "_O2S.RID R@ _O2S.VAULT @ CVAULT-RECOVER" in recover
    hydrate = _flat(_word_body(source, "_O2S-HYDRATE"))
    assert "R@ _O2S-R.REFRESH 0" in hydrate
    assert "O2TOK-SET" in hydrate

    transition = _flat(_word_body(source, "_O2S-PHASE-TRANSITION"))
    _ordered(
        transition,
        "_O2S-LOAD",
        "_O2S-RECORD-VALID?",
        "CVAULT-REPLACE",
        "_O2S.GENERATION !",
        "_O2S.PHASE !",
    )
    expose = _flat(_word_body(source, "O2SESSION-REFRESH-EXPOSE"))
    _ordered(
        expose,
        "_O2S-PHASE-TRANSITION",
        "_O2S-R.REFRESH",
        "_O2S-CALLBACK-SAFE",
    )
    commit = _flat(_word_body(source, "_O2S-REFRESH-COMMIT-BODY"))
    _ordered(
        commit,
        "_O2S-LOAD",
        "_O2S-REFRESH-APPLY",
        "CVAULT-REPLACE",
        "_O2S-HYDRATE",
    )
    assert "_O2S-CALLBACK-CANARY" in source
    assert "_O2S-E-CALLBACK-STACK" in source
    assert "_O2S-F-BUSY" in _word_body(source, "_O2S-OP-BEGIN")
    immutable_shape = _flat(
        _word_body(source, "_O2S-IMMUTABLE-SHAPE?")
    )
    assert (
        "DUP _O2S.ISSUER SWAP _O2S.ISSUER-U @ "
        "O2SESSION-ISSUER-CAPACITY _O2S-CANONICAL-ARENA?"
        in immutable_shape
    )
    logout = _flat(_word_body(source, "O2SESSION-LOGOUT"))
    assert (
        "THEN OVER R@ _O2S.OP-EXPECTED ! 2DROP "
        "R@ _O2S.OP-EXPECTED @"
        in logout
    )

    assert "CVAULT-SECRET-CAPACITY@" in vault_source
    assert "CVAULT-SECRET-CAPACITY@" in vault_doc
    assert "CVAULT-SECRET-CAPACITY@" in source
    assert "O2SESSION-RECORD-SIZE U<" in source

    for marker in (
        "provider-neutral",
        "REFRESH-CLAIMED",
        "REFRESH-EXPOSED",
        "persist",
        "reboot",
        "DPoP",
        "AT Protocol",
        "Streams",
        "callback",
        "tombstone",
    ):
        assert marker.lower() in doc.lower()
    assert "security/oauth2/session.f" in doc

    for marker in (
        "PROVIDED akashic-cred-vault",
        "O2S-TEST-CVAULT-INIT",
        "O2S-TEST-CVAULT-BLOCK",
        "CVAULT-WITH",
        "consumer-result",
    ):
        assert marker in deps
    assert (
        "( expected-rid vault -- generation state status )" in deps
    )
    for test_word in (
        "_O2ST-INITIAL-INSTALL",
        "_O2ST-REBOOT-AND-BINDING",
        "_O2ST-REFRESH-ROTATION",
        "_O2ST-CALLBACK-CONTAINMENT",
        "_O2ST-RECOVERY-AND-LOGOUT",
    ):
        assert test_word in fixture
    assert "O2SESSION-S-ABSENT = _O2ST-ASSERT" in fixture
    assert "O2SESSION-S-BUSY = _O2ST-ASSERT" in fixture
    assert "O2SESSION-S-CALLBACK = _O2ST-ASSERT" in fixture
    assert "O2SESSION-S-REVOKED = _O2ST-ASSERT" in fixture
    assert "_O2ST-RID RID-SIZE 0x5A FILL" in fixture
    assert "_O2ST-OTHER-RID RID-SIZE 0xA5 FILL" in fixture
    _ordered(
        _flat(_word_body(fixture, "_O2ST-RUN")),
        "_O2ST-REFRESH-ROTATION _O2ST-STACK "
        '." OAUTH2 SESSION REFRESH READY" CR TX-FLUSH KEY DROP',
        "_O2ST-CALLBACK-CONTAINMENT _O2ST-STACK "
        '." OAUTH2 SESSION CALLBACK READY" CR TX-FLUSH KEY DROP',
        "_O2ST-RECOVERY-AND-LOGOUT _O2ST-STACK",
    )

    for path, text in (
        (SOURCE, source),
        (TOKEN_SOURCE, token_source),
        (DEPS, deps),
        (FIXTURE, fixture),
    ):
        for line_number, line in enumerate(text.splitlines(), start=1):
            forth_code = line.split("\\", 1)[0]
            if "(" in forth_code:
                assert ")" in forth_code.split("(", 1)[1], (
                    "KDOS parenthesized comments must close on their "
                    f"physical line: {path}:{line_number}"
                )

    token_requires = re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", token_source
    )
    assert token_requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../../concurrency/guard.f",
    ]


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    def packed(path: Path, *, remove_requires: bool = False) -> bytes:
        return harness._minify_forth(
            path.read_text(encoding="utf-8"),
            remove_requires=remove_requires,
        ).encode("utf-8")

    profile = "oauth2-session-life"
    image = Path("/tmp/akashic-oauth2-session-life.img")
    marker = "OAUTH2 SESSION PASS"
    load_marker = "OAUTH2 SESSION LOAD READY"
    autoexec = (
        "\\ autoexec.f - durable OAuth session lifecycle\n"
        "ENTER-USERLAND\n"
        '." OAUTH2 LOAD DEPS" CR TX-FLUSH\n'
        "REQUIRE local_testing/oauth2-session-deps.f\n"
        '." OAUTH2 LOAD TOKEN" CR TX-FLUSH\n'
        "REQUIRE local_testing/o2s-token.f\n"
        '." OAUTH2 LOAD SESSION" CR TX-FLUSH\n'
        "REQUIRE local_testing/o2s-session.f\n"
        '." OAUTH2 LOAD TEST" CR TX-FLUSH\n'
        "REQUIRE local_testing/oauth2-session-test.f\n"
        "DEPTH IF\n"
        '  ." OAUTH2 SESSION LOAD STACK FAIL" CR TX-FLUSH\n'
        "THEN\n"
        f'." {load_marker}" CR TX-FLUSH\n'
        "KEY DROP\n"
        '." OAUTH2 LOAD RUN" CR TX-FLUSH\n'
        "_O2ST-RUN\n"
    )
    harness.PROFILES[profile] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=autoexec,
        ready_markers=(marker,),
        stable_markers=(marker,),
        failure_markers=(
            "OAUTH2 SESSION FAIL",
            "OAUTH2 SESSION ASSERT",
            "OAUTH2 SESSION STACK",
            "OAUTH2 SESSION LOAD STACK FAIL",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            ("local_testing/oauth2-session-deps.f", packed(DEPS)),
            (
                "local_testing/o2s-token.f",
                packed(TOKEN_SOURCE, remove_requires=True),
            ),
            (
                "local_testing/o2s-session.f",
                packed(SOURCE, remove_requires=True),
            ),
            ("local_testing/oauth2-session-test.f", packed(FIXTURE)),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=2048,
    )
    image_path = harness.build_image(profile, image)

    def guest_failures(session: object) -> tuple[str, ...]:
        raw = session.raw_text()
        screen = session.screen_text()
        failures = list(harness._has_forth_error(raw))
        failures.extend(
            harness._matched_failure_markers(
                harness.PROFILES[profile], raw, screen
            )
        )
        return tuple(dict.fromkeys(failures))

    def write_captures(session: object, raw: str) -> None:
        capture_root = harness.OUTPUT_ROOT / f"smoke-{profile}"
        screen = session.snapshot()
        screen.write_text(capture_root.with_suffix(".txt"))
        screen.write_json(capture_root.with_suffix(".cells.json"))
        screen.write_png(
            capture_root.with_suffix(".png"),
            font_path=(
                harness.AKASHIC_ROOT
                / "assets"
                / "fonts"
                / "DejaVuSansMono.ttf"
            ),
        )
        capture_root.with_suffix(".raw.txt").write_text(
            raw, encoding="utf-8"
        )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=128 << 20,
        num_cores=1,
    ) as session:
        session.boot()
        load = session.run(
            max_steps=PHASE_MAX_STEPS,
            wall_timeout_s=timeout,
            until_text=load_marker,
            text_scope="raw",
        )
        load_raw = session.raw_text()
        load_failures = guest_failures(session)
        load_ok = load_marker in load_raw and not load_failures
        if not load_ok:
            write_captures(session, load_raw)
            print(
                "Staged oauth2-session-life: FAIL\n"
                f"  load: {load.steps:,} steps in "
                f"{load.elapsed_s:.2f}s; stop={load.reason}"
            )
            for failure in load_failures:
                print(f"  load failure: {failure}")
            print(f"  recent guest output:\n{load_raw[-4000:]}")
            return 1

        phases = (
            ("install-refresh", "OAUTH2 SESSION REFRESH READY"),
            ("callbacks", "OAUTH2 SESSION CALLBACK READY"),
            ("recovery-logout", marker),
        )
        reports = []
        combined = [load_raw]
        for phase_name, phase_marker in phases:
            session.clear_output()
            session.send_text("x")
            report = session.run(
                max_steps=PHASE_MAX_STEPS,
                wall_timeout_s=timeout,
                until_text=phase_marker,
                text_scope="raw",
            )
            phase_raw = session.raw_text()
            failures = guest_failures(session)
            reports.append((phase_name, report))
            combined.extend(
                (f"\n--- staged {phase_name} ---\n", phase_raw)
            )
            if phase_marker not in phase_raw or failures:
                write_captures(session, "".join(combined))
                print(
                    "Staged oauth2-session-life: FAIL\n"
                    f"  load: {load.steps:,} steps in "
                    f"{load.elapsed_s:.2f}s; stop={load.reason}\n"
                    f"  {phase_name}: {report.steps:,} steps in "
                    f"{report.elapsed_s:.2f}s; stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {phase_name} failure: {failure}")
                print(
                    f"  recent guest output:\n{phase_raw[-4000:]}"
                )
                return 1

        write_captures(session, "".join(combined))
        print(
            "Staged oauth2-session-life: PASS\n"
            f"  load: {load.steps:,} steps in "
            f"{load.elapsed_s:.2f}s; stop={load.reason}"
        )
        for phase_name, report in reports:
            print(
                f"  {phase_name}: {report.steps:,} steps in "
                f"{report.elapsed_s:.2f}s; stop={report.reason}"
            )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("OAUTH2 SESSION STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
