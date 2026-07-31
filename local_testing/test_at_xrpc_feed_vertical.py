#!/usr/bin/env python3
"""Qualify the authenticated PDS feed-to-Streams vertical slice."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
ROOT = LOCAL_TESTING.parent
SOURCE_ROOT = ROOT / "akashic"
sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
import test_at_xrpc_auth_read as auth_read  # noqa: E402
from forth_dependencies import dependency_order  # noqa: E402
from test_oauth2_p256_key import P256_JWK_DOUBLES  # noqa: E402


PROFILE = "at-xrpc-feed-vertical"
IMAGE = Path("/tmp/akashic-at-xrpc-feed-vertical.img")
PASS_MARKER = "AT XRPC FEED VERTICAL PASS"
MAX_PHASE_STEPS = 180_000_000
EXT_MEM_SIZE = 128 << 20
NUM_CORES = 1

FEED_TARGET = SOURCE_ROOT / "atproto" / "get-author-feed.f"
FEED_CONNECTOR = (
    SOURCE_ROOT
    / "tui"
    / "applets"
    / "streams"
    / "atproto-author-feed-connector.f"
)
CONTRACT = LOCAL_TESTING / "at-xrpc-feed-vertical.f"
TIMELINE = LOCAL_TESTING / "fixtures" / "atproto" / "timeline.json"
TIMELINE_GUEST = "atfv-feed.json"

REPLACED_CRYPTO_MODULES = auth_read.REPLACED_CRYPTO_MODULES
REPLACED_TRANSPORT_MODULES = frozenset({"net/transports/kdos-tls.f"})
TRANSPORT_DOUBLE = """
PROVIDED akashic-kdos-tls
0 CONSTANT KDOSTLS-STATE-CLOSED
0 CONSTANT KDOSTLS-E-OK
0 CONSTANT _ATFVT-KDOS-STATE
8 CONSTANT _ATFVT-KDOS-PORT
_ATFVT-KDOS-PORT NET-IO-PORT-SIZE + CONSTANT KDOSTLS-SIZE
: KDOSTLS.STATE  ( adapter -- field )
    _ATFVT-KDOS-STATE + ;
: KDOSTLS.PORT  ( adapter -- port )
    _ATFVT-KDOS-PORT + ;
: KDOSTLS-INIT  ( adapter -- )
    DUP KDOSTLS-SIZE 0 FILL
    DUP KDOSTLS.PORT NIO-INIT
    KDOSTLS-STATE-CLOSED SWAP KDOSTLS.STATE ! ;
: KDOSTLS-CONFIGURE  ( host-a host-u remote-port adapter -- status )
    2DROP 2DROP KDOSTLS-E-OK ;
"""

RAW_MODULES = dependency_order(
    SOURCE_ROOT,
    (
        "tui/applets/streams/atproto-author-feed-connector.f",
        "utils/fs/vfs.f",
    ),
)


def _module_items() -> tuple[auth_read.LoadItem, ...]:
    items: list[auth_read.LoadItem] = []
    sequence = 0
    crypto_seam_inserted = False
    transport_seam_inserted = False
    for module in RAW_MODULES:
        if module in REPLACED_CRYPTO_MODULES:
            continue
        if module in REPLACED_TRANSPORT_MODULES:
            items.append(
                auth_read.LoadItem(
                    name="deterministic-transport-seam",
                    guest="local_testing/atfv-net.f",
                    marker="AT XRPC FEED TRANSPORT SEAM READY",
                    inline=TRANSPORT_DOUBLE,
                    remove_requires=False,
                )
            )
            transport_seam_inserted = True
            continue
        if module == "security/oauth2/key-p256.f":
            items.append(
                auth_read.LoadItem(
                    name="deterministic-crypto-seam",
                    guest="local_testing/atfv-seam.f",
                    marker="AT XRPC FEED CRYPTO READY",
                    inline=P256_JWK_DOUBLES,
                    remove_requires=False,
                )
            )
            crypto_seam_inserted = True
        sequence += 1
        items.append(
            auth_read.LoadItem(
                name=f"module-{sequence:02d}",
                guest=f"local_testing/atfv-m{sequence:02d}.f",
                marker=f"AT XRPC FEED MODULE {sequence:02d} READY",
                source=SOURCE_ROOT / module,
            )
        )
    assert crypto_seam_inserted
    assert transport_seam_inserted
    return tuple(items)


MODULE_ITEMS = _module_items()
FIXTURE_ITEMS = (
    auth_read.LoadItem(
        name="profile-fixture",
        guest="local_testing/atfv-prof.f",
        marker="AT XRPC FEED PROFILE READY",
        source=auth_read.PROFILE_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="client-fixture",
        guest="local_testing/atfv-client.f",
        marker="AT XRPC FEED CLIENT READY",
        source=auth_read.CLIENT_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="durable-session-fixture",
        guest="local_testing/atfv-auth.f",
        marker="AT XRPC FEED SESSION FIXTURE READY",
        source=auth_read.CONTRACT,
    ),
    auth_read.LoadItem(
        name="feed-vertical-fixture",
        guest="local_testing/atfv-test.f",
        marker="AT XRPC FEED FIXTURE READY",
        source=CONTRACT,
    ),
)

RUNTIME_STAGES = (
    ("fixture-load", "_ATFV-LOAD", "AT XRPC FEED DOCUMENT READY"),
    ("setup", "_ATXR-SETUP", "AT XRPC FEED SETUP READY"),
    ("provision", "_ATXR-PROVISION", "AT XRPC FEED KEY READY"),
    ("install", "_ATXR-INSTALL", "AT XRPC FEED SESSION READY"),
    ("owner-restart", "_ATXR-RESTART", "AT XRPC FEED REOPEN READY"),
    ("vertical", "_ATFV-QUALIFY", "AT XRPC FEED FLOW READY"),
    ("finish", "_ATFV-FINISH", PASS_MARKER),
)

FAILURE_MARKERS = (
    *auth_read.FAILURE_MARKERS,
    "AT XRPC FEED ASSERT",
    "AT XRPC FEED STATUS",
    "AT XRPC FEED STACK",
    "AT XRPC FEED LOAD STACK FAIL",
)


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _assert_static() -> None:
    target = FEED_TARGET.read_text(encoding="utf-8")
    connector = FEED_CONNECTOR.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")
    timeline = TIMELINE.read_bytes()

    assert "atproto/get-author-feed.f" in RAW_MODULES
    assert "atproto/xrpc-exchange.f" in RAW_MODULES
    assert (
        "tui/applets/streams/atproto-author-feed-connector.f"
        in RAW_MODULES
    )
    assert REPLACED_CRYPTO_MODULES < set(RAW_MODULES)
    assert 0 < MAX_PHASE_STEPS <= 180_000_000
    assert EXT_MEM_SIZE == 128 << 20
    assert NUM_CORES == 1

    for marker in (
        "PROVIDED akashic-at-getauthfeed",
        "AT-GET-AUTHOR-FEED-TARGET!",
        "AT-GET-AUTHOR-FEED-WORKSPACE-SIZE",
        "AT-GET-AUTHOR-FEED-FILTER-POSTS-WITH-REPLIES",
    ):
        assert marker in target

    for marker in (
        "PROVIDED akashic-streams-atfeed",
        "AT-AUTHOR-FEED-CONNECTOR-INIT",
        "AT-AUTHOR-FEED-CONNECTOR-BIND",
        "AT-AUTHOR-FEED-CONNECTOR-PREPARE",
        "AT-AUTHOR-FEED-CONNECTOR-PUBLISH",
        "AT-AUTHOR-FEED-CONNECTOR-XIO-WIPE",
        "BFM-DECODE-FEED",
        "STREAMS-FLOW-SEAL-INGRESS",
        "STREAMS-FLOW-ADMIT",
    ):
        assert marker in connector

    assert _requires(CONTRACT) == ["at-xrpc-auth-read-test.f"]
    for marker in (
        "_ATFV-LOAD",
        "_ATFV-QUALIFY",
        "_ATFV-FINISH",
        "HTTP/1.1 400 Bad Request",
        "use_dpop_nonce",
        "pds-nonce-1",
        "pds-nonce-2",
        "did:web:api.bsky.app#bsky_appview",
        "app.bsky.feed.getAuthorFeed",
        "AT-AUTHOR-FEED-CONNECTOR-PUBLISH",
        "STREAMS-RUNTIME-PROFILE-COMPACT",
    ):
        assert marker in fixture

    assert timeline
    assert b'"cursor": "page-2-token"' in timeline
    assert timeline.count(b'"post": {') == 2
    assert b"Injected fixtures make network behavior reviewable." in timeline
    assert TIMELINE_GUEST.encode("ascii") in fixture.encode("utf-8")

    all_items = (*MODULE_ITEMS, *FIXTURE_ITEMS)
    assert len({item.name for item in all_items}) == len(all_items)
    assert len({item.marker for item in all_items}) == len(all_items)
    for item in all_items:
        assert len(Path(item.guest).name.encode("utf-8")) <= 23
        assert (item.source is None) != (item.inline is None)
    assert len(Path(TIMELINE_GUEST).name.encode("utf-8")) <= 23

    for path in (
        *(item.source for item in all_items if item.source),
        FEED_TARGET,
        FEED_CONNECTOR,
        CONTRACT,
    ):
        auth_read._assert_physical_comments(  # noqa: SLF001
            path,
            path.read_text(encoding="utf-8"),
        )


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    return (
        (TIMELINE_GUEST, TIMELINE.read_bytes()),
        *(
            (item.guest, auth_read._load_bytes(item))  # noqa: SLF001
            for item in (*MODULE_ITEMS, *FIXTURE_ITEMS)
        ),
    )


def _autoexec() -> str:
    lines = [
        "\\ autoexec.f - authenticated PDS feed to Streams vertical\n",
        "ENTER-USERLAND\n",
    ]
    for item in (*MODULE_ITEMS, *FIXTURE_ITEMS):
        lines.extend(
            (
                f"REQUIRE {item.guest}\n",
                (
                    'DEPTH IF ." AT XRPC FEED LOAD STACK FAIL '
                    f'{item.name}" CR TX-FLUSH THEN\n'
                ),
                f'." {item.marker}" CR TX-FLUSH\n',
                "KEY DROP\n",
            )
        )
    for _, word, marker in RUNTIME_STAGES:
        lines.append(f"{word}\n")
        if marker == PASS_MARKER:
            lines.append(f'." {marker}" CR TX-FLUSH\n')
        else:
            lines.extend((f'." {marker}" CR TX-FLUSH\n', "KEY DROP\n"))
    return "".join(lines)


def _run_vertical(timeout: float) -> int:
    harness.PROFILES[PROFILE] = harness.Profile(
        roots=(),
        resources=(),
        autoexec=_autoexec(),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=FAILURE_MARKERS,
        initial_files=_initial_files(),
        linked=False,
        include_large_sample=False,
        total_sectors=8192,
    )
    image_path = harness.build_image(PROFILE, IMAGE)
    profile = harness.PROFILES[PROFILE]
    stages = (
        *(
            (item.name, item.marker)
            for item in (*MODULE_ITEMS, *FIXTURE_ITEMS)
        ),
        *((name, marker) for name, _, marker in RUNTIME_STAGES),
    )

    with harness.MachineSession.from_bios(
        harness.MEGAPAD_ROOT / "bios.asm",
        storage_image=image_path,
        cols=120,
        rows=44,
        batch_steps=500_000,
        ext_mem_size=EXT_MEM_SIZE,
        num_cores=NUM_CORES,
    ) as machine:
        machine.boot()
        for index, (stage_name, marker) in enumerate(stages):
            if index:
                machine.clear_output()
                machine.send_text("x")
            report = machine.run(
                max_steps=MAX_PHASE_STEPS,
                wall_timeout_s=timeout,
                until_text=marker,
                text_scope="raw",
            )
            raw_text = machine.raw_text()
            failures = tuple(
                dict.fromkeys(
                    (
                        *harness._has_forth_error(raw_text),  # noqa: SLF001
                        *harness._matched_failure_markers(  # noqa: SLF001
                            profile,
                            raw_text,
                            machine.screen_text(),
                        ),
                    )
                )
            )
            if marker not in raw_text or failures:
                print(f"AT XRPC FEED {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-5000:])
                return 1
            print(
                f"AT XRPC FEED {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("AT XRPC FEED vertical: PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--static-only", action="store_true")
    mode.add_argument("--vertical", action="store_true")
    parser.add_argument("--timeout", type=float, default=180.0)
    args = parser.parse_args()

    _assert_static()
    if args.static_only:
        print("AT XRPC FEED STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
