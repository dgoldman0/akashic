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
"""Test suite for akashic-websocket Forth library (ws.f).

Tests layers that don't require actual network:
  SHA-1       — Known test vectors (RFC 3174)
  Error       — WS-ERR, WS-FAIL, WS-OK?, WS-CLEAR-ERR, constants
  Opcodes     — WS-OP-* constant values
  State       — WS-AUTO-PONG default
  Masking     — _WS-MASK XOR masking
  Key gen     — _WS-MAKE-KEY Base64 output length
  Validate    — _WS-VALIDATE accept-header check
  Big-endian  — _SHA1-BE@ / _SHA1-BE!
"""
import os, sys, time, hashlib, base64

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

# Forth source files (new structure)
STR_F  = os.path.join(ROOT_DIR, "akashic", "utils", "string.f")
URL_F  = os.path.join(ROOT_DIR, "akashic", "net", "url.f")
HDR_F  = os.path.join(ROOT_DIR, "akashic", "net", "headers.f")
B64_F  = os.path.join(ROOT_DIR, "akashic", "net", "base64.f")
HTTP_F = os.path.join(ROOT_DIR, "akashic", "net", "http.f")
WS_F   = os.path.join(ROOT_DIR, "akashic", "net", "ws.f")
EVENT_F = os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f")
SEM_F   = os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f")
GUARD_F = os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f")

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
    print("[*] Building snapshot: BIOS + KDOS + string.f + url.f + headers.f + base64.f + http.f + ws.f ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)
    event_lines = _load_forth_lines(EVENT_F)
    sem_lines   = _load_forth_lines(SEM_F)
    guard_lines = _load_forth_lines(GUARD_F)
    str_lines  = _load_forth_lines(STR_F)
    url_lines  = _load_forth_lines(URL_F)
    hdr_lines  = _load_forth_lines(HDR_F)
    b64_lines  = _load_forth_lines(B64_F)
    http_lines = _load_forth_lines(HTTP_F)
    ws_lines   = _load_forth_lines(WS_F)

    helpers = [
        'CREATE _TB 512 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        'CREATE _OB 512 ALLOT',
        'CREATE _SB 64 ALLOT',       # scratch buffer for SHA tests
        # Simple hex byte emitter (avoids <# # #> issues)
        ': .HX1 ( n -- ) DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;',
        ': .HX ( n -- ) DUP 4 RSHIFT 15 AND .HX1 15 AND .HX1 ;',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = (kdos_lines + ["ENTER-USERLAND"]
                 + event_lines + sem_lines + guard_lines
                 + str_lines + url_lines + hdr_lines + b64_lines
                 + http_lines + ws_lines + helpers)
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 600_000_000

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
    elapsed = time.time() - t0
    print(f"[*] Snapshot ready.  {steps:,} steps in {elapsed:.1f}s")
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


# ── Test framework ──

_pass = 0; _fail = 0

def check(name, forth_lines, expected=None, check_fn=None):
    global _pass, _fail
    output = run_forth(forth_lines)
    clean = output.strip()
    ok = check_fn(clean) if check_fn else (expected in clean if expected else True)
    if ok:
        _pass += 1; print(f"  PASS  {name}")
    else:
        _fail += 1; print(f"  FAIL  {name}")
        if expected: print(f"        expected: {expected!r}")
        print(f"        got (last lines): {clean.split(chr(10))[-3:]}")


# =====================================================================
#  Tests
# =====================================================================

def test_error_handling():
    print("\n── Error Handling ──\n")

    check("WS-OK? initially true",
          [': _T WS-CLEAR-ERR WS-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")

    check("WS-FAIL sets error",
          [': _T 3 WS-FAIL WS-ERR @ . ; _T'],
          "3 ")

    check("WS-OK? false after FAIL",
          [': _T 1 WS-FAIL WS-OK? IF 1 ELSE 0 THEN . ; _T'],
          "0 ")

    check("WS-CLEAR-ERR resets",
          [': _T 5 WS-FAIL WS-CLEAR-ERR WS-OK? IF 1 ELSE 0 THEN . ; _T'],
          "1 ")


def test_error_constants():
    print("\n── Error Constants ──\n")

    check("WS-E-CONNECT = 1",
          [': _T WS-E-CONNECT . ; _T'], "1 ")
    check("WS-E-HANDSHAKE = 2",
          [': _T WS-E-HANDSHAKE . ; _T'], "2 ")
    check("WS-E-OVERFLOW = 3",
          [': _T WS-E-OVERFLOW . ; _T'], "3 ")
    check("WS-E-FRAME = 4",
          [': _T WS-E-FRAME . ; _T'], "4 ")
    check("WS-E-CLOSED = 5",
          [': _T WS-E-CLOSED . ; _T'], "5 ")
    check("WS-E-PROTOCOL = 6",
          [': _T WS-E-PROTOCOL . ; _T'], "6 ")


def test_opcodes():
    print("\n── Opcode Constants ──\n")

    check("WS-OP-CONT = 0",
          [': _T WS-OP-CONT . ; _T'], "0 ")
    check("WS-OP-TEXT = 1",
          [': _T WS-OP-TEXT . ; _T'], "1 ")
    check("WS-OP-BINARY = 2",
          [': _T WS-OP-BINARY . ; _T'], "2 ")
    check("WS-OP-CLOSE = 8",
          [': _T WS-OP-CLOSE . ; _T'], "8 ")
    check("WS-OP-PING = 9",
          [': _T WS-OP-PING . ; _T'], "9 ")
    check("WS-OP-PONG = 10",
          [': _T WS-OP-PONG . ; _T'], "10 ")


def test_state_defaults():
    print("\n── State Defaults ──\n")

    check("WS-AUTO-PONG default is -1",
          [': _T WS-AUTO-PONG @ . ; _T'], "-1 ")

    check("_WS-OPEN default is 0",
          [': _T _WS-OPEN @ . ; _T'], "0 ")


def test_sha1_be():
    print("\n── SHA-1 Big-Endian Helpers ──\n")

    # Store 0xDEADBEEF and read it back
    check("_SHA1-BE! / _SHA1-BE@ roundtrip",
          [': _T 3735928559 _SB _SHA1-BE! _SB _SHA1-BE@ . ; _T'],
          "3735928559 ")

    # Check byte order: 0x01020304
    check("_SHA1-BE! byte order",
          [': _T 16909060 _SB _SHA1-BE!',
           '_SB     C@ .',   # 0x01 = 1
           '_SB 1 + C@ .',   # 0x02 = 2
           '_SB 2 + C@ .',   # 0x03 = 3
           '_SB 3 + C@ .',   # 0x04 = 4
           '; _T'],
          "1 2 3 4 ")


def test_sha1():
    """Test SHA-1 against known vectors (RFC 3174 + FIPS 180-1)."""
    print("\n── SHA-1 ──\n")

    # Vector 1: SHA1("") = da39a3ee5e6b4b0d3255bfef95601890afd80709
    check("SHA1 empty string",
          [': _T _SB 0 _OB SHA1',
           '20 0 DO _OB I + C@ .HX LOOP',
           '; _T'],
          check_fn=lambda out: "da39a3ee5e6b4b0d3255bfef95601890afd80709" in out.lower().replace(' ', ''))

    # Vector 2: SHA1("abc") = a9993e364706816aba3e25717850c26c9cd0d89d
    check("SHA1 'abc'",
          tstr("abc") +
          [': _T TA _OB SHA1',
           '20 0 DO _OB I + C@ .HX LOOP',
           '; _T'],
          check_fn=lambda out: "a9993e364706816aba3e25717850c26c9cd0d89d" in out.lower().replace(' ', ''))

    # Vector 3: SHA1("Hello") = f7ff9e8b7bb2e09b70935a5d785e0cc5d9d0abf0
    check("SHA1 'Hello'",
          tstr("Hello") +
          [': _T TA _OB SHA1',
           '20 0 DO _OB I + C@ .HX LOOP',
           '; _T'],
          check_fn=lambda out: "f7ff9e8b7bb2e09b70935a5d785e0cc5d9d0abf0" in out.lower().replace(' ', ''))

    # Vector 4: SHA1("The quick brown fox jumps over the lazy dog")
    #         = 2fd4e1c67a2d28fced849ee1bb76e7391b93eb12
    check("SHA1 'The quick brown fox...'",
          tstr("The quick brown fox jumps over the lazy dog") +
          [': _T TA _OB SHA1',
           '20 0 DO _OB I + C@ .HX LOOP',
           '; _T'],
          check_fn=lambda out: "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12" in out.lower().replace(' ', ''))


def test_sha1_websocket_accept():
    """Test the SHA1+Base64 flow used for Sec-WebSocket-Accept."""
    print("\n── SHA-1 WebSocket Accept ──\n")

    # RFC 6455 §4.2.2 example:
    #   Key: "dGhlIHNhbXBsZSBub25jZQ=="
    #   Key + GUID: "dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    #   SHA-1: 0xb3 7a 4f 2c c0 62 4f 16 90 f6 46 06 cf 38 59 45 b2 be c4 ea
    #   Base64: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

    # Test full SHA1 of the concatenated key+GUID
    key_guid = "dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    check("SHA1(key+GUID) for RFC 6455 example",
          tstr(key_guid) +
          [': _T TA _OB SHA1',
           '20 0 DO _OB I + C@ .HX LOOP',
           '; _T'],
          check_fn=lambda out: "b37a4f2cc0624f1690f64606cf385945b2bec4ea" in out.lower().replace(' ', ''))

    # Test SHA1 → Base64 (the full accept value pipeline)
    check("Base64(SHA1(key+GUID)) = expected accept",
          tstr(key_guid) +
          [': _T',
           'TA _SB SHA1',
           '_SB 20 _OB 32 B64-ENCODE',
           '_OB SWAP TYPE',
           '; _T'],
          "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")


def test_mask():
    print("\n── _WS-MASK ──\n")

    # XOR mask with key 0x37FA213D (bytes: 0x37 0xFA 0x21 0x3D)
    # Data: "Hello" = 0x48 0x65 0x6C 0x6C 0x6F
    # Masked: 0x48^0x37=0x7F  0x65^0xFA=0x9F  0x6C^0x21=0x4D
    #         0x6C^0x3D=0x51  0x6F^0x37=0x58
    check("_WS-MASK basic XOR",
          tstr("Hello") +
          [': _T',
           'TA 939139389 _WS-MASK',    # 0x37FA213D = 939139389
           '_TB 5 0 DO DUP I + C@ . LOOP DROP',
           '; _T'],
          "127 159 77 81 88 ")

    # Double-mask is identity (XOR is involution)
    check("_WS-MASK double-apply = identity",
          tstr("Test!!") +
          [': _T',
           'TA 305419896 _WS-MASK',    # mask once
           'TA 305419896 _WS-MASK',    # mask again
           'TA TYPE',
           '; _T'],
          "Test!!")

    # Zero mask = no change
    check("_WS-MASK zero key = identity",
          tstr("ABCD") +
          [': _T',
           'TA 0 _WS-MASK',
           'TA TYPE',
           '; _T'],
          "ABCD")


def test_make_key():
    print("\n── _WS-MAKE-KEY ──\n")

    # Key should be 24 characters (16 bytes → Base64 = 24 chars including padding)
    check("_WS-MAKE-KEY length = 24",
          [': _T _WS-MAKE-KEY . DROP ; _T'],
          "24 ")

    # Two consecutive keys should differ (probabilistic but virtually certain)
    check("_WS-MAKE-KEY produces different keys",
          [': _T',
           '_WS-MAKE-KEY',
           # Save first key to _TB
           '2DUP _TB SWAP CMOVE',
           'DROP _TL !',
           # Generate second key
           '_WS-MAKE-KEY',
           # Compare
           '_TB _TL @ STR-STR= IF 0 ELSE 1 THEN .',
           '; _T'],
          "1 ")

    # Key should be valid Base64 (all chars in alphabet)
    check("_WS-MAKE-KEY is valid Base64",
          [': _T',
           '_WS-MAKE-KEY',
           '1',  # flag: all valid so far
           'SWAP 0 DO',
           '  OVER I + C@',
           '  DUP 65 >= OVER 90 <= AND IF DROP ELSE',  # A-Z
           '  DUP 97 >= OVER 122 <= AND IF DROP ELSE',  # a-z
           '  DUP 48 >= OVER 57 <= AND IF DROP ELSE',   # 0-9
           '  DUP 43 = IF DROP ELSE',                    # +
           '  DUP 47 = IF DROP ELSE',                    # /
           '  DUP 61 = IF DROP ELSE',                    # =
           '  DROP DROP 0 SWAP LEAVE',
           '  THEN THEN THEN THEN THEN THEN',
           'LOOP',
           'NIP . ; _T'],
          "1 ")


def test_validate():
    """Test _WS-VALIDATE using the RFC 6455 example."""
    print("\n── _WS-VALIDATE ──\n")

    # RFC 6455 §4.2.2 example:
    #   Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
    #   Expected Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
    #
    # We need to simulate a response header containing the Accept value,
    # then call _WS-VALIDATE with the key.
    #
    # _WS-VALIDATE expects: ( hdr-a hdr-u key-a key-u -- flag )
    # It will:
    #   1. Concatenate key + GUID
    #   2. SHA-1 hash
    #   3. Base64 encode
    #   4. HDR-FIND "Sec-WebSocket-Accept" in response
    #   5. Compare

    # Build a mock response header in _TB
    resp_hdr = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"

    check("_WS-VALIDATE with RFC 6455 example (valid)",
          tstr(resp_hdr) +
          [': _T',
           # Set _WS-KEY-LEN to 24 (length of the key)
           '24 _WS-KEY-LEN !',
           'TA',                       # ( hdr-a hdr-u )
           'S" dGhlIHNhbXBsZSBub25jZQ=="',  # ( hdr-a hdr-u key-a key-u )
           '_WS-VALIDATE . ; _T'],
          "-1 ")

    # Wrong accept value
    bad_hdr = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: WRONG_VALUE_HERE\r\n\r\n"

    check("_WS-VALIDATE with wrong accept (invalid)",
          tstr(bad_hdr) +
          [': _T',
           '24 _WS-KEY-LEN !',
           'TA',
           'S" dGhlIHNhbXBsZSBub25jZQ=="',
           '_WS-VALIDATE . ; _T'],
          "0 ")


def test_buffer_size():
    """[FIX D08] _WS-RBUF raised from 4096 to 16384."""
    print("\n── Buffer Size (D08) ──\n")

    # Write 0xAB at the last byte (offset 16383) and read it back
    check("_WS-RBUF last byte at offset 16383",
          [': _T 171 _WS-RBUF 16383 + C!  _WS-RBUF 16383 + C@ . ; _T'],
          "171 ")

    # _WS-RBUF-LEN should default to 0
    check("_WS-RBUF-LEN initially 0",
          [': _T _WS-RBUF-LEN @ . ; _T'],
          "0 ")


def test_sha1_rotl():
    print("\n── SHA-1 Rotate Left ──\n")

    # ROTL(1, 1) = 2
    check("ROTL 1 by 1 = 2",
          [': _T 1 1 _SHA1-ROTL . ; _T'],
          "2 ")

    # ROTL(0x80000000, 1) = 1  (bit wraps around)
    check("ROTL 0x80000000 by 1 = 1",
          [': _T 2147483648 1 _SHA1-ROTL . ; _T'],
          "1 ")

    # ROTL(0x12345678, 4) = 0x23456781
    check("ROTL 0x12345678 by 4",
          [': _T 305419896 4 _SHA1-ROTL . ; _T'],
          "591751041 ")


# =====================================================================
#  Main
# =====================================================================

if __name__ == "__main__":
    build_snapshot()

    test_error_handling()
    test_error_constants()
    test_opcodes()
    test_state_defaults()
    test_buffer_size()
    test_sha1_rotl()
    test_sha1_be()
    test_sha1()
    test_sha1_websocket_accept()
    test_mask()
    test_make_key()
    test_validate()

    print(f"\n{'='*40}")
    print(f"  {_pass} passed, {_fail} failed")
    print(f"{'='*40}")
    sys.exit(1 if _fail else 0)
