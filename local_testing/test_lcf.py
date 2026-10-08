#!/usr/bin/env python3
"""Test suite for akashic-lcf (LCF reader/writer) Forth library.

Every check runs on a fresh native machine (native_forth.py) with KDOS and
lcf.f's closure loaded.
"""
from native_forth import NativeForth

# Test helper words
HELPERS = (
    'CREATE _TB 4096 ALLOT  VARIABLE _TL',
    ': TR  0 _TL ! ;',
    ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
    ': TA  ( -- addr u ) _TB _TL @ ;',
    'CREATE _UB 512 ALLOT',
    'CREATE _WB 4096 ALLOT',
)

SUITE = NativeForth(("liraq/lcf.f",), prelude=HELPERS)


def uart_text(raw):
    return "".join(
        chr(b) if (0x20 <= b < 0x7F or b in (10, 13, 9)) else ""
        for b in raw
    )


def run_forth(lines, max_steps=50_000_000):
    return uart_text(SUITE.run(lines, max_steps))


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


def check(name, forth_lines, expected=None, check_fn=None):
    output = run_forth(forth_lines)
    last = "\n".join(output.strip().split("\n")[-5:])
    if check_fn:
        assert check_fn(output), f"{name}: check failed, got:\n{last}"
    elif expected is not None:
        assert expected in output, f"{name}: expected {expected!r}, got:\n{last}"


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
