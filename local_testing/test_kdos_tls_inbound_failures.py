#!/usr/bin/env python3
"""Qualify real inbound KDOS TLS failure cleanup and listener recovery."""

from __future__ import annotations

import sys
import tempfile
import time
import unittest
from pathlib import Path


LOCAL_TESTING = Path(__file__).resolve().parent
GUEST_SOURCE = LOCAL_TESTING / "tls-inbound-failures.f"
PROFILE_NAME = "kdos-tls-inbound-failure-qualification"
CANCEL_READY_MARKER = "TLS INBOUND FAILURE CANCEL READY"
CANCEL_DONE_MARKER = "TLS INBOUND FAILURE CANCEL DONE"
TIMEOUT_READY_MARKER = "TLS INBOUND FAILURE TIMEOUT READY"
TIMEOUT_DONE_MARKER = "TLS INBOUND FAILURE TIMEOUT DONE"
MALFORMED_READY_MARKER = "TLS INBOUND FAILURE MALFORMED READY"
MALFORMED_DONE_MARKER = "TLS INBOUND FAILURE MALFORMED DONE"
RECOVERY_READY_MARKER = "TLS INBOUND FAILURE RECOVERY READY"
PASS_MARKER = "TLS INBOUND FAILURE PASS"
FAIL_MARKER = "TLS INBOUND FAILURE FAIL"

RECOVERY_REQUEST = b"ping?"
RECOVERY_RESPONSE = b"pong!"

sys.path.insert(0, str(LOCAL_TESTING))

import kdos_tls_vertical_harness as vertical  # noqa: E402
from kdos_tls_memory_peer import (  # noqa: E402
    KdosTlsFaultPeer,
    KdosTlsMemoryPeer,
    KdosTlsMemoryPeerMux,
    TCP_ACK,
    TCP_RST,
)


harness = vertical.harness


def _autoexec(leaf: bytes, intermediate: bytes) -> str:
    chain = leaf + intermediate
    lines = [
        "\\ autoexec.f - real inbound KDOS TLS failure qualification",
        "ENTER-USERLAND",
        *vertical.forth_bytes("_ktif-chain", chain),
        f"{len(chain)} CONSTANT _KTIF-CHAIN-U",
        *vertical.forth_bytes("_ktif-key", b"\x03" + bytes(31)),
        "REQUIRE net/transports/kdos-tls-inbound.f",
        "REQUIRE local_testing/tls-inbound-failures.f",
        "TX-FLUSH",
    ]
    return "\n".join(lines) + "\n"


def _profile(leaf: bytes, intermediate: bytes) -> object:
    return harness.Profile(
        roots=("net/transports/kdos-tls-inbound.f",),
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
            "local_testing/tls-inbound-failures.f",
            GUEST_SOURCE.read_bytes(),
        ),),
        linked=False,
        requires_tap=False,
        include_large_sample=False,
    )


def _malformed_client_hello(wire: bytes) -> bytes:
    if (
        len(wire) < 5
        or wire[0] != 22
        or wire[1] != 3
        or wire[2] not in (1, 3)
    ):
        raise ValueError("OpenSSL did not produce a TLS handshake record")
    # Preserve the generated record type/version but declare an empty body.
    # KDOS must classify this exact malformed record as decode_error (50).
    return wire[:3] + b"\x00\x00"


class TestKdosTlsInboundFailures(unittest.TestCase):
    """Run three real lower failures, then recover on the same listener."""

    def _assert_fault_peer(
        self,
        machine: object,
        peer: KdosTlsFaultPeer,
        *all_peers: object,
    ) -> None:
        diagnostic = vertical.diagnostics(machine, *all_peers)
        self.assertFalse(peer.errors, diagnostic)
        self.assertTrue(peer.succeeded, diagnostic)
        self.assertTrue(peer.synack_seen, diagnostic)
        self.assertTrue(peer.rst_seen, diagnostic)
        self.assertTrue(peer.rst_exact, diagnostic)
        self.assertEqual(peer.rst_flags, TCP_RST | TCP_ACK, diagnostic)
        self.assertEqual(peer.rst_payload, b"", diagnostic)

    def _assert_recovery_peer(
        self,
        machine: object,
        peer: KdosTlsMemoryPeer,
        leaf: bytes,
        *all_peers: object,
    ) -> None:
        diagnostic = vertical.diagnostics(machine, *all_peers)
        self.assertFalse(peer.errors, diagnostic)
        self.assertTrue(peer.succeeded, diagnostic)
        self.assertTrue(peer.handshake_complete, diagnostic)
        self.assertTrue(peer.request_sent, diagnostic)
        self.assertEqual(
            peer.request_bytes_written,
            len(RECOVERY_REQUEST),
            diagnostic,
        )
        self.assertEqual(peer.decrypted_response, RECOVERY_RESPONSE, diagnostic)
        self.assertEqual(peer.version, "TLSv1.3", diagnostic)
        self.assertIsNotNone(peer.cipher, diagnostic)
        self.assertEqual(peer.cipher[0], "TLS_AES_128_GCM_SHA256", diagnostic)
        self.assertEqual(peer.alpn, "http/1.1", diagnostic)
        self.assertEqual(peer.peer_certificate_der, leaf, diagnostic)
        self.assertTrue(peer.client_close_notify_sent, diagnostic)
        self.assertTrue(peer.server_close_notify_seen, diagnostic)
        self.assertTrue(peer.tls_shutdown_complete, diagnostic)
        self.assertTrue(peer.client_fin_sent, diagnostic)
        self.assertTrue(peer.client_fin_acked, diagnostic)
        self.assertTrue(peer.server_fin_seen, diagnostic)

    def test_failures_clean_up_before_listener_recovery(self) -> None:
        leaf = vertical.fixture("leaf")
        intermediate = vertical.fixture("intermediate")
        root = vertical.fixture("root")
        self.assertTrue(leaf and intermediate and root)

        profile = _profile(leaf, intermediate)
        previous_profile = harness.PROFILES.get(PROFILE_NAME)
        harness.PROFILES[PROFILE_NAME] = profile
        try:
            with tempfile.TemporaryDirectory(
                prefix="akashic-kdos-tls-inbound-failures-"
            ) as directory:
                image = harness.build_image(
                    PROFILE_NAME,
                    Path(directory) / "failures.img",
                )
                with harness.MachineSession.from_bios(
                    harness.MEGAPAD_ROOT / "bios.asm",
                    storage_image=image,
                    cols=120,
                    rows=40,
                    batch_steps=500_000,
                    ext_mem_size=vertical.EXT_MEM_SIZE,
                    num_cores=1,
                ) as machine:
                    mux = KdosTlsMemoryPeerMux()
                    nic = machine.system.nic
                    nic.on_tx_frame = mux.tx_callback(nic)
                    peers: list[object] = []
                    steps = [0]
                    started_at = time.monotonic()
                    deadline = started_at + vertical.TOTAL_WALL_TIMEOUT_S
                    try:
                        machine.boot()
                        vertical.run_until(
                            machine,
                            profile,
                            CANCEL_READY_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )

                        cancel_peer = KdosTlsFaultPeer(
                            root,
                            client_port=50100,
                            client_isn=3999,
                            withhold_client_hello=True,
                        )
                        peers.append(cancel_peer)
                        mux.add(cancel_peer)
                        mux.inject_syn(nic, cancel_peer.key)
                        machine.send_text("x")
                        vertical.run_until(
                            machine,
                            profile,
                            CANCEL_DONE_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        self._assert_fault_peer(machine, cancel_peer, *peers)

                        vertical.run_until(
                            machine,
                            profile,
                            TIMEOUT_READY_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        timeout_peer = KdosTlsFaultPeer(
                            root,
                            client_port=50101,
                            client_isn=4999,
                            withhold_client_hello=True,
                        )
                        peers.append(timeout_peer)
                        mux.add(timeout_peer)
                        mux.inject_syn(nic, timeout_peer.key)
                        machine.send_text("x")
                        vertical.run_until(
                            machine,
                            profile,
                            TIMEOUT_DONE_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        self._assert_fault_peer(machine, timeout_peer, *peers)

                        vertical.run_until(
                            machine,
                            profile,
                            MALFORMED_READY_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        malformed_peer = KdosTlsFaultPeer(
                            root,
                            client_port=50102,
                            client_isn=5999,
                            client_hello_transform=_malformed_client_hello,
                        )
                        peers.append(malformed_peer)
                        mux.add(malformed_peer)
                        mux.inject_syn(nic, malformed_peer.key)
                        machine.send_text("x")
                        vertical.run_until(
                            machine,
                            profile,
                            MALFORMED_DONE_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        self._assert_fault_peer(machine, malformed_peer, *peers)
                        self.assertTrue(malformed_peer.client_hello_sent)
                        self.assertTrue(malformed_peer.client_hello_transformed)
                        self.assertEqual(
                            malformed_peer.client_hello_wire[:1], b"\x16"
                        )
                        self.assertEqual(
                            malformed_peer.client_hello_wire[3:], b"\x00\x00"
                        )
                        self.assertEqual(
                            len(malformed_peer.client_hello_wire), 5
                        )

                        vertical.run_until(
                            machine,
                            profile,
                            RECOVERY_READY_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )
                        recovery_peer = KdosTlsMemoryPeer(
                            root,
                            RECOVERY_REQUEST,
                            client_port=50103,
                            client_isn=6999,
                            alpn_protocols=("http/1.1",),
                            server_hostname="test.example.com",
                            response_complete_predicate=(
                                lambda response: response == RECOVERY_RESPONSE
                            ),
                        )
                        peers.append(recovery_peer)
                        mux.add(recovery_peer)
                        mux.inject_syn(nic, recovery_peer.key)
                        machine.send_text("x")
                        vertical.run_until(
                            machine,
                            profile,
                            PASS_MARKER,
                            deadline=deadline,
                            steps=steps,
                        )

                        self.assertFalse(
                            vertical.guest_failures(profile, machine),
                            vertical.diagnostics(machine, *peers),
                        )
                        self._assert_fault_peer(
                            machine, cancel_peer, *peers
                        )
                        self._assert_fault_peer(
                            machine, timeout_peer, *peers
                        )
                        self._assert_fault_peer(
                            machine, malformed_peer, *peers
                        )
                        self._assert_recovery_peer(
                            machine,
                            recovery_peer,
                            leaf,
                            *peers,
                        )
                        print(
                            "KDOS TLS inbound failure recovery: PASS "
                            f"({steps[0]:,} guest steps, "
                            f"{time.monotonic() - started_at:.2f}s)"
                        )
                    except self.failureException:
                        raise
                    except Exception as error:
                        self.fail(
                            f"failure vertical raised {error!r}\n"
                            f"{vertical.diagnostics(machine, *peers)}"
                        )
        finally:
            if previous_profile is None:
                harness.PROFILES.pop(PROFILE_NAME, None)
            else:
                harness.PROFILES[PROFILE_NAME] = previous_profile


if __name__ == "__main__":
    unittest.main()
