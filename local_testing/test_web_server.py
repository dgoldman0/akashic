#!/usr/bin/env python3
# ┌──────────────────────────────────────────────────────────────┐
# │ HARNESS UPDATE REQUIRED (March 2026)                         │
# │                                                              │
# │ 1. BOOT-TO-IDLE: run_forth() must call boot() on a fresh    │
# │    MegapadSystem before overwriting RAM/CPU state from the   │
# │    snapshot.  Without boot(), the C++ accelerator's MMIO     │
# │    routing (UART writes) is never wired → empty output.      │
# │    Fix: save bios_code in the snapshot tuple, then in        │
# │    run_forth(): load_binary(0, bios_code), boot(), run to    │
# │    idle, THEN overwrite mem/cpu/ext from snapshot.           │
# │                                                              │
# │ 2. NO [: ;] CLOSURES: This BIOS/KDOS does not define the    │
# │    [: ... ;] anonymous quotation words.  Replace all uses    │
# │    with named helper words and ['] ticks.                    │
# │                                                              │
# │ See test_coroutine.py for the corrected pattern.             │
# └──────────────────────────────────────────────────────────────┘
"""Test suite for akashic-web-server Forth library (web/server.f).

Tests:
  Compile  — all words compile without error
  Error    — SRV-FAIL, SRV-OK?, SRV-CLEAR-ERR
  Flags    — _SRV-RUNNING, SERVE-STOP
  Options  — SRV-MAX-REQUEST, SRV-TIMEOUT
  Logging  — SRV-LOG, SRV-LOG-ENABLED
  Init     — SRV-INIT with mocked sockets
  CATCH    — exception handling around handlers
  Pipeline — SRV-HANDLE-BUF (full request→route→response)
  Params   — path & query parameter access in handlers
  Crash    — handler THROW → 500
  Dispatch — SRV-SET-DISPATCH custom dispatch

NOTE: S" only works inside colon definitions in this BIOS.
      All route registration and S" usage must be inside : ... ;
      The [\\] tick-bracket syntax is used for POSTPONE ['] inside
      compiled definitions.
"""
import os, sys, time

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
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

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
    print("[*] Building snapshot: BIOS + KDOS + libs + server.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    str_lines  = _load_forth_lines(STR_F)
    url_lines  = _load_forth_lines(URL_F)
    hdr_lines  = _load_forth_lines(HDR_F)
    dt_lines   = _load_forth_lines(DT_F)
    tbl_lines  = _load_forth_lines(TBL_F)
    req_lines  = _load_forth_lines(REQ_F)
    resp_lines = _load_forth_lines(RESP_F)
    rtr_lines  = _load_forth_lines(RTR_F)
    srv_lines  = _load_forth_lines(SRV_F)
    helpers = [
        'CREATE _TB 2048 ALLOT  VARIABLE _TL',
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
                 event_lines + sem_lines + guard_lines +
                 str_lines + url_lines + hdr_lines + dt_lines +
                 tbl_lines + req_lines + resp_lines + rtr_lines +
                 srv_lines + helpers)
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
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    buf.clear()
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
    Suitable for embedding inside a colon definition.
    Returns a list of Forth lines within line length limits."""
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


_pass = 0; _fail = 0
def check(name, forth_lines, expected=None, check_fn=None):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    ok = check_fn(clean) if check_fn else (expected in clean if expected else True)
    if ok:
        _pass += 1; print(f"  PASS  {name}")
    else:
        _fail += 1; print(f"  FAIL  {name}")
        if expected: print(f"        expected: {expected!r}")
        print(f"        got (last lines): {clean.split(chr(10))[-3:]}")


# =====================================================================
#  Tests
# =====================================================================

def test_compile():
    print("\n── Compile Check ──\n")

    check("All server words compile",
          [': _T SRV-CLEAR-ERR SRV-OK? DROP ; _T'],
          check_fn=lambda t: "not found" not in t.lower())

    check("SERVE-STOP compiles",
          [': _T SERVE-STOP ; _T'],
          check_fn=lambda t: "not found" not in t.lower())

    check("SRV-SET-DISPATCH compiles",
          [": _T ['] ROUTE-DISPATCH SRV-SET-DISPATCH ; _T"],
          check_fn=lambda t: "not found" not in t.lower())


def test_error_handling():
    print("\n── Error Handling ──\n")

    check("SRV-OK? initially true",
          [': _T SRV-CLEAR-ERR SRV-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("SRV-FAIL sets error",
          [': _T 2 SRV-FAIL SRV-ERR @ . ; _T'],
          "2 ")

    check("SRV-OK? false after FAIL",
          [': _T 1 SRV-FAIL SRV-OK? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("SRV-CLEAR-ERR resets",
          [': _T 3 SRV-FAIL SRV-CLEAR-ERR SRV-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("SRV-E-SOCKET is 1",
          [': _T SRV-E-SOCKET . ; _T'], "1 ")

    check("SRV-E-BIND is 2",
          [': _T SRV-E-BIND . ; _T'], "2 ")

    check("SRV-E-LISTEN is 3",
          [': _T SRV-E-LISTEN . ; _T'], "3 ")

    check("SRV-E-RECV is 4",
          [': _T SRV-E-RECV . ; _T'], "4 ")


def test_flags():
    print("\n── Server Flags ──\n")

    check("SERVE-STOP clears _SRV-RUNNING",
          [': _T -1 _SRV-RUNNING ! SERVE-STOP _SRV-RUNNING @ . ; _T'],
          "0 ")

    check("SRV-MAX-REQUEST is 8192",
          [': _T SRV-MAX-REQUEST . ; _T'],
          "8192 ")

    check("SRV-TIMEOUT is 5000",
          [': _T SRV-TIMEOUT . ; _T'],
          "5000 ")

    check("SRV-KEEP-ALIVE? starts 0",
          [': _T SRV-KEEP-ALIVE? @ . ; _T'],
          "0 ")


def test_logging():
    print("\n── Logging ──\n")

    # Use EMIT to print marker without S" issues
    check("SRV-LOG-ENABLED defaults to true",
          [': _T SRV-LOG-ENABLED @ IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("SRV-LOG-ENABLED can be toggled",
          [': _T 0 SRV-LOG-ENABLED !',
           '  SRV-LOG-ENABLED @ IF 1 ELSE 0 THEN .',
           '  -1 SRV-LOG-ENABLED ! ; _T'],
          "0 ")


def test_init():
    """Test SRV-INIT with mocked socket ops."""
    print("\n── SRV-INIT ──\n")

    check("SRV-INIT sets port",
          [': _T SRV-CLEAR-ERR 8080 SRV-INIT _SRV-PORT @ . ; _T'],
          "8080 ")

    check("SRV-INIT sets running flag",
          [': _T SRV-CLEAR-ERR 3000 SRV-INIT',
           '  _SRV-RUNNING @ 0<> IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("SRV-INIT OK",
          [': _T SRV-CLEAR-ERR 9000 SRV-INIT',
           '  SRV-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("SRV-INIT fails on bad socket",
          [': _SOCK-BAD ( type -- sd ) DROP -1 ;',
           "' _SOCK-BAD _SRV-SOCKET-XT !",
           ': _T SRV-CLEAR-ERR 8080 SRV-INIT',
           '  SRV-OK? IF 1 ELSE 0 THEN . SRV-ERR @ . ; _T',
           # Restore mock
           ': _SOCK-OK ( type -- sd ) DROP 1 ;',
           "' _SOCK-OK _SRV-SOCKET-XT !"],
          check_fn=lambda t: "0 " in t and "1 " in t)

    check("SRV-INIT prints listening message",
          [': _T SRV-CLEAR-ERR -1 SRV-LOG-ENABLED ! 4567 SRV-INIT ; _T'],
          check_fn=lambda t: "Listening" in t and "4567" in t)


def test_catch():
    """Test CATCH/THROW works standalone."""
    print("\n── CATCH/THROW ──\n")

    check("CATCH returns 0 on success",
          [": _ok 1 DROP ;",
           ": _T ['] _ok CATCH . ; _T"],
          "0 ")

    check("CATCH returns throw code on failure",
          [': _boom -1 THROW ;',
           ": _T ['] _boom CATCH . ; _T"],
          check_fn=lambda t: "-1" in t)


def test_handle_buf():
    """Test SRV-HANDLE-BUF: full pipeline without socket I/O.
    All S" strings and route registration inside colon defs."""
    print("\n── SRV-HANDLE-BUF (Full Pipeline) ──\n")

    req = "GET /hello HTTP/1.1\r\nHost: test\r\n\r\n"
    check("200 response via SRV-HANDLE-BUF",
          [': _h-hello',
           '  200 RESP-STATUS',
           '  S" Hello World" RESP-BODY',
           '  RESP-SEND ;',
           ': _T ROUTE-CLEAR RESP-CLEAR',
           "  S\" GET\" S\" /hello\" ['] _h-hello ROUTE"] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "200 OK" in t and "Hello World" in t)

    req2 = "GET /nope HTTP/1.1\r\nHost: test\r\n\r\n"
    check("404 on unmatched route",
          [': _T ROUTE-CLEAR RESP-CLEAR'] +
          ['  ' + l for l in tstr_compiled(req2)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "404" in t)

    req3 = "GARBAGE"
    check("400 on malformed request",
          [': _T ROUTE-CLEAR RESP-CLEAR'] +
          ['  ' + l for l in tstr_compiled(req3)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "400" in t)

    req4 = "POST /items HTTP/1.1\r\nHost: test\r\nContent-Length: 0\r\n\r\n"
    check("POST route works",
          [': _h-post 201 RESP-STATUS',
           '  S" created" RESP-BODY RESP-SEND ;',
           ': _T ROUTE-CLEAR RESP-CLEAR',
           "  S\" POST\" S\" /items\" ['] _h-post ROUTE"] +
          ['  ' + l for l in tstr_compiled(req4)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "201 Created" in t)


def test_param_routes():
    """Test path parameter routes through the full pipeline."""
    print("\n── Path Parameters via Pipeline ──\n")

    req = "GET /user/42 HTTP/1.1\r\nHost: test\r\n\r\n"
    check("Route with :id param",
          [': _h-user 200 RESP-STATUS',
           '  S" id" ROUTE-PARAM RESP-BODY RESP-SEND ;',
           ': _T ROUTE-CLEAR RESP-CLEAR',
           "  S\" GET\" S\" /user/:id\" ['] _h-user ROUTE"] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "200 OK" in t and "42" in t)

    req2 = "GET /user/abc/post/99 HTTP/1.1\r\nHost: test\r\n\r\n"
    check("Route with two params",
          [': _h-pp 200 RESP-STATUS',
           '  S" uid" ROUTE-PARAM RESP-BODY',
           '  S" -" RESP-BODY',
           '  S" pid" ROUTE-PARAM RESP-BODY',
           '  RESP-SEND ;',
           ': _T ROUTE-CLEAR RESP-CLEAR',
           "  S\" GET\" S\" /user/:uid/post/:pid\" ['] _h-pp ROUTE"] +
          ['  ' + l for l in tstr_compiled(req2)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "200 OK" in t and "abc" in t and "99" in t)


def test_handler_crash():
    """Test that a crashing handler produces 500, not a server crash."""
    print("\n── Handler Crash → 500 ──\n")

    req = "GET /crash HTTP/1.1\r\nHost: test\r\n\r\n"
    check("Throwing handler yields 500",
          [': _h-crash  -1 THROW ;',
           ': _T ROUTE-CLEAR RESP-CLEAR',
           "  S\" GET\" S\" /crash\" ['] _h-crash ROUTE"] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "500" in t)


def test_custom_dispatch():
    """Test SRV-SET-DISPATCH replaces the dispatch vector."""
    print("\n── Custom Dispatch ──\n")

    req = "GET /anything HTTP/1.1\r\nHost: test\r\n\r\n"
    check("Custom dispatch XT is called",
          [': _custom-dispatch',
           '  200 RESP-STATUS',
           '  S" custom" RESP-BODY',
           '  RESP-SEND ;',
           ': _T ROUTE-CLEAR RESP-CLEAR',
           "  ['] _custom-dispatch SRV-SET-DISPATCH"] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF',
           # Restore default dispatch
           "  ['] ROUTE-DISPATCH SRV-SET-DISPATCH ; _T"],
          check_fn=lambda t: "200 OK" in t and "custom" in t)


def test_query_params():
    """Test query parameters are accessible via REQ-PARAM-FIND."""
    print("\n── Query Parameters in Pipeline ──\n")

    req = "GET /search?q=hello HTTP/1.1\r\nHost: test\r\n\r\n"
    check("Query param accessible in handler",
          [': _h-search 200 RESP-STATUS',
           '  S" q" REQ-PARAM-FIND IF',
           '    RESP-BODY',
           '  ELSE',
           '    2DROP S" none" RESP-BODY',
           '  THEN',
           '  RESP-SEND ;',
           ': _T ROUTE-CLEAR RESP-CLEAR',
           "  S\" GET\" S\" /search\" ['] _h-search ROUTE"] +
          ['  ' + l for l in tstr_compiled(req)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "200 OK" in t and "hello" in t)


def test_multiple_requests():
    """Test that SRV-HANDLE-BUF can be called multiple times (state resets)."""
    print("\n── Multiple Sequential Requests ──\n")

    req1 = "GET /a HTTP/1.1\r\nHost: x\r\n\r\n"
    req2 = "GET /b HTTP/1.1\r\nHost: x\r\n\r\n"
    check("Two requests in sequence",
          [': _h1 200 RESP-STATUS S" first" RESP-BODY RESP-SEND ;',
           ': _h2 200 RESP-STATUS S" second" RESP-BODY RESP-SEND ;',
           ': _T ROUTE-CLEAR',
           "  S\" GET\" S\" /a\" ['] _h1 ROUTE",
           "  S\" GET\" S\" /b\" ['] _h2 ROUTE"] +
          ['  ' + l for l in tstr_compiled(req1)] +
          ['  TA SRV-HANDLE-BUF'] +
          ['  ' + l for l in tstr_compiled(req2)] +
          ['  TA SRV-HANDLE-BUF ; _T'],
          check_fn=lambda t: "first" in t and "second" in t)


def test_loop_exits():
    """Test that SRV-LOOP exits immediately when _SRV-RUNNING is 0."""
    print("\n── Accept Loop Exit ──\n")

    check("SRV-LOOP exits when _SRV-RUNNING is 0",
          [': _T 0 _SRV-RUNNING ! SRV-LOOP 42 . ; _T'],
          "42 ")


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()
    test_compile()
    test_error_handling()
    test_flags()
    test_logging()
    test_init()
    test_catch()
    test_handle_buf()
    test_param_routes()
    test_handler_crash()
    test_custom_dispatch()
    test_query_params()
    test_multiple_requests()
    test_loop_exits()
    print(f"\n{'='*40}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail else 0)
