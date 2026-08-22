#!/usr/bin/env python3
"""Qualify the real Streams callbacks against a composed Burrow manager."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"


PROFILE = "streams-burrow-lifecycle-linked"
IMAGE = Path("/tmp/akashic-streams-burrow-lifecycle-linked.img")
RABBIT_CAPABILITIES = (
    SOURCE_ROOT / "tui" / "applets" / "streams" / "rabbit-capabilities.f"
)
STREAMS = SOURCE_ROOT / "tui" / "applets" / "streams" / "streams.f"
SCRIPTED_PROVIDER = LOCAL_TESTING / "streams-burrow-prov.f"
FIXTURE = LOCAL_TESTING / "streams-burrow-life.f"

BOOT_MARKER = "STREAMS BURROW LIFECYCLE USERLAND READY"
PASS_MARKER = "STREAMS BURROW LIFECYCLE PASS"
# Full linked Streams profiles already qualify under this retained ceiling;
# only the cold source compilation uses it.  Fixture loads and every runtime
# callback phase remain under the focused 120M-step ceiling below.
BOOT_MAX_STEPS = 8_000_000_000
PHASE_MAX_STEPS = 120_000_000
TOTAL_SECTORS = 8192
EXT_MEMORY_BYTES = 64 << 20
NUM_CORES = 1
LINK_ROOTS = (
    "tui/applets/streams/rabbit-capabilities.f",
    "tui/applets/streams/streams.f",
)

LOAD_STAGES = (
    (
        "scripted-provider",
        "local_testing/streams-burrow-prov.f",
        "STREAMS BURROW LIFECYCLE PROVIDER READY",
    ),
    (
        "fixture",
        "local_testing/streams-burrow-life.f",
        "STREAMS BURROW LIFECYCLE FIXTURE READY",
    ),
)

CONTRACT_STAGES = (
    (
        "prepare-start",
        "_SBL-PREPARE",
        "STREAMS BURROW LIFECYCLE STARTING PASS",
    ),
    (
        "tick-running",
        "_SBL-TO-RUNNING",
        "STREAMS BURROW LIFECYCLE RUNNING PASS",
    ),
    (
        "close-retained",
        "_SBL-CLOSE-RETAINED",
        "STREAMS BURROW LIFECYCLE CLOSE PASS",
    ),
)

FAILURE_MARKERS = (
    "STREAMS BURROW LIFECYCLE FAIL",
    "STREAMS BURROW LIFECYCLE ASSERT",
    "STREAMS BURROW LIFECYCLE STACK",
    "STREAMS BURROW LIFECYCLE BOOT STACK",
    "STREAMS BURROW LIFECYCLE LOAD STACK FAIL",
    "DRIVER THROW",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
)


def _forth_code(source: str) -> str:
    return "\n".join(
        line.split("\\", 1)[0] for line in source.splitlines()
    )


def _assert_static_contracts() -> None:
    rabbit = RABBIT_CAPABILITIES.read_text(encoding="utf-8")
    streams = STREAMS.read_text(encoding="utf-8")
    provider = SCRIPTED_PROVIDER.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert BOOT_MAX_STEPS == 8_000_000_000
    assert PHASE_MAX_STEPS == 120_000_000
    assert TOTAL_SECTORS == 8192
    assert EXT_MEMORY_BYTES == 64 << 20
    assert NUM_CORES == 1
    assert LINK_ROOTS == (
        "tui/applets/streams/rabbit-capabilities.f",
        "tui/applets/streams/streams.f",
    )
    assert "4 CONSTANT STREAMS-BURROW-CAPABILITY-COUNT" in rabbit
    assert "[DEFINED] STREAMS-BURROW-CAPABILITY-COUNT [IF]" in streams
    assert "CONSTANT _STM-BURROW-BUILD?" in streams
    assert "_STM-BURROW-BUILD? [IF] 19 [ELSE] 15 [THEN]" in streams
    for word in (
        "STREAMS-BURROW-COMPOSITION-STATE!",
        "STREAMS-INIT-CB",
        "STREAMS-TICK-CB",
        "STREAMS-REQUEST-CLOSE-CB",
        "STREAMS-SHUTDOWN-CB",
    ):
        assert re.search(rf"^:\s+{re.escape(word)}(?=\s)", streams, re.MULTILINE)

    assert "PROVIDED akashic-test-srbprov" in provider
    assert "PROVIDED akashic-test-srblife" in fixture
    for marker in (
        "STREAMS-BURROW-COMPOSITION-STATE!",
        "SRBMGR-OP-START _STM-BURROW-UI-MUTATE",
        "STREAMS-TICK-CB",
        "STREAMS-REQUEST-CLOSE-CB",
        "APP-CLOSE-D-CANCEL",
        "APP-CLOSE-D-ALLOW",
        "STREAMS-SHUTDOWN-CB",
        "CINST-FREE",
        "HEAP-FREE-BYTES _SBL-HEAP-BASELINE @ =",
        "STREAMS-COMP-DESC COMP.CAPS-N @ 19 =",
    ):
        assert marker in fixture
    for phase, _, _ in CONTRACT_STAGES:
        assert phase
    for _, word, _ in CONTRACT_STAGES:
        assert re.search(rf"^:\s+{re.escape(word)}\b", fixture, re.MULTILINE)
    assert re.search(r"^:\s+_SBL-FINISH\b", fixture, re.MULTILINE)
    assert "SBSP-SIZE" in fixture
    assert "SRBMGR-DECLARATION-SIZE" in fixture
    assert "SRBMGR-REPLAY-SIZE" in fixture
    assert "SRBMGR-TICK" not in fixture
    assert "SRBMGR-QUIESCE" not in fixture
    assert "4096" not in fixture
    assert "65536" not in fixture
    assert not re.search(r"\?DO|\bDO\b", _forth_code(fixture))

    guests = tuple(module for _, module, _ in LOAD_STAGES)
    assert len(set(guests)) == len(guests)
    assert all(len(Path(guest).name.encode("utf-8")) <= 23 for guest in guests)


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


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - real Streams Burrow lifecycle callbacks\n",
        "ENTER-USERLAND\n",
        # The order is semantic: Streams selects its full 19-cap build only
        # when the Rabbit extension has already defined its capability count.
        "REQUIRE tui/applets/streams/rabbit-capabilities.f\n",
        "REQUIRE tui/applets/streams/streams.f\n",
        "DEPTH IF\n",
        (
            '." STREAMS BURROW LIFECYCLE BOOT STACK " '
            "DEPTH . CR .S CR TX-FLUSH\n"
        ),
        "THEN\n",
        f'." {BOOT_MARKER}" CR TX-FLUSH\n',
        "KEY DROP\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        lines.extend(
            (
                f"REQUIRE {module}\n",
                "DEPTH IF\n",
                (
                    '." STREAMS BURROW LIFECYCLE LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH\n'
                ),
                "THEN\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker in CONTRACT_STAGES:
        lines.extend(
            (
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    lines.append("_SBL-FINISH TX-FLUSH\n")
    return "".join(lines)


def _report_failure(stage, report, raw, failures, machine) -> int:
    print(f"Streams Burrow lifecycle {stage}: FAIL")
    print(
        f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
        f"stop={report.reason}"
    )
    for failure in failures:
        print(f"  {failure}")
    if len(raw) > 8000:
        print(raw[:4000])
        print("\n... lifecycle trace middle omitted ...\n")
    print(raw[-4000:])
    print(machine.screen_text())
    return 1


def _run_lifecycle(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    harness.PROFILES[PROFILE] = harness.Profile(
        roots=LINK_ROOTS,
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=_initial_files(harness),
        linked=True,
        include_large_sample=False,
        total_sectors=TOTAL_SECTORS,
    )
    image_path = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    stages = (
        ("boot", BOOT_MARKER),
        *((name, marker) for name, _, marker in LOAD_STAGES),
        *((name, marker) for name, _, marker in CONTRACT_STAGES),
        ("shutdown-fini", PASS_MARKER),
    )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=112,
        rows=40,
        batch_steps=250_000,
        ext_mem_size=EXT_MEMORY_BYTES,
        num_cores=NUM_CORES,
    ) as machine:
        machine.boot()
        reports = []
        for index, (stage_name, marker) in enumerate(stages):
            print(f"Lifecycle {stage_name}: starting", flush=True)
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=(BOOT_MAX_STEPS if index == 0 else PHASE_MAX_STEPS),
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
                return _report_failure(
                    stage_name, report, raw, failures, machine
                )

        match = re.search(
            r"STREAMS BURROW LIFECYCLE PASS[ \t]+([0-9]+)", raw
        )
        ok = match is not None
        print(
            "Streams Burrow lifecycle: "
            f"{'PASS' if ok else 'FAIL'}"
            f"{f' ({match.group(1)} checks)' if match else ''}"
        )
        for label, stage_report in reports:
            print(
                f"  {label}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        if not ok:
            return _report_failure(
                "shutdown-fini", report, raw, failures, machine
            )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--lifecycle", action="store_true")
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS BURROW LIFECYCLE STATIC PASS")
        return 0
    return _run_lifecycle(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
