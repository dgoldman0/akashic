#!/usr/bin/env python3
"""Qualify the Streams-owned multi-peer Rabbit Burrow host."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
BURROW = ROOT / "akashic" / "tui" / "applets" / "streams" / "rabbit-burrow.f"
FIXTURE = LOCAL_TESTING / "rabbit-burrow-test.f"

SUPPORT_FIXTURES = (
    LOCAL_TESTING / "rabbit-client-test.f",
    LOCAL_TESTING / "rabbit-client-flow.f",
    LOCAL_TESTING / "rabbit-sub-test.f",
    LOCAL_TESTING / "rabbit-server-test.f",
    LOCAL_TESTING / "rabbit-servsub-test.f",
    LOCAL_TESTING / "rabbit-cap-test.f",
)
CORE_FIXTURE = LOCAL_TESTING / "rabbit-core-test.f"
CORE_SUPPORT_PATH = "local_testing/rbur-core.f"
CORE_SUPPORT_LINES = 284

PASS_MARKER = "STREAMS RABBIT BURROW PASS"
PHASE_MAX_STEPS = 120_000_000

LOAD_STAGES = (
    ("profile", "net/rabbit/profile.f", "BURROW PROFILE READY"),
    ("memory-span", "utils/memory-span.f", "BURROW MEMORY SPAN READY"),
    ("string", "utils/string.f", "BURROW STRING READY"),
    ("utf8", "text/utf8.f", "BURROW UTF8 READY"),
    ("io-port", "net/io-port.f", "BURROW IO PORT READY"),
    ("frame", "net/rabbit/frame.f", "BURROW FRAME READY"),
    ("message", "net/rabbit/message.f", "BURROW MESSAGE READY"),
    (
        "memory-duplex",
        "net/transports/memory-duplex.f",
        "BURROW MEMORY DUPLEX READY",
    ),
    ("session", "net/rabbit/session.f", "BURROW SESSION READY"),
    ("builder", "net/rabbit/builder.f", "BURROW BUILDER READY"),
    ("connection", "net/rabbit/connection.f", "BURROW CONNECTION READY"),
    ("client", "net/rabbit/client.f", "BURROW CLIENT READY"),
    (
        "subscription",
        "net/rabbit/subscription.f",
        "BURROW SUBSCRIPTION READY",
    ),
    ("router", "net/rabbit/router.f", "BURROW ROUTER READY"),
    ("server", "net/rabbit/server.f", "BURROW SERVER READY"),
    (
        "server-subscription",
        "net/rabbit/server-subscription.f",
        "BURROW SERVER SUBSCRIPTION READY",
    ),
    (
        "burrow",
        "tui/applets/streams/rabbit-burrow.f",
        "STREAMS RABBIT BURROW READY",
    ),
    (
        "core-fixture",
        CORE_SUPPORT_PATH,
        "BURROW CORE FIXTURE READY",
    ),
    (
        "client-fixture",
        "local_testing/rabbit-client-test.f",
        "BURROW CLIENT FIXTURE READY",
    ),
    (
        "client-flow-fixture",
        "local_testing/rabbit-client-flow.f",
        "BURROW CLIENT FLOW FIXTURE READY",
    ),
    (
        "subscription-fixture",
        "local_testing/rabbit-sub-test.f",
        "BURROW SUBSCRIPTION FIXTURE READY",
    ),
    (
        "server-fixture",
        "local_testing/rabbit-server-test.f",
        "BURROW SERVER FIXTURE READY",
    ),
    (
        "server-subscription-fixture",
        "local_testing/rabbit-servsub-test.f",
        "BURROW SERVER SUBSCRIPTION FIXTURE READY",
    ),
    (
        "capstone-fixture",
        "local_testing/rabbit-cap-test.f",
        "BURROW CAPSTONE FIXTURE READY",
    ),
    (
        "burrow-fixture",
        "local_testing/rabbit-burrow-test.f",
        "STREAMS RABBIT BURROW FIXTURE READY",
    ),
)

CONTRACT_STAGES = (
    (
        "zero-capacity",
        "_RBT-BUR-PHASE-ZERO-CAPACITY",
        "STREAMS RABBIT BURROW ZERO CAPACITY PASS",
    ),
    (
        "geometry",
        "_RBT-BUR-PHASE-GEOMETRY",
        "STREAMS RABBIT BURROW GEOMETRY PASS",
    ),
    (
        "compose-a",
        "_RBT-BUR-PHASE-COMPOSE-A",
        "STREAMS RABBIT BURROW COMPOSE A PASS",
    ),
    (
        "compose-duplicate",
        "_RBT-BUR-PHASE-COMPOSE-DUPLICATE",
        "STREAMS RABBIT BURROW COMPOSE DUPLICATE PASS",
    ),
    (
        "compose-alias",
        "_RBT-BUR-PHASE-COMPOSE-ALIAS",
        "STREAMS RABBIT BURROW COMPOSE ALIAS PASS",
    ),
    (
        "compose-b",
        "_RBT-BUR-PHASE-COMPOSE-B",
        "STREAMS RABBIT BURROW COMPOSE B PASS",
    ),
    (
        "published-bindings",
        "_RBT-BUR-PHASE-PUBLISHED-BINDINGS",
        "STREAMS RABBIT BURROW PUBLISHED BINDINGS PASS",
    ),
    (
        "activate",
        "_RBT-BUR-PHASE-ACTIVATE",
        "STREAMS RABBIT BURROW ACTIVATE PASS",
    ),
    (
        "admission-a-start",
        "_RBT-BUR-PHASE-ADMISSION-A-START",
        "STREAMS RABBIT BURROW ADMISSION A START PASS",
    ),
    (
        "admission-a-host",
        "_RBT-BUR-PHASE-ADMISSION-A-HOST",
        "STREAMS RABBIT BURROW ADMISSION A HOST PASS",
    ),
    (
        "admission-a-client",
        "_RBT-BUR-PHASE-ADMISSION-A-CLIENT",
        "STREAMS RABBIT BURROW ADMISSION A CLIENT PASS",
    ),
    (
        "admission-b-start",
        "_RBT-BUR-PHASE-ADMISSION-B-START",
        "STREAMS RABBIT BURROW ADMISSION B START PASS",
    ),
    (
        "admission-b-host",
        "_RBT-BUR-PHASE-ADMISSION-B-HOST",
        "STREAMS RABBIT BURROW ADMISSION B HOST PASS",
    ),
    (
        "admission-b-client",
        "_RBT-BUR-PHASE-ADMISSION-B-CLIENT",
        "STREAMS RABBIT BURROW ADMISSION B CLIENT PASS",
    ),
    (
        "admission-proof",
        "_RBT-BUR-PHASE-ADMISSION-PROOF",
        "STREAMS RABBIT BURROW ADMISSION PROOF PASS",
    ),
    (
        "fair-start",
        "_RBT-BUR-PHASE-FAIR-START",
        "STREAMS RABBIT BURROW FAIR START PASS",
    ),
    (
        "fair-step-1",
        "_RBT-BUR-PHASE-FAIR-STEP-1",
        "STREAMS RABBIT BURROW FAIR STEP 1 PASS",
    ),
    (
        "fair-step-2",
        "_RBT-BUR-PHASE-FAIR-STEP-2",
        "STREAMS RABBIT BURROW FAIR STEP 2 PASS",
    ),
    (
        "fair-step-3",
        "_RBT-BUR-PHASE-FAIR-STEP-3",
        "STREAMS RABBIT BURROW FAIR STEP 3 PASS",
    ),
    (
        "fair-step-4",
        "_RBT-BUR-PHASE-FAIR-STEP-4",
        "STREAMS RABBIT BURROW FAIR STEP 4 PASS",
    ),
    (
        "fair-step-5",
        "_RBT-BUR-PHASE-FAIR-STEP-5",
        "STREAMS RABBIT BURROW FAIR STEP 5 PASS",
    ),
    (
        "fair-step-6",
        "_RBT-BUR-PHASE-FAIR-STEP-6",
        "STREAMS RABBIT BURROW FAIR STEP 6 PASS",
    ),
    (
        "fair-step-7",
        "_RBT-BUR-PHASE-FAIR-STEP-7",
        "STREAMS RABBIT BURROW FAIR STEP 7 PASS",
    ),
    (
        "fair-step-8",
        "_RBT-BUR-PHASE-FAIR-STEP-8",
        "STREAMS RABBIT BURROW FAIR STEP 8 PASS",
    ),
    (
        "fair-results",
        "_RBT-BUR-PHASE-FAIR-RESULTS",
        "STREAMS RABBIT BURROW FAIR RESULTS PASS",
    ),
    (
        "detach",
        "_RBT-BUR-PHASE-DETACH",
        "STREAMS RABBIT BURROW DETACH PASS",
    ),
    (
        "detached-a-start",
        "_RBT-BUR-PHASE-DETACHED-A-START",
        "STREAMS RABBIT BURROW DETACHED A START PASS",
    ),
    (
        "detached-a-host",
        "_RBT-BUR-PHASE-DETACHED-A-HOST",
        "STREAMS RABBIT BURROW DETACHED A HOST PASS",
    ),
    (
        "detached-a-client",
        "_RBT-BUR-PHASE-DETACHED-A-CLIENT",
        "STREAMS RABBIT BURROW DETACHED A CLIENT PASS",
    ),
    (
        "rebuild-b-client",
        "_RBT-BUR-PHASE-REBUILD-B-CLIENT",
        "STREAMS RABBIT BURROW REBUILD B CLIENT PASS",
    ),
    (
        "rebuild-b-server",
        "_RBT-BUR-PHASE-REBUILD-B-SERVER",
        "STREAMS RABBIT BURROW REBUILD B SERVER PASS",
    ),
    (
        "replace-b",
        "_RBT-BUR-PHASE-REPLACE-B",
        "STREAMS RABBIT BURROW REPLACE B PASS",
    ),
    (
        "readmit-b-start",
        "_RBT-BUR-PHASE-READMIT-B-START",
        "STREAMS RABBIT BURROW READMIT B START PASS",
    ),
    (
        "readmit-b-host",
        "_RBT-BUR-PHASE-READMIT-B-HOST",
        "STREAMS RABBIT BURROW READMIT B HOST PASS",
    ),
    (
        "readmit-b-client",
        "_RBT-BUR-PHASE-READMIT-B-CLIENT",
        "STREAMS RABBIT BURROW READMIT B CLIENT PASS",
    ),
    (
        "cleanup-begin",
        "_RBT-BUR-PHASE-CLEANUP-BEGIN",
        "STREAMS RABBIT BURROW CLEANUP BEGIN PASS",
    ),
    (
        "cleanup-proof",
        "_RBT-BUR-PHASE-CLEANUP-PROOF",
        "STREAMS RABBIT BURROW CLEANUP PROOF PASS",
    ),
    (
        "cleanup-retry",
        "_RBT-BUR-PHASE-CLEANUP-RETRY",
        "STREAMS RABBIT BURROW CLEANUP RETRY PASS",
    ),
    (
        "cleanup-retry-proof",
        "_RBT-BUR-PHASE-CLEANUP-RETRY-PROOF",
        "STREAMS RABBIT BURROW CLEANUP RETRY PROOF PASS",
    ),
    (
        "fini",
        "_RBT-BUR-PHASE-FINI",
        "STREAMS RABBIT BURROW FINI PASS",
    ),
)


def _assert_static_contracts() -> None:
    burrow = BURROW.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == 120_000_000
    assert "PROVIDED akashic-streams-rburrow" in burrow
    for word in (
        "STREAMS-RABBIT-BURROW-INIT",
        "STREAMS-RABBIT-BURROW-ADD",
        "STREAMS-RABBIT-BURROW-SEAL",
        "STREAMS-RABBIT-BURROW-OPEN",
        "STREAMS-RABBIT-BURROW-SERVICE",
        "STREAMS-RABBIT-BURROW-DETACH",
        "STREAMS-RABBIT-BURROW-REPLACE",
        "STREAMS-RABBIT-BURROW-CANCEL",
        "STREAMS-RABBIT-BURROW-FINI",
        "STREAMS-RABBIT-BURROW-ADMIT",
        "STREAMS-RABBIT-BURROW-ACTIVE-BINDING@",
    ):
        assert f": {word}" in burrow

    for _, word, _ in CONTRACT_STAGES:
        assert f": {word}" in fixture

    assert "['] STREAMS-RABBIT-BURROW-ADMIT" in fixture
    assert "STREAMS-RABBIT-BURROW-SERVICE" in fixture
    assert "RABBIT-SERVER-POLL" not in fixture
    assert "RABBIT-SERVER-SUBSCRIPTIONS-SERVICE" not in fixture
    assert "4096" not in fixture  # Disk geometry belongs only to this driver.
    assert re.search(r"\b128 0 \?DO\b", fixture)


def _initial_files(harness) -> tuple[tuple[str, bytes], ...]:
    paths = (*SUPPORT_FIXTURES, FIXTURE)
    core_lines = CORE_FIXTURE.read_text(encoding="utf-8").splitlines(
        keepends=True
    )
    assert core_lines[CORE_SUPPORT_LINES - 1].rstrip().endswith(";")
    core_support = "".join(core_lines[:CORE_SUPPORT_LINES])
    support = tuple(
        (
            str(path.relative_to(ROOT)),
            harness._minify_forth(path.read_text(encoding="utf-8")).encode("utf-8"),
        )
        for path in paths
    )
    return (
        (
            CORE_SUPPORT_PATH,
            harness._minify_forth(core_support).encode("utf-8"),
        ),
        *support,
    )


def _run_burrow(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - source-loaded Streams Rabbit Burrow contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT BURROW LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
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
    autoexec.append(
        '." STREAMS RABBIT BURROW PASS " _RBT-CHECKS @ . CR TX-FLUSH\n'
    )

    profile_name = "streams-rabbit-burrow-source"
    image = Path("/tmp/akashic-streams-rabbit-burrow-source.img")
    harness.PROFILES[profile_name] = harness.Profile(
        roots=(
            "net/rabbit/profile.f",
            "net/rabbit/frame.f",
            "net/rabbit/message.f",
            "net/rabbit/builder.f",
            "net/transports/memory-duplex.f",
            "net/rabbit/session.f",
            "net/rabbit/connection.f",
            "net/rabbit/client.f",
            "net/rabbit/subscription.f",
            "net/rabbit/router.f",
            "net/rabbit/server.f",
            "net/rabbit/server-subscription.f",
            "tui/applets/streams/rabbit-burrow.f",
        ),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT BURROW ASSERT",
            "STREAMS RABBIT BURROW STACK",
            "STREAMS RABBIT BURROW LOAD STACK FAIL",
            "RABBIT CORE ASSERT",
            "RABBIT CORE STACK",
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
        total_sectors=4096,
    )
    image_path = harness.build_image(profile_name, image)
    profile = harness.PROFILES[profile_name]

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=110,
        rows=38,
        batch_steps=250_000,
        ext_mem_size=64 << 20,
        num_cores=1,
    ) as machine:
        machine.boot()
        reports = []
        for index, (stage_name, _, marker) in enumerate(LOAD_STAGES):
            print(f"Burrow load {stage_name}: starting", flush=True)
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
                return _report_failure(stage_name, report, raw, failures, machine)

        for stage_name, _, marker in CONTRACT_STAGES:
            print(f"Burrow contract {stage_name}: starting", flush=True)
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
                return _report_failure(stage_name, report, raw, failures, machine)

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
        match = re.search(r"STREAMS RABBIT BURROW PASS[ \t]+([0-9]+)", raw)
        ok = match is not None and not failures
        print(
            "Streams Rabbit Burrow: "
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


def _report_failure(stage, report, raw, failures, machine) -> int:
    print(f"Burrow {stage}: FAIL")
    print(
        f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
        f"stop={report.reason}"
    )
    for failure in failures:
        print(f"  {failure}")
    if len(raw) > 8000:
        print(raw[:4000])
        print("\n... Burrow trace middle omitted ...\n")
    print(raw[-4000:])
    print(machine.screen_text())
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--burrow", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT BURROW STATIC PASS")
        return 0
    return _run_burrow(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
