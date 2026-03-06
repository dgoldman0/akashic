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
"""Test suite for akashic-url Forth library.

Uses the Megapad-64 emulator to boot KDOS, load url.f,
and run Forth test expressions.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
URL_F      = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

# ---------------------------------------------------------------------------
#  Emulator helpers (same pattern as test_json.py)
# ---------------------------------------------------------------------------

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

def _next_line_chunk(data: bytes, pos: int) -> bytes:
    nl = data.find(b'\n', pos)
    if nl == -1:
        return data[pos:]
    return data[pos:nl + 1]

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
    return {
        'pc': cpu.pc,
        'regs': list(cpu.regs),
        'psel': cpu.psel, 'xsel': cpu.xsel, 'spsel': cpu.spsel,
        'flag_z': cpu.flag_z, 'flag_c': cpu.flag_c,
        'flag_n': cpu.flag_n, 'flag_v': cpu.flag_v,
        'flag_p': cpu.flag_p, 'flag_g': cpu.flag_g,
        'flag_i': cpu.flag_i, 'flag_s': cpu.flag_s,
        'd_reg': cpu.d_reg, 'q_out': cpu.q_out, 't_reg': cpu.t_reg,
        'ivt_base': cpu.ivt_base, 'ivec_id': cpu.ivec_id,
        'trap_addr': cpu.trap_addr,
        'halted': cpu.halted, 'idle': cpu.idle,
        'cycle_count': cpu.cycle_count,
        '_ext_modifier': cpu._ext_modifier,
    }

def restore_cpu_state(cpu, state):
    cpu.pc = state['pc']
    cpu.regs[:] = state['regs']
    for k in ('psel', 'xsel', 'spsel',
              'flag_z', 'flag_c', 'flag_n', 'flag_v',
              'flag_p', 'flag_g', 'flag_i', 'flag_s',
              'd_reg', 'q_out', 't_reg',
              'ivt_base', 'ivec_id', 'trap_addr',
              'halted', 'idle', 'cycle_count', '_ext_modifier'):
        setattr(cpu, k, state[k])

def build_snapshot():
    """Boot BIOS + KDOS + url.f, save snapshot for fast test replay."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + url.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    url_lines   = _load_forth_lines(URL_F)

    # Test helper words
    test_helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _OB 512 ALLOT',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + event_lines + sem_lines + guard_lines + url_lines + test_helpers
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 600_000_000

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    err_lines = [l for l in text.strip().split('\n') if '?' in l]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-10:]:
            print(f"    {ln}")

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu), bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=50_000_000):
    """Restore snapshot, feed Forth lines, return UART text output."""
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
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
    data = payload.encode()
    pos = 0
    steps = 0

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    return uart_text(buf)


def tstr(s):
    """Build Forth lines that construct string s in _TB using TC."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        split_at = full.rfind(' ', 0, 70)
        if split_at == -1:
            split_at = 70
        lines.append(full[:split_at])
        full = full[split_at:].lstrip()
    if full:
        lines.append(full)
    return lines


# ---------------------------------------------------------------------------
#  Test framework
# ---------------------------------------------------------------------------

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()

    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True

    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        last = clean.split('\n')[-3:]
        print(f"        got (last lines): {last}")


# ---------------------------------------------------------------------------
#  Tests
# ---------------------------------------------------------------------------

def test_layer0():
    """Layer 0: Percent Encoding"""
    print("\n── Layer 0: Percent Encoding ──\n")

    # _URL-HEX-DIGIT
    check("HEX-DIGIT 0",
          [': _T 0 _URL-HEX-DIGIT EMIT ; _T'],
          "0")

    check("HEX-DIGIT 9",
          [': _T 9 _URL-HEX-DIGIT EMIT ; _T'],
          "9")

    check("HEX-DIGIT 10 (A)",
          [': _T 10 _URL-HEX-DIGIT EMIT ; _T'],
          "A")

    check("HEX-DIGIT 15 (F)",
          [': _T 15 _URL-HEX-DIGIT EMIT ; _T'],
          "F")

    # _URL-HEX-VAL
    check("HEX-VAL '0'",
          [': _T 48 _URL-HEX-VAL . ; _T'],
          "0 ")

    check("HEX-VAL 'A'",
          [': _T 65 _URL-HEX-VAL . ; _T'],
          "10 ")

    check("HEX-VAL 'f' (lowercase)",
          [': _T 102 _URL-HEX-VAL . ; _T'],
          "15 ")

    check("HEX-VAL invalid",
          [': _T 33 _URL-HEX-VAL . ; _T'],
          "-1 ")

    # URL-UNRESERVED?
    check("UNRESERVED 'A'",
          [': _T 65 URL-UNRESERVED? . ; _T'],
          "-1 ")

    check("UNRESERVED 'z'",
          [': _T 122 URL-UNRESERVED? . ; _T'],
          "-1 ")

    check("UNRESERVED '5'",
          [': _T 53 URL-UNRESERVED? . ; _T'],
          "-1 ")

    check("UNRESERVED '-'",
          [': _T 45 URL-UNRESERVED? . ; _T'],
          "-1 ")

    check("UNRESERVED '~'",
          [': _T 126 URL-UNRESERVED? . ; _T'],
          "-1 ")

    check("NOT UNRESERVED ' '",
          [': _T 32 URL-UNRESERVED? . ; _T'],
          "0 ")

    check("NOT UNRESERVED '/'",
          [': _T 47 URL-UNRESERVED? . ; _T'],
          "0 ")

    # URL-ENCODE
    check("ENCODE simple (no encoding needed)",
          [': _T S" hello" _OB 512 URL-ENCODE _OB SWAP TYPE ; _T'],
          "hello")

    check("ENCODE space → %20",
          tstr("hello world") +
          [': _T TA _OB 512 URL-ENCODE _OB SWAP TYPE ; _T'],
          "hello%20world")

    check("ENCODE slash → %2F",
          tstr("a/b") +
          [': _T TA _OB 512 URL-ENCODE _OB SWAP TYPE ; _T'],
          "a%2Fb")

    check("ENCODE mixed",
          tstr("foo bar&baz") +
          [': _T TA _OB 512 URL-ENCODE _OB SWAP TYPE ; _T'],
          "foo%20bar%26baz")

    # URL-DECODE
    check("DECODE simple",
          [': _T S" hello" _OB 512 URL-DECODE _OB SWAP TYPE ; _T'],
          "hello")

    check("DECODE %20 → space",
          tstr("hello%20world") +
          [': _T TA _OB 512 URL-DECODE _OB SWAP TYPE ; _T'],
          "hello world")

    check("DECODE %2F → slash",
          tstr("a%2Fb") +
          [': _T TA _OB 512 URL-DECODE _OB SWAP TYPE ; _T'],
          "a/b")

    check("DECODE + → space",
          tstr("hello+world") +
          [': _T TA _OB 512 URL-DECODE _OB SWAP TYPE ; _T'],
          "hello world")

    check("ENCODE-DECODE roundtrip",
          tstr("hello world!") +
          [': _T TA _OB 256 URL-ENCODE',
           '_OB SWAP _OB 256 + 256 URL-DECODE',
           '_OB 256 + SWAP TYPE ; _T'],
          "hello world!")


def test_layer1():
    """Layer 1: URL Parsing"""
    print("\n── Layer 1: URL Parsing ──\n")

    check("Parse http://example.com/path",
          tstr("http://example.com/path") +
          [': _T TA URL-PARSE . ; _T'],
          "0 ")

    check("HTTP scheme detected",
          tstr("http://example.com/path") +
          [': _T TA URL-PARSE DROP URL-SCHEME @ . ; _T'],
          "0 ")   # URL-S-HTTP = 0

    check("Host extracted",
          tstr("http://example.com/path") +
          [': _T TA URL-PARSE DROP URL-HOST URL-HOST-LEN @ TYPE ; _T'],
          "example.com")

    check("Path extracted",
          tstr("http://example.com/path") +
          [': _T TA URL-PARSE DROP URL-PATH URL-PATH-LEN @ TYPE ; _T'],
          "/path")

    check("Default HTTP port",
          tstr("http://example.com/path") +
          [': _T TA URL-PARSE DROP URL-PORT @ . ; _T'],
          "80 ")

    check("HTTPS scheme + port",
          tstr("https://secure.example.com/api") +
          [': _T TA URL-PARSE DROP URL-SCHEME @ . URL-PORT @ . ; _T'],
          "1 443 ")  # URL-S-HTTPS=1, port=443

    check("Custom port",
          tstr("http://localhost:8080/test") +
          [': _T TA URL-PARSE DROP URL-PORT @ . ; _T'],
          "8080 ")

    check("Custom port host",
          tstr("http://localhost:8080/test") +
          [': _T TA URL-PARSE DROP URL-HOST URL-HOST-LEN @ TYPE ; _T'],
          "localhost")

    check("FTP scheme",
          tstr("ftp://files.example.com/pub/readme.txt") +
          [': _T TA URL-PARSE DROP URL-SCHEME @ . URL-PORT @ . ; _T'],
          "2 21 ")  # URL-S-FTP=2, port=21

    check("Gopher scheme",
          tstr("gopher://gopher.floodgap.com/") +
          [': _T TA URL-PARSE DROP URL-SCHEME @ . URL-PORT @ . ; _T'],
          "5 70 ")  # URL-S-GOPHER=5, port=70

    check("Rabbit scheme",
          tstr("rabbit://myburrow.local:7443/0/readme") +
          [': _T TA URL-PARSE DROP URL-SCHEME @ . URL-PORT @ . ; _T'],
          "6 7443 ")  # URL-S-RABBIT=6, port=7443

    check("Rabbit path",
          tstr("rabbit://myburrow.local/0/readme") +
          [': _T TA URL-PARSE DROP URL-PATH URL-PATH-LEN @ TYPE ; _T'],
          "/0/readme")

    check("Query string parsed",
          tstr("http://example.com/search?q=hello&lang=en") +
          [': _T TA URL-PARSE DROP URL-QUERY-BUF URL-QUERY-LEN @ TYPE ; _T'],
          "q=hello&lang=en")

    check("Fragment parsed",
          tstr("http://example.com/page#section1") +
          [': _T TA URL-PARSE DROP URL-FRAG URL-FRAG-LEN @ TYPE ; _T'],
          "section1")

    check("Query + fragment together",
          tstr("http://example.com/page?key=val#frag") +
          [': _T TA URL-PARSE DROP',
           'URL-QUERY-BUF URL-QUERY-LEN @ TYPE',
           '32 EMIT',
           'URL-FRAG URL-FRAG-LEN @ TYPE ; _T'],
          "key=val frag")

    check("No path defaults to /",
          tstr("http://example.com") +
          [': _T TA URL-PARSE DROP URL-PATH URL-PATH-LEN @ TYPE ; _T'],
          "/")

    check("Unknown scheme fails",
          tstr("xyz://foo/bar") +
          [': _T TA URL-PARSE . ; _T'],
          "-1 ")

    check("URL-DEFAULT-PORT http",
          [': _T 0 URL-DEFAULT-PORT . ; _T'],
          "80 ")

    check("URL-DEFAULT-PORT rabbit",
          [': _T 6 URL-DEFAULT-PORT . ; _T'],
          "7443 ")


def test_layer2():
    """Layer 2: Query String Parsing & Building"""
    print("\n── Layer 2: Query String Parsing ──\n")

    check("QUERY-NEXT first pair",
          tstr("key1=val1&key2=val2") +
          [': _T TA URL-QUERY-NEXT',
           'IF TYPE 32 EMIT TYPE 32 EMIT 2DROP',
           'ELSE 2DROP 2DROP THEN ; _T'],
          "val1 key1 ")

    check("QUERY-NEXT iterates both pairs",
          tstr("a=1&b=2") +
          [': _T TA',
           'URL-QUERY-NEXT IF TYPE 32 EMIT 2DROP ELSE 2DROP THEN',
           'URL-QUERY-NEXT IF TYPE 32 EMIT 2DROP ELSE 2DROP THEN',
           '; _T'],
          "1 2 ")

    check("QUERY-FIND existing key",
          tstr("name=alice&age=30") +
          [': _T TA S" age" URL-QUERY-FIND',
           'IF TYPE ELSE 2DROP THEN ; _T'],
          "30")

    check("QUERY-FIND missing key",
          tstr("name=alice") +
          [': _T TA S" missing" URL-QUERY-FIND',
           'IF TYPE ELSE 2DROP 46 EMIT THEN ; _T'],
          ".")


def test_layer3():
    """Layer 3: URL Building"""
    print("\n── Layer 3: URL Building ──\n")

    check("Build simple HTTP URL",
          [': _T _OB 512 URL-BUILD',
           '0 URL-BUILD-SCHEME',
           'S" example.com" URL-BUILD-HOST',
           '80 URL-BUILD-PORT',
           'S" /path" URL-BUILD-PATH',
           'URL-BUILD-RESULT TYPE ; _T'],
          "http://example.com/path")

    check("Build HTTPS with non-default port",
          [': _T _OB 512 URL-BUILD',
           '1 URL-BUILD-SCHEME',
           'S" api.example.com" URL-BUILD-HOST',
           '8443 URL-BUILD-PORT',
           'S" /v1/data" URL-BUILD-PATH',
           'URL-BUILD-RESULT TYPE ; _T'],
          "https://api.example.com:8443/v1/data")

    check("Build Rabbit URL",
          [': _T _OB 512 URL-BUILD',
           '6 URL-BUILD-SCHEME',
           'S" myburrow.local" URL-BUILD-HOST',
           '7443 URL-BUILD-PORT',
           'S" /0/readme" URL-BUILD-PATH',
           'URL-BUILD-RESULT TYPE ; _T'],
          "rabbit://myburrow.local/0/readme")

    check("Default port omitted",
          [': _T _OB 512 URL-BUILD',
           '0 URL-BUILD-SCHEME',
           'S" example.com" URL-BUILD-HOST',
           '80 URL-BUILD-PORT',
           'URL-BUILD-RESULT TYPE ; _T'],
          "http://example.com")

    check("Non-default port included",
          [': _T _OB 512 URL-BUILD',
           '0 URL-BUILD-SCHEME',
           'S" example.com" URL-BUILD-HOST',
           '3000 URL-BUILD-PORT',
           'URL-BUILD-RESULT TYPE ; _T'],
          "http://example.com:3000")


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    build_snapshot()

    test_layer0()
    test_layer1()
    test_layer2()
    test_layer3()

    print(f"\n{'='*60}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*60}")
    sys.exit(1 if _fail_count > 0 else 0)
