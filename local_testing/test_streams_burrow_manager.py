#!/usr/bin/env python3
"""Qualify the caller-sized Streams Rabbit lifecycle manager."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
PROVIDER = ROOT / "akashic" / "tui" / "applets" / "streams" / "rabbit-provider.f"
MANAGER = ROOT / "akashic" / "tui" / "applets" / "streams" / "rabbit-manager.f"
SCRIPTED_PROVIDER = LOCAL_TESTING / "streams-burrow-prov.f"
FIXTURE = LOCAL_TESTING / "streams-burrow-mgr.f"

PASS_MARKER = "STREAMS BURROW MANAGER PASS"
PHASE_MAX_STEPS = 120_000_000
TOTAL_SECTORS = 4096
EXT_MEMORY_BYTES = 64 << 20

LOAD_STAGES = (
    ("identity", "runtime/identity.f", "STREAMS MANAGER IDENTITY READY"),
    (
        "memory-span",
        "utils/memory-span.f",
        "STREAMS MANAGER MEMORY SPAN READY",
    ),
    ("sha3", "math/sha3.f", "STREAMS MANAGER SHA3 READY"),
    (
        "provider",
        "tui/applets/streams/rabbit-provider.f",
        "STREAMS MANAGER PROVIDER READY",
    ),
    (
        "manager",
        "tui/applets/streams/rabbit-manager.f",
        "STREAMS MANAGER OWNER READY",
    ),
    (
        "scripted-provider",
        "local_testing/streams-burrow-prov.f",
        "STREAMS MANAGER SCRIPTED PROVIDER READY",
    ),
    (
        "fixture",
        "local_testing/streams-burrow-mgr.f",
        "STREAMS MANAGER FIXTURE READY",
    ),
)

CONTRACT_STAGES = (
    (
        "geometry",
        "_SBM-PHASE-GEOMETRY",
        "STREAMS BURROW MANAGER GEOMETRY PASS",
    ),
    (
        "create",
        "_SBM-PHASE-CREATE",
        "STREAMS BURROW MANAGER CREATE PASS",
    ),
    (
        "acquire-rollback",
        "_SBM-PHASE-ACQUIRE-ROLLBACK",
        "STREAMS BURROW MANAGER ACQUIRE ROLLBACK PASS",
    ),
    (
        "open-rollback",
        "_SBM-PHASE-OPEN-ROLLBACK",
        "STREAMS BURROW MANAGER OPEN ROLLBACK PASS",
    ),
    (
        "running-replay",
        "_SBM-PHASE-RUNNING-REPLAY",
        "STREAMS BURROW MANAGER RUNNING REPLAY PASS",
    ),
    (
        "stop-pending",
        "_SBM-PHASE-STOP-PENDING",
        "STREAMS BURROW MANAGER STOP PENDING PASS",
    ),
    (
        "blocked-retry",
        "_SBM-PHASE-BLOCKED-RETRY",
        "STREAMS BURROW MANAGER BLOCKED RETRY PASS",
    ),
    (
        "quiesce-fini",
        "_SBM-PHASE-QUIESCE-FINI",
        "STREAMS BURROW MANAGER QUIESCE FINI PASS",
    ),
    (
        "capacity-tamper",
        "_SBM-PHASE-CAPACITY-TAMPER",
        "STREAMS BURROW MANAGER CAPACITY TAMPER PASS",
    ),
)


def _assert_static_contracts() -> None:
    provider = PROVIDER.read_text(encoding="utf-8")
    manager = MANAGER.read_text(encoding="utf-8")
    scripted = SCRIPTED_PROVIDER.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == 120_000_000
    assert TOTAL_SECTORS == 4096
    assert EXT_MEMORY_BYTES == 64 << 20
    assert "PROVIDED akashic-streams-srbp" in provider
    assert "PROVIDED akashic-streams-rmgr" in manager
    assert "PROVIDED akashic-test-srbprov" in scripted
    assert "PROVIDED akashic-test-srbmgr" in fixture
    for word in (
        "SRBMGR-INIT",
        "SRBMGR-VALID?",
        "SRBMGR-PLAN-CREATE",
        "SRBMGR-PLAN-STATUS",
        "SRBMGR-PLAN-START",
        "SRBMGR-PLAN-STOP",
        "SRBMGR-COMMIT",
        "SRBMGR-TICK",
        "SRBMGR-QUIESCE",
        "SRBMGR-CANCEL",
        "SRBMGR-FINI",
    ):
        assert f": {word}" in manager
    for _, word, _ in CONTRACT_STAGES:
        assert f": {word}" in fixture

    assert "SRBPROV-S-PENDING SRBPROV-D-BURROW-OPEN" in fixture
    assert "SRBPROV-S-IO SRBPROV-D-PROVIDER-RELEASE" in fixture
    assert "SRBMGR-PLAN-FRESH? 0=" in fixture
    assert "SRBMGR.REPLAY-COUNT @ _SBM-COUNT @ =" in fixture
    assert "SRBMGR.SERIAL @ _SBM-SERIAL @ =" in fixture
    assert "SRBMGR-DECL.SERVICE-COUNT @ 3 =" in fixture
    assert "SBSP-OP-RELEASE _SBM-PROVIDER SBSP-COUNT@" in fixture
    assert "4096" not in fixture
    assert not re.search(r"\?DO|\bDO\b", fixture)


def _initial_files(harness) -> tuple[tuple[str, bytes], ...]:
    # Both sources are intentionally supplied explicitly.  The scripted
    # provider and the Forth contract remain ignored local fixtures rather
    # than becoming product roots.
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
    print(f"Streams Burrow manager {stage}: FAIL")
    print(
        f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
        f"stop={report.reason}"
    )
    for failure in failures:
        print(f"  {failure}")
    if len(raw) > 8000:
        print(raw[:4000])
        print("\n... manager trace middle omitted ...\n")
    print(raw[-4000:])
    print(machine.screen_text())
    return 1


def _run_manager(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - source-loaded Streams Burrow manager contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                "DEPTH IF\n",
                (
                    '  ." STREAMS BURROW MANAGER LOAD STACK FAIL '
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
                f"{word}\n",
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    autoexec.append("_SBM-FINAL TX-FLUSH\n")

    profile_name = "streams-burrow-manager-source"
    image = Path("/tmp/akashic-streams-burrow-manager-source.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=("tui/applets/streams/rabbit-manager.f",),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS BURROW MANAGER FAIL",
            "STREAMS BURROW MANAGER ASSERT",
            "STREAMS BURROW MANAGER STACK",
            "STREAMS BURROW MANAGER LOAD STACK FAIL",
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
            print(f"Manager load {stage_name}: starting", flush=True)
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
            print(f"Manager contract {stage_name}: starting", flush=True)
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
        match = re.search(r"STREAMS BURROW MANAGER PASS[ \t]+([0-9]+)", raw)
        ok = match is not None and not failures
        print(
            "Streams Burrow manager: "
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
    mode.add_argument("--manager", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS BURROW MANAGER STATIC PASS")
        return 0
    return _run_manager(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
