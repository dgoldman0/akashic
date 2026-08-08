#!/usr/bin/env python3
"""Qualify the effectful Streams Rabbit PUBLISH-to-Practice bridge."""

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
    / "rabbit-action-mount.f"
)
FIXTURE = LOCAL_TESTING / "rabbit-action-mount-test.f"
FIXTURE_IMAGE_PATH = "local_testing/ramount-test.f"

sys.path.insert(0, str(LOCAL_TESTING))
import test_streams_rabbit_burrow as burrow


PASS_MARKER = "STREAMS RABBIT ACTION MOUNT PASS"
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
        "ACTION MOUNT CAPABILITY FACET READY",
    ),
    (
        "burrow",
        "tui/applets/streams/rabbit-burrow.f",
        "ACTION MOUNT BURROW READY",
    ),
    (
        "json-value",
        "interop/codecs/json-value.f",
        "ACTION MOUNT JSON VALUE READY",
    ),
    (
        "registry",
        "runtime/registry.f",
        "ACTION MOUNT REGISTRY READY",
    ),
    (
        "request-bus",
        "interop/request-bus.f",
        "ACTION MOUNT REQUEST BUS READY",
    ),
    (
        "action-mount",
        "tui/applets/streams/rabbit-action-mount.f",
        "STREAMS RABBIT ACTION MOUNT READY",
    ),
    *FIXTURE_LOAD_STAGES,
    (
        "action-mount-fixture",
        FIXTURE_IMAGE_PATH,
        "STREAMS RABBIT ACTION MOUNT FIXTURE READY",
    ),
)


def _request_case_stages(
    name: str, start_word: str, results_word: str
) -> tuple[tuple[str, str, str], ...]:
    label = name.replace("-", " ").upper()
    return (
        (
            f"mount-{name}-start",
            start_word,
            f"STREAMS RABBIT ACTION MOUNT {label} START PASS",
        ),
        *(
            (
                f"mount-{name}-step-{index}",
                "_RBT-RAM-PHASE-REQUEST-STEP",
                f"STREAMS RABBIT ACTION MOUNT {label} STEP {index} PASS",
            )
            for index in range(1, 9)
        ),
        (
            f"mount-{name}-results",
            results_word,
            f"STREAMS RABBIT ACTION MOUNT {label} RESULTS PASS",
        ),
    )


ACTION_CONTRACT_STAGES = (
    (
        "mount-bound",
        "_RBT-RAM-PHASE-BOUND",
        "STREAMS RABBIT ACTION MOUNT BOUND PASS",
    ),
    *_request_case_stages(
        "accept",
        "_RBT-RAM-PHASE-ACCEPT-START",
        "_RBT-RAM-PHASE-ACCEPT-RESULTS",
    ),
    *_request_case_stages(
        "duplicate",
        "_RBT-RAM-PHASE-DUPLICATE-START",
        "_RBT-RAM-PHASE-DUPLICATE-RESULTS",
    ),
    *_request_case_stages(
        "conflict",
        "_RBT-RAM-PHASE-CONFLICT-START",
        "_RBT-RAM-PHASE-CONFLICT-RESULTS",
    ),
    *_request_case_stages(
        "stale",
        "_RBT-RAM-PHASE-STALE-START",
        "_RBT-RAM-PHASE-STALE-RESULTS",
    ),
    *_request_case_stages(
        "capacity",
        "_RBT-RAM-PHASE-CAPACITY-START",
        "_RBT-RAM-PHASE-CAPACITY-RESULTS",
    ),
    *_request_case_stages(
        "deny",
        "_RBT-RAM-PHASE-DENY-START",
        "_RBT-RAM-PHASE-DENY-RESULTS",
    ),
    *_request_case_stages(
        "missing-idem",
        "_RBT-RAM-PHASE-MISSING-IDEM-START",
        "_RBT-RAM-PHASE-MISSING-IDEM-RESULTS",
    ),
    *_request_case_stages(
        "missing-accept",
        "_RBT-RAM-PHASE-MISSING-ACCEPT-START",
        "_RBT-RAM-PHASE-MISSING-ACCEPT-RESULTS",
    ),
    *_request_case_stages(
        "noncanonical",
        "_RBT-RAM-PHASE-NONCANONICAL-START",
        "_RBT-RAM-PHASE-NONCANONICAL-RESULTS",
    ),
    *_request_case_stages(
        "postcommit-fail",
        "_RBT-RAM-PHASE-POSTCOMMIT-FAIL-START",
        "_RBT-RAM-PHASE-POSTCOMMIT-FAIL-RESULTS",
    ),
    *_request_case_stages(
        "postcommit-retry",
        "_RBT-RAM-PHASE-POSTCOMMIT-RETRY-START",
        "_RBT-RAM-PHASE-POSTCOMMIT-RETRY-RESULTS",
    ),
    (
        "mount-fini-borrowed",
        "_RBT-RAM-PHASE-FINI-BORROWED",
        "STREAMS RABBIT ACTION MOUNT BORROWED FINI PASS",
    ),
)


def _contract_stages() -> tuple[tuple[str, str, str], ...]:
    stages: list[tuple[str, str, str]] = []
    for stage in burrow.CONTRACT_STAGES:
        stages.append(stage)
        if stage[0] == "admission-proof":
            break
    stages.extend(ACTION_CONTRACT_STAGES)
    teardown_names = {
        "cleanup-begin",
        "cleanup-proof",
        "cleanup-retry",
        "cleanup-retry-proof",
        "fini",
    }
    stages.extend(
        stage for stage in burrow.CONTRACT_STAGES if stage[0] in teardown_names
    )
    stages.append(
        (
            "mount-fini",
            "_RBT-RAM-PHASE-FINI",
            "STREAMS RABBIT ACTION MOUNT FINI PASS",
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
    assert "PROVIDED akashic-streams-ramount" in mount
    for word in (
        "STREAMS-RABBIT-ACTION-MOUNT-INIT",
        "STREAMS-RABBIT-ACTION-MOUNT-BINDING-VALID?",
        "STREAMS-RABBIT-ACTION-MOUNT-VALID?",
        "STREAMS-RABBIT-ACTION-MOUNT-LAST@",
        "STREAMS-RABBIT-ACTION-MOUNT-ROUTE@",
        "STREAMS-RABBIT-ACTION-MOUNT-FINI",
    ):
        assert f": {word}" in mount
    for _, word, _ in ACTION_CONTRACT_STAGES:
        assert f": {word}" in fixture
    assert ": _RBT-RAM-PHASE-FINI" in fixture
    assert "CAP.KIND @ CAP-K-COMMAND <>" in mount
    assert "CAP.EFFECTS @ CAP-E-MUTATE <>" in mount
    assert "CAP.FLAGS @ CAP-F-IDEMPOTENT AND 0=" in mount
    assert "CFENTRY-F-REVIEW-COMMIT" in mount
    assert "STREAMS-RABBIT-BURROW-ACTIVE-BINDING@" in mount
    assert "CBR-ARGS-SEAL!" in mount
    assert "0 R@ CBR.EXPECT-REV !" in mount
    assert "CBR.INVOCATION-ID SHA3-256-END" in mount
    assert "IVJSON-ENCODE" in mount and "COMPARE IF" in mount
    assert "_SRAMH-PRESENT @ 0= IF 0 EXIT THEN" in mount
    assert '200 S" RESULT" _SRAMH-TYPED-RECEIPT' in mount
    assert '412 S" PRECONDITION FAIL" _SRAMH-TYPED-RECEIPT' in mount
    assert '409 S" CONFLICT" _SRAMH-MAPPED-BODYLESS' in mount
    assert '429 S" FLOW-LIMIT" _SRAMH-MAPPED-BODYLESS' in mount
    assert "RABBIT-SERVER-POLL" not in mount
    assert "RABBIT-SERVER-SUBSCRIPTIONS-SERVICE" not in mount
    assert fixture.index("_RBT-RAM-LEDGER-FIND ?DUP IF") < fixture.index(
        "1 _RBT-RAM-EXPECTED-CHECKS +!"
    )
    assert "_RBT-RAM-MOUNT SRAM.JSON-CAP !" in fixture


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
    profile_name = "streams-rabbit-action-mount-source"
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
            "tui/applets/streams/rabbit-action-mount.f",
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT BURROW ASSERT",
            "STREAMS RABBIT BURROW STACK",
            "STREAMS RABBIT ACTION MOUNT LOAD STACK FAIL",
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
        "\\ autoexec.f - source-loaded Streams Rabbit action mount contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT ACTION MOUNT LOAD STACK FAIL '
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
        '." STREAMS RABBIT ACTION MOUNT PASS " _RBT-CHECKS @ . CR TX-FLUSH\n'
    )

    profile_name, profile = _profile(harness, "".join(autoexec))
    image = Path("/tmp/akashic-streams-rabbit-action-mount-source.img")
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
            print(f"Action mount {label}: starting", flush=True)
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
            r"STREAMS RABBIT ACTION MOUNT PASS[ \t]+([0-9]+)", raw
        )
        ok = match is not None and not failures
        print(
            "Streams Rabbit action mount: "
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
    print(f"Action mount {label}: FAIL")
    print(
        f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
        f"stop={report.reason}"
    )
    for failure in failures:
        print(f"  {failure}")
    if len(raw) > 8000:
        print(raw[:4000])
        print("\n... action mount trace middle omitted ...\n")
    print(raw[-4000:])
    print(machine.screen_text())
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--action-mount", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT ACTION MOUNT STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
