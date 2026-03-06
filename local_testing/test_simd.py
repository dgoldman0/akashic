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
"""Test suite for integer SIMD / multi-mode tile engine support (simd.f).

Tests: mode words (U8-MODE, U16-MODE, U32-MODE, etc.),
       mode-agnostic TILE- ops (ADD, SUB, MUL, WMUL, bitwise, reductions),
       fill helpers, saturating modes, and the existing FP16 SIMD- API
       to verify no regressions.
"""
import os, sys, time, struct

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
MATH_DIR   = os.path.join(ROOT_DIR, "akashic", "math")

FP16_F     = os.path.join(MATH_DIR, "fp16.f")
FP16EXT_F  = os.path.join(MATH_DIR, "fp16-ext.f")
SIMD_F     = os.path.join(MATH_DIR, "simd.f")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── FP16 helpers ──

def fp16(val):
    import numpy as np
    return int(np.float16(val).view(np.uint16))

def fp16_to_float(bits):
    import numpy as np
    return float(np.uint16(bits & 0xFFFF).view(np.float16))

FP16_ONE  = 0x3C00
FP16_TWO  = 0x4000
FP16_THREE = 0x4200

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
    print("[*] Building snapshot: BIOS + KDOS + fp16 + simd ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    fp16_lines  = _load_forth_lines(FP16_F)
    fp16e_lines = _load_forth_lines(FP16EXT_F)
    simd_lines  = _load_forth_lines(SIMD_F)
    event_lines  = _load_forth_lines(EVENT_F)
    sem_lines    = _load_forth_lines(SEM_F)
    guard_lines  = _load_forth_lines(GUARD_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + event_lines + sem_lines + guard_lines
                 + fp16_lines + fp16e_lines
                 + simd_lines)
    payload = "\n".join(all_lines) + "\n"
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
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            print(f"  [!] {l}")
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

# ── Tile alloc helper (used in most tests) ──
# Allocate 3 tiles: a, b, c  (each 64 bytes in HBW)
ALLOC_ABC = [
    'SIMD-ALLOT CONSTANT _a',
    'SIMD-ALLOT CONSTANT _b',
    'SIMD-ALLOT CONSTANT _c',
]

# ====================================================================
#  Mode word tests
# ====================================================================

def test_mode_words():
    print("\n=== Mode Words ===")

    check("U8-MODE sets TMODE to 0",
          ['U8-MODE  TMODE@ .'],
          '0 ')

    check("I8-MODE sets TMODE to 0x10",
          ['I8-MODE  TMODE@ .'],
          '16 ')

    check("U8S-MODE sets TMODE to 0x20",
          ['U8S-MODE  TMODE@ .'],
          '32 ')

    check("I8S-MODE sets TMODE to 0x30",
          ['I8S-MODE  TMODE@ .'],
          '48 ')

    check("U16-MODE sets TMODE to 1",
          ['U16-MODE  TMODE@ .'],
          '1 ')

    check("I16-MODE sets TMODE to 0x11",
          ['I16-MODE  TMODE@ .'],
          '17 ')

    check("U32-MODE sets TMODE to 2",
          ['U32-MODE  TMODE@ .'],
          '2 ')

    check("I32-MODE sets TMODE to 0x12",
          ['I32-MODE  TMODE@ .'],
          '18 ')

    check("U64-MODE sets TMODE to 3",
          ['U64-MODE  TMODE@ .'],
          '3 ')

    check("I64-MODE sets TMODE to 0x13",
          ['I64-MODE  TMODE@ .'],
          '19 ')

# ====================================================================
#  U8 mode tests (64 lanes, unsigned 8-bit)
# ====================================================================

def test_u8_add():
    print("\n=== U8 TILE-ADD ===")
    # Fill a with 10, b with 20, add → c should be 30
    check("u8 add 10+20=30",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 10 TILE-FILL-U8',
              '_b 20 TILE-FILL-U8',
              '_a _b _c TILE-ADD',
              '_c C@ .  _c 32 + C@ .  _c 63 + C@ .',
          ],
          '30 30 30')

def test_u8_sub():
    print("\n=== U8 TILE-SUB ===")
    check("u8 sub 50-20=30",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 50 TILE-FILL-U8',
              '_b 20 TILE-FILL-U8',
              '_a _b _c TILE-SUB',
              '_c C@ .  _c 63 + C@ .',
          ],
          '30 30')

def test_u8_mul():
    print("\n=== U8 TILE-MUL ===")
    # 3 * 7 = 21 (fits in u8)
    check("u8 mul 3*7=21",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 3 TILE-FILL-U8',
              '_b 7 TILE-FILL-U8',
              '_a _b _c TILE-MUL',
              '_c C@ .  _c 32 + C@ .',
          ],
          '21 21')
    # 16 * 20 = 320 → truncated to 320 & 0xFF = 64
    check("u8 mul 16*20 truncates to 64",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 16 TILE-FILL-U8',
              '_b 20 TILE-FILL-U8',
              '_a _b _c TILE-MUL',
              '_c C@ .',
          ],
          '64 ')

def test_u8_bitwise():
    print("\n=== U8 Bitwise ===")
    check("u8 AND 0xFF & 0x0F = 0x0F",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 255 TILE-FILL-U8',
              '_b 15 TILE-FILL-U8',
              '_a _b _c TILE-AND',
              '_c C@ .',
          ],
          '15 ')

    check("u8 OR 0xF0 | 0x0F = 0xFF",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 240 TILE-FILL-U8',
              '_b 15 TILE-FILL-U8',
              '_a _b _c TILE-OR',
              '_c C@ .',
          ],
          '255 ')

    check("u8 XOR 0xFF ^ 0x0F = 0xF0",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 255 TILE-FILL-U8',
              '_b 15 TILE-FILL-U8',
              '_a _b _c TILE-XOR',
              '_c C@ .',
          ],
          '240 ')

def test_u8_minmax():
    print("\n=== U8 MIN/MAX ===")
    check("u8 min(10,20)=10",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 10 TILE-FILL-U8',
              '_b 20 TILE-FILL-U8',
              '_a _b _c TILE-MIN',
              '_c C@ .',
          ],
          '10 ')

    check("u8 max(10,20)=20",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 10 TILE-FILL-U8',
              '_b 20 TILE-FILL-U8',
              '_a _b _c TILE-MAX',
              '_c C@ .',
          ],
          '20 ')

def test_u8_reductions():
    print("\n=== U8 Reductions ===")
    # Sum of 64 × 1 = 64
    check("u8 sum 64×1 = 64",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 1 TILE-FILL-U8',
              '_a TILE-SUM .',
          ],
          '64 ')

    # Sum of 64 × 3 = 192
    check("u8 sum 64×3 = 192",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 3 TILE-FILL-U8',
              '_a TILE-SUM .',
          ],
          '192 ')

    # rmin: fill with 50, set lane 0 to 5 → min=5
    check("u8 rmin",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 50 TILE-FILL-U8',
              '5 _a C!',
              '_a TILE-RMIN .',
          ],
          '5 ')

    # rmax: fill with 50, set lane 63 to 99 → max=99
    check("u8 rmax",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 50 TILE-FILL-U8',
              '99 _a 63 + C!',
              '_a TILE-RMAX .',
          ],
          '99 ')

def test_u8_saturating():
    print("\n=== U8 Saturating ===")
    # U8S-MODE: 200 + 200 should saturate to 255 (not wrap to 144)
    check("u8s add 200+200 saturates to 255",
          ALLOC_ABC + [
              'U8S-MODE',
              '_a 200 TILE-FILL-U8',
              '_b 200 TILE-FILL-U8',
              '_a _b _c TILE-ADD',
              '_c C@ .',
          ],
          '255 ')

    # U8S-MODE: 100 + 50 = 150 (no saturation)
    check("u8s add 100+50 = 150 (no sat)",
          ALLOC_ABC + [
              'U8S-MODE',
              '_a 100 TILE-FILL-U8',
              '_b 50 TILE-FILL-U8',
              '_a _b _c TILE-ADD',
              '_c C@ .',
          ],
          '150 ')

def test_u8_zero():
    print("\n=== U8 TILE-ZERO ===")
    check("tile-zero clears all 64 bytes",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 99 TILE-FILL-U8',
              '_a TILE-ZERO',
              '_a C@ .  _a 32 + C@ .  _a 63 + C@ .',
          ],
          '0 0 0')

def test_u8_copy():
    print("\n=== U8 TILE-COPY ===")
    check("tile-copy duplicates tile",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 42 TILE-FILL-U8',
              '_b TILE-ZERO',
              '_a _b TILE-COPY',
              '_b C@ .  _b 32 + C@ .  _b 63 + C@ .',
          ],
          '42 42 42')

# ====================================================================
#  U16 mode tests (32 lanes, unsigned 16-bit)
# ====================================================================

def test_u16_add():
    print("\n=== U16 TILE-ADD ===")
    check("u16 add 1000+2000=3000",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 1000 TILE-FILL-U16',
              '_b 2000 TILE-FILL-U16',
              '_a _b _c TILE-ADD',
              '_c W@ .  _c 62 + W@ .',   # lane 0 and lane 31
          ],
          '3000 3000')

def test_u16_mul():
    print("\n=== U16 TILE-MUL ===")
    # 200 * 100 = 20000 (fits in u16)
    check("u16 mul 200*100=20000",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 200 TILE-FILL-U16',
              '_b 100 TILE-FILL-U16',
              '_a _b _c TILE-MUL',
              '_c W@ .',
          ],
          '20000 ')

def test_u16_sub():
    print("\n=== U16 TILE-SUB ===")
    check("u16 sub 5000-3000=2000",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 5000 TILE-FILL-U16',
              '_b 3000 TILE-FILL-U16',
              '_a _b _c TILE-SUB',
              '_c W@ .',
          ],
          '2000 ')

def test_u16_reductions():
    print("\n=== U16 Reductions ===")
    # Sum of 32 × 10 = 320
    check("u16 sum 32×10 = 320",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 10 TILE-FILL-U16',
              '_a TILE-SUM .',
          ],
          '320 ')

    # Sum of 32 × 1000 = 32000
    check("u16 sum 32×1000 = 32000",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 1000 TILE-FILL-U16',
              '_a TILE-SUM .',
          ],
          '32000 ')

def test_u16_minmax():
    print("\n=== U16 MIN/MAX ===")
    check("u16 min(1000,2000)=1000",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 1000 TILE-FILL-U16',
              '_b 2000 TILE-FILL-U16',
              '_a _b _c TILE-MIN',
              '_c W@ .',
          ],
          '1000 ')

    check("u16 max(1000,2000)=2000",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 1000 TILE-FILL-U16',
              '_b 2000 TILE-FILL-U16',
              '_a _b _c TILE-MAX',
              '_c W@ .',
          ],
          '2000 ')

def test_u16_saturating():
    print("\n=== U16 Saturating ===")
    # U16S: 60000 + 60000 → 65535
    check("u16s add 60000+60000 saturates to 65535",
          ALLOC_ABC + [
              'U16S-MODE',
              '_a 60000 TILE-FILL-U16',
              '_b 60000 TILE-FILL-U16',
              '_a _b _c TILE-ADD',
              '_c W@ .',
          ],
          '65535 ')

# ====================================================================
#  U32 mode tests (16 lanes, unsigned 32-bit)
# ====================================================================

def test_u32_add():
    print("\n=== U32 TILE-ADD ===")
    check("u32 add 100000+200000=300000",
          ALLOC_ABC + [
              'U32-MODE',
              '_a 100000 TILE-FILL-U32',
              '_b 200000 TILE-FILL-U32',
              '_a _b _c TILE-ADD',
              '_c L@ .  _c 60 + L@ .',   # lane 0 and lane 15
          ],
          '300000 300000')

def test_u32_mul():
    print("\n=== U32 TILE-MUL ===")
    # 1000 * 500 = 500000 (fits in u32)
    check("u32 mul 1000*500=500000",
          ALLOC_ABC + [
              'U32-MODE',
              '_a 1000 TILE-FILL-U32',
              '_b 500 TILE-FILL-U32',
              '_a _b _c TILE-MUL',
              '_c L@ .',
          ],
          '500000 ')

def test_u32_reductions():
    print("\n=== U32 Reductions ===")
    # Sum of 16 × 100 = 1600
    check("u32 sum 16×100 = 1600",
          ALLOC_ABC + [
              'U32-MODE',
              '_a 100 TILE-FILL-U32',
              '_a TILE-SUM .',
          ],
          '1600 ')

# ====================================================================
#  Widening multiply test
# ====================================================================

def test_u8_wmul():
    print("\n=== U8 TILE-WMUL (widening) ===")
    # In u8 mode, wmul produces u16 outputs across dst (low) and dst+64 (high).
    # 10 * 20 = 200 fits in low byte, high = 0
    check("u8 wmul 10*20=200 (low tile)",
          ALLOC_ABC + [
              'SIMD-ALLOT CONSTANT _d',    # extra tile for high part
              'U8-MODE',
              '_a 10 TILE-FILL-U8',
              '_b 20 TILE-FILL-U8',
              # dst = _c, high part at _c+64.  Make sure _d = _c+64 by
              # using _c directly (TWMUL writes dst and dst+64)
              '_a _b _c TILE-WMUL',
              # Result is interleaved: lane i → u16 at dst[2*i..2*i+1]
              # Actually for widening: dst holds low halves, dst+64 holds high halves
              # In u8 wmul: lane 0 result at (_c word 0) = 200, check lane 0 low byte
              '_c W@ .',
          ],
          '200 ')

def test_u16_wmul():
    print("\n=== U16 TILE-WMUL (widening) ===")
    # In u16 mode, wmul: 300 * 200 = 60000 → fits in u32
    check("u16 wmul 300*200=60000",
          ALLOC_ABC + [
              'U16-MODE',
              '_a 300 TILE-FILL-U16',
              '_b 200 TILE-FILL-U16',
              '_a _b _c TILE-WMUL',
              # Widening: u32 result. Lane 0 low 32 bits at _c as L@
              '_c L@ .',
          ],
          '60000 ')

# ====================================================================
#  FMA test
# ====================================================================

def test_fp16_fma():
    print("\n=== FP16 TILE-FMA ===")
    # FMA: dst[i] = src0[i]*src1[i] + dst[i]
    # a=1.0, b=2.0, c=3.0 → c = 1.0*2.0 + 3.0 = 5.0
    # FP16: 1.0=0x3C00, 2.0=0x4000, 3.0=0x4200, 5.0=0x4500
    check("fp16 fma 1*2+3=5.0",
          ALLOC_ABC + [
              'FP16-MODE',
              f'_a {FP16_ONE} TILE-FILL-U16',
              f'_b {FP16_TWO} TILE-FILL-U16',
              f'_c {FP16_THREE} TILE-FILL-U16',
              '_a _b _c TILE-FMA',
              '_c W@ .',
          ],
          '17664 ')  # 0x4500 = FP16 5.0 = 17664

# ====================================================================
#  DOT product test (integer)
# ====================================================================

def test_u8_dot():
    print("\n=== U8 TILE-DOT ===")
    # 64 × (3 * 2) = 64 × 6 = 384
    check("u8 dot 64×(3*2) = 384",
          ALLOC_ABC + [
              'U8-MODE',
              '_a 3 TILE-FILL-U8',
              '_b 2 TILE-FILL-U8',
              '_a _b TILE-DOT .',
          ],
          '384 ')

# ====================================================================
#  TILE-TRANS test
# ====================================================================

def test_tile_trans():
    print("\n=== TILE-TRANS (8×8 transpose) ===")
    # Fill a with a pattern: row 0 all=0, row 1 all=1, row 2 all=2, etc.
    # Use explicit writes (DO..LOOP is compile-only, can't use at prompt)
    # After transpose: col j should be all-j → row 0 = [0,1,2,...,7]
    fill_lines = []
    for row in range(8):
        for col in range(8):
            offset = row * 8 + col
            fill_lines.append(f'{row} _a {offset} + C!')
    check("transpose 8×8",
          ALLOC_ABC + [
              'U8-MODE',
          ] + fill_lines + [
              '_a _b TILE-TRANS',
              # After: row 0 = old column 0 = [0,1,2,3,4,5,6,7]
              '_b C@ .  _b 1 + C@ .  _b 2 + C@ .  _b 7 + C@ .',
          ],
          '0 1 2 7')

# ====================================================================
#  FP16 regression: verify existing SIMD- API still works
# ====================================================================

def test_fp16_regression():
    print("\n=== FP16 SIMD Regression ===")
    # SIMD-ADD with FP16 1.0 + 2.0 = 3.0
    check("fp16 simd-add 1.0+2.0=3.0",
          ALLOC_ABC + [
              f'_a {FP16_ONE} SIMD-FILL',
              f'_b {FP16_TWO} SIMD-FILL',
              '_a _b _c SIMD-ADD',
              '_c W@ .',   # lane 0 should be FP16 3.0 = 0x4200
          ],
          f'{FP16_THREE} ')

    # SIMD-ZERO + SIMD-COPY
    check("fp16 simd-zero+copy",
          ALLOC_ABC + [
              f'_a {FP16_ONE} SIMD-FILL',
              '_b SIMD-ZERO',
              '_a _b SIMD-COPY',
              '_b W@ .',
          ],
          f'{FP16_ONE} ')

    # SIMD-SUM: 32 × 1.0 = 32.0 (FP32 bit pattern)
    # FP32 32.0 = 0x42000000
    check("fp16 simd-sum 32×1.0",
          ALLOC_ABC + [
              f'_a {FP16_ONE} SIMD-FILL',
              '_a SIMD-SUM .',
          ],
          '1107296256 ')  # 0x42000000 = 1107296256

# ====================================================================
#  Fill helpers
# ====================================================================

def test_fill_helpers():
    print("\n=== Fill Helpers ===")

    check("tile-fill-u8 fills all 64 bytes",
          ALLOC_ABC + [
              '_a 42 TILE-FILL-U8',
              '_a C@ .  _a 31 + C@ .  _a 63 + C@ .',
          ],
          '42 42 42')

    check("tile-fill-u16 fills all 32 words",
          ALLOC_ABC + [
              '_a 12345 TILE-FILL-U16',
              '_a W@ .  _a 30 + W@ .  _a 62 + W@ .',  # lane 0, 15, 31
          ],
          '12345 12345 12345')

    check("tile-fill-u32 fills all 16 dwords",
          ALLOC_ABC + [
              '_a 1000000 TILE-FILL-U32',
              '_a L@ .  _a 28 + L@ .  _a 60 + L@ .',  # lane 0, 7, 15
          ],
          '1000000 1000000 1000000')

    check("tile-fill-u64 fills all 8 qwords",
          ALLOC_ABC + [
              '_a 9876543210 TILE-FILL-U64',
              '_a @ .  _a 56 + @ .',  # lane 0, 7
          ],
          '9876543210 9876543210')

# ====================================================================
#  Main
# ====================================================================

if __name__ == '__main__':
    build_snapshot()

    test_mode_words()
    test_u8_add()
    test_u8_sub()
    test_u8_mul()
    test_u8_bitwise()
    test_u8_minmax()
    test_u8_reductions()
    test_u8_saturating()
    test_u8_zero()
    test_u8_copy()

    test_u16_add()
    test_u16_sub()
    test_u16_mul()
    test_u16_reductions()
    test_u16_minmax()
    test_u16_saturating()

    test_u32_add()
    test_u32_mul()
    test_u32_reductions()

    test_u8_wmul()
    test_u16_wmul()

    test_fp16_fma()
    test_u8_dot()
    test_tile_trans()

    test_fill_helpers()
    test_fp16_regression()

    print(f"\n{'='*50}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*50}")
    sys.exit(1 if _fail_count else 0)
