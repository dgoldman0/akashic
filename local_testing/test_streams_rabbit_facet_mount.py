#!/usr/bin/env python3
"""Qualify the Streams Rabbit observe-facet bridge through a live Burrow."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
MOUNT = (
    ROOT
    / "akashic"
    / "tui"
    / "applets"
    / "streams"
    / "rabbit-facet-mount.f"
)
FIXTURE = LOCAL_TESTING / "rabbit-facet-mount-test.f"
FIXTURE_IMAGE_PATH = "local_testing/rfmount-test.f"

sys.path.insert(0, str(LOCAL_TESTING))
import test_streams_rabbit_burrow as burrow


PASS_MARKER = "STREAMS RABBIT FACET MOUNT PASS"
PHASE_MAX_STEPS = 120_000_000

FACET_STAGE_INDEX = next(
    index
    for index, stage in enumerate(burrow.LOAD_STAGES)
    if stage[0] == "capability-facet"
)
BURROW_STAGE_INDEX = next(
    index for index, stage in enumerate(burrow.LOAD_STAGES) if stage[0] == "burrow"
)
NETWORK_LOAD_STAGES = burrow.LOAD_STAGES[:FACET_STAGE_INDEX]
FIXTURE_LOAD_STAGES = burrow.LOAD_STAGES[BURROW_STAGE_INDEX + 1 :]
LOAD_STAGES = (
    *NETWORK_LOAD_STAGES,
    (
        "capability-facet",
        "interop/capability-facet.f",
        "FACET MOUNT CAPABILITY FACET READY",
    ),
    (
        "burrow",
        "tui/applets/streams/rabbit-burrow.f",
        "FACET MOUNT BURROW READY",
    ),
    (
        "json-value",
        "interop/codecs/json-value.f",
        "FACET MOUNT JSON VALUE READY",
    ),
    (
        "registry",
        "runtime/registry.f",
        "FACET MOUNT REGISTRY READY",
    ),
    (
        "request-bus",
        "interop/request-bus.f",
        "FACET MOUNT REQUEST BUS READY",
    ),
    (
        "facet-mount",
        "tui/applets/streams/rabbit-facet-mount.f",
        "STREAMS RABBIT FACET MOUNT READY",
    ),
    *FIXTURE_LOAD_STAGES,
    (
        "facet-mount-fixture",
        FIXTURE_IMAGE_PATH,
        "STREAMS RABBIT FACET MOUNT FIXTURE READY",
    ),
)

def _request_case_stages(
    name: str,
    start_word: str,
    results_word: str,
    *,
    step_word: str = "_RBT-FM-PHASE-REQUEST-STEP",
) -> tuple[tuple[str, str, str], ...]:
    label = name.replace("-", " ").upper()
    return (
        (
            f"mount-{name}-start",
            start_word,
            f"STREAMS RABBIT FACET MOUNT {label} START PASS",
        ),
        *((
            f"mount-{name}-step-{index}",
            step_word,
            f"STREAMS RABBIT FACET MOUNT {label} STEP {index} PASS",
        ) for index in range(1, 9)),
        (
            f"mount-{name}-results",
            results_word,
            f"STREAMS RABBIT FACET MOUNT {label} RESULTS PASS",
        ),
    )


MOUNT_CONTRACT_STAGES = (
    (
        "mount-bound",
        "_RBT-FM-PHASE-BOUND",
        "STREAMS RABBIT FACET MOUNT BOUND PASS",
    ),
    *_request_case_stages(
        "deny",
        "_RBT-FM-PHASE-DENY-START",
        "_RBT-FM-PHASE-DENY-RESULTS",
    ),
    *_request_case_stages(
        "throw",
        "_RBT-FM-PHASE-THROW-START",
        "_RBT-FM-PHASE-THROW-RESULTS",
    ),
    *_request_case_stages(
        "stale-caller",
        "_RBT-FM-PHASE-STALE-CALLER-START",
        "_RBT-FM-PHASE-STALE-CALLER-RESULTS",
    ),
    *_request_case_stages(
        "runtime-alias",
        "_RBT-FM-PHASE-ALIAS-START",
        "_RBT-FM-PHASE-ALIAS-RESULTS",
        step_word="_RBT-FM-PHASE-ALIAS-STEP",
    ),
    *_request_case_stages(
        "success",
        "_RBT-FM-PHASE-SUCCESS-START",
        "_RBT-FM-PHASE-SUCCESS-RESULTS",
    ),
    *_request_case_stages(
        "profile-success",
        "_RBT-FM-PHASE-PROFILE-SUCCESS-START",
        "_RBT-FM-PHASE-PROFILE-SUCCESS-RESULTS",
    ),
    *_request_case_stages(
        "profile-throw",
        "_RBT-FM-PHASE-PROFILE-THROW-START",
        "_RBT-FM-PHASE-PROFILE-THROW-RESULTS",
    ),
    *_request_case_stages(
        "profile-stack",
        "_RBT-FM-PHASE-PROFILE-STACK-START",
        "_RBT-FM-PHASE-PROFILE-STACK-RESULTS",
    ),
    *_request_case_stages(
        "profile-malformed",
        "_RBT-FM-PHASE-PROFILE-MALFORMED-START",
        "_RBT-FM-PHASE-PROFILE-MALFORMED-RESULTS",
    ),
    *_request_case_stages(
        "profile-schema",
        "_RBT-FM-PHASE-PROFILE-SCHEMA-START",
        "_RBT-FM-PHASE-PROFILE-SCHEMA-RESULTS",
    ),
    (
        "mount-fini-borrowed",
        "_RBT-FM-PHASE-FINI-BORROWED",
        "STREAMS RABBIT FACET MOUNT BORROWED FINI PASS",
    ),
)


def _contract_stages() -> tuple[tuple[str, str, str], ...]:
    stages: list[tuple[str, str, str]] = []
    for stage in burrow.CONTRACT_STAGES:
        stages.append(stage)
        if stage[0] == "admission-proof":
            stages.extend(MOUNT_CONTRACT_STAGES)
    stages.append(
        (
            "mount-fini",
            "_RBT-FM-PHASE-FINI",
            "STREAMS RABBIT FACET MOUNT FINI PASS",
        )
    )
    return tuple(stages)


CONTRACT_STAGES = _contract_stages()


def _assert_static_contracts() -> None:
    burrow._assert_static_contracts()
    mount = MOUNT.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == burrow.PHASE_MAX_STEPS == 120_000_000
    assert NETWORK_LOAD_STAGES[-1][0] == "server-subscription"
    assert FIXTURE_LOAD_STAGES[0][0] == "core-fixture"
    assert "PROVIDED akashic-streams-rfmount" in mount
    for word in (
        "STREAMS-RABBIT-FACET-MOUNT-INIT",
        "STREAMS-RABBIT-FACET-MOUNT-INIT-PROFILED",
        "STREAMS-RABBIT-FACET-MOUNT-BINDING-VALID?",
        "STREAMS-RABBIT-FACET-MOUNT-VALID?",
        "STREAMS-RABBIT-FACET-MOUNT-LAST@",
        "STREAMS-RABBIT-FACET-MOUNT-ROUTE@",
        "STREAMS-RABBIT-FACET-MOUNT-FINI",
    ):
        assert f": {word}" in mount
    for _, word, _ in MOUNT_CONTRACT_STAGES:
        assert f": {word}" in fixture
    assert ": _RBT-FM-PHASE-FINI" in fixture
    assert "CAP.EFFECTS @ CAP-E-OBSERVE <>" in mount
    assert "COMP-CAPS-GRAPH-SPAN-OVERLAP?" in mount
    assert "STREAMS-RABBIT-BURROW-ACTIVE-BINDING@" in mount
    assert "CBUS-DISPATCH" in mount
    assert "RABBIT-SERVER-POLL" not in mount
    assert "RABBIT-SERVER-SUBSCRIPTIONS-SERVICE" not in mount


def _initial_files(harness) -> tuple[tuple[str, bytes], ...]:
    return (
        *burrow._initial_files(harness),
        (
            FIXTURE_IMAGE_PATH,
            harness._minify_forth(FIXTURE.read_text(encoding="utf-8")).encode(
                "utf-8"
            ),
        ),
    )


def _profile(harness, autoexec: str):
    profile_name = "streams-rabbit-facet-mount-source"
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
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT BURROW ASSERT",
            "STREAMS RABBIT BURROW STACK",
            "STREAMS RABBIT FACET MOUNT LOAD STACK FAIL",
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
        "\\ autoexec.f - source-loaded Streams Rabbit facet mount contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT FACET MOUNT LOAD STACK FAIL '
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
        '." STREAMS RABBIT FACET MOUNT PASS " _RBT-CHECKS @ . CR TX-FLUSH\n'
    )

    profile_name, profile = _profile(harness, "".join(autoexec))
    image = Path("/tmp/akashic-streams-rabbit-facet-mount-source.img")
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
            print(f"Facet mount {label}: starting", flush=True)
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
                return _report_failure(label, report, raw, failures, machine)

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
        match = re.search(
            r"STREAMS RABBIT FACET MOUNT PASS[ \t]+([0-9]+)", raw
        )
        ok = match is not None and not failures
        print(
            "Streams Rabbit facet mount: "
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


def _report_failure(label, report, raw, failures, machine) -> int:
    print(f"Facet mount {label}: FAIL")
    print(
        f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
        f"stop={report.reason}"
    )
    for failure in failures:
        print(f"  {failure}")
    if len(raw) > 8000:
        print(raw[:4000])
        print("\n... facet mount trace middle omitted ...\n")
    print(raw[-4000:])
    print(machine.screen_text())
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--mount", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT FACET MOUNT STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
