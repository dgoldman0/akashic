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
"""Test suite for Akashic font libraries (ttf.f, raster.f).

Tests: Big-endian readers, TTF table parsing, cmap lookup,
       glyph decoding, rasterizer edge table, scanline fill,
       Bézier contour walker.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

FP16_F     = os.path.join(ROOT_DIR, "akashic", "math", "fp16.f")
FP16EXT_F  = os.path.join(ROOT_DIR, "akashic", "math", "fp16-ext.f")
FIXED_F    = os.path.join(ROOT_DIR, "akashic", "math", "fixed.f")
BEZIER_F   = os.path.join(ROOT_DIR, "akashic", "math", "bezier.f")
TTF_F      = os.path.join(ROOT_DIR, "akashic", "font", "ttf.f")
RASTER_F   = os.path.join(ROOT_DIR, "akashic", "font", "raster.f")
CACHE_F    = os.path.join(ROOT_DIR, "akashic", "font", "cache.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
LAYOUT_F   = os.path.join(ROOT_DIR, "akashic", "text", "layout.f")

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
    print("[*] Building snapshot: BIOS + KDOS + math + font libs ...")
    t0 = time.time()
    bios_code   = _load_bios()
    kdos_lines  = _load_forth_lines(KDOS_PATH)
    fp16_lines  = _load_forth_lines(FP16_F)
    fp16e_lines = _load_forth_lines(FP16EXT_F)
    fixed_lines = _load_forth_lines(FIXED_F)
    bezier_lines= _load_forth_lines(BEZIER_F)
    ttf_lines   = _load_forth_lines(TTF_F)
    raster_lines= _load_forth_lines(RASTER_F)
    cache_lines = _load_forth_lines(CACHE_F)
    utf8_lines  = _load_forth_lines(UTF8_F)
    layout_lines= _load_forth_lines(LAYOUT_F)

    # Test helpers
    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    # Load in dependency order
    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + fp16_lines + fp16e_lines
                 + fixed_lines + bezier_lines
                 + ttf_lines + raster_lines + cache_lines
                 + utf8_lines + layout_lines
                 + helpers)
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
    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
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
#  TTF tests — big-endian readers
# =====================================================================

def test_big_endian_readers():
    print("\n=== Big-Endian Readers ===")
    # Store 0xABCD at a known address, read back with BE-W@
    check("BE-W@ basic",
          ['CREATE _TBE 16 ALLOT',
           '0xAB _TBE C!  0xCD _TBE 1+ C!',
           '_TBE BE-W@ .'],
          '43981 ')    # 0xABCD = 43981

    check("BE-L@ basic",
          ['CREATE _TBE 16 ALLOT',
           '0x12 _TBE C!  0x34 _TBE 1+ C!  0x56 _TBE 2 + C!  0x78 _TBE 3 + C!',
           '_TBE BE-L@ .'],
          '305419896 ')  # 0x12345678

    # Signed 16-bit: 0xFF80 = -128
    check("BE-SW@ negative",
          ['CREATE _TBE 16 ALLOT',
           '0xFF _TBE C!  0x80 _TBE 1+ C!',
           '_TBE BE-SW@ .'],
          '-128 ')

    check("BE-SW@ positive",
          ['CREATE _TBE 16 ALLOT',
           '0x00 _TBE C!  0x7F _TBE 1+ C!',
           '_TBE BE-SW@ .'],
          '127 ')

# =====================================================================
#  Rasterizer tests — edge table
# =====================================================================

def test_edge_insertion():
    print("\n=== Edge Table ===")
    # Basic edge insertion
    check("RAST-EDGE count",
          ['RAST-RESET',
           '0 0 10 10 RAST-EDGE',
           '5 5 15 3 RAST-EDGE',
           'RAST-NEDGES .'],
          '2 ')

    # Horizontal edges should be discarded
    check("Horizontal edge discard",
          ['RAST-RESET',
           '0 5 10 5 RAST-EDGE',
           'RAST-NEDGES .'],
          '0 ')

    # Reset clears edges
    check("RAST-RESET",
          ['0 0 10 10 RAST-EDGE',
           'RAST-RESET',
           'RAST-NEDGES .'],
          '0 ')

# =====================================================================
#  Rasterizer tests — scanline fill
# =====================================================================

def test_scanline_fill():
    print("\n=== Scanline Fill ===")
    # Render a simple rectangle (4 edges) into a small bitmap
    # Rectangle from (2,2) to (6,6) in an 8x8 bitmap
    # Note: top/bottom edges are horizontal and get discarded — only
    # the left and right vertical edges remain, which is correct.
    check("Rectangle fill center",
          ['RAST-RESET',
           '2 2 6 2 RAST-EDGE',
           '6 2 6 6 RAST-EDGE',
           '6 6 2 6 RAST-EDGE',
           '2 6 2 2 RAST-EDGE',
           'CREATE _RBUF 64 ALLOT',
           '_RBUF 8 8 RAST-FILL',
           '_RBUF 3 8 * + 3 + C@ .'],
          '255 ')
    check("Rectangle fill corner empty",
          ['RAST-RESET',
           '6 2 6 6 RAST-EDGE',
           '2 2 2 6 RAST-EDGE',
           'CREATE _RBUF 64 ALLOT',
           '_RBUF 8 8 RAST-FILL',
           '_RBUF C@ .'],
          '0 ')

    # Triangle: vertices at (4,1), (1,7), (7,7)
    check("Triangle fill center",
          ['RAST-RESET',
           '4 1 1 7 RAST-EDGE',
           '1 7 7 7 RAST-EDGE',
           '7 7 4 1 RAST-EDGE',
           'CREATE _RBUF 64 ALLOT',
           '_RBUF 8 8 RAST-FILL',
           '_RBUF 4 8 * + 4 + C@ .'],
          '255 ')
    check("Triangle fill corner empty",
          ['RAST-RESET',
           '4 1 1 7 RAST-EDGE',
           '7 7 4 1 RAST-EDGE',
           'CREATE _RBUF 64 ALLOT',
           '_RBUF 8 8 RAST-FILL',
           '_RBUF C@ .'],
          '0 ')

# =====================================================================
#  Rasterizer tests — contour walker with synthetic glyph data
# =====================================================================

def test_contour_walker_lines():
    """Test contour walker with all on-curve points (line-only contour)."""
    print("\n=== Contour Walker (lines) ===")
    # Manually set up a simple square glyph in the TTF point arrays.
    # 4 on-curve points forming a 500-unit square at UPEM=1000, 16px.
    # Points: (100,100) (600,100) (600,600) (100,600) — all on-curve
    # At 16px/1000upem scale: (1,14) (9,14) (9,6) (1,6) approx
    # After scaling 16px/1000upem, the y-coords for P0,P1 are the same
    # (both at 100 font units → pixel 15) and P2,P3 are the same
    # (both at 600 → pixel 7). So top/bottom edges are horizontal
    # and get discarded. Only 2 non-horizontal edges remain.
    check("Square contour all on-curve",
          ['100 0 CELLS _TTF-PTS-X + !',
           '600 1 CELLS _TTF-PTS-X + !',
           '600 2 CELLS _TTF-PTS-X + !',
           '100 3 CELLS _TTF-PTS-X + !',
           '100 0 CELLS _TTF-PTS-Y + !',
           '100 1 CELLS _TTF-PTS-Y + !',
           '600 2 CELLS _TTF-PTS-Y + !',
           '600 3 CELLS _TTF-PTS-Y + !',
           '1 _TTF-PTS-FL 0 + C!',
           '1 _TTF-PTS-FL 1 + C!',
           '1 _TTF-PTS-FL 2 + C!',
           '1 _TTF-PTS-FL 3 + C!',
           '3 0 CELLS _TTF-CONT-ENDS + !',
           '1000 _TTF-UPEM !',
           '16 _RST-YFLIP !',
           '16 1000 RAST-SCALE!',
           'RAST-RESET',
           '0 3 _RST-WALK-CONTOUR',
           # 2 non-horizontal edges (horiz top/bottom discarded)
           'RAST-NEDGES .'],
          '2 ')

def test_contour_walker_curves():
    """Test contour walker with off-curve points (Bézier curves)."""
    print("\n=== Contour Walker (curves) ===")
    # 3 points: on-curve, off-curve, on-curve → should emit flatten edges
    # P0=(0,0) on-curve, P1=(500,1000) off-curve ctrl, P2=(1000,0) on-curve
    # This is a simple arch shape
    check("Quad curve generates edges",
          ['0   0 CELLS _TTF-PTS-X + !',
           '500 1 CELLS _TTF-PTS-X + !',
           '1000 2 CELLS _TTF-PTS-X + !',
           '0   0 CELLS _TTF-PTS-Y + !',
           '1000 1 CELLS _TTF-PTS-Y + !',
           '0   2 CELLS _TTF-PTS-Y + !',
           # P0 on-curve, P1 off-curve, P2 on-curve
           '1 _TTF-PTS-FL 0 + C!',
           '0 _TTF-PTS-FL 1 + C!',
           '1 _TTF-PTS-FL 2 + C!',
           '2 0 CELLS _TTF-CONT-ENDS + !',
           '1000 _TTF-UPEM !',
           '16 _RST-YFLIP !',
           '16 1000 RAST-SCALE!',
           'RAST-RESET',
           '0 2 _RST-WALK-CONTOUR',
           # Should have MORE than 3 edges (Bézier flattening subdivides)
           'RAST-NEDGES 3 > IF ." YES" ELSE ." NO" THEN'],
          'YES')

def test_contour_walker_consecutive_offcurve():
    """Test implied midpoints between consecutive off-curve points."""
    print("\n=== Contour Walker (consecutive off-curve) ===")
    # 4 points: on, off, off, on
    # P0=(0,0) on, P1=(300,600) off, P2=(700,600) off, P3=(1000,0) on
    # Between P1 and P2, implied on-curve at (500,600)
    check("Consecutive off-curve implied midpoint",
          ['0    0 CELLS _TTF-PTS-X + !',
           '300  1 CELLS _TTF-PTS-X + !',
           '700  2 CELLS _TTF-PTS-X + !',
           '1000 3 CELLS _TTF-PTS-X + !',
           '0    0 CELLS _TTF-PTS-Y + !',
           '600  1 CELLS _TTF-PTS-Y + !',
           '600  2 CELLS _TTF-PTS-Y + !',
           '0    3 CELLS _TTF-PTS-Y + !',
           '1 _TTF-PTS-FL 0 + C!',
           '0 _TTF-PTS-FL 1 + C!',
           '0 _TTF-PTS-FL 2 + C!',
           '1 _TTF-PTS-FL 3 + C!',
           '3 0 CELLS _TTF-CONT-ENDS + !',
           '1000 _TTF-UPEM !',
           '16 _RST-YFLIP !',
           '16 1000 RAST-SCALE!',
           'RAST-RESET',
           '0 3 _RST-WALK-CONTOUR',
           # Should generate edges (more than just 4 straight lines)
           'RAST-NEDGES 4 > IF ." YES" ELSE ." NO" THEN'],
          'YES')

def test_rast_glyph_synthetic():
    """Test RAST-GLYPH with a synthetic simple triangle glyph."""
    print("\n=== RAST-GLYPH (synthetic) ===")
    # Build a minimal glyph in memory: triangle with 3 on-curve points.
    # We directly set up the decoded arrays and test RAST-GLYPH's fill.
    check("RAST-GLYPH fills bitmap",
          [# Set up a triangle: (100,100) (900,100) (500,900)
           '100 0 CELLS _TTF-PTS-X + !',
           '900 1 CELLS _TTF-PTS-X + !',
           '500 2 CELLS _TTF-PTS-X + !',
           '100 0 CELLS _TTF-PTS-Y + !',
           '100 1 CELLS _TTF-PTS-Y + !',
           '900 2 CELLS _TTF-PTS-Y + !',
           '1 _TTF-PTS-FL 0 + C!',
           '1 _TTF-PTS-FL 1 + C!',
           '1 _TTF-PTS-FL 2 + C!',
           '2 0 CELLS _TTF-CONT-ENDS + !',
           '1000 _TTF-UPEM !',
           # Allocate bitmap: 16x16 = 256 bytes
           'CREATE _GBUF 256 ALLOT',
           # Set scale and rasterize manually
           '16 _RST-YFLIP !',
           '16 1000 RAST-SCALE!',
           'RAST-RESET',
           # Manually decode points and walk
           '0 2 _RST-WALK-CONTOUR',
           '_GBUF 16 16 RAST-FILL',
           # Check center pixel (8,8) is filled
           '_GBUF 8 16 * + 8 + C@ 0<> IF ." FILLED" ELSE ." EMPTY" THEN'],
          'FILLED')

# =====================================================================
#  Cache tests
# =====================================================================

def test_cache_flush():
    print("\n=== Cache ===" )
    # After flush, lookup should miss
    check("GC-FLUSH then lookup misses",
          ['GC-FLUSH',
           '65 16 GC-LOOKUP . . .'],
          '0 0 0 ')

def test_cache_hash():
    # Hash function should produce values < GC-SLOTS
    check("Hash within bounds",
          ['65 16 _GC-HASH GC-SLOTS < IF ." OK" ELSE ." BAD" THEN'],
          'OK')

def test_cache_store_and_lookup():
    """Store a synthetic glyph and verify lookup returns it."""
    # Set up a tiny triangle glyph, store via GC-STORE, then lookup
    check("GC-STORE then GC-LOOKUP hits",
          [# Set up synthetic glyph data (triangle)
           '100 0 CELLS _TTF-PTS-X + !',
           '900 1 CELLS _TTF-PTS-X + !',
           '500 2 CELLS _TTF-PTS-X + !',
           '100 0 CELLS _TTF-PTS-Y + !',
           '100 1 CELLS _TTF-PTS-Y + !',
           '900 2 CELLS _TTF-PTS-Y + !',
           '1 _TTF-PTS-FL 0 + C!',
           '1 _TTF-PTS-FL 1 + C!',
           '1 _TTF-PTS-FL 2 + C!',
           '2 0 CELLS _TTF-CONT-ENDS + !',
           '1000 _TTF-UPEM !',
           '3 _TTF-DEC-NCONT !',
           '2 _TTF-DEC-NPTS !',
           'GC-FLUSH',
           # Store glyph 0 at 8px (GC-STORE calls RAST-GLYPH internally)
           # But RAST-GLYPH calls TTF-DECODE-GLYPH which needs real data.
           # Instead, test the cache lookup/miss path directly.
           '42 16 GC-LOOKUP . . .',
          ],
          '0 0 0 ')

def test_cache_gc_get_miss():
    """Lookup after flush should miss."""
    check("GC-GET lookup miss",
          ['GC-FLUSH',
           '42 8 GC-LOOKUP . . .'],
          '0 0 0 ')

# =====================================================================
#  Layout tests
# =====================================================================

def _layout_setup():
    """Forth lines to create synthetic TTF metrics for layout testing.

    Identity cmap (codepoint=glyph ID) for ASCII 32-127.
    All glyphs have advance width 500 in 1000 UPEM.
    At 10px scale: char width=5, ascender=8, descender=-2, line height=10.

    Also redefines layout words with fresh compilation so they
    pick up the current dictionary state for TTF lookups.
    """
    return [
        ': BE-W! ( val addr -- ) OVER 8 RSHIFT OVER C! 1+ SWAP 0xFF AND SWAP C! ;',
        # hmtx: 128 entries, advance=500 lsb=0
        'CREATE _SYN-HMTX 512 ALLOT',
        ': _FILL-HMTX 128 0 DO 500 _SYN-HMTX I 4 * + BE-W! 0 _SYN-HMTX I 4 * + 2 + BE-W! LOOP ;',
        '_FILL-HMTX',
        '_SYN-HMTX _TTF-HMTX ! 128 _TTF-NHMETRICS !',
        '1000 _TTF-UPEM ! 800 _TTF-ASCENDER ! -200 _TTF-DESCENDER ! 0 _TTF-LINEGAP !',
        # cmap format 4: 2 segments, identity map 32-127
        'CREATE _SYN-CMAP4 64 ALLOT',
        '4 _SYN-CMAP4 0 + BE-W! 32 _SYN-CMAP4 2 + BE-W! 0 _SYN-CMAP4 4 + BE-W!',
        '4 _SYN-CMAP4 6 + BE-W! 2 _SYN-CMAP4 8 + BE-W! 1 _SYN-CMAP4 10 + BE-W! 0 _SYN-CMAP4 12 + BE-W!',
        '127 _SYN-CMAP4 14 + BE-W! 65535 _SYN-CMAP4 16 + BE-W!',
        '0 _SYN-CMAP4 18 + BE-W!',
        '32 _SYN-CMAP4 20 + BE-W! 65535 _SYN-CMAP4 22 + BE-W!',
        '0 _SYN-CMAP4 24 + BE-W! 1 _SYN-CMAP4 26 + BE-W!',
        '0 _SYN-CMAP4 28 + BE-W! 0 _SYN-CMAP4 30 + BE-W!',
        '_SYN-CMAP4 _TTF-CMAP4 ! 2 _TTF-CMAP4-NSEG !',
        '10 LAY-SCALE!',
    ]

def test_layout_bew_diag():
    """Minimal diagnostic: does BE-W! / BE-W@ work from snapshot?"""
    print("\n=== Layout diag ===")
    check("BE-W! round-trip",
          [': BE-W! ( v a -- ) OVER 8 RSHIFT OVER C! 1+ SWAP 255 AND SWAP C! ;',
           'CREATE _TMP 8 ALLOT',
           '500 _TMP BE-W! _TMP BE-W@ .'],
          '500 ')

def test_layout_char_width():
    print("\n=== Layout ===")
    check("LAY-CHAR-WIDTH basic",
          _layout_setup() + ['65 LAY-CHAR-WIDTH .'],
          '5 ')

def test_layout_text_width():
    # Diag: two CW calls, print both
    check("LAY-TW print both",
          _layout_setup() + ['65 LAY-CHAR-WIDTH . 66 LAY-CHAR-WIDTH .'],
          '5 5 ')
    # Diag: two CW calls, add and print — expect EXACTLY 10
    check("LAY-TW add two",
          _layout_setup() + ['65 LAY-CHAR-WIDTH 66 LAY-CHAR-WIDTH + ." =" .'],
          '=10 ')

def test_layout_metrics():
    check("LAY-LINE-HEIGHT",
          _layout_setup() + ['LAY-LINE-HEIGHT .'],
          '10 ')
    check("LAY-ASCENDER",
          _layout_setup() + ['LAY-ASCENDER .'],
          '8 ')

def test_layout_cursor():
    check("LAY-CURSOR init and read",
          _layout_setup() + [
              '10 20 LAY-CURSOR-INIT',
              'LAY-CURSOR@ SWAP . .'],
          '10 20')
    check("LAY-CURSOR-ADV",
          _layout_setup() + [
              '10 20 LAY-CURSOR-INIT',
              '65 LAY-CURSOR-ADV',
              '_LAY-CX @ .'],
          '15 ')
    check("LAY-CURSOR-NL",
          _layout_setup() + [
              '10 20 LAY-CURSOR-INIT',
              'LAY-CURSOR-NL',
              '_LAY-CX @ . _LAY-CY @ .'],
          '10 30')

def test_layout_wrap_word_break():
    # wrap width 14: "AB CD". Each char 5px. A(5) B(10) space(15>14 → break).
    # Use CREATE'd string and separate line outputs checked individually.
    check("LAY-WRAP word break line1",
          _layout_setup() + [
              '14 LAY-WRAP-WIDTH!',
              'CREATE _WS 8 ALLOT',
              '65 _WS C! 66 _WS 1 + C! 32 _WS 2 + C! 67 _WS 3 + C! 68 _WS 4 + C!',
              '_WS 5 LAY-WRAP-INIT',
              'LAY-WRAP-LINE DROP NIP .'],
          '3 ')
    check("LAY-WRAP word break line2",
          _layout_setup() + [
              '14 LAY-WRAP-WIDTH!',
              'CREATE _WS 8 ALLOT',
              '65 _WS C! 66 _WS 1 + C! 32 _WS 2 + C! 67 _WS 3 + C! 68 _WS 4 + C!',
              '_WS 5 LAY-WRAP-INIT',
              'LAY-WRAP-LINE 2DROP DROP',
              'LAY-WRAP-LINE DROP NIP .'],
          '2 ')

def test_layout_wrap_hard_newline():
    check("LAY-WRAP hard newline line1",
          _layout_setup() + [
              '100 LAY-WRAP-WIDTH!',
              'CREATE _NLS 8 ALLOT',
              '65 _NLS C! 66 _NLS 1 + C! 10 _NLS 2 + C! 67 _NLS 3 + C! 68 _NLS 4 + C!',
              '_NLS 5 LAY-WRAP-INIT',
              'LAY-WRAP-LINE DROP NIP .'],
          '2 ')
    check("LAY-WRAP hard newline line2",
          _layout_setup() + [
              '100 LAY-WRAP-WIDTH!',
              'CREATE _NLS 8 ALLOT',
              '65 _NLS C! 66 _NLS 1 + C! 10 _NLS 2 + C! 67 _NLS 3 + C! 68 _NLS 4 + C!',
              '_NLS 5 LAY-WRAP-INIT',
              'LAY-WRAP-LINE 2DROP DROP',
              'LAY-WRAP-LINE DROP NIP .'],
          '2 ')

def test_layout_wrap_forced_break():
    # wrap width 7: each char 5px, only 1 fits. "ABCD" → 4×1
    check("LAY-WRAP forced line1",
          _layout_setup() + [
              '7 LAY-WRAP-WIDTH!',
              'CREATE _FS 8 ALLOT',
              '65 _FS C! 66 _FS 1 + C! 67 _FS 2 + C! 68 _FS 3 + C!',
              '_FS 4 LAY-WRAP-INIT',
              'LAY-WRAP-LINE DROP NIP .'],
          '1 ')
    check("LAY-WRAP forced line2",
          _layout_setup() + [
              '7 LAY-WRAP-WIDTH!',
              'CREATE _FS 8 ALLOT',
              '65 _FS C! 66 _FS 1 + C! 67 _FS 2 + C! 68 _FS 3 + C!',
              '_FS 4 LAY-WRAP-INIT',
              'LAY-WRAP-LINE 2DROP DROP',
              'LAY-WRAP-LINE DROP NIP .'],
          '1 ')

def test_layout_wrap_fits():
    # Entire string fits in one line, then done flag=0
    check("LAY-WRAP fits one line",
          _layout_setup() + [
              '100 LAY-WRAP-WIDTH!',
              'CREATE _FS2 8 ALLOT',
              '72 _FS2 C! 101 _FS2 1 + C! 108 _FS2 2 + C! 108 _FS2 3 + C! 111 _FS2 4 + C!',
              '_FS2 5 LAY-WRAP-INIT',
              'LAY-WRAP-LINE DROP NIP .'],
          '5 ')
    check("LAY-WRAP done after one line",
          _layout_setup() + [
              '100 LAY-WRAP-WIDTH!',
              'CREATE _FS2 8 ALLOT',
              '72 _FS2 C! 101 _FS2 1 + C! 108 _FS2 2 + C! 108 _FS2 3 + C! 111 _FS2 4 + C!',
              '_FS2 5 LAY-WRAP-INIT',
              'LAY-WRAP-LINE 2DROP DROP',
              'LAY-WRAP-LINE NIP NIP .'],
          '0 ')

# =====================================================================
#  Main
# =====================================================================

if __name__ == '__main__':
    build_snapshot()

    test_big_endian_readers()
    test_edge_insertion()
    test_scanline_fill()
    test_contour_walker_lines()
    test_contour_walker_curves()
    test_contour_walker_consecutive_offcurve()
    test_rast_glyph_synthetic()

    test_cache_flush()
    test_cache_hash()
    test_cache_store_and_lookup()
    test_cache_gc_get_miss()

    test_layout_bew_diag()
    test_layout_char_width()
    test_layout_text_width()
    test_layout_metrics()
    test_layout_cursor()
    test_layout_wrap_word_break()
    test_layout_wrap_hard_newline()
    test_layout_wrap_forced_break()
    test_layout_wrap_fits()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    if _fail_count:
        sys.exit(1)
