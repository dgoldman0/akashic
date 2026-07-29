#!/usr/bin/env python3
"""Qualify AT OAuth discovery over generic caller-owned HTTPS resources."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "at-oauth-hres-contracts"
IMAGE = Path("/tmp/akashic-at-oauth-hres-contracts.img")
SOURCE = ROOT / "akashic" / "atproto" / "oauth-profile-hres.f"
PROFILE_SOURCE = ROOT / "akashic" / "atproto" / "oauth-profile.f"
DOC = ROOT / "docs" / "atproto" / "oauth-profile-http-resource.md"
HRES_CONTRACT = LOCAL_TESTING / "hres-contracts.f"
PROFILE_CONTRACT = LOCAL_TESTING / "at-oauth-prof-test.f"
CONTRACT = LOCAL_TESTING / "at-oauth-hres-test.f"

PASS_MARKER = "AT OAUTH HRES PASS"
MAX_PHASE_STEPS = 180_000_000
FINISH_STEPS = 20_000_000
LOAD_STAGES = (
    ("event", "concurrency/event.f", "ATOH EVENT READY", 120_000_000),
    (
        "semaphore",
        "concurrency/semaphore.f",
        "ATOH SEMAPHORE READY",
        120_000_000,
    ),
    ("guard", "concurrency/guard.f", "ATOH GUARD READY", 120_000_000),
    ("string", "utils/string.f", "ATOH STRING READY", 120_000_000),
    (
        "memory-span",
        "utils/memory-span.f",
        "ATOH MEMORY SPAN READY",
        120_000_000,
    ),
    (
        "caller-span",
        "utils/caller-span.f",
        "ATOH CALLER SPAN READY",
        120_000_000,
    ),
    ("io-port", "net/io-port.f", "ATOH IO PORT READY", 120_000_000),
    (
        "external-io",
        "net/external-io.f",
        "ATOH EXTERNAL IO READY",
        120_000_000,
    ),
    (
        "http-request",
        "net/http-request.f",
        "ATOH HTTP REQUEST READY",
        120_000_000,
    ),
    (
        "http-stream",
        "net/http-stream.f",
        "ATOH HTTP STREAM READY",
        120_000_000,
    ),
    (
        "http-buffered",
        "net/http-buffered.f",
        "ATOH HTTP BUFFERED READY",
        120_000_000,
    ),
    (
        "http-target",
        "net/http-target.f",
        "ATOH HTTP TARGET READY",
        120_000_000,
    ),
    (
        "media-type",
        "net/media-type.f",
        "ATOH MEDIA TYPE READY",
        120_000_000,
    ),
    (
        "json-object",
        "security/jose/json-object.f",
        "ATOH JSON OBJECT READY",
        180_000_000,
    ),
    ("did", "atproto/did.f", "ATOH DID READY", 120_000_000),
    ("handle", "atproto/handle.f", "ATOH HANDLE READY", 120_000_000),
    (
        "did-document",
        "atproto/did-document.f",
        "ATOH DID DOCUMENT READY",
        180_000_000,
    ),
    ("dns-txt", "net/dns-txt.f", "ATOH DNS TXT READY", 180_000_000),
    (
        "identity",
        "atproto/identity.f",
        "ATOH IDENTITY READY",
        180_000_000,
    ),
    (
        "http-resource",
        "net/http-resource.f",
        "ATOH HTTP RESOURCE READY",
        180_000_000,
    ),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "ATOH RESOURCE METADATA READY",
        180_000_000,
    ),
    (
        "as-metadata",
        "security/oauth2/metadata.f",
        "ATOH AS METADATA READY",
        180_000_000,
    ),
    (
        "oauth-profile",
        "atproto/oauth-profile.f",
        "ATOH PROFILE READY",
        180_000_000,
    ),
    (
        "adapter",
        "atproto/oauth-profile-hres.f",
        "ATOH ADAPTER READY",
        180_000_000,
    ),
    (
        "hres-fixture",
        "local_testing/hres-contracts.f",
        "ATOH HRES FIXTURE READY",
        180_000_000,
    ),
    (
        "profile-fixture",
        "local_testing/at-oauth-prof-test.f",
        "ATOH PROFILE FIXTURE READY",
        180_000_000,
    ),
    (
        "adapter-fixture",
        "local_testing/at-oauth-hres-test.f",
        "ATOH ADAPTER FIXTURE READY",
        180_000_000,
    ),
)
GROUP_STAGES = (
    (
        "policy",
        "_ATOHT-TEST-POLICY",
        "ATOH POLICY GROUP READY",
        180_000_000,
    ),
    (
        "happy",
        "_ATOHT-TEST-HAPPY",
        "ATOH HAPPY GROUP READY",
        180_000_000,
    ),
    (
        "envelope",
        "_ATOHT-TEST-ENVELOPE",
        "ATOH ENVELOPE GROUP READY",
        180_000_000,
    ),
    (
        "parse-preservation",
        "_ATOHT-TEST-RETRY",
        "ATOH PARSE GROUP READY",
        180_000_000,
    ),
    (
        "semantic-failure",
        "_ATOHT-TEST-SEMANTIC",
        "ATOH SEMANTIC GROUP READY",
        180_000_000,
    ),
    (
        "ownership",
        "_ATOHT-TEST-GEOMETRY",
        "ATOH OWNERSHIP GROUP READY",
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
    profile_source = PROFILE_SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")
    hres_fixture = HRES_CONTRACT.read_text(encoding="utf-8")
    profile_fixture = PROFILE_CONTRACT.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
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
    for fixture_path in (HRES_CONTRACT, PROFILE_CONTRACT, CONTRACT):
        assert len(fixture_path.name.encode("utf-8")) <= 23

    assert _requires(SOURCE) == [
        "../utils/memory-span.f",
        "../utils/caller-span.f",
        "../utils/string.f",
        "../net/http-resource.f",
        "../security/oauth2/resource-metadata.f",
        "../security/oauth2/metadata.f",
        "oauth-profile.f",
    ]
    assert "PROVIDED akashic-at-oauth-hres" in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:CREATE|VARIABLE|VALUE|DEFER|GUARD)\b",
        source,
    ), "AT OAuth HTTP adapter owns mutable module state"
    for forbidden in (
        "streams",
        "session.f",
        "xrpc",
        "kdos-tls",
        "tcp-",
        "udp-",
    ):
        assert forbidden not in forth_code

    for word in (
        "AT-OAUTH-HRES-WORKSPACE-SIZE",
        "AT-OAUTH-HRES-WORKSPACE-CLEAR",
        "AT-OAUTH-HRES-SPEC-POLICY!",
        "AT-OAUTH-HRES-RESOURCE!",
        "AT-OAUTH-HRES-AUTHORIZATION-SERVER!",
    ):
        assert word in source

    policy = _word_body(source, "AT-OAUTH-HRES-SPEC-POLICY!")
    for word in (
        "HRES-SPEC-ACCEPT!",
        "HRES-SPEC-SUCCESS-RANGE!",
        "HRES-SPEC-REDIRECT-MAX!",
        "HRES-SPEC-MEDIA-MODE!",
        "HRES-SPEC-MEDIA!",
    ):
        assert word in policy
    assert 'S" application/json"' in policy
    assert "200 200" in policy
    assert "HRES-MEDIA-REQUIRED" in policy

    envelope = _word_body(source, "_ATOH-ENVELOPE?")
    for word in (
        "HRES-VALID?",
        "HRES-RESULT-VALID?",
        "HRES-HTTP-STATUS@",
        "HRES-REDIRECT-COUNT@",
        "HRES-REQUESTED-TARGET",
        "HRES-EFFECTIVE-TARGET",
        "HTARGET-EQUAL?",
        "HRES-MEDIA@",
        "_ATOH-JSON-MEDIA?",
    ):
        assert word in envelope
    assert "200 <>" in envelope
    assert "0<>" in envelope

    for word in (
        "OAUTH2-RESOURCE-METADATA-PARSE",
        "OAUTH2-METADATA-PARSE",
        "AT-OAUTH-PROFILE-RESOURCE!",
        "AT-OAUTH-PROFILE-AUTHORIZATION-SERVER!",
        "_ATOH-BODY-GEOMETRY",
        "_ATOH-CALL-CLEAN",
        "HRES-BODY-STORAGE@",
    ):
        assert word in source
    for private_prefix in ("_HRES.", "_O2RM.", "_O2MD.", "_ATOP."):
        assert private_prefix not in source
    assert "hres-" not in "\n".join(
        line.split("\\", 1)[0] for line in profile_source.splitlines()
    ).lower()

    assert "PROVIDED akashic-hres-contracts" in hres_fixture
    assert "PROVIDED at-oauth-prof-test" in profile_fixture
    for _, group_word, _, _ in GROUP_STAGES:
        assert group_word in fixture
    for marker in (
        "AT OAUTH HRES PASS",
        "AT-OAUTH-PROFILE-S-HTTP",
        "AT-OAUTH-PROFILE-S-RESOURCE-BINDING",
        "Application/JSON; charset=utf-8",
        "text/plain",
    ):
        assert marker in fixture

    for phrase in (
        "caller-owned",
        "exact HTTP status `200`",
        "redirect count zero",
        "requested target exactly equal",
        "effective target exactly equal",
        "`application/json`",
        "leave the pending profile phase unchanged",
        "public-address policy",
        "rethrown",
    ):
        assert phrase in doc

    _assert_physical_comments(SOURCE, source)
    _assert_physical_comments(CONTRACT, fixture)


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - staged AT OAuth HTTP-resource contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker, _ in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." AT OAUTH HRES LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOHT-INIT\n")
    for _, word, marker, _ in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_ATOHT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("atproto/oauth-profile-hres.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "AT OAUTH HRES FAIL",
            "AT OAUTH HRES ASSERT",
            "AT OAUTH HRES STATUS",
            "AT OAUTH HRES STACK",
            "AT OAUTH HRES LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                f"local_testing/{HRES_CONTRACT.name}",
                harness._minify_forth(
                    HRES_CONTRACT.read_text(encoding="utf-8")
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
                print(f"AT OAuth HRES {stage_name}: FAIL")
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
        print(f"AT OAuth HRES lifecycle: {'PASS' if ok else 'FAIL'}")
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
        print("AT OAUTH HRES STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
