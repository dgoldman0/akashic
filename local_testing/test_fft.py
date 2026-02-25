#!/usr/bin/env python3
"""Test suite for Akashic math/fft.f — Fast Fourier Transform.

Uses snapshot-based testing: boots BIOS + KDOS + all deps once,
then replays from snapshot for each test.
"""
import os, sys, time, struct, math

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
MATH_DIR   = os.path.join(ROOT_DIR, "akashic", "math")

FP16_F     = os.path.join(MATH_DIR, "fp16.f")
FP16EXT_F  = os.path.join(MATH_DIR, "fp16-ext.f")
TRIG_F     = os.path.join(MATH_DIR, "trig.f")
FFT_F      = os.path.join(MATH_DIR, "fft.f")

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

# ── Array helpers ──

def arr_setup(name, float_values):
    n = len(float_values)
    lines = [f"{n * 2} HBW-ALLOT CONSTANT {name}"]
    for i, v in enumerate(float_values):
        bits = fp16(v)
        lines.append(f"0x{bits:04X} {name} {i * 2} + W!")
    return lines

def dst_setup(name, n):
    return [f"{n * 2} HBW-ALLOT CONSTANT {name}"]

def read_arr(name, n):
    """Generate Forth to print n FP16 values from array, prefixed with marker."""
    lines = ['.\" |RESULT| "']
    for i in range(n):
        lines.append(f"{name} {i * 2} + W@ .")
    return lines

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
    print("[*] Building snapshot: BIOS + KDOS + fp16 + fp16-ext + trig + fft ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    fp16_lines  = _load_forth_lines(FP16_F)
    fp16e_lines = _load_forth_lines(FP16EXT_F)
    trig_lines  = _load_forth_lines(TRIG_F)
    fft_lines   = _load_forth_lines(FFT_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + fp16_lines + fp16e_lines
                 + trig_lines
                 + fft_lines)
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
    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=80_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
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

# ── Test infrastructure ──

_pass_count = 0
_fail_count = 0

def parse_ints(output):
    """Parse integers from ok-ending lines AFTER the |RESULT| marker.
    
    Echo lines start with '> ' and don't end with 'ok', so they are
    naturally filtered out — no stray command offsets get parsed.
    """
    vals = []
    found_marker = False
    for line in output.strip().split('\n'):
        line = line.strip()
        if '|RESULT|' in line:
            found_marker = True
            continue
        if not found_marker:
            continue
        if not line.endswith('ok'):
            continue
        for tok in line.split():
            if tok == 'ok':
                continue
            try:
                vals.append(int(tok))
            except ValueError:
                pass
    return vals

def check_fp16_arr(name, forth_lines, expected_floats, max_ulp=2):
    """Check multiple FP16 values printed in order."""
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    # Check for errors
    for line in output.strip().split('\n'):
        if 'underflow' in line.lower() or 'not found' in line.lower():
            _fail_count += 1
            print(f"  FAIL  {name}  (runtime error: {line.strip()})")
            return
    vals = parse_ints(output)
    if len(vals) < len(expected_floats):
        _fail_count += 1
        print(f"  FAIL  {name}  (expected {len(expected_floats)} values, got {len(vals)})")
        if vals:
            print(f"        got raw: {vals}")
        # Show some output for debugging
        for line in output.strip().split('\n')[-5:]:
            if line.strip():
                print(f"        uart: {line.strip()}")
        return
    ok = True
    details = []
    for i, exp_f in enumerate(expected_floats):
        exp_bits = fp16(exp_f)
        got_bits = vals[i] & 0xFFFF
        diff = abs(got_bits - exp_bits)
        details.append(diff)
        if diff > max_ulp:
            ok = False
    if ok:
        _pass_count += 1
        print(f"  PASS  {name}  (ULP diffs={details})")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  (ULP diffs={details})")
        for i, exp_f in enumerate(expected_floats):
            exp_b = fp16(exp_f)
            got_b = vals[i] & 0xFFFF if i < len(vals) else -1
            print(f"        [{i}] expected=0x{exp_b:04X} ({fp16_to_float(exp_b):.4f}) "
                  f"got=0x{got_b:04X} ({fp16_to_float(got_b):.4f})")

def check_fp16(name, forth_lines, expected, max_ulp=2):
    check_fp16_arr(name, forth_lines, [expected], max_ulp)

# ── Tests ──

def parse_last_int(output):
    """Parse the last integer from UART output (for simple single-value tests)."""
    for line in reversed(output.strip().split('\n')):
        line = line.strip()
        if not line:
            continue
        toks = line.split()
        # Scan right-to-left for last integer before 'ok'
        for tok in reversed(toks):
            if tok == 'ok':
                continue
            try:
                return int(tok)
            except ValueError:
                continue
    return None

def test_log2():
    """Verify _FFT-LOG2 helper."""
    print("\n── _FFT-LOG2 ──")
    for n, expected in [(2, 1), (4, 2), (8, 3), (16, 4), (32, 5)]:
        output = run_forth([f"{n} _FFT-LOG2 ."])
        val = parse_last_int(output)
        global _pass_count, _fail_count
        if val == expected:
            _pass_count += 1
            print(f"  PASS  log2({n})={expected}")
        else:
            _fail_count += 1
            print(f"  FAIL  log2({n}) expected={expected} got={val}")

def test_bitrev():
    """Verify _FFT-BITREV helper."""
    print("\n── _FFT-BITREV ──")
    # For nbits=3 (n=8): 0→0, 1→4, 2→2, 3→6, 4→1, 5→5, 6→3, 7→7
    cases = [(0,3,0), (1,3,4), (2,3,2), (3,3,6), (4,3,1)]
    for i, nbits, expected in cases:
        output = run_forth([f"{i} {nbits} _FFT-BITREV ."])
        val = parse_last_int(output)
        global _pass_count, _fail_count
        if val == expected:
            _pass_count += 1
            print(f"  PASS  bitrev({i}, {nbits})={expected}")
        else:
            _fail_count += 1
            print(f"  FAIL  bitrev({i}, {nbits}) expected={expected} got={val}")

def test_fft_dc():
    """FFT of DC signal [1,1,1,1] → [4,0,0,0] + i*[0,0,0,0]."""
    print("\n── FFT-FORWARD DC ──")
    n = 4
    setup = arr_setup("RE", [1.0, 1.0, 1.0, 1.0])
    setup += arr_setup("IM", [0.0, 0.0, 0.0, 0.0])
    forth = setup + [f"RE IM {n} FFT-FORWARD"] + read_arr("RE", n) + read_arr("IM", n)
    check_fp16_arr("fft dc re", forth, [4.0, 0.0, 0.0, 0.0], max_ulp=5)

def test_fft_impulse():
    """FFT of impulse [1,0,0,0] → [1,1,1,1] + i*[0,0,0,0]."""
    print("\n── FFT-FORWARD impulse ──")
    n = 4
    setup = arr_setup("RE", [1.0, 0.0, 0.0, 0.0])
    setup += arr_setup("IM", [0.0, 0.0, 0.0, 0.0])
    forth = setup + [f"RE IM {n} FFT-FORWARD"] + read_arr("RE", n) + read_arr("IM", n)
    # FFT of [1,0,0,0] = [1,1,1,1] + i*[0,0,0,0]
    check_fp16_arr("fft impulse re+im",
                   forth,
                   [1.0, 1.0, 1.0, 1.0,   # re
                    0.0, 0.0, 0.0, 0.0],   # im
                   max_ulp=5)

def test_fft_nyquist():
    """FFT of [1,-1,1,-1] → [0,0,4,0] + i*[0,0,0,0]."""
    print("\n── FFT-FORWARD nyquist ──")
    n = 4
    setup = arr_setup("RE", [1.0, -1.0, 1.0, -1.0])
    setup += arr_setup("IM", [0.0, 0.0, 0.0, 0.0])
    forth = setup + [f"RE IM {n} FFT-FORWARD"] + read_arr("RE", n) + read_arr("IM", n)
    check_fp16_arr("fft nyquist re+im",
                   forth,
                   [0.0, 0.0, 4.0, 0.0,   # re
                    0.0, 0.0, 0.0, 0.0],   # im
                   max_ulp=5)

def test_fft_sine():
    """FFT of pure sine [0, 1, 0, -1] → re=[0,0,0,0], im=[0,-2,0,2]."""
    print("\n── FFT-FORWARD sine ──")
    n = 4
    setup = arr_setup("RE", [0.0, 1.0, 0.0, -1.0])
    setup += arr_setup("IM", [0.0, 0.0, 0.0, 0.0])
    forth = setup + [f"RE IM {n} FFT-FORWARD"] + read_arr("RE", n) + read_arr("IM", n)
    check_fp16_arr("fft sine re+im",
                   forth,
                   [0.0, 0.0, 0.0, 0.0,    # re
                    0.0, -2.0, 0.0, 2.0],   # im
                   max_ulp=5)

def test_fft_inverse_dc():
    """FFT then IFFT of DC [1,1,1,1] should round-trip."""
    print("\n── FFT-INVERSE round-trip DC ──")
    n = 4
    setup = arr_setup("RE", [1.0, 1.0, 1.0, 1.0])
    setup += arr_setup("IM", [0.0, 0.0, 0.0, 0.0])
    forth = setup + [
        f"RE IM {n} FFT-FORWARD",
        f"RE IM {n} FFT-INVERSE",
    ] + read_arr("RE", n) + read_arr("IM", n)
    check_fp16_arr("ifft(fft(dc)) re+im",
                   forth,
                   [1.0, 1.0, 1.0, 1.0,
                    0.0, 0.0, 0.0, 0.0],
                   max_ulp=5)

def test_fft_inverse_impulse():
    """FFT then IFFT of impulse [1,0,0,0] should round-trip."""
    print("\n── FFT-INVERSE round-trip impulse ──")
    n = 4
    setup = arr_setup("RE", [1.0, 0.0, 0.0, 0.0])
    setup += arr_setup("IM", [0.0, 0.0, 0.0, 0.0])
    forth = setup + [
        f"RE IM {n} FFT-FORWARD",
        f"RE IM {n} FFT-INVERSE",
    ] + read_arr("RE", n) + read_arr("IM", n)
    check_fp16_arr("ifft(fft(impulse)) re+im",
                   forth,
                   [1.0, 0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0, 0.0],
                   max_ulp=5)

def test_fft_inverse_sine():
    """FFT then IFFT of sine [0,1,0,-1] should round-trip."""
    print("\n── FFT-INVERSE round-trip sine ──")
    n = 4
    setup = arr_setup("RE", [0.0, 1.0, 0.0, -1.0])
    setup += arr_setup("IM", [0.0, 0.0, 0.0, 0.0])
    forth = setup + [
        f"RE IM {n} FFT-FORWARD",
        f"RE IM {n} FFT-INVERSE",
    ] + read_arr("RE", n) + read_arr("IM", n)
    check_fp16_arr("ifft(fft(sine)) re+im",
                   forth,
                   [0.0, 1.0, 0.0, -1.0,
                    0.0, 0.0, 0.0, 0.0],
                   max_ulp=5)

def test_fft_magnitude():
    """FFT-MAGNITUDE of [3+4i] → [5]."""
    print("\n── FFT-MAGNITUDE ──")
    n = 4
    # re=[3,0,0,0], im=[4,0,0,0] → mag=[5,0,0,0]
    setup = arr_setup("RE", [3.0, 0.0, 0.0, 0.0])
    setup += arr_setup("IM", [4.0, 0.0, 0.0, 0.0])
    setup += dst_setup("MAG", n)
    forth = setup + [f"RE IM MAG {n} FFT-MAGNITUDE"] + read_arr("MAG", n)
    check_fp16_arr("magnitude [3+4i,0,0,0]",
                   forth,
                   [5.0, 0.0, 0.0, 0.0],
                   max_ulp=5)

def test_fft_power():
    """FFT-POWER of [3+4i] → [25]."""
    print("\n── FFT-POWER ──")
    n = 4
    setup = arr_setup("RE", [3.0, 0.0, 0.0, 0.0])
    setup += arr_setup("IM", [4.0, 0.0, 0.0, 0.0])
    setup += dst_setup("PWR", n)
    forth = setup + [f"RE IM PWR {n} FFT-POWER"] + read_arr("PWR", n)
    # 3²+4²=25, 0²+0²=0
    check_fp16_arr("power [3+4i,0,0,0]",
                   forth,
                   [25.0, 0.0, 0.0, 0.0],
                   max_ulp=2)

def test_fft_convolve_impulse():
    """Convolving with impulse [1,0,0,0] returns original signal."""
    print("\n── FFT-CONVOLVE impulse ──")
    n = 4
    setup = arr_setup("AA", [2.0, 3.0, 0.0, 0.0])
    setup += arr_setup("BB", [1.0, 0.0, 0.0, 0.0])
    setup += dst_setup("DST", n)
    forth = setup + [f"AA BB DST {n} FFT-CONVOLVE"] + read_arr("DST", n)
    check_fp16_arr("convolve(x, impulse)=x",
                   forth,
                   [2.0, 3.0, 0.0, 0.0],
                   max_ulp=10)

def test_fft_convolve_shift():
    """Convolving [1,0,0,0] with [0,1,0,0] shifts: [0,1,0,0]."""
    print("\n── FFT-CONVOLVE shift ──")
    n = 4
    setup = arr_setup("AA", [1.0, 0.0, 0.0, 0.0])
    setup += arr_setup("BB", [0.0, 1.0, 0.0, 0.0])
    setup += dst_setup("DST", n)
    forth = setup + [f"AA BB DST {n} FFT-CONVOLVE"] + read_arr("DST", n)
    check_fp16_arr("convolve(impulse, shift)=[0,1,0,0]",
                   forth,
                   [0.0, 1.0, 0.0, 0.0],
                   max_ulp=10)

def test_fft_correlate_auto():
    """Autocorrelation of [1,0,0,0] = [1,0,0,0]."""
    print("\n── FFT-CORRELATE auto ──")
    n = 4
    setup = arr_setup("AA", [1.0, 0.0, 0.0, 0.0])
    setup += arr_setup("BB", [1.0, 0.0, 0.0, 0.0])
    setup += dst_setup("DST", n)
    forth = setup + [f"AA BB DST {n} FFT-CORRELATE"] + read_arr("DST", n)
    check_fp16_arr("correlate(impulse, impulse)=[1,0,0,0]",
                   forth,
                   [1.0, 0.0, 0.0, 0.0],
                   max_ulp=10)

def test_fft_n8_dc():
    """FFT of 8-point DC [1,1,1,1,1,1,1,1] → [8,0,0,0,0,0,0,0]."""
    print("\n── FFT-FORWARD N=8 DC ──")
    n = 8
    setup = arr_setup("RE", [1.0]*8)
    setup += arr_setup("IM", [0.0]*8)
    forth = setup + [f"RE IM {n} FFT-FORWARD"] + read_arr("RE", n)
    check_fp16_arr("fft n=8 dc re",
                   forth,
                   [8.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
                   max_ulp=5)

def test_fft_n8_roundtrip():
    """FFT→IFFT round-trip of [1,2,3,4,5,6,7,8]."""
    print("\n── FFT-INVERSE N=8 round-trip ──")
    n = 8
    vals = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
    setup = arr_setup("RE", vals)
    setup += arr_setup("IM", [0.0]*8)
    forth = setup + [
        f"RE IM {n} FFT-FORWARD",
        f"RE IM {n} FFT-INVERSE",
    ] + read_arr("RE", n) + read_arr("IM", n)
    check_fp16_arr("ifft(fft([1..8])) re+im",
                   forth,
                   vals + [0.0]*8,
                   max_ulp=10)

def test_fft_convolve_box():
    """Convolve [1,1,0,0] with [1,1,0,0] → [1,2,1,0] (circular)."""
    print("\n── FFT-CONVOLVE box ──")
    n = 4
    setup = arr_setup("AA", [1.0, 1.0, 0.0, 0.0])
    setup += arr_setup("BB", [1.0, 1.0, 0.0, 0.0])
    setup += dst_setup("DST", n)
    forth = setup + [f"AA BB DST {n} FFT-CONVOLVE"] + read_arr("DST", n)
    check_fp16_arr("convolve([1,1,0,0],[1,1,0,0])=[1,2,1,0]",
                   forth,
                   [1.0, 2.0, 1.0, 0.0],
                   max_ulp=10)

# ── Main ──

if __name__ == "__main__":
    build_snapshot()
    test_log2()
    test_bitrev()
    test_fft_dc()
    test_fft_impulse()
    test_fft_nyquist()
    test_fft_sine()
    test_fft_inverse_dc()
    test_fft_inverse_impulse()
    test_fft_inverse_sine()
    test_fft_magnitude()
    test_fft_power()
    test_fft_convolve_impulse()
    test_fft_convolve_shift()
    test_fft_correlate_auto()
    test_fft_n8_dc()
    test_fft_n8_roundtrip()
    test_fft_convolve_box()

    print(f"\n{'='*60}")
    print(f"  Total: {_pass_count+_fail_count}  |  PASS: {_pass_count}  |  FAIL: {_fail_count}")
    print(f"{'='*60}")
    sys.exit(0 if _fail_count == 0 else 1)
