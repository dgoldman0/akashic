#!/usr/bin/env python3
"""Focused contracts for strict OAuth 2 protected-resource metadata."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402


PROFILE = "oauth2-resource-metadata-contracts"
IMAGE = Path("/tmp/akashic-oauth2-resource-metadata-contracts.img")
CONTRACT = LOCAL_TESTING / "oauth2-rmeta-test.f"
SOURCE = (
    LOCAL_TESTING.parent
    / "akashic"
    / "security"
    / "oauth2"
    / "resource-metadata.f"
)
DOC = (
    LOCAL_TESTING.parent
    / "docs"
    / "security"
    / "oauth2-protected-resource-metadata.md"
)

PASS_MARKER = "OAUTH2 RESOURCE METADATA PASS"
MAX_PHASE_STEPS = 180_000_000
LOAD_STAGES = (
    (
        "memory-span",
        "utils/memory-span.f",
        "O2RM MEMORY SPAN READY",
        120_000_000,
    ),
    (
        "caller-span",
        "utils/caller-span.f",
        "O2RM CALLER SPAN READY",
        120_000_000,
    ),
    (
        "json-object",
        "security/jose/json-object.f",
        "O2RM JSON OBJECT READY",
        180_000_000,
    ),
    (
        "resource-metadata",
        "security/oauth2/resource-metadata.f",
        "O2RM SOURCE READY",
        180_000_000,
    ),
    (
        "fixture",
        "local_testing/oauth2-rmeta-test.f",
        "O2RM FIXTURE READY",
        120_000_000,
    ),
)
GROUP_STAGES = (
    ("full", "_o2rmt-test-full", "O2RM FULL READY", 120_000_000),
    (
        "optional",
        "_o2rmt-test-optional",
        "O2RM OPTIONAL READY",
        120_000_000,
    ),
    (
        "rejections",
        "_o2rmt-test-rejections",
        "O2RM REJECTIONS READY",
        180_000_000,
    ),
    (
        "capacity",
        "_o2rmt-test-capacity",
        "O2RM CAPACITY READY",
        180_000_000,
    ),
    (
        "corruption",
        "_o2rmt-test-corruption",
        "O2RM CORRUPTION READY",
        120_000_000,
    ),
    (
        "preflight",
        "_o2rmt-test-preflight",
        "O2RM PREFLIGHT READY",
        120_000_000,
    ),
)


def _word_body(source: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^:[ \t]+{re.escape(name)}(?=[ \t\r\n(])"
        rf"(?P<body>.*?)[ \t]+;",
        source,
    )
    assert match is not None, f"missing definition for {name}"
    return match.group("body")


def _assert_source_contracts() -> None:
    source = SOURCE.read_text(encoding="utf-8")
    doc = DOC.read_text(encoding="utf-8")

    assert all(
        0 < stage_steps <= MAX_PHASE_STEPS
        for _, _, _, stage_steps in (*LOAD_STAGES, *GROUP_STAGES)
    )
    assert len(
        {name for name, _, _, _ in (*LOAD_STAGES, *GROUP_STAGES)}
    ) == len((*LOAD_STAGES, *GROUP_STAGES))
    assert len(
        {marker for _, _, marker, _ in (*LOAD_STAGES, *GROUP_STAGES)}
    ) == len((*LOAD_STAGES, *GROUP_STAGES))

    assert "U<=" not in source
    assert not re.search(
        r"(?mi)^[ \t]*(?:VARIABLE|VALUE|DEFER|CREATE)\b", source
    ), "resource metadata parsing must use caller-owned mutable storage"

    requires = re.findall(r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)", source)
    assert requires == [
        "../../utils/memory-span.f",
        "../../utils/caller-span.f",
        "../jose/json-object.f",
    ]
    assert not any(
        marker in requirement.lower()
        for requirement in requires
        for marker in ("http", "atproto", "identity", "session", "xrpc")
    )

    for word in (
        "OAUTH2-RESOURCE-METADATA-SIZE",
        "OAUTH2-RESOURCE-METADATA-WORKSPACE-SIZE",
        "OAUTH2-RESOURCE-METADATA-STATUS-VALID?",
        "OAUTH2-RESOURCE-METADATA-VALID?",
        "OAUTH2-RESOURCE-METADATA-WORKSPACE-CLEAR",
        "OAUTH2-RESOURCE-METADATA-PARSE",
        "OAUTH2-RESOURCE-METADATA-PRESENCE@",
        "OAUTH2-RESOURCE-METADATA-RESOURCE@",
        "OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER-COUNT@",
        "OAUTH2-RESOURCE-METADATA-AUTHORIZATION-SERVER@",
    ):
        assert word in source

    for field in ("resource", "authorization_servers"):
        assert f'S" {field}"' in source

    parser = _word_body(source, "_O2RM-PARSE-STAGE")
    assert "JOSE-JSON-OBJECT-PARSE" in parser
    assert "_O2RM-PROCESS-ALL" in parser
    assert (
        "OAUTH2-RESOURCE-METADATA-P-RESOURCE AND 0=" in parser
    )
    assert "_O2RM.PRESENCE !" in parser
    assert "MOVE" not in parser

    array_parser = _word_body(source, "_O2RM-ARRAY-PARSE")
    assert "_O2RM-DECODE-ARRAY-TOKEN" in array_parser
    assert "_O2RM-ARRAY-APPEND" in array_parser
    assert "OAUTH2-RESOURCE-METADATA-S-VALUE" in array_parser
    assert "JOSE-JSON-STRING-DECODE" in _word_body(
        source, "_O2RM-DECODE-ARRAY-TOKEN"
    )
    assert "OAUTH2-RESOURCE-METADATA-S-DUPLICATE" in _word_body(
        source, "_O2RM-ARRAY-APPEND"
    )

    geometry = _word_body(source, "_O2RM-PARSE-GEOMETRY")
    assert geometry.count("_O2RM-ADMIT-SPAN") == 3
    assert geometry.count("MSPAN-OVERLAP?") == 3

    admitted = _word_body(source, "_O2RM-PARSE-ADMITTED")
    publish = _word_body(source, "_O2RM-PUBLISH")
    call = _word_body(source, "_O2RM-PARSE-CALL")
    assert "_O2RM-WIPE" in admitted
    assert "MOVE" not in admitted
    assert publish.index("0 OVER _O2RMW.OUTPUT @ _O2RM.MAGIC !") < (
        publish.index("MOVE")
    )
    assert publish.index("MOVE") < publish.index("_O2RM-MAGIC-VALUE")
    assert "_O2RM-CALL-FINALLY" in call

    assert "RFC 9728" in doc
    assert "`resource` is required" in doc
    assert "does not fetch" in doc
    assert "AT Protocol" in doc


def _run_lifecycle(timeout: float) -> int:
    autoexec = [
        "\\ autoexec.f - staged OAuth 2 resource metadata\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker, _ in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." O2RM LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_O2RMT-INIT\n")
    for _, word, marker, _ in GROUP_STAGES:
        autoexec.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_O2RMT-FINISH\nTX-FLUSH\n")

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=("security/oauth2/resource-metadata.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "OAUTH2 RESOURCE METADATA FAIL",
            "OAUTH2 RESOURCE METADATA ASSERT",
            "OAUTH2 RESOURCE METADATA STATUS",
            "O2RM LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/oauth2-rmeta-test.f",
                harness._minify_forth(
                    CONTRACT.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=4096,
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
                print(f"OAuth 2 resource metadata {stage_name}: FAIL")
                for failure in failures:
                    print(f"  {failure}")
                print(raw[-4000:])
                return 1

        machine.clear_output()
        machine.send_text("x")
        report = machine.run(
            max_steps=20_000_000,
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
        print(
            "OAuth 2 resource metadata lifecycle: "
            f"{'PASS' if ok else 'FAIL'}"
        )
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
        help="check source contracts without building or running an image",
    )
    mode.add_argument(
        "--lifecycle",
        action="store_true",
        help="run the staged deterministic guest contracts",
    )
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_source_contracts()
    if args.static_only:
        print("OAUTH2 RESOURCE METADATA STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
