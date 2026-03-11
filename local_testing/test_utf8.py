#!/usr/bin/env python3
"""Test suite for akashic-utf8: utf8.f — UTF-8 codec.

Tests encode, decode, length counting, validation, and nth-codepoint
lookup against the Megapad-64 emulator.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")

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
    buf = bytearray()
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
    if _snapshot:
        return _snapshot
    print("[*] Building snapshot: BIOS + KDOS + utf8.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    utf8_lines = _load_forth_lines(UTF8_F)

    # Scratch buffers for tests
    helpers = [
        'CREATE _TBUF 16 ALLOT',   # encode output buffer
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    payload = "\n".join(
        kdos_lines + ["ENTER-USERLAND"] + utf8_lines + helpers
    ) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    mx = 800_000_000

    while steps < mx:
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
        batch = sys_obj.run_batch(min(100_000, mx - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    errors = False
    for l in text.strip().split('\n'):
        if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower()):
            print(f"  [!] COMPILE ERROR: {l}")
            errors = True
    if errors:
        print("[!] Snapshot has compilation errors — tests may fail.")

    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def _make_system():
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    return sys_obj


def run_forth(lines, max_steps=50_000_000):
    sys_obj = _make_system()
    buf = capture_uart(sys_obj)
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
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")


# =====================================================================
#  Helper: build a Forth CREATE buffer with specific bytes
# =====================================================================

def make_buf(name, byte_list):
    """Return Forth lines that CREATE a named buffer with given bytes."""
    lines = [f'CREATE {name} {len(byte_list)} ALLOT']
    for i, b in enumerate(byte_list):
        lines.append(f'{b} {name} {i} + C!')
    return lines


# =====================================================================
#  DECODE tests
# =====================================================================

def test_decode_ascii():
    print("\n── UTF8-DECODE ASCII ──")
    # 'A' = 0x41, 1 byte
    buf = make_buf('_DB', [0x41, 0x42, 0x43])
    check("decode A",
        buf + ['_DB 3 UTF8-DECODE ROT . SWAP . .'],
        "65 2")  # cp=65, len'=2  (addr changes)

    # Single byte
    check("decode single Z",
        make_buf('_DB', [0x5A]) + ['_DB 1 UTF8-DECODE ROT . SWAP DROP .'],
        "90 0")


def test_decode_2byte():
    print("\n── UTF8-DECODE 2-byte ──")
    # U+00E9 = é = C3 A9
    check("decode é (U+00E9)",
        make_buf('_DB', [0xC3, 0xA9]) + ['_DB 2 UTF8-DECODE ROT . SWAP DROP .'],
        "233 0")

    # U+00A9 = © = C2 A9
    check("decode © (U+00A9)",
        make_buf('_DB', [0xC2, 0xA9, 0x58]) + ['_DB 3 UTF8-DECODE ROT . SWAP DROP .'],
        "169 1")


def test_decode_3byte():
    print("\n── UTF8-DECODE 3-byte ──")
    # U+263A = ☺ = E2 98 BA
    check("decode ☺ (U+263A)",
        make_buf('_DB', [0xE2, 0x98, 0xBA]) + ['_DB 3 UTF8-DECODE ROT . SWAP DROP .'],
        "9786 0")

    # U+4E16 = 世 = E4 B8 96
    check("decode 世 (U+4E16)",
        make_buf('_DB', [0xE4, 0xB8, 0x96]) + ['_DB 3 UTF8-DECODE ROT . SWAP DROP .'],
        "19990 0")


def test_decode_4byte():
    print("\n── UTF8-DECODE 4-byte ──")
    # U+1F600 = 😀 = F0 9F 98 80
    check("decode 😀 (U+1F600)",
        make_buf('_DB', [0xF0, 0x9F, 0x98, 0x80]) +
        ['_DB 4 UTF8-DECODE ROT . SWAP DROP .'],
        "128512 0")

    # U+10348 = 𐍈 = F0 90 8D 88
    check("decode 𐍈 (U+10348)",
        make_buf('_DB', [0xF0, 0x90, 0x8D, 0x88]) +
        ['_DB 4 UTF8-DECODE ROT . SWAP DROP .'],
        "66376 0")


def test_decode_invalid():
    print("\n── UTF8-DECODE invalid sequences ──")
    # Bare continuation byte → U+FFFD, advance 1
    check("decode bare continuation",
        make_buf('_DB', [0x80]) + ['_DB 1 UTF8-DECODE ROT . SWAP DROP .'],
        "65533 0")

    # Truncated 2-byte (missing continuation)
    check("decode truncated 2-byte",
        make_buf('_DB', [0xC3]) + ['_DB 1 UTF8-DECODE ROT . SWAP DROP .'],
        "65533 0")

    # Overlong 2-byte: U+0041 encoded as C1 81 (should be just 41)
    check("decode overlong 2-byte",
        make_buf('_DB', [0xC1, 0x81]) + ['_DB 2 UTF8-DECODE ROT . SWAP DROP .'],
        "65533 0")

    # Empty buffer
    check("decode empty buffer",
        ['0 0 UTF8-DECODE ROT . SWAP DROP .'],
        "65533 0")


# =====================================================================
#  ENCODE tests
# =====================================================================

def test_encode_ascii():
    print("\n── UTF8-ENCODE ASCII ──")
    # 'A' = 0x41 → 1 byte
    check("encode A",
        ['65 _TBUF UTF8-ENCODE _TBUF - .  _TBUF C@ .'],
        "1 65")

    check("encode space",
        ['32 _TBUF UTF8-ENCODE _TBUF - .  _TBUF C@ .'],
        "1 32")


def test_encode_2byte():
    print("\n── UTF8-ENCODE 2-byte ──")
    # U+00E9 = é → C3 A9
    check("encode é (U+00E9)",
        ['233 _TBUF UTF8-ENCODE _TBUF - .  _TBUF C@ .  _TBUF 1 + C@ .'],
        "2 195 169")

    # U+00A9 = © → C2 A9
    check("encode © (U+00A9)",
        ['169 _TBUF UTF8-ENCODE _TBUF - .  _TBUF C@ .  _TBUF 1 + C@ .'],
        "2 194 169")


def test_encode_3byte():
    print("\n── UTF8-ENCODE 3-byte ──")
    # U+263A = ☺ → E2 98 BA
    check("encode ☺ (U+263A)",
        ['9786 _TBUF UTF8-ENCODE _TBUF - .  _TBUF C@ .  _TBUF 1 + C@ .  _TBUF 2 + C@ .'],
        "3 226 152 186")


def test_encode_4byte():
    print("\n── UTF8-ENCODE 4-byte ──")
    # U+1F600 = 😀 → F0 9F 98 80
    check("encode 😀 (U+1F600)",
        ['128512 _TBUF UTF8-ENCODE _TBUF - .  _TBUF C@ .  _TBUF 1 + C@ .  _TBUF 2 + C@ .  _TBUF 3 + C@ .'],
        "4 240 159 152 128")


def test_encode_decode_roundtrip():
    print("\n── UTF8 encode → decode round-trip ──")
    check("roundtrip ASCII 'Z'",
        ['90 _TBUF UTF8-ENCODE _TBUF -  _TBUF SWAP UTF8-DECODE ROT . 2DROP'],
        "90")
    check("roundtrip U+00E9",
        ['233 _TBUF UTF8-ENCODE _TBUF -  _TBUF SWAP UTF8-DECODE ROT . 2DROP'],
        "233")
    check("roundtrip U+263A",
        ['9786 _TBUF UTF8-ENCODE _TBUF -  _TBUF SWAP UTF8-DECODE ROT . 2DROP'],
        "9786")
    check("roundtrip U+1F600",
        ['128512 _TBUF UTF8-ENCODE _TBUF -  _TBUF SWAP UTF8-DECODE ROT . 2DROP'],
        "128512")


# =====================================================================
#  UTF8-LEN tests
# =====================================================================

def test_len():
    print("\n── UTF8-LEN ──")
    # "ABC" = 3 codepoints
    check("len ASCII 3",
        make_buf('_DB', [0x41, 0x42, 0x43]) + ['_DB 3 UTF8-LEN .'],
        "3")

    # "Aé" = 2 codepoints (1 + 2 bytes)
    check("len mixed 2",
        make_buf('_DB', [0x41, 0xC3, 0xA9]) + ['_DB 3 UTF8-LEN .'],
        "2")

    # "☺" = 1 codepoint (3 bytes)
    check("len 3-byte 1",
        make_buf('_DB', [0xE2, 0x98, 0xBA]) + ['_DB 3 UTF8-LEN .'],
        "1")

    # "😀" = 1 codepoint (4 bytes)
    check("len 4-byte 1",
        make_buf('_DB', [0xF0, 0x9F, 0x98, 0x80]) + ['_DB 4 UTF8-LEN .'],
        "1")

    # empty
    check("len empty",
        ['0 0 UTF8-LEN .'],
        "0")

    # "Aé☺" = 3 codepoints (1+2+3 = 6 bytes)
    check("len mixed 3",
        make_buf('_DB', [0x41, 0xC3, 0xA9, 0xE2, 0x98, 0xBA]) +
        ['_DB 6 UTF8-LEN .'],
        "3")


# =====================================================================
#  UTF8-VALID? tests
# =====================================================================

def test_valid():
    print("\n── UTF8-VALID? ──")
    check("valid ASCII",
        make_buf('_DB', [0x41, 0x42]) + ['_DB 2 UTF8-VALID? .'],
        "-1")

    check("valid 2-byte",
        make_buf('_DB', [0xC3, 0xA9]) + ['_DB 2 UTF8-VALID? .'],
        "-1")

    check("valid 3-byte",
        make_buf('_DB', [0xE2, 0x98, 0xBA]) + ['_DB 3 UTF8-VALID? .'],
        "-1")

    check("valid 4-byte",
        make_buf('_DB', [0xF0, 0x9F, 0x98, 0x80]) + ['_DB 4 UTF8-VALID? .'],
        "-1")

    check("invalid bare continuation",
        make_buf('_DB', [0x80]) + ['_DB 1 UTF8-VALID? .'],
        "0")

    check("invalid truncated",
        make_buf('_DB', [0xC3]) + ['_DB 1 UTF8-VALID? .'],
        "0")

    check("valid empty",
        ['0 0 UTF8-VALID? .'],
        "-1")

    check("valid mixed",
        make_buf('_DB', [0x41, 0xC3, 0xA9, 0xE2, 0x98, 0xBA, 0xF0, 0x9F, 0x98, 0x80]) +
        ['_DB 10 UTF8-VALID? .'],
        "-1")


# =====================================================================
#  UTF8-NTH tests
# =====================================================================

def test_nth():
    print("\n── UTF8-NTH ──")
    # "Aé☺" = codepoints [65, 233, 9786]
    buf = make_buf('_DB', [0x41, 0xC3, 0xA9, 0xE2, 0x98, 0xBA])
    check("nth 0 → A",
        buf + ['_DB 6 0 UTF8-NTH .'],
        "65")
    check("nth 1 → é",
        buf + ['_DB 6 1 UTF8-NTH .'],
        "233")
    check("nth 2 → ☺",
        buf + ['_DB 6 2 UTF8-NTH .'],
        "9786")
    check("nth out of range → FFFD",
        buf + ['_DB 6 5 UTF8-NTH .'],
        "65533")


# =====================================================================
#  UTF8-REPLACEMENT constant test
# =====================================================================

def test_replacement():
    print("\n── UTF8-REPLACEMENT ──")
    check("replacement = U+FFFD",
        ['UTF8-REPLACEMENT .'],
        "65533")


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()

    test_decode_ascii()
    test_decode_2byte()
    test_decode_3byte()
    test_decode_4byte()
    test_decode_invalid()

    test_encode_ascii()
    test_encode_2byte()
    test_encode_3byte()
    test_encode_4byte()
    test_encode_decode_roundtrip()

    test_len()
    test_valid()
    test_nth()
    test_replacement()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail_count else 0)
