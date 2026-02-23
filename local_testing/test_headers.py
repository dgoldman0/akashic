#!/usr/bin/env python3
"""Test suite for akashic-http-headers Forth library."""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
HDR_F      = os.path.join(ROOT_DIR, "utils", "net", "headers.f")

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
    print("[*] Building snapshot: BIOS + KDOS + headers.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    hdr_lines  = _load_forth_lines(HDR_F)
    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _OB 512 ALLOT',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024)
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + hdr_lines + helpers) + "\n"
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


# ── Build tests ──

def test_build():
    print("\n── Header Building ──\n")

    check("HDR-RESET + RESULT empty",
          [': _T HDR-RESET HDR-RESULT . DROP ; _T'],
          "0 ")

    check("HDR-GET basic",
          [': _T HDR-RESET S" /index.html" HDR-GET',
           'HDR-RESULT TYPE ; _T'],
          "GET /index.html HTTP/1.1\r\n")

    check("HDR-POST",
          [': _T HDR-RESET S" /api/data" HDR-POST',
           'HDR-RESULT TYPE ; _T'],
          "POST /api/data HTTP/1.1\r\n")

    check("HDR-HOST",
          [': _T HDR-RESET S" example.com" HDR-HOST',
           'HDR-RESULT TYPE ; _T'],
          "Host: example.com\r\n")

    check("HDR-ADD custom header",
          [': _T HDR-RESET',
           'S" X-Custom" S" myvalue" HDR-ADD',
           'HDR-RESULT TYPE ; _T'],
          "X-Custom: myvalue\r\n")

    check("HDR-CONTENT-LENGTH 42",
          [': _T HDR-RESET 42 HDR-CONTENT-LENGTH',
           'HDR-RESULT TYPE ; _T'],
          "Content-Length: 42\r\n")

    check("HDR-CONTENT-LENGTH 0",
          [': _T HDR-RESET 0 HDR-CONTENT-LENGTH',
           'HDR-RESULT TYPE ; _T'],
          "Content-Length: 0\r\n")

    check("HDR-CONTENT-LENGTH 12345",
          [': _T HDR-RESET 12345 HDR-CONTENT-LENGTH',
           'HDR-RESULT TYPE ; _T'],
          "Content-Length: 12345\r\n")

    check("HDR-CONNECTION-CLOSE",
          [': _T HDR-RESET HDR-CONNECTION-CLOSE',
           'HDR-RESULT TYPE ; _T'],
          "Connection: close\r\n")

    check("HDR-CONTENT-JSON",
          [': _T HDR-RESET HDR-CONTENT-JSON',
           'HDR-RESULT TYPE ; _T'],
          "Content-Type: application/json\r\n")

    check("HDR-AUTH-BEARER",
          tstr("mytoken123") +
          [': _T HDR-RESET TA HDR-AUTH-BEARER',
           'HDR-RESULT TYPE ; _T'],
          "Authorization: Bearer mytoken123\r\n")

    check("HDR-END adds blank line",
          [': _T HDR-RESET HDR-END',
           'HDR-RESULT NIP . ; _T'],
          "2 ")   # just \r\n = 2 bytes

    check("Full GET request",
          [': _T HDR-RESET',
           'S" /api/v1/users" HDR-GET',
           'S" api.example.com" HDR-HOST',
           'HDR-CONTENT-JSON',
           'HDR-CONNECTION-CLOSE',
           'HDR-END',
           'HDR-RESULT TYPE ; _T'],
          check_fn=lambda o: all(s in o for s in [
              "GET /api/v1/users HTTP/1.1\r\n",
              "Host: api.example.com\r\n",
              "Content-Type: application/json\r\n",
              "Connection: close\r\n"]))


# ── Parse tests ──

# Helper to build a raw HTTP response in _TB
def build_response(status_line, headers, body=""):
    """Build Forth lines that construct a raw HTTP response in _TB."""
    raw = status_line + "\r\n"
    for h in headers:
        raw += h + "\r\n"
    raw += "\r\n" + body
    return tstr(raw)


def test_parse():
    print("\n── Header Parsing ──\n")

    # HDR-FIND-HEND
    resp = build_response("HTTP/1.1 200 OK",
                         ["Content-Length: 5", "Connection: close"],
                         "hello")
    # Calculate expected offset: "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\n"
    hdr_part = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\n"
    expected_offset = len(hdr_part)
    check("HDR-FIND-HEND finds boundary",
          resp + [f': _T TA HDR-FIND-HEND . ; _T'],
          f"{expected_offset} ")

    check("HDR-FIND-HEND not found (no blank line)",
          tstr("HTTP/1.1 200 OK\r\nHost: x\r\n") +
          [': _T TA HDR-FIND-HEND . ; _T'],
          "0 ")

    # LF-only boundary
    resp_lf = tstr("HTTP/1.1 200 OK\nContent-Length: 3\n\nabc")
    off_lf = len("HTTP/1.1 200 OK\nContent-Length: 3\n\n")
    check("HDR-FIND-HEND LF-only boundary",
          resp_lf + [f': _T TA HDR-FIND-HEND . ; _T'],
          f"{off_lf} ")

    # HDR-PARSE-STATUS
    check("HDR-PARSE-STATUS 200",
          tstr("HTTP/1.1 200 OK") +
          [': _T TA HDR-PARSE-STATUS . ; _T'],
          "200 ")

    check("HDR-PARSE-STATUS 404",
          tstr("HTTP/1.1 404 Not Found") +
          [': _T TA HDR-PARSE-STATUS . ; _T'],
          "404 ")

    check("HDR-PARSE-STATUS 301",
          tstr("HTTP/1.1 301 Moved") +
          [': _T TA HDR-PARSE-STATUS . ; _T'],
          "301 ")

    check("HDR-PARSE-STATUS too short",
          [': _T S" HTTP" 4 HDR-PARSE-STATUS . ; _T'],
          "0 ")

    # HDR-PARSE-CLEN
    resp2 = build_response("HTTP/1.1 200 OK",
                           ["Content-Type: text/html",
                            "Content-Length: 1234",
                            "Connection: close"])
    check("HDR-PARSE-CLEN found",
          resp2 + [': _T TA HDR-PARSE-CLEN . ; _T'],
          "1234 ")

    check("HDR-PARSE-CLEN case insensitive",
          tstr("CONTENT-LENGTH: 42\r\n\r\n") +
          [': _T TA HDR-PARSE-CLEN . ; _T'],
          "42 ")

    check("HDR-PARSE-CLEN not found",
          tstr("Content-Type: text/html\r\n\r\n") +
          [': _T TA HDR-PARSE-CLEN . ; _T'],
          "-1 ")

    # HDR-FIND
    resp3 = build_response("HTTP/1.1 200 OK",
                           ["Content-Type: application/json",
                            "X-Request-Id: abc123",
                            "Connection: close"])
    check("HDR-FIND existing header",
          resp3 + [': _T TA S" X-Request-Id" HDR-FIND',
                   'IF TYPE ELSE 2DROP THEN ; _T'],
          "abc123")

    check("HDR-FIND case insensitive",
          resp3 + [': _T TA S" content-type" HDR-FIND',
                   'IF TYPE ELSE 2DROP THEN ; _T'],
          "application/json")

    check("HDR-FIND not found",
          resp3 + [': _T TA S" X-Missing" HDR-FIND',
                   'IF TYPE ELSE 2DROP 46 EMIT THEN ; _T'],
          ".")

    # HDR-CHUNKED?
    resp_chunked = build_response("HTTP/1.1 200 OK",
                                  ["Transfer-Encoding: chunked"])
    check("HDR-CHUNKED? true",
          resp_chunked + [': _T TA HDR-CHUNKED? . ; _T'],
          "-1 ")

    resp_not_chunked = build_response("HTTP/1.1 200 OK",
                                      ["Content-Length: 5"])
    check("HDR-CHUNKED? false",
          resp_not_chunked + [': _T TA HDR-CHUNKED? . ; _T'],
          "0 ")

    # HDR-LOCATION
    resp_redir = build_response("HTTP/1.1 301 Moved",
                                ["Location: https://new.example.com/page"])
    check("HDR-LOCATION found",
          resp_redir + [': _T TA HDR-LOCATION',
                        'IF TYPE ELSE 2DROP THEN ; _T'],
          "https://new.example.com/page")


# ── Main ──

if __name__ == "__main__":
    build_snapshot()
    test_build()
    test_parse()
    print(f"\n{'='*60}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*60}")
    sys.exit(1 if _fail > 0 else 0)
