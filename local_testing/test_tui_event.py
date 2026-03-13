#!/usr/bin/env python3
"""Test suite for tui/event.f (TUI Event Loop & Dispatch).

Uses the Megapad-64 emulator to boot KDOS, load the full TUI dependency
chain through event.f, then exercises:
  - Compilation (clean load of all deps + event.f)
  - TUI-EVT-QUIT / _TUI-EVT-RUNNING flag
  - Deferred action queue (TUI-EVT-POST + drain)
  - Timer tick mechanism
  - Dirty widget redraw via FOC-EACH
  - TUI-EVT-REDRAW flag
  - Global key handler registration
  - Loop start/quit cycle
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

# Dependency order: everything through event.f
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
    os.path.join(AK, "tui",   "event.f"),
]

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers  (same pattern as test_focus.py)
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

    print("[*] Building snapshot: BIOS + KDOS + TUI stack + event.f ...")
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
    # _MK-MOCK ( row col h w id -- wdg )  Allocate a mock widget
    # _EV: event buffer (3 cells = 24 bytes)
    # _HIT-ID: stores which widget-id the handler saw
    # _DRAW-COUNT: counts how many times _MOCK-DRAW is called
    # _TICK-COUNT: counts tick callback invocations
    # _POST-LOG: counts posted action executions
    test_helpers = [
        'VARIABLE _HIT-ID',
        'VARIABLE _DRAW-COUNT',
        'VARIABLE _TICK-COUNT',
        'VARIABLE _POST-LOG',
        'CREATE _EV 24 ALLOT',
        # Draw xt: increments _DRAW-COUNT
        ': _MOCK-DRAW ( wdg -- ) DROP  _DRAW-COUNT @ 1+ _DRAW-COUNT ! ;',
        # Handle xt: stores widget type-id in _HIT-ID, returns -1 (consumed)
        ': _MOCK-HANDLE ( ev wdg -- flag ) _WDG-O-TYPE + @ _HIT-ID ! DROP -1 ;',
        # _MK-MOCK ( row col h w id -- wdg )
        ': _MK-MOCK',
        '  >R',
        '  RGN-NEW',
        '  40 ALLOCATE DROP',
        '  DUP R>',
        '  3 PICK',
        "  ['] _MOCK-DRAW",
        "  ['] _MOCK-HANDLE",
        '  _WDG-INIT',
        '  NIP',
        ';',
        # Screen creation helper (needed for SCR-FLUSH in event loop)
        '10 5 SCR-NEW SCR-USE',
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
#  Mock widget helpers
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
#  §B — TUI-EVT-QUIT / Running Flag
# ═══════════════════════════════════════════════════════════════════

def test_quit_sets_flag():
    """TUI-EVT-QUIT sets _TUI-EVT-RUNNING to 0."""
    check("quit-flag", [
        '-1 _TUI-EVT-RUNNING !',
        'TUI-EVT-QUIT',
        '." R=" _TUI-EVT-RUNNING @ . CR',
    ], "R=0 ")

def test_running_flag_default():
    """_TUI-EVT-RUNNING is 0 by default (loop not entered yet)."""
    check("running-default", [
        '." R=" _TUI-EVT-RUNNING @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §C — Configuration Words
# ═══════════════════════════════════════════════════════════════════

def test_tick_ms():
    """TUI-EVT-TICK-MS! sets the tick interval."""
    check("tick-ms-set", [
        '200 TUI-EVT-TICK-MS!',
        '." R=" _TUI-EVT-TICK-MS @ . CR',
    ], "R=200 ")

def test_on_tick():
    """TUI-EVT-ON-TICK registers a callback xt."""
    check("on-tick-reg", [
        ': _MY-TICK  ." TICKED" ;',
        "' _MY-TICK TUI-EVT-ON-TICK",
        '_TUI-EVT-ON-TICK-XT @ EXECUTE CR',
    ], "TICKED")

def test_on_resize():
    """TUI-EVT-ON-RESIZE registers a callback xt."""
    check("on-resize-reg", [
        ': _MY-RESIZE ( w h -- ) + . ;',
        "' _MY-RESIZE TUI-EVT-ON-RESIZE",
        '80 24 _TUI-EVT-ON-RESIZE-XT @ EXECUTE CR',
    ], "104")

def test_on_key():
    """TUI-EVT-ON-KEY registers a global key handler xt."""
    check("on-key-reg", [
        ': _MY-KEY ( ev -- f ) DROP -1 ;',
        "' _MY-KEY TUI-EVT-ON-KEY",
        '." R=" _TUI-EVT-ON-KEY-XT @ 0<> . CR',
    ], "R=-1 ")

def test_redraw_flag():
    """TUI-EVT-REDRAW sets the redraw flag."""
    check("redraw-flag", [
        '0 _TUI-EVT-REDRAW-FLAG !',
        'TUI-EVT-REDRAW',
        '." R=" _TUI-EVT-REDRAW-FLAG @ 0<> . CR',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §D — Deferred Action Queue (TUI-EVT-POST)
# ═══════════════════════════════════════════════════════════════════

def test_post_single():
    """Post one action and drain — it executes."""
    check("post-single", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        '0 _POST-LOG !',
        ': _INC-LOG  _POST-LOG @ 1+ _POST-LOG ! ;',
        "' _INC-LOG TUI-EVT-POST",
        '_TUI-EVT-DRAIN-POSTED',
        '." R=" _POST-LOG @ . CR',
    ], "R=1 ")

def test_post_fifo_order():
    """Multiple posted actions execute in FIFO order."""
    check("post-fifo", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        ': _P1  ." A" ;',
        ': _P2  ." B" ;',
        ': _P3  ." C" ;',
        "' _P1 TUI-EVT-POST",
        "' _P2 TUI-EVT-POST",
        "' _P3 TUI-EVT-POST",
        '_TUI-EVT-DRAIN-POSTED',
        'CR',
    ], "ABC")

def test_post_drain_empty():
    """Draining empty queue is a no-op."""
    check("post-drain-empty", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        '_TUI-EVT-DRAIN-POSTED',
        '." OK" CR',
    ], "OK")

def test_post_overflow():
    """Posting more than 8 actions drops excess."""
    check("post-overflow", [
        '0 _TUI-EVT-POST-HEAD !',
        '0 _TUI-EVT-POST-TAIL !',
        '0 _POST-LOG !',
        ': _INC-LOG2  _POST-LOG @ 1+ _POST-LOG ! ;',
        # Post 10 actions — only 8 should be stored
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",
        "' _INC-LOG2 TUI-EVT-POST",   # 9th — should be dropped
        "' _INC-LOG2 TUI-EVT-POST",   # 10th — should be dropped
        '_TUI-EVT-DRAIN-POSTED',
        '." R=" _POST-LOG @ . CR',
    ], "R=8 ")


# ═══════════════════════════════════════════════════════════════════
#  §E — Timer Tick Check
# ═══════════════════════════════════════════════════════════════════

def test_tick_no_callback():
    """_TUI-EVT-CHECK-TICK does nothing if no callback registered."""
    check("tick-no-cb", [
        '0 _TUI-EVT-ON-TICK-XT !',
        '_TUI-EVT-CHECK-TICK',
        '." OK" CR',
    ], "OK")

def test_tick_fires_when_elapsed():
    """Tick fires when enough time has elapsed."""
    check("tick-fires", [
        '0 _TICK-COUNT !',
        ': _MY-TICK3  _TICK-COUNT @ 1+ _TICK-COUNT ! ;',
        "' _MY-TICK3 TUI-EVT-ON-TICK",
        # Set tick interval very small and last-tick to 0 (far in the past)
        '1 TUI-EVT-TICK-MS!',
        '0 _TUI-EVT-LAST-TICK !',
        '_TUI-EVT-CHECK-TICK',
        '." R=" _TICK-COUNT @ . CR',
    ], "R=1 ")

def test_tick_skips_when_recent():
    """Tick doesn't fire if interval hasn't elapsed."""
    check("tick-skips", [
        '0 _TICK-COUNT !',
        ': _MY-TICK4  _TICK-COUNT @ 1+ _TICK-COUNT ! ;',
        "' _MY-TICK4 TUI-EVT-ON-TICK",
        # Set tick interval very large and last-tick to now
        '999999 TUI-EVT-TICK-MS!',
        'MS@ _TUI-EVT-LAST-TICK !',
        '_TUI-EVT-CHECK-TICK',
        '." R=" _TICK-COUNT @ . CR',
    ], "R=0 ")


# ═══════════════════════════════════════════════════════════════════
#  §F — Dirty Widget Redraw
# ═══════════════════════════════════════════════════════════════════

def test_draw_dirty_widget():
    """_TUI-EVT-DRAW-DIRTY redraws dirty widgets in the focus chain."""
    check("draw-dirty", [
        'FOC-CLEAR',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WA', 0, 0, 1, 10, 1) + [
        '_WA @ FOC-ADD',
        # Widget starts VISIBLE|DIRTY from _WDG-INIT
        '_TUI-EVT-DRAW-DIRTY',
        '." R=" _DRAW-COUNT @ . CR',
    ], "R=1 ")

def test_draw_clean_skipped():
    """Clean widgets are not redrawn."""
    check("draw-clean-skip", [
        'FOC-CLEAR',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WB', 0, 0, 1, 10, 2) + [
        '_WB @ FOC-ADD',
        '_WB @ WDG-CLEAN',   # clear dirty flag
        '_TUI-EVT-DRAW-DIRTY',
        '." R=" _DRAW-COUNT @ . CR',
    ], "R=0 ")

def test_redraw_marks_all_dirty():
    """TUI-EVT-REDRAW + _TUI-EVT-DRAW-DIRTY redraws all widgets."""
    check("redraw-all", [
        'FOC-CLEAR',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WC', 0, 0, 1, 10, 3) + [
        '_WC @ FOC-ADD',
    ] + _mk_named('_WD', 1, 0, 1, 10, 4) + [
        '_WD @ FOC-ADD',
        # Clean both widgets
        '_WC @ WDG-CLEAN',
        '_WD @ WDG-CLEAN',
        # Request redraw
        'TUI-EVT-REDRAW',
        '_TUI-EVT-DRAW-DIRTY',
        '." R=" _DRAW-COUNT @ . CR',
    ], "R=2 ")


# ═══════════════════════════════════════════════════════════════════
#  §G — Global Key Handler
# ═══════════════════════════════════════════════════════════════════

def test_global_key_intercepts():
    """Global handler can consume events before focus dispatch."""
    check("global-intercept", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
    ] + _mk_named('_WE', 0, 0, 1, 10, 77) + [
        '_WE @ FOC-ADD',
        # Global handler always consumes
        ': _GOBBLER ( ev -- f ) DROP -1 ;',
        "' _GOBBLER TUI-EVT-ON-KEY",
        # Build a fake char event in _EV
        'KEY-T-CHAR _EV !',
        '65 _EV 8 + !',    # 'A'
        '0 _EV 16 + !',    # no mods
        # Simulate dispatch chain: global handler check then FOC-DISPATCH
        '_TUI-EVT-ON-KEY-XT @ ?DUP IF',
        '  _EV SWAP EXECUTE',
        'ELSE 0 THEN',
        '0= IF _EV FOC-DISPATCH THEN',
        # _HIT-ID should still be 0 (global consumed it)
        '." R=" _HIT-ID @ . CR',
    ], "R=0 ")

def test_global_key_passthrough():
    """Global handler returns 0 → focus dispatch runs."""
    check("global-passthru", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
    ] + _mk_named('_WF', 0, 0, 1, 10, 88) + [
        '_WF @ FOC-ADD',
        # Global handler passes through
        ': _PASSER ( ev -- f ) DROP 0 ;',
        "' _PASSER TUI-EVT-ON-KEY",
        # Build fake char event
        'KEY-T-CHAR _EV !',
        '66 _EV 8 + !',    # 'B'
        '0 _EV 16 + !',
        # Simulate dispatch chain
        '_TUI-EVT-ON-KEY-XT @ ?DUP IF',
        '  _EV SWAP EXECUTE',
        'ELSE 0 THEN',
        '0= IF _EV FOC-DISPATCH THEN',
        # _HIT-ID should be 88 (widget type-id)
        '_HIT-ID @ . CR',
    ], "88")

def test_no_global_handler():
    """No global handler → events go straight to focus."""
    check("no-global-handler", [
        'FOC-CLEAR',
        '0 _HIT-ID !',
        '0 _TUI-EVT-ON-KEY-XT !',
    ] + _mk_named('_WG', 0, 0, 1, 10, 55) + [
        '_WG @ FOC-ADD',
        # Build event
        'KEY-T-CHAR _EV !',
        '67 _EV 8 + !',    # 'C'
        '0 _EV 16 + !',
        # Simulate dispatch chain
        '_TUI-EVT-ON-KEY-XT @ ?DUP IF',
        '  _EV SWAP EXECUTE',
        'ELSE 0 THEN',
        '0= IF _EV FOC-DISPATCH THEN',
        '_HIT-ID @ . CR',
    ], "55")


# ═══════════════════════════════════════════════════════════════════
#  §H — Event Loop Start/Quit
# ═══════════════════════════════════════════════════════════════════

def test_loop_quit_via_post():
    """Loop starts and exits when TUI-EVT-QUIT is posted."""
    check("loop-quit-post", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        "' TUI-EVT-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." EXITED" CR',
    ], "EXITED")

def test_loop_running_during():
    """_TUI-EVT-RUNNING is TRUE inside the loop."""
    check("loop-running", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        'VARIABLE _WAS-RUNNING',
        ': _CHK-AND-QUIT  _TUI-EVT-RUNNING @ _WAS-RUNNING ! TUI-EVT-QUIT ;',
        "' _CHK-AND-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _WAS-RUNNING @ 0<> . CR',
    ], "R=-1 ")

def test_loop_post_resets_queue():
    """Loop entry resets the post queue — old posts don't re-fire."""
    check("loop-post-reset", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _POST-LOG !',
        ': _INC-AND-QUIT  _POST-LOG @ 1+ _POST-LOG ! TUI-EVT-QUIT ;',
        "' _INC-AND-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _POST-LOG @ . CR',
    ], "R=1 ")


# ═══════════════════════════════════════════════════════════════════
#  §I — Tick Callback in Loop
# ═══════════════════════════════════════════════════════════════════

def test_loop_tick_fires():
    """Tick callback fires during loop when interval has elapsed."""
    # Strategy: post an action that backdates LAST-TICK to 0, then the
    # tick callback (1 ms interval) fires on the next iteration and quits.
    check("loop-tick", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _TICK-COUNT !',
        '1 TUI-EVT-TICK-MS!',
        ': _T-TICK  _TICK-COUNT @ 1+ _TICK-COUNT ! TUI-EVT-QUIT ;',
        "' _T-TICK TUI-EVT-ON-TICK",
        ': _BACKDATE  0 _TUI-EVT-LAST-TICK ! ;',
        "' _BACKDATE TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _TICK-COUNT @ 0> . CR',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §J — Draw Dirty in Loop
# ═══════════════════════════════════════════════════════════════════

def test_loop_draws_dirty():
    """Loop draws dirty widgets during its iteration."""
    check("loop-draw", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _DRAW-COUNT !',
    ] + _mk_named('_WH', 0, 0, 1, 10, 42) + [
        '_WH @ FOC-ADD',
        "' TUI-EVT-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _DRAW-COUNT @ 0> . CR',
    ], "R=-1 ")


# ═══════════════════════════════════════════════════════════════════
#  §K — Deferred Actions in Loop
# ═══════════════════════════════════════════════════════════════════

def test_loop_post_executes():
    """Posted action executes during loop iteration."""
    check("loop-post-exec", [
        'FOC-CLEAR',
        '0 _TUI-EVT-ON-KEY-XT !',
        '0 _TUI-EVT-ON-TICK-XT !',
        '0 _TUI-EVT-ON-RESIZE-XT !',
        '0 _POST-LOG !',
        ': _P-INC  _POST-LOG @ 1+ _POST-LOG ! ;',
        "' _P-INC TUI-EVT-POST",
        "' TUI-EVT-QUIT TUI-EVT-POST",
        'TUI-EVT-LOOP',
        '." R=" _POST-LOG @ . CR',
    ], "R=1 ")


# ═══════════════════════════════════════════════════════════════════
#  §L — YIELD? Compatibility
# ═══════════════════════════════════════════════════════════════════

def test_yield_no_crash():
    """YIELD? is callable and doesn't crash."""
    check("yield-ok", [
        'YIELD?',
        '." YIELD-OK" CR',
    ], "YIELD-OK")


# ═══════════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    build_snapshot()

    print()
    print("=" * 60)
    print("  §A  Compilation")
    print("=" * 60)
    test_compilation()

    print()
    print("=" * 60)
    print("  §B  TUI-EVT-QUIT / Running Flag")
    print("=" * 60)
    test_quit_sets_flag()
    test_running_flag_default()

    print()
    print("=" * 60)
    print("  §C  Configuration Words")
    print("=" * 60)
    test_tick_ms()
    test_on_tick()
    test_on_resize()
    test_on_key()
    test_redraw_flag()

    print()
    print("=" * 60)
    print("  §D  Deferred Action Queue")
    print("=" * 60)
    test_post_single()
    test_post_fifo_order()
    test_post_drain_empty()
    test_post_overflow()

    print()
    print("=" * 60)
    print("  §E  Timer Tick")
    print("=" * 60)
    test_tick_no_callback()
    test_tick_fires_when_elapsed()
    test_tick_skips_when_recent()

    print()
    print("=" * 60)
    print("  §F  Dirty Widget Redraw")
    print("=" * 60)
    test_draw_dirty_widget()
    test_draw_clean_skipped()
    test_redraw_marks_all_dirty()

    print()
    print("=" * 60)
    print("  §G  Global Key Handler")
    print("=" * 60)
    test_global_key_intercepts()
    test_global_key_passthrough()
    test_no_global_handler()

    print()
    print("=" * 60)
    print("  §H  Event Loop Start/Quit")
    print("=" * 60)
    test_loop_quit_via_post()
    test_loop_running_during()
    test_loop_post_resets_queue()

    print()
    print("=" * 60)
    print("  §I  Tick Callback in Loop")
    print("=" * 60)
    test_loop_tick_fires()

    print()
    print("=" * 60)
    print("  §J  Draw Dirty in Loop")
    print("=" * 60)
    test_loop_draws_dirty()

    print()
    print("=" * 60)
    print("  §K  Deferred Actions in Loop")
    print("=" * 60)
    test_loop_post_executes()

    print()
    print("=" * 60)
    print("  §L  YIELD? Compatibility")
    print("=" * 60)
    test_yield_no_crash()

    print()
    total = _pass_count + _fail_count
    print(f"{'=' * 60}")
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    print(f"{'=' * 60}")
    sys.exit(0 if _fail_count == 0 else 1)
