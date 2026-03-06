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

    check("PROF-NAME basic",
          tstr(PROFILE_VISUAL) +
          [': _T TA PROF-NAME TYPE ; _T'],
          "lcars-dark")

    check("PROF-VERSION basic",
          tstr(PROFILE_VISUAL) +
          [': _T TA PROF-VERSION TYPE ; _T'],
          "1.0")

    check("PROF-DESC? present",
          tstr(PROFILE_VISUAL) +
          [': _T TA PROF-DESC? IF TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "LCARS dark theme")

    check("PROF-DESC? absent",
          tstr(PROFILE_MULTI) +
          [': _T TA PROF-DESC? IF TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "NONE")

    check("PROF-VALID? good profile",
          tstr(PROFILE_VISUAL) +
          [': _T TA PROF-VALID? . ; _T'],
          "-1")

    check("PROF-VALID? bad profile",
          tstr(PROFILE_INVALID) +
          [': _T TA PROF-VALID? . ; _T'],
          "0")

    check("PROF-CAPS-COUNT visual",
          tstr(PROFILE_VISUAL) +
          [': _T TA PROF-CAPS-COUNT . ; _T'],
          "1")

    check("PROF-CAPS-COUNT multi",
          tstr(PROFILE_MULTI) +
          [': _T TA PROF-CAPS-COUNT . ; _T'],
          "2")

    check("PROF-HAS-CAP? visual yes",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" visual" PROF-HAS-CAP? . ; _T'],
          "-1")

    check("PROF-HAS-CAP? auditory no",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" auditory" PROF-HAS-CAP? . ; _T'],
          "0")

    check("PROF-HAS-CAP? multi - visual",
          tstr(PROFILE_MULTI) +
          [': _T TA S" visual" PROF-HAS-CAP? . ; _T'],
          "-1")

    check("PROF-HAS-CAP? multi - tactile",
          tstr(PROFILE_MULTI) +
          [': _T TA S" tactile" PROF-HAS-CAP? . ; _T'],
          "-1")

    check("PROF-HAS-CAP? multi - auditory",
          tstr(PROFILE_MULTI) +
          [': _T TA S" auditory" PROF-HAS-CAP? . ; _T'],
          "0")

    check("PROF-NAME auditory",
          tstr(PROFILE_AUDITORY) +
          [': _T TA PROF-NAME TYPE ; _T'],
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
        check(f"PROF-ELEM-CAT {etype}",
              [f': _T S" {etype}" PROF-ELEM-CAT TYPE ; _T'],
              expected_cat)

def test_defaults():
    """Direct default layer access."""
    print("\n── Default Layer Tests ──\n")

    check("PROF-DEFAULT content.color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" content" S" color" PROF-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    check("PROF-DEFAULT content.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" content" S" font-size" PROF-DEFAULT',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "18")

    check("PROF-DEFAULT container.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" container" S" background" PROF-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    check("PROF-DEFAULT container.padding",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" container" S" padding" PROF-DEFAULT',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "12")

    check("PROF-DEFAULT interactive.cursor",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" interactive" S" cursor" PROF-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "pointer")

    check("PROF-DEFAULT separator.thickness",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" separator" S" thickness" PROF-DEFAULT',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "2")

    check("PROF-DEFAULT missing category",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" nonexist" S" color" PROF-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

    check("PROF-DEFAULT missing prop",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" content" S" bogus" PROF-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_etype():
    """Element-type layer access."""
    print("\n── Element-Type Layer Tests ──\n")

    check("PROF-ETYPE label.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" label" S" font-weight" PROF-ETYPE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "400")

    check("PROF-ETYPE action.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" action" S" background" PROF-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")

    check("PROF-ETYPE action.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" action" S" font-weight" PROF-ETYPE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")

    check("PROF-ETYPE input.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" input" S" background" PROF-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#1A1A2E")

    check("PROF-ETYPE indicator.bar-color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" indicator" S" bar-color" PROF-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    check("PROF-ETYPE missing type",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" toggle" S" color" PROF-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_roles():
    """Role layer access."""
    print("\n── Role Layer Tests ──\n")

    check("PROF-ROLE navigation.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" navigation" S" background" PROF-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")

    check("PROF-ROLE alert.color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" alert" S" color" PROF-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF3333")

    check("PROF-ROLE alert.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" alert" S" font-weight" PROF-ROLE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")

    check("PROF-ROLE header.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" header" S" font-size" PROF-ROLE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "24")

    check("PROF-ROLE missing role",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" toolbar" S" color" PROF-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_states():
    """State layer access."""
    print("\n── State Layer Tests ──\n")

    check("PROF-STATE attended.outline",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" attended" S" outline" PROF-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "2px solid #FFFFFF")

    check("PROF-STATE active.background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" active" S" background" PROF-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    check("PROF-STATE active.color",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" active" S" color" PROF-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    check("PROF-STATE missing state",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" loading" S" opacity" PROF-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_importance():
    """Importance layer access."""
    print("\n── Importance Layer Tests ──\n")

    check("PROF-IMPORTANCE high.font-weight",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" high" S" font-weight" PROF-IMPORTANCE',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")

    check("PROF-IMPORTANCE low.opacity",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" low" S" opacity" PROF-IMPORTANCE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "0.7")

    check("PROF-IMPORTANCE missing level",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" critical" S" color" PROF-IMPORTANCE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_density():
    """Density variant access."""
    print("\n── Density Tests ──\n")

    check("PROF-DENSITY compact.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" compact" S" font-size" PROF-DENSITY',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "14")

    check("PROF-DENSITY spacious.font-size",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" spacious" S" font-size" PROF-DENSITY',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "22")

    check("PROF-DENSITY missing variant",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" normal" S" font-size" PROF-DENSITY',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_high_contrast():
    """High-contrast palette access."""
    print("\n── High-Contrast Tests ──\n")

    check("PROF-HIGH-CONTRAST foreground",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" foreground" PROF-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FFFFFF")

    check("PROF-HIGH-CONTRAST background",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" background" PROF-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    check("PROF-HIGH-CONTRAST link",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" link" PROF-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FFFF00")

    check("PROF-HIGH-CONTRAST missing key",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" active" PROF-HIGH-CONTRAST',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_cascade():
    """Cascade resolution via PROF-SET-TYPE / PROF-SET-ROLE / PROF-SET-STATE / PROF-SET-IMP / PROF-GET."""
    print("\n── Cascade Resolution Tests ──\n")

    # Cascade: label with no role/state/imp → defaults.content.color
    check("PROF-GET defaults only (label color)",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           ': _T TA S" color" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF9900")

    # Cascade: label with no extra → gets element-type font-weight=400
    check("PROF-GET element-type overrides default (label font-weight)",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           ': _T TA S" font-weight" PROF-GET',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "400")

    # Cascade: action → element-type background="#CC6699"
    check("PROF-GET action background from element-type",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE',
           ': _T TA S" background" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")

    # Cascade: action + role=navigation → role overrides background
    check("PROF-GET role overrides element-type",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE S" navigation" PROF-SET-ROLE',
           ': _T TA S" background" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#CC6699")  # same in this case, nav bg = #CC6699

    # Cascade: label + role=alert → role color overrides default
    check("PROF-GET alert role overrides default color",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE S" alert" PROF-SET-ROLE',
           ': _T TA S" color" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#FF3333")

    # Cascade: label + state=active → state overrides color
    check("PROF-GET state overrides default color",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE S" active" PROF-SET-STATE',
           ': _T TA S" color" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    # Cascade: label + role=alert + state=active → state wins over role
    check("PROF-GET state overrides role for color",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           'S" alert" PROF-SET-ROLE S" active" PROF-SET-STATE',
           ': _T TA S" color" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    # Cascade: action + imp=high → importance overrides font-weight
    check("PROF-GET importance overrides element-type",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE S" high" PROF-SET-IMP',
           ': _T TA S" font-weight" PROF-GET',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "700")  # both action and high have 700

    # Cascade: label + imp=low → importance opacity should be found
    check("PROF-GET importance low opacity",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE S" low" PROF-SET-IMP',
           ': _T TA S" opacity" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "0.7")

    # Cascade: region → container defaults
    check("PROF-GET region gets container defaults",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" region" PROF-SET-TYPE',
           ': _T TA S" background" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

    # Cascade: region → container padding
    check("PROF-GET region gets container padding",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" region" PROF-SET-TYPE',
           ': _T TA S" padding" PROF-GET',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "12")

    # Cascade: missing property through all layers
    check("PROF-GET not found through cascade",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           ': _T TA S" animation" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

    # Cascade: context clear works
    check("PROF-GET after clear context (no type = no defaults)",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX',
           ': _T TA S" color" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

def test_auditory():
    """Test with auditory profile."""
    print("\n── Auditory Profile Tests ──\n")

    check("Auditory PROF-DEFAULT content.voice",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" content" S" voice" PROF-DEFAULT',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "neutral")

    check("Auditory PROF-ETYPE action.voice",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" action" S" voice" PROF-ETYPE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "assertive")

    check("Auditory PROF-ROLE alert.voice",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" alert" S" voice" PROF-ROLE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "urgent")

    check("Auditory PROF-STATE attended.earcon",
          tstr(PROFILE_AUDITORY) +
          [': _T TA S" attended" S" earcon" PROF-STATE',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "focus-tone")

    check("Auditory cascade: action + alert role",
          tstr(PROFILE_AUDITORY) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE S" alert" PROF-SET-ROLE',
           ': _T TA S" voice" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "urgent")  # role overrides etype

    check("Auditory cascade: action (etype voice)",
          tstr(PROFILE_AUDITORY) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE',
           ': _T TA S" voice" PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "assertive")

# ── Gap 4.6: Property namespace constants ──

def test_property_constants():
    """Auditory and tactile property namespace constants."""
    print("\n── Property Namespace Constants ──\n")

    # Auditory constant via cascade lookup
    check("Auditory constant PROF-VOICE",
          tstr(PROFILE_AUDITORY) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE',
           ': _T TA PROF-VOICE PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "assertive")

    # Tactile constant lookup (we need a tactile profile)
    check("Tactile constant PROF-HAPTIC",
          tstr(PROFILE_TACTILE) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE',
           ': _T TA PROF-HAPTIC PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "pulse")

    # Cascade with auditory constant
    check("Cascade with PROF-EARCON",
          tstr(PROFILE_AUDITORY) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE S" attended" PROF-SET-STATE',
           ': _T TA PROF-EARCON PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "focus-tone")  # state overrides

    # Unknown property via constant
    check("Unknown property via PROF-PIN-FLASH",
          tstr(PROFILE_AUDITORY) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           ': _T TA PROF-PIN-FLASH PROF-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")

# ── Gap 4.1: Multi-capability profile ──

PROFILE_MULTICAP = (
    'profile:\n'
    '  name: multi-sense\n'
    '  version: "1.0"\n'
    '  capabilities: [visual, auditory]\n'
    '\n'
    'defaults:\n'
    '  visual:\n'
    '    color: "#00FF00"\n'
    '    font-size: 20\n'
    '  auditory:\n'
    '    voice: calm\n'
    '  font-family: "Helvetica"\n'
)

PROFILE_TACTILE = (
    'profile:\n'
    '  name: braille-basic\n'
    '  version: "1.0"\n'
    '  capabilities: [tactile]\n'
    '\n'
    'defaults:\n'
    '  content:\n'
    '    cell-routing: direct\n'
    '\n'
    'element-types:\n'
    '  action:\n'
    '    haptic: pulse\n'
)

def test_multicap():
    """Multi-capability profile scoped lookups."""
    print("\n── Multi-Cap Profile Tests ──\n")

    check("Multi-cap: read visual property",
          tstr(PROFILE_MULTICAP) +
          [': _T TA S" visual" S" color" PROF-CAP-SECTION',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#00FF00")

    check("Multi-cap: read auditory property",
          tstr(PROFILE_MULTICAP) +
          [': _T TA S" auditory" S" voice" PROF-CAP-SECTION',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "calm")

    check("Multi-cap: fallback to unscoped",
          tstr(PROFILE_MULTICAP) +
          [': _T TA S" visual" S" font-family" PROF-CAP-SECTION',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "Helvetica")

    check("Single-cap: no cap section graceful",
          tstr(PROFILE_VISUAL) +
          [': _T TA S" visual" S" color" PROF-CAP-SECTION',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "MISS")  # PROFILE_VISUAL has no cap subsections under defaults

    check("Missing cap section -> fallback",
          tstr(PROFILE_MULTICAP) +
          [': _T TA S" tactile" S" font-family" PROF-CAP-SECTION',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "Helvetica")  # tactile section doesn't exist, falls back to defaults.font-family

# ── Gap 4.4: Profile stacking ──

PROFILE_STACK_A = (
    'defaults:\n'
    '  content:\n'
    '    color: "#111111"\n'
    '    font-size: 16\n'
)

PROFILE_STACK_B = (
    'defaults:\n'
    '  content:\n'
    '    color: "#222222"\n'
    '    background: "#000000"\n'
)

def test_stacking():
    """Profile stacking — B overrides A."""
    print("\n── Profile Stacking Tests ──\n")

    # Disjoint: font-size only in A
    check("Stack: disjoint property from A",
          ['CREATE _BA 2048 ALLOT  CREATE _BB 2048 ALLOT',
           'VARIABLE _LA  VARIABLE _LB'] +
          tstr(PROFILE_STACK_A) +
          ['TA DUP _LA ! _BA SWAP MOVE'] +
          tstr(PROFILE_STACK_B) +
          ['TA DUP _LB ! _BB SWAP MOVE',
           'PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           '_BA _LA @ _BB _LB @ PROF-STACK',
           ': _T S" font-size" PROF-STACK-GET',
           'IF YAML-GET-INT . ELSE 2DROP ." MISS" THEN ; _T'],
          "16")

    # Overlapping: color in both, B wins
    check("Stack: overlapping property B wins",
          ['CREATE _BA2 2048 ALLOT  CREATE _BB2 2048 ALLOT',
           'VARIABLE _LA2  VARIABLE _LB2'] +
          tstr(PROFILE_STACK_A) +
          ['TA DUP _LA2 ! _BA2 SWAP MOVE'] +
          tstr(PROFILE_STACK_B) +
          ['TA DUP _LB2 ! _BB2 SWAP MOVE',
           'PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           '_BA2 _LA2 @ _BB2 _LB2 @ PROF-STACK',
           ': _T S" color" PROF-STACK-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#222222")

    # B has background, A doesn't
    check("Stack: unique property from B",
          ['CREATE _BA3 2048 ALLOT  CREATE _BB3 2048 ALLOT',
           'VARIABLE _LA3  VARIABLE _LB3'] +
          tstr(PROFILE_STACK_A) +
          ['TA DUP _LA3 ! _BA3 SWAP MOVE'] +
          tstr(PROFILE_STACK_B) +
          ['TA DUP _LB3 ! _BB3 SWAP MOVE',
           'PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           '_BA3 _LA3 @ _BB3 _LB3 @ PROF-STACK',
           ': _T S" background" PROF-STACK-GET',
           'IF YAML-GET-STRING TYPE ELSE 2DROP ." MISS" THEN ; _T'],
          "#000000")

# ── Gap 4.5: Inline override ──

PROFILE_ELEM_WITH_INLINE = (
    'present-voice: override-voice\n'
    'present-color: "#FF0000"\n'
    'label: hello\n'
)

def test_inline():
    """Inline present-* overrides."""
    print("\n── Inline Override Tests ──\n")

    check("Inline: one override (voice)",
          tstr(PROFILE_ELEM_WITH_INLINE) +
          ['TA PROF-SET-ELEM',
           ': _T S" voice" S" neutral" PROF-INLINE TYPE ; _T'],
          "override-voice")

    check("Inline: override color",
          tstr(PROFILE_ELEM_WITH_INLINE) +
          ['TA PROF-SET-ELEM',
           ': _T S" color" S" #FFFFFF" PROF-INLINE TYPE ; _T'],
          "#FF0000")

    check("Inline: no matching present-* keeps original",
          tstr(PROFILE_ELEM_WITH_INLINE) +
          ['TA PROF-SET-ELEM',
           ': _T S" font-size" S" 18" PROF-INLINE TYPE ; _T'],
          "18")

# ── Gap 4.3: Accommodation ──

ACCOM_LARGE_TEXT = (
    'large-text: true\n'
)

ACCOM_REDUCED = (
    'reduced-motion: true\n'
)

ACCOM_NONE = (
    'nothing: here\n'
)

def test_accommodation():
    """Accommodation integration."""
    print("\n── Accommodation Tests ──\n")

    check("Accom: large-text font-size scaled",
          tstr(ACCOM_LARGE_TEXT) +
          ['TA PROF-ACCOMMODATE',
           ': _T 18 S" font-size" PROF-ACCOM-INT . ; _T'],
          "27")  # 18 * 3 / 2 = 27

    # High-contrast flag — parse YAML directly
    check("Accom: high-contrast flag set",
          ['PROF-ACCOM-CLEAR'] +
          tstr('high-contrast: true\n') +
          ['TA PROF-ACCOMMODATE',
           ': _T PROF-ACCOM-HC? . ; _T'],
          "-1")

    check("Accom: reduced-motion animation 0",
          tstr(ACCOM_REDUCED) +
          ['TA PROF-ACCOMMODATE',
           ': _T 300 S" animation-duration" PROF-ACCOM-INT . ; _T'],
          "0")

    check("Accom: no accommodations unchanged",
          tstr(ACCOM_NONE) +
          ['TA PROF-ACCOMMODATE',
           ': _T 18 S" font-size" PROF-ACCOM-INT . ; _T'],
          "18")

# ── Gap 4.2: Profile resolution ──

def test_resolution():
    """Profile resolution — filter by cap subset, pick most specific."""
    print("\n── Profile Resolution Tests ──\n")

    # Single profile matching
    check("Resolve: single matching profile",
          tstr(PROFILE_VISUAL) +
          ['VARIABLE _PA1 VARIABLE _PL1',
           'TA _PL1 ! _PA1 !',
           'CREATE _ADDRS _PA1 @ ,',
           'CREATE _LENS  _PL1 @ ,',
           ': _T 1 _ADDRS _LENS 1 PROF-RESOLVE',
           'IF PROF-NAME TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "lcars-dark")

    # No matching profile
    check("Resolve: no match returns empty",
          tstr(PROFILE_VISUAL) +
          ['VARIABLE _PNA VARIABLE _PNL',
           'TA _PNL ! _PNA !',
           'CREATE _AN _PNA @ ,',
           'CREATE _LN _PNL @ ,',
           ': _T 2 _AN _LN 1 PROF-RESOLVE',
           'IF PROF-NAME TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "NONE")

    # Capability subset filtering
    check("Resolve: cap subset filtering",
          tstr(PROFILE_MULTICAP) +
          ['VARIABLE _PSA VARIABLE _PSL',
           'TA _PSL ! _PSA !',
           'CREATE _AS _PSA @ ,',
           'CREATE _LS _PSL @ ,',
           ': _T 3 _AS _LS 1 PROF-RESOLVE',
           'IF PROF-NAME TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "multi-sense")

    # Two profiles with separate buffers — more specific wins
    check("Resolve: more specific wins",
          ['CREATE _RB1 2048 ALLOT  CREATE _RB2 2048 ALLOT',
           'VARIABLE _RL1  VARIABLE _RL2'] +
          tstr(PROFILE_VISUAL) +
          ['TA DUP _RL1 ! _RB1 SWAP MOVE'] +
          tstr(PROFILE_MULTICAP) +
          ['TA DUP _RL2 ! _RB2 SWAP MOVE',
           'CREATE _RA2 _RB1 , _RB2 ,',
           'CREATE _RLL2 _RL1 @ , _RL2 @ ,',
           ': _T 1 _RA2 _RLL2 2 PROF-RESOLVE',
           'IF PROF-NAME TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "lcars-dark")

    # Three profiles with separate buffers
    check("Resolve: three profiles best specificity",
          ['CREATE _RB3A 2048 ALLOT  CREATE _RB3B 2048 ALLOT',
           'CREATE _RB3C 2048 ALLOT',
           'VARIABLE _RL3A  VARIABLE _RL3B  VARIABLE _RL3C'] +
          tstr(PROFILE_VISUAL) +
          ['TA DUP _RL3A ! _RB3A SWAP MOVE'] +
          tstr(PROFILE_MULTICAP) +
          ['TA DUP _RL3B ! _RB3B SWAP MOVE'] +
          tstr(PROFILE_AUDITORY) +
          ['TA DUP _RL3C ! _RB3C SWAP MOVE',
           'CREATE _RA3 _RB3A , _RB3B , _RB3C ,',
           'CREATE _RLL3 _RL3A @ , _RL3B @ , _RL3C @ ,',
           ': _T 1 _RA3 _RLL3 3 PROF-RESOLVE',
           'IF PROF-NAME TYPE ELSE 2DROP ." NONE" THEN ; _T'],
          "lcars-dark")

# ── Gap 4.7: Profile → CSL ──

def test_to_csl():
    """Profile to CSL translation."""
    print("\n── Profile → CSL Tests ──\n")

    # Visual profile CSL
    check("CSL: visual profile basic",
          tstr(PROFILE_VISUAL) +
          ['PROF-CLEAR-CTX S" label" PROF-SET-TYPE',
           ': _T TA 0 0 PROF-TO-CSL TYPE ; _T'],
          check_fn=lambda out: "color:" in out and "font-size:" in out)

    # Auditory profile CSL
    check("CSL: auditory profile",
          tstr(PROFILE_AUDITORY) +
          ['PROF-CLEAR-CTX S" action" PROF-SET-TYPE',
           ': _T TA 0 0 PROF-TO-CSL TYPE ; _T'],
          check_fn=lambda out: "voice:" in out)

    # Empty profile — no matching keys
    check("CSL: empty profile",
          tstr(PROFILE_INVALID) +
          ['PROF-CLEAR-CTX',
           ': _T TA 0 0 PROF-TO-CSL DUP . ; _T'],
          "0")  # length is 0


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
    test_property_constants()
    test_multicap()
    test_stacking()
    test_inline()
    test_accommodation()
    test_resolution()
    test_to_csl()

    print(f"\n{'='*60}")
    print(f"  Profile Parser:  {_pass} passed, {_fail} failed")
    print(f"{'='*60}")
    sys.exit(1 if _fail else 0)
