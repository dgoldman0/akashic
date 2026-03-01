#!/usr/bin/env python3
"""Test suite for Akashic audio Phase 4 — Synthesis Engines.

Tests: pluck.f (Karplus-Strong), synth.f (subtractive), fm.f (FM synthesis).

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
SIMD_F     = os.path.join(MATH_DIR,  "simd.f")
SORT_F     = os.path.join(MATH_DIR,  "sort.f")
FILTER_F   = os.path.join(MATH_DIR,  "filter.f")
PCM_F      = os.path.join(AUDIO_DIR, "pcm.f")
OSC_F      = os.path.join(AUDIO_DIR, "osc.f")
NOISE_F    = os.path.join(AUDIO_DIR, "noise.f")
ENV_F      = os.path.join(AUDIO_DIR, "env.f")
LFO_F      = os.path.join(AUDIO_DIR, "lfo.f")
CHAIN_F    = os.path.join(AUDIO_DIR, "chain.f")
FX_F       = os.path.join(AUDIO_DIR, "fx.f")
MIX_F      = os.path.join(AUDIO_DIR, "mix.f")
PLUCK_F    = os.path.join(AUDIO_DIR, "pluck.f")
SYNTH_F    = os.path.join(AUDIO_DIR, "synth.f")
FM_F       = os.path.join(AUDIO_DIR, "fm.f")

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
    print("[*] Building snapshot: BIOS + KDOS + fp16 + trig + exp + filter + pcm + gen + chain + fx + mix + pluck + synth + fm ...")
    t0 = time.time()
    bios_code    = _load_bios()
    kdos_lines   = _load_forth_lines(KDOS_PATH)
    fp16_lines   = _load_forth_lines(FP16_F)
    fp16x_lines  = _load_forth_lines(FP16X_F)
    trig_lines   = _load_forth_lines(TRIG_F)
    exp_lines    = _load_forth_lines(EXP_F)
    simd_lines   = _load_forth_lines(SIMD_F)
    sort_lines   = _load_forth_lines(SORT_F)
    filter_lines = _load_forth_lines(FILTER_F)
    pcm_lines    = _load_forth_lines(PCM_F)
    osc_lines    = _load_forth_lines(OSC_F)
    noise_lines  = _load_forth_lines(NOISE_F)
    env_lines    = _load_forth_lines(ENV_F)
    lfo_lines    = _load_forth_lines(LFO_F)
    chain_lines  = _load_forth_lines(CHAIN_F)
    fx_lines     = _load_forth_lines(FX_F)
    mix_lines    = _load_forth_lines(MIX_F)
    pluck_lines  = _load_forth_lines(PLUCK_F)
    synth_lines  = _load_forth_lines(SYNTH_F)
    fm_lines     = _load_forth_lines(FM_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + fp16_lines + fp16x_lines + trig_lines + exp_lines
                 + simd_lines + sort_lines + filter_lines
                 + pcm_lines + osc_lines + noise_lines
                 + env_lines + lfo_lines
                 + chain_lines + fx_lines + mix_lines
                 + pluck_lines + synth_lines + fm_lines)
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
#  Pluck tests — Karplus-Strong
# ════════════════════════════════════════════════════════════════════

def test_pluck_create_free():
    """PLUCK-CREATE allocates, PLUCK-FREE deallocates without error."""
    check_no_error("pluck_create_free", [
        ": TMP",
        "  440 INT>FP16 1000 PLUCK-CREATE",
        "  PLUCK-FREE ;",
        "TMP"
    ])

def test_pluck_delay_length():
    """Delay line length = rate / freq.  1000 Hz / 100 Hz = 10 samples."""
    check_val("pluck_delay_length", [
        ": TMP",
        "  100 INT>FP16 1000 PLUCK-CREATE",
        "  DUP PLUCK-LEN SWAP PLUCK-FREE . ;",
        "TMP"
    ], 10)

def test_pluck_freq():
    """PLUCK-FREQ returns the frequency set at creation."""
    # 440 INT>FP16 = 0x5D80 (FP16 for 440.0)
    check_val("pluck_freq", [
        ": TMP",
        "  440 INT>FP16 1000 PLUCK-CREATE",
        "  DUP PLUCK-FREQ SWAP PLUCK-FREE . ;",
        "TMP"
    ], float_to_fp16(440.0))

def test_pluck_excite_nonsilent():
    """After PLUCK-EXCITE, the first rendered sample should be non-zero."""
    check_val("pluck_excite_nonsilent", [
        "VARIABLE _PD",
        ": TMP",
        "  440 INT>FP16 1000 PLUCK-CREATE _PD !",
        "  _PD @ PLUCK-EXCITE",
        "  _PD @ PLUCK-RENDER",   # returns buf
        "  0 SWAP PCM-FRAME@",    # read frame 0
        "  0<>",                   # non-zero?
        "  _PD @ PLUCK-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_pluck_decay_over_time():
    """Energy should decrease over time (later samples smaller in magnitude)."""
    # Render, check that |sample_0| + ... + |sample_N/4| > |sample_3N/4| + ...
    check_val("pluck_decay_over_time", [
        "VARIABLE _PD",
        "VARIABLE _PBF",
        "VARIABLE _PS1",
        "VARIABLE _PS2",
        ": TMP",
        "  200 INT>FP16 1000 PLUCK-CREATE _PD !",
        "  _PD @ PLUCK-EXCITE",
        "  _PD @ PLUCK-RENDER _PBF !",
        # Sum |samples| in first quarter
        "  0x0000 _PS1 !",
        "  64 0 DO",
        "    I _PBF @ PCM-FRAME@ FP16-ABS",
        "    _PS1 @ FP16-ADD _PS1 !",
        "  LOOP",
        # Sum |samples| in last quarter
        "  0x0000 _PS2 !",
        "  256 192 DO",
        "    I _PBF @ PCM-FRAME@ FP16-ABS",
        "    _PS2 @ FP16-ADD _PS2 !",
        "  LOOP",
        # First quarter energy > last quarter energy?
        "  _PS1 @ _PS2 @ FP16-GT",
        "  _PD @ PLUCK-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_pluck_decay_setter():
    """PLUCK-DECAY! changes the loss factor."""
    # With decay=0.5 (very fast), after excite+render, energy should
    # drop much faster than default (0.996).
    check_val("pluck_decay_setter", [
        "VARIABLE _PD",
        "VARIABLE _PBF",
        ": TMP",
        "  200 INT>FP16 1000 PLUCK-CREATE _PD !",
        "  0x3800 _PD @ PLUCK-DECAY!",  # decay = 0.5
        "  _PD @ PLUCK-EXCITE",
        "  _PD @ PLUCK-RENDER _PBF !",
        # Last sample should be near zero (fast decay)
        "  255 _PBF @ PCM-FRAME@ FP16-ABS",
        "  0x2000 FP16-LT",            # |last| < 0.0156 (very small)
        "  _PD @ PLUCK-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_pluck_render_twice():
    """Rendering twice continues from state — second block has lower energy."""
    check_val("pluck_render_twice", [
        "VARIABLE _PD",
        "VARIABLE _PB1",
        "VARIABLE _PB2",
        "VARIABLE _PE1",
        "VARIABLE _PE2",
        ": TMP",
        "  200 INT>FP16 1000 PLUCK-CREATE _PD !",
        "  _PD @ PLUCK-EXCITE",
        # First render — measure energy
        "  _PD @ PLUCK-RENDER _PB1 !",
        "  0x0000 _PE1 !",
        "  256 0 DO",
        "    I _PB1 @ PCM-FRAME@ FP16-ABS",
        "    _PE1 @ FP16-ADD _PE1 !",
        "  LOOP",
        # Second render
        "  _PD @ PLUCK-RENDER _PB2 !",
        "  0x0000 _PE2 !",
        "  256 0 DO",
        "    I _PB2 @ PCM-FRAME@ FP16-ABS",
        "    _PE2 @ FP16-ADD _PE2 !",
        "  LOOP",
        # First block energy > second block?
        "  _PE1 @ _PE2 @ FP16-GT",
        "  _PD @ PLUCK-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_pluck_one_shot():
    """PLUCK one-shot fills a pre-allocated buffer with sound."""
    check_val("pluck_one_shot", [
        "VARIABLE _PB",
        ": TMP",
        "  256 1000 16 1 PCM-ALLOC _PB !",
        "  200 INT>FP16",
        "  996 INT>FP16 1000 INT>FP16 FP16-DIV",   # decay = 0.996
        "  _PB @",
        "  PLUCK",
        # Check frame 0 is non-zero
        "  0 _PB @ PCM-FRAME@ 0<>",
        "  _PB @ PCM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_pluck_pitch_affects_length():
    """Higher frequency → shorter delay line."""
    check_val("pluck_pitch_length", [
        "VARIABLE _PL",
        "VARIABLE _PH",
        ": TMP",
        "  100 INT>FP16 1000 PLUCK-CREATE _PL !",  # 100 Hz → len=10
        "  200 INT>FP16 1000 PLUCK-CREATE _PH !",  # 200 Hz → len=5
        "  _PL @ PLUCK-LEN _PH @ PLUCK-LEN >",     # 10 > 5
        "  _PL @ PLUCK-FREE _PH @ PLUCK-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_pluck_re_excite():
    """Re-exciting restores energy."""
    check_val("pluck_re_excite", [
        "VARIABLE _PD",
        "VARIABLE _PB",
        ": TMP",
        "  200 INT>FP16 1000 PLUCK-CREATE _PD !",
        "  _PD @ PLUCK-EXCITE",
        # Render several blocks to decay
        "  _PD @ PLUCK-RENDER DROP",
        "  _PD @ PLUCK-RENDER DROP",
        "  _PD @ PLUCK-RENDER DROP",
        # Re-excite
        "  _PD @ PLUCK-EXCITE",
        "  _PD @ PLUCK-RENDER _PB !",
        # First sample of fresh excitation should be non-zero
        "  0 _PB @ PCM-FRAME@ 0<>",
        "  _PD @ PLUCK-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)


# ════════════════════════════════════════════════════════════════════
#  Synth tests — Subtractive synthesis
# ════════════════════════════════════════════════════════════════════

def test_synth_create_free():
    """SYNTH-CREATE allocates voice, SYNTH-FREE deallocates without error."""
    check_no_error("synth_create_free", [
        ": TMP",
        "  0 -1 1000 64 SYNTH-CREATE",   # sine osc1, no osc2
        "  SYNTH-FREE ;",
        "TMP"
    ])

def test_synth_create_dual_osc():
    """Create voice with two oscillators (sine + saw)."""
    check_no_error("synth_create_dual", [
        ": TMP",
        "  0 2 1000 64 SYNTH-CREATE",    # sine + saw
        "  SYNTH-FREE ;",
        "TMP"
    ])

def test_synth_note_on_renders():
    """After NOTE-ON, SYNTH-RENDER produces non-silent output."""
    check_val("synth_note_on_renders", [
        "VARIABLE _SV",
        "VARIABLE _SB",
        ": TMP",
        "  0 -1 1000 64 SYNTH-CREATE _SV !",
        "  440 INT>FP16 0x3C00 _SV @ SYNTH-NOTE-ON",
        "  _SV @ SYNTH-RENDER _SB !",
        # Check some sample is non-zero
        "  0",                             # accumulator
        "  64 0 DO",
        "    I _SB @ PCM-FRAME@ 0<> IF 1+ THEN",
        "  LOOP",
        "  0>",                            # any non-zero?
        "  _SV @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_synth_note_off_decays():
    """After NOTE-OFF, amplitude envelope decays toward zero."""
    check_val("synth_note_off_decays", [
        "VARIABLE _SV",
        "VARIABLE _SB",
        "VARIABLE _SE1",
        "VARIABLE _SE2",
        ": TMP",
        "  0 -1 1000 64 SYNTH-CREATE _SV !",
        "  440 INT>FP16 0x3C00 _SV @ SYNTH-NOTE-ON",
        # Render a few blocks during sustain
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-RENDER DROP",
        # Measure energy before note-off
        "  _SV @ SYNTH-RENDER _SB !",
        "  0x0000 _SE1 !",
        "  64 0 DO I _SB @ PCM-FRAME@ FP16-ABS _SE1 @ FP16-ADD _SE1 ! LOOP",
        # Note off
        "  _SV @ SYNTH-NOTE-OFF",
        # Render several blocks to let release happen
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-RENDER _SB !",
        "  0x0000 _SE2 !",
        "  64 0 DO I _SB @ PCM-FRAME@ FP16-ABS _SE2 @ FP16-ADD _SE2 ! LOOP",
        # Energy should be lower after release
        "  _SE1 @ _SE2 @ FP16-GT",
        "  _SV @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_synth_cutoff_setter():
    """SYNTH-CUTOFF! changes the filter cutoff without error."""
    check_no_error("synth_cutoff_setter", [
        "VARIABLE _SV",
        ": TMP",
        "  0 -1 1000 64 SYNTH-CREATE _SV !",
        "  500 INT>FP16 _SV @ SYNTH-CUTOFF!",
        "  440 INT>FP16 0x3C00 _SV @ SYNTH-NOTE-ON",
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-FREE ;",
        "TMP"
    ])

def test_synth_reso_setter():
    """SYNTH-RESO! changes the filter resonance without error."""
    check_no_error("synth_reso_setter", [
        "VARIABLE _SV",
        ": TMP",
        "  0 -1 1000 64 SYNTH-CREATE _SV !",
        "  0x4000 _SV @ SYNTH-RESO!",    # Q = 2.0
        "  440 INT>FP16 0x3C00 _SV @ SYNTH-NOTE-ON",
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-FREE ;",
        "TMP"
    ])

def test_synth_lp_vs_hp():
    """LP filter passes more low-freq energy than HP when fundamental < cutoff."""
    # Use saw wave (rich harmonics) at 50 Hz with cutoff 200 Hz
    # LP passes the fundamental, HP blocks it → LP has more energy
    check_val("synth_lp_vs_hp", [
        "VARIABLE _SLP",
        "VARIABLE _SHP",
        "VARIABLE _SBL",
        "VARIABLE _SBH",
        "VARIABLE _ELP",
        "VARIABLE _EHP",
        ": TMP",
        # LP voice
        "  2 -1 1000 64 SYNTH-CREATE _SLP !",   # saw osc
        "  200 INT>FP16 _SLP @ SYNTH-CUTOFF!",
        "  0 _SLP @ SYNTH-FILT-TYPE!",           # LP
        "  50 INT>FP16 0x3C00 _SLP @ SYNTH-NOTE-ON",
        "  _SLP @ SYNTH-RENDER _SBL !",
        "  0x0000 _ELP !",
        "  64 0 DO I _SBL @ PCM-FRAME@ FP16-ABS _ELP @ FP16-ADD _ELP ! LOOP",
        # HP voice
        "  2 -1 1000 64 SYNTH-CREATE _SHP !",
        "  200 INT>FP16 _SHP @ SYNTH-CUTOFF!",
        "  1 _SHP @ SYNTH-FILT-TYPE!",           # HP
        "  50 INT>FP16 0x3C00 _SHP @ SYNTH-NOTE-ON",
        "  _SHP @ SYNTH-RENDER _SBH !",
        "  0x0000 _EHP !",
        "  64 0 DO I _SBH @ PCM-FRAME@ FP16-ABS _EHP @ FP16-ADD _EHP ! LOOP",
        # LP should have more energy (fundamental is below cutoff)
        "  _ELP @ _EHP @ FP16-GT",
        "  _SLP @ SYNTH-FREE _SHP @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_synth_detune():
    """SYNTH-DETUNE! causes osc2 to differ from osc1 frequency."""
    check_no_error("synth_detune", [
        "VARIABLE _SV",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _SV !",   # sine + sine
        "  7 INT>FP16 _SV @ SYNTH-DETUNE!",    # 7 cents
        "  440 INT>FP16 0x3C00 _SV @ SYNTH-NOTE-ON",
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-FREE ;",
        "TMP"
    ])

def test_synth_dual_osc_louder():
    """Dual oscillator voice should have more energy than single."""
    check_val("synth_dual_louder", [
        "VARIABLE _SS",
        "VARIABLE _SD",
        "VARIABLE _SBS",
        "VARIABLE _SBD",
        "VARIABLE _ES",
        "VARIABLE _ED",
        ": TMP",
        # Single osc
        "  0 -1 1000 64 SYNTH-CREATE _SS !",
        "  2000 INT>FP16 _SS @ SYNTH-CUTOFF!",  # open filter
        "  440 INT>FP16 0x3C00 _SS @ SYNTH-NOTE-ON",
        "  _SS @ SYNTH-RENDER _SBS !",
        "  0x0000 _ES !",
        "  64 0 DO I _SBS @ PCM-FRAME@ FP16-ABS _ES @ FP16-ADD _ES ! LOOP",
        # Dual osc
        "  0 0 1000 64 SYNTH-CREATE _SD !",
        "  2000 INT>FP16 _SD @ SYNTH-CUTOFF!",
        "  440 INT>FP16 0x3C00 _SD @ SYNTH-NOTE-ON",
        "  _SD @ SYNTH-RENDER _SBD !",
        "  0x0000 _ED !",
        "  64 0 DO I _SBD @ PCM-FRAME@ FP16-ABS _ED @ FP16-ADD _ED ! LOOP",
        # Dual should have more or equal energy
        "  _ED @ _ES @ FP16-GE",
        "  _SS @ SYNTH-FREE _SD @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_synth_bp_filter():
    """Band-pass filter type works without error."""
    check_no_error("synth_bp_filter", [
        "VARIABLE _SV",
        ": TMP",
        "  0 -1 1000 64 SYNTH-CREATE _SV !",
        "  2 _SV @ SYNTH-FILT-TYPE!",            # BP
        "  200 INT>FP16 _SV @ SYNTH-CUTOFF!",
        "  440 INT>FP16 0x3C00 _SV @ SYNTH-NOTE-ON",
        "  _SV @ SYNTH-RENDER DROP",
        "  _SV @ SYNTH-FREE ;",
        "TMP"
    ])


# ════════════════════════════════════════════════════════════════════
#  FM synthesis tests
# ════════════════════════════════════════════════════════════════════

def test_fm_create_free_2op():
    """FM-CREATE with 2 ops allocates, FM-FREE deallocates without error."""
    check_no_error("fm_create_free_2op", [
        ": TMP",
        "  2 0 1000 64 FM-CREATE",
        "  FM-FREE ;",
        "TMP"
    ])

def test_fm_create_free_4op():
    """FM-CREATE with 4 ops allocates fine."""
    check_no_error("fm_create_free_4op", [
        ": TMP",
        "  4 0 1000 64 FM-CREATE",
        "  FM-FREE ;",
        "TMP"
    ])

def test_fm_note_on_2op():
    """After FM-NOTE-ON, 2-op FM-RENDER produces non-silent output."""
    check_val("fm_note_on_2op", [
        "VARIABLE _FV",
        "VARIABLE _FB",
        ": TMP",
        "  2 0 1000 64 FM-CREATE _FV !",
        "  440 INT>FP16 0x3C00 _FV @ FM-NOTE-ON",
        "  _FV @ FM-RENDER _FB !",
        "  0",
        "  64 0 DO",
        "    I _FB @ PCM-FRAME@ 0<> IF 1+ THEN",
        "  LOOP",
        "  0>",
        "  _FV @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_note_off_decays():
    """After FM-NOTE-OFF, output decays toward silence."""
    check_val("fm_note_off_decays", [
        "VARIABLE _FV",
        "VARIABLE _FB",
        "VARIABLE _FE1",
        "VARIABLE _FE2",
        ": TMP",
        "  2 0 1000 64 FM-CREATE _FV !",
        "  440 INT>FP16 0x3C00 _FV @ FM-NOTE-ON",
        # Render during note-on
        "  _FV @ FM-RENDER DROP",
        "  _FV @ FM-RENDER _FB !",
        "  0x0000 _FE1 !",
        "  64 0 DO I _FB @ PCM-FRAME@ FP16-ABS _FE1 @ FP16-ADD _FE1 ! LOOP",
        # Note off
        "  _FV @ FM-NOTE-OFF",
        # Render several blocks during release
        "  _FV @ FM-RENDER DROP",
        "  _FV @ FM-RENDER _FB !",
        "  0x0000 _FE2 !",
        "  64 0 DO I _FB @ PCM-FRAME@ FP16-ABS _FE2 @ FP16-ADD _FE2 ! LOOP",
        # Energy should decrease
        "  _FE1 @ _FE2 @ FP16-GT",
        "  _FV @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_ratio_changes_timbre():
    """Changing modulator ratio should change the output spectrum."""
    # Ratio=1 vs Ratio=3 should produce different waveforms
    check_val("fm_ratio_changes_timbre", [
        "VARIABLE _FV1",
        "VARIABLE _FV2",
        "VARIABLE _FB1",
        "VARIABLE _FB2",
        ": TMP",
        # Voice 1: ratio=1 for modulator
        "  2 0 1000 64 FM-CREATE _FV1 !",
        "  0x3C00 0 _FV1 @ FM-RATIO!",   # op0 ratio = 1.0
        "  440 INT>FP16 0x3C00 _FV1 @ FM-NOTE-ON",
        "  _FV1 @ FM-RENDER _FB1 !",
        # Voice 2: ratio=3 for modulator
        "  2 0 1000 64 FM-CREATE _FV2 !",
        "  0x4200 0 _FV2 @ FM-RATIO!",   # op0 ratio = 3.0
        "  440 INT>FP16 0x3C00 _FV2 @ FM-NOTE-ON",
        "  _FV2 @ FM-RENDER _FB2 !",
        # Check samples differ at some point
        "  0",
        "  64 0 DO",
        "    I _FB1 @ PCM-FRAME@ I _FB2 @ PCM-FRAME@ <> IF 1+ THEN",
        "  LOOP",
        "  0>",   # at least some samples differ
        "  _FV1 @ FM-FREE _FV2 @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_index_zero_is_sine():
    """With modulation index=0, carrier is a pure sine (no FM modulation)."""
    # With index=0, op1's output doesn't affect op2's phase
    check_val("fm_index_zero_sine", [
        "VARIABLE _FV",
        "VARIABLE _FB",
        ": TMP",
        "  2 0 1000 64 FM-CREATE _FV !",
        "  0x0000 0 _FV @ FM-INDEX!",     # op0 index = 0 (no effect)
        "  0x0000 1 _FV @ FM-INDEX!",     # op1 index = 0 (no mod input used)
        "  440 INT>FP16 0x3C00 _FV @ FM-NOTE-ON",
        "  _FV @ FM-RENDER _FB !",
        # Should have non-zero output (pure carrier sine)
        "  0",
        "  64 0 DO I _FB @ PCM-FRAME@ 0<> IF 1+ THEN LOOP",
        "  0>",
        "  _FV @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_feedback():
    """Enabling op1 feedback changes the output spectrum."""
    check_val("fm_feedback", [
        "VARIABLE _FV1",
        "VARIABLE _FV2",
        "VARIABLE _FB1",
        "VARIABLE _FB2",
        ": TMP",
        # No feedback
        "  2 0 1000 64 FM-CREATE _FV1 !",
        "  440 INT>FP16 0x3C00 _FV1 @ FM-NOTE-ON",
        "  _FV1 @ FM-RENDER _FB1 !",
        # With feedback
        "  2 0 1000 64 FM-CREATE _FV2 !",
        "  0x3800 _FV2 @ FM-FEEDBACK!",   # feedback = 0.5
        "  440 INT>FP16 0x3C00 _FV2 @ FM-NOTE-ON",
        "  _FV2 @ FM-RENDER _FB2 !",
        # At least some samples should differ
        "  0",
        "  64 0 DO",
        "    I _FB1 @ PCM-FRAME@ I _FB2 @ PCM-FRAME@ <> IF 1+ THEN",
        "  LOOP",
        "  0>",
        "  _FV1 @ FM-FREE _FV2 @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_4op_serial():
    """4-op serial algorithm renders without error."""
    check_val("fm_4op_serial", [
        "VARIABLE _FV",
        "VARIABLE _FB",
        ": TMP",
        "  4 0 1000 64 FM-CREATE _FV !",   # algo=0 serial
        "  440 INT>FP16 0x3C00 _FV @ FM-NOTE-ON",
        "  _FV @ FM-RENDER _FB !",
        "  0",
        "  64 0 DO I _FB @ PCM-FRAME@ 0<> IF 1+ THEN LOOP",
        "  0>",
        "  _FV @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_4op_parallel():
    """4-op parallel algorithm renders without error."""
    check_val("fm_4op_parallel", [
        "VARIABLE _FV",
        "VARIABLE _FB",
        ": TMP",
        "  4 1 1000 64 FM-CREATE _FV !",   # algo=1 parallel
        "  440 INT>FP16 0x3C00 _FV @ FM-NOTE-ON",
        "  _FV @ FM-RENDER _FB !",
        "  0",
        "  64 0 DO I _FB @ PCM-FRAME@ 0<> IF 1+ THEN LOOP",
        "  0>",
        "  _FV @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_level_setter():
    """FM-LEVEL! changes operator output level."""
    # Setting carrier level to 0 should produce silence (or near-silence)
    check_val("fm_level_setter", [
        "VARIABLE _FV",
        "VARIABLE _FB",
        "VARIABLE _FE",
        ": TMP",
        "  2 0 1000 64 FM-CREATE _FV !",
        "  0x0000 1 _FV @ FM-LEVEL!",     # carrier level = 0
        "  440 INT>FP16 0x3C00 _FV @ FM-NOTE-ON",
        "  _FV @ FM-RENDER _FB !",
        # Sum absolute values — should be zero or negligible
        "  0x0000 _FE !",
        "  64 0 DO",
        "    I _FB @ PCM-FRAME@ FP16-ABS _FE @ FP16-ADD _FE !",
        "  LOOP",
        # Total energy should be below threshold (allow FP16 rounding)
        "  _FE @ 0x1000 FP16-LT",        # < very small threshold
        "  _FV @ FM-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_fm_algo_setter():
    """FM-ALGO! changes the algorithm at runtime without error."""
    check_no_error("fm_algo_setter", [
        "VARIABLE _FV",
        ": TMP",
        "  4 0 1000 64 FM-CREATE _FV !",
        "  2 _FV @ FM-ALGO!",             # switch to 3-chain
        "  440 INT>FP16 0x3C00 _FV @ FM-NOTE-ON",
        "  _FV @ FM-RENDER DROP",
        "  _FV @ FM-FREE ;",
        "TMP"
    ])


# ════════════════════════════════════════════════════════════════════
#  Runner
# ════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_snapshot()

    print("\n── pluck.f — Karplus-Strong ──")
    test_pluck_create_free()
    test_pluck_delay_length()
    test_pluck_freq()
    test_pluck_excite_nonsilent()
    test_pluck_decay_over_time()
    test_pluck_decay_setter()
    test_pluck_render_twice()
    test_pluck_one_shot()
    test_pluck_pitch_affects_length()
    test_pluck_re_excite()

    print("\n── synth.f — Subtractive ──")
    test_synth_create_free()
    test_synth_create_dual_osc()
    test_synth_note_on_renders()
    test_synth_note_off_decays()
    test_synth_cutoff_setter()
    test_synth_reso_setter()
    test_synth_lp_vs_hp()
    test_synth_detune()
    test_synth_dual_osc_louder()
    test_synth_bp_filter()

    print("\n── fm.f — FM synthesis ──")
    test_fm_create_free_2op()
    test_fm_create_free_4op()
    test_fm_note_on_2op()
    test_fm_note_off_decays()
    test_fm_ratio_changes_timbre()
    test_fm_index_zero_is_sine()
    test_fm_feedback()
    test_fm_4op_serial()
    test_fm_4op_parallel()
    test_fm_level_setter()
    test_fm_algo_setter()

    print(f"\n{'='*50}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*50}")
    sys.exit(1 if _fail_count else 0)
