#!/usr/bin/env python3
"""Test suite for akashic-conc-map Forth library (conc-map.f).

Tests: CMAP, CMAP-PUT, CMAP-GET, CMAP-DEL, CMAP-COUNT,
       CMAP-EACH, CMAP-CLEAR, CMAP-INFO.

The emulator runs single-core, so concurrency contention isn't
tested.  We verify correctness of the RW-locked wrapper around
KDOS §19 hash tables: insert, lookup, delete, iteration, clear.

Hash table keys and values are byte arrays.  For simplicity,
tests use 8-byte (CELL-sized) keys and values so we can store
integers directly with !.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
RWLOCK_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "rwlock.f")
CMAP_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "conc-map.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + rwlock.f + conc-map.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    rwl_lines  = _load_forth_lines(RWLOCK_F)
    cm_lines   = _load_forth_lines(CMAP_F)
    helpers = [
        # Create a cmap: 8-byte keys, 8-byte values, 31 slots
        '8 8 31 CMAP _M1',
        # Temp key/value buffers (8 bytes each)
        'CREATE _K1 8 ALLOT  CREATE _K2 8 ALLOT  CREATE _K3 8 ALLOT',
        'CREATE _V1 8 ALLOT  CREATE _V2 8 ALLOT  CREATE _V3 8 ALLOT',
        'VARIABLE _RES  0 _RES !',
        'VARIABLE _ACC  0 _ACC !',
        # Helper: sum all values via CMAP-EACH
        ': _SUM-VALS ( key val -- ) NIP @ _ACC +! ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + rwl_lines + cm_lines + helpers) + "\n"
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

# ── Test runner ──

_pass = 0
_fail = 0

def check(name, forth_lines, expected):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        print(f"  PASS  {name}")
        _pass += 1
    else:
        print(f"  FAIL  {name}")
        print(f"        expected: {expected!r}")
        print(f"        got (last lines): {clean.split(chr(10))[-3:]}")
        _fail += 1

# ── Tests ──

if __name__ == '__main__':
    build_snapshot()

    # ────────────────────────────────────────────────────────────────
    print("\n── CMAP Creation ──\n")

    check("CMAP-COUNT starts at 0",
          [': _T _M1 CMAP-COUNT . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CMAP-PUT / CMAP-GET ──\n")

    check("put then get returns value",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-GET @ . ; _T'],
          "42 ")

    check("put increments count",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT _M1 CMAP-COUNT . ; _T'],
          "1 ")

    check("put two entries",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 20 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '_M1 CMAP-COUNT . ; _T'],
          "2 ")

    check("get first of two",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 20 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-GET @ . ; _T'],
          "10 ")

    check("get second of two",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 20 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '_K2 _M1 CMAP-GET @ . ; _T'],
          "20 ")

    check("get missing key returns 0",
          [': _T 999 _K3 ! _K3 _M1 CMAP-GET . ; _T'],
          "0 ")

    check("put updates existing key",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '99 _V2 ! _K1 _V2 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-GET @ . _M1 CMAP-COUNT . ; _T'],
          "99 1 ")

    check("three distinct entries",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 20 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '3 _K3 ! 30 _V3 ! _K3 _V3 _M1 CMAP-PUT',
           '_M1 CMAP-COUNT . ; _T'],
          "3 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CMAP-DEL ──\n")

    check("delete existing key returns -1",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-DEL . ; _T'],
          "-1 ")

    check("delete reduces count",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-DEL DROP _M1 CMAP-COUNT . ; _T'],
          "0 ")

    check("get after delete returns 0",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-DEL DROP _K1 _M1 CMAP-GET . ; _T'],
          "0 ")

    check("delete missing key returns 0",
          [': _T 999 _K3 ! _K3 _M1 CMAP-DEL . ; _T'],
          "0 ")

    check("delete one of two, other remains",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 20 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-DEL DROP',
           '_K2 _M1 CMAP-GET @ . _M1 CMAP-COUNT . ; _T'],
          "20 1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CMAP-EACH ──\n")

    check("CMAP-EACH on empty map",
          [': _T 0 _ACC ! [\'] _SUM-VALS _M1 CMAP-EACH _ACC @ . ; _T'],
          "0 ")

    check("CMAP-EACH sums one entry",
          [': _T 0 _ACC ! 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '[\'] _SUM-VALS _M1 CMAP-EACH _ACC @ . ; _T'],
          "42 ")

    check("CMAP-EACH sums two entries",
          [': _T 0 _ACC ! 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 20 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '[\'] _SUM-VALS _M1 CMAP-EACH _ACC @ . ; _T'],
          "30 ")

    check("CMAP-EACH sums three entries",
          [': _T 0 _ACC ! 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 20 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '3 _K3 ! 30 _V3 ! _K3 _V3 _M1 CMAP-PUT',
           '[\'] _SUM-VALS _M1 CMAP-EACH _ACC @ . ; _T'],
          "60 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CMAP-CLEAR ──\n")

    check("CMAP-CLEAR resets count to 0",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 99 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '_M1 CMAP-CLEAR _M1 CMAP-COUNT . ; _T'],
          "0 ")

    check("CMAP-CLEAR makes get return 0",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_M1 CMAP-CLEAR _K1 _M1 CMAP-GET . ; _T'],
          "0 ")

    check("put works after clear",
          [': _T 1 _K1 ! 42 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_M1 CMAP-CLEAR',
           '1 _K1 ! 77 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-GET @ . ; _T'],
          "77 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CMAP-INFO ──\n")

    check("CMAP-INFO outputs prefix",
          [': _T _M1 CMAP-INFO ; _T'],
          "[cmap")

    check("CMAP-INFO shows count=",
          [': _T _M1 CMAP-INFO ; _T'],
          "count=")

    # ────────────────────────────────────────────────────────────────
    print("\n── Integration ──\n")

    check("put-get-update-get cycle",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-GET @ .',
           '20 _V2 ! _K1 _V2 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-GET @ . ; _T'],
          "10 20 ")

    check("put-delete-put cycle",
          [': _T 1 _K1 ! 10 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-DEL .',
           '99 _V2 ! _K1 _V2 _M1 CMAP-PUT',
           '_K1 _M1 CMAP-GET @ . _M1 CMAP-COUNT . ; _T'],
          "-1 99 1 ")

    check("fill and iterate",
          [': _T 0 _ACC !',
           '1 _K1 ! 100 _V1 ! _K1 _V1 _M1 CMAP-PUT',
           '2 _K2 ! 200 _V2 ! _K2 _V2 _M1 CMAP-PUT',
           '3 _K3 ! 300 _V3 ! _K3 _V3 _M1 CMAP-PUT',
           '[\'] _SUM-VALS _M1 CMAP-EACH _ACC @ . _M1 CMAP-COUNT . ; _T'],
          "600 3 ")

    # ────────────────────────────────────────────────────────────────
    # Done
    print(f"\n{'='*60}")
    print(f"  {_pass} passed, {_fail} failed, {_pass + _fail} total")
    print(f"{'='*60}")
    sys.exit(1 if _fail else 0)
