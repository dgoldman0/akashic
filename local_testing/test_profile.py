#!/usr/bin/env python3
"""Test suite for akashic LIRAQ presentation profile parser (profile.f).

Structural tests — verifying YAML-based presentation profile loading,
metadata extraction, cascade resolution, density/high-contrast variants.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

STRING_F   = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
YAML_F     = os.path.join(ROOT_DIR, "akashic", "utils", "yaml.f")
PROFILE_F  = os.path.join(ROOT_DIR, "akashic", "liraq", "profile.f")

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
        ("string.f",  STRING_F),
        ("utf8.f",    UTF8_F),
        ("yaml.f",    YAML_F),
        ("profile.f", PROFILE_F),
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
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
    ]

    all_lines = kdos_lines + ['ENTER-USERLAND'] + all_lib_lines + helpers
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16*(1<<20))
    sys_obj.cpu.mem[:len(bios_code)] = bios_code
    sys_obj.boot()

    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0
    max_steps = 600_000_000
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

def run_forth(lines, max_steps=50_000_000):
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
    clean = output.strip()
    ok = check_fn(clean) if check_fn else (expected in clean if expected else True)
    if ok:
        print(f"  PASS  {name}")
        _pass += 1
    else:
        _fail += 1
        print(f"  FAIL  {name}")
        if expected:
            print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-4:]:
            print(f"        got:      '{l}'")

# ── Reference YAML profiles ──

# Minimal visual profile for most tests
PROFILE_VISUAL = (
    'profile:\n'
    '  name: lcars-dark\n'
    '  version: "1.0"\n'
    '  capabilities: [visual]\n'
    '  description: "LCARS dark theme"\n'
    '\n'
    'defaults:\n'
    '  content:\n'
    '    font-family: "Antonio"\n'
    '    font-size: 18\n'
    '    color: "#FF9900"\n'
    '  container:\n'
    '    background: "#000000"\n'
    '    padding: 12\n'
    '  interactive:\n'
    '    cursor: pointer\n'
    '  separator:\n'
    '    thickness: 2\n'
    '\n'
    'element-types:\n'
    '  label:\n'
    '    font-weight: 400\n'
    '  action:\n'
    '    background: "#CC6699"\n'
    '    font-weight: 700\n'
    '  input:\n'
    '    background: "#1A1A2E"\n'
    '  indicator:\n'
    '    bar-color: "#FF9900"\n'
    '\n'
    'roles:\n'
    '  navigation:\n'
    '    background: "#CC6699"\n'
    '  alert:\n'
    '    color: "#FF3333"\n'
    '    font-weight: 700\n'
    '  header:\n'
    '    font-size: 24\n'
    '\n'
    'states:\n'
    '  attended:\n'
    '    outline: "2px solid #FFFFFF"\n'
    '  active:\n'
    '    background: "#FF9900"\n'
    '    color: "#000000"\n'
    '  disabled:\n'
    '    opacity: 0.4\n'
    '\n'
    'importance:\n'
    '  high:\n'
    '    font-weight: 700\n'
    '  low:\n'
    '    opacity: 0.7\n'
    '\n'
    'density:\n'
    '  compact:\n'
    '    font-size: 14\n'
    '  spacious:\n'
    '    font-size: 22\n'
    '\n'
    'high-contrast:\n'
    '  foreground: "#FFFFFF"\n'
    '  background: "#000000"\n'
    '  link: "#FFFF00"\n'
)

# Auditory profile (single-capability)
PROFILE_AUDITORY = (
    'profile:\n'
    '  name: standard-auditory\n'
    '  version: "1.0"\n'
    '  capabilities: [auditory]\n'
    '\n'
    'defaults:\n'
    '  content:\n'
    '    voice: neutral\n'
    '    rate: 1.0\n'
    '  container:\n'
    '    pause-before: 200\n'
    '\n'
    'element-types:\n'
    '  action:\n'
    '    voice: assertive\n'
    '\n'
    'roles:\n'
    '  alert:\n'
    '    voice: urgent\n'
    '\n'
    'states:\n'
    '  attended:\n'
    '    earcon: focus-tone\n'
)

# Multi-capability profile
PROFILE_MULTI = (
    'profile:\n'
    '  name: kiosk\n'
    '  version: "1.0"\n'
    '  capabilities: [visual, tactile]\n'
)

# Minimal invalid profile
PROFILE_INVALID = 'nothing:\n  here: true\n'

# =====================================================================
#  Tests
# =====================================================================

def test_metadata():
    """Profile metadata: name, version, description, validation."""
    print("\n── Metadata Tests ──\n")

    check("PP-NAME basic",
          tstr(PROFILE_VISUAL) +
          [': _T TA PP-NAME TYPE ; _T'],
          "lcars-dark")

    check("PP-VERSION basic",
          tstr(PROFILE_VISUAL) +
          [': _T TA PP-VERSION TYPE ; _T'],
          "1.0")

    check("PP-DESC? present",
          tstr(PROFILE_VISUAL) +
          [': _T TA PP-DESC? IF TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "LCARS dark theme")

    check("PP-DESC? absent",
          tstr(PROFILE_MULTI) +
          [': _T TA PP-DESC? IF TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "NONE")

    check("PP-VALID? good profile",
          tstr(PROFILE_VISUAL) +
          [': _T TA PP-VALID? . ; _T'],
          "-1")

    check("PP-VALID? bad profile",
          tstr(PROFILE_INVALID) +
          [': _T TA PP-VALID? . ; _T'],
          "0")

    check("PP-CAPS-COUNT visual",
          tstr(PROFILE_VISUAL) +
          [': _T TA PP-CAPS-COUNT . ; _T'],
          "1")

    check("PP-CAPS-COUNT multi",
          tstr(PROFILE_MULTI) +
          [': _T TA PP-CAPS-COUNT . ; _T'],
          "2")

    check("PP-HAS-CAP? visual yes",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" visual" PP-HAS-CAP? . ; _T'],
          "-1")

    check("PP-HAS-CAP? auditory no",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" auditory" PP-HAS-CAP? . ; _T'],
          "0")

    check("PP-HAS-CAP? multi - visual",
          tstr(PROFILE_MULTI) +
          [': _T TA S" visual" PP-HAS-CAP? . ; _T'],
          "-1")

    check("PP-HAS-CAP? multi - tactile",
          tstr(PROFILE_MULTI) +
          [': _T TA S" tactile" PP-HAS-CAP? . ; _T'],
          "-1")

    check("PP-HAS-CAP? multi - auditory",
          tstr(PROFILE_MULTI) +
          [': _T TA S" auditory" PP-HAS-CAP? . ; _T'],
          "0")

    check("PP-NAME auditory",
          tstr(PROFILE_AUDITORY) +
          [': _T TA PP-NAME TYPE ; _T'],
          "standard-auditory")

def test_elem_cat():
    """Element category classification."""
    print("\n── Element Category Tests ──\n")

    for etype, expected_cat in [
        ("label",      "content"),
        ("indicator",  "content"),
        ("media",      "content"),
        ("canvas",     "content"),
        ("symbol",     "content"),
        ("meta",       "content"),
        ("region",     "container"),
        ("group",      "container"),
        ("collection", "container"),
        ("table",      "container"),
        ("action",     "interactive"),
        ("input",      "interactive"),
        ("selector",   "interactive"),
        ("toggle",     "interactive"),
        ("range",      "interactive"),
        ("separator",  "separator"),
    ]:
        check(f"PP-ELEM-CAT {etype}",
              [f': _T S" {etype}" PP-ELEM-CAT TYPE ; _T'],
              expected_cat)

def test_defaults():
    """Direct default layer access."""
    print("\n── Default Layer Tests ──\n")

    check("PP-DEFAULT content.color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" content" S" color" PP-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    check("PP-DEFAULT content.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" content" S" font-size" PP-DEFAULT',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "18")

    check("PP-DEFAULT container.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" container" S" background" PP-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    check("PP-DEFAULT container.padding",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" container" S" padding" PP-DEFAULT',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "12")

    check("PP-DEFAULT interactive.cursor",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" interactive" S" cursor" PP-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "pointer")

    check("PP-DEFAULT separator.thickness",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" separator" S" thickness" PP-DEFAULT',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "2")

    check("PP-DEFAULT missing category",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" nonexist" S" color" PP-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

    check("PP-DEFAULT missing prop",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" content" S" bogus" PP-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_etype():
    """Element-type layer access."""
    print("\n── Element-Type Layer Tests ──\n")

    check("PP-ETYPE label.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" label" S" font-weight" PP-ETYPE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "400")

    check("PP-ETYPE action.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" action" S" background" PP-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")

    check("PP-ETYPE action.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" action" S" font-weight" PP-ETYPE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")

    check("PP-ETYPE input.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" input" S" background" PP-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#1A1A2E")

    check("PP-ETYPE indicator.bar-color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" indicator" S" bar-color" PP-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    check("PP-ETYPE missing type",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" toggle" S" color" PP-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_roles():
    """Role layer access."""
    print("\n── Role Layer Tests ──\n")

    check("PP-ROLE navigation.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" navigation" S" background" PP-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")

    check("PP-ROLE alert.color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" alert" S" color" PP-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF3333")

    check("PP-ROLE alert.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" alert" S" font-weight" PP-ROLE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")

    check("PP-ROLE header.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" header" S" font-size" PP-ROLE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "24")

    check("PP-ROLE missing role",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" toolbar" S" color" PP-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_states():
    """State layer access."""
    print("\n── State Layer Tests ──\n")

    check("PP-STATE attended.outline",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" attended" S" outline" PP-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "2px solid #FFFFFF")

    check("PP-STATE active.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" active" S" background" PP-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    check("PP-STATE active.color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" active" S" color" PP-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    check("PP-STATE missing state",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" loading" S" opacity" PP-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_importance():
    """Importance layer access."""
    print("\n── Importance Layer Tests ──\n")

    check("PP-IMPORTANCE high.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" high" S" font-weight" PP-IMPORTANCE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")

    check("PP-IMPORTANCE low.opacity",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" low" S" opacity" PP-IMPORTANCE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "0.7")

    check("PP-IMPORTANCE missing level",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" critical" S" color" PP-IMPORTANCE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_density():
    """Density variant access."""
    print("\n── Density Tests ──\n")

    check("PP-DENSITY compact.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" compact" S" font-size" PP-DENSITY',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "14")

    check("PP-DENSITY spacious.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" spacious" S" font-size" PP-DENSITY',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "22")

    check("PP-DENSITY missing variant",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" normal" S" font-size" PP-DENSITY',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_high_contrast():
    """High-contrast palette access."""
    print("\n── High-Contrast Tests ──\n")

    check("PP-HIGH-CONTRAST foreground",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" foreground" PP-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FFFFFF")

    check("PP-HIGH-CONTRAST background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" background" PP-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    check("PP-HIGH-CONTRAST link",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" link" PP-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FFFF00")

    check("PP-HIGH-CONTRAST missing key",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" active" PP-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_cascade():
    """Cascade resolution via PP-SET-TYPE / PP-SET-ROLE / PP-SET-STATE / PP-SET-IMP / PP-GET."""
    print("\n── Cascade Resolution Tests ──\n")

    # Cascade: label with no role/state/imp → defaults.content.color
    check("PP-GET defaults only (label color)",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" label" PP-SET-TYPE',
           ': _T TA S" color" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    # Cascade: label with no extra → gets element-type font-weight=400
    check("PP-GET element-type overrides default (label font-weight)",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" label" PP-SET-TYPE',
           ': _T TA S" font-weight" PP-GET',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "400")

    # Cascade: action → element-type background="#CC6699"
    check("PP-GET action background from element-type",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" action" PP-SET-TYPE',
           ': _T TA S" background" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")

    # Cascade: action + role=navigation → role overrides background
    check("PP-GET role overrides element-type",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" action" PP-SET-TYPE S" navigation" PP-SET-ROLE',
           ': _T TA S" background" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")  # same in this case, nav bg = #CC6699

    # Cascade: label + role=alert → role color overrides default
    check("PP-GET alert role overrides default color",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" label" PP-SET-TYPE S" alert" PP-SET-ROLE',
           ': _T TA S" color" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF3333")

    # Cascade: label + state=active → state overrides color
    check("PP-GET state overrides default color",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" label" PP-SET-TYPE S" active" PP-SET-STATE',
           ': _T TA S" color" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    # Cascade: label + role=alert + state=active → state wins over role
    check("PP-GET state overrides role for color",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" label" PP-SET-TYPE',
           'S" alert" PP-SET-ROLE S" active" PP-SET-STATE',
           ': _T TA S" color" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    # Cascade: action + imp=high → importance overrides font-weight
    check("PP-GET importance overrides element-type",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" action" PP-SET-TYPE S" high" PP-SET-IMP',
           ': _T TA S" font-weight" PP-GET',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")  # both action and high have 700

    # Cascade: label + imp=low → importance opacity should be found
    check("PP-GET importance low opacity",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" label" PP-SET-TYPE S" low" PP-SET-IMP',
           ': _T TA S" opacity" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "0.7")

    # Cascade: region → container defaults
    check("PP-GET region gets container defaults",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" region" PP-SET-TYPE',
           ': _T TA S" background" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    # Cascade: region → container padding
    check("PP-GET region gets container padding",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" region" PP-SET-TYPE',
           ': _T TA S" padding" PP-GET',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "12")

    # Cascade: missing property through all layers
    check("PP-GET not found through cascade",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX S" label" PP-SET-TYPE',
           ': _T TA S" animation" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

    # Cascade: context clear works
    check("PP-GET after clear context (no type = no defaults)",
          tstr(PROFILE_VISUAL) +
          ['PP-CLEAR-CTX',
           ': _T TA S" color" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_auditory():
    """Test with auditory profile."""
    print("\n── Auditory Profile Tests ──\n")

    check("Auditory PP-DEFAULT content.voice",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" content" S" voice" PP-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "neutral")

    check("Auditory PP-ETYPE action.voice",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" action" S" voice" PP-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "assertive")

    check("Auditory PP-ROLE alert.voice",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" alert" S" voice" PP-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "urgent")

    check("Auditory PP-STATE attended.earcon",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" attended" S" earcon" PP-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "focus-tone")

    check("Auditory cascade: action + alert role",
          tstr(PROFILE_AUDITORY) +
          ['PP-CLEAR-CTX S" action" PP-SET-TYPE S" alert" PP-SET-ROLE',
           ': _T TA S" voice" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "urgent")  # role overrides etype

    check("Auditory cascade: action (etype voice)",
          tstr(PROFILE_AUDITORY) +
          ['PP-CLEAR-CTX S" action" PP-SET-TYPE',
           ': _T TA S" voice" PP-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "assertive")

# ── Main entry point ──

if __name__ == '__main__':
    build_snapshot()

    test_metadata()
    test_elem_cat()
    test_defaults()
    test_etype()
    test_roles()
    test_states()
    test_importance()
    test_density()
    test_high_contrast()
    test_cascade()
    test_auditory()

    print(f"\n{'='*60}")
    print(f"  Profile Parser:  {_pass} passed, {_fail} failed")
    print(f"{'='*60}")
    sys.exit(1 if _fail else 0)
