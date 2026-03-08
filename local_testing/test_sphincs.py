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
"""Test suite for SPHINCS+-SHAKE-128s (akashic/math/sphincs-plus.f).

Tests individual components first (fast), then integration sign/verify.

Depends on: sha3.f random.f sphincs-plus.f
"""
import os, sys, time, hashlib

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR   = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))
EMU_DIR    = os.path.join(ROOT_DIR, "local_testing", "emu")

LIB_PATHS = [
    os.path.join(ROOT_DIR, "akashic", "concurrency", "event.f"),
    os.path.join(ROOT_DIR, "akashic", "concurrency", "semaphore.f"),
    os.path.join(ROOT_DIR, "akashic", "concurrency", "guard.f"),
    os.path.join(ROOT_DIR, "akashic", "math", "fp16.f"),
    os.path.join(ROOT_DIR, "akashic", "math", "sha3.f"),
    os.path.join(ROOT_DIR, "akashic", "math", "random.f"),
    os.path.join(ROOT_DIR, "akashic", "math", "sphincs-plus.f"),
]

sys.path.insert(0, EMU_DIR)
from asm import assemble
from system import MegapadSystem

BIOS_PATH = os.path.join(EMU_DIR, "bios.asm")
KDOS_PATH = os.path.join(EMU_DIR, "kdos.f")

# ── Emulator helpers ─────────────────────────────────────────────────

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
            if s.startswith('PROVIDED '):
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
    print("[*] Building snapshot: BIOS + KDOS + sha3 + random + sphincs-plus ...")
    t0 = time.time()
    bios_code  = _load_bios()
    kdos_lines = _load_forth_lines(KDOS_PATH)

    lib_lines = []
    for path in LIB_PATHS:
        if not os.path.isfile(path):
            print(f"  FATAL: missing {path}")
            sys.exit(1)
        lib_lines += _load_forth_lines(path)

    helpers = [
        'CREATE _TB 1024 ALLOT  VARIABLE _TL',
        ': TR  0 _TL ! ;',
        ': TC  ( c -- ) _TB _TL @ + C!  1 _TL +! ;',
        ': TA  ( -- addr u ) _TB _TL @ ;',
        ': _HEXNIB  DUP 10 < IF 48 + ELSE 87 + THEN EMIT ;',
        ': .HEX  ( addr n -- ) 0 ?DO DUP I + C@ DUP 4 RSHIFT _HEXNIB 15 AND _HEXNIB LOOP DROP ;',
        # Test buffers
        'CREATE _TSEED 48 ALLOT',
        'CREATE _TPK 32 ALLOT',
        'CREATE _TSK 64 ALLOT',
        'CREATE _TSIG 7856 ALLOT',
        'CREATE _TMSG 256 ALLOT',
        'CREATE _TBUF 1024 ALLOT',
    ]

    sys_obj = MegapadSystem(ram_size=1024*1024, ext_mem_size=16 * (1 << 20))
    buf = capture_uart(sys_obj)
    sys_obj.load_binary(0, bios_code)
    sys_obj.boot()

    all_lines = kdos_lines + ["ENTER-USERLAND"] + lib_lines + helpers
    payload = "\n".join(all_lines) + "\n"
    data = payload.encode(); pos = 0; steps = 0; mx = 2_000_000_000
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
    errors = []
    for l in text.strip().split('\n'):
        if '?' in l and 'not found' in l.lower():
            errors.append(l.strip())
            print(f"  [!] {l}")
    if errors:
        print(f"  [FATAL] {len(errors)} 'not found' errors during load!")
        print(f"  Aborting — sphincs-plus.f failed to compile cleanly.")
        sys.exit(1)
    _snapshot = (bios_code, bytes(sys_obj.cpu.mem), save_cpu_state(sys_obj.cpu),
                 bytes(sys_obj._ext_mem))
    print(f"[*] Snapshot ready.  {steps:,} steps in {time.time()-t0:.1f}s")
    return _snapshot


def run_forth(lines, max_steps=800_000_000):
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


# ── Test framework ───────────────────────────────────────────────────

_pass_count = 0
_fail_count = 0

import re
_HEX_RE = re.compile(r'[0-9a-f]+')

def _extract_hex(text, min_len=32):
    joined = ''.join(_HEX_RE.findall(text.lower()))
    if len(joined) >= min_len:
        return joined[:min_len]
    return None

def check(name, forth_lines, expected):
    global _pass_count, _fail_count
    output = run_forth(forth_lines)
    clean = output.strip()
    if expected in clean:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}")
        print(f"        expected: '{expected}'")
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")

def check_fn(name, forth_lines, predicate, desc="", max_steps=800_000_000):
    global _pass_count, _fail_count
    output = run_forth(forth_lines, max_steps=max_steps)
    clean = output.strip()
    try:
        ok = predicate(clean)
    except Exception as e:
        ok = False
        desc = f"{desc}; predicate raised {e}"
    if ok:
        _pass_count += 1
        print(f"  PASS  {name}")
    else:
        _fail_count += 1
        print(f"  FAIL  {name}" + (f" ({desc})" if desc else ""))
        for l in clean.split('\n')[-6:]:
            print(f"        got:      '{l}'")


# ── Python reference: SHAKE-256 ──────────────────────────────────────

def shake256(data, outlen):
    """SHAKE-256 of data, output outlen bytes."""
    return hashlib.shake_256(data).digest(outlen)


# ── Tests: Constants ─────────────────────────────────────────────────

def test_constants():
    print("\n=== Constants ===")
    check("T01 SPX-N=16",
          ['SPX-N . CR'], "16")
    check("T02 SPX-SIG-LEN=7856",
          ['SPX-SIG-LEN . CR'], "7856")
    check("T03 SPX-PK-LEN=32",
          ['SPX-PK-LEN . CR'], "32")
    check("T04 SPX-SK-LEN=64",
          ['SPX-SK-LEN . CR'], "64")


# ── Tests: Big-endian helpers ────────────────────────────────────────

def test_be_helpers():
    print("\n=== Big-Endian Helpers ===")
    # BE32!: store 0xDEADBEEF, read back all 4 bytes on one line
    check("T05 BE32!-roundtrip",
          ['0xDEADBEEF _TBUF _SPX-BE32!',
           '_TBUF C@ . _TBUF 1+ C@ . _TBUF 2 + C@ . _TBUF 3 + C@ . CR'],
          "222 173 190 239")

    # BE64!: store 0x0102030405060708
    check("T06 BE64!-roundtrip",
          ['0x0102030405060708 _TBUF _SPX-BE64!',
           '_TBUF C@ . _TBUF 7 + C@ . CR'],
          "1 8")

    # BE24@: read 3 bytes
    check("T07 BE24@",
          ['0xAB _TBUF C!  0xCD _TBUF 1+ C!  0xEF _TBUF 2 + C!',
           '_TBUF _SPX-BE24@ . CR'],
          str(0xABCDEF))

    # BE16@: read 2 bytes
    check("T08 BE16@",
          ['0x12 _TBUF C!  0x34 _TBUF 1+ C!',
           '_TBUF _SPX-BE16@ . CR'],
          str(0x1234))


# ── Tests: ADRS manipulation ────────────────────────────────────────

def test_adrs():
    print("\n=== ADRS Manipulation ===")
    # Set type, check byte 19 (type is at bytes 16-19 BE)
    check("T09 ADRS-TYPE!",
          ['_SPX-ADRS-ZERO',
           '3 _SPX-ADRS-TYPE!',
           '_SPX-ADRS 19 + C@ . CR'],
          "3")

    # Set layer, check byte 3
    check("T10 ADRS-LAYER!",
          ['_SPX-ADRS-ZERO',
           '5 _SPX-ADRS-LAYER!',
           '_SPX-ADRS 3 + C@ . CR'],
          "5")

    # Set kp, check byte 23
    check("T11 ADRS-KP!",
          ['_SPX-ADRS-ZERO',
           '42 _SPX-ADRS-KP!',
           '_SPX-ADRS 23 + C@ . CR'],
          "42")

    # Set chain, check byte 27
    check("T12 ADRS-CHAIN!",
          ['_SPX-ADRS-ZERO',
           '7 _SPX-ADRS-CHAIN!',
           '_SPX-ADRS 27 + C@ . CR'],
          "7")

    # Set hash, check byte 31
    check("T13 ADRS-HASH!",
          ['_SPX-ADRS-ZERO',
           '9 _SPX-ADRS-HASH!',
           '_SPX-ADRS 31 + C@ . CR'],
          "9")

    # Type! does NOT clear bytes 20-31
    check("T14 TYPE!-no-autoclear",
          ['_SPX-ADRS-ZERO',
           '42 _SPX-ADRS-KP!',
           '7 _SPX-ADRS-CHAIN!',
           '1 _SPX-ADRS-TYPE!',  # switch type
           '_SPX-ADRS 23 + C@ . _SPX-ADRS 27 + C@ . CR'],
          "42 7")


# ── Tests: base_w encoding ───────────────────────────────────────────

def test_base_w():
    print("\n=== base_w Encoding ===")
    # Encode byte 0xAB -> nibbles 0xA=10, 0xB=11
    check("T15 base_w-single-byte",
          ['0xAB _TBUF C!',
           '_TBUF 2 _SPX-BASE-W',
           '_SPX-WOTS-MSG C@ . _SPX-WOTS-MSG 1+ C@ . CR'],
          "10 11")

    # Encode 0x00 -> 0, 0
    check("T16 base_w-zero",
          ['0 _TBUF C!',
           '_TBUF 2 _SPX-BASE-W',
           '_SPX-WOTS-MSG C@ . _SPX-WOTS-MSG 1+ C@ . CR'],
          "0 0")

    # Encode 0xFF -> 15, 15
    check("T17 base_w-ff",
          ['0xFF _TBUF C!',
           '_TBUF 2 _SPX-BASE-W',
           '_SPX-WOTS-MSG C@ . _SPX-WOTS-MSG 1+ C@ . CR'],
          "15 15")


# ── Tests: WOTS+ checksum ───────────────────────────────────────────

def test_wots_checksum():
    print("\n=== WOTS+ Checksum ===")
    # All zeros -> checksum = 32*15 = 480, shifted left 4 = 7680 = 0x1E00
    # Nibbles: (7680>>8)&15=14, (7680>>4)&15=0, 7680&15=0
    check("T18 checksum-all-zeros",
          ['_TBUF 16 0 FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "14 0 0")

    # All 0xFF -> each nibble is 15, checksum = 32*0 = 0, shifted = 0
    check("T19 checksum-all-ff",
          ['_TBUF 16 0xFF FILL',
           '_TBUF _SPX-WOTS-ENCODE',
           '_SPX-WOTS-MSG 32 + C@ . _SPX-WOTS-MSG 33 + C@ . _SPX-WOTS-MSG 34 + C@ . CR'],
          "0 0 0")


# ── Tests: T_1 hash function ────────────────────────────────────────

def test_t1_hash():
    print("\n=== T_1 Hash ===")
    # Compute T_1(PK.seed, ADRS, input) in Forth and Python.
    # PK.seed = 16 bytes of 0x01, ADRS = all zeros, input = 16 bytes of 0x02
    pk_seed = b'\x01' * 16
    adrs    = b'\x00' * 32
    inp     = b'\x02' * 16
    expected = shake256(pk_seed + adrs + inp, 16).hex()

    check_fn("T20 T_1-hash-value",
        ['_TBUF 16 0x01 FILL',           # PK.seed
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 16 + 16 0x02 FILL',      # input
         '_TBUF 16 +  _TBUF 32 +  _SPX-T1',  # T1(in, dst)
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


# ── Tests: T_1! in-place ────────────────────────────────────────────

def test_t1_inplace():
    print("\n=== T_1! In-Place ===")
    pk_seed = b'\x01' * 16
    adrs    = b'\x00' * 32
    inp     = b'\x03' * 16
    expected = shake256(pk_seed + adrs + inp, 16).hex()

    check_fn("T21 T_1!-inplace",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 16 + 16 0x03 FILL',      # input in buf
         '_TBUF 16 + _SPX-T1!',          # in-place hash
         '_TBUF 16 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


# ── Tests: T_2 hash function ────────────────────────────────────────

def test_t2_hash():
    print("\n=== T_2 Hash ===")
    pk_seed = b'\x01' * 16
    adrs    = b'\x00' * 32
    left    = b'\x04' * 16
    right   = b'\x05' * 16
    expected = shake256(pk_seed + adrs + left + right, 16).hex()

    check_fn("T22 T_2-hash-value",
        ['_TBUF 16 0x01 FILL',           # PK.seed
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 16 + 16 0x04 FILL',      # left
         '_TBUF 32 + 16 0x05 FILL',      # right
         '_TBUF 48 + 16 0 FILL',         # clear dst
         '_TBUF 16 +  _TBUF 32 +  _TBUF 48 +  _SPX-T2',
         '_TBUF 48 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


# ── Tests: PRF function ─────────────────────────────────────────────

def test_prf():
    print("\n=== PRF ===")
    pk_seed = b'\x01' * 16
    sk_seed = b'\x06' * 16
    adrs    = b'\x00' * 32
    expected = shake256(pk_seed + adrs + sk_seed, 16).hex()

    check_fn("T23 PRF-value",
        ['_TBUF 16 0x01 FILL',           # PK.seed
         '_TBUF _SPX-PK-SEED !',
         '_TBUF 16 + 16 0x06 FILL',      # SK.seed
         '_TBUF 16 + _SPX-SK-SEED !',
         '_SPX-ADRS-ZERO',
         '_TBUF 32 + _SPX-PRF',
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")


# ── Tests: Chain function ────────────────────────────────────────────

def test_chain():
    print("\n=== WOTS+ Chain ===")
    # Test chain with 1 step: should be T_1 of input.
    # Chain(src, start=0, steps=1, dst) = T_1(input)
    # ADRS: type=WOTS_HASH(0), chain=0, hash set by chain to 0
    pk_seed = b'\x01' * 16
    adrs = bytearray(32)
    # After chain sets hash=0: ADRS is all zeros
    inp = b'\x07' * 16
    expected = shake256(pk_seed + bytes(adrs) + inp, 16).hex()

    check_fn("T24 chain-1-step",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '0 _SPX-ADRS-TYPE!',
         '0 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x07 FILL',      # src
         '_TBUF 16 +  0  1  _TBUF 32 + _SPX-CHAIN',  # chain 1 step
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected in out.strip().lower().replace(' ', ''),
        f"expected {expected}")

    # Chain with 0 steps: should be copy
    check_fn("T25 chain-0-steps",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '0 _SPX-ADRS-TYPE!',
         '0 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x08 FILL',
         '_TBUF 32 + 16 0 FILL',
         '_TBUF 16 +  0  0  _TBUF 32 + _SPX-CHAIN',
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: ('08' * 16) in out.strip().lower().replace(' ', ''),
        "expected 08*16 (copy)")

    # Chain with 2 steps: T_1(T_1(input)) with hash=0 then hash=1
    # step 0: ADRS.hash=0, T_1(input) → intermediate
    # step 1: ADRS.hash=1, T_1(intermediate) → result
    adrs0 = bytearray(32)
    intermediate = shake256(pk_seed + bytes(adrs0) + inp, 16)
    adrs1 = bytearray(32)
    adrs1[31] = 1  # hash index = 1
    expected2 = shake256(pk_seed + bytes(adrs1) + intermediate, 16).hex()

    check_fn("T26 chain-2-steps",
        ['_TBUF 16 0x01 FILL',
         '_TBUF _SPX-PK-SEED !',
         '_SPX-ADRS-ZERO',
         '0 _SPX-ADRS-TYPE!',
         '0 _SPX-ADRS-CHAIN!',
         '_TBUF 16 + 16 0x07 FILL',
         '_TBUF 16 +  0  2  _TBUF 32 + _SPX-CHAIN',
         '_TBUF 32 + 16 .HEX CR'],
        lambda out: expected2 in out.strip().lower().replace(' ', ''),
        f"expected {expected2}")


# ── Tests: Digest extraction ────────────────────────────────────────

def test_digest_extraction():
    print("\n=== Digest Extraction ===")
    # Fill _SPX-DIGEST with known pattern, extract FORS/tree/leaf indices.
    # We'll use a pattern where we know the bit layout.

    # Digest = 30 bytes, we set specific values.
    # FORS index extraction: 12-bit from big-endian starting at bit i*12.
    # For i=0: bits 0..11 from bytes 0..1 (top 12 bits of first 24 bits).
    # If byte[0]=0xAB (10101011), byte[1]=0xCD (11001101), byte[2]=0xEF
    # 24-bit val = 0xABCDEF, >> (12-0) = >> 12 = 0xABC, mask 0xFFF = 0xABC = 2748

    check("T27 FORS-IDX-0",
        ['0xAB _SPX-DIGEST C!',
         '0xCD _SPX-DIGEST 1+ C!',
         '0xEF _SPX-DIGEST 2 + C!',
         '0 _SPX-FORS-IDX . CR'],
        str(0xABC))

    # Leaf index: bytes 28-29, mask to 9 bits.
    # Set byte[28]=0x01, byte[29]=0xFF → 0x01FF = 511, mask 511 = 511
    check("T28 LEAF-IDX",
        ['_SPX-DIGEST 30 0 FILL',
         '0x01 _SPX-DIGEST 28 + C!',
         '0xFF _SPX-DIGEST 29 + C!',
         '_SPX-LEAF-IDX . CR'],
        "511")

    # Leaf index with overflow: byte[28]=0x02, byte[29]=0x03 -> 0x0203=515, mask 511 = 3
    check("T29 LEAF-IDX-mask",
        ['_SPX-DIGEST 30 0 FILL',
         '0x02 _SPX-DIGEST 28 + C!',
         '0x03 _SPX-DIGEST 29 + C!',
         '_SPX-LEAF-IDX . CR'],
        "3")


# ── Tests: Sign mode ─────────────────────────────────────────────────

def test_sign_mode():
    print("\n=== Sign Mode ===")
    check("T30 default-is-random",
          ['SPX-SIGN-MODE @ . CR'], "0")

    check("T31 set-deterministic",
          ['SPX-MODE-DETERMINISTIC SPX-SIGN-MODE !',
           'SPX-SIGN-MODE @ . CR',
           'SPX-MODE-RANDOM SPX-SIGN-MODE !'],  # restore
          "1")


# ── Tests: WOTS+ sign → pk_from_sig roundtrip ───────────────────────

def test_wots_roundtrip():
    """Sign a known hash, recover pk, verify the two pks match."""
    print("\n=== WOTS+ Roundtrip ===")
    # We generate WOTS+ pk directly, then sign, then recover pk from sig.
    # Both should match. Uses deterministic secrets via PRF.
    #
    # This is expensive (~35 chain iterations * 35 chains * 2 = ~2450 hash ops)
    # but still manageable in emulator.

    check_fn("T32 WOTS-sign-pk-roundtrip",
        [
            # Set up seeds
            '_TBUF 16 0x11 FILL',             # PK.seed
            '_TBUF _SPX-PK-SEED !',
            '_TBUF 16 + 16 0x22 FILL',        # SK.seed
            '_TBUF 16 + _SPX-SK-SEED !',
            # ADRS: layer=0, tree=0, kp=0
            '_SPX-ADRS-ZERO',
            '0 _SPX-ADRS-LAYER!',
            '0 _SPX-ADRS-TREE!',
            # Generate WOTS+ pk
            '0 _TBUF 32 + _SPX-WOTS-PK-GEN',   # pk → _TBUF+32 (16 bytes)
            # Now sign a test hash
            '_TBUF 48 + 16 0x33 FILL',          # msg hash = 0x33 * 16
            # Reset ADRS for sign
            '_SPX-ADRS-ZERO',
            '0 _SPX-ADRS-LAYER!',
            '0 _SPX-ADRS-TREE!',
            '0 _SPX-ADRS-KP!',
            '0 _SPX-ADRS-TYPE!',
            '_TBUF 48 + _TBUF 64 + _SPX-WOTS-SIGN',  # sig → _TBUF+64 (560 bytes)
            # Recover pk from sig
            '_SPX-ADRS-ZERO',
            '0 _SPX-ADRS-LAYER!',
            '0 _SPX-ADRS-TREE!',
            '0 _SPX-ADRS-KP!',
            '0 _SPX-ADRS-TYPE!',
            '_TBUF 48 + _TBUF 64 +  _TBUF 624 + _SPX-WOTS-PK-FROM-SIG',
            # Compare: _TBUF+32 (16 bytes) vs _TBUF+624 (16 bytes)
            '0',
            '16 0 DO',
            '  _TBUF 32 + I + C@ _TBUF 624 + I + C@ XOR OR',
            'LOOP',
            '0= IF .\" WOTS-MATCH\" ELSE .\" WOTS-MISMATCH\" THEN CR',
        ],
        lambda out: "WOTS-MATCH" in out,
        "WOTS pk should match",
        max_steps=2_000_000_000)


# ── Tests: Full keygen + sign + verify ───────────────────────────────

def test_full_roundtrip():
    """Full keygen → sign → verify roundtrip.
    WARNING: This is extremely slow in the emulator (~billions of steps).
    """
    print("\n=== Full Roundtrip (SLOW) ===")
    check_fn("T33 keygen-sign-verify",
        [
            # Use deterministic signing for reproducibility
            'SPX-MODE-DETERMINISTIC SPX-SIGN-MODE !',
            # Fill seed with known pattern
            '_TSEED 48 0 FILL',
            '48 0 DO I _TSEED I + C! LOOP',
            # Keygen
            '_TSEED _TPK _TSK SPX-KEYGEN',
            # Prepare message
            '_TMSG 32 0 FILL',
            '0xDE _TMSG C! 0xAD _TMSG 1+ C!',
            # Sign (msg, len, sec, sig)
            '_TMSG 2 _TSK _TSIG SPX-SIGN',
            # Verify (msg, len, pub, sig)
            '_TMSG 2 _TPK _TSIG SPX-VERIFY',
            'IF .\" SPX-VERIFY-OK\" ELSE .\" SPX-VERIFY-FAIL\" THEN CR',
        ],
        lambda out: "SPX-VERIFY-OK" in out,
        "sign/verify roundtrip",
        max_steps=50_000_000_000)  # 50B steps — this will be SLOW


def test_verify_rejects_bad_sig():
    """Verify rejects if a sig byte is flipped."""
    print("\n=== Verify Rejects Bad Sig ===")
    check_fn("T34 verify-reject-bad-sig",
        [
            'SPX-MODE-DETERMINISTIC SPX-SIGN-MODE !',
            '_TSEED 48 0 FILL',
            '48 0 DO I _TSEED I + C! LOOP',
            '_TSEED _TPK _TSK SPX-KEYGEN',
            '_TMSG 2 0 FILL  0xDE _TMSG C! 0xAD _TMSG 1+ C!',
            '_TMSG 2 _TSK _TSIG SPX-SIGN',
            # Flip one byte in signature
            '_TSIG 100 + C@ 255 XOR _TSIG 100 + C!',
            '_TMSG 2 _TPK _TSIG SPX-VERIFY',
            'IF .\" SPX-VERIFY-OK\" ELSE .\" SPX-VERIFY-FAIL\" THEN CR',
        ],
        lambda out: "SPX-VERIFY-FAIL" in out,
        "should reject flipped sig",
        max_steps=50_000_000_000)


# ── Main ─────────────────────────────────────────────────────────────

if __name__ == '__main__':
    t0 = time.time()
    build_snapshot()

    # Fast component tests
    test_constants()
    test_be_helpers()
    test_adrs()
    test_base_w()
    test_wots_checksum()
    test_t1_hash()
    test_t1_inplace()
    test_t2_hash()
    test_prf()
    test_chain()
    test_digest_extraction()
    test_sign_mode()

    # Medium tests
    test_wots_roundtrip()

    # Slow integration tests (only run if --full flag)
    if '--full' in sys.argv:
        test_full_roundtrip()
        test_verify_rejects_bad_sig()
    else:
        print("\n  [SKIP] Full roundtrip tests (use --full to enable)")

    elapsed = time.time() - t0
    print(f"\n{'='*60}")
    print(f"  {_pass_count} passed, {_fail_count} failed   ({elapsed:.1f}s)")
    print(f"{'='*60}")
    sys.exit(1 if _fail_count else 0)
