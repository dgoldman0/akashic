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
"""Test suite for akashic-web-response Forth library (web/response.f).

Tests:
  Error    — RESP-FAIL, RESP-OK?, RESP-CLEAR-ERR
  Layer 0  — RESP-STATUS, _RESP-REASON, _RESP-BUILD-STATUS
  Layer 1  — RESP-HEADER, RESP-CONTENT-TYPE (via HDR-ADD)
  Layer 2  — RESP-BODY, body buffer overflow
  Layer 3  — RESP-SEND (capture via mock SEND)
  Layer 5  — _RESP-NUM>HEX
  Layer 6  — RESP-ERROR body construction
  Clear    — RESP-CLEAR
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F      = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HDR_F      = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
DT_F       = os.path.join(ROOT_DIR, "akashic", "utils", "datetime.f")
RESP_F     = os.path.join(ROOT_DIR, "akashic", "web", "response.f")
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
    print("[*] Building snapshot: BIOS + KDOS + string.f + url.f + headers.f + datetime.f + response.f ...")
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
    resp_lines = _load_forth_lines(RESP_F)
    helpers = [
        'CREATE _TB 2048 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Mock SEND: use vectored hook to TYPE instead of socket SEND
        ': _RESP-SEND-MOCK  ( addr len -- ) TYPE ;',
        "' _RESP-SEND-MOCK _RESP-SEND-XT !",
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + event_lines + sem_lines + guard_lines + str_lines + url_lines + hdr_lines + dt_lines + resp_lines + helpers) + "\n"
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

    check("RESP-OK? initially true",
          [': _T RESP-CLEAR-ERR RESP-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("RESP-FAIL sets error",
          [': _T 2 RESP-FAIL RESP-ERR @ . ; _T'],
          "2 ")

    check("RESP-OK? false after FAIL",
          [': _T 1 RESP-FAIL RESP-OK? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("RESP-CLEAR-ERR resets",
          [': _T 3 RESP-FAIL RESP-CLEAR-ERR RESP-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_status():
    print("\n── Status + Reason ──\n")

    check("_RESP-REASON 200",
          [': _T 200 _RESP-REASON TYPE ; _T'], "OK")

    check("_RESP-REASON 404",
          [': _T 404 _RESP-REASON TYPE ; _T'], "Not Found")

    check("_RESP-REASON 500",
          [': _T 500 _RESP-REASON TYPE ; _T'], "Internal Server Error")

    check("_RESP-REASON 999 unknown",
          [': _T 999 _RESP-REASON TYPE ; _T'], "Unknown")

    check("RESP-STATUS sets code",
          [': _T 201 RESP-STATUS _RESP-CODE @ . ; _T'], "201 ")

    check("_RESP-BUILD-STATUS 200",
          [': _T RESP-CLEAR 200 RESP-STATUS _RESP-BUILD-STATUS TYPE ; _T'],
          "HTTP/1.1 200 OK")

    check("_RESP-BUILD-STATUS 404",
          [': _T RESP-CLEAR 404 RESP-STATUS _RESP-BUILD-STATUS TYPE ; _T'],
          "HTTP/1.1 404 Not Found")

    check("_RESP-BUILD-STATUS 302",
          [': _T RESP-CLEAR 302 RESP-STATUS _RESP-BUILD-STATUS TYPE ; _T'],
          "HTTP/1.1 302 Found")

    check("_RESP-BUILD-STATUS 503",
          [': _T RESP-CLEAR 503 RESP-STATUS _RESP-BUILD-STATUS TYPE ; _T'],
          "HTTP/1.1 503 Service Unavailable")


def test_headers():
    print("\n── Headers ──\n")

    # After RESP-CLEAR, header builder is pointed at _RESP-HDR-BUF.
    # We can add headers and check HDR-RESULT.
    check("RESP-HEADER adds header",
          [': _T RESP-CLEAR',
           '  S" X-Custom" S" hello" RESP-HEADER',
           '  HDR-RESULT TYPE ; _T'],
          "X-Custom: hello")

    check("RESP-CONTENT-TYPE",
          [': _T RESP-CLEAR',
           '  S" text/html" RESP-CONTENT-TYPE',
           '  HDR-RESULT TYPE ; _T'],
          "Content-Type: text/html")

    check("RESP-LOCATION",
          [': _T RESP-CLEAR',
           '  S" /new-page" RESP-LOCATION',
           '  HDR-RESULT TYPE ; _T'],
          "Location: /new-page")

    check("RESP-SET-COOKIE",
          [': _T RESP-CLEAR',
           '  S" sid=abc123" RESP-SET-COOKIE',
           '  HDR-RESULT TYPE ; _T'],
          "Set-Cookie: sid=abc123")

    check("RESP-NO-CACHE",
          [': _T RESP-CLEAR RESP-NO-CACHE HDR-RESULT TYPE ; _T'],
          "Cache-Control: no-store, no-cache")

    check("RESP-CORS adds 3 headers",
          [': _T RESP-CLEAR RESP-CORS HDR-RESULT TYPE ; _T'],
          check_fn=lambda t: "Access-Control-Allow-Origin: *" in t
                         and "Access-Control-Allow-Methods:" in t)

    check("Multiple headers accumulate",
          [': _T RESP-CLEAR',
           '  S" text/plain" RESP-CONTENT-TYPE',
           '  S" X-Foo" S" bar" RESP-HEADER',
           '  HDR-RESULT TYPE ; _T'],
          check_fn=lambda t: "Content-Type: text/plain" in t and "X-Foo: bar" in t)


def test_body():
    print("\n── Body Buffer ──\n")

    check("RESP-BODY appends",
          [': _T RESP-CLEAR',
           '  S" Hello" RESP-BODY',
           '  _RESP-BODY-BUF _RESP-BODY-LEN @ TYPE ; _T'],
          "Hello")

    check("RESP-BODY accumulates",
          [': _T RESP-CLEAR',
           '  S" Hel" RESP-BODY S" lo" RESP-BODY',
           '  _RESP-BODY-BUF _RESP-BODY-LEN @ TYPE ; _T'],
          "Hello")

    check("RESP-TEXT sets content-type and body",
          [': _T RESP-CLEAR',
           '  S" hi" RESP-TEXT',
           '  HDR-RESULT TYPE 10 EMIT',
           '  _RESP-BODY-BUF _RESP-BODY-LEN @ TYPE ; _T'],
          check_fn=lambda t: "Content-Type: text/plain" in t and "hi" in t)

    check("RESP-HTML sets content-type and body",
          [': _T RESP-CLEAR',
           '  S" <b>yo</b>" RESP-HTML',
           '  HDR-RESULT TYPE 10 EMIT',
           '  _RESP-BODY-BUF _RESP-BODY-LEN @ TYPE ; _T'],
          check_fn=lambda t: "text/html" in t and "<b>yo</b>" in t)

    check("RESP-BODY-LEN tracks length",
          [': _T RESP-CLEAR',
           '  S" 12345" RESP-BODY',
           '  _RESP-BODY-LEN @ . ; _T'],
          "5 ")


def test_send():
    """Test RESP-SEND — since we mocked _RESP-SEND-RAW to TYPE,
    the full HTTP response appears on UART."""
    print("\n── RESP-SEND ──\n")

    check("RESP-SEND simple 200",
          [': _T RESP-CLEAR',
           '  S" hi" RESP-BODY',
           '  RESP-SEND ; _T'],
          check_fn=lambda t: "HTTP/1.1 200 OK" in t and "Content-Length: 2" in t and "hi" in t)

    check("RESP-SEND with custom status",
          [': _T RESP-CLEAR 201 RESP-STATUS',
           '  S" ok" RESP-BODY',
           '  RESP-SEND ; _T'],
          check_fn=lambda t: "HTTP/1.1 201 Created" in t)

    check("RESP-SEND with headers",
          [': _T RESP-CLEAR',
           '  S" text/plain" RESP-CONTENT-TYPE',
           '  S" hello" RESP-BODY',
           '  RESP-SEND ; _T'],
          check_fn=lambda t: "Content-Type: text/plain" in t and "hello" in t)

    check("RESP-SEND empty body (Content-Length: 0)",
          [': _T RESP-CLEAR RESP-SEND ; _T'],
          check_fn=lambda t: "HTTP/1.1 200 OK" in t and "Content-Length: 0" in t)


def test_hex():
    print("\n── Hex Conversion ──\n")

    check("_RESP-NUM>HEX 0",
          [': _T 0 _RESP-NUM>HEX TYPE ; _T'], "0")

    check("_RESP-NUM>HEX 255",
          [': _T 255 _RESP-NUM>HEX TYPE ; _T'], "ff")

    check("_RESP-NUM>HEX 256",
          [': _T 256 _RESP-NUM>HEX TYPE ; _T'], "100")

    check("_RESP-NUM>HEX 16",
          [': _T 16 _RESP-NUM>HEX TYPE ; _T'], "10")

    check("_RESP-NUM>HEX 1",
          [': _T 1 _RESP-NUM>HEX TYPE ; _T'], "1")


def test_error_responses():
    print("\n── Error Responses ──\n")

    check("RESP-ERROR 404",
          [': _T RESP-CLEAR 404 RESP-ERROR ; _T'],
          check_fn=lambda t: "HTTP/1.1 404 Not Found" in t
                         and '"error":404' in t
                         and '"message":"Not Found"' in t)

    check("RESP-ERROR 500",
          [': _T RESP-CLEAR 500 RESP-ERROR ; _T'],
          check_fn=lambda t: "HTTP/1.1 500 Internal Server Error" in t
                         and '"error":500' in t)

    check("RESP-NOT-FOUND",
          [': _T RESP-CLEAR RESP-NOT-FOUND ; _T'],
          check_fn=lambda t: "HTTP/1.1 404" in t)

    check("RESP-METHOD-NOT-ALLOWED",
          [': _T RESP-CLEAR RESP-METHOD-NOT-ALLOWED ; _T'],
          check_fn=lambda t: "HTTP/1.1 405" in t)

    check("RESP-INTERNAL-ERROR",
          [': _T RESP-CLEAR RESP-INTERNAL-ERROR ; _T'],
          check_fn=lambda t: "HTTP/1.1 500" in t)


def test_json():
    print("\n── JSON Convenience ──\n")

    check("RESP-JSON sets content-type and body",
          [': _T RESP-CLEAR'] +
          tstr('{"ok":true}') +
          ['  TA RESP-JSON',
           '  RESP-SEND ; _T'],
          check_fn=lambda t: "application/json" in t)


def test_clear():
    print("\n── RESP-CLEAR ──\n")

    check("RESP-CLEAR resets code to 200",
          [': _T 404 RESP-STATUS RESP-CLEAR _RESP-CODE @ . ; _T'],
          "200 ")

    check("RESP-CLEAR empties body",
          [': _T S" hello" RESP-BODY RESP-CLEAR _RESP-BODY-LEN @ . ; _T'],
          "0 ")

    check("RESP-CLEAR resets headers",
          [': _T',
           '  S" X-Foo" S" bar" RESP-HEADER',
           '  RESP-CLEAR',
           '  HDR-RESULT NIP . ; _T'],
          "0 ")


def test_compile():
    print("\n── Compile Check ──\n")

    check("All words compile",
          [': _T RESP-CLEAR ; _T'],
          check_fn=lambda t: "not found" not in t.lower())


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()
    test_error_handling()
    test_status()
    test_headers()
    test_body()
    test_send()
    test_hex()
    test_error_responses()
    test_json()
    test_clear()
    test_compile()
    print(f"\n{'='*40}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail else 0)
