#!/usr/bin/env python3
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
URL_F      = os.path.join(ROOT_DIR, "utils", "net", "url.f")
HDR_F      = os.path.join(ROOT_DIR, "utils", "net", "headers.f")
HTTP_F     = os.path.join(ROOT_DIR, "utils", "net", "http.f")

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
        return [line for line in f.read().splitlines()
                if line.strip() and not line.strip().startswith('\\')]

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
    print("[*] Building snapshot: BIOS + KDOS + url.f + headers.f + http.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
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
    sys_obj = MegapadSystem(ram_size=1024*1024)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + url_lines + hdr_lines + http_lines + helpers) + "\n"
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
    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    mem_bytes, cpu_state = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024)
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
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

    check("APPLY-SESSION with no session — no extra headers",
          [': _T HTTP-CLEAR-BEARER 0 _HTTP-UA-LEN !',
           'HDR-RESET S" /" HDR-GET HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda out: "Authorization" not in out and "User-Agent" not in out)


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


# ── Main ──

if __name__ == "__main__":
    build_snapshot()
    test_error_handling()
    test_static_buffer()
    test_parse()
    test_header_lookup()
    test_dechunk()
    test_session()
    test_redirect()
    test_dns_cache()
    test_compile_check()
    print(f"\n{'='*40}")
    print(f"  {_pass} passed,  {_fail} failed")
    print(f"{'='*40}\n")
    sys.exit(1 if _fail else 0)
