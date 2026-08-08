#!/usr/bin/env python3
"""Qualify the persistent Streams Rabbit typed-subscription owner."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
REMOTE_SUB = (
    ROOT
    / "akashic"
    / "tui"
    / "applets"
    / "streams"
    / "rabbit-remote-sub.f"
)
FIXTURE = LOCAL_TESTING / "rabbit-remote-sub-test.f"
FIXTURE_IMAGE_PATH = "local_testing/rsub-test.f"

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

PASS_MARKER = "STREAMS RABBIT REMOTE SUBSCRIPTION PASS"
PHASE_MAX_STEPS = 120_000_000

ROUTER_STAGE_INDEX = next(
    index
    for index, stage in enumerate(burrow.LOAD_STAGES)
    if stage[0] == "router"
)
NETWORK_LOAD_STAGES = burrow.LOAD_STAGES[: ROUTER_STAGE_INDEX + 1]
LOAD_STAGES = (
    *NETWORK_LOAD_STAGES,
    ("guard", "concurrency/guard.f", "REMOTE SUBSCRIPTION GUARD READY"),
    ("value", "interop/value.f", "REMOTE SUBSCRIPTION VALUE READY"),
    ("schema", "interop/schema.f", "REMOTE SUBSCRIPTION SCHEMA READY"),
    ("json", "utils/json.f", "REMOTE SUBSCRIPTION JSON READY"),
    (
        "json-value",
        "interop/codecs/json-value.f",
        "REMOTE SUBSCRIPTION JSON VALUE READY",
    ),
    (
        "streams-connector",
        "tui/applets/streams/rabbit-connector.f",
        "REMOTE SUBSCRIPTION CONNECTOR READY",
    ),
    (
        "remote-resource",
        "tui/applets/streams/rabbit-remote.f",
        "REMOTE SUBSCRIPTION RESOURCE READY",
    ),
    (
        "remote-subscription",
        "tui/applets/streams/rabbit-remote-sub.f",
        "STREAMS RABBIT REMOTE SUBSCRIPTION READY",
    ),
    ("core-fixture", CORE_SUPPORT_PATH, "REMOTE SUBSCRIPTION CORE FIXTURE READY"),
    (
        "client-fixture",
        "local_testing/rabbit-client-test.f",
        "REMOTE SUBSCRIPTION CLIENT FIXTURE READY",
    ),
    (
        "client-flow-fixture",
        "local_testing/rabbit-client-flow.f",
        "REMOTE SUBSCRIPTION CLIENT FLOW FIXTURE READY",
    ),
    (
        "subscription-fixture",
        "local_testing/rabbit-sub-test.f",
        "REMOTE SUBSCRIPTION NEUTRAL FIXTURE READY",
    ),
    (
        "connector-fixture",
        "local_testing/rabbit-connector-test.f",
        "REMOTE SUBSCRIPTION CONNECTOR FIXTURE READY",
    ),
    (
        "resource-fixture",
        "local_testing/rabbit-remote-test.f",
        "REMOTE SUBSCRIPTION RESOURCE FIXTURE READY",
    ),
    (
        "remote-subscription-fixture",
        FIXTURE_IMAGE_PATH,
        "STREAMS RABBIT REMOTE SUBSCRIPTION FIXTURE READY",
    ),
)

CONTRACT_STAGES = (
    (
        "connector-dependency",
        "_RBT-RRSUB-PHASE-CONNECTOR-DEPENDENCY",
        "REMOTE SUBSCRIPTION CONNECTOR DEPENDENCY PASS",
    ),
    (
        "dependencies",
        "_RBT-RRSUB-PHASE-DEPENDENCIES",
        "REMOTE SUBSCRIPTION DEPENDENCIES PASS",
    ),
    ("init", "_RBT-RRSUB-PHASE-INIT", "REMOTE SUBSCRIPTION INIT PASS"),
    (
        "init-evidence",
        "_RBT-RRSUB-PHASE-INIT-EVIDENCE",
        "REMOTE SUBSCRIPTION INIT EVIDENCE PASS",
    ),
    (
        "init-stale-handle",
        "_RBT-RRSUB-PHASE-INIT-STALE-HANDLE",
        "REMOTE SUBSCRIPTION INIT STALE HANDLE PASS",
    ),
    (
        "init-geometry",
        "_RBT-RRSUB-PHASE-INIT-GEOMETRY",
        "REMOTE SUBSCRIPTION INIT GEOMETRY PASS",
    ),
    (
        "init-routing",
        "_RBT-RRSUB-PHASE-INIT-ROUTING",
        "REMOTE SUBSCRIPTION INIT ROUTING PASS",
    ),
    (
        "handshake",
        "_RBT-RRSUB-PHASE-HANDSHAKE",
        "REMOTE SUBSCRIPTION HANDSHAKE PASS",
    ),
    (
        "bind-alias",
        "_RBT-RRSUB-PHASE-BIND-ALIAS",
        "REMOTE SUBSCRIPTION BIND ALIAS PASS",
    ),
    (
        "bind-reject-start",
        "_RBT-RRSUB-PHASE-BIND-REJECT-START",
        "REMOTE SUBSCRIPTION BIND REJECT START PASS",
    ),
    (
        "bind-reject-result",
        "_RBT-RRSUB-PHASE-BIND-REJECT",
        "REMOTE SUBSCRIPTION BIND REJECT PASS",
    ),
    (
        "bind-reject-evidence",
        "_RBT-RRSUB-PHASE-BIND-REJECT-EVIDENCE",
        "REMOTE SUBSCRIPTION BIND REJECT EVIDENCE PASS",
    ),
    (
        "bind-reject-detail",
        "_RBT-RRSUB-PHASE-BIND-REJECT-DETAIL",
        "REMOTE SUBSCRIPTION BIND REJECT DETAIL PASS",
    ),
    (
        "bind-reject-resolve",
        "_RBT-RRSUB-PHASE-BIND-REJECT-RESOLVE",
        "REMOTE SUBSCRIPTION BIND REJECT RESOLVE PASS",
    ),
    (
        "bind-accept-start",
        "_RBT-RRSUB-PHASE-BIND-ACCEPT-START",
        "REMOTE SUBSCRIPTION BIND ACCEPT START PASS",
    ),
    (
        "bind-accept-result",
        "_RBT-RRSUB-PHASE-BIND-ACCEPT",
        "REMOTE SUBSCRIPTION BIND ACCEPT PASS",
    ),
    (
        "bind-accept-evidence",
        "_RBT-RRSUB-PHASE-BIND-ACCEPT-EVIDENCE",
        "REMOTE SUBSCRIPTION BIND ACCEPT EVIDENCE PASS",
    ),
    (
        "bind-accept-resolve",
        "_RBT-RRSUB-PHASE-BIND-ACCEPT-RESOLVE",
        "REMOTE SUBSCRIPTION BIND ACCEPT RESOLVE PASS",
    ),
    (
        "event-new",
        "_RBT-RRSUB-PHASE-EVENT-NEW",
        "REMOTE SUBSCRIPTION EVENT NEW PASS",
    ),
    (
        "event-new-ack",
        "_RBT-RRSUB-PHASE-EVENT-NEW-ACK",
        "REMOTE SUBSCRIPTION EVENT NEW ACK PASS",
    ),
    (
        "failed-commit",
        "_RBT-RRSUB-PHASE-FAILED-COMMIT",
        "REMOTE SUBSCRIPTION FAILED COMMIT PASS",
    ),
    (
        "event-duplicate",
        "_RBT-RRSUB-PHASE-EVENT-DUPLICATE",
        "REMOTE SUBSCRIPTION EVENT DUPLICATE PASS",
    ),
    (
        "event-duplicate-exact",
        "_RBT-RRSUB-PHASE-EVENT-DUPLICATE-EXACT",
        "REMOTE SUBSCRIPTION EVENT DUPLICATE EXACT PASS",
    ),
    (
        "event-duplicate-ack",
        "_RBT-RRSUB-PHASE-EVENT-DUPLICATE-ACK",
        "REMOTE SUBSCRIPTION EVENT DUPLICATE ACK PASS",
    ),
    (
        "rejections",
        "_RBT-RRSUB-PHASE-REJECTIONS",
        "REMOTE SUBSCRIPTION REJECTIONS PASS",
    ),
    (
        "validator-rejections",
        "_RBT-RRSUB-PHASE-REJECTIONS-VALIDATOR",
        "REMOTE SUBSCRIPTION VALIDATOR REJECTIONS PASS",
    ),
    (
        "validator-exceptions",
        "_RBT-RRSUB-PHASE-REJECTIONS-EXCEPTION",
        "REMOTE SUBSCRIPTION VALIDATOR EXCEPTIONS PASS",
    ),
    (
        "retry-publish",
        "_RBT-RRSUB-PHASE-RETRY-PUBLISH",
        "REMOTE SUBSCRIPTION RETRY PUBLISH PASS",
    ),
    (
        "retry-publish-apply",
        "_RBT-RRSUB-PHASE-RETRY-PUBLISH-APPLY",
        "REMOTE SUBSCRIPTION RETRY PUBLISH APPLY PASS",
    ),
    (
        "retry-discard",
        "_RBT-RRSUB-PHASE-RETRY-DISCARD",
        "REMOTE SUBSCRIPTION RETRY DISCARD PASS",
    ),
    (
        "retry-discard-apply",
        "_RBT-RRSUB-PHASE-RETRY-DISCARD-APPLY",
        "REMOTE SUBSCRIPTION RETRY DISCARD APPLY PASS",
    ),
    ("gap", "_RBT-RRSUB-PHASE-GAP", "REMOTE SUBSCRIPTION GAP PASS"),
    (
        "detach",
        "_RBT-RRSUB-PHASE-DETACH",
        "REMOTE SUBSCRIPTION DETACH PASS",
    ),
    (
        "detach-evidence",
        "_RBT-RRSUB-PHASE-DETACH-EVIDENCE",
        "REMOTE SUBSCRIPTION DETACH EVIDENCE PASS",
    ),
    (
        "rebind-attach",
        "_RBT-RRSUB-PHASE-REBIND-ATTACH",
        "REMOTE SUBSCRIPTION REBIND ATTACH PASS",
    ),
    (
        "rebind-handshake",
        "_RBT-RRSUB-PHASE-REBIND-HANDSHAKE",
        "REMOTE SUBSCRIPTION REBIND HANDSHAKE PASS",
    ),
    (
        "rebind-start",
        "_RBT-RRSUB-PHASE-REBIND-START",
        "REMOTE SUBSCRIPTION REBIND START PASS",
    ),
    (
        "rebind-result",
        "_RBT-RRSUB-PHASE-REBIND-RESULT",
        "REMOTE SUBSCRIPTION REBIND RESULT PASS",
    ),
    (
        "rebind-resolve",
        "_RBT-RRSUB-PHASE-REBIND-RESOLVE",
        "REMOTE SUBSCRIPTION REBIND RESOLVE PASS",
    ),
    (
        "replay",
        "_RBT-RRSUB-PHASE-REPLAY",
        "REMOTE SUBSCRIPTION REPLAY PASS",
    ),
    (
        "replay-ack",
        "_RBT-RRSUB-PHASE-REPLAY-ACK",
        "REMOTE SUBSCRIPTION REPLAY ACK PASS",
    ),
    (
        "equivocation",
        "_RBT-RRSUB-PHASE-EQUIVOCATION",
        "REMOTE SUBSCRIPTION EQUIVOCATION PASS",
    ),
    ("fini", "_RBT-RRSUB-PHASE-FINI", "REMOTE SUBSCRIPTION FINI PASS"),
    (
        "fini-owner",
        "_RBT-RRSUB-PHASE-FINI-OWNER",
        "REMOTE SUBSCRIPTION FINI OWNER PASS",
    ),
    (
        "fini-temp",
        "_RBT-RRSUB-PHASE-FINI-TEMP",
        "REMOTE SUBSCRIPTION FINI TEMP PASS",
    ),
    (
        "fini-dependencies",
        "_RBT-RRSUB-PHASE-FINI-DEPENDENCIES",
        "REMOTE SUBSCRIPTION FINI DEPENDENCIES PASS",
    ),
)


def _assert_static_contracts() -> None:
    remote_sub = REMOTE_SUB.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == burrow.PHASE_MAX_STEPS == 120_000_000
    assert NETWORK_LOAD_STAGES[-1][0] == "router"
    assert "PROVIDED akashic-streams-rrsub" in remote_sub
    assert "REQUIRE rabbit-remote.f" in remote_sub
    assert re.search(
        r"304\s+CONSTANT\s+STREAMS-RABBIT-REMOTE-SUB-SIZE", remote_sub
    )
    for word in (
        "STREAMS-RABBIT-REMOTE-SUB-INIT",
        "STREAMS-RABBIT-REMOTE-SUB-VALID?",
        "STREAMS-RABBIT-REMOTE-SUB-STATE@",
        "STREAMS-RABBIT-REMOTE-SUB-LAST@",
        "STREAMS-RABBIT-REMOTE-SUB-HANDLE@",
        "STREAMS-RABBIT-REMOTE-SUB-PENDING@",
        "STREAMS-RABBIT-REMOTE-SUB-CURSOR@",
        "STREAMS-RABBIT-REMOTE-SUB-LAST-EVENT@",
        "STREAMS-RABBIT-REMOTE-SUB-BIND",
        "STREAMS-RABBIT-REMOTE-SUB-REBIND",
        "STREAMS-RABBIT-REMOTE-SUB-BIND-RESULT@",
        "STREAMS-RABBIT-REMOTE-SUB-BIND-REQUIRED@",
        "STREAMS-RABBIT-REMOTE-SUB-BIND-RESOLVE",
        "STREAMS-RABBIT-REMOTE-SUB-CALLBACK",
        "STREAMS-RABBIT-REMOTE-SUB-CONSUME",
        "STREAMS-RABBIT-REMOTE-SUB-EVENT-RETRY",
        "STREAMS-RABBIT-REMOTE-SUB-RECONCILE",
        "STREAMS-RABBIT-REMOTE-SUB-RETAINED-SPAN-OVERLAP?",
        "STREAMS-RABBIT-REMOTE-SUB-FINI",
    ):
        assert f": {word}" in remote_sub
    assert "STREAMS-RABBIT-CONNECTOR-POLL" not in remote_sub
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-STAGE-JSON-CALLBACK" in remote_sub
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-STAGED-CALLBACK@" in remote_sub
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-STAGE-MATCH?" in remote_sub
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-PUBLISH-STAGED" in remote_sub
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-DISCARD-STAGED" in remote_sub
    assert "STREAMS-RABBIT-CONNECTOR-SUBSCRIPTION-SNAPSHOT@" in remote_sub
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-BUILDER-OVERLAP?" in remote_sub
    assert "SRRS.EVENT-VALIDATOR-XT" in remote_sub
    assert "SRRS.EVENT-VALIDATOR-CONTEXT" in remote_sub
    assert "SRRS.EVENT-APPROVED" in remote_sub
    assert "STREAMS-RABBIT-REMOTE-SUB-DETAIL-VALIDATOR" in remote_sub
    assert (
        "STREAMS-RABBIT-CONNECTOR-SUBSCRIPTION-LAST-OBSERVED-EVENT-SEQ@"
        in remote_sub
    )
    consume = remote_sub.split(": _SRRS-CONSUME\n", 1)[1].split(
        ": STREAMS-RABBIT-REMOTE-SUB-CONSUME", 1
    )[0]
    assert consume.index("_SRRSN-MATCH?") < consume.index("_SRRS-WITH-BUSY")
    callback_stage = remote_sub.split(": _SRRSC-STAGE", 1)[1].split(
        ": _SRRSC-INNER", 1
    )[0]
    assert callback_stage.index("_SRRSC-VALIDATE-STAGED") < callback_stage.index(
        "SRRS.EVENT-ACTION !"
    )
    bind_geometry = remote_sub.split(": _SRRS-BUILDER-DISJOINT?", 1)[1].split(
        ": _SRRSB-CONNECTOR-BIND", 1
    )[0]
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-BUILDER-OVERLAP?" in bind_geometry
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-SIZE" not in bind_geometry
    assert "['] _RBT-RRSUB-EVENT-VALIDATOR 0xE17D" in fixture
    for _, word, _ in CONTRACT_STAGES:
        assert f": {word}" in fixture
    assert "128 0 ?DO" in fixture
    assert "64 << 20" in Path(__file__).read_text(encoding="utf-8")
    assert "num_cores=1" in Path(__file__).read_text(encoding="utf-8")


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
    profile_name = "streams-rabbit-remote-subscription-source"
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
            "tui/applets/streams/rabbit-remote-sub.f",
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT REMOTE SUBSCRIPTION LOAD STACK FAIL",
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
        "\\ autoexec.f - source-loaded Streams Rabbit remote subscription\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT REMOTE SUBSCRIPTION LOAD STACK '
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
        '." STREAMS RABBIT REMOTE SUBSCRIPTION PASS " _RBT-CHECKS @ . '
        "CR TX-FLUSH\n"
    )

    profile_name, profile = _profile(harness, "".join(autoexec))
    image = Path("/tmp/akashic-streams-rabbit-remote-subscription-source.img")
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
            print(f"Remote subscription {label}: starting", flush=True)
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
            r"STREAMS RABBIT REMOTE SUBSCRIPTION PASS[ \t]+([0-9]+)", raw
        )
        ok = match is not None and not failures
        print(
            "Streams Rabbit remote subscription: "
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
    mode.add_argument("--remote-subscription", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT REMOTE SUBSCRIPTION STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
