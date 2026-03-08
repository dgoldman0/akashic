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
"""Test suite for akashic AT Protocol: xrpc.f, session.f, repo.f.

Structural tests — verifying compilation, URL construction,
cursor management, JSON building, and session state.
Network calls (HTTP-GET/POST) cannot be tested without a live PDS,
so we test everything up to the point of the actual HTTP call.
"""
import os, sys, time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Library files in load order
STRING_F   = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
JSON_F     = os.path.join(ROOT_DIR, "akashic", "utils", "json.f")
URL_F      = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HEADERS_F  = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
HTTP_F     = os.path.join(ROOT_DIR, "akashic", "net", "http.f")
URI_F      = os.path.join(ROOT_DIR, "akashic", "net", "uri.f")
ATURI_F    = os.path.join(ROOT_DIR, "akashic", "atproto", "aturi.f")
DID_F      = os.path.join(ROOT_DIR, "akashic", "atproto", "did.f")
TID_F      = os.path.join(ROOT_DIR, "akashic", "atproto", "tid.f")
XRPC_F     = os.path.join(ROOT_DIR, "akashic", "atproto", "xrpc.f")
SESSION_F  = os.path.join(ROOT_DIR, "akashic", "atproto", "session.f")
REPO_F     = os.path.join(ROOT_DIR, "akashic", "atproto", "repo.f")

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
    libs = [
        ("string.f",  STRING_F),
        ("json.f",    JSON_F),
        ("url.f",     URL_F),
        ("headers.f", HEADERS_F),
        ("http.f",    HTTP_F),
        ("uri.f",     URI_F),
        ("aturi.f",   ATURI_F),
        ("did.f",     DID_F),
        ("tid.f",     TID_F),
        ("xrpc.f",    XRPC_F),
        ("session.f", SESSION_F),
        ("repo.f",    REPO_F),
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
        'CREATE _BUF 512 ALLOT',
        'CREATE _BUF2 512 ALLOT',
        # JSON-string builder helpers (same pattern as test_json.py)
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': .S$  ( addr len -- )',
        '  0 ?DO DUP I + C@ EMIT LOOP DROP ;',
    ]
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()
    payload = "\n".join(kdos_lines + ["ENTER-USERLAND"]
                        + all_lib_lines + helpers) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 800_000_000
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
    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.cpu.mem[:len(mem_bytes)] = mem_bytes
    sys_obj._ext_mem[:len(ext_mem_bytes)] = ext_mem_bytes
    restore_cpu_state(sys_obj.cpu, cpu_state)
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
        if sp == -1: sp = 70
        lines.append(full[:sp])
        full = full[sp:].lstrip()
    if full: lines.append(full)
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
        print(f"  FAIL  {name}")
        if expected: print(f"        expected: {expected!r}")
        print(f"        got (last lines): {clean.split(chr(10))[-3:]}")
        _fail += 1

# ── Edge Case Test Functions ──

def test_xrpc_accept_header():
    """Test the interpret-mode S" fix for XRPC Accept header."""
    print("\n── XRPC: Accept Header Fix ──\n")

    # Accept header should be set to application/json by default
    check("XRPC default accept = application/json",
          [': _T _HTTP-ACCEPT _HTTP-ACCEPT-LEN @ TYPE ; _T'],
          "application/json")

    check("XRPC accept length = 16",
          [': _T _HTTP-ACCEPT-LEN @ . ; _T'],
          "16 ")

    # Accept header persists after host change
    check("accept persists after set-host",
          [': _T S" my.pds.example" XRPC-SET-HOST',
           '_HTTP-ACCEPT _HTTP-ACCEPT-LEN @ TYPE ; _T'],
          "application/json")

    # Accept header appears in assembled headers
    check("accept in header build",
          [': _T HTTP-CLEAR-BEARER 0 _HTTP-UA-LEN !',
           'S" application/json" HTTP-SET-ACCEPT',
           'HDR-RESET S" /xrpc/test" HDR-GET HTTP-APPLY-SESSION HDR-END',
           'HDR-RESULT TYPE ; _T'],
          "Accept: application/json")


def test_xrpc_url_edge_cases():
    """Edge cases for XRPC URL building."""
    print("\n── XRPC: URL Edge Cases ──\n")

    # Very long NSID
    long_nsid = "com.atproto.admin.searchAccounts"
    check("URL with long NSID",
          [f': _T S" {long_nsid}" 0 0 2SWAP _XRPC-BUILD-URL _XRPC-APPEND-PARAMS',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          f"https://bsky.social/xrpc/{long_nsid}")

    # Params with special characters
    check("URL with encoded params",
          [': _T S" app.bsky.actor.getProfile" _XRPC-BUILD-URL',
           'S" actor=did:plc:abc123" _XRPC-APPEND-PARAMS',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          "https://bsky.social/xrpc/app.bsky.actor.getProfile?actor=did:plc:abc123")

    # Multiple params
    check("URL with multiple params",
          [': _T S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           'S" limit=50&cursor=abc" _XRPC-APPEND-PARAMS',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=50&cursor=abc")

    # Empty NSID (degenerate but should not crash)
    check("URL with empty NSID",
          [': _T S" " _XRPC-BUILD-URL',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          "https://bsky.social/xrpc/")

    # Custom host in URL
    check("URL with custom host",
          [': _T S" pds.example.com" XRPC-SET-HOST',
           'S" com.atproto.sync.getBlob" _XRPC-BUILD-URL',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          "https://pds.example.com/xrpc/com.atproto.sync.getBlob")

    # Reset back to default host
    check("URL reset default host",
          [': _T _XRPC-DEFAULT-HOST',
           'S" app.bsky.actor.getProfile" _XRPC-BUILD-URL',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          "https://bsky.social/xrpc/app.bsky.actor.getProfile")


def test_xrpc_cursor_edge_cases():
    """Edge cases for cursor management."""
    print("\n── XRPC: Cursor Edge Cases ──\n")

    # Cursor at max length (127)
    long_cursor = "C" * 127
    check("cursor max length 127",
          tstr(long_cursor) +
          [': _T TA XRPC-SET-CURSOR XRPC-CURSOR-LEN @ . ; _T'],
          "127 ")

    # Cursor over max length (128) — should be rejected
    over_cursor = "D" * 128
    check("cursor 128 rejected",
          tstr(over_cursor) +
          [': _T XRPC-CLEAR-CURSOR TA XRPC-SET-CURSOR XRPC-CURSOR-LEN @ . ; _T'],
          "0 ")

    # Cursor with special characters
    check("cursor with special chars",
          [': _T S" bafyr+abc/123==" XRPC-SET-CURSOR',
           'XRPC-CURSOR XRPC-CURSOR-LEN @ TYPE ; _T'],
          "bafyr+abc/123==")

    # Set cursor, clear, verify gone
    check("set then clear cursor",
          [': _T S" mycursor" XRPC-SET-CURSOR',
           'XRPC-HAS-CURSOR? IF 1 ELSE 0 THEN .',
           'XRPC-CLEAR-CURSOR',
           'XRPC-HAS-CURSOR? IF 1 ELSE 0 THEN . ; _T'],
          "1 0 ")

    # Overwrite cursor
    check("overwrite cursor",
          [': _T S" first" XRPC-SET-CURSOR',
           'S" second" XRPC-SET-CURSOR',
           'XRPC-CURSOR XRPC-CURSOR-LEN @ TYPE ; _T'],
          "second")

    # Cursor appended to URL with existing params
    check("cursor + params ordering",
          [': _T S" page2" XRPC-SET-CURSOR',
           'S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           'S" limit=25" _XRPC-APPEND-PARAMS',
           '_XRPC-APPEND-CURSOR',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=25&cursor=page2")

    # Cursor appended to URL without params (should use ?)
    check("cursor no params uses ?",
          [': _T S" cursor1" XRPC-SET-CURSOR',
           'S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           'S" " _XRPC-APPEND-PARAMS',
           '_XRPC-APPEND-CURSOR',
           '_XR-URL _XR-POS @ TYPE ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline?cursor=cursor1")

    # Clean up cursor state
    check("clean cursor state",
          [': _T XRPC-CLEAR-CURSOR _XRPC-DEFAULT-HOST 1 . ; _T'],
          "1 ")


def test_xrpc_extract_cursor_edge_cases():
    """Edge cases for cursor extraction from JSON."""
    print("\n── XRPC: Extract Cursor Edge Cases ──\n")

    # Empty string cursor clears
    check("extract empty cursor clears",
          tstr('{"cursor":"","feed":[]}') +
          [': _T TA XRPC-EXTRACT-CURSOR XRPC-HAS-CURSOR? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    # Zero-length input clears cursor
    check("extract zero-len input clears",
          [': _T S" prev" XRPC-SET-CURSOR',
           '0 0 XRPC-EXTRACT-CURSOR',
           'XRPC-HAS-CURSOR? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    # No cursor key in JSON clears
    check("extract no cursor key clears",
          tstr('{"feed":[],"count":5}') +
          [': _T S" prev" XRPC-SET-CURSOR',
           'TA XRPC-EXTRACT-CURSOR',
           'XRPC-HAS-CURSOR? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")


def test_xrpc_host_edge_cases():
    """Edge cases for host configuration."""
    print("\n── XRPC: Host Edge Cases ──\n")

    # Exactly 63 chars (max)
    host63 = "a" * 59 + ".com"
    check("host exactly 63 chars",
          tstr(host63) +
          [': _T TA XRPC-SET-HOST XRPC-HOST-LEN @ . ; _T'],
          "63 ")

    # 64 chars (rejected)
    host64 = "b" * 60 + ".com"
    check("host 64 chars rejected",
          tstr(host64) +
          [': _T _XRPC-DEFAULT-HOST TA XRPC-SET-HOST XRPC-HOST-LEN @ . ; _T'],
          "11 ")  # stays at "bsky.social" = 11

    # Single char host
    check("host single char",
          [': _T S" x" XRPC-SET-HOST XRPC-HOST-LEN @ .',
           'XRPC-HOST 1 TYPE ; _T'],
          check_fn=lambda out: "1" in out and "x" in out)

    # Reset back
    check("reset to default host",
          [': _T _XRPC-DEFAULT-HOST XRPC-HOST XRPC-HOST-LEN @ TYPE ; _T'],
          "bsky.social")


# ── Tests ──

if __name__ == '__main__':
    build_snapshot()

    # ================================================================
    print("\n── XRPC: Compilation ──\n")

    check("xrpc words exist",
          [': _T XRPC-HOST XRPC-HOST-LEN XRPC-CURSOR XRPC-CURSOR-LEN',
           '  DROP DROP DROP DROP ; _T'],
          "")

    check("xrpc-set-host exists",
          [': _T S" example.com" XRPC-SET-HOST ; _T'],
          "")

    check("cursor words exist",
          [': _T XRPC-CLEAR-CURSOR XRPC-HAS-CURSOR? DROP ; _T'],
          "")

    # ================================================================
    print("\n── XRPC: Host Configuration ──\n")

    check("default host is bsky.social",
          [': _T XRPC-HOST XRPC-HOST-LEN @ .S$ ; _T'],
          "bsky.social")

    check("set host",
          [': _T S" my.pds.example" XRPC-SET-HOST',
           '  XRPC-HOST XRPC-HOST-LEN @ .S$ ; _T'],
          "my.pds.example")

    check("set host length",
          [': _T S" tiny.pds" XRPC-SET-HOST',
           '  XRPC-HOST-LEN @ . ; _T'],
          "8 ")

    check("set host too long rejected",
          [': _T S" bsky.social" XRPC-SET-HOST',
           '  S" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" XRPC-SET-HOST',
           '  XRPC-HOST XRPC-HOST-LEN @ .S$ ; _T'],
          "bsky.social")

    # ================================================================
    print("\n── XRPC: URL Building ──\n")

    check("build url default host",
          [': _T S" bsky.social" XRPC-SET-HOST',
           '  S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           '  _XR-URL _XR-POS @ .S$ ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline")

    check("build url custom host",
          [': _T S" pds.example.com" XRPC-SET-HOST',
           '  S" com.atproto.repo.getRecord" _XRPC-BUILD-URL',
           '  _XR-URL _XR-POS @ .S$ ; _T'],
          "https://pds.example.com/xrpc/com.atproto.repo.getRecord")

    check("url with params",
          [': _T S" bsky.social" XRPC-SET-HOST',
           '  S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           '  S" limit=20" _XRPC-APPEND-PARAMS',
           '  _XR-URL _XR-POS @ .S$ ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=20")

    check("empty params skipped",
          [': _T S" bsky.social" XRPC-SET-HOST',
           '  S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           '  S" " _XRPC-APPEND-PARAMS',
           '  _XR-URL _XR-POS @ .S$ ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline")

    check("url position correct",
          [': _T S" bsky.social" XRPC-SET-HOST',
           '  S" test.nsid" _XRPC-BUILD-URL',
           '  _XR-POS @ . ; _T'],
          "34 ")   # https://bsky.social/xrpc/test.nsid = 34 chars

    # ================================================================
    print("\n── XRPC: Cursor Management ──\n")

    check("cursor initially clear",
          [': _T XRPC-CLEAR-CURSOR XRPC-HAS-CURSOR? . ; _T'],
          "0 ")

    check("set cursor then has",
          [': _T S" abc123cursor" XRPC-SET-CURSOR',
           '  XRPC-HAS-CURSOR? . ; _T'],
          "-1 ")

    check("read cursor value",
          [': _T S" abc123cursor" XRPC-SET-CURSOR',
           '  XRPC-CURSOR XRPC-CURSOR-LEN @ .S$ ; _T'],
          "abc123cursor")

    check("clear cursor",
          [': _T S" abc123cursor" XRPC-SET-CURSOR',
           '  XRPC-CLEAR-CURSOR',
           '  XRPC-HAS-CURSOR? . ; _T'],
          "0 ")

    check("cursor len after clear",
          [': _T S" some" XRPC-SET-CURSOR XRPC-CLEAR-CURSOR',
           '  XRPC-CURSOR-LEN @ . ; _T'],
          "0 ")

    check("cursor appended with ? (no params)",
          [': _T XRPC-CLEAR-CURSOR',
           '  S" bsky.social" XRPC-SET-HOST',
           '  S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           '  S" page2cursor" XRPC-SET-CURSOR',
           '  _XRPC-APPEND-CURSOR',
           '  _XR-URL _XR-POS @ .S$ ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline?cursor=page2cursor")

    check("cursor appended with & (params exist)",
          [': _T XRPC-CLEAR-CURSOR',
           '  S" bsky.social" XRPC-SET-HOST',
           '  S" app.bsky.feed.getTimeline" _XRPC-BUILD-URL',
           '  S" limit=20" _XRPC-APPEND-PARAMS',
           '  S" xyz789" XRPC-SET-CURSOR',
           '  _XRPC-APPEND-CURSOR',
           '  _XR-URL _XR-POS @ .S$ ; _T'],
          "https://bsky.social/xrpc/app.bsky.feed.getTimeline?limit=20&cursor=xyz789")

    check("no cursor = no append",
          [': _T XRPC-CLEAR-CURSOR',
           '  S" bsky.social" XRPC-SET-HOST',
           '  S" test.nsid" _XRPC-BUILD-URL',
           '  _XRPC-APPEND-CURSOR',
           '  _XR-URL _XR-POS @ .S$ ; _T'],
          "https://bsky.social/xrpc/test.nsid")

    # ================================================================
    print("\n── XRPC: Buffer Overflow Protection ──\n")

    # _XR-URL is 512 bytes.  _XR-APPEND drops whole chunk if it won't fit.
    # _XR-C! drops char when _XR-POS > 511.
    # These edge tests would have caught the pre-fix overflow that
    # corrupted _XR-POS and adjacent buffers like _HTTP-ACCEPT.

    # prefix: https:// (8) + bsky.social (11) + /xrpc/ (6) = 25
    # nsid=487 → total 512 — fills buffer exactly
    check("url fills exactly 512 bytes",
          tstr("X" * 487) +
          [': _T  S" bsky.social" XRPC-SET-HOST',
           '  TA _XRPC-BUILD-URL',
           '  _XR-POS @ . ; _T'],
          "512 ")

    # nsid=488 → total 513 — nsid chunk dropped (all-or-nothing)
    check("url at 513 — nsid dropped",
          tstr("X" * 488) +
          [': _T  S" bsky.social" XRPC-SET-HOST',
           '  TA _XRPC-BUILD-URL',
           '  _XR-POS @ . ; _T'],
          "25 ")

    # nsid=490 → _XR-POS must never exceed 512
    check("_XR-POS capped after overflow",
          tstr("N" * 490) +
          [': _T  S" bsky.social" XRPC-SET-HOST',
           '  TA _XRPC-BUILD-URL',
           '  _XR-POS @ 512 > IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    # _XR-C! at position 511 — last valid byte
    check("_XR-C! at pos 511 stores byte",
          [': _T  511 _XR-POS !',
           '  65 _XR-C!',
           '  _XR-POS @ . ; _T'],
          "512 ")

    # _XR-C! at position 512 — should be dropped
    check("_XR-C! at pos 512 dropped",
          [': _T  512 _XR-POS !',
           '  65 _XR-C!',
           '  _XR-POS @ . ; _T'],
          "512 ")

    # Long params: prefix=25, nsid "test.nsid"=9, pos=34
    # _XRPC-APPEND-PARAMS: '?' stored (pos=35), 480 chars → 35+480=515 > 512 → dropped
    check("overlong params dropped after ?",
          tstr("Q" * 480) +
          [': _T  S" bsky.social" XRPC-SET-HOST',
           '  S" test.nsid" _XRPC-BUILD-URL',
           '  TA _XRPC-APPEND-PARAMS',
           '  _XR-POS @ . ; _T'],
          "35 ")

    # Cursor near buffer limit: pos=500, cursor "abc"
    # ?cursor=abc = 1+7+3 = 11 chars → 500+11=511 ≤ 512 → fits
    check("cursor near limit fits",
          tstr("X" * 475) +
          [': _T  S" bsky.social" XRPC-SET-HOST',
           '  TA _XRPC-BUILD-URL',
           '  S" abc" XRPC-SET-CURSOR',
           '  _XRPC-APPEND-CURSOR',
           '  _XR-POS @ . ; _T'],
          "511 ")

    # Cursor when URL nearly full: pos=510
    # '?' stored (pos=511), "cursor=" (7) → 511+7=518 > 512 → dropped
    check("cursor dropped when URL nearly full",
          tstr("X" * 485) +
          [': _T  S" bsky.social" XRPC-SET-HOST',
           '  TA _XRPC-BUILD-URL',
           '  S" abc" XRPC-SET-CURSOR',
           '  _XRPC-APPEND-CURSOR',
           '  _XR-POS @ . ; _T'],
          "511 ")

    # Accept header survives after overflow attempt
    check("Accept survives overlength URL build",
          tstr("N" * 490) +
          [': _T  S" application/json" HTTP-SET-ACCEPT',
           '  S" bsky.social" XRPC-SET-HOST',
           '  TA _XRPC-BUILD-URL',
           '  _HTTP-ACCEPT _HTTP-ACCEPT-LEN @ .S$ ; _T'],
          "application/json")

    # Bearer survives after overflow attempt
    check("Bearer survives overlength URL build",
          tstr("N" * 490) +
          [': _T  S" tok_abc_123" HTTP-SET-BEARER',
           '  S" bsky.social" XRPC-SET-HOST',
           '  TA _XRPC-BUILD-URL',
           '  _HTTP-BEARER _HTTP-BEARER-LEN @ .S$ ; _T'],
          "tok_abc_123")

    # ================================================================
    print("\n── XRPC: Extract Cursor from JSON ──\n")

    # Build: {"feed":[],"cursor":"page2val"} using TC
    check("extract cursor from json",
          ['XRPC-CLEAR-CURSOR',
           ': _T TR',
           '  123 TC',                                   # {
           '  34 TC 102 TC 101 TC 101 TC 100 TC 34 TC',  # "feed"
           '  58 TC 91 TC 93 TC 44 TC',                  # :[],
           '  34 TC 99 TC 117 TC 114 TC 115 TC 111 TC 114 TC 34 TC',  # "cursor"
           '  58 TC',                                    # :
           '  34 TC 112 TC 97 TC 103 TC 101 TC 50 TC 118 TC 97 TC 108 TC 34 TC', # "page2val"
           '  125 TC',                                   # }
           '  TA XRPC-EXTRACT-CURSOR',
           '  XRPC-CURSOR XRPC-CURSOR-LEN @ .S$ ; _T'],
          "page2val")

    # Build: {"feed":[]} — no cursor key
    check("extract cursor clears when absent",
          [': _T S" page2val" XRPC-SET-CURSOR',
           '  TR 123 TC',                                # {
           '  34 TC 102 TC 101 TC 101 TC 100 TC 34 TC',  # "feed"
           '  58 TC 91 TC 93 TC',                        # :[]
           '  125 TC',                                   # }
           '  TA XRPC-EXTRACT-CURSOR',
           '  XRPC-HAS-CURSOR? . ; _T'],
          "0 ")

    # ================================================================
    print("\n── SESSION: Compilation ──\n")

    check("session words exist",
          [': _T SESS-ACTIVE? DROP SESS-DID 2DROP ; _T'],
          "")

    # ================================================================
    print("\n── SESSION: Initial State ──\n")

    check("session initially inactive",
          [': _T SESS-ACTIVE? . ; _T'],
          "0 ")

    check("session did len zero",
          [': _T SESS-DID NIP . ; _T'],
          "0 ")

    # ================================================================
    print("\n── SESSION: Login JSON ──\n")

    check("login json structure",
          [': _T S" alice.bsky.social" S" pass123"',
           '  _SES-PL ! _SES-PA !  _SES-HL ! _SES-HA !',
           '  _SES-JBUF 512 JSON-SET-OUTPUT',
           '  JSON-{',
           '    S" identifier" _SES-HA @ _SES-HL @ JSON-KV-STR',
           '    S" password"   _SES-PA @ _SES-PL @ JSON-KV-STR',
           '  JSON-}',
           '  JSON-OUTPUT-RESULT .S$ ; _T'],
          '{"identifier":"alice.bsky.social","password":"pass123"}')

    # ================================================================
    print("\n── SESSION: Refresh without login ──\n")

    check("refresh without login fails",
          [': _T SESS-REFRESH . ; _T'],
          "-1 ")

    # ================================================================
    print("\n── REPO: Compilation ──\n")

    check("repo words exist",
          [': _T _REP-J-RESET _REP-P-RESET',
           '  _REP-JP @ . _REP-PP @ . ; _T'],
          "0 0 ")

    # ================================================================
    print("\n── REPO: No-session guard ──\n")

    check("repo-get without session",
          [': _T S" at://did:plc:x/app.bsky.feed.post/abc" REPO-GET',
           '  . 2DROP ; _T'],
          "-1 ")

    check("repo-create without session",
          [': _T S" app.bsky.feed.post" S" {}" REPO-CREATE',
           '  . 2DROP ; _T'],
          "-1 ")

    check("repo-put without session",
          [': _T S" at://did:plc:x/coll/rk" S" {}" REPO-PUT . ; _T'],
          "-1 ")

    check("repo-delete without session",
          [': _T S" at://did:plc:x/coll/rk" REPO-DELETE . ; _T'],
          "-1 ")

    # ================================================================
    print("\n── REPO: JSON Concat Helpers ──\n")

    # Test _REP-J-QSTR: should produce "value"
    check("j-qstr emits quoted string",
          [': _T _REP-J-RESET',
           '  S" hello" _REP-J-QSTR',
           '  _REP-JBUF _REP-JP @ .S$ ; _T'],
          '"hello"')

    # Test _REP-J-KV: should produce ,"key":"value"
    check("j-kv emits key-value",
          [': _T _REP-J-RESET',
           '  S" name" S" alice" _REP-J-KV',
           '  _REP-JBUF _REP-JP @ .S$ ; _T'],
          ',"name":"alice"')

    # Test _REP-J-KRAW: should produce ,"key":<raw>
    check("j-kraw emits key-raw",
          [': _T _REP-J-RESET',
           '  S" record" S" 42" _REP-J-KRAW',
           '  _REP-JBUF _REP-JP @ .S$ ; _T'],
          ',"record":42')

    # Full JSON build: {"repo":"did:plc:test","collection":"myns"}
    check("full json concat",
          [': _T _REP-J-RESET',
           '  123 _REP-J-CH',
           '  34 _REP-J-CH S" repo" _REP-J-APPEND 34 _REP-J-CH',
           '  58 _REP-J-CH',
           '  S" did:plc:test" _REP-J-QSTR',
           '  S" collection" S" myns" _REP-J-KV',
           '  125 _REP-J-CH',
           '  _REP-JBUF _REP-JP @ .S$ ; _T'],
          '{"repo":"did:plc:test","collection":"myns"}')

    # JSON with raw record: ,"record":{"text":"hi"}
    check("json with raw record",
          [': _T _REP-J-RESET',
           '  123 _REP-J-CH',
           '  34 _REP-J-CH S" repo" _REP-J-APPEND 34 _REP-J-CH',
           '  58 _REP-J-CH',
           '  S" did:plc:x" _REP-J-QSTR',
           '  TR',                                       # build raw JSON in _TB
           '  123 TC',                                   # {
           '  34 TC 116 TC 34 TC',                       # "t"
           '  58 TC',                                    # :
           '  34 TC 104 TC 105 TC 34 TC',                # "hi"
           '  125 TC',                                   # }
           '  S" record" TA _REP-J-KRAW',
           '  125 _REP-J-CH',
           '  _REP-JBUF _REP-JP @ .S$ ; _T'],
          '{"repo":"did:plc:x","record":{"t":"hi"}}')

    # ================================================================
    print("\n── REPO: Query Params Building ──\n")

    check("get-record params",
          [': _T S" at://did:plc:abc/app.bsky.feed.post/rk1" ATURI-PARSE DROP',
           '  _REP-P-RESET',
           '  S" repo=" _REP-P-APPEND',
           '  ATURI-AUTHORITY ATURI-AUTH-LEN @ _REP-P-APPEND',
           '  S" &collection=" _REP-P-APPEND',
           '  ATURI-COLLECTION ATURI-COLL-LEN @ _REP-P-APPEND',
           '  S" &rkey=" _REP-P-APPEND',
           '  ATURI-RKEY ATURI-RKEY-LEN @ _REP-P-APPEND',
           '  _REP-PBUF _REP-PP @ .S$ ; _T'],
          "repo=did:plc:abc&collection=app.bsky.feed.post&rkey=rk1")

    check("get-record params no rkey",
          [': _T S" at://did:plc:abc/app.bsky.actor.profile" ATURI-PARSE DROP',
           '  _REP-P-RESET',
           '  S" repo=" _REP-P-APPEND',
           '  ATURI-AUTHORITY ATURI-AUTH-LEN @ _REP-P-APPEND',
           '  S" &collection=" _REP-P-APPEND',
           '  ATURI-COLLECTION ATURI-COLL-LEN @ _REP-P-APPEND',
           '  _REP-PBUF _REP-PP @ .S$ ; _T'],
          "repo=did:plc:abc&collection=app.bsky.actor.profile")

    # ── Call edge case test functions ──
    test_xrpc_accept_header()
    test_xrpc_url_edge_cases()
    test_xrpc_cursor_edge_cases()
    test_xrpc_extract_cursor_edge_cases()
    test_xrpc_host_edge_cases()

    # ================================================================
    print(f"\n{'='*60}")
    print(f"  {_pass} passed, {_fail} failed out of {_pass+_fail}")
    print(f"{'='*60}")
    sys.exit(1 if _fail else 0)
