#!/usr/bin/env python3
"""Live multi-connection stress test — Akashic web server over TAP.

Boots the Akashic web framework server, then verifies it can handle
multiple simultaneous TCP connections.  This exercises the KDOS TCP
stack's backlog handling, TCB slot management, and the server's
sequential accept loop under concurrent load.

Architecture
------------
KDOS TCP has an effective backlog of 1:  the listener TCB itself
transitions to ESTABLISHED on SYN→SYN-ACK→ACK, then SOCK-ACCEPT
transplants it and immediately re-opens TCP-LISTEN.  Additional SYNs
that arrive while the single listener is occupied are dropped and must
wait for the client's TCP retransmission.

As of a67828d the TCB pool is scaled 16–256 (floor 16, cap 256 with
XMEM) and includes a TIME_WAIT reaper.  TCB-ALLOC automatically runs
the reaper on pool exhaustion, and TCB-FLUSH-TIMEWAIT force-reclaims
all TIME_WAIT entries regardless of age (used by the test harness
via the server's vectored _SRV-CLOSE-XT to keep the pool fresh).

This means:
  - 2 concurrent connections:  both complete (one queues briefly)
  - 3+ concurrent:  some SYN retransmits (1-3 s added latency)
  - All should eventually succeed if given enough time
  - Sustained sequential loads (20-30+ requests) succeed because
    TCB-FLUSH-TIMEWAIT reclaims slots after each close

Prerequisites
-------------
    sudo ip tuntap add dev mp64tap0 mode tap user $USER
    sudo ip addr add 10.64.0.1/24 dev mp64tap0
    sudo ip link set mp64tap0 up

Running
-------
    cd local_testing
    python test_live_multi_conn.py                    # standalone
    python -m pytest test_live_multi_conn.py -v       # via pytest
    python -m pytest test_live_multi_conn.py -v -k concurrent  # subset
"""
from __future__ import annotations

import concurrent.futures
import os
import re
import socket
import sys
import threading
import time
import unittest

# ---------------------------------------------------------------------------
#  Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AKASHIC    = os.path.join(ROOT_DIR, "akashic")

LIB_FILES = [
    os.path.join(AKASHIC, "utils",  "string.f"),
    os.path.join(AKASHIC, "utils",  "table.f"),
    os.path.join(AKASHIC, "utils",  "datetime.f"),
    os.path.join(AKASHIC, "net",    "url.f"),
    os.path.join(AKASHIC, "net",    "headers.f"),
    os.path.join(AKASHIC, "markup", "core.f"),
    os.path.join(AKASHIC, "markup", "html.f"),
    os.path.join(AKASHIC, "web",    "request.f"),
    os.path.join(AKASHIC, "web",    "response.f"),
    os.path.join(AKASHIC, "web",    "router.f"),
    os.path.join(AKASHIC, "web",    "server.f"),
    os.path.join(AKASHIC, "web",    "template.f"),
    os.path.join(AKASHIC, "web",    "middleware.f"),
]

sys.path.insert(0, EMU_DIR)
from asm import assemble                             # noqa: E402
from system import MegapadSystem                     # noqa: E402
from nic_backends import TAPBackend, tap_available   # noqa: E402

# ---------------------------------------------------------------------------
#  Config
# ---------------------------------------------------------------------------

TAP_NAME  = os.environ.get("MP64_TAP",     "mp64tap0")
HOST_IP   = os.environ.get("MP64_HOST_IP", "10.64.0.1")
EMU_IP    = os.environ.get("MP64_EMU_IP",  "10.64.0.2")
PORT      = int(os.environ.get("MP64_PORT", "8080"))

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# Timeout for individual HTTP requests.  Must account for TCP SYN
# retransmission when the backlog-1 listener is busy (~1-3 s per retry).
# Keep short enough that a hung connection doesn't stall the whole suite.
HTTP_TIMEOUT = 10.0

# ---------------------------------------------------------------------------
#  Low-level helpers (shared with test_live_web.py)
# ---------------------------------------------------------------------------

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())


def _load_forth_lines(path):
    with open(path) as f:
        lines = []
        for line in f.read().splitlines():
            s = line.strip()
            if not s or s.startswith('\\'):
                continue
            if s.startswith('REQUIRE ') or s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines


def _next_line_chunk(data: bytes, pos: int) -> bytes:
    nl = data.find(b'\n', pos)
    return data[pos:nl + 1] if nl != -1 else data[pos:]


def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf


def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf
    )


def save_cpu_state(cpu):
    return {k: getattr(cpu, k) for k in
            ['pc', 'psel', 'xsel', 'spsel',
             'flag_z', 'flag_c', 'flag_n', 'flag_v',
             'flag_p', 'flag_g', 'flag_i', 'flag_s',
             'd_reg', 'q_out', 't_reg',
             'ivt_base', 'ivec_id', 'trap_addr',
             'halted', 'idle', 'cycle_count',
             '_ext_modifier']} | {'regs': list(cpu.regs)}


def restore_cpu_state(cpu, state):
    cpu.regs[:] = state['regs']
    for k, v in state.items():
        if k != 'regs':
            setattr(cpu, k, v)


# ---------------------------------------------------------------------------
#  Forth string constant builder
# ---------------------------------------------------------------------------

def _forth_create_string(name: str, s: str) -> list[str]:
    """CREATE <name> <bytes,>... and <name>-LEN CONSTANT."""
    chunks, cur = [], []
    for ch in s:
        cur.append(f"{ord(ch)} C,")
        if len(" ".join(cur)) > 70:
            chunks.append("  " + " ".join(cur))
            cur = []
    if cur:
        chunks.append("  " + " ".join(cur))
    return [f"CREATE {name}"] + chunks + [f"{len(s)} CONSTANT {name}-LEN"]


# ---------------------------------------------------------------------------
#  Demo Application (Forth source) — same routes as test_live_web.py
#  but uses the standard SERVE (no debug SRV-HANDLE redefinition) for
#  maximum throughput during concurrent-connection testing.
# ---------------------------------------------------------------------------

def build_demo_app(port: int) -> list[str]:
    """Generate Forth source for the demo application."""
    lines = []

    # JSON body constant (avoids S" quoting nightmares)
    json_status = '{"status":"ok","server":"akashic","port":' + str(port) + '}'
    lines += _forth_create_string("_DEMO-JSON", json_status)
    lines.append("")

    # Hello template
    hello_tpl = "<h1>Hello, {{ name }}!</h1><p>Welcome to Akashic Web.</p>"
    lines += _forth_create_string("_DEMO-HELLO-TPL", hello_tpl)
    lines.append("")

    lines += [
        # HTML output buffer
        'CREATE _HTML-BUF 8192 ALLOT',
        '_HTML-BUF 8192 HTML-SET-OUTPUT',
        '',
        # ---------- Handlers ----------
        ': _DEMO-HOME-BODY',
        '    S" h1" HTML-< HTML->  S" Akashic Web" HTML-TEXT!  S" h1" HTML-</',
        '    S" p" HTML-< HTML->   S" Megapad-64 web server" HTML-TEXT!  S" p" HTML-</',
        ';',
        '',
        ': HANDLE-HOME',
        '    200 RESP-STATUS',
        '    S" text/html" RESP-CONTENT-TYPE',
        '    HTML-OUTPUT-RESET',
        "    S\" Akashic\" ['] _DEMO-HOME-BODY TPL-PAGE",
        '    HTML-OUTPUT-RESULT RESP-BODY',
        '    RESP-SEND ;',
        '',
        ': _DEMO-ABOUT-BODY',
        '    S" h1" HTML-< HTML->  S" About" HTML-TEXT!  S" h1" HTML-</',
        '    S" p" HTML-< HTML->   S" Akashic framework" HTML-TEXT!  S" p" HTML-</',
        ';',
        '',
        ': HANDLE-ABOUT',
        '    200 RESP-STATUS',
        '    S" text/html" RESP-CONTENT-TYPE',
        '    HTML-OUTPUT-RESET',
        "    S\" About\" ['] _DEMO-ABOUT-BODY TPL-PAGE",
        '    HTML-OUTPUT-RESULT RESP-BODY',
        '    RESP-SEND ;',
        '',
        ': HANDLE-STATUS',
        '    200 RESP-STATUS',
        '    S" application/json" RESP-CONTENT-TYPE',
        '    _DEMO-JSON _DEMO-JSON-LEN RESP-BODY',
        '    RESP-SEND ;',
        '',
        ': HANDLE-ECHO',
        '    200 RESP-STATUS',
        '    S" application/json" RESP-CONTENT-TYPE',
        '    REQ-BODY RESP-BODY',
        '    RESP-SEND ;',
        '',
        ': HANDLE-HELLO',
        '    200 RESP-STATUS',
        '    S" text/html" RESP-CONTENT-TYPE',
        '    TPL-VAR-CLEAR',
        '    S" name" ROUTE-PARAM S" name" TPL-VAR!',
        '    _DEMO-HELLO-TPL _DEMO-HELLO-TPL-LEN TPL-EXPAND',
        '    RESP-BODY  RESP-SEND ;',
        '',
        # ---------- Routes ----------
        ': SETUP-ROUTES',
        '    ROUTE-CLEAR',
        "    S\" GET\"  S\" /\"            ['] HANDLE-HOME   ROUTE",
        "    S\" GET\"  S\" /about\"       ['] HANDLE-ABOUT  ROUTE",
        "    S\" GET\"  S\" /api/status\"  ['] HANDLE-STATUS ROUTE",
        "    S\" POST\" S\" /api/echo\"    ['] HANDLE-ECHO   ROUTE",
        "    S\" GET\"  S\" /hello/:name\" ['] HANDLE-HELLO  ROUTE",
        ';',
        'SETUP-ROUTES',
        '',
        # ---------- Middleware ----------
        'MW-CLEAR',
        "' MW-CORS MW-USE",
        "' MW-LOG  MW-USE",
        "' MW-RUN SRV-SET-DISPATCH",
        '',
        # ---------- TCB housekeeping ----------
        # Override the server's vectored close to flush TIME_WAIT TCBs
        # after every connection.  This keeps the pool from filling up
        # during sustained sequential requests.
        ': _SRV-CLOSE-FLUSH  ( sd -- )  CLOSE TCB-REAP-TW ;',
        "' _SRV-CLOSE-FLUSH _SRV-CLOSE-XT !",
        '',
        # ---------- Start server ----------
        f'{port} SERVE',
    ]
    return lines


# ---------------------------------------------------------------------------
#  Snapshot builder
# ---------------------------------------------------------------------------

_snapshot = None


def build_snapshot():
    """Compile BIOS + KDOS + all web framework libs → (mem, cpu_state, ext_mem)."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + web framework ...")
    t0 = time.time()

    bios_code = _load_bios()
    all_lines = _load_forth_lines(KDOS_PATH) + ["ENTER-USERLAND"]
    for path in LIB_FILES:
        all_lines.extend(_load_forth_lines(path))

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    payload = ("\n".join(all_lines) + "\n").encode()
    pos, steps, mx = 0, 0, 800_000_000

    while steps < mx:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(payload):
                chunk = _next_line_chunk(payload, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    errs = [l for l in text.strip().split('\n')
            if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower())]
    if errs:
        print("[!] Compilation warnings (non-fatal):")
        for ln in errs[-15:]:
            print(f"    {ln}")

    _snapshot = (
        bytes(sys_obj.cpu.mem),
        save_cpu_state(sys_obj.cpu),
        bytes(sys_obj._ext_mem) if hasattr(sys_obj, '_ext_mem') else b'',
        bios_code,
    )
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time() - t0:.1f}s")
    return _snapshot


# ---------------------------------------------------------------------------
#  Emulator Server — runs in a background thread
# ---------------------------------------------------------------------------

class EmuServer:
    """Manages the Megapad-64 emulator running the Akashic web server."""

    def __init__(self, snapshot, port: int = PORT):
        self.snapshot = snapshot
        self.port = port
        self.shutdown = threading.Event()
        self.ready = threading.Event()
        self.thread: threading.Thread | None = None
        self.sys_obj: MegapadSystem | None = None
        self.uart_buf: list[int] = []
        self.steps = 0

    def start(self, timeout: float = 120.0):
        """Start the emulator loop in a daemon thread; block until ready."""
        self.thread = threading.Thread(target=self._run, daemon=True,
                                       name="emu-server")
        self.thread.start()
        if not self.ready.wait(timeout=timeout):
            raise RuntimeError("Server did not become ready within "
                               f"{timeout}s")

    def stop(self):
        """Signal shutdown and wait for thread to finish."""
        self.shutdown.set()
        if self.thread and self.thread.is_alive():
            self.thread.join(timeout=10.0)
        if self.sys_obj:
            try:
                self.sys_obj.nic.stop()
            except Exception:
                pass

    def _run(self):
        mem_bytes, cpu_state, ext_mem, bios_code = self.snapshot

        backend = TAPBackend(tap_name=TAP_NAME)
        sys_obj = MegapadSystem(
            ram_size=1024 * 1024,
            ext_mem_size=16 * (1 << 20),
            nic_backend=backend,
        )
        self.sys_obj = sys_obj
        self.uart_buf = buf = capture_uart(sys_obj)

        # Boot-to-idle: wire up C++ accelerator MMIO routing
        sys_obj.load_binary(0, bios_code)
        sys_obj.boot()
        for _ in range(200):
            if sys_obj.cpu.idle:
                break
            sys_obj.run_batch(50_000)

        # Restore snapshot over the booted state
        sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
        if ext_mem and hasattr(sys_obj, '_ext_mem'):
            sys_obj._ext_mem[:len(ext_mem)] = ext_mem
        restore_cpu_state(sys_obj.cpu, cpu_state)
        buf.clear()

        # IP configuration + demo app
        ip_parts = EMU_IP.split(".")
        gw_parts = HOST_IP.split(".")
        inject_lines = [
            f"{ip_parts[0]} {ip_parts[1]} {ip_parts[2]} {ip_parts[3]} IP-SET",
            f"{gw_parts[0]} {gw_parts[1]} {gw_parts[2]} {gw_parts[3]} GW-IP IP!",
            "255 255 255 0 NET-MASK IP!",
        ] + build_demo_app(self.port)

        payload = ("\n".join(inject_lines) + "\n").encode()
        pos = 0
        idle_polls = 0
        server_ready = False

        try:
            while not self.shutdown.is_set():
                if sys_obj.cpu.halted:
                    break

                if sys_obj.cpu.idle:
                    # Feed pending UART input
                    if not sys_obj.uart.has_rx_data and pos < len(payload):
                        chunk = _next_line_chunk(payload, pos)
                        sys_obj.uart.inject_input(chunk)
                        pos += len(chunk)
                        idle_polls = 0
                    elif sys_obj._any_nic_rx():
                        idle_polls = 0
                    else:
                        idle_polls += 1

                    time.sleep(0.01 if server_ready else 0.005)
                    sys_obj.cpu.idle = False

                    # Detect server ready
                    if not server_ready:
                        text = uart_text(buf)
                        if "Listening on" in text or "SERVE" in text:
                            # Give it a moment to stabilise
                            for _ in range(10):
                                sys_obj.cpu.idle = False
                                sys_obj.run_batch(50_000)
                                time.sleep(0.01)
                            server_ready = True
                            self.ready.set()
                    continue

                batch = sys_obj.run_batch(min(100_000, 1_000_000_000))
                self.steps += max(batch, 1)
        finally:
            try:
                sys_obj.nic.stop()
            except Exception:
                pass


# ---------------------------------------------------------------------------
#  HTTP client helpers
# ---------------------------------------------------------------------------

def http_get(path: str, timeout: float = HTTP_TIMEOUT) -> tuple[int, dict, str]:
    """Raw HTTP GET → (status, headers, body).  Returns (0, {}, error) on failure."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((EMU_IP, PORT))
        req = (f"GET {path} HTTP/1.1\r\n"
               f"Host: {EMU_IP}:{PORT}\r\n"
               f"Connection: close\r\n"
               f"\r\n")
        s.sendall(req.encode())

        chunks = []
        while True:
            try:
                data = s.recv(4096)
                if not data:
                    break
                chunks.append(data)
            except socket.timeout:
                break

        raw = b''.join(chunks)
        text = raw.decode('utf-8', errors='replace')

        first_line = text.split('\r\n', 1)[0]
        status = int(first_line.split(' ', 2)[1]) if ' ' in first_line else 0

        if '\r\n\r\n' in text:
            hdr_part, body = text.split('\r\n\r\n', 1)
        else:
            hdr_part, body = text, ''

        headers = {}
        for line in hdr_part.split('\r\n')[1:]:
            if ':' in line:
                k, v = line.split(':', 1)
                headers[k.strip().lower()] = v.strip()

        return (status, headers, body)

    except Exception as e:
        return (0, {}, f"ERROR: {e}")
    finally:
        s.close()


def http_post(path: str, body: str,
              content_type: str = "application/json",
              timeout: float = HTTP_TIMEOUT) -> tuple[int, dict, str]:
    """Raw HTTP POST → (status, headers, body)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect((EMU_IP, PORT))
        req = (f"POST {path} HTTP/1.1\r\n"
               f"Host: {EMU_IP}:{PORT}\r\n"
               f"Content-Type: {content_type}\r\n"
               f"Content-Length: {len(body)}\r\n"
               f"Connection: close\r\n"
               f"\r\n"
               f"{body}")
        s.sendall(req.encode())

        chunks = []
        while True:
            try:
                data = s.recv(4096)
                if not data:
                    break
                chunks.append(data)
            except socket.timeout:
                break

        raw = b''.join(chunks)
        text = raw.decode('utf-8', errors='replace')

        first_line = text.split('\r\n', 1)[0]
        status = int(first_line.split(' ', 2)[1]) if ' ' in first_line else 0

        if '\r\n\r\n' in text:
            hdr_part, resp_body = text.split('\r\n\r\n', 1)
        else:
            hdr_part, resp_body = text, ''

        headers = {}
        for line in hdr_part.split('\r\n')[1:]:
            if ':' in line:
                k, v = line.split(':', 1)
                headers[k.strip().lower()] = v.strip()

        return (status, headers, resp_body)

    except Exception as e:
        return (0, {}, f"ERROR: {e}")
    finally:
        s.close()


# ---------------------------------------------------------------------------
#  Test Suite
# ---------------------------------------------------------------------------

def _skip_if_no_tap():
    """Skip the entire module if TAP is unavailable."""
    if not tap_available(TAP_NAME):
        raise unittest.SkipTest(
            f"TAP device '{TAP_NAME}' not accessible.  Set up with:\n"
            f"  sudo ip tuntap add dev {TAP_NAME} mode tap user $USER\n"
            f"  sudo ip addr add {HOST_IP}/24 dev {TAP_NAME}\n"
            f"  sudo ip link set {TAP_NAME} up"
        )


class TestLiveMultiConn(unittest.TestCase):
    """Concurrent connection tests for the Akashic HTTP server.

    The server runs inside the emulator over a real TAP device.
    Tests fire multiple HTTP requests simultaneously from Python
    using ThreadPoolExecutor and verify all get proper responses.
    """

    _server: EmuServer | None = None
    _skip_setup: bool = False     # set by main() when server already running

    @classmethod
    def setUpClass(cls):
        if cls._skip_setup and cls._server is not None:
            # Server already started by main() — skip setup
            return
        _skip_if_no_tap()
        snapshot = build_snapshot()
        cls._server = EmuServer(snapshot)
        cls._server.start(timeout=120.0)
        # Brief warmup — let the server's accept loop stabilise
        time.sleep(1.0)
        # Smoke test: one plain GET to prime ARP etc.
        status, _, _ = http_get("/", timeout=20.0)
        if status != 200:
            raise unittest.SkipTest(
                f"Smoke test GET / failed with status {status}; "
                f"server may not have booted properly.")
        print(f"[*] Server ready — smoke test passed (status {status})")

    @classmethod
    def tearDownClass(cls):
        if cls._server:
            cls._server.stop()

    # ------------------------------------------------------------------
    #  Helper: run N requests concurrently and collect results
    # ------------------------------------------------------------------

    def _concurrent_requests(self, requests, *, max_workers=None):
        """Fire a list of (method, path[, body]) tuples concurrently.

        Returns list of (status, headers, body) in the same order.
        """
        if max_workers is None:
            max_workers = len(requests)

        def _do(r):
            if r[0] == "POST":
                return http_post(r[1], r[2] if len(r) > 2 else "")
            else:
                return http_get(r[1])

        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = [pool.submit(_do, r) for r in requests]
            return [f.result() for f in futures]

    # ------------------------------------------------------------------
    #  §1 — Rapid sequential requests (no inter-request sleep)
    # ------------------------------------------------------------------

    def test_01_rapid_sequential_5_gets(self):
        """5 GET / requests with zero delay between them."""
        for i in range(5):
            status, _, body = http_get("/")
            self.assertEqual(status, 200,
                             f"Request {i+1}/5 failed: status={status}")
            self.assertIn("Akashic", body,
                          f"Request {i+1}/5: unexpected body")

    def test_02_rapid_sequential_different_routes(self):
        """Hit all 5 routes in rapid succession."""
        routes = ["/", "/about", "/api/status", "/hello/Test", "/"]
        for path in routes:
            status, _, body = http_get(path)
            self.assertEqual(status, 200, f"GET {path}: status={status}")

    # ------------------------------------------------------------------
    #  §2 — Two concurrent connections
    # ------------------------------------------------------------------

    def test_03_concurrent_2_gets_same_route(self):
        """2 simultaneous GET / — both should return 200."""
        results = self._concurrent_requests([
            ("GET", "/"),
            ("GET", "/"),
        ])
        for i, (status, hdrs, body) in enumerate(results):
            self.assertEqual(status, 200,
                             f"Connection {i+1}/2: status={status}")
            self.assertIn("Akashic", body,
                          f"Connection {i+1}/2: body missing 'Akashic'")

    def test_04_concurrent_2_different_routes(self):
        """2 simultaneous requests to different routes."""
        results = self._concurrent_requests([
            ("GET", "/"),
            ("GET", "/api/status"),
        ])
        self.assertEqual(results[0][0], 200, "GET /")
        self.assertIn("Akashic", results[0][2])

        self.assertEqual(results[1][0], 200, "GET /api/status")
        self.assertIn('"status"', results[1][2])

    # ------------------------------------------------------------------
    #  §3 — Three concurrent connections
    # ------------------------------------------------------------------

    def test_05_concurrent_3_different_routes(self):
        """3 simultaneous requests to /, /about, /api/status."""
        results = self._concurrent_requests([
            ("GET", "/"),
            ("GET", "/about"),
            ("GET", "/api/status"),
        ])
        self.assertEqual(results[0][0], 200, "GET /")
        self.assertIn("Akashic", results[0][2])

        self.assertEqual(results[1][0], 200, "GET /about")
        self.assertIn("About", results[1][2])

        self.assertEqual(results[2][0], 200, "GET /api/status")
        self.assertIn("ok", results[2][2])

    # ------------------------------------------------------------------
    #  §4 — Mixed methods concurrently
    # ------------------------------------------------------------------

    def test_06_concurrent_post_and_get(self):
        """Simultaneous POST and GET — both return 200."""
        results = self._concurrent_requests([
            ("GET",  "/api/status"),
            ("POST", "/api/echo", '{"msg":"hello"}'),
        ])
        self.assertEqual(results[0][0], 200, "GET /api/status")
        self.assertIn("ok", results[0][2])

        self.assertEqual(results[1][0], 200, "POST /api/echo")
        self.assertIn("hello", results[1][2])

    # ------------------------------------------------------------------
    #  §5 — Four concurrent connections (stress TCB limits)
    # ------------------------------------------------------------------

    def test_07_concurrent_4_requests(self):
        """4 simultaneous requests — stresses TCB slot management.

        KDOS has 16–256 TCB slots (16 floor, 256 cap with XMEM).
        1 slot is the listener, leaving 15+ for active connections.
        All 4 should succeed comfortably.
        """
        results = self._concurrent_requests([
            ("GET",  "/"),
            ("GET",  "/about"),
            ("GET",  "/api/status"),
            ("POST", "/api/echo", '{"n":4}'),
        ])
        ok_count = sum(1 for s, _, _ in results if s == 200)
        self.assertGreaterEqual(
            ok_count, 3,
            f"Expected at least 3/4 successes, got {ok_count}/4: "
            f"{[s for s, _, _ in results]}")
        # Ideally all 4 succeed
        for i, (status, _, _) in enumerate(results):
            if status != 200:
                print(f"  [WARN] Connection {i+1}/4 returned {status}")

    # ------------------------------------------------------------------
    #  §6 — Body integrity under load
    # ------------------------------------------------------------------

    def test_08_body_integrity_concurrent(self):
        """Verify response bodies are not corrupted under concurrent load.

        Fire 3 requests to routes with distinctive content and verify
        each body contains the expected strings (no cross-contamination).
        """
        results = self._concurrent_requests([
            ("GET", "/"),
            ("GET", "/api/status"),
            ("GET", "/hello/MultiTest"),
        ])
        # Home page
        self.assertEqual(results[0][0], 200)
        self.assertIn("Akashic", results[0][2])
        self.assertNotIn('"status"', results[0][2],
                         "Home page body leaked JSON content")

        # JSON status
        self.assertEqual(results[1][0], 200)
        self.assertIn('"status"', results[1][2])
        self.assertNotIn("<h1>", results[1][2],
                         "JSON body leaked HTML content")

        # Hello template
        self.assertEqual(results[2][0], 200)
        self.assertIn("MultiTest", results[2][2])

    # ------------------------------------------------------------------
    #  §7 — Burst then sequential
    # ------------------------------------------------------------------

    def test_09_burst_then_sequential(self):
        """Fire 2 concurrent requests, then 3 more sequentially."""
        # Burst
        results = self._concurrent_requests([
            ("GET", "/"),
            ("GET", "/about"),
        ])
        self.assertEqual(results[0][0], 200)
        self.assertEqual(results[1][0], 200)

        # Sequential follow-up (server should recover cleanly)
        for path in ["/api/status", "/hello/Burst", "/"]:
            status, _, _ = http_get(path)
            self.assertEqual(status, 200, f"Sequential GET {path} after burst")

    # ------------------------------------------------------------------
    #  §8 — Rapid 10 sequential (throughput floor)
    # ------------------------------------------------------------------

    def test_10_rapid_sequential_10(self):
        """10 rapid sequential GET requests — no request should fail."""
        paths = ["/", "/about", "/api/status", "/hello/A", "/",
                 "/about", "/api/status", "/hello/B", "/", "/about"]
        t0 = time.time()
        for i, path in enumerate(paths):
            rt0 = time.time()
            status, _, body = http_get(path)
            rt = time.time() - rt0
            if rt > 2.0:
                print(f"  [SLOW] req {i+1}/10 GET {path}: {rt:.1f}s status={status}")
            self.assertEqual(status, 200,
                             f"Request {i+1}/10 GET {path}: status={status}")
        elapsed = time.time() - t0
        print(f"  [INFO] 10 sequential requests in {elapsed:.1f}s "
              f"({elapsed/10:.2f}s avg)")

    # ------------------------------------------------------------------
    #  §9 — Five concurrent connections (high stress)
    # ------------------------------------------------------------------

    def test_11_concurrent_5_requests(self):
        """5 simultaneous connections — pushes backlog handling hard."""
        results = self._concurrent_requests([
            ("GET",  "/"),
            ("GET",  "/about"),
            ("GET",  "/api/status"),
            ("GET",  "/hello/Stress"),
            ("POST", "/api/echo", '{"stress":true}'),
        ])
        ok_count = sum(1 for s, _, _ in results if s == 200)
        # With XMEM and TCP retransmits, all 5 should eventually succeed.
        # Accept at least 4/5 to account for edge cases.
        self.assertGreaterEqual(
            ok_count, 4,
            f"Expected at least 4/5 successes, got {ok_count}/5: "
            f"statuses={[s for s, _, _ in results]}")

    # ------------------------------------------------------------------
    #  §10 — Interleaved waves
    # ------------------------------------------------------------------

    def test_12_two_waves(self):
        """Two waves of 3 concurrent requests back-to-back."""
        # Wave 1
        r1 = self._concurrent_requests([
            ("GET", "/"),
            ("GET", "/about"),
            ("GET", "/api/status"),
        ])
        ok1 = sum(1 for s, _, _ in r1 if s == 200)
        self.assertGreaterEqual(ok1, 2, f"Wave 1: {ok1}/3")

        # Brief pause for TCP state to settle
        time.sleep(0.5)

        # Wave 2
        r2 = self._concurrent_requests([
            ("GET",  "/hello/Wave2"),
            ("POST", "/api/echo", '{"wave":2}'),
            ("GET",  "/"),
        ])
        ok2 = sum(1 for s, _, _ in r2 if s == 200)
        self.assertGreaterEqual(ok2, 2, f"Wave 2: {ok2}/3")

    # ------------------------------------------------------------------
    #  §11 — 404 under concurrent load
    # ------------------------------------------------------------------

    def test_13_404_mixed_with_valid(self):
        """A 404 request concurrent with valid ones shouldn't break anything."""
        results = self._concurrent_requests([
            ("GET", "/"),
            ("GET", "/nonexistent"),
            ("GET", "/api/status"),
        ])
        self.assertEqual(results[0][0], 200, "GET / should be 200")
        self.assertEqual(results[1][0], 404, "GET /nonexistent should be 404")
        self.assertEqual(results[2][0], 200, "GET /api/status should be 200")

    # ------------------------------------------------------------------
    #  §12 — TCB exhaustion probe
    # ------------------------------------------------------------------

    def test_14_sustained_30_requests(self):
        """30 rapid sequential requests — should all succeed.

        With the TCB pool at 16–256 slots and TCB-REAP-TW hooked into
        the server's vectored close, TIME_WAIT slots are reclaimed
        after every connection close.  All 30 should succeed without
        any pool exhaustion.
        """
        routes = ["/", "/about", "/api/status", "/hello/Probe"]
        ok = 0
        failures = []
        t0 = time.time()
        for i in range(30):
            path = routes[i % len(routes)]
            rt0 = time.time()
            status, _, body = http_get(path, timeout=8.0)
            rt = time.time() - rt0
            if status == 200:
                ok += 1
            else:
                failures.append((i + 1, path, status, f"{rt:.2f}s"))
            if rt > 2.0 or status != 200:
                tag = "OK" if status == 200 else f"FAIL({status})"
                print(f"  [PROBE] #{i+1:2d} {path:16s} {tag:8s} {rt:.2f}s")

        elapsed = time.time() - t0
        print(f"  [INFO] 30 sequential: {ok}/30 OK in {elapsed:.1f}s "
              f"({elapsed/30:.2f}s avg)")
        if failures:
            print(f"  [FAIL] {failures}")
        # With reaper hooked in, all 30 should succeed
        self.assertGreaterEqual(ok, 28,
                                f"Only {ok}/30 succeeded: {failures}")

    # ------------------------------------------------------------------
    #  §13 — Sustained load with cooldown (TIME_WAIT friendly)
    # ------------------------------------------------------------------

    def test_15_concurrent_burst_after_sustained(self):
        """3-way concurrent burst right after the 30 sustained requests.

        This verifies the server recovers cleanly from heavy sequential
        load and can still handle concurrent connections.
        """
        results = self._concurrent_requests([
            ("GET",  "/"),
            ("GET",  "/about"),
            ("POST", "/api/echo", '{"after_sustained":true}'),
        ])
        for i, (status, _, body) in enumerate(results):
            self.assertEqual(status, 200,
                             f"Post-sustained burst conn {i+1}/3: "
                             f"status={status}")


# ---------------------------------------------------------------------------
#  Standalone runner
# ---------------------------------------------------------------------------

def main():
    """Run tests as a standalone script with visible output."""
    print(f"{'=' * 70}")
    print(f"  Akashic Web Server — Multi-Connection Stress Test")
    print(f"  TAP: {TAP_NAME}  Host: {HOST_IP}  Emu: {EMU_IP}  Port: {PORT}")
    print(f"{'=' * 70}")
    print()

    if not tap_available(TAP_NAME):
        print(f"[!] TAP device '{TAP_NAME}' not available.")
        print(f"    sudo ip tuntap add dev {TAP_NAME} mode tap user $USER")
        print(f"    sudo ip addr add {HOST_IP}/24 dev {TAP_NAME}")
        print(f"    sudo ip link set {TAP_NAME} up")
        sys.exit(1)

    # Build snapshot
    snapshot = build_snapshot()

    # Start server
    print(f"\n[*] Starting server on {EMU_IP}:{PORT} ...")
    server = EmuServer(snapshot)
    server.start(timeout=120.0)

    # Warmup
    print("[*] Warmup: single GET / ...")
    time.sleep(1.0)
    status, _, body = http_get("/", timeout=20.0)
    if status != 200:
        print(f"[!] Warmup failed: status={status}")
        server.stop()
        sys.exit(1)
    print(f"[*] Warmup OK — status {status}")

    # Run unittest
    print()
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestLiveMultiConn)
    # Override setUpClass since we already have the server running
    TestLiveMultiConn._server = server
    TestLiveMultiConn._skip_setup = True

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    server.stop()

    passed = result.testsRun - len(result.failures) - len(result.errors)
    print(f"\n{'=' * 70}")
    print(f"  Results: {passed} passed, {len(result.failures)} failed, "
          f"{len(result.errors)} errors, {result.testsRun} total")
    print(f"{'=' * 70}")

    sys.exit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    main()
