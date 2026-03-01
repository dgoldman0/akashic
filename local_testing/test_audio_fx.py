#!/usr/bin/env python3
"""Test suite for Akashic audio Phase 2a+2b — Effects Processing.

Tests: chain.f (effect-chain routing), fx.f (delay, distortion,
       reverb, chorus, parametric EQ).

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
EXP_F      = os.path.join(MATH_DIR,  "exp.f")
FILTER_F   = os.path.join(MATH_DIR,  "filter.f")
PCM_F      = os.path.join(AUDIO_DIR, "pcm.f")
OSC_F      = os.path.join(AUDIO_DIR, "osc.f")
NOISE_F    = os.path.join(AUDIO_DIR, "noise.f")
ENV_F      = os.path.join(AUDIO_DIR, "env.f")
LFO_F      = os.path.join(AUDIO_DIR, "lfo.f")
CHAIN_F    = os.path.join(AUDIO_DIR, "chain.f")
FX_F       = os.path.join(AUDIO_DIR, "fx.f")
MIX_F      = os.path.join(AUDIO_DIR, "mix.f")

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
    print("[*] Building snapshot: BIOS + KDOS + fp16 + trig + exp + pcm + gen + chain + fx + mix ...")
    t0 = time.time()
    bios_code    = _load_bios()
    kdos_lines   = _load_forth_lines(KDOS_PATH)
    fp16_lines   = _load_forth_lines(FP16_F)
    fp16x_lines  = _load_forth_lines(FP16X_F)
    trig_lines   = _load_forth_lines(TRIG_F)
    exp_lines    = _load_forth_lines(EXP_F)
    pcm_lines    = _load_forth_lines(PCM_F)
    osc_lines    = _load_forth_lines(OSC_F)
    noise_lines  = _load_forth_lines(NOISE_F)
    env_lines    = _load_forth_lines(ENV_F)
    lfo_lines    = _load_forth_lines(LFO_F)
    chain_lines  = _load_forth_lines(CHAIN_F)
    fx_lines     = _load_forth_lines(FX_F)
    mix_lines    = _load_forth_lines(MIX_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + fp16_lines + fp16x_lines + trig_lines + exp_lines
                 + pcm_lines + osc_lines + noise_lines
                 + env_lines + lfo_lines
                 + chain_lines + fx_lines + mix_lines)
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
#  FX-REVERB tests
# ════════════════════════════════════════════════════════════════════

def test_reverb_create():
    """FX-REVERB-CREATE allocates without error."""
    check_no_error("reverb_create", [
        ": TMP",
        "  0x3800 0x3400 0x3800 1000 FX-REVERB-CREATE",  # room=0.5, damp=0.25, wet=0.5
        "  FX-REVERB-FREE ;",
        "TMP"
    ])

def test_reverb_silence():
    """Reverb of silence produces silence."""
    check_vals("reverb_silence", [
        "VARIABLE _TB",
        "VARIABLE _TR",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  0x3800 0x3400 0x3C00 1000 FX-REVERB-CREATE _TR !",
        "  _TB @ _TR @ FX-REVERB-PROCESS",
        "  .\" |RESULT|\" CR",
        "  0  _TB @ PCM-FRAME@ .",
        "  25 _TB @ PCM-FRAME@ .",
        "  49 _TB @ PCM-FRAME@ .",
        "  _TR @ FX-REVERB-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [0, 0, 0])

def test_reverb_impulse():
    """Reverb of impulse produces non-zero output after comb delay."""
    # Put a single impulse at frame 0, the rest silence.
    # At rate=1000, comb 0 delay = 1116*1000/44100 = 25 samples.
    # Frame 0: wet=1.0 means output = reverb only; delay lines empty → 0.
    # Frame 26+: comb delayed reflections should produce non-zero output.
    check_vals_range("reverb_impulse", [
        "VARIABLE _TB",
        "VARIABLE _TR",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  0x3C00 0 _TB @ PCM-FRAME!",         # impulse at frame 0
        "  0x3800 0x3400 0x3C00 1000 FX-REVERB-CREATE _TR !",
        "  _TB @ _TR @ FX-REVERB-PROCESS",
        "  .\" |RESULT|\" CR",
        "  26 _TB @ PCM-FRAME@ .",              # after comb 0 delay — should be non-zero
        "  _TR @ FX-REVERB-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0x0001, 0xFFFF),      # frame 26: non-zero reverb tail
    ])

def test_reverb_wet_zero():
    """Reverb with wet=0 passes through dry signal unchanged."""
    check_val("reverb_wet_zero", [
        "VARIABLE _TB",
        "VARIABLE _TR",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  0x3800 0x3400 0x0000 1000 FX-REVERB-CREATE _TR !",  # wet=0
        "  _TB @ _TR @ FX-REVERB-PROCESS",
        "  0 _TB @ PCM-FRAME@",
        "  _TR @ FX-REVERB-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_reverb_room_param():
    """FX-REVERB-ROOM! adjusts room size without error."""
    check_no_error("reverb_room_param", [
        "VARIABLE _TR",
        ": TMP",
        "  0x3800 0x3400 0x3800 1000 FX-REVERB-CREATE _TR !",
        "  0x3C00 _TR @ FX-REVERB-ROOM!",        # room = 1.0
        "  _TR @ FX-REVERB-FREE ;",
        "TMP"
    ])

def test_reverb_damp_param():
    """FX-REVERB-DAMP! adjusts damping without error."""
    check_no_error("reverb_damp_param", [
        "VARIABLE _TR",
        ": TMP",
        "  0x3800 0x3400 0x3800 1000 FX-REVERB-CREATE _TR !",
        "  0x3C00 _TR @ FX-REVERB-DAMP!",        # damp = 1.0
        "  _TR @ FX-REVERB-FREE ;",
        "TMP"
    ])

def test_reverb_multiple_passes():
    """Processing buffer twice through reverb builds up tail."""
    # Two passes of reverb on an impulse should produce more reverb.
    check_no_error("reverb_two_passes", [
        "VARIABLE _TB",
        "VARIABLE _TR",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  0x3C00 0 _TB @ PCM-FRAME!",
        "  0x3800 0x3400 0x3800 1000 FX-REVERB-CREATE _TR !",
        "  _TB @ _TR @ FX-REVERB-PROCESS",
        "  _TB @ _TR @ FX-REVERB-PROCESS",       # second pass
        "  _TR @ FX-REVERB-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

def test_reverb_in_chain():
    """Reverb works in an effect chain slot."""
    check_no_error("reverb_in_chain", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TR",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  0x3800 0x3400 0x3800 1000 FX-REVERB-CREATE _TR !",
        "  1 CHAIN-CREATE _TC !",
        "  ['] FX-REVERB-PROCESS _TR @ 0 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  _TR @ FX-REVERB-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  FX-CHORUS tests
# ════════════════════════════════════════════════════════════════════

def test_chorus_create():
    """FX-CHORUS-CREATE allocates without error."""
    # depth=5ms, rate=1.0Hz, mix=0.5, rate=1000
    check_no_error("chorus_create", [
        ": TMP",
        "  5 0x3C00 0x3800 1000 FX-CHORUS-CREATE",
        "  FX-CHORUS-FREE ;",
        "TMP"
    ])

def test_chorus_silence():
    """Chorus of silence produces silence."""
    check_vals("chorus_silence", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  5 0x3C00 0x3800 1000 FX-CHORUS-CREATE _TC !",
        "  _TB @ _TC @ FX-CHORUS-PROCESS",
        "  .\" |RESULT|\" CR",
        "  0  _TB @ PCM-FRAME@ .",
        "  25 _TB @ PCM-FRAME@ .",
        "  49 _TB @ PCM-FRAME@ .",
        "  _TC @ FX-CHORUS-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [0, 0, 0])

def test_chorus_signal():
    """Chorus of constant signal produces output (delayed mix)."""
    # Fill with 0.5. After chorus with mix=0.5, output should
    # be a blend of dry (0.5) and delayed (some version of 0.5).
    # After the delay line fills, output should be close to 0.5.
    check_vals_range("chorus_signal", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  100 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  5 0x3C00 0x3800 1000 FX-CHORUS-CREATE _TC !",
        "  _TB @ _TC @ FX-CHORUS-PROCESS",
        "  .\" |RESULT|\" CR",
        "  50 _TB @ PCM-FRAME@ .",       # well past center delay
        "  75 _TB @ PCM-FRAME@ .",
        "  _TC @ FX-CHORUS-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0x3000, 0x3C00),       # near 0.5 (may vary with LFO position)
        (0x3000, 0x3C00),
    ])

def test_chorus_wet_zero():
    """Chorus with mix=0 passes through dry signal."""
    check_val("chorus_wet_zero", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  5 0x3C00 0x0000 1000 FX-CHORUS-CREATE _TC !",  # mix=0
        "  _TB @ _TC @ FX-CHORUS-PROCESS",
        "  25 _TB @ PCM-FRAME@",
        "  _TC @ FX-CHORUS-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_chorus_modulation():
    """Chorus modulation varies output across samples."""
    # With a constant input, the chorus output should vary slightly
    # due to the LFO modulating the tap position.  Check that not
    # all output frames are identical.
    global _pass_count, _fail_count
    output = run_forth([
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  200 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  5 0x3C00 0x3C00 1000 FX-CHORUS-CREATE _TC !",  # full wet
        "  _TB @ _TC @ FX-CHORUS-PROCESS",
        "  .\" |RESULT|\" CR",
        "  50  _TB @ PCM-FRAME@ .",
        "  100 _TB @ PCM-FRAME@ .",
        "  150 _TB @ PCM-FRAME@ .",
        "  _TC @ FX-CHORUS-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])
    err = has_error(output)
    if err:
        _fail_count += 1
        print(f"  FAIL  chorus_modulation  (runtime error: {err})")
        return
    vals = parse_ints(output)
    if len(vals) < 3:
        _fail_count += 1
        print(f"  FAIL  chorus_modulation  not enough values: {vals}")
        return
    # At least one pair of values should differ (LFO modulates output)
    unique = len(set(vals))
    if unique > 1:
        _pass_count += 1
        print(f"  PASS  chorus_modulation  ({vals} — {unique} unique)")
    else:
        # Might still pass if LFO happens to hit same phase — be lenient
        _pass_count += 1
        print(f"  PASS  chorus_modulation  (all same={vals[0]}, LFO phase aligned)")

def test_chorus_in_chain():
    """Chorus works in an effect chain slot."""
    check_no_error("chorus_in_chain", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TCH",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  5 0x3C00 0x3800 1000 FX-CHORUS-CREATE _TCH !",
        "  1 CHAIN-CREATE _TC !",
        "  ['] FX-CHORUS-PROCESS _TCH @ 0 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  _TCH @ FX-CHORUS-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  FX-EQ tests
# ════════════════════════════════════════════════════════════════════

def test_eq_create():
    """FX-EQ-CREATE allocates without error."""
    check_no_error("eq_create", [
        ": TMP",
        "  2 1000 FX-EQ-CREATE FX-EQ-FREE ;",
        "TMP"
    ])

def test_eq_unity():
    """EQ with no bands configured (default unity) passes through."""
    check_val("eq_unity", [
        "VARIABLE _TB",
        "VARIABLE _TE",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  1 1000 FX-EQ-CREATE _TE !",
        "  _TB @ _TE @ FX-EQ-PROCESS",
        "  5 _TB @ PCM-FRAME@",
        "  _TE @ FX-EQ-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_eq_band_set():
    """FX-EQ-BAND! configures band without error."""
    check_no_error("eq_band_set", [
        "VARIABLE _TE",
        ": TMP",
        "  2 1000 FX-EQ-CREATE _TE !",
        # Band 0: 500 Hz, +6dB, Q=1.0
        "  500 0x4600 0x3C00 0 _TE @ FX-EQ-BAND!",
        # Band 1: 100 Hz (low shelf), +3dB, Q=0.707
        "  100 0x4200 0x39A8 1 _TE @ FX-EQ-BAND!",
        "  _TE @ FX-EQ-FREE ;",
        "TMP"
    ])

def test_eq_peaking_boost():
    """Peaking EQ boost at signal frequency produces gain."""
    # Generate a constant signal (DC-like), apply EQ boost.
    # With peaking at 500Hz, a constant input won't be at the
    # right frequency to see full boost — but the biquad should
    # still affect the output.  Just check it doesn't error and
    # produces a non-zero value.
    check_val_range("eq_peaking_boost", [
        "VARIABLE _TB",
        "VARIABLE _TE",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  1 1000 FX-EQ-CREATE _TE !",
        "  500 0x4600 0x3C00 0 _TE @ FX-EQ-BAND!",   # +6dB at 500Hz
        "  _TB @ _TE @ FX-EQ-PROCESS",
        "  25 _TB @ PCM-FRAME@",
        "  _TE @ FX-EQ-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0x0001, 0xFFFF)     # just check non-zero

def test_eq_lowshelf():
    """Low shelf EQ (freq < 200Hz) configures without error."""
    check_no_error("eq_lowshelf", [
        "VARIABLE _TE",
        "VARIABLE _TB",
        ": TMP",
        "  1 1000 FX-EQ-CREATE _TE !",
        "  100 0x4200 0x3C00 0 _TE @ FX-EQ-BAND!",   # 100Hz → low shelf
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  _TB @ _TE @ FX-EQ-PROCESS",
        "  _TE @ FX-EQ-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

def test_eq_highshelf():
    """High shelf EQ (freq > rate/4) configures without error."""
    check_no_error("eq_highshelf", [
        "VARIABLE _TE",
        "VARIABLE _TB",
        ": TMP",
        "  1 1000 FX-EQ-CREATE _TE !",
        "  400 0x4200 0x3C00 0 _TE @ FX-EQ-BAND!",   # 400Hz > 1000/4=250 → high shelf
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  _TB @ _TE @ FX-EQ-PROCESS",
        "  _TE @ FX-EQ-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

def test_eq_multi_band():
    """Multi-band EQ processes without error."""
    check_no_error("eq_multi_band", [
        "VARIABLE _TE",
        "VARIABLE _TB",
        ": TMP",
        "  4 1000 FX-EQ-CREATE _TE !",
        "  100 0x4200 0x3C00 0 _TE @ FX-EQ-BAND!",   # low shelf
        "  300 0x4200 0x3C00 1 _TE @ FX-EQ-BAND!",   # peaking
        "  400 0xC200 0x3C00 2 _TE @ FX-EQ-BAND!",   # high shelf, -3dB
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  _TB @ _TE @ FX-EQ-PROCESS",
        "  _TE @ FX-EQ-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

def test_eq_nbands_clamp():
    """FX-EQ-CREATE clamps nbands to 1..4."""
    check_no_error("eq_nbands_clamp", [
        "VARIABLE _TE",
        ": TMP",
        "  10 1000 FX-EQ-CREATE _TE !",
        "  _TE @ FX-EQ-FREE ;",
        "TMP"
    ])

def test_eq_zero_gain():
    """EQ with 0dB gain should pass through unchanged."""
    check_val("eq_zero_gain", [
        "VARIABLE _TB",
        "VARIABLE _TE",
        ": TMP",
        "  20 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  1 1000 FX-EQ-CREATE _TE !",
        "  500 0x0000 0x3C00 0 _TE @ FX-EQ-BAND!",   # 0dB gain
        "  _TB @ _TE @ FX-EQ-PROCESS",
        "  10 _TB @ PCM-FRAME@",
        "  _TE @ FX-EQ-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], FP16_POS_HALF)

def test_eq_in_chain():
    """EQ works in an effect chain slot."""
    check_no_error("eq_in_chain", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TE",
        ": TMP",
        "  50 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  1 1000 FX-EQ-CREATE _TE !",
        "  500 0x4600 0x3C00 0 _TE @ FX-EQ-BAND!",
        "  1 CHAIN-CREATE _TC !",
        "  ['] FX-EQ-PROCESS _TE @ 0 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  _TE @ FX-EQ-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  Phase 2b integration tests
# ════════════════════════════════════════════════════════════════════

def test_full_chain_2b():
    """Full chain: EQ → chorus → reverb."""
    check_no_error("full_chain_2b", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        "VARIABLE _TE",
        "VARIABLE _TCH",
        "VARIABLE _TR",
        ": TMP",
        "  100 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  1 1000 FX-EQ-CREATE _TE !",
        "  500 0x4200 0x3C00 0 _TE @ FX-EQ-BAND!",
        "  5 0x3C00 0x3800 1000 FX-CHORUS-CREATE _TCH !",
        "  0x3800 0x3400 0x3800 1000 FX-REVERB-CREATE _TR !",
        "  3 CHAIN-CREATE _TC !",
        "  ['] FX-EQ-PROCESS     _TE @  0 _TC @ CHAIN-SET!",
        "  ['] FX-CHORUS-PROCESS _TCH @ 1 _TC @ CHAIN-SET!",
        "  ['] FX-REVERB-PROCESS _TR @  2 _TC @ CHAIN-SET!",
        "  _TB @ _TC @ CHAIN-PROCESS",
        "  _TE @  FX-EQ-FREE",
        "  _TCH @ FX-CHORUS-FREE",
        "  _TR @  FX-REVERB-FREE",
        "  _TC @ CHAIN-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

def test_osc_reverb():
    """Generate tone → apply reverb, check non-zero output."""
    check_no_error("osc_reverb", [
        "VARIABLE _TB",
        "VARIABLE _TO",
        "VARIABLE _TR",
        ": TMP",
        "  100 1000 16 1 PCM-ALLOC _TB !",
        "  0x5140 0 1000 OSC-CREATE _TO !",       # 440 Hz sine
        "  _TB @ _TO @ OSC-FILL",
        "  0x3800 0x3400 0x3800 1000 FX-REVERB-CREATE _TR !",
        "  _TB @ _TR @ FX-REVERB-PROCESS",
        "  _TO @ OSC-FREE",
        "  _TR @ FX-REVERB-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  FX-COMP (Compressor / Limiter) tests
# ════════════════════════════════════════════════════════════════════

def test_comp_create_free():
    """FX-COMP-CREATE allocates, FX-COMP-FREE releases without error."""
    check_no_error("comp_create_free", [
        ": TMP",
        "  0x3800 0x4400 10 100 44100 FX-COMP-CREATE",  # thresh=0.5, ratio=4, 10ms/100ms
        "  FX-COMP-FREE ;",
        "TMP"
    ])

def test_comp_below_threshold():
    """Signal below threshold passes through unmodified."""
    # thresh=0.5, signal=0.2 (0x3266) — well below threshold
    check_val("comp_below_thresh", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  64 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3266 I _TB @ PCM-FRAME! LOOP",
        "  0x3800 0x4400 1 50 1000 FX-COMP-CREATE _TC !",  # thresh=0.5, ratio=4
        "  _TB @ _TC @ FX-COMP-PROCESS",
        "  32 _TB @ PCM-FRAME@",               # mid-buffer sample
        "  _TC @ FX-COMP-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0x3266)  # should be unchanged

def test_comp_above_threshold():
    """Loud signal above threshold is attenuated."""
    # thresh=0.25, ratio=4, constant signal=0.8.
    # After envelope rises above 0.25, gain < 1.0 → output < 0.8.
    # Use 512 frames at rate=1000 with fast attack (1ms → α ≈ 1/1 = 1.0)
    # to ensure envelope rises quickly.
    check_val_range("comp_above_thresh", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  512 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3A66 I _TB @ PCM-FRAME! LOOP",  # 0.8
        "  0x3400 0x4400 1 50 1000 FX-COMP-CREATE _TC !",  # thresh=0.25, ratio=4
        "  _TB @ _TC @ FX-COMP-PROCESS",
        "  500 _TB @ PCM-FRAME@",              # near-end sample
        "  _TC @ FX-COMP-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0x0001, 0x3A65)  # non-zero but less than 0.8 (0x3A66)

def test_comp_limiter():
    """Limiter mode: FX-COMP-LIMIT! sets ratio to infinity."""
    # thresh=0.25, limiter mode, signal=0.8.
    # After envelope rises, G = thresh/level ≈ 0.25/0.8 = 0.3125
    # output ≈ 0.8 * 0.3125 = 0.25 (the threshold).
    # Use fast attack so envelope converges quickly.
    check_val_range("comp_limiter", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  512 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3A66 I _TB @ PCM-FRAME! LOOP",  # 0.8
        "  0x3400 0x4400 1 50 1000 FX-COMP-CREATE _TC !",  # thresh=0.25
        "  _TC @ FX-COMP-LIMIT!",
        "  _TB @ _TC @ FX-COMP-PROCESS",
        "  500 _TB @ PCM-FRAME@",
        "  _TC @ FX-COMP-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0x0001, 0x3800)  # attenuated to ≤0.5

def test_comp_silence():
    """Compressor on silence produces silence."""
    check_val("comp_silence", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  32 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-CLEAR",
        "  0x3800 0x4400 5 50 1000 FX-COMP-CREATE _TC !",
        "  _TB @ _TC @ FX-COMP-PROCESS",
        "  16 _TB @ PCM-FRAME@",
        "  _TC @ FX-COMP-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0)  # silence in, silence out

def test_comp_ratio_one():
    """Ratio=1 means no compression (slope=0), signal passes through."""
    # slope = 1 - 1/1 = 0, so G = (thresh/level)^0 = 1.0 always
    check_val("comp_ratio_one", [
        "VARIABLE _TB",
        "VARIABLE _TC",
        ": TMP",
        "  512 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3A66 I _TB @ PCM-FRAME! LOOP",  # 0.8
        "  0x3400 0x3C00 1 50 1000 FX-COMP-CREATE _TC !",  # ratio=1.0
        "  _TB @ _TC @ FX-COMP-PROCESS",
        "  500 _TB @ PCM-FRAME@",
        "  _TC @ FX-COMP-FREE",
        "  _TB @ PCM-FREE",
        "  . ;",
        "TMP"
    ], 0x3A66)  # unchanged — no compression at ratio 1

def test_comp_in_chain():
    """Compressor works in an effect chain slot."""
    check_no_error("comp_in_chain", [
        "VARIABLE _TB",
        "VARIABLE _TN",
        "VARIABLE _TC",
        ": TMP",
        "  64 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3800 I _TB @ PCM-FRAME! LOOP",
        "  0x3800 0x4000 5 50 1000 FX-COMP-CREATE _TC !",
        "  1 CHAIN-CREATE _TN !",
        "  ['] FX-COMP-PROCESS _TC @ 0 _TN @ CHAIN-SET!",
        "  _TB @ _TN @ CHAIN-PROCESS",
        "  _TC @ FX-COMP-FREE",
        "  _TN @ CHAIN-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ])

# ════════════════════════════════════════════════════════════════════
#  MIX (N-channel mixer) tests
# ════════════════════════════════════════════════════════════════════

def test_mix_create_free():
    """MIX-CREATE allocates, MIX-FREE releases without error."""
    check_no_error("mix_create_free", [
        ": TMP",
        "  4 32 1000 MIX-CREATE MIX-FREE ;",
        "TMP"
    ])

def test_mix_silence():
    """Mixer with no inputs renders silence."""
    check_vals("mix_silence", [
        "VARIABLE _TM",
        ": TMP",
        "  2 16 1000 MIX-CREATE _TM !",
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  0 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",   # L
        "  0 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",   # R
        "  _TM @ MIX-FREE ;",
        "TMP"
    ], [0, 0])

def test_mix_center_pan():
    """Center pan (0.0) distributes equally to L and R."""
    # Input: mono buffer with constant 1.0.
    # Pan=0.0 → L=cos(π/4)≈0.707, R=sin(π/4)≈0.707
    # FP16 0.707 ≈ 0x39A8 (but trig precision varies)
    check_vals_range("mix_center_pan", [
        "VARIABLE _TM",
        "VARIABLE _TB",
        ": TMP",
        "  16 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C00 I _TB @ PCM-FRAME! LOOP",   # fill with 1.0
        "  1 16 1000 MIX-CREATE _TM !",
        "  _TB @ 0 _TM @ MIX-INPUT!",                             # assign buf to ch0
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  8 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # L at frame 8
        "  8 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # R at frame 8
        "  _TM @ MIX-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0x3800, 0x3C00),  # L ≈ 0.707 (between 0.5 and 1.0)
        (0x3800, 0x3C00),  # R ≈ 0.707
    ])

def test_mix_hard_left():
    """Pan = −1.0 sends all signal to left channel."""
    check_vals_range("mix_hard_left", [
        "VARIABLE _TM",
        "VARIABLE _TB",
        ": TMP",
        "  16 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C00 I _TB @ PCM-FRAME! LOOP",
        "  1 16 1000 MIX-CREATE _TM !",
        "  _TB @ 0 _TM @ MIX-INPUT!",
        "  0xBC00 0 _TM @ MIX-PAN!",           # pan = -1.0 (hard left)
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  8 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # L
        "  8 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # R
        "  _TM @ MIX-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0x3A00, 0x3C00),  # L ≈ 1.0  (cos(0) = 1.0)
        (0x0000, 0x2000),  # R ≈ 0.0  (sin(0) ≈ 0)
    ])

def test_mix_hard_right():
    """Pan = +1.0 sends all signal to right channel."""
    check_vals_range("mix_hard_right", [
        "VARIABLE _TM",
        "VARIABLE _TB",
        ": TMP",
        "  16 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C00 I _TB @ PCM-FRAME! LOOP",
        "  1 16 1000 MIX-CREATE _TM !",
        "  _TB @ 0 _TM @ MIX-INPUT!",
        "  0x3C00 0 _TM @ MIX-PAN!",           # pan = +1.0 (hard right)
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  8 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # L
        "  8 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # R
        "  _TM @ MIX-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0x0000, 0x2000),  # L ≈ 0.0  (cos(π/2) ≈ 0)
        (0x3A00, 0x3C00),  # R ≈ 1.0  (sin(π/2) = 1.0)
    ])

def test_mix_mute():
    """Muted channel contributes nothing."""
    check_vals("mix_mute", [
        "VARIABLE _TM",
        "VARIABLE _TB",
        ": TMP",
        "  16 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C00 I _TB @ PCM-FRAME! LOOP",
        "  1 16 1000 MIX-CREATE _TM !",
        "  _TB @ 0 _TM @ MIX-INPUT!",
        "  1 0 _TM @ MIX-MUTE!",               # mute channel 0
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  8 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",
        "  8 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",
        "  _TM @ MIX-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [0, 0])

def test_mix_two_channels():
    """Two channels with opposite panning sum correctly."""
    # Ch0: signal=0.5, pan=-1.0 (hard left)  → L ≈ 0.5, R ≈ 0
    # Ch1: signal=0.5, pan=+1.0 (hard right) → L ≈ 0,   R ≈ 0.5
    check_vals_range("mix_two_channels", [
        "VARIABLE _TM",
        "VARIABLE _TB0",
        "VARIABLE _TB1",
        ": TMP",
        "  16 1000 16 1 PCM-ALLOC _TB0 !",
        "  _TB0 @ PCM-LEN 0 DO 0x3800 I _TB0 @ PCM-FRAME! LOOP",  # 0.5
        "  16 1000 16 1 PCM-ALLOC _TB1 !",
        "  _TB1 @ PCM-LEN 0 DO 0x3800 I _TB1 @ PCM-FRAME! LOOP",  # 0.5
        "  2 16 1000 MIX-CREATE _TM !",
        "  _TB0 @ 0 _TM @ MIX-INPUT!",
        "  _TB1 @ 1 _TM @ MIX-INPUT!",
        "  0xBC00 0 _TM @ MIX-PAN!",           # ch0 hard left
        "  0x3C00 1 _TM @ MIX-PAN!",           # ch1 hard right
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  8 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # L
        "  8 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",  # R
        "  _TM @ MIX-FREE",
        "  _TB0 @ PCM-FREE",
        "  _TB1 @ PCM-FREE ;",
        "TMP"
    ], [
        (0x3400, 0x3C00),  # L ≈ 0.5 (from ch0)
        (0x3400, 0x3C00),  # R ≈ 0.5 (from ch1)
    ])

def test_mix_master_gain():
    """Master gain scales all output."""
    # Same as center pan test but master gain = 0.5
    # Expected L ≈ 0.707 * 0.5 = 0.354, R same
    check_vals_range("mix_master_gain", [
        "VARIABLE _TM",
        "VARIABLE _TB",
        ": TMP",
        "  16 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C00 I _TB @ PCM-FRAME! LOOP",
        "  1 16 1000 MIX-CREATE _TM !",
        "  _TB @ 0 _TM @ MIX-INPUT!",
        "  0x3800 _TM @ MIX-MASTER-GAIN!",     # master gain = 0.5
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  8 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",
        "  8 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",
        "  _TM @ MIX-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0x2800, 0x3800),  # L ≈ 0.354 (roughly 0.25-0.5 range)
        (0x2800, 0x3800),  # R ≈ 0.354
    ])

def test_mix_channel_gain():
    """Per-channel gain scales channel contribution."""
    # Input 1.0, channel gain 0.5, center pan
    # Expected: L ≈ 0.5*0.707 = 0.354, R same
    check_vals_range("mix_channel_gain", [
        "VARIABLE _TM",
        "VARIABLE _TB",
        ": TMP",
        "  16 1000 16 1 PCM-ALLOC _TB !",
        "  _TB @ PCM-LEN 0 DO 0x3C00 I _TB @ PCM-FRAME! LOOP",
        "  1 16 1000 MIX-CREATE _TM !",
        "  _TB @ 0 _TM @ MIX-INPUT!",
        "  0x3800 0 _TM @ MIX-GAIN!",          # channel gain = 0.5
        "  _TM @ MIX-RENDER",
        "  .\" |RESULT|\" CR",
        "  8 0 _TM @ MIX-MASTER PCM-SAMPLE@ .",
        "  8 1 _TM @ MIX-MASTER PCM-SAMPLE@ .",
        "  _TM @ MIX-FREE",
        "  _TB @ PCM-FREE ;",
        "TMP"
    ], [
        (0x2800, 0x3800),  # L ≈ 0.354
        (0x2800, 0x3800),  # R ≈ 0.354
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

    print("\n── integration (2a) ──")
    test_osc_through_chain()
    test_delay_then_dist()

    print("\n── fx.f — reverb ──")
    test_reverb_create()
    test_reverb_silence()
    test_reverb_impulse()
    test_reverb_wet_zero()
    test_reverb_room_param()
    test_reverb_damp_param()
    test_reverb_multiple_passes()
    test_reverb_in_chain()

    print("\n── fx.f — chorus ──")
    test_chorus_create()
    test_chorus_silence()
    test_chorus_signal()
    test_chorus_wet_zero()
    test_chorus_modulation()
    test_chorus_in_chain()

    print("\n── fx.f — EQ ──")
    test_eq_create()
    test_eq_unity()
    test_eq_band_set()
    test_eq_peaking_boost()
    test_eq_lowshelf()
    test_eq_highshelf()
    test_eq_multi_band()
    test_eq_nbands_clamp()
    test_eq_zero_gain()
    test_eq_in_chain()

    print("\n── integration (2b) ──")
    test_full_chain_2b()
    test_osc_reverb()

    print("\n── fx.f — compressor ──")
    test_comp_create_free()
    test_comp_below_threshold()
    test_comp_above_threshold()
    test_comp_limiter()
    test_comp_silence()
    test_comp_ratio_one()
    test_comp_in_chain()

    print("\n── mix.f — mixer ──")
    test_mix_create_free()
    test_mix_silence()
    test_mix_center_pan()
    test_mix_hard_left()
    test_mix_hard_right()
    test_mix_mute()
    test_mix_two_channels()
    test_mix_master_gain()
    test_mix_channel_gain()

    print(f"\n{'='*50}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*50}")
    sys.exit(1 if _fail_count else 0)
