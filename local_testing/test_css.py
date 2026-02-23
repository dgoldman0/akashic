#!/usr/bin/env python3
"""Test suite for akashic-css Forth library.

Uses the Megapad-64 emulator to boot KDOS, load css.f,
and run Forth test expressions.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "utils", "string", "string.f")
CSS_F      = os.path.join(ROOT_DIR, "utils", "css", "css.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

# ---------------------------------------------------------------------------
#  Emulator helpers (same pattern as test_markup.py)
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
    """Boot BIOS + KDOS + css.f, save snapshot for fast test replay."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + string.f + css.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    css_lines  = _load_forth_lines(CSS_F)

    # Test helper words
    test_helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 256 ALLOT  VARIABLE _UL',
        ': UR  0 _UL ! ;',
        ': UC  ( c -- ) _UB _UL @ + C!  1 _UL +! ;',
        ': UA  ( -- addr u ) _UB _UL @ ;',
        ': .SNS  ( a u type na nu -- )',
        '  2>R 48 + EMIT 124 EMIT 2R> TYPE 2DROP ;',
        ': .TRBL  ( ta tl ra rl ba bl la ll n -- )',
        '  >R 2>R 2>R 2>R TYPE 124 EMIT 2R> TYPE 124 EMIT',
        '  2R> TYPE 124 EMIT 2R> TYPE 124 EMIT R> . ;',
        ': .2S  ( a1 u1 a2 u2 flag -- )',
        '  >R 2>R TYPE 124 EMIT 2R> TYPE 124 EMIT R> . ;',
        ': .1S  ( a u flag -- )',
        '  >R TYPE 124 EMIT R> . ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + str_lines + css_lines + test_helpers
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode()
    pos = 0
    steps = 0
    max_steps = 600_000_000

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
        for ln in err_lines[-10:]:
            print(f"    {ln}")

    _snapshot = (bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=50_000_000):
    """Restore snapshot, feed Forth lines, return UART text output."""
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


def ustr(s):
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


# ---------------------------------------------------------------------------
#  Layer 0 — Scanning Primitives
# ---------------------------------------------------------------------------

def test_layer0():
    print("\n=== Layer 0 — Scanning Primitives ===")

    # -- CSS-SKIP-WS --
    check("skip-ws: spaces",
          mstr("   hello") + ['TA CSS-SKIP-WS .S'],
          check_fn=lambda o: 'hello' in run_forth(
              mstr("   hello") + ['TA CSS-SKIP-WS TYPE']))

    check("skip-ws: spaces+tabs",
          mstr("  \t\n hello") + ['TA CSS-SKIP-WS TYPE'],
          "hello")

    check("skip-ws: no ws",
          mstr("hello") + ['TA CSS-SKIP-WS TYPE'],
          "hello")

    check("skip-ws: empty",
          mstr("") + ['TA CSS-SKIP-WS . '],
          "0 ")

    # -- CSS-SKIP-COMMENT --
    check("skip-comment: basic",
          mstr("/* comment */rest") + ['TA CSS-SKIP-COMMENT TYPE'],
          "rest")

    check("skip-comment: nested stars",
          mstr("/* ** stars ** */after") + ['TA CSS-SKIP-COMMENT TYPE'],
          "after")

    check("skip-comment: not a comment",
          mstr("/not*comment") + ['TA CSS-SKIP-COMMENT TYPE'],
          "/not*comment")

    # -- CSS-SKIP-WS with comments --
    check("skip-ws: comment in whitespace",
          mstr("  /* comment */  rest") + ['TA CSS-SKIP-WS TYPE'],
          "rest")

    check("skip-ws: multiple comments",
          mstr("/* a */ /* b */ rest") + ['TA CSS-SKIP-WS TYPE'],
          "rest")

    check("skip-ws: comment only",
          mstr("/* comment */") + ['TA CSS-SKIP-WS . '],
          "0 ")

    # -- CSS-SKIP-STRING --
    check("skip-string: double quotes",
          mstr('"hello" rest') + ['TA CSS-SKIP-STRING TYPE'],
          " rest")

    check("skip-string: single quotes",
          mstr("'hello' rest") + ['TA CSS-SKIP-STRING TYPE'],
          " rest")

    check("skip-string: escaped quote",
          mstr('"he\\"llo" rest') + ['TA CSS-SKIP-STRING TYPE'],
          " rest")

    check("skip-string: escaped backslash",
          mstr('"he\\\\llo" rest') + ['TA CSS-SKIP-STRING TYPE'],
          " rest")

    check("skip-string: not a string",
          mstr("hello") + ['TA CSS-SKIP-STRING TYPE'],
          "hello")

    check("skip-string: empty string",
          mstr('""rest') + ['TA CSS-SKIP-STRING TYPE'],
          "rest")

    # -- CSS-SKIP-IDENT --
    check("skip-ident: simple",
          mstr("hello world") + ['TA CSS-SKIP-IDENT TYPE'],
          " world")

    check("skip-ident: with-hyphen",
          mstr("font-size: 12px") + ['TA CSS-SKIP-IDENT TYPE'],
          ": 12px")

    check("skip-ident: leading-hyphen",
          mstr("-webkit-thing rest") + ['TA CSS-SKIP-IDENT TYPE'],
          " rest")

    check("skip-ident: underscore",
          mstr("_private rest") + ['TA CSS-SKIP-IDENT TYPE'],
          " rest")

    check("skip-ident: with digits",
          mstr("h1 rest") + ['TA CSS-SKIP-IDENT TYPE'],
          " rest")

    check("skip-ident: not ident (digit start)",
          mstr("123abc") + ['TA CSS-SKIP-IDENT TYPE'],
          "123abc")

    # -- CSS-GET-IDENT --
    check("get-ident: extract name",
          mstr("color: red") + [
              'TA CSS-GET-IDENT',
              '2SWAP 2DROP TYPE'],
          "color")

    check("get-ident: hyphenated",
          mstr("font-size: 12px") + [
              'TA CSS-GET-IDENT',
              '2SWAP 2DROP TYPE'],
          "font-size")

    check("get-ident: cursor advances",
          mstr("color: red") + [
              'TA CSS-GET-IDENT',
              '2DROP TYPE'],
          ": red")

    # -- CSS-SKIP-BLOCK --
    check("skip-block: simple",
          mstr("{ color: red } rest") + ['TA CSS-SKIP-BLOCK TYPE'],
          " rest")

    check("skip-block: nested",
          mstr("{ a { b } c } rest") + ['TA CSS-SKIP-BLOCK TYPE'],
          " rest")

    check("skip-block: string inside",
          mstr('{ content: "}" } rest') + ['TA CSS-SKIP-BLOCK TYPE'],
          " rest")

    check("skip-block: comment inside",
          mstr("{ /* } */ color: red } rest") +
          ['TA CSS-SKIP-BLOCK TYPE'],
          " rest")

    check("skip-block: not at brace",
          mstr("hello") + ['TA CSS-SKIP-BLOCK TYPE'],
          "hello")

    # -- CSS-SKIP-PARENS --
    check("skip-parens: simple",
          mstr("(10px) rest") + ['TA CSS-SKIP-PARENS TYPE'],
          " rest")

    check("skip-parens: nested",
          mstr("(a (b) c) rest") + ['TA CSS-SKIP-PARENS TYPE'],
          " rest")

    check("skip-parens: string inside",
          mstr('(")") rest') + ['TA CSS-SKIP-PARENS TYPE'],
          " rest")

    check("skip-parens: not at paren",
          mstr("hello") + ['TA CSS-SKIP-PARENS TYPE'],
          "hello")

    # -- CSS-SKIP-UNTIL --
    check("skip-until: semicolon",
          mstr("color: red; next") + ['TA 59 CSS-SKIP-UNTIL TYPE'],
          "; next")

    check("skip-until: respects strings",
          mstr('content: ";"; next') + ['TA 59 CSS-SKIP-UNTIL TYPE'],
          "; next")

    check("skip-until: respects blocks",
          mstr("a { ; } ; rest") + ['TA 59 CSS-SKIP-UNTIL TYPE'],
          "; rest")

    check("skip-until: respects comments",
          mstr("a /* ; */ ; rest") + ['TA 59 CSS-SKIP-UNTIL TYPE'],
          "; rest")

    check("skip-until: respects parens",
          mstr("calc(;) ; rest") + ['TA 59 CSS-SKIP-UNTIL TYPE'],
          "; rest")

    # -- STR-STRI= --
    check("stri=: same case",
          mstr("color") + [
              'TA'] +
          mstr("color") + [
              'TA STR-STRI= .'],
          "-1 ")

    check("stri=: diff case",
          mstr("Color") + [
              'TA'] +
          mstr("color") + [
              'TA STR-STRI= .'],
          "-1 ")

    check("stri=: different",
          mstr("color") + [
              'TA'] +
          mstr("width") + [
              'TA STR-STRI= .'],
          "0 ")

    # -- Error handling --
    check("error: initial state",
          ['CSS-OK? .'],
          "-1 ")

    check("error: fail sets code",
          ['3 CSS-FAIL CSS-ERR @ .'],
          "3 ")

    check("error: ok? after fail",
          ['3 CSS-FAIL CSS-OK? .'],
          "0 ")

    check("error: clear-err resets",
          ['3 CSS-FAIL CSS-CLEAR-ERR CSS-OK? .'],
          "-1 ")


# ---------------------------------------------------------------------------
#  Layer 1 — Declaration Parsing
# ---------------------------------------------------------------------------

def test_layer1():
    print("\n=== Layer 1 — Declaration Parsing ===")

    # -- CSS-DECL-NEXT: basic --
    check("decl-next: single decl",
          mstr("color: red;") + [
              'TA CSS-DECL-NEXT',
              'IF 2>R 2SWAP 2DROP TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "color|red")

    check("decl-next: value with spaces",
          mstr("margin: 10px 20px;") + [
              'TA CSS-DECL-NEXT',
              'IF 2>R 2SWAP 2DROP TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "margin|10px 20px")

    check("decl-next: trims trailing ws",
          mstr("color: red  ;") + [
              'TA CSS-DECL-NEXT',
              'IF 2>R 2SWAP 2DROP TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "color|red")

    check("decl-next: at closing brace",
          mstr("}") + [
              'TA CSS-DECL-NEXT . . . . . '],
          "0 0 0 0 0 ")

    check("decl-next: empty input",
          mstr("") + [
              'TA CSS-DECL-NEXT . . . . . '],
          "0 0 0 0 0 ")

    # -- Multiple declarations --
    check("decl-next: two decls",
          mstr("color: red; font-size: 12px;") + [
              'TA CSS-DECL-NEXT IF',
              '  2>R 2>R 2R> TYPE 124 EMIT 2R> TYPE 32 EMIT',
              '  CSS-DECL-NEXT IF',
              '    2>R 2SWAP 2DROP TYPE 124 EMIT 2R> TYPE',
              '  THEN',
              'THEN'],
          "color|red font-size|12px")

    # -- Skip bare semicolons --
    check("decl-next: skips bare semicolons",
          mstr(";;color: red;") + [
              'TA CSS-DECL-NEXT',
              'IF 2>R 2SWAP 2DROP TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "color|red")

    # -- Value with special chars --
    check("decl-next: value with parens",
          mstr("background: url(test.png);") + [
              'TA CSS-DECL-NEXT',
              'IF 2>R 2SWAP 2DROP TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "background|url(test.png)")

    check("decl-next: value with string",
          mstr('content: "hello;world";') + [
              'TA CSS-DECL-NEXT',
              'IF 2>R 2SWAP 2DROP TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          'content|"hello;world"')

    # -- Last decl without semicolon (before }) --
    check("decl-next: no trailing semicolon",
          mstr("color: red}") + [
              'TA CSS-DECL-NEXT',
              'IF 2>R 2SWAP 2DROP TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "color|red")

    # -- CSS-DECL-FIND --
    check("decl-find: found",
          mstr("color: red; font-size: 12px; margin: 0;") + [
              'TA'] +
          mstr("font-size") + [
              'TA CSS-DECL-FIND',
              'IF TYPE ELSE 2DROP THEN'],
          "12px")

    check("decl-find: case insensitive",
          mstr("Color: red; FONT-SIZE: 12px;") + [
              'TA'] +
          mstr("font-size") + [
              'TA CSS-DECL-FIND',
              'IF TYPE ELSE 2DROP THEN'],
          "12px")

    check("decl-find: not found",
          mstr("color: red;") + [
              'TA'] +
          mstr("margin") + [
              'TA CSS-DECL-FIND . 2DROP'],
          "0 ")

    # -- CSS-DECL-HAS? --
    check("decl-has?: found",
          mstr("color: red; margin: 0;") + [
              'TA'] +
          mstr("margin") + [
              'TA CSS-DECL-HAS? .'],
          "-1 ")

    check("decl-has?: not found",
          mstr("color: red;") + [
              'TA'] +
          mstr("padding") + [
              'TA CSS-DECL-HAS? .'],
          "0 ")

    # -- CSS-IMPORTANT? --
    check("important?: yes",
          mstr("red !important") + [
              'TA CSS-IMPORTANT? .'],
          "-1 ")

    check("important?: no",
          mstr("red") + [
              'TA CSS-IMPORTANT? .'],
          "0 ")

    check("important?: case insensitive",
          mstr("red !IMPORTANT") + [
              'TA CSS-IMPORTANT? .'],
          "-1 ")

    check("important?: with trailing ws",
          mstr("red !important  ") + [
              'TA CSS-IMPORTANT? .'],
          "-1 ")

    # -- CSS-STRIP-IMPORTANT --
    check("strip-important: removes it",
          mstr("red !important") + [
              'TA CSS-STRIP-IMPORTANT TYPE'],
          "red")

    check("strip-important: no important",
          mstr("red") + [
              'TA CSS-STRIP-IMPORTANT TYPE'],
          "red")

    check("strip-important: trims ws",
          mstr("10px  !important") + [
              'TA CSS-STRIP-IMPORTANT TYPE'],
          "10px")


# ---------------------------------------------------------------------------
#  Layer 2 — Rule Iteration
# ---------------------------------------------------------------------------

def test_layer2():
    print("\n=== Layer 2 — Rule Iteration ===")

    # -- CSS-AT-RULE? --
    check("at-rule?: yes",
          mstr("@media screen") + [
              'TA CSS-AT-RULE? .'],
          "-1 ")

    check("at-rule?: no",
          mstr("h1 { color: red; }") + [
              'TA CSS-AT-RULE? .'],
          "0 ")

    check("at-rule?: empty",
          ['0 0 CSS-AT-RULE? .'],
          "0 ")

    # -- CSS-AT-RULE-NAME --
    check("at-rule-name: media",
          mstr("@media screen") + [
              'TA CSS-AT-RULE-NAME TYPE'],
          "media")

    check("at-rule-name: import",
          mstr("@import url(x);") + [
              'TA CSS-AT-RULE-NAME TYPE'],
          "import")

    check("at-rule-name: keyframes",
          mstr("@keyframes fade") + [
              'TA CSS-AT-RULE-NAME TYPE'],
          "keyframes")

    # -- CSS-SKIP-AT-RULE --
    check("skip-at-rule: block rule",
          mstr("@media screen { body { color: red; } }rest") + [
              'TA CSS-SKIP-AT-RULE TYPE'],
          "rest")

    check("skip-at-rule: statement rule",
          mstr('@import url("style.css");rest') + [
              'TA CSS-SKIP-AT-RULE TYPE'],
          "rest")

    check("skip-at-rule: charset",
          mstr('@charset "UTF-8";rest') + [
              'TA CSS-SKIP-AT-RULE TYPE'],
          "rest")

    check("skip-at-rule: not at-rule",
          mstr("h1 { color: red; }") + [
              'TA CSS-SKIP-AT-RULE TYPE'],
          "h1 { color: red; }")

    # -- CSS-RULE-NEXT --
    # Helper: print sel|body
    # After CSS-RULE-NEXT IF: stack = ( a' u' sel-a sel-u body-a body-u )
    # Use 2>R to stash body, 2>R for cursor, print sel, |, 2R> print body, drop cursor

    check("rule-next: single rule",
          mstr("h1 { color: red; }") + [
              'TA CSS-RULE-NEXT',
              'IF 2>R 2>R 2DROP 2R> TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "h1| color: red; ")

    check("rule-next: trimmed selector",
          mstr("  h1  { color: red; }") + [
              'TA CSS-RULE-NEXT',
              'IF 2>R 2>R 2DROP 2R> TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "h1| color: red; ")

    check("rule-next: empty body",
          mstr(".x {}") + [
              'TA CSS-RULE-NEXT',
              'IF 2>R 2>R 2DROP 2R> TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          ".x|")

    check("rule-next: complex selector",
          mstr("h1, h2.title > p { margin: 0; }") + [
              'TA CSS-RULE-NEXT',
              'IF 2>R 2>R 2DROP 2R> TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "h1, h2.title > p| margin: 0; ")

    check("rule-next: empty input",
          ['0 0 CSS-RULE-NEXT . 2DROP 2DROP'],
          "0 ")

    check("rule-next: whitespace only",
          mstr("   ") + [
              'TA CSS-RULE-NEXT . 2DROP 2DROP'],
          "0 ")

    check("rule-next: skips @-rules",
          mstr('@import url("x"); h1 { color: red; }') + [
              'TA CSS-RULE-NEXT',
              'IF 2>R 2>R 2DROP 2R> TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          "h1| color: red; ")

    check("rule-next: two rules",
          mstr("h1 { color: red; } p { margin: 0; }") + [
              'TA CSS-RULE-NEXT IF',
              '  2>R 2>R 2R> TYPE 124 EMIT 2R> TYPE 32 EMIT',
              '  CSS-RULE-NEXT IF',
              '    2>R 2SWAP 2DROP TYPE 124 EMIT 2R> TYPE',
              '  THEN',
              'THEN'],
          "h1| color: red;  p| margin: 0; ")

    check("rule-next: nested braces in value",
          mstr("p { content: \"}\"; }") + [
              'TA CSS-RULE-NEXT',
              'IF 2>R 2>R 2DROP 2R> TYPE',
              '  124 EMIT 2R> TYPE',
              'THEN'],
          'p| content: "}"; ')

    check("rule-next: no more rules flag",
          mstr("h1 { x: 1; }") + [
              'TA CSS-RULE-NEXT IF',
              '  2DROP 2DROP',
              '  CSS-RULE-NEXT . 2DROP 2DROP',
              'THEN'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 3 — Selector Parsing
# ---------------------------------------------------------------------------

def test_layer3():
    print("\n=== Layer 3 — Selector Parsing ===")

    # .SNS defined in snapshot: ( a u type na nu -- ) prints type|name

    # -- CSS-SEL-NEXT-SIMPLE --
    check("sel-simple: type",
          mstr("div") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "1|div")

    check("sel-simple: class",
          mstr(".active") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "3|active")

    check("sel-simple: id",
          mstr("#main") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "4|main")

    check("sel-simple: universal",
          mstr("*") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "2|")

    check("sel-simple: attribute bare",
          mstr("[href]") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "5|href")

    check("sel-simple: attribute with value",
          mstr('[type="text"]') + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          '5|type="text"')

    check("sel-simple: pseudo-class",
          mstr(":hover") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "6|hover")

    check("sel-simple: pseudo-element",
          mstr("::before") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "7|before")

    check("sel-simple: function pseudo",
          mstr(":nth-child(2n+1)") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'DROP .SNS'],
          "6|nth-child(2n+1)")

    check("sel-simple: empty",
          ['0 0 CSS-SEL-NEXT-SIMPLE',
           'IF 2DROP 2DROP 2DROP',
           'ELSE 2DROP DROP 2DROP 78 EMIT',
           'THEN'],
          "N")

    check("sel-simple: compound chain",
          mstr("div.active#main") + [
              'TA CSS-SEL-NEXT-SIMPLE',
              'IF 2>R 48 + EMIT 124 EMIT 2R> TYPE 32 EMIT',
              '  CSS-SEL-NEXT-SIMPLE',
              '  IF 2>R 48 + EMIT 124 EMIT 2R> TYPE 32 EMIT',
              '    CSS-SEL-NEXT-SIMPLE',
              '    IF 2>R 48 + EMIT 124 EMIT 2R> TYPE 2DROP',
              '    THEN',
              '  THEN',
              'THEN'],
          "1|div 3|active 4|main")

    # -- CSS-SEL-COMBINATOR --
    _COMB_PRINT = 'IF >R 2DROP R> 48 + EMIT ELSE DROP 2DROP 78 EMIT THEN'

    check("sel-comb: descendant",
          mstr(" p") + [
              'TA CSS-SEL-COMBINATOR',
              _COMB_PRINT],
          "0")

    check("sel-comb: child",
          mstr(" > p") + [
              'TA CSS-SEL-COMBINATOR',
              _COMB_PRINT],
          "1")

    check("sel-comb: adjacent",
          mstr(" + p") + [
              'TA CSS-SEL-COMBINATOR',
              _COMB_PRINT],
          "2")

    check("sel-comb: general sibling",
          mstr(" ~ p") + [
              'TA CSS-SEL-COMBINATOR',
              _COMB_PRINT],
          "3")

    check("sel-comb: end comma",
          mstr(", p") + [
              'TA CSS-SEL-COMBINATOR',
              _COMB_PRINT],
          "N")

    check("sel-comb: end empty",
          ['0 0 CSS-SEL-COMBINATOR',
           _COMB_PRINT],
          "N")

    # -- CSS-SEL-GROUP-NEXT --
    check("sel-group: single",
          mstr("h1") + [
              'TA CSS-SEL-GROUP-NEXT',
              'IF TYPE 2DROP ELSE 2DROP 78 EMIT THEN'],
          "h1")

    check("sel-group: two groups",
          mstr("h1, h2") + [
              'TA CSS-SEL-GROUP-NEXT IF',
              '  TYPE 32 EMIT',
              '  CSS-SEL-GROUP-NEXT IF',
              '    TYPE 2DROP',
              '  THEN',
              'THEN'],
          "h1 h2")

    check("sel-group: trims whitespace",
          mstr("  h1  ,  h2  ") + [
              'TA CSS-SEL-GROUP-NEXT IF',
              '  TYPE 32 EMIT',
              '  CSS-SEL-GROUP-NEXT IF',
              '    TYPE 2DROP',
              '  THEN',
              'THEN'],
          "h1 h2")

    check("sel-group: complex selectors",
          mstr("h1 > p, .class") + [
              'TA CSS-SEL-GROUP-NEXT IF',
              '  TYPE 32 EMIT',
              '  CSS-SEL-GROUP-NEXT IF',
              '    TYPE 2DROP',
              '  THEN',
              'THEN'],
          "h1 > p .class")

    check("sel-group: empty",
          ['0 0 CSS-SEL-GROUP-NEXT',
           'IF TYPE 2DROP ELSE 2DROP 78 EMIT THEN'],
          "N")

    check("sel-group: end flag",
          mstr("h1") + [
              'TA CSS-SEL-GROUP-NEXT IF',
              '  2DROP',
              '  CSS-SEL-GROUP-NEXT . 2DROP',
              'THEN'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 4 — Selector Matching
# ---------------------------------------------------------------------------

def test_layer4():
    print("\n=== Layer 4 — Selector Matching ===")

    # -- CSS-MATCH-TYPE --
    check("match-type: same case",
          mstr("div") + ['TA'] +
          ustr("div") + ['UA CSS-MATCH-TYPE .'],
          "-1 ")

    check("match-type: case insensitive",
          mstr("DIV") + ['TA'] +
          ustr("div") + ['UA CSS-MATCH-TYPE .'],
          "-1 ")

    check("match-type: mismatch",
          mstr("div") + ['TA'] +
          ustr("span") + ['UA CSS-MATCH-TYPE .'],
          "0 ")

    # -- CSS-MATCH-ID --
    check("match-id: match",
          mstr("main") + ['TA'] +
          ustr("main") + ['UA CSS-MATCH-ID .'],
          "-1 ")

    check("match-id: mismatch",
          mstr("main") + ['TA'] +
          ustr("nav") + ['UA CSS-MATCH-ID .'],
          "0 ")

    # -- CSS-MATCH-CLASS --
    check("match-class: single found",
          mstr("active") + ['TA'] +
          ustr("active") + ['UA CSS-MATCH-CLASS .'],
          "-1 ")

    check("match-class: among multiple",
          mstr("bar") + ['TA'] +
          ustr("foo bar baz") + ['UA CSS-MATCH-CLASS .'],
          "-1 ")

    check("match-class: not found",
          mstr("qux") + ['TA'] +
          ustr("foo bar baz") + ['UA CSS-MATCH-CLASS .'],
          "0 ")

    check("match-class: empty list",
          mstr("foo") + ['TA'] +
          ['0 0 CSS-MATCH-CLASS .'],
          "0 ")

    check("match-class: first in list",
          mstr("foo") + ['TA'] +
          ustr("foo bar baz") + ['UA CSS-MATCH-CLASS .'],
          "-1 ")

    check("match-class: last in list",
          mstr("baz") + ['TA'] +
          ustr("foo bar baz") + ['UA CSS-MATCH-CLASS .'],
          "-1 ")

    # -- CSS-MATCH-SIMPLE via CSS-MATCH-SET --
    check("match-simple: type match",
          ustr("div") + ['UA 0 0 0 0 CSS-MATCH-SET'] +
          mstr("div") + ['CSS-S-TYPE TA CSS-MATCH-SIMPLE .'],
          "-1 ")

    check("match-simple: type mismatch",
          ustr("div") + ['UA 0 0 0 0 CSS-MATCH-SET'] +
          mstr("span") + ['CSS-S-TYPE TA CSS-MATCH-SIMPLE .'],
          "0 ")

    check("match-simple: universal",
          ustr("div") + ['UA 0 0 0 0 CSS-MATCH-SET'] +
          ['CSS-S-UNIVERSAL 0 0 CSS-MATCH-SIMPLE .'],
          "-1 ")

    check("match-simple: id match",
          ustr("main") + ['0 0 UA 0 0 CSS-MATCH-SET'] +
          mstr("main") + ['CSS-S-ID TA CSS-MATCH-SIMPLE .'],
          "-1 ")

    check("match-simple: id mismatch",
          ustr("nav") + ['0 0 UA 0 0 CSS-MATCH-SET'] +
          mstr("main") + ['CSS-S-ID TA CSS-MATCH-SIMPLE .'],
          "0 ")

    check("match-simple: class match",
          ustr("foo bar baz") + ['0 0 0 0 UA CSS-MATCH-SET'] +
          mstr("bar") + ['CSS-S-CLASS TA CSS-MATCH-SIMPLE .'],
          "-1 ")

    check("match-simple: class mismatch",
          ustr("foo bar baz") + ['0 0 0 0 UA CSS-MATCH-SET'] +
          mstr("qux") + ['CSS-S-CLASS TA CSS-MATCH-SIMPLE .'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 5 — Specificity & Cascade
# ---------------------------------------------------------------------------

def test_layer5():
    print("\n=== Layer 5 — Specificity & Cascade ===")

    # CSS-SPECIFICITY returns ( a b c )
    # . . . prints c b a (stack order)
    check("specificity: type only",
          mstr("p") + ['TA CSS-SPECIFICITY . . .'],
          "1 0 0 ")

    check("specificity: class only",
          mstr(".foo") + ['TA CSS-SPECIFICITY . . .'],
          "0 1 0 ")

    check("specificity: id only",
          mstr("#bar") + ['TA CSS-SPECIFICITY . . .'],
          "0 0 1 ")

    check("specificity: universal",
          mstr("*") + ['TA CSS-SPECIFICITY . . .'],
          "0 0 0 ")

    check("specificity: compound",
          mstr("div.active") +
          ['TA CSS-SPECIFICITY . . .'],
          "1 1 0 ")

    check("specificity: complex",
          mstr("#main .content p") +
          ['TA CSS-SPECIFICITY . . .'],
          "1 1 1 ")

    check("specificity: multiple classes",
          mstr(".a.b.c") +
          ['TA CSS-SPECIFICITY . . .'],
          "0 3 0 ")

    check("specificity: id + type",
          mstr("#nav li") +
          ['TA CSS-SPECIFICITY . . .'],
          "1 0 1 ")

    # CSS-SPEC-COMPARE
    check("spec-compare: a wins",
          ['1 0 0 0 1 0 CSS-SPEC-COMPARE .'],
          "1 ")

    check("spec-compare: b wins",
          ['0 2 0 0 1 0 CSS-SPEC-COMPARE .'],
          "1 ")

    check("spec-compare: second wins",
          ['0 0 1 0 1 0 CSS-SPEC-COMPARE .'],
          "-1 ")

    check("spec-compare: equal",
          ['0 1 0 0 1 0 CSS-SPEC-COMPARE .'],
          "0 ")

    check("spec-compare: c decides",
          ['0 0 3 0 0 2 CSS-SPEC-COMPARE .'],
          "1 ")

    # CSS-SPEC-PACK
    check("spec-pack: simple",
          ['1 2 3 CSS-SPEC-PACK .'],
          "66051 ")

    check("spec-pack: zero",
          ['0 0 0 CSS-SPEC-PACK .'],
          "0 ")

    check("spec-pack: id only",
          ['1 0 0 CSS-SPEC-PACK .'],
          "65536 ")


# ---------------------------------------------------------------------------
#  Layer 6 — Value Parsing
# ---------------------------------------------------------------------------

def test_layer6():
    print("\n=== Layer 6 — Value Parsing ===")

    # -- CSS-PARSE-INT --
    check("parse-int: positive",
          mstr("42rest") + [
              'TA CSS-PARSE-INT',
              'IF . TYPE ELSE 2DROP . THEN'],
          "42 rest")

    check("parse-int: negative",
          mstr("-7rest") + [
              'TA CSS-PARSE-INT',
              'IF . TYPE ELSE 2DROP . THEN'],
          "-7 rest")

    check("parse-int: zero",
          mstr("0rest") + [
              'TA CSS-PARSE-INT',
              'IF . TYPE ELSE 2DROP . THEN'],
          "0 rest")

    check("parse-int: no digits",
          mstr("abc") + [
              'TA CSS-PARSE-INT',
              'IF . 2DROP ELSE 2DROP 78 EMIT THEN'],
          "N")

    check("parse-int: sign only",
          mstr("-abc") + [
              'TA CSS-PARSE-INT',
              'IF . 2DROP ELSE 2DROP 78 EMIT THEN'],
          "N")

    # -- CSS-PARSE-NUMBER --
    check("parse-num: integer",
          mstr("42rest") + [
              'TA CSS-PARSE-NUMBER',
              'IF . . . TYPE',
              'ELSE 2DROP . . . THEN'],
          "0 0 42 rest")

    check("parse-num: with decimal",
          mstr("3.14rest") + [
              'TA CSS-PARSE-NUMBER',
              'IF . . . TYPE',
              'ELSE 2DROP . . . THEN'],
          "2 14 3 rest")

    check("parse-num: decimal only",
          mstr(".5rest") + [
              'TA CSS-PARSE-NUMBER',
              'IF . . . TYPE',
              'ELSE 2DROP . . . THEN'],
          "1 5 0 rest")

    check("parse-num: negative",
          mstr("-10.5x") + [
              'TA CSS-PARSE-NUMBER',
              'IF . . . TYPE',
              'ELSE 2DROP . . . THEN'],
          "1 5 -10 x")

    check("parse-num: no number",
          mstr("abc") + [
              'TA CSS-PARSE-NUMBER',
              'IF . . . 2DROP ELSE 2DROP . . . 78 EMIT THEN'],
          "N")

    # -- CSS-SKIP-NUMBER --
    check("skip-number: basic",
          mstr("3.14px") + [
              'TA CSS-SKIP-NUMBER TYPE'],
          "px")

    check("skip-number: negative",
          mstr("-10em") + [
              'TA CSS-SKIP-NUMBER TYPE'],
          "em")

    check("skip-number: integer",
          mstr("42rest") + [
              'TA CSS-SKIP-NUMBER TYPE'],
          "rest")

    # -- CSS-PARSE-UNIT --
    check("parse-unit: px",
          mstr("px") + [
              'TA CSS-PARSE-UNIT TYPE 2DROP'],
          "px")

    check("parse-unit: percent",
          mstr("%") + [
              'TA CSS-PARSE-UNIT TYPE 2DROP'],
          "%")

    check("parse-unit: rem",
          mstr("rem") + [
              'TA CSS-PARSE-UNIT TYPE 2DROP'],
          "rem")

    check("parse-unit: none",
          mstr(" rest") + [
              'TA CSS-PARSE-UNIT . . 2DROP'],
          "0 0 ")

    # -- CSS-PARSE-HEX-COLOR --
    check("hex-color: 6-digit",
          mstr("#FF0000") + [
              'TA CSS-PARSE-HEX-COLOR',
              'IF . . . 2DROP ELSE 2DROP . . . THEN'],
          "0 0 255 ")

    check("hex-color: 3-digit",
          mstr("#F00") + [
              'TA CSS-PARSE-HEX-COLOR',
              'IF . . . 2DROP ELSE 2DROP . . . THEN'],
          "0 0 255 ")

    check("hex-color: mixed case",
          mstr("#aaBB11") + [
              'TA CSS-PARSE-HEX-COLOR',
              'IF . . . 2DROP ELSE 2DROP . . . THEN'],
          "17 187 170 ")

    check("hex-color: white 3-digit",
          mstr("#fff") + [
              'TA CSS-PARSE-HEX-COLOR',
              'IF . . . 2DROP ELSE 2DROP . . . THEN'],
          "255 255 255 ")

    check("hex-color: not a color",
          mstr("red") + [
              'TA CSS-PARSE-HEX-COLOR',
              'IF . . . 2DROP ELSE 2DROP 78 EMIT THEN'],
          "N")

    check("hex-color: cursor advance",
          mstr("#FF0000 rest") + [
              'TA CSS-PARSE-HEX-COLOR',
              'IF . . . TYPE ELSE 2DROP . . . THEN'],
          "0 0 255  rest")


# ---------------------------------------------------------------------------
#  Layer 7 — Shorthand Expansion
# ---------------------------------------------------------------------------

def test_layer7():
    print("\n=== Layer 7 — Shorthand Expansion ===")

    # -- CSS-SKIP-VALUE --
    check("skip-value: ident",
          mstr("bold rest") + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    check("skip-value: number+unit",
          mstr("10px rest") + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    check("skip-value: percent",
          mstr("50% rest") + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    check("skip-value: hex color",
          mstr("#ff0000 rest") + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    check("skip-value: function",
          mstr("rgb(1,2,3) rest") + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    check("skip-value: string",
          mstr('"hello" rest') + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    check("skip-value: negative number",
          mstr("-10em rest") + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    check("skip-value: decimal",
          mstr(".5em rest") + [
              'TA CSS-SKIP-VALUE TYPE'],
          " rest")

    # -- CSS-NEXT-VALUE --
    check("next-value: first of list",
          mstr("10px 20px") + [
              'TA CSS-NEXT-VALUE',
              'IF TYPE 2DROP ELSE 2DROP 78 EMIT THEN'],
          "10px")

    check("next-value: iterates",
          mstr("10px 20px 30px") + [
              'TA CSS-NEXT-VALUE IF',
              '  TYPE 32 EMIT',
              '  CSS-NEXT-VALUE IF',
              '    TYPE 32 EMIT',
              '    CSS-NEXT-VALUE IF',
              '      TYPE 2DROP',
              '    THEN',
              '  THEN',
              'THEN'],
          "10px 20px 30px")

    check("next-value: empty",
          ['0 0 CSS-NEXT-VALUE',
           'IF TYPE 2DROP ELSE 2DROP 78 EMIT THEN'],
          "N")

    check("next-value: leading ws",
          mstr("  bold") + [
              'TA CSS-NEXT-VALUE',
              'IF TYPE 2DROP ELSE 2DROP 78 EMIT THEN'],
          "bold")

    # -- CSS-EXPAND-TRBL --
    # Result: ( t-a t-u r-a r-u b-a b-u l-a l-u n )
    # We define a helper word to print T|R|B|L|n

    check("expand-trbl: 1 value",
          mstr("10px") + [
              'TA CSS-EXPAND-TRBL .TRBL'],
          "10px|10px|10px|10px|1 ")

    check("expand-trbl: 2 values",
          mstr("10px 20px") + [
              'TA CSS-EXPAND-TRBL .TRBL'],
          "10px|20px|10px|20px|2 ")

    check("expand-trbl: 3 values",
          mstr("10px 20px 30px") + [
              'TA CSS-EXPAND-TRBL .TRBL'],
          "10px|20px|30px|20px|3 ")

    check("expand-trbl: 4 values",
          mstr("10px 20px 30px 40px") + [
              'TA CSS-EXPAND-TRBL .TRBL'],
          "10px|20px|30px|40px|4 ")

    check("expand-trbl: empty",
          ['0 0 CSS-EXPAND-TRBL . 2DROP 2DROP 2DROP 2DROP'],
          "0 ")

    check("expand-trbl: auto keyword",
          mstr("auto") + [
              'TA CSS-EXPAND-TRBL .TRBL'],
          "auto|auto|auto|auto|1 ")


# ---------------------------------------------------------------------------
#  Layer 8 — @-Rule Parsing
# ---------------------------------------------------------------------------

def test_layer8():
    print("\n=== Layer 8 — @-Rule Parsing ===")

    # --- CSS-MEDIA-QUERY ---

    check("media-query: basic",
          mstr("@media screen { .x { color: red } }") + [
              'TA CSS-MEDIA-QUERY .2S'],
          "screen|.x { color: red }|-1 ")

    check("media-query: complex cond",
          mstr("@media screen and (max-width: 768px) { body { font-size: 14px } }") + [
              'TA CSS-MEDIA-QUERY .2S'],
          "screen and (max-width: 768px)|body { font-size: 14px }|-1 ")

    check("media-query: empty body",
          mstr("@media print { }") + [
              'TA CSS-MEDIA-QUERY .2S'],
          "print||-1 ")

    check("media-query: not media",
          mstr("@import \"x.css\";") + [
              'TA CSS-MEDIA-QUERY . . . . .'],
          "0 0 0 0 0 ")

    check("media-query: empty",
          mstr("") + [
              'TA CSS-MEDIA-QUERY . . . . .'],
          "0 0 0 0 0 ")

    # --- CSS-IMPORT-URL ---

    check("import-url: double quoted",
          mstr("@import \"style.css\";") + [
              'TA CSS-IMPORT-URL .1S'],
          "style.css|-1 ")

    check("import-url: single quoted",
          mstr("@import 'style.css';") + [
              'TA CSS-IMPORT-URL .1S'],
          "style.css|-1 ")

    check("import-url: url() double",
          mstr("@import url(\"style.css\");") + [
              'TA CSS-IMPORT-URL .1S'],
          "style.css|-1 ")

    check("import-url: url() single",
          mstr("@import url('style.css');") + [
              'TA CSS-IMPORT-URL .1S'],
          "style.css|-1 ")

    check("import-url: url() bare",
          mstr("@import url(style.css);") + [
              'TA CSS-IMPORT-URL .1S'],
          "style.css|-1 ")

    check("import-url: not import",
          mstr("@media screen { }") + [
              'TA CSS-IMPORT-URL . . .'],
          "0 0 0 ")

    check("import-url: empty",
          mstr("") + [
              'TA CSS-IMPORT-URL . . .'],
          "0 0 0 ")

    # --- CSS-KEYFRAMES ---

    check("keyframes: basic",
          mstr("@keyframes fadeIn { from { opacity: 0 } to { opacity: 1 } }") + [
              'TA CSS-KEYFRAMES .2S'],
          "fadeIn|from { opacity: 0 } to { opacity: 1 }|-1 ")

    check("keyframes: empty body",
          mstr("@keyframes spin { }") + [
              'TA CSS-KEYFRAMES .2S'],
          "spin||-1 ")

    check("keyframes: not keyframes",
          mstr("@media screen { }") + [
              'TA CSS-KEYFRAMES . . . . .'],
          "0 0 0 0 0 ")

    check("keyframes: empty",
          mstr("") + [
              'TA CSS-KEYFRAMES . . . . .'],
          "0 0 0 0 0 ")


# ---------------------------------------------------------------------------
#  Layer 9 — Builder
# ---------------------------------------------------------------------------

def test_layer9():
    print("\n=== Layer 9 — Builder ===")

    # --- Output setup ---

    check("builder: set+result",
          ['CREATE _OB 512 ALLOT  _OB 512 CSS-SET-OUTPUT',
           'CSS-OUTPUT-RESULT NIP .'],
          "0 ")

    # --- CSS-RULE-START / CSS-RULE-END ---

    check("builder: rule",
          ['CREATE _OB2 512 ALLOT  _OB2 512 CSS-SET-OUTPUT'] +
          mstr("div") + [
              'TA CSS-RULE-START CSS-RULE-END',
              'CSS-OUTPUT-RESULT TYPE'],
          "div { } ")

    # --- CSS-PROP! ---

    check("builder: prop",
          ['CREATE _OB3 512 ALLOT  _OB3 512 CSS-SET-OUTPUT'] +
          mstr("red") +
          ustr("color") + [
              'UA TA CSS-PROP!',
              'CSS-OUTPUT-RESULT TYPE'],
          "color: red; ")

    # --- Full rule with properties ---

    check("builder: rule with props",
          ['CREATE _OB4 512 ALLOT  _OB4 512 CSS-SET-OUTPUT'] +
          mstr("div") + ['TA CSS-RULE-START'] +
          mstr("red") + ustr("color") + ['UA TA CSS-PROP!'] +
          mstr("10px") + ustr("margin") + ['UA TA CSS-PROP!'] +
          ['CSS-RULE-END',
           'CSS-OUTPUT-RESULT TYPE'],
          "div { color: red; margin: 10px; } ")

    # --- CSS-COMMENT! ---

    check("builder: comment",
          ['CREATE _OB5 512 ALLOT  _OB5 512 CSS-SET-OUTPUT'] +
          mstr("reset styles") + [
              'TA CSS-COMMENT!',
              'CSS-OUTPUT-RESULT TYPE'],
          "/* reset styles */ ")

    # --- CSS-MEDIA-START / CSS-MEDIA-END ---

    check("builder: media block",
          ['CREATE _OB6 512 ALLOT  _OB6 512 CSS-SET-OUTPUT'] +
          mstr("screen") + ['TA CSS-MEDIA-START'] +
          mstr("body") + ['TA CSS-RULE-START'] +
          mstr("14px") + ustr("font-size") + ['UA TA CSS-PROP!'] +
          ['CSS-RULE-END CSS-MEDIA-END',
           'CSS-OUTPUT-RESULT TYPE'],
          "@media screen { body { font-size: 14px; } } ")

    # --- CSS-IMPORT! ---

    check("builder: import",
          ['CREATE _OB7 512 ALLOT  _OB7 512 CSS-SET-OUTPUT'] +
          mstr("style.css") + [
              'TA CSS-IMPORT!',
              'CSS-OUTPUT-RESULT TYPE'],
          "@import url(\"style.css\"); ")

    # --- CSS-OUTPUT-RESET ---

    check("builder: reset",
          ['CREATE _OB8 512 ALLOT  _OB8 512 CSS-SET-OUTPUT'] +
          mstr("div") + ['TA CSS-RULE-START CSS-RULE-END'] +
          ['CSS-OUTPUT-RESET CSS-OUTPUT-RESULT .'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 10 — Named Colors
# ---------------------------------------------------------------------------

def test_layer10():
    print("\n=== Layer 10 — Named Colors ===")

    check("color-find: red",
          mstr("red") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 0 0 255 ")

    check("color-find: blue",
          mstr("blue") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 255 0 0 ")

    check("color-find: green",
          mstr("green") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 0 128 0 ")

    check("color-find: white",
          mstr("white") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 255 255 255 ")

    check("color-find: black",
          mstr("black") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 0 0 0 ")

    check("color-find: case insensitive",
          mstr("Red") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 0 0 255 ")

    check("color-find: cornflowerblue",
          mstr("cornflowerblue") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 237 149 100 ")

    check("color-find: rebeccapurple",
          mstr("rebeccapurple") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 153 51 102 ")

    check("color-find: yellowgreen",
          mstr("yellowgreen") + ['TA CSS-COLOR-FIND . . . .'],
          "-1 50 205 154 ")

    check("color-find: not found",
          mstr("notacolor") + ['TA CSS-COLOR-FIND . . . .'],
          "0 0 0 0 ")

    check("color-find: empty",
          mstr("") + ['TA CSS-COLOR-FIND . . . .'],
          "0 0 0 0 ")


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    build_snapshot()

    test_layer0()
    test_layer1()
    test_layer2()
    test_layer3()
    test_layer4()
    test_layer5()
    test_layer6()
    test_layer7()
    test_layer8()
    test_layer9()
    test_layer10()

    print(f"\n{'='*50}")
    print(f"  Total: {_pass_count + _fail_count}  "
          f"Pass: {_pass_count}  Fail: {_fail_count}")
    print(f"{'='*50}")
    sys.exit(1 if _fail_count else 0)
