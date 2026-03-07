#!/usr/bin/env python3
"""Test suite for Akashic fmt.f (akashic/utils/fmt.f).

Tests hex nibble conversion, byte display, multi-byte hex printing,
hex string builder, cell-as-hex display, and hexdump formatting.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

FMT_F      = os.path.join(ROOT_DIR, "akashic", "utils", "fmt.f")

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
            if s.startswith('REQUIRE '):
                continue
            if s.startswith('PROVIDED '):
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
    print("[*] Building snapshot: BIOS + KDOS + fmt.f ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    fmt_lines  = _load_forth_lines(FMT_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + fmt_lines
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 400_000_000
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
    errors = []
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            errors.append(l.strip())
            print(f"  [!] {l.strip()}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors during load!")
        for l in text.strip().split('\n')[-20:]:
            print(f"    {l}")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=200_000_000):
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

# ── Test framework ──

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

def check_fn(name, forth_lines, predicate, desc=""):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if predicate(clean):
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  ({desc})")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

# ── Tests ──

def test_compile():
    print("\n=== Compile check ===")
    check("Module loaded", ['1 2 + .'], "3")

def test_nib_to_char():
    """FMT-NIB>C converts nibbles to hex chars."""
    print("\n=== FMT-NIB>C ===")
    check("nibble 0",  ['0  FMT-NIB>C EMIT'], "0")
    check("nibble 9",  ['9  FMT-NIB>C EMIT'], "9")
    check("nibble 10", ['10 FMT-NIB>C EMIT'], "a")
    check("nibble 15", ['15 FMT-NIB>C EMIT'], "f")

def test_dot_nib():
    """FMT-.NIB emits a single hex nibble."""
    print("\n=== FMT-.NIB ===")
    check("emit nib 0",  ['0  FMT-.NIB'], "0")
    check("emit nib 12", ['12 FMT-.NIB'], "c")

def test_dot_byte():
    """FMT-.BYTE emits a byte as two hex chars."""
    print("\n=== FMT-.BYTE ===")
    check("byte 0x00",  ['0   FMT-.BYTE'], "00")
    check("byte 0xFF",  ['255 FMT-.BYTE'], "ff")
    check("byte 0xAB",  ['0xAB FMT-.BYTE'], "ab")
    check("byte 0x0A",  ['10  FMT-.BYTE'], "0a")

def test_dot_hex():
    """FMT-.HEX emits n bytes as hex."""
    print("\n=== FMT-.HEX ===")
    # Build a 4-byte buffer with DE AD BE EF and print it
    lines = [
        'CREATE _BUF 4 ALLOT',
        '0xDE _BUF C!  0xAD _BUF 1+ C!  0xBE _BUF 2 + C!  0xEF _BUF 3 + C!',
        '_BUF 4 FMT-.HEX',
    ]
    check("deadbeef", lines, "deadbeef")

    # Empty buffer — should print nothing, no crash
    check("zero length", ['CREATE _E 1 ALLOT  _E 0 FMT-.HEX ." OK"'], "OK")

    # Single byte
    lines2 = [
        'CREATE _B1 1 ALLOT  0x42 _B1 C!',
        '_B1 1 FMT-.HEX',
    ]
    check("single byte 0x42", lines2, "42")

def test_to_hex():
    """FMT->HEX writes hex to a buffer (no EMIT)."""
    print("\n=== FMT->HEX ===")
    lines = [
        'CREATE _SRC 3 ALLOT',
        '0xCA _SRC C!  0xFE _SRC 1+ C!  0x01 _SRC 2 + C!',
        'CREATE _DST 6 ALLOT',
        '_SRC 3 _DST FMT->HEX .',     # should print 6
        '_DST 6 TYPE',                  # should print cafe01
    ]
    check_fn("->HEX writes 6 chars", lines,
             lambda out: "6" in out and "cafe01" in out,
             "len=6 and content=cafe01")

    # Return value is always n*2
    lines2 = [
        'CREATE _S2 1 ALLOT  0xFF _S2 C!',
        'CREATE _D2 2 ALLOT',
        '_S2 1 _D2 FMT->HEX .',
    ]
    check("return 2 for 1 byte", lines2, "2")

def test_u_dot_h():
    """FMT-U.H emits a full 64-bit cell as 16 hex chars."""
    print("\n=== FMT-U.H ===")
    check("zero", ['0 FMT-U.H'], "0000000000000000")
    check("0xFF", ['255 FMT-U.H'], "00000000000000ff")
    check("0x123", ['0x123 FMT-U.H'], "0000000000000123")

def test_u_dot_h4():
    """FMT-U.H4 emits low 32 bits as 8 hex chars."""
    print("\n=== FMT-U.H4 ===")
    check("zero",   ['0 FMT-U.H4'],     "00000000")
    check("0xFF",   ['255 FMT-U.H4'],   "000000ff")
    check("0xDEAD", ['0xDEAD FMT-U.H4'], "0000dead")

def test_hexdump_basic():
    """FMT-.HEXDUMP doesn't crash and shows hex output."""
    print("\n=== FMT-.HEXDUMP ===")
    # 5 bytes: "Hello"
    lines = [
        'CREATE _HD 5 ALLOT',
        '72 _HD C!  101 _HD 1+ C!  108 _HD 2 + C!  108 _HD 3 + C!  111 _HD 4 + C!',
        '_HD 5 FMT-.HEXDUMP',
        '." DONE"',
    ]
    check_fn("hexdump runs", lines,
             lambda out: "DONE" in out and "48" in out,
             "completes and shows hex 48 for 'H'")

    # Check it shows ASCII sidebar
    check_fn("hexdump ASCII sidebar", lines,
             lambda out: "|" in out and "Hello" in out,
             "ASCII sidebar shows Hello")

def test_hexdump_multiline():
    """FMT-.HEXDUMP wraps at 16 bytes."""
    print("\n=== FMT-.HEXDUMP multi-line ===")
    # 20 bytes — should produce 2 lines
    lines = [
        'CREATE _HD2 20 ALLOT',
        '20 0 DO  65 I + _HD2 I + C!  LOOP',   # A B C D ... T
        '_HD2 20 FMT-.HEXDUMP',
        '." DONE"',
    ]
    check_fn("20 bytes = 2 lines", lines,
             lambda out: "DONE" in out and "00000010" in out,
             "second line starts with offset 00000010")

# ── Main ──

if __name__ == "__main__":
    build_snapshot()

    test_compile()
    test_nib_to_char()
    test_dot_nib()
    test_dot_byte()
    test_dot_hex()
    test_to_hex()
    test_u_dot_h()
    test_u_dot_h4()
    test_hexdump_basic()
    test_hexdump_multiline()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    if _fail_count:
        sys.exit(1)
    print("  All tests passed!")
