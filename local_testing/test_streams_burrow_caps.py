#!/usr/bin/env python3
"""Qualify the Checkpoint-3 Streams Burrow capability boundary."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
CAPABILITIES = (
    ROOT / "akashic" / "tui" / "applets" / "streams" / "rabbit-capabilities.f"
)
STREAMS = ROOT / "akashic" / "tui" / "applets" / "streams" / "streams.f"
UIDL = ROOT / "akashic" / "tui" / "applets" / "streams" / "streams.uidl"
SCRIPTED_PROVIDER = LOCAL_TESTING / "streams-burrow-prov.f"
FIXTURE = LOCAL_TESTING / "streams-burrow-caps.f"

PASS_MARKER = "STREAMS BURROW CAPS PASS"
PHASE_MAX_STEPS = 120_000_000
TOTAL_SECTORS = 4096
EXT_MEMORY_BYTES = 64 << 20

LOAD_STAGES = (
    ("identity", "runtime/identity.f", "STREAMS CAPS IDENTITY READY"),
    ("memory-span", "utils/memory-span.f", "STREAMS CAPS MEMORY SPAN READY"),
    ("sha3", "math/sha3.f", "STREAMS CAPS SHA3 READY"),
    (
        "provider",
        "tui/applets/streams/rabbit-provider.f",
        "STREAMS CAPS PROVIDER READY",
    ),
    (
        "manager",
        "tui/applets/streams/rabbit-manager.f",
        "STREAMS CAPS MANAGER READY",
    ),
    ("string", "utils/string.f", "STREAMS CAPS STRING READY"),
    ("utf8", "text/utf8.f", "STREAMS CAPS UTF8 READY"),
    ("value", "interop/value.f", "STREAMS CAPS VALUE READY"),
    ("schema", "interop/schema.f", "STREAMS CAPS BASE SCHEMA READY"),
    ("json", "utils/json.f", "STREAMS CAPS JSON READY"),
    (
        "json-value",
        "interop/codecs/json-value.f",
        "STREAMS CAPS JSON VALUE READY",
    ),
    ("instance", "runtime/instance.f", "STREAMS CAPS INSTANCE READY"),
    (
        "capability",
        "interop/capability.f",
        "STREAMS CAPS CAPABILITY READY",
    ),
    ("registry", "runtime/registry.f", "STREAMS CAPS REGISTRY READY"),
    ("policy", "interop/policy.f", "STREAMS CAPS POLICY READY"),
    ("authority", "interop/authority.f", "STREAMS CAPS AUTHORITY READY"),
    ("mandate", "interop/mandate.f", "STREAMS CAPS MANDATE READY"),
    (
        "practice-turn",
        "interop/practice-turn.f",
        "STREAMS CAPS PRACTICE TURN READY",
    ),
    ("request-bus", "interop/request-bus.f", "STREAMS CAPS BUS READY"),
    ("resource", "interop/resource.f", "STREAMS CAPS RESOURCE READY"),
    (
        "schema-common",
        "interop/schema-common.f",
        "STREAMS CAPS SCHEMA READY",
    ),
    (
        "construction",
        "interop/construction.f",
        "STREAMS CAPS CONSTRUCTION READY",
    ),
    (
        "capabilities",
        "tui/applets/streams/rabbit-capabilities.f",
        "STREAMS CAPS ADAPTER READY",
    ),
    (
        "scripted-provider",
        "local_testing/streams-burrow-prov.f",
        "STREAMS CAPS SCRIPTED PROVIDER READY",
    ),
    (
        "fixture",
        "local_testing/streams-burrow-caps.f",
        "STREAMS CAPS FIXTURE READY",
    ),
)

CONTRACT_STAGES = (
    (
        "descriptors-bounds",
        "_SBC-PHASE-DESCRIPTORS-BOUNDS",
        "STREAMS BURROW CAPS DESCRIPTORS BOUNDS PASS",
    ),
    (
        "create-replay-errors",
        "_SBC-PHASE-CREATE-REPLAY-ERRORS",
        "STREAMS BURROW CAPS CREATE REPLAY PASS",
    ),
    (
        "lifecycle-status",
        "_SBC-PHASE-LIFECYCLE-STATUS",
        "STREAMS BURROW CAPS LIFECYCLE PASS",
    ),
)


def _word_body(source: str, word: str) -> str:
    match = re.search(
        rf"(?ms)^:\s+{re.escape(word)}\b.*?\s;\s*$", source
    )
    assert match is not None, word
    return match.group(0)


def _assert_static_contracts() -> None:
    adapter = CAPABILITIES.read_text(encoding="utf-8")
    streams = STREAMS.read_text(encoding="utf-8")
    uidl = UIDL.read_text(encoding="utf-8")
    provider = SCRIPTED_PROVIDER.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == 120_000_000
    assert TOTAL_SECTORS == 4096
    assert EXT_MEMORY_BYTES == 64 << 20
    assert "PROVIDED akashic-streams-srbc" in adapter
    assert "PROVIDED akashic-test-srbprov" in provider
    assert "PROVIDED akashic-test-streams-burrow-caps" in fixture

    for capability_id in (
        "streams.burrow.create",
        "streams.burrow.status",
        "streams.burrow.start",
        "streams.burrow.stop",
    ):
        assert f'S" {capability_id}"' in adapter
    assert "4 CONSTANT STREAMS-BURROW-CAPABILITY-COUNT" in adapter
    assert "CAP-F-IDEMPOTENT CAP-F-NEEDS-TARGET OR" in adapter
    assert "CAP-E-PERSIST" not in adapter
    assert "CAP-E-EXTERNAL" not in adapter
    assert "_SRBCAP-CHANGED @ IF" in adapter
    assert "['] _SRBCAP-INVALIDATE-CALL CATCH DROP" in adapter
    assert "CBUS-S-NO-EFFECT" in adapter
    assert "CBR-ARGS-SEAL-MATCH?" in adapter
    assert "_SRBCAP-RESULT-SEAL" in adapter
    assert "_SRBCAP-MUTATION-RESULT-SCHEMA" in adapter
    assert "_SRBCAP-STATUS-RESULT-SCHEMA" in adapter
    assert "STREAMS-BURROW-CAPABILITY-BIND" in adapter

    # The applet composition owns the manager and borrowed pools.  The
    # adapter resolver is bound by normal component setup, and each public
    # lifecycle callback delegates exactly once to the Burrow owner layer.
    assert "STREAMS-BURROW-COMPOSITION-STATE!" in streams
    assert "( rows row-cap replays replay-cap provider state -- status )" in streams
    cap_setup = _word_body(streams, "_STM-CAP-SETUP")
    burrow_cap_setup = _word_body(streams, "_STM-BURROW-CAP-SETUP")
    assert cap_setup.count("_STM-BURROW-CAP-SETUP") == 1
    assert "STREAMS-BURROW-CAPABILITY-BIND" in burrow_cap_setup
    assert "STREAMS-BURROW-APPLET-CAPABILITIES-SETUP" in burrow_cap_setup
    assert (
        "STREAMS-BURROW-APPLET-CAPABILITY-COUNT CAP-DESC * MOVE"
        in burrow_cap_setup
    )
    assert "_STM-BURROW-BUILD? [IF] 19 [ELSE] 15 [THEN]" in streams
    assert "STREAMS-CAP-BURROW-CREATE STREAMS-CAPS CAP-DESC 15 * +" in streams
    assert "STREAMS-CAP-BURROW-STOP STREAMS-CAPS CAP-DESC 18 * +" in streams

    init = _word_body(streams, "STREAMS-INIT-CB")
    tick = _word_body(streams, "STREAMS-TICK-CB")
    close = _word_body(streams, "STREAMS-REQUEST-CLOSE-CB")
    shutdown = _word_body(streams, "STREAMS-SHUTDOWN-CB")
    invalidator = _word_body(streams, "_STM-BURROW-CAP-INVALIDATE")
    assert init.count("_STM-BURROW-INIT") == 1
    assert tick.count("_STM-BURROW-TICK") == 1
    assert close.count("_STM-BURROW-QUIESCE?") == 1
    assert close.index("_STM-BURROW-QUIESCE?") < close.index("_STM-AUTH-QUIESCE?")
    assert shutdown.count("_STM-BURROW-RELEASE") == 1
    assert shutdown.index("_STM-BURROW-RELEASE") < shutdown.index("_STM-AUTH-RELEASE")
    assert "_STM-OWNER-TOUCH" not in invalidator

    # Visible control and status wiring is checked from the actual UIDL, not
    # duplicated into the Forth fixture as a second UI contract.
    for token in (
        "do=burrows",
        "do=burrow-start",
        "do=burrow-stop",
        "id=sbar-burrow",
        "key=Ctrl+B",
    ):
        assert token in uidl
    for token in (
        'S" sbar-burrow" UTUI-BY-ID',
        'S" burrows" [\'] _STM-DO-BURROWS UTUI-DO!',
        'S" burrow-start" [\'] _STM-DO-BURROW-START UTUI-DO!',
        'S" burrow-stop" [\'] _STM-DO-BURROW-STOP UTUI-DO!',
    ):
        assert token in streams

    for _, word, _ in CONTRACT_STAGES:
        assert f": {word}" in fixture
    for symbol in (
        "STREAMS-BURROW-CREATE-REQUEST-SEMANTIC-PLAIN-MAX",
        "STREAMS-BURROW-CREATE-REQUEST-SCHEMA-TYPED-MAX",
        "STREAMS-BURROW-MUTATION-RESULT-SCHEMA-TYPED-MAX",
        "STREAMS-BURROW-STATUS-RESULT-SCHEMA-TYPED-MAX",
        "IVJSON-E-CAPACITY",
        "CBUS-S-NO-EFFECT",
        "SRBPROV-S-CONFLICT",
        "_SBC-INVALIDATE-THROW",
    ):
        assert symbol in fixture
    assert "_SBC-BOUND-EXPECTED @ 1-" in fixture
    assert "_SBC-BEFORE-REVISION @ 1+" in fixture
    assert "_SBC-BEFORE-INVALIDATIONS @ 1+" in fixture
    assert not re.search(r"\b(?:DO|\?DO)\b", fixture)


def _initial_files(harness) -> tuple[tuple[str, bytes], ...]:
    return tuple(
        (
            str(path.relative_to(ROOT)),
            harness._minify_forth(path.read_text(encoding="utf-8")).encode(
                "utf-8"
            ),
        )
        for path in (SCRIPTED_PROVIDER, FIXTURE)
    )


def _report_failure(stage, report, raw, failures, machine) -> int:
    print(f"Streams Burrow capabilities {stage}: FAIL")
    print(
        f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
        f"stop={report.reason}"
    )
    for failure in failures:
        print(f"  {failure}")
    if len(raw) > 8000:
        print(raw[:4000])
        print("\n... capability trace middle omitted ...\n")
    print(raw[-4000:])
    print(machine.screen_text())
    return 1


def _run_caps(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - source-loaded Streams Burrow capability contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                "DEPTH IF\n",
                (
                    '." STREAMS BURROW CAPS LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH\n'
                ),
                "THEN\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker in CONTRACT_STAGES:
        autoexec.extend(
            (
                f"' {word} CATCH DUP IF\n",
                '  ." STREAMS BURROW CAPS CONTRACT THROW " . CR TX-FLUSH\n',
                "THEN\n",
                "?DUP IF THROW THEN\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_SBC-FINISH TX-FLUSH\n")

    profile_name = "streams-burrow-caps-source"
    image = Path("/tmp/akashic-streams-burrow-caps-source.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("tui/applets/streams/rabbit-capabilities.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS BURROW CAPS FAIL",
            "STREAMS BURROW CAPS ASSERT",
            "STREAMS BURROW CAPS STACK",
            "STREAMS BURROW CAPS CONTRACT THROW",
            "STREAMS BURROW CAPS LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=_initial_files(harness),
        linked=False,
        include_large_sample=False,
        total_sectors=TOTAL_SECTORS,
    )
    image_path = harness.build_image(profile_name, image)
    profile = harness.PROFILES[profile_name]

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=112,
        rows=40,
        batch_steps=250_000,
        ext_mem_size=EXT_MEMORY_BYTES,
        num_cores=1,
    ) as machine:
        machine.boot()
        reports = []
        for index, (stage_name, _, marker) in enumerate(LOAD_STAGES):
            print(f"Capability load {stage_name}: starting", flush=True)
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=PHASE_MAX_STEPS,
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
            reports.append((f"load {stage_name}", report))
            if marker not in raw or failures:
                return _report_failure(
                    stage_name, report, raw, failures, machine
                )

        for stage_name, _, marker in CONTRACT_STAGES:
            print(f"Capability contract {stage_name}: starting", flush=True)
            machine.clear_output()
            machine.send_text("x")
            report = machine.run(
                max_steps=PHASE_MAX_STEPS,
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
            reports.append((f"contract {stage_name}", report))
            if marker not in raw or failures:
                return _report_failure(
                    stage_name, report, raw, failures, machine
                )

        machine.clear_output()
        machine.send_text("x")
        report = machine.run(
            max_steps=PHASE_MAX_STEPS,
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
        match = re.search(r"STREAMS BURROW CAPS PASS[ \t]+([0-9]+)", raw)
        ok = match is not None and not failures
        print(
            "Streams Burrow capabilities: "
            f"{'PASS' if ok else 'FAIL'}"
            f"{f' ({match.group(1)} checks)' if match else ''}"
        )
        for label, stage_report in reports:
            print(
                f"  {label}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        if not ok:
            return _report_failure("final", report, raw, failures, machine)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--caps", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS BURROW CAPS STATIC PASS")
        return 0
    return _run_caps(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
