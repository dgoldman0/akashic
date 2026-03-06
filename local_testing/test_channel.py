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
"""Test suite for akashic-channel Forth library (channel.f).

Tests: CHANNEL, CHAN-SEND, CHAN-RECV, CHAN-TRY-SEND, CHAN-TRY-RECV,
       CHAN-SEND-BUF, CHAN-RECV-BUF, CHAN-CLOSE, CHAN-CLOSED?,
       CHAN-COUNT, CHAN-SELECT, CHAN-INFO.

Note: Full blocking tests (CHAN-SEND spinning when full) require
multicore emulation.  These tests cover single-core fast paths,
state transitions, FIFO ordering, close semantics, SELECT, and
addr-based operations.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
CHAN_F     = os.path.join(ROOT_DIR, "akashic", "concurrency", "channel.f")

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
    print("[*] Building snapshot: BIOS + KDOS + event.f + channel.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    evt_lines  = _load_forth_lines(EVENT_F)
    chan_lines  = _load_forth_lines(CHAN_F)
    helpers = [
        # ch1: standard 1-cell channel, capacity 4
        '6 1 CELLS 4 CHANNEL _CH1',
        # ch2: standard 1-cell channel, capacity 8
        '6 1 CELLS 8 CHANNEL _CH2',
        # ch3: for close tests
        '6 1 CELLS 4 CHANNEL _CH3',
        # ch4, ch5: for SELECT tests
        '6 1 CELLS 4 CHANNEL _CH4',
        '6 1 CELLS 4 CHANNEL _CH5',
        # buf-channel: 2-cell elements (16 bytes each), capacity 4
        '6 2 CELLS 4 CHANNEL _BCHX',
        'VARIABLE _RES',
        'VARIABLE _V1',
        'VARIABLE _V2',
        # A 2-cell buffer for BUF tests
        'CREATE _TBUF 2 CELLS ALLOT',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"] + evt_lines
                        + chan_lines + helpers) + "\n"
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
    print("\n── CHANNEL creation ──\n")

    check("initial count = 0",
          [': _T _CH1 CHAN-COUNT . ; _T'],
          "0 ")

    check("not closed initially",
          [': _T _CH1 CHAN-CLOSED? . ; _T'],
          "0 ")

    check("elem-size is 8 (1 cell)",
          [': _T _CH1 _CHAN-ESIZE @ . ; _T'],
          "8 ")

    check("capacity is 4",
          [': _T _CH1 _CHAN-CAP @ . ; _T'],
          "4 ")

    check("lock# is 6",
          [': _T _CH1 _CHAN-LOCK# @ . ; _T'],
          "6 ")

    check("head starts at 0",
          [': _T _CH1 _CHAN-HEAD @ . ; _T'],
          "0 ")

    check("tail starts at 0",
          [': _T _CH1 _CHAN-TAIL @ . ; _T'],
          "0 ")

    check("evt-nf initially SET (not full)",
          [': _T _CH1 _CHAN-EVT-NF EVT-SET? . ; _T'],
          "-1 ")

    check("evt-ne initially UNSET (empty)",
          [': _T _CH1 _CHAN-EVT-NE EVT-SET? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Constants ──\n")

    check("_CHAN-FIXED-CELLS is 15",
          [': _T _CHAN-FIXED-CELLS . ; _T'],
          "15 ")

    check("_CHAN-FIXED-SIZE is 120",
          [': _T _CHAN-FIXED-SIZE . ; _T'],
          "120 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Condition checks ──\n")

    check("empty channel is empty",
          [': _T _CH2 _CHAN-EMPTY? . ; _T'],
          "-1 ")

    check("empty channel is not full",
          [': _T _CH2 _CHAN-FULL? . ; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CHAN-TRY-SEND / CHAN-TRY-RECV basic ──\n")

    check("try-send on empty succeeds",
          [': _T 42 _CH2 CHAN-TRY-SEND . ; _T'],
          "-1 ")

    check("try-recv gets the value back",
          [': _T 42 _CH2 CHAN-TRY-SEND DROP _CH2 CHAN-TRY-RECV . . ; _T'],
          "-1 42 ")

    check("try-recv on empty returns 0 0",
          [': _T _CH2 CHAN-TRY-RECV . . ; _T'],
          "0 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CHAN-SEND / CHAN-RECV (fast-path) ──\n")

    check("send then recv returns value",
          [': _T 99 _CH2 CHAN-SEND _CH2 CHAN-RECV . ; _T'],
          "99 ")

    check("send multiple, recv in FIFO order",
          [': _T 10 _CH2 CHAN-SEND 20 _CH2 CHAN-SEND 30 _CH2 CHAN-SEND',
           '_CH2 CHAN-RECV . _CH2 CHAN-RECV . _CH2 CHAN-RECV . ; _T'],
          "10 20 30 ")

    check("count tracks sends",
          [': _T 1 _CH2 CHAN-SEND 2 _CH2 CHAN-SEND _CH2 CHAN-COUNT . ',
           '_CH2 CHAN-RECV DROP _CH2 CHAN-RECV DROP ; _T'],
          "2 ")

    check("count decreases after recv",
          [': _T 1 _CH2 CHAN-SEND 2 _CH2 CHAN-SEND _CH2 CHAN-RECV DROP',
           ' _CH2 CHAN-COUNT . _CH2 CHAN-RECV DROP ; _T'],
          "1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Fill to capacity ──\n")

    check("try-send fills up capacity 4",
          [': _T',
           '  1 _CH1 CHAN-TRY-SEND DROP',
           '  2 _CH1 CHAN-TRY-SEND DROP',
           '  3 _CH1 CHAN-TRY-SEND DROP',
           '  4 _CH1 CHAN-TRY-SEND DROP',
           '  _CH1 CHAN-COUNT .',
           '  5 _CH1 CHAN-TRY-SEND .    \\ should fail',
           '  _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '  _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '; _T'],
          "4 0 ")

    check("FIFO correct after filling",
          [': _T',
           '  11 _CH1 CHAN-TRY-SEND DROP',
           '  22 _CH1 CHAN-TRY-SEND DROP',
           '  33 _CH1 CHAN-TRY-SEND DROP',
           '  44 _CH1 CHAN-TRY-SEND DROP',
           '  _CH1 CHAN-RECV . _CH1 CHAN-RECV .',
           '  _CH1 CHAN-RECV . _CH1 CHAN-RECV .',
           '; _T'],
          "11 22 33 44 ")

    check("full channel is full",
          [': _T',
           '  1 _CH1 CHAN-TRY-SEND DROP',
           '  2 _CH1 CHAN-TRY-SEND DROP',
           '  3 _CH1 CHAN-TRY-SEND DROP',
           '  4 _CH1 CHAN-TRY-SEND DROP',
           '  _CH1 _CHAN-FULL? .',
           '  _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '  _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Wrap-around (ring head/tail wrapping) ──\n")

    check("head/tail wrap around correctly",
          [': _T',
           '  \\ Fill and drain twice to force wrap-around',
           '  1 _CH1 CHAN-SEND 2 _CH1 CHAN-SEND',
           '  3 _CH1 CHAN-SEND 4 _CH1 CHAN-SEND',
           '  _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '  _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '  \\ Second round: head and tail should wrap',
           '  100 _CH1 CHAN-SEND 200 _CH1 CHAN-SEND',
           '  300 _CH1 CHAN-SEND 400 _CH1 CHAN-SEND',
           '  _CH1 CHAN-RECV . _CH1 CHAN-RECV .',
           '  _CH1 CHAN-RECV . _CH1 CHAN-RECV .',
           '; _T'],
          "100 200 300 400 ")

    check("three rounds of wrap-around",
          [': _T',
           '  3 0 DO',
           '    I 10 * 1+ _CH1 CHAN-SEND',
           '    I 10 * 2 + _CH1 CHAN-SEND',
           '    _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '  LOOP',
           '  77 _CH1 CHAN-SEND _CH1 CHAN-RECV .',
           '; _T'],
          "77 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CHAN-CLOSE ──\n")

    check("CHAN-CLOSE sets closed flag",
          [': _T _CH3 CHAN-CLOSE _CH3 CHAN-CLOSED? . ; _T'],
          "-1 ")

    check("CHAN-TRY-SEND on closed returns 0",
          [': _T _CH3 CHAN-CLOSE 42 _CH3 CHAN-TRY-SEND . ; _T'],
          "0 ")

    check("CHAN-TRY-RECV on closed+empty returns 0 0",
          [': _T _CH3 CHAN-CLOSE _CH3 CHAN-TRY-RECV . . ; _T'],
          "0 0 ")

    check("CHAN-RECV on closed+empty returns 0",
          [': _T _CH3 CHAN-CLOSE _CH3 CHAN-RECV . ; _T'],
          "0 ")

    check("recv remaining items from closed channel",
          [': _T',
           '  50 _CH3 CHAN-SEND 60 _CH3 CHAN-SEND',
           '  _CH3 CHAN-CLOSE',
           '  _CH3 CHAN-RECV . _CH3 CHAN-RECV .',
           '  _CH3 CHAN-RECV .   \\ closed+empty = 0',
           '; _T'],
          "50 60 0 ")

    check("CHAN-SEND on closed throws",
          [': _chan-send-cl 42 _CH3 CHAN-SEND ;',
           ': _T _CH3 CHAN-CLOSE [\'] _chan-send-cl CATCH . ." |done" ; _T'],
          "-1 |done")

    # ────────────────────────────────────────────────────────────────
    print("\n── CHAN-SELECT ──\n")

    check("select with one ready channel",
          [': _T',
           '  77 _CH4 CHAN-SEND',
           '  _CH4 _CH5 2 CHAN-SELECT',
           '  . .   \\ should be val=77 idx=0',
           '; _T'],
          "77 0 ")

    check("select picks second channel",
          [': _T',
           '  88 _CH5 CHAN-SEND',
           '  _CH4 _CH5 2 CHAN-SELECT',
           '  . .   \\ should be val=88 idx=1',
           '; _T'],
          "88 1 ")

    check("select all closed returns -1 0",
          [': _T',
           '  _CH4 CHAN-CLOSE _CH5 CHAN-CLOSE',
           '  _CH4 _CH5 2 CHAN-SELECT',
           '  . .   \\ val=0 idx=-1',
           '; _T'],
          "0 -1 ")

    check("select drains closed channel with data first",
          [': _T',
           '  55 _CH4 CHAN-SEND',
           '  _CH4 CHAN-CLOSE _CH5 CHAN-CLOSE',
           '  _CH4 _CH5 2 CHAN-SELECT',
           '  . .   \\ val=55, idx=0',
           '; _T'],
          "55 0 ")

    check("select with single channel",
          [': _T',
           '  42 _CH4 CHAN-SEND',
           '  _CH4 1 CHAN-SELECT . .',
           '; _T'],
          "42 0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CHAN-SEND-BUF / CHAN-RECV-BUF ──\n")

    check("send-buf and recv-buf round-trip (1-cell channel)",
          [': _T',
           '   99 _V1 !',
           '   _V1 _CH2 CHAN-SEND-BUF',
           '   _V2 _CH2 CHAN-RECV-BUF . \\ flag',
           '   _V2 @ .                  \\ value',
           '; _T'],
          "-1 99 ")

    check("send-buf / recv-buf with 2-cell elements",
          [': _T',
           '   111 _TBUF !  222 _TBUF 8 + !',
           '   _TBUF _BCHX CHAN-SEND-BUF',
           '   0 _TBUF !  0 _TBUF 8 + !  \\ clear buf',
           '   _TBUF _BCHX CHAN-RECV-BUF . \\ flag',
           '   _TBUF @ . _TBUF 8 + @ .    \\ values',
           '; _T'],
          "-1 111 222 ")

    check("recv-buf on closed+empty returns 0",
          [': _T',
           '   _CH2 CHAN-CLOSE',
           '   _V1 _CH2 CHAN-RECV-BUF .',
           '; _T'],
          "0 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── CHAN-INFO ──\n")

    check("chan-info shows open status",
          [': _T _CH2 CHAN-INFO ; _T'],
          "[channel")

    check("chan-info shows lock#",
          [': _T _CH2 CHAN-INFO ; _T'],
          "lock#=")

    # ────────────────────────────────────────────────────────────────
    print("\n── Event signaling ──\n")

    check("send sets evt-ne (not-empty)",
          [': _T',
           '  42 _CH2 CHAN-SEND',
           '  _CH2 _CHAN-EVT-NE EVT-SET? .',
           '  _CH2 CHAN-RECV DROP',
           '; _T'],
          "-1 ")

    check("recv sets evt-nf (not-full)",
          [': _T',
           '  1 _CH1 CHAN-TRY-SEND DROP',
           '  2 _CH1 CHAN-TRY-SEND DROP',
           '  3 _CH1 CHAN-TRY-SEND DROP',
           '  4 _CH1 CHAN-TRY-SEND DROP',
           '  \\ ch1 is now full',
           '  _CH1 CHAN-RECV DROP  \\ frees one slot',
           '  _CH1 _CHAN-EVT-NF EVT-SET? .',
           '  _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP _CH1 CHAN-RECV DROP',
           '; _T'],
          "-1 ")

    # ────────────────────────────────────────────────────────────────
    print("\n── Edge cases ──\n")

    check("send and recv single value many times",
          [': _T',
           '  10 0 DO',
           '    I _CH2 CHAN-SEND',
           '    _CH2 CHAN-RECV DROP',
           '  LOOP',
           '  _CH2 CHAN-COUNT .',
           '; _T'],
          "0 ")

    check("capacity-1 send-recv cycles",
          [': _T',
           '  100 _CH1 CHAN-SEND 200 _CH1 CHAN-SEND 300 _CH1 CHAN-SEND',
           '  _CH1 CHAN-RECV . _CH1 CHAN-RECV . _CH1 CHAN-RECV .',
           '  400 _CH1 CHAN-SEND 500 _CH1 CHAN-SEND 600 _CH1 CHAN-SEND',
           '  _CH1 CHAN-RECV . _CH1 CHAN-RECV . _CH1 CHAN-RECV .',
           '; _T'],
          "100 200 300 400 500 600 ")

    check("zero value can be sent/received",
          [': _T 0 _CH2 CHAN-SEND _CH2 CHAN-RECV . ; _T'],
          "0 ")

    check("large values (near 64-bit max)",
          [': _T',
           '  9999999999 _CH2 CHAN-SEND',
           '  _CH2 CHAN-RECV .',
           '; _T'],
          "9999999999 ")

    check("negative values",
          [': _T -1 _CH2 CHAN-SEND _CH2 CHAN-RECV . ; _T'],
          "-1 ")

    check("try-send on closed channel is 0",
          [': _T',
           '  _CH3 CHAN-CLOSE',
           '  123 _CH3 CHAN-TRY-SEND .',
           '; _T'],
          "0 ")

    check("send-buf on closed throws",
          [': _sbuf-cl _V1 _CH3 CHAN-SEND-BUF ;',
           ': _T _CH3 CHAN-CLOSE [\'] _sbuf-cl CATCH . ." |ok" ; _T'],
          "-1 |ok")

    # ────────────────────────────────────────────────────────────────
    print("\n── Summary ──\n")
    total = _pass + _fail
    print(f"  {_pass}/{total} passed, {_fail} failed.")
    if _fail:
        sys.exit(1)
    else:
        print("  All tests passed!")
