#!/usr/bin/env python3
"""Test suite for akashic-web-middleware Forth library (web/middleware.f).

Tests:
  Compile      — all words compile without error
  MW-USE       — add middleware to chain
  MW-CLEAR     — reset chain
  MW-RUN       — chain execution, FIFO ordering
  MW-LOG       — logging output
  MW-CORS      — CORS headers + OPTIONS handling
  MW-JSON-BODY — content-type validation
  MW-BASIC-AUTH — HTTP Basic authentication
  MW-STATIC    — static file serving (extension/MIME/prefix)
  Chaining     — multiple middleware together
  Integration  — plug into server dispatch

NOTE: S" only works inside colon definitions in this BIOS.
"""
import os, sys, time, base64

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F      = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HDR_F      = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
DT_F       = os.path.join(ROOT_DIR, "akashic", "utils", "datetime.f")
TBL_F      = os.path.join(ROOT_DIR, "akashic", "utils", "table.f")
REQ_F      = os.path.join(ROOT_DIR, "akashic", "web", "request.f")
RESP_F     = os.path.join(ROOT_DIR, "akashic", "web", "response.f")
RTR_F      = os.path.join(ROOT_DIR, "akashic", "web", "router.f")
SRV_F      = os.path.join(ROOT_DIR, "akashic", "web", "server.f")
MW_F       = os.path.join(ROOT_DIR, "akashic", "web", "middleware.f")
B64_F      = os.path.join(ROOT_DIR, "akashic", "net", "base64.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ──

_snapshot = None

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

def _next_line_chunk(data, pos):
    nl = data.find(b'\n', pos)
    return data[pos:nl+1] if nl != -1 else data[pos:]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b: buf.append(b)
    return buf

def uart_text(buf):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in buf)

def save_cpu_state(cpu):
    return {k: getattr(cpu, k) for k in
            ['pc','psel','xsel','spsel','flag_z','flag_c','flag_n','flag_v',
             'flag_p','flag_g','flag_i','flag_s','d_reg','q_out','t_reg',
             'ivt_base','ivec_id','trap_addr','halted','idle','cycle_count',
             '_ext_modifier']} | {'regs': list(cpu.regs)}

def restore_cpu_state(cpu, state):
    cpu.regs[:] = state['regs']
    for k, v in state.items():
        if k != 'regs':
            setattr(cpu, k, v)

def build_snapshot():
    global _snapshot
    if _snapshot: return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + libs + server.f + middleware.f ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    url_lines  = _load_forth_lines(URL_F)
    hdr_lines  = _load_forth_lines(HDR_F)
    dt_lines   = _load_forth_lines(DT_F)
    tbl_lines  = _load_forth_lines(TBL_F)
    b64_lines  = _load_forth_lines(B64_F)
    req_lines  = _load_forth_lines(REQ_F)
    resp_lines = _load_forth_lines(RESP_F)
    rtr_lines  = _load_forth_lines(RTR_F)
    srv_lines  = _load_forth_lines(SRV_F)
    mw_lines   = _load_forth_lines(MW_F)
    helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Mock SEND for response.f — TYPE to UART
        ': _RESP-SEND-MOCK  ( addr len -- ) TYPE ;',
        "' _RESP-SEND-MOCK _RESP-SEND-XT !",
        # Mock socket ops for server.f — no-ops
        ': _SRV-SOCKET-MOCK  ( type -- sd ) DROP 1 ;',
        "' _SRV-SOCKET-MOCK _SRV-SOCKET-XT !",
        ': _SRV-BIND-MOCK  ( sd port -- ior ) 2DROP 0 ;',
        "' _SRV-BIND-MOCK _SRV-BIND-XT !",
        ': _SRV-LISTEN-MOCK  ( sd -- ior ) DROP 0 ;',
        "' _SRV-LISTEN-MOCK _SRV-LISTEN-XT !",
        ': _SRV-ACCEPT-MOCK  ( sd -- new-sd ) DROP -1 ;',
        "' _SRV-ACCEPT-MOCK _SRV-ACCEPT-XT !",
        ': _SRV-RECV-MOCK  ( sd addr max -- actual ) 2DROP DROP 0 ;',
        "' _SRV-RECV-MOCK _SRV-RECV-XT !",
        ': _SRV-CLOSE-MOCK  ( sd -- ) DROP ;',
        "' _SRV-CLOSE-MOCK _SRV-CLOSE-XT !",
        ': _SRV-POLL-MOCK  ( -- ) ;',
        "' _SRV-POLL-MOCK _SRV-POLL-XT !",
        ': _SRV-IDLE-MOCK  ( -- ) ;',
        "' _SRV-IDLE-MOCK _SRV-IDLE-XT !",
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    all_lines = (kdos_lines + ["ENTER-USERLAND"] +
                 str_lines + url_lines + hdr_lines + dt_lines +
                 tbl_lines + b64_lines + req_lines + resp_lines + rtr_lines +
                 srv_lines + mw_lines + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 900_000_000
    while steps < mx:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)
    text = uart_text(buf)
    errs = [l for l in text.strip().split('\n') if '?' in l and 'not found' in l.lower()]
    if errs:
        print("[!] Compilation errors:")
        for ln in errs[-10:]: print(f"    {ln}")
    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode(); pos = 0; steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted: break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else: break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)


def tstr_compiled(s):
    """Build Forth code to construct string s in _TB via TR/TC.
    Returns list of Forth lines within line length limits."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp == -1: sp = 70
        lines.append(full[:sp])
        full = full[sp:].lstrip()
    if full: lines.append(full)
    return lines


# Helper: build a minimal HTTP request string for REQ-PARSE
def http_request(method="GET", path="/", headers=None, body=""):
    """Return tstr_compiled lines for a minimal HTTP request."""
    h = headers or {}
    req = f"{method} {path} HTTP/1.1\r\n"
    for k, v in h.items():
        req += f"{k}: {v}\r\n"
    req += "\r\n"
    req += body
    return tstr_compiled(req)


# ── Test Infrastructure ──

_pass_count = 0
_fail_count = 0

def check(label, lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    out = run_forth(lines)
    clean = out.strip()
    if check_fn:
        ok = check_fn(clean)
    else:
        ok = expected in clean if expected else True
    if ok:
        _pass_count += 1
        print(f"  [PASS] {label}")
    else:
        _fail_count += 1
        print(f"  [FAIL] {label}")
        if expected is not None:
            print(f"         expected: {repr(expected)}")
        tail = clean.split('\n')[-5:]
        print(f"         got (last lines): {tail}")


# =====================================================================
#  Tests — Compilation
# =====================================================================

def test_compile():
    print("\n--- Compile ---")
    for word in ['MW-USE', 'MW-CLEAR', 'MW-RUN',
                 'MW-LOG', 'MW-CORS', 'MW-JSON-BODY',
                 'MW-BASIC-AUTH', 'MW-BASIC-AUTH-SET',
                 'MW-STATIC', 'MW-STATIC-SET',
                 '_MW-STATIC-EXT', '_MW-STATIC-MIME', '_MW-SOPEN']:
        check(f"{word} exists",
              [f"' {word} ."],
              check_fn=lambda t: "not found" not in t.lower())


# =====================================================================
#  Tests — Chain Basics
# =====================================================================

def test_chain_basics():
    print("\n--- Chain Basics ---")

    # MW-RUN with no middleware → ROUTE-DISPATCH (which sends 404 for no routes)
    check("MW-RUN empty chain → ROUTE-DISPATCH",
          [': _T MW-CLEAR ROUTE-CLEAR'] +
          http_request("GET", "/nowhere") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN',
           '  _RESP-CODE @ . ; _T'],
          "404 ")

    # MW-USE + MW-RUN with a simple tracing middleware
    check("Single middleware executes",
          [': _mw-trace  ( next-xt -- )',
           '  ." BEFORE " EXECUTE ." AFTER " ;',
           ': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] _mw-trace MW-USE"] +
          http_request("GET", "/test") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "BEFORE")

    check("Single middleware after-hook runs",
          [': _mw-trace2  ( next-xt -- )',
           '  ." B " EXECUTE ." A " ;',
           ': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] _mw-trace2 MW-USE"] +
          http_request("GET", "/test") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "A ")

    # MW-CLEAR removes middleware
    check("MW-CLEAR resets chain",
          [': _mw-trace3  ( next-xt -- )',
           '  ." TRACE " EXECUTE ;',
           ': _T MW-CLEAR',
           "  ['] _mw-trace3 MW-USE",
           '  MW-CLEAR',
           '  _MW-COUNT @ . ; _T'],
          "0 ")


def test_chain_ordering():
    print("\n--- Chain Ordering ---")

    # Two middleware in FIFO order
    check("Two middleware FIFO order",
          [': _mw-A  ( next-xt -- )  ." A " EXECUTE ;',
           ': _mw-B  ( next-xt -- )  ." B " EXECUTE ;',
           ': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] _mw-A MW-USE",
           "  ['] _mw-B MW-USE"] +
          http_request("GET", "/order") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "A B ")

    # Three middleware with pre and post
    check("Three middleware pre/post ordering",
          [': _mw-1  ( next-xt -- )  ." 1> " EXECUTE ." <1 " ;',
           ': _mw-2  ( next-xt -- )  ." 2> " EXECUTE ." <2 " ;',
           ': _mw-3  ( next-xt -- )  ." 3> " EXECUTE ." <3 " ;',
           ': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] _mw-1 MW-USE",
           "  ['] _mw-2 MW-USE",
           "  ['] _mw-3 MW-USE"] +
          http_request("GET", "/deep") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "1> 2> 3>")

    check("Three middleware post in reverse",
          [': _mw-1b  ( next-xt -- )  ." 1> " EXECUTE ." <1 " ;',
           ': _mw-2b  ( next-xt -- )  ." 2> " EXECUTE ." <2 " ;',
           ': _mw-3b  ( next-xt -- )  ." 3> " EXECUTE ." <3 " ;',
           ': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] _mw-1b MW-USE",
           "  ['] _mw-2b MW-USE",
           "  ['] _mw-3b MW-USE"] +
          http_request("GET", "/deep") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "<3 <2 <1 ")


def test_short_circuit():
    print("\n--- Short Circuit ---")

    # Middleware that skips next (does not call next-xt)
    check("Middleware can skip next",
          [': _mw-block  ( next-xt -- )  DROP ." BLOCKED " ;',
           ': _mw-after  ( next-xt -- )  ." NEVER " EXECUTE ;',
           ': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] _mw-block MW-USE",
           "  ['] _mw-after MW-USE"] +
          http_request("GET", "/blocked") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "BLOCKED ")

    check("Blocked middleware skips second",
          [': _mw-block2  ( next-xt -- )  DROP ." STOP " ;',
           ': _mw-after2  ( next-xt -- )  ." ZZQ " EXECUTE ;',
           ': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] _mw-block2 MW-USE",
           "  ['] _mw-after2 MW-USE"] +
          http_request("GET", "/blocked") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          check_fn=lambda t: "ZZQ" not in t.split("_T")[-1] and "STOP" in t)


# =====================================================================
#  Tests — MW-CORS
# =====================================================================

def test_mw_cors():
    print("\n--- MW-CORS ---")

    # OPTIONS request → 204, CORS headers, no route dispatch
    check("MW-CORS OPTIONS → 204",
          [': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] MW-CORS MW-USE"] +
          http_request("OPTIONS", "/api") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "204")

    check("MW-CORS OPTIONS includes Allow-Origin header",
          [': _T MW-CLEAR ROUTE-CLEAR',
           "  ['] MW-CORS MW-USE"] +
          http_request("OPTIONS", "/api") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "Access-Control-Allow-Origin")

    # GET request → adds CORS headers AND calls next (route dispatch)
    check("MW-CORS GET → calls next + CORS headers",
          [': _handler  200 RESP-STATUS S" text/plain"',
           '  RESP-CONTENT-TYPE S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route',
           "  S\" GET\" S\" /api\" ['] _handler ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route',
           "  ['] MW-CORS MW-USE"] +
          http_request("GET", "/api") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "200 OK")

    check("MW-CORS GET includes body",
          [': _handler2  200 RESP-STATUS S" text/plain"',
           '  RESP-CONTENT-TYPE S" hello" RESP-BODY RESP-SEND ;',
           ': _setup-route2',
           "  S\" GET\" S\" /test\" ['] _handler2 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route2',
           "  ['] MW-CORS MW-USE"] +
          http_request("GET", "/test") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "hello")


# =====================================================================
#  Tests — MW-JSON-BODY
# =====================================================================

def test_mw_json_body():
    print("\n--- MW-JSON-BODY ---")

    # Non-JSON content type → passthrough (next is called)
    check("MW-JSON-BODY non-JSON → passthrough",
          [': _handler3  200 RESP-STATUS S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route3',
           "  S\" POST\" S\" /data\" ['] _handler3 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route3',
           "  ['] MW-JSON-BODY MW-USE"] +
          http_request("POST", "/data",
                       {"Content-Type": "text/plain"},
                       "hello") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "200 OK")

    # JSON with body → passthrough
    check("MW-JSON-BODY JSON with body → passthrough",
          [': _handler4  200 RESP-STATUS S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route4',
           "  S\" POST\" S\" /json\" ['] _handler4 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route4',
           "  ['] MW-JSON-BODY MW-USE"] +
          http_request("POST", "/json",
                       {"Content-Type": "application/json"},
                       '{"key":"val"}') +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "200 OK")

    # JSON with empty body → 400
    check("MW-JSON-BODY JSON empty body → 400",
          [': _handler5  200 RESP-STATUS S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route5',
           "  S\" POST\" S\" /json\" ['] _handler5 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route5',
           "  ['] MW-JSON-BODY MW-USE"] +
          http_request("POST", "/json",
                       {"Content-Type": "application/json"}) +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "400")

    # No content-type at all → passthrough
    check("MW-JSON-BODY no content-type → passthrough",
          [': _handler6  200 RESP-STATUS S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route6',
           "  S\" GET\" S\" /plain\" ['] _handler6 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route6',
           "  ['] MW-JSON-BODY MW-USE"] +
          http_request("GET", "/plain") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "200 OK")


# =====================================================================
#  Tests — MW-LOG
# =====================================================================

def test_mw_log():
    print("\n--- MW-LOG ---")

    # Log output should contain method and path
    check("MW-LOG outputs method and path",
          [': _handler7  200 RESP-STATUS S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route7',
           "  S\" GET\" S\" /logme\" ['] _handler7 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route7',
           "  ['] MW-LOG MW-USE"] +
          http_request("GET", "/logme") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "GET /logme")

    check("MW-LOG outputs status code",
          [': _handler8  200 RESP-STATUS S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route8',
           "  S\" GET\" S\" /logme\" ['] _handler8 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route8',
           "  ['] MW-LOG MW-USE"] +
          http_request("GET", "/logme") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "200")

    check("MW-LOG outputs ms timing",
          [': _handler9  200 RESP-STATUS S" ok" RESP-BODY RESP-SEND ;',
           ': _setup-route9',
           "  S\" GET\" S\" /logme\" ['] _handler9 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route9',
           "  ['] MW-LOG MW-USE"] +
          http_request("GET", "/logme") +
          ['  TA REQ-PARSE',
           '  RESP-CLEAR',
           '  MW-RUN ; _T'],
          "ms)")


# =====================================================================
#  Tests — Integration: MW-RUN as server dispatch
# =====================================================================

def test_integration():
    print("\n--- Integration ---")

    # Plug MW-RUN into server dispatch via SRV-SET-DISPATCH
    check("SRV-SET-DISPATCH with MW-RUN",
          [": _T ['] MW-RUN SRV-SET-DISPATCH",
           '  _SRV-DISPATCH-XT @ . ; _T'],
          check_fn=lambda t: "not found" not in t.lower())

    # Full pipeline: MW-CORS + route via SRV-HANDLE-BUF
    check("Full pipeline: CORS MW + route handler",
          [': _handler10  200 RESP-STATUS',
           '  S" text/plain" RESP-CONTENT-TYPE',
           '  S" pong" RESP-BODY RESP-SEND ;',
           ': _setup-route10',
           "  S\" GET\" S\" /ping\" ['] _handler10 ROUTE ;",
           ': _T MW-CLEAR ROUTE-CLEAR _setup-route10',
           "  ['] MW-CORS MW-USE",
           "  ['] MW-RUN SRV-SET-DISPATCH"] +
          http_request("GET", "/ping") +
          ['  TA SRV-HANDLE-BUF ; _T'],
          "pong")


# =====================================================================
#  Helpers — Forth byte array builder
# =====================================================================

def _ba_lines(name, s):
    """Return Forth lines creating a byte array with contents of string s."""
    lines = [f'CREATE {name} {len(s)} ALLOT']
    for i, ch in enumerate(s):
        lines.append(f'{ord(ch)} {name} {i} + C!')
    return lines


def _b64_creds(user, password):
    """Base64-encode user:password for HTTP Basic auth."""
    return base64.b64encode(f"{user}:{password}".encode()).decode()


# =====================================================================
#  Tests — MW-BASIC-AUTH
# =====================================================================

def test_mw_basic_auth():
    print("\n--- MW-BASIC-AUTH ---")

    # Setup: create byte arrays for "admin" and "secret" credentials
    cred_setup = (
        _ba_lines('_AU', 'admin') +
        _ba_lines('_AP', 'secret') +
        [': _cred-set _AU 5 _AP 6 MW-BASIC-AUTH-SET ;']
    )

    # Handler for authenticated route
    auth_handler = [
        ': _authed  200 RESP-STATUS S" text/plain"',
        '  RESP-CONTENT-TYPE S" welcome" RESP-BODY RESP-SEND ;',
        ': _setup-auth-route',
        "  S\" GET\" S\" /secret\" ['] _authed ROUTE ;",
    ]

    b64_valid = _b64_creds("admin", "secret")

    # 1. Valid creds → 200 + body
    check("MW-BASIC-AUTH valid → 200",
          cred_setup + auth_handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-auth-route _cred-set',
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("GET", "/secret",
                       {"Authorization": f"Basic {b64_valid}"}) +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "welcome")

    # 2. Missing Authorization → 401
    check("MW-BASIC-AUTH missing → 401",
          cred_setup + auth_handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-auth-route _cred-set',
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("GET", "/secret") +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "401")

    # 3. Missing Auth → includes WWW-Authenticate header
    check("MW-BASIC-AUTH 401 has WWW-Authenticate",
          cred_setup + auth_handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-auth-route _cred-set',
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("GET", "/secret") +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "WWW-Authenticate")

    # 4. Wrong password → 403
    b64_wrong_pass = _b64_creds("admin", "wrong")
    check("MW-BASIC-AUTH wrong pass → 403",
          cred_setup + auth_handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-auth-route _cred-set',
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("GET", "/secret",
                       {"Authorization": f"Basic {b64_wrong_pass}"}) +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "403")

    # 5. Wrong user → 403
    b64_wrong_user = _b64_creds("nobody", "secret")
    check("MW-BASIC-AUTH wrong user → 403",
          cred_setup + auth_handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-auth-route _cred-set',
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("GET", "/secret",
                       {"Authorization": f"Basic {b64_wrong_user}"}) +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "403")

    # 6. Bearer scheme → 403 (not "Basic ")
    check("MW-BASIC-AUTH Bearer → 403",
          cred_setup + auth_handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-auth-route _cred-set',
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("GET", "/secret",
                       {"Authorization": "Bearer sometoken"}) +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "403")


# =====================================================================
#  Tests — MW-STATIC helpers (extension + MIME)
# =====================================================================

def test_mw_static_mime():
    print("\n--- MW-STATIC MIME ---")

    # Test _MW-STATIC-MIME with different extensions
    cases = [
        ('html', 'text/html'),
        ('htm',  'text/html'),
        ('css',  'text/css'),
        ('js',   'application/javascript'),
        ('json', 'application/json'),
        ('txt',  'text/plain'),
        ('png',  'image/png'),
        ('bin',  'application/octet-stream'),
    ]
    for ext, expected_mime in cases:
        ba = _ba_lines('_EX', ext)
        check(f"MIME .{ext} → {expected_mime}",
              ba +
              [f': _T _EX {len(ext)} _MW-STATIC-MIME TYPE ; _T'],
              expected_mime)


def test_mw_static_ext():
    print("\n--- MW-STATIC EXT ---")

    cases = [
        ('index.html', 'html'),
        ('style.css',  'css'),
        ('app.min.js', 'js'),
    ]
    for fname, expected_ext in cases:
        ba = _ba_lines('_FN', fname)
        check(f"EXT {fname} → {expected_ext}",
              ba +
              [f': _T _FN {len(fname)} _MW-STATIC-EXT TYPE ; _T'],
              expected_ext)

    # No extension → 0 0 (nothing printed)
    ba = _ba_lines('_FN2', 'Makefile')
    check("EXT no-dot → empty",
          ba +
          [': _T _FN2 8 _MW-STATIC-EXT DUP 0= IF',
           '  2DROP ." NOEXT" ELSE TYPE THEN ; _T'],
          "NOEXT")


def test_mw_static_prefix():
    print("\n--- MW-STATIC Prefix ---")

    # Handler for fallthrough
    handler_setup = [
        ': _fallback  200 RESP-STATUS S" text/plain"',
        '  RESP-CONTENT-TYPE S" fell-through" RESP-BODY RESP-SEND ;',
        ': _setup-fb-route',
        "  S\" GET\" S\" /api\" ['] _fallback ROUTE ;",
    ]

    # MW-STATIC unconfigured → falls through to next (handler)
    check("MW-STATIC unconfigured → fallthrough",
          handler_setup +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-fb-route',
           '  0 _MW-STATIC-PFX-A !',  # ensure unconfigured
           "  ['] MW-STATIC MW-USE"] +
          http_request("GET", "/api") +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "fell-through")

    # MW-STATIC prefix doesn't match → falls through
    prefix_setup = _ba_lines('_SP', '/static/')
    check("MW-STATIC non-matching path → fallthrough",
          handler_setup + prefix_setup +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-fb-route',
           '  _SP 8 MW-STATIC-SET',
           "  ['] MW-STATIC MW-USE"] +
          http_request("GET", "/api") +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "fell-through")

    # MW-STATIC prefix matches but no FS → falls through (FS-OK=0)
    check("MW-STATIC no FS → fallthrough",
          handler_setup + prefix_setup +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-fb-route',
           '  _SP 8 MW-STATIC-SET',
           '  0 FS-OK !',  # ensure FS not loaded
           "  ['] MW-STATIC MW-USE"] +
          http_request("GET", "/static/index.html") +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          check_fn=lambda t: "404" in t or "fell-through" in t)


# =====================================================================
#  Tests — MW-BASIC-AUTH + MW-CORS integration
# =====================================================================

def test_auth_cors_integration():
    print("\n--- Auth+CORS Integration ---")

    cred_setup = (
        _ba_lines('_AU2', 'admin') +
        _ba_lines('_AP2', 'secret') +
        [': _cred-set2 _AU2 5 _AP2 6 MW-BASIC-AUTH-SET ;']
    )
    handler = [
        ': _authed2  200 RESP-STATUS S" text/plain"',
        '  RESP-CONTENT-TYPE S" protected" RESP-BODY RESP-SEND ;',
        ': _setup-protected',
        "  S\" GET\" S\" /api\" ['] _authed2 ROUTE ;",
    ]

    # OPTIONS preflight should bypass auth (CORS first, auth second)
    check("OPTIONS bypasses auth (CORS before AUTH)",
          cred_setup + handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-protected _cred-set2',
           "  ['] MW-CORS MW-USE",
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("OPTIONS", "/api") +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "204")

    # GET with auth → goes through CORS and AUTH to handler
    b64 = _b64_creds("admin", "secret")
    check("GET with auth through CORS+AUTH → 200",
          cred_setup + handler +
          [': _T MW-CLEAR ROUTE-CLEAR _setup-protected _cred-set2',
           "  ['] MW-CORS MW-USE",
           "  ['] MW-BASIC-AUTH MW-USE"] +
          http_request("GET", "/api",
                       {"Authorization": f"Basic {b64}"}) +
          ['  TA REQ-PARSE RESP-CLEAR MW-RUN ; _T'],
          "protected")


# =====================================================================
#  Main
# =====================================================================

def main():
    build_snapshot()
    test_compile()
    test_chain_basics()
    test_chain_ordering()
    test_short_circuit()
    test_mw_cors()
    test_mw_json_body()
    test_mw_log()
    test_mw_basic_auth()
    test_mw_static_mime()
    test_mw_static_ext()
    test_mw_static_prefix()
    test_auth_cors_integration()
    test_integration()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    return 1 if _fail_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
