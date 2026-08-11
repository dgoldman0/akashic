#!/usr/bin/env python3
"""Qualify two Streams typed caches through one mounted Rabbit resource."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
CONNECTOR = (
    ROOT / "akashic" / "tui" / "applets" / "streams" / "rabbit-connector.f"
)
REMOTE = ROOT / "akashic" / "tui" / "applets" / "streams" / "rabbit-remote.f"
FIXTURE = LOCAL_TESTING / "rabbit-mounted-test.f"
FIXTURE_IMAGE_PATH = "local_testing/rabbit-mounted-test.f"

sys.path.insert(0, str(LOCAL_TESTING))
import test_streams_rabbit_facet_mount as facet_mount


PASS_MARKER = "STREAMS RABBIT MOUNTED READ PASS"
PHASE_MAX_STEPS = 120_000_000

CORE_FIXTURE_INDEX = next(
    index
    for index, stage in enumerate(facet_mount.LOAD_STAGES)
    if stage[0] == "core-fixture"
)
MODULE_LOAD_STAGES = facet_mount.LOAD_STAGES[:CORE_FIXTURE_INDEX]
FIXTURE_LOAD_STAGES = facet_mount.LOAD_STAGES[CORE_FIXTURE_INDEX:]
LOAD_STAGES = (
    *MODULE_LOAD_STAGES,
    (
        "streams-connector",
        "tui/applets/streams/rabbit-connector.f",
        "MOUNTED READ CONNECTOR READY",
    ),
    (
        "remote-resource",
        "tui/applets/streams/rabbit-remote.f",
        "MOUNTED READ REMOTE RESOURCE READY",
    ),
    *FIXTURE_LOAD_STAGES,
    (
        "mounted-read-fixture",
        FIXTURE_IMAGE_PATH,
        "STREAMS RABBIT MOUNTED READ FIXTURE READY",
    ),
)

ADMISSION_PROOF_INDEX = next(
    index
    for index, stage in enumerate(facet_mount.burrow.CONTRACT_STAGES)
    if stage[0] == "admission-proof"
)
BURROW_PREFIX_STAGES = facet_mount.burrow.CONTRACT_STAGES[
    : ADMISSION_PROOF_INDEX + 1
]

MOUNTED_STAGES = (
    (
        "mounted-init",
        "_RBT-MREAD-PHASE-INIT",
        "STREAMS RABBIT MOUNTED READ INIT PASS",
    ),
    (
        "fetch-start",
        "_RBT-MREAD-PHASE-FETCH-START",
        "STREAMS RABBIT MOUNTED READ FETCH START PASS",
    ),
    *(
        (
            f"mounted-step-{index}",
            f"_RBT-MREAD-PHASE-STEP-{index}",
            f"STREAMS RABBIT MOUNTED READ STEP {index} PASS",
        )
        for index in range(1, 17)
    ),
    (
        "mounted-results",
        "_RBT-MREAD-PHASE-RESULTS",
        "STREAMS RABBIT MOUNTED READ RESULTS PASS",
    ),
    (
        "refusal-start",
        "_RBT-MREAD-PHASE-REFUSAL-START",
        "STREAMS RABBIT MOUNTED READ REFUSAL START PASS",
    ),
    *(
        (
            f"refusal-step-{index}",
            f"_RBT-MREAD-PHASE-REFUSAL-STEP-{index}",
            f"STREAMS RABBIT MOUNTED READ REFUSAL STEP {index} PASS",
        )
        for index in range(1, 13)
    ),
    (
        "refusal-results",
        "_RBT-MREAD-PHASE-REFUSAL-RESULTS",
        "STREAMS RABBIT MOUNTED READ REFUSAL RESULTS PASS",
    ),
    (
        "remote-fini",
        "_RBT-MREAD-PHASE-REMOTE-FINI",
        "STREAMS RABBIT MOUNTED READ REMOTE FINI PASS",
    ),
    (
        "connector-fini",
        "_RBT-MREAD-PHASE-CONNECTOR-FINI",
        "STREAMS RABBIT MOUNTED READ CONNECTOR FINI PASS",
    ),
    (
        "host-cancel",
        "_RBT-MREAD-PHASE-HOST-CANCEL",
        "STREAMS RABBIT MOUNTED READ HOST CANCEL PASS",
    ),
    *(
        (
            f"host-fini-{index}",
            f"_RBT-MREAD-PHASE-HOST-FINI-{index}",
            f"STREAMS RABBIT MOUNTED READ HOST FINI {index} PASS",
        )
        for index in range(1, 5)
    ),
    (
        "mounted-fini",
        "_RBT-MREAD-PHASE-FINI",
        "STREAMS RABBIT MOUNTED READ FINI PASS",
    ),
)

CONTRACT_STAGES = (*BURROW_PREFIX_STAGES, *MOUNTED_STAGES)


def _assert_static_contracts() -> None:
    facet_mount._assert_static_contracts()
    connector = CONNECTOR.read_text(encoding="utf-8")
    remote = REMOTE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == facet_mount.PHASE_MAX_STEPS == 120_000_000
    assert MODULE_LOAD_STAGES[-1][0] == "facet-mount"
    assert FIXTURE_LOAD_STAGES[0][0] == "core-fixture"
    assert "PROVIDED akashic-streams-rconn" in connector
    assert "PROVIDED akashic-streams-rres" in remote
    assert "PROVIDED rabbit-mounted-test" in fixture
    for _, word, _ in MOUNTED_STAGES:
        assert f": {word}" in fixture
    assert fixture.count("STREAMS-RABBIT-CONNECTOR-INIT") >= 2
    assert fixture.count("STREAMS-RABBIT-REMOTE-RESOURCE-INIT") >= 2
    assert "STREAMS-RABBIT-BURROW-SERVICE" not in fixture
    assert "RABBIT-CLIENT-POLL" not in fixture
    assert "RABBIT-SERVER-POLL" not in fixture
    assert "RABBIT-SERVER-SUBSCRIPTIONS-SERVICE" not in fixture
    assert "4096" not in fixture


def _initial_files(harness) -> tuple[tuple[str, bytes], ...]:
    return (
        *facet_mount._initial_files(harness),
        (
            FIXTURE_IMAGE_PATH,
            harness._minify_forth(FIXTURE.read_text(encoding="utf-8")).encode(
                "utf-8"
            ),
        ),
    )


def _profile(harness, autoexec: str):
    profile_name = "streams-rabbit-mounted-read-source"
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
            "interop/request-bus.f",
            "interop/capability-facet.f",
            "interop/codecs/json-value.f",
            "tui/applets/streams/rabbit-burrow.f",
            "tui/applets/streams/rabbit-facet-mount.f",
            "tui/applets/streams/rabbit-connector.f",
            "tui/applets/streams/rabbit-remote.f",
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT MOUNTED READ LOAD STACK FAIL",
            "STREAMS RABBIT BURROW ASSERT",
            "STREAMS RABBIT BURROW STACK",
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
    return profile_name, harness.PROFILES[profile_name]


def _run(timeout: float) -> int:
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - source-loaded two-client mounted Rabbit read\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT MOUNTED READ LOAD STACK '
                    f'FAIL {stage_name}" CR TX-FLUSH '
                    "DEPTH 0 ?DO DROP LOOP THEN\n"
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
        '." STREAMS RABBIT MOUNTED READ PASS " _RBT-CHECKS @ . '
        "CR TX-FLUSH\n"
    )

    profile_name, profile = _profile(harness, "".join(autoexec))
    image = Path("/tmp/akashic-streams-rabbit-mounted-read-source.img")
    image_path = harness.build_image(profile_name, image)

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
        all_stages = (
            *((f"load {name}", marker) for name, _, marker in LOAD_STAGES),
            *((f"contract {name}", marker) for name, _, marker in CONTRACT_STAGES),
        )
        for index, (label, marker) in enumerate(all_stages):
            print(f"Mounted read {label}: starting", flush=True)
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
            reports.append((label, report))
            if marker not in raw or failures:
                return facet_mount._report_failure(
                    label, report, raw, failures, machine
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
        match = re.search(r"STREAMS RABBIT MOUNTED READ PASS[ \t]+([0-9]+)", raw)
        ok = match is not None and not failures
        print(
            "Streams Rabbit mounted read: "
            f"{'PASS' if ok else 'FAIL'}"
            f"{f' ({match.group(1)} checks)' if match else ''}"
        )
        for label, stage_report in reports:
            print(
                f"  {label}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        if not ok:
            return facet_mount._report_failure(
                "final", report, raw, failures, machine
            )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--mounted-read", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT MOUNTED READ STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
