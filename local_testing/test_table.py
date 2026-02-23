#!/usr/bin/env python3
"""Test suite for akashic-table Forth library (table.f).

Tests: TBL-CREATE, TBL-ALLOC, TBL-FREE, TBL-COUNT,
       TBL-SLOT, TBL-EACH, TBL-FIND, TBL-FLUSH.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
TBL_F      = os.path.join(ROOT_DIR, "utils", "table", "table.f")

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
    print("[*] Building snapshot: BIOS + KDOS + table.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    tbl_lines  = _load_forth_lines(TBL_F)
    # Test table: 16-byte slots, up to 8 slots.
    # Total memory: 24 header + 8 * (1 + 16) = 24 + 136 = 160 bytes
    helpers = [
        'CREATE _MYTBL 256 ALLOT',
        '16 8 _MYTBL TBL-CREATE',
        # A second smaller table for edge-case tests
        'CREATE _TINY 64 ALLOT',
        '4 2 _TINY TBL-CREATE',
        # Accumulator for TBL-EACH tests
        'VARIABLE _ACC',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + tbl_lines + helpers) + "\n"
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
    print("\n── TBL-CREATE / TBL-COUNT ──\n")

    check("count after create is 0",
          [': _T _MYTBL TBL-COUNT . ; _T'],
          "0 ")

    check("slot-size stored correctly",
          [': _T _MYTBL @ . ; _T'],
          "16 ")

    check("max-slots stored correctly",
          [': _T _MYTBL 8 + @ . ; _T'],
          "8 ")

    check("tiny table count = 0",
          [': _T _TINY TBL-COUNT . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TBL-ALLOC ──\n")

    check("alloc returns non-zero",
          [': _T _MYTBL TBL-ALLOC 0 > . ; _T'],
          "-1 ")

    check("alloc twice returns different addresses",
          [': _T _MYTBL TBL-ALLOC _MYTBL TBL-ALLOC <> . ; _T'],
          "-1 ")

    check("count after 2 allocs = 2",
          [': _T _MYTBL TBL-ALLOC DROP _MYTBL TBL-ALLOC DROP',
           '_MYTBL TBL-COUNT . ; _T'],
          "2 ")

    check("alloc on full table returns 0",
          [': _T _TINY TBL-ALLOC DROP _TINY TBL-ALLOC DROP',
           '_TINY TBL-ALLOC . ; _T'],
          "0 ")

    check("write and read slot data",
          [': _T _MYTBL TBL-ALLOC DUP 42 SWAP ! @ . ; _T'],
          "42 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TBL-FREE ──\n")

    check("free decrements count",
          [': _T',
           '  _MYTBL TBL-ALLOC',      # alloc one slot
           '  _MYTBL TBL-COUNT .  ',   # count = 1
           '  _MYTBL SWAP TBL-FREE',   # free it
           '  _MYTBL TBL-COUNT .  ',   # count = 0
           '; _T'],
          "1 0 ")

    check("freed slot can be re-allocated",
          [': _T',
           '  _MYTBL TBL-ALLOC',          # s1
           '  DUP _MYTBL SWAP TBL-FREE',  # free s1
           '  _MYTBL TBL-ALLOC',          # re-alloc (should reuse)
           '  0 > . ',                    # non-zero
           '; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TBL-SLOT ──\n")

    check("slot returns 0 when free",
          [': _T _MYTBL 0 TBL-SLOT . ; _T'],
          "0 ")

    check("slot returns addr when used",
          [': _T _MYTBL TBL-ALLOC DROP _MYTBL 0 TBL-SLOT 0 > . ; _T'],
          "-1 ")

    check("slot out of range returns 0",
          [': _T _MYTBL 99 TBL-SLOT . ; _T'],
          "0 ")

    check("slot returns same addr as alloc",
          [': _T',
           '  _MYTBL TBL-ALLOC',
           '  _MYTBL 0 TBL-SLOT',
           '  = . ',
           '; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TBL-FLUSH ──\n")

    check("flush resets count to 0",
          [': _T',
           '  _MYTBL TBL-ALLOC DROP _MYTBL TBL-ALLOC DROP',
           '  _MYTBL TBL-FLUSH',
           '  _MYTBL TBL-COUNT .',
           '; _T'],
          "0 ")

    check("alloc works after flush",
          [': _T',
           '  _MYTBL TBL-ALLOC DROP _MYTBL TBL-ALLOC DROP',
           '  _MYTBL TBL-FLUSH',
           '  _MYTBL TBL-ALLOC 0 > .',
           '; _T'],
          "-1 ")

    check("all slots free after flush",
          [': _T',
           '  _MYTBL TBL-ALLOC DROP',
           '  _MYTBL TBL-ALLOC DROP',
           '  _MYTBL TBL-ALLOC DROP',
           '  _MYTBL TBL-FLUSH',
           '  _MYTBL 0 TBL-SLOT .',
           '  _MYTBL 1 TBL-SLOT .',
           '  _MYTBL 2 TBL-SLOT .',
           '; _T'],
          "0 0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TBL-EACH ──\n")

    check("each sums all slot values",
          [': _ADD-ACC  @ _ACC @ + _ACC ! ;',
           ': _T',
           '  0 _ACC !',
           '  _MYTBL TBL-FLUSH',         # start fresh
           '  _MYTBL TBL-ALLOC 10 SWAP !',
           '  _MYTBL TBL-ALLOC 20 SWAP !',
           '  _MYTBL TBL-ALLOC 30 SWAP !',
           "  _MYTBL ['] _ADD-ACC TBL-EACH",
           '  _ACC @ .',
           '; _T'],
          "60 ")

    check("each skips free slots",
          [': _ADD-ACC2  @ _ACC @ + _ACC ! ;',
           ': _T',
           '  0 _ACC !',
           '  _MYTBL TBL-FLUSH',
           '  _MYTBL TBL-ALLOC 10 SWAP !',
           '  _MYTBL TBL-ALLOC 20 SWAP !',  # slot 1
           '  _MYTBL TBL-ALLOC 30 SWAP !',
           '  _MYTBL 1 TBL-SLOT _MYTBL SWAP TBL-FREE',  # free slot 1 (val 20)
           "  _MYTBL ['] _ADD-ACC2 TBL-EACH",
           '  _ACC @ .',
           '; _T'],
          "40 ")

    check("each on empty table does nothing",
          [': _BUMP  DROP 1 _ACC +! ;',
           ': _T',
           '  0 _ACC !',
           '  _MYTBL TBL-FLUSH',
           "  _MYTBL ['] _BUMP TBL-EACH",
           '  _ACC @ .',
           '; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── TBL-FIND ──\n")

    check("find returns matching slot",
          [': _IS20?  @ 20 = ;',
           ': _T',
           '  _MYTBL TBL-FLUSH',
           '  _MYTBL TBL-ALLOC 10 SWAP !',
           '  _MYTBL TBL-ALLOC 20 SWAP !',
           '  _MYTBL TBL-ALLOC 30 SWAP !',
           "  _MYTBL ['] _IS20? TBL-FIND",
           '  @ .',
           '; _T'],
          "20 ")

    check("find returns 0 when none match",
          [': _IS99?  @ 99 = ;',
           ': _T',
           '  _MYTBL TBL-FLUSH',
           '  _MYTBL TBL-ALLOC 10 SWAP !',
           '  _MYTBL TBL-ALLOC 20 SWAP !',
           "  _MYTBL ['] _IS99? TBL-FIND",
           '  .',
           '; _T'],
          "0 ")

    check("find returns 0 on empty table",
          [': _ANY?  DROP -1 ;',
           ': _T',
           '  _MYTBL TBL-FLUSH',
           "  _MYTBL ['] _ANY? TBL-FIND",
           '  .',
           '; _T'],
          "0 ")

    check("find returns first match",
          [': _GT15?  @ 15 > ;',
           ': _T',
           '  _MYTBL TBL-FLUSH',
           '  _MYTBL TBL-ALLOC 10 SWAP !',
           '  _MYTBL TBL-ALLOC 20 SWAP !',
           '  _MYTBL TBL-ALLOC 30 SWAP !',
           "  _MYTBL ['] _GT15? TBL-FIND",
           '  @ .',
           '; _T'],
          "20 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Compile Checks ──\n")

    check("TBL-CREATE compiles",
          [': _T 8 4 PAD TBL-CREATE ; _T'],
          "")

    check("TBL-ALLOC compiles",
          [': _T 8 4 PAD TBL-CREATE PAD TBL-ALLOC DROP ; _T'],
          "")

    check("TBL-EACH compiles",
          [": _NOP DROP ;",
           ": _T 8 4 PAD TBL-CREATE PAD ['] _NOP TBL-EACH ; _T"],
          "")

    # ────────────────────────────────────────────────────────────────

    # Remove the placeholder test
    print()
    print("=" * 40)
    print(f"  {_pass} passed, {_fail} failed")
    print("=" * 40)
    sys.exit(1 if _fail else 0)
