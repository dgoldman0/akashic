#!/usr/bin/env python3
"""Test suite for akashic-sml-core Forth library.

Uses the Megapad-64 emulator to boot KDOS, load core.f dependencies
and sml/core.f, then run Forth test expressions.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
MU_CORE_F  = os.path.join(ROOT_DIR, "akashic", "markup", "core.f")
SML_CORE_F = os.path.join(ROOT_DIR, "akashic", "sml", "core.f")

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

    print("[*] Building snapshot: BIOS + KDOS + string.f + utf8.f + markup/core.f + sml/core.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    utf8_lines = _load_forth_lines(UTF8_F)
    mu_lines   = _load_forth_lines(MU_CORE_F)
    sml_lines  = _load_forth_lines(SML_CORE_F)

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
                 + str_lines + utf8_lines + mu_lines + sml_lines
                 + test_helpers)
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
        for ln in err_lines[-15:]:
            print(f"    {ln}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=50_000_000):
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
            last_lines = clean.split('\n')[-3:]
            print(f"        check_fn failed")
            print(f"        got (last lines): {last_lines}")


# ===========================================================================
#  Test: Element Type Classification (SML-TYPE?)
# ===========================================================================

def test_type_classification():
    print("\n--- Element Type Classification (SML-TYPE?) ---")

    # Envelope elements → 0
    check("TYPE? sml = ENVELOPE",
          [': _T S" sml" SML-TYPE? . ; _T'], "0 ")
    check("TYPE? head = ENVELOPE",
          [': _T S" head" SML-TYPE? . ; _T'], "0 ")

    # Meta elements → 1
    check("TYPE? title = META",
          [': _T S" title" SML-TYPE? . ; _T'], "1 ")
    check("TYPE? meta = META",
          [': _T S" meta" SML-TYPE? . ; _T'], "1 ")
    check("TYPE? link = META",
          [': _T S" link" SML-TYPE? . ; _T'], "1 ")
    check("TYPE? style = META",
          [': _T S" style" SML-TYPE? . ; _T'], "1 ")
    check("TYPE? cue-def = META",
          [': _T S" cue-def" SML-TYPE? . ; _T'], "1 ")

    # Scope elements → 2
    check("TYPE? seq = SCOPE",
          [': _T S" seq" SML-TYPE? . ; _T'], "2 ")
    check("TYPE? ring = SCOPE",
          [': _T S" ring" SML-TYPE? . ; _T'], "2 ")
    check("TYPE? gate = SCOPE",
          [': _T S" gate" SML-TYPE? . ; _T'], "2 ")
    check("TYPE? trap = SCOPE",
          [': _T S" trap" SML-TYPE? . ; _T'], "2 ")

    # Position elements → 3
    check("TYPE? item = POSITION",
          [': _T S" item" SML-TYPE? . ; _T'], "3 ")
    check("TYPE? act = POSITION",
          [': _T S" act" SML-TYPE? . ; _T'], "3 ")
    check("TYPE? val = POSITION",
          [': _T S" val" SML-TYPE? . ; _T'], "3 ")
    check("TYPE? pick = POSITION",
          [': _T S" pick" SML-TYPE? . ; _T'], "3 ")
    check("TYPE? ind = POSITION",
          [': _T S" ind" SML-TYPE? . ; _T'], "3 ")
    check("TYPE? tick = POSITION",
          [': _T S" tick" SML-TYPE? . ; _T'], "3 ")
    check("TYPE? alert = POSITION",
          [': _T S" alert" SML-TYPE? . ; _T'], "3 ")

    # Struct elements → 4
    check("TYPE? announce = STRUCT",
          [': _T S" announce" SML-TYPE? . ; _T'], "4 ")
    check("TYPE? shortcut = STRUCT",
          [': _T S" shortcut" SML-TYPE? . ; _T'], "4 ")
    check("TYPE? hint = STRUCT",
          [': _T S" hint" SML-TYPE? . ; _T'], "4 ")
    check("TYPE? gap = STRUCT",
          [': _T S" gap" SML-TYPE? . ; _T'], "4 ")
    check("TYPE? lane = STRUCT",
          [': _T S" lane" SML-TYPE? . ; _T'], "4 ")

    # Compose elements → 5
    check("TYPE? frag = COMPOSE",
          [': _T S" frag" SML-TYPE? . ; _T'], "5 ")
    check("TYPE? slot = COMPOSE",
          [': _T S" slot" SML-TYPE? . ; _T'], "5 ")

    # Unknown → 6
    check("TYPE? div = UNKNOWN",
          [': _T S" div" SML-TYPE? . ; _T'], "6 ")
    check("TYPE? span = UNKNOWN",
          [': _T S" span" SML-TYPE? . ; _T'], "6 ")
    check("TYPE? empty = UNKNOWN",
          [': _T S" " SML-TYPE? . ; _T'], "6 ")


# ===========================================================================
#  Test: Category Predicates
# ===========================================================================

def test_predicates():
    print("\n--- Category Predicates ---")

    check("NAVIGABLE? scope=yes",
          [': _T SML-T-SCOPE SML-NAVIGABLE? . ; _T'], "-1 ")
    check("NAVIGABLE? position=yes",
          [': _T SML-T-POSITION SML-NAVIGABLE? . ; _T'], "-1 ")
    check("NAVIGABLE? meta=no",
          [': _T SML-T-META SML-NAVIGABLE? . ; _T'], "0 ")
    check("NAVIGABLE? struct=no",
          [': _T SML-T-STRUCT SML-NAVIGABLE? . ; _T'], "0 ")

    check("CONTAINER? envelope=yes",
          [': _T SML-T-ENVELOPE SML-CONTAINER? . ; _T'], "-1 ")
    check("CONTAINER? scope=yes",
          [': _T SML-T-SCOPE SML-CONTAINER? . ; _T'], "-1 ")
    check("CONTAINER? compose=yes",
          [': _T SML-T-COMPOSE SML-CONTAINER? . ; _T'], "-1 ")
    check("CONTAINER? position=no",
          [': _T SML-T-POSITION SML-CONTAINER? . ; _T'], "0 ")
    check("CONTAINER? meta=no",
          [': _T SML-T-META SML-CONTAINER? . ; _T'], "0 ")


# ===========================================================================
#  Test: Content Model (SML-VALID-CHILD?)
# ===========================================================================

def test_content_model():
    print("\n--- Content Model (SML-VALID-CHILD?) ---")

    # Envelope children: envelope yes, meta yes, scope yes, compose yes, position no
    check("CHILD? envelope→envelope = yes",
          [': _T SML-T-ENVELOPE SML-T-ENVELOPE SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? envelope→meta = yes",
          [': _T SML-T-ENVELOPE SML-T-META SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? envelope→scope = yes",
          [': _T SML-T-ENVELOPE SML-T-SCOPE SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? envelope→compose = yes",
          [': _T SML-T-ENVELOPE SML-T-COMPOSE SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? envelope→position = no",
          [': _T SML-T-ENVELOPE SML-T-POSITION SML-VALID-CHILD? . ; _T'], "0 ")

    # Scope children: scope yes, position yes, struct yes, compose yes, meta no
    check("CHILD? scope→position = yes",
          [': _T SML-T-SCOPE SML-T-POSITION SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? scope→scope = yes",
          [': _T SML-T-SCOPE SML-T-SCOPE SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? scope→struct = yes",
          [': _T SML-T-SCOPE SML-T-STRUCT SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? scope→compose = yes",
          [': _T SML-T-SCOPE SML-T-COMPOSE SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? scope→meta = no",
          [': _T SML-T-SCOPE SML-T-META SML-VALID-CHILD? . ; _T'], "0 ")

    # Position children: struct yes, compose yes, scope no
    check("CHILD? position→struct = yes",
          [': _T SML-T-POSITION SML-T-STRUCT SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? position→compose = yes",
          [': _T SML-T-POSITION SML-T-COMPOSE SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? position→scope = no",
          [': _T SML-T-POSITION SML-T-SCOPE SML-VALID-CHILD? . ; _T'], "0 ")

    # Compose children: scope yes, position yes, struct yes, compose yes
    check("CHILD? compose→scope = yes",
          [': _T SML-T-COMPOSE SML-T-SCOPE SML-VALID-CHILD? . ; _T'], "-1 ")
    check("CHILD? compose→position = yes",
          [': _T SML-T-COMPOSE SML-T-POSITION SML-VALID-CHILD? . ; _T'], "-1 ")

    # Meta and struct are leaf — no children
    check("CHILD? meta→anything = no",
          [': _T SML-T-META SML-T-META SML-VALID-CHILD? . ; _T'], "0 ")
    check("CHILD? struct→anything = no",
          [': _T SML-T-STRUCT SML-T-POSITION SML-VALID-CHILD? . ; _T'], "0 ")


# ===========================================================================
#  Test: Attribute Access (SML-ATTR)
# ===========================================================================

def test_attributes():
    print("\n--- Attribute Access ---")

    # SML-ATTR on a tag body
    check("ATTR id from body",
          mstr('item id="nav" label="Home"') +
          [': _T TA S" id" SML-ATTR . TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'nav' in o)

    check("ATTR label from body",
          mstr('item id="nav" label="Home"') +
          [': _T TA S" label" SML-ATTR . TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'Home' in o)

    check("ATTR missing returns 0",
          mstr('item id="nav"') +
          [': _T TA S" class" SML-ATTR . . . ; _T'],
          check_fn=lambda o: '0 0 0' in o)

    # Convenience shortcuts
    check("ATTR-ID shortcut",
          mstr('item id="main" label="X"') +
          [': _T TA MU-SKIP-NAME SML-ATTR-ID . TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'main' in o)

    check("ATTR-LABEL shortcut",
          mstr('item id="x" label="Settings"') +
          [': _T TA MU-SKIP-NAME SML-ATTR-LABEL . TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'Settings' in o)

    check("ATTR-KIND shortcut",
          mstr('val kind="text"') +
          [': _T TA MU-SKIP-NAME SML-ATTR-KIND . TYPE ; _T'],
          check_fn=lambda o: '-1' in o and 'text' in o)


# ===========================================================================
#  Test: SML-ELEM-NTH
# ===========================================================================

def test_elem_nth():
    print("\n--- Element Enumeration (SML-ELEM-NTH) ---")

    # First element should be "sml" (type ENVELOPE=0)
    check("ELEM-NTH 0 = sml",
          [': _T 0 SML-ELEM-NTH . TYPE ; _T'],
          check_fn=lambda o: '0' in o and 'sml' in o)

    # Second element should be "head" (type ENVELOPE=0)
    check("ELEM-NTH 1 = head",
          [': _T 1 SML-ELEM-NTH . TYPE ; _T'],
          check_fn=lambda o: '0' in o and 'head' in o)

    # Element 2 = "title" (type META=1)
    check("ELEM-NTH 2 = title",
          [': _T 2 SML-ELEM-NTH . TYPE ; _T'],
          check_fn=lambda o: '1' in o and 'title' in o)

    # Last element = "slot" (#24, type COMPOSE=5)
    check("ELEM-NTH 24 = slot",
          [': _T 24 SML-ELEM-NTH . TYPE ; _T'],
          check_fn=lambda o: '5' in o and 'slot' in o)

    # Out of range → 0 0 UNKNOWN
    check("ELEM-NTH 25 = out of range",
          [': _T 25 SML-ELEM-NTH . . . ; _T'],
          check_fn=lambda o: '6 0 0' in o)

    check("ELEM-NTH -1 = out of range",
          [': _T -1 SML-ELEM-NTH . . . ; _T'],
          check_fn=lambda o: '6 0 0' in o)


# ===========================================================================
#  Test: Scope Kind Checks
# ===========================================================================

def test_scope_kinds():
    print("\n--- Scope Kind Checks ---")

    check("SML-SEQ? yes",
          [': _T S" seq" SML-SEQ? . ; _T'], "-1 ")
    check("SML-SEQ? no",
          [': _T S" ring" SML-SEQ? . ; _T'], "0 ")
    check("SML-RING? yes",
          [': _T S" ring" SML-RING? . ; _T'], "-1 ")
    check("SML-GATE? yes",
          [': _T S" gate" SML-GATE? . ; _T'], "-1 ")
    check("SML-TRAP? yes",
          [': _T S" trap" SML-TRAP? . ; _T'], "-1 ")


# ===========================================================================
#  Test: Val Kind Validation
# ===========================================================================

def test_val_kinds():
    print("\n--- Val Kind Validation ---")

    check("VALID-VAL-KIND? text",
          [': _T S" text" SML-VALID-VAL-KIND? . ; _T'], "-1 ")
    check("VALID-VAL-KIND? range",
          [': _T S" range" SML-VALID-VAL-KIND? . ; _T'], "-1 ")
    check("VALID-VAL-KIND? toggle",
          [': _T S" toggle" SML-VALID-VAL-KIND? . ; _T'], "-1 ")
    check("VALID-VAL-KIND? display",
          [': _T S" display" SML-VALID-VAL-KIND? . ; _T'], "-1 ")
    check("VALID-VAL-KIND? checkbox = no",
          [': _T S" checkbox" SML-VALID-VAL-KIND? . ; _T'], "0 ")
    check("VALID-VAL-KIND? empty = no",
          [': _T S" " SML-VALID-VAL-KIND? . ; _T'], "0 ")


# ===========================================================================
#  Test: Pick Count
# ===========================================================================

def test_pick_count():
    print("\n--- Pick Count ---")

    check("PICK-COUNT 3 choices",
          mstr('pick choices="a|b|c"') +
          [': _T TA MU-SKIP-NAME SML-PICK-COUNT . ; _T'], "3 ")

    check("PICK-COUNT 1 choice (no |)",
          mstr('pick choices="single"') +
          [': _T TA MU-SKIP-NAME SML-PICK-COUNT . ; _T'], "1 ")

    check("PICK-COUNT no choices attr",
          mstr('pick label="X"') +
          [': _T TA MU-SKIP-NAME SML-PICK-COUNT . ; _T'], "0 ")


# ===========================================================================
#  Test: SML-VALID?  — Document Validation
# ===========================================================================

def test_validation():
    print("\n--- Document Validation (SML-VALID?) ---")

    # Valid minimal doc
    check("VALID? minimal <sml></sml>",
          mstr('<sml></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")

    # Valid with head + seq
    check("VALID? sml > head + seq",
          mstr('<sml><head><title>T</title></head><seq><item/></seq></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")

    # Valid with ring scope
    check("VALID? sml > ring > items",
          mstr('<sml><ring><item/><item/><item/></ring></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")

    # Valid nested scopes
    check("VALID? nested scopes",
          mstr('<sml><seq><seq><item/></seq></seq></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")

    # Valid compose element
    check("VALID? compose in scope",
          mstr('<sml><seq><frag><item/></frag></seq></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")

    # Valid struct in scope
    check("VALID? struct in scope",
          mstr('<sml><seq><gap/><item/></seq></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")

    # Invalid: wrong root
    check("VALID? bad root <div>",
          mstr('<div></div>') +
          [': _T TA SML-VALID? . SML-ERR @ . ; _T'],
          check_fn=lambda o: '0 ' in o and '1 ' in o)

    # Invalid: unknown element
    check("VALID? unknown <div> inside",
          mstr('<sml><div/></sml>') +
          [': _T TA SML-VALID? . SML-ERR @ . ; _T'],
          check_fn=lambda o: '0 ' in o and '2 ' in o)

    # Invalid: bad nesting (position inside meta)
    # head is envelope, meta elements can be children, but item cannot be in head directly
    # Actually head is envelope type, and position IS NOT valid child of envelope
    check("VALID? position in envelope = bad",
          mstr('<sml><item/></sml>') +
          [': _T TA SML-VALID? . SML-ERR @ . ; _T'],
          check_fn=lambda o: '0 ' in o and '3 ' in o)

    # Empty doc
    check("VALID? empty string",
          [': _T 0 0 SML-VALID? . SML-ERR @ . ; _T'],
          check_fn=lambda o: '0 ' in o and '5 ' in o)

    # Self-closing elements
    check("VALID? self-closing items",
          mstr('<sml><seq><item/><act/><val/></seq></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")

    # Comments are allowed
    check("VALID? with comments",
          mstr('<sml><!-- comment --><seq><item/></seq></sml>') +
          [': _T TA SML-VALID? . ; _T'], "-1 ")


# ===========================================================================
#  Test: SML-COUNT-CHILDREN
# ===========================================================================

def test_count_children():
    print("\n--- Count Children ---")

    check("COUNT-CHILDREN 3 items in seq",
          mstr('<seq><item/><item/><item/></seq>') +
          [': _T TA SML-COUNT-CHILDREN . ; _T'], "3 ")

    check("COUNT-CHILDREN 1 item",
          mstr('<seq><item/></seq>') +
          [': _T TA SML-COUNT-CHILDREN . ; _T'], "1 ")

    check("COUNT-CHILDREN 0 empty",
          mstr('<seq></seq>') +
          [': _T TA SML-COUNT-CHILDREN . ; _T'], "0 ")

    check("COUNT-CHILDREN nested scopes",
          mstr('<seq><seq><item/></seq><item/></seq>') +
          [': _T TA SML-COUNT-CHILDREN . ; _T'], "2 ")


# ===========================================================================
#  Test: SML-TAG-BODY
# ===========================================================================

def test_tag_body():
    print("\n--- Tag Body Extraction ---")

    check("TAG-BODY gets name and body",
          mstr('<item id="x" label="Y">') +
          [': _T TA SML-TAG-BODY TYPE SPACE TYPE ; _T'],
          check_fn=lambda o: 'item' in o)


# ===========================================================================
#  Test: Error state management
# ===========================================================================

def test_errors():
    print("\n--- Error State ---")

    check("initial ERR = 0",
          [': _T SML-ERR @ . ; _T'], "0 ")
    check("SML-OK? initially true",
          [': _T SML-OK? . ; _T'], "-1 ")
    check("FAIL sets ERR",
          [': _T 3 SML-FAIL SML-ERR @ . ; _T'], "3 ")
    check("CLEAR-ERR resets",
          [': _T 3 SML-FAIL SML-CLEAR-ERR SML-OK? . ; _T'], "-1 ")


# ===========================================================================
#  Main
# ===========================================================================

if __name__ == '__main__':
    build_snapshot()

    test_type_classification()
    test_predicates()
    test_content_model()
    test_attributes()
    test_elem_nth()
    test_scope_kinds()
    test_val_kinds()
    test_pick_count()
    test_validation()
    test_count_children()
    test_tag_body()
    test_errors()

    total = _pass_count + _fail_count
    print(f"\n{'='*60}")
    print(f"  {_pass_count} passed, {_fail_count} failed ({total} total)")
    print(f"{'='*60}")
    sys.exit(0 if _fail_count == 0 else 1)
