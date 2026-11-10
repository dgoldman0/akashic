#!/usr/bin/env python3
"""Test suite for akashic-par Forth library (par.f).

Tests: PAR-DO, PAR-MAP, PAR-REDUCE, PAR-FOR, PAR-SCATTER,
       PAR-GATHER, PAR-INFO, and all internal parameter tables.

The emulator runs single-core (NCORES = 1), so all parallel
combinators execute sequentially on core 0.  Tests verify
correctness of chunking, in-place mutation, reduction, and
index iteration — the multicore dispatch path (CORE-RUN +
BARRIER) is exercised by the same code paths but with NCORES > 1
on real hardware.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.environ.get(
    "MEGAPAD_ROOT", os.path.abspath(os.path.join(ROOT_DIR, "..", "megapad"))
)
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
PAR_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "par.f")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem
from forth_snapshot import run_file_tests, transcript_checks

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + par.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    par_lines  = _load_forth_lines(PAR_F)
    helpers = [
        # Test arrays
        'CREATE _ARR 8 CELLS ALLOT',      # 8-element array
        'CREATE _ARR2 16 CELLS ALLOT',     # 16-element array
        'CREATE _BIG 64 CELLS ALLOT',      # 64-element array
        'VARIABLE _RES',
        'VARIABLE _V1',
        'VARIABLE _ACC',
        # Doubler: ( n -- n*2 )
        ': _DOUBLE 2 * ;',
        # Incrementer: ( n -- n+1 )
        ': _INC1 1+ ;',
        # Squarer: ( n -- n*n )
        ': _SQR DUP * ;',
        # Negate: ( n -- -n )
        ': _NEG NEGATE ;',
        # Adder: ( a b -- a+b )
        ': _ADD + ;',
        # Multiplier: ( a b -- a*b )
        ': _MUL * ;',
        # Max: ( a b -- max )
        ': _MAX MAX ;',
        # For-body: store index squared into array
        ': _FOR-SQ DUP DUP * SWAP CELLS _ARR2 + ! ;',
        # PAR-DO helpers ( -- )
        ': _DO-ADD10 10 _RES +! ;',
        ': _DO-ADD20 20 _RES +! ;',
        ': _DO-ADD3  3 _RES +! ;',
        ': _DO-ADD7  7 _RES +! ;',
        ': _DO-NOOP ;',
        # PAR-FOR accumulate helper ( i -- )
        ': _ACC+! _ACC +! ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + par_lines + helpers) + "\n"
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
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    if _snapshot is None:
        build_snapshot()
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
#
# The checks read only what the program printed, and fail their test when a
# check fails or KDOS reports a failed line (forth_snapshot.transcript_checks).

check, _, _ = transcript_checks(run_forth)

# ── Tests ──


# ── Constants ──

def test_par_constants():
    check("_PAR-MAX-CORES is 16",
          [': _T _PAR-MAX-CORES . ; _T'],
          "16 ")

    check("NCORES is at least 1",
          [': _T NCORES 0> . ; _T'],
          "-1 ")


# ── PAR-DO ──

def test_par_do():
    check("PAR-DO runs both XTs",
          [': _T',
           '  0 _RES !',
           "  ['] _DO-ADD10 ['] _DO-ADD20 PAR-DO",
           '  _RES @ .',
           '; _T'],
          "30 ")

    check("PAR-DO with noops",
          [': _T',
           "  ['] _DO-NOOP ['] _DO-NOOP PAR-DO",
           '  42 .',
           '; _T'],
          "42 ")

    check("PAR-DO order doesn't matter for commutative ops",
          [': _T',
           '  0 _RES !',
           "  ['] _DO-ADD3 ['] _DO-ADD7 PAR-DO",
           '  _RES @ .',
           '; _T'],
          "10 ")


# ── PAR-MAP basic ──

def test_par_map_basic():
    check("map double over 4 elements",
          [': _T',
           '  1 _ARR !  2 _ARR CELL+ !  3 _ARR 2 CELLS + !  4 _ARR 3 CELLS + !',
           "  ['] _DOUBLE _ARR 4 PAR-MAP",
           '  _ARR @ . _ARR CELL+ @ . _ARR 2 CELLS + @ . _ARR 3 CELLS + @ .',
           '; _T'],
          "2 4 6 8 ")

    check("map increment over 4 elements",
          [': _T',
           '  10 _ARR !  20 _ARR CELL+ !  30 _ARR 2 CELLS + !  40 _ARR 3 CELLS + !',
           "  ['] _INC1 _ARR 4 PAR-MAP",
           '  _ARR @ . _ARR CELL+ @ . _ARR 2 CELLS + @ . _ARR 3 CELLS + @ .',
           '; _T'],
          "11 21 31 41 ")

    check("map square over 3 elements",
          [': _T',
           '  3 _ARR !  5 _ARR CELL+ !  7 _ARR 2 CELLS + !',
           "  ['] _SQR _ARR 3 PAR-MAP",
           '  _ARR @ . _ARR CELL+ @ . _ARR 2 CELLS + @ .',
           '; _T'],
          "9 25 49 ")

    check("map negate over 4 elements",
          [': _T',
           '  1 _ARR !  2 _ARR CELL+ !  3 _ARR 2 CELLS + !  4 _ARR 3 CELLS + !',
           "  ['] _NEG _ARR 4 PAR-MAP",
           '  _ARR @ . _ARR CELL+ @ . _ARR 2 CELLS + @ . _ARR 3 CELLS + @ .',
           '; _T'],
          "-1 -2 -3 -4 ")


# ── PAR-MAP edge cases ──

def test_par_map_edge_cases():
    check("map over 1 element",
          [': _T',
           '  42 _ARR !',
           "  ['] _DOUBLE _ARR 1 PAR-MAP",
           '  _ARR @ .',
           '; _T'],
          "84 ")

    check("map over 0 elements is noop",
          [': _T',
           '  42 _ARR !',
           "  ['] _DOUBLE _ARR 0 PAR-MAP",
           '  _ARR @ .',
           '; _T'],
          "42 ")

    check("map over 8 elements",
          [': _T',
           '  8 0 DO I 1+ I CELLS _ARR + ! LOOP',
           "  ['] _DOUBLE _ARR 8 PAR-MAP",
           '  8 0 DO I CELLS _ARR + @ . LOOP',
           '; _T'],
          "2 4 6 8 10 12 14 16 ")


# ── PAR-REDUCE basic ──

def test_par_reduce_basic():
    check("reduce sum of 4 elements",
          [': _T',
           '  10 _ARR !  20 _ARR CELL+ !  30 _ARR 2 CELLS + !  40 _ARR 3 CELLS + !',
           "  ['] _ADD 0 _ARR 4 PAR-REDUCE .",
           '; _T'],
          "100 ")

    check("reduce sum of 8 elements (1+2+...+8 = 36)",
          [': _T',
           '  8 0 DO I 1+ I CELLS _ARR + ! LOOP',
           "  ['] _ADD 0 _ARR 8 PAR-REDUCE .",
           '; _T'],
          "36 ")

    check("reduce product of 4 elements (1*2*3*4 = 24)",
          [': _T',
           '  1 _ARR !  2 _ARR CELL+ !  3 _ARR 2 CELLS + !  4 _ARR 3 CELLS + !',
           "  ['] _MUL 1 _ARR 4 PAR-REDUCE .",
           '; _T'],
          "24 ")

    check("reduce max of 4 elements",
          [': _T',
           '  5 _ARR !  99 _ARR CELL+ !  3 _ARR 2 CELLS + !  42 _ARR 3 CELLS + !',
           "  ['] _MAX 0 _ARR 4 PAR-REDUCE .",
           '; _T'],
          "99 ")


# ── PAR-REDUCE edge cases ──

def test_par_reduce_edge_cases():
    check("reduce single element",
          [': _T',
           '  42 _ARR !',
           "  ['] _ADD 0 _ARR 1 PAR-REDUCE .",
           '; _T'],
          "42 ")

    check("reduce 0 elements returns identity",
          [': _T',
           "  ['] _ADD 999 _ARR 0 PAR-REDUCE .",
           '; _T'],
          "999 ")

    check("reduce sum of 16 elements",
          [': _T',
           '  16 0 DO I 1+ I CELLS _ARR2 + ! LOOP',
           "  ['] _ADD 0 _ARR2 16 PAR-REDUCE .",
           '; _T'],
          "136 ")


# ── PAR-FOR basic ──

def test_par_for_basic():
    check("for-loop stores index squares",
          [': _T',
           "  ['] _FOR-SQ 0 4 PAR-FOR",
           '  _ARR2 @ . _ARR2 CELL+ @ . _ARR2 2 CELLS + @ . _ARR2 3 CELLS + @ .',
           '; _T'],
          "0 1 4 9 ")

    check("for-loop 0..8 stores squares",
          [': _T',
           "  ['] _FOR-SQ 0 8 PAR-FOR",
           '  8 0 DO I CELLS _ARR2 + @ . LOOP',
           '; _T'],
          "0 1 4 9 16 25 36 49 ")

    check("for-loop accumulates via variable",
          [': _T',
           '  0 _ACC !',
           "  ['] _ACC+! 0 10 PAR-FOR",
           '  _ACC @ .',
           '; _T'],
          "45 ")


# ── PAR-FOR edge cases ──

def test_par_for_edge_cases():
    check("for-loop empty range is noop",
          [': _T',
           '  0 _ACC !',
           "  ['] _ACC+! 5 5 PAR-FOR",
           '  _ACC @ .',
           '; _T'],
          "0 ")

    check("for-loop reversed range is noop",
          [': _T',
           '  0 _ACC !',
           "  ['] _ACC+! 10 5 PAR-FOR",
           '  _ACC @ .',
           '; _T'],
          "0 ")

    check("for-loop single iteration",
          [': _T',
           '  0 _ACC !',
           "  ['] _ACC+! 42 43 PAR-FOR",
           '  _ACC @ .',
           '; _T'],
          "42 ")

    check("for-loop with offset range (5..9)",
          [': _T',
           '  0 _ACC !',
           "  ['] _ACC+! 5 9 PAR-FOR",
           '  _ACC @ .',               # 5+6+7+8 = 26
           '; _T'],
          "26 ")


# ── PAR-SCATTER / PAR-GATHER ──

def test_par_scatter_and_gather():
    check("scatter sets up start/count for 8 elements",
          [': _T',
           '  _ARR 8 8 PAR-SCATTER',
           '  0 _PAR-START@ . 0 _PAR-CNT@ .',
           '; _T'],
          "0 8 ")

    check("gather collects results",
          [': _T',
           '  42 0 _PAR-RESULTS!',
           '  _ARR 1 PAR-GATHER',
           '  _ARR @ .',
           '; _T'],
          "42 ")


# ── PAR-INFO ──

def test_par_info():
    check("PAR-INFO shows active cores",
          [': _T PAR-INFO ; _T'],
          "[par active=")

    check("PAR-INFO shows full/total",
          [': _T PAR-INFO ; _T'],
          "full=")

    check("PAR-INFO shows per-core type",
          [': _T PAR-INFO ; _T'],
          "(full)")


# ── Core-type awareness ──

def test_core_type_awareness():
    check("PAR-CORES defaults to N-FULL",
          [': _T PAR-CORES N-FULL = . ; _T'],
          "-1 ")

    check("PAR-USE-ALL sets PAR-CORES to NCORES",
          [': _T PAR-USE-ALL PAR-CORES NCORES = . PAR-USE-FULL ; _T'],
          "-1 ")

    check("PAR-USE-FULL restores N-FULL",
          [': _T PAR-USE-ALL PAR-USE-FULL PAR-CORES N-FULL = . ; _T'],
          "-1 ")


# ── PAR-MAP + PAR-REDUCE composition ──

def test_par_map_and_reduce_composition():
    check("double all then sum (1..4 -> 2+4+6+8 = 20)",
          [': _T',
           '  1 _ARR !  2 _ARR CELL+ !  3 _ARR 2 CELLS + !  4 _ARR 3 CELLS + !',
           "  ['] _DOUBLE _ARR 4 PAR-MAP",
           "  ['] _ADD 0 _ARR 4 PAR-REDUCE .",
           '; _T'],
          "20 ")

    check("square then sum (1..4 -> 1+4+9+16 = 30)",
          [': _T',
           '  1 _ARR !  2 _ARR CELL+ !  3 _ARR 2 CELLS + !  4 _ARR 3 CELLS + !',
           "  ['] _SQR _ARR 4 PAR-MAP",
           "  ['] _ADD 0 _ARR 4 PAR-REDUCE .",
           '; _T'],
          "30 ")


# ── Larger arrays ──

def test_larger_arrays():
    check("map double 64 elements",
          [': _T',
           '  64 0 DO I 1+ I CELLS _BIG + ! LOOP',
           "  ['] _DOUBLE _BIG 64 PAR-MAP",
           '  _BIG @ .                  \\ first: 2',
           '  _BIG 63 CELLS + @ .      \\ last: 128',
           '; _T'],
          "2 128 ")

    check("reduce sum 64 elements (1+2+...+64 = 2080)",
          [': _T',
           '  64 0 DO I 1+ I CELLS _BIG + ! LOOP',
           "  ['] _ADD 0 _BIG 64 PAR-REDUCE .",
           '; _T'],
          "2080 ")


if __name__ == '__main__':
    run_file_tests(__file__)
