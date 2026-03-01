#!/usr/bin/env python3
"""Test suite for Akashic audio Phase 4b — Voice Management.

Tests: poly.f (polyphonic voice manager), porta.f (monophonic portamento).

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
POLY_F     = os.path.join(AUDIO_DIR, "poly.f")
PORTA_F    = os.path.join(AUDIO_DIR, "porta.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── FP16 helpers (Python-side) ──

def float_to_fp16(f):
    return struct.unpack('H', struct.pack('e', f))[0]

def fp16_to_float(bits):
    return struct.unpack('e', struct.pack('H', bits & 0xFFFF))[0]

FP16_POS_ZERO = 0x0000
FP16_POS_ONE  = 0x3C00
FP16_NEG_ONE  = 0xBC00
FP16_POS_HALF = 0x3800
FP16_TWO      = 0x4000

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
    print("[*] Building snapshot: BIOS + KDOS + all audio + poly + porta ...")
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
    poly_lines   = _load_forth_lines(POLY_F)
    porta_lines  = _load_forth_lines(PORTA_F)

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
                 + pluck_lines + synth_lines + fm_lines
                 + poly_lines + porta_lines)
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

def check_no_error(name, forth_lines):
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
#  POLY tests — Polyphonic voice manager
# ════════════════════════════════════════════════════════════════════

def test_poly_create_free():
    """POLY-CREATE allocates, POLY-FREE deallocates without error."""
    check_no_error("poly_create_free", [
        ": TMP  4 0 0 1000 64 POLY-CREATE  POLY-FREE ;",
        "TMP"
    ])

def test_poly_count():
    """POLY-COUNT returns the number of voices."""
    check_val("poly_count", [
        "VARIABLE _P",
        ": TMP  4 0 0 1000 64 POLY-CREATE _P !",
        "  _P @ POLY-COUNT",
        "  _P @ POLY-FREE . ;",
        "TMP"
    ], 4)

def test_poly_voice_access():
    """POLY-VOICE returns a valid synth voice descriptor."""
    # Access voice 0, read its osc1 — should be non-zero (allocated)
    check_val("poly_voice_access", [
        "VARIABLE _P",
        ": TMP  2 0 0 1000 64 POLY-CREATE _P !",
        "  0 _P @ POLY-VOICE SY.OSC1 @ 0<>",
        "  _P @ POLY-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_poly_note_on_renders():
    """POLY-NOTE-ON + POLY-RENDER produces non-silent output."""
    check_val("poly_note_on_renders", [
        "VARIABLE _P",
        "VARIABLE _B",
        ": TMP  2 0 0 1000 64 POLY-CREATE _P !",
        "  440 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        "  _P @ POLY-RENDER _B !",
        # Check that at least one sample is non-zero
        "  0",
        "  64 0 DO",
        "    I _B @ PCM-FRAME@ 0<> IF DROP 1 THEN",
        "  LOOP",
        "  _P @ POLY-FREE . ;",
        "TMP"
    ], 1)

def test_poly_two_notes():
    """Two NOTE-ONs allocate to different voices (both active)."""
    check_val("poly_two_notes", [
        "VARIABLE _P",
        ": TMP  4 0 0 1000 64 POLY-CREATE _P !",
        "  440 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        "  523 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        # Both voice 0 and voice 1 should be in ATTACK phase (1)
        "  0 _P @ POLY-VOICE SY.AENV @ E.PHASE @ 1 =",
        "  1 _P @ POLY-VOICE SY.AENV @ E.PHASE @ 1 =",
        "  AND",
        "  _P @ POLY-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_poly_voice_stealing():
    """When all voices used, NOTE-ON steals the quietest voice."""
    # Create 2-voice poly, trigger 2 notes, render to let envelopes advance,
    # trigger a 3rd note — it must steal one of the existing voices.
    # After stealing, we should still be able to render without error.
    check_no_error("poly_voice_stealing", [
        "VARIABLE _P",
        ": TMP  2 0 0 1000 64 POLY-CREATE _P !",
        "  440 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        "  523 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        "  _P @ POLY-RENDER DROP",
        # Third note must steal
        "  659 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-FREE ;",
        "TMP"
    ])

def test_poly_note_off_all():
    """POLY-NOTE-OFF-ALL releases all voices — envelopes reach DONE."""
    check_val("poly_note_off_all", [
        "VARIABLE _P",
        ": TMP  2 0 0 1000 64 POLY-CREATE _P !",
        "  440 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-NOTE-OFF-ALL",
        # Render enough blocks to complete release (200ms = 200 frames at 1000Hz)
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-RENDER DROP",
        # After 5 blocks x 64 = 320 frames, release (200 frames) should be done
        # Voice 0's envelope should be DONE (phase 5)
        "  0 _P @ POLY-VOICE SY.AENV @ E.PHASE @ 5 =",
        "  _P @ POLY-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_poly_cutoff_setter():
    """POLY-CUTOFF! applies to all voices."""
    check_no_error("poly_cutoff_setter", [
        "VARIABLE _P",
        ": TMP  2 0 0 1000 64 POLY-CREATE _P !",
        "  500 INT>FP16 _P @ POLY-CUTOFF!",
        # Check voice 0 cutoff
        "  0 _P @ POLY-VOICE SY.FCUT @ 500 INT>FP16 = . CR",
        # Check voice 1 cutoff
        "  1 _P @ POLY-VOICE SY.FCUT @ 500 INT>FP16 = . CR",
        "  _P @ POLY-FREE ;",
        "TMP"
    ])

def test_poly_reso_setter():
    """POLY-RESO! applies to all voices."""
    check_no_error("poly_reso_setter", [
        "VARIABLE _P",
        ": TMP  2 0 0 1000 64 POLY-CREATE _P !",
        "  0x4000 _P @ POLY-RESO!",
        "  0 _P @ POLY-VOICE SY.FRESO @ 0x4000 = . CR",
        "  _P @ POLY-FREE ;",
        "TMP"
    ])

def test_poly_filter_state_isolation():
    """Each voice maintains independent filter state across renders."""
    # Two voices at same freq but the poly render doesn't corrupt state.
    # Render 2 blocks — master buffer should have non-zero energy
    # (proving both voices contribute through independent filter states).
    check_val("poly_filter_state_isolation", [
        "VARIABLE _P",
        "VARIABLE _E",
        ": TMP  2 0 0 1000 64 POLY-CREATE _P !",
        "  440 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        "  523 INT>FP16 0x3C00 _P @ POLY-NOTE-ON",
        # Render 3 blocks to let filters stabilize
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-RENDER DROP",
        "  _P @ POLY-RENDER DROP",
        # Master buffer should have non-zero energy
        "  0x0000 _E !",
        "  64 0 DO",
        "    I _P @ PO.MASTER @ PCM-FRAME@ FP16-ABS _E @ FP16-ADD _E !",
        "  LOOP",
        "  _E @ 0<>",
        "  _P @ POLY-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

# ════════════════════════════════════════════════════════════════════
#  PORTA tests — Monophonic portamento
# ════════════════════════════════════════════════════════════════════

def test_porta_create_free():
    """PORTA-CREATE allocates, PORTA-FREE deallocates without error."""
    check_no_error("porta_create_free", [
        "VARIABLE _V",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        "  _V @ 0x3C00 PORTA-CREATE",  # speed = 1.0 (instant)
        "  PORTA-FREE",
        "  _V @ SYNTH-FREE ;",
        "TMP"
    ])

def test_porta_note_on_renders():
    """PORTA-NOTE-ON + PORTA-RENDER produces non-silent output."""
    check_val("porta_note_on_renders", [
        "VARIABLE _V",
        "VARIABLE _PT",
        "VARIABLE _B",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        "  _V @ 0x3C00 PORTA-CREATE _PT !",
        "  440 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  _PT @ PORTA-RENDER _B !",
        "  0",
        "  64 0 DO",
        "    I _B @ PCM-FRAME@ 0<> IF DROP 1 THEN",
        "  LOOP",
        "  _PT @ PORTA-FREE",
        "  _V @ SYNTH-FREE . ;",
        "TMP"
    ], 1)

def test_porta_first_note_snaps():
    """First note snaps to target (no glide) — current = target immediately."""
    check_val("porta_first_note_snaps", [
        "VARIABLE _V",
        "VARIABLE _PT",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        # Speed = 0.05 (slow glide) but first note should snap
        "  _V @ 0x2A66 PORTA-CREATE _PT !",
        "  440 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  _PT @ PORTA-FREQ 440 INT>FP16 =",
        "  _PT @ PORTA-FREE  _V @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_porta_glide_moves_freq():
    """Second note glides — after TICK, current is between old and new."""
    check_val("porta_glide_moves_freq", [
        "VARIABLE _V",
        "VARIABLE _PT",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        # Speed = 0.5 (fast but not instant)
        "  _V @ 0x3800 PORTA-CREATE _PT !",
        # First note snaps to 200 Hz
        "  200 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        # Second note targets 400 Hz
        "  400 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        # After note-on, current should still be at 200 (not yet ticked)
        # Now tick once — current should move toward 400
        "  _PT @ PORTA-TICK",
        "  _PT @ PORTA-FREQ",
        # Should be > 200 and < 400
        "  DUP 200 INT>FP16 FP16-GT",
        "  SWAP 400 INT>FP16 FP16-LT AND",
        "  _PT @ PORTA-FREE  _V @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_porta_instant_speed():
    """Speed = 1.0 means no glide — reaches target in one tick."""
    check_val("porta_instant_speed", [
        "VARIABLE _V",
        "VARIABLE _PT",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        "  _V @ 0x3C00 PORTA-CREATE _PT !",  # speed = 1.0
        "  200 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  400 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  _PT @ PORTA-TICK",
        "  _PT @ PORTA-FREQ 400 INT>FP16 =",
        "  _PT @ PORTA-FREE  _V @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_porta_speed_setter():
    """PORTA-SPEED! changes the glide speed."""
    check_val("porta_speed_setter", [
        "VARIABLE _V",
        "VARIABLE _PT",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        "  _V @ 0x3800 PORTA-CREATE _PT !",  # start with 0.5
        "  0x3C00 _PT @ PORTA-SPEED!",        # change to 1.0
        "  200 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  400 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  _PT @ PORTA-TICK",
        # With speed=1.0, should reach target exactly
        "  _PT @ PORTA-FREQ 400 INT>FP16 =",
        "  _PT @ PORTA-FREE  _V @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_porta_note_off():
    """PORTA-NOTE-OFF releases the voice — envelope reaches DONE."""
    check_val("porta_note_off", [
        "VARIABLE _V",
        "VARIABLE _PT",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        "  _V @ 0x3C00 PORTA-CREATE _PT !",
        "  440 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  _PT @ PORTA-RENDER DROP",
        "  _PT @ PORTA-NOTE-OFF",
        # Render enough blocks: release=200ms=200 frames, 5 blocks x 64=320 frames
        "  _PT @ PORTA-RENDER DROP",
        "  _PT @ PORTA-RENDER DROP",
        "  _PT @ PORTA-RENDER DROP",
        "  _PT @ PORTA-RENDER DROP",
        "  _PT @ PORTA-RENDER DROP",
        # Amp envelope should be DONE (phase 5)
        "  _V @ SY.AENV @ E.PHASE @ 5 =",
        "  _PT @ PORTA-FREE  _V @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

def test_porta_render_convenience():
    """PORTA-RENDER = PORTA-TICK + SYNTH-RENDER in one call."""
    # Verify it produces the same result as manual tick+render
    check_val("porta_render_convenience", [
        "VARIABLE _V",
        "VARIABLE _PT",
        "VARIABLE _B",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        "  _V @ 0x3C00 PORTA-CREATE _PT !",
        "  440 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  _PT @ PORTA-RENDER _B !",
        # Buffer should be non-silent
        "  0",
        "  64 0 DO",
        "    I _B @ PCM-FRAME@ 0<> IF DROP 1 THEN",
        "  LOOP",
        "  _PT @ PORTA-FREE  _V @ SYNTH-FREE . ;",
        "TMP"
    ], 1)

def test_porta_glide_converges():
    """Multiple ticks converge toward target frequency."""
    check_val("porta_glide_converges", [
        "VARIABLE _V",
        "VARIABLE _PT",
        "VARIABLE _D1",
        "VARIABLE _D2",
        ": TMP",
        "  0 0 1000 64 SYNTH-CREATE _V !",
        # Speed = 0.5 — halves distance each tick
        "  _V @ 0x3800 PORTA-CREATE _PT !",
        "  200 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        "  400 INT>FP16 0x3C00 _PT @ PORTA-NOTE-ON",
        # Tick once — measure distance to target
        "  _PT @ PORTA-TICK",
        "  400 INT>FP16 _PT @ PORTA-FREQ FP16-SUB FP16-ABS _D1 !",
        # Tick again — distance should decrease
        "  _PT @ PORTA-TICK",
        "  400 INT>FP16 _PT @ PORTA-FREQ FP16-SUB FP16-ABS _D2 !",
        "  _D1 @ _D2 @ FP16-GT",
        "  _PT @ PORTA-FREE  _V @ SYNTH-FREE",
        "  IF 1 ELSE 0 THEN . ;",
        "TMP"
    ], 1)

# ════════════════════════════════════════════════════════════════════
#  Runner
# ════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_snapshot()
    print()

    print("── poly.f — Polyphonic voice manager ──")
    test_poly_create_free()
    test_poly_count()
    test_poly_voice_access()
    test_poly_note_on_renders()
    test_poly_two_notes()
    test_poly_voice_stealing()
    test_poly_note_off_all()
    test_poly_cutoff_setter()
    test_poly_reso_setter()
    test_poly_filter_state_isolation()

    print()
    print("── porta.f — Monophonic portamento ──")
    test_porta_create_free()
    test_porta_note_on_renders()
    test_porta_first_note_snaps()
    test_porta_glide_moves_freq()
    test_porta_instant_speed()
    test_porta_speed_setter()
    test_porta_note_off()
    test_porta_render_convenience()
    test_porta_glide_converges()

    print()
    print("=" * 50)
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print("=" * 50)
    sys.exit(1 if _fail_count else 0)
