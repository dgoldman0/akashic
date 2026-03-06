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
"""Test suite for akashic-base64 Forth library."""
import os, sys, time, base64

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
B64_F      = os.path.join(ROOT_DIR, "akashic", "net", "base64.f")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers (same as test_url.py) ──

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
    return {
        'pc': cpu.pc, 'regs': list(cpu.regs),
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
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + base64.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    b64_lines   = _load_forth_lines(B64_F)

    test_helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _OB 512 ALLOT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + event_lines + sem_lines + guard_lines + b64_lines + test_helpers
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0; steps = 0; max_steps = 600_000_000

    while steps < max_steps:
        if sys_obj.cpu.halted: break
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
    err_lines = [l for l in text.strip().split('\n')
                 if '?' in l and 'not found' in l.lower()]
    if err_lines:
        print("[!] Compilation errors:")
        for ln in err_lines[-10:]:
            print(f"    {ln}")

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu), bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
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
    data = payload.encode()
    pos = 0; steps = 0

    while steps < max_steps:
        if sys_obj.cpu.halted: break
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
    """Build Forth lines that construct string s in _TB."""
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
    if full:
        lines.append(full)
    return lines

# ── Test framework ──

_pass = 0
_fail = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True
    if ok:
        _pass += 1
        print(f"  PASS  {name}")
    else:
        _fail += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        last = clean.split('\n')[-3:]
        print(f"        got (last lines): {last}")


# ── Encoding tests ──

def test_encode():
    print("\n── B64-ENCODE ──\n")

    # RFC 4648 test vectors
    check("encode empty",
          [': _T S" " _OB 512 B64-ENCODE . ; _T'],
          "0 ")

    check("encode 'f'",
          [': _T S" f" _OB 512 B64-ENCODE _OB SWAP TYPE ; _T'],
          "Zg==")

    check("encode 'fo'",
          [': _T S" fo" _OB 512 B64-ENCODE _OB SWAP TYPE ; _T'],
          "Zm8=")

    check("encode 'foo'",
          [': _T S" foo" _OB 512 B64-ENCODE _OB SWAP TYPE ; _T'],
          "Zm9v")

    check("encode 'foob'",
          [': _T S" foob" _OB 512 B64-ENCODE _OB SWAP TYPE ; _T'],
          "Zm9vYg==")

    check("encode 'fooba'",
          [': _T S" fooba" _OB 512 B64-ENCODE _OB SWAP TYPE ; _T'],
          "Zm9vYmE=")

    check("encode 'foobar'",
          [': _T S" foobar" _OB 512 B64-ENCODE _OB SWAP TYPE ; _T'],
          "Zm9vYmFy")

    check("encode 'Hello, World!'",
          tstr("Hello, World!") +
          [': _T TA _OB 512 B64-ENCODE _OB SWAP TYPE ; _T'],
          "SGVsbG8sIFdvcmxkIQ==")


def test_decode():
    print("\n── B64-DECODE ──\n")

    check("decode empty",
          [': _T S" " _OB 512 B64-DECODE . ; _T'],
          "0 ")

    check("decode 'Zg=='",
          tstr("Zg==") +
          [': _T TA _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "f")

    check("decode 'Zm8='",
          tstr("Zm8=") +
          [': _T TA _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "fo")

    check("decode 'Zm9v'",
          tstr("Zm9v") +
          [': _T TA _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "foo")

    check("decode 'Zm9vYg=='",
          tstr("Zm9vYg==") +
          [': _T TA _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "foob")

    check("decode 'Zm9vYmE='",
          tstr("Zm9vYmE=") +
          [': _T TA _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "fooba")

    check("decode 'Zm9vYmFy'",
          tstr("Zm9vYmFy") +
          [': _T TA _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "foobar")

    check("decode 'SGVsbG8sIFdvcmxkIQ=='",
          tstr("SGVsbG8sIFdvcmxkIQ==") +
          [': _T TA _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "Hello, World!")

    # Decode without padding
    check("decode no-pad 'Zg'",
          [': _T S" Zg" _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "f")

    check("decode no-pad 'Zm8'",
          [': _T S" Zm8" _OB 512 B64-DECODE _OB SWAP TYPE ; _T'],
          "fo")


def test_roundtrip():
    print("\n── Roundtrip ──\n")

    check("encode→decode 'Hello'",
          tstr("Hello") +
          [': _T TA _OB 512 B64-ENCODE',
           '_OB SWAP _OB 256 + 256 B64-DECODE',
           '_OB 256 + SWAP TYPE ; _T'],
          "Hello")

    # Binary data (non-printable bytes)
    check("roundtrip binary",
          ['TR 0 TC 1 TC 255 TC 128 TC 64 TC',
           ': _T TA _OB 512 B64-ENCODE',
           '_OB SWAP _OB 256 + 256 B64-DECODE',
           '5 = . ; _T'],   # check decoded length = 5
          "-1 ")


def test_url_safe():
    print("\n── URL-safe ──\n")

    # Standard encodes bytes 62,63 as +/; URL-safe as -_
    # Input: 0xFB 0xEF 0xBE  → standard = "++/+"  → url-safe = "--_-"
    # Actually let's use known test:  0x3F 0xBF 0xFF → P7//
    # Better: use a string that produces + and / in standard

    check("url encode no padding",
          [': _T S" fo" _OB 512 B64-ENCODE-URL _OB SWAP TYPE ; _T'],
          "Zm8")   # no '=' padding

    check("url encode 1-byte no padding",
          [': _T S" f" _OB 512 B64-ENCODE-URL _OB SWAP TYPE ; _T'],
          "Zg")    # no '==' padding

    check("url decode same as standard",
          [': _T S" Zm9v" _OB 512 B64-DECODE-URL _OB SWAP TYPE ; _T'],
          "foo")

    # Standard + and / should decode with B64-DECODE
    check("standard decode + and /",
          tstr("++//") +
          [': _T TA _OB 512 B64-DECODE . ; _T'],
          "3 ")    # 4 base64 chars → 3 decoded bytes

    # URL-safe - and _ should also decode
    check("url-safe decode - and _",
          tstr("--__") +
          [': _T TA _OB 512 B64-DECODE-URL . ; _T'],
          "3 ")


def test_length():
    print("\n── Length Calculations ──\n")

    check("ENCODED-LEN 0",
          [': _T 0 B64-ENCODED-LEN . ; _T'], "0 ")
    check("ENCODED-LEN 1",
          [': _T 1 B64-ENCODED-LEN . ; _T'], "4 ")
    check("ENCODED-LEN 2",
          [': _T 2 B64-ENCODED-LEN . ; _T'], "4 ")
    check("ENCODED-LEN 3",
          [': _T 3 B64-ENCODED-LEN . ; _T'], "4 ")
    check("ENCODED-LEN 4",
          [': _T 4 B64-ENCODED-LEN . ; _T'], "8 ")
    check("ENCODED-LEN 6",
          [': _T 6 B64-ENCODED-LEN . ; _T'], "8 ")

    check("DECODED-LEN 0",
          [': _T 0 B64-DECODED-LEN . ; _T'], "0 ")
    check("DECODED-LEN 4",
          [': _T 4 B64-DECODED-LEN . ; _T'], "3 ")
    check("DECODED-LEN 8",
          [': _T 8 B64-DECODED-LEN . ; _T'], "6 ")


def test_errors():
    print("\n── Error Handling ──\n")

    check("invalid char sets error",
          tstr("Zm9!v") +
          [': _T TA _OB 512 B64-DECODE DROP B64-OK? . ; _T'],
          "0 ")    # B64-OK? returns false


# ── Main ──

if __name__ == "__main__":
    build_snapshot()
    test_encode()
    test_decode()
    test_roundtrip()
    test_url_safe()
    test_length()
    test_errors()

    print(f"\n{'='*60}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*60}")
    sys.exit(1 if _fail > 0 else 0)
