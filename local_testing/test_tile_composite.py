#!/usr/bin/env python3
"""Test suite for tile-accelerated glyph compositing (draw.f tile path).

Verifies that the U16-mode tile blend in DRAW-GLYPH produces correct
sRGB-blended pixels for various coverage patterns.  Compares tile
path output against the reference scalar _DRAW-GL-BLEND.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
MATH_DIR   = os.path.join(ROOT_DIR, "akashic", "math")
RENDER_DIR = os.path.join(ROOT_DIR, "akashic", "render")
FONT_DIR   = os.path.join(ROOT_DIR, "akashic", "font")
TEXT_DIR   = os.path.join(ROOT_DIR, "akashic", "text")

# Full dependency chain for draw.f (topological order)
DEPS = [
    os.path.join(MATH_DIR,   "fp16.f"),
    os.path.join(MATH_DIR,   "fp16-ext.f"),
    os.path.join(MATH_DIR,   "exp.f"),
    os.path.join(TEXT_DIR,    "utf8.f"),
    os.path.join(FONT_DIR,   "ttf.f"),
    os.path.join(MATH_DIR,   "simd.f"),
    os.path.join(MATH_DIR,   "bezier.f"),
    os.path.join(MATH_DIR,   "color.f"),
    os.path.join(RENDER_DIR, "surface.f"),
    os.path.join(FONT_DIR,   "raster.f"),
    os.path.join(FONT_DIR,   "cache.f"),
    os.path.join(TEXT_DIR,    "layout.f"),
    os.path.join(RENDER_DIR, "draw.f"),
]

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
    print("[*] Building snapshot: BIOS + KDOS + full draw.f chain ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for dep_path in DEPS:
        dep_lines += _load_forth_lines(dep_path)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 900_000_000
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
    err = False
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            print(f"  [!] {l}")
            err = True
    if err:
        print("[!] Some words not found during snapshot build.")
        print("    Last output lines:")
        for l in text.strip().split('\n')[-10:]:
            print(f"    {l}")
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

# ── Reference blending (Python) ──

def _build_luts():
    """Build matching sRGB LUTs to compare against Forth."""
    s2l = [0] * 256
    l2s = [0] * 256
    for i in range(256):
        s2l[i] = min(255, i * i // 270)    # sRGB→linear (γ≈2.1)
    for i in range(256):
        l2s[i] = min(255, _isqrt(i * 255))  # linear→sRGB
    return s2l, l2s

def _isqrt(n):
    if n < 1: return n
    g = n
    while True:
        ng = (n // g + g) // 2
        if ng >= g:
            return g
        g = ng

S2L, L2S = _build_luts()

def ref_blend_channel(fg_ch, bg_ch, cov):
    """Reference scalar blend matching _DRAW-GL-BLEND."""
    fg_lin = S2L[fg_ch]
    bg_lin = S2L[bg_ch]
    blended_lin = (fg_lin * cov + bg_lin * (255 - cov)) // 255
    return L2S[min(255, blended_lin)]

def ref_blend_tile_channel(fg_ch, bg_ch, cov):
    """Reference tile blend: (fg_lin*cov + bg_lin*(255-cov) + 128) >> 8."""
    fg_lin = S2L[fg_ch]
    bg_lin = S2L[bg_ch]
    num = fg_lin * cov + bg_lin * (255 - cov) + 128
    blended_lin = (num >> 8) & 0xFF
    return L2S[min(255, blended_lin)]

# ── Test framework ──

_pass_count = 0
_fail_count = 0

def _extract_result_numbers(full_output):
    """Extract result numbers from Forth output, ignoring echoed input.

    Only collect numbers from lines containing ' ok' (Forth result lines).
    """
    nums = []
    for line in full_output.strip().split('\n'):
        if 'ok' not in line:
            continue
        cleaned = line.replace('ok', '').replace('>', '').strip()
        for tok in cleaned.split():
            try:
                nums.append(int(tok))
            except ValueError:
                pass
    return nums

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

def check_fn(name, forth_lines, validate_fn):
    """Run Forth, pass output to validate_fn."""
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    lines = [l for l in clean.split('\n') if l.strip()]
    last = lines[-1].strip() if lines else ""
    if validate_fn(last, clean):
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

# =====================================================================
#  Test: sRGB LUT initialization
# =====================================================================

def test_srgb_lut_s2l():
    """Verify _DRAW-S2L LUT matches Python reference."""
    # Sample a few values
    for i in [0, 50, 128, 200, 255]:
        check(f"S2L[{i}]", [f'{i} _DRAW-S2L + C@ .'], str(S2L[i]))

def test_srgb_lut_l2s():
    """Verify _DRAW-L2S LUT matches Python reference."""
    for i in [0, 30, 60, 120, 200]:
        check(f"L2S[{i}]", [f'{i} _DRAW-L2S + C@ .'], str(L2S[i]))

# =====================================================================
#  Test: scalar _DRAW-GL-BLEND (reference path — still used by fallback)
# =====================================================================

def test_scalar_blend():
    """Verify _DRAW-GL-BLEND produces correct output for known inputs."""
    # fg=200 (R channel), bg=50, cov=128 (half coverage)
    fg, bg, cov = 200, 50, 128
    expected = ref_blend_channel(fg, bg, cov)
    check("scalar _DRAW-GL-BLEND", [
        f'{fg} {bg} {cov} _DRAW-GL-BLEND .'
    ], str(expected))

# =====================================================================
#  Test: tile blend helpers (unit tests of internal words)
# =====================================================================

def test_tile_blend_known():
    """End-to-end tile blend: set up tiles manually, blend, read result."""
    # Test: fg_lin=100, bg_lin=20, cov=200 (out of 255)
    # Expected: (100*200 + 20*55 + 128) >> 8 = (20000+1100+128)>>8 = 21228>>8 = 82
    # Then delinearize: L2S[82]
    fg_lin = 100
    bg_lin = 20
    cov    = 200
    icov   = 255 - cov
    num    = fg_lin * cov + bg_lin * icov + 128
    result_lin = (num >> 8) & 0xFF
    result_srgb = L2S[result_lin]

    lines = [
        # Set up tiles directly
        'U16-MODE',
        # Write coverage=200 into lane 0 of T_COV (_SIMD-S0)
        f'{cov} _SIMD-S0 @ W!',
        # Compute icov tile: fill S6 with 255, SUB
        f'_SIMD-S6 @ 255 TILE-FILL-U16',
        f'_SIMD-S6 @ _SIMD-S0 @ _SIMD-S1 @ TILE-SUB',
        # Set up rounding constant
        f'_SIMD-S6 @ 128 TILE-FILL-U16',
        # Write bg_lin=20 into lane 0 of T_BGR (_SIMD-S2)
        f'{bg_lin} _SIMD-S2 @ W!',
        # Blend R channel
        f'{fg_lin} _SIMD-S2 @ _DRAW-TB-BLEND-CH',
        # Read high byte of lane 0 from T_WORK (_SIMD-S7)
        '_SIMD-S7 @ 1+ C@ .',
    ]
    check("tile blend known values (raw)", lines, str(result_lin))

def test_tile_blend_delinearize():
    """After blend + delinearize, result matches reference."""
    fg_lin = 100
    bg_lin = 20
    cov    = 200
    num    = fg_lin * cov + bg_lin * (255 - cov) + 128
    result_lin = (num >> 8) & 0xFF
    result_srgb = L2S[result_lin]

    lines = [
        'U16-MODE',
        f'{cov} _SIMD-S0 @ W!',
        f'_SIMD-S6 @ 255 TILE-FILL-U16',
        f'_SIMD-S6 @ _SIMD-S0 @ _SIMD-S1 @ TILE-SUB',
        f'_SIMD-S6 @ 128 TILE-FILL-U16',
        f'{bg_lin} _SIMD-S2 @ W!',
        f'{fg_lin} _SIMD-S2 @ _DRAW-TB-BLEND-CH',
        # Delinearize: read high byte, look up in L2S
        '_SIMD-S7 @ 1+ C@ _DRAW-L2S + C@ .',
    ]
    check("tile blend + delinearize", lines, str(result_srgb))

# =====================================================================
#  Test: full DRAW-GLYPH tile path via synthetic surface + bitmap
# =====================================================================

def _make_surface_and_glyph(width, height, bg_rgba, cov_bytes):
    """Generate Forth code to create a surface and fake glyph bitmap.

    Returns (setup_lines, gw, gh).
    We bypass GC-GET by faking a glyph bitmap directly.
    """
    lines = []
    # Create surface (VARIABLE must be on its own line in KDOS)
    lines.append('VARIABLE _TEST-SURF')
    lines.append(f'{width} {height} SURF-CREATE _TEST-SURF !')
    # Fill surface with background color
    lines.append(f'_TEST-SURF @ 0x{bg_rgba:08X} SURF-CLEAR')
    # Create glyph bitmap (coverage bytes)
    gw = len(cov_bytes[0]) if cov_bytes else 0
    gh = len(cov_bytes)
    total = gw * gh
    lines.append('VARIABLE _TEST-BMP')
    lines.append(f'HERE {total} ALLOT _TEST-BMP !')
    # Write coverage data
    for row_idx, row in enumerate(cov_bytes):
        for col_idx, c in enumerate(row):
            offset = row_idx * gw + col_idx
            lines.append(f'{c} _TEST-BMP @ {offset} + C!')
    return lines, gw, gh

def test_draw_glyph_full_coverage():
    """Pixel with cov=255 should be foreground color exactly."""
    bg_rgba = 0x8080_80FF   # grey background with A=255
    fg_rgba = 0xFF00_00FF   # red foreground
    cov = [[255]]           # single pixel, full coverage
    setup, gw, gh = _make_surface_and_glyph(10, 10, bg_rgba, cov)

    lines = setup + [
        # Directly set up the variables that DRAW-GLYPH expects
        f'0x{fg_rgba:08X} _DRAW-RGBA !',
        f'3 _DRAW-GL-X !  3 _DRAW-GL-Y !',
        f'_TEST-SURF @ _DRAW-SURF !',
        f'_TEST-BMP @ _DRAW-GL-BMP !',
        f'{gw} _DRAW-GL-W !  {gh} _DRAW-GL-H !',
        # Extract & pre-linearize fg
        f'_DRAW-RGBA @ 24 RSHIFT 255 AND _DRAW-GL-FR !',
        f'_DRAW-RGBA @ 16 RSHIFT 255 AND _DRAW-GL-FG !',
        f'_DRAW-RGBA @  8 RSHIFT 255 AND _DRAW-GL-FB !',
        f'_DRAW-GL-FR @ _DRAW-S2L + C@ _DRAW-TB-FGR !',
        f'_DRAW-GL-FG @ _DRAW-S2L + C@ _DRAW-TB-FGG !',
        f'_DRAW-GL-FB @ _DRAW-S2L + C@ _DRAW-TB-FGB !',
        f'{gw} _DRAW-TB-N !',
        # Run tile row
        '0 _DRAW-TB-ROW',
        # Read back pixel at (3, 3)
        '_TEST-SURF @ 3 3 SURF-PIXEL@ .',
    ]
    check("full coverage → fg color", lines, str(fg_rgba))

def test_draw_glyph_zero_coverage():
    """Pixel with cov=0 should remain background color."""
    bg_rgba = 0x4080_C0FF
    fg_rgba = 0xFF00_00FF
    cov = [[0]]
    setup, gw, gh = _make_surface_and_glyph(10, 10, bg_rgba, cov)

    lines = setup + [
        f'0x{fg_rgba:08X} _DRAW-RGBA !',
        f'3 _DRAW-GL-X !  3 _DRAW-GL-Y !',
        f'_TEST-SURF @ _DRAW-SURF !',
        f'_TEST-BMP @ _DRAW-GL-BMP !',
        f'{gw} _DRAW-GL-W !  {gh} _DRAW-GL-H !',
        f'_DRAW-RGBA @ 24 RSHIFT 255 AND _DRAW-GL-FR !',
        f'_DRAW-RGBA @ 16 RSHIFT 255 AND _DRAW-GL-FG !',
        f'_DRAW-RGBA @  8 RSHIFT 255 AND _DRAW-GL-FB !',
        f'_DRAW-GL-FR @ _DRAW-S2L + C@ _DRAW-TB-FGR !',
        f'_DRAW-GL-FG @ _DRAW-S2L + C@ _DRAW-TB-FGG !',
        f'_DRAW-GL-FB @ _DRAW-S2L + C@ _DRAW-TB-FGB !',
        f'{gw} _DRAW-TB-N !',
        '0 _DRAW-TB-ROW',
        '_TEST-SURF @ 3 3 SURF-PIXEL@ .',
    ]
    check("zero coverage → bg unchanged", lines, str(bg_rgba))

def test_draw_glyph_partial_coverage():
    """Partial coverage blend matches reference (within ±1 for rounding)."""
    bg_rgba = 0x4060_80FF   # bg: R=64, G=96, B=128
    fg_rgba = 0xE0C0_A0FF   # fg: R=224, G=192, B=160
    cov_val = 128
    cov = [[cov_val]]
    setup, gw, gh = _make_surface_and_glyph(10, 10, bg_rgba, cov)

    # Compute expected per-channel using tile formula
    bg_r, bg_g, bg_b = 0x40, 0x60, 0x80
    fg_r, fg_g, fg_b = 0xE0, 0xC0, 0xA0
    exp_r = ref_blend_tile_channel(fg_r, bg_r, cov_val)
    exp_g = ref_blend_tile_channel(fg_g, bg_g, cov_val)
    exp_b = ref_blend_tile_channel(fg_b, bg_b, cov_val)
    exp_rgba = (exp_r << 24) | (exp_g << 16) | (exp_b << 8) | 0xFF

    lines = setup + [
        f'0x{fg_rgba:08X} _DRAW-RGBA !',
        f'3 _DRAW-GL-X !  3 _DRAW-GL-Y !',
        f'_TEST-SURF @ _DRAW-SURF !',
        f'_TEST-BMP @ _DRAW-GL-BMP !',
        f'{gw} _DRAW-GL-W !  {gh} _DRAW-GL-H !',
        f'_DRAW-RGBA @ 24 RSHIFT 255 AND _DRAW-GL-FR !',
        f'_DRAW-RGBA @ 16 RSHIFT 255 AND _DRAW-GL-FG !',
        f'_DRAW-RGBA @  8 RSHIFT 255 AND _DRAW-GL-FB !',
        f'_DRAW-GL-FR @ _DRAW-S2L + C@ _DRAW-TB-FGR !',
        f'_DRAW-GL-FG @ _DRAW-S2L + C@ _DRAW-TB-FGG !',
        f'_DRAW-GL-FB @ _DRAW-S2L + C@ _DRAW-TB-FGB !',
        f'{gw} _DRAW-TB-N !',
        '0 _DRAW-TB-ROW',
        '_TEST-SURF @ 3 3 SURF-PIXEL@ .',
    ]
    def validate(last, full):
        nums = _extract_result_numbers(full)
        if not nums:
            print(f"        No numeric results found")
            return False
        actual = nums[-1]  # Last result number
        # Allow ±1 per channel for rounding differences
        for shift in [24, 16, 8, 0]:
            a_ch = (actual >> shift) & 0xFF
            e_ch = (exp_rgba >> shift) & 0xFF
            if abs(a_ch - e_ch) > 1:
                print(f"        channel at bit {shift}: got {a_ch}, expected {e_ch}")
                return False
        return True

    check_fn(f"partial coverage ({cov_val}/255) blend", lines, validate)

def test_draw_glyph_multi_pixel_row():
    """A row of 8 pixels with varying coverage values."""
    bg_rgba = 0x0000_00FF    # black background
    fg_rgba = 0xFFFF_FFFF    # white foreground
    coverages = [0, 64, 128, 192, 255, 50, 200, 0]
    cov = [coverages]
    setup, gw, gh = _make_surface_and_glyph(20, 10, bg_rgba, cov)

    # Compute expected values for each pixel
    expected_pixels = []
    for c in coverages:
        if c == 0:
            expected_pixels.append(bg_rgba)
        elif c == 255:
            expected_pixels.append(fg_rgba)
        else:
            er = ref_blend_tile_channel(0xFF, 0x00, c)
            eg = ref_blend_tile_channel(0xFF, 0x00, c)
            eb = ref_blend_tile_channel(0xFF, 0x00, c)
            expected_pixels.append((er << 24) | (eg << 16) | (eb << 8) | 0xFF)

    lines = setup + [
        f'0x{fg_rgba:08X} _DRAW-RGBA !',
        f'2 _DRAW-GL-X !  2 _DRAW-GL-Y !',
        f'_TEST-SURF @ _DRAW-SURF !',
        f'_TEST-BMP @ _DRAW-GL-BMP !',
        f'{gw} _DRAW-GL-W !  {gh} _DRAW-GL-H !',
        f'_DRAW-RGBA @ 24 RSHIFT 255 AND _DRAW-GL-FR !',
        f'_DRAW-RGBA @ 16 RSHIFT 255 AND _DRAW-GL-FG !',
        f'_DRAW-RGBA @  8 RSHIFT 255 AND _DRAW-GL-FB !',
        f'_DRAW-GL-FR @ _DRAW-S2L + C@ _DRAW-TB-FGR !',
        f'_DRAW-GL-FG @ _DRAW-S2L + C@ _DRAW-TB-FGG !',
        f'_DRAW-GL-FB @ _DRAW-S2L + C@ _DRAW-TB-FGB !',
        f'{gw} _DRAW-TB-N !',
        '0 _DRAW-TB-ROW',
    ]
    # Read back each pixel
    for i in range(len(coverages)):
        lines.append(f'_TEST-SURF @ {2 + i} 2 SURF-PIXEL@ .')
    expected_str = " ".join(str(p) for p in expected_pixels)

    def validate(last, full):
        # Get all result values from 'ok' lines only
        actual_pixels = _extract_result_numbers(full)
        if len(actual_pixels) < len(coverages):
            print(f"        Only got {len(actual_pixels)} values, expected {len(coverages)}")
            return False
        # Take the last N values
        actual_pixels = actual_pixels[-len(coverages):]
        ok = True
        for idx, (act, exp) in enumerate(zip(actual_pixels, expected_pixels)):
            for shift in [24, 16, 8, 0]:
                a_ch = (act >> shift) & 0xFF
                e_ch = (exp >> shift) & 0xFF
                if abs(a_ch - e_ch) > 1:
                    print(f"        pixel {idx} ch@{shift}: got {a_ch}, expected {e_ch}")
                    ok = False
        return ok

    check_fn("multi-pixel row (8 px varying coverage)", lines, validate)

def test_draw_glyph_multirow():
    """Test 2 rows with different coverage patterns."""
    bg_rgba = 0x2040_60FF
    fg_rgba = 0xC0A0_80FF
    cov = [
        [0, 128, 255, 0],
        [255, 0, 128, 64],
    ]
    setup, gw, gh = _make_surface_and_glyph(20, 10, bg_rgba, cov)

    lines = setup + [
        f'0x{fg_rgba:08X} _DRAW-RGBA !',
        f'1 _DRAW-GL-X !  1 _DRAW-GL-Y !',
        f'_TEST-SURF @ _DRAW-SURF !',
        f'_TEST-BMP @ _DRAW-GL-BMP !',
        f'{gw} _DRAW-GL-W !  {gh} _DRAW-GL-H !',
        f'_DRAW-RGBA @ 24 RSHIFT 255 AND _DRAW-GL-FR !',
        f'_DRAW-RGBA @ 16 RSHIFT 255 AND _DRAW-GL-FG !',
        f'_DRAW-RGBA @  8 RSHIFT 255 AND _DRAW-GL-FB !',
        f'_DRAW-GL-FR @ _DRAW-S2L + C@ _DRAW-TB-FGR !',
        f'_DRAW-GL-FG @ _DRAW-S2L + C@ _DRAW-TB-FGG !',
        f'_DRAW-GL-FB @ _DRAW-S2L + C@ _DRAW-TB-FGB !',
        f'{gw} _DRAW-TB-N !',
        '0 _DRAW-TB-ROW',
        '1 _DRAW-TB-ROW',
    ]
    # Read back all pixels from both rows
    for row in range(2):
        for col in range(gw):
            lines.append(f'_TEST-SURF @ {1 + col} {1 + row} SURF-PIXEL@ .')

    fg_r, fg_g, fg_b = 0xC0, 0xA0, 0x80
    bg_r, bg_g, bg_b = 0x20, 0x40, 0x60

    def compute_expected(c):
        if c == 0: return bg_rgba
        if c == 255: return fg_rgba
        er = ref_blend_tile_channel(fg_r, bg_r, c)
        eg = ref_blend_tile_channel(fg_g, bg_g, c)
        eb = ref_blend_tile_channel(fg_b, bg_b, c)
        return (er << 24) | (eg << 16) | (eb << 8) | 0xFF

    expected = []
    for row in cov:
        for c in row:
            expected.append(compute_expected(c))

    def validate(last, full):
        actual = _extract_result_numbers(full)
        if len(actual) < len(expected):
            print(f"        Only got {len(actual)} values, expected {len(expected)}")
            return False
        actual = actual[-len(expected):]
        ok = True
        for idx, (act, exp) in enumerate(zip(actual, expected)):
            for shift in [24, 16, 8, 0]:
                a_ch = (act >> shift) & 0xFF
                e_ch = (exp >> shift) & 0xFF
                if abs(a_ch - e_ch) > 1:
                    row = idx // gw
                    col = idx % gw
                    print(f"        pixel ({col},{row}) ch@{shift}: got {a_ch}, expected {e_ch}")
                    ok = False
        return ok

    check_fn("multi-row blend (2×4 coverage grid)", lines, validate)

def test_scalar_vs_tile_agreement():
    """Verify tile path matches scalar _DRAW-GL-BLEND within ±1."""
    # Test several fg/bg/cov combos, one at a time
    combos = [
        (200, 50, 128),
        (0, 255, 1),
        (128, 128, 128),
        (255, 0, 200),
        (100, 200, 50),
    ]
    all_ok = True
    for fg, bg, cov in combos:
        fg_lin = S2L[fg]
        bg_lin = S2L[bg]
        # Run scalar
        scalar_lines = [f'{fg} {bg} {cov} _DRAW-GL-BLEND .']
        scalar_out = run_forth(scalar_lines).strip()
        # Find the result: last number before "ok" or at end
        scalar_val = None
        for line in scalar_out.split('\n'):
            toks = line.replace('ok', '').strip().split()
            for t in toks:
                try:
                    scalar_val = int(t)
                except ValueError:
                    pass

        # Run tile
        tile_lines = [
            'U16-MODE',
            '_SIMD-S0 @ TILE-ZERO',
            '_SIMD-S2 @ TILE-ZERO',
            f'{cov} _SIMD-S0 @ W!',
            '_SIMD-S6 @ 255 TILE-FILL-U16',
            '_SIMD-S6 @ _SIMD-S0 @ _SIMD-S1 @ TILE-SUB',
            '_SIMD-S6 @ 128 TILE-FILL-U16',
            f'{bg_lin} _SIMD-S2 @ W!',
            f'{fg_lin} _SIMD-S2 @ _DRAW-TB-BLEND-CH',
            '_SIMD-S7 @ 1+ C@ _DRAW-L2S + C@ .',
        ]
        tile_out = run_forth(tile_lines).strip()
        tile_val = None
        for line in tile_out.split('\n'):
            toks = line.replace('ok', '').strip().split()
            for t in toks:
                try:
                    tile_val = int(t)
                except ValueError:
                    pass

        if scalar_val is not None and tile_val is not None:
            if abs(scalar_val - tile_val) > 1:
                print(f"  FAIL  scalar vs tile ({fg},{bg},{cov}): s={scalar_val} t={tile_val}")
                all_ok = False
        else:
            print(f"  FAIL  scalar vs tile ({fg},{bg},{cov}): parse error")
            all_ok = False

    global _pass_count, _fail_count
    if all_ok:
        _pass_count += 1
        print(f"  PASS  scalar vs tile agreement (5 combos)")
    else:
        _fail_count += 1

def test_surface_intact_outside_glyph():
    """Pixels outside the glyph area should be untouched."""
    bg_rgba = 0xDEAD_BEFF
    fg_rgba = 0x1234_56FF
    cov = [[128]]
    setup, gw, gh = _make_surface_and_glyph(10, 10, bg_rgba, cov)

    lines = setup + [
        f'0x{fg_rgba:08X} _DRAW-RGBA !',
        f'5 _DRAW-GL-X !  5 _DRAW-GL-Y !',
        f'_TEST-SURF @ _DRAW-SURF !',
        f'_TEST-BMP @ _DRAW-GL-BMP !',
        f'{gw} _DRAW-GL-W !  {gh} _DRAW-GL-H !',
        f'_DRAW-RGBA @ 24 RSHIFT 255 AND _DRAW-GL-FR !',
        f'_DRAW-RGBA @ 16 RSHIFT 255 AND _DRAW-GL-FG !',
        f'_DRAW-RGBA @  8 RSHIFT 255 AND _DRAW-GL-FB !',
        f'_DRAW-GL-FR @ _DRAW-S2L + C@ _DRAW-TB-FGR !',
        f'_DRAW-GL-FG @ _DRAW-S2L + C@ _DRAW-TB-FGG !',
        f'_DRAW-GL-FB @ _DRAW-S2L + C@ _DRAW-TB-FGB !',
        f'{gw} _DRAW-TB-N !',
        '0 _DRAW-TB-ROW',
        # Read a pixel far from glyph — should be untouched bg
        '_TEST-SURF @ 0 0 SURF-PIXEL@ .',
        '_TEST-SURF @ 9 9 SURF-PIXEL@ .',
    ]
    def validate(last, full):
        nums = _extract_result_numbers(full)
        if len(nums) < 2:
            print(f"        Expected 2 values, got {len(nums)}")
            return False
        return nums[-2] == bg_rgba and nums[-1] == bg_rgba

    check_fn("surface intact outside glyph", lines, validate)

# =====================================================================
#  Main
# =====================================================================

if __name__ == '__main__':
    build_snapshot()

    print("\n── sRGB LUT tests ──")
    test_srgb_lut_s2l()
    test_srgb_lut_l2s()

    print("\n── Scalar blend reference ──")
    test_scalar_blend()

    print("\n── Tile blend unit tests ──")
    test_tile_blend_known()
    test_tile_blend_delinearize()

    print("\n── Full tile glyph path ──")
    test_draw_glyph_full_coverage()
    test_draw_glyph_zero_coverage()
    test_draw_glyph_partial_coverage()
    test_draw_glyph_multi_pixel_row()
    test_draw_glyph_multirow()

    print("\n── Cross-validation ──")
    test_scalar_vs_tile_agreement()
    test_surface_intact_outside_glyph()

    print(f"\n{'='*50}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    if _fail_count:
        sys.exit(1)
    print("  All tests passed!")
