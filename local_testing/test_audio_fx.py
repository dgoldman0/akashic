#!/usr/bin/env python3
"""Test suite for Akashic audio Phase 2a — Effects Processing.

Tests: chain.f (effect-chain routing), fx.f (delay + distortion).

Uses snapshot-based testing: boots BIOS + KDOS + all deps once,
then replays from snapshot for each test.
"""
import os, sys, time, struct

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AUDIO_DIR  = os.path.join(ROOT_DIR, "akashic", "audio")
MATH_DIR   = os.path.join(ROOT_DIR, "akashic", "math")

FP16_F     = os.path.join(MATH_DIR,  "fp16.f")
FP16X_F    = os.path.join(MATH_DIR,  "fp16-ext.f")
TRIG_F     = os.path.join(MATH_DIR,  "trig.f")
PCM_F      = os.path.join(AUDIO_DIR, "pcm.f")
OSC_F      = os.path.join(AUDIO_DIR, "osc.f")
NOISE_F    = os.path.join(AUDIO_DIR, "noise.f")
ENV_F      = os.path.join(AUDIO_DIR, "env.f")
LFO_F      = os.path.join(AUDIO_DIR, "lfo.f")
CHAIN_F    = os.path.join(AUDIO_DIR, "chain.f")
FX_F       = os.path.join(AUDIO_DIR, "fx.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── FP16 helpers (Python-side) ──

def float_to_fp16(f):
    """Convert Python float to FP16 bit pattern (uint16)."""
    return struct.unpack('H', struct.pack('e', f))[0]

def fp16_to_float(bits):
    """Convert FP16 bit pattern (uint16) to Python float."""
    return struct.unpack('e', struct.pack('H', bits & 0xFFFF))[0]

FP16_POS_ZERO = 0x0000
FP16_POS_ONE  = 0x3C00
FP16_NEG_ONE  = 0xBC00
FP16_POS_HALF = 0x3800
FP16_TWO      = 0x4000
FP16_THREE    = 0x4200
FP16_FOUR     = 0x4400

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
    print("[*] Building snapshot: BIOS + KDOS + fp16 + trig + pcm + gen + chain + fx ...")
    t0 = time.time()
    bios_code    = _load_bios()
    kdos_lines   = _load_forth_lines(KDOS_PATH)
    fp16_lines   = _load_forth_lines(FP16_F)
    fp16x_lines  = _load_forth_lines(FP16X_F)
    trig_lines   = _load_forth_lines(TRIG_F)
    pcm_lines    = _load_forth_lines(PCM_F)
    osc_lines    = _load_forth_lines(OSC_F)
    noise_lines  = _load_forth_lines(NOISE_F)
    env_lines    = _load_forth_lines(ENV_F)
    lfo_lines    = _load_forth_lines(LFO_F)
    chain_lines  = _load_forth_lines(CHAIN_F)
    fx_lines     = _load_forth_lines(FX_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + fp16_lines + fp16x_lines + trig_lines
                 + pcm_lines + osc_lines + noise_lines
                 + env_lines + lfo_lines
                 + chain_lines + fx_lines)
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
    errors = []
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            errors.append(l)
            print(f"  [!] {l}")
        if 'underflow' in l.lower() or 'abort' in l.lower():
            errors.append(l)
            print(f"  [!] {l}")
    if errors:
        print(f"[!] Snapshot has {len(errors)} error(s) — tests may fail")
        for l in text.strip().split('\n')[-20:]:
            print(f"     | {l}")
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

def parse_last_int(output):
    for line in reversed(output.strip().split('\n')):
        line = line.strip()
        if not line: continue
        toks = line.split()
        for tok in reversed(toks):
            if tok == 'ok': continue
            try:
                return int(tok)
            except ValueError:
                continue
    return None

def parse_ints(output):
    vals = []
    found_marker = False
    for line in output.strip().split('\n'):
        line = line.strip()
        if '|RESULT|' in line:
            found_marker = True
            continue
        if not found_marker: continue
        if not line.endswith('ok'): continue
        for tok in line.split():
            if tok == 'ok': continue
            try:
                vals.append(int(tok))
            except ValueError:
                pass
    return vals

def has_error(output):
    for line in output.strip().split('\n'):
        low = line.lower()
        if any(e in low for e in ['underflow', 'not found', 'abort']):
            return line.strip()
    return None

def check_val(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    err = has_error(output)
    if err:
        _fail_count += 1
        print(f"  FAIL  {name}  (runtime error: {err})")
        return
    val = parse_last_int(output)
    if val == expected:
        _pass_count += 1
        print(f"  PASS  {name}  ({val})")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  expected={expected} got={val}")
        for l in output.strip().split('\n')[-4:]:
            print(f"        uart: '{l.strip()}'")

def check_val_range(name, forth_lines, lo, hi):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    err = has_error(output)
    if err:
        _fail_count += 1
        print(f"  FAIL  {name}  (runtime error: {err})")
        return
    val = parse_last_int(output)
    if val is not None and lo <= val <= hi:
        _pass_count += 1
        print(f"  PASS  {name}  ({val} in [{lo},{hi}])")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  expected [{lo},{hi}] got={val}")
        for l in output.strip().split('\n')[-4:]:
            print(f"        uart: '{l.strip()}'")

def check_vals(name, forth_lines, expected_list):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    err = has_error(output)
    if err:
        _fail_count += 1
        print(f"  FAIL  {name}  (runtime error: {err})")
        return
    vals = parse_ints(output)
    if len(vals) < len(expected_list):
        _fail_count += 1
        print(f"  FAIL  {name}  expected {len(expected_list)} values, got {len(vals)}: {vals}")
        return
    ok = True
    for i, exp in enumerate(expected_list):
        if vals[i] != exp: ok = False
    if ok:
        _pass_count += 1
        print(f"  PASS  {name}  {vals[:len(expected_list)]}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        for i, exp in enumerate(expected_list):
            got = vals[i] if i < len(vals) else '?'
            marker = '!!' if got != exp else '  '
            print(f"    {marker} [{i}] expected={exp} got={got}")

def check_vals_range(name, forth_lines, range_list):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    err = has_error(output)
    if err:
        _fail_count += 1
        print(f"  FAIL  {name}  (runtime error: {err})")
        return
    vals = parse_ints(output)
    if len(vals) < len(range_list):
        _fail_count += 1
        print(f"  FAIL  {name}  expected {len(range_list)} values, got {len(vals)}: {vals}")
        return
    ok = True
    for i, (lo, hi) in enumerate(range_list):
        if not (lo <= vals[i] <= hi): ok = False
    if ok:
        _pass_count += 1
        print(f"  PASS  {name}  {vals[:len(range_list)]}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        for i, (lo, hi) in enumerate(range_list):
            got = vals[i] if i < len(vals) else '?'
            ok_i = lo <= vals[i] <= hi if i < len(vals) else False
            marker = '  ' if ok_i else '!!'
            print(f"    {marker} [{i}] expected [{lo},{hi}] got={got}")

def check_no_error(name, forth_lines):
    """Just verify no runtime error occurs."""
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    err = has_error(output)
    if err:
        _fail_count += 1
        print(f"  FAIL  {name}  (runtime error: {err})")
    else:
        _pass_count += 1
        print(f"  PASS  {name}")

# ════════════════════════════════════════════════════════════════════
#  Chain tests
# ════════════════════════════════════════════════════════════════════

def test_chain_create():
    """CHAIN-CREATE allocates chain, CHAIN-N returns slot count."""
    check_val("chain_create_n4", [
        ": TMP 4 CHAIN-CREATE DUP CHAIN-N SWAP CHAIN-FREE ; TMP ."
    ], 4)

def test_chain_create_clamp():
    """CHAIN-CREATE clamps to max 8 slots."""
    check_val("chain_create_clamp", [
        ": TMP 20 CHAIN-CREATE DUP CHAIN-N SWAP CHAIN-FREE ; TMP ."
    ], 8)

def test_chain_process_empty():
    """CHAIN-PROCESS on empty chain leaves buffer unchanged."""
    check_val("chain_process_empty", [
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC",
        "  DUP 0x3800 0 ROT PCM-FRAME!",   # frame 0 = 0.5
        "  2 CHAIN-CREATE",
        "  2DUP CHAIN-PROCESS",
        "  DROP 0 SWAP PCM-FRAME@ . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_chain_set_and_process():
    """Install FX-DIST (hard clip, drive=3) into chain slot 0, process."""
    # Input 0.5 * 3.0 = 1.5 → clamp → 1.0
    check_val("chain_set_process", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TD",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",  # fill with 0.5
        "  0x4200 1 FX-DIST-CREATE _TD !",        # drive=3.0, hard clip
        "  1 CHAIN-CREATE _TC !",
        "  ['] FX-DIST-PROCESS _TD @ 0 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  0 _TB @ PCM-FRAME@",               # read frame 0
        "  _TD @ FX-DIST-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_ONE)

def test_chain_bypass():
    """Bypassed slot is skipped during CHAIN-PROCESS."""
    # Same as above but bypass slot 0 → output should stay 0.5
    check_val("chain_bypass", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TD",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  0x4200 1 FX-DIST-CREATE _TD !",
        "  1 CHAIN-CREATE _TC !",
        "  ['] FX-DIST-PROCESS _TD @ 0 _TC @ CHAIN-SET!",
        "  1 0 _TC @ CHAIN-BYPASS!",            # bypass slot 0
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_chain_clear():
    """CHAIN-CLEAR removes all effect slots."""
    check_val("chain_clear", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TD",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  0x4200 1 FX-DIST-CREATE _TD !",
        "  1 CHAIN-CREATE _TC !",
        "  ['] FX-DIST-PROCESS _TD @ 0 _TC @ CHAIN-SET!",
        "  _TC @ CHAIN-CLEAR",                  # clear all slots
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_chain_two_effects():
    """Two effects in series: hard clip(drive=2) then soft clip(drive=1)."""
    # Input 0.75 → hard clip drive=2: 0.75*2=1.5 → clamp 1.0
    # Then soft clip drive=1: 1.0*1/(1+1) = 0.5
    check_val("chain_two_fx", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TD1",
        "VARIABLE _TD2",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3A00 I _TB @ PCM-FRAME! LOOP",  # 0.75
        "  0x4000 1 FX-DIST-CREATE _TD1 !",       # hard clip, drive=2
        "  0x3C00 0 FX-DIST-CREATE _TD2 !",       # soft clip, drive=1
        "  2 CHAIN-CREATE _TC !",
        "  ['] FX-DIST-PROCESS _TD1 @ 0 _TC @ CHAIN-SET!",
        "  ['] FX-DIST-PROCESS _TD2 @ 1 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD1 @ FX-DIST-FREE",
        "  _TD2 @ FX-DIST-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

# ════════════════════════════════════════════════════════════════════
#  FX-DELAY tests
# ════════════════════════════════════════════════════════════════════

def test_delay_create():
    """FX-DELAY-CREATE allocates without error."""
    check_no_error("delay_create", [
        ": TMP 10 1000 FX-DELAY-CREATE FX-DELAY-FREE ; TMP"
    ])

def test_delay_silence():
    """Delay of silence produces silence (all zeros)."""
    check_vals("delay_silence", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  10 1000 FX-DELAY-CREATE _TD !",
        "  FP16-POS-ONE _TD @ FX-DELAY-WET!",     # fully wet
        "  FP16-POS-ZERO _TD @ FX-DELAY-FB!",     # no feedback
        "  _TB @ _TD @ FX-DELAY-PROCESS",
        "  .\" |RESULT|\" CR",
        "  0  _TB @ PCM-FRAME@ .",
        "  10 _TB @ PCM-FRAME@ .",
        "  19 _TB @ PCM-FRAME@ .",
        "  _TD @ FX-DELAY-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [0, 0, 0])

def test_delay_basic():
    """10-frame delay shifts signal: first 10 frames silent, next 10 echo."""
    # Fill frames 0-9 with 0.5, frames 10-19 with 0.0.
    # After delay (wet=1.0, fb=0): frames 0-9 should be 0,
    # frames 10-19 should be 0.5 (the delayed input).
    check_vals("delay_basic_shift", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  10 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",   # frames 0-9 = 0.5
        "  10 1000 FX-DELAY-CREATE _TD !",
        "  FP16-POS-ONE _TD @ FX-DELAY-WET!",
        "  FP16-POS-ZERO _TD @ FX-DELAY-FB!",
        "  _TB @ _TD @ FX-DELAY-PROCESS",
        "  .\" |RESULT|\" CR",
        "  0  _TB @ PCM-FRAME@ .",              # should be 0  (silence)
        "  5  _TB @ PCM-FRAME@ .",              # should be 0
        "  9  _TB @ PCM-FRAME@ .",              # should be 0
        "  10 _TB @ PCM-FRAME@ .",              # should be 0x3800 (0.5)
        "  15 _TB @ PCM-FRAME@ .",              # should be 0x3800
        "  19 _TB @ PCM-FRAME@ .",              # should be 0x3800
        "  _TD @ FX-DELAY-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [0, 0, 0, FP16_POS_HALF, FP16_POS_HALF, FP16_POS_HALF])

def test_delay_wet_mix():
    """Delay with wet=0.5: output is mix of dry and delayed."""
    # Fill all 20 frames with 0.5.  After delay (wet=0.5, fb=0):
    #   Frame 0: lerp(0.5, 0.0, 0.5) = 0.25  (delayed=0 initially)
    #   Frame 10: lerp(0.5, delayed, 0.5)
    #     delayed = DL-TAP at frame 10 = sample written at frame 0 = 0.5
    #     output = lerp(0.5, 0.5, 0.5) = 0.5
    check_vals("delay_wet_mix", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  10 1000 FX-DELAY-CREATE _TD !",
        "  FP16-POS-HALF _TD @ FX-DELAY-WET!",
        "  FP16-POS-ZERO _TD @ FX-DELAY-FB!",
        "  _TB @ _TD @ FX-DELAY-PROCESS",
        "  .\" |RESULT|\" CR",
        "  0  _TB @ PCM-FRAME@ .",        # lerp(0.5, 0, 0.5) = 0.25 = 0x3400
        "  10 _TB @ PCM-FRAME@ .",        # lerp(0.5, 0.5, 0.5) = 0.5 = 0x3800
        "  _TD @ FX-DELAY-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [0x3400, FP16_POS_HALF])

def test_delay_feedback():
    """Delay with feedback produces repeated echoes."""
    # 30-frame buffer.  Frames 0-9 = 0.5, rest = 0.
    # Delay = 10 frames, wet=1.0, feedback=0.5.
    # Frame 10: delayed = 0.5 (from frame 0), output = 0.5.
    #   Wrote to DL: 0 + 0.5*0.5 = 0.25
    # Frame 20: delayed = 0.25 (written at frame 10), output = 0.25.
    #   2nd echo is half amplitude.
    check_vals_range("delay_feedback", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  30 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  10 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  10 1000 FX-DELAY-CREATE _TD !",
        "  FP16-POS-ONE _TD @ FX-DELAY-WET!",
        "  FP16-POS-HALF _TD @ FX-DELAY-FB!",
        "  _TB @ _TD @ FX-DELAY-PROCESS",
        "  .\" |RESULT|\" CR",
        "  0  _TB @ PCM-FRAME@ .",     # silence (delay line empty)
        "  10 _TB @ PCM-FRAME@ .",     # first echo ~0.5
        "  20 _TB @ PCM-FRAME@ .",     # second echo ~0.25 (feedback decay)
        "  _TD @ FX-DELAY-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0, 0),                    # frame 0: silence
        (0x3700, 0x3900),          # frame 10: ~0.5 (0x3800 ± tolerance)
        (0x3300, 0x3500),          # frame 20: ~0.25 (0x3400 ± tolerance)
    ])

def test_delay_change_time():
    """FX-DELAY! changes delay time (clamped to capacity)."""
    check_no_error("delay_change_time", [
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 FX-DELAY-CREATE _TD !",
        "  5 _TD @ FX-DELAY!",                # change to 5ms
        "  _TD @ FX-DELAY-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  FX-DIST tests — Soft clip
# ════════════════════════════════════════════════════════════════════

def test_dist_create():
    """FX-DIST-CREATE allocates without error."""
    check_no_error("dist_create", [
        ": TMP 0x4000 0 FX-DIST-CREATE FX-DIST-FREE ; TMP"
    ])

def test_dist_soft_zero():
    """Soft clip of zero input = zero output."""
    check_val("dist_soft_zero", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  0x4000 0 FX-DIST-CREATE _TD !",        # soft clip, drive=2
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0)

def test_dist_soft_one():
    """Soft clip: input=1.0, drive=1.0 → 1/(1+1) = 0.5."""
    check_val("dist_soft_one", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C00 I _TB @ PCM-FRAME! LOOP",
        "  0x3C00 0 FX-DIST-CREATE _TD !",        # soft clip, drive=1
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_dist_soft_negative():
    """Soft clip preserves sign: input=-1.0, drive=1.0 → -0.5."""
    # -0.5 in FP16 = 0xB800
    check_val("dist_soft_neg", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0xBC00 I _TB @ PCM-FRAME! LOOP",
        "  0x3C00 0 FX-DIST-CREATE _TD !",        # soft clip, drive=1
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0xB800)

def test_dist_soft_saturation():
    """Soft clip saturates: high drive, output stays in (-1,1)."""
    # Input 0.5, drive=10 → t=5.0, |t|=5.0, output = 5/6 ≈ 0.833
    # Just check it's < 1.0 (0x3C00) and > 0.7 (~ 0x399A)
    check_val_range("dist_soft_sat", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  0x4900 0 FX-DIST-CREATE _TD !",       # drive=10 (FP16 0x4900)
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0x3900, 0x3C00)

# ════════════════════════════════════════════════════════════════════
#  FX-DIST tests — Hard clip
# ════════════════════════════════════════════════════════════════════

def test_dist_hard_within():
    """Hard clip: input within range passes through scaled."""
    # Input 0.25 (0x3400), drive=2, output = 0.25*2 = 0.5 (within [-1,1])
    check_val("dist_hard_within", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3400 I _TB @ PCM-FRAME! LOOP",
        "  0x4000 1 FX-DIST-CREATE _TD !",        # hard clip, drive=2
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_dist_hard_clip_pos():
    """Hard clip: positive overflow clamped to 1.0."""
    # Input 0.75 (0x3A00), drive=2, output = 0.75*2=1.5 → clamp 1.0
    check_val("dist_hard_clip_pos", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3A00 I _TB @ PCM-FRAME! LOOP",
        "  0x4000 1 FX-DIST-CREATE _TD !",
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_ONE)

def test_dist_hard_clip_neg():
    """Hard clip: negative overflow clamped to -1.0."""
    # Input -0.75 (0xBA00), drive=2, output = -1.5 → clamp -1.0
    check_val("dist_hard_clip_neg", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0xBA00 I _TB @ PCM-FRAME! LOOP",
        "  0x4000 1 FX-DIST-CREATE _TD !",
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_NEG_ONE)

def test_dist_hard_zero():
    """Hard clip: zero stays zero."""
    check_val("dist_hard_zero", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  0x4000 1 FX-DIST-CREATE _TD !",
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0)

# ════════════════════════════════════════════════════════════════════
#  FX-DIST tests — Bitcrush
# ════════════════════════════════════════════════════════════════════

def test_dist_crush_quantize():
    """Bitcrush quantizes: 0x3C0F → 0x3C00 with drive=4 (zero lower 4 bits)."""
    check_val("dist_crush_quant", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C0F I _TB @ PCM-FRAME! LOOP",
        "  0x4400 2 FX-DIST-CREATE _TD !",       # bitcrush, drive=4 (=FP16 4.0)
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",                  # frame 0 captured immediately
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0x3C00)

def test_dist_crush_clean():
    """Bitcrush passes through values with no low bits set."""
    # 0x3800 (0.5) has no bits in lower 4 → unchanged
    check_val("dist_crush_clean", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  0x4400 2 FX-DIST-CREATE _TD !",
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_dist_crush_hold():
    """Bitcrush sample-and-hold: with drive=2, held samples appear."""
    # With drive=2: capture every 2nd sample.
    # Frame 0 = captured (cnt starts at 0), Frame 1 = held.
    # Use 10 frames (>= 16 bytes data) to avoid XMEM-FREE minimum.
    check_vals("dist_crush_hold", [
        "VARIABLE _TB",
        "VARIABLE _TD",
        ": TMP",
        "  10 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  0x3800 0 _TB @ PCM-FRAME!",           # frame 0 = 0.5
        "  0x3C00 1 _TB @ PCM-FRAME!",           # frame 1 = 1.0
        "  0x3400 2 _TB @ PCM-FRAME!",           # frame 2 = 0.25
        "  0x4000 3 _TB @ PCM-FRAME!",           # frame 3 = 2.0
        "  0x4000 2 FX-DIST-CREATE _TD !",       # bitcrush, drive=2
        "  _TB @ _TD @ FX-DIST-PROCESS",
        "  .\" |RESULT|\" CR",
        "  0 _TB @ PCM-FRAME@ .",                # captured: 0x3800
        "  1 _TB @ PCM-FRAME@ .",                # held from frame 0: 0x3800
        "  2 _TB @ PCM-FRAME@ .",                # captured: 0x3400
        "  3 _TB @ PCM-FRAME@ .",                # held from frame 2: 0x3400
        "  _TD @ FX-DIST-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [0x3800, 0x3800, 0x3400, 0x3400])

def test_dist_drive_change():
    """FX-DIST-DRIVE! updates drive parameter."""
    # Start with drive=1 (soft clip, 1*1/(1+1)=0.5), change to drive=2
    # With drive=2: 1*2/(1+2) = 2/3 ≈ 0.6667
    check_no_error("dist_drive_change", [
        "VARIABLE _TD",
        ": TMP",
        "  0x3C00 0 FX-DIST-CREATE _TD !",
        "  0x4000 _TD @ FX-DIST-DRIVE!",
        "  _TD @ FX-DIST-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  Integration tests
# ════════════════════════════════════════════════════════════════════

def test_osc_through_chain():
    """Generate sine with osc, process through distortion chain."""
    check_no_error("osc_through_chain", [
        "VARIABLE _TB",
        "VARIABLE _TO",
        "VARIABLE _TC",
        "VARIABLE _TD",
        ": TMP",
        "  100 1000 16 1 PCM-ALLOC _TB !",
        "  0x5140 0 1000 OSC-CREATE _TO !",    # 440 Hz sine
        "  _TB @ _TO @ OSC-FILL",
        "  0x4000 0 FX-DIST-CREATE _TD !",     # soft clip, drive=2
        "  1 CHAIN-CREATE _TC !",
        "  ['] FX-DIST-PROCESS _TD @ 0 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  _TO @ OSC-FREE",
        "  _TD @ FX-DIST-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

def test_delay_then_dist():
    """Chain: delay (slot 0) → distortion (slot 1)."""
    # This tests that two different effect types work in a chain.
    check_no_error("delay_then_dist", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TDL",
        "VARIABLE _TDS",
        ": TMP",
        "  30 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  5 1000 FX-DELAY-CREATE _TDL !",
        "  0x3C00 1 FX-DIST-CREATE _TDS !",       # hard clip, drive=1 (passthrough)
        "  2 CHAIN-CREATE _TC !",
        "  ['] FX-DELAY-PROCESS _TDL @ 0 _TC @ CHAIN-SET!",
        "  ['] FX-DIST-PROCESS  _TDS @ 1 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  _TDL @ FX-DELAY-FREE",
        "  _TDS @ FX-DIST-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  Main
# ════════════════════════════════════════════════════════════════════

if __name__ == '__main__':
    build_snapshot()
    print()

    print("── chain.f ──")
    test_chain_create()
    test_chain_create_clamp()
    test_chain_process_empty()
    test_chain_set_and_process()
    test_chain_bypass()
    test_chain_clear()
    test_chain_two_effects()

    print("\n── fx.f — delay ──")
    test_delay_create()
    test_delay_silence()
    test_delay_basic()
    test_delay_wet_mix()
    test_delay_feedback()
    test_delay_change_time()

    print("\n── fx.f — dist (soft clip) ──")
    test_dist_create()
    test_dist_soft_zero()
    test_dist_soft_one()
    test_dist_soft_negative()
    test_dist_soft_saturation()

    print("\n── fx.f — dist (hard clip) ──")
    test_dist_hard_within()
    test_dist_hard_clip_pos()
    test_dist_hard_clip_neg()
    test_dist_hard_zero()

    print("\n── fx.f — dist (bitcrush) ──")
    test_dist_crush_quantize()
    test_dist_crush_clean()
    test_dist_crush_hold()
    test_dist_drive_change()

    print("\n── integration ──")
    test_osc_through_chain()
    test_delay_then_dist()

    print(f"\n{'='*50}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*50}")
    sys.exit(1 if _fail_count else 0)
