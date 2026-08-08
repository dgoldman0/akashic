#!/usr/bin/env python3
"""Qualify the generic two-client Rabbit Streams Landing 3 vertical slice."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
STREAMS = ROOT / "akashic" / "tui" / "applets" / "streams"

BURROW = STREAMS / "rabbit-burrow.f"
FACET_MOUNT = STREAMS / "rabbit-facet-mount.f"
ACTION_MOUNT = STREAMS / "rabbit-action-mount.f"
CONNECTOR = STREAMS / "rabbit-connector.f"
REMOTE_RESOURCE = STREAMS / "rabbit-remote.f"
REMOTE_SUB = STREAMS / "rabbit-remote-sub.f"
REMOTE_ACTION = STREAMS / "rabbit-remote-action.f"
MUX_FIXTURE = LOCAL_TESTING / "rabbit-l3-mux-test.f"
MUX_FIXTURE_IMAGE_PATH = "local_testing/rabbit-l3-mux-test.f"
FIXTURE = LOCAL_TESTING / "rabbit-landing3-test.f"
FIXTURE_IMAGE_PATH = "local_testing/rabbit-landing3-test.f"

sys.path.insert(0, str(LOCAL_TESTING))
import test_streams_rabbit_burrow as burrow


PASS_MARKER = "STREAMS RABBIT LANDING 3 PASS"
PHASE_MAX_STEPS = 120_000_000
NORMAL_STEP_COUNT = 16
# Action completion and subscription fanout are independent Rabbit flows.  Give
# the fair two-peer host a separate bounded delivery window before comparing the
# resource caches with the committed world.
FANOUT_STEP_COUNT = NORMAL_STEP_COUNT
CREDIT_STEP_COUNT = 4
LOSS_UPLINK_STEP_COUNT = 12
LOSS_HOST_STEP_COUNT = 12
LOSS_A_STEP_COUNT = 12
HOST_FINI_STEP_COUNT = 8

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
        "LANDING 3 CAPABILITY FACET READY",
    ),
    (
        "burrow",
        "tui/applets/streams/rabbit-burrow.f",
        "LANDING 3 BURROW READY",
    ),
    (
        "json-value",
        "interop/codecs/json-value.f",
        "LANDING 3 JSON VALUE READY",
    ),
    ("registry", "runtime/registry.f", "LANDING 3 REGISTRY READY"),
    (
        "request-bus",
        "interop/request-bus.f",
        "LANDING 3 REQUEST BUS READY",
    ),
    (
        "facet-mount",
        "tui/applets/streams/rabbit-facet-mount.f",
        "LANDING 3 FACET MOUNT READY",
    ),
    (
        "action-mount",
        "tui/applets/streams/rabbit-action-mount.f",
        "LANDING 3 ACTION MOUNT READY",
    ),
    (
        "streams-connector",
        "tui/applets/streams/rabbit-connector.f",
        "LANDING 3 CONNECTOR READY",
    ),
    (
        "remote-resource",
        "tui/applets/streams/rabbit-remote.f",
        "LANDING 3 REMOTE RESOURCE READY",
    ),
    (
        "remote-subscription",
        "tui/applets/streams/rabbit-remote-sub.f",
        "LANDING 3 REMOTE SUBSCRIPTION READY",
    ),
    (
        "remote-action",
        "tui/applets/streams/rabbit-remote-action.f",
        "LANDING 3 REMOTE ACTION READY",
    ),
    *FIXTURE_LOAD_STAGES,
    (
        "landing3-mux-fixture",
        MUX_FIXTURE_IMAGE_PATH,
        "STREAMS RABBIT LANDING 3 MUX FIXTURE READY",
    ),
    (
        "landing3-fixture",
        FIXTURE_IMAGE_PATH,
        "STREAMS RABBIT LANDING 3 FIXTURE READY",
    ),
)


def _phase(name: str, word: str) -> tuple[str, str, str]:
    label = name.replace("-", " ").upper()
    return name, word, f"STREAMS RABBIT LANDING 3 {label} PASS"


def _repeat_phases(
    name: str, word: str, count: int
) -> tuple[tuple[str, str, str], ...]:
    label = name.replace("-", " ").upper()
    return tuple(
        (
            f"{name}-step-{index}",
            word,
            f"STREAMS RABBIT LANDING 3 {label} STEP {index} PASS",
        )
        for index in range(1, count + 1)
    )


FAIR_RESULTS_INDEX = next(
    index
    for index, stage in enumerate(burrow.CONTRACT_STAGES)
    if stage[0] == "fair-results"
)
BURROW_PREFIX_STAGES = burrow.CONTRACT_STAGES[: FAIR_RESULTS_INDEX + 1]

LANDING3_STAGES = (
    _phase("client-a", "_RBT-L3-PHASE-CLIENT-A"),
    _phase("client-b", "_RBT-L3-PHASE-CLIENT-B"),
    _phase("clients", "_RBT-L3-PHASE-CLIENTS"),
    _phase("fetch-start", "_RBT-L3-PHASE-FETCH-START"),
    *_repeat_phases("fetch", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("fetch-results", "_RBT-L3-PHASE-FETCH-RESULTS"),
    _phase("bind-start", "_RBT-L3-PHASE-BIND-START"),
    *_repeat_phases("bind", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("bind-a-result", "_RBT-L3-PHASE-BIND-A-RESULT"),
    _phase("bind-b-result", "_RBT-L3-PHASE-BIND-B-RESULT"),
    _phase("bind-results", "_RBT-L3-PHASE-BIND-RESULTS"),
    *_repeat_phases(
        "bind-credit", "_RBT-L3-PHASE-STEP", CREDIT_STEP_COUNT
    ),
    _phase("loss-start", "_RBT-L3-PHASE-LOSS-START"),
    *_repeat_phases(
        "loss-uplink", "_RBT-L3-PHASE-LOSS-UPLINK", LOSS_UPLINK_STEP_COUNT
    ),
    *_repeat_phases(
        "loss-host", "_RBT-L3-PHASE-HOST-ONLY", LOSS_HOST_STEP_COUNT
    ),
    _phase("loss-proof", "_RBT-L3-PHASE-LOSS-PROOF"),
    *_repeat_phases("loss-a", "_RBT-L3-PHASE-A-ONLY", LOSS_A_STEP_COUNT),
    _phase("loss-a-result", "_RBT-L3-PHASE-LOSS-A-RESULT"),
    _phase("rebuild-b-detach", "_RBT-L3-PHASE-REBUILD-B-DETACH"),
    _phase("rebuild-b-client", "_RBT-L3-PHASE-REBUILD-B-CLIENT"),
    _phase("rebuild-b-server", "_RBT-L3-PHASE-REBUILD-B-SERVER"),
    _phase("rebuild-b", "_RBT-L3-PHASE-REBUILD-B"),
    _phase("hello-b-start", "_RBT-L3-PHASE-HELLO-B-START"),
    *_repeat_phases("hello-b", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("hello-b-result", "_RBT-L3-PHASE-HELLO-B-RESULT"),
    _phase("retry-start", "_RBT-L3-PHASE-RETRY-START"),
    *_repeat_phases("retry", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("retry-result", "_RBT-L3-PHASE-RETRY-RESULT"),
    _phase("rebind-b-start", "_RBT-L3-PHASE-REBIND-B-START"),
    *_repeat_phases("rebind-b", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("rebind-b-result", "_RBT-L3-PHASE-REBIND-B-RESULT"),
    *_repeat_phases("replay-11", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("replay-11-result", "_RBT-L3-PHASE-REPLAY11-RESULT"),
    _phase("stale-start", "_RBT-L3-PHASE-STALE-START"),
    *_repeat_phases("stale", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("stale-result", "_RBT-L3-PHASE-STALE-RESULT"),
    _phase("conflict-start", "_RBT-L3-PHASE-CONFLICT-START"),
    *_repeat_phases("conflict", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("conflict-result", "_RBT-L3-PHASE-CONFLICT-RESULT"),
    _phase("accept-2-start", "_RBT-L3-PHASE-ACCEPT2-START"),
    *_repeat_phases("accept-2", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("accept-2-result", "_RBT-L3-PHASE-ACCEPT2-RESULT"),
    *_repeat_phases("accept-2-fanout", "_RBT-L3-PHASE-STEP", FANOUT_STEP_COUNT),
    _phase(
        "accept-2-fanout-result", "_RBT-L3-PHASE-ACCEPT2-FANOUT-RESULT"
    ),
    _phase("detach-2-b", "_RBT-L3-PHASE-DETACH2-B"),
    _phase("rebuild-2-b-client", "_RBT-L3-PHASE-REBUILD2-B-CLIENT"),
    _phase("rebuild-2-b-server", "_RBT-L3-PHASE-REBUILD2-B-SERVER"),
    _phase("rebuild-2-b", "_RBT-L3-PHASE-REBUILD2-B"),
    _phase("hello-2-b-start", "_RBT-L3-PHASE-HELLO2-B-START"),
    *_repeat_phases("hello-2-b", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("hello-2-b-result", "_RBT-L3-PHASE-HELLO2-B-RESULT"),
    _phase("accept-3-start", "_RBT-L3-PHASE-ACCEPT3-START"),
    *_repeat_phases("accept-3", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("accept-3-result", "_RBT-L3-PHASE-ACCEPT3-RESULT"),
    *_repeat_phases("accept-3-fanout", "_RBT-L3-PHASE-STEP", FANOUT_STEP_COUNT),
    _phase(
        "accept-3-fanout-result", "_RBT-L3-PHASE-ACCEPT3-FANOUT-RESULT"
    ),
    _phase("accept-4-start", "_RBT-L3-PHASE-ACCEPT4-START"),
    *_repeat_phases("accept-4", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("accept-4-result", "_RBT-L3-PHASE-ACCEPT4-RESULT"),
    *_repeat_phases("accept-4-fanout", "_RBT-L3-PHASE-STEP", FANOUT_STEP_COUNT),
    _phase(
        "accept-4-fanout-result", "_RBT-L3-PHASE-ACCEPT4-FANOUT-RESULT"
    ),
    _phase("gap-b-start", "_RBT-L3-PHASE-GAP-B-START"),
    *_repeat_phases("gap-b", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("gap-b-result", "_RBT-L3-PHASE-GAP-B-RESULT"),
    _phase("fetch-b-start", "_RBT-L3-PHASE-FETCH-B-START"),
    *_repeat_phases("fetch-b", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("fetch-b-result", "_RBT-L3-PHASE-FETCH-B-RESULT"),
    _phase("accept-5-start", "_RBT-L3-PHASE-ACCEPT5-START"),
    *_repeat_phases("accept-5", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("accept-5-result", "_RBT-L3-PHASE-ACCEPT5-RESULT"),
    *_repeat_phases("accept-5-fanout", "_RBT-L3-PHASE-STEP", FANOUT_STEP_COUNT),
    _phase(
        "accept-5-fanout-result", "_RBT-L3-PHASE-ACCEPT5-FANOUT-RESULT"
    ),
    _phase("recovery-b-start", "_RBT-L3-PHASE-RECOVERY-B-START"),
    *_repeat_phases("recovery-b-bind", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase(
        "recovery-b-bind-result", "_RBT-L3-PHASE-RECOVERY-B-BIND-RESULT"
    ),
    *_repeat_phases("recovery-b-replay", "_RBT-L3-PHASE-STEP", NORMAL_STEP_COUNT),
    _phase("final-result", "_RBT-L3-PHASE-FINAL-RESULT"),
    _phase("remote-fini", "_RBT-L3-PHASE-REMOTE-FINI"),
    _phase("connector-fini", "_RBT-L3-PHASE-CONNECTOR-FINI"),
    _phase("host-cancel", "_RBT-L3-PHASE-HOST-CANCEL"),
    *_repeat_phases(
        "host-fini", "_RBT-L3-PHASE-HOST-FINI-STEP", HOST_FINI_STEP_COUNT
    ),
    _phase("fini", "_RBT-L3-PHASE-FINI"),
)

CONTRACT_STAGES = (*BURROW_PREFIX_STAGES, *LANDING3_STAGES)


PUBLIC_API_CONTRACTS = {
    FACET_MOUNT: (
        "STREAMS-RABBIT-FACET-MOUNT-INIT",
        "STREAMS-RABBIT-FACET-MOUNT-VALID?",
        "STREAMS-RABBIT-FACET-MOUNT-ROUTE@",
        "STREAMS-RABBIT-FACET-MOUNT-FINI",
    ),
    ACTION_MOUNT: (
        "STREAMS-RABBIT-ACTION-MOUNT-INIT",
        "STREAMS-RABBIT-ACTION-MOUNT-VALID?",
        "STREAMS-RABBIT-ACTION-MOUNT-ROUTE@",
        "STREAMS-RABBIT-ACTION-MOUNT-FINI",
    ),
    CONNECTOR: (
        "STREAMS-RABBIT-CONNECTOR-INIT",
        "STREAMS-RABBIT-CONNECTOR-POLL",
        "STREAMS-RABBIT-CONNECTOR-HELLO",
        "STREAMS-RABBIT-CONNECTOR-DETACH",
        "STREAMS-RABBIT-CONNECTOR-ATTACH",
        "STREAMS-RABBIT-CONNECTOR-CONTROL",
        "STREAMS-RABBIT-CONNECTOR-FINI",
    ),
    REMOTE_RESOURCE: (
        "STREAMS-RABBIT-REMOTE-RESOURCE-INIT",
        "STREAMS-RABBIT-REMOTE-RESOURCE-FETCH",
        "STREAMS-RABBIT-REMOTE-RESOURCE-POLL-CALLBACK",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CONSUME",
        "STREAMS-RABBIT-REMOTE-RESOURCE-CACHE@",
        "STREAMS-RABBIT-REMOTE-RESOURCE-FINI",
    ),
    REMOTE_SUB: (
        "STREAMS-RABBIT-REMOTE-SUB-INIT",
        "STREAMS-RABBIT-REMOTE-SUB-BIND",
        "STREAMS-RABBIT-REMOTE-SUB-REBIND",
        "STREAMS-RABBIT-REMOTE-SUB-BIND-RESULT@",
        "STREAMS-RABBIT-REMOTE-SUB-BIND-RESOLVE",
        "STREAMS-RABBIT-REMOTE-SUB-STATUS-VALID?",
        "STREAMS-RABBIT-REMOTE-SUB-PENDING@",
        "STREAMS-RABBIT-REMOTE-SUB-EVENT-RETRY",
        "STREAMS-RABBIT-REMOTE-SUB-LAST-EVENT@",
        "STREAMS-RABBIT-REMOTE-SUB-CONSUME",
        "STREAMS-RABBIT-REMOTE-SUB-RECONCILE",
        "STREAMS-RABBIT-REMOTE-SUB-FINI",
    ),
    REMOTE_ACTION: (
        "STREAMS-RABBIT-REMOTE-ACTION-INIT",
        "STREAMS-RABBIT-REMOTE-ACTION-PROFILE!",
        "STREAMS-RABBIT-REMOTE-ACTION-PREPARE",
        "STREAMS-RABBIT-REMOTE-ACTION-SEND",
        "STREAMS-RABBIT-REMOTE-ACTION-RETRY",
        "STREAMS-RABBIT-REMOTE-ACTION-POLL-CALLBACK",
        "STREAMS-RABBIT-REMOTE-ACTION-CONSUME",
        "STREAMS-RABBIT-REMOTE-ACTION-RECONCILE",
        "STREAMS-RABBIT-REMOTE-ACTION-RECEIPT@",
        "STREAMS-RABBIT-REMOTE-ACTION-FINI",
    ),
    BURROW: (
        "STREAMS-RABBIT-BURROW-ACTIVE-BINDING@",
        "STREAMS-RABBIT-BURROW-SERVICE",
        "STREAMS-RABBIT-BURROW-DETACH",
        "STREAMS-RABBIT-BURROW-REPLACE",
        "STREAMS-RABBIT-BURROW-CANCEL",
        "STREAMS-RABBIT-BURROW-FINI",
    ),
}

FIXTURE_API_USES = tuple(
    word
    for path, words in PUBLIC_API_CONTRACTS.items()
    for word in words
    if not (path == BURROW and word == "STREAMS-RABBIT-BURROW-SERVICE")
) + ("RABBIT-SERVER-SUBSCRIPTIONS-BIND-ADMISSION!",)


def _assert_static_contracts() -> None:
    burrow._assert_static_contracts()
    mux_fixture = MUX_FIXTURE.read_text(encoding="utf-8")
    fixture = FIXTURE.read_text(encoding="utf-8")
    fixture_contract = f"{mux_fixture}\n{fixture}"
    driver = Path(__file__).read_text(encoding="utf-8")
    sources = {
        path: path.read_text(encoding="utf-8") for path in PUBLIC_API_CONTRACTS
    }

    assert PHASE_MAX_STEPS == burrow.PHASE_MAX_STEPS == 120_000_000
    assert NETWORK_LOAD_STAGES[-1][0] == "server-subscription"
    assert FIXTURE_LOAD_STAGES[0][0] == "core-fixture"
    assert BURROW_PREFIX_STAGES[-1][0] == "fair-results"
    assert "S\" LIST\" S\" /fixture\"" in burrow.FIXTURE.read_text(
        encoding="utf-8"
    )

    providers = {
        BURROW: "akashic-streams-rburrow",
        FACET_MOUNT: "akashic-streams-rfmount",
        ACTION_MOUNT: "akashic-streams-ramount",
        CONNECTOR: "akashic-streams-rconn",
        REMOTE_RESOURCE: "akashic-streams-rres",
        REMOTE_SUB: "akashic-streams-rrsub",
        REMOTE_ACTION: "akashic-streams-rract",
    }
    for path, provider in providers.items():
        assert f"PROVIDED {provider}" in sources[path]
    for path, words in PUBLIC_API_CONTRACTS.items():
        for word in words:
            assert f": {word}" in sources[path]

    assert "PROVIDED rabbit-landing3-mux-test" in mux_fixture
    assert "PROVIDED rabbit-landing3-test" in fixture
    for word in dict.fromkeys(word for _, word, _ in LANDING3_STAGES):
        assert f": {word}" in fixture
    for word in FIXTURE_API_USES:
        assert word in fixture_contract
    for word in (
        "_RBT-L3-MUX-PENDING?",
        "_RBT-L3-MUX-ACK-LATEST",
        "_RBT-L3-MUX-RETRY-PENDING",
    ):
        assert f": {word}" in mux_fixture
        assert word in fixture
    assert "_RBT-BUR-SERVICE" in fixture

    exact_view = "application/akashic-value+json"
    assert f'S\" {exact_view}\"' in fixture
    assert set(re.findall(r'S\" (application/[^\"]+)\"', fixture)) == {
        exact_view
    }
    for body in (
        "[30,0,10,0,0]",
        "[31,0,1]",
        "[31,0,9]",
        "[32,0,1,11,1]",
        "[32,1,1,11,1]",
    ):
        assert f'S\" {body}\"' in fixture
    assert "IVJSON-ENCODE" in fixture
    assert "STR-STR=" in fixture or "COMPARE" in fixture
    assert re.search(r"CV-LEN@\s+(?:DUP\s+)?5\s+(?:=|<>)", fixture)
    assert re.search(r"CV-LEN@\s+(?:DUP\s+)?3\s+(?:=|<>)", fixture)
    assert "CV-LIST-NTH" in fixture

    for actor_field in (
        "CBR.PRACTICE-ID",
        "CBR.CONTEXT-ID",
        "CBR.CONTEXT-GEN",
        "CBR.EPOCH",
        "CBR.INVOCATION-ID",
        "CBR.ARGS-LEN",
        "CBR.ARGS-DIGEST",
    ):
        assert actor_field in fixture
    ledger_lookup = re.search(
        r"_RBT-L3-LEDGER-FIND\s+\?DUP\s+IF", fixture
    )
    revision_check = re.search(
        r"1\s+_RBT-L3-WORLD\s+L3W\.EXPECTED-CHECKS\s+\+!", fixture
    )
    assert ledger_lookup is not None and revision_check is not None
    assert ledger_lookup.start() < revision_check.start()

    assert 'S" /fixture/events"' in fixture
    assert 'S" /fixture/action"' in fixture
    assert "RMSG-KIND-FETCH" in fixture
    assert "STREAMS-RABBIT-REMOTE-SUB-BIND" in fixture
    assert "STREAMS-RABBIT-REMOTE-ACTION-SEND" in fixture
    assert "STREAMS-RABBIT-REMOTE-ACTION-RETRY" in fixture
    assert "_RBT-L3-PHASE-REPLAY11-RESULT" in fixture
    assert "_RBT-L3-PHASE-GAP-B-RESULT" in fixture
    assert "_RBT-L3-PHASE-FINAL-RESULT" in fixture
    assert "_RBT-L3-PHASE-FINI" in fixture

    assert "RABBIT-CLIENT-POLL" not in fixture
    assert "RABBIT-SERVER-POLL" not in fixture
    assert "RABBIT-SERVER-SUBSCRIPTIONS-SERVICE" not in fixture
    assert "4096" not in fixture
    assert sum(
        word == "_RBT-L3-PHASE-STEP" for _, word, _ in LANDING3_STAGES
    ) >= NORMAL_STEP_COUNT
    assert "ext_mem_size=64 << 20" in driver
    assert "num_cores=1" in driver
    assert "total_sectors=8192" in driver

    for source in (sources[FACET_MOUNT], sources[ACTION_MOUNT]):
        assert exact_view in source
        assert "STREAMS-RABBIT-BURROW-ACTIVE-BINDING@" in source
    assert "IVJSON-ENCODE" in sources[ACTION_MOUNT]
    assert "COMPARE IF" in sources[ACTION_MOUNT]
    assert '200 S" RESULT"' in sources[ACTION_MOUNT]
    assert '412 S" PRECONDITION FAIL"' in sources[ACTION_MOUNT]
    assert '409 S" CONFLICT"' in sources[ACTION_MOUNT]
    assert "IVJSON-DECODE-AS" in sources[REMOTE_RESOURCE]
    assert "_SRRAP-VIEW?" in sources[REMOTE_ACTION]
    assert "SRRA.ACTION-VIEW-A" in sources[REMOTE_ACTION]
    assert "SRRA.RECEIPT-VIEW-A" in sources[REMOTE_ACTION]


def _initial_files(harness) -> tuple[tuple[str, bytes], ...]:
    return (
        *burrow._initial_files(harness),
        (
            MUX_FIXTURE_IMAGE_PATH,
            harness._minify_forth(
                MUX_FIXTURE.read_text(encoding="utf-8")
            ).encode("utf-8"),
        ),
        (
            FIXTURE_IMAGE_PATH,
            harness._minify_forth(FIXTURE.read_text(encoding="utf-8")).encode(
                "utf-8"
            ),
        ),
    )


def _profile(harness, autoexec: str):
    profile_name = "streams-rabbit-landing3-source"
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
            "runtime/registry.f",
            "interop/request-bus.f",
            "interop/capability-facet.f",
            "interop/codecs/json-value.f",
            "tui/applets/streams/rabbit-burrow.f",
            "tui/applets/streams/rabbit-facet-mount.f",
            "tui/applets/streams/rabbit-action-mount.f",
            "tui/applets/streams/rabbit-connector.f",
            "tui/applets/streams/rabbit-remote.f",
            "tui/applets/streams/rabbit-remote-sub.f",
            "tui/applets/streams/rabbit-remote-action.f",
        ),
        resources=(),
        autoexec=autoexec,
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "STREAMS RABBIT LANDING 3 ASSERT",
            "STREAMS RABBIT LANDING 3 STACK",
            "STREAMS RABBIT LANDING 3 LOAD STACK FAIL",
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
        total_sectors=8192,
    )
    return profile_name, harness.PROFILES[profile_name]


def _run(timeout: float) -> int:
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - source-loaded Rabbit Streams Landing 3 slice\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." STREAMS RABBIT LANDING 3 LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH DEPTH 0 ?DO DROP LOOP THEN\n'
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
        '." STREAMS RABBIT LANDING 3 PASS " _RBT-CHECKS @ . CR TX-FLUSH\n'
    )

    profile_name, profile = _profile(harness, "".join(autoexec))
    image = Path("/tmp/akashic-streams-rabbit-landing3-source.img")
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
            print(f"Landing 3 {label}: starting", flush=True)
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
        match = re.search(r"STREAMS RABBIT LANDING 3 PASS[ \t]+([0-9]+)", raw)
        ok = match is not None and not failures
        print(
            "Streams Rabbit Landing 3: "
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
    print(f"Landing 3 {label}: FAIL")
    print(
        f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
        f"stop={report.reason}"
    )
    for failure in failures:
        print(f"  {failure}")
    if len(raw) > 8000:
        print(raw[:4000])
        print("\n... Landing 3 trace middle omitted ...\n")
    print(raw[-4000:])
    print(machine.screen_text())
    return 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--landing3", action="store_true")
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("STREAMS RABBIT LANDING 3 STATIC PASS")
        return 0
    return _run(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
