#!/usr/bin/env python3
"""Diagnostic for Batch A features: PgUp/PgDn, Ctrl+Left/Right, dirty indicator."""

import os, sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(SCRIPT_DIR, "emu")
AK         = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

_DEP_PATHS = [
    os.path.join(AK, "concurrency", "event.f"),
    os.path.join(AK, "concurrency", "semaphore.f"),
    os.path.join(AK, "concurrency", "guard.f"),
    os.path.join(AK, "utils",       "string.f"),
    os.path.join(AK, "math",        "fp32.f"),
    os.path.join(AK, "math",        "fixed.f"),
    os.path.join(AK, "text",        "utf8.f"),
    os.path.join(AK, "markup",      "core.f"),
    os.path.join(AK, "markup",      "xml.f"),
    os.path.join(AK, "liraq",       "state-tree.f"),
    os.path.join(AK, "liraq",       "lel.f"),
    os.path.join(AK, "liraq",       "uidl.f"),
    os.path.join(AK, "liraq",       "uidl-chrome.f"),
    os.path.join(AK, "tui",         "cell.f"),
    os.path.join(AK, "tui",         "ansi.f"),
    os.path.join(AK, "tui",         "screen.f"),
    os.path.join(AK, "tui",         "draw.f"),
    os.path.join(AK, "tui",         "tui-sidecar.f"),
    os.path.join(AK, "tui",         "box.f"),
    os.path.join(AK, "tui",         "region.f"),
    os.path.join(AK, "tui",         "layout.f"),
    os.path.join(AK, "tui",         "keys.f"),
    os.path.join(AK, "tui",         "widget.f"),
    os.path.join(AK, "tui",         "widgets", "tree.f"),
    os.path.join(AK, "tui",         "widgets", "input.f"),
    os.path.join(AK, "tui",         "widgets", "textarea.f"),
    os.path.join(AK, "tui",         "uidl-tui.f"),
]

# ─── helpers (same pattern as test_uidl_tui.py) ───

def _load_bios():
    with open(BIOS_PATH) as f:
        return assemble(f.read())

def _load_forth_lines(path):
    lines = []
    with open(path) as f:
        for line in f:
            s = line.rstrip("\n\r")
            if s.startswith("REQUIRE ") or s.startswith("PROVIDED "):
                continue
            lines.append(s)
    return lines

def _next_line_chunk(data: bytes, pos: int) -> bytes:
    nl = data.find(b"\n", pos)
    if nl == -1:
        return data[pos:]
    return data[pos:nl+1]

def capture_uart(sys_obj):
    buf = []
    sys_obj.uart.on_tx = lambda b, _b=buf: _b.append(b)
    return buf

def uart_text(buf):
    return "".join(chr(b) if (0x20 <= b < 0x7F or b in (10,13,9)) else "" for b in buf)

def save_cpu_state(cpu):
    return {
        'pc': cpu.pc, 'regs': list(cpu.regs),
        'psel': cpu.psel, 'xsel': cpu.xsel, 'spsel': cpu.spsel,
        'flag_z': cpu.flag_z, 'flag_c': cpu.flag_c,
        'flag_n': cpu.flag_n, 'flag_v': cpu.flag_v,
        'flag_p': cpu.flag_p, 'flag_g': cpu.flag_g,
        'flag_i': cpu.flag_i, 'flag_s': cpu.flag_s,
        'd_reg': cpu.d_reg, 'q_out': cpu.q_out, 't_reg': cpu.t_reg,
        'ivt_base': cpu.ivt_base, 'ivec_id': cpu.ivec_id,
        'trap_addr': cpu.trap_addr,
        'halted': cpu.halted, 'idle': cpu.idle,
        'cycle_count': cpu.cycle_count,
        '_ext_modifier': cpu._ext_modifier,
    }

def restore_cpu_state(cpu, state):
    cpu.pc = state['pc']
    cpu.regs[:] = state['regs']
    for k in ('psel','xsel','spsel','flag_z','flag_c','flag_n','flag_v',
              'flag_p','flag_g','flag_i','flag_s','d_reg','q_out','t_reg',
              'ivt_base','ivec_id','trap_addr','halted','idle',
              'cycle_count','_ext_modifier'):
        setattr(cpu, k, state[k])

_snapshot = None

def build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return

    bios_code = _load_bios()
    with open(KDOS_PATH) as f:
        kdos_lines = f.read().splitlines()

    dep_lines = []
    for p in _DEP_PATHS:
        dep_lines.extend(_load_forth_lines(p))

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 800_000_000

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    if " err" in text.lower() or "not found" in text.lower():
        print("[WARN] Possible errors during load:")
        for line in text.splitlines()[-10:]:
            print("  ", line)

    _snapshot = {
        'sys': sys_obj,
        'cpu_state': save_cpu_state(sys_obj.cpu),
        'mem': bytearray(sys_obj._shared_mem),
    }

def run_forth(lines, max_steps=80_000_000):
    build_snapshot()
    sys_obj = _snapshot['sys']
    restore_cpu_state(sys_obj.cpu, _snapshot['cpu_state'])
    sys_obj._shared_mem[:] = _snapshot['mem']

    buf = capture_uart(sys_obj)

    payload = "\n".join(lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0

    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk)
                pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    return uart_text(buf)

# ─── test framework ───

_pass_count = 0
_fail_count = 0

def check(name, lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    out = run_forth(lines)
    ok = False
    if expected is not None:
        ok = expected in out
    elif check_fn is not None:
        ok = check_fn(out)
    if ok:
        print(f"  PASS  {name}")
        _pass_count += 1
    else:
        print(f"  FAIL  {name}")
        print(f"        output: {out.strip()!r:.200}")
        _fail_count += 1


# ─── setup templates ───

_SETUP_30LINES = [
    '0 0 10 40 RGN-NEW CONSTANT _T-RGN',
    'CREATE _T-BUF 4096 ALLOT',
    '_T-RGN _T-BUF 4096 TXTA-NEW CONSTANT _T-W',
    # Fill 30 lines: "Line 00\n" ... "Line 29\n"  (8 bytes each = 240 total)
    ': _FILL-LINES',
    '  30 0 DO',
    '    [CHAR] L _T-BUF I 8 * + 0 + C!',
    '    [CHAR] i _T-BUF I 8 * + 1 + C!',
    '    [CHAR] n _T-BUF I 8 * + 2 + C!',
    '    [CHAR] e _T-BUF I 8 * + 3 + C!',
    '    32      _T-BUF I 8 * + 4 + C!',
    '    I 10 / [CHAR] 0 + _T-BUF I 8 * + 5 + C!',
    '    I 10 MOD [CHAR] 0 + _T-BUF I 8 * + 6 + C!',
    '    10      _T-BUF I 8 * + 7 + C!',
    '  LOOP',
    '  240 _T-W 56 + !',      # buf-len = 30 * 8 = 240
    '  0 _T-W 64 + !',        # cursor = 0
    ';',
    '_FILL-LINES',
]


def main():
    global _pass_count, _fail_count
    print("[*] Building snapshot...")
    build_snapshot()
    print("[*] Ready.\n")

    # ── Page Up/Down ──
    print("[Page Up/Down]")

    check("pgdn-jumps-to-line-10", _SETUP_30LINES + [
        '0 _T-W 64 + !',          # cursor at line 0
        '_T-W _TXTA-W !',
        '_TXTA-PGDN',
        '_TXTA-CURSOR-LINE . CR',
    ], "10")

    check("pgup-from-line-10-to-0", _SETUP_30LINES + [
        # line 10 = byte offset 80
        '80 _T-W 64 + !',
        '_T-W _TXTA-W !',
        '_TXTA-PGUP',
        '_TXTA-CURSOR-LINE . CR',
    ], "0")

    check("pgdn-clamp-at-end", _SETUP_30LINES + [
        # line 28 = byte offset 224; 30 lines + trailing NL → 31 lines (0..30)
        '224 _T-W 64 + !',
        '_T-W _TXTA-W !',
        '_TXTA-PGDN',
        '_TXTA-CURSOR-LINE . CR',
    ], "30")

    check("pgup-clamp-at-top", _SETUP_30LINES + [
        # line 2 = byte offset 16
        '16 _T-W 64 + !',
        '_T-W _TXTA-W !',
        '_TXTA-PGUP',
        '_TXTA-CURSOR-LINE . CR',
    ], "0")
    print()

    # ── Word Movement ──
    print("[Word Movement]")

    _WORD_SETUP = [
        '0 0 10 40 RGN-NEW CONSTANT _W-RGN',
        'CREATE _W-BUF 256 ALLOT',
        '_W-RGN _W-BUF 256 TXTA-NEW CONSTANT _W-W',
        'S" hello world foo" _W-W TXTA-SET-TEXT',
    ]

    check("word-right-from-0", _WORD_SETUP + [
        '0 _W-W 64 + !',
        '_W-W _TXTA-W !',
        '_TXTA-WORD-RIGHT',
        '_TXTA-CURSOR . CR',
    ], "6")

    check("word-right-twice", _WORD_SETUP + [
        '0 _W-W 64 + !',
        '_W-W _TXTA-W !',
        '_TXTA-WORD-RIGHT _TXTA-WORD-RIGHT',
        '_TXTA-CURSOR . CR',
    ], "12")

    check("word-left-from-end", _WORD_SETUP + [
        '15 _W-W 64 + !',
        '_W-W _TXTA-W !',
        '_TXTA-WORD-LEFT',
        '_TXTA-CURSOR . CR',
    ], "12")

    check("word-left-twice", _WORD_SETUP + [
        '15 _W-W 64 + !',
        '_W-W _TXTA-W !',
        '_TXTA-WORD-LEFT _TXTA-WORD-LEFT',
        '_TXTA-CURSOR . CR',
    ], "6")

    check("word-right-at-end-noop", _WORD_SETUP + [
        '15 _W-W 64 + !',
        '_W-W _TXTA-W !',
        '_TXTA-WORD-RIGHT',
        '_TXTA-CURSOR . CR',
    ], "15")

    check("word-left-at-start-noop", _WORD_SETUP + [
        '0 _W-W 64 + !',
        '_W-W _TXTA-W !',
        '_TXTA-WORD-LEFT',
        '_TXTA-CURSOR . CR',
    ], "0")
    print()

    # ── On-Change Callback ──
    print("[On-Change Callback]")

    _CB_SETUP = [
        '0 0 5 40 RGN-NEW CONSTANT _C-RGN',
        'CREATE _C-BUF 256 ALLOT',
        '_C-RGN _C-BUF 256 TXTA-NEW CONSTANT _C-W',
        'S" abc" _C-W TXTA-SET-TEXT',
        'VARIABLE _HIT  0 _HIT !',
        ': _ON-CHG  DROP  _HIT @ 1+ _HIT ! ;',
        "' _ON-CHG _C-W TXTA-ON-CHANGE",
    ]

    check("on-change-insert", _CB_SETUP + [
        '_C-W _TXTA-W !',
        '[CHAR] X _TXTA-INSERT',
        '_HIT @ . CR',
    ], "1")

    check("on-change-delete", _CB_SETUP + [
        '0 _C-W 64 + !',
        '_C-W _TXTA-W !',
        '_TXTA-DELETE',
        '_HIT @ . CR',
    ], "1")

    check("on-change-backspace", _CB_SETUP + [
        '2 _C-W 64 + !',
        '_C-W _TXTA-W !',
        '_TXTA-BACKSPACE',
        '_HIT @ . CR',
    ], "1")
    print()

    # ── Summary ──
    total = _pass_count + _fail_count
    print("=" * 50)
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    print("=" * 50)
    return 0 if _fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
