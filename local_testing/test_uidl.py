#!/usr/bin/env python3
"""Test suite for akashic LIRAQ UIDL document model (uidl.f, Layer 3).

Structural tests — parsing UIDL XML, element types, arrangement,
ID registry, attributes, tree traversal, binding, when, collections,
representation sets.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

STRING_F   = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
FP32_F     = os.path.join(ROOT_DIR, "akashic", "math", "fp32.f")
FIXED_F    = os.path.join(ROOT_DIR, "akashic", "math", "fixed.f")
ST_F       = os.path.join(ROOT_DIR, "akashic", "liraq", "state-tree.f")
LEL_F      = os.path.join(ROOT_DIR, "akashic", "liraq", "lel.f")
CORE_F     = os.path.join(ROOT_DIR, "akashic", "markup", "core.f")
XML_F      = os.path.join(ROOT_DIR, "akashic", "markup", "xml.f")
UIDL_F     = os.path.join(ROOT_DIR, "akashic", "liraq", "uidl.f")

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
    if _snapshot:
        return _snapshot
    libs = [
        ("string.f",     STRING_F),
        ("fp32.f",       FP32_F),
        ("fixed.f",      FIXED_F),
        ("state-tree.f", ST_F),
        ("lel.f",        LEL_F),
        ("core.f",       CORE_F),
        ("xml.f",        XML_F),
        ("uidl.f",       UIDL_F),
    ]
    print(f"[*] Building snapshot: BIOS + KDOS + {len(libs)} libraries ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    all_lib_lines = []
    for name, path in libs:
        ll = _load_forth_lines(path)
        all_lib_lines.extend(ll)
        print(f"    loaded {name}: {len(ll)} lines")

    helpers = [
        'CREATE _TB 8192 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': .R  ( n -- ) 35 EMIT . CR ;',
        ': .S  ( a l -- ) 35 EMIT TYPE CR ;',
    ]

    all_lines = kdos_lines + ['ENTER-USERLAND'] + all_lib_lines + helpers
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    sys_obj.cpu.mem[:len(bios_code)] = bios_code
    sys_obj.boot()

    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0
    max_steps = 800_000_000
    buf = capture_uart(sys_obj)
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)

    text = uart_text(buf)
    errors = False
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            print(f"  [!] {l}")
            errors = True
    if errors:
        print("[!] SNAPSHOT ERRORS — some words not found!")
    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=80_000_000):
    mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    payload = "\n".join(lines) + "\nBYE\n"
    data = payload.encode(); pos = 0; steps = 0
    while steps < max_steps:
        if sys_obj.cpu.halted:
            break
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            if pos < len(data):
                chunk = _next_line_chunk(data, pos)
                sys_obj.uart.inject_input(chunk); pos += len(chunk)
            else:
                break
            continue
        batch = sys_obj.run_batch(min(100_000, max_steps - steps))
        steps += max(batch, 1)
    return uart_text(buf)

# ── Test runner ──

_pass = 0
_fail = 0

def tstr(s):
    """Build string s in _TB via TR/TC.  Returns list of Forth lines."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp == -1:
            sp = 70
        lines.append(full[:sp])
        full = full[sp:].lstrip()
    if full:
        lines.append(full)
    return lines

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass, _fail
    output = run_forth(forth_lines)
    # Filter echoed input (> prefix), prompts, and TC command fragments
    result_lines = []
    for line in output.split('\n'):
        s = line.strip()
        if not s or s.startswith('>') or s in ('ok', 'Bye!'):
            continue
        # Skip TC/TR command fragments (wrapped tstr echoes)
        if ' TC' in s or s.startswith('TC ') or s.startswith('TR'):
            continue
        result_lines.append(s)
    clean = '\n'.join(result_lines) if result_lines else output.strip()
    ok = check_fn(clean) if check_fn else (expected in clean if expected else True)
    if ok:
        print(f"  PASS  {name}")
        _pass += 1
    else:
        _fail += 1
        print(f"  FAIL  {name}")
        if expected:
            print(f"        expected: '{expected}'")
        for l in output.strip().split('\n')[-6:]:
            print(f"        got:      '{l}'")

# =====================================================================
#  Reference UIDL Documents
# =====================================================================

# Minimal document
DOC_MINIMAL = '<uidl><region id="r1" /></uidl>'

# All 16 semantic element types (self-closing for simplicity)
DOC_ALL_TYPES = (
    '<uidl>'
    '<region id="e1" />'
    '<group id="e2" />'
    '<separator id="e3" />'
    '<meta id="e4" key="title" value="test" />'
    '<label id="e5" text="hello" />'
    '<media id="e6"><rep modality="description" text="d" /></media>'
    '<symbol id="e7" name="star" />'
    '<canvas id="e8" />'
    '<action id="e9" on-activate="do-thing" />'
    '<input id="e10" input-type="text" />'
    '<selector id="e11" mode="single" />'
    '<toggle id="e12" />'
    '<range id="e13" min="0" max="100" />'
    '<collection id="e14"><template><label id="t-{_index}" /></template></collection>'
    '<table id="e15" />'
    '<indicator id="e16" mode="determinate" />'
    '</uidl>'
)

# Arrangement modes
DOC_ARRANGE = (
    '<uidl>'
    '<region id="r-dock" arrange="dock" />'
    '<region id="r-flex" arrange="flex" />'
    '<region id="r-stack" arrange="stack" />'
    '<region id="r-flow" arrange="flow" />'
    '<region id="r-grid" arrange="grid" />'
    '<region id="r-none" arrange="none" />'
    '</uidl>'
)

# Nested structure with roles
DOC_NESTED = (
    '<uidl>'
    '<region id="nav" arrange="flex" role="navigation">'
    '  <action id="btn-a" label="A" on-activate="go-a" />'
    '  <action id="btn-b" label="B" on-activate="go-b" />'
    '</region>'
    '<region id="main" arrange="dock" role="primary">'
    '  <group id="header" role="header">'
    '    <label id="title" text="Hello" />'
    '  </group>'
    '  <group id="content" arrange="flow">'
    '    <label id="msg" text="World" />'
    '    <separator id="sep1" />'
    '    <label id="msg2" text="!" />'
    '  </group>'
    '</region>'
    '</uidl>'
)

# Data binding
DOC_BIND = (
    '<uidl>'
    '<label id="lbl1" bind="=user.name" />'
    '<label id="lbl2" text="static" />'
    '<indicator id="ind1" bind="=sensors.pressure" mode="determinate" />'
    '<input id="inp1" bind="=form.email" input-type="email" />'
    '</uidl>'
)

# When conditions
DOC_WHEN = (
    '<uidl>'
    '<label id="visible" text="always" />'
    '<label id="conditional" text="maybe" when="=gt(sensors.pressure, 90)" />'
    '<label id="hidden" text="nope" when="=false" />'
    '</uidl>'
)

# Media with representation sets
DOC_MEDIA = (
    '<uidl>'
    '<media id="status">'
    '  <rep modality="visual" src="diagram.svg" />'
    '  <rep modality="auditory" text="All systems nominal" />'
    '  <rep modality="tactile" pattern="smooth" />'
    '  <rep modality="description" text="Ship diagram, all green" />'
    '</media>'
    '</uidl>'
)

# Collection with template and empty
DOC_COLLECTION = (
    '<uidl>'
    '<collection id="alerts" arrange="flow">'
    '  <template>'
    '    <group id="alert-{_index}" role="alert">'
    '      <label id="alert-msg-{_index}" />'
    '    </group>'
    '  </template>'
    '  <empty>'
    '    <label id="no-alerts" text="No alerts" />'
    '  </empty>'
    '</collection>'
    '</uidl>'
)

# Duplicate ID (should fail)
DOC_DUP_ID = (
    '<uidl>'
    '<label id="same" text="first" />'
    '<label id="same" text="second" />'
    '</uidl>'
)

# Generic attributes (on-activate, emit, set-state, dock-position, etc.)
DOC_ATTRS = (
    '<uidl>'
    '<action id="a1" on-activate="nav-switch" label="Go" />'
    '<action id="a2" emit="help-request" label="Help" />'
    '<action id="a3" set-state="ui.mode" set-value="dark" label="Dark" />'
    '<group id="g1" dock-position="start" flex-weight="2" />'
    '</uidl>'
)

# =====================================================================
#  Tests
# =====================================================================

def test_parse_basics():
    """Basic parsing: minimal doc, root detection, element count."""
    print("\n── Parse Basics ──\n")

    check("parse minimal doc",
          tstr(DOC_MINIMAL) + [
              'TA UIDL-PARSE . CR'],
          '-1')

    check("root exists",
          tstr(DOC_MINIMAL) + [
              'TA UIDL-PARSE DROP',
              'UIDL-ROOT 0<> . CR'],
          '-1')

    check("root type is UIDL",
          tstr(DOC_MINIMAL) + [
              'TA UIDL-PARSE DROP',
              'UIDL-ROOT UIDL-TYPE . CR'],
          '17')

    check("element count minimal",
          tstr(DOC_MINIMAL) + [
              'TA UIDL-PARSE DROP',
              'UIDL-ELEM-COUNT . CR'],
          '2')  # uidl + region

    check("no-root error",
          ['TR', 'TA UIDL-PARSE . CR'],
          '0')

    check("bad-root error",
          tstr('<div id="x"/>') + [
              'TA UIDL-PARSE . CR'],
          '0')

    check("error code for bad root",
          tstr('<div id="x"/>') + [
              'TA UIDL-PARSE DROP',
              'UIDL-ERR . CR'],
          '1')  # UIDL-E-NO-ROOT

def test_element_types():
    """All 16 semantic element types + pseudo-types."""
    print("\n── Element Types ──\n")

    # Parse the big doc with all types
    setup = tstr(DOC_ALL_TYPES) + ['TA UIDL-PARSE DROP']

    check("element count all-types",
          setup + ['UIDL-ELEM-COUNT . CR'],
          '20')  # uidl + 16 semantic + template + rep + label inside template

    type_checks = [
        ("e1",  "1",  "region"),
        ("e2",  "2",  "group"),
        ("e3",  "3",  "separator"),
        ("e4",  "4",  "meta"),
        ("e5",  "5",  "label"),
        ("e6",  "6",  "media"),
        ("e7",  "7",  "symbol"),
        ("e8",  "8",  "canvas"),
        ("e9",  "9",  "action"),
        ("e10", "10", "input"),
        ("e11", "11", "selector"),
        ("e12", "12", "toggle"),
        ("e13", "13", "range"),
        ("e14", "14", "collection"),
        ("e15", "15", "table"),
        ("e16", "16", "indicator"),
    ]

    for eid, etype, ename in type_checks:
        check(f"type {ename}",
              setup + tstr(eid) + [
                  f'TA UIDL-BY-ID DUP 0<> IF UIDL-TYPE . ELSE DROP 0 . THEN CR'],
              etype)

def test_type_name():
    """UIDL-TYPE-NAME returns correct strings."""
    print("\n── Type Names ──\n")

    names = [
        (0, "none"), (1, "region"), (5, "label"), (9, "action"),
        (14, "collection"), (16, "indicator"), (17, "uidl"),
        (18, "template"), (20, "rep"),
    ]
    for tnum, tname in names:
        check(f"type-name {tnum}={tname}",
              [f'{tnum} UIDL-TYPE-NAME TYPE CR'],
              tname)

def test_id_registry():
    """ID lookup, uniqueness enforcement."""
    print("\n── ID Registry ──\n")

    setup = tstr(DOC_NESTED) + ['TA UIDL-PARSE DROP']

    check("lookup existing ID",
          setup + tstr('btn-a') + [
              'TA UIDL-BY-ID 0<> . CR'],
          '-1')

    check("lookup missing ID",
          setup + tstr('nonexistent') + [
              'TA UIDL-BY-ID . CR'],
          '0')

    check("lookup returns correct element",
          setup + tstr('title') + [
              'TA UIDL-BY-ID UIDL-TYPE . CR'],
          '5')  # UIDL-T-LABEL

    # Duplicate ID should fail parse
    check("duplicate ID detection",
          tstr(DOC_DUP_ID) + [
              'TA UIDL-PARSE . CR'],
          '0')

    check("dup-ID error code",
          tstr(DOC_DUP_ID) + [
              'TA UIDL-PARSE DROP',
              'UIDL-ERR . CR'],
          '2')  # UIDL-E-DUP-ID

def test_element_id():
    """UIDL-ID returns the correct ID string."""
    print("\n── Element ID ──\n")

    setup = tstr(DOC_NESTED) + ['TA UIDL-PARSE DROP']

    check("ID string nav",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-ID TYPE CR'],
          'nav')

    check("ID string btn-a",
          setup + tstr('btn-a') + [
              'TA UIDL-BY-ID UIDL-ID TYPE CR'],
          'btn-a')

    check("ID string title",
          setup + tstr('title') + [
              'TA UIDL-BY-ID UIDL-ID TYPE CR'],
          'title')

def test_arrangement():
    """Arrangement mode parsing for all 6 modes."""
    print("\n── Arrangement ──\n")

    setup = tstr(DOC_ARRANGE) + ['TA UIDL-PARSE DROP']

    modes = [
        ("r-dock",  "1", "dock"),
        ("r-flex",  "2", "flex"),
        ("r-stack", "3", "stack"),
        ("r-flow",  "4", "flow"),
        ("r-grid",  "5", "grid"),
        ("r-none",  "0", "none"),
    ]

    for eid, mode_val, mode_name in modes:
        check(f"arrange {mode_name}",
              setup + tstr(eid) + [
                  f'TA UIDL-BY-ID UIDL-ARRANGE . CR'],
              mode_val)

def test_roles():
    """Role attribute extraction."""
    print("\n── Roles ──\n")

    setup = tstr(DOC_NESTED) + ['TA UIDL-PARSE DROP']

    check("role navigation",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-ROLE TYPE CR'],
          'navigation')

    check("role primary",
          setup + tstr('main') + [
              'TA UIDL-BY-ID UIDL-ROLE TYPE CR'],
          'primary')

    check("role header",
          setup + tstr('header') + [
              'TA UIDL-BY-ID UIDL-ROLE TYPE CR'],
          'header')

    check("no role → empty",
          setup + tstr('content') + [
              'TA UIDL-BY-ID UIDL-ROLE NIP . CR'],
          '0')  # length = 0

def test_tree_traversal():
    """Parent, children, siblings."""
    print("\n── Tree Traversal ──\n")

    setup = tstr(DOC_NESTED) + ['TA UIDL-PARSE DROP']

    # Root children count (nav + main = 2)
    check("root children count",
          setup + ['UIDL-ROOT UIDL-NCHILDREN . CR'],
          '2')

    # Nav children count (btn-a + btn-b = 2)
    check("nav children count",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-NCHILDREN . CR'],
          '2')

    # Content children count (msg + sep1 + msg2 = 3)
    check("content children count",
          setup + tstr('content') + [
              'TA UIDL-BY-ID UIDL-NCHILDREN . CR'],
          '3')

    # First child of nav is btn-a
    check("first child of nav",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-FIRST-CHILD UIDL-ID TYPE CR'],
          'btn-a')

    # Last child of nav is btn-b
    check("last child of nav",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-LAST-CHILD UIDL-ID TYPE CR'],
          'btn-b')

    # Next sibling of btn-a is btn-b
    check("next sib of btn-a",
          setup + tstr('btn-a') + [
              'TA UIDL-BY-ID UIDL-NEXT-SIB UIDL-ID TYPE CR'],
          'btn-b')

    # Prev sibling of btn-b is btn-a
    check("prev sib of btn-b",
          setup + tstr('btn-b') + [
              'TA UIDL-BY-ID UIDL-PREV-SIB UIDL-ID TYPE CR'],
          'btn-a')

    # Parent of btn-a is nav
    check("parent of btn-a",
          setup + tstr('btn-a') + [
              'TA UIDL-BY-ID UIDL-PARENT UIDL-ID TYPE CR'],
          'nav')

    # Parent of nav is uidl root
    check("parent of nav is root",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-PARENT UIDL-TYPE . CR'],
          '17')  # UIDL-T-UIDL

    # No next sib for last child
    check("no next sib for btn-b",
          setup + tstr('btn-b') + [
              'TA UIDL-BY-ID UIDL-NEXT-SIB . CR'],
          '0')

    # No prev sib for first child
    check("no prev sib for btn-a",
          setup + tstr('btn-a') + [
              'TA UIDL-BY-ID UIDL-PREV-SIB . CR'],
          '0')

    # Header has 1 child (title)
    check("header nchildren",
          setup + tstr('header') + [
              'TA UIDL-BY-ID UIDL-NCHILDREN . CR'],
          '1')

    # Content: first child is msg, last is msg2
    check("content first child",
          setup + tstr('content') + [
              'TA UIDL-BY-ID UIDL-FIRST-CHILD UIDL-ID TYPE CR'],
          'msg')

    check("content last child",
          setup + tstr('content') + [
              'TA UIDL-BY-ID UIDL-LAST-CHILD UIDL-ID TYPE CR'],
          'msg2')

    # Sibling chain: msg → sep1 → msg2
    check("sibling chain",
          setup + tstr('msg') + [
              'TA UIDL-BY-ID UIDL-NEXT-SIB UIDL-ID TYPE CR'],
          'sep1')

    check("sibling chain 2",
          setup + tstr('sep1') + [
              'TA UIDL-BY-ID UIDL-NEXT-SIB UIDL-ID TYPE CR'],
          'msg2')

def test_self_closing():
    """Self-closing elements have UIDL-F-SELFCLOSE flag."""
    print("\n── Self-Closing ──\n")

    setup = tstr(DOC_MINIMAL) + ['TA UIDL-PARSE DROP']

    check("self-close flag on region",
          setup + tstr('r1') + [
              'TA UIDL-BY-ID UIDL-FLAGS 1 AND . CR'],
          '1')  # UIDL-F-SELFCLOSE = 1

    # uidl root is NOT self-closing
    check("root not self-closing",
          setup + ['UIDL-ROOT UIDL-FLAGS 1 AND . CR'],
          '0')

def test_two_way_flag():
    """Interactive elements get UIDL-F-TWOWAY flag."""
    print("\n── Two-Way Flag ──\n")

    setup = tstr(DOC_ALL_TYPES) + ['TA UIDL-PARSE DROP']

    check("input has twoway",
          setup + tstr('e10') + [
              'TA UIDL-BY-ID UIDL-FLAGS 2 AND . CR'],
          '2')

    check("selector has twoway",
          setup + tstr('e11') + [
              'TA UIDL-BY-ID UIDL-FLAGS 2 AND . CR'],
          '2')

    check("toggle has twoway",
          setup + tstr('e12') + [
              'TA UIDL-BY-ID UIDL-FLAGS 2 AND . CR'],
          '2')

    check("range has twoway",
          setup + tstr('e13') + [
              'TA UIDL-BY-ID UIDL-FLAGS 2 AND . CR'],
          '2')

    # Non-interactive should NOT have twoway
    check("label no twoway",
          setup + tstr('e5') + [
              'TA UIDL-BY-ID UIDL-FLAGS 2 AND . CR'],
          '0')

    check("action no twoway",
          setup + tstr('e9') + [
              'TA UIDL-BY-ID UIDL-FLAGS 2 AND . CR'],
          '0')

def test_bind():
    """Bind attribute parsing (with '=' stripping)."""
    print("\n── Data Binding ──\n")

    setup = tstr(DOC_BIND) + ['TA UIDL-PARSE DROP']

    check("bind present flag",
          setup + tstr('lbl1') + [
              'TA UIDL-BY-ID UIDL-BIND IF 2DROP 1 ELSE 0 THEN . CR'],
          '1')

    check("bind expr stripped",
          setup + tstr('lbl1') + [
              'TA UIDL-BY-ID UIDL-BIND IF TYPE ELSE 2DROP THEN CR'],
          'user.name')

    check("bind absent flag",
          setup + tstr('lbl2') + [
              'TA UIDL-BY-ID UIDL-BIND IF 2DROP 1 ELSE 0 THEN . CR'],
          '0')

    check("bind on indicator",
          setup + tstr('ind1') + [
              'TA UIDL-BY-ID UIDL-BIND IF TYPE ELSE 2DROP THEN CR'],
          'sensors.pressure')

    check("bind on input",
          setup + tstr('inp1') + [
              'TA UIDL-BY-ID UIDL-BIND IF TYPE ELSE 2DROP THEN CR'],
          'form.email')

def test_when():
    """When attribute parsing."""
    print("\n── When Condition ──\n")

    setup = tstr(DOC_WHEN) + ['TA UIDL-PARSE DROP']

    check("when absent → flag 0",
          setup + tstr('visible') + [
              'TA UIDL-BY-ID UIDL-WHEN IF 2DROP 1 ELSE 0 THEN . CR'],
          '0')

    check("when present → flag -1",
          setup + tstr('conditional') + [
              'TA UIDL-BY-ID UIDL-WHEN IF 2DROP 1 ELSE 0 THEN . CR'],
          '1')

    check("when expr stripped gt",
          setup + tstr('conditional') + [
              'TA UIDL-BY-ID UIDL-WHEN IF TYPE ELSE 2DROP THEN CR'],
          'gt(sensors.pressure, 90)')

    check("when false literal",
          setup + tstr('hidden') + [
              'TA UIDL-BY-ID UIDL-WHEN IF TYPE ELSE 2DROP THEN CR'],
          'false')

def test_generic_attrs():
    """Generic attributes stored in linked list."""
    print("\n── Generic Attributes ──\n")

    setup = tstr(DOC_ATTRS) + ['TA UIDL-PARSE DROP']

    check("on-activate attr",
          setup + tstr('a1') + [
              'TA UIDL-BY-ID',
              'S" on-activate" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'nav-switch')

    check("label attr",
          setup + tstr('a1') + [
              'TA UIDL-BY-ID',
              'S" label" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'Go')

    check("emit attr",
          setup + tstr('a2') + [
              'TA UIDL-BY-ID',
              'S" emit" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'help-request')

    check("set-state attr",
          setup + tstr('a3') + [
              'TA UIDL-BY-ID',
              'S" set-state" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'ui.mode')

    check("set-value attr",
          setup + tstr('a3') + [
              'TA UIDL-BY-ID',
              'S" set-value" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'dark')

    check("dock-position attr",
          setup + tstr('g1') + [
              'TA UIDL-BY-ID',
              'S" dock-position" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'start')

    check("flex-weight attr",
          setup + tstr('g1') + [
              'TA UIDL-BY-ID',
              'S" flex-weight" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          '2')

    check("missing attr → flag 0",
          setup + tstr('a1') + [
              'TA UIDL-BY-ID',
              'S" nonexistent" UIDL-ATTR IF 2DROP 1 ELSE 0 THEN . CR'],
          '0')

def test_attr_iteration():
    """Iterate all attributes on an element."""
    print("\n── Attribute Iteration ──\n")

    setup = tstr(DOC_ATTRS) + ['TA UIDL-PARSE DROP',
        ': _CNT-ATTRS UIDL-ATTR-FIRST 0 BEGIN OVER 0<> WHILE SWAP UIDL-ATTR-NEXT SWAP 1+ REPEAT NIP ;']

    # a1 has: on-activate, label (generic attrs only, id is special)
    check("attr count on a1",
          setup + tstr('a1') + [
              'TA UIDL-BY-ID _CNT-ATTRS . CR'],
          '2')  # on-activate + label

    # g1 has: dock-position, flex-weight
    check("attr count on g1",
          setup + tstr('g1') + [
              'TA UIDL-BY-ID _CNT-ATTRS . CR'],
          '2')

def test_media_reps():
    """Media element with representation sets."""
    print("\n── Representation Sets ──\n")

    setup = tstr(DOC_MEDIA) + ['TA UIDL-PARSE DROP']

    check("media type",
          setup + tstr('status') + [
              'TA UIDL-BY-ID UIDL-TYPE . CR'],
          '6')  # UIDL-T-MEDIA

    check("rep count",
          setup + tstr('status') + [
              'TA UIDL-BY-ID UIDL-REP-COUNT . CR'],
          '4')

    check("rep visual found",
          setup + tstr('status') + [
              'TA UIDL-BY-ID S" visual" UIDL-REP-BY-MOD 0<> . CR'],
          '-1')

    check("rep auditory found",
          setup + tstr('status') + [
              'TA UIDL-BY-ID S" auditory" UIDL-REP-BY-MOD 0<> . CR'],
          '-1')

    check("rep tactile found",
          setup + tstr('status') + [
              'TA UIDL-BY-ID S" tactile" UIDL-REP-BY-MOD 0<> . CR'],
          '-1')

    check("rep description found",
          setup + tstr('status') + [
              'TA UIDL-BY-ID S" description" UIDL-REP-BY-MOD 0<> . CR'],
          '-1')

    check("rep nonexistent → 0",
          setup + tstr('status') + [
              'TA UIDL-BY-ID S" braille" UIDL-REP-BY-MOD . CR'],
          '0')

    # Rep attributes
    check("visual rep src attr",
          setup + tstr('status') + [
              'TA UIDL-BY-ID S" visual" UIDL-REP-BY-MOD',
              'S" src" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'diagram.svg')

    check("auditory rep text attr",
          setup + tstr('status') + [
              'TA UIDL-BY-ID S" auditory" UIDL-REP-BY-MOD',
              'S" text" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'All systems nominal')

def test_collection():
    """Collection element with template and empty children."""
    print("\n── Collections ──\n")

    setup = tstr(DOC_COLLECTION) + ['TA UIDL-PARSE DROP']

    check("collection type",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-TYPE . CR'],
          '14')

    check("collection arrange",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-ARRANGE . CR'],
          '4')  # UIDL-A-FLOW

    check("template found",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-TEMPLATE 0<> . CR'],
          '-1')

    check("template type",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-TEMPLATE UIDL-TYPE . CR'],
          '18')  # UIDL-T-TEMPLATE

    check("empty-child found",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-EMPTY-CHILD 0<> . CR'],
          '-1')

    check("empty-child type",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-EMPTY-CHILD UIDL-TYPE . CR'],
          '19')  # UIDL-T-EMPTY

    # Template has children (group with label)
    check("template has children",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-TEMPLATE UIDL-NCHILDREN . CR'],
          '1')

    # Empty has children (label)
    check("empty has children",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-EMPTY-CHILD UIDL-NCHILDREN . CR'],
          '1')

def test_meta_element():
    """Meta element with key/value attributes."""
    print("\n── Meta Element ──\n")

    setup = tstr(DOC_ALL_TYPES) + ['TA UIDL-PARSE DROP']

    check("meta key attr",
          setup + tstr('e4') + [
              'TA UIDL-BY-ID',
              'S" key" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'title')

    check("meta value attr",
          setup + tstr('e4') + [
              'TA UIDL-BY-ID',
              'S" value" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'test')

def test_binding_eval():
    """Evaluate bind expressions via LEL + state tree."""
    print("\n── Binding Evaluation ──\n")

    # Set up state tree, then parse UIDL and evaluate
    setup = [
        '512 4096 ST-CREATE',
        'ST-USE',
        'S" user.name" S" Kirk" ST-SET-STRING DROP',
    ] + tstr(DOC_BIND) + ['TA UIDL-PARSE DROP']

    check("bind eval string",
          setup + tstr('lbl1') + [
              'TA UIDL-BY-ID UIDL-BIND-EVAL',
              'ROT . CR'],  # type = 1 (ST-T-STRING)
          '1')

    check("bind eval null for unbound",
          setup + tstr('lbl2') + [
              'TA UIDL-BY-ID UIDL-BIND-EVAL',
              'ROT . CR'],  # type = 4 (ST-T-NULL)
          '4')

def test_when_eval():
    """Evaluate when conditions via LEL + state tree."""
    print("\n── When Evaluation ──\n")

    setup_base = [
        '512 4096 ST-CREATE',
        'ST-USE',
    ]

    # Pressure > 90 → when should be true
    setup_high = setup_base + [
        'S" sensors.pressure" 95 ST-SET-INTEGER DROP',
    ] + tstr(DOC_WHEN) + ['TA UIDL-PARSE DROP']

    # No when → always visible
    check("eval-when no condition",
          setup_high + tstr('visible') + [
              'TA UIDL-BY-ID UIDL-EVAL-WHEN . CR'],
          '-1')

    # when="=false" → always hidden
    check("eval-when false literal",
          setup_high + tstr('hidden') + [
              'TA UIDL-BY-ID UIDL-EVAL-WHEN . CR'],
          '0')

def test_complete_document():
    """Parse the spec §11 complete example (simplified)."""
    print("\n── Complete Document ──\n")

    doc = (
        '<uidl xmlns="urn:liraq:uidl:1.0">'
        '<meta id="doc-meta" key="title" value="Ship Console" />'
        '<region id="nav" arrange="flex" role="navigation">'
        '  <action id="nav-sys" label="Systems" on-activate="ss" />'
        '  <action id="nav-comms" label="Comms" on-activate="ss" />'
        '</region>'
        '<region id="main" arrange="dock" role="primary">'
        '  <group id="hdr" dock-position="before" role="header">'
        '    <symbol id="status-icon" name="status" set="lcars" />'
        '    <label id="title" />'
        '  </group>'
        '  <group id="cnt" dock-position="fill" arrange="flow">'
        '    <collection id="alerts" arrange="flow">'
        '      <template>'
        '        <group id="alert-{_index}" role="alert" arrange="flex">'
        '          <label id="alert-msg-{_index}" />'
        '          <action id="alert-ack-{_index}" label="Ack" emit="ack" />'
        '        </group>'
        '      </template>'
        '      <empty>'
        '        <label id="no-alerts" text="No active alerts" role="status" />'
        '      </empty>'
        '    </collection>'
        '  </group>'
        '</region>'
        '<region id="status-bar" arrange="flex" role="status">'
        '  <label id="stardate" />'
        '  <indicator id="power" mode="determinate" min="0" max="100" />'
        '  <indicator id="alert-status" mode="state" />'
        '</region>'
        '</uidl>'
    )

    setup = tstr(doc) + ['TA UIDL-PARSE DROP']

    check("complete: parse ok",
          tstr(doc) + ['TA UIDL-PARSE . CR'],
          '-1')

    check("complete: root children",
          setup + ['UIDL-ROOT UIDL-NCHILDREN . CR'],
          '4')  # meta + nav + main + status-bar

    check("complete: nav type",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-TYPE . CR'],
          '1')  # region

    check("complete: nav arrange",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-ARRANGE . CR'],
          '2')  # flex

    check("complete: nav role",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-ROLE TYPE CR'],
          'navigation')

    check("complete: nav children",
          setup + tstr('nav') + [
              'TA UIDL-BY-ID UIDL-NCHILDREN . CR'],
          '2')

    check("complete: header role",
          setup + tstr('hdr') + [
              'TA UIDL-BY-ID UIDL-ROLE TYPE CR'],
          'header')

    check("complete: dock-position",
          setup + tstr('hdr') + [
              'TA UIDL-BY-ID',
              'S" dock-position" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'before')

    check("complete: symbol name attr",
          setup + tstr('status-icon') + [
              'TA UIDL-BY-ID',
              'S" name" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'status')

    check("complete: collection template",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-TEMPLATE 0<> . CR'],
          '-1')

    check("complete: collection empty",
          setup + tstr('alerts') + [
              'TA UIDL-BY-ID UIDL-EMPTY-CHILD 0<> . CR'],
          '-1')

    check("complete: indicator mode",
          setup + tstr('power') + [
              'TA UIDL-BY-ID',
              'S" mode" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          'determinate')

    check("complete: indicator min",
          setup + tstr('power') + [
              'TA UIDL-BY-ID',
              'S" min" UIDL-ATTR IF TYPE ELSE 2DROP THEN CR'],
          '0')

    check("complete: status-bar role",
          setup + tstr('status-bar') + [
              'TA UIDL-BY-ID UIDL-ROLE TYPE CR'],
          'status')

    check("complete: elem count",
          setup + ['UIDL-ELEM-COUNT . CR'],
          check_fn=lambda o: int(o.split('\n')[-1].strip()) >= 20)

# =====================================================================
#  Main
# =====================================================================

if __name__ == '__main__':
    build_snapshot()

    test_parse_basics()
    test_element_types()
    test_type_name()
    test_id_registry()
    test_element_id()
    test_arrangement()
    test_roles()
    test_tree_traversal()
    test_self_closing()
    test_two_way_flag()
    test_bind()
    test_when()
    test_generic_attrs()
    test_attr_iteration()
    test_media_reps()
    test_collection()
    test_meta_element()
    test_binding_eval()
    test_when_eval()
    test_complete_document()

    print(f"\n{'='*60}")
    print(f"  UIDL Document Model: {_pass} passed, {_fail} failed")
    print(f"{'='*60}")
    if _fail:
        sys.exit(1)
