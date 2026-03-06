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
"""Test suite for akashic-sml-tree Forth library.

Uses the Megapad-64 emulator to boot KDOS, load all dependencies
(string.f, utf8.f, css.f, markup/core.f, markup/html.f, css/bridge.f,
dom.f, sml/core.f, sml/tree.f), then run Forth test expressions.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Dependency files in load order
STR_F       = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
UTF8_F      = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
CSS_F       = os.path.join(ROOT_DIR, "akashic", "css", "css.f")
MU_CORE_F   = os.path.join(ROOT_DIR, "akashic", "markup", "core.f")
MU_HTML_F   = os.path.join(ROOT_DIR, "akashic", "markup", "html.f")
CSS_BRIDGE_F= os.path.join(ROOT_DIR, "akashic", "css", "bridge.f")
DOM_F       = os.path.join(ROOT_DIR, "akashic", "dom", "dom.f")
SML_CORE_F  = os.path.join(ROOT_DIR, "akashic", "sml", "core.f")
SML_TREE_F  = os.path.join(ROOT_DIR, "akashic", "sml", "tree.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

# ---------------------------------------------------------------------------
#  Emulator helpers
# ---------------------------------------------------------------------------

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

    print("[*] Building snapshot: KDOS + all deps + sml/tree.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines    = _load_forth_lines(KDOS_PATH)
    str_lines     = _load_forth_lines(STR_F)
    utf8_lines    = _load_forth_lines(UTF8_F)
    css_lines     = _load_forth_lines(CSS_F)
    mu_lines      = _load_forth_lines(MU_CORE_F)
    html_lines    = _load_forth_lines(MU_HTML_F)
    bridge_lines  = _load_forth_lines(CSS_BRIDGE_F)
    dom_lines     = _load_forth_lines(DOM_F)
    sml_core_lines= _load_forth_lines(SML_CORE_F)
    sml_tree_lines= _load_forth_lines(SML_TREE_F)

    test_helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 512 ALLOT  VARIABLE _UL',
        ': UR  0 _UL ! ;',
        ': UC  ( c -- ) _UB _UL @ + C!  1 _UL +! ;',
        ': UA  ( -- addr u ) _UB _UL @ ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + str_lines + utf8_lines + css_lines
                 + mu_lines + html_lines + bridge_lines
                 + dom_lines + sml_core_lines + sml_tree_lines
                 + test_helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 1_200_000_000

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
        for ln in err_lines[-25:]:
            print(f"    {ln}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=100_000_000):
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


def mstr(s):
    """Build Forth lines that construct string s in _TB using TC."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        split_at = full.rfind(' ', 0, 70)
        if split_at == -1:
            split_at = 70
        lines.append(full[:split_at])
        full = full[split_at:].lstrip()
    if full:
        lines.append(full)
    return lines


def mstr2(s):
    """Build Forth lines that construct string s in _UB using UC."""
    parts = ['UR']
    for ch in s:
        parts.append(f'{ord(ch)} UC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        split_at = full.rfind(' ', 0, 70)
        if split_at == -1:
            split_at = 70
        lines.append(full[:split_at])
        full = full[split_at:].lstrip()
    if full:
        lines.append(full)
    return lines


# ---------------------------------------------------------------------------
#  Test framework
# ---------------------------------------------------------------------------

_pass_count = 0
_fail_count = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()

    if check_fn:
        ok = check_fn(clean)
    elif expected is not None:
        ok = expected in clean
    else:
        ok = True

    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        if expected is not None:
            last_lines = clean.split('\n')[-3:]
            print(f"        expected: '{expected}'")
            print(f"        got (last lines): {last_lines}")
        elif check_fn:
            last_lines = clean.split('\n')[-5:]
            print(f"        check_fn failed")
            print(f"        got (last lines): {last_lines}")


# ===========================================================================
#  Test: Tree Creation / Destruction
# ===========================================================================

def test_tree_create():
    print("\n--- Tree Creation ---")

    check("TREE-CREATE returns nonzero",
          [': _T SML-TREE-CREATE . ; _T'],
          check_fn=lambda o: o.strip().split('\n')[-1].strip() != '0')

    check("TREE handle has DOC",
          [': _T SML-TREE-CREATE DUP @ . DROP ; _T'],
          check_fn=lambda o: o.strip().split('\n')[-1].strip() != '0')

    check("TREE handle has EXT",
          [': _T SML-TREE-CREATE DUP 8 + @ . DROP ; _T'],
          check_fn=lambda o: o.strip().split('\n')[-1].strip() != '0')


# ===========================================================================
#  Test: SML Type Encoding
# ===========================================================================

def test_type_encoding():
    print("\n--- SML Type Encoding in DOM Flags ---")

    # Create tree, make an element, set type, read back
    check("Set and read SML type on node",
          [': _T SML-TREE-CREATE DROP',
           '  S" item" DOM-CREATE-ELEMENT',
           '  SML-T-POSITION OVER _SML-SET-TYPE',
           '  SML-NODE-TYPE@ . ; _T'], "3 ")

    check("SML type SCOPE on node",
          [': _T SML-TREE-CREATE DROP',
           '  S" seq" DOM-CREATE-ELEMENT',
           '  SML-T-SCOPE OVER _SML-SET-TYPE',
           '  SML-NODE-TYPE@ . ; _T'], "2 ")

    check("SML type ENVELOPE on node",
          [': _T SML-TREE-CREATE DROP',
           '  S" sml" DOM-CREATE-ELEMENT',
           '  SML-T-ENVELOPE OVER _SML-SET-TYPE',
           '  SML-NODE-TYPE@ . ; _T'], "0 ")

    check("SML type META on node",
          [': _T SML-TREE-CREATE DROP',
           '  S" title" DOM-CREATE-ELEMENT',
           '  SML-T-META OVER _SML-SET-TYPE',
           '  SML-NODE-TYPE@ . ; _T'], "1 ")


# ===========================================================================
#  Test: SML-LOAD — Parse SML markup into tree
# ===========================================================================

def test_sml_load():
    print("\n--- SML-LOAD ---")

    # Load a minimal doc and check it parsed
    check("LOAD minimal <sml><seq><item/></seq></sml>",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T SML-TREE-CREATE DROP',
           '  TA SML-TREE SML-LOAD',
           '  SML-TREE SML-FIRST DUP . 0<> . ; _T'],
          check_fn=lambda o: '-1' in o)

    # Load and verify first navigable is an item
    check("LOAD first navigable = item tag",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T SML-TREE-CREATE DROP',
           '  TA SML-TREE SML-LOAD',
           '  SML-TREE SML-FIRST DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'item' in o)

    # Load and verify type encoding
    check("LOAD types encoded correctly",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T SML-TREE-CREATE DROP',
           '  TA SML-TREE SML-LOAD',
           '  SML-TREE SML-FIRST SML-NODE-TYPE@ . ; _T'], "3 ")


# ===========================================================================
#  Test: SML-INIT convenience
# ===========================================================================

def test_sml_init():
    print("\n--- SML-INIT ---")

    check("INIT creates tree + loads + cursor",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  DUP SOM-CURRENT 0<> . ; _T'], "-1 ")

    check("INIT cursor on first item",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  DUP SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'item' in o)


# ===========================================================================
#  Test: SML-FIRST / SML-LAST
# ===========================================================================

def test_first_last():
    print("\n--- SML-FIRST / SML-LAST ---")

    check("FIRST = item (first position elem)",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'item' in o)

    check("LAST = val (last position elem)",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-LAST DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'val' in o)

    check("FIRST skips non-navigable gap",
          mstr('<sml><seq><gap/><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'item' in o)


# ===========================================================================
#  Test: SML-NEXT / SML-PREV
# ===========================================================================

def test_next_prev():
    print("\n--- SML-NEXT / SML-PREV ---")

    check("NEXT from first to second",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST  SML-TREE SML-NEXT',
           '  DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'act' in o)

    check("NEXT from second to third",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST  SML-TREE SML-NEXT',
           '  SML-TREE SML-NEXT  DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'val' in o)

    check("NEXT past last = 0",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST  SML-TREE SML-NEXT',
           '  SML-TREE SML-NEXT . ; _T'], "0 ")

    check("PREV from second to first",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST  SML-TREE SML-NEXT',
           '  SML-TREE SML-PREV  DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'item' in o)

    check("PREV from first = 0",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST  SML-TREE SML-PREV . ; _T'], "0 ")

    check("NEXT skips gap",
          mstr('<sml><seq><item/><gap/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SML-FIRST  SML-TREE SML-NEXT',
           '  DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'act' in o)


# ===========================================================================
#  Test: SML-CHILDREN
# ===========================================================================

def test_children_count():
    print("\n--- SML-CHILDREN ---")

    check("CHILDREN count = 3 items",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-SCOPE SML-TREE SML-CHILDREN . ; _T'], "3 ")

    check("CHILDREN count = 1 item + gap",
          mstr('<sml><seq><gap/><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-SCOPE SML-TREE SML-CHILDREN . ; _T'], "1 ")


# ===========================================================================
#  Test: SML-JUMP?
# ===========================================================================

def test_jump():
    print("\n--- SML-JUMP? ---")

    check("JUMP? on seq with jump=true",
          mstr('<sml><seq><seq jump="true"><item/></seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-SCOPE DOM-FIRST-CHILD',
           '    SML-TREE SML-JUMP? . ; _T'], "-1 ")

    check("JUMP? on seq without jump attr",
          mstr('<sml><seq><seq><item/></seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-SCOPE DOM-FIRST-CHILD',
           '    SML-TREE SML-JUMP? . ; _T'], "0 ")


# ===========================================================================
#  Test: SOM-NODE-ADD / SOM-NODE-REMOVE
# ===========================================================================

def test_node_add_remove():
    print("\n--- SML-NODE-ADD / REMOVE ---")

    check("NODE-ADD creates element",
          mstr('<sml><seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-SCOPE',
           '  S" item" S" Hello" SML-NODE-ADD',
           '  DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'item' in o)

    check("NODE-ADD node has label",
          mstr('<sml><seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-SCOPE',
           '  S" act" S" Click" SML-NODE-ADD',
           '  S" label" DOM-ATTR@ DROP TYPE ; _T'],
          check_fn=lambda o: 'Click' in o)


# ===========================================================================
#  Test: Cursor API — SOM-CURRENT / SCOPE / POSITION
# ===========================================================================

def test_cursor_read():
    print("\n--- Cursor Read API ---")

    check("CURRENT = first item after init",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  DUP SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'item' in o)

    check("SCOPE = seq after init",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  DUP SOM-SCOPE DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'seq' in o)

    check("POSITION = 0 at first item",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  DUP SOM-POSITION . ; _T'], "0 ")


# ===========================================================================
#  Test: SOM-NEXT — cursor movement
# ===========================================================================

def test_som_next():
    print("\n--- SOM-NEXT (cursor) ---")

    check("SOM-NEXT moves to second item",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-NEXT . ; _T'], "-1 ")

    check("SOM-NEXT cursor now on act",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-NEXT DROP',
           '  SML-TREE SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'act' in o)

    check("SOM-NEXT position increments",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-NEXT DROP',
           '  SML-TREE SOM-POSITION . ; _T'], "1 ")

    check("SOM-NEXT at end of seq = not moved",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-NEXT DROP',
           '  SML-TREE SOM-NEXT . ; _T'], "0 ")

    check("SOM-NEXT at end sets boundary=LAST",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-NEXT DROP',
           '  SML-TREE SOM-NEXT DROP',
           '  SML-TREE SOM-AT-BOUNDARY . ; _T'], "2 ")


# ===========================================================================
#  Test: SOM-PREV — cursor movement
# ===========================================================================

def test_som_prev():
    print("\n--- SOM-PREV (cursor) ---")

    check("SOM-PREV from second to first",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-NEXT DROP',
           '  SML-TREE SOM-PREV .',
           '  SML-TREE SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'item' in o)

    check("SOM-PREV at start = not moved",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-PREV . ; _T'], "0 ")

    check("SOM-PREV at start sets boundary=FIRST",
          mstr('<sml><seq><item/><act/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-PREV DROP',
           '  SML-TREE SOM-AT-BOUNDARY . ; _T'], "1 ")


# ===========================================================================
#  Test: Ring wrap behavior
# ===========================================================================

def test_ring_wrap():
    print("\n--- Ring Wrap ---")

    check("NEXT wraps in ring",
          mstr('<sml><ring><item/><act/></ring></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-NEXT DROP',     # act
           '  SML-TREE SOM-NEXT .',         # wrap to item
           '  SML-TREE SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'item' in o)

    check("PREV wraps in ring",
          mstr('<sml><ring><item/><act/></ring></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-PREV .',
           '  SML-TREE SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'act' in o)


# ===========================================================================
#  Test: SOM-ENTER / SOM-BACK
# ===========================================================================

def test_enter_back():
    print("\n--- SOM-ENTER / SOM-BACK ---")

    check("ENTER into nested seq",
          mstr('<sml><seq><seq><item/><act/></seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER .',
           '  SML-TREE SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'item' in o)

    check("ENTER then SCOPE = inner seq",
          mstr('<sml><seq><seq><item/></seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER DROP',
           '  SML-TREE SOM-SCOPE DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: 'seq' in o)

    check("BACK returns to parent scope",
          mstr('<sml><seq><seq><item/></seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER DROP',
           '  SML-TREE SOM-BACK .',
           '  SML-TREE SOM-SCOPE DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'seq' in o)

    check("ENTER non-scope = no move",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER . ; _T'], "0 ")


# ===========================================================================
#  Test: Trap — BACK denied
# ===========================================================================

def test_trap():
    print("\n--- Trap: BACK denied ---")

    check("BACK denied in trap",
          mstr('<sml><seq><trap><item/><act/></trap></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER DROP',      # enter trap
           '  SML-TREE SOM-BACK . ; _T'], "0 ")

    check("ENTER trap sets ctx=TRAPPED",
          mstr('<sml><seq><trap><item/></trap></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER DROP',
           '  SML-TREE SOM-CTX@ . ; _T'], "5 ")


# ===========================================================================
#  Test: Ring → MENU context
# ===========================================================================

def test_ring_context():
    print("\n--- Ring → MENU context ---")

    check("ENTER ring sets ctx=MENU",
          mstr('<sml><seq><ring><item/><act/></ring></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER DROP',
           '  SML-TREE SOM-CTX@ . ; _T'], "4 ")


# ===========================================================================
#  Test: Input Context API
# ===========================================================================

def test_input_context():
    print("\n--- Input Context API ---")

    check("CTX@ initial = NAV (0)",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-CTX@ . ; _T'], "0 ")

    check("CTX-ENTER sets context",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-CURRENT SOM-CTX-TEXT SML-TREE SOM-CTX-ENTER',
           '  SML-TREE SOM-CTX@ . ; _T'], "1 ")

    check("CTX-EXIT returns to NAV",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-CURRENT SOM-CTX-SLIDER SML-TREE SOM-CTX-ENTER',
           '  SML-TREE SOM-CTX-EXIT',
           '  SML-TREE SOM-CTX@ . ; _T'], "0 ")

    check("CTX-TARGET after enter",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-CURRENT SOM-CTX-TEXT SML-TREE SOM-CTX-ENTER',
           '  SML-TREE SOM-CTX-TARGET 0<> . ; _T'], "-1 ")

    check("CTX-VALUE set/get",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  42 SML-TREE SOM-CTX-SET-VALUE',
           '  SML-TREE SOM-CTX-VALUE . ; _T'], "42 ")


# ===========================================================================
#  Test: SOM-JUMP
# ===========================================================================

def test_som_jump():
    print("\n--- SOM-JUMP ---")

    check("JUMP to item by id",
          mstr('<sml><seq><item id="a"/><act id="b"/><val id="c"/></seq></sml>') +
          [': _T TA SML-INIT',
           '  S" c" SML-TREE SOM-JUMP .',
           '  SML-TREE SOM-CURRENT DOM-TAG-NAME TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'val' in o)

    check("JUMP to nonexistent id = no move",
          mstr('<sml><seq><item id="a"/></seq></sml>') +
          [': _T TA SML-INIT',
           '  S" zzz" SML-TREE SOM-JUMP . ; _T'], "0 ")


# ===========================================================================
#  Test: Focus Stack
# ===========================================================================

def test_focus_stack():
    print("\n--- Focus Stack ---")

    check("FS-DEPTH = 1 after init (root scope)",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-FS-DEPTH . ; _T'], "1 ")

    check("FS-DEPTH = 2 after enter",
          mstr('<sml><seq><seq><item/></seq></seq></sml>') +
          [': _T TA SML-INIT',
           '  SML-TREE SOM-ENTER DROP',
           '  SML-TREE SOM-FS-DEPTH . ; _T'], "2 ")


# ===========================================================================
#  Test: SML-PATCH stub
# ===========================================================================

def test_patch_stub():
    print("\n--- SML-PATCH stub ---")

    check("PATCH does not crash",
          mstr('<sml><seq><item/></seq></sml>') +
          [': _T TA SML-INIT',
           '  S" noop" SML-TREE SML-PATCH',
           '  SML-TREE SOM-CURRENT 0<> . ; _T'], "-1 ")


# ===========================================================================
#  Test: SOM Context Constants
# ===========================================================================

def test_constants():
    print("\n--- SOM Constants ---")

    check("SOM-CTX-NAV = 0",
          [': _T SOM-CTX-NAV . ; _T'], "0 ")
    check("SOM-CTX-TEXT = 1",
          [': _T SOM-CTX-TEXT . ; _T'], "1 ")
    check("SOM-CTX-SLIDER = 2",
          [': _T SOM-CTX-SLIDER . ; _T'], "2 ")
    check("SOM-CTX-CYCLING = 3",
          [': _T SOM-CTX-CYCLING . ; _T'], "3 ")
    check("SOM-CTX-MENU = 4",
          [': _T SOM-CTX-MENU . ; _T'], "4 ")
    check("SOM-CTX-TRAPPED = 5",
          [': _T SOM-CTX-TRAPPED . ; _T'], "5 ")

    check("SOM-RESUME-FIRST = 0",
          [': _T SOM-RESUME-FIRST . ; _T'], "0 ")
    check("SOM-RESUME-LAST = 1",
          [': _T SOM-RESUME-LAST . ; _T'], "1 ")
    check("SOM-RESUME-NONE = 2",
          [': _T SOM-RESUME-NONE . ; _T'], "2 ")

    check("SOM-BOUND-NONE = 0",
          [': _T SOM-BOUND-NONE . ; _T'], "0 ")
    check("SOM-BOUND-FIRST = 1",
          [': _T SOM-BOUND-FIRST . ; _T'], "1 ")
    check("SOM-BOUND-LAST = 2",
          [': _T SOM-BOUND-LAST . ; _T'], "2 ")


# ===========================================================================
#  Main
# ===========================================================================

if __name__ == '__main__':
    build_snapshot()

    test_constants()
    test_tree_create()
    test_type_encoding()
    test_sml_load()
    test_sml_init()
    test_first_last()
    test_next_prev()
    test_children_count()
    test_jump()
    test_node_add_remove()
    test_cursor_read()
    test_som_next()
    test_som_prev()
    test_ring_wrap()
    test_enter_back()
    test_trap()
    test_ring_context()
    test_input_context()
    test_som_jump()
    test_focus_stack()
    test_patch_stub()

    total = _pass_count + _fail_count
    print(f"\n{'='*60}")
    print(f"  {_pass_count} passed, {_fail_count} failed ({total} total)")
    print(f"{'='*60}")
    sys.exit(0 if _fail_count == 0 else 1)
