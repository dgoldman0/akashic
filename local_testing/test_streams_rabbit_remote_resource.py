#!/usr/bin/env python3
"""Qualify the Streams Rabbit typed remote-resource owner."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
REMOTE = (
    ROOT
    / "akashic"
    / "tui"
    / "applets"
    / "streams"
    / "rabbit-remote.f"
)
FIXTURE = LOCAL_TESTING / "rabbit-remote-test.f"

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
)

PASS_MARKER = "STREAMS RABBIT REMOTE RESOURCE PASS"
PHASE_MAX_STEPS = 120_000_000

ROUTER_STAGE_INDEX = next(
    index
    for index, stage in enumerate(burrow.LOAD_STAGES)
    if stage[0] == "router"
)
NETWORK_LOAD_STAGES = burrow.LOAD_STAGES[: ROUTER_STAGE_INDEX + 1]
LOAD_STAGES = (
    *NETWORK_LOAD_STAGES,
    ("guard", "concurrency/guard.f", "REMOTE RESOURCE GUARD READY"),
    ("value", "interop/value.f", "REMOTE RESOURCE VALUE READY"),
    ("schema", "interop/schema.f", "REMOTE RESOURCE SCHEMA READY"),
    ("json", "utils/json.f", "REMOTE RESOURCE JSON READY"),
    (
        "json-value",
        "interop/codecs/json-value.f",
        "REMOTE RESOURCE JSON VALUE READY",
    ),
    (
        "streams-connector",
        "tui/applets/streams/rabbit-connector.f",
        "REMOTE RESOURCE CONNECTOR READY",
    ),
    (
        "remote-resource",
        "tui/applets/streams/rabbit-remote.f",
        "STREAMS RABBIT REMOTE RESOURCE READY",
    ),
    ("core-fixture", CORE_SUPPORT_PATH, "REMOTE RESOURCE CORE FIXTURE READY"),
    (
        "client-fixture",
        "local_testing/rabbit-client-test.f",
        "REMOTE RESOURCE CLIENT FIXTURE READY",
    ),
    (
        "client-flow-fixture",
        "local_testing/rabbit-client-flow.f",
        "REMOTE RESOURCE CLIENT FLOW FIXTURE READY",
    ),
    (
        "subscription-fixture",
        "local_testing/rabbit-sub-test.f",
        "REMOTE RESOURCE SUBSCRIPTION FIXTURE READY",
    ),
    (
        "connector-fixture",
        "local_testing/rabbit-connector-test.f",
        "REMOTE RESOURCE CONNECTOR FIXTURE READY",
    ),
    (
        "remote-resource-fixture",
        "local_testing/rabbit-remote-test.f",
        "STREAMS RABBIT REMOTE RESOURCE FIXTURE READY",
    ),
)

CONTRACT_STAGES = (
    (
        "init",
        "_RBT-RRES-PHASE-INIT",
        "STREAMS RABBIT REMOTE RESOURCE INIT PASS",
    ),
    (
        "handshake",
        "_RBT-RRES-PHASE-HANDSHAKE",
        "STREAMS RABBIT REMOTE RESOURCE HANDSHAKE PASS",
    ),
    (
        "first-publish",
        "_RBT-RRES-PHASE-FIRST-PUBLISH",
        "STREAMS RABBIT REMOTE RESOURCE FIRST PUBLISH PASS",
    ),
    (
        "wrong-view",
        "_RBT-RRES-PHASE-WRONG-VIEW",
        "STREAMS RABBIT REMOTE RESOURCE WRONG VIEW PASS",
    ),
    (
        "malformed",
        "_RBT-RRES-PHASE-MALFORMED",
        "STREAMS RABBIT REMOTE RESOURCE MALFORMED PASS",
    ),
    (
        "schema",
        "_RBT-RRES-PHASE-SCHEMA",
        "STREAMS RABBIT REMOTE RESOURCE SCHEMA PASS",
    ),
    (
        "validator",
        "_RBT-RRES-PHASE-VALIDATOR",
        "STREAMS RABBIT REMOTE RESOURCE VALIDATOR PASS",
    ),
    (
        "not-found",
        "_RBT-RRES-PHASE-NOT-FOUND",
        "STREAMS RABBIT REMOTE RESOURCE NOT FOUND PASS",
    ),
    (
        "cache-stage",
        "_RBT-RRES-PHASE-CACHE-STAGE",
        "STREAMS RABBIT REMOTE RESOURCE CACHE STAGE PASS",
    ),
    (
        "stale-fetch",
        "_RBT-RRES-PHASE-STALE-FETCH",
        "STREAMS RABBIT REMOTE RESOURCE STALE FETCH PASS",
    ),
    (
        "replace",
        "_RBT-RRES-PHASE-REPLACE",
        "STREAMS RABBIT REMOTE RESOURCE REPLACE PASS",
    ),
    (
        "fini",
        "_RBT-RRES-PHASE-FINI",
        "STREAMS RABBIT REMOTE RESOURCE FINI PASS",
    ),
)


def _assert_static_contracts() -> None:
    remote = REMOTE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")

    assert PHASE_MAX_STEPS == burrow.PHASE_MAX_STEPS == 120_000_000
    assert NETWORK_LOAD_STAGES[-1][0] == "router"
    assert "PROVIDED akashic-streams-rres" in remote
    for word in (
        "STREAMS-RABBIT-REMOTE-RESOURCE-INIT",
        "STREAMS-RABBIT-REMOTE-RESOURCE-VALID?",
        "STREAMS-RABBIT-REMOTE-RESOURCE-FETCH",
        "STREAMS-RABBIT-REMOTE-RESOURCE-POLL-CALLBACK",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CONSUME",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE@",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-CALLBACK@",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-STAGE-JSON-CALLBACK",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-PUBLISH-STAGED",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-DISCARD-STAGED",
        "STREAMS-RABBIT-REMOTE-RESOURCE-RETAINED-SPAN-OVERLAP?",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CONNECTOR-MATCH?",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CLEANUP",
        "STREAMS-RABBIT-REMOTE-RESOURCE-ABANDON",
        "STREAMS-RABBIT-REMOTE-RESOURCE-FINI",
    ):
        assert f": {word}" in remote
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-ADOPT" not in remote
    assert "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE-VALIDATE" not in remote
    assert "STREAMS-RABBIT-CONNECTOR-POLL" not in remote
    assert "STREAMS-RABBIT-CONNECTOR-OP-RESULT@" in remote
    assert "STREAMS-RABBIT-CONNECTOR-OP-RELEASE" in remote
    consume = remote.split(": _SRRES-CONSUME", 1)[1].split(
        ": STREAMS-RABBIT-REMOTE-RESOURCE-CONSUME", 1
    )[0]
    assert consume.index("_SRRESC-BUSY @") < consume.index("_SRRESC-O !")
    assert consume.index("_SRRESC-MARK-STALE") < consume.index(
        "_SRRESC-ACCESS"
    )
    assert consume.index("_SRRESC-RELEASE") < consume.index("_SRRESC-FINISH")
    assert "IVJSON-DECODE-AS" in remote
    assert "RABBIT-CLIENT-" not in remote
    assert "RCLIENT." not in remote
    for _, word, _ in CONTRACT_STAGES:
        assert f": {word}" in fixture
    assert "128 0 ?DO" in fixture


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
        for path in (*SUPPORT_FIXTURES, FIXTURE)
    )
    return (
        (
            CORE_SUPPORT_PATH,
            harness._minify_forth(core_support).encode("utf-8"),
        ),
        *support,
    )


def _profile(harness, autoexec: str):
    profile_name = "streams-rabbit-remote-resource-source"
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
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT REMOTE RESOURCE LOAD STACK FAIL",
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
        "\\ autoexec.f - source-loaded Streams Rabbit remote resource\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT REMOTE RESOURCE LOAD STACK '
                    f'FAIL {stage_name}" CR TX-FLUSH DEPTH 0 ?DO DROP LOOP THEN\n'
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
        '." STREAMS RABBIT REMOTE RESOURCE PASS " _RBT-CHECKS @ . '
        "CR TX-FLUSH\n"
    )

    profile_name, profile = _profile(harness, "".join(autoexec))
    image = Path("/tmp/akashic-streams-rabbit-remote-resource-source.img")
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
            print(f"Remote resource {label}: starting", flush=True)
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
            r"STREAMS RABBIT REMOTE RESOURCE PASS[ \t]+([0-9]+)", raw
        )
        ok = match is not None and not failures
        print(
            "Streams Rabbit remote resource: "
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
    mode.add_argument("--remote-resource", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT REMOTE RESOURCE STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
