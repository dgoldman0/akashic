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
"""Test suite for Akashic STARK AIR constraint descriptor (akashic/math/stark-air.f).

Tests AIR builder (AIR-BEGIN/TRANS/BOUNDARY/END), query words
(AIR-N-COLS/N-TRANS/N-BOUND/MAX-OFF), transition evaluation
(AIR-EVAL-TRANS), and boundary checking (AIR-CHECK-BOUND).

Depends on baby-bear.f for BB+ BB- BB* BB-W32! BB-W32@.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
BB_F       = os.path.join(ROOT_DIR, "akashic", "math", "baby-bear.f")
AIR_F      = os.path.join(ROOT_DIR, "akashic", "math", "stark-air.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

Q = 2013265921  # Baby Bear prime

# ── Emulator helpers ─────────────────────────────────────────────────

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
    print("[*] Building snapshot: BIOS + KDOS + baby-bear.f + stark-air.f ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    bb_lines   = _load_forth_lines(BB_F)
    air_lines  = _load_forth_lines(AIR_F)

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + bb_lines + air_lines)
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
            errors.append(l.strip())
            print(f"  [!] {l}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors!")
        print(f"  Aborting — stark-air.f failed to compile cleanly.")
        sys.exit(1)
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

# ── Test framework ───────────────────────────────────────────────────

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

def check_fn(name, forth_lines, predicate, desc=""):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if predicate(clean):
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}  ({desc})")
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")

# =====================================================================
#  Fibonacci AIR setup (1 column, 256 rows)
# =====================================================================

# Build the Fibonacci trace in Forth: trace[0]=1, trace[1]=1, trace[i+2]=trace[i]+trace[i+1]
FIB_SETUP = [
    # Allocate trace buffer (256 * 4 = 1024 bytes)
    'CREATE _ftrace 1024 ALLOT',
    # cols array: 1 cell pointing to _ftrace
    'CREATE _fcols 8 ALLOT  _ftrace _fcols !',
    # Fill Fibonacci values
    ': _fill-fib',
    '  1 _ftrace BB-W32!',
    '  1 _ftrace 4 + BB-W32!',
    '  254 0 DO',
    '    I 4 * _ftrace + BB-W32@',
    '    I 1 + 4 * _ftrace + BB-W32@',
    '    BB+',
    '    I 2 + 4 * _ftrace + BB-W32!',
    '  LOOP ;',
    '_fill-fib',
    # Build the Fibonacci AIR descriptor
    '1 AIR-BEGIN',
    '  AIR-ADD 0 0  0 1  0 2  AIR-TRANS',
    '  0 0 1 AIR-BOUNDARY',
    '  0 1 1 AIR-BOUNDARY',
    'AIR-END CONSTANT _FIB-AIR',
]

# =====================================================================
#  Two-column AIR setup: col0[i+1] = col0[i] + col1[i]
#  col0 = [1, 4, 7, 10, ...] (arithmetic progression +3)
#  col1 = [3, 3, 3, 3, ...] (constant 3)
# =====================================================================

TWOCOL_SETUP = [
    'CREATE _t0 1024 ALLOT',
    'CREATE _t1 1024 ALLOT',
    'CREATE _2cols 16 ALLOT  _t0 _2cols !  _t1 _2cols 8 + !',
    # Fill col1 with constant 3
    ': _fill-t1  256 0 DO  3  I 4 * _t1 + BB-W32!  LOOP ;',
    '_fill-t1',
    # Fill col0: col0[0]=1, col0[i+1] = col0[i] + 3
    ': _fill-t0',
    '  1 _t0 BB-W32!',
    '  255 0 DO',
    '    I 4 * _t0 + BB-W32@  3 BB+',
    '    I 1 + 4 * _t0 + BB-W32!',
    '  LOOP ;',
    '_fill-t0',
    # AIR: col0[i+1] = col0[i] + col1[i]
    '2 AIR-BEGIN',
    '  AIR-ADD 0 0  1 0  0 1  AIR-TRANS',
    '  0 0 1 AIR-BOUNDARY',
    '  1 0 3 AIR-BOUNDARY',
    'AIR-END CONSTANT _2C-AIR',
]

# =====================================================================
#  Tests
# =====================================================================

def test_constants():
    print("\n=== AIR constants ===")
    check("AIR-ADD", ['." V=" AIR-ADD .'], 'V=0 ')
    check("AIR-SUB", ['." V=" AIR-SUB .'], 'V=1 ')
    check("AIR-MUL", ['." V=" AIR-MUL .'], 'V=2 ')

def test_fib_header():
    print("\n=== Fibonacci AIR header ===")
    check("N-COLS=1",
          FIB_SETUP + ['." V=" _FIB-AIR AIR-N-COLS .'],
          'V=1 ')
    check("N-TRANS=1",
          FIB_SETUP + ['." V=" _FIB-AIR AIR-N-TRANS .'],
          'V=1 ')
    check("N-BOUND=2",
          FIB_SETUP + ['." V=" _FIB-AIR AIR-N-BOUND .'],
          'V=2 ')
    check("MAX-OFF=2",
          FIB_SETUP + ['." V=" _FIB-AIR AIR-MAX-OFF .'],
          'V=2 ')

def test_fib_eval_trans():
    print("\n=== Fibonacci AIR transition eval ===")
    # Valid row: residual should be 0
    check("fib trans row 0 = 0",
          FIB_SETUP + ['." V=" _FIB-AIR _fcols 0 AIR-EVAL-TRANS .'],
          'V=0 ')
    check("fib trans row 50 = 0",
          FIB_SETUP + ['." V=" _FIB-AIR _fcols 50 AIR-EVAL-TRANS .'],
          'V=0 ')
    check("fib trans row 253 = 0",
          FIB_SETUP + ['." V=" _FIB-AIR _fcols 253 AIR-EVAL-TRANS .'],
          'V=0 ')
    # Tamper: set trace[2] = 999 instead of 2
    check("fib trans tampered != 0",
          FIB_SETUP + [
              '999 _ftrace 8 + BB-W32!',
              '." V=" _FIB-AIR _fcols 0 AIR-EVAL-TRANS .'
          ],
          # residual = 999 - (1+1) = 997
          'V=997 ')

def test_fib_boundary():
    print("\n=== Fibonacci AIR boundary check ===")
    check("fib boundary valid = TRUE",
          FIB_SETUP + ['." V=" _FIB-AIR _fcols AIR-CHECK-BOUND .'],
          'V=-1 ')
    # Tamper: set trace[0] = 42
    check("fib boundary invalid = FALSE",
          FIB_SETUP + [
              '42 _ftrace BB-W32!',
              '." V=" _FIB-AIR _fcols AIR-CHECK-BOUND .'
          ],
          'V=0 ')

def test_twocol_header():
    print("\n=== Two-column AIR header ===")
    check("2col N-COLS=2",
          TWOCOL_SETUP + ['." V=" _2C-AIR AIR-N-COLS .'],
          'V=2 ')
    check("2col N-TRANS=1",
          TWOCOL_SETUP + ['." V=" _2C-AIR AIR-N-TRANS .'],
          'V=1 ')
    check("2col N-BOUND=2",
          TWOCOL_SETUP + ['." V=" _2C-AIR AIR-N-BOUND .'],
          'V=2 ')
    check("2col MAX-OFF=1",
          TWOCOL_SETUP + ['." V=" _2C-AIR AIR-MAX-OFF .'],
          'V=1 ')

def test_twocol_eval():
    print("\n=== Two-column AIR transition eval ===")
    check("2col trans row 0 = 0",
          TWOCOL_SETUP + ['." V=" _2C-AIR _2cols 0 AIR-EVAL-TRANS .'],
          'V=0 ')
    check("2col trans row 100 = 0",
          TWOCOL_SETUP + ['." V=" _2C-AIR _2cols 100 AIR-EVAL-TRANS .'],
          'V=0 ')
    # Tamper col0[1] = 999
    check("2col trans tampered != 0",
          TWOCOL_SETUP + [
              '999 _t0 4 + BB-W32!',
              '." V=" _2C-AIR _2cols 0 AIR-EVAL-TRANS .'
          ],
          # residual = 999 - (1 + 3) = 995
          'V=995 ')

def test_twocol_boundary():
    print("\n=== Two-column AIR boundary check ===")
    check("2col boundary valid = TRUE",
          TWOCOL_SETUP + ['." V=" _2C-AIR _2cols AIR-CHECK-BOUND .'],
          'V=-1 ')
    # Tamper col1[0] = 7 instead of 3
    check("2col boundary invalid = FALSE",
          TWOCOL_SETUP + [
              '7 _t1 BB-W32!',
              '." V=" _2C-AIR _2cols AIR-CHECK-BOUND .'
          ],
          'V=0 ')

def test_mul_constraint():
    """Test AIR-MUL: col0[i+1] = col0[i] * col1[i], doubling."""
    print("\n=== MUL constraint ===")
    # col0 = [1, 2, 4, 8, 16, ...] (powers of 2)
    # col1 = [2, 2, 2, ...] (constant 2)
    setup = [
        'CREATE _m0 1024 ALLOT',
        'CREATE _m1 1024 ALLOT',
        'CREATE _mcols 16 ALLOT  _m0 _mcols !  _m1 _mcols 8 + !',
        ': _fill-m1  256 0 DO  2  I 4 * _m1 + BB-W32!  LOOP ;',
        '_fill-m1',
        ': _fill-m0',
        '  1 _m0 BB-W32!',
        '  255 0 DO',
        '    I 4 * _m0 + BB-W32@  2 BB*',
        '    I 1 + 4 * _m0 + BB-W32!',
        '  LOOP ;',
        '_fill-m0',
        '2 AIR-BEGIN',
        '  AIR-MUL 0 0  1 0  0 1  AIR-TRANS',
        '  0 0 1 AIR-BOUNDARY',
        '  1 0 2 AIR-BOUNDARY',
        'AIR-END CONSTANT _MUL-AIR',
    ]
    check("mul trans row 0 = 0",
          setup + ['." V=" _MUL-AIR _mcols 0 AIR-EVAL-TRANS .'],
          'V=0 ')
    check("mul trans row 20 = 0",
          setup + ['." V=" _MUL-AIR _mcols 20 AIR-EVAL-TRANS .'],
          'V=0 ')
    check("mul boundary valid",
          setup + ['." V=" _MUL-AIR _mcols AIR-CHECK-BOUND .'],
          'V=-1 ')

def test_sub_constraint():
    """Test AIR-SUB: col0[i+1] = col0[i] - col1[i], counting down."""
    print("\n=== SUB constraint ===")
    # col0 = [1000, 999, 998, ...] (counting down by 1)
    # col1 = [1, 1, 1, ...] (constant 1)
    setup = [
        'CREATE _s0 1024 ALLOT',
        'CREATE _s1 1024 ALLOT',
        'CREATE _scols 16 ALLOT  _s0 _scols !  _s1 _scols 8 + !',
        ': _fill-s1  256 0 DO  1  I 4 * _s1 + BB-W32!  LOOP ;',
        '_fill-s1',
        ': _fill-s0',
        '  1000 _s0 BB-W32!',
        '  255 0 DO',
        '    I 4 * _s0 + BB-W32@  1 BB-',
        '    I 1 + 4 * _s0 + BB-W32!',
        '  LOOP ;',
        '_fill-s0',
        '2 AIR-BEGIN',
        '  AIR-SUB 0 0  1 0  0 1  AIR-TRANS',
        '  0 0 1000 AIR-BOUNDARY',
        '  1 0 1 AIR-BOUNDARY',
        'AIR-END CONSTANT _SUB-AIR',
    ]
    check("sub trans row 0 = 0",
          setup + ['." V=" _SUB-AIR _scols 0 AIR-EVAL-TRANS .'],
          'V=0 ')
    check("sub boundary valid",
          setup + ['." V=" _SUB-AIR _scols AIR-CHECK-BOUND .'],
          'V=-1 ')

def test_all_rows_fib():
    """Evaluate Fibonacci transition at all 254 valid rows."""
    print("\n=== Fibonacci all rows ===")
    # Define a word that checks all rows 0..253 and counts failures
    check("fib all 254 rows = 0 failures",
          FIB_SETUP + [
              'VARIABLE _nfail  0 _nfail !',
              ': _check-all  254 0 DO',
              '    _FIB-AIR _fcols I AIR-EVAL-TRANS',
              '    0 <> IF _nfail @ 1 + _nfail ! THEN',
              '  LOOP ;',
              '_check-all',
              '." V=" _nfail @ .',
          ],
          'V=0 ')

# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()

    test_constants()
    test_fib_header()
    test_fib_eval_trans()
    test_fib_boundary()
    test_twocol_header()
    test_twocol_eval()
    test_twocol_boundary()
    test_mul_constraint()
    test_sub_constraint()
    test_all_rows_fib()

    print(f"\n{'='*50}")
    total = _pass_count + _fail_count
    print(f"  {_pass_count}/{total} passed")
    if _fail_count:
        print(f"  {_fail_count} FAILED")
        sys.exit(1)
    else:
        print(f"  All tests passed!")
