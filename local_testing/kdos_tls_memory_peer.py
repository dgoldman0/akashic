"""Independent TLS-over-raw-TCP peer for KDOS integration tests.

The MegaPad NIC test seam transports complete Ethernet frames.  This module
keeps that seam independent of KDOS's TLS implementation: Python's ``ssl``
module supplies the TLS 1.3 client, while the small TCP shim below supplies
only the sequencing and acknowledgements needed by a deterministic test
peer.

It is intentionally test-only.  The shim has no retransmission, congestion,
or reassembly policy; an unexpected sequence, reset, or malformed HTTP
response is retained as an assertion-visible error instead of being hidden
by a forgiving host TCP stack.
"""

from __future__ import annotations

import ssl
from collections.abc import Callable, Sequence
from typing import Any


TCP_FIN = 0x01
TCP_SYN = 0x02
TCP_RST = 0x04
TCP_PSH = 0x08
TCP_ACK = 0x10

MEGAPAD_MAC = bytes((0x02, 0x4D, 0x50, 0x36, 0x34, 0x00))
PEER_MAC = bytes((0xAA,) * 6)
GUEST_IP = bytes((10, 0, 0, 2))
PEER_IP = bytes((10, 0, 0, 1))


def _checksum(data: bytes) -> int:
    """Return an Internet checksum for an even- or odd-sized byte string."""
    if len(data) & 1:
        data += b"\x00"
    total = 0
    for offset in range(0, len(data), 2):
        total += (data[offset] << 8) | data[offset + 1]
    while total > 0xFFFF:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def build_ip_frame(
    destination_mac: bytes | Sequence[int],
    source_mac: bytes | Sequence[int],
    protocol: int,
    source_ip: bytes | Sequence[int],
    destination_ip: bytes | Sequence[int],
    payload: bytes,
) -> bytes:
    """Build one Ethernet/IPv4 frame suitable for ``nic.inject_frame``."""
    destination_mac = bytes(destination_mac)
    source_mac = bytes(source_mac)
    source_ip = bytes(source_ip)
    destination_ip = bytes(destination_ip)
    if len(destination_mac) != 6 or len(source_mac) != 6:
        raise ValueError("Ethernet addresses must be six bytes")
    if len(source_ip) != 4 or len(destination_ip) != 4:
        raise ValueError("IPv4 addresses must be four bytes")
    if len(payload) > 0xFFFF - 20:
        raise ValueError("IPv4 payload is too large")

    ethernet = destination_mac + source_mac + b"\x08\x00"
    header = bytearray(20)
    header[0] = 0x45
    total_length = 20 + len(payload)
    header[2:4] = total_length.to_bytes(2, "big")
    header[6] = 0x40  # Don't Fragment.
    header[8] = 64
    header[9] = protocol & 0xFF
    header[12:16] = source_ip
    header[16:20] = destination_ip
    header[10:12] = _checksum(bytes(header)).to_bytes(2, "big")
    return ethernet + bytes(header) + bytes(payload)


def build_tcp_frame(
    destination_mac: bytes | Sequence[int],
    source_mac: bytes | Sequence[int],
    source_ip: bytes | Sequence[int],
    destination_ip: bytes | Sequence[int],
    source_port: int,
    destination_port: int,
    sequence: int,
    acknowledgement: int,
    flags: int,
    window: int,
    payload: bytes = b"",
) -> bytes:
    """Build one Ethernet/IPv4/TCP frame, including the TCP checksum."""
    source_ip = bytes(source_ip)
    destination_ip = bytes(destination_ip)
    payload = bytes(payload)
    for name, value in (
        ("source_port", source_port),
        ("destination_port", destination_port),
        ("window", window),
    ):
        if not 0 <= value <= 0xFFFF:
            raise ValueError(f"{name} is outside its unsigned 16-bit range")
    for name, value in (
        ("sequence", sequence),
        ("acknowledgement", acknowledgement),
    ):
        if not 0 <= value <= 0xFFFFFFFF:
            raise ValueError(f"{name} is outside its unsigned 32-bit range")

    header = bytearray(20)
    header[0:2] = source_port.to_bytes(2, "big")
    header[2:4] = destination_port.to_bytes(2, "big")
    header[4:8] = sequence.to_bytes(4, "big")
    header[8:12] = acknowledgement.to_bytes(4, "big")
    header[12] = 0x50  # Five 32-bit words, with no TCP options.
    header[13] = flags & 0xFF
    header[14:16] = window.to_bytes(2, "big")

    segment = bytes(header) + payload
    pseudo_header = (
        source_ip
        + destination_ip
        + b"\x00\x06"
        + len(segment).to_bytes(2, "big")
    )
    header[16:18] = _checksum(pseudo_header + segment).to_bytes(2, "big")
    return build_ip_frame(
        destination_mac,
        source_mac,
        6,
        source_ip,
        destination_ip,
        bytes(header) + payload,
    )


def parse_tcp_frame(frame: bytes | bytearray | Sequence[int]) -> dict[str, Any] | None:
    """Parse an Ethernet/IPv4/TCP frame, or return ``None`` for other traffic."""
    frame = bytes(frame)
    if len(frame) < 54 or frame[12:14] != b"\x08\x00":
        return None

    ip_start = 14
    version = frame[ip_start] >> 4
    ip_header_length = (frame[ip_start] & 0x0F) * 4
    if version != 4 or ip_header_length < 20:
        return None
    if len(frame) < ip_start + ip_header_length + 20:
        return None
    if frame[ip_start + 9] != 6:
        return None

    ip_total_length = int.from_bytes(frame[ip_start + 2:ip_start + 4], "big")
    if ip_total_length < ip_header_length + 20:
        return None
    ip_end = ip_start + ip_total_length
    if ip_end > len(frame):
        return None

    tcp_start = ip_start + ip_header_length
    tcp_header_length = (frame[tcp_start + 12] >> 4) * 4
    if tcp_header_length < 20 or tcp_start + tcp_header_length > ip_end:
        return None

    return {
        "sport": int.from_bytes(frame[tcp_start:tcp_start + 2], "big"),
        "dport": int.from_bytes(frame[tcp_start + 2:tcp_start + 4], "big"),
        "seq": int.from_bytes(frame[tcp_start + 4:tcp_start + 8], "big"),
        "ack": int.from_bytes(frame[tcp_start + 8:tcp_start + 12], "big"),
        "flags": frame[tcp_start + 13],
        "window": int.from_bytes(
            frame[tcp_start + 14:tcp_start + 16], "big"
        ),
        "payload": frame[tcp_start + tcp_header_length:ip_end],
        "src_ip": bytes(frame[ip_start + 12:ip_start + 16]),
        "dst_ip": bytes(frame[ip_start + 16:ip_start + 20]),
        "src_mac": bytes(frame[6:12]),
        "dst_mac": bytes(frame[0:6]),
    }


class KdosTlsMemoryPeer:
    """A strict raw-TCP TLS 1.3 client for one KDOS listener connection.

    Constructing the peer runs the client far enough to retain its complete
    ClientHello.  Call :meth:`syn_frame` when the harness wants an initial NIC
    frame, or :meth:`inject_syn` when the NIC is already available.  Install
    :meth:`on_server_frame` as the NIC transmit callback.

    All protocol failures are retained in :attr:`errors`; NIC callbacks do
    not throw protocol exceptions through the emulator.
    """

    _MAX_TCP_PAYLOAD = 1400
    _WINDOW = 4096

    def __init__(
        self,
        root_certificate_der: bytes,
        request: bytes,
        *,
        client_port: int,
        client_isn: int,
        alpn_protocols: Sequence[str] = ("http/1.1",),
        server_hostname: str = "test.example.com",
        server_port: int = 443,
        response_complete_predicate: Callable[[bytes], bool] | None = None,
    ) -> None:
        if not root_certificate_der:
            raise ValueError("a DER trust root is required")
        if not request:
            raise ValueError("the application request must not be empty")
        if not 0 < client_port <= 0xFFFF:
            raise ValueError("client_port must be in 1..65535")
        if not 0 < server_port <= 0xFFFF:
            raise ValueError("server_port must be in 1..65535")
        if not 0 <= client_isn <= 0xFFFFFFFF:
            raise ValueError("client_isn must be an unsigned 32-bit value")
        if not alpn_protocols or any(not item for item in alpn_protocols):
            raise ValueError("at least one nonempty ALPN protocol is required")

        self.root_certificate_der = bytes(root_certificate_der)
        self.request = bytes(request)
        self.client_port = client_port
        self.client_isn = client_isn
        self.server_port = server_port
        self.server_hostname = server_hostname
        self.alpn_protocols = tuple(alpn_protocols)
        self.response_complete_predicate = response_complete_predicate

        self.client_next = (client_isn + 1) & 0xFFFFFFFF
        self.server_next: int | None = None
        self.syn_sent = False
        self.synack_seen = False
        self.handshake_complete = False
        self.request_sent = False
        self.request_bytes_written = 0
        self.response_plaintext = bytearray()
        self.response_status_line: bytes | None = None
        self.response_status_code: int | None = None
        self.response_headers: dict[str, str] = {}
        self.response_content_length: int | None = None
        self.response_expected_length: int | None = None
        self.response_complete = False
        self.close_started = False
        self.client_close_notify_sent = False
        self.server_close_notify_seen = False
        self.tls_shutdown_complete = False
        self.client_fin_sent = False
        self.client_fin_acked = False
        self.server_fin_seen = False
        self.version: str | None = None
        self.cipher: tuple[str, str, int] | None = None
        self.alpn: str | None = None
        self.peer_certificate: dict[str, Any] | None = None
        self.peer_certificate_der: bytes | None = None
        self.errors: list[str] = []

        self._syn_injected = False
        self._peer_frames_sent = 0
        self._response_body_offset: int | None = None
        self._incoming = ssl.MemoryBIO()
        self._outgoing = ssl.MemoryBIO()
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.minimum_version = ssl.TLSVersion.TLSv1_3
        context.maximum_version = ssl.TLSVersion.TLSv1_3
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        context.load_verify_locations(
            cadata=ssl.DER_cert_to_PEM_cert(self.root_certificate_der)
        )
        context.set_alpn_protocols(list(self.alpn_protocols))
        self._tls = context.wrap_bio(
            self._incoming,
            self._outgoing,
            server_side=False,
            server_hostname=self.server_hostname,
        )

        try:
            self._tls.do_handshake()
        except ssl.SSLWantReadError:
            pass
        else:
            raise RuntimeError("TLS client completed before receiving a server flight")
        self._client_hello = self._drain_outgoing()
        if len(self._client_hello) <= 5 or self._client_hello[0] != 22:
            raise RuntimeError("TLS client did not produce a handshake ClientHello")
        self._syn = build_tcp_frame(
            MEGAPAD_MAC,
            PEER_MAC,
            PEER_IP,
            GUEST_IP,
            self.client_port,
            self.server_port,
            self.client_isn,
            0,
            TCP_SYN,
            self._WINDOW,
        )

    @property
    def key(self) -> tuple[int, int]:
        """Return the deterministic identity used by a multi-peer harness."""
        return self.client_port, self.client_isn

    @property
    def decrypted_response(self) -> bytes:
        """Return all application bytes authenticated from the TLS server."""
        return bytes(self.response_plaintext)

    @property
    def response_body(self) -> bytes:
        """Return the parsed HTTP response body, or empty bytes before headers."""
        if self._response_body_offset is None:
            return b""
        return bytes(self.response_plaintext[self._response_body_offset:])

    @property
    def succeeded(self) -> bool:
        """Whether authenticated HTTP exchange and bidirectional close finished."""
        return (
            not self.errors
            and self.synack_seen
            and self.handshake_complete
            and self.request_sent
            and self.response_complete
            and self.client_close_notify_sent
            and self.server_close_notify_seen
            and self.tls_shutdown_complete
            and self.client_fin_sent
            and self.client_fin_acked
            and self.server_fin_seen
        )

    @property
    def assertion_state(self) -> dict[str, Any]:
        """Return a stable, serialization-friendly integration-test summary."""
        return {
            "key": self.key,
            "errors": tuple(self.errors),
            "syn_sent": self.syn_sent,
            "synack_seen": self.synack_seen,
            "handshake_complete": self.handshake_complete,
            "request_sent": self.request_sent,
            "request_bytes_written": self.request_bytes_written,
            "response_plaintext": bytes(self.response_plaintext),
            "decrypted_response": self.decrypted_response,
            "response_status_line": self.response_status_line,
            "response_status_code": self.response_status_code,
            "response_headers": dict(self.response_headers),
            "response_content_length": self.response_content_length,
            "response_expected_length": self.response_expected_length,
            "response_body": self.response_body,
            "response_complete": self.response_complete,
            "close_started": self.close_started,
            "client_close_notify_sent": self.client_close_notify_sent,
            "server_close_notify_seen": self.server_close_notify_seen,
            "tls_shutdown_complete": self.tls_shutdown_complete,
            "client_fin_sent": self.client_fin_sent,
            "client_fin_acked": self.client_fin_acked,
            "server_fin_seen": self.server_fin_seen,
            "version": self.version,
            "cipher": self.cipher,
            "alpn": self.alpn,
            "peer_certificate": self.peer_certificate,
            "peer_certificate_der": self.peer_certificate_der,
            "succeeded": self.succeeded,
        }

    def syn_frame(self) -> bytes:
        """Return the prebuilt SYN for initial-frame injection."""
        self.syn_sent = True
        return self._syn

    def inject_syn(self, nic: Any) -> None:
        """Inject the connection's SYN directly into a MegaPad test NIC."""
        if self._syn_injected:
            self._note_error("duplicate-client-syn", self.key)
            return
        if not nic.inject_frame(self._syn):
            self._note_error("nic-rejected-client-syn", self.key)
            return
        self._syn_injected = True
        self.syn_sent = True

    def on_server_frame(self, nic: Any, raw_frame: Any) -> None:
        """Consume one MegaPad TX frame and inject any immediate peer reply."""
        try:
            frame = parse_tcp_frame(raw_frame)
            if frame is None:
                return
            if (
                frame["sport"] != self.server_port
                or frame["dport"] != self.client_port
            ):
                return
            if frame["src_ip"] != GUEST_IP or frame["dst_ip"] != PEER_IP:
                self._note_error(
                    "server-address",
                    (frame["src_ip"], frame["dst_ip"]),
                )
                return
            if frame["src_mac"] != MEGAPAD_MAC or frame["dst_mac"] != PEER_MAC:
                self._note_error(
                    "server-ethernet-address",
                    (frame["src_mac"], frame["dst_mac"]),
                )
                return
            self._consume_server_tcp(nic, frame)
        except Exception as error:  # Keep emulator callbacks diagnostically safe.
            self._note_error("peer-callback", error)

    def tx_callback(self, nic: Any) -> Callable[[Any], None]:
        """Adapt the two-argument handler to a one-argument NIC TX seam."""
        return lambda raw_frame: self.on_server_frame(nic, raw_frame)

    def _consume_server_tcp(self, nic: Any, frame: dict[str, Any]) -> None:
        flags = frame["flags"]
        payload = frame["payload"]

        if flags & TCP_RST:
            self._note_error("server-rst", frame)
            return

        if flags & TCP_SYN:
            self._consume_synack(nic, frame)
            return

        if not self.synack_seen or self.server_next is None:
            self._note_error("server-frame-before-synack", frame)
            return
        if frame["seq"] != self.server_next:
            self._note_error(
                "server-sequence",
                (frame["seq"], self.server_next, len(payload), flags),
            )
            self._inject_segment(nic)
            return

        acknowledgement = frame["ack"]
        if self._seq_after(acknowledgement, self.client_next):
            self._note_error(
                "server-ack-beyond-client-sequence",
                (acknowledgement, self.client_next),
            )
        if self.client_fin_sent and acknowledgement == self.client_next:
            self.client_fin_acked = True

        # Advance first so every immediate response acknowledges both payload
        # and a FIN carried on the same segment.
        self.server_next = self._seq_add(self.server_next, len(payload))
        if flags & TCP_FIN:
            self.server_next = self._seq_add(self.server_next, 1)

        frames_before = self._peer_frames_sent
        if payload:
            self._consume_tls_payload(nic, payload)

        if flags & TCP_FIN:
            self.server_fin_seen = True
            if not self.server_close_notify_seen:
                self._note_error("server-fin-before-close-notify", frame)

        if (payload or flags & TCP_FIN) and self._peer_frames_sent == frames_before:
            self._inject_segment(nic)

    def _consume_synack(self, nic: Any, frame: dict[str, Any]) -> None:
        if self.synack_seen:
            self._note_error("duplicate-server-syn", frame)
            return
        if not frame["flags"] & TCP_ACK:
            self._note_error("server-syn-without-ack", frame)
            return
        if frame["ack"] != self.client_next:
            self._note_error(
                "server-synack-ack",
                (frame["ack"], self.client_next),
            )
            return
        if frame["payload"]:
            self._note_error("server-syn-with-payload", len(frame["payload"]))
            return

        self.synack_seen = True
        self.server_next = self._seq_add(frame["seq"], 1)
        self._inject_segment(nic)
        self._inject_payload(nic, self._client_hello)

    def _consume_tls_payload(self, nic: Any, payload: bytes) -> None:
        try:
            self._incoming.write(payload)
            if not self.handshake_complete:
                self._advance_handshake(nic)
            elif self.close_started:
                self._advance_shutdown(nic)
            else:
                self._read_response(nic)
        except ssl.SSLError as error:
            self._note_error("peer-tls", error)

    def _advance_handshake(self, nic: Any) -> None:
        try:
            self._tls.do_handshake()
        except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
            pass
        else:
            self.handshake_complete = True
            self.version = self._tls.version()
            self.cipher = self._tls.cipher()
            self.alpn = self._tls.selected_alpn_protocol()
            self.peer_certificate = self._tls.getpeercert()
            self.peer_certificate_der = self._tls.getpeercert(binary_form=True)
            if self.alpn not in self.alpn_protocols:
                self._note_error("server-alpn", self.alpn)

        handshake_wire = self._drain_outgoing()
        if handshake_wire:
            self._inject_payload(nic, handshake_wire)
        if self.handshake_complete and not self.request_sent:
            self._send_request(nic)

    def _send_request(self, nic: Any) -> None:
        while self.request_bytes_written < len(self.request):
            try:
                count = self._tls.write(
                    self.request[self.request_bytes_written:]
                )
            except (ssl.SSLWantReadError, ssl.SSLWantWriteError) as error:
                self._note_error("client-request-write-blocked", error)
                break
            if count <= 0:
                self._note_error("client-request-short-write", count)
                break
            self.request_bytes_written += count
        self.request_sent = self.request_bytes_written == len(self.request)
        request_wire = self._drain_outgoing()
        if request_wire:
            self._inject_payload(nic, request_wire)
        elif self.request_sent:
            self._note_error("missing-encrypted-request", len(self.request))

    def _read_response(self, nic: Any) -> None:
        while True:
            try:
                plaintext = self._tls.read(65536)
            except ssl.SSLWantReadError:
                break
            except ssl.SSLZeroReturnError:
                self.server_close_notify_seen = True
                self._note_error(
                    "server-close-notify-before-complete-response",
                    len(self.response_plaintext),
                )
                break
            if not plaintext:
                self.server_close_notify_seen = True
                if not self.response_complete:
                    self._note_error(
                        "server-close-notify-before-complete-response",
                        len(self.response_plaintext),
                    )
                break
            self.response_plaintext.extend(plaintext)
            self._update_response_completion()
            if self.response_complete:
                break

        if self.response_complete and not self.close_started:
            self._begin_shutdown(nic)

    def _update_response_completion(self) -> None:
        response = bytes(self.response_plaintext)
        header_end = response.find(b"\r\n\r\n")
        if header_end >= 0 and self._response_body_offset is None:
            self._capture_response_headers(response[:header_end], header_end + 4)

        if self.response_complete_predicate is not None:
            try:
                self.response_complete = bool(
                    self.response_complete_predicate(response)
                )
            except Exception as error:
                self._note_error("response-completion-predicate", error)
            return

        if header_end < 0:
            return
        header_block = response[:header_end]
        lines = header_block.split(b"\r\n")
        if self.response_status_code is None:
            return

        lengths: list[bytes] = []
        for line in lines[1:]:
            if b":" not in line:
                self._note_error("malformed-response-header", line)
                return
            name, value = line.split(b":", 1)
            if name.strip().lower() == b"content-length":
                lengths.append(value.strip())
        if not lengths:
            self._note_error("missing-response-content-length", header_block)
            return
        if any(value != lengths[0] for value in lengths[1:]):
            self._note_error("conflicting-response-content-length", lengths)
            return
        if not lengths[0].isdigit():
            self._note_error("invalid-response-content-length", lengths[0])
            return

        content_length = int(lengths[0])
        self.response_content_length = content_length
        self.response_expected_length = header_end + 4 + content_length
        if len(response) > self.response_expected_length:
            self._note_error(
                "response-beyond-content-length",
                (len(response), self.response_expected_length),
            )
            return
        self.response_complete = len(response) == self.response_expected_length

    def _capture_response_headers(self, header_block: bytes, body_offset: int) -> None:
        lines = header_block.split(b"\r\n")
        if not lines or not lines[0].startswith(b"HTTP/"):
            self._note_error("response-status-line", lines[0] if lines else b"")
            return
        status_parts = lines[0].split(b" ", 2)
        if len(status_parts) < 2 or len(status_parts[1]) != 3:
            self._note_error("response-status-line", lines[0])
            return
        try:
            status_code = int(status_parts[1])
        except ValueError:
            self._note_error("response-status-line", lines[0])
            return

        headers: dict[str, str] = {}
        for line in lines[1:]:
            if b":" not in line:
                self._note_error("malformed-response-header", line)
                return
            name, value = line.split(b":", 1)
            try:
                normalized_name = name.strip().decode("ascii").lower()
                normalized_value = value.strip().decode("latin-1")
            except UnicodeDecodeError:
                self._note_error("malformed-response-header", line)
                return
            if normalized_name in headers:
                headers[normalized_name] += ", " + normalized_value
            else:
                headers[normalized_name] = normalized_value

        self.response_status_line = lines[0]
        self.response_status_code = status_code
        self.response_headers = headers
        self._response_body_offset = body_offset

    def _begin_shutdown(self, nic: Any) -> None:
        self.close_started = True
        self._advance_shutdown(nic)

    def _advance_shutdown(self, nic: Any) -> None:
        try:
            self._tls.unwrap()
        except (ssl.SSLWantReadError, ssl.SSLWantWriteError):
            pass
        else:
            self.server_close_notify_seen = True
            self.tls_shutdown_complete = True

        close_wire = self._drain_outgoing()
        if close_wire:
            if self.client_fin_sent:
                self._note_error("tls-output-after-client-fin", close_wire.hex())
                return
            self.client_close_notify_sent = True
            self._inject_payload(nic, close_wire, finish=True)
        elif not self.client_close_notify_sent:
            self._note_error("missing-client-close-notify", b"")

    def _inject_payload(
        self,
        nic: Any,
        payload: bytes,
        *,
        finish: bool = False,
    ) -> None:
        if not payload:
            if finish:
                self._inject_segment(nic, flags=TCP_ACK | TCP_FIN)
                self.client_fin_sent = True
            return
        chunks = [
            payload[offset:offset + self._MAX_TCP_PAYLOAD]
            for offset in range(0, len(payload), self._MAX_TCP_PAYLOAD)
        ]
        for index, chunk in enumerate(chunks):
            flags = TCP_ACK | TCP_PSH
            if finish and index == len(chunks) - 1:
                flags |= TCP_FIN
            self._inject_segment(nic, chunk, flags)
        if finish:
            self.client_fin_sent = True

    def _inject_segment(
        self,
        nic: Any,
        payload: bytes = b"",
        flags: int | None = None,
    ) -> None:
        if self.server_next is None:
            self._note_error("inject-before-synack", flags)
            return
        if flags is None:
            flags = TCP_ACK | (TCP_PSH if payload else 0)
        frame = build_tcp_frame(
            MEGAPAD_MAC,
            PEER_MAC,
            PEER_IP,
            GUEST_IP,
            self.client_port,
            self.server_port,
            self.client_next,
            self.server_next,
            flags,
            self._WINDOW,
            payload,
        )
        if not nic.inject_frame(frame):
            self._note_error(
                "nic-rejected-client-segment",
                (self.client_next, len(payload), flags),
            )
            return
        self._peer_frames_sent += 1
        self.client_next = self._seq_add(self.client_next, len(payload))
        if flags & TCP_FIN:
            self.client_next = self._seq_add(self.client_next, 1)

    def _drain_outgoing(self) -> bytes:
        wire = bytearray()
        while self._outgoing.pending:
            wire.extend(self._outgoing.read())
        return bytes(wire)

    def _note_error(self, label: str, detail: Any) -> None:
        self.errors.append(f"{label}: {detail!r}")

    @staticmethod
    def _seq_add(sequence: int, amount: int) -> int:
        return (sequence + amount) & 0xFFFFFFFF

    @staticmethod
    def _seq_after(left: int, right: int) -> bool:
        difference = (left - right) & 0xFFFFFFFF
        return 0 < difference < 0x80000000


class KdosTlsMemoryPeerMux:
    """Dispatch server frames among explicitly activated sequential peers."""

    def __init__(self, peers: Sequence[KdosTlsMemoryPeer] = ()) -> None:
        self.peers: dict[tuple[int, int], KdosTlsMemoryPeer] = {}
        self._active_by_port: dict[int, KdosTlsMemoryPeer] = {}
        for peer in peers:
            self.add(peer)

    def add(self, peer: KdosTlsMemoryPeer) -> None:
        if peer.key in self.peers:
            raise ValueError(f"duplicate peer key {peer.key!r}")
        self.peers[peer.key] = peer

    def syn_frame(self, key: tuple[int, int]) -> bytes:
        peer = self._activate(key)
        return peer.syn_frame()

    def inject_syn(self, nic: Any, key: tuple[int, int]) -> None:
        peer = self._activate(key)
        peer.inject_syn(nic)

    def on_server_frame(self, nic: Any, raw_frame: Any) -> None:
        frame = parse_tcp_frame(raw_frame)
        if frame is None:
            return
        peer = self._active_by_port.get(frame["dport"])
        if peer is not None:
            peer.on_server_frame(nic, raw_frame)

    def tx_callback(self, nic: Any) -> Callable[[Any], None]:
        """Adapt the mux to a one-argument NIC TX callback."""
        return lambda raw_frame: self.on_server_frame(nic, raw_frame)

    @property
    def errors(self) -> tuple[str, ...]:
        return tuple(
            f"{key!r} {error}"
            for key, peer in self.peers.items()
            for error in peer.errors
        )

    @property
    def succeeded(self) -> bool:
        return bool(self.peers) and all(peer.succeeded for peer in self.peers.values())

    @property
    def assertion_state(self) -> dict[tuple[int, int], dict[str, Any]]:
        return {key: peer.assertion_state for key, peer in self.peers.items()}

    def _activate(self, key: tuple[int, int]) -> KdosTlsMemoryPeer:
        peer = self.peers[key]
        previous = self._active_by_port.get(peer.client_port)
        if previous is not None and previous is not peer and not previous.succeeded:
            raise RuntimeError(
                f"client port {peer.client_port} is still owned by {previous.key!r}"
            )
        self._active_by_port[peer.client_port] = peer
        return peer


__all__ = [
    "GUEST_IP",
    "KdosTlsMemoryPeer",
    "KdosTlsMemoryPeerMux",
    "MEGAPAD_MAC",
    "PEER_IP",
    "PEER_MAC",
    "TCP_ACK",
    "TCP_FIN",
    "TCP_PSH",
    "TCP_RST",
    "TCP_SYN",
    "build_ip_frame",
    "build_tcp_frame",
    "parse_tcp_frame",
]
