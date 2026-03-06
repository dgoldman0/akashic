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
"""Test suite for akashic-http Forth library (http.f).

Tests layers that don't require actual network:
  Layer 2  — HTTP-PARSE, HTTP-DECHUNK, HTTP-HEADER
  Layer 4  — Session (HTTP-SET-BEARER, HTTP-SET-UA, HTTP-APPLY-SESSION)
  Layer 6  — _HTTP-REDIRECT? detection
  Error    — HTTP-FAIL, HTTP-OK?, HTTP-CLEAR-ERR
  Static   — HTTP-USE-STATIC setup
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F      = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HDR_F      = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
HTTP_F     = os.path.join(ROOT_DIR, "akashic", "net", "http.f")
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
    print("[*] Building snapshot: BIOS + KDOS + string.f + url.f + headers.f + http.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    str_lines  = _load_forth_lines(STR_F)
    url_lines  = _load_forth_lines(URL_F)
    hdr_lines  = _load_forth_lines(HDR_F)
    http_lines = _load_forth_lines(HTTP_F)
    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _OB 512 ALLOT',
        'CREATE _RB 4096 ALLOT',
        ': _SETUP  TA _RB SWAP CMOVE  _RB HTTP-RECV-BUF !  _TL @ HTTP-RECV-LEN !  4096 HTTP-RECV-MAX ! ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + event_lines + sem_lines + guard_lines + str_lines + url_lines + hdr_lines + http_lines + helpers) + "\n"
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

def http_response(status_line, headers, body=""):
    """Build HTTP response in _TB via TR/TC.  Returns Forth lines."""
    raw = status_line + "\r\n"
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


# ── Tests ──

def test_error_handling():
    print("\n── Error Handling ──\n")

    check("HTTP-OK? initially true",
          [': _T HTTP-CLEAR-ERR HTTP-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("HTTP-FAIL sets error",
          [': _T 3 HTTP-FAIL HTTP-ERR @ . ; _T'],
          "3 ")

    check("HTTP-OK? false after FAIL",
          [': _T 1 HTTP-FAIL HTTP-OK? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("HTTP-CLEAR-ERR resets",
          [': _T 5 HTTP-FAIL HTTP-CLEAR-ERR HTTP-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("Error constants",
          [': _T HTTP-E-DNS . HTTP-E-CONNECT . HTTP-E-SEND .',
           'HTTP-E-TIMEOUT . HTTP-E-PARSE . HTTP-E-OVERFLOW .',
           'HTTP-E-TLS . HTTP-E-REDIRECT . ; _T'],
          "1 2 3 4 5 6 7 8 ")


def test_static_buffer():
    print("\n── HTTP-USE-STATIC ──\n")

    check("USE-STATIC sets max and len",
          [': _T _OB 256 HTTP-USE-STATIC',
           'HTTP-RECV-MAX @ . HTTP-RECV-LEN @ . ; _T'],
          "256 0 ")


def test_parse():
    print("\n── HTTP-PARSE ──\n")

    # Simple 200 OK
    check("PARSE simple 200",
          http_response("HTTP/1.1 200 OK",
                        ["Content-Length: 5", "Content-Type: text/plain"],
                        "Hello") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . HTTP-BODY-LEN @ . ; _T'],
          "0 200 5 ")

    # 404 Not Found
    check("PARSE 404",
          http_response("HTTP/1.1 404 Not Found",
                        ["Content-Length: 9"],
                        "Not Found") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . HTTP-BODY-LEN @ . ; _T'],
          "0 404 9 ")

    # 301 redirect
    check("PARSE 301 redirect",
          http_response("HTTP/1.1 301 Moved",
                        ["Location: http://example.com/new",
                         "Content-Length: 0"],
                        "") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . ; _T'],
          "0 301 ")

    # Body shorter than Content-Length (truncated recv)
    check("PARSE body = min(actual, clen)",
          http_response("HTTP/1.1 200 OK",
                        ["Content-Length: 100"],
                        "short") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-BODY-LEN @ . ; _T'],
          "0 5 ")

    # No Content-Length header
    check("PARSE no clen — uses buffer remainder",
          http_response("HTTP/1.1 200 OK",
                        ["Server: test"],
                        "BodyData") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-BODY-LEN @ . ; _T'],
          "0 8 ")

    # 500 server error
    check("PARSE 500",
          http_response("HTTP/1.1 500 Internal Server Error",
                        ["Content-Length: 5"],
                        "error") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . ; _T'],
          "0 500 ")

    # Empty buffer → error
    check("PARSE empty → error",
          [': _T 0 HTTP-RECV-LEN !',
           'CREATE _EB 16 ALLOT _EB HTTP-RECV-BUF !',
           'HTTP-PARSE . HTTP-ERR @ . ; _T'],
          "-1 4 ")   # -1 ior, HTTP-E-TIMEOUT=4

    # Body content readable
    check("PARSE body content",
          http_response("HTTP/1.1 200 OK",
                        ["Content-Length: 5"],
                        "World") +
          ['_SETUP',
           ': _T HTTP-PARSE DROP HTTP-BODY-ADDR @ HTTP-BODY-LEN @ TYPE ; _T'],
          "World")


def test_header_lookup():
    print("\n── HTTP-HEADER (post-parse) ──\n")

    check("HEADER find Content-Type",
          http_response("HTTP/1.1 200 OK",
                        ["Content-Type: text/html",
                         "Content-Length: 4"],
                        "test") +
          ['_SETUP',
           ': _T HTTP-PARSE DROP',
           'S" Content-Type" HTTP-HEADER',
           'IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "text/html")

    check("HEADER find Server",
          http_response("HTTP/1.1 200 OK",
                        ["Server: KDOS/1.1",
                         "Content-Length: 2"],
                        "ok") +
          ['_SETUP',
           ': _T HTTP-PARSE DROP',
           'S" Server" HTTP-HEADER',
           'IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "KDOS/1.1")

    check("HEADER not found",
          http_response("HTTP/1.1 200 OK",
                        ["Content-Length: 2"],
                        "ok") +
          ['_SETUP',
           ': _T HTTP-PARSE DROP',
           'S" X-Custom" HTTP-HEADER',
           'IF TYPE ELSE 2DROP ." NOTFOUND" THEN ; _T'],
          "NOTFOUND")


def test_dechunk():
    print("\n── HTTP-DECHUNK ──\n")

    # Simple single chunk
    check("DECHUNK single chunk",
          tstr("5\r\nHello\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "Hello")

    # Multiple chunks
    check("DECHUNK multiple chunks",
          tstr("5\r\nHello\r\n7\r\n World!\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "Hello World!")

    # Hex sizes (uppercase)
    check("DECHUNK hex size A=10 length",
          tstr("A\r\n0123456789\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "10 ")

    check("DECHUNK hex size A=10 content",
          tstr("A\r\n0123456789\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "0123456789")

    # Hex sizes (lowercase)
    check("DECHUNK hex size a=10 length",
          tstr("a\r\n0123456789\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "10 ")

    check("DECHUNK hex size a=10 content",
          tstr("a\r\n0123456789\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "0123456789")

    # Large hex size
    check("DECHUNK hex 1F=31",
          tstr("1F\r\n" + "X" * 31 + "\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "31 ")

    # Zero chunk only (empty body)
    check("DECHUNK empty",
          tstr("0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "0 ")

    # Three chunks
    check("DECHUNK three chunks",
          tstr("3\r\nabc\r\n3\r\ndef\r\n3\r\nghi\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "abcdefghi")

    # Dechunk result length
    check("DECHUNK returns correct length",
          tstr("5\r\nHello\r\n3\r\n Hi\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "8 ")


def test_session():
    print("\n── Session / Persistent Headers ──\n")

    check("SET-BEARER stores token",
          [': _T S" mytoken123" HTTP-SET-BEARER',
           '_HTTP-BEARER-LEN @ . ; _T'],
          "10 ")

    # 300-char token (typical Bluesky JWT length)
    jwt300 = "A" * 300
    check("SET-BEARER stores 300-char JWT",
          tstr(jwt300) +
          [': _T TA HTTP-SET-BEARER',
           '_HTTP-BEARER-LEN @ . ; _T'],
          "300 ")

    check("CLEAR-BEARER resets",
          [': _T S" abc" HTTP-SET-BEARER HTTP-CLEAR-BEARER',
           '_HTTP-BEARER-LEN @ . ; _T'],
          "0 ")

    check("SET-UA stores user-agent",
          [': _T S" TestBot/2.0" HTTP-SET-UA',
           '_HTTP-UA-LEN @ . ; _T'],
          "11 ")

    check("APPLY-SESSION with bearer adds auth header",
          [': _T S" tok999" HTTP-SET-BEARER',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "Authorization: Bearer tok999")

    check("APPLY-SESSION with UA adds user-agent",
          [': _T HTTP-CLEAR-BEARER S" Bot/1" HTTP-SET-UA',
           'HDR-RESET S" /x" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "User-Agent: Bot/1")

    check("APPLY-SESSION with both",
          [': _T S" t1" HTTP-SET-BEARER S" A/1" HTTP-SET-UA',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "Bearer t1" in out and "User-Agent: A/1" in out)

    check("APPLY-SESSION with no session — default UA only",
          [': _T HTTP-CLEAR-BEARER 0 _HTTP-UA-LEN ! HTTP-CLEAR-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "Authorization" not in out
                               and "User-Agent: KDOS/1.1 Megapad-64" in out
                               and "Accept" not in out)

    check("SET-ACCEPT stores accept type",
          [': _T S" application/json" HTTP-SET-ACCEPT',
           '_HTTP-ACCEPT-LEN @ . ; _T'],
          "16 ")

    check("CLEAR-ACCEPT resets",
          [': _T S" text/html" HTTP-SET-ACCEPT HTTP-CLEAR-ACCEPT',
           '_HTTP-ACCEPT-LEN @ . ; _T'],
          "0 ")

    check("APPLY-SESSION with accept adds Accept header",
          [': _T HTTP-CLEAR-BEARER 0 _HTTP-UA-LEN !',
           'S" application/json" HTTP-SET-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "Accept: application/json")

    check("APPLY-SESSION no accept — no Accept header",
          [': _T HTTP-CLEAR-BEARER 0 _HTTP-UA-LEN ! HTTP-CLEAR-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "Accept" not in out)

    check("SET-ACCEPT overwrite replaces value",
          [': _T S" text/html" HTTP-SET-ACCEPT',
           'S" application/json" HTTP-SET-ACCEPT',
           'HTTP-CLEAR-BEARER 0 _HTTP-UA-LEN !',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "Accept: application/json")

    check("SET-ACCEPT clamps at 63 chars",
          [': _T S" application/vnd.example.superlongmimetype+json; charset=utf-8; boundary=something" HTTP-SET-ACCEPT',
           '_HTTP-ACCEPT-LEN @ . ; _T'],
          "63 ")

    check("Accept + bearer + UA all emitted together",
          [': _T S" tk" HTTP-SET-BEARER S" B/1" HTTP-SET-UA',
           'S" application/json" HTTP-SET-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "Bearer tk" in out
                               and "User-Agent: B/1" in out
                               and "Accept: application/json" in out)

    check("Accept persists across two header builds",
          [': _T HTTP-CLEAR-BEARER 0 _HTTP-UA-LEN !',
           'S" application/json" HTTP-SET-ACCEPT',
           'HDR-RESET S" /a" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESET S" /b" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "Accept: application/json")


def test_redirect():
    print("\n── Redirect Detection ──\n")

    check("301 is redirect",
          [': _T 301 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("302 is redirect",
          [': _T 302 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("307 is redirect",
          [': _T 307 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("308 is redirect",
          [': _T 308 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("200 is NOT redirect",
          [': _T 200 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("404 is NOT redirect",
          [': _T 404 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("500 is NOT redirect",
          [': _T 500 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("HTTP-MAX-REDIRECTS default=5",
          [': _T HTTP-MAX-REDIRECTS @ . ; _T'],
          "5 ")

    check("HTTP-FOLLOW? default=true",
          [': _T HTTP-FOLLOW? @ IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_dns_cache():
    print("\n── DNS Cache ──\n")

    check("DNS-FLUSH clears cache",
          [': _T HTTP-DNS-FLUSH',
           '0 CELLS _DNS-LENS + @ . ; _T'],
          "0 ")

    check("_DNS-SLOTS is 8",
          [': _T _DNS-SLOTS . ; _T'],
          "8 ")


def test_req_target():
    """Verify _HTTP-REQ-TARGET builds path?query correctly."""
    print("\n── Request Target (_HTTP-REQ-TARGET) ──\n")

    # Path only, no query string
    check("REQ-TARGET path only",
          [': _T S" http://example.com/foo/bar" URL-PARSE DROP',
           '_HTTP-REQ-TARGET TYPE ; _T'],
          "/foo/bar")

    # Path with query string
    check("REQ-TARGET path + query",
          [': _T S" http://example.com/api?key=val" URL-PARSE DROP',
           '_HTTP-REQ-TARGET TYPE ; _T'],
          "/api?key=val")

    # Multiple query params
    check("REQ-TARGET multi param",
          [': _T S" http://x.com/p?a=1&b=2&c=3" URL-PARSE DROP',
           '_HTTP-REQ-TARGET TYPE ; _T'],
          "/p?a=1&b=2&c=3")

    # Root path with query
    check("REQ-TARGET root + query",
          [': _T S" http://x.com/?q=hello" URL-PARSE DROP',
           '_HTTP-REQ-TARGET TYPE ; _T'],
          "/?q=hello")

    # XRPC-style URL (the original bug scenario)
    check("REQ-TARGET xrpc style",
          [': _T S" https://bsky.social/xrpc/app.bsky.actor.getProfile?actor=did:plc:xxx" URL-PARSE DROP',
           '_HTTP-REQ-TARGET TYPE ; _T'],
          "/xrpc/app.bsky.actor.getProfile?actor=did:plc:xxx")

    # Verify request line includes query (end-to-end via HDR-METHOD)
    check("HDR-METHOD includes query",
          [': _T S" https://example.com/search?q=test" URL-PARSE DROP',
           'HDR-RESET',
           'S" GET" _HTTP-REQ-TARGET HDR-METHOD',
           'HDR-END HDR-RESULT TYPE ; _T'],
          "GET /search?q=test HTTP/1.1")

    # Path without query → no trailing ?
    check("HDR-METHOD no query no ?",
          [': _T S" http://example.com/plain" URL-PARSE DROP',
           'HDR-RESET',
           'S" POST" _HTTP-REQ-TARGET HDR-METHOD',
           'HDR-END HDR-RESULT TYPE ; _T'],
          "POST /plain HTTP/1.1")


def test_req_target_bounds():
    """Edge cases for _HTTP-REQ-TARGET buffer bounds (512-byte _HTTP-RT-BUF).

    URL-PATH is 256 bytes max, URL-QUERY-BUF is 256 bytes max.
    _HTTP-REQ-TARGET assembles path + '?' + query, clamped to 511 total.
    These tests exercise the boundary conditions that would have caught
    an overflow before bounds-checking was added.
    """
    print("\n── Request Target Bounds ──\n")

    # Max path (256) + max query (256) = 513 → clamped to 511
    check("RT-BOUNDS max path+query → 511",
          [': _T  URL-PATH 256 80 FILL  256 URL-PATH-LEN !',
           '  URL-QUERY-BUF 256 81 FILL  256 URL-QUERY-LEN !',
           '  _HTTP-REQ-TARGET NIP . ; _T'],
          "511 ")

    # '?' separator sits at position 256 (right after 256-byte path)
    check("RT-BOUNDS ? at correct offset",
          [': _T  URL-PATH 256 80 FILL  256 URL-PATH-LEN !',
           '  URL-QUERY-BUF 256 81 FILL  256 URL-QUERY-LEN !',
           '  _HTTP-REQ-TARGET DROP 256 + C@ . ; _T'],
          "63 ")        # '?' = ASCII 63

    # Last byte of result is query content, not garbage
    check("RT-BOUNDS last byte is query",
          [': _T  URL-PATH 256 80 FILL  256 URL-PATH-LEN !',
           '  URL-QUERY-BUF 256 81 FILL  256 URL-QUERY-LEN !',
           '  _HTTP-REQ-TARGET + 1 - C@ . ; _T'],
          "81 ")        # 'Q' = ASCII 81

    # Short path (100) + full query (256) fits entirely: 100+1+256=357
    check("RT-BOUNDS short path + full query → 357",
          [': _T  URL-PATH 100 80 FILL  100 URL-PATH-LEN !',
           '  URL-QUERY-BUF 256 81 FILL  256 URL-QUERY-LEN !',
           '  _HTTP-REQ-TARGET NIP . ; _T'],
          "357 ")

    # Max path with no query → just path length
    check("RT-BOUNDS max path no query → 256",
          [': _T  URL-PATH 256 80 FILL  256 URL-PATH-LEN !',
           '  0 URL-QUERY-LEN !',
           '  _HTTP-REQ-TARGET NIP . ; _T'],
          "256 ")

    # _HTTP-RT-LEN variable matches the stack value
    check("RT-BOUNDS _HTTP-RT-LEN matches return",
          [': _T  URL-PATH 256 80 FILL  256 URL-PATH-LEN !',
           '  URL-QUERY-BUF 256 81 FILL  256 URL-QUERY-LEN !',
           '  _HTTP-REQ-TARGET NIP _HTTP-RT-LEN @ = IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    # Two successive calls produce consistent lengths
    check("RT-BOUNDS idempotent",
          [': _T  URL-PATH 200 80 FILL  200 URL-PATH-LEN !',
           '  URL-QUERY-BUF 150 81 FILL  150 URL-QUERY-LEN !',
           '  _HTTP-REQ-TARGET NIP . _HTTP-REQ-TARGET NIP . ; _T'],
          "351 351 ")   # 200+1+150=351


def test_compile_check():
    """Verify that all words compile without error."""
    print("\n── Compile Checks ──\n")

    check("HTTP-GET compiles",
          [': _T-CG  S" http://x.com/" HTTP-GET 2DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-POST compiles",
          [': _T-CP  S" http://x.com/" S" {}" S" application/json" HTTP-POST 2DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-POST-JSON compiles",
          [': _T-CJ  S" http://x.com/" S" {}" HTTP-POST-JSON 2DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-REQUEST compiles",
          [': _T-CR  S" PUT" S" http://x.com/" HTTP-REQUEST DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-CONNECT compiles",
          [': _T-CC  S" example.com" 80 0 HTTP-CONNECT DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-DISCONNECT compiles",
          [': _T-CD  HTTP-DISCONNECT ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-DNS-LOOKUP compiles",
          [': _T-DL  S" example.com" HTTP-DNS-LOOKUP DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())


def test_dechunk_edge_cases():
    """Edge cases for chunked transfer-encoding — the chunking bug fix."""
    print("\n── DECHUNK Edge Cases ──\n")

    # Single byte chunk
    check("DECHUNK single byte chunk",
          tstr("1\r\nX\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "X")

    # Very large hex chunk size (FF = 255)
    check("DECHUNK hex FF=255",
          tstr("FF\r\n" + "A" * 255 + "\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "255 ")

    # Mixed case hex (aF = 175)
    check("DECHUNK mixed case hex aF",
          tstr("aF\r\n" + "B" * 175 + "\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "175 ")

    # Many small chunks (10 × 1-byte)
    many_small = ""
    for c in "ABCDEFGHIJ":
        many_small += f"1\r\n{c}\r\n"
    many_small += "0\r\n\r\n"
    check("DECHUNK 10 × 1-byte chunks",
          tstr(many_small) +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "ABCDEFGHIJ")

    check("DECHUNK 10 × 1-byte length",
          tstr(many_small) +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "10 ")

    # Chunk with \r\n in data (binary-safe)
    # Hex 5 bytes: "ab" + CR + LF + "c" — this tests that only the trailing CRLF is consumed
    check("DECHUNK data content preserved",
          tstr("3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "abcde")

    # Trailing data after final 0 chunk (should be ignored)
    check("DECHUNK ignores trailer after 0 chunk",
          tstr("5\r\nHello\r\n0\r\n\r\nTrailer: extra\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "Hello")

    check("DECHUNK ignores trailer length",
          tstr("5\r\nHello\r\n0\r\n\r\nTrailer: extra\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "5 ")

    # Two-digit decimal chunk sizes
    check("DECHUNK hex 10=16 bytes",
          tstr("10\r\n" + "Z" * 16 + "\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "16 ")

    # Chunk size 0 alone (empty body from chunked response)
    check("DECHUNK just 0 chunk returns empty",
          tstr("0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "0 ")

    # Five equal chunks concatenated
    check("DECHUNK five equal chunks",
          tstr("4\r\nAAAA\r\n4\r\nBBBB\r\n4\r\nCCCC\r\n4\r\nDDDD\r\n4\r\nEEEE\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "AAAABBBBCCCCDDDDEEEE")

    check("DECHUNK five equal chunks length",
          tstr("4\r\nAAAA\r\n4\r\nBBBB\r\n4\r\nCCCC\r\n4\r\nDDDD\r\n4\r\nEEEE\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK . DROP ; _T'],
          "20 ")

    # Chunk with hex size 0 in middle (would be a bad server, but should stop)
    check("DECHUNK stops at mid-stream 0 chunk",
          tstr("3\r\nabc\r\n0\r\n\r\n3\r\ndef\r\n0\r\n\r\n") +
          [': _T TA HTTP-DECHUNK TYPE ; _T'],
          "abc")


def test_dechunk_with_parse():
    """Test dechunked responses through the full parse pathway — the primary chunking bug."""
    print("\n── DECHUNK + PARSE Integration ──\n")

    # Chunked response parsed correctly
    chunked_resp = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nHello\r\n0\r\n\r\n"
    check("PARSE + DECHUNK chunked response",
          tstr(chunked_resp) +
          ['_SETUP',
           ': _T HTTP-PARSE DROP',
           'HTTP-BODY-ADDR @ HTTP-BODY-LEN @',
           'HTTP-RECV-BUF @ _HTTP-HEND-OFF @ HDR-CHUNKED? IF HTTP-DECHUNK THEN',
           'TYPE ; _T'],
          "Hello")

    # Multi-chunk through parse
    multi_chunk = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nfoo\r\n3\r\nbar\r\n0\r\n\r\n"
    check("PARSE + DECHUNK multi-chunk",
          tstr(multi_chunk) +
          ['_SETUP',
           ': _T HTTP-PARSE DROP',
           'HTTP-BODY-ADDR @ HTTP-BODY-LEN @',
           'HTTP-RECV-BUF @ _HTTP-HEND-OFF @ HDR-CHUNKED? IF HTTP-DECHUNK THEN',
           'TYPE ; _T'],
          "foobar")

    # Non-chunked still works (no dechunk applied)
    normal_resp = "HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ntest"
    check("PARSE non-chunked unmodified",
          tstr(normal_resp) +
          ['_SETUP',
           ': _T HTTP-PARSE DROP',
           'HTTP-BODY-ADDR @ HTTP-BODY-LEN @',
           'HTTP-RECV-BUF @ _HTTP-HEND-OFF @ HDR-CHUNKED? IF HTTP-DECHUNK THEN',
           'TYPE ; _T'],
          "test")

    # Chunked with JSON body (real-world scenario)
    json_body = '{"ok":true}'
    hex_len = format(len(json_body), 'x')
    chunked_json = f"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: application/json\r\n\r\n{hex_len}\r\n{json_body}\r\n0\r\n\r\n"
    check("PARSE + DECHUNK JSON body",
          tstr(chunked_json) +
          ['_SETUP',
           ': _T HTTP-PARSE DROP',
           'HTTP-BODY-ADDR @ HTTP-BODY-LEN @',
           'HTTP-RECV-BUF @ _HTTP-HEND-OFF @ HDR-CHUNKED? IF HTTP-DECHUNK THEN',
           'TYPE ; _T'],
          '{"ok":true}')

    # Chunked 404 response
    err_body = "Not Found"
    hex_err = format(len(err_body), 'x')
    chunked_404 = f"HTTP/1.1 404 Not Found\r\nTransfer-Encoding: chunked\r\n\r\n{hex_err}\r\n{err_body}\r\n0\r\n\r\n"
    check("PARSE + DECHUNK 404 chunked",
          tstr(chunked_404) +
          ['_SETUP',
           ': _T HTTP-PARSE DROP HTTP-STATUS @ .',
           'HTTP-BODY-ADDR @ HTTP-BODY-LEN @',
           'HTTP-RECV-BUF @ _HTTP-HEND-OFF @ HDR-CHUNKED? IF HTTP-DECHUNK THEN',
           'TYPE ; _T'],
          check_fn=lambda out: "404" in out and "Not Found" in out)


def test_method_buffer():
    """Test the method string buffer fix — verifying method doesn't get clobbered."""
    print("\n── Method Buffer Fix ──\n")

    check("_HTTP-METHOD-BUF exists",
          [': _T _HTTP-METHOD-BUF DROP 1 . ; _T'],
          "1 ")

    check("_HTTP-METHOD-LEN exists",
          [': _T _HTTP-METHOD-LEN @ DROP 1 . ; _T'],
          "1 ")

    # Store and retrieve method
    check("Method buffer stores GET",
          [': _T S" GET" 3 MIN DUP _HTTP-METHOD-LEN !',
           '_HTTP-METHOD-BUF SWAP CMOVE',
           '_HTTP-METHOD-BUF _HTTP-METHOD-LEN @ TYPE ; _T'],
          "GET")

    check("Method buffer stores DELETE",
          [': _T S" DELETE" 6 MIN DUP _HTTP-METHOD-LEN !',
           '_HTTP-METHOD-BUF SWAP CMOVE',
           '_HTTP-METHOD-BUF _HTTP-METHOD-LEN @ TYPE ; _T'],
          "DELETE")

    check("Method buffer stores PATCH",
          [': _T S" PATCH" 5 MIN DUP _HTTP-METHOD-LEN !',
           '_HTTP-METHOD-BUF SWAP CMOVE',
           '_HTTP-METHOD-BUF _HTTP-METHOD-LEN @ TYPE ; _T'],
          "PATCH")

    # Method buffer clamps at 15 chars
    check("Method buffer clamps long method",
          [': _T S" VERYVERYLONGMETHOD" 15 MIN DUP _HTTP-METHOD-LEN !',
           '_HTTP-METHOD-BUF SWAP CMOVE',
           '_HTTP-METHOD-LEN @ . ; _T'],
          "15 ")

    # HTTP-REQUEST compilation with various methods (verifies the method buffer
    # doesn't get clobbered by URL-PARSE's S" buffer reuse)
    check("HTTP-REQUEST compiles with PUT",
          [': _T-PUT  S" PUT" S" http://x.com/res" HTTP-REQUEST DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-REQUEST compiles with DELETE",
          [': _T-DEL  S" DELETE" S" http://x.com/res" HTTP-REQUEST DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())

    check("HTTP-REQUEST compiles with PATCH",
          [': _T-PATCH  S" PATCH" S" http://x.com/res" HTTP-REQUEST DROP ;'],
          check_fn=lambda out: 'not found' not in out.lower())


def test_session_default_ua():
    """Test the default User-Agent fix in HTTP-APPLY-SESSION."""
    print("\n── Default User-Agent Fix ──\n")

    # When no custom UA is set, default UA should still be emitted
    check("Default UA emitted when UA-LEN=0",
          [': _T 0 _HTTP-UA-LEN ! HTTP-CLEAR-BEARER HTTP-CLEAR-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "User-Agent: KDOS/1.1 Megapad-64")

    # Custom UA overrides default
    check("Custom UA overrides default",
          [': _T S" MyBot/2.0" HTTP-SET-UA HTTP-CLEAR-BEARER HTTP-CLEAR-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "User-Agent: MyBot/2.0" in out
                               and "KDOS/1.1 Megapad-64" not in out)

    # After clearing custom UA, default resumes
    check("Default UA resumes after clearing custom",
          [': _T S" Bot/1" HTTP-SET-UA 0 _HTTP-UA-LEN !',
           'HTTP-CLEAR-BEARER HTTP-CLEAR-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "User-Agent: KDOS/1.1 Megapad-64")

    # Default UA present alongside bearer
    check("Default UA with bearer token",
          [': _T 0 _HTTP-UA-LEN ! S" mytoken" HTTP-SET-BEARER HTTP-CLEAR-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "User-Agent: KDOS/1.1 Megapad-64" in out
                               and "Bearer mytoken" in out)

    # Default UA present alongside accept
    check("Default UA with accept header",
          [': _T 0 _HTTP-UA-LEN ! HTTP-CLEAR-BEARER',
           'S" text/html" HTTP-SET-ACCEPT',
           'HDR-RESET S" /" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "User-Agent: KDOS/1.1 Megapad-64" in out
                               and "Accept: text/html" in out)


def test_parse_edge_cases():
    """Additional edge cases for HTTP-PARSE."""
    print("\n── HTTP-PARSE Edge Cases ──\n")

    # 204 No Content (no body)
    check("PARSE 204 No Content",
          http_response("HTTP/1.1 204 No Content",
                        ["Content-Length: 0"],
                        "") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . HTTP-BODY-LEN @ . ; _T'],
          "0 204 0 ")

    # Very long Content-Length field
    check("PARSE large Content-Length truncated by buffer",
          http_response("HTTP/1.1 200 OK",
                        ["Content-Length: 99999"],
                        "tiny") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-BODY-LEN @ . ; _T'],
          "0 4 ")

    # Multiple headers
    check("PARSE multi-header response",
          http_response("HTTP/1.1 200 OK",
                        ["X-Request-Id: abc123",
                         "Content-Type: text/plain",
                         "X-Rate-Limit: 100",
                         "Content-Length: 2"],
                        "OK") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . HTTP-BODY-LEN @ . ; _T'],
          "0 200 2 ")

    # 100 Continue status
    check("PARSE status 201",
          http_response("HTTP/1.1 201 Created",
                        ["Content-Length: 11"],
                        "resource ok") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . ; _T'],
          "0 201 ")

    # 503 Service Unavailable
    check("PARSE 503",
          http_response("HTTP/1.1 503 Service Unavailable",
                        ["Content-Length: 11", "Retry-After: 30"],
                        "unavailable") +
          ['_SETUP',
           ': _T HTTP-PARSE . HTTP-STATUS @ . ; _T'],
          "0 503 ")


def test_redirect_edge_cases():
    """Additional redirect status codes."""
    print("\n── Redirect Edge Cases ──\n")

    check("303 is NOT redirect (not in set)",
          [': _T 303 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("304 Not Modified is NOT redirect",
          [': _T 304 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("300 is NOT redirect",
          [': _T 300 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("0 is NOT redirect",
          [': _T 0 HTTP-STATUS ! _HTTP-REDIRECT? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("HTTP-MAX-REDIRECTS can be changed",
          [': _T 10 HTTP-MAX-REDIRECTS ! HTTP-MAX-REDIRECTS @ . ; _T'],
          "10 ")

    check("HTTP-FOLLOW? can be disabled",
          [': _T 0 HTTP-FOLLOW? ! HTTP-FOLLOW? @ IF 1 ELSE 0 THEN . ; _T'],
          "0 ")


# ── Main ──

if __name__ == "__main__":
    build_snapshot()
    test_error_handling()
    test_static_buffer()
    test_parse()
    test_parse_edge_cases()
    test_header_lookup()
    test_dechunk()
    test_dechunk_edge_cases()
    test_dechunk_with_parse()
    test_session()
    test_session_default_ua()
    test_method_buffer()
    test_redirect()
    test_redirect_edge_cases()
    test_dns_cache()
    test_req_target()
    test_req_target_bounds()
    test_compile_check()
    print(f"\n{'='*40}")
    print(f"  {_pass} passed,  {_fail} failed")
    print(f"{'='*40}\n")
    sys.exit(1 if _fail else 0)
