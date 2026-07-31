#!/usr/bin/env python3
"""Qualify the production authenticated XRPC exchange and getSession gate."""

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


PROFILE = "at-xrpc-exchange"
IMAGE = Path("/tmp/akashic-at-xrpc-exchange.img")
PASS_MARKER = "AT XRPC EXCHANGE PASS"
MAX_PHASE_STEPS = 180_000_000
EXT_MEM_SIZE = 128 << 20
NUM_CORES = 1

EXCHANGE = SOURCE_ROOT / "atproto" / "xrpc-exchange.f"
GETSESSION = SOURCE_ROOT / "atproto" / "get-session-response.f"
CONTRACT = LOCAL_TESTING / "at-xrpc-exchange-test.f"

REPLACED_CRYPTO_MODULES = auth_read.REPLACED_CRYPTO_MODULES
REPLACED_TRANSPORT_MODULES = frozenset({"net/transports/kdos-tls.f"})
TRANSPORT_DOUBLE = """
PROVIDED akashic-kdos-tls
0 CONSTANT KDOSTLS-STATE-CLOSED
0 CONSTANT KDOSTLS-E-OK
0 CONSTANT _ATXET-KDOS-STATE
8 CONSTANT _ATXET-KDOS-PORT
_ATXET-KDOS-PORT NET-IO-PORT-SIZE + CONSTANT KDOSTLS-SIZE
: KDOSTLS.STATE  ( adapter -- field )
    _ATXET-KDOS-STATE + ;
: KDOSTLS.PORT  ( adapter -- port )
    _ATXET-KDOS-PORT + ;
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
        "atproto/xrpc-exchange.f",
        "atproto/get-session-response.f",
        "utils/fs/vfs.f",
    ),
)


def _module_items() -> tuple[auth_read.LoadItem, ...]:
    items: list[auth_read.LoadItem] = []
    sequence = 0
    seam_inserted = False
    transport_seam_inserted = False
    for module in RAW_MODULES:
        if module in REPLACED_CRYPTO_MODULES:
            continue
        if module in REPLACED_TRANSPORT_MODULES:
            sequence += 1
            items.append(
                auth_read.LoadItem(
                    name="deterministic-transport-seam",
                    guest="local_testing/xe-netseam.f",
                    marker="AT XRPC EXCHANGE TRANSPORT SEAM READY",
                    inline=TRANSPORT_DOUBLE,
                    remove_requires=False,
                )
            )
            transport_seam_inserted = True
            continue
        if module == "security/oauth2/key-p256.f":
            sequence += 1
            items.append(
                auth_read.LoadItem(
                    name="deterministic-crypto-seam",
                    guest="local_testing/xe-seam.f",
                    marker="AT XRPC EXCHANGE CRYPTO READY",
                    inline=P256_JWK_DOUBLES,
                    remove_requires=False,
                )
            )
            seam_inserted = True
        sequence += 1
        items.append(
            auth_read.LoadItem(
                name=f"module-{sequence:02d}",
                guest=f"local_testing/xe-m{sequence:02d}.f",
                marker=f"AT XRPC EXCHANGE MODULE {sequence:02d} READY",
                source=SOURCE_ROOT / module,
            )
        )
    assert seam_inserted
    assert transport_seam_inserted
    return tuple(items)


MODULE_ITEMS = _module_items()
FIXTURE_ITEMS = (
    auth_read.LoadItem(
        name="profile-fixture",
        guest="local_testing/xe-prof.f",
        marker="AT XRPC EXCHANGE PROFILE READY",
        source=auth_read.PROFILE_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="client-fixture",
        guest="local_testing/xe-client.f",
        marker="AT XRPC EXCHANGE CLIENT READY",
        source=auth_read.CLIENT_FIXTURE,
        remove_requires=False,
    ),
    auth_read.LoadItem(
        name="durable-session-fixture",
        guest="local_testing/xe-auth.f",
        marker="AT XRPC EXCHANGE SESSION FIXTURE READY",
        source=auth_read.CONTRACT,
    ),
    auth_read.LoadItem(
        name="exchange-fixture",
        guest="local_testing/xe-fixture.f",
        marker="AT XRPC EXCHANGE FIXTURE READY",
        source=CONTRACT,
    ),
)

RUNTIME_STAGES = (
    ("setup", "_ATXR-SETUP", "AT XRPC EXCHANGE SETUP READY"),
    ("provision", "_ATXR-PROVISION", "AT XRPC EXCHANGE KEY READY"),
    ("install", "_ATXR-INSTALL", "AT XRPC EXCHANGE SESSION READY"),
    ("owner-restart", "_ATXR-RESTART", "AT XRPC EXCHANGE REOPEN READY"),
    ("exchange", "_ATXET-QUALIFY", "AT XRPC EXCHANGE VERTICAL READY"),
    ("finish", "_ATXET-FINISH", PASS_MARKER),
)

FAILURE_MARKERS = (
    "AT XRPC AUTH READ FAIL",
    "AT XRPC AUTH READ ASSERT",
    "AT XRPC AUTH READ STATUS",
    "AT XRPC AUTH READ STACK",
    "AT XRPC LOAD STACK FAIL",
    "AT XRPC EXCHANGE LOAD STACK FAIL",
    "AT OAUTH PROFILE ASSERT",
    "AT OAUTH CLIENT ASSERT",
    "DRIVER THROW",
    "Branch offset overflow",
    "dictionary full",
    "exception",
    "Module not found",
    "Path component not found",
    "? (not found)",
)


def _requires(path: Path) -> list[str]:
    return re.findall(
        r"(?mi)^[ \t]*REQUIRE[ \t]+(\S+)",
        path.read_text(encoding="utf-8"),
    )


def _assert_static() -> None:
    exchange = EXCHANGE.read_text(encoding="utf-8")
    getsession = GETSESSION.read_text(encoding="utf-8")
    fixture = CONTRACT.read_text(encoding="utf-8")

    assert RAW_MODULES[-2:] == (
        "atproto/xrpc-exchange.f",
        "atproto/get-session-response.f",
    )
    assert "atproto/xrpc-exchange.f" in RAW_MODULES
    assert REPLACED_CRYPTO_MODULES < set(RAW_MODULES)
    assert NUM_CORES == 1
    assert EXT_MEM_SIZE == 128 << 20

    for marker in (
        "PROVIDED akashic-at-xrpc-exch",
        "AT-XRPC-EXCHANGE-INIT",
        "AT-XRPC-EXCHANGE-BIND",
        "AT-XRPC-EXCHANGE-PREPARE",
        "AT-XRPC-AUTH-GET-BUILD",
        "OAUTH2-DPOP-NONCE-REPLACE",
        "OAUTH2-ERROR-RESPONSE-WITH",
        "AT-XRPC-EXCHANGE-XIO-START",
        "AT-XRPC-EXCHANGE-XIO-POLL",
        "HREQ-CLEAR",
    ):
        assert marker in exchange
    assert "HRES-" not in exchange
    assert "PAF-" not in exchange
    assert "STREAMS-" not in exchange

    for marker in (
        "PROVIDED akashic-at-getsession",
        "AT-GETSESSION-ADMIT",
        "JOSE-JSON-OBJECT-PARSE",
        "AT-HANDLE-VALIDATE",
        "DID-VALIDATE",
        "AT-OAUTH-PROFILE-DID@",
    ):
        assert marker in getsession

    assert _requires(CONTRACT) == ["at-xrpc-auth-read-test.f"]
    for marker in (
        "_ATXET-QUALIFY",
        "_ATXET-FINISH",
        "AT-XRPC-EXCHANGE-INIT",
        "AT-XRPC-EXCHANGE-BIND",
        "AT-XRPC-EXCHANGE-PREPARE",
        "AT-GETSESSION-ADMIT",
        "DPoP-Nonce: pds-nonce-1",
        "Authorization: DPoP access-vertical",
    ):
        assert marker in fixture

    all_items = (*MODULE_ITEMS, *FIXTURE_ITEMS)
    assert len({item.name for item in all_items}) == len(all_items)
    assert len({item.marker for item in all_items}) == len(all_items)
    for item in all_items:
        assert len(Path(item.guest).name.encode("utf-8")) <= 23
        assert (item.source is None) != (item.inline is None)
    for path in (
        *(item.source for item in all_items if item.source),
        EXCHANGE,
        GETSESSION,
        CONTRACT,
    ):
        auth_read._assert_physical_comments(  # noqa: SLF001
            path,
            path.read_text(encoding="utf-8"),
        )


def _initial_files() -> tuple[tuple[str, bytes], ...]:
    return tuple(
        (item.guest, auth_read._load_bytes(item))  # noqa: SLF001
        for item in (*MODULE_ITEMS, *FIXTURE_ITEMS)
    )


def _autoexec() -> str:
    lines = ["\\ autoexec.f - authenticated XRPC exchange\n", "ENTER-USERLAND\n"]
    for item in (*MODULE_ITEMS, *FIXTURE_ITEMS):
        lines.extend(
            (
                f"REQUIRE {item.guest}\n",
                (
                    'DEPTH IF ." AT XRPC EXCHANGE LOAD STACK FAIL '
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
                print(f"AT XRPC EXCHANGE {stage_name}: FAIL")
                print(
                    f"  {report.steps:,} steps in {report.elapsed_s:.2f}s; "
                    f"stop={report.reason}"
                )
                for failure in failures:
                    print(f"  {failure}")
                print(raw_text[-5000:])
                return 1
            print(
                f"AT XRPC EXCHANGE {stage_name}: PASS "
                f"({report.steps:,} steps, {report.elapsed_s:.2f}s)",
                flush=True,
            )
    print("AT XRPC EXCHANGE vertical: PASS")
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
        print("AT XRPC EXCHANGE STATIC PASS")
        return 0
    return _run_vertical(args.timeout)


if __name__ == "__main__":
    raise SystemExit(main())
