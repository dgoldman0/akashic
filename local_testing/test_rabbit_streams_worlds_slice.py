#!/usr/bin/env python3
"""Qualify the transport-neutral Rabbit protocol foundation."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
PROFILE = ROOT / "akashic" / "net" / "rabbit" / "profile.f"
FRAME = ROOT / "akashic" / "net" / "rabbit" / "frame.f"
MESSAGE = ROOT / "akashic" / "net" / "rabbit" / "message.f"
BUILDER = ROOT / "akashic" / "net" / "rabbit" / "builder.f"
SESSION = ROOT / "akashic" / "net" / "rabbit" / "session.f"
CONNECTION = ROOT / "akashic" / "net" / "rabbit" / "connection.f"
CLIENT = ROOT / "akashic" / "net" / "rabbit" / "client.f"
SUBSCRIPTION = ROOT / "akashic" / "net" / "rabbit" / "subscription.f"
ROUTER = ROOT / "akashic" / "net" / "rabbit" / "router.f"
SERVER = ROOT / "akashic" / "net" / "rabbit" / "server.f"
SERVER_SUBSCRIPTION = (
    ROOT / "akashic" / "net" / "rabbit" / "server-subscription.f"
)
STREAMS_CONNECTOR = (
    ROOT
    / "akashic"
    / "tui"
    / "applets"
    / "streams"
    / "rabbit-connector.f"
)
MEMORY = ROOT / "akashic" / "net" / "transports" / "memory-duplex.f"
DOC = ROOT / "docs" / "net" / "rabbit.md"
FIXTURE = LOCAL_TESTING / "rabbit-core-test.f"
CLIENT_FIXTURE = LOCAL_TESTING / "rabbit-client-test.f"
CLIENT_JOURNEY = LOCAL_TESTING / "rabbit-client-flow.f"
SUBSCRIPTION_FIXTURE = LOCAL_TESTING / "rabbit-sub-test.f"
SERVER_FIXTURE = LOCAL_TESTING / "rabbit-server-test.f"
SERVER_SUBSCRIPTION_FIXTURE = (
    LOCAL_TESTING / "rabbit-servsub-test.f"
)
CAPSTONE_FIXTURE = LOCAL_TESTING / "rabbit-cap-test.f"
STREAMS_CONNECTOR_FIXTURE = LOCAL_TESTING / "rabbit-connector-test.f"

PASS_MARKER = "RABBIT CORE PASS"
PHASE_MAX_STEPS = 120_000_000
LOAD_STAGES = (
    ("profile", "net/rabbit/profile.f", "RABBIT PROFILE READY"),
    (
        "memory-span",
        "utils/memory-span.f",
        "RABBIT MEMORY SPAN READY",
    ),
    ("string", "utils/string.f", "RABBIT STRING READY"),
    ("utf8", "text/utf8.f", "RABBIT UTF8 READY"),
    ("io-port", "net/io-port.f", "RABBIT IO PORT READY"),
    ("frame", "net/rabbit/frame.f", "RABBIT FRAME READY"),
    ("message", "net/rabbit/message.f", "RABBIT MESSAGE READY"),
    (
        "memory-duplex",
        "net/transports/memory-duplex.f",
        "RABBIT MEMORY DUPLEX READY",
    ),
    ("session", "net/rabbit/session.f", "RABBIT SESSION READY"),
    ("builder", "net/rabbit/builder.f", "RABBIT BUILDER READY"),
    ("connection", "net/rabbit/connection.f", "RABBIT CONNECTION READY"),
    ("client", "net/rabbit/client.f", "RABBIT CLIENT READY"),
    (
        "subscription",
        "net/rabbit/subscription.f",
        "RABBIT SUBSCRIPTION READY",
    ),
    ("router", "net/rabbit/router.f", "RABBIT ROUTER READY"),
    ("server", "net/rabbit/server.f", "RABBIT SERVER READY"),
    (
        "fixture",
        "local_testing/rabbit-core-test.f",
        "RABBIT CORE FIXTURE READY",
    ),
    (
        "client-fixture",
        "local_testing/rabbit-client-test.f",
        "RABBIT CLIENT FIXTURE READY",
    ),
    (
        "client-journey",
        "local_testing/rabbit-client-flow.f",
        "RABBIT CLIENT JOURNEY READY",
    ),
    (
        "subscription-fixture",
        "local_testing/rabbit-sub-test.f",
        "RABBIT SUBSCRIPTION FIXTURE READY",
    ),
    (
        "server-fixture",
        "local_testing/rabbit-server-test.f",
        "RABBIT SERVER FIXTURE READY",
    ),
    (
        "server-subscription",
        "net/rabbit/server-subscription.f",
        "RABBIT SERVER SUBSCRIPTION READY",
    ),
    (
        "server-subscription-fixture",
        "local_testing/rabbit-servsub-test.f",
        "RABBIT SERVER SUBSCRIPTION FIXTURE READY",
    ),
    (
        "two-peer-capstone-fixture",
        "local_testing/rabbit-cap-test.f",
        "RABBIT TWO PEER CAPSTONE FIXTURE READY",
    ),
    (
        "streams-connector",
        "tui/applets/streams/rabbit-connector.f",
        "STREAMS RABBIT CONNECTOR READY",
    ),
    (
        "streams-connector-fixture",
        "local_testing/rabbit-connector-test.f",
        "STREAMS RABBIT CONNECTOR FIXTURE READY",
    ),
)
CONTRACT_STAGES = (
    ("base", "_RBT-RUN", "RABBIT CORE BASE PASS", False),
    ("client-init", "_RBT-CLI-PHASE-INIT", "RABBIT CLIENT INIT PASS", True),
    (
        "client-handshake",
        "_RBT-CLI-PHASE-HANDSHAKE",
        "RABBIT CLIENT HANDSHAKE PASS",
        True,
    ),
    (
        "client-builder-alias",
        "_RBT-CLI-PHASE-BUILDER-ALIAS",
        "RABBIT CLIENT BUILDER ALIAS PASS",
        True,
    ),
    (
        "client-requests",
        "_RBT-CLI-PHASE-REQUESTS-EVENT",
        "RABBIT CLIENT REQUESTS PASS",
        True,
    ),
    (
        "client-responses",
        "_RBT-CLI-PHASE-RESPONSES-GENERATION",
        "RABBIT CLIENT RESPONSES PASS",
        True,
    ),
    (
        "client-cancellation",
        "_RBT-CLI-PHASE-CANCELLATION",
        "RABBIT CLIENT CANCELLATION PASS",
        True,
    ),
    (
        "client-teardown-client",
        "_RBT-CLI-PHASE-TEARDOWN-CLIENT",
        "RABBIT CLIENT TEARDOWN CLIENT PASS",
        True,
    ),
    (
        "client-teardown-connection-close",
        "_RBT-CLI-PHASE-TEARDOWN-CONNECTION-CLOSE",
        "RABBIT CLIENT TEARDOWN CONNECTION CLOSE PASS",
        True,
    ),
    (
        "client-teardown-connection-fini",
        "_RBT-CLI-PHASE-TEARDOWN-CONNECTION-FINI",
        "RABBIT CLIENT TEARDOWN CONNECTION FINI PASS",
        True,
    ),
    (
        "client-teardown-queues",
        "_RBT-CLI-PHASE-TEARDOWN-QUEUES",
        "RABBIT CLIENT TEARDOWN QUEUES PASS",
        True,
    ),
    (
        "client-teardown-transport",
        "_RBT-CLI-PHASE-TEARDOWN-TRANSPORT",
        "RABBIT CLIENT TEARDOWN TRANSPORT PASS",
        True,
    ),
    (
        "subscription-graph-init",
        "_RBT-CLI-PHASE-INIT",
        "RABBIT SUBSCRIPTION GRAPH INIT PASS",
        True,
    ),
    (
        "subscription-handshake",
        "_RBT-CLI-PHASE-HANDSHAKE",
        "RABBIT SUBSCRIPTION HANDSHAKE PASS",
        True,
    ),
    (
        "subscription-owner-init",
        "_RBT-SUB-PHASE-OWNER-INIT",
        "RABBIT SUBSCRIPTION OWNER INIT PASS",
        True,
    ),
    (
        "subscription-first-bind",
        "_RBT-SUB-PHASE-FIRST-BIND",
        "RABBIT SUBSCRIPTION FIRST BIND PASS",
        True,
    ),
    (
        "subscription-fallback-invalid",
        "_RBT-SUB-PHASE-FALLBACK-INVALID",
        "RABBIT SUBSCRIPTION FALLBACK INVALID PASS",
        True,
    ),
    (
        "subscription-event-new",
        "_RBT-SUB-PHASE-EVENT-NEW",
        "RABBIT SUBSCRIPTION EVENT NEW PASS",
        True,
    ),
    (
        "subscription-event-new-ack",
        "_RBT-SUB-PHASE-EVENT-NEW-ACK",
        "RABBIT SUBSCRIPTION EVENT NEW ACK PASS",
        True,
    ),
    (
        "subscription-event-duplicate",
        "_RBT-SUB-PHASE-EVENT-DUPLICATE",
        "RABBIT SUBSCRIPTION EVENT DUPLICATE PASS",
        True,
    ),
    (
        "subscription-event-gap",
        "_RBT-SUB-PHASE-EVENT-GAP",
        "RABBIT SUBSCRIPTION EVENT GAP PASS",
        True,
    ),
    (
        "subscription-disconnect",
        "_RBT-SUB-PHASE-DISCONNECT",
        "RABBIT SUBSCRIPTION DISCONNECT PASS",
        True,
    ),
    (
        "subscription-disconnect-graph-fini",
        "_RBT-SUB-PHASE-DISCONNECT-GRAPH-FINI",
        "RABBIT SUBSCRIPTION DISCONNECT GRAPH FINI PASS",
        True,
    ),
    (
        "subscription-regraph-init",
        "_RBT-CLI-PHASE-INIT",
        "RABBIT SUBSCRIPTION REGRAPH INIT PASS",
        True,
    ),
    (
        "subscription-rehandshake",
        "_RBT-CLI-PHASE-HANDSHAKE",
        "RABBIT SUBSCRIPTION REHANDSHAKE PASS",
        True,
    ),
    (
        "subscription-rebind",
        "_RBT-SUB-PHASE-REBIND",
        "RABBIT SUBSCRIPTION REBIND PASS",
        True,
    ),
    (
        "subscription-replay",
        "_RBT-SUB-PHASE-REPLAY",
        "RABBIT SUBSCRIPTION REPLAY PASS",
        True,
    ),
    (
        "subscription-fini",
        "_RBT-SUB-PHASE-FINI",
        "RABBIT SUBSCRIPTION FINI PASS",
        True,
    ),
    (
        "server-graph-init",
        "_RBT-CLI-PHASE-INIT",
        "RABBIT SERVER GRAPH INIT PASS",
        True,
    ),
    (
        "server-owner-init",
        "_RBT-SRV-PHASE-OWNER-INIT",
        "RABBIT SERVER OWNER INIT PASS",
        True,
    ),
    (
        "server-handshake-control",
        "_RBT-SRV-PHASE-HANDSHAKE-CONTROL",
        "RABBIT SERVER HANDSHAKE CONTROL PASS",
        True,
    ),
    (
        "server-fetch",
        "_RBT-SRV-PHASE-FETCH",
        "RABBIT SERVER FETCH PASS",
        True,
    ),
    (
        "server-miss-deny",
        "_RBT-SRV-PHASE-MISS-DENY",
        "RABBIT SERVER MISS DENY PASS",
        True,
    ),
    (
        "server-wrong-correlation",
        "_RBT-SRV-PHASE-WRONG-CORRELATION",
        "RABBIT SERVER WRONG CORRELATION PASS",
        True,
    ),
    (
        "server-handler-failures",
        "_RBT-SRV-PHASE-HANDLER-FAILURES",
        "RABBIT SERVER HANDLER FAILURES PASS",
        True,
    ),
    (
        "server-extension-lane-zero",
        "_RBT-SRV-PHASE-EXTENSION-LANE-ZERO",
        "RABBIT SERVER EXTENSION LANE ZERO PASS",
        True,
    ),
    (
        "server-event-delivery",
        "_RBT-SRV-PHASE-EVENT-DELIVERY",
        "RABBIT SERVER EVENT DELIVERY PASS",
        True,
    ),
    (
        "server-event-reserve-liveness",
        "_RBT-SRV-PHASE-EVENT-RESERVE-LIVENESS",
        "RABBIT SERVER EVENT RESERVE LIVENESS PASS",
        True,
    ),
    (
        "server-backpressure",
        "_RBT-SRV-PHASE-BACKPRESSURE",
        "RABBIT SERVER BACKPRESSURE PASS",
        True,
    ),
    (
        "server-fini",
        "_RBT-SRV-PHASE-FINI",
        "RABBIT SERVER FINI PASS",
        True,
    ),
    (
        "server-denial-graph-init",
        "_RBT-CLI-PHASE-INIT",
        "RABBIT SERVER DENIAL GRAPH INIT PASS",
        True,
    ),
    (
        "server-denial-owner-init",
        "_RBT-SRV-PHASE-OWNER-INIT",
        "RABBIT SERVER DENIAL OWNER INIT PASS",
        True,
    ),
    (
        "server-admission-deny",
        "_RBT-SRV-PHASE-ADMISSION-DENY",
        "RABBIT SERVER ADMISSION DENY PASS",
        True,
    ),
    (
        "server-denial-fini",
        "_RBT-SRV-PHASE-DENIAL-FINI",
        "RABBIT SERVER DENIAL FINI PASS",
        True,
    ),
    (
        "server-sub-graph-init",
        "_RBT-CLI-PHASE-INIT",
        "RABBIT SERVER SUBSCRIPTION GRAPH INIT PASS",
        True,
    ),
    (
        "server-sub-owner-init",
        "_RBT-SSRV-PHASE-OWNER-INIT",
        "RABBIT SERVER SUBSCRIPTION OWNER INIT PASS",
        True,
    ),
    (
        "server-sub-handshake",
        "_RBT-SSRV-PHASE-HANDSHAKE",
        "RABBIT SERVER SUBSCRIPTION HANDSHAKE PASS",
        True,
    ),
    (
        "server-sub-bind-since",
        "_RBT-SSRV-PHASE-BIND-SINCE",
        "RABBIT SERVER SUBSCRIPTION BIND SINCE PASS",
        True,
    ),
    (
        "server-sub-no-credit",
        "_RBT-SSRV-PHASE-NO-CREDIT",
        "RABBIT SERVER SUBSCRIPTION NO CREDIT PASS",
        True,
    ),
    (
        "server-sub-events-retained",
        "_RBT-SSRV-PHASE-EVENTS-RETAINED",
        "RABBIT SERVER SUBSCRIPTION EVENTS RETAINED PASS",
        True,
    ),
    (
        "server-sub-event14-reserve",
        "_RBT-SSRV-PHASE-EVENT14-RESERVE",
        "RABBIT SERVER SUBSCRIPTION EVENT14 RESERVE PASS",
        True,
    ),
    (
        "server-sub-event14-retry",
        "_RBT-SSRV-PHASE-EVENT14-RETRY",
        "RABBIT SERVER SUBSCRIPTION EVENT14 RETRY PASS",
        True,
    ),
    (
        "server-sub-fini",
        "_RBT-SSRV-PHASE-FINI",
        "RABBIT SERVER SUBSCRIPTION FINI PASS",
        True,
    ),
    (
        "capstone-graphs-init",
        "_RBT-CAP-PHASE-GRAPHS-INIT",
        "RABBIT CAPSTONE GRAPHS INIT PASS",
        True,
    ),
    (
        "capstone-builder-connection-geometry",
        "_RBT-CAP-PHASE-BUILDER-CONNECTION-GEOMETRY",
        "RABBIT CAPSTONE BUILDER CONNECTION GEOMETRY PASS",
        True,
    ),
    (
        "capstone-server-geometry",
        "_RBT-CAP-PHASE-SERVER-GEOMETRY",
        "RABBIT CAPSTONE SERVER GEOMETRY PASS",
        True,
    ),
    (
        "capstone-subscription-geometry",
        "_RBT-CAP-PHASE-SUBSCRIPTION-GEOMETRY",
        "RABBIT CAPSTONE SUBSCRIPTION GEOMETRY PASS",
        True,
    ),
    (
        "capstone-handshakes",
        "_RBT-CAP-PHASE-HANDSHAKES",
        "RABBIT CAPSTONE HANDSHAKES PASS",
        True,
    ),
    (
        "capstone-discovery",
        "_RBT-CAP-PHASE-DISCOVERY",
        "RABBIT CAPSTONE DISCOVERY PASS",
        True,
    ),
    (
        "capstone-bind-both",
        "_RBT-CAP-PHASE-BIND-BOTH",
        "RABBIT CAPSTONE BIND BOTH PASS",
        True,
    ),
    (
        "capstone-actions",
        "_RBT-CAP-PHASE-ACTIONS",
        "RABBIT CAPSTONE ACTIONS PASS",
        True,
    ),
    (
        "capstone-actions-complete",
        "_RBT-CAP-PHASE-ACTIONS-COMPLETE",
        "RABBIT CAPSTONE ACTIONS COMPLETE PASS",
        True,
    ),
    (
        "capstone-post-action-fetch",
        "_RBT-CAP-PHASE-POST-ACTION-FETCH",
        "RABBIT CAPSTONE POST ACTION FETCH PASS",
        True,
    ),
    (
        "capstone-independent-pressure",
        "_RBT-CAP-PHASE-INDEPENDENT-PRESSURE",
        "RABBIT CAPSTONE INDEPENDENT PRESSURE PASS",
        True,
    ),
    (
        "capstone-b-saturates",
        "_RBT-CAP-PHASE-B-SATURATES",
        "RABBIT CAPSTONE B SATURATES PASS",
        True,
    ),
    (
        "capstone-a-continues",
        "_RBT-CAP-PHASE-A-CONTINUES",
        "RABBIT CAPSTONE A CONTINUES PASS",
        True,
    ),
    (
        "capstone-b-disconnect",
        "_RBT-CAP-PHASE-B-DISCONNECT",
        "RABBIT CAPSTONE B DISCONNECT PASS",
        True,
    ),
    (
        "capstone-b-rebuild-rebind",
        "_RBT-CAP-PHASE-B-REBUILD-REBIND",
        "RABBIT CAPSTONE B REBUILD REBIND PASS",
        True,
    ),
    (
        "capstone-b-exact-suffix",
        "_RBT-CAP-PHASE-B-EXACT-SUFFIX",
        "RABBIT CAPSTONE B EXACT SUFFIX PASS",
        True,
    ),
    (
        "capstone-fini",
        "_RBT-CAP-PHASE-FINI",
        "RABBIT CAPSTONE FINI PASS",
        True,
    ),
    (
        "streams-connector-init",
        "_RBT-RCONN-PHASE-INIT",
        "STREAMS RABBIT CONNECTOR INIT PASS",
        True,
    ),
    (
        "streams-connector-result-ownership",
        "_RBT-RCONN-PHASE-RESULT-OWNERSHIP",
        "STREAMS RABBIT CONNECTOR RESULT OWNERSHIP PASS",
        True,
    ),
    (
        "streams-connector-detach",
        "_RBT-RCONN-PHASE-DETACH",
        "STREAMS RABBIT CONNECTOR DETACH PASS",
        True,
    ),
    (
        "streams-connector-attach",
        "_RBT-RCONN-PHASE-ATTACH",
        "STREAMS RABBIT CONNECTOR ATTACH PASS",
        True,
    ),
    (
        "streams-connector-reconnect-aba",
        "_RBT-RCONN-PHASE-RECONNECT-ABA",
        "STREAMS RABBIT CONNECTOR RECONNECT ABA PASS",
        True,
    ),
    (
        "streams-connector-fini",
        "_RBT-RCONN-PHASE-FINI",
        "STREAMS RABBIT CONNECTOR FINI PASS",
        True,
    ),
)


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _declarations(path: Path, source: str) -> list[tuple[str, str]]:
    return re.findall(
        r"(?mi)^[ \t]*(CREATE|VARIABLE|VALUE|DEFER|GUARD)[ \t]+(\S+)",
        source,
    )


def _assert_physical_comments(path: Path, source: str) -> None:
    for line_number, line in enumerate(source.splitlines(), start=1):
        forth_code = line.split("\\", 1)[0]
        if "(" in forth_code:
            assert ")" in forth_code.split("(", 1)[1], (
                "parenthesized comments must close on their physical line: "
                f"{path}:{line_number}"
            )


def _assert_static_contracts() -> None:
    profile = PROFILE.read_text(encoding="utf-8")
    frame = FRAME.read_text(encoding="utf-8")
    message = MESSAGE.read_text(encoding="utf-8")
    builder = BUILDER.read_text(encoding="utf-8")
    session = SESSION.read_text(encoding="utf-8")
    connection = CONNECTION.read_text(encoding="utf-8")
    client = CLIENT.read_text(encoding="utf-8")
    subscription = SUBSCRIPTION.read_text(encoding="utf-8")
    router = ROUTER.read_text(encoding="utf-8")
    server = SERVER.read_text(encoding="utf-8")
    server_subscription = SERVER_SUBSCRIPTION.read_text(encoding="utf-8")
    streams_connector = STREAMS_CONNECTOR.read_text(encoding="utf-8")
    memory = MEMORY.read_text(encoding="utf-8")
    doc = " ".join(DOC.read_text(encoding="utf-8").split())
    fixture = FIXTURE.read_text(encoding="utf-8")
    client_fixture = CLIENT_FIXTURE.read_text(encoding="utf-8")
    client_journey = CLIENT_JOURNEY.read_text(encoding="utf-8")
    subscription_fixture = SUBSCRIPTION_FIXTURE.read_text(encoding="utf-8")
    server_fixture = SERVER_FIXTURE.read_text(encoding="utf-8")
    server_subscription_fixture = SERVER_SUBSCRIPTION_FIXTURE.read_text(
        encoding="utf-8"
    )
    capstone_fixture = CAPSTONE_FIXTURE.read_text(encoding="utf-8")
    streams_connector_fixture = STREAMS_CONNECTOR_FIXTURE.read_text(
        encoding="utf-8"
    )

    assert 0 < PHASE_MAX_STEPS <= 120_000_000
    assert len({name for name, _, _ in LOAD_STAGES}) == len(LOAD_STAGES)
    assert len({marker for _, _, marker in LOAD_STAGES}) == len(LOAD_STAGES)

    assert _requires(FRAME) == [
        "../../utils/memory-span.f",
        "../../utils/string.f",
        "../../text/utf8.f",
    ]
    assert _requires(PROFILE) == []
    assert _requires(SESSION) == [
        "profile.f",
        "../io-port.f",
        "../../utils/memory-span.f",
    ]
    assert _requires(MESSAGE) == [
        "frame.f",
        "profile.f",
        "../../utils/string.f",
    ]
    assert _requires(BUILDER) == [
        "frame.f",
        "message.f",
        "profile.f",
        "../../utils/memory-span.f",
        "../../utils/string.f",
    ]
    assert _requires(ROUTER) == [
        "../../utils/memory-span.f",
        "../../text/utf8.f",
    ]
    assert _requires(CONNECTION) == [
        "builder.f",
        "session.f",
        "../../utils/memory-span.f",
    ]
    assert _requires(CLIENT) == [
        "connection.f",
        "../../utils/memory-span.f",
    ]
    assert _requires(SUBSCRIPTION) == [
        "client.f",
        "../../utils/memory-span.f",
        "../../text/utf8.f",
    ]
    assert _requires(SERVER) == [
        "connection.f",
        "router.f",
        "../../utils/memory-span.f",
        "../../text/utf8.f",
    ]
    assert _requires(SERVER_SUBSCRIPTION) == [
        "server.f",
        "../../utils/memory-span.f",
        "../../text/utf8.f",
    ]
    assert _requires(STREAMS_CONNECTOR) == [
        "../../../net/rabbit/subscription.f",
        "../../../utils/memory-span.f",
    ]
    assert _requires(MEMORY) == [
        "../io-port.f",
        "../../utils/memory-span.f",
    ]

    for source, provider in (
        (profile, "PROVIDED akashic-rabbit-profile"),
        (frame, "PROVIDED akashic-rabbit-frame"),
        (message, "PROVIDED akashic-rabbit-message"),
        (builder, "PROVIDED akashic-rabbit-builder"),
        (session, "PROVIDED akashic-rabbit-session"),
        (connection, "PROVIDED akashic-rabbit-connection"),
        (client, "PROVIDED akashic-rabbit-client"),
        (subscription, "PROVIDED akashic-rabbit-subscription"),
        (router, "PROVIDED akashic-rabbit-router"),
        (server, "PROVIDED akashic-rabbit-server"),
        (
            server_subscription,
            "PROVIDED akashic-rabbit-server-subscription",
        ),
        (streams_connector, "PROVIDED akashic-streams-rconn"),
        (memory, "PROVIDED akashic-net-memory-duplex"),
    ):
        assert provider in source

    assert ": STREAMS-RABBIT-CONNECTOR-OWNED-SPAN-OVERLAP?" in streams_connector
    assert ": STREAMS-RABBIT-CONNECTOR-OP-STATE@" in streams_connector
    assert "_SRCONN-SPAN-HITS-SUB-GRAPH?" in streams_connector

    frame_declarations = _declarations(FRAME, frame)
    assert frame_declarations
    assert all(kind == "VARIABLE" for kind, _ in frame_declarations)
    assert all(name.startswith("_RBF") for _, name in frame_declarations)
    assert "synchronous and deliberately non-reentrant" in frame
    assert "operation scratch only" in frame
    message_declarations = _declarations(MESSAGE, message)
    assert message_declarations
    assert all(kind == "VARIABLE" for kind, _ in message_declarations)
    assert all(name.startswith("_RMSG") for _, name in message_declarations)
    assert "deliberately state-free" in message
    builder_declarations = _declarations(BUILDER, builder)
    assert builder_declarations
    assert all(kind == "VARIABLE" for kind, _ in builder_declarations)
    assert all(name.startswith("_RMSGB") for _, name in builder_declarations)
    assert "copies every start-line" in builder
    assert "non-reentrant" in builder
    connection_declarations = _declarations(CONNECTION, connection)
    assert connection_declarations
    assert all(kind == "VARIABLE" for kind, _ in connection_declarations)
    assert all(
        name.startswith("_RCONN") or name.startswith("_RTXQ")
        for _, name in connection_declarations
    )
    assert "one cooperative owner" in connection
    assert "control traffic takes priority" in connection
    assert "remain owned until a cumulative lane ACK" in connection
    client_declarations = _declarations(CLIENT, client)
    assert client_declarations
    assert all(kind == "VARIABLE" for kind, _ in client_declarations)
    assert all(name.startswith("_RCLI") for _, name in client_declarations)
    assert "One cooperative owner must" in client
    assert "exact session (Lane, Txn)" in client
    subscription_declarations = _declarations(SUBSCRIPTION, subscription)
    assert subscription_declarations
    assert all(kind == "VARIABLE" for kind, _ in subscription_declarations)
    assert all(name.startswith("_RSUB") for _, name in subscription_declarations)
    assert "Lane Seq and Event-Seq are deliberately independent" in subscription
    assert "recursive dispatch and registration/lifecycle mutation are refused" in subscription
    router_declarations = _declarations(ROUTER, router)
    assert router_declarations
    assert all(kind == "VARIABLE" for kind, _ in router_declarations)
    assert all(name.startswith("_RROUTER") for _, name in router_declarations)
    assert "every call must be serialized" in router
    server_declarations = _declarations(SERVER, server)
    assert server_declarations
    assert all(kind == "VARIABLE" for kind, _ in server_declarations)
    assert all(name.startswith("_RSERVER") for _, name in server_declarations)
    assert "deliberately a per-peer protocol owner" in server
    assert "globally non-reentrant" in server
    server_subscription_declarations = _declarations(
        SERVER_SUBSCRIPTION, server_subscription
    )
    assert server_subscription_declarations
    assert all(
        kind == "VARIABLE" for kind, _ in server_subscription_declarations
    )
    assert all(
        name.startswith("_RSERVSUB")
        for _, name in server_subscription_declarations
    )
    assert "takes exclusive ownership of one initialized" in server_subscription
    assert "Registration is commit-gated" in server_subscription
    assert "never treats the immutable router context" in server_subscription
    streams_connector_declarations = _declarations(
        STREAMS_CONNECTOR, streams_connector
    )
    assert streams_connector_declarations
    assert all(
        kind == "VARIABLE" for kind, _ in streams_connector_declarations
    )
    assert all(
        name.startswith("_SRCONN")
        for _, name in streams_connector_declarations
    )
    assert "long-lived Streams Rabbit client connector" in streams_connector
    assert "retryable DETACH/FINI cleanup path" in streams_connector
    assert not _declarations(PROFILE, profile)
    assert not _declarations(SESSION, session)
    assert not _declarations(MEMORY, memory)

    for word in (
        "RBF-PARSER-BYTES",
        "RBF-PARSER-INIT",
        "RBF-PARSER-RESET",
        "RBF-FEED",
        "RBF-EOF",
        "RBF-FRAME-MEASURE",
        "RBF-FRAME-ENCODE",
        "RBF-HEADER$",
        "RBF-S-TRUNCATED",
    ):
        assert word in frame
    for word in (
        "RMSG-ADMIT",
        "RMSG-KIND@",
        "RMSG-STATUS@",
        "RMSG-LABEL$",
        "RMSG-LANE@",
        "RMSG-TXN$",
        "RMSG-SEQ@",
        "RMSG-EVENT-SEQ@",
        "RMSG-CREDIT@",
        "RMSG-ACCEPT-VIEW$",
        "RMSG-BURROW-ID$",
        "RMSG-TIMEOUT@",
        "RMSG-CAPS@",
        "RMSG-HELLO-OK-STATUS",
        "RMSG-PONG-STATUS",
    ):
        assert word in message
    for word in (
        "RMSGB-BUILDER-BYTES",
        "RMSGB-INIT",
        "RMSGB-RESET",
        "RMSGB-FINI",
        "RMSGB-READY-FRAME@",
        "RMSGB-OWNED-SPAN-OVERLAP?",
        "RMSGB-OWNED-GRAPHS-DISJOINT?",
        "RMSGB-BEGIN-HELLO",
        "RMSGB-BEGIN-REQUEST",
        "RMSGB-BEGIN-EVENT",
        "RMSGB-BEGIN-ACK",
        "RMSGB-BEGIN-CREDIT",
        "RMSGB-BEGIN-RESPONSE",
        "RMSGB-BEGIN-CONTROL-RESPONSE",
        "RMSGB-ACCEPT-VIEW!",
        "RMSGB-BURROW-ID!",
        "RMSGB-TIMEOUT!",
        "RMSGB-BODY!",
        "RMSGB-SEAL",
        "RMSGB-MEASURE",
        "RMSGB-ENCODE",
    ):
        assert word in builder
    for word in (
        "RABBIT-SESSION-INIT",
        "RABBIT-SESSION-CONFIGURE",
        "RABBIT-SESSION-HELLO-BEGIN",
        "RABBIT-SESSION-HELLO-ACCEPT",
        "RABBIT-SESSION-APP-LANE-OPEN",
        "RABBIT-SESSION-CREDIT+",
        "RABBIT-SESSION-GRANT-CREDIT",
        "RABBIT-SESSION-NEXT-SEND@",
        "RABBIT-SESSION-RESERVE-SEND-EXACT",
        "RABBIT-SESSION-RESERVE-SEND",
        "RABBIT-SESSION-NEXT-CONTROL@",
        "RABBIT-SESSION-RESERVE-CONTROL-EXACT",
        "RABBIT-SESSION-RESERVE-CONTROL",
        "RABBIT-SESSION-ACK",
        "RABBIT-SESSION-INBOUND-CLASSIFY",
        "RABBIT-SESSION-INBOUND-COMMIT",
        "RABBIT-SESSION-INBOUND",
        "RABBIT-SESSION-RECV-CREDIT@",
        "RABBIT-SESSION-TXN-BEGIN",
        "RABBIT-SESSION-TXN-COMPLETE",
    ):
        assert word in session
    for word in (
        "RROUTER-ENTRY-BYTES",
        "RROUTER-INIT",
        "RROUTER-ADD",
        "RROUTER-SEAL",
        "RROUTER-MATCH",
        "RROUTER-OWNED-SPAN-OVERLAP?",
        "RROUTER-RESET",
        "RROUTER-FINI",
    ):
        assert word in router
    for word in (
        "RCONN-TXQ-INIT",
        "RCONN-TXQ-FINI",
        "RABBIT-CONNECTION-INIT",
        "RABBIT-CONNECTION-OPEN",
        "RABBIT-CONNECTION-ENQUEUE-RESERVED",
        "RABBIT-CONNECTION-ENQUEUE",
        "RABBIT-CONNECTION-PUMP",
        "RABBIT-CONNECTION-RX-LOAN",
        "RABBIT-CONNECTION-RX-COMMIT",
        "RABBIT-CONNECTION-RX-DROP",
        "RABBIT-CONNECTION-OWNED-SPAN-OVERLAP?",
        "RABBIT-CONNECTION-OWNED-GRAPHS-DISJOINT?",
        "RABBIT-CONNECTION-BUILDER-OVERLAP?",
        "RABBIT-CONNECTION-WIRE-EVIDENCE@",
        "RABBIT-CONNECTION-CLOSE",
        "RABBIT-CONNECTION-CANCEL",
        "RABBIT-CONNECTION-FINI",
    ):
        assert word in connection
    for word in (
        "RABBIT-CLIENT-INIT",
        "RABBIT-CLIENT-OPEN",
        "RABBIT-CLIENT-APP-LANE-ENSURE",
        "RABBIT-CLIENT-HELLO",
        "RABBIT-CLIENT-REQUEST",
        "RABBIT-CLIENT-OP-MATCH?",
        "RABBIT-CLIENT-BURROW-ID$",
        "RABBIT-CLIENT-OP-STATE@",
        "RABBIT-CLIENT-OP-STATUS@",
        "RABBIT-CLIENT-OP-RESPONSE-CODE@",
        "RABBIT-CLIENT-OP-RESULT@",
        "RABBIT-CLIENT-OP-REQUIRED@",
        "RABBIT-CLIENT-OP-CANCEL",
        "RABBIT-CLIENT-OP-RELEASE",
        "RABBIT-CLIENT-OWNED-SPAN-OVERLAP?",
        "RABBIT-CLIENT-CONTROL",
        "RABBIT-CLIENT-DISPATCH",
        "RABBIT-CLIENT-POLL",
        "RABBIT-CLIENT-CLOSE",
        "RABBIT-CLIENT-CANCEL",
        "RABBIT-CLIENT-FINI",
    ):
        assert word in client
    for word in (
        "RABBIT-SUBSCRIPTION-ENTRY-BYTES",
        "RABBIT-SUBSCRIPTIONS-INIT",
        "RABBIT-SUBSCRIPTIONS-ADD",
        "RABBIT-SUBSCRIPTION-FIND",
        "RABBIT-SUBSCRIPTION-BIND",
        "RABBIT-SUBSCRIPTION-BIND-RESULT@",
        "RABBIT-SUBSCRIPTION-BIND-RESOLVE",
        "RABBIT-SUBSCRIPTION-LAST-OBSERVED-EVENT-SEQ@",
        "RABBIT-SUBSCRIPTIONS-DISPATCH",
        "RABBIT-SUBSCRIPTIONS-POLL",
        "RABBIT-SUBSCRIPTIONS-DISCONNECT",
        "RABBIT-SUBSCRIPTIONS-ATTACH",
        "RABBIT-SUBSCRIPTIONS-BINDING-VALID?",
        "RABBIT-SUBSCRIPTION-RELEASE",
        "RABBIT-SUBSCRIPTIONS-FINI",
    ):
        assert word in subscription
    for word in (
        "RABBIT-SERVER-SIZE",
        "RABBIT-SERVER-VALID?",
        "RABBIT-SERVER-INIT",
        "RABBIT-SERVER-STATE@",
        "RABBIT-SERVER-LAST-STATUS@",
        "RABBIT-SERVER-DETAIL@",
        "RABBIT-SERVER-BURROW-ID$",
        "RABBIT-SERVER-PEER@",
        "RABBIT-SERVER-LAST-RESPONSE-CODE@",
        "RABBIT-SERVER-OWNED-SPAN-OVERLAP?",
        "RABBIT-SERVER-OWNED-GRAPHS-DISJOINT?",
        "RABBIT-SERVER-GRAPH-SPAN-OVERLAP?",
        "RABBIT-SERVER-OPEN",
        "RABBIT-SERVER-DISPATCH",
        "RABBIT-SERVER-POLL",
        "RABBIT-SERVER-CLOSE",
        "RABBIT-SERVER-CLOSE-POLL",
        "RABBIT-SERVER-CANCEL",
        "RABBIT-SERVER-NEXT-EVENT-LANE-SEQ@",
        "RABBIT-SERVER-HELD-APP-LANE-ENSURE",
        "RABBIT-SERVER-EVENT",
        "RABBIT-SERVER-FINI",
    ):
        assert word in server
    for word in (
        "RABBIT-SERVER-SUBSCRIPTIONS-SIZE",
        "RABBIT-SERVER-SUBSCRIPTION-ENTRY-SIZE",
        "RABBIT-SERVER-SUBSCRIPTION-CAPACITY-VALID?",
        "RABBIT-SERVER-SUBSCRIPTION-ENTRY-BYTES",
        "RABBIT-SERVER-SUBSCRIPTIONS-VALID?",
        "RABBIT-SERVER-SUBSCRIPTIONS-OWNED-SPAN-OVERLAP?",
        "RABBIT-SERVER-SUBSCRIPTIONS-OWNED-GRAPHS-DISJOINT?",
        "RABBIT-SERVER-SUBSCRIPTIONS-GRAPH-SPAN-OVERLAP?",
        "RABBIT-SERVER-SUBSCRIPTIONS-INIT",
        "RABBIT-SERVER-SUBSCRIPTIONS-COUNT@",
        "RABBIT-SERVER-SUBSCRIPTIONS-LAST-STATUS@",
        "RABBIT-SERVER-SUBSCRIPTIONS-DETAIL@",
        "RABBIT-SERVER-SUBSCRIPTION-FIND",
        "RABBIT-SERVER-SUBSCRIPTION-TARGET$",
        "RABBIT-SERVER-SUBSCRIPTION-LANE@",
        "RABBIT-SERVER-SUBSCRIPTION-CURSOR@",
        "RABBIT-SERVER-SUBSCRIPTION-LAST-LANE-SEQ@",
        "RABBIT-SERVER-SUBSCRIPTIONS-ROUTE",
        "RABBIT-SERVER-SUBSCRIPTIONS-DISPATCH",
        "RABBIT-SERVER-SUBSCRIPTIONS-POLL",
        "RABBIT-SERVER-SUBSCRIPTIONS-SERVICE",
        "RABBIT-SERVER-SUBSCRIPTIONS-RESET",
        "RABBIT-SERVER-SUBSCRIPTIONS-OPEN",
        "RABBIT-SERVER-SUBSCRIPTIONS-CLOSE",
        "RABBIT-SERVER-SUBSCRIPTIONS-CLOSE-POLL",
        "RABBIT-SERVER-SUBSCRIPTIONS-CANCEL",
        "RABBIT-SERVER-SUBSCRIPTIONS-FINI",
    ):
        assert word in server_subscription
    for word in (
        "STREAMS-RABBIT-CONNECTOR-SIZE",
        "STREAMS-RABBIT-CONNECTOR-VALID?",
        "STREAMS-RABBIT-CONNECTOR-INIT",
        "STREAMS-RABBIT-CONNECTOR-STATE@",
        "STREAMS-RABBIT-CONNECTOR-LAST-STATUS@",
        "STREAMS-RABBIT-CONNECTOR-DETAIL@",
        "STREAMS-RABBIT-CONNECTOR-LAST-ACTIVITY@",
        "STREAMS-RABBIT-CONNECTOR-POLL-COUNT@",
        "STREAMS-RABBIT-CONNECTOR-RECONNECT-COUNT@",
        "STREAMS-RABBIT-CONNECTOR-ATTACHMENT-GENERATION@",
        "STREAMS-RABBIT-CONNECTOR-POLL",
        "STREAMS-RABBIT-CONNECTOR-HELLO",
        "STREAMS-RABBIT-CONNECTOR-LANE-ENSURE",
        "STREAMS-RABBIT-CONNECTOR-REQUEST",
        "STREAMS-RABBIT-CONNECTOR-OP-RESULT@",
        "STREAMS-RABBIT-CONNECTOR-OP-REQUIRED@",
        "STREAMS-RABBIT-CONNECTOR-OP-RELEASE",
        "STREAMS-RABBIT-CONNECTOR-SUBSCRIPTION-BIND",
        "STREAMS-RABBIT-CONNECTOR-SUBSCRIPTION-BIND-RESOLVE",
        "STREAMS-RABBIT-CONNECTOR-CONTROL",
        "STREAMS-RABBIT-CONNECTOR-DETACH",
        "STREAMS-RABBIT-CONNECTOR-ATTACH",
        "STREAMS-RABBIT-CONNECTOR-FINI",
    ):
        assert word in streams_connector
    for word in (
        "NMD-ENDPOINT-INIT",
        "NMD-PAIR",
        "NMD-BIND",
        "NMD-PAIR-FINI",
        "NET-IO-PORT-SIZE",
    ):
        assert word in memory

    production_requires = (
        *_requires(PROFILE),
        *_requires(FRAME),
        *_requires(MESSAGE),
        *_requires(BUILDER),
        *_requires(SESSION),
        *_requires(CONNECTION),
        *_requires(CLIENT),
        *_requires(SUBSCRIPTION),
        *_requires(ROUTER),
        *_requires(SERVER),
        *_requires(SERVER_SUBSCRIPTION),
        *_requires(MEMORY),
    )
    for forbidden in (
        "streams",
        "worlds",
        "desk",
        "library",
        "tui/",
        "tls",
        "socket",
        "networking.f",
    ):
        assert all(forbidden not in item.lower() for item in production_requires)

    for phrase in (
        "c79f25697868645d958d2a43aec1c2e4f566585a",
        "Streams will operate configured Rabbit instances",
        "does not own generic Rabbit pumping",
        "generic one-peer server owner",
        "stronger nonzero data requirement",
        "RSERVER-S-NOT-FOUND",
        "Backpressure therefore cannot repeat application work",
        "Server-side EVENT publication",
        "no second Rabbit transport abstraction",
        "two distinct zero counters",
        "Event-Seq",
        "exact `(Lane, Txn)` pair",
        "TLS 1.3 server accept",
        "supplies no confidentiality",
        "Rabbit refinement",
        "Reference mismatches intentionally not copied",
    ):
        assert phrase in doc

    fixture_contracts = (
        fixture
        + "\n"
        + client_fixture
        + "\n"
        + client_journey
        + "\n"
        + subscription_fixture
        + "\n"
        + server_fixture
        + "\n"
        + server_subscription_fixture
        + "\n"
        + capstone_fixture
        + "\n"
        + streams_connector_fixture
    )
    for marker in (
        "_RBT-TEST-ENCODE",
        "_RBT-TEST-PARSE",
        "_RBT-TEST-REJECTIONS",
        "_RBT-TEST-MESSAGE",
        "_RBT-TEST-BUILDER-LIFECYCLE",
        "_RBT-TEST-BUILDER-FAILURES",
        "_RBT-TEST-BUILDER-TYPED-CONTROL",
        "_RBT-TEST-MEMORY-DUPLEX",
        "_RBT-TEST-SESSION",
        "_RBT-TEST-CONNECTION",
        "_RBT-CLI-PHASE-RESPONSES-GENERATION",
        "_RBT-TEST-ROUTER",
        "_RBT-SRV-PHASE-FETCH",
        "_RBT-SRV-PHASE-HANDLER-FAILURES",
        "_RBT-SRV-PHASE-EXTENSION-LANE-ZERO",
        "_RBT-SRV-PHASE-BACKPRESSURE",
        "_RBT-SRV-PHASE-ADMISSION-DENY",
        "_RBT-SSRV-PHASE-OWNER-INIT",
        "_RBT-SSRV-PHASE-HANDSHAKE",
        "_RBT-SSRV-PHASE-BIND-SINCE",
        "_RBT-SSRV-PHASE-NO-CREDIT",
        "_RBT-SSRV-PHASE-EVENTS-RETAINED",
        "_RBT-SSRV-PHASE-EVENT14-RESERVE",
        "_RBT-SSRV-PHASE-EVENT14-RETRY",
        "_RBT-SSRV-PHASE-FINI",
        "_RBT-CAP-PHASE-GRAPHS-INIT",
        "_RBT-CAP-PHASE-BUILDER-CONNECTION-GEOMETRY",
        "_RBT-CAP-PHASE-SERVER-GEOMETRY",
        "_RBT-CAP-PHASE-SUBSCRIPTION-GEOMETRY",
        "_RBT-CAP-PHASE-HANDSHAKES",
        "_RBT-CAP-PHASE-DISCOVERY",
        "_RBT-CAP-PHASE-BIND-BOTH",
        "_RBT-CAP-PHASE-ACTIONS",
        "_RBT-CAP-PHASE-ACTIONS-COMPLETE",
        "_RBT-CAP-PHASE-POST-ACTION-FETCH",
        "_RBT-CAP-PHASE-INDEPENDENT-PRESSURE",
        "_RBT-CAP-PHASE-B-SATURATES",
        "_RBT-CAP-PHASE-A-CONTINUES",
        "_RBT-CAP-PHASE-B-DISCONNECT",
        "_RBT-CAP-PHASE-B-REBUILD-REBIND",
        "_RBT-CAP-PHASE-B-EXACT-SUFFIX",
        "_RBT-CAP-PHASE-FINI",
        "_RBT-RCONN-PHASE-INIT",
        "_RBT-RCONN-PHASE-DETACH",
        "_RBT-RCONN-PHASE-ATTACH",
        "_RBT-RCONN-PHASE-FINI",
        "RBF-EOF",
    ):
        assert marker in fixture_contracts

    for path, source in (
        (PROFILE, profile),
        (FRAME, frame),
        (MESSAGE, message),
        (BUILDER, builder),
        (SESSION, session),
        (CONNECTION, connection),
        (CLIENT, client),
        (SUBSCRIPTION, subscription),
        (ROUTER, router),
        (SERVER, server),
        (SERVER_SUBSCRIPTION, server_subscription),
        (STREAMS_CONNECTOR, streams_connector),
        (MEMORY, memory),
        (FIXTURE, fixture),
        (CLIENT_FIXTURE, client_fixture),
        (CLIENT_JOURNEY, client_journey),
        (SUBSCRIPTION_FIXTURE, subscription_fixture),
        (SERVER_FIXTURE, server_fixture),
        (SERVER_SUBSCRIPTION_FIXTURE, server_subscription_fixture),
        (CAPSTONE_FIXTURE, capstone_fixture),
        (STREAMS_CONNECTOR_FIXTURE, streams_connector_fixture),
    ):
        _assert_physical_comments(path, source)


def _run_rabbit_core(timeout: float) -> int:
    sys.path.insert(0, str(LOCAL_TESTING))
    import akashic_tui as harness

    autoexec = [
        "\\ autoexec.f - staged Rabbit foundation contracts\n",
        "ENTER-USERLAND\n",
    ]
    for stage_name, module, marker in LOAD_STAGES:
        autoexec.extend(
            (
                f"REQUIRE {module}\n",
                (
                    'DEPTH IF ." RABBIT LOAD STACK FAIL '
                    f'{stage_name}" CR TX-FLUSH THEN\n'
                ),
                f'." {marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker, announce in CONTRACT_STAGES:
        autoexec.append(f"{word}\n")
        if announce:
            autoexec.append(f'." {marker}" CR\n')
        autoexec.append("TX-FLUSH\nKEY DROP\n")
    autoexec.append('." RABBIT CORE PASS " _RBT-CHECKS @ . CR\nTX-FLUSH\n')

    profile_name = "rabbit-streams-worlds-core"
    image = Path("/tmp/akashic-rabbit-streams-worlds-core.img")
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
            "tui/applets/streams/rabbit-connector.f",
        ),
        resources=(),
        autoexec="".join(autoexec),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            "RABBIT CORE FAIL",
            "RABBIT CORE ASSERT",
            "RABBIT CORE STACK",
            "RABBIT LOAD STACK FAIL",
            "DRIVER THROW",
            "dictionary full",
            "exception",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=(
            (
                "local_testing/rabbit-core-test.f",
                harness._minify_forth(
                    FIXTURE.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/rabbit-client-test.f",
                harness._minify_forth(
                    CLIENT_FIXTURE.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/rabbit-client-flow.f",
                harness._minify_forth(
                    CLIENT_JOURNEY.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/rabbit-sub-test.f",
                harness._minify_forth(
                    SUBSCRIPTION_FIXTURE.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/rabbit-server-test.f",
                harness._minify_forth(
                    SERVER_FIXTURE.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/rabbit-servsub-test.f",
                harness._minify_forth(
                    SERVER_SUBSCRIPTION_FIXTURE.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/rabbit-cap-test.f",
                harness._minify_forth(
                    CAPSTONE_FIXTURE.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
            (
                "local_testing/rabbit-connector-test.f",
                harness._minify_forth(
                    STREAMS_CONNECTOR_FIXTURE.read_text(encoding="utf-8")
                ).encode("utf-8"),
            ),
        ),
        linked=False,
        include_large_sample=False,
        total_sectors=2048,
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
            print(f"Rabbit load {stage_name}: starting", flush=True)
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
            reports.append((stage_name, report))
            if marker not in raw or failures:
                print(f"Rabbit load {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                if len(raw) > 8000:
                    print(raw[:4000])
                    print("\n... Rabbit trace middle omitted ...\n")
                print(raw[-4000:])
                print(machine.screen_text())
                return 1

        contract_reports = []
        for stage_name, _, marker, _ in CONTRACT_STAGES:
            print(f"Rabbit contract {stage_name}: starting", flush=True)
            machine.clear_output()
            machine.send_text("x")
            stage_report = machine.run(
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
            contract_reports.append((stage_name, stage_report))
            if marker not in raw or failures:
                print(f"Rabbit contract {stage_name}: FAIL")
                print(
                    f"  {stage_report.steps:,} steps in "
                    f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                if len(raw) > 8000:
                    print(raw[:4000])
                    print("\n... Rabbit trace middle omitted ...\n")
                print(raw[-4000:])
                print(machine.screen_text())
                return 1

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
        pass_match = re.search(r"RABBIT CORE PASS[ \t]+([0-9]+)", raw)
        ok = pass_match is not None and not failures
        check_summary = (
            f" ({pass_match.group(1)} checks)" if pass_match is not None else ""
        )
        print(
            f"Rabbit core lifecycle: {'PASS' if ok else 'FAIL'}"
            f"{check_summary}"
        )
        for stage_name, stage_report in reports:
            print(
                f"  {stage_name}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        for stage_name, stage_report in contract_reports:
            print(
                f"  contract {stage_name}: {stage_report.steps:,} steps in "
                f"{stage_report.elapsed_s:.2f}s; stop={stage_report.reason}"
            )
        print(
            f"  contracts: {report.steps:,} steps in "
            f"{report.elapsed_s:.2f}s; stop={report.reason}"
        )
        if not ok:
            for failure in failures:
                print(f"  {failure}")
            if len(raw) > 8000:
                print(raw[:4000])
                print("\n... Rabbit trace middle omitted ...\n")
            print(raw[-4000:])
            print(machine.screen_text())
            return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--rabbit-core", action="store_true")
    parser.add_argument("--timeout", type=float, default=90.0)
    args = parser.parse_args()

    _assert_static_contracts()
    if args.static_only:
        print("RABBIT STREAMS WORLDS STATIC PASS")
        return 0
    return _run_rabbit_core(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
