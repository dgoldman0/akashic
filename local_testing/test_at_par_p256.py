#!/usr/bin/env python3
"""Qualify durable P-256 ownership through the public AT PAR wrapper."""

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


PROFILE = "at-par-p256-vertical"
IMAGE = Path("/tmp/akashic-at-par-p256-vertical.img")
PASS_MARKER = "AT PAR P256 PASS"

WRAPPER = SOURCE_ROOT / "atproto" / "oauth-par-p256.f"
RAW_PAR = SOURCE_ROOT / "atproto" / "oauth-par.f"
VAULT = SOURCE_ROOT / "security" / "credential-vault.f"
KEY_OWNER = SOURCE_ROOT / "security" / "oauth2" / "key-p256.f"
CV_DEPS = LOCAL_TESTING / "cv-deps.f"

PROFILE_FIXTURE = LOCAL_TESTING / "at-oauth-prof-test.f"
CLIENT_FIXTURE = LOCAL_TESTING / "at-oauth-client-test.f"
HTTP_FIXTURE = LOCAL_TESTING / "o2-http-post-common.f"
RAW_FIXTURE = LOCAL_TESTING / "at-oauth-par-test.f"
KEY_FIXTURE = LOCAL_TESTING / "oauth2-p256-key-test.f"
CONTRACT = LOCAL_TESTING / "at-par-p256-test.f"
FIXTURES = (
    PROFILE_FIXTURE,
    CLIENT_FIXTURE,
    HTTP_FIXTURE,
    RAW_FIXTURE,
    KEY_FIXTURE,
    CONTRACT,
)

MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000

RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    ("atproto/oauth-par.f",),
)
PACKED_RAW = tuple(
    (f"local_testing/p2r-{index:02d}.f", module)
    for index, module in enumerate(RAW_MODULES, start=1)
)
RAW_LOAD_STAGES = tuple(
    (
        f"raw-{index:02d}",
        guest,
        f"AT PAR P256 RAW {index:02d} READY",
        MAX_PHASE_STEPS,
    )
    for index, (guest, _) in enumerate(PACKED_RAW, start=1)
)

SEAM_GUEST = "local_testing/p2-seam.f"
VAULT_GUEST = "local_testing/p2-vault.f"
KEY_GUEST = "local_testing/p2-key.f"
WRAPPER_GUEST = "local_testing/p2-wrap.f"
OWNER_LOAD_STAGES = (
    ("seam", SEAM_GUEST, "AT PAR P256 SEAM READY", MAX_PHASE_STEPS),
    ("vault", VAULT_GUEST, "AT PAR P256 VAULT READY", MAX_PHASE_STEPS),
    ("key", KEY_GUEST, "AT PAR P256 KEY READY", MAX_PHASE_STEPS),
    (
        "wrapper",
        WRAPPER_GUEST,
        "AT PAR P256 WRAPPER READY",
        MAX_PHASE_STEPS,
    ),
)

FIXTURE_LOAD_STAGES = tuple(
    (
        f"fixture-{index:02d}",
        f"local_testing/{fixture.name}",
        f"AT PAR P256 FIXTURE {index:02d} READY",
        MAX_PHASE_STEPS,
    )
    for index, fixture in enumerate(FIXTURES, start=1)
)
RUNTIME_STAGES = (
    (
        "setup",
        "_ATP2T-INIT",
        "AT PAR P256 SETUP READY",
        MAX_PHASE_STEPS,
    ),
    (
        "rejection",
        "_ATP2T-TEST-REJECTION",
        "AT PAR P256 REJECTION READY",
        MAX_PHASE_STEPS,
    ),
    (
        "happy",
        "_ATP2T-TEST-HAPPY",
        "AT PAR P256 HAPPY READY",
        MAX_PHASE_STEPS,
    ),
)

FAILURE_MARKERS = (
    "AT PAR P256 FAIL",
    "AT PAR P256 ASSERT",
    "AT PAR P256 STATUS",
    "AT PAR P256 STACK",
    "AT PAR P256 LOAD STACK FAIL",
    "AT OAUTH PAR FAIL",
    "AT OAUTH PAR ASSERT",
    "AT OAUTH PAR STATUS",
    "AT OAUTH PROFILE ASSERT",
    "AT OAUTH PROFILE STATUS",
    "AT OAUTH CLIENT ASSERT",
    "AT OAUTH CLIENT STATUS",
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
    wrapper = WRAPPER.read_text(encoding="utf-8")
    raw = RAW_PAR.read_text(encoding="utf-8")
    vault = VAULT.read_text(encoding="utf-8")
    owner = KEY_OWNER.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    seam = (
        CV_DEPS.read_text(encoding="utf-8")
        + "\n"
        + P256_JWK_DOUBLES
    )

    all_stages = (
        *RAW_LOAD_STAGES,
        *OWNER_LOAD_STAGES,
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
        *FIXTURE_LOAD_STAGES,
    ):
        assert len(Path(guest).name.encode("utf-8")) <= 23

    # The raw closure must load before cv-deps.  cv-deps deliberately
    # republishes several already-loaded generic module IDs while supplying
    # the exact vault/key-owner seam; loading it first would make KDOS skip
    # the corresponding exact raw modules during their PROVIDED pre-scan.
    raw_ids = {
        module_id
        for module in RAW_MODULES
        for module_id in _provided_ids(
            (SOURCE_ROOT / module).read_text(encoding="utf-8")
        )
    }
    seam_ids = _provided_ids(seam)
    assert seam_ids[0] == "cv-test-deps"
    assert {
        "akashic-memory-span",
        "akashic-caller-span",
        "akashic-entropy",
        "akashic-guard",
    } <= raw_ids & set(seam_ids)
    assert all_stages.index(RAW_LOAD_STAGES[-1]) < all_stages.index(
        OWNER_LOAD_STAGES[0]
    )
    assert OWNER_LOAD_STAGES[0][0] == "seam"

    wrapper_ids = _provided_ids(wrapper)
    assert wrapper_ids == ["akashic-at-oauth-par256"]
    assert wrapper_ids[0] not in raw_ids
    assert wrapper_ids[0] not in seam_ids
    assert all(
        len(module_id.encode("ascii")) <= 23
        for module_id in wrapper_ids
    )
    assert _requires(WRAPPER) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../security/credential-vault.f",
        "../security/oauth2/client-config.f",
        "../security/oauth2/http-post.f",
        "../security/oauth2/key-p256.f",
        "oauth-profile.f",
        "oauth-client.f",
        "oauth-par.f",
    ]
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        wrapper,
    ), "AT PAR P256 wrapper must own no mutable module-global state"
    for word in (
        "AT-OAUTH-PAR-P256-INPUT-SIZE",
        "AT-OAUTH-PAR-P256-I.LOGIN-A",
        "AT-OAUTH-PAR-P256-I.LOGIN-U",
        "AT-OAUTH-PAR-P256-I.NONCE-A",
        "AT-OAUTH-PAR-P256-I.NONCE-U",
        "AT-OAUTH-PAR-P256-I.IAT",
        "AT-OAUTH-PAR-P256-I.VAULT",
        "AT-OAUTH-PAR-P256-I.CONFIG",
        "AT-OAUTH-PAR-P256-I.PROFILE",
        "AT-OAUTH-PAR-P256-I.TRANSACTION",
        "AT-OAUTH-PAR-P256-I.POST",
        "AT-OAUTH-PAR-P256-I.REQUEST-A",
        "AT-OAUTH-PAR-P256-I.REQUEST-CAP",
        "AT-OAUTH-PAR-P256-I.FORM-A",
        "AT-OAUTH-PAR-P256-I.FORM-CAP",
        "AT-OAUTH-PAR-P256-I.RESPONSE-A",
        "AT-OAUTH-PAR-P256-I.RESPONSE-CAP",
        "AT-OAUTH-PAR-P256-INPUT-CLEAR",
        "AT-OAUTH-PAR-P256-WORKSPACE-SIZE",
        "AT-OAUTH-PAR-P256-WORKSPACE-CLEAR",
        "AT-OAUTH-PAR-P256-BUILD",
    ):
        assert word in wrapper
    assert re.search(
        r"(?m)^128 CONSTANT AT-OAUTH-PAR-P256-INPUT-SIZE$",
        wrapper,
    )
    assert not re.search(
        r"(?m)^AT-OAUTH-PAR-P256-WORKSPACE-SIZE[ \t]+\d+[ \t]+<>",
        wrapper,
    )
    for marker in (
        "_ATPPW-INPUT-OFF AT-OAUTH-PAR-P256-INPUT-SIZE +",
        "_ATPPW-BINDING-OFF OAUTH2-P256-KEY-BINDING-SIZE +",
        "_ATPPW-DPOP-INPUT-OFF OAUTH2-P256-KEY-DPOP-INPUT-SIZE +",
        "_ATPPW-PROOF-OFF OAUTH2-DPOP-ES256-MAX-PROOF-BYTES +",
        "AT-OAUTH-CLIENT-WORKSPACE-SIZE",
        "OAUTH2-P256-KEY-DPOP-WORKSPACE-SIZE MAX",
        "AT-OAUTH-PAR-WORKSPACE-SIZE MAX",
    ):
        assert marker in wrapper
    for marker in (
        "CVAULT-EXTERNAL-SPAN-STATUS",
        "OAUTH2-HTTP-POST-CONFIGURE",
        "OAUTH2-HTTP-POST-HTU$",
        "OAUTH2-P256-KEY-DPOP-PROOF",
        "AT-OAUTH-PAR-BUILD",
    ):
        assert marker in wrapper
    for forbidden in (
        "_ATPAR",
        "_O2PK",
        "_O2HP.",
        "_CVAULT",
    ):
        assert forbidden not in wrapper

    geometry = _word_body(wrapper, "_ATPP-GEOMETRY")
    assert geometry.index("_ATPP-FIELD-GEOMETRY") < geometry.index(
        "_ATPP-ALIAS-GEOMETRY"
    )
    assert geometry.index("_ATPP-ALIAS-GEOMETRY") < geometry.index(
        "_ATPP-VAULT-GEOMETRY"
    )
    fresh_post = _word_body(wrapper, "_ATPP-FRESH-POST?")
    for marker in (
        "_ATPP-ZERO?",
        "OAUTH2-HTTP-POST-VALID?",
        "OAUTH2-HTTP-POST-STATE-EMPTY",
    ):
        assert marker in fresh_post
    field_geometry = _word_body(wrapper, "_ATPP-FIELD-GEOMETRY")
    assert "_ATPP-FRESH-POST?" in field_geometry
    vault_geometry = _word_body(wrapper, "_ATPP-VAULT-GEOMETRY")
    for field in (
        "LOGIN-U",
        "NONCE-U",
        "CONFIG",
        "PROFILE",
        "TRANSACTION",
        "POST",
        "REQUEST-A",
        "FORM-A",
        "RESPONSE-A",
    ):
        assert f"AT-OAUTH-PAR-P256-I.{field}" in vault_geometry
    assert "AT-OAUTH-PAR-P256-WORKSPACE-SIZE" in vault_geometry

    config_callback = _word_body(wrapper, "_ATPP-CONFIG-CALLBACK")
    assert config_callback.index("AT-OAUTH-CLIENT-VIEW-ADMIT") < (
        config_callback.index("OAUTH2-CLIENT-VIEW-BINDING@")
    )
    assert "OAUTH2-P256-KEY-BINDING-PRESENCE@" in config_callback
    assert "OAUTH2-P256-KEY-BINDING-F-DPOP <>" in config_callback

    configure_post = _word_body(wrapper, "_ATPP-CONFIGURE-POST")
    assert configure_post.index("AT-OAUTH-PROFILE-PAR-TARGET@") < (
        configure_post.index("OAUTH2-HTTP-POST-CONFIGURE")
    )
    dpop_input = _word_body(wrapper, "_ATPP-PREPARE-DPOP-INPUT")
    assert 'S" POST"' in dpop_input
    assert "OAUTH2-HTTP-POST-HTU$" in dpop_input
    assert "OAUTH2-P256-KEY-DPOP-I.NONCE-A" in dpop_input
    assert "OAUTH2-P256-KEY-DPOP-I.NONCE-U" in dpop_input
    assert "OAUTH2-P256-KEY-DPOP-I.TOKEN-A" not in dpop_input
    assert "OAUTH2-P256-KEY-DPOP-I.TOKEN-U" not in dpop_input

    operation = _word_body(wrapper, "_ATPP-OP")
    for earlier, later in (
        ("_ATPP-ADMIT-CONFIG", "_ATPP-CONFIGURE-POST"),
        ("_ATPP-CONFIGURE-POST", "_ATPP-PREPARE-DPOP-INPUT"),
        ("_ATPP-PREPARE-DPOP-INPUT", "_ATPP-SIGN"),
        ("_ATPP-SIGN", "_ATPP-RAW-BUILD"),
    ):
        assert operation.index(earlier) < operation.index(later)
    raw_build = _word_body(wrapper, "_ATPP-RAW-BUILD")
    assert "AT-OAUTH-PAR-BUILD" in raw_build
    assert re.search(r"(?m)^[ \t]*0 0$", raw_build)
    finish = _word_body(wrapper, "_ATPP-FINISH")
    assert "_ATPP-WIPE" in finish
    call = _word_body(wrapper, "_ATPP-CALL")
    assert call.index("CATCH") < call.index("_ATPP-WIPE")
    build = _word_body(wrapper, "AT-OAUTH-PAR-P256-BUILD")
    assert build.index("_ATPP-GEOMETRY") < build.index("_ATPP-CALL")

    assert _requires(CONTRACT) == [
        "at-oauth-par-test.f",
        "oauth2-p256-key-test.f",
    ]
    for marker in (
        "PROVIDED at-par-p256-test",
        "_ATP2T-INIT",
        "_ATP2T-TEST-REJECTION",
        "_ATP2T-TEST-HAPPY",
        "_ATP2T-FINISH",
        "AT-OAUTH-PAR-S-BINDING",
        "AT-OAUTH-PAR-P256-BUILD",
        "deterministic-dpop-proof",
        "OAUTH2-HTTP-POST-HTU$",
        "_O2PKD-DPOP-PRIVATE-OK",
        "_O2PKD-DPOP-NONCE-A",
        "_O2PKD-DPOP-TOKEN-A",
        "O2CODE-PHASE-PAR-READY",
        "_atp2t-work-zero?",
        "_atp2t-work-contains?",
        "_ATPART-TEST-ACCEPT",
        PASS_MARKER,
    ):
        assert marker in fixture
    assert fixture.count("AT-OAUTH-PAR-P256-BUILD") == 2
    assert "AT-OAUTH-PAR-BUILD" not in fixture
    for broad_group in (
        "_ATPART-TEST-REJECTIONS",
        "_O2PKT-TEST-DPOP",
        "_O2PKT-TEST-DPOP-PROOF",
        "_O2PKT-TEST-PREFLIGHT",
    ):
        assert broad_group not in fixture
    for deferred_status in (
        "AT-OAUTH-PAR-S-ALIAS",
        "AT-OAUTH-PAR-S-TARGET",
        "OAUTH2-P256-KEY-S-MISMATCH",
        "OAUTH2-P256-KEY-S-HTU",
    ):
        assert deferred_status not in fixture
    assert not re.search(
        r"(?i)(?<![A-Za-z0-9_-])(?:\?DO|DO|\+LOOP|LOOP)"
        r"(?![A-Za-z0-9_-])",
        fixture,
    ), "focused fixture must not borrow the DO-loop return stack"

    # This vertical deliberately does not requalify real P-256, JWK, or
    # ES256 cryptography. test_oauth2_dpop_es256.py verifies the real compact
    # proof and signature; this runner keeps the exact durable owner and raw
    # AT wrapper while making their subordinate seam deterministic.
    assert "PROVIDED akashic-p256" in P256_JWK_DOUBLES
    assert "PROVIDED akashic-jose-jwk-p256" in P256_JWK_DOUBLES
    assert "PROVIDED akashic-oauth2-dpop256" in P256_JWK_DOUBLES
    assert "deterministic-dpop-proof" in P256_JWK_DOUBLES
    for exact_source, marker in (
        (raw, "AT-OAUTH-PAR-BUILD"),
        (vault, "CVAULT-EXTERNAL-SPAN-STATUS"),
        (owner, "OAUTH2-P256-KEY-DPOP-PROOF"),
    ):
        assert marker in exact_source

    for module in RAW_MODULES:
        path = SOURCE_ROOT / module
        _assert_physical_comments(
            path,
            path.read_text(encoding="utf-8"),
        )
    for path in (VAULT, KEY_OWNER, WRAPPER, *FIXTURES):
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
        "\\ autoexec.f - durable P256 AT PAR public vertical\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, guest, marker, _ in (
        *RAW_LOAD_STAGES,
        *OWNER_LOAD_STAGES,
        *FIXTURE_LOAD_STAGES,
    ):
        lines.extend(
            (
                f"REQUIRE {guest}\n",
                (
                    'DEPTH IF ." AT PAR P256 LOAD STACK FAIL '
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
    lines.append("_ATP2T-FINISH\nTX-FLUSH\n")
    return "".join(lines)


def _run_vertical(timeout: float) -> int:
    seam_source = CV_DEPS.read_text(encoding="utf-8")
    seam_source += "\n"
    seam_source += P256_JWK_DOUBLES
    initial_files = (
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
        + (
            (
                SEAM_GUEST,
                harness._minify_forth(seam_source).encode("utf-8"),
            ),
            (VAULT_GUEST, _packed(VAULT, remove_requires=True)),
            (KEY_GUEST, _packed(KEY_OWNER, remove_requires=True)),
            (WRAPPER_GUEST, _packed(WRAPPER, remove_requires=True)),
        )
        + tuple(
            (
                f"local_testing/{fixture.name}",
                _packed(fixture),
            )
            for fixture in FIXTURES
        )
    )

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=initial_files,
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
                print(f"AT PAR P256 {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-4000:])
                return 1
            print(
                f"AT PAR P256 {stage_name}: PASS "
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
        print(f"AT PAR P256 vertical: {'PASS' if ok else 'FAIL'}")
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
        help="run the staged one-core durable P256 AT PAR vertical",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("AT PAR P256 STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
