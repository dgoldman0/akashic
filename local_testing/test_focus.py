#!/usr/bin/env python3
"""Test suite for focus.f (Focus Manager) and focus-2d.f (Spatial Navigation).

Uses the Megapad-64 emulator to boot KDOS, load the full TUI dependency
chain through focus.f + focus-2d.f, then exercises:
  - focus.f: ring-topology tab-cycle, add/remove/set/get/clear/dispatch
  - focus-2d.f: directional focus, synthetic clicks, F2D-DISPATCH
"""
import os
import sys
import time

# ──────── paths ────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
AK         = os.path.join(ROOT_DIR, "akashic")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# Dependency order: everything through focus-2d.f
_DEP_PATHS = [
    os.path.join(AK, "text",  "utf8.f"),
    os.path.join(AK, "tui",   "ansi.f"),
    os.path.join(AK, "tui",   "keys.f"),
    os.path.join(AK, "tui",   "cell.f"),
    os.path.join(AK, "tui",   "screen.f"),
    os.path.join(AK, "tui",   "draw.f"),
    os.path.join(AK, "tui",   "box.f"),
    os.path.join(AK, "tui",   "region.f"),
    os.path.join(AK, "tui",   "layout.f"),
    os.path.join(AK, "tui",   "widget.f"),
    os.path.join(AK, "tui",   "focus.f"),
    os.path.join(AK, "tui",   "focus-2d.f"),
]

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers  (same pattern as test_tui.py)
# ═══════════════════════════════════════════════════════════════════

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
        for b in buf
    )

def save_cpu_state(cpu):
    return {
        'pc': cpu.pc,
        'regs': list(cpu.regs),
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
    for k in ('psel', 'xsel', 'spsel',
              'flag_z', 'flag_c', 'flag_n', 'flag_v',
              'flag_p', 'flag_g', 'flag_i', 'flag_s',
              'd_reg', 'q_out', 't_reg',
              'ivt_base', 'ivec_id', 'trap_addr',
              'halted', 'idle', 'cycle_count', '_ext_modifier'):
        setattr(cpu, k, state[k])


def build_snapshot():
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + TUI stack + focus + focus-2d ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    dep_lines = []
    for p in _DEP_PATHS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        dep_lines.extend(_load_forth_lines(p))

    # Test helpers:
    # _MOCK-DRAW / _MOCK-HANDLE: dummy draw / handle xts
    # _MK-MOCK ( row col h w id -- wdg )  Allocate a mock widget with a region
    # _EV: event buffer (3 cells = 24 bytes)
    # _HIT-ID: stores which widget-id the handler saw
    test_helpers = [
        'VARIABLE _HIT-ID',
        'CREATE _EV 24 ALLOT',
        ': _MOCK-DRAW ( wdg -- ) DROP ;',
        # handle-xt: ( ev wdg -- consumed? ) — stores wdg _WDG-O-TYPE val in _HIT-ID, returns -1
        ': _MOCK-HANDLE ( ev wdg -- flag ) _WDG-O-TYPE + @ _HIT-ID ! DROP -1 ;',
        # _MK-MOCK ( row col h w id -- wdg )
        #   Creates a region, allocates widget (40 bytes), inits header
        ': _MK-MOCK',
        '  >R                         \\ save id on return stack',
        '  RGN-NEW                    \\ ( rgn ) from row col h w',
        '  40 ALLOCATE DROP           \\ ( rgn wdg-addr )',
        '  DUP R>                     \\ ( rgn wdg wdg id )',
        '  3 PICK                     \\ ( rgn wdg wdg id rgn )',
        "  ['] _MOCK-DRAW",
        "  ['] _MOCK-HANDLE",
        '  _WDG-INIT                  \\ ( rgn wdg ) — header filled',
        '  NIP                        \\ ( wdg )',
        ';',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + dep_lines + test_helpers
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
    err_lines = [l for l in text.strip().split('\n')
                 if '?' in l and ('not found' in l.lower() or 'undefined' in l.lower())]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-20:]:
            print(f"    {ln}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=80_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)

    payload = "\n".join(lines) + "\nBYE\n"
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


# ═══════════════════════════════════════════════════════════════════
#  Test framework
# ═══════════════════════════════════════════════════════════════════

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected=None, check_fn=None, not_expected=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()

    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True

    if not_expected is not None and ok:
        ok = not_expected not in clean

    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            print(f"        expected: {expected!r}")
        if not_expected is not None:
            print(f"        NOT expected: {not_expected!r}")
        last = clean.split('\n')[-8:]
        print(f"        got (last lines):")
        for l in last:
            print(f"          {l}")


# ═══════════════════════════════════════════════════════════════════
#  Mock widget helpers (Forth code)
# ═══════════════════════════════════════════════════════════════════

def _mk(row, col, h, w, wid):
    """Return Forth line creating a mock widget and leaving it on stack."""
    return f'{row} {col} {h} {w} {wid} _MK-MOCK'

def _mk_named(name, row, col, h, w, wid):
    """Return Forth lines creating a mock widget stored in a VARIABLE."""
    return [
        f'VARIABLE {name}',
        f'{_mk(row, col, h, w, wid)} {name} !',
    ]


# ═══════════════════════════════════════════════════════════════════
#  §A — Compilation
# ═══════════════════════════════════════════════════════════════════

def test_compilation():
    check("compile-clean", [
        '." COMPILE-OK" CR',
    ], "COMPILE-OK")


# ═══════════════════════════════════════════════════════════════════
#  §B — FOC-ADD / FOC-GET / FOC-COUNT
# ═══════════════════════════════════════════════════════════════════

def test_add_get():
    """Add one widget, FOC-GET returns it."""
    check("add-get", [
        'FOC-CLEAR',
        _mk(0, 0, 1, 10, 101),
        'DUP FOC-ADD',
        'FOC-GET = IF ." SAME" ELSE ." DIFF" THEN CR',
    ], "SAME")

def test_count():
    """FOC-COUNT tracks additions."""
    check("count-add", [
        'FOC-CLEAR',
        _mk(0, 0, 1, 10, 1),  'FOC-ADD',
        _mk(1, 0, 1, 10, 2),  'FOC-ADD',
        _mk(2, 0, 1, 10, 3),  'FOC-ADD',
        'FOC-COUNT . CR',
    ], "3")

def test_add_duplicate():
    """Adding same widget twice doesn't increase count."""
    check("add-dup", [
        'FOC-CLEAR',
        _mk(0, 0, 1, 10, 1),
        'DUP FOC-ADD',
        'DUP FOC-ADD',
        'FOC-COUNT . CR',
        'DROP',
    ], "1")

def test_empty_get():
    """FOC-GET returns 0 on empty chain."""
    check("empty-get", [
        'FOC-CLEAR',
        'FOC-GET . CR',
    ], "0")


# ═══════════════════════════════════════════════════════════════════
#  §C — FOC-NEXT / FOC-PREV (Ring Cycle)
# ═══════════════════════════════════════════════════════════════════

def test_next_cycle():
    """FOC-NEXT cycles through 3 widgets and wraps."""
    check("next-cycle", [
        'FOC-CLEAR',
    ] + _mk_named('_W1', 0, 0, 1, 10, 11) + [
        '_W1 @ FOC-ADD',
    ] + _mk_named('_W2', 1, 0, 1, 10, 22) + [
        '_W2 @ FOC-ADD',
    ] + _mk_named('_W3', 2, 0, 1, 10, 33) + [
        '_W3 @ FOC-ADD',
        # Current is _W1 (first added)
        # Insert-after-current => ring order: W1→W3→W2→W1
        'FOC-GET _W1 @ = . CR',           # -1
        'FOC-NEXT FOC-GET _W3 @ = . CR',  # -1
        'FOC-NEXT FOC-GET _W2 @ = . CR',  # -1
        'FOC-NEXT FOC-GET _W1 @ = . CR',  # -1 (wraps)
    ], check_fn=lambda o: o.count('-1') >= 4)

def test_prev_cycle():
    """FOC-PREV cycles backwards."""
    check("prev-cycle", [
        'FOC-CLEAR',
    ] + _mk_named('_W1', 0, 0, 1, 10, 11) + [
        '_W1 @ FOC-ADD',
    ] + _mk_named('_W2', 1, 0, 1, 10, 22) + [
        '_W2 @ FOC-ADD',
    ] + _mk_named('_W3', 2, 0, 1, 10, 33) + [
        '_W3 @ FOC-ADD',
        # Current is _W1; ring order W1→W3→W2, so prev goes W1→W2→W3
        'FOC-PREV FOC-GET _W2 @ = . CR',  # -1 (wraps back)
        'FOC-PREV FOC-GET _W3 @ = . CR',  # -1
    ], check_fn=lambda o: o.count('-1') >= 2)

def test_next_single():
    """FOC-NEXT with one widget stays on it."""
    check("next-single", [
        'FOC-CLEAR',
        _mk(0, 0, 1, 10, 42),
        'DUP FOC-ADD',
        'FOC-NEXT',
        'FOC-GET = IF ." SAME" ELSE ." DIFF" THEN CR',
    ], "SAME")

def test_next_empty():
    """FOC-NEXT on empty chain doesn't crash."""
    check("next-empty", [
        'FOC-CLEAR',
        'FOC-NEXT',
        '." OK" CR',
    ], "OK")


# ═══════════════════════════════════════════════════════════════════
#  §D — FOC-SET
# ═══════════════════════════════════════════════════════════════════

def test_set_explicit():
    """FOC-SET moves focus to specific widget."""
    check("set-explicit", [
        'FOC-CLEAR',
    ] + _mk_named('_W1', 0, 0, 1, 10, 11) + [
        '_W1 @ FOC-ADD',
    ] + _mk_named('_W2', 1, 0, 1, 10, 22) + [
        '_W2 @ FOC-ADD',
        '_W2 @ FOC-SET',
        'FOC-GET _W2 @ = IF ." SET-OK" ELSE ." SET-FAIL" THEN CR',
    ], "SET-OK")

def test_set_not_in_chain():
    """FOC-SET with widget not in chain does nothing."""
    check("set-not-in-chain", [
        'FOC-CLEAR',
    ] + _mk_named('_W1', 0, 0, 1, 10, 11) + [
        '_W1 @ FOC-ADD',
    ] + _mk_named('_W2', 1, 0, 1, 10, 22) + [
        # _W2 NOT added
        '_W2 @ FOC-SET',
        'FOC-GET _W1 @ = IF ." UNCHANGED" ELSE ." CHANGED" THEN CR',
    ], "UNCHANGED")

def test_set_updates_flags():
    """FOC-SET clears old FOCUSED flag, sets new one."""
    check("set-flags", [
        'FOC-CLEAR',
    ] + _mk_named('_W1', 0, 0, 1, 10, 11) + [
        '_W1 @ FOC-ADD',
    ] + _mk_named('_W2', 1, 0, 1, 10, 22) + [
        '_W2 @ FOC-ADD',
        '_W1 @ FOC-SET',
        # W1 should have FOCUSED flag
        '_W1 @ WDG-FOCUSED? IF ." W1-FOC" ELSE ." W1-NO" THEN CR',
        '_W2 @ FOC-SET',
        # Now W2 focused, W1 not
        '_W2 @ WDG-FOCUSED? IF ." W2-FOC" ELSE ." W2-NO" THEN CR',
        '_W1 @ WDG-FOCUSED? 0= IF ." W1-CLR" ELSE ." W1-STILL" THEN CR',
    ], check_fn=lambda o: "W1-FOC" in o and "W2-FOC" in o and "W1-CLR" in o)


# ═══════════════════════════════════════════════════════════════════
#  §E — FOC-REMOVE
# ═══════════════════════════════════════════════════════════════════

def test_remove_middle():
    """Removing a non-focused widget preserves current focus."""
    check("remove-middle", [
        'FOC-CLEAR',
    ] + _mk_named('_W1', 0, 0, 1, 10, 11) + [
        '_W1 @ FOC-ADD',
    ] + _mk_named('_W2', 1, 0, 1, 10, 22) + [
        '_W2 @ FOC-ADD',
    ] + _mk_named('_W3', 2, 0, 1, 10, 33) + [
        '_W3 @ FOC-ADD',
        '_W2 @ FOC-REMOVE',
        'FOC-COUNT . CR',
        'FOC-GET _W1 @ = IF ." FOCUS-OK" ELSE ." FOCUS-MOVED" THEN CR',
    ], check_fn=lambda o: "2" in o and "FOCUS-OK" in o)

def test_remove_focused():
    """Removing focused widget moves focus to next."""
    check("remove-focused", [
        'FOC-CLEAR',
    ] + _mk_named('_W1', 0, 0, 1, 10, 11) + [
        '_W1 @ FOC-ADD',
    ] + _mk_named('_W2', 1, 0, 1, 10, 22) + [
        '_W2 @ FOC-ADD',
        # Focus is on _W1, remove it
        '_W1 @ FOC-REMOVE',
        'FOC-GET _W2 @ = IF ." MOVED" ELSE ." LOST" THEN CR',
        'FOC-COUNT . CR',
    ], check_fn=lambda o: "MOVED" in o and "1" in o)

def test_remove_last():
    """Removing the only widget clears chain."""
    check("remove-last", [
        'FOC-CLEAR',
        _mk(0, 0, 1, 10, 1), 'DUP FOC-ADD FOC-REMOVE',
        'FOC-GET . CR',
        'FOC-COUNT . CR',
    ], check_fn=lambda o: "0" in o)


# ═══════════════════════════════════════════════════════════════════
#  §F — FOC-CLEAR
# ═══════════════════════════════════════════════════════════════════

def test_clear():
    """FOC-CLEAR resets everything."""
    check("clear-all", [
        'FOC-CLEAR',
        _mk(0, 0, 1, 10, 1), 'FOC-ADD',
        _mk(1, 0, 1, 10, 2), 'FOC-ADD',
        'FOC-CLEAR',
        'FOC-GET . CR',
        'FOC-COUNT . CR',
    ], check_fn=lambda o: o.count("0") >= 2)


# ═══════════════════════════════════════════════════════════════════
#  §G — FOC-DISPATCH
# ═══════════════════════════════════════════════════════════════════

def test_dispatch():
    """FOC-DISPATCH sends event to focused widget's handler."""
    check("dispatch-hit", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
    ] + _mk_named('_W1', 0, 0, 1, 10, 77) + [
        '_W1 @ FOC-ADD',
        '_EV FOC-DISPATCH',
        '_HIT-ID @ . CR',
    ], "77")

def test_dispatch_empty():
    """FOC-DISPATCH on empty chain doesn't crash."""
    check("dispatch-empty", [
        'FOC-CLEAR',
        '_EV FOC-DISPATCH',
        '." OK" CR',
    ], "OK")


# ═══════════════════════════════════════════════════════════════════
#  §H — FOC-EACH
# ═══════════════════════════════════════════════════════════════════

def test_each():
    """FOC-EACH visits all widgets."""
    check("each-visits", [
        'FOC-CLEAR',
        'VARIABLE _ECNT  0 _ECNT !',
        ': _INC-CNT ( wdg -- ) DROP 1 _ECNT +! ;',
        _mk(0, 0, 1, 10, 1), 'FOC-ADD',
        _mk(1, 0, 1, 10, 2), 'FOC-ADD',
        _mk(2, 0, 1, 10, 3), 'FOC-ADD',
        "['] _INC-CNT FOC-EACH",
        '_ECNT @ . CR',
    ], "3")

def test_each_empty():
    """FOC-EACH on empty chain doesn't crash."""
    check("each-empty", [
        'FOC-CLEAR',
        ': _NOP-EACH ( wdg -- ) DROP ;',
        "['] _NOP-EACH FOC-EACH",
        '." OK" CR',
    ], "OK")


# ═══════════════════════════════════════════════════════════════════
#  §I — F2D Directional Navigation
# ═══════════════════════════════════════════════════════════════════

# Layout:
#           col 0       col 40
#  row 0:   [  W-TL  ]  [  W-TR  ]
#  row 12:  [  W-BL  ]  [  W-BR  ]

def _setup_grid():
    """Return Forth lines setting up 4 widgets in a 2×2 grid."""
    lines = ['FOC-CLEAR']
    lines += _mk_named('_TL', 0,  0,  6, 20, 1)
    lines += _mk_named('_TR', 0,  40, 6, 20, 2)
    lines += _mk_named('_BL', 12, 0,  6, 20, 3)
    lines += _mk_named('_BR', 12, 40, 6, 20, 4)
    lines += [
        '_TL @ FOC-ADD',
        '_TR @ FOC-ADD',
        '_BL @ FOC-ADD',
        '_BR @ FOC-ADD',
        '_TL @ FOC-SET',  # Start at top-left
    ]
    return lines


def test_f2d_down():
    """F2D-DOWN from top-left moves to bottom-left."""
    check("f2d-down", _setup_grid() + [
        'F2D-DOWN',
        'FOC-GET _BL @ = IF ." BL" ELSE ." OTHER" THEN CR',
    ], "BL")

def test_f2d_up():
    """F2D-UP from bottom-left moves to top-left."""
    check("f2d-up", _setup_grid() + [
        '_BL @ FOC-SET',
        'F2D-UP',
        'FOC-GET _TL @ = IF ." TL" ELSE ." OTHER" THEN CR',
    ], "TL")

def test_f2d_right():
    """F2D-RIGHT from top-left moves to top-right."""
    check("f2d-right", _setup_grid() + [
        'F2D-RIGHT',
        'FOC-GET _TR @ = IF ." TR" ELSE ." OTHER" THEN CR',
    ], "TR")

def test_f2d_left():
    """F2D-LEFT from top-right moves to top-left."""
    check("f2d-left", _setup_grid() + [
        '_TR @ FOC-SET',
        'F2D-LEFT',
        'FOC-GET _TL @ = IF ." TL" ELSE ." OTHER" THEN CR',
    ], "TL")

def test_f2d_diagonal_bias():
    """F2D-DOWN from top-right prefers bottom-right (same column)."""
    check("f2d-diag-bias", _setup_grid() + [
        '_TR @ FOC-SET',
        'F2D-DOWN',
        'FOC-GET _BR @ = IF ." BR" ELSE ." OTHER" THEN CR',
    ], "BR")

def test_f2d_no_candidate():
    """F2D-UP from top-left stays (no widget above)."""
    check("f2d-no-up", _setup_grid() + [
        'F2D-UP',
        'FOC-GET _TL @ = IF ." STAYED" ELSE ." MOVED" THEN CR',
    ], "STAYED")

def test_f2d_empty():
    """F2D-DOWN on empty chain doesn't crash."""
    check("f2d-empty", [
        'FOC-CLEAR',
        'F2D-DOWN',
        '." OK" CR',
    ], "OK")


# ═══════════════════════════════════════════════════════════════════
#  §J — F2D Synthetic Clicks
# ═══════════════════════════════════════════════════════════════════

def test_click_left():
    """F2D-CLICK-L dispatches to focused widget's handler."""
    check("click-left", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
    ] + _mk_named('_W1', 5, 10, 3, 20, 55) + [
        '_W1 @ FOC-ADD',
        'F2D-CLICK-L',
        '_HIT-ID @ . CR',
    ], "55")

def test_click_empty():
    """F2D-CLICK-L on empty chain doesn't crash."""
    check("click-empty", [
        'FOC-CLEAR',
        'F2D-CLICK-L',
        '." OK" CR',
    ], "OK")


# ═══════════════════════════════════════════════════════════════════
#  §K — F2D-DISPATCH (key routing)
# ═══════════════════════════════════════════════════════════════════

def test_dispatch_alt_down():
    """F2D-DISPATCH handles Alt+Down."""
    check("f2d-dispatch-down", _setup_grid() + [
        # Build a synthetic event: special, KEY-DOWN, MOD-ALT
        'KEY-T-SPECIAL _EV !',
        'KEY-DOWN _EV 8 + !',
        'KEY-MOD-ALT _EV 16 + !',
        '_EV F2D-DISPATCH . CR',
        'FOC-GET _BL @ = IF ." BL" ELSE ." OTHER" THEN CR',
    ], check_fn=lambda o: "-1" in o and "BL" in o)

def test_dispatch_alt_right():
    """F2D-DISPATCH handles Alt+Right."""
    check("f2d-dispatch-right", _setup_grid() + [
        'KEY-T-SPECIAL _EV !',
        'KEY-RIGHT _EV 8 + !',
        'KEY-MOD-ALT _EV 16 + !',
        '_EV F2D-DISPATCH . CR',
        'FOC-GET _TR @ = IF ." TR" ELSE ." OTHER" THEN CR',
    ], check_fn=lambda o: "-1" in o and "TR" in o)

def test_dispatch_non_alt():
    """F2D-DISPATCH returns 0 for non-Alt keys."""
    check("f2d-dispatch-non-alt", [
        'KEY-T-SPECIAL _EV !',
        'KEY-DOWN _EV 8 + !',
        '0 _EV 16 + !',  # no mods
        '_EV F2D-DISPATCH . CR',
    ], "0")

def test_dispatch_char_key():
    """F2D-DISPATCH returns 0 for character keys."""
    check("f2d-dispatch-char", [
        'KEY-T-CHAR _EV !',
        '65 _EV 8 + !',  # 'A'
        'KEY-MOD-ALT _EV 16 + !',
        '_EV F2D-DISPATCH . CR',
    ], "0")

def test_dispatch_alt_del():
    """F2D-DISPATCH handles Alt+Delete (left click)."""
    check("f2d-dispatch-alt-del", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
    ] + _mk_named('_W1', 5, 10, 3, 20, 88) + [
        '_W1 @ FOC-ADD',
        'KEY-T-SPECIAL _EV !',
        'KEY-DEL _EV 8 + !',
        'KEY-MOD-ALT _EV 16 + !',
        '_EV F2D-DISPATCH . CR',
        '_HIT-ID @ . CR',
    ], check_fn=lambda o: "-1" in o and "88" in o)


# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════

def main():
    global _pass_count, _fail_count

    build_snapshot()
    print()
    print("=" * 60)
    print("  Focus + Focus-2D Test Suite")
    print("=" * 60)
    print()

    # §A
    print("[A] Compilation")
    test_compilation()
    print()

    # §B
    print("[B] FOC-ADD / FOC-GET / FOC-COUNT")
    test_add_get()
    test_count()
    test_add_duplicate()
    test_empty_get()
    print()

    # §C
    print("[C] FOC-NEXT / FOC-PREV (Ring Cycle)")
    test_next_cycle()
    test_prev_cycle()
    test_next_single()
    test_next_empty()
    print()

    # §D
    print("[D] FOC-SET")
    test_set_explicit()
    test_set_not_in_chain()
    test_set_updates_flags()
    print()

    # §E
    print("[E] FOC-REMOVE")
    test_remove_middle()
    test_remove_focused()
    test_remove_last()
    print()

    # §F
    print("[F] FOC-CLEAR")
    test_clear()
    print()

    # §G
    print("[G] FOC-DISPATCH")
    test_dispatch()
    test_dispatch_empty()
    print()

    # §H
    print("[H] FOC-EACH")
    test_each()
    test_each_empty()
    print()

    # §I
    print("[I] F2D Directional Navigation")
    test_f2d_down()
    test_f2d_up()
    test_f2d_right()
    test_f2d_left()
    test_f2d_diagonal_bias()
    test_f2d_no_candidate()
    test_f2d_empty()
    print()

    # §J
    print("[J] F2D Synthetic Clicks")
    test_click_left()
    test_click_empty()
    print()

    # §K
    print("[K] F2D-DISPATCH (Key Routing)")
    test_dispatch_alt_down()
    test_dispatch_alt_right()
    test_dispatch_non_alt()
    test_dispatch_char_key()
    test_dispatch_alt_del()
    print()

    # Summary
    print("=" * 60)
    total = _pass_count + _fail_count
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    print("=" * 60)
    return 1 if _fail_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
