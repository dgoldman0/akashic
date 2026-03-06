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
"""Test suite for akashic-web-template Forth library (web/template.f).

Tests:
  Compile    — all words compile without error
  TPL-PAGE   — full HTML5 page boilerplate
  TPL-LINK   — anchor tag generation
  TPL-LIST   — unordered list with index
  TPL-TABLE-ROW — table row with cells
  TPL-FORM   — form element with action/method
  TPL-INPUT  — input element with type/name
  TPL-VAR!   — variable set + lookup
  TPL-EXPAND — micro-template {{ name }} expansion
  TPL-VAR-CLEAR — variable reset

NOTE: S" only works inside colon definitions in this BIOS.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
CORE_F     = os.path.join(ROOT_DIR, "akashic", "markup", "core.f")
HTML_F     = os.path.join(ROOT_DIR, "akashic", "markup", "html.f")
TPL_F      = os.path.join(ROOT_DIR, "akashic", "web", "template.f")
EVENT_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F      = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F    = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

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
    print("[*] Building snapshot: BIOS + KDOS + string.f + core.f + html.f + template.f ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    str_lines  = _load_forth_lines(STR_F)
    core_lines = _load_forth_lines(CORE_F)
    html_lines = _load_forth_lines(HTML_F)
    tpl_lines  = _load_forth_lines(TPL_F)
    helpers = [
        'CREATE _TB 2048 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        # Output buffer for HTML builder
        'CREATE _OB 4096 ALLOT',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    all_lines = (kdos_lines + ["ENTER-USERLAND"] +
                 event_lines + sem_lines + guard_lines +
                 str_lines + core_lines + html_lines +
                 tpl_lines + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 900_000_000
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
    errs = [l for l in text.strip().split('\n') if '?' in l and 'not found' in l.lower()]
    if errs:
        print("[!] Compilation errors:")
        for ln in errs[-10:]: print(f"    {ln}")
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot

def run_forth(lines, max_steps=50_000_000):
    bios_code, mem_bytes, cpu_state, ext_mem_bytes = _snapshot
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    for _ in range(5_000_000):
        if sys_obj.cpu.idle and not sys_obj.uart.has_rx_data:
            break
        sys_obj.run_batch(10_000)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
    buf.clear()
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


def tstr_compiled(s):
    """Build Forth code to construct string s in _TB via TR/TC.
    Returns list of Forth lines within line length limits."""
    parts = ['TR']
    for ch in s:
        parts.append(f'{ord(ch)} TC')
    full = " ".join(parts)
    lines = []
    while len(full) > 70:
        sp = full.rfind(' ', 0, 70)
        if sp == -1: sp = 70
        lines.append(full[:sp])
        full = full[sp:].lstrip()
    if full: lines.append(full)
    return lines


# ── Test Infrastructure ──

_pass_count = 0
_fail_count = 0

def check(label, lines, expected=None, contains=False, negate=False, check_fn=None):
    global _pass_count, _fail_count
    out = run_forth(lines)
    clean = out.strip()
    if check_fn:
        ok = check_fn(clean)
    elif negate:
        ok = expected not in clean
    elif contains:
        ok = expected in clean
    else:
        ok = expected in clean
    if ok:
        _pass_count += 1
        print(f"  [PASS] {label}")
    else:
        _fail_count += 1
        print(f"  [FAIL] {label}")
        if expected is not None:
            print(f"         expected: {repr(expected)}")
        tail = clean.split('\n')[-3:]
        print(f"         got (last lines): {tail}")


# =====================================================================
#  Tests — Compilation
# =====================================================================

def test_compile():
    print("\n--- Compile ---")
    # Key words exist
    for word in ['TPL-PAGE', 'TPL-LINK', 'TPL-LIST', 'TPL-TABLE-ROW',
                 'TPL-FORM', 'TPL-INPUT', 'TPL-VAR!', 'TPL-EXPAND',
                 'TPL-VAR-CLEAR']:
        check(f"{word} exists",
              [f"' {word} ."],
              check_fn=lambda t: "not found" not in t.lower())


# =====================================================================
#  Tests — Compositional Words (Approach A)
# =====================================================================

def test_tpl_link():
    print("\n--- TPL-LINK ---")
    check("TPL-LINK basic",
          [': _T _OB 4096 HTML-SET-OUTPUT',
           '  S" /login" S" Log In" TPL-LINK',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<a href="/login">Log In</a>')

    check("TPL-LINK with escaping",
          [': _T _OB 4096 HTML-SET-OUTPUT',
           '  S" /a&b" S" X&Y" TPL-LINK',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<a href="/a&b">X&amp;Y</a>')


def test_tpl_input():
    print("\n--- TPL-INPUT ---")
    check("TPL-INPUT text/username",
          [': _T _OB 4096 HTML-SET-OUTPUT',
           '  S" text" S" username" TPL-INPUT',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<input type="text" name="username">')

    check("TPL-INPUT password/pw",
          [': _T _OB 4096 HTML-SET-OUTPUT',
           '  S" password" S" pw" TPL-INPUT',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<input type="password" name="pw">')


def test_tpl_list():
    print("\n--- TPL-LIST ---")
    # 3 items, each emitting index as text
    check("TPL-LIST 3 items",
          [': _emit-idx  ( i -- ) NUM>STR HTML-TEXT! ;',
           ': _T _OB 4096 HTML-SET-OUTPUT',
           "  3 ['] _emit-idx TPL-LIST",
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<ul><li>0</li><li>1</li><li>2</li></ul>')

    check("TPL-LIST 0 items",
          [': _emit-idx2  ( i -- ) NUM>STR HTML-TEXT! ;',
           ': _T _OB 4096 HTML-SET-OUTPUT',
           "  0 ['] _emit-idx2 TPL-LIST",
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<ul></ul>')


def test_tpl_table_row():
    print("\n--- TPL-TABLE-ROW ---")
    check("TPL-TABLE-ROW 2 cols",
          [': _emit-col  ( i -- ) NUM>STR HTML-TEXT! ;',
           ': _T _OB 4096 HTML-SET-OUTPUT',
           "  2 ['] _emit-col TPL-TABLE-ROW",
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<tr><td>0</td><td>1</td></tr>')


def test_tpl_form():
    print("\n--- TPL-FORM ---")
    check("TPL-FORM basic",
          [': _form-body S" text" S" user" TPL-INPUT ;',
           ': _T _OB 4096 HTML-SET-OUTPUT',
           "  S\" /submit\" S\" POST\" ['] _form-body TPL-FORM",
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<form action="/submit" method="POST"><input type="text" name="user"></form>')


def test_tpl_page():
    print("\n--- TPL-PAGE ---")
    check("TPL-PAGE basic",
          [': _body S" h1" HTML-<  HTML->  S" Hi" HTML-TEXT!  S" h1" HTML-</ ;',
           ': _T _OB 4096 HTML-SET-OUTPUT',
           "  S\" Test\" ['] _body TPL-PAGE",
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Test</title></head><body><h1>Hi</h1></body></html>')

    check("TPL-PAGE empty body",
          [': _empty ;',
           ': _T _OB 4096 HTML-SET-OUTPUT',
           "  S\" X\" ['] _empty TPL-PAGE",
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<!DOCTYPE html><html><head><meta charset="utf-8"><title>X</title></head><body></body></html>')


# =====================================================================
#  Tests — Micro-Templates (Approach B)
# =====================================================================

def test_tpl_var():
    print("\n--- TPL-VAR! ---")
    check("Set and expand single var",
          [': _T',
           '  S" Alice" S" user" TPL-VAR!',
           ] + tstr_compiled("Hello {{ user }}!") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "Hello Alice!")

    check("Unknown var → empty",
          [': _T',
           '  TPL-VAR-CLEAR',
           ] + tstr_compiled("Hi {{ nobody }}!") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "Hi !")

    check("No placeholders → passthrough",
          [': _T',
           ] + tstr_compiled("plain text") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "plain text")


def test_tpl_expand_multi():
    print("\n--- TPL-EXPAND multi ---")
    check("Two vars in one template",
          [': _T',
           '  S" Bob" S" name" TPL-VAR!',
           '  S" 42" S" age" TPL-VAR!',
           ] + tstr_compiled("{{ name }} is {{ age }}") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "Bob is 42")

    check("Same var twice",
          [': _T',
           '  S" X" S" v" TPL-VAR!',
           ] + tstr_compiled("{{ v }}+{{ v }}") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "X+X")


def test_tpl_var_overwrite():
    print("\n--- TPL-VAR! overwrite ---")
    check("Overwrite existing var",
          [': _T',
           '  S" old" S" x" TPL-VAR!',
           '  S" new" S" x" TPL-VAR!',
           ] + tstr_compiled("{{ x }}") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "new")


def test_tpl_var_clear():
    print("\n--- TPL-VAR-CLEAR ---")
    check("Clear removes vars",
          [': _T',
           '  S" val" S" k" TPL-VAR!',
           '  TPL-VAR-CLEAR',
           ] + tstr_compiled("{{ k }}") + [
           '  TA TPL-EXPAND',
           '  46 EMIT TYPE 46 EMIT ; _T'],
          "..",
          check_fn=lambda t: ".." in t)


def test_tpl_expand_edge():
    print("\n--- TPL-EXPAND edge cases ---")
    check("Empty template",
          [': _T',
           ] + tstr_compiled("") + [
           '  TA TPL-EXPAND',
           '  46 EMIT TYPE 46 EMIT ; _T'],
          check_fn=lambda t: ".." in t)

    check("Unclosed {{ passes through",
          [': _T',
           ] + tstr_compiled("start {{ no close") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "start {{ no close")

    check("Adjacent placeholders",
          [': _T',
           '  S" A" S" a" TPL-VAR!',
           '  S" B" S" b" TPL-VAR!',
           ] + tstr_compiled("{{ a }}{{ b }}") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "AB")

    check("No space around name",
          [': _T',
           '  S" OK" S" x" TPL-VAR!',
           ] + tstr_compiled("{{x}}") + [
           '  TA TPL-EXPAND TYPE ; _T'],
          "OK")


def test_tpl_combined():
    print("\n--- Combined: template + HTML builder ---")
    # Use TPL-EXPAND to get a string, then feed to builder as text
    check("Expand into HTML text",
          [': _T',
           '  S" World" S" who" TPL-VAR!',
           '  _OB 4096 HTML-SET-OUTPUT',
           '  S" h1" HTML-<  HTML->',
           ] + tstr_compiled("Hello {{ who }}!") + [
           '  TA TPL-EXPAND HTML-TEXT!',
           '  S" h1" HTML-</',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          "<h1>Hello World!</h1>")


# =====================================================================
#  Main
# =====================================================================

def main():
    build_snapshot()
    test_compile()
    test_tpl_link()
    test_tpl_input()
    test_tpl_list()
    test_tpl_table_row()
    test_tpl_form()
    test_tpl_page()
    test_tpl_var()
    test_tpl_expand_multi()
    test_tpl_var_overwrite()
    test_tpl_var_clear()
    test_tpl_expand_edge()
    test_tpl_combined()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    return 1 if _fail_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
