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
"""Test suite for akashic-lcf (LCF reader/writer) Forth library.

Uses the Megapad-64 emulator to boot KDOS, load dependencies, and run tests.
"""
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")
STR_F      = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
UTF8_F     = os.path.join(ROOT_DIR, "akashic", "text", "utf8.f")
TOML_F     = os.path.join(ROOT_DIR, "akashic", "utils", "toml.f")
JSON_F     = os.path.join(ROOT_DIR, "akashic", "utils", "json.f")
LCF_F      = os.path.join(ROOT_DIR, "akashic", "liraq", "lcf.f")

sys.path.insert(0, EMU_DIR)

from asm import assemble
from system import MegapadSystem

BIOS_PATH  = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH  = os.path.join(EMU_DIR, "kdos.f")

# ---------------------------------------------------------------------------
#  Emulator helpers (same pattern as test_toml.py)
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
    global _snapshot
    if _snapshot is not None:
        return _snapshot

    print("[*] Building snapshot: BIOS + KDOS + string + utf8 + toml + lcf ...")
    t0 = time.time()
    bios_code = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    str_lines  = _load_forth_lines(STR_F)
    utf8_lines = _load_forth_lines(UTF8_F)
    toml_lines = _load_forth_lines(TOML_F)
    json_lines = _load_forth_lines(JSON_F)
    lcf_lines  = _load_forth_lines(LCF_F)

    # Test helper words
    test_helpers = [
        'CREATE _TB 4096 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _UB 512 ALLOT',
        'CREATE _WB 4096 ALLOT',
    ]

    sys_obj = MegapadSystem(ram_size=1024 * 1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + str_lines + utf8_lines + toml_lines + json_lines
                 + lcf_lines + test_helpers)
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


def tstr(s):
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
            print(f"        expected: {expected!r}")
        last = clean.split('\n')[-5:]
        print(f"        got (last lines): {last}")


# ---------------------------------------------------------------------------
#  Sample LCF messages as TOML text
# ---------------------------------------------------------------------------

# A batch action message
BATCH_MSG = '''\
[action]
type = "batch"

[[batch]]
op = "set-state"
path = "navigation.active"
value = "systems"

[[batch]]
op = "set-attribute"
element-id = "title-label"
attribute = "text"
value = "Systems Overview"
'''

# A query action message
QUERY_MSG = '''\
[action]
type = "query"
method = "get-state"
path = "navigation.active"
'''

# An ok result message
OK_RESULT = '''\
[result]
status = "ok"
value = "systems"
'''

# An error result message
ERROR_RESULT = '''\
[result]
status = "error"
error = "element-not-found"
detail = "No element with id 'nav-panel'"
'''

# A handshake message with capabilities
HANDSHAKE_MSG = '''\
[action]
type = "handshake"

[capabilities]
version = "1.0"
queries = true
mutations = true
behaviors = false
surfaces = true
max-batch-size = 50
'''

# ---------------------------------------------------------------------------
#  Tests
# ---------------------------------------------------------------------------

def test_reader_action():
    """Reader: action inspection"""
    print("\n── Reader: Action Inspection ──\n")

    # LCF-ACTION?
    check("ACTION? on batch msg",
          tstr(BATCH_MSG) +
          [': _T TA LCF-ACTION? . ; _T'],
          "-1")

    check("ACTION? on result msg",
          tstr(OK_RESULT) +
          [': _T TA LCF-ACTION? . ; _T'],
          "0")

    # LCF-RESULT?
    check("RESULT? on ok result",
          tstr(OK_RESULT) +
          [': _T TA LCF-RESULT? . ; _T'],
          "-1")

    check("RESULT? on batch msg",
          tstr(BATCH_MSG) +
          [': _T TA LCF-RESULT? . ; _T'],
          "0")

    # LCF-ACTION-TYPE
    check("ACTION-TYPE batch",
          tstr(BATCH_MSG) +
          [': _T TA LCF-ACTION-TYPE TYPE ; _T'],
          "batch")

    check("ACTION-TYPE query",
          tstr(QUERY_MSG) +
          [': _T TA LCF-ACTION-TYPE TYPE ; _T'],
          "query")

    check("ACTION-TYPE handshake",
          tstr(HANDSHAKE_MSG) +
          [': _T TA LCF-ACTION-TYPE TYPE ; _T'],
          "handshake")


def test_reader_result():
    """Reader: result inspection"""
    print("\n── Reader: Result Inspection ──\n")

    # LCF-RESULT-STATUS
    check("RESULT-STATUS ok",
          tstr(OK_RESULT) +
          [': _T TA LCF-RESULT-STATUS TYPE ; _T'],
          "ok")

    check("RESULT-STATUS error",
          tstr(ERROR_RESULT) +
          [': _T TA LCF-RESULT-STATUS TYPE ; _T'],
          "error")

    # LCF-RESULT-OK?
    check("RESULT-OK? true",
          tstr(OK_RESULT) +
          [': _T TA LCF-RESULT-OK? . ; _T'],
          "-1")

    check("RESULT-OK? false",
          tstr(ERROR_RESULT) +
          [': _T TA LCF-RESULT-OK? . ; _T'],
          "0")

    # LCF-RESULT-ERROR
    check("RESULT-ERROR",
          tstr(ERROR_RESULT) +
          [': _T TA LCF-RESULT-ERROR TYPE ; _T'],
          "element-not-found")

    # LCF-RESULT-DETAIL
    check("RESULT-DETAIL",
          tstr(ERROR_RESULT) +
          [': _T TA LCF-RESULT-DETAIL TYPE ; _T'],
          "No element with id")


def test_reader_batch():
    """Reader: batch access"""
    print("\n── Reader: Batch Access ──\n")

    # LCF-BATCH-NTH + LCF-BATCH-OP
    check("BATCH entry 0 op",
          tstr(BATCH_MSG) +
          [': _T TA 0 LCF-BATCH-NTH',
           'S" op" TOML-KEY TOML-GET-STRING TYPE ; _T'],
          "set-state")

    check("BATCH entry 1 op",
          tstr(BATCH_MSG) +
          [': _T TA 1 LCF-BATCH-NTH',
           'S" op" TOML-KEY TOML-GET-STRING TYPE ; _T'],
          "set-attribute")

    # LCF-BATCH-OP shortcut
    check("BATCH-OP entry 0",
          tstr(BATCH_MSG) +
          [': _T TA 0 LCF-BATCH-NTH LCF-BATCH-OP TYPE ; _T'],
          "set-state")

    # Batch entry fields
    check("BATCH entry 0 path",
          tstr(BATCH_MSG) +
          [': _T TA 0 LCF-BATCH-NTH',
           'S" path" LCF-ENTRY-STRING TYPE ; _T'],
          "navigation.active")

    check("BATCH entry 0 value",
          tstr(BATCH_MSG) +
          [': _T TA 0 LCF-BATCH-NTH',
           'S" value" LCF-ENTRY-STRING TYPE ; _T'],
          "systems")

    check("BATCH entry 1 element-id",
          tstr(BATCH_MSG) +
          [': _T TA 1 LCF-BATCH-NTH',
           'S" element-id" LCF-ENTRY-STRING TYPE ; _T'],
          "title-label")

    check("BATCH entry 1 value",
          tstr(BATCH_MSG) +
          [': _T TA 1 LCF-BATCH-NTH',
           'S" value" LCF-ENTRY-STRING TYPE ; _T'],
          "Systems Overview")

    # LCF-BATCH-COUNT
    check("BATCH-COUNT",
          tstr(BATCH_MSG) +
          [': _T TA LCF-BATCH-COUNT . ; _T'],
          "2")


def test_reader_query():
    """Reader: query access"""
    print("\n── Reader: Query Access ──\n")

    check("QUERY-METHOD",
          tstr(QUERY_MSG) +
          [': _T TA LCF-QUERY-METHOD TYPE ; _T'],
          "get-state")

    check("QUERY-PATH",
          tstr(QUERY_MSG) +
          [': _T TA LCF-QUERY-PATH TYPE ; _T'],
          "navigation.active")


def test_reader_capabilities():
    """Reader: capability access"""
    print("\n── Reader: Capabilities ──\n")

    check("CAP-VERSION",
          tstr(HANDSHAKE_MSG) +
          [': _T TA LCF-CAP-VERSION TYPE ; _T'],
          "1.0")

    check("CAP queries = true",
          tstr(HANDSHAKE_MSG) +
          [': _T TA S" queries" LCF-CAP-BOOL . ; _T'],
          "-1")

    check("CAP behaviors = false",
          tstr(HANDSHAKE_MSG) +
          [': _T TA S" behaviors" LCF-CAP-BOOL . ; _T'],
          "0")

    check("CAP max-batch-size = 50",
          tstr(HANDSHAKE_MSG) +
          [': _T TA S" max-batch-size" LCF-CAP-INT . ; _T'],
          "50")


def test_validation():
    """Validation"""
    print("\n── Validation ──\n")

    # Valid keys
    check("VALID-KEY? kebab",
          [': _T S" element-id" LCF-VALID-KEY? . ; _T'],
          "-1")

    check("VALID-KEY? bare",
          [': _T S" status" LCF-VALID-KEY? . ; _T'],
          "-1")

    check("VALID-KEY? with digits",
          [': _T S" level-2" LCF-VALID-KEY? . ; _T'],
          "-1")

    # Invalid keys
    check("VALID-KEY? uppercase",
          [': _T S" Status" LCF-VALID-KEY? . ; _T'],
          "0")

    check("VALID-KEY? underscore",
          [': _T S" my_key" LCF-VALID-KEY? . ; _T'],
          "0")

    check("VALID-KEY? empty",
          [': _T S" " DROP 0 LCF-VALID-KEY? . ; _T'],
          "0")

    # LCF-VALIDATE
    check("VALIDATE batch msg",
          tstr(BATCH_MSG) +
          [': _T TA LCF-VALIDATE . ; _T'],
          "-1")

    check("VALIDATE ok result",
          tstr(OK_RESULT) +
          [': _T TA LCF-VALIDATE . ; _T'],
          "-1")

    check("VALIDATE no header",
          tstr('key = "value"\n') +
          [': _T TA LCF-VALIDATE . ; _T'],
          "0")


def test_writer_kv():
    """Writer: key-value emission"""
    print("\n── Writer: Key-Value Emission ──\n")

    # LCF-W-KV-STR
    check("W-KV-STR",
          [': _T _WB 4096 LCF-W-INIT',
           'S" status" S" ok" LCF-W-KV-STR',
           'LCF-W-STR TYPE ; _T'],
          'status = "ok"')

    # LCF-W-KV-INT positive
    check("W-KV-INT positive",
          [': _T _WB 4096 LCF-W-INIT',
           'S" count" 42 LCF-W-KV-INT',
           'LCF-W-STR TYPE ; _T'],
          'count = 42')

    # LCF-W-KV-INT zero
    check("W-KV-INT zero",
          [': _T _WB 4096 LCF-W-INIT',
           'S" n" 0 LCF-W-KV-INT',
           'LCF-W-STR TYPE ; _T'],
          'n = 0')

    # LCF-W-KV-INT negative
    check("W-KV-INT negative",
          [': _T _WB 4096 LCF-W-INIT',
           'S" offset" -17 LCF-W-KV-INT',
           'LCF-W-STR TYPE ; _T'],
          'offset = -17')

    # LCF-W-KV-BOOL true
    check("W-KV-BOOL true",
          [': _T _WB 4096 LCF-W-INIT',
           'S" enabled" -1 LCF-W-KV-BOOL',
           'LCF-W-STR TYPE ; _T'],
          'enabled = true')

    # LCF-W-KV-BOOL false
    check("W-KV-BOOL false",
          [': _T _WB 4096 LCF-W-INIT',
           'S" debug" 0 LCF-W-KV-BOOL',
           'LCF-W-STR TYPE ; _T'],
          'debug = false')


def test_writer_tables():
    """Writer: table headers"""
    print("\n── Writer: Table Headers ──\n")

    check("W-TABLE",
          [': _T _WB 4096 LCF-W-INIT',
           'S" action" LCF-W-TABLE',
           'LCF-W-STR TYPE ; _T'],
          '[action]')

    check("W-ATABLE",
          [': _T _WB 4096 LCF-W-INIT',
           'S" batch" LCF-W-ATABLE',
           'LCF-W-STR TYPE ; _T'],
          '[[batch]]')


def test_writer_ok():
    """Writer: complete OK response"""
    print("\n── Writer: Complete Messages ──\n")

    # LCF-W-OK
    check("W-OK",
          [': _T _WB 4096 LCF-W-OK . ; _T'],
          "23")

    # Verify output is valid TOML parseable by our reader
    check("W-OK roundtrip",
          [': _T _WB 4096 LCF-W-OK',
           '_WB SWAP LCF-RESULT-OK? . ; _T'],
          "-1")


def test_writer_error():
    """Writer: complete error response"""
    print("\n── Writer: Error Response ──\n")

    check("W-ERROR roundtrip status",
          [': _T _WB 4096',
           'S" not-found" S" No such element"',
           'LCF-W-ERROR DROP',
           '_WB LCF-W-LEN LCF-RESULT-STATUS TYPE ; _T'],
          "error")

    check("W-ERROR roundtrip error field",
          [': _T _WB 4096',
           'S" not-found" S" No such element"',
           'LCF-W-ERROR DROP',
           '_WB LCF-W-LEN LCF-RESULT-ERROR TYPE ; _T'],
          "not-found")

    check("W-ERROR roundtrip detail field",
          [': _T _WB 4096',
           'S" not-found" S" No such element"',
           'LCF-W-ERROR DROP',
           '_WB LCF-W-LEN LCF-RESULT-DETAIL TYPE ; _T'],
          "No such element")


def test_writer_value_result():
    """Writer: value result"""
    print("\n── Writer: Value Result ──\n")

    check("W-VALUE-RESULT roundtrip",
          [': _T _WB 4096 S" systems" LCF-W-VALUE-RESULT DROP',
           '_WB LCF-W-LEN',
           'S" result" TOML-FIND-TABLE',
           'S" value" TOML-KEY TOML-GET-STRING TYPE ; _T'],
          "systems")

    check("W-INT-RESULT roundtrip",
          [': _T _WB 4096 99 LCF-W-INT-RESULT DROP',
           '_WB LCF-W-LEN',
           'S" result" TOML-FIND-TABLE',
           'S" value" TOML-KEY TOML-GET-INT . ; _T'],
          "99")


def test_writer_multi_kv():
    """Writer: multiple key-value pairs"""
    print("\n── Writer: Multi KV ──\n")

    check("W multi-field message",
          [': _T _WB 4096 LCF-W-INIT',
           'S" action" LCF-W-TABLE',
           'S" type" S" batch" LCF-W-KV-STR',
           'LCF-W-NL',
           'S" batch" LCF-W-ATABLE',
           'S" op" S" set-state" LCF-W-KV-STR',
           'S" path" S" nav.active" LCF-W-KV-STR',
           'S" value" S" home" LCF-W-KV-STR',
           'LCF-W-STR TYPE ; _T'],
          check_fn=lambda o: '[action]' in o and '[[batch]]' in o
                             and 'set-state' in o and 'nav.active' in o)

    # Roundtrip: write, then read back
    check("W multi-field roundtrip action-type",
          [': _T _WB 4096 LCF-W-INIT',
           'S" action" LCF-W-TABLE',
           'S" type" S" batch" LCF-W-KV-STR',
           'LCF-W-NL',
           'S" batch" LCF-W-ATABLE',
           'S" op" S" set-state" LCF-W-KV-STR',
           '_WB LCF-W-LEN LCF-ACTION-TYPE TYPE ; _T'],
          "batch")

    check("W multi-field roundtrip batch op",
          [': _T _WB 4096 LCF-W-INIT',
           'S" action" LCF-W-TABLE',
           'S" type" S" batch" LCF-W-KV-STR',
           'LCF-W-NL',
           'S" batch" LCF-W-ATABLE',
           'S" op" S" set-state" LCF-W-KV-STR',
           'S" path" S" nav.active" LCF-W-KV-STR',
           '_WB LCF-W-LEN 0 LCF-BATCH-NTH',
           'LCF-BATCH-OP TYPE ; _T'],
          "set-state")


def test_writer_int_edge():
    """Writer: integer edge cases"""
    print("\n── Writer: Integer Edge Cases ──\n")

    check("W-KV-INT large",
          [': _T _WB 4096 LCF-W-INIT',
           'S" big" 65536 LCF-W-KV-INT',
           'LCF-W-STR TYPE ; _T'],
          'big = 65536')

    check("W-KV-INT 1",
          [': _T _WB 4096 LCF-W-INIT',
           'S" x" 1 LCF-W-KV-INT',
           'LCF-W-STR TYPE ; _T'],
          'x = 1')

    check("W-KV-INT -1",
          [': _T _WB 4096 LCF-W-INIT',
           'S" x" -1 LCF-W-KV-INT',
           'LCF-W-STR TYPE ; _T'],
          'x = -1')

    check("W-KV-INT 100",
          [': _T _WB 4096 LCF-W-INIT',
           'S" n" 100 LCF-W-KV-INT',
           'LCF-W-STR TYPE ; _T'],
          'n = 100')


# ---------------------------------------------------------------------------
#  JSON-format sample messages
# ---------------------------------------------------------------------------

JSON_ACTION = '{"action":{"type":"batch"},"batch":[{"op":"set-state","path":"navigation.active","value":"systems"},{"op":"set-attribute","element-id":"title-label","attribute":"text","value":"Systems Overview"}]}'

JSON_RESULT_OK = '{"result":{"status":"ok","value":"systems"}}'

JSON_RESULT_ERR = '{"result":{"status":"error","error":"element-not-found","detail":"No element with id nav-panel"}}'

JSON_HANDSHAKE = '{"action":{"type":"handshake"},"capabilities":{"version":"1.0","queries":true,"mutations":true,"behaviors":false,"surfaces":true,"max-batch-size":50}}'

# Notification messages (TOML)
NOTIFY_EVENT = '''\
[notification]
type = "event"
path = "ui.button-click"
value = "save-btn"
'''

NOTIFY_STATE = '''\
[notification]
type = "state-change"
path = "navigation.active"
value = "settings"
'''

NOTIFY_SURFACE = '''\
[notification]
type = "surface-change"
path = "display.resolution"
value = "1920x1080"
'''

NOTIFY_ERROR = '''\
[notification]
type = "error"
path = "network.connection"
value = "timeout"
'''

# Session result with session-id
SESSION_RESULT = '''\
[result]
status = "ok"
session-id = "sess-abc-123"
'''

JSON_SESSION_RESULT = '{"result":{"status":"ok","session-id":"sess-abc-123"}}'

# ---------------------------------------------------------------------------
#  Gap 5.1 tests — JSON backend
# ---------------------------------------------------------------------------

def test_json_reader():
    """JSON backend: reader dispatches transparently"""
    print("\n── JSON Reader ──\n")

    check("JSON ACTION?",
          tstr(JSON_ACTION) +
          [': _T TA LCF-ACTION? . ; _T'],
          "-1")

    check("JSON RESULT? on action msg",
          tstr(JSON_ACTION) +
          [': _T TA LCF-RESULT? . ; _T'],
          "0")

    check("JSON ACTION-TYPE",
          tstr(JSON_ACTION) +
          [': _T TA LCF-ACTION-TYPE TYPE ; _T'],
          "batch")

    check("JSON RESULT-STATUS ok",
          tstr(JSON_RESULT_OK) +
          [': _T TA LCF-RESULT-STATUS TYPE ; _T'],
          "ok")

    check("JSON RESULT-OK?",
          tstr(JSON_RESULT_OK) +
          [': _T TA LCF-RESULT-OK? . ; _T'],
          "-1")

    check("JSON RESULT-ERROR",
          tstr(JSON_RESULT_ERR) +
          [': _T TA LCF-RESULT-ERROR TYPE ; _T'],
          "element-not-found")

    check("JSON BATCH-COUNT",
          tstr(JSON_ACTION) +
          [': _T TA LCF-BATCH-COUNT . ; _T'],
          "2")

    check("JSON BATCH-OP entry 0",
          tstr(JSON_ACTION) +
          [': _T TA 0 LCF-BATCH-NTH LCF-BATCH-OP TYPE ; _T'],
          "set-state")

    check("JSON BATCH entry 1 value",
          tstr(JSON_ACTION) +
          [': _T TA 1 LCF-BATCH-NTH',
           'S" value" LCF-ENTRY-STRING TYPE ; _T'],
          "Systems Overview")

    check("JSON CAP-VERSION",
          tstr(JSON_HANDSHAKE) +
          [': _T TA LCF-CAP-VERSION TYPE ; _T'],
          "1.0")

    check("JSON CAP-BOOL queries",
          tstr(JSON_HANDSHAKE) +
          [': _T TA S" queries" LCF-CAP-BOOL . ; _T'],
          "-1")

    check("JSON CAP-INT max-batch-size",
          tstr(JSON_HANDSHAKE) +
          [': _T TA S" max-batch-size" LCF-CAP-INT . ; _T'],
          "50")

    check("JSON VALIDATE",
          tstr(JSON_ACTION) +
          [': _T TA LCF-VALIDATE . ; _T'],
          "-1")


def test_json_writer():
    """JSON backend: writer produces JSON when LCF-FORMAT is JSON"""
    print("\n── JSON Writer ──\n")

    check("JSON W-OK",
          [': _T LCF-FMT-JSON LCF-FORMAT !',
           '_WB 4096 LCF-W-OK DROP',
           'LCF-W-STR TYPE',
           'LCF-FMT-TOML LCF-FORMAT ! ; _T'],
          check_fn=lambda o: '"status":"ok"' in o.replace(' ', ''))

    check("JSON W-OK roundtrip",
          [': _T LCF-FMT-JSON LCF-FORMAT !',
           '_WB 4096 LCF-W-OK DROP',
           '_WB LCF-W-LEN LCF-RESULT-OK? .',
           'LCF-FMT-TOML LCF-FORMAT ! ; _T'],
          "-1")

    check("JSON W-ERROR roundtrip",
          [': _T LCF-FMT-JSON LCF-FORMAT !',
           '_WB 4096 S" not-found" S" No such element" LCF-W-ERROR DROP',
           '_WB LCF-W-LEN LCF-RESULT-ERROR TYPE',
           'LCF-FMT-TOML LCF-FORMAT ! ; _T'],
          "not-found")

    check("JSON W-VALUE-RESULT roundtrip",
          [': _T LCF-FMT-JSON LCF-FORMAT !',
           '_WB 4096 S" hello" LCF-W-VALUE-RESULT DROP',
           '_WB LCF-W-LEN',
           'LCF-RESULT-OK? .',
           'LCF-FMT-TOML LCF-FORMAT ! ; _T'],
          "-1")

    check("JSON W-INT-RESULT roundtrip",
          [': _T LCF-FMT-JSON LCF-FORMAT !',
           '_WB 4096 42 LCF-W-INT-RESULT DROP',
           '_WB LCF-W-LEN',
           'LCF-RESULT-OK? .',
           'LCF-FMT-TOML LCF-FORMAT ! ; _T'],
          "-1")


def test_auto_detect():
    """JSON/TOML auto-detect"""
    print("\n── Auto-Detect ──\n")

    check("Auto-detect TOML",
          tstr(BATCH_MSG) +
          [': _T TA LCF-ACTION-TYPE TYPE ; _T'],
          "batch")

    check("Auto-detect JSON",
          tstr(JSON_ACTION) +
          [': _T TA LCF-ACTION-TYPE TYPE ; _T'],
          "batch")

    check("TOML/JSON equivalence: RESULT-STATUS",
          tstr(OK_RESULT) +
          [': _T TA LCF-RESULT-STATUS TYPE ; _T'],
          "ok")

    check("Format switch: TOML then JSON write",
          [': _T LCF-FMT-TOML LCF-FORMAT !',
           '_WB 4096 LCF-W-OK DROP',
           '_WB LCF-W-LEN LCF-RESULT-OK? .',
           'LCF-FMT-JSON LCF-FORMAT !',
           '_UB 512 LCF-W-OK DROP',
           '_UB LCF-W-LEN LCF-RESULT-OK? .',
           'LCF-FMT-TOML LCF-FORMAT ! ; _T'],
          check_fn=lambda o: '-1 -1' in o)


# ---------------------------------------------------------------------------
#  Gap 5.2 tests — Notification messages
# ---------------------------------------------------------------------------

def test_notifications():
    """Notification reader/writer"""
    print("\n── Notifications ──\n")

    check("NOTIFICATION? event",
          tstr(NOTIFY_EVENT) +
          [': _T TA LCF-NOTIFICATION? . ; _T'],
          "-1")

    check("NOTIFICATION? on action msg",
          tstr(BATCH_MSG) +
          [': _T TA LCF-NOTIFICATION? . ; _T'],
          "0")

    check("NOTIFY-TYPE event",
          tstr(NOTIFY_EVENT) +
          [': _T TA LCF-NOTIFY-TYPE TYPE ; _T'],
          "event")

    check("NOTIFY-TYPE state-change",
          tstr(NOTIFY_STATE) +
          [': _T TA LCF-NOTIFY-TYPE TYPE ; _T'],
          "state-change")

    check("NOTIFY-TYPE surface-change",
          tstr(NOTIFY_SURFACE) +
          [': _T TA LCF-NOTIFY-TYPE TYPE ; _T'],
          "surface-change")

    check("NOTIFY-TYPE error",
          tstr(NOTIFY_ERROR) +
          [': _T TA LCF-NOTIFY-TYPE TYPE ; _T'],
          "error")

    check("NOTIFY-PATH",
          tstr(NOTIFY_STATE) +
          [': _T TA LCF-NOTIFY-PATH TYPE ; _T'],
          "navigation.active")

    check("NOTIFY-VALUE",
          tstr(NOTIFY_STATE) +
          [': _T TA LCF-NOTIFY-VALUE TYPE ; _T'],
          "settings")

    check("W-NOTIFICATION roundtrip type",
          [': _T _WB 4096',
           'S" event" S" ui.click" S" save-btn"',
           'LCF-W-NOTIFICATION DROP',
           '_WB LCF-W-LEN LCF-NOTIFY-TYPE TYPE ; _T'],
          "event")

    check("W-NOTIFICATION roundtrip path",
          [': _T _WB 4096',
           'S" event" S" ui.click" S" save-btn"',
           'LCF-W-NOTIFICATION DROP',
           '_WB LCF-W-LEN LCF-NOTIFY-PATH TYPE ; _T'],
          "ui.click")

    check("VALIDATE accepts notification",
          tstr(NOTIFY_EVENT) +
          [': _T TA LCF-VALIDATE . ; _T'],
          "-1")


# ---------------------------------------------------------------------------
#  Gap 5.3 tests — Handshake / session
# ---------------------------------------------------------------------------

def test_handshake():
    """Handshake / session"""
    print("\n── Handshake / Session ──\n")

    check("W-HANDSHAKE roundtrip action-type",
          [': _T _WB 4096',
           '11 S" 1.0" LCF-W-HANDSHAKE DROP',
           '_WB LCF-W-LEN LCF-ACTION-TYPE TYPE ; _T'],
          "handshake")

    check("W-HANDSHAKE cap version",
          [': _T _WB 4096',
           '11 S" 1.0" LCF-W-HANDSHAKE DROP',
           '_WB LCF-W-LEN LCF-CAP-VERSION TYPE ; _T'],
          "1.0")

    check("W-HANDSHAKE cap queries",
          [': _T _WB 4096',
           '11 S" 1.0" LCF-W-HANDSHAKE DROP',
           '_WB LCF-W-LEN S" queries" LCF-CAP-BOOL . ; _T'],
          "-1")

    check("HANDSHAKE? true",
          tstr(HANDSHAKE_MSG) +
          [': _T TA LCF-HANDSHAKE? . ; _T'],
          "-1")

    check("HANDSHAKE? false on query",
          tstr(QUERY_MSG) +
          [': _T TA LCF-HANDSHAKE? . ; _T'],
          "0")

    check("SESSION-ID TOML",
          tstr(SESSION_RESULT) +
          [': _T TA LCF-SESSION-ID TYPE ; _T'],
          "sess-abc-123")

    check("SESSION-ID JSON",
          tstr(JSON_SESSION_RESULT) +
          [': _T TA LCF-SESSION-ID TYPE ; _T'],
          "sess-abc-123")


# ---------------------------------------------------------------------------
#  Gap 5.4 tests — Operation vocabulary
# ---------------------------------------------------------------------------

def test_operations():
    """Operation vocabulary"""
    print("\n── Operation Vocabulary ──\n")

    check("OP-VALID? query",
          [': _T S" query" LCF-OP-VALID? . ; _T'],
          "-1")

    check("OP-VALID? set-state",
          [': _T S" set-state" LCF-OP-VALID? . ; _T'],
          "-1")

    check("OP-VALID? subscribe",
          [': _T S" subscribe" LCF-OP-VALID? . ; _T'],
          "-1")

    check("OP-VALID? create",
          [': _T S" create" LCF-OP-VALID? . ; _T'],
          "-1")

    check("OP-VALID? invalid",
          [': _T S" foobar" LCF-OP-VALID? . ; _T'],
          "0")

    check("OP-VALID? empty",
          [': _T S" " DROP 0 LCF-OP-VALID? . ; _T'],
          "0")

    check("OP-COUNT",
          [': _T LCF-OP-COUNT . ; _T'],
          "24")

    check("OP-NTH 0 = close",
          [': _T 0 LCF-OP-NTH IF TYPE ELSE 2DROP THEN ; _T'],
          "close")

    check("OP-NTH 23 = write",
          [': _T 23 LCF-OP-NTH IF TYPE ELSE 2DROP THEN ; _T'],
          "write")

    check("OP-NTH 24 = invalid",
          [': _T 24 LCF-OP-NTH . 2DROP ; _T'],
          "0")


# ---------------------------------------------------------------------------
#  Main
# ---------------------------------------------------------------------------

if __name__ == '__main__':
    build_snapshot()

    test_reader_action()
    test_reader_result()
    test_reader_batch()
    test_reader_query()
    test_reader_capabilities()
    test_validation()
    test_writer_kv()
    test_writer_tables()
    test_writer_ok()
    test_writer_error()
    test_writer_value_result()
    test_writer_multi_kv()
    test_writer_int_edge()
    test_json_reader()
    test_json_writer()
    test_auto_detect()
    test_notifications()
    test_handshake()
    test_operations()

    total = _pass_count + _fail_count
    print(f"\n{'='*60}")
    print(f"  {_pass_count} passed, {_fail_count} failed ({total} total)")
    print(f"{'='*60}")
    sys.exit(1 if _fail_count else 0)
