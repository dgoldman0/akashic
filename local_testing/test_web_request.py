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
"""Test suite for akashic-web-request Forth library (web/request.f).

Tests:
  Layer 0  — REQ-PARSE-LINE (method, path, query, version)
  Layer 1  — REQ-PARSE-HEADERS + REQ-HEADER lookups
  Layer 2  — REQ-PARSE-BODY, REQ-JSON-BODY, REQ-FORM-BODY
  Layer 3  — REQ-PARSE (full parse)
  Layer 4  — REQ-PARAM-FIND, REQ-PARAM?
  Layer 5  — REQ-GET?, REQ-POST?, etc.
  Error    — REQ-FAIL, REQ-OK?, REQ-CLEAR-ERR
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F      = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HDR_F      = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
REQ_F      = os.path.join(ROOT_DIR, "akashic", "web", "request.f")
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
    print("[*] Building snapshot: BIOS + KDOS + string.f + url.f + headers.f + request.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    str_lines  = _load_forth_lines(STR_F)
    url_lines  = _load_forth_lines(URL_F)
    hdr_lines  = _load_forth_lines(HDR_F)
    req_lines  = _load_forth_lines(REQ_F)
    helpers = [
        'CREATE _TB 2048 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + event_lines + sem_lines + guard_lines + str_lines + url_lines + hdr_lines + req_lines + helpers) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 600_000_000
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
        for ln in errs[-5:]: print(f"    {ln}")
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

def tstr(s):
    """Build string s in _TB via TR/TC.  Returns list of Forth lines."""
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

def http_request(method, path, headers, body=""):
    """Build raw HTTP request string in _TB via TR/TC."""
    raw = f"{method} {path} HTTP/1.1\r\n"
    for h in headers:
        raw += h + "\r\n"
    raw += "\r\n"
    raw += body
    return tstr(raw)


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

def test_error_handling():
    print("\n── Error Handling ──\n")

    check("REQ-OK? initially true",
          [': _T REQ-CLEAR-ERR REQ-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-FAIL sets error",
          [': _T 2 REQ-FAIL REQ-ERR @ . ; _T'],
          "2 ")

    check("REQ-OK? false after FAIL",
          [': _T 1 REQ-FAIL REQ-OK? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("REQ-CLEAR-ERR resets",
          [': _T 3 REQ-FAIL REQ-CLEAR-ERR REQ-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("Error constants defined",
          [': _T REQ-E-MALFORMED . REQ-E-NO-CRLF . REQ-E-TOO-LONG . ; _T'],
          "1 2 3 ")


def test_parse_line():
    print("\n── REQ-PARSE-LINE ──\n")

    # Simple GET
    check("GET / — method",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-METHOD TYPE ; _T'],
          "GET")

    check("GET / — path",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-PATH TYPE ; _T'],
          "/")

    check("GET / — version",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-VERSION TYPE ; _T'],
          "HTTP/1.1")

    check("GET / — no query",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-QUERY DUP . DROP ; _T'],
          "0 ")

    # POST method
    check("POST /api — method",
          http_request("POST", "/api/data", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-METHOD TYPE ; _T'],
          "POST")

    check("POST /api/data — path",
          http_request("POST", "/api/data", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-PATH TYPE ; _T'],
          "/api/data")

    # Path with query string
    check("GET /search?q=hello — path",
          http_request("GET", "/search?q=hello", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-PATH TYPE ; _T'],
          "/search")

    check("GET /search?q=hello — query",
          http_request("GET", "/search?q=hello", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-QUERY TYPE ; _T'],
          "q=hello")

    # Multiple query params
    check("Multiple query params",
          http_request("GET", "/api?page=2&sort=name", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-QUERY TYPE ; _T'],
          "page=2&sort=name")

    # PUT method
    check("PUT method",
          http_request("PUT", "/item/5", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-METHOD TYPE ; _T'],
          "PUT")

    # DELETE method
    check("DELETE method",
          http_request("DELETE", "/item/5", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-METHOD TYPE ; _T'],
          "DELETE")

    # Long path
    check("Long path",
          http_request("GET", "/api/v2/users/profile/settings", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-PATH TYPE ; _T'],
          "/api/v2/users/profile/settings")

    # Path length
    check("Method length",
          http_request("GET", "/hello", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-METHOD DUP . DROP ; _T'],
          "3 ")

    check("Path length",
          http_request("GET", "/hello", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-PATH DUP . DROP ; _T'],
          "6 ")

    # OPTIONS method
    check("OPTIONS method",
          http_request("OPTIONS", "/api", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-METHOD TYPE ; _T'],
          "OPTIONS")

    # PATCH method
    check("PATCH method",
          http_request("PATCH", "/user/1", ["Host: localhost"]) +
          [': _T TA REQ-PARSE-LINE REQ-METHOD TYPE ; _T'],
          "PATCH")


def test_parse_headers():
    print("\n── REQ-PARSE-HEADERS + REQ-HEADER ──\n")

    check("Find Host header",
          http_request("GET", "/", ["Host: example.com", "Accept: text/html"]) +
          [': _T TA REQ-PARSE REQ-HOST TYPE ; _T'],
          "example.com")

    check("Find Accept header",
          http_request("GET", "/", ["Host: localhost", "Accept: application/json"]) +
          [': _T TA REQ-PARSE REQ-ACCEPT TYPE ; _T'],
          "application/json")

    check("Find Content-Type",
          http_request("POST", "/api", [
              "Host: localhost",
              "Content-Type: application/json",
              "Content-Length: 2"
          ], "{}") +
          [': _T TA REQ-PARSE REQ-CONTENT-TYPE TYPE ; _T'],
          "application/json")

    check("Content-Length parsed",
          http_request("POST", "/api", [
              "Host: localhost",
              "Content-Type: application/json",
              "Content-Length: 13"
          ], '{"key":"val"}') +
          [': _T TA REQ-PARSE REQ-CONTENT-LENGTH . ; _T'],
          "13 ")

    check("Authorization header",
          http_request("GET", "/secret", [
              "Host: localhost",
              "Authorization: Bearer tok123"
          ]) +
          [': _T TA REQ-PARSE REQ-AUTH TYPE ; _T'],
          "Bearer tok123")

    check("Cookie header",
          http_request("GET", "/", [
              "Host: localhost",
              "Cookie: session=abc123"
          ]) +
          [': _T TA REQ-PARSE REQ-COOKIE TYPE ; _T'],
          "session=abc123")

    check("Custom header via REQ-HEADER",
          http_request("GET", "/", [
              "Host: localhost",
              "X-Request-ID: req-42"
          ]) +
          [': _T TA REQ-PARSE',
           'S" X-Request-ID" REQ-HEADER IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "req-42")

    check("Header not found",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'S" X-Missing" REQ-HEADER IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "NOTFOUND")

    check("Content-Length -1 when absent",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-CONTENT-LENGTH . ; _T'],
          "-1 ")


def test_parse_body():
    print("\n── REQ-PARSE-BODY ──\n")

    check("Body present",
          http_request("POST", "/api", [
              "Host: localhost",
              "Content-Length: 13"
          ], '{"key":"val"}') +
          [': _T TA REQ-PARSE REQ-BODY TYPE ; _T'],
          '{"key":"val"}')

    check("Body length",
          http_request("POST", "/api", [
              "Host: localhost",
              "Content-Length: 5"
          ], "Hello") +
          [': _T TA REQ-PARSE REQ-BODY DUP . DROP ; _T'],
          "5 ")

    check("No body on GET",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-BODY DUP . DROP ; _T'],
          "0 ")

    check("JSON body type check — matching",
          http_request("POST", "/api", [
              "Host: localhost",
              "Content-Type: application/json",
              "Content-Length: 2"
          ], "{}") +
          [': _T TA REQ-PARSE REQ-JSON-BODY DUP . TYPE ; _T'],
          check_fn=lambda out: "2 " in out and "{}" in out)

    check("JSON body type check — wrong content-type",
          http_request("POST", "/api", [
              "Host: localhost",
              "Content-Type: text/plain",
              "Content-Length: 5"
          ], "hello") +
          [': _T TA REQ-PARSE REQ-JSON-BODY DUP . DROP ; _T'],
          "0 ")

    check("Form body type check — matching",
          http_request("POST", "/login", [
              "Host: localhost",
              "Content-Type: application/x-www-form-urlencoded",
              "Content-Length: 17"
          ], "user=alice&pass=x") +
          [': _T TA REQ-PARSE REQ-FORM-BODY TYPE ; _T'],
          "user=alice&pass=x")

    check("Form body type check — wrong content-type",
          http_request("POST", "/api", [
              "Host: localhost",
              "Content-Type: application/json",
              "Content-Length: 2"
          ], "{}") +
          [': _T TA REQ-PARSE REQ-FORM-BODY DUP . DROP ; _T'],
          "0 ")

    check("Multiline body",
          http_request("POST", "/data", [
              "Host: localhost",
              "Content-Length: 11"
          ], "line1\r\nline2") +
          [': _T TA REQ-PARSE REQ-BODY DUP . DROP ; _T'],
          "11 ")


def test_full_parse():
    print("\n── REQ-PARSE (full) ──\n")

    check("Full parse GET",
          http_request("GET", "/hello?name=world", [
              "Host: example.com",
              "Accept: text/html"
          ]) +
          [': _T TA REQ-PARSE',
           'REQ-METHOD TYPE ."  " REQ-PATH TYPE ."  "',
           'REQ-QUERY TYPE ; _T'],
          "GET /hello name=world")

    check("Full parse POST with body",
          http_request("POST", "/submit", [
              "Host: localhost",
              "Content-Type: application/json",
              "Content-Length: 14"
          ], '{"name":"bob"}') +
          [': _T TA REQ-PARSE',
           'REQ-METHOD TYPE ."  " REQ-PATH TYPE ."  "',
           'REQ-BODY TYPE ; _T'],
          'POST /submit {"name":"bob"}')

    check("REQ-CLEAR resets all state",
          http_request("GET", "/test", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'REQ-CLEAR',
           'REQ-METHOD DUP . DROP',
           'REQ-PATH DUP . DROP',
           'REQ-BODY DUP . DROP ; _T'],
          "0 0 0 ")

    check("REQ-OK? true after good parse",
          http_request("GET", "/ok", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_query_params():
    print("\n── REQ-PARAM-FIND / REQ-PARAM? ──\n")

    check("Find query param 'name'",
          http_request("GET", "/search?name=alice&age=30", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'S" name" REQ-PARAM-FIND IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "alice")

    check("Find query param 'age'",
          http_request("GET", "/search?name=alice&age=30", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'S" age" REQ-PARAM-FIND IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "30")

    check("Query param not found",
          http_request("GET", "/search?name=alice", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'S" missing" REQ-PARAM-FIND IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "NOTFOUND")

    check("REQ-PARAM? true",
          http_request("GET", "/search?q=hello", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'S" q" REQ-PARAM? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-PARAM? false",
          http_request("GET", "/search?q=hello", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'S" x" REQ-PARAM? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("No query — param not found",
          http_request("GET", "/page", ["Host: localhost"]) +
          [': _T TA REQ-PARSE',
           'S" key" REQ-PARAM-FIND IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "NOTFOUND")


def test_method_checks():
    print("\n── REQ-GET? / REQ-POST? / etc. ──\n")

    check("REQ-GET? true",
          http_request("GET", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-GET? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-GET? false on POST",
          http_request("POST", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-GET? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("REQ-POST? true",
          http_request("POST", "/api", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-POST? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-PUT? true",
          http_request("PUT", "/item", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-PUT? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-DELETE? true",
          http_request("DELETE", "/item/1", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-DELETE? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-HEAD? true",
          http_request("HEAD", "/", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-HEAD? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-OPTIONS? true",
          http_request("OPTIONS", "/api", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-OPTIONS? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("REQ-PATCH? true",
          http_request("PATCH", "/user/1", ["Host: localhost"]) +
          [': _T TA REQ-PARSE REQ-PATCH? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_compile_check():
    """Verify that all public words compile without error."""
    print("\n── Compile Checks ──\n")

    check("All REQ- words compile",
          [': _T-ALL',
           '  REQ-CLEAR',
           '  REQ-METHOD 2DROP',
           '  REQ-PATH 2DROP',
           '  REQ-QUERY 2DROP',
           '  REQ-VERSION 2DROP',
           '  REQ-BODY 2DROP',
           '  REQ-HOST 2DROP',
           '  REQ-ACCEPT 2DROP',
           '  REQ-AUTH 2DROP',
           '  REQ-COOKIE 2DROP',
           '  REQ-CONTENT-TYPE 2DROP',
           '  REQ-CONTENT-LENGTH DROP',
           '  S" x" REQ-PARAM-FIND 2DROP DROP',
           '  S" x" REQ-PARAM? DROP',
           '  REQ-GET? DROP',
           '  REQ-POST? DROP',
           '  REQ-PUT? DROP',
           '  REQ-DELETE? DROP',
           '  REQ-HEAD? DROP',
           '  REQ-OPTIONS? DROP',
           '  REQ-PATCH? DROP',
           ';'],
          check_fn=lambda out: 'not found' not in out.lower())


# ── Main ──

if __name__ == "__main__":
    build_snapshot()
    test_error_handling()
    test_parse_line()
    test_parse_headers()
    test_parse_body()
    test_full_parse()
    test_query_params()
    test_method_checks()
    test_compile_check()
    print(f"\n{'='*40}")
    print(f"  {_pass} passed,  {_fail} failed")
    print(f"{'='*40}\n")
    sys.exit(1 if _fail else 0)
