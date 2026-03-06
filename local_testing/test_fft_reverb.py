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
"""Test suite for Akashic audio/fft-reverb.f — FFT partitioned convolution reverb.

Uses snapshot-based testing: boots BIOS + KDOS + all deps once,
then replays from snapshot for each test.
"""
import os, sys, time, struct, math

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
MATH_DIR   = os.path.join(ROOT_DIR, "akashic", "math")
AUDIO_DIR  = os.path.join(ROOT_DIR, "akashic", "audio")

FP16_F     = os.path.join(MATH_DIR, "fp16.f")
FP16EXT_F  = os.path.join(MATH_DIR, "fp16-ext.f")
FP32_F     = os.path.join(MATH_DIR, "fp32.f")
ACCUM_F    = os.path.join(MATH_DIR, "accum.f")
TRIG_F     = os.path.join(MATH_DIR, "trig.f")
SIMD_F     = os.path.join(MATH_DIR, "simd.f")
SIMDX_F    = os.path.join(MATH_DIR, "simd-ext.f")
FFT_F      = os.path.join(MATH_DIR, "fft.f")
PCM_F      = os.path.join(AUDIO_DIR, "pcm.f")
FFTREV_F   = os.path.join(AUDIO_DIR, "fft-reverb.f")

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

# ── Emulator core ──

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
    print("[*] Building snapshot: BIOS + KDOS + fp16 + fp16-ext + fp32 + accum"
          " + trig + simd + simd-ext + fft + pcm + fft-reverb ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    fp16_lines  = _load_forth_lines(FP16_F)
    fp16e_lines = _load_forth_lines(FP16EXT_F)
    fp32_lines  = _load_forth_lines(FP32_F)
    accum_lines = _load_forth_lines(ACCUM_F)
    trig_lines  = _load_forth_lines(TRIG_F)
    simd_lines  = _load_forth_lines(SIMD_F)
    simdx_lines = _load_forth_lines(SIMDX_F)
    fft_lines   = _load_forth_lines(FFT_F)
    pcm_lines   = _load_forth_lines(PCM_F)
    fftrev_lines = _load_forth_lines(FFTREV_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + fp16_lines + fp16e_lines + fp32_lines + accum_lines
                 + trig_lines + simd_lines + simdx_lines
                 + fft_lines + pcm_lines + fftrev_lines)
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

def run_forth(lines, max_steps=200_000_000):
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

def fp16_to_sortable(bits):
    if bits & 0x8000:
        return -(bits ^ 0x8000)
    return bits

def check_fp16_arr(name, forth_lines, expected_floats, max_ulp=2):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
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
            print(f"        got raw: {vals[:20]}...")
        for line in output.strip().split('\n')[-5:]:
            if line.strip():
                print(f"        uart: {line.strip()}")
        return
    ok = True
    details = []
    for i, exp_f in enumerate(expected_floats):
        exp_bits = fp16(exp_f)
        got_bits = vals[i] & 0xFFFF
        sdiff = abs(fp16_to_sortable(got_bits) - fp16_to_sortable(exp_bits))
        details.append(sdiff)
        if sdiff > max_ulp:
            ok = False
    if ok:
        _pass_count += 1
        print(f"  PASS  {name}  (max ULP={max(details) if details else 0})")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  (ULP diffs={details})")
        for i, exp_f in enumerate(expected_floats):
            exp_b = fp16(exp_f)
            got_b = vals[i] & 0xFFFF if i < len(vals) else -1
            d = details[i] if i < len(details) else -1
            if d > max_ulp:
                print(f"        [{i}] expected=0x{exp_b:04X} ({fp16_to_float(exp_b):.4f}) "
                      f"got=0x{got_b:04X} ({fp16_to_float(got_b):.4f})  ULP={d}")

def check_int(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    for line in output.strip().split('\n'):
        if 'not found' in line.lower():
            _fail_count += 1
            print(f"  FAIL  {name}  (runtime error: {line.strip()})")
            return
    vals = parse_ints(output)
    if not vals:
        _fail_count += 1
        print(f"  FAIL  {name}  (no output parsed)")
        for line in output.strip().split('\n')[-5:]:
            print(f"        uart: {line.strip()}")
        return
    got = vals[0]
    if got == expected:
        _pass_count += 1
        print(f"  PASS  {name}  (got={got})")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  (expected={expected}, got={got})")

# ── Helpers to build Forth code for tests ──

def read_arr(name, n):
    lines = ['.\" |RESULT| "']
    for i in range(n):
        lines.append(f"{name} {i * 2} + W@ .")
    return lines

def pcm_read_frames(name, n):
    """Read n frames from a PCM buffer by index."""
    lines = ['.\" |RESULT| "']
    for i in range(n):
        lines.append(f"{i} {name} PCM-FRAME@ .")
    return lines

# ── Tests ──

def test_fftrev_create_free():
    """Basic create and free without crash."""
    print("\n── FFTREV-CREATE / FFTREV-FREE ──")
    n = 4  # tiny IR
    bs = 4  # block size
    forth = [
        # Create an IR buffer: 4 samples of impulse [1, 0, 0, 0]
        f"{n * 2} HBW-ALLOT CONSTANT IR",
        f"0x3C00 IR W!",          # IR[0] = 1.0
        f"0x0000 IR 2 + W!",      # IR[1] = 0.0
        f"0x0000 IR 4 + W!",      # IR[2] = 0.0
        f"0x0000 IR 6 + W!",      # IR[3] = 0.0
        f"IR {n} {bs} FFTREV-CREATE CONSTANT REV",
        '.\" |RESULT| "',
        "REV 0<> .",              # should print non-zero (true)
        "REV FFTREV-FREE",
    ]
    check_int("create+free impulse", forth, -1)

def test_fftrev_impulse_passthrough():
    """Convolving with impulse [1,0,...] should pass through the signal."""
    print("\n── FFTREV impulse passthrough ──")
    bs = 4
    n_fft = bs * 2  # = 8
    forth = [
        # IR = impulse [1, 0, 0, 0]
        f"{bs * 2} HBW-ALLOT CONSTANT IR",
        f"0x3C00 IR W!",
        f"0x0000 IR 2 + W!",
        f"0x0000 IR 4 + W!",
        f"0x0000 IR 6 + W!",
        f"IR {bs} {bs} FFTREV-CREATE CONSTANT REV",
        # Create PCM buffer: 4 frames, 44100 Hz, 16-bit, mono
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF",
    ]
    # Write test signal: [0.5, -0.25, 0.75, -0.5]
    test_signal = [0.5, -0.25, 0.75, -0.5]
    for i, v in enumerate(test_signal):
        forth.append(f"0x{fp16(v):04X} {i} BUF PCM-FRAME!")

    # Process: first call fills history, output may have startup transient
    # We need to "prime" the reverb with one block of zeros first
    forth += [
        # First block: all zeros to prime history
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT ZERO-BUF",
        "ZERO-BUF PCM-CLEAR",
        "ZERO-BUF REV FFTREV-PROCESS",
        "ZERO-BUF PCM-FREE",
        # Second block: our actual signal
        "BUF REV FFTREV-PROCESS",
    ]
    forth += pcm_read_frames("BUF", bs)
    forth += ["BUF PCM-FREE", "REV FFTREV-FREE"]

    # With wet=1.0 and impulse IR, output should equal input
    check_fp16_arr("impulse passthrough B=4", forth, test_signal, max_ulp=20)

def test_fftrev_delay_ir():
    """Convolving with IR [0,1,0,0] should delay the signal by 1 sample."""
    print("\n── FFTREV delay IR ──")
    bs = 4
    forth = [
        # IR = [0, 1, 0, 0] — unit delay
        f"{bs * 2} HBW-ALLOT CONSTANT IR",
        f"0x0000 IR W!",
        f"0x3C00 IR 2 + W!",
        f"0x0000 IR 4 + W!",
        f"0x0000 IR 6 + W!",
        f"IR {bs} {bs} FFTREV-CREATE CONSTANT REV",
        # Prime with zero block
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF0",
        "BUF0 PCM-CLEAR",
        "BUF0 REV FFTREV-PROCESS",
        "BUF0 PCM-FREE",
        # Signal block: [1, 0, 0, 0]
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF1",
    ]
    for i, v in enumerate([1.0, 0.0, 0.0, 0.0]):
        forth.append(f"0x{fp16(v):04X} {i} BUF1 PCM-FRAME!")
    forth += [
        "BUF1 REV FFTREV-PROCESS",
    ]
    # Expected: convolved with [0,1,0,0] should give [0,1,0,0]
    # But overlap-save means first block uses history[0..B-1]=0.
    # history after prime: [0,0,0,0,0,0,0,0]
    # After shift+new: [0,0,0,0 | 1,0,0,0]
    # FFT of that, × FFT([0,1,0,0,0,0,0,0]), IFFT → linear conv
    # conv([0,0,0,0,1,0,0,0], [0,1,0,0,0,0,0,0])
    # = [0,0,0,0,0,1,0,0,0,0,0,0,0,0,0] (15 elements)
    # Take last B=4: indices [4..7] = [0,1,0,0]
    # With wet=1.0: output = conv result (no dry mix because LERP(dry, wet, 1.0) = wet)
    forth += pcm_read_frames("BUF1", bs)
    forth += ["BUF1 PCM-FREE", "REV FFTREV-FREE"]
    check_fp16_arr("delay IR [0,1,0,0]", forth, [0.0, 1.0, 0.0, 0.0], max_ulp=20)

def test_fftrev_wet_dry():
    """Wet=0.5 should give 50% mix of dry and reverb."""
    print("\n── FFTREV wet/dry mix ──")
    bs = 4
    forth = [
        # IR = impulse [1, 0, 0, 0]  → reverb = input
        f"{bs * 2} HBW-ALLOT CONSTANT IR",
        f"0x3C00 IR W!",
        f"0x0000 IR 2 + W!",
        f"0x0000 IR 4 + W!",
        f"0x0000 IR 6 + W!",
        f"IR {bs} {bs} FFTREV-CREATE CONSTANT REV",
        # Set wet to 0.5
        f"0x3800 REV FFTREV-WET!",  # 0x3800 = 0.5 in FP16
        # Prime
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF0",
        "BUF0 PCM-CLEAR",
        "BUF0 REV FFTREV-PROCESS",
        "BUF0 PCM-FREE",
        # Signal
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF1",
    ]
    signal = [1.0, 0.0, 0.0, 0.0]
    for i, v in enumerate(signal):
        forth.append(f"0x{fp16(v):04X} {i} BUF1 PCM-FRAME!")
    forth += [
        "BUF1 REV FFTREV-PROCESS",
    ]
    forth += pcm_read_frames("BUF1", bs)
    forth += ["BUF1 PCM-FREE", "REV FFTREV-FREE"]
    # wet=0.5, impulse IR → reverb=dry → LERP(dry, dry, 0.5) = dry
    # Actually LERP(dry, wet_sample, wet_amount):
    # LERP(1.0, 1.0, 0.5) = 1.0  → output same as input
    check_fp16_arr("wet=0.5 impulse", forth, signal, max_ulp=20)

def test_fftrev_multi_partition():
    """IR longer than block size → multiple partitions."""
    print("\n── FFTREV multi-partition IR ──")
    bs = 4
    # IR = 8 samples → 2 partitions of 4
    # IR = [0.5, 0, 0, 0, 0.5, 0, 0, 0]
    # This is like: output = 0.5*input + 0.5*(input delayed by 4)
    ir_len = 8
    ir_vals = [0.5, 0.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.0]
    forth = [
        f"{ir_len * 2} HBW-ALLOT CONSTANT IR",
    ]
    for i, v in enumerate(ir_vals):
        forth.append(f"0x{fp16(v):04X} IR {i*2} + W!")
    forth += [
        f"IR {ir_len} {bs} FFTREV-CREATE CONSTANT REV",
        # Prime: send 2 zero blocks to fill pipeline
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT Z0",
        "Z0 PCM-CLEAR",
        "Z0 REV FFTREV-PROCESS",
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT Z1",
        "Z1 PCM-CLEAR",
        "Z1 REV FFTREV-PROCESS",
        "Z0 PCM-FREE", "Z1 PCM-FREE",
        # Signal block: [1, 0, 0, 0]
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF",
    ]
    signal = [1.0, 0.0, 0.0, 0.0]
    for i, v in enumerate(signal):
        forth.append(f"0x{fp16(v):04X} {i} BUF PCM-FRAME!")
    forth += [
        "BUF REV FFTREV-PROCESS",
    ]
    forth += pcm_read_frames("BUF", bs)
    forth += ["BUF PCM-FREE", "REV FFTREV-FREE"]
    # With partitioned convolution, the multi-partition IR processes
    # correctly. After priming with zeros, the signal [1,0,0,0] convolved
    # with [0.5,0,0,0,0.5,0,0,0] should give [0.5,0,0,0] for this block
    # (the delayed component from partition 2 will appear in the next block).
    check_fp16_arr("multi-partition 2×4", forth, [0.5, 0.0, 0.0, 0.0], max_ulp=20)

def test_fftrev_scaling():
    """IR that scales: [0.5, 0, 0, 0] should halve the signal."""
    print("\n── FFTREV scaling IR ──")
    bs = 4
    forth = [
        f"{bs * 2} HBW-ALLOT CONSTANT IR",
        f"0x{fp16(0.5):04X} IR W!",
        f"0x0000 IR 2 + W!",
        f"0x0000 IR 4 + W!",
        f"0x0000 IR 6 + W!",
        f"IR {bs} {bs} FFTREV-CREATE CONSTANT REV",
        # Prime
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT Z0",
        "Z0 PCM-CLEAR",
        "Z0 REV FFTREV-PROCESS",
        "Z0 PCM-FREE",
        # Signal
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF",
    ]
    signal = [1.0, -1.0, 0.5, -0.5]
    for i, v in enumerate(signal):
        forth.append(f"0x{fp16(v):04X} {i} BUF PCM-FRAME!")
    forth += [
        "BUF REV FFTREV-PROCESS",
    ]
    forth += pcm_read_frames("BUF", bs)
    forth += ["BUF PCM-FREE", "REV FFTREV-FREE"]
    expected = [v * 0.5 for v in signal]
    check_fp16_arr("scale IR [0.5,0,0,0]", forth, expected, max_ulp=20)

def test_fftrev_larger_block():
    """Test with block size 8 for slightly larger FFT."""
    print("\n── FFTREV B=8 impulse ──")
    bs = 8
    forth = [
        f"{bs * 2} HBW-ALLOT CONSTANT IR",
        f"0x3C00 IR W!",  # IR[0] = 1.0
    ]
    for i in range(1, bs):
        forth.append(f"0x0000 IR {i*2} + W!")
    forth += [
        f"IR {bs} {bs} FFTREV-CREATE CONSTANT REV",
        # Prime
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT Z0",
        "Z0 PCM-CLEAR",
        "Z0 REV FFTREV-PROCESS",
        "Z0 PCM-FREE",
        # Signal
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT BUF",
    ]
    signal = [0.25 * (i+1) for i in range(bs)]  # [0.25, 0.5, 0.75, 1.0, ...]
    # Clamp to FP16 range
    signal = [min(v, 1.0) for v in signal]
    for i, v in enumerate(signal):
        forth.append(f"0x{fp16(v):04X} {i} BUF PCM-FRAME!")
    forth += [
        "BUF REV FFTREV-PROCESS",
    ]
    forth += pcm_read_frames("BUF", bs)
    forth += ["BUF PCM-FREE", "REV FFTREV-FREE"]
    check_fp16_arr("impulse passthrough B=8", forth, signal, max_ulp=20)

def test_fftrev_create_nparts():
    """Verify number of partitions = ceil(ir_len / block_size)."""
    print("\n── FFTREV partition count ──")
    # IR=10 samples, block_size=4 → ceil(10/4) = 3 partitions
    bs = 4
    ir_len = 10
    forth = [
        f"{ir_len * 2} HBW-ALLOT CONSTANT IR",
    ]
    for i in range(ir_len):
        forth.append(f"0x0000 IR {i*2} + W!")
    forth.append(f"0x3C00 IR W!")  # just need some IR content
    forth += [
        f"IR {ir_len} {bs} FFTREV-CREATE CONSTANT REV",
        '.\" |RESULT| "',
        # Read NP field at offset +16
        "REV 16 + @ .",
        "REV FFTREV-FREE",
    ]
    check_int("ceil(10/4)=3 partitions", forth, 3)

def test_fftrev_consecutive_blocks():
    """Process two consecutive signal blocks, verify continuity."""
    print("\n── FFTREV consecutive blocks ──")
    bs = 4
    forth = [
        # IR = impulse
        f"{bs * 2} HBW-ALLOT CONSTANT IR",
        f"0x3C00 IR W!",
        f"0x0000 IR 2 + W!",
        f"0x0000 IR 4 + W!",
        f"0x0000 IR 6 + W!",
        f"IR {bs} {bs} FFTREV-CREATE CONSTANT REV",
        # Prime
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT Z0",
        "Z0 PCM-CLEAR",
        "Z0 REV FFTREV-PROCESS",
        "Z0 PCM-FREE",
        # Block 1: [1, 0, 0, 0]
        f"{bs} 44100 16 1 PCM-ALLOC CONSTANT B1",
    ]
    sig1 = [1.0, 0.0, 0.0, 0.0]
    for i, v in enumerate(sig1):
        forth.append(f"0x{fp16(v):04X} {i} B1 PCM-FRAME!")
    forth += ["B1 REV FFTREV-PROCESS"]
    # Block 2: [0, 0, 0, 1]
    forth += [f"{bs} 44100 16 1 PCM-ALLOC CONSTANT B2"]
    sig2 = [0.0, 0.0, 0.0, 1.0]
    for i, v in enumerate(sig2):
        forth.append(f"0x{fp16(v):04X} {i} B2 PCM-FRAME!")
    forth += ["B2 REV FFTREV-PROCESS"]
    # Read both blocks' results
    forth += pcm_read_frames("B1", bs)
    for i in range(bs):
        forth.append(f"{i} B2 PCM-FRAME@ .")
    forth += ["B1 PCM-FREE", "B2 PCM-FREE", "REV FFTREV-FREE"]
    # First block: impulse conv → should be [1,0,0,0]
    # Second block: impulse conv → should be [0,0,0,1]
    expected = sig1 + sig2
    check_fp16_arr("consecutive blocks", forth, expected, max_ulp=2000)

# ── Main ──

def main():
    build_snapshot()

    test_fftrev_create_free()
    test_fftrev_create_nparts()
    test_fftrev_impulse_passthrough()
    test_fftrev_delay_ir()
    test_fftrev_wet_dry()
    test_fftrev_scaling()
    test_fftrev_larger_block()
    test_fftrev_multi_partition()
    test_fftrev_consecutive_blocks()

    print(f"\n{'='*60}")
    print(f"  Total: {_pass_count + _fail_count}  |  PASS: {_pass_count}  |  FAIL: {_fail_count}")
    print(f"{'='*60}")
    return _fail_count == 0

if __name__ == "__main__":
    ok = main()
    sys.exit(0 if ok else 1)
