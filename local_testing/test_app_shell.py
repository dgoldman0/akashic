#!/usr/bin/env python3
"""Test suite for akashic-tui-app-shell (TUI Application Shell Runtime).

Uses the Megapad-64 emulator to boot KDOS, load the full dependency chain
through uidl-tui + app-shell, then exercises the public API.
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

# Full topological dependency order (REQUIRE/PROVIDED stripped by loader)
_DEP_PATHS = [
    os.path.join(AK, "concurrency", "event.f"),
    os.path.join(AK, "concurrency", "semaphore.f"),
    os.path.join(AK, "concurrency", "guard.f"),
    os.path.join(AK, "utils",       "string.f"),
    os.path.join(AK, "utils",       "term.f"),
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
    os.path.join(AK, "tui",         "focus.f"),
    os.path.join(AK, "tui",         "widgets", "tree.f"),
    os.path.join(AK, "tui",         "widgets", "input.f"),
    os.path.join(AK, "text",        "gap-buf.f"),
    os.path.join(AK, "text",        "undo.f"),
    os.path.join(AK, "text",        "cell-width.f"),
    os.path.join(AK, "tui",         "widgets", "textarea.f"),
    os.path.join(AK, "css",         "css.f"),
    os.path.join(AK, "tui",         "color.f"),
    os.path.join(AK, "tui",         "uidl-tui.f"),
    os.path.join(AK, "tui",         "event.f"),
    os.path.join(AK, "tui",         "app.f"),
    os.path.join(AK, "tui",         "app-shell.f"),
]

# ═══════════════════════════════════════════════════════════════════
#  Emulator helpers
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
            if s.startswith('REQUIRE '):
                continue
            if s.startswith('PROVIDED '):
                continue
            lines.append(line)
        return lines

def _next_line_chunk(data: bytes, pos: int) -> bytes:
    nl = data.find(b'\n', pos)
    if nl == -1:
        return data[pos:]
    return data[pos:nl + 1]

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

    print("[*] Building snapshot: BIOS + KDOS + full TUI stack + app-shell ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    # Load all deps in topo order
    dep_lines = []
    for p in _DEP_PATHS:
        if not os.path.exists(p):
            raise FileNotFoundError(f"Missing dep: {p}")
        dep_lines.extend(_load_forth_lines(p))

    # Test helpers
    test_helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
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
    err_lines = [l for l in text.strip().split('\n') if '?' in l]
    if err_lines:
        print("[!] Possible compilation errors:")
        for ln in err_lines[-30:]:
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

import re

def _normalize(raw: str) -> str:
    """Strip ANSI, command echoes, prompts, 'ok' tags; extract printed values."""
    # Remove common ANSI fragment leftovers (ESC char already stripped)
    raw = re.sub(r'\[\??\d+[hlJKm]', '', raw)
    raw = re.sub(r'\[\d*;\d*[Hfr]', '', raw)
    raw = re.sub(r'\[[\d;]*m', '', raw)
    raw = re.sub(r'\[H', '', raw)
    raw = re.sub(r'\[2J', '', raw)
    # Remove BIOS greeting that leaks through alt-screen switch
    raw = re.sub(r'Megapad-64 Forth BIOS v[\d.]+', '', raw)
    raw = re.sub(r'RAM: [0-9a-fA-F]+ bytes', '', raw)
    # Process line by line
    lines = raw.split('\n')
    values = []
    for line in lines:
        line = line.strip()
        # Skip command echoes (lines starting with "> ")
        if line.startswith('> '):
            continue
        # Remove trailing " ok"
        line = re.sub(r'\s+ok\s*$', '', line)
        # Skip empty, BYE, and prompt-only lines
        if not line or line == 'Bye!' or line == '>':
            continue
        values.append(line)
    return ' '.join(values)

def check(name, forth_lines, expected=None, check_fn=None, not_expected=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = _normalize(output)

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
        print(f"        normalized: {clean!r}")
        raw_last = output.strip().split('\n')[-8:]
        print(f"        raw (last lines):")
        for l in raw_last:
            print(f"          {l!r}")


# ═══════════════════════════════════════════════════════════════════
#  §1 — APP-DESC Structure Tests
# ═══════════════════════════════════════════════════════════════════

def test_desc_size():
    """APP-DESC constant should be 112 (14 cells)."""
    check("desc-size", [
        'APP-DESC .',
    ], expected='112')

def test_desc_init():
    """APP-DESC-INIT should zero-fill the descriptor."""
    check("desc-init", [
        'CREATE _D APP-DESC ALLOT',
        '99 _D !',
        '_D APP-DESC-INIT',
        '_D @ .  _D 104 + @ .',
    ], expected='0 0')

def test_field_offsets():
    """Field accessors should return correct addresses."""
    check("field-offsets", [
        'CREATE _D APP-DESC ALLOT  _D APP-DESC-INIT',
        '111 _D APP.INIT-XT !  222 _D APP.EVENT-XT !',
        '333 _D APP.TICK-XT !  444 _D APP.PAINT-XT !',
        '555 _D APP.SHUTDOWN-XT !  666 _D APP.UIDL-A !',
        '777 _D APP.UIDL-U !  80 _D APP.WIDTH !  24 _D APP.HEIGHT !',
        '888 _D APP.UIDL-FILE-A !  999 _D APP.UIDL-FILE-U !',
        '_D APP.INIT-XT @ .  _D APP.EVENT-XT @ .  _D APP.TICK-XT @ .',
        '_D APP.PAINT-XT @ .  _D APP.SHUTDOWN-XT @ .',
        '_D APP.UIDL-A @ .  _D APP.UIDL-U @ .',
        '_D APP.WIDTH @ .  _D APP.HEIGHT @ .',
        '_D APP.UIDL-FILE-A @ .  _D APP.UIDL-FILE-U @ .',
    ], expected='111 222 333 444 555 666 777 80 24 888 999')


# ═══════════════════════════════════════════════════════════════════
#  §2 — Shell State (before run)
# ═══════════════════════════════════════════════════════════════════

def test_initial_state():
    """Shell state should be zeroed before any run."""
    check("initial-state", [
        'ASHELL-REGION .  ASHELL-UIDL? .  ASHELL-DESC .',
    ], expected='0 0 0')

def test_post_queue():
    """ASHELL-POST should enqueue without crashing."""
    check("post-queue", [
        'VARIABLE _PQ-RESULT  0 _PQ-RESULT !',
        ": _PQ-INC  1 _PQ-RESULT +! ;",
        # Use ' (tick) in interpret mode, not ['] which is compile-time only
        "' _PQ-INC ASHELL-POST",
        "' _PQ-INC ASHELL-POST",
        "' _PQ-INC ASHELL-POST",
        '_PQ-RESULT @ .',
    ], expected='0')  # actions enqueued but not yet drained


# ═══════════════════════════════════════════════════════════════════
#  §3 — Lifecycle Tests (quit immediately)
# ═══════════════════════════════════════════════════════════════════

def test_run_quit_no_uidl():
    """ASHELL-RUN with an app that quits immediately (no UIDL)."""
    check("run-quit-no-uidl", [
        'VARIABLE _RQN-INITED  0 _RQN-INITED !',
        'VARIABLE _RQN-SD      0 _RQN-SD !',
        ': _RQN-INIT-FN  -1 _RQN-INITED ! ASHELL-QUIT ;',
        ': _RQN-SD-FN    -1 _RQN-SD ! ;',
        'CREATE _RQN-D APP-DESC ALLOT  _RQN-D APP-DESC-INIT',
        "' _RQN-INIT-FN _RQN-D APP.INIT-XT !",
        "' _RQN-SD-FN _RQN-D APP.SHUTDOWN-XT !",
        '_RQN-D ASHELL-RUN',
        '_RQN-INITED @ .  _RQN-SD @ .',
    ], expected='-1 -1')

def test_run_quit_with_uidl():
    """ASHELL-RUN with UIDL document — init->quit cycle."""
    check("run-quit-with-uidl", [
        'VARIABLE _RQU-OK  0 _RQU-OK !',
        ': _RQU-INIT  ASHELL-UIDL? _RQU-OK !  ASHELL-QUIT ;',
        'CREATE _RQU-UIDL 256 ALLOT',
        'S" <uidl><region><label text=Hello/></region></uidl>"',
        '_RQU-UIDL SWAP MOVE',
        'CREATE _RQU-D APP-DESC ALLOT  _RQU-D APP-DESC-INIT',
        "' _RQU-INIT _RQU-D APP.INIT-XT !",
        '_RQU-UIDL _RQU-D APP.UIDL-A !',
        '49 _RQU-D APP.UIDL-U !',
        '_RQU-D ASHELL-RUN',
        '_RQU-OK @ .',
    ], expected='-1')

def test_region_available_in_init():
    """ASHELL-REGION should be non-zero inside app init callback."""
    check("region-in-init", [
        'VARIABLE _RGI-V  0 _RGI-V !',
        ': _RGI-INIT  ASHELL-REGION _RGI-V !  ASHELL-QUIT ;',
        'CREATE _RGI-D APP-DESC ALLOT  _RGI-D APP-DESC-INIT',
        "' _RGI-INIT _RGI-D APP.INIT-XT !",
        '_RGI-D ASHELL-RUN',
        '_RGI-V @ 0<> .',
    ], expected='-1')

def test_cleanup_after_run():
    """After ASHELL-RUN returns, shell state should be reset."""
    check("cleanup-after-run", [
        ': _CLN-INIT  ASHELL-QUIT ;',
        'CREATE _CLN-D APP-DESC ALLOT  _CLN-D APP-DESC-INIT',
        "' _CLN-INIT _CLN-D APP.INIT-XT !",
        '_CLN-D ASHELL-RUN',
        'ASHELL-DESC .  ASHELL-REGION .  ASHELL-UIDL? .',
    ], expected='0 0 0')


# ═══════════════════════════════════════════════════════════════════
#  §4 — Event Dispatch Tests
# ═══════════════════════════════════════════════════════════════════

def test_event_callback():
    """App EVENT-XT wiring — init can quit cleanly."""
    check("event-callback-wired", [
        ': _EC-EV  ( ev -- flag ) DROP 0 ;',
        ': _EC-INIT  ASHELL-QUIT ;',
        'CREATE _EC-D APP-DESC ALLOT  _EC-D APP-DESC-INIT',
        "' _EC-INIT _EC-D APP.INIT-XT !",
        "' _EC-EV   _EC-D APP.EVENT-XT !",
        '_EC-D ASHELL-RUN',
        'S" OK" TYPE',
    ], expected='OK')


# ═══════════════════════════════════════════════════════════════════
#  §5 — Tick Callback Tests
# ═══════════════════════════════════════════════════════════════════

def test_tick_ms_accessor():
    """ASHELL-TICK-MS! should store the tick interval."""
    check("tick-ms-set", [
        '200 ASHELL-TICK-MS!',
        'S" OK" TYPE',
    ], expected='OK')


# ═══════════════════════════════════════════════════════════════════
#  §6 — Dirty Flag Tests
# ═══════════════════════════════════════════════════════════════════

def test_dirty_flag():
    """ASHELL-DIRTY! should be callable outside of run."""
    check("dirty-flag", [
        'ASHELL-DIRTY!',
        'S" OK" TYPE',
    ], expected='OK')


# ═══════════════════════════════════════════════════════════════════
#  §7 — Error Handling Tests
# ═══════════════════════════════════════════════════════════════════

def test_throw_in_init():
    """If app init THROWs, shell should still clean up and propagate."""
    check("throw-in-init", [
        ': _TI-INIT  -999 THROW ;',
        'CREATE _TI-D APP-DESC ALLOT  _TI-D APP-DESC-INIT',
        "' _TI-INIT _TI-D APP.INIT-XT !",
        # CATCH restores stack to pre-CATCH state then pushes throw code.
        # The desc stays on stack from CATCH restore, so DROP it.
        "_TI-D ' ASHELL-RUN CATCH . DROP",
        'ASHELL-DESC .',
    ], expected='-999')


# ═══════════════════════════════════════════════════════════════════
#  §8 — All Callbacks Wired Test
# ═══════════════════════════════════════════════════════════════════

def test_all_callbacks():
    """All 5 callbacks should be callable."""
    check("all-callbacks", [
        'VARIABLE _AC-BITS  0 _AC-BITS !',
        ': _AC-INIT      1 _AC-BITS +!  ASHELL-QUIT ;',
        ': _AC-EVENT     ( ev -- flag ) DROP 0 ;',
        ': _AC-TICK      ;',
        ': _AC-PAINT     ;',
        ': _AC-SHUTDOWN  16 _AC-BITS +! ;',
        'CREATE _AC-D APP-DESC ALLOT  _AC-D APP-DESC-INIT',
        "' _AC-INIT     _AC-D APP.INIT-XT !",
        "' _AC-EVENT    _AC-D APP.EVENT-XT !",
        "' _AC-TICK     _AC-D APP.TICK-XT !",
        "' _AC-PAINT    _AC-D APP.PAINT-XT !",
        "' _AC-SHUTDOWN _AC-D APP.SHUTDOWN-XT !",
        '_AC-D ASHELL-RUN',
        '_AC-BITS @ .',
    ], expected='17')


# ═══════════════════════════════════════════════════════════════════
#  §9 — UIDL Integration Tests
# ═══════════════════════════════════════════════════════════════════

def test_uidl_by_id_in_init():
    """UTUI-BY-ID should work inside the app init callback."""
    check("uidl-by-id-in-init", [
        'VARIABLE _UBI-FOUND  0 _UBI-FOUND !',
        ': _UBI-INIT',
        '    S" lbl1" UTUI-BY-ID',
        '    0<> _UBI-FOUND !',
        '    ASHELL-QUIT ;',
        'CREATE _UBI-UIDL 256 ALLOT',
        'S" <uidl><region><label id=lbl1 text=Test/></region></uidl>"',
        '_UBI-UIDL SWAP MOVE',
        'CREATE _UBI-D APP-DESC ALLOT  _UBI-D APP-DESC-INIT',
        "' _UBI-INIT _UBI-D APP.INIT-XT !",
        '_UBI-UIDL _UBI-D APP.UIDL-A !',
        '56 _UBI-D APP.UIDL-U !',
        '_UBI-D ASHELL-RUN',
        '_UBI-FOUND @ .',
    ], expected='-1')

def test_uidl_action_registration():
    """UTUI-DO! should work when UIDL is loaded via shell."""
    check("uidl-action-reg", [
        'VARIABLE _UAR-FIRED  0 _UAR-FIRED !',
        ': _UAR-FIRE  -1 _UAR-FIRED ! ;',
        ': _UAR-INIT',
        "    S\" my-act\" ['] _UAR-FIRE UTUI-DO!",
        '    ASHELL-QUIT ;',
        'CREATE _UAR-UIDL 256 ALLOT',
        'S" <uidl><region><action do=my-act text=Go key=F1/></region></uidl>"',
        '_UAR-UIDL SWAP MOVE',
        'CREATE _UAR-D APP-DESC ALLOT  _UAR-D APP-DESC-INIT',
        "' _UAR-INIT _UAR-D APP.INIT-XT !",
        '_UAR-UIDL _UAR-D APP.UIDL-A !',
        '64 _UAR-D APP.UIDL-U !',
        '_UAR-D ASHELL-RUN',
        'S" OK" TYPE',
    ], expected='OK')


# ═══════════════════════════════════════════════════════════════════
#  Runner
# ═══════════════════════════════════════════════════════════════════

def main():
    global _pass_count, _fail_count

    build_snapshot()
    print()

    tests = [
        # §1 — Descriptor
        test_desc_size,
        test_desc_init,
        test_field_offsets,
        # §2 — Shell state
        test_initial_state,
        test_post_queue,
        # §3 — Lifecycle
        test_run_quit_no_uidl,
        test_run_quit_with_uidl,
        test_region_available_in_init,
        test_cleanup_after_run,
        # §4 — Events
        test_event_callback,
        # §5 — Tick
        test_tick_ms_accessor,
        # §6 — Dirty
        test_dirty_flag,
        # §7 — Error handling
        test_throw_in_init,
        # §8 — All callbacks
        test_all_callbacks,
        # §9 — UIDL integration
        test_uidl_by_id_in_init,
        test_uidl_action_registration,
    ]

    for test in tests:
        try:
            test()
        except Exception as e:
            _fail_count += 1
            print(f"  ERROR {test.__name__}: {e}")

    print(f"\n{'='*50}")
    total = _pass_count + _fail_count
    print(f"  {_pass_count}/{total} passed, {_fail_count} failed")
    if _fail_count:
        print("  SOME TESTS FAILED")
    else:
        print("  ALL TESTS PASSED")
    print(f"{'='*50}")
    return 0 if _fail_count == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
