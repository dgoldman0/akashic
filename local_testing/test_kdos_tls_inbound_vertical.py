#!/usr/bin/env python3
"""Qualify the real inbound KDOS TLS -> NIO -> HCONN composition."""

from __future__ import annotations

import base64
import sys
import tempfile
import time
import unittest
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
GUEST_SOURCE = LOCAL_TESTING / "tls-inbound-vertical.f"
PROFILE_NAME = "kdos-tls-inbound-vertical-qualification"
READY_MARKER = "TLS INBOUND VERTICAL READY"
FIRST_DONE_MARKER = "TLS INBOUND FIRST DONE"
PASS_MARKER = "TLS INBOUND VERTICAL PASS"
FAIL_MARKER = "TLS INBOUND VERTICAL FAIL"

# This qualification owns a new bounded budget; it does not override any
# checked-in MegaPad or Akashic smoke ceiling.  Runs remain single-core and
# advance in short chunks so a guest failure is reported promptly.
RUN_CHUNK_STEPS = 50_000_000
TOTAL_MAX_STEPS = 1_500_000_000
TOTAL_WALL_TIMEOUT_S = 180.0
EXT_MEM_SIZE = 128 << 20

REQUEST = b"GET /probe HTTP/1.1\r\nHost: test.example.com\r\n\r\n"
RESPONSE_BODY = b"Akashic secure transport\n"
EXPECTED_RESPONSE = (
    b"HTTP/1.1 200 OK\r\n"
    b"Content-Type: text/plain\r\n"
    b"Content-Length: 25\r\n"
    b"Connection: close\r\n"
    b"\r\n"
    + RESPONSE_BODY
)

sys.path.insert(0, str(LOCAL_TESTING))

import akashic_tui as harness  # noqa: E402
from kdos_tls_memory_peer import (  # noqa: E402
    KdosTlsMemoryPeer,
    KdosTlsMemoryPeerMux,
)


class _VerticalFailure(RuntimeError):
    """An emulator lifecycle failure that needs full guest diagnostics."""


def _fixture(name: str) -> bytes:
    path = (
        harness.MEGAPAD_ROOT
        / "tests"
        / "fixtures"
        / "tls"
        / f"{name}.der.b64"
    )
    encoded = b"".join(path.read_bytes().split())
    return base64.b64decode(encoded, validate=True)


def _forth_bytes(name: str, data: bytes) -> list[str]:
    lines = [f"CREATE {name}"]
    for offset in range(0, len(data), 16):
        chunk = data[offset : offset + 16]
        lines.append(" ".join(f"{byte} C," for byte in chunk))
    return lines


def _autoexec(leaf: bytes, intermediate: bytes) -> str:
    chain = leaf + intermediate
    lines = [
        "\\ autoexec.f - real inbound KDOS TLS vertical qualification",
        "ENTER-USERLAND",
        *_forth_bytes("_ktiv-chain", chain),
        f"{len(chain)} CONSTANT _KTIV-CHAIN-U",
        *_forth_bytes("_ktiv-key", b"\x03" + bytes(31)),
        "REQUIRE net/transports/kdos-tls-inbound.f",
        "REQUIRE web/http-connection-owner.f",
        "REQUIRE local_testing/tls-inbound-vertical.f",
        "TX-FLUSH",
    ]
    return "\n".join(lines) + "\n"


def _profile(leaf: bytes, intermediate: bytes) -> object:
    return harness.Profile(
        roots=(
            "net/transports/kdos-tls-inbound.f",
            "web/http-connection-owner.f",
        ),
        resources=(),
        autoexec=_autoexec(leaf, intermediate),
        ready_markers=(PASS_MARKER,),
        stable_markers=(PASS_MARKER,),
        failure_markers=(
            FAIL_MARKER,
            "ASSERT ",
            "STACK ",
            "DRIVER THROW",
            "dictionary full",
            "Module not found",
            "Path component not found",
            "? (not found)",
        ),
        initial_files=((
            "local_testing/tls-inbound-vertical.f",
            GUEST_SOURCE.read_bytes(),
        ),),
        linked=False,
        requires_tap=False,
        include_large_sample=False,
    )


def _guest_failures(profile: object, machine: object) -> tuple[str, ...]:
    raw = machine.raw_text()
    return tuple(
        dict.fromkeys(
            (
                *harness._has_forth_error(raw),  # noqa: SLF001
                *harness._matched_failure_markers(  # noqa: SLF001
                    profile,
                    raw,
                    machine.screen_text(),
                ),
            )
        )
    )


def _diagnostics(machine: object, *peers: object) -> str:
    peer_lines = []
    for index, peer in enumerate(peers, start=1):
        peer_lines.append(
            f"peer {index}: state={peer.assertion_state!r}; "
            f"errors={peer.errors!r}"
        )
    return "\n".join(
        (
            *peer_lines,
            "screen:",
            machine.screen_text(),
            "recent raw output:",
            machine.raw_text()[-8000:],
        )
    )


def _run_until(
    machine: object,
    profile: object,
    marker: str,
    *,
    deadline: float,
    steps: list[int],
) -> None:
    while True:
        raw = machine.raw_text()
        failures = _guest_failures(profile, machine)
        if failures:
            raise _VerticalFailure(
                f"guest failed before {marker!r}: {failures!r}"
            )
        if marker in raw:
            return
        if steps[0] >= TOTAL_MAX_STEPS:
            raise _VerticalFailure(
                f"guest did not reach {marker!r} within "
                f"{TOTAL_MAX_STEPS:,} steps"
            )
        remaining_wall = deadline - time.monotonic()
        if remaining_wall <= 0:
            raise _VerticalFailure(
                f"guest did not reach {marker!r} within "
                f"{TOTAL_WALL_TIMEOUT_S:.0f} seconds"
            )
        report = machine.run(
            max_steps=min(
                RUN_CHUNK_STEPS,
                TOTAL_MAX_STEPS - steps[0],
            ),
            wall_timeout_s=min(5.0, remaining_wall),
            until_text=marker,
            text_scope="raw",
            advance_idle=True,
        )
        steps[0] += report.steps
        if report.reason in ("halted", "stalled"):
            raise _VerticalFailure(
                f"guest stopped ({report.reason}) before {marker!r}"
            )


class TestKdosTlsInboundVertical(unittest.TestCase):
    """Drive two independent TLS clients through the production composition."""

    def _assert_peer(
        self,
        machine: object,
        peer: KdosTlsMemoryPeer,
        leaf: bytes,
        *all_peers: KdosTlsMemoryPeer,
    ) -> None:
        diagnostic = _diagnostics(machine, *all_peers)
        self.assertFalse(peer.errors, diagnostic)
        self.assertTrue(peer.succeeded, diagnostic)
        self.assertTrue(peer.synack_seen, diagnostic)
        self.assertTrue(peer.handshake_complete, diagnostic)
        self.assertTrue(peer.request_sent, diagnostic)
        self.assertEqual(peer.request_bytes_written, len(REQUEST), diagnostic)
        self.assertTrue(peer.response_complete, diagnostic)
        self.assertEqual(
            peer.response_expected_length,
            len(EXPECTED_RESPONSE),
            diagnostic,
        )
        self.assertEqual(
            bytes(peer.response_plaintext),
            EXPECTED_RESPONSE,
            diagnostic,
        )
        self.assertEqual(peer.response_status_code, 200, diagnostic)
        self.assertEqual(
            peer.response_content_length,
            len(RESPONSE_BODY),
            diagnostic,
        )
        self.assertEqual(peer.response_body, RESPONSE_BODY, diagnostic)
        self.assertEqual(peer.version, "TLSv1.3", diagnostic)
        self.assertIsNotNone(peer.cipher, diagnostic)
        self.assertEqual(peer.cipher[0], "TLS_AES_128_GCM_SHA256", diagnostic)
        self.assertEqual(peer.alpn, "http/1.1", diagnostic)
        self.assertTrue(peer.peer_certificate, diagnostic)
        self.assertEqual(peer.peer_certificate_der, leaf, diagnostic)
        self.assertTrue(peer.close_started, diagnostic)
        self.assertTrue(peer.client_close_notify_sent, diagnostic)
        self.assertTrue(peer.server_close_notify_seen, diagnostic)
        self.assertTrue(peer.tls_shutdown_complete, diagnostic)
        self.assertTrue(peer.client_fin_sent, diagnostic)
        self.assertTrue(peer.client_fin_acked, diagnostic)
        self.assertTrue(peer.server_fin_seen, diagnostic)

    def test_two_connections_reuse_one_secure_listener(self) -> None:
        leaf = _fixture("leaf")
        intermediate = _fixture("intermediate")
        root = _fixture("root")
        self.assertTrue(leaf and intermediate and root)

        profile = _profile(leaf, intermediate)
        previous_profile = harness.PROFILES.get(PROFILE_NAME)
        harness.PROFILES[PROFILE_NAME] = profile
        try:
            with tempfile.TemporaryDirectory(
                prefix="akashic-kdos-tls-inbound-vertical-"
            ) as directory:
                image = harness.build_image(
                    PROFILE_NAME,
                    Path(directory) / "vertical.img",
                )
                with harness.MachineSession.from_bios(
                    harness.MEGAPAD_ROOT / "bios.asm",
                    storage_image=image,
                    cols=120,
                    rows=40,
                    batch_steps=500_000,
                    ext_mem_size=EXT_MEM_SIZE,
                    num_cores=1,
                ) as machine:
                    mux = KdosTlsMemoryPeerMux()
                    nic = machine.system.nic
                    nic.on_tx_frame = mux.tx_callback(nic)
                    peers: list[KdosTlsMemoryPeer] = []
                    steps = [0]
                    started_at = time.monotonic()
                    deadline = started_at + TOTAL_WALL_TIMEOUT_S
                    try:
                        machine.boot()
                        _run_until(
                            machine,
                            profile,
                            READY_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )

                        peer1 = KdosTlsMemoryPeer(
                            root,
                            REQUEST,
                            client_port=50000,
                            client_isn=1999,
                            alpn_protocols=("http/1.1",),
                            server_hostname="test.example.com",
                        )
                        peers.append(peer1)
                        mux.add(peer1)
                        mux.inject_syn(nic, peer1.key)
                        machine.send_text("x")
                        _run_until(
                            machine,
                            profile,
                            FIRST_DONE_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        self._assert_peer(
                            machine,
                            peer1,
                            leaf,
                            *peers,
                        )

                        peer2 = KdosTlsMemoryPeer(
                            root,
                            REQUEST,
                            client_port=50001,
                            client_isn=2999,
                            alpn_protocols=("http/1.1",),
                            server_hostname="test.example.com",
                        )
                        peers.append(peer2)
                        mux.add(peer2)
                        mux.inject_syn(nic, peer2.key)
                        machine.send_text("x")
                        _run_until(
                            machine,
                            profile,
                            PASS_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        self.assertIn(
                            PASS_MARKER,
                            machine.raw_text(),
                            _diagnostics(machine, *peers),
                        )
                        self.assertFalse(
                            _guest_failures(profile, machine),
                            _diagnostics(machine, *peers),
                        )
                        self._assert_peer(
                            machine,
                            peer1,
                            leaf,
                            *peers,
                        )
                        self._assert_peer(
                            machine,
                            peer2,
                            leaf,
                            *peers,
                        )
                        print(
                            "KDOS TLS inbound vertical: PASS "
                            f"({steps[0]:,} guest steps, "
                            f"{time.monotonic() - started_at:.2f}s)"
                        )
                    except self.failureException:
                        raise
                    except Exception as error:
                        self.fail(
                            f"vertical raised {error!r}\n"
                            f"{_diagnostics(machine, *peers)}"
                        )
        finally:
            if previous_profile is None:
                harness.PROFILES.pop(PROFILE_NAME, None)
            else:
                harness.PROFILES[PROFILE_NAME] = previous_profile


if __name__ == "__main__":
    unittest.main()
