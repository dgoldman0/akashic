#!/usr/bin/env python3
"""Test suite for Tier-2 math module concurrency guards.

Validates that the guard wrappers on FFT and SORT modules:
  1. Preserve functional correctness.
  2. Release the guard after each call.
  3. Allow sequential calls (guard not stuck).

Uses FFT-FORWARD and SORT-FP16 as representative guarded operations.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
MATH_DIR   = os.path.join(ROOT_DIR, "akashic", "math")

FP16_F     = os.path.join(MATH_DIR, "fp16.f")
FP16EXT_F  = os.path.join(MATH_DIR, "fp16-ext.f")
FP32_F     = os.path.join(MATH_DIR, "fp32.f")
ACCUM_F    = os.path.join(MATH_DIR, "accum.f")
TRIG_F     = os.path.join(MATH_DIR, "trig.f")
SIMD_F     = os.path.join(MATH_DIR, "simd.f")
SIMDX_F    = os.path.join(MATH_DIR, "simd-ext.f")
FFT_F      = os.path.join(MATH_DIR, "fft.f")
SORT_F     = os.path.join(MATH_DIR, "sort.f")
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
    print("[*] Building snapshot: BIOS + KDOS + math deps + fft + sort ...")
    t0 = time.time()
    bios_code    = _load_bios()
    kdos_lines   = _load_forth_lines(KDOS_PATH)
    event_lines  = _load_forth_lines(EVENT_F)
    sem_lines    = _load_forth_lines(SEM_F)
    guard_lines  = _load_forth_lines(GUARD_F)
    fp16_lines   = _load_forth_lines(FP16_F)
    fp16e_lines  = _load_forth_lines(FP16EXT_F)
    fp32_lines   = _load_forth_lines(FP32_F)
    accum_lines  = _load_forth_lines(ACCUM_F)
    trig_lines   = _load_forth_lines(TRIG_F)
    simd_lines   = _load_forth_lines(SIMD_F)
    simdx_lines  = _load_forth_lines(SIMDX_F)
    fft_lines    = _load_forth_lines(FFT_F)
    sort_lines   = _load_forth_lines(SORT_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + event_lines + sem_lines + guard_lines
                 + fp16_lines + fp16e_lines + fp32_lines + accum_lines
                 + trig_lines + simd_lines + simdx_lines
                 + fft_lines + sort_lines)
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
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            print(f"  [!] {l}")
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=80_000_000):
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

# ── FFT setup helpers ──

# 4-element input: [1.0, 0.0, 0.0, 0.0]  (impulse)
# FFT of impulse → all bins = 1.0 (real), 0.0 (imag)
FFT_SETUP = [
    '8 HBW-ALLOT CONSTANT _FR',   # 4 reals
    '8 HBW-ALLOT CONSTANT _FI',   # 4 imags
    # Set real[0]=1.0, rest=0
    '0x3C00 _FR W!',              # 1.0
    '0 _FR 2 + W!',
    '0 _FR 4 + W!',
    '0 _FR 6 + W!',
    # Imag = all zeros
    '0 _FI W!  0 _FI 2 + W!  0 _FI 4 + W!  0 _FI 6 + W!',
]

# Sort setup: 4-element array [3.0, 1.0, 4.0, 2.0]
SORT_SETUP = [
    '8 HBW-ALLOT CONSTANT _SA',
    '0x4200 _SA W!',              # 3.0
    '0x3C00 _SA 2 + W!',          # 1.0
    '0x4400 _SA 4 + W!',          # 4.0
    '0x4000 _SA 6 + W!',          # 2.0
]

# ============================================================
# Tests
# ============================================================

def main():
    build_snapshot()
    print()

    # ── 1. FFT correctness through guard ──
    print("=== FFT correctness (guard transparent) ===")
    # FFT of impulse: all real bins should be 1.0 (0x3C00)
    check("FFT-FORWARD impulse → all-ones real",
          FFT_SETUP + [
           '_FR _FI 4 FFT-FORWARD',
           '." R0=" _FR W@ .  ." R1=" _FR 2 + W@ .  '
           '." R2=" _FR 4 + W@ .  ." R3=" _FR 6 + W@ .'],
          'R0=15360 R1=15360 R2=15360 R3=15360 ')

    # ── 2. FFT guard released after call ──
    print("\n=== FFT guard released after call ===")
    check("guard free after FFT-FORWARD",
          FFT_SETUP + [
           '_FR _FI 4 FFT-FORWARD',
           '_fft-guard GUARD-HELD?',
           'IF ." HELD" ELSE ." FREE" THEN'],
          "FREE")

    # ── 3. Two sequential FFTs succeed ──
    print("\n=== Sequential FFT calls ===")
    check("second FFT-FORWARD after first",
          FFT_SETUP + [
           '_FR _FI 4 FFT-FORWARD',
           # Reset to impulse
           '0x3C00 _FR W!  0 _FR 2 + W!  0 _FR 4 + W!  0 _FR 6 + W!',
           '0 _FI W!  0 _FI 2 + W!  0 _FI 4 + W!  0 _FI 6 + W!',
           '_FR _FI 4 FFT-FORWARD',
           '." R0=" _FR W@ .'],
          'R0=15360 ')

    # ── 4. FFT-INVERSE after FFT-FORWARD ──
    print("\n=== FFT round-trip ===")
    check("FFT-FORWARD then FFT-INVERSE recovers input",
          FFT_SETUP + [
           '_FR _FI 4 FFT-FORWARD',
           '_FR _FI 4 FFT-INVERSE',
           '." R0=" _FR W@ .'],
          'R0=15360 ')

    # ── 5. SORT correctness through guard ──
    print("\n=== SORT correctness (guard transparent) ===")
    # [3.0. 1.0, 4.0, 2.0] → [1.0, 2.0, 3.0, 4.0]
    check("SORT-FP16 ascending",
          SORT_SETUP + [
           '_SA 4 SORT-FP16',
           '." S0=" _SA W@ .  ." S1=" _SA 2 + W@ .  '
           '." S2=" _SA 4 + W@ .  ." S3=" _SA 6 + W@ .'],
          'S0=15360 S1=16384 S2=16896 S3=17408 ')

    # ── 6. SORT guard released ──
    print("\n=== SORT guard released after call ===")
    check("guard free after SORT-FP16",
          SORT_SETUP + [
           '_SA 4 SORT-FP16',
           '_sort-guard GUARD-HELD?',
           'IF ." HELD" ELSE ." FREE" THEN'],
          "FREE")

    # ── 7. Two sequential sorts ──
    print("\n=== Sequential SORT calls ===")
    check("second SORT after first",
          SORT_SETUP + [
           '_SA 4 SORT-FP16',
           # Reshuffle
           '0x4200 _SA W!  0x3C00 _SA 2 + W!  0x4400 _SA 4 + W!  0x4000 _SA 6 + W!',
           '_SA 4 SORT-FP16',
           '." S0=" _SA W@ .'],
          'S0=15360 ')

    # ── Summary ──
    print()
    print("=" * 60)
    print(f"Math guard tests: {_pass_count}/{_pass_count + _fail_count} passed, "
          f"{_fail_count} failed")
    if _fail_count == 0:
        print("All math guard tests passed!")
    else:
        print("SOME TESTS FAILED")
        sys.exit(1)

if __name__ == "__main__":
    main()
