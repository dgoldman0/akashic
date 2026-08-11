#!/usr/bin/env python3
"""Qualify the persistent Streams Rabbit typed-action attempt owner."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
REMOTE_ACTION = (
    ROOT
    / "akashic"
    / "tui"
    / "applets"
    / "streams"
    / "rabbit-remote-action.f"
)
FIXTURE = LOCAL_TESTING / "rabbit-remote-action-test.f"
FIXTURE_IMAGE_PATH = "local_testing/ract-test.f"

sys.path.insert(0, str(LOCAL_TESTING))
import test_streams_rabbit_burrow as burrow


CORE_FIXTURE = LOCAL_TESTING / "rabbit-core-test.f"
CORE_SUPPORT_PATH = "local_testing/rres-core.f"
CORE_SUPPORT_LINES = 284
SUPPORT_FIXTURES = (
    LOCAL_TESTING / "rabbit-client-test.f",
    LOCAL_TESTING / "rabbit-client-flow.f",
    LOCAL_TESTING / "rabbit-sub-test.f",
    LOCAL_TESTING / "rabbit-connector-test.f",
    LOCAL_TESTING / "rabbit-remote-test.f",
)

PASS_MARKER = "STREAMS RABBIT REMOTE ACTION PASS"
PHASE_MAX_STEPS = 120_000_000

ROUTER_STAGE_INDEX = next(
    index
    for index, stage in enumerate(burrow.LOAD_STAGES)
    if stage[0] == "router"
)
NETWORK_LOAD_STAGES = burrow.LOAD_STAGES[: ROUTER_STAGE_INDEX + 1]
LOAD_STAGES = (
    *NETWORK_LOAD_STAGES,
    ("guard", "concurrency/guard.f", "REMOTE ACTION GUARD READY"),
    ("value", "interop/value.f", "REMOTE ACTION VALUE READY"),
    ("schema", "interop/schema.f", "REMOTE ACTION SCHEMA READY"),
    ("json", "utils/json.f", "REMOTE ACTION JSON READY"),
    (
        "json-value",
        "interop/codecs/json-value.f",
        "REMOTE ACTION JSON VALUE READY",
    ),
    (
        "streams-connector",
        "tui/applets/streams/rabbit-connector.f",
        "REMOTE ACTION CONNECTOR READY",
    ),
    (
        "remote-resource",
        "tui/applets/streams/rabbit-remote.f",
        "REMOTE ACTION RESOURCE READY",
    ),
    (
        "remote-action",
        "tui/applets/streams/rabbit-remote-action.f",
        "STREAMS RABBIT REMOTE ACTION READY",
    ),
    ("core-fixture", CORE_SUPPORT_PATH, "REMOTE ACTION CORE FIXTURE READY"),
    (
        "client-fixture",
        "local_testing/rabbit-client-test.f",
        "REMOTE ACTION CLIENT FIXTURE READY",
    ),
    (
        "client-flow-fixture",
        "local_testing/rabbit-client-flow.f",
        "REMOTE ACTION CLIENT FLOW FIXTURE READY",
    ),
    (
        "subscription-fixture",
        "local_testing/rabbit-sub-test.f",
        "REMOTE ACTION NEUTRAL FIXTURE READY",
    ),
    (
        "connector-fixture",
        "local_testing/rabbit-connector-test.f",
        "REMOTE ACTION CONNECTOR FIXTURE READY",
    ),
    (
        "resource-fixture",
        "local_testing/rabbit-remote-test.f",
        "REMOTE ACTION RESOURCE FIXTURE READY",
    ),
    (
        "remote-action-fixture",
        FIXTURE_IMAGE_PATH,
        "STREAMS RABBIT REMOTE ACTION FIXTURE READY",
    ),
)

CONTRACT_STAGES = (
    (
        "dependencies",
        "_RBT-RRA-PHASE-DEPENDENCIES",
        "REMOTE ACTION DEPENDENCIES PASS",
    ),
    ("init", "_RBT-RRA-PHASE-INIT", "REMOTE ACTION INIT PASS"),
    (
        "handshake",
        "_RBT-RRA-PHASE-HANDSHAKE",
        "REMOTE ACTION HANDSHAKE PASS",
    ),
    ("routing", "_RBT-RRA-PHASE-ROUTING", "REMOTE ACTION ROUTING PASS"),
    (
        "accepted-send",
        "_RBT-RRA-PHASE-ACCEPT-SEND",
        "REMOTE ACTION ACCEPTED SEND PASS",
    ),
    (
        "fallback-failures",
        "_RBT-RRA-PHASE-FALLBACK-FAILURES",
        "REMOTE ACTION FALLBACK FAILURES PASS",
    ),
    (
        "accepted-result",
        "_RBT-RRA-PHASE-ACCEPT-RESULT",
        "REMOTE ACTION ACCEPTED RESULT PASS",
    ),
    (
        "retryable-send",
        "_RBT-RRA-PHASE-RETRYABLE-SEND",
        "REMOTE ACTION RETRYABLE SEND PASS",
    ),
    (
        "retryable-result",
        "_RBT-RRA-PHASE-RETRYABLE-RESULT",
        "REMOTE ACTION RETRYABLE RESULT PASS",
    ),
    (
        "retryable-retry",
        "_RBT-RRA-PHASE-RETRYABLE-RETRY",
        "REMOTE ACTION RETRYABLE RETRY PASS",
    ),
    (
        "retryable-accept",
        "_RBT-RRA-PHASE-RETRYABLE-ACCEPT",
        "REMOTE ACTION RETRYABLE ACCEPT PASS",
    ),
    (
        "no-effect",
        "_RBT-RRA-PHASE-NO-EFFECT",
        "REMOTE ACTION NO EFFECT PASS",
    ),
    (
        "classifier-throw",
        "_RBT-RRA-PHASE-CLASSIFIER-THROW",
        "REMOTE ACTION CLASSIFIER THROW PASS",
    ),
    (
        "classifier-stack",
        "_RBT-RRA-PHASE-CLASSIFIER-STACK",
        "REMOTE ACTION CLASSIFIER STACK PASS",
    ),
    (
        "strict-profile",
        "_RBT-RRA-PHASE-STRICT-PROFILE",
        "REMOTE ACTION STRICT PROFILE PASS",
    ),
    (
        "result-mismatch",
        "_RBT-RRA-PHASE-RESULT-MISMATCH",
        "REMOTE ACTION RESULT MISMATCH PASS",
    ),
    (
        "disconnect-send",
        "_RBT-RRA-PHASE-DISCONNECT-SEND",
        "REMOTE ACTION DISCONNECT SEND PASS",
    ),
    (
        "disconnect",
        "_RBT-RRA-PHASE-DISCONNECT",
        "REMOTE ACTION DISCONNECT PASS",
    ),
    (
        "reattach",
        "_RBT-RRA-PHASE-REATTACH",
        "REMOTE ACTION REATTACH PASS",
    ),
    (
        "reattach-result",
        "_RBT-RRA-PHASE-REATTACH-RESULT",
        "REMOTE ACTION REATTACH RESULT PASS",
    ),
    (
        "abandon-fini",
        "_RBT-RRA-PHASE-ABANDON-FINI",
        "REMOTE ACTION ABANDON FINI PASS",
    ),
)


def _assert_static_contracts() -> None:
    remote_action = REMOTE_ACTION.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    driver = Path(__file__).read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == burrow.PHASE_MAX_STEPS == 120_000_000
    assert NETWORK_LOAD_STAGES[-1][0] == "router"
    assert "PROVIDED akashic-streams-rract" in remote_action
    assert "REQUIRE rabbit-connector.f" in remote_action
    assert re.search(
        r"480\s+CONSTANT\s+STREAMS-RABBIT-REMOTE-ACTION-SIZE",
        remote_action,
    )
    for word in (
        "STREAMS-RABBIT-REMOTE-ACTION-INIT",
        "STREAMS-RABBIT-REMOTE-ACTION-PROFILE!",
        "STREAMS-RABBIT-REMOTE-ACTION-PREPARE",
        "STREAMS-RABBIT-REMOTE-ACTION-VALID?",
        "STREAMS-RABBIT-REMOTE-ACTION-STATE@",
        "STREAMS-RABBIT-REMOTE-ACTION-LAST@",
        "STREAMS-RABBIT-REMOTE-ACTION-PENDING@",
        "STREAMS-RABBIT-REMOTE-ACTION-HANDLE@",
        "STREAMS-RABBIT-REMOTE-ACTION-ACTION$",
        "STREAMS-RABBIT-REMOTE-ACTION-IDEM$",
        "STREAMS-RABBIT-REMOTE-ACTION-TXN$",
        "STREAMS-RABBIT-REMOTE-ACTION-RECEIPT@",
        "STREAMS-RABBIT-REMOTE-ACTION-CALLBACK@",
        "STREAMS-RABBIT-REMOTE-ACTION-SEND-COUNT@",
        "STREAMS-RABBIT-REMOTE-ACTION-SEND",
        "STREAMS-RABBIT-REMOTE-ACTION-RETRY",
        "STREAMS-RABBIT-REMOTE-ACTION-POLL-CALLBACK",
        "STREAMS-RABBIT-REMOTE-ACTION-CONSUME",
        "STREAMS-RABBIT-REMOTE-ACTION-RECONCILE",
        "STREAMS-RABBIT-REMOTE-ACTION-CLEANUP",
        "STREAMS-RABBIT-REMOTE-ACTION-ABANDON",
        "STREAMS-RABBIT-REMOTE-ACTION-FINI",
    ):
        assert f": {word}" in remote_action
    for label in (
        'S" RESULT"',
        'S" PRECONDITION FAIL"',
        'S" FORBIDDEN"',
        'S" CONFLICT"',
        'S" FLOW-LIMIT"',
        'S" BUSY"',
    ):
        assert label in remote_action
    assert "STREAMS-RABBIT-CONNECTOR-POLL" not in remote_action
    assert "RMSGB-ACCEPT-VIEW!" in remote_action
    assert "RMSGB-IDEM!" in remote_action
    assert "_SRRASN-FRESH?" in remote_action
    assert "_SRRA-BUILDER-OVERLAP?" in remote_action
    assert "_SRRAN-MATCH? 0= IF" in remote_action
    assert "_SRRAC-MATCH? IF _SRRAC-EXACT ELSE _SRRAC-FALLBACK" in remote_action
    assert "_SRRAN-COPY-RESULT" in remote_action
    assert "SRRA.RECEIPT-CAP @ U>" in remote_action
    assert "_RBT-RRA-FALLBACK-MODE" in fixture
    assert "_RBT-RRA-INJECT-CALLBACK-CODE" in fixture
    for _, word, _ in CONTRACT_STAGES:
        assert f": {word}" in fixture
    assert "128 0 ?DO" in fixture
    assert "64 << 20" in driver
    assert "num_cores=1" in driver


def _initial_files(harness) -> tuple[tuple[str, bytes], ...]:
    core_lines = CORE_FIXTURE.read_text(encoding="utf-8").splitlines(
        keepends=True
    )
    assert core_lines[CORE_SUPPORT_LINES - 1].rstrip().endswith(";")
    core_support = "".join(core_lines[:CORE_SUPPORT_LINES])
    support = tuple(
        (
            str(path.relative_to(ROOT)),
            harness._minify_forth(path.read_text(encoding="utf-8")).encode(
                "utf-8"
            ),
        )
        for path in SUPPORT_FIXTURES
    )
    return (
        (
            CORE_SUPPORT_PATH,
            harness._minify_forth(core_support).encode("utf-8"),
        ),
        *support,
        (
            FIXTURE_IMAGE_PATH,
            harness._minify_forth(FIXTURE.read_text(encoding="utf-8")).encode(
                "utf-8"
            ),
        ),
    )


def _profile(harness, autoexec: str):
    profile_name = "streams-rabbit-remote-action-source"
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
            "concurrency/guard.f",
            "interop/value.f",
            "interop/schema.f",
            "utils/json.f",
            "interop/codecs/json-value.f",
            "tui/applets/streams/rabbit-connector.f",
            "tui/applets/streams/rabbit-remote.f",
            "tui/applets/streams/rabbit-remote-action.f",
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT REMOTE ACTION LOAD STACK FAIL",
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
        "\\ autoexec.f - source-loaded Streams Rabbit remote action\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT REMOTE ACTION LOAD STACK '
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
        '." STREAMS RABBIT REMOTE ACTION PASS " _RBT-CHECKS @ . '
        "CR TX-FLUSH\n"
    )

    profile_name, profile = _profile(harness, "".join(autoexec))
    image = Path("/tmp/akashic-streams-rabbit-remote-action-source.img")
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
            print(f"Remote action {label}: starting", flush=True)
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
                return burrow._report_failure(
                    label, report, raw, failures, machine
                )

        machine.clear_output()
        if all_stages:
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
            r"STREAMS RABBIT REMOTE ACTION PASS[ \t]+([0-9]+)", raw
        )
        ok = match is not None and not failures
        print(
            "Streams Rabbit remote action: "
            f"{'PASS' if ok else 'FAIL'}"
            f"{f' ({match.group(1)} checks)' if match else ''}"
        )
        for label, stage_report in reports:
            print(
                f"  {label}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        if not ok:
            return burrow._report_failure(
                "final", report, raw, failures, machine
            )
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--remote-action", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT REMOTE ACTION STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
