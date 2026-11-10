#!/usr/bin/env python3
"""Test suite for akashic-web-router Forth library (web/router.f)."""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from forth_snapshot import run_file_tests, transcript_checks, module_source_lines

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

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
    print("[*] Building snapshot: BIOS + KDOS + libs + router.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    module_lines = module_source_lines((
        "concurrency/event.f",
        "concurrency/semaphore.f",
        "concurrency/guard.f",
        "utils/string.f",
        "net/url.f",
        "net/headers.f",
        "utils/datetime.f",
        "utils/table.f",
        "web/request.f",
        "web/response.f",
        "web/router.f",
    ))
    helpers = [
        'CREATE _TB 2048 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Mock SEND for response.f
        ': _RESP-SEND-MOCK  ( addr len -- ) TYPE ;',
        "' _RESP-SEND-MOCK _RESP-SEND-XT !",
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    all_lines = (kdos_lines + ["ENTER-USERLAND"] +
                 module_lines + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 800_000_000
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
    if _snapshot is None:
        build_snapshot()
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

# The checks read only what the program printed, and fail their test when a
# check fails or KDOS reports a failed line (forth_snapshot.transcript_checks).
check = transcript_checks(run_forth)[0]


def test_compile():
    print("\n── Compile Check ──\n")
    check("All words compile",
          [': _T ROUTE-CLEAR ROUTE-COUNT . ; _T'],
          check_fn=lambda t: "not found" not in t.lower())

def test_route_table():
    print("\n── Route Table ──\n")

    check("ROUTE-COUNT starts at 0",
          [': _T ROUTE-CLEAR ROUTE-COUNT . ; _T'], "0 ")

    check("ROUTE registers a route",
          [': _h1 ;',
           ': _T ROUTE-CLEAR',
           '  S" GET" S" /foo" [\'] _h1 ROUTE',
           '  ROUTE-COUNT . ; _T'], "1 ")

    check("Multiple routes",
          [': _h1 ; : _h2 ;',
           ': _T ROUTE-CLEAR',
           '  S" GET"  S" /a" [\'] _h1 ROUTE',
           '  S" POST" S" /b" [\'] _h2 ROUTE',
           '  ROUTE-COUNT . ; _T'], "2 ")

    check("ROUTE-GET convenience",
          [': _h1 ;',
           ': _T ROUTE-CLEAR',
           '  S" /x" [\'] _h1 ROUTE-GET',
           '  ROUTE-COUNT . ; _T'], "1 ")

    check("ROUTE-CLEAR empties table",
          [': _h1 ;',
           ': _T',
           '  S" GET" S" /a" [\'] _h1 ROUTE',
           '  ROUTE-CLEAR ROUTE-COUNT . ; _T'], "0 ")

def test_next_seg():
    print("\n── _ROUTE-NEXT-SEG ──\n")

    check("/ → empty seg, empty rest",
          [': _T S" /" _ROUTE-NEXT-SEG . . . . ; _T'],
          check_fn=lambda t: "0 0" in t.replace('\r','').replace('\n',' '))

    check("/foo → foo 3 + empty rest",
          [': _T S" /foo" _ROUTE-NEXT-SEG',
           '  . . TYPE ; _T'],
          check_fn=lambda t: "foo" in t and "0 0" in t.replace('\r','').replace('\n',' '))

    check("/foo/bar → foo 3 + /bar rest",
          [': _T S" /foo/bar" _ROUTE-NEXT-SEG',
           '  2SWAP TYPE 32 EMIT TYPE ; _T'],
          check_fn=lambda t: "foo" in t and "/bar" in t or "bar" in t)

def test_pattern_match():
    print("\n── Pattern Matching ──\n")

    check("Exact match /foo",
          [': _T S" /foo" S" /foo" _ROUTE-PATTERN-MATCH . ; _T'],
          check_fn=lambda t: "-1" in t)

    check("Exact match / (root)",
          [': _T S" /" S" /" _ROUTE-PATTERN-MATCH . ; _T'],
          check_fn=lambda t: "-1" in t)

    check("Mismatch /foo vs /bar",
          [': _T S" /foo" S" /bar" _ROUTE-PATTERN-MATCH . ; _T'],
          "0 ")

    check("Mismatch /foo vs /foo/bar (extra segment)",
          [': _T S" /foo" S" /foo/bar" _ROUTE-PATTERN-MATCH . ; _T'],
          "0 ")

    check("Mismatch /foo/bar vs /foo (missing segment)",
          [': _T S" /foo/bar" S" /foo" _ROUTE-PATTERN-MATCH . ; _T'],
          "0 ")

    check("Multi-segment /a/b matches /a/b",
          [': _T S" /a/b" S" /a/b" _ROUTE-PATTERN-MATCH . ; _T'],
          check_fn=lambda t: "-1" in t)

    check("Param :id captures value",
          [': _T S" /user/:id" S" /user/42" _ROUTE-PATTERN-MATCH .',
           '  S" id" ROUTE-PARAM TYPE ; _T'],
          check_fn=lambda t: "-1" in t and "42" in t)

    check("Two params",
          [': _T S" /user/:id/post/:pid" S" /user/5/post/99"',
           '  _ROUTE-PATTERN-MATCH .',
           '  S" id" ROUTE-PARAM TYPE 32 EMIT',
           '  S" pid" ROUTE-PARAM TYPE ; _T'],
          check_fn=lambda t: "-1" in t and "5" in t and "99" in t)

def test_route_match():
    print("\n── ROUTE-MATCH ──\n")

    check("Match registered GET /hello",
          [': _h1 42 . ;',
           ': _T ROUTE-CLEAR',
           '  S" /hello" [\'] _h1 ROUTE-GET',
           '  S" GET" S" /hello" ROUTE-MATCH',
           '  DUP 0<> IF EXECUTE ELSE . THEN ; _T'],
          "42 ")

    check("No match returns 0",
          [': _h1 ;',
           ': _T ROUTE-CLEAR',
           '  S" /a" [\'] _h1 ROUTE-GET',
           '  S" GET" S" /nope" ROUTE-MATCH . ; _T'],
          "0 ")

    check("Method mismatch returns 0",
          [': _h1 ;',
           ': _T ROUTE-CLEAR',
           '  S" /a" [\'] _h1 ROUTE-GET',
           '  S" POST" S" /a" ROUTE-MATCH . ; _T'],
          "0 ")

    check("Param route match",
          [': _h1 S" id" ROUTE-PARAM TYPE ;',
           ': _T ROUTE-CLEAR',
           '  S" /user/:id" [\'] _h1 ROUTE-GET',
           '  S" GET" S" /user/abc" ROUTE-MATCH',
           '  DUP 0<> IF EXECUTE ELSE . THEN ; _T'],
          "abc")

def test_dispatch():
    print("\n── ROUTE-DISPATCH ──\n")

    # ROUTE-DISPATCH reads REQ-METHOD and REQ-PATH, so we need to
    # parse a request first via REQ-PARSE, then dispatch.
    check("Dispatch calls handler",
          [': _h1 99 . ;', ': _T ROUTE-CLEAR'] +
          tstr("GET /test HTTP/1.1\r\nHost: x\r\n\r\n") +
          ['  S" /test" [\'] _h1 ROUTE-GET',
           '  TA REQ-PARSE',
           '  ROUTE-DISPATCH ; _T'],
          "99 ")

    check("Dispatch 404 on no match",
          [': _T ROUTE-CLEAR RESP-CLEAR'] +
          tstr("GET /nope HTTP/1.1\r\nHost: x\r\n\r\n") +
          ['  TA REQ-PARSE',
           '  ROUTE-DISPATCH ; _T'],
          check_fn=lambda t: "404" in t)


if __name__ == "__main__":
    run_file_tests(__file__)
