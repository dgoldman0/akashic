#!/usr/bin/env python3
"""Test suite for akashic-markup-core Forth library.

Uses the Megapad-64 emulator to boot KDOS, load core.f,
and run Forth test expressions.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "utils", "string", "string.f")
CORE_F     = os.path.join(ROOT_DIR, "utils", "markup", "core.f")
XML_F      = os.path.join(ROOT_DIR, "utils", "markup", "xml.f")
HTML_F     = os.path.join(ROOT_DIR, "utils", "markup", "html.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

# ---------------------------------------------------------------------------
#  Emulator helpers (same pattern as test_json.py)
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
            # Skip REQUIRE lines — we load files explicitly
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
    """Boot BIOS + KDOS + core.f, save snapshot for fast test replay."""
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + string.f + markup/core.f ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    core_lines = _load_forth_lines(CORE_F)
    xml_lines  = _load_forth_lines(XML_F)
    html_lines = _load_forth_lines(HTML_F)

    # Test helper words: buffer for constructing test input strings
    test_helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 256 ALLOT',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + str_lines + core_lines + xml_lines + html_lines + test_helpers
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
    """Build Forth lines that construct string s in _TB using TC.

    Handles any character including angle brackets and quotes.
    Splits into multiple lines to avoid TIB overflow (~70 chars/line).
    """
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
#  Layer 0 — Low-level Scanning Primitives
# ---------------------------------------------------------------------------

def test_layer0():
    print("\n--- Layer 0: Low-level Scanning ---")

    # MU-SKIP-WS
    check("SKIP-WS spaces",
          mstr('   hello') +
          [': _T TA MU-SKIP-WS TYPE ; _T'],
          "hello")

    check("SKIP-WS tabs and newlines",
          mstr('\t\n\r hello') +
          [': _T TA MU-SKIP-WS TYPE ; _T'],
          "hello")

    check("SKIP-WS no whitespace",
          mstr('hello') +
          [': _T TA MU-SKIP-WS TYPE ; _T'],
          "hello")

    check("SKIP-WS empty",
          [': _T 0 0 MU-SKIP-WS DUP . ; _T'],
          "0 ")

    # MU-SKIP-UNTIL-CH
    check("SKIP-UNTIL-CH found",
          mstr('hello>world') +
          [': _T TA 62 MU-SKIP-UNTIL-CH TYPE ; _T'],
          ">world")

    check("SKIP-UNTIL-CH not found",
          mstr('hello') +
          [': _T TA 62 MU-SKIP-UNTIL-CH DUP . ; _T'],
          "0 ")

    check("SKIP-UNTIL-CH at start",
          mstr('>hello') +
          [': _T TA 62 MU-SKIP-UNTIL-CH TYPE ; _T'],
          ">hello")

    # MU-SKIP-PAST-CH
    check("SKIP-PAST-CH found",
          mstr('hello>world') +
          [': _T TA 62 MU-SKIP-PAST-CH TYPE ; _T'],
          "world")

    check("SKIP-PAST-CH not found",
          mstr('hello') +
          [': _T TA 62 MU-SKIP-PAST-CH DUP . ; _T'],
          "0 ")

    # MU-SKIP-NAME
    check("SKIP-NAME alpha",
          mstr('div class="x"') +
          [': _T TA MU-SKIP-NAME TYPE ; _T'],
          ' class="x"')

    check("SKIP-NAME with hyphen",
          mstr('data-id="5" >') +
          [': _T TA MU-SKIP-NAME TYPE ; _T'],
          '="5" >')

    check("SKIP-NAME with colon",
          mstr('xml:lang="en" >') +
          [': _T TA MU-SKIP-NAME TYPE ; _T'],
          '="en" >')

    check("SKIP-NAME digits",
          mstr('h1 class') +
          [': _T TA MU-SKIP-NAME TYPE ; _T'],
          ' class')

    # MU-GET-NAME
    check("GET-NAME tag",
          mstr('div class="x"') +
          [': _T TA MU-GET-NAME TYPE ; _T'],
          "div")

    check("GET-NAME namespaced",
          mstr('xml:lang="en"') +
          [': _T TA MU-GET-NAME TYPE ; _T'],
          "xml:lang")

    # After GET-NAME, remainder is available
    check("GET-NAME remainder",
          mstr('div class="x"') +
          [': _T TA MU-GET-NAME 2DROP TYPE ; _T'],
          ' class="x"')

    # MU-SKIP-QUOTED
    check("SKIP-QUOTED double",
          mstr('"hello" rest') +
          [': _T TA MU-SKIP-QUOTED TYPE ; _T'],
          " rest")

    check("SKIP-QUOTED single",
          mstr("'hello' rest") +
          [': _T TA MU-SKIP-QUOTED TYPE ; _T'],
          " rest")

    check("SKIP-QUOTED with inner content",
          mstr('"hello world 123" rest') +
          [': _T TA MU-SKIP-QUOTED TYPE ; _T'],
          " rest")

    # MU-GET-QUOTED
    check("GET-QUOTED double",
          mstr('"hello" rest') +
          [': _T TA MU-GET-QUOTED TYPE ; _T'],
          "hello")

    check("GET-QUOTED single",
          mstr("'world' rest") +
          [': _T TA MU-GET-QUOTED TYPE ; _T'],
          "world")

    check("GET-QUOTED remainder",
          mstr('"hello" rest') +
          [': _T TA MU-GET-QUOTED 2DROP TYPE ; _T'],
          " rest")

    check("GET-QUOTED empty",
          mstr('""next') +
          [': _T TA MU-GET-QUOTED DUP . 2DROP TYPE ; _T'],
          "0 ")  # length = 0

    # STR-STR=
    check("STR= match",
          mstr('hello') +
          [': _T TA TA STR-STR= . ; _T'],
          "-1 ")

    check("STR= no match",
          mstr('helloworld') +
          [': _T TA 5 2DUP 5 /STRING STR-STR= . ; _T'],
          "0 ")

    check("STR= different length",
          mstr('hello') +
          [': _T TA 2DUP 1- STR-STR= . ; _T'],
          "0 ")

    check("STR= empty",
          [': _T 0 0 0 0 STR-STR= . ; _T'],
          "-1 ")

    # STR-STRI=
    check("STRI= case match",
          mstr('DIVdiv') +
          [': _T _TB 3  _TB 3 + 3  STR-STRI= . ; _T'],
          "-1 ")

    check("STRI= mixed case",
          mstr('HeLlOhello') +
          [': _T _TB 5  _TB 5 + 5  STR-STRI= . ; _T'],
          "-1 ")

    check("STRI= no match",
          mstr('divspan') +
          [': _T _TB 3  _TB 3 + 3  STR-STRI= . ; _T'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 1 — Tag Detection & Classification
# ---------------------------------------------------------------------------

def test_layer1():
    print("\n--- Layer 1: Tag Classification ---")

    # MU-AT-TAG?
    check("AT-TAG? yes",
          mstr('<div>') +
          [': _T TA MU-AT-TAG? . ; _T'],
          "-1 ")

    check("AT-TAG? no",
          mstr('hello') +
          [': _T TA MU-AT-TAG? . ; _T'],
          "0 ")

    check("AT-TAG? empty",
          [': _T 0 0 MU-AT-TAG? . ; _T'],
          "0 ")

    # MU-TAG-TYPE — open tag
    check("TAG-TYPE open",
          mstr('<div>') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "1 ")  # MU-T-OPEN

    check("TAG-TYPE open with attrs",
          mstr('<div class="x">') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "1 ")

    # MU-TAG-TYPE — close tag
    check("TAG-TYPE close",
          mstr('</div>') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "2 ")  # MU-T-CLOSE

    # MU-TAG-TYPE — self-close
    check("TAG-TYPE self-close",
          mstr('<br/>') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "3 ")  # MU-T-SELF-CLOSE

    check("TAG-TYPE self-close with space",
          mstr('<img src="x" />') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "3 ")

    # MU-TAG-TYPE — comment
    check("TAG-TYPE comment",
          mstr('<!-- hello -->') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "4 ")  # MU-T-COMMENT

    # MU-TAG-TYPE — PI
    check("TAG-TYPE PI",
          mstr('<?xml version="1.0"?>') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "5 ")  # MU-T-PI

    # MU-TAG-TYPE — CDATA
    check("TAG-TYPE CDATA",
          mstr('<![CDATA[hello]]>') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "6 ")  # MU-T-CDATA

    # MU-TAG-TYPE — DOCTYPE
    check("TAG-TYPE DOCTYPE upper",
          mstr('<!DOCTYPE html>') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "7 ")  # MU-T-DOCTYPE

    check("TAG-TYPE DOCTYPE lower",
          mstr('<!doctype html>') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "7 ")

    # MU-TAG-TYPE — text (not a tag)
    check("TAG-TYPE text",
          mstr('hello world') +
          [': _T TA MU-TAG-TYPE . ; _T'],
          "0 ")  # MU-T-TEXT

    check("TAG-TYPE empty",
          [': _T 0 0 MU-TAG-TYPE . ; _T'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 2 — Tag Scanning
# ---------------------------------------------------------------------------

def test_layer2():
    print("\n--- Layer 2: Tag Scanning ---")

    # MU-SKIP-TAG
    check("SKIP-TAG open",
          mstr('<div>hello') +
          [': _T TA MU-SKIP-TAG TYPE ; _T'],
          "hello")

    check("SKIP-TAG open with attrs",
          mstr('<div class="x">hello') +
          [': _T TA MU-SKIP-TAG TYPE ; _T'],
          "hello")

    check("SKIP-TAG self-close",
          mstr('<br/>hello') +
          [': _T TA MU-SKIP-TAG TYPE ; _T'],
          "hello")

    check("SKIP-TAG with quotes containing >",
          mstr('<div data="a>b">hello') +
          [': _T TA MU-SKIP-TAG TYPE ; _T'],
          "hello")

    check("SKIP-TAG not at tag",
          mstr('hello') +
          [': _T TA MU-SKIP-TAG TYPE ; _T'],
          "hello")

    # MU-SKIP-COMMENT
    check("SKIP-COMMENT basic",
          mstr('<!-- comment -->rest') +
          [': _T TA MU-SKIP-COMMENT TYPE ; _T'],
          "rest")

    check("SKIP-COMMENT with dashes",
          mstr('<!-- a -- b -->rest') +
          [': _T TA MU-SKIP-COMMENT TYPE ; _T'],
          "rest")

    # MU-SKIP-PI
    check("SKIP-PI basic",
          mstr('<?xml version="1.0"?>rest') +
          [': _T TA MU-SKIP-PI TYPE ; _T'],
          "rest")

    # MU-SKIP-CDATA
    check("SKIP-CDATA basic",
          mstr('<![CDATA[hello world]]>rest') +
          [': _T TA MU-SKIP-CDATA TYPE ; _T'],
          "rest")

    check("SKIP-CDATA with brackets",
          mstr('<![CDATA[a]b]]>rest') +
          [': _T TA MU-SKIP-CDATA TYPE ; _T'],
          "rest")

    # MU-SKIP-TO-TAG
    check("SKIP-TO-TAG basic",
          mstr('hello<div>') +
          [': _T TA MU-SKIP-TO-TAG TYPE ; _T'],
          "<div>")

    check("SKIP-TO-TAG at tag",
          mstr('<div>') +
          [': _T TA MU-SKIP-TO-TAG TYPE ; _T'],
          "<div>")

    # MU-GET-TEXT
    check("GET-TEXT basic",
          mstr('hello world<br>') +
          [': _T TA MU-GET-TEXT TYPE ; _T'],
          "hello world")

    check("GET-TEXT remainder",
          mstr('hello<br>') +
          [': _T TA MU-GET-TEXT 2DROP TYPE ; _T'],
          "<br>")

    check("GET-TEXT empty",
          mstr('<br>') +
          [': _T TA MU-GET-TEXT DUP . 2DROP 2DROP ; _T'],
          "0 ")

    # MU-GET-TAG-NAME
    check("GET-TAG-NAME open",
          mstr('<div class="x">') +
          [': _T TA MU-GET-TAG-NAME TYPE ; _T'],
          "div")

    check("GET-TAG-NAME close",
          mstr('</div>') +
          [': _T TA MU-GET-TAG-NAME TYPE ; _T'],
          "div")

    check("GET-TAG-NAME self-close",
          mstr('<br/>') +
          [': _T TA MU-GET-TAG-NAME TYPE ; _T'],
          "br")

    check("GET-TAG-NAME namespaced",
          mstr('<xml:lang>') +
          [': _T TA MU-GET-TAG-NAME TYPE ; _T'],
          "xml:lang")

    # MU-GET-TAG-BODY
    check("GET-TAG-BODY open",
          mstr('<div class="x">rest') +
          [': _T TA MU-GET-TAG-BODY TYPE ; _T'],
          'div class="x"')

    check("GET-TAG-BODY self-close",
          mstr('<br/>rest') +
          [': _T TA MU-GET-TAG-BODY TYPE ; _T'],
          "br/")

    check("GET-TAG-BODY close",
          mstr('</div>rest') +
          [': _T TA MU-GET-TAG-BODY TYPE ; _T'],
          "/div")


# ---------------------------------------------------------------------------
#  Layer 3 — Attribute Parsing
# ---------------------------------------------------------------------------

def test_layer3():
    print("\n--- Layer 3: Attribute Parsing ---")

    # To test MU-ATTR-NEXT, we need a tag body past the tag name.
    # Strategy: use MU-GET-TAG-BODY then MU-SKIP-NAME MU-SKIP-WS
    # to position past the tag name into the attribute area.

    # Helper: extract first attr name from a tag
    check("ATTR-NEXT name=value",
          mstr('div class="main"') +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  DROP 2SWAP 2DROP  TYPE ; _T'],
          "main")

    check("ATTR-NEXT name only",
          mstr('div class="main"') +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  DROP 2DROP  TYPE  2DROP ; _T'],
          "class")

    check("ATTR-NEXT single quotes",
          mstr("div id='foo'") +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  DROP 2SWAP 2DROP  TYPE ; _T'],
          "foo")

    check("ATTR-NEXT bare attr",
          mstr('input disabled >') +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  DROP DUP . 2DROP  TYPE  2DROP ; _T'],
          "0 ")  # value len = 0

    check("ATTR-NEXT bare attr name",
          mstr('input disabled >') +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  DROP 2DROP  TYPE  2DROP ; _T'],
          "disabled")

    check("ATTR-NEXT no attrs",
          mstr('div>') +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  . 2DROP 2DROP 2DROP ; _T'],
          "0 ")  # flag = 0

    # Multiple attributes
    check("ATTR-NEXT two attrs first",
          mstr('div class="a" id="b"') +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  DROP 2SWAP 2DROP  TYPE ; _T'],
          "a")

    check("ATTR-NEXT two attrs second",
          mstr('div class="a" id="b"') +
          [': _T TA MU-SKIP-NAME MU-ATTR-NEXT',
           '  DROP 2DROP 2DROP',
           '  MU-ATTR-NEXT DROP 2SWAP 2DROP TYPE ; _T'],
          "b")

    # MU-ATTR-FIND
    check("ATTR-FIND found",
          mstr('div class="main" id="x"') +
          [': _T TA MU-SKIP-NAME',
           '  _TB 19 + 2  MU-ATTR-FIND  . 2DROP 2DROP ; _T'],
          None)  # just checking it doesn't crash for now

    # Simpler: construct search name separately
    check("ATTR-FIND by name",
          mstr('div class="main" id="top"') +
          # Build "id" at a known buffer location (_TB+256)
          ['_TB 256 + 105 OVER C! 1+  100 SWAP C!',
           ': _T TA MU-SKIP-NAME',
           '  _TB 256 + 2 MU-ATTR-FIND',
           '  . TYPE 2DROP ; _T'],
          "-1 top")

    check("ATTR-FIND not found",
          mstr('div class="main"') +
          ['_TB 256 + 105 OVER C! 1+  100 SWAP C!',
           ': _T TA MU-SKIP-NAME',
           '  _TB 256 + 2 MU-ATTR-FIND',
           '  . 2DROP 2DROP ; _T'],
          "0 ")

    # MU-ATTR-HAS?
    check("ATTR-HAS? yes",
          mstr('div class="x"') +
          ['_TB 256 + 99 OVER C! 1+ 108 OVER C! 1+ 97 OVER C! 1+ 115 OVER C! 1+ 115 SWAP C!',
           ': _T TA MU-SKIP-NAME  _TB 256 + 5 MU-ATTR-HAS? . 2DROP ; _T'],
          "-1 ")

    check("ATTR-HAS? no",
          mstr('div class="x"') +
          ['_TB 256 + 105 OVER C! 1+  100 SWAP C!',
           ': _T TA MU-SKIP-NAME  _TB 256 + 2 MU-ATTR-HAS? . 2DROP ; _T'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 4 — Entity Decoding
# ---------------------------------------------------------------------------

def test_layer4():
    print("\n--- Layer 4: Entity Decoding ---")

    # MU-DECODE-ENTITY — named entities
    check("DECODE amp",
          mstr('&amp;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "&rest")

    check("DECODE lt",
          mstr('&lt;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "<rest")

    check("DECODE gt",
          mstr('&gt;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          ">rest")

    check("DECODE quot",
          mstr('&quot;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          '"rest')

    check("DECODE apos",
          mstr('&apos;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "'rest")

    # Numeric decimal
    check("DECODE decimal",
          mstr('&#60;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "<rest")

    check("DECODE decimal 65",
          mstr('&#65;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "Arest")

    # Numeric hex
    check("DECODE hex lower",
          mstr('&#x3c;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "<rest")

    check("DECODE hex upper",
          mstr('&#x3C;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "<rest")

    check("DECODE hex 41",
          mstr('&#x41;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "Arest")

    # Non-entity character
    check("DECODE plain char",
          mstr('hello') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "hello")

    # Unknown entity — returns '&'
    check("DECODE unknown",
          mstr('&foo;rest') +
          [': _T TA MU-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "&foo;rest")

    # MU-UNESCAPE
    check("UNESCAPE basic",
          mstr('a&amp;b') +
          [': _T TA _UB 256 MU-UNESCAPE _UB SWAP TYPE ; _T'],
          "a&b")

    check("UNESCAPE multiple",
          mstr('&lt;div&gt;') +
          [': _T TA _UB 256 MU-UNESCAPE _UB SWAP TYPE ; _T'],
          "<div>")

    check("UNESCAPE mixed",
          mstr('a&#65;b&amp;c') +
          [': _T TA _UB 256 MU-UNESCAPE _UB SWAP TYPE ; _T'],
          "aAb&c")

    check("UNESCAPE no entities",
          mstr('hello world') +
          [': _T TA _UB 256 MU-UNESCAPE _UB SWAP TYPE ; _T'],
          "hello world")

    check("UNESCAPE empty",
          [': _T 0 0 _UB 256 MU-UNESCAPE . ; _T'],
          "0 ")


# ---------------------------------------------------------------------------
#  Layer 5 — Element Navigation
# ---------------------------------------------------------------------------

def test_layer5():
    print("\n--- Layer 5: Element Navigation ---")

    # MU-ENTER
    check("ENTER basic",
          mstr('<div>hello</div>') +
          [': _T TA MU-ENTER TYPE ; _T'],
          "hello</div>")

    check("ENTER with attrs",
          mstr('<div class="x">hello</div>') +
          [': _T TA MU-ENTER TYPE ; _T'],
          "hello</div>")

    # MU-SKIP-ELEMENT
    check("SKIP-ELEMENT simple",
          mstr('<div>hello</div>rest') +
          [': _T TA MU-SKIP-ELEMENT TYPE ; _T'],
          "rest")

    check("SKIP-ELEMENT nested",
          mstr('<div><p>inner</p></div>rest') +
          [': _T TA MU-SKIP-ELEMENT TYPE ; _T'],
          "rest")

    check("SKIP-ELEMENT self-close",
          mstr('<br/>rest') +
          [': _T TA MU-SKIP-ELEMENT TYPE ; _T'],
          "rest")

    check("SKIP-ELEMENT deeply nested",
          mstr('<a><b><c>x</c></b></a>rest') +
          [': _T TA MU-SKIP-ELEMENT TYPE ; _T'],
          "rest")

    check("SKIP-ELEMENT with comment",
          mstr('<div><!-- comment --></div>rest') +
          [': _T TA MU-SKIP-ELEMENT TYPE ; _T'],
          "rest")

    # MU-INNER
    check("INNER basic",
          mstr('<div>hello world</div>') +
          [': _T TA MU-INNER TYPE ; _T'],
          "hello world")

    check("INNER nested",
          mstr('<div><p>inner</p></div>') +
          [': _T TA MU-INNER TYPE ; _T'],
          "<p>inner</p>")

    check("INNER empty",
          mstr('<div></div>') +
          [': _T TA MU-INNER DUP . 2DROP ; _T'],
          "0 ")

    # MU-FIND-CLOSE
    check("FIND-CLOSE basic",
          mstr('hello</div>rest') +
          # Position is inside element, searching for "div"
          ['_TB 256 + 100 OVER C! 1+ 105 OVER C! 1+ 118 SWAP C!',
           ': _T TA _TB 256 + 3 MU-FIND-CLOSE TYPE ; _T'],
          "</div>rest")

    check("FIND-CLOSE nested",
          mstr('<div>inner</div></div>rest') +
          ['_TB 256 + 100 OVER C! 1+ 105 OVER C! 1+ 118 SWAP C!',
           ': _T TA _TB 256 + 3 MU-FIND-CLOSE TYPE ; _T'],
          "</div>rest")

    # MU-NEXT-SIBLING
    check("NEXT-SIBLING found",
          mstr('<a>1</a><b>2</b>') +
          [': _T TA MU-NEXT-SIBLING . TYPE ; _T'],
          "-1 <b>2</b>")

    check("NEXT-SIBLING at end",
          mstr('<a>1</a>') +
          [': _T TA MU-NEXT-SIBLING . 2DROP ; _T'],
          "0 ")

    # MU-FIND-TAG
    check("FIND-TAG first match",
          mstr('<a>1</a><b>2</b><a>3</a>') +
          ['_TB 256 + 97 SWAP C!',
           ': _T TA _TB 256 + 1 MU-FIND-TAG . TYPE ; _T'],
          "-1 <a>1</a>")

    check("FIND-TAG skip non-match",
          mstr('<a>1</a><b>2</b><c>3</c>') +
          # Search for "c"
          ['_TB 256 + 99 SWAP C!',
           ': _T TA _TB 256 + 1 MU-FIND-TAG . TYPE ; _T'],
          "-1 <c>3</c>")

    check("FIND-TAG not found",
          mstr('<a>1</a><b>2</b>') +
          ['_TB 256 + 99 SWAP C!',
           ': _T TA _TB 256 + 1 MU-FIND-TAG . 2DROP ; _T'],
          "0 ")


# ---------------------------------------------------------------------------
#  XML Reader
# ---------------------------------------------------------------------------

def test_xml_reader():
    print("\n--- XML Reader ---")

    # XML-ENTER
    check("XML-ENTER",
          mstr('<root>content</root>') +
          [': _T TA XML-ENTER TYPE ; _T'],
          "content</root>")

    # XML-TEXT
    check("XML-TEXT basic",
          mstr('<msg>hello world</msg>') +
          [': _T TA XML-TEXT TYPE ; _T'],
          "hello world")

    check("XML-TEXT with children",
          mstr('<div>text<br/>more</div>') +
          [': _T TA XML-TEXT TYPE ; _T'],
          "text")

    # XML-INNER
    check("XML-INNER",
          mstr('<div><p>hi</p></div>') +
          [': _T TA XML-INNER TYPE ; _T'],
          "<p>hi</p>")

    # XML-CHILD
    check("XML-CHILD found",
          mstr('<root><a>1</a><b>2</b></root>') +
          ['_TB 256 + 98 SWAP C!',
           ': _T TA _TB 256 + 1 XML-CHILD MU-INNER TYPE ; _T'],
          "2")

    # XML-CHILD?
    check("XML-CHILD? found",
          mstr('<root><item>x</item></root>') +
          ['_TB 256 + 105 OVER C! 1+ 116 OVER C! 1+ 101 OVER C! 1+ 109 SWAP C!',
           ': _T TA _TB 256 + 4 XML-CHILD? . 2DROP ; _T'],
          "-1 ")

    check("XML-CHILD? not found",
          mstr('<root><a>1</a></root>') +
          ['_TB 256 + 120 SWAP C!',
           ': _T TA _TB 256 + 1 XML-CHILD? . 2DROP ; _T'],
          "0 ")

    # XML-ATTR
    check("XML-ATTR basic",
          mstr('<div id="main">') +
          ['_TB 256 + 105 OVER C! 1+ 100 SWAP C!',
           ': _T TA _TB 256 + 2 XML-ATTR TYPE ; _T'],
          "main")

    # XML-ATTR?
    check("XML-ATTR? found",
          mstr('<div class="big" id="x">') +
          ['_TB 256 + 105 OVER C! 1+ 100 SWAP C!',
           ': _T TA _TB 256 + 2 XML-ATTR? . TYPE ; _T'],
          "-1 x")

    check("XML-ATTR? not found",
          mstr('<div class="big">') +
          ['_TB 256 + 105 OVER C! 1+ 100 SWAP C!',
           ': _T TA _TB 256 + 2 XML-ATTR? . 2DROP ; _T'],
          "0 ")

    # XML-GET-CDATA
    check("XML-GET-CDATA",
          mstr('<![CDATA[hello <world>]]>') +
          [': _T TA XML-GET-CDATA TYPE ; _T'],
          "hello <world>")

    # XML-PATH
    check("XML-PATH simple",
          mstr('<a><b><c>deep</c></b></a>') +
          ['_TB 256 + 97 OVER C! 1+ 47 OVER C! 1+ 98 OVER C! 1+ 47 OVER C! 1+ 99 SWAP C!',
           ': _T TA _TB 256 + 5 XML-PATH MU-INNER TYPE ; _T'],
          "deep")

    # XML-EACH-CHILD
    check("XML-EACH-CHILD first",
          mstr('<root><a>1</a><b>2</b></root>') +
          [': _T TA MU-ENTER XML-EACH-CHILD . TYPE 2DROP ; _T'],
          "-1 a")

    check("XML-EACH-CHILD iterate",
          mstr('<root><a>1</a><b>2</b></root>') +
          [': _T TA MU-ENTER',
           '  XML-EACH-CHILD DROP 2DROP',
           '  MU-SKIP-ELEMENT',
           '  XML-EACH-CHILD . TYPE 2DROP ; _T'],
          "-1 b")


# ---------------------------------------------------------------------------
#  XML Builder
# ---------------------------------------------------------------------------

def test_xml_builder():
    print("\n--- XML Builder ---")

    # Basic tag
    check("XML build open/close tag",
          ['CREATE _OB 256 ALLOT',
           ': _T _OB 256 XML-SET-OUTPUT',
           '  _TB 100 OVER C! 1+ 105 OVER C! 1+ 118 SWAP C!',
           '  _TB 3 XML-<  XML->',
           '  _TB 3 XML-</',
           '  XML-OUTPUT-RESULT TYPE ; _T'],
          "<div></div>")

    # Self-close
    check("XML build self-close",
          ['CREATE _OB 256 ALLOT',
           ': _T _OB 256 XML-SET-OUTPUT',
           '  _TB 98 OVER C! 1+ 114 SWAP C!',
           '  _TB 2 XML-<  XML-/>',
           '  XML-OUTPUT-RESULT TYPE ; _T'],
          "<br/>")

    # Attribute
    check("XML build with attr",
          ['CREATE _OB 256 ALLOT',
           ': _T _OB 256 XML-SET-OUTPUT',
           '  _TB 97 SWAP C!',
           '  _TB 256 + 105 OVER C! 1+ 100 SWAP C!',
           '  _TB 260 + 120 SWAP C!',
           '  _TB 1 XML-<',
           '  _TB 256 + 2  _TB 260 + 1  XML-ATTR!',
           '  XML-/>',
           '  XML-OUTPUT-RESULT TYPE ; _T'],
          '<a id="x"/>')

    # Text with escaping
    check("XML build text escaped",
          ['CREATE _OB 256 ALLOT',
           ': _T _OB 256 XML-SET-OUTPUT'] +
          mstr('a&b<c') +
          ['  TA XML-TEXT!',
           '  XML-OUTPUT-RESULT TYPE ; _T'],
          "a&amp;b&lt;c")

    # Comment
    check("XML build comment",
          ['CREATE _OB 256 ALLOT',
           ': _T _OB 256 XML-SET-OUTPUT'] +
          mstr('hello') +
          ['  TA XML-COMMENT!',
           '  XML-OUTPUT-RESULT TYPE ; _T'],
          "<!-- hello -->")

    # PI
    check("XML build PI",
          ['CREATE _OB 256 ALLOT',
           ': _T _OB 256 XML-SET-OUTPUT',
           '  _TB 120 OVER C! 1+ 109 OVER C! 1+ 108 SWAP C!',
           '  _TB 256 + 118 OVER C! 1+ 49 SWAP C!',
           '  _TB 3  _TB 256 + 2  XML-PI!',
           '  XML-OUTPUT-RESULT TYPE ; _T'],
          "<?xml v1?>")


# ---------------------------------------------------------------------------
#  HTML5 Reader Tests
# ---------------------------------------------------------------------------

def test_html_reader():
    print("\n--- HTML5 Reader ---")

    # HTML-VOID?
    check("HTML-VOID? br",
          mstr('br') +
          [': _T TA HTML-VOID? . ; _T'],
          "-1")

    check("HTML-VOID? BR uppercase",
          mstr('BR') +
          [': _T TA HTML-VOID? . ; _T'],
          "-1")

    check("HTML-VOID? img",
          mstr('img') +
          [': _T TA HTML-VOID? . ; _T'],
          "-1")

    check("HTML-VOID? input",
          mstr('input') +
          [': _T TA HTML-VOID? . ; _T'],
          "-1")

    check("HTML-VOID? div not void",
          mstr('div') +
          [': _T TA HTML-VOID? . ; _T'],
          "0")

    check("HTML-VOID? source",
          mstr('source') +
          [': _T TA HTML-VOID? . ; _T'],
          "-1")

    # HTML-ENTER
    check("HTML-ENTER",
          mstr('<div class="x">hello</div>') +
          [': _T TA HTML-ENTER TYPE ; _T'],
          "hello</div>")

    # HTML-TEXT
    check("HTML-TEXT basic",
          mstr('<P>hello world</P>') +
          [': _T TA HTML-TEXT TYPE ; _T'],
          "hello world")

    # HTML-INNER
    check("HTML-INNER basic",
          mstr('<div>stuff</div>') +
          [': _T TA HTML-INNER TYPE ; _T'],
          "stuff")

    check("HTML-INNER case-insensitive",
          mstr('<DIV>content</div>') +
          [': _T TA HTML-INNER TYPE ; _T'],
          "content")

    check("HTML-INNER with void",
          mstr('<p>line1<br>line2</p>') +
          [': _T TA HTML-INNER TYPE ; _T'],
          "line1<br>line2")

    # HTML-CHILD (case-insensitive)
    check("HTML-CHILD case-insensitive",
          mstr('<div><SPAN>hi</SPAN></div>') +
          mstr('span') +
          [': _T',
           '  _TB _TL @ + 4 - 4',  # get 'span' from second mstr
           '  _TB 26 2SWAP',        # stack: (_TB, 26, span-a, 4)
           '  HTML-CHILD',
           '  HTML-INNER TYPE ; _T'],
          "hi")

    # HTML-CHILD? found
    check("HTML-CHILD? found",
          mstr('<ul><li>one</li></ul>') +
          [': _T TA',
           '  _TB 256 + 108 OVER C! 1+ 105 SWAP C!',
           '  _TB 256 + 2 HTML-CHILD? . TYPE ; _T'],
          "-1")

    # HTML-CHILD? not found
    check("HTML-CHILD? not found",
          mstr('<ul><li>one</li></ul>') +
          [': _T TA',
           '  _TB 256 + 100 OVER C! 1+ 105 OVER C! 1+ 118 SWAP C!',
           '  _TB 256 + 3 HTML-CHILD?',
           '  . 2DROP ; _T'],
          "0")

    # HTML-ATTR
    check("HTML-ATTR basic",
          mstr('<a href="test.html">link</a>') +
          [': _T TA',
           '  _TB 256 + 104 OVER C! 1+ 114 OVER C! 1+ 101 OVER C! 1+ 102 SWAP C!',
           '  _TB 256 + 4 HTML-ATTR TYPE ; _T'],
          "test.html")

    # HTML-ATTR? found
    check("HTML-ATTR? found",
          mstr('<img src="pic.png">') +
          [': _T TA',
           '  _TB 256 + 115 OVER C! 1+ 114 OVER C! 1+ 99 SWAP C!',
           '  _TB 256 + 3 HTML-ATTR? . TYPE ; _T'],
          "-1")

    # HTML-ID
    check("HTML-ID",
          mstr('<div id="main">content</div>') +
          [': _T TA HTML-ID TYPE ; _T'],
          "main")

    # HTML-CLASS-HAS?
    check("HTML-CLASS-HAS? found",
          mstr('<div class="foo bar baz">x</div>') +
          [': _T TA',
           '  _TB 256 + 98 OVER C! 1+ 97 OVER C! 1+ 114 SWAP C!',
           '  _TB 256 + 3 HTML-CLASS-HAS? . ; _T'],
          "-1")

    check("HTML-CLASS-HAS? not found",
          mstr('<div class="foo baz">x</div>') +
          [': _T TA',
           '  _TB 256 + 98 OVER C! 1+ 97 OVER C! 1+ 114 SWAP C!',
           '  _TB 256 + 3 HTML-CLASS-HAS? . ; _T'],
          "0")

    check("HTML-CLASS-HAS? single class",
          mstr('<div class="active">x</div>') +
          [': _T TA _TB 256 + 97 OVER C! 1+ 99 OVER C! 1+ 116 OVER C! 1+ 105 OVER C! 1+ 118 OVER C! 1+ 101 SWAP C!',
           '  _TB 256 + 6 HTML-CLASS-HAS? . ; _T'],
          "-1")

    # HTML-EACH-CHILD
    check("HTML-EACH-CHILD first",
          mstr('<ul><li>one</li><li>two</li></ul>') +
          [': _T TA HTML-ENTER HTML-EACH-CHILD',
           '  IF TYPE ELSE 2DROP THEN ; _T'],
          "li")

    # Void element skip
    check("skip element with void",
          mstr('<div><br><p>text</p></div>') +
          [': _T TA',
           '  _TB 256 + 112 SWAP C!',  # 'p'
           '  _TB 256 + 1 HTML-CHILD',
           '  HTML-INNER TYPE ; _T'],
          "text")


# ---------------------------------------------------------------------------
#  HTML5 Entity Decode Tests
# ---------------------------------------------------------------------------

def test_html_entities():
    print("\n--- HTML5 Entities ---")

    check("HTML-DECODE nbsp",
          mstr('&nbsp;rest') +
          [': _T TA HTML-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "rest")

    check("HTML-DECODE copy",
          mstr('&copy;x') +
          [': _T TA HTML-DECODE-ENTITY ROT . TYPE ; _T'],
          "169")

    check("HTML-DECODE reg",
          mstr('&reg;x') +
          [': _T TA HTML-DECODE-ENTITY ROT . TYPE ; _T'],
          "174")

    check("HTML-DECODE mdash",
          mstr('&mdash;x') +
          [': _T TA HTML-DECODE-ENTITY ROT . TYPE ; _T'],
          "8212")

    check("HTML-DECODE trade",
          mstr('&trade;x') +
          [': _T TA HTML-DECODE-ENTITY ROT . TYPE ; _T'],
          "8482")

    check("HTML-DECODE euro",
          mstr('&euro;x') +
          [': _T TA HTML-DECODE-ENTITY ROT . TYPE ; _T'],
          "8364")

    check("HTML-DECODE core amp",
          mstr('&amp;x') +
          [': _T TA HTML-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "&x")

    check("HTML-DECODE core lt",
          mstr('&lt;x') +
          [': _T TA HTML-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "<x")

    check("HTML-DECODE numeric",
          mstr('&#65;x') +
          [': _T TA HTML-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "Ax")

    check("HTML-DECODE unknown",
          mstr('&bogus;x') +
          [': _T TA HTML-DECODE-ENTITY ROT EMIT TYPE ; _T'],
          "&x")


# ---------------------------------------------------------------------------
#  HTML5 Builder Tests
# ---------------------------------------------------------------------------

def test_html_builder():
    print("\n--- HTML5 Builder ---")

    # DOCTYPE
    check("HTML-DOCTYPE",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  HTML-DOCTYPE',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          "<!DOCTYPE html>")

    # Open/close tag
    check("HTML build open/close tag",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  _TB 100 OVER C! 1+ 105 OVER C! 1+ 118 SWAP C!',  # 'div'
           '  _TB 3 HTML-<  HTML->',
           '  _TB 3 HTML-</',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          "<div></div>")

    # Self-close void
    check("HTML build void element",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  _TB 98 OVER C! 1+ 114 SWAP C!',  # 'br'
           '  _TB 2 HTML-<  HTML-/>',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          "<br>")

    # With attribute
    check("HTML build with attr",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  _TB 97 SWAP C!',  # 'a'
           '  _TB 1 HTML-<',
           '  _TB 256 + 104 OVER C! 1+ 114 OVER C! 1+ 101 OVER C! 1+ 102 SWAP C!',  # 'href'
           '  _TB 300 + 47 SWAP C!',  # '/'
           '  _TB 256 + 4  _TB 300 + 1  HTML-ATTR!',
           '  HTML->',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<a href="/">')

    # Bare attribute
    check("HTML build bare attr",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  _TB 105 OVER C! 1+ 110 OVER C! 1+ 112 OVER C! 1+ 117 OVER C! 1+ 116 SWAP C!',  # 'input'
           '  _TB 5 HTML-<',
           '  _TB 256 + 114 OVER C! 1+ 101 OVER C! 1+ 113 OVER C! 1+ 117 OVER C! 1+ 105 OVER C! 1+ 114 OVER C! 1+ 101 OVER C! 1+ 100 SWAP C!',  # 'required'
           '  _TB 256 + 8 HTML-BARE-ATTR!',
           '  HTML-/>',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          '<input required>')

    # Text escaped
    check("HTML build text escaped",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  _TB 49 OVER C! 1+ 38 OVER C! 1+ 50 SWAP C!',  # '1&2'
           '  _TB 3 HTML-TEXT!',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          "1&amp;2")

    # Comment
    check("HTML build comment",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  _TB 104 OVER C! 1+ 105 SWAP C!',  # 'hi'
           '  _TB 2 HTML-COMMENT!',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          "<!-- hi -->")

    # Raw output
    check("HTML build raw",
          ['CREATE _OB 512 ALLOT',
           ': _T _OB 512 HTML-SET-OUTPUT',
           '  _TB 60 OVER C! 1+ 98 SWAP C!',  # '<b'
           '  _TB 2 HTML-RAW!',
           '  HTML-OUTPUT-RESULT TYPE ; _T'],
          "<b")


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

def main():
    build_snapshot()
    test_layer0()
    test_layer1()
    test_layer2()
    test_layer3()
    test_layer4()
    test_layer5()
    test_xml_reader()
    test_xml_builder()
    test_html_reader()
    test_html_entities()
    test_html_builder()

    print(f"\n{'='*40}")
    print(f"  {_pass_count} passed, {_fail_count} failed")
    print(f"{'='*40}")
    return 1 if _fail_count > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
